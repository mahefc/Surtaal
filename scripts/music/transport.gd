extends Node
## Autoload: musical clock. Emits step_fired for every 16th note while playing.
## Frame-driven (jitter <= one frame); sample-accurate lookahead scheduling is a
## later-phase item once the native audio layer exists.

signal step_fired(step: int)
signal started
signal stopped
signal finished  # reached the end with loop == false

const STEPS_PER_BAR := 16
const MIN_BPM := 40.0
const MAX_BPM := 220.0

signal bpm_changed

var bpm := 100.0:
	set(v):
		var nv := clampf(v, MIN_BPM, MAX_BPM)
		if nv != bpm:
			bpm = nv
			bpm_changed.emit()
var playing := false
var step := -1  # last fired step (0 .. loop_steps-1)
var loop_steps := 64  # length being played, in 16ths
var loop := true      # false = stop at the end (songs), true = repeat (previews)

var _acc := 0.0


func start(from_step: int = 0) -> void:
	if playing:
		return
	playing = true
	step = clampi(from_step, 0, maxi(loop_steps - 1, 0)) - 1  # the first step fired is `from_step`
	_acc = 1.0  # fire the first step on the next frame
	started.emit()


func stop() -> void:
	if not playing:
		return
	playing = false
	step = -1
	stopped.emit()


## Jump to a step while playing (the next step fired is `to_step`).
func seek(to_step: int) -> void:
	step = clampi(to_step, 0, maxi(loop_steps - 1, 0)) - 1
	_acc = 1.0


func toggle() -> void:
	if playing:
		stop()
	else:
		start()


func seconds_per_step() -> float:
	return 60.0 / bpm / 4.0


## Elapsed song time in seconds at the last fired step.
func position_sec() -> float:
	return maxf(step, 0) * seconds_per_step()


func _process(delta: float) -> void:
	if not playing:
		return
	_acc += delta * bpm / 60.0 * 4.0  # 4 sixteenths per beat
	while _acc >= 1.0:
		_acc -= 1.0
		var nxt := step + 1
		if nxt >= maxi(loop_steps, 1):
			if loop:
				nxt = 0
			else:
				stop()
				finished.emit()
				return
		step = nxt
		step_fired.emit(step)
