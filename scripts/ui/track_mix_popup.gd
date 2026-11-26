class_name TrackMixPopup
extends PopupPanel
## Everything about one track that doesn't need to be on its row: its name, volume, pan,
## drawing the pan, list order, duplicate, and (loop tracks) how long the loop plays.
## `minimal = true` shows only the reverb slider (used by the instrument editor).

## How many times the loop pattern repeats (you can also drag the loop's right edge in the timeline).
const LOOP_REPEATS := [["1 loop", 1], ["2 loops", 2], ["4 loops", 4], ["8 loops", 8], ["16 loops", 16], ["32 loops", 32]]

var track: Track
var _minimal := false
var _title: Label
var _name_row: Control
var _name_edit: LineEdit
var _art: InstrumentArt
var _vol_row: Control
var _pan_row: Control
var _rev_row: Control
var _vol: HSlider
var _pan: HSlider
var _rev: HSlider
var _time_box: Control
var _loop_box: Control
var _loop_opt: OptionButton


func _init() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	add_child(m)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)

	# editor mode: just a title
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	v.add_child(_title)

	# song mode: the track's picture and its name, edited right here
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 10)
	_name_row = nr
	v.add_child(nr)
	_art = InstrumentArt.new()
	_art.custom_minimum_size = Vector2(32, 32)
	_art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nr.add_child(_art)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Track name"
	_name_edit.max_length = 28
	_name_edit.select_all_on_focus = true
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size = Vector2(0, 38)
	_name_edit.text_submitted.connect(func(_t: String): _commit_name())
	nr.add_child(_name_edit)
	popup_hide.connect(_commit_name)

	_vol = _slider(0.0, 1.0)
	_vol_row = _icon_slider("speaker", _vol, v)
	_vol.value_changed.connect(func(x: float):
		track.volume = x
		TrackManager.apply_mix())

	_pan = _slider(-1.0, 1.0)
	_pan_row = _pan_slider(_pan, v)
	_pan.value_changed.connect(func(x: float):
		track.pan = 0.0 if absf(x) < 0.06 else x
		TrackManager.apply_mix())

	_rev = _slider(0.0, 1.0)
	_rev_row = _icon_slider("reverb", _rev, v)
	_rev.value_changed.connect(func(x: float):
		track.reverb = x
		TrackManager.apply_mix())
	for s in [_vol, _pan, _rev]:  # one undo / dirty step per drag
		s.drag_ended.connect(func(_c: bool): TrackManager.notify_changed(track))

	# loop tracks: how long the loop plays
	var lb := VBoxContainer.new()
	lb.add_theme_constant_override("separation", 4)
	_loop_box = lb
	v.add_child(lb)
	lb.add_child(_small_label("Loop plays for"))
	_loop_opt = OptionButton.new()
	_loop_opt.focus_mode = Control.FOCUS_NONE
	_loop_opt.fit_to_longest_item = false
	_loop_opt.custom_minimum_size = Vector2(0, 38)
	for l in LOOP_REPEATS:
		_loop_opt.add_item(l[0])
	_loop_opt.item_selected.connect(func(i: int):
		track.drum_len = LOOP_REPEATS[i][1] * track.pattern_steps()
		TrackManager.notify_changed(track))
	lb.add_child(_loop_opt)

	# order + duplicate: three compact buttons on one line
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 6)
	_time_box = tb
	v.add_child(tb)
	tb.add_child(_action("up", "  Up", "Move this track up in the list", func(): TrackManager.move_track(track, -1)))
	tb.add_child(_action("down", "  Down", "Move this track down in the list", func(): TrackManager.move_track(track, 1)))
	tb.add_child(_action("copy", "  Copy", "Duplicate this track", func():
		TrackManager.duplicate_track(track)
		hide()))


func _action(icon: String, text: String, tip: String, cb: Callable) -> IconButton:
	var b := IconButton.create(icon, tip, Vector2(0, 38))
	b.text = text
	b.glyph.icon_left = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b


func _slider(lo: float, hi: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 30)
	return s


func _small_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", StudioTheme.DIM)
	return l


## [icon] ------o------   (volume, reverb)
func _icon_slider(icon: String, slider: HSlider, parent: Control) -> Control:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	var g := Control.new()
	g.custom_minimum_size = Vector2(26, 26)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var glyph := IconGlyph.new(icon)
	glyph.glyph_scale = 0.28
	glyph.glyph_color = StudioTheme.DIM
	g.add_child(glyph)
	r.add_child(g)
	r.add_child(slider)
	parent.add_child(r)
	return r


## L ------o------ R
func _pan_slider(slider: HSlider, parent: Control) -> Control:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	var l := _small_label("L")
	l.custom_minimum_size = Vector2(26, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.add_child(l)
	r.add_child(slider)
	var rr := _small_label("R")
	rr.custom_minimum_size = Vector2(26, 0)
	rr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.add_child(rr)
	parent.add_child(r)
	return r


## Apply the name typed in the box (on Enter, or when the popup closes).
func _commit_name() -> void:
	if track == null or _minimal or _name_edit.text.strip_edges() == track.name:
		return
	TrackManager.rename_track(track, _name_edit.text)


## Show the popup for a track under `anchor` (or centred).
func open_for(t: Track, minimal: bool = false, anchor: Control = null) -> void:
	track = t
	_minimal = minimal
	_title.text = "Reverb  -  %s" % t.name
	_title.visible = minimal
	_name_row.visible = not minimal
	_name_edit.text = t.name
	if t.kind == "melodic":
		_art.kind = InstrumentArt.kind_of(InstrumentManager.get_by_id(t.instrument_id))
	else:
		_art.kind = "drum" if t.kind == "drums" else "mic"
	_art.tint = TrackManager.color_of(t)
	_vol.set_value_no_signal(t.volume)
	_pan.set_value_no_signal(t.pan)
	_rev.set_value_no_signal(t.reverb)
	_vol_row.visible = not minimal
	_pan_row.visible = not minimal
	_rev_row.visible = minimal
	_time_box.visible = not minimal
	_loop_box.visible = not minimal and t.kind == "drums"
	var idx := 0
	var reps := float(t.drum_len) / maxf(t.pattern_steps(), 1.0)
	for i in LOOP_REPEATS.size():
		if absf(LOOP_REPEATS[i][1] - reps) < absf(LOOP_REPEATS[idx][1] - reps):
			idx = i
	_loop_opt.select(idx)
	reset_size()
	if anchor:
		var gp := anchor.get_global_rect().position + Vector2(0, anchor.size.y + 4)
		popup_on_parent(Rect2i(Vector2i(gp), Vector2i(1, 1)))
	else:
		popup_centered()
