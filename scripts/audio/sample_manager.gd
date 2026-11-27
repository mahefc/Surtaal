extends Node
## Autoload: bakes and caches synthesized notes.
## prebake() queues background bakes; get_sample() bakes synchronously as a fallback
## so a tap is never silent. Cache key = instrument + preset + zone-root note.
##
## Concurrency is bounded (cores - 2) so background baking can never starve the
## main thread (UI, audio scheduling, recording timestamps). Urgent requests jump
## the queue.

const MAX_CACHED := 500

var last_bake_ms := 0.0
var bake_count := 0
var max_parallel := maxi(1, OS.get_processor_count() - 2)

var _cache := {}
var _pending := {}   # key -> true while queued or baking
var _failed := {}    # key -> true when bake returned null (do not block Play forever)
var _queue: Array[Dictionary] = []
var _running := 0
var _mutex := Mutex.new()


func _key(def: InstrumentDef, midi: int, preset: int, layer: int = 0) -> String:
	return "%s#%d:%d:%d" % [def.id, preset, layer, def.zone_root(midi, layer)]


## The instruments a layered instrument is made of, with the note each one plays for `midi`.
func layer_parts(def: InstrumentDef, midi: int) -> Array:
	var out := []
	for l in def.params.get("layers", []):
		var sub := InstrumentManager.get_by_id(str(l.get("id", "")))
		if sub == null or sub.is_layered():
			continue
		out.append({"def": sub, "midi": clampi(midi + int(l.get("shift", 0)), 0, 127), "gain": float(l.get("gain", 1.0))})
	return out


func has_sample(def: InstrumentDef, midi: int, preset: int = -1) -> bool:
	if def.is_layered():
		for p in layer_parts(def, midi):
			if not has_sample(p.def, p.midi, 0):
				return false
		return true
	if preset < 0:
		preset = def.active_preset
	_mutex.lock()
	var r := true
	for l in def.velocity_layers():  # every velocity layer of this note must be ready
		var k := _key(def, midi, preset, l)
		if not _cache.has(k) and not _failed.has(k):
			r = false
			break
	_mutex.unlock()
	return r


func all_cached(def: InstrumentDef, notes: Array) -> bool:
	for m in notes:
		if not has_sample(def, m):
			return false
	return true


func get_sample(def: InstrumentDef, midi: int, preset: int = -1, layer: int = 0) -> AudioStreamWAV:
	if preset < 0:
		preset = def.active_preset
	var k := _key(def, midi, preset, layer)
	_mutex.lock()
	var s: AudioStreamWAV = _cache.get(k)
	_mutex.unlock()
	if s != null:
		return s
	return _bake(def, midi, preset, k, layer)


## Queue background bakes for notes that are not cached yet.
## urgent = true puts them (and any already-queued duplicates) at the front.
func prebake(def: InstrumentDef, notes: Array, preset: int = -1, urgent: bool = false) -> void:
	if def.is_layered():  # bake every part of the layer stack
		var by_part := {}  # instrument id -> {def, notes}
		for m in notes:
			for p in layer_parts(def, m):
				if not by_part.has(p.def.id):
					by_part[p.def.id] = {"def": p.def, "notes": []}
				by_part[p.def.id].notes.append(p.midi)
		for k in by_part:
			prebake(by_part[k].def, by_part[k].notes, 0, urgent)
		return
	if preset < 0:
		preset = def.active_preset
	var fresh: Array[Dictionary] = []
	_mutex.lock()
	for m in notes:
		for layer in def.velocity_layers():  # every velocity layer, so any touch plays at once
			var k := _key(def, m, preset, layer)
			if _cache.has(k) or _failed.has(k):
				continue
			if _pending.has(k):
				if urgent:  # already queued: move to the front
					for i in _queue.size():
						if _queue[i].key == k:
							fresh.append(_queue[i])
							_queue.remove_at(i)
							break
				continue
			_pending[k] = true
			fresh.append({"def": def, "midi": m, "preset": preset, "key": k, "layer": layer})
	if urgent:
		fresh.append_array(_queue)
		_queue = fresh
	else:
		_queue.append_array(fresh)
	_mutex.unlock()
	_pump()


func _pump() -> void:
	while true:
		_mutex.lock()
		if _running >= max_parallel or _queue.is_empty():
			_mutex.unlock()
			return
		var item: Dictionary = _queue.pop_front()
		_running += 1
		_mutex.unlock()
		WorkerThreadPool.add_task(_run_item.bind(item), false, "bake " + item.key)


func _run_item(item: Dictionary) -> void:
	_bake(item.def, item.midi, item.preset, item.key, int(item.layer))
	_mutex.lock()
	_running -= 1
	_mutex.unlock()
	_pump.call_deferred()


func _bake(def: InstrumentDef, midi: int, preset: int, k: String, layer: int = 0) -> AudioStreamWAV:
	var t0 := Time.get_ticks_usec()
	var s := SynthBaker.bake(def, midi, preset, layer)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_mutex.lock()
	_pending.erase(k)
	if s != null:
		_failed.erase(k)
		_cache[k] = s
		last_bake_ms = ms
		bake_count += 1
		while _cache.size() > MAX_CACHED:  # evict oldest (insertion order)
			_cache.erase(_cache.keys()[0])
	else:
		_failed[k] = true
	_mutex.unlock()
	return s
