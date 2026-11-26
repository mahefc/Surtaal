class_name LayerPanel
extends PopupPanel
## Everything about one drum layer, opened by tapping its card in the loop grid:
## change its sound, pitch, volume, mute, or remove it. Each change is heard straight away.

signal change_sound_requested(lane_key: String)

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

var track: Track
var _key := ""
var _art: InstrumentArt
var _title: Label
var _sub: Label
var _pitch: Label
var _vol: HSlider
var _vol_pct: Label
var _mute: IconButton


func _init() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	add_child(m)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)

	# who: the layer's picture, its name and instrument
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	_art = InstrumentArt.new()
	_art.custom_minimum_size = Vector2(34, 34)
	_art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_art)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 17)
	names.add_child(_title)
	_sub = _small_label("")
	names.add_child(_sub)
	var done := IconButton.create("close", "Done", Vector2(36, 34))
	done.pressed.connect(hide)
	head.add_child(done)

	# the big action: pick another sound for this layer
	var change := _action("swap", "  Change sound", "Pick another instrument for this layer (its hits stay)", func():
		var k := _key
		hide()
		change_sound_requested.emit(k))
	v.add_child(change)

	# pitch:  Pitch   [-]  C2  [+]
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 8)
	v.add_child(pr)
	var pl := _small_label("Pitch")
	pl.custom_minimum_size = Vector2(52, 0)
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pr.add_child(pl)
	var down := IconButton.create("minus", "Lower the pitch", Vector2(38, 34))
	down.pressed.connect(func(): _nudge(-1))
	pr.add_child(down)
	_pitch = Label.new()
	_pitch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pitch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pitch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pitch.add_theme_font_size_override("font_size", 16)
	pr.add_child(_pitch)
	var up := IconButton.create("plus", "Raise the pitch", Vector2(38, 34))
	up.pressed.connect(func(): _nudge(1))
	pr.add_child(up)

	# volume:  [speaker] ------o------ 85%
	var vr := HBoxContainer.new()
	vr.add_theme_constant_override("separation", 10)
	v.add_child(vr)
	var g := Control.new()
	g.custom_minimum_size = Vector2(26, 26)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var glyph := IconGlyph.new("speaker")
	glyph.glyph_scale = 0.28
	glyph.glyph_color = StudioTheme.DIM
	g.add_child(glyph)
	vr.add_child(g)
	_vol = HSlider.new()
	_vol.min_value = 0.1
	_vol.max_value = 1.0
	_vol.step = 0.01
	_vol.focus_mode = Control.FOCUS_NONE
	_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol.custom_minimum_size = Vector2(0, 30)
	_vol.value_changed.connect(_on_volume)
	_vol.drag_ended.connect(func(_c: bool):
		var lane := _lane()
		if not lane.is_empty():
			TrackManager.notify_changed(track)
			TrackManager.audition_drum(track, lane))
	vr.add_child(_vol)
	_vol_pct = _small_label("")
	_vol_pct.custom_minimum_size = Vector2(40, 0)
	_vol_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_vol_pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vr.add_child(_vol_pct)

	# mute and remove, side by side
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 6)
	v.add_child(br)
	_mute = _action("muted", "  Mute", "Silence this layer (its hits stay)", _toggle_mute)
	br.add_child(_mute)
	br.add_child(_action("trash", "  Remove", "Remove this layer from the loop", func():
		var k := _key
		hide()
		TrackManager.remove_drum_lane(track, k)))


func _action(icon: String, text: String, tip: String, cb: Callable) -> IconButton:
	var b := IconButton.create(icon, tip, Vector2(0, 40))
	b.text = text
	b.glyph.icon_left = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(cb)
	return b


func _small_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", StudioTheme.DIM)
	return l


func _lane() -> Dictionary:
	if track == null:
		return {}
	var i := track.lane_index(_key)
	return track.drum_lanes[i] if i != -1 else {}


## Show the panel for a layer, near `anchor` (a global rectangle, e.g. the layer's card).
func open_for(t: Track, lane_key: String, anchor: Rect2) -> void:
	track = t
	_key = lane_key
	_refresh()
	reset_size()
	popup_on_parent(Rect2i(Vector2i(anchor.position + Vector2(anchor.size.x, 0)), Vector2i(1, 1)))


func _refresh() -> void:
	var lane := _lane()
	if lane.is_empty():
		return
	var def := InstrumentManager.get_by_id(lane.id)
	_title.text = lane.key
	_sub.text = def.display_name if def else ""
	_art.kind = InstrumentArt.kind_of(def)
	_art.tint = def.color if def else StudioTheme.ACCENT
	_pitch.text = "%s%d" % [NOTE_NAMES[int(lane.midi) % 12], int(lane.midi) / 12 - 1]
	_vol.set_value_no_signal(float(lane.vol))
	_vol_pct.text = "%d%%" % int(float(lane.vol) / 0.85 * 100.0)
	_mute.text = "  Unmute" if lane.mute else "  Mute"
	_mute.icon_name = "muted" if lane.mute else "speaker"


func _nudge(semitones: int) -> void:
	var lane := _lane()
	if lane.is_empty():
		return
	lane.midi = clampi(int(lane.midi) + semitones, 12, 108)
	var def := InstrumentManager.get_by_id(lane.id)
	if def:
		SampleManager.prebake(def, [lane.midi], 0, true)
	TrackManager.notify_changed(track)
	_refresh()
	TrackManager.audition_drum(track, lane)


func _on_volume(x: float) -> void:
	var lane := _lane()
	if lane.is_empty():
		return
	lane.vol = x
	_vol_pct.text = "%d%%" % int(x / 0.85 * 100.0)


func _toggle_mute() -> void:
	var lane := _lane()
	if lane.is_empty():
		return
	lane.mute = not lane.mute
	TrackManager.notify_changed(track)
	_refresh()
