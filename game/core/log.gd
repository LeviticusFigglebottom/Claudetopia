extends Node
## Log: tagged logging with error/warning counters (used by the smoke test to fail on errors).

enum Level { DEBUG, INFO, WARN, ERROR }

var min_level: Level = Level.INFO
var error_count: int = 0
var warning_count: int = 0
var history: Array[String] = []
const HISTORY_MAX := 400
var _file: FileAccess


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://logs")
	_file = FileAccess.open("user://logs/wickmere.log", FileAccess.WRITE)
	info("Log", "Wickmere %s starting (%s, %s)" % [ProjectSettings.get_setting("application/config/version"), OS.get_name(), Engine.get_version_info().string])


func debug(tag: String, msg: String) -> void:
	_emit(Level.DEBUG, tag, msg)


func info(tag: String, msg: String) -> void:
	_emit(Level.INFO, tag, msg)


func warn(tag: String, msg: String) -> void:
	warning_count += 1
	_emit(Level.WARN, tag, msg)
	push_warning("[%s] %s" % [tag, msg])


func error(tag: String, msg: String) -> void:
	error_count += 1
	_emit(Level.ERROR, tag, msg)
	push_error("[%s] %s" % [tag, msg])


func _emit(level: Level, tag: String, msg: String) -> void:
	if level < min_level:
		return
	var line := "%s [%s] %s" % [["D", "I", "W", "E"][level], tag, msg]
	history.append(line)
	if history.size() > HISTORY_MAX:
		history.pop_front()
	if level != Level.ERROR and level != Level.WARN:
		print(line)
	if _file:
		_file.store_line(line)
		_file.flush()
