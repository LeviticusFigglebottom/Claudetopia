extends TestCase
## Standing and gossip: the deed table, the Hearth/Hollow and Renown tiers and their titles,
## witnesses, rumours spreading between settlements over game hours, decay, and both save
## sections. Runs against the live Social.Standing and Social.Gossip nodes.

const MERROWBY := "core:place/merrowby"
const TAMWICK := "core:place/tamwick"
const WARDENS_REST := "core:place/wardens_rest"
const ISSEVA := "core:place/isseva"

var standing: Node
var gossip: Node
var morality_events: Array = []
var renown_events: Array = []
var deed_events: Array = []


func before_each() -> void:
	standing = Social.standing
	gossip = Social.gossip
	standing.reset_for_new_game()
	gossip.reset_for_new_game()
	morality_events = []
	renown_events = []
	deed_events = []
	EventBus.morality_changed.connect(_on_morality)
	EventBus.renown_changed.connect(_on_renown)
	EventBus.deed_applied.connect(_on_deed)


func after_each() -> void:
	EventBus.morality_changed.disconnect(_on_morality)
	EventBus.renown_changed.disconnect(_on_renown)
	EventBus.deed_applied.disconnect(_on_deed)
	standing.reset_for_new_game()
	gossip.reset_for_new_game()


func _on_morality(value: int, delta: int, reason: String) -> void:
	morality_events.append({"value": value, "delta": delta, "reason": reason})


func _on_renown(value: int, delta: int, reason: String) -> void:
	renown_events.append({"value": value, "delta": delta, "reason": reason})


func _on_deed(deed_id: String, hearth: int, renown: int, witnesses: int) -> void:
	deed_events.append({"deed": deed_id, "hearth": hearth, "renown": renown, "witnesses": witnesses})


# --- the axes ---------------------------------------------------------------------------------

func test_axes_move_and_clamp() -> void:
	standing.add_morality(30, "test")
	assert_eq(standing.morality(), 30)
	standing.add_morality(-200)
	assert_eq(standing.morality(), -100, "the Hollow end is -100")
	standing.add_renown(2000)
	assert_eq(standing.renown(), 1000)
	standing.add_renown(-5000)
	assert_eq(standing.renown(), 0, "renown does not go below nothing")


func test_events_carry_the_reason() -> void:
	standing.add_renown(10, "a song")
	assert_eq(renown_events.size(), 1)
	assert_eq(str(renown_events[0]["reason"]), "a song")
	standing.add_renown(0)
	assert_eq(renown_events.size(), 1, "a change of nothing is not an event")


# --- tiers and titles --------------------------------------------------------------------------

func test_renown_tiers_and_titles() -> void:
	assert_eq(standing.renown_tier(), 0)
	assert_eq(standing.renown_title(), "", "a stranger has no title")
	standing.set_renown(25)
	assert_eq(standing.renown_tier(), 1)
	assert_eq(standing.renown_title(), "the Heard-Of")
	standing.set_renown(100)
	assert_eq(standing.renown_title(), "the Known")
	standing.set_renown(300)
	assert_eq(standing.renown_title(), "the Spoken-Of")
	standing.set_renown(600)
	assert_eq(standing.renown_tier(), 4)
	assert_eq(standing.renown_title(), "the Named")
	standing.set_renown(599)
	assert_eq(standing.renown_title(), "the Spoken-Of", "the tier boundary is exact")


func test_morality_tiers_are_signed() -> void:
	assert_eq(standing.morality_tier(), 0)
	standing.set_morality(40)
	assert_eq(standing.morality_tier(), 2)
	assert_eq(standing.morality_title(), "Hearth-Warm")
	standing.set_morality(80)
	assert_eq(standing.morality_tier(), 3)
	assert_eq(standing.morality_title(), "the Hearth-Kept")
	standing.set_morality(-40)
	assert_eq(standing.morality_tier(), -2)
	assert_eq(standing.morality_title(), "Quiet-eyed")
	standing.set_morality(-90)
	assert_eq(standing.morality_tier(), -3)
	assert_eq(standing.morality_title(), "the Hollow")
	standing.set_morality(-5)
	assert_eq(standing.morality_tier(), 0, "small sins do not show on the face")


func test_reaction_profile_is_the_contract_other_streams_read() -> void:
	standing.set_renown(320)
	standing.set_morality(-50)
	var p: Dictionary = standing.reaction_profile()
	for key in ["renown", "renown_tier", "morality", "morality_tier", "title"]:
		assert_has(p, key)
	assert_eq(int(p["renown_tier"]), 3)
	assert_eq(int(p["morality_tier"]), -2)
	assert_eq(str(p["title"]), "the Spoken-Of")
	assert_true(bool(p["hollow"]))


func test_title_falls_back_to_the_face_when_unknown() -> void:
	standing.set_morality(-80)
	assert_eq(standing.renown_title(), "")
	assert_eq(standing.title(), "the Hollow", "an unknown but Hollow stranger is still called something")


# --- deeds --------------------------------------------------------------------------------------

func test_deed_table_is_loaded_and_complete() -> void:
	var ids: Array = standing.deed_ids()
	assert_gt(ids.size(), 30)
	for id in ids:
		var row: Dictionary = standing.deed_row(id)
		assert_has(row, "hearth")
		assert_has(row, "renown")
		assert_has(row, "label")
		var rumour := str(row.get("rumour", ""))
		if rumour != "":
			assert_true(ContentDB.has(rumour), "deed %s names unknown rumour %s" % [id, rumour])


func test_deed_moves_both_axes() -> void:
	var result: Dictionary = standing.apply_deed("help_villager", ["core:npc/wardens_hesk"], MERROWBY)
	assert_eq(int(result["hearth"]), 3)
	assert_eq(int(result["renown"]), 3, "2 base plus 1 for the one witness")
	assert_eq(standing.morality(), 3)
	assert_eq(deed_events.size(), 1)
	assert_eq(int(deed_events[0]["witnesses"]), 1)


func test_murder_costs_the_hearth_and_buys_renown() -> void:
	var result: Dictionary = standing.apply_deed("murder", 2, MERROWBY)
	assert_eq(int(result["hearth"]), -25)
	assert_eq(int(result["renown"]), 10 + 4 * 2, "notoriety is renown, and witnesses spread it")
	assert_eq(standing.morality(), -25)
	assert_eq(standing.morality_tier(), -1, "one killing shows on the face, but not as the Hollow")


func test_witnesses_are_capped() -> void:
	var few: Dictionary = standing.apply_deed("boss_kill", 4)
	standing.reset_for_new_game()
	var many: Dictionary = standing.apply_deed("boss_kill", 40)
	assert_eq(int(few["renown"]), int(many["renown"]), "a crowd past the cap adds nothing more")
	assert_eq(int(many["renown"]), 40 + 5 * 4)


func test_unwitnessed_deeds_still_change_who_you_are() -> void:
	var result: Dictionary = standing.apply_deed("murder", [])
	assert_eq(int(result["hearth"]), -25, "nobody saw it; you still did it")
	assert_eq(int(result["renown"]), 10, "but only the deed itself is known")
	assert_empty(gossip.pool_of(MERROWBY), "and nobody is talking")


func test_repeating_a_kindness_softens_but_cruelty_does_not() -> void:
	var first: Dictionary = standing.apply_deed("help_villager", 1)
	var second: Dictionary = standing.apply_deed("help_villager", 1)
	assert_true(int(second["renown"]) <= int(first["renown"]), "the village stops being surprised")
	var murder_one: Dictionary = standing.apply_deed("murder", 1)
	var murder_two: Dictionary = standing.apply_deed("murder", 1)
	assert_eq(int(murder_two["hearth"]), int(murder_one["hearth"]), "cruelty never gets cheaper")


func test_unknown_deed_is_a_content_problem_not_a_crash() -> void:
	var result: Dictionary = standing.apply_deed("dance_with_a_bear", 1)
	assert_empty(result)
	assert_empty(deed_events)


func test_a_cold_deed_is_remembered_by_its_witnesses() -> void:
	assert_eq(str(standing.npc_witnessed("core:npc/wardens_dole")), "")
	standing.apply_deed("steal", ["core:npc/wardens_dole"], MERROWBY)
	assert_eq(str(standing.npc_witnessed("core:npc/wardens_dole")), "steal")
	standing.apply_deed("help_villager", ["core:npc/wardens_dole"], MERROWBY)
	assert_eq(str(standing.npc_witnessed("core:npc/wardens_dole")), "steal", "a good turn does not erase it")
	standing.forget_witness("core:npc/wardens_dole")
	assert_eq(str(standing.npc_witnessed("core:npc/wardens_dole")), "")


func test_disposition_is_per_npc_and_clamped() -> void:
	standing.add_disposition("core:npc/wardens_hesk", 30)
	assert_eq(standing.disposition("core:npc/wardens_hesk"), 30)
	assert_eq(standing.disposition("core:npc/wardens_dole"), 0)
	standing.add_disposition("core:npc/wardens_hesk", 500)
	assert_eq(standing.disposition("core:npc/wardens_hesk"), 100)


# --- gossip ----------------------------------------------------------------------------------------

func test_a_witnessed_deed_enters_the_local_pool() -> void:
	standing.apply_deed("boss_kill", ["core:npc/wardens_hesk"], MERROWBY)
	assert_true(gossip.knows_deed(MERROWBY, "boss_kill"))
	assert_false(gossip.knows_deed(ISSEVA, "boss_kill"), "the marsh has not heard yet")
	var pool: Array = gossip.pool_of(MERROWBY, {"player": "Wren"})
	assert_eq(pool.size(), 1)
	assert_eq(str(pool[0]["rumour"]), "core:rumour/boss_slain")
	assert_false(str(pool[0]["text"]).contains("{"), "the text is filled in, not a template")
	assert_true(str(pool[0]["text"]).contains("Merrowby") or str(pool[0]["text"]).contains("Wren"))


func test_rumours_spread_to_neighbouring_settlements_over_hours() -> void:
	gossip.add_rumour("core:rumour/boss_slain", MERROWBY, 1.0, "boss_kill")
	assert_empty(gossip.neighbours_of(MERROWBY).filter(func(n: Dictionary) -> bool: return gossip.knows_rumour(str(n["place"]), "core:rumour/boss_slain")))
	gossip.advance_hours(6.0)
	var reached: Array[String] = []
	for place in gossip.places_talking():
		if place != MERROWBY:
			reached.append(place)
	assert_gt(reached.size(), 0, "somebody carried it up the road")
	for place in reached:
		assert_true(gossip.heat_of(place, "core:rumour/boss_slain") < gossip.heat_of(MERROWBY, "core:rumour/boss_slain"), "second-hand news is cooler")


func test_spread_respects_distance() -> void:
	gossip.add_rumour("core:rumour/song", WARDENS_REST, 1.2, "song_sung")
	gossip.advance_hours(1.0)
	var near_hours := 999.0
	for link in gossip.neighbours_of(WARDENS_REST):
		near_hours = minf(near_hours, float(link["hours"]))
	assert_gt(near_hours, 0.0, "the talk graph knows how far apart places are")
	assert_false(gossip.knows_rumour(ISSEVA, "core:rumour/song"), "Sedgemire is a long walk from Hearthvale")


func test_rumours_cool_and_are_forgotten() -> void:
	gossip.add_rumour("core:rumour/bad_manners", MERROWBY, 0.4, "gesture_offence")
	var hot: float = gossip.heat_of(MERROWBY, "core:rumour/bad_manners")
	gossip.advance_hours(10.0)
	var warm: float = gossip.heat_of(MERROWBY, "core:rumour/bad_manners")
	assert_true(warm < hot, "talk cools")
	assert_true(warm > 0.0)
	gossip.advance_hours(200.0)
	assert_eq(gossip.heat_of(MERROWBY, "core:rumour/bad_manners"), 0.0, "and is finally forgotten")
	assert_false(gossip.knows_deed(MERROWBY, "gesture_offence"))


func test_hot_news_outlives_small_talk() -> void:
	gossip.add_rumour("core:rumour/murder", MERROWBY, 1.0, "murder")
	gossip.add_rumour("core:rumour/nosy_stranger", MERROWBY, 0.3, "trespass")
	gossip.advance_hours(40.0)
	assert_true(gossip.knows_deed(MERROWBY, "murder"), "blood is still being talked about")
	assert_false(gossip.knows_deed(MERROWBY, "trespass"), "nosiness is not")


func test_hottest_gives_the_village_something_to_say() -> void:
	gossip.add_rumour("core:rumour/board_job", MERROWBY, 0.4)
	gossip.add_rumour("core:rumour/child_returned", MERROWBY, 1.0, "child_returned")
	var top: Dictionary = gossip.hottest(MERROWBY, {"player": "Wren"})
	assert_eq(str(top["rumour"]), "core:rumour/child_returned")
	assert_false(str(top["text"]).is_empty())


func test_unknown_rumour_is_ignored_with_a_warning() -> void:
	gossip.add_rumour("core:rumour/not_a_thing", MERROWBY, 1.0)
	assert_empty(gossip.pool_of(MERROWBY))


func test_the_talk_graph_only_links_places_where_people_live() -> void:
	assert_empty(gossip.neighbours_of("core:place/hollin_barrow"), "a barrow does not gossip")
	var links: Array = gossip.neighbours_of(MERROWBY)
	assert_gt(links.size(), 0)
	for link in links:
		var kind := str(ContentDB.get_or_empty(str(link["place"])).get("kind", ""))
		assert_true(gossip.SETTLED_KINDS.has(kind), "%s is not a settled place" % link["place"])


func test_nearest_place_finds_where_it_was_seen() -> void:
	var merrowby_pos: Array = ContentDB.get_or_empty(MERROWBY)["position"]
	var near := Vector3(float(merrowby_pos[0]) + 30.0, 0.0, float(merrowby_pos[1]) - 20.0)
	assert_eq(gossip.nearest_place(near), MERROWBY)


func test_every_rumour_has_text_and_no_leftover_tokens() -> void:
	var rumours: Array = ContentDB.all("rumour")
	assert_gt(rumours.size(), 14, "at least fifteen rumours ship")
	for def in rumours:
		assert_has(def, "text")
		var text: String = gossip.rumour_text(str(def["id"]), MERROWBY, {"player": "Wren", "title": "the Known", "npc": "Hesk"})
		assert_false(text.is_empty(), "%s renders to nothing" % def["id"])
		assert_false(text.contains("{"), "%s still has a token: %s" % [def["id"], text])


# --- save -------------------------------------------------------------------------------------------

func test_standing_save_round_trip() -> void:
	standing.apply_deed("boss_kill", 3, MERROWBY)
	standing.apply_deed("steal", ["core:npc/wardens_dole"], MERROWBY)
	standing.add_disposition("core:npc/wardens_hesk", 25)
	var text := JSON.stringify(standing.to_save())
	var renown_before: int = standing.renown()
	var morality_before: int = standing.morality()

	standing.reset_for_new_game()
	assert_eq(standing.renown(), 0)

	standing.from_save(JSON.parse_string(text))
	assert_eq(standing.renown(), renown_before)
	assert_eq(standing.morality(), morality_before)
	assert_eq(standing.disposition("core:npc/wardens_hesk"), 25)
	assert_eq(str(standing.npc_witnessed("core:npc/wardens_dole")), "steal")
	assert_eq(standing.deed_count("boss_kill"), 1, "repeats keep softening across a save")


func test_gossip_save_round_trip_keeps_heat_and_spread() -> void:
	gossip.add_rumour("core:rumour/mercy", MERROWBY, 0.9, "mercy")
	gossip.advance_hours(5.0)
	var before_places: Array = gossip.places_talking()
	var heat_before: float = gossip.heat_of(MERROWBY, "core:rumour/mercy")
	var text := JSON.stringify(gossip.to_save())

	gossip.reset_for_new_game()
	assert_empty(gossip.places_talking())

	gossip.from_save(JSON.parse_string(text))
	assert_eq(gossip.places_talking(), before_places)
	assert_near(gossip.heat_of(MERROWBY, "core:rumour/mercy"), heat_before, 0.0001)
	assert_true(gossip.knows_deed(MERROWBY, "mercy"))
	# The spread record survives too, so a loaded game does not re-tell the same village.
	gossip.advance_hours(1.0)
	assert_true(gossip.heat_of(MERROWBY, "core:rumour/mercy") < heat_before)


func test_hour_changed_drives_the_pools() -> void:
	gossip.add_rumour("core:rumour/song", TAMWICK, 0.8, "song_sung")
	var before: float = gossip.heat_of(TAMWICK, "core:rumour/song")
	EventBus.hour_changed.emit(WorldClock.hour())
	assert_true(gossip.heat_of(TAMWICK, "core:rumour/song") < before, "an hour of the world passing cools the talk")
