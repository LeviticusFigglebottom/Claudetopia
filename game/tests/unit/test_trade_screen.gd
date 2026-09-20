extends TestCase
## Shopping, by pressing what is on the counter.
##
## `Merchant` is the whole of DESIGN §5.14 and it was reached by nothing a player can do. The
## trade screen was handed an npc id and went looking for "any Inventory that is not the
## player's" — so it traded against whatever bag happened to be first in the scene tree, at
## base value times a flat multiplier. The shopkeeper's own stock, marks, disposition, your
## Speech, their temper, what they will and will not deal in, and the Vale's refusal to serve
## a Hollow customer were all sitting there being tested and never being shopped against.

const SCREEN := preload("res://ui/trade/trade_screen.tscn")
const SHOPKEEPER := "core:npc/wren_tallow"
const ROPE := "core:item/rope"

var merchant: Merchant
var player: Node3D
var bag: Inventory
var screen: Control


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	Peers.overrides.clear()
	if EconomyService.instance != null:
		EconomyService.instance.saved_state.clear()
	player = Node3D.new()
	player.add_to_group("player")
	_tree().root.add_child(player)
	bag = Inventory.new()
	bag.add_to_group("inventory")
	player.add_child(bag)
	bag.add_marks(2000)
	merchant = Merchant.new()
	merchant.name = "Merchant"
	merchant.npc_id = SHOPKEEPER
	_tree().root.add_child(merchant)


func after_each() -> void:
	for n in [screen, merchant, player]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	screen = null
	Peers.overrides.clear()


func _open() -> void:
	screen = SCREEN.instantiate()
	screen.call("setup", {"merchant_id": SHOPKEEPER, "merchant": merchant})
	_tree().root.add_child(screen)


func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var b := n as Button
		if b != null:
			out.append(b)
		stack.append_array(n.get_children())
	return out


## The button whose row names this item, on either side of the counter.
func _row_for(item_id: String) -> Button:
	var wanted := str(ContentDB.get_or_empty(item_id).get("name", ""))
	for b in _buttons():
		for child in b.find_children("*", "Label", true, false):
			if (child as Label).text == wanted:
				return b
	return null


func test_the_counter_shows_the_shopkeepers_own_stock() -> void:
	merchant.stock = {ROPE: 4}
	_open()
	await _tree().process_frame
	assert_true(_row_for(ROPE) != null,
		"the shopkeeper's rope was not on the counter, so this is somebody else's bag")


func test_buying_takes_it_out_of_their_stock_and_your_purse() -> void:
	merchant.stock = {ROPE: 4}
	merchant.marks = 300
	_open()
	await _tree().process_frame
	var before := bag.marks
	_row_for(ROPE).pressed.emit()
	await _tree().process_frame
	assert_eq(merchant.count(ROPE), 3, "the shop did not part with the rope")
	assert_eq(bag.count(ROPE), 1, "the rope did not reach the bag")
	assert_gt(before, bag.marks, "the rope was free")
	assert_gt(merchant.marks, 300, "the shopkeeper was not paid")


func test_the_price_is_the_shopkeepers_price_and_not_base_value() -> void:
	merchant.stock = {ROPE: 4}
	_open()
	await _tree().process_frame
	var shown := int(screen.call("price_of", ROPE, 1, true))
	assert_eq(shown, merchant.buy_price_of(ROPE),
		"the screen quoted its own price instead of the shopkeeper's")


## They deal in what they deal in. The old screen would take anything.
func test_they_will_not_buy_what_they_do_not_deal_in() -> void:
	merchant.buys = ["material"]
	merchant.stock = {ROPE: 1}
	bag.add("core:item/iron_greatsword", 1)
	_open()
	await _tree().process_frame
	var row := _row_for("core:item/iron_greatsword")
	assert_true(row != null, "the greatsword was not in your own column")
	row.pressed.emit()
	await _tree().process_frame
	assert_eq(bag.count("core:item/iron_greatsword"), 1,
		"a chandler bought a greatsword because the screen never asked")


## DESIGN §5.11: a Vale village turns a Hollow customer away. The merchant has always known;
## the screen never asked, so the shop opened and refused each purchase silently.
func test_a_refused_customer_is_told_so_on_the_page() -> void:
	merchant.stock = {ROPE: 2}
	merchant.place_id = "core:place/merrowby"
	var hollow := GDScript.new()
	hollow.source_code = "extends Node\nfunc reaction_profile() -> Dictionary:\n\treturn {\"renown_tier\": 0, \"morality_tier\": -3, \"title\": \"\"}\n"
	hollow.reload()
	var standing := Node.new()
	standing.set_script(hollow)
	_tree().root.add_child(standing)
	Peers.overrides["standing"] = standing
	# No quiet skip. Wren Tallow keeps shop in Merrowby, which is Vale, and a test that
	# returns early when it cannot provoke the thing it is testing is the same shape of
	# nothing that let nine finished systems ship without ever running.
	assert_true(merchant.refuses_trade(),
		"a Hollow customer was not refused in a Vale village, so this asserts nothing")
	_open()
	await _tree().process_frame
	var told := false
	for label in screen.find_children("*", "Label", true, false):
		if (label as Label).text.contains("will not trade"):
			told = true
	assert_true(told, "the shop opened as normal and refused every purchase without saying why")
	for b in _buttons():
		if b.text != "Done":
			assert_true(b.disabled, "a refused customer was still offered the goods")
	standing.queue_free()
