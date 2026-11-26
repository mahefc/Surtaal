class_name ExportDialog
extends PopupPanel
## "Export song": name, format, progress. The song is bounced in real time.

var _name_edit: LineEdit
var _format: OptionButton
var _info: Label
var _bar: ProgressBar
var _status: Label
var _go: IconButton
var _folder: Button
var _last_path := ""


func _init() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	add_child(m)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(380, 0)
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	var title := Label.new()
	title.text = "Export song"
	title.add_theme_font_size_override("font_size", 20)
	v.add_child(title)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "File name"
	v.add_child(_name_edit)

	_format = OptionButton.new()
	_format.focus_mode = Control.FOCUS_NONE
	_format.add_item("MP3  (192 kbps)")
	_format.add_item("WAV  (lossless)")
	_format.custom_minimum_size = Vector2(0, 40)
	v.add_child(_format)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 12)
	_info.add_theme_color_override("font_color", StudioTheme.DIM)
	v.add_child(_info)

	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.visible = false
	v.add_child(_bar)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	_status.custom_minimum_size = Vector2(0, 0)
	v.add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_go = IconButton.create("export", "Start the export", Vector2(0, 46))
	_go.text = "Export"
	_go.glyph.icon_left = true
	_go.glyph.glyph_color = Color.WHITE
	_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	StudioTheme.tint_button(_go, StudioTheme.ACCENT)
	_go.pressed.connect(_run)
	row.add_child(_go)
	_folder = Button.new()
	_folder.text = "Show folder"
	_folder.focus_mode = Control.FOCUS_NONE
	_folder.custom_minimum_size = Vector2(0, 46)
	_folder.visible = false
	_folder.pressed.connect(func(): OS.shell_show_in_file_manager(_last_path if _last_path != "" else ExportManager.output_dir()))
	row.add_child(_folder)
	var close := IconButton.create("close", "Close", Vector2(46, 46))
	close.pressed.connect(hide)
	row.add_child(close)


func _ready() -> void:
	ExportManager.progress.connect(_on_progress)


func open() -> void:
	_name_edit.text = ProjectManager.project_name
	_status.text = ""
	_bar.visible = false
	_folder.visible = false
	_go.disabled = false
	_info.text = "Length %s. The song is recorded in real time, so exporting takes about as long as the song.\n%s" % [
		TrackManager.format_time(TrackManager.song_seconds()), ExportManager.encoder_hint()]
	popup_centered()


func _run() -> void:
	_go.disabled = true
	_bar.visible = true
	_bar.value = 0.0
	_folder.visible = false
	var result := await ExportManager.export_song(_name_edit.text, _format.selected == 0)
	_go.disabled = false
	_status.text = result.message
	_status.add_theme_color_override("font_color", StudioTheme.TEXT if result.ok else Color("ff7a7a"))
	if result.ok:
		_last_path = result.get("path", "")
		_folder.visible = OS.get_name() not in ["Android", "iOS"]


func _on_progress(fraction: float, text: String) -> void:
	_bar.value = fraction
	_status.text = text
	_status.add_theme_color_override("font_color", StudioTheme.DIM)
