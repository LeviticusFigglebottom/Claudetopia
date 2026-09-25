extends TestCase
## Each region's mist lies on its own ground (world/ground_mist.gd, assets/shaders/ground_mist.gdshader)
## and each region's lamps burn in its own colour (NightLights.region_lamp): the tables the shader
## and the glow read are the pack's, in the world's region order, and the switches turn them off.

const REGIONS := ["core:region/hearthvale", "core:region/brightwater", "core:region/sedgemire",
		"core:region/briarwold", "core:region/skerrow", "core:region/cinderlea"]


func test_every_region_names_its_mist_and_its_lamps() -> void:
	for id in REGIONS:
		if not ContentDB.has(id):
			continue
		var light: Dictionary = ContentDB.get_def(id).get("identity", {}).get("light", {})
		for key in ["mist_color", "mist_density", "mist_depth", "mist_morning", "mist_water", "lamp_tint", "lamp_energy"]:
			assert_true(light.has(key), "%s's light names %s" % [id, key])


func test_the_marsh_is_the_mistiest_and_the_fells_the_clearest() -> void:
	var dens := {}
	for id in REGIONS:
		dens[id] = float(GroundMist.layer_of(id)["mist_density"])
	for id in REGIONS:
		if id != "core:region/sedgemire":
			assert_gt(dens["core:region/sedgemire"], dens[id], "the Sedgemire's mist is thicker than %s's" % id)
		if id != "core:region/skerrow":
			assert_gt(dens[id], dens["core:region/skerrow"], "%s's mist is thicker than the fells'" % id)


func test_the_table_is_in_the_worlds_order() -> void:
	var order := ["core:region/cinderlea", "core:region/sedgemire"]
	var img := GroundMist.table(order)
	assert_eq(img.get_width(), 2)
	var ash := GroundMist.layer_of("core:region/cinderlea")
	var marsh := GroundMist.layer_of("core:region/sedgemire")
	assert_near(img.get_pixel(0, 0).a, float(ash["mist_density"]) * 10.0, 0.0001, "column 0 is Cinderlea's")
	assert_near(img.get_pixel(1, 0).a, float(marsh["mist_density"]) * 10.0, 0.0001, "column 1 is the marsh's")
	assert_near(img.get_pixel(1, 1).r, float(marsh["mist_depth"]) / 16.0, 0.0001, "and its depth")
	var none := GroundMist.table(["core:region/nowhere"])
	assert_eq(none.get_pixel(0, 0).a, 0.0, "a region that says nothing has no mist")


func test_the_mist_lies_on_the_water_and_not_under_it() -> void:
	var provider := World.terrain()
	if provider == null or not provider.has_runtime_maps() or provider.runtime_levels().is_empty():
		return
	var levels := GroundMist.water_levels(provider)
	var wet := provider.runtime_water()
	var all := provider.runtime_levels()
	assert_eq(levels.size(), wet.size())
	var checked := 0
	for i in range(0, wet.size(), 997):
		if wet[i] != 0:
			assert_near(levels[i], all[i], 0.001, "a wet texel carries its surface")
			checked += 1
		else:
			assert_eq(levels[i], TerrainProvider.NO_WATER, "a dry texel carries none")
	assert_gt(checked, 0, "some water was checked")


func test_off_indoors_and_with_the_haze_off() -> void:
	var mist := GroundMist.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(mist)
	mist.set_state(0.5, 1.0, Vector2.ZERO, "", false, 0.1)
	assert_false(mist.visible, "turned off, it draws nothing")
	assert_eq(mist.material.render_priority, Material.RENDER_PRIORITY_MAX, "drawn over the water and the smoke")
	mist.free()


func test_a_regions_lamps_are_its_own() -> void:
	var provider := World.terrain()
	if provider == null or not provider.has_runtime_maps():
		return
	var start: Array = provider.manifest.get("start", {}).get("pos", [10.0, 0.0, 3670.0])
	var at := Vector3(float(start[0]), float(start[1]), float(start[2]))
	var lamp := NightLights.region_lamp(at)
	var region := provider.nearest_region_id_at(at.x, at.z)
	var light: Dictionary = ContentDB.get_def(region).get("identity", {}).get("light", {}) if ContentDB.has(region) else {}
	assert_near(float(lamp[1]), float(light.get("lamp_energy", 1.0)), 0.0001, "the start's lamps are its region's")
	var owner := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(owner)
	NightLights.add(owner, [at], "lantern")
	var s: Array = NightLights.sources_of(owner)
	var want: Color = NightLights.KINDS["lantern"]["colour"]
	var tint: Color = lamp[0]
	assert_near((s[0][2] as Color).r, want.r * tint.r, 0.001, "a lantern takes the region's tint")
	assert_near(float(s[0][3]), float(NightLights.KINDS["lantern"]["energy"]) * float(lamp[1]), 0.001, "and its strength")
	NightLights.add(owner, [at], "poi", Color(0.2, 0.4, 1.0, 1.0), 3.0, 9.0)
	s = NightLights.sources_of(owner)
	assert_near((s[1][2] as Color).b, 1.0, 0.0001, "a point of interest's own light is left as its builder made it")
	owner.free()
