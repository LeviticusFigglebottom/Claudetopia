extends TestCase
## Picking a pocket in play (triage 25, Pickpocketing): crouched at somebody unaware of you the
## interact key offers their pocket instead of a word; the screen lists what they carry with each
## thing's chance; a lift rolls, moves the goods and tells the lesson; a fumble is a crime the mark
## witnesses, a reaction, and a mark who is wary of you after. The rogue's lesson counts it.

const BRAM := "core:npc/example_thatcher_bram"
const NELL := "core:npc/example_grocer_nell"
const COLLECTOR := "core:npc/tithe_collector"
const KEY := "core:item/tithe_collector_key"
const FIRST := "core:quest/first_rogue"
const PLAYER := preload("res://actors/player/player.tscn")

var _nodes: Array[Node] = []


func before_each() -> void:
	Peers.overrides.clear()
	GameState.reset_for_new_game(71)
	WorldClock.set_time(2.0, 2)
	Pickpocketing.store.clear()
	var ledger := Bounty.ensure()
	if ledger != null:
		ledger.clear_all()
	var reg := NpcRegistry.instance
	if reg != null:
		reg.despawn_all()
		reg.states.clear()
		reg.abstract_only = true
		reg.rebuild()


func after_each() -> void:
	UI.close_all()
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()
	Pickpocketing.store.clear()
	var ledger := Bounty.ensure()
	if ledger != null:
		ledger.clear_all()
	Social.quests.call("reset_for_new_game")
	# the registry stood back as the game has it, or every test file after this one that stands
	# people up finds nobody (test_poi_people, test_settlement_people: triage 38)
	if NpcRegistry.instance != null:
		NpcRegistry.instance.despawn_all()
		NpcRegistry.instance.abstract_only = false


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _player() -> Player:
	var p := PLAYER.instantiate() as Player
	_root().add_child(p)
	_nodes.append(p)
	p.global_position = at_place("core:place/merrowby", 40.0) + Vector3(0, 0, 1.2)
	Peers.overrides["player"] = p
	return p


func _npc(id: String) -> Npc:
	var n: Npc = load("res://actors/npc/npc.tscn").instantiate()
	n.npc_id = id
	_root().add_child(n)
	_nodes.append(n)
	n.global_position = at_place("core:place/merrowby", 40.0)
	n.set_physics_process(false)   # its meter is the test's to set
	n.detection = 0.0
	return n


## An RNG whose first randf() is below `chance` (succeed) or at/above it (fail).
func _rng_rolling(chance: float, succeed: bool) -> RandomNumberGenerator:
	for s in range(1, 4000):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		if (probe.randf() < chance) == succeed:
			var rng := RandomNumberGenerator.new()
			rng.seed = s
			return rng
	fail("no seed rolls %s against %f" % ["below" if succeed else "above", chance])
	return RandomNumberGenerator.new()


func test_the_offer_needs_a_crouch_and_somebody_unaware() -> void:
	var me := _player()
	var bram := _npc(BRAM)
	me.is_sneaking = false
	assert_eq(bram.prompt_text(), "Talk to Bram Thatchen", "standing up, a word")
	me.is_sneaking = true
	assert_eq(bram.prompt_text(), "Pick Bram Thatchen's pocket", "crouched at a man who has not seen you, his pocket")
	bram.detection = DetectionMeter.SUSPICIOUS + 0.05
	assert_eq(bram.prompt_text(), "Talk to Bram Thatchen", "he has noticed you: no")
	bram.detection = 0.0
	bram.hostile = true
	assert_false(Pickpocketing.can_offer(bram, me), "nor somebody fighting you")
	bram.hostile = false
	var nell := _npc(NELL)
	assert_eq(nell.prompt_text(), "Pick Nell Cresswell's pocket", "a trader's too, instead of her trade")
	me.is_sneaking = false
	assert_eq(nell.prompt_text(), "Trade with Nell Cresswell")
	assert_false(Pickpocketing.can_offer(bram, bram), "only the player's hand")


func test_crouched_the_interact_key_asks_for_the_screen_not_a_talk() -> void:
	var me := _player()
	var bram := _npc(BRAM)
	me.is_sneaking = true
	var asked: Array = []
	var on_ask := func(mark: Node, actor: Node) -> void:
		asked.append([mark, actor])
	EventBus.pickpocket_requested.connect(on_ask)
	bram.interact(me)
	EventBus.pickpocket_requested.disconnect(on_ask)
	assert_eq(asked.size(), 1, "the pickpocket screen is asked for")
	assert_false(bool(Social.dialogue.call("is_running")), "and nobody is talking")
	assert_true(UI.is_menu_open("pickpocket"), "the UI opens it")
	var screen := UI.menu_node("pickpocket")
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(screen.get("mark"), bram)
	UI.close_all()


func test_a_sleeper_is_all_but_unaware() -> void:
	var me := _player()
	me.is_sneaking = true
	var tole := _npc(COLLECTOR)
	var awake_chance := Pickpocketing.chance_for(tole, me, KEY)
	tole.detection = 0.6
	assert_false(Pickpocketing.can_offer(tole, me), "awake and looking at you")
	tole.play_intent("Sleep_Idle")
	assert_true(Pickpocketing.is_asleep(tole))
	assert_near(Pickpocketing.awareness(tole), 0.6 * Pickpocketing.ASLEEP_FACTOR, 0.001)
	assert_true(Pickpocketing.can_offer(tole, me), "asleep, his eyes are shut whatever the meter says")
	tole.detection = 0.0
	assert_near(Pickpocketing.chance_for(tole, me, KEY), minf(awake_chance + Pickpocketing.ASLEEP_BONUS, 0.95), 0.0001, "and his pocket is open to the hand")
	tole.detection = 0.6
	tole.detection = 1.0
	assert_false(Pickpocketing.can_offer(tole, me), "woken")


func test_the_pockets_and_their_chances() -> void:
	var me := _player()
	var tole := _npc(COLLECTOR)
	var rows := Pickpocketing.contents(tole, me)
	assert_eq(rows.size(), 2, "his purse and his key: %s" % str(rows))
	assert_eq(str(rows[0]["id"]), Stealth.PURSE, "the purse first")
	assert_eq(int(rows[0]["value"]), 18)
	assert_eq(str(rows[1]["id"]), KEY)
	var key_chance := float(rows[1]["chance"])
	assert_near(key_chance, Stealth.pickpocket_chance(Peers.skill_level("sneak"), 0.0, 12, 0.0, 0.05), 0.0001, "Stealth's rule")
	assert_gt(Stealth.pickpocket_chance(20, 0.0, 12, 0.0, 0.05), Stealth.pickpocket_chance(20, 0.0, 12, 0.0, 2.0), "heavier is harder")
	assert_gt(Stealth.pickpocket_chance(20, 0.0, 12), Stealth.pickpocket_chance(20, 0.0, 120), "dearer is harder")
	assert_gt(key_chance, Pickpocketing.chance_for(tole, me, KEY, 2), "and each thing already lifted makes the next harder")
	var bram := _npc(BRAM)
	var first := Pickpocketing.pockets(bram).to_save()
	bram.get_node(Pickpocketing.POCKETS_NODE).free()
	assert_eq(Pickpocketing.pockets(bram).to_save(), first, "a pocket is filled once and kept")


func test_a_lift_moves_the_thing_and_tells_the_lesson() -> void:
	var me := _player()
	var tole := _npc(COLLECTOR)
	var bag := me.get_node("Inventory") as Inventory
	var acts: Array = []
	var on_act := func(act: String, _by: Node, on: Node, detail: String) -> void:
		acts.append([act, on, detail])
	EventBus.act_done.connect(on_act)
	var chance := Pickpocketing.chance_for(tole, me, KEY)
	var r := Pickpocketing.attempt(tole, me, KEY, _rng_rolling(chance, true))
	EventBus.act_done.disconnect(on_act)
	assert_true(bool(r["ok"]), "lifted")
	assert_eq(bag.count(KEY), 1, "the key in your bag")
	assert_eq(Pickpocketing.pockets(tole).count(KEY), 0, "and not in his pocket")
	assert_true(acts.size() == 1 and acts[0][0] == "pickpocket" and acts[0][1] == tole and acts[0][2] == KEY, "the act: %s" % str(acts))
	var b := Bounty.ensure()
	assert_eq(str(b.history.back()["kind"]), "pickpocket", "a crime all the same")
	assert_false(bool(b.history.back()["witnessed"]), "that nobody saw")
	var marks_before := bag.marks
	chance = Pickpocketing.chance_for(tole, me, Stealth.PURSE, 1)
	r = Pickpocketing.attempt(tole, me, Stealth.PURSE, _rng_rolling(chance, true), 1)
	assert_true(bool(r["ok"]))
	assert_eq(bag.marks - marks_before, 18, "his purse")
	# a new body for him, as a cell loaded again: his pockets stay emptied
	tole.get_node(Pickpocketing.POCKETS_NODE).free()
	assert_true(Pickpocketing.contents(tole, me).is_empty(), "what was taken stays taken")


func test_caught_it_is_a_crime_he_saw_and_he_is_wary_of_you() -> void:
	var me := _player()
	me.is_sneaking = true
	var tole := _npc(COLLECTOR)
	var reacted: Array = []
	var on_react := func(id: String, kind: String) -> void:
		reacted.append([id, kind])
	Reactions.ensure().reaction.connect(on_react)
	var chance := Pickpocketing.chance_for(tole, me, KEY)
	var r := Pickpocketing.attempt(tole, me, KEY, _rng_rolling(chance, false))
	Reactions.ensure().reaction.disconnect(on_react)
	assert_false(bool(r["ok"]))
	assert_true(bool(r["caught"]))
	assert_eq(str(r["reaction"]), "confront", "a proud man squares up to a thief")
	assert_eq(reacted, [[COLLECTOR, "confront"]])
	assert_eq(Pickpocketing.pockets(tole).count(KEY), 1, "he keeps his key")
	assert_eq((me.get_node("Inventory") as Inventory).count(KEY), 0)
	var b := Bounty.ensure()
	assert_eq(str(b.history.back()["kind"]), "pickpocket")
	assert_true(bool(b.history.back()["witnessed"]), "he saw it")
	assert_near(tole.detection, 1.0, 0.0001)
	tole.detection = 0.0
	assert_true(Pickpocketing.is_wary(tole))
	assert_false(Pickpocketing.can_offer(tole, me), "and he is wary of you for a while")
	WorldClock.set_time(2.0 + Pickpocketing.WARY_HOURS + 0.5, 2)
	assert_true(Pickpocketing.can_offer(tole, me), "and then he is not")


func test_the_screen_lifts_and_closes_on_a_fumble() -> void:
	var me := _player()
	var tole := _npc(COLLECTOR)
	var screen := UI.open("pickpocket", {"mark": tole, "actor": me})
	await (Engine.get_main_loop() as SceneTree).process_frame
	var list := screen.get("_list") as VBoxContainer
	assert_eq(list.get_child_count(), 2, "a row for the purse and one for the key")
	var chance := Pickpocketing.chance_for(tole, me, KEY)
	var r: Dictionary = screen.call("lift", KEY, _rng_rolling(chance, true))
	assert_true(bool(r["ok"]))
	assert_eq(int(screen.get("lifted")), 1)
	assert_eq(list.get_child_count(), 1, "the key gone from the list")
	chance = Pickpocketing.chance_for(tole, me, Stealth.PURSE, 1)
	r = screen.call("lift", Stealth.PURSE, _rng_rolling(chance, false))
	assert_true(bool(r["caught"]))
	await (Engine.get_main_loop() as SceneTree).create_timer(1.0, true, false, true).timeout
	assert_false(UI.is_menu_open("pickpocket"), "caught, the screen closes")


func test_the_rogue_s_lesson_counts_a_lift_from_the_collector() -> void:
	var me := _player()
	var quests: Node = Social.quests
	GameState.set_flag(StyleDef.FLAG, "core:style/rogue")
	quests.call("start", FIRST)
	quests.call("set_stage", FIRST, "the_strongbox")
	var objs: Array = quests.call("objectives_of", FIRST)
	var idx := -1
	for o in objs:
		if str((o as Dictionary).get("type", "")) == "act" and str((o as Dictionary).get("target", "")) == "pickpocket":
			idx = int(o["index"])
			assert_true(bool(o["optional"]), "an optional lesson")
	assert_true(idx >= 0, "the strongbox stage teaches the purse")
	var bram := _npc(BRAM)
	EventBus.act_done.emit("pickpocket", me, bram, "core:item/candle")
	assert_false(bool(quests.call("objective_done", FIRST, idx)), "somebody else's pocket is not the lesson")
	var tole := _npc(COLLECTOR)
	var chance := Pickpocketing.chance_for(tole, me, KEY)
	Pickpocketing.attempt(tole, me, KEY, _rng_rolling(chance, true))
	assert_true(bool(quests.call("objective_done", FIRST, idx)), "his key, lifted")
	assert_eq(str(quests.call("stage_id_of", FIRST)), "the_strongbox", "and the lock is still to pick")
	var def := ContentDB.get_def(COLLECTOR)
	assert_true((def.get("appearance", {}) as Dictionary).has("feminine"), "every person says their body")
	var spots: Array = ContentDB.get_def(FIRST).get("spots", [])
	assert_true(spots.any(func(s: Variant) -> bool: return str((s as Dictionary).get("name", "")) == "collector_doze"), "and his spot is on the landing")
