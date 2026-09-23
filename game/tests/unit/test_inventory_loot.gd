extends TestCase
## LootTable: determinism, weights, ranges, conditions, nesting, guaranteed entries; plus the
## world pickups and containers that consume it.

const APPLE := "core:item/apple"
const INGOT := "core:item/iron_ingot"


func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_the_same_seed_gives_the_same_loot() -> void:
	var a := LootTable.roll("core:loot/bandit_pockets", rng(12345))
	var b := LootTable.roll("core:loot/bandit_pockets", rng(12345))
	assert_eq(JSON.stringify(a), JSON.stringify(b), "same seed, same drops")
	assert_gt(a.size(), 0)


func test_different_seeds_give_different_loot() -> void:
	var same := 0
	for i in 8:
		var a := JSON.stringify(LootTable.roll("core:loot/common_chest", rng(i)))
		var b := JSON.stringify(LootTable.roll("core:loot/common_chest", rng(i + 1000)))
		if a == b:
			same += 1
	assert_true(same < 8, "eight seed pairs should not all agree")


func test_rolls_range_is_respected() -> void:
	var table := {"rolls": [2, 2], "entries": [{"item": APPLE, "weight": 1}]}
	var r := LootTable.roll(table, rng(1))
	assert_eq(r.size(), 2)
	assert_eq(str(r[0]["item"]), APPLE)


func test_weights_decide_the_share() -> void:
	var table := {"rolls": 200, "entries": [{"item": APPLE, "weight": 9}, {"item": INGOT, "weight": 1}]}
	var apples := 0
	for r in LootTable.roll(table, rng(7)):
		if str(r["item"]) == APPLE:
			apples += 1
	assert_gt(apples, 150, "a weight of 9 against 1 should take most of 200 rolls")
	assert_true(apples < 200, "and not all of them")


func test_zero_weight_entries_never_drop() -> void:
	var table := {"rolls": 50, "entries": [{"item": APPLE, "weight": 1}, {"item": INGOT, "weight": 0}]}
	for r in LootTable.roll(table, rng(3)):
		assert_ne(str(r["item"]), INGOT)


func test_count_ranges_stay_inside_their_bounds() -> void:
	var table := {"rolls": 40, "entries": [{"item": APPLE, "count": [2, 5], "weight": 1}]}
	for r in LootTable.roll(table, rng(11)):
		assert_true(int(r["count"]) >= 2 and int(r["count"]) <= 5, "count %d out of range" % int(r["count"]))


func test_nothing_entries_drop_nothing() -> void:
	var table := {"rolls": 20, "entries": [{"nothing": true, "weight": 1}]}
	assert_empty(LootTable.roll(table, rng(2)))


func test_guaranteed_entries_always_drop() -> void:
	var table := {"rolls": 0, "guaranteed": [{"item": INGOT, "count": 2}], "entries": [{"item": APPLE, "weight": 1}]}
	for seed_value in [1, 2, 3, 4]:
		var r := LootTable.roll(table, rng(seed_value))
		assert_eq(r.size(), 1)
		assert_eq(str(r[0]["item"]), INGOT)
		assert_eq(int(r[0]["count"]), 2)


func test_guaranteed_chance_is_applied() -> void:
	var table := {"rolls": 0, "guaranteed": [{"item": INGOT, "chance": 0.5}]}
	var hits := 0
	for seed_value in 60:
		if not LootTable.roll(table, rng(seed_value)).is_empty():
			hits += 1
	assert_gt(hits, 10, "a half chance should hit sometimes")
	assert_true(hits < 50, "and miss sometimes")


func test_conditions_gate_entries() -> void:
	var table := {"rolls": 10, "entries": [{"item": INGOT, "weight": 1, "conditions": [{"min_level": 5}]}, {"item": APPLE, "weight": 1}]}
	for r in LootTable.roll(table, rng(4), {"level": 1}):
		assert_eq(str(r["item"]), APPLE, "the ingot needs level 5")
	var found := false
	for r in LootTable.roll(table, rng(4), {"level": 9}):
		if str(r["item"]) == INGOT:
			found = true
	assert_true(found, "at level 9 the ingot can drop")


func test_region_flag_and_quest_conditions() -> void:
	assert_true(LootTable.condition_passes({"region": "core:region/skerrow"}, {"region": "core:region/skerrow"}))
	assert_false(LootTable.condition_passes({"region": "core:region/skerrow"}, {"region": "core:region/hearthvale"}))
	assert_true(LootTable.condition_passes({"flag": "quiet_hands_member"}, {"flags": {"quiet_hands_member": true}}))
	assert_false(LootTable.condition_passes({"flag": "quiet_hands_member"}, {"flags": {}}))
	assert_true(LootTable.condition_passes({"flag_not": "x"}, {"flags": {}}))
	# a stage is named the pack's way, by id or by number from one; the context holds the index
	var NAMING := "core:quest/the_naming"          # wake, the_choir, ash_wights, hearthstone, the_cart
	assert_true(LootTable.condition_passes({"quest_at": [NAMING, 2]}, {"quests": {NAMING: 1}}), "the second stage is index 1")
	assert_false(LootTable.condition_passes({"quest_at": [NAMING, 2]}, {"quests": {NAMING: 2}}), "and not index 2")
	assert_true(LootTable.condition_passes({"quest_at": [NAMING, "ash_wights"]}, {"quests": {NAMING: 2}}))
	assert_false(LootTable.condition_passes({"quest_at": [NAMING, "ash_wights"]}, {"quests": {}}), "not started")
	assert_true(LootTable.condition_passes({"quest_min": [NAMING, "hearthstone"]}, {"quests": {NAMING: 4}}))
	assert_false(LootTable.condition_passes({"quest_min": [NAMING, "hearthstone"]}, {"quests": {NAMING: 2}}))
	assert_true(LootTable.condition_passes({"quest_min": [NAMING, "hearthstone"]}, {"quests": {}, "quests_done": [NAMING]}),
			"a finished quest is past every stage")
	assert_false(LootTable.condition_passes({"quest_at": ["core:quest/no_such_quest", 1]}, {"quests": {"core:quest/no_such_quest": 0}}),
			"a stage of a quest nobody wrote is no stage")
	assert_true(LootTable.condition_passes({"luck_min": 2.0}, {"luck": 3.0}))
	assert_false(LootTable.condition_passes({"luck_min": 2.0}, {"luck": 1.0}))


## A chest and a kill are rolled in the same world. A chest rolled in the default context, a level-1
## stranger with no quests, so nothing a story gates on could ever come out of one; and the quest
## conditions were read against a context nobody filled.
func test_a_roll_reads_the_quests_as_they_stand() -> void:
	var quests: Node = Social.quests
	quests.reset_for_new_game()
	assert_true(quests.start("core:quest/the_naming"))
	quests.set_stage("core:quest/the_naming", "ash_wights")
	var ctx := LootTable.world_context()
	assert_eq(int((ctx["quests"] as Dictionary).get("core:quest/the_naming", -1)), 2, "the Naming at its third stage")
	var table := {"rolls": 1, "entries": [{"item": INGOT, "weight": 1,
			"conditions": [{"quest_at": ["core:quest/the_naming", "ash_wights"]}]}, {"nothing": true, "weight": 0}]}
	assert_eq(LootTable.roll(table, rng(3), ctx).size(), 1, "an entry gated on the stage the story is at drops")
	quests.set_stage("core:quest/the_naming", "hearthstone")
	assert_empty(LootTable.roll(table, rng(3), LootTable.world_context()), "and not a stage later")
	var scene: PackedScene = load("res://systems/inventory/container.tscn")
	var chest: WorldContainer = scene.instantiate()
	var chest_quests: Dictionary = chest.loot_context().get("quests", {})
	assert_eq(int(chest_quests.get("core:quest/the_naming", -1)), 3, "a chest reads the same quests")
	chest.free()
	quests.reset_for_new_game()


func test_luck_raises_the_weight_of_lucky_entries() -> void:
	var table := {"rolls": 100, "entries": [{"item": INGOT, "weight": 1, "weight_per_luck": 4.0}, {"item": APPLE, "weight": 5}]}
	var unlucky := 0
	var lucky := 0
	for r in LootTable.roll(table, rng(5), {"luck": 0.0}):
		if str(r["item"]) == INGOT:
			unlucky += 1
	for r in LootTable.roll(table, rng(5), {"luck": 5.0}):
		if str(r["item"]) == INGOT:
			lucky += 1
	assert_gt(lucky, unlucky, "luck should pull the lucky entry up")


func test_nested_tables_are_rolled_in_full() -> void:
	var inner := {"rolls": 2, "entries": [{"item": INGOT, "weight": 1}]}
	var outer := {"rolls": 1, "entries": [{"table": inner, "weight": 1}]}
	var r := LootTable.roll(outer, rng(6))
	assert_eq(r.size(), 2, "the nested table's own rolls happen")


func test_nesting_stops_at_the_depth_limit() -> void:
	var table := {"rolls": 1, "entries": [{"item": INGOT, "weight": 1}]}
	table["entries"].append({"table": table, "weight": 5})
	var r := LootTable.roll(table, rng(8))
	assert_true(r.size() <= LootTable.MAX_DEPTH + 2, "a self-referencing table must terminate")


func test_merge_combines_duplicates() -> void:
	var merged := LootTable.merge([{"item": APPLE, "count": 2}, {"marks": 5}, {"item": APPLE, "count": 3}, {"marks": 7}] as Array[Dictionary])
	assert_eq(merged.size(), 2)
	assert_eq(int(merged[0]["count"]), 5)
	assert_eq(int(merged[1]["marks"]), 12)


func test_core_loot_tables_roll_without_dangling_items() -> void:
	for id in ContentDB.ids_of("loot"):
		for seed_value in 5:
			for r in LootTable.roll(id, rng(seed_value), {"level": 10, "luck": 3.0, "region": "core:region/skerrow"}):
				if r.has("item"):
					assert_true(ContentDB.has(str(r["item"])), "%s dropped unknown item %s" % [id, r["item"]])
				else:
					assert_gt(int(r["marks"]), 0)


func test_range_value_handles_ints_and_arrays() -> void:
	var r := rng(1)
	assert_eq(LootTable.range_value(3, r), 3)
	assert_eq(LootTable.range_value([4, 4], r), 4)
	assert_eq(LootTable.range_value([5, 2], r) >= 2, true, "reversed bounds are sorted")


func test_world_item_hands_its_contents_to_an_actor() -> void:
	var scene: PackedScene = load("res://systems/inventory/world_item.tscn")
	var wi: Node = scene.instantiate()
	wi.setup(APPLE, 3, {}, 25)
	var holder := Node3D.new()
	var inv := Inventory.new()
	holder.add_child(inv)
	add_children([holder, wi])
	assert_true(wi.prompt_text().contains("Vale Apple"))
	assert_true(wi.interact(holder))
	assert_eq(inv.count(APPLE), 3)
	assert_eq(inv.marks, 25)
	await wi.tree_exited
	holder.free()


func test_world_item_refuses_an_actor_without_a_bag() -> void:
	var scene: PackedScene = load("res://systems/inventory/world_item.tscn")
	var wi: Node = scene.instantiate()
	wi.setup(APPLE, 1)
	var holder := Node3D.new()
	add_children([holder, wi])
	assert_false(wi.interact(holder))
	assert_true(is_instance_valid(wi), "nothing was taken, so the pickup stays")
	wi.free()
	holder.free()


func test_container_rolls_its_table_once_and_keeps_its_contents() -> void:
	var scene: PackedScene = load("res://systems/inventory/container.tscn")
	var c: WorldContainer = scene.instantiate()
	c.container_id = "_unit_test_chest"
	c.loot_table = "core:loot/common_chest"
	add_children([c])
	c.forget_state()
	var actor := Node3D.new()
	var inv := Inventory.new()
	actor.add_child(inv)
	add_children([actor])
	assert_true(c.interact(actor))
	var first := c.inventory.size() + (1 if c.inventory.marks > 0 else 0)
	assert_gt(first, 0, "a common chest holds something")
	var contents := JSON.stringify(c.inventory.to_save())
	assert_true(c.interact(actor))
	assert_eq(JSON.stringify(c.inventory.to_save()), contents, "opening again must not re-roll")
	c.take_all(actor)
	assert_true(c.inventory.is_empty())
	assert_true(inv.size() > 0 or inv.marks > 0)
	close_screen("container", "an opened chest shows what is in it")
	c.forget_state()
	c.free()
	actor.free()


func test_locked_container_needs_its_key() -> void:
	var scene: PackedScene = load("res://systems/inventory/container.tscn")
	var c: WorldContainer = scene.instantiate()
	c.container_id = "_unit_test_locked"
	c.locked = true
	c.key_item = "core:item/merrowby_house_key"
	add_children([c])
	c.forget_state()
	c.locked = true
	var actor := Node3D.new()
	var inv := Inventory.new()
	actor.add_child(inv)
	add_children([actor])
	assert_false(c.interact(actor), "no key, no chest")
	assert_true(c.prompt_text().contains("Locked"))
	inv.add("core:item/merrowby_house_key", 1)
	assert_true(c.interact(actor))
	assert_false(c.locked, "using the key unlocks it for good")
	close_screen("container", "the unlocked chest opens")
	c.forget_state()
	c.free()
	actor.free()


func test_loot_drops_turn_an_enemy_def_into_pickups() -> void:
	var drops := LootDrops.new()
	drops.rng.seed = 99
	var enemy := {"loot": "core:loot/wolf_carcass", "marks": [3, 6]}
	var results := drops.drops_for(enemy, {"level": 3, "luck": 0.0, "region": "core:region/hearthvale", "flags": {}, "quests": {}})
	assert_gt(results.size(), 0)
	var marks := 0
	for r in results:
		if r.has("marks"):
			marks = int(r["marks"])
	assert_true(marks >= 3 and marks <= 6, "the purse stays inside the def's range")
	var root := Node3D.new()
	add_children([root, drops])
	var nodes := drops.spawn_drops(results, Vector3(1, 0, 2), root)
	assert_eq(nodes.size(), results.size())
	drops.free()
	root.free()


func test_dropping_puts_the_item_back_in_the_world() -> void:
	var carrier := Node3D.new()
	var inv := Inventory.new()
	carrier.add_child(inv)
	add_children([carrier])
	carrier.global_position = Vector3(2, 0, 2)
	inv.add(APPLE, 5)
	var node := inv.drop(APPLE, 2)
	assert_ne(node, null)
	assert_eq(inv.count(APPLE), 3, "only the dropped apples leave the bag")
	await carrier.get_tree().process_frame
	assert_true(node.is_inside_tree(), "the pickup is in the world")
	assert_eq(str(node.get("item_id")), APPLE)
	assert_eq(int(node.get("count")), 2)
	assert_true((node as Node3D).global_position.distance_to(carrier.global_position) < 2.0)
	node.free()
	carrier.free()


func test_a_kill_spawns_its_loot_where_the_victim_fell() -> void:
	var root := Node3D.new()
	var drops := LootDrops.new()
	drops.rng.seed = 4242
	drops.snap_to_ground = false
	add_children([root, drops])
	# the victim names its own loot; there is no enemy def for this id at all
	var victim: Node3D = preload("res://tests/fixtures/loot_victim.gd").new()
	root.add_child(victim)
	victim.global_position = Vector3(5, 0, -3)
	var reported: Array = []
	drops.dropped.connect(func(results: Array, pos: Vector3, enemy_id: String) -> void: reported.append(results))
	EventBus.entity_killed.emit(victim, null, "core:enemy/not_in_the_pack_yet")
	await get_tree_of(drops).process_frame
	await get_tree_of(drops).physics_frame
	await get_tree_of(drops).process_frame
	assert_eq(reported.size(), 1, "the kill was turned into drops")
	var pickups := 0
	for c in root.get_children():
		if c is WorldItem:
			pickups += 1
			assert_true((c as WorldItem).global_position.distance_to(Vector3(5, 0, -3)) < 2.0, "drops land by the body")
	assert_gt(pickups, 0)
	drops.free()
	root.free()


func get_tree_of(n: Node) -> SceneTree:
	return n.get_tree()


## Adds nodes to the scene tree via the test runner's own tree.
func add_children(nodes: Array) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for n in nodes:
		tree.root.add_child(n)
