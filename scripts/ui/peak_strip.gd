class_name PeakStrip
extends Control
## Waveform strip for the recording workflow: grows live while recording and
## stays on screen afterwards. Also carries the short status message.

var color: Color = StudioTheme.ACCENT
var message := ""
var level := 0.0  # live input level 0..1 (drives the left meter dot)

var _peaks := PackedFloat32Array()
var _capacity := 1


func _init() -> void:
	custom_minimum_size = Vector2(0, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `capacity` = how many peak windows fit the full width (the available recording time).
func set_data(peaks: PackedFloat32Array, capacity: int) -> void:
	_peaks = peaks
	_capacity = maxi(capacity, 1)
	queue_redraw()


func clear() -> void:
	_peaks = PackedFloat32Array()
	queue_redraw()


func set_message(m: String) -> void:
	message = m
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0e1117"))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.05), false, 1.0)
	var mid := size.y * 0.5
	draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.06), 1.0)
	if not _peaks.is_empty():
		var top := 0.05
		for p in _peaks:
			top = maxf(top, p)
		var step := maxf(size.x / _capacity, 1.0)
		for i in _peaks.size():
			var x := float(i) / _capacity * size.x
			var h := clampf(_peaks[i] / top, 0.0, 1.0) * (mid - 3.0)
			draw_line(Vector2(x, mid - h), Vector2(x, mid + h), color, step)
	if level > 0.02:  # live input meter on the left
		var lh := clampf(level, 0.0, 1.0) * (size.y - 8.0)
		draw_rect(Rect2(3, size.y - 4 - lh, 4, lh), color.lightened(0.2))
	if message != "":
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(11, mid + 5), message, HORIZONTAL_ALIGNMENT_LEFT, size.x - 18, 13, Color(0, 0, 0, 0.65))
		draw_string(f, Vector2(10, mid + 4), message, HORIZONTAL_ALIGNMENT_LEFT, size.x - 18, 13, StudioTheme.TEXT)
