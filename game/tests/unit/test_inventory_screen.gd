extends TestCase
## Pressing the button, not calling the function underneath it.
##
## `Equipment` could bind a belt slot, count it, use it, save it and tell the HUD about it,
## and the HUD drew four slots for it. Nothing in the game ever bound one: the inventory
## screen offers Equip only to things `ItemStack.is_equippable()` calls equippable, which is
## weapons and armour, so a potion got Use and nothing else. Every test of the belt passed.
##
## So this one finds the button by the words on it and presses it. It is slower and clumsier
## than calling `bind_quick` directly and it is the only kind of test that would have caught
## the thing that was actually wrong.

const SCREEN := preload("res://ui/inventory/inventory_screen.tscn")
const POTION := "core:item/potion_restore_health"
const SWORD := "core:item/iron_sword"

var bag: Inventory
var doll: Equipment
var screen: Control


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	bag = Inventory.new()
	bag.add_to_group("inventory")
	doll = Equipment.new()
	doll.add_to_group("equipment")
	doll.inventory = bag
	_tree().root.add_child(bag)
	_tree().root.add_child(doll)


func after_each() -> void:
	for n in [screen, doll, bag]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	screen = null


## The screen finds the real bag and paper doll by group, and a leftover `Inventory` from
## another test file is just as much in that group as ours. Hand it the pair explicitly.
func _open() -> void:
	screen = SCREEN.instantiate()
	screen.call("setup", {"bag": bag, "doll": doll})
	_tree().root.add_child(screen)


## Every Button anywhere under the screen whose label is exactly this.
func _button(text: String) -> Button:
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var b := n as Button
		if b != null and b.text == text:
			return b
		stack.append_array(n.get_children())
	return null


func test_a_potion_offers_the_belt_and_a_sword_does_not() -> void:
	bag.add(POTION, 2)
	_open()
	await _tree().process_frame
	assert_true(_button("To the belt") != null,
		"a potion in the bag offered no way onto the belt, so the four HUD slots stay empty")
	assert_true(_button("Use") != null, "a potion should still be drinkable from the bag")

	bag.remove(POTION, bag.count(POTION))
	bag.add(SWORD, 1)
	await _tree().process_frame
	assert_true(_button("To the belt") == null, "a sword was offered a belt slot it cannot take")


func test_pressing_the_button_binds_the_slot_the_hud_reads() -> void:
	bag.add(POTION, 2)
	_open()
	await _tree().process_frame
	_button("To the belt").pressed.emit()
	await _tree().process_frame
	assert_eq(doll.quick_item("quick_1"), POTION,
		"the button did not reach the paper doll the HUD draws from")
	assert_eq(doll.quick_count("quick_1"), 2, "the belt did not count what is in the bag")


func test_the_same_button_takes_it_off_again() -> void:
	bag.add(POTION, 1)
	_open()
	await _tree().process_frame
	_button("To the belt").pressed.emit()
	await _tree().process_frame
	var off := _button("Off the belt")
	assert_true(off != null, "once it is on the belt there was no way to take it off")
	off.pressed.emit()
	await _tree().process_frame
	assert_eq(doll.quick_item("quick_1"), "", "it stayed on the belt")


## The first free slot, not the first slot: a belt that always overwrites slot one holds one
## thing however many slots are drawn.
func test_the_belt_fills_the_first_free_slot() -> void:
	const STAMINA := "core:item/potion_restore_stamina"
	doll.bind_quick("quick_1", POTION)
	bag.add(STAMINA, 1)
	_open()
	await _tree().process_frame
	var b := _button("To the belt")
	assert_true(b != null, "the second potion was offered no slot at all")
	b.pressed.emit()
	await _tree().process_frame
	assert_eq(doll.quick_item("quick_1"), POTION, "the first slot was overwritten")
	assert_eq(doll.quick_item("quick_2"), STAMINA, "the second potion did not find the free slot")
