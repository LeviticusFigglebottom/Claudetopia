class_name ScatterSolids
extends Node
## What the scatter draws near the player that a body does not walk through: tree trunks, rocks and
## boulders, stumps and logs, field walls, hedges and fences, gate posts, milestones and bales.
## Grass, flowers, bracken and bushes stay passable, and so does anything a foot steps over.
##
## The near ring (3x3 cells of 256 m round the player, where the foes and the people are) is cut
## into blocks of BLOCK_M, and each block with something solid in it stands one static body on the
## physics server, with a simple shape for each solid thing. A trunk is a cylinder of the forge's
## own trunk radius. A wall, a hedge or a fence module is the box of its bounds. A rock is the
## convex hull of its mesh, and a cliff slab is the hull of the forge's collision mesh. There are no
## nodes. The shapes are server calls, spread over ticks with the block nearest the player first,
## and a block's body joins the physics space whole, once its last shape is in: the physics engine
## re-files every shape of a body in space each time one is added, which made a 1000-shape cell
## cost it a million moves. The bodies go with their cell. The far ring has none.
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
## The side of a block (m): a cell of 256 m is sixty-four. The block the player stands in is solid
## a tick or two after its cell arrives, and the densest block (a wood) is some 50 shapes, whose
## join is a millisecond or so.
const BLOCK_M := 32.0
## How much of a physics tick the shapes may take (µs). An asset seen for the first time (its meta
## read, a rock's hull made: 2 to 15 ms here) is made at the start of a tick of its own, so a tick
## runs over by one asset at most, once a session.
const BUDGET_USEC := 1500
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
## What standing the shapes has cost: cells, blocks and shapes stood, assets made ready, and
## microseconds in all and in the worst tick. The capture runner and the solids probe report these.
static var stats := {"cells": 0, "blocks": 0, "shapes": 0, "assets": 0, "asset_us_total": 0, "asset_us_max": 0,
		"asset_worst": "", "join_us_max": 0, "tick_us": [], "stood_us_total": 0, "stood_us_max": 0, "ticks": 0}


## One block of a cell: its body, and what is still to stand in it.
class Job:
	extends RefCounted
	var node: Node3D
	## the block's middle, in the world, on the flat
	var centre := Vector2.ZERO
	var body := RID()
	var space := RID()
	## asset path -> rows of the cell's scatter in this block, and [Shape3D, Transform3D] the
	## wayside built there
	var groups: Dictionary = {}
	var paths: Array = []
	var extra: Array = []
	var gi := 0
	var ri := 0
	var ei := 0
	var shapes := 0
	var in_space := false
	var gone := false

	func finished() -> bool:
		return gi >= paths.size() and ei >= extra.size()


## Off, a block's body is in the space from its first shape (as it was first built): the solids
## probe's `--join-each`, to measure what joining whole saves.
static var join_whole := true

var _jobs: Array = []
## blocks whole and waiting to join the space, at the start of the next tick
var _to_join: Array = []
var _live: Array = []
var _sorted_for := Vector2.INF


## Takes a near-ring cell's scatter (`instances`, what it draws: asset path -> rows) and what the
## wayside built there (`extra`, [Shape3D, Transform3D] relative to the cell), and gives each of the
## cell's blocks with something solid in it a body, whose shapes `build` stands.
func add_cell(node: Node3D, instances: Dictionary, extra: Array = []) -> void:
	if node == null or not node.is_inside_tree():
		return
	var origin := node.global_position
	var blocks: Dictionary = {}          # Vector2i -> Job
	for path in instances:
		var p := str(path)
		if not maybe_solid(p):
			continue
		for row in instances[path]:
			var key := Vector2i(floori((float(row[0]) - origin.x) / BLOCK_M), floori((float(row[2]) - origin.z) / BLOCK_M))
			var job: Job = blocks.get(key)
			if job == null:
				job = Job.new()
				blocks[key] = job
			var rows: Array = job.groups.get_or_add(p, [])
			rows.append(row)
	for e in extra:
		var at: Vector3 = (e[1] as Transform3D).origin
		var key := Vector2i(floori(at.x / BLOCK_M), floori(at.z / BLOCK_M))
		var job: Job = blocks.get(key)
		if job == null:
			job = Job.new()
			blocks[key] = job
		job.extra.append(e)
	if blocks.is_empty():
		return
	var holder := Node.new()
	holder.name = "Solids"
	node.add_child(holder)
	var cell_jobs: Array = []
	var space := node.get_world_3d().space
	for key: Vector2i in blocks:
		var job: Job = blocks[key]
		job.node = node
		job.paths = job.groups.keys()
		job.centre = Vector2(origin.x + (float(key.x) + 0.5) * BLOCK_M, origin.z + (float(key.y) + 0.5) * BLOCK_M)
		job.space = space
		job.body = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(job.body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_collision_layer(job.body, LAYER)
		PhysicsServer3D.body_set_collision_mask(job.body, 0)
		PhysicsServer3D.body_attach_object_instance_id(job.body, holder.get_instance_id())
		PhysicsServer3D.body_set_state(job.body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), origin))
		# not in the space until its last shape is in (see the top)
		if not join_whole:
			PhysicsServer3D.body_set_space(job.body, space)
			job.in_space = true
		_jobs.append(job)
		_live.append(job)
		cell_jobs.append(job)
	holder.tree_exiting.connect(_drop_cell.bind(cell_jobs), CONNECT_ONE_SHOT)
	_sorted_for = Vector2.INF
	stats["cells"] += 1
	stats["blocks"] += cell_jobs.size()


## Stands the waiting blocks' shapes, the block nearest `eye` first, for at most `budget_usec` of
## this tick (0: all of them). Returns how many it stood.
func build(eye: Vector3, budget_usec: int = BUDGET_USEC) -> int:
	if _jobs.is_empty() and _to_join.is_empty():
		return 0
	var t0 := Time.get_ticks_usec()
	var flat := Vector2(eye.x, eye.z)
	# sorted again when a cell arrives or the eye has gone half a block: by keys the engine sorts,
	# since a GDScript comparison over the ring's 600 blocks is milliseconds
	if _jobs.size() > 1 and (_sorted_for == Vector2.INF or _sorted_for.distance_to(flat) > BLOCK_M * 0.5):
		var keyed: Array = []
		for i in _jobs.size():
			keyed.append([(_jobs[i] as Job).centre.distance_squared_to(flat), i])
		keyed.sort()
		var sorted: Array = []
		for k in keyed:
			sorted.append(_jobs[int(k[1])])
		_jobs = sorted
		_sorted_for = flat
	var deadline := t0 + budget_usec if budget_usec > 0 else 0
	var stood := 0
	# the blocks stood whole last tick join the space first: a join files every shape of the block
	# at once, so it is done at the start of a tick, and a tick that has joined one makes no new
	# asset that could run it over
	var joined := false
	while not _to_join.is_empty():
		_join(_to_join.pop_front())
		joined = true
		if deadline > 0 and Time.get_ticks_usec() - t0 >= (budget_usec >> 1):
			break
	# an asset seen for the first time is made only in a tick that has done nothing else heavy
	var free_from := -1 if joined else Time.get_ticks_usec()
	while not _jobs.is_empty() and (deadline == 0 or Time.get_ticks_usec() < deadline):
		var job: Job = _jobs[0]
		if job.gone:
			_jobs.pop_front()
			continue
		var n := _stand(job, deadline, free_from)
		stood += maxi(n, 0)
		if job.finished():
			_jobs.pop_front()
			if deadline == 0:
				_join(job)
			else:
				_to_join.append(job)
		elif n < 0:
			break
	var us := Time.get_ticks_usec() - t0
	stats["stood_us_total"] += us
	stats["stood_us_max"] = maxi(int(stats["stood_us_max"]), us)
	stats["ticks"] += 1
	(stats["tick_us"] as Array).append(us)
	return stood


func _join(job: Job) -> void:
	if job.gone or job.in_space or not job.body.is_valid():
		return
	var j0 := Time.get_ticks_usec()
	PhysicsServer3D.body_set_space(job.body, job.space)
	stats["join_us_max"] = maxi(int(stats["join_us_max"]), Time.get_ticks_usec() - j0)
	job.in_space = true


## Stands everything waiting, now: a test, or a body put down somewhere new.
func flush() -> int:
	return build(Vector3.ZERO, 0)


## Blocks still to stand, or to join the space.
func pending() -> int:
	return _jobs.size() + _to_join.size()


## Shapes standing, in all the live bodies.
func shape_count() -> int:
	var n := 0
	for job in _live:
		n += (job as Job).shapes
	return n


## Bodies standing, a block each.
func body_count() -> int:
	return _live.size()


## The bodies standing, for a probe or a test that wants to ask the server about them.
func bodies() -> Array[RID]:
	var out: Array[RID] = []
	for job in _live:
		out.append((job as Job).body)
	return out


## Shapes standing in the blocks of the cell `node`.
func shapes_under(node: Node3D) -> int:
	var n := 0
	for job in _live:
		n += (job as Job).shapes if (job as Job).node == node else 0
	return n


## The blocks of the cell `node` that are in the physics space.
func in_space_under(node: Node3D) -> int:
	var n := 0
	for job in _live:
		n += 1 if (job as Job).node == node and (job as Job).in_space else 0
	return n


## Whether each body is in the physics space yet (it joins whole, when its last shape is in).
func bodies_in_space() -> int:
	var n := 0
	for job in _live:
		n += 1 if (job as Job).in_space else 0
	return n


## Stands `job`'s shapes until `deadline` (µs; 0, all of them). An asset not yet made ready is made
## only at the start of a tick's work (`free_from`, or -1 when the tick has done something heavy
## already): met later, it waits for the next tick, and -1 says so.
func _stand(job: Job, deadline: int, free_from: int) -> int:
	var stood := 0
	var origin := job.node.global_position
	while job.gi < job.paths.size():
		var path := str(job.paths[job.gi])
		var rows: Array = job.groups[path]
		if job.ri >= rows.size():
			job.gi += 1
			job.ri = 0
			continue
		if deadline > 0 and not _shape_ready(path):
			if free_from < 0 or Time.get_ticks_usec() - free_from > 50:
				stats["shapes"] += stood
				return -1 if stood == 0 else stood
			stats["assets"] += 1
			var a0 := Time.get_ticks_usec()
			solid_of(path, rows[job.ri], origin)
			var aus := Time.get_ticks_usec() - a0
			stats["asset_us_total"] += aus
			if aus > int(stats["asset_us_max"]):
				stats["asset_us_max"] = aus
				stats["asset_worst"] = path.get_file()
		var solid := solid_of(path, rows[job.ri], origin)
		job.ri += 1
		if not solid.is_empty():
			PhysicsServer3D.body_add_shape(job.body, (solid[0] as Shape3D).get_rid(), solid[1])
			job.shapes += 1
			stood += 1
		if deadline > 0 and Time.get_ticks_usec() >= deadline:
			stats["shapes"] += stood
			return stood
	while job.ei < job.extra.size():
		var e: Array = job.extra[job.ei]
		job.ei += 1
		PhysicsServer3D.body_add_shape(job.body, (e[0] as Shape3D).get_rid(), e[1])
		job.shapes += 1
		stood += 1
		if deadline > 0 and Time.get_ticks_usec() >= deadline:
			break
	stats["shapes"] += stood
	return stood


## Whether an asset's shape can be had without reading its meta or making its hull.
static func _shape_ready(path: String) -> bool:
	if not _specs.has(path):
		return false
	var kind := str(_specs[path]["kind"])
	if kind == "hull":
		return _hulls.has(path)
	if kind == "mesh":
		return _faces.has(path)
	return true


func _drop_cell(jobs: Array) -> void:
	for job: Job in jobs:
		job.gone = true
		if job.body.is_valid():
			PhysicsServer3D.free_rid(job.body)
			job.body = RID()
		_live.erase(job)
		_jobs.erase(job)
		_to_join.erase(job)
		# the wayside's shapes were this cell's alone; the scatter's are shared and stay cached
		job.extra = []
		job.groups = {}


func _exit_tree() -> void:
	var jobs := _live.duplicate()
	_drop_cell(jobs)


## Whether an asset may stand as anything, from its path alone: grass, flowers, bracken and bushes
## (the flora), and loose or flat things, never do, and are not looked at again.
static func maybe_solid(path: String) -> bool:
	if _specs.has(path):
		return str(_specs[path]["kind"]) != "none"
	if not path.contains("/trees/") and not path.contains("/rocks/") and not path.contains("/props/"):
		return false
	var file := path.get_file()
	for word in PASSABLE:
		if file.contains(word):
			return false
	return true


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
