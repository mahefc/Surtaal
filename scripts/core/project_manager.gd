extends Node
## Autoload: project state, save/load, autosave + recovery, undo/redo.
##
## State is split in two:
##   content - what you composed (bpm, tuning, Sa, song length, tracks). Undoable.
##   view    - UI-only state. Saved, but not undoable (currently empty).
## Undo works on debounced snapshots, so a drag gesture is one undo step.

signal state_changed          # name / dirty / undo-redo availability changed
signal project_list_changed

const VERSION := 2
const DIR := "user://projects/"
const AUTOSAVE_PATH := "user://projects/_autosave.json"
const MAX_UNDO := 60
const AUTOSAVE_SEC := 15.0
const COMMIT_DELAY := 0.4
## Edits reach the project file this long after the first change (later edits in the window ride along).
const SAVE_DELAY := 1.0

var project_name := "Untitled"
## True while there are edits that are not on disk yet. With autosave this is only ever true for a moment.
var dirty := false
## Ticks (msec) of the last write of the project file; 0 = not saved yet.
var last_saved_msec := 0

var _undo: Array[String] = []
var _redo: Array[String] = []
var _current := ""
var _applying := false
var _debounce := Timer.new()
var _autosave := Timer.new()
var _save_timer := Timer.new()
var _saved_name := ""  # the name the project file on disk has (so a rename can move it)
## Dev/test switch: SURTAAL_FRESH=1 skips recovery and never touches the autosave file.
var _fresh := OS.has_environment("SURTAAL_FRESH")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_debounce.one_shot = true
	_debounce.wait_time = COMMIT_DELAY
	_debounce.timeout.connect(flush)
	add_child(_debounce)
	_autosave.wait_time = AUTOSAVE_SEC
	_autosave.timeout.connect(_on_autosave)
	add_child(_autosave)
	_autosave.start()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)

	if _fresh:
		_autosave.stop()
	elif FileAccess.file_exists(AUTOSAVE_PATH):  # project recovery
		var d := _read(AUTOSAVE_PATH)
		if not d.is_empty():
			_apply_file(d)
			if FileAccess.file_exists(_path(project_name)):
				_saved_name = project_name
	_current = _content_json()

	TrackManager.tracks_changed.connect(_on_content_changed)
	TrackManager.track_changed.connect(func(_t): _on_content_changed())
	TuningManager.changed.connect(_on_content_changed)
	Transport.bpm_changed.connect(_on_content_changed)


# ------------------------------------------------------------- state
func content_state() -> Dictionary:
	var s := TrackManager.export_state()
	s["bpm"] = Transport.bpm
	s["tuning"] = TuningManager.tuning_index
	s["root"] = TuningManager.root_pc
	return s


func view_state() -> Dictionary:
	return {}

func _content_json() -> String:
	return JSON.stringify(content_state(), "", true)


func _apply_content(c: Dictionary) -> void:
	_applying = true
	Transport.bpm = float(c.get("bpm", 100.0))
	TuningManager.tuning_index = clampi(int(c.get("tuning", 0)), 0, TuningManager.PRESETS.size() - 1)
	TuningManager.root_pc = posmod(int(c.get("root", 0)), 12)
	TuningManager.changed.emit()
	TrackManager.import_state(c)
	_applying = false
	_debounce.stop()


func _apply_view(_v: Dictionary) -> void:
	pass


func _apply_file(d: Dictionary) -> void:
	project_name = str(d.get("name", "Untitled"))
	_apply_content(d.get("content", {}))
	_apply_view(d.get("view", {}))


# -------------------------------------------------------------- undo
func _on_content_changed() -> void:
	if _applying:
		return
	_mark_dirty()
	_debounce.start()
	_queue_save()


## Autosave: write the project file shortly after the first change. Not restarted by further
## changes, so a long editing session still saves every second or so.
func _queue_save() -> void:
	if not _fresh and _save_timer.is_stopped():
		_save_timer.start()


func _mark_dirty() -> void:
	if _applying:
		return
	if not dirty:
		dirty = true
		state_changed.emit()


## Commit any pending edit as an undo step now.
func flush() -> void:
	_debounce.stop()
	var s := _content_json()
	if s == _current:
		return
	_undo.append(_current)
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()
	_current = s
	state_changed.emit()


func can_undo() -> bool:
	return not _undo.is_empty() or _content_json() != _current


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> void:
	flush()
	if _undo.is_empty():
		return
	_redo.append(_current)
	_current = _undo.pop_back()
	_apply_content(JSON.parse_string(_current))
	dirty = true
	_queue_save()
	state_changed.emit()


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_current)
	_current = _redo.pop_back()
	_apply_content(JSON.parse_string(_current))
	dirty = true
	_queue_save()
	state_changed.emit()


# ------------------------------------------------------ files / projects
func slug(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		out += ch if (ch.is_valid_identifier() or ch == "-" or ch == " ") else "_"
	out = out.replace(" ", "_").lstrip("_")
	return out if out != "" else "untitled"


func _path(n: String) -> String:
	return DIR + slug(n) + ".json"


func _document() -> Dictionary:
	return {"version": VERSION, "name": project_name, "content": content_state(), "view": view_state()}


func _write(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ProjectManager: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(_document(), "\t"))
	return true


func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) > VERSION:
		push_warning("ProjectManager: unreadable or newer project file %s" % path)
		return {}
	return parsed


func save() -> bool:
	_save_timer.stop()
	flush()
	var ok := _write(_path(project_name))
	if ok:
		if _saved_name != "" and slug(_saved_name) != slug(project_name):
			DirAccess.remove_absolute(_path(_saved_name))  # renamed: the old file goes away
		_saved_name = project_name
		last_saved_msec = Time.get_ticks_msec()
		if not _fresh:
			_write(AUTOSAVE_PATH)
		dirty = false
		state_changed.emit()
		project_list_changed.emit()
	return ok


## Autosave entry point. Writes the project if it has unsaved edits (and is worth keeping: a
## brand-new project with no tracks is not written until something is added).
func save_now() -> void:
	_save_timer.stop()
	if _fresh or _applying:
		return
	if not dirty and _debounce.is_stopped():
		return
	if TrackManager.tracks.is_empty() and _saved_name == "":
		return
	save()


func _notification(what: int) -> void:
	# leaving the app (closing, switching away, phone call, home button): never lose an edit
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_now()


func rename(new_name: String) -> void:
	project_name = new_name.strip_edges() if new_name.strip_edges() != "" else "Untitled"
	_mark_dirty()
	state_changed.emit()
	_queue_save()


func list_projects() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for file in d.get_files():
		if file.ends_with(".json") and not file.begins_with("_"):
			var doc := _read(DIR + file)
			if not doc.is_empty():
				out.append(str(doc.get("name", file.get_basename())))
	out.sort()
	return out


func open_project(n: String) -> bool:
	var doc := _read(_path(n))
	if doc.is_empty():
		return false
	_apply_file(doc)
	_saved_name = project_name
	_reset_history()
	return true


func new_project() -> void:
	save_now()  # whatever was open is safe first
	_saved_name = ""
	var existing := list_projects()
	var n := "Untitled"
	var i := 2
	while existing.has(n):
		n = "Untitled %d" % i
		i += 1
	project_name = n
	_apply_content({"bpm": 100.0, "tuning": 0, "root": 0, "tracks": []})
	_reset_history()


func duplicate_project() -> void:
	flush()
	save_now()
	project_name = project_name + " copy"
	_saved_name = ""  # a new file: the original stays
	save()


func delete_project(n: String) -> void:
	DirAccess.remove_absolute(_path(n))
	if slug(n) == slug(_saved_name):  # the open project: do not let autosave bring it back
		_saved_name = ""
		_save_timer.stop()
		dirty = false
	project_list_changed.emit()


func _reset_history() -> void:
	_undo.clear()
	_redo.clear()
	_current = _content_json()
	dirty = false
	state_changed.emit()


func _on_autosave() -> void:
	if dirty and not _fresh:
		_write(AUTOSAVE_PATH)
