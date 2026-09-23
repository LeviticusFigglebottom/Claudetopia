extends TestCase
## The opening is data, and data that plays for ninety seconds in front of every new player has
## to be refused when it is wrong rather than discovered to be wrong on screen. These hold the
## validator to the mistakes an author actually makes: a stored altitude, a place that is not a
## place, a line nobody can read in the time it is up, a subtitle caught in a dissolve, a camera
## handed back from anywhere but the last shot.

const OPENING := "core:cinematic/opening"


## The smallest definition the validator accepts, for the tests below to break one thing at a time.
func _minimal() -> Dictionary:
	return {
		"id": "core:cinematic/test_minimal",
		"name": "Minimal",
		"handover": {"time": 7.0, "weather": "core:weather/clear", "facing": {"bearing": 0}},
		"shots": [
			{"id": "black", "duration": 3.0, "black": true,
			 "lines": [{"at": 0.5, "for": 2.0, "text": "{name}."}]},
			{"id": "look", "duration": 6.0, "time": 8.0, "weather": "core:weather/mist",
			 "keys": [
				{"t": 0.0, "at": {"place": "core:place/merrowby", "bearing": 90, "distance": 100, "height": 20},
				 "look": {"place": "core:place/merrowby", "height": 5}},
				{"t": 1.0, "at": {"place": "core:place/merrowby", "bearing": 80, "distance": 90, "height": 18},
				 "look": {"place": "core:place/merrowby", "height": 5}}],
			 "lines": [{"at": 0.5, "for": 3.0, "text": "A line of words."}]},
			{"id": "end", "duration": 8.0, "handover": true,
			 "keys": [
				{"t": 0.0, "at": {"place": "player", "bearing": 180, "distance": 40, "height": 12},
				 "look": {"place": "player", "height": 2}},
				{"t": 1.0, "at": "player_camera"}]},
		],
	}


func _problems(def: Dictionary) -> String:
	return " | ".join(CinematicDef.validate(def, "test"))


func _expect_refused(def: Dictionary, words: String, why: String) -> void:
	var problems := _problems(def)
	assert_true(problems.contains(words), "%s: expected a problem saying '%s', got: %s" % [why, words, problems])


# --- the opening itself ------------------------------------------------------------------------

func test_the_opening_is_in_the_pack_and_validates() -> void:
	assert_true(ContentDB.has(OPENING), "the opening cinematic is not in the core pack")
	var def := ContentDB.get_def(OPENING)
	assert_eq(_problems(def), "", "the opening does not validate")
	for p in ContentDB.problems:
		assert_false(str(p).contains("cinematic"), "a content problem names a cinematic: %s" % p)


func test_a_new_game_opens_on_it_and_it_ends_by_handing_over() -> void:
	var opening := ContentDB.get_def(GameServices.OPENING)
	assert_eq(str(opening.get("cinematic", "")), OPENING, "core:opening/new_game does not name the opening")
	var def := ContentDB.get_def(OPENING)
	var shots := CinematicDef.shots_of(def)
	assert_eq(CinematicDef.handover_index(def), shots.size() - 1, "control is handed back from the last shot")
	var total := CinematicDef.total_seconds(def)
	assert_true(total > 45.0 and total < 150.0, "an opening of %.0f s is not the minute or two it was designed as" % total)


func test_the_opening_says_the_name_the_player_chose() -> void:
	var def := ContentDB.get_def(OPENING)
	var first: Dictionary = CinematicDef.shots_of(def)[0]
	var line: Dictionary = (first.get("lines", []) as Array)[0]
	assert_eq(CinematicDef.words(line, "Tam Cresswell"), "Tam Cresswell.", "the first thing said is the name")
	assert_eq(CinematicDef.words(line, "  "), "Foundling.", "and with no name, what the world calls you")


func test_the_opening_never_dissolves_into_or_out_of_black() -> void:
	var def := ContentDB.get_def(OPENING)
	var shots := CinematicDef.shots_of(def)
	for i in range(1, shots.size()):
		var black := bool((shots[i] as Dictionary).get("black", false)) or bool((shots[i - 1] as Dictionary).get("black", false))
		if black:
			assert_eq(CinematicDef.dissolve_into(def, i), 0.0, "a dissolve through black at shot %d" % i)
		else:
			assert_gt(CinematicDef.dissolve_into(def, i), 0.0, "shot %d cuts where it should dissolve" % i)


# --- what the validator refuses ----------------------------------------------------------------------

func test_the_minimal_definition_passes() -> void:
	assert_eq(_problems(_minimal()), "", "the test's own minimal definition should be valid")


func test_a_camera_needs_a_height_above_the_ground_not_an_altitude() -> void:
	var def := _minimal()
	var key: Dictionary = def["shots"][1]["keys"][0]
	(key["at"] as Dictionary).erase("height")
	key["at"]["y"] = 120.0
	_expect_refused(def, "no height above the ground", "a stored altitude")
	def = _minimal()
	def["shots"][1]["keys"][0]["at"]["height"] = 0.5
	_expect_refused(def, "closer to the ground", "a camera in the grass")


func test_a_camera_is_placed_relative_to_a_place() -> void:
	var def := _minimal()
	def["shots"][1]["keys"][0]["at"]["place"] = "core:item/iron_sword"
	_expect_refused(def, "not a place or a point of interest", "a sword is not somewhere")
	def = _minimal()
	(def["shots"][1]["keys"][1]["look"] as Dictionary).erase("place")
	_expect_refused(def, "not placed relative to anywhere", "a look with no place")


func test_a_line_has_to_be_readable_in_the_time_it_is_up() -> void:
	var def := _minimal()
	def["shots"][1]["lines"][0] = {"at": 0.5, "for": 1.2, "text": "This line is far too long to read in a second and a bit."}
	_expect_refused(def, "characters a second", "a line nobody can read")


func test_a_line_is_gone_before_the_cut() -> void:
	var def := _minimal()
	def["shots"][1]["lines"][0] = {"at": 3.0, "for": 2.9, "text": "Into the cut."}
	_expect_refused(def, "into the cut", "a subtitle caught in the dissolve")


func test_lines_do_not_overlap() -> void:
	var def := _minimal()
	(def["shots"][1]["lines"] as Array).append({"at": 2.0, "for": 1.5, "text": "Over the first."})
	_expect_refused(def, "before the line before it has gone", "two lines at once")


func test_control_is_handed_back_once_and_last() -> void:
	var def := _minimal()
	def["shots"][1]["handover"] = true
	_expect_refused(def, "not the last shot", "a hand-over in the middle")
	def = _minimal()
	(def["shots"][2] as Dictionary).erase("handover")
	_expect_refused(def, "exactly one shot", "no hand-over at all")


func test_only_the_last_key_of_the_hand_over_is_the_player_camera() -> void:
	var def := _minimal()
	def["shots"][1]["keys"][1] = {"t": 1.0, "at": "player_camera"}
	_expect_refused(def, "only the last key of the hand-over", "the player's camera mid-film")
	def = _minimal()
	def["shots"][2]["keys"][1] = {"t": 1.0, "at": {"place": "player", "height": 3}, "look": {"place": "player"}}
	_expect_refused(def, "must be the player's camera", "a hand-over that does not arrive at the player")


func test_keys_run_forward_from_zero_to_one() -> void:
	var def := _minimal()
	def["shots"][1]["keys"][0]["t"] = 0.2
	_expect_refused(def, "first key must be at t 0", "a path that starts late")
	def = _minimal()
	def["shots"][1]["keys"][1]["t"] = 0.0
	_expect_refused(def, "run forward in time", "a path that goes backwards")


func test_the_weather_and_the_title_card_are_checked() -> void:
	var def := _minimal()
	def["shots"][1]["weather"] = "core:item/iron_sword"
	_expect_refused(def, "is not a weather id", "weather that is a sword")
	def = _minimal()
	def["title_card"] = {"shot": "look", "at": 4.0, "for": 5.0, "title": "Wickmere"}
	_expect_refused(def, "does not fit inside shot", "a title card longer than its shot")
	def = _minimal()
	def["title_card"] = {"shot": "nowhere", "at": 0.0, "for": 2.0, "title": "Wickmere"}
	_expect_refused(def, "which does not exist", "a title over a shot that is not there")


func test_the_content_loader_refuses_a_broken_cinematic() -> void:
	var def := _minimal()
	def.erase("shots")
	var problems := Schemas.validate_def(def, "test")
	assert_true(" ".join(problems).contains("missing required field 'shots'"), str(problems))
	def = _minimal()
	def["shots"][1]["keys"][0]["at"]["height"] = 0.1
	assert_false(Schemas.validate_def(def, "test").is_empty(), "the deep validator runs through the schema")


# --- its music --------------------------------------------------------------------------------------

func test_the_opening_has_its_own_cue_and_the_director_plays_holds_and_lets_it_go() -> void:
	var def := ContentDB.get_def(OPENING)
	var music := str(def.get("music", ""))
	assert_eq(music, "core:music/opening", "the opening names its cue")
	var stems: Dictionary = ContentDB.get_or_empty(music).get("stems", {})
	assert_true(ResourceLoader.exists(str(stems.get("main", ""))), "and the cue is on disk")
	Music.stop_all()
	Music.enabled = true
	Music.play_region("core:region/cinderlea", true)
	assert_true(Music.play_cue(music), "the director takes the cue")
	assert_eq(Music.overlay_kind(), "cue")
	Music.pause_cue(true)
	assert_false(Music.cue_playing(), "a held cue waits with the pictures")
	Music.pause_cue(false)
	Music.end_cue()
	assert_eq(Music.overlay_kind(), "", "and when control comes back the region's own music has the floor")
	assert_false(Music.play_cue(""), "no cue, no takeover")
	Music.stop_all()
