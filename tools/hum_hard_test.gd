extends SceneTree
## Dev tool: godot --headless --script res://tools/hum_hard_test.gd
## Realistic-singing stress test. Each case adds human imperfections to the same
## melody (120 BPM feel) and scores note-level precision/recall: a detected note
## counts only if the pitch is exactly right AND the onset is within 80 ms.

const RATE := 44100
var _rng := RandomNumberGenerator.new()

# [midi, start_sec, length_sec]; repeated notes, a leap, legato steps
const MELODY := [
	[60, 0.00, 0.50], [62, 0.50, 0.25], [64, 0.75, 0.25], [64, 1.00, 0.25], [65, 1.25, 0.50],
	[67, 1.75, 0.25], [67, 2.00, 0.50], [72, 2.50, 0.50], [71, 3.00, 0.25], [69, 3.25, 0.25],
	[67, 3.50, 0.50], [60, 4.00, 0.75],
]

var CASES := {
	"clean vibrato +-25c": {"vib": 25.0},
	"wide vibrato +-55c": {"vib": 55.0},
	"scoop into notes (-100c, 70 ms)": {"vib": 15.0, "scoop": -100.0},
	"flat singer (-35c) + wander": {"vib": 20.0, "drift": -35.0, "wander": 12.0},
	"octave glitch (2 frames)": {"vib": 15.0, "glitch": 0.03},
	"octave glitch (6 frames)": {"vib": 15.0, "glitch": 0.09},
	"legato + consonant dips": {"vib": 20.0, "dip": 0.35},
	"quiet + breathy": {"vib": 20.0, "breath": 0.05, "amp": 0.08},
	"combined (typical amateur)": {"vib": 35.0, "scoop": -60.0, "drift": -25.0, "wander": 10.0, "breath": 0.03, "dip": 0.5},
}


func _initialize() -> void:
	await process_frame
	_rng.seed = 11
	var total_f1 := 0.0
	var worst := 1.0
	var failures := 0
	for name in CASES:
		var f1 := _run(name, CASES[name])
		total_f1 += f1
		worst = minf(worst, f1)
		if f1 < 0.9:
			failures += 1
	failures += _tempo_test()
	failures += _exact_test()
	print("MEAN F1 %.3f   WORST %.3f   cases below 0.90: %d" % [total_f1 / CASES.size(), worst, failures])
	quit(failures)


func _run(label: String, o: Dictionary) -> float:
	var buf := PackedFloat32Array()
	buf.resize(int(6.0 * RATE))
	for n in MELODY:
		_voice(buf, 0.4 + n[1], n[2], n[0], o)
	var amp: float = o.get("amp", 0.5)
	var breath: float = o.get("breath", 0.01)
	for i in buf.size():
		buf[i] += _rng.randf_range(-breath, breath) * amp
	var found := HumTranscriber.transcribe(buf, RATE)
	var hits := 0
	var used := {}
	for n in MELODY:
		for j in found.size():
			if used.has(j):
				continue
			if int(round(found[j].midi)) == n[0] and absf(found[j].t0 - (0.4 + n[1])) < 0.08:
				used[j] = true
				hits += 1
				break
	var prec := float(hits) / maxf(found.size(), 1)
	var rec := float(hits) / MELODY.size()
	var f1 := 2.0 * prec * rec / maxf(prec + rec, 1e-6)
	var got := []
	for f in found:
		got.append(int(round(f.midi)))
	print("%-34s found %2d/%d  P %.2f R %.2f  F1 %.2f  %s" % [label, found.size(), MELODY.size(), prec, rec, f1, "" if f1 >= 0.9 else "<-- " + str(got)])
	return f1


func _voice(buf: PackedFloat32Array, start: float, dur: float, midi: float, o: Dictionary) -> void:
	var n := int(dur * RATE)
	var base := int(start * RATE)
	var ph := 0.0
	var vib: float = o.get("vib", 0.0)
	var scoop: float = o.get("scoop", 0.0)
	var drift: float = o.get("drift", 0.0)
	var wander: float = o.get("wander", 0.0)
	var amp: float = o.get("amp", 0.5)
	var dip: float = o.get("dip", 0.0)
	var glitch: float = o.get("glitch", 0.0)
	var vph := _rng.randf() * TAU
	var wph := _rng.randf() * TAU
	var glitch_at := dur * 0.45
	for i in n:
		var t := float(i) / RATE
		var cents := drift + vib * sin(TAU * 5.8 * t + vph) * minf(1.0, t / 0.2)
		cents += wander * sin(TAU * 0.7 * (start + t) + wph)
		cents += scoop * exp(-t / 0.035)
		if glitch > 0.0 and dur > glitch + 0.1 and t >= glitch_at and t < glitch_at + glitch:
			cents += 1200.0
		var f := 440.0 * pow(2.0, (midi - 69) / 12.0 + cents / 1200.0)
		ph += TAU * f / RATE
		var attack := 0.03
		var env := minf(1.0, t / attack)
		if dip > 0.0:
			env = lerpf(dip, 1.0, minf(1.0, t / 0.045))
		env *= minf(1.0, (dur - t) / 0.03)
		var trem := 1.0 + 0.12 * sin(TAU * 6.5 * t)
		var v := sin(ph) + 0.6 * sin(2.0 * ph) + 0.35 * sin(3.0 * ph) + 0.2 * sin(4.0 * ph) + 0.1 * sin(5.0 * ph)
		buf[base + i] += amp * 0.4 * env * trem * v


## Hummed at 120 BPM into a 100 BPM project: the estimator should find ~120; a take that
## already matches the project tempo must be left alone.
func _tempo_test() -> int:
	var buf := PackedFloat32Array()
	buf.resize(int(6.0 * RATE))
	for n in MELODY:
		_voice(buf, 0.4 + n[1], n[2], n[0], {"vib": 20.0})
	var found := HumTranscriber.transcribe(buf, RATE)
	var est: float = HumTranscriber.estimate_bpm(found, 100.0)
	var keep: float = HumTranscriber.estimate_bpm(found, 120.0)
	var ok: bool = absf(est - 120.0) <= 2.0 and keep == 120.0
	print("tempo estimate: hummed 120 BPM, project 100 -> %.0f ; project already 120 -> %.0f  %s" % [est, keep, "ok" if ok else "FAIL"])
	return 0 if ok else 1


## The notes that reach the track must reproduce what was sung: pitch within 15 cents (even for notes sung
## between piano keys), start within 30 ms, length within 60 ms - not rounded to the grid.
func _exact_test() -> int:
	var sung := []  # [midi_float, start, len]
	var shifts := [0.4, -0.4, 0.3, -0.3, 0.45, -0.2, 0.35, -0.45, 0.1, -0.35, 0.25, -0.1]  # scattered: no common offset to remove
	for i in MELODY.size():
		sung.append([MELODY[i][0] + shifts[i], 0.4 + MELODY[i][1], MELODY[i][2]])
	var buf := PackedFloat32Array()
	buf.resize(int(6.0 * RATE))
	for n in sung:
		_voice(buf, n[1], n[2], n[0], {"vib": 20.0, "scoop": -60.0})
	var found := HumTranscriber.transcribe(buf, RATE)
	var notes := HumTranscriber.to_track_notes(found, 100.0, 0, 0.0)
	var step_sec := 0.15
	var worst_c := 0.0
	var worst_t := 0.0
	var worst_d := 0.0
	var matched := 0
	for n in sung:
		for nt in notes:
			var t0: float = (nt.start + nt.off) * step_sec
			if absf(t0 - n[1]) < 0.12:
				matched += 1
				worst_c = maxf(worst_c, absf((nt.midi + nt.cents / 100.0) - n[0]) * 100.0)
				worst_t = maxf(worst_t, absf(t0 - n[1]))
				worst_d = maxf(worst_d, absf(nt.dur * step_sec - n[2]))
				break
	var ok: bool = matched == sung.size() and notes.size() == sung.size() and worst_c <= 15.0 and worst_t <= 0.03 and worst_d <= 0.06
	print("exact performance: %d/%d notes, worst pitch error %.1f cents, onset %.0f ms, length %.0f ms  %s" % [
		matched, sung.size(), worst_c, worst_t * 1000.0, worst_d * 1000.0, "ok" if ok else "FAIL"])
	return 0 if ok else 1