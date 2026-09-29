extends Node
## Discovers res://tests/unit/test_*.gd, runs every test_* method, prints a report, exits
## with 0 on success or 1 on failure. Run: godot --headless --path game res://tests/run_tests.tscn
## Filter: -- --filter=substring (several, comma-separated: any of them)
##
## A run that logs errors is not a passing run. Two kinds are counted and neither is free:
##
## * The errors the game logs itself (`Log.error`) are counted per test, so the report names the
##   test that caused each one instead of leaving a number at the bottom. A test that provokes
##   one on purpose -- driving a refusal path, where the error *is* the evidence it refused --
##   says so in ERRORS_ALLOWED below, and anything not named there fails the run.
## A test that leaves a screen open is reported the same way, and the screen is closed and the
## world unpaused before the next test runs: a full-screen screen pauses the world, an Area3D
## flushes its overlaps on the physics step, and one leftover screen therefore freezes the physics
## of everything after it -- which then passes or fails for reasons of its own that are not its own.
##
## * The engine's own SCRIPT ERRORs cannot be counted from inside GDScript: there is no API for
##   it, and the honest count is the one on stderr, so `run.sh test` greps for them and fails
##   the run. That is not bookkeeping. An invalid call abandons the rest of the function it is
##   in, so a script error inside a test means the assertions after it never ran, and three
##   tests in this suite were printing ok with half of their bodies unexecuted.

## Tests that make the game log an error on purpose. The count is exact: one more than this and
## the run goes red, because the extra one is nobody's intention.
const ERRORS_ALLOWED := {
	# Handing an item nobody has defined to a real bag: `add()` returns null and says why.
	"test_economy_integration.test_give_and_take_against_the_real_inventory": 1,
	# Walking into an interior that does not exist. This one asserts the error itself.
	"test_interiors.test_unknown_interior_refused": 1,
	"test_inventory_bag.test_add_rejects_unknown_items": 1,
	# Loading a save slot that is not there. This one asserts the error is said exactly once.
	"test_player_body.test_a_missing_slot_is_reported_not_crashed": 1,
}

func _ready() -> void:
	# Tests change settings in memory -- a render scale, a rebound key -- and the player's
	# settings.cfg is the same file the game and the capture tools read. Nothing a test sets may
	# reach it.
	Settings.persist = false
	# and every test starts from the shipped settings: a settings.cfg another run left in user://
	# (every worktree once shared one) must not decide a result. Said, then put right in memory.
	var off := Settings.off_default(Settings.data)
	if not off.is_empty():
		print("SETTINGS | came in off their shipped defaults (%s); the suite runs on the shipped ones" % ", ".join(PackedStringArray(off)))
		Settings.data = Settings.DEFAULTS.duplicate(true)
		Settings.apply_all()
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	# Leave the scene-setup frame so tests may add nodes to the root freely.
	await get_tree().process_frame
	# this run's slots in a folder of its own, away from the player's and any other run's
	var save_dir := "%s/tests_%d" % [SaveSystem.SAVE_DIR, OS.get_process_id()]
	SaveSystem.use_save_dir(save_dir)
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests/unit"):
		if f.begins_with("test_") and (f.ends_with(".gd") or f.ends_with(".gd.remap")):
			files.append("res://tests/unit/" + f.trim_suffix(".remap"))
	files.sort()
	var total := 0
	var failed := 0
	var skipped: Array[String] = []
	var failures: Array[String] = []
	var logged_total := 0
	var noisy: Array[String] = []
	var paused_by: Array[String] = []
	var t0 := Time.get_ticks_msec()
	for path in files:
		var script: GDScript = load(path)
		# A script with a parse error still loads, as a GDScript that cannot be instantiated;
		# calling new() on it takes the whole run down instead of failing that one file.
		if script == null or not script.can_instantiate():
			failures.append("%s: failed to load (parse error?)" % path)
			failed += 1
			print("  FAIL %s (did not compile)" % path)
			continue
		if not script.can_instantiate():
			failures.append("%s: script did not compile" % path)
			failed += 1
			continue
		var made: Variant = script.new()
		if made == null or not (made is TestCase):
			failures.append("%s: does not instance a TestCase (parse error?)" % path)
			failed += 1
			continue
		var inst: TestCase = made
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not _passes(filter, name, path):
				continue
			total += 1
			inst._current = "%s.%s" % [path.get_file().get_basename(), name]
			var before := inst._failures.size()
			var skips_before := inst._skips.size()
			var errors_before := Log.error_count
			if inst.has_method("before_each"):
				inst.before_each()
			await inst.call(name)
			if inst.has_method("after_each"):
				inst.after_each()
			await get_tree().process_frame
			# Eight tests walk up to a board, a shop, a chest or a book and the real event opens
			# the real screen, which is exactly what they are for. A full-screen screen pauses the
			# world, though, and an Area3D flushes its overlaps on the physics step -- so a screen
			# left open freezes the physics of every test after it, and those tests then pass or
			# fail for reasons that have nothing to do with them. Putting the UI back is the
			# harness's job, not eight authors'; the one that left it open is named.
			var left_open := 0
			while UI.is_menu_open() and left_open < 16:
				UI.close()
				left_open += 1
			if get_tree().paused:
				get_tree().paused = false
				if left_open == 0:
					left_open = -1        # paused with nothing open: rarer, and worth saying so
			if left_open != 0:
				paused_by.append("%s left %s" % [inst._current,
					"the world paused with no screen open" if left_open < 0
					else "%d screen%s open, and the world paused behind %s" % [
						left_open, "" if left_open == 1 else "s", "it" if left_open == 1 else "them"]])
			var logged := Log.error_count - errors_before
			logged_total += logged
			var allowed := int(ERRORS_ALLOWED.get(inst._current, 0))
			if logged > allowed:
				noisy.append("%s logged %d error%s%s" % [inst._current, logged,
					"" if logged == 1 else "s",
					" (%d expected)" % allowed if allowed > 0 else ""])
			if inst._failures.size() > before:
				failed += 1
				print("  FAIL %s" % inst._current)
			elif inst._skips.size() > skips_before:
				skipped.append(inst._skips[-1])
				print("  skip %s" % inst._skips[-1])
			else:
				print("  ok   %s" % inst._current)
		failures.append_array(inst._failures)
	var ms := Time.get_ticks_msec() - t0
	print("")
	for f in failures:
		print("FAILURE: %s" % f)
	for n in noisy:
		print("ERRORS: %s" % n)
	# Reported rather than fatal: the screens are closed and the world unpaused between tests, so
	# nothing after them is measuring a frozen physics step and there is nothing left to fail the
	# run for. A test may still shut its own screens, as `test_crafting_station` does.
	for n in paused_by:
		print("PAUSED: %s" % n)
	# A test that could not run here is not a pass: it is counted and named, reason and all.
	for sk in skipped:
		print("SKIPPED: %s" % sk)
	print("%d tests, %d failed, %d skipped, %d content problems, %d logged errors, %d left the world paused, %d ms" % [
		total, failed, skipped.size(), ContentDB.problems.size(), logged_total, paused_by.size(), ms])
	for p in ContentDB.problems:
		print("CONTENT: %s" % p)
	# Audio autoloads hold open stream decoders while they play. Releasing them here keeps a
	# test run from ending on Godot's "resources still in use" error, which the smoke check
	# reads as a failure. It is not completely reliable: AudioServer drops a stopped player's
	# playback on its own schedule, so a run can still end with that message even though every
	# player has been stopped and emptied. The exit code is unaffected.
	for autoload_name in ["Music", "Ambience", "Foley"]:
		var node := get_node_or_null("/root/" + autoload_name)
		if node and node.has_method("release"):
			node.release()
	# AudioServer drops a stopped player's stream playback on its next update, so quitting in
	# the same frame as the release leaves those playbacks (and the streams they reference)
	# alive, which the engine then reports as leaked resources at exit.
	for i in 3:
		await get_tree().process_frame
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute("%s/%s" % [save_dir, f])
	DirAccess.remove_absolute(save_dir)
	var code := 0 if (failed == 0 and ContentDB.problems.is_empty() and noisy.is_empty()) else 1
	print("RESULT: %s" % ("PASS" if code == 0 else "FAIL"))
	get_tree().quit(code)


## Whether a test is in the run: its name or its file contains one of the filter's comma-separated
## substrings.
static func _passes(filter: String, name: String, path: String) -> bool:
	for part in filter.split(",", false):
		if name.contains(part) or path.contains(part):
			return true
	return false
