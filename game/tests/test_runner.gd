extends Node
## Discovers res://tests/unit/test_*.gd, runs every test_* method, prints a report, exits
## with 0 on success or 1 on failure. Run: godot --headless --path game res://tests/run_tests.tscn
## Filter: -- --filter=substring

func _ready() -> void:
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	# Leave the scene-setup frame so tests may add nodes to the root freely.
	await get_tree().process_frame
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
	var failures: Array[String] = []
	var t0 := Time.get_ticks_msec()
	for path in files:
		var script: GDScript = load(path)
		if script == null:
			failures.append("%s: failed to load" % path)
			failed += 1
			continue
		if not script.can_instantiate():
			failures.append("%s: script did not compile" % path)
			failed += 1
			continue
		var inst: TestCase = script.new()
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not name.contains(filter) and not path.contains(filter):
				continue
			total += 1
			inst._current = "%s.%s" % [path.get_file().get_basename(), name]
			var before := inst._failures.size()
			if inst.has_method("before_each"):
				inst.before_each()
			await inst.call(name)
			if inst.has_method("after_each"):
				inst.after_each()
			await get_tree().process_frame
			if inst._failures.size() > before:
				failed += 1
				print("  FAIL %s" % inst._current)
			else:
				print("  ok   %s" % inst._current)
		failures.append_array(inst._failures)
	var ms := Time.get_ticks_msec() - t0
	print("")
	for f in failures:
		print("FAILURE: %s" % f)
	print("%d tests, %d failed, %d content problems, %d ms" % [total, failed, ContentDB.problems.size(), ms])
	for p in ContentDB.problems:
		print("CONTENT: %s" % p)
	var code := 0 if (failed == 0 and ContentDB.problems.is_empty()) else 1
	print("RESULT: %s" % ("PASS" if code == 0 else "FAIL"))
	get_tree().quit(code)
