extends TestCase
## Pressing the button at the forge, not calling the function underneath it.
##
## `Crafting.temper` and `Crafting.temper_preview` are the whole of "temper existing gear
## (+10% per tier)" from DESIGN §5.8, with passing tests behind them, and `station_screen.gd`'s
## own header said the forge tab does "tempering what you already own". No file in `game/ui`
## called either one. You could walk to Hallam's anvil, have the iron and the sword in your
## bag, and there was no control on the screen that would put one into the other.
##
## So these find the control by the words on it, press it, and then ask `Crafting` and the bag
## whether the tier rose and the material was spent.

const SCREEN := preload("res://ui/crafting/station_screen.tscn")
const SWORD := "core:item/iron_sword"
const INGOT := "core:item/iron_ingot"

var holder: Node
var bag: Inventory
var crafting: Crafting
var screen: Control


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	holder = Node.new()
	bag = Inventory.new()
	crafting = Crafting.new()
	holder.add_child(bag)
	holder.add_child(crafting)
	_tree().root.add_child(holder)


func after_each() -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	screen = null
	if holder != null and is_instance_valid(holder):
		holder.queue_free()
	holder = null
	UI.close_all()
	if _tree().paused:
		_tree().paused = false


## Hand it the pair: a leftover Inventory from another test file is just as much in the
## "inventory" group as ours, and the screen looks by group.
func _open() -> void:
	screen = SCREEN.instantiate()
	screen.call("setup", {"station": "forge", "crafting": crafting, "bag": bag})
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


## The row in the list whose label reads like this: the forge's rows are flat buttons with a
## label inside them, the way the player sees them.
func _row(contains: String) -> Button:
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var b := n as Button
		if b != null:
			for child in b.find_children("*", "Label", true, false):
				if (child as Label).text.contains(contains):
					return b
		stack.append_array(n.get_children())
	return null


## Picks the sword out of the forge's list, the way a player does before deciding.
func _pick_the_sword() -> void:
	var row := _row("Iron Sword")
	if row == null:
		row = _row("Iron sword")
	assert_true(row != null, "the sword in the bag is not on the forge's list: %s" % _words())
	if row != null:
		row.pressed.emit()


## Every Label under the screen, as one string, for asking what the screen says.
func _words() -> String:
	var out := ""
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var l := n as Label
		if l != null:
			out += l.text + "\n"
		stack.append_array(n.get_children())
	return out


func test_the_forge_lists_the_gear_you_are_carrying() -> void:
	bag.add(SWORD, 1)
	bag.add(INGOT, 4)
	_open()
	assert_true(_words().contains("What you carry"),
			"the forge offered no way to temper anything you own")
	assert_true(_words().contains("Iron Sword") or _words().contains("Iron sword"),
			"the sword in the bag is not on the forge's list: %s" % _words())


func test_tempering_raises_the_tier_and_spends_the_material() -> void:
	var stack := bag.add(SWORD, 1)
	bag.add(INGOT, 4)
	_open()
	_pick_the_sword()
	assert_eq(stack.temper_tier(), 0, "it starts untempered")
	var strike := _button("Temper it")
	assert_true(strike != null, "there is no button at the forge that tempers anything")
	assert_false(strike.disabled, "the sword can be tempered and the button was dead")
	strike.pressed.emit()

	# Ask the bag, not the screen. Tempering splits a stack, so find the tempered piece.
	var best := 0
	for s in bag.query({"id": SWORD}):
		best = maxi(best, s.temper_tier())
	assert_eq(best, 1, "pressing Temper it did not raise the tier")
	assert_eq(bag.count(INGOT), 3, "pressing Temper it did not spend any iron")


## What it became stays in front of you, and the ceiling is the smith's, not the iron's: at
## smithing 0 the second tier is out of reach and the screen has to say so rather than offer
## a button that does nothing. Tempering splits the stack, so the piece that was struck has a
## new uid -- the screen follows it rather than losing the selection.
func test_the_struck_piece_stays_in_front_of_you_with_its_new_tier() -> void:
	bag.add(SWORD, 1)
	bag.add(INGOT, 4)
	_open()
	_pick_the_sword()
	_button("Temper it").pressed.emit()
	assert_true(_words().contains("+1"), "the screen does not say what the tier became")
	var strike := _button("Temper it")
	assert_true(strike != null, "the tempered piece fell off the list")
	assert_true(strike.disabled, "a smith of no skill was offered a second tier")
	assert_true(_words().contains("smithing"),
			"the forge does not say the second tier wants a better smith: %s" % _words())


## What it costs has to be on the screen before it is spent, and that is what `temper_preview`
## is for. It had ten passing tests and no caller.
func test_the_screen_says_what_it_costs_before_you_press_it() -> void:
	bag.add(SWORD, 1)
	bag.add(INGOT, 4)
	_open()
	_pick_the_sword()
	var said := _words()
	assert_true(said.contains("It takes"), "the forge does not say what tempering takes")
	assert_true(said.contains("Iron Ingot") or said.contains("Iron ingot"),
			"the forge does not name the material: %s" % said)
	assert_true(said.contains("1 / 1") or said.contains("4 / 1"),
			"the forge does not say how much of it: %s" % said)


func test_with_no_iron_the_button_is_dead_and_the_screen_says_why() -> void:
	bag.add(SWORD, 1)
	_open()
	_pick_the_sword()
	var strike := _button("Temper it")
	assert_true(strike != null, "the sword is still temperable, it is only short of iron")
	assert_true(strike.disabled, "a forge with no iron in the bag still offered to temper")
	assert_true(_words().contains("short"), "the forge does not say why: %s" % _words())


## A potion is not gear and the forge has nothing to say about it.
func test_what_is_not_gear_is_not_on_the_list() -> void:
	bag.add("core:item/potion_restore_health", 2)
	bag.add(INGOT, 4)
	_open()
	assert_false(_words().contains("Potion"), "the forge offered to temper a potion: %s" % _words())
