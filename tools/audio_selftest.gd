extends SceneTree
## Dev tool: godot --headless --path . --script res://tools/audio_selftest.gd
## Bakes every instrument at several notes; verifies no silence/NaN and measures
## fundamental frequency by autocorrelation (pitched instruments only).

func _initialize() -> void:
	await process_frame
	var im: Node = root.get_node("InstrumentManager")
	if im.instruments.is_empty():
		push_error("no instruments loaded")
		quit(1)
		return
	var failures := 0
	for def: InstrumentDef in im.instruments:
		for midi in [def.start_midi, def.start_midi + 7, def.start_midi + 12]:
			var t0 := Time.get_ticks_usec()
			var s := SynthBaker.bake(def, midi)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var ch := 2 if s.stereo else 1
			var n := s.data.size() / (2 * ch)
			var x := PackedFloat32Array()  # left channel
			x.resize(n)
			var peak := 0.0
			var energy := 0.0
			var cross := 0.0
			var e_l := 0.0
			var e_r := 0.0
			for i in n:
				x[i] = s.data.decode_s16(i * ch * 2) / 32768.0
				peak = maxf(peak, absf(x[i]))
				energy += x[i] * x[i]
				if ch == 2:
					var r := s.data.decode_s16(i * 4 + 2) / 32768.0
					cross += x[i] * r
					e_l += x[i] * x[i]
					e_r += r * r
			var max_d := 0.0
			for i in range(1, n):
				max_d = maxf(max_d, absf(x[i] - x[i - 1]))
			var rms := sqrt(energy / n)
			var gain_lin := pow(10.0, float(s.get_meta("gain_db", 0.0)) / 20.0)  # sampled instruments are balanced by the engine
			rms *= gain_lin
			peak *= gain_lin
			max_d *= gain_lin
			var corr := cross / maxf(sqrt(e_l * e_r), 1e-9) if ch == 2 else 1.0
			var target := SynthBaker.midi_to_freq(def.zone_root(midi))
			var est := _f0(x, target) if not (def.is_percussive() or def.is_fixed_pitch()) else -1.0
			var cents := 1200.0 * log(est / target) / log(2.0) if est > 0.0 else 0.0
			var seam_ok := true
			var seam_txt := ""
			if s.loop_mode != AudioStreamWAV.LOOP_DISABLED:
				# The jump when wrapping loop_end -> loop_begin must look like an ordinary sample step.
				var max_step := 0.0
				for i in range(s.loop_begin + 1, s.loop_end):
					max_step = maxf(max_step, absf(x[i] - x[i - 1]))
				var jump := absf(x[s.loop_begin] - x[s.loop_end - 1])
				seam_ok = jump <= max_step * 1.5 + 0.01
				seam_txt = " loop seam jump %.3f (max step %.3f)" % [jump, max_step]
			var ok := seam_ok and peak > 0.2 and rms > 0.02 and rms < 0.3 and max_d > 0.002  # flat = NaN/DC blow-up and (est < 0.0 or absf(cents) < 35.0)  # integer-lag autocorrelation resolves ~20 cents at 520 Hz
			if not ok:
				failures += 1
			print("%-12s midi %3d (root %3d) %s  peak %.2f rms %.3f  est %7.1f Hz err %+6.1f c  L/R corr %.2f  bake %5.0f ms  %s%s" % [
				def.id, midi, def.zone_root(midi), "st" if ch == 2 else "mo", peak, rms, est, cents, corr, ms, "ok" if ok else "FAIL", seam_txt])
	failures += _test_tuning(im)
	failures += _test_project(im)
	failures += await _test_sequencer(im)
	print("FAILURES: ", failures)
	quit(failures)


func _check(label: String, cond: bool) -> int:
	print("%s  %s" % [label, "ok" if cond else "FAIL"])
	return 0 if cond else 1


## Tracks, save/load round-trip, undo/redo.
func _test_project(im: Node) -> int:
	var pm: Node = root.get_node("ProjectManager")
	var tm: Node = root.get_node("TrackManager")
	var tn: Node = root.get_node("TuningManager")
	var tr: Node = root.get_node("Transport")
	var bad := 0
	pm.new_project()
	var base: String = JSON.stringify(pm.content_state())
	bad += _check("project: starts with no tracks", tm.tracks.is_empty())

	var t: Track = tm.add_track("bansuri")
	t.add_note(4, 2, 67, 0.6)
	t.add_note(20, 3, 72, 0.9)
	t.preset = 1
	var d: Track = tm.add_track("", "drums")
	tm.notify_changed(t)
	tn.set_tuning(5)
	tn.set_root(2)
	tr.bpm = 132.0
	pm.flush()
	var edited: String = JSON.stringify(pm.content_state())
	bad += _check("project: edits change state", edited != base)
	bad += _check("tracks: unique names + drum starter", tm.tracks.size() == 2 and d.has_content())

	pm.rename("selftest proj")
	bad += _check("project: save", pm.save())
	pm.new_project()
	bad += _check("project: new resets state", JSON.stringify(pm.content_state()) == base)
	bad += _check("project: listed", "selftest proj" in pm.list_projects())
	bad += _check("project: open", pm.open_project("selftest proj"))
	bad += _check("project: content round-trips exactly", JSON.stringify(pm.content_state()) == edited)
	bad += _check("project: tracks restored (notes, preset, auto length)",
		tm.tracks.size() == 2 and tm.tracks[0].notes.size() == 2 and tm.tracks[0].preset == 1 and tm.song_steps == 32)

	tm.tracks[0].add_note(8, 1, 60, 0.9)
	tm.notify_changed(tm.tracks[0])
	pm.flush()
	var after_add: String = JSON.stringify(pm.content_state())
	pm.undo()
	bad += _check("undo restores previous content", JSON.stringify(pm.content_state()) == edited)
	pm.redo()
	bad += _check("redo reapplies edit", JSON.stringify(pm.content_state()) == after_add)
	tm.remove_track(tm.tracks[1])
	pm.flush()
	pm.undo()
	bad += _check("undo brings a deleted track back", tm.tracks.size() == 2)

	pm.delete_project("selftest proj")
	bad += _check("project: delete", not ("selftest proj" in pm.list_projects()))
	pm.new_project()
	tn.set_tuning(0)
	tn.set_root(0)
	return bad

func _test_tuning(_im: Node) -> int:
	var tm: Node = root.get_node("TuningManager")
	var bad := 0
	tm.set_tuning(4)  # Raga Bhairav, Sa = C
	tm.set_root(0)
	# Pa = pure fifth = +1.955 cents; komal Re = 16/15 = -(100-111.73) -> +11.73; Ga = 5/4 -> -13.69
	var expect := {67: 1.955, 61: 11.73, 64: -13.69, 60: 0.0}
	for midi in expect:
		var got: float = tm.offset_cents(midi)
		var ok := absf(got - expect[midi]) < 0.05
		if not ok:
			bad += 1
		print("tuning Bhairav midi %d offset %+.2f cents (expect %+.2f) %s" % [midi, got, expect[midi], "ok" if ok else "FAIL"])
	tm.set_root(2)  # Sa = D: degrees move with Sa
	var got2: float = tm.offset_cents(62 + 7)  # Pa above D
	print("tuning Sa=D, Pa offset %+.2f %s" % [got2, "ok" if absf(got2 - 1.955) < 0.05 else "FAIL"])
	if absf(got2 - 1.955) >= 0.05:
		bad += 1
	tm.set_tuning(0)
	tm.set_root(0)
	return bad


func _test_sequencer(im: Node) -> int:
	var tr: Node = root.get_node("Transport")
	var tm: Node = root.get_node("TrackManager")
	var eng: Node = root.get_node("AudioEngine")
	var sm: Node = root.get_node("SampleManager")
	root.get_node("ProjectManager").new_project()
	var mel: Track = tm.add_track("grand_piano")
	mel.add_note(0, 4, 60, 0.8)
	mel.add_note(20, 4, 64, 0.8)  # ends at step 24 -> the song loops every 32 steps
	tm.notify_changed(mel)
	var t: Track = tm.add_track("", "drums")
	await tm.prepare()  # exactly what play_all() does: render every note before the clock starts
	for lane in t.drum_lanes:  # pre-bake so timing is not affected by synth cost
		sm.get_sample(im.get_by_id(lane.id), lane.midi)
	var fired := []
	tr.step_fired.connect(func(s): fired.append(s))
	tr.bpm = 220.0  # 16th = 68 ms
	tr.start()
	var peak_voices := 0
	var t_end := Time.get_ticks_msec() + 2400
	while Time.get_ticks_msec() < t_end:
		await process_frame
		peak_voices = maxi(peak_voices, eng.active_voices())
	tr.stop()
	var in_order := true
	var wrapped := false
	for i in range(1, fired.size()):
		if fired[i] != (fired[i - 1] + 1) % 32:
			in_order = false
		if fired[i] < fired[i - 1]:
			wrapped = true
	var ok: bool = fired.size() >= 30 and in_order and wrapped and peak_voices >= 2
	print("sequencer: %d steps in 2.4 s @220 BPM, in order=%s, loops at song end=%s, peak voices=%d  %s" % [
		fired.size(), in_order, wrapped, peak_voices, "ok" if ok else "FAIL"])
	root.get_node("ProjectManager").new_project()
	return 0 if ok else 1

## Autocorrelation peak near the expected period, on a window after the attack.
func _f0(x: PackedFloat32Array, target: float) -> float:
	var rate := SynthBaker.RATE
	var start := int(0.25 * rate)
	var win := 4096
	if start + win + rate / 50 >= x.size():
		start = 0
	var lo := int(rate / (target * 1.06))
	var hi := int(rate / (target * 0.94))
	var best := -1.0
	var best_lag := 0
	for lag in range(lo, hi + 1):
		var acc := 0.0
		for i in win:
			acc += x[start + i] * x[start + i + lag]
		if acc > best:
			best = acc
			best_lag = lag
	return float(rate) / best_lag if best_lag > 0 else -1.0