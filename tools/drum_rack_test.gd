extends SceneTree
## Dev tool: godot --headless --script res://tools/drum_rack_test.gd
## Drum rack: layers are any instrument; composed together in one pattern.

var bad := 0


func _check(label: String, cond: bool) -> void:
	print("%s  %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		bad += 1


func _initialize() -> void:
	await process_frame
	var tm: Node = root.get_node("TrackManager")
	var pm: Node = root.get_node("ProjectManager")
	pm.new_project()
	var t: Track = tm.add_track("", "drums")
	_check("a new drum track starts with the 4 default layers", t.drum_lanes.size() == 4 and t.lane_index("Kick") == 0)

	tm.add_drum_lane(t, "dhol")
	tm.add_drum_lane(t, "taiko")
	tm.add_drum_lane(t, "tabla")  # a second tabla layer: keys must stay unique
	_check("any instrument can join the rack (7 layers)", t.drum_lanes.size() == 7)
	_check("duplicate instruments get unique layer names", t.lane_index("Tabla") != -1 and t.lane_index("Tabla 2") != -1)

	t.drum_steps = {}
	t.set_drum("Dhol", 0, true)
	t.set_drum("Dhol", 6, true)
	t.set_drum("Taiko", 8, true)
	t.set_drum("Kick", 0, true)
	tm.set_drum_res(t, 2)
	_check("a finer grid has 32 cells but is still ONE bar", t.grid_steps() == 32 and t.pattern_steps() == 16 and t.drum_bars == 1)
	_check("hits keep their place in the music (cell x2)", t.drum_on("Dhol", 12) and t.drum_on("Taiko", 16) and t.drum_on("Kick", 0) and not t.drum_on("Dhol", 6))
	t.set_drum("Dhol", 13, true)  # a hit between two 16th notes
	tm.set_drum_res(t, 4)
	_check("64 cells: still one bar, hits move to cell x4", t.grid_steps() == 64 and t.pattern_steps() == 16 and t.drum_on("Dhol", 24) and t.drum_on("Dhol", 26))
	tm.set_drum_res(t, 1)
	_check("back to 16: the off-grid hit snaps to the nearest 16th", t.grid_steps() == 16 and t.drum_on("Dhol", 6) and t.drum_on("Dhol", 7) and t.drum_on("Taiko", 8))
	t.set_drum("Dhol", 7, false)

	# mute: a muted layer is neither prepared nor played
	t.drum_lanes[t.lane_index("Taiko")].mute = true
	var needed: Array = tm._needed_samples(t)
	var ids := []
	for e in needed:
		ids.append(e.def.id)
	_check("muted layer is skipped (%s)" % str(ids), "dhol" in ids and "kick" in ids and not ("taiko" in ids))

	# remove a layer
	tm.remove_drum_lane(t, "Dhol")
	_check("removing a layer deletes it and its hits", t.lane_index("Dhol") == -1 and not t.drum_steps.has("Dhol"))

	# persistence
	tm.set_drum_res(t, 4)
	t.drum_lanes[0].midi = 40
	pm.flush()
	var before: String = JSON.stringify(t.to_dict())
	var back := Track.from_dict(JSON.parse_string(before))
	_check("rack survives save/load (layers, pitch, mute, length)",
		JSON.stringify(back.to_dict()) == before and back.drum_res == 4 and back.drum_bars == 1 and back.drum_lanes[0].midi == 40 and back.drum_lanes[back.lane_index("Taiko")].mute)

	# old projects (before racks): no lanes stored -> default kit, patterns kept
	var old := Track.from_dict({"id": 9, "kind": "drums", "name": "Old drums", "drums": {"Kick": [0, 8], "Snare": [4]}})
	_check("old drum tracks load with the default kit and keep their hits", old.drum_lanes.size() == 4 and old.drum_on("Kick", 8) and old.pattern_steps() == 16)

	print("DRUM RACK FAILURES: ", bad)
	pm.new_project()
	quit(bad)
