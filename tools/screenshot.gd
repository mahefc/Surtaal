extends SceneTree
## Dev tool: godot --path . --resolution 450x900 --script res://tools/screenshot.gd -- out.png VIEW
## VIEW: empty | tracks | editor | drums | picker
## "editor" synthesises a hummed melody and runs it through the real transcription path.

func _hum(notes: Array, rate: int) -> PackedFloat32Array:
	var total := 0.3
	for n in notes:
		total += n[1] + n[2]
	var buf := PackedFloat32Array()
	buf.resize(int((total + 0.3) * rate))
	var t := 0.3
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for n in notes:
		var f0 := 440.0 * pow(2.0, (n[0] - 69.0) / 12.0)
		var ph := 0.0
		var count := int(n[1] * rate)
		for i in count:
			var tt := float(i) / rate
			ph += TAU * f0 * pow(2.0, 20.0 * sin(TAU * 5.5 * tt) / 1200.0) / rate
			var env := minf(1.0, tt / 0.04) * minf(1.0, (count - i) / (0.03 * rate))
			buf[int(t * rate) + i] += 0.25 * env * (sin(ph) + 0.5 * sin(2 * ph) + 0.25 * sin(3 * ph)) + rng.randf_range(-0.004, 0.004)
		t += n[1] + n[2]
	return buf


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shot.png"
	var view: String = args[1] if args.size() > 1 else "empty"
	var scene: Node = load("res://scenes/studio/studio.tscn").instantiate()
	root.add_child(scene)
	var tm: Node = root.get_node("TrackManager")
	var tr: Node = root.get_node("Transport")
	for i in 30:
		await process_frame

	if view != "empty" and view != "picker" and view != "export" and view != "mix" and view != "choose" and view != "voice":
		# a hummed line -> detected notes -> bansuri track
		var melody := [[72, 0.5, 0.05, 0], [74, 0.5, 0.0, 0], [76, 0.4, 0.05, 0], [76, 0.4, 0.05, 0],
			[79, 0.7, 0.08, 0], [77, 0.5, 0.0, 0], [76, 0.5, 0.05, 0], [74, 0.7, 0.0, 0]]
		var found := HumTranscriber.transcribe(_hum(melody, 44100), 44100)
		var quantised := HumTranscriber.to_track_notes(found, 100.0, 0, 0.0)
		var t1: Track = tm.add_track("bansuri")
		for n in quantised:
			t1.add_note(n.start, n.len, n.midi, n.vel)
		print("detected %d notes -> %d quantised" % [found.size(), quantised.size()])
		var t2: Track = tm.add_track("sitar")
		for n in [[0, 4, 48], [8, 4, 55], [16, 4, 53], [24, 4, 48], [32, 8, 52], [48, 8, 55]]:
			t2.add_note(n[0], n[1], n[2], 0.8)
		var t3: Track = tm.add_track("", "drums")
		for i in 3:  # an empty track too, as a fresh "add" would leave it
			pass
		tm.add_track("violin")
		if view == "editor" or view == "keys" or view == "choice":
			scene._open_editor(t1)
			if view == "keys":
				scene._editor._set_source(true)
			if view == "choice":
				scene._editor._on_record_pressed()
		elif view == "drums":
			tm.add_drum_lane(t3, "dhol")
			tm.add_drum_lane(t3, "taiko")
			tm.add_drum_lane(t3, "parai")
			for st in [0, 3, 6, 10, 14]:
				t3.set_drum("Dhol", st, true)
			for st in [0, 8]:
				t3.set_drum("Taiko", st, true)
			for st in [2, 5, 7, 11, 13, 15]:
				t3.set_drum("Parai", st, true)
			tm.set_drum_res(t3, 2)
			tm.notify_changed(t3)
			scene._open_editor(t3)
		else:
			tr.start()
	elif view == "export":
		var am: Node = tm
		var a: Track = am.add_track("bansuri")
		a.add_note(0, 8, 72, 0.8)
		a.add_note(16, 8, 76, 0.8)
		am.notify_changed(a)
		scene._export.open()
	elif view == "mix":
		var a1: Track = tm.add_track("violins")
		a1.add_note(0, 8, 64, 0.8)
		a1.add_note(8, 8, 67, 0.8)
		tm.add_track("", "drums")
		tm.notify_changed(a1)
		await process_frame
		await process_frame
		scene._arrangement._mix_popup.open_for(a1, false, scene._arrangement._lane_nodes[0])
	elif view == "choose":
		var c1: Track = tm.add_track("bansuri")
		c1.add_note(0, 8, 72, 0.8)
		c1.add_note(8, 8, 76, 0.8)
		tm.notify_changed(c1)
		await process_frame
		scene._arrangement._add_popup.popup_centered()
	elif view == "voice":
		var v1: Track = tm.add_track("", "audio")
		var raw := PackedFloat32Array()
		raw.resize(48000 * 4)
		for i in raw.size():
			var tt := float(i) / 48000.0
			raw[i] = (0.35 * sin(TAU * 200.0 * tt) * (0.5 + 0.5 * sin(TAU * 0.7 * tt))) if tt > 0.3 and tt < 3.5 else 0.004 * sin(i * 0.7)
		var clean := VoiceEnhancer.process(raw, 48000)
		var rm: Node = root.get_node("RecordingManager")
		rm.save_wav(clean, 48000, "user://assets/_shot_voice.wav")
		v1.audio_path = "user://assets/_shot_voice.wav"
		v1.audio_dur = 4.0
		tm.add_track("grand_piano").add_note(0, 8, 60, 0.8)
		tm.notify_changed(v1)
		await process_frame
		scene._open_editor(v1)
	elif view == "picker":
		scene._picker.open("Add a track", true)

	await create_timer(0.8).timeout
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	tr.stop()
	quit()
