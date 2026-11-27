extends SceneTree
## Dev tool: godot --headless --script res://tools/loop_octave_test.gd
## Octave buttons move piano keys + note grid together; the loop builder repeats a drum pattern.

var bad := 0


func _check(label: String, cond: bool) -> void:
	print("%s  %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		bad += 1


func _initialize() -> void:
	await process_frame
	var scene: Node = load("res://scenes/studio/studio.tscn").instantiate()
	root.add_child(scene)
	var tm: Node = root.get_node("TrackManager")
	var tr: Node = root.get_node("Transport")
	var pm: Node = root.get_node("ProjectManager")
	for i in 5:
		await process_frame
	pm.new_project()

	# ---- octave: keys and grid together
	var t: Track = tm.add_track("grand_piano")
	scene._open_editor(t)
	var ed: Node = scene._editor
	var keys0: int = ed._keys.first_midi
	var roll0: int = ed._roll.low_midi
	ed._shift_octave(12)
	_check("octave up moves the keys by +12 (%d -> %d)" % [keys0, ed._keys.first_midi], ed._keys.first_midi == keys0 + 12)
	_check("octave up moves the note grid by +12 (%d -> %d)" % [roll0, ed._roll.low_midi], ed._roll.low_midi == roll0 + 12)
	ed._shift_octave(-24)
	_check("octave down twice moves both by -24", ed._keys.first_midi == keys0 - 12 and ed._roll.low_midi == roll0 - 12)
	var visible: Array = ed._keys.visible_notes()
	_check("keys now span the lower octave (%d..%d)" % [visible[0], visible[-1]], visible[0] == keys0 - 12)

	# ---- loop builder
	tr.bpm = 220.0
	var d: Track = tm.add_track("", "drums")
	scene._open_editor(d)
	_check("loop builder track is named as a loop", d.name.begins_with("Drum loop"))
	_check("editor header says Loop builder", ed._title_lbl.text.begins_with("Loop builder"))
	var steps_seen := []
	tr.step_fired.connect(func(s): steps_seen.append(s))
	tm.loop_preview(d)
	var t0 := Time.get_ticks_msec()
	while not tr.playing and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_check("Play loop starts", tr.playing and tm.only == d and tr.loop and tr.loop_steps == d.pattern_steps())
	await create_timer(1.6).timeout  # 220 BPM: 16 steps = 1.09 s, so it must wrap at least once
	var wrapped := false
	for i in range(1, steps_seen.size()):
		if steps_seen[i] < steps_seen[i - 1]:
			wrapped = true
	_check("the loop repeats (%d steps seen, wrapped=%s)" % [steps_seen.size(), wrapped], wrapped and tr.playing)
	# editing while it plays: add a layer, loop keeps running
	tm.add_drum_lane(d, "dhol")
	await create_timer(0.3).timeout
	_check("editing the loop while it plays keeps it running", tr.playing)
	tm.loop_preview(d)  # tap again = stop
	await create_timer(0.2).timeout
	_check("tapping again stops it and restores the song state", not tr.playing and tm.only == null and tr.loop)

	# ---- home screen entry point exists
	var has_loop_btn := false
	for n in scene._arrangement.find_children("*", "IconButton", true, false):
		if n.tooltip_text.begins_with("Add:"):
			has_loop_btn = true
	_check("home screen has the + button (it offers the loop builder)", has_loop_btn)

	print("LOOP/OCTAVE FAILURES: ", bad)
	pm.new_project()
	quit(bad)
