extends SceneTree
## Headless parse/compile check for every GDScript under the given res:// folders.
## Run: godot --headless --path game -s res://tools_gd/check_scripts.gd -- actors systems tests
## Exits 1 when any script fails to load (parse errors are printed by the engine).

func _initialize() -> void:
	# _initialize (not _init) so the autoload singletons exist when scripts compile.
	var roots: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			roots.append("res://" + a.trim_prefix("res://"))
	if roots.is_empty():
		roots = ["res://actors", "res://systems", "res://tests", "res://ui", "res://core", "res://tools_gd"]
	var failed := 0
	var count := 0
	for root in roots:
		for path in _list(root):
			count += 1
			var script: Variant = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
			if script == null or not (script as GDScript).can_instantiate() and not (script as GDScript).is_abstract():
				var ok := script != null and (script as GDScript).reload() == OK
				if not ok:
					print("CHECK FAIL: %s" % path)
					failed += 1
	print("checked %d scripts, %d failed" % [count, failed])
	quit(1 if failed > 0 else 0)


func _list(dir: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append("%s/%s" % [dir, f])
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		out.append_array(_list("%s/%s" % [dir, d]))
	out.sort()
	return out
