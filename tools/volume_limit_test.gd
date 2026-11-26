extends SceneTree
## Dev tool: does AudioStreamPlayer.volume_db really pass more than +24 dB?  (needs SURTAAL_FRESH=1)
##   godot --headless --path . --script res://tools/volume_limit_test.gd


func _level(db: float) -> float:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 44100
	var bytes := PackedByteArray()
	bytes.resize(44100 * 2)
	for i in 44100:
		bytes.encode_s16(i * 2, int(sin(TAU * 440.0 * i / 44100.0) * 300.0))  # about -40 dBFS
	s.data = bytes
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = 44100
	var p := AudioStreamPlayer.new()
	p.bus = "Instruments"
	p.stream = s
	p.volume_db = db
	root.add_child(p)
	p.play()
	var peak := -200.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 600:
		await process_frame
		peak = maxf(peak, AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index("Instruments"), 0))
	print("volume_db requested %5.1f -> player reports %5.1f, Instruments bus peak %6.1f dB" % [db, p.volume_db, peak])
	p.stop()
	p.queue_free()
	await create_timer(0.3).timeout
	return peak


func _initialize() -> void:
	await process_frame
	for db in [0.0, 12.0, 24.0, 36.0, 48.0]:
		await _level(db)
	quit()
