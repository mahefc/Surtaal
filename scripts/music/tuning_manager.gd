extends Node
## Autoload: current tuning + Sa (root). Not forced into 12-TET: each preset gives
## the exact cents of the 12 scale degrees above Sa (just intonation / raga shruti),
## and a scale mask used for highlighting. Samples are baked at 12-TET; the engine
## retunes with pitch_scale by offset_cents().

signal changed

const J := [0.0, 111.73, 203.91, 315.64, 386.31, 498.04, 590.22, 701.96, 813.69, 884.36, 996.09, 1088.27]
const ET := [0.0, 100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0, 1000.0, 1100.0]
const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

## name, cents of degrees 0..11 above Sa, scale degrees (semitone steps above Sa)
const PRESETS := [
	{"name": "12-TET Chromatic", "cents": ET, "scale": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]},
	{"name": "12-TET Major", "cents": ET, "scale": [0, 2, 4, 5, 7, 9, 11]},
	{"name": "12-TET Minor", "cents": ET, "scale": [0, 2, 3, 5, 7, 8, 10]},
	{"name": "Just Intonation", "cents": J, "scale": [0, 2, 4, 5, 7, 9, 11]},
	{"name": "Raga Bhairav", "cents": J, "scale": [0, 1, 4, 5, 7, 8, 11]},
	{"name": "Raga Yaman", "cents": J, "scale": [0, 2, 4, 6, 7, 9, 11]},
	{"name": "Raga Bhairavi", "cents": J, "scale": [0, 1, 3, 5, 7, 8, 10]},
	{"name": "Raga Kafi", "cents": J, "scale": [0, 2, 3, 5, 7, 9, 10]},
	{"name": "Chinese Gong (pentatonic)", "cents": J, "scale": [0, 2, 4, 7, 9]},
	{"name": "Chinese Yu (pentatonic)", "cents": J, "scale": [0, 3, 5, 7, 10]},
]

var tuning_index := 0
var root_pc := 0  # Sa as a pitch class, 0 = C


func names() -> PackedStringArray:
	var out := PackedStringArray()
	for p in PRESETS:
		out.append(p.name)
	return out


func set_tuning(i: int) -> void:
	tuning_index = clampi(i, 0, PRESETS.size() - 1)
	changed.emit()


func set_root(pc: int) -> void:
	root_pc = posmod(pc, 12)
	changed.emit()


## Deviation in cents from 12-TET for this MIDI note under the current tuning.
func offset_cents(midi: int) -> float:
	var deg := posmod(midi - root_pc, 12)
	var cents: Array = PRESETS[tuning_index].cents
	return float(cents[deg]) - 100.0 * deg


func in_scale(midi: int) -> bool:
	return posmod(midi - root_pc, 12) in PRESETS[tuning_index].scale


func is_root(midi: int) -> bool:
	return posmod(midi - root_pc, 12) == 0


## Actual frequency of a note in the current tuning (for display/analysis).
func frequency(midi: int) -> float:
	return SynthBaker.midi_to_freq(midi + offset_cents(midi) / 100.0)
