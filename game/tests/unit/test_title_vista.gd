extends TestCase
## The country behind the title's menu (ui/menus/title_vista.gd, `core:cinematic/title`). The menu is
## the game's own scene, stood up as the game stands it: its buttons take the keys at once, while the
## world is still being stood up behind them; the country comes up moving; no shot is shown before
## its cells have arrived, round the whole list, the cells its camera will see included; and leaving the title -- which is what New Game,
## Continue and Load all do, by changing the scene -- leaves no world, camera, cell, streamer or
## service behind, gives the clock back and never told the game it had entered a region.
##
## Needs the built world; without it the title keeps its chart and these say so and skip.

const MENU_SCENE := "res://ui/menus/main_menu.tscn"
## Real seconds the country may take to come up behind the menu on this machine.
const UP_WITHIN_S := 240.0

var _menu: Node = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	TitleVista.headless_allowed = true
	GameState.reset_for_new_game(7)


func after_each() -> void:
	_key(KEY_DOWN, false)
	if _menu != null and is_instance_valid(_menu):
		_menu.free()
	_menu = null
	TitleVista.headless_allowed = false
	await _tree().process_frame
	await _tree().process_frame
	GameState.reset_for_new_game(7)


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.physical_keycode = code as Key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## The title as the game stands it, and its vista; null (and a note) when there is no world to show.
func _title() -> TitleVista:
	if not bool(WorldStatus.current().get("playable", false)) or not ContentDB.has(TitleVista.DEF_ID):
		skip("no built world or no title cinematic: the title keeps its chart; skipped")
		return null
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(_menu)
	return _menu.get("vista") as TitleVista


func _wait_up(vista: TitleVista) -> bool:
	var until := Time.get_ticks_msec() + int(UP_WITHIN_S * 1000.0)
	while not vista.is_showing() and vista.phase != TitleVista.Phase.GONE and Time.get_ticks_msec() < until:
		await _tree().process_frame
	return vista.is_showing()


func test_the_menu_takes_the_keys_at_once_and_the_country_comes_up_moving() -> void:
	var region_before := GameState.current_region_id
	var vista := _title()
	if vista == null:
		return
	await _tree().process_frame
	var first := _menu.get_viewport().gui_get_focus_owner()
	assert_true(first is Button and str((first as Button).text) == "New Game", "the first thing focused is New Game (%s)" % str(first))
	assert_false(vista.is_showing(), "the country is not up yet: the menu came first")
	_key(KEY_DOWN, true)
	await _tree().process_frame
	_key(KEY_DOWN, false)
	await _tree().process_frame
	var second := _menu.get_viewport().gui_get_focus_owner()
	assert_true(second != first and second is Button, "a key moves the focus while the world stands up behind (%s)" % str(second))
	var began := Time.get_ticks_msec()
	assert_true(await _wait_up(vista), "the country came up behind the menu within %.0f s" % UP_WITHIN_S)
	if not vista.is_showing():
		return
	print("    the country came up %.1f s after the menu" % (float(Time.get_ticks_msec() - began) / 1000.0))
	var at := vista.camera.global_position
	for i in 30:
		await _tree().process_frame
	assert_true(vista.camera.global_position.distance_to(at) > 0.01, "the camera moves (%.3f m in 30 frames)" % vista.camera.global_position.distance_to(at))
	assert_eq(_menu.get_viewport().get_camera_3d(), vista.camera, "and it is the camera the screen is drawn from")
	assert_eq(GameState.current_region_id, region_before, "the title never told the game it had entered a region")
	assert_eq(vista.world.streamer.report_regions, false, "and its streamer does not either")


func test_no_shot_is_shown_before_its_cells_are_in_round_the_whole_list() -> void:
	var vista := _title()
	if vista == null:
		return
	vista.time_scale = 8.0
	var checked: Array[String] = []
	var late: Array[String] = []
	vista.shot_started.connect(func(i: int, id: String) -> void:
		checked.append(id)
		for p in vista.need_of(i):
			if not vista.world.streamer.is_loaded_around(p):
				late.append("%s at (%.0f, %.0f)" % [id, p.x, p.z])
		# and every near cell its opening sees (ShotSight), past the streamer's own rings; the far
		# ring's are asked for with them and come while it plays (TRIAGE item 36)
		var opening := vista.world.streamer.standing_of(ShotSight.near_only(ShotSight.rings(vista.sight_of(i), TitleVista.OPENING_U)))
		if opening.x < opening.y:
			late.append("%s: %d of the %d near cells its opening sees" % [id, opening.x, opening.y]))
	if not await _wait_up(vista):
		assert_true(false, "the country never came up")
		return
	var shots: int = (vista.def.get("shots", []) as Array).size()
	var until := Time.get_ticks_msec() + int(UP_WITHIN_S * 1000.0) * 2
	while checked.size() <= shots and Time.get_ticks_msec() < until:
		await _tree().process_frame
	assert_true(checked.size() > shots, "every shot was shown and the list came round again (%d of %d)" % [checked.size(), shots + 1])
	assert_eq(late, [] as Array[String], "every shot's cells were in when it was shown")
	for s in vista.shown:
		assert_true(bool((s as Dictionary)["cells_ready"]), "%s was shown with its country in" % str((s as Dictionary)["id"]))


func test_leaving_the_title_leaves_nothing_behind() -> void:
	var clock_before := WorldClock.time_hours
	var running_before := WorldClock.running
	var region_before := GameState.current_region_id
	var vista := _title()
	if vista == null:
		return
	assert_true(await _wait_up(vista), "the country came up")
	var world := vista.world
	var streamer: WorldStreamer = world.streamer if world != null else null
	var cells := streamer.loaded_count() if streamer != null and streamer.has_method("loaded_count") else -1
	assert_true(World.instance == world, "while it is up, the title's world is the world")
	assert_true(cells != 0, "and it has streamed country in (%d cells)" % cells)
	assert_false(WorldClock.running, "the clock is held while the title shows its hours")
	# what New Game, Continue and Load do: the scene changes, and the title goes with it
	_menu.free()
	_menu = null
	await _tree().process_frame
	await _tree().process_frame
	assert_true(World.instance == null, "no world is left standing")
	assert_false(is_instance_valid(world), "the title's world is gone")
	assert_false(is_instance_valid(streamer), "and its streamer with every cell it streamed")
	assert_eq(_tree().get_nodes_in_group("title_vista").size(), 0, "no vista is left")
	assert_eq(_tree().get_nodes_in_group("streamer_target").size(), 0, "nor its camera")
	assert_eq(_tree().get_nodes_in_group("game_services").size(), 0, "and no services were ever stood up")
	assert_eq(_tree().get_nodes_in_group(CinematicPlayer.GROUP).size(), 0, "nor a cinematic player")
	# given back as it stood when the vista took it, a few frames after the test read it
	assert_near(WorldClock.time_hours, clock_before, 0.02, "the clock is given back its hour (%.4f, %.4f before)" % [WorldClock.time_hours, clock_before])
	assert_eq(WorldClock.running, running_before, "and runs as it did")
	assert_eq(GameState.current_region_id, region_before, "the game was never told of a region")


func test_stopping_it_brings_the_chart_back_and_frees_the_world() -> void:
	var vista := _title()
	if vista == null:
		return
	assert_true(await _wait_up(vista), "the country came up")
	var world := vista.world
	vista.stop()
	await _tree().process_frame
	await _tree().process_frame
	assert_false(is_instance_valid(world), "the world goes when the vista stops")
	assert_near(vista.chart.modulate.a, 1.0, 0.001, "and the chart is back")
	assert_false(vista.is_showing(), "and nothing shows")


func test_the_title_setting_off_keeps_the_chart() -> void:
	var was: Variant = Settings.get_value("graphics", "title_vista", true)
	Settings.data["graphics"]["title_vista"] = false
	assert_false(TitleVista.wanted(), "off in the settings, there is no vista")
	Settings.data["graphics"]["title_vista"] = was
	assert_false(bool(Graphics.PRESETS["low"]["title_vista"]), "Low keeps the chart")
	assert_true(bool(Graphics.PRESETS["medium"]["title_vista"]), "Medium shows the country")
