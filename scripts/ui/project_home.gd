class_name ProjectHome
extends VBoxContainer
## First screen: start a new project, open a saved one, or delete one.

signal project_opened

var _list: VBoxContainer
var _confirm: ConfirmationDialog
var _pending := ""


func _init() -> void:
	add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "Surtaal"
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)

	var new_btn := Button.new()
	new_btn.text = "  New project"
	new_btn.icon = null
	new_btn.focus_mode = Control.FOCUS_NONE
	new_btn.custom_minimum_size = Vector2(0, 44)
	StudioTheme.tint_button(new_btn, StudioTheme.ACCENT)
	new_btn.pressed.connect(func():
		Transport.stop()
		ProjectManager.new_project()
		project_opened.emit())
	add_child(new_btn)

	var sub := Label.new()
	sub.text = "Your projects"
	sub.add_theme_color_override("font_color", StudioTheme.DIM)
	add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func():
		ProjectManager.delete_project(_pending)
		refresh())
	add_child(_confirm)


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var names := ProjectManager.list_projects()
	if names.is_empty():
		var l := Label.new()
		l.text = "No saved projects yet. Tap New project to start."
		l.add_theme_color_override("font_color", StudioTheme.DIM)
		_list.add_child(l)
	for n in names:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var open := Button.new()
		open.text = n
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.focus_mode = Control.FOCUS_NONE
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.custom_minimum_size = Vector2(0, 38)
		open.tooltip_text = "Open this project"
		var pname: String = n
		open.pressed.connect(func():
			Transport.stop()
			if ProjectManager.open_project(pname):
				project_opened.emit())
		row.add_child(open)
		var del := IconButton.create("trash", "Delete this project", Vector2(38, 38))
		del.pressed.connect(func():
			_pending = pname
			_confirm.dialog_text = "Delete project \"%s\"? This cannot be undone." % pname
			_confirm.popup_centered())
		row.add_child(del)
		_list.add_child(row)
