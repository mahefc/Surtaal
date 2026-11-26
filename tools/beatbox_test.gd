extends SceneTree
## Dev tool: godot --headless --script res://tools/beatbox_test.gd
## Beatbox -> drum loop: synthetic kick / snare / hat hits (with a little timing jitter) must come
## back as the right lane on the right step; silence gives nothing.

const RATE := 44100
var bad := 0


func _check(label: String, cond: bool) -> void:
	print("%s  %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		bad += 1


func _add(buf: PackedFloat32Array, at: float, kind: String, rng: RandomNumberGenerator) -> void:
	var start := int(at * RATE)
	var len := int(0.12 * RATE)
	var lp := 0.0
	var prev := 0.0
	for i in len:
		if start + i >= buf.size():
			break
		var t := float(i) / RATE
		var v := 0.0
		match kind:
			"kick":
				v = sin(TAU * (60.0 + 90.0 * exp(-t * 40.0)) * t) * exp(-t * 28.0) * 0.8
			"snare":
				var w := rng.randf_range(-1.0, 1.0)
				lp += 0.3 * (w - lp)
				v = (lp * 1.6 + sin(TAU * 190.0 * t) * 0.25) * exp(-t * 26.0) * 0.7
			"hat":
				var w2 := rng.randf_range(-1.0, 1.0)
				v = (w2 - prev) * 0.5 * exp(-t * 70.0) * 0.6
				prev = w2
		buf[start + i] += v


func _initialize() -> void:
	await process_frame
	var A = load("res://scripts/recording/beatbox_analyzer.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bpm := 100.0
	var step_sec := 60.0 / bpm / 4.0
	var want := {"kick": [0, 8, 10], "snare": [4, 12], "hat": [2, 6, 14]}
	var buf := PackedFloat32Array()
	buf.resize(int(16 * step_sec * RATE) + int(0.4 * RATE))
	for kind in want:
		for s in want[kind]:
			var jitter := rng.randf_range(-0.02, 0.02)
			_add(buf, maxf(s * step_sec + jitter + 0.05, 0.0), kind, rng)  # +50 ms "latency"
	for i in buf.size():
		buf[i] += rng.randf_range(-0.004, 0.004)  # mic hiss

	var hits: Array = A.analyze(buf, RATE)
	_check("it found all 8 hits (%d)" % hits.size(), hits.size() == 8)
	var got: Dictionary = A.to_steps(hits, bpm, 16, 0.05)
	for kind in want:
		_check("%s on steps %s (got %s)" % [kind, str(want[kind]), str(got[kind])], got[kind] == want[kind])

	var quiet := PackedFloat32Array()
	quiet.resize(RATE)
	for i in quiet.size():
		quiet[i] = rng.randf_range(-0.001, 0.001)
	_check("silence gives no hits", A.analyze(quiet, RATE).is_empty())

	var wrapped: Dictionary = A.to_steps([{"t": 2.5, "kind": "kick", "vel": 1.0}], bpm, 16, 0.0)
	_check("a hit after the end of the loop wraps around (%s)" % str(wrapped.kick), wrapped.kick == [1])

	# ---- the rack: beatbox result and the ready-made loops
	var tm: Node = root.get_node("TrackManager")
	var t = tm.add_track("kick", "drums")
	t.set_drum("Hi-hat", 3, true)
	var placed: int = tm.apply_beatbox(t, got)
	_check("the take fills the Kick/Snare/Hi-hat layers (%d hits)" % placed, placed == 8 and t.drum_steps["Kick"] == [0, 8, 10] and t.drum_steps["Hi-hat"] == [2, 6, 14])
	tm.set_drum_res(t, 4)
	tm.load_drum_starter(t, "Rock with a fill")
	_check("a ready-made loop spreads over a 64-cell bar, still one bar (%d)" % t.pattern_steps(), t.grid_steps() == 64 and t.pattern_steps() == 16 and 60 in t.drum_steps["Snare"] and 56 in t.drum_steps["Snare"])
	t.drum_bars = 4
	tm.load_drum_starter(t, "Hip-hop")
	_check("an older multi-bar pattern is filled by repeating the loop", t.drum_steps["Kick"].size() == 12 and 3 * 64 + 28 in t.drum_steps["Kick"])
	t.drum_bars = 1
	tm.set_drum_res(t, 1)
	for name in tm.DRUM_STARTERS:
		var ok := true
		for lane in tm.DRUM_STARTERS[name]:
			ok = ok and t.lane_index(lane) != -1
		_check("loop '%s' fits the default layers" % name, ok)

	# ---- swap a layer's sound, per-hit velocity, pan
	var t2 = tm.add_track("kick", "drums")
	tm.load_drum_starter(t2, "Basic beat")
	t2.set_hit_vel("Snare", 4, 0.3)
	_check("a default downbeat is stronger than an off-beat", t2.hit_vel("Kick", 0) > t2.hit_vel("Kick", 10))
	_check("a drawn velocity is used (%.2f)" % t2.hit_vel("Snare", 4), is_equal_approx(t2.hit_vel("Snare", 4), 0.3))
	var other := ""
	for d in root.get_node("InstrumentManager").instruments:
		if d.is_loop_only() and d.id != "snare" and d.id != "kick" and d.id != "hat":
			other = d.id
			break
	_check("there is another loop sound to swap in (%s)" % other, other != "")
	tm.change_drum_lane(t2, "Snare", other)
	var new_key: String = t2.drum_lanes[1].key
	_check("the swapped layer is renamed and keeps its hits (%s)" % new_key, new_key != "Snare" and t2.drum_steps.get(new_key, []) == [4, 12] and not t2.drum_steps.has("Snare"))
	_check("... and its drawn velocity (%.2f)" % t2.hit_vel(new_key, 4), is_equal_approx(t2.hit_vel(new_key, 4), 0.3))
	_check("... and it still plays the snare part", t2.lane_key_for_role("snare") == new_key)
	tm.load_drum_starter(t2, "Funk")
	_check("a ready-made loop reaches the swapped layer", 15 in t2.drum_steps.get(new_key, []))
	t2.set_hit_vel(new_key, 15, 0.5)
	var back = load("res://scripts/music/track.gd").from_dict(JSON.parse_string(JSON.stringify(t2.to_dict())))
	_check("velocity and part survive saving (%.2f)" % back.hit_vel(new_key, 15), is_equal_approx(back.hit_vel(new_key, 15), 0.5) and back.lane_key_for_role("snare") == new_key)
	t2.set_drum(new_key, 15, false)
	_check("removing a hit forgets its velocity", not t2.drum_vel[new_key].has(15))
	var vels: Dictionary = A.to_velocities(hits, bpm, 16, 0.05)
	_check("beatbox loudness becomes hit velocity", vels.kick.has(0) and vels.kick[0] > 0.3 and vels.kick[0] <= 1.0)
	t2.pan_curve = [[0, -1.0], [32, 1.0]]
	_check("the loop's pan curve moves across the song (%.2f)" % t2.pan_at(16), absf(t2.pan_at(16)) < 0.05)

	print("RESULT: %s" % ("PASS" if bad == 0 else "%d FAILED" % bad))
	quit(0 if bad == 0 else 1)
