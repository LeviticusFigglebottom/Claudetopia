class_name WaterSurface
extends Node3D
## The Mere, the Grey Sea, the marsh pools and the rivers, as stylised surfaces.
##
## One subdivided sheet covers the whole world and takes its height from the builder's water
## level map, discarding wherever the water mask says there is no water; the rivers are ribbon
## meshes built from rivers.json, which carries each river's own falling surface profile.
## Region tinting comes from the region palettes, so the Mere is not the same blue as the sea.

const SHADER := preload("res://assets/shaders/painted_water.gdshader")
const GENERATED := "res://world/generated"

## Region look: deep colour, shallow colour, how quickly depth reads as deep, how much of the
## world the surface mirrors (`reflect`, and `cap`, the most it gives back at the grazing angle),
## how hard the sun glitters on it, how rough the open water is (`waves`, the lake and the sea
## only; a river keeps its own), and how much foam its edges raise (`foam`). The Mere is Lake
## Glass: calm enough that the island and the far shore stand in it upside down, with the
## glittering path WORLD_BIBLE 6.2 asks for; the marsh's pools are still and brown, give back
## little and raise no surf (they are shallower than the foam band everywhere, and at the sea's
## foam the whole Sedgemire was white); the Grey Sea stays rough.
const REGION_WATER := {
	"core:region/brightwater": {"deep": "#09243c", "shallow": "#2d6a86", "fade": 5.0, "reflect": 0.9, "cap": 0.85, "glint": 4.0, "waves": 0.14, "foam": 0.5},
	"core:region/sedgemire": {"deep": "#0c221f", "shallow": "#2b5f55", "fade": 2.0, "reflect": 0.5, "cap": 0.65, "glint": 1.2, "waves": 0.12, "foam": 0.08},
	"core:region/hearthvale": {"deep": "#123239", "shallow": "#3f7a6a", "fade": 2.6, "reflect": 0.85, "cap": 0.7, "glint": 3.0, "waves": 0.3, "foam": 0.5},
	"core:region/briarwold": {"deep": "#0b2016", "shallow": "#2b5236", "fade": 2.6, "reflect": 0.7, "cap": 0.65, "glint": 2.0, "waves": 0.2, "foam": 0.3},
	"core:region/skerrow": {"deep": "#111f33", "shallow": "#3d6b8c", "fade": 3.4, "reflect": 0.9, "cap": 0.65, "glint": 3.5, "waves": 0.42, "foam": 0.8},
	"core:region/cinderlea": {"deep": "#16191b", "shallow": "#3f4a50", "fade": 2.6, "reflect": 0.6, "cap": 0.6, "glint": 1.5, "waves": 0.25, "foam": 0.4, "damp": 1.25},
}

@export var sheet_subdivisions: int = 96

## The graphics setting `water_quality` (0 Low .. 3 Painted): how finely the sheet is cut, which
## is what the swell and the depth colour have to interpolate over, and how much of the finest
## ripple layer the shader draws. High (2) is the water as it was built.
const QUALITY_SUBDIVISIONS := [48, 64, 96, 160]
## The sheet as it is built on a loaded world: cells of this many metres laid over the water
## only, each corner at the water level under it (`water_mesh`). The subdivided plane took its
## height from the level map at vertices ninety metres apart, and wherever two waters at
## different levels were nearer than that -- a tarn under its fall, the Mere where a beck comes
## down -- the water between was drawn at a level between the two: Weaver's Linn stood 13 m
## over itself in a blue slab under its fall.
const QUALITY_CELL_M := [32.0, 24.0, 16.0, 12.0]
## Open water this many cells square, all at one level, is laid as one quad.
const BLOCK_CELLS := 8  # even: the block's middle is a corner of the grid
const QUALITY_DETAIL := [0.0, 0.6, 1.0, 1.0]
## ... and how far over the water the mirror looks for the far shore (the shader's steps).
const QUALITY_MIRROR_STEPS := [8, 11, 16, 18]
## How much of a river's ribbon runs past its waterline, under the bank, to thin away there.
const RIBBON_OVERHANG_M := 0.35
## The shore classes in the order the water shader numbers them (CONTRACTS 6, runtime.shore).
const SHORE_CLASSES := ["none", "sand", "shingle", "rock", "cliff", "mud", "reeds"]
## How much of the region's mirror a river keeps.
const RIVER_REFLECT := 0.6
## How far past a river's water, or a fall's, the lake sheet leaves the texels to it: a texel and
## a half, so that no wet texel of the river's own is left for the sheet to draw. At 4 m, one a
## texel off the line was the sheet's, and where a place's pad lies under the river's level it
## stood over the bank as a wedge of water (the Three Sisters).
const CLAIM_REACH_M := 12.0
## The cells `surface_at` files the rivers' segments by.
const SURFACE_CELL_M := 32.0
## The speeds (m/s) a river runs at: a lowland reach barely moves, a mountain beck runs.
const RIVER_SPEED := Vector2(0.3, 3.5)
var quality := 2

var provider: TerrainProvider
var sheet: MeshInstance3D
var skirt: MeshInstance3D
var rivers_root: Node3D
var _sheet_material: ShaderMaterial
var _skirt_material: ShaderMaterial
var _river_materials: Array[ShaderMaterial] = []
var falls: RiverFalls
var underwater: UnderwaterView = null
## The swash, its foam and the wet band on the ground above the still water (world/shore_band.gd).
var shore: ShoreBand = null
var _claim_tex: ImageTexture
var _level_tex: ImageTexture
var _mask_tex: ImageTexture
var _shore_tex: ImageTexture
var _levels := PackedFloat32Array()
var _height_tex: ImageTexture
## The rivers' water as it is drawn, for `surface_at`: each segment of a ribbon that is drawn, as
## [a (Vector2), b, surface at a, surface at b, half the water's width, the current's speed at a,
## at b], filed by the SURFACE_CELL_M cells it passes over; and each fall's pool, as
## [centre (Vector2), radius, surface].
var _river_segments: Array = []
var _pools: Array = []
var _segment_cells: Dictionary = {}

## The water the world last built, for the static `at` (the player, the camera, the swimmer).
static var current: WaterSurface = null

static var _variants: Dictionary = {}


## The water shader, with the mirror or without it, for open water or for a river's ribbon.
## Without the mirror is the same code built with WATER_NO_MIRROR defined, so the screen texture is
## never named: a material that names it makes the renderer copy the frame before the water is
## drawn, whatever its `mirror` uniform says, and the setting that turns reflections off is there
## to save that copy. A river is the same code with WATER_RIVER: its flow, its channel's depth and
## its foam come from the ribbon's own vertices.
static func shader_for(mirrored: bool, river := false) -> Shader:
	if mirrored and not river:
		return SHADER
	var key := "%s%s" % [mirrored, river]
	if not _variants.has(key):
		var defines := ""
		if not mirrored:
			defines += "\n#define WATER_NO_MIRROR"
		if river:
			defines += "\n#define WATER_RIVER"
		var sh := Shader.new()
		sh.code = SHADER.code.replace("shader_type spatial;", "shader_type spatial;" + defines)
		_variants[key] = sh
	return _variants[key]


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)


## Puts every water material on the shader `graphics/water_reflections` asks for, keeping what
## the region look and the builder set on it.
func apply_reflections() -> void:
	var mirrored := bool(Settings.get_value("graphics", "water_reflections", true))
	for mat in _all_materials():
		var shader := shader_for(mirrored, _river_materials.has(mat))
		if mat.shader != shader:
			var keep := {}
			if mat.shader != null:
				for u in mat.shader.get_shader_uniform_list():
					keep[str(u["name"])] = mat.get_shader_parameter(str(u["name"]))
			mat.shader = shader
			for k in keep:
				if keep[k] != null:
					mat.set_shader_parameter(k, keep[k])
		mat.set_shader_parameter("mirror", 1.0 if mirrored else 0.0)


## Builds the water. Given a `slice` (a world standing up while it is drawn), it is paced by the
## frame's budget (WorldPace) between its parts and its rivers, and takes as many frames as that
## needs: await it. In one go it was a frame of 0.6 s behind the title's menu (TRIAGE item 36).
func build(p: TerrainProvider, slice: WorldPace.Slice = null) -> void:
	current = self
	if underwater == null:
		underwater = UnderwaterView.new()
		underwater.name = "Underwater"
		add_child(underwater)
	provider = p
	if provider == null:
		return
	quality = clampi(int(Settings.get_value("graphics", "water_quality", 2)), 0, 3)
	sheet_subdivisions = QUALITY_SUBDIVISIONS[quality]
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	_build_textures()
	if slice != null:
		await slice.pace("water_textures")
	await _build_sheet(slice)
	if slice != null:
		await slice.pace("water_sheet")
	_build_skirt()
	if slice != null:
		await slice.pace("water_skirt")
	await _build_rivers(slice)
	shore = ShoreBand.new()
	shore.name = "Shore"
	add_child(shore)
	shore.setup(provider, _level_tex, _shore_tex)
	set_region_look(GameState.current_region_id)
	var skirt_aabb := skirt.get_aabb() if skirt else AABB()
	Log.info("WaterSurface", "sheet %.0f m, sea skirt %.0f m (%d verts), %d rivers, sea level %.1f m"
		% [provider.size_m + 512.0, skirt_aabb.size.x, 0 if skirt == null else skirt.mesh.get_faces().size(),
			_river_materials.size(), provider.sea_level])


func _build_textures() -> void:
	var rt: Dictionary = provider.manifest.get("runtime", {})
	var n := int(rt.get("grid", 1024))
	var level_path := "%s/%s" % [GENERATED, rt.get("water_level", "")]
	_level_tex = _texture_rf(level_path, n)
	# the levels themselves, for laying the sheet (a quarter of a million corners at 16 m)
	var level_bytes := FileAccess.get_file_as_bytes(level_path)
	if level_bytes.size() >= n * n * 4:
		_levels = level_bytes.to_float32_array()
	_height_tex = _texture_rf("%s/%s" % [GENERATED, rt.get("heights", "")], n)
	_mask_tex = _mask_texture(mask_path(provider.manifest), n)
	_shore_tex = _shore_texture(provider.manifest, n)


func _texture_rf(path: String, n: int) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < n * n * 4:
		Log.error("WaterSurface", "cannot read %s" % path)
		return null
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, bytes)
	return ImageTexture.create_from_image(img)


func _mask_texture(path: String, n: int) -> ImageTexture:
	var img := mask_image(path, n)
	if img == null:
		Log.error("WaterSurface", "cannot read %s" % path)
		return null
	return ImageTexture.create_from_image(img)


## The shore classes (0 none, 1 sand, 2 shingle, 3 rock, 4 cliff, 5 mud, 6 reeds), one byte a
## texel on the runtime grid, or null when the world build has not written them.
static func _shore_texture(manifest: Dictionary, n: int) -> ImageTexture:
	var rt: Dictionary = manifest.get("runtime", {})
	if not rt.has("shore"):
		return null
	var bytes := FileAccess.get_file_as_bytes("%s/%s" % [GENERATED, rt["shore"]])
	if bytes.size() < n * n:
		return null
	bytes = shore_bytes(bytes.slice(0, n * n), rt.get("shore_classes", []))
	return ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_R8, bytes))


## The shore classes as the shader numbers them (SHORE_CLASSES), whatever order the build wrote
## its names in (`runtime.shore_classes`); a class the shader does not know reads as none.
static func shore_bytes(bytes: PackedByteArray, names: Array) -> PackedByteArray:
	if names.is_empty() or names == SHORE_CLASSES:
		return bytes
	var table := PackedByteArray()
	table.resize(256)
	for i in names.size():
		table[i] = maxi(SHORE_CLASSES.find(str(names[i])), 0)
	var out := bytes.duplicate()
	for i in out.size():
		out[i] = table[out[i]]
	return out


## Where the water mask the game loads lives, from the world manifest.
static func mask_path(manifest: Dictionary) -> String:
	var rt: Dictionary = manifest.get("runtime", {})
	return "%s/%s" % [GENERATED, rt.get("water", "")]


## The water mask exactly as the shader will sample it (see `mask_bytes`), or null if it cannot
## be read. The water shader discards wherever this is under 0.5.
static func mask_image(path: String, n: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < n * n:
		return null
	return Image.create_from_data(n, n, false, Image.FORMAT_R8, mask_bytes(bytes))


## The water mask as the shader reads it: 0 dry, 255 wet. The world builder writes it as 0 and 1,
## and an R8 texture reads a byte as byte/255, so a wet texel was 0.004 to the shader -- under its
## 0.5 test everywhere. Every lake and the sea were discarded, from the first runtime world on, and
## what the camera saw on the Mere was the lake bed's own terrain texture under no water at all:
## the water shader's reflections, glints and colours never reached a frame outside the rivers.
## Stretched to 255, the mask's linear filter still puts the waterline midway between a wet texel
## and a dry one. A mask already written as 0 and 255 is left as it is.
static func mask_bytes(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.has(255) or not bytes.has(1):
		return bytes
	var out := bytes.duplicate()
	for i in out.size():
		if out[i] != 0:
			out[i] = 255
	return out


func _make_material(follow_level: bool, use_mask: bool, river := false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var mirrored := bool(Settings.get_value("graphics", "water_reflections", true))
	mat.shader = shader_for(mirrored, river)
	mat.set_shader_parameter("level_tex", _level_tex)
	mat.set_shader_parameter("mask_tex", _mask_tex)
	# what each shore is made of, where the world build says (runtime.shore, CONTRACTS 6): the
	# foam breaks on rock and runs up sand, and lies still on mud and in the reeds
	mat.set_shader_parameter("shore_tex", _shore_tex)
	mat.set_shader_parameter("has_shore", _shore_tex != null)
	mat.set_shader_parameter("height_tex", _height_tex)
	mat.set_shader_parameter("world_origin", provider.origin)
	mat.set_shader_parameter("world_size", provider.size_m)
	mat.set_shader_parameter("follow_level", follow_level)
	mat.set_shader_parameter("use_mask", use_mask)
	mat.set_shader_parameter("detail", QUALITY_DETAIL[quality])
	mat.set_shader_parameter("mirror_steps", QUALITY_MIRROR_STEPS[quality])
	# the lake gives back the far shore and the hills; a machine that cannot spare the frame copy
	# the lookup needs can turn it off, and the water keeps the sky's own colours
	mat.set_shader_parameter("mirror", 1.0 if mirrored else 0.0)
	return mat


func _build_sheet(slice: WorldPace.Slice = null) -> void:
	sheet = MeshInstance3D.new()
	sheet.name = "WaterSheet"
	var cells: ArrayMesh = null
	if slice != null:
		# laid on a worker thread (it reads the maps and nothing else), while frames go on: on the
		# main thread it was a quarter of a second in one frame behind the title's menu
		slice.due("water_textures")
		var out: Array = [null]
		var cell_m: float = QUALITY_CELL_M[quality]
		var task := WorkerThreadPool.add_task(func() -> void: out[0] = water_mesh(cell_m), true, "wm_water_sheet")
		while not WorkerThreadPool.is_task_completed(task):
			await WorldPace.next_frame()
		WorkerThreadPool.wait_for_task_completion(task)
		slice.t0 = Time.get_ticks_usec()
		cells = out[0]
	else:
		cells = water_mesh(QUALITY_CELL_M[quality])
	if cells != null:
		sheet.mesh = cells
		_sheet_material = _make_material(false, true)
	else:
		# no runtime maps to lay it over: the plane, lifted to the level map in the shader
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(provider.size_m + 512.0, provider.size_m + 512.0)
		mesh.subdivide_width = sheet_subdivisions
		mesh.subdivide_depth = sheet_subdivisions
		sheet.mesh = mesh
		_sheet_material = _make_material(true, true)
	sheet.position = Vector3.ZERO
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the sheet spans the world, so its own bounds must not cull it when the camera is inside
	sheet.extra_cull_margin = provider.size_m
	sheet.material_override = _sheet_material
	add_child(sheet)


## The lakes, the sea and the marsh's pools as cells of `cell` metres laid over the water mask
## (and one cell round it, which the mask's filter reaches into), every corner at the level of
## the water under it, so each water stands at its own level to within a cell of where it meets
## another. The shader discards what the mask calls dry, what a river's ribbon or a fall's pool
## draws instead, and what a cell's corners would still lift above its water. Null with no
## runtime maps.
func water_mesh(cell: float) -> ArrayMesh:
	if provider == null or not provider.has_runtime_maps():
		return null
	var n := provider.runtime_grid()
	var sp := provider.runtime_spacing()
	var org := provider.origin
	var wet := provider.runtime_water()
	if wet.size() != n * n:
		return null
	var cn := int(ceil(provider.size_m / cell))
	var used := PackedByteArray()
	used.resize(cn * cn)
	for j in n:
		var row := j * n
		var cz := mini(int((float(j) + 0.5) * sp / cell), cn - 1)
		for i in n:
			if wet[row + i] != 0:
				used[cz * cn + mini(int((float(i) + 0.5) * sp / cell), cn - 1)] = 1
	# one cell round every wet one
	var grown := used.duplicate()
	for cz in cn:
		for cx in cn:
			if used[cz * cn + cx] == 0:
				continue
			for dz in range(maxi(cz - 1, 0), mini(cz + 2, cn)):
				for dx in range(maxi(cx - 1, 0), mini(cx + 2, cn)):
					grown[dz * cn + dx] = 1
	var vid := PackedInt32Array()
	vid.resize((cn + 1) * (cn + 1))
	vid.fill(-1)
	var level := PackedFloat32Array()
	level.resize((cn + 1) * (cn + 1))
	# each corner's level is the level map's texel nearest it (TerrainProvider.nearest_water_level),
	# read straight from the map where it was loaded
	var fast := _levels.size() == n * n
	for gz in cn + 1:
		var z := org.y + float(gz) * cell
		var iz := clampi(roundi((z - org.y) / sp), 0, n - 1)
		for gx in cn + 1:
			var x := org.x + float(gx) * cell
			if fast:
				level[gz * (cn + 1) + gx] = _levels[iz * n + clampi(roundi((x - org.x) / sp), 0, n - 1)]
			else:
				level[gz * (cn + 1) + gx] = provider.nearest_water_level(x, z)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	# Open water a block of cells wide, all of it at one level, is one quad: the sea and the Mere
	# are most of the water, and at 16 m cells they were a hundred thousand triangles drawn in
	# every frame. A block's edge meets its finer neighbours' corners on the same flat level.
	var block := BLOCK_CELLS
	var done := PackedByteArray()
	done.resize(cn * cn)
	for bz in range(0, cn - block + 1, block):
		for bx in range(0, cn - block + 1, block):
			var flat := true
			var y0 := level[bz * (cn + 1) + bx]
			for dz in block + 1:
				for dx in block + 1:
					if absf(level[(bz + dz) * (cn + 1) + bx + dx] - y0) > 0.01:
						flat = false
					if dz < block and dx < block and grown[(bz + dz) * cn + bx + dx] == 0:
						flat = false
			if not flat:
				continue
			for dz in block:
				for dx in block:
					done[(bz + dz) * cn + bx + dx] = 1
			# a fan from the block's middle through every grid corner on its edge, so its edge meets
			# the finer cells beside it corner to corner: as one quad its edge had none of theirs,
			# and a crack of sky ran along it across the Mere
			var ring := PackedInt32Array()
			for k in block:
				ring.append(_sheet_vertex(vid, level, bx + k, bz, cn, cell, verts, uvs, normals))
			for k in block:
				ring.append(_sheet_vertex(vid, level, bx + block, bz + k, cn, cell, verts, uvs, normals))
			for k in block:
				ring.append(_sheet_vertex(vid, level, bx + block - k, bz + block, cn, cell, verts, uvs, normals))
			for k in block:
				ring.append(_sheet_vertex(vid, level, bx, bz + block - k, cn, cell, verts, uvs, normals))
			var mid := _sheet_vertex(vid, level, bx + (block >> 1), bz + (block >> 1), cn, cell, verts, uvs, normals)
			for k in ring.size():
				indices.append_array([mid, ring[k], ring[(k + 1) % ring.size()]])
	for cz in cn:
		for cx in cn:
			if grown[cz * cn + cx] == 0 or done[cz * cn + cx] == 1:
				continue
			var corner := PackedInt32Array()
			for k in 4:
				corner.append(_sheet_vertex(vid, level, cx + (k & 1), cz + (k >> 1), cn, cell, verts, uvs, normals))
			indices.append_array([corner[0], corner[1], corner[3], corner[0], corner[3], corner[2]])
	if indices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _sheet_vertex(vid: PackedInt32Array, level: PackedFloat32Array, gx: int, gz: int, cn: int, cell: float,
		verts: PackedVector3Array, uvs: PackedVector2Array, normals: PackedVector3Array) -> int:
	var key := gz * (cn + 1) + gx
	if vid[key] < 0:
		var x := provider.origin.x + float(gx) * cell
		var z := provider.origin.y + float(gz) * cell
		vid[key] = verts.size()
		verts.append(Vector3(x, level[key], z))
		uvs.append(Vector2(x, z))
		normals.append(Vector3.UP)
	return vid[key]


## The Grey Sea runs to the horizon, not to the edge of the heightmap.
##
## The sheet stops where the world does, so from any hill the far edge of the ocean was a
## straight grey bar with sky under it. This is a flat ring of water outside the world, at sea
## level, big enough that its own edge is over the horizon. The shader's maps are sampled with
## clamp-to-edge, so a skirt texel takes the mask, level and ground height of the nearest world
## edge texel: it is water exactly where the coast is water, and discards where the world ends
## in land (the mountain wall north, the cliffs south).
func _build_skirt() -> void:
	# from the world's edge out: the sheet's cells lie over the world's own water only, and the
	# 256 m the skirt used to leave between the two was open to the sky's underside
	var r_in := provider.size_m * 0.5
	var r_out := provider.size_m * 6.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# eight pieces: four sides and four corners, each subdivided so distance fog has something
	# to interpolate over
	var bands: Array = [
		[-r_out, -r_out, -r_in, -r_in], [-r_in, -r_out, r_in, -r_in], [r_in, -r_out, r_out, -r_in],
		[-r_out, -r_in, -r_in, r_in], [r_in, -r_in, r_out, r_in],
		[-r_out, r_in, -r_in, r_out], [-r_in, r_in, r_in, r_out], [r_in, r_in, r_out, r_out],
	]
	for b in bands:
		_add_quad(st, float(b[0]), float(b[1]), float(b[2]), float(b[3]), 6)
	skirt = MeshInstance3D.new()
	skirt.name = "SeaSkirt"
	skirt.mesh = st.commit()
	skirt.position = Vector3(0.0, provider.sea_level, 0.0)
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skirt.extra_cull_margin = r_out
	_skirt_material = _make_material(false, true)
	skirt.material_override = _skirt_material
	add_child(skirt)


func _add_quad(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, steps: int) -> void:
	for i in steps:
		for j in steps:
			var ax := lerpf(x0, x1, float(i) / float(steps))
			var bx := lerpf(x0, x1, float(i + 1) / float(steps))
			var az := lerpf(z0, z1, float(j) / float(steps))
			var bz := lerpf(z0, z1, float(j + 1) / float(steps))
			# wound as the sheet is, so the shader sees it from above (FRONT_FACING): wound the other
			# way it took the sea beyond the world for water seen from below, and gave back no sky
			for corner in [[ax, az], [bx, az], [bx, bz], [ax, az], [bx, bz], [ax, bz]]:
				# the shader culls nothing, so the winding does not matter, but the normal
				# does: a generated one could come out pointing at the sea bed
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(float(corner[0]), float(corner[1])))
				st.add_vertex(Vector3(float(corner[0]), 0.0, float(corner[1])))


func _build_rivers(slice: WorldPace.Slice = null) -> void:
	rivers_root = Node3D.new()
	rivers_root.name = "Rivers"
	add_child(rivers_root)
	var path := "%s/rivers.json" % GENERATED
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		return
	# each river's falls: the sheet, the pool, the white water and the mist; the ribbon stops at
	# every lip and starts again at the foot
	falls = RiverFalls.new()
	falls.name = "Falls"
	rivers_root.add_child(falls)
	falls.build(parsed)
	var claims: Array = []
	for entry in parsed:
		if slice != null:
			await slice.pace("water_river")
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var mesh := _river_mesh(entry)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = str(entry.get("id", "river")).get_file()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _make_material(false, false, true)
		mat.set_shader_parameter("depth_fade_m", 1.8)
		mat.set_shader_parameter("foam_width_m", 0.5)
		mat.set_shader_parameter("wave_strength", 0.3)
		# the current's texture held further off than a lake's ripples: a river is narrow, and
		# calmed at the lake's distance it was one flat strip from the bank above it
		mat.set_shader_parameter("distance_calm_m", 600.0)
		mat.set_shader_parameter("opacity_shallow", 0.35)
		mat.set_shader_parameter("opacity_deep", 0.9)
		mat.set_shader_parameter("mirror_ripple", 0.8)
		mi.material_override = mat
		_river_materials.append(mat)
		rivers_root.add_child(mi)
		claims.append_array(river_claims(entry))
	for f in RiverFalls.read_falls(parsed):
		claims.append_array(fall_claims(f))
		var pool: Variant = f.get("pool", null)
		if typeof(pool) == TYPE_DICTIONARY and (pool as Dictionary).has("centre"):
			var c: Array = pool["centre"]
			_pools.append([Vector2(float(c[0]), float(c[2])), float(pool.get("radius_m", 5.0)), float(c[1])])
	if slice != null:
		await slice.pace("water_river")
	_claim_tex = _claim_texture(claims)
	for mat in [_sheet_material, _skirt_material]:
		if mat != null:
			mat.set_shader_parameter("claim_tex", _claim_tex)


## Where a river's ribbon and the falls draw the water, as [x, z, radius] discs: the lake sheet
## discards there (its level is read at vertices ninety metres apart, and on a river in the hills
## it stood metres off the channel, a second blue band beside the first). A point where the river
## has run into open water claims nothing.
func river_claims(entry: Dictionary) -> Array:
	var out: Array = []
	var pts: Array = entry.get("points", [])
	var fade := _ribbon_fade(entry)
	var w_from := float(entry.get("width_from_m", entry.get("width_m", 6.0)))
	var w_to := float(entry.get("width_to_m", entry.get("width_m", 6.0)))
	for i in pts.size():
		if fade.size() == pts.size() and fade[i] < 0.5:
			continue
		var p: Array = pts[i]
		var t := float(i) / float(maxi(pts.size() - 1, 1))
		out.append([float(p[0]), float(p[1]), lerpf(w_from, w_to, pow(t, 0.7)) * 0.5 + CLAIM_REACH_M])
	return out


static func fall_claims(f: Dictionary) -> Array:
	var out: Array = []
	var top: Array = f["top"]
	var foot: Array = f["foot"]
	var w := float(f.get("width_m", 4.0))
	for k in 5:
		var t := float(k) / 4.0
		out.append([lerpf(float(top[0]), float(foot[0]), t), lerpf(float(top[2]), float(foot[2]), t), w * 0.5 + CLAIM_REACH_M])
	var pool: Variant = f.get("pool", null)
	if typeof(pool) == TYPE_DICTIONARY and (pool as Dictionary).has("centre"):
		var c: Array = pool["centre"]
		out.append([float(c[0]), float(c[2]), float(pool.get("radius_m", 5.0)) + CLAIM_REACH_M])
	return out


## The claim map, on the runtime grid: 255 where a disc of `claims` covers a texel that is not
## open water (the region map's 255), 0 elsewhere.
func _claim_texture(claims: Array) -> ImageTexture:
	if provider == null:
		return null
	var n := provider.runtime_grid()
	var sp := provider.runtime_spacing()
	var org := provider.origin
	var regions := provider.runtime_regions()
	var bytes := PackedByteArray()
	bytes.resize(n * n)
	for c in claims:
		var cx := float(c[0])
		var cz := float(c[1])
		var r := float(c[2])
		var i0 := maxi(int(floor((cx - r - org.x) / sp)), 0)
		var i1 := mini(int(ceil((cx + r - org.x) / sp)), n - 1)
		var j0 := maxi(int(floor((cz - r - org.y) / sp)), 0)
		var j1 := mini(int(ceil((cz + r - org.y) / sp)), n - 1)
		for j in range(j0, j1 + 1):
			var z := org.y + (float(j) + 0.5) * sp
			for i in range(i0, i1 + 1):
				var x := org.x + (float(i) + 0.5) * sp
				if (x - cx) * (x - cx) + (z - cz) * (z - cz) > r * r:
					continue
				var k := j * n + i
				if regions.size() == n * n and regions[k] == 255:
					continue
				bytes[k] = 255
	return ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_R8, bytes))


## How much of a river's ribbon is drawn at each point: none where the river has run out into a
## lake or the sea (the region map's open water, at the lake's own level), fading in over the
## two points before, so the ribbon thins into the lake instead of ending on it. Empty when the
## world is not loaded.
func _ribbon_fade(entry: Dictionary) -> PackedFloat32Array:
	var pts: Array = entry.get("points", [])
	var surface: Array = entry.get("surface_m", [])
	var out := PackedFloat32Array()
	if provider == null or not provider.has_runtime_maps():
		return out
	out.resize(pts.size())
	for i in pts.size():
		var p: Array = pts[i]
		var x := float(p[0])
		var z := float(p[1])
		var y := float(surface[i]) if surface.size() == pts.size() else provider.nearest_water_level(x, z)
		var open := provider.region_index_at(x, z) == 255 and absf(provider.water_level_at(x, z) - y) < 1.0
		# and where the sea or a lake stands over the river's own surface: the Sedgemire's channels
		# run out across the tideflats below the sea's level, and there the ribbon lay under a cut in
		# the sea, a sunken lane with the sea's edge standing over it (the North Channel's mouth)
		var standing := _standing_level(x, z)
		if standing > y + 0.3:
			open = true
		out[i] = 0.0 if open else 1.0
	# fade in over the two points either side of open water
	var soft := out.duplicate()
	for i in out.size():
		if out[i] == 0.0:
			continue
		for d in [1, 2]:
			for j in [i - d, i + d]:
				if j >= 0 and j < out.size() and out[j] == 0.0:
					soft[i] = minf(soft[i], 0.5 * float(d) - 0.25)
	return soft


## The level of the sea or a lake at a point, if that is the water there; NO_WATER otherwise.
func _standing_level(x: float, z: float) -> float:
	if not provider.is_water(x, z):
		return TerrainProvider.NO_WATER
	var l := provider.nearest_water_level(x, z)
	if absf(l - provider.sea_level) < 0.3:
		return l
	for lake in provider.manifest.get("lakes", []):
		if absf(l - float((lake as Dictionary).get("level_m", -9999.0))) < 0.3:
			return l
	return TerrainProvider.NO_WATER


## A ribbon along the river's centre line at its own (falling) water surface, in the channel the
## builder carved: no higher than the surface the builder gives at each point (CONTRACTS 6). It
## carries its flow for the river shader: UV is metres across (0 on the centre line) and metres
## along; UV2 the current's speed (from the slope of its surface) and how hard it bends (signed,
## + turning toward +across); COLOR its downstream direction, its water's half-width / 20 and how
## much of it is drawn. The ribbon is cut over every fall (the fall is drawn there instead) and
## where the river has run out into open water.
func _river_mesh(entry: Dictionary) -> ArrayMesh:
	var pts: Array = entry.get("points", [])
	if pts.size() < 2:
		return null
	var w_from := float(entry.get("width_from_m", entry.get("width_m", 6.0)))
	var w_to := float(entry.get("width_to_m", entry.get("width_m", 6.0)))
	var s_from := float(entry.get("surface_from_m", 0.0))
	var s_to := float(entry.get("surface_to_m", 0.0))
	# the builder's own surface at every point (CONTRACTS 6), where the file has it
	var surface: Array = entry.get("surface_m", [])
	var count := pts.size()
	var fade := _ribbon_fade(entry)
	var cut := PackedByteArray()
	cut.resize(count)
	for span in RiverFalls.spans(entry):
		for i in range(int(span[0]), int(span[1])):
			cut[i] = 1
	var xz: Array[Vector2] = []
	var ys := PackedFloat32Array()
	for i in count:
		var p: Array = pts[i]
		xz.append(Vector2(float(p[0]), float(p[1])))
		var t := float(i) / float(count - 1)
		var y: float = lerpf(s_from, s_to, t)
		if surface.size() == count:
			# A mountain river falls in its gorge and runs level across its plain; a straight
			# ramp between its two ends stood the Skerrow Water 158 m over the dales.
			y = float(surface[i])
		elif provider != null:
			y = maxf(provider.nearest_water_level(xz[i].x, xz[i].y), y - 0.35)
		ys.append(y)
	# the current: faster where the surface falls faster, smoothed along the river
	var raw_speed := PackedFloat32Array()
	var raw_bend := PackedFloat32Array()
	raw_speed.resize(count)
	raw_bend.resize(count)
	for i in count:
		var a := maxi(i - 1, 0)
		var b := mini(i + 1, count - 1)
		var run := maxf(xz[a].distance_to(xz[b]), 0.5)
		var grade := clampf((ys[a] - ys[b]) / run, 0.0, 1.0)
		raw_speed[i] = clampf(RIVER_SPEED.x + sqrt(grade) * 6.0, RIVER_SPEED.x, RIVER_SPEED.y)
		if i > 0 and i < count - 1:
			var d0 := (xz[i] - xz[i - 1]).normalized()
			var d1 := (xz[i + 1] - xz[i]).normalized()
			var half := lerpf(w_from, w_to, pow(float(i) / float(count - 1), 0.7)) * 0.5
			raw_bend[i] = clampf(d0.cross(d1) / maxf(run * 0.5, 1.0) * half * 8.0, -1.0, 1.0)
	var speed := _smooth(raw_speed, 3)
	var bend := _smooth(raw_bend, 2)
	# Water stands no higher than the lower of its banks. Where something was laid over the river
	# after it was carved -- a place's pad, a road's crown -- the ground beside the channel can
	# be lower than the builder's surface, and the ribbon stood over it as a plank (the Three
	# Sisters' pad lies 0.45 m under the Brindle Beck). It is lowered to the bank, never by more
	# than most of the channel's depth, and smoothly along the river.
	if provider != null and provider.has_runtime_maps():
		var drops := PackedFloat32Array()
		drops.resize(count)
		for i in count:
			var dir2 := (xz[mini(i + 1, count - 1)] - xz[maxi(i - 1, 0)])
			if dir2.length_squared() < 0.0001:
				continue
			dir2 = dir2.normalized()
			var side2 := Vector2(-dir2.y, dir2.x)
			var water_half := lerpf(w_from, w_to, pow(float(i) / float(count - 1), 0.7)) * 0.5
			var reach := water_half + 2.5
			# On the coarse map alone (Terrain3D not bound: a test, a tool, the fallback ground) an
			# eight-metre texel beside the channel averages the channel into the bank, and the bank
			# read there stood a median 0.42 m under the Larkbourne's water, which was lowered into a
			# trench for it. A texel further out is the bank itself.
			if not provider.has_terrain():
				reach += provider.runtime_spacing()
			var a := xz[i] - side2 * reach
			var b := xz[i] + side2 * reach
			var bank := minf(provider.get_height(a.x, a.y), provider.get_height(b.x, b.y))
			var depth := 1.1 + 0.2 * water_half
			drops[i] = clampf(ys[i] - (bank - 0.05), 0.0, depth * 0.6)
		drops = _smooth(drops, 2)
		for i in count:
			ys[i] -= drops[i]
	_file_segments(xz, ys, speed, cut, fade, w_from, w_to)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colours := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var along := 0.0
	for i in count:
		var t := float(i) / float(count - 1)
		var here := xz[i]
		var prev: Vector2 = xz[maxi(i - 1, 0)]
		var next: Vector2 = xz[mini(i + 1, count - 1)]
		if i > 0:
			along += here.distance_to(prev)
		var dir := (next - prev)
		if dir.length_squared() < 0.0001:
			dir = Vector2(1.0, 0.0)
		dir = dir.normalized()
		var side := Vector2(-dir.y, dir.x)
		var water_half: float = lerpf(w_from, w_to, pow(t, 0.7)) * 0.5
		var half := water_half + RIBBON_OVERHANG_M
		var y := ys[i]
		var a := here - side * half
		var b := here + side * half
		verts.append(Vector3(a.x, y, a.y))
		verts.append(Vector3(b.x, y, b.y))
		uvs.append(Vector2(-half, along))
		uvs.append(Vector2(half, along))
		uv2s.append(Vector2(speed[i], bend[i]))
		uv2s.append(Vector2(speed[i], bend[i]))
		var shown := fade[i] if fade.size() == count else 1.0
		var c := Color(dir.x * 0.5 + 0.5, dir.y * 0.5 + 0.5, clampf(water_half / 20.0, 0.0, 1.0), shown)
		colours.append(c)
		colours.append(c)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		if i < count - 1 and cut[i] == 0:
			var both_open := fade.size() == count and fade[i] <= 0.0 and fade[i + 1] <= 0.0
			if not both_open:
				var k := i * 2
				indices.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	if indices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _file_segments(xz: Array[Vector2], ys: PackedFloat32Array, speed: PackedFloat32Array, cut: PackedByteArray,
		fade: PackedFloat32Array, w_from: float, w_to: float) -> void:
	var count := xz.size()
	for i in count - 1:
		if cut[i] == 1:
			continue
		# where the ribbon has faded into a lake or the sea, the sheet's level is the water's
		if fade.size() == count and fade[i] <= 0.0 and fade[i + 1] <= 0.0:
			continue
		var half := lerpf(w_from, w_to, pow(float(i) / float(count - 1), 0.7)) * 0.5
		var seg := [xz[i], xz[i + 1], ys[i], ys[i + 1], half, speed[i], speed[i + 1]]
		var k := _river_segments.size()
		_river_segments.append(seg)
		var lo := Vector2(minf(xz[i].x, xz[i + 1].x), minf(xz[i].y, xz[i + 1].y)) - Vector2.ONE * half
		var hi := Vector2(maxf(xz[i].x, xz[i + 1].x), maxf(xz[i].y, xz[i + 1].y)) + Vector2.ONE * half
		for cz in range(floori(lo.y / SURFACE_CELL_M), floori(hi.y / SURFACE_CELL_M) + 1):
			for cx in range(floori(lo.x / SURFACE_CELL_M), floori(hi.x / SURFACE_CELL_M) + 1):
				var key := Vector2i(cx, cz)
				# a packed array is copied out of a dictionary, not referenced: append, then put back
				var list: PackedInt32Array = _segment_cells.get(key, PackedInt32Array())
				list.append(k)
				_segment_cells[key] = list


## The water at a world position, as the player meets it: `has` whether there is water there at
## all (over dry ground, or where the ground stands above the water, there is none); `y` its
## surface; `depth` from the surface down to the ground; `flow` the current (m/s, horizontal;
## zero on a lake, a pool or the sea); and `kind`, "river", "pool", "lake" or "sea".
##
## A river is its ribbon as drawn, at its own sloping surface, and a fall's pool its own level; a
## lake or the sea the level map where the water mask says there is water. The ground is the
## provider's, Terrain3D's two-metre ground where it is loaded. It costs a dictionary lookup and a
## handful of segments: cheap enough for every physics tick and a few more for the camera.
func surface_at(x: float, z: float) -> Dictionary:
	var out := {"has": false, "y": TerrainProvider.NO_WATER, "depth": 0.0, "flow": Vector3.ZERO, "kind": ""}
	if provider == null:
		return out
	var p := Vector2(x, z)
	var ground := provider.get_height(x, z)
	# a fall's pool, at its own level: its disc lies over the start of the river running out of it
	for pool in _pools:
		if p.distance_to(pool[0]) <= float(pool[1]):
			out["y"] = float(pool[2])
			out["kind"] = "pool"
			break
	# a river's ribbon, nearest first
	var best := INF
	var list: Variant = _segment_cells.get(Vector2i(floori(x / SURFACE_CELL_M), floori(z / SURFACE_CELL_M)), null)
	if list != null and str(out["kind"]) == "":
		for k in (list as PackedInt32Array):
			var seg: Array = _river_segments[k]
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var off := p.distance_to(a + ab * t)
			if off > float(seg[4]) or off >= best:
				continue
			best = off
			out["y"] = lerpf(float(seg[2]), float(seg[3]), t)
			out["flow"] = Vector3(ab.x, 0.0, ab.y).normalized() * lerpf(float(seg[5]), float(seg[6]), t)
			out["kind"] = "river"
	if str(out["kind"]) == "" and provider.is_water(x, z):
		out["y"] = provider.nearest_water_level(x, z)
		out["kind"] = "sea" if absf(float(out["y"]) - provider.sea_level) < 0.3 else "lake"
	if str(out["kind"]) == "":
		return out
	out["depth"] = maxf(float(out["y"]) - ground, 0.0)
	out["has"] = float(out["depth"]) > 0.0
	if not bool(out["has"]):
		out["kind"] = ""
		out["flow"] = Vector3.ZERO
	return out


## `surface_at` on the water the world last built; no water when there is none.
static func at(x: float, z: float) -> Dictionary:
	if current == null or not is_instance_valid(current):
		return {"has": false, "y": TerrainProvider.NO_WATER, "depth": 0.0, "flow": Vector3.ZERO, "kind": ""}
	return current.surface_at(x, z)


## Whether a point (a camera) is under the water's surface, and how far.
static func under(point: Vector3) -> float:
	var w := at(point.x, point.z)
	if not bool(w["has"]):
		return 0.0
	return maxf(float(w["y"]) - point.y, 0.0)


static func _smooth(v: PackedFloat32Array, reach: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(v.size())
	for i in v.size():
		var sum := 0.0
		var n := 0
		for j in range(maxi(i - reach, 0), mini(i + reach, v.size() - 1) + 1):
			sum += v[j]
			n += 1
		out[i] = sum / float(n)
	return out


## Tints every water surface for the region the camera is in.
func set_region_look(region_id: String) -> void:
	var look: Dictionary = REGION_WATER.get(region_id, REGION_WATER["core:region/brightwater"])
	var deep := Color.html(str(look["deep"]))
	var shallow := Color.html(str(look["shallow"]))
	var fade := float(look.get("fade", 5.0))
	for mat in _all_materials():
		mat.set_shader_parameter("deep_colour", deep)
		mat.set_shader_parameter("shallow_colour", shallow)
		mat.set_shader_parameter("reflect_strength", float(look.get("reflect", 0.85)))
		mat.set_shader_parameter("fresnel_cap", float(look.get("cap", 0.65)))
		mat.set_shader_parameter("glint_strength", float(look.get("glint", 3.0)))
		mat.set_shader_parameter("foam_strength", float(look.get("foam", 0.7)))
		if mat == _sheet_material or mat == _skirt_material:
			mat.set_shader_parameter("depth_fade_m", fade)
			mat.set_shader_parameter("wave_strength", float(look.get("waves", 0.42)))
		elif _river_materials.has(mat):
			# A river is clear running water over its bed, not a strip of the lake's deep: its
			# deep is the region's lifted a third of the way to its shallow, and it gives back less of the
			# sky, which on a narrow channel seen from its bank turned it one flat blue.
			mat.set_shader_parameter("deep_colour", deep.lerp(shallow, 0.3))
			mat.set_shader_parameter("shallow_colour", shallow.lightened(0.12))
			mat.set_shader_parameter("reflect_strength", float(look.get("reflect", 0.85)) * RIVER_REFLECT)
	# under the surface the region's deep water, a little darker
	if underwater != null:
		# the shallows' colour: the deep's is all but black in linear light, and under the surface
		# the water round the eye is lit through from above
		underwater.water_colour = shallow.lerp(deep, 0.25)
	# the swash that runs up the shore is the shallows' own water
	if shore != null and shore.material != null:
		shore.material.set_shader_parameter("water_colour", shallow)
		shore.material.set_shader_parameter("strength", clampf(0.55 + float(look.get("foam", 0.7)) * 0.6, 0.6, 1.0))
		# how dark the damp band goes, the region's to say ("damp", 1 by default)
		shore.material.set_shader_parameter("damp", float(look.get("damp", 1.0)))
	# the falls and their pools in the region's water, and those a place raises later
	if falls != null:
		falls.set_colours(deep, shallow)
	else:
		RiverFalls.deep_colour = deep
		RiverFalls.shallow_colour = shallow


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section != "graphics":
		return
	if key == "water_quality":
		apply_quality(int(value))
	elif key == "water_reflections":
		apply_reflections()


## Water quality, live: the sheet re-cut to its new subdivision and every surface's ripple
## detail set. Nothing else is rebuilt.
func apply_quality(q: int) -> void:
	quality = clampi(q, 0, 3)
	sheet_subdivisions = QUALITY_SUBDIVISIONS[quality]
	if sheet != null and sheet.mesh is PlaneMesh:
		(sheet.mesh as PlaneMesh).subdivide_width = sheet_subdivisions
		(sheet.mesh as PlaneMesh).subdivide_depth = sheet_subdivisions
	elif sheet != null:
		var cells := water_mesh(QUALITY_CELL_M[quality])
		if cells != null:
			sheet.mesh = cells
	for mat in _all_materials():
		mat.set_shader_parameter("detail", QUALITY_DETAIL[quality])
		mat.set_shader_parameter("mirror_steps", QUALITY_MIRROR_STEPS[quality])


func _all_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if _sheet_material:
		out.append(_sheet_material)
	if _skirt_material:
		out.append(_skirt_material)
	out.append_array(_river_materials)
	return out
