extends TestCase
## Safe mode (core/safe_mode.gd, core/startup.gd): a launch that never got its menu going makes the
## next start on the coarse ground with the drawn chart behind the title, says so there, and stays
## that way until the player turns the full terrain back on. Tools, tests and headless runs are
## never touched. The sentinel is written to a file of the test's own.

const MENU := preload("res://ui/menus/main_menu.tscn")

var _path := ""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_path = "user://tests_launch_state_%d.json" % OS.get_process_id()


func after_each() -> void:
	SafeMode.pinned = false
	SafeMode.set_active(false)
	WorldStatus.override = {}
	for p in [_path, _path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func _args(a: Array) -> PackedStringArray:
	return PackedStringArray(a)


func test_a_launch_that_never_reached_its_menu_makes_the_next_one_safe() -> void:
	for state in ["starting", "stalled"]:
		var v := SafeMode.decide({"state": state}, _args([]), true, true)
		assert_true(bool(v["safe"]), "%s last time: safe" % state)
		assert_eq(v["why"], "last_launch")
		assert_false(bool(v["pinned"]), "and the setting can end it")
	for state in ["menu_ok", "clean_exit"]:
		assert_false(bool(SafeMode.decide({"state": state}, _args([]), true, true)["safe"]), "%s last time: not safe" % state)
	assert_false(bool(SafeMode.decide({}, _args([]), true, true)["safe"]), "a first launch ever is not safe")


func test_the_setting_off_is_safe_and_stays_the_players() -> void:
	var v := SafeMode.decide({"state": "menu_ok"}, _args([]), false, true)
	assert_true(bool(v["safe"]), "two good safe launches do not switch the full terrain back on")
	assert_eq(v["why"], "setting")


func test_the_command_line_decides_first() -> void:
	var on := SafeMode.decide({"state": "clean_exit"}, _args(["--safe-mode"]), true, true)
	assert_true(bool(on["safe"]) and bool(on["pinned"]), "--safe-mode forces it")
	assert_eq(on["why"], "asked")
	var off := SafeMode.decide({"state": "starting"}, _args(["--no-safe-mode"]), true, true)
	assert_false(bool(off["safe"]), "--no-safe-mode skips the check")
	var t3d := SafeMode.decide({"state": "starting"}, _args(["--terrain=terrain3d"]), false, true)
	assert_false(bool(t3d["safe"]), "--terrain=terrain3d takes the risk")
	assert_true(bool(t3d["pinned"]))
	assert_false(bool(SafeMode.decide({"state": "starting"}, _args([]), true, false)["safe"]),
			"a run that does not check never reads an unclean sentinel as a reason")


func test_tools_tests_and_headless_runs_skip_the_check() -> void:
	assert_true(SafeMode.skips_check(_args([]), _args([]), true, false), "headless")
	assert_true(SafeMode.skips_check(_args([]), _args([]), false, true), "the editor's debugger")
	assert_true(SafeMode.skips_check(_args(["--flow=/tmp/f"]), _args([]), false, false), "a tool's argument")
	assert_true(SafeMode.skips_check(_args(["--capture=title"]), _args([]), false, false))
	assert_true(SafeMode.skips_check(_args([]), _args(["--path", "game", "res://tests/run_tests.tscn"]), false, false), "a scene of its own")
	assert_true(SafeMode.skips_check(_args([]), _args(["-s", "res://tools_gd/x.gd"]), false, false), "a script")
	assert_false(SafeMode.skips_check(_args([]), _args(["--path", "game"]), false, false), "a player's launch")
	assert_false(SafeMode.skips_check(_args(["--terrain=fallback", "--safe-mode", "--no-safe-mode"]),
			_args(["--rendering-driver", "d3d12"]), false, false), "a player's arguments")
	assert_true(SafeMode.skips_check(_args([]), OS.get_cmdline_args(), DisplayServer.get_name() == "headless", EngineDebugger.is_active()),
			"this run (the suite) skips it")


func test_the_sentinel_round_trips_and_a_torn_one_reads_as_nothing() -> void:
	assert_eq(SafeMode.read_state(_path), {}, "none there")
	assert_true(SafeMode.write_state({"state": "starting", "step": "boot"}, _path))
	assert_eq(str(SafeMode.read_state(_path).get("state", "")), "starting")
	assert_true(SafeMode.write_state({"state": "menu_ok", "step": "x"}, _path), "written over")
	assert_eq(str(SafeMode.read_state(_path).get("state", "")), "menu_ok")
	assert_false(FileAccess.file_exists(_path + ".tmp"), "no temporary left beside it")
	var f := FileAccess.open(_path, FileAccess.WRITE)
	f.store_string("{\"state\": \"sta")
	f.close()
	assert_eq(SafeMode.read_state(_path), {}, "half a file is no verdict")


func test_safe_mode_is_the_coarse_ground_one_read_and_no_country() -> void:
	SafeMode.set_active(true, "last_launch")
	assert_true(WorldStatus.force_fallback, "the coarse ground")
	assert_eq(ThreadedLoads.limit(), 1, "one threaded read at a time")
	assert_false(TitleVista.switched_on(), "no country behind the title")
	var s := WorldStatus.current()
	assert_eq(s["reason"], "safe_mode")
	assert_eq(s["terrain"], "fallback")
	assert_false(bool(s["announce"]), "the title says it in its own line, not across the sheet")
	SafeMode.set_active(false)
	assert_false(WorldStatus.force_fallback)
	assert_true(ThreadedLoads.limit() > 1 or ThreadedLoads.pool_size() <= 3, "the machine's own limit again")


func test_the_setting_follows_unless_the_command_line_pinned_it() -> void:
	SafeMode.follow_setting(false)
	assert_true(SafeMode.active, "off is safe")
	assert_eq(SafeMode.why, "setting")
	SafeMode.follow_setting(true)
	assert_false(SafeMode.active, "and on leaves it")
	SafeMode.pinned = true
	SafeMode.set_active(true, "asked")
	SafeMode.follow_setting(true)
	assert_true(SafeMode.active, "--safe-mode holds for the launch")


func test_the_title_says_why_in_one_line_and_shows_no_country() -> void:
	SafeMode.set_active(true, "last_launch")
	var menu: Control = MENU.instantiate()
	_tree().root.add_child(menu)
	await _tree().process_frame
	assert_eq(menu.get("notice"), null, "no account across the sheet")
	assert_eq(menu.get("vista"), null, "no country behind it")
	var line: Label = menu.get("ground_line")
	assert_true(line != null and line.text.contains("did not start properly last time"), "the line says why")
	assert_true(line != null and line.text.contains("Graphics settings"), "and the way back")
	menu.queue_free()
	await _tree().process_frame


func test_the_region_reads_never_take_the_whole_pool() -> void:
	for pool in [4, 5, 6, 8, 12, 16, 32]:
		var tasks := World.region_read_tasks(pool, 16)
		# ThreadedLoads.limit() with those threads reserved
		var loads := clampi(pool - 2 - tasks, 1, 4)
		assert_true(tasks >= 1 and tasks + loads <= pool - 2,
				"%d threads: %d region readers and %d loads leave two for a compile" % [pool, tasks, loads])
	assert_eq(World.region_read_tasks(2, 16), 1, "one reader on the smallest pool")
	assert_eq(World.region_read_tasks(32, 3), 3, "no more readers than files")
	var before := ThreadedLoads.limit()
	ThreadedLoads.reserved = 1
	assert_true(ThreadedLoads.limit() == maxi(before - 1, 1) or before == 4, "the reserved threads come off the limit here")
	ThreadedLoads.reserved = 0
	assert_eq(ThreadedLoads.limit(), before)
