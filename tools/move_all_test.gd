extends SceneTree
## Dev tool: godot --headless --script res://tools/move_all_test.gd
## A phrase moves together with shift_notes (the arrow keys use the same move).

var bad := 0


func _check(label: String, cond: bool) -> void:
	print("%s  %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		bad += 1


func _initialize() -> void:
	await process_frame
	var tm: Node = root.get_node("TrackManager")
	var t = tm.add_track("piano")
	var a = t.add_note(4, 2, 60, 0.8)
	var b = t.add_note(10, 3, 64, 0.8)
	var roll = load("res://scripts/ui/piano_roll.gd").new()
	root.add_child(roll)
	roll.size = Vector2(440, 300)
	roll.steps = 16
	roll.low_midi = 48
	roll.fixed_rows = 24
	roll.track = t
	await process_frame
	var cw: float = (roll.size.x - roll.LABEL_W) / 16.0
	var rh: float = (roll.size.y - roll._lane_h() - 4.0) / 24.0
	var p0 := Vector2(roll.LABEL_W + cw * 8.5, rh * 6.5)

	var before: int = t.notes.size()
	roll._begin(p0)
	roll._end()
	_check("a tap on an empty cell draws a note", t.notes.size() == before + 1)
	t.notes.pop_back()

	var moved: int = tm.shift_notes(t, 0, 16, 3, -2)
	_check("the phrase moves 3 steps later (%d, %d)" % [a.start, b.start], moved == 2 and a.start == 7 and b.start == 13)
	_check("the phrase moves 2 semitones together (%d, %d)" % [a.midi, b.midi], a.midi == 58 and b.midi == 62)
	_check("no note was added or removed", t.notes.size() == 2)

	tm.shift_notes(t, 0, 16, -500, 500)
	_check("it stops when the first note reaches the start (%d)" % a.start, a.start == 0 and b.start == 6)
	_check("it stops at the top of the pitch range (%d)" % maxi(a.midi, b.midi), maxi(a.midi, b.midi) == 127 and a.midi < b.midi)

	var outside = t.add_note(20, 1, 60, 0.8)
	tm.shift_notes(t, 0, 16, 0, -1)
	_check("a note outside these bars stays put (%d)" % outside.midi, outside.midi == 60 and outside.start == 20)

	print("RESULT: %s" % ("PASS" if bad == 0 else "%d FAILED" % bad))
	quit(0 if bad == 0 else 1)
