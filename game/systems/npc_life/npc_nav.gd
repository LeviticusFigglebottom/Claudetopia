class_name NpcNav
extends Node
## The ways round a town, for the people who live in it.
##
## A villager's walk was a straight line with detours (Npc's stuck watch): enough to get round a
## house or a stall, not round a row of gardens fenced to the street. This stands a navigation mesh
## over a settlement when the player comes near it, and over a house when the player goes in, and
## `path` asks it for the way.
##
## The mesh is made from what a body cannot walk through, read off the physics space rather than
## the scene: one query over the ground names every solid shape there (the houses' boxes, the
## fences and walls of the yards, the market cross, the scatter's trunks and field walls, which are
## server bodies with no node, and a house's shell and floors indoors), and each goes in as the
## triangles of its shape. Outdoors the ground is the terrain's heights under the town. The shapes
## are read a slice at a time over frames, and the mesh is baked on a worker thread.
##
## The meshes live on a navigation map of their own, not the world's: a foe steers by the world's
## map whenever it has a region on it (Enemy._setup_navigation), and one in the wild would have been
## routed to the nearest town's streets.

const GROUP := "npc_nav"
## How often the service looks round for a town or a house to stand a mesh over (s).
const INTERVAL := 1.0
## A settlement gets its mesh when the player is within this of its pad (NpcStreamer.NEAR_M, where
## its people are stood up), and it is taken down again past FORGET_M.
const NEAR_M := 240.0
const FORGET_M := 700.0
## Round the pad, the ground the mesh covers (m): gardens and paddocks run out past it.
const MARGIN_M := 25.0
## The terrain's heights are read this far apart for the ground (m), so many rows of them a frame.
const GROUND_STEP_M := 2.0
const GROUND_ROWS_A_FRAME := 12
## A town or a house is given this long after it comes near before its shapes are read (ms): the
## scatter's solids stand over ticks after their cell arrives, and a house builds its shell and
## floors a moment after its root joins the tree.
const SETTLE_MS := 1500
## A house's mesh covers this round its origin (the pocket's houses are 1 km apart).
const INDOOR_HALF_M := 40.0
## Shapes read a frame while a mesh is gathered.
const SHAPES_A_FRAME := 250
## The body the mesh is baked for, in whole cells (Recast rounds to them): the capsule is 0.32, and
## a house's doorway is not much wider than a person.
const CELL_M := 0.15
const CELL_H := 0.15
const AGENT_R := 0.3
const AGENT_H := 1.6
const CLIMB_M := 0.45
const SLOPE_DEG := 42.0
## A point further than this from the mesh is not on it, and gets no path (m, flat / up).
const ON_MESH_M := 1.6
const ON_MESH_UP_M := 2.0

static var instance: NpcNav = null
static var _map := RID()

## owner node's instance id -> {"node", "region", "state": "gathering"/"baking"/"ready", ...}
var _meshes: Dictionary = {}
var _look := PollTimer.new(INTERVAL)
var _busy := false
## node instance id -> when it was first near (ms)
var _near_since: Dictionary = {}
## The longest one square of the ground took to ask about, this mesh (µs).
var _asked_us := 0
## What the last few meshes cost: shapes read, triangles, and milliseconds gathering and baking.
var stats: Array = []


static func ensure() -> NpcNav:
	if instance != null and is_instance_valid(instance) and instance.is_inside_tree():
		return instance
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is NpcNav:
		return found as NpcNav
	var made := NpcNav.new()
	made.name = "NpcNav"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


func _enter_tree() -> void:
	instance = self
	add_to_group(GROUP)


func _exit_tree() -> void:
	for key in _meshes.keys():
		_drop(key)
	if instance == self:
		instance = null
		if _map.is_valid():
			NavigationServer3D.free_rid(_map)
			_map = RID()


func _process(delta: float) -> void:
	if _look.due(delta):
		look_round()


# --- the map and the way through it ------------------------------------------------------------

## The people's own navigation map, made on first use.
static func map() -> RID:
	if not _map.is_valid():
		_map = NavigationServer3D.map_create()
		NavigationServer3D.map_set_cell_size(_map, CELL_M)
		NavigationServer3D.map_set_cell_height(_map, CELL_H)
		NavigationServer3D.map_set_use_edge_connections(_map, false)
		NavigationServer3D.map_set_active(_map, true)
	return _map


## Whether any mesh stands on the map yet, synced.
static func has_mesh() -> bool:
	return _map.is_valid() and not NavigationServer3D.map_get_regions(_map).is_empty() \
			and NavigationServer3D.map_get_iteration_id(_map) > 0


## Whether `at` stands on a mesh (within ON_MESH_M of it).
static func on_mesh(at: Vector3) -> bool:
	if not has_mesh():
		return false
	var c := NavigationServer3D.map_get_closest_point(_map, at)
	return Vector2(c.x - at.x, c.z - at.z).length() <= ON_MESH_M and absf(c.y - at.y) <= ON_MESH_UP_M


## The way from `from` to `to` round what is in the way: its corners, the first where `from` meets
## the mesh and the last the nearest the mesh comes to `to` (which is `to` when it can be reached).
## Empty when `from` is not on a mesh.
static func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not on_mesh(from):
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(_map, from, to, true)


## The nearest point of the mesh to `at`, or `at` when there is no mesh there.
static func nearest_on_mesh(at: Vector3) -> Vector3:
	if not has_mesh():
		return at
	var c := NavigationServer3D.map_get_closest_point(_map, at)
	return c if c.distance_to(at) < 50.0 else at


# --- standing meshes up -------------------------------------------------------------------------

## A town near the player, or the house they are in, without a mesh: one is begun (one at a time).
## A town's mesh far behind them is taken down.
func look_round() -> void:
	var anchor := _anchor()
	if anchor == Vector3.INF:
		return
	for key in _meshes.keys():
		var m: Dictionary = _meshes[key]
		var node: Variant = m.get("node")
		if not is_instance_valid(node):
			_drop(key)
		elif (node as Node).is_in_group("settlement") and _flat((node as Node3D).global_position - anchor) > FORGET_M:
			_drop(key)
			_near_since.erase(key)
	if _busy:
		return
	for n in get_tree().get_nodes_in_group("interior_root"):
		if n is Node3D and not _meshes.has(n.get_instance_id()) and (n as Node3D).global_position.distance_to(anchor) < INDOOR_HALF_M * 2.0:
			if _settled(n):
				stand(n as Node3D)
			return
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("settlement"):
		if not (n is Node3D) or _meshes.has(n.get_instance_id()):
			continue
		var d := _flat((n as Node3D).global_position - anchor) - _pad(n)
		if d < NEAR_M and d < best_d:
			best_d = d
			best = n as Node3D
	if best != null and _settled(best):
		stand(best)


## How far a settlement's pad reaches (m); a stand-in in the group without one, a village's.
static func _pad(node: Node) -> float:
	var r: Variant = node.get("pad_radius")
	return float(r) if r is float or r is int else 40.0


## Whether `node` has been near for SETTLE_MS.
func _settled(node: Node) -> bool:
	var key := node.get_instance_id()
	var now := Time.get_ticks_msec()
	if not _near_since.has(key):
		_near_since[key] = now
	return now - int(_near_since[key]) >= SETTLE_MS


## Gathers and bakes a mesh over `node`: a settlement (its pad and round it) or an interior's root.
## Returns once the shapes are read; the bake finishes on a worker thread and the region joins the
## map when it does (`is_ready`).
func stand(node: Node3D) -> void:
	var key := node.get_instance_id()
	if _meshes.has(key):
		return
	_busy = true
	var outdoors := node.is_in_group("settlement")
	var entry := {"node": node, "region": RID(), "state": "gathering", "name": str(node.name)}
	_meshes[key] = entry
	var t0 := Time.get_ticks_usec()
	var centre := node.global_position
	var half := _pad(node) + MARGIN_M if outdoors else INDOOR_HALF_M
	var ground := centre.y
	var bounds := AABB(centre - Vector3(half, 30.0 if outdoors else 10.0, half), Vector3(half * 2.0, 70.0 if outdoors else 30.0, half * 2.0))
	var source := NavigationMeshSourceGeometryData3D.new()
	_asked_us = 0
	var found: Array = await _shapes_in(node, bounds)
	t0 = Time.get_ticks_usec()
	var read := 0
	var worked := 0
	var worst := 0
	var faces := 0
	for hit: Dictionary in found:
		if not is_instance_valid(node):
			break
		faces += add_shape(source, hit["rid"], int(hit["shape"]))
		read += 1
		if read % SHAPES_A_FRAME == 0:
			worked += Time.get_ticks_usec() - t0
			worst = maxi(worst, Time.get_ticks_usec() - t0)
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()
	if not is_instance_valid(node) or not _meshes.has(key):
		_meshes.erase(key)
		_busy = false
		return
	if outdoors:
		faces += await _add_ground(source, centre, half)
		t0 = Time.get_ticks_usec()
		ground = WorldProbe.get_height(centre.x, centre.z, centre.y)
		bounds = AABB(Vector3(centre.x - half, ground - 20.0, centre.z - half), Vector3(half * 2.0, 60.0, half * 2.0))
	worked += Time.get_ticks_usec() - t0
	worst = maxi(worst, Time.get_ticks_usec() - t0)
	var mesh := make_mesh(bounds)
	entry["state"] = "baking"
	entry["gather_ms"] = worked / 1000.0
	entry["worst_frame_ms"] = maxi(worst, _asked_us) / 1000.0
	entry["shapes"] = read
	entry["triangles"] = faces
	entry["baking_from"] = Time.get_ticks_usec()
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, source, _baked.bind(key, mesh))


func _baked(key: int, mesh: NavigationMesh) -> void:
	# said from the worker's side in some builds: the region joins on the main thread
	_join.call_deferred(key, mesh)


func _join(key: int, mesh: NavigationMesh) -> void:
	_busy = false
	if not _meshes.has(key):
		return
	var entry: Dictionary = _meshes[key]
	if not is_instance_valid(entry.get("node")):
		_meshes.erase(key)
		return
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map())
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	entry["region"] = region
	entry["state"] = "ready"
	entry["bake_ms"] = (Time.get_ticks_usec() - int(entry["baking_from"])) / 1000.0
	entry["polygons"] = mesh.get_polygon_count()
	var row := {"name": entry["name"], "shapes": entry["shapes"], "triangles": entry["triangles"],
			"gather_ms": snappedf(float(entry["gather_ms"]), 0.1), "worst_frame_ms": snappedf(float(entry["worst_frame_ms"]), 0.1),
			"bake_ms": snappedf(float(entry["bake_ms"]), 0.1), "polygons": entry["polygons"]}
	stats.append(row)
	Log.info("NpcNav", "a way round %s: %d shapes, %d triangles, %d polygons (%.1f ms read, %.1f in the worst frame; %.0f ms baked)" % [
			row["name"], row["shapes"], row["triangles"], row["polygons"], row["gather_ms"], row["worst_frame_ms"], row["bake_ms"]])


## Takes `node`'s mesh off the map (a test's yard; a house gone).
func forget(node: Node) -> void:
	if node != null:
		_drop(node.get_instance_id())
	_busy = false


## Whether `node`'s mesh is on the map.
func is_ready(node: Node) -> bool:
	return node != null and str((_meshes.get(node.get_instance_id(), {}) as Dictionary).get("state", "")) == "ready"


func _drop(key: int) -> void:
	var entry: Dictionary = _meshes.get(key, {})
	var region: RID = entry.get("region", RID())
	if region.is_valid():
		NavigationServer3D.free_rid(region)
	_meshes.erase(key)


## The mesh's settings: the body it is for, and the box it is baked in.
static func make_mesh(bounds: AABB) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.cell_size = CELL_M
	mesh.cell_height = CELL_H
	mesh.agent_radius = AGENT_R
	mesh.agent_height = AGENT_H
	mesh.agent_max_climb = CLIMB_M
	mesh.agent_max_slope = SLOPE_DEG
	mesh.region_min_size = 4.0
	mesh.filter_baking_aabb = bounds
	return mesh


## The side of the squares a town's ground is asked about one at a time, a frame each (m).
const TILE_M := 24.0

## Every solid shape in `bounds` (world and scatter layers), each body's shapes once: [{rid, shape}].
## Asked a square of TILE_M at a time, a frame apart: the terrain's own body answers on the world
## layer too, as a heightmap in pieces, thousands under a town, and one query over the whole town
## filled its answer with those before the houses were in it, and cost 127 ms in one frame. Its
## bodies are left out of the squares after the first that names them.
func _shapes_in(node: Node3D, bounds: AABB) -> Array:
	var space := node.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1 | ScatterSolids.LAYER
	q.collide_with_areas = false
	var ground: Array[RID] = []
	var seen := {}
	var out: Array = []
	var nx := maxi(1, int(ceil(bounds.size.x / TILE_M)))
	var nz := maxi(1, int(ceil(bounds.size.z / TILE_M)))
	box.size = Vector3(bounds.size.x / float(nx), bounds.size.y, bounds.size.z / float(nz))
	for j in nz:
		for i in nx:
			if not is_instance_valid(node):
				return out
			q.transform = Transform3D(Basis(), bounds.position + Vector3((float(i) + 0.5) * box.size.x,
					bounds.size.y * 0.5, (float(j) + 0.5) * box.size.z))
			q.exclude = ground
			var t0 := Time.get_ticks_usec()
			for hit: Dictionary in space.intersect_shape(q, 4096):
				var body: RID = hit["rid"]
				var index := int(hit["shape"])
				var key := "%d:%d" % [body.get_id(), index]
				if seen.has(key) or index >= PhysicsServer3D.body_get_shape_count(body):
					continue
				seen[key] = true
				if PhysicsServer3D.shape_get_type(PhysicsServer3D.body_get_shape(body, index)) == PhysicsServer3D.SHAPE_HEIGHTMAP:
					if not ground.has(body):
						ground.append(body)
					continue
				out.append(hit)
			_asked_us = maxi(_asked_us, Time.get_ticks_usec() - t0)
			await get_tree().process_frame
	return out


## Adds one shape of a physics body as triangles; returns how many. A box, a trunk, a rock, a
## house's shell: each as it stands. The terrain's heightmap is left out (the ground is read apart).
static func add_shape(source: NavigationMeshSourceGeometryData3D, body: RID, index: int) -> int:
	if index >= PhysicsServer3D.body_get_shape_count(body):
		return 0
	var shape := PhysicsServer3D.body_get_shape(body, index)
	var at: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
	at = at * PhysicsServer3D.body_get_shape_transform(body, index)
	var data: Variant = PhysicsServer3D.shape_get_data(shape)
	var tris := PackedVector3Array()
	match PhysicsServer3D.shape_get_type(shape):
		PhysicsServer3D.SHAPE_BOX:
			tris = _box_faces(data as Vector3)
		PhysicsServer3D.SHAPE_CYLINDER, PhysicsServer3D.SHAPE_CAPSULE:
			var d: Dictionary = data
			tris = _prism_faces(_circle(float(d["radius"])), -float(d["height"]) * 0.5, float(d["height"]) * 0.5)
		PhysicsServer3D.SHAPE_SPHERE:
			tris = _prism_faces(_circle(float(data)), -float(data), float(data))
		PhysicsServer3D.SHAPE_CONVEX_POLYGON:
			# a rock: the prism of its outline, from its foot to its top, in the world's frame
			var pts: PackedVector3Array = data
			var flat := PackedVector2Array()
			var lo := INF
			var hi := -INF
			for p in pts:
				var w := at * p
				flat.append(Vector2(w.x, w.z))
				lo = minf(lo, w.y)
				hi = maxf(hi, w.y)
			var hull := Geometry2D.convex_hull(flat)
			if hull.size() < 4:
				return 0
			hull.resize(hull.size() - 1)
			var prism := _prism_faces(hull, lo, hi)
			source.add_faces(prism, Transform3D.IDENTITY)
			return int(prism.size() / 3.0)
		PhysicsServer3D.SHAPE_CONCAVE_POLYGON:
			tris = (data as Dictionary).get("faces", PackedVector3Array())
		_:
			return 0
	if tris.is_empty():
		return 0
	source.add_faces(tris, at)
	return int(tris.size() / 3.0)


## The terrain under a town as triangles, GROUND_STEP_M apart.
func _add_ground(source: NavigationMeshSourceGeometryData3D, centre: Vector3, half: float) -> int:
	var n := int(ceil(half * 2.0 / GROUND_STEP_M))
	var x0 := centre.x - half
	var z0 := centre.z - half
	var h := PackedFloat32Array()
	h.resize((n + 1) * (n + 1))
	var t0 := Time.get_ticks_usec()
	for j in n + 1:
		for i in n + 1:
			var x := x0 + float(i) * GROUND_STEP_M
			var z := z0 + float(j) * GROUND_STEP_M
			h[j * (n + 1) + i] = WorldProbe.get_height(x, z, centre.y)
		# a few rows a frame
		if j % GROUND_ROWS_A_FRAME == GROUND_ROWS_A_FRAME - 1:
			_asked_us = maxi(_asked_us, Time.get_ticks_usec() - t0)
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()
	var tris := PackedVector3Array()
	tris.resize(n * n * 6)
	var k := 0
	for j in n:
		for i in n:
			var a := Vector3(x0 + float(i) * GROUND_STEP_M, h[j * (n + 1) + i], z0 + float(j) * GROUND_STEP_M)
			var b := Vector3(a.x + GROUND_STEP_M, h[j * (n + 1) + i + 1], a.z)
			var c := Vector3(a.x, h[(j + 1) * (n + 1) + i], a.z + GROUND_STEP_M)
			var d := Vector3(a.x + GROUND_STEP_M, h[(j + 1) * (n + 1) + i + 1], a.z + GROUND_STEP_M)
			# wound so the face looks up (Recast keeps the faces whose normal is within the slope)
			tris[k] = a
			tris[k + 1] = b
			tris[k + 2] = c
			tris[k + 3] = b
			tris[k + 4] = d
			tris[k + 5] = c
			k += 6
	source.add_faces(tris, Transform3D.IDENTITY)
	return n * n * 2


static func _box_faces(half: Vector3) -> PackedVector3Array:
	var c: Array[Vector3] = []
	for i in 8:
		c.append(Vector3(half.x if i & 1 else -half.x, half.y if i & 2 else -half.y, half.z if i & 4 else -half.z))
	var out := PackedVector3Array()
	# the six sides, two triangles each
	for q: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		out.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	return outward(out, Vector3.ZERO)


## Each triangle turned to face away from `inside`, the way a mesh's faces are wound (clockwise
## seen from the front), so a box's top and a floor are ground to stand on and nothing's underside is.
static func outward(tris: PackedVector3Array, inside: Vector3) -> PackedVector3Array:
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		if (c - a).cross(b - a).dot((a + b + c) / 3.0 - inside) < 0.0:
			tris[i + 1] = c
			tris[i + 2] = b
	return tris


static func _circle(r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 8:
		var a := TAU * float(i) / 8.0
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


## An upright prism over a convex outline (x, z), from `lo` to `hi`: its sides and its top.
static func _prism_faces(outline: PackedVector2Array, lo: float, hi: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := outline.size()
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		out.append_array([Vector3(a.x, lo, a.y), Vector3(b.x, lo, b.y), Vector3(b.x, hi, b.y),
				Vector3(a.x, lo, a.y), Vector3(b.x, hi, b.y), Vector3(a.x, hi, a.y)])
	var mid := Vector2.ZERO
	for i in range(1, n - 1):
		out.append_array([Vector3(outline[0].x, hi, outline[0].y), Vector3(outline[i + 1].x, hi, outline[i + 1].y),
				Vector3(outline[i].x, hi, outline[i].y)])
	for p in outline:
		mid += p / float(n)
	return outward(out, Vector3(mid.x, (lo + hi) * 0.5, mid.y))


## Whoever the people are stood round: the player, or what the world follows.
func _anchor() -> Vector3:
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		return (player as Node3D).global_position
	var world := World.instance
	if world != null and world.target != null:
		return world.target.global_position
	return Vector3.INF


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
