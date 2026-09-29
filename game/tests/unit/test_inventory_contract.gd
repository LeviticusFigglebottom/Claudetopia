extends TestCase
## The cross-stream contract: the groups other systems look the nodes up by, and the method
## names the UI, hearth, combat, NPC and crime streams call. If a name here changes, another
## stream breaks, so this test is the record of it.

const APPLE := "core:item/apple"
const SWORD := "core:item/iron_sword"


func test_a_bag_on_a_player_actor_joins_the_inventory_group() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	var bag := Inventory.new()
	var eq := Equipment.new()
	player.add_child(bag)
	player.add_child(eq)
	root().add_child(player)
	assert_true(bag.is_in_group(Inventory.GROUP), "the player's bag announces itself")
	assert_true(bag.is_player)
	assert_eq(Inventory.player_bag(root().get_tree()), bag)
	assert_true(eq.is_in_group(Equipment.GROUP))
	assert_eq(eq.inventory, bag, "the paper-doll finds its sibling bag")
	player.free()


func test_a_loose_bag_stays_out_of_the_group() -> void:
	var chest := Node3D.new()
	var bag := Inventory.new()
	chest.add_child(bag)
	root().add_child(chest)
	assert_false(bag.is_in_group(Inventory.GROUP), "a chest is not the player")
	assert_eq(Inventory.player_bag(root().get_tree()), null)
	chest.free()


func test_the_hearth_can_take_and_return_marks_through_the_group() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	var bag := Inventory.new()
	player.add_child(bag)
	root().add_child(player)
	bag.add_marks(140)
	var found: Node = root().get_tree().get_first_node_in_group("inventory")
	assert_ne(found, null)
	var marks := int(found.get("marks"))
	assert_eq(marks, 140)
	assert_eq(found.call("remove_marks", marks), 140, "death takes what the Echo will hold")
	assert_eq(int(found.get("marks")), 0)
	found.call("add_marks", marks)
	assert_eq(int(found.get("marks")), 140, "and the Echo gives it back")
	player.free()


func test_the_inventory_methods_the_other_streams_call_exist() -> void:
	var bag := Inventory.new()
	for method in ["add", "remove", "has", "count", "items", "weight", "capacity", "use", "drop", "add_marks", "remove_marks", "query", "sort", "transfer_to", "to_save", "from_save"]:
		assert_true(bag.has_method(method), "Inventory.%s is part of the contract" % method)
	bag.add(APPLE, 2)
	var items := bag.items()
	assert_eq(items.size(), 1)
	for key in ["item_id", "count", "name", "category", "weight", "value"]:
		assert_has(items[0], key)
	assert_near(bag.weight(), 0.4, 0.001)
	assert_gt(bag.capacity(), 0.0)
	bag.free()


func test_the_equipment_methods_the_ui_calls_exist() -> void:
	var bag := Inventory.new()
	var eq := Equipment.new()
	eq.inventory = bag
	for method in ["slots", "equip", "unequip", "get_slot", "item_id", "armour_total", "stability", "weight_class", "modifiers", "summary", "use_quick", "to_save", "from_save"]:
		assert_true(eq.has_method(method), "Equipment.%s is part of the contract" % method)
	bag.add(SWORD, 1)
	assert_true(eq.equip(SWORD), "equipping by item id works")
	assert_eq(str(eq.slots()["main_hand"]), SWORD)
	eq.unequip("main_hand")
	assert_eq(str(eq.slots()["main_hand"]), "")
	eq.free()
	bag.free()


func test_the_progression_methods_the_ui_calls_exist() -> void:
	var prog := Progression.new()
	prog.listen_to_event_bus = false
	root().add_child(prog)
	assert_true(prog.is_in_group(Progression.GROUP))
	for method in ["skills", "perks_for", "take_perk", "spend_attribute", "skill_level", "attribute", "summary", "load_capacity", "max_health", "max_stamina", "max_mana"]:
		assert_true(prog.has_method(method), "Progression.%s is part of the contract" % method)
	var skills := prog.skills()
	assert_eq(skills.size(), 16)
	for key in ["id", "level", "progress"]:
		assert_has(skills[0], key)
	var perks := prog.perks_for("one_handed")
	assert_eq(perks.size(), 3)
	for key in ["id", "name", "description", "requires_level", "taken", "available"]:
		assert_has(perks[0], key)
	assert_eq(prog.level, 1)
	assert_eq(prog.attribute_points, 0)
	assert_eq(prog.perk_points, 0)
	prog.free()


func test_the_crafting_methods_the_ui_calls_exist() -> void:
	var holder := Node.new()
	var bag := Inventory.new()
	var c := Crafting.new()
	holder.add_child(bag)
	holder.add_child(c)
	root().add_child(holder)
	assert_true(c.is_in_group(Crafting.GROUP))
	for method in ["recipes_for", "craft", "known_effects", "combine", "enchant", "disenchant", "recharge", "consume_charge", "temper", "ingredients", "enchantments", "eat_ingredient"]:
		assert_true(c.has_method(method), "Crafting.%s is part of the contract" % method)
	var recipes := c.recipes_for("forge")
	assert_gt(recipes.size(), 0)
	for key in ["id", "name", "inputs", "output", "can_craft", "missing"]:
		assert_has(recipes[0], key)
	var r := c.combine([APPLE, "core:item/watercress"])
	for key in ["ok", "item_id", "effects"]:
		assert_has(r, key)
	holder.free()


func test_the_player_bag_mirrors_its_events_onto_the_event_bus() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	var bag := Inventory.new()
	player.add_child(bag)
	root().add_child(player)
	var acquired: Array = []
	var removed: Array = []
	var marks: Array = []
	var a := func(id: String, n: int) -> void: acquired.append([id, n])
	var r := func(id: String, n: int) -> void: removed.append([id, n])
	var m := func(total: int, delta: int) -> void: marks.append([total, delta])
	EventBus.item_acquired.connect(a)
	EventBus.item_removed.connect(r)
	EventBus.marks_changed.connect(m)
	bag.add(APPLE, 3)
	bag.remove(APPLE, 1)
	bag.add_marks(10)
	assert_eq(acquired, [[APPLE, 3]])
	assert_eq(removed, [[APPLE, 1]])
	assert_eq(marks, [[10, 10]])
	EventBus.item_acquired.disconnect(a)
	EventBus.item_removed.disconnect(r)
	EventBus.marks_changed.disconnect(m)
	player.free()


func test_equipping_on_the_player_announces_the_slot() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	var bag := Inventory.new()
	var eq := Equipment.new()
	player.add_child(bag)
	player.add_child(eq)
	root().add_child(player)
	var events: Array = []
	var cb := func(slot: String, item_id: String) -> void: events.append([slot, item_id])
	EventBus.item_equipped.connect(cb)
	bag.add(SWORD, 1)
	eq.equip(SWORD)
	eq.unequip("main_hand")
	assert_eq(events, [["main_hand", SWORD], ["main_hand", ""]])
	EventBus.item_equipped.disconnect(cb)
	player.free()


func test_the_save_sections_are_the_ones_architecture_lists() -> void:
	assert_eq(Crafting.SAVE_SECTION, "crafting")
	assert_eq(Progression.SAVE_SECTION, "progression")
	assert_eq(WorldContainer.SAVE_SECTION, "containers")


func root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func test_an_item_description_can_follow_a_story_flag() -> void:
	var had := GameState.has_flag("woke_at_hushline")
	GameState.clear_flag("woke_at_hushline")
	var bell := ItemStack.new("core:item/listening_bell")
	assert_true(bell.description().contains("hums"), "before the wake the bell hums")
	GameState.set_flag("woke_at_hushline")
	assert_true(bell.description().contains("silent"), "after the wake it is silent")
	if not had:
		GameState.clear_flag("woke_at_hushline")
