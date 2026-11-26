class_name AddChoicePopup
extends PopupPanel
## What do you want to add? One + button, three answers.

signal chosen(kind: String)  # "instrument" | "loop" | "voice" | "import"


func _init() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var title := Label.new()
	title.text = "Add to your song"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	row.add_child(_card("keys", "Instrument", "play, hum or draw a tune", "instrument"))
	row.add_child(_card("loop", "Loop", "build a drum loop", "loop"))
	row.add_child(_card("mic", "Voice", "record your voice", "voice"))
	row.add_child(_card("export", "Import", "wav, mp3 or ogg file", "import"))


func _card(icon: String, title: String, sub: String, kind: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(140, 124)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(0, 56)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := IconGlyph.new(icon)
	g.glyph_scale = 0.28
	ic.add_child(g)
	v.add_child(ic)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 17)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var s := Label.new()
	s.text = sub
	s.add_theme_font_size_override("font_size", 11)
	s.add_theme_color_override("font_color", StudioTheme.DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(s)
	b.pressed.connect(func():
		hide()
		chosen.emit(kind))
	return b
