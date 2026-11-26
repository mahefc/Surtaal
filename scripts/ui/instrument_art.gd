class_name InstrumentArt
extends Control
## A small picture of an instrument (violin, flute, drum, keys...) drawn in code, so it is
## crisp at any size and tinted with the instrument's colour. Used on the instrument cards
## and on the track rows.

var kind := "note":
	set(v):
		kind = v
		queue_redraw()
var tint := Color.WHITE:
	set(v):
		tint = v
		queue_redraw()
var disc := true  # sit on a soft tinted circle


## Which picture suits an instrument (by id, then family, then how it is made).
static func kind_of(def: InstrumentDef) -> String:
	if def == null:
		return "note"
	var id := def.id
	var fam := def.family.to_lower()
	var tokens := {
		"keys": ["harpsichord", "clavi", "piano", "harmonium"],  # first: "harpsichord" contains "harp"
		"violin": ["violin", "viola", "cello", "contrabass", "strings", "ostinato", "erhu"],
		"guitar": ["guitar", "sitar", "tanpura"],
		"harp": ["harp"],
		"zither": ["guzheng", "tranh", "zither"],
		"flute": ["flute", "bansuri", "dizi", "ocarina", "recorder"],
		"reed": ["oboe", "clarinet", "bassoon", "shehnai", "nadaswaram", "harmonica", "sax"],
		"horn": ["horn", "trumpet", "tuba", "trombone", "brass", "braam"],
		"organ": ["organ"],
		"mallet": ["marimba", "xylophone", "glock", "kalimba", "balafon", "vibraphone"],
		"frame": ["parai", "kanjira", "frame_drum", "tambourine"],
		"pot": ["ghatam"],
		"gong": ["gong", "agogo"],
		"cymbal": ["cymbal", "hat"],
		"choir": ["choir"],
		"burst": ["epic_hit", "trailer_hit"],
		"drum": ["tabla", "dhol", "thavil", "mridangam", "taiko", "kick", "snare", "bassdrum", "conga", "darbuka", "cajon", "bongo", "woodblock"],
		"synth": ["synth", "pad", "lead", "bass808"],
	}
	for k in tokens:
		for t in tokens[k]:
			if id.contains(t):
				return k
	if fam.contains("drum"):
		return "drum"
	if fam.contains("string") or fam.contains("fiddle"):
		return "violin"
	if fam.contains("synth") or fam.contains("pad"):
		return "synth"
	match def.synth:
		"pluck":
			return "guitar"
		"membrane":
			return "drum"
		"wavetable", "super":
			return "synth"
	return "note"


## A ready-made picture for an instrument at `px` pixels.
static func make(def: InstrumentDef, px: float) -> InstrumentArt:
	var a := InstrumentArt.new()
	a.kind = kind_of(def)
	a.tint = def.color if def else Color.WHITE
	a.custom_minimum_size = Vector2(px, px)
	return a


func _init() -> void:
	custom_minimum_size = Vector2(36, 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	if disc:
		draw_circle(c, r, Color(tint, 0.18))
		draw_arc(c, r - 0.75, 0.0, TAU, 40, Color(tint, 0.5), 1.2, true)
	paint(self, kind, c, r * (0.58 if disc else 0.9), tint)


## Draw a picture inside the square of half-size `r` centred on `c` (call from _draw).
static func paint(cv: CanvasItem, what: String, c: Vector2, r: float, col: Color) -> void:
	var w := maxf(1.6, r * 0.14)
	var dark := Color("11141a")
	match what:
		"keys":
			var box := Rect2(c - Vector2(r, r * 0.75), Vector2(r * 2.0, r * 1.5))
			cv.draw_rect(box, col, false, w)
			for x in [-0.5, 0.0, 0.5]:
				cv.draw_line(c + Vector2(r * x, -r * 0.75), c + Vector2(r * x, r * 0.75), col, w * 0.6, true)
			for x in [-0.5, 0.0]:
				cv.draw_rect(Rect2(c + Vector2(r * x - r * 0.14, -r * 0.75), Vector2(r * 0.28, r * 0.85)), col)
		"violin":
			cv.draw_circle(c + Vector2(0, -r * 0.1), r * 0.34, col)
			cv.draw_circle(c + Vector2(0, r * 0.45), r * 0.46, col)
			cv.draw_rect(Rect2(c + Vector2(-r * 0.2, -r * 0.1), Vector2(r * 0.4, r * 0.55)), col)
			cv.draw_line(c + Vector2(0, -r * 0.35), c + Vector2(0, -r * 0.98), col, w * 1.4, true)
			cv.draw_circle(c + Vector2(0, -r * 1.0), r * 0.1, col)
			cv.draw_line(c + Vector2(-r * 0.12, r * 0.25), c + Vector2(-r * 0.12, r * 0.55), dark, w * 0.7, true)
			cv.draw_line(c + Vector2(r * 0.12, r * 0.25), c + Vector2(r * 0.12, r * 0.55), dark, w * 0.7, true)
			cv.draw_line(c + Vector2(-r * 0.95, r * 0.75), c + Vector2(r * 0.9, -r * 0.35), col, w * 0.8, true)
		"guitar":
			cv.draw_circle(c + Vector2(0, r * 0.5), r * 0.48, col)
			cv.draw_circle(c + Vector2(0, r * 0.0), r * 0.34, col)
			cv.draw_line(c + Vector2(0, -r * 0.2), c + Vector2(0, -r * 0.95), col, w * 1.7, true)
			cv.draw_rect(Rect2(c + Vector2(-r * 0.16, -r * 1.05), Vector2(r * 0.32, r * 0.25)), col)
			cv.draw_circle(c + Vector2(0, r * 0.42), r * 0.15, dark)
		"harp":
			cv.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.7, r * 0.9), c + Vector2(-r * 0.7, -r * 0.9),
				c + Vector2(r * 0.7, -r * 0.25), c + Vector2(r * 0.7, r * 0.9)]), col, w * 1.3, true)
			for t in [0.25, 0.5, 0.75]:
				var x := lerpf(-0.7, 0.7, t)
				cv.draw_line(c + Vector2(r * x, lerpf(-0.9, -0.25, t) * r + r * 0.12), c + Vector2(r * x, r * 0.8), col, w * 0.6, true)
		"flute":
			var a := c + Vector2(-r * 0.95, r * 0.5)
			var b := c + Vector2(r * 0.95, -r * 0.5)
			cv.draw_line(a, b, col, r * 0.3, true)
			for t in [0.3, 0.45, 0.6, 0.75]:
				cv.draw_circle(a.lerp(b, t), r * 0.06, dark)
		"reed":
			cv.draw_line(c + Vector2(0, -r * 0.98), c + Vector2(0, -r * 0.75), col, w * 0.9, true)
			cv.draw_line(c + Vector2(0, -r * 0.75), c + Vector2(0, r * 0.6), col, r * 0.3, true)
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.15, r * 0.5), c + Vector2(r * 0.15, r * 0.5),
				c + Vector2(r * 0.38, r * 0.98), c + Vector2(-r * 0.38, r * 0.98)]), col)
			for y in [-0.45, -0.1, 0.25]:
				cv.draw_circle(c + Vector2(0, r * y), r * 0.06, dark)
		"horn":
			cv.draw_arc(c + Vector2(-r * 0.3, r * 0.2), r * 0.45, 0.0, TAU, 28, col, w * 1.4, true)
			cv.draw_line(c + Vector2(-r * 0.95, -r * 0.3), c + Vector2(r * 0.45, -r * 0.3), col, w * 1.3, true)
			cv.draw_line(c + Vector2(-r * 0.3, r * 0.65), c + Vector2(r * 0.45, r * 0.65), col, w * 1.3, true)
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.4, -r * 0.45), c + Vector2(r * 1.0, -r * 0.95),
				c + Vector2(r * 1.0, r * 1.0), c + Vector2(r * 0.4, r * 0.5)]), col)
		"drum":
			var top := PackedVector2Array()
			for i in 24:
				var an := TAU * float(i) / 24.0
				top.append(c + Vector2(cos(an) * r * 0.8, -r * 0.3 + sin(an) * r * 0.27))
			cv.draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.3), Vector2(r * 1.6, r * 0.95)), col)
			cv.draw_colored_polygon(top, col.lightened(0.35))
			cv.draw_line(c + Vector2(-r * 0.55, -r * 0.98), c + Vector2(r * 0.15, -r * 0.4), col, w, true)
			cv.draw_line(c + Vector2(r * 0.55, -r * 0.98), c + Vector2(-r * 0.15, -r * 0.4), col, w, true)
		"frame":
			cv.draw_arc(c, r * 0.85, 0.0, TAU, 32, col, w * 1.8, true)
			cv.draw_arc(c, r * 0.5, 0.0, TAU, 28, Color(col, 0.5), w * 0.8, true)
			cv.draw_circle(c, r * 0.12, col)
		"pot":
			cv.draw_circle(c + Vector2(0, r * 0.25), r * 0.68, col)
			cv.draw_rect(Rect2(c + Vector2(-r * 0.26, -r * 0.6), Vector2(r * 0.52, r * 0.4)), col)
			cv.draw_line(c + Vector2(-r * 0.4, -r * 0.62), c + Vector2(r * 0.4, -r * 0.62), col, w * 1.3, true)
			cv.draw_arc(c + Vector2(0, r * 0.25), r * 0.4, 0.2 * PI, 0.8 * PI, 12, dark, w * 0.8, true)
		"mallet":
			for i in 5:
				var bw := r * (1.8 - i * 0.28)
				cv.draw_rect(Rect2(c + Vector2(-bw * 0.5, -r * 0.85 + i * r * 0.38), Vector2(bw, r * 0.26)), col)
		"gong":
			cv.draw_line(c + Vector2(-r * 0.95, -r * 0.95), c + Vector2(r * 0.95, -r * 0.95), col, w * 1.3, true)
			cv.draw_line(c + Vector2(-r * 0.6, -r * 0.95), c + Vector2(-r * 0.45, -r * 0.45), col, w * 0.7, true)
			cv.draw_line(c + Vector2(r * 0.6, -r * 0.95), c + Vector2(r * 0.45, -r * 0.45), col, w * 0.7, true)
			cv.draw_circle(c + Vector2(0, r * 0.2), r * 0.7, col)
			cv.draw_circle(c + Vector2(0, r * 0.2), r * 0.25, col.lightened(0.4))
		"cymbal":
			cv.draw_line(c + Vector2(0, -r * 0.95), c + Vector2(0, r * 0.95), col, w * 0.9, true)
			for y in [-0.2, 0.25]:
				var pts := PackedVector2Array()
				for i in 25:
					var an := TAU * float(i) / 24.0
					pts.append(c + Vector2(cos(an) * r * 0.9, r * y + sin(an) * r * 0.18))
				cv.draw_polyline(pts, col, w * 1.3, true)
		"choir":
			for x in [-0.6, 0.0, 0.6]:
				var yy := -0.45 if x == 0.0 else -0.2
				cv.draw_circle(c + Vector2(r * x, r * yy), r * 0.25, col)
				cv.draw_arc(c + Vector2(r * x, r * (yy + 0.95)), r * 0.38, PI, TAU, 14, col, r * 0.28, true)
		"synth":
			var pts := PackedVector2Array()
			for i in 21:
				var t := float(i) / 20.0
				pts.append(c + Vector2(lerpf(-r * 0.95, r * 0.95, t), -sin(t * TAU * 1.5) * r * 0.55))
			cv.draw_line(c + Vector2(-r * 0.95, 0), c + Vector2(r * 0.95, 0), Color(col, 0.35), w * 0.6, true)
			cv.draw_polyline(pts, col, w * 1.5, true)
		"organ":
			for i in 5:
				var hh: float = r * float([0.9, 1.3, 1.7, 1.3, 0.9][i])
				cv.draw_rect(Rect2(c + Vector2(-r * 0.95 + i * r * 0.4, r * 0.85 - hh), Vector2(r * 0.28, hh)), col)
		"zither":
			cv.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.95, r * 0.45), c + Vector2(-r * 0.6, -r * 0.5),
				c + Vector2(r * 0.95, -r * 0.5), c + Vector2(r * 0.95, r * 0.45), c + Vector2(-r * 0.95, r * 0.45)]), col, w * 1.2, true)
			for y in [-0.3, -0.1, 0.1, 0.3]:
				cv.draw_line(c + Vector2(-r * 0.8, r * y), c + Vector2(r * 0.9, r * y), col, w * 0.6, true)
		"burst":
			for i in 8:
				var d := Vector2.from_angle(TAU * float(i) / 8.0)
				cv.draw_line(c + d * r * 0.4, c + d * r * 0.98, col, w * 1.3, true)
			cv.draw_circle(c, r * 0.25, col)
		"note":
			cv.draw_circle(c + Vector2(-r * 0.3, r * 0.55), r * 0.32, col)
			cv.draw_line(c + Vector2(0.0, r * 0.5), c + Vector2(0.0, -r * 0.85), col, w * 1.2, true)
			cv.draw_polyline(PackedVector2Array([c + Vector2(0, -r * 0.85), c + Vector2(r * 0.3, -r * 0.7), c + Vector2(r * 0.55, -r * 0.3)]), col, w * 1.4, true)
		_:
			if Icons.NAMES.has(what):
				Icons.draw(cv, what, c, r, col)
			else:
				paint(cv, "note", c, r, col)
