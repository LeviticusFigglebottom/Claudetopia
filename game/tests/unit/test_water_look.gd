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
	river.shader = WaterSurface.shader_for(true)
	ws._river_materials.append(river)
	return ws


func test_every_region_has_its_water() -> void:
	for id in REGIONS:
		assert_true(WaterSurface.REGION_WATER.has(id), "%s has a water look" % id)
		var look: Dictionary = WaterSurface.REGION_WATER[id]
		for key in ["deep", "shallow", "fade", "reflect", "cap", "glint", "waves"]:
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

	var had: Variant = Settings.get_value("video", "water_reflections", true)
	var ws := _surface()
	ws.set_region_look("core:region/sedgemire")
	var deep: Variant = ws._sheet_material.get_shader_parameter("deep_colour")
	Settings.set_value("video", "water_reflections", false, false)
	ws.apply_reflections()
	assert_true(ws._sheet_material.shader == off, "reflections off: the sheet is on the mirrorless shader")
	assert_true(ws._river_materials[0].shader == off, "and so is every river")
	assert_eq(ws._sheet_material.get_shader_parameter("deep_colour"), deep, "the marsh keeps its colour")
	assert_near(float(ws._sheet_material.get_shader_parameter("mirror")), 0.0, 0.0001, "and its mirror is out")
	Settings.set_value("video", "water_reflections", true, false)
	ws.apply_reflections()
	assert_true(ws._sheet_material.shader == on, "reflections on: the mirror is back")
	assert_eq(ws._sheet_material.get_shader_parameter("deep_colour"), deep, "with the colour still on it")
	Settings.set_value("video", "water_reflections", had, false)
	ws.free()
