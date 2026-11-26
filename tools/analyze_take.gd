extends SceneTree
## Dev tool: godot --headless --script res://tools/analyze_take.gd -- <path-to.wav>
## Runs the real pitch tracker + transcriber on a recorded voice take and prints what it heard.

const NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


func _note_name(m: float) -> String:
	var r := int(round(m))
	return "%s%d" % [NAMES[posmod(r, 12)], r / 12 - 1]


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <wav>")
		quit(1)
		return
	var wav := AudioStreamWAV.load_from_file(args[0])
	if wav == null:
		print("cannot load ", args[0])
		quit(1)
		return
	var ch := 2 if wav.stereo else 1
	var n := wav.data.size() / (2 * ch)
	var x := PackedFloat32Array()
	x.resize(n)
	var peak := 0.0
	var energy := 0.0
	for i in n:
		x[i] = wav.data.decode_s16(i * ch * 2) / 32768.0
		peak = maxf(peak, absf(x[i]))
		energy += x[i] * x[i]
	var rate := wav.mix_rate
	print("== %s" % args[0].get_file())
	print("   %.2f s @ %d Hz, %s, peak %.3f, rms %.4f" % [float(n) / rate, rate, "stereo" if wav.stereo else "mono", peak, sqrt(energy / n)])

	var tr := PitchTracker.track(x, rate)
	var f0: PackedFloat32Array = tr.f0
	var rms: PackedFloat32Array = tr.rms
	var voiced := 0
	var lo := 1e9
	var hi := 0.0
	var mids := []
	for f in f0:
		if f > 0.0:
			voiced += 1
			lo = minf(lo, f)
			hi = maxf(hi, f)
			mids.append(69.0 + 12.0 * log(f / 440.0) / log(2.0))
	print("   frames %d (%.0f ms hop): voiced %d (%.0f%%), f0 %.0f-%.0f Hz, gate %.4f" % [f0.size(), tr.hop_sec * 1000.0, voiced, 100.0 * voiced / maxf(f0.size(), 1), lo, hi, tr.gate])
	if mids.size() > 0:
		mids.sort()
		print("   pitch range %s .. %s (median %s)" % [_note_name(mids[0]), _note_name(mids[-1]), _note_name(mids[mids.size() / 2])])
	# how choppy is the voicing? (runs of voiced frames)
	var runs := []
	var run := 0
	for f in f0:
		if f > 0.0:
			run += 1
		elif run > 0:
			runs.append(run)
			run = 0
	if run > 0:
		runs.append(run)
	var short_runs := 0
	for r in runs:
		if r * tr.hop_sec < 0.1:
			short_runs += 1
	print("   voiced runs: %d, of which shorter than 100 ms: %d" % [runs.size(), short_runs])

	var notes := HumTranscriber.segment(tr)
	print("   notes found: %d" % notes.size())
	var line := ""
	for nt in notes:
		line += "%s(%.2f+%.2f) " % [_note_name(nt.midi), nt.t0, nt.t1 - nt.t0]
	print("   ", line)
	var fr := []
	for nt in notes:
		fr.append("%.2f" % (nt.midi - round(nt.midi)))
	print("   cents off the nearest semitone (in semitones): ", " ".join(fr))
	var tn := HumTranscriber.to_track_notes(notes, 100.0, 0, 0.0)
	var tl := ""
	for nt in tn:
		tl += "%s%+.0fc@%.2fs/%.2fs " % [_note_name(nt.midi), nt.cents, (nt.start + nt.off) * 0.15, nt.dur * 0.15]
	print("   what the instrument now plays (note, sung offset in cents, start, length): ", tl)
	print("   estimated tempo from the onsets: %.0f BPM (project default 100)" % HumTranscriber.estimate_bpm(notes, 100.0))
	quit(0)
