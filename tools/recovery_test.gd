extends SceneTree
## Dev tool (run twice, WITHOUT SURTAAL_FRESH):
##   godot --headless --script res://tools/recovery_test.gd -- write   # edit + autosave, then "crash"
##   godot --headless --script res://tools/recovery_test.gd -- read    # must come back with the edit

func _initialize() -> void:
	await process_frame
	var mode: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "read"
	var pm: Node = root.get_node("ProjectManager")
	var tm: Node = root.get_node("TrackManager")
	if mode == "write":
		pm.new_project()
		pm.rename("crash test")
		tm.add_track("violin").add_note(6, 3, 71, 0.7)
		root.get_node("Transport").bpm = 147.0
		pm.flush()
		pm._on_autosave()
		print("WROTE autosave (dirty=%s)" % pm.dirty)
		quit(0)
	else:
		var ok: bool = pm.project_name == "crash test" and tm.tracks.size() == 1 \
			and tm.tracks[0].instrument_id == "violin" and tm.tracks[0].notes[0].midi == 71 and root.get_node("Transport").bpm == 147.0
		print("RECOVERED name=%s tracks=%d bpm=%s  %s" % [pm.project_name, tm.tracks.size(),
			root.get_node("Transport").bpm, "ok" if ok else "FAIL"])
		DirAccess.remove_absolute("user://projects/_autosave.json")  # leave a clean slate
		quit(0 if ok else 1)
