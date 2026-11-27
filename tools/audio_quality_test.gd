extends SceneTree
## Dev tool (needs SURTAAL_FRESH=1 so no project data is touched):
##   $env:SURTAAL_FRESH=1; godot --path . --script res://tools/audio_quality_test.gd -- out.wav
## Plays a short piano + strings song through the real mixer and bounces it, so the sound
## chain can be measured (see tools/analyze_wav.py).


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://aq.wav"
	var tm: Node = root.get_node("TrackManager")
	var tr: Node = root.get_node("Transport")
	var pm: Node = root.get_node("ProjectManager")
	var ex: Node = root.get_node("ExportManager")
	pm.new_project()
	tr.bpm = 100.0
	var piano: Track = tm.add_track("grand_piano")
	var pad: Track = tm.add_track("violins")
	var bass: Track = tm.add_track("cellos")
	var chords := [[48, 52, 55, 60], [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59]]
	for bar in 4:
		var c: Array = chords[bar]
		for n in c:
			piano.add_note(bar * 16, 8, n + 12, 0.7)
			piano.add_note(bar * 16 + 8, 8, n + 12, 0.55)
		pad.add_note(bar * 16, 16, c[1] + 12, 0.7)
		pad.add_note(bar * 16, 16, c[2] + 12, 0.7)
		bass.add_note(bar * 16, 16, c[0] - 12, 0.8)
	for i in 8:  # a melody on top
		piano.add_note(i * 8, 6, [76, 79, 77, 74, 72, 76, 79, 83][i], 0.85)
	tm.notify_changed(piano)
	tm.notify_changed(pad)
	tm.notify_changed(bass)

	var result: Dictionary = await ex.export_song("aq_test", false)
	print("result: ", result)
	if result.get("ok", false):
		DirAccess.copy_absolute(result.path, out)
		DirAccess.remove_absolute(result.path)
		print("copied to ", out)
	quit(0 if result.get("ok", false) else 1)
