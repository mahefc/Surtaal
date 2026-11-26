class_name TimelineRuler
extends Control
## Time ruler (m:ss) above the track lanes, with the playhead marker.
## Label spacing adapts to the zoom level.

const INTERVALS := [1, 2, 5, 10, 15, 30, 60, 120, 300]


func _init() -> void:
	custom_minimum_size = Vector2(0, 28)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Tap or drag here to choose where Play starts"


func _ready() -> void:
	TrackManager.length_changed.connect(queue_redraw)
	TrackManager.cursor_changed.connect(queue_redraw)
	Transport.bpm_changed.connect(queue_redraw)
	Transport.step_fired.connect(func(_s: int): queue_redraw())
	Transport.stopped.connect(queue_redraw)


func _draw() -> void:
	var step_sec := Transport.seconds_per_step()
	var px_per_sec := TrackLane.px_per_step / step_sec
	var font := ThemeDB.fallback_font
	var every := 300
	for iv in INTERVALS:
		if iv * px_per_sec >= 64.0:
			every = iv
			break
	var secs := size.x / px_per_sec
	var t := 0
	while t <= secs:
		var x := t * px_per_sec
		draw_line(Vector2(x, size.y - 9), Vector2(x, size.y), Color(1, 1, 1, 0.3), 1.0)
		draw_string(font, Vector2(x + 4, size.y - 10), TrackManager.format_time(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, StudioTheme.DIM)
		t += every
	# the start marker (where Play begins)
	var sx := TrackManager.start_step * TrackLane.px_per_step
	draw_line(Vector2(sx, 0), Vector2(sx, size.y), Color("ffb347"), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(sx, 0), Vector2(sx + 11, 0), Vector2(sx, 11)]), Color("ffb347"))
	if Transport.playing and Transport.step >= 0:
		var px := (Transport.step + 0.5) * TrackLane.px_per_step
		draw_colored_polygon(PackedVector2Array([Vector2(px - 5, 0), Vector2(px + 5, 0), Vector2(px, 8)]), Color.WHITE)


func _gui_input(e: InputEvent) -> void:
	var pressed: bool = e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed
	var dragging: bool = e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if pressed or dragging:
		TrackManager.set_start_step(int(round(e.position.x / TrackLane.px_per_step)))
		accept_event()