class_name Benchmark
extends Node
## The built-in benchmark: the title, the Naming, then the world flown along a fixed path (a town, the
## Greatwood, open country, a large site, a town by night), each segment timed frame by frame, and a
## report written to user://benchmark/ as text and JSON. docs/BENCHMARK.md says how to run it.
##
##   Wickmere.exe -- --benchmark [--benchmark-preset=medium] [--benchmark-quick] [--benchmark-paced]
##                   [--benchmark-set=graphics.<key>=<value> ...]
##   (from the title: Ctrl+Shift+B)
##
## Drawn as the player's settings draw it, unless `--benchmark-preset` names a preset (set for the
## run only; settings.cfg is not written). By default the frame rate is not held back (vsync off, no
## cap, the menus' cap off too), so the numbers are what the machine can do; `--benchmark-paced`
## keeps the player's vsync and caps.
##
## The world is stood up as the title stands it (World.vista: no body, no people, no services), and
## each stop waits for its country to stream in before it is timed, so a segment times drawing and
## moving through a place, not loading it. What it records per segment: frames, the average frame
## rate, frame times (p50, p95, p99, max), frames over 50 and 100 ms, the worst hitches, draw calls
## and primitives (mean and max), and video memory. And once: the adapter, the renderer and driver,
## the preset and the knobs that cost the most, the window and the render scale.

const OUT_DIR := "user://benchmark"
const TITLE_S := 14.0
const NAMING_S := 10.0
const STOP_S := 12.0
const SETTLE_S := 1.5
## A stop whose country has not come in this long is timed anyway, and says so.
const STREAM_CAP_S := 90.0
## A segment is timed for its seconds and at least this many frames (a machine drawing a frame in
## seconds still gives numbers), but never more than MAX_SEGMENT_S.
const MIN_FRAMES := 12
const MAX_SEGMENT_S := 180.0
const WORLD_SCENE := "res://world/world.tscn"
const MENU_SCENE := "res://ui/menus/main_menu.tscn"
const NAMING_SCENE := "res://ui/character/naming.tscn"

## The flight: each stop's camera from `from` to `to` over STOP_S, looking at `look` (or along the
## way), at its hour and weather. A place spec (`{"place": id, "bearing", "distance", "height"}`,
## height above the ground) goes where its place goes when the map is drawn again; the Greatwood and
## the open country are the performance suite's own spots (tools/capture/plans/perf_suite.json).
const STOPS := [
	{"id": "town", "what": "Merrowby's street and market at a walk, by day", "region": "core:region/hearthvale",
		"time": 10.0, "weather": "core:weather/clear",
		"from": {"place": "core:place/merrowby", "bearing": 91.6, "distance": 42.0, "height": 1.7},
		"to": {"place": "core:place/merrowby", "bearing": 260.0, "distance": 30.0, "height": 1.7}},
	{"id": "greatwood", "what": "over and into the Briarwold's Greatwood", "region": "core:region/briarwold",
		"time": 10.5, "weather": "core:weather/still",
		"from": [3334.0, 160.1, 774.0], "to": [3120.0, 130.0, 630.0], "look": [2902.9, 97.6, 483.2]},
	{"id": "open_country", "what": "the Hearthvale from a height, the long view west", "region": "core:region/hearthvale",
		"time": 9.0, "weather": "core:weather/clear",
		"from": [671.3, 134.8, 2334.9], "to": [560.0, 120.0, 2420.0], "look": [-1327.7, 74.8, 2273.9]},
	{"id": "large_site", "what": "round Tinehold, the castle ruin under the Tine Tower", "region": "",
		"time": 15.0, "weather": "core:weather/thin_sun",
		"from": {"place": "core:poi/tinehold", "bearing": 200.0, "distance": 110.0, "height": 22.0},
		"to": {"place": "core:poi/tinehold", "bearing": 250.0, "distance": 90.0, "height": 16.0},
		"look": {"place": "core:poi/tinehold", "height": 8.0}},
	{"id": "town_night", "what": "a Cinderlea street by night, its lamps lit", "region": "core:region/cinderlea",
		"time": 20.8, "weather": "core:weather/still_grey",
		"from": [163.6, 70.1, 2862.3], "to": [185.0, 70.1, 2892.0], "look": [190.0, 70.4, 2930.0]},
]

var quick := false
var paced := false
var preset := ""
## `--benchmark-set=section.key=value`, each laid over the preset for the run.
var overrides: Array[String] = []
var from_menu := false
var report := {"segments": []}

var _segment := ""
var _samples: Array = []          # [ms, draws, prims] per frame of the segment
var _seg_t0 := 0
var _last_us := 0
var _measuring := false
var _world: World = null
var _camera: Camera3D = null
var _saved_settings: Dictionary = {}
var _saved_persist := true
var _clock_saved: Dictionary = {}


func _ready() -> void:
	name = "Benchmark"
	process_mode = Node.PROCESS_MODE_ALWAYS
	# last in the frame: one call to the next is one whole frame
	process_priority = 100000
	for a in OS.get_cmdline_user_args():
		if a == "--benchmark-quick":
			quick = true
		elif a == "--benchmark-paced":
			paced = true
		elif a.begins_with("--benchmark-preset="):
			preset = a.substr(19)
		elif a.begins_with("--benchmark-set="):
			overrides.append(a.substr(16))
	if preset == "" and not Settings.graphics_saved:
		# no settings saved yet (a fresh install): what a player's first launch would be given
		preset = str(HardwareTier.recommend(HardwareTier.adapter())["preset"])
	_saved_persist = Settings.persist
	_saved_settings = (Settings.data.get("graphics", {}) as Dictionary).duplicate()
	if preset != "" and Graphics.PRESETS.has(preset):
		Settings.persist = false
		Settings.apply_graphics_preset(preset)
	for o in overrides:
		var dot := o.find(".")
		var eq := o.find("=")
		if dot > 0 and eq > dot:
			Settings.persist = false
			var v: Variant = str_to_var(o.substr(eq + 1))
			Settings.set_value(o.substr(0, dot), o.substr(dot + 1, eq - dot - 1), v if v != null else o.substr(eq + 1))
	report["overrides"] = overrides
	# the CPU's share of drawing each frame (culling, occlusion culling, the draw calls), per segment
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if not paced:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("BENCHMARK: started (%s, %s)" % [Settings.get_value("graphics", "preset", "?"), "paced" if paced else "unpaced"])
	_run.call_deferred()


func _s(seconds: float) -> float:
	return seconds * (0.4 if quick else 1.0)


func _process(_delta: float) -> void:
	if not paced:
		# the menus' cap (Graphics.menu_pace) and the player's are off while it runs
		Engine.max_fps = 0
	var now := Time.get_ticks_usec()
	if _measuring and _last_us > 0:
		_samples.append([(now - _last_us) / 1000.0,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
					+ RenderingServer.get_frame_setup_time_cpu()])
	_last_us = now


func _run() -> void:
	report["started"] = Time.get_datetime_string_from_system(false, true)
	report["machine"] = _machine()
	# the title, as the player meets it (boot opens it on a launch with --benchmark)
	var t_menu := Time.get_ticks_msec()
	while not _on_title() and Time.get_ticks_msec() - t_menu < 5000:
		await get_tree().process_frame
	if not _on_title():
		get_tree().change_scene_to_file(MENU_SCENE)
	await _wait_s(1.0)
	await _time("title", "the title screen with its country (%s)" % _title_kind(), _s(TITLE_S))
	# the Naming, its figure turning
	get_tree().change_scene_to_file(NAMING_SCENE)
	await _wait_s(0.5)
	var naming := get_tree().current_scene
	await _time("creator", "the Naming, the figure turning", _s(NAMING_S), func(t: float) -> void:
		if is_instance_valid(naming):
			naming.set("_yaw_target", 0.38 + t * 0.9)
			naming.set("_zoom_target", 1.0 if fmod(t, 6.0) > 3.0 else 0.0))
	# the world, its stops one after another
	get_tree().unload_current_scene()
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	await _stand_world_up()
	report["world_stand_up_s"] = (Time.get_ticks_msec() - t0) / 1000.0
	if _world != null:
		for stop: Dictionary in STOPS:
			await _fly(stop)
	_finish()


func _on_title() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path.ends_with("main_menu.tscn")


func _title_kind() -> String:
	var menu := get_tree().current_scene
	if menu == null:
		return "none"
	if menu.get("vista") != null:
		return "live"
	if menu.get("reel") != null:
		return "filmed"
	return "the chart"


func _wait_s(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


## Times `seconds` of frames as segment `id`; `each(t)` is called every frame with the seconds in.
func _time(id: String, what: String, seconds: float, each := Callable()) -> void:
	_segment = id
	_samples = []
	_measuring = true
	_last_us = 0
	_seg_t0 = Time.get_ticks_msec()
	var mem0 := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	while (Time.get_ticks_msec() - _seg_t0 < int(seconds * 1000.0) or _samples.size() < MIN_FRAMES) \
			and Time.get_ticks_msec() - _seg_t0 < int(MAX_SEGMENT_S * 1000.0):
		if each.is_valid():
			each.call((Time.get_ticks_msec() - _seg_t0) / 1000.0)
		await get_tree().process_frame
	_measuring = false
	var entry := summarise(_samples)
	entry["id"] = id
	entry["what"] = what
	entry["video_mem_mb"] = roundi(maxf(mem0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0)
	(report["segments"] as Array).append(entry)
	print("BENCHMARK: %-12s %5d frames, %5.1f fps, p50 %5.1f ms, p95 %5.1f, p99 %5.1f, max %6.1f, >50 ms %d, draws %d, prims %.2f M" % [
			id, int(entry["frames"]), float(entry["avg_fps"]), float(entry["p50_ms"]), float(entry["p95_ms"]),
			float(entry["p99_ms"]), float(entry["max_ms"]), int(entry["over_50ms"]), int(entry["draws_mean"]),
			float(entry["prims_mean"]) / 1e6])


## A segment's frames, [ms, draws, prims] each, summed up. Pure, for the tests.
static func summarise(samples: Array) -> Dictionary:
	var ms: Array[float] = []
	var total := 0.0
	var draws := 0.0
	var prims := 0.0
	var draws_max := 0
	var prims_max := 0
	var worst: Array = []
	var render_cpu: Array[float] = []
	for i in samples.size():
		var s: Array = samples[i]
		ms.append(float(s[0]))
		total += float(s[0])
		draws += float(s[1])
		prims += float(s[2])
		draws_max = maxi(draws_max, int(s[1]))
		prims_max = maxi(prims_max, int(s[2]))
		worst.append([float(s[0]), i])
		if s.size() > 3:
			render_cpu.append(float(s[3]))
	worst.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var sorted := ms.duplicate()
	sorted.sort()
	var n := maxi(samples.size(), 1)
	var over50 := 0
	var over100 := 0
	for v in ms:
		over50 += 1 if v > 50.0 else 0
		over100 += 1 if v > 100.0 else 0
	var hitches: Array = []
	for w: Array in worst.slice(0, 5):
		if float(w[0]) > 50.0:
			hitches.append({"frame": int(w[1]), "ms": snappedf(float(w[0]), 0.1)})
	return {"frames": samples.size(), "seconds": snappedf(total / 1000.0, 0.01),
		"avg_fps": snappedf(1000.0 * samples.size() / maxf(total, 0.001), 0.1),
		"p50_ms": snappedf(_pct(sorted, 0.5), 0.1), "p95_ms": snappedf(_pct(sorted, 0.95), 0.1),
		"p99_ms": snappedf(_pct(sorted, 0.99), 0.1), "max_ms": snappedf(_pct(sorted, 1.0), 0.1),
		"over_50ms": over50, "over_100ms": over100, "worst_hitches": hitches,
		"draws_mean": roundi(draws / n), "draws_max": draws_max,
		"prims_mean": roundi(prims / n), "prims_max": prims_max,
		"render_cpu_mean_ms": snappedf(_mean(render_cpu), 0.01)}


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var t := 0.0
	for v in values:
		t += v
	return t / values.size()


static func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[clampi(int(ceil(p * sorted.size())) - 1, 0, sorted.size() - 1)])


# --- the world ----------------------------------------------------------------------------------

func _stand_world_up() -> void:
	if not ResourceLoader.exists(WORLD_SCENE) or not bool(WorldStatus.current().get("playable", false)):
		report["world"] = "not built"
		return
	_clock_saved = {"time": WorldClock.time_hours, "running": WorldClock.running}
	WorldClock.running = false
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	w.name = "BenchmarkWorld"
	w.vista = true
	var spawn := w.get_node_or_null("PlayerSpawn")
	if spawn != null:
		spawn.set("enabled", false)
		spawn.set("services_without_a_body", false)
	_camera = Camera3D.new()
	_camera.name = "BenchmarkCamera"
	_camera.near = 0.25
	_camera.add_to_group("streamer_target")
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	w.add_child(_camera)
	w.spawn_place = "core:place/merrowby"
	var start := _point(STOPS[0]["from"], null)
	if start != Vector3.INF:
		_camera.position = Vector3(start.x, 120.0, start.z)
	_world = w
	add_child(w)
	_camera.make_current()
	if not w.is_world_ready:
		await w.world_ready
	_camera.far = Graphics.camera_far(Settings.data.get("graphics", {}))


## A stop: posed at its start, its country streamed in (the streamer hurried, as under the title's
## dip), settled, then flown from `from` to `to` over STOP_S and timed.
func _fly(stop: Dictionary) -> void:
	var a := _point(stop["from"], _world)
	var b := _point(stop["to"], _world)
	if a == Vector3.INF or b == Vector3.INF:
		(report["segments"] as Array).append({"id": stop["id"], "what": stop["what"], "skipped": "its place is not on the map"})
		return
	var look: Variant = stop.get("look", null)
	var look_at := _point(look, _world) if look != null else Vector3.INF
	WorldClock.time_hours = float(stop.get("time", 12.0))
	var region := str(stop.get("region", ""))
	if region.is_empty() and _world.provider != null:
		region = _world.provider.nearest_region_id_at(a.x, a.z)
	if _world.atmosphere != null and not region.is_empty():
		_world.atmosphere.call("set_region", region, true)
		if stop.has("weather"):
			_world.atmosphere.call("force_weather", str(stop["weather"]), true)
	if _world.water != null and not region.is_empty():
		_world.water.set_region_look(region)
	_pose(a, b, look_at, 0.0)
	var streamer := _world.streamer
	var came := true
	if streamer != null:
		streamer.set_also_around([a, b])
		streamer.hurry = true
		var t0 := Time.get_ticks_msec()
		while not (streamer.is_loaded_around(a) and streamer.is_loaded_around(b)):
			await get_tree().process_frame
			if Time.get_ticks_msec() - t0 > int(STREAM_CAP_S * 1000.0):
				came = false
				break
		streamer.hurry = false
	await _wait_s(SETTLE_S)
	var seconds := _s(STOP_S)
	await _time(str(stop["id"]), str(stop["what"]), seconds, func(t: float) -> void:
		_pose(a, b, look_at, clampf(t / seconds, 0.0, 1.0)))
	if not came:
		var last: Dictionary = (report["segments"] as Array).back()
		last["note"] = "timed before all its country had streamed in"


func _pose(a: Vector3, b: Vector3, look_at: Vector3, u: float) -> void:
	var s := u * u * (3.0 - 2.0 * u)
	var at := a.lerp(b, s)
	_camera.global_position = at
	var target := look_at if look_at != Vector3.INF else at + (b - a).normalized() * 50.0
	if not at.is_equal_approx(target):
		_camera.look_at(target, Vector3.UP)


## A stop's point: [x, y, z] as it is, or a place spec at its height above the ground there.
func _point(spec: Variant, w: World) -> Vector3:
	if spec is Array:
		var arr := spec as Array
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	if not spec is Dictionary:
		return Vector3.INF
	var xz := PlaceRef.point_xz(spec as Dictionary)
	if xz == Vector2.INF:
		return Vector3.INF
	var ground := 0.0
	if w != null and w.provider != null:
		ground = maxf(w.provider.get_height(xz.x, xz.y), w.provider.water_level_at(xz.x, xz.y))
	return Vector3(xz.x, ground + float((spec as Dictionary).get("height", 2.0)), xz.y)


# --- the report ---------------------------------------------------------------------------------

func _machine() -> Dictionary:
	var a := HardwareTier.adapter()
	var g: Dictionary = Settings.data.get("graphics", {})
	var info := Engine.get_version_info()
	var mem := OS.get_memory_info()
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
	var window := DisplayServer.window_get_size()
	return {
		"game": "%s (commit %s)" % [str(ProjectSettings.get_setting("application/config/version", "")), ErrorLog.game_commit()],
		"godot": "%s (%s)" % [str(info.get("string", "")), "debug" if OS.is_debug_build() else "release"],
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"cpu": "%s, %d threads" % [OS.get_processor_name(), OS.get_processor_count()],
		"ram_gb": snappedf(float(mem.get("physical", 0)) / 1073741824.0, 0.1),
		"gpu": str(a.get("name", "")), "gpu_vendor": str(a.get("vendor", "")),
		"gpu_kind": HardwareTier.kind_of(a), "gpu_driver": " ".join(OS.get_video_adapter_driver_info()),
		"recommended": HardwareTier.recommend(a),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"window": "%dx%d" % [window.x, window.y], "canvas": "%dx%d" % [int(size.x), int(size.y)],
		"preset": str(g.get("preset", "")),
		"render_scale": g.get("render_scale"), "upscaler": Graphics.UPSCALER_CHOICES[clampi(int(g.get("upscaler", 0)), 0, 2)],
		"msaa": ["off", "2x", "4x", "8x"][clampi(int(g.get("msaa", 0)), 0, 3)], "shadow_atlas": g.get("shadow_atlas"),
		"ssao": g.get("ssao"), "volumetric_fog": g.get("volumetric_fog"), "sdfgi": g.get("sdfgi"),
		"view_distance": ["near", "far", "epic"][clampi(int(g.get("view_distance", 1)), 0, 2)],
		"title_live": g.get("title_live"), "distant_ground": g.get("distant_ground"),
		"pacing": "player's vsync and caps" if paced else "vsync off, no frame cap",
		"quick": quick,
	}


func _finish() -> void:
	report["finished"] = Time.get_datetime_string_from_system(false, true)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "_")
	var base := "%s/benchmark_%s" % [OUT_DIR, stamp]
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
		f.close()
	var t := FileAccess.open(base + ".txt", FileAccess.WRITE)
	if t != null:
		t.store_string(text_report(report))
		t.close()
	var where := ProjectSettings.globalize_path(base)
	print("BENCHMARK: written to %s.txt and .json" % where)
	report["path"] = where
	# the world goes, the clock and the settings come back as they were
	if _world != null and is_instance_valid(_world):
		_world.tear_down()
		_world.queue_free()
	_world = null
	if not _clock_saved.is_empty():
		WorldClock.time_hours = float(_clock_saved["time"])
		WorldClock.running = bool(_clock_saved["running"])
	if preset != "":
		for key in _saved_settings:
			Settings.data["graphics"][key] = _saved_settings[key]
		Settings.apply_all()
	Settings.persist = _saved_persist
	if not paced:
		Settings.apply_all()
	if from_menu:
		get_tree().change_scene_to_file(MENU_SCENE)
		EventBus.emit_notify("The benchmark is written to %s.txt" % where, "info")
		queue_free()
	else:
		# a few frames for the world's teardown before the engine's own
		for i in 5:
			await get_tree().process_frame
		get_tree().quit(0)


## The report as text, for a person: the machine, then a table of the segments, then the hitches.
static func text_report(r: Dictionary) -> String:
	var m: Dictionary = r.get("machine", {})
	var rec: Dictionary = m.get("recommended", {})
	var lines: Array[String] = []
	lines.append("Wickmere benchmark, %s" % str(r.get("started", "")))
	lines.append("Game %s; Godot %s; %s" % [str(m.get("game", "")), str(m.get("godot", "")), str(m.get("os", ""))])
	lines.append("GPU: %s (%s, %s); driver %s" % [str(m.get("gpu", "")), str(m.get("gpu_vendor", "")),
			str(m.get("gpu_kind", "")), str(m.get("gpu_driver", ""))])
	lines.append("Renderer: %s via %s, API %s" % [str(m.get("renderer", "")), str(m.get("driver", "")), str(m.get("api", ""))])
	lines.append("CPU: %s; RAM %.1f GB" % [str(m.get("cpu", "")), float(m.get("ram_gb", 0.0))])
	lines.append("Window %s; preset %s (render scale %s, %s, MSAA %s, shadows %s, SSAO %s, view %s, live title %s, distant ground %s)" % [
			str(m.get("window", "")), str(m.get("preset", "")), str(m.get("render_scale", "")), str(m.get("upscaler", "")),
			str(m.get("msaa", "")), str(m.get("shadow_atlas", "")), str(m.get("ssao", "")), str(m.get("view_distance", "")),
			str(m.get("title_live", "")), str(m.get("distant_ground", ""))])
	lines.append("Recommended for this GPU: %s (%s)" % [str(rec.get("preset", "")), str(rec.get("why", ""))])
	lines.append("Pacing: %s%s" % [str(m.get("pacing", "")), "; quick run" if bool(m.get("quick", false)) else ""])
	if not (r.get("overrides", []) as Array).is_empty():
		lines.append("Set for this run: %s" % ", ".join(r["overrides"]))
	lines.append("(cpu draw: the CPU's ms a frame preparing the frame for the GPU: culling, occlusion culling, the draw calls)")
	if r.has("world_stand_up_s"):
		lines.append("The world stood up in %.1f s" % float(r["world_stand_up_s"]))
	lines.append("")
	lines.append("%-13s %6s %7s %7s %7s %7s %8s %6s %7s %7s %7s %9s %9s %8s" % ["segment", "frames", "avg fps",
			"p50 ms", "p95 ms", "p99 ms", "max ms", ">50ms", ">100ms", "draws", "max", "prims M", "max M", "cpu draw"])
	for s: Dictionary in r.get("segments", []):
		if s.has("skipped"):
			lines.append("%-13s skipped: %s" % [str(s["id"]), str(s["skipped"])])
			continue
		lines.append("%-13s %6d %7.1f %7.1f %7.1f %7.1f %8.1f %6d %7d %7d %7d %9.2f %9.2f %8.2f%s" % [str(s["id"]),
				int(s["frames"]), float(s["avg_fps"]), float(s["p50_ms"]), float(s["p95_ms"]), float(s["p99_ms"]),
				float(s["max_ms"]), int(s["over_50ms"]), int(s["over_100ms"]), int(s["draws_mean"]), int(s["draws_max"]),
				float(s["prims_mean"]) / 1e6, float(s["prims_max"]) / 1e6, float(s.get("render_cpu_mean_ms", 0.0)),
				("  (%s)" % str(s["note"])) if s.has("note") else ""])
	lines.append("")
	lines.append("Worst hitches (over 50 ms):")
	var any := false
	for s: Dictionary in r.get("segments", []):
		for h: Dictionary in s.get("worst_hitches", []):
			lines.append("  %-13s frame %5d: %.1f ms" % [str(s["id"]), int(h["frame"]), float(h["ms"])])
			any = true
	if not any:
		lines.append("  none")
	lines.append("")
	for s: Dictionary in r.get("segments", []):
		lines.append("%-13s %s" % [str(s.get("id", "")), str(s.get("what", ""))])
	return "\n".join(lines) + "\n"
