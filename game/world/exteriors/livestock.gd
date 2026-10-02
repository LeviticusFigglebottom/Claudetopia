class_name Livestock
extends Node3D
## A settlement's beasts, where its people keep them: hens in the yards, geese on the green,
## sheep in the paddock behind the houses, a pig in its sty. And the few wild things a place's
## sentence names: the crabs on the Tideflat's old strand.
##
## A village with nobody's hens scratching in it is a model of a village. Each kind is one
## MultiMesh; each beast keeps to its own patch of ground and wanders it the way its kind does --
## a hen in quick short runs with long stops, a ewe a slow step at a time with its head in the
## grass -- and only while somebody is near enough to see it: past `AWAKE_M` nothing is moved
## and the beasts stand where they were.

## How each kind goes about: how fast it walks (m/s), how far from home it wanders, and how long
## it stands between one walk and the next. A crab goes `sideways`.
const HABITS := {
	"hen": {"speed": 0.7, "pause": [0.8, 3.5], "step": [0.4, 1.4]},
	"goose": {"speed": 0.45, "pause": [2.0, 7.0], "step": [0.8, 2.5]},
	"sheep": {"speed": 0.3, "pause": [4.0, 14.0], "step": [0.5, 2.0]},
	"pig": {"speed": 0.25, "pause": [3.0, 12.0], "step": [0.3, 0.9]},
	"crab": {"speed": 0.4, "pause": [0.4, 4.0], "step": [0.2, 1.0], "sideways": true},
}
## Beasts the forge has rigged on WM_Quadruped_v1 (tools/forge/horse_forge.py): a kind here is
## drawn from its GLB -- far off as a MultiMesh of its standing body, and within LIVE_M of the
## camera (the nearest MAX_LIVE of them) as a live model that walks, turns and grazes with its
## clips. A kind without a rigged GLB keeps the forge's static props.
const RIGGED := {"sheep": "res://assets/models/creatures/sheep_ewe/sheep_ewe.glb"}
## A rigged kind far off: the forge's bind-pose LOD2 (`<name>_lod2_bind.glb`, its legs, neck and
## tail marked in vertex colour), drawn as one MultiMesh posed by the herd_far shader -- grazing,
## looking up, walking, flicking its tail -- from FAR_FROM_M out to FAR_TO_M, where the standing
## body stops at RANGE_M. A flock on the next hill was a field with nothing in it past 180 m.
## The colours are the beast's own painted in: the bind mesh carries no material.
const FAR := {
	"sheep": {"mesh": "res://assets/models/creatures/sheep_ewe/sheep_ewe_lod2_bind.glb",
			"body": Color("#e3d9c3"), "head": Color("#2f2925"), "legs": Color("#2f2925"), "tail": Color("#d8cdb5"), "hz": 0.9},
	"horse": {"mesh": "res://assets/models/creatures/horse_cob/horse_cob_lod2_bind.glb",
			"body": Color("#6b4128"), "head": Color("#5e3822"), "legs": Color("#2a1c14"), "tail": Color("#1d1410"), "hz": 0.8},
}
const FAR_FROM_M := 150.0
const FAR_TO_M := 900.0
const LIVE_M := 42.0
const MAX_LIVE := 10
const AWAKE_M := 110.0
const TICK_S := 0.1
const RANGE_M := 180.0

## {kind, path, home (Vector3, this node's space), radius, at, yaw, target, wait, instance}
var beasts: Array = []
var _mm: Dictionary = {}           # path -> MultiMesh
var _shadow_mm: Dictionary = {}    # path -> MultiMesh of the forge's lowest rung, what the sun draws
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _live: Dictionary = {}          # beast index -> HorseModel (a rigged beast near the camera)
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
var _far_mm: Dictionary = {}       # path -> MultiMesh of the kind's far body, same instances as _mm
var _far_lift: Dictionary = {}     # path -> how far its feet stand below its origin


## The beasts are put down and wander the same way on every visit to the place.
func seed_with(n: int) -> void:
	_rng.seed = n


## How far from its home's height a beast is set down on the ground under it; past this the ground
## the terrain answers is not where it stands (a deck, a raised yard), and it keeps its home's.
const GROUND_REACH_M := 2.5


## Puts `count` beasts of `kind` (drawn from `paths`, the forge's variants) on the ground round
## `home`, keeping within `radius` of it. Call before the node enters the tree.
func keep(kind: String, paths: Array[String], home: Vector3, radius: float, count: int) -> void:
	if paths.is_empty() or not HABITS.has(kind):
		return
	for i in range(count):
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * radius
		var at := home + Vector3(cos(a), 0.0, sin(a)) * r
		beasts.append({"kind": kind, "path": paths[i % paths.size()], "home": home, "radius": radius,
				"at": at, "yaw": _rng.randf() * TAU, "target": at, "wait": _rng.randf() * 3.0, "instance": -1,
				"grazes": _rng.randf() < 0.65})


func _ready() -> void:
	add_to_group("livestock")
	for b in beasts:
		var rig := rigged_path(str(b["kind"]))
		if not rig.is_empty():
			b["path"] = rig
			b["rigged"] = true
	var by_path: Dictionary = {}
	for b in beasts:
		var path := str(b["path"])
		if not by_path.has(path):
			by_path[path] = []
		(by_path[path] as Array).append(b)
	for path in by_path:
		var packed := load(str(path)) as PackedScene
		if packed == null:
			continue
		var mesh := WorldStreamer._mesh_of(packed, 1)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var list: Array = by_path[path]
		mm.instance_count = list.size()
		for i in range(list.size()):
			(list[i] as Dictionary)["instance"] = i
		_mm[path] = mm
		var inst := MultiMeshInstance3D.new()
		inst.name = str(path).get_file().get_basename()
		inst.multimesh = mm
		# a beast wanders a few metres from where its instance was first put
		inst.extra_cull_margin = 8.0
		# the beasts are moved from _process, a tenth of a second at a time, and a MultiMesh the
		# physics interpolation keeps is to be moved from the physics ticks (the engine warns)
		inst.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		# a hen's shadow is a smudge under a hen, and a pass of the sun for each kind of bird; a
		# ewe's is her lowest rung (Settlement.shadow_of), moved with her
		var size := mesh.get_aabb().size
		var casts := maxf(size.x, maxf(size.y, size.z)) >= Settlement.SMALL_PROP_M
		var low := Settlement._lod_parts(packed, 2)
		FabricMesh.near_only(inst, RANGE_M, casts and low.is_empty())
		add_child(inst)
		if casts and not low.is_empty():
			var sh := Settlement.shadow_of(inst, low[0], RANGE_M)
			sh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			_shadow_mm[path] = sh.multimesh
			add_child(sh)
		_add_far(str(path), list)
		for b in list:
			_place(b)


## The far herd of a rigged kind: one MultiMesh of its bind-pose LOD2, beside the near one.
func _add_far(path: String, list: Array) -> void:
	if list.is_empty() or not bool((list[0] as Dictionary).get("rigged", false)):
		return
	var spec: Dictionary = FAR.get(str((list[0] as Dictionary)["kind"]), {})
	if spec.is_empty() or not ResourceLoader.exists(str(spec["mesh"])):
		return
	var mesh := far_mesh(str(spec["mesh"]))
	if mesh == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/herd_far.gdshader")
	var marks := far_marks(mesh)
	mat.set_shader_parameter("leg_top", marks["legs"])
	mat.set_shader_parameter("neck_pivot", marks["neck"])
	mat.set_shader_parameter("tail_pivot", marks["tail"])
	mat.set_shader_parameter("stride_hz", float(spec["hz"]))
	mat.set_shader_parameter("body_colour", spec["body"])
	mat.set_shader_parameter("head_colour", spec["head"])
	mat.set_shader_parameter("leg_colour", spec["legs"])
	mat.set_shader_parameter("tail_colour", spec["tail"])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# instance colours on, white: a MultiMesh with custom data and none drew its vertex colours as
	# black on Compatibility, and the shader reads its parts from them
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var b: Dictionary = list[i]
		b["far_pose"] = Color(_rng.randf(), 0.0, 1.0 if bool(b.get("grazes", true)) else 0.0, 0.0)
		mm.set_instance_color(i, Color.WHITE)
		mm.set_instance_custom_data(i, b["far_pose"])
	var inst := MultiMeshInstance3D.new()
	inst.name = path.get_file().get_basename() + "_far"
	inst.multimesh = mm
	inst.material_override = mat
	inst.extra_cull_margin = 8.0
	inst.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visibility_range_begin = FAR_FROM_M
	inst.visibility_range_begin_margin = FAR_FROM_M * 0.15
	inst.visibility_range_end = FAR_TO_M
	inst.visibility_range_end_margin = FAR_TO_M * 0.1
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(inst)
	_far_mm[path] = mm
	_far_lift[path] = maxf(0.0, -mesh.get_aabb().position.y)


## The first mesh in a GLB scene.
static func far_mesh(glb: String) -> Mesh:
	var packed := load(glb) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [root]
	while not stack.is_empty() and found == null:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			found = (n as MeshInstance3D).mesh
		for c in n.get_children():
			stack.append(c)
	root.free()
	return found


## Where the far mesh's parts hinge, from its colour marks: the top of each leg, the withers (the
## neck's lowest weight), the tail's root.
static func far_marks(mesh: Mesh) -> Dictionary:
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var legs := Vector4(0.0, 0.0, 0.0, 0.0)
	var neck := Vector3.ZERO
	var neck_w := 2.0
	var tail := Vector3.ZERO
	var tail_w := 2.0
	for i in mini(verts.size(), cols.size()):
		var c := cols[i]
		var v := verts[i]
		if c.r > 0.1:
			var id := clampi(roundi(c.r * 4.0) - 1, 0, 3)
			legs[id] = maxf(legs[id], v.y)
		elif c.g > 0.01 and c.g < neck_w:
			neck_w = c.g
			neck = v
		elif c.b > 0.01 and c.b < tail_w:
			tail_w = c.b
			tail = v
	return {"legs": legs, "neck": neck, "tail": tail}


## The rigged GLB for a kind, or "" when it has none (and keeps its props).
static func rigged_path(kind: String) -> String:
	var p := str(RIGGED.get(kind, ""))
	return p if not p.is_empty() and ResourceLoader.exists(p) else ""


func _process(delta: float) -> void:
	_clock += delta
	if _clock < TICK_S:
		return
	var dt := _clock
	_clock = 0.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or cam.global_position.distance_to(global_position) > AWAKE_M + 60.0:
		_let_go_of_live()
		return
	step(dt)
	_liven(cam.global_position)


## The nearest rigged beasts within LIVE_M of `eye` get a live model; the rest stand in the MultiMesh.
func _liven(eye: Vector3) -> void:
	var near: Array = []
	for i in beasts.size():
		var b: Dictionary = beasts[i]
		if not bool(b.get("rigged", false)):
			continue
		var d := (to_global(b["at"]) as Vector3).distance_to(eye)
		if d <= LIVE_M:
			near.append([d, i])
	near.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var want: Dictionary = {}
	for k in mini(near.size(), MAX_LIVE):
		want[int(near[k][1])] = true
	for i in _live.keys():
		if not want.has(i):
			(_live[i] as Node).queue_free()
			_live.erase(i)
			_place(beasts[i])
	for i in want:
		if not _live.has(i):
			var m := HorseModel.new()
			m.model_path = str(beasts[i]["path"])
			m.name = "Live_%d" % int(i)
			add_child(m)
			_live[i] = m
		_place(beasts[i])


func _let_go_of_live() -> void:
	for i in _live.keys():
		(_live[i] as Node).queue_free()
		_place(beasts[i])
	_live.clear()


## How many beasts are drawn by a live, animated model now (for tests and captures).
func live_count() -> int:
	return _live.size()


## Moves every beast on by `dt` seconds: a walk toward where it is going, or a stand where it is.
func step(dt: float) -> void:
	for b in beasts:
		var beast: Dictionary = b
		var habit: Dictionary = HABITS[beast["kind"]]
		if float(beast["wait"]) > 0.0:
			beast["wait"] = float(beast["wait"]) - dt
			if float(beast["wait"]) <= 0.0:
				beast["target"] = _next_target(beast, habit)
			continue
		var at: Vector3 = beast["at"]
		var to: Vector3 = beast["target"]
		var way := Vector3(to.x - at.x, 0.0, to.z - at.z)
		var left := way.length()
		var stride := float(habit["speed"]) * dt
		if left <= stride:
			beast["at"] = Vector3(to.x, at.y, to.z)
			var p: Array = habit["pause"]
			beast["wait"] = _rng.randf_range(float(p[0]), float(p[1]))
		else:
			beast["at"] = at + way / left * stride
			beast["yaw"] = atan2(-way.z, way.x) + (PI * 0.5 if bool(habit.get("sideways", false)) else 0.0)
		_place(beast)


## `at` (local) on the ground under it. The beasts were kept at their home's height wherever they
## wandered, so on a fold on sloping ground a ewe stood a metre over the turf at one side of it
## (w4096h: the seat audit's floating sheep at the Two-Knot Fold).
func _on_ground(at: Vector3) -> Vector3:
	if not is_inside_tree():
		return at
	var t := World.terrain()
	if t == null:
		return at
	var g := to_global(at)
	var h := t.get_height(g.x, g.z)
	if is_nan(h) or absf(h - g.y) > GROUND_REACH_M:
		return at
	return Vector3(at.x, at.y + h - g.y, at.z)


## Somewhere a short walk away that is still inside the beast's own patch.
func _next_target(beast: Dictionary, habit: Dictionary) -> Vector3:
	var at: Vector3 = beast["at"]
	var home: Vector3 = beast["home"]
	var s: Array = habit["step"]
	for i in range(6):
		var a := _rng.randf() * TAU
		var p := at + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(float(s[0]), float(s[1]))
		if Vector2(p.x - home.x, p.z - home.z).length() <= float(beast["radius"]):
			return p
	return home + (at - home) * 0.5


func _place(beast: Dictionary) -> void:
	var mm: MultiMesh = _mm.get(beast["path"], null)
	if mm == null or int(beast["instance"]) < 0:
		return
	var lift := maxf(0.0, -mm.mesh.get_aabb().position.y)
	var at: Vector3 = _on_ground(beast["at"])
	var yaw := float(beast["yaw"])
	# the props stand with their heads to +X, a rigged beast with its head to +Z (CONTRACTS §1)
	if bool(beast.get("rigged", false)):
		yaw += PI * 0.5
	var xf := Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0.0, lift, 0.0))
	var live: HorseModel = _live.get(beasts.find(beast), null) if not _live.is_empty() else null
	if live != null:
		live.transform = xf
		var moving := float(beast["wait"]) <= 0.0
		live.set_motion(float(HABITS[beast["kind"]]["speed"]) if moving else 0.0, 0.0, "Walk")
		live.grazing = not moving and bool(beast.get("grazes", true))
		xf = _hidden
	mm.set_instance_transform(int(beast["instance"]), xf)
	var far: MultiMesh = _far_mm.get(beast["path"], null)
	if far != null:
		var fxf := xf
		if live == null:
			fxf = Transform3D(xf.basis, at + Vector3(0.0, float(_far_lift[beast["path"]]), 0.0))
		far.set_instance_transform(int(beast["instance"]), fxf)
		var pose: Color = beast.get("far_pose", Color(0.0, 0.0, 1.0, 0.0))
		pose.g = 0.0 if float(beast["wait"]) > 0.0 else 1.0
		beast["far_pose"] = pose
		far.set_instance_custom_data(int(beast["instance"]), pose)
	var shadow: MultiMesh = _shadow_mm.get(beast["path"], null)
	if shadow != null:
		shadow.set_instance_transform(int(beast["instance"]), xf)


## The forge's variants of a beast, if it built them: the Vale's, or `region`'s.
static func paths_of(kind: String, region := "hearthvale") -> Array[String]:
	return Settlement._prop_paths(region, kind)
