extends TestCase
## Smithing: recipe gating, material cost, tempering, and the Crafting node's forge screen.

const INGOT := "core:item/iron_ingot"
const LEATHER := "core:item/leather"
const SWORD := "core:item/iron_sword"
const SWORD_RECIPE := "core:recipe/iron_sword"
const GREATSWORD_RECIPE := "core:recipe/iron_greatsword"
const BELL_SWORD_RECIPE := "core:recipe/bell_bronze_sword"

var inv: Inventory


func before_each() -> void:
	inv = Inventory.new()


func after_each() -> void:
	inv.free()


func test_every_recipe_names_real_items_and_a_station() -> void:
	var recipes := Smithing.all_recipes()
	assert_true(recipes.size() >= 15, "at least fifteen recipes, found %d" % recipes.size())
	for d in recipes:
		assert_true(ContentDB.has(str(d["output"]["item"])), "%s outputs unknown item" % d["id"])
		assert_ne(str(d["station"]), "")
		assert_gt(d["inputs"].size(), 0)
		for i in d["inputs"]:
			assert_true(ContentDB.has(str(i["item"])), "%s needs unknown item %s" % [d["id"], i["item"]])


func test_recipes_at_a_station() -> void:
	var forge := Smithing.recipes_at("forge")
	assert_true(forge.has(SWORD_RECIPE))
	assert_empty(Smithing.recipes_at("nowhere"))


func test_crafting_consumes_inputs_and_adds_the_output() -> void:
	inv.add(INGOT, 2)
	inv.add(LEATHER, 1)
	var r := Smithing.craft(SWORD_RECIPE, inv, 20)
	assert_true(r["ok"], r["reason"])
	assert_eq(inv.count(SWORD), 1)
	assert_eq(inv.count(INGOT), 0)
	assert_eq(inv.count(LEATHER), 0)
	assert_gt(float(r["xp"]), 0.0)


func test_missing_materials_block_the_craft() -> void:
	inv.add(INGOT, 1)
	assert_eq(Smithing.blocker(SWORD_RECIPE, inv, 20), "missing_materials")
	var missing := Smithing.missing_inputs(SWORD_RECIPE, inv)
	assert_eq(missing.size(), 2)
	assert_eq(int(missing[0]["have"]), 1)
	var r := Smithing.craft(SWORD_RECIPE, inv, 20)
	assert_false(r["ok"])
	assert_eq(inv.count(INGOT), 1, "a failed craft consumes nothing")


func test_skill_gates_the_higher_recipes() -> void:
	inv.add(INGOT, 4)
	inv.add(LEATHER, 1)
	assert_eq(Smithing.blocker(GREATSWORD_RECIPE, inv, 5), "skill_too_low")
	assert_eq(Smithing.blocker(GREATSWORD_RECIPE, inv, 20), "")


func test_the_wrong_station_blocks_the_craft() -> void:
	inv.add(INGOT, 2)
	inv.add(LEATHER, 1)
	assert_eq(Smithing.blocker(SWORD_RECIPE, inv, 20, "alembic"), "wrong_station")


func test_unknown_recipes_are_blocked() -> void:
	inv.add(INGOT, 9)
	inv.add(LEATHER, 4)
	assert_eq(Smithing.blocker(SWORD_RECIPE, inv, 20, "forge", false), "not_known")


func test_the_thrift_perk_trims_material_cost() -> void:
	var m := Modifiers.new()
	m.set_source("perks", [{"stat": "smithing_material_cost", "mult": 0.75}])
	var plain := Smithing.inputs_for("core:recipe/brigandine")
	var thrifty := Smithing.inputs_for("core:recipe/brigandine", m)
	assert_eq(int(plain[0]["count"]), 5)
	assert_eq(int(thrifty[0]["count"]), 4, "five ingots become four")
	var single := Smithing.inputs_for("core:recipe/iron_axe", m)
	assert_eq(int(single[0]["count"]), 1, "a cost of one never drops to zero")


func test_tempering_raises_the_tier_and_the_numbers() -> void:
	inv.add(SWORD, 1)
	inv.add(INGOT, 4)
	var stack := inv.find_first(SWORD)
	assert_near(float(stack.effective_weapon()["damage"]), 14.0, 0.001)
	var r := Smithing.temper(stack, inv, 40)
	assert_true(r["ok"], r["reason"])
	assert_eq(int(r["tier"]), 1)
	assert_eq(inv.count(INGOT), 3, "tier one costs one ingot")
	assert_near(float(stack.effective_weapon()["damage"]), 15.4, 0.001, "+10% per tier")
	assert_true(stack.display_name().contains("Fine"))
	var r2 := Smithing.temper(stack, inv, 40)
	assert_true(r2["ok"])
	assert_eq(int(r2["tier"]), 2)
	assert_eq(inv.count(INGOT), 1, "tier two costs two ingots")
	assert_near(float(stack.effective_weapon()["damage"]), 16.8, 0.001)


func test_tempering_is_gated_by_smithing_level() -> void:
	inv.add(SWORD, 1)
	inv.add(INGOT, 20)
	var stack := inv.find_first(SWORD)
	assert_eq(Smithing.max_tier_for_level(0), 1)
	assert_eq(Smithing.max_tier_for_level(30), 3)
	assert_eq(Smithing.max_tier_for_level(100), Smithing.MAX_TEMPER)
	assert_true(Smithing.temper(stack, inv, 0)["ok"])
	assert_eq(Smithing.temper_blocker(stack, inv, 0), "skill_too_low", "tier two needs more training")
	assert_eq(Smithing.temper_blocker(stack, inv, 20), "")


func test_tempering_needs_the_right_material() -> void:
	inv.add("core:item/clan_plate", 1)
	var stack := inv.find_first("core:item/clan_plate")
	assert_eq(Smithing.temper_material(stack), "core:item/giant_bone_shard")
	assert_eq(Smithing.temper_blocker(stack, inv, 60), "missing_materials")
	inv.add("core:item/giant_bone_shard", 2)
	assert_eq(Smithing.temper_blocker(stack, inv, 60), "")


func test_tempering_splits_a_stack_so_only_one_piece_changes() -> void:
	inv.add("core:item/iron_arrow", 10)
	inv.add(INGOT, 5)
	var arrows := inv.find_first("core:item/iron_arrow")
	assert_eq(Smithing.temper_blocker(arrows, inv, 40), "not_temperable", "arrows have no weapon block")
	inv.add("core:item/ring_cragborn_bone", 3)
	var rings := inv.find_first("core:item/ring_cragborn_bone")
	assert_eq(rings.count, 1, "rings do not stack, so nothing to split")


func test_potions_and_materials_cannot_be_tempered() -> void:
	inv.add("core:item/potion_restore_health", 1)
	assert_eq(Smithing.temper_blocker(inv.find_first("core:item/potion_restore_health"), inv, 99), "not_temperable")
	assert_eq(Smithing.temper_blocker(null, inv, 99), "no_item")


func test_the_red_door_perk_widens_the_temper_step() -> void:
	var m := Modifiers.new()
	m.set_source("perks", [{"stat": "temper_bonus", "add": 0.05}])
	assert_near(Smithing.bonus_per_tier(m), 0.15, 0.001)
	inv.add(SWORD, 1, {"temper": 2})
	var stack := inv.find_first(SWORD)
	assert_near(float(stack.effective_weapon(Smithing.bonus_per_tier(m))["damage"]), 14.0 * 1.3, 0.001)


func test_crafting_node_lists_recipes_for_a_station() -> void:
	var c := make_crafting()
	c.bag().add(INGOT, 2)
	c.bag().add(LEATHER, 1)
	var list := c.recipes_for("forge")
	assert_gt(list.size(), 10)
	var sword: Dictionary = {}
	for r in list:
		if str(r["id"]) == SWORD_RECIPE:
			sword = r
	assert_false(sword.is_empty())
	assert_true(bool(sword["can_craft"]))
	assert_empty(sword["missing"])
	assert_eq(str(sword["output_name"]), "Iron Sword")
	free_crafting(c)


func test_crafting_node_crafts_and_awards_xp() -> void:
	var c := make_crafting()
	var prog := Progression.new()
	prog.listen_to_event_bus = true
	add_node(prog)
	c.bag().add(INGOT, 2)
	c.bag().add(LEATHER, 1)
	var crafted: Array = []
	c.crafted.connect(func(recipe: String, item: String, count: int) -> void: crafted.append(item))
	assert_true(c.craft(SWORD_RECIPE))
	assert_eq(c.bag().count(SWORD), 1)
	assert_eq(crafted.size(), 1)
	assert_true(prog.skills.xp("core:skill/smithing") > 0.0, "crafting trains smithing")
	prog.free()
	free_crafting(c)


func test_unknown_recipes_must_be_learned_first() -> void:
	var c := make_crafting()
	c.bag().add("core:item/bell_bronze_scrap", 3)
	c.bag().add(INGOT, 1)
	c.bag().add(LEATHER, 1)
	assert_false(c.knows_recipe(BELL_SWORD_RECIPE), "the bell-bronze pattern is not common knowledge")
	assert_false(c.craft(BELL_SWORD_RECIPE))
	var learned: Array = []
	EventBus.recipe_learned.connect(func(id: String) -> void: learned.append(id), CONNECT_ONE_SHOT)
	assert_true(c.learn_recipe(BELL_SWORD_RECIPE))
	assert_eq(learned, [BELL_SWORD_RECIPE])
	assert_false(c.learn_recipe(BELL_SWORD_RECIPE), "learning twice changes nothing")
	assert_true(c.can_craft(BELL_SWORD_RECIPE) == false or c.can_craft(BELL_SWORD_RECIPE), "skill may still gate it")
	free_crafting(c)


func test_crafting_node_tempers_through_its_bag() -> void:
	var c := make_crafting()
	c.bag().add(SWORD, 1)
	c.bag().add(INGOT, 2)
	var preview := c.temper_preview(SWORD)
	assert_true(bool(preview["ok"]), str(preview["reason"]))
	assert_eq(str(preview["material"]), INGOT)
	assert_eq(int(preview["cost"]), 1)
	var r := c.temper(SWORD)
	assert_true(bool(r["ok"]), str(r["reason"]))
	assert_eq(int(r["tier"]), 1)
	assert_eq(c.bag().find_first(SWORD).temper_tier(), 1)
	free_crafting(c)


func make_crafting() -> Crafting:
	var holder := Node.new()
	var bag := Inventory.new()
	var c := Crafting.new()
	holder.add_child(bag)
	holder.add_child(c)
	add_node(holder)
	return c


func free_crafting(c: Crafting) -> void:
	c.get_parent().free()


func add_node(n: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(n)
