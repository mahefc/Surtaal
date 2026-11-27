extends SceneTree
## Dev tool: godot --path . --script res://tools/mix_export_test.gd   (needs an audio device for the export part)
## Automatic song length, mixer (solo/mute/pan/volume), play-one-track, and a real WAV bounce.

var bad := 0


func _check(label: String, cond: bool) -> void:
	print("%s  %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		bad += 1


func _initialize() -> void:
	await process_frame
	var tm: Node = root.get_node("TrackManager")
	var tr: Node = root.get_node("Transport")
	var pm: Node = root.get_node("ProjectManager")
	var ex: Node = root.get_node("ExportManager")
	var im: Node = root.get_node("InstrumentManager")
	pm.new_project()
	tr.bpm = 220.0  # 16th = 68 ms: keeps real-time tests short

	# ---- song length is automatic, no bars to set
	_check("empty song has a default length (4 bars)", tm.song_steps == 64)
	var a: Track = tm.add_track("grand_piano")
	a.add_note(0, 4, 60, 0.8)
	a.add_note(20, 4, 64, 0.8)
	tm.notify_changed(a)
	_check("song grows with the notes: end at step 24 -> 32 steps", tm.song_steps == 32)
	a.add_note(1000, 8, 67, 0.8)
	tm.notify_changed(a)
	_check("song reaches far (step 1008 -> 1008 steps)", tm.song_steps == 1008)
	var max_steps: int = tm.max_steps()
	a.add_note(max_steps + 500, 8, 67, 0.8)
	tm.notify_changed(a)
	_check("song length is capped at 10 minutes (%d steps)" % max_steps, tm.song_steps == max_steps and tm.song_seconds() <= 600.5)
	a.notes.clear()
	a.add_note(0, 4, 60, 0.8)
	a.add_note(20, 4, 64, 0.8)
	tm.notify_changed(a)

	# ---- mixer
	var b: Track = tm.add_track("bansuri")
	b.add_note(0, 4, 72, 0.8)
	tm.notify_changed(b)
	a.volume = 0.425  # half of unity (0.85)
	a.pan = -0.5
	tm.mix_changed()
	var ia := AudioServer.get_bus_index(tm.bus_of(a))
	var ib := AudioServer.get_bus_index(tm.bus_of(b))
	_check("each track has its own bus", ia != -1 and ib != -1 and ia != ib)
	_check("volume 0.425 = -6 dB", absf(AudioServer.get_bus_volume_db(ia) - (-6.02)) < 0.1)
	_check("pan applied (-0.5)", absf((AudioServer.get_bus_effect(ia, 0) as AudioEffectPanner).pan + 0.5) < 0.01)
	_check("both audible by default", tm.audible(a) and tm.audible(b))
	b.solo = true
	tm.mix_changed()
	_check("solo b: a silenced, b audible", not tm.audible(a) and tm.audible(b) and AudioServer.is_bus_mute(ia) and not AudioServer.is_bus_mute(ib))
	b.solo = false
	a.muted = true
	tm.mix_changed()
	_check("mute a: a silenced, b audible", not tm.audible(a) and tm.audible(b))
	a.muted = false
	tm.mix_changed()

	# ---- play one track alone
	tm.play_only(b)
	var t0 := Time.get_ticks_msec()
	while not tr.playing and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_check("play-one starts and isolates the track", tr.playing and tm.only == b and tm.audible(b) and not tm.audible(a))
	t0 = Time.get_ticks_msec()
	while tr.playing and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_check("play-one stops by itself at the track's end and restores the mix", not tr.playing and tm.only == null and tm.audible(a))

	# ---- real export (bounce)
	ex.progress.connect(func(f, t): pass)
	var result: Dictionary = await ex.export_song("selftest export", false)
	print("export result: ", result)
	var ok: bool = result.get("ok", false) and FileAccess.file_exists(result.get("path", ""))
	if ok:
		var wav := AudioStreamWAV.load_from_file(result.path)
		var secs: float = float(wav.data.size()) / (2.0 * (2 if wav.stereo else 1)) / wav.mix_rate
		var peak := 0
		for i in range(0, wav.data.size() - 1, 2 * 7):
			peak = maxi(peak, absi(wav.data.decode_s16(i)))
		print("exported %.2f s, %s, %d Hz, peak %d/32767" % [secs, "stereo" if wav.stereo else "mono", wav.mix_rate, peak])
		_check("export is audible (not silence)", peak > 500)
		_check("export length ~ song + tail (%.1f s expected ~%.1f)" % [secs, tm.song_seconds() + 2.5], absf(secs - (tm.song_seconds() + 2.5)) < 1.5)
		DirAccess.remove_absolute(result.path)
	_check("export produced a file", ok)

	print("MIX/EXPORT FAILURES: ", bad)
	pm.new_project()
	quit(bad)
