extends SceneTree
## Dev tool (needs a real audio device, NOT --headless):
##   godot --path . --script res://tools/mic_test.gd
## Records 1.5 s from the default input, then checks capture, WAV save/load and async transcription.

func _initialize() -> void:
	await process_frame
	var rm: Node = root.get_node("RecordingManager")
	print("input devices: ", AudioServer.get_input_device_list(), "  mix rate: ", AudioServer.get_input_mix_rate())
	var err: String = rm.start()
	if err != "":
		print("MIC START FAILED: ", err)
		quit(1)
		return
	await create_timer(1.5).timeout
	rm.stop()
	var s: PackedFloat32Array = rm.samples
	var peak := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
	var secs: float = float(s.size()) / float(rm.rate)
	print("captured %d samples = %.2f s @ %d Hz, peak %.4f, peak windows %d" % [s.size(), secs, rm.rate, peak, rm.peaks.size()])
	var ok: bool = secs > 1.0 and secs < 2.0

	var path := "user://assets/_mic_test.wav"
	var saved: bool = rm.save_wav(s, rm.rate, path)
	var back: AudioStreamWAV = rm.load_wav(path)
	var wav_ok: bool = saved and back != null and back.data.size() == s.size() * 2 and back.mix_rate == rm.rate
	print("wav save/load round-trip: saved=%s reloaded=%s bytes=%d  %s" % [saved, back != null, back.data.size() if back else 0, "ok" if wav_ok else "FAIL"])
	DirAccess.remove_absolute(path)

	var done := [false, 0]
	rm.transcribed.connect(func(n: Array): done[0] = true; done[1] = n.size())
	rm.transcribe_async(s, rm.rate)
	var t0 := Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	print("async transcription finished=%s notes=%d (room noise should be ~0)  %s" % [done[0], done[1], "ok" if done[0] else "FAIL"])
	print("MIC TEST: ", "ok" if (ok and wav_ok and done[0]) else "FAIL")
	quit(0 if (ok and wav_ok and done[0]) else 1)
