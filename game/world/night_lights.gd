class_name NightLights
extends Node3D
## Every lamp, lantern, brazier, fire and lit window in the country: a glow that reads from the
## next hill, and the few nearest to you as real light on the ground.
##
## Compatibility draws at most twelve omni lights on any one object (project.godot,
## `max_lights_per_object`) and drops the rest without a word, and one terrain chunk, the
## world-wide water sheet or a merged causeway is in reach of every lamp near it. So nothing in
## the open country owns a light of its own: every source is registered here, drawn as a glow --
## a point turned to face the camera, all of them in one MultiMesh for the whole world -- and a
## pool of real, unshadowed OmniLight3Ds (`graphics/night_lights`, eight by default and at most) is
## handed each tick to the sources nearest the camera that are worth a real light, fading in and
## out with distance so that a lamp never pops on as you walk up to it.
##
## Eight, because the pool shares the twelve with the lights that are still their own: a
## Hearthstone's flame (two can be in reach), the player's lantern, an Echo. The points of
## interest used to hang an OmniLight of their own at every fire and lamp -- six along the Long
## Stride alone, always on -- and those passed the twelve with the pool; they are sources here now.
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
## The glow MultiMesh is rebuilt from the whole registry, so a burst of registrations -- a
## settlement raising its windows, a cell's points of interest dressing themselves -- is gathered
## into one rebuild rather than one each.
const REBUILD_SECONDS := 0.5
const DEFAULT_POOL := 8
const MAX_POOL := 8

## kind -> colour, real light energy and range (m), glow size (m) and strength, whether it is
## ever given a real light, and whether it burns by day. A window is glow only: there are too
## many of them, and the door of the same lit house carries its light. A point of interest's
## lamp or fire burns at any hour, as it always did, with the energy and reach its builder gave.
const KINDS := {
	"window": {"colour": Color(1.0, 0.66, 0.36), "energy": 0.8, "range": 6.0, "size": 0.9, "glow": 0.75, "real": false, "day": false},
	"door": {"colour": Color(1.0, 0.70, 0.42), "energy": 1.5, "range": 8.0, "size": 1.1, "glow": 0.9, "real": true, "day": false},
	"lantern": {"colour": Color(1.0, 0.78, 0.50), "energy": 1.9, "range": 10.0, "size": 1.5, "glow": 1.1, "real": true, "day": false},
	"brazier": {"colour": Color(1.0, 0.56, 0.26), "energy": 2.4, "range": 11.0, "size": 2.1, "glow": 1.3, "real": true, "day": false},
	"fire": {"colour": Color(1.0, 0.62, 0.32), "energy": 2.0, "range": 10.0, "size": 2.2, "glow": 1.2, "real": false, "day": false},
	"poi": {"colour": Color(1.0, 0.72, 0.42), "energy": 2.2, "range": 11.0, "size": 2.0, "glow": 1.15, "real": true, "day": true},
}

## owner instance id -> Array of [world position, kind, colour, energy, range]
static var _sources: Dictionary = {}
## owner instance id -> its sources as glow instances, already in the MultiMesh's buffer layout
## (16 floats each: three rows of scaled basis and origin, then colour and strength), so a
## rebuild is a concatenation rather than a call into the renderer per lamp
static var _chunks: Dictionary = {}
static var _version := 0
## What the rebuilds and the pool cost: count, total and worst in microseconds, and how many
## sources the last rebuild drew. The capture runner writes these into perf.json.
static var stats := {"rebuilds": 0, "rebuild_us_total": 0, "rebuild_us_max": 0, "rebuild_sources": 0,
		"assigns": 0, "assign_us_total": 0, "assign_us_max": 0}

var pool_size := DEFAULT_POOL
var _pool: Array[OmniLight3D] = []
var _glow: MultiMeshInstance3D
var _glow_version := -1
var _rebuild_wait := 0.0
var _timer := 0.0
## What the pool is lighting this tick, for tests and the debug console.
var lit: Array = []


## Adds `points` (world positions) as sources of `kind` owned by `owner`. `colour`, `energy`
## and `reach` override the kind's own, for a fire or a lamp whose builder knows better.
static func add(owner: Node, points: Array, kind: String, colour := Color(0, 0, 0, 0),
		energy := -1.0, reach := -1.0) -> void:
	if owner == null or points.is_empty() or not KINDS.has(kind):
		return
	var id := owner.get_instance_id()
	if not _sources.has(id):
		_sources[id] = []
		owner.tree_exiting.connect(Callable(NightLights, "remove").bind(id), CONNECT_ONE_SHOT)
	var k: Dictionary = KINDS[kind]
	var c: Color = colour if colour.a > 0.0 else k["colour"]
	var e: float = energy if energy >= 0.0 else float(k["energy"])
	var r: float = reach if reach > 0.0 else float(k["range"])
	var size := float(k["size"])
	var chunk: PackedFloat32Array = _chunks.get(id, PackedFloat32Array())
	for p in points:
		(_sources[id] as Array).append([p, kind, c, e, r])
		var at: Vector3 = p
		chunk.append_array([size, 0.0, 0.0, at.x, 0.0, size, 0.0, at.y, 0.0, 0.0, size, at.z,
			c.r, c.g, c.b, float(k["glow"])])
	_chunks[id] = chunk
	_version += 1


static func remove(owner_id: int) -> void:
	_chunks.erase(owner_id)
	if _sources.erase(owner_id):
		_version += 1


## Every source, flattened: [world position, kind, colour, energy, range].
static func sources() -> Array:
	var out: Array = []
	for id in _sources:
		out.append_array(_sources[id])
	return out


## What one owner registered.
static func sources_of(owner: Node) -> Array:
	if owner == null:
		return []
	return (_sources.get(owner.get_instance_id(), []) as Array).duplicate()


static func count(kind := "") -> int:
	var n := 0
	for id in _sources:
		for s in _sources[id]:
			if kind == "" or str(s[1]) == kind:
				n += 1
	return n


static func reset_stats() -> void:
	for key in stats:
		stats[key] = 0


## What the glow rebuilds and the pool's assignments have cost so far (see `stats`).
func costs() -> Dictionary:
	return {"night_lights": stats.duplicate()}


func _ready() -> void:
	add_to_group(GROUP)
	_size_pool(int(Settings.get_value("graphics", "night_lights", DEFAULT_POOL)))
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
	if section == "graphics" and key == "night_lights":
		_size_pool(int(value))


func _process(delta: float) -> void:
	var night := Atmosphere.night_factor
	if _glow_version != _version:
		_rebuild_wait -= delta
		if _rebuild_wait <= 0.0 or _glow.multimesh == null:
			rebuild_glow()
	_glow.visible = night > 0.01 and _glow.multimesh != null and _glow.multimesh.instance_count > 0
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_SECONDS
	assign(night)


## Hands the pool to the sources nearest the camera that are worth a real light: by day the
## points of interest's fires and lamps, which always burned; after dark every lamp.
func assign(night: float) -> void:
	var t0 := Time.get_ticks_usec()
	lit.clear()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or _pool.is_empty():
		for l in _pool:
			l.visible = false
		return
	var eye := cam.global_position
	var near: Array = []
	var reach2 := REAL_REACH_M * REAL_REACH_M
	var dark := night >= 0.02
	for id in _sources:
		for s in _sources[id]:
			var k: Dictionary = KINDS[s[1]]
			if not bool(k["real"]) or not (dark or bool(k["day"])):
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
		var by_night := 1.0 if bool(KINDS[s[1]]["day"]) else night
		var d := sqrt(float(near[i][0]))
		var fade := 1.0 - smoothstep(REAL_REACH_M * 0.6, REAL_REACH_M, d)
		l.global_position = s[0]
		l.light_color = s[2]
		l.omni_range = float(s[4])
		l.light_energy = float(s[3]) * by_night * fade
		l.visible = l.light_energy > 0.01
		lit.append(s)
	var us := Time.get_ticks_usec() - t0
	stats["assigns"] += 1
	stats["assign_us_total"] += us
	stats["assign_us_max"] = maxi(int(stats["assign_us_max"]), us)


## The glow MultiMesh, from the whole registry. Public so a capture can have it current before an
## exposure rather than waiting out the gathering delay.
func rebuild_glow() -> void:
	var t0 := Time.get_ticks_usec()
	_glow_version = _version
	_rebuild_wait = REBUILD_SECONDS
	# the whole buffer at once, from each owner's chunk: a call per lamp into the renderer took
	# five milliseconds a rebuild on average and seventy-three at worst for seven hundred lamps
	var buf := PackedFloat32Array()
	for id in _chunks:
		buf.append_array(_chunks[id])
	var n := buf.size() / 16
	var mm := _glow.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		mm.mesh = quad
	mm.instance_count = n
	if n > 0:
		mm.buffer = buf
	_glow.multimesh = mm
	var us := Time.get_ticks_usec() - t0
	stats["rebuilds"] += 1
	stats["rebuild_us_total"] += us
	stats["rebuild_us_max"] = maxi(int(stats["rebuild_us_max"]), us)
	stats["rebuild_sources"] = n
