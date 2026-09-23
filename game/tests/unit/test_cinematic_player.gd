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
const SLOT := "test_cinematic_opening"
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
	SaveSystem.delete_slot(SLOT)


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
	}


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


## One run of the opening, skipped when `skip_when` says so (never, if it is empty).
func _run(w: World, mode: CinematicPlayer.Mode, skip_when: Callable) -> Dictionary:
	var cin := CinematicPlayer.new()
	cin.time_scale = FAST
	var done := [false]
	var shown: Array[String] = []
	var early: Array[String] = []
	var regions := [0]
	var on_region := func(_id: String, _prev: String) -> void: regions[0] += 1
	EventBus.region_entered.connect(on_region)
	cin.finished.connect(func(_skipped: bool) -> void: done[0] = true)
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
			"region_after": GameState.current_region_id, "region_before": start_region}
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
		assert_true(CinematicPlayer.should_play(OPENING), "it could play again, now nothing else is")
		Settings.set_value("gameplay", "play_opening", false, false)
		assert_false(CinematicPlayer.should_play(OPENING), "unless the player has said never again")
		Settings.set_value("gameplay", "play_opening", true, false)
	assert_eq(SaveSystem.save_to_slot(SLOT), OK)
	await _drop(w)
	# Continue: the same character read back from the slot
	Social.reset_for_new_game()
	GameState.reset_for_new_game(12)
	GameState.set_flag("_pending_load_slot", SLOT)
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
	var until := Time.get_ticks_msec() + 5000
	while (UI.is_faded_out() or not cin.is_playing()) and Time.get_ticks_msec() < until:
		await _tree().process_frame
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
