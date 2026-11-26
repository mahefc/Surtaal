class_name IconGlyph
extends Control
## Draws a vector icon over its parent Button (child nodes paint above the button face).
## Reacts to the parent's hover / pressed / disabled state.

var icon_name := "":
	set(v):
		icon_name = v
		queue_redraw()
## Override the colour (e.g. red for Record). Transparent = automatic.
var glyph_color := Color.TRANSPARENT:
	set(v):
		glyph_color = v
		queue_redraw()
var glyph_scale := 0.22   # icon half-size as a fraction of the button's short side
var icon_left := false   # put the icon at the left edge (for buttons that also show text)


func _init(icon: String = "") -> void:
	icon_name = icon
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var b := get_parent() as BaseButton
	if b:
		b.toggled.connect(func(_on): queue_redraw())
		b.mouse_entered.connect(queue_redraw)
		b.mouse_exited.connect(queue_redraw)
		b.button_down.connect(queue_redraw)
		b.button_up.connect(queue_redraw)
		b.resized.connect(queue_redraw)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED:
		queue_redraw()


func _draw() -> void:
	if icon_name == "":
		return
	var b := get_parent() as BaseButton
	var col := glyph_color
	if col.a == 0.0:
		var lit := b != null and (b.button_pressed or b.is_hovered())
		col = Color.WHITE if lit else StudioTheme.TEXT
	if b != null and b.disabled:
		col = Color(StudioTheme.DIM, 0.5)
	var r := minf(size.x, size.y) * glyph_scale
	var center := size * 0.5
	if icon_left:
		center = Vector2(maxf(r + 12.0, 22.0), size.y * 0.5)
	Icons.draw(self, icon_name, center, r, col)
