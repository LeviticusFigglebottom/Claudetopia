extends SceneTree
## The Godot half of `tools/debug/warning_census.py`, run by it as
##
##   godot --headless --path game --script tools/debug/warning_census.gd -- --levels
##   godot --headless --path game --script tools/debug/warning_census.gd
##
## With `--levels` it prints every GDScript warning setting and its level (0 off, 1 warn, 2
## error), one `LEVEL <setting> <level>` line each, which is how the census learns which warnings
## the project leaves at "warn". Without it, it compiles every script under res:// afresh, each
## under a stand-in path (res://__census__/<its own path>) with its `class_name` commented out so
## the copy does not hide the real class. With the census's override.cfg in place, which makes
## every warn-level warning an error, the log names each warning the analyzer finds, with the
## stand-in path and line. It changes nothing on disk.

const STAND_IN := "res://__census__/"


func _walk(dir: String, out: Array[String]) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n.begins_with("."):
			n = da.get_next()
			continue
		var p := dir.path_join(n)
		if da.current_is_dir():
			if n != "addons":
				_walk(p, out)
		elif n.ends_with(".gd"):
			out.append(p)
		n = da.get_next()
	da.list_dir_end()


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--levels"):
		for p in ProjectSettings.get_property_list():
			var setting := str(p["name"])
			if setting.begins_with("debug/gdscript/warnings/"):
				var v: Variant = ProjectSettings.get_setting(setting)
				if typeof(v) == TYPE_INT:
					print("LEVEL %s %d" % [setting, int(v)])
		quit(0)
		return
	var files: Array[String] = []
	_walk("res://", files)
	print("CENSUS compiling %d scripts" % files.size())
	for path in files:
		var copy := GDScript.new()
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			if lines[i].begins_with("class_name "):
				lines[i] = "# " + lines[i]
		copy.source_code = "\n".join(lines)
		copy.resource_path = STAND_IN + path.trim_prefix("res://")
		copy.reload()
	print("CENSUS done")
	quit(0)
