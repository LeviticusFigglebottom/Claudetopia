class_name Livestock
extends Node3D
## A settlement's beasts, where its people keep them: hens in the yards, geese on the green,
## sheep in the paddock behind the houses, a pig in its sty.
##
## A village with nobody's hens scratching in it is a model of a village. Each kind is one
## MultiMesh; each beast keeps to its own patch of ground and wanders it the way its kind does --
## a hen in quick short runs with long stops, a ewe a slow step at a time with its head in the
## grass -- and only while somebody is near enough to see it: past `AWAKE_M` nothing is moved
## and the beasts stand where they were.

## How each kind goes about: how fast it walks (m/s), how far from home it wanders, and how long
## it stands between one walk and the next.
const HABITS := {
	"hen": {"speed": 0.7, "pause": [0.8, 3.5], "step": [0.4, 1.4]},
	"goose": {"speed": 0.45, "pause": [2.0, 7.0], "step": [0.8, 2.5]},
	"sheep": {"speed": 0.3, "pause": [4.0, 14.0], "step": [0.5, 2.0]},
	"pig": {"speed": 0.25, "pause": [3.0, 12.0], "step": [0.3, 0.9]},
}
const AWAKE_M := 110.0
const TICK_S := 0.1
const RANGE_M := 180.0

## {kind, path, home (Vector3, this node's space), radius, at, yaw, target, wait, instance}
var beasts: Array = []
var _mm: Dictionary = {}           # path -> MultiMesh
var _rng := RandomNumberGenerator.new()
var _clock := 0.0


## The beasts are put down and wander the same way on every visit to the place.
func seed_with(n: int) -> void:
	_rng.seed = n


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
				"at": at, "yaw": _rng.randf() * TAU, "target": at, "wait": _rng.randf() * 3.0, "instance": -1})


func _ready() -> void:
	add_to_group("livestock")
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
		FabricMesh.near_only(inst, RANGE_M, true)
		add_child(inst)
		for b in list:
			_place(b)


func _process(delta: float) -> void:
	_clock += delta
	if _clock < TICK_S:
		return
	var dt := _clock
	_clock = 0.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or cam.global_position.distance_to(global_position) > AWAKE_M + 60.0:
		return
	step(dt)


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
			beast["yaw"] = atan2(-way.z, way.x)
		_place(beast)


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
	var at: Vector3 = beast["at"]
	mm.set_instance_transform(int(beast["instance"]),
			Transform3D(Basis(Vector3.UP, float(beast["yaw"])), at + Vector3(0.0, lift, 0.0)))


## The forge's variants of a beast, if it built them.
static func paths_of(kind: String) -> Array[String]:
	return Settlement._prop_paths("hearthvale", kind)
