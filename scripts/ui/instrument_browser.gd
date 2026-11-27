class_name InstrumentBrowser
extends VBoxContainer
## Organised instrument picker: search, category chips, grouped cards.
## Real recordings (sampler) are listed first within each category.

signal instrument_chosen(id: String)

var _cards := {}  # id -> Button
var _chips := {}  # category -> Button
var _card_group := ButtonGroup.new()
var _chip_group := ButtonGroup.new()
var _sections := {}  # category -> [header Label, HFlowContainer]
var _search: LineEdit
var _cat := "All"
var _sbox: VBoxContainer
## false: the melodic instrument picker (drums hidden). true: the loop builder's drum sounds only.
var layer_mode := false:
	set(v):
		layer_mode = v
		if is_node_ready():
			_refilter()


func _ready() -> void:
	add_theme_constant_override("separation", 8)

	_search = LineEdit.new()
	_search.placeholder_text = "Search by name or family..."
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String): _refilter())
	add_child(_search)

	var chip_scroll := ScrollContainer.new()
	chip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chip_scroll.custom_minimum_size = Vector2(0, 40)
	add_child(chip_scroll)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 6)
	chip_scroll.add_child(chip_row)

	var preferred := ["All", "Orchestra", "Keys", "Drums"]
	var cats := ["All"]
	for c in preferred:
		if c != "All" and InstrumentManager.categories().has(c) and not cats.has(c):
			cats.append(c)
	for c in InstrumentManager.categories():
		if not cats.has(c):
			cats.append(c)
	for c in cats:
		var b := Button.new()
		b.text = c
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_group = _chip_group
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func():
			_cat = c
			_refilter())
		chip_row.add_child(b)
		_chips[c] = b
	_chips["All"].button_pressed = true

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_sbox = VBoxContainer.new()
	_sbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_sbox)

	var by_cat := {}
	for def in InstrumentManager.instruments:
		if not by_cat.has(def.category):
			by_cat[def.category] = []
		by_cat[def.category].append(def)
	for cat in cats:
		if cat == "All" or not by_cat.has(cat):
			continue
		var head := Label.new()
		head.text = cat
		head.add_theme_font_size_override("font_size", 14)
		head.add_theme_color_override("font_color", StudioTheme.DIM)
		_sbox.add_child(head)
		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		_sbox.add_child(flow)
		_sections[cat] = [head, flow]
		var list: Array = by_cat[cat]
		list.sort_custom(func(a: InstrumentDef, b: InstrumentDef) -> bool:
			var ar := 1 if a.synth == "sampler" else 0
			var br := 1 if b.synth == "sampler" else 0
			if ar != br:
				return ar > br
			return a.display_name < b.display_name)
		for def in list:
			var card := _make_card(def)
			flow.add_child(card)
			_cards[def.id] = card

	InstrumentManager.instrument_selected.connect(_on_selected)
	_refilter()


func _make_card(def: InstrumentDef) -> Button:
	var real := def.synth == "sampler"
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.button_group = _card_group
	b.custom_minimum_size = Vector2(158, 62)
	b.tooltip_text = "%s — %s\n%s%s" % [
		def.category, def.family, def.description,
		"\n● Real recording (VSCO 2 CE, CC0)" if real else ""]
	var normal := StudioTheme.box(StudioTheme.PANEL_HI, 10, 0, Color.TRANSPARENT, 4)
	normal.border_width_left = 4
	normal.border_color = def.color
	var pressed := StudioTheme.box(def.color.darkened(0.35), 10, 2, def.color, 4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)

	# picture on the left, name + family on the right
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	b.add_child(m)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 9)
	m.add_child(row)
	var art := InstrumentArt.make(def, 34.0)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_theme_constant_override("separation", 4)
	col.add_child(name_row)
	var title := Label.new()
	title.text = def.display_name
	title.add_theme_font_size_override("font_size", 11)
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(title)
	if real:
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_font_size_override("font_size", 9)
		dot.add_theme_color_override("font_color", Color("2ed3b7"))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_row.add_child(dot)
	var sub := Label.new()
	sub.text = def.family if def.family != "" else ("Recording" if real else "Synth")
	sub.add_theme_font_size_override("font_size", 9)
	sub.add_theme_color_override("font_color", StudioTheme.DIM)
	sub.clip_text = true
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)

	b.pressed.connect(func(): instrument_chosen.emit(def.id))
	return b


func _refilter() -> void:
	var q := _search.text.strip_edges().to_lower()
	var shown := {}
	var avail := {}  # categories that have something in the current mode
	for def in InstrumentManager.instruments:
		var in_mode: bool = def.is_loop_only() == layer_mode
		if in_mode:
			avail[def.category] = true
		var hay := (def.display_name + " " + def.family + " " + def.category + " " + def.description).to_lower()
		var ok: bool = in_mode and (_cat == "All" or def.category == _cat) and (q == "" or hay.contains(q))
		if _cards.has(def.id):
			_cards[def.id].visible = ok
		if ok:
			shown[def.category] = true
	for c in _chips:
		_chips[c].visible = c == "All" or avail.has(c)
	if _cat != "All" and not avail.has(_cat):
		_cat = "All"
		_chips["All"].button_pressed = true
		_refilter()
		return
	for c in _sections:
		_sections[c][0].visible = shown.has(c)
		_sections[c][1].visible = shown.has(c)


func _on_selected(def: InstrumentDef) -> void:
	if _cards.has(def.id):
		_cards[def.id].set_pressed_no_signal(true)
