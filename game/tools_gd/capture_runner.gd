extends Node
## Headless screenshot runner. boot.gd routes here for `-- --capture=<plan.json> --out=<dir>`.
##
##   ./run.sh shots [plan.json]
##   xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 1600x900 \
##       -- --capture=tools/capture/plans/default.json --out=captures
##
## Plan format:
##   {"shots": [{"label", "at": {place spec}, "look": {place spec} | "yaw"/"pitch",
##               "fov", "time": hours}],
##    "flythrough": {"path": [[x, y, z], ...], "frames": n, "look_ahead": true, "time": hours},
##    "gait": {"at": {place spec}, "heading": deg, "frames": 8, "interval": 0.1, "settle": 1.6,
##             "camera": {"distance": m, "height": m, "fov": deg},
##             "runs": [{"label": "jog", "press": ["move_forward"]}, ...]},
##    "cinematic": {"id": "core:cinematic/x", "samples": [0.0, 0.5, 1.0], "shots": [ids]?,
##                  "opening": "core:opening/x"? (the body stood at that start, for a style film)}}
##
## A place spec is the opening cinematic's: `{"place": id, "bearing": deg, "distance": m,
## "height": m}`, a compass bearing and a distance from the place and `height` metres above the
## ground there (`PlaceRef`, `CinematicPath.point_of`), so a shot goes where its place goes when
## the map is drawn again. `tools/capture/relative_plan.py` turns a plan written in coordinates
## into one. Coordinates still work -- `"pos": [x, y, z]` with an optional `"height_above_ground"`,
## `"place"` alone for the place itself, `"look_at": [x, y, z]` -- and stay where they are.
##
## A `cinematic` block loads the world with its body standing where the story opens and has
## `CinematicPlayer` scrub to each shot's samples, so every frame on disk is the player's own
## frame -- letterbox, subtitle and title card included -- and writes <out>/cinematic.json with
## where each camera stood and how far above the ground.
##
## `"gaits": [ {gait}, ... ]` films several, each at its own place. A run's `"from": "behind"` films
## it over the body's shoulder, as the player's own camera does, instead of from its right side.
##
## A gait run may also hold keys and tap one, as real key events through the input map rather
## than as actions: {"label": "roll", "hold_keys": ["W"], "tap_key": "Shift", "tap_hold": 0.1}.
## A run's `"timeline": [[t, key, pressed], ...]` sends keys at times from its first frame, and
## `"horse": true` stands the player's horse (the Stable's cob) at the start first, its near side to
## the camera, with the body a pace off that side facing it: `E` then gets up.
## The tap comes after the settle and just before the first frame, so the frames film whatever
## the key does. "frames", "interval" and "settle" may be set per run.
##
## For each shot it sets the clock, moves the fly camera, waits until the streamer reports the
## full-detail ring loaded *and* something standing in it (plus ten frames so LODs and shadows
## settle), saves <index>_<label>.png and records Performance monitors into <out>/perf.json, with
## the light the frame was taken in (the sun's height and energy, the fill, the exposure).
##
## A shot whose cells are loaded but hold no scatter at all is a photograph of an empty county.
## It is marked `"unstreamed": true` in perf.json, kept out of the worst frame and the budget
## verdict, named on the document, and fails the run. A perf sheet that silently reports a third
## of the real cost is worse than no perf sheet, because somebody will act on it (DECISIONS.md,
## "A capture that photographs nothing fails the run").
##
## A shot may try a change to the light without editing the pack (`"light"` where `"look"` aims the
## camera): `"look": {"contrast": 1.0,
## "ambient_tint": "#a09ab2"}` lays region-light keys over the region's own for that shot
## (Atmosphere.look_override). `"terrain_view": "grey"` draws the ground in one of Terrain3D's
## debug views ("grey" is every material at albedo 0.2; "checkered", "colormap", "control"), which
## tells a dark texture from a dark light.
##
## A `gait` section films the player's own body in motion: it stands a player up on the ground
## at `at` (or `pos`), facing `heading` (a compass bearing), presses the run's actions exactly as a player
## would, lets it settle, and takes `frames` shots `interval` seconds apart from its left side.
## Run it with `--fixed-fps 60` so an interval is simulation time and not whatever the software
## rasteriser managed: every frame is then one physics tick.
##
## `"preview_pois": [ids]` stands those POIs up where their defs say, on pads laid at runtime, even
## when the built world has them somewhere else (PoiPreview): a place written or moved since the last
## world build, photographed before the next (tools/world/poi_sheet.py, docs/WORLD_LIFE.md).
##
## A shot's `"dress": {"kind", "region", "at": [x, z], "brief"?, "encounter"?, "radius"?}` stands up a
## point of interest of that kind on the ground there for the shot, as the world raises one from a
## POI def, and takes it down after: a kind can be photographed in the real country before the map
## puts one there (tools/capture/plans/poi_kinds.json).
##
## A fight, as the player meets it: `"quests": {"<quest id>": "<stage id>"}` puts each quest at that
## stage once the world stands (a shot may carry its own, set before its exposure), and a shot's `"body"` (a place spec or [x, _, z]) stands the player's body there,
## facing what the shot looks at, before its exposure. The world then does what it does with a
## player near, and a stage's foes are stood up round the place of its fight (QuestFoes), waited for
## up to FOES_WAIT_SECONDS. Put the shot's camera behind the body at a player's height; with
## `"face_foes": true` the body turns to the nearest of them and the camera follows it round.

const WORLD_SCENE := "res://world/world.tscn"
const PLAYER_SCENE := "res://actors/player/player.tscn"
## Everything a gait run may hold down, released between runs so one run cannot leak into the next.
const GAIT_ACTIONS: Array[String] = ["move_forward", "move_back", "move_left", "move_right", "sprint", "sneak", "walk"]
const SETTLE_FRAMES := 10
const MAX_WAIT_FRAMES := 240
## DESIGN.md §11. What `within_budget` in perf.json is measured against.
const BUDGET_DRAW_CALLS := 2000
const BUDGET_PRIMITIVES := 1500000
## Real seconds a shot with a body waits for the stage's foes to be stood up round it.
const FOES_WAIT_SECONDS := 30.0

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
## `--set=graphics.view_distance=0` sets one setting after the preset, in memory only, for an A/B of
## the same plan with one knob moved.
var overrides: Array[String] = []
## `--no-horizon` shoots the world as it was before the horizon layer: no stand-ins past the
## streamed ring and Terrain3D's clipmap at its old 32 vertices a ring, for a before and after.
var horizon := true
## `--no-sight`: a cinematic's shots ask only for the rings round their camera and what they look
## at, as before ShotSight (CinematicPlayer.sight_streaming), for a before and after of bare ground.
## `--no-film-picture`: a cinematic is drawn with the graphics settings as they stand, not with
## Graphics.FILM over them (CinematicPlayer.film_picture), for a before and after.
## `--measure=<frames>`: after each shot's exposure the game is left running that many frames and
## timed (PerfMeasure): the wall clock and the main thread's CPU a frame, the process and physics
## steps, what is drawn, memory and nodes, into the shot's `timing` in perf.json. A plan's `walks`
## are only taken with it. The frames are measured after the PNG is written, so the pictures are
## the plan's own either way.
var measure_frames := 0
## `--cpu-attribute`: with --measure, each shot also stops every script's processing in turn for a
## few frames and records how much the process and physics steps fell (PerfMeasure.attribute).
var cpu_attribute := false
## How the run came up: when the runner was ready and how long the world took to stand.
var _startup := {}
var _walks: Array = []
var _gameplay_cells_per_frame := 2
## The player's body a shot's `body` stands (one, moved from shot to shot).
var _body: Node3D = null
## The plan's `hud` section, when it asks for the HUD over its shots.
var _hud_spec: Dictionary = {}
## Where the stage's foes stood round the body, when they were last waited for.
var _foes_at: Array[Vector3] = []


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
		elif a.begins_with("--set="):
			overrides.append(a.substr(6))
		elif a == "--no-horizon":
			horizon = false
		elif a.begins_with("--measure="):
			measure_frames = int(a.substr(10))
		elif a == "--cpu-attribute":
			cpu_attribute = true
		elif a == "--no-sight":
			# a cinematic's shots ask only for the rings round their camera, as before ShotSight
			CinematicPlayer.sight_streaming = false
		elif a == "--no-film-picture":
			# a cinematic drawn with the settings as they stand, as before Graphics.FILM
			CinematicPlayer.film_picture = false
	# a measuring tool never writes the player's settings.cfg, preset or no preset
	Settings.persist = false
	if preset != "":
		if not Graphics.PRESETS.has(preset):
			Log.error("Capture", "no graphics preset %s (low, medium, high, painted)" % preset)
			get_tree().quit(2)
			return
		Settings.apply_graphics_preset(preset)
		Log.info("Capture", "graphics preset: %s" % preset)
	for o in overrides:
		var eq := o.find("=")
		var dot := o.find(".")
		if dot < 0 or eq < dot:
			Log.error("Capture", "--set= wants section.key=value, not %s" % o)
			continue
		var value: Variant = str_to_var(o.substr(eq + 1))
		Settings.set_value(o.substr(0, dot), o.substr(dot + 1, eq - dot - 1), value if value != null else o.substr(eq + 1))
		Log.info("Capture", "set %s" % o)
	var code: int = await run()
	get_tree().quit(code)


func run() -> int:
	var plan := _read_plan()
	if plan.is_empty():
		return 2
	DirAccess.make_dir_recursive_absolute(out_dir)
	# game flags set before the world stands up, so a plan can photograph the world as a given
	# moment of the story sees it: `{"new_game": true}` is the start as a new game has it, with
	# the Warden held at her fire (tools/capture/plans/start.json)
	var flags: Variant = plan.get("flags", {})
	if flags is Dictionary:
		for key: String in flags:
			GameState.set_flag(key, flags[key])
	if plan.has("cinematic"):
		return await _shoot_cinematic(plan["cinematic"])
	# `"preview_pois": [ids]`: those POIs stood up where their defs say, on pads laid now, whatever
	# the built world has (PoiPreview; tools/world/poi_sheet.py writes such a plan)
	PoiPreview.ask(plan.get("preview_pois", []))
	_startup["runner_ready_ms"] = Time.get_ticks_msec()
	var mem_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	if measure_frames > 0:
		# What is measured is the main thread: the software renderer here draws a frame in seconds,
		# which says nothing of a player's GPU and would pace the world's standing up to its frames.
		# Each shot's exposure is drawn; draw calls are counted there.
		RenderingServer.render_loop_enabled = false
	_world = await _load_world()
	if _world == null:
		Log.error("Capture", "world scene failed to load")
		return 1
	_startup["world_ready_ms"] = Time.get_ticks_msec()
	_startup["world_load_ms"] = int(_startup["world_ready_ms"]) - int(_startup["runner_ready_ms"])
	_startup["world_static_mem_mb"] = snappedf((Performance.get_monitor(Performance.MEMORY_STATIC) - mem_before) / 1048576.0, 0.1)
	if _world.streamer:
		_gameplay_cells_per_frame = _world.streamer.cells_per_frame
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
	_stage_quests(plan.get("quests", {}))
	_hud_spec = plan.get("hud", {}) if typeof(plan.get("hud", {})) == TYPE_DICTIONARY else {}
	if not _hud_spec.is_empty():
		_show_hud(_hud_spec)
	var shots: Array = plan.get("shots", [])
	Log.info("Capture", "%d shots -> %s" % [shots.size(), out_dir])
	var index := 0
	# a `sequences` section (see _sequence at the end of this file) is shot first
	for seq in plan.get("sequences", []):
		if typeof(seq) == TYPE_DICTIONARY:
			index = await _sequence(index, seq)
	for shot in shots:
		if typeof(shot) != TYPE_DICTIONARY:
			continue
		await _take_shot(index, shot)
		index += 1
	var fly: Dictionary = plan.get("flythrough", {})
	if not fly.is_empty():
		index = await _fly(index, fly)
	var gait: Dictionary = plan.get("gait", {})
	if not gait.is_empty():
		index = await _gait(index, gait)
	for more in plan.get("gaits", []):
		if typeof(more) == TYPE_DICTIONARY:
			index = await _gait(index, more)
	if measure_frames > 0:
		for walk in plan.get("walks", []):
			if typeof(walk) == TYPE_DICTIONARY:
				_walks.append(await PerfMeasure.walk(self, _world, walk, _gameplay_cells_per_frame))
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


func _load_world(with_body := false) -> World:
	var world_status := WorldStatus.current()
	if not bool(world_status.get("playable", false)):
		# a photograph of a void is not a photograph of the country
		Log.error("Capture", "%s %s" % [str(world_status.get("title", "")), str(world_status.get("detail", ""))])
		return null
	var packed: PackedScene = load(WORLD_SCENE)
	if packed == null:
		return null
	var w: Node = packed.instantiate()
	# A capture is a photograph of the country, taken from a planned camera. A body standing in
	# it would both block the shot and take the streaming off the plan, so the world is loaded
	# without one and keeps its fly camera -- except for a cinematic, whose last shot is of the
	# body, and which takes the camera and the streaming itself.
	var spawn: Node = w.get_node_or_null("PlayerSpawn")
	if spawn != null and not with_body:
		spawn.set("enabled", false)
		# ...but the world's services still go in, because they are what stands the villagers
		# up, and a photograph of a village with nobody in it is a photograph of a model.
		spawn.set("services_without_a_body", true)
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	# the world stands up in steps over many frames now; until it is up nothing 3D is drawn, and
	# every shot before it was an empty frame (0 draw calls)
	if w is World and not (w as World).is_world_ready:
		await (w as World).world_ready
	return w as World


## A shot's `"hide": ["cliff_ledge", "Poi_lark_mill/Face"]` hides, for that frame, every drawn thing
## whose node path or scatter asset holds one of the words: to say which thing in a frame is which,
## by taking it away and shooting again.
var _hidden_by_shot: Array = []


func _hide_for_shot(words_v: Variant) -> void:
	# what the last shot hid comes back first: each shot hides only what it names
	for n in _hidden_by_shot:
		if is_instance_valid(n):
			(n as Node3D).visible = true
	_hidden_by_shot.clear()
	if not (words_v is Array) or (words_v as Array).is_empty() or _world == null:
		return
	var hidden := 0
	for n in _world.find_children("*", "GeometryInstance3D", true, false):
		if not (n as Node3D).visible:
			continue
		var path := str(_world.get_path_to(n)) + " " + str(n.get_meta("asset_path", ""))
		for w in words_v:
			if path.contains(str(w)):
				(n as Node3D).visible = false
				_hidden_by_shot.append(n)
				hidden += 1
				break
	Log.info("Capture", "hid %d drawn things for %s" % [hidden, str(words_v)])


## A shot's `"materials": ["brightwater_boulder"]` logs, for every drawn thing whose path or asset
## names one of the words, each surface's material as the renderer has it: its class, its shader,
## and a shader material's parameters. What a probe outside the world reads is the material as it
## was made; this is the one the frame is drawn with.
func _report_materials(words_v: Variant) -> void:
	if not (words_v is Array) or (words_v as Array).is_empty() or _world == null:
		return
	var told := {}
	for n in _world.find_children("*", "GeometryInstance3D", true, false):
		var path := str(_world.get_path_to(n)) + " " + str(n.get_meta("asset_path", ""))
		var hit := false
		for w in words_v:
			hit = hit or path.contains(str(w))
		if not hit:
			continue
		var mesh: Mesh = null
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			mesh = (n as MultiMeshInstance3D).multimesh.mesh
		elif n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat: Material = (n as GeometryInstance3D).material_override
			if mat == null:
				mat = mesh.surface_get_material(s)
			if mat == null or told.has(mat.get_instance_id()):
				continue
			told[mat.get_instance_id()] = true
			var line := "%s s%d %s" % [n.name, s, mat.get_class()]
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
				var sm := mat as ShaderMaterial
				line += " %s" % sm.shader.resource_path.get_file()
				for u in sm.shader.get_shader_uniform_list():
					var v: Variant = sm.get_shader_parameter(u["name"])
					line += " %s=%s" % [u["name"], (v as Resource).get_class() + str((v as Texture2D).get_size()) if v is Texture2D else str(v)]
			Log.info("Capture", "material " + line)


## Terrain3D's debug view for a shot: "grey" (every material at albedo 0.2), "checkered",
## "colormap", "control", or "" for the textures.
func _set_terrain_view(view: String) -> void:
	var t3d: Variant = _world.get("terrain_node") if _world else null
	if not (t3d is Node):
		return
	var mat: Object = (t3d as Node).get("material")
	if mat == null:
		return
	var views := {"grey": "show_grey", "checkered": "show_checkered", "colormap": "show_colormap",
		"control": "show_control_texture"}
	for v in views:
		var want: bool = v == view
		if bool(mat.get(views[v])) != want:
			mat.set(views[v], want)


func _take_shot(index: int, shot: Dictionary) -> void:
	var label := str(shot.get("label", "shot_%d" % index))
	# a shot's own settings over the run's, applied live: `"set": {"graphics.occlusion": false}`
	# photographs one place with a knob off and on in one world (the run's --set= is for all of them)
	var own: Variant = shot.get("set", {})
	if own is Dictionary:
		for k: String in own:
			var dot := k.find(".")
			if dot > 0:
				Settings.set_value(k.substr(0, dot), k.substr(dot + 1), (own as Dictionary)[k])
	if shot.has("time"):
		# a shot's `day` (the clock's count from 1) photographs a day of the week: a market day
		WorldClock.set_time(float(shot["time"]), int(shot.get("day", -1)))
	if shot.has("weather"):
		_force_weather(str(shot["weather"]))
	# a shot may move the story on for itself: the tracker and the compass photographed at each stage
	if shot.has("quests"):
		_stage_quests(shot["quests"])
	var pos := _shot_position(shot)
	var cam := _world.fly_camera
	if cam == null:
		_failures.append("no fly camera for shot %s" % label)
		return
	cam.fov = float(shot.get("fov", 65.0))
	var look := _look_of(shot)
	if look != Vector3.INF:
		cam.move_to(pos, look)
	else:
		cam.move_to(pos)
		cam.set_yaw_pitch(float(shot.get("yaw", 0.0)), float(shot.get("pitch", -8.0)))
	if shot.has("body"):
		_stand_body(shot["body"], look)
	_world.move_target(pos)
	var staged := _dress_for(shot)
	var waited := await _wait_for_streaming()
	if _world.horizon != null:
		if not horizon:
			_world.horizon.visible = false
			if is_instance_valid(_world.terrain_node):
				_world.terrain_node.set("mesh_size", 32)
				World.share_clipmap(_world.terrain_node)
		Log.info("Capture", "%s: horizon %s" % [str(shot.get("label", index)),
				_world.horizon.summary() if horizon else "left out (--no-horizon)"])
	if shot.has("body"):
		waited += await _wait_for_foes(label)
		if bool(shot.get("face_foes", false)) and _face_the_foes(cam, pos, label):
			waited += await _wait_for_streaming()
	if shot.has("frame"):
		# Re-aim at something the world raised at runtime, now that it is standing: a waterfall's
		# sheet is built from the terrain's own grain, so no plan written beforehand knows which
		# way it faces.
		if _frame_node(cam, shot["frame"]):
			waited += await _wait_for_streaming()
		else:
			_failures.append("%s: nothing to frame for %s" % [label, str(shot["frame"])])
	# A region's look blends over six seconds when the camera crosses into it, which is right
	# for walking and wrong for a photograph: without this a shot taken a few frames after a
	# teleport was of half one region's light and half the last's. The lamps are handed out for
	# where the camera now is, rather than wherever it stood at their last tick.
	# Both are asked for by name, so this runner can still photograph a build from before either
	# existed: a before-and-after is only a comparison if the camera is the same on both sides.
	var atmos := _world.atmosphere
	# The plan's weather again, now the camera is standing in the shot's region: entering a region
	# starts that region's own weather, so a weather pinned before the move lasted only until the
	# region changed under it, and every shot that crossed a border took whatever the region's dice
	# gave (the Briarwold vista in rain, pinned "still"). Sheets were not repeatable across a
	# change to any region's weather odds.
	if shot.has("weather"):
		_force_weather(str(shot["weather"]))
	# A shot can lay values over the region's light ("look": {"ambient_energy": 2.0}), to try a
	# change beside the look as it stands without editing the pack, and can draw the ground in
	# one of Terrain3D's debug views ("terrain_view": "grey") to tell a dark texture from a dark
	# light. Both last for the one shot.
	# ("light" says the same where "look" is already the camera's place spec)
	if atmos:
		var light: Variant = shot.get("light", {} if PlaceRef.is_spec(shot.get("look", null)) else shot.get("look", {}))
		atmos.set("look_override", light if typeof(light) == TYPE_DICTIONARY else {})
	_set_terrain_view(str(shot.get("terrain_view", "")))
	_hide_for_shot(shot.get("hide", []))
	_report_materials(shot.get("materials", []))
	# `"debug_draw": "unshaded"` (or "lighting", "overdraw", "wireframe") draws the shot in one of the
	# viewport's debug views: unshaded is the albedo alone, which tells a colour from a light.
	var views := {"unshaded": Viewport.DEBUG_DRAW_UNSHADED, "lighting": Viewport.DEBUG_DRAW_LIGHTING,
			"overdraw": Viewport.DEBUG_DRAW_OVERDRAW, "wireframe": Viewport.DEBUG_DRAW_WIREFRAME}
	get_viewport().debug_draw = views.get(str(shot.get("debug_draw", "")), Viewport.DEBUG_DRAW_DISABLED)
	if atmos and atmos.has_method("settle"):
		atmos.call("settle")
	var lights: Variant = _world.get("night_lights")
	if lights != null and (lights as Object).has_method("rebuild_glow"):
		(lights as Object).call("rebuild_glow")
	if lights != null and (lights as Object).has_method("assign"):
		var st: Variant = atmos.get("state") if atmos else null
		(lights as Object).call("assign", float((st as Dictionary).get("night", 0.0)) if st is Dictionary else 0.0)
	if not _hud_spec.is_empty():
		await _settle_hud()
	if not RenderingServer.render_loop_enabled:
		# --measure keeps the software renderer off between exposures; it draws the shot's own
		# frames, a few first so the shadows and the LOD fades have been drawn once
		RenderingServer.render_loop_enabled = true
		for _i in PerfMeasure.DRAWN_BEFORE_EXPOSURE:
			await RenderingServer.frame_post_draw
	await get_tree().process_frame
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
	if mark_unstreamed(sample):
		# There is no --allow-unstreamed: no committed plan shoots anywhere the world is genuinely
		# bare, so the flag would have no honest use and one dishonest one.
		var empty := "%s photographed an empty world: %d cells loaded, not one scatter instance" \
			% [label, int(sample["cells_loaded"])]
		Log.warn("Capture", empty)
		_failures.append(empty + " -- the frame measures nothing")
	_perf.append(sample)
	# Only composed region shots go into the drop-test folder, filed under the region the plan
	# says they are about; the flythrough deliberately crosses boundaries, so its frames are
	# not a picture of any one region.
	_write_region_copy(img, str(shot.get("region", "")), label)
	Log.info("Capture", "%s: %s (%d draw calls, %.2f M primitives, %d frames waited)"
		% [label, path.get_file(), int(_perf[-1]["draw_calls"]), float(_perf[-1]["primitives"]) / 1e6, waited])
	if measure_frames > 0:
		RenderingServer.render_loop_enabled = false
		Log.info("Capture", "%s: measuring %d frames" % [label, measure_frames])
		sample["timing"] = await PerfMeasure.frames(self, measure_frames)
		Log.info("Capture", "%s: %s" % [label, PerfMeasure.line(sample["timing"])])
		Log.info("Capture", "between: shots")
		if cpu_attribute and bool(shot.get("cpu_attribute", false)):
			sample["cpu_by_script"] = await PerfMeasure.attribute(self)
	if attribute:
		await _attribute_shot(label, cam)
	if staged != null:
		staged.queue_free()


## A point of interest the plan stands up for its shot, of a kind the world may have none of yet:
## `"dress": {"kind": "mill", "region": "core:region/hearthvale", "at": [x, z], "brief": "the mill
## on the Larkbourne", "encounter": "", "radius": 30}`. It is raised on the ground there as the world
## raises a POI def of that kind, with the world's roads, and taken down after the shot.
func _dress_for(shot: Dictionary) -> Node3D:
	var spec: Variant = shot.get("dress", null)
	if not (spec is Dictionary):
		return null
	var at: Array = (spec as Dictionary).get("at", [0.0, 0.0])
	var x := float(at[0])
	var z := float(at[1])
	var provider := World.terrain()
	var y := provider.get_height(x, z) if provider != null else 0.0
	if spec.has("scene"):
		# a scene as a cell's `scenes` entry stands it (a town stone): at the ground, turned to `yaw`,
		# configured with `props`
		var packed := load(str(spec["scene"])) as PackedScene
		if packed == null:
			return null
		# drawn as a cell draws it: a carved landmark or a rock in the painted stone
		RockPaint.paint_scene(packed, str(spec["scene"]))
		var inst := packed.instantiate() as Node3D
		if inst.has_method("configure"):
			inst.call("configure", spec.get("props", {}))
		# set into the ground as a cell sets it (a carved landmark's `buried_m`)
		inst.position = Vector3(x, y - WorldStreamer.seated_depth(str(spec["scene"])), z)
		inst.rotation.y = deg_to_rad(float(spec.get("yaw", 0.0)))
		_world.add_child(inst)
		return inst
	var kind := str(spec.get("kind", ""))
	var id := "core:poi/staged_%s" % kind
	var entry := {"place_id": id, "pos": [x, y, z], "radius_flat_m": float(spec.get("radius", 30.0))}
	var def := {"id": id, "name": kind.capitalize(), "kind": kind, "region": str(spec.get("region", "")),
			"unique_feature": str(spec.get("brief", "")), "encounter": str(spec.get("encounter", ""))}
	var d := PoiDressing.raise(entry, def, false, provider, WorldPois.roads_from_disk())
	_world.add_child(d)
	Log.info("Capture", "stood a %s up at (%.0f, %.1f, %.0f) for the shot" % [kind, x, y, z])
	return d


## Puts the camera in front of a mesh raised under a named node -- `{"node": "Poi_whitecut_falls",
## "child_prefix": "Fall", "distance": 22, "height": 2}` -- facing it. The facing is read off the
## mesh: its area-weighted normal, turned toward the side its lower edge bulges to, which for a
## sheet of falling water is the side the water falls away from the rock on.
func _frame_node(cam: FlyCamera, spec: Dictionary) -> bool:
	var host := _world.find_child(str(spec.get("node", "")), true, false)
	if host == null:
		return false
	var prefix := str(spec.get("child_prefix", ""))
	var target: MeshInstance3D = null
	for n in host.find_children("*", "MeshInstance3D", true, false):
		if prefix == "" or str(n.name).begins_with(prefix):
			target = n as MeshInstance3D
			break
	if target == null or target.mesh == null:
		return false
	var faces := target.mesh.get_faces()
	var normal := Vector3.ZERO
	var i := 0
	while i + 2 < faces.size():
		normal += (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])
		i += 3
	var box: AABB = target.global_transform * target.get_aabb()
	var centre := box.get_center()
	normal = (target.global_transform.basis * normal)
	normal.y = 0.0
	if normal.length() < 0.001:
		return false
	normal = normal.normalized()
	# a sheet bulges out at its foot: the camera belongs on that side
	var low := Vector3.ZERO
	var high := Vector3.ZERO
	var nl := 0
	var nh := 0
	for p in faces:
		var g: Vector3 = target.global_transform * p
		if g.y < centre.y:
			low += g
			nl += 1
		else:
			high += g
			nh += 1
	if nl > 0 and nh > 0:
		var out := low / float(nl) - high / float(nh)
		out.y = 0.0
		if out.dot(normal) < 0.0:
			normal = -normal
	var at := centre + normal * float(spec.get("distance", 22.0))
	var ground := _world.provider.get_height(at.x, at.z)
	at.y = maxf(at.y, ground + float(spec.get("height", 2.0)))
	cam.move_to(at, centre)
	_world.move_target(at)
	Log.info("Capture", "framed %s/%s from %s" % [host.name, target.name, str(at.snapped(Vector3(0.1, 0.1, 0.1)))])
	return true


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


## What the per-frame systems cost over the whole run: the night-light glow rebuilds and pool
## assignments and the grade LUT rebuilds, each count, total and worst in microseconds. Asked for by
## name, so a build from before either existed still runs.
func _costs() -> Dictionary:
	var out := {}
	for node in [_world.get("night_lights") if _world else null, _world.atmosphere if _world else null]:
		if node != null and (node as Object).has_method("costs"):
			out.merge((node as Object).call("costs"))
	return out


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
	if PlaceRef.is_spec(shot.get("at", null)):
		var at := _spec_point(shot["at"])
		if at == Vector3.INF:
			_failures.append("%s: no place %s" % [str(shot.get("label", "?")), str(shot["at"].get("place", ""))])
			return Vector3.ZERO
		return at
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


## Where a shot (or a sequence) looks: its `look` place spec, else its `look_at` coordinates;
## Vector3.INF when it says neither and aims by yaw and pitch instead.
func _look_of(shot: Dictionary) -> Vector3:
	if PlaceRef.is_spec(shot.get("look", null)):
		return _spec_point(shot["look"])
	var la: Variant = shot.get("look_at", null)
	if typeof(la) == TYPE_ARRAY and (la as Array).size() >= 3:
		return Vector3(float(la[0]), float(la[1]), float(la[2]))
	return Vector3.INF


## A place spec or [x, y, z] as a point in this world; Vector3.INF for anything else.
func _point_of(v: Variant) -> Vector3:
	if PlaceRef.is_spec(v):
		return _spec_point(v)
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.INF


## A place spec in this world, as the opening's cinematic resolves one (the place's built
## position, the terrain under the point), so a plan and the cinematic agree about a bearing.
func _spec_point(spec: Dictionary) -> Vector3:
	return CinematicPath.point_of(spec, Callable(self, "_ground_at"), Callable(self, "_place_at"))


func _ground_at(x: float, z: float) -> float:
	return _world.provider.get_height(x, z)


func _place_at(id: String) -> Vector3:
	if id.is_empty() or not ContentDB.has(id):
		return Vector3.INF
	var at := _world.place_position(id)
	return Vector3.INF if at == Vector3.ZERO else at


## Puts each quest a plan names at the stage it names (see the header), starting it if need be.
func _stage_quests(quests: Variant) -> void:
	if not (quests is Dictionary) or (quests as Dictionary).is_empty():
		return
	var log_node := get_tree().get_first_node_in_group("quest_log")
	if log_node == null or not log_node.has_method("set_stage"):
		_failures.append("no quest log to put %s in" % str(quests))
		return
	for id: String in quests:
		log_node.call("set_stage", id, quests[id])
		Log.info("Capture", "%s is at stage %d" % [id, int(log_node.call("stage_of", id))])


## Stands the player's body at `at` (its x and z, on the ground), facing `look` when there is one.
## `at` is a place spec or [x, y, z], as a shot's camera is. The plan's camera stays the one
## drawing: the body's own rig makes itself current when it comes in.
func _stand_body(at_v: Variant, look: Vector3) -> void:
	var at := _point_of(at_v)
	if at == Vector3.INF:
		_failures.append("a shot's body is a place spec or [x, y, z], not %s" % str(at_v))
		return
	if _body == null:
		_body = (load(PLAYER_SCENE) as PackedScene).instantiate() as Node3D
		_world.add_child(_body)
		_world.fly_camera.make_current()
	var p := Vector3(at.x, 0.0, at.z)
	p.y = _world.provider.get_height(p.x, p.z) + 0.05
	_body.set("velocity", Vector3.ZERO)
	_body.global_position = p
	if look != Vector3.INF:
		var to := Vector3(look.x - p.x, 0.0, look.z - p.z)
		if to.length() > 0.01:
			_body.rotation.y = atan2(-to.x, -to.z)
			var rig: Node = _body.get("camera_rig")
			if rig != null:
				rig.set("yaw", _body.rotation.y)
	_body.reset_physics_interpolation()
	Log.info("Capture", "the body stands at %s" % str(p.snapped(Vector3.ONE * 0.1)))


## A plan's `"hud": {"discovered": [ids] | "all" | "none"}` puts the game's HUD over every shot,
## with those places found, so the compass strip can be looked at where a player stands (a shot
## with a `body` gives the HUD its player; without one the strip reads the camera).
func _show_hud(spec: Dictionary) -> void:
	var found: Variant = spec.get("discovered", "none")
	if typeof(found) == TYPE_STRING and str(found) == "all":
		for type in ["place", "poi"]:
			for def in ContentDB.all(type):
				GameState.discover(str(def.get("id", "")))
	elif typeof(found) == TYPE_ARRAY:
		for id in found:
			GameState.discover(str(id))
	var hud := UI.show_hud()
	if hud == null:
		_failures.append("the plan asks for the HUD and there is none")
		return
	UI.hud_layer.visible = true
	hud.visible = true
	Log.info("Capture", "the HUD over every shot, %d places found" % GameState.discovered_places.size())


## The HUD told where the body is, awake (not faded for idling) and its compass chosen afresh, then
## given a few frames to draw it. Logs what the strip shows.
func _settle_hud() -> void:
	var hud := UI.hud()
	if hud == null:
		return
	hud.call("_connect_world")
	hud.call("_rebuild_markers")
	hud.set("_idle", 0.0)
	(hud as CanvasItem).modulate.a = 1.0
	for i in 4:
		await get_tree().process_frame
	if hud.has_method("compass_marker_labels"):
		Log.info("Capture", "the compass shows: %s" % ", ".join(hud.call("compass_marker_labels")))
	if hud.has_method("tracked_waymarks"):
		for w in hud.call("tracked_waymarks"):
			Log.info("Capture", "tracked: %s [%s] at %s" % [str(w["text"]), str(w["detail"]),
					str((w["xz"] as Vector2).round()) if bool(w["ok"]) else "nowhere"])
		for i in 2:
			await get_tree().process_frame


## After a body is stood: waits until every fight a current stage wants within QuestFoes.STAND_M of
## it has its group standing, or FOES_WAIT_SECONDS have gone on the wall clock, and says which not.
func _wait_for_foes(label: String) -> int:
	var foes := get_tree().get_first_node_in_group(QuestFoes.GROUP) as QuestFoes
	if foes == null or _body == null:
		return 0
	var frames := 0
	var until := Time.get_ticks_msec() + int(FOES_WAIT_SECONDS * 1000.0)
	var missing: Array[String] = []
	while true:
		missing.clear()
		var want := foes.wanted()
		for key: String in want:
			var at: Vector3 = (want[key] as Dictionary)["at"]
			var d := Vector2(at.x - _body.global_position.x, at.z - _body.global_position.z).length()
			if d <= QuestFoes.STAND_M and foes.group_for(key) == null:
				missing.append(key)
		if missing.is_empty() or Time.get_ticks_msec() >= until:
			break
		await get_tree().process_frame
		frames += 1
	if not missing.is_empty():
		Log.warn("Capture", "%s: nothing stood for %s in %.0f s" % [label, ", ".join(missing), FOES_WAIT_SECONDS])
	# the foes are drawn on the frames after they stand: a few more for their pose and shadows
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
		frames += 1
	_foes_at.clear()
	var words: Array[String] = []
	for key: String in foes.wanted():
		var group := foes.group_for(key)
		if group == null:
			continue
		for e: Enemy in group.alive():
			_foes_at.append(e.global_position)
			words.append(str(e.global_position.snapped(Vector3.ONE * 0.1)))
	if not words.is_empty():
		Log.info("Capture", "%s: the stage's foes stand at %s" % [label, ", ".join(words)])
	return frames


## A shot's `"face_foes": true` turns the body to the nearest of the foes stood round it, as a player
## turns to the first of a fight, and puts the camera behind it again, as far back and as high as the
## plan had it: a place's foes are stood on clear ground round it, and a plan written beforehand does
## not know which side that is.
func _face_the_foes(cam: FlyCamera, pos: Vector3, label: String) -> bool:
	if _foes_at.is_empty() or _body == null:
		return false
	var body := _body.global_position
	var nearest := _foes_at[0]
	for p in _foes_at:
		if Vector2(p.x - body.x, p.z - body.z).length() < Vector2(nearest.x - body.x, nearest.z - body.z).length():
			nearest = p
	var to := Vector3(nearest.x - body.x, 0.0, nearest.z - body.z)
	if to.length() < 0.5:
		return false
	var ahead := to.normalized()
	_body.rotation.y = atan2(-ahead.x, -ahead.z)
	var rig: Node = _body.get("camera_rig")
	if rig != null:
		rig.set("yaw", _body.rotation.y)
	var back := Vector2(pos.x - body.x, pos.z - body.z).length()
	var lift := pos.y - _world.provider.get_height(pos.x, pos.z)
	var at := body - ahead * back
	at.y = _world.provider.get_height(at.x, at.z) + lift
	cam.move_to(at, nearest + Vector3.UP * 1.2)
	_world.move_target(at)
	Log.info("Capture", "%s: turned to the nearest of the foes, %.0f m off" % [label, to.length()])
	return true


## Waits until the streamer has the full-detail ring around the camera *with something in it*,
## then lets the frame settle (LOD selection, shadow splits and the water's first animation step).
##
## `is_ring_loaded()` answers whether the ring was built -- a cell node per cell and nothing
## pending -- and is true of a ring of cells that hold no scatter at all, because a cell can
## legitimately be empty. That is the right contract for the streamer and the wrong question for a
## photograph, so the wait asks for instances too. The frame cap keeps a bare place a slow shot
## rather than a hung one; still bare when the cap runs out, the shot is flagged (mark_unstreamed)
## and the run fails rather than quietly recording an empty frame.
func _wait_for_streaming() -> int:
	var frames := 0
	# undrawn (--measure), a frame is short and the streaming paced to it: many more of them
	while frames < (MAX_WAIT_FRAMES if RenderingServer.render_loop_enabled else MAX_WAIT_FRAMES * 20):
		await get_tree().process_frame
		frames += 1
		if _world.streamer == null:
			break
		if _world.streamer.is_ring_loaded() and _world.streamer.instance_count() > 0:
			break
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
		frames += 1
	if RenderingServer.render_loop_enabled:
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
		"light": _light_now(),
	}


## Marks a sample that photographed nothing, and says whether it did.
##
## Cells round the camera and not one scatter instance standing in them means the world did not
## stream -- a failed resource load, a streamer never set up -- and the monitors then record the
## cost of an empty county as the cost of the country. `cells_loaded` of zero is another thing
## (nothing has streamed at all, so there is nothing yet to disbelieve), and a real scatter count is
## all the evidence needed that the world is there.
static func mark_unstreamed(sample: Dictionary) -> bool:
	if int(sample.get("cells_loaded", 0)) <= 0:
		return false
	if int(sample.get("scatter_instances", 0)) > 0:
		return false
	sample["unstreamed"] = true
	return true


## The budget verdict over the shots that photographed the world.
##
## Flagged shots are left out rather than counted: an empty frame is cheap, so counting one can only
## make a sheet look better than the world is. A sheet with nothing left to measure is not within
## budget -- it has no verdict at all, and false is the safe reading.
static func verdict(samples: Array) -> Dictionary:
	var worst_draw := 0
	var worst_prims := 0
	var counted := 0
	var excluded: Array[String] = []
	for p: Dictionary in samples:
		if bool(p.get("unstreamed", false)):
			excluded.append(str(p.get("label", "?")))
			continue
		counted += 1
		worst_draw = maxi(worst_draw, int(p.get("draw_calls", 0)))
		worst_prims = maxi(worst_prims, int(p.get("primitives", 0)))
	return {
		"worst": {"draw_calls": worst_draw, "primitives": worst_prims},
		"within_budget": counted > 0 and worst_draw <= BUDGET_DRAW_CALLS and worst_prims <= BUDGET_PRIMITIVES,
		"shots_counted": counted,
		"unstreamed_shots": excluded,
	}


## The light the frame was taken in, so a sheet can be read against the numbers that made it: the
## sun's height and energy, the fill's energy, colour and share of sky, and the exposure.
func _light_now() -> Dictionary:
	var atmos: Variant = _world.atmosphere if _world else null
	if atmos == null:
		return {}
	var out := {}
	var st: Variant = (atmos as Object).get("state")
	if st is Dictionary:
		out["elevation"] = snappedf(float((st as Dictionary).get("elevation", 0.0)), 0.1)
	var sun: Variant = (atmos as Object).get("sun")
	if sun is DirectionalLight3D:
		out["sun_energy"] = snappedf((sun as DirectionalLight3D).light_energy, 0.01)
	var env: Variant = (atmos as Object).get("env")
	if env is Environment:
		var e := env as Environment
		out["ambient_energy"] = snappedf(e.ambient_light_energy, 0.01)
		out["ambient_color"] = "#" + e.ambient_light_color.to_html(false)
		out["sky_contribution"] = snappedf(e.ambient_light_sky_contribution, 0.01)
		out["exposure"] = snappedf(e.tonemap_exposure, 0.01)
	return out


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


## Films the player's body walking, jogging and sprinting (see the `gait` plan section above).
## The body is the real player scene driven through the real input actions, so what is in the
## frames is what a player's key presses produce, not a clip played on a mannequin.
func _gait(index: int, gait: Dictionary) -> int:
	var cam := _world.fly_camera
	if cam == null:
		_failures.append("no fly camera for the gait sequence")
		return index
	if gait.has("time"):
		WorldClock.set_time(float(gait["time"]))
	if gait.has("weather"):
		_force_weather(str(gait["weather"]))
	var start := Vector3.ZERO
	if PlaceRef.is_spec(gait.get("at", null)):
		start = _spec_point(gait["at"])
		if start == Vector3.INF:
			_failures.append("gait: no place %s" % str(gait["at"].get("place", "")))
			return index
	else:
		var p: Array = gait.get("pos", [0.0, 0.0, 0.0])
		start = Vector3(float(p[0]), 0.0, float(p[2]))
	start.y = _world.provider.get_height(start.x, start.z)
	var bearing := deg_to_rad(float(gait.get("heading", 90.0)))
	var travel := Vector3(sin(bearing), 0.0, -cos(bearing))        # north is -Z (CONTRACTS §1)
	var yaw := atan2(-travel.x, -travel.z)
	var right := Basis(Vector3.UP, -PI * 0.5) * travel             # film from the right: motion runs left to right
	var cam_cfg: Dictionary = gait.get("camera", {})
	var distance := float(cam_cfg.get("distance", 4.2))
	var cam_height := float(cam_cfg.get("height", 1.0))
	cam.fov = float(cam_cfg.get("fov", 50.0))
	var frames := int(gait.get("frames", 8))
	var interval := float(gait.get("interval", 0.1))
	var settle := float(gait.get("settle", 1.6))
	_world.move_target(start + right * distance + Vector3.UP * cam_height, start + Vector3.UP)
	await _wait_for_streaming()
	# Under the software rasteriser a frame of the country takes seconds, and a gait needs a
	# hundred simulated ticks between shots. Only the frames that are saved are drawn.
	RenderingServer.render_loop_enabled = false
	var packed := load(PLAYER_SCENE) as PackedScene
	var player := packed.instantiate() as Node3D
	_world.add_child(player)
	# The body's own camera rig makes itself current on _ready; this is a side view.
	cam.set_process(false)          # it reads the same move actions the body is being given
	cam.make_current()
	for run in gait.get("runs", []):
		if typeof(run) != TYPE_DICTIONARY:
			continue
		var label := str(run.get("label", "run"))
		_release_gait_actions()
		player.set("velocity", Vector3.ZERO)
		player.global_position = start + Vector3.UP * 0.05
		player.rotation.y = yaw
		var rig: Node = player.get("camera_rig")
		if rig != null:
			rig.set("yaw", yaw)
		if player.has_method("full_restore"):
			player.call("full_restore")
		player.set("is_sneaking", false)       # a toggle: one run's sneak must not leak into the next
		player.reset_physics_interpolation()
		if bool(run.get("horse", false)):
			await _stand_horse(player, start, yaw)
		await _physics_seconds(0.25)
		for action in run.get("press", []):
			if InputMap.has_action(str(action)):
				Input.action_press(str(action))
			else:
				Log.warn("Capture", "gait run %s: no input action '%s'" % [label, str(action)])
		for k in run.get("hold_keys", []):
			_send_key(str(k), true)
		await _physics_seconds(float(run.get("settle", settle)))
		if run.has("tap_key"):
			_send_key(str(run["tap_key"]), true)
			await _physics_seconds(float(run.get("tap_hold", 0.1)))
			_send_key(str(run["tap_key"]), false)
		var run_frames := int(run.get("frames", frames))
		var run_interval := float(run.get("interval", interval))
		var behind := str(run.get("from", "right")) == "behind"
		var timeline: Array = (run.get("timeline", []) as Array).duplicate()
		var run_t := 0.0
		for f in run_frames:
			while not timeline.is_empty() and float(timeline[0][0]) <= run_t + 0.0001:
				var k: Array = timeline.pop_front()
				_send_key(str(k[1]), bool(k[2]))
			var at := player.get_global_transform_interpolated().origin
			if behind:
				cam.move_to(at - travel * distance + Vector3.UP * (cam_height + 0.7), at + travel * 1.5 + Vector3.UP * 1.0)
			else:
				cam.move_to(at + right * distance + Vector3.UP * cam_height, at + Vector3.UP * 0.95)
			RenderingServer.render_loop_enabled = true
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			RenderingServer.render_loop_enabled = false
			var shot_label := "gait_%s_%02d" % [label, f]
			var path := "%s/%02d_%s.png" % [out_dir, index, shot_label]
			var img := get_viewport().get_texture().get_image()
			if img.save_png(path) != OK:
				_failures.append("cannot write %s" % path)
			var v: Vector3 = player.get("velocity")
			var state := str(player.call("state_name")) if player.has_method("state_name") else "?"
			var untouchable := bool(player.call("is_in_iframes")) if player.has_method("is_in_iframes") else false
			var anim: Node = player.get("anim")
			var clip := str(anim.get("current_clip")) if anim != null else ""
			Log.info("Capture", "%s: speed %.2f m/s, stamina %.0f, %s%s, clip %s, at %s" % [shot_label,
					Vector2(v.x, v.z).length(), float(player.get("stamina")), state,
					" (untouchable)" if untouchable else "", clip, str(player.global_position.snapped(Vector3.ONE * 0.01))])
			index += 1
			await _physics_seconds(run_interval)
			run_t += run_interval
		for k in run.get("timeline", []):
			_send_key(str(k[1]), false)
		for k in run.get("hold_keys", []):
			_send_key(str(k), false)
		_release_gait_actions()
	RenderingServer.render_loop_enabled = true
	player.queue_free()
	cam.set_process(true)
	cam.make_current()
	return index


## The player's cob, stood at `at` facing the other way from the run (so its near side is toward the
## camera, which films from the run's right), and the body a pace off that side facing it.
func _stand_horse(player: Node3D, at: Vector3, yaw: float) -> void:
	var stable := Stable.find(self)
	if stable == null:
		_failures.append("gait: no Stable in the world to stand a horse")
		return
	var horse: Node3D = null
	for i in 60:
		horse = stable.give("core:mount/wardens_cob", false)
		if horse != null:
			break
		await get_tree().physics_frame
	if horse == null:
		_failures.append("gait: the Stable stood no horse")
		return
	var heading := yaw + PI
	horse.call("place", at, heading)
	var near := at + Basis(Vector3.UP, heading) * Vector3(-1.7, 0.0, -0.2)
	near.y = _world.provider.get_height(near.x, near.z) + 0.02
	player.global_position = near
	player.rotation.y = heading - PI * 0.5        # facing the horse's near side
	var rig: Node = player.get("camera_rig")
	if rig != null:
		rig.set("yaw", player.rotation.y)
	player.reset_physics_interpolation()
	await _physics_seconds(0.5)


## A key as a keyboard sends it, through the input map (so through the bindings the game set up):
## a modifier key reports itself held while it is down.
func _send_key(name: String, pressed: bool) -> void:
	var code := OS.find_keycode_from_string(name)
	if code == KEY_NONE:
		Log.warn("Capture", "no key called '%s'" % name)
		return
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.key_label = code
	ev.pressed = pressed
	ev.ctrl_pressed = pressed and code == KEY_CTRL
	ev.shift_pressed = pressed and code == KEY_SHIFT
	ev.alt_pressed = pressed and code == KEY_ALT
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _release_gait_actions() -> void:
	for action in GAIT_ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)


## Waits for `seconds` of simulated time, counted in physics ticks rather than wall-clock.
func _physics_seconds(seconds: float) -> void:
	var until := Engine.get_physics_frames() + int(round(seconds * Engine.physics_ticks_per_second))
	while Engine.get_physics_frames() < until:
		await get_tree().physics_frame


func _write_perf() -> void:
	var v := verdict(_perf)
	var excluded: Array = v["unstreamed_shots"]
	var worst_draw := int(v["worst"]["draw_calls"])
	var worst_prims := int(v["worst"]["primitives"])
	var doc := {
		"generated_at": Time.get_datetime_string_from_system(),
		"renderer": RenderingServer.get_current_rendering_method(),
		# The window size is what the 3D scene is actually rendered at, and what the saved PNG
		# measures; the project's base viewport only sets the 2D stretch reference.
		"resolution": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"base_viewport": [int(ProjectSettings.get_setting("display/window/size/viewport_width")),
			int(ProjectSettings.get_setting("display/window/size/viewport_height"))],
		"budget": {"draw_calls": BUDGET_DRAW_CALLS, "primitives": BUDGET_PRIMITIVES},
		"graphics_preset": str(Settings.get_value("graphics", "preset", "")),
		"graphics": (Settings.data.get("graphics", {}) as Dictionary).duplicate(),
		"worst": v["worst"],
		"within_budget": v["within_budget"],
		# what the verdict was taken over, beside the verdict and not only in the log: a reader has
		# to see that shots were thrown away without going back to the run that made the sheet
		"shots_measured": int(v["shots_counted"]),
		"shots_unstreamed": excluded,
		"costs": _costs(),
		"shots": _perf,
	}
	if measure_frames > 0:
		doc["startup"] = _startup
		doc["walks"] = _walks
	var f := FileAccess.open("%s/perf.json" % out_dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(doc, "  "))
		f.close()
	Log.info("Capture", "worst frame: %d draw calls, %.2f M primitives (budget %d / %.1f M), over %d shots"
		% [worst_draw, float(worst_prims) / 1e6, BUDGET_DRAW_CALLS, float(BUDGET_PRIMITIVES) / 1e6,
			int(v["shots_counted"])])
	if not excluded.is_empty():
		Log.warn("Capture", "%d of %d shots did not stream and are not in the verdict: %s"
			% [excluded.size(), _perf.size(), ", ".join(PackedStringArray(excluded))])
	Log.info("Capture", "costs: %s" % JSON.stringify(doc["costs"]))


# --- sequences ------------------------------------------------------------------------------

## `"sequences": [{"label", "pos", "look_at", "height_above_ground", "fov", "time", "weather",
## "from_region", "region", "frames": n, "every": seconds, "to": [x, y, z]}]` in a plan. With
## `to` the camera travels there over the run, looking the same way, so what flashes as the
## camera moves shows too.
##
## A run of frames from one camera with the game left running between them, for what a single
## exposure cannot show: a flash, a flicker, a blend. With `from_region` the look is settled
## there first and then left to blend into `region`, as it does when you walk over the border.
## Every frame drawn is measured -- its mean brightness, and whether the grade's table was
## rebuilt for it -- not only the ones saved every `every` seconds, because a flash can be one
## frame long; a frame brighter or darker than both its neighbours by more than FLASH_STEP is
## saved as well and reported as a FLASH, and every frame under half the run's median brightness
## is counted as DARK (a flash can also last half a second: the grade swap drew ten black frames
## in a row on Forward+). A thing that flashes on its own -- a roof going black for a frame, a
## wall fighting the ground -- hardly moves a frame's mean, so each frame is also sampled on a
## grid and the samples that jump by more than FLICKER_STEP and come straight back are counted:
## the frames with most of them are saved as `_flicker_` for looking at. Run it with --fixed-fps, so the game's time between two frames does not
## depend on how slowly this machine draws them.
const FLASH_STEP := 0.06
const FLICKER_STEP := 0.25
const FLICKER_GRID := Vector2i(160, 90)
const FLICKER_SAVES := 6


func _sequence(index: int, seq: Dictionary) -> int:
	var label := str(seq.get("label", "sequence"))
	if seq.has("time"):
		WorldClock.set_time(float(seq["time"]))
	if seq.has("weather"):
		_force_weather(str(seq["weather"]))
	var pos := _shot_position(seq)
	var cam := _world.fly_camera
	if cam == null:
		_failures.append("no fly camera for sequence %s" % label)
		return index
	cam.fov = float(seq.get("fov", 65.0))
	var look := _look_of(seq)
	if look != Vector3.INF:
		cam.move_to(pos, look)
	else:
		cam.move_to(pos)
		cam.set_yaw_pitch(float(seq.get("yaw", 0.0)), float(seq.get("pitch", -8.0)))
	_world.move_target(pos)
	await _wait_for_streaming()
	var atmos := _world.atmosphere
	if seq.has("weather"):
		_force_weather(str(seq["weather"]))
	var to := str(seq.get("region", _world.provider.nearest_region_id_at(pos.x, pos.z)))
	if atmos and seq.has("from_region"):
		atmos.call("set_region", str(seq["from_region"]), true)
		atmos.call("settle")
		await get_tree().process_frame
		atmos.call("set_region", to, false)
	var want := int(seq.get("frames", 40))
	var every := float(seq.get("every", 0.25))
	var start_pos := pos
	var end_pos := pos
	if seq.get("to", null) is Array:
		var t: Array = seq["to"]
		end_pos = Vector3(float(t[0]), float(t[1]), float(t[2]))
	elif PlaceRef.is_spec(seq.get("to", null)):
		end_pos = _spec_point(seq["to"])
		if end_pos == Vector3.INF:
			end_pos = pos
	var look_off := Vector3.ZERO
	if look != Vector3.INF:
		look_off = look - start_pos
	var travel := float(want) * every
	var grid_a := PackedFloat32Array()
	var grid_b := PackedFloat32Array()
	var flicker_worst := 0
	var flicker_frames := 0
	var flicker_saved := 0
	var lums: Array[float] = []
	var luts: Array[int] = []
	var prev_img: Image = null
	var clock := 0.0
	var next_save := 0.0
	var saved := 0
	var flashes: Array[String] = []
	var builds_at_start := _grade_builds()
	var drawn := 0
	while saved < want and drawn < want * 200:
		await RenderingServer.frame_post_draw
		drawn += 1
		clock += get_process_delta_time()
		var img := get_viewport().get_texture().get_image()
		var lum := _mean_luminance(img)
		# samples that jumped in the frame before this one and came straight back
		var grid := _luma_grid(img)
		if grid_a.size() == grid.size() and grid_b.size() == grid.size():
			var spikes := 0
			for i in grid.size():
				var da := grid_b[i] - grid_a[i]
				var dc := grid_b[i] - grid[i]
				if da * dc > 0.0 and minf(absf(da), absf(dc)) > FLICKER_STEP:
					spikes += 1
			flicker_worst = maxi(flicker_worst, spikes)
			if spikes * 500 > grid.size():
				flicker_frames += 1
				if prev_img and flicker_saved < FLICKER_SAVES:
					flicker_saved += 1
					prev_img.save_png("%s/%02d_%s_flicker_%03d.png" % [out_dir, index, label, lums.size() - 1])
					Log.info("Capture", "FLICKER %s frame %d at %.2f s: %d of %d samples jumped and came back"
						% [label, lums.size() - 1, clock, spikes, grid.size()])
		grid_a = grid_b
		grid_b = grid
		if end_pos != start_pos:
			var p := start_pos.lerp(end_pos, clampf(clock / maxf(travel, 0.001), 0.0, 1.0))
			if seq.has("height_above_ground"):
				p.y = _world.provider.get_height(p.x, p.z) + float(seq["height_above_ground"])
			cam.move_to(p, p + look_off if look != Vector3.INF else null)
		var builds := _grade_builds() - builds_at_start
		lums.append(lum)
		luts.append(builds)
		# the frame before this one is a flash if it stands out from both of its neighbours
		var n := lums.size()
		if n >= 3:
			var a := lums[n - 3]
			var b := lums[n - 2]
			if (b - a) * (b - lum) > 0.0 and minf(absf(b - a), absf(b - lum)) > FLASH_STEP:
				var fpath := "%s/%02d_%s_flash_%03d.png" % [out_dir, index, label, n - 2]
				if prev_img:
					prev_img.save_png(fpath)
				flashes.append("frame %d at %.2f s: %.3f between %.3f and %.3f (grade tables built so far %d)"
					% [n - 2, clock, b, a, lum, luts[n - 2]])
		prev_img = img
		if clock + 0.0001 >= next_save:
			var path := "%s/%02d_%s_%03d.png" % [out_dir, index, label, saved]
			img.save_png(path)
			print("SEQ %s %03d t=%.2f s frame=%d mean=%.3f grade_tables=%d" % [label, saved, clock, drawn, lum, builds])
			saved += 1
			next_save += every
	var lo := 1.0
	var hi := 0.0
	for l in lums:
		lo = minf(lo, l)
		hi = maxf(hi, l)
	var sorted := lums.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
	var dark := 0
	for l in lums:
		if l < median * 0.5:
			dark += 1
	Log.info("Capture", "sequence %s: %d frames drawn over %.1f s, %d saved, mean brightness %.3f..%.3f (median %.3f), grade tables built %d, %d flash(es), %d DARK frame(s), %d frame(s) with things flickering (worst %d of %d samples)"
		% [label, drawn, clock, saved, lo, hi, median, luts[-1] if not luts.is_empty() else 0, flashes.size(), dark,
			flicker_frames, flicker_worst, FLICKER_GRID.x * FLICKER_GRID.y])
	if dark > 0 or not flashes.is_empty():
		_failures.append("sequence %s: %d flash(es), %d frame(s) under half the median brightness" % [label, flashes.size(), dark])
	for f in flashes:
		Log.info("Capture", "FLASH %s %s" % [label, f])
	return index + 1


## How many times the grade's table has been built, asked for by name so a build from before the
## count existed still runs a sequence (it reads 0 there).
func _grade_builds() -> int:
	var atmos := _world.atmosphere if _world else null
	if atmos == null or not atmos.has_method("costs"):
		return 0
	var c: Dictionary = atmos.call("costs")
	return int((c.get("grade_lut", {}) as Dictionary).get("builds", 0))


## The frame's luminance on a FLICKER_GRID of samples.
static func _luma_grid(img: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(FLICKER_GRID.x * FLICKER_GRID.y)
	var w := img.get_width()
	var h := img.get_height()
	var i := 0
	for gy in FLICKER_GRID.y:
		var y := int((float(gy) + 0.5) * float(h) / float(FLICKER_GRID.y))
		for gx in FLICKER_GRID.x:
			out[i] = img.get_pixel(int((float(gx) + 0.5) * float(w) / float(FLICKER_GRID.x)), y).get_luminance()
			i += 1
	return out


static func _mean_luminance(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var total := 0.0
	var n := 0
	for y in range(h / 36, h, h / 18):
		for x in range(w / 64, w, w / 32):
			total += img.get_pixel(x, y).get_luminance()
			n += 1
	return total / float(maxi(n, 1))


# --- cinematics --------------------------------------------------------------------------------------

## Real seconds each cinematic frame is given after its country stands, so a subtitle or a title
## card that has just begun to ink in is photographed arrived rather than halfway.
const CINEMATIC_SETTLE_SECONDS := 2.0


## Every sample of every shot of a cinematic, through `CinematicPlayer.scrub`.
func _shoot_cinematic(spec: Dictionary) -> int:
	var id := str(spec.get("id", ""))
	if not ContentDB.has(id):
		Log.error("Capture", "no cinematic %s" % id)
		return 2
	# A plan that stages a new game (`flags: {new_game: true}`) must not have the real opening start
	# under the frames it poses: that one takes the screen, black, from its first shot. Not saved.
	Settings.set_value("gameplay", "play_opening", false, false)
	_world = await _load_world(true)
	if _world == null:
		Log.error("Capture", "world scene failed to load")
		return 1
	if not _world.is_world_ready:
		await _world.world_ready
	var spawn: Node = _world.get_node_or_null("PlayerSpawn")
	var player: Node3D = null
	for i in 600:
		player = spawn.get("player") as Node3D if spawn != null else null
		if player != null:
			break
		await get_tree().process_frame
	if player == null:
		Log.error("Capture", "no body stood up to hand the cinematic over to")
		return 1
	_world.streamer.cells_per_frame = 12
	# a style's film hands over to a body standing at its own start (`"opening": "core:opening/x"`)
	var opening_id := str(spec.get("opening", ""))
	if opening_id != "" and spawn != null and spawn.has_method("stand_at_opening"):
		if not bool(spawn.call("stand_at_opening", ContentDB.get_or_empty(opening_id))):
			_failures.append("cannot stand the body at %s" % opening_id)
	# the body drops the last half-metre onto the ground before the last shot is composed on it
	for i in 40:
		await get_tree().physics_frame
	if bool(spec.get("play", false)):
		return await _play_cinematic(id, player)
	var cin := CinematicPlayer.new()
	_world.add_child(cin)
	await cin.begin(_world, player, ContentDB.get_def(id), CinematicPlayer.Mode.SCRUB)
	var samples: Array = spec.get("samples", [0.0, 0.5, 1.0])
	# `"film_ab": true` shoots every frame twice, with the settings as they stand and with the
	# film's picture over them (Graphics.FILM): a before and after from one world
	var ab := bool(spec.get("film_ab", false))
	var only: Array = spec.get("shots", [])
	var shots := CinematicDef.shots_of(cin.def)
	var rows: Array = []
	var index := 0
	for i in shots.size():
		var shot: Dictionary = shots[i]
		var sid := str(shot.get("id", ""))
		if not only.is_empty() and not only.has(sid):
			continue
		var black := bool(shot.get("black", false))
		var takes: Array = []
		for u_v in ([0.5] if black else samples):
			for film: bool in ([false, true] if ab else [true]):
				takes.append([float(u_v), film])
		for take: Array in takes:
			var u := float(take[0])
			if ab:
				cin.set_film_picture(bool(take[1]))
			cin.scrub(i, u)
			var waited := 0
			while waited < MAX_WAIT_FRAMES and not cin.ready_to_show():
				await get_tree().process_frame
				waited += 1
			var ready := cin.ready_to_show()
			var until := Time.get_ticks_msec() + int(CINEMATIC_SETTLE_SECONDS * 1000.0)
			var frames := 0
			while frames < SETTLE_FRAMES or Time.get_ticks_msec() < until:
				await get_tree().process_frame
				frames += 1
			await RenderingServer.frame_post_draw
			# the trees go to the levels the film's detail asks for a few at a time (WorldStreamer.update_lods)
			var lod_frames := 0
			while lod_frames < 900 and not _world.streamer.lods_settled():
				await get_tree().process_frame
				lod_frames += 1
			await RenderingServer.frame_post_draw
			var file := "%02d_%s_%03d%s.png" % [index, sid, int(round(u * 100.0)),
					("_film" if bool(take[1]) else "_plain") if ab else ""]
			var img := get_viewport().get_texture().get_image()
			if img == null or img.save_png("%s/%s" % [out_dir, file]) != OK:
				_failures.append("cannot write %s" % file)
			var cam := cin.camera().global_position
			var ground := _world.provider.max_height_around(cam.x, cam.z, 3.0, 12)
			rows.append({
				"file": file, "shot": sid, "u": u, "camera": [snappedf(cam.x, 0.1), snappedf(cam.y, 0.1), snappedf(cam.z, 0.1)],
				"above_ground": snappedf(cam.y - ground, 0.01), "fov": snappedf(cin.camera().fov, 0.1),
				"hour": snappedf(WorldClock.time_hours, 0.01),
				"weather": str(_world.atmosphere.call("current_weather_id")) if _world.atmosphere else "",
				"words": cin.overlay().said(), "ready": ready, "frames_waited": waited,
				# the bare-ground measure: of the cells this moment sees, how many were standing
				"seen_standing": [cin.sight_standing().x, cin.sight_standing().y],
				"loaded": _world.streamer.loaded_count(),
				"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				# what the frame was drawn at, against the window (CinematicPlayer.render_report)
				"film_picture": bool(take[1]) if ab else CinematicPlayer.film_picture,
				"render": cin.render_report(),
				"image": [img.get_width(), img.get_height()] if img != null else [0, 0],
			})
			if not ready and not black:
				_failures.append("%s: its cells were not standing after %d frames" % [file, waited])
			Log.info("Capture", "%s  %.1f m above the ground, %s, %d of the %d cells it sees standing" % [file, cam.y - ground,
					"ready" if ready else "NOT READY", cin.sight_standing().x, cin.sight_standing().y])
			index += 1
	cin.release()
	var f := FileAccess.open("%s/cinematic.json" % out_dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"cinematic": id, "frames": rows}, "  "))
		f.close()
	for failure in _failures:
		Log.error("Capture", failure)
	Log.info("Capture", "%d cinematic frames written to %s" % [index, out_dir])
	return 1 if not _failures.is_empty() else 0


## A cinematic block with `"play": true` plays the film as the pause menu's replay does, in real
## time, and writes down what every drawn frame was drawn at (CinematicPlayer.render_report) into
## <out>/cinematic_play.json, with the first frame past each shot's middle on disk: the render size a
## player gets, measured frame by frame rather than at a scrubbed pose.
func _play_cinematic(id: String, player: Node3D) -> int:
	var cin := CinematicPlayer.new()
	cin.name = "Replay"
	_world.add_child(cin)
	cin.begin(_world, player, ContentDB.get_def(id), CinematicPlayer.Mode.REPLAY)
	var rows: Array = []
	var shot_at := -1
	var shot_saved := false
	var frame := 0
	var until := Time.get_ticks_msec() + 900000
	var off_window := 0
	while is_instance_valid(cin) and cin.phase_name() != "DONE" and Time.get_ticks_msec() < until:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(cin):
			break
		frame += 1
		var r := cin.render_report()
		var shots := CinematicDef.shots_of(cin.def)
		var i := cin.current_shot()
		var sid := str((shots[i] as Dictionary).get("id", "")) if i >= 0 and i < shots.size() else ""
		var row := {"frame": frame, "phase": cin.phase_name(), "shot": sid, "t": snappedf(cin.shot_time(), 0.01), "render": r}
		if cin.phase_name() == "PLAY" and r.get("render_3d", []) != r.get("window", []):
			off_window += 1
		if i != shot_at:
			shot_at = i
			shot_saved = false
		var dur := float((shots[i] as Dictionary).get("duration", 1.0)) if i >= 0 and i < shots.size() else 1.0
		if not shot_saved and cin.phase_name() == "PLAY" and cin.shot_time() >= dur * 0.5:
			shot_saved = true
			var img := get_viewport().get_texture().get_image()
			var file := "play_%02d_%s.png" % [i, sid]
			if img != null and img.save_png("%s/%s" % [out_dir, file]) == OK:
				row["file"] = file
				row["image"] = [img.get_width(), img.get_height()]
		rows.append(row)
	var f := FileAccess.open("%s/cinematic_play.json" % out_dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"cinematic": id, "frames": rows, "frames_off_window": off_window}, "  "))
		f.close()
	Log.info("Capture", "played %s: %d frames drawn, %d of them in a picture not drawn at the window's size"
			% [id, frame, off_window])
	return 0
