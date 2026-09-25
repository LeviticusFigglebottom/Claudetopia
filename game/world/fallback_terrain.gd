class_name FallbackTerrain
extends Node3D
## The ground, drawn from the runtime height map, when Terrain3D cannot draw it.
##
## Terrain3D is a GDExtension. A platform its release has no binary for (Linux on arm64, a Mac
## older than the one the frameworks were built for), or a copy of the game whose terrain regions
## were never imported, used to get no ground at all: the country's trees and houses stood in a
## grey void over nothing. The world builder already writes a quarter-resolution copy of the
## heights, regions and water for queries (`runtime/*_1024.*`, 8 m to a texel), so this draws that.
##
## * The mesh is one flat grid of 64 x 64 quads (512 m) with a skirt ring, shared by all 256
##   chunks and lifted in the vertex shader (`fallback_terrain.gdshader`). Each chunk carries four
##   index LODs of the same vertices (every 2nd, 4th, 8th and 16th), which Godot's mesh LOD picks
##   by distance; the skirts hide the cracks where two LODs meet.
## * The surface is the region's own terrain textures, tinted by its palette the way the builder's
##   colour map is, with slope, height, water, snow and the roads (stamped at 2 m from roads.json).
## * Collision is one HeightMapShape3D per chunk from the same heights, on the world and terrain
##   layers, so a body stands on it and every ray that looks for the ground finds it.
## * `TerrainProvider` answers heights on the same triangles (`bind_fallback`), and the scatter a
##   cell streams in, which was placed on the 2 m ground, is set down on this one as it arrives.

const SHADER_PATH := "res://world/fallback_terrain.gdshader"
const TEXTURE_DIR := "res://assets/textures/terrain"
## The import tool's slot table holds each material's tile size and albedo value; reading it keeps
## the coarse ground and the full one agreeing about what vale grass looks like.
const IMPORT_TOOL := "res://tools_gd/import_terrain.gd"
const ROADS_PATH := "res://world/generated/roads.json"
const CHUNK_QUADS := 64
## Index LODs: [step, key]. The key is the error in metres that Godot's mesh LOD lets shrink under
## `mesh_lod/lod_change/threshold_pixels` before it takes the rung, so at 1280 px wide and a 75
## degree field of view the rungs arrive at roughly 350 m, 950 m, 2.4 km and 5.7 km.
const LODS := [[2, 3.0], [4, 8.0], [8, 20.0], [16, 48.0]]
const SKIRT_DEPTH := 48.0
const TEXTURE_SIZE := 512
## The road mask: 2 m texels over the whole world.
const ROAD_TEXEL := 2.0
const LAYER_WORLD := 1 << 0
const LAYER_TERRAIN := 1 << 10

## What each region's ground is made of here, by the shape its map block names: a flat material, a
## steep one, a patch that comes through in noise within a height band [low, high, share, steep
## bias], and what lies at the water's edge. A simplification of tools/world/worldgen/surface.py.
## The steep bias lowers the slope at which the steep material takes over: Cinderlea's terraces
## are steps two metres high, and an 8 m map rounds each riser off into a moderate slope that would
## otherwise never read as the dark ash it is.
const GROUND_BY_SHAPE := {
	"downs": {"flat": "vale_grass", "steep": "chalk", "patch": "orchard_grass", "band": [0.0, 128.0, 0.35, 0.0], "shore": "mud"},
	"lake_basin": {"flat": "vale_grass", "steep": "chalk", "patch": "heather", "band": [16.0, 60.0, 0.30, 0.0], "shore": "shingle"},
	"delta": {"flat": "peat", "steep": "mud", "patch": "sand_flats", "band": [-20.0, 2.0, 0.55, 0.0], "shore": "mud"},
	"forest_rise": {"flat": "forest_floor", "steep": "granite", "patch": "moss", "band": [0.0, 420.0, 0.45, 0.0], "shore": "moss"},
	"mountains": {"flat": "limestone", "steep": "scree", "patch": "heather", "band": [110.0, 430.0, 0.55, 0.0], "shore": "shingle"},
	"ash_plateau": {"flat": "grey_grass", "steep": "ash_soil", "patch": "ash_soil", "band": [0.0, 900.0, 0.14, 0.14], "shore": "ash_soil"},
}
const WATER_GROUND := {"flat": "mud", "steep": "scree", "patch": "lake_bed", "band": [-4.0, 12.0, 0.6, 0.0], "shore": "shingle"}
const DEFAULT_GROUND := {"flat": "vale_grass", "steep": "granite", "patch": "moss", "band": [0.0, 400.0, 0.3, 0.0], "shore": "mud"}
## Which palette entries carry each shape's ground colour, its second voice and its accent, and how
## strong the accent is: surface.COLOUR_VOICES.
const COLOUR_VOICES := {
	"downs": [1, 0, 2, 0.30], "lake_basin": [1, 2, 3, 0.26], "delta": [0, 1, 3, 0.34],
	"forest_rise": [0, 3, 1, 0.34], "mountains": [0, 1, 2, 0.30], "ash_plateau": [0, 2, 1, 0.26],
}
const EXTRA_LAYERS := ["snow", "lake_bed", "dirt_path"]

var provider: TerrainProvider = null
## The streamer whose cells get set down on this ground as they arrive.
var streamer: Node = null
var material: ShaderMaterial = null
var chunks: Array[MeshInstance3D] = []
var bodies: Array[StaticBody3D] = []
## Milliseconds each part of the build took, for the log and for anyone wondering.
var timings: Dictionary = {}
var _layers: Array[String] = []


## Builds everything from the provider's runtime maps. False if there is nothing to build from.
func build(p: TerrainProvider) -> bool:
	provider = p
	if provider == null or not provider.has_runtime_maps():
		return false
	var t0 := Time.get_ticks_msec()
	var n := provider.runtime_grid()
	var heights := Image.create_from_data(n, n, false, Image.FORMAT_RF, provider.runtime_heights().to_byte_array())
	var normals := heights.duplicate() as Image
	normals.bump_map_to_normal_map(1.0 / provider.runtime_spacing())
	var regions := Image.create_from_data(n, n, false, Image.FORMAT_R8, provider.runtime_regions())
	var water := _water_image(n)
	var roads := _road_image()
	_mark(t0, "maps")
	material = ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	material.set_shader_parameter("heights", ImageTexture.create_from_image(heights))
	material.set_shader_parameter("normals", ImageTexture.create_from_image(normals))
	material.set_shader_parameter("regions", ImageTexture.create_from_image(regions))
	material.set_shader_parameter("water", ImageTexture.create_from_image(water))
	material.set_shader_parameter("roads", ImageTexture.create_from_image(roads))
	material.set_shader_parameter("height_origin", provider.height_origin())
	material.set_shader_parameter("mask_origin", provider.origin)
	material.set_shader_parameter("spacing", provider.runtime_spacing())
	material.set_shader_parameter("grid", n)
	material.set_shader_parameter("road_extent", provider.size_m)
	material.set_shader_parameter("skirt_depth", SKIRT_DEPTH)
	_set_regions()
	_mark(t0, "material")
	_set_layers()
	_mark(t0, "textures")
	_build_chunks(heights)
	_mark(t0, "chunks")
	provider.bind_fallback(self)
	if not EventBus.cell_loaded.is_connected(_on_cell_loaded):
		EventBus.cell_loaded.connect(_on_cell_loaded)
	Log.info("FallbackTerrain", "ground from the %d x %d runtime map: %d chunks, %d layers, %d ms (%s)"
			% [n, n, chunks.size(), _layers.size(), Time.get_ticks_msec() - t0, str(timings)])
	return true


func _mark(t0: int, what: String) -> void:
	var now := Time.get_ticks_msec() - t0
	var before := 0
	for v in timings.values():
		before += int(v)
	timings[what] = now - before


# --- maps --------------------------------------------------------------------------------------

## The water mask arrives as 0 and 1; its mipmaps are what tell the shader how near the water is,
## and an 8-bit average of ones and zeros is zero, so it is scaled to 0 and 255 first.
func _water_image(n: int) -> Image:
	var bytes := provider.runtime_water()
	if bytes.size() < n * n:
		bytes = PackedByteArray()
		bytes.resize(n * n)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_R8, bytes)
	img.adjust_bcs(255.0, 1.0, 1.0)
	img.generate_mipmaps()
	return img


## The roads, stamped at 2 m along every polyline in roads.json at its own width. A square stamp a
## texel apart is crude, and it is all C++ (`fill_rect`), which is what makes 36 km of road cost
## tens of milliseconds rather than seconds.
func _road_image() -> Image:
	var size := int(provider.size_m / ROAD_TEXEL)
	var img := Image.create(size, size, false, Image.FORMAT_R8)
	var roads := _read_roads()
	var white := Color(1, 1, 1, 1)
	for road in roads:
		var pts: Array = road.get("points", [])
		var half := maxf(float(road.get("width_m", 4.0)) * 0.5 / ROAD_TEXEL, 0.5)
		var side := maxi(int(round(half * 2.0)), 1)
		for i in range(1, pts.size()):
			var a := _road_texel(pts[i - 1])
			var b := _road_texel(pts[i])
			var steps := maxi(int(ceil(a.distance_to(b))), 1)
			for s in steps + 1:
				var c := a.lerp(b, float(s) / float(steps))
				img.fill_rect(Rect2i(int(round(c.x - half)), int(round(c.y - half)), side, side), white)
	img.generate_mipmaps()
	return img


func _road_texel(pt: Variant) -> Vector2:
	var arr: Array = pt
	return Vector2((float(arr[0]) - provider.origin.x) / ROAD_TEXEL, (float(arr[1]) - provider.origin.y) / ROAD_TEXEL)


func _read_roads() -> Array:
	if not FileAccess.file_exists(ROADS_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROADS_PATH))
	return parsed if typeof(parsed) == TYPE_ARRAY else []


# --- the regions' ground and colour -------------------------------------------------------------

func _set_regions() -> void:
	var ids := provider.region_ids
	var grounds: Array[Dictionary] = []
	var c0 := PackedVector3Array()
	var c1 := PackedVector3Array()
	var c2 := PackedVector3Array()
	var accent := PackedFloat32Array()
	for i in 8:
		var def := ContentDB.get_or_empty(ids[i]) if i < ids.size() else {}
		var shape := str((def.get("map", {}) as Dictionary).get("shape", ""))
		var ground: Dictionary = GROUND_BY_SHAPE.get(shape, DEFAULT_GROUND)
		if i == ids.size():
			ground = WATER_GROUND
		grounds.append(ground)
		var voices: Array = COLOUR_VOICES.get(shape, [0, 1, 2, 0.3])
		var palette: Array = (def.get("identity", {}) as Dictionary).get("palette", [])
		c0.append(_palette_colour(palette, int(voices[0])))
		c1.append(_palette_colour(palette, int(voices[1])))
		c2.append(_palette_colour(palette, int(voices[2])))
		accent.append(float(voices[3]) if not palette.is_empty() else 0.0)
	for g in grounds:
		for key in ["flat", "steep", "patch", "shore"]:
			_layer_index(str(g[key]))
	for extra in EXTRA_LAYERS:
		_layer_index(extra)
	var layers := PackedInt32Array()
	var bands := PackedVector4Array()
	for g in grounds:
		for key in ["flat", "steep", "patch", "shore"]:
			layers.append(_layer_index(str(g[key])))
		var band: Array = g["band"]
		bands.append(Vector4(float(band[0]), float(band[1]), float(band[2]), float(band[3]) if band.size() > 3 else 0.0))
	material.set_shader_parameter("region_layers", layers)
	material.set_shader_parameter("region_band", bands)
	material.set_shader_parameter("region_c0", c0)
	material.set_shader_parameter("region_c1", c1)
	material.set_shader_parameter("region_c2", c2)
	material.set_shader_parameter("region_accent", accent)
	material.set_shader_parameter("region_count", ids.size())
	material.set_shader_parameter("water_region", mini(ids.size(), 7))
	material.set_shader_parameter("snow_layer", _layer_index("snow"))
	material.set_shader_parameter("bed_layer", _layer_index("lake_bed"))
	material.set_shader_parameter("road_layer", _layer_index("dirt_path"))


## A palette entry as the builder reads it: sRGB, 0..1. Grey where a region has no palette.
static func _palette_colour(palette: Array, index: int) -> Vector3:
	if palette.is_empty():
		return Vector3(0.5, 0.5, 0.5)
	var c := Color.from_string(str(palette[index % palette.size()]), Color(0.5, 0.5, 0.5))
	return Vector3(c.r, c.g, c.b)


func _layer_index(layer_name: String) -> int:
	var i := _layers.find(layer_name)
	if i < 0:
		_layers.append(layer_name)
		i = _layers.size() - 1
	return i


## The texture arrays: each layer's albedo-and-height and normal-and-roughness maps at 512 px,
## with the tile size and albedo value the import tool gives Terrain3D.
func _set_layers() -> void:
	var slots := _slot_table()
	var scales := PackedFloat32Array()
	var value := PackedFloat32Array()
	var rough := PackedFloat32Array()
	for layer_name in _layers:
		var slot: Dictionary = slots.get(layer_name, {})
		scales.append(1.0 / float(slot.get("tile_m", 2.6)))
		value.append(float(slot.get("value", 0.5)))
		rough.append(float(slot.get("roughness_mod", 0.0)))
	while scales.size() < 24:
		scales.append(1.0)
		value.append(0.5)
		rough.append(0.0)
	# Most of what building this costs (a second or two when the machine is quiet), all of it reading
	# the terrain textures back and scaling them.
	var albedo: Array[Image] = []
	var normal: Array[Image] = []
	for layer_name in _layers:
		albedo.append(_layer_image("%s/%s_albedo_height.png" % [TEXTURE_DIR, layer_name], Color(0.45, 0.45, 0.4, 0.5)))
		normal.append(_layer_image("%s/%s_normal_rough.png" % [TEXTURE_DIR, layer_name], Color(0.5, 0.5, 1.0, 0.8)))
	var albedo_array := Texture2DArray.new()
	albedo_array.create_from_images(albedo)
	var normal_array := Texture2DArray.new()
	normal_array.create_from_images(normal)
	material.set_shader_parameter("albedo_array", albedo_array)
	material.set_shader_parameter("normal_array", normal_array)
	material.set_shader_parameter("layer_scale", scales)
	material.set_shader_parameter("layer_value", value)
	material.set_shader_parameter("layer_rough", rough)


func _slot_table() -> Dictionary:
	var out := {}
	var tool := load(IMPORT_TOOL) as GDScript
	if tool == null:
		return out
	var consts := tool.get_script_constant_map()
	for slot in consts.get("SLOTS", []):
		out[str(slot.get("name", ""))] = slot
	return out


## One terrain texture, at the fallback's size, uncompressed, with its own mipmaps. A texture that
## is not there becomes a flat colour rather than a hole. A headless run draws nothing and cannot
## read a texture back from a renderer it does not have, so it gets the flat colour, small.
func _layer_image(path: String, fill: Color) -> Image:
	if DisplayServer.get_name() == "headless":
		var flat := Image.create(4, 4, true, Image.FORMAT_RGBA8)
		flat.fill(fill)
		flat.generate_mipmaps()
		return flat
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			img = tex.get_image()
	if img == null or img.is_empty():
		Log.warn("FallbackTerrain", "terrain texture missing, using a flat colour: %s" % path)
		img = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(fill)
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != TEXTURE_SIZE or img.get_height() != TEXTURE_SIZE:
		img.resize(TEXTURE_SIZE, TEXTURE_SIZE, Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	return img


# --- chunks ------------------------------------------------------------------------------------

func _build_chunks(heights: Image) -> void:
	var mesh := chunk_mesh(CHUNK_QUADS, provider.runtime_spacing())
	var n := provider.runtime_grid()
	var spacing := provider.runtime_spacing()
	var hs := provider.height_origin()
	var per_side := int(ceil(float(n) / float(CHUNK_QUADS)))
	for cz in per_side:
		for cx in per_side:
			var i0 := cx * CHUNK_QUADS
			var j0 := cz * CHUNK_QUADS
			var i1: int = mini(i0 + CHUNK_QUADS, n - 1)
			var j1: int = mini(j0 + CHUNK_QUADS, n - 1)
			var shape := HeightMapShape3D.new()
			# heights over eight, under a uniform scale of eight: Jolt takes a uniform scale on
			# any shape, and the 8 m spacing comes with it
			shape.update_map_data_from_image(heights.get_region(Rect2i(i0, j0, i1 - i0 + 1, j1 - j0 + 1)), 0.0, 1.0 / spacing)
			var low := shape.get_min_height() * spacing
			var high := shape.get_max_height() * spacing
			var body := StaticBody3D.new()
			body.name = "Ground_%d_%d" % [cx, cz]
			body.collision_layer = LAYER_WORLD | LAYER_TERRAIN
			body.collision_mask = 0
			body.position = Vector3(hs.x + (float(i0 + i1) * 0.5) * spacing, 0.0, hs.y + (float(j0 + j1) * 0.5) * spacing)
			var col := CollisionShape3D.new()
			col.shape = shape
			col.scale = Vector3.ONE * spacing
			body.add_child(col)
			add_child(body)
			bodies.append(body)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.mesh = mesh
			mi.material_override = material
			mi.position = Vector3(hs.x + float(i0) * spacing, 0.0, hs.y + float(j0) * spacing)
			var extent := float(CHUNK_QUADS) * spacing
			mi.custom_aabb = AABB(Vector3(0.0, low - SKIRT_DEPTH, 0.0), Vector3(extent, high - low + SKIRT_DEPTH, extent))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)
			chunks.append(mi)


## The one mesh every chunk shares: (q + 1)^2 grid vertices `spacing` apart and a skirt ring
## (UV.x = 1) under the edge, with an index LOD for each rung in LODS. Triangles are split along
## the diagonal from (x + 1, z) to (x, z + 1), which is HeightMapShape3D's split, and wound
## clockwise seen from above, which is Godot's front face. The skirt is wound both ways: it is
## only ever seen through a crack, from whichever side the crack is on.
static func chunk_mesh(q: int, spacing: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for b in q + 1:
		for a in q + 1:
			verts.append(Vector3(float(a) * spacing, 0.0, float(b) * spacing))
			uvs.append(Vector2(0.0, 0.0))
			normals.append(Vector3.UP)
	# the skirt: one vertex under every edge vertex, side by side (north, south, west, east)
	var skirt_base := verts.size()
	for side in 4:
		for k in q + 1:
			var at := _edge_vertex(side, k, q)
			verts.append(Vector3(float(at.x) * spacing, 0.0, float(at.y) * spacing))
			uvs.append(Vector2(1.0, 0.0))
			normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = _indices(q, 1, skirt_base)
	var lods := {}
	for rung in LODS:
		lods[float(rung[1])] = _indices(q, int(rung[0]), skirt_base)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	return mesh


## Grid coordinates of the k-th vertex along one side: 0 north (z = 0), 1 south, 2 west, 3 east.
static func _edge_vertex(side: int, k: int, q: int) -> Vector2i:
	match side:
		0:
			return Vector2i(k, 0)
		1:
			return Vector2i(k, q)
		2:
			return Vector2i(0, k)
	return Vector2i(q, k)


static func _indices(q: int, step: int, skirt_base: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var row := q + 1
	for b in range(0, q, step):
		for a in range(0, q, step):
			var v00 := b * row + a
			var v10 := b * row + a + step
			var v01 := (b + step) * row + a
			var v11 := (b + step) * row + a + step
			out.append_array([v00, v10, v01, v10, v11, v01])
	for side in 4:
		for k in range(0, q, step):
			var e0 := _edge_vertex(side, k, q)
			var e1 := _edge_vertex(side, k + step, q)
			var t0 := e0.y * row + e0.x
			var t1 := e1.y * row + e1.x
			var s0 := skirt_base + side * row + k
			var s1 := skirt_base + side * row + k + step
			out.append_array([t0, s0, s1, t0, s1, t1, t0, s1, s0, t0, t1, s1])
	return out


# --- scatter placed on the full ground, set down on this one ------------------------------------

## A cell's scatter was placed on the 2 m ground, and this one is 8 m: over a tenth of the land they
## differ by more than a metre, which is grass hanging in the air. Each MultiMesh's positions are
## set down on this ground as the cell arrives, straight through its buffer.
func _on_cell_loaded(cell: Vector2i) -> void:
	if streamer == null or not is_instance_valid(streamer) or provider == null:
		return
	var node := streamer.get_node_or_null("Cell_%d_%d" % [cell.x, cell.y]) as Node3D
	if node == null:
		return
	reground(node, provider)
	# the trees drawn by level of detail are refilled from their group's own rows, so the rows
	# are what is set down (WorldStreamer.set_lod_groups_down, world/scatter_lod.gd)
	if streamer.has_method("set_lod_groups_down"):
		streamer.call("set_lod_groups_down", node, provider)


## Sets every MultiMesh instance under `cell` down on the provider's ground. Returns how many moved.
## A renderer that keeps no instance data -- the headless one -- hands back an empty buffer, and
## there is then nothing to move and nothing to write back.
static func reground(cell: Node3D, p: TerrainProvider) -> int:
	var moved := 0
	for child in cell.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.transform_format != MultiMesh.TRANSFORM_3D:
			continue
		# a level-of-detail group's MultiMeshes are refilled from the group's rows as the eye
		# moves, so what this wrote into them would not last, and on Forward+ they read back as
		# NaN positions; the group's rows are set down instead (ScatterLod.Group.set_down)
		if mmi.has_meta("lod_group"):
			continue
		var mm := mmi.multimesh
		var stride := buffer_stride(mm)
		var buf := mm.buffer
		if buf.is_empty() or buf.size() != mm.instance_count * stride:
			continue
		mm.buffer = set_down(buf, stride, cell.position, p)
		moved += mm.instance_count
	return moved


## Floats per instance in a MultiMesh buffer: a 3 x 4 transform, then colour, then custom data.
static func buffer_stride(mm: MultiMesh) -> int:
	return 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)


## The same buffer with every instance's height taken from the provider's ground; `origin` is
## where the cell node stands, since instance positions are stored relative to it. The transform is
## row-major, so the position's x, y and z are floats 3, 7 and 11 of each instance.
static func set_down(buf: PackedFloat32Array, stride: int, origin: Vector3, p: TerrainProvider) -> PackedFloat32Array:
	for o in range(0, buf.size() - stride + 1, stride):
		buf[o + 7] = p.get_height(buf[o + 3] + origin.x, buf[o + 11] + origin.z) - origin.y
	return buf
