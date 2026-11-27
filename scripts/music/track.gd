class_name Track
extends RefCounted
## One track in the arrangement.
##   melodic: notes {start, len, midi, vel} in 16th-note steps from song start.
##   drums:   a one-bar step grid per lane, looped across the whole song.
## Mixer settings (volume, pan, mute, solo) live here too.

const STEPS_PER_BAR := 16
const HIT_VEL := 0.85  # default loudness of a drum hit on a downbeat

var id := 0
var name := ""
var kind := "melodic"  # "melodic" | "drums"
var instrument_id := ""
var preset := 0
var muted := false
var solo := false
var volume := 0.85  # 0..1, 0.85 = unity
var pan := 0.0      # -1 (left) .. +1 (right)
var pan_curve: Array = []  # drawn pan over time: [[step, -1..1], ...] (empty = fixed pan)
var reverb := 0.0   # 0..1: reverb amount, set in the instrument editor (off by default)
var notes: Array[Dictionary] = []
## Drum rack: every layer is any instrument. {key, id (instrument), midi, vol 0..1, mute}
var drum_lanes: Array[Dictionary] = []
var drum_bars := 1         # pattern length in bars (projects made before the finer grid may use 2 or 4)
var drum_res := 1          # grid cells per 16th note: 1, 2 or 4 = 16 / 32 / 64 cells in a bar (finer hits, same bar)
var drum_steps := {}       # lane key -> Array[int] of active steps (0 .. pattern_steps-1)
var drum_vel := {}         # lane key -> {step: 0.1..1.0} loudness of the hits that were drawn (others: default)
var hum_path := ""  # original recording (audio asset), kept alongside the notes
## Loop clip placement (drum tracks): where the loop starts in the song and how long it plays (0 = to the end).
var drum_start := 0
var drum_len := 0
## Voice (audio) track: a recorded take played as audio. kind == "audio".
var audio_path := ""
var audio_dur := 0.0       # seconds in the recording
var audio_start := 0       # step where the clip starts in the song
var audio_trim := 0.0      # seconds kept from the start of the take (0 = all of it)
var audio_span := 0        # steps the clip plays for when it is stretched longer than the take: the take loops (0 = once)
var audio_peaks := PackedFloat32Array()  # waveform for display (one peak per 20 ms); rebuilt from the file, not saved


## Seconds of the take that are played (after trimming).
func audio_len_sec() -> float:
	return audio_trim if (audio_trim > 0.0 and audio_trim < audio_dur) else audio_dur


## Notes sit on the 16th-note grid (start/len/midi), but a note can also carry the EXACT performance:
##   cents - how far off the semitone it was sung (-50..50), played by the instrument as sung
##   off   - fraction of a step the note starts after its grid step (0..1)
##   dur   - exact length in steps
## Voice recordings fill these in so the instrument plays what was actually sung. Editing a note by hand clears them.
func add_note(start: int, length: int, midi: int, vel: float = 0.8, cents: float = 0.0, off: float = 0.0, dur: float = 0.0) -> Dictionary:
	var n := {"start": maxi(start, 0), "len": maxi(length, 1), "midi": clampi(midi, 0, 127), "vel": clampf(vel, 0.05, 1.0)}
	if absf(cents) >= 0.5:
		n["cents"] = clampf(cents, -50.0, 50.0)
	if off > 0.001:
		n["off"] = clampf(off, 0.0, 0.999)
	if dur > 0.0:
		n["dur"] = dur
	notes.append(n)
	return n


func remove_note(n: Dictionary) -> void:
	notes.erase(n)


## Note covering this step at this pitch, or {}.
func note_at(step: int, midi: int) -> Dictionary:
	for n in notes:
		if n.midi == midi and step >= n.start and step < n.start + n.len:
			return n
	return {}


func notes_starting_at(step: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in notes:
		if n.start == step:
			out.append(n)
	return out


## Delete notes that begin inside [from_step, to_step).
func clear_range(from_step: int, to_step: int) -> void:
	var keep: Array[Dictionary] = []
	for n in notes:
		if n.start < from_step or n.start >= to_step:
			keep.append(n)
	notes = keep


## Where the first note starts (0 when there are no notes).
func start_step() -> int:
	if notes.is_empty():
		return 0
	var s := 1 << 30
	for n in notes:
		s = mini(s, n.start)
	return s


func end_step() -> int:
	var e := 0
	for n in notes:
		e = maxi(e, n.start + n.len)
	return e


static func default_drum_lanes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Virtuosity drum kit (CC0): roles stay kick/snare/hat so patterns and randomize still work.
	for l in [["Kick", "kick", 36, "kick"], ["Snare", "snare", 38, "snare"], ["Hi-hat", "hat", 42, "hat"]]:
		out.append({"key": l[0], "id": l[1], "midi": l[2], "vol": 0.85, "mute": false, "role": l[3]})
	return out


## What a layer plays in the beat: "kick", "snare" or "hat" for the first three layers (it stays
## the same when the sound is swapped for another one), otherwise the instrument itself.
static func lane_role(lane: Dictionary) -> String:
	var r := str(lane.get("role", ""))
	return r if r != "" else str(lane.id)


## The layer's name in the grid for a role (or ""), e.g. "kick" -> "Kick".
func lane_key_for_role(role: String) -> String:
	for lane in drum_lanes:
		if lane_role(lane) == role:
			return lane.key
	return ""


## Loudness of one hit (`step` is a grid cell): whatever was drawn for it, else the default
## (a hit on the beat is stronger).
func hit_vel(lane: String, step: int) -> float:
	var v: Dictionary = drum_vel.get(lane, {})
	if v.has(step):
		return float(v[step])
	return HIT_VEL if step % (4 * drum_res) == 0 else HIT_VEL * 0.75


func set_hit_vel(lane: String, step: int, vel: float) -> void:
	if not drum_vel.has(lane):
		drum_vel[lane] = {}
	drum_vel[lane][step] = clampf(vel, 0.1, 1.0)


## Length of the pattern in song steps (16th notes): what the clip repeats.
func pattern_steps() -> int:
	return drum_bars * STEPS_PER_BAR


## Number of cells in the pattern's grid: `pattern_steps()` times the grid detail.
func grid_steps() -> int:
	return pattern_steps() * drum_res


func lane_index(key: String) -> int:
	for i in drum_lanes.size():
		if drum_lanes[i].key == key:
			return i
	return -1


func drum_on(lane: String, step: int) -> bool:
	return step in drum_steps.get(lane, [])


func set_drum(lane: String, step: int, on: bool) -> void:
	var arr: Array = drum_steps.get(lane, [])
	if on and not (step in arr):
		arr.append(step)
	elif not on:
		arr.erase(step)
		if drum_vel.has(lane):
			drum_vel[lane].erase(step)
	drum_steps[lane] = arr


## Pan at a song step: the drawn curve if there is one, else the fixed pan.
## Curve points may use fractional steps (freehand drawing).
func pan_at(step: float) -> float:
	if pan_curve.is_empty():
		return pan
	var prev = null
	for p in pan_curve:
		var t := float(p[0])
		if t >= step:
			if prev == null or is_equal_approx(t, step):
				return float(p[1])
			var f := (step - float(prev[0])) / (t - float(prev[0]))
			return lerpf(float(prev[1]), float(p[1]), f)
		prev = p
	return float(prev[1])


func has_content() -> bool:
	if kind == "audio":
		return audio_path != ""
	if kind == "drums":
		for lane in drum_steps:
			if not drum_steps[lane].is_empty():
				return true
		return false
	return not notes.is_empty()


func to_dict() -> Dictionary:
	var ns := []
	for n in notes:
		var nd := {"start": n.start, "len": n.len, "midi": n.midi, "vel": snappedf(n.vel, 0.001)}
		if n.has("cents"):
			nd["cents"] = snappedf(n.cents, 0.1)
		if n.has("off"):
			nd["off"] = snappedf(n.off, 0.001)
		if n.has("dur"):
			nd["dur"] = snappedf(n.dur, 0.001)
		ns.append(nd)
	return {
		"id": id, "name": name, "kind": kind, "instrument": instrument_id, "preset": preset,
		"muted": muted, "solo": solo, "volume": snappedf(volume, 0.001), "pan": snappedf(pan, 0.001),
		"reverb": snappedf(reverb, 0.001), "pan_curve": pan_curve.duplicate(true), "drum_start": drum_start, "drum_len": drum_len,
		"notes": ns, "drums": drum_steps.duplicate(true), "hum": hum_path,
		"lanes": drum_lanes.duplicate(true), "drum_bars": drum_bars, "drum_res": drum_res, "drum_vel": _vel_dict(),
		"audio": {"path": audio_path, "dur": snappedf(audio_dur, 0.001), "start": audio_start, "trim": snappedf(audio_trim, 0.001), "span": audio_span},
	}


## Drawn hit loudness for saving: only hits that still exist, rounded.
func _vel_dict() -> Dictionary:
	var out := {}
	for lane in drum_vel:
		var m := {}
		for s in drum_vel[lane]:
			if s in drum_steps.get(lane, []):
				m[str(s)] = snappedf(drum_vel[lane][s], 0.01)
		if not m.is_empty():
			out[lane] = m
	return out


static func from_dict(d: Dictionary) -> Track:
	var t := Track.new()
	t.id = int(d.get("id", 0))
	t.name = str(d.get("name", "Track"))
	t.kind = str(d.get("kind", "melodic"))
	t.instrument_id = InstrumentManager.resolve_id(str(d.get("instrument", ""))) if str(d.get("instrument", "")) != "" else ""
	t.preset = int(d.get("preset", 0))
	if t.kind == "melodic" and t.instrument_id == "":
		t.instrument_id = InstrumentManager.resolve_id("grand_piano")
	elif t.kind == "drums" and t.instrument_id == "":
		t.instrument_id = "kick"
	t.muted = bool(d.get("muted", false))
	t.solo = bool(d.get("solo", false))
	t.volume = float(d.get("volume", 0.85))
	t.pan = clampf(float(d.get("pan", 0.0)), -1.0, 1.0)
	t.reverb = clampf(float(d.get("reverb", 0.0)), 0.0, 1.0)
	for p in d.get("pan_curve", []):
		t.pan_curve.append([float(p[0]), clampf(float(p[1]), -1.0, 1.0)])
	t.drum_start = maxi(int(d.get("drum_start", 0)), 0)
	t.drum_len = maxi(int(d.get("drum_len", 0)), 0)
	var au: Dictionary = d.get("audio", {})
	t.audio_path = str(au.get("path", ""))
	t.audio_dur = float(au.get("dur", 0.0))
	t.audio_start = maxi(int(au.get("start", 0)), 0)
	t.audio_trim = maxf(float(au.get("trim", 0.0)), 0.0)
	t.audio_span = maxi(int(au.get("span", 0)), 0)
	t.hum_path = str(d.get("hum", ""))
	t.drum_bars = clampi(int(d.get("drum_bars", 1)), 1, 4)
	t.drum_res = int(d.get("drum_res", 1))
	if not (t.drum_res in [1, 2, 4]):
		t.drum_res = 1
	for l in d.get("lanes", []):
		var lid := InstrumentManager.resolve_id(str(l.get("id", "kick")))
		var ldef := InstrumentManager.get_by_id(lid)
		t.drum_lanes.append({"key": str(l.get("key", "Layer")), "id": lid,
			"midi": int(l.get("midi", ldef.start_midi if ldef else 36)),
			"vol": float(l.get("vol", 0.85)), "mute": bool(l.get("mute", false)), "role": str(l.get("role", ""))})
	if t.kind == "drums" and t.drum_lanes.is_empty():  # projects saved before drum racks existed
		t.drum_lanes = default_drum_lanes()
	for n in d.get("notes", []):
		t.add_note(int(n.get("start", 0)), int(n.get("len", 1)), int(n.get("midi", 60)), float(n.get("vel", 0.8)),
			float(n.get("cents", 0.0)), float(n.get("off", 0.0)), float(n.get("dur", 0.0)))
	var drums: Dictionary = d.get("drums", {})
	for lane in drums:
		var arr := []
		for s in drums[lane]:
			arr.append(int(s))
		t.drum_steps[lane] = arr
	var vels: Dictionary = d.get("drum_vel", {})
	for lane in vels:
		t.drum_vel[lane] = {}
		for s in vels[lane]:
			t.drum_vel[lane][int(s)] = clampf(float(vels[lane][s]), 0.1, 1.0)
	return t
