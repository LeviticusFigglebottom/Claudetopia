class_name TerrainProvider
extends Node
## The one place the rest of the game asks about the ground.
##
## Heights and normals come from Terrain3D when it is present (exact, full resolution); the
## region mask, the water mask and water levels come from the small runtime copies the world
## builder writes beside the big maps (`runtime/*_1024.*`), so region and water queries cost
## one array lookup and work even with no terrain node at all (tests, tools, servers).
##
## Coordinates are world metres: x east, z south, y up (docs/CONTRACTS.md §1).

const GENERATED := "res://world/generated"
const OPEN_WATER := 255
const NO_WATER := -1000.0

var manifest: Dictionary = {}
var size_m: float = 8192.0
var origin := Vector2(-4096.0, -4096.0)
var lake_level: float = 8.0
var sea_level: float = 0.0
var region_ids: Array[String] = []

var _terrain: Node3D = null
var _data: Object = null
var _fallback: Node3D = null
var _grid: int = 0
var _spacing: float = 8.0
## Where the height map's texel (0, 0) stands. The region, water and level maps are point samples
## of the full grid and sit on the origin; the height map is a block mean of `factor x factor`
## full texels (tools/world/worldgen/noise.downsample), so each of its texels is centred half a
## block further on: 3 m east and 3 m south at a 4096 grid and a 1024 runtime copy. Reading it
## as though it stood on the origin put every runtime height 3 m out in both directions, which is
## more than a metre of error on 37% of the land and more than three metres on 11% of it.
var _height_origin := Vector2(-4096.0, -4096.0)
## Heights answered on the same two triangles per 8 m quad as the fallback ground's mesh and its
## HeightMapShape3D (diagonal from (x+1, z) to (x, z+1)), instead of bilinearly, so that where a
## body stands, what it collides with and what is drawn under it are one surface.
var _triangles := false
var _heights := PackedFloat32Array()
var _regions := PackedByteArray()
var _water := PackedByteArray()
var _levels := PackedFloat32Array()
var _loaded := false


func _ready() -> void:
	if not _loaded:
		load_data()


## Loads the manifest and the low-resolution runtime maps. Safe to call twice.
func load_data() -> bool:
	_loaded = true
	var path := "%s/world_manifest.json" % GENERATED
	if not FileAccess.file_exists(path):
		Log.error("TerrainProvider", "%s missing; run ./run.sh world" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.error("TerrainProvider", "%s is not valid JSON" % path)
		return false
	manifest = parsed
	size_m = float(manifest.get("size_m", 8192))
	var o: Array = manifest.get("origin", [-4096, -4096])
	origin = Vector2(float(o[0]), float(o[1]))
	lake_level = float(manifest.get("lake_level", 8))
	sea_level = float(manifest.get("sea_level", 0))
	region_ids.assign(manifest.get("regions", []))
	var rt: Dictionary = manifest.get("runtime", {})
	_grid = int(rt.get("grid", 1024))
	_spacing = size_m / float(maxi(_grid, 1))
	_height_origin = origin + Vector2.ONE * runtime_height_offset(manifest)
	_heights = _read_floats("%s/%s" % [GENERATED, rt.get("heights", "")], _grid * _grid)
	_levels = _read_floats("%s/%s" % [GENERATED, rt.get("water_level", "")], _grid * _grid)
	_regions = _read_bytes("%s/%s" % [GENERATED, rt.get("regions", "")], _grid * _grid)
	_water = _read_bytes("%s/%s" % [GENERATED, rt.get("water", "")], _grid * _grid)
	if _heights.is_empty():
		Log.error("TerrainProvider", "runtime height map missing or short")
		return false
	Log.info("TerrainProvider", "world %d m, runtime grid %d (%.1f m), %d regions"
		% [int(size_m), _grid, _spacing, region_ids.size()])
	return true


## How far east and south of the origin the height map's first texel is centred. A manifest may
## say so itself (`runtime.height_offset_m`); otherwise it follows from the block mean the builder
## takes: half of one block less half a full texel.
static func runtime_height_offset(m: Dictionary) -> float:
	var rt: Dictionary = m.get("runtime", {})
	if rt.has("height_offset_m"):
		return float(rt["height_offset_m"])
	var full := int(m.get("grid", 0))
	var low := int(rt.get("grid", 0))
	if full <= low or low <= 0 or full % low != 0:
		return 0.0
	var full_spacing := float(m.get("size_m", 8192)) / float(full)
	return float(full / low - 1) * full_spacing * 0.5


func bind_terrain(terrain: Node3D) -> void:
	_terrain = terrain
	_data = terrain.get("data") if terrain else null


## The ground drawn from the runtime map (`FallbackTerrain`) when Terrain3D cannot draw one.
## Heights are then answered on its triangles, so they agree with its mesh and its collision.
func bind_fallback(ground: Node3D) -> void:
	_fallback = ground
	_triangles = ground != null


func has_terrain() -> bool:
	return _data != null


## "terrain3d", "fallback", or "" when nothing draws the ground.
func terrain_kind() -> String:
	if _data != null:
		return "terrain3d"
	return "fallback" if _fallback != null else ""


# --- the runtime maps, for the fallback ground -------------------------------------------------

func has_runtime_maps() -> bool:
	return not _heights.is_empty() and _grid > 1


func runtime_grid() -> int:
	return _grid


func runtime_spacing() -> float:
	return _spacing


## World x and z of the height map's texel (0, 0) (see `_height_origin`).
func height_origin() -> Vector2:
	return _height_origin


func runtime_heights() -> PackedFloat32Array:
	return _heights


func runtime_regions() -> PackedByteArray:
	return _regions


func runtime_water() -> PackedByteArray:
	return _water


func runtime_levels() -> PackedFloat32Array:
	return _levels


# --- queries ---------------------------------------------------------------------------------

## Ground height in metres at a world position.
func get_height(x: float, z: float) -> float:
	if _data != null:
		var h: float = _data.call("get_height", Vector3(x, 0.0, z))
		if not is_nan(h):
			return h
	return sample_height(x, z)


## The name of the texture painted most strongly at a world position (`snow`, `cobbles`,
## `sand_flats` ...), or "" with no Terrain3D to ask or outside its regions. Terrain3D keeps a
## base and an overlay texture per control texel with a blend between them; whichever of the two
## the blend favours is what is underfoot. The id is named from the build's own slot list
## (`texture_slots` in the manifest, the order the builder painted in): the Terrain3D texture
## list is emptied once its arrays are on the card (World._build_texture_arrays), so it cannot be
## asked by then.
func texture_at(x: float, z: float) -> String:
	if _data == null:
		return ""
	var info: Variant = _data.call("get_texture_id", Vector3(x, 0.0, z))
	if not (info is Vector3):
		return ""
	var v := info as Vector3
	if is_nan(v.x) or is_nan(v.y) or is_nan(v.z):
		return ""
	var id := int(v.y) if v.z >= 0.5 else int(v.x)
	var slots: Array = manifest.get("texture_slots", [])
	if id < 0 or id >= slots.size():
		return ""
	return str(slots[id])


## Height from the runtime copy (works without Terrain3D): bilinear, or on the fallback ground's
## own triangles while it is the ground being drawn.
func sample_height(x: float, z: float) -> float:
	if _heights.is_empty():
		return 0.0
	var fx := clampf((x - _height_origin.x) / _spacing, 0.0, float(_grid) - 1.001)
	var fz := clampf((z - _height_origin.y) / _spacing, 0.0, float(_grid) - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var x1: int = mini(x0 + 1, _grid - 1)
	var z1: int = mini(z0 + 1, _grid - 1)
	var h00 := _heights[z0 * _grid + x0]
	var h10 := _heights[z0 * _grid + x1]
	var h01 := _heights[z1 * _grid + x0]
	var h11 := _heights[z1 * _grid + x1]
	if _triangles:
		return triangle_height(h00, h10, h01, h11, tx, tz)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## A point on a quad split along the diagonal from (1, 0) to (0, 1): the split Godot's
## HeightMapShape3D makes (Jolt's is mirrored to match it) and the one FallbackTerrain meshes.
static func triangle_height(h00: float, h10: float, h01: float, h11: float, tx: float, tz: float) -> float:
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


## Unit surface normal at a world position.
func get_normal(x: float, z: float) -> Vector3:
	if _data != null:
		var n: Vector3 = _data.call("get_normal", Vector3(x, 0.0, z))
		if not is_nan(n.x):
			return n
	var e := _spacing
	var hl := sample_height(x - e, z)
	var hr := sample_height(x + e, z)
	var hd := sample_height(x, z - e)
	var hu := sample_height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## Slope in radians (0 = flat).
func get_slope(x: float, z: float) -> float:
	return acos(clampf(get_normal(x, z).y, -1.0, 1.0))


func _index(x: float, z: float) -> int:
	var ix := clampi(int(round((x - origin.x) / _spacing)), 0, _grid - 1)
	var iz := clampi(int(round((z - origin.y) / _spacing)), 0, _grid - 1)
	return iz * _grid + ix


## Region id at a world position, or "" over open water (lake and sea).
func region_id_at(x: float, z: float) -> String:
	if _regions.is_empty():
		return ""
	var v := int(_regions[_index(x, z)])
	if v == OPEN_WATER or v >= region_ids.size():
		return ""
	return region_ids[v]


## Like region_id_at, but open water answers with the nearest land region instead of "".
func nearest_region_id_at(x: float, z: float) -> String:
	var id := region_id_at(x, z)
	if not id.is_empty():
		return id
	for r in [64.0, 160.0, 400.0, 900.0, 1600.0]:
		for a in range(0, 8):
			var ang := TAU * float(a) / 8.0
			id = region_id_at(x + cos(ang) * r, z + sin(ang) * r)
			if not id.is_empty():
				return id
	return region_ids[0] if not region_ids.is_empty() else ""


func region_index_at(x: float, z: float) -> int:
	if _regions.is_empty():
		return -1
	return int(_regions[_index(x, z)])


func is_water(x: float, z: float) -> bool:
	if _water.is_empty():
		return get_height(x, z) < sea_level
	return _water[_index(x, z)] != 0


## Water surface height at a position, or NO_WATER (-1000) if there is no water there.
## The stored level map is filled (every texel carries the nearest water surface), so the
## water mask is what decides whether there is water at all.
func water_level_at(x: float, z: float) -> float:
	if _levels.is_empty():
		return sea_level if get_height(x, z) < sea_level else NO_WATER
	if not is_water(x, z):
		return NO_WATER
	return _levels[_index(x, z)]


## The nearest water surface level whether or not this texel is under water (for shaders
## and for shore effects).
func nearest_water_level(x: float, z: float) -> float:
	if _levels.is_empty():
		return sea_level
	return _levels[_index(x, z)]


## Water depth at a position (0 on dry land).
func water_depth_at(x: float, z: float) -> float:
	var level := water_level_at(x, z)
	if level <= NO_WATER * 0.5:
		return 0.0
	return maxf(0.0, level - get_height(x, z))


## Highest ground in a radius: used by the capture runner and vista checks.
func max_height_around(x: float, z: float, radius: float, samples: int = 12) -> float:
	var best := get_height(x, z)
	for i in samples:
		var a := TAU * float(i) / float(samples)
		best = maxf(best, get_height(x + cos(a) * radius, z + sin(a) * radius))
	return best


func in_bounds(x: float, z: float) -> bool:
	return x >= origin.x and z >= origin.y and x <= origin.x + size_m and z <= origin.y + size_m


func _read_floats(path: String, count: int) -> PackedFloat32Array:
	if not FileAccess.file_exists(path):
		return PackedFloat32Array()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < count * 4:
		Log.error("TerrainProvider", "%s is %d bytes, expected %d" % [path, bytes.size(), count * 4])
		return PackedFloat32Array()
	return bytes.to_float32_array()


func _read_bytes(path: String, count: int) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < count:
		Log.error("TerrainProvider", "%s is %d bytes, expected %d" % [path, bytes.size(), count])
		return PackedByteArray()
	return bytes
