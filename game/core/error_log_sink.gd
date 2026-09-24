extends Logger
## What ErrorLog hangs on the engine: every error and warning the engine or a script reports, as
## it is reported, kept in memory until ErrorLog writes it down.
##
## Kept in a file of its own, loaded only when the engine has a `Logger` class to extend: an
## engine without one would fail to parse an autoload that named it, and then there would be no
## error log at all rather than one that says it cannot listen.
##
## The engine calls this from whatever thread the error happened on, and from inside its own
## error path, so nothing here may report an error, print, touch the scene tree or the disk. It
## takes the lock, counts, and keeps the first lines of each kind for the session file.

## How many times one report is written out line by line before it is only counted: a warning
## said every frame for an hour is one line in the summary with a count beside it, not a file of
## a million lines.
const LINES_PER_REPORT := 50
## And how many lines the session file takes from the whole session.
const LINES_MAX := 20000
const KIND_NAMES := ["error", "warning", "script_error", "shader_error"]
## Frames that are only the messenger: `Log.error` calls `push_error`, so the place that said it
## is the frame below.
const MESSENGER_FRAMES := ["res://core/log.gd"]

var _lock := Mutex.new()
var _started_ms := Time.get_ticks_msec()
## key -> {kind, message, source, count, first_ms, last_ms, backtrace}
var reports := {}
var pending_lines: PackedStringArray = []
var lines_written := 0
var totals := {"error": 0, "warning": 0, "script_error": 0, "shader_error": 0, "printerr": 0}
var dirty := false
## Called once (deferred, on the main thread) the first time a report says the editor's import
## cache is older than the files it was made from.
var on_stale_import: Callable
var stale_import_seen := false
var _fold := RegEx.create_from_string("(?<![A-Za-z_])-?\\d+(?:\\.\\d+)?(?![A-Za-z_])|0x[0-9a-fA-F]+")


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var kind: String = KIND_NAMES[error_type] if error_type >= 0 and error_type < KIND_NAMES.size() else "error"
	var message := rationale if rationale != "" else code
	var engine_at := "%s (%s:%d)" % [function, file, line]
	var source := ""
	var backtrace := ""
	for bt in script_backtraces:
		if bt == null or bt.is_empty():
			continue
		if backtrace == "":
			backtrace = bt.format(0, 4)
		if source == "":
			for i in bt.get_frame_count():
				var f := bt.get_frame_file(i)
				if f in MESSENGER_FRAMES:
					continue
				source = "%s:%d in %s()" % [f, bt.get_frame_line(i), bt.get_frame_function(i)]
				break
	# a script error names its own script and line; an engine error, the C++ it came from
	if source == "":
		source = engine_at if kind != "script_error" or file == "" else "%s:%d in %s()" % [file, line, function]
	record(kind, message, source, backtrace, engine_at)


func _log_message(message: String, error: bool) -> void:
	# `printerr` and the engine's print_error: said on stderr, but not through the error path.
	# Plain prints are the game talking, not something going wrong, and are left alone.
	if not error:
		return
	var m := message.strip_edges()
	if m == "" or m.begins_with("ERROR:") or m.begins_with("WARNING:") or m.begins_with("at:") \
			or m.begins_with("SCRIPT ERROR:") or m.begins_with("USER"):
		return
	record("printerr", m, "", "", "")


## One report. Public so a test (or a fallback) can put one in by hand.
func record(kind: String, message: String, source: String, backtrace: String, engine_at: String) -> void:
	var now := Time.get_ticks_msec() - _started_ms
	if not stale_import_seen and is_stale_import(message):
		stale_import_seen = true
		if on_stale_import.is_valid():
			# deferred: this is inside the engine's error path, on any thread
			on_stale_import.call_deferred(message)
	_lock.lock()
	var key := "%s|%s|%s" % [kind, _fold.sub(message, "N", true), source]
	var r: Dictionary = reports.get(key, {})
	if r.is_empty():
		r = {"kind": kind, "message": message, "source": source, "count": 0,
			"first_ms": now, "last_ms": now, "backtrace": backtrace}
		reports[key] = r
	r["count"] = int(r["count"]) + 1
	r["last_ms"] = now
	if kind in totals:
		totals[kind] = int(totals[kind]) + 1
	if int(r["count"]) <= LINES_PER_REPORT and lines_written < LINES_MAX:
		lines_written += 1
		var ev := {"t": snappedf(now / 1000.0, 0.001), "kind": kind, "message": message, "source": source}
		if engine_at != "" and engine_at != source:
			ev["engine"] = engine_at
		if backtrace != "" and int(r["count"]) == 1:
			ev["backtrace"] = backtrace
		if int(r["count"]) == LINES_PER_REPORT:
			ev["note"] = "said %d times; later ones are only counted" % LINES_PER_REPORT
		pending_lines.append(JSON.stringify(ev))
	dirty = true
	_lock.unlock()


## What an import cache out of step with the checkout says: a model's imported scene naming a
## texture that has since been renamed or removed, a cached scene that will not load, or a UID the
## editor's cache has never heard of. None of it is the game's to fix while it runs; the editor
## reimports it when told to.
static func is_stale_import(message: String) -> bool:
	return (message.begins_with("Failed loading resource: res://.godot/imported/")
		or (message.contains("invalid UID") and message.contains("using text path instead")))


## The session file's new lines and a copy of the reports, taken under the lock, for the writer.
func take() -> Dictionary:
	_lock.lock()
	var out := {"lines": pending_lines, "reports": reports.values().map(func(r: Dictionary) -> Dictionary: return r.duplicate()),
		"totals": totals.duplicate(), "dirty": dirty}
	pending_lines = PackedStringArray()
	dirty = false
	_lock.unlock()
	return out
