class_name StudioTheme
extends RefCounted
## Surtaal visual identity: deep charcoal, soft gradients, vivid per-family accents.

const BG_TOP := Color("1a1f28")
const BG_BOTTOM := Color("080a0e")
const PANEL := Color("1a1f29")
const PANEL_HI := Color("262d3b")
const PANEL_SOFT := Color("151920")
const TEXT := Color("eef1f8")
const DIM := Color("8b93a7")
const ACCENT := Color("7c5cff")
const GOOD := Color("2ed3b7")
const WARN := Color("ffb347")


static func box(color: Color, radius: int = 14, border: int = 0, border_color: Color = Color.TRANSPARENT, h_margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.content_margin_left = h_margin
	s.content_margin_right = h_margin
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## A floating panel: soft shadow, thin rim and a slightly brighter fill.
static func card(color: Color = PANEL, radius: int = 16) -> StyleBoxFlat:
	var s := box(color, radius, 1, Color(1, 1, 1, 0.06), 10)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 3)
	return s


## Give one button a coloured identity (record = red, add = accent, ...).
static func tint_button(b: Button, color: Color) -> void:
	var n := box(color, 12, 0, Color.TRANSPARENT, 10)
	n.shadow_color = Color(color, 0.35)
	n.shadow_size = 6
	n.shadow_offset = Vector2(0, 2)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", box(color.lightened(0.12), 12, 0, Color.TRANSPARENT, 10))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.18), 12, 0, Color.TRANSPARENT, 10))
	b.add_theme_stylebox_override("disabled", box(Color(color, 0.35), 12, 0, Color.TRANSPARENT, 10))
	b.add_theme_color_override("font_color", Color.WHITE)


static func _circle(diameter: int, color: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := diameter * 0.5
	for y in diameter:
		for x in diameter:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - dist, 0.0, 1.0)  # 1px anti-aliased edge
			img.set_pixel(x, y, Color(color, a))
	return ImageTexture.create_from_image(img)


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14

	var normal := box(PANEL_HI, 12, 1, Color(1, 1, 1, 0.04), 8)
	normal.shadow_color = Color(0, 0, 0, 0.28)
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0, 1)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", box(Color("323a4b"), 12, 1, Color(1, 1, 1, 0.08), 8))
	t.set_stylebox("pressed", "Button", box(ACCENT, 12, 0, Color.TRANSPARENT, 8))
	t.set_stylebox("disabled", "Button", box(Color(PANEL, 0.6), 12, 0, Color.TRANSPARENT, 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(DIM, 0.55))

	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "OptionButton", t.get_stylebox(state, "Button"))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", Color.WHITE)
	t.set_color("font_pressed_color", "OptionButton", Color.WHITE)
	t.set_stylebox("panel", "PopupPanel", card(Color("1c212b"), 16))
	t.set_stylebox("panel", "PopupMenu", card(PANEL, 12))
	t.set_stylebox("hover", "PopupMenu", box(ACCENT, 8))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 14)

	t.set_color("font_color", "Label", TEXT)

	t.set_stylebox("panel", "PanelContainer", card(PANEL, 18))

	var track := box(Color("0c0f14"), 4)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT.lightened(0.2), 4))
	var knob := _circle(26, Color.WHITE)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	t.set_icon("grabber_disabled", "HSlider", knob)
	return t
