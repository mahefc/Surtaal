class_name ArrangementView
extends VBoxContainer
## Home screen = the song as tracks over a time ruler, with a mixer on every row:
## play-alone, mute, solo, volume and pan. Songs are as long as you make them (up
## to 10 minutes): there are no bars to set. Export bounces the mix to MP3/WAV.

signal open_track(track: Track)
signal export_requested
signal loop_builder_requested   # the "Loop" answer of the + chooser
signal add_instrument_requested
signal add_voice_requested
signal import_audio_requested   # the "Import" answer of the + chooser: a wav / mp3 / ogg file on a new track
signal home_requested

const HEAD_W := 240.0
const ROW_H := 44.0
const RULER_H := 32.0
const ZB := 30.0  # width of the zoom / menu buttons at the ends of the ruler
const MENU_NEW := 1
const MENU_TITLE := 2
const MENU_RENAME := 3
const MENU_DUP := 4
const MENU_EXPORT := 6
const MENU_HOME := 7

var _bar: HBoxContainer
var _undo_btn: IconButton
var _redo_btn: IconButton
var _project_menu: MenuButton
var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _play_btn: IconButton
var _bpm_menu: Button
var _bpm_pop: PopupPanel
var _ruler: TimelineRuler
var _ruler_scroll: ScrollContainer  # follows _hscroll, so the header row never scrolls away

var _vscroll: ScrollContainer
var _heads: VBoxContainer
var _hscroll: ScrollContainer
var _lanes: VBoxContainer
var _empty: Label
var _lane_nodes: Array[TrackLane] = []
var _play_btns := {}  # Track -> IconButton
var _mix_popup: TrackMixPopup
var _add_popup: AddChoicePopup
var _delete_dialog: ConfirmationDialog
var _menu_track: Track


func _init() -> void:
	add_theme_constant_override("separation", 6)
	# ONE header row: [undo redo play tempo] [zoom -] [time ruler] [zoom +] [menu]
	# so the controls and the timeline share a line, and it stays put while the tracks scroll.
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	add_child(_bar)
	_build_bar()
	_build_timeline()
	_build_popups()


func _ready() -> void:
	TrackManager.tracks_changed.connect(_rebuild_rows)
	TrackManager.length_changed.connect(_relayout_lanes)
	TrackManager.only_changed.connect(_refresh_play_icons)
	ProjectManager.state_changed.connect(_on_project_state)
	ProjectManager.project_list_changed.connect(_rebuild_project_menu)
	Transport.started.connect(_refresh_play_icons)
	Transport.stopped.connect(_refresh_play_icons)
	Transport.bpm_changed.connect(_update_labels)
	_hscroll.resized.connect(_relayout_lanes)
	_hscroll.get_h_scroll_bar().value_changed.connect(func(v: float): _ruler_scroll.scroll_horizontal = int(v))
	_rebuild_project_menu()
	_on_project_state()
	_rebuild_rows()


func _process(_d: float) -> void:
	if not is_visible_in_tree():
		return
	_update_labels()
	if _ruler_scroll.scroll_horizontal != _hscroll.scroll_horizontal:
		_ruler_scroll.scroll_horizontal = _hscroll.scroll_horizontal
	if Transport.playing and Transport.step >= 0:  # keep the playhead in view
		var x := (Transport.step + 0.5) * TrackLane.px_per_step
		var left := _hscroll.scroll_horizontal
		var right := left + _hscroll.size.x
		if x > right - 60.0 or x < left:
			_hscroll.scroll_horizontal = int(maxf(x - 80.0, 0.0))


# ------------------------------------------------------------- header
func _build_bar() -> void:
	var bar := _bar
	# the menu is the first thing in the header
	_project_menu = MenuButton.new()
	_project_menu.tooltip_text = "Menu: export, projects, rename... (your work saves itself)"
	_project_menu.focus_mode = Control.FOCUS_NONE
	_project_menu.custom_minimum_size = Vector2(ZB, 30)
	_project_menu.add_child(IconGlyph.new("menu"))
	_project_menu.get_popup().id_pressed.connect(_on_project_menu)
	_project_menu.get_popup().about_to_popup.connect(_rebuild_project_menu)  # fresh title every time it opens
	bar.add_child(_project_menu)

	# above the track names: undo, redo, play, tempo. Sized so the ruler starts exactly
	# where the lanes below start, and both run to the right edge of the screen.
	var corner := HBoxContainer.new()
	corner.custom_minimum_size = Vector2(HEAD_W - ZB - 16.0, RULER_H)
	corner.add_theme_constant_override("separation", 3)
	bar.add_child(corner)
	_undo_btn = IconButton.create("undo", "Undo", Vector2(28, 30))
	_undo_btn.pressed.connect(ProjectManager.undo)
	corner.add_child(_undo_btn)
	_redo_btn = IconButton.create("redo", "Redo", Vector2(28, 30))
	_redo_btn.pressed.connect(ProjectManager.redo)
	corner.add_child(_redo_btn)
	corner.add_child(_gap(4))
	_play_btn = IconButton.create("play", "Play from the start marker (tap the time ruler to move it)", Vector2(34, 30))
	_play_btn.glyph.glyph_color = Color.WHITE
	StudioTheme.tint_button(_play_btn, Color("2ed3b7").darkened(0.45))
	_play_btn.pressed.connect(_on_play)
	corner.add_child(_play_btn)
	# tempo: the button shows the number; tapping it offers a minus and a plus icon
	_bpm_menu = Button.new()
	_bpm_menu.tooltip_text = "Tempo (beats per minute)"
	_bpm_menu.focus_mode = Control.FOCUS_NONE
	_bpm_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bpm_menu.custom_minimum_size = Vector2(0, 30)
	_bpm_menu.add_theme_font_size_override("font_size", 12)
	_bpm_menu.pressed.connect(func():
		var gp := _bpm_menu.get_global_rect().position + Vector2(0, _bpm_menu.size.y + 4)
		_bpm_pop.popup_on_parent(Rect2i(Vector2i(gp), Vector2i(1, 1))))
	corner.add_child(_bpm_menu)
	_bpm_pop = PopupPanel.new()
	var bpm_row := HBoxContainer.new()
	bpm_row.add_theme_constant_override("separation", 6)
	_bpm_pop.add_child(bpm_row)
	var slower := IconButton.create("minus", "Remove 5 BPM", Vector2(36, 32))
	slower.pressed.connect(func(): Transport.bpm -= 5.0)
	var faster := IconButton.create("plus", "Add 5 BPM", Vector2(36, 32))
	faster.pressed.connect(func(): Transport.bpm += 5.0)
	bpm_row.add_child(slower)
	bpm_row.add_child(faster)
	add_child(_bpm_pop)

	# the time ruler runs to the screen edge, in line with the tracks. The zoom icons sit
	# on it, small, one at each end.
	var ruler_box := Control.new()
	ruler_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ruler_box.custom_minimum_size = Vector2(0, RULER_H)
	bar.add_child(ruler_box)
	_ruler_scroll = ScrollContainer.new()
	_ruler_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ruler_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_ruler_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ruler_box.add_child(_ruler_scroll)
	_ruler = TimelineRuler.new()
	_ruler_scroll.add_child(_ruler)
	ruler_box.add_child(_zoom_icon("zoomout", "Zoom out the timeline", 1.0 / 1.5, false))
	ruler_box.add_child(_zoom_icon("zoomin", "Zoom in the timeline", 1.5, true))

	AudioEngine.set_master_volume(0.9)

	_name_dialog = ConfirmationDialog.new()
	_name_dialog.title = "Project name"
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(240, 0)
	_name_dialog.add_child(_name_edit)
	_name_dialog.confirmed.connect(func(): ProjectManager.rename(_name_edit.text))
	add_child(_name_dialog)


## A small zoom button anchored to one end of the time ruler, centred on its line.
func _zoom_icon(icon: String, tip: String, factor: float, right: bool) -> IconButton:
	var b := IconButton.create(icon, tip, Vector2(22, 22))
	b.anchor_top = 0.5
	b.anchor_bottom = 0.5
	b.offset_top = -11.0
	b.offset_bottom = 11.0
	if right:
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.offset_left = -24.0
		b.offset_right = -2.0
	else:
		b.offset_left = 2.0
		b.offset_right = 24.0
	b.pressed.connect(func(): _zoom(factor))
	return b


func _gap(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c

func _rebuild_project_menu() -> void:
	var pop := _project_menu.get_popup()
	pop.clear()
	pop.add_item(ProjectManager.project_name, MENU_TITLE)
	pop.set_item_disabled(0, true)
	pop.add_separator()
	pop.add_item("Export song (MP3 / WAV)...", MENU_EXPORT)
	pop.add_item("All projects", MENU_HOME)
	pop.add_separator()
	pop.add_item("New project", MENU_NEW)
	pop.add_item("Rename...", MENU_RENAME)
	pop.add_item("Duplicate", MENU_DUP)


func _on_project_menu(id: int) -> void:
	match id:
		MENU_EXPORT:
			export_requested.emit()
		MENU_HOME:
			home_requested.emit()
		MENU_NEW:
			Transport.stop()
			ProjectManager.new_project()
		MENU_RENAME:
			_name_edit.text = ProjectManager.project_name
			_name_dialog.popup_centered()
		MENU_DUP:
			ProjectManager.duplicate_project()


func _on_project_state() -> void:
	_undo_btn.disabled = not ProjectManager.can_undo()
	_redo_btn.disabled = not ProjectManager.can_redo()


# ---------------------------------------------------------- transport
func _zoom(factor: float) -> void:
	TrackLane.px_per_step = clampf(TrackLane.px_per_step * factor, 0.6, 18.0)
	_relayout_lanes()


func _update_labels() -> void:
	var bpm_text := "%d BPM" % int(Transport.bpm)
	if _bpm_menu.text != bpm_text:
		_bpm_menu.text = bpm_text


func _on_play() -> void:
	if Transport.playing:
		Transport.stop()
		return
	if not TrackManager.has_audible_content():
		return
	_play_btn.disabled = true
	await TrackManager.play_all()
	_play_btn.disabled = false


func _refresh_play_icons() -> void:
	_play_btn.icon_name = "stop" if (Transport.playing and TrackManager.only == null) else "play"
	for t in _play_btns:
		var b: IconButton = _play_btns[t]
		b.icon_name = "stop" if (Transport.playing and TrackManager.only == t) else "play"


# ----------------------------------------------------------- timeline
func _build_timeline() -> void:
	_vscroll = ScrollContainer.new()
	_vscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_vscroll)
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	_vscroll.add_child(box)

	_heads = VBoxContainer.new()
	_heads.custom_minimum_size = Vector2(HEAD_W, 0)
	_heads.add_theme_constant_override("separation", 8)
	box.add_child(_heads)

	_hscroll = ScrollContainer.new()
	_hscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_hscroll)
	_lanes = VBoxContainer.new()
	_lanes.add_theme_constant_override("separation", 8)
	_hscroll.add_child(_lanes)

	_empty = Label.new()
	_empty.text = "Your song is empty.\n\nTap  Add track  on the left,  choose an instrument,\nthen hum a melody or play the keys."
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_theme_color_override("font_color", StudioTheme.DIM)
	_empty.custom_minimum_size = Vector2(0, 150)
	_empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _rebuild_rows() -> void:
	for c in _heads.get_children():
		_heads.remove_child(c)
		c.queue_free()
	for c in _lanes.get_children():
		_lanes.remove_child(c)
		if c != _empty:
			c.queue_free()
	_lane_nodes.clear()
	_play_btns.clear()

	if TrackManager.tracks.is_empty():
		_lanes.add_child(_empty)
	for t in TrackManager.tracks:
		_heads.add_child(_make_head(t))
		var lane := TrackLane.new()
		lane.track = t
		lane.custom_minimum_size = Vector2(0, ROW_H)
		lane.tapped.connect(func(): open_track.emit(t))
		_lanes.add_child(lane)
		_lane_nodes.append(lane)

	# "Add track" lives in the track list itself, right under the last track
	var add := Button.new()
	add.text = "     Add track"
	add.focus_mode = Control.FOCUS_NONE
	add.custom_minimum_size = Vector2(HEAD_W, ROW_H)
	add.tooltip_text = "Add an instrument, a drum loop or your voice"
	add.add_theme_font_size_override("font_size", 13)
	StudioTheme.tint_button(add, StudioTheme.ACCENT.darkened(0.25))
	var plus := IconGlyph.new("plus")
	plus.glyph_color = Color.WHITE
	plus.icon_left = true
	add.add_child(plus)
	add.pressed.connect(func(): _add_popup.popup_centered())
	_heads.add_child(add)
	_relayout_lanes()
	_refresh_play_icons()
	_update_labels()


## Lane width = song length at the current zoom (plus room to grow), never narrower than the view.
func _relayout_lanes() -> void:
	var w := maxf(TrackManager.song_steps * TrackLane.px_per_step + 16 * 4 * TrackLane.px_per_step, _hscroll.size.x - 4.0)
	for lane in _lane_nodes:
		lane.custom_minimum_size = Vector2(w, ROW_H)
		lane.queue_redraw()
	_ruler.custom_minimum_size = Vector2(w, RULER_H)
	_ruler.queue_redraw()
	_empty.custom_minimum_size.x = maxf(_hscroll.size.x - 8.0, 100.0)


func _make_head(t: Track) -> Control:
	var col := TrackManager.color_of(t)
	var head := PanelContainer.new()
	head.custom_minimum_size = Vector2(HEAD_W, ROW_H)
	var hs := StudioTheme.box(StudioTheme.PANEL_HI, 10, 0, Color.TRANSPARENT, 6)
	hs.border_width_left = 5
	hs.border_color = col
	hs.content_margin_top = 2
	hs.content_margin_bottom = 2
	head.add_theme_stylebox_override("panel", hs)
	# one thin line: name | play | solo | delete | menu (volume, pan, reverb, move, duplicate live in the menu)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	head.add_child(row)
	# picture of the instrument, then its name (tap = open the track to play / edit)
	var art := InstrumentArt.new()
	art.custom_minimum_size = Vector2(30, 30)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.tint = col
	if t.kind == "melodic":
		art.kind = InstrumentArt.kind_of(InstrumentManager.get_by_id(t.instrument_id))
	else:
		art.kind = "drum" if t.kind == "drums" else "mic"
	row.add_child(art)
	var name_btn := Button.new()
	name_btn.text = t.name
	name_btn.flat = true
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.clip_text = true
	name_btn.focus_mode = Control.FOCUS_NONE
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.add_theme_font_size_override("font_size", 12)
	name_btn.add_theme_color_override("font_color", col)
	name_btn.tooltip_text = "Open this track"
	name_btn.pressed.connect(func(): open_track.emit(t))
	row.add_child(name_btn)
	var play := IconButton.create("play", "Play only this track (from its first note)", Vector2(24, 24))
	play.pressed.connect(func(): _play_one(t))
	row.add_child(play)
	_play_btns[t] = play
	var mute := IconButton.create("speaker" if not t.muted else "muted", "Mute this track", Vector2(24, 24))
	mute.toggle_mode = true
	mute.button_pressed = t.muted
	mute.add_theme_stylebox_override("pressed", StudioTheme.box(Color("5a6272"), 8, 0, Color.TRANSPARENT, 4))
	mute.toggled.connect(func(on: bool):
		t.muted = on
		mute.icon_name = "muted" if on else "speaker"
		name_btn.add_theme_color_override("font_color", Color(col, 0.45) if on else col)
		TrackManager.mix_changed())
	if t.muted:
		name_btn.add_theme_color_override("font_color", Color(col, 0.45))
	row.add_child(mute)
	var solo := IconButton.create("solo", "Solo: hear only this track in the song", Vector2(24, 24))
	solo.toggle_mode = true
	solo.button_pressed = t.solo
	solo.add_theme_stylebox_override("pressed", StudioTheme.box(Color("e8b04a"), 8, 0, Color.TRANSPARENT, 4))
	solo.toggled.connect(func(on: bool):
		t.solo = on
		TrackManager.mix_changed())
	row.add_child(solo)
	var del := IconButton.create("trash", "Delete this track", Vector2(24, 24))
	del.pressed.connect(func(): _ask_delete(t))
	row.add_child(del)
	var more := IconButton.create("menu", "Track options: name, volume, pan, order, duplicate", Vector2(24, 24))
	more.pressed.connect(func(): _mix_popup.open_for(t, false, more))
	row.add_child(more)
	return head


func _play_one(t: Track) -> void:
	if t.has_content():
		TrackManager.play_only(t)


# ------------------------------------------------- per-track popups
func _build_popups() -> void:
	_mix_popup = TrackMixPopup.new()
	add_child(_mix_popup)
	_add_popup = AddChoicePopup.new()
	_add_popup.chosen.connect(_on_add_chosen)
	add_child(_add_popup)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.confirmed.connect(func():
		if _menu_track:
			Transport.stop()
			TrackManager.remove_track(_menu_track))
	add_child(_delete_dialog)


func _on_add_chosen(kind: String) -> void:
	match kind:
		"instrument":
			add_instrument_requested.emit()
		"loop":
			loop_builder_requested.emit()
		"voice":
			add_voice_requested.emit()
		"import":
			import_audio_requested.emit()


func _ask_delete(t: Track) -> void:
	_menu_track = t
	_delete_dialog.dialog_text = "Delete \"%s\" and everything in it?\n(Undo brings it back.)" % t.name
	_delete_dialog.popup_centered()
