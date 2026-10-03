extends TestCase
## The opening in the built world: that a new game plays it and a Continue does not, that the
## story starts when it hands control back, and that skipping it at any moment -- in the black,
## in the middle of a shot, in the last shot -- leaves the game in exactly the state watching it
## through does. The two ends are compared field by field: where the body stands and faces, what
## the streamer follows, whether anything is paused, every audio bus, the clock, the sky, the HUD,
## the toasts, the camera, the music and the input.
##
## The pictures run fast here (`time_scale`); the waits for the country to load do not, because
## what they wait for is real.

const WORLD_SCENE := "res://world/world.tscn"
const OPENING := "core:cinematic/opening"
## Every checkout on a machine shares one `user://saves`, and two suites run at once each wrote,
## read and deleted the same slot: one run's clean-up took the save out from under the other's
## Continue. The process id keeps this run's slot its own.
var _slot := "test_cinematic_opening_%d" % OS.get_process_id()
const BUSES := ["Master", "Music", "SFX", "Ambience", "UI", "Voice"]
const FAST := 60.0
## Real seconds any one run may take before the test gives up on it rather than hang the suite.
const RUN_TIMEOUT := 240.0


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _built() -> bool:
	return FileAccess.file_exists("res://world/generated/world_manifest.json")


var _setting_was: Variant = true


func before_each() -> void:
	CinematicPlayer.headless_allowed = true
	# whatever this machine's own settings say, a new game here is one that plays the opening
	_setting_was = Settings.get_value("gameplay", "play_opening", true)
	Settings.set_value("gameplay", "play_opening", true, false)


func after_each() -> void:
	CinematicPlayer.headless_allowed = false
	Settings.set_value("gameplay", "play_opening", _setting_was, false)
	SaveSystem.delete_slot(_slot)


func _world() -> World:
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	return w


func _drop(w: Node) -> void:
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame


func _player(w: World) -> Node3D:
	return w.get_node("PlayerSpawn").get("player") as Node3D


func _quest_active(id: String) -> bool:
	var log_node := _tree().get_first_node_in_group("quest_log")
	return log_node != null and bool(log_node.call("is_active", id))


## Looks once more after the time is up: the frame the world stands up in can itself outlast the
## wait on a loaded machine, and the opening begins at the end of that frame.
func _wait_for_cinematic(seconds: float) -> CinematicPlayer:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while true:
		var found := _tree().get_first_node_in_group(CinematicPlayer.GROUP)
		if found is CinematicPlayer:
			return found as CinematicPlayer
		if Time.get_ticks_msec() >= until:
			return null
		await _tree().process_frame
	return null


## Waits for `cin` to hand control back; false if it did not within the timeout.
func _until_finished(cin: CinematicPlayer, done: Array) -> bool:
	var until := Time.get_ticks_msec() + int(RUN_TIMEOUT * 1000.0)
	while not bool(done[0]) and Time.get_ticks_msec() < until:
		await _tree().process_frame
	return bool(done[0])


func _settle(frames := 12) -> void:
	for i in frames:
		await _tree().physics_frame


## Everything the cinematic borrows, as it stands now.
func _state(w: World) -> Dictionary:
	var player := _player(w)
	var rig: Node = player.get("camera_rig")
	var buses := {}
	for bus: String in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			buses[bus] = [snappedf(AudioServer.get_bus_volume_db(i), 0.001), AudioServer.is_bus_mute(i)]
	var cam: Camera3D = rig.get("camera")
	return {
		"position": player.global_position,
		"facing": snappedf(player.rotation.y, 0.001),
		"rig": [snappedf(float(rig.get("yaw")), 0.001), snappedf(float(rig.get("pitch")), 0.001)],
		"streams_around_the_player": w.streamer.target == player,
		"streams_ahead": w.streamer.also_around.size(),
		"streams_seen": w.streamer.also_cells.size(),
		"hurries": w.streamer.hurry,
		"reports_regions": w.streamer.report_regions,
		"paused": _tree().paused,
		"buses": buses,
		"hour": WorldClock.time_hours,
		"clock_running": WorldClock.running,
		"weather": w.atmosphere.call("current_weather_id"),
		"sky_region": str(w.atmosphere.get("region_id")),
		"region": GameState.current_region_id,
		"hud": UI.hud_visible,
		"toasts": UI.toast_layer.visible,
		"gameplay_camera": _tree().root.get_viewport().get_camera_3d() == cam,
		"music_overlay": Music.overlay_kind(),
		"input": bool(player.get("input_enabled")),
		"body_moves": player.is_physics_processing(),
		"terrain_follows": str(w.terrain_node.call("get_camera").name) if w.terrain_node != null and w.terrain_node.call("get_camera") != null else "",
		"cinematics": _tree().get_nodes_in_group(CinematicPlayer.GROUP).size(),
		# the picture the film lifts (Graphics.FILM) and must give back
		"msaa": int(_tree().root.msaa_3d),
		"fxaa": int(_tree().root.screen_space_aa),
		"render_scale": snappedf(_tree().root.scaling_3d_scale, 0.001),
		"mesh_lod_threshold": snappedf(_tree().root.mesh_lod_threshold, 0.001),
		"tree_lod_bias": snappedf(w.streamer.lod_bias, 0.001),
		"sun_shadow_m": snappedf(_sun_shadow_reach(), 0.1),
	}


func _sun_shadow_reach() -> float:
	var reach := 0.0
	for node in _tree().get_nodes_in_group(Graphics.LIGHTS):
		var light := node as DirectionalLight3D
		if light != null and light.shadow_enabled:
			reach = maxf(reach, light.directional_shadow_max_distance)
	return reach


func _same(a: Dictionary, b: Dictionary, what: String) -> void:
	for key: String in a:
		match key:
			"position":
				var d := (a[key] as Vector3).distance_to(b[key])
				assert_true(d < 0.05, "%s: the body ends %.3f m from where watching it through leaves it" % [what, d])
			"hour":
				assert_near(float(a[key]), float(b[key]), 0.02, "%s: the clock" % what)
			_:
				assert_eq(a[key], b[key], "%s: %s" % [what, key])


## Puts the world back to one fixed starting point, so every run begins from the same place.
func _before(w: World, feet: Vector3) -> void:
	var player := _player(w)
	player.global_position = feet + Vector3(0.0, 0.6, 0.0)
	player.set("velocity", Vector3.ZERO)
	player.rotation.y = 1.1
	var rig: Node = player.get("camera_rig")
	rig.set("yaw", 1.1)
	rig.set("pitch", -0.3)
	WorldClock.set_time(11.0)
	w.atmosphere.call("force_weather", "core:weather/rain", true)


## One run of the opening, skipped when `skip_when` says so (never, if it is empty); `configure`
## is given the player before it begins.
func _run(w: World, mode: CinematicPlayer.Mode, skip_when: Callable, configure := Callable()) -> Dictionary:
	var cin := CinematicPlayer.new()
	cin.time_scale = FAST
	if configure.is_valid():
		configure.call(cin)
	var done := [false]
	var shown: Array[String] = []
	var early: Array[String] = []
	var regions := [0]
	var on_region := func(_id: String, _prev: String) -> void: regions[0] += 1
	EventBus.region_entered.connect(on_region)
	# read as it finishes: it frees itself on the same frame
	var capped := {"gave_up": false, "shown_early": []}
	cin.finished.connect(func(_skipped: bool) -> void:
		done[0] = true
		capped["gave_up"] = cin.gave_up
		capped["shown_early"] = cin.shown_early.duplicate())
	w.add_child(cin)
	cin.begin(w, _player(w), ContentDB.get_def(OPENING), mode)
	var last_phase := ""
	var start_region := GameState.current_region_id
	var until := Time.get_ticks_msec() + int(RUN_TIMEOUT * 1000.0)
	while not bool(done[0]) and Time.get_ticks_msec() < until:
		await _tree().process_frame
		if not is_instance_valid(cin) or bool(done[0]):
			break
		var phase := cin.phase_name()
		# a shot is only ever shown once its country is standing
		if phase == "PLAY" and last_phase == "HOLD":
			var id := "%d" % cin.current_shot()
			shown.append(id)
			if not bool((CinematicDef.shots_of(cin.def)[cin.current_shot()] as Dictionary).get("black", false)) and not cin.ready_to_show():
				early.append(id)
		last_phase = phase
		if skip_when.is_valid() and bool(skip_when.call(cin)):
			cin.skip()
			skip_when = Callable()
	EventBus.region_entered.disconnect(on_region)
	var result := {"finished": bool(done[0]), "shown": shown, "early": early, "regions": regions[0],
			"region_after": GameState.current_region_id, "region_before": start_region,
			"gave_up": capped["gave_up"], "shown_early": capped["shown_early"]}
	await _settle()
	result["state"] = _state(w)
	return result


# --- the tests -------------------------------------------------------------------------------------------

func test_a_new_game_plays_the_opening_and_a_continue_does_not() -> void:
	if not _built():
		return
	Social.reset_for_new_game()
	GameState.reset_for_new_game(11)
	GameState.set_flag("player_name", "Tam Cresswell")
	GameState.set_flag("player_calling", "core:calling/cragborn")
	GameState.set_flag("new_game", true)
	var w := _world()
	await w.world_ready
	var cin := await _wait_for_cinematic(45.0)
	assert_true(cin != null, "a new game plays the opening")
	if cin != null:
		assert_false(_quest_active("core:quest/the_naming"), "the story waits for the hand-over")
		assert_false(UI.hud_visible, "no HUD over the pictures")
		assert_eq(w.streamer.target, cin.camera(), "the country streams around the camera")
		assert_false(w.streamer.report_regions, "and the camera is not a traveller")
		# the Warden says the name back first
		var until := Time.get_ticks_msec() + 20000
		while is_instance_valid(cin) and cin.overlay() != null and cin.overlay().said().is_empty() and Time.get_ticks_msec() < until:
			await _tree().process_frame
		if is_instance_valid(cin) and cin.overlay() != null:
			assert_eq(cin.overlay().said(), "Tam Cresswell.", "the first words are the name the player chose")
		var done := [false]
		cin.finished.connect(func(_s: bool) -> void: done[0] = true)
		cin.skip()
		assert_true(await _until_finished(cin, done), "a skipped opening hands control back")
		await _settle()
		assert_true(_quest_active("core:quest/the_naming"), "the Naming starts when control comes back")
		assert_true(UI.hud_visible, "with the HUD")
		# ...at the Stair Head, with the Warden there to speak first (DESIGN §5.1a, the start)
		var body := _player(w)
		assert_true(Vector2(body.global_position.x, body.global_position.z).distance_to(
				WorldProbe.xz_of(ContentDB.get_or_empty("core:poi/stair_head"))) < 3.0, "control comes back at the Stair Head")
		var services := _tree().get_first_node_in_group("game_services")
		assert_true(services != null and str(services.get("first_words")).begins_with("There you are."),
				"the Warden's own first words are said as control comes back")
		var wren: Node3D = null
		var until_wren := Time.get_ticks_msec() + 30000
		while wren == null and Time.get_ticks_msec() < until_wren:
			await _tree().process_frame
			if NpcRegistry.instance != null:
				wren = NpcRegistry.instance.actor("core:npc/wren_tallow") as Node3D
		assert_true(wren != null, "the Warden is stood up at the start")
		if wren != null:
			await _settle(4)
			var apart := wren.global_position.distance_to(body.global_position)
			assert_true(apart > 3.0 and apart < 12.0, "at her fire, %.1f m in front of the player" % apart)
		assert_true(CinematicPlayer.should_play(OPENING), "it could play again, now nothing else is")
		Settings.set_value("gameplay", "play_opening", false, false)
		assert_false(CinematicPlayer.should_play(OPENING), "unless the player has said never again")
		Settings.set_value("gameplay", "play_opening", true, false)
	assert_eq(SaveSystem.save_to_slot(_slot), OK)
	await _drop(w)
	# Continue: the same character read back from the slot
	Social.reset_for_new_game()
	GameState.reset_for_new_game(12)
	GameState.set_flag("_pending_load_slot", _slot)
	w = _world()
	await w.world_ready
	var again := await _wait_for_cinematic(4.0)
	assert_true(again == null, "a Continue does not play the opening")
	assert_true(UI.hud_visible, "and the HUD is simply there")
	await _drop(w)


func test_skipping_anywhere_ends_exactly_where_watching_it_through_does() -> void:
	if not _built():
		return
	Social.reset_for_new_game()
	GameState.reset_for_new_game(13)
	var w := _world()
	await w.world_ready
	await _settle()
	w.streamer.cells_per_frame = 12
	var player := _player(w)
	var feet := player.global_position
	feet.y = w.provider.get_height(feet.x, feet.z)

	_before(w, feet)
	var through := await _run(w, CinematicPlayer.Mode.OPENING, Callable())
	assert_true(bool(through["finished"]), "watched through, the opening ends")
	var shots := CinematicDef.shots_of(ContentDB.get_def(OPENING)).size()
	assert_eq((through["shown"] as Array).size(), shots, "every shot is shown, once: %s" % str(through["shown"]))
	assert_empty(through["early"], "shots shown before their cells stood")
	assert_eq(int(through["regions"]), 0, "flying over five regions tells the game nothing")
	assert_eq(through["region_after"], through["region_before"], "the player is still where they were")
	var end: Dictionary = through["state"]
	assert_true(bool(end["streams_around_the_player"]) and bool(end["gameplay_camera"]) and bool(end["input"]),
			"control is back: %s" % str(end))
	assert_eq(int(end["cinematics"]), 0, "nothing of it is left in the tree")
	assert_true(bool(end["body_moves"]), "the body is let go")
	assert_near(float(end["hour"]), 7.2, 0.02, "it hands over at the hour it says")
	assert_eq(str(end["weather"]), "core:weather/thin_sun", "in the weather it says")

	var moments := {
		"in the black, before a picture": func(c: CinematicPlayer) -> bool: return c.current_shot() == 0 and c.phase_name() == "PLAY",
		"waiting for the Drowned Nave to load": func(c: CinematicPlayer) -> bool: return c.current_shot() == 3,
		"in the middle of Merrowby": func(c: CinematicPlayer) -> bool: return c.current_shot() == 5 and c.phase_name() == "PLAY",
		"coming down the Stair": func(c: CinematicPlayer) -> bool: return c.current_shot() == shots - 1 and c.phase_name() == "PLAY",
	}
	for what: String in moments:
		_before(w, feet)
		var run := await _run(w, CinematicPlayer.Mode.OPENING, moments[what])
		assert_true(bool(run["finished"]), "skipped %s, it still ends" % what)
		_same(run["state"], end, "skipped %s" % what)
	await _drop(w)


## Nothing can keep a player inside the opening. The streamer is throttled to nothing -- every cell
## the opening asks for is asked for for ever -- and each shot is still shown once its own wait
## runs out; then, with the waits made endless, the overall cap hands over as a held key would.
## Both end exactly where watching it through does.
func test_a_country_that_never_comes_cannot_keep_anyone_in_the_opening() -> void:
	if not _built():
		return
	Social.reset_for_new_game()
	GameState.reset_for_new_game(16)
	var w := _world()
	await w.world_ready
	await _settle()
	w.streamer.cells_per_frame = 12
	var player := _player(w)
	var feet := player.global_position
	feet.y = w.provider.get_height(feet.x, feet.z)
	_before(w, feet)
	# "When the country comes": the hold's cap is seconds on the wall, and headless nothing is paced,
	# so a frame stands up a dozen cells and everyone living in them at once -- a hundred people over
	# the opening, 0.1 to 0.45 s each, and on a loaded machine one frame of Merrowby's country ran
	# past the cap before the next could find it in. The cap is the starved run's, below; here the
	# country always comes, and each shot must wait for all of it.
	var through := await _run(w, CinematicPlayer.Mode.OPENING, Callable(),
			func(c: CinematicPlayer) -> void: c.hold_cap_seconds = 120.0)
	assert_true(bool(through["finished"]) and not bool(through["gave_up"]), "watched through, it ends on its own")
	assert_empty(through["shown_early"], "and waits for every shot's country when the country comes")
	var end: Dictionary = through["state"]
	var shots := CinematicDef.shots_of(ContentDB.get_def(OPENING)).size()

	_before(w, feet)
	w.streamer.cells_per_frame = 0
	var starved := await _run(w, CinematicPlayer.Mode.OPENING, Callable(),
			func(c: CinematicPlayer) -> void: c.hold_cap_seconds = 0.8)
	w.streamer.cells_per_frame = 12
	assert_true(bool(starved["finished"]), "with no country arriving at all, the opening still ends")
	assert_false(bool(starved["gave_up"]), "each shot on its own wait, well inside the overall cap")
	assert_eq((starved["shown"] as Array).size(), shots, "and every shot is shown: %s" % str(starved["shown"]))
	assert_gt((starved["shown_early"] as Array).size(), 0,
			"shown with what there was: %s" % str(starved["shown_early"]))
	_same(starved["state"], end, "a starved opening")

	_before(w, feet)
	w.streamer.cells_per_frame = 0
	var stuck := await _run(w, CinematicPlayer.Mode.OPENING, Callable(),
			func(c: CinematicPlayer) -> void:
				c.hold_cap_seconds = 100000.0
				c.overall_cap_seconds = 2.0)
	w.streamer.cells_per_frame = 12
	assert_true(bool(stuck["finished"]), "a wait that would never end is ended")
	assert_true(bool(stuck["gave_up"]), "by the overall cap")
	assert_true((stuck["shown"] as Array).size() < shots, "before the pictures were all shown: %s" % str(stuck["shown"]))
	_same(stuck["state"], end, "handed over by the overall cap")
	await _drop(w)


## The pictures keep the wall clock, not the engine's: on a machine that cannot keep up the engine
## slows the whole game, and a shot timed on its delta ran for ten minutes (PROGRESS). Frames of a
## third of a second each are made here by stalling the loop; nine seconds of the Spire must still
## take about nine seconds.
func test_the_pictures_keep_the_wall_clock_on_a_machine_that_cannot_keep_up() -> void:
	if not _built():
		return
	Social.reset_for_new_game()
	GameState.reset_for_new_game(19)
	var w := _world()
	await w.world_ready
	await _settle()
	w.streamer.cells_per_frame = 12
	var cin := CinematicPlayer.new()
	var done := [false]
	cin.finished.connect(func(_s: bool) -> void: done[0] = true)
	w.add_child(cin)
	cin.begin(w, _player(w), ContentDB.get_def(OPENING), CinematicPlayer.Mode.OPENING)
	var until := Time.get_ticks_msec() + 120000
	while is_instance_valid(cin) and not (cin.current_shot() >= 1 and cin.phase_name() == "PLAY") \
			and Time.get_ticks_msec() < until:
		await _tree().process_frame
	assert_true(is_instance_valid(cin) and cin.phase_name() == "PLAY", "the first picture is playing")
	if not is_instance_valid(cin):
		await _drop(w)
		return
	var shot := cin.current_shot()
	var from_t := cin.shot_time()
	var from_ms := Time.get_ticks_msec()
	var frames := 0
	while is_instance_valid(cin) and cin.current_shot() == shot and frames < 12:
		OS.delay_msec(330)
		await _tree().process_frame
		frames += 1
	var wall := (Time.get_ticks_msec() - from_ms) / 1000.0
	# every frame took at least the 0.33 s it was held for; the engine's own clock counts each as
	# at most eight physics steps, 0.13 s
	if is_instance_valid(cin) and cin.current_shot() == shot:
		var moved := cin.shot_time() - from_t
		assert_true(moved > frames * 0.33 * 0.8, "%.1f s of the shot went by in %.1f s on the wall, over %d slow frames"
				% [moved, wall, frames])
	else:
		assert_true(wall < 14.0, "the shot ended on time over slow frames (%.1f s)" % wall)
	if is_instance_valid(cin):
		cin.skip()
		assert_true(await _until_finished(cin, done), "and it hands back")
	await _drop(w)


## A slot written during the opening kept the `new_game` flag up and the borrowed hour and sky,
## and loading it played the opening again. No slot is written while it plays; and a slot that
## still carries the flag (written before that rule) is loaded as the game it is, never as a new
## one: the story, not the pictures.
func test_no_slot_is_written_while_the_opening_plays_and_a_loaded_game_never_plays_it() -> void:
	if not _built():
		return
	Social.reset_for_new_game()
	GameState.reset_for_new_game(18)
	GameState.set_flag("player_name", "Tam Cresswell")
	GameState.set_flag("player_calling", "core:calling/cragborn")
	GameState.set_flag("new_game", true)
	var w := _world()
	await w.world_ready
	var cin := await _wait_for_cinematic(45.0)
	assert_true(cin != null, "a new game plays the opening")
	if cin == null:
		await _drop(w)
		return
	assert_eq(SaveSystem.save_to_slot(_slot), ERR_BUSY, "no slot is written while it plays")
	assert_false(SaveSystem.slot_exists(_slot), "and nothing reaches the disk")
	var done := [false]
	cin.finished.connect(func(_s: bool) -> void: done[0] = true)
	cin.skip()
	assert_true(await _until_finished(cin, done), "skipped, it hands back")
	await _settle()
	assert_false(GameState.has_flag("new_game"), "the new game's flag is down once control is back")
	assert_eq(SaveSystem.save_to_slot(_slot), OK, "and slots are written again")
	# the slot as one written mid-opening before the rule would read: the flag still up
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.slot_path(_slot)))
	assert_true(raw is Dictionary, "the slot reads back")
	if raw is Dictionary:
		var data: Dictionary = raw
		var sections: Dictionary = data["sections"]
		var state: Dictionary = sections["state"]
		var flags: Dictionary = state["flags"]
		flags["new_game"] = true
		var f := FileAccess.open(SaveSystem.slot_path(_slot), FileAccess.WRITE)
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	await _drop(w)
	Social.reset_for_new_game()
	GameState.reset_for_new_game(20)
	GameState.set_flag("_pending_load_slot", _slot)
	w = _world()
	await w.world_ready
	var again := await _wait_for_cinematic(6.0)
	assert_true(again == null, "loading it does not play the opening again")
	await _settle()
	assert_false(GameState.has_flag("new_game"), "it is not a new game once loaded")
	assert_true(_quest_active("core:quest/the_naming"), "and its story goes on")
	assert_true(UI.hud_visible, "with the HUD up")
	if again != null and is_instance_valid(again):
		again.skip()
	await _drop(w)


## Skipped at any moment -- here while a shot waits for country that is not coming -- a new game
## is handed over whole: the world follows the body (its streaming and Terrain3D's camera), the HUD
## is up, the Warden stands in view at her fire, the first objective's smudge is on the strip and
## its line is written, and the body stands on dry ground.
func test_a_new_game_skipped_while_the_country_is_late_is_handed_over_whole() -> void:
	if not _built():
		return
	Social.reset_for_new_game()
	GameState.reset_for_new_game(21)
	GameState.set_flag("player_name", "Tam Cresswell")
	GameState.set_flag("player_calling", "core:calling/cragborn")
	GameState.set_flag("new_game", true)
	var w := _world()
	await w.world_ready
	var cin := await _wait_for_cinematic(45.0)
	assert_true(cin != null, "a new game plays the opening")
	if cin == null:
		await _drop(w)
		return
	# nothing more of the country is built: the Mere waits for cells that do not come
	w.streamer.cells_per_frame = 0
	var until := Time.get_ticks_msec() + 60000
	while is_instance_valid(cin) and not (cin.current_shot() == 1 and cin.phase_name() == "HOLD") \
			and Time.get_ticks_msec() < until:
		await _tree().process_frame
	assert_true(is_instance_valid(cin) and cin.current_shot() == 1 and cin.phase_name() == "HOLD",
			"the Mere is waiting for its country")
	if not is_instance_valid(cin):
		await _drop(w)
		return
	var done := [false]
	cin.finished.connect(func(_s: bool) -> void: done[0] = true)
	cin.skip()
	w.streamer.cells_per_frame = 12
	assert_true(await _until_finished(cin, done), "skipped in the hold, it hands back")
	# the first frame of control, as the flow probe reads it: the Warden already standing
	await _tree().process_frame
	var reg := NpcRegistry.instance
	var standing: Node = reg.actor("core:npc/wren_tallow") if reg != null else null
	var said := "registry %s; her state %s; people in the tree: %s" % [
			"missing" if reg == null else "with %d standing" % reg.spawned.size(),
			str(reg.state("core:npc/wren_tallow")) if reg != null else "?",
			", ".join(_tree().get_nodes_in_group("npc").map(func(n: Node) -> String: return str(n.get("npc_id"))))]
	assert_true(standing != null, "the Warden stands at the start on the first frame of control (%s)" % said)
	await _settle()
	var body := _player(w)
	var rig: Node = body.get("camera_rig")
	var cam: Camera3D = rig.get("camera")
	assert_eq(w.streamer.target, body, "the country streams around the body")
	if w.terrain_node != null:
		assert_eq(w.terrain_node.call("get_camera"), cam, "and Terrain3D draws and collides around the body's own camera")
	assert_eq(_tree().root.get_viewport().get_camera_3d(), cam, "the gameplay camera is the one drawing")
	assert_true(UI.hud_visible, "the HUD is up")
	assert_true(_quest_active("core:quest/the_naming"), "the Naming has begun")
	assert_true(PlayerSpawn._dry_at(w.provider, body.global_position.x, body.global_position.z),
			"the body stands on dry ground at %s" % str(body.global_position.round()))
	var wren: Node3D = null
	var until_wren := Time.get_ticks_msec() + 30000
	while wren == null and Time.get_ticks_msec() < until_wren:
		await _tree().process_frame
		if NpcRegistry.instance != null:
			wren = NpcRegistry.instance.actor("core:npc/wren_tallow") as Node3D
	assert_true(wren != null, "the Warden is stood up at the start")
	# the objective line inks in, and the Warden is put at her fire as the camp's cell comes in
	var hud := UI.hud()
	var line := ""
	var in_view := false
	var near := false
	var marked := false
	var until_all := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < until_all and not (line != "" and in_view and near and marked):
		await _tree().process_frame
		line = str(hud.call("objective_shown")) if hud != null else ""
		marked = hud != null and bool(hud.call("quest_marker_on_strip"))
		if wren != null and is_instance_valid(wren):
			var head := wren.global_position + Vector3(0.0, 1.2, 0.0)
			near = wren.global_position.distance_to(body.global_position) < 14.0
			in_view = not cam.is_position_behind(head) \
					and _tree().root.get_viewport().get_visible_rect().has_point(cam.unproject_position(head))
	assert_true(marked, "the first objective's smudge is on the strip")
	assert_true(line.begins_with("The Naming"), "and its line is written under the compass: '%s'" % line)
	assert_true(near, "the Warden is at her fire, near")
	assert_true(in_view, "and in view")
	await _drop(w)


## Any key shows the prompt; only a key held past its fill skips, and the hold is timed from the
## press on the wall clock. On a machine drawing a frame every few seconds a tap inside one long
## frame is not a hold, and a key held across one is.
func test_a_tap_never_skips_and_a_held_key_does_even_across_long_frames() -> void:
	if not _built():
		return
	Social.reset_for_new_game()
	GameState.reset_for_new_game(22)
	var w := _world()
	await w.world_ready
	await _settle()
	var cin := CinematicPlayer.new()
	var done := [false]
	cin.finished.connect(func(_s: bool) -> void: done[0] = true)
	w.add_child(cin)
	cin.begin(w, _player(w), ContentDB.get_def(OPENING), CinematicPlayer.Mode.OPENING)
	var until := Time.get_ticks_msec() + 30000
	while is_instance_valid(cin) and not cin.is_playing() and Time.get_ticks_msec() < until:
		await _tree().process_frame
	assert_true(is_instance_valid(cin) and cin.is_playing(), "the opening is playing")
	if not is_instance_valid(cin):
		await _drop(w)
		return
	_key(true)
	await _tree().process_frame
	assert_true(cin.overlay().prompt_shown(), "a key shows the prompt at once")
	# the key comes up again inside one long frame, before the opening looks at it
	OS.delay_msec(1500)
	_key(false)
	await _tree().process_frame
	await _tree().process_frame
	assert_false(cin.skipped, "a tap is not a skip, however long the frame it fell in")
	_key(true)
	await _tree().process_frame
	assert_false(cin.skipped, "a key held is not a skip on the frame it goes down")
	OS.delay_msec(1500)
	await _tree().process_frame
	await _tree().process_frame
	assert_true(cin.skipped, "held across a long frame, past the fill, it skips")
	_key(false)
	assert_true(await _until_finished(cin, done), "and hands back")
	await _drop(w)


## A key, straight to the viewport's `_input`: a headless run has no window to send it through.
func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = down
	_tree().root.push_input(ev)


## The menus fade to black on the way into the world, and something else lifts it: the body
## standing, or the streaming being done. The opening must not depend on which, or on when: a
## fade still down when it begins would hide every picture behind the subtitles.
func test_a_fade_left_down_does_not_hide_the_pictures() -> void:
	if not _built():
		return
	Social.reset_for_new_game()
	GameState.reset_for_new_game(15)
	var w := _world()
	await w.world_ready
	await _settle()
	UI.fade_to_black(0.0, "The Roll is read again.")
	# the fade is a tween, which moves on the idle step, not the physics one
	var down_by := Time.get_ticks_msec() + 2000
	while not UI.is_faded_out() and Time.get_ticks_msec() < down_by:
		await _tree().process_frame
	assert_true(UI.is_faded_out(), "the fade is down, as a menu leaves it")
	var cin := CinematicPlayer.new()
	var done := [false]
	cin.finished.connect(func(_s: bool) -> void: done[0] = true)
	w.add_child(cin)
	cin.begin(w, _player(w), ContentDB.get_def(OPENING), CinematicPlayer.Mode.OPENING)
	# a hang is five seconds and a dozen frames: headless nothing is paced, and the frames of the
	# take-over stand up the country round the hand-over and the first shots, people and all --
	# seconds each on a loaded machine. What is asked is the order, not the machine's speed.
	var until := Time.get_ticks_msec() + 5000
	var frames := 0
	while (UI.is_faded_out() or not cin.is_playing()) and (Time.get_ticks_msec() < until or frames < 12):
		await _tree().process_frame
		frames += 1
	assert_false(UI.is_faded_out(), "the opening lifts it, under its own black")
	assert_true(is_instance_valid(cin) and cin.is_playing() and cin.current_shot() == 0,
			"while the Warden is still saying the name")
	assert_true(cin.overlay().curtain() > 0.99, "so nothing of the world shows before the first picture")
	cin.skip()
	assert_true(await _until_finished(cin, done), "and it still hands back")
	await _drop(w)


func test_a_replay_puts_everything_back_as_it_was() -> void:
	if not _built():
		return
	Social.reset_for_new_game()
	GameState.reset_for_new_game(14)
	var w := _world()
	await w.world_ready
	await _settle()
	w.streamer.cells_per_frame = 12
	var player := _player(w)
	var feet := player.global_position
	feet.y = w.provider.get_height(feet.x, feet.z)
	_before(w, feet)
	await _settle(30)
	var before := _state(w)
	var run := await _run(w, CinematicPlayer.Mode.REPLAY,
			func(c: CinematicPlayer) -> bool: return c.current_shot() == 4 and c.phase_name() == "PLAY")
	assert_true(bool(run["finished"]), "a replay skipped halfway ends")
	_same(run["state"], before, "after a replay")
	await _drop(w)


## A prompt asked for and let go before its fade had begun -- a key down and a skip on the next
## frame of a slow machine -- does not go on fading in over the skip's black.
func test_a_prompt_let_go_before_its_fade_began_does_not_appear() -> void:
	var overlay := CinematicOverlay.new()
	_tree().root.add_child(overlay)
	overlay.prompt(true)
	overlay.prompt(false)
	for _i in 30:
		await _tree().process_frame
	assert_false(overlay.prompt_shown(), "the prompt stays gone")
	overlay.prompt(true)
	for _i in 30:
		await _tree().process_frame
	assert_true(overlay.prompt_shown(), "and a key held shows it")
	_tree().root.remove_child(overlay)
	overlay.queue_free()


## The owner's report (2026-10-02): "the intro cinematics are at very low resolution". Every frame a
## film shows is drawn into the window's own pixels, scaled by the preset's render scale and by
## nothing else, through the film's own camera, with the streaming and Terrain3D's clipmap round
## that camera rather than round the body. On High it is drawn with Graphics.FILM over the settings
## (4x MSAA, the meshes' and trees' detail twice as far, the sun's shadows over the subject); on
## Medium, what an integrated GPU is given, with the settings as they stand. Either way everything is
## given back when it ends.
func test_every_frame_of_a_film_is_drawn_at_the_window_size_round_its_own_camera() -> void:
	if not _built():
		return
	var own_graphics: Dictionary = (Settings.data.get("graphics", {}) as Dictionary).duplicate()
	var persisted := Settings.persist
	Settings.persist = false
	for preset: String in ["high", "medium"]:
		Settings.apply_graphics_preset(preset)
		var g: Dictionary = Settings.data["graphics"]
		var scale := float(g["render_scale"])
		var lifted := Graphics.film_values(g)
		Social.reset_for_new_game()
		GameState.reset_for_new_game(14)
		var w := _world()
		await w.world_ready
		await _settle()
		w.streamer.cells_per_frame = 12
		var player := _player(w)
		var feet := player.global_position
		feet.y = w.provider.get_height(feet.x, feet.z)
		_before(w, feet)
		await _settle(30)
		var before := _state(w)
		var frames: Array = []
		var run := await _run(w, CinematicPlayer.Mode.REPLAY, func(c: CinematicPlayer) -> bool:
			if c.phase_name() == "PLAY":
				frames.append(c.render_report())
			return c.current_shot() == 4 and c.phase_name() == "PLAY")
		assert_true(bool(run["finished"]), "%s: the replay ends" % preset)
		assert_true(frames.size() > 10, "%s: pictures were shown (%d frames)" % [preset, frames.size()])
		var base := float(ProjectSettings.get_setting("rendering/mesh_lod/lod_change/threshold_pixels", 1.0))
		var wrong := 0
		for r: Dictionary in frames:
			var win: Array = r["window"]
			var want := [int(round(int(win[0]) * scale)), int(round(int(win[1]) * scale))]
			if r["frame"] != win or r["render_3d"] != want or not bool(r["camera_is_film"]) \
					or not bool(r["streams_round_film"]) or (w.terrain_node != null and not bool(r["terrain_round_film"])) \
					or int(r["msaa"]) != [0, 2, 4, 8][int(lifted["msaa"])] \
					or absf(float(r["mesh_lod_threshold"]) - base / float(lifted["lod_bias"])) > 0.01 \
					or absf(float(r["tree_lod_bias"]) - float(lifted["lod_bias"])) > 0.01:
				if wrong == 0:
					assert_true(false, "%s: a film frame drawn as %s, wanted %s at %.2f of the window, 4x edges on High" % [preset, r, want, scale])
				wrong += 1
		assert_eq(wrong, 0, "%s: every film frame at the window's size times the render scale, round the film's camera" % preset)
		if preset == "high":
			var reach := float((frames[frames.size() - 1] as Dictionary)["sun_shadow_m"])
			assert_true(reach >= 600.0 or reach == 0.0, "high: the sun's shadows reach the subject (%.0f m)" % reach)
			assert_eq(int(lifted["msaa"]), 2, "high: a film has 4x edges")
		else:
			assert_eq(lifted, g, "medium: a film keeps the settings it is given")
		_same(run["state"], before, "%s: after the film" % preset)
		await _drop(w)
	Settings.data["graphics"] = own_graphics
	Graphics.apply(own_graphics, _tree())
	Settings.persist = persisted
