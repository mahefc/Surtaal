extends SceneTree
## Dev tool: godot --headless --script res://tools/voice_enhancer_test.gd
## A raw take with DC offset, low rumble, hiss between phrases and uneven loudness must come out
## clean: no DC, rumble gone, hiss reduced, phrases levelled, -1 dBFS peak, nothing clipped,
## and the pitch (the voice itself) untouched.

const RATE := 48000
var bad := 0


func _check(label: String, cond: bool) -> void:
	print("%s  %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		bad += 1


func _rms(x: PackedFloat32Array, a: float, b: float) -> float:
	var i0 := int(a * RATE)
	var i1 := mini(int(b * RATE), x.size())
	var e := 0.0
	for i in range(i0, i1):
		e += x[i] * x[i]
	return sqrt(e / maxf(i1 - i0, 1))


func _freq(x: PackedFloat32Array, a: float, b: float) -> float:
	var zc := 0
	var i0 := int(a * RATE)
	var i1 := mini(int(b * RATE), x.size())
	for i in range(i0 + 1, i1):
		if x[i - 1] <= 0.0 and x[i] > 0.0:
			zc += 1
	return float(zc) / ((i1 - i0) / float(RATE))


func _median_f0(x: PackedFloat32Array) -> float:
	var tr := PitchTracker.track(x, RATE)
	var f: PackedFloat32Array = tr.f0
	var v := []
	for a in f:
		if a > 0.0:
			v.append(a)
	v.sort()
	return float(v[v.size() / 2]) if v.size() > 0 else -1.0


func _initialize() -> void:
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var raw := PackedFloat32Array()
	raw.resize(RATE * 4)
	for i in raw.size():
		var t := float(i) / RATE
		var v := 0.05  # DC offset
		v += 0.10 * sin(TAU * 40.0 * t)  # rumble
		v += rng.randf_range(-0.012, 0.012)  # hiss
		if t >= 0.5 and t < 1.5:  # loud phrase (220 Hz)
			v += 0.40 * sin(TAU * 220.0 * t)
		if t >= 2.5 and t < 3.5:  # soft phrase (220 Hz)
			v += 0.08 * sin(TAU * 220.0 * t)
		raw[i] = v
	var t0 := Time.get_ticks_msec()
	var out := VoiceEnhancer.process(raw, RATE)
	print("processed %.1f s of audio in %d ms" % [raw.size() / float(RATE), Time.get_ticks_msec() - t0])

	var dc := 0.0
	for v in out:
		dc += v
	dc /= out.size()
	_check("DC offset removed (mean %.4f, was 0.05)" % dc, absf(dc) < 0.005)
	var hiss_before := _rms(raw, 1.8, 2.3)
	var hiss_after := _rms(out, 1.8, 2.3)
	var loud_before := _rms(raw, 0.7, 1.3)
	var loud_after := _rms(out, 0.7, 1.3)
	var soft_after := _rms(out, 2.7, 3.3)
	var snr_before := 20.0 * log(loud_before / hiss_before) / log(10.0)
	var snr_after := 20.0 * log(loud_after / maxf(hiss_after, 1e-6)) / log(10.0)
	_check("noise between phrases reduced: signal-to-noise %.0f -> %.0f dB (gain of %.0f dB)" % [snr_before, snr_after, snr_after - snr_before], snr_after - snr_before >= 8.0)
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	_check("level matched to about -1 dBFS (peak %.3f) and never clips" % peak, peak > 0.8 and peak <= 0.95)
	var ratio_before := _rms(raw, 2.7, 3.3) / _rms(raw, 0.7, 1.3)
	var ratio_after := soft_after / loud_after
	_check("loud and soft phrases are closer in level (soft/loud %.2f -> %.2f)" % [ratio_before, ratio_after], ratio_after > ratio_before * 1.5)
	var f_before := _median_f0(raw)
	var f_after := _median_f0(out)
	_check("the voice's pitch is untouched (%.1f Hz -> %.1f Hz, was sung at 220)" % [f_before, f_after], absf(f_after - 220.0) < 2.0 and absf(f_before - f_after) < 1.5)
	var rumble := _rms(out, 3.7, 3.95) / _rms(raw, 3.7, 3.95)
	_check("40 Hz rumble is attenuated (x%.2f)" % rumble, rumble < 0.6)
	var finite := true
	for v in out:
		finite = finite and not is_nan(v) and not is_inf(v)
	_check("no NaN / infinite samples", finite)
	print("VOICE ENHANCER FAILURES: ", bad)
	quit(bad)
