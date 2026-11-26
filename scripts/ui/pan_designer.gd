class_name PanDesigner
extends PopupPanel
## Draw where a track sits in the stereo field over time: drag a finger across the canvas.
## Top = right speaker, middle = centre, bottom = left. Plays back with the song.

var track: Track
var _canvas: Control
var _title: Label


func _init() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var hint := Label.new()
	hint.text = "Draw with your finger: up = right, down = left"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", StudioTheme.DIM)
	head.add_child(hint)
	var clear := IconButton.create("trash", "Remove the drawing (back to the fixed pan)", Vector2(36, 34))
	clear.pressed.connect(func():
		track.pan_curve.clear()
		TrackManager.apply_mix()
		TrackManager.notify_changed(track)
		_canvas.queue_redraw())
	head.add_child(clear)
	var done := IconButton.create("close", "Done", Vector2(36, 34))
	done.pressed.connect(hide)
	head.add_child(done)
	_canvas = PanCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(300, 160)
	v.add_child(_canvas)


func open_for(t: Track) -> void:
	track = t
	_canvas.track = t
	_title.text = "%s  -  pan design%s" % [t.name, "  (repeats with the loop)" if t.kind == "drums" else ""]
	_canvas.queue_redraw()
	popup_centered_ratio(0.9)


class PanCanvas extends Control:
	var track: Track
	var _drawing := false
	var _last := Vector2(-1, 0)

	func _steps() -> int:
		if track != null and track.kind == "drums":
			return track.pattern_steps()  # a loop's drawing is one pattern long and repeats with it
		return maxi(TrackManager.song_steps, 32)

	func _process(_d: float) -> void:
		if is_visible_in_tree() and Transport.playing:
			queue_redraw()

	func _to_step(x: float) -> int:
		return clampi(int(x / maxf(size.x, 1.0) * _steps()), 0, _steps() - 1)

	func _to_pan(y: float) -> float:
		var p := (0.5 - y / maxf(size.y, 1.0)) * 2.0
		p = clampf(p, -1.0, 1.0)
		return 0.0 if absf(p) < 0.05 else p

	func _put(pos: Vector2) -> void:
		var s := _to_step(pos.x)
		var p := _to_pan(pos.y)
		var from := s
		var p0 := p
		if _last.x >= 0.0:  # fill the gap between two motion events
			from = int(_last.x)
			p0 = _last.y
		var a := mini(from, s)
		var b := maxi(from, s)
		for k in range(a, b + 1):
			var f := 1.0 if b == a else float(k - from) / float(s - from) if s != from else 1.0
			_set_point(k, lerpf(p0, p, clampf(f, 0.0, 1.0)))
		_last = Vector2(s, p)
		queue_redraw()

	func _set_point(step: int, pan: float) -> void:
		for i in track.pan_curve.size():
			if int(track.pan_curve[i][0]) == step:
				track.pan_curve[i][1] = pan
				return
		track.pan_curve.append([step, pan])

	func _gui_input(e: InputEvent) -> void:
		if track == null:
			return
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_drawing = e.pressed
			_last = Vector2(-1, 0)
			if e.pressed:
				_put(e.position)
			else:
				track.pan_curve.sort_custom(func(a, b): return a[0] < b[0])
				TrackManager.notify_changed(track)
		elif e is InputEventMouseMotion and _drawing:
			_put(e.position)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), StudioTheme.PANEL_HI)
		draw_line(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), Color(1, 1, 1, 0.25), 1.0)
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(6, 16), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, StudioTheme.DIM)
		draw_string(f, Vector2(6, size.y - 6), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, StudioTheme.DIM)
		if track == null:
			return
		var steps := _steps()
		var pts: Array = track.pan_curve.duplicate()
		pts.sort_custom(func(a, b): return a[0] < b[0])
		var col := TrackManager.color_of(track)
		if pts.is_empty():  # the fixed pan, drawn as a flat line
			var y := (0.5 - track.pan * 0.5) * size.y
			draw_line(Vector2(0, y), Vector2(size.x, y), col.darkened(0.3), 2.0)
		else:
			var line := PackedVector2Array()
			for p in pts:
				line.append(Vector2((float(p[0]) + 0.5) / steps * size.x, (0.5 - float(p[1]) * 0.5) * size.y))
			if line.size() > 1:
				draw_polyline(line, col, 3.0, true)
			for pt in line:
				draw_circle(pt, 2.5, col)
		if Transport.playing and Transport.step >= 0:
			var x := (TrackManager.pan_step(track, Transport.step) + 0.5) / steps * size.x
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.7), 1.5)
