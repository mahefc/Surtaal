extends SceneTree
## Dev tool: godot --headless --script res://tools/voice_track_test.gd
## One + button that asks Instrument / Loop / Voice; thin rows without arrows or header volume/time;
## voice (audio) tracks: record -> studio clean-up -> play on the timeline from where the marker is;
## trim handles on instrument and voice clips.

const RATE := 48000
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
	var rm: Node = root.get_node("RecordingManager")
	for i in 5:
		await process_frame
	pm.new_project()
	var arr: Node = scene._arrangement

	# ---- header: no master volume, no time readout; ONE add button that asks what to add
	_check("header has no volume slider", arr._bar.find_children("*", "HSlider", true, false).is_empty())
	var tips := []
	for n in arr.find_children("*", "IconButton", true, false):
		tips.append(n.tooltip_text)
	var add_buttons := 0
	for tt in tips:
		if tt.begins_with("Add:"):
			add_buttons += 1
		_check_not_loop_button(tt)
	_check("exactly ONE add button (and no separate loop button): %d" % add_buttons, add_buttons == 1)
	var got := []
	arr.add_instrument_requested.connect(func(): got.append("instrument"))
	arr.loop_builder_requested.connect(func(): got.append("loop"))
	arr.add_voice_requested.connect(func(): got.append("voice"))
	for kind in ["instrument", "loop", "voice"]:
		arr._add_popup.chosen.emit(kind)
	_check("the + chooser offers Instrument, Loop and Voice: %s" % str(got), got == ["instrument", "loop", "voice"])

	# ---- thin rows, no arrows
	var m: Track = tm.add_track("grand_piano")
	for k in 6:
		m.add_note(k * 8, 4, 60 + k, 0.8)
	tm.notify_changed(m)
	await process_frame
	var tips2 := []
	for n in arr._heads.find_children("*", "IconButton", true, false):
		if not n.tooltip_text.begins_with("Zoom"):
			tips2.append(n.tooltip_text)
	var has_arrows := false
	for tt in tips2:
		has_arrows = has_arrows or tt.begins_with("Move this track")
	_check("track rows have no up/down arrows", not has_arrows)
	_check("rows are thin (%d px)" % int(arr.ROW_H), arr.ROW_H <= 52.0)
	_check("a row is a single line: play, solo, delete, menu = 4 buttons per row (%d buttons, %d rows)" % [tips2.size(), tm.tracks.size()], tips2.size() == 4 * tm.tracks.size())

	# ---- trim an instrument clip
	pm.flush()
	var count_before: int = m.notes.size()
	tm.trim_track(m, 20)
	var left := []
	for n in m.notes:
		left.append([n.start, n.len])
	_check("trim at step 20: notes after it are gone, the crossing note is cut %s" % str(left), m.notes.size() == 3 and left[2] == [16, 4])
	m.notes.clear()
	for k in 6:
		m.add_note(k * 8, 4, 60 + k, 0.8)
	tm.notify_changed(m)
	await process_frame
	var lane = null
	for l in arr._lane_nodes:
		if l.track == m:
			lane = l
	lane.size = Vector2(1400, 50)
	var ps: float = lane.px_per_step
	var end_x: float = tm.clip_end(m) * ps  # 44 steps
	lane._gui_input(_btn(true, Vector2(end_x - 3, 25)))
	lane._gui_input(_mv(Vector2(end_x - 3 - 24 * ps, 25)))
	_check("while dragging, the clip is not cut yet (preview only)", m.notes.size() == 6)
	lane._gui_input(_btn(false, Vector2(end_x - 3 - 24 * ps, 25)))
	_check("dragging the instrument clip's trim handle cuts it short (%d notes left, end %d)" % [m.notes.size(), tm.clip_end(m)], tm.clip_end(m) <= 20 and m.notes.size() < 6)
	pm.flush()
	pm.undo()
	await process_frame
	var m2: Track = null
	for tt in tm.tracks:
		if tt.kind == "melodic":
			m2 = tt
	print("   after undo: %d tracks, melodic track has %d notes" % [tm.tracks.size(), m2.notes.size() if m2 else -1])
	_check("undo restores the trimmed notes (%d)" % (m2.notes.size() if m2 else -1), m2 != null and m2.notes.size() == 6)

	# ---- voice track
	var v: Track = tm.add_track("", "audio")
	_check("a voice track is its own kind", v.kind == "audio" and v.name.begins_with("Voice"))
	_check("empty voice track has no content", not v.has_content())
	var raw := PackedFloat32Array()
	raw.resize(RATE * 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for i in raw.size():
		var t := float(i) / RATE
		raw[i] = 0.03 + rng.randf_range(-0.01, 0.01) + (0.3 * sin(TAU * 220.0 * t) if t > 0.4 and t < 2.4 else 0.0)
	# what the voice editor does after a take: clean up, save, attach
	var clean := VoiceEnhancer.process(raw, RATE)
	var path := "user://assets/_voice_test.wav"
	_check("the cleaned take is saved as a WAV", rm.save_wav(clean, RATE, path))
	v.audio_path = path
	v.audio_dur = float(clean.size()) / RATE
	v.audio_start = 8
	tm.notify_changed(v)
	_check("it has content and a waveform after loading", v.has_content() and (tm.ensure_audio_peaks(v) == null or true) and v.audio_peaks.size() > 100)
	_check("it extends the song to fit (%d steps)" % tm.song_steps, tm.song_steps >= 8 + int(3.0 / tm.step_sec()) - 1)
	var back := Track.from_dict(JSON.parse_string(JSON.stringify(v.to_dict())))
	_check("a voice track survives save+load", back.kind == "audio" and back.audio_path == path and back.audio_start == 8 and absf(back.audio_dur - 3.0) < 0.01)

	# ---- playback on the timeline
	tr.bpm = 120.0
	var sec: float = tm.step_sec()
	tm._on_step(7)
	_check("not playing before its start step", not tm._audio.has(v.id) or not tm._audio[v.id].player.playing)
	tm._on_step(8)
	_check("starts exactly at its start step", tm._audio.has(v.id) and tm._audio[v.id].player.playing)
	tm._stop_all_audio()
	tr.started.emit()  # a new play begins with the marker in the middle of the clip
	tm._on_step(8 + 6)
	var pos: float = tm._audio[v.id].player.get_playback_position() if tm._audio.has(v.id) else -1.0
	_check("starting from the marker inside the clip plays from the matching point (%.2f s, want ~%.2f)" % [pos, 6 * sec],
		tm._audio.has(v.id) and tm._audio[v.id].player.playing and absf(pos - 6 * sec) < 0.2)
	tm._stop_all_audio()
	v.muted = true
	tm.mix_changed()
	tm._on_step(8)
	_check("a muted voice track stays silent", not tm._audio[v.id].player.playing)
	v.muted = false
	tm.mix_changed()
	v.solo = false

	# ---- trim a voice clip, move it
	var before_len: float = v.audio_len_sec()
	tm.trim_track(v, 8 + int(1.0 / sec))
	_check("trimming a voice clip keeps only the first part (%.2f -> %.2f s)" % [before_len, v.audio_len_sec()], v.audio_len_sec() < 1.2 and v.audio_len_sec() > 0.8)
	tm.shift_track(v, 8)
	_check("a voice clip can be moved in time (start %d)" % v.audio_start, v.audio_start == 16)

	# ---- editor routing and isolation
	scene._open_editor(m2)
	var ed: Node = scene._editor
	var notes_before: int = m2.notes.size()
	scene._open_editor(v)
	_check("a voice track opens the voice editor, not the note editor", scene._audio_editor.visible and not ed.visible)
	var ae: Node = scene._audio_editor
	ae._rec = 2  # RECORDING
	ae._skip_samples = 0
	var tone := PackedFloat32Array()
	tone.resize(RATE * 2)
	for i in tone.size():
		tone[i] = 0.3 * sin(TAU * 200.0 * i / RATE) + 0.01 * sin(i * 0.37)
	var old_path: String = v.audio_path
	rm.finished.emit(tone, RATE)
	var t0 := Time.get_ticks_msec()
	while v.audio_path == old_path and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	_check("a new take replaces the recording (cleaned + saved: %s)" % v.audio_path.get_file(), v.audio_path != old_path and FileAccess.file_exists(v.audio_path))
	_check("...with the right length (%.1f s)" % v.audio_dur, absf(v.audio_dur - 2.0) < 0.05)
	_check("the note editor ignored the voice take (no notes were added)", m2.notes.size() == notes_before)

	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(v.audio_path)
	print("VOICE TRACK FAILURES: ", bad)
	pm.new_project()
	quit(bad)


func _check_not_loop_button(tt: String) -> void:
	if tt.begins_with("Loop builder: combine"):
		_check("no separate loop button in the header", false)
