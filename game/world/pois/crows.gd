class_name Crows
extends Node3D
## A few crows about a camp: sat on what stands up in it, put up by anybody who comes near, wheeling
## over it a while, and coming back down to sit once they are left alone.
##
## The playtest found the start "a little sparse", and nothing in it moved but the smoke and the
## Warden. There are no animal models in Wickmere yet, and a crow is a thing seen as a shape against
## the sky: a body, a head, a tail and two wings, drawn here and shared by every bird, black enough
## that the shape is all there is to read. The wings are pivots, so a bird flaps and glides.
##
## Everything a bird does is in local space: `perches` are points on things the camp stood up, and
## the wheel is a circle `radius` wide at `height` above `centre`. Engine time moves them, so a
## paused world holds them where they are.

signal put_up(index: int)

const BODY_COLOUR := Color(0.05, 0.05, 0.06)
## A body nearer than this (flat distance) to a sitting crow puts it up.
const SPOOK_M := 7.0
## A crow wheels at least this long before it thinks of sitting again, and only comes down to a
## perch nobody is standing near.
const WHEEL_SECONDS := Vector2(14.0, 30.0)
const FLAP_HZ := 3.4
const TAKE_OFF_SECONDS := 2.4
const COME_DOWN_SECONDS := 3.6

enum State { SITTING, TAKING_OFF, WHEELING, COMING_DOWN }

var perches: Array[Vector3] = []
var centre := Vector3.ZERO
var radius := 16.0
var height := 18.0
## What counts as somebody coming near: the nodes in this group.
var spooked_by := "player"

var _birds: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _time := 0.0

static var _body_mesh: ArrayMesh = null
static var _wing_mesh: ArrayMesh = null
static var _material: StandardMaterial3D = null


## Stands `count` crows up, one on each of the first perches, the rest on the wheel.
func setup(at_perches: Array[Vector3], wheel_centre: Vector3, how_many: int, seed_value: int) -> void:
	perches = at_perches
	centre = wheel_centre
	_rng.seed = seed_value
	for i in how_many:
		var bird := _make_bird(i)
		if i < perches.size():
			bird["state"] = State.SITTING
			bird["perch"] = i
			(bird["node"] as Node3D).position = perches[i]
			(bird["node"] as Node3D).rotation.y = _rng.randf_range(0.0, TAU)
			bird["next"] = _rng.randf_range(1.0, 4.0)
		else:
			bird["state"] = State.WHEELING
			bird["until"] = _rng.randf_range(WHEEL_SECONDS.x, WHEEL_SECONDS.y)
			(bird["node"] as Node3D).position = _on_wheel(bird)
		_birds.append(bird)


func count() -> int:
	return _birds.size()


func state_of(index: int) -> int:
	return int(_birds[index]["state"])


func position_of(index: int) -> Vector3:
	return (_birds[index]["node"] as Node3D).position


## How many are sitting.
func sitting() -> int:
	var n := 0
	for b in _birds:
		if int(b["state"]) == State.SITTING:
			n += 1
	return n


func _process(delta: float) -> void:
	step(delta)


## Moves every crow on by `delta` seconds.
func step(delta: float) -> void:
	_time += delta
	var near := _near_bodies()
	for i in _birds.size():
		var b: Dictionary = _birds[i]
		var node := b["node"] as Node3D
		b["t"] = float(b["t"]) + delta
		match int(b["state"]):
			State.SITTING:
				_flap(b, 0.0, 0.0)
				if _somebody_near(node.position, near, SPOOK_M):
					_take_off(i)
				elif float(b["t"]) >= float(b["next"]):
					# a look round, a hop on the spot
					b["t"] = 0.0
					b["next"] = _rng.randf_range(1.5, 5.0)
					node.rotation.y += _rng.randf_range(-1.4, 1.4)
			State.TAKING_OFF:
				var k := clampf(float(b["t"]) / TAKE_OFF_SECONDS, 0.0, 1.0)
				var to := _on_wheel(b)
				var from: Vector3 = b["from"]
				var at := from.lerp(to, _ease(k)) + Vector3(0.0, sin(k * PI) * 2.0, 0.0)
				_face_towards(node, at)
				node.position = at
				_flap(b, 1.0, 0.0)
				b["angle"] = float(b["angle"]) + float(b["speed"]) * delta
				if k >= 1.0:
					b["state"] = State.WHEELING
					b["t"] = 0.0
					b["until"] = _rng.randf_range(WHEEL_SECONDS.x, WHEEL_SECONDS.y)
			State.WHEELING:
				b["angle"] = float(b["angle"]) + float(b["speed"]) * delta
				var at := _on_wheel(b)
				_face_towards(node, at)
				node.position = at
				# flap a while, glide a while, banked into the turn
				var flapping := fmod(float(b["t"]) + float(b["phase"]), 5.0) < 1.6
				_flap(b, 1.0 if flapping else 0.0, -0.35 * signf(float(b["speed"])))
				if float(b["t"]) >= float(b["until"]):
					var perch := _free_perch(near)
					if perch >= 0:
						b["state"] = State.COMING_DOWN
						b["perch"] = perch
						b["from"] = node.position
						b["t"] = 0.0
					else:
						b["until"] = float(b["t"]) + _rng.randf_range(6.0, 12.0)
			State.COMING_DOWN:
				var k := clampf(float(b["t"]) / COME_DOWN_SECONDS, 0.0, 1.0)
				var to: Vector3 = perches[int(b["perch"])]
				if _somebody_near(to, near, SPOOK_M):
					_take_off(i)
					continue
				var from: Vector3 = b["from"]
				var at := from.lerp(to, _ease(k))
				if k < 1.0:
					_face_towards(node, at)
				node.position = at
				_flap(b, 1.0 if k > 0.75 else 0.0, 0.0)
				if k >= 1.0:
					b["state"] = State.SITTING
					b["t"] = 0.0
					b["next"] = _rng.randf_range(1.0, 3.0)
					node.rotation = Vector3(0.0, node.rotation.y, 0.0)


func _take_off(i: int) -> void:
	var b: Dictionary = _birds[i]
	var node := b["node"] as Node3D
	b["state"] = State.TAKING_OFF
	b["from"] = node.position
	b["perch"] = -1
	b["t"] = 0.0
	# onto the wheel at the bearing it is at, so it climbs away rather than across the camp
	var off := node.position - centre
	b["angle"] = atan2(off.z, off.x)
	put_up.emit(i)


func _on_wheel(b: Dictionary) -> Vector3:
	var a := float(b["angle"])
	var r := radius * float(b["reach"])
	var bob := sin(_time * 0.6 + float(b["phase"])) * 1.2
	return centre + Vector3(cos(a) * r, height * float(b["lift"]) + bob, sin(a) * r)


func _free_perch(near: Array[Vector3]) -> int:
	var taken := {}
	for b in _birds:
		if int(b["perch"]) >= 0:
			taken[int(b["perch"])] = true
	var start := _rng.randi_range(0, maxi(perches.size() - 1, 0))
	for j in perches.size():
		var p := (start + j) % perches.size()
		if not taken.has(p) and not _somebody_near(perches[p], near, SPOOK_M * 1.6):
			return p
	return -1


func _near_bodies() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(spooked_by):
		if n is Node3D:
			out.append(to_local((n as Node3D).global_position))
	return out


static func _somebody_near(at: Vector3, bodies: Array[Vector3], within: float) -> bool:
	for p in bodies:
		if Vector2(p.x - at.x, p.z - at.z).length() < within:
			return true
	return false


static func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


func _face_towards(node: Node3D, at: Vector3) -> void:
	var d := at - node.position
	if Vector2(d.x, d.z).length() > 0.001:
		node.rotation.y = atan2(d.x, d.z)


## Wings: `beat` 1 flaps, 0 holds them out to glide; a sitting crow has them folded back along its
## body. `bank` rolls the body into the turn.
func _flap(b: Dictionary, beat: float, bank: float) -> void:
	var node := b["node"] as Node3D
	var left := b["left"] as Node3D
	var right := b["right"] as Node3D
	var is_sitting := int(b["state"]) == State.SITTING
	if is_sitting:
		left.rotation = Vector3(0.0, 1.3, -0.15)
		right.rotation = Vector3(0.0, -1.3, 0.15)
	else:
		var angle := sin((_time + float(b["phase"])) * TAU * FLAP_HZ) * 0.9 if beat > 0.0 else 0.08
		left.rotation = Vector3(0.0, 0.0, angle)
		right.rotation = Vector3(0.0, 0.0, -angle)
	node.rotation.z = lerpf(node.rotation.z, 0.0 if is_sitting else bank, 0.1)


func _make_bird(i: int) -> Dictionary:
	_build_meshes()
	var node := Node3D.new()
	node.name = "Crow%d" % i
	var s := _rng.randf_range(0.9, 1.1)
	node.scale = Vector3.ONE * s
	add_child(node)
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(body)
	var pivots: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.04, 0.03, 0.02)
		node.add_child(pivot)
		var wing := MeshInstance3D.new()
		wing.mesh = _wing_mesh
		wing.scale = Vector3(side, 1.0, 1.0)
		wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(wing)
		pivots.append(pivot)
	return {
		"node": node, "left": pivots[1], "right": pivots[0], "state": State.WHEELING, "perch": -1,
		"t": 0.0, "next": 0.0, "until": 0.0, "from": Vector3.ZERO,
		"angle": _rng.randf_range(0.0, TAU), "speed": _rng.randf_range(0.35, 0.55) * (1.0 if _rng.randf() < 0.7 else -1.0),
		"reach": _rng.randf_range(0.7, 1.15), "lift": _rng.randf_range(0.8, 1.2), "phase": _rng.randf_range(0.0, 5.0),
	}


static func _build_meshes() -> void:
	if _body_mesh != null:
		return
	_material = StandardMaterial3D.new()
	_material.albedo_color = BODY_COLOUR
	_material.roughness = 0.85
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# the body: a long diamond from beak to tail, +Z forward (as the forge's props face)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nose := Vector3(0.0, 0.05, 0.26)       # the beak's tip
	var head := Vector3(0.0, 0.07, 0.17)
	var chest := [Vector3(0.0, 0.11, 0.05), Vector3(0.065, 0.04, 0.04), Vector3(0.0, -0.02, 0.04), Vector3(-0.065, 0.04, 0.04)]
	var rump := Vector3(0.0, 0.04, -0.14)
	var tail := [Vector3(0.05, 0.04, -0.3), Vector3(-0.05, 0.04, -0.3)]
	for j in 4:
		var a: Vector3 = chest[j]
		var b: Vector3 = chest[(j + 1) % 4]
		_tri(st, head, a, b)
		_tri(st, rump, b, a)
	_tri(st, nose, head + Vector3(0.03, 0.0, 0.0), head + Vector3(-0.03, 0.0, 0.0))
	_tri(st, nose, head + Vector3(0.0, 0.03, 0.0), head + Vector3(0.0, -0.03, 0.0))
	_tri(st, rump, tail[0], tail[1])
	st.generate_normals()
	st.set_material(_material)
	_body_mesh = st.commit()
	# a wing: out to the left (+X), swept back at the tip
	var sw := SurfaceTool.new()
	sw.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_front := Vector3(0.0, 0.0, 0.06)
	var root_back := Vector3(0.0, 0.0, -0.08)
	var elbow := Vector3(0.2, 0.01, 0.03)
	var tip := Vector3(0.38, 0.0, -0.1)
	_tri(sw, root_front, elbow, root_back)
	_tri(sw, root_back, elbow, tip)
	sw.generate_normals()
	sw.set_material(_material)
	_wing_mesh = sw.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
