class_name WorldStreamer
extends Node3D
## Loads 256 m cells in rings around a target.
##
## Ring 0 (3x3): full detail -- authored POI scenes, every scatter MultiMesh.
## Ring 1 (5x5): MultiMesh instances only, at reduced density and with shorter LOD ranges.
## Outside: unloaded.
##
## Cell JSON is parsed on a worker thread (they are small but there are up to 25 in flight);
## the scene-tree work happens on the main thread, a bounded number of cells per frame, so a
## fast traversal never stalls the frame. Emits EventBus.cell_loaded / cell_unloaded and tells
## GameState when the target crosses a region boundary.

const GENERATED := "res://world/generated"

@export var cell_size: float = 256.0
@export var full_ring: int = 1                     # 3x3
@export var far_ring: int = 2                      # 5x5
@export var far_density: float = 0.45              # fraction of instances kept in the far ring
@export var cells_per_frame: int = 2
@export var lod_bias_far: float = 0.6
@export var enabled: bool = true

## How far each kind of scatter is worth drawing (metres). A grass tuft is invisible at 80 m
## but still costs a draw call and its share of the primitive budget, so the ranges are what
## keep a forest cell inside DESIGN.md §11 rather than the instance counts alone.
##
## The far-ring numbers are measured from the camera to the cell, and a far-ring cell is
## between 384 m and 905 m away: a range *shorter* than that hides the whole ring. They were,
## which is why a wooded region could be shot from a hilltop and show eight trees. The far
## ring's cost is controlled by `far_density` and by drawing it at a lower LOD, not by a range
## that cuts it off before it begins.
## `herb` reaches 95 m rather than 70: at 70 the ground cover ended in a ring you could see
## from eye height, with bare terrain beyond it and the grass visibly arriving as you walked.
## Herbs are 10 to 12 triangles each, so the extra band costs far less than the trees do --
## but it is not free, and with the cover raised to something that reads as cover, 110 m put
## the village street at 1.56 M primitives against a 1.5 M budget. 95 is where both hold.
const VIEW_RANGE := {"tree": 340.0, "bush": 190.0, "rock": 230.0, "prop": 200.0, "herb": 110.0}
const VIEW_RANGE_FAR := {"tree": 920.0, "bush": 430.0, "rock": 480.0, "prop": 400.0, "herb": 0.0}
## and how much of the far ring is worth keeping, per kind: a wood reads as a wood from a
## kilometre away at a fraction of its stems, and trees are much the most expensive thing in
## the world -- the forge's are seven to fifteen thousand triangles each.
const FAR_KEEP := {"tree": 0.35, "bush": 0.3, "rock": 0.4, "prop": 0.4, "herb": 0.0}

var target: Node3D = null
var provider: TerrainProvider = null
## Whether crossing into another region tells the game the player has arrived there. A camera
## flying the opening over five regions is not a traveller: a region change seeds that region's
## rumours, moves the music and titles the HUD, so a cinematic turns this off while it leads.
var report_regions := true
## Points besides the target whose full-detail ring is wanted too (a cinematic loads its next
## shot while this one plays). Set it with `set_also_around`, which refreshes.
var also_around: Array[Vector3] = []

var _cells_wide: int = 32
var _origin := Vector2(-4096.0, -4096.0)
var _loaded: Dictionary = {}          # Vector2i -> Node3D
var _pending: Dictionary = {}         # Vector2i -> int (ring) awaiting parse
var _parsed: Dictionary = {}          # Vector2i -> Dictionary (data ready to build)
var _tasks: Dictionary = {}           # Vector2i -> task id
var _current_cell := Vector2i(-9999, -9999)
var _current_region := ""
## How often the region under the target is looked at, and how far inside a new region the target
## has to be before it counts as there. The region used to be read only when the target crossed
## into a new streaming cell, with no margin: a walk along a cell edge that lay on a border
## flipped the region -- the light's six-second blend, the music, the name on the screen -- at
## every step over the edge, and a region entered mid-cell was not noticed until the next cell.
const REGION_CHECK_SECONDS := 0.5
const REGION_MARGIN_M := 24.0
## A target that moved further than this between two looks was put somewhere -- a load, fast
## travel, a capture's camera -- rather than walked there, and takes the region it landed in.
const REGION_JUMP_M := 60.0
var _region_timer := 0.0
var _region_checked_at := Vector3.INF
var _missing_assets: Dictionary = {}  # asset path -> true (one warning each)
var _mesh_cache: Dictionary = {}      # asset path -> Mesh or null
var _scene_cache: Dictionary = {}
var _mutex := Mutex.new()


func _ready() -> void:
	set_physics_process(false)
	if provider:
		_cells_wide = int(provider.manifest.get("cells", [32, 32])[0])
		_origin = provider.origin


func setup(p: TerrainProvider, t: Node3D) -> void:
	provider = p
	target = t
	if provider:
		var cells: Array = provider.manifest.get("cells", [32, 32])
		_cells_wide = int(cells[0])
		cell_size = float(provider.manifest.get("cell_size_m", 256))
		_origin = provider.origin
	set_physics_process(true)
	refresh()


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor((pos.x - _origin.x) / cell_size)), int(floor((pos.z - _origin.y) / cell_size)))


func cell_centre(cell: Vector2i) -> Vector2:
	return Vector2(_origin.x + (float(cell.x) + 0.5) * cell_size, _origin.y + (float(cell.y) + 0.5) * cell_size)


func _physics_process(delta: float) -> void:
	if not enabled or target == null or provider == null:
		return
	var cell := cell_of(target.global_position)
	_region_timer -= delta
	if cell != _current_cell:
		_current_cell = cell
		refresh()
		_region_timer = 0.0
	if _region_timer <= 0.0:
		_region_timer = REGION_CHECK_SECONDS
		_check_region()
	_drain_parsed()


## True when every cell of the full-detail ring around the target is loaded.
func is_ring_loaded(ring: int = -1) -> bool:
	if target == null:
		return false
	var r := full_ring if ring < 0 else ring
	var cell := cell_of(target.global_position)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := Vector2i(cell.x + dx, cell.y + dz)
			if not _in_world(c):
				continue
			if not _loaded.has(c):
				return false
	return _pending.is_empty() and _parsed.is_empty()


## True when the full-detail ring around any point is standing: what a cinematic asks before it
## shows a shot, since its camera is somewhere the target has not been yet.
func is_loaded_around(pos: Vector3, ring: int = -1) -> bool:
	var r := full_ring if ring < 0 else ring
	var cell := cell_of(pos)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := Vector2i(cell.x + dx, cell.y + dz)
			if _in_world(c) and not _loaded.has(c):
				return false
	return true


## The cells of the full-detail ring around `pos` that are in the world.
func cells_around(pos: Vector3, ring: int = -1) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := full_ring if ring < 0 else ring
	var cell := cell_of(pos)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := Vector2i(cell.x + dx, cell.y + dz)
			if _in_world(c):
				out.append(c)
	return out


## Those of them not standing yet: what `is_loaded_around` is waiting for.
func missing_around(pos: Vector3, ring: int = -1) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells_around(pos, ring):
		if not _loaded.has(c):
			out.append(c)
	return out


## Where one cell has got to, in words, for a log that has to say why something is waiting.
func cell_state(c: Vector2i) -> String:
	if _loaded.has(c):
		return "standing"
	_mutex.lock()
	var parsed := _parsed.has(c)
	_mutex.unlock()
	if parsed:
		return "read, waiting to be built" if _pending.has(c) else "read, and no longer wanted"
	if _pending.has(c):
		return "being read"
	return "not asked for"


func queue() -> Dictionary:
	_mutex.lock()
	var parsed := _parsed.size()
	_mutex.unlock()
	return {"loaded": _loaded.size(), "pending": _pending.size(), "parsed": parsed}


func set_also_around(points: Array) -> void:
	also_around.clear()
	for p in points:
		if p is Vector3:
			also_around.append(p)
	refresh()


func loaded_count() -> int:
	return _loaded.size()


## Whether one cell's contents are standing in the world yet. Anything waiting on a cell — a
## capture, a test, a tool — should ask this rather than counting frames.
func is_loaded(cell: Vector2i) -> bool:
	return _loaded.has(cell)


func instance_count() -> int:
	var total := 0
	for cell in _loaded:
		var node: Node3D = _loaded[cell]
		for child in node.get_children():
			if child is MultiMeshInstance3D and child.multimesh:
				total += child.multimesh.instance_count
	return total


func refresh() -> void:
	if target == null:
		return
	var cell := cell_of(target.global_position)
	var wanted: Dictionary = {}
	_want_around(wanted, cell, far_ring)
	for p in also_around:
		_want_around(wanted, cell_of(p), full_ring)
	for c in wanted:
		var ring: int = wanted[c]
		if _loaded.has(c):
			# A cell built for the far ring has no grass in it at all (and thinned instances
			# elsewhere), so moving between near and far detail means rebuilding it rather than
			# patching what is there. Between the centre and the rest of the near ring nothing
			# differs, so nothing is rebuilt.
			if (int(_loaded[c].get_meta("ring", 0)) > full_ring) != (ring > full_ring):
				_unload(c)
				_request(c, ring)
			continue
		if _pending.has(c) or _parsed.has(c):
			# built at whatever ring it is wanted at when its data arrives; a cell whose data had
			# arrived after it stopped being wanted is wanted again, not dropped at the drain
			_pending[c] = ring
			continue
		_request(c, ring)
	for c in _loaded.keys():
		if not wanted.has(c):
			_unload(c)
	for c in _pending.keys():
		if not wanted.has(c):
			_pending.erase(c)


## Adds the rings around `centre` to `wanted`, each cell at the nearest ring anything wants it at.
func _want_around(wanted: Dictionary, centre: Vector2i, rings: int) -> void:
	for dz in range(-rings, rings + 1):
		for dx in range(-rings, rings + 1):
			var c := Vector2i(centre.x + dx, centre.y + dz)
			if not _in_world(c):
				continue
			var ring: int = maxi(absi(dx), absi(dz))
			wanted[c] = mini(ring, int(wanted.get(c, ring)))


func _in_world(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _cells_wide and c.y < _cells_wide


func _request(cell: Vector2i, ring: int) -> void:
	_pending[cell] = ring
	var path := "%s/cells/%d_%d.json" % [GENERATED, cell.x, cell.y]
	var task := WorkerThreadPool.add_task(_parse_cell.bind(cell, path), true, "wm_cell_%d_%d" % [cell.x, cell.y])
	_tasks[cell] = task


func _parse_cell(cell: Vector2i, path: String) -> void:
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
	_mutex.lock()
	_parsed[cell] = data
	_mutex.unlock()


func _drain_parsed() -> void:
	var built := 0
	_mutex.lock()
	var ready_cells: Array = _parsed.keys()
	_mutex.unlock()
	for cell in ready_cells:
		if built >= cells_per_frame:
			break
		if not _pending.has(cell):
			_mutex.lock()
			_parsed.erase(cell)
			_mutex.unlock()
			_finish_task(cell)
			continue
		_mutex.lock()
		var data: Dictionary = _parsed[cell]
		_parsed.erase(cell)
		_mutex.unlock()
		var ring: int = int(_pending[cell])
		_pending.erase(cell)
		_finish_task(cell)
		_build_cell(cell, ring, data)
		built += 1


func _finish_task(cell: Vector2i) -> void:
	if _tasks.has(cell):
		WorkerThreadPool.wait_for_task_completion(int(_tasks[cell]))
		_tasks.erase(cell)


func _build_cell(cell: Vector2i, ring: int, data: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Cell_%d_%d" % [cell.x, cell.y]
	var centre := cell_centre(cell)
	node.position = Vector3(centre.x, 0.0, centre.y)
	node.set_meta("ring", ring)
	node.set_meta("region", str(data.get("region", "")))
	add_child(node)
	_loaded[cell] = node
	# the furniture of the roads and the field walls: signposts, gates and drystone runs are
	# built rather than scattered (world/wayside.gd)
	var instances: Dictionary = Wayside.prepare(data.get("instances", {}), node, ring <= full_ring)
	for asset_path in instances:
		var rows: Array = instances[asset_path]
		if rows.is_empty():
			continue
		var mesh := _mesh_for(str(asset_path), ring)
		if mesh == null:
			continue
		_build_multimesh(node, str(asset_path), mesh, rows, ring)
	# A landmark is the one thing that has to be visible from outside the near ring -- a
	# hundred-and-twenty-metre spire in a marsh is a skyline, and the shot that shows it stands
	# 360 m off, which is often the far ring. There are thirty-four POIs in the whole world, so
	# building them out to the edge of what is streamed costs almost nothing. Encounters stay
	# near: a wolf you cannot see does not need a body.
	for entry in data.get("scenes", []):
		_build_scene(node, entry)
	# What stands at the points of interest in this cell is raised here, from the POI data,
	# and hangs off the cell node so it streams and unloads with the ring; the far ring gets
	# silhouettes only. See world/pois/world_pois.gd.
	# the group name as a literal, not `WorldPois.GROUP`: `PoiKit` reads this class's mesh and
	# transform helpers, so naming the type here closes a cycle that makes GDScript fail to
	# resolve one end of it — and it failed on the test file rather than on either script,
	# which is a parse error a long way from its cause
	var pois := get_tree().get_first_node_in_group("world_pois") if is_inside_tree() else null
	if pois != null and pois.has_method("raise_in_cell"):
		pois.call("raise_in_cell", node, cell, ring > full_ring)
	if ring <= full_ring:
		_build_spawns(node, data.get("spawns", []))
	EventBus.cell_loaded.emit(cell)


## What is standing in this cell waiting for you. Only the near ring: a wolf three hundred
## metres away that you cannot see does not need a body, and it gets one the moment the cell
## comes into the full-detail ring. They hang off the cell node, so unloading takes them with
## it and the world does not fill up with everything you have ever walked past.
func _build_spawns(parent: Node3D, spawns: Array) -> void:
	if spawns.is_empty():
		return
	var spawner := EnemySpawner.new()
	spawner.name = "Encounters"
	spawner.spawn_on_ready = false
	spawner.respawn_on_rest = true
	spawner.drop_to_ground = false
	parent.add_child(spawner)
	for entry in spawns:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var spawn: Dictionary = entry
		if str(spawn.get("kind", "enemy")) != "enemy":
			continue          # npc and animal spawns belong to their own systems
		var def_id := str(spawn.get("def", ""))
		if def_id == "" or not ContentDB.has(def_id):
			continue
		var p: Array = spawn.get("pos", [])
		if p.size() < 3:
			continue
		var at := Vector3(float(p[0]), float(p[1]), float(p[2]))
		# The builder samples the ground at full resolution and the runtime reads a quarter-res
		# copy, so on a slope the two disagree by a few metres. The ground under your feet is
		# the one that counts: ask it rather than trusting what was written down.
		var provider := World.terrain()
		if provider != null:
			at.y = provider.get_height(at.x, at.z)
		spawner.spawn_one(def_id, at, deg_to_rad(float(spawn.get("yaw", 0.0))),
				{"group": str(spawn.get("group", ""))})


func _build_multimesh(parent: Node3D, asset_path: String, mesh: Mesh, rows: Array, ring: int) -> void:
	var keep := rows.size()
	if ring > full_ring:
		var kind := asset_kind(asset_path)
		keep = int(ceil(float(rows.size()) * float(FAR_KEEP.get(kind, far_density))))
	if keep <= 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = keep
	var origin3 := parent.position
	var step := float(rows.size()) / float(keep)
	for i in keep:
		var row: Array = rows[int(floor(float(i) * step))]
		mm.set_instance_transform(i, instance_transform(row, origin3))
		mm.set_instance_color(i, instance_tint(row))
	var kind := asset_kind(asset_path)
	var range_end: float = float(VIEW_RANGE.get(kind, 220.0)) if ring <= full_ring \
		else float(VIEW_RANGE_FAR.get(kind, 160.0))
	if range_end <= 0.0:
		return                                   # not worth drawing this far out at all
	var mmi := MultiMeshInstance3D.new()
	mmi.name = asset_path.get_file().get_basename()
	mmi.set_meta("asset_path", asset_path)
	mmi.multimesh = mm
	# only trees and rocks in the near ring cast shadows; grass shadows cost more than they show
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
		if (ring <= full_ring and kind in ["tree", "rock", "prop"]) \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = range_end
	mmi.visibility_range_end_margin = range_end * 0.15
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.lod_bias = 1.0 if ring <= full_ring else lod_bias_far
	parent.add_child(mmi)


## A scatter row is [x, y, z, yaw_deg, scale, tint_hex] in world metres (CONTRACTS §6), and
## optionally two more, [.., lean_deg, lean_toward_deg]: a tree the wind has bent, tipped
## `lean_deg` from upright toward the ground direction (cos, sin) of `lean_toward_deg` in x, z.
## A six-field row stands upright, so every cell written before the lean existed reads as it did.
## MultiMesh instances are stored relative to their cell node so the transforms stay small. A row
## `Wayside` has fitted into a run carries instead a seventh entry that is an array, [sx, sy, sz],
## a scale in the asset's own axes that replaces the uniform one (and it has no lean).
static func instance_transform(row: Array, cell_origin: Vector3) -> Transform3D:
	var pos := Vector3(float(row[0]), float(row[1]), float(row[2])) - cell_origin
	var yaw := deg_to_rad(float(row[3])) if row.size() > 3 else 0.0
	if row.size() > 6 and typeof(row[6]) == TYPE_ARRAY and (row[6] as Array).size() == 3:
		var s: Array = row[6]
		return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(float(s[0]), float(s[1]), float(s[2]))), pos)
	var scale := float(row[4]) if row.size() > 4 else 1.0
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
	if row.size() > 7 and float(row[6]) != 0.0:
		var toward := deg_to_rad(float(row[7]))
		var dir := Vector3(cos(toward), 0.0, sin(toward))
		# rotating about UP x dir carries the trunk's top toward dir
		b = Basis(Vector3.UP.cross(dir).normalized(), deg_to_rad(float(row[6]))) * b
	return Transform3D(b, pos)


static func instance_tint(row: Array) -> Color:
	if row.size() > 5:
		return Color.from_string(str(row[5]), Color.WHITE)
	return Color.WHITE


func _build_scene(parent: Node3D, entry: Variant) -> void:
	if typeof(entry) != TYPE_DICTIONARY:
		return
	var path := str(entry.get("scene", ""))
	if path.is_empty():
		return
	var packed := _scene_for(path)
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	if inst is Node3D:
		var pos: Array = entry.get("pos", [0, 0, 0])
		var node3d: Node3D = inst
		node3d.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2])) - parent.position
		node3d.rotation.y = deg_to_rad(float(entry.get("yaw", 0.0)))
	var props: Dictionary = entry.get("props", {})
	if not props.is_empty() and inst.has_method("configure"):
		inst.call("configure", props)
	parent.add_child(inst)
	_add_collision(inst, str(entry.get("collision", "")))


## A landmark you can walk through is worse than a landmark that is not there. The forge builds
## a separate low-triangle collision mesh beside each landmark and names it in its meta file,
## which the world builder copies into the cell entry; here it becomes a static body under the
## instance. Building it from the visible mesh instead would put ten thousand triangles into
## the physics world for something you mostly walk around.
func _add_collision(inst: Node, path: String) -> void:
	if path.is_empty() or not (inst is Node3D):
		return
	if not ResourceLoader.exists(path):
		if not _missing_assets.has(path):
			_missing_assets[path] = true
			Log.warn("WorldStreamer", "landmark collision missing, skipping: %s" % path)
		return
	var packed: PackedScene = load(path)
	if packed == null:
		return
	var source: Node = packed.instantiate()
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shapes := 0
	for m in source.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (m as MeshInstance3D).mesh
		if mesh == null:
			continue
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		# `source` is never in the tree, so its meshes have no global transform to read;
		# compose the local transforms up to the collision scene's root instead.
		shape.transform = _transform_within(m as Node3D, source)
		body.add_child(shape)
		shapes += 1
	source.queue_free()
	if shapes == 0:
		body.queue_free()
		return
	(inst as Node3D).add_child(body)


## A node's transform relative to `root`, for scenes that are not (and will not be) in the
## tree: `global_transform` errors there and returns identity, which silently put every
## landmark's collision at the landmark's origin.
static func _transform_within(node: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## The kind of thing an asset is, from where the forge files it. Scatter rules put trees in
## models/trees, foliage in models/flora, rocks in models/rocks and everything else in props.
static func asset_kind(asset_path: String) -> String:
	if asset_path.contains("/trees/"):
		return "tree"
	if asset_path.contains("/rocks/"):
		return "rock"
	if asset_path.contains("/props/"):
		return "prop"
	for bush in ["briar", "juniper", "hawthorn", "bush"]:
		if asset_path.contains(bush):
			return "bush"
	return "herb"


func _unload(cell: Vector2i) -> void:
	var node: Node3D = _loaded.get(cell, null)
	if node:
		node.queue_free()
	_loaded.erase(cell)
	EventBus.cell_unloaded.emit(cell)


## Loads the mesh for a scatter asset, warning exactly once per missing asset.
## The mesh to draw one of these with, at the detail this ring deserves.
##
## The forge builds every scatter asset with LOD1 and LOD2 meshes beside the full one, named
## after it. A tree is about 150 triangles at LOD0 and a fifth of that at LOD2, and a tree
## three hundred metres away across a valley is four pixels tall, so the far ring takes the
## cheap one. That is what buys the Briarwold its density: the budget is spent on the wood you
## are standing in rather than on the one on the far hill.
func _mesh_for(asset_path: String, ring: int = 0) -> Mesh:
	# Only the cell you are standing in gets the full mesh. The eight around it are already
	# a hundred metres away, where the difference between fifteen thousand triangles and five
	# is a tree you cannot tell apart, and there are eight times as many of them.
	# Godot's own per-surface mesh LODs do the distance work inside a MultiMesh, and the
	# forge's LOD0 is a single mesh carrying every material of the asset. So the near rings
	# take the full mesh and let the renderer decimate it; only the far ring, which is past
	# 384 m and where a stem is a couple of pixels, asks for a cheaper rung explicitly.
	var want_lod := 0 if ring <= full_ring else 2
	var key := "%s#%d" % [asset_path, want_lod]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh: Mesh = null
	if ResourceLoader.exists(asset_path):
		var res: Resource = load(asset_path)
		if res is Mesh:
			mesh = res
		elif res is PackedScene:
			mesh = _mesh_of(res, want_lod)
	if mesh == null and not _missing_assets.has(asset_path):
		_missing_assets[asset_path] = true
		Log.warn("WorldStreamer", "scatter asset missing, skipping: %s" % asset_path)
	_mesh_cache[key] = mesh
	return mesh


## The cheapest mesh in the scene that is still worth drawing, for a far-ring instance; the
## full one for the near ring.
##
## LOD ladders arrive in whatever shape the generator gave them, and not every rung is usable:
## some of the forge's trees collapse to four triangles at LOD2, which is not a distant tree,
## it is nothing. So a rung is only taken if it still has a silhouette, and otherwise the next
## one up is used. Falling back rather than failing matters -- a missing LOD should cost
## triangles, not a bald hillside.
const MIN_LOD_TRIS := 12


static func _tri_count(mesh: Mesh) -> int:
	var am := mesh as ArrayMesh
	if am == null:
		return MIN_LOD_TRIS          # not an ArrayMesh: assume it is worth drawing
	var tris := 0
	for si in am.get_surface_count():
		var n := am.surface_get_array_index_len(si)
		if n == 0:
			n = am.surface_get_array_len(si)
		tris += n / 3
	return tris


static func _mesh_of(packed: PackedScene, want_lod: int) -> Mesh:
	var state := packed.get_state()
	var full: Mesh = null
	var by_lod: Dictionary = {}
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
				by_lod[int(node_name.substr(at + 4).to_int())] = v
	if want_lod <= 0:
		if full != null:
			return full
		return by_lod.get(1, by_lod.values()[0] if not by_lod.is_empty() else null)
	# walk down from the wanted rung to the full mesh, taking the first that still has a shape
	var rungs: Array = by_lod.keys()
	rungs.sort()
	rungs.reverse()
	for lod in rungs:
		if lod > want_lod:
			continue
		var m: Mesh = by_lod[lod]
		if _tri_count(m) >= MIN_LOD_TRIS:
			return m
	return full


func _scene_for(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	var packed: PackedScene = null
	if ResourceLoader.exists(path):
		packed = load(path)
	elif not _missing_assets.has(path):
		_missing_assets[path] = true
		Log.warn("WorldStreamer", "POI scene missing, skipping: %s" % path)
	_scene_cache[path] = packed
	return packed


func _check_region() -> void:
	if provider == null or target == null or not report_regions:
		return
	var pos := target.global_position
	var jumped := _region_checked_at == Vector3.INF or pos.distance_to(_region_checked_at) > REGION_JUMP_M
	_region_checked_at = pos
	var id := provider.region_id_at(pos.x, pos.z)
	if id.is_empty():
		# Over open water a walk (or a swim) stays in the region it came from. The nearest shore
		# is a search that can land either side of a strait: off the Hushline Stair, where a new
		# game begins on a patch of Cinderlea in open water, it finds Sedgemire's and
		# Brightwater's coasts from spots a hundred metres out. A target put down on the water
		# takes the nearest shore's.
		if not jumped and not _current_region.is_empty():
			return
		id = provider.nearest_region_id_at(pos.x, pos.z)
	if id.is_empty() or id == _current_region:
		return
	if not jumped and not region_entered_at(pos, id):
		return
	_current_region = id
	GameState.enter_region(id)


## Whether a walk to `pos` has taken the target far enough inside region `id` to count as having
## entered it: the first region of all is taken at once, and any other only once no land of
## another region lies within REGION_MARGIN_M, so a border has a band either side of it where
## nothing changes. (A target put down somewhere takes its region at once: REGION_JUMP_M.)
func region_entered_at(pos: Vector3, id: String) -> bool:
	if _current_region.is_empty():
		return true
	for k in 4:
		var a := TAU * float(k) / 4.0
		var there := provider.region_id_at(pos.x + cos(a) * REGION_MARGIN_M, pos.z + sin(a) * REGION_MARGIN_M)
		# open water beside you is nobody's; land of another region is not yet behind you
		if not there.is_empty() and there != id:
			return false
	return true


func unload_all() -> void:
	for cell in _loaded.keys():
		_unload(cell)
	_pending.clear()
	for cell in _tasks.keys():
		_finish_task(cell)
	_parsed.clear()


func _exit_tree() -> void:
	for cell in _tasks.keys():
		_finish_task(cell)
