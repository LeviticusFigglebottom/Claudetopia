class_name ScatterSolids
extends Node
## What the scatter draws near the player that a body does not walk through: tree trunks, rocks and
## boulders, stumps and logs, field walls, hedges and fences, gate posts, milestones and bales.
## Grass, flowers, bracken and bushes stay passable, and so does anything a foot steps over.
##
## Each cell of the near ring (3x3 round the player, where the foes and the people are) stands one
## static body on the physics server, with a simple shape for each solid thing in it. A trunk is a
## cylinder of the forge's own trunk radius. A wall, a hedge or a fence module is the box of its
## bounds. A rock is the convex hull of its mesh, and a cliff slab is the forge's collision mesh.
## There are no nodes. A cell's shapes are server calls, spread over frames with the nearest cell
## first, and the body goes with the cell. The far ring has none.
##
## The shapes are on a layer of their own (13, "scatter"). The player, the foes and the people walk
## into it (Actor.BODY_MASK and their scenes' masks). The camera's arm, sight, arrows, footsteps and
## the quests' ground rays do not see it. So a trunk between the camera and the player does not
## pull the camera in, as a house wall does.

const LAYER := 1 << 12
## A thing lower than this as it stands (m) is stepped over, not walked into.
const MIN_HEIGHT_M := 0.45
## A trunk stands from under the ground to at most this (m): enough to walk into, and the crown is
## walked under.
const TRUNK_TOP_M := 4.5
## How far under the ground a shape reaches, so a slope leaves no gap under it.
const SINK_M := 0.4
## How much of a physics tick the shapes may take (µs).
const BUDGET_USEC := 1500
## How many shapes are stood between two looks at the clock.
const CHUNK := 24
## The most points a rock's hull may have: the physics engine takes a hull of at most 256.
const MAX_HULL_POINTS := 200
## Passable whatever the forge says: loose stones, driftwood, what lies flat or is walked on. A
## signpost is built by the wayside, which stands its post.
const PASSABLE := ["scree", "pebble", "driftwood", "moss", "lichen", "plank", "signpost"]
## Laid in lines or stacked square, and stood as the box of their bounds.
const BOXED := ["drystone_wall", "fence", "hedge_segment", "hurdle", "paling", "hay_bale"]
## Solid though the forge says none: a hedge is a field's wall, and the field's gate is its gap.
const SOLID_ANYWAY := ["hedge_segment"]

## asset path -> how it stands (see `spec_for`)
static var _specs: Dictionary = {}
## The shapes, shared by every body that stands one of them: a trunk's by (radius, height), a
## box's by its size, and a rock's hull or collision mesh by asset path, then scale.
static var _cylinders: Dictionary = {}
static var _boxes: Dictionary = {}
static var _scaled: Dictionary = {}
## asset path -> the unscaled hull points or collision faces its scaled shapes are made from
static var _hulls: Dictionary = {}
static var _faces: Dictionary = {}
## What standing the shapes has cost: cells and shapes stood, and microseconds in all and in the
## worst tick. The capture runner and the solids probe report these.
static var stats := {"cells": 0, "shapes": 0, "stood_us_total": 0, "stood_us_max": 0, "ticks": 0}


## One cell's body and what is still to stand in it.
class Job:
	extends RefCounted
	var node: Node3D
	var holder: Node
	var body := RID()
	## [asset path, rows] of the cell's scatter, and [Shape3D, Transform3D] the wayside built
	var groups: Array = []
	var extra: Array = []
	var gi := 0
	var ri := 0
	var ei := 0
	var shapes := 0
	var gone := false

	func finished() -> bool:
		return gi >= groups.size() and ei >= extra.size()


var _jobs: Array = []
var _live: Array = []


## Takes a near-ring cell's scatter (`instances`, what it draws: asset path -> rows) and what the
## wayside built there (`extra`, [Shape3D, Transform3D] relative to the cell), and gives the cell a
## body its shapes are stood in by `build`.
func add_cell(node: Node3D, instances: Dictionary, extra: Array = []) -> void:
	if node == null or not node.is_inside_tree():
		return
	var job := Job.new()
	job.node = node
	for path in instances:
		if str(spec_for(str(path))["kind"]) != "none":
			job.groups.append([str(path), instances[path]])
	job.extra = extra
	if job.groups.is_empty() and job.extra.is_empty():
		return
	job.holder = Node.new()
	job.holder.name = "Solids"
	node.add_child(job.holder)
	job.holder.tree_exiting.connect(_drop.bind(job), CONNECT_ONE_SHOT)
	job.body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(job.body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(job.body, LAYER)
	PhysicsServer3D.body_set_collision_mask(job.body, 0)
	PhysicsServer3D.body_attach_object_instance_id(job.body, job.holder.get_instance_id())
	PhysicsServer3D.body_set_state(job.body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), node.global_position))
	PhysicsServer3D.body_set_space(job.body, node.get_world_3d().space)
	_jobs.append(job)
	_live.append(job)
	stats["cells"] += 1


## Stands the waiting cells' shapes, the cell nearest `eye` first, for at most `budget_usec` of
## this tick (0: all of them). Returns how many it stood.
func build(eye: Vector3, budget_usec: int = BUDGET_USEC) -> int:
	if _jobs.is_empty():
		return 0
	var t0 := Time.get_ticks_usec()
	if _jobs.size() > 1:
		_jobs.sort_custom(func(a: Job, b: Job) -> bool:
				return _flat_d2(a, eye) < _flat_d2(b, eye))
	var stood := 0
	while not _jobs.is_empty():
		var job: Job = _jobs[0]
		if job.gone:
			_jobs.pop_front()
			continue
		stood += _stand(job, CHUNK if budget_usec > 0 else 1 << 30)
		if job.finished():
			_jobs.pop_front()
		if budget_usec > 0 and Time.get_ticks_usec() - t0 >= budget_usec:
			break
	var us := Time.get_ticks_usec() - t0
	stats["stood_us_total"] += us
	stats["stood_us_max"] = maxi(int(stats["stood_us_max"]), us)
	stats["ticks"] += 1
	return stood


## Stands everything waiting, now: a test, or a body put down somewhere new.
func flush() -> int:
	return build(Vector3.ZERO, 0)


func pending() -> int:
	return _jobs.size()


## Shapes standing, in all the live bodies.
func shape_count() -> int:
	var n := 0
	for job in _live:
		n += (job as Job).shapes
	return n


func body_count() -> int:
	return _live.size()


## The bodies standing, for a probe or a test that wants to ask the server about them.
func bodies() -> Array[RID]:
	var out: Array[RID] = []
	for job in _live:
		out.append((job as Job).body)
	return out


static func _flat_d2(job: Job, eye: Vector3) -> float:
	if not is_instance_valid(job.node):
		return INF
	var p := job.node.global_position
	return Vector2(p.x - eye.x, p.z - eye.z).length_squared()


func _stand(job: Job, count: int) -> int:
	var stood := 0
	var origin := job.node.global_position
	while stood < count and job.gi < job.groups.size():
		var group: Array = job.groups[job.gi]
		var rows: Array = group[1]
		if job.ri >= rows.size():
			job.gi += 1
			job.ri = 0
			continue
		var solid := solid_of(str(group[0]), rows[job.ri], origin)
		job.ri += 1
		if solid.is_empty():
			continue
		PhysicsServer3D.body_add_shape(job.body, (solid[0] as Shape3D).get_rid(), solid[1])
		job.shapes += 1
		stood += 1
	while stood < count and job.ei < job.extra.size():
		var e: Array = job.extra[job.ei]
		job.ei += 1
		PhysicsServer3D.body_add_shape(job.body, (e[0] as Shape3D).get_rid(), e[1])
		job.shapes += 1
		stood += 1
	stats["shapes"] += stood
	return stood


func _drop(job: Job) -> void:
	job.gone = true
	if job.body.is_valid():
		PhysicsServer3D.free_rid(job.body)
		job.body = RID()
	_live.erase(job)
	_jobs.erase(job)
	# the wayside's shapes were this cell's alone; the scatter's are shared and stay cached
	job.extra = []


func _exit_tree() -> void:
	for job in _live.duplicate():
		_drop(job)


# --- what stands as what ----------------------------------------------------------------------

## How an asset stands: {"kind": "none"} for what is walked through, or "trunk" (a cylinder of the
## forge's trunk radius), "box" (its bounds), "hull" (its mesh's convex hull) or "mesh" (the
## forge's own collision mesh), with "tall", its height unscaled. From the meta beside the glb.
static func spec_for(path: String) -> Dictionary:
	if _specs.has(path):
		return _specs[path]
	var spec := _make_spec(path)
	_specs[path] = spec
	return spec


static func _make_spec(path: String) -> Dictionary:
	var none := {"kind": "none", "tall": 0.0}
	var tree := path.contains("/trees/")
	if not tree and not path.contains("/rocks/") and not path.contains("/props/"):
		return none                       # grass, flowers, bracken, bushes
	var file := path.get_file().get_basename()
	for word in PASSABLE:
		if file.contains(word):
			return none
	var m := meta(path)
	var b: Dictionary = m.get("bounds", {})
	var lo := _vec3(b.get("min", []))
	var hi := _vec3(b.get("max", []))
	var tall := float(b.get("height", hi.y - lo.y))
	var col := str(m.get("collision", "none"))
	var anyway := false
	for word in SOLID_ANYWAY:
		anyway = anyway or file.contains(word)
	if (col == "none" or col == "") and not anyway:
		return none
	var params: Dictionary = m.get("collision_params", {})
	if tree or col == "capsule":
		return {"kind": "trunk", "radius": float(params.get("radius", 0.2)),
				"height": float(params.get("height", tall)), "tall": tall}
	for word in BOXED:
		if file.contains(word):
			return {"kind": "box", "min": lo, "max": hi, "tall": tall}
	if col.ends_with(".glb"):
		# a rock's collision mesh is a rock's shape: its hull stands as well as the mesh and costs a
		# fraction, at every scale a slab is strewn at
		var kind := "hull" if path.contains("/rocks/") else "mesh"
		return {"kind": kind, "col": path.get_base_dir() + "/" + col, "tall": tall}
	return {"kind": "hull", "tall": tall}


## The shape one scatter row stands as and where, relative to `origin` (the cell's): [Shape3D,
## Transform3D], or [] when it is passable.
static func solid_of(path: String, row: Array, origin: Vector3) -> Array:
	var spec := spec_for(path)
	var kind := str(spec["kind"])
	if kind == "none":
		return []
	var t := row_transform(row, origin)
	var scale3 := t.basis.get_scale()
	if float(spec["tall"]) * scale3.y < MIN_HEIGHT_M:
		return []
	var at := Transform3D(t.basis.orthonormalized(), t.origin)
	match kind:
		"trunk":
			var r := snappedf(clampf(float(spec["radius"]) * scale3.x, 0.1, 6.0), 0.02)
			var top := snappedf(minf(float(spec["height"]) * scale3.y, TRUNK_TOP_M), 0.1)
			return [_cylinder(r, top + SINK_M), at * Transform3D(Basis(), Vector3(0.0, (top - SINK_M) * 0.5, 0.0))]
		"box":
			var lo: Vector3 = spec["min"]
			var hi: Vector3 = spec["max"]
			var size := ((hi - lo) * scale3).snapped(Vector3.ONE * 0.05) + Vector3(0.0, SINK_M, 0.0)
			var centre := (hi + lo) * 0.5 * scale3 - Vector3(0.0, SINK_M * 0.5, 0.0)
			return [_box(size), at * Transform3D(Basis(), centre)]
		"hull":
			var hull := _hull(path, snappedf(scale3.x, 0.05))
			return [hull, at] if hull != null else []
		"mesh":
			var faces := _mesh(path, str(spec["col"]), snappedf(scale3.x, 0.05))
			return [faces, at] if faces != null else []
	return []


## A scatter row's transform relative to `origin`: [x, y, z, yaw_deg, scale, tint], and optionally
## [.., lean_deg, lean_toward_deg] and a fitted [sx, sy, sz] (CONTRACTS §6). The same as
## WorldStreamer.instance_transform, which draws the row; a test holds the two together.
static func row_transform(row: Array, origin: Vector3) -> Transform3D:
	var pos := Vector3(float(row[0]), float(row[1]), float(row[2])) - origin
	var yaw := deg_to_rad(float(row[3])) if row.size() > 3 else 0.0
	var s := float(row[4]) if row.size() > 4 else 1.0
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
	if row.size() > 8:
		var f: Array = row[8]
		b = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(float(f[0]), float(f[1]), float(f[2])))
	if row.size() > 7 and float(row[6]) != 0.0:
		var toward := deg_to_rad(float(row[7]))
		var dir := Vector3(cos(toward), 0.0, sin(toward))
		b = Basis(Vector3.UP.cross(dir).normalized(), deg_to_rad(float(row[6]))) * b
	return Transform3D(b, pos)


static func _cylinder(r: float, h: float) -> Shape3D:
	var key := Vector2(r, h)
	if not _cylinders.has(key):
		var c := CylinderShape3D.new()
		c.radius = r
		c.height = h
		_cylinders[key] = c
	return _cylinders[key]


static func _box(size: Vector3) -> Shape3D:
	if not _boxes.has(size):
		var b := BoxShape3D.new()
		b.size = size.max(Vector3.ONE * 0.05)
		_boxes[size] = b
	return _boxes[size]


## A rock's convex hull, from its coarsest level of detail that still has a shape (the full mesh's
## hull has hundreds of points and stands no differently), at a scale. Not the engine's simplified
## hull: that is a convex decomposition, a quarter of a second a rock.
static func _hull(path: String, s: float) -> Shape3D:
	var by_scale: Dictionary = _scaled.get_or_add(path, {})
	if by_scale.has(s):
		return by_scale[s]
	if not _hulls.has(path):
		var points := PackedVector3Array()
		var tries := _meshes_of(path)
		var col := str(spec_for(path).get("col", ""))
		if col != "":
			var faces := _collision_faces(col)
			if faces.size() >= 3:
				var arrays := []
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX] = faces
				var am := ArrayMesh.new()
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				tries = [am]
		for m in tries:
			var hull := (m as Mesh).create_convex_shape(true, false) as ConvexPolygonShape3D
			# a level collapsed to a few triangles is no rock: the next finer one is tried
			if hull != null and hull.points.size() >= 8 and hull.points.size() <= MAX_HULL_POINTS:
				points = hull.points
				break
		_hulls[path] = points
	var pts: PackedVector3Array = (_hulls[path] as PackedVector3Array).duplicate()
	var out: Shape3D = null
	if pts.size() >= 4:
		for i in pts.size():
			pts[i] *= s
		var c := ConvexPolygonShape3D.new()
		c.points = pts
		out = c
	by_scale[s] = out
	return out


## The forge's own collision mesh for an asset (its `*_col.glb`), at a scale.
static func _mesh(path: String, col_path: String, s: float) -> Shape3D:
	var by_scale: Dictionary = _scaled.get_or_add(path, {})
	if by_scale.has(s):
		return by_scale[s]
	if not _faces.has(path):
		_faces[path] = _collision_faces(col_path)
	var faces: PackedVector3Array = (_faces[path] as PackedVector3Array).duplicate()
	var out: Shape3D = null
	if faces.size() >= 3:
		for i in faces.size():
			faces[i] *= s
		var c := ConcavePolygonShape3D.new()
		c.set_faces(faces)
		out = c
	by_scale[s] = out
	return out


## Every triangle of a collision scene, in its root's space. The scene never enters the tree, so a
## mesh's place in it is composed from the local transforms.
static func _collision_faces(col_path: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not ResourceLoader.exists(col_path):
		return out
	var packed := load(col_path) as PackedScene
	if packed == null:
		return out
	var root := packed.instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for v in mesh.get_faces():
			out.append(xf * v)
	root.free()
	return out


## An asset's meshes, coarsest level of detail first and the full mesh last: what a rock's hull is
## tried from.
static func _meshes_of(path: String) -> Array:
	if not ResourceLoader.exists(path):
		return []
	var packed := load(path) as PackedScene
	if packed == null:
		return []
	var state := packed.get_state()
	var full: Mesh = null
	var by_level: Dictionary = {}
	for i in state.get_node_count():
		if state.get_node_type(i) != "MeshInstance3D":
			continue
		var node_name := str(state.get_node_name(i))
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) != "mesh":
				continue
			var v: Variant = state.get_node_property_value(i, p)
			if not (v is Mesh):
				continue
			var at := node_name.rfind("_LOD")
			if at < 0:
				if full == null:
					full = v
			else:
				by_level[int(node_name.substr(at + 4).to_int())] = v
	var levels: Array = by_level.keys()
	levels.sort()
	levels.reverse()
	var out: Array = []
	for level in levels:
		out.append(by_level[level])
	if full != null:
		out.append(full)
	return out


## The forge's meta beside a glb: collision kind, bounds, trunk.
static func meta(path: String) -> Dictionary:
	var meta_path := path.get_basename() + ".meta.json"
	if not FileAccess.file_exists(meta_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	return parsed if parsed is Dictionary else {}


static func _vec3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


# --- a body with nowhere to go ------------------------------------------------------------------

## How long a body has to be getting nowhere before it walks through, and for how long it does.
const STUCK_S := 1.0
const THROUGH_S := 1.5

## A villager or a foe that is walking and has not got anywhere for a second -- pressed square
## against a wall, caught in the crook of two trunks -- walks through the scatter for a moment, as
## everything did before the scatter was solid. One with nowhere to go is worse than one that
## brushes through a hedge. `wanted` is the horizontal velocity it asked for this tick. Called
## after `move_and_slide`. The player never is: a hand steers round.
static func unstick(body: CharacterBody3D, wanted: Vector3, delta: float) -> void:
	var s: Dictionary = body.get_meta("_scatter_unstick", {})
	if s.is_empty():
		s = {"from": body.global_position, "asked": 0.0, "t": 0.0, "through": 0.0}
		body.set_meta("_scatter_unstick", s)
	if float(s["through"]) > 0.0:
		s["through"] = float(s["through"]) - delta
		if float(s["through"]) <= 0.0:
			body.collision_mask |= LAYER
			s["from"] = body.global_position
			s["asked"] = 0.0
			s["t"] = 0.0
		return
	var speed := Vector2(wanted.x, wanted.z).length()
	if speed < 0.3:
		s["from"] = body.global_position
		s["asked"] = 0.0
		s["t"] = 0.0
		return
	s["asked"] = float(s["asked"]) + speed * delta
	s["t"] = float(s["t"]) + delta
	if float(s["t"]) < STUCK_S:
		return
	var from: Vector3 = s["from"]
	var went := Vector2(body.global_position.x - from.x, body.global_position.z - from.z).length()
	if went < float(s["asked"]) * 0.25 and (body.collision_mask & LAYER) != 0:
		body.collision_mask &= ~LAYER
		s["through"] = THROUGH_S
	s["from"] = body.global_position
	s["asked"] = 0.0
	s["t"] = 0.0
