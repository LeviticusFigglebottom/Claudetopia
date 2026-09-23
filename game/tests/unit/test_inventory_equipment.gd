extends TestCase
## Equipment: slot rules, the two-handed rule, aggregation and the save round-trip.

const SWORD := "core:item/iron_sword"
const DAGGER := "core:item/iron_dagger"
const GREATSWORD := "core:item/iron_greatsword"
const BOW := "core:item/hunting_bow"
const SHIELD := "core:item/oak_round_shield"
const LANTERN := "core:item/lantern"
const HELM := "core:item/kettle_helm"
const BODY := "core:item/brigandine"
const PLATE := "core:item/clan_plate"
const TUNIC := "core:item/wool_tunic"
const RING := "core:item/ring_cragborn_bone"
const AMULET := "core:item/amulet_ansels_ember"
const POTION := "core:item/potion_restore_health"

var inv: Inventory
var eq: Equipment


func before_each() -> void:
	inv = Inventory.new()
	eq = Equipment.new()
	eq.inventory = inv


func after_each() -> void:
	eq.free()
	inv.free()


func test_weapons_and_armour_go_to_their_slots() -> void:
	inv.add(SWORD, 1)
	inv.add(HELM, 1)
	inv.add(BODY, 1)
	assert_true(eq.equip(SWORD))
	assert_true(eq.equip(HELM))
	assert_true(eq.equip(BODY))
	assert_eq(eq.item_id("main_hand"), SWORD)
	assert_eq(eq.item_id("head"), HELM)
	assert_eq(eq.item_id("body"), BODY)


func test_equipping_an_item_not_in_the_bag_fails() -> void:
	var loose := ItemStack.new(SWORD, 1)
	assert_false(eq.equip(loose))
	assert_eq(eq.item_id("main_hand"), "")


func test_armour_cannot_go_into_a_weapon_slot() -> void:
	inv.add(HELM, 1)
	assert_false(eq.equip(HELM, "main_hand"))
	assert_eq(eq.can_equip(inv.find_first(HELM), "main_hand")["reason"], "wrong_slot")


func test_materials_are_not_equippable() -> void:
	inv.add("core:item/iron_ingot", 1)
	assert_false(eq.equip("core:item/iron_ingot"))
	assert_eq(eq.can_equip(inv.find_first("core:item/iron_ingot"))["reason"], "not_equippable")


func test_two_handed_weapon_clears_the_off_hand() -> void:
	inv.add(SHIELD, 1)
	inv.add(GREATSWORD, 1)
	assert_true(eq.equip(SHIELD))
	assert_eq(eq.item_id("off_hand"), SHIELD)
	assert_true(eq.equip(GREATSWORD))
	assert_eq(eq.item_id("main_hand"), GREATSWORD)
	assert_eq(eq.item_id("off_hand"), "", "a greatsword takes both hands")


func test_off_hand_clears_a_two_handed_main_weapon() -> void:
	inv.add(BOW, 1)
	inv.add(SHIELD, 1)
	assert_true(eq.equip(BOW))
	assert_true(eq.is_equipped_id(BOW))
	assert_true(eq.equip(SHIELD))
	assert_eq(eq.item_id("off_hand"), SHIELD)
	assert_eq(eq.item_id("main_hand"), "", "a bow cannot be held while a shield is strapped on")


## The round shield is a shield worn as armour (its `armour` block names the off hand), and the
## slot rules knew only shields carried as weapons: it was sold and could never be taken up.
func test_a_shield_worn_as_armour_goes_on_the_off_hand() -> void:
	inv.add(SWORD, 1)
	inv.add("core:item/round_shield", 1)
	assert_true(eq.equip(SWORD))
	assert_true(eq.equip("core:item/round_shield"), "the round shield can be taken up")
	assert_eq(eq.item_id("off_hand"), "core:item/round_shield")
	assert_eq(eq.item_id("main_hand"), SWORD, "beside a one-handed blade")
	assert_near(eq.armour_total(), 1.0, 0.001, "and counts its armour")


func test_daggers_and_lanterns_may_take_the_off_hand() -> void:
	inv.add(SWORD, 1)
	inv.add(DAGGER, 1)
	inv.add(LANTERN, 1)
	eq.equip(SWORD)
	assert_true(eq.equip(DAGGER, "off_hand"))
	assert_eq(eq.item_id("off_hand"), DAGGER)
	assert_true(eq.equip(LANTERN))
	assert_eq(eq.item_id("off_hand"), LANTERN, "the lantern replaces the dagger in the off hand")
	assert_eq(eq.item_id("main_hand"), SWORD, "the sword stays")


func test_rings_fill_both_slots_before_replacing() -> void:
	inv.add(RING, 2)
	assert_eq(inv.size(), 2, "rings do not stack")
	var first := inv.stacks()[0]
	var second := inv.stacks()[1]
	assert_true(eq.equip(first))
	assert_true(eq.equip(second))
	assert_eq(eq.item_id("ring_1"), RING)
	assert_eq(eq.item_id("ring_2"), RING)
	assert_eq(eq.slot_of(first), "ring_1")
	assert_eq(eq.slot_of(second), "ring_2")


func test_equipping_an_already_worn_item_elsewhere_moves_it() -> void:
	inv.add(DAGGER, 1)
	eq.equip(DAGGER, "main_hand")
	assert_true(eq.equip(DAGGER, "off_hand"))
	assert_eq(eq.item_id("main_hand"), "", "one dagger cannot be in both hands")
	assert_eq(eq.item_id("off_hand"), DAGGER)


func test_unequip_leaves_the_item_in_the_bag() -> void:
	inv.add(SWORD, 1)
	eq.equip(SWORD)
	var s := eq.unequip("main_hand")
	assert_ne(s, null)
	assert_eq(eq.item_id("main_hand"), "")
	assert_eq(inv.count(SWORD), 1, "unequipping does not destroy the sword")


func test_dropping_an_equipped_item_clears_its_slot() -> void:
	inv.add(SWORD, 1)
	eq.equip(SWORD)
	inv.remove(SWORD, 1)
	assert_eq(eq.item_id("main_hand"), "", "the slot empties when the item leaves the bag")


func test_armour_total_sums_worn_pieces_with_temper() -> void:
	inv.add(HELM, 1)          # 5
	inv.add(BODY, 1)          # 14
	eq.equip(HELM)
	eq.equip(BODY)
	assert_near(eq.armour_total(), 19.0)
	inv.find_first(BODY).data["temper"] = 2
	assert_near(eq.armour_total(), 5.0 + 14.0 * 1.2, 0.01, "two temper tiers add 20% to the body")


func test_stability_prefers_the_shield_and_adds_armour() -> void:
	inv.add(SWORD, 1)
	eq.equip(SWORD)
	assert_near(eq.stability(), 0.35, 0.001, "the sword's own stability while guarding")
	inv.add(SHIELD, 1)
	eq.equip(SHIELD)
	assert_near(eq.stability(), 0.7, 0.001, "the shield takes over")
	inv.add(BODY, 1)
	eq.equip(BODY)
	assert_near(eq.stability(), 0.8, 0.001, "the brigandine adds 0.1")


func test_weight_class_is_the_weighted_average_of_worn_armour() -> void:
	assert_eq(eq.weight_class(), "light", "unarmoured counts as light")
	inv.add(TUNIC, 1)
	eq.equip(TUNIC)
	assert_eq(eq.weight_class(), "light")
	inv.add(PLATE, 1)
	eq.equip(PLATE)
	assert_eq(eq.weight_class(), "heavy", "clan plate on the body outweighs everything else")
	inv.add("core:item/leather_boots", 1)
	inv.add("core:item/leather_gloves", 1)
	inv.add("core:item/leather_cap", 1)
	eq.equip("core:item/leather_boots")
	eq.equip("core:item/leather_gloves")
	eq.equip("core:item/leather_cap")
	assert_eq(eq.weight_class(), "medium", "light extremities pull heavy plate down to medium")


func test_equipped_weight_counts_each_worn_item_once() -> void:
	inv.add(SWORD, 1)
	inv.add(HELM, 1)
	eq.equip(SWORD)
	eq.equip(HELM)
	assert_near(eq.equipped_weight(), 5.5, 0.001)


func test_main_weapon_block_carries_temper() -> void:
	inv.add(SWORD, 1, {"temper": 3})
	eq.equip(SWORD)
	var w := eq.main_weapon()
	assert_near(float(w["damage"]), 14.0 * 1.3, 0.001)
	assert_eq(int(w["temper"]), 3)
	assert_eq(str(w["class"]), "sword")


func test_modifiers_come_from_worn_items_and_enchantments() -> void:
	inv.add(RING, 1)
	eq.equip(RING)
	var mods := eq.modifiers()
	assert_eq(mods.size(), 1)
	assert_eq(str(mods[0]["stat"]), "resist_frost")
	assert_near(float(mods[0]["add"]), 0.15, 0.001, "15% resist frost scaled to a fraction")
	inv.add(BODY, 1, {"enchant": {"effect": "core:effect/fortify_armour", "magnitude": 20.0, "charge": 0, "charge_max": 0}})
	eq.equip(BODY)
	var m := Modifiers.new()
	m.set_source("equipment", eq.modifiers())
	assert_near(m.get_add("armour"), 20.0, 0.001)
	assert_near(m.get_add("resist_frost"), 0.15, 0.001)


func test_a_spent_weapon_enchantment_contributes_nothing() -> void:
	inv.add(SWORD, 1, {"enchant": {"effect": "core:effect/ember_burst", "magnitude": 10.0, "charge": 0.0, "charge_max": 50.0, "charge_cost": 3.0}})
	eq.equip(SWORD)
	assert_empty(eq.modifiers(), "ember_burst has no passive modifier and no charge")


func test_quick_slots_bind_consumables_only() -> void:
	inv.add(POTION, 3)
	inv.add(SWORD, 1)
	assert_true(eq.bind_quick("quick_1", POTION))
	assert_eq(eq.quick_item("quick_1"), POTION)
	assert_eq(eq.quick_count("quick_1"), 3)
	assert_false(eq.bind_quick("quick_2", SWORD), "a sword is not a quick item")
	assert_true(eq.use_quick("quick_1"))
	assert_eq(inv.count(POTION), 2)


func test_slots_dictionary_lists_every_slot() -> void:
	inv.add(SWORD, 1)
	eq.equip(SWORD)
	var slots := eq.slots()
	assert_eq(slots.size(), Equipment.SLOTS.size())
	assert_eq(str(slots["main_hand"]), SWORD)
	assert_eq(str(slots["feet"]), "")


func test_save_round_trip_restores_slots_and_quick_bindings() -> void:
	inv.add(SWORD, 1)
	inv.add(HELM, 1)
	inv.add(POTION, 2)
	eq.equip(SWORD)
	eq.equip(HELM)
	eq.bind_quick("quick_1", POTION)
	var inv_text := JSON.stringify(inv.to_save())
	var eq_text := JSON.stringify(eq.to_save())
	var inv2 := Inventory.new()
	var eq2 := Equipment.new()
	eq2.inventory = inv2
	inv2.from_save(JSON.parse_string(inv_text))
	eq2.from_save(JSON.parse_string(eq_text))
	assert_eq(eq2.item_id("main_hand"), SWORD)
	assert_eq(eq2.item_id("head"), HELM)
	assert_eq(eq2.quick_item("quick_1"), POTION)
	assert_near(eq2.armour_total(), 5.0)
	eq2.free()
	inv2.free()


func test_save_loaded_before_the_inventory_still_resolves() -> void:
	inv.add(SWORD, 1)
	eq.equip(SWORD)
	var inv_text := JSON.stringify(inv.to_save())
	var eq_text := JSON.stringify(eq.to_save())
	var inv2 := Inventory.new()
	var eq2 := Equipment.new()
	eq2.inventory = inv2
	eq2.from_save(JSON.parse_string(eq_text))
	assert_eq(eq2.item_id("main_hand"), "", "nothing to resolve yet")
	inv2.from_save(JSON.parse_string(inv_text))
	assert_eq(eq2.item_id("main_hand"), SWORD, "the slot resolves once the bag arrives")
	eq2.free()
	inv2.free()


# --- the carried light ---------------------------------------------------------------------------

func test_a_lantern_in_the_off_hand_becomes_a_real_light() -> void:
	# CONTRACTS §7 gives items a `light` block; nothing read it until now, so a lantern was a
	# 1.4 kg paperweight. It hangs off Socket.Lantern and starts unlit.
	var p := Player.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	p.equip_offhand("core:item/lantern")
	var light := p.get_socket("Socket.Lantern").get_node_or_null("CarriedLight") as OmniLight3D
	assert_true(light != null, "a lamp is built on the lantern socket")
	assert_false(light.visible, "carried dark until you strike it")
	assert_near(light.omni_range, 8.0)
	assert_true(p.toggle_lantern(), "striking it lights it")
	assert_true(light.visible)
	var stealth := light.get_node_or_null("StealthLight") as StealthLight
	assert_true(stealth != null and stealth.enabled, "and the dark stops hiding you")
	assert_false(p.toggle_lantern(), "shuttering it puts it out")
	assert_false(light.visible)
	p.equip_offhand("core:item/oak_round_shield")
	assert_true(p.get_socket("Socket.Lantern").get_node_or_null("CarriedLight") == null, "a shield is not a lamp")
	assert_false(p.lantern_lit)
	(Engine.get_main_loop() as SceneTree).root.remove_child(p)
	p.free()


func test_striking_nothing_says_so_rather_than_failing_quietly() -> void:
	var p := Player.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	var heard: Array = []
	var handler := func(_text: String, kind: String) -> void: heard.append(kind)
	EventBus.notify.connect(handler)
	assert_false(p.toggle_lantern())
	EventBus.notify.disconnect(handler)
	assert_eq(heard, ["warning"])
	(Engine.get_main_loop() as SceneTree).root.remove_child(p)
	p.free()


# --- the crossbow --------------------------------------------------------------------------------

func test_a_crossbow_costs_the_winding_time_back() -> void:
	# DESIGN §5.3: a bow is drawn, a crossbow is loaded. The reload_time in the item data was
	# read by nothing, so the crossbow was a bow that fired instantly for 32 damage.
	var p := Player.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	p.equip_weapon("core:item/crossbow")
	p.arrows = 5
	assert_near(p.reload_left(), 0.0, 0.001, "it starts loaded")
	assert_near(float(p.weapon.ranged.get("draw_time", -1.0)), 0.0, 0.001, "and is not drawn")
	p._fire_arrow(1.0)
	assert_gt(p.reload_left(), 2.0, "then it has to be wound again")
	assert_false(p._start_bow(), "and will not loose while it is being wound")
	p.equip_weapon("core:item/hunting_bow")
	p._reload_until = -1.0
	p._fire_arrow(1.0)
	assert_near(p.reload_left(), 0.0, 0.001, "a bow has no reload at all")
	(Engine.get_main_loop() as SceneTree).root.remove_child(p)
	p.free()


# --- the hands follow the paper doll ---------------------------------------------------------------

func _player_with_gear() -> Player:
	var p := Player.new()
	var inv := Inventory.new()
	inv.name = "Inventory"
	p.add_child(inv)
	var eq := Equipment.new()
	eq.name = "Equipment"
	p.add_child(eq)
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	eq.set_inventory(inv)
	return p


func test_what_you_equip_in_the_menu_is_what_you_swing() -> void:
	# Equipping went through Equipment and never reached the WeaponInstance, so the paper doll
	# and the hands disagreed: the menu said greatsword and the swing was still a fist.
	var p := _player_with_gear()
	var inv: Inventory = p.get_node("Inventory")
	var eq: Equipment = p.get_node("Equipment")
	var stack := inv.add("core:item/iron_greatsword", 1)
	assert_true(eq.equip(stack))
	assert_eq(p.weapon.item_id, "core:item/iron_greatsword", "the hands follow the doll")
	assert_eq(p.weapon.weapon_class, "greatsword")
	(Engine.get_main_loop() as SceneTree).root.remove_child(p)
	p.free()


func test_a_tempered_weapon_hits_harder_in_the_hand() -> void:
	var p := _player_with_gear()
	var inv: Inventory = p.get_node("Inventory")
	var eq: Equipment = p.get_node("Equipment")
	var plain := inv.add("core:item/iron_sword", 1)
	eq.equip(plain)
	var base := p.weapon.damage
	var fine := inv.add("core:item/iron_sword", 1, {"temper": 3})
	eq.equip(fine)
	assert_gt(p.weapon.damage, base, "three tiers of tempering are worth something")
	(Engine.get_main_loop() as SceneTree).root.remove_child(p)
	p.free()


func test_an_enchanted_blade_burns_and_runs_down() -> void:
	# Enchanting wrote `enchant` onto the stack and combat never looked at it: a named weapon
	# did exactly what an unnamed one did.
	var p := _player_with_gear()
	var inv: Inventory = p.get_node("Inventory")
	var eq: Equipment = p.get_node("Equipment")
	var stack := inv.add("core:item/iron_sword", 1, {"enchant":
		{"effect": "core:effect/ember_burst", "magnitude": 8.0, "duration": 4.0, "charge": 30, "charge_max": 30}})
	eq.equip(stack)
	var hit := p.weapon.build_hit("light", 0, 0.0, 10.0)
	assert_eq(hit.kind, "fire", "the blade's own damage type wins")
	var burned := false
	for st in hit.statuses:
		if str(st["id"]) == "burning":
			burned = true
	assert_true(burned, "and it leaves the mark the effect describes")
	assert_gt(hit.enchant_cost, 0, "which costs charge")
	p.weapon._spend_charge(hit.enchant_cost)
	assert_eq(int(stack.data["enchant"]["charge"]), 30 - hit.enchant_cost, "off the blade and off the stack")
	# A spent enchantment is a decoration.
	stack.data["enchant"]["charge"] = 0
	p.weapon.enchant["charge"] = 0
	var spent := p.weapon.build_hit("light", 0, 0.0, 10.0)
	assert_eq(spent.kind, "slash", "a weapon with nothing left in it is just iron")
	assert_eq(spent.enchant_cost, 0)
	(Engine.get_main_loop() as SceneTree).root.remove_child(p)
	p.free()


# --- the belt ---------------------------------------------------------------------------------

## The belt was implemented twice and reachable from neither end. `Equipment` bound it,
## counted it, used it, saved it and told the HUD about it; the HUD drew four slots. But
## nothing in the game ever called `bind_quick` — the inventory screen only offers Equip to
## things `is_equippable()` calls equippable, and that is weapons and armour — and the quick
## keys read a *second* array on the Player that nothing filled. Four dim slots on screen
## read exactly like "you have nothing worth putting there".
func test_a_quick_key_drinks_the_potion_on_the_belt() -> void:
	var p := _player_with_gear()
	var bag: Inventory = p.get_node("Inventory")
	var doll: Equipment = p.get_node("Equipment")
	bag.add(POTION, 2)
	p.set_quick_slot(0, POTION)
	assert_eq(doll.quick_item("quick_1"), POTION,
		"binding a belt slot on the player did not reach the doll the HUD reads")
	p.use_quick_slot(0)
	assert_eq(bag.count(POTION), 1, "the quick key did not drink anything")
	p.queue_free()


## The keys used to read the player's own array; the HUD read the doll. Whichever one a future
## caller fills, the other must not disagree, because a belt you can see and cannot fire is
## worse than no belt at all.
func test_the_belt_the_hud_draws_is_the_belt_the_keys_fire() -> void:
	var p := _player_with_gear()
	var bag: Inventory = p.get_node("Inventory")
	var doll: Equipment = p.get_node("Equipment")
	bag.add(POTION, 1)
	doll.bind_quick("quick_2", POTION)
	# An Array, not a String: a lambda captures a local by value, so a captured String is
	# written to a copy and the assertion reads the empty original.
	var fired: Array[String] = []
	p.quick_slot_used.connect(func(_i: int, id: String) -> void: fired.append(id))
	p.use_quick_slot(1)
	assert_eq(fired, [POTION] as Array[String], "the key fired a different slot than the HUD draws")
	p.queue_free()


## A saying is not an item and has no place on the paper doll, so the player's own array is
## still the right home for one. Binding it must not try to put it on the doll and fail.
func test_a_saying_still_rides_the_players_own_slot() -> void:
	var p := _player_with_gear()
	var doll: Equipment = p.get_node("Equipment")
	p.set_quick_slot(2, "core:spell/emberlight")
	assert_eq(doll.quick_item("quick_3"), "", "a saying was pushed onto the paper doll")
	assert_eq(str(p.quick_slots[2]), "core:spell/emberlight")
	p.queue_free()


## Taking it off again is the other half of putting it on, and it was equally unreachable.
func test_clearing_a_belt_slot_reaches_the_doll() -> void:
	var p := _player_with_gear()
	var bag: Inventory = p.get_node("Inventory")
	var doll: Equipment = p.get_node("Equipment")
	bag.add(POTION, 1)
	p.set_quick_slot(0, POTION)
	p.set_quick_slot(0, "")
	assert_eq(doll.quick_item("quick_1"), "", "the slot was cleared on the player and not the doll")
	p.queue_free()
