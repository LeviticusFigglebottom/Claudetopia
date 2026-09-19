extends Node
## Imports the world builder's maps into Terrain3D region files, and builds the terrain
## asset list and material. Run headlessly:
##
##   godot --headless --path game --audio-driver Dummy res://tools_gd/import_terrain.tscn
##
## Reads  res://world/generated/{world_manifest.json, heights.r32, control.u32, color.rgba8}
## Writes res://terrain_data/terrain3d*.res   (gitignored build artifact)
##        res://world/terrain_assets.tres     (Terrain3DAssets: the 21 slots of CONTRACTS §5)
##        res://world/terrain_material.tres   (Terrain3DMaterial with our shader settings)
##
## The control map arrives pre-packed by the Python builder (see worldgen/output.pack_control),
## so nothing here touches a pixel: 4096² images are handed to Terrain3D as raw byte arrays.

const GENERATED := "res://world/generated"
const DATA_DIR := "res://terrain_data"
const ASSETS_PATH := "res://world/terrain_assets.tres"
const MATERIAL_PATH := "res://world/terrain_material.tres"
const TEXTURE_DIR := "res://assets/textures/terrain"
const REGION_SIZE := 1024
const VERTEX_SPACING := 2.0

## Slot order is binding (docs/CONTRACTS.md §5); uv_scale is 1 / tile size in metres.
const SLOTS: Array = [
	{"name": "vale_grass", "tile_m": 2.6},
	{"name": "chalk", "tile_m": 3.0},
	{"name": "dirt_path", "tile_m": 2.8},
	{"name": "mud", "tile_m": 2.4},
	{"name": "peat", "tile_m": 2.6},
	{"name": "forest_floor", "tile_m": 2.8},
	{"name": "moss", "tile_m": 1.8},
	{"name": "granite", "tile_m": 3.4},
	{"name": "limestone", "tile_m": 3.6},
	{"name": "scree", "tile_m": 2.4},
	{"name": "snow", "tile_m": 3.2},
	{"name": "heather", "tile_m": 2.2},
	{"name": "ash_soil", "tile_m": 2.6},
	{"name": "grey_grass", "tile_m": 2.4},
	{"name": "fused_stone", "tile_m": 4.0},
	{"name": "shingle", "tile_m": 2.0},
	{"name": "cobbles", "tile_m": 2.6},
	{"name": "barley", "tile_m": 2.4},
	{"name": "orchard_grass", "tile_m": 2.4},
	{"name": "lake_bed", "tile_m": 2.8},
	{"name": "sand_flats", "tile_m": 3.0},
]


func _ready() -> void:
	var code: int = await run()
	get_tree().quit(code)


func run() -> int:
	var t0 := Time.get_ticks_msec()
	var manifest := _read_manifest()
	if manifest.is_empty():
		return 1
	var grid := int(manifest.get("grid", 4096))
	var origin: Array = manifest.get("origin", [-4096, -4096])
	if not ClassDB.class_exists("Terrain3D"):
		Log.error("ImportTerrain", "Terrain3D extension is not available")
		return 1

	var assets := _build_assets()
	if assets == null:
		return 1
	var material := _build_material()

	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
	terrain.set("material", material)
	terrain.set("assets", assets)
	add_child(terrain)
	# Terrain3D builds its data object when the node enters the world, one frame after
	# add_child, so everything below has to wait for that frame.
	await get_tree().process_frame
	_clear_data_dir()
	terrain.set("data_directory", DATA_DIR)
	# region_size and vertex_spacing must be set before importing, and region_size only
	# takes effect through change_region_size() once the data object exists.
	terrain.call("change_region_size", REGION_SIZE)
	terrain.set("vertex_spacing", VERTEX_SPACING)
	if int(terrain.get("region_size")) != REGION_SIZE:
		Log.error("ImportTerrain", "region size stuck at %d (wanted %d)" % [int(terrain.get("region_size")), REGION_SIZE])
		return 1

	var height_img := _image_rf("%s/heights.r32" % GENERATED, grid)
	var control_img := _image_rf("%s/control.u32" % GENERATED, grid)
	var colour_img := _image_rgba("%s/color.rgba8" % GENERATED, grid)
	if height_img == null:
		Log.error("ImportTerrain", "heights.r32 missing or the wrong size; run tools/world/build_world.py")
		return 1
	var images: Array[Image] = [height_img, control_img, colour_img]
	var data: Object = terrain.get("data")
	var pos := Vector3(float(origin[0]), 0.0, float(origin[1]))
	data.call("import_images", images, pos, 0.0, 1.0)
	data.call("calc_height_range", true)
	var regions: int = data.call("get_region_count")
	data.call("save_directory", DATA_DIR)
	var range_v: Vector2 = data.call("get_height_range")
	Log.info("ImportTerrain", "%d regions, height range %.1f..%.1f m, %d ms"
		% [regions, range_v.x, range_v.y, Time.get_ticks_msec() - t0])
	# a last sanity check: heights at the centre of the world and at a known place
	var h_centre: float = data.call("get_height", Vector3(0.0, 0.0, 0.0))
	Log.info("ImportTerrain", "height at world centre (the Mere): %.2f m" % h_centre)
	if regions <= 0:
		Log.error("ImportTerrain", "no regions were created")
		return 1
	return 0


## The terrain data directory is a build artifact: start from empty so a rebuild cannot
## inherit regions of a different size from a previous run.
func _clear_data_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DATA_DIR)
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with("terrain3d") and (f.ends_with(".res") or f.ends_with(".tres")):
			dir.remove(f)


func _read_manifest() -> Dictionary:
	var path := "%s/world_manifest.json" % GENERATED
	if not FileAccess.file_exists(path):
		Log.error("ImportTerrain", "%s missing; run tools/world/build_world.py first" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.error("ImportTerrain", "%s is not valid JSON" % path)
		return {}
	return parsed


## A raw float32 (or packed uint32, which Terrain3D also stores in FORMAT_RF) map.
func _image_rf(path: String, grid: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() != grid * grid * 4:
		if bytes.size() > 0:
			Log.error("ImportTerrain", "%s is %d bytes, expected %d" % [path, bytes.size(), grid * grid * 4])
		return null
	return Image.create_from_data(grid, grid, false, Image.FORMAT_RF, bytes)


func _image_rgba(path: String, grid: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() != grid * grid * 4:
		return null
	var img := Image.create_from_data(grid, grid, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	return img


func _build_assets() -> Resource:
	var assets: Resource = ClassDB.instantiate("Terrain3DAssets")
	var missing: Array[String] = []
	for i in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		var name: String = slot["name"]
		var albedo_path := "%s/%s_albedo_height.png" % [TEXTURE_DIR, name]
		var normal_path := "%s/%s_normal_rough.png" % [TEXTURE_DIR, name]
		if not ResourceLoader.exists(albedo_path):
			missing.append(name)
			continue
		var tex: Resource = ClassDB.instantiate("Terrain3DTextureAsset")
		tex.set("name", name)
		tex.set("id", i)
		tex.set("albedo_texture", load(albedo_path))
		if ResourceLoader.exists(normal_path):
			tex.set("normal_texture", load(normal_path))
		tex.set("uv_scale", 1.0 / float(slot.get("tile_m", 2.5)))
		tex.set("detiling_rotation", 0.12)
		tex.set("detiling_shift", 0.08)
		tex.set("normal_depth", float(slot.get("normal_depth", 0.55)))
		tex.set("ao_strength", float(slot.get("ao", 0.5)))
		tex.set("roughness", float(slot.get("roughness_mod", 0.0)))
		assets.call("set_texture", i, tex)
	if not missing.is_empty():
		Log.error("ImportTerrain", "missing terrain textures: %s (run tools/world/gen_terrain_textures.py)"
			% ", ".join(missing))
		return null
	assets.call("update_texture_list")
	DirAccess.make_dir_recursive_absolute(ASSETS_PATH.get_base_dir())
	var err := ResourceSaver.save(assets, ASSETS_PATH)
	if err != OK:
		Log.error("ImportTerrain", "cannot save %s: %s" % [ASSETS_PATH, error_string(err)])
		return null
	Log.info("ImportTerrain", "%d texture slots -> %s" % [SLOTS.size(), ASSETS_PATH])
	return assets


func _build_material() -> Resource:
	var mat: Resource = ClassDB.instantiate("Terrain3DMaterial")
	mat.set("world_background", 1)            # FLAT: the sea and the Hush continue past the regions
	mat.set("auto_shader", false)             # our control map is authored, not automatic
	mat.set("dual_scaling", false)
	mat.set("texture_filtering", 0)           # linear
	mat.call("set_shader_param", "blend_sharpness", 0.82)
	mat.call("set_shader_param", "enable_macro_variation", true)
	mat.call("set_shader_param", "macro_variation1", Color(0.94, 0.96, 0.90))
	mat.call("set_shader_param", "macro_variation2", Color(0.92, 0.90, 0.86))
	mat.call("set_shader_param", "macro_variation_slope", 0.4)
	mat.call("set_shader_param", "enable_projection", true)
	mat.call("set_shader_param", "mipmap_bias", 0.95)
	mat.call("set_shader_param", "bias_distance", 420.0)
	var err := ResourceSaver.save(mat, MATERIAL_PATH)
	if err != OK:
		Log.warn("ImportTerrain", "cannot save %s: %s" % [MATERIAL_PATH, error_string(err)])
	return mat
