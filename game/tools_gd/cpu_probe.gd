extends Node
## What the title and a new game's opening cost the main thread, frame by frame (TRIAGE item 36).
##
## Attached by boot (`--cpu=<out dir>`), at the root, so it outlives the scenes it watches. By default
## nothing is drawn (`RenderingServer.render_loop_enabled = false`): this machine renders on the CPU
## (llvmpipe), where a frame is seconds and says nothing about a player's GPU, so what is measured is
## everything else the main thread does in a frame -- the scripts, physics, the streaming, the
## world standing up, the scene tree -- which a GPU does not make any quicker. `--cpu-draw` keeps the
## drawing, for comparison.
##
## Each frame it writes down the wall clock since the last and the main thread's own CPU time over
## it (Linux: /proc/<pid>/task/<pid>/schedstat, in nanoseconds; the wall clock alone where that is
## missing), under the phase the game is in:
##   menu_loading  the title is up and answering, its country not yet shown
##   menu_vista    the country behind the menu is shown (CPU_MENU_S seconds of it)
##   naming        the Naming, after New Game (skipped straight through)
##   loading       from "Be named" until the world is ready
##   body          until the body stands
##   fade          until the loading fade lifts
##   film_wait     the opening's curtain is up, its first shot not yet shown
##   film          the opening plays
##   control       control is the player's (CONTROL_S seconds)
## and the moments between them. Writes <out>/cpu_probe.json and prints a CPU| line per phase.
##
##   xvfb-run -a godot --path game --rendering-driver opengl3 --audio-driver Dummy -- \
##       --cpu=<abs dir> [--cpu-new=core:style/warrior] [--cpu-menu-s=30] [--cpu-draw] [--cpu-no-vista-caps]
##   godot --headless --path game --audio-driver Dummy -- --cpu=<abs dir> ...   (no renderer at all:
##       the world is paced and the title and the film play as where they are drawn)
##
## Without --cpu-new it stops after the title's CPU_MENU_S seconds of country.
## `--cpu-preset=<name>` measures at a graphics preset (in memory only).
## `--cpu-naming-s=N` presses New Game and stays N seconds in the Naming before going on (or, with no
## --cpu-new, stops there): the Naming's own frames, which straight through are only its first.

const CAP_S := 900.0
const CONTROL_S := 8.0

var out_dir := ""
var style := ""
var menu_s := 30.0
var naming_s := 0.0
## `--cpu-preset=<name>`: measured at that graphics preset, set in memory only.
var preset := ""
var draw := false
## Off (`--cpu-no-vista-caps`), the title's caps before its first shot (TitleVista.LONG_FRAME_S,
## FIRST_SHOW_CAP_S) are widened, so what a first launch costs is measured to the end rather than
## given up on (docs/FIRST_LAUNCH.md).
var vista_caps := true

var _phase := "boot"
var _phase_began_ms := 0
var _samples: Dictionary = {}      # phase -> Array of [wall_ms, cpu_ms]
var _marks: Dictionary = {}        # moment -> ms since the engine started
var _stat_path := ""
var _last_us := 0
var _last_cpu_ns := 0
var _pressed := false
var _named := false
var _done := false
var _film_seen := false
var _slowest: Dictionary = {}      # phase -> [wall_ms, what the streamer and world were doing]
var _blame: Dictionary = {}        # phase -> {culprit -> frames over 8 ms}
var _blame30: Dictionary = {}      # the same, over 30 ms
var _frames30: Array = []          # [phase, cpu ms, {piece: ms}] of every frame over 30 ms


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# last in the frame, so one call to the next is one whole frame
	process_priority = 100000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cpu-new="):
			style = a.substr(10)
		elif a.begins_with("--cpu-menu-s="):
			menu_s = float(a.substr(13))
		elif a.begins_with("--cpu-naming-s="):
			naming_s = float(a.substr(15))
		elif a.begins_with("--cpu-preset="):
			preset = a.substr(13)
		elif a == "--cpu-draw":
			draw = true
		elif a == "--cpu-no-vista-caps":
			vista_caps = false
			# and on a software rasterizer too, which the title otherwise keeps its chart on
			TitleVista.software_allowed = true
	var pid := OS.get_process_id()
	var p := "/proc/%d/task/%d/schedstat" % [pid, pid]
	if FileAccess.file_exists(p):
		_stat_path = p
	if not draw:
		RenderingServer.render_loop_enabled = false
	if DisplayServer.get_name() == "headless":
		# no renderer at all (the dummy one): the world is still stood up and built as where it is
		# drawn, paced, with the title's country and the opening's film, so what is measured is the
		# main thread's own work and nothing of the software renderer's
		WorldPace.paced_override = 1
		TitleVista.headless_allowed = true
		CinematicPlayer.headless_allowed = true
	Settings.persist = false
	if Graphics.PRESETS.has(preset):
		Settings.apply_graphics_preset(preset)
		print("CPU: graphics preset %s" % preset)
	# where a place's long steps begin and end (PoiKit.long_steps)
	PoiKit.trace_steps = true
	_mark("probe_attached")
	print("CPU: attached (drawing %s, thread CPU %s)" % ["on" if draw else "off", "from schedstat" if not _stat_path.is_empty() else "not readable: wall clock only"])


func _cpu_ns() -> int:
	if _stat_path.is_empty():
		return 0
	var f := FileAccess.open(_stat_path, FileAccess.READ)
	if f == null:
		return 0
	var line := f.get_line()
	return int(line.split(" ")[0])


func _mark(moment: String) -> void:
	if not _marks.has(moment):
		_marks[moment] = Time.get_ticks_msec()
		print("CPU: %-22s at %6.2f s" % [moment, Time.get_ticks_msec() / 1000.0])


func _enter(phase: String) -> void:
	if phase == _phase:
		return
	_phase = phase
	_phase_began_ms = Time.get_ticks_msec()
	if not phase in ["film", "film_hold"] or not _marks.has("begin_" + phase):
		_mark("begin_" + phase)


func _process(_delta: float) -> void:
	if _done:
		return
	var now := Time.get_ticks_usec()
	var cpu := _cpu_ns()
	if _last_us > 0:
		var wall_ms := (now - _last_us) / 1000.0
		var cpu_ms := (cpu - _last_cpu_ns) / 1000000.0 if not _stat_path.is_empty() else wall_ms
		if not _samples.has(_phase):
			_samples[_phase] = []
		(_samples[_phase] as Array).append([wall_ms, cpu_ms])
		var worst: Array = _slowest.get(_phase, [0.0, ""])
		if cpu_ms > float(worst[0]):
			_slowest[_phase] = [cpu_ms, _doing()]
		if cpu_ms > 8.0:
			# what the slow frame went on: the biggest piece built in it, or the world standing up
			var by: Dictionary = _blame.get(_phase, {})
			var what := _culprit()
			by[what] = int(by.get(what, 0)) + 1
			_blame[_phase] = by
			if cpu_ms > 30.0:
				var big: Dictionary = _blame30.get(_phase, {})
				big[what] = int(big.get(what, 0)) + 1
				_blame30[_phase] = big
				# each such frame, with every piece built in it (ms), for the report
				var all := {}
				var s := _streamer()
				for src: Dictionary in [WorldPace.frame_pieces if WorldPace._pieces_frame == Engine.get_process_frames() else {},
						s.done_frame_pieces if s != null else {}]:
					for k: String in src:
						all[k] = snappedf(float(all.get(k, 0.0)) + float(src[k]), 0.1)
				_frames30.append([_phase, snappedf(cpu_ms, 0.1), all])
	_last_us = Time.get_ticks_usec()
	_last_cpu_ns = _cpu_ns()
	_advance()
	if Time.get_ticks_msec() > CAP_S * 1000.0:
		print("CPU: the cap (%d s) came first, in %s" % [int(CAP_S), _phase])
		_finish()


## The biggest single piece built in this frame (the streamer's, and everything paced by WorldPace),
## if it took 2 ms or more; else the step the world is standing up at, or "other".
func _culprit() -> String:
	var best := ""
	var best_ms := 2.0
	var s := _streamer()
	var sources: Array = [WorldPace.frame_pieces if WorldPace._pieces_frame == Engine.get_process_frames() else {}]
	if s != null:
		sources.append(s.done_frame_pieces)
	for src: Dictionary in sources:
		for k: String in src:
			if float(src[k]) > best_ms:
				best_ms = float(src[k])
				best = k
	if not best.is_empty():
		return best
	var w := _world()
	if w != null and not w.is_world_ready:
		return "stand_up:" + str(w.stand_up_ms.keys().back() if not w.stand_up_ms.is_empty() else "begin")
	# neither: which of the engine's steps took it (its monitors are the last frame's)
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return "other:physics" if phys > proc else "other:process"


func _world() -> World:
	var w := World.instance
	if w == null:
		var vista := get_tree().get_first_node_in_group("title_vista") as TitleVista
		w = vista.world if vista != null else null
	return w if w != null and is_instance_valid(w) else null


func _streamer() -> WorldStreamer:
	var w := _world()
	return w.streamer if w != null else null


## What the frame just measured was spent on, as far as the world and the streamer say.
func _doing() -> String:
	var w := World.instance
	if w == null:
		var vista := get_tree().get_first_node_in_group("title_vista") as TitleVista
		w = vista.world if vista != null else null
	if w == null or not is_instance_valid(w):
		return ""
	var s := w.streamer
	var bits: Array[String] = ["stand_up %s" % str(w.stand_up_ms.keys().back() if not w.stand_up_ms.is_empty() else "")]
	if s != null:
		bits.append("built %s (cells, ms)" % str(s.done_frame_build))
		if not s.done_frame_pieces.is_empty():
			bits.append("pieces %s" % str(s.done_frame_pieces))
	return ", ".join(bits)


func _advance() -> void:
	var scene := get_tree().current_scene
	var scene_path := scene.scene_file_path if scene != null else ""
	match _phase:
		"boot":
			if scene_path.ends_with("main_menu.tscn"):
				_enter("menu_loading")
				_mark("first_menu_frame")
		"menu_loading", "menu_vista":
			var focus := get_viewport().gui_get_focus_owner()
			if focus is BaseButton:
				_mark("menu_interactive")
			var vista := get_tree().get_first_node_in_group("title_vista") as TitleVista
			if vista != null and not vista_caps:
				vista.long_frame_s = 3600.0
				vista.first_show_cap_s = 3600.0
			if _phase == "menu_loading" and (vista == null or vista.is_showing() or vista.phase == TitleVista.Phase.GONE):
				if vista != null and vista.is_showing():
					_mark("vista_shown")
				elif Time.get_ticks_msec() - _phase_began_ms < 2000:
					return
				_enter("menu_vista")
			if _phase == "menu_vista" and Time.get_ticks_msec() - _phase_began_ms > int(menu_s * 1000.0):
				if style.is_empty() and naming_s <= 0.0:
					_finish()
					return
				if not _pressed:
					_pressed = true
					_mark("new_game_pressed")
					_enter("naming")
					scene.call("_on_new_game")
		"naming":
			if scene_path.ends_with("naming.tscn") and not _named and scene.is_node_ready():
				if not _marks.has("naming_ready"):
					_mark("naming_ready")
				if Time.get_ticks_msec() - int(_marks["naming_ready"]) < int(naming_s * 1000.0):
					return
				if style.is_empty():
					_finish()
					return
				_named = true
				scene.set("player_name", "Probe")
				if str(scene.get("calling_id")).is_empty():
					scene.set("calling_id", str(ContentDB.all("calling")[0].get("id", "")))
				scene.set("style_id", style)
				_mark("be_named_pressed")
				_enter("loading")
				scene.call("_begin_game")
		"loading":
			if World.instance != null and World.instance.is_world_ready:
				_mark("world_ready")
				_enter("body")
		"body":
			if not get_tree().get_nodes_in_group("player").is_empty():
				_mark("body_stands")
				_enter("fade")
		"fade", "film_wait", "film", "film_hold":
			var cin := get_tree().get_first_node_in_group(CinematicPlayer.GROUP) as CinematicPlayer
			if _phase == "fade" and not UI.is_faded_out() and not UI.is_holding_for_country():
				_mark("fade_lifted")
				_enter("film_wait" if cin != null else "control")
			if cin != null and not _film_seen:
				_film_seen = true
				_mark("film_begins")
				if _phase == "fade":
					_enter("film_wait")
			# the pictures playing (`film`), and the holds between shots, black or on the last frame
			# held, where the country for the next is built (`film_hold`)
			if cin != null and cin.is_playing() and cin.phase_name() == "PLAY":
				_mark("first_film_frame")
				_enter("film")
			elif _phase in ["film", "film_hold"] and cin != null and cin.phase_name() != "PLAY":
				if _phase == "film":
					_samples_note("film_holds")
				_enter("film_hold")
			if _film_seen and cin == null and not UI.is_faded_out():
				_mark("control")
				_enter("control")
		"control":
			if Time.get_ticks_msec() - _phase_began_ms > int(CONTROL_S * 1000.0):
				_finish()


func _samples_note(what: String) -> void:
	_marks[what] = int(_marks.get(what, 0)) + 1


static func _pct(values: Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	return float(v[clampi(int(ceil(p * v.size())) - 1, 0, v.size() - 1)])


func _finish() -> void:
	if _done:
		return
	_done = true
	RenderingServer.render_loop_enabled = true
	var report := {"drawing": draw, "thread_cpu": not _stat_path.is_empty(), "marks_ms": _marks, "phases": {}}
	for phase: String in _samples:
		var rows: Array = _samples[phase]
		var walls: Array = []
		var cpus: Array = []
		for r: Array in rows:
			walls.append(r[0])
			cpus.append(r[1])
		var over8 := 0
		var over12 := 0
		var over50 := 0
		var wall50 := 0
		for c: float in cpus:
			over8 += 1 if c > 8.0 else 0
			over12 += 1 if c > 12.0 else 0
			over50 += 1 if c > 50.0 else 0
		for w: float in walls:
			wall50 += 1 if w > 50.0 else 0
		var total_cpu := 0.0
		for c: float in cpus:
			total_cpu += c
		var entry := {"frames": rows.size(), "cpu_p50": _pct(cpus, 0.5), "cpu_p95": _pct(cpus, 0.95),
				"cpu_max": _pct(cpus, 1.0), "wall_p95": _pct(walls, 0.95), "wall_max": _pct(walls, 1.0),
				"cpu_total_s": total_cpu / 1000.0, "over_8ms": over8, "over_12ms": over12, "over_50ms": over50,
				"wall_p50": _pct(walls, 0.5), "wall_over_50ms": wall50,
				"worst": _slowest.get(phase, [])}
		entry["slow_frames_by"] = _blame.get(phase, {})
		entry["over_30ms_by"] = _blame30.get(phase, {})
		report["phases"][phase] = entry
		print("CPU| %-13s %5d frames  main-thread ms p50 %6.1f  p95 %6.1f  max %7.1f  (>8 ms %d, >12 ms %d, >50 ms %d; wall p50 %.1f, >50 ms %d; %.1f s CPU)  worst: %s"
				% [phase, rows.size(), entry["cpu_p50"], entry["cpu_p95"], entry["cpu_max"], over8, over12, over50,
					entry["wall_p50"], wall50,
					entry["cpu_total_s"], str((entry["worst"] as Array).back() if not (entry["worst"] as Array).is_empty() else "")])
	for phase: String in _samples:
		var by: Dictionary = _blame.get(phase, {})
		var keys := by.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return int(by[a]) > int(by[b]))
		var parts: Array[String] = []
		for k: String in keys.slice(0, 10):
			parts.append("%s %d" % [k, int(by[k])])
		if not parts.is_empty():
			print("CPU| %-13s frames over 8 ms by what they built most: %s" % [phase, ", ".join(parts)])
	var t := func(a: String, b: String) -> String:
		return "%.2f s" % ((int(_marks[b]) - int(_marks[a])) / 1000.0) if _marks.has(a) and _marks.has(b) else "-"
	print("CPU| first menu frame at %s from the engine's start; menu interactive %s; country shown %s after the first menu frame"
			% ["%.2f s" % (int(_marks.get("first_menu_frame", 0)) / 1000.0), t.call("first_menu_frame", "menu_interactive"),
				t.call("first_menu_frame", "vista_shown")])
	if not style.is_empty():
		print("CPU| from Be named: world ready %s, body %s, fade lifts %s, first film frame %s, control %s"
				% [t.call("be_named_pressed", "world_ready"), t.call("be_named_pressed", "body_stands"),
					t.call("be_named_pressed", "fade_lifted"), t.call("be_named_pressed", "first_film_frame"),
					t.call("be_named_pressed", "control")])
	var w := World.instance
	if w != null:
		report["stand_up_ms"] = w.stand_up_ms
		if w.streamer != null:
			report["pieces"] = w.streamer.piece_stats
			print("CPU| world stood up in %s" % str(w.stand_up_ms))
			print("CPU| streamer pieces (count, total ms, max ms): %s" % str(w.streamer.piece_stats))
	report["paced_pieces"] = WorldPace.pieces
	var paced := WorldPace.pieces.keys()
	paced.sort_custom(func(a: String, b: String) -> bool: return float(WorldPace.pieces[a][2]) > float(WorldPace.pieces[b][2]))
	var worst: Array[String] = []
	for k: String in paced:
		worst.append("%s %s" % [k, str(WorldPace.pieces[k])])
	print("CPU| paced pieces (pieces, ms, longest): %s" % ", ".join(worst))
	report["poi_raise_ms"] = WorldPois.raise_ms
	var kinds := WorldPois.raise_ms.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return float(WorldPois.raise_ms[a][1]) > float(WorldPois.raise_ms[b][1]))
	var top: Array[String] = []
	for k: String in kinds.slice(0, 12):
		top.append("%s %s" % [k, str(WorldPois.raise_ms[k])])
	print("CPU| places by kind (raised, ms, longest): %s" % ", ".join(top))
	var steps: Array = []
	for k: String in PoiKit.long_steps:
		steps.append([float(PoiKit.long_steps[k][1]), int(PoiKit.long_steps[k][0]), k])
	steps.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var worst_steps: Array[String] = []
	for s in steps.slice(0, 25):
		worst_steps.append("%s [%d, %.1f]" % [s[2], s[1], s[0]])
	print("CPU| a place's longest steps (from -> to [pieces, ms]): %s" % "; ".join(worst_steps))
	report["poi_long_steps"] = PoiKit.long_steps
	report["frames_over_30ms"] = _frames30
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir.path_join("cpu_probe.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
		f.close()
	get_tree().quit(0)
