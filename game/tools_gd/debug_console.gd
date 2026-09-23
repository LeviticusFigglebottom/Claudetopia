extends CanvasLayer
## Debug console (autoload `Debug`). Toggle with the `debug_console` action (backquote).
## Systems register commands: Debug.register("give", callable, "give <item_id> [count]").
## Command-line: `-- --cmd="time 13; weather core:weather/fog"` runs after the world is ready.

var _commands: Dictionary = {}     # name -> {callable, help}
var _panel: PanelContainer
var _history: RichTextLabel
var _input: LineEdit
var _open := false
var _pending_cmdline: Array[String] = []
var _lines: Array[String] = []


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # a screen, not a body
	_build_ui()
	_register_builtins()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cmd="):
			for part in a.substr(6).split(";"):
				if not part.strip_edges().is_empty():
					_pending_cmdline.append(part.strip_edges())
	if not _pending_cmdline.is_empty():
		EventBus.player_spawned.connect(func(_p: Node) -> void: _run_pending(), CONNECT_ONE_SHOT)
		get_tree().create_timer(3.0).timeout.connect(_run_pending)


func _run_pending() -> void:
	var cmds := _pending_cmdline.duplicate()
	_pending_cmdline.clear()
	for c in cmds:
		run(c)


func register(name: String, callable: Callable, help := "") -> void:
	_commands[name] = {"callable": callable, "help": help}


func log_line(text: String) -> void:
	_lines.append(text)
	if _lines.size() > 200:
		_lines.pop_front()
	if _history:
		_history.text = "\n".join(_lines)
		_history.scroll_to_line(_history.get_line_count() - 1)
	print("[debug] " + text)


## Runs a command line; returns the output text.
func run(line: String) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var name := parts[0]
	var args := parts.slice(1)
	if not _commands.has(name):
		log_line("unknown command '%s' (try help)" % name)
		return ""
	var result: Variant = (_commands[name]["callable"] as Callable).call(args)
	var text := str(result) if result != null else "ok"
	log_line("> %s\n%s" % [line, text])
	return text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_console"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_open = not _open
	_panel.visible = _open
	if _open:
		_input.grab_focus()
		_input.text = ""


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.45
	_panel.modulate = Color(1, 1, 1, 0.92)
	add_child(_panel)
	var vb := VBoxContainer.new()
	_panel.add_child(vb)
	_history = RichTextLabel.new()
	_history.scroll_following = true
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.bbcode_enabled = false
	vb.add_child(_history)
	_input = LineEdit.new()
	_input.placeholder_text = "command (help)"
	_input.text_submitted.connect(func(t: String) -> void:
		run(t)
		_input.text = "")
	vb.add_child(_input)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


## A teleport through the body's own `teleport` (CONTRACTS §8), which also brings the camera and
## drops the old position's interpolation, rather than a bare write of the position.
func _put(p: Node3D, pos: Vector3) -> void:
	if p.has_method("teleport"):
		p.call("teleport", pos, p.rotation.y)
	else:
		p.global_position = pos


func _register_builtins() -> void:
	register("help", func(_a: Array) -> String:
		var names := _commands.keys()
		names.sort()
		var out: Array[String] = []
		for n in names:
			out.append("%s  %s" % [n, _commands[n]["help"]])
		return "\n".join(out), "list commands")
	register("time", func(a: Array) -> String:
		if a.size() > 0:
			WorldClock.set_time(float(a[0]))
		return WorldClock.formatted(), "time [hours]")
	register("day", func(a: Array) -> String:
		if a.size() > 0:
			WorldClock.day = int(a[0])
		return str(WorldClock.day), "day [n]")
	register("timescale", func(a: Array) -> String:
		if a.size() > 0:
			WorldClock.time_scale = float(a[0])
		return str(WorldClock.time_scale), "timescale [x]")
	register("weather", func(a: Array) -> String:
		var atm := get_tree().get_first_node_in_group("atmosphere")
		if atm == null:
			return "no atmosphere"
		if a.size() > 0:
			var id: String = a[0] if a[0].contains(":") else "core:weather/%s" % a[0]
			atm.force_weather(id, a.size() > 1 and a[1] == "instant")
		return str(atm.current_weather_id()), "weather [id] [instant]")
	register("look", func(_a: Array) -> String:
		var atm := get_tree().get_first_node_in_group("atmosphere")
		if atm == null or not ("state" in atm):
			return "no atmosphere"
		var st: Dictionary = atm.get("state")
		var lk: Dictionary = atm.call("look")
		var msg := "%s: sun %.1f deg, night %.2f, dusk %.2f, haze top %.0f m, weather %s" % [
			str(lk.get("name", "?")), float(st.get("elevation", 0.0)), float(st.get("night", 0.0)),
			float(st.get("dusk", 0.0)), float(st.get("haze_top", 0.0)), str(atm.call("current_weather_id"))]
		return msg, "look (the region's light, the sun's height, night and dusk, the haze top)")
	register("region", func(a: Array) -> String:
		if a.size() > 0:
			var id: String = a[0] if a[0].contains(":") else "core:region/%s" % a[0]
			GameState.enter_region(id)
		return GameState.current_region_id, "region [id] (look only; use tp to move)")
	register("tp", func(a: Array) -> String:
		var p := _player()
		if p == null:
			return "no player"
		if a.size() == 1:
			var id: String = a[0] if a[0].contains(":") else "core:place/%s" % a[0]
			var def := ContentDB.get_or_empty(id)
			if def.is_empty():
				return "unknown place"
			var pos: Array = def.get("position", [0, 0])
			var y := 200.0
			var world := get_tree().get_first_node_in_group("world")
			if world and world.has_method("get_height"):
				y = float(world.get_height(float(pos[0]), float(pos[1]))) + 1.0
			_put(p, Vector3(float(pos[0]), y, float(pos[1])))
			return "teleported to %s" % id
		if a.size() >= 3:
			_put(p, Vector3(float(a[0]), float(a[1]), float(a[2])))
			return "teleported"
		return str(p.global_position), "tp <place_id> | tp <x> <y> <z>")
	register("pos", func(_a: Array) -> String:
		var p := _player()
		return str(p.global_position) if p else "no player", "player position")
	register("flag", func(a: Array) -> String:
		if a.size() == 1:
			return str(GameState.get_flag(a[0]))
		if a.size() >= 2:
			var v: Variant = a[1]
			if a[1] == "true":
				v = true
			elif a[1] == "false":
				v = false
			elif a[1].is_valid_int():
				v = int(a[1])
			GameState.set_flag(a[0], v)
			return "set"
		return str(GameState.flags), "flag <key> [value]")
	register("save", func(a: Array) -> String:
		return error_string(SaveSystem.save_to_slot(a[0] if a.size() > 0 else SaveSystem.QUICK_SLOT)), "save [slot]")
	register("load", func(a: Array) -> String:
		return error_string(SaveSystem.load_from_slot(a[0] if a.size() > 0 else SaveSystem.QUICK_SLOT)), "load [slot]")
	register("interior", func(a: Array) -> String:
		if a.size() == 0:
			return Interiors.current_id
		var id: String = a[0] if a[0].contains(":") else "core:interior/%s" % a[0]
		return "entered" if Interiors.enter(id) else "failed", "interior <id>")
	register("exit", func(_a: Array) -> String:
		return "exited" if Interiors.exit() else "not inside", "leave the current interior")
	register("rest", func(_a: Array) -> String:
		var p := _player()
		if p == null:
			return "no player"
		Hearth.rest_at("debug", p.global_position, p.global_rotation.y, false)
		return "rested here", "rest at the current position")
	register("die", func(_a: Array) -> String:
		var p := _player()
		if p == null:
			return "no player"
		if p.has_method("kill"):
			p.kill()
		else:
			EventBus.player_died.emit(p.global_position)
		return "dead", "kill the player")
	register("marks", func(a: Array) -> String:
		var inv := get_tree().get_first_node_in_group("inventory")
		if inv == null:
			return "no inventory"
		if a.size() > 0 and inv.has_method("add_marks"):
			inv.add_marks(int(a[0]))
		return str(inv.get("marks")), "marks [+n]")
	register("give", func(a: Array) -> String:
		var inv := get_tree().get_first_node_in_group("inventory")
		if inv == null or a.size() == 0:
			return "usage: give <item_id> [count]"
		var id: String = a[0] if a[0].contains(":") else "core:item/%s" % a[0]
		if not ContentDB.has(id):
			return "unknown item"
		if inv.has_method("add"):
			inv.add(id, int(a[1]) if a.size() > 1 else 1)
		return "given %s" % id, "give <item_id> [count]")
	register("stats", func(_a: Array) -> String:
		return "fps %.0f  draw %d  prims %d  objs %d  mem %.0f MB  nodes %d" % [
			Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)], "render/perf stats")
	register("draws", func(a: Array) -> String:
		var cam := get_viewport().get_camera_3d()
		var world := World.instance
		if cam == null or world == null:
			return "no camera or no world"
		var text := DrawAttribution.census_table(DrawAttribution.census(cam, get_tree().root))
		if a.size() > 0 and a[0] == "measure":
			# hides each owner for a frame in turn, so the answer arrives a moment later
			var measuring := func() -> void:
				var m: Dictionary = await DrawAttribution.measure(world)
				log_line(DrawAttribution.measure_table(m))
			measuring.call()
			text += "\n(measuring...)"
		return text, "draws [measure]: who the frame's draw calls belong to")
	register("screenshot", func(a: Array) -> String:
		var path: String = a[0] if a.size() > 0 else "user://screenshot_%d.png" % Time.get_ticks_msec()
		get_viewport().get_texture().get_image().save_png(path)
		return path, "screenshot [path]")
	register("quit", func(_a: Array) -> String:
		get_tree().quit()
		return "bye", "quit the game")
	register("errors", func(_a: Array) -> String:
		return "errors %d warnings %d" % [Log.error_count, Log.warning_count], "log counters")
