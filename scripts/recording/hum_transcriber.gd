class_name HumTranscriber
extends RefCounted
## Turns a recorded hum/whistle/sung line into notes:
##   audio -> PitchTracker (f0 per 15 ms) -> segmentation -> clean-up -> quantised notes.
## This is pitch-to-MIDI transcription, not timbre conversion: the notes are then
## performed by whichever instrument the track uses.
##
## Built for real (imperfect) singing:
##  - a note only splits on a SUSTAINED pitch change, so wide vibrato stays one note
##  - slides ("scoops") into or out of a note are absorbed into it
##  - short octave-error glitches are repaired
##  - each note's pitch is the median of its stable middle, not its onset/tail
##  - the take's overall tuning offset (a singer who is consistently flat/sharp) is removed
##  - re-articulated repeats ("la la la") split on the energy dip

const MIN_NOTE_SEC := 0.09
const REF_FRAMES := 16            # long reference window: > one vibrato cycle
const SPLIT_SEMITONES := 0.7      # deviation that counts as "moving to another note"
const MAX_GAP_FRAMES := 2         # unvoiced frames bridged inside one note
const RETRIGGER_DIP := 0.55       # energy fell below this fraction of the peak...
const RETRIGGER_REBOUND := 1.6    # ...then rose again by this factor = new syllable
const SCOOP_MAX_SEC := 0.09       # a short segment this brief next to a note is a slide
const SCOOP_MAX_SEMITONES := 1.3
const GLITCH_MAX_SEC := 0.20      # octave glitches shorter than this are repaired
const LEAD_SCOOP_MAX_SEC := 0.2   # a slide into the first note of a phrase can be this long...
const LEAD_SCOOP_MAX_SEMITONES := 3.6  # ...and start this far below/above it


## Heavy (runs on a worker thread). Returns [{t0, t1, midi (float), level}].
static func transcribe(samples: PackedFloat32Array, rate: int) -> Array[Dictionary]:
	return segment(PitchTracker.track(samples, rate))


static func segment(tr: Dictionary) -> Array[Dictionary]:
	var f0: PackedFloat32Array = tr.f0
	var rms: PackedFloat32Array = tr.rms
	var hop: float = tr.hop_sec
	var n := f0.size()
	var midi := contour_midi(tr)

	var peak_level := 0.0001
	for r in rms:
		peak_level = maxf(peak_level, r)

	var notes: Array[Dictionary] = []
	var seg := {}
	var gap := 0
	for i in n:
		if midi[i] < 0.0:
			if not seg.is_empty():
				gap += 1
				if gap > MAX_GAP_FRAMES:
					_close(seg, hop, peak_level, notes)
					seg = {}
			continue
		gap = 0
		if seg.is_empty():
			seg = _new_seg(i, "start")
			_extend(seg, i, midi[i], rms[i], 0)
			continue
		var ref := _median(seg.vals.slice(maxi(0, seg.vals.size() - REF_FRAMES)))
		var dev := midi[i] - ref
		var flag := 0
		if absf(dev) > SPLIT_SEMITONES:
			flag = 1 if dev > 0.0 else -1
		_extend(seg, i, midi[i], rms[i], flag)

		# Pitch change: 3 of the last 4 frames beyond the threshold, same direction, and agreeing.
		var k := _sustained_shift(seg)
		if k > 0:
			var moved := _split_tail(seg, k)
			_close(seg, hop, peak_level, notes)
			seg = moved
			seg.reason = "pitch"
			continue
		# Same pitch, but energy dipped and rebounded: a re-articulated note.
		if seg.vals.size() >= 3 and rms[i] > seg.valley * RETRIGGER_REBOUND \
				and seg.valley < seg.peak * RETRIGGER_DIP and rms[i] > seg.peak * 0.6:
			var moved := _split_tail(seg, 1)
			_close(seg, hop, peak_level, notes)
			seg = moved
			seg.reason = "energy"
	if not seg.is_empty():
		_close(seg, hop, peak_level, notes)

	notes = _absorb_slides(notes, hop)
	notes = _fix_octave_glitches(notes)
	notes = _merge_spurious_splits(notes, hop)
	notes = _drop_isolated_blips(notes)
	var kept: Array[Dictionary] = []
	for nt in notes:
		if nt.t1 - nt.t0 >= MIN_NOTE_SEC:
			kept.append(nt)
	_remove_take_offset(kept)
	return kept


# ----------------------------------------------------------- segments
## Per-frame pitch in (fractional) MIDI notes, -1 = unvoiced, with tracker mistakes repaired:
##  - a frame an octave away from its neighbours is folded back (octave error)
##  - a frame that disagrees with BOTH the notes before and after it is an isolated blip: dropped
## A real leap is never touched, because the frames after it agree with each other.
static func contour_midi(tr: Dictionary) -> PackedFloat32Array:
	var f0: PackedFloat32Array = tr.f0
	var n := f0.size()
	var midi := PackedFloat32Array()
	midi.resize(n)
	for i in n:
		midi[i] = 69.0 + 12.0 * log(f0[i] / 440.0) / log(2.0) if f0[i] > 0.0 else -1.0
	var out := midi.duplicate()
	for i in n:
		if midi[i] < 0.0:
			continue
		var before := _voiced_neighbours(midi, i, -1, 6, 14)
		var after := _voiced_neighbours(midi, i, 1, 6, 14)
		if before.size() < 3 or after.size() < 3:
			continue
		var mb := _median(before)
		var ma := _median(after)
		var db := midi[i] - mb
		var da := midi[i] - ma
		if absf(db) > 4.0 and absf(da) > 4.0:
			var k := roundi(db / 12.0)
			var folded := midi[i] - 12.0 * k
			if k != 0 and absf(folded - mb) < 1.8 and absf(folded - ma) < 1.8 + absf(mb - ma):
				out[i] = folded  # octave error
			else:
				out[i] = -1.0  # isolated blip
	return out


static func _voiced_neighbours(midi: PackedFloat32Array, i: int, dir: int, want: int, reach: int) -> Array:
	var out := []
	var j := i + dir
	var steps := 0
	while j >= 0 and j < midi.size() and out.size() < want and steps < reach:
		if midi[j] >= 0.0:
			out.append(midi[j])
		j += dir
		steps += 1
	return out

static func _new_seg(start: int, reason: String) -> Dictionary:
	return {"start": start, "last": start - 1, "vals": [], "rms": [], "flags": [],
		"peak": 0.0, "valley": INF, "reason": reason}


static func _extend(seg: Dictionary, i: int, m: float, r: float, flag: int) -> void:
	seg.last = i
	seg.vals.append(m)
	seg.rms.append(r)
	seg.flags.append(flag)
	if r > seg.peak:
		seg.peak = r
		seg.valley = r
	else:
		seg.valley = minf(seg.valley, r)


## If the last frames show a sustained move to a new pitch, return how many trailing
## frames belong to the new note (0 = no split).
static func _sustained_shift(seg: Dictionary) -> int:
	var cnt: int = seg.flags.size()
	if cnt < 5:
		return 0
	var window: Array = seg.flags.slice(cnt - 4)
	for sign in [1, -1]:
		var hits := 0
		var first := -1
		for j in 4:
			if window[j] == sign:
				hits += 1
				if first < 0:
					first = j
		if hits >= 3:
			var lo := INF
			var hi := -INF
			for j in range(first, 4):
				if window[j] == sign:
					lo = minf(lo, seg.vals[cnt - 4 + j])
					hi = maxf(hi, seg.vals[cnt - 4 + j])
			if hi - lo < 0.8:  # the new pitch is steady, not just wobble
				return 4 - first
	return 0


## Move the last k frames out of `seg` into a fresh segment (returned).
static func _split_tail(seg: Dictionary, k: int) -> Dictionary:
	var cnt: int = seg.vals.size()
	k = mini(k, cnt - 1)
	var moved := _new_seg(int(seg.last) - k + 1, "split")
	for j in range(cnt - k, cnt):
		_extend(moved, int(seg.start) + j, seg.vals[j], seg.rms[j], 0)
	seg.vals = seg.vals.slice(0, cnt - k)
	seg.rms = seg.rms.slice(0, cnt - k)
	seg.flags = seg.flags.slice(0, cnt - k)
	seg.last = int(seg.last) - k
	return moved


static func _close(seg: Dictionary, hop: float, peak_level: float, out: Array[Dictionary]) -> void:
	var cnt: int = seg.vals.size()
	if cnt < 2:
		return
	var level := 0.0
	for r in seg.rms:
		level += r
	level /= cnt
	# Pitch from the stable middle: ignore onset scoops and tail fall-offs.
	var vals: Array = seg.vals
	if cnt >= 8:
		var cut := int(cnt * 0.2)
		vals = seg.vals.slice(cut, cnt - cut)
	out.append({
		"t0": seg.start * hop, "t1": (seg.last + 1) * hop, "midi": _median(vals),
		"level": clampf(level / peak_level, 0.0, 1.0), "reason": seg.reason,
	})


static func _median(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


# ----------------------------------------------------------- clean-up
## A very short segment touching a note is a slide into/out of it: absorb it.
static func _absorb_slides(notes: Array[Dictionary], hop: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	while i < notes.size():
		var n: Dictionary = notes[i]
		var short: bool = n.t1 - n.t0 < SCOOP_MAX_SEC
		# A phrase usually starts with a slide up into the first real note ("scoop"): a short
		# segment that follows silence and leads into a clearly longer note belongs to that note.
		if i + 1 < notes.size() and n.t1 - n.t0 < LEAD_SCOOP_MAX_SEC and (out.is_empty() or n.t0 - out[-1].t1 > 0.08):
			var lead: Dictionary = notes[i + 1]
			if lead.t0 - n.t1 <= hop * 3.0 and absf(lead.midi - n.midi) <= LEAD_SCOOP_MAX_SEMITONES \
					and (lead.t1 - lead.t0) > 1.8 * (n.t1 - n.t0):
				lead.t0 = n.t0
				i += 1
				continue
		if short and i + 1 < notes.size():
			var nxt: Dictionary = notes[i + 1]
			if nxt.t0 - n.t1 <= hop * 3.0 and absf(nxt.midi - n.midi) <= SCOOP_MAX_SEMITONES \
					and nxt.t1 - nxt.t0 > n.t1 - n.t0:
				nxt.t0 = n.t0  # slide into the next note
				i += 1
				continue
		if short and not out.is_empty():
			var prev: Dictionary = out[-1]
			if n.t0 - prev.t1 <= hop * 3.0 and absf(prev.midi - n.midi) <= SCOOP_MAX_SEMITONES \
					and prev.t1 - prev.t0 > n.t1 - n.t0:
				prev.t1 = n.t1  # fall-off at the end of the previous note
				i += 1
				continue
		out.append(n)
		i += 1
	return out


## Short notes an octave away from their neighbours are pitch-tracker errors.
static func _fix_octave_glitches(notes: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	while i < notes.size():
		var n: Dictionary = notes[i]
		if n.t1 - n.t0 < GLITCH_MAX_SEC:
			var prev: Dictionary = out[-1] if not out.is_empty() else {}
			var nxt: Dictionary = notes[i + 1] if i + 1 < notes.size() else {}
			var dur: float = n.t1 - n.t0
			# only a LONGER neighbour can show that this note is the glitch
			var near_prev: bool = not prev.is_empty() and _is_octave(n.midi, prev.midi) and prev.t1 - prev.t0 > dur
			var near_next: bool = not nxt.is_empty() and _is_octave(n.midi, nxt.midi) and nxt.t1 - nxt.t0 > dur
			if near_prev and near_next and absf(prev.midi - nxt.midi) < 1.5:
				prev.t1 = nxt.t1  # prev + glitch + next were one note
				prev.midi = (prev.midi + nxt.midi) * 0.5
				i += 2
				continue
			if near_prev or near_next:
				if near_prev:
					prev.t1 = n.t1
				else:
					nxt.t0 = n.t0
				i += 1
				continue
		out.append(n)
		i += 1
	return out


## A very short note that is far from BOTH its neighbours (and they are close to each other) is a tracking blip.
static func _drop_isolated_blips(notes: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in notes.size():
		var n: Dictionary = notes[i]
		if n.t1 - n.t0 < 0.12 and i > 0 and i + 1 < notes.size():
			var p: Dictionary = notes[i - 1]
			var q: Dictionary = notes[i + 1]
			if n.t0 - p.t1 < 0.2 and q.t0 - n.t1 < 0.2 and absf(n.midi - p.midi) >= 3.0 and absf(n.midi - q.midi) >= 3.0 \
					and absf(p.midi - q.midi) < 2.5:
				continue
		out.append(n)
	return out


static func _is_octave(a: float, b: float) -> bool:
	return absf(absf(a - b) - 12.0) < 0.8


## Splits caused by wobble rather than a new note (same pitch, touching, not a re-articulation).
static func _merge_spurious_splits(notes: Array[Dictionary], hop: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in notes:
		if not out.is_empty():
			var prev: Dictionary = out[-1]
			if n.reason != "energy" and n.t0 - prev.t1 <= hop * 1.5 and round(n.midi) == round(prev.midi):
				prev.t1 = n.t1
				continue
		out.append(n)
	return out


## Singers are often consistently flat/sharp. Estimate the common offset from the
## semitone grid (circular mean, duration-weighted) and remove it when it is clear.
static func _remove_take_offset(notes: Array[Dictionary]) -> void:
	if notes.size() < 3:
		return
	var sx := 0.0
	var sy := 0.0
	var wsum := 0.0
	for n in notes:
		var w: float = n.t1 - n.t0
		var ang: float = TAU * (n.midi - round(n.midi))
		sx += w * cos(ang)
		sy += w * sin(ang)
		wsum += w
	var r := sqrt(sx * sx + sy * sy) / maxf(wsum, 1e-6)
	var offset := atan2(sy, sx) / TAU
	if r > 0.75 and absf(offset) > 0.06:
		for n in notes:
			n.midi -= offset


# ------------------------------------------------------- quantising
## Best-fitting tempo for the detected onsets (so a singer who hums at their own speed
## still lands on the grid). Returns `current_bpm` unless the improvement is clear.
static func estimate_bpm(notes: Array, current_bpm: float) -> float:
	if notes.size() < 5:
		return current_bpm
	var t_first: float = notes[0].t0
	var best_bpm := current_bpm
	var best := INF
	var cur_err := _grid_error(notes, t_first, current_bpm)
	for i in range(0, 201):
		var bpm := 60.0 + i * 0.5
		var score := _grid_error(notes, t_first, bpm) + 0.0006 * absf(bpm - 100.0)
		if score < best:
			best = score
			best_bpm = bpm
	var best_err := _grid_error(notes, t_first, best_bpm)
	if best_err < 0.12 and cur_err - best_err > 0.06:
		return roundf(best_bpm)
	return current_bpm


## Mean distance of onsets from an eighth-note grid, in grid units (random = 0.25).
static func _grid_error(notes: Array, t_first: float, bpm: float) -> float:
	var g := 60.0 / bpm / 2.0
	var e := 0.0
	for n in notes:
		var x: float = (n.t0 - t_first) / g
		e += absf(x - round(x))
	return e / notes.size()


## Place detected notes on the song's 16th-note grid, KEEPING the exact performance:
##   start/len/midi : the grid position (start is the step the note begins in, midi the nearest key)
##   off            : how far into that step it really begins (0..1)
##   dur            : its exact length in steps
##   cents          : how far from the key it was actually sung (-50..50) - the instrument plays it as sung
##   base_step  - song step where the recording started
##   latency    - seconds to shift notes earlier (output+input latency)
##   in_scale   - optional Callable(midi) -> bool; if valid, pitches snap to the scale (cents = 0)
## Monophonic: overlapping notes are trimmed so the line stays clean.
static func to_track_notes(notes: Array, bpm: float, base_step: int, latency: float, in_scale: Callable = Callable()) -> Array[Dictionary]:
	var step_sec := 60.0 / bpm / 4.0
	var out: Array[Dictionary] = []
	for n in notes:
		var exact: float = n.midi
		var pitch := int(round(exact))
		var cents := (exact - pitch) * 100.0
		if in_scale.is_valid():
			pitch = _snap(pitch, in_scale)
			cents = 0.0
		var pos := maxf(base_step + (n.t0 - latency) / step_sec, float(base_step))
		var start := int(floor(pos))
		var dur_steps := maxf((n.t1 - n.t0) / step_sec, 0.25)
		out.append({"start": start, "off": pos - start, "len": maxi(1, int(round(dur_steps))), "dur": dur_steps,
			"midi": clampi(pitch, 0, 127), "cents": clampf(cents, -50.0, 50.0),
			"vel": clampf(0.45 + 0.55 * n.level, 0.4, 1.0)})
	out.sort_custom(func(a, b): return a.start + a.off < b.start + b.off)
	var clean: Array[Dictionary] = []
	for n in out:
		if not clean.is_empty():
			var prev: Dictionary = clean[-1]
			var p_pos: float = prev.start + prev.off
			var n_pos: float = n.start + n.off
			if n_pos - p_pos < 0.25:  # practically the same moment: keep the longer
				if n.dur > prev.dur:
					clean[-1] = n
				continue
			if n_pos < p_pos + prev.dur:  # trim the previous note so they do not overlap
				prev.dur = n_pos - p_pos
				prev.len = maxi(1, int(round(prev.dur)))
		clean.append(n)
	return clean

static func _snap(midi: int, in_scale: Callable) -> int:
	for d in [0, 1, -1, 2, -2, 3, -3]:
		if in_scale.call(midi + d):
			return midi + d
	return midi
