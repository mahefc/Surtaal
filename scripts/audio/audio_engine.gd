extends Node
## Autoload: bus layout and the polyphonic voice engine.
##
## Bus layout:  voices -> one bus per track (pan, reverb, section chorus) -> "Instruments" -> "Master" (compressor, limiter)
##
## Voices support: hold/release (looped samples sustain until note_off), live
## vibrato, per-note microtonal tuning, and glide (meend) between pitches.
## note_on() returns a note id; pass it to note_off() / glide().

signal note_played(def: InstrumentDef, midi: int, stream: AudioStreamWAV)

const VOICES := 72  # a full orchestra plays each note up to 7 times (times its layers), so a chord still has voices left
const SECTION_CENTS := [-9.0, 12.0, -17.0, 6.0, -5.0, 19.0]  # how far each extra player is off the lead
const BUS_INSTRUMENTS := "Instruments"
const STEREO_WIDTH := 0.7
const LIMITER_DRIVE_DB := 5.0
## Master EQ gains (dB) at 32, 100, 320, 1000, 3200 and 10000 Hz.
const EQ_DB := [-12.0, 0.0, -1.5, 0.0, 1.5, 2.0]
const MAX_HOLD_SEC := 30.0  # stuck-note guard for sustaining voices


class Voice:
	var player: AudioStreamPlayer
	var id := -1
	var midi := 0
	var tuning_cents := 0.0
	var tunable := true
	var sample_cents := 0.0
	var glide_cur := 0.0
	var glide_from := 0.0
	var glide_to := 0.0
	var glide_t := 1.0
	var glide_dur := 0.1
	var vib_hz := 0.0
	var vib_depth := 0.0
	var vib_delay := 0.0
	var age := 0.0
	var base_db := 0.0
	var sustains := false
	var releases_on_off := false
	var releasing := false
	var rel_t := 0.0
	var rel_dur := 0.25


var _voices: Array[Voice] = []
var _next_id := 0
## Extra players of a section note, started a little late so they are not a perfect copy. Same note id as the lead.
var _late: Array = []


func _ready() -> void:
	_build_buses()
	for i in VOICES:
		var v := Voice.new()
		v.player = AudioStreamPlayer.new()
		v.player.bus = BUS_INSTRUMENTS
		add_child(v.player)
		_voices.append(v)


func _build_buses() -> void:
	var idx := AudioServer.get_bus_index(BUS_INSTRUMENTS)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_INSTRUMENTS)
		AudioServer.set_bus_send(idx, "Master")
	# (reverb and the section chorus are per track: see TrackManager._ensure_bus)
	# Stereo width. The recordings are already wide, and widening them more makes the left and right
	# channels partly cancel when a phone / laptop speaker plays them as mono (hollow, thin sound).
	# 1.0 = as recorded; 0.7 keeps a clear stereo picture on headphones and stays full on one speaker.
	if ClassDB.class_exists("AudioEffectStereoEnhance"):
		var wide := ClassDB.instantiate("AudioEffectStereoEnhance") as AudioEffect
		wide.set("pan_pullout", STEREO_WIDTH)
		AudioServer.add_bus_effect(idx, wide)

	# Master: tone shaping -> glue compressor -> limiter.
	var master := AudioServer.get_bus_index("Master")
	# Gentle tone: no rumble below ~40 Hz (small speakers only waste power on it), a touch less
	# low-mid mud, a little presence and air so the sound stays clear on small speakers.
	var eq := AudioEffectEQ6.new()  # bands: 32, 100, 320, 1000, 3200, 10000 Hz
	for band in EQ_DB.size():
		eq.set_band_gain_db(band, EQ_DB[band])
	AudioServer.add_bus_effect(master, eq)
	# Glue compressor so layered parts sit together (slow attack keeps the note starts crisp) ...
	var comp := AudioEffectCompressor.new()
	comp.threshold = -20.0
	comp.ratio = 3.0
	comp.attack_us = 30000.0
	comp.release_ms = 200.0
	comp.gain = 4.0  # make-up: the song comes out at a normal loudness, not whisper-quiet
	AudioServer.add_bus_effect(master, comp)
	# ... then a brick-wall limiter so nothing ever clips.
	for cls in ["AudioEffectHardLimiter", "AudioEffectLimiter"]:
		if ClassDB.class_exists(cls):
			var lim := ClassDB.instantiate(cls) as AudioEffect
			if cls == "AudioEffectHardLimiter":
				lim.set("pre_gain_db", LIMITER_DRIVE_DB)  # more level; the limiter catches the peaks
				lim.set("ceiling_db", -1.0)
				lim.set("release", 0.1)
			AudioServer.add_bus_effect(master, lim)
			break


## Start a note. Returns a note id, or -1 on failure.
## `bus` routes the note to a track mixer channel (default: the shared Instruments bus).
## A layered instrument (strings = violins + cellos + basses) plays all of its parts under one note id.
## A big-section instrument (def.ensemble_level() 1-3) adds 2 / 4 / 6 quieter copies of each part, each a few cents
## flat or sharp and a few milliseconds late (the track's bus adds a chorus on top), so it sounds like a section,
## an orchestra or a full orchestra playing together.
func note_on(def: InstrumentDef, midi: int, velocity: float = 0.8, preset: int = -1, bus: String = "", cents: float = 0.0) -> int:
	if preset < 0:
		preset = def.active_preset
	var parts: Array = []
	if def.is_layered():
		for p in SampleManager.layer_parts(def, midi):
			parts.append({"def": p.def, "midi": p.midi, "vel": velocity * p.gain, "preset": 0})
	else:
		parts.append({"def": def, "midi": midi, "vel": velocity, "preset": preset})
	if parts.is_empty():
		return -1
	for p in parts:
		if SampleManager.get_sample(p.def, p.midi, p.preset, p.def.layer_for_velocity(p.vel)) == null:
			return -1
	_next_id += 1
	var id := _next_id
	var copies := def.ensemble_level() * 2
	var lead_gain := 1.0 / sqrt(1.0 + 0.45 * copies)  # a bigger section is not much louder, just fuller
	var now := Time.get_ticks_usec()
	for p in parts:
		var pd: InstrumentDef = p.def
		var solo_part: bool = copies == 0 or pd.is_percussive() or pd.is_fixed_pitch()
		_voice_on(id, pd, p.midi, p.vel * (1.0 if solo_part else lead_gain), p.preset, bus, cents)
		if solo_part:
			continue
		for i in copies:
			_late.append({
				"at": now + int((14.0 + 13.0 * i + 4.0 * sin(i * 2.3 + p.midi)) * 1000.0), "id": id, "def": pd, "midi": p.midi,
				"velocity": p.vel * lead_gain * maxf(0.75 - 0.09 * i, 0.3), "preset": p.preset, "bus": bus,
				"cents": cents + SECTION_CENTS[i % SECTION_CENTS.size()]})
	return id


func _voice_on(id: int, def: InstrumentDef, midi: int, velocity: float, preset: int, bus: String, cents: float) -> void:
	var layer := def.layer_for_velocity(velocity)  # soft notes take the soft recording, loud the loud one
	var stream := SampleManager.get_sample(def, midi, preset, layer)
	if stream == null:
		return
	var v := _acquire()
	v.id = id
	v.midi = midi
	v.age = 0.0
	v.releasing = false
	v.rel_t = 0.0
	v.glide_cur = 0.0
	v.glide_t = 1.0
	v.tunable = not def.is_percussive() and not def.is_fixed_pitch()
	# zone sampling: the rendered root may be a semitone or two away from the requested note
	v.sample_cents = 0.0 if def.is_fixed_pitch() else (midi - def.zone_root(midi, layer)) * 100.0
	v.tuning_cents = (TuningManager.offset_cents(midi) + cents if v.tunable else 0.0) + v.sample_cents  # `cents`: the pitch as it was sung
	v.sustains = stream.loop_mode != AudioStreamWAV.LOOP_DISABLED
	# Pitched recordings stop when the note ends (like a damper). Without this a piano/harp/mallet note rang out its whole
	# recorded hall tail, which sounds like reverb even with the reverb off. Drum hits still ring out naturally.
	v.releases_on_off = def.synth == "wavetable" or def.synth == "super" or (def.synth == "sampler" and (v.sustains or not def.is_fixed_pitch()))
	var p := def.params_for(preset)
	v.rel_dur = clampf(float(p.get("release", 0.25 if v.sustains else 0.35)), 0.08, 1.2)
	v.vib_hz = float(p.get("vib_hz", 0.0)) if v.sustains else 0.0
	v.vib_depth = float(p.get("vib_depth", 0.0)) if v.sustains else 0.0
	v.vib_delay = float(p.get("vib_delay", 0.0))
	v.base_db = linear_to_db(clampf(velocity, 0.05, 1.0) * 0.8) + float(stream.get_meta("gain_db", 0.0))
	v.player.stop()
	v.player.bus = bus if bus != "" else BUS_INSTRUMENTS
	v.player.stream = stream
	v.player.volume_db = v.base_db
	v.player.pitch_scale = _scale(v.tuning_cents)
	v.player.play()
	note_played.emit(def, midi, stream)


## Release a held note (sustaining/keyboard-style instruments fade out; plucks and
## drums ring out naturally). A section note releases every player of it.
func note_off(id: int) -> void:
	for v in _voices:
		if v.id == id and v.releases_on_off:
			v.releasing = true
	var keep := []
	for job in _late:
		if int(job.id) != id:
			keep.append(job)
	_late = keep


## Slide a sounding note to another pitch over `seconds` (meend / portamento).
## The target keeps the current tuning, so a raga's shruti are respected.
func glide(id: int, to_midi: int, seconds: float = 0.12) -> void:
	for v in _voices:
		if v.id != id or v.releasing:
			continue
		var target_cents := (to_midi - v.midi) * 100.0
		if v.tunable:
			target_cents += TuningManager.offset_cents(to_midi) - TuningManager.offset_cents(v.midi)
		# note: the glide is relative to the pitch the sample already sounds at
		v.glide_from = v.glide_cur
		v.glide_to = target_cents
		v.glide_t = 0.0
		v.glide_dur = maxf(seconds, 0.01)


func all_notes_off() -> void:
	_late.clear()
	for v in _voices:
		v.player.stop()
		v.id = -1


func active_voices() -> int:
	var c := 0
	for v in _voices:
		if v.id >= 0 and v.player.playing:
			c += 1
	return c


func set_master_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(linear, 0.0001)))


func _process(delta: float) -> void:
	if not _late.is_empty():
		var now := Time.get_ticks_usec()
		var still := []
		for job in _late:
			if int(job.at) <= now:
				_voice_on(int(job.id), job.def, int(job.midi), float(job.velocity), int(job.preset), str(job.bus), float(job.cents))
			else:
				still.append(job)
		_late = still
	for v in _voices:
		if v.id < 0:
			continue
		if not v.player.playing:
			v.id = -1
			continue
		v.age += delta
		var c := v.tuning_cents
		if v.glide_t < 1.0:
			v.glide_t = minf(1.0, v.glide_t + delta / v.glide_dur)
			v.glide_cur = lerpf(v.glide_from, v.glide_to, smoothstep(0.0, 1.0, v.glide_t))
		c += v.glide_cur
		if v.vib_depth > 0.0 and v.age > v.vib_delay:
			var fade := minf(1.0, (v.age - v.vib_delay) * 2.0)
			c += v.vib_depth * 1731.0 * fade * sin(TAU * v.vib_hz * v.age)
		v.player.pitch_scale = _scale(c)
		if v.sustains and not v.releasing and v.age > MAX_HOLD_SEC:
			v.releasing = true
		if v.releasing:
			v.rel_t += delta
			if v.rel_t >= v.rel_dur:
				v.player.stop()
				v.id = -1
			else:
				v.player.volume_db = v.base_db + linear_to_db(1.0 - v.rel_t / v.rel_dur)


func _scale(cents: float) -> float:
	return pow(2.0, cents / 1200.0)


func _acquire() -> Voice:
	var oldest: Voice = _voices[0]
	for v in _voices:
		if v.id < 0 or not v.player.playing:
			return v
		if v.age > oldest.age:
			oldest = v
	return oldest  # all busy: steal the longest-sounding voice
