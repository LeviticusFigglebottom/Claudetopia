extends Node
## Headless screenshot runner. boot.gd routes here for `-- --capture=<plan.json> --out=<dir>`.
##
##   ./run.sh shots [plan.json]
##   xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 1600x900 \
##       -- --capture=tools/capture/plans/default.json --out=captures
##
## Plan format:
##   {"shots": [{"label", "pos": [x, y, z], "look_at": [x, y, z] | "yaw"/"pitch",
##               "fov", "time": hours, "place": "core:place/x", "height_above_ground": m}],
##    "flythrough": {"path": [[x, y, z], ...], "frames": n, "look_ahead": true, "time": hours}}
##
## For each shot it sets the clock, moves the fly camera, waits until the streamer reports the
## full-detail ring loaded (plus ten frames so LODs and shadows settle), saves
## <index>_<label>.png and records Performance monitors into <out>/perf.json.

const WORLD_SCENE := "res://world/world.tscn"
const SETTLE_FRAMES := 10
const MAX_WAIT_FRAMES := 240

var plan_path := ""
var out_dir := "captures"
var _world: World = null
var _perf: Array = []
## `--no-people` shoots the same plan with the villagers left out. It is how you find out what
## a frame costs in terrain and what it costs in people, which is not a question you can answer
## by looking at the picture.
var people := true
## `--attribute` follows every shot with `DrawAttribution`: a census of what the camera sees
## by owning script, and the measured cost of each owner with its shadow passes, printed and
## written to <out>/attribution.json. A draw-call total on its own names nobody.
var attribute := false
var _attribution: Array = []
var _failures: Array[String] = []
## `--preset=low|medium|high|painted` shoots the plan at that graphics preset (core/graphics.gd),
## set in memory only: a measurement never writes the player's settings.cfg. Without it the plan
## is shot at whatever settings.cfg says, and perf.json records which that was either way.
var preset := ""
## `--no-lod` draws the scatter as it was before trees had levels of detail (one MultiMesh a cell
## and asset), for an A/B of the same frame on the same build.
var per_tree_lod := true


func _ready() -> void:
	plan_path = str(GameState.get_flag("_capture_plan", ""))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--capture=") and plan_path.is_empty():
			plan_path = a.substr(10)
		elif a == "--no-people":
			people = false
		elif a == "--attribute":
			attribute = true
		elif a.begins_with("--preset="):
			preset = a.substr(9)
		elif a == "--no-lod":
			per_tree_lod = false
	if preset != "":
		if not Graphics.PRESETS.has(preset):
			Log.error("Capture", "no graphics preset %s (low, medium, high, painted)" % preset)
			get_tree().quit(2)
			return
		Settings.persist = false
		Settings.apply_graphics_preset(preset)
		Log.info("Capture", "graphics preset: %s" % preset)
	var code: int = await run()
	get_tree().quit(code)


func run() -> int:
	var plan := _read_plan()
	if plan.is_empty():
		return 2
	DirAccess.make_dir_recursive_absolute(out_dir)
	_world = await _load_world()
	if _world == null:
		Log.error("Capture", "world scene failed to load")
		return 1
	if _world.streamer:
		# a capture teleports across the world between shots, so build cells as fast as the
		# machine allows rather than at the gameplay drip rate
		_world.streamer.cells_per_frame = 12
		if not per_tree_lod:
			_world.streamer.lod_enabled = false
			_world.streamer.unload_all()
			_world.streamer.refresh()
			Log.info("Capture", "scatter drawn without per-tree levels of detail (--no-lod)")
	if not people:
		var crowd := get_tree().root.find_child("NpcStreamer", true, false)
		if crowd:
			crowd.set("enabled", false)
			var registry := get_tree().root.find_child("NpcRegistry", true, false)
			if registry and registry.has_method("despawn_all"):
				registry.call("despawn_all")
			Log.info("Capture", "shooting with the villagers left out")
	var shots: Array = plan.get("shots", [])
	Log.info("Capture", "%d shots -> %s" % [shots.size(), out_dir])
	var index := 0
	for shot in shots:
		if typeof(shot) != TYPE_DICTIONARY:
			continue
		await _take_shot(index, shot)
		index += 1
	var fly: Dictionary = plan.get("flythrough", {})
	if not fly.is_empty():
		index = await _fly(index, fly)
	_write_perf()
	if not _failures.is_empty():
		for f in _failures:
			Log.error("Capture", f)
		return 1
	Log.info("Capture", "%d images written to %s" % [index, out_dir])
	return 0


func _read_plan() -> Dictionary:
	if plan_path.is_empty():
		Log.error("Capture", "no --capture=<plan.json> given")
		return {}
	var path := plan_path
	if not FileAccess.file_exists(path):
		# plans are usually given relative to the repository root, not to res://
		var alt := "res://../" + path
		if FileAccess.file_exists(alt):
			path = alt
		else:
			Log.error("Capture", "plan not found: %s" % plan_path)
			return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.error("Capture", "plan is not a JSON object: %s" % path)
		return {}
	return parsed


func _load_world() -> World:
	var packed: PackedScene = load(WORLD_SCENE)
	if packed == null:
		return null
	var w: Node = packed.instantiate()
	# A capture is a photograph of the country, taken from a planned camera. A body standing in
	# it would both block the shot and take the streaming off the plan, so the world is loaded
	# without one and keeps its fly camera.
	var spawn: Node = w.get_node_or_null("PlayerSpawn")
	if spawn != null:
		spawn.set("enabled", false)
		# ...but the world's services still go in, because they are what stands the villagers
		# up, and a photograph of a village with nobody in it is a photograph of a model.
		spawn.set("services_without_a_body", true)
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	return w as World


func _take_shot(index: int, shot: Dictionary) -> void:
	var label := str(shot.get("label", "shot_%d" % index))
	if shot.has("time"):
		WorldClock.set_time(float(shot["time"]))
	if shot.has("weather"):
		_force_weather(str(shot["weather"]))
	var pos := _shot_position(shot)
	var cam := _world.fly_camera
	if cam == null:
		_failures.append("no fly camera for shot %s" % label)
		return
	cam.fov = float(shot.get("fov", 65.0))
	if shot.has("look_at"):
		var la: Array = shot["look_at"]
		cam.move_to(pos, Vector3(float(la[0]), float(la[1]), float(la[2])))
	else:
		cam.move_to(pos)
		cam.set_yaw_pitch(float(shot.get("yaw", 0.0)), float(shot.get("pitch", -8.0)))
	_world.move_target(pos)
	var waited := await _wait_for_streaming()
	# The atmosphere rewrites the environment every frame, so the fog override only holds if
	# its per-frame update is paused for the exposure.
	_pause_atmosphere(true)
	_set_fog_scale(float(shot.get("fog_scale", 1.0)))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%02d_%s.png" % [out_dir, index, label]
	var img := get_viewport().get_texture().get_image()
	_pause_atmosphere(false)
	var err := img.save_png(path)
	if err != OK:
		_failures.append("cannot write %s: %s" % [path, error_string(err)])
		return
	var sample := _sample_perf(label, pos, waited, path)
	_perf.append(sample)
	# Only composed region shots go into the drop-test folder, filed under the region the plan
	# says they are about; the flythrough deliberately crosses boundaries, so its frames are
	# not a picture of any one region.
	_write_region_copy(img, str(shot.get("region", "")), label)
	Log.info("Capture", "%s: %s (%d draw calls, %.2f M primitives, %d frames waited)"
		% [label, path.get_file(), int(_perf[-1]["draw_calls"]), float(_perf[-1]["primitives"]) / 1e6, waited])
	if attribute:
		await _attribute_shot(label, cam)


## Who the draw calls belong to, for one shot: the census first (cheap, colour pass only),
## then the measured cost of hiding each owner, which is the number that includes the sun.
func _attribute_shot(label: String, cam: Camera3D) -> void:
	# from the root, not the world: the villagers hang off the services, not off the terrain
	var rows := DrawAttribution.census(cam, get_tree().root)
	var measured: Dictionary = await DrawAttribution.measure(_world)
	print("ATTRIBUTION %s\n%s\n%s" % [label, DrawAttribution.census_table(rows),
			DrawAttribution.measure_table(measured)])
	_attribution.append({"label": label, "census": rows.values(), "measured": measured})
	var f := FileAccess.open("%s/attribution.json" % out_dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_attribution, "  "))
		f.close()


## Review shots look a long way, where the region fog densities turn the land into haze.
## A plan can thin the fog for a shot; the world itself is untouched.
func _set_fog_scale(scale: float) -> void:
	if is_equal_approx(scale, 1.0):
		return
	var env := _environment()
	if env == null:
		return
	# multiply what the atmosphere just wrote for this region and weather, not a remembered
	# value from an earlier shot in another region
	env.fog_density *= scale


func _pause_atmosphere(paused: bool) -> void:
	var atmos := _world.atmosphere if _world else null
	if atmos:
		atmos.set_process(not paused)


func _environment() -> Environment:
	var atmos := _world.atmosphere if _world else null
	if atmos == null:
		return null
	var env: Variant = atmos.get("env")
	return env as Environment


## A second copy named <region>_<label>.png, which is what tools/uniqueness_check.py reads
## for the automated half of the region drop test (DESIGN.md §10).
func _write_region_copy(img: Image, region_id: String, label: String) -> void:
	if region_id.is_empty():
		return
	var dir := "%s/regions" % out_dir
	DirAccess.make_dir_recursive_absolute(dir)
	# tools/uniqueness_check.py reads the region from the leading name, so the file has to be
	# <region>_<rest>; most shot labels already start with the region, so do not repeat it
	var short_name: String = region_id.get_file()
	var rest := label
	if rest.begins_with(short_name + "_"):
		rest = rest.substr(short_name.length() + 1)
	img.save_png("%s/%s_%s.png" % [dir, short_name, rest])


## Capture plans pin the weather so a sheet is repeatable and each region shows its own light.
func _force_weather(weather_id: String) -> void:
	var atmos := _world.atmosphere if _world else null
	if atmos and atmos.has_method("force_weather"):
		atmos.call("force_weather", weather_id, true)


func _shot_position(shot: Dictionary) -> Vector3:
	var pos := Vector3.ZERO
	if shot.has("place"):
		pos = _world.place_position(str(shot["place"]))
	if shot.has("pos"):
		var p: Array = shot["pos"]
		pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if shot.has("height_above_ground"):
		var ground := _world.provider.get_height(pos.x, pos.z)
		pos.y = ground + float(shot["height_above_ground"])
	return pos


## Waits until the streamer has the full-detail ring around the camera, then lets the frame
## settle (LOD selection, shadow splits and the water's first animation step).
func _wait_for_streaming() -> int:
	var frames := 0
	while frames < MAX_WAIT_FRAMES:
		await get_tree().process_frame
		frames += 1
		if _world.streamer == null or _world.streamer.is_ring_loaded():
			break
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
		frames += 1
	await RenderingServer.frame_post_draw
	return frames


func _sample_perf(label: String, pos: Vector3, waited: int, path: String) -> Dictionary:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return {
		"label": label,
		"file": path.get_file(),
		"pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1)],
		"region": _world.provider.nearest_region_id_at(pos.x, pos.z),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"fps_estimate": snappedf(fps, 0.1),
		"process_ms": snappedf(frame_ms, 0.01),
		"cells_loaded": _world.streamer.loaded_count() if _world.streamer else 0,
		"scatter_instances": _world.streamer.instance_count() if _world.streamer else 0,
		"frames_waited": waited,
		"time_hours": snappedf(WorldClock.time_hours, 0.01),
	}


func _fly(index: int, fly: Dictionary) -> int:
	var path_points: Array = fly.get("path", [])
	if path_points.size() < 2:
		return index
	var frames := int(fly.get("frames", 24))
	var look_ahead := bool(fly.get("look_ahead", true))
	if fly.has("time"):
		WorldClock.set_time(float(fly["time"]))
	if fly.has("weather"):
		_force_weather(str(fly["weather"]))
	for f in frames:
		var t := float(f) / float(maxi(frames - 1, 1)) * float(path_points.size() - 1)
		var i0 := clampi(int(floor(t)), 0, path_points.size() - 1)
		var i1 := clampi(i0 + 1, 0, path_points.size() - 1)
		var frac := t - float(i0)
		var a: Array = path_points[i0]
		var b: Array = path_points[i1]
		var pos := Vector3(float(a[0]), float(a[1]), float(a[2])).lerp(
			Vector3(float(b[0]), float(b[1]), float(b[2])), frac)
		var shot := {"label": "fly_%03d" % f, "pos": [pos.x, pos.y, pos.z],
			"fog_scale": float(fly.get("fog_scale", 0.4))}
		if look_ahead:
			var ahead_t := minf(t + 0.6, float(path_points.size() - 1))
			var j0 := clampi(int(floor(ahead_t)), 0, path_points.size() - 1)
			var j1 := clampi(j0 + 1, 0, path_points.size() - 1)
			var c: Array = path_points[j0]
			var d: Array = path_points[j1]
			var look := Vector3(float(c[0]), float(c[1]), float(c[2])).lerp(
				Vector3(float(d[0]), float(d[1]), float(d[2])), ahead_t - float(j0))
			shot["look_at"] = [look.x, look.y - 10.0, look.z]
		await _take_shot(index, shot)
		index += 1
	return index


func _write_perf() -> void:
	var worst_draw := 0
	var worst_prims := 0
	for p in _perf:
		worst_draw = maxi(worst_draw, int(p["draw_calls"]))
		worst_prims = maxi(worst_prims, int(p["primitives"]))
	var doc := {
		"generated_at": Time.get_datetime_string_from_system(),
		"renderer": RenderingServer.get_current_rendering_method(),
		# The window size is what the 3D scene is actually rendered at, and what the saved PNG
		# measures; the project's base viewport only sets the 2D stretch reference.
		"resolution": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"base_viewport": [int(ProjectSettings.get_setting("display/window/size/viewport_width")),
			int(ProjectSettings.get_setting("display/window/size/viewport_height"))],
		"budget": {"draw_calls": 2000, "primitives": 1500000},
		"graphics_preset": str(Settings.get_value("graphics", "preset", "")),
		"graphics": (Settings.data.get("graphics", {}) as Dictionary).duplicate(),
		"worst": {"draw_calls": worst_draw, "primitives": worst_prims},
		"within_budget": worst_draw <= 2000 and worst_prims <= 1500000,
		"shots": _perf,
	}
	var f := FileAccess.open("%s/perf.json" % out_dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(doc, "  "))
		f.close()
	Log.info("Capture", "worst frame: %d draw calls, %.2f M primitives (budget 2000 / 1.5 M)"
		% [worst_draw, float(worst_prims) / 1e6])
