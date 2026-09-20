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
	assert_true(registry.owns(DEED), "the screen bought a house the registry never heard of")
	assert_gt(bag.count(DEED), 0, "no deed in the bag")
	var key := PropertyRegistry.key_item_of(DEED)
	assert_gt(bag.count(key), 0, "no key with the deed, so the door stays shut")


func test_you_cannot_take_a_key_you_cannot_pay_for() -> void:
	bag.remove_marks(bag.marks)
	_open(registry.asking_price(DEED))
	await _tree().process_frame
	assert_true(_button("Take the key").disabled, "a penniless player was offered the key")
	assert_false(registry.owns(DEED))


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
	sign_node.queue_free()
