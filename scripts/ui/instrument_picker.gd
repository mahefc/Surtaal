class_name InstrumentPicker
extends Control
## Full-screen overlay: choose an instrument (or the drum machine) for a track.

signal chosen(kind: String, instrument_id: String)  # kind: "melodic" | "drums"

var _title: Label
var _drum_btn: Button
var _browser: InstrumentBrowser


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var card := PanelContainer.new()
	margin.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var cancel := IconButton.create("close", "Close", Vector2(44, 40))
	cancel.pressed.connect(close)
	head.add_child(cancel)

	_drum_btn = Button.new()
	_drum_btn.text = "Loop builder  -  combine many instruments into one drum loop"
	_drum_btn.focus_mode = Control.FOCUS_NONE
	_drum_btn.custom_minimum_size = Vector2(0, 42)
	StudioTheme.tint_button(_drum_btn, Color("ff6b6b").darkened(0.35))
	_drum_btn.pressed.connect(func():
		close()
		chosen.emit("drums", ""))
	v.add_child(_drum_btn)

	_browser = InstrumentBrowser.new()
	var browser := _browser
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.instrument_chosen.connect(func(id: String):
		close()
		chosen.emit("melodic", id))
	v.add_child(browser)


## `drum_sounds`: list only the loop-builder sounds (drums, hits) instead of the melodic instruments.
func open(title: String, allow_drums: bool, drum_sounds: bool = false) -> void:
	_title.text = title
	_drum_btn.visible = allow_drums
	_browser.layer_mode = drum_sounds
	visible = true


func close() -> void:
	visible = false
