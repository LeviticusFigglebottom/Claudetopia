extends TestCase
## The quest log (stages, objective trackers, markers, rewards, save) and the radiant job-board
## generator (determinism, region-appropriate targets, written journal text, rewards by danger).
## Runs against the live Social.quests / Social.radiant, with a faked inventory and player.

const WARDENS_Q1 := "core:quest/wardens_roll_of_names"
const HEARTHVALE := "core:region/hearthvale"
const MERROWBY := "core:place/merrowby"
const BELL := "core:item/wardens_hand_bell"

var log_node: Node
var radiant: RadiantGenerator
var ctx: SocialContext
var inventory: SocialFakes.FakeInventory
var player: SocialFakes.FakePlayer
var started: Array[String] = []
var stage_changes: Array = []
var completed: Array = []


func before_each() -> void:
	log_node = Social.quests
	radiant = Social.radiant
	ctx = Social.ctx
	log_node.reset_for_new_game()
	Social.standing.reset_for_new_game()
	Social.factions.reset_for_new_game()
	Social.gossip.reset_for_new_game()
	inventory = SocialFakes.FakeInventory.new()
	player = SocialFakes.FakePlayer.new()
	Social.bind("inventory", inventory)
	Social.bind("player", player)
	started = []
	stage_changes = []
	completed = []
	EventBus.quest_started.connect(_on_started)
	EventBus.quest_stage_changed.connect(_on_stage)
	EventBus.quest_completed.connect(_on_completed)


func after_each() -> void:
	EventBus.quest_started.disconnect(_on_started)
	EventBus.quest_stage_changed.disconnect(_on_stage)
	EventBus.quest_completed.disconnect(_on_completed)
	log_node.reset_for_new_game()
	log_node.position_provider = null
	Social.bind("inventory", null)
	Social.bind("player", null)


func _on_started(quest_id: String) -> void:
	started.append(quest_id)


func _on_stage(quest_id: String, stage: int) -> void:
	stage_changes.append({"quest": quest_id, "stage": stage})


func _on_completed(quest_id: String, outcome: String) -> void:
	completed.append({"quest": quest_id, "outcome": outcome})


## A small quest that exercises one objective type at a time.
func scripted_quest() -> Dictionary:
	return {
		"id": "core:quest/_test_scripted",
		"name": "A Scripted Errand",
		"layer": "side",
		"stages": [
			{"id": "kill_them", "journal": "Wolves in the dry valley.",
			 "objectives": [{"type": "kill", "target": "core:enemy/_test_wolf", "count": 2, "text": "Kill two wolves"}]},
			{"id": "fetch_it", "journal": "Bring back the bell.",
			 "objectives": [{"type": "collect", "target": BELL, "count": 1}]},
			{"id": "tell_them", "journal": "Tell Hesk.",
			 "on_enter": [{"set_flag": "_test_stage_entered"}],
			 "objectives": [{"type": "talk", "target": "core:npc/wardens_hesk"}],
			 "on_complete": [{"set_flag": "_test_stage_done"}]},
			{"id": "done", "auto": true, "journal": "Finished.", "objectives": []}
		],
		"rewards": {"marks": 50, "renown": 5, "rep": [["core:faction/wardens", 4]], "items": [["core:item/wardens_lantern_badge", 1]]}
	}


# --- life cycle ---------------------------------------------------------------------------------

func test_start_records_the_journal_and_the_first_stage() -> void:
	log_node.register_runtime(scripted_quest())
	assert_true(log_node.start("core:quest/_test_scripted"))
	assert_eq(started, ["core:quest/_test_scripted"])
	assert_true(log_node.is_active("core:quest/_test_scripted"))
	assert_eq(log_node.stage_of("core:quest/_test_scripted"), 0)
	assert_eq(log_node.stage_id_of("core:quest/_test_scripted"), "kill_them")
	var entry: Dictionary = log_node.entry("core:quest/_test_scripted")
	assert_eq(entry["journal"], ["Wolves in the dry valley."])
	assert_eq(entry["objectives"][0]["text"], "Kill two wolves")
	assert_eq(int(entry["objectives"][0]["needed"]), 2)
	assert_false(bool(entry["objectives"][0]["done"]))


func test_starting_twice_is_refused() -> void:
	log_node.register_runtime(scripted_quest())
	assert_true(log_node.start("core:quest/_test_scripted"))
	assert_false(log_node.start("core:quest/_test_scripted"))


func test_unknown_quest_is_a_content_problem_not_a_crash() -> void:
	assert_false(log_node.start("core:quest/nothing_like_this"))
	assert_empty(started)


# --- objective trackers ---------------------------------------------------------------------------

func test_kills_advance_the_stage() -> void:
	log_node.register_runtime(scripted_quest())
	log_node.start("core:quest/_test_scripted")
	EventBus.entity_killed.emit(null, null, "core:enemy/_test_wolf")
	assert_eq(log_node.stage_id_of("core:quest/_test_scripted"), "kill_them", "one of two")
	assert_eq(int(log_node.objectives_of("core:quest/_test_scripted")[0]["count"]), 1)
	EventBus.entity_killed.emit(null, null, "core:enemy/_test_wolf")
	assert_eq(log_node.stage_id_of("core:quest/_test_scripted"), "fetch_it", "the stage closed itself")
	assert_eq(stage_changes.size(), 2)


func test_wrong_target_does_not_count() -> void:
	log_node.register_runtime(scripted_quest())
	log_node.start("core:quest/_test_scripted")
	EventBus.entity_killed.emit(null, null, "core:enemy/_test_boar")
	assert_eq(int(log_node.objectives_of("core:quest/_test_scripted")[0]["count"]), 0)


func test_collect_counts_items_and_the_stage_syncs_on_entry() -> void:
	log_node.register_runtime(scripted_quest())
	log_node.start("core:quest/_test_scripted")
	inventory.add(BELL, 1)                      # picked up early, before the stage asks for it
	EventBus.entity_killed.emit(null, null, "core:enemy/_test_wolf")
	EventBus.entity_killed.emit(null, null, "core:enemy/_test_wolf")
	assert_eq(log_node.stage_id_of("core:quest/_test_scripted"), "tell_them",
		"the fetch stage was already satisfied by what was in the pack")
	assert_true(ctx.has_flag("_test_stage_entered"), "on_enter effects ran")


func test_talking_closes_a_talk_objective_and_runs_on_complete() -> void:
	log_node.register_runtime(scripted_quest())
	log_node.start("core:quest/_test_scripted")
	log_node.set_stage("core:quest/_test_scripted", "tell_them")
	EventBus.dialogue_ended.emit("core:npc/wardens_dole")
	assert_true(log_node.is_active("core:quest/_test_scripted"), "the wrong NPC does not count")
	EventBus.dialogue_ended.emit("core:npc/wardens_hesk")
	assert_true(ctx.has_flag("_test_stage_done"))
	assert_true(log_node.is_completed("core:quest/_test_scripted"), "the auto stage closed the quest")


func test_rewards_are_granted_on_completion() -> void:
	log_node.register_runtime(scripted_quest())
	log_node.start("core:quest/_test_scripted")
	log_node.set_stage("core:quest/_test_scripted", "done")
	assert_eq(completed.size(), 1)
	assert_eq(inventory.marks(), 50)
	assert_eq(inventory.count("core:item/wardens_lantern_badge"), 1)
	assert_eq(Social.factions.reputation("core:faction/wardens"), 4)
	assert_gt(Social.standing.renown(), 0, "finishing a side quest is worth being known for")


func test_rest_book_use_and_escort_objectives() -> void:
	var def := scripted_quest()
	def["id"] = "core:quest/_test_events"
	def["stages"] = [
		{"id": "rest", "journal": "Rest.", "objectives": [{"type": "rest_at", "target": "core:place/merrowby"}]},
		{"id": "read", "journal": "Read.", "objectives": [{"type": "read_book", "target": "core:book/_test"}]},
		{"id": "use", "journal": "Use.", "objectives": [{"type": "use_item", "target": BELL}]},
		{"id": "escort", "journal": "Escort.", "objectives": [{"type": "escort", "target": "core:npc/wardens_ryn", "place": MERROWBY}]},
		{"id": "done", "auto": true, "journal": "Done.", "objectives": []}
	]
	log_node.register_runtime(def)
	log_node.start("core:quest/_test_events")
	EventBus.hearthstone_rested.emit("core:place/merrowby")
	assert_eq(log_node.stage_id_of("core:quest/_test_events"), "read")
	EventBus.book_opened.emit("core:book/_test")
	assert_eq(log_node.stage_id_of("core:quest/_test_events"), "use")
	close_screen("book", "opening a book draws it")
	EventBus.item_used.emit(BELL, [])
	assert_eq(log_node.stage_id_of("core:quest/_test_events"), "escort")
	EventBus.escort_arrived.emit("core:npc/wardens_ryn", "core:place/tamwick")
	assert_true(log_node.is_active("core:quest/_test_events"), "the wrong destination does not count")
	EventBus.escort_arrived.emit("core:npc/wardens_ryn", MERROWBY)
	assert_true(log_node.is_completed("core:quest/_test_events"))


func test_reach_objectives_use_the_position_provider() -> void:
	var def := scripted_quest()
	def["id"] = "core:quest/_test_reach"
	def["stages"] = [
		{"id": "go", "journal": "Go there.", "objectives": [{"type": "reach", "target": MERROWBY, "radius": 60}]},
		{"id": "done", "auto": true, "journal": "Arrived.", "objectives": []}
	]
	log_node.register_runtime(def)
	log_node.position_provider = player
	var pos: Array = ContentDB.get_or_empty(MERROWBY)["position"]
	player.pos = Vector3(float(pos[0]) + 500.0, 0.0, float(pos[1]))
	log_node.start("core:quest/_test_reach")
	log_node.check_reach()
	assert_true(log_node.is_active("core:quest/_test_reach"), "still half a kilometre away")
	player.pos = Vector3(float(pos[0]) + 20.0, 0.0, float(pos[1]) + 10.0)
	log_node.check_reach()
	assert_true(log_node.is_completed("core:quest/_test_reach"))


func test_reach_works_with_a_plain_node3d_player() -> void:
	# Other streams' player doubles are Node3Ds with no position() method; the seam must take
	# either shape, because the real player will be a CharacterBody3D.
	var node_player: Node3D = preload("res://tests/fakes/fake_player.gd").new()
	Engine.get_main_loop().root.add_child(node_player)
	var def := scripted_quest()
	def["id"] = "core:quest/_test_reach_node"
	def["stages"] = [
		{"id": "go", "journal": "Go there.", "objectives": [{"type": "reach", "target": MERROWBY, "radius": 60}]},
		{"id": "done", "auto": true, "journal": "Arrived.", "objectives": []}
	]
	log_node.register_runtime(def)
	Social.bind("player", node_player)
	assert_eq(log_node.position_provider, node_player, "a Node3D counts as a position provider")
	var pos: Array = ContentDB.get_or_empty(MERROWBY)["position"]
	node_player.global_position = Vector3(float(pos[0]), 0.0, float(pos[1]))
	log_node.start("core:quest/_test_reach_node")
	log_node.check_reach()
	assert_true(log_node.is_completed("core:quest/_test_reach_node"))
	node_player.queue_free()


func test_marks_can_be_a_property_on_the_inventory() -> void:
	var node_inventory: Node = preload("res://tests/fakes/fake_inventory.gd").new()
	Engine.get_main_loop().root.add_child(node_inventory)
	Social.bind("inventory", node_inventory)
	ctx.add_marks(25)
	assert_eq(ctx.marks(), 25, "the inventory stream may expose marks as a property")
	ctx.add_marks(-10)
	assert_eq(ctx.marks(), 15)
	node_inventory.queue_free()


func test_discovering_a_place_also_satisfies_reach() -> void:
	var def := scripted_quest()
	def["id"] = "core:quest/_test_discover"
	def["stages"] = [
		{"id": "go", "journal": "Find it.", "objectives": [{"type": "reach", "target": "core:poi/tumbled_watchtower"}]},
		{"id": "done", "auto": true, "journal": "Found.", "objectives": []}
	]
	log_node.register_runtime(def)
	log_node.start("core:quest/_test_discover")
	EventBus.place_discovered.emit("core:poi/tumbled_watchtower")
	assert_true(log_node.is_completed("core:quest/_test_discover"))


func test_choice_objectives_record_an_outcome() -> void:
	var def := scripted_quest()
	def["id"] = "core:quest/_test_choice"
	def["stages"] = [
		{"id": "decide", "journal": "Decide.", "objectives": [
			{"type": "choice", "target": "the_roll", "options": ["restore", "strike"],
			 "effects_by_option": {"restore": [{"set_flag": "_test_restored"}], "strike": [{"set_flag": "_test_struck"}]}}]},
		{"id": "done", "auto": true, "journal": "Written.", "objectives": []}
	]
	log_node.register_runtime(def)
	log_node.start("core:quest/_test_choice")
	log_node.choose("core:quest/_test_choice", "restore")
	assert_true(ctx.has_flag("_test_restored"))
	assert_false(ctx.has_flag("_test_struck"))
	assert_true(log_node.is_completed("core:quest/_test_choice"))
	assert_eq(log_node.outcome_of("core:quest/_test_choice"), "restore")


## Options written as objects, which is how every quest in the pack but the Wardens' first one
## writes them. `["a", "b"].has(option)` is false for a list of objects, so none of those
## choices closed and none of their effects ran: the quests could not be finished at all.
func test_options_written_as_objects_are_answerable() -> void:
	var def := scripted_quest()
	def["id"] = "core:quest/_test_option_objects"
	def["stages"] = [
		{"id": "decide", "journal": "Decide.", "objectives": [
			{"type": "choice", "target": "the_stone", "options": [
				{"id": "name_it", "text": "Name it.", "effects": [{"set_flag": "_test_named"}, {"renown": 7}]},
				{"id": "leave_it", "text": "Leave it.", "effects": [{"set_flag": "_test_left"}]}
			]}]},
		{"id": "done", "auto": true, "journal": "Said.", "objectives": []}
	]
	log_node.register_runtime(def)
	log_node.start("core:quest/_test_option_objects")
	log_node.choose("core:quest/_test_option_objects", "name_it")
	assert_true(ctx.has_flag("_test_named"), "the option's own effects ran")
	assert_false(ctx.has_flag("_test_left"))
	assert_gt(Social.standing.renown(), 0)
	assert_true(log_node.is_completed("core:quest/_test_option_objects"), "and the objective closed")
	assert_eq(log_node.outcome_of("core:quest/_test_option_objects"), "name_it")


func test_an_option_whose_conditions_are_unmet_is_refused() -> void:
	var def := scripted_quest()
	def["id"] = "core:quest/_test_gated_option"
	def["stages"] = [
		{"id": "decide", "journal": "Decide.", "objectives": [
			{"type": "choice", "target": "the_scraped_name", "options": [
				{"id": "say_it", "text": "Say the name.", "conditions": [{"flag": "_test_found_it"}],
				 "effects": [{"set_flag": "_test_said_it"}]},
				{"id": "say_nothing", "text": "Say nothing.", "effects": [{"set_flag": "_test_said_nothing"}]}
			]}]},
		{"id": "done", "auto": true, "journal": "Said.", "objectives": []}
	]
	log_node.register_runtime(def)
	log_node.start("core:quest/_test_gated_option")
	assert_eq(log_node.open_options("core:quest/_test_gated_option").size(), 1, "only the open option is offered")
	log_node.choose("core:quest/_test_gated_option", "say_it")
	assert_false(ctx.has_flag("_test_said_it"), "a name you have not found cannot be said")
	assert_true(log_node.is_active("core:quest/_test_gated_option"))
	ctx.set_flag("_test_found_it")
	assert_eq(log_node.open_options("core:quest/_test_gated_option").size(), 2)
	log_node.choose("core:quest/_test_gated_option", "say_it")
	assert_true(ctx.has_flag("_test_said_it"))
	assert_true(log_node.is_completed("core:quest/_test_gated_option"))


func test_a_branching_option_lands_on_the_stage_it_names() -> void:
	var def := scripted_quest()
	def["id"] = "core:quest/_test_branch"
	def["stages"] = [
		{"id": "decide", "journal": "Decide.", "objectives": [
			{"type": "choice", "target": "which_way", "options": [
				{"id": "left", "text": "Left.", "effects": [{"quest_stage": ["core:quest/_test_branch", "the_left_way"]}]},
				{"id": "right", "text": "Right.", "effects": [{"quest_stage": ["core:quest/_test_branch", "the_right_way"]}]}
			]}]},
		{"id": "the_left_way", "journal": "Left.", "objectives": [{"type": "talk", "target": "core:npc/wardens_hesk"}]},
		{"id": "the_right_way", "journal": "Right.", "objectives": [{"type": "talk", "target": "core:npc/wardens_dole"}]},
		{"id": "done", "auto": true, "journal": "Arrived.", "objectives": []}
	]
	log_node.register_runtime(def)
	log_node.start("core:quest/_test_branch")
	log_node.choose("core:quest/_test_branch", "right")
	assert_eq(log_node.stage_id_of("core:quest/_test_branch"), "the_right_way",
		"the branch the option named, not the next stage in the list")


func test_failing_a_quest_stops_it() -> void:
	log_node.register_runtime(scripted_quest())
	log_node.start("core:quest/_test_scripted")
	log_node.fail("core:quest/_test_scripted", "the miller died first")
	assert_true(log_node.is_failed("core:quest/_test_scripted"))
	assert_false(log_node.is_active("core:quest/_test_scripted"))
	EventBus.entity_killed.emit(null, null, "core:enemy/_test_wolf")
	assert_empty(log_node.objectives_of("core:quest/_test_scripted"), "a dead quest tracks nothing")


# --- lists and markers ---------------------------------------------------------------------------

func test_active_and_completed_lists() -> void:
	log_node.register_runtime(scripted_quest())
	log_node.start("core:quest/_test_scripted")
	var active: Array[Dictionary] = log_node.active_quests()
	assert_eq(active.size(), 1)
	for key in ["id", "name", "layer", "journal", "objectives"]:
		assert_has(active[0], key)
	assert_empty(log_node.completed_quests())
	log_node.complete("core:quest/_test_scripted", "")
	assert_empty(log_node.active_quests())
	assert_eq(log_node.completed_quests().size(), 1)


func test_markers_are_areas_never_pins() -> void:
	log_node.start(WARDENS_Q1)
	var markers: Array[Dictionary] = log_node.active_markers()
	assert_gt(markers.size(), 0)
	for m in markers:
		assert_true(m.has("place_id") or m.has("region_id"), "a marker names a place, not a point")
		assert_gt(float(m["radius"]), 50.0, "markers are approximate areas")
		assert_false(m.has("position"), "the map never spoon-feeds an exact pin")
		assert_eq(str(m["quest_id"]), WARDENS_Q1)


func test_markers_follow_the_stage() -> void:
	log_node.start(WARDENS_Q1)
	log_node.set_stage(WARDENS_Q1, "the_tumbled_watch")
	var places: Array[String] = []
	for m in log_node.active_markers():
		places.append(str(m.get("place_id", "")))
	assert_true(places.has("core:poi/tumbled_watchtower"))


# --- the authored Wardens quest ---------------------------------------------------------------------

func test_wardens_quest_walks_its_stages() -> void:
	assert_true(log_node.start(WARDENS_Q1))
	assert_eq(log_node.stage_id_of(WARDENS_Q1), "summons")
	EventBus.dialogue_ended.emit("core:npc/wardens_hesk")
	assert_eq(log_node.stage_id_of(WARDENS_Q1), "the_tumbled_watch")

	EventBus.place_discovered.emit("core:poi/tumbled_watchtower")
	inventory.add(BELL, 1)
	assert_eq(log_node.stage_id_of(WARDENS_Q1), "bring_it_back")

	EventBus.dialogue_ended.emit("core:npc/wardens_hesk")
	assert_eq(log_node.stage_id_of(WARDENS_Q1), "who_struck_it")
	EventBus.dialogue_ended.emit("core:npc/wardens_dole")
	assert_eq(log_node.stage_id_of(WARDENS_Q1), "find_the_name")

	EventBus.place_discovered.emit("core:poi/gosling_pit")
	EventBus.dialogue_ended.emit("core:npc/wardens_ryn")
	assert_eq(log_node.stage_id_of(WARDENS_Q1), "the_pen")

	log_node.choose(WARDENS_Q1, "restore")
	assert_true(log_node.is_completed(WARDENS_Q1))
	assert_eq(log_node.outcome_of(WARDENS_Q1), "restore")
	assert_true(Social.factions.is_member("core:faction/wardens"), "the closing stage swears you in")
	assert_gt(Social.factions.reputation("core:faction/wardens"), 30)
	assert_eq(inventory.count("core:item/wardens_lantern_badge"), 1)
	assert_gt(Social.standing.morality(), 0, "restoring a name is a Hearth deed")


func test_wardens_quest_journal_is_written_and_placeholder_free() -> void:
	log_node.start(WARDENS_Q1)
	for stage_id in ["the_tumbled_watch", "bring_it_back", "who_struck_it", "find_the_name", "the_pen"]:
		log_node.set_stage(WARDENS_Q1, stage_id)
	var entry: Dictionary = log_node.entry(WARDENS_Q1)
	assert_gt((entry["journal"] as Array).size(), 4)
	for line in entry["journal"]:
		assert_false(str(line).contains("{"), "journal line still has a token: %s" % line)
		assert_gt(str(line).length(), 40, "journal lines are written, not stubs")


func test_striking_the_name_is_the_other_ending() -> void:
	log_node.start(WARDENS_Q1)
	log_node.set_stage(WARDENS_Q1, "the_pen")
	log_node.choose(WARDENS_Q1, "strike")
	assert_eq(log_node.outcome_of(WARDENS_Q1), "strike")
	assert_true(Social.standing.morality() < 0, "striking a name costs the Hearth")
	assert_eq(ctx.get_flag("wardens_roll_ryn", ""), "struck")


# --- radiant -----------------------------------------------------------------------------------------

func test_six_templates_ship_and_are_shaped_right() -> void:
	var templates: Array[Dictionary] = radiant.templates()
	assert_eq(templates.size(), 6)
	var kinds: Array[String] = []
	for t in templates:
		var spec: Dictionary = t["template"]
		kinds.append(str(spec["kind"]))
		assert_gt((spec.get("names", []) as Array).size(), 1, "%s needs text variants" % t["id"])
		assert_gt((spec.get("journal", []) as Array).size(), 1)
		assert_gt((spec.get("board_lines", []) as Array).size(), 1)
		assert_gt((t.get("stages", []) as Array).size(), 0)
	for kind in ["bounty", "hunt", "deliver", "clear", "escort", "fetch"]:
		assert_true(kinds.has(kind), "missing the %s template" % kind)


func test_generation_is_deterministic_for_a_seed() -> void:
	var first: Array[Dictionary] = radiant.generate(HEARTHVALE, 3, MERROWBY, 4242)
	var second: Array[Dictionary] = radiant.generate(HEARTHVALE, 3, MERROWBY, 4242)
	assert_eq(first.size(), second.size())
	assert_gt(first.size(), 0, "Hearthvale has content to make work from")
	for i in first.size():
		assert_eq(str(first[i]["id"]), str(second[i]["id"]), "the same board on the same day offers the same work")
		assert_eq(str(first[i]["name"]), str(second[i]["name"]))
		assert_eq(JSON.stringify(first[i]["stages"]), JSON.stringify(second[i]["stages"]))
	var other: Array[Dictionary] = radiant.generate(HEARTHVALE, 3, MERROWBY, 99)
	var same := other.size() == first.size()
	if same:
		for i in first.size():
			if str(other[i]["id"]) != str(first[i]["id"]):
				same = false
	assert_false(same, "a different seed offers different work")


func test_generated_quests_are_placeholder_free_and_runnable() -> void:
	var jobs: Array[Dictionary] = radiant.generate(HEARTHVALE, 4, MERROWBY, 77)
	assert_gt(jobs.size(), 0)
	for job in jobs:
		assert_true(Ids.is_valid(str(job["id"])), "%s is not a valid id" % job["id"])
		assert_eq(str(job["layer"]), "radiant")
		assert_false(str(job["name"]).contains("{"), "unfilled name: %s" % job["name"])
		for stage in job["stages"]:
			assert_false(str((stage as Dictionary).get("journal", "")).contains("{"),
				"unfilled journal in %s: %s" % [job["id"], stage.get("journal", "")])
			for o in (stage as Dictionary).get("objectives", []):
				var target := str((o as Dictionary).get("target", ""))
				assert_false(target.contains("{"), "unfilled target in %s" % job["id"])
				if target != "":
					assert_true(ContentDB.has(target), "%s targets unknown %s" % [job["id"], target])
				assert_false(str((o as Dictionary).get("text", "")).contains("{"))
		assert_true(log_node.start(str(job["id"])), "a generated quest can be taken")
		assert_true(log_node.is_active(str(job["id"])))


func test_rewards_scale_with_danger() -> void:
	var calm: Array[Dictionary] = radiant.generate(HEARTHVALE, 3, MERROWBY, 5)
	var grim: Array[Dictionary] = radiant.generate("core:region/cinderlea", 3, "core:place/pilgrims_ash", 5)
	if calm.is_empty() or grim.is_empty():
		return
	var calm_max := 0
	var grim_max := 0
	for j in calm:
		calm_max = maxi(calm_max, int((j["rewards"] as Dictionary).get("marks", 0)))
	for j in grim:
		grim_max = maxi(grim_max, int((j["rewards"] as Dictionary).get("marks", 0)))
	assert_gt(grim_max, calm_max, "Cinderlea pays better because Cinderlea is worse")


func test_generated_targets_belong_to_the_region() -> void:
	var jobs: Array[Dictionary] = radiant.generate(HEARTHVALE, 5, MERROWBY, 31)
	for job in jobs:
		for stage in job["stages"]:
			for o in (stage as Dictionary).get("objectives", []):
				var target := str((o as Dictionary).get("target", ""))
				var type := Ids.type_of(target)
				if type == "poi":
					assert_eq(str(ContentDB.get_or_empty(target).get("region", "")), HEARTHVALE)


func test_boards_keep_their_notices_until_the_cooldown_passes() -> void:
	var first: Array[Dictionary] = radiant.generate_for_board(MERROWBY, HEARTHVALE, 3)
	var again: Array[Dictionary] = radiant.generate_for_board(MERROWBY, HEARTHVALE, 3)
	assert_eq(first.size(), again.size())
	for i in first.size():
		assert_eq(str(first[i]["id"]), str(again[i]["id"]), "the board has not been repapered yet")
	assert_gt(radiant.board_cooldown_remaining(MERROWBY), 0.0)
	WorldClock.advance_hours(radiant.DEFAULT_COOLDOWN_HOURS + 1.0)
	assert_eq(radiant.board_cooldown_remaining(MERROWBY), 0.0)
	var fresh: Array[Dictionary] = radiant.generate_for_board(MERROWBY, HEARTHVALE, 3)
	assert_gt(fresh.size(), 0)


func test_every_template_generates_once_the_world_has_enemies_and_goods() -> void:
	# The bestiary and the item tables belong to other streams; with them stood in, all six
	# templates must produce work, which is what the generator promises job boards.
	var rich := RadiantGenerator.new(log_node, Social.factions, SocialFakes.hearthvale_content())
	var kinds: Dictionary = {}
	for seed_value in [11, 22, 33, 44, 55, 66, 77, 88]:
		for job in rich.generate(HEARTHVALE, 6, MERROWBY, seed_value):
			kinds[str(job["kind"])] = true
			for stage in job["stages"]:
				for o in (stage as Dictionary).get("objectives", []):
					assert_false(str((o as Dictionary).get("target", "")).contains("{"))
	for kind in ["bounty", "hunt", "deliver", "clear", "escort", "fetch"]:
		assert_true(kinds.has(kind), "the %s template never produced work" % kind)


func test_kill_targets_come_from_the_regions_ecology() -> void:
	var rich := RadiantGenerator.new(log_node, Social.factions, SocialFakes.hearthvale_content())
	var seen_bounty := false
	var seen_hunt := false
	for seed_value in [3, 13, 23, 43, 53, 63, 73, 83, 93]:
		for job in rich.generate(HEARTHVALE, 6, MERROWBY, seed_value):
			for stage in job["stages"]:
				for o in (stage as Dictionary).get("objectives", []):
					if str((o as Dictionary).get("type", "")) != "kill":
						continue
					var target := str((o as Dictionary)["target"])
					var def: Dictionary = SocialFakes.hearthvale_content().get_or_empty(target)
					assert_eq(str(def.get("region", "")), HEARTHVALE, "%s is not native here" % target)
					if str(job["kind"]) == "bounty":
						seen_bounty = true
						assert_true((def.get("tags", []) as Array).has("bandit"), "bounty target %s is not tagged bandit" % target)
					if str(job["kind"]) == "hunt":
						seen_hunt = true
						assert_true((def.get("tags", []) as Array).has("beast"), "hunt target %s is not tagged beast" % target)
	assert_true(seen_bounty and seen_hunt, "both kill templates were exercised")


func test_board_jobs_through_social() -> void:
	var jobs: Array[Dictionary] = Social.board_jobs("core:place/tamwick", HEARTHVALE, 2)
	assert_gt(jobs.size(), 0)
	assert_true(Social.take_quest(str(jobs[0]["id"])))


# --- save ---------------------------------------------------------------------------------------------

func test_save_round_trip_keeps_progress_and_generated_quests() -> void:
	log_node.start(WARDENS_Q1)
	EventBus.dialogue_ended.emit("core:npc/wardens_hesk")
	var jobs: Array[Dictionary] = radiant.generate(HEARTHVALE, 2, MERROWBY, 808)
	assert_gt(jobs.size(), 0)
	var job_id := str(jobs[0]["id"])
	log_node.start(job_id)
	var job_name: String = log_node.entry(job_id)["name"]

	var text := JSON.stringify(log_node.to_save())
	log_node.reset_for_new_game()
	assert_false(log_node.is_active(WARDENS_Q1))

	log_node.from_save(JSON.parse_string(text))
	assert_true(log_node.is_active(WARDENS_Q1))
	assert_eq(log_node.stage_id_of(WARDENS_Q1), "the_tumbled_watch")
	assert_gt((log_node.entry(WARDENS_Q1)["journal"] as Array).size(), 1)
	assert_true(log_node.is_active(job_id), "a generated quest survives a save")
	assert_eq(str(log_node.entry(job_id)["name"]), job_name, "with its own written name")
	assert_gt((log_node.entry(job_id)["objectives"] as Array).size(), 0, "and its objectives")


func test_save_round_trip_through_the_save_system() -> void:
	log_node.start(WARDENS_Q1)
	EventBus.dialogue_ended.emit("core:npc/wardens_hesk")
	var data := SaveSystem.serialize()
	assert_has(data["sections"], "quests")
	assert_has(data["sections"], "factions")
	assert_has(data["sections"], "standing")
	assert_has(data["sections"], "gossip")
	var text := JSON.stringify(data)
	log_node.reset_for_new_game()
	SaveSystem.deserialize(JSON.parse_string(text))
	assert_true(log_node.is_active(WARDENS_Q1))
	assert_eq(log_node.stage_id_of(WARDENS_Q1), "the_tumbled_watch")


## A quest log that has outlived the body it was watching.
##
## `position_provider` is bound to the player, and nothing told the quest log when that player
## was freed -- a body that died, a scene that changed, a test that finished. `check_reach` then
## handed the dead reference to `SocialContext.can_locate`, and passing a freed instance to a
## typed Object parameter is a script error in its own right: a hundred and nine of the one
## hundred and thirteen a full test run logged came from this one line, reached from `_sync_stage`
## every time a stage was entered. The log drops a provider that no longer exists.
func test_a_freed_player_is_dropped_rather_than_called_through() -> void:
	var gone: Node3D = preload("res://tests/fakes/fake_player.gd").new()
	Engine.get_main_loop().root.add_child(gone)
	Social.bind("player", gone)
	assert_eq(log_node.position_provider, gone)
	gone.get_parent().remove_child(gone)
	gone.free()
	assert_false(is_instance_valid(gone), "the body is gone")
	log_node.check_reach()
	# A freed reference compares equal to null, so `== null` cannot tell the two apart and a
	# test written that way passes while the error is still being logged. The variant's type can:
	# a dropped provider is nil, a dead one is still an Object.
	assert_eq(typeof(log_node.position_provider), TYPE_NIL,
		"the log is still holding a freed player, and calls can_locate through it")


## The other end of the same seam: a bound provider that leaves the tree takes its binding with
## it, so nothing has to notice afterwards that it is dead.
func test_a_player_leaving_the_tree_unbinds_itself() -> void:
	var leaving: Node3D = preload("res://tests/fakes/fake_player.gd").new()
	Engine.get_main_loop().root.add_child(leaving)
	Social.bind("player", leaving)
	assert_eq(Social.ctx.provider("player"), leaving)
	leaving.get_parent().remove_child(leaving)
	assert_eq(Social.ctx.provider("player"), null, "the context still names a body that walked out")
	assert_eq(log_node.position_provider, null, "and the log still polls it")
	leaving.free()
