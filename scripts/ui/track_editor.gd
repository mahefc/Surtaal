class_name TrackEditor
extends VBoxContainer
## Edit one track. Melodic tracks: note view, record, piano keys.
## Tap Record -> choose how: VOICE (hum/sing/whistle -> pitch detection -> notes)
## or PIANO (play the keys -> notes, overdubs). Either way the
## notes are performed by the track's instrument. Drum tracks: a 16-step grid.
##
## Layout: landscape (default) = note view + keys on the left, controls in a side
## column; portrait = a single stacked column. Components are built once and
## re-parented on rotation, so nothing is lost.

signal back_requested
signal change_instrument_requested
signal add_layer_requested  # drum rack: pick an instrument to add as a layer
signal change_layer_requested(lane_key: String)  # drum rack: pick another sound for this layer

enum Rec { IDLE, COUNT_IN, RECORDING, PROCESSING }

const SIDE_W := 210.0

var track: Track
var def: InstrumentDef

var _rec := Rec.IDLE
var _use_keys := false          # record source chosen in the popup
var _rec_base_step := 0
var _skip_samples := 0
var _rec_started_ms := 0
var _discard := false
var _held_ids := {}
var _key_down := {}             # midi -> {t, vel}  (keys recording)
var _key_notes: Array[Dictionary] = []
var _audition_token := 0
var _land := true
var _view_zoom := 1  # 0 zoomed in (1 bar, long keys) .. 2 zoomed out (4 bars, more keys)

var _header: HBoxContainer
var _note_step_btn: IconButton  # steps inside one bar (16 / 32 / 64); the bars on screen stay put
var _roll: PianoRoll
var _grid: DrumGrid
var _tools: HFlowContainer
var _bar_label: Label
var _melodic_only: Array[Control] = []
var _drum_only: Array[Control] = []
var _follow_btn: IconButton  # octave buttons also transpose the notes
var _keys_row: HBoxContainer   # [piano keys]
var _roll_row: HBoxContainer   # [octave scroll buttons][note editor]
var _len_btn: IconButton
var _loop_btn: IconButton
var _peak: PeakStrip
var _rec_btn: IconButton
var _beat_btn: IconButton   # drum loops: beatbox into the mic
var _beatbox := false       # the take being recorded is a beatbox for the drum loop
var _vel_btn: IconButton    # toggle velocity editing (notes lane / drum hits)
var _pan_btn: IconButton    # toggle pan draw lane (notes / drums)
var _move_btn: IconButton   # select notes and move them
var _copy_btn: IconButton   # select notes and copy / paste them
var _auto_loop := false     # the loop preview was started by drawing (velocity / pan), not by the play button
var _hear_btn: IconButton
var _hear_all_btn: IconButton
var _undo_btn: IconButton
var _redo_btn: IconButton
var _keys: PianoKeys
var _delete_dialog: ConfirmationDialog
var _choice: PopupPanel
var _title_lbl: Label           # drum tracks only
var _swap_btn: IconButton       # change instrument (tinted with the instrument's colour)

# audition / recording playhead
var _aud_active := false
var _aud_token := 0
var _aud_t0 := 0.0
var _aud_from := 0
var _aud_end := 0.0
var _aud_whole := false

# layout containers (rebuilt on rotation)
var _body: HBoxContainer
var _left: VBoxContainer
var _side: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_build_header()
	_build_tools()
	_roll = PianoRoll.new()
	_roll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roll.resized.connect(func(): _sync_roll_to_keys.call_deferred())
	_roll.selection_made.connect(_on_notes_selected)
	_roll.paste_requested.connect(_on_paste_clicked)
	_roll.selection_moved.connect(_recopy_if_waiting)
	_grid = DrumGrid.new()
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.change_sound_requested.connect(func(key: String): change_layer_requested.emit(key))
	_build_record_area()
	_keys = PianoKeys.new()
	_keys.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keys.note_pressed.connect(_on_key_pressed)
	_keys.note_released.connect(_on_key_released)
	_keys.note_moved.connect(_on_key_moved)
	_build_keys_row()  # also builds _roll_row = [octave rail][_roll][zoom rail]
	_melodic_only.append(_roll_row)
	_melodic_only.append(_keys)
	_drum_only.append(_grid)

	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 8)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 8)
	_side.custom_minimum_size = Vector2(SIDE_W, 0)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.dialog_text = "Delete this track and its notes?"
	_delete_dialog.confirmed.connect(_delete_track)
	add_child(_delete_dialog)
	_build_choice_popup()


func _ready() -> void:
	TrackManager.only_changed.connect(_refresh_loop_button)
	TrackManager.tracks_changed.connect(_on_tracks_changed)
	Transport.started.connect(_refresh_loop_button)
	Transport.stopped.connect(_refresh_loop_button)
	Transport.stopped.connect(func(): _auto_loop = false)  # stopped by hand: leave later playback alone
	RecordingManager.finished.connect(_on_recorded)
	RecordingManager.transcribed.connect(_on_transcribed)
	RecordingManager.level_changed.connect(func(p: float): _peak.level = p)
	RecordingManager.peaks_updated.connect(_on_peaks)
	TuningManager.changed.connect(func(): _roll.queue_redraw())
	get_viewport().size_changed.connect(_apply_orientation)
	_apply_orientation()


# ---------------------------------------------------------- building
func _icon(icon: String, tip: String, size: Vector2 = Vector2(24, 24)) -> IconButton:
	return IconButton.create(icon, tip, size)


## Octave scroll buttons sit right beside the note editor. The note editor runs low (top) to
## high (bottom), like the keyboard runs low (left) to high (right), so the arrows scroll that way.
func _build_keys_row() -> void:
	_keys_row = HBoxContainer.new()
	_keys_row.add_theme_constant_override("separation", 4)
	_keys_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keys_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_melodic_only.append(_keys_row)

	# [octave rail] [note editor] [zoom rail]: the editor's own controls hug the editor.
	_roll_row = HBoxContainer.new()
	_roll_row.add_theme_constant_override("separation", 5)
	_roll_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roll_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var up := _icon("up", "Scroll up: lower octave (notes and keyboard)", Vector2(22, 22))
	up.pressed.connect(func(): _shift_octave(-12))
	_follow_btn = _icon("transpose", "When on, the notes move along with the octave", Vector2(22, 22))
	_follow_btn.toggle_mode = true
	var down := _icon("down", "Scroll down: higher octave (notes and keyboard)", Vector2(22, 22))
	down.pressed.connect(func(): _shift_octave(12))
	_roll_row.add_child(_rail([up, _follow_btn, down]))
	_roll_row.add_child(_roll)
	var zoom_in := _icon("zoomin", "Zoom in: bigger notes, longer keys, fewer bars", Vector2(22, 22))
	zoom_in.pressed.connect(func(): _zoom_roll(1))
	var zoom_out := _icon("zoomout", "Zoom out: smaller notes, a longer keyboard, more bars", Vector2(22, 22))
	zoom_out.pressed.connect(func(): _zoom_roll(-1))
	_roll_row.add_child(_rail([zoom_in, zoom_out]))


## A slim rounded strip of icon buttons, centred beside the note editor.
func _rail(buttons: Array) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StudioTheme.card(Color(StudioTheme.PANEL, 0.92), 14)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	for b in buttons:
		v.add_child(b)
	return p




func _build_header() -> void:
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 4)
	add_child(_header)
	var back := _icon("back", "Back to the song", Vector2(26, 26))
	back.pressed.connect(_go_back)
	_header.add_child(back)
	# The track's name lives in the song view; here the instrument is shown by its colour.
	_title_lbl = Label.new()  # never shown: kept only so tools/tests can read it
	_title_lbl.visible = false
	_header.add_child(_title_lbl)
	_swap_btn = _icon("swap", "Change the instrument", Vector2(26, 26))
	_swap_btn.pressed.connect(func(): change_instrument_requested.emit())
	_header.add_child(_swap_btn)
	_melodic_only.append(_swap_btn)


func _build_tools() -> void:
	_tools = HFlowContainer.new()
	_tools.add_theme_constant_override("h_separation", 3)
	_tools.add_theme_constant_override("v_separation", 3)

	_undo_btn = _icon("undo", "Undo")
	_undo_btn.pressed.connect(ProjectManager.undo)
	_redo_btn = _icon("redo", "Redo")
	_redo_btn.pressed.connect(ProjectManager.redo)
	ProjectManager.state_changed.connect(_refresh_undo)
	var prev := _icon("prev", "Earlier bars")
	prev.pressed.connect(func(): _set_bar(_roll.bar - 1))
	_bar_label = Label.new()
	_bar_label.custom_minimum_size = Vector2(66, 0)
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_label.add_theme_font_size_override("font_size", 12)
	var nxt := _icon("next", "Later bars")
	nxt.pressed.connect(func(): _set_bar(_roll.bar + 1))
	_note_step_btn = _icon("steps", "Steps in each bar: 16, 32 or 64. The bars on screen stay the same", Vector2(34, 22))
	_note_step_btn.icon_name = ""  # number only — clearer than icon + text
	_note_step_btn.add_theme_font_size_override("font_size", 12)
	_note_step_btn.text = "16"
	_note_step_btn.pressed.connect(_cycle_note_steps)
	var clear := _icon("clear", "Clear the notes in the bars on screen")
	clear.pressed.connect(func():
		track.clear_range(_roll.base_step(), _roll.base_step() + _roll.steps)
		TrackManager.notify_changed(track))
	_move_btn = _icon("moveall", "Select and move: drag a box around notes, then drag them (or use the arrow keys)", Vector2(22, 22))
	_move_btn.toggle_mode = true
	_move_btn.toggled.connect(func(on: bool): _set_select_kind("move" if on else ""))
	_copy_btn = _icon("copy", "Select and copy: drag a box around notes, then click where to paste", Vector2(22, 22))
	_copy_btn.toggle_mode = true
	_copy_btn.toggled.connect(func(on: bool): _set_select_kind("copy" if on else ""))
	for c in [_undo_btn, _redo_btn, prev, _bar_label, nxt, _note_step_btn, _move_btn, _copy_btn, clear]:
		if c is IconButton and c != _note_step_btn:
			c.custom_minimum_size = Vector2(22, 22)
		_tools.add_child(c)
		if c != _undo_btn and c != _redo_btn:  # undo / redo work for loops too
			_melodic_only.append(c)

	# Loop builder: icon-only buttons.  [play] [add layer] [ready-made patterns] [length]
	_loop_btn = _icon("play", "Play the loop (repeats while you edit)", Vector2(36, 28))
	_loop_btn.glyph.glyph_color = Color.WHITE
	StudioTheme.tint_button(_loop_btn, Color("2ed3b7").darkened(0.45))
	_loop_btn.pressed.connect(func(): if track: TrackManager.loop_preview(track))
	_tools.add_child(_loop_btn)
	_drum_only.append(_loop_btn)

	var add_layer := _icon("plus", "Add a layer: any instrument joins this drum rack", Vector2(36, 28))
	add_layer.glyph.glyph_color = Color.WHITE
	StudioTheme.tint_button(add_layer, StudioTheme.ACCENT)
	add_layer.pressed.connect(func(): add_layer_requested.emit())
	_tools.add_child(add_layer)
	_drum_only.append(add_layer)

	# one tap: a fresh random beat (no menu)
	var starter := _icon("patterns", "Random beat: fill the grid with a new pattern", Vector2(36, 28))
	starter.pressed.connect(func():
		if track:
			TrackManager.randomize_drums(track))
	_tools.add_child(starter)
	_drum_only.append(starter)

	_len_btn = _icon("steps", "Steps in the bar: tap to switch between 16, 32 and 64 (finer hits; it stays one bar)", Vector2(34, 28))
	_len_btn.icon_name = ""  # number only
	_len_btn.add_theme_font_size_override("font_size", 13)
	_len_btn.text = "16"
	_len_btn.pressed.connect(func():
		if track:
			TrackManager.set_drum_res(track, {1: 2, 2: 4, 4: 1}[track.drum_res])
			_refresh_len_label())
	_tools.add_child(_len_btn)
	_drum_only.append(_len_btn)

	# beatbox: four clicks, then make drum sounds with your mouth for one pass of the loop;
	# kicks, snares and hi-hats are recognised and placed on the grid
	_beat_btn = _icon("mic", "Beatbox: tap, then beatbox when ready (boom = kick, pf = snare, ts = hi-hat)", Vector2(36, 28))
	_beat_btn.glyph.glyph_color = Color.WHITE
	StudioTheme.tint_button(_beat_btn, Color("e5484d"))
	_beat_btn.pressed.connect(_on_beatbox_pressed)
	_tools.add_child(_beat_btn)
	_drum_only.append(_beat_btn)

	# velocity: melodic = lane under the notes; drums = hit strength on the grid
	_vel_btn = _icon("velocity", "Velocity: tap to edit how hard each note or hit is played", Vector2(24, 24))
	_vel_btn.toggle_mode = true
	_vel_btn.toggled.connect(_on_velocity_toggled)
	_tools.add_child(_vel_btn)

	# pan: draw lane under the notes / drum grid (like velocity)
	_pan_btn = _icon("pan", "Pan: tap to draw where the sound sits between the left and right speaker", Vector2(24, 24))
	_pan_btn.toggle_mode = true
	_pan_btn.toggled.connect(_on_pan_toggled)
	_tools.add_child(_pan_btn)


func _build_record_area() -> void:
	_peak = PeakStrip.new()
	_peak.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_peak.custom_minimum_size = Vector2(0, 30)

	# Record and Play sit in the toolbar, right after the note tools.
	_rec_btn = _icon("record", "Record: choose voice or piano", Vector2(34, 24))
	_rec_btn.glyph.glyph_color = Color.WHITE
	StudioTheme.tint_button(_rec_btn, Color("e5484d"))
	_rec_btn.pressed.connect(_on_record_pressed)
	_hear_btn = _icon("play", "Play the bars on screen (loops)", Vector2(24, 24))
	_hear_btn.pressed.connect(func(): _audition(false))
	_hear_all_btn = _icon("playall", "Play the whole tune (loops)", Vector2(24, 24))
	_hear_all_btn.pressed.connect(func(): _audition(true))
	_tools.add_child(_rec_btn)
	_tools.add_child(_hear_btn)
	_tools.add_child(_hear_all_btn)
	_melodic_only.append(_rec_btn)
	_melodic_only.append(_hear_btn)
	_melodic_only.append(_hear_all_btn)


## "Record with..." chooser shown when Record is tapped.
func _build_choice_popup() -> void:
	_choice = PopupPanel.new()
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	_choice.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var title := Label.new()
	title.text = "Record with..."
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var voice := _choice_card("mic", "Voice", "hum, sing or whistle", false)
	var piano := _choice_card("keys", "Piano", "play the keys", true)
	row.add_child(voice)
	row.add_child(piano)
	add_child(_choice)


func _choice_card(icon: String, title: String, sub: String, keys: bool) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 128)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(0, 58)
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
		_choice.hide()
		_use_keys = keys
		_set_source(keys)
		_start_recording())
	return b


# --------------------------------------------------------- open / close
func open(t: Track) -> void:
	track = t
	var drums := t.kind == "drums"
	if not drums:
		t.instrument_id = InstrumentManager.resolve_id(t.instrument_id)
	def = InstrumentManager.get_or_default(t.instrument_id if t.instrument_id != "" else "kick")
	_roll.track = t
	_grid.track = t
	_refresh_len_label()
	var color := TrackManager.color_of(t)
	_roll.accent = color
	_keys.accent = color
	_peak.color = color
	_swap_btn.glyph.glyph_color = color
	_roll.def = def
	if not drums and def != null:
		def.active_preset = t.preset
		_keys.first_midi = def.start_midi - (def.start_midi % 12)
		_view_zoom = 1 if get_viewport_rect().size.x > get_viewport_rect().size.y else 0
		_roll.set_zoom([16, 32, 64][_view_zoom])
		_roll.bar = 0
		_focus_octave()
		_set_bar(0)
	_peak.clear()
	_peak.set_message("")
	_vel_btn.set_pressed_no_signal(false)
	_pan_btn.set_pressed_no_signal(false)
	_move_btn.set_pressed_no_signal(false)
	_copy_btn.set_pressed_no_signal(false)
	_roll.show_velocity = false
	_roll.show_pan = false
	_roll.select_kind = ""
	_grid.velocity_mode = false
	_grid.show_pan = false
	_set_rec_state(Rec.IDLE)
	_refresh_name()
	_apply_orientation()
	_refresh_prebake()


func refresh_instrument() -> void:
	def = InstrumentManager.get_by_id(track.instrument_id)
	_roll.def = def
	_roll.accent = TrackManager.color_of(track)
	_keys.accent = _roll.accent
	_peak.color = _roll.accent
	_swap_btn.glyph.glyph_color = _roll.accent
	_focus_octave()
	_refresh_name()
	_refresh_prebake()


## The name is not shown in the editor; keep the tooltips telling which instrument this is.
func _refresh_name() -> void:
	if track == null:
		return
	if track.kind == "drums":
		_title_lbl.text = "Loop builder"
	elif def != null:
		_swap_btn.tooltip_text = "%s  -  tap to change the instrument" % def.display_name


func _set_source(keys: bool) -> void:
	_use_keys = keys


func _go_back() -> void:
	_stop_everything()
	back_requested.emit()


func _stop_everything() -> void:
	_audition_token += 1
	_choice.hide()
	if _rec == Rec.COUNT_IN or _rec == Rec.RECORDING:
		_discard = true
		if not _use_keys:
			RecordingManager.stop()
	_key_down.clear()
	_roll.clear_live()
	_set_rec_state(Rec.IDLE)
	Transport.stop()
	AudioEngine.all_notes_off()


func _delete_track() -> void:
	_stop_everything()
	var gone := track
	track = null  # so the "tracks changed" handler does not react to our own delete
	TrackManager.remove_track(gone)
	back_requested.emit()


## Undo / redo rebuilds every track as a NEW object. Without this the editor kept drawing and
## editing the old, discarded one, so undo and redo looked broken. Follow the track by its id.
func _on_tracks_changed() -> void:
	if track == null or not visible:
		return
	if TrackManager.tracks.has(track):
		_refresh_name()
		return
	var fresh: Track = null
	for t in TrackManager.tracks:
		if t.id == track.id:
			fresh = t
			break
	if fresh == null:  # the undo removed this track (e.g. undoing its creation): nothing left to edit
		_stop_everything()
		back_requested.emit()
		return
	_rebind(fresh)


func _rebind(t: Track) -> void:
	var was_recording := _rec == Rec.RECORDING or _rec == Rec.COUNT_IN
	if was_recording:
		_stop_everything()
	track = t
	def = InstrumentManager.get_by_id(t.instrument_id)
	_roll.track = t
	_roll.def = def
	_roll.cancel_drag()
	_grid.track = t
	_refresh_len_label()
	var color := TrackManager.color_of(t)
	_roll.accent = color
	_keys.accent = color
	_peak.color = color
	_swap_btn.glyph.glyph_color = color
	if t.kind == "melodic" and def != null:
		def.active_preset = t.preset
	_roll.queue_redraw()
	_grid.queue_redraw()
	_refresh_name()
	_refresh_prebake()
	_refresh_undo()


func _set_bar(b: int) -> void:
	_roll.bar = clampi(b, 0, TrackManager.max_steps() / _roll.steps - 1)
	var per := maxi(_roll.steps / Track.STEPS_PER_BAR, 1)  # bars on screen
	var first := _roll.bar * per + 1
	_bar_label.text = "Bar %d" % first if per == 1 else "Bars %d-%d" % [first, first + per - 1]


## One octave up/down: the note grid AND the piano keys move together.
func _shift_octave(delta: int) -> void:
	var first := clampi(_keys.first_midi + delta, 12, 96)
	var moved := first - _keys.first_midi
	if moved == 0:
		return
	if _follow_btn.button_pressed and track != null and track.kind == "melodic":  # take the notes with it
		for n in track.notes:
			n.midi = clampi(n.midi + moved, 0, 127)
		TrackManager.notify_changed(track)
	_keys.first_midi = first
	_sync_roll_to_keys()
	_refresh_prebake()


## The note screen and the keyboard cover exactly the same notes. How many keys (and so how
## tall each note row is) comes from the zoom: zoom in = fewer, longer keys; zoom out = more keys.
func _sync_roll_to_keys() -> void:
	var whites := _zoomed_whites()
	if _keys.white_count != whites:
		_keys.white_count = whites
	_roll.low_midi = _keys.first_midi
	_roll.fixed_rows = _keys.visible_notes().size()


## White keys at the current zoom. Index 0 is zoomed in.
func _zoomed_whites() -> int:
	var counts: Array = [10, 15, 22] if _land else [7, 11, 16]
	return counts[clampi(_view_zoom, 0, 2)]


## Put the keyboard (and so the note screen) on the octave the tune lives in.
func _focus_octave() -> void:
	if track != null and not track.notes.is_empty():
		var mids := []
		for n in track.notes:
			mids.append(n.midi)
		mids.sort()
		_keys.first_midi = clampi((int(mids[mids.size() / 2]) / 12) * 12, 12, 96)
	elif def != null:
		_keys.first_midi = clampi(def.start_midi - (def.start_midi % 12), 12, 96)
	_sync_roll_to_keys()


func _refresh_loop_button() -> void:
	var on := Transport.playing and TrackManager.only == track and track != null
	_loop_btn.icon_name = "stop" if on else "play"


## Zoom in (+1) and out (-1): the notes, the keyboard and the bars, together.
## In = bigger notes, longer keys, fewer bars. Out = the opposite.
func _zoom_roll(direction: int) -> void:
	_view_zoom = clampi(_view_zoom - direction, 0, 2)
	_roll.set_zoom([16, 32, 64][_view_zoom])
	_set_bar(_roll.bar)
	_sync_roll_to_keys()


## 16, then 32, then 64 steps inside each bar. The bars on screen do not change.
func _cycle_note_steps() -> void:
	var n: int = {16: 32, 32: 64, 64: 16}[_roll.steps_per_bar]
	_roll.steps_per_bar = n
	_note_step_btn.text = "%d" % n


func _on_velocity_toggled(on: bool) -> void:
	if track != null and track.kind == "drums":
		_grid.velocity_mode = on
		if on:
			_pan_btn.set_pressed_no_signal(false)
			_grid.show_pan = false
			_loop_on_for_drawing()
		else:
			_loop_off_after_drawing()
	else:
		_roll.show_velocity = on
		if on:
			_pan_btn.set_pressed_no_signal(false)
		_grid.velocity_mode = false
		_grid.show_pan = false


func _on_pan_toggled(on: bool) -> void:
	if track == null:
		return
	if track.kind == "drums":
		_grid.show_pan = on
		if on:
			_vel_btn.set_pressed_no_signal(false)
			_grid.velocity_mode = false
			_loop_on_for_drawing()
		else:
			_loop_off_after_drawing()
	else:
		_roll.show_pan = on
		if on:
			_vel_btn.set_pressed_no_signal(false)
			_roll.show_velocity = false
		_grid.show_pan = false


## Move and copy are exclusive: turning one on turns the other off.
func _set_select_kind(kind: String) -> void:
	if kind == "move":
		_copy_btn.set_pressed_no_signal(false)
	elif kind == "copy":
		_move_btn.set_pressed_no_signal(false)
	elif kind == "":
		_move_btn.set_pressed_no_signal(false)
		_copy_btn.set_pressed_no_signal(false)
	_roll.select_kind = kind


func _shortcuts_open() -> bool:
	return visible and track != null and track.kind == "melodic" and _rec == Rec.IDLE


## Copy mode: the box is drawn, the notes are copied, and the paste pointer shows.
func _on_notes_selected() -> void:
	if _roll.select_kind != "copy":
		return
	var n := TrackManager.copy_notes(_roll.selection)
	_peak.set_message("Copied %d note%s. Click where they should go; click again to paste more." % [n, "" if n == 1 else "s"])


## A click on the grid pastes the copied notes there. The pointer stays, so more clicks paste
## again, until Copy is turned off (or a new box is drawn to copy something else).
## The newest pasted notes stay selected so they can be nudged into place.
func _on_paste_clicked(step: int, midi: int) -> void:
	if track == null or track.kind != "melodic" or TrackManager.note_clip.is_empty():
		_roll.armed = false
		return
	var n := TrackManager.paste_notes(track, step, midi)
	_roll.selection = TrackManager.last_pasted.duplicate()
	_roll.queue_redraw()
	_peak.set_message("Pasted %d note%s. Click to paste again, or turn Copy off." % [n, "" if n == 1 else "s"])


## If the selection moved before it was pasted, what gets pasted is the moved notes.
func _recopy_if_waiting() -> void:
	if _roll.armed and not _roll.selection.is_empty():
		TrackManager.copy_notes(_roll.selection)


## Arrow keys: the selected notes slide the way the key points (up is toward the top of the grid).
func _nudge_selection(dx: int, dy: int) -> void:
	if _roll.selection.is_empty():
		return
	if TrackManager.shift_group(track, _roll.selection, dx, dy) == 0:
		_peak.set_message("Those notes can't move any further that way.")
		return
	_recopy_if_waiting()


func _delete_selection() -> void:
	if _roll.selection.is_empty() or track == null:
		return
	for n in _roll.selection:
		track.remove_note(n)
	_roll.selection = []  # the copy stays, so pasting can go on
	_roll.queue_redraw()
	TrackManager.notify_changed(track)


func _unhandled_input(e: InputEvent) -> void:
	if not _shortcuts_open() or not (e is InputEventKey) or not e.pressed:
		return
	var k := e as InputEventKey
	if k.ctrl_pressed or k.meta_pressed or k.alt_pressed or k.shift_pressed:
		return
	var dx := 0
	var dy := 0
	match k.keycode:
		KEY_LEFT:
			dx = -_roll.snap
		KEY_RIGHT:
			dx = _roll.snap
		KEY_UP:
			dy = -1
		KEY_DOWN:
			dy = 1
		KEY_DELETE, KEY_BACKSPACE:
			if not k.echo:
				_delete_selection()
				get_viewport().set_input_as_handled()
			return
		_:
			return
	if _roll.selection.is_empty():
		return
	_nudge_selection(dx, dy)
	get_viewport().set_input_as_handled()


func _refresh_len_label() -> void:
	if track != null:
		_len_btn.text = "%d" % track.grid_steps()


## Hear the loop while drawing on it (velocity, pan): start the loop preview unless it is playing.
func _loop_on_for_drawing() -> void:
	if track == null or track.kind != "drums" or (Transport.playing and TrackManager.only == track):
		return
	TrackManager.loop_preview(track)
	_auto_loop = true  # started by us, so we stop it when the drawing is finished


func _loop_off_after_drawing() -> void:
	if _auto_loop and track != null and Transport.playing and TrackManager.only == track:
		Transport.stop()
	_auto_loop = false


func _refresh_prebake() -> void:
	if track != null and track.kind == "drums":
		TrackManager.prebake_drums(track)  # the first hit you draw must not wait for its sound
		return
	if def == null or track == null:
		return
	SampleManager.prebake(def, _roll.visible_notes() + _keys.visible_notes(), track.preset)


# --------------------------------------------------------------- layout
func _detach(c: Node) -> void:
	if c.get_parent():
		c.get_parent().remove_child(c)


func _apply_orientation() -> void:
	var rect := get_viewport_rect().size
	_land = rect.x > rect.y
	var drums := track != null and track.kind == "drums"
	for c in _melodic_only:
		c.visible = not drums
	for c in _drum_only:
		c.visible = drums

	for c in [_tools, _roll_row, _grid, _peak, _keys, _keys_row, _body, _left, _side]:
		_detach(c)
	_keys_row.add_child(_keys)
	_tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tools.custom_minimum_size = Vector2(0, 28)
	_roll_row.size_flags_stretch_ratio = 1.0
	if _land:
		# ONE top row: back, instrument and all the tools; then the big note view / drum grid,
		# a slim status strip (only while recording), and the keyboard.
		_header.add_child(_tools)
		add_child(_body)
		_body.add_child(_left)
		_left.add_child(_roll_row)
		_left.add_child(_grid)
		_left.add_child(_peak)
		_left.add_child(_keys_row)
		_roll.custom_minimum_size = Vector2(0, 140)
		_keys_row.custom_minimum_size = Vector2(0, 56)
		_keys_row.size_flags_stretch_ratio = 0.28
		_grid.custom_minimum_size = Vector2(0, 150)
	else:
		add_child(_tools)
		add_child(_roll_row)
		add_child(_grid)
		add_child(_peak)
		add_child(_keys_row)
		_roll.custom_minimum_size = Vector2(0, 180)
		_keys_row.custom_minimum_size = Vector2(0, 80)
		_keys_row.size_flags_stretch_ratio = 0.28
		_grid.custom_minimum_size = Vector2(0, 220)
	_refresh_peak_strip()
	_sync_roll_to_keys()

# ------------------------------------------------------------ live keys
func _elapsed() -> float:
	return (Time.get_ticks_msec() - _rec_started_ms) / 1000.0


func _on_key_pressed(midi: int, velocity: float) -> void:
	if _held_ids.has(midi):
		AudioEngine.note_off(_held_ids[midi])
	_held_ids[midi] = AudioEngine.note_on(def, midi, velocity, track.preset, TrackManager.bus_of(track))
	_roll.set_live(midi, true)  # light up the note in the editor
	# Armed and waiting: the first key starts the take (no fixed count-in delay).
	if _rec == Rec.COUNT_IN and _use_keys:
		_begin_keys_take()
	if _rec == Rec.RECORDING and _use_keys:
		var t := maxf(_elapsed(), 0.0)
		_close_key_note(midi, t)  # same key struck again (e.g. two fingers): end the first one
		_key_down[midi] = {"t": t, "vel": velocity}


func _on_key_released(midi: int) -> void:
	if _held_ids.has(midi):
		AudioEngine.note_off(_held_ids[midi])
		_held_ids.erase(midi)
	_roll.set_live(midi, false)
	if _use_keys and (_rec == Rec.RECORDING or _key_down.has(midi)):
		_close_key_note(midi, maxf(_elapsed(), 0.0))


func _on_key_moved(from_midi: int, to_midi: int) -> void:
	if not _held_ids.has(from_midi):
		return
	var id: int = _held_ids[from_midi]
	_held_ids.erase(from_midi)
	_held_ids[to_midi] = id
	_roll.set_live(from_midi, false)
	_roll.set_live(to_midi, true)
	AudioEngine.glide(id, to_midi, 0.14)
	if _key_down.has(from_midi):  # a glide continues as the new pitch
		var t := maxf(_elapsed(), 0.0)
		var vel: float = _key_down[from_midi].vel if _key_down.has(from_midi) else 0.7
		_close_key_note(from_midi, t)
		_key_down[to_midi] = {"t": t, "vel": vel}


func _close_key_note(midi: int, t_off: float) -> void:
	if not _key_down.has(midi):
		return
	var d: Dictionary = _key_down[midi]
	_key_down.erase(midi)
	_key_notes.append({"t0": d.t, "t1": maxf(t_off, d.t + 0.03), "midi": midi, "vel": d.vel})


# --------------------------------------------------------------- recording
func _set_rec_state(s: Rec) -> void:
	_rec = s
	match s:
		Rec.IDLE:
			_rec_btn.icon_name = "record"
			_rec_btn.tooltip_text = "Record: choose voice or piano"
			_rec_btn.disabled = false
		Rec.COUNT_IN:
			_rec_btn.icon_name = "close"
			_rec_btn.tooltip_text = "Cancel (waiting for you to play or sing)"
		Rec.RECORDING:
			_rec_btn.icon_name = "stop"
			_rec_btn.tooltip_text = "Stop recording"
		Rec.PROCESSING:
			_rec_btn.icon_name = "wave"
			_rec_btn.tooltip_text = "Working..."
			_rec_btn.disabled = true
	if s == Rec.IDLE:
		_beatbox = false
	var beat_icons := {Rec.IDLE: "mic", Rec.COUNT_IN: "close", Rec.RECORDING: "stop", Rec.PROCESSING: "wave"}
	_beat_btn.icon_name = beat_icons[s]
	_beat_btn.tooltip_text = "Beatbox: tap, then beatbox when ready (boom = kick, pf = snare, ts = hi-hat)" if s == Rec.IDLE else "Stop / cancel the beatbox"
	_beat_btn.disabled = s == Rec.PROCESSING
	_hear_btn.disabled = s != Rec.IDLE
	_hear_all_btn.disabled = s != Rec.IDLE
	_peak.level = 0.0
	if s == Rec.IDLE or s == Rec.PROCESSING:
		TrackManager.end_backing()
	_refresh_peak_strip()


## Status strip only while recording — keeps that space for the note grid otherwise.
func _refresh_peak_strip() -> void:
	var need := _rec != Rec.IDLE
	_peak.visible = need
	_peak.custom_minimum_size = Vector2(0, 22 if need else 0)
	_peak.size_flags_vertical = Control.SIZE_FILL if need else 0


func _on_record_pressed() -> void:
	match _rec:
		Rec.IDLE:
			_choice.popup_centered()  # voice or piano?
		Rec.COUNT_IN:
			_discard = true
			if not _use_keys:
				RecordingManager.stop()
			_set_rec_state(Rec.IDLE)
			_peak.set_message("Cancelled.")
		Rec.RECORDING:
			if _use_keys:
				_finish_keys()
			else:
				RecordingManager.stop()


## Drum loop: beatbox. Tap = four clicks, then one pass of the loop is recorded; tap again to cancel/stop.
func _on_beatbox_pressed() -> void:
	match _rec:
		Rec.IDLE:
			_start_beatbox()
		Rec.COUNT_IN:
			_discard = true
			RecordingManager.stop()
			_set_rec_state(Rec.IDLE)
			_peak.set_message("Cancelled.")
		Rec.RECORDING:
			RecordingManager.stop()  # finish early: what was heard so far is used


func _start_beatbox() -> void:
	if track == null or track.kind != "drums":
		return
	Transport.stop()
	_audition_token += 1
	_discard = false
	_use_keys = false
	var err := RecordingManager.start()
	if err != "":
		_peak.set_message(err)
		return
	_beatbox = true
	_peak.clear()
	_set_rec_state(Rec.COUNT_IN)
	if not await _wait_for_voice_start("Beatbox when ready..."):
		return
	_set_rec_state(Rec.RECORDING)
	_peak.set_message("Beatboxing...  (%d steps at %d BPM)" % [track.grid_steps(), int(Transport.bpm)])
	var limit := track.pattern_steps() * Transport.seconds_per_step() + 0.25  # a little tail for a late last hit
	while _rec == Rec.RECORDING and _beatbox:
		await get_tree().process_frame
		if _elapsed() >= limit:
			RecordingManager.stop()
			return


## The beatbox take is in: find the hits, snap them to the grid and put them in the rack.
func _finish_beatbox(cut: PackedFloat32Array, rate: int) -> void:
	_set_rec_state(Rec.PROCESSING)
	_peak.set_message("Finding the beats...")
	await get_tree().process_frame
	var hits := BeatboxAnalyzer.analyze(cut, rate)
	var latency := minf(AudioServer.get_output_latency(), 0.06)
	# the grid may be finer than a 16th note: hits snap to its cells (res cells per 16th = res times the tempo)
	var steps := BeatboxAnalyzer.to_steps(hits, Transport.bpm * track.drum_res, track.grid_steps(), latency)
	var vels := BeatboxAnalyzer.to_velocities(hits, Transport.bpm * track.drum_res, track.grid_steps(), latency)
	var placed := TrackManager.apply_beatbox(track, steps, vels) if not hits.is_empty() else 0
	_set_rec_state(Rec.IDLE)
	if placed == 0:
		_peak.set_message("I couldn't hear any beats. Beatbox louder or closer to the mic.")
	else:
		_peak.set_message("Found %d kicks, %d snares and %d hi-hats." % [steps.kick.size(), steps.snare.size(), steps.hat.size()])


func _start_recording() -> void:
	Transport.stop()
	_audition_token += 1
	_discard = false
	if not _use_keys:
		var err := RecordingManager.start()
		if err != "":
			_peak.set_message(err)
			_refresh_peak_strip()
			return
	_rec_base_step = _roll.base_step()
	_peak.clear()
	_set_rec_state(Rec.COUNT_IN)
	_rec_started_ms = 0
	if _use_keys:
		# A key press whose sound is not rendered yet would block the main thread while it
		# bakes and corrupt the recorded timing, so wait until every visible key is ready.
		_peak.set_message("Getting the sound ready...")
		var keys_needed := _keys.visible_notes()
		SampleManager.prebake(def, keys_needed, track.preset, true)
		while _rec == Rec.COUNT_IN and not _all_cached(keys_needed):
			await get_tree().process_frame
		if _rec != Rec.COUNT_IN:
			return
		_key_down.clear()
		_key_notes.clear()
		_peak.set_message("Play when ready...")
		return  # first key press starts the take via _begin_keys_take()
	if not await _wait_for_voice_start("Sing or hum when ready..."):
		return
	_set_rec_state(Rec.RECORDING)
	_peak.set_message("")
	_watch_length()


## First piano key while armed: start the take clock on that press (no countdown).
func _begin_keys_take() -> void:
	if _rec != Rec.COUNT_IN or not _use_keys:
		return
	_rec_started_ms = Time.get_ticks_msec()
	_set_rec_state(Rec.RECORDING)
	_peak.set_message("")
	_watch_length()


## Wait until the mic hears sound, then mark that as the take start. Returns false if cancelled.
func _wait_for_voice_start(hint: String) -> bool:
	_peak.set_message(hint)
	var loud_frames := 0
	while _rec == Rec.COUNT_IN:
		await get_tree().process_frame
		if _peak.level >= 0.06:
			loud_frames += 1
		else:
			loud_frames = 0
		if loud_frames >= 2:  # a short blip of noise should not start the take
			var pad := int(0.04 * maxf(RecordingManager.rate, 1.0))
			_skip_samples = maxi(0, RecordingManager.samples.size() - pad)
			_rec_started_ms = Time.get_ticks_msec()
			return true
	return false


## Stop automatically at the end of the song.
func _watch_length() -> void:
	var step_sec := 60.0 / Transport.bpm / 4.0
	var room := _room_sec()
	while _rec == Rec.RECORDING:
		await get_tree().process_frame
		if _elapsed() >= room:
			if _use_keys:
				_finish_keys()
			else:
				RecordingManager.stop()
			return


# ---- keys recording
func _finish_keys() -> void:
	if _rec != Rec.RECORDING:
		return
	var t_end := _elapsed()
	for midi in _key_down.keys():
		_close_key_note(midi, t_end)
	_set_rec_state(Rec.IDLE)
	if _key_notes.is_empty():
		_peak.set_message("No notes were played. Tap Record and try again.")
		return
	var step_sec := 60.0 / Transport.bpm / 4.0
	_key_notes.sort_custom(func(a, b): return a.t0 < b.t0)
	# snap to the 1/16 grid; a repeated key cuts the previous one of the same pitch short
	var placed: Array[Dictionary] = []
	var last_of := {}  # midi -> index in placed
	for n in _key_notes:
		var start := clampi(_rec_base_step + int(round(n.t0 / step_sec)), 0, TrackManager.max_steps() - 1)
		var length := maxi(1, int(round((n.t1 - n.t0) / step_sec)))
		if last_of.has(n.midi):
			var prev: Dictionary = placed[last_of[n.midi]]
			if prev.start >= start:
				start = prev.start + 1
			prev.len = clampi(prev.len, 1, start - prev.start)
		if start >= TrackManager.max_steps():
			continue
		last_of[n.midi] = placed.size()
		placed.append({"start": start, "len": mini(length, TrackManager.max_steps() - start), "midi": n.midi, "vel": n.vel})
	# overdub: the new take replaces old notes of the same pitch that it overlaps
	for p in placed:
		for old in track.notes.duplicate():
			if old.midi == p.midi and old.start < p.start + p.len and old.start + old.len > p.start:
				track.remove_note(old)
	for p in placed:
		track.add_note(p.start, p.len, p.midi, clampf(0.45 + 0.55 * float(p.vel), 0.4, 1.0))
	_key_notes.clear()
	_roll.rec_notes = []
	TrackManager.notify_changed(track)
	_focus_octave()
	_peak.set_message("")


# ---- voice recording
func _on_peaks(peaks: PackedFloat32Array) -> void:
	if _rec != Rec.RECORDING or _use_keys:
		return
	var skip := int(float(_skip_samples) / maxf(RecordingManager.rate, 1) / RecordingManager.PEAK_WINDOW_SEC)
	var shown := peaks.slice(skip)
	if _beatbox:  # the strip is exactly one pass of the loop
		_peak.set_data(shown, int((track.pattern_steps() * Transport.seconds_per_step() + 0.25) / RecordingManager.PEAK_WINDOW_SEC))
		return
	# the strip rescales as you go: always at least 15 s wide, never more than ~87% full
	_peak.set_data(shown, maxi(int(shown.size() * 1.15), int(15.0 / RecordingManager.PEAK_WINDOW_SEC)))


func _on_recorded(samples: PackedFloat32Array, rate: int) -> void:
	if _discard or track == null or _use_keys or _rec != Rec.RECORDING:
		_discard = false
		return
	var cut := samples.slice(_skip_samples)
	if _beatbox:
		_finish_beatbox(cut, rate)
		return
	if cut.size() < int(rate * 0.3):
		_set_rec_state(Rec.IDLE)
		_peak.set_message("That was too short - try again.")
		return
	_set_rec_state(Rec.PROCESSING)
	_peak.set_message("Finding the notes...")
	# Keep the original performance as an audio asset on the track.
	var path := "user://assets/%s_track%d.wav" % [ProjectManager.slug(ProjectManager.project_name), track.id]
	if RecordingManager.save_wav(cut, rate, path):
		track.hum_path = path
	RecordingManager.transcribe_async(cut, rate)


func _room_sec() -> float:
	return (TrackManager.max_steps() - _rec_base_step) * Transport.seconds_per_step()


func _on_transcribed(found: Array) -> void:
	if _rec != Rec.PROCESSING or track == null:
		return
	_set_rec_state(Rec.IDLE)
	var bpm := Transport.bpm
	var msg := ""
	# If this is the only musical content, adopt the tempo the singer actually hummed at.
	var others := false
	for t in TrackManager.tracks:
		others = others or (t != track and t.has_content())
	if not others:
		var est := HumTranscriber.estimate_bpm(found, bpm)
		if est != bpm:
			bpm = est
			Transport.bpm = est
			msg = " Tempo set to %d BPM." % int(est)
	# Mild latency only — the old +30 ms pad was shifting the first notes off the take.
	var latency := minf(AudioServer.get_output_latency(), 0.06)
	var in_scale := Callable()  # no snapping: the notes are exactly what was sung
	var notes := HumTranscriber.to_track_notes(found, bpm, _rec_base_step, latency, in_scale)
	if notes.is_empty():
		_peak.set_message("I couldn't hear a clear pitch. Hum louder or closer to the mic.")
		return
	var first: int = notes[0].start
	var last: int = notes[-1].start + notes[-1].len
	track.clear_range(first, last)
	for n in notes:
		track.add_note(n.start, n.len, n.midi, n.vel, n.get("cents", 0.0), n.get("off", 0.0), n.get("dur", 0.0))
	TrackManager.notify_changed(track)
	_focus_octave()
	_peak.set_message("" if msg == "" else msg.strip_edges())
	_refresh_prebake()
	_audition()


## Play this track's notes (from the current bar) with the track's instrument.
func _refresh_undo() -> void:
	_undo_btn.disabled = not ProjectManager.can_undo()
	_redo_btn.disabled = not ProjectManager.can_redo()


func _stop_audition() -> void:
	_audition_token += 1
	_aud_active = false
	_roll.playhead = -1.0
	AudioEngine.all_notes_off()
	_refresh_hear_icons()


func _refresh_hear_icons() -> void:
	_hear_btn.icon_name = "stop" if _aud_active and not _aud_whole else "play"
	_hear_all_btn.icon_name = "stop" if _aud_active and _aud_whole else "playall"


## The moving playhead on the note editor while the tune plays, and while a take is recorded.
func _process(_d: float) -> void:
	var step_sec := 60.0 / Transport.bpm / 4.0
	if _aud_active:
		if _aud_token != _audition_token:  # stopped / replaced elsewhere
			_aud_active = false
			_roll.playhead = -1.0
			_refresh_hear_icons()
			return
		var span := maxf(_aud_end - float(_aud_from), 1.0)
		var raw := float(_aud_from) + (Time.get_ticks_msec() / 1000.0 - _aud_t0) / step_sec
		var pos := float(_aud_from) + fposmod(raw - float(_aud_from), span)
		_roll.playhead = pos
		if _aud_whole and (pos < _roll.base_step() or pos >= _roll.base_step() + _roll.steps):
			_set_bar(int(pos) / _roll.steps)  # keep the playhead on screen
	elif _rec == Rec.RECORDING and _use_keys:
		var now := _elapsed()
		var pos := float(_rec_base_step) + now / step_sec
		_roll.playhead = pos
		if pos >= _roll.base_step() + _roll.steps:
			_set_bar(int(pos) / _roll.steps)
		# show what is being played, before it is saved
		var ghosts := []
		for kn in _key_notes:
			ghosts.append({"start": _rec_base_step + kn.t0 / step_sec, "len": (kn.t1 - kn.t0) / step_sec, "midi": kn.midi})
		for m in _key_down:
			var t0: float = _key_down[m].t
			ghosts.append({"start": _rec_base_step + t0 / step_sec, "len": (now - t0) / step_sec, "midi": m})
		_roll.rec_notes = ghosts
	else:
		if _roll.playhead >= 0.0:
			_roll.playhead = -1.0
		if not _roll.rec_notes.is_empty():
			_roll.rec_notes = []


func _audition(whole: bool = false) -> void:
	if _aud_active:  # a second tap stops it
		_stop_audition()
		return
	if track == null or track.kind == "drums" or track.notes.is_empty():
		return
	_audition_token += 1
	var token := _audition_token
	var from_step := 0 if whole else _roll.base_step()
	var to_step := 1 << 30 if whole else _roll.base_step() + _roll.steps
	var list: Array = []
	var needed := {}
	for n in track.notes:
		if n.start + n.len > from_step and n.start < to_step:
			list.append(n)
			needed[n.midi] = true
	list.sort_custom(func(a, b): return a.start < b.start)
	SampleManager.prebake(def, needed.keys(), track.preset, true)
	while token == _audition_token and not _all_cached(needed.keys()):
		await get_tree().process_frame
	if token != _audition_token:
		return
	var step_sec := 60.0 / Transport.bpm / 4.0
	var last_end := float(from_step)
	for n in list:
		last_end = maxf(last_end, float(n.start + n.len))
	_aud_token = token
	_aud_from = from_step
	_aud_end = float(to_step) if not whole else last_end
	_aud_whole = whole
	_aud_active = true
	_refresh_hear_icons()
	# Loop until the user stops: each pass resets the playhead clock.
	while token == _audition_token:
		var t0 := Time.get_ticks_msec() / 1000.0
		_aud_t0 = t0
		for n in list:
			var due: float = (maxf(float(n.start) + float(n.get("off", 0.0)), float(from_step)) - from_step) * step_sec
			var wait := due - (Time.get_ticks_msec() / 1000.0 - t0)
			if wait > 0.0:
				await get_tree().create_timer(wait).timeout
			if token != _audition_token:
				return
			var id := AudioEngine.note_on(def, n.midi, n.vel, track.preset, TrackManager.bus_of(track), float(n.get("cents", 0.0)))
			get_tree().create_timer(maxf(float(n.get("dur", n.len)) * step_sec * 0.97, 0.08)).timeout.connect(AudioEngine.note_off.bind(id))
		var loop_wait := (_aud_end - float(from_step)) * step_sec - (Time.get_ticks_msec() / 1000.0 - t0)
		if loop_wait > 0.0:
			await get_tree().create_timer(loop_wait).timeout
		if token != _audition_token:
			return


func _all_cached(notes: Array) -> bool:
	for m in notes:
		if not SampleManager.has_sample(def, m, track.preset):
			return false
	return true
