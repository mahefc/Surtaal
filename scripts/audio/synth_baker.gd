class_name SynthBaker
extends RefCounted
## Original synthesis engines. Renders one note to a 16-bit mono AudioStreamWAV.
## Pure/static and thread-safe (local RNG only), so it can run on WorkerThreadPool.
##
## Engines:
##   pluck     - Karplus-Strong string with fractional-delay tuning and optional
##               bridge-buzz waveshaping (sitar jawari, tanpura jivari).
##   wavetable - single-cycle additive table with ADSR, vibrato, pitch scoop,
##               breath noise, detuned second oscillator and bright->dark morph.
##   membrane  - pitched drum: pitch-dropping sine, inharmonic partials, noise burst.

const RATE := 44100
const TABLE_SIZE := 2048
const TABLE_MASK := 2047


static func midi_to_freq(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


const TARGET_RMS := 0.17     # loudness target (about -15 dBFS) for every rendered note
const LOOP_BODY_SEC := 0.5   # length of the sustain loop
const LOOP_XFADE_SEC := 0.12 # crossfade that hides the loop seam
const MAX_PLAYER_DB := 48.0  # most make-up gain a recording may get (see _bake_sampler)


## Renders one note. Sustaining wavetable instruments get a seamless loop
## (attack/decay pre-roll + crossfaded sustain body); the engine handles
## vibrato and release at runtime.
static func bake(def: InstrumentDef, midi: int, preset: int = 0, layer: int = 0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.id) + midi * 7919
	# Multi-sample zones: only every `zone`-th note is rendered; the engine
	# repitches neighbours by up to +-zone/2 semitones (def.zone_root()).
	midi = def.zone_root(midi, layer)
	rng.seed = hash(def.id) + midi * 7919
	var f := midi_to_freq(midi)
	var p := def.params_for(preset)
	var loop := def.is_loopable(preset)
	match def.synth:
		"pluck":
			return _finish([_pluck(p, f, rng)])
		"wavetable", "super":
			if loop:
				return _bake_loop(def.synth, p, f, rng)
			return _finish(_render(def.synth, p, f, rng))
		"membrane":
			return _finish([_membrane(p, f, rng)])
		"sampler":
			return _bake_sampler(p, midi, layer)
	push_error("SynthBaker: unknown synth '%s' for %s" % [def.synth, def.id])
	return null


## Render one channel set ([mono] or [left, right]) for a sustained engine.
static func _render(kind: String, p: Dictionary, f: float, rng: RandomNumberGenerator) -> Array:
	if kind == "super":
		return _super(p, f, rng)
	return [_wavetable(p, f, rng)]


static func _bake_loop(kind: String, p: Dictionary, f: float, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var pre := clampf(float(p.get("attack", 0.02)) + 4.0 * float(p.get("decay", 0.3)), 0.3, 1.5)
	var q := p.duplicate()
	q["dur"] = pre + LOOP_BODY_SEC + LOOP_XFADE_SEC
	q["vib_depth"] = 0.0  # vibrato is applied live by the engine
	q["no_release"] = true
	var chans := _render(kind, q, f, rng)
	var s_i := int(pre * RATE)
	var l_i := int(LOOP_BODY_SEC * RATE)
	for buf: PackedFloat32Array in chans:
		var x_i := mini(int(LOOP_XFADE_SEC * RATE), buf.size() - s_i - l_i)
		# Blend the head of the loop with the signal that continues past its end,
		# so wrapping end -> start is continuous.
		for j in x_i:
			var w := float(j) / x_i
			buf[s_i + j] = buf[s_i + j] * w + buf[s_i + l_i + j] * (1.0 - w)
		buf.resize(s_i + l_i)
	var s := _finish(chans, false)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = s_i
	s.loop_end = s_i + l_i
	return s


# ---------------------------------------------------------------- super
## Cinematic subtractive engine: layered unison oscillators spread across the stereo
## field, sub oscillator, resonant low-pass with its own envelope, soft saturation.
##   voices/detune/spread - unison count, detune width (fraction), stereo spread 0..1
##   stack               - [[freq_ratio, amp], ...] octave/fifth layers (braam = [1,.8],[0.5,1])
##   osc/harmonics       - "saw" | "square" or an explicit harmonic list (organ, reed)
##   formants            - [[Hz, amp, bandwidth], ...] vowel shaping (choir "aah")
##   cutoff/cutoff_env/cutoff_decay/cutoff_track/resonance - filter
##   drive, sub, noise   - saturation, sub-octave sine, breath/bow noise
static func _super(p: Dictionary, f: float, rng: RandomNumberGenerator) -> Array:
	var dur: float = p.get("dur", 2.0)
	var atk: float = maxf(p.get("attack", 0.02), 0.001)
	var dec: float = maxf(p.get("decay", 0.3), 0.001)
	var sus: float = p.get("sustain", 0.8)
	var rel: float = maxf(p.get("release", 0.3), 0.005)
	var no_release: bool = p.get("no_release", false)
	var voices: int = maxi(1, int(p.get("voices", 5)))
	var detune: float = p.get("detune", 0.01)
	var spread: float = p.get("spread", 0.8)
	var sub: float = p.get("sub", 0.0)
	var cutoff: float = p.get("cutoff", 8000.0)
	var fenv: float = p.get("cutoff_env", 0.0)
	var fdec: float = maxf(p.get("cutoff_decay", 0.3), 0.01)
	var ftrack: float = p.get("cutoff_track", 0.0)
	var q: float = maxf(1.0 - float(p.get("resonance", 0.15)), 0.5)
	var drive: float = p.get("drive", 0.0)
	var noise: float = p.get("noise", 0.0)
	var vib_hz: float = p.get("vib_hz", 0.0)
	var vib_depth: float = p.get("vib_depth", 0.0)
	var vib_delay: float = p.get("vib_delay", 0.0)
	var stack: Array = p.get("stack", [[1.0, 1.0]])
	# Dark/low-passed instruments render at half rate (2x cheaper) and are interpolated up.
	var half: bool = p.get("half_rate", false)
	var sr: float = RATE * 0.5 if half else float(RATE)

	var max_ratio := 1.0
	for layer in stack:
		max_ratio = maxf(max_ratio, float(layer[0]))
	var tab := _super_table(p, f * max_ratio, sr)
	var sine := _make_table([1.0], f)

	var total := voices * stack.size()
	var ph := PackedFloat32Array()
	var inc := PackedFloat32Array()
	var gl := PackedFloat32Array()
	var gr := PackedFloat32Array()
	ph.resize(total)
	inc.resize(total)
	gl.resize(total)
	gr.resize(total)
	var k := 0
	for layer in stack:
		for v in voices:
			var pos := 0.0 if voices == 1 else (float(v) / (voices - 1) - 0.5) * 2.0
			pos += rng.randf_range(-0.08, 0.08)
			inc[k] = f * float(layer[0]) * (1.0 + detune * pos) * TABLE_SIZE / sr
			ph[k] = rng.randf() * TABLE_SIZE
			var pan := clampf(pos * spread, -1.0, 1.0)
			var amp := float(layer[1]) / sqrt(float(total))
			gl[k] = amp * cos((pan + 1.0) * PI / 4.0)
			gr[k] = amp * sin((pan + 1.0) * PI / 4.0)
			k += 1

	var n := int(dur * sr)
	var out_l := PackedFloat32Array()
	var out_r := PackedFloat32Array()
	out_l.resize(n)
	out_r.resize(n)
	var sub_inc := f * 0.5 * TABLE_SIZE / sr
	var sub_ph := 0.0
	var low_l := 0.0
	var band_l := 0.0
	var low_r := 0.0
	var band_r := 0.0
	var ff := 0.9
	var nz := 0.0
	var g_drive := 1.0 + drive * 4.0
	for i in n:
		var t := float(i) / sr
		var e: float
		if t < atk:
			e = t / atk
		else:
			e = sus + (1.0 - sus) * exp(-(t - atk) / dec)
		if t > dur - rel and not no_release:
			e *= maxf(0.0, (dur - t) / rel)

		var fc := cutoff + fenv * exp(-t / fdec) + ftrack * f
		if (i & 7) == 0:  # filter coefficient changes slowly: update every 8 samples
			# The filter runs twice per sample (2x oversampled), which keeps the
			# Chamberlin structure stable up to ~0.28 x sample rate (important at half rate).
			ff = 2.0 * sin(PI * minf(fc, sr * 0.28) / (2.0 * sr))
		var bend := 1.0
		if vib_depth > 0.0 and t > vib_delay:
			bend += vib_depth * minf(1.0, (t - vib_delay) * 2.0) * sin(TAU * vib_hz * t)

		var l := 0.0
		var r := 0.0
		for j in total:
			var pp := ph[j] + inc[j] * bend
			if pp >= TABLE_SIZE:
				pp -= TABLE_SIZE
			ph[j] = pp
			var ii := int(pp)
			var a := tab[ii]
			var s := a + (tab[(ii + 1) & TABLE_MASK] - a) * (pp - ii)
			l += s * gl[j]
			r += s * gr[j]
		if sub > 0.0:
			sub_ph += sub_inc
			if sub_ph >= TABLE_SIZE:
				sub_ph -= TABLE_SIZE
			var ssi := int(sub_ph)
			var sv := sine[ssi] + (sine[(ssi + 1) & TABLE_MASK] - sine[ssi]) * (sub_ph - ssi)
			l += sv * sub
			r += sv * sub
		if noise > 0.0:
			nz += (rng.randf_range(-1.0, 1.0) - nz) * 0.3
			l += nz * noise
			r += nz * noise * 0.9

		if fc < sr * 0.28:  # Chamberlin state-variable low-pass, 2 sub-steps per sample
			for _k in 2:
				low_l += ff * band_l
				band_l += ff * (l - low_l - q * band_l)
				low_r += ff * band_r
				band_r += ff * (r - low_r - q * band_r)
			l = low_l
			r = low_r
		if drive > 0.0:  # soft saturation: weight + harmonics that survive small speakers
			l *= g_drive
			r *= g_drive
			l = l / (1.0 + absf(l))
			r = r / (1.0 + absf(r))
		out_l[i] = l * e
		out_r[i] = r * e
	if half:
		return [_upsample2(out_l), _upsample2(out_r)]
	return [out_l, out_r]


static func _upsample2(x: PackedFloat32Array) -> PackedFloat32Array:
	var n := x.size()
	var y := PackedFloat32Array()
	y.resize(n * 2)
	for i in n - 1:
		y[2 * i] = x[i]
		y[2 * i + 1] = 0.5 * (x[i] + x[i + 1])
	y[2 * n - 2] = x[n - 1]
	y[2 * n - 1] = x[n - 1]
	return y


## Band-limited single-cycle table: saw/square/custom harmonics, optionally formant-shaped.
static func _super_table(p: Dictionary, f_top: float, sr: float = RATE) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(TABLE_SIZE)
	var kind: String = p.get("osc", "saw")
	var custom: Array = p.get("harmonics", [])
	var formants: Array = p.get("formants", [])
	var base_f: float = p.get("_f0", f_top)
	var max_h := int(sr * 0.45 / maxf(f_top, 1.0))
	if not custom.is_empty():
		max_h = mini(max_h, custom.size())
	max_h = clampi(max_h, 1, 96)
	for h in range(1, max_h + 1):
		var amp: float
		if not custom.is_empty():
			amp = float(custom[h - 1])
		elif kind == "square":
			amp = 1.0 / h if h % 2 == 1 else 0.0
		else:
			amp = 1.0 / h
		if not formants.is_empty():
			var w := 0.04
			for fm in formants:
				var d := (h * f_top - float(fm[0])) / float(fm[2])
				w += float(fm[1]) * exp(-d * d)
			amp *= w
		if amp == 0.0:
			continue
		for i in TABLE_SIZE:
			t[i] += amp * sin(TAU * h * i / TABLE_SIZE)
	var peak := 0.0001
	for v in t:
		peak = maxf(peak, absf(v))
	for i in TABLE_SIZE:
		t[i] /= peak
	return t


# ---------------------------------------------------------------- pluck
static func _pluck(p: Dictionary, f: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = p.get("dur", 2.0)
	var damp: float = p.get("damp", 0.997)
	var bright: float = p.get("bright", 0.5)
	var buzz: float = p.get("buzz", 0.0)
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)

	var period := RATE / f - 0.5  # the 2-point average adds half a sample of delay
	var len_i := maxi(int(floor(period)), 2)
	var d := period - len_i
	var c := (1.0 - d) / (1.0 + d)  # first-order allpass for fractional delay
	var ring := PackedFloat32Array()
	ring.resize(len_i)
	var lp := 0.0
	for i in len_i:
		lp += (rng.randf_range(-1.0, 1.0) - lp) * bright
		ring[i] = lp

	var idx := 0
	var ap_x1 := 0.0
	var ap_y1 := 0.0
	for i in n:
		var cur := ring[idx]
		var nxt_i := idx + 1
		if nxt_i >= len_i:
			nxt_i = 0
		var avg := damp * 0.5 * (cur + ring[nxt_i])
		var y := c * (avg - ap_y1) + ap_x1
		ap_x1 = avg
		ap_y1 = y
		ring[idx] = y
		idx = nxt_i
		if buzz > 0.0:
			out[i] = cur / (1.0 + buzz * absf(cur))
		else:
			out[i] = cur
	return out


# ------------------------------------------------------------ wavetable
static func _make_table(h: Array, f: float) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(TABLE_SIZE)
	for k in h.size():
		var harmonic := k + 1
		if harmonic * f > RATE * 0.45:
			break  # keep partials below Nyquist (no aliasing)
		var amp: float = h[k]
		for i in TABLE_SIZE:
			t[i] += amp * sin(TAU * harmonic * i / TABLE_SIZE)
	var peak := 0.0001
	for v in t:
		peak = maxf(peak, absf(v))
	for i in TABLE_SIZE:
		t[i] /= peak
	return t


static func _read(tab: PackedFloat32Array, ph: float) -> float:
	var i := int(ph)
	var fr := ph - i
	var a := tab[i]
	var b := tab[(i + 1) & TABLE_MASK]
	return a + (b - a) * fr


static func _wavetable(p: Dictionary, f: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = p.get("dur", 2.0)
	var atk: float = maxf(p.get("attack", 0.02), 0.001)
	var dec: float = maxf(p.get("decay", 0.3), 0.001)
	var sus: float = p.get("sustain", 0.8)
	var rel: float = maxf(p.get("release", 0.2), 0.005)
	var vib_hz: float = p.get("vib_hz", 0.0)
	var vib_depth: float = p.get("vib_depth", 0.0)
	var vib_delay: float = p.get("vib_delay", 0.0)
	var scoop: float = p.get("scoop", 0.0)
	var breath: float = p.get("breath", 0.0)
	var det: float = p.get("detune", 0.0)
	var morph: float = p.get("morph", 0.0)
	var no_release: bool = p.get("no_release", false)

	var bright := _make_table(p.get("harmonics", [1.0]), f)
	var tail := PackedFloat32Array()
	if morph > 0.0:
		tail = _make_table(p.get("tail", [1.0]), f)

	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var inc0 := f * TABLE_SIZE / RATE
	var ph1 := 0.0
	var ph2 := rng.randf() * TABLE_SIZE
	var nz := 0.0

	for i in n:
		var t := float(i) / RATE
		var e: float
		if t < atk:
			e = t / atk
		else:
			e = sus + (1.0 - sus) * exp(-(t - atk) / dec)
		if t > dur - rel and not no_release:
			e *= maxf(0.0, (dur - t) / rel)

		var bend := 1.0 + scoop * exp(-t / 0.07)
		if vib_depth > 0.0 and t > vib_delay:
			bend += vib_depth * minf(1.0, (t - vib_delay) * 2.0) * sin(TAU * vib_hz * t)
		var inc := inc0 * bend

		ph1 += inc
		if ph1 >= TABLE_SIZE:
			ph1 -= TABLE_SIZE
		var v := _read(bright, ph1)
		if morph > 0.0:
			var tv := _read(tail, ph1)
			v = tv + (v - tv) * exp(-t / morph)
		if det > 0.0:
			ph2 += inc * (1.0 + det)
			if ph2 >= TABLE_SIZE:
				ph2 -= TABLE_SIZE
			v = (v + _read(bright, ph2)) * 0.5
		if breath > 0.0:
			nz += (rng.randf_range(-1.0, 1.0) - nz) * 0.35
			v += nz * breath * 3.0
		out[i] = v * e
	return out


# ------------------------------------------------------------- membrane
static func _membrane(p: Dictionary, f: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = p.get("dur", 1.0)
	var decay: float = maxf(p.get("decay", 0.4), 0.01)
	var drop: float = p.get("drop", 0.2)
	var drop_t: float = maxf(p.get("drop_time", 0.05), 0.001)
	var noise: float = p.get("noise", 0.1)
	var noise_d: float = maxf(p.get("noise_decay", 0.01), 0.001)
	var partials: Array = p.get("partials", [])
	var tone: float = p.get("tone", 1.0)
	var noise_hp: bool = p.get("noise_hp", false)
	var noise_lp: float = p.get("noise_lp", 0.0)
	var click: float = p.get("click", 0.0)
	var sat: float = p.get("sat", 0.0)

	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var nlp := 0.0
	var pph := PackedFloat32Array()
	pph.resize(partials.size())

	for i in n:
		var t := float(i) / RATE
		var drop_env := exp(-t / drop_t)
		ph += f * (1.0 + drop * drop_env) / RATE
		var v := tone * sin(TAU * ph) * exp(-t / decay)
		for k in partials.size():
			var pr: Array = partials[k]
			pph[k] += f * float(pr[0]) * (1.0 + drop * 0.3 * drop_env) / RATE
			v += tone * float(pr[1]) * sin(TAU * pph[k]) * exp(-t / (decay * float(pr[2])))
		var nz := rng.randf_range(-1.0, 1.0)
		if noise_hp:  # crude high-pass for hats/snare sizzle
			nlp += (nz - nlp) * 0.25
			nz -= nlp
		elif noise_lp > 0.0:  # low-passed noise = skin rumble / boom
			nlp += (nz - nlp) * noise_lp
			nz = nlp * 3.0
		v += noise * nz * exp(-t / noise_d)
		if click > 0.0:  # stick/hand transient
			v += click * rng.randf_range(-1.0, 1.0) * exp(-t / 0.0025)
		if sat > 0.0:  # drum saturation: punch and harmonics that survive phone speakers
			v = v * (1.0 + sat) / (1.0 + sat * absf(v))
		out[i] = v
	return out


# --------------------------------------------------------------- output
## Interleaves 1 or 2 channels to 16-bit PCM. Level is balanced by loudness (RMS) so
## pads, plucks and drums sit together, with peaks kept under the limit.
static func _finish(chans: Array, fade_tail: bool = true) -> AudioStreamWAV:
	var n: int = chans[0].size()
	var peak := 0.0001
	var energy := 0.0
	for ch: PackedFloat32Array in chans:
		for v in ch:
			peak = maxf(peak, absf(v))
			energy += v * v
	var rms := sqrt(energy / maxf(n * chans.size(), 1))
	var gain := minf(0.93 / peak, TARGET_RMS / maxf(rms, 1e-5))
	var fade := mini(int(0.02 * RATE), n) if fade_tail else 0
	var cc := chans.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2 * cc)
	for i in n:
		var w := 1.0
		if fade > 0 and i >= n - fade:
			w = float(n - 1 - i) / fade
		for c in cc:
			var v: float = chans[c][i] * gain * w
			bytes.encode_s16((i * cc + c) * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = cc == 2
	s.data = bytes
	return s


# -------------------------------------------------------------- sampler
## Real recordings. Loads the zone's file, builds a seamless sustain loop from the steady
## middle of the note (crossfaded), trims the unused tail, and stores a loudness-balancing
## gain in the stream's "gain_db" metadata (applied by AudioEngine).
static func _bake_sampler(p: Dictionary, root: int, layer: int = 0) -> AudioStreamWAV:
	var path := ""
	for z in p.get("samples", []):
		if int(z.midi) == root and int(z.get("vel", 0)) == layer:
			path = str(z.file)
	var src := load(path) as AudioStreamWAV if path != "" else null
	if src == null:
		push_error("SynthBaker: cannot load sample '%s'" % path)
		return null
	if src.format != AudioStreamWAV.FORMAT_16_BITS:
		push_error("SynthBaker: sample '%s' is not 16-bit PCM" % path)
		return null
	var s := src.duplicate() as AudioStreamWAV
	var ch := 2 if s.stereo else 1
	var fb := 2 * ch
	var data := s.data
	var n := data.size() / fb
	var rate := s.mix_rate
	var loop: bool = p.get("loop", false) and n > int(1.6 * rate)
	var from := 0
	var to := mini(n, rate)  # loudness is measured on the first second for one-shots
	if loop:
		var xf := mini(int(0.15 * rate), int(n * 0.12))
		# Loop start: the first rising zero crossing after 30 % of the note.
		var begin := int(n * 0.30)
		var zs := _upward_zeros(data, ch, begin, mini(begin + int(0.05 * rate), n - 2))
		if not zs.is_empty():
			begin = zs[0]
		# Loop end: among the rising zero crossings near 74 %, the one whose following sound is most like the
		# loop start (same phase of the note), so the blend does not cancel or pulse.
		var end := int(n * 0.74)
		var best := -2.0
		var lo := maxi(end - int(0.05 * rate), begin + xf * 3)
		var cands := _upward_zeros(data, ch, lo, mini(end + int(0.05 * rate), n - xf - 2))
		var skip := maxi(cands.size() / 40, 1)  # high notes have hundreds of crossings: 40 tries are plenty
		for ci in range(0, cands.size(), skip):
			var sim := _similarity(data, ch, begin, cands[ci], xf, 16)
			if sim > best:
				best = sim
				end = cands[ci]
		end = mini(end, n - xf - 1)
		xf = mini(xf, mini(n - end - 1, (end - begin) / 3))
		# Fade shape by similarity: alike sounds (1.0) cross-fade linearly; unrelated ones (0.0) with equal
		# power, so the level neither dips nor bumps once per loop.
		var like := clampf(_similarity(data, ch, begin, end, xf), 0.0, 1.0)
		for j in xf:  # blend the loop head with the audio that continues past its end
			var w := float(j) / xf
			var g_head := lerpf(sqrt(w), w, like)
			var g_tail := lerpf(sqrt(1.0 - w), 1.0 - w, like)
			for c in ch:
				var i1 := ((begin + j) * ch + c) * 2
				var i2 := ((end + j) * ch + c) * 2
				data.encode_s16(i1, clampi(int(data.decode_s16(i1) * g_head + data.decode_s16(i2) * g_tail), -32768, 32767))
		s.data = data.slice(0, end * fb)
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = begin
		s.loop_end = end
		from = begin
		to = end
	# loudness balance
	var stride := maxi(1, (to - from) / 4000)
	var energy := 0.0
	var peak := 0.0
	var cnt := 0
	var i := from
	while i < to:
		for c in ch:
			var v := absf(data.decode_s16((i * ch + c) * 2)) / 32768.0
			energy += v * v
			peak = maxf(peak, v)
		cnt += ch
		i += stride
	var rms := sqrt(energy / maxf(cnt, 1)) + 1e-6
	var gain := TARGET_RMS / rms if loop else minf(TARGET_RMS * 4.0 / rms, 0.7 / maxf(peak, 1e-4))
	# Quiet recordings (soft layers of brass and low strings) need a lot of gain: the player's volume_db passes
	# far more than +24 dB (mixing is in floating point), so it is simply applied there.
	s.set_meta("gain_db", clampf(20.0 * log(gain) / log(10.0), -MAX_PLAYER_DB, MAX_PLAYER_DB))
	return s


## Indices in [lo, hi) where the first channel rises through zero.
static func _upward_zeros(data: PackedByteArray, ch: int, lo: int, hi: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if hi - lo < 2:
		return out
	var prev := data.decode_s16(lo * ch * 2)
	for i in range(lo + 1, hi):
		var v := data.decode_s16(i * ch * 2)
		if prev < 0 and v >= 0:
			out.append(i)
		prev = v
	return out


## How alike two stretches of `count` frames are (normalised correlation, -1..1), on the first channel.
static func _similarity(data: PackedByteArray, ch: int, a: int, b: int, count: int, stride: int = 4) -> float:
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	var i := 0
	while i < count:
		var x := float(data.decode_s16((a + i) * ch * 2))
		var y := float(data.decode_s16((b + i) * ch * 2))
		sab += x * y
		saa += x * x
		sbb += y * y
		i += stride
	return sab / sqrt(saa * sbb + 1e-6)