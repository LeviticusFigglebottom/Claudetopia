extends TestCase
## What a weak machine is spared before the game begins: the menus' frame-rate cap, the Naming's
## portrait drawn no larger than it is shown and cheaper on Low and Medium, what the title reads
## ahead for the Naming, a settings file from before a knob existed keeping its preset, and the
## benchmark's sums.

const NAMING := preload("res://ui/character/naming.tscn")

var _saved: Dictionary = {}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_saved = Settings.data.duplicate(true)


func after_each() -> void:
	Graphics.menu_screens = 0
	NamingAhead.release()
	Settings.data = _saved.duplicate(true)
	Settings.path = Settings.PATH
	Settings.apply_all()


func test_the_menus_hold_the_frame_rate_and_give_the_game_its_own_back() -> void:
	var g := {"preset": "high", "fps_cap": 0}
	Graphics.menu_screens = 0
	assert_eq(Graphics.frame_cap(g), 0, "in the game: no cap")
	Graphics.menu_screens = 1
	assert_eq(Graphics.frame_cap(g), Graphics.MENU_FPS, "a menu with no game behind it: 60")
	assert_eq(Graphics.frame_cap({"preset": "low", "fps_cap": 0}), Graphics.MENU_FPS_LOW, "30 on Low")
	assert_eq(Graphics.frame_cap({"preset": "high", "fps_cap": 30}), 30, "the player's own lower cap stands")
	assert_eq(Graphics.frame_cap({"preset": "high", "fps_cap": 144}), Graphics.MENU_FPS, "a higher one is held to the menus'")
	Graphics.menu_screens = 0
	assert_eq(Graphics.frame_cap({"preset": "high", "fps_cap": 144}), 144, "and given back after")


func _naming() -> Control:
	var n := NAMING.instantiate() as Control
	n.set("world_scene", "")
	_tree().root.add_child(n)
	await _tree().process_frame
	await _tree().process_frame
	return n


func test_the_portrait_is_drawn_at_the_render_scale_and_no_larger_than_shown() -> void:
	Settings.apply_graphics_preset("medium")
	var n := await _naming()
	var preview := n.get("_preview") as SubViewport
	var view := n.get("_view") as TextureRect
	assert_true(preview != null and view != null, "the portrait is there")
	if preview == null:
		n.queue_free()
		return
	n.call("_fit_preview")
	var scale := clampf(n.get_viewport().get_final_transform().get_scale().x, 0.25, 8.0)
	assert_true(preview.size.x <= int(round(view.size.x * scale)) + 1 and preview.size.y <= int(round(view.size.y * scale)) + 1,
			"no larger than the rectangle it fills (%s for %s)" % [str(preview.size), str(view.size * scale)])
	assert_near(preview.scaling_3d_scale, float(Graphics.PRESETS["medium"]["render_scale"]), 0.001,
			"its 3D at Medium's render scale")
	assert_eq(preview.msaa_3d, Viewport.MSAA_2X, "2x on Medium")
	n.queue_free()
	await _tree().process_frame
	Settings.apply_graphics_preset("high")
	var h := await _naming()
	assert_eq((h.get("_preview") as SubViewport).msaa_3d, Viewport.MSAA_4X, "High keeps the 4x it always had")
	assert_near((h.get("_preview") as SubViewport).scaling_3d_scale, 1.0, 0.001, "at full scale")
	h.queue_free()
	await _tree().process_frame


func test_on_low_the_portraits_hair_is_its_shell() -> void:
	Settings.apply_graphics_preset("low")
	var n := await _naming()
	var model := n.get("_model") as Node
	if model == null:
		skip("no body forged")
		n.queue_free()
		return
	# a style with strand cards
	n.get("appearance").set_part("hair", "long_loose")
	n.call("_apply_appearance")
	var cards := 0
	var shells := 0
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		match str(mi.get_meta("material", "")):
			"hair_cards":
				cards += 1
				assert_false(mi.visible, "no strand cards on Low")
			"hair":
				shells += 1
				assert_near(mi.visibility_range_begin, 0.0, 0.001, "the shell is drawn close")
	assert_gt(shells, 0, "the hair has a shell")
	n.queue_free()
	await _tree().process_frame
	Settings.apply_graphics_preset("high")
	var h := await _naming()
	(h.get("appearance") as CharacterAppearance).set_part("hair", "long_loose")
	h.call("_apply_appearance")
	for mi: MeshInstance3D in (h.get("_model") as Node).find_children("*", "MeshInstance3D", true, false):
		if str(mi.get_meta("material", "")) == "hair_cards":
			assert_true(mi.visible, "High keeps the cards")
	h.queue_free()
	await _tree().process_frame


func test_the_title_reads_the_naming_ahead() -> void:
	var ahead := NamingAhead.new()
	ahead.warm = false
	ahead.ground = false
	_tree().root.add_child(ahead)
	ahead._start()
	var until := Time.get_ticks_msec() + 60000
	while not NamingAhead.held.has(NamingAhead.MODEL_SCENE) or NamingAhead.naming_scene() == null:
		await _tree().process_frame
		if Time.get_ticks_msec() > until:
			break
	assert_true(NamingAhead.naming_scene() != null, "the Naming's scene is read and held")
	assert_true(NamingAhead.held.has(NamingAhead.MODEL_SCENE), "and the body it shows")
	NamingAhead.release()
	assert_eq(NamingAhead.naming_scene(), null, "and let go of once the Naming has it")
	ahead.queue_free()
	await _tree().process_frame


func test_a_file_from_before_a_knob_keeps_its_preset() -> void:
	var test_path := "user://test_lowend_menus.cfg"
	var bindings := Settings.bindings.duplicate(true)
	Settings.path = test_path
	var cf := ConfigFile.new()
	# Medium as it was saved before the title's film and the distant ground
	for key in Graphics.PRESETS["medium"]:
		if key in ["title_live", "distant_ground"]:
			continue
		cf.set_value("graphics", key, Graphics.PRESETS["medium"][key])
	cf.set_value("graphics", "preset", "medium")
	cf.save(test_path)
	Settings.load_settings()
	assert_eq(Settings.get_value("graphics", "title_live"), false, "Medium's own value, not High's")
	assert_eq(Settings.get_value("graphics", "distant_ground"), true)
	assert_eq(Graphics.matching_preset(Settings.data["graphics"]), "medium", "still Medium")
	# Low as it was: the chart; Low now is the film
	var low := ConfigFile.new()
	for key in Graphics.PRESETS["low"]:
		if key in ["title_live", "distant_ground"]:
			continue
		low.set_value("graphics", key, Graphics.PRESETS["low"][key])
	low.set_value("graphics", "title_vista", false)
	low.set_value("graphics", "preset", "low")
	low.save(test_path)
	Settings.load_settings()
	assert_eq(Graphics.matching_preset(Settings.data["graphics"]), "low", "a Low file stays Low")
	assert_true(bool(Settings.get_value("graphics", "title_vista")), "and shows the film")
	Settings.bindings = bindings
	DirAccess.remove_absolute(test_path)


func test_fsr_on_medium_and_bilinear_a_little_larger_on_compatibility() -> void:
	var fp := Graphics.preset_values("medium", Graphics.RENDERER_FORWARD_PLUS)
	assert_eq(int(fp["upscaler"]), 1, "Medium upscales with FSR 1 on Forward+")
	assert_near(float(fp["render_scale"]), 0.77, 0.001, "from 0.77 of the window")
	var gl := Graphics.preset_values("medium", Graphics.RENDERER_COMPATIBILITY)
	assert_eq(int(gl["upscaler"]), 0, "bilinear on Compatibility")
	assert_near(float(gl["render_scale"]), 0.85, 0.001, "at a scale bilinear keeps sharp")
	assert_eq(Graphics.matching_preset(gl, Graphics.RENDERER_COMPATIBILITY), "medium", "and it is still Medium there")
	assert_near(float(Graphics.preset_values("high", Graphics.RENDERER_COMPATIBILITY)["render_scale"]), 1.0, 0.001,
			"a discrete card's High keeps native resolution")
	var vp := SubViewport.new()
	Graphics.apply_viewport(vp, fp, Graphics.RENDERER_FORWARD_PLUS)
	assert_eq(vp.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR)
	assert_near(vp.fsr_sharpness, Graphics.FSR_SHARPNESS, 0.001, "sharpened")
	vp.free()


func test_the_lands_occluder_stays_under_the_ground_it_stands_for() -> void:
	# a valley between two ridges, 8 m texels: no vertex may stand above any ground within half a
	# step of it, so the sheet never hides what stands on the ground
	var grid := 33
	var heights := PackedFloat32Array()
	heights.resize(grid * grid)
	for z in grid:
		for x in grid:
			heights[z * grid + x] = 40.0 * absf(sin(float(x) * 0.3)) + float(z) * 0.5
	var arrays := TerrainOccluder.build_arrays(heights, grid, 8.0, Vector2(-128.0, -128.0), 8, 2.0)
	var verts: PackedVector3Array = arrays[0]
	var idx: PackedInt32Array = arrays[1]
	assert_eq(verts.size(), 25, "a vertex every 8 texels, 5 by 5")
	assert_eq(idx.size(), 4 * 4 * 6, "two triangles a square")
	for v in verts:
		var gx := roundi((v.x + 128.0) / 8.0)
		var gz := roundi((v.z + 128.0) / 8.0)
		for z in range(maxi(gz - 4, 0), mini(gz + 4, grid - 1) + 1):
			for x in range(maxi(gx - 4, 0), mini(gx + 4, grid - 1) + 1):
				assert_true(v.y <= heights[z * grid + x] - 2.0 + 0.001, "under the ground near it")
	assert_false(bool(Graphics.PRESETS["painted"]["occlusion"]), "off in every preset, Painted too")


func test_the_benchmark_sums_a_segment() -> void:
	var samples := []
	for i in 98:
		samples.append([16.0, 1000, 500000])
	samples.append([60.0, 1200, 600000])
	samples.append([120.0, 1100, 550000])
	var s := Benchmark.summarise(samples)
	assert_eq(int(s["frames"]), 100)
	assert_near(float(s["p50_ms"]), 16.0, 0.01)
	assert_eq(int(s["over_50ms"]), 2)
	assert_eq(int(s["over_100ms"]), 1)
	assert_near(float(s["max_ms"]), 120.0, 0.01)
	assert_eq(int(s["draws_max"]), 1200)
	assert_eq((s["worst_hitches"] as Array).size(), 2, "the two hitches named")
	var text := Benchmark.text_report({"started": "now", "machine": {"gpu": "AMD Radeon(TM) 740M"}, "segments": [s.merged({"id": "town", "what": "a town"})]})
	assert_true(text.contains("AMD Radeon(TM) 740M") and text.contains("town"), "the text report names the GPU and the segment")
