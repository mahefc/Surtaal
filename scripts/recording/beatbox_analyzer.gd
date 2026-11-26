class_name BeatboxAnalyzer
extends RefCounted
## Turns a beatbox recording into drum hits.
##
## 1. Onsets: a loud jump in a short-time energy envelope marks each hit.
## 2. Sound type: the "brightness" (spectral centroid, estimated from how fast the waveform
##    wiggles) of the first 50 ms after the onset. A low thud ("boom", "b") is a kick, a
##    broad burst ("pf", "kh") is a snare, a hissy tick ("ts", "tss") is a hi-hat.
## 3. Grid: each hit is snapped to the nearest 1/16 step of the loop.

const HOP_SEC := 0.005
const LOOK_SEC := 0.05          # the slice after an onset that is used to tell the sounds apart
const MIN_GAP_SEC := 0.07       # two hits closer than this are one hit
const REL_FLOOR := 0.14         # a hit must reach this fraction of the loudest hit
const JUMP := 1.8               # ... and be this many times louder than what came just before
const KICK_BELOW_HZ := 1100.0   # brightness under this = kick
const HAT_ABOVE_HZ := 5200.0    # brightness over this = hi-hat; in between = snare


## Returns [{t: seconds from the start, kind: "kick"|"snare"|"hat", vel: 0..1}], oldest first.
static func analyze(data: PackedFloat32Array, rate: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := data.size()
	var hop := maxi(int(rate * HOP_SEC), 16)
	var hops := n / hop
	if hops < 8:
		return out
	# remove DC and rumble so a slow mic offset never reads as a hit
	var x := PackedFloat32Array()
	x.resize(n)
	var prev_in := 0.0
	var prev_out := 0.0
	for i in n:
		var v := data[i]
		prev_out = v - prev_in + 0.995 * prev_out
		prev_in = v
		x[i] = prev_out
	var env := PackedFloat32Array()
	env.resize(hops)
	var peak := 0.0
	for k in hops:
		var acc := 0.0
		var base := k * hop
		for i in hop:
			var s := x[base + i]
			acc += s * s
		env[k] = sqrt(acc / hop)
		peak = maxf(peak, env[k])
	if peak < 0.004:
		return out  # silence
	var floor_level := maxf(peak * REL_FLOOR, 0.003)
	var gap := maxi(int(MIN_GAP_SEC / HOP_SEC), 2)
	var look := int(rate * LOOK_SEC)
	var last := -gap
	var onsets: Array[Dictionary] = []
	var k := 4
	while k < hops - 1:
		var before := 0.0
		var cnt := 0
		for j in range(maxi(k - 10, 0), maxi(k - 2, 1)):
			before += env[j]
			cnt += 1
		before = before / maxf(cnt, 1)
		if env[k] >= floor_level and env[k] > JUMP * before + 0.0008 and k - last >= gap:
			# the hit's strength is the loudest hop shortly after
			var top := 0.0
			for j in range(k, mini(k + 7, hops)):
				top = maxf(top, env[j])
			onsets.append({"k": k, "top": top})
			last = k
		k += 1
	for o in onsets:
		var s0: int = o.k * hop
		var s1 := mini(s0 + look, n)
		var e := 0.0
		var ed := 0.0
		for i in range(maxi(s0, 1), s1):
			var d := x[i] - x[i - 1]
			e += x[i] * x[i]
			ed += d * d
		if e <= 0.0:
			continue
		var centroid := rate / TAU * sqrt(ed / e)
		var kind := "snare"
		if centroid < KICK_BELOW_HZ:
			kind = "kick"
		elif centroid > HAT_ABOVE_HZ:
			kind = "hat"
		out.append({"t": float(o.k) * HOP_SEC, "kind": kind, "vel": clampf(float(o.top) / peak, 0.0, 1.0)})
	return out


## How hard each snapped hit was: {"kick": {step: 0.1..1.0}, ...}. The loudest hit of a take is
## full strength; soft hits stay clearly audible. Same snapping as `to_steps`.
static func to_velocities(hits: Array, bpm: float, pattern_steps: int, latency: float) -> Dictionary:
	var step_sec := 60.0 / maxf(bpm, 1.0) / 4.0
	var out := {"kick": {}, "snare": {}, "hat": {}}
	for h in hits:
		var s := posmod(int(roundf((float(h.t) - latency) / step_sec)), maxi(pattern_steps, 1))
		var v := clampf(0.35 + 0.65 * float(h.vel), 0.1, 1.0)
		var lane: Dictionary = out[h.kind]
		lane[s] = maxf(float(lane.get(s, 0.0)), v)
	return out


## Snap hits to the loop's 1/16 grid. `latency` (seconds) moves them earlier: the singer reacts to
## a click that arrives late and the mic hears them late. Returns {"kick": [steps], "snare": [...], "hat": [...]}.
static func to_steps(hits: Array, bpm: float, pattern_steps: int, latency: float) -> Dictionary:
	var step_sec := 60.0 / maxf(bpm, 1.0) / 4.0
	var out := {"kick": [], "snare": [], "hat": []}
	for h in hits:
		var s := posmod(int(roundf((float(h.t) - latency) / step_sec)), maxi(pattern_steps, 1))
		var lane: Array = out[h.kind]
		if not (s in lane):
			lane.append(s)
	for kind in out:
		out[kind].sort()
	return out
