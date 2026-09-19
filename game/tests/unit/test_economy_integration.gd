extends TestCase
## The economy and crime systems against the *real* Inventory and Progression nodes rather
## than test doubles, so the duck-typed seams in Peers and Purse are checked against the
## interfaces they actually meet at runtime.

const ROPE := "core:item/rope"
const CANDLE := "core:item/candle"
const PICK := "core:item/lockpick"

var _nodes: Array[Node] = []
var _player: CharacterBody3D = null
var _bag: Inventory = null
var _progression: Progression = null


func before_each() -> void:
	Peers.overrides.clear()
	GameState.reset_for_new_game(1)
	WorldClock.set_time(11.0, 3)
	_player = CharacterBody3D.new()
	_player.add_to_group("player")
	_root().add_child(_player)
	_nodes.append(_player)
	_bag = Inventory.new()
	_bag.is_player = true
	_player.add_child(_bag)
	_progression = Progression.new()
	_root().add_child(_progression)
	_nodes.append(_progression)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	_player = null
	_bag = null
	_progression = null
	Peers.overrides.clear()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _merchant(table := "core:table/stock_general", marks := 400) -> Merchant:
	var m := Merchant.new()
	m.npc_id = "core:npc/_integration_shop"
	m.stock_table = table
	m.marks = marks
	m.buys = ["all"]
	m.place_id = "core:place/merrowby"
	m.restock_on_clock = false
	_root().add_child(m)
	_nodes.append(m)
	return m


# --- the seams -----------------------------------------------------------------------------

func test_peers_finds_the_real_systems_by_group() -> void:
	assert_eq(Peers.inventory(), _bag, "the player's bag joins the \"inventory\" group")
	assert_eq(Peers.player(), _player)
	assert_eq(Peers.progression(), _progression)
	assert_eq(Peers.inventory_of(_player), _bag, "and is reachable from the player node")


func test_give_and_take_against_the_real_inventory() -> void:
	assert_true(Peers.give_item(_player, ROPE, 2))
	assert_eq(Peers.item_count(_player, ROPE), 2)
	assert_eq(_bag.count(ROPE), 2)
	assert_false(Peers.give_item(_player, "core:item/not_a_thing", 1), "add() returns null for an unknown item, which is not success")
	assert_true(Peers.take_item(_player, ROPE, 1))
	assert_eq(_bag.count(ROPE), 1)
	assert_false(Peers.take_item(_player, ROPE, 5), "you cannot hand over what you do not have")
	assert_eq(_bag.count(ROPE), 1, "and nothing was taken in the attempt")
	assert_true(Peers.give_item(_player, ROPE, 0), "asking for nothing succeeds trivially")
	var listed := Peers.items_of(_player)
	assert_gt(listed.size(), 0)
	assert_eq(str(listed[0]["item_id"]), ROPE)


func test_purse_uses_the_real_marks() -> void:
	_bag.marks = 100
	assert_eq(Purse.balance(_player), 100)
	assert_true(Purse.can_pay(_player, 100))
	assert_false(Purse.can_pay(_player, 101))
	assert_true(Purse.pay(_player, 40))
	assert_eq(_bag.marks, 60)
	assert_false(Purse.pay(_player, 100), "refused, and nothing taken")
	assert_eq(_bag.marks, 60)
	Purse.give(_player, 15)
	assert_eq(_bag.marks, 75)


func test_speech_skill_reaches_pricing() -> void:
	var m := _merchant()
	var dear := "core:item/iron_sword"
	m.stock[dear] = 2
	var before := m.buy_price_of(dear)
	assert_gt(before, 20, "a sword is worth haggling over")
	_progression.award("speech", 20000.0)
	assert_gt(Peers.skill_level("speech"), 20, "the progression node answers skill_level")
	assert_gt(before, m.buy_price_of(dear), "a practised tongue pays less")


# --- a whole trade --------------------------------------------------------------------------

func test_buying_and_selling_move_real_goods_and_marks() -> void:
	var m := _merchant()
	_bag.marks = 300
	m.stock[ROPE] = 5
	var r := m.buy(_player, ROPE, 2)
	assert_true(r["ok"], "reason: %s" % str(r["reason"]))
	assert_eq(_bag.count(ROPE), 2, "the rope is really in the bag")
	assert_eq(_bag.marks, 300 - int(r["price"]))
	assert_eq(m.count(ROPE), 3)
	var sold := m.sell(_player, ROPE, 1)
	assert_true(sold["ok"])
	assert_eq(_bag.count(ROPE), 1)
	assert_eq(_bag.marks, 300 - int(r["price"]) + int(sold["price"]))
	assert_eq(m.count(ROPE), 4, "and back on his shelf")
	assert_true(_bag.weight() > 0.0, "the inventory weighs what it holds")


func test_a_pauper_cannot_buy_and_the_bag_is_untouched() -> void:
	var m := _merchant()
	_bag.marks = 1
	m.stock[CANDLE] = 5
	var r := m.buy(_player, CANDLE, 5)
	assert_false(r["ok"])
	assert_eq(r["reason"], "poor")
	assert_eq(_bag.count(CANDLE), 0)
	assert_eq(_bag.marks, 1)
	assert_eq(m.count(CANDLE), 5)


# --- property and locks --------------------------------------------------------------------------

func test_buying_a_house_with_the_real_bag() -> void:
	var reg := PropertyRegistry.ensure()
	reg.owned.clear()
	_bag.marks = 5000
	var deed := "core:item/deed_merrowby_crater_cottage"
	var r := reg.buy(_player, deed)
	assert_true(r["ok"])
	assert_eq(_bag.marks, 5000 - int(r["price"]))
	assert_eq(_bag.count(deed), 1, "the deed is a real item in the bag")
	assert_eq(_bag.count(PropertyRegistry.key_item_of(deed)), 1, "and so is the key")
	assert_true(reg.is_owned(deed))
	reg.owned.clear()


func test_the_canonical_lockpick_is_found_by_tag() -> void:
	var lock := DoorLock.new()
	lock.lock_level = 1
	var door := StaticBody3D.new()
	door.add_child(lock)
	_root().add_child(door)
	_nodes.append(door)
	assert_eq(lock.lockpick_item_id(), PICK, "DoorLock finds a pick by tag, not by a hard-coded id")
	assert_false(lock.has_pick(_player))
	_bag.add(PICK, 1)
	assert_true(lock.has_pick(_player), "and reads the real bag")
	assert_eq(lock.interact(_player)["state"], "locked", "with a pick in hand the minigame starts")


func test_a_job_pays_into_the_real_purse() -> void:
	var station := JobStation.new()
	station.kind = "chop"
	_root().add_child(station)
	_nodes.append(station)
	assert_true(station.interact(_player))
	var pay := station.finish(_player)
	assert_gt(pay, 0)
	assert_eq(_bag.marks, pay)
	assert_eq(_bag.count("core:item/oak_plank"), 1, "and the plank is in the bag")
	assert_gt(Peers.skill_level("athletics"), -1, "the shift fed skill_used into progression")


func test_pickpocketing_a_real_bag() -> void:
	var st := Stealth.ensure()
	var b := Bounty.ensure()
	b.clear_all()
	var victim := Node3D.new()
	victim.set_name("Mark")
	_root().add_child(victim)
	_nodes.append(victim)
	victim.global_position = Vector3(900, 40, 2350)
	var their_bag := Inventory.new()
	victim.add_child(their_bag)
	their_bag.add(ROPE, 1)
	assert_false(their_bag.is_in_group("inventory"), "only the player's bag joins the group")
	assert_eq(Peers.inventory_of(victim), their_bag, "an NPC's own bag, not the player's")
	assert_eq(Peers.inventory_of(Node3D.new()), null, "and an NPC with no bag has nothing to steal")
	var chance := Stealth.pickpocket_chance(Peers.skill_level("sneak"), 1.0, 6)
	assert_true(chance > 0.0)
	var r := st.pickpocket(_player, victim, ROPE, _rng_rolling(chance, true))
	assert_true(r["ok"])
	assert_eq(their_bag.count(ROPE), 0, "taken from their bag")
	assert_eq(_bag.count(ROPE), 1, "and into yours")
	assert_eq(b.history.back()["kind"], "pickpocket")
	b.clear_all()


func _rng_rolling(chance: float, succeed: bool) -> RandomNumberGenerator:
	for s in range(1, 2000):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		if (probe.randf() < chance) == succeed:
			var rng := RandomNumberGenerator.new()
			rng.seed = s
			return rng
	fail("no seed rolls that way against %f" % chance)
	return RandomNumberGenerator.new()
