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
## Terrain3D projects its textures sideways where the ground's normal is under this: 0.86, 31 degrees.
const PROJECTION_THRESHOLD := 0.86
const ATMOSPHERE_SCENE := "res://systems/atmosphere/atmosphere.tscn"

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

var _pois: Array = []


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
	status = WorldStatus.current()
	if not bool(status.get("playable", false)):
		# There is no country to stand in. Everything that waits for world_ready -- the body, the
		# doors, the points of interest -- goes on waiting, and the screen says why instead of
		# showing a grey void with the HUD up.
		_stand_down()
		return
	provider = TerrainProvider.new()
	provider.name = "TerrainProvider"
	add_child(provider)        # TerrainProvider loads its maps in _ready
	_load_pois()
	_setup_target()            # before the terrain: Terrain3D looks for a camera on its first frame
	await _setup_terrain()
	if terrain_mode.is_empty():
		# nothing could draw the ground: not even the runtime height map was readable
		status = status.duplicate()
		status["playable"] = false
		status["title"] = "The ground could not be drawn."
		status["detail"] = ("Neither Terrain3D nor the runtime height map in game/world/generated/runtime/ gave this world a ground. "
				+ "Build the world again from the repository's top folder with the command below. It needs %s.") % WorldStatus.BUILD_NEEDS
		_stand_down()
		return
	_setup_atmosphere()
	_setup_night_lights()
	_setup_water()
	_setup_wildlife()
	_setup_streamer()
	_setup_horizon()
	if not vista:
		EventBus.region_entered.connect(_on_region_entered)
		var start := _spawn_position()
		GameState.enter_region(provider.nearest_region_id_at(start.x, start.z))
	is_world_ready = true
	Log.info("World", "ready: terrain=%s, %d pois, target=%s"
		% [terrain_mode if not terrain_mode.is_empty() else "none", _pois.size(), target.name if target else "none"])
	if terrain_mode == "fallback":
		ground_notice = GroundNotice.make(status)
		add_child(ground_notice)
		EventBus.player_spawned.connect(_say_the_ground_is_coarse, CONNECT_ONE_SHOT)
	world_ready.emit()


func _exit_tree() -> void:
	if instance == self:
		instance = null
		share_clipmap(null)


# --- construction -----------------------------------------------------------------------------

## Terrain3D when it is here and has regions to draw; otherwise the coarse ground, the same country
## from the 8 m runtime map (FallbackTerrain). Never nothing: a machine without the plugin, or a
## copy without the regions, used to stand the player on a grey void.
func _setup_terrain() -> void:
	if str(status.get("terrain", "")) == "terrain3d":
		await _setup_terrain3d()
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
	await get_tree().process_frame


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
	if ResourceLoader.exists(ASSETS_RESOURCE):
		terrain_node.set("assets", load(ASSETS_RESOURCE))
	add_child(terrain_node)
	terrain_node.set("data_directory", TERRAIN_DATA)
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
		collision.set("mode", 1)                 # dynamic collision around the camera/player
		collision.set("radius", 96)
	provider.bind_terrain(terrain_node)
	if fly_camera:
		terrain_node.call("set_camera", fly_camera)
	elif target is Camera3D:
		terrain_node.call("set_camera", target)
	await get_tree().process_frame
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
	_build_texture_arrays(mat)


## Builds the terrain texture arrays and then releases the source images.
func _build_texture_arrays(mat: Object) -> void:
	var assets: Object = terrain_node.get("assets")
	if assets == null:
		return
	if int(assets.call("get_texture_count")) == 0 and ResourceLoader.exists(ASSETS_RESOURCE):
		# Terrain3D cleared the list before the arrays were made: put it back and rebuild
		assets = ResourceLoader.load(ASSETS_RESOURCE, "", ResourceLoader.CACHE_MODE_IGNORE)
		terrain_node.set("assets", assets)
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
	water.build(provider)


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
	if DisplayServer.get_name() != "headless":
		horizon.build_from(self)


func _setup_streamer() -> void:
	streamer = WorldStreamer.new()
	streamer.name = "WorldStreamer"
	streamer.enabled = stream_enabled
	streamer.report_regions = not vista
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
