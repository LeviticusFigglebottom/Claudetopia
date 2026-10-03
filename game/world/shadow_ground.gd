class_name ShadowGround
extends Node3D
## The ground's shadow caster: the land round the camera from the runtime 8 m height map, drawn
## only into the sun's shadow, in place of Terrain3D's own clipmap.
##
## Terrain3D 1.0.2 casts with the meshes it draws -- every ring of a clipmap reaching 12 km, drawn
## again into each of the sun's four cascades -- and has no coarser shadow mesh of its own. That was
## 0.49-0.53 M primitives of a Greatwood frame (attribution at the Windthrow, Tinehold and the
## Name-Wife's Hollow, w4096j), most of it the shadow passes. What a hill's shadow needs is the
## hill, not its 2 m relief, so Terrain3D casts nothing and this does: world-aligned chunks of
## CHUNK_TEXELS x CHUNK_TEXELS texels (192 m), RADIUS chunks each way round the camera, built a few a
## frame as the camera moves, so they never swim and never hitch.
##
## Every vertex is the lowest of its texel and the four beside it, less SINK_M: the caster never
## stands above the real ground, so it puts no false shadow in a hollow the 8 m map smooths over.
## What it gives up is the self-shadow of relief under about 8 m (a bank's own shadow at your feet);
## the land's normals still shade every slope by the sun.
##
## `-- --no-shadow-ground` casts with Terrain3D as before, for an A/B (World reads it).

const CHUNK_TEXELS := 24
const RADIUS := 3
const SINK_M := 0.5
const BUILD_PER_FRAME := 2
const ARG_OFF := "--no-shadow-ground"

var provider: TerrainProvider = null
var _chunks: Dictionary = {}          # Vector2i -> MeshInstance3D
var _material: StandardMaterial3D = null


static func enabled() -> bool:
	return not OS.get_cmdline_user_args().has(ARG_OFF)


func _init(p: TerrainProvider = null) -> void:
	provider = p
	name = "ShadowGround"


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# the sun may be low enough to see a slope's underside from the side it casts from
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _process(_delta: float) -> void:
	if provider == null or not provider.has_runtime_maps():
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return
	update_around(cam.global_position, BUILD_PER_FRAME)


## Keeps the chunks within RADIUS of `eye` and lets go of the rest; builds at most `budget` new ones
## (all of them for 0). Returns how many are still to build.
func update_around(eye: Vector3, budget: int = 0) -> int:
	var span := float(CHUNK_TEXELS) * provider.runtime_spacing()
	var origin := provider.height_origin()
	var at := Vector2i(floori((eye.x - origin.x) / span), floori((eye.z - origin.y) / span))
	for key in _chunks.keys():
		var k: Vector2i = key
		if absi(k.x - at.x) > RADIUS + 1 or absi(k.y - at.y) > RADIUS + 1:
			(_chunks[k] as Node).queue_free()
			_chunks.erase(k)
	var wanted: Array[Vector2i] = []
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var k := at + Vector2i(dx, dz)
			if not _chunks.has(k):
				wanted.append(k)
	# nearest first
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - at).length_squared() < (b - at).length_squared())
	var built := 0
	for k in wanted:
		if budget > 0 and built >= budget:
			break
		_chunks[k] = _build_chunk(k)
		built += 1
	return wanted.size() - built


func chunk_count() -> int:
	return _chunks.size()


func _build_chunk(k: Vector2i) -> MeshInstance3D:
	var grid := provider.runtime_grid()
	var heights := provider.runtime_heights()
	var spacing := provider.runtime_spacing()
	var origin := provider.height_origin()
	var n := CHUNK_TEXELS + 1
	var verts := PackedVector3Array()
	verts.resize(n * n)
	var x0 := k.x * CHUNK_TEXELS
	var z0 := k.y * CHUNK_TEXELS
	for j in n:
		for i in n:
			var gx := clampi(x0 + i, 0, grid - 1)
			var gz := clampi(z0 + j, 0, grid - 1)
			var h := heights[gz * grid + gx]
			h = minf(h, heights[gz * grid + clampi(gx - 1, 0, grid - 1)])
			h = minf(h, heights[gz * grid + clampi(gx + 1, 0, grid - 1)])
			h = minf(h, heights[clampi(gz - 1, 0, grid - 1) * grid + gx])
			h = minf(h, heights[clampi(gz + 1, 0, grid - 1) * grid + gx])
			verts[j * n + i] = Vector3(origin.x + float(x0 + i) * spacing, h - SINK_M,
					origin.y + float(z0 + j) * spacing)
	var idx := PackedInt32Array()
	idx.resize(CHUNK_TEXELS * CHUNK_TEXELS * 6)
	var o := 0
	for j in CHUNK_TEXELS:
		for i in CHUNK_TEXELS:
			var a := j * n + i
			idx[o] = a
			idx[o + 1] = a + 1
			idx[o + 2] = a + n
			idx[o + 3] = a + 1
			idx[o + 4] = a + n + 1
			idx[o + 5] = a + n
			o += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [k.x, k.y]
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	return mi
