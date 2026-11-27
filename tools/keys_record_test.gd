extends SceneTree
## Dev tool: godot --headless --script res://tools/keys_record_test.gd
## Drives the real TrackEditor "record by keys" flow in real time at 100 BPM
## (beat = 0.6 s, 16th = 0.15 s): count-in, timed key presses, stop -> notes.

func _initialize() -> void:
	await process_frame
	var scene: Node = load("res://scenes/studio/studio.tscn").instantiate()
	root.add_child(scene)
	var tm: Node = root.get_node("TrackManager")
	var tr: Node = root.get_node("Transport")
	for i in 5:
		await process_frame
	tr.bpm = 100.0
	var t: Track = tm.add_track("grand_piano")
	scene._open_editor(t)
	var ed: Node = scene._editor
	ed._set_source(true)
	ed._start_recording()  # what the "Piano" choice in the Record popup does: 4-beat count-in
	var t0 := Time.get_ticks_msec()
	while ed._rec != 2 and Time.get_ticks_msec() - t0 < 6000:
		await process_frame
	print("count-in finished after %.2f s (expect ~2.4), state=%d" % [(Time.get_ticks_msec() - t0) / 1000.0, ed._rec])
	var rec_t0 := Time.get_ticks_msec()

	# (midi, press at s, hold s)
	var plan := [[48, 0.6, 0.3], [52, 1.2, 0.6], [55, 1.8, 0.3], [59, 1.8, 0.3]]
	var events := []
	for n in plan:
		events.append([n[1], true, n[0]])
		events.append([n[1] + n[2], false, n[0]])
	events.sort_custom(func(a, b): return a[0] < b[0])
	for e in events:
		while (Time.get_ticks_msec() - rec_t0) / 1000.0 < e[0]:
			await process_frame
		var tc := Time.get_ticks_usec()
		if e[1]:
			ed._on_key_pressed(e[2], 0.8)
			print("  press %d at %.3f s took %.1f ms, cached=%s" % [e[2], (Time.get_ticks_msec() - rec_t0) / 1000.0, (Time.get_ticks_usec() - tc) / 1000.0, root.get_node("SampleManager").has_sample(ed.def, e[2], 0)])
		else:
			ed._on_key_released(e[2])
	while (Time.get_ticks_msec() - rec_t0) / 1000.0 < 2.5:
		await process_frame
	ed._on_record_pressed()  # stop

	var got := []
	for n in t.notes:
		got.append([n.start, n.len, n.midi])
	got.sort()
	var want := [[4, 2, 48], [8, 4, 52], [12, 2, 55], [12, 2, 59]]
	var ok: bool = got == want and ed._rec == 0
	print("keys recording: want %s got %s  %s" % [str(want), str(got), "ok" if ok else "FAIL"])

	# cancel during count-in must record nothing
	var before := t.notes.size()
	ed._start_recording()
	await create_timer(0.7).timeout
	ed._on_record_pressed()  # Cancel
	await create_timer(0.2).timeout
	var cancelled: bool = ed._rec == 0 and t.notes.size() == before
	print("cancel during count-in: idle=%s, notes unchanged=%s  %s" % [ed._rec == 0, t.notes.size() == before, "ok" if cancelled else "FAIL"])
	quit(0 if (ok and cancelled) else 1)
