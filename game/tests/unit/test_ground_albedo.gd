extends TestCase
## The ground as the sun meets it. Terrain3D draws each slot as its albedo texture times the
## asset's albedo_color, so a texture painted near black and then multiplied down again draws as a
## hole in the ground on every renderer. The Stair Head, where a new game begins, stood on ash
## that drew at 0.008 (a texture averaging 0.017, times 0.45): the player's first sight of the
## country was black ground under lit tents and bone-white grass. tools/world/ground_albedo.py
## prints the same table, with what the ground is made of at any point of a built world.

const ASSETS := "res://world/terrain_assets.tres"
const IMPORTER := "res://tools_gd/import_terrain.gd"
## Below this a material reads as no ground at all under Cinderlea's low sun. The darkest honest
## materials -- peat, fused stone, the black soil of the ash heath -- sit between it and 0.05.
const FLOOR := 0.02
## Every 16th texel each way: 4 096 samples of a 1024 tile is plenty for a mean.
const STEP := 16


## Mean linear luminance of a PNG in the project, read from its bytes (headless has no GPU copy).
static func mean_linear(path: String) -> float:
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return -1.0
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), STEP):
		for x in range(0, img.get_width(), STEP):
			sum += img.get_pixel(x, y).srgb_to_linear().get_luminance()
			n += 1
	return sum / maxf(float(n), 1.0)


## {name: {"texture": mean linear albedo of the texture, "value": albedo_color, "albedo": both}}
static func slots() -> Dictionary:
	var out := {}
	if not ClassDB.class_exists("Terrain3DAssets") or not ResourceLoader.exists(ASSETS):
		return out
	# a fresh copy: the world frees the source textures of the one it draws with
	var assets: Resource = ResourceLoader.load(ASSETS, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	for i in int(assets.call("get_texture_count")):
		var tex: Resource = assets.call("get_texture", i)
		if tex == null:
			continue
		var albedo: Texture2D = tex.get("albedo_texture")
		var t := mean_linear(albedo.resource_path) if albedo != null else -1.0
		var v: float = (tex.get("albedo_color") as Color).get_luminance()
		out[str(tex.get("name"))] = {"texture": t, "value": v, "albedo": t * v}
	return out


func test_no_ground_draws_black() -> void:
	var table := slots()
	if table.is_empty():
		return      # no Terrain3D on this machine: the coarse ground has its own colours
	assert_eq(table.size(), 23, "every slot of CONTRACTS §5 is in the terrain assets")
	for name in table:
		var s: Dictionary = table[name]
		assert_gt(float(s["texture"]), 0.0, "%s's albedo texture reads" % name)
		assert_gt(float(s["albedo"]), FLOOR, "%s draws at %.4f (texture %.3f x %.2f): darker than %.2f reads as a hole in the ground"
			% [name, float(s["albedo"]), float(s["texture"]), float(s["value"]), FLOOR])


## Black soil and grey grass (WORLD_BIBLE 6.6): the ash is the darker of the two, but ground, not
## a void -- within a factor of two of the grass it grows among.
func test_the_ash_is_darker_than_the_grass_but_still_ground() -> void:
	var table := slots()
	if table.is_empty():
		return
	var ash := float(table["ash_soil"]["albedo"])
	var grass := float(table["grey_grass"]["albedo"])
	assert_true(ash < grass, "the black soil (%.4f) is darker than the grey grass (%.4f)" % [ash, grass])
	assert_gt(ash, grass * 0.5, "the ash is within a factor of two of the grass")


## The importer's table and the resource agree, so building the terrain again keeps the ground
## as it is drawn now instead of putting the old values back.
func test_the_importer_writes_what_the_ground_draws_with() -> void:
	var table := slots()
	if table.is_empty():
		return
	var consts: Dictionary = (load(IMPORTER) as Script).get_script_constant_map()
	for slot in consts["SLOTS"]:
		var name := str(slot["name"])
		assert_has(table, name, "%s is in the terrain assets" % name)
		if table.has(name):
			assert_near(float(table[name]["value"]), float(slot.get("value", 1.0)), 0.001,
				"%s: import_terrain.gd's value and terrain_assets.tres's albedo_color" % name)
