extends TestCase
## Looting a chest. `take_all()` had no caller outside a test and no screen showed the
## contents, so every chest, barrel and cupboard in the world was scenery you could open and
## not reach into. These pin the taking rather than the pixels: one item, the money, the lot,
## and the rule that emptying somebody's strongbox is one theft and not nine.

const OWNER := "core:npc/ellard_wynstead"
## Merrowby, wherever the map puts it (docs/COORDINATES.md).
var HERE := at_place("core:place/merrowby", 56.0)

var chest: WorldContainer
var player: Node3D
var bag: Inventory
var crimes: Array[Dictionary] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	# Containers persist their contents by id, so a chest built with the same id in the next
	# test would restore what the last one left in it.
	WorldContainer.store.clear()
	Bounty.ensure().clear_all()
	CrimeReports.ensure()
	crimes = []
	EventBus.crime_committed.connect(_note)
	player = Node3D.new()
	player.add_to_group("player")
	_tree().root.add_child(player)
	player.global_position = HERE
	bag = Inventory.new()
	player.add_child(bag)
	chest = WorldContainer.new()
	chest.container_id = "test:container/kist"
	_tree().root.add_child(chest)
	chest.global_position = HERE


func after_each() -> void:
	if EventBus.crime_committed.is_connected(_note):
		EventBus.crime_committed.disconnect(_note)
	for n in [chest, player]:
		if is_instance_valid(n):
			n.queue_free()
	Bounty.ensure().clear_all()


func _note(crime: Dictionary) -> void:
	crimes.append(crime)


func _fill() -> void:
	chest.inventory.add("core:item/iron_sword", 1)
	chest.inventory.add("core:item/bread", 3)
	chest.inventory.add_marks(40)


# --- taking ---------------------------------------------------------------------------------

func test_one_thing_at_a_time() -> void:
	_fill()
	var first: ItemStack = chest.inventory.stacks()[0]
	var id := first.id
	assert_true(chest.take(first, player), "the stack would not come out")
	assert_true(bag.has(id), "it did not arrive in the bag")
	assert_false(chest.inventory.has(id), "it is still in the chest as well")


func test_the_money_comes_out_separately() -> void:
	_fill()
	assert_eq(chest.take_marks(player), 40)
	assert_eq(bag.marks, 40, "the marks did not reach the purse")
	assert_eq(chest.inventory.marks, 0, "the chest kept its money")


func test_take_everything_empties_it() -> void:
	_fill()
	chest.take_all(player)
	assert_true(chest.inventory.is_empty(), "something was left behind")
	assert_eq(chest.inventory.marks, 0)
	assert_eq(bag.marks, 40)


func test_taking_from_a_chest_that_is_not_there_fails_quietly() -> void:
	var loose := ItemStack.new()
	loose.id = "core:item/bread"
	loose.count = 1
	assert_false(chest.take(loose, player), "a stack the chest does not hold came out of it")


# --- and the law ------------------------------------------------------------------------------

func test_emptying_a_strangers_chest_item_by_item_is_one_theft() -> void:
	chest.owner_npc = OWNER
	_fill()
	while not chest.inventory.stacks().is_empty():
		chest.take(chest.inventory.stacks()[0], player)
	chest.take_marks(player)
	assert_true(crimes.is_empty(), "the law was told before the visit was over")
	chest.close_up(player)
	assert_eq(crimes.size(), 1, "emptying one chest made %d separate cases" % crimes.size())
	assert_eq(str(crimes[0].get("kind", "")), "theft")
	assert_gt(int(crimes[0].get("value", 0)), 40, "the theft was priced at less than the money in it")


func test_closing_an_unowned_chest_reports_nothing() -> void:
	_fill()
	chest.take_all(player)
	chest.close_up(player)
	assert_true(crimes.is_empty(), "looting a chest nobody owns was reported")


func test_closing_a_chest_you_took_nothing_from_reports_nothing() -> void:
	chest.owner_npc = OWNER
	_fill()
	chest.close_up(player)
	assert_true(crimes.is_empty(), "looking in a chest was a crime")


func test_the_tally_resets_so_a_second_visit_is_its_own_theft() -> void:
	chest.owner_npc = OWNER
	_fill()
	chest.take_all(player)      # take_all closes up by itself
	assert_eq(crimes.size(), 1)
	chest.close_up(player)
	assert_eq(crimes.size(), 1, "closing an emptied chest reported the same theft twice")


# --- the screen exists and is reachable ---------------------------------------------------------

func test_the_ui_knows_about_the_container_screen() -> void:
	assert_true(UI.MENUS.has("container"), "no container screen is registered")
	var path: String = UI.MENUS["container"]["scene"]
	assert_true(ResourceLoader.exists(path), "the container screen's scene is missing: %s" % path)
