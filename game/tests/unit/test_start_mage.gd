extends TestCase
## The mage's start (docs/FIGHTING_STYLE_STARTS.md §3.3): the braziers below the Lamp, Jory's shingle
## and the Ward, Mend, Hush-Frost on the wreck's drakes, the smuggler-Sayers at dusk, Kettle, and The
## Note Under the Water, a listening-bell that hums louder the further south it points, to the
## Stair Head.

const STYLE := "core:style/mage"
const OPENING := "core:opening/mage"
const FIRST := "core:quest/first_mage"
const NOTE := "core:quest/the_note_under_the_water"
const NAMING := "core:quest/the_naming"
const TAMSIN := "core:npc/tamsin_wick"
const JORY := "core:npc/jory_wick"
const WREN := "core:npc/wren_tallow"
const LAMP := "core:place/the_lamp"
const BELL := "core:item/listening_bell"
const PLAYER := preload("res://actors/player/player.tscn")

var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _built() -> bool:
	return FileAccess.file_exists("res://world/generated/world_manifest.json")


func before_each() -> void:
	GameState.reset_for_new_game(41)
	Social.quests.call("reset_for_new_game")
	GameState.set_flag(StyleDef.FLAG, STYLE)
	GameState.set_flag(Openings.STYLE_START, true)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Social.quests.call("reset_for_new_game")
	GameState.reset_for_new_game(41)


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


func _player() -> Player:
	var p := PLAYER.instantiate() as Player
	_tree().root.add_child(p)
	_nodes.append(p)
	p.global_position = Vector3(6000, 0, 6000)
	return p


func _at(q: String) -> String:
	return str(Social.quests.call("stage_id_of", q))


func _done(q: String, i: int) -> bool:
	return bool((Social.quests.call("objectives_of", q) as Array)[i]["done"])


func test_the_mage_is_a_whole_style_with_its_own_start() -> void:
	var def := ContentDB.get_def(STYLE)
	assert_empty(StyleDef.validate(def, "pack"))
	assert_eq(str(Openings.for_new_game().get("id", "")), OPENING)
	var film := ContentDB.get_def(str(ContentDB.get_def(OPENING)["cinematic"]))
	assert_eq(CinematicDef.validate(film, "pack"), [] as Array[String])
	var seconds := CinematicDef.total_seconds(film)
	assert_true(seconds >= 30.0 and seconds <= 40.0, "30-40 s (%.0f s)" % seconds)
	assert_true(StyleDef.kit_words(def).begins_with("an ash staff"), StyleDef.kit_words(def))
	var kettle := ContentDB.get_def("core:mount/wicks_carthorse")
	assert_true(float((kettle["look"] as Dictionary)["scale"]) > 1.0, "a cart-horse, bigger than the cob")
	assert_eq(str(ContentDB.get_def(BELL).get("category", "")), "tool", "the bell is a thing you use")


func test_the_braziers_count_lights_by_how_far_they_were_said() -> void:
	var quests: Node = Social.quests
	assert_true(bool(quests.call("start", FIRST)))
	var me := _node("", Vector3.ZERO, true)
	var near := _node("prop:brazier", Vector3(0, 0, 9))
	var far := _node("prop:brazier", Vector3(0, 0, 20))
	EventBus.act_done.emit("kindle", me, near, "")
	assert_true(_done(FIRST, 0), "the near one lit")
	assert_false(_done(FIRST, 1), "and nine paces is not from where you stand")
	EventBus.act_done.emit("kindle", me, far, "")
	EventBus.act_done.emit("kindle", me, far, "")
	assert_eq(_at(FIRST), "the_racks", "two lit from afar: Jory and the shingle")
	assert_true(GameState.has_flag(SocialContext.MOUNT_FLAG_PREFIX + "core:mount/wicks_carthorse"), "and Kettle is the mage's from the first lesson (triage 52)")


func test_the_racks_wait_for_jory_and_count_only_what_the_ward_takes() -> void:
	var quests: Node = Social.quests
	quests.call("start", FIRST)
	quests.call("set_stage", FIRST, "the_racks")
	var sparring := Sparring.new()
	_tree().root.add_child(sparring)
	_nodes.append(sparring)
	var want: Dictionary = sparring.wanted()
	assert_eq(str((want.get("spar", {}) as Dictionary).get("enemy", "")), "core:enemy/sparring_jory", "Jory is the bout")
	assert_true(PlaceRef.is_spec((want.get("spar", {}) as Dictionary).get("at", null)), "on the shingle, with no ring")
	var me := _node("", Vector3.ZERO, true)
	EventBus.dialogue_node_entered.emit(JORY, "shingle_begin")
	assert_true(_done(FIRST, 0), "Jory asked")
	var jory := _node("core:enemy/sparring_jory", Vector3(0, 0, 11))
	var drake := _node("core:enemy/gutter_drake", Vector3(0, 0, 3))
	EventBus.act_done.emit("cast", me, null, "core:spell/ward")
	EventBus.act_done.emit("ward", me, drake, "")
	assert_false(_done(FIRST, 2), "a drake is not Jory")
	EventBus.act_done.emit("ward", me, jory, "")
	EventBus.act_done.emit("ward", me, jory, "")
	assert_true(_done(FIRST, 2), "two stones on the Ward")
	EventBus.act_done.emit("cast", me, null, "core:spell/kindle_bolt")
	assert_false(_done(FIRST, 3), "a bolt is not Mend")
	EventBus.act_done.emit("cast", me, null, "core:spell/mend")
	assert_eq(_at(FIRST), "the_racks", "and Kettle got up on once")
	EventBus.act_done.emit("mount", me, _node("core:mount/wicks_carthorse", Vector3(3, 0, 0)), "")
	assert_eq(_at(FIRST), "the_boat", "the Ward, Mend and Kettle: the smugglers")


## The Ward is a lesson because taking a blow on it says so: the `ward` act, and no harm done.
func test_a_ward_that_takes_a_blow_says_so() -> void:
	var player := _player()
	var foe := _node("core:enemy/sparring_jory", Vector3(6000, 0, 6010))
	var seen: Array = []
	var on_act := func(act: String, by: Node, on: Node, _detail: String) -> void:
		seen.append([act, by, on])
	EventBus.act_done.connect(on_act)
	var whole := player.health
	player._apply_damage(6.0, "blunt", foe, "")
	assert_true(player.health < whole, "unwarded, it hurts")
	seen.clear()
	player.add_shield(40.0, 12.0)
	whole = player.health
	player._apply_damage(6.0, "blunt", foe, "")
	EventBus.act_done.disconnect(on_act)
	assert_near(player.health, whole, 0.01, "warded, it does not")
	assert_true(seen.size() == 1 and seen[0][0] == "ward" and seen[0][1] == player and seen[0][2] == foe,
			"and the Ward says it took it: %s" % str(seen))


func test_the_racks_teach_hush_frost_and_a_style_readies_its_first_saying() -> void:
	var player := _player()
	player._ready_style_sayings(STYLE)
	assert_eq(player.equipped_spell, "", "nothing readied that is not known")
	var prog := player.get_node("Progression")
	for s in (ContentDB.get_def(STYLE)["kit"] as Dictionary)["spells"]:
		prog.call("learn_spell", str(s))
	player._ready_style_sayings(STYLE)
	assert_eq(player.equipped_spell, "core:spell/kindle_bolt", "Kindle-Bolt readied for the first lesson")
	assert_true(player.quick_slots.has("core:spell/mend") and player.quick_slots.has("core:spell/ward"), "the others on quick keys: %s" % str(player.quick_slots))
	Social.refresh_providers()
	var quests: Node = Social.quests
	quests.call("start", FIRST)
	quests.call("set_stage", FIRST, "the_racks")
	assert_false(bool(prog.call("knows_spell", "core:spell/hush_frost")), "not before the Ward and Mend")
	for i in 5:
		quests.call("complete_objective", FIRST, i)
	assert_eq(_at(FIRST), "the_boat")
	assert_true(bool(prog.call("knows_spell", "core:spell/hush_frost")), "Tamsin teaches the cold before the smugglers come")


func test_the_boat_gives_the_bell_and_the_report_hears_it_and_sends_you_south() -> void:
	var quests: Node = Social.quests
	var bag := SocialFakes.FakeInventory.new()
	Social.bind("inventory", bag)
	quests.call("start", FIRST)
	quests.call("set_stage", FIRST, "the_boat")
	quests.call("complete_objective", FIRST, 0)
	assert_eq(_at(FIRST), "report", "the smugglers down: up to Tamsin")
	assert_eq(bag.count(BELL), 1, "with the bell out of their boat")
	EventBus.dialogue_node_entered.emit(TAMSIN, "report_done")
	assert_false(bool(quests.call("is_completed", FIRST)), "shown, and not yet heard")
	EventBus.item_used.emit(BELL, [])
	assert_true(bool(quests.call("is_completed", FIRST)))
	assert_eq(_at(NOTE), "the_ride", "the bell heard: the Note begins with the ride south")
	Social.bind("inventory", null)
	Social.refresh_providers()
	var spots := {}
	for id in [TAMSIN, JORY]:
		spots[id] = str(Schedules.entry_for_def(ContentDB.get_def(id), 3, 11.0).get("spot", ""))
	assert_ne(spots[TAMSIN], "tamsin_lamp", "Tamsin goes back to her day once the bell is heard")


## The Naming offers the mage's card beside the warrior's and the ranger's; a style written but not
## yet verified (`offered: false`) stays in the pack and has no card.
func test_the_naming_offers_the_mage_and_not_a_style_held_back() -> void:
	var ids: Array = []
	for def in StyleDef.all_styles():
		ids.append(str(def["id"]))
	assert_true(ids.has(STYLE), "the mage has a card: %s" % str(ids))
	for def in ContentDB.all(StyleDef.TYPE):
		if not bool(def.get("offered", true)):
			assert_false(ids.has(str(def["id"])), "%s is held back" % str(def["id"]))


## Merrowby has no Hearthstone of its own; the stone halfway is the Wellspring's, past Ashwell, the
## one on the road nearest the ride's middle (5.4 km of 7.4).
func test_the_ride_s_stone_halfway_is_the_wellspring() -> void:
	var quests: Node = Social.quests
	quests.call("start", NOTE)
	quests.call("set_stage", NOTE, "the_wellspring")
	var stone := ""
	for o in quests.call("objectives_of", NOTE) as Array:
		if str((o as Dictionary).get("type", "")) == "rest_at":
			stone = str((o as Dictionary).get("target", ""))
	assert_eq(stone, "core:poi/the_wellspring")
	assert_true(bool(ContentDB.get_def(stone).get("hearthstone", false)), "and it is a Hearthstone")
	EventBus.place_discovered.emit("core:place/merrowby")
	EventBus.place_discovered.emit("core:poi/the_wellspring")
	EventBus.hearthstone_rested.emit("core:poi/the_wellspring")
	assert_eq(_at(NOTE), "the_stair_head", "the hand on the stone: on to the Stair")


func test_the_note_ends_at_the_stair_with_the_naming_waiting() -> void:
	var quests: Node = Social.quests
	quests.call("start", NOTE)
	quests.call("set_stage", NOTE, "the_stair_head")
	var greeting := str(Social.dialogue.call("greeting_for", WREN))
	assert_true(greeting.begins_with("Tamsin's."), "the Warden knows who sent you: " + greeting)
	EventBus.dialogue_node_entered.emit(WREN, "the_note_came")
	assert_true(bool(quests.call("is_completed", NOTE)))
	assert_eq(_at(NAMING), "down_the_stair")


## The horse given after the first lesson stands in the world near where it was given, on its feet
## and dry, and can be got up on (triage 52: "the horse early").
func _horse_stands(mount_id: String, near: Vector3, within: float, player: Node3D) -> void:
	var stood := false
	for i in 600:
		var st := Stable.find()
		if st != null and st.horses.has(mount_id):
			stood = true
			break
		await _tree().process_frame
	assert_true(stood, "%s is stood up in the world" % mount_id)
	if not stood:
		return
	var horse := Stable.find().horses[mount_id] as Mount
	await _tree().create_timer(1.0).timeout
	var d := Vector2(horse.global_position.x - near.x, horse.global_position.z - near.z).length()
	var ground := _floor_under(horse.global_position, horse)
	var t: Object = World.terrain()
	var water := float(t.call("water_depth_at", horse.global_position.x, horse.global_position.z)) if t != null and t.has_method("water_depth_at") else 0.0
	print("HORSE %s at %s, %.1f m from where it was given, %.2f m over the ground, water %.2f" % [mount_id, horse.global_position.snapped(Vector3.ONE * 0.1), d, horse.global_position.y - ground, water])
	assert_true(d < within, "%s stands near where it was given (%.1f m)" % [mount_id, d])
	assert_true(absf(horse.global_position.y - ground) < 0.6, "on its feet on the ground")
	assert_true(water < 0.3, "and dry")
	player.global_position = horse.global_position + Vector3(1.6, 0.3, 0.0)
	await _tree().process_frame
	assert_true(Rider.of(player).mount(horse), "and can be got up on")


func test_tamsin_greets_a_calling_from_far_away() -> void:
	Social.quests.call("start", FIRST)
	GameState.set_flag("player_calling", "core:calling/cragborn")
	var line := str(Social.dialogue.call("greeting_for", TAMSIN))
	assert_true(line.begins_with("Off the fells"), line)
	var spot := str(Schedules.entry_for_def(ContentDB.get_def(TAMSIN), 3, 20.0).get("spot", ""))
	assert_eq(spot, "tamsin_lamp", "held at the Lamp through the lessons, at any hour")


func _until(pred: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if bool(pred.call()):
			return true
		await _tree().process_frame
	return bool(pred.call())


## In the built world: a mage's new game stands on the shingle below the Lamp with three braziers
## down the shore, the staff in hand and Kindle-Bolt readied, Tamsin speaking first beside it; a
## brazier lit is counted.
func test_a_mage_s_new_game_begins_below_the_lamp_with_the_braziers_down_the_shore() -> void:
	if not _built():
		skip("no built world")
		return
	GameState.set_flag("player_name", "Hesk of the Mere")
	GameState.set_flag("player_calling", "core:calling/lantern_clerk")
	GameState.set_flag(Openings.STYLE_DUE, true)
	WorldClock.set_time(15.5)
	var w := (load("res://world/world.tscn") as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	var begun := await _until(func() -> bool: return bool(Social.quests.call("is_active", FIRST)), 10.0)
	assert_true(begun, "the tutorial begins")
	var player := w.get_node("PlayerSpawn").get("player") as Player
	var braziers: Array = []
	for p in _tree().get_nodes_in_group("pell"):
		if (p as Pell).kind == "brazier":
			braziers.append(p)
	assert_eq(braziers.size(), 3, "three braziers")
	var dists: Array = []
	for b in braziers:
		dists.append(snappedf(Vector2((b as Node3D).global_position.x - player.global_position.x, (b as Node3D).global_position.z - player.global_position.z).length(), 1.0))
	dists.sort()
	assert_true(dists.size() == 3 and dists[0] > 6.0 and dists[0] < 12.0 and dists[2] > 20.0 and dists[2] < 28.0,
			"at about nine, sixteen and twenty-four paces from where the body stands: %s" % str(dists))
	var ground := w.provider.get_height(player.global_position.x, player.global_position.z)
	assert_true(absf(player.global_position.y - ground) < 1.0, "on the shingle, not in the air or the Mere")
	await _tree().physics_frame
	var from := player.global_position + Vector3.UP * 1.6
	var roof := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 30.0, 1, [(player as CollisionObject3D).get_rid()]))
	assert_true(roof.is_empty(), "open sky over the body, not a house: %s" % str(roof.get("collider", "")))
	var worn := player.get_node("Equipment") as Equipment
	assert_eq(str(worn.get_slot("main_hand").id), "core:item/ash_staff", "the staff in hand")
	assert_eq(player.equipped_spell, "core:spell/kindle_bolt", "Kindle-Bolt readied")
	var services := _tree().get_first_node_in_group("game_services")
	assert_true(str(services.get("first_words")).begins_with("There's the braziers"), "Tamsin speaks first: %s" % str(services.get("first_words")))
	var tamsin_near := await _until(func() -> bool:
			var t := NpcRegistry.instance.actor(TAMSIN) as Node3D
			return t != null and t.global_position.distance_to(player.global_position) < 10.0, 20.0)
	assert_true(tamsin_near, "Tamsin stands by the Lamp's door")
	if not braziers.is_empty():
		(braziers[0] as Pell).kindle(player)
		assert_true((braziers[0] as Pell).lit, "a brazier catches")
	for i in 2:
		Social.quests.call("complete_objective", FIRST, i)
	await _horse_stands("core:mount/wicks_carthorse", QuestSpots.ensure().position_of("kettle_tether"), 9.0, player)
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
