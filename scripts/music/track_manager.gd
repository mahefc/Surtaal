extends Node
## Autoload: the arrangement (tracks), per-track mixer channels, song length and playback.
##
## There is no fixed song length: it grows with what you record (rounded up to whole
## bars internally), up to MAX_SONG_SEC (10 minutes).
## Mixer: every track has its own audio bus (volume, pan, mute, solo) that feeds the
## shared "Instruments" bus (reverb) and Master.

signal tracks_changed               # tracks added/removed/renamed, mixer settings changed
signal track_changed(track: Track)  # notes or drum pattern edited
signal length_changed               # song length changed
signal only_changed                 # single-track preview started/stopped
signal cursor_changed               # the start marker moved

const MIN_STEPS := 32               # shortest song: 2 bars
const DEFAULT_STEPS := 64           # empty / drums-only song
const MAX_SONG_SEC := 600.0         # 10 minutes
const STARTER_ROLES := {"Kick": "kick", "Snare": "snare", "Hi-hat": "hat"}
const DRUM_STARTERS := {
	"Basic beat": {"Kick": [0, 8, 10], "Snare": [4, 12], "Hi-hat": [0, 2, 4, 6, 8, 10, 12, 14]},
	"Four on the floor": {"Kick": [0, 4, 8, 12], "Snare": [4, 12], "Hi-hat": [2, 6, 10, 14]},
	"Rock drive": {"Kick": [0, 2, 8, 10], "Snare": [4, 12], "Hi-hat": [0, 2, 4, 6, 8, 10, 12, 14]},
	"Half-time": {"Kick": [0, 10], "Snare": [8], "Hi-hat": [0, 2, 4, 6, 8, 10, 12, 14]},
	"Hip-hop": {"Kick": [0, 7, 10], "Snare": [4, 12], "Hi-hat": [0, 2, 4, 6, 8, 10, 12, 14]},
	"Trap": {"Kick": [0, 3, 10], "Snare": [8], "Hi-hat": [0, 2, 4, 6, 8, 10, 11, 12, 14, 15]},
	"Disco": {"Kick": [0, 4, 8, 12], "Snare": [4, 12], "Hi-hat": [2, 6, 10, 14, 15]},
	"Funk": {"Kick": [0, 3, 6, 10], "Snare": [4, 12, 15], "Hi-hat": [0, 2, 4, 6, 8, 10, 12, 14]},
	"Reggae one-drop": {"Kick": [8], "Snare": [8], "Hi-hat": [2, 6, 10, 14]},
	"Breakbeat": {"Kick": [0, 2, 10], "Snare": [4, 12, 15], "Hi-hat": [0, 2, 4, 6, 8, 10, 12, 14]},
	"Drum and bass": {"Kick": [0, 10], "Snare": [4, 12], "Hi-hat": [0, 2, 4, 6, 8, 10, 12, 14]},
	"Dholak groove": {"Kick": [0, 2, 8, 10], "Snare": [4, 6, 12, 14], "Hi-hat": [1, 3, 5, 7, 9, 11, 13, 15]},
	"Bhangra bounce": {"Kick": [0, 3, 8, 11], "Snare": [4, 6, 12, 14], "Hi-hat": [0, 2, 4, 6, 8, 10, 12, 14]},
	"Rock with a fill": {"Kick": [0, 8, 10], "Snare": [4, 12, 13, 14, 15], "Hi-hat": [0, 2, 4, 6, 8, 10, 12, 14]},
}

var tracks: Array[Track] = []
var song_steps := DEFAULT_STEPS
var only: Track = null  # the track being previewed alone, if any
var start_step := 0     # where Play begins: set by tapping the time ruler
var backing_skip: Track = null  # play-along recording: this track is being recorded, the rest play
var _preview_loop := false  # loop builder preview: ignore the clip's start/length
var _audio := {}  # track id -> {player: AudioStreamPlayer, token: int}  (voice clips being played)
var _audio_streams := {}  # path -> AudioStreamWAV
var _first_step := true  # the first step of a play: voice clips already underway start mid-way

var _next_id := 1
var _active: Array[Dictionary] = []  # {id, remaining}


func _ready() -> void:
	tracks_changed.connect(_recalc)
	track_changed.connect(func(_t): _recalc())
	Transport.bpm_changed.connect(_recalc)
	Transport.started.connect(func(): _first_step = true)
	Transport.step_fired.connect(_on_step)
	Transport.stopped.connect(_on_transport_stopped)
	Transport.finished.connect(func(): pass)
	_recalc()


# --------------------------------------------------------- song length
func step_sec() -> float:
	return 60.0 / Transport.bpm / 4.0


func max_steps() -> int:
	return int(MAX_SONG_SEC / step_sec())


func song_seconds() -> float:
	return song_steps * step_sec()


func _recalc() -> void:
	var end := 0
	var melodic := false
	for t in tracks:
		if t.kind == "melodic" and not t.notes.is_empty():
			melodic = true
			end = maxi(end, t.end_step())
	for t in tracks:  # a voice clip ends where its recording (after trimming) ends
		if t.kind == "audio" and t.audio_path != "":
			melodic = true
			end = maxi(end, t.audio_start + audio_clip_steps(t))
	for t in tracks:  # a loop with an explicit length also defines the song length
		if t.kind == "drums" and t.drum_len > 0:
			melodic = true
			end = maxi(end, t.drum_start + t.drum_len)
	var steps := DEFAULT_STEPS
	if melodic:
		steps = maxi(ceili(end / float(Track.STEPS_PER_BAR)) * Track.STEPS_PER_BAR, MIN_STEPS)
	steps = mini(steps, max_steps())
	if steps != song_steps:
		song_steps = steps
		length_changed.emit()
	if only == null:
		Transport.loop_steps = song_steps


static func format_time(seconds: float) -> String:
	var s := int(round(seconds))
	return "%d:%02d" % [s / 60, s % 60]


# ------------------------------------------------------------ editing
func add_track(instrument_id: String, kind: String = "melodic") -> Track:
	var t := Track.new()
	t.id = _next_id
	_next_id += 1
	t.kind = kind
	t.instrument_id = instrument_id if kind == "melodic" else ("" if kind == "audio" else "kick")
	if kind == "audio":
		t.audio_start = start_step
	if kind == "drums":
		t.drum_lanes = Track.default_drum_lanes()
		t.drum_len = 4 * t.pattern_steps()  # a loop clip has a real length: it neither grows nor shrinks by itself
		t.drum_start = start_step
	var mel_def := InstrumentManager.get_or_default(instrument_id) if kind == "melodic" else null
	if kind == "melodic" and mel_def:
		t.instrument_id = mel_def.id
	var base := "Drum loop" if kind == "drums" else ("Voice" if kind == "audio" else (mel_def.display_name if mel_def else "Track"))
	t.name = _unique_name(base)
	if kind == "drums":
		load_drum_starter(t, "Basic beat")
	tracks.append(t)
	_ensure_bus(t)
	apply_mix()
	tracks_changed.emit()
	return t


func remove_track(t: Track) -> void:
	if only == t:
		Transport.stop()
	tracks.erase(t)
	_remove_bus(t)
	apply_mix()
	tracks_changed.emit()


func set_instrument(t: Track, instrument_id: String) -> void:
	var old := InstrumentManager.get_by_id(t.instrument_id)
	var was_default: bool = old != null and t.name.begins_with(old.display_name)
	var neu := InstrumentManager.get_or_default(instrument_id)
	t.instrument_id = neu.id if neu else instrument_id
	t.preset = 0
	apply_mix()  # the chorus that thickens a big-section instrument follows the instrument
	if was_default and neu:  # a default name follows the instrument; a name the user chose stays
		t.name = _unique_name(neu.display_name)
	tracks_changed.emit()


func rename_track(t: Track, new_name: String) -> void:
	var n := new_name.strip_edges()
	if t == null or n == "" or n == t.name:
		return
	var taken := {}
	for other in tracks:
		if other != t:
			taken[other.name] = true
	if taken.has(n):
		var i := 2
		while taken.has("%s %d" % [n, i]):
			i += 1
		n = "%s %d" % [n, i]
	t.name = n
	tracks_changed.emit()
	notify_changed(t)


func notify_changed(t: Track) -> void:
	track_changed.emit(t)


## Steps a voice clip plays for: one pass of the (trimmed) take, or the stretched length when it loops.
func audio_clip_steps(t: Track) -> int:
	if t.audio_span > 0:
		return t.audio_span
	return ceili(t.audio_len_sec() / step_sec())


## Drag a clip's end handle to `end_step`. Shorter: the clip is cut exactly there (instrument clips lose the notes
## after it and a note crossing it is shortened; voice clips keep the first part of the take). Longer: the clip
## repeats itself to fill the space (notes are copied / the take loops). Undo brings the old clip back.
func trim_track(t: Track, end_step: int) -> void:
	if t.kind == "melodic" and not t.notes.is_empty() and end_step > clip_end(t):
		_loop_notes_to(t, end_step)
	if t.kind == "melodic":
		var keep: Array[Dictionary] = []
		for n in t.notes:
			if n.start >= end_step:
				continue
			if n.start + n.len > end_step:
				n.len = end_step - n.start
				if n.has("dur"):
					n.dur = minf(float(n.dur), float(n.len))
			keep.append(n)
		t.notes = keep
	elif t.kind == "audio":
		var secs := maxf((end_step - t.audio_start) * step_sec(), 0.2)
		if secs > t.audio_len_sec() + 0.05:  # longer than the take: it plays again and again
			t.audio_span = end_step - t.audio_start
		else:
			t.audio_span = 0
			t.audio_trim = 0.0 if secs >= t.audio_dur else secs
	_recalc()
	track_changed.emit(t)


## Repeat the tune (whole beats long) after itself until it reaches `end_step`.
func _loop_notes_to(t: Track, end_step: int) -> void:
	var beat := 4
	var clip_start := (t.start_step() / beat) * beat
	var length := maxi(ceili((t.end_step() - clip_start) / float(beat)) * beat, beat)
	var k := 1
	while clip_start + length * k < mini(end_step, max_steps()):
		copy_range(t, clip_start, clip_start + length, length * k)
		k += 1


## Where a clip ends (in steps): the last note, the loop end, or the end of the voice take.
func clip_end(t: Track) -> int:
	if t.kind == "drums":
		return t.drum_start + t.drum_len
	if t.kind == "audio":
		return t.audio_start + audio_clip_steps(t)
	return t.end_step()


## Move a melodic clip in time by `delta` steps (never before 0). Returns the shift actually applied.
func shift_track(t: Track, delta: int) -> int:
	if t.kind == "drums":  # a loop clip: move where it starts in the song
		var ns := clampi(t.drum_start + delta, 0, max_steps() - 1)
		var applied := ns - t.drum_start
		if applied != 0:
			t.drum_start = ns
			track_changed.emit(t)
		return applied
	if t.kind == "audio":
		var ns := clampi(t.audio_start + delta, 0, max_steps() - 1)
		var applied := ns - t.audio_start
		if applied != 0:
			t.audio_start = ns
			track_changed.emit(t)
		return applied
	if t.kind != "melodic" or t.notes.is_empty() or delta == 0:
		return 0
	delta = maxi(delta, -t.start_step())
	delta = mini(delta, max_steps() - t.end_step())
	if delta == 0:
		return 0
	for n in t.notes:
		n.start += delta
	track_changed.emit(t)
	return delta


## Note clipboard (shared by every melodic track). Entries are relative to the anchor note:
## {dstart, dmidi, len, midi, vel, cents?, off?, dur?}.
var note_clip: Array = []


## Notes created by the last paste (so the editor can select them).
var last_pasted: Array = []


func copy_notes(notes_to_copy: Array) -> int:
	note_clip = []
	if notes_to_copy.is_empty():
		return 0
	# The anchor is the earliest note (lowest pitch if several start together). A paste point
	# is where that one note should land; the others keep their distance from it.
	var origin := 1 << 30
	var origin_midi := 127
	for n in notes_to_copy:
		var s := int(n.start)
		if s < origin or (s == origin and int(n.midi) < origin_midi):
			origin = s
			origin_midi = int(n.midi)
	for n in notes_to_copy:
		var e := {
			"dstart": int(n.start) - origin,
			"dmidi": int(n.midi) - origin_midi,
			"len": int(n.len),
			"midi": int(n.midi),
			"vel": float(n.vel),
		}
		for k in ["cents", "off", "dur"]:
			if n.has(k):
				e[k] = n[k]
		note_clip.append(e)
	return note_clip.size()


## Paste the clipboard so the anchor note lands at `at_step`. Pass `at_midi` (>= 0) to land it on
## that pitch too; -1 keeps each note's original pitch. A pasted note replaces any note of the
## same pitch that it lands on. Returns how many notes were pasted.
func paste_notes(t: Track, at_step: int, at_midi: int = -1) -> int:
	last_pasted = []
	var anchor := at_midi
	if anchor >= 0:
		var lo_d := 0
		var hi_d := 0
		for e in note_clip:
			lo_d = mini(lo_d, int(e.get("dmidi", 0)))
			hi_d = maxi(hi_d, int(e.get("dmidi", 0)))
		anchor = clampi(anchor, -lo_d, 127 - hi_d)
	var pasted := 0
	for e in note_clip:
		var s: int = at_step + int(e.dstart)
		if s >= max_steps():
			continue
		var midi := int(e.midi) if anchor < 0 else anchor + int(e.get("dmidi", 0))
		var span := mini(int(e.len), max_steps() - s)
		for old in t.notes.duplicate():
			if old.midi == midi and old.start < s + span and old.start + old.len > s:
				t.remove_note(old)
		last_pasted.append(t.add_note(s, span, midi, float(e.vel), float(e.get("cents", 0.0)), float(e.get("off", 0.0)), float(e.get("dur", 0.0))))
		pasted += 1
	if pasted > 0:
		notify_changed(t)
	return pasted


## Move every note that starts in [from_step, to_step) by the same amount: `dx` steps in time,
## `dy` semitones in pitch. The whole group stops together at the start of the song, the end,
## and MIDI 0..127. Returns how many notes moved (0 if there were none, or they could not move).
func shift_notes(t: Track, from_step: int, to_step: int, dx: int, dy: int) -> int:
	var group: Array = []
	for n in t.notes:
		if int(n.start) >= from_step and int(n.start) < to_step:
			group.append(n)
	return shift_group(t, group, dx, dy)


## Move these notes together by `dx` steps and `dy` semitones. Notes no longer on the track are
## ignored. The group stops together at the start of the song, the end, and MIDI 0..127.
func shift_group(t: Track, notes: Array, dx: int, dy: int) -> int:
	var group: Array = []
	for n in notes:
		for existing in t.notes:
			if is_same(existing, n):
				group.append(n)
				break
	if group.is_empty() or (dx == 0 and dy == 0):
		return 0
	var lo_s := 1 << 30
	var hi_e := 0
	var lo_m := 127
	var hi_m := 0
	for n in group:
		lo_s = mini(lo_s, int(n.start))
		hi_e = maxi(hi_e, int(n.start) + int(n.len))
		lo_m = mini(lo_m, int(n.midi))
		hi_m = maxi(hi_m, int(n.midi))
	dx = clampi(dx, -lo_s, max_steps() - hi_e)
	dy = clampi(dy, -lo_m, 127 - hi_m)
	if dx == 0 and dy == 0:
		return 0
	for n in group:
		n.start = int(n.start) + dx
		n.midi = int(n.midi) + dy
		if dx != 0:
			n.erase("off")
		if dy != 0:
			n.erase("cents")
	notify_changed(t)
	return group.size()


func copy_range(t: Track, from_step: int, to_step: int, offset: int) -> int:
	var added := 0
	var src: Array[Dictionary] = []
	for n in t.notes:
		if n.start >= from_step and n.start < to_step:
			src.append(n)
	for n in src:
		var s: int = n.start + offset
		if s >= max_steps():
			continue
		var same := t.note_at(s, n.midi)
		if not same.is_empty() and same.start == s:
			t.remove_note(same)
		t.add_note(s, mini(n.len, max_steps() - s), n.midi, n.vel)
		added += 1
	if added > 0:
		track_changed.emit(t)
	return added


## Move a track up (-1) or down (+1) in the list.
func move_track(t: Track, delta: int) -> void:
	var i := tracks.find(t)
	var j := clampi(i + delta, 0, tracks.size() - 1)
	if i == -1 or i == j:
		return
	tracks.remove_at(i)
	tracks.insert(j, t)
	tracks_changed.emit()


func duplicate_track(t: Track) -> Track:
	var d := Track.from_dict(t.to_dict())
	d.id = _next_id
	_next_id += 1
	d.name = _unique_name(t.name)
	d.hum_path = ""
	tracks.insert(tracks.find(t) + 1, d)
	_ensure_bus(d)
	apply_mix()
	tracks_changed.emit()
	return d


## Call after changing volume / pan / mute / solo.
func mix_changed(t: Track = null) -> void:
	apply_mix()
	if t:
		track_changed.emit(t)
	else:
		tracks_changed.emit()


func load_drum_starter(t: Track, starter: String) -> void:
	t.drum_steps = {}
	t.drum_vel = {}
	var pat: Dictionary = DRUM_STARTERS.get(starter, {})
	# a starter is one bar of 16th notes: it is spread over the grid's detail (16 / 32 / 64 cells a
	# bar) and repeated if the pattern is longer than a bar
	var res := t.drum_res
	for name in pat:  # starters are written for kick / snare / hi-hat: they go to whatever sound plays that part
		var key := t.lane_key_for_role(STARTER_ROLES[name])
		if key == "":
			continue
		var steps: Array = []
		for off in range(0, t.grid_steps(), Track.STEPS_PER_BAR * res):
			for s in pat[name]:
				steps.append(off + int(s) * res)
		t.drum_steps[key] = steps
	track_changed.emit(t)


## Fill the rack with a fresh random beat (biased by each layer's role). One tap, no menu.
func randomize_drums(t: Track) -> void:
	if t == null or t.kind != "drums":
		return
	t.drum_steps = {}
	t.drum_vel = {}
	var res := t.drum_res
	var total := t.grid_steps()
	for lane in t.drum_lanes:
		var role := Track.lane_role(lane)
		var hits: Array = []
		for s in total:
			var p := 0.12
			match role:
				"kick":
					p = 0.72 if s % (4 * res) == 0 else (0.28 if s % (2 * res) == 0 else 0.08)
				"snare":
					p = 0.7 if s % (8 * res) == 4 * res else (0.18 if s % (4 * res) == 0 else 0.05)
				"hat":
					p = 0.62 if s % (2 * res) == 0 else 0.22
				_:
					p = 0.2 if s % (4 * res) == 0 else 0.1
			if randf() < p:
				hits.append(s)
		# keep at least a little something on known roles so the loop is not empty
		if hits.is_empty() and role in ["kick", "snare", "hat"]:
			hits.append(0 if role != "snare" else mini(4 * res, total - 1))
		t.drum_steps[lane.key] = hits
	track_changed.emit(t)


## Change how finely a bar is divided: 1, 2 or 4 cells per 16th note (16 / 32 / 64 cells in a bar).
## The pattern is still the same length, and every hit stays where it is in the music (a hit
## that falls between the cells of a coarser grid moves to the nearest cell).
func set_drum_res(t: Track, res: int) -> void:
	if not (res in [1, 2, 4]) or res == t.drum_res:
		return
	var old := t.drum_res
	var old_total := t.pattern_steps() * old
	var total := t.pattern_steps() * res
	for key in t.drum_steps.keys():
		var moved: Array = []
		var vels := {}
		for s in t.drum_steps[key]:
			if s >= old_total:
				continue
			var n := clampi(int(roundf(float(s) * res / old)), 0, total - 1)
			if n in moved:
				continue
			moved.append(n)
			if t.drum_vel.get(key, {}).has(s):
				vels[n] = t.drum_vel[key][s]
		t.drum_steps[key] = moved
		if vels.is_empty():
			t.drum_vel.erase(key)
		else:
			t.drum_vel[key] = vels
	t.drum_res = res
	track_changed.emit(t)


## Play one hit of a layer now (to hear what is being drawn or changed).
func audition_drum(t: Track, lane: Dictionary, vel: float = Track.HIT_VEL) -> void:
	var def := InstrumentManager.get_by_id(lane.id)
	if def:
		AudioEngine.note_on(def, lane.midi, minf(1.0, vel * float(lane.vol) / 0.85), 0, bus_of(t))


## Have the sound of every layer ready, so the first hit you draw or play is not late.
func prebake_drums(t: Track) -> void:
	for lane in t.drum_lanes:
		var def := InstrumentManager.get_by_id(lane.id)
		if def:
			SampleManager.prebake(def, [lane.midi], 0, true)


## Beatbox take -> the rack: `steps` is {"kick": [...], "snare": [...], "hat": [...]} (see
## BeatboxAnalyzer.to_steps). The layers playing those parts are replaced; other layers are left
## alone. `vels` ({"kick": {step: loudness}}, optional) keeps how hard each hit was.
## Returns how many hits were placed.
func apply_beatbox(t: Track, steps: Dictionary, vels: Dictionary = {}) -> int:
	var placed := 0
	for kind in ["kick", "snare", "hat"]:
		var key := t.lane_key_for_role(kind)
		if key == "":
			continue
		t.drum_steps[key] = (steps.get(kind, []) as Array).duplicate()
		t.drum_vel.erase(key)
		for s in t.drum_steps[key]:
			var v: Dictionary = vels.get(kind, {})
			if v.has(s):
				t.set_hit_vel(key, s, v[s])
		placed += t.drum_steps[key].size()
	track_changed.emit(t)
	return placed


## Swap the sound of a layer for another instrument. The layer keeps its hits, loudness, volume
## and its part in the beat (so a beatbox or a ready-made loop still reaches it); it takes the
## new instrument's name unless that name is already used by another layer.
func change_drum_lane(t: Track, key: String, instrument_id: String) -> void:
	var i := t.lane_index(key)
	var def := InstrumentManager.get_or_default(instrument_id)
	if i == -1 or def == null or t.kind != "drums":
		return
	var lane: Dictionary = t.drum_lanes[i]
	lane["role"] = Track.lane_role(lane)
	lane.id = def.id
	lane.midi = def.start_midi
	var new_key := def.display_name
	var n := 2
	while t.lane_index(new_key) != -1 and new_key != key:
		new_key = "%s %d" % [def.display_name, n]
		n += 1
	if new_key != key:
		t.drum_steps[new_key] = t.drum_steps.get(key, [])
		t.drum_steps.erase(key)
		if t.drum_vel.has(key):
			t.drum_vel[new_key] = t.drum_vel[key]
			t.drum_vel.erase(key)
		lane.key = new_key
	SampleManager.prebake(def, [def.start_midi], 0, true)
	track_changed.emit(t)


## Add any instrument as a new drum layer.
func add_drum_lane(t: Track, instrument_id: String) -> void:
	var def := InstrumentManager.get_or_default(instrument_id)
	if def == null or t.kind != "drums":
		return
	var key := def.display_name
	var i := 2
	while t.lane_index(key) != -1:
		key = "%s %d" % [def.display_name, i]
		i += 1
	t.drum_lanes.append({"key": key, "id": def.id, "midi": def.start_midi, "vol": 0.85, "mute": false})
	SampleManager.prebake(def, [def.start_midi], 0, true)
	track_changed.emit(t)


func remove_drum_lane(t: Track, key: String) -> void:
	var i := t.lane_index(key)
	if i == -1:
		return
	t.drum_lanes.remove_at(i)
	t.drum_steps.erase(key)
	t.drum_vel.erase(key)
	track_changed.emit(t)


func color_of(t: Track) -> Color:
	if t.kind == "audio":
		return Color("66c2ff")
	var def := InstrumentManager.get_by_id(t.instrument_id)
	return def.color if def else StudioTheme.ACCENT


func _unique_name(base: String) -> String:
	var taken := {}
	for t in tracks:
		taken[t.name] = true
	if not taken.has(base):
		return base
	var i := 2
	while taken.has("%s %d" % [base, i]):
		i += 1
	return "%s %d" % [base, i]


# --------------------------------------------------------------- mixer
func bus_of(t: Track) -> String:
	_ensure_bus(t)
	return "T%d" % t.id


func _ensure_bus(t: Track) -> void:
	var n := "T%d" % t.id
	if AudioServer.get_bus_index(n) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, n)
	AudioServer.set_bus_send(idx, AudioEngine.BUS_INSTRUMENTS)
	AudioServer.add_bus_effect(idx, AudioEffectPanner.new())  # effect 0
	var rv := AudioEffectReverb.new()  # effect 1: this track's own reverb
	rv.room_size = 0.82
	rv.damping = 0.45
	rv.predelay_msec = 35.0
	rv.hipass = 0.15
	rv.spread = 1.0
	rv.dry = 1.0
	rv.wet = 0.0
	AudioServer.add_bus_effect(idx, rv)
	AudioServer.set_bus_effect_enabled(idx, 1, false)  # off until the instrument editor turns reverb on
	var ch := AudioEffectChorus.new()  # effect 2: thickens a section / orchestra (see apply_mix)
	ch.dry = 1.0
	ch.wet = 0.0
	AudioServer.add_bus_effect(idx, ch)
	AudioServer.set_bus_effect_enabled(idx, 2, false)


func _remove_bus(t: Track) -> void:
	var idx := AudioServer.get_bus_index("T%d" % t.id)
	if idx != -1:
		AudioServer.remove_bus(idx)


func _clear_buses() -> void:
	for i in range(AudioServer.bus_count - 1, -1, -1):
		var n := AudioServer.get_bus_name(i)
		if n.length() > 1 and n[0] == "T" and n.substr(1).is_valid_int():
			AudioServer.remove_bus(i)


func any_solo() -> bool:
	for t in tracks:
		if t.solo:
			return true
	return false


## Is this track heard in a normal (whole-song) play?
func audible(t: Track) -> bool:
	if t == backing_skip:
		return false
	if only != null:
		return t == only
	if t.muted:
		return false
	return not any_solo() or t.solo


## The chorus that goes with an ensemble size: more slowly drifting voices, panned apart, as the section grows.
func _set_ensemble_chorus(ch: AudioEffectChorus, bus_idx: int, level: int) -> void:
	AudioServer.set_bus_effect_enabled(bus_idx, 2, level > 0)
	if level <= 0:
		return
	ch.voice_count = clampi(level + 1, 2, 4)
	ch.dry = 1.0
	ch.wet = [0.0, 0.32, 0.42, 0.5][level]
	for i in ch.voice_count:
		var k := i + 1
		ch.set("voice/%d/delay_ms" % k, 11.0 + 4.5 * i)
		ch.set("voice/%d/rate_hz" % k, 0.35 + 0.19 * i)
		ch.set("voice/%d/depth_ms" % k, 1.8 + 0.9 * i)
		ch.set("voice/%d/level_db" % k, -3.0)
		ch.set("voice/%d/cutoff_hz" % k, 12000.0)
		ch.set("voice/%d/pan" % k, [-0.7, 0.7, -0.3, 0.3][i])


func apply_mix() -> void:
	for t in tracks:
		_ensure_bus(t)
		var idx := AudioServer.get_bus_index("T%d" % t.id)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(t.volume, 0.0001) / 0.85))
		var panner := AudioServer.get_bus_effect(idx, 0) as AudioEffectPanner
		if panner:
			panner.pan = t.pan
		var rv := AudioServer.get_bus_effect(idx, 1) as AudioEffectReverb
		if rv:
			rv.wet = clampf(t.reverb, 0.0, 1.0)
			AudioServer.set_bus_effect_enabled(idx, 1, t.reverb > 0.01)  # no cost when it is off
		var chorus := AudioServer.get_bus_effect(idx, 2) as AudioEffectChorus
		if chorus:
			var inst := InstrumentManager.get_by_id(t.instrument_id) if t.kind == "melodic" else null
			_set_ensemble_chorus(chorus, idx, inst.ensemble_level() if inst != null else 0)
		# the track being recorded stays un-muted so you hear your own playing (its old notes are not scheduled)
		AudioServer.set_bus_mute(idx, not (audible(t) or t == backing_skip))


# -------------------------------------------------------- persistence
func export_state() -> Dictionary:
	var arr := []
	for t in tracks:
		arr.append(t.to_dict())
	return {"tracks": arr}


func import_state(d: Dictionary) -> void:
	_clear_buses()
	tracks.clear()
	_next_id = 1
	for td in d.get("tracks", []):
		var t := Track.from_dict(td)
		if t.id <= 0 or t.id >= _next_id:
			_next_id = maxi(_next_id, t.id + 1)
		if t.id <= 0:
			t.id = _next_id
			_next_id += 1
		tracks.append(t)
		_ensure_bus(t)
	var melodic_end := 0
	for t in tracks:
		if t.kind == "melodic":
			melodic_end = maxi(melodic_end, t.end_step())
	for t in tracks:
		if t.kind == "drums" and t.drum_len == 0:
			t.drum_len = maxi(maxi(melodic_end - t.drum_start, 4 * t.pattern_steps()), t.pattern_steps())
	start_step = 0
	apply_mix()
	tracks_changed.emit()
	for t in tracks:
		track_changed.emit(t)


# ------------------------------------------------------------ playback
## Move the start marker (and jump there if the song is playing).
func set_start_step(s: int) -> void:
	start_step = clampi(s, 0, maxi(song_steps - 1, 0))
	cursor_changed.emit()
	if Transport.playing and only == null:
		Transport.seek(start_step)


## Play the song once, starting at the marker.
func play_all() -> void:
	Transport.stop()
	only = null
	apply_mix()
	await prepare()
	Transport.loop = false
	Transport.loop_steps = song_steps
	Transport.start(start_step if start_step < song_steps else 0)


## Play along: while a take is recorded on `skip`, every OTHER track plays (mute / solo respected).
## Step 1 (during the count-in): bake the sounds.  Step 2 (when recording starts): start the song.
func prepare_backing(skip: Track) -> void:
	only = null
	backing_skip = skip
	apply_mix()
	await prepare()


func start_backing(from_step: int) -> void:
	if backing_skip == null:
		return
	Transport.stop()
	only = null
	apply_mix()
	Transport.loop = false
	Transport.loop_steps = maxi(song_steps, from_step + 1)
	Transport.start(from_step)


## Recording is over (or cancelled): stop the backing and let the track be heard again.
func end_backing() -> void:
	if backing_skip == null:
		return
	backing_skip = null
	if Transport.playing:
		Transport.stop()
	apply_mix()


## Is there anything else (besides `skip`) that would play along?
func has_other_content(skip: Track) -> bool:
	for t in tracks:
		if t != skip and t.has_content() and audible(t):
			return true
	return false


## Loop builder: repeat a drum track's pattern endlessly so you can hear it while you edit (tap again to stop).
func loop_preview(t: Track) -> void:
	if only == t and Transport.playing:
		Transport.stop()
		return
	Transport.stop()
	only = t
	only_changed.emit()
	apply_mix()
	await prepare(t)
	if only != t:
		return
	_preview_loop = true
	Transport.loop = true
	Transport.loop_steps = t.pattern_steps()
	Transport.start()


## Play a single track on its own (tap again to stop).
func play_only(t: Track) -> void:
	if only == t and Transport.playing:
		Transport.stop()
		return
	Transport.stop()
	only = t
	only_changed.emit()
	apply_mix()
	await prepare(t)
	if only != t:
		return
	Transport.loop = false
	Transport.loop_steps = song_steps if t.kind == "drums" else maxi(ceili(t.end_step() / 16.0) * 16, 16)
	# Start at this track's own beginning (not the song play marker on the ruler).
	var from := t.drum_start if t.kind == "drums" else (t.audio_start if t.kind == "audio" else t.start_step())
	Transport.start(from if from < Transport.loop_steps else 0)


func _on_transport_stopped() -> void:
	apply_mix()
	_release_all()
	_stop_all_audio()
	_preview_loop = false
	if only != null:
		only = null
		Transport.loop = true
		_recalc()
		apply_mix()
		only_changed.emit()


## Bake (in the background) every note that will be played, then return.
func prepare(just: Track = null) -> void:
	var pending := _needed_samples(just)
	for entry in pending:
		SampleManager.prebake(entry.def, entry.notes, entry.preset, true)
	var guard := 0
	while guard < 1800 and not _all_ready(pending):  # ~30 s safety
		await get_tree().process_frame
		guard += 1


func has_audible_content(just: Track = null) -> bool:
	for t in tracks:
		if (just == null or t == just) and t.has_content() and (just != null or audible(t)):
			return true
	return false


func _needed_samples(just: Track) -> Array:
	var out := []
	for t in tracks:
		if just != null and t != just:
			continue
		if just == null and not audible(t):
			continue
		if t.kind == "drums":
			for lane in t.drum_lanes:
				var def := InstrumentManager.get_by_id(lane.id)
				if def and not lane.mute and not t.drum_steps.get(lane.key, []).is_empty():
					out.append({"def": def, "notes": [lane.midi], "preset": 0})
		else:
			var def := InstrumentManager.get_by_id(t.instrument_id)
			if def == null:
				continue
			var seen := {}
			for n in t.notes:
				seen[n.midi] = true
			if not seen.is_empty():
				out.append({"def": def, "notes": seen.keys(), "preset": t.preset})
	return out


func _all_ready(pending: Array) -> bool:
	for e in pending:
		for m in e.notes:
			if not SampleManager.has_sample(e.def, m, e.preset):
				return false
	return true


## Where the pan drawing is read at a song step. A melodic track's drawing spans the song; a
## drum loop's drawing spans one pattern and repeats with it (so you can hear it in the loop builder).
func pan_step(t: Track, step: int) -> int:
	if t.kind != "drums":
		return step
	var start := 0 if _preview_loop else t.drum_start
	return posmod(step - start, t.pattern_steps())


func _on_step(step: int) -> void:
	for pt in tracks:  # drawn pan automation
		if not pt.pan_curve.is_empty():
			var pi := AudioServer.get_bus_index("T%d" % pt.id)
			var pn := AudioServer.get_bus_effect(pi, 0) as AudioEffectPanner if pi >= 0 else null
			if pn:
				pn.pan = pt.pan_at(pan_step(pt, step))
	for n in _active.duplicate():
		n.remaining -= 1
		if n.remaining <= 0:
			AudioEngine.note_off(n.id)
			_active.erase(n)
	for t in tracks:
		if t.kind == "audio":
			_tick_audio(t, step)
			continue
		if not audible(t):
			continue
		var bus := bus_of(t)
		if t.kind == "drums":
			var gate_start := 0 if _preview_loop else t.drum_start
			if step < gate_start:
				continue
			if not _preview_loop and t.drum_len > 0 and step >= t.drum_start + t.drum_len:
				continue
			var bar_step := (step - gate_start) % t.pattern_steps()
			for lane in t.drum_lanes:
				if lane.mute:
					continue
				for k in t.drum_res:  # a finer grid: the cells inside this 16th note
					var cell := bar_step * t.drum_res + k
					if not t.drum_on(lane.key, cell):
						continue
					var def := InstrumentManager.get_by_id(lane.id)
					if def == null:
						continue
					var vel := minf(1.0, t.hit_vel(lane.key, cell) * float(lane.vol) / 0.85)
					if k == 0:
						AudioEngine.note_on(def, lane.midi, vel, 0, bus)
					else:
						_hit_later(def, lane.midi, vel, bus, float(k) / t.drum_res)
		else:
			var def := InstrumentManager.get_by_id(t.instrument_id)
			if def == null:
				continue
			for n in t.notes_starting_at(step):
				var off: float = n.get("off", 0.0)
				var dur: float = n.get("dur", float(n.len))
				var cents: float = n.get("cents", 0.0)
				if off < 0.02 and absf(dur - n.len) < 0.02:  # on the grid: sample-clock-exact, released on a step
					var id := AudioEngine.note_on(def, n.midi, n.vel, t.preset, bus, cents)
					_active.append({"id": id, "remaining": n.len})
				else:  # a performance with its own timing: start/stop between steps
					_play_timed(def, t, n, bus, off, dur, cents)
	_first_step = false



## A drum hit that falls between two 16th-note steps: play it `frac` of a step late.
func _hit_later(def: InstrumentDef, midi: int, vel: float, bus: String, frac: float) -> void:
	await get_tree().create_timer(frac * step_sec()).timeout
	if Transport.playing:
		AudioEngine.note_on(def, midi, vel, 0, bus)


## A note whose start/length fall between grid steps (voice recordings): start it `off` steps late
## and release it after `dur` steps.
func _play_timed(def: InstrumentDef, t: Track, n: Dictionary, bus: String, off: float, dur: float, cents: float) -> void:
	var sec := step_sec()
	if off > 0.01:
		await get_tree().create_timer(off * sec).timeout
	if not Transport.playing:
		return
	var id := AudioEngine.note_on(def, n.midi, n.vel, t.preset, bus, cents)
	await get_tree().create_timer(maxf(dur, 0.1) * sec).timeout
	AudioEngine.note_off(id)


func _release_all() -> void:
	for n in _active:
		AudioEngine.note_off(n.id)
	_active.clear()


# ---------------------------------------------------- voice clips (audio tracks)
func audio_stream(t: Track) -> AudioStreamWAV:
	if t.audio_path == "":
		return null
	if not _audio_streams.has(t.audio_path):
		_audio_streams[t.audio_path] = RecordingManager.load_wav(t.audio_path)
	return _audio_streams[t.audio_path]


func forget_audio(path: String) -> void:
	_audio_streams.erase(path)


## Rebuild the display waveform of a voice clip from its file.
func ensure_audio_peaks(t: Track) -> void:
	if not t.audio_peaks.is_empty():
		return
	var s := audio_stream(t)
	if s == null:
		return
	var ch := 2 if s.stereo else 1
	var frames := s.data.size() / (2 * ch)
	var win := maxi(int(s.mix_rate * 0.02), 1)
	var out := PackedFloat32Array()
	var i := 0
	while i < frames:
		var pk := 0.0
		var stride := maxi(win / 12, 1)
		var j := i
		while j < mini(i + win, frames):
			pk = maxf(pk, absf(s.data.decode_s16(j * ch * 2)) / 32768.0)
			j += stride
		out.append(pk)
		i += win
	t.audio_peaks = out
	t.audio_dur = float(frames) / s.mix_rate if t.audio_dur <= 0.0 else t.audio_dur


func _tick_audio(t: Track, step: int) -> void:
	if t.audio_path == "" or not audible(t):
		_stop_audio(t)
		return
	var rel := step - t.audio_start
	var sec := rel * step_sec()
	if rel == 0 or (_first_step and rel > 0 and rel < audio_clip_steps(t)):
		_start_audio(t, maxf(sec, 0.0))


func _start_audio(t: Track, offset: float) -> void:
	var stream := audio_stream(t)
	if stream == null:
		return
	var rec: Dictionary = _audio.get(t.id, {})
	var player: AudioStreamPlayer = rec.get("player")
	if player == null:
		player = AudioStreamPlayer.new()
		add_child(player)
		rec = {"player": player, "token": 0}
	rec["token"] = int(rec.token) + 1
	_audio[t.id] = rec
	player.bus = bus_of(t)
	var take := t.audio_len_sec()
	var total := audio_clip_steps(t) * step_sec() if t.audio_span > 0 else take
	if t.audio_span > 0:  # stretched past the take: loop the kept part of it
		var looped := stream.duplicate() as AudioStreamWAV
		looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looped.loop_begin = 0
		looped.loop_end = mini(int(take * looped.mix_rate), looped.data.size() / (4 if looped.stereo else 2))
		player.stream = looped
		player.play(fmod(offset, maxf(take, 0.05)))
	else:
		player.stream = stream
		player.play(offset)
	var token: int = rec.token
	var remain := total - offset
	get_tree().create_timer(maxf(remain, 0.05)).timeout.connect(func():
		var r: Dictionary = _audio.get(t.id, {})
		if int(r.get("token", -1)) == token and r.has("player"):
			(r.player as AudioStreamPlayer).stop())


func _stop_audio(t: Track) -> void:
	var rec: Dictionary = _audio.get(t.id, {})
	if rec.has("player"):
		(rec.player as AudioStreamPlayer).stop()


func _stop_all_audio() -> void:
	for id in _audio:
		(_audio[id].player as AudioStreamPlayer).stop()