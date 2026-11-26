class_name AudioTrackEditor
extends VBoxContainer
## Editor for a VOICE track: record your voice as audio (not converted to notes).
## Record -> 4-beat count-in -> speak/sing -> Stop -> studio clean-up (VoiceEnhancer:
## rumble filter, noise reduction, gentle compression, level matching) -> saved as a
## 16-bit WAV at the microphone's own sample rate (usually 48 kHz) -> shown as a waveform.
## Re-recording replaces the take. Trim the clip's end by dragging its handle on the timeline.

signal back_requested
signal import_requested(track: Track)  # replace this clip with a wav / mp3 / ogg file

enum Rec { IDLE, COUNT_IN, RECORDING, PROCESSING }

var track: Track

var _rec := Rec.IDLE
var _discard := false
var _skip_samples := 0
var _name_label: Label
var _wave: PeakStrip
var _rec_btn: IconButton
var _play_btn: IconButton
var _import_btn: IconButton
var _delete_dialog: ConfirmationDialog
var _info: Label


func _init() -> void:
	add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	add_child(head)
	var back := IconButton.create("back", "Back to the song", Vector2(48, 42))
	back.pressed.connect(_go_back)
	head.add_child(back)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", Color("66c2ff"))
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_name_label)
	var del := IconButton.create("trash", "Delete this track", Vector2(48, 42))
	del.pressed.connect(func(): _delete_dialog.popup_centered())
	head.add_child(del)

	_wave = PeakStrip.new()
	_wave.color = Color("66c2ff")
	_wave.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wave.custom_minimum_size = Vector2(0, 110)
	add_child(_wave)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_rec_btn = IconButton.create("record", "Record your voice", Vector2(170, 48))
	_rec_btn.text = "   Record voice"
	_rec_btn.glyph.icon_left = true
	_rec_btn.glyph.glyph_color = Color.WHITE
	StudioTheme.tint_button(_rec_btn, Color("e5484d"))
	_rec_btn.pressed.connect(_on_record_pressed)
	row.add_child(_rec_btn)
	_play_btn = IconButton.create("play", "Play the recording", Vector2(52, 48))
	_play_btn.pressed.connect(_on_play)
	row.add_child(_play_btn)
	_import_btn = IconButton.create("export", "Import a wav, mp3 or ogg file instead", Vector2(52, 48))
	_import_btn.pressed.connect(func():
		if track != null and _rec == Rec.IDLE:
			import_requested.emit(track))
	row.add_child(_import_btn)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 12)
	_info.add_theme_color_override("font_color", StudioTheme.DIM)
	_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_info)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.dialog_text = "Delete this voice track and its recording?"
	_delete_dialog.confirmed.connect(func():
		_stop_everything()
		TrackManager.remove_track(track)
		back_requested.emit())
	add_child(_delete_dialog)


func _ready() -> void:
	RecordingManager.finished.connect(_on_recorded)
	RecordingManager.peaks_updated.connect(_on_peaks)
	TrackManager.only_changed.connect(_refresh_play)
	Transport.started.connect(_refresh_play)
	Transport.stopped.connect(_refresh_play)


func open(t: Track) -> void:
	track = t
	_name_label.text = t.name
	_set_state(Rec.IDLE)
	_show_clip()


func _show_clip() -> void:
	if track.audio_path != "":
		TrackManager.ensure_audio_peaks(track)
		_wave.set_data(track.audio_peaks, track.audio_peaks.size())
		_wave.set_message("")
		_info.text = "%.1f s. Record or import to replace it. Drag its right edge on the timeline: left to trim, right to loop it." % track.audio_len_sec()
	else:
		_wave.clear()
		_wave.set_message("Tap Record voice, then speak or sing")
		_info.text = "Use headphones if you can: the recording keeps only your voice."
	_play_btn.disabled = track.audio_path == ""


# ------------------------------------------------------------ recording
func _set_state(s: Rec) -> void:
	_rec = s
	match s:
		Rec.IDLE:
			_rec_btn.text = "   Record voice"
			_rec_btn.icon_name = "record"
			_rec_btn.disabled = false
		Rec.COUNT_IN:
			_rec_btn.text = "   Cancel"
			_rec_btn.icon_name = "close"
		Rec.RECORDING:
			_rec_btn.text = "   Stop"
			_rec_btn.icon_name = "stop"
		Rec.PROCESSING:
			_rec_btn.text = "   Cleaning up..."
			_rec_btn.icon_name = "wave"
			_rec_btn.disabled = true
	_play_btn.disabled = s != Rec.IDLE or track == null or track.audio_path == ""


func _on_record_pressed() -> void:
	match _rec:
		Rec.IDLE:
			_start()
		Rec.COUNT_IN:
			_discard = true
			RecordingManager.stop()
			_set_state(Rec.IDLE)
			_wave.set_message("Cancelled.")
		Rec.RECORDING:
			RecordingManager.stop()


func _start() -> void:
	Transport.stop()
	_discard = false
	var err := RecordingManager.start()
	if err != "":
		_wave.set_message(err)
		return
	_wave.clear()
	_set_state(Rec.COUNT_IN)
	var beat := 60.0 / Transport.bpm
	var click := InstrumentManager.get_by_id("hat")
	for i in 4:
		if _rec != Rec.COUNT_IN:
			return
		_wave.set_message("Get ready...  %d" % (4 - i))
		AudioEngine.note_on(click, 60, 1.0 if i == 0 else 0.6)
		await get_tree().create_timer(beat).timeout
	if _rec != Rec.COUNT_IN:
		return
	_skip_samples = RecordingManager.samples.size()  # drop the clicks the microphone picked up
	_set_state(Rec.RECORDING)
	_wave.set_message("Recording...  tap Stop when you are done")


func _on_peaks(peaks: PackedFloat32Array) -> void:
	if _rec != Rec.RECORDING:
		return
	var skip := int(float(_skip_samples) / maxf(RecordingManager.rate, 1) / RecordingManager.PEAK_WINDOW_SEC)
	var shown := peaks.slice(skip)
	_wave.set_data(shown, maxi(int(shown.size() * 1.15), int(10.0 / RecordingManager.PEAK_WINDOW_SEC)))


func _on_recorded(samples: PackedFloat32Array, rate: int) -> void:
	if _rec != Rec.RECORDING or track == null:
		_discard = false
		return
	var cut := samples.slice(_skip_samples)
	if cut.size() < int(rate * 0.3):
		_set_state(Rec.IDLE)
		_wave.set_message("That was too short - try again.")
		return
	_set_state(Rec.PROCESSING)
	_wave.set_message("Cleaning up your voice...")
	WorkerThreadPool.add_task(func():
		var clean := VoiceEnhancer.process(cut, rate)
		_finish.call_deferred(clean, rate), false, "voice clean-up")


func _finish(clean: PackedFloat32Array, rate: int) -> void:
	if track == null:
		return
	var old := track.audio_path
	var path := "user://assets/%s_voice%d_%d.wav" % [ProjectManager.slug(ProjectManager.project_name), track.id, Time.get_ticks_msec()]
	if not RecordingManager.save_wav(clean, rate, path):
		_set_state(Rec.IDLE)
		_wave.set_message("Could not save the recording.")
		return
	if old != "":
		TrackManager.forget_audio(old)
	track.audio_path = path
	track.audio_dur = float(clean.size()) / rate
	track.audio_trim = 0.0
	track.audio_span = 0
	# the waveform: one peak per 20 ms
	var win := maxi(int(rate * 0.02), 1)
	var peaks := PackedFloat32Array()
	var i := 0
	while i < clean.size():
		var pk := 0.0
		for j in range(i, mini(i + win, clean.size()), maxi(win / 12, 1)):
			pk = maxf(pk, absf(clean[j]))
		peaks.append(pk)
		i += win
	track.audio_peaks = peaks
	TrackManager.notify_changed(track)
	_set_state(Rec.IDLE)
	_show_clip()


# ------------------------------------------------------------- playback
func _on_play() -> void:
	if track == null or track.audio_path == "":
		return
	if Transport.playing:
		Transport.stop()
		return
	TrackManager.set_start_step(track.audio_start)  # preview from where the clip begins
	TrackManager.play_only(track)


func _refresh_play() -> void:
	if _play_btn == null:
		return
	_play_btn.icon_name = "stop" if (Transport.playing and TrackManager.only == track) else "play"


func _go_back() -> void:
	_stop_everything()
	back_requested.emit()


func _stop_everything() -> void:
	if _rec == Rec.COUNT_IN or _rec == Rec.RECORDING:
		_discard = true
		RecordingManager.stop()
	_set_state(Rec.IDLE)
	Transport.stop()
