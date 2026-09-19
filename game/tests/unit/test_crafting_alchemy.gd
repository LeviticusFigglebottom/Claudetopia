extends TestCase
## Alchemy: the ingredient content, effect discovery by eating and combining, and brewing.

const APPLE := "core:item/apple"              # restore_stamina, restore_health, fortify_speech, cure_poison
const WATERCRESS := "core:item/watercress"    # restore_health, cure_poison, fortify_stamina, night_eye
const HAWTHORN := "core:item/hawthorn_berry"  # regen_health, fortify_vigour, resist_frost, restore_stamina
const YEW := "core:item/yew_berry"            # damage_health, slow, silence, invisibility
const LICHEN := "core:item/lichen"            # resist_frost, fortify_armour, cure_poison, silence

var inv: Inventory
var alchemy: Alchemy


func before_each() -> void:
	inv = Inventory.new()
	alchemy = Alchemy.new()


func after_each() -> void:
	inv.free()


func test_the_pack_holds_sixteen_or_more_ingredients_with_four_effects_each() -> void:
	var count := 0
	for d in ContentDB.all("item"):
		if not d.has("alchemy"):
			continue
		count += 1
		var effects: Array = d["alchemy"]["effects"]
		assert_eq(effects.size(), Alchemy.INGREDIENT_EFFECT_COUNT, "%s needs four effects" % d["id"])
		var seen := {}
		for e in effects:
			assert_true(ContentDB.has(str(e)), "%s names unknown effect %s" % [d["id"], e])
			assert_false(seen.has(str(e)), "%s repeats effect %s" % [d["id"], e])
			seen[str(e)] = true
		assert_true(ContentDB.has(str(d.get("origin", ""))), "%s should name its region" % d["id"])
	assert_true(count >= 16, "at least sixteen ingredients, found %d" % count)


func test_every_alchemy_effect_has_a_potion_template() -> void:
	for d in ContentDB.all("effect"):
		if not d.get("tags", []).has("alchemy"):
			continue
		var potion := str(d.get("potion", ""))
		assert_true(ContentDB.has(potion), "%s has no potion template" % d["id"])
		assert_eq(str(ContentDB.get_def(potion)["category"]), "consumable")


func test_only_the_first_effect_is_known_at_the_start() -> void:
	var known := alchemy.known_effects(APPLE)
	assert_eq(known.size(), 1)
	assert_eq(known[0], "core:effect/restore_stamina")
	assert_false(alchemy.is_fully_known(APPLE))
	assert_false(alchemy.knows(APPLE, "core:effect/cure_poison"))


func test_eating_reveals_one_more_effect_each_time() -> void:
	var first := alchemy.eat(APPLE)
	assert_true(bool(first["ok"]))
	assert_eq(int(first["index"]), 1, "the second effect is learned")
	assert_eq(str(first["effect"]), "core:effect/restore_health")
	assert_eq(alchemy.known_effects(APPLE).size(), 2)
	assert_eq(int(alchemy.eat(APPLE)["index"]), 2)
	assert_eq(int(alchemy.eat(APPLE)["index"]), 3)
	assert_true(alchemy.is_fully_known(APPLE))
	var again := alchemy.eat(APPLE)
	assert_eq(int(again["index"]), -1, "there is nothing left to learn")
	assert_true(bool(again["ok"]))


func test_eating_applies_the_first_effect_at_half_strength() -> void:
	var r := alchemy.eat(HAWTHORN)
	var e: Dictionary = r["effects"][0]
	assert_eq(str(e["effect"]), "core:effect/regen_health")
	var base := float(ContentDB.get_def("core:effect/regen_health")["magnitude_base"])
	assert_near(float(e["magnitude"]), base * 0.5, 0.001)


func test_shared_effects_are_found_between_ingredients() -> void:
	var shared := Alchemy.shared_effects([APPLE, WATERCRESS])
	assert_true(shared.has("core:effect/restore_health"))
	assert_true(shared.has("core:effect/cure_poison"))
	assert_eq(shared.size(), 2)
	assert_empty(Alchemy.shared_effects([YEW, HAWTHORN]), "yew and hawthorn have nothing in common")


func test_combining_two_ingredients_brews_a_potion() -> void:
	inv.add(APPLE, 1)
	inv.add(WATERCRESS, 1)
	var r := alchemy.combine([APPLE, WATERCRESS], inv, 0)
	assert_true(bool(r["ok"]), str(r["reason"]))
	assert_eq(str(r["item_id"]), "core:item/potion_restore_health")
	assert_eq(inv.count(APPLE), 0, "the ingredients are used up")
	assert_eq(inv.count(WATERCRESS), 0)
	assert_eq(inv.count("core:item/potion_restore_health"), 1)
	var stack: ItemStack = r["stack"]
	assert_eq(stack.effect_entries().size(), 2, "both shared effects go into the bottle")
	assert_true(stack.display_name().contains("Cure Poison"), stack.display_name())


func test_a_successful_combine_teaches_the_shared_effects() -> void:
	inv.add(APPLE, 1)
	inv.add(WATERCRESS, 1)
	var r := alchemy.combine([APPLE, WATERCRESS], inv, 0)
	assert_gt(r["discovered"].size(), 0)
	assert_true(alchemy.knows(APPLE, "core:effect/restore_health"))
	assert_true(alchemy.knows(WATERCRESS, "core:effect/cure_poison"))
	assert_false(alchemy.knows(APPLE, "core:effect/fortify_speech"), "unrelated effects stay hidden")


func test_a_mixture_with_nothing_in_common_is_wasted() -> void:
	inv.add(YEW, 1)
	inv.add(HAWTHORN, 1)
	var r := alchemy.combine([YEW, HAWTHORN], inv, 0)
	assert_false(bool(r["ok"]))
	assert_eq(str(r["reason"]), "no_shared_effect")
	assert_eq(inv.count(YEW), 0, "the ingredients are spoiled anyway")
	assert_eq(inv.count(HAWTHORN), 0)


func test_three_ingredients_may_be_combined_but_not_four() -> void:
	inv.add(APPLE, 1)
	inv.add(WATERCRESS, 1)
	inv.add(LICHEN, 1)
	assert_eq(alchemy.combine_blocker([APPLE, WATERCRESS, LICHEN], inv), "")
	assert_eq(alchemy.combine_blocker([APPLE, WATERCRESS, LICHEN, YEW], inv), "too_many")
	assert_eq(alchemy.combine_blocker([APPLE], inv), "too_few")
	var r := alchemy.combine([APPLE, WATERCRESS, LICHEN], inv, 0)
	assert_true(bool(r["ok"]))
	assert_eq(str(r["item_id"]), "core:item/potion_restore_health", "the first shared effect names the bottle")


func test_combining_needs_the_ingredients_in_the_bag() -> void:
	inv.add(APPLE, 1)
	assert_eq(alchemy.combine_blocker([APPLE, WATERCRESS], inv), "missing_ingredient")
	assert_eq(alchemy.combine_blocker([APPLE, APPLE], inv), "missing_ingredient", "two apples means two apples")
	inv.add(APPLE, 1)
	assert_eq(alchemy.combine_blocker([APPLE, APPLE], inv), "no_shared_effect", "an ingredient shares nothing with itself")
	inv.add(WATERCRESS, 1)
	assert_eq(alchemy.combine_blocker([APPLE, WATERCRESS], inv), "")
	assert_eq(alchemy.combine_blocker([APPLE, "core:item/iron_ingot"], inv), "not_an_ingredient")


func test_magnitude_scales_with_the_alchemy_skill() -> void:
	var novice := Alchemy.brewed_magnitude("core:effect/restore_health", 0)
	var master := Alchemy.brewed_magnitude("core:effect/restore_health", 100)
	assert_near(float(novice["magnitude"]), 20.0, 0.1)
	assert_near(float(master["magnitude"]), 40.0, 0.1, "a hundred levels doubles it")
	assert_gt(float(master["magnitude"]), float(novice["magnitude"]))


func test_the_potency_perks_scale_potions_and_poisons_apart() -> void:
	var m := Modifiers.new()
	m.set_source("perks", [{"stat": "potion_potency", "mult": 1.2}, {"stat": "poison_potency", "mult": 1.3}])
	assert_near(float(Alchemy.brewed_magnitude("core:effect/restore_health", 0, m)["magnitude"]), 24.0, 0.1)
	assert_near(float(Alchemy.brewed_magnitude("core:effect/damage_health", 0, m)["magnitude"]), 6.5, 0.1)


func test_brewed_potions_carry_their_own_strength_and_do_not_merge() -> void:
	inv.add(APPLE, 2)
	inv.add(WATERCRESS, 2)
	alchemy.combine([APPLE, WATERCRESS], inv, 0)
	alchemy.combine([APPLE, WATERCRESS], inv, 80)
	assert_eq(inv.count("core:item/potion_restore_health"), 2)
	assert_eq(inv.query({"id": "core:item/potion_restore_health"}).size(), 2, "different brews keep separate stacks")
	var strong := inv.stacks()[1]
	var weak := inv.stacks()[0]
	assert_gt(float(strong.effect_entries()[0]["magnitude"]), float(weak.effect_entries()[0]["magnitude"]))
	assert_gt(strong.unit_value(), weak.unit_value(), "a stronger brew is worth more")


func test_the_alchemy_screen_hides_what_is_not_known() -> void:
	inv.add(APPLE, 3)
	var list := alchemy.summaries(inv)
	assert_eq(list.size(), 1)
	var effects: Array = list[0]["effects"]
	assert_eq(effects.size(), 4)
	assert_true(bool(effects[0]["known"]))
	assert_eq(str(effects[1]["name"]), "?")
	alchemy.eat(APPLE)
	list = alchemy.summaries(inv)
	assert_true(bool(list[0]["effects"][1]["known"]))
	assert_eq(str(list[0]["effects"][1]["name"]), "Restore Health")


func test_discovery_survives_a_save_round_trip() -> void:
	alchemy.eat(APPLE)
	alchemy.eat(APPLE)
	var text := JSON.stringify(alchemy.to_save())
	var other := Alchemy.new()
	other.from_save(JSON.parse_string(text))
	assert_eq(other.known_effects(APPLE).size(), 3)
	assert_true(other.knows(APPLE, "core:effect/fortify_speech"))
	assert_false(other.knows(WATERCRESS, "core:effect/cure_poison"))


func test_a_saved_discovery_of_a_vanished_ingredient_is_dropped() -> void:
	var other := Alchemy.new()
	other.from_save({"discovered": {"core:item/ghost_root": [1, 2], APPLE: [1]}})
	assert_eq(other.discovered.size(), 1)
	assert_eq(other.known_effects(APPLE).size(), 2)


func test_crafting_node_eats_combines_and_broadcasts() -> void:
	var holder := Node.new()
	var bag := Inventory.new()
	var c := Crafting.new()
	holder.add_child(bag)
	holder.add_child(c)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	bag.add(APPLE, 2)
	bag.add(WATERCRESS, 1)
	var discoveries: Array = []
	var cb := func(item_id: String, index: int) -> void: discoveries.append([item_id, index])
	EventBus.ingredient_effect_discovered.connect(cb)
	var eaten := c.eat_ingredient(APPLE)
	assert_true(bool(eaten["ok"]))
	assert_eq(bag.count(APPLE), 1, "eating uses one up")
	assert_eq(discoveries.size(), 1)
	var r := c.combine([APPLE, WATERCRESS])
	assert_true(bool(r["ok"]), str(r["reason"]))
	assert_eq(bag.count("core:item/potion_restore_health"), 1)
	assert_gt(discoveries.size(), 1)
	assert_eq(c.known_effects(APPLE).size(), 3, "eating and brewing both taught something")
	EventBus.ingredient_effect_discovered.disconnect(cb)
	holder.free()
