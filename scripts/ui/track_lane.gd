class_name TrackLane
extends Control
## One track's clip across the song timeline: a miniature of the notes (or drum
## pattern), faint bar lines, and the playhead. Tap to open the track editor.
## Width follows the song length and the zoom level (px_per_step).

signal tapped

## Timeline zoom, shared by every lane and the ruler.
static var px_per_step := 4.0

var track: Track:
	set(v):
		track = v
		queue_redraw()

const HOLD_SEC := 0.35   # touch: hold this long to pick the tune up, then drag it
const MOVE_SNAP := 4      # moves snap to a beat (4 steps)

var _pressing := false
var _press_pos := Vector2.ZERO
var _stamp := 0
var _moved := false       # moved before being picked up = a scroll gesture, not a tap
var _grabbed := false     # the tune is picked up and follows the finger
var _real_mouse := false
var _applied := 0         # steps the tune has been shifted during this drag
var _resizing := false    # dragging the right edge of a loop clip
var _trimming := false    # dragging the trim handle of an instrument / voice clip
var _trim_to := 0         # where the clip would end if released now


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 96)
	tooltip_text = "Tap to open. Hold, then drag to move this tune in time."


func _ready() -> void:
	TrackManager.track_changed.connect(func(t: Track): if t == track: queue_redraw())
	TrackManager.tracks_changed.connect(queue_redraw)
	TrackManager.length_changed.connect(queue_redraw)
	TrackManager.cursor_changed.connect(queue_redraw)
	Transport.step_fired.connect(func(_s: int): queue_redraw())
	Transport.stopped.connect(queue_redraw)


func _draw() -> void:
	if track == null:
		return
	var ps := px_per_step
	var total_steps := TrackManager.song_steps
	var w := size.x
	var h := size.y
	var col := TrackManager.color_of(track)
	if not TrackManager.audible(track) and TrackManager.only == null:
		col = col.lerp(Color("555b69"), 0.7)
	draw_rect(Rect2(0, 0, w, h), Color("12161e"))
	draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.05), false, 1.0)
	var bar_px := Track.STEPS_PER_BAR * ps
	var bars := int(ceil(w / bar_px))
	for b in bars:
		if b % 2 == 1:
			draw_rect(Rect2(b * bar_px, 0, bar_px, h), Color(1, 1, 1, 0.02))
		if bar_px >= 6.0:
			draw_line(Vector2(b * bar_px, 0), Vector2(b * bar_px, h), Color(1, 1, 1, 0.07), 1.0)
	# the end of the song
	var end_x := total_steps * ps
	draw_rect(Rect2(end_x, 0, maxf(w - end_x, 0.0), h), Color(0, 0, 0, 0.28))
	draw_line(Vector2(end_x, 0), Vector2(end_x, h), Color(1, 1, 1, 0.18), 1.0)

	if track.has_content() and track.kind == "audio":
		var ss := TrackManager.step_sec()
		var x0 := track.audio_start * ps
		var take_w := track.audio_len_sec() / ss * ps  # one pass of the take
		var clip_w := TrackManager.audio_clip_steps(track) * ps  # wider than the take when it loops
		draw_rect(Rect2(x0, 1, clip_w, h - 2), Color(col, 0.10))
		draw_rect(Rect2(x0, 1, 3, h - 2), Color(col, 0.7))
		if track.audio_peaks.is_empty():
			TrackManager.ensure_audio_peaks(track)
		var peaks := track.audio_peaks
		var px_per_peak := 0.02 / ss * ps
		var group := maxi(1, int(ceil(1.0 / maxf(px_per_peak, 0.01))))
		var count := mini(int(track.audio_len_sec() / 0.02), peaks.size())
		var mid := h * 0.5
		var passes := int(ceil(clip_w / maxf(take_w, 1.0)))
		for pass_i in passes:
			var px0 := x0 + pass_i * take_w
			if pass_i > 0:  # where the take starts again
				draw_line(Vector2(px0, 4), Vector2(px0, h - 4), Color(col, 0.6), 1.0)
			var k := 0
			while k < count:
				var gx := px0 + k * px_per_peak
				if gx > x0 + clip_w:
					break
				var pk := 0.0
				for j in range(k, mini(k + group, count)):
					pk = maxf(pk, peaks[j])
				var hh := minf(pk * 2.0, 1.0) * (mid - 7.0)
				draw_line(Vector2(gx, mid - hh), Vector2(gx, mid + hh), col, maxf(px_per_peak * group, 1.0))
				k += group
	elif track.kind == "drums":
		var lanes: Array = track.drum_lanes
		var rh := (h - 10.0) / maxf(lanes.size(), 1.0)
		var plen := track.pattern_steps()
		var clip_end := track.drum_start + track.drum_len if track.drum_len > 0 else total_steps
		var reps := int(ceil(maxf(clip_end - track.drum_start, plen) / float(plen)))
		var dw := maxf(ps - 1.0, 1.5)
		# the clip: a tinted block from where the loop starts to where it ends
		draw_rect(Rect2(track.drum_start * ps, 1, maxf((clip_end - track.drum_start) * ps, 2.0), h - 2), Color(col, 0.10))
		draw_rect(Rect2(track.drum_start * ps, 1, 3, h - 2), Color(col, 0.7))
		# right-edge handle: drag to make the loop shorter or longer
		var hx := clip_end * ps
		draw_rect(Rect2(hx - 7, 8, 7, h - 16), Color(col, 0.85))
		draw_line(Vector2(hx - 4, h * 0.5 - 7), Vector2(hx - 4, h * 0.5 + 7), Color(0, 0, 0, 0.6), 1.5)
		for r in reps:
			for li in lanes.size():
				var lcol := col
				var ldef := InstrumentManager.get_by_id(lanes[li].id)
				if ldef and TrackManager.audible(track) and not lanes[li].mute:
					lcol = ldef.color  # each layer shows in its own colour
				for s in track.drum_steps.get(lanes[li].key, []):
					var hit_step: float = track.drum_start + r * plen + float(s) / track.drum_res  # cells are finer than a step
					if hit_step < clip_end and s < track.grid_steps():
						draw_rect(Rect2(hit_step * ps, 5 + li * rh + 1, maxf(dw / track.drum_res, 1.0), maxf(rh - 2.0, 2.0)), lcol)
	else:
		var lo := 127
		var hi := 0
		for n in track.notes:
			lo = mini(lo, n.midi)
			hi = maxi(hi, n.midi)
		var span := maxf(float(hi - lo), 7.0)
		var nh := clampf((h - 14.0) / (span + 1.0), 2.0, 8.0)
		for n in track.notes:
			var x: float = n.start * ps
			var nw: float = maxf(n.len * ps - 1.0, 2.0)
			var y: float = 7.0 + (h - 14.0 - nh) * (1.0 - (float(n.midi - lo) / span))
			var fill := col.lerp(Color.WHITE, clampf(float(n.get("vel", 0.8)) * 0.22, 0.0, 0.22))
			draw_rect(Rect2(x, y, nw, nh), fill)
			if nh >= 3.0:
				draw_rect(Rect2(x, y, nw, 1.0), Color(1, 1, 1, 0.22))

	if track.kind != "drums" and track.has_content():  # trim handle: drag it left to cut the clip short
		var handle_x := TrackManager.clip_end(track) * ps
		draw_rect(Rect2(handle_x - 7, 8, 7, h - 16), Color(col, 0.85))
		draw_line(Vector2(handle_x - 4, h * 0.5 - 7), Vector2(handle_x - 4, h * 0.5 + 7), Color(0, 0, 0, 0.6), 1.5)
	if _trimming:
		var cur_x := TrackManager.clip_end(track) * ps
		var new_x := _trim_to * ps
		if new_x < cur_x:  # what would be cut
			draw_rect(Rect2(new_x, 1, cur_x - new_x, h - 2), Color(0, 0, 0, 0.6))
			draw_line(Vector2(new_x, 0), Vector2(new_x, h), Color("ff6b6b"), 2.0)
		elif new_x > cur_x:  # what would be filled by repeating the clip
			draw_rect(Rect2(cur_x, 1, new_x - cur_x, h - 2), Color(col, 0.28))
			draw_line(Vector2(new_x, 0), Vector2(new_x, h), Color("2ed3b7"), 2.0)
	if _grabbed:
		draw_rect(Rect2(1, 1, w - 2, h - 2), Color(1, 1, 1, 0.55), false, 2.0)
	if not Transport.playing:  # where Play will start
		var cx := TrackManager.start_step * ps
		draw_line(Vector2(cx, 0), Vector2(cx, h), Color("ffb347", 0.75), 1.5)
	if Transport.playing and Transport.step >= 0 and (TrackManager.only == null or TrackManager.only == track):
		var px := (Transport.step + 0.5) * ps
		draw_line(Vector2(px, 0), Vector2(px, h), Color(1, 1, 1, 0.8), 1.5)


func _gui_input(e: InputEvent) -> void:
	if track == null:
		return
	var movable := track.kind == "drums" or track.kind == "audio" or not track.notes.is_empty()
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and track.kind != "drums" and track.has_content():
			var end_step_ := TrackManager.clip_end(track)
			var first_step_ := _clip_start()
			var trim_x := end_step_ * px_per_step
			if absf(e.position.x - trim_x) <= minf(14.0, maxf(trim_x - first_step_ * px_per_step, 8.0) * 0.4):
				_trimming = true  # grabbed the trim handle
				_trim_to = end_step_
				_pressing = true
				_moved = true
				queue_redraw()
				accept_event()
				return
		if not e.pressed and _trimming:
			var changed := _trim_to != TrackManager.clip_end(track)
			_trimming = false
			_pressing = false
			if changed:
				TrackManager.trim_track(track, _trim_to)
			queue_redraw()
			accept_event()
			return
		if e.pressed and track.kind == "drums" and absf(e.position.x - (track.drum_start + track.drum_len) * px_per_step) <= minf(14.0, track.drum_len * px_per_step * 0.4):
			_resizing = true  # grabbed the loop's right edge
			_pressing = true
			_moved = true
			accept_event()
			return
		if not e.pressed and _resizing:
			_resizing = false
			_pressing = false
			queue_redraw()
			accept_event()
			return
		if e.pressed:
			_pressing = true
			_press_pos = e.position
			_moved = false
			_grabbed = false
			_applied = 0
			_stamp = Time.get_ticks_msec()
			_real_mouse = e.device != InputEvent.DEVICE_ID_EMULATION
			if movable and not _real_mouse:  # touch: long-press picks the tune up
				var stamp := _stamp
				get_tree().create_timer(HOLD_SEC).timeout.connect(func():
					if _pressing and _stamp == stamp and not _moved:
						_grabbed = true
						queue_redraw())
		else:
			var was_grabbed := _grabbed
			var tap: bool = not was_grabbed and not _moved and e.position.distance_to(_press_pos) < 12.0
			_pressing = false
			_grabbed = false
			queue_redraw()
			if tap:
				tapped.emit()
	elif e is InputEventMouseMotion and _trimming:
		var first := _clip_start()
		var sn := _trim_snap()
		var snapped_ := int(round(e.position.x / px_per_step / sn)) * sn
		# shorter = cut there; longer = the clip repeats to fill it
		_trim_to = clampi(snapped_, first + sn, TrackManager.max_steps())
		queue_redraw()
		accept_event()
	elif e is InputEventMouseMotion and _resizing:
		var snapped := int(round((e.position.x / px_per_step - track.drum_start) / MOVE_SNAP)) * MOVE_SNAP
		var new_len := clampi(snapped, MOVE_SNAP, TrackManager.max_steps() - track.drum_start)
		if new_len != track.drum_len:
			track.drum_len = new_len
			TrackManager.notify_changed(track)
		accept_event()
	elif e is InputEventMouseMotion and _pressing:
		var dx: float = e.position.x - _press_pos.x
		if not _grabbed:
			if _real_mouse and movable and absf(dx) > 8.0:
				_grabbed = true  # desktop: drag straight away
			elif absf(dx) > 10.0 or absf(e.position.y - _press_pos.y) > 10.0:
				_moved = true  # a scroll, not a tap or a move
		if _grabbed:
			var target := int(round(dx / px_per_step / MOVE_SNAP)) * MOVE_SNAP
			var d := target - _applied
			if d != 0:
				_applied += TrackManager.shift_track(track, d)
			queue_redraw()
			accept_event()
	elif e is InputEventScreenDrag and _grabbed:
		accept_event()  # keep the timeline from scrolling while a tune is being moved

## Trim handle precision: a single step when zoomed in, a beat when zoomed out.
func _trim_snap() -> int:
	if px_per_step >= 10.0:
		return 1
	if px_per_step >= 5.0:
		return 2
	return MOVE_SNAP


## Where this clip starts: the voice clip's start, or the first note.
func _clip_start() -> int:
	return track.audio_start if track.kind == "audio" else track.start_step()