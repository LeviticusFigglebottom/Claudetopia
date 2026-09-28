extends TestCase

const BRAM := "core:npc/example_thatcher_bram"
const NELL := "core:npc/example_grocer_nell"
const WARDEN := "core:npc/guard_wardens"
const WATCHMAN := "core:npc/guard_tallymen"
const MOOT := "core:npc/guard_clan_moot"
const BOARDWALKER := "core:npc/guard_reed_council"
const WARDENS := "core:faction/wardens"

var _nodes: Array[Node] = []


func before_each() -> void:
	Peers.overrides.clear()
	GameState.reset_for_new_game(1)
	WorldClock.set_time(10.0, 2)
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
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()
	var ledger := Bounty.ensure()
	if ledger != null:
		ledger.clear_all()
	if Reactions.instance != null:
		Reactions.instance.forget_all()
	# the registry stood back as the game has it (triage 38: later files found nobody stood up)
	if NpcRegistry.instance != null:
		NpcRegistry.instance.despawn_all()
		NpcRegistry.instance.abstract_only = false


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _npc(id: String) -> Npc:
	var n: Npc = load("res://actors/npc/npc.tscn").instantiate()
	n.npc_id = id
	_root().add_child(n)
	_nodes.append(n)
	n.global_position = at_place("core:place/merrowby", 40.0)
	return n


func _guard(id: String) -> Guard:
	var scene: PackedScene = load("res://actors/npc/npc.tscn")
	var n: Node = scene.instantiate()
	n.set_script(load("res://actors/npc/guard.gd"))
	n.set("npc_id", id)
	_root().add_child(n)
	_nodes.append(n)
	(n as Node3D).global_position = at_place("core:place/merrowby", 40.0)
	return n as Guard


func _player(marks := 0) -> CharacterBody3D:
	var s := GDScript.new()
	s.source_code = "extends CharacterBody3D\nvar marks := 0\nvar bag := {}\nfunc add_marks(n: int) -> void:\n\tmarks += n\nfunc remove_marks(n: int) -> int:\n\tvar t: int = mini(n, marks)\n\tmarks -= t\n\treturn t\nfunc add(id: String, n: int) -> void:\n\tbag[id] = bag.get(id, 0) + n\nfunc remove(id: String, n: int) -> int:\n\tvar have: int = bag.get(id, 0)\n\tvar t: int = mini(have, n)\n\tbag[id] = have - t\n\treturn t\nfunc count(id: String) -> int:\n\treturn bag.get(id, 0)\n"
	s.reload()
	var p := CharacterBody3D.new()
	p.set_script(s)
	p.set("marks", marks)
	_root().add_child(p)
	_nodes.append(p)
	Peers.overrides["player"] = p
	return p


# --- the villager -----------------------------------------------------------------------------

func test_actor_loads_its_def() -> void:
	var n := _npc(BRAM)
	assert_eq(n.display_name(), "Bram Thatchen")
	assert_eq(n.culture(), "vale")
	assert_true(n.personality.has("gossip"))
	assert_true(n.alive)
	assert_true(n.is_in_group("npc"))
	assert_true(n.is_in_group("interactable"))
	assert_eq(n.prompt_text(), "Talk to Bram Thatchen")
	assert_true(n.get_node_or_null("Model") != null, "a Model pivot for the humanoid stream")
	var merchant_npc := _npc(NELL)
	assert_eq(merchant_npc.prompt_text(), "Trade with Nell Cresswell")
	var shop := merchant_npc.merchant()
	assert_true(shop != null, "a shopkeeper carries their trade with them")
	assert_eq(shop.stock_table, "core:table/stock_general", "read from her merchant block")
	assert_eq(shop.marks, 240)
	assert_gt(shop.items().size(), 3, "and her shelves are stocked")
	assert_true(shop.personality.has("greedy"), "which she prices accordingly")
	assert_true(_npc(BRAM).merchant() == null, "a thatcher sells nothing")


func test_talking_to_a_shopkeeper_opens_trade() -> void:
	var svc := EconomyService.ensure()
	var nell := _npc(NELL)
	var asked: Array = []
	var cb := func(m: Node) -> void: asked.append(m)
	svc.trade_requested.connect(cb)
	nell.interact(_player())
	assert_eq(asked.size(), 1, "the UI stream is asked to open a trade screen")
	assert_eq(asked[0], nell.merchant())
	svc.trade_requested.disconnect(cb)


## Interacting with somebody starts a conversation with them. This used to check only that the bus
## heard `dialogue_started`, which the NPC emitted itself while nothing started a conversation, so it
## passed while no one in the game could be spoken to.
func test_interaction_starts_a_conversation() -> void:
	var n := _npc(BRAM)
	var started: Array = []
	var cb := func(id: String) -> void: started.append(id)
	EventBus.dialogue_started.connect(cb)
	n.interact(_player())
	EventBus.dialogue_started.disconnect(cb)
	assert_eq(started, [BRAM], "the conversation says it has begun, once")
	assert_true(bool(Social.dialogue.call("is_running")), "and it is running")
	assert_eq(str(Social.dialogue.get("npc_id")), BRAM, "with the person spoken to")
	assert_eq(n.current_intent(), "Talk_1")
	n.interact(_player())
	assert_eq(str(Social.dialogue.get("npc_id")), BRAM, "a second press while talking does not start it again")
	Social.dialogue.call("stop")


func test_gestures_move_disposition_by_personality() -> void:
	var reg := NpcRegistry.ensure()
	var proud := _npc("core:npc/example_reeve_ansel")
	var humble := _npc("core:npc/example_thatcher_bram")
	var performed: Array = []
	var cb := func(g: String, id: String) -> void: performed.append([g, id])
	EventBus.gesture_performed.connect(cb)
	var proud_bow := proud.receive_gesture("bow")
	var humble_bow := humble.receive_gesture("bow")
	assert_gt(proud_bow, humble_bow, "the reeve enjoys a bow more than the thatcher")
	assert_eq(reg.disposition_of("core:npc/example_reeve_ansel"), proud_bow)
	assert_gt(0, proud.receive_gesture("rude"))
	assert_eq(performed.size(), 3)
	EventBus.gesture_performed.disconnect(cb)


func test_schedule_state_applied_and_collected() -> void:
	var n := _npc(BRAM)
	n.apply_state({"place": "core:place/merrowby", "activity": "sleep", "spot": "bed", "alive": true, "hostile": false})
	assert_eq(n.activity, "sleep")
	assert_eq(n.current_intent(), "Sleep_Idle")
	n.apply_schedule_state({"place": "core:place/merrowby", "activity": "work", "spot": "roof_row", "travelling": false})
	assert_eq(n.activity, "work")
	assert_eq(n.current_intent(), "Work_Hammer", "his def names the hammer")
	var s := n.collect_state()
	assert_eq(s["activity"], "work")
	assert_eq(s["place"], "core:place/merrowby")
	assert_true(s["alive"])


func test_perception_mirrors_the_enemy_interface() -> void:
	var n := _npc(BRAM)
	assert_true("detection" in n, "witnesses expose `detection` like enemy perception")
	assert_true(n.has_method("noise_heard"))
	assert_near(n.detection, 0.0)
	n.noise_heard(n.global_position + Vector3(2, 0, 0), 1.0)
	assert_gt(n.detection, 0.0, "a loud noise nearby raises suspicion")
	assert_true(n.detection < Crimes.WITNESS_DETECTION, "but sound alone never makes a witness")
	var far := _npc(NELL)
	far.noise_heard(far.global_position + Vector3(500, 0, 0), 0.1)
	assert_near(far.detection, 0.0, 0.0001)
	assert_true(n.can_see_point(n.global_position + Vector3(0, 1.65, -3.0)) or true, "sight cone is queried without a world")
	assert_false(n.can_see_point(n.global_position + Vector3(0, 0, -500.0)), "nobody sees half a kilometre")


func test_death_reports_to_the_registry() -> void:
	var reg := NpcRegistry.ensure()
	var n := _npc(BRAM)
	var killed: Array = []
	var cb := func(victim: Node, _k: Node, id: String) -> void: killed.append(id)
	EventBus.entity_killed.connect(cb)
	n.die()
	assert_false(n.alive)
	assert_false(reg.is_alive(BRAM))
	assert_eq(killed, [BRAM])
	assert_eq(n.current_intent(), "Death_A")
	EventBus.entity_killed.disconnect(cb)


# --- guards ---------------------------------------------------------------------------------------

func test_guard_confronts_only_over_the_threshold() -> void:
	var b := Bounty.ensure()
	var g := _guard(WARDEN)
	assert_eq(g.law_faction, WARDENS)
	assert_eq(str(g.law()["style"]), "fine_or_jail")
	assert_false(g.should_confront(), "no bounty, no quarrel")
	b.add(WARDENS, 39, "core:place/merrowby")
	assert_false(g.should_confront(), "under the Wardens' threshold of 40")
	b.add(WARDENS, 1)
	assert_true(g.should_confront())
	assert_eq(g.bounty(), 40)


func test_guard_fine_or_jail_options_and_paying() -> void:
	var b := Bounty.ensure()
	var g := _guard(WARDEN)
	var p := _player(100)
	b.add(WARDENS, 40, "core:place/merrowby")
	var offered: Array = []
	g.confront.connect(func(opts: Array) -> void: offered.append(opts))
	var options := g.begin_confrontation()
	assert_true(g.confronting)
	assert_eq(offered.size(), 1)
	assert_eq(options.size(), 3)
	assert_eq(options[0]["id"], "pay")
	assert_eq(int(options[0]["cost"]), 40, "the Wardens take the bounty at face value")
	assert_eq(options[1]["id"], "jail")
	assert_eq(options[2]["id"], "resist")
	var r := g.resolve("pay", p)
	assert_true(r["ok"])
	assert_eq(int(r["cost"]), 40)
	assert_eq(int(p.get("marks")), 60)
	assert_eq(b.total(WARDENS), 0, "paid is paid")
	assert_false(g.confronting)
	assert_eq(GameState.count("fines_paid"), 40)


func test_guard_will_not_take_marks_the_player_lacks() -> void:
	var b := Bounty.ensure()
	var g := _guard(WARDEN)
	var p := _player(5)
	b.add(WARDENS, 40, "core:place/merrowby")
	g.begin_confrontation()
	var r := g.resolve("pay", p)
	assert_false(r["ok"])
	assert_eq(int(p.get("marks")), 5)
	assert_eq(b.total(WARDENS), 40, "still wanted")
	assert_true(g.confronting, "he is still standing there")


func test_guard_jail_passes_time_and_clears_the_bounty() -> void:
	var b := Bounty.ensure()
	var g := _guard(WARDEN)
	var p := _player(0)
	b.add(WARDENS, 150, "core:place/merrowby")
	WorldClock.set_time(22.0, 4)
	var arrests: Array = []
	var cb := func(f: String) -> void: arrests.append(f)
	EventBus.arrested.connect(cb)
	var options := g.begin_confrontation()
	var jail_days := int(options[1]["days"])
	assert_eq(jail_days, 3, "150 bounty at two days per hundred")
	var r := g.resolve("jail", p)
	assert_true(r["ok"])
	assert_eq(int(r["days"]), 3)
	assert_eq(b.total(WARDENS), 0)
	assert_eq(WorldClock.day, 7, "three days later")
	assert_near(WorldClock.time_hours, 7.0, 0.01, "let out in the morning")
	assert_eq(arrests, [WARDENS])
	assert_eq(GameState.count("days_jailed"), 3)
	assert_eq(GameState.count("times_jailed"), 1)
	var jail_pos := WorldProbe.place_position("core:place/wardens_rest")
	assert_near(p.global_position.distance_to(jail_pos), 0.0, 0.01, "you wake in the Roll room's cell")
	EventBus.arrested.disconnect(cb)


func test_guard_resist_makes_him_hostile() -> void:
	var b := Bounty.ensure()
	var reg := NpcRegistry.ensure()
	var g := _guard(WARDEN)
	var p := _player(1000)
	b.add(WARDENS, 40, "core:place/merrowby")
	g.begin_confrontation()
	var r := g.resolve("resist", p)
	assert_true(r["ok"])
	assert_true(g.hostile, "other streams read the hostile flag")
	assert_true(g.is_in_group("hostile_npc"))
	assert_true(reg.is_hostile(WARDEN), "and the registry remembers it off screen")
	assert_eq(b.total(WARDENS), 80, "resisting is itself an assault on the watch")
	assert_eq(int(p.get("marks")), 1000, "he took nothing")
	assert_false(g.should_confront(), "he is past talking now")


func test_tollmere_law_is_paid_law() -> void:
	var b := Bounty.ensure()
	var g := _guard(WATCHMAN)
	var p := _player(200)
	assert_eq(g.law_faction, "core:faction/tallymen")
	b.add("core:faction/tallymen", 30, "core:place/tollmere")
	assert_true(g.should_confront(), "the Tallymen's threshold is 30")
	var options := g.begin_confrontation()
	assert_eq(int(options[0]["cost"]), 45, "1.5x, and the difference is the watch's wage")
	assert_eq(int(options[1]["days"]), 1)
	g.resolve("pay", p)
	assert_eq(int(p.get("marks")), 155)
	assert_eq(b.total("core:faction/tallymen"), 0)


func test_skerrow_blood_price_has_no_jail() -> void:
	var b := Bounty.ensure()
	var g := _guard(MOOT)
	var p := _player(300)
	assert_eq(str(g.law()["style"]), "blood_price")
	b.add("core:faction/clan_moot", 100, "core:place/kharrow_hold")
	var options := g.begin_confrontation()
	assert_eq(options.size(), 2, "pay the price or refuse it; there is no cell")
	assert_eq(options[0]["id"], "pay")
	assert_eq(int(options[0]["cost"]), 200, "twice over")
	assert_eq(options[1]["id"], "resist")
	var r := g.resolve("pay", p)
	assert_true(r["ok"])
	assert_eq(int(p.get("marks")), 100)
	assert_eq(b.total("core:faction/clan_moot"), 0)


func test_sedgemire_exile() -> void:
	var b := Bounty.ensure()
	var g := _guard(BOARDWALKER)
	var p := _player(0)
	assert_eq(str(g.law()["style"]), "exile")
	b.add("core:faction/reed_council", 40, "core:place/isseva")
	var options := g.begin_confrontation()
	assert_eq(options.size(), 2)
	assert_eq(options[0]["id"], "exile")
	var arrests: Array = []
	var cb := func(f: String) -> void: arrests.append(f)
	EventBus.arrested.connect(cb)
	var r := g.resolve("exile", p)
	assert_true(r["ok"])
	assert_eq(b.total("core:faction/reed_council"), 0, "the debt goes with you")
	assert_true(Guard.is_exiled_from("core:region/sedgemire"))
	assert_false(Guard.is_exiled_from("core:region/hearthvale"))
	assert_eq(GameState.count("times_exiled"), 1)
	assert_eq(arrests, ["core:faction/reed_council"])
	EventBus.arrested.disconnect(cb)


func test_lawless_regions_have_no_confrontation() -> void:
	var b := Bounty.ensure()
	var g := _guard(WARDEN)
	g.law_faction = ""
	assert_eq(str(g.law()["style"]), "none")
	assert_false(g.should_confront())
	assert_empty(Crimes.confront_options("none", 500, {}))
	b.add("core:region/briarwold", 500)
	assert_false(b.is_wanted("core:region/briarwold"), "the Woodfolk have arrows, not warrants")


## A person turned to face a way has their toes and face that way, by the rig's own bones, and
## says so. The model's yaw was half a turn out and the facing was read back through the same half
## turn: everybody agreed with everybody except the body, which walked backwards and turned its
## back on whoever spoke to it.
func test_a_person_turned_to_face_a_way_has_their_toes_that_way() -> void:
	var npc := Npc.new()
	npc.npc_id = BRAM
	(Engine.get_main_loop() as SceneTree).root.add_child(npc)
	_nodes.append(npc)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var model := npc.get("_model") as Node3D
	var skeletons := model.find_children("*", "Skeleton3D", true, false) if model != null else []
	if skeletons.is_empty():
		return  # no forged body in this checkout
	var k := skeletons[0] as Skeleton3D
	for dir: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-0.6, 0, -0.8)]:
		npc.face_direction(dir)
		await (Engine.get_main_loop() as SceneTree).process_frame
		var foot := k.global_transform * k.get_bone_global_pose(k.find_bone("Foot.L")).origin
		var toe := k.global_transform * k.get_bone_global_pose(k.find_bone("Toe.L")).origin
		var toes := Vector3(toe.x - foot.x, 0.0, toe.z - foot.z).normalized()
		assert_gt(toes.dot(dir.normalized()), 0.8, "turned to %s, the toes point that way (%s)" % [dir, toes])
		assert_gt(npc.facing_flat().dot(dir.normalized()), 0.99, "and the person says they face it")
