class_name DrumGrid
extends Control
## Drum rack editor for a drums-kind Track: every row is a LAYER (any instrument) and
## all layers are composed together in one grid that loops through the song.
## Tap / drag on cells to paint hits (silent while designing — use Play to hear the loop).
## Tap a layer's card for its panel: change sound, pitch, volume, mute, remove.
## Velocity mode: drag up/down on a hit to set how hard it is played (drag along a row to draw it).
## Pan mode: a lane under the rows to draw L/R over the pattern (same idea as the note editor).
## The grid has 16, 32 or 64 cells in a bar (`Track.drum_res`): a finer grid, never more bars.

const LABEL_W := 128.0
const COMPACT_W := 62.0   # the layer cards shrink to just the picture when the grid is very fine
const MIN_ROW_H := 28.0
const MAX_ROW_H := 64.0
const PAN_H := 56.0  # taller for freehand pan drawing
const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

## "Change sound" was chosen in a layer's panel: the editor opens the instrument picker.
signal change_sound_requested(lane_key: String)

var track: Track:
	set(v):
		track = v
		queue_redraw()

## Velocity mode: hits become bars; drag up/down on one to set how hard it is played.
var velocity_mode := false:
	set(v):
		velocity_mode = v
		if v:
			show_pan = false
		_paint = -1
		queue_redraw()

## Pan lane under the rows (toolbar toggle, like the note editor).
var show_pan := false:
	set(v):
		show_pan = v
		if v:
			velocity_mode = false
		_paint = -1
		queue_redraw()

var _paint := -1  # -1 idle, 0 erasing, 1 adding, 2 drawing velocities, 3 drawing pan
var _vel_row := -1
var _vel_dirty := false
var _last := Vector2i(-1, -1)
var _pan_last_px := Vector2(-1, -1)  # last freehand pan sample in lane pixels
var _panel: LayerPanel
var _sb := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 120)
	_panel = LayerPanel.new()
	_panel.change_sound_requested.connect(func(key: String): change_sound_requested.emit(key))
	add_child(_panel)


func _ready() -> void:
	TrackManager.track_changed.connect(func(_t): queue_redraw())
	Transport.step_fired.connect(func(_s: int): queue_redraw())
	Transport.stopped.connect(queue_redraw)
	resized.connect(queue_redraw)


## A filled rounded rectangle (one reusable style box, so drawing stays cheap).
func _box(r: Rect2, c: Color, radius: int) -> void:
	_sb.bg_color = c
	_sb.set_corner_radius_all(radius)
	draw_style_box(_sb, r)


func _lanes() -> Array:
	return track.drum_lanes if track else []


func _steps() -> int:
	return track.grid_steps() if track else 16


func _res() -> int:
	return track.drum_res if track else 1


## Width of the layer cards: full, or just the picture when the grid is so fine the cells need the room.
func _lw() -> float:
	return COMPACT_W if _steps() > 32 else LABEL_W


func _pan_h() -> float:
	return PAN_H if show_pan else 0.0


func _row_h() -> float:
	var avail := maxf(size.y - _pan_h(), 1.0)
	return clampf(avail / maxf(_lanes().size(), 1.0), MIN_ROW_H, MAX_ROW_H)


func _cw() -> float:
	return (size.x - _lw()) / _steps()


func _lane_rect() -> Rect2:
	return Rect2(_lw(), size.y - _pan_h(), size.x - _lw(), _pan_h())


func _cell(pos: Vector2) -> Vector2i:
	if show_pan and pos.y >= size.y - _pan_h():
		return Vector2i(-1, -1)
	var x := int(floorf((pos.x - _lw()) / _cw()))
	var y := int(floorf(pos.y / _row_h()))
	if x < 0 or x >= _steps() or y < 0 or y >= _lanes().size():
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func _draw() -> void:
	if track == null:
		return
	var lanes := _lanes()
	var rh := _row_h()
	var cw := _cw()
	var lw := _lw()
	var steps := _steps()
	var res := _res()
	var beat := 4 * res  # cells in one beat
	var font := ThemeDB.fallback_font
	if lanes.is_empty():
		draw_string(font, Vector2(12, 32), "No layers yet - tap + to add an instrument.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 15, StudioTheme.DIM)
		return
	# the moving column: a soft band through every row while the loop plays (one 16th note wide)
	if Transport.playing and Transport.step >= 0:
		var play_cell := (Transport.step % track.pattern_steps()) * res
		draw_rect(Rect2(lw + play_cell * cw, 0, cw * res, lanes.size() * rh), Color(1, 1, 1, 0.07))
	var radius := 6 if cw >= 10.0 else 2
	for li in lanes.size():
		var lane: Dictionary = lanes[li]
		var def := InstrumentManager.get_by_id(lane.id)
		var col: Color = def.color if def else StudioTheme.ACCENT
		var muted: bool = lane.mute
		if muted:
			col = col.lerp(Color("555b69"), 0.75)
		var y := li * rh
		# layer card: the instrument's picture, its name and pitch
		_box(Rect2(0, y + 2, lw - 8, rh - 4), StudioTheme.PANEL_HI, 10)
		var pr := minf((rh - 8.0) * 0.5, 17.0)
		var pc := Vector2(8.0 + pr, y + rh * 0.5)
		draw_circle(pc, pr, Color(col, 0.2))
		InstrumentArt.paint(self, InstrumentArt.kind_of(def), pc, pr * 0.52, col)
		var tx := pc.x + pr + 8.0
		var tw := lw - 8.0 - tx - 4.0
		if tw >= 24.0:
			var pitch := "%s%d" % [NOTE_NAMES[int(lane.midi) % 12], int(lane.midi) / 12 - 1]
			var tcol: Color = StudioTheme.DIM if muted else StudioTheme.TEXT
			if rh >= 40.0:
				draw_string(font, Vector2(tx, y + rh * 0.5 - 1.0), lane.key, HORIZONTAL_ALIGNMENT_LEFT, tw, 13, tcol)
				draw_string(font, Vector2(tx, y + rh * 0.5 + 13.0), pitch, HORIZONTAL_ALIGNMENT_LEFT, tw, 10, StudioTheme.DIM)
			else:
				draw_string(font, Vector2(tx, y + rh * 0.5 + 4.0), lane.key, HORIZONTAL_ALIGNMENT_LEFT, tw, 12, tcol)
		for s in steps:
			var gap := 3.0 if cw >= 10.0 else 1.0
			var r := Rect2(lw + s * cw + gap * 0.5, y + 3, maxf(cw - gap, 1.0), rh - 6)
			var on := track.drum_on(lane.key, s)
			var group_dark := (s / beat) % 2 == 1
			var base := Color("1b202a") if group_dark else Color("262d3c")
			var drawn: bool = track.drum_vel.get(lane.key, {}).has(s)
			var vel := track.hit_vel(lane.key, s)
			if on and velocity_mode:  # a bar from the bottom: the taller, the harder the hit
				_box(r, base, radius)
				var h := maxf(r.size.y * vel, 3.0)
				_box(Rect2(r.position.x, r.end.y - h, r.size.x, h), col.lightened(0.15) if drawn else col, radius)
			elif on:
				var hit_col := col if s % beat != 0 else col.lightened(0.18)
				if drawn:  # a drawn velocity: softer hits are dimmer
					hit_col = col.darkened(0.55 * (1.0 - vel))
				_box(r, hit_col, radius)
			else:
				_box(r, base, radius)
	# bar lines (only when the pattern is more than one bar)
	for b in range(1, track.drum_bars):
		var x := lw + b * 16 * res * cw
		draw_line(Vector2(x, 0), Vector2(x, lanes.size() * rh), Color(1, 1, 1, 0.25), 1.5)
	if show_pan:
		_draw_pan_lane(font)


func _apply(c: Vector2i) -> void:
	if c.x < 0 or c == _last or track == null:
		return
	_last = c
	var lane: Dictionary = _lanes()[c.y]
	var on := _paint == 1
	if track.drum_on(lane.key, c.x) == on:
		return
	track.set_drum(lane.key, c.x, on)
	TrackManager.notify_changed(track)  # silent while designing — Play hears the loop


## Velocity mode: the finger's height in the pressed layer's row is the loudness of the hit under it.
func _draw_velocity(pos: Vector2) -> void:
	if _vel_row < 0 or _vel_row >= _lanes().size():
		return
	var c := _cell(Vector2(pos.x, _vel_row * _row_h() + 1.0))
	if c.x < 0:
		return
	var lane: Dictionary = _lanes()[_vel_row]
	if not track.drum_on(lane.key, c.x):
		return
	var y0 := _vel_row * _row_h() + 3.0
	var vel := clampf(1.0 - (pos.y - y0) / maxf(_row_h() - 6.0, 1.0), 0.1, 1.0)
	if absf(vel - track.hit_vel(lane.key, c.x)) < 0.005 and track.drum_vel.get(lane.key, {}).has(c.x):
		return
	track.set_hit_vel(lane.key, c.x, vel)
	_vel_dirty = true
	if c != _last:
		_last = c
	queue_redraw()


func _pan_reset_rect() -> Rect2:
	var ph := _pan_h()
	var mid_y := size.y - ph * 0.5
	return Rect2(4, mid_y - 10, _lw() - 10, 20)


func _reset_pan() -> void:
	if track == null:
		return
	track.pan_curve.clear()
	TrackManager.apply_mix()
	TrackManager.notify_changed(track)
	queue_redraw()


func _draw_pan_lane(font: Font) -> void:
	var ph := _pan_h()
	var strip := Rect2(0, size.y - ph, size.x, ph)
	var lr := _lane_rect()
	draw_rect(strip, Color("10131a"))
	draw_line(Vector2(0, strip.position.y), Vector2(size.x, strip.position.y), Color(1, 1, 1, 0.06), 1.0)
	draw_line(Vector2(lr.position.x, lr.position.y + lr.size.y * 0.5), Vector2(lr.end.x, lr.position.y + lr.size.y * 0.5), Color(1, 1, 1, 0.18), 1.0)
	draw_string(font, Vector2(6, lr.position.y + 12), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, StudioTheme.DIM)
	draw_string(font, Vector2(6, lr.end.y - 4), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, StudioTheme.DIM)
	var reset := _pan_reset_rect()
	draw_rect(reset, StudioTheme.PANEL_HI)
	Icons.draw(self, "trash", reset.get_center(), 7.0, StudioTheme.DIM)
	var steps := float(track.pattern_steps())
	var col := TrackManager.color_of(track)
	var pts: Array = track.pan_curve.duplicate()
	pts.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	if pts.is_empty():
		var y := lr.position.y + (0.5 - track.pan * 0.5) * lr.size.y
		draw_line(Vector2(lr.position.x, y), Vector2(lr.end.x, y), Color(col, 0.55), 2.0)
	else:
		var line := PackedVector2Array()
		for p in pts:
			var s := float(p[0])
			if s < -0.01 or s > steps + 0.01:
				continue
			var x := lr.position.x + (s / steps) * lr.size.x
			var y := lr.position.y + (0.5 - float(p[1]) * 0.5) * lr.size.y
			line.append(Vector2(x, y))
		if line.size() == 1:
			draw_circle(line[0], 2.0, col)
		elif line.size() > 1:
			draw_polyline(line, col, 2.8, true)
	if Transport.playing and Transport.step >= 0:
		var px := lr.position.x + (float(TrackManager.pan_step(track, Transport.step)) + 0.5) / steps * lr.size.x
		draw_line(Vector2(px, lr.position.y), Vector2(px, lr.end.y), Color(1, 1, 1, 0.7), 1.5)


## Freehand pan: sample densely along the finger path (not one point per grid cell).
func _put_pan(pos: Vector2) -> void:
	if track == null:
		return
	var lr := _lane_rect()
	var clamped := Vector2(clampf(pos.x, lr.position.x, lr.end.x), clampf(pos.y, lr.position.y, lr.end.y))
	if _pan_last_px.x < 0.0:
		_sample_pan_px(clamped, lr)
	else:
		var dist := clamped.distance_to(_pan_last_px)
		var n := maxi(1, int(ceil(dist / 2.0)))  # ~every 2px along the stroke
		for i in n + 1:
			_sample_pan_px(_pan_last_px.lerp(clamped, float(i) / float(n)), lr)
	_pan_last_px = clamped
	queue_redraw()


func _sample_pan_px(pos: Vector2, lr: Rect2) -> void:
	var steps := float(track.pattern_steps())
	var t := clampf((pos.x - lr.position.x) / maxf(lr.size.x, 1.0), 0.0, 1.0)
	var step_f := snappedf(t * steps, 0.05)
	var pan := clampf((0.5 - (pos.y - lr.position.y) / maxf(lr.size.y, 1.0)) * 2.0, -1.0, 1.0)
	_set_pan_point(step_f, pan)


func _set_pan_point(step: float, pan: float) -> void:
	for i in track.pan_curve.size():
		if absf(float(track.pan_curve[i][0]) - step) < 0.03:
			track.pan_curve[i][0] = step
			track.pan_curve[i][1] = pan
			return
	track.pan_curve.append([step, pan])


func _gui_input(e: InputEvent) -> void:
	if track == null:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			if show_pan and e.position.y >= size.y - _pan_h():
				if _pan_reset_rect().has_point(e.position):
					_reset_pan()
					accept_event()
					return
				if _lane_rect().has_point(e.position):
					_paint = 3
					_pan_last_px = Vector2(-1, -1)
					_put_pan(e.position)
					accept_event()
					return
				accept_event()
				return
			if e.position.x < _lw() and e.position.y < size.y - _pan_h():  # a layer's card -> its panel
				var li := int(floorf(e.position.y / _row_h()))
				if li >= 0 and li < _lanes().size():
					var card := Rect2(get_global_rect().position + Vector2(0, li * _row_h()), Vector2(_lw(), _row_h()))
					_panel.open_for(track, _lanes()[li].key, card)
				accept_event()
				return
			var c := _cell(e.position)
			if c.x >= 0 and velocity_mode:  # draw loudness: nothing is added or removed in this mode
				_paint = 2
				_vel_row = c.y
				_vel_dirty = false
				_last = Vector2i(-1, -1)
				_draw_velocity(e.position)
			elif c.x >= 0:
				_paint = 0 if track.drum_on(_lanes()[c.y].key, c.x) else 1
				_last = Vector2i(-1, -1)
				_apply(c)
		else:
			if _paint == 2 and _vel_dirty:
				TrackManager.notify_changed(track)
			elif _paint == 3:
				track.pan_curve.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
				TrackManager.apply_mix()
				TrackManager.notify_changed(track)
				_pan_last_px = Vector2(-1, -1)
			_paint = -1
			_vel_dirty = false
		accept_event()
	elif e is InputEventMouseMotion and _paint >= 0:
		if _paint == 2:
			_draw_velocity(e.position)
		elif _paint == 3:
			_put_pan(e.position)
		else:
			_apply(_cell(e.position))
