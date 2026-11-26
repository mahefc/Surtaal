class_name PianoRoll
extends Control
## Piano roll for one Track. It shows `steps` columns at a time (zoomable: 16/32/64);
## `bar` is the page index (page = steps columns).
## Always a sketch pad: tap an empty cell for a new note (drag right for length, up/down for
## pitch); tap a note to delete it; drag a note to move it; drag its right end to resize.
## Select-move: box notes, then drag (or arrow keys) to slide them.
## Select-copy: box notes to copy, then click to paste; keep clicking to paste again.
## Editing makes no sound.
## Notes are coloured by velocity (soft blue ... loud red), see vel_color().
## Velocity / pan lanes (toolbar toggles) sit under the notes when switched on.

## A box was drawn around notes in copy mode: they are `selection` now, ready to paste.
signal selection_made
## The user clicked a cell while notes were copied: paste them with their first note on it.
signal paste_requested(step: int, midi: int)
## The selected notes were dragged to a new place.
signal selection_moved
## Rows are tinted by the current scale/tuning (TuningManager).

const ZOOMS := [16, 32, 64]
const LABEL_W := 36.0
const VEL_H := 40.0
const MIN_ROW_H := 14.0
const TAP_SLOP := 9.0  # a finger never stays perfectly still: small wobbles still count as a tap
const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const BLACK_PCS := [1, 3, 6, 8, 10]


## Every velocity has its own colour, so loud and soft notes tell apart at a glance:
## soft = blue, then teal, green, yellow, orange, and loud = red.
static func vel_color(v: float) -> Color:
	var t := clampf(v, 0.0, 1.0)
	return Color.from_hsv(lerpf(0.62, 0.0, t), 0.62, 0.96)

var track: Track:
	set(v):
		track = v
		selection = []  # `armed` stays: the copied notes can be pasted into another track
		queue_redraw()
var def: InstrumentDef  # for note preview
var accent: Color = StudioTheme.ACCENT:
	set(v):
		accent = v
		queue_redraw()
## Song steps (16ths) visible on one page. Zoom changes this, so it also changes how many bars show.
var steps: int = 32
## Grid cells inside one bar: 16, 32 or 64. This does not change how many bars are on screen.
var steps_per_bar: int = 16:
	set(v):
		steps_per_bar = v
		queue_redraw()
var bar: int = 0:  # page index
	set(v):
		bar = maxi(v, 0)
		queue_redraw()
var low_midi: int = 48:
	set(v):
		low_midi = clampi(v, 0, 127 - 12)
		queue_redraw()
var snap: int = 1  # notes snap to 1/16 steps
## Show exactly this many rows (set by the editor to match the keyboard); 0 = as many as fit.
var fixed_rows: int = 0:
	set(v):
		fixed_rows = maxi(v, 0)
		_layout()
## MIDI notes of keys held down right now (lights up their rows).
var live := {}


func set_live(midi: int, on: bool) -> void:
	if on:
		live[midi] = true
	else:
		live.erase(midi)
	queue_redraw()


## Forget any finger gesture in progress (the notes it was holding may no longer exist).
func cancel_drag() -> void:
	_drag = {}


func clear_live() -> void:
	live.clear()
	queue_redraw()


## Notes being recorded from the keys right now, shown before they are saved:
## [{start: float step, len: float steps, midi}]
var rec_notes: Array = []:
	set(v):
		rec_notes = v
		queue_redraw()

## Show the velocity lane under the notes (toolbar toggle).
var show_velocity := false:
	set(v):
		show_velocity = v
		if v:
			show_pan = false
		_layout()

## Show the pan lane under the notes (toolbar toggle): draw L/R over the bars on screen.
var show_pan := false:
	set(v):
		show_pan = v
		if v:
			show_velocity = false
		_layout()

## Playhead for audition / recording, in (fractional) song steps; -1 = hidden.
var playhead := -1.0:
	set(v):
		playhead = v
		queue_redraw()

## "" = draw notes; "move" = box-select then drag; "copy" = box-select then click to paste.
var select_kind := "":
	set(v):
		select_kind = v
		_drag = {}
		if v == "":
			selection = []
			armed = false
		elif v == "move":
			armed = false
		queue_redraw()

## Notes chosen with the box (dictionaries from the track).
var selection: Array = []
## True while notes are copied (copy mode): every click on the grid pastes them there.
var armed := false:
	set(v):
		armed = v
		if not v:
			_hover = Vector2i(-1, -1)
		queue_redraw()

var _hover := Vector2i(-1, -1)  # cell under the mouse (x = song step, y = row); -1 = none
var _rows := 12
var _row_h := 24.0
var _drag := {}  # {mode: "move"|"resize"|"draw"|"vel"|"pan"|"box"|"group", ...}
var _preview_id := -1
var _pan_last := Vector2(-1, 0)  # last pan stroke sample (step, pan)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 150)
	resized.connect(_layout)


func _ready() -> void:
	TrackManager.track_changed.connect(func(_t): queue_redraw())
	TuningManager.changed.connect(queue_redraw)
	Transport.step_fired.connect(func(_s: int): queue_redraw())
	Transport.stopped.connect(queue_redraw)
	_layout()


func base_step() -> int:
	return bar * steps


## Change how many steps fit on a page, keeping the same start position.
func set_zoom(n: int) -> void:
	var start := base_step()
	steps = n
	bar = start / steps
	queue_redraw()


func zoom_by(direction: int) -> void:  # +1 = zoom in (fewer, bigger cells)
	var i := ZOOMS.find(steps)
	if i == -1:
		i = 1
	set_zoom(ZOOMS[clampi(i - direction, 0, ZOOMS.size() - 1)])


func visible_notes() -> Array:
	var out := []
	for i in _rows:
		if low_midi + i <= 127:
			out.append(low_midi + i)
	return out


## Height reserved under the note rows for velocity or pan (0 when both hidden).
func _lane_h() -> float:
	return VEL_H if show_velocity or show_pan else 0.0


## How many note rows fit at a readable height.
func rows_that_fit() -> int:
	return clampi(int((size.y - _lane_h() - 4.0) / MIN_ROW_H), 4, 48)


func _layout() -> void:
	var avail := maxf(size.y - _lane_h() - 4.0, 1.0)
	_rows = fixed_rows if fixed_rows > 0 else rows_that_fit()
	_row_h = avail / _rows
	queue_redraw()


func _cw() -> float:
	return (size.x - LABEL_W) / steps


## Cells across the page: one per song step at 16 per bar, two at 32, four at 64.
func _columns() -> int:
	return steps * steps_per_bar / 16


func _cell_w() -> float:
	return (size.x - LABEL_W) / float(_columns())


## Song-step position of the grid cell under `pos` (a whole 16th, a 32nd or a 64th).
func _song_at(pos: Vector2) -> float:
	var q := 16.0 / float(steps_per_bar)
	var col := clampi(int(floor((pos.x - LABEL_W) / _cell_w())), 0, _columns() - 1)
	return float(base_step()) + col * q


func _note_pos(n: Dictionary) -> float:
	return float(n.start) + float(n.get("off", 0.0))


func _note_dur(n: Dictionary) -> float:
	return float(n.dur) if n.has("dur") else float(n.len)


func _total() -> int:
	return TrackManager.max_steps()


func _row_midi(r: int) -> int:
	# Low notes at the top, high notes further down: same order as the keyboard (low left -> high right).
	return low_midi + r


func _cell(pos: Vector2) -> Vector2i:  # x = absolute song step
	var x := clampi(int(floorf((pos.x - LABEL_W) / _cw())), 0, steps - 1)
	var r := clampi(int(floorf(pos.y / _row_h)), 0, _rows - 1)
	return Vector2i(base_step() + x, r)


func _lane_rect() -> Rect2:
	return Rect2(LABEL_W, size.y - _lane_h(), size.x - LABEL_W, _lane_h())


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var cw := _cw()
	var base := base_step()
	var lh := _lane_h()
	var note_bottom := size.y - lh - (2.0 if lh > 0.0 else 0.0)
	# Smaller type with breathing room; skip sharps when rows are tight.
	var label_size := 9 if _row_h >= 20.0 else (8 if _row_h >= 15.0 else 7)
	var label_sharps := _row_h >= 16.0
	for r in _rows:
		var midi := _row_midi(r)
		var y := r * _row_h
		var pc := midi % 12
		var col := Color("12161d") if pc in BLACK_PCS else Color("181d27")
		if TuningManager.in_scale(midi):
			col = col.lerp(accent, 0.10)
		if TuningManager.is_root(midi):
			col = col.lerp(accent, 0.16)
		draw_rect(Rect2(LABEL_W, y, size.x - LABEL_W, _row_h), col)
		if label_sharps or pc not in BLACK_PCS:
			var label := "%s%d" % [NOTE_NAMES[pc], midi / 12 - 1]
			var lcol := StudioTheme.TEXT if TuningManager.in_scale(midi) else Color(StudioTheme.DIM, 0.55)
			var ty := y + (_row_h + label_size) * 0.5 - 1.0
			draw_string(font, Vector2(3, ty), label, HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 5, label_size, lcol)
	var cols := _columns()
	var cell_w := _cell_w()
	var beat_every := maxi(steps_per_bar / 4, 1)  # a quarter note
	for s in cols + 1:
		var x := LABEL_W + s * cell_w
		var on_bar := s % steps_per_bar == 0
		var on_beat := s % beat_every == 0
		if cell_w < 6.0 and not on_beat:
			continue  # too dense: only draw beats
		var alpha := 0.28 if on_bar else (0.13 if on_beat else 0.045)
		draw_line(Vector2(x, 0), Vector2(x, note_bottom), Color(1, 1, 1, alpha), 1.0)

	if lh > 0.0:
		var lr := _lane_rect()
		draw_rect(lr, Color("10131a"))
		draw_line(Vector2(lr.position.x, lr.position.y), Vector2(lr.end.x, lr.position.y), Color(1, 1, 1, 0.06), 1.0)
		if show_pan:
			_draw_pan_lane(lr, font)
	if track == null:
		return
	# keys being played right now: light up their row and name
	for m in live:
		var live_r: int = int(m) - low_midi
		if live_r >= 0 and live_r < _rows:
			draw_rect(Rect2(0, live_r * _row_h, size.x, _row_h), Color(accent, 0.30))
			draw_rect(Rect2(0, live_r * _row_h, LABEL_W, _row_h), Color(accent, 0.75))
	var now := _now_step()
	if show_velocity:
		var vr2 := _lane_rect()
		var vel_bars := _vel_bars()
		for i in vel_bars.size():  # velocity lane: notes sharing a step get side-by-side bars
			var vb: Dictionary = vel_bars[i]
			var vn: Dictionary = vb.note
			var bar_h: float = vn.vel * (VEL_H - 4)
			var hot: bool = is_same(_drag.get("note"), vn)
			var vc := vel_color(vn.vel)
			var bar := Rect2(vb.x, vr2.end.y - 2 - bar_h, vb.w, bar_h)
			draw_rect(bar, Color(0, 0, 0, 0.35))
			draw_rect(Rect2(bar.position.x, bar.position.y, bar.size.x, maxf(bar.size.y - 1.0, 1.0)), vc.lightened(0.28) if hot else vc)
			if hot and _drag.get("mode", "") == "vel":  # the exact value while dragging
				var txt := "%d%%" % roundi(vn.vel * 100.0)
				draw_string(font, Vector2(clampf(float(vb.x) - 6.0, LABEL_W, size.x - 34.0), vr2.position.y - 4.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	for n in track.notes:
		var p0 := _note_pos(n) - base
		var p1 := p0 + _note_dur(n)
		p0 = maxf(p0, 0.0)
		p1 = minf(p1, float(steps))
		if p1 <= 0.0 or p0 >= steps:
			continue
		var r: int = int(n.midi) - low_midi
		if r < 0 or r >= _rows:
			continue
		var rect := Rect2(LABEL_W + p0 * cw + 1, r * _row_h + 1, maxf((p1 - p0) * cw - 2, 2.0), _row_h - 2)
		var sounding: bool = now >= 0.0 and now >= n.start and now < n.start + n.len
		var nc := vel_color(n.vel)  # the colour is the velocity
		_draw_note(rect, nc.lightened(0.45) if sounding else nc, sounding or _is_selected(n))
	if armed and _hover.x >= 0:  # the paste pointer: the copied notes as they would land under the mouse
		var hmidi := _row_midi(_hover.y)
		var cell := Rect2(LABEL_W + (_hover.x - base) * cw, _hover.y * _row_h, cw, _row_h)
		draw_rect(cell, Color(1, 1, 1, 0.16))
		draw_rect(cell, Color.WHITE, false, 1.5)
		for e in TrackManager.note_clip:
			var gx0: int = maxi(_hover.x + int(e.dstart) - base, 0)
			var gx1: int = mini(_hover.x + int(e.dstart) + int(e.len) - base, steps)
			var gr: int = hmidi + int(e.get("dmidi", 0)) - low_midi
			if gx1 <= 0 or gx0 >= steps or gr < 0 or gr >= _rows:
				continue
			var ghost := Rect2(LABEL_W + gx0 * cw + 1, gr * _row_h + 1, (gx1 - gx0) * cw - 2, _row_h - 2)
			draw_rect(ghost, Color(1, 1, 1, 0.22))
			draw_rect(ghost, Color(1, 1, 1, 0.8), false, 1.0)
	if _drag.get("mode", "") == "box":
		var box := Rect2(_drag.a, _drag.b - _drag.a).abs()
		draw_rect(box, Color(1, 1, 1, 0.12), true)
		draw_rect(box, Color(1, 1, 1, 0.85), false, 1.0)
	for rn in rec_notes:  # being recorded: bright red-ish, grows while the key is held
		var r: int = int(rn.midi) - low_midi
		var f0: float = maxf(float(rn.start) - base, 0.0)
		var f1: float = minf(float(rn.start) + maxf(float(rn.len), 0.5) - base, float(steps))
		if r < 0 or r >= _rows or f1 <= 0.0 or f0 >= steps:
			continue
		var rr := Rect2(LABEL_W + f0 * cw + 1, r * _row_h + 1, maxf((f1 - f0) * cw - 2, 3.0), _row_h - 2)
		draw_rect(rr, Color("ff6b6b"))
		draw_rect(rr, Color.WHITE, false, 1.5)

	var ps := Transport.step - base
	if Transport.playing and ps >= 0 and ps < steps:
		_draw_playhead(LABEL_W + (ps + 0.5) * cw)
	elif playhead >= 0.0:
		var pf := playhead - base
		if pf >= 0.0 and pf <= steps:
			_draw_playhead(LABEL_W + pf * cw)


## Where playback is, in steps (-1 when nothing is playing).
func _now_step() -> float:
	if Transport.playing and Transport.step >= 0:
		return float(Transport.step) + 0.5
	return playhead


## One velocity bar per note that starts on the screen. Notes that start on the same step
## share that step's width side by side (lowest pitch on the left), so each can be grabbed.
func _vel_bars() -> Array:
	var out := []
	if track == null:
		return out
	var base := base_step()
	var cw := _cw()
	var groups := {}
	for n in track.notes:
		if n.start < base or n.start >= base + steps:
			continue
		if not groups.has(n.start):
			groups[n.start] = []
		groups[n.start].append(n)
	for s in groups:
		var list: Array = groups[s]
		list.sort_custom(func(a, b): return a.midi < b.midi)
		var k := list.size()
		var cell_x := LABEL_W + (int(s) - base) * cw
		var slot := cw / k
		for i in k:
			var w := maxf(slot * 0.8, 3.0)
			out.append({"note": list[i], "x": cell_x + slot * i + (slot - w) * 0.5, "w": w})
	return out


## A note block with a soft top highlight and a dark rim (selected / sounding: white rim).
func _draw_note(rect: Rect2, fill: Color, rim: bool) -> void:
	draw_rect(rect, fill)
	if rect.size.y >= 4.0:
		draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, maxf(rect.size.y * 0.28, 1.0)), Color(1, 1, 1, 0.18))
	draw_rect(rect, Color(0, 0, 0, 0.45), false, 1.0)
	if rim:
		draw_rect(rect, Color(1, 1, 1, 0.92), false, 2.0)


func _draw_playhead(px: float) -> void:
	var c := Color.WHITE
	draw_line(Vector2(px, 0), Vector2(px, size.y), Color(c, 0.9), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(px - 5, 0), Vector2(px + 5, 0), Vector2(px, 7)]), c)


func _preview(midi: int) -> void:
	if def == null:
		return
	if _preview_id >= 0:
		AudioEngine.note_off(_preview_id)
	_preview_id = AudioEngine.note_on(def, midi, 0.8, track.preset if track else -1, TrackManager.bus_of(track) if track else "")
	var id := _preview_id
	get_tree().create_timer(0.35).timeout.connect(func(): AudioEngine.note_off(id))


func _changed() -> void:
	TrackManager.notify_changed(track)


func _begin(pos: Vector2) -> void:
	if track == null:
		return
	_drag = {}
	var note_bottom := size.y - _lane_h() - (2.0 if _lane_h() > 0.0 else 0.0)
	if pos.x < LABEL_W and pos.y < note_bottom:  # the note names are keys: click one to hear it
		_preview(_row_midi(_cell(pos).y))
		_drag = {"mode": "key"}
		return
	if show_velocity and _lane_rect().has_point(pos):
		# the bar nearest to the finger wins, so stacked notes can each be picked
		var best := {}
		var best_d := INF
		for vb in _vel_bars():
			var d := absf(pos.x - (float(vb.x) + float(vb.w) * 0.5))
			if d < best_d:
				best_d = d
				best = vb
		if not best.is_empty() and best_d <= maxf(_cw(), 12.0) * 0.6:
			_drag = {"mode": "vel", "note": best.note}
			_set_vel(pos)
			_changed()
		return
	if show_pan and _lane_rect().has_point(pos):
		_pan_last = Vector2(-1, 0)
		_drag = {"mode": "pan"}
		_put_pan(pos)
		return
	if pos.x < LABEL_W or pos.y > note_bottom:
		return
	if select_kind != "":
		var sc := _cell(pos)
		var under := track.note_at(sc.x, _row_midi(sc.y))
		if not under.is_empty() and _is_selected(under):  # grab the selection: drag moves all of it
			var orig := []
			for sn in selection:
				orig.append({"note": sn, "start": int(sn.start), "midi": int(sn.midi)})
			_drag = {"mode": "group", "press": pos, "orig": orig, "tap": true}
		else:  # a box; in copy mode a plain click pastes when armed
			_drag = {"mode": "box", "a": pos, "b": pos, "press": pos, "tap": true}
		queue_redraw()
		return
	# Editing is silent. Empty cell: draw a new note (drag right = longer, up/down = other pitch).
	# Existing note: tap = delete, drag = move, drag its right end = resize.
	var c := _cell(pos)
	var midi := _row_midi(c.y)
	var song := _song_at(pos)
	var n := _note_covering(song, midi)
	if n.is_empty():
		var q := 16.0 / float(steps_per_bar)
		n = track.add_note(int(floor(song + 1e-4)), maxi(1, int(ceil(q - 1e-4))), midi, 0.8)
		_write_span(n, song, q)
		_drag = {"mode": "draw", "note": n, "anchor": song}
		_changed()
		return
	var cw := _cw()
	var note_x1 := LABEL_W + (_note_pos(n) + _note_dur(n) - base_step()) * cw
	var grip := clampf(cw * 0.5, 6.0, 14.0)  # right-end handle, only on notes long enough to keep a body
	if _note_dur(n) > 16.0 / float(steps_per_bar) + 0.01 and pos.x >= note_x1 - grip:
		_drag = {"mode": "resize", "note": n, "press": pos, "tap": true, "anchor": _note_pos(n)}
	else:
		_drag = {"mode": "move", "note": n, "grab": song - _note_pos(n), "press": pos, "tap": true}



## The note sounding at this song position and pitch, or {}.
func _note_covering(song: float, midi: int) -> Dictionary:
	var q := 16.0 / float(steps_per_bar)
	for n in track.notes:
		if int(n.midi) != midi:
			continue
		var a := _note_pos(n)
		var b := a + _note_dur(n)
		if song < b - 0.001 and song + q > a + 0.001:
			return n
	return {}


## Put a note at `pos` (song steps) for `dur` steps. On the 16th grid this is a plain start and length.
func _write_span(n: Dictionary, pos: float, dur: float) -> void:
	var q := 16.0 / float(steps_per_bar)
	pos = clampf(snapped(pos, q), 0.0, float(_total()) - q)
	dur = clampf(snapped(dur, q), q, float(_total()) - pos)
	var start := int(floor(pos + 1e-4))
	var off := pos - start
	var length := maxi(1, int(ceil(pos + dur - 1e-4)) - start)
	n.start = start
	n.len = length
	if off > 0.02:
		n.off = off
	else:
		n.erase("off")
	if absf(dur - float(length)) > 0.02:
		n.dur = dur
	else:
		n.erase("dur")


func _is_selected(n: Dictionary) -> bool:
	for s in selection:
		if is_same(s, n):
			return true
	return false


## Slide the whole selection by how far the mouse moved from where it grabbed (whole steps and
## semitones); the group stops together at the song start / end and the ends of the keyboard.
func _update_group(pos: Vector2) -> void:
	if _drag.get("tap", false):
		if pos.distance_to(_drag.press) < TAP_SLOP:
			return
		_drag["tap"] = false
	var orig: Array = _drag.orig
	if orig.is_empty():
		return
	var lo_s := 1 << 30
	var hi_e := 0
	var lo_m := 127
	var hi_m := 0
	for o in orig:
		lo_s = mini(lo_s, o.start)
		hi_e = maxi(hi_e, o.start + int(o.note.len))
		lo_m = mini(lo_m, o.midi)
		hi_m = maxi(hi_m, o.midi)
	var press: Vector2 = _drag.press
	var dx := int(roundf((pos.x - press.x) / _cw() / snap)) * snap
	var dy := int(roundf((pos.y - press.y) / _row_h))
	dx = clampi(dx, -lo_s, _total() - hi_e)
	dy = clampi(dy, -lo_m, 127 - hi_m)
	if dx == _drag.get("dx", 0) and dy == _drag.get("dy", 0):
		return
	_drag["dx"] = dx
	_drag["dy"] = dy
	for o in orig:
		var n: Dictionary = o.note
		n.start = o.start + dx
		n.midi = o.midi + dy
		if dx != 0:
			n.erase("off")
		if dy != 0:
			n.erase("cents")  # a bend belonged to the old pitch
	_drag["dirty"] = true
	queue_redraw()


func _update_box(pos: Vector2) -> void:
	if _drag.get("tap", false) and pos.distance_to(_drag.press) < TAP_SLOP:
		return
	_drag["tap"] = false
	_drag["b"] = pos
	var ca := _cell(_drag.a)
	var cb := _cell(pos)
	var x0 := mini(ca.x, cb.x)
	var x1 := maxi(ca.x, cb.x) + 1
	var lo := _row_midi(mini(ca.y, cb.y))
	var hi := _row_midi(maxi(ca.y, cb.y))
	selection = []
	for n in track.notes:
		if n.start < x1 and n.start + n.len > x0 and n.midi >= lo and n.midi <= hi:
			selection.append(n)
	queue_redraw()


func _update(pos: Vector2) -> void:
	if _drag.get("mode", "") == "box":
		_update_box(pos)
		return
	if _drag.get("mode", "") == "group":
		_update_group(pos)
		return
	if _drag.is_empty() or track == null or not _drag.has("note"):
		return  # e.g. dragging over the note-name labels (audition only): nothing to edit
	var n: Dictionary = _drag.note
	if _drag.get("tap", false):
		if pos.distance_to(_drag.press) < TAP_SLOP:
			return
		_drag["tap"] = false  # it really moved: not a tap
	var c := _cell(pos)
	var before := [n.start, n.len, n.midi, n.get("off", 0.0), n.get("dur", 0.0)]
	var q := 16.0 / float(steps_per_bar)
	var song := _song_at(pos)
	match _drag.mode:
		"vel":
			_set_vel(pos)
			queue_redraw()
			return
		"pan":
			_put_pan(pos)
			return
		"draw", "resize":
			var anchor: float = _drag.anchor
			var dur := clampf(song + q - anchor, q, float(_total()) - anchor)
			_write_span(n, anchor, dur)
			if _drag.mode == "draw":
				n.midi = _row_midi(c.y)
		"move":
			var dur_m := _note_dur(n)
			var np := clampf(song - float(_drag.grab), 0.0, float(_total()) - dur_m)
			_write_span(n, snapped(np, q), dur_m)
			n.midi = _row_midi(c.y)
	if before != [n.start, n.len, n.midi, n.get("off", 0.0), n.get("dur", 0.0)]:
		if steps_per_bar == 16:  # a hand edit on the normal grid drops the sung timing
			n.erase("off")
			n.erase("dur")
		if before[2] != n.midi:
			n.erase("cents")
		_drag["dirty"] = true
		queue_redraw()


func _end() -> void:
	if _drag.get("mode", "") == "group":
		var moved: bool = _drag.get("dirty", false)
		_drag = {}
		if moved:
			_changed()
			selection_moved.emit()
		queue_redraw()
		return
	if _drag.get("mode", "") == "pan":
		track.pan_curve.sort_custom(func(a, b): return a[0] < b[0])
		TrackManager.apply_mix()
		_changed()
		_drag = {}
		_pan_last = Vector2(-1, 0)
		queue_redraw()
		return
	if _drag.get("mode", "") == "box":
		var was_click: bool = _drag.get("tap", false)
		var at := _cell(_drag.a)
		_drag = {}
		if was_click:
			if select_kind == "copy" and armed:
				paste_requested.emit(at.x, _row_midi(at.y))  # the click picks the paste cell
			else:
				selection = []
		elif selection.is_empty():
			pass  # empty box: keep any earlier copy armed in copy mode
		elif select_kind == "copy":
			armed = true  # next click pastes
			selection_made.emit()
		# move mode: selection stays highlighted for dragging / arrow keys
		queue_redraw()
		return
	if track != null and _drag.has("note"):
		if _drag.get("tap", false):
			track.remove_note(_drag.note)  # tap on a note = delete it
			_changed()
		elif _drag.get("dirty", false) or _drag.mode == "vel":
			_changed()
	_drag = {}


func _set_vel(pos: Vector2) -> void:
	if not _drag.has("note"):
		return
	var vr := _lane_rect()
	_drag.note.vel = clampf(1.0 - (pos.y - vr.position.y) / VEL_H, 0.05, 1.0)


func _draw_pan_lane(lr: Rect2, font: Font) -> void:
	draw_line(Vector2(lr.position.x, lr.position.y + lr.size.y * 0.5), Vector2(lr.end.x, lr.position.y + lr.size.y * 0.5), Color(1, 1, 1, 0.2), 1.0)
	draw_string(font, Vector2(6, lr.position.y + 14), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, StudioTheme.DIM)
	draw_string(font, Vector2(6, lr.end.y - 4), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, StudioTheme.DIM)
	if track == null:
		return
	var base := base_step()
	var cw := _cw()
	var col := accent
	var pts: Array = []
	for p in track.pan_curve:
		var s := int(p[0])
		if s >= base and s < base + steps:
			pts.append(p)
	pts.sort_custom(func(a, b): return a[0] < b[0])
	if pts.is_empty():
		var y := lr.position.y + (0.5 - track.pan * 0.5) * lr.size.y
		draw_line(Vector2(lr.position.x, y), Vector2(lr.end.x, y), col.darkened(0.25), 2.0)
	else:
		var line := PackedVector2Array()
		for p in pts:
			var x := LABEL_W + (float(p[0]) - base + 0.5) * cw
			var y := lr.position.y + (0.5 - float(p[1]) * 0.5) * lr.size.y
			line.append(Vector2(x, y))
		if line.size() > 1:
			draw_polyline(line, col, 2.5, true)
		for pt in line:
			draw_circle(pt, 2.2, col)


func _put_pan(pos: Vector2) -> void:
	if track == null:
		return
	var lr := _lane_rect()
	var step := clampi(int(floor((pos.x - LABEL_W) / _cw())) + base_step(), 0, _total() - 1)
	var pan := clampf((0.5 - (pos.y - lr.position.y) / maxf(lr.size.y, 1.0)) * 2.0, -1.0, 1.0)
	if absf(pan) < 0.05:
		pan = 0.0
	var from := step
	var p0 := pan
	if _pan_last.x >= 0.0:
		from = int(_pan_last.x)
		p0 = _pan_last.y
	var a := mini(from, step)
	var b := maxi(from, step)
	for k in range(a, b + 1):
		var f := 1.0 if b == a else float(k - from) / float(step - from) if step != from else 1.0
		_set_pan_point(k, lerpf(p0, pan, clampf(f, 0.0, 1.0)))
	_pan_last = Vector2(step, pan)
	queue_redraw()


func _set_pan_point(step: int, pan: float) -> void:
	for i in track.pan_curve.size():
		if int(track.pan_curve[i][0]) == step:
			track.pan_curve[i][1] = pan
			return
	track.pan_curve.append([step, pan])


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_begin(e.position)
		else:
			_end()
		accept_event()
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_update(e.position)
	elif e is InputEventMouseMotion and armed:  # the paste pointer follows the mouse
		var inside: bool = e.position.x >= LABEL_W and e.position.y < size.y - _lane_h() - 2.0
		var at := _cell(e.position) if inside else Vector2i(-1, -1)
		if at != _hover:
			_hover = at
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover.x >= 0:
		_hover = Vector2i(-1, -1)
		queue_redraw()
