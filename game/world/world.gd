class_name World
extends Node3D
## The overworld scene root.
##
## Owns the terrain (Terrain3D bound to the built region data), the TerrainProvider every other
## system asks about the ground, the water surfaces, the cell streamer, the atmosphere and --
## when no player exists yet -- a fly camera that stands in for one.
##
## Access from anywhere with `World.instance`; prefer `World.terrain()` for ground queries.

static var instance: World = null

const GENERATED := "res://world/generated"
const TERRAIN_DATA := "res://terrain_data"
const ATMOSPHERE_SCENE := "res://systems/atmosphere/atmosphere.tscn"

@export var spawn_place: String = "core:place/merrowby"
@export var stream_enabled: bool = true

var provider: TerrainProvider
var streamer: WorldStreamer
var water: WaterSurface
var terrain_node: Node3D = null
var atmosphere: Node = null
var fly_camera: FlyCamera = null
var target: Node3D = null

var _pois: Array = []
var _ready_done := false


static func terrain() -> TerrainProvider:
	return instance.provider if instance else null


func _ready() -> void:
	instance = self
	provider = TerrainProvider.new()
	provider.name = "TerrainProvider"
	add_child(provider)        # TerrainProvider loads its maps in _ready
	_load_pois()
	_setup_terrain()
	_setup_atmosphere()
	_setup_water()
	_setup_target()
	_setup_streamer()
	EventBus.region_entered.connect(_on_region_entered)
	var start := _spawn_position()
	GameState.enter_region(provider.nearest_region_id_at(start.x, start.z))
	_ready_done = true
	Log.info("World", "ready: terrain=%s, %d pois, target=%s"
		% [str(provider.has_terrain()), _pois.size(), target.name if target else "none"])


func _exit_tree() -> void:
	if instance == self:
		instance = null


# --- construction -----------------------------------------------------------------------------

func _setup_terrain() -> void:
	if not ClassDB.class_exists("Terrain3D"):
		Log.warn("World", "Terrain3D extension unavailable; terrain queries fall back to the runtime map")
		return
	if not DirAccess.dir_exists_absolute(TERRAIN_DATA) or DirAccess.get_files_at(TERRAIN_DATA).is_empty():
		Log.warn("World", "%s is empty; run ./run.sh world to build the terrain" % TERRAIN_DATA)
		return
	terrain_node = ClassDB.instantiate("Terrain3D")
	terrain_node.name = "Terrain3D"
	if ResourceLoader.exists("res://world/terrain_assets.tres"):
		terrain_node.set("assets", load("res://world/terrain_assets.tres"))
	add_child(terrain_node)
	terrain_node.set("data_directory", TERRAIN_DATA)
	terrain_node.set("vertex_spacing", 2.0)
	terrain_node.set("cast_shadows", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	terrain_node.set("mesh_lods", 7)
	terrain_node.set("mesh_size", 48)
	var mat: Object = terrain_node.get("material")
	if mat:
		mat.set("world_background", 1)          # FLAT: the world keeps going past the regions
		mat.set("auto_shader", false)
		mat.call("set_shader_param", "blend_sharpness", 0.82)
		mat.call("set_shader_param", "enable_macro_variation", true)
		mat.call("set_shader_param", "macro_variation1", Color(0.95, 0.97, 0.91))
		mat.call("set_shader_param", "macro_variation2", Color(0.92, 0.90, 0.87))
		mat.call("set_shader_param", "macro_variation_slope", 0.4)
		mat.call("set_shader_param", "mipmap_bias", 0.95)
		mat.call("set_shader_param", "bias_distance", 420.0)
	var collision: Object = terrain_node.get("collision")
	if collision:
		collision.set("mode", 1)                 # dynamic collision around the camera/player
		collision.set("radius", 96)
	provider.bind_terrain(terrain_node)


func _setup_atmosphere() -> void:
	if not ResourceLoader.exists(ATMOSPHERE_SCENE):
		Log.warn("World", "atmosphere scene missing: %s" % ATMOSPHERE_SCENE)
		return
	var packed: PackedScene = load(ATMOSPHERE_SCENE)
	atmosphere = packed.instantiate()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)


func _setup_water() -> void:
	water = WaterSurface.new()
	water.name = "Water"
	add_child(water)
	water.build(provider)


func _setup_target() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node3D:
		target = players[0]
		return
	fly_camera = FlyCamera.new()
	fly_camera.name = "FlyCamera"
	fly_camera.provider = provider
	fly_camera.far = 6000.0
	fly_camera.near = 0.2
	fly_camera.fov = float(Settings.get_value("video", "fov", 75.0))
	add_child(fly_camera)
	var start := _spawn_position()
	fly_camera.move_to(start + Vector3(0.0, 12.0, 60.0), start + Vector3(0.0, 6.0, 0.0))
	target = fly_camera
	if terrain_node:
		terrain_node.call("set_camera", fly_camera)


func _setup_streamer() -> void:
	streamer = WorldStreamer.new()
	streamer.name = "WorldStreamer"
	streamer.enabled = stream_enabled
	add_child(streamer)
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


## Moves whatever the streamer follows (the fly camera, or the player) to a world position.
func move_target(pos: Vector3, look_at: Variant = null) -> void:
	if fly_camera:
		fly_camera.move_to(pos, look_at)
	elif target:
		target.global_position = pos
	if streamer:
		streamer.refresh()


func _on_region_entered(region_id: String, _previous: String) -> void:
	if water:
		water.set_region_look(region_id)
	if atmosphere and atmosphere.has_method("set_region"):
		atmosphere.call("set_region", region_id)
