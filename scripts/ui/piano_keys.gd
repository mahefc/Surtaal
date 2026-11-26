class_name PianoKeys
extends Control
## Touch/mouse/keyboard piano. Multi-touch capable, supports glissando drags.
## Emits note_pressed / note_released; knows nothing about audio.

signal note_pressed(midi: int, velocity: float)
signal note_released(midi: int)
signal note_moved(from_midi: int, to_midi: int)  # only when glide is on

## When true, dragging across keys glides the held note (meend) instead of re-striking.
var glide := false

const BLACK_PCS := [1, 3, 6, 8, 10]
const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
## Computer-keyboard piano (desktop testing): semitone offset from first C.
const KEY_MAP := {
	KEY_A: 0, KEY_W: 1, KEY_S: 2, KEY_E: 3, KEY_D: 4, KEY_F: 5, KEY_T: 6,
	KEY_G: 7, KEY_Y: 8, KEY_H: 9, KEY_U: 10, KEY_J: 11, KEY_K: 12, KEY_O: 13, KEY_L: 14,
}

var accent: Color = StudioTheme.ACCENT:
	set(v):
		accent = v
		queue_redraw()
var first_midi: int = 60:
	set(v):
		first_midi = clampi(v, 0, 108)
		_relayout()
var white_count: int = 8:
	set(v):
		white_count = maxi(v, 1)
		_relayout()

var _keys: Array[Dictionary] = []  # {midi, rect, black}
var _held := {}  # pointer id -> midi
var _seen_touch := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_relayout)


## MIDI notes currently spanned by the keyboard (independent of layout state).
func visible_notes() -> Array:
	var out := []
	var wi := 0
	var m := first_midi
	while wi < white_count and m <= 127:
		out.append(m)
		if not ((m % 12) in BLACK_PCS):
			wi += 1
		m += 1
	return out


func _relayout() -> void:
	_keys.clear()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var ww := size.x / white_count
	var bw := ww * 0.6
	var bh := size.y * 0.6
	var wi := 0
	var m := first_midi
	while wi < white_count and m <= 127:
		if (m % 12) in BLACK_PCS:
			if wi > 0:
				_keys.append({"midi": m, "rect": Rect2(wi * ww - bw * 0.5, 0, bw, bh), "black": true})
		else:
			_keys.append({"midi": m, "rect": Rect2(wi * ww, 0, ww, size.y), "black": false})
			wi += 1
		m += 1
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for pass_black in [false, true]:
		for k in _keys:
			if k.black != pass_black:
				continue
			var r: Rect2 = k.rect
			var down := _held.values().has(k.midi)
			if k.black:
				draw_rect(r, accent.lightened(0.1) if down else Color("12141a"))
				draw_rect(r, Color("2a2f3b"), false, 1.0)
			else:
				var col := accent if down else Color("e9ecf4")
				draw_rect(Rect2(r.position + Vector2(1, 0), r.size - Vector2(2, 2)), col)
				if k.midi % 12 == 0:
					var label := "C%d" % (k.midi / 12 - 1)
					draw_string(font, r.position + Vector2(5, r.size.y - 8), label,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("5a6174"))


func _key_at(pos: Vector2) -> Dictionary:
	for pass_black in [true, false]:  # black keys sit on top
		for k in _keys:
			if k.black == pass_black and (k.rect as Rect2).has_point(pos):
				return k
	return {}


func _press(id: int, pos: Vector2) -> void:
	var k := _key_at(pos)
	if k.is_empty():
		return
	_held[id] = k.midi
	note_pressed.emit(k.midi, remap(clampf(pos.y / size.y, 0.0, 1.0), 0.0, 1.0, 0.45, 1.0))
	queue_redraw()


func _move(id: int, pos: Vector2) -> void:
	if not _held.has(id):
		return
	var k := _key_at(pos)
	if k.is_empty() or k.midi == _held[id]:
		return
	if glide:  # meend: slide the sounding note instead of re-striking
		note_moved.emit(_held[id], k.midi)
		_held[id] = k.midi
		queue_redraw()
		return
	note_released.emit(_held[id])
	_held[id] = k.midi
	note_pressed.emit(k.midi, 0.7)
	queue_redraw()


func _release(id: int) -> void:
	if _held.has(id):
		note_released.emit(_held[id])
		_held.erase(id)
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		_seen_touch = true
		if e.pressed:
			_press(e.index, e.position)
		else:
			_release(e.index)
		accept_event()
	elif e is InputEventScreenDrag:
		_move(e.index, e.position)
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if _seen_touch and e.device == InputEvent.DEVICE_ID_EMULATION:
			return  # already handled via the real touch event
		if e.pressed:
			_press(-1, e.position)
		else:
			_release(-1)
		accept_event()
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if _seen_touch and e.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_move(-1, e.position)


func _unhandled_key_input(e: InputEvent) -> void:
	var ke := e as InputEventKey
	if ke == null or ke.echo or not KEY_MAP.has(ke.physical_keycode):
		return
	var midi: int = first_midi - (first_midi % 12) + KEY_MAP[ke.physical_keycode]
	# keys that fall past the last key on screen (O, L ...) wrap down an octave so they
	# always land on a visible key and its row in the note editor
	var shown := visible_notes()
	if not shown.is_empty():
		while midi > int(shown[-1]) and midi - 12 >= int(shown[0]):
			midi -= 12
	var id := 1000 + ke.physical_keycode
	if ke.pressed:
		_held[id] = midi
		note_pressed.emit(midi, 0.75)
		queue_redraw()
	else:
		_release(id)
