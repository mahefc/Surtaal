extends Control
## App shell / screen router.
##   Arrangement (home)  ->  Add track -> Instrument picker -> Track editor
## Layouts are container-driven so every screen reflows between portrait and
## landscape without losing state.

var _body: MarginContainer
var _home: ProjectHome
var _change_track: Track
var _arrangement: ArrangementView
var _editor: TrackEditor
var _audio_editor: AudioTrackEditor
var _picker: InstrumentPicker
var _export: ExportDialog
var _importer: AudioImporter
var _pick_mode := "track"  # "track" | "change" | "layer" | "swap"
var _swap_key := ""        # drum layer whose sound is being swapped


func _ready() -> void:
	theme = StudioTheme.build()
	_add_background()

	_body = MarginContainer.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_body)
	_home = ProjectHome.new()
	_body.add_child(_home)
	_home.project_opened.connect(_show_arrangement)
	_arrangement = ArrangementView.new()
	_arrangement.visible = false
	_body.add_child(_arrangement)
	_arrangement.home_requested.connect(_show_home)
	_editor = TrackEditor.new()
	_editor.visible = false
	_body.add_child(_editor)
	_audio_editor = AudioTrackEditor.new()
	_audio_editor.visible = false
	_body.add_child(_audio_editor)
	_audio_editor.back_requested.connect(_show_arrangement)

	_picker = InstrumentPicker.new()
	add_child(_picker)
	_export = ExportDialog.new()
	add_child(_export)
	_arrangement.export_requested.connect(_export.open)

	_arrangement.add_instrument_requested.connect(func():
		_pick_mode = "track"
		_picker.open("Choose an instrument", false))
	_arrangement.add_voice_requested.connect(func(): _open_editor(TrackManager.add_track("", "audio")))
	_importer = AudioImporter.new()
	add_child(_importer)
	_importer.imported.connect(func(t: Track):
		if _audio_editor.visible and _audio_editor.track == t:
			_audio_editor.open(t))
	_importer.failed.connect(func(msg: String):
		var d := AcceptDialog.new()
		d.title = "Import audio"
		d.dialog_text = msg
		d.confirmed.connect(d.queue_free)
		d.canceled.connect(d.queue_free)
		add_child(d)
		d.popup_centered())
	_arrangement.import_audio_requested.connect(func(): _importer.open(null))
	_audio_editor.import_requested.connect(func(t: Track): _importer.open(t))
	_editor.add_layer_requested.connect(func():
		_pick_mode = "layer"
		_picker.open("Add a layer to the drum rack", false, true))
	_editor.change_layer_requested.connect(func(key: String):
		_swap_key = key
		_pick_mode = "swap"
		_picker.open("Change this layer's sound", false, true))
	_arrangement.open_track.connect(_open_editor)
	_arrangement.loop_builder_requested.connect(func(): _open_editor(TrackManager.add_track("", "drums")))
	_editor.back_requested.connect(_show_arrangement)
	_editor.change_instrument_requested.connect(func():
		if _editor.track != null and _editor.track.kind == "melodic":
			_change_track = _editor.track
			_pick_mode = "change"
			_picker.open("Change instrument", false))
	_picker.chosen.connect(_on_picked)
	_home.refresh()

	var win := get_window()
	win.content_scale_size = Vector2i.ZERO  # scale by DPI factor, not a fixed design size
	if not OS.has_feature("mobile"):
		win.min_size = Vector2i(480, 300)  # desktop: do not let the window shrink below a usable size
	win.size_changed.connect(_on_window_resized)
	_on_window_resized()


func _add_background() -> void:
	var grad := Gradient.new()
	grad.set_color(0, StudioTheme.BG_TOP)
	grad.set_color(1, StudioTheme.BG_BOTTOM)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	var bg := TextureRect.new()
	bg.texture = tex
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


## UI scale for any screen: a phone, a tablet, a desktop window, portrait or landscape.
## The UI is laid out in "logical" pixels (window pixels / scale). Two limits decide the scale:
##  - comfort: small screens show ~400 logical px on the short side; bigger screens get a little
##    more room (up to ~560), so a big monitor is not just a giant phone;
##  - fit: the logical size must never drop below what the screens need (landscape 640 x 340,
##    portrait 360 x 640), so nothing is cut off on a small or odd-shaped window.
func _ui_scale(px: Vector2) -> float:
	var short := minf(px.x, px.y)
	var target_short := lerpf(400.0, 560.0, clampf((short - 700.0) / 1400.0, 0.0, 1.0))
	var comfort := short / target_short
	var need := Vector2(640.0, 340.0) if px.x >= px.y else Vector2(360.0, 640.0)
	var fit := minf(px.x / need.x, px.y / need.y)
	return clampf(minf(comfort, fit), 0.5, 4.0)


func _on_window_resized() -> void:
	var win := get_window()
	win.content_scale_factor = _ui_scale(Vector2(win.size))
	var m := Vector4(12, 10, 12, 10)  # left, top, right, bottom (logical px)
	if OS.has_feature("mobile"):  # keep clear of notches / gesture bars
		var safe := DisplayServer.get_display_safe_area()
		var scr := DisplayServer.screen_get_size()
		m += Vector4(safe.position.x, safe.position.y, scr.x - safe.end.x, scr.y - safe.end.y) / win.content_scale_factor
	_body.add_theme_constant_override("margin_left", int(m.x))
	_body.add_theme_constant_override("margin_top", int(m.y))
	_body.add_theme_constant_override("margin_right", int(m.z))
	_body.add_theme_constant_override("margin_bottom", int(m.w))


func _open_editor(t: Track) -> void:
	Transport.stop()
	_home.visible = false
	_arrangement.visible = false
	if t.kind == "audio":
		_editor.visible = false
		_audio_editor.visible = true
		_audio_editor.open(t)
	else:
		_audio_editor.visible = false
		_editor.visible = true
		_editor.open(t)


func _show_home() -> void:
	Transport.stop()
	ProjectManager.flush()
	if TrackManager.tracks.size() > 0:
		ProjectManager.save()
	_editor.visible = false
	_audio_editor.visible = false
	_arrangement.visible = false
	_home.refresh()
	_home.visible = true


func _show_arrangement() -> void:
	_home.visible = false
	_editor.visible = false
	_audio_editor.visible = false
	_arrangement.visible = true


func _on_picked(kind: String, instrument_id: String) -> void:
	if _pick_mode == "layer":
		TrackManager.add_drum_lane(_editor.track, instrument_id)
		return
	if _pick_mode == "swap":
		TrackManager.change_drum_lane(_editor.track, _swap_key, instrument_id)
		return
	if _pick_mode == "change":
		TrackManager.set_instrument(_change_track, instrument_id)
		if _editor.visible and _editor.track == _change_track:
			_editor.refresh_instrument()
		return
	var t := TrackManager.add_track(instrument_id, kind)
	_open_editor(t)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:  # Android back button
		if _picker.visible:
			_picker.close()
		elif _editor.visible:
			_editor._go_back()
		elif _audio_editor.visible:
			_audio_editor._go_back()
