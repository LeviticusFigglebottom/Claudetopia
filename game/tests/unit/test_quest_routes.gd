extends TestCase
## The ways a quest objective gets closed that nobody wrote a line for.
##
## Walking every quest in the pack found nine objectives no player could close: five deliveries
## with no line anywhere to hand the thing over on, and four of the main thread's decisions with no
## button anywhere to decide them on (the fifth, the note itself, is `ChoicePoint`'s). Two more asked
## you to *use* a tool, and nothing could. These press the buttons a player would.

const LOUDER_THAN_BOOKS := "core:quest/louder_than_books"
const WATER_KEPT := "core:quest/what_the_water_kept"
const ROPE := "core:quest/a_hand_on_the_rope"
const BRIAR := "core:quest/the_briars_purpose"
const VIGIL := "core:quest/vigil"
const FORTY_ONE := "core:quest/forty_one_places"
const WARDENS_Q1 := "core:quest/wardens_roll_of_names"
const LOUDER := "core:quest/louder"
const LETTER := "core:item/letter_to_the_circle"
const ALDITH := "core:npc/aldith_sulion"

## Each unwritten decision, who is asked it, and one option to take.
const DECISIONS := [
	[LOUDER_THAN_BOOKS, "the_price", ALDITH, "accept"],
	[WATER_KEPT, "whose_bell", "core:npc/tallissa_oul", "to_water"],
	[ROPE, "the_eighth_verse", "core:npc/dunna_ko_kharrow", "give_name"],
	[BRIAR, "the_briars_purpose", "core:npc/alder_wyke", "name_woodfolk"],
]

var log_node: Node
var inventory: SocialFakes.FakeInventory
var sayings: SocialFakes.Sayings


func before_each() -> void:
	log_node = Social.quests
	GameState.reset_for_new_game(1)
	log_node.reset_for_new_game()
	Social.standing.reset_for_new_game()
	Social.factions.reset_for_new_game()
	inventory = SocialFakes.FakeInventory.new()
	sayings = SocialFakes.Sayings.new()
	Social.bind("inventory", inventory)
	Social.bind("sayings", sayings)


func after_each() -> void:
	if Social.dialogue.is_running():
		Social.dialogue.stop()
	UI.close_all()
	log_node.reset_for_new_game()
	Social.standing.reset_for_new_game()
	Social.factions.reset_for_new_game()
	Social.bind("inventory", null)
	Social.bind("sayings", null)
	Social.refresh_providers()


func _talk_to(npc_id: String) -> Node:
	var runner := Social.talk(npc_id)
	for i in 8:
		if not runner.is_running() or not runner.current_choices.is_empty():
			break
		runner.advance()
	return runner


func _offered(runner: Node) -> Array[String]:
	var out: Array[String] = []
	for c in runner.current_choices:
		out.append(str((c as Dictionary).get("text", "")))
	return out


func _option_text(quest_id: String, stage_id: String, option: String) -> String:
	var def := ContentDB.get_or_empty(quest_id)
	for stage in def.get("stages", []):
		if str((stage as Dictionary).get("id", "")) != stage_id:
			continue
		for o in (stage as Dictionary).get("objectives", []):
			for entry in (o as Dictionary).get("options", []):
				if typeof(entry) == TYPE_DICTIONARY and str(entry.get("id", "")) == option:
					return str(entry.get("text", ""))
	return ""


# --- decisions nobody wrote a button for ---------------------------------------------------------------

func test_the_main_threads_decisions_are_put_by_the_people_who_host_them() -> void:
	for row in DECISIONS:
		log_node.reset_for_new_game()
		var quest_id: String = row[0]
		assert_true(log_node.start(quest_id), "%s would not start" % quest_id)
		log_node.set_stage(quest_id, row[1])
		var offers: Array[Dictionary] = log_node.unwritten_choices_for(row[2])
		assert_gt(offers.size(), 1, "%s asks %s nothing at %s" % [quest_id, row[2], row[1]])
		var text := _option_text(quest_id, row[1], row[3])
		var runner := _talk_to(row[2])
		assert_true(_offered(runner).has(text), "%s's conversation does not offer '%s'; got %s" % [row[2], text, str(_offered(runner))])
		var picked := false
		for i in (runner.current_choices as Array).size():
			if str((runner.current_choices[i] as Dictionary).get("text", "")) == text:
				runner.choose(i)
				picked = true
				break
		assert_true(picked)
		if runner.is_running():
			runner.stop()
		assert_eq(log_node.outcome_of(quest_id), str(row[3]), "%s: the choice was not recorded" % quest_id)
		var moved_on: bool = log_node.is_completed(quest_id) or log_node.stage_id_of(quest_id) != str(row[1])
		assert_true(moved_on, "%s: deciding it and saying so moves the quest on from %s" % [quest_id, row[1]])


func test_nobody_else_is_asked_and_the_choice_is_gone_once_made() -> void:
	assert_true(log_node.start(WATER_KEPT))
	log_node.set_stage(WATER_KEPT, "whose_bell")
	assert_empty(log_node.unwritten_choices_for(ALDITH), "the Circle does not get to decide whose the bell is")
	log_node.choose(WATER_KEPT, "keep")
	assert_empty(log_node.unwritten_choices_for("core:npc/tallissa_oul"), "a made decision is not offered again")


func test_a_decision_with_an_authored_button_is_left_to_it() -> void:
	assert_true(log_node.start(WARDENS_Q1))
	log_node.set_stage(WARDENS_Q1, "the_pen")
	assert_empty(log_node.unwritten_choices_for("core:npc/wardens_hesk"))
	assert_empty(log_node.unwritten_choices_for("core:npc/wardens_ryn"))


# --- deliveries nobody wrote a hand-over for ----------------------------------------------------------

func test_the_letter_changes_hands_when_you_speak_to_the_sayer() -> void:
	assert_true(log_node.start(LOUDER_THAN_BOOKS))
	log_node.set_stage(LOUDER_THAN_BOOKS, "the_spire")
	EventBus.dialogue_ended.emit(ALDITH)
	assert_false(log_node.objective_done(LOUDER_THAN_BOOKS, 1), "no letter, no delivery")
	inventory.add(LETTER, 1)
	EventBus.dialogue_ended.emit(ALDITH)
	assert_true(log_node.objective_done(LOUDER_THAN_BOOKS, 1), "carrying it, speaking to her hands it over")
	assert_eq(inventory.count(LETTER), 0, "and it is hers now")


func test_speaking_to_somebody_else_does_not_deliver() -> void:
	assert_true(log_node.start(LOUDER_THAN_BOOKS))
	log_node.set_stage(LOUDER_THAN_BOOKS, "the_spire")
	inventory.add(LETTER, 1)
	EventBus.dialogue_ended.emit("core:npc/bennick_cresswell")
	assert_false(log_node.objective_done(LOUDER_THAN_BOOKS, 1))
	assert_eq(inventory.count(LETTER), 1, "the letter is still yours")


## Nan Greyfold's basket has a scene of its own; the generic hand-over waits for it.
func test_an_authored_hand_over_is_left_to_its_scene() -> void:
	var stage: Dictionary = {}
	for s in ContentDB.get_or_empty(FORTY_ONE).get("stages", []):
		if str((s as Dictionary).get("id", "")) == "the_lane":
			stage = s
	assert_true(QuestRoutes.dialogue_closes(FORTY_ONE, stage, 1), "Nan's own line closes the basket")
	var spire: Dictionary = ContentDB.get_or_empty(LOUDER_THAN_BOOKS).get("stages", [])[1]
	assert_false(QuestRoutes.dialogue_closes(LOUDER_THAN_BOOKS, spire, 1), "nobody wrote the letter's hand-over")
	assert_true(log_node.start(VIGIL))
	log_node.complete(VIGIL)
	Social.factions.set_reputation("core:faction/tolling_order", 30)
	assert_true(log_node.start(FORTY_ONE))
	log_node.set_stage(FORTY_ONE, "the_lane")
	assert_gt(inventory.count("core:item/ash_cake"), 0, "the basket was given at the chapter-house")
	EventBus.dialogue_ended.emit("core:npc/nan_greyfold")
	assert_false(log_node.objective_done(FORTY_ONE, 1), "the basket is handed over in Nan's own words, not by walking past her")


# --- using a tool -----------------------------------------------------------------------------------

func test_a_tool_is_used_and_kept_and_the_quest_hears_it() -> void:
	var bag := Inventory.new()
	bag.is_player = true
	Engine.get_main_loop().root.add_child(bag)
	bag.add("core:item/speaking_stone", 1)
	assert_true(log_node.start(LOUDER))
	log_node.set_stage(LOUDER, "say_something")
	var stack: ItemStack = bag.resolve("core:item/speaking_stone")
	assert_true(stack.is_tool(), "a speaking stone is a tool")
	assert_true(bool(stack.summary().get("tool", false)), "and the bag's screen is told so, so it offers Use")
	assert_true(bag.use("core:item/speaking_stone"), "using it does something")
	assert_eq(bag.count("core:item/speaking_stone"), 1, "and does not use it up")
	assert_true(log_node.objective_done(LOUDER, 1), "the Hound's stage heard the stone used")
	bag.get_parent().remove_child(bag)
	bag.free()
