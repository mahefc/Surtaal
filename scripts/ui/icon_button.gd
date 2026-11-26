class_name IconButton
extends Button
## A Button whose face is a vector icon (see Icons). Optional text sits beside it.

var glyph: IconGlyph

var icon_name: String:
	get:
		return glyph.icon_name
	set(v):
		glyph.icon_name = v

var glyph_color: Color:
	get:
		return glyph.glyph_color
	set(v):
		glyph.glyph_color = v


static func create(icon: String, tip: String = "", min_size: Vector2 = Vector2(32, 32)) -> IconButton:
	var b := IconButton.new()
	b.glyph.icon_name = icon
	b.tooltip_text = tip
	b.custom_minimum_size = min_size
	return b


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	# Soft fill, no border/outline around the icon.
	add_theme_stylebox_override("normal", StudioTheme.box(StudioTheme.PANEL_HI, 8, 0, Color.TRANSPARENT, 4))
	add_theme_stylebox_override("hover", StudioTheme.box(Color("323a4b"), 8, 0, Color.TRANSPARENT, 4))
	add_theme_stylebox_override("pressed", StudioTheme.box(StudioTheme.ACCENT, 8, 0, Color.TRANSPARENT, 4))
	add_theme_stylebox_override("disabled", StudioTheme.box(Color(StudioTheme.PANEL, 0.6), 8, 0, Color.TRANSPARENT, 4))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	glyph = IconGlyph.new()
	add_child(glyph)
