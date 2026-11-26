extends SceneTree
## Dev tool (needs an audio device): godot --path . --script res://tools/sampler_song_test.gd
## A small song of REAL recordings (violins, horn, bass drum) played through the engine and bounced.

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
	tr.bpm = 180.0
	for id in ["violins", "horn", "bassdrum", "flute"]:
		_check("instrument '%s' is in the catalogue as a sampler" % id, im.get_by_id(id) != null and im.get_by_id(id).synth == "sampler")

	var v: Track = tm.add_track("violins")
	for n in [[0, 8, 64], [8, 8, 67], [16, 16, 71]]:
		v.add_note(n[0], n[1], n[2], 0.8)
	var h: Track = tm.add_track("horn")
	for n in [[0, 16, 48], [16, 16, 55]]:
		h.add_note(n[0], n[1], n[2], 0.85)
	var d: Track = tm.add_track("bassdrum")
	d.add_note(0, 2, 48, 0.9)
	d.add_note(16, 2, 48, 0.9)
	tm.notify_changed(v)
	tm.notify_changed(h)
	tm.notify_changed(d)

	var t0 := Time.get_ticks_msec()
	await tm.prepare()
	print("prepared the song's recorded notes in %d ms" % (Time.get_ticks_msec() - t0))
	var all_cached := true
	for t in [v, h, d]:
		var def: InstrumentDef = im.get_by_id(t.instrument_id)
		for n in t.notes:
			all_cached = all_cached and root.get_node("SampleManager").has_sample(def, n.midi, 0)
	_check("every note of the song is rendered before playback", all_cached)

	var result: Dictionary = await ex.export_song("sampler song test", false)
	var ok: bool = result.get("ok", false) and FileAccess.file_exists(result.get("path", ""))
	_check("song exported", ok)
	if ok:
		var wav := AudioStreamWAV.load_from_file(result.path)
		var n := wav.data.size() / 4
		var peak := 0
		var energy := 0.0
		var clipped := 0
		for i in range(0, n, 3):
			var l := wav.data.decode_s16(i * 4)
			peak = maxi(peak, absi(l))
			energy += float(l) * float(l)
			if absi(l) >= 32700:
				clipped += 1
		var rms := sqrt(energy / (n / 3.0)) / 32768.0
		var secs := float(n) / wav.mix_rate
		print("exported %.1f s: peak %d/32767, rms %.3f (%.1f dBFS), clipped samples %d" % [secs, peak, rms, 20.0 * log(maxf(rms, 1e-6)) / log(10.0), clipped])
		_check("recorded instruments are audible", peak > 3000)
		_check("not clipping (limiter working)", clipped == 0)
		_check("sensible loudness (-30 .. -8 dBFS rms)", rms > 0.03 and rms < 0.4)
		DirAccess.remove_absolute(result.path)
	print("SAMPLER SONG FAILURES: ", bad)
	pm.new_project()
	quit(bad)
