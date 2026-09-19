extends TestCase
## Inventory: stacking, weight, capacity, queries, sorting, marks, transfer and save round-trip.

const SWORD := "core:item/iron_sword"
const APPLE := "core:item/apple"
const INGOT := "core:item/iron_ingot"
const BREAD := "core:item/bread"

var inv: Inventory


func before_each() -> void:
	inv = Inventory.new()


func after_each() -> void:
	inv.free()


func test_add_merges_into_stacks_up_to_the_stack_size() -> void:
	var max_stack: int = int(ContentDB.get_def(APPLE)["stack"])
	assert_eq(max_stack, 30)
	inv.add(APPLE, 12)
	inv.add(APPLE, 12)
	assert_eq(inv.count(APPLE), 24)
	assert_eq(inv.size(), 1, "both lots should merge into one stack")
	inv.add(APPLE, 12)
	assert_eq(inv.count(APPLE), 36)
	assert_eq(inv.size(), 2, "the overflow should open a second stack")
	assert_eq(inv.stacks()[0].count, 30)
	assert_eq(inv.stacks()[1].count, 6)


func test_unstackable_items_never_merge() -> void:
	inv.add(SWORD, 3)
	assert_eq(inv.count(SWORD), 3)
	assert_eq(inv.size(), 3, "swords do not stack")


func test_stacks_with_different_instance_data_do_not_merge() -> void:
	inv.add(INGOT, 2)
	inv.add(INGOT, 2, {"marked": true})
	assert_eq(inv.count(INGOT), 4)
	assert_eq(inv.size(), 2)
	assert_eq(inv.remove(INGOT, 10, {"marked": true}), 2, "the data filter limits removal")
	assert_eq(inv.count(INGOT), 2)


func test_add_rejects_unknown_items() -> void:
	assert_eq(inv.add("core:item/does_not_exist", 1), null)
	assert_eq(inv.size(), 0)


func test_remove_takes_from_several_stacks_and_reports_the_amount() -> void:
	inv.add(APPLE, 45)
	assert_eq(inv.size(), 2)
	assert_eq(inv.remove(APPLE, 40), 40)
	assert_eq(inv.count(APPLE), 5)
	assert_eq(inv.remove(APPLE, 99), 5, "removing more than is held takes what is there")
	assert_eq(inv.count(APPLE), 0)
	assert_true(inv.is_empty())


func test_has_and_count() -> void:
	inv.add(BREAD, 3)
	assert_true(inv.has(BREAD))
	assert_true(inv.has(BREAD, 3))
	assert_false(inv.has(BREAD, 4))
	assert_eq(inv.count("core:item/mutton"), 0)


func test_weight_is_the_sum_of_stack_weights() -> void:
	inv.add(INGOT, 4)          # 1.0 each
	inv.add(APPLE, 5)          # 0.2 each
	assert_near(inv.weight(), 5.0)
	inv.remove(INGOT, 1)
	assert_near(inv.weight(), 4.0)


func test_capacity_and_overload() -> void:
	inv.capacity_override = 10.0
	assert_near(inv.capacity(), 10.0)
	inv.add(INGOT, 8)
	assert_false(inv.is_overloaded())
	assert_near(inv.load_fraction(), 0.8)
	inv.add(INGOT, 4)
	assert_true(inv.is_overloaded(), "12 kg in a 10 kg bag is overloaded")
	assert_false(inv.can_carry(INGOT, 1))


func test_query_by_category_tag_and_name() -> void:
	inv.add(SWORD, 1)
	inv.add(APPLE, 2)
	inv.add(INGOT, 3)
	assert_eq(inv.query({"category": "weapon"}).size(), 1)
	assert_eq(inv.query({"category": ["ingredient", "material"]}).size(), 2)
	assert_eq(inv.by_tag("smithing").size(), 1)
	assert_eq(inv.query({"equippable": true}).size(), 1)
	assert_eq(inv.query({"name_contains": "iron"}).size(), 2)
	assert_eq(inv.query({"weapon_class": "sword"}).size(), 1)


func test_sort_by_category_and_value() -> void:
	inv.add(APPLE, 1)
	inv.add(SWORD, 1)
	inv.add(INGOT, 1)
	inv.sort("category")
	assert_eq(inv.stacks()[0].id, SWORD, "weapons come first")
	inv.sort("value")
	assert_eq(inv.stacks()[0].id, SWORD, "the sword is the most valuable")
	assert_eq(inv.stacks()[2].id, APPLE)


func test_marks_emit_and_clamp() -> void:
	var seen: Array = []
	inv.marks_changed.connect(func(total: int, delta: int) -> void: seen.append([total, delta]))
	inv.add_marks(50)
	assert_eq(inv.marks, 50)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0], [50, 50])
	assert_eq(inv.remove_marks(20), 20)
	assert_eq(inv.marks, 30)
	assert_eq(inv.remove_marks(100), 30, "removing more marks than held takes what is there")
	assert_eq(inv.marks, 0)
	assert_false(inv.can_afford(1))


func test_take_all_marks_for_the_echo() -> void:
	inv.add_marks(120)
	assert_eq(inv.take_all_marks(), 120)
	assert_eq(inv.marks, 0)


func test_transfer_between_bags_keeps_instance_data() -> void:
	var other := Inventory.new()
	inv.add(SWORD, 1, {"temper": 3})
	inv.add_marks(40)
	assert_eq(inv.transfer_to(other, SWORD, 1), 1)
	assert_eq(other.count(SWORD), 1)
	assert_eq(other.find_first(SWORD).temper_tier(), 3)
	inv.add(APPLE, 4)
	assert_eq(inv.transfer_all_to(other), 4)
	assert_eq(other.marks, 40)
	assert_eq(inv.marks, 0)
	assert_true(inv.is_empty())
	other.free()


func test_use_consumes_food_and_reports_effects() -> void:
	inv.add(BREAD, 2)
	var used: Array = []
	inv.item_used.connect(func(item_id: String, effects: Array) -> void: used.append([item_id, effects]))
	assert_true(inv.use(BREAD))
	assert_eq(inv.count(BREAD), 1)
	assert_eq(used.size(), 1)
	assert_eq(used[0][0], BREAD)
	assert_eq(used[0][1][0]["effect"], "core:effect/restore_health")
	assert_false(inv.use(INGOT), "materials cannot be used")


func test_use_of_a_raw_ingredient_yields_its_first_effect_at_half_strength() -> void:
	inv.add("core:item/hawthorn_berry", 1)
	var effects := Inventory.use_effects(inv.find_first("core:item/hawthorn_berry"))
	assert_eq(effects.size(), 1)
	assert_eq(effects[0]["effect"], "core:effect/regen_health")
	assert_true(bool(effects[0]["raw"]))


func test_changed_fires_on_add_and_remove() -> void:
	var fired: Array[int] = []
	inv.changed.connect(func() -> void: fired.append(1))
	inv.add(APPLE, 1)
	inv.remove(APPLE, 1)
	assert_eq(fired.size(), 2)


func test_save_round_trip_keeps_stacks_uids_and_marks() -> void:
	inv.add(SWORD, 1, {"temper": 2})
	inv.add(APPLE, 7)
	inv.add_marks(88)
	var uid := inv.find_first(SWORD).uid
	var text := JSON.stringify(inv.to_save())
	var other := Inventory.new()
	other.from_save(JSON.parse_string(text))
	assert_eq(other.marks, 88)
	assert_eq(other.count(APPLE), 7)
	assert_eq(other.count(SWORD), 1)
	assert_eq(other.find_first(SWORD).uid, uid, "uids survive so equipment slots still resolve")
	assert_eq(other.find_first(SWORD).temper_tier(), 2)
	other.add(SWORD, 1)
	assert_ne(other.stacks()[2].uid, uid, "new stacks get fresh uids")
	other.free()


func test_save_drops_items_that_no_longer_exist() -> void:
	var other := Inventory.new()
	other.from_save({"marks": 5, "stacks": [{"uid": 1, "id": "core:item/ghost_blade", "count": 1, "data": {}}, {"uid": 2, "id": APPLE, "count": 2, "data": {}}]})
	assert_eq(other.size(), 1)
	assert_eq(other.count(APPLE), 2)
	other.free()
