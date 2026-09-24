extends TestCase
## The water's look by region, and the mirror the setting turns off. Every lake and sea in the
## country ran at one wave height, rough enough to scramble whatever the water mirrored into
## streaks, so the Mere -- Lake Glass -- could not hold its island upside down; and the setting
## that turned the mirror off only zeroed a uniform, which still had the frame copied for it.

const REGIONS := ["core:region/hearthvale", "core:region/brightwater", "core:region/sedgemire",
	"core:region/briarwold", "core:region/skerrow", "core:region/cinderlea"]


func _surface() -> WaterSurface:
	# the materials alone, as the builder would make them, without a world under them
	var ws := WaterSurface.new()
	ws._sheet_material = ShaderMaterial.new()
	ws._sheet_material.shader = WaterSurface.shader_for(true)
	var river := ShaderMaterial.new()
	river.shader = WaterSurface.shader_for(true, true)
	ws._river_materials.append(river)
	return ws


func test_every_region_has_its_water() -> void:
	for id in REGIONS:
		assert_true(WaterSurface.REGION_WATER.has(id), "%s has a water look" % id)
		var look: Dictionary = WaterSurface.REGION_WATER[id]
		for key in ["deep", "shallow", "fade", "reflect", "cap", "glint", "waves", "foam"]:
			assert_true(look.has(key), "%s names its %s" % [id, key])
		assert_true(float(look["cap"]) > 0.0 and float(look["cap"]) <= 1.0, "%s: a Fresnel cap is a share" % id)


## Lake Glass is calm enough to mirror, and gives back more at the grazing angle than the sea;
## the Grey Sea stays the roughest water in the country.
func test_the_mere_is_calm_and_the_sea_is_not() -> void:
	var mere: Dictionary = WaterSurface.REGION_WATER["core:region/brightwater"]
	var sea: Dictionary = WaterSurface.REGION_WATER["core:region/skerrow"]
	assert_true(float(mere["waves"]) <= 0.2, "the Mere's waves are low enough to hold a reflection")
	assert_true(float(mere["cap"]) > float(sea["cap"]), "the Mere mirrors more than the sea")
	for id in REGIONS:
		assert_true(float(WaterSurface.REGION_WATER[id]["waves"]) <= float(sea["waves"]),
			"%s is no rougher than the open sea" % id)
		assert_true(float(WaterSurface.REGION_WATER[id]["foam"]) <= float(sea["foam"]),
			"%s raises no more foam than the sea's surf" % id)
	assert_true(float(WaterSurface.REGION_WATER["core:region/sedgemire"]["foam"]) <= 0.1,
		"the marsh's still pools raise no surf")


## The region's waves go on the lake and the sea; a river keeps its own, running with the current.
func test_the_region_sets_the_open_water_and_leaves_the_rivers() -> void:
	var ws := _surface()
	var river: ShaderMaterial = ws._river_materials[0]
	var before: Variant = river.get_shader_parameter("wave_strength")
	ws.set_region_look("core:region/brightwater")
	assert_near(float(ws._sheet_material.get_shader_parameter("wave_strength")), 0.14, 0.0001,
		"the Mere's sheet takes the Mere's waves")
	assert_near(float(ws._sheet_material.get_shader_parameter("fresnel_cap")), 0.85, 0.0001,
		"and its cap")
	assert_eq(river.get_shader_parameter("wave_strength"), before, "a river keeps its own waves")
	assert_near(float(river.get_shader_parameter("fresnel_cap")), 0.85, 0.0001,
		"though it mirrors like the water round it")
	ws.free()


## Turning reflections off takes the screen texture out of the shader, so the frame is not copied
## for it, and keeps every colour the region set; turning them on puts it back.
func test_turning_the_mirror_off_takes_the_frame_copy_away() -> void:
	var on := WaterSurface.shader_for(true)
	var off := WaterSurface.shader_for(false)
	assert_true(on.code.contains("hint_screen_texture"), "the mirrored shader reads the frame")
	assert_true(off.code.contains("#define WATER_NO_MIRROR"), "the other is built without the lookup")
	assert_true(WaterSurface.shader_for(false) == off, "and built once")
	var names := []
	for u in off.get_shader_uniform_list():
		names.append(str(u["name"]))
	assert_false(names.has("screen_tex"), "the mirrorless shader does not name the screen texture")
	assert_true(names.has("deep_colour"), "but it has everything else")

	var had: Variant = Settings.get_value("graphics", "water_reflections", true)
	var ws := _surface()
	ws.set_region_look("core:region/sedgemire")
	var deep: Variant = ws._sheet_material.get_shader_parameter("deep_colour")
	Settings.set_value("graphics", "water_reflections", false, false)
	ws.apply_reflections()
	assert_true(ws._sheet_material.shader == off, "reflections off: the sheet is on the mirrorless shader")
	assert_true(ws._river_materials[0].shader == WaterSurface.shader_for(false, true), "and so is every river")
	assert_true(ws._river_materials[0].shader.code.contains("#define WATER_RIVER"), "on the river's own flow-mapped variant")
	assert_eq(ws._sheet_material.get_shader_parameter("deep_colour"), deep, "the marsh keeps its colour")
	assert_near(float(ws._sheet_material.get_shader_parameter("mirror")), 0.0, 0.0001, "and its mirror is out")
	Settings.set_value("graphics", "water_reflections", true, false)
	ws.apply_reflections()
	assert_true(ws._sheet_material.shader == on, "reflections on: the mirror is back")
	assert_eq(ws._sheet_material.get_shader_parameter("deep_colour"), deep, "with the colour still on it")
	Settings.set_value("graphics", "water_reflections", had, false)
	ws.free()


## The builder writes the water mask as 0 and 1, and a texture reads a byte as byte/255: a wet
## texel was 0.004 to the shader, under its 0.5 test everywhere, so every lake and the sea were
## discarded and the Mere was its own lake bed. The mask is stretched to 255 as it is loaded.
func test_the_water_mask_is_stretched_to_what_a_shader_reads() -> void:
	var raw := PackedByteArray([0, 1, 1, 0, 1])
	assert_eq(WaterSurface.mask_bytes(raw), PackedByteArray([0, 255, 255, 0, 255]), "a wet texel is 255")
	var full := PackedByteArray([0, 255, 0])
	assert_eq(WaterSurface.mask_bytes(full), full, "a mask already written as 0 and 255 is left alone")
	assert_eq(raw, PackedByteArray([0, 1, 1, 0, 1]), "the bytes read from the file are not changed in place")


## The water mask the game loads, loaded the way the game loads it, must read as water in the
## shader wherever the file says water: a builder and a loader that disagree about the byte for
## "wet" drew no lake or sea at all, and nothing said so. (docs/CONTRACTS.md 6 has the convention.)
func test_the_water_mask_the_game_loads_reads_as_water_where_the_file_says_so() -> void:
	var manifest_path := "%s/world_manifest.json" % WaterSurface.GENERATED
	if not FileAccess.file_exists(manifest_path):
		print("  (world data missing: water mask test skipped)")
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	assert_true(manifest is Dictionary, "the world manifest parses")
	var n := int(((manifest as Dictionary).get("runtime", {}) as Dictionary).get("grid", 1024))
	var path := WaterSurface.mask_path(manifest)
	var raw := FileAccess.get_file_as_bytes(path)
	assert_eq(raw.size(), n * n, "the mask is %d x %d bytes" % [n, n])
	var img := WaterSurface.mask_image(path, n)
	assert_true(img != null, "the mask loads")
	if img == null:
		return
	var wet := 0
	var dry_in_shader := 0
	for i in range(0, raw.size(), 7):
		if raw[i] == 0:
			continue
		wet += 1
		if img.get_pixel(i % n, i / n).r < 0.5:
			dry_in_shader += 1
	assert_gt(wet, 0, "the world has water in it")
	assert_eq(dry_in_shader, 0, "%d of %d wet texels would be discarded by the water shader" % [dry_in_shader, wet])


## A river's ribbon stands on the water surface the builder gives at each of its points
## (rivers.json `surface_m`, CONTRACTS 6), not on a straight ramp from its source to its mouth:
## the Skerrow Water falls 500 m in its gorge and runs nearly level to the Mere, and drawn on the
## ramp it stood 158 m in the air over the dales. Without `surface_m` the old ramp is kept.
func test_a_river_ribbon_stands_on_its_own_surface() -> void:
	var ws := WaterSurface.new()
	var entry := {"id": "test:river/gorge", "points": [[0.0, 0.0], [0.0, 100.0], [0.0, 200.0]],
		"width_m": 6.0, "surface_from_m": 500.0, "surface_to_m": 8.0, "surface_m": [500.0, 20.0, 8.0]}
	var mesh: ArrayMesh = ws._river_mesh(entry)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 6, "two vertices a point")
	assert_near(verts[2].y, 20.0, 0.01, "the middle of the gorge river is at its own surface, not the ramp's 254 m")
	assert_near(verts[3].y, 20.0, 0.01, "and not lifted off it")
	entry.erase("surface_m")
	var ramp: ArrayMesh = ws._river_mesh(entry)
	var rv: PackedVector3Array = ramp.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_near(rv[2].y, 254.0, 0.01, "a file without surface_m keeps the ramp")
	ws.free()


## The shore classes are read by name (runtime.shore_classes, CONTRACTS 6), so a build that
## writes them in another order still breaks surf on rock and lays none on mud.
func test_the_shore_classes_are_read_by_name() -> void:
	var raw := PackedByteArray([0, 1, 2, 3])
	assert_eq(WaterSurface.shore_bytes(raw, []), raw, "no names: the contract's own order")
	assert_eq(WaterSurface.shore_bytes(raw, WaterSurface.SHORE_CLASSES), raw, "the contract's order is kept")
	var other := ["none", "mud", "rock", "glass"]
	assert_eq(WaterSurface.shore_bytes(raw, other), PackedByteArray([0, 5, 3, 0]),
		"mud and rock by name, a class the water does not know as none")


## The lakes and the sea are laid as cells over the water, each corner at the level of the water
## under it: every wet texel is covered, and no corner stands anywhere but at its water's level.
## The plane before it took its level at vertices ninety metres apart, and Weaver's Linn stood
## 13 m over itself under its fall.
func test_the_sheet_lies_on_every_water_at_its_own_level() -> void:
	var provider := TerrainProvider.new()
	if not provider.load_data() or not provider.has_runtime_maps():
		print("  (world data missing: sheet test skipped)")
		provider.free()
		return
	var ws := WaterSurface.new()
	ws.provider = provider
	var cell: float = WaterSurface.QUALITY_CELL_M[2]
	var mesh := ws.water_mesh(cell)
	assert_true(mesh != null, "the sheet is laid")
	if mesh == null:
		ws.free()
		provider.free()
		return
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var off := 0
	for i in range(0, verts.size(), 7):
		var v := verts[i]
		if absf(v.y - provider.nearest_water_level(v.x, v.z)) > 0.001:
			off += 1
	assert_eq(off, 0, "every corner at its water's level")
	# which cells the quads cover
	var cn := int(ceil(provider.size_m / cell))
	var covered := PackedByteArray()
	covered.resize(cn * cn)
	for t in range(0, idx.size(), 6):
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for k in 6:
			var p := verts[idx[t + k]]
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		for cz in range(int(round((lo.y - provider.origin.y) / cell)), int(round((hi.y - provider.origin.y) / cell))):
			for cx in range(int(round((lo.x - provider.origin.x) / cell)), int(round((hi.x - provider.origin.x) / cell))):
				covered[cz * cn + cx] = 1
	var n := provider.runtime_grid()
	var sp := provider.runtime_spacing()
	var wet := provider.runtime_water()
	var bare := 0
	var count := 0
	for j in range(0, n, 3):
		for i in range(0, n, 3):
			if wet[j * n + i] == 0:
				continue
			count += 1
			var cx := int((float(i) + 0.5) * sp / cell)
			var cz := int((float(j) + 0.5) * sp / cell)
			if covered[cz * cn + cx] == 0:
				bare += 1
	assert_gt(count, 1000, "the world has water")
	assert_eq(bare, 0, "%d of %d wet texels with no sheet over them" % [bare, count])
	ws.free()
	provider.free()
