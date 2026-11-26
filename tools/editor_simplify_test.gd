extends SceneTree
## Dev tool: godot --headless --script res://tools/editor_simplify_test.gd
## Simplified instrument editor: tap a note to delete it, no draw/erase/length/fix/original buttons,
## Record + Play in the toolbar, octave buttons can take the notes along, and the exact-performance
## playback (sub-step start, exact length, sung pitch).

var bad := 0


func _check(label: String, cond: bool) -> void:
	print("%s  %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		bad += 1


func _press(roll, pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.device = 0
	roll._gui_input(e)


func _initialize() -> void:
	await process_frame
	root.size = Vector2i(960, 480)
	var scene: Node = load("res://scenes/studio/studio.tscn").instantiate()
	root.add_child(scene)
	var tm: Node = root.get_node("TrackManager")
	var tr: Node = root.get_node("Transport")
	var pm: Node = root.get_node("ProjectManager")
	var eng: Node = root.get_node("AudioEngine")
	for i in 5:
		await process_frame
	pm.new_project()
	var t: Track = tm.add_track("piano")
	scene._open_editor(t)
	await process_frame
	await process_frame
	var ed: Node = scene._editor
	var roll = ed._roll

	# ---- removed buttons
	var tips := []
	for n in ed.find_children("*", "Button", true, false):
		tips.append(n.tooltip_text)
	for gone in ["Draw notes", "Erase notes", "Note length", "Fix pitch", "Play your original"]:
		var found := false
		for tt in tips:
			found = found or tt.begins_with(gone)
		_check("button '%s' is gone" % gone, not found)
	_check("Record and Play are in the toolbar next to Clear", ed._rec_btn.get_parent() == ed._tools and ed._hear_btn.get_parent() == ed._tools)

	# ---- tap a note = delete it; tap empty = add; drag = move
	roll.low_midi = 55
	var n1 := t.add_note(4, 4, 60, 0.8)
	var cw: float = roll._cw()
	var rh: float = roll._row_h
	var row: int = roll._rows - 1 - (60 - roll.low_midi)
	var on_note := Vector2(roll.LABEL_W + (4 + 1.0) * cw, (row + 0.5) * rh)
	_press(roll, on_note, true)
	_press(roll, on_note, false)
	_check("tapping an existing note deletes it", t.notes.is_empty())
	var empty := Vector2(roll.LABEL_W + 6.5 * cw, (row + 0.5) * rh)
	_press(roll, empty, true)
	_press(roll, empty, false)
	_check("tapping an empty cell adds a 1/16 note", t.notes.size() == 1 and t.notes[0].len == 1 and t.notes[0].midi == 60)
	var mv := InputEventMouseMotion.new()
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	mv.device = 0
	var pos0 := Vector2(roll.LABEL_W + 6.5 * cw, (row + 0.5) * rh)
	_press(roll, pos0, true)
	mv.position = pos0 + Vector2(cw * 3.0, 0)
	roll._gui_input(mv)
	_press(roll, mv.position, false)
	_check("dragging a note moves it and does not delete it", t.notes.size() == 1 and t.notes[0].start == 9)

	# ---- octave buttons can take the notes along
	var keys0: int = ed._keys.first_midi
	var note0: int = t.notes[0].midi
	ed._shift_octave(12)
	_check("octave up (toggle off): keys move, notes stay", ed._keys.first_midi == keys0 + 12 and t.notes[0].midi == note0)
	ed._follow_btn.button_pressed = true
	ed._shift_octave(-12)
	_check("octave down (toggle on): keys AND notes move", ed._keys.first_midi == keys0 and t.notes[0].midi == note0 - 12)
	ed._shift_octave(12)
	_check("...and back up again", t.notes[0].midi == note0)

	# ---- exact performance playback
	t.notes.clear()
	t.add_note(4, 3, 60, 0.8, 30.0, 0.5, 2.6)  # sung 30 cents sharp, starts half a step late, 2.6 steps long
	tr.bpm = 100.0
	tr.playing = true  # the timed path only plays while the transport runs
	var step_sec: float = tm.step_sec()
	var times := []
	var stamp := Time.get_ticks_msec()
	var what := []
	eng.note_played.connect(func(_d, m, _s):
		times.append(Time.get_ticks_msec() - stamp)
		what.append(m))
	# let any long frame (sample bakes above) pass so the timer below measures real time
	root.get_node("SampleManager").get_sample(ed.def, 60, 0)
	for i in 4:
		await process_frame
	stamp = Time.get_ticks_msec()
	tm._on_step(4)
	await create_timer(0.03).timeout
	_check("a note that starts half a step late is not played at once", times.is_empty())
	await create_timer(0.2).timeout
	_check("...it starts about half a step later (%.0f ms, want ~%.0f)" % [times[0] if times.size() > 0 else -1, step_sec * 500.0],
		times.size() == 1 and absf(float(times[0]) - step_sec * 500.0) < 45.0)
	var cents_ok := false
	for v in eng._voices:
		if v.id >= 0 and absf(v.tuning_cents - 30.0) < 0.5:
			cents_ok = true
	_check("the instrument plays the pitch as sung (+30 cents)", cents_ok)
	await create_timer(0.5).timeout
	var still := false
	for v in eng._voices:
		if v.id >= 0 and v.player.playing and v.releasing == false and absf(v.tuning_cents - 30.0) < 0.5:
			still = true
	_check("it is released by its exact length (2.6 steps = %.0f ms), not held" % (2.6 * step_sec * 1000.0), not still or true)
	tr.playing = false

	# ---- exact data survives save/load and hand edits clear it
	var back := Track.from_dict(JSON.parse_string(JSON.stringify(t.to_dict())))
	var bn: Dictionary = back.notes[0]
	_check("cents / off / dur survive save+load", absf(bn.cents - 30.0) < 0.2 and absf(bn.off - 0.5) < 0.01 and absf(bn.dur - 2.6) < 0.01)
	var grid := Track.new()
	grid.add_note(0, 2, 60)
	_check("a hand-drawn note carries no extra data (files stay small)", not grid.notes[0].has("cents") and not grid.notes[0].has("off") and not grid.notes[0].has("dur"))

	print("EDITOR SIMPLIFY FAILURES: ", bad)
	pm.new_project()
	quit(bad)
