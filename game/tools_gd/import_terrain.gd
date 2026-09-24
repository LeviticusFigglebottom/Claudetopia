extends Node
## Imports the world builder's maps into Terrain3D region files, and builds the terrain
## asset list and material. Run headlessly:
##
##   godot --headless --path game --audio-driver Dummy res://tools_gd/import_terrain.tscn
##
## Reads  res://world/generated/{world_manifest.json, heights.r32, control.u32, color.rgba8}
## Writes res://terrain_data/terrain3d*.res   (gitignored build artifact)
##        res://world/terrain_assets.tres     (Terrain3DAssets: the 21 slots of CONTRACTS §5)
##
## The control map arrives pre-packed by the Python builder (see worldgen/output.pack_control),
## so nothing here touches a pixel: 4096² images are handed to Terrain3D as raw byte arrays.

const GENERATED := "res://world/generated"
const DATA_DIR := "res://terrain_data"
const ASSETS_PATH := "res://world/terrain_assets.tres"
const TEXTURE_DIR := "res://assets/textures/terrain"
const REGION_SIZE := 1024
## The metres between two height samples when the manifest does not say (the full 4096 build's).
## A build says it as `spacing_m`: 2 at 4096, 8 for a 1024 preview. Fixed at 2, a 1024 build went
## in as a 2 km square in the north-west corner of the world, one region, and the height at the
## world's centre came back NaN: every in-engine look at a preview world stood on nothing.
const VERTEX_SPACING := 2.0

## Slot order is binding (docs/CONTRACTS.md §5); uv_scale is 1 / tile size in metres.
## `value` is an albedo multiplier (Terrain3DTextureAsset.albedo_color): the painted textures
## are authored at a comfortable value for viewing, and this brings them down to the ground
## albedo the atmosphere's sun expects -- about 0.4-0.6 for rock and grass, higher for snow.
## What is drawn is the texture's mean in linear light times this, and nothing may draw under
## 0.02 (tests/unit/test_ground_albedo.gd; tools/world/ground_albedo.py prints the table). The
## ash was painted as charcoal and multiplied down to 0.008 -- black ground at the Stair Head --
## and the fused stone, painted dark as glass, drew at 0.020; it is let up to 0.035.
## `roughness_mod` nudges the material's roughness (the fused Oroth stone would otherwise be
## a mirror; ash and lake bed want the opposite).
const SLOTS: Array = [
	{"name": "vale_grass", "tile_m": 2.6, "value": 0.42, "roughness_mod": 0.0},
	{"name": "chalk", "tile_m": 3.0, "value": 0.42, "roughness_mod": 0.0},
	{"name": "dirt_path", "tile_m": 2.8, "value": 0.52, "roughness_mod": 0.0},
	{"name": "mud", "tile_m": 2.4, "value": 0.56, "roughness_mod": -0.05},
	{"name": "peat", "tile_m": 2.6, "value": 0.58, "roughness_mod": 0.0},
	{"name": "forest_floor", "tile_m": 2.8, "value": 0.50, "roughness_mod": 0.0},
	{"name": "moss", "tile_m": 1.8, "value": 0.44, "roughness_mod": 0.0},
	{"name": "granite", "tile_m": 3.4, "value": 0.58, "roughness_mod": 0.0},
	{"name": "limestone", "tile_m": 3.6, "value": 0.40, "roughness_mod": 0.0},
	{"name": "scree", "tile_m": 2.4, "value": 0.50, "roughness_mod": 0.0},
	{"name": "snow", "tile_m": 3.2, "value": 0.58, "roughness_mod": 0.18},
	{"name": "heather", "tile_m": 2.2, "value": 0.51, "roughness_mod": 0.0},
	{"name": "ash_soil", "tile_m": 2.6, "value": 0.52, "roughness_mod": 0.05},
	{"name": "grey_grass", "tile_m": 2.4, "value": 0.46, "roughness_mod": 0.0},
	{"name": "fused_stone", "tile_m": 4.0, "value": 0.75, "roughness_mod": 0.4},
	{"name": "shingle", "tile_m": 3.2, "value": 0.51, "roughness_mod": 0.0},
	{"name": "cobbles", "tile_m": 2.6, "value": 0.53, "roughness_mod": 0.0},
	{"name": "barley", "tile_m": 2.4, "value": 0.49, "roughness_mod": 0.0},
	{"name": "orchard_grass", "tile_m": 2.4, "value": 0.44, "roughness_mod": 0.0},
	{"name": "lake_bed", "tile_m": 2.8, "value": 0.42, "roughness_mod": 0.1},
	{"name": "sand_flats", "tile_m": 3.0, "value": 0.50, "roughness_mod": 0.0},
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

	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
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
	terrain.set("vertex_spacing", spacing_of(manifest, grid))
	_configure_material(terrain.get("material"))
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


## The metres between two of the build's height samples: its own `spacing_m`, or its size over its
## grid, or VERTEX_SPACING.
static func spacing_of(manifest: Dictionary, grid: int) -> float:
	if manifest.has("spacing_m"):
		return float(manifest["spacing_m"])
	if manifest.has("size_m") and grid > 0:
		return float(manifest["size_m"]) / float(grid)
	return VERTEX_SPACING


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
		var v := float(slot.get("value", 1.0))
		tex.set("albedo_color", Color(v, v, v, 1.0))
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


## The terrain node makes its own Terrain3DMaterial; we only set it up. (Instantiating a
## detached one and saving it as a resource makes Terrain3D try to load an empty shader path.)
func _configure_material(mat: Object) -> void:
	if mat == null:
		return
	# NONE, not FLAT. Terrain3D's FLAT background does not discard vertices outside the
	# regions: it keeps drawing, sampling the edge region with a wrapped coordinate, which
	# from any hill reads as a flat grey shelf across the distance with a visible corner,
	# occluding the land behind it. NONE discards them, so the land simply ends -- and the
	# sea keeps going because WaterSurface draws a skirt out past the horizon.
	mat.set("world_background", 0)
	mat.set("auto_shader", false)             # our control map is authored, not automatic
	mat.set("dual_scaling", false)
	mat.set("texture_filtering", 0)           # linear
	mat.set("show_checkered", false)
	mat.call("set_shader_param", "blend_sharpness", 0.34)
	mat.call("set_shader_param", "enable_macro_variation", true)
	# the tiling's breakup at a distance: two large noise fields darken and warm the ground by up
	# to an eighth (a twentieth left the tile repeat readable across a hillside)
	mat.call("set_shader_param", "macro_variation1", Color(0.88, 0.90, 0.84))
	mat.call("set_shader_param", "macro_variation2", Color(0.88, 0.84, 0.79))
	mat.call("set_shader_param", "macro_variation_slope", 0.4)
	mat.call("set_shader_param", "enable_projection", true)
	mat.call("set_shader_param", "mipmap_bias", 0.95)
	mat.call("set_shader_param", "bias_distance", 420.0)
