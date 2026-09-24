extends TestCase
## Reaching a shop. An NPC with a `merchant` block carries a stock table, a float of marks and
## a price list, and nothing in the game ever opened the trade screen — so every shopkeeper in
## Wickmere was somebody you could talk to and not buy from. The way in is a choice offered at
## any hub, like the talk of the place, so a merchant is reachable whether or not whoever
## wrote their dialogue remembered the topic.

var runner: Node
var ctx: SocialContext
var shown: Array[Dictionary] = []
var asked: Array[String] = []


func before_each() -> void:
	ctx = SocialFakes.context()
	runner = preload("res://systems/dialogue/dialogue_runner.gd").new()
	runner.ctx = ctx
	Engine.get_main_loop().root.add_child(runner)
	shown = []
	asked = []
	runner.line_shown.connect(func(_s: String, text: String, choices: Array) -> void:
		shown.append({"text": text, "choices": choices}))
	EventBus.trade_requested.connect(_note_trade)


func after_each() -> void:
	if EventBus.trade_requested.is_connected(_note_trade):
		EventBus.trade_requested.disconnect(_note_trade)
	if is_instance_valid(runner):
		runner.queue_free()
	Greetings.forget()


func _note_trade(npc_id: String) -> void:
	asked.append(npc_id)


func _graph(extra: Dictionary = {}) -> Dictionary:
	var hub := {"speaker": "Keeper", "text": "Yes?", "choices": [
		{"text": "About the weather.", "next": "weather"},
		{"text": "Nothing.", "next": "end"},
	]}
	hub.merge(extra, true)
	return {"id": "test:dialogue/shop", "start": "hub", "nodes": {
		"hub": hub,
		"weather": {"speaker": "Keeper", "text": "It is what it is.", "next": "hub"},
	}}


func _choice_texts() -> Array[String]:
	var out: Array[String] = []
	for c in shown[-1]["choices"]:
		out.append(str((c as Dictionary).get("text", "")))
	return out


const A_SHOPKEEPER := "core:npc/maud_brambling"       # kind; keeps the general stock
const A_SOUR_ONE := "core:npc/sorrel_lathe"           # cynical; sells crossbows under charter
const NOT_A_SHOPKEEPER := "core:npc/ellard_wynstead"  # the steward sells nothing


## The runner reads the NPC out of the content pack when a conversation begins, so a fixture
## NPC invented in the test has no merchant block by the time the choices are built. These use
## people who actually keep shops.
func _open(who: String, extra: Dictionary = {}) -> void:
	assert_true(ContentDB.has(who), "%s is not in the pack any more" % who)
	runner.start_def(_graph(extra), who)


# --- the way in -------------------------------------------------------------------------------

func test_a_shopkeeper_offers_their_stock() -> void:
	_open(A_SHOPKEEPER)
	assert_true(_choice_texts().has(runner.TRADE_CHOICE),
			"a merchant's hub offered %s" % str(_choice_texts()))


func test_somebody_who_keeps_no_shop_does_not() -> void:
	_open(NOT_A_SHOPKEEPER)
	assert_false(_choice_texts().has(runner.TRADE_CHOICE),
			"a villager with no stock offered to sell you something")


func test_a_node_can_turn_the_shop_down() -> void:
	# A tense scene should not be interrupted by "let me see what you have".
	_open(A_SHOPKEEPER, {"no_trade": true})
	assert_false(_choice_texts().has(runner.TRADE_CHOICE), "no_trade was ignored")


func test_asking_opens_the_shop_and_the_conversation_carries_on() -> void:
	_open(A_SHOPKEEPER)
	var index := _choice_texts().find(runner.TRADE_CHOICE)
	assert_gt(index, -1, "there was nothing to press")
	runner.choose(index)
	assert_eq(asked, [A_SHOPKEEPER] as Array[String], "nobody was asked for their stock")
	assert_true(runner.is_running(), "the shop ended the conversation")
	assert_false(str(shown[-1]["text"]).is_empty(), "the keeper said nothing while opening up")
	close_screen("trade", "asking to see the stock opens the shop")


func test_the_keeper_says_it_in_their_own_voice() -> void:
	_open(A_SOUR_ONE)
	runner.choose(_choice_texts().find(runner.TRADE_CHOICE))
	var sour := str(shown[-1]["text"])
	shown = []
	asked = []
	_open(A_SHOPKEEPER)
	runner.choose(_choice_texts().find(runner.TRADE_CHOICE))
	assert_ne(sour, str(shown[-1]["text"]), "a sour keeper and a kind one open up the same way")
	close_screen("trade", "both keepers open the shop")


# --- the shop exists to be opened ---------------------------------------------------------------

func test_the_ui_opens_a_trade_screen_when_asked() -> void:
	assert_true(UI.MENUS.has("trade"), "there is no trade screen to open")
	assert_true(EventBus.trade_requested.get_connections().size() > 0,
			"nothing is listening for somebody asking to see the stock")


func test_every_merchant_in_the_pack_names_a_stock_table_that_exists() -> void:
	var keepers := 0
	for npc in ContentDB.all("npc"):
		var m: Variant = (npc as Dictionary).get("merchant", null)
		if typeof(m) != TYPE_DICTIONARY:
			continue
		keepers += 1
		var table := str((m as Dictionary).get("stock", ""))
		assert_true(table == "" or ContentDB.has(table),
				"%s sells from a table that does not exist: %s" % [npc.get("id", "?"), table])
	assert_gt(keepers, 0, "nobody in the world keeps a shop")


# --- the steward's deeds ------------------------------------------------------------------------

func _deed_texts() -> Array[String]:
	var out: Array[String] = []
	for t in _choice_texts():
		if t.begins_with("The deed to"):
			out.append(t)
	return out


## Merrowby's steward `sells_deeds`: he keeps no shop, and he holds the town's deeds, and the key
## was written on him and read by nothing -- he told you where the deeds were kept and could not
## hand you one. Each deed still for sale is at his hub now, and taking one opens the deed screen.
func test_the_steward_offers_the_deeds_of_his_place() -> void:
	_open(NOT_A_SHOPKEEPER)
	var deeds := _deed_texts()
	assert_eq(deeds.size(), PropertyRegistry.deeds_at("core:place/merrowby").size(),
			"the steward offered %s" % [deeds])
	var offered: Array = []
	var cb := func(id: String, price: int) -> void: offered.append([id, price])
	EventBus.property_offered.connect(cb)
	runner.choose(_choice_texts().find(deeds[0]))
	EventBus.property_offered.disconnect(cb)
	assert_eq(offered.size(), 1, "taking a deed down opened nothing")
	assert_true(str(offered[0][0]).begins_with("core:item/deed_merrowby"), "the steward offered %s" % str(offered[0][0]))
	assert_true(runner.is_running(), "taking a deed down ended the conversation")
	close_screen("deed", "the deed screen opens on the steward's deed")


func test_a_shopkeeper_holds_no_deeds() -> void:
	_open(A_SHOPKEEPER)
	assert_empty(_deed_texts(), "a baker offered to sell a house")
