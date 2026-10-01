extends TestCase
## The warrior's start (docs/FIGHTING_STYLE_STARTS.md §3.1): Wardens' Rest's drill yard with pells
## to strike and a ring to spar in, Sergeant Dole's lessons as objectives the body's own blows and
## guards close, the horse after the first lesson, the bout in the ring that nobody dies of, the ditch,
## the report, and The Relief,
## which ends at the Stair Head with Tam Hobb walking down it and the Naming waiting there.
##
## The yard tests stand the built world up and ask the fort; the story tests drive the quest log
## with the events play sends (EventBus.act_done, a conversation's line, a kill).

const STYLE := "core:style/warrior"
const OPENING := "core:opening/warrior"
const FIRST := "core:quest/first_warrior"
const RELIEF := "core:quest/the_relief"
const NAMING := "core:quest/the_naming"
const DOLE := "core:npc/wardens_dole"
const TAM := "core:npc/tam_hobb"
const WREN := "core:npc/wren_tallow"
const SPARRING := "core:enemy/sparring_dole"
const REST := "core:place/wardens_rest"
const PLAYER := preload("res://actors/player/player.tscn")

var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _built() -> bool:
	return FileAccess.file_exists("res://world/generated/world_manifest.json")


static func _water(p: Vector3) -> float:
	var t: Object = World.terrain()
	return float(t.call("water_depth_at", p.x, p.z)) if t != null and t.has_method("water_depth_at") else 0.0


func before_each() -> void:
	GameState.reset_for_new_game(21)
	Social.quests.call("reset_for_new_game")
	GameState.set_flag(StyleDef.FLAG, STYLE)
	GameState.set_flag(Openings.STYLE_START, true)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Social.quests.call("reset_for_new_game")
	GameState.reset_for_new_game(21)


# --- the data ----------------------------------------------------------------------------------------

func test_the_warrior_is_a_whole_style_with_its_own_start() -> void:
	var def := ContentDB.get_def(STYLE)
	assert_empty(StyleDef.validate(def, "pack"))
	assert_eq(str(Openings.for_new_game().get("id", "")), OPENING, "a warrior begins at Wardens' Rest")
	var opening := ContentDB.get_def(OPENING)
	assert_eq(str(opening.get("quest", "")), FIRST)
	assert_eq(str(opening.get("greeter", "")), DOLE, "and Sergeant Dole speaks first")
	assert_true(ContentDB.has(str(opening.get("cinematic", ""))), "with a film of its own")
	var film := ContentDB.get_def(str(opening["cinematic"]))
	assert_eq(CinematicDef.validate(film, "pack"), [] as Array[String], "that validates")
	var seconds := CinematicDef.total_seconds(film)
	assert_true(seconds >= 30.0 and seconds <= 40.0, "30-40 s, as the user asked (%.0f s)" % seconds)
	assert_eq(StyleDef.kit_words(def), "an iron sword, an oak round shield and a pitch torch")
	assert_eq(str(def.get("tie_in", "")), RELIEF)


func test_the_teacher_greets_a_calling_from_far_away_with_a_line_of_its_own() -> void:
	Social.quests.call("start", FIRST)
	GameState.set_flag("player_calling", "core:calling/cragborn")
	var line := str(Social.dialogue.call("greeting_for", DOLE))
	assert_true(line.contains("long way from the fells, Cragborn") and line.ends_with("I'll say what today's for, once."), "Dole calls a Cragborn over: %s" % line)
	Social.quests.call("set_stage", FIRST, "the_yard")
	line = str(Social.dialogue.call("greeting_for", DOLE))
	assert_true(line.contains("long way from the fells, Cragborn"), "Dole to a Cragborn: %s" % line)
	GameState.set_flag("player_calling", "core:calling/hearthkeeper")
	line = str(Social.dialogue.call("greeting_for", DOLE))
	assert_eq(line, "Recruit. The Warden at the Stair Head is a month short of her pay, and somebody rides it south today. If you can fight, it's you. Pells first. Light blows. I'll say it once.",
			"and to one of the Vale's own, only the goal and the pells")


# --- the story ---------------------------------------------------------------------------------------

func _me() -> Node3D:
	var me := Node3D.new()
	me.add_to_group("player")
	_tree().root.add_child(me)
	_nodes.append(me)
	return me


func _foe(id: String) -> Node3D:
	var n := _Foe.new()
	n.id = id
	_tree().root.add_child(n)
	_nodes.append(n)
	return n


class _Foe extends Node3D:
	var id := ""

	func content_id() -> String:
		return id


func _at() -> String:
	return str(Social.quests.call("stage_id_of", FIRST))


func test_the_yard_s_lessons_close_on_the_body_s_own_blows() -> void:
	var quests: Node = Social.quests
	assert_true(bool(quests.call("start", FIRST)))
	# the day opens on Dole's word: what it is for, and why (the owner's playtest, 2026-09-30)
	assert_eq(_at(), "hear_dole", "the day opens on Dole's word")
	var talk: Dictionary = (quests.call("objectives_of", FIRST) as Array)[0]
	assert_true(str(talk["type"]) == "talk" and str(talk["target"]) == DOLE, "the first objective is to speak to him")
	EventBus.dialogue_node_entered.emit(DOLE, "the_day")
	assert_eq(_at(), "the_yard", "and once he has said it, the pells")
	var me := _me()
	var pell := _foe("prop:pell")
	# a blow at anything else is not the yard's (the marker points at the pells: `against`)
	EventBus.act_done.emit("hit_light", me, _foe("core:enemy/roadside_bandit"), "")
	assert_eq(int((quests.call("objectives_of", FIRST) as Array)[0]["count"]), 0, "a blow at a bandit is not a pell's")
	for i in 3:
		EventBus.act_done.emit("hit_light", me, pell, "")
	assert_eq(_at(), "the_yard", "three light blows are not the whole yard")
	EventBus.act_done.emit("hit_heavy", me, pell, "")
	EventBus.act_done.emit("hit_heavy", me, pell, "")
	EventBus.act_done.emit("lock_on", me, pell, "")
	assert_eq(_at(), "the_ring", "light, heavy and a lock-on: into the ring")
	assert_true(GameState.has_flag(SocialContext.MOUNT_FLAG_PREFIX + "core:mount/wardens_cob"), "and Hollin is the recruit's from the first lesson (triage 52)")
	assert_true(Conditions.check({"has_mount": true}, Social.ctx), "a horse of your own")
	var text := str((quests.call("objectives_of", FIRST) as Array)[1]["text"])
	assert_true(text.begins_with("Take two of his blows on your shield: hold [") and not text.contains("{"), "the lesson says the key: %s" % text)


## Triage 80: the lock-on was on the middle mouse button alone, which some players have not got.
## It is on a key as well (Z), the yard's lesson says both, and the lesson is done with the key, as
## the keyboard sends it, by the real body at a pell: no mouse at all.
func test_the_yard_s_lock_on_is_done_with_a_key_not_the_mouse() -> void:
	var keys: Array[String] = Settings.bindings_for("lock_on", false)
	assert_true(keys.has("mouse:3") and keys.has("key:Z"), "the lock-on is on the middle mouse button and on Z: %s" % str(keys))
	for other in Settings.bindings:
		if other != "lock_on":
			assert_false((Settings.bindings[other] as Array).has("key:Z"), "Z is the lock-on's alone, not %s's" % other)
	var quests: Node = Social.quests
	assert_true(bool(quests.call("start", FIRST)))
	quests.call("set_stage", FIRST, "the_yard")
	quests.call("complete_objective", FIRST, 0)
	quests.call("complete_objective", FIRST, 1)
	var text := str((quests.call("objectives_of", FIRST) as Array)[2]["text"])
	assert_true(text.contains("[MMB] or [Z]"), "the lesson says both: %s" % text)
	# a floor, the body on it facing north, and a pell four paces ahead
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	ground.add_child(shape)
	_tree().root.add_child(ground)
	_nodes.append(ground)
	ground.global_position = Vector3(9000.0, -0.5, 9000.0)
	var body := PLAYER.instantiate() as Player
	_tree().root.add_child(body)
	_nodes.append(body)
	body.teleport(Vector3(9000.0, 0.02, 9000.0), 0.0)
	var pell := Pell.new()
	pell.name = "yard_pell"
	_tree().root.add_child(pell)
	_nodes.append(pell)
	pell.global_position = Vector3(9000.0, 0.0, 8996.0)
	for i in 10:
		await _tree().physics_frame
	assert_false(body.lock.is_locked(), "not locked on yet")
	var z := InputEventKey.new()
	z.physical_keycode = KEY_Z
	z.keycode = KEY_Z
	z.pressed = true
	Input.parse_input_event(z)
	for i in 4:
		await _tree().physics_frame
	var up := z.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	for i in 3:
		await _tree().physics_frame
	assert_true(body.lock.is_locked() and body.lock.target == pell, "Z locks on to the pell (target %s)" % str(body.lock.target))
	assert_eq(_at(), "the_ring", "and the yard's lock-on lesson is done with the key: into the ring")


func test_the_ring_waits_for_the_word_then_counts_only_the_teacher_s_blows() -> void:
	var quests: Node = Social.quests
	quests.call("start", FIRST)
	quests.call("set_stage", FIRST, "the_ring")
	var me := _me()
	var dole := _foe(SPARRING)
	var bandit := _foe("core:enemy/roadside_bandit")
	EventBus.act_done.emit("block", me, bandit, "")
	assert_eq(int((quests.call("objectives_of", FIRST) as Array)[1]["count"]), 0, "a bandit's blow is not the lesson")
	# the word: the ring_begin line sets the flag the bout waits for, and closes the talk
	Social.dialogue.call("start", "core:dialogue/wardens_q1_dole", DOLE, REST)
	Social.dialogue.call("_enter", "ring_begin")
	if bool(Social.dialogue.call("is_running")):
		Social.dialogue.call("stop")
	assert_true(GameState.has_flag("dole_spar_ready"), "Dole is ready once asked")
	for a in ["block", "block", "parry", "dodge", "dodge"]:
		EventBus.act_done.emit(a, me, dole, "")
	assert_eq(_at(), "the_ditch", "the bout's lessons done: the ditch")
	assert_false(GameState.has_flag("dole_spar_ready"), "and the ring is shut")
	assert_true(GameState.has_flag("tam_sent"), "and Tam sent ahead to the verge")


func test_the_ditch_is_ridden_to_on_hollin_and_fought() -> void:
	var quests: Node = Social.quests
	quests.call("start", FIRST)
	quests.call("set_stage", FIRST, "the_ditch")
	var me := _me()
	EventBus.act_done.emit("mount", me, _foe("core:mount/rosen_pony"), "")
	assert_false(bool(quests.call("objective_done", FIRST, 0)), "somebody else's pony is not Hollin")
	EventBus.act_done.emit("mount", me, _foe("core:mount/wardens_cob"), "")
	assert_true(bool(quests.call("objective_done", FIRST, 0)), "up on Hollin")
	quests.call("complete_objective", FIRST, 1)
	assert_eq(_at(), "report", "the two bandits down: back to Dole")


func test_the_report_gives_the_pay_and_the_road_south() -> void:
	var quests: Node = Social.quests
	var bag := SocialFakes.FakeInventory.new()
	Social.bind("inventory", bag)
	quests.call("start", FIRST)
	quests.call("set_stage", FIRST, "report")
	EventBus.dialogue_ended.emit(TAM)
	EventBus.dialogue_node_entered.emit(DOLE, "report_done")
	assert_true(bool(quests.call("is_completed", FIRST)), "First Blood is done")
	assert_eq(bag.count("core:item/stair_head_pay"), 1, "with the Stair Head's pay")
	assert_eq(bag.count("core:item/new_roll_page"), 1, "and the Roll's new page")
	assert_true(bool(quests.call("is_active", RELIEF)), "and The Relief begun")
	assert_eq(str(quests.call("stage_id_of", RELIEF)), "the_ride", "whose first step is the ride south")
	Social.bind("inventory", null)
	Social.refresh_providers()


func test_the_relief_ends_with_tam_going_down_and_the_naming_waiting() -> void:
	var quests: Node = Social.quests
	var bag := SocialFakes.FakeInventory.new()
	Social.bind("inventory", bag)
	bag.add("core:item/stair_head_pay", 1)
	bag.add("core:item/new_roll_page", 1)
	quests.call("start", RELIEF)
	quests.call("set_stage", RELIEF, "the_stair_head")
	var greeting := str(Social.dialogue.call("greeting_for", WREN))
	assert_true(greeting.begins_with("Dole's recruit."), "the Warden knows who sent you: %s" % greeting)
	assert_true(greeting.contains("I'm the Warden; that's all the name the Stair needs"), "and does not give her name")
	assert_eq(Npc.shown_name(ContentDB.get_def(WREN), Social.ctx), "The Warden", "her nameplate says so too")
	var tam_there := Schedules.entry_for_def(ContentDB.get_def(TAM), 3, 11.0)
	assert_eq(str(tam_there.get("spot", "")), "stair_head_guest", "Tam is at her fire")
	Social.dialogue.call("start", "core:dialogue/wren_tallow", WREN, "core:poi/stair_head")
	Social.dialogue.call("_enter", "the_pay")
	if bool(Social.dialogue.call("is_running")):
		Social.dialogue.call("stop")
	await _tree().process_frame
	assert_true(bool(quests.call("is_completed", RELIEF)), "the pay is handed over and The Relief is done")
	assert_eq(bag.count("core:item/stair_head_pay"), 0)
	assert_eq(str(quests.call("stage_id_of", NAMING)), "down_the_stair", "the Naming waits at the top of the stair")
	var tam_goes := Schedules.entry_for_def(ContentDB.get_def(TAM), 3, 11.0)
	assert_eq(str(tam_goes.get("spot", "")), StairDescent.LEAD_SPOT, "and Tam walks down it")
	assert_eq(str(tam_goes.get("place", "")), "core:poi/stair_head")
	GameState.set_flag("woke_at_hushline", true)
	var reg := NpcRegistry.instance
	if reg != null:
		assert_true(reg.is_gone(TAM), "after the wake he is not in the world")
	Social.bind("inventory", null)
	Social.refresh_providers()


# --- the bout ------------------------------------------------------------------------------------------

class _Ring extends Node3D:
	var place_id := REST

	func feature_position(feature_name: String) -> Vector3:
		return global_position if feature_name == "ring" else Vector3.INF


func test_a_bout_in_the_ring_stands_the_teacher_up_and_nobody_dies_of_it() -> void:
	var ring := _Ring.new()
	ring.add_to_group("settlement")
	_tree().root.add_child(ring)
	_nodes.append(ring)
	ring.global_position = Vector3(5000.0, 0.0, 5000.0)
	var player := PLAYER.instantiate() as Actor
	_tree().root.add_child(player)
	_nodes.append(player)
	player.global_position = ring.global_position + Vector3(2.0, 0.0, 0.0)
	var sparring := Sparring.new()
	_tree().root.add_child(sparring)
	_nodes.append(sparring)
	Social.quests.call("start", FIRST)
	Social.quests.call("set_stage", FIRST, "the_ring")
	sparring.refresh()
	assert_true(sparring.foe == null, "nobody steps in before Dole is asked")
	GameState.set_flag("dole_spar_ready", true)
	sparring.refresh()
	assert_true(sparring.foe != null, "asked, he steps into the ring")
	if sparring.foe == null:
		return
	assert_eq(sparring.foe.content_id(), SPARRING)
	assert_true(sparring.foe.is_hostile_to(player), "and means it")
	player.health = player.max_health * 0.3
	sparring.refresh()
	assert_true(sparring.foe == null, "beaten down, the bout ends")
	assert_true(player.is_stunned(), "off your feet")
	assert_eq(sparring.tip(), "Shield up. Up. That is your roof. Nobody fights in the rain without a roof.",
			"and told the one thing: the first lesson not yet learned")
	await _tree().create_timer(Sparring.DOWN_S + 0.2).timeout
	assert_near(player.health, player.max_health, 0.5, "helped up whole")
	sparring.phase = Sparring.Phase.IDLE
	sparring.refresh()
	assert_true(sparring.foe != null, "and again")
	Social.quests.call("set_stage", FIRST, "the_ditch")
	sparring.refresh()
	assert_true(sparring.foe == null, "the lessons done, the ring is empty")


# --- the yard, in the built world --------------------------------------------------------------------

func test_the_fort_s_yard_has_pells_to_strike_a_ring_and_the_recruit_s_place() -> void:
	if not _built():
		skip("no built world")
		return
	var w := (load("res://world/world.tscn") as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	await _tree().process_frame
	var fort: Node3D = null
	for s in _tree().get_nodes_in_group("settlement"):
		if str(s.get("place_id")) == REST:
			fort = s
	assert_true(fort != null, "Wardens' Rest is raised")
	if fort == null:
		w.queue_free()
		return
	var pells: Array = fort.find_children("Pell*", "", false, false)
	assert_eq(pells.size(), 3, "three pells in the yard")
	var ring: Vector3 = fort.call("feature_position", "ring")
	assert_ne(ring, Vector3.INF, "a ring pegged out on the square")
	var spots := {}
	for n in fort.find_children("*", "", true, false):
		if n is NpcSpot:
			spots[str(n.name)] = (n as Node3D).global_position
	for name in ["dole_yard", "tam_yard", "dole_ring", "recruit_start"]:
		assert_true(spots.has(name), "the yard marks %s" % name)
	# the opening's start is the recruit's place, said from the fort so it can be stood before the fort is
	var spawn := w.get_node("PlayerSpawn")
	var pose: Dictionary = spawn.call("pose_for", ContentDB.get_def(OPENING))
	if spots.has("recruit_start"):
		var d := Vector2((pose["pos"] as Vector3).x - (spots["recruit_start"] as Vector3).x, (pose["pos"] as Vector3).z - (spots["recruit_start"] as Vector3).z).length()
		assert_true(d < 2.5, "core:opening/warrior's start is the yard's recruit_start (%.1f m off)" % d)
	for p in pells:
		var pell := p as Pell
		assert_true(pell.is_in_group("lockable"), "a pell can be locked on to")
		assert_true(Vector2(pell.global_position.x - ring.x, pell.global_position.z - ring.z).length() > Settlement.RING_R + 1.0,
				"and stands clear of the ring")
	# a blow on a pell lands, is counted, and leaves it whole
	var pell0 := pells[0] as Pell
	var me := _me()
	var counted := [0]
	var count := func(act: String, by: Node, on: Node, _d: String) -> void:
		if act in ["parry", "block", "dodge"] or on != pell0:
			return
		counted[0] += 1
	EventBus.act_done.connect(count)
	var hit := HitData.new()
	hit.amount = 30.0
	hit.poise_damage = 40.0
	hit.attacker = me
	hit.origin = pell0.global_position + Vector3(0.0, 0.0, 1.5)
	var outcome := pell0.take_hit(hit)
	EventBus.act_done.disconnect(count)
	assert_eq(outcome, "hit", "the blow lands")
	assert_near(pell0.health, pell0.max_health, 0.01, "and the post is whole after it")
	assert_false(pell0.dead)
	w.queue_free()
	await _tree().process_frame


# --- a warrior's new game, in the built world --------------------------------------------------------

func _until(pred: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if bool(pred.call()):
			return true
		await _tree().process_frame
	return bool(pred.call())


## What the Naming writes for a warrior, and the world stood up on it: the body in the yard a pace
## from the middle pell, First Blood begun, Dole at the end of the row speaking first, and Tam at his
## pell; the kit in the hands. The film does not play headless, so the story starts at once.
func test_a_warrior_s_new_game_begins_in_the_yard_with_dole_speaking_first() -> void:
	if not _built():
		skip("no built world")
		return
	GameState.reset_for_new_game(22)
	GameState.set_flag("player_name", "Hesk of the Downs")
	GameState.set_flag("player_calling", "core:calling/hearthkeeper")
	GameState.set_flag(StyleDef.FLAG, STYLE)
	GameState.set_flag(Openings.STYLE_START, true)
	GameState.set_flag(Openings.STYLE_DUE, true)
	WorldClock.set_time(10.0)
	var w := (load("res://world/world.tscn") as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	var begun := await _until(func() -> bool: return bool(Social.quests.call("is_active", FIRST)), 10.0)
	assert_true(begun, "First Blood begins with the new game")
	assert_false(GameState.has_flag(Openings.STYLE_DUE), "and is begun once")
	assert_false(GameState.has_flag(Openings.NEW_GAME), "the wake's flag waits for the stair")
	assert_false(bool(Social.quests.call("is_active", NAMING)), "and so does the Naming")
	var player := w.get_node("PlayerSpawn").get("player") as Node3D
	var fort: Node3D = null
	for s in _tree().get_nodes_in_group("settlement"):
		if str(s.get("place_id")) == REST:
			fort = s
	var start := Vector3.INF
	for n in fort.find_children("*", "", true, false):
		if n is NpcSpot and n.name == "recruit_start":
			start = (n as Node3D).global_position
	var off := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	assert_true(off < 2.5, "the body stands at the recruit's place in the yard (%.1f m off)" % off)
	var services := _tree().get_first_node_in_group("game_services")
	var words := str(services.get("first_words"))
	assert_true(words.ends_with("Here. To me. I'll say what today's for, once."), "Sergeant Dole speaks first, and calls you over: %s" % words)
	assert_eq(str(Social.quests.call("stage_id_of", FIRST)), "hear_dole", "his word on the day is the first objective")
	var worn := player.get_node("Equipment") as Equipment
	assert_eq(str(worn.get_slot("main_hand").id), "core:item/iron_sword", "sword in hand")
	assert_eq(str(worn.get_slot("off_hand").id), "core:item/oak_round_shield", "shield on the arm")
	var dole_here := await _until(func() -> bool:
			var d := NpcRegistry.instance.actor(DOLE) as Node3D
			return d != null and d.global_position.distance_to(player.global_position) < 10.0, 20.0)
	assert_true(dole_here, "Dole stands in the yard, a few paces off")
	var tam_here := await _until(func() -> bool:
			var t := NpcRegistry.instance.actor(TAM) as Node3D
			return t != null and t.global_position.distance_to(player.global_position) < 10.0, 20.0)
	assert_true(tam_here, "and Tam at his pell")
	var pells := fort.find_children("Pell*", "", false, false)
	var nearest := INF
	for p in pells:
		nearest = minf(nearest, (p as Node3D).global_position.distance_to(player.global_position))
	assert_true(nearest < 4.0, "a pell within reach of a few steps (%.1f m)" % nearest)
	# the first lesson done, Hollin stands across the yard, on her feet, where she can be got up on
	Social.quests.call("set_stage", FIRST, "the_yard")
	for i in 3:
		Social.quests.call("complete_objective", FIRST, i)
	var hollin := await _until(func() -> bool:
			var st := Stable.find()
			return st != null and st.horses.has("core:mount/wardens_cob"), 10.0)
	assert_true(hollin, "Hollin is stood up in the world after the yard")
	if hollin:
		var horse := Stable.find().horses["core:mount/wardens_cob"] as Mount
		await _tree().create_timer(1.0).timeout
		var d := horse.global_position.distance_to(player.global_position)
		var ground := _floor_under(horse.global_position, horse)
		print("HORSE Hollin at %s, %.1f m from the recruit's place, %.2f m over the ground, water %.2f" % [horse.global_position.snapped(Vector3.ONE * 0.1), d, horse.global_position.y - ground, _water(horse.global_position)])
		assert_true(d < 30.0, "within the fort's yard (%.1f m)" % d)
		assert_true(absf(horse.global_position.y - ground) < 0.6, "standing on the ground")
		player.global_position = horse.global_position + Vector3(1.6, 0.3, 0.0)
		await _tree().process_frame
		assert_true(Rider.of(player).mount(horse), "and she can be got up on")
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame


## Down the Hushline Stair after Tam: the fortieth step plays the wake, the body is stood at the top
## where the Warden will find it, and the Naming goes on at its wake with Tam gone out of the world.
func test_the_fortieth_step_after_tam_plays_the_wake_at_the_stair_head() -> void:
	if not _built():
		skip("no built world")
		return
	GameState.reset_for_new_game(23)
	GameState.set_flag("player_name", "Hesk of the Downs")
	GameState.set_flag("player_calling", "core:calling/hearthkeeper")
	GameState.set_flag(StyleDef.FLAG, STYLE)
	GameState.set_flag(Openings.STYLE_START, true)
	WorldClock.set_time(11.0)
	var w := (load("res://world/world.tscn") as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	var player := w.get_node("PlayerSpawn").get("player") as Node3D
	Social.quests.call("start", NAMING)
	assert_eq(str(Social.quests.call("stage_id_of", NAMING)), "down_the_stair")
	var head := WorldProbe.place_position("core:poi/stair_head")
	player.call("teleport", head + Vector3(0.0, 1.0, 0.0), 0.0, "test")
	var stood := await _until(func() -> bool:
			var found := _tree().get_first_node_in_group(StairDescent.GROUP) as StairDescent
			return found != null and not found.step_at.is_empty(), 40.0)
	var descent := _tree().get_first_node_in_group(StairDescent.GROUP) as StairDescent
	stood = stood and descent != null
	assert_true(stood, "the Stair Head's stair is counted")
	if not stood:
		_tree().root.remove_child(w)
		w.queue_free()
		return
	var tam_goes := await _until(func() -> bool:
			var t := NpcRegistry.instance.actor(TAM) as Node3D
			return t != null, 20.0)
	assert_true(tam_goes, "Tam is on the stair ahead")
	var halfway := descent.point_along(descent.step_at[19])
	player.call("teleport", halfway + Vector3(0.0, 0.3, 0.0), 0.0, "test")
	await _until(func() -> bool: return descent.progress > 0.3, 5.0)
	assert_true(descent.progress > 0.3 and descent.progress < 0.8, "twenty steps down, the colour is half gone (%.2f)" % descent.progress)
	var past := descent.point_along(descent.trigger_m() + 0.6)
	player.call("teleport", past + Vector3(0.0, 0.3, 0.0), 0.0, "test")
	var woke := await _until(func() -> bool: return str(Social.quests.call("stage_id_of", NAMING)) == "wake", 20.0)
	assert_true(woke, "the fortieth step plays the wake, and the Naming is at its wake")
	assert_false(GameState.has_flag(Openings.NEW_GAME), "the wake's flag is down again once it has played")
	assert_false(GameState.has_flag(Openings.STYLE_START), "and the style's start is over")
	var start := head
	var at := player.global_position
	assert_true(Vector2(at.x - start.x, at.z - start.z).length() < 30.0, "the body is at the top of the stair, where the Warden is")
	assert_true(NpcRegistry.instance.is_gone(TAM), "Tam is not in the world")
	var services := _tree().get_first_node_in_group("game_services")
	assert_true(str(services.get("first_words")).contains("Tam Hobb. He was Dole's."), "and the Warden knows what went down: %s" % services.get("first_words"))
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame


## What a hoof stands on under a point: the world's solid floor (boards on stilts count), else the
## terrain.
func _floor_under(at: Vector3, skip: CollisionObject3D) -> float:
	var space := skip.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 6.0, 1, [skip.get_rid()]))
	if not hit.is_empty():
		return (hit["position"] as Vector3).y
	return WorldProbe.get_height(at.x, at.z, at.y)
