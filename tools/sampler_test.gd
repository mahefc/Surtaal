extends SceneTree
## Dev tool: godot --headless --script res://tools/sampler_test.gd
## Real-recording instruments: loads, loops seamlessly, is loudness-balanced, and plays in tune
## (including notes between recorded zones, which are repitched).

var bad := 0


func _initialize() -> void:
	await process_frame
	var im: Node = root.get_node("InstrumentManager")
	var count := 0
	for def: InstrumentDef in im.instruments:
		if def.synth != "sampler":
			continue
		count += 1
		var notes := [def.start_midi, def.start_midi + 4]  # one on a recorded zone, one repitched
		for midi in notes:
			var t0 := Time.get_ticks_msec()
			var s := SynthBaker.bake(def, midi)
			var ms := Time.get_ticks_msec() - t0
			if s == null:
				print("%-10s midi %d  BAKE FAILED" % [def.id, midi])
				bad += 1
				continue
			var ch := 2 if s.stereo else 1
			var n := s.data.size() / (2 * ch)
			var x := PackedFloat32Array()
			x.resize(n)
			var peak := 0.0
			var energy := 0.0
			var bytes := s.data  # read once: every access to .data copies the whole sample
			for i in n:
				x[i] = bytes.decode_s16(i * ch * 2) / 32768.0
				peak = maxf(peak, absf(x[i]))
				energy += x[i] * x[i]
			var gain: float = pow(10.0, float(s.get_meta("gain_db", 0.0)) / 20.0)
			var rms: float = sqrt(energy / n) * gain
			var root_midi: int = def.zone_root(midi)
			var shift_c: float = 0.0 if def.is_fixed_pitch() else float(midi - root_midi) * 100.0
			var seam := ""
			var seam_ok := true
			if s.loop_mode != AudioStreamWAV.LOOP_DISABLED:
				var max_step := 0.0
				for i in range(s.loop_begin + 1, s.loop_end):
					max_step = maxf(max_step, absf(x[i] - x[i - 1]))
				var jump := absf(x[s.loop_begin] - x[s.loop_end - 1])
				seam_ok = jump <= max_step * 1.5 + 0.01
				seam = " loop %.2f-%.2f s seam jump %.4f (max step %.4f)" % [float(s.loop_begin) / s.mix_rate, float(s.loop_end) / s.mix_rate, jump, max_step]
			var loud_ok: bool = rms > 0.05 and rms < 0.45 and (peak * gain) < 1.6
			var ok: bool = seam_ok and loud_ok and (s.format == AudioStreamWAV.FORMAT_16_BITS)
			if not ok:
				bad += 1
			print("%-10s midi %3d (zone root %3d, repitch %+4.0f c) %s %d Hz  %.1f s  gain %+5.1f dB  rms %.3f  bake %4d ms  %s%s" % [
				def.id, midi, root_midi, shift_c, "st" if ch == 2 else "mo", s.mix_rate, float(n) / s.mix_rate,
				float(s.get_meta("gain_db", 0.0)), rms, ms, "ok" if ok else "FAIL", seam])
	print("sampled instruments tested: ", count)
	print("SAMPLER FAILURES: ", bad)
	quit(bad if count > 0 else 1)
