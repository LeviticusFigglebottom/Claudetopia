extends TestCase
## Each style's intro film, played through as a new game in the built world, headless but with the
## world streamed and built as it is where it is drawn (WorldPace paced: the budgets, the places, the
## towns and the people a piece at a time), at the pictures' own speed. Once its first picture is up
## the film must never wait on the country again: no cut held for cells, towns or people, no hold line
## on the black, no loading caption, no shot shown without its country. The only wait is the one
## before the first picture, and that one must end because the whole film's country came, not on a
## cap (CinematicPlayer._plan_film). The owner's report: mid-film the picture froze, "loading N
## cells" came up, and only then did the film go on.

const WORLD_SCENE := "res://world/world.tscn"
const STYLES := ["core:style/warrior", "core:style/ranger", "core:style/mage", "core:style/rogue"]
## Real seconds a film may take, from the world's first frame to control, before the test gives up.
const RUN_TIMEOUT := 300.0

var _paced_was := -1
## The clock as the test found it: a film played as a new game hands over at its own hour (the
## evening for some styles), and the next test's world would be lit for the night it left
## (test_objects_seated then judged the night's lamps by a clock it never set).
var _clock_was := Vector3(8.0, 1.0, 1.0)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _built() -> bool:
	return FileAccess.file_exists("res://world/generated/world_manifest.json")


func before_each() -> void:
	CinematicPlayer.headless_allowed = true
	_paced_was = WorldPace.paced_override
	_clock_was = Vector3(WorldClock.time_hours, float(WorldClock.day), 1.0 if WorldClock.running else 0.0)
	Settings.set_value("gameplay", "play_opening", true, false)


func after_each() -> void:
	CinematicPlayer.headless_allowed = false
	WorldPace.paced_override = _paced_was
	WorldClock.set_time(_clock_was.x, int(_clock_was.y))
	WorldClock.running = _clock_was.z > 0.5
	# a film played as a new game leaves that game's flags: the next test's game is not still opening
	# (Wren's hold at the Stair Head reads new_game and style_start)
	for flag in ["new_game", Openings.STYLE_START, Openings.STYLE_DUE, StyleDef.FLAG, "player_name", "player_calling"]:
		GameState.clear_flag(flag)
	Social.reset_for_new_game()


func test_the_warriors_film_never_waits_once_it_has_begun() -> void:
	await _play(STYLES[0])


func test_the_rangers_film_never_waits_once_it_has_begun() -> void:
	await _play(STYLES[1])


func test_the_mages_film_never_waits_once_it_has_begun() -> void:
	await _play(STYLES[2])


func test_the_rogues_film_never_waits_once_it_has_begun() -> void:
	await _play(STYLES[3])


func _play(style: String) -> void:
	if not _built():
		return
	Social.reset_for_new_game()
	GameState.reset_for_new_game(31)
	GameState.set_flag("player_name", "Tam Cresswell")
	GameState.set_flag("player_calling", "core:calling/cragborn")
	GameState.set_flag(StyleDef.FLAG, style)
	GameState.set_flag(Openings.STYLE_DUE, true)
	GameState.set_flag("new_game", true)
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	# From the moment the world is ready (before the new game hears it and the film begins), streamed
	# and built as where it is drawn: cells, places, towns and people a piece at a time within the
	# frame's budget. The world itself stands up at once, as it does headless: its skyline is never
	# built here (the dummy renderer has no primitive meshes' arrays to build it from).
	w.world_ready.connect(func() -> void: WorldPace.paced_override = 1, CONNECT_ONE_SHOT)
	_tree().root.add_child(w)
	var until := Time.get_ticks_msec() + int(RUN_TIMEOUT * 1000.0)
	var cin: CinematicPlayer = null
	while cin == null and Time.get_ticks_msec() < until:
		await _tree().process_frame
		cin = _tree().get_first_node_in_group(CinematicPlayer.GROUP) as CinematicPlayer
	assert_true(cin != null, "%s: a new game plays its film" % style)
	if cin == null:
		await _drop(w)
		return
	var film := str(cin.def.get("id", ""))
	var done := [false]
	var out := {}
	cin.finished.connect(func(_s: bool) -> void:
		done[0] = true
		out["holds"] = cin.holds.duplicate(true)
		out["shown_early"] = cin.shown_early.duplicate()
		out["gave_up"] = cin.gave_up
		out["preroll"] = cin.preroll.duplicate(true))
	var began := false
	var captions: Array[String] = []
	var longest_ms := 0
	var last_ms := 0
	while not bool(done[0]) and Time.get_ticks_msec() < until:
		await _tree().process_frame
		if bool(done[0]) or not is_instance_valid(cin):
			break
		var now := Time.get_ticks_msec()
		if not began and cin.phase_name() == "PLAY":
			began = true
		elif began:
			longest_ms = maxi(longest_ms, now - last_ms)
			var at := "shot %d (%s) %.1f s in" % [cin.current_shot(), cin.phase_name(), cin.shot_time()]
			if UI.is_loading_shown():
				captions.append("the loading caption at %s: %s" % [at, UI.loading_text().replace("\n", " / ")])
			if cin.overlay() != null and cin.overlay().caption_shown():
				captions.append("the hold line at %s" % at)
		last_ms = now
	assert_true(bool(done[0]), "%s plays to its end within %d s" % [film, int(RUN_TIMEOUT)])
	if bool(done[0]):
		var holds: Array = out["holds"]
		var preroll: Dictionary = out["preroll"]
		var waits: Array[String] = []
		for h: Dictionary in holds:
			if bool(h.get("mid", false)) and (not bool(h.get("ready", true)) or bool(h.get("caption", false)) or bool(h.get("early", false))):
				waits.append(str(h))
		var said := "%s: holds %s; before the first picture %s; longest frame of the pictures %d ms" % [
				film, str(holds), str(preroll), longest_ms]
		print("FILM_STREAMING| ", said)
		assert_false(bool(out["gave_up"]), "%s is not handed over by the overall cap" % film)
		assert_eq(str(preroll.get("why", "")), "", "%s: the whole film's country came before the first picture (%s)" % [film, said])
		assert_empty(waits, "%s: no cut waits on the country once the film has begun (%s)" % [film, said])
		assert_empty(captions.slice(0, 5), "%s: no loading caption and no hold line once the film has begun (%d frames)" % [film, captions.size()])
	await _drop(w)


func _drop(w: Node) -> void:
	var cin := _tree().get_first_node_in_group(CinematicPlayer.GROUP)
	if cin != null:
		cin.queue_free()
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame
