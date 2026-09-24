extends TestCase

const COTTAGE := "core:item/deed_merrowby_crater_cottage"
const BELLROW := "core:item/deed_merrowby_bellrow_house"
const STILT := "core:item/deed_isseva_stilt_house"

var _nodes: Array[Node] = []


func before_each() -> void:
	Peers.overrides.clear()
	GameState.reset_for_new_game(1)
	WorldClock.set_time(9.0, 10)
	var reg := PropertyRegistry.ensure()
	if reg != null:
		reg.owned.clear()
	if Ownership.instance != null:
		Ownership.instance.registry.clear()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()
	var reg := PropertyRegistry.ensure()
	if reg != null:
		reg.owned.clear()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _buyer(marks: int) -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar marks := 0\nvar bag := {}\nfunc add_marks(n: int) -> void:\n\tmarks += n\nfunc remove_marks(n: int) -> int:\n\tvar t: int = mini(n, marks)\n\tmarks -= t\n\treturn t\nfunc add(id: String, n: int) -> void:\n\tbag[id] = bag.get(id, 0) + n\nfunc remove(id: String, n: int) -> int:\n\tvar have: int = bag.get(id, 0)\n\tvar t: int = mini(have, n)\n\tbag[id] = have - t\n\treturn t\nfunc count(id: String) -> int:\n\treturn bag.get(id, 0)\n"
	s.reload()
	var n := Node.new()
	n.set_script(s)
	n.set("marks", marks)
	_root().add_child(n)
	_nodes.append(n)
	return n


# --- content ------------------------------------------------------------------------------

func test_deed_content_is_complete() -> void:
	var deeds := PropertyRegistry.all_deeds()
	assert_eq(deeds.size(), 6, "Merrowby 2, Tollmere 1, Isseva 1, Kharrow 1, Grandfather Hollow 1")
	var by_place := {}
	for d in deeds:
		var b: Dictionary = d["property"]
		for key in ["place", "interior", "name", "price", "key", "storage", "bed"]:
			assert_has(b, key, "%s missing property.%s" % [d["id"], key])
		assert_true(ContentDB.has(b["place"]), "%s: unknown place" % d["id"])
		assert_true(ContentDB.has(b["key"]), "%s: key item missing" % d["id"])
		assert_false(ContentDB.has(b["interior"]), "%s: an interior id is a plain string until real interiors land, never a place" % d["id"])
		assert_gt(int(b["price"]), 0)
		assert_gt(PropertyRegistry.rent_per_day(d["id"]), 0)
		by_place[b["place"]] = int(by_place.get(b["place"], 0)) + 1
	assert_eq(int(by_place["core:place/merrowby"]), 2)
	assert_eq(int(by_place["core:place/tollmere"]), 1)
	assert_eq(int(by_place["core:place/isseva"]), 1)
	assert_eq(int(by_place["core:place/kharrow_hold"]), 1)
	assert_eq(int(by_place["core:place/grandfather_hollow"]), 1)
	assert_eq(PropertyRegistry.deeds_at("core:place/merrowby").size(), 2)
	# Two houses in one village must not share a door, a chest or a bed.
	var ids := {}
	for d in deeds:
		for f in [PropertyRegistry.interior_of(d["id"]), PropertyRegistry.door_id_of(d["id"]), PropertyRegistry.storage_id_of(d["id"]), PropertyRegistry.bed_id_of(d["id"])]:
			assert_false(ids.has(f), "%s shares %s with %s" % [d["id"], f, ids.get(f, "")])
			ids[f] = d["id"]


func test_buying_a_house_does_not_claim_the_village() -> void:
	var reg := PropertyRegistry.ensure()
	var buyer := _buyer(9000)
	assert_true(reg.buy(buyer, COTTAGE)["ok"])
	assert_false(Ownership.instance.is_player_owned("core:place/merrowby"), "a cottage is not the whole town")
	assert_false(Ownership.instance.is_player_owned(PropertyRegistry.door_id_of(BELLROW)), "nor the neighbour's door")
	assert_false(reg.owns_bed(PropertyRegistry.bed_id_of(BELLROW)))
	assert_true(Ownership.instance.is_player_owned(PropertyRegistry.door_id_of(COTTAGE)))


func test_accessors() -> void:
	assert_eq(PropertyRegistry.place_of(COTTAGE), "core:place/merrowby")
	assert_eq(PropertyRegistry.display_name(COTTAGE), "the Crater Cottage")
	assert_eq(PropertyRegistry.price_of(COTTAGE), 1400)
	assert_eq(PropertyRegistry.key_item_of(COTTAGE), "core:item/econ_key_crater_cottage")
	assert_eq(PropertyRegistry.rent_per_day(COTTAGE), 6)
	assert_true(PropertyRegistry.storage_id_of(COTTAGE).contains("chest"))
	assert_true(PropertyRegistry.door_id_of(COTTAGE).ends_with("#door"))


# --- buying ---------------------------------------------------------------------------------

func test_buying_takes_marks_and_grants_key_and_ownership() -> void:
	var reg := PropertyRegistry.ensure()
	var buyer := _buyer(2000)
	var bought: Array = []
	var cb := func(id: String) -> void: bought.append(id)
	EventBus.property_purchased.connect(cb)
	var price := reg.asking_price(COTTAGE)
	assert_eq(price, 1400, "no standing, no Speech: the asking price")
	var r := reg.buy(buyer, COTTAGE)
	assert_true(r["ok"])
	assert_eq(int(r["price"]), 1400)
	assert_eq(int(buyer.get("marks")), 600)
	assert_true(reg.is_owned(COTTAGE))
	assert_eq(buyer.call("count", COTTAGE), 1, "the deed itself")
	assert_eq(buyer.call("count", "core:item/econ_key_crater_cottage"), 1, "and its key")
	assert_true(GameState.has_flag("owns_deed_merrowby_crater_cottage"))
	assert_eq(GameState.count("properties_owned"), 1)
	assert_eq(bought, [COTTAGE])
	assert_true(reg.owns_property_at("core:place/merrowby"))
	assert_false(reg.owns_property_at("core:place/tollmere"))
	# The interior, its door, its chest and its bed are now the player's.
	assert_false(Ownership.is_owned_by_other(PropertyRegistry.storage_id_of(COTTAGE)))
	assert_false(Ownership.is_owned_by_other(PropertyRegistry.bed_id_of(COTTAGE)))
	assert_true(Ownership.instance.is_player_owned(PropertyRegistry.door_id_of(COTTAGE)))
	assert_true(reg.owns_bed(PropertyRegistry.bed_id_of(COTTAGE)))
	assert_false(reg.owns_bed("core:place/merrowby#inn_bed_2"), "the inn's beds are still the inn's")
	assert_eq(reg.storage_ids(), [PropertyRegistry.storage_id_of(COTTAGE)])
	EventBus.property_purchased.disconnect(cb)


func test_buying_refused_when_poor_unknown_or_already_owned() -> void:
	var reg := PropertyRegistry.ensure()
	var pauper := _buyer(10)
	var r := reg.buy(pauper, BELLROW)
	assert_false(r["ok"])
	assert_eq(r["reason"], "poor")
	assert_eq(int(pauper.get("marks")), 10)
	assert_false(reg.is_owned(BELLROW))
	assert_eq(reg.buy(pauper, "core:item/rope")["reason"], "unknown", "not every item is a house")
	assert_eq(reg.buy(pauper, "core:item/nope")["reason"], "unknown")
	var rich := _buyer(99999)
	assert_true(reg.buy(rich, BELLROW)["ok"])
	assert_eq(reg.buy(rich, BELLROW)["reason"], "already_owned")


func test_asking_price_moves_with_standing_but_has_a_floor() -> void:
	var reg := PropertyRegistry.ensure()
	var s := GDScript.new()
	s.source_code = "extends Node\nfunc reaction_profile() -> Dictionary:\n\treturn {\"renown_tier\": 4, \"morality_tier\": 3, \"title\": \"\"}\n"
	s.reload()
	var standing := Node.new()
	standing.set_script(s)
	_nodes.append(standing)
	Peers.overrides["standing"] = standing
	var p := GDScript.new()
	p.source_code = "extends Node\nfunc skill_level(id: String) -> int:\n\treturn 100\n"
	p.reload()
	var prog := Node.new()
	prog.set_script(p)
	_nodes.append(prog)
	Peers.overrides["progression"] = prog
	var haggled := reg.asking_price(COTTAGE)
	assert_true(haggled < 1400, "a famous, kindly, silver-tongued buyer pays less")
	assert_true(haggled >= roundi(1400 * PropertyRegistry.PRICE_FLOOR), "but never below three-quarters")
	# A rank-holder in the selling faction reaches the floor and stops there.
	var f := GDScript.new()
	f.source_code = "extends Node\nfunc rank(id: String) -> int:\n\treturn 10\nfunc is_member(id: String) -> bool:\n\treturn true\n"
	f.reload()
	var factions := Node.new()
	factions.set_script(f)
	_nodes.append(factions)
	Peers.overrides["factions"] = factions
	assert_eq(reg.asking_price(COTTAGE, "core:faction/wardens"), roundi(1400 * PropertyRegistry.PRICE_FLOOR), "the floor holds")


# --- letting and rent ---------------------------------------------------------------------------

func test_rent_accrues_per_day_only_when_let() -> void:
	var reg := PropertyRegistry.ensure()
	var owner := _buyer(5000)
	reg.buy(owner, COTTAGE)
	assert_eq(reg.rent_due(COTTAGE), 0)
	WorldClock.set_time(9.0, 15)
	assert_eq(reg.rent_due(COTTAGE), 0, "an empty house pays nothing")
	assert_true(reg.set_let(COTTAGE, true))
	assert_true(reg.is_let(COTTAGE))
	assert_eq(reg.rent_due(COTTAGE), 0, "letting starts the clock now")
	WorldClock.set_time(9.0, 18)
	assert_eq(reg.rent_due(COTTAGE), 18, "three days at six marks")
	assert_eq(reg.total_rent_due(), 18)
	var marks_before := int(owner.get("marks"))
	var collected := reg.collect_rent(owner)
	assert_eq(collected, 18)
	assert_eq(int(owner.get("marks")), marks_before + 18)
	assert_eq(reg.rent_due(COTTAGE), 0, "collected rent is not owed twice")
	WorldClock.set_time(9.0, 20)
	assert_eq(reg.rent_due(COTTAGE), 12)
	reg.set_let(COTTAGE, false)
	assert_eq(reg.rent_due(COTTAGE), 0)
	assert_false(reg.set_let("core:item/deed_nothing", true))


func test_furnishings() -> void:
	var reg := PropertyRegistry.ensure()
	var owner := _buyer(5000)
	reg.buy(owner, COTTAGE)
	assert_true(reg.add_furnishing(COTTAGE, "core:item/candle"))
	assert_false(reg.add_furnishing(COTTAGE, "core:item/candle"), "already there")
	assert_eq(reg.furnishings(COTTAGE), ["core:item/candle"])
	assert_false(reg.add_furnishing(STILT, "core:item/rope"), "you do not own the stilt house")


# --- signs ----------------------------------------------------------------------------------------

func test_property_sign_offers_and_sells() -> void:
	var reg := PropertyRegistry.ensure()
	var sign_node: PropertySign = load("res://systems/economy/property_sign.tscn").instantiate()
	sign_node.property_id = STILT
	_root().add_child(sign_node)
	_nodes.append(sign_node)
	assert_true(sign_node.is_in_group("interactable"))
	assert_eq(sign_node.price(), 2100)
	assert_eq(sign_node.prompt_text(), "Buy the Stilt House (2100 marks)")
	var offers: Array = []
	sign_node.offer_made.connect(func(id: String, p: int) -> void: offers.append([id, p]))
	var buyer := _buyer(2500)
	sign_node.interact(buyer)
	assert_eq(offers.size(), 1, "the board quotes a price and waits")
	assert_false(reg.is_owned(STILT))
	var r := sign_node.accept(buyer)
	assert_true(r["ok"])
	assert_true(reg.is_owned(STILT))
	assert_eq(int(buyer.get("marks")), 400)
	# Once it is yours the board stops being a shop and becomes a landlord's business.
	assert_true(sign_node.prompt_text().begins_with("Let the Stilt House"),
			"got '%s'" % sign_node.prompt_text())
	var steward_sign: PropertySign = load("res://systems/economy/property_sign.tscn").instantiate()
	steward_sign.property_id = COTTAGE
	steward_sign.steward_npc = "core:npc/example_reeve"
	_root().add_child(steward_sign)
	_nodes.append(steward_sign)
	var talks: Array = []
	var cb := func(id: String) -> void: talks.append(id)
	EventBus.dialogue_started.connect(cb)
	steward_sign.interact(buyer)
	assert_eq(talks, ["core:npc/example_reeve"], "a steward is spoken to, not haggled with at a board")
	assert_true(bool(Social.dialogue.call("is_running")), "in a conversation that has actually begun")
	EventBus.dialogue_started.disconnect(cb)
	Social.dialogue.call("stop")
	close_screen("deed", "the board's quote is drawn on the deed screen")


# --- save --------------------------------------------------------------------------------------------

func test_save_round_trip_restores_ownership() -> void:
	var reg := PropertyRegistry.ensure()
	var owner := _buyer(9000)
	reg.buy(owner, COTTAGE)
	reg.set_let(COTTAGE, true)
	reg.add_furnishing(COTTAGE, "core:item/torch")
	WorldClock.set_time(9.0, 12)
	var data := reg.to_save()
	var text := JSON.stringify(data)
	reg.owned.clear()
	Ownership.instance.registry.clear()
	assert_false(reg.is_owned(COTTAGE))
	reg.from_save(JSON.parse_string(text))
	assert_true(reg.is_owned(COTTAGE))
	assert_true(reg.is_let(COTTAGE))
	assert_eq(reg.furnishings(COTTAGE), ["core:item/torch"])
	assert_eq(reg.rent_due(COTTAGE), 12, "two days at six marks survived the save")
	assert_true(Ownership.instance.is_player_owned(PropertyRegistry.storage_id_of(COTTAGE)), "the chest is still yours")
	assert_true(reg.owns_bed(PropertyRegistry.bed_id_of(COTTAGE)))


# --- the board outside a house you own -----------------------------------------------------------

func _own_sign(property_id: String) -> PropertySign:
	var reg := PropertyRegistry.ensure()
	reg.grant(property_id)
	var sign := PropertySign.new()
	sign.property_id = property_id
	_root().add_child(sign)
	_nodes.append(sign)
	return sign


## The board outside a house you own opens the landlord's side of the deed screen, where
## letting, rent and furnishings are each their own button. It used to act on the registry
## silently, and which of the three things one press did depended on state the board never
## showed. `test_deed_screen.gd` presses those buttons; this asserts the board reaches them.
func test_your_own_board_opens_the_landlords_side() -> void:
	var sign := _own_sign(COTTAGE)
	assert_true(sign.prompt_text().begins_with("Let "), "got '%s'" % sign.prompt_text())
	var offered: Array[String] = []
	var note := func(id: String, _price: int) -> void: offered.append(id)
	EventBus.property_offered.connect(note)
	sign.interact(null)
	EventBus.property_offered.disconnect(note)
	assert_eq(offered, [COTTAGE] as Array[String],
		"standing at your own board told the UI nothing, so nothing was drawn")
	assert_true(UI.MENUS.has("deed"), "no screen is registered to answer it")
	close_screen("deed", "your own board opens the landlord's side")


func test_your_own_board_says_what_is_waiting_before_you_walk_up_to_it() -> void:
	var reg := PropertyRegistry.ensure()
	var sign := _own_sign(COTTAGE)
	assert_true(sign.prompt_text().begins_with("Let "), "got '%s'" % sign.prompt_text())
	reg.set_let(COTTAGE, true)
	assert_true(sign.prompt_text().contains("(let"), "got '%s'" % sign.prompt_text())
	WorldClock.set_time(9.0, 14)              # four days pass
	assert_gt(reg.rent_due(COTTAGE), 0, "no rent accrued over four days")
	assert_true(sign.prompt_text().begins_with("Collect "), "got '%s'" % sign.prompt_text())


func test_a_board_for_a_house_you_do_not_own_still_sells_it() -> void:
	var sign := PropertySign.new()
	sign.property_id = BELLROW
	_root().add_child(sign)
	_nodes.append(sign)
	assert_true(sign.prompt_text().begins_with("Buy "), "got '%s'" % sign.prompt_text())


## A deed says what the house is -- its rooms, its beds, a line of its history -- and the deed
## screen reads it out under the name. The deeds carried all three and the screen showed a name
## and a price.
func test_a_deed_describes_its_house() -> void:
	var line := PropertyRegistry.describe("core:item/deed_merrowby_bellrow_house")
	assert_true(line.begins_with("Four rooms, two beds."), line)
	assert_true(line.contains("bronze"), "the deed's history was left off: %s" % line)
	for d in PropertyRegistry.all_deeds():
		var b: Dictionary = d["property"]
		if b.has("beds"):
			assert_true(PropertyRegistry.describe(str(d["id"])).contains(" bed"), "%s: its beds went unread" % d["id"])
