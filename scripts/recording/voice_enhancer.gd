class_name VoiceEnhancer
extends RefCounted
## Studio-style clean-up of a raw microphone take (runs on a worker thread):
##   1. DC offset removal + 80 Hz high-pass (handling noise, plosive thumps, rumble)
##   2. noise reduction: an expander that pulls the room/mic hiss down between phrases
##      (the floor is measured from the quietest parts of the take itself)
##   3. gentle compression (3:1) so loud and soft phrases sit at a similar level
##   4. level matching to -1 dBFS with a soft limiter, so it never clips
## It does not change pitch or timing.

const HIGHPASS_HZ := 80.0
const TARGET_PEAK := 0.89            # -1 dBFS
const MAX_NOISE_CUT := 0.15          # the expander never cuts more than ~-16 dB
const COMP_THRESHOLD := 0.09         # about -21 dBFS
const COMP_RATIO := 3.0


static func process(x: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	var n := x.size()
	if n == 0:
		return x
	var y := _highpass(x, rate)
	y = _expand(y, rate)
	y = _compress(y, rate)
	var peak := 0.0001
	for v in y:
		peak = maxf(peak, absf(v))
	var g := TARGET_PEAK / peak
	for i in n:
		var v := y[i] * g
		y[i] = v / (1.0 + 0.08 * absf(v))  # soft limiter: tames the odd stray peak without audible distortion
	return y


# 2nd-order Butterworth high-pass (RBJ biquad) also removes DC.
static func _highpass(x: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	var w0 := TAU * HIGHPASS_HZ / rate
	var c := cos(w0)
	var alpha := sin(w0) / (2.0 * 0.70710678)
	var a0 := 1.0 + alpha
	var b0 := (1.0 + c) * 0.5 / a0
	var b1 := -(1.0 + c) / a0
	var b2 := b0
	var a1 := -2.0 * c / a0
	var a2 := (1.0 - alpha) / a0
	var n := x.size()
	var y := PackedFloat32Array()
	y.resize(n)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in n:
		var xi := x[i]
		var yi := b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = xi
		y2 = y1
		y1 = yi
		y[i] = yi
	return y


static func _expand(x: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	var n := x.size()
	var frame := maxi(int(rate * 0.02), 1)
	var rms := PackedFloat32Array()
	var i := 0
	while i + frame <= n:
		var e := 0.0
		for j in frame:
			e += x[i + j] * x[i + j]
		rms.append(sqrt(e / frame))
		i += frame
	if rms.size() < 5:
		return x
	var sorted := rms.duplicate()
	sorted.sort()
	var floor_rms: float = sorted[int(sorted.size() * 0.1)]
	var threshold := maxf(floor_rms * 3.0, 0.004)
	var atk := exp(-1.0 / (0.005 * rate))
	var rel := exp(-1.0 / (0.10 * rate))
	var env_rel := exp(-1.0 / (0.03 * rate))
	var env := 0.0
	var gain := 1.0
	var y := PackedFloat32Array()
	y.resize(n)
	for k in n:
		var a := absf(x[k])
		env = a if a > env else env * env_rel + a * (1.0 - env_rel)
		var target := 1.0
		if env < threshold:
			target = maxf(pow(env / threshold, 1.5), MAX_NOISE_CUT)
		# open quickly (never clip the start of a word), close slowly
		gain = gain * (atk if target > gain else rel) + target * (1.0 - (atk if target > gain else rel))
		y[k] = x[k] * gain
	return y


static func _compress(x: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	var n := x.size()
	var atk := exp(-1.0 / (0.010 * rate))
	var rel := exp(-1.0 / (0.15 * rate))
	var exponent := 1.0 - 1.0 / COMP_RATIO
	var env := 0.0
	var y := PackedFloat32Array()
	y.resize(n)
	for i in n:
		var a := absf(x[i])
		env = env * (atk if a > env else rel) + a * (1.0 - (atk if a > env else rel))
		var g := 1.0
		if env > COMP_THRESHOLD:
			g = pow(COMP_THRESHOLD / env, exponent)
		y[i] = x[i] * g
	return y
