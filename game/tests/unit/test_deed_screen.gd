extends TestCase
## Buying a house by pressing the button on the board outside it.
##
## Three pieces existed and none of them were joined. `PropertySign` is a for-sale board that
## nothing placed. `deed_confirm.tscn` is a confirmation screen that nothing opened. And the
## screen's own Take-the-key took the marks itself, set a flag called `owns:<id>` that nothing
## else reads, and emitted the purchase signal — a second kind of ownership, with no deed in
## your bag, no key, no door or bed claimed in your name, and `PropertyRegistry.owns()` still
## saying no. The journey passed throughout, because it calls `buy()` directly.

const SCREEN := preload("res://ui/property/deed_confirm.tscn")
const DEED := "core:item/deed_merrowby_crater_cottage"

var registry: PropertyRegistry
var player: Node3D
var bag: Inventory
var screen: Control


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	player = Node3D.new()
	player.add_to_group("player")
	_tree().root.add_child(player)
	bag = Inventory.new()
	bag.add_to_group("inventory")
	player.add_child(bag)
	registry = PropertyRegistry.ensure()
	registry.owned.clear()
	bag.add_marks(9000)


func after_each() -> void:
	for n in [screen, player]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	if is_instance_valid(registry):
		registry.owned.clear()
	screen = null


func _open(price: int) -> void:
	screen = SCREEN.instantiate()
	screen.call("setup", {"property_id": DEED, "name": "the Crater Cottage",
		"place": "Merrowby", "price": price})
	_tree().root.add_child(screen)


func _button(text: String) -> Button:
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var b := n as Button
		if b != null and b.text == text:
			return b
		stack.append_array(n.get_children())
	return null


func test_taking_the_key_is_the_same_buying_the_journey_does() -> void:
	_open(registry.asking_price(DEED))
	await _tree().process_frame
	_button("Take the key").pressed.emit()
	await _tree().process_frame
	# `owns` never existed on the registry (`is_owned` does): this line threw, the test stopped
	# here, and the two lines under it were never reached
	assert_true(registry.is_owned(DEED), "the screen bought a house the registry never heard of")
	assert_gt(bag.count(DEED), 0, "no deed in the bag")
	var key := PropertyRegistry.key_item_of(DEED)
	assert_gt(bag.count(key), 0, "no key with the deed, so the door stays shut")


func test_you_cannot_take_a_key_you_cannot_pay_for() -> void:
	bag.remove_marks(bag.marks)
	_open(registry.asking_price(DEED))
	await _tree().process_frame
	assert_true(_button("Take the key").disabled, "a penniless player was offered the key")
	assert_false(registry.is_owned(DEED))


## Buying a furnishing for a house you own, by pressing the button on the landlord's board.
##
## DESIGN §5.14 ends "Furnishings bought". `PropertyRegistry.add_furnishing()` and
## `furnishings()` were written, saved and tested, and `tools/unwired.py --verbs` showed
## nothing outside the tests calling either of them: there was nowhere in the game to buy one
## and nothing that drew one. This is the buying.
const RUG := "core:item/furnishing_hearth_rug"


func _own_it() -> void:
	registry.grant(DEED)
	screen = SCREEN.instantiate()
	screen.call("setup", {"property_id": DEED, "name": "the Crater Cottage", "place": "Merrowby"})
	_tree().root.add_child(screen)


func test_the_board_of_a_house_you_own_sells_furnishings() -> void:
	_own_it()
	await _tree().process_frame
	assert_true(screen.call("owned"), "the screen did not know the house was already yours")
	assert_true(_button("Take the key") == null, "your own house was offered for sale again")
	assert_true(_labels().any(func(t: String) -> bool: return t == "Furnishings"),
		"the landlord's board offered no furnishings at all")
	var rug_name := str(ContentDB.get_def(RUG)["name"])
	assert_true(_labels().has(rug_name), "%s was not on offer" % rug_name)


func test_buying_one_takes_the_marks_and_puts_it_in_the_house() -> void:
	_own_it()
	await _tree().process_frame
	var before := bag.marks
	var price := PropertyRegistry.furnishing_price(RUG)
	assert_gt(price, 0, "a furnishing with no price")
	_row_button(str(ContentDB.get_def(RUG)["name"]), "Buy it").pressed.emit()
	await _tree().process_frame
	assert_true(registry.furnishings(DEED).has(RUG), "the rug was bought and not recorded")
	assert_eq(bag.marks, before - price, "the marks did not leave the bag")
	assert_true(_labels().has("in the house"),
		"the board went on offering a furnishing that is already in the house")


func test_you_cannot_buy_a_furnishing_you_cannot_pay_for() -> void:
	bag.remove_marks(bag.marks)
	_own_it()
	await _tree().process_frame
	assert_true(_row_button(str(ContentDB.get_def(RUG)["name"]), "Buy it").disabled,
		"a penniless landlord was offered a rug")
	assert_empty(registry.furnishings(DEED))


## Rent and letting are buttons on the same board now, rather than three things one silent
## press at the sign might have done.
func test_the_board_lets_the_house_and_collects_the_rent() -> void:
	_own_it()
	await _tree().process_frame
	_button("Put it to let (%s marks a day)" % UiKit.marks(PropertyRegistry.rent_per_day(DEED))).pressed.emit()
	await _tree().process_frame
	assert_true(registry.is_let(DEED), "the board did not let the house")
	WorldClock.set_time(9.0, WorldClock.day + 4)
	var due := registry.rent_due(DEED)
	assert_gt(due, 0, "no rent accrued over four days")
	var before := bag.marks
	screen.call("_rebuild")
	await _tree().process_frame
	_button("Collect %s marks of rent" % UiKit.marks(due)).pressed.emit()
	await _tree().process_frame
	assert_eq(bag.marks, before + due, "the rent did not reach the bag")
	assert_eq(registry.rent_due(DEED), 0, "the rent was not collected")
	assert_true(registry.is_let(DEED), "collecting the rent also ended the tenancy")


## The button on the row whose name label says `name`, so two rows offering "Buy it" do not
## get mixed up.
func _row_button(row_name: String, text: String) -> Button:
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is HBoxContainer:
			var names := false
			var found: Button = null
			for child in n.get_children():
				var l := child as Label
				if l != null and l.text == row_name:
					names = true
				var b := child as Button
				if b != null and b.text == text:
					found = b
			if names and found != null:
				return found
		stack.append_array(n.get_children())
	return null


func _labels() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var l := n as Label
		if l != null:
			out.append(l.text)
		stack.append_array(n.get_children())
	return out


## Walking up to the board has to reach the screen. The sign's own `offer_made` signal had no
## listener outside a test, so a board with `confirm_required` quoted a price into the air.
func test_reading_the_board_offers_the_deed() -> void:
	var sign_node := PropertySign.new()
	sign_node.property_id = DEED
	_tree().root.add_child(sign_node)
	var offered: Array[String] = []
	var note := func(id: String, _price: int) -> void: offered.append(id)
	EventBus.property_offered.connect(note)
	sign_node.interact(player)
	EventBus.property_offered.disconnect(note)
	assert_eq(offered, [DEED] as Array[String], "the board offered nothing to anybody")
	assert_true(UI.MENUS.has("deed"), "no screen is registered to answer the offer")
	close_screen("deed", "the offer is answered by the deed screen")
	sign_node.queue_free()
