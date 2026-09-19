extends TestCase

const GENERAL := "core:table/stock_general"
const ROPE := "core:item/rope"
const CANDLE := "core:item/candle"
const KNIFE := "core:item/iron_dagger"

var _nodes: Array[Node] = []


func before_each() -> void:
	Peers.overrides.clear()
	GameState.reset_for_new_game(1)
	WorldClock.set_time(9.0, 2)
	if EconomyService.instance != null:
		EconomyService.instance.saved_state.clear()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


## A buyer with the contracted inventory + marks API.
func _buyer(marks: int) -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar marks := 0\nvar bag := {}\nfunc add_marks(n: int) -> void:\n\tmarks += n\nfunc remove_marks(n: int) -> int:\n\tvar t: int = mini(n, marks)\n\tmarks -= t\n\treturn t\nfunc add(id: String, n: int) -> void:\n\tbag[id] = bag.get(id, 0) + n\nfunc remove(id: String, n: int) -> int:\n\tvar have: int = bag.get(id, 0)\n\tvar t: int = mini(have, n)\n\tbag[id] = have - t\n\treturn t\nfunc count(id: String) -> int:\n\treturn bag.get(id, 0)\nfunc items() -> Array:\n\tvar out: Array = []\n\tfor k in bag:\n\t\tout.append({\"item_id\": k, \"count\": bag[k]})\n\treturn out\n"
	s.reload()
	var n := Node.new()
	n.set_script(s)
	n.set("marks", marks)
	_root().add_child(n)
	_nodes.append(n)
	return n


func _merchant(table := GENERAL, marks := 200, buys: Array[String] = ["all"], on_clock := true) -> Merchant:
	var m := Merchant.new()
	m.npc_id = "core:npc/_test_shop"
	m.stock_table = table
	m.marks = marks
	m.buys = buys
	m.place_id = "core:place/merrowby"
	m.restock_on_clock = on_clock
	_root().add_child(m)
	_nodes.append(m)
	return m


# --- stock tables and restocking -----------------------------------------------------------

func test_stock_tables_are_well_formed() -> void:
	var tables := ContentQuery.where_scalar("table", "role", "merchant_stock")
	assert_eq(tables.size(), 6, "general, smith, alchemist, innkeeper, fishmonger, binder")
	for t in tables:
		assert_gt(t["rows"].size(), 3, "%s is thin" % t["id"])
		for row in t["rows"]:
			assert_has(row, "item")
			assert_true(ContentDB.has(row["item"]), "%s: unknown item %s" % [t["id"], row["item"]])
			assert_has(row, "count")
			assert_eq(row["count"].size(), 2, "%s: %s count is a [min, max]" % [t["id"], row["item"]])
			assert_true(int(row["count"][0]) <= int(row["count"][1]))
			assert_gt(float(row.get("restock_hours", 0)), 0.0, "%s: %s needs restock_hours" % [t["id"], row["item"]])


## Every shelf in the world has to be somebody's: a stock table nobody stands behind is a
## shop that does not exist, which is how the tomes ended up unbuyable.
func test_every_stock_table_has_a_merchant_behind_it() -> void:
	var kept := {}
	for npc in ContentDB.all("npc"):
		var merchant: Dictionary = npc.get("merchant", {})
		if merchant.has("stock"):
			kept[str(merchant["stock"])] = str(npc["id"])
	for t in ContentQuery.where_scalar("table", "role", "merchant_stock"):
		assert_true(kept.has(str(t["id"])), "nobody sells from %s" % t["id"])


func test_initial_stock_within_table_range() -> void:
	var m := _merchant()
	assert_gt(m.items().size(), 5)
	for row in m.table_rows():
		var id: String = row["item"]
		var lo := int(row["count"][0])
		var hi := int(row["count"][1])
		assert_true(m.count(id) >= lo and m.count(id) <= hi, "%s: %d not within [%d, %d]" % [id, m.count(id), lo, hi])
	assert_gt(m.count(CANDLE), 0)


func test_restock_only_when_due_and_never_removes_sold_in_goods() -> void:
	var m := _merchant(GENERAL, 200, ["all"], false)
	m.stock[CANDLE] = 0
	assert_eq(m.restock_all(), 0, "nothing is due yet")
	assert_eq(m.count(CANDLE), 0)
	WorldClock.set_time(9.0, 4)
	var done := m.restock_all()
	assert_gt(done, 0, "a day and a half later the candles are back")
	assert_gt(m.count(CANDLE), 0)
	m.stock[CANDLE] = 999
	WorldClock.set_time(9.0, 10)
	m.restock_all()
	assert_eq(m.count(CANDLE), 999, "restocking tops up; it never confiscates")


func test_restock_runs_on_the_clock() -> void:
	var m := _merchant()
	m.stock[CANDLE] = 0
	m.next_restock[CANDLE] = 0.0
	WorldClock.set_time(10.0, 2)
	assert_gt(m.count(CANDLE), 0, "hour_changed restocks what is due")


func test_stock_is_deterministic_per_merchant() -> void:
	var a := _merchant()
	var b := _merchant()
	assert_eq(a.count(ROPE), b.count(ROPE), "same npc id, same seeded stock")


# --- buying and selling ----------------------------------------------------------------------

func test_buy_moves_goods_and_marks() -> void:
	var m := _merchant()
	m.stock[ROPE] = 4
	var buyer := _buyer(100)
	var events: Array = []
	var cb := func(mid: String, iid: String, c: int, p: int, bought: bool) -> void: events.append([mid, iid, c, p, bought])
	EventBus.transaction.connect(cb)
	var price := m.buy_price_of(ROPE)
	assert_gt(price, 0)
	var r := m.buy(buyer, ROPE, 2)
	assert_true(r["ok"])
	assert_eq(int(r["count"]), 2)
	assert_eq(m.count(ROPE), 2, "two ropes off the shelf")
	assert_eq(buyer.call("count", ROPE), 2)
	assert_eq(int(buyer.get("marks")), 100 - int(r["price"]))
	assert_eq(m.marks, 200 + int(r["price"]))
	assert_eq(events.size(), 1)
	assert_eq(events[0][1], ROPE)
	assert_true(events[0][4], "bought")
	EventBus.transaction.disconnect(cb)


func test_buy_refused_when_poor_or_out_of_stock() -> void:
	var m := _merchant()
	m.stock[KNIFE] = 1
	var pauper := _buyer(2)
	var r := m.buy(pauper, KNIFE, 1)
	assert_false(r["ok"])
	assert_eq(r["reason"], "poor")
	assert_eq(m.count(KNIFE), 1, "nothing changed hands")
	assert_eq(int(pauper.get("marks")), 2)
	var rich := _buyer(9999)
	assert_false(m.buy(rich, KNIFE, 5)["ok"], "he has only the one")
	assert_eq(m.buy(rich, KNIFE, 1)["ok"], true)
	assert_eq(m.count(KNIFE), 0)
	assert_eq(m.buy(rich, KNIFE, 1)["reason"], "out_of_stock")


func test_sell_respects_buys_list_and_merchant_purse() -> void:
	var m := _merchant(GENERAL, 30, ["tool", "material"])
	var seller := _buyer(0)
	seller.call("add", ROPE, 3)
	seller.call("add", "core:item/potion_restore_health", 1)
	assert_false(m.will_buy("core:item/potion_restore_health"), "a general store does not deal in potions")
	var no := m.sell(seller, "core:item/potion_restore_health", 1)
	assert_false(no["ok"])
	assert_eq(no["reason"], "not_bought")
	assert_true(m.will_buy(ROPE))
	var r := m.sell(seller, ROPE, 2)
	assert_true(r["ok"])
	assert_eq(int(r["count"]), 2)
	assert_eq(seller.call("count", ROPE), 1)
	assert_eq(int(seller.get("marks")), int(r["price"]))
	assert_eq(m.marks, 30 - int(r["price"]))
	var m2 := _merchant(GENERAL, 0, ["tool"])
	var seller2 := _buyer(0)
	seller2.call("add", ROPE, 2)
	var poor := m2.sell(seller2, ROPE, 2)
	assert_false(poor["ok"])
	assert_eq(poor["reason"], "merchant_poor")
	assert_eq(seller2.call("count", ROPE), 2, "he keeps his rope")


func test_partial_sale_when_merchant_runs_short() -> void:
	var m := _merchant(GENERAL, 0, ["all"])
	var quote := Pricing.bulk(ContentQuery.item_value(ROPE), m.region_id(), m.count(ROPE), 3, m.effective_disposition(), 0, "sell")
	m.marks = int(quote["unit_prices"][0]) + int(quote["unit_prices"][1])
	var seller := _buyer(0)
	seller.call("add", ROPE, 3)
	var r := m.sell(seller, ROPE, 3)
	assert_true(r["ok"])
	assert_eq(int(r["count"]), 2, "he buys what he can pay for")
	assert_eq(seller.call("count", ROPE), 1)
	assert_eq(m.marks, 0)


func test_prices_follow_standing_speech_and_personality() -> void:
	var m := _merchant(GENERAL, 200, ["all"], false)
	m.stock[KNIFE] = 4
	var base := m.buy_price_of(KNIFE)
	m.personality = Personality.of(["greedy"])
	assert_gt(m.buy_price_of(KNIFE), base, "a greedy shopkeeper")
	m.personality = Personality.of(["generous"])
	assert_gt(base, m.buy_price_of(KNIFE))
	m.personality = null
	_standing_and_skills(3, 0, 60)
	assert_gt(base, m.buy_price_of(KNIFE), "renown and a silver tongue")
	assert_gt(m.sell_price_of(KNIFE), Pricing.sell_price(ContentQuery.item_value(KNIFE), m.region_id(), 4, 0, 0), "and he pays you more")


func _standing_and_skills(renown_tier: int, morality_tier: int, speech: int) -> Array[Node]:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar rt := 0\nvar mt := 0\nfunc reaction_profile() -> Dictionary:\n\treturn {\"renown_tier\": rt, \"morality_tier\": mt, \"title\": \"\"}\n"
	s.reload()
	var standing := Node.new()
	standing.set_script(s)
	standing.set("rt", renown_tier)
	standing.set("mt", morality_tier)
	var p := GDScript.new()
	p.source_code = "extends Node\nvar lvl := 0\nfunc skill_level(id: String) -> int:\n\treturn lvl\n"
	p.reload()
	var prog := Node.new()
	prog.set_script(p)
	prog.set("lvl", speech)
	_nodes.append_array([standing, prog])
	Peers.overrides["standing"] = standing
	Peers.overrides["progression"] = prog
	return [standing, prog]


func test_vale_shopkeepers_refuse_the_deeply_hollow() -> void:
	var m := _merchant()
	m.stock[ROPE] = 4
	assert_false(m.refuses_trade())
	_standing_and_skills(0, -1, 0)
	assert_false(m.refuses_trade(), "a little Hollow is only a higher price")
	assert_gt(m.buy_price_of(ROPE), 0)
	var penalised := m.buy_price_of(ROPE)
	_standing_and_skills(0, 0, 0)
	assert_gt(penalised, m.buy_price_of(ROPE), "the Hollow pay more")
	_standing_and_skills(0, -2, 0)
	assert_true(m.refuses_trade(), "Merrowby is a Vale village")
	var buyer := _buyer(500)
	var r := m.buy(buyer, ROPE, 1)
	assert_false(r["ok"])
	assert_eq(r["reason"], "refused")
	assert_eq(buyer.call("count", ROPE), 0)
	var far := _merchant(GENERAL, 200)
	far.place_id = "core:place/kharrow_hold"
	assert_false(far.refuses_trade(), "the clans will sell to anyone who pays the price")


# --- service, trade requests and saving ---------------------------------------------------------

func test_service_registers_merchants_and_requests_trade() -> void:
	var m := _merchant()
	var svc := EconomyService.ensure()
	assert_true(svc != null)
	assert_true(svc.is_in_group("economy"))
	assert_eq(svc.merchant(m.merchant_id()), m)
	var asked: Array = []
	var cb := func(x: Node) -> void: asked.append(x)
	svc.trade_requested.connect(cb)
	m.open_trade(null)
	assert_eq(asked.size(), 1)
	assert_eq(asked[0], m)
	svc.trade_requested.disconnect(cb)


func test_save_round_trip_keeps_stock_marks_and_disposition() -> void:
	var m := _merchant()
	var buyer := _buyer(500)
	m.stock[ROPE] = 5
	m.buy(buyer, ROPE, 2)
	var rope_left := m.count(ROPE)
	var marks_after := m.marks
	var svc := EconomyService.ensure()
	var data := svc.to_save()
	assert_has(data["merchants"], m.merchant_id())
	var text := JSON.stringify(data)
	m.stock[ROPE] = 0
	m.marks = 0
	svc.from_save(JSON.parse_string(text))
	assert_eq(m.count(ROPE), rope_left)
	assert_eq(m.marks, marks_after)
	assert_eq(m.disposition, 1)


func test_despawned_merchant_keeps_its_stock() -> void:
	var svc := EconomyService.ensure()
	var m := _merchant()
	m.stock[ROPE] = 7
	m.marks = 321
	var id := m.merchant_id()
	_root().remove_child(m)
	m.free()
	_nodes.erase(m)
	assert_has(svc.saved_state, id)
	var again := _merchant()
	assert_eq(again.count(ROPE), 7, "the shop is as he left it")
	assert_eq(again.marks, 321)
