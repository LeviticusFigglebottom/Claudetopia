class_name World
extends Node3D
## The overworld scene root.
##
## Owns the terrain (Terrain3D bound to the built region data), the TerrainProvider every other
## system asks about the ground, the water surfaces, the cell streamer, the atmosphere and --
## when no player exists yet -- a fly camera that stands in for one.
##
## Access from anywhere with `World.instance`; prefer `World.terrain()` for ground queries.

## Emitted once the terrain, water, atmosphere and streamer are all in place.
signal world_ready

static var instance: World = null

const GENERATED := "res://world/generated"
const TERRAIN_DATA := "res://terrain_data"
const ASSETS_RESOURCE := "res://world/terrain_assets.tres"
## The High ground textures (Graphics "Ground texture quality"): the same slots, the most-seen six
## painted at 2048 (tools/world/gen_terrain_textures.py --high) and the rest scaled up to them as the
## world loads (`match_texture_sizes`), since a Terrain3D texture array takes one size.
const ASSETS_RESOURCE_HIGH := "res://world/terrain_assets_high.tres"
## `-- --ground-textures=standard|high` overrides the setting for one run (captures, the benchmark).
const GROUND_TEXTURES_ARG := "--ground-textures="
## Terrain3D projects its textures sideways where the ground's normal is under this: 0.86, 31 degrees.
const PROJECTION_THRESHOLD := 0.86
const ATMOSPHERE_SCENE := "res://systems/atmosphere/atmosphere.tscn"
## What the first frames drawing a new place show, one more a frame (`warm_layers`): the ground and
## the sky first, then these. A shader is compiled the first time something drawn with it is seen,
## and everything at once was one frame of 5.3 s behind the title's chart on the software renderer.
const WARM_LAYERS := ["Water", "Horizon", "WorldStreamer"]
## However long the body takes to stand, the 3D held under the loading fade is given back after this.
const HOLD_3D_CAP_S := 180.0

@export var spawn_place: String = "core:place/merrowby"
@export var stream_enabled: bool = true
## A world stood up behind the title's menu (ui/menus/title_vista.gd): it is looked at, not entered.
## It never tells the game which region it is in (the music, the HUD and a later game's first
## region all listen for that), and its streamer does not either.
@export var vista: bool = false

var provider: TerrainProvider
var streamer: WorldStreamer
var water: WaterSurface
var wildlife: Wildlife = null
var terrain_node: Node3D = null
## The ground drawn from the runtime height map when Terrain3D cannot draw it.
var fallback: FallbackTerrain = null
## What draws the ground: "terrain3d", "fallback", or "" when nothing does.
var terrain_mode := ""
## `WorldStatus.current()` as this world found it: whether there is a world, and what draws it.
var status: Dictionary = {}
## The corner plate and the arrival card that say the ground is the coarse one (fallback only).
var ground_notice: GroundNotice = null
var atmosphere: Node = null
var night_lights: NightLights = null
var horizon: HorizonLayer = null
var fly_camera: FlyCamera = null
var target: Node3D = null

var is_world_ready := false
## Whether `tear_down` has been: the world is going, and does nothing more.
var torn_down := false
## What each step of standing the world up took on the wall clock, in milliseconds, in order
## (`_mark`): what a frame gap while it stands up is made of.
var stand_up_ms: Dictionary = {}
## Whether the world stands up a step a frame, so whatever is drawn meanwhile (the title's chart
## and menu, the loading caption) goes on being drawn between the steps. On wherever something is
## drawn; a headless run (the unit suite builds dozens of worlds) stands it up in one go.
var stand_up_in_steps := WorldPace.paced()

var _pois: Array = []
var _mark_us := 0
## The terrain's files, read on worker threads from the first moment (`_start_reading_terrain`):
## Terrain3D reads its sixteen regions itself, on the main thread, when it is given its data
## directory (3.7 s here, 2.5 s of it alone), and the texture list is another 1.7 s.
var _regions: RegionReads = null
var _regions_task := -1
## The worker threads the region reads were given (`region_read_tasks`), held off ThreadedLoads'
## limit until they are done.
var _regions_reserved := 0
var _assets_requested := false
## The texture list this world reads, chosen once as its terrain begins to be read: a change of the
## setting meanwhile waits for the next world, as the settings screen says.
var _assets_path := ""
var _holding_3d := false


static func terrain() -> TerrainProvider:
	return instance.provider if instance else null


## The three ground questions, answered statically so anything can ask them without holding a
## reference to the world. `WorldProbe` looks for exactly these on the World script: without
## them every query fell through to the region's nominal base height, which is how NPCs came to
## stand at the average altitude of their county rather than on the hill they live on.
static func get_height(x: float, z: float) -> float:
	var t := terrain()
	return t.get_height(x, z) if t != null else 0.0


## Takes a point rather than a pair, because that is the shape `WorldProbe` asks in.
static func region_id_at(pos: Vector3) -> String:
	var t := terrain()
	return t.nearest_region_id_at(pos.x, pos.z) if t != null else ""


static func is_water(x: float, z: float) -> bool:
	var t := terrain()
	return t.is_water(x, z) if t != null else false


## Tells the shaders how `terrain3d` draws its clipmap (its vertices a side and the metres between
## its nearest), or that there is none (null): a town's paving follows its far rings up
## (painted_surface.gdshader, `terrain_follow`). Asked again whenever its mesh_size changes.
static func share_clipmap(terrain3d: Object) -> void:
	var at := Vector2.ZERO
	if terrain3d != null and is_instance_valid(terrain3d):
		at = Vector2(float(terrain3d.get("mesh_size")), float(terrain3d.get("vertex_spacing")))
	RenderingServer.global_shader_parameter_set("wm_terrain_clipmap", at)


func _ready() -> void:
	instance = self
	_mark_us = Time.get_ticks_usec()
	status = WorldStatus.current()
	_trace("standing up (%s, %s, terrain %s)" % ["the title's" if vista else "a game's", "a step a frame" if stand_up_in_steps else "at once",
			str(status.get("terrain", "none"))])
	if not bool(status.get("playable", false)):
		# There is no country to stand in. Everything that waits for world_ready -- the body, the
		# doors, the points of interest -- goes on waiting, and the screen says why instead of
		# showing a grey void with the HUD up.
		_stand_down()
		return
	_start_reading_terrain()
	# the prototype (world/grass_instancer.gd): decided before the first cell streams in
	GrassInstancer.active = not vista and str(status.get("terrain", "")) == "terrain3d" and GrassInstancer.mode() > 0
	if stand_up_in_steps:
		# the places' builders (seven thousand lines) are compiled on a loader thread while the
		# ground is read, not in the frame the first place is raised (half a second there)
		ThreadedLoads.request(PoiDressing.BUILDERS_PATH)
	provider = TerrainProvider.new()
	provider.name = "TerrainProvider"
	add_child(provider)        # TerrainProvider loads its maps in _ready
	_load_pois()
	if stand_up_in_steps:
		# the landmarks' models, for the skyline (HorizonLayer) and the cells, on loader threads
		var models: Array = []
		for e in _pois:
			if e is Dictionary:
				models.append(str((e as Dictionary).get("scene", "")))
		WorldStreamer.prefetch_paths(models)
		# and the props the places and the towns are dressed in, all of them: a place's first use of a
		# cart or a barrel read it from disk in the frame it was raised (TRIAGE item 36)
		for dir in ["props", "rocks", "flora", "trees"]:
			WorldStreamer.prefetch_paths(asset_files("res://assets/models/" + dir))
	_setup_target()           # before the terrain: Terrain3D looks for a camera on its first frame
	# Standing up in steps, a world left before it is up (the title's, when New Game or Continue is
	# pressed early) stops at the next step: it never says it is ready from outside the tree.
	_hold_3d(true)
	if not await _mark("provider"):
		return
	_trace("terrain step begins")
	await _setup_terrain()
	if not await _mark("terrain"):
		return
	if terrain_mode.is_empty():
		# nothing could draw the ground: not even the runtime height map was readable
		status = status.duplicate()
		status["playable"] = false
		status["title"] = "The ground could not be drawn."
		status["detail"] = ("Neither Terrain3D nor the runtime height map in game/world/generated/runtime/ gave this world a ground. "
				+ "Build the world again from the repository's top folder with the command below. It needs %s.") % WorldStatus.BUILD_NEEDS
		_stand_down()
		return
	_trace("atmosphere step begins")
	_setup_atmosphere()
	if not await _mark("atmosphere"):
		return
	_trace("water step begins")
	_setup_night_lights()
	await _setup_water()
	if not await _mark("water"):
		return
	_setup_wildlife()
	# the POIs written since the land was built, and any asked for, on pads laid now (PoiPreview):
	# before the streamer, so the cells' scatter is cleared off them as it is read
	if not vista:
		_pois = PoiPreview.apply(_pois, provider)
	_trace("streamer step begins")
	_setup_streamer()
	if not await _mark("streamer"):
		return
	_trace("horizon step begins")
	await _setup_horizon()
	if not await _mark("horizon"):
		return
	# the doors, and the towns round where the world is first seen from, a piece at a time, before
	# anything hears the world is ready (WorldDoors raises them all at once on hearing it otherwise);
	# the other towns after, nearest the eye first
	var doors := get_node_or_null("Doors")
	if stand_up_in_steps and doors != null and doors.has_method("place_all_over_frames") and bool(doors.get("place_doors")):
		_trace("doors step begins")
		await doors.call("place_all_over_frames", _first_seen_from())
		if not await _mark("doors"):
			return
	if not vista:
		EventBus.region_entered.connect(_on_region_entered)
		var start := _spawn_position()
		GameState.enter_region(provider.nearest_region_id_at(start.x, start.z))
	is_world_ready = true
	Log.info("World", "ready: terrain=%s, %d pois, target=%s; stood up in %s ms"
		% [terrain_mode if not terrain_mode.is_empty() else "none", _pois.size(), target.name if target else "none", str(stand_up_ms)])
	if terrain_mode == "fallback":
		ground_notice = GroundNotice.make(status)
		add_child(ground_notice)
		EventBus.player_spawned.connect(_say_the_ground_is_coarse, CONNECT_ONE_SHOT)
	_trace("ready (%s)" % str(stand_up_ms))
	_mark_us = Time.get_ticks_usec()
	world_ready.emit()
	# what the world's listeners did on hearing it (the doors, the places, the stable, whoever stood it up)
	_note("ready_listeners")
	_draw_when_seen()


## The 3D held while the world stood up under the fade comes back when the fade is about to lift:
## the body stands, and the menus' fade waits for the country round it (UI.wait_for_country); the
## cells come much quicker while no frame of them is drawn (a frame of this world is seconds on a
## software renderer, and held 3D the country round the body came in 40 s rather than 5). Given
## back at once when nothing covers the screen, and after HOLD_3D_CAP_S whatever happens.
func _draw_when_seen() -> void:
	var until := Time.get_ticks_msec() + int(HOLD_3D_CAP_S * 1000.0)
	# until the menus' fade begins to wait for the country round the body (the body stands a few
	# frames after this, and a load reads its slot first), then for as long as it waits
	while _holding_3d and is_inside_tree() and UI.is_faded_out() and not UI.is_holding_for_country() \
			and Time.get_ticks_msec() < until:
		await _frame()
	while _holding_3d and is_inside_tree() and UI.is_holding_for_country() and Time.get_ticks_msec() < until:
		await _frame()
	_hold_3d(false)


## Stops what the world would go on doing on later frames, before it is freed: the streamer asks
## for no more cells, the provider lets go of Terrain3D, and the paced
## stand-up stops at its next step. The title calls it when its world goes (TitleVista.stop, and
## its `_exit_tree` on a click), and `_exit_tree` does it for anyone else. Safe to call twice.
func tear_down() -> void:
	if torn_down:
		return
	torn_down = true
	_trace("torn down (%s)" % ("standing up: %s" % str(stand_up_ms.keys()) if not is_world_ready else "was ready"))
	if streamer != null and is_instance_valid(streamer):
		streamer.enabled = false
		streamer.also_cells = {}
	# Terrain3D keeps its camera: set_camera(null) crashes Terrain3D 1.0.2 (a segfault in the
	# library, here on the title's teardown). The camera is the world's own and goes with it.
	if terrain_node != null and is_instance_valid(terrain_node) and provider != null:
		provider.bind_terrain(null)
	if instance == self:
		share_clipmap(null)
		GrassInstancer.active = false


func _exit_tree() -> void:
	tear_down()
	if instance == self:
		instance = null
		share_clipmap(null)
	# a world freed while it stands up (the title left early) must not leave its readers running
	_exit_tree_terrain_reads()
	_hold_3d(false)


## Writes down how long the part of a step just done took, and goes on at once.
func _note(part: String) -> void:
	var now := Time.get_ticks_usec()
	stand_up_ms[part] = roundi((now - _mark_us) / 1000.0)
	_mark_us = now
	_trace("%s done in %d ms" % [part, int(stand_up_ms[part])])


## Writes down how long the step just done took, and, standing up in steps, lets a frame be drawn
## before the next. False when the world has left the tree meanwhile: stop standing it up.
func _mark(step: String) -> bool:
	if torn_down:
		return false
	var now := Time.get_ticks_usec()
	stand_up_ms[step] = roundi((now - _mark_us) / 1000.0)
	_trace("%s step done in %d ms" % [step, int(stand_up_ms[step])])
	if stand_up_in_steps:
		await _frame()
	_mark_us = Time.get_ticks_usec()
	return is_inside_tree() and not torn_down


## A line in the startup trace (StartupTrace), which costs nothing once the game has started.
func _trace(what: String) -> void:
	if StartupTrace.active:
		StartupTrace.step("world%s: %s" % [" (title)" if vista else "", what])


## The next frame, asked of the main loop: a world taken out of the tree has no tree to ask.
func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


## Under the loading fade nothing of the world is seen until it is up, and a frame that draws it
## costs as much as the world does (seconds, on a software renderer): standing up in steps under the
## fade, the viewport draws no 3D until the world is ready. The title's world is the title's to
## show (TitleVista does the same for its own reasons).
func _hold_3d(on: bool) -> void:
	if vista or not stand_up_in_steps or not is_inside_tree():
		return
	var vp := get_viewport()
	# the caption says the fade is coming even on the frame its tween has not yet begun (boot's --load)
	if on and (UI.is_faded_out() or UI.is_loading_shown()) and not vp.disable_3d:
		vp.disable_3d = true
		_holding_3d = true
	elif not on and _holding_3d:
		vp.disable_3d = false
		_holding_3d = false


# --- construction -----------------------------------------------------------------------------

## Terrain3D when it is here and has regions to draw; otherwise the coarse ground, the same country
## from the 8 m runtime map (FallbackTerrain). Never nothing: a machine without the plugin, or a
## copy without the regions, used to stand the player on a grey void.
func _setup_terrain() -> void:
	if str(status.get("terrain", "")) == "terrain3d":
		await _setup_terrain3d()
		if not is_inside_tree():
			return
		if terrain_node != null:
			terrain_mode = "terrain3d"
			return
		# regions that are on disk and load as nothing (another Terrain3D version, a truncated copy)
		status = status.duplicate()
		status["state"] = "fallback"
		status["terrain"] = "fallback"
		status["reason"] = "terrain_unreadable"
		status["title"] = "The full terrain could not be read."
		status["detail"] = ("Terrain3D read no regions from the files in game/terrain_data (another Terrain3D version, "
				+ "or a copy cut short), so the ground is drawn from the coarse 8 m height map, which is why it looks plain and grey. "
				+ "Build the terrain again with the command below. It needs %s.") % WorldStatus.BUILD_NEEDS
		status["command"] = WorldStatus.BUILD_COMMAND
		status["announce"] = true
		status["badge"] = WorldStatus.badge_line("terrain_unreadable", WorldStatus.BUILD_COMMAND)
		status["notice"] = ("The full terrain is not drawn here: you are walking on the coarse ground. "
				+ "(Terrain3D read no regions from game/terrain_data: %s builds them again.)") % WorldStatus.BUILD_COMMAND
	Log.warn("World", "%s Drawing the ground from the runtime height map." % str(status.get("title", "")))
	_setup_fallback()
	# Terrain3D's path waits a frame for its data object, so `world_ready` has always come after
	# `add_child` returned, and every caller that adds a world and then awaits the signal depends
	# on that. Without the wait the coarse ground made the world ready inside `add_child`, and a
	# caller waiting afterwards waited for ever.
	await _frame()


func _setup_fallback() -> void:
	fallback = FallbackTerrain.new()
	fallback.name = "FallbackTerrain"
	add_child(fallback)
	if fallback.build(provider):
		terrain_mode = "fallback"
		return
	Log.error("World", "no runtime height map to draw the ground from; the world has no ground")
	fallback.queue_free()
	fallback = null


## The `step`th frame of drawing a place for the first time: the ground and the sky, with the layers
## after WARM_LAYERS[step - 1] hidden. True once every layer is shown (and from then on). Whoever
## warms a place hides nothing for good: a large step shows every layer.
func warm_layers(step: int) -> bool:
	for k in WARM_LAYERS.size():
		var layer := get_node_or_null(str(WARM_LAYERS[k])) as Node3D
		if layer != null:
			layer.visible = k < step
	return step >= WARM_LAYERS.size()


## The coarse ground is the country, but not all of it, and the player is owed the account of why:
## the card across the top once the fade is up (under the loading sheet nobody reads it), and the
## plate in the corner for as long as they walk on it (GroundNotice). A toast used to say it, once,
## and a player played for days on the coarse ground without seeing it.
func _say_the_ground_is_coarse(_player: Node) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while is_inside_tree() and UI.is_faded_out() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if is_inside_tree() and ground_notice != null:
		ground_notice.announce()


## No world on disk: say so on the screen, plainly, with the way back to the title.
func _stand_down() -> void:
	_hold_3d(false)
	Log.warn("World", "%s %s" % [str(status.get("title", "")), str(status.get("detail", ""))])
	var layer := CanvasLayer.new()
	layer.name = "Unbuilt"
	layer.layer = UI.LAYER_FADE + 5
	add_child(layer)
	var screen := WorldNotice.screen(status)
	layer.add_child(screen)
	UI.hide_hud()
	UI.fade_from_black(0.3)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _setup_terrain3d() -> void:
	terrain_node = ClassDB.instantiate("Terrain3D")
	terrain_node.name = "Terrain3D"
	# Terrain3D frees the source textures in NOTIFICATION_READY, which lands before its data
	# object exists in a runtime-built node -- the texture arrays would then be built from an
	# empty list and the ground would render as the debug checkerboard. We keep the sources,
	# build the arrays ourselves below, and free them once they are safely in VRAM.
	terrain_node.set("free_editor_textures", false)
	# a debug build asked to (`-- --debug-stall-terrain=N`) holds the main thread here, for the watchdog
	Startup.debug_stall("the terrain step")
	_trace("terrain: waiting for the terrain's assets")
	var assets: Resource = await _terrain_assets()
	# a world left while its terrain was read (the title's, when New Game or Continue is pressed)
	# stops here: a Terrain3D given regions outside the tree says "Terrain isn't inside world", and
	# its texture arrays are never built (TRIAGE item 37)
	if not is_inside_tree():
		terrain_node.free()
		terrain_node = null
		return
	if assets != null:
		terrain_node.set("assets", assets)
	_note("terrain_assets")
	_trace("terrain: assets received (%s); adding Terrain3D" % ("%d textures" % int(assets.call("get_texture_count")) if assets != null else "none"))
	add_child(terrain_node)
	# the build's own texel (2 m at 4096): a preview world imported at its 8 m and drawn at 2 m
	# would be a quarter of the world in its north-west corner
	terrain_node.set("vertex_spacing", float(provider.manifest.get("spacing_m", 2.0)) if provider != null else 2.0)
	terrain_node.set("cast_shadows", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	# The clipmap has to cover the whole world, not a circle around the camera. At 7 LODs and
	# 2 m spacing it reached about 6 km, so from any hill the terrain stopped in a dead straight
	# line with a visible corner -- a flat shelf across the distance with the land cut off
	# behind it. Wickmere's diagonal is 11.6 km; 8 LODs reach 12.3 km, so the ground now runs
	# to the edge of the world from anywhere in it. One more ring costs one more strip of the
	# same vertex count at twice the spacing. Tools can ask for fewer (`--terrain-lods=N`).
	var lods := WorldStatus.terrain_lods_for(status)
	if lods != WorldStatus.TERRAIN_LODS:
		Log.info("World", "Terrain3D draws %d clipmap rings (%s); %d reach the edge of the world"
				% [lods, str(status.get("lods_why", "asked for")), WorldStatus.TERRAIN_LODS])
	terrain_node.set("mesh_lods", lods)
	terrain_node.set("mesh_size", 32)
	share_clipmap(terrain_node)
	var mat: Object = terrain_node.get("material")
	_trace("terrain: Terrain3D added, %d rings of %d; material and shader parameters" % [lods, int(terrain_node.get("mesh_size"))])
	if mat:
		# NONE: see tools_gd/import_terrain.gd. FLAT draws a shelf across the far distance.
		mat.set("world_background", 0)
		mat.set("auto_shader", false)
		mat.call("set_shader_param", "blend_sharpness", 0.34)
		mat.call("set_shader_param", "enable_macro_variation", true)
		# the tiling's breakup at a distance: two large noise fields darken and warm the ground by up
		# to an eighth (a twentieth left the tile repeat readable across a hillside)
		mat.call("set_shader_param", "macro_variation1", Color(0.88, 0.90, 0.84))
		mat.call("set_shader_param", "macro_variation2", Color(0.88, 0.84, 0.79))
		mat.call("set_shader_param", "macro_variation_slope", 0.4)
		# textures projected sideways from 31 degrees (the shader's own 0.8 is 37): below it the
		# turf on a steep bank was the top-down projection stretched down the bank (playtest 6)
		mat.call("set_shader_param", "enable_projection", true)
		mat.call("set_shader_param", "projection_threshold", PROJECTION_THRESHOLD)
		mat.call("set_shader_param", "mipmap_bias", 0.95)
		mat.call("set_shader_param", "bias_distance", 420.0)
	var collision: Object = terrain_node.get("collision")
	if collision:
		# dynamic collision around the camera/player; the title's world is only looked at, and
		# building the shapes round its camera was work every shot paid for nothing
		collision.set("mode", 0 if vista else 1)
		collision.set("radius", 96)
	_trace("terrain: material set; collision, provider, camera")
	provider.bind_terrain(terrain_node)
	if fly_camera:
		terrain_node.call("set_camera", fly_camera)
	elif target is Camera3D:
		terrain_node.call("set_camera", target)
	_trace("terrain: waiting for Terrain3D's first frame")
	await _frame()
	_note("terrain_first_frame")
	await _add_terrain_regions()
	_note("terrain_regions")
	if not is_inside_tree() or terrain_node == null:
		return
	# Region files that are there but cannot be read (a different Terrain3D version, a truncated
	# copy) load as nothing, and nothing is a void: give the ground to the fallback instead.
	var data: Object = terrain_node.get("data")
	var regions := int(data.call("get_region_count")) if data != null else 0
	if regions == 0:
		Log.warn("World", "Terrain3D loaded no regions from %s" % TERRAIN_DATA)
		provider.bind_terrain(null)
		terrain_node.queue_free()
		terrain_node = null
		share_clipmap(null)
		return
	_trace("terrain: %d regions in; building the texture arrays" % regions)
	_build_texture_arrays(mat)
	_note("terrain_textures")
	if GrassInstancer.active:
		await _setup_grass_instancer()


## The prototype's ground cover (world/grass_instancer.gd): the region's rows read on a worker
## thread, then handed to Terrain3D's instancer.
func _setup_grass_instancer() -> void:
	var t0 := Time.get_ticks_msec()
	var read := {"rows": {}}
	var task := WorkerThreadPool.add_task(func() -> void: read["rows"] = GrassInstancer.read_rows(), true,
			"wm_grass_instancer")
	while is_inside_tree() and not WorkerThreadPool.is_task_completed(task):
		await _frame()
	WorkerThreadPool.wait_for_task_completion(task)
	if not is_inside_tree() or terrain_node == null:
		return
	var read_ms := Time.get_ticks_msec() - t0
	var g: Dictionary = Settings.data.get("graphics", {})
	GrassInstancer.populate(terrain_node, read["rows"], float(g.get("view_range", 1.0)),
			float(g.get("scatter_density", 1.0)), GrassInstancer.mode() == 2)
	GrassInstancer.last["read_ms"] = read_ms
	GrassInstancer.last["total_ms"] = Time.get_ticks_msec() - t0
	Log.info("World", "grass instancer: %s" % str(GrassInstancer.last))
	_note("grass_instancer")


## Begins reading the terrain's texture list and its region files on worker threads, so that by the
## time the terrain node wants them they are read, and the frames meanwhile go on being drawn.
func _start_reading_terrain() -> void:
	if str(status.get("terrain", "")) != "terrain3d":
		return
	var files: Array[String] = []
	for f in DirAccess.get_files_at(TERRAIN_DATA):
		# an exported build lists the remapped name
		var file := f.trim_suffix(".remap")
		if file.begins_with("terrain3d") and file.ends_with(".res"):
			files.append(file)
	# The region files are read by a few worker threads, not all of them (-1 was every thread in the
	# pool): the shader compiles that the first frames need run as tasks on the same pool, and the
	# first-launch deadlock (docs/FIRST_LAUNCH.md) was a pool with no thread left for them. The
	# threads they are given are held off ThreadedLoads' limit meanwhile, so the two together always
	# leave two threads free, and the assets' read is asked for after them.
	if not files.is_empty():
		var tasks := region_read_tasks(ThreadedLoads.pool_size(), files.size())
		_regions_reserved = tasks
		ThreadedLoads.reserved += tasks
		_trace("terrain: reading %d region files on %d of the pool's %d threads" % [files.size(), tasks, ThreadedLoads.pool_size()])
		# read by an object of its own, not this world's method: a world torn down while they are read
		# (the title's, on a click) leaves them to finish and is freed at once (`_exit_tree_terrain_reads`)
		_regions = RegionReads.new(files)
		_regions_task = WorkerThreadPool.add_group_task(_regions.read, files.size(), tasks, true, "wm_terrain_regions")
	_assets_path = assets_resource()
	if ResourceLoader.exists(_assets_path):
		_assets_requested = ThreadedLoads.request(_assets_path) == OK


## The texture list the ground is drawn with: High's or Standard's, by the setting (or the run's
## `--ground-textures=`), Standard when the High list is not there.
static func assets_resource() -> String:
	var g: Dictionary = {"ground_textures": Settings.get_value("graphics", "ground_textures", -1)}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(GROUND_TEXTURES_ARG):
			g["ground_textures"] = 1 if arg.trim_prefix(GROUND_TEXTURES_ARG) == "high" else 0
	if Graphics.ground_texture_quality(g) == 1 and ResourceLoader.exists(ASSETS_RESOURCE_HIGH):
		return ASSETS_RESOURCE_HIGH
	return ASSETS_RESOURCE


## Brings every slot of `assets` to the size of its largest, so Terrain3D can build one array from
## them: the High list's 1024 slots are scaled up (cubic) beside its 2048 ones. Nothing to do for the
## Standard list. Returns the slots it scaled.
static func match_texture_sizes(assets: Resource) -> int:
	if assets == null:
		return 0
	var count := int(assets.call("get_texture_count"))
	var want := 0
	for i in count:
		var t: Resource = assets.call("get_texture", i)
		var tex: Texture2D = t.get("albedo_texture") if t != null else null
		if tex != null:
			want = maxi(want, tex.get_width())
	var scaled := 0
	for i in count:
		var t: Resource = assets.call("get_texture", i)
		if t == null:
			continue
		var grew := false
		for prop in ["albedo_texture", "normal_texture"]:
			var tex: Texture2D = t.get(prop)
			if tex == null or tex.get_width() >= want:
				continue
			var img := tex.get_image()
			if img == null:
				continue
			if img.is_compressed():
				img.decompress()
			img.clear_mipmaps()
			img.resize(want, want, Image.INTERPOLATE_CUBIC)
			img.generate_mipmaps()
			t.set(prop, ImageTexture.create_from_image(img))
			grew = true
		if grew:
			scaled += 1
	return scaled


## The worker threads the region files are read on: half of what the pool has past the two a
## compile is always left, at least one, and no more than there are files.
static func region_read_tasks(pool: int, files: int) -> int:
	return clampi(floori((pool - 2) / 2.0), 1, maxi(files, 1))


## The terrain's region files, read on worker threads into a list of their own.
class RegionReads extends RefCounted:
	var files: Array[String] = []
	var read_out: Array = []           # [Vector2i location, Terrain3DRegion]
	var mutex := Mutex.new()

	func _init(names: Array[String]) -> void:
		files = names

	func read(i: int) -> void:
		var file := files[i]
		var loc := World.region_location(file)
		var region: Resource = null
		if StartupTrace.active:
			StartupTrace.step("terrain: region %s read begins" % file)
		if loc != Vector2i(2147483647, 2147483647):
			region = ResourceLoader.load("%s/%s" % [World.TERRAIN_DATA, file], "", ResourceLoader.CACHE_MODE_IGNORE)
		if StartupTrace.active:
			StartupTrace.step("terrain: region %s read %s" % [file, "ends" if region != null else "ends, NOTHING READ"])
		mutex.lock()
		read_out.append([loc, region])
		mutex.unlock()


## Where a region file stands, from its name as Terrain3D writes it: `terrain3d-01_02.res` is
## (-1, 2); the sign before each pair of digits is `-` or `_`. INT_MAX for a name that is not one.
static func region_location(file: String) -> Vector2i:
	var n := file.get_file().get_basename().trim_prefix("terrain3d")
	if n.length() != 6 or n[0] not in ["-", "_"] or n[3] not in ["-", "_"]:
		return Vector2i(2147483647, 2147483647)
	var x := int(n.substr(1, 2)) * (-1 if n[0] == "-" else 1)
	var y := int(n.substr(4, 2)) * (-1 if n[3] == "-" else 1)
	return Vector2i(x, y)


## The texture list, read on a worker thread: waited for a frame at a time when standing up in
## steps, and outright otherwise.
func _terrain_assets() -> Resource:
	if _assets_path == "":
		_assets_path = assets_resource()
	var assets: Resource = null
	if not _assets_requested:
		assets = load(_assets_path) if ResourceLoader.exists(_assets_path) else null
	else:
		while stand_up_in_steps and is_inside_tree() \
				and ThreadedLoads.status(_assets_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await _frame()
		# left meanwhile: `_exit_tree` took the read, and nothing is wanted (a load here would be seconds)
		if not is_inside_tree() or not _assets_requested:
			return null
		_assets_requested = false
		assets = ThreadedLoads.take(_assets_path)
	if _assets_path == ASSETS_RESOURCE_HIGH and assets != null:
		var t0 := Time.get_ticks_msec()
		var scaled := match_texture_sizes(assets)
		if scaled > 0:
			Log.info("World", "High ground textures: %d slots scaled up to the 2048 set in %d ms"
					% [scaled, Time.get_ticks_msec() - t0])
	return assets


## Gives Terrain3D the regions read on the worker threads, and builds its maps once. If none were
## read (another Terrain3D, files named otherwise), Terrain3D is given its data directory to read
## them itself, as it always was.
func _add_terrain_regions() -> void:
	if _regions_task >= 0:
		_trace("terrain: waiting for the region reads")
		while stand_up_in_steps and is_inside_tree() and not WorkerThreadPool.is_group_task_completed(_regions_task):
			await _frame()
		if _regions_task >= 0 and is_inside_tree():
			WorkerThreadPool.wait_for_group_task_completion(_regions_task)
			_regions_task = -1
			_release_region_threads()
	# left while the regions were read: `_exit_tree` has waited for the readers, and there is no
	# world to put them in (Terrain3D: "Terrain isn't inside world")
	if not is_inside_tree() or terrain_node == null or not terrain_node.is_inside_tree():
		return
	var data: Object = terrain_node.get("data") if terrain_node != null else null
	var read: Array = []
	if _regions != null:
		for pair in _regions.read_out:
			if pair is Array and (pair as Array)[1] != null:
				read.append(pair)
		_regions = null
	if data == null or read.is_empty() or not data.has_method("add_region"):
		_trace("terrain: no regions read here; Terrain3D reads %s itself" % TERRAIN_DATA)
		terrain_node.set("data_directory", TERRAIN_DATA)
		await _frame()
		return
	var size := int((read[0][1] as Resource).get("region_size"))
	if size > 0 and int(terrain_node.get("region_size")) != size:
		terrain_node.set("region_size", size)
	for pair in read:
		var region: Resource = pair[1]
		region.set("location", pair[0])
		_trace("terrain: add_region %s" % str(pair[0]))
		data.call("add_region", region, false)
	_trace("terrain: update_maps begins (%d regions)" % read.size())
	data.call("update_maps")
	_trace("terrain: update_maps ends")


## A world leaving while its terrain is read never waits for the reads: the region readers are left
## to finish on their own (ThreadedLoads.after_task keeps them and gives the threads back after), and
## the assets' read is forgotten, to be collected when done. A main thread waiting on them was the
## title's freeze on a click.
func _exit_tree_terrain_reads() -> void:
	if _regions_task >= 0:
		_trace("terrain: left while the regions were read; they finish on their own")
		var reserved := _regions_reserved
		_regions_reserved = 0
		ThreadedLoads.after_task(_regions_task, true, _regions, func() -> void:
			ThreadedLoads.reserved = maxi(ThreadedLoads.reserved - reserved, 0))
		_regions_task = -1
		_regions = null
	_release_region_threads()
	if _assets_requested:
		ThreadedLoads.forget(_assets_path)
	_assets_requested = false


## Gives ThreadedLoads back the threads the region reads held.
func _release_region_threads() -> void:
	if _regions_reserved > 0:
		ThreadedLoads.reserved = maxi(ThreadedLoads.reserved - _regions_reserved, 0)
		_regions_reserved = 0


## Builds the terrain texture arrays and then releases the source images.
func _build_texture_arrays(mat: Object) -> void:
	var assets: Object = terrain_node.get("assets")
	if assets == null:
		return
	var path := _assets_path if _assets_path != "" else ASSETS_RESOURCE
	if int(assets.call("get_texture_count")) == 0 and ResourceLoader.exists(path):
		# Terrain3D cleared the list before the arrays were made: put it back and rebuild
		assets = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		match_texture_sizes(assets)
		terrain_node.set("assets", assets)
	# built already when the node took its assets: building them again was 0.4 s of one frame
	if not (assets.call("get_albedo_array_rid") as RID).is_valid():
		_trace("terrain: update_texture_list begins")
		assets.call("update_texture_list")
	var slots := int(assets.call("get_texture_count"))
	var albedo_rid: RID = assets.call("get_albedo_array_rid")
	if not albedo_rid.is_valid():
		Log.error("World", "terrain texture array was not built (%d slots); the ground will be checkered" % slots)
		return
	if mat:
		mat.set("show_checkered", false)
	assets.call("clear_textures", false)      # arrays are in VRAM; drop the source images
	Log.info("World", "terrain textures ready: %d slots" % slots)
	_trace("terrain: texture arrays built (%d slots)" % slots)


func _setup_atmosphere() -> void:
	if not ResourceLoader.exists(ATMOSPHERE_SCENE):
		Log.warn("World", "atmosphere scene missing: %s" % ATMOSPHERE_SCENE)
		return
	var packed: PackedScene = load(ATMOSPHERE_SCENE)
	atmosphere = packed.instantiate()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)


## The lamps, lanterns, braziers, fires and lit windows after dark: one glow MultiMesh for the
## whole country and a small pool of real lights near the eye (world/night_lights.gd).
func _setup_night_lights() -> void:
	night_lights = NightLights.new()
	night_lights.name = "NightLights"
	add_child(night_lights)


func _setup_water() -> void:
	water = WaterSurface.new()
	water.name = "Water"
	add_child(water)
	# a part at a time within the frame's budget, where something is drawn meanwhile
	await water.build(provider, WorldPace.Slice.new() if stand_up_in_steps else null)


## The wild things between the places (world/wildlife/wildlife.gd).
func _setup_wildlife() -> void:
	wildlife = Wildlife.new()
	wildlife.name = "Wildlife"
	wildlife.provider = provider
	add_child(wildlife)


func _setup_target() -> void:
	# The player leads the streaming when there is one; a test or tool can put a bare probe in
	# the "streamer_target" group instead; otherwise the world flies itself.
	# A body in this world, not any body anywhere. The group is global, so a player another
	# scene stood up — a test's, a tool's, a review harness's — was adopted as this world's
	# eye, and then the streaming followed it wherever it was standing. That is how a suite
	# run came to stream twenty-five cells around somebody else's player while the cell it had
	# been asked for never arrived at all.
	for group in ["player", "streamer_target"]:
		for found in get_tree().get_nodes_in_group(group):
			if found is Node3D and is_ancestor_of(found):
				target = found
				return
	fly_camera = FlyCamera.new()
	fly_camera.name = "FlyCamera"
	fly_camera.provider = provider
	# far enough to see the whole world from a peak; by 12 km even the clearest region's fog is
	# at 95%, so the far plane falls where nothing is left to cut
	fly_camera.far = 12000.0
	fly_camera.near = 0.25
	fly_camera.fov = float(Settings.get_value("video", "fov", 75.0))
	add_child(fly_camera)
	var start := _spawn_position()
	fly_camera.move_to(start + Vector3(0.0, 12.0, 60.0), start + Vector3(0.0, 6.0, 0.0))
	target = fly_camera


## What stands on the skyline past the streamed ring (world/horizon_layer.gd).
func _setup_horizon() -> void:
	horizon = HorizonLayer.new()
	horizon.name = "Horizon"
	add_child(horizon)
	# Nothing is drawn headless, and the build (a hundred stand-ins, the Briar wall's fifteen
	# hundred trees) is most of a second a world: the unit suite builds dozens of worlds.
	if not WorldPace.paced():
		return
	if stand_up_in_steps:
		await horizon.build_from_in_steps(self)
	else:
		horizon.build_from(self)


func _setup_streamer() -> void:
	streamer = WorldStreamer.new()
	streamer.name = "WorldStreamer"
	streamer.enabled = stream_enabled
	streamer.report_regions = not vista
	# the title's world is looked at, not entered: nobody fights its foes or meets the people at its
	# places, and standing them up was most of what its cells cost behind the menu
	streamer.stand_up_foes = not vista
	streamer.solid_scatter = streamer.solid_scatter and not vista
	var dressings := get_node_or_null("Pois")
	if vista and dressings != null and "encounters" in dressings:
		dressings.set("encounters", false)
	add_child(streamer)
	if fallback != null:
		fallback.streamer = streamer      # its scatter is set down on the coarse ground as it arrives
	streamer.setup(provider, target)


# --- places and spawning ------------------------------------------------------------------------

func _load_pois() -> void:
	var path := "%s/pois.json" % GENERATED
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) == TYPE_ARRAY:
		_pois = parsed


## World position of a named place, taking y from the built terrain.
func place_position(place_id: String) -> Vector3:
	for p in _pois:
		if str(p.get("place_id", "")) == place_id:
			var pos: Array = p.get("pos", [0, 0, 0])
			return Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var def := ContentDB.get_or_empty(place_id)
	if def.has("position"):
		var xz: Array = def["position"]
		var x := float(xz[0])
		var z := float(xz[1])
		return Vector3(x, provider.get_height(x, z), z)
	return Vector3.ZERO


func pois() -> Array:
	return _pois


## Every model under `dir` (one folder deep, as the forge files them), by its source path.
static func asset_files(dir: String) -> Array:
	var out: Array = []
	for sub in DirAccess.get_directories_at(dir):
		for f in DirAccess.get_files_at("%s/%s" % [dir, sub]):
			var file := f.trim_suffix(".remap").trim_suffix(".import")
			if file.ends_with(".glb") or file.ends_with(".tscn"):
				var path := "%s/%s/%s" % [dir, sub, file]
				if not out.has(path):
					out.append(path)
	return out


## Where the world will first be looked at from: whatever it follows now (the title's camera at its
## first shot, the fly camera), and where a new game's body will stand (PlayerSpawn). A load's
## saved spot is not known until the body stands; the loading fade waits for the towns round it then.
func _first_seen_from() -> Array:
	var out: Array = []
	var spawn := get_node_or_null("PlayerSpawn")
	# a world a body will stand in is not looked at through its fly camera (at the default place)
	if target != null and is_instance_valid(target) and (vista or spawn == null or not bool(spawn.get("enabled"))):
		out.append(target.global_position)
	if not vista and spawn != null and bool(spawn.get("enabled")) and spawn.has_method("_opening_position") \
			and str(GameState.get_flag("_pending_load_slot", "")).is_empty():
		var at: Vector3 = spawn.call("_opening_position")
		if at != Vector3.ZERO:
			out.append(at)
	return out


func _spawn_position() -> Vector3:
	var pos := place_position(spawn_place)
	if pos == Vector3.ZERO and not _pois.is_empty():
		var first: Array = _pois[0].get("pos", [0, 0, 0])
		pos = Vector3(float(first[0]), float(first[1]), float(first[2]))
	return pos


## Hands the world to a body: the streaming follows it, and so do Terrain3D's clipmap and its
## dynamic collision, which are built around whatever camera Terrain3D was last given. The spawn
## handed the streamer the player and never told Terrain3D, which went on following the fly
## camera the world starts with -- and that camera kept flying on the player's own keys (W A S D,
## Space, Q, E; Shift made it fast), so the ground's collision moved away from the body at every
## step, and a player walked under the terrain among trees that seemed to float. The fly camera
## now stops flying and stops being anyone's eye; the tools that shoot without a player keep it.
func follow(body: Node3D) -> void:
	target = body
	if streamer != null:
		streamer.target = body
		streamer.refresh()
	_point_terrain_at(body)
	if fly_camera != null and body != fly_camera:
		fly_camera.set_process(false)
		fly_camera.set_process_unhandled_input(false)
		fly_camera.current = false


## Gives Terrain3D the body's own camera (the camera itself when the body is one). Set before the
## fly camera is let go, so the plugin is never left holding a camera that is not there.
func _point_terrain_at(body: Node3D) -> void:
	if terrain_node == null or not terrain_node.has_method("set_camera"):
		return
	var cam := body as Camera3D
	if cam == null:
		for c in body.find_children("*", "Camera3D", true, false):
			cam = c as Camera3D
			break
	if cam != null:
		terrain_node.call("set_camera", cam)


## Moves whatever the streamer follows (the fly camera, or the player) to a world position.
func move_target(pos: Vector3, look_at: Variant = null) -> void:
	# Move whatever the streaming is actually following. Once a body has spawned, the fly
	# camera is still in the scene but is nobody's eye: moving it moved nothing at all and the
	# world went on streaming around the player standing where they were.
	if target == fly_camera and fly_camera != null:
		fly_camera.move_to(pos, look_at)
	elif target != null and target.has_method("teleport"):
		target.call("teleport", pos, target.rotation.y, "moved")
	elif target != null:
		target.global_position = pos
		target.reset_physics_interpolation()
	elif fly_camera != null:
		fly_camera.move_to(pos, look_at)
	if streamer:
		streamer.refresh()


## Streams as though whatever the streamer follows were standing here. Headless tools and the
## smoke run call this to sweep the map without a player.
func force_stream_around(pos: Vector3) -> void:
	move_target(pos)


func _on_region_entered(region_id: String, _previous: String) -> void:
	if water:
		water.set_region_look(region_id)
	if atmosphere and atmosphere.has_method("set_region"):
		atmosphere.call("set_region", region_id)
