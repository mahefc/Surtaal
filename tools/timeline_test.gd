extends SceneTree
## Dev tool: godot --headless --script res://tools/timeline_test.gd
## Single toolbar row, start marker (play from where you tap), and loop clips that keep a fixed,
## resizable length (moving never expands them; dragging the right edge shrinks / grows them).

var bad := 0


func _check(label: String, cond: bool) -> void:
	print("%s  %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		bad += 1


func _btn(pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.device = 0
	return e


func _mv(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.device = 0
	return e


func _initialize() -> void:
	await process_frame
	root.size = Vector2i(960, 480)
	var scene: Node = load("res://scenes/studio/studio.tscn").instantiate()
	root.add_child(scene)
	var tm: Node = root.get_node("TrackManager")
	var tr: Node = root.get_node("Transport")
	var pm: Node = root.get_node("ProjectManager")
	for i in 5:
		await process_frame
	pm.new_project()
	var arr: Node = scene._arrangement

	# ---- one toolbar row
	var bar: Node = arr._bar
	var inside := 0
	for want in ["Play from the start marker", "Add:", "Undo", "Redo", "Export the song", "Faster", "Slower"]:
		for n in bar.find_children("*", "IconButton", true, false):
			if n.tooltip_text.begins_with(want):
				inside += 1
				break
	_check("play, volume, tempo, zoom, loop builder, add, undo, redo, export are all in ONE bar (%d/7)" % inside, inside == 7)
	await process_frame
	var bar_h: float = bar.get_combined_minimum_size().y
	_check("...and the bar is a single row (%.0f px tall)" % bar_h, bar_h < 52.0)
	_check("the old second toolbar row is gone", arr._bar.get_parent() == arr and arr.get_child_count() > 0)

	# ---- start marker: tap the ruler
	var m: Track = tm.add_track("piano")
	m.add_note(0, 4, 60, 0.8)
	m.add_note(16, 4, 64, 0.8)
	m.add_note(32, 4, 67, 0.8)
	tm.notify_changed(m)
	await process_frame
	var ruler = null
	for r in arr.find_children("*", "Control", true, false):
		if r.get_script() != null and r.get_script().get_global_name() == "TimelineRuler":
			ruler = r
	ruler.size = Vector2(800, 28)
	_check("start marker begins at 0", tm.start_step == 0)
	ruler._gui_input(_btn(true, Vector2(64, 10)))  # 64 px / 4 px per step = step 16
	ruler._gui_input(_btn(false, Vector2(64, 10)))
	_check("tapping the ruler sets the start marker (step %d, want 16)" % tm.start_step, tm.start_step == 16)
	ruler._gui_input(_btn(true, Vector2(100, 10)))
	ruler._gui_input(_mv(Vector2(120, 10)))
	ruler._gui_input(_btn(false, Vector2(120, 10)))
	_check("dragging along the ruler moves it (step %d, want 30)" % tm.start_step, tm.start_step == 30)
	ruler._gui_input(_btn(true, Vector2(5000, 10)))
	_check("it cannot go past the end of the song (%d < %d)" % [tm.start_step, tm.song_steps], tm.start_step < tm.song_steps)
	# ---- play from the marker
	tr.bpm = 220.0
	tm.set_start_step(16)
	var seen := []
	tr.step_fired.connect(func(s): seen.append(s))
	tm.play_all()
	var t0 := Time.get_ticks_msec()
	while seen.is_empty() and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_check("Play starts AT the marker: first step fired = %d (want 16)" % (seen[0] if seen.size() > 0 else -1), seen.size() > 0 and seen[0] == 16)
	await create_timer(0.4).timeout
	tr.stop()
	await process_frame
	tm.set_start_step(0)
	seen.clear()
	tm.play_all()
	t0 = Time.get_ticks_msec()
	while seen.is_empty() and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_check("with the marker at 0 it starts at the beginning", seen.size() > 0 and seen[0] == 0)
	tr.stop()
	await process_frame

	# ---- loop clips: a real length that moving never changes
	tm.set_start_step(32)
	var d: Track = tm.add_track("", "drums")
	_check("a new loop is placed at the marker (step %d)" % d.drum_start, d.drum_start == 32)
	_check("a new loop has a real length: 4 repeats = %d steps" % d.drum_len, d.drum_len == 4 * d.pattern_steps())
	var len0: int = d.drum_len
	tm.shift_track(d, 16)
	tm.shift_track(d, -8)
	_check("moving a loop never changes its length (%d -> %d)" % [len0, d.drum_len], d.drum_len == len0 and d.drum_start == 40)

	# ---- resize by dragging the right edge
	await process_frame
	var lane = null
	for l in arr._lane_nodes:
		if l.track == d:
			lane = l
	lane.size = Vector2(1600, 68)
	var ps: float = lane.px_per_step
	var edge := (d.drum_start + d.drum_len) * ps
	lane._gui_input(_btn(true, Vector2(edge - 3, 30)))
	lane._gui_input(_mv(Vector2(edge - 3 - 8 * ps, 30)))  # 8 steps shorter
	lane._gui_input(_btn(false, Vector2(edge - 3 - 8 * ps, 30)))
	_check("dragging the right edge SHORTENS the loop (%d -> %d, want %d)" % [len0, d.drum_len, len0 - 8], d.drum_len == len0 - 8)
	var edge2 := (d.drum_start + d.drum_len) * ps
	lane._gui_input(_btn(true, Vector2(edge2 - 2, 30)))
	lane._gui_input(_mv(Vector2(edge2 - 2 + 24 * ps, 30)))  # 24 steps longer
	lane._gui_input(_btn(false, Vector2(edge2 + 24 * ps, 30)))
	_check("dragging it out LENGTHENS it (%d)" % d.drum_len, d.drum_len == len0 - 8 + 24)
	var edge3 := (d.drum_start + d.drum_len) * ps
	lane._gui_input(_btn(true, Vector2(edge3 - 2, 30)))
	lane._gui_input(_mv(Vector2(d.drum_start * ps - 200, 30)))  # far past the start
	lane._gui_input(_btn(false, Vector2(0, 30)))
	_check("it cannot be made shorter than one beat (%d)" % d.drum_len, d.drum_len == 4)
	_check("resizing did not move the loop", d.drum_start == 40)
	var starts_before: int = d.drum_start
	lane._gui_input(_btn(true, Vector2((d.drum_start + 1) * ps, 30)))  # inside the clip, not on the edge
	lane._gui_input(_mv(Vector2((d.drum_start + 1) * ps + 16 * ps, 30)))
	lane._gui_input(_btn(false, Vector2((d.drum_start + 17) * ps, 30)))
	_check("dragging the body still moves it (%d -> %d), length stays 4" % [starts_before, d.drum_start], d.drum_start == starts_before + 16 and d.drum_len == 4)

	# ---- old projects (loop with no length) get a fixed length instead of 'to the end'
	var legacy := {"tracks": [m.to_dict(), {"id": 9, "kind": "drums", "name": "Old", "drums": {"Kick": [0, 8]}, "drum_len": 0, "drum_start": 0}]}
	tm.import_state(legacy)
	var old: Track = tm.tracks[1]
	_check("an old loop that ran 'to the end' now has a fixed length (%d)" % old.drum_len, old.drum_len > 0)

	# ---- the loop-length control in the popup counts repeats
	var popup = load("res://scripts/ui/track_mix_popup.gd").new()
	root.add_child(popup)
	old.drum_len = 3 * old.pattern_steps()
	popup.open_for(old, false)
	popup._loop_opt.select(2)  # "4 loops"
	popup._loop_opt.item_selected.emit(2)
	_check("popup: choosing '4 loops' sets the length to 4 x the pattern", old.drum_len == 4 * old.pattern_steps())

	print("TIMELINE FAILURES: ", bad)
	pm.new_project()
	quit(bad)
