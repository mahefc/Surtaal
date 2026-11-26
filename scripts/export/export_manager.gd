extends Node
## Autoload: exports the song.
##
## Bounce: the whole arrangement is played once in real time while an AudioEffectRecord
## on the Master bus captures it, so the file is exactly what you hear (per-track
## mixer, reverb, compressor, limiter). A song takes as long to export as it lasts.
## WAV (16-bit stereo, lossless) always works. MP3 needs an encoder:
##   desktop: `ffmpeg` (libmp3lame) or `lame` on the PATH, e.g. `winget install ffmpeg`
##   phones : not available through OS.execute - needs a native encoder plugin
##            (Android MediaCodec / LAME, iOS AVAssetWriter). WAV is saved instead.

signal progress(fraction: float, text: String)

const TAIL_SEC := 2.5  # let the reverb ring out

var busy := false


## Folder the exported files go to (Music/Surtaal on desktop, app storage on phones).
func output_dir() -> String:
	var base := OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)
	if base == "" or OS.get_name() in ["Android", "iOS"]:
		base = ProjectSettings.globalize_path("user://exports")
	else:
		base = base.path_join("Surtaal")
	DirAccess.make_dir_recursive_absolute(base)
	return base


## {kind, path} of a usable MP3 encoder, or {} if none.
func find_encoder() -> Dictionary:
	if OS.get_name() in ["Android", "iOS", "Web"]:
		return {}
	for candidate in [["ffmpeg", ["-version"]], ["lame", ["--version"]]]:
		var out := []
		if OS.execute(candidate[0], candidate[1], out) == 0:
			return {"kind": candidate[0], "path": candidate[0]}
	return {}


func encoder_hint() -> String:
	var enc := find_encoder()
	if not enc.is_empty():
		return "MP3 encoder found (%s)." % enc.kind
	if OS.get_name() in ["Android", "iOS"]:
		return "MP3 needs a native encoder on phones - WAV will be saved for now."
	return "No MP3 encoder found. Install ffmpeg (winget install ffmpeg) for MP3 - WAV will be saved until then."


## Returns {ok, path, format, message}.
func export_song(file_name: String, as_mp3: bool) -> Dictionary:
	if busy:
		return {"ok": false, "message": "An export is already running."}
	if not TrackManager.has_audible_content():
		return {"ok": false, "message": "Nothing to export yet - record or draw some notes first (and check mute/solo)."}
	busy = true
	Transport.stop()
	TrackManager.only = null
	TrackManager.apply_mix()

	progress.emit(0.0, "Preparing sounds...")
	await TrackManager.prepare()

	var master := AudioServer.get_bus_index("Master")
	var rec := AudioEffectRecord.new()
	rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(master, rec)  # last in the chain: after compressor + limiter
	rec.set_recording_active(true)

	Transport.loop = false
	Transport.loop_steps = TrackManager.song_steps
	var total := float(TrackManager.song_steps)
	Transport.start()
	while Transport.playing:
		var frac := clampf(float(maxi(Transport.step, 0)) / total, 0.0, 1.0)
		progress.emit(frac * 0.9, "Recording the mix...  %s / %s" % [
			TrackManager.format_time(Transport.position_sec()), TrackManager.format_time(TrackManager.song_seconds())])
		await get_tree().process_frame
	progress.emit(0.9, "Finishing...")
	await get_tree().create_timer(TAIL_SEC).timeout
	rec.set_recording_active(false)
	var wav: AudioStreamWAV = rec.get_recording()
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) == rec:
			AudioServer.remove_bus_effect(master, i)
			break
	AudioEngine.all_notes_off()

	var result := await _write_files(wav, file_name, as_mp3)
	busy = false
	progress.emit(1.0, result.message)
	return result


func _write_files(wav: AudioStreamWAV, file_name: String, as_mp3: bool) -> Dictionary:
	if wav == null or wav.data.size() < 1000:
		return {"ok": false, "message": "Nothing was recorded - is the audio output working?"}
	var dir := output_dir()
	var base := ProjectManager.slug(file_name)
	var wav_path := _unique(dir.path_join(base + ".wav"))
	if wav.save_to_wav(wav_path) != OK:
		return {"ok": false, "message": "Could not write %s" % wav_path}
	if not as_mp3:
		return {"ok": true, "path": wav_path, "format": "wav", "message": "Saved %s" % wav_path}
	var enc := find_encoder()
	if enc.is_empty():
		return {"ok": true, "path": wav_path, "format": "wav", "message": "Saved WAV (no MP3 encoder): %s\n%s" % [wav_path, encoder_hint()]}
	progress.emit(0.95, "Encoding MP3...")
	var mp3_path := _unique(dir.path_join(base + ".mp3"))
	var args: Array = []
	if enc.kind == "ffmpeg":
		args = ["-y", "-loglevel", "error", "-i", wav_path, "-codec:a", "libmp3lame", "-b:a", "192k", mp3_path]
	else:
		args = ["-b", "192", "--silent", wav_path, mp3_path]
	var state := {"done": false, "code": -1, "out": []}
	WorkerThreadPool.add_task(func():
		var out := []
		state.code = OS.execute(enc.path, args, out, true)
		state.out = out
		state.done = true, false, "mp3 encode")
	while not state.done:
		await get_tree().process_frame
	if state.code == 0 and FileAccess.file_exists(mp3_path):
		DirAccess.remove_absolute(wav_path)
		return {"ok": true, "path": mp3_path, "format": "mp3", "message": "Saved %s" % mp3_path}
	return {"ok": true, "path": wav_path, "format": "wav", "message": "MP3 encoding failed (%s) - WAV saved: %s" % [str(state.out), wav_path]}


func _unique(path: String) -> String:
	if not FileAccess.file_exists(path):
		return path
	var stem := path.get_basename()
	var ext := path.get_extension()
	var i := 2
	while FileAccess.file_exists("%s (%d).%s" % [stem, i, ext]):
		i += 1
	return "%s (%d).%s" % [stem, i, ext]
