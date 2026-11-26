extends Node
## Autoload: microphone capture + background transcription.
##
## Capture path: AudioStreamMicrophone -> "Record" bus (AudioEffectCapture, bus
## faded to -80 dB so the mic is never monitored through the speakers) -> samples.
## Requires project setting audio/driver/enable_input = true, the OS microphone
## permission (Android RECORD_AUDIO / iOS NSMicrophoneUsageDescription) and, for
## low-latency overdubbing, a native audio plugin (see docs/ARCHITECTURE.md).

signal started
signal level_changed(peak: float)             # 0..1, while recording
signal peaks_updated(peaks: PackedFloat32Array)  # coarse waveform, one value per PEAK_WINDOW_SEC
signal finished(samples: PackedFloat32Array, rate: int)
signal transcribed(notes: Array)

const BUS := "Record"
const PEAK_WINDOW_SEC := 0.02
const MAX_SEC := 120.0

var recording := false
var samples := PackedFloat32Array()
var rate := 44100
var peaks := PackedFloat32Array()

var _capture: AudioEffectCapture
var _player: AudioStreamPlayer
var _peak_acc := 0.0
var _peak_count := 0
var _peak_window := 882


func _ready() -> void:
	set_process(false)


## Begin capturing. Returns "" on success, otherwise a human-readable problem.
func start() -> String:
	if recording:
		return ""
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return "Microphone input is disabled in project settings."
	if OS.get_name() == "Android" and not ("android.permission.RECORD_AUDIO" in OS.get_granted_permissions()):
		OS.request_permissions()
		return "Allow microphone access, then tap Record again."
	var err := _ensure_setup()
	if err != "":
		return err
	rate = int(AudioServer.get_input_mix_rate())
	_peak_window = maxi(1, int(rate * PEAK_WINDOW_SEC))
	samples = PackedFloat32Array()
	peaks = PackedFloat32Array()
	_peak_acc = 0.0
	_peak_count = 0
	_capture.clear_buffer()
	_player.play()
	recording = true
	set_process(true)
	started.emit()
	return ""


func stop() -> void:
	if not recording:
		return
	_drain()
	recording = false
	set_process(false)
	_player.stop()
	finished.emit(samples, rate)


func elapsed() -> float:
	return float(samples.size()) / maxf(rate, 1)


func _process(_d: float) -> void:
	_drain()
	if elapsed() >= MAX_SEC:
		stop()


func _ensure_setup() -> String:
	if _capture != null:
		return ""
	var idx := AudioServer.get_bus_index(BUS)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_send(idx, "Master")
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(idx, _capture)
	AudioServer.set_bus_volume_db(idx, -80.0)  # effects run before the fader: capture stays full-level
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS
	add_child(_player)
	return ""


func _drain() -> void:
	if _capture == null:
		return
	var avail := _capture.get_frames_available()
	if avail <= 0:
		return
	var frames := _capture.get_buffer(avail)
	var chunk_peak := 0.0
	var base := samples.size()
	samples.resize(base + avail)
	for i in avail:
		var v := (frames[i].x + frames[i].y) * 0.5
		samples[base + i] = v
		var a := absf(v)
		chunk_peak = maxf(chunk_peak, a)
		_peak_acc = maxf(_peak_acc, a)
		_peak_count += 1
		if _peak_count >= _peak_window:
			peaks.append(_peak_acc)
			_peak_acc = 0.0
			_peak_count = 0
	level_changed.emit(chunk_peak)
	peaks_updated.emit(peaks)


## Run pitch tracking off the main thread; emits `transcribed(notes)`.
func transcribe_async(data: PackedFloat32Array, sample_rate: int) -> void:
	WorkerThreadPool.add_task(func():
		var tr := PitchTracker.track(data, sample_rate)
		var notes := HumTranscriber.segment(tr)
		transcribed.emit.call_deferred(notes), false, "transcribe hum")


## Keep the original performance as an audio asset next to the project.
func save_wav(data: PackedFloat32Array, sample_rate: int, path: String) -> bool:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.stereo = false
	s.data = bytes
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return s.save_to_wav(path) == OK


func load_wav(path: String) -> AudioStreamWAV:
	if path == "" or not FileAccess.file_exists(path):
		return null
	return AudioStreamWAV.load_from_file(path)
