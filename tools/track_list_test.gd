extends SceneTree
## Dev tool: godot --headless --script res://tools/track_list_test.gd
## Track list: reorder, repeat (loop) a tune, duplicate, delete+undo, drag/move a clip with
## mouse and touch gestures, and the loop builder's top toolbar.

var bad := 0
var taps := 0


func _check(label: String, cond: bool) -> void:
	print("%s  %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		bad += 1


func _mouse(pressed: bool, pos: Vector2, device: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.device = device
	return e


func _motion(pos: Vector2, device: int) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.device = device
	return e


func _starts(t: Track) -> Array:
	var s := []
	for n in t.notes:
		s.append(n.start)
	s.sort()
	return s


func _initialize() -> void:
	await process_frame
	var scene: Node = load("res://scenes/studio/studio.tscn").instantiate()
	root.size = Vector2i(960, 480)  # the headless window defaults to a square: use a landscape phone
	root.add_child(scene)
	var tm: Node = root.get_node("TrackManager")
	var pm: Node = root.get_node("ProjectManager")
	for i in 5:
		await process_frame
	pm.new_project()

	var a: Track = tm.add_track("piano")
	a.add_note(0, 4, 60, 0.8)
	a.add_note(8, 4, 64, 0.8)
	var b: Track = tm.add_track("bansuri")
	b.add_note(0, 4, 72, 0.8)
	var c: Track = tm.add_track("", "drums")
	tm.notify_changed(a)
	await process_frame

	# ---- reorder
	tm.move_track(b, -1)
	_check("move up: order is B, A, drums", tm.tracks[0] == b and tm.tracks[1] == a and tm.tracks[2] == c)
	tm.move_track(b, -1)
	_check("moving the first track up does nothing", tm.tracks[0] == b)
	tm.move_track(c, 1)
	_check("moving the last track down does nothing", tm.tracks[2] == c)
	tm.move_track(b, 1)
	_check("move down: order is A, B, drums", tm.tracks[0] == a and tm.tracks[1] == b)

	# ---- drag the end handle right: the tune repeats to fill the space, ending exactly where it was dropped
	tm.trim_track(a, 36)
	_check("stretching to 36 repeats the 12-step tune: %s" % str(_starts(a)), _starts(a) == [0, 8, 12, 20, 24, 32] and tm.clip_end(a) == 36)
	_check("song length grew to fit (%d steps)" % tm.song_steps, tm.song_steps == 48)
	tm.trim_track(a, 10)
	_check("dragging it back cuts the clip exactly there: %s" % str(_starts(a)), _starts(a) == [0, 8] and tm.clip_end(a) == 10)

	# ---- duplicate
	var d: Track = tm.duplicate_track(b)
	_check("duplicate: placed right after, unique id and name", tm.tracks[tm.tracks.find(b) + 1] == d and d.id != b.id and d.name != b.name and d.notes.size() == b.notes.size())

	# ---- delete + undo
	pm.flush()
	var count_before: int = tm.tracks.size()
	tm.remove_track(d)
	pm.flush()
	_check("delete removes the track", tm.tracks.size() == count_before - 1)
	pm.undo()
	_check("undo brings the deleted track back", tm.tracks.size() == count_before)
	var ida: int = a.id
	var idc: int = c.id
	for tr in tm.tracks:  # undo rebuilt the tracks from saved state: re-fetch them
		if tr.id == ida:
			a = tr
		if tr.id == idc:
			c = tr

	# ---- header buttons exist on every row
	await process_frame
	var tooltips := []
	for n in scene._arrangement.find_children("*", "IconButton", true, false):
		tooltips.append(n.tooltip_text)
	for want in ["Delete this track", "Play only this track", "Solo"]:
		var found := false
		for tt in tooltips:
			found = found or tt.begins_with(want)
		_check("track list has a '%s' button" % want, found)

	var gone_ok := true
	for tt in tooltips:
		gone_ok = gone_ok and not (tt == "Mute" or tt.begins_with("Loop this tune") or tt.begins_with("Loop builder: edit") or tt.begins_with("Copy this tune"))
	_check("track rows no longer have mute / loop / copy buttons", gone_ok)

	# ---- move a clip by dragging it (mouse)
	var lanes: Array = scene._arrangement._lane_nodes
	var lane = null
	for l in lanes:
		if l.track == a:
			lane = l
	lane.tapped.connect(func(): taps += 1)
	lane.size = Vector2(800, 88)
	var before := _starts(a)
	lane._gui_input(_mouse(true, Vector2(50, 40), 0))
	lane._gui_input(_motion(Vector2(50 + 32, 40), 0))  # 32 px = 8 steps at 4 px/step
	lane._gui_input(_mouse(false, Vector2(82, 40), 0))
	var after := _starts(a)
	_check("mouse drag moves the tune 8 steps later %s -> %s" % [str(before.slice(0, 3)), str(after.slice(0, 3))], after[0] == before[0] + 8 and taps == 0)
	lane._gui_input(_mouse(true, Vector2(50, 40), 0))
	lane._gui_input(_motion(Vector2(50 - 16, 40), 0))
	lane._gui_input(_mouse(false, Vector2(34, 40), 0))
	_check("dragging back moves it earlier (snaps to beats)", _starts(a)[0] == before[0] + 4)
	lane._gui_input(_mouse(true, Vector2(50, 40), 0))
	lane._gui_input(_motion(Vector2(50 - 400, 40), 0))
	lane._gui_input(_mouse(false, Vector2(-350, 40), 0))
	_check("it can never be dragged before time 0", _starts(a)[0] == 0)

	# ---- tap opens (no move)
	taps = 0
	lane._gui_input(_mouse(true, Vector2(50, 40), 0))
	lane._gui_input(_mouse(false, Vector2(50, 40), 0))
	_check("a click without dragging is a tap (opens the track)", taps == 1)

	# ---- touch: a quick swipe scrolls (no move, no tap); hold-then-drag moves
	var s0 := _starts(a)
	taps = 0
	lane._gui_input(_mouse(true, Vector2(50, 40), InputEvent.DEVICE_ID_EMULATION))
	lane._gui_input(_motion(Vector2(90, 40), InputEvent.DEVICE_ID_EMULATION))
	lane._gui_input(_mouse(false, Vector2(90, 40), InputEvent.DEVICE_ID_EMULATION))
	_check("touch swipe = scroll: tune does not move and no tap", _starts(a) == s0 and taps == 0)
	lane._gui_input(_mouse(true, Vector2(50, 40), InputEvent.DEVICE_ID_EMULATION))
	await create_timer(0.5).timeout  # long-press picks the tune up
	_check("touch long-press picks the tune up", lane._grabbed)
	lane._gui_input(_motion(Vector2(66, 40), InputEvent.DEVICE_ID_EMULATION))  # +16 px = 4 steps
	lane._gui_input(_mouse(false, Vector2(66, 40), InputEvent.DEVICE_ID_EMULATION))
	_check("touch hold + drag moves it 4 steps", _starts(a)[0] == s0[0] + 4 and taps == 0)

	# ---- loop builder toolbar on top
	var ed: Node = scene._editor
	scene._open_editor(c)
	await process_frame
	await process_frame
	_check("loop builder: controls are a horizontal toolbar in the main area (top)", ed._tools.get_parent() == ed._left and ed._left.get_child(0) == ed._tools)
	_check("loop builder: the side column is gone (grid gets the full width)", ed._side.get_parent() == null)
	var tools_h: float = ed._tools.get_combined_minimum_size().y
	_check("toolbar is one row (%.0f px tall)" % tools_h, tools_h < 60.0)
	scene._open_editor(a)
	await process_frame
	_check("instrument editor uses the same top toolbar", ed._tools.get_parent() == ed._left and ed._side.get_parent() == null)

	print("TRACK LIST FAILURES: ", bad)
	pm.new_project()
	quit(bad)
