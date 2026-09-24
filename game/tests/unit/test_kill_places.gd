extends TestCase
## A kill counts where the story puts the fight, and the stage stands up the fight it asks for.
##
## A kill objective counted a kill of its kind anywhere. The Undercroft's strongroom stage — the
## Guild's two bravos in the room behind the bell — closed on the bravos who work the Long Stride's
## toll queue, and the drakes in the crawl behind the bell on the drakes in the Gullhithe Wreck,
## because the Undercroft's own encounters were down-wolves and bandits standing in for both. Every
## authored kill objective now says `where` (KillPlaces), the Undercroft holds its drakes and its
## bravos, and where nothing stood at a place a story sends you to fight, `QuestFoes` stands it.

const KILL_AT := preload("res://tests/fixtures/kill_at.gd")
const EVERY_PRICE := "core:quest/every_price"
const AGAINST_THE_BELL := "core:quest/against_the_bell"
const THE_WRECK := "core:quest/a_thing_nobody_reported"
const A_VERSE := "core:quest/a_verse_about_you"
const COLD_FIRE := "core:quest/the_cold_fire"
const AT_THE_GATE := "core:quest/at_the_gate"
const BRIARS := "core:quest/the_briars_purpose"
const NAMING := "core:quest/the_naming"
const HART := "core:boss/hart_of_thorns"

var log_node: Node
var player: SocialFakes.FakePlayer
var foes: QuestFoes
var body: Node3D
var spawned: Array[Node] = []


func before_each() -> void:
	log_node = Social.quests
	GameState.reset_for_new_game(1)
	log_node.reset_for_new_game()
	Social.factions.reset_for_new_game()
	player = SocialFakes.FakePlayer.new()
	Social.bind("player", player)
	Interiors.current_id = ""
	WorldClock.set_time(12.0, 2)


func after_each() -> void:
	log_node.reset_for_new_game()
	Social.factions.reset_for_new_game()
	Social.bind("player", null)
	Social.refresh_providers()
	Interiors.current_id = ""
	for n in spawned:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	spawned.clear()
	if foes != null and is_instance_valid(foes):
		foes.get_parent().remove_child(foes)
		foes.free()
	foes = null
	if body != null and is_instance_valid(body):
		body.get_parent().remove_child(body)
		body.free()
	body = null
	GameState.clear_flag("boss_deed/" + HART)
	WorldClock.set_time(9.0, 2)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## The quest started and moved to the stage that asks for the kill, its gate opened the way a
## player opens it: the quests before it finished, the standing it asks for earned.
func _at(quest_id: String, stage_id: String) -> void:
	_open_gate(quest_id)
	assert_true(log_node.start(quest_id), "%s starts" % quest_id)
	log_node.set_stage(quest_id, stage_id)
	assert_eq(log_node.stage_id_of(quest_id), stage_id)


func _open_gate(quest_id: String) -> void:
	for c in ContentDB.get_or_empty(quest_id).get("requires", []):
		var cond: Dictionary = c
		if cond.has("quest_done"):
			var before := str(cond["quest_done"])
			if not log_node.is_completed(before):
				_open_gate(before)
				log_node.start(before)
				log_node.complete(before)
		elif cond.has("rep_min"):
			Social.factions.set_reputation(str(cond["rep_min"][0]), int(cond["rep_min"][1]))
		elif cond.has("flag"):
			GameState.set_flag(str(cond["flag"]))


## How far the kill objective of the quest's current stage has come.
func _kills(quest_id: String) -> int:
	for entry in log_node.current_objectives("kill"):
		if str(entry["quest_id"]) == quest_id:
			return int(entry["progress"])
	return -1


func _place_xz(place_id: String) -> Vector3:
	var xz := WorldProbe.xz_of(ContentDB.get_or_empty(place_id))
	return Vector3(xz.x, 0.0, xz.y)


# --- where a kill counts --------------------------------------------------------------------------

func test_the_guilds_bravos_are_not_the_ones_at_the_long_stride() -> void:
	_at(EVERY_PRICE, "the_strongroom")
	KILL_AT.emit("core:enemy/bravo", "core:poi/long_stride", 2)
	assert_eq(_kills(EVERY_PRICE), 0, "two bravos put down at the Long Stride closed the strongroom")
	KILL_AT.emit("core:enemy/bravo", "core:interior/undercroft", 2)
	assert_eq(_kills(EVERY_PRICE), 2, "the two in the room behind the bell count")


func test_the_drakes_behind_the_bell_are_not_the_ones_in_the_gullhithe_wreck() -> void:
	_at(AGAINST_THE_BELL, "behind_the_bell")
	KILL_AT.emit("core:enemy/gutter_drake", "core:poi/gullhithe_wreck", 4)
	assert_eq(_kills(AGAINST_THE_BELL), 0, "the wreck's drakes cleared the crawl under Tollmere")
	KILL_AT.emit("core:enemy/gutter_drake", "core:interior/undercroft", 4)
	# four in the crawl close it, and with the Undercroft already known the stage is behind you
	assert_true(_kills(AGAINST_THE_BELL) == 4 or log_node.stage_id_of(AGAINST_THE_BELL) != "behind_the_bell",
			"the four in the crawl count")


## The Undercroft holds what its stages ask for: the recipe's notes said drakes and the Guild's men,
## and the forge had put down-wolves and roadside bandits there because the bestiary had nothing else.
func test_the_undercroft_holds_its_drakes_and_its_bravos() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			str(ContentDB.get_or_empty("core:interior/undercroft").get("meta", ""))))
	var held: Dictionary = {}
	for e in meta.get("encounters", []):
		var id := str((e as Dictionary).get("enemy", ""))
		held[id] = int(held.get(id, 0)) + int((e as Dictionary).get("count", 1))
	assert_true(int(held.get("core:enemy/gutter_drake", 0)) >= 4, "drakes in the crawl: %s" % str(held))
	assert_true(int(held.get("core:enemy/bravo", 0)) >= 2, "the Guild's two bravos: %s" % str(held))
	assert_false(held.has("core:enemy/down_wolf"), "no stand-in wolves left under Tollmere")


## A kill with no body to ask (a script, the debug console) is placed by the player: where they
## stand, and the interior they are in.
func test_a_kill_with_no_body_is_where_the_player_is() -> void:
	_at(EVERY_PRICE, "the_strongroom")
	player.pos = _place_xz("core:poi/long_stride")
	EventBus.entity_killed.emit(null, null, "core:enemy/bravo")
	assert_eq(_kills(EVERY_PRICE), 0, "counted in the open at the Long Stride")
	Interiors.current_id = "core:interior/undercroft"
	EventBus.entity_killed.emit(null, null, "core:enemy/bravo")
	assert_eq(_kills(EVERY_PRICE), 1, "counted with the player standing in the Undercroft")


## A place in the open counts within the objective's radius of it, and not in a deep place's pocket.
func test_a_place_counts_near_it_and_not_down_a_hole() -> void:
	var o := {"type": "kill", "target": "core:enemy/wisp", "where": "core:poi/wisp_hollow"}
	var at := _place_xz("core:poi/wisp_hollow")
	body = Node3D.new()
	_tree().root.add_child(body)
	body.global_position = at + Vector3(30.0, 0.0, -20.0)
	assert_true(KillPlaces.counts(o, body, null), "36 m from the hollow is at the hollow")
	body.global_position = at + Vector3(400.0, 0.0, 0.0)
	assert_false(KillPlaces.counts(o, body, null), "400 m off is not")
	body.global_position = at
	body.set_meta("interior_id", "core:interior/sunken_barge")
	assert_false(KillPlaces.counts(o, body, null), "a body in a deep place's pocket is not in the open")


## A job board's hunt ("on the Hearthvale roads") counts in its region.
func test_a_hunt_counts_in_its_region() -> void:
	var o := {"type": "kill", "target": "core:enemy/down_wolf", "region": "core:region/hearthvale"}
	var here := WorldProbe.xz_of(ContentDB.get_or_empty("core:region/hearthvale").get("map", {}), "center")
	var there := WorldProbe.xz_of(ContentDB.get_or_empty("core:region/skerrow").get("map", {}), "center")
	body = Node3D.new()
	_tree().root.add_child(body)
	body.global_position = Vector3(here.x, 0.0, here.y)
	assert_true(KillPlaces.counts(o, body, null), "a wolf in Hearthvale")
	body.global_position = Vector3(there.x, 0.0, there.y)
	assert_false(KillPlaces.counts(o, body, null), "a wolf in Skerrow")


## Every authored kill objective says where its stage puts the fight; a job board's says its region.
func test_every_authored_kill_says_where() -> void:
	var kills := 0
	for def in ContentDB.all("quest"):
		if def.has("template"):
			continue
		for stage in def.get("stages", []):
			for o in (stage as Dictionary).get("objectives", []):
				if str((o as Dictionary).get("type", "")) != "kill":
					continue
				kills += 1
				assert_true((o as Dictionary).has("where"), "%s / %s kills %s anywhere at all" % [def["id"],
						(stage as Dictionary).get("id", ""), (o as Dictionary).get("target", "")])
	assert_gt(kills, 20, "the pack's kill objectives were read")


# --- a boss put down before its stage ---------------------------------------------------------------

## The Hart stands in the Moot from the first day. A player who put him down before the main thread
## asked had killed the one foe its fourth stage could be closed on.
func test_a_boss_put_down_early_closes_its_stage_on_entry() -> void:
	GameState.set_flag("boss_deed/" + HART)
	_at(BRIARS, "the_hart")
	assert_eq(_kills(BRIARS), 1, "the Hart, already down, is counted when the stage opens")


# --- the stage stands the fight up ---------------------------------------------------------------------

func _foes_at(place_id: String) -> void:
	foes = QuestFoes.new()
	foes.enabled = false
	_tree().root.add_child(foes)
	var at := _place_xz(place_id)
	foes.cell_ready(WorldProbe.cell_of(at))
	player.pos = at
	var standing := Node3D.new()
	standing.add_to_group("player")
	_tree().root.add_child(standing)
	standing.global_position = at + Vector3(0.0, 0.0, 60.0)
	spawned.append(standing)


func _key(quest_id: String) -> String:
	for entry in log_node.current_objectives("kill"):
		if str(entry["quest_id"]) == quest_id:
			return "%s|%d|%d" % [quest_id, int(entry["stage"]), int(entry["index"])]
	return ""


## Where nothing stood — no sayer ever stood at the Gullhithe Wreck — the stage stands both.
func test_the_wreck_gets_its_two_sayers() -> void:
	_at(THE_WRECK, "the_wreck")
	_foes_at("core:poi/gullhithe_wreck")
	foes.refresh()
	var group := foes.group_for(_key(THE_WRECK))
	assert_true(group != null, "nothing was stood up at the wreck")
	if group == null:
		return
	var sayers := group.all()
	assert_eq(sayers.size(), 2, "two sayers on the wreck")
	var at := _place_xz("core:poi/gullhithe_wreck")
	for s in sayers:
		assert_eq(s.content_id(), "core:enemy/smuggler_sayer")
		var flat := Vector2(s.global_position.x - at.x, s.global_position.z - at.z).length()
		assert_true(flat <= QuestFoes.RING_MAX_M + 0.5, "a sayer stands %.0f m from the wreck" % flat)
	# they are what the objective is closed on
	for s in sayers:
		s.die(null)
	assert_eq(_kills(THE_WRECK), 2, "the two stood up for the stage close it")
	# and once the stage has moved on and the player has walked away, they go
	for n in _tree().get_nodes_in_group("player"):
		(n as Node3D).global_position = at + Vector3(QuestFoes.LEAVE_M + 50.0, 0.0, 0.0)
	foes.refresh()
	assert_true(foes.group_for(_key(THE_WRECK)) == null, "the group outlived its fight")


## What already stands is counted first: the Tumbled Watch keeps its own five, and gets none.
func test_the_tumbled_watch_is_not_doubled() -> void:
	_at(A_VERSE, "the_road")
	_foes_at("core:poi/tumbled_watchtower")
	var at := _place_xz("core:poi/tumbled_watchtower")
	var hall := EnemySpawner.new()
	hall.spawn_on_ready = false
	hall.drop_to_ground = false
	_tree().root.add_child(hall)
	spawned.append(hall)
	for k in 5:
		hall.spawn_one("core:enemy/roadside_bandit", at + Vector3(float(k) * 2.0, 0.0, 6.0), 0.0)
	foes.refresh()
	var group := foes.group_for(_key(A_VERSE))
	assert_true(group == null or group.all().is_empty(), "five standing, and the stage stood more")
	# three of them fell somewhere else long ago: the stage stands the three it is short
	foes.free()
	for k in 3:
		(hall.all()[k] as Enemy).dead = true
	_foes_at("core:poi/tumbled_watchtower")
	foes.refresh()
	group = foes.group_for(_key(A_VERSE))
	assert_true(group != null and group.all().size() == 3, "two standing of five: the stage stands three")


## "Six more are sitting in the ring now, in newer grey": the Cold Fire's own six are not them.
func test_the_newer_six_are_their_own() -> void:
	_at(COLD_FIRE, "the_camp")
	_foes_at("core:poi/cold_fire_camp")
	var at := _place_xz("core:poi/cold_fire_camp")
	var ring := EnemySpawner.new()
	ring.spawn_on_ready = false
	ring.drop_to_ground = false
	_tree().root.add_child(ring)
	spawned.append(ring)
	for k in 6:
		ring.spawn_one("core:enemy/ash_wight", at + Vector3(float(k), 0.0, 3.0), 0.0)
	foes.refresh()
	var group := foes.group_for(_key(COLD_FIRE))
	assert_true(group != null and group.all().size() == 6, "the newer six were not stood up beside the old ring")


## A landmark's collision is its mesh's surface, so a spot inside the Choir's colossus touched
## nothing and was called clear: two of the Naming's three ash-wights were stood inside its robe,
## nine and eleven metres from its middle, where nobody could reach them and the Naming could not be
## finished. The colossus here is built as the streamer builds it, a trimesh of a cone as wide at the
## foot as the forge's; every wight must stand outside it.
func test_nobody_is_stood_inside_the_choir_s_colossus() -> void:
	_at(NAMING, "ash_wights")
	_foes_at("core:place/sunken_choir")
	var at := _place_xz("core:place/sunken_choir")
	var robe := 13.5
	_solid(at, robe, 7.0, 50.0)
	await _tree().physics_frame
	await _tree().physics_frame
	foes.refresh()
	var group := foes.group_for(_key(NAMING))
	assert_true(group != null and group.all().size() == 3, "the Naming's three ash-wights are stood at the Choir")
	if group == null:
		return
	for wight in group.all():
		var flat := Vector2(wight.global_position.x - at.x, wight.global_position.z - at.z).length()
		assert_gt(flat, robe, "an ash-wight stands %.1f m from the colossus's middle, inside its robe" % flat)


## A ring with no room stands its fight further out, never at the middle: the middle of a landmark
## is inside it, and a fight stood there cannot be finished. Held at the Choir, with its colossus
## grown to cover the whole ring, and at the Headless Watch, with a crag under the tower as wide as
## the ring. Every spot must be clear of the solid, outside it, and still where the kill counts.
func test_a_ring_with_no_room_stands_its_fight_further_out() -> void:
	foes = QuestFoes.new()
	foes.enabled = false
	_tree().root.add_child(foes)
	var wide := QuestFoes.RING_MAX_M + 2.0
	var places := ["core:place/sunken_choir", "core:poi/headless_watch"]
	var middles: Array[Vector3] = []
	for place in places:
		var at := KillPlaces.place_position({"where": place})
		middles.append(at)
		_solid(at, wide, 6.0, 40.0)
	await _tree().physics_frame
	await _tree().physics_frame
	for i in places.size():
		var at := middles[i]
		var spots := foes.clear_ground("test|%s" % places[i], at, 3)
		assert_eq(spots.size(), 3, "%s gets its three" % places[i])
		for spot in spots:
			var flat := Vector2(spot.x - at.x, spot.z - at.z).length()
			assert_gt(flat, wide, "%s: a foe stands %.1f m out, inside the solid" % [places[i], flat])
			assert_true(flat <= KillPlaces.RADIUS_M, "%s: and within %.0f m, where the kill counts (%.1f m)" % [places[i], KillPlaces.RADIUS_M, flat])
			assert_false(foes._blocked(spot), "%s: and the spot is clear" % places[i])


## A hollow cone standing on the ground at `at`, built the way the streamer builds a landmark's
## collision: a trimesh of its mesh, a surface with nothing inside it.
func _solid(at: Vector3, foot: float, top: float, height: float) -> StaticBody3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = foot
	mesh.top_radius = top
	mesh.height = height
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	var body := StaticBody3D.new()
	body.add_child(shape)
	_tree().root.add_child(body)
	spawned.append(body)
	body.global_position = Vector3(at.x, WorldProbe.get_height(at.x, at.z, at.y) + height * 0.5, at.z)
	return body


## "The choristers come to the ring on a full night": not at noon.
func test_the_choristers_keep_their_hour() -> void:
	_at(AT_THE_GATE, "the_ring")
	_foes_at("core:place/sunken_choir")
	foes.refresh()
	assert_true(foes.group_for(_key(AT_THE_GATE)) == null, "choristers at the ring at noon")
	WorldClock.set_time(23.5, 2)
	foes.refresh()
	var group := foes.group_for(_key(AT_THE_GATE))
	assert_true(group != null and group.all().size() == 2, "two choristers at the ring after dark")
