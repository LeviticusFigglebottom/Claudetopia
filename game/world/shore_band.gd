class_name ShoreBand
extends Node3D
## The water's edge on the land: the swash that runs up a beach and draws back, its line of foam,
## and the band of sand and stone it leaves dark and glossy above the still water. The lake sheet
## ends at the waterline; what happens above the line is on the ground, so it is drawn on the
## ground: a thin mesh laid a few centimetres over it in the band where it stands within a metre
## or so of its water's level, near the eye (world/shore_band.gdshader does the rest).
##
## The shore is found from the runtime maps once (cells of CELL_M with a wet texel beside a dry
## one on still water: a lake, the marsh's pools or the sea); the cells within REACH_M of the eye
## are sampled on the ground Terrain3D draws, two metres apart, and kept while they are near. All
## of them are one mesh, one draw, rebuilt only when a cell comes or goes.

const CELL_M := 64.0
const REACH_M := 150.0
const STEP_M := 2.0
## The band: from this far under the still water (so it meets the sheet with no gap) to this far
## above it (the highest the swash and the spray reach, on the sea).
const BELOW_M := 0.3
const ABOVE_M := 1.4
const LIFT_M := 0.04
## Cells built in a frame at most; the rest wait their turn.
const BUILDS_PER_FRAME := 2

var provider: TerrainProvider = null
var material: ShaderMaterial = null
var mesh_instance: MeshInstance3D = null
var _shore_cells: Dictionary = {}     # Vector2i -> true
var _built: Dictionary = {}           # Vector2i -> [verts, normals] (PackedVector3Array x2), or [] if none
var _live: Array[Vector2i] = []
var _dirty := false
var _eye := Vector3(INF, 0.0, INF)
var _still_levels: Array[float] = []


func setup(p: TerrainProvider, level_tex: Texture2D, shore_tex: Texture2D) -> void:
	provider = p
	_find_shore()
	material = ShaderMaterial.new()
	material.shader = load("res://assets/shaders/shore_band.gdshader")
	material.set_shader_parameter("level_tex", level_tex)
	material.set_shader_parameter("world_origin", provider.origin)
	material.set_shader_parameter("world_size", provider.size_m)
	material.set_shader_parameter("sea_level", provider.sea_level)
	if shore_tex != null:
		material.set_shader_parameter("shore_tex", shore_tex)
		material.set_shader_parameter("has_shore", true)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "ShoreBand"
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)


func shore_cells() -> int:
	return _shore_cells.size()


func _find_shore() -> void:
	_shore_cells.clear()
	if provider == null or not provider.has_runtime_maps():
		return
	_still_levels = [provider.sea_level]
	for lake in provider.manifest.get("lakes", []):
		_still_levels.append(float((lake as Dictionary).get("level_m", -9999.0)))
	var g := provider.runtime_grid()
	var s := provider.runtime_spacing()
	var water := provider.runtime_water()
	var levels := provider.runtime_levels()
	if water.size() < g * g or levels.size() < g * g:
		return
	for iz in range(1, g - 1):
		for ix in range(1, g - 1):
			var i := iz * g + ix
			if water[i] == 0:
				continue
			if water[i - 1] != 0 and water[i + 1] != 0 and water[i - g] != 0 and water[i + g] != 0:
				continue
			if not _is_still(levels[i]):
				continue
			var x := provider.origin.x + float(ix) * s
			var z := provider.origin.y + float(iz) * s
			# the cell it is in and, since the band reaches past it, the ones it borders on
			for dz in [-s, 0.0, s]:
				for dx in [-s, 0.0, s]:
					_shore_cells[Vector2i(floori((x + dx) / CELL_M), floori((z + dz) / CELL_M))] = true


func _is_still(level: float) -> bool:
	for l in _still_levels:
		if absf(level - l) < 0.3:
			return true
	return false


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	update(cam.global_position)


## Brings the band round `eye` in, a couple of cells a call, and drops what fell out of reach.
func update(eye: Vector3) -> void:
	if provider == null:
		return
	var moved := Vector2(eye.x - _eye.x, eye.z - _eye.z).length() > 8.0
	if moved:
		_eye = eye
		var want: Array[Vector2i] = []
		var r := int(ceil(REACH_M / CELL_M))
		var here := Vector2i(floori(eye.x / CELL_M), floori(eye.z / CELL_M))
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := here + Vector2i(dx, dz)
				if not _shore_cells.has(c):
					continue
				var centre := Vector2((float(c.x) + 0.5) * CELL_M, (float(c.y) + 0.5) * CELL_M)
				if centre.distance_to(Vector2(eye.x, eye.z)) <= REACH_M + CELL_M * 0.72:
					want.append(c)
		if want != _live:
			_live = want
			_dirty = true
	var built := 0
	for c in _live:
		if not _built.has(c):
			if built >= BUILDS_PER_FRAME:
				break
			_built[c] = _build_cell(c)
			built += 1
			_dirty = true
	# forget cells far behind, so a long walk does not hold the whole coast
	if _built.size() > 96:
		for c in _built.keys():
			if not _live.has(c):
				_built.erase(c)
	if _dirty:
		_rebuild()


func _build_cell(c: Vector2i) -> Array:
	var n := int(CELL_M / STEP_M)
	var x0 := float(c.x) * CELL_M
	var z0 := float(c.y) * CELL_M
	var hs := PackedFloat32Array()
	var ls := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	ls.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := x0 + float(i) * STEP_M
			var z := z0 + float(j) * STEP_M
			hs[j * (n + 1) + i] = provider.get_height(x, z)
			ls[j * (n + 1) + i] = provider.nearest_water_level(x, z)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for j in n:
		for i in n:
			var k := [j * (n + 1) + i, j * (n + 1) + i + 1, (j + 1) * (n + 1) + i, (j + 1) * (n + 1) + i + 1]
			var inside: Array[bool] = []
			for q in k:
				var rise := hs[q] - ls[q]
				inside.append(rise > -BELOW_M and rise < ABOVE_M and _is_still(ls[q]))
			if not (inside[0] or inside[1] or inside[2] or inside[3]):
				continue
			var p: Array[Vector3] = []
			for q in k:
				var qi: int = q % (n + 1)
				var qj: int = floori(float(q) / float(n + 1))
				p.append(Vector3(x0 + float(qi) * STEP_M, hs[q] + LIFT_M, z0 + float(qj) * STEP_M))
			var nrm := (p[2] - p[0]).cross(p[1] - p[0]).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			for tri in [[0, 2, 1], [1, 2, 3]]:
				if not (inside[tri[0]] or inside[tri[1]] or inside[tri[2]]):
					continue
				for idx in tri:
					verts.append(p[idx])
					normals.append(nrm)
	return [verts, normals]


func _rebuild() -> void:
	_dirty = false
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for c in _live:
		var part: Array = _built.get(c, [])
		if part.is_empty():
			continue
		verts.append_array(part[0])
		normals.append_array(part[1])
	if verts.is_empty():
		mesh_instance.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = m


## Triangles drawn now (for tests and the budget).
func triangles() -> int:
	if mesh_instance == null or mesh_instance.mesh == null:
		return 0
	return int((mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3.0)
