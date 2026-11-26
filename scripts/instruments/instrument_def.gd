class_name InstrumentDef
extends Resource
## Data-driven description of one instrument. Loaded from data/instruments/*.json.

@export var id: String = ""
@export var display_name: String = ""
@export var category: String = ""
@export var family: String = ""
@export var synth: String = ""  # "pluck" | "wavetable" | "membrane"
@export var color: Color = Color.WHITE
@export var start_midi: int = 60
@export var range_lo: int = 36
@export var range_hi: int = 96
@export var description: String = ""
@export var params: Dictionary = {}
## Sample zone width in semitones: only every Nth note is rendered, neighbours are repitched.
@export var zone: int = 1


static func from_dict(d: Dictionary) -> InstrumentDef:
	var def := InstrumentDef.new()
	def.id = str(d.get("id", ""))
	def.display_name = str(d.get("name", def.id))
	def.category = str(d.get("category", "Other"))
	def.family = str(d.get("family", ""))
	def.synth = str(d.get("synth", ""))
	def.color = Color.html(str(d.get("color", "#7c5cff")))
	def.start_midi = int(d.get("start_midi", 60))
	var r: Array = d.get("range", [36, 96])
	def.range_lo = int(r[0])
	def.range_hi = int(r[1])
	def.description = str(d.get("description", ""))
	def.params = d.get("params", {})
	def.zone = maxi(1, int(d.get("zone", 1)))
	return def


## Preset overrides: [{name, params}]. Index 0 of the UI list is always "Default".
var presets: Array = []
var active_preset: int = 0


func preset_names() -> PackedStringArray:
	var out := PackedStringArray(["Default"])
	for p in presets:
		out.append(str(p.get("name", "Preset")))
	return out


## Synth parameters with the given preset (0 = default) merged on top.
func params_for(preset: int) -> Dictionary:
	var p := params.duplicate(true)
	if preset > 0 and preset - 1 < presets.size():
		p.merge(presets[preset - 1].get("params", {}), true)
	return p


## Sustaining wavetable voices are baked as seamless loops (hold-to-sustain).
func is_loopable(preset: int = 0) -> bool:
	if synth == "sampler":
		return bool(params.get("loop", false))
	return (synth == "wavetable" or synth == "super") and float(params_for(preset).get("sustain", 0.0)) >= 0.3


## Unpitched recorded hits (drums, cymbals): played at their natural pitch whatever the key.
func is_fixed_pitch() -> bool:
	return synth == "sampler" and bool(params.get("fixed", false))


var _roots_by_layer := {}  # velocity layer -> sorted PackedInt32Array of recorded notes
var _layer_count := -1


## How many velocity layers the recordings have (soft to loud takes of the same note). Most instruments: 1.
func velocity_layers() -> int:
	if _layer_count < 0:
		_layer_count = 1
		for s in params.get("samples", []):
			_layer_count = maxi(_layer_count, int(s.get("vel", 0)) + 1)
	return _layer_count


## The velocity layer a note of this velocity plays: soft notes take the soft recordings.
func layer_for_velocity(v: float) -> int:
	var n := velocity_layers()
	if n <= 1:
		return 0
	return clampi(int(floor(clampf(v, 0.0, 1.0) * n)), 0, n - 1)


func _sampler_roots(layer: int = 0) -> PackedInt32Array:
	if not _roots_by_layer.has(layer):
		var roots := PackedInt32Array()
		for s in params.get("samples", []):
			if int(s.get("vel", 0)) == layer:
				roots.append(int(s.midi))
		roots.sort()
		if roots.is_empty() and layer != 0:  # no take at this layer: fall back to layer 0
			return _sampler_roots(0)
		_roots_by_layer[layer] = roots
	return _roots_by_layer[layer]


## The rendered (root) note that stands in for `midi` in this instrument's zone layout.
func zone_root(midi: int, layer: int = 0) -> int:
	if synth == "sampler":  # nearest recorded note in this velocity layer
		var roots := _sampler_roots(layer)
		if roots.is_empty():
			return midi
		if is_fixed_pitch():
			return roots[0]
		var best := roots[0]
		for r in roots:
			if absi(r - midi) < absi(best - midi):
				best = r
		return best
	if zone <= 1:
		return midi
	return clampi(int(round(float(midi) / zone)) * zone, 0, 127)


## A layered instrument plays several other instruments at once (e.g. violins + cellos + basses).
## params.layers = [{id, shift (semitones), gain (0..1)}]
func is_layered() -> bool:
	return synth == "layered"


## How big a section this instrument sounds like (params.ensemble: 0 = one player, 1 = ~10, 2 = ~20, 3 = ~30):
## every note is doubled by quieter, slightly detuned and late copies, and the track bus adds a chorus.
func ensemble_level() -> int:
	return clampi(int(params.get("ensemble", 0)), 0, 3)


## Unpitched hits and drum-kit pieces belong to the loop builder only, not the instrument picker.
func is_loop_only() -> bool:
	return is_fixed_pitch() or category == "Drums"


func is_percussive() -> bool:
	return synth == "membrane"
