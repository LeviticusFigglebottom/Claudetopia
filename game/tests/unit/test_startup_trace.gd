extends TestCase
## The startup trace (core/startup_trace.gd): a line a step, on disk at once, the last ten files
## kept, and nothing written once the game has started. A folder of the test's own.

var _dir := ""


func before_each() -> void:
	_dir = "user://tests_startup_trace_%d" % OS.get_process_id()
	StartupTrace.echo = false


func after_each() -> void:
	StartupTrace.close()
	StartupTrace.path = ""
	StartupTrace.echo = true
	if not DirAccess.dir_exists_absolute(_dir):
		return
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute("%s/%s" % [_dir, f])
	DirAccess.remove_absolute(_dir)


func test_each_step_is_on_disk_before_the_next() -> void:
	var path := StartupTrace.begin(_dir)
	assert_true(path.begins_with(_dir + "/startup_") and path.ends_with(".txt"), path)
	StartupTrace.step("boot")
	StartupTrace.step("world: terrain step begins")
	# read back while the file is still open: a game killed now has these lines
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	assert_eq(lines.size(), 2)
	assert_true(lines[1].contains("world: terrain step begins"), lines[1])
	assert_true(lines[1].contains("main") and lines[1].contains("static ") and lines[1].contains(" MB"), "the thread and the memory: " + lines[1])
	assert_eq(StartupTrace.last(), "world: terrain step begins", "the watchdog's step")


func test_a_worker_threads_line_says_which_thread() -> void:
	var path := StartupTrace.begin(_dir)
	var id := WorkerThreadPool.add_task(func() -> void: StartupTrace.step("terrain: region x read begins"))
	WorkerThreadPool.wait_for_task_completion(id)
	var text := FileAccess.get_file_as_string(path)
	assert_true(text.contains("terrain: region x read begins"), text)
	assert_false(text.contains(" main "), "not the main thread: " + text)
	assert_ne(StartupTrace.last(), "terrain: region x read begins", "a worker's line is not where the main thread stopped")


func test_after_finish_steps_cost_nothing_but_the_watchdog_still_writes() -> void:
	var path := StartupTrace.begin(_dir)
	StartupTrace.finish("the title's first shot is shown")
	assert_false(StartupTrace.active)
	StartupTrace.step("world: something later")
	StartupTrace.note("WATCHDOG: main thread stalled 5 s at step \"x\"")
	var text := FileAccess.get_file_as_string(path)
	assert_true(text.contains("trace ends: the title's first shot is shown"), text)
	assert_false(text.contains("something later"), "nothing after the end")
	assert_true(text.contains("WATCHDOG"), "but the watchdog's line")


func test_only_the_last_ten_are_kept() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	for i in 12:
		var f := FileAccess.open("%s/startup_2000-01-01_00-00-%02d.txt" % [_dir, i], FileAccess.WRITE)
		f.store_line("old")
		f.close()
	var other := FileAccess.open("%s/session_2000-01-01_00-00-00.jsonl" % _dir, FileAccess.WRITE)
	other.close()
	var path := StartupTrace.begin(_dir)
	var kept: Array[String] = []
	for f in DirAccess.get_files_at(_dir):
		if f.begins_with("startup_"):
			kept.append(f)
	assert_eq(kept.size(), StartupTrace.KEEP, "ten: %s" % str(kept))
	assert_has(kept, path.get_file(), "this launch's among them")
	assert_false(kept.has("startup_2000-01-01_00-00-00.txt"), "the oldest went")
	assert_true(FileAccess.file_exists("%s/session_2000-01-01_00-00-00.jsonl" % _dir), "the error log's files are not touched")


func test_the_line_format() -> void:
	var l := StartupTrace.format(12.345, 120, "main", "world: water step begins", "static 400 MB")
	assert_eq(l, "[   12.35 s] +   120 ms  main   world: water step begins  | static 400 MB")
