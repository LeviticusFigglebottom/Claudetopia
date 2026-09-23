extends TestCase
## A quest's giver starts it, by being talked to.
##
## A quest names its `giver`, and nothing read the name: `QuestConditions.offers_of` was only ever
## called by its tests. Every quest in the pack happens to have a line or an effect that starts it,
## so none was stuck, and the first quest written with a giver and nothing else would have been.
## Now the giver offers it at their hub, where nothing else in the pack starts it (so the Toll Hums
## still begins when the Naming ends, and Wren does not offer it early), once its `requires` hold.

const PATCH := preload("res://tests/fixtures/content_patch.gd")
const OFFERED := "core:quest/_test_asked_for"
const GATED := "core:quest/_test_asked_for_later"
const QUIET := "core:quest/_test_asked_of_the_quiet"
const GIVER := "core:npc/sorrel_rooke"
const QUIET_GIVER := "core:npc/_test_quiet_giver"

var log_node: Node


func _quest(id: String, giver: String, name: String, requires: Array = []) -> Dictionary:
	# the work is somebody else's to finish, so taking it does not also close it
	return {"id": id, "name": name, "layer": "side", "giver": giver, "requires": requires,
			"stages": [{"id": "only", "journal": "Asked, and taken on.",
					"objectives": [{"type": "talk", "target": "core:npc/wren_tallow"}]}]}


func before_each() -> void:
	log_node = Social.quests
	GameState.reset_for_new_game(1)
	log_node.reset_for_new_game()
	PATCH.add(_quest(OFFERED, GIVER, "A Thing Asked For"))
	PATCH.add(_quest(GATED, GIVER, "A Thing Asked For Later", [{"flag": "_test_gate_open"}]))
	PATCH.add({"id": QUIET_GIVER, "name": "Quiet Giver", "home_place": "core:place/merrowby"})
	PATCH.add(_quest(QUIET, QUIET_GIVER, "A Thing Asked Of The Quiet"))
	QuestRoutes.reset()


func after_each() -> void:
	if Social.dialogue.is_running():
		Social.dialogue.stop()
	for id in [OFFERED, GATED, QUIET, QUIET_GIVER]:
		PATCH.remove(id)
	QuestRoutes.reset()
	log_node.reset_for_new_game()
	GameState.clear_flag("_test_gate_open")


func _talk(npc_id: String) -> Node:
	var runner := Social.talk(npc_id)
	for i in 8:
		if not runner.is_running() or not runner.current_choices.is_empty():
			break
		runner.advance()
	return runner


func _offer_index(runner: Node, name: String) -> int:
	for i in (runner.current_choices as Array).size():
		if str((runner.current_choices[i] as Dictionary).get("text", "")).contains(name):
			return i
	return -1


func test_the_giver_offers_it_and_taking_it_starts_it() -> void:
	var runner := _talk(GIVER)
	var at := _offer_index(runner, "A Thing Asked For)")
	assert_true(at >= 0, "Sorrel does not offer the work she is the giver of")
	if at < 0:
		return
	runner.choose(at)
	assert_true(log_node.is_active(OFFERED), "taking it did not start it")
	assert_true(runner.is_running(), "and the conversation carries on")
	runner.stop()
	runner = _talk(GIVER)
	assert_eq(_offer_index(runner, "A Thing Asked For)"), -1, "offered again once taken")


func test_a_quest_waits_for_its_requirements() -> void:
	var runner := _talk(GIVER)
	assert_eq(_offer_index(runner, "Asked For Later"), -1, "offered before its requirements hold")
	runner.stop()
	GameState.set_flag("_test_gate_open")
	runner = _talk(GIVER)
	assert_true(_offer_index(runner, "Asked For Later") >= 0, "and not once they do")


func test_somebody_with_nothing_to_say_still_offers_their_work() -> void:
	var runner := _talk(QUIET_GIVER)
	var at := _offer_index(runner, "Asked Of The Quiet")
	assert_true(at >= 0, "a bare greeting had no room for the work")
	if at < 0:
		return
	runner.choose(at)
	assert_true(log_node.is_active(QUIET))
	assert_false(runner.is_running(), "taking it ends a conversation that had nothing else in it")


## What the pack already starts some other way is not offered again: the Toll Hums begins when the
## Naming ends, and its giver does not hand it over first.
func test_what_the_pack_starts_elsewhere_is_not_offered_by_its_giver() -> void:
	var elsewhere := 0
	for def in ContentDB.all("quest"):
		var giver := str(def.get("giver", ""))
		if giver == "" or str(def["id"]).begins_with("core:quest/_test") or not QuestRoutes.started_elsewhere(str(def["id"])):
			continue
		elsewhere += 1
		for offer in log_node.giver_offers(giver):
			assert_ne(str(offer["quest_id"]), str(def["id"]), "%s offers %s, which the pack starts elsewhere" % [giver, def["id"]])
	assert_gt(elsewhere, 20, "the pack's quests were asked about")
