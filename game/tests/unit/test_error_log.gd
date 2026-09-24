extends TestCase
## ErrorLog: what push_error and push_warning say reaches the player's summary, once per report
## with a count, and the session file line by line. A log of its own in a folder of its own, so the
## player's sessions are not touched.

const ErrorLogScript := preload("res://core/error_log.gd")

var _log: Node = null
var _dir := ""


func before_each() -> void:
	_dir = "user://tests_errorlog_%d" % OS.get_process_id()
	_log = ErrorLogScript.new()


func after_each() -> void:
	if _log != null:
		_log.end()
		_log.free()
		_log = null
	if not DirAccess.dir_exists_absolute(_dir):
		return
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute("%s/%s" % [_dir, f])
	DirAccess.remove_absolute(_dir)


func test_the_engine_can_be_listened_to() -> void:
	assert_true(_log.listening, "Godot 4.5+ has Logger and OS.add_logger; 4.7 must")


func test_push_error_and_push_warning_land_deduped_in_the_summary() -> void:
	if not _log.listening:
		return
	_log.begin(_dir)
	for i in 3:
		push_error("errorlog test: the lamp %d would not light" % i)
	# the same words from the same line: one report (from two lines they would be two)
	for i in 2:
		push_warning("errorlog test: a warning said once")
	_log.flush(true)
	var summary := FileAccess.get_file_as_string(_log.summary_path)
	# three errors differing only by a number are one report counted three times
	assert_true(summary.contains("x3     ERROR        errorlog test: the lamp 0 would not light"), summary.left(1500))
	assert_true(summary.contains("x2     WARNING      errorlog test: a warning said once"), summary.left(1500))
	assert_eq(summary.count("errorlog test: the lamp"), 1, "one line per report, not per time said")
	# and the place that said it is this test, not the engine's push_error
	assert_true(summary.contains("test_error_log.gd"), "the source is the script line: " + summary.left(1500))
	assert_eq(_log.count("error"), 3)
	assert_eq(_log.count("warning"), 2)


func test_the_session_file_has_a_line_each() -> void:
	if not _log.listening:
		return
	_log.begin(_dir)
	push_warning("errorlog test: one")
	push_warning("errorlog test: two")
	_log.flush(false)
	var lines := FileAccess.get_file_as_string(_log.jsonl_path).strip_edges().split("\n")
	assert_eq(lines.size(), 2)
	var first: Variant = JSON.parse_string(lines[0])
	assert_true(first is Dictionary)
	assert_eq(str(first.get("kind", "")), "warning")
	assert_eq(str(first.get("message", "")), "errorlog test: one")


func test_the_summary_says_what_machine_it_was() -> void:
	_log.begin(_dir)
	var summary := FileAccess.get_file_as_string(_log.summary_path)
	for field in ["Godot:", "OS:", "Renderer:", "GPU:", "Driver:", "Preset:", "Commit:", "Played:"]:
		assert_true(summary.contains(field), "header lacks %s" % field)


func test_only_the_last_ten_sessions_are_kept() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	for i in 12:
		for ext in [".jsonl", "_summary.txt"]:
			var f := FileAccess.open("%s/session_2000-01-01_00-00-%02d%s" % [_dir, i, ext], FileAccess.WRITE)
			f.close()
	_log.begin(_dir)
	var sessions := Array(DirAccess.get_files_at(_dir)).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))
	assert_eq(sessions.size(), 10)
	assert_false(sessions.has("session_2000-01-01_00-00-00.jsonl"), "the oldest goes first")
	assert_true(FileAccess.file_exists(_log.jsonl_path), "never this session's own")


func test_a_stale_import_cache_is_recognised() -> void:
	var sink: Script = load("res://core/error_log_sink.gd")
	assert_true(sink.call("is_stale_import", "Failed loading resource: res://.godot/imported/shirt.glb-c399a6.scn."))
	assert_true(sink.call("is_stale_import", "'res://a/b.glb': In external resource #0, invalid UID: 'uid://r0sggv7jywrv' - using text path instead: 'res://a/b_albedo.png'."))
	assert_false(sink.call("is_stale_import", "Failed loading resource: res://assets/models/a.glb."))
