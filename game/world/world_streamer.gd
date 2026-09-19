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

var target: Node3D = null
var provider: TerrainProvider = null

var _cells_wide: int = 32
var _origin := Vector2(-4096.0, -4096.0)
var _loaded: Dictionary = {}          # Vector2i -> Node3D
var _pending: Dictionary = {}         # Vector2i -> int (ring) awaiting parse
var _parsed: Dictionary = {}          # Vector2i -> Dictionary (data ready to build)
var _tasks: Dictionary = {}           # Vector2i -> task id
var _current_cell := Vector2i(-9999, -9999)
var _current_region := ""
var _missing_assets: Dictionary = {}  # asset path -> true (one warning each)
var _mesh_cache: Dictionary = {}      # asset path -> Mesh or null
var _scene_cache: Dictionary = {}
var _ready_for_target := false
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
	_ready_for_target = true
	set_physics_process(true)
	refresh()


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor((pos.x - _origin.x) / cell_size)), int(floor((pos.z - _origin.y) / cell_size)))


func cell_centre(cell: Vector2i) -> Vector2:
	return Vector2(_origin.x + (float(cell.x) + 0.5) * cell_size, _origin.y + (float(cell.y) + 0.5) * cell_size)


func _physics_process(_delta: float) -> void:
	if not enabled or target == null or provider == null:
		return
	var cell := cell_of(target.global_position)
	if cell != _current_cell:
		_current_cell = cell
		refresh()
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


func loaded_count() -> int:
	return _loaded.size()


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
	for dz in range(-far_ring, far_ring + 1):
		for dx in range(-far_ring, far_ring + 1):
			var c := Vector2i(cell.x + dx, cell.y + dz)
			if not _in_world(c):
				continue
			var ring: int = maxi(absi(dx), absi(dz))
			wanted[c] = ring
	for c in wanted:
		var ring: int = wanted[c]
		if _loaded.has(c):
			var node: Node3D = _loaded[c]
			if int(node.get_meta("ring", 0)) != ring:
				node.set_meta("ring", ring)
				_apply_ring(node, ring)
			continue
		if _pending.has(c) or _parsed.has(c):
			continue
		_request(c, ring)
	for c in _loaded.keys():
		if not wanted.has(c):
			_unload(c)
	for c in _pending.keys():
		if not wanted.has(c):
			_pending.erase(c)


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
	var instances: Dictionary = data.get("instances", {})
	for asset_path in instances:
		var rows: Array = instances[asset_path]
		if rows.is_empty():
			continue
		var mesh := _mesh_for(str(asset_path))
		if mesh == null:
			continue
		_build_multimesh(node, str(asset_path), mesh, rows, ring)
	if ring <= full_ring:
		for entry in data.get("scenes", []):
			_build_scene(node, entry)
	EventBus.cell_loaded.emit(cell)


func _build_multimesh(parent: Node3D, asset_path: String, mesh: Mesh, rows: Array, ring: int) -> void:
	var keep := rows.size()
	if ring > full_ring:
		keep = int(ceil(float(rows.size()) * far_density))
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
		var pos := Vector3(float(row[0]), float(row[1]), float(row[2])) - origin3
		var yaw := deg_to_rad(float(row[3]))
		var scale := float(row[4])
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		var tint := Color.WHITE
		if row.size() > 5:
			tint = Color.from_string(str(row[5]), Color.WHITE)
		mm.set_instance_color(i, tint)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = asset_path.get_file().get_basename()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if ring <= full_ring \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = (cell_size * 3.0) if ring <= full_ring else (cell_size * 2.2)
	mmi.visibility_range_end_margin = cell_size * 0.35
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.lod_bias = 1.0 if ring <= full_ring else lod_bias_far
	parent.add_child(mmi)


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


func _apply_ring(node: Node3D, ring: int) -> void:
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = child
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if ring <= full_ring \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.lod_bias = 1.0 if ring <= full_ring else lod_bias_far


func _unload(cell: Vector2i) -> void:
	var node: Node3D = _loaded.get(cell, null)
	if node:
		node.queue_free()
	_loaded.erase(cell)
	EventBus.cell_unloaded.emit(cell)


## Loads the mesh for a scatter asset, warning exactly once per missing asset.
func _mesh_for(asset_path: String) -> Mesh:
	if _mesh_cache.has(asset_path):
		return _mesh_cache[asset_path]
	var mesh: Mesh = null
	if ResourceLoader.exists(asset_path):
		var res: Resource = load(asset_path)
		if res is Mesh:
			mesh = res
		elif res is PackedScene:
			mesh = _first_mesh_of(res)
	if mesh == null and not _missing_assets.has(asset_path):
		_missing_assets[asset_path] = true
		Log.warn("WorldStreamer", "scatter asset missing, skipping: %s" % asset_path)
	_mesh_cache[asset_path] = mesh
	return mesh


static func _first_mesh_of(packed: PackedScene) -> Mesh:
	var state := packed.get_state()
	for i in state.get_node_count():
		if state.get_node_type(i) != "MeshInstance3D":
			continue
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == "mesh":
				var v: Variant = state.get_node_property_value(i, p)
				if v is Mesh:
					return v
	return null


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
	if provider == null or target == null:
		return
	var pos := target.global_position
	var id := provider.nearest_region_id_at(pos.x, pos.z)
	if id.is_empty() or id == _current_region:
		return
	_current_region = id
	GameState.enter_region(id)


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
