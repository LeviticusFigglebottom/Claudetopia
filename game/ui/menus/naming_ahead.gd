class_name NamingAhead
extends Node
## What the Naming needs, read and warmed while the title is up, so New Game does not stall on it:
## the Naming's scene, the body it shows (the humanoid model), its stage's shaders and floor, and
## the world's ground textures that the Naming would otherwise ask for when it opens.
##
## Started by the title a few seconds after its menu is up (`START_S`), never while the live
## country is still standing up behind it (that has its own reads and compiles to do first). The
## reads go through ThreadedLoads like every other. Once the body is read, it is stood up once on a
## tiny stage of its own, off the screen, lit and shadowed as the Naming's portrait is and with the
## same edge smoothing, and drawn for WARM_FRAMES frames: the pipelines its first frame would have
## compiled are compiled behind the title instead. Then the stage goes; what was read is held here
## (`held`) until the Naming has opened, so the Naming's own `load` calls find it in the cache.
##
## Never on a software rasterizer (TitleVista.software_renderer: lavapipe, WARP): there each of the
## body's pipelines is an LLVM compile, and the stage held the title still for 17-23 s here.

const START_S := 1.5
const WARM_FRAMES := 4
const WARM_SIZE := Vector2i(96, 160)
const NAMING_SCENE := "res://ui/character/naming.tscn"
const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const STAGE := ["res://assets/shaders/portrait_backdrop.gdshader", "res://assets/shaders/portrait_floor.gdshader",
		"res://assets/textures/terrain/cobbles_albedo_height.png"]

## What has been read, by path, held until the Naming has opened.
static var held: Dictionary = {}
## The reads asked for and not yet taken.
var _pending: Array[String] = []
var _t := 0.0
var _started := false
var _warm: SubViewport = null
var _warm_frames := 0
## Whether to ask for the world's ground textures too (not when the live country reads them itself).
var ground := true
## Whether to warm the body's pipelines on a stage of its own (not headless).
var warm := true
## A gate the title sets: false while its live country is standing up.
var may_start: Callable = Callable()
## A gate for the warm stage: false while a live shot is watched, so its compile hitch falls in a
## dip to dark between shots (measured: 0.47 s on this machine's OpenGL, in a shot that pans).
var may_warm: Callable = Callable()
var _warm_scene: PackedScene = null


## The Naming's scene, read ahead, or null.
static func naming_scene() -> PackedScene:
	return held.get(NAMING_SCENE, null) as PackedScene


## Lets go of everything held: the Naming has opened (and took it), or the game went another way.
static func release() -> void:
	held.clear()


func _ready() -> void:
	name = "NamingAhead"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t += delta
	if not _started:
		if _t < START_S or (may_start.is_valid() and not bool(may_start.call())):
			return
		_start()
	for path in _pending.duplicate():
		if ThreadedLoads.status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_pending.erase(path)
		var res := ThreadedLoads.take(path)
		if res != null:
			held[path] = res
		StartupTrace.step("title: read ahead for the Naming: %s" % path.get_file())
		if path == MODEL_SCENE and warm and res is PackedScene:
			_warm_scene = res as PackedScene
	if _warm_scene != null and _warm == null and _pending.is_empty() \
			and (not may_warm.is_valid() or bool(may_warm.call())):
		_stand_warm_stage(_warm_scene)
		_warm_scene = null
	if _warm != null:
		_warm_frames += 1
		if _warm_frames > WARM_FRAMES:
			StartupTrace.step("title: the Naming's body was drawn once off the screen; its stage goes")
			_warm.queue_free()
			_warm = null
	if _pending.is_empty() and _warm == null and _warm_scene == null and _started:
		set_process(false)


func _start() -> void:
	_started = true
	for path: String in [NAMING_SCENE, MODEL_SCENE] + STAGE:
		if ResourceLoader.exists(path) and not held.has(path):
			_pending.append(path)
			ThreadedLoads.request(path)
	# not taken here: the Naming asks for it again and the world takes it (World._terrain_assets)
	if ground and ResourceLoader.exists(World.ASSETS_RESOURCE):
		ThreadedLoads.request(World.ASSETS_RESOURCE)


## The body on a tiny lit stage of its own, drawn a few frames off the screen: the Naming's portrait
## in miniature (its sky, its floor, its shadowed key light and its edge smoothing), so the
## pipelines its first frame needs are compiled now.
func _stand_warm_stage(model_scene: PackedScene) -> void:
	_warm = SubViewport.new()
	_warm.name = "NamingWarmStage"
	_warm.own_world_3d = true
	_warm.size = WARM_SIZE
	_warm.msaa_3d = Viewport.MSAA_2X if str(Settings.get_value("graphics", "preset", "high")) in ["low", "medium"] \
			else Viewport.MSAA_4X
	_warm.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_warm)
	Graphics.apply_viewport(_warm, Settings.data.get("graphics", {}))
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = held.get(STAGE[0], null) as Shader
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	_warm.add_child(env)
	var key := DirectionalLight3D.new()
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 9.0
	_warm.add_child(key)
	key.look_at_from_position(Vector3(-3.0, 3.0, 2.0), Vector3(0.0, 0.9, 0.0), Vector3.UP)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	floor_mesh.mesh = plane
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = held.get(STAGE[1], null) as Shader
	if held.has(STAGE[2]):
		floor_mat.set_shader_parameter("stones", held[STAGE[2]])
	floor_mesh.material_override = floor_mat
	_warm.add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.fov = 28.0
	cam.current = true
	_warm.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 1.0, 4.5), Vector3(0.0, 0.9, 0.0), Vector3.UP)
	var body := model_scene.instantiate()
	_warm.add_child(body)
	# the Naming's first look: a short-haired body in its first Calling's clothes
	var look := CharacterAppearance.new()
	look.set_part("head", "default")
	look.set_part("hair", "short")
	var callings := ContentDB.all("calling")
	var calling := str(callings[0].get("id", "")) if not callings.is_empty() else ""
	look.dress_for_culture(CharacterAppearance.culture_of_calling(calling), abs(calling.hash()), true)
	if body.has_method("apply_appearance"):
		body.call("apply_appearance", look.to_dict())


func _exit_tree() -> void:
	# a read still going is left to finish (never waited for); what was read stays held for the Naming
	for path in _pending:
		ThreadedLoads.forget(path)
	_pending.clear()
