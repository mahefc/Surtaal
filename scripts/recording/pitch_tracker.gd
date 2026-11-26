class_name PitchTracker
extends RefCounted
## Monophonic fundamental-frequency tracker based on YIN
## (de Cheveigne & Kawahara, 2002): difference function -> cumulative mean
## normalisation -> absolute threshold -> parabolic interpolation.
##
## Performance notes (GDScript, mobile): input is decimated to ~12 kHz, silent
## frames are skipped, and the search stops at the first dip below threshold.
## Intended to run on a worker thread after recording stops.
##
## pYIN (probabilistic, HMM-smoothed) is the planned upgrade; the segmenter's
## outlier rejection stands in for it for now.

const TARGET_RATE := 12000.0
const FMIN := 75.0    # ~D2: low male hum
const FMAX := 900.0   # ~A5: high whistle/soprano
const THRESHOLD := 0.15
const HOP_SEC := 0.015
const WINDOW_SEC := 0.022
const HIGHPASS_HZ := 70.0  # removes handling rumble / DC


## Returns {hop_sec, f0: PackedFloat32Array (0 = unvoiced), rms: PackedFloat32Array, voiced_conf}.
static func track(samples: PackedFloat32Array, rate: int) -> Dictionary:
	var dec := maxi(1, int(round(rate / TARGET_RATE)))
	var eff := float(rate) / dec
	var y := _decimate_highpass(samples, dec, eff)
	var m := y.size()
	var w := int(eff * WINDOW_SEC)
	var hop := maxi(1, int(eff * HOP_SEC))
	var tau_min := maxi(2, int(floor(eff / FMAX)))
	var tau_max := int(ceil(eff / FMIN))
	var frames := maxi(0, (m - w - tau_max - 1) / hop)

	var f0 := PackedFloat32Array()
	var rms := PackedFloat32Array()
	var conf := PackedFloat32Array()
	f0.resize(frames)
	rms.resize(frames)
	conf.resize(frames)

	for i in frames:
		var s := i * hop
		var e := 0.0
		for j in w:
			e += y[s + j] * y[s + j]
		rms[i] = sqrt(e / w)

	var gate := _gate(rms)
	var dn := PackedFloat32Array()
	dn.resize(tau_max + 2)
	for i in frames:
		if rms[i] < gate:
			continue
		var tau := _yin_frame(y, i * hop, w, tau_min, tau_max, dn)
		if tau > 0.0:
			f0[i] = eff / tau
			conf[i] = 1.0 - dn[int(tau)]
	return {"hop_sec": hop / eff, "f0": f0, "rms": rms, "conf": conf, "gate": gate}


## Noise gate: relative to the loud parts so it adapts to mic level, with a floor.
static func _gate(rms: PackedFloat32Array) -> float:
	if rms.is_empty():
		return 1.0
	var sorted := rms.duplicate()
	sorted.sort()
	var p95 := sorted[int(sorted.size() * 0.95)]
	return maxf(0.006, 0.12 * p95)


static func _decimate_highpass(x: PackedFloat32Array, dec: int, eff: float) -> PackedFloat32Array:
	var m := x.size() / dec
	var y := PackedFloat32Array()
	y.resize(m)
	var a := 1.0 / (1.0 + TAU * HIGHPASS_HZ / eff)
	var px := 0.0
	var py := 0.0
	for i in m:
		var s := 0.0
		for k in dec:
			s += x[i * dec + k]
		s /= dec  # box filter = cheap anti-alias for the decimation
		var h := a * (py + s - px)
		px = s
		py = h
		y[i] = h
	return y


## One YIN frame. Returns the (interpolated) lag in samples, or -1 if unvoiced.
## `dn` is scratch space (size >= tau_max + 2) holding the normalised difference.
static func _yin_frame(y: PackedFloat32Array, s: int, w: int, tau_min: int, tau_max: int, dn: PackedFloat32Array) -> float:
	var running := 0.0
	var found := -1
	dn[0] = 1.0
	var last_tau := 0
	for tau in range(1, tau_max + 1):
		var sum := 0.0
		for j in w:
			var d := y[s + j] - y[s + j + tau]
			sum += d * d
		running += sum
		dn[tau] = sum * tau / running if running > 0.0 else 1.0
		last_tau = tau
		if found < 0:
			if tau >= tau_min and dn[tau] < THRESHOLD:
				found = tau
		elif dn[tau] > dn[tau - 1]:
			break  # past the local minimum
	var best := -1
	if found >= 0:
		best = found
		while best + 1 <= last_tau and dn[best + 1] < dn[best]:
			best += 1
	else:  # no clear dip: accept the global minimum only if reasonably periodic
		var lo := 1.0
		for tau in range(tau_min, tau_max + 1):
			if dn[tau] < lo:
				lo = dn[tau]
				best = tau
		if lo > 0.35:
			return -1.0
	if best < 1 or best + 1 > last_tau:
		return float(best)
	var a := dn[best - 1]
	var b := dn[best]
	var c := dn[best + 1]
	var denom := a - 2.0 * b + c
	var shift := 0.5 * (a - c) / denom if absf(denom) > 1e-9 else 0.0
	return float(best) + clampf(shift, -1.0, 1.0)
