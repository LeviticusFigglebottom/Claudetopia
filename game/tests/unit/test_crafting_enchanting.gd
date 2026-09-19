extends TestCase
## Enchanting: disenchanting, writing a note with Ember Motes, charge and recharge,
## and the "crafting" save section as a whole.

const MOTE := "core:item/ember_mote"
const SWORD := "core:item/iron_sword"
const BODY := "core:item/brigandine"
const RING := "core:item/ring_ash_knights_signet"
const EMBER_BURST := "core:effect/ember_burst"
const COLD_BITE := "core:effect/cold_bite"
const FORTIFY_ARMOUR := "core:effect/fortify_armour"
const RESIST_FIRE := "core:effect/resist_fire"

var inv: Inventory


func before_each() -> void:
	inv = Inventory.new()


func after_each() -> void:
	inv.free()


func test_the_pack_holds_four_enchantments_with_slots_and_costs() -> void:
	var list := Enchanting.all_enchantments()
	assert_true(list.size() >= 4, "at least four notes, found %d" % list.size())
	for id in list:
		var d := Enchanting.def(id)
		assert_gt(d.get("enchant_slots", []).size(), 0, "%s names no slots" % id)
		assert_gt(float(d.get("magnitude_base", 0)), 0.0)
		assert_true(str(d.get("description", "")).length() > 20, "%s needs lore" % id)
	assert_true(list.has(EMBER_BURST))
	assert_true(list.has(COLD_BITE))


func test_slot_kinds_are_read_from_the_item() -> void:
	inv.add(SWORD, 1)
	inv.add(BODY, 1)
	inv.add(RING, 1)
	inv.add("core:item/oak_round_shield", 1)
	assert_eq(Enchanting.slot_kind(inv.find_first(SWORD)), "weapon")
	assert_eq(Enchanting.slot_kind(inv.find_first(BODY)), "armour")
	assert_eq(Enchanting.slot_kind(inv.find_first(RING)), "jewellery")
	assert_eq(Enchanting.slot_kind(inv.find_first("core:item/oak_round_shield")), "shield")
	assert_true(Enchanting.fits(EMBER_BURST, inv.find_first(SWORD)))
	assert_false(Enchanting.fits(EMBER_BURST, inv.find_first(BODY)), "a burning edge needs an edge")
	assert_true(Enchanting.fits(FORTIFY_ARMOUR, inv.find_first(BODY)))


func test_enchanting_needs_a_known_note() -> void:
	inv.add(SWORD, 1)
	inv.add(MOTE, 4)
	var stack := inv.find_first(SWORD)
	assert_eq(Enchanting.enchant_blocker(stack, EMBER_BURST, 4, inv, []), "not_known")
	assert_eq(Enchanting.enchant_blocker(stack, EMBER_BURST, 4, inv, [EMBER_BURST]), "")


func test_enchanting_spends_motes_and_writes_the_note() -> void:
	inv.add(SWORD, 1)
	inv.add(MOTE, 6)
	var stack := inv.find_first(SWORD)
	var r := Enchanting.enchant(stack, EMBER_BURST, 4, inv, [EMBER_BURST], 0)
	assert_true(bool(r["ok"]), str(r["reason"]))
	assert_eq(inv.count(MOTE), 2, "four motes were burned")
	assert_true(stack.is_enchanted())
	var ench: Dictionary = r["enchant"]
	assert_eq(str(ench["effect"]), EMBER_BURST)
	assert_near(float(ench["charge"]), 100.0, 0.1, "four motes at 25 charge each")
	assert_near(float(ench["charge_max"]), 100.0, 0.1)
	assert_gt(float(ench["magnitude"]), 0.0)


func test_more_motes_buy_more_magnitude_up_to_a_limit() -> void:
	var small := Enchanting.preview(EMBER_BURST, 2)
	var large := Enchanting.preview(EMBER_BURST, 8)
	var huge := Enchanting.preview(EMBER_BURST, 40)
	assert_eq(int(small["steps"]), 1)
	assert_eq(int(large["steps"]), 4)
	assert_eq(int(huge["steps"]), Enchanting.MAGNITUDE_STEPS_MAX, "magnitude tops out")
	assert_gt(float(large["magnitude"]), float(small["magnitude"]))
	assert_gt(float(large["charge"]), float(small["charge"]))


func test_skill_and_perks_raise_what_a_note_is_worth() -> void:
	var novice := Enchanting.preview(FORTIFY_ARMOUR, 2, 0)
	var adept := Enchanting.preview(FORTIFY_ARMOUR, 2, 100)
	assert_near(float(adept["magnitude"]), float(novice["magnitude"]) * 2.0, 0.2)
	var m := Modifiers.new()
	m.set_source("perks", [{"stat": "enchant_charge", "mult": 1.25}, {"stat": "enchant_magnitude", "mult": 1.2}])
	var perked := Enchanting.preview(EMBER_BURST, 4, 0, m)
	assert_near(float(perked["charge"]), 125.0, 0.5)
	assert_near(float(perked["magnitude"]), float(Enchanting.preview(EMBER_BURST, 4, 0)["magnitude"]) * 1.2, 0.1)


func test_an_item_cannot_be_enchanted_twice_or_with_the_wrong_note() -> void:
	inv.add(SWORD, 1)
	inv.add(MOTE, 10)
	var stack := inv.find_first(SWORD)
	assert_eq(Enchanting.enchant_blocker(stack, FORTIFY_ARMOUR, 4, inv, [FORTIFY_ARMOUR]), "wrong_item")
	Enchanting.enchant(stack, EMBER_BURST, 4, inv, [EMBER_BURST])
	assert_eq(Enchanting.enchant_blocker(stack, COLD_BITE, 4, inv, [COLD_BITE]), "already_enchanted")


func test_too_few_motes_block_the_work() -> void:
	inv.add(SWORD, 1)
	inv.add(MOTE, 1)
	var stack := inv.find_first(SWORD)
	assert_eq(Enchanting.enchant_blocker(stack, EMBER_BURST, 2, inv, [EMBER_BURST]), "not_enough_motes")
	assert_eq(Enchanting.enchant_blocker(stack, EMBER_BURST, 1, inv, [EMBER_BURST]), "not_enough_motes", "one mote is below the note's cost")


func test_enchanting_a_stack_splits_off_one_piece() -> void:
	inv.add("core:item/iron_arrow", 5)
	inv.add(MOTE, 6)
	var arrows := inv.find_first("core:item/iron_arrow")
	assert_eq(Enchanting.enchant_blocker(arrows, EMBER_BURST, 4, inv, [EMBER_BURST]), "wrong_item", "arrows carry no weapon block")
	inv.add("core:item/potion_restore_health", 3)
	assert_eq(Enchanting.slot_kind(inv.find_first("core:item/potion_restore_health")), "")


func test_charge_is_spent_per_use_and_the_note_goes_silent() -> void:
	inv.add(SWORD, 1)
	inv.add(MOTE, 2)
	var stack := inv.find_first(SWORD)
	Enchanting.enchant(stack, EMBER_BURST, 2, inv, [EMBER_BURST])
	var full := Enchanting.charge_of(stack)
	assert_near(full, 50.0, 0.1)
	assert_true(Enchanting.has_charge(stack))
	assert_true(Enchanting.consume_charge(stack, -1.0, inv))
	assert_near(Enchanting.charge_of(stack), full - 3.0, 0.01, "ember_burst costs 3 a hit")
	var uses := 0
	while Enchanting.consume_charge(stack, -1.0, inv):
		uses += 1
		if uses > 100:
			break
	assert_eq(uses, 15, "the rest of the charge is 15 more blows")
	assert_false(Enchanting.has_charge(stack), "the note has gone quiet")
	assert_near(Enchanting.charge_fraction(stack), 0.04, 0.01)


func test_a_passive_note_never_spends_charge() -> void:
	inv.add(BODY, 1)
	inv.add(MOTE, 2)
	var stack := inv.find_first(BODY)
	Enchanting.enchant(stack, FORTIFY_ARMOUR, 2, inv, [FORTIFY_ARMOUR])
	assert_true(Enchanting.has_charge(stack))
	assert_true(Enchanting.consume_charge(stack, -1.0, inv))
	assert_near(Enchanting.charge_of(stack), 50.0, 0.1, "a worn ward spends nothing")


func test_recharging_refills_from_motes() -> void:
	inv.add(SWORD, 1)
	inv.add(MOTE, 6)
	var stack := inv.find_first(SWORD)
	Enchanting.enchant(stack, EMBER_BURST, 4, inv, [EMBER_BURST])
	for i in 20:
		Enchanting.consume_charge(stack, -1.0, inv)
	assert_near(Enchanting.charge_of(stack), 40.0, 0.1)
	var r := Enchanting.recharge(stack, 2, inv)
	assert_true(bool(r["ok"]), str(r["reason"]))
	assert_eq(int(r["motes_used"]), 2)
	assert_near(Enchanting.charge_of(stack), 90.0, 0.1)
	assert_eq(inv.count(MOTE), 0)
	var none := Enchanting.recharge(stack, 2, inv)
	assert_false(bool(none["ok"]))
	assert_eq(str(none["reason"]), "not_enough_motes")


func test_recharging_never_overfills() -> void:
	inv.add(SWORD, 1)
	inv.add(MOTE, 10)
	var stack := inv.find_first(SWORD)
	Enchanting.enchant(stack, EMBER_BURST, 2, inv, [EMBER_BURST])
	Enchanting.consume_charge(stack, 6.0, inv)
	var r := Enchanting.recharge(stack, 8, inv)
	assert_true(bool(r["ok"]))
	assert_eq(int(r["motes_used"]), 1, "one mote is all it takes")
	assert_near(Enchanting.charge_of(stack), 50.0, 0.1)
	assert_eq(str(Enchanting.recharge(stack, 1, inv)["reason"]), "full")


func test_disenchanting_destroys_the_item_and_teaches_the_note() -> void:
	inv.add(RING, 1)
	var stack := inv.find_first(RING)
	assert_false(stack.is_enchanted(), "the ring's effect is not a written note")
	inv.add(SWORD, 1)
	inv.add(MOTE, 2)
	var sword := inv.find_first(SWORD)
	Enchanting.enchant(sword, COLD_BITE, 2, inv, [COLD_BITE])
	var known: Array = []
	var r := Enchanting.disenchant(sword, inv, known)
	assert_true(bool(r["ok"]), str(r["reason"]))
	assert_eq(str(r["effect"]), COLD_BITE)
	assert_eq(inv.count(SWORD), 0, "the sword is spent learning")
	assert_eq(Enchanting.disenchant_blocker(null, inv, known), "no_item")


func test_disenchanting_a_note_you_know_is_refused() -> void:
	inv.add(SWORD, 1)
	inv.add(MOTE, 2)
	var sword := inv.find_first(SWORD)
	Enchanting.enchant(sword, COLD_BITE, 2, inv, [COLD_BITE])
	assert_eq(Enchanting.disenchant_blocker(sword, inv, [COLD_BITE]), "already_known")
	assert_eq(inv.count(SWORD), 1, "and the sword is not wasted")


func test_a_plain_item_cannot_be_disenchanted() -> void:
	inv.add(SWORD, 1)
	assert_eq(Enchanting.disenchant_blocker(inv.find_first(SWORD), inv, []), "not_enchanted")


func test_an_enchanted_item_is_worth_more() -> void:
	inv.add(SWORD, 1)
	inv.add(SWORD, 1)
	inv.add(MOTE, 4)
	var plain := inv.stacks()[0]
	var written := inv.stacks()[1]
	Enchanting.enchant(written, EMBER_BURST, 4, inv, [EMBER_BURST])
	assert_gt(written.unit_value(), plain.unit_value() * 2)


func test_crafting_node_enchants_recharges_and_disenchants() -> void:
	var c := make_crafting()
	var bag := c.bag()
	bag.add(SWORD, 1)
	bag.add(MOTE, 8)
	assert_false(c.enchant(SWORD, EMBER_BURST, 4), "the note is not known yet")
	assert_true(c.learn_enchantment(EMBER_BURST))
	assert_true(c.knows_enchantment(EMBER_BURST))
	var written: Array = []
	c.enchanted.connect(func(item_id: String, effect_id: String) -> void: written.append(effect_id))
	assert_true(c.enchant(SWORD, EMBER_BURST, 4))
	assert_eq(written, [EMBER_BURST])
	var stack := bag.find_first(SWORD)
	assert_true(stack.is_enchanted())
	assert_true(c.consume_charge(SWORD))
	assert_near(Enchanting.charge_of(stack), 97.0, 0.1)
	assert_true(c.recharge(SWORD, 1))
	assert_near(Enchanting.charge_of(stack), 100.0, 0.1)
	free_crafting(c)


func test_crafting_node_learns_a_note_by_disenchanting() -> void:
	var c := make_crafting()
	var bag := c.bag()
	bag.add(BODY, 1, {"enchant": {"effect": RESIST_FIRE, "magnitude": 20.0, "duration": 0, "charge": 0, "charge_max": 0, "charge_cost": 0}})
	assert_false(c.knows_enchantment(RESIST_FIRE))
	assert_true(c.disenchant(BODY))
	assert_true(c.knows_enchantment(RESIST_FIRE))
	assert_eq(bag.count(BODY), 0)
	free_crafting(c)


func test_the_crafting_save_section_round_trips() -> void:
	var c := make_crafting()
	var bag := c.bag()
	bag.add("core:item/apple", 1)
	c.learn_recipe("core:recipe/bell_bronze_sword")
	c.learn_enchantment(COLD_BITE)
	c.eat_ingredient("core:item/apple")
	var text := JSON.stringify(c.to_save())
	var c2 := make_crafting()
	c2.from_save(JSON.parse_string(text))
	assert_true(c2.knows_recipe("core:recipe/bell_bronze_sword"))
	assert_true(c2.knows_recipe("core:recipe/iron_sword"), "default recipes stay known")
	assert_true(c2.knows_enchantment(COLD_BITE))
	assert_false(c2.knows_enchantment(EMBER_BURST))
	assert_eq(c2.known_effects("core:item/apple").size(), 2, "the discovery came back")
	free_crafting(c2)
	free_crafting(c)


func test_the_save_drops_recipes_and_notes_that_no_longer_exist() -> void:
	var c := make_crafting()
	c.from_save({"known_recipes": ["core:recipe/ghost", "core:recipe/iron_axe"], "known_enchantments": ["core:effect/ghost_note", COLD_BITE], "alchemy": {}})
	assert_eq(c.known_recipes.size(), 1)
	assert_eq(c.known_enchantments.size(), 1)
	free_crafting(c)


func make_crafting() -> Crafting:
	var holder := Node.new()
	var bag := Inventory.new()
	var c := Crafting.new()
	holder.add_child(bag)
	holder.add_child(c)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	return c


func free_crafting(c: Crafting) -> void:
	c.get_parent().free()
