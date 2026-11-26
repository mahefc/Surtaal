class_name Icons
extends RefCounted
## Vector icon set drawn in code (no image assets, crisp at any DPI/scale).
## Every icon is drawn inside a square of half-size `r` centred on `c`.

const NAMES := [
	"play", "stop", "record", "mic", "keys", "undo", "redo", "plus", "minus", "back", "prev", "next",
	"trash", "speaker", "muted", "menu", "up", "down", "close", "wave",
	"swap", "export", "solo", "zoomin", "zoomout", "copy", "loop", "reverb", "transpose", "playall", "clear", "pan", "patterns", "steps", "along", "moveall", "velocity", "select", "paste",
]


static func draw(cv: CanvasItem, icon: String, c: Vector2, r: float, col: Color) -> void:
	var w := maxf(1.4, r * 0.18)
	match icon:
		"play":
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.55, -r * 0.8), c + Vector2(r * 0.85, 0), c + Vector2(-r * 0.55, r * 0.8)]), col)
		"playall":
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.85, -r * 0.7), c + Vector2(r * 0.35, 0), c + Vector2(-r * 0.85, r * 0.7)]), col)
			cv.draw_rect(Rect2(c + Vector2(r * 0.55, -r * 0.7), Vector2(r * 0.3, r * 1.4)), col)
		"stop":
			cv.draw_rect(Rect2(c - Vector2(r * 0.7, r * 0.7), Vector2(r * 1.4, r * 1.4)), col)
		"record":
			cv.draw_circle(c, r * 0.85, col)
		"mic":
			var cap := Rect2(c + Vector2(-r * 0.32, -r * 0.95), Vector2(r * 0.64, r * 1.3))
			cv.draw_rect(cap, col)
			cv.draw_circle(cap.position + Vector2(r * 0.32, 0), r * 0.32, col)
			cv.draw_circle(cap.position + Vector2(r * 0.32, cap.size.y), r * 0.32, col)
			cv.draw_arc(c + Vector2(0, r * 0.2), r * 0.7, 0.05 * PI, 0.95 * PI, 20, col, w, true)
			cv.draw_line(c + Vector2(0, r * 0.9), c + Vector2(0, r * 1.15), col, w, true)
			cv.draw_line(c + Vector2(-r * 0.4, r * 1.15), c + Vector2(r * 0.4, r * 1.15), col, w, true)
		"keys":
			var box := Rect2(c - Vector2(r * 1.0, r * 0.7), Vector2(r * 2.0, r * 1.4))
			cv.draw_rect(box, col, false, w)
			for x in [-0.33, 0.33]:
				cv.draw_line(c + Vector2(r * x * 2.0, -r * 0.7), c + Vector2(r * x * 2.0, r * 0.7), col, w * 0.7, true)
				cv.draw_rect(Rect2(c + Vector2(r * x * 2.0 - r * 0.13, -r * 0.7), Vector2(r * 0.26, r * 0.8)), col)
		"undo", "redo":
			# U-turn arrow: a horizontal stroke, a half-circle, and an arrow head at the start.
			var s := -1.0 if icon == "redo" else 1.0
			var cen := c + Vector2(s * r * 0.4, r * 0.1)
			var rad := r * 0.45
			if s > 0.0:
				cv.draw_arc(cen, rad, -PI * 0.5, PI * 0.5, 16, col, w, true)
			else:
				cv.draw_arc(cen, rad, PI * 0.5, PI * 1.5, 16, col, w, true)
			cv.draw_line(c + Vector2(-s * r * 0.45, -r * 0.35), c + Vector2(s * r * 0.4, -r * 0.35), col, w, true)
			cv.draw_line(c + Vector2(s * r * 0.4, r * 0.55), c + Vector2(-s * r * 0.2, r * 0.55), col, w, true)
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * r * 0.9, -r * 0.35), c + Vector2(-s * r * 0.4, -r * 0.8), c + Vector2(-s * r * 0.4, r * 0.1)]), col)
		"plus":
			cv.draw_line(c + Vector2(-r * 0.75, 0), c + Vector2(r * 0.75, 0), col, w * 1.2, true)
			cv.draw_line(c + Vector2(0, -r * 0.75), c + Vector2(0, r * 0.75), col, w * 1.2, true)
		"minus":
			cv.draw_line(c + Vector2(-r * 0.75, 0), c + Vector2(r * 0.75, 0), col, w * 1.2, true)
		"back", "prev":
			cv.draw_polyline(PackedVector2Array([c + Vector2(r * 0.35, -r * 0.8), c + Vector2(-r * 0.4, 0), c + Vector2(r * 0.35, r * 0.8)]), col, w * 1.2, true)
		"next":
			cv.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.35, -r * 0.8), c + Vector2(r * 0.4, 0), c + Vector2(-r * 0.35, r * 0.8)]), col, w * 1.2, true)
		"up":
			cv.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.8, r * 0.35), c + Vector2(0, -r * 0.4), c + Vector2(r * 0.8, r * 0.35)]), col, w * 1.2, true)
		"down":
			cv.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.35), c + Vector2(0, r * 0.4), c + Vector2(r * 0.8, -r * 0.35)]), col, w * 1.2, true)
		"close":
			cv.draw_line(c + Vector2(-r * 0.65, -r * 0.65), c + Vector2(r * 0.65, r * 0.65), col, w * 1.2, true)
			cv.draw_line(c + Vector2(-r * 0.65, r * 0.65), c + Vector2(r * 0.65, -r * 0.65), col, w * 1.2, true)
		"trash":
			cv.draw_line(c + Vector2(-r * 0.85, -r * 0.5), c + Vector2(r * 0.85, -r * 0.5), col, w, true)
			cv.draw_rect(Rect2(c + Vector2(-r * 0.25, -r * 0.85), Vector2(r * 0.5, r * 0.3)), col, false, w * 0.8)
			cv.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.4), c + Vector2(-r * 0.5, r * 0.9), c + Vector2(r * 0.5, r * 0.9), c + Vector2(r * 0.6, -r * 0.4)]), col, w, true)
			cv.draw_line(c + Vector2(0, -r * 0.1), c + Vector2(0, r * 0.6), col, w * 0.7, true)
		"speaker", "muted":
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.95, -r * 0.3), c + Vector2(-r * 0.4, -r * 0.3), c + Vector2(r * 0.15, -r * 0.8),
				c + Vector2(r * 0.15, r * 0.8), c + Vector2(-r * 0.4, r * 0.3), c + Vector2(-r * 0.95, r * 0.3)]), col)
			if icon == "speaker":
				cv.draw_arc(c + Vector2(r * 0.1, 0), r * 0.55, -PI * 0.3, PI * 0.3, 10, col, w, true)
				cv.draw_arc(c + Vector2(r * 0.1, 0), r * 0.95, -PI * 0.3, PI * 0.3, 12, col, w, true)
			else:
				cv.draw_line(c + Vector2(r * 0.45, -r * 0.45), c + Vector2(r * 1.0, r * 0.45), col, w, true)
				cv.draw_line(c + Vector2(r * 0.45, r * 0.45), c + Vector2(r * 1.0, -r * 0.45), col, w, true)
		"menu":
			for y in [-0.6, 0.0, 0.6]:
				cv.draw_line(c + Vector2(-r * 0.85, r * y), c + Vector2(r * 0.85, r * y), col, w * 1.1, true)
		"patterns":
			# a small step grid, some cells lit: ready-made beats
			var lit := [Vector2i(0, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(2, 2)]
			for gy in 3:
				for gx in 3:
					var cell := Rect2(c + Vector2(-r * 0.9 + gx * r * 0.65, -r * 0.9 + gy * r * 0.65), Vector2(r * 0.5, r * 0.5))
					if lit.has(Vector2i(gx, gy)):
						cv.draw_rect(cell, col)
					else:
						cv.draw_rect(cell, Color(col, 0.35), false, maxf(1.0, w * 0.5))
		"steps":
			# one row of steps with a start and an end tick: how long the loop is
			for k in 4:
				cv.draw_rect(Rect2(c + Vector2(-r * 0.95 + k * r * 0.5, -r * 0.25), Vector2(r * 0.4, r * 0.5)), col if k % 2 == 0 else Color(col, 0.45))
			cv.draw_line(c + Vector2(-r * 0.95, -r * 0.75), c + Vector2(-r * 0.95, r * 0.75), col, w * 0.7, true)
			cv.draw_line(c + Vector2(r * 0.95, -r * 0.75), c + Vector2(r * 0.95, r * 0.75), col, w * 0.7, true)
		"along":
			# stacked layers: the other tracks playing underneath
			for k in 3:
				var oy := (k - 1) * r * 0.6
				var top := c + Vector2(0, oy - r * 0.3)
				cv.draw_polyline(PackedVector2Array([top + Vector2(-r * 0.9, r * 0.1), top + Vector2(0, -r * 0.35), top + Vector2(r * 0.9, r * 0.1), top + Vector2(0, r * 0.55), top + Vector2(-r * 0.9, r * 0.1)]),
					col if k == 2 else Color(col, 0.6), w * 0.8, true)
		"pan":
			# a drawn S-curve between a left and a right marker: sound moving across the speakers
			var pts_pan := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				pts_pan.append(c + Vector2(lerpf(-r * 0.85, r * 0.85, t), -sin((t - 0.5) * PI) * r * 0.55))
			cv.draw_polyline(pts_pan, col, w * 1.2, true)
			cv.draw_circle(c + Vector2(r * 0.85, -r * 0.55), r * 0.2, col)
			cv.draw_line(c + Vector2(-r * 0.85, r * 0.55), c + Vector2(-r * 0.85, r * 0.95), col, w, true)
			cv.draw_line(c + Vector2(r * 0.85, r * 0.55), c + Vector2(r * 0.85, r * 0.95), col, w, true)
			cv.draw_line(c + Vector2(-r * 0.85, r * 0.75), c + Vector2(r * 0.85, r * 0.75), col, w * 0.6, true)
		"select":
			# a dashed box with two notes inside it
			var q := r * 0.85
			var corners := [c + Vector2(-q, -q), c + Vector2(q, -q), c + Vector2(q, q), c + Vector2(-q, q)]
			for k in 4:
				var p_from: Vector2 = corners[k]
				var p_to: Vector2 = corners[(k + 1) % 4]
				for d in 4:  # dashes: every other quarter of each side
					if d % 2 == 0:
						cv.draw_line(p_from.lerp(p_to, d / 4.0), p_from.lerp(p_to, (d + 1) / 4.0), col, w * 0.8, true)
			cv.draw_rect(Rect2(c + Vector2(-r * 0.4, -r * 0.25), Vector2(r * 0.4, r * 0.3)), col)
			cv.draw_rect(Rect2(c + Vector2(r * 0.05, r * 0.1), Vector2(r * 0.4, r * 0.3)), col)
		"paste":
			# a clipboard: board with a clip on top and a few lines
			cv.draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.6), Vector2(r * 1.4, r * 1.5)), col, false, w)
			cv.draw_rect(Rect2(c + Vector2(-r * 0.3, -r * 0.85), Vector2(r * 0.6, r * 0.45)), col)
			cv.draw_line(c + Vector2(-r * 0.4, -r * 0.1), c + Vector2(r * 0.4, -r * 0.1), col, w * 0.8, true)
			cv.draw_line(c + Vector2(-r * 0.4, r * 0.25), c + Vector2(r * 0.4, r * 0.25), col, w * 0.8, true)
			cv.draw_line(c + Vector2(-r * 0.4, r * 0.6), c + Vector2(r * 0.1, r * 0.6), col, w * 0.8, true)
		"velocity":
			# hits of different strength: bars of different height on a baseline
			var heights := [0.9, 0.45, 0.7, 0.3]
			for k in 4:
				var bh: float = r * 1.7 * heights[k]
				cv.draw_rect(Rect2(c + Vector2(-r * 0.95 + k * r * 0.5, r * 0.85 - bh), Vector2(r * 0.34, bh)), col)
		"moveall":
			# a four-way arrow: select every note and slide them together
			cv.draw_line(c + Vector2(-r * 0.9, 0), c + Vector2(r * 0.9, 0), col, w, true)
			cv.draw_line(c + Vector2(0, -r * 0.9), c + Vector2(0, r * 0.9), col, w, true)
			for s in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var tip: Vector2 = c + s * r * 0.95
				var side := Vector2(-s.y, s.x)
				cv.draw_colored_polygon(PackedVector2Array([tip, tip - s * r * 0.4 + side * r * 0.3, tip - s * r * 0.4 - side * r * 0.3]), col)
		"clear":
			# eraser: angled block with a clean face
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.85, r * 0.15), c + Vector2(-r * 0.25, -r * 0.75),
				c + Vector2(r * 0.55, -r * 0.35), c + Vector2(-r * 0.05, r * 0.55)]), col)
			cv.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.05, r * 0.55), c + Vector2(r * 0.55, -r * 0.35),
				c + Vector2(r * 0.85, r * 0.05), c + Vector2(r * 0.25, r * 0.95)]), Color(col, 0.55))
			cv.draw_line(c + Vector2(-r * 0.7, r * 0.85), c + Vector2(r * 0.55, r * 0.85), col, w * 0.9, true)
		"wave":
			var hs := [0.25, 0.6, 0.95, 0.5, 0.8, 0.35, 0.6]
			for i in hs.size():
				var x := -r * 0.9 + i * (r * 1.8 / (hs.size() - 1))
				cv.draw_line(c + Vector2(x, -r * hs[i]), c + Vector2(x, r * hs[i]), col, w * 1.1, true)
		"swap":
			cv.draw_line(c + Vector2(-r * 0.8, -r * 0.35), c + Vector2(r * 0.7, -r * 0.35), col, w, true)
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.9, -r * 0.35), c + Vector2(r * 0.4, -r * 0.75), c + Vector2(r * 0.4, r * 0.05)]), col)
			cv.draw_line(c + Vector2(r * 0.8, r * 0.35), c + Vector2(-r * 0.7, r * 0.35), col, w, true)
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.9, r * 0.35), c + Vector2(-r * 0.4, -r * 0.05), c + Vector2(-r * 0.4, r * 0.75)]), col)
		"export":
			# tray with an arrow leaving it
			cv.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.85, r * 0.1), c + Vector2(-r * 0.85, r * 0.85), c + Vector2(r * 0.85, r * 0.85), c + Vector2(r * 0.85, r * 0.1)]), col, w, true)
			cv.draw_line(c + Vector2(0, r * 0.45), c + Vector2(0, -r * 0.85), col, w * 1.1, true)
			cv.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.4, -r * 0.4), c + Vector2(0, -r * 0.85), c + Vector2(r * 0.4, -r * 0.4)]), col, w * 1.1, true)
		"solo":
			# headphones
			cv.draw_arc(c + Vector2(0, r * 0.1), r * 0.8, PI, TAU, 20, col, w, true)
			cv.draw_rect(Rect2(c + Vector2(-r * 0.98, r * 0.05), Vector2(r * 0.34, r * 0.8)), col)
			cv.draw_rect(Rect2(c + Vector2(r * 0.64, r * 0.05), Vector2(r * 0.34, r * 0.8)), col)
		"zoomin", "zoomout":
			cv.draw_arc(c + Vector2(-r * 0.15, -r * 0.15), r * 0.62, 0, TAU, 24, col, w, true)
			cv.draw_line(c + Vector2(r * 0.3, r * 0.3), c + Vector2(r * 0.95, r * 0.95), col, w * 1.3, true)
			cv.draw_line(c + Vector2(-r * 0.45, -r * 0.15), c + Vector2(r * 0.15, -r * 0.15), col, w * 0.9, true)
			if icon == "zoomin":
				cv.draw_line(c + Vector2(-r * 0.15, -r * 0.45), c + Vector2(-r * 0.15, r * 0.15), col, w * 0.9, true)
		"copy":
			cv.draw_rect(Rect2(c + Vector2(-r * 0.2, -r * 0.2), Vector2(r * 1.05, r * 1.05)), col, false, w)
			cv.draw_polyline(PackedVector2Array([c + Vector2(r * 0.0, -r * 0.2), c + Vector2(r * 0.0, -r * 0.85), c + Vector2(-r * 0.9, -r * 0.85), c + Vector2(-r * 0.9, r * 0.05), c + Vector2(-r * 0.2, r * 0.05)]), col, w, true)
		"loop":
			# a circular arrow: "repeat"
			cv.draw_arc(c, r * 0.75, -PI * 0.15, PI * 1.55, 28, col, w * 1.1, true)
			var tip := c + Vector2(cos(-PI * 0.15), sin(-PI * 0.15)) * r * 0.75
			cv.draw_colored_polygon(PackedVector2Array([tip + Vector2(-r * 0.05, -r * 0.55), tip + Vector2(r * 0.5, r * 0.15), tip + Vector2(-r * 0.5, r * 0.25)]), col)
		"reverb":
			# a dot with spreading echo rings
			cv.draw_circle(c + Vector2(-r * 0.55, 0), r * 0.2, col)
			for k in 3:
				var rad := r * (0.5 + 0.38 * k)
				cv.draw_arc(c + Vector2(-r * 0.55, 0), rad, -PI * 0.28, PI * 0.28, 10, col, w, true)
		"transpose":
			# a note with an up/down arrow: "notes follow the octave"
			cv.draw_circle(c + Vector2(-r * 0.45, r * 0.55), r * 0.3, col)
			cv.draw_line(c + Vector2(-r * 0.17, r * 0.5), c + Vector2(-r * 0.17, -r * 0.75), col, w, true)
			cv.draw_polyline(PackedVector2Array([c + Vector2(r * 0.45, -r * 0.2), c + Vector2(r * 0.8, -r * 0.7), c + Vector2(r * 1.15, -r * 0.2)]), col, w, true)
			cv.draw_polyline(PackedVector2Array([c + Vector2(r * 0.45, r * 0.2), c + Vector2(r * 0.8, r * 0.7), c + Vector2(r * 1.15, r * 0.2)]), col, w, true)
