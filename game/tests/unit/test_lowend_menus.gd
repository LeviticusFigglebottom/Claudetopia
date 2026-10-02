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


