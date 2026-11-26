extends SceneTree
## Dev tool: godot --headless --script res://tools/hum_test.gd
## Synthesises "hummed" melodies (harmonics, vibrato, breath noise, level changes)
## and checks the YIN tracker + segmenter + quantiser recover the exact notes.

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	await process_frame
	_rng.seed = 7
	var bad := 0
	# [midi, seconds, gap_after, vibrato_cents]
	var melody := [[60, 0.45, 0.06, 20], [62, 0.45, 0.0, 25], [64, 0.30, 0.06, 15], [64, 0.30, 0.06, 15],
		[67, 0.60, 0.08, 30], [72, 0.45, 0.06, 20], [55, 0.60, 0.05, 20], [69, 0.45, 0.0, 10]]
	for rate in [44100, 48000]:
		for noise in [0.0, 0.02]:
			bad += _run(melody, rate, noise)
	# sine (whistle-like), slow glissando must not explode into many notes
	bad += _run_whistle()
	bad += _run_silence()
	print("HUM FAILURES: ", bad)
	quit(bad)


func _tone(buf: PackedFloat32Array, start: int, n: int, midi: float, vib_cents: float, rate: int, amp: float) -> void:
	var f0 := 440.0 * pow(2.0, (midi - 69.0) / 12.0)
	var ph := 0.0
	var vph := _rng.randf() * TAU
	for i in n:
		var t := float(i) / rate
		var vib := vib_cents * sin(TAU * 5.5 * t + vph) / 1200.0
		ph += TAU * f0 * pow(2.0, vib) / rate
		var env := minf(1.0, t / 0.04) * minf(1.0, (n - i) / (0.03 * rate))
		var v := sin(ph) + 0.5 * sin(2.0 * ph) + 0.25 * sin(3.0 * ph) + 0.12 * sin(4.0 * ph)
		buf[start + i] += amp * env * v * 0.4


func _run(melody: Array, rate: int, noise: float) -> int:
	var total := 0.3
	for n in melody:
		total += n[1] + n[2]
	var buf := PackedFloat32Array()
	buf.resize(int((total + 0.3) * rate))
	var t := 0.3
	for n in melody:
		_tone(buf, int(t * rate), int(n[1] * rate), n[0], n[3], rate, 0.6)
		t += n[1] + n[2]
	if noise > 0.0:
		for i in buf.size():
			buf[i] += _rng.randf_range(-noise, noise)
	var t0 := Time.get_ticks_msec()
	var notes := HumTranscriber.transcribe(buf, rate)
	var ms := Time.get_ticks_msec() - t0
	var got := []
	for n in notes:
		got.append(int(round(n.midi)))
	var want := []
	for n in melody:
		want.append(n[0])
	var ok := got == want
	# quantised into song steps at 100 BPM (16th = 150 ms): starts within 1 step, same pitches
	if ok:
		var q := HumTranscriber.to_track_notes(notes, 100.0, 0, 0.0)
		var tq := 0.3
		var qok := q.size() == melody.size()
		for i in melody.size():
			if qok:
				qok = q[i].midi == melody[i][0] and absi(q[i].start - int(round(tq / 0.15))) <= 1
			tq += melody[i][1] + melody[i][2]
		if not qok:
			print("  quantise mismatch: ", q)
		ok = qok
	# timing: onsets within 40 ms of truth
	var tt := 0.3
	var worst := 0.0
	if ok:
		for i in melody.size():
			worst = maxf(worst, absf(notes[i].t0 - tt))
			tt += melody[i][1] + melody[i][2]
		ok = worst < 0.045
	print("hum %d Hz noise %.2f: want %s got %s  worst onset err %.0f ms  [%d ms for %.1f s audio]  %s" % [
		rate, noise, str(want), str(got), worst * 1000.0, ms, total, "ok" if ok else "FAIL"])
	return 0 if ok else 1


func _run_whistle() -> int:
	var rate := 44100
	var buf := PackedFloat32Array()
	buf.resize(rate * 2)
	var ph := 0.0
	for i in buf.size():
		var t := float(i) / rate
		var f := 600.0 * pow(2.0, t * 0.5 / 12.0 * 4.0 / 2.0)  # glide ~ +2 semitones over 2 s
		ph += TAU * f / rate
		buf[i] = 0.5 * sin(ph)
	var notes := HumTranscriber.transcribe(buf, rate)
	var ok := notes.size() >= 1 and notes.size() <= 4
	print("whistle glide: %d notes (expect 1-4, not dozens)  %s" % [notes.size(), "ok" if ok else "FAIL"])
	return 0 if ok else 1


func _run_silence() -> int:
	var buf := PackedFloat32Array()
	buf.resize(44100)
	for i in buf.size():
		buf[i] = _rng.randf_range(-0.003, 0.003)
	var notes := HumTranscriber.transcribe(buf, 44100)
	print("silence/noise floor: %d notes (expect 0)  %s" % [notes.size(), "ok" if notes.is_empty() else "FAIL"])
	return 0 if notes.is_empty() else 1
