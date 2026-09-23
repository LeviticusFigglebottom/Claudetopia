class_name NightLights
extends Node3D
## The country after dark: every lamp, lantern, brazier, fire and lit window in it, as a glow
## that reads from the next hill, and the few nearest to you as real light on the ground.
##
## Compatibility caps the omni lights one object may take (ARCHITECTURE 10) and a village has a
## hundred lit windows, so they cannot all be lights. Every source is a glow instead -- a point
## turned to face the camera, all of them in one MultiMesh for the whole world, drawn only at
## night -- and a small pool of real, unshadowed OmniLight3Ds (`video/night_lights`, eight by
## default) is handed each tick to the real-light sources nearest the camera, fading in and out
## with distance so that a lamp never pops on as you walk up to it.
##
## Sources are registered by whatever raises them -- `Settlement`, `Building`, `PoiKit.light` --
## with `NightLights.add(owner, points, kind)` in world space, and leave when their owner leaves
## the tree. The registry is static, so a settlement raised before this node exists is not lost.

const GROUP := "night_lights"
const GLOW_SHADER := preload("res://assets/shaders/night_glow.gdshader")
## Past this a source is never given a real light: at sixty metres a lamp's pool of light on the
## ground is a few pixels, and its glow is doing the work.
const REAL_REACH_M := 60.0
const UPDATE_SECONDS := 0.15
const DEFAULT_POOL := 8

## kind -> colour, real light energy, real light range (m), glow size (m), glow strength, and
## whether the kind is ever given a real light. A window is glow only: there are too many of
## them, and the door of the same lit house carries its light.
const KINDS := {
	"window": {"colour": Color(1.0, 0.66, 0.36), "energy": 0.8, "range": 6.0, "size": 0.9, "glow": 0.75, "real": false},
	"door": {"colour": Color(1.0, 0.70, 0.42), "energy": 1.5, "range": 8.0, "size": 1.1, "glow": 0.9, "real": true},
	"lantern": {"colour": Color(1.0, 0.78, 0.50), "energy": 1.9, "range": 10.0, "size": 1.5, "glow": 1.1, "real": true},
	"brazier": {"colour": Color(1.0, 0.56, 0.26), "energy": 2.4, "range": 11.0, "size": 2.1, "glow": 1.3, "real": true},
	"fire": {"colour": Color(1.0, 0.62, 0.32), "energy": 2.0, "range": 10.0, "size": 2.2, "glow": 1.2, "real": false},
}

## owner instance id -> Array of [world position, kind, colour]
static var _sources: Dictionary = {}
static var _version := 0

var pool_size := DEFAULT_POOL
var _pool: Array[OmniLight3D] = []
var _glow: MultiMeshInstance3D
var _glow_version := -1
var _timer := 0.0
## What the pool is lighting this tick, for tests and the debug console.
var lit: Array = []


## Adds `points` (world positions) as sources of `kind` owned by `owner`. `colour` overrides the
## kind's own, for a fire or a wisp that knows what colour it is.
static func add(owner: Node, points: Array, kind: String, colour := Color(0, 0, 0, 0)) -> void:
	if owner == null or points.is_empty() or not KINDS.has(kind):
		return
	var id := owner.get_instance_id()
	if not _sources.has(id):
		_sources[id] = []
		owner.tree_exiting.connect(Callable(NightLights, "remove").bind(id), CONNECT_ONE_SHOT)
	var c: Color = colour if colour.a > 0.0 else KINDS[kind]["colour"]
	for p in points:
		(_sources[id] as Array).append([p, kind, c])
	_version += 1


static func remove(owner_id: int) -> void:
	if _sources.erase(owner_id):
		_version += 1


## Every source, flattened: [world position, kind, colour].
static func sources() -> Array:
	var out: Array = []
	for id in _sources:
		out.append_array(_sources[id])
	return out


static func count(kind := "") -> int:
	var n := 0
	for id in _sources:
		for s in _sources[id]:
			if kind == "" or str(s[1]) == kind:
				n += 1
	return n


func _ready() -> void:
	add_to_group(GROUP)
	_size_pool(int(Settings.get_value("video", "night_lights", DEFAULT_POOL)))
	Settings.changed.connect(_on_setting_changed)
	_glow = MultiMeshInstance3D.new()
	_glow.name = "Glows"
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the quads are grown in the vertex shader, past the instances' own box
	_glow.extra_cull_margin = 400.0
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	_glow.material_override = mat
	_glow.visible = false
	add_child(_glow)


## Ten at most. Compatibility draws twelve lights on any one object (project.godot,
## `max_lights_per_object`) and drops the rest without a word, and a street's walls or the
## ground under a camp can be in reach of every lamp in the pool and of the camp's own fire.
const MAX_POOL := 10


func _size_pool(n: int) -> void:
	for l in _pool:
		l.queue_free()
	_pool.clear()
	pool_size = clampi(n, 0, MAX_POOL)
	for i in pool_size:
		var l := OmniLight3D.new()
		l.name = "Lamp%d" % i
		l.shadow_enabled = false
		l.omni_attenuation = 1.2
		l.visible = false
		add_child(l)
		_pool.append(l)
	_timer = 0.0


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section == "video" and key == "night_lights":
		_size_pool(int(value))


func _process(delta: float) -> void:
	var night := Atmosphere.night_factor
	if _glow_version != _version:
		_rebuild_glow()
	_glow.visible = night > 0.01 and _glow.multimesh != null and _glow.multimesh.instance_count > 0
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_SECONDS
	assign(night)


## Hands the pool to the real-light sources nearest the camera, or puts it all out by day.
func assign(night: float) -> void:
	lit.clear()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if night < 0.02 or cam == null or _pool.is_empty():
		for l in _pool:
			l.visible = false
		return
	var eye := cam.global_position
	var near: Array = []
	var reach2 := REAL_REACH_M * REAL_REACH_M
	for id in _sources:
		for s in _sources[id]:
			if not bool(KINDS[s[1]]["real"]):
				continue
			var d2 := eye.distance_squared_to(s[0])
			if d2 < reach2:
				near.append([d2, s])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in _pool.size():
		var l := _pool[i]
		if i >= near.size():
			l.visible = false
			continue
		var s: Array = near[i][1]
		var k: Dictionary = KINDS[s[1]]
		var d := sqrt(float(near[i][0]))
		var fade := 1.0 - smoothstep(REAL_REACH_M * 0.6, REAL_REACH_M, d)
		l.global_position = s[0]
		l.light_color = s[2]
		l.omni_range = float(k["range"])
		l.light_energy = float(k["energy"]) * night * fade
		l.visible = l.light_energy > 0.01
		lit.append(s)


func _rebuild_glow() -> void:
	_glow_version = _version
	var all := sources()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = all.size()
	for i in all.size():
		var s: Array = all[i]
		var k: Dictionary = KINDS[s[1]]
		var size := float(k["size"])
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(size, size, size)), s[0]))
		var c: Color = s[2]
		mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, float(k["glow"])))
	_glow.multimesh = mm
