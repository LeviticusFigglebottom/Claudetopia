extends TestCase
## The rogue's start (docs/FIGHTING_STYLE_STARTS.md §3.4): the South Channel's traps before dawn,
## the collector's strongbox on the lockpick screen, a sack of eels and the dagger, the bravo on
## tithe-day, Tally, and The Unsaid Page, a courier a field ahead by road who goes down the stair.
## The systems it teaches are checked first: a crouched blow at something that never saw you is a
## sneak attack, and a lock can be picked (before this there was no lockpick screen at all).

const STYLE := "core:style/rogue"
const OPENING := "core:opening/rogue"
const FIRST := "core:quest/first_rogue"
const PAGE := "core:quest/the_unsaid_page"
const NAMING := "core:quest/the_naming"
const SAUVE := "core:npc/sauve_mor"
const WREN := "core:npc/wren_tallow"
const PLAYER := preload("res://actors/player/player.tscn")

var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _built() -> bool:
	return FileAccess.file_exists("res://world/generated/world_manifest.json")


func before_each() -> void:
	GameState.reset_for_new_game(53)
	Social.quests.call("reset_for_new_game")
	GameState.set_flag(StyleDef.FLAG, STYLE)
	GameState.set_flag(Openings.STYLE_START, true)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Social.quests.call("reset_for_new_game")
	GameState.reset_for_new_game(53)


class _At extends Node3D:
	var id := ""

	func content_id() -> String:
		return id


func _node(id := "", at := Vector3.ZERO, player := false) -> Node3D:
	var n := _At.new()
	n.id = id
	if player:
		n.add_to_group("player")
	_tree().root.add_child(n)
	n.global_position = at
	_nodes.append(n)
	return n


func _at(q: String) -> String:
	return str(Social.quests.call("stage_id_of", q))


func test_the_rogue_is_a_whole_style_with_its_own_start() -> void:
	var def := ContentDB.get_def(STYLE)
	assert_empty(StyleDef.validate(def, "pack"))
	assert_eq(str(Openings.for_new_game().get("id", "")), OPENING)
	var film := ContentDB.get_def(str(ContentDB.get_def(OPENING)["cinematic"]))
	assert_eq(CinematicDef.validate(film, "pack"), [] as Array[String])
	var seconds := CinematicDef.total_seconds(film)
	assert_true(seconds >= 30.0 and seconds <= 40.0, "30-40 s (%.0f s)" % seconds)
	assert_eq(StyleDef.kit_words(def), "an iron dagger and 6 lockpicks")
	assert_true(NpcRegistry.instance == null or NpcRegistry.instance.is_gone("core:npc/tithe_courier"), "the courier is only ever a lead")


## A lock picked: a set pin opens a locked chest, a bad miss snaps a pick, and the lesson is told.
func test_a_locked_chest_can_be_picked() -> void:
	var player := PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	_nodes.append(player)
	player.global_position = Vector3(6000, 0, 6000)
	var bag := player.get_node("Inventory") as Inventory
	var box := WorldContainer.new()
	box.container_id = "test_rogue/strongbox"
	box.locked = true
	box.lock_level = 1
	_tree().root.add_child(box)
	_nodes.append(box)
	var asked: Array = []
	var on_ask := func(lock: Object, _actor: Node) -> void:
		asked.append(lock)
	EventBus.lockpick_requested.connect(on_ask)
	assert_false(box.interact(player), "locked, and no pick: shut")
	assert_true(asked.is_empty(), "nothing to pick it with")
	bag.add("core:item/lockpick", 2)
	assert_false(box.interact(player), "a pick is not a key")
	EventBus.lockpick_requested.disconnect(on_ask)
	assert_eq(asked.size(), 1, "the lockpick screen is asked for")
	var seen: Array = []
	var on_act := func(act: String, _by: Node, on: Node, _d: String) -> void:
		seen.append([act, on])
	EventBus.act_done.connect(on_act)
	var r := box.attempt(player, 1.0)
	assert_false(bool(r["success"]), "a wild miss does not set it")
	assert_true(bool(r["broke"]), "and snaps the pick")
	assert_eq(bag.count("core:item/lockpick"), 1, "one pick gone")
	r = box.attempt(player, 0.0)
	EventBus.act_done.disconnect(on_act)
	assert_true(bool(r["success"]) and not box.locked, "a pin set dead centre opens it")
	assert_true(seen.size() == 1 and seen[0][0] == "pick_lock" and seen[0][1] == box, "and says so: %s" % str(seen))
	assert_true(box.interact(player), "and it opens")
	UI.close_all()


## The screen itself: a needle that sweeps, and a press on it that tries the pin.
func test_the_lockpick_screen_tries_the_pin_where_the_needle_stands() -> void:
	var player := PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	_nodes.append(player)
	(player.get_node("Inventory") as Inventory).add("core:item/lockpick", 1)
	var box := WorldContainer.new()
	box.container_id = "test_rogue/screen"
	box.locked = true
	_tree().root.add_child(box)
	_nodes.append(box)
	var screen := (load("res://ui/inventory/lockpick_screen.tscn") as PackedScene).instantiate()
	_tree().root.add_child(screen)
	_nodes.append(screen)
	screen.call("setup", {"lock": box, "actor": player})
	screen.set("_needle", 0.5)
	assert_near(float(screen.call("miss")), 0.0, 0.001, "the needle in the band's middle")
	screen.set_process(false)
	screen.call("try_pin")
	assert_false(box.locked, "set there, the pin opens the lock")
	# the screen closes itself a moment after the pin sets
	await _tree().create_timer(0.5).timeout


func test_a_crouched_blow_at_the_sack_is_a_sneak_attack() -> void:
	var player := PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	_nodes.append(player)
	player.global_position = Vector3(6000, 0, 6000)
	var sack := Pell.new()
	sack.kind = "sack"
	_tree().root.add_child(sack)
	_nodes.append(sack)
	sack.global_position = player.global_position + Vector3(0, 0, -1.2)
	assert_eq(sack.content_id(), "prop:sack")
	player.lock.set_target(sack)
	player.is_sneaking = false
	assert_eq(player._sneak_crit(), "", "standing up, it is only a blow")
	player.is_sneaking = true
	assert_eq(player._sneak_crit(), "sneak", "crouched and locked on, it never saw you")
	# and from behind it, locked on or not, the light is the backstab, carrying the sneak crit
	player.lock.clear()
	await _tree().physics_frame
	assert_eq(player._backstab_candidate(), sack, "behind the sack, within reach: a backstab")
	sack.rotation.y = PI
	await _tree().physics_frame
	assert_eq(player._backstab_candidate(), null, "in front of it, no")
	var pell := Pell.new()
	_tree().root.add_child(pell)
	_nodes.append(pell)
	pell.global_position = player.global_position + Vector3(0, 0, -1.0)
	await _tree().physics_frame
	assert_eq(player._backstab_candidate(), null, "a drill yard's pell is not stabbed in the back")


func test_the_lessons_close_on_the_acts() -> void:
	var quests: Node = Social.quests
	assert_true(bool(quests.call("start", FIRST)))
	var me := _node("", Vector3.ZERO, true)
	EventBus.act_done.emit("sneak", me, null, "")
	EventBus.dialogue_node_entered.emit(SAUVE, "traps_lifted")
	assert_eq(_at(FIRST), "the_strongbox", "quiet, and at the traps: the strongbox")
	EventBus.act_done.emit("pick_lock", me, _node("", Vector3.ZERO), "")
	assert_eq(_at(FIRST), "the_dagger")
	var sack := _node("prop:sack", Vector3(0, 0, 1))
	EventBus.act_done.emit("hit_light", me, sack, "")
	assert_eq(_at(FIRST), "the_dagger", "a plain blow is not the lesson")
	EventBus.act_done.emit("sneak_attack", me, sack, "")
	assert_eq(_at(FIRST), "the_bravo", "once, from behind")


func test_the_report_gives_tally_and_the_page_and_the_courier_leads_south() -> void:
	var quests: Node = Social.quests
	var bag := SocialFakes.FakeInventory.new()
	Social.bind("inventory", bag)
	quests.call("start", FIRST)
	quests.call("set_stage", FIRST, "report")
	EventBus.dialogue_node_entered.emit(SAUVE, "report_done")
	assert_true(bool(quests.call("is_completed", FIRST)))
	assert_eq(bag.count("core:item/unsaid_page"), 1, "the page from the collector's satchel")
	assert_true(GameState.has_flag(SocialContext.MOUNT_FLAG_PREFIX + "core:mount/tithe_bay"), "Tally is the rogue's")
	assert_eq(_at(PAGE), "the_courier")
	var leads := Leads.new()
	_tree().root.add_child(leads)
	_nodes.append(leads)
	var spec: Dictionary = leads.wanted().get("tithe_courier", {})
	assert_eq(str(spec.get("npc", "")), "core:npc/tithe_courier", "the courier stands at the landing's end")
	EventBus.dialogue_node_entered.emit(SAUVE, "courier_ask")
	assert_eq(_at(PAGE), "follow")
	spec = leads.wanted().get("tithe_courier", {})
	if _built():
		var way := leads.way_of(spec)
		var length := 0.0
		for i in range(way.size() - 1):
			length += Vector2(way[i].x, way[i].z).distance_to(Vector2(way[i + 1].x, way[i + 1].z))
		assert_true(length > 7000.0 and length < 10500.0, "by road to the Stair Head: %.0f m" % length)
	quests.call("set_stage", PAGE, "the_stair_head")
	var greeting := str(Social.dialogue.call("greeting_for", WREN))
	assert_true(greeting.begins_with("Nobody I want to know"), greeting)
	EventBus.dialogue_node_entered.emit(WREN, "the_page_came")
	assert_true(bool(quests.call("is_completed", PAGE)))
	assert_eq(_at(NAMING), "down_the_stair")
	spec = leads.wanted().get("tithe_courier", {})
	assert_eq(str(spec.get("way", "")), "descent", "and then he goes down the stair")
	Social.bind("inventory", null)
	Social.refresh_providers()


func test_sauve_greets_a_calling_from_far_away() -> void:
	Social.quests.call("start", FIRST)
	GameState.set_flag("player_calling", "core:calling/cragborn")
	var line := str(Social.dialogue.call("greeting_for", SAUVE))
	assert_true(line.begins_with("Fell-boots, in a marsh."), line)


func _until(pred: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if bool(pred.call()):
			return true
		await _tree().process_frame
	return bool(pred.call())


## In the built world: a rogue's new game stands on Moreva's south boards with the dagger in hand
## and picks in the pack, the strongbox and the sack laid on the landing, and Sauve speaking first.
func test_a_rogue_s_new_game_begins_on_the_boards_at_moreva() -> void:
	if not _built():
		skip("no built world")
		return
	GameState.set_flag("player_name", "Hesk of the Delta")
	GameState.set_flag("player_calling", "core:calling/lantern_clerk")
	GameState.set_flag(Openings.STYLE_DUE, true)
	WorldClock.set_time(5.0)
	var w := (load("res://world/world.tscn") as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	var begun := await _until(func() -> bool: return bool(Social.quests.call("is_active", FIRST)), 10.0)
	assert_true(begun, "the tutorial begins")
	var player := w.get_node("PlayerSpawn").get("player") as Player
	var ground := w.provider.get_height(player.global_position.x, player.global_position.z)
	assert_true(absf(player.global_position.y - ground) < 1.5, "on the boards, not in the air or the channel")
	await _tree().physics_frame
	var from := player.global_position + Vector3.UP * 1.6
	var roof := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 30.0, 1, [(player as CollisionObject3D).get_rid()]))
	assert_true(roof.is_empty(), "open sky over the body, not a house: %s" % str(roof.get("collider", "")))
	var worn := player.get_node("Equipment") as Equipment
	assert_eq(str(worn.get_slot("main_hand").id), "core:item/iron_dagger", "the dagger in hand")
	assert_true((player.get_node("Inventory") as Inventory).count("core:item/lockpick") >= 6, "and six picks, with whatever the Calling brought")
	var spots := QuestSpots.ensure()
	var box: Variant = spots.props.get("tithe_strongbox", null)
	assert_true(box is WorldContainer and (box as WorldContainer).locked, "the strongbox, locked")
	var sack: Variant = spots.props.get("eel_sack", null)
	assert_true(sack is Pell and (sack as Pell).kind == "sack", "the sack on its crossbar")
	if box is Node3D:
		var d := (box as Node3D).global_position.distance_to(player.global_position)
		assert_true(d < 40.0, "the strongbox on the landing, %.0f m off" % d)
	var services := _tree().get_first_node_in_group("game_services")
	assert_true(str(services.get("first_words")).begins_with("Down."), "Sauve speaks first: %s" % str(services.get("first_words")))
	var sauve_near := await _until(func() -> bool:
			var t := NpcRegistry.instance.actor(SAUVE) as Node3D
			return t != null and t.global_position.distance_to(player.global_position) < 12.0, 20.0)
	assert_true(sauve_near, "Sauve on the boards")
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame
