extends TestCase
## Triage 79: what a player could spoil on the way to finishing a quest, and the guards that stop
## it (tools/quests/softlock_check.py finds the content side): a thing a quest wants is not dropped,
## sold or eaten; a lesson that spends arrows or picks has its teacher hand more; a strongbox picked
## before its lesson counts when the lesson comes.

const LOAF := "core:item/hearth_loaf"
const LOAVES := "test:quest/loaves_for_the_softlock_test"
const RANGER := "core:quest/first_ranger"
const ROGUE := "core:quest/first_rogue"

var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(79)
	Social.quests.call("reset_for_new_game")


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Social.quests.call("reset_for_new_game")
	GameState.reset_for_new_game(79)


class _Spots extends Node:
	var props: Dictionary = {}


func test_a_thing_a_quest_wants_is_kept_not_dropped_sold_or_eaten() -> void:
	var def := {"id": LOAVES, "name": "Three Loaves", "layer": "side", "stages": [
			{"id": "the_loaves", "journal": "x", "objectives": [
				{"type": "deliver", "target": "core:npc/hesta_hollins", "item": LOAF, "count": 3}]}]}
	assert_true(bool(Social.quests.call("register_runtime", def)))
	var bag := Inventory.new()
	bag.is_player = true
	_tree().root.add_child(bag)
	_nodes.append(bag)
	bag.add(LOAF, 3)
	var shop := Merchant.new()
	shop.buys = ["consumable", "food"] as Array[String]
	_nodes.append(shop)
	var sells_before := shop.will_buy(LOAF)
	assert_eq(bag.held_for(LOAF), "", "nothing wants it yet")
	assert_true(bool(Social.quests.call("start", LOAVES)))
	assert_eq(bag.held_for(LOAF), "Three Loaves", "now the quest does")
	assert_false(bag.use(LOAF), "not eaten on the way")
	assert_eq(bag.drop(LOAF), null, "nor let fall (a dropped thing is not saved with the world)")
	assert_eq(bag.count(LOAF), 3, "all three still in the bag")
	assert_false(shop.will_buy(LOAF), "and no shop buys it")
	Social.quests.call("complete", LOAVES)
	assert_eq(bag.held_for(LOAF), "", "the quest done, the bag's own again")
	assert_eq(shop.will_buy(LOAF), sells_before)


func test_out_of_arrows_at_the_butts_the_teacher_hands_more() -> void:
	var bag := SocialFakes.FakeInventory.new()
	Social.bind("inventory", bag)
	Social.quests.call("start", RANGER)
	Social.quests.call("set_stage", RANGER, "the_butts")
	assert_eq(bag.count("core:item/iron_arrow"), 12, "a lesson in shooting begun with no arrows: twelve handed over")
	bag.remove("core:item/iron_arrow", 12)
	assert_eq(bag.count("core:item/iron_arrow"), 12, "and again when the last is loosed")
	bag.remove("core:item/iron_arrow", 5)
	assert_eq(bag.count("core:item/iron_arrow"), 7, "but not while there are any left")
	Social.quests.call("set_stage", RANGER, "the_force")
	bag.remove("core:item/iron_arrow", 7)
	assert_eq(bag.count("core:item/iron_arrow"), 0, "past the lesson, nobody hands arrows out")
	bag.items.clear()


func test_snapped_picks_at_the_strongbox_sauve_hands_more() -> void:
	var bag := SocialFakes.FakeInventory.new()
	Social.bind("inventory", bag)
	bag.add("core:item/lockpick", 1)
	Social.quests.call("start", ROGUE)
	Social.quests.call("set_stage", ROGUE, "the_strongbox")
	bag.remove("core:item/lockpick", 1)
	assert_eq(bag.count("core:item/lockpick"), 3, "the last pick snapped: three of Sauve's")
	bag.items.clear()


func test_a_strongbox_picked_before_its_lesson_counts_when_it_comes() -> void:
	var spots := _Spots.new()
	spots.add_to_group("quest_spots")
	_tree().root.add_child(spots)
	_nodes.append(spots)
	var box := WorldContainer.new()
	box.name = "tithe_strongbox"
	box.locked = true
	spots.add_child(box)
	spots.props["tithe_strongbox"] = box
	var me := Node3D.new()
	me.add_to_group("player")
	_tree().root.add_child(me)
	_nodes.append(me)
	Social.quests.call("start", ROGUE)
	assert_eq(str(Social.quests.call("stage_id_of", ROGUE)), "hear_sauve")
	# picked before Sauve has said why: it does not count now, and it cannot be picked again
	box.locked = false
	EventBus.act_done.emit("pick_lock", me, box, "")
	Social.quests.call("set_stage", ROGUE, "the_strongbox")
	assert_true(bool(Social.quests.call("objective_done", ROGUE, 1)), "the box already open: the lesson is done")
