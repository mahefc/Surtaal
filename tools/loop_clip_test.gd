extends SceneTree
## Dev tool: godot --headless --script res://tools/loop_clip_test.gd
## Loop clips can be moved in time and given a length; per-track reverb; the mix popup;
## slimmer track rows; the instrument editor's top toolbar.

var bad := 0
var played := 0


func _check(label: String, cond: bool) -> void:
	print("%s  %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		bad += 1


func _initialize() -> void:
	await process_frame
	root.size = Vector2i(960, 480)
	var scene: Node = load("res://scenes/studio/studio.tscn").instantiate()
	root.add_child(scene)
	var tm: Node = root.get_node("TrackManager")
	var pm: Node = root.get_node("ProjectManager")
	var eng: Node = root.get_node("AudioEngine")
	for i in 5:
		await process_frame
	pm.new_project()
	eng.note_played.connect(func(_d, _m, _s): played += 1)

	var m: Track = tm.add_track("grand_piano")
	m.add_note(0, 4, 60, 0.8)
	m.add_note(48, 4, 64, 0.8)
	var d: Track = tm.add_track("", "drums")
	tm.notify_changed(m)
	await process_frame

	# ---- loop clips: start position
	_check("a new loop starts at 0 with a real length", d.drum_start == 0 and d.drum_len == 64)
	var applied: int = tm.shift_track(d, 16)
	_check("a loop clip can be moved in time (+16 steps)", applied == 16 and d.drum_start == 16)
	_check("...never before 0", tm.shift_track(d, -100) == -16 and d.drum_start == 0)
	tm.shift_track(d, 16)
	m.muted = true  # judge the loop on its own: keep the piano out of the count
	tm.mix_changed()
	played = 0
	tm._on_step(0)
	_check("before its start the loop is silent", played == 0)
	tm._on_step(16)
	_check("from its start the loop plays (%d hits)" % played, played > 0)

	# ---- loop clips: length
	d.drum_len = 32
	tm.notify_changed(d)
	played = 0
	tm._on_step(16 + 32)
	_check("after its length the loop stops", played == 0)
	played = 0
	tm._on_step(16 + 16)
	_check("inside its length it still plays", played > 0)
	d.drum_len = 200
	tm.notify_changed(d)
	_check("a long loop extends the song (%d steps)" % tm.song_steps, tm.song_steps >= 224)
	d.drum_len = 64
	tm.notify_changed(d)
	m.muted = false
	tm.mix_changed()

	# ---- loop clip drag on the timeline
	var lane = null
	for l in scene._arrangement._lane_nodes:
		if l.track == d:
			lane = l
	lane.size = Vector2(800, 68)
	var start0: int = d.drum_start
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(300, 30)
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(300 + 32, 30)
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = Vector2(332, 30)
	lane._gui_input(press)
	lane._gui_input(mv)
	lane._gui_input(rel)
	_check("dragging a loop clip moves it (%d -> %d)" % [start0, d.drum_start], d.drum_start == start0 + 8)

	# ---- persistence
	d.reverb = 0.6
	d.drum_len = 64
	var back := Track.from_dict(JSON.parse_string(JSON.stringify(d.to_dict())))
	_check("loop start / length / reverb survive save+load", back.drum_start == d.drum_start and back.drum_len == 64 and absf(back.reverb - 0.6) < 0.01)
	d.drum_len = 64

	# ---- per-track reverb
	d.reverb = 0.5
	tm.mix_changed()
	var idx := AudioServer.get_bus_index(tm.bus_of(d))
	var rv := AudioServer.get_bus_effect(idx, 1) as AudioEffectReverb
	_check("each track has its own reverb (wet %.2f)" % rv.wet, rv != null and absf(rv.wet - 0.5) < 0.01 and AudioServer.is_bus_effect_enabled(idx, 1))
	d.reverb = 0.0
	tm.mix_changed()
	_check("reverb at 0 switches the effect off (no CPU)", not AudioServer.is_bus_effect_enabled(idx, 1))
	d.reverb = 0.22
	tm.mix_changed()

	# ---- mix popup (volume / pan / reverb live there now)
	var popup = load("res://scripts/ui/track_mix_popup.gd").new()
	root.add_child(popup)
	popup.open_for(m, false)
	popup._vol.value = 0.3
	popup._pan.value = 0.7
	popup._rev.value = 0.4
	_check("popup sets volume / pan / reverb on the track", absf(m.volume - 0.3) < 0.01 and absf(m.pan - 0.7) < 0.01 and absf(m.reverb - 0.4) < 0.01)
	_check("popup shows the loop-length control only for loops", not popup._loop_box.visible)
	popup.open_for(d, false)
	_check("...and it is there for a loop track", popup._loop_box.visible)
	popup.open_for(m, true)
	_check("minimal mode shows only reverb", popup._rev_row.visible and not popup._vol_row.visible and not popup._pan_row.visible and not popup._time_box.visible)
	popup.hide()

	# ---- slimmer rows: no volume / pan sliders on the rows
	await process_frame
	var sliders: Array = scene._arrangement._heads.find_children("*", "HSlider", true, false)
	_check("track rows have no sliders any more (%d)" % sliders.size(), sliders.is_empty())

	# ---- instrument editor: top toolbar, no reverb button and no sound panel
	var ed: Node = scene._editor
	scene._open_editor(m)
	await process_frame
	await process_frame
	_check("instrument editor: toolbar runs along the top", ed._tools.get_parent() == ed._left and ed._left.get_child(0) == ed._tools)
	_check("instrument editor: no side column", ed._side.get_parent() == null)
	var tips := []
	for n in ed.find_children("*", "IconButton", true, false):
		tips.append(n.tooltip_text)
	var has_reverb := false
	var has_sound := false
	for tt in tips:
		has_reverb = has_reverb or tt == "Reverb" or tt.begins_with("Reverb for this track")
		has_sound = has_sound or tt.begins_with("Sound:")
	_check("the note editor has no reverb button and no sound panel", not has_reverb and not has_sound)
	var tools_h: float = ed._tools.get_combined_minimum_size().y
	_check("toolbar is one row (%.0f px)" % tools_h, tools_h < 60.0)
	_check("Record and Play sit in the toolbar", ed._rec_btn.get_parent() == ed._tools and ed._hear_btn.get_parent() == ed._tools)

	print("LOOP CLIP FAILURES: ", bad)
	pm.new_project()
	quit(bad)
