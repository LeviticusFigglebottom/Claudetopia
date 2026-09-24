extends Node
## ErrorLog: every error and warning a play session reports, written to a file a player can send.
##
## The editor's debugger lists them but will not let them be copied out, and a player without the
## editor never sees them at all. This listens to the engine itself (a `Logger` hung on it with
## OS.add_logger), so it hears what the debugger hears -- the engine's own errors and warnings,
## SCRIPT ERRORs, every `push_error` / `push_warning` (which `Log.error` / `Log.warn` call) -- and
## writes two files into user://logs:
##
##   session_<date>_<time>.jsonl        one line per report, as it happened
##   session_<date>_<time>_summary.txt  the machine, then each report once: how many times, when
##                                      first and last, where from, one backtrace; most first
##
## The summary is written every 30 seconds while there is something new, and when the game ends,
## so a crash still leaves the last half-minute's. The last ten sessions are kept.
##
## Costs nothing while nothing goes wrong: the engine calls in only when there is something to
## say, the same report said a thousand times is one entry with a count, and the writer does
## nothing on a tick with nothing new.
##
## A headless run (the tests, the tools) listens but writes no files, so it cannot push the
## player's own sessions out of the ten; pass `-- --errorlog` to make one write them anyway.

const DIR := "user://logs"
const KEEP_SESSIONS := 10
const FLUSH_SECONDS := 30.0
const SINK_PATH := "res://core/error_log_sink.gd"
const STALE_IMPORT_NOTE := ("Stale import cache: some models were imported from older files than these, so they load "
	+ "without their textures or not at all. Close the editor, delete the game/.godot folder (or at least "
	+ "game/.godot/imported and game/.godot/uid_cache.bin), and open the project again; it reimports everything.")

## Whether the engine could be listened to (Godot 4.5 and later).
var listening := false
## Whether this session writes files (not in a headless run unless asked).
var writing := false
var session_name := ""
var jsonl_path := ""
var summary_path := ""

var _dir := DIR
var _sink: RefCounted = null
var _jsonl: FileAccess = null
var _reports: Array = []
var _totals := {}
var _started_unix := 0.0
var _started_ms := 0
var _timer: Timer = null
var _ended := false


func _init() -> void:
	_started_ms = Time.get_ticks_msec()
	_started_unix = Time.get_unix_time_from_system()
	# as early as an autoload can: the errors of every autoload after this one are heard
	_listen()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var asked := "--errorlog" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" or asked:
		begin(DIR)
	_timer = Timer.new()
	_timer.wait_time = FLUSH_SECONDS
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.timeout.connect(func() -> void: flush(false))
	add_child(_timer)
	_timer.start()


func _listen() -> void:
	if _sink != null:
		return
	if not ClassDB.class_exists("Logger") or not OS.has_method("add_logger"):
		return
	var script: Script = load(SINK_PATH)
	if script == null:
		return
	_sink = script.new()
	_sink.set("on_stale_import", _on_stale_import)
	OS.call("add_logger", _sink)
	listening = true


## Start writing this session's files into `dir`. The autoload does it for user://logs; a test
## does it for a folder of its own.
func begin(dir: String) -> void:
	_dir = dir
	DirAccess.make_dir_recursive_absolute(_dir)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	session_name = "session_%s" % stamp
	# two sessions started in the same second (a test, a relaunch) do not share a file
	var n := 1
	while FileAccess.file_exists("%s/%s.jsonl" % [_dir, session_name]):
		n += 1
		session_name = "session_%s_%d" % [stamp, n]
	jsonl_path = "%s/%s.jsonl" % [_dir, session_name]
	summary_path = "%s/%s_summary.txt" % [_dir, session_name]
	_jsonl = FileAccess.open(jsonl_path, FileAccess.WRITE)
	writing = _jsonl != null
	if writing:
		_prune()
		flush(true)


## Write what is new: the session file's lines, and the summary over again. `force` writes the
## summary even when nothing is new (the first one, and the last).
func flush(force := false) -> void:
	if _sink == null and not force:
		return
	var got: Dictionary = _sink.call("take") if _sink != null else {"lines": PackedStringArray(), "reports": [], "totals": {}, "dirty": false}
	if not got["dirty"] and not force:
		return
	_reports = got["reports"]
	_totals = got["totals"]
	if not writing:
		return
	if _jsonl != null:
		for l: String in got["lines"]:
			_jsonl.store_line(l)
		_jsonl.flush()
	var f := FileAccess.open(summary_path, FileAccess.WRITE)
	if f != null:
		f.store_string(summary_text())
		f.close()


## The summary, as the file has it.
func summary_text() -> String:
	var out := PackedStringArray()
	out.append("Wickmere error log: %s" % session_name)
	out.append("")
	for pair in header():
		out.append("%-14s %s" % [str(pair[0]) + ":", str(pair[1])])
	out.append("")
	if not listening:
		out.append("This engine cannot be listened to (it has no Logger class; Godot 4.5 or later has one).")
		out.append("The game's own count: %d errors, %d warnings." % [_log_count("error_count"), _log_count("warning_count")])
		return "\n".join(out) + "\n"
	out.append("Totals: %d errors, %d script errors, %d shader errors, %d warnings, %d on stderr" % [
		int(_totals.get("error", 0)), int(_totals.get("script_error", 0)), int(_totals.get("shader_error", 0)),
		int(_totals.get("warning", 0)), int(_totals.get("printerr", 0))])
	out.append("Distinct: %d" % _reports.size())
	out.append("")
	if _sink != null and bool(_sink.get("stale_import_seen")):
		out.append(STALE_IMPORT_NOTE)
		out.append("")
	for r: Dictionary in sorted_reports():
		out.append("x%-5d %-12s %s" % [int(r["count"]), str(r["kind"]).to_upper(), str(r["message"])])
		if str(r["source"]) != "":
			out.append("       from   %s" % r["source"])
		out.append("       first  %s   last %s" % [_clock(int(r["first_ms"])), _clock(int(r["last_ms"]))])
		if str(r["backtrace"]) != "":
			for bl in str(r["backtrace"]).strip_edges().split("\n"):
				out.append("       | %s" % bl)
		out.append("")
	if _reports.is_empty():
		out.append("Nothing went wrong.")
	return "\n".join(out) + "\n"


## Most said first; errors before warnings at the same count.
func sorted_reports() -> Array:
	var rs := _reports.duplicate()
	rs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["count"]) != int(b["count"]):
			return int(a["count"]) > int(b["count"])
		return _rank(str(a["kind"])) < _rank(str(b["kind"])))
	return rs


func _rank(kind: String) -> int:
	return ["script_error", "error", "shader_error", "warning", "printerr"].find(kind)


## The machine and the build, for whoever reads the file without the machine in front of them.
func header() -> Array:
	var info := Engine.get_version_info()
	var driver_info := OS.get_video_adapter_driver_info()
	var preset: Variant = "?"
	var settings := _autoload("Settings")
	if settings != null and settings.has_method("get_value"):
		preset = settings.call("get_value", "graphics", "preset", "?")
	var played := (Time.get_ticks_msec() - _started_ms) / 1000.0
	return [
		["Game", "%s %s" % [ProjectSettings.get_setting("application/config/name", "Wickmere"),
			ProjectSettings.get_setting("application/config/version", "")]],
		["Commit", game_commit()],
		["Started", Time.get_datetime_string_from_unix_time(int(_started_unix), true) + " UTC"],
		["Played", _clock(int(played * 1000.0))],
		["Godot", "%s (%s)" % [info.get("string", "?"), "debug" if OS.is_debug_build() else "release"]],
		["OS", "%s %s" % [OS.get_name(), OS.get_version()]],
		["Renderer", "%s, %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()]],
		["GPU", "%s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()]],
		["Graphics API", RenderingServer.get_video_adapter_api_version()],
		["Driver", " ".join(driver_info) if not driver_info.is_empty() else "?"],
		["Preset", preset],
		["Display", "%s, %s" % [DisplayServer.get_name(), str(DisplayServer.window_get_size())]],
		["Build", ("run from the editor" if EngineDebugger.is_active() else "editor binary, no debugger")
			if OS.has_feature("editor") else "exported"],
	]


## The commit the game was built from, when it can be known: a build_commit.txt shipped with an
## export, or the git checkout the editor is running from.
func game_commit() -> String:
	if FileAccess.file_exists("res://build_commit.txt"):
		return _read("res://build_commit.txt")
	if not OS.has_feature("editor"):
		return "unknown"
	var git := ProjectSettings.globalize_path("res://").path_join("../.git")
	var common := git
	if FileAccess.file_exists(git):
		# a worktree: .git is a file naming the real one
		var pointer := _read(git)
		if not pointer.begins_with("gitdir:"):
			return "unknown"
		git = pointer.substr(7).strip_edges()
		if git.is_relative_path():
			git = ProjectSettings.globalize_path("res://").path_join("..").path_join(git)
		common = git
		if FileAccess.file_exists(git.path_join("commondir")):
			var c := _read(git.path_join("commondir"))
			common = git.path_join(c) if c.is_relative_path() else c
	var head := _read(git.path_join("HEAD"))
	if head == "":
		return "unknown"
	if not head.begins_with("ref:"):
		return head.left(12)
	var ref := head.substr(4).strip_edges()
	for base in [git, common]:
		var sha := _read(str(base).path_join(ref))
		if sha != "":
			return "%s (%s)" % [sha.left(12), ref.trim_prefix("refs/heads/")]
	for l in _read(common.path_join("packed-refs")).split("\n"):
		if l.ends_with(" " + ref):
			return "%s (%s)" % [l.left(12), ref.trim_prefix("refs/heads/")]
	return "unknown (%s)" % ref


## The console's `errors`: where the file is, the totals, and the ten most said.
func report(top := 10) -> String:
	flush(true)
	var out := PackedStringArray()
	# the totals first: the console's `errors` has always answered with its counts on the first line
	if listening:
		out.append("errors %d  script errors %d  warnings %d  distinct %d" % [int(_totals.get("error", 0)),
			int(_totals.get("script_error", 0)), int(_totals.get("warning", 0)), _reports.size()])
	else:
		out.append("errors %d  warnings %d  (the game's own count: the engine cannot be listened to here)" % [
			_log_count("error_count"), _log_count("warning_count")])
	if writing:
		out.append("summary: %s" % ProjectSettings.globalize_path(summary_path))
	else:
		out.append("not writing files this session (headless); folder: %s" % ProjectSettings.globalize_path(_dir))
	if not listening:
		return "\n".join(out)
	var rs := sorted_reports()
	for i in mini(top, rs.size()):
		var r: Dictionary = rs[i]
		out.append("x%d %s %s  <- %s" % [int(r["count"]), r["kind"], str(r["message"]).left(140), r["source"]])
	return "\n".join(out)


## Said once, in words, when the engine first reports an import cache older than the checkout:
## the hundreds of "invalid UID" and "Failed loading resource: res://.godot/imported/..." lines
## that follow a pull the editor has not caught up with all have the one cure.
func _on_stale_import(first_report: String) -> void:
	var l := _autoload("Log")
	if l != null and l.has_method("warn"):
		l.call("warn", "Assets", STALE_IMPORT_NOTE + " (first sign: %s)" % first_report.left(200))
	else:
		push_warning("[Assets] " + STALE_IMPORT_NOTE)


## The folder, in the system's file browser.
func open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	OS.shell_open(ProjectSettings.globalize_path(DIR))


func count(kind: String) -> int:
	flush(false)
	return int(_totals.get(kind, 0))


## Stop listening and close the files. The autoload does it when the game ends; a test, when it
## is done with the one it made.
func end() -> void:
	if _ended:
		return
	_ended = true
	flush(true)
	if _jsonl != null:
		_jsonl.close()
		_jsonl = null
	if _sink != null and OS.has_method("remove_logger"):
		OS.call("remove_logger", _sink)
	_sink = null


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_CRASH:
			flush(true)
		NOTIFICATION_EXIT_TREE, NOTIFICATION_PREDELETE:
			end()


func _prune() -> void:
	var sessions: Array[String] = []
	for f in DirAccess.get_files_at(_dir):
		if f.begins_with("session_") and f.ends_with(".jsonl"):
			sessions.append(f.trim_suffix(".jsonl"))
	sessions.sort()
	while sessions.size() > KEEP_SESSIONS:
		var old: String = sessions.pop_front()
		DirAccess.remove_absolute("%s/%s.jsonl" % [_dir, old])
		DirAccess.remove_absolute("%s/%s_summary.txt" % [_dir, old])


## A file's text, or "" without a word when it is not there: an error log must not log errors of
## its own looking for a commit it may not have.
func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).strip_edges()


## Another autoload, asked of the tree rather than of this node, which a test makes without
## putting it in the tree.
func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree != null else null


func _log_count(field: String) -> int:
	var l := _autoload("Log")
	return int(l.get(field)) if l != null else 0


func _clock(ms: int) -> String:
	var s := maxi(ms, 0) / 1000.0
	return "%d:%02d:%02d" % [floori(s / 3600.0), floori(s / 60.0) % 60, floori(s) % 60]
