extends TestCase
## The ranger's start (docs/FIGHTING_STYLE_STARTS.md §3.2): the butts behind Fernhold, the morning
## walk on the Briar with Alder, the weaver in Fern Gully, the thornhounds at Wold Force with Rosen
## watching, the pony, and The Grey Hart, a lead that keeps ahead by road to the Stair Head and goes
## down it.

const STYLE := "core:style/ranger"
const OPENING := "core:opening/ranger"
const FIRST := "core:quest/first_ranger"
const HART := "core:quest/the_grey_hart"
const NAMING := "core:quest/the_naming"
const ROSEN := "core:npc/rosen_wyke"
const ALDER := "core:npc/alder_wyke"
const WREN := "core:npc/wren_tallow"
const FERNHOLD := "core:place/fernhold"
const PLAYER := preload("res://actors/player/player.tscn")

var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _built() -> bool:
	return FileAccess.file_exists("res://world/generated/world_manifest.json")


func before_each() -> void:
	GameState.reset_for_new_game(31)
	Social.quests.call("reset_for_new_game")
	GameState.set_flag(StyleDef.FLAG, STYLE)
	GameState.set_flag(Openings.STYLE_START, true)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Social.quests.call("reset_for_new_game")
	GameState.reset_for_new_game(31)


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


func test_the_ranger_is_a_whole_style_with_its_own_start() -> void:
	var def := ContentDB.get_def(STYLE)
	assert_empty(StyleDef.validate(def, "pack"))
	assert_eq(str(Openings.for_new_game().get("id", "")), OPENING)
	var film := ContentDB.get_def(str(ContentDB.get_def(OPENING)["cinematic"]))
	assert_eq(CinematicDef.validate(film, "pack"), [] as Array[String])
	var seconds := CinematicDef.total_seconds(film)
	assert_true(seconds >= 30.0 and seconds <= 40.0, "30-40 s (%.0f s)" % seconds)
	assert_eq(StyleDef.kit_words(def), "a hunting bow, 40 iron arrows and a hunting knife")
	var pony := ContentDB.get_def("core:mount/rosen_pony")
	assert_lt_or_eq(float((pony["look"] as Dictionary)["scale"]), 0.9, "a pony, smaller than the cob")


func assert_lt_or_eq(a: float, b: float, msg := "") -> void:
	assert_true(a <= b, "%s (%s > %s)" % [msg, str(a), str(b)])


func test_the_butts_count_hits_by_how_far_they_were_shot() -> void:
	var quests: Node = Social.quests
	assert_true(bool(quests.call("start", FIRST)))
	var me := _node("", Vector3.ZERO, true)
	var near := _node("prop:butt", Vector3(0, 0, 20))
	var far := _node("prop:butt", Vector3(0, 0, 50))
	var wolf := _node("core:enemy/down_wolf", Vector3(0, 0, 50))
	EventBus.act_done.emit("arrow_hit", me, wolf, "")
	assert_eq(int((quests.call("objectives_of", FIRST) as Array)[0]["count"]), 0, "a wolf is not a butt")
	EventBus.act_done.emit("arrow_hit", me, near, "")
	EventBus.act_done.emit("arrow_hit", me, near, "")
	assert_true(bool((quests.call("objectives_of", FIRST) as Array)[0]["done"]), "two on the near butt")
	assert_false(bool((quests.call("objectives_of", FIRST) as Array)[1]["done"]), "and twenty paces is not thirty-five")
	EventBus.act_done.emit("arrow_hit", me, far, "")
	assert_eq(_at(FIRST), "the_briar", "the far butt counts for the middle and the far: the Briar")


func test_the_walk_and_the_report_give_the_pony_and_the_hart() -> void:
	var quests: Node = Social.quests
	quests.call("start", FIRST)
	quests.call("set_stage", FIRST, "the_briar")
	var me := _node("", Vector3.ZERO, true)
	EventBus.act_done.emit("sneak", me, null, "")
	EventBus.dialogue_node_entered.emit(ALDER, "count_the_grey")
	assert_eq(_at(FIRST), "the_gully", "quiet, and the count seen: the gully")
	assert_true(GameState.has_flag("seen_briar_grey"), "Alder's own lines know it")
	quests.call("set_stage", FIRST, "report")
	EventBus.dialogue_node_entered.emit(ROSEN, "report_done")
	assert_true(bool(quests.call("is_completed", FIRST)))
	assert_true(GameState.has_flag(SocialContext.MOUNT_FLAG_PREFIX + "core:mount/rosen_pony"), "Nettle is the ranger's")
	assert_eq(_at(HART), "the_hart")
	var spots := {}
	for id in [ROSEN, ALDER]:
		spots[id] = str(Schedules.entry_for_def(ContentDB.get_def(id), 3, 11.0).get("spot", ""))
	assert_eq(spots[ALDER], "alder_lodge", "Alder watches the hart from the lodge")


func test_the_hart_is_led_by_road_and_down_the_stair() -> void:
	var quests: Node = Social.quests
	var leads := Leads.new()
	_tree().root.add_child(leads)
	_nodes.append(leads)
	assert_true(leads.wanted().is_empty(), "no hart before the quest")
	quests.call("start", HART)
	var spec: Dictionary = leads.wanted().get("grey_hart", {})
	assert_eq(leads.way_of(spec).size(), 1, "at first it stands at the clearing's edge")
	quests.call("set_stage", HART, "follow")
	spec = leads.wanted().get("grey_hart", {})
	if not _built():
		return
	var way := leads.way_of(spec)
	var length := 0.0
	for i in range(way.size() - 1):
		length += Vector2(way[i].x, way[i].z).distance_to(Vector2(way[i + 1].x, way[i + 1].z))
	assert_true(length > 8500.0 and length < 11000.0, "by road to the Stair Head: %.0f m" % length)
	var end := way[way.size() - 1]
	var head := PlaceRef.xz("core:poi/stair_head")
	assert_true(Vector2(end.x, end.z).distance_to(head) < 20.0, "and it ends at the camp")
	quests.call("set_stage", HART, "the_stair_head")
	EventBus.dialogue_node_entered.emit(WREN, "the_hart_came")
	assert_true(bool(quests.call("is_completed", HART)))
	assert_eq(_at(NAMING), "down_the_stair")
	spec = leads.wanted().get("grey_hart", {})
	assert_eq(str(spec.get("way", "")), "descent", "and then it goes down the stair")


func test_rosen_shoots_only_when_you_are_hurt() -> void:
	var quests: Node = Social.quests
	quests.call("start", FIRST)
	quests.call("set_stage", FIRST, "the_force")
	var player := PLAYER.instantiate() as Actor
	_tree().root.add_child(player)
	_nodes.append(player)
	player.global_position = Vector3(6000, 0, 6000)
	var spawner := EnemySpawner.new()
	spawner.spawn_on_ready = false
	_tree().root.add_child(spawner)
	_nodes.append(spawner)
	var hound := spawner.spawn_one("core:enemy/thornhound", player.global_position + Vector3(4, 0, 0), 0.0)
	var watch := Overwatch.new()
	_tree().root.add_child(watch)
	_nodes.append(watch)
	assert_true(watch.refresh() == null, "whole, she holds")
	var before := hound.health
	player.health = player.max_health * 0.3
	assert_true(watch.refresh() == hound, "hurt, she shoots the nearest hound")
	assert_true(hound.health < before, "and it lands")
	assert_true(GameState.has_flag("rosen_shot_for_you"))
	assert_true(watch.refresh() == null, "and not again at once")


func test_rosen_greets_a_calling_from_far_away() -> void:
	Social.quests.call("start", FIRST)
	GameState.set_flag("player_calling", "core:calling/cragborn")
	var line := str(Social.dialogue.call("greeting_for", ROSEN))
	assert_true(line.begins_with("You're a long way from the fells, Cragborn. The wood won't mind."), line)


## In the built world: a ranger's new game stands on the line with three butts down the range and
## Rosen beside the line, and a butt struck by an arrow is counted.
func test_a_ranger_s_new_game_begins_on_the_line_with_the_butts_down_the_range() -> void:
	if not _built():
		skip("no built world")
		return
	GameState.set_flag("player_name", "Hesk of the Wold")
	GameState.set_flag("player_calling", "core:calling/wayfarer")
	GameState.set_flag(Openings.STYLE_DUE, true)
	WorldClock.set_time(9.0)
	var w := (load("res://world/world.tscn") as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	var begun := false
	for i in 300:
		if bool(Social.quests.call("is_active", FIRST)):
			begun = true
			break
		await _tree().process_frame
	assert_true(begun, "the tutorial begins")
	var player := w.get_node("PlayerSpawn").get("player") as Node3D
	var butts: Array = []
	for p in _tree().get_nodes_in_group("pell"):
		if (p as Pell).kind == "butt":
			butts.append(p)
	assert_eq(butts.size(), 3, "three butts")
	var dists: Array = []
	for b in butts:
		dists.append(snappedf(Vector2((b as Node3D).global_position.x - player.global_position.x, (b as Node3D).global_position.z - player.global_position.z).length(), 1.0))
	dists.sort()
	assert_true(dists.size() == 3 and dists[0] > 17.0 and dists[0] < 23.0 and dists[2] > 46.0 and dists[2] < 54.0,
			"at about twenty, thirty-five and fifty paces from where the body stands: %s" % str(dists))
	var worn := player.get_node("Equipment") as Equipment
	assert_eq(str(worn.get_slot("main_hand").id), "core:item/hunting_bow", "the bow in hand")
	assert_eq(str(worn.quick_item("quick_4")), "core:item/hunting_knife", "the knife on a quick key")
	(player as Player).use_quick_slot(3)
	assert_eq(str(worn.get_slot("main_hand").id), "core:item/hunting_knife", "the key takes the knife into the hand")
	(player as Player).use_quick_slot(3)
	assert_eq(str(worn.get_slot("main_hand").id), "core:item/hunting_bow", "and gives the bow back")
	var rosen_near := false
	for i in 600:
		var r := NpcRegistry.instance.actor(ROSEN) as Node3D
		if r != null and r.global_position.distance_to(player.global_position) < 8.0:
			rosen_near = true
			break
		await _tree().process_frame
	assert_true(rosen_near, "Rosen stands by the line")
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame
