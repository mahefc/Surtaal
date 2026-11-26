class_name AudioImporter
extends Node
## Bring an audio file (wav / mp3 / ogg) onto an audio track.
##   wav       - read straight away.
##   mp3, ogg  - Godot can play these but cannot hand over their samples, so the file is played once into a silent
##               capture bus at normal speed (a 3 minute song takes 3 minutes) and the captured audio is kept as a wav.
## The result is a 16-bit wav inside the project assets, so it behaves like any recorded voice clip
## (move, trim, loop, volume, pan, reverb).

signal imported(track: Track)
signal failed(message: String)

const MAX_SEC := 600.0
const CAP_BUS := "ImportCapture"

var _dialog: FileDialog
var _target: Track
var _name := ""
var _busy := false
var _panel: PopupPanel
var _status: Label
var _bar: ProgressBar
var _player: AudioStreamPlayer
var _cap: AudioEffectCapture
var _bus_idx := -1
var _length := 0.0
var _l := PackedFloat32Array()
var _r := PackedFloat32Array()
var _n := 0


func _ready() -> void:
	set_process(false)
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true  # the system's own picker (also on phones)
	_dialog.title = "Import audio"
	_dialog.filters = PackedStringArray(["*.wav, *.mp3, *.ogg ; Audio files"])
	_dialog.file_selected.connect(_on_file)
	add_child(_dialog)

	_panel = PopupPanel.new()
	_panel.exclusive = true
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(300, 0)
	m.add_child(v)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 18)
	v.add_child(_bar)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(cancel_import)
	v.add_child(cancel)
	add_child(_panel)


## Pick a file. `target` = the audio track to put it on (null = make a new audio track).
func open(target: Track = null) -> void:
	if _busy:
		return
	_target = target
	_dialog.popup_centered_ratio(0.8)


func _on_file(path: String) -> void:
	var ext := path.get_extension().to_lower()
	_name = path.get_file().get_basename()
	Transport.stop()
	match ext:
		"wav":
			var s := AudioStreamWAV.load_from_file(path)
			if s == null:
				failed.emit("That wav file could not be read.")
				return
			_store(s)
		"mp3":
			var s := AudioStreamMP3.load_from_file(path)
			if s == null:
				failed.emit("That mp3 file could not be read.")
				return
			_capture(s)
		"ogg":
			var s := AudioStreamOggVorbis.load_from_file(path)
			if s == null:
				failed.emit("That ogg file could not be read.")
				return
			_capture(s)
		_:
			failed.emit("Pick a wav, mp3 or ogg file.")


# ---------------------------------------------------------- mp3 / ogg: record the playback
func _capture(stream: AudioStream) -> void:
	_length = stream.get_length()
	if _length <= 0.05:
		failed.emit("That file has no audio.")
		return
	_length = minf(_length, MAX_SEC)
	AudioServer.add_bus()
	_bus_idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_bus_idx, CAP_BUS)
	AudioServer.set_bus_send(_bus_idx, "Master")
	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 1.0
	AudioServer.add_bus_effect(_bus_idx, _cap)
	AudioServer.set_bus_volume_db(_bus_idx, -80.0)  # silent: the effect still sees the sound
	_l = PackedFloat32Array()
	_r = PackedFloat32Array()
	_l.resize(int(_length * AudioServer.get_mix_rate()) + 8192)
	_r.resize(_l.size())
	_n = 0
	_player = AudioStreamPlayer.new()
	_player.bus = CAP_BUS
	_player.stream = stream
	add_child(_player)
	_busy = true
	_bar.value = 0.0
	_status.text = "Importing %s (%s)... the file plays once, silently, so it takes as long as the song." % [_name, TrackManager.format_time(_length)]
	_panel.popup_centered()
	_player.play()
	set_process(true)


func _process(_delta: float) -> void:
	if not _busy or _player == null:
		set_process(false)
		return
	_drain()
	var pos := _player.get_playback_position()
	_bar.value = clampf(pos / _length, 0.0, 1.0) * 100.0
	if not _player.playing or pos >= _length:
		_drain()
		_end_capture()
		_store(_captured())


func _drain() -> void:
	var avail := _cap.get_frames_available()
	if avail <= 0:
		return
	var buf := _cap.get_buffer(avail)
	if _n + buf.size() > _l.size():
		_l.resize(_n + buf.size() + 8192)
		_r.resize(_l.size())
	for i in buf.size():
		_l[_n + i] = buf[i].x
		_r[_n + i] = buf[i].y
	_n += buf.size()


func _captured() -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.stereo = true
	s.mix_rate = int(AudioServer.get_mix_rate())
	var bytes := PackedByteArray()
	bytes.resize(_n * 4)
	for i in _n:
		bytes.encode_s16(i * 4, int(clampf(_l[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(_r[i], -1.0, 1.0) * 32767.0))
	s.data = bytes
	_l = PackedFloat32Array()
	_r = PackedFloat32Array()
	return s


func _end_capture() -> void:
	_busy = false
	set_process(false)
	_panel.hide()
	if _player != null:
		_player.stop()
		_player.queue_free()
		_player = null
	if _bus_idx >= 0 and _bus_idx < AudioServer.bus_count and AudioServer.get_bus_name(_bus_idx) == CAP_BUS:
		AudioServer.remove_bus(_bus_idx)
	_bus_idx = -1
	_cap = null


func cancel_import() -> void:
	if _busy:
		_end_capture()


# ------------------------------------------------------------------- put it on a track
func _store(s: AudioStreamWAV) -> void:
	if s == null or s.data.is_empty():
		failed.emit("Nothing was imported.")
		return
	if s.format == AudioStreamWAV.FORMAT_8_BITS:  # widen to 16 bit
		var wide := PackedByteArray()
		wide.resize(s.data.size() * 2)
		for i in s.data.size():
			wide.encode_s16(i * 2, s.data.decode_s8(i) * 256)
		s.data = wide
		s.format = AudioStreamWAV.FORMAT_16_BITS
	if s.format != AudioStreamWAV.FORMAT_16_BITS:
		failed.emit("That wav uses a format Surtaal cannot read. Save it as a normal 16-bit wav and try again.")
		return
	s.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var ch := 2 if s.stereo else 1
	var frames := s.data.size() / (2 * ch)
	var keep := mini(frames, int(MAX_SEC * s.mix_rate))
	if keep < frames:
		s.data = s.data.slice(0, keep * 2 * ch)
		frames = keep
	if frames < int(s.mix_rate * 0.1):
		failed.emit("That file is too short.")
		return
	var t := _target
	var created := false
	if t == null:
		t = TrackManager.add_track("", "audio")
		created = true
	var path := "user://assets/%s_import%d_%d.wav" % [ProjectManager.slug(ProjectManager.project_name), t.id, Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if s.save_to_wav(path) != OK:
		if created:
			TrackManager.remove_track(t)
		failed.emit("Could not save the imported audio.")
		return
	var old := t.audio_path
	t.audio_path = path
	t.audio_dur = float(frames) / s.mix_rate
	t.audio_trim = 0.0
	t.audio_span = 0
	t.audio_peaks = PackedFloat32Array()
	if old != "":
		TrackManager.forget_audio(old)
	if created or t.name.begins_with("Voice"):
		TrackManager.rename_track(t, _name if _name != "" else "Imported audio")
	TrackManager.ensure_audio_peaks(t)
	TrackManager.notify_changed(t)
	TrackManager.tracks_changed.emit()
	imported.emit(t)
