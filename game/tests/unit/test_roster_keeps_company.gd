extends TestCase
## Somebody the player is with stays. The roster looks at everybody's day every ten game-minutes
## and on the hour, and a body whose day has moved it out of the loaded cells is taken away, one
## whose marker comes up is put down on it, and one who goes indoors is taken away at once. In a
## loaded run of the suite a single step of the clock crossed an hour, and the Warden went from
## beside her fire in the middle of a conversation with the Foundling (test_talk_to_the_warden).
## Now nobody the player is talking to, has in the interact prompt, a quest is waiting on, or is
## standing within NpcRegistry.KEEP_NEAR_M of, is taken away or put down elsewhere by the roster:
## the day moves on in the roster, and they finish talking and walk.

const WREN := "core:npc/wren_tallow"
const NAMING := "core:quest/the_naming"
## Tollday: the Warden eats in the hall at the Wardens' Rest from two, and is on the crater rim at
## Merrowby at four, walking the road between.
const TOLLDAY := 7
## A weekday: counting the bells in Merrowby from seven, in bed at nine.
const KINDLEDAY := 1
const A_WORD := {
	"id": "test:dialogue/a_word_with_the_warden",
	"start": "hello",
	"nodes": {
		"hello": {"speaker": "Wren Tallow", "text": "A moment. The hour's turning.",
				"choices": [{"text": "Go on.", "next": "bye"}]},
		"bye": {"speaker": "Wren Tallow", "text": "Mind the road."},
	},
}

var registry: NpcRegistry
var host: Node3D
var _made_streamer: NpcStreamer = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	# her own days, not the story's: nothing holds her at the Stair Head (her def's `holds`)
	Social.reset_for_new_game()
	GameState.set_flag("new_game", false)
	GameState.set_flag("_weather", "clear")
	# out of doors: the streamer stands up only a building's own people while the player is inside
	GameState.current_interior_id = ""
	WorldClock.running = false
	registry = NpcRegistry.ensure()
	registry.despawn_all()
	registry.loaded_cells.clear()
	registry.states.clear()
	registry.abstract_only = false
	registry.spawning_enabled = true
	registry.rebuild()
	var streamer := _tree().get_first_node_in_group(NpcStreamer.GROUP)
	if streamer != null:
		streamer.set("enabled", false)
	host = Node3D.new()
	host.name = "RosterTestHost"
	host.add_to_group("world_dynamic")
	_tree().root.add_child(host)


func after_each() -> void:
	if bool(Social.dialogue.call("is_running")):
		Social.dialogue.call("stop")
	registry.despawn_all()
	registry.loaded_cells.clear()
	registry.states.clear()
	registry.rebuild()
	if _made_streamer != null and is_instance_valid(_made_streamer):
		_made_streamer.queue_free()
	_made_streamer = null
	if is_instance_valid(host):
		_tree().root.remove_child(host)
		host.queue_free()
	Social.reset_for_new_game()
	WorldClock.running = true
	WorldClock.set_time(8.0, 1)


## The last five minutes on `day` before `until` at which her schedule still has her at `place`,
## scanning back from `until`; -1 when it never does.
func _last_hour_at(day: int, place: String, from_hour: float, until: float) -> float:
	var def := ContentDB.get_or_empty(WREN)
	var h := until
	while h >= from_hour:
		if str(Schedules.entry_for_def(def, day, h, "clear").get("place", "")) == place:
			return h
		h -= 1.0 / 12.0
	return -1.0


## Stands her up at the clock's hour, with the player's stand-in `d` metres off.
func _stand_her_up(d: float) -> Dictionary:
	registry.simulate_all("clear")
	var body := registry.spawn(WREN) as Node3D
	if body == null:
		return {}
	for i in 3:
		await _tree().physics_frame
	var player := Node3D.new()
	player.name = "StandIn"
	player.add_to_group("player")
	host.add_child(player)
	player.global_position = body.global_position + Vector3(d, 0.0, 0.0)
	return {"body": body, "player": player}


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## Whether the body stood up for her is still the one the registry has, and still in the world.
## Untyped: a body the roster took away is a freed object by now.
func _still_her(body: Variant) -> bool:
	if not is_instance_valid(body):
		return false
	var node := body as Node3D
	return node != null and registry.actor(WREN) == node and not node.is_queued_for_deletion() and node.is_inside_tree()


func test_the_warden_stays_while_she_talks_across_a_schedule_boundary() -> void:
	var rest := "core:place/wardens_rest"
	var t0 := _last_hour_at(TOLLDAY, rest, 14.0, 16.0)
	assert_true(t0 > 0.0, "on a Tollday afternoon her day has her at the Wardens' Rest, then on the road to Merrowby")
	if t0 < 0.0:
		return
	WorldClock.set_time(t0, TOLLDAY)
	var stood: Dictionary = await _stand_her_up(2.5)
	assert_false(stood.is_empty(), "the Warden is stood up")
	if stood.is_empty():
		return
	var body: Node3D = stood["body"]
	var player: Node3D = stood["player"]
	# as the interact key does (Npc.interact), with a line of the test's own rather than hers
	body.call("stop")
	body.call("face_direction", player.global_position - body.global_position)
	Social.dialogue.call("start_def", A_WORD, WREN, rest)
	assert_true(NpcRegistry.is_talking(WREN), "and talking to the player")
	var before := body.global_position

	# the loaded run's step: the clock crosses her hour in one look, and none of the ground she is
	# going to is loaded (a body the roster had followed there was taken away)
	registry.loaded_cells.clear()
	WorldClock.set_time(t0 + 0.75, TOLLDAY)
	registry.simulate_all("clear")
	registry._on_cell_unloaded(registry.cell_of(WREN))
	for i in 30:
		await _tree().physics_frame
	assert_ne(registry.place_of(WREN), rest, "her day has moved on (%s)" % registry.place_of(WREN))
	if not _still_her(body):
		fail("the Warden went while she talked, as her day moved on to %s" % registry.place_of(WREN))
		return
	assert_true(_flat(body.global_position, before) < 0.5,
			"not put down anywhere else while she talks (moved %.1f m)" % _flat(body.global_position, before))
	assert_false(bool(body.get("has_target")), "nor walking off in the middle of it")

	# the conversation over, she goes: walking, from where she stood
	Social.dialogue.call("stop")
	if not _still_her(body):
		fail("the Warden went from beside the player when the talk was over")
		return
	assert_true(bool(body.get("has_target")), "she is sent on to where her day has got to")
	for i in 40:
		await _tree().physics_frame
	if not _still_her(body):
		fail("the Warden went, rather than walking off")
		return
	assert_true(_flat(body.global_position, before) > 0.3,
			"off from where she stood (%.1f m)" % _flat(body.global_position, before))
	player.global_position += Vector3(500.0, 0.0, 0.0)
	assert_false(registry.is_kept(WREN), "once the player has gone the roster is free to take her")


## Bedtime beside the player: the streamer takes somebody going indoors away at once, and did so
## a step from the player. At the player's elbow they walk to where their day sends them and go in
## there; talking to the player, they finish first.
func test_somebody_going_to_bed_at_the_players_elbow_walks_in_rather_than_vanishing() -> void:
	var streamer := _streamer_by_hand()
	var stood: Dictionary = await _counting_the_bells(3.0)
	if stood.is_empty():
		return
	var body: Node3D = stood["body"]
	WorldClock.set_time(21.1, KINDLEDAY)
	registry.simulate_all("clear")
	streamer.refresh()
	assert_true(registry.is_indoors(WREN), "at nine her day has her in bed")
	assert_true(_still_her(body), "with the player three metres off she is not taken away in front of them")
	assert_true(bool(body.get("has_target")), "she walks to where her day sends her")
	assert_true(await _until_arrived(body), "and gets there")
	streamer.refresh()
	assert_false(registry.is_spawned(WREN), "and goes in there")


func test_somebody_talking_at_bedtime_finishes_before_they_go_in() -> void:
	var streamer := _streamer_by_hand()
	var stood: Dictionary = await _counting_the_bells(3.0)
	if stood.is_empty():
		return
	var body: Node3D = stood["body"]
	body.call("stop")
	Social.dialogue.call("start_def", A_WORD, WREN, "core:place/merrowby")
	WorldClock.set_time(21.1, KINDLEDAY)
	registry.simulate_all("clear")
	for i in 20:
		await _tree().physics_frame
	streamer.refresh()
	assert_true(registry.is_indoors(WREN), "at nine her day has her in bed")
	assert_true(_still_her(body), "and while she is talking to the player she stays")
	Social.dialogue.call("stop")
	streamer.refresh()
	assert_true(_still_her(body), "when the talk is over she does not vanish at the player's elbow")
	assert_true(await _until_arrived(body), "she walks to where her day sends her")
	streamer.refresh()
	assert_false(registry.is_spawned(WREN), "and goes in there")


## Once the player has left somebody going in, they go in at once, walking or not.
func test_somebody_going_to_bed_goes_in_once_the_player_has_gone() -> void:
	var streamer := _streamer_by_hand()
	var stood: Dictionary = await _counting_the_bells(3.0)
	if stood.is_empty():
		return
	var player: Node3D = stood["player"]
	WorldClock.set_time(21.1, KINDLEDAY)
	registry.simulate_all("clear")
	player.global_position += Vector3(4.0 * NpcRegistry.KEEP_NEAR_M, 0.0, 0.0)
	streamer.refresh()
	assert_false(registry.is_spawned(WREN), "with the player gone, she goes in")


## The streamer follows the first body in the player group. A stand-in some other system left in
## the group, far off, is no reason to take away the person the player is standing beside.
func test_a_stand_in_left_in_the_player_group_does_not_take_away_the_person_beside_the_player() -> void:
	var streamer := _streamer_by_hand()
	var left_behind := Node3D.new()
	left_behind.name = "LeftBehind"
	left_behind.add_to_group("player")
	host.add_child(left_behind)
	var stood: Dictionary = await _counting_the_bells(3.0)
	if stood.is_empty():
		return
	var body: Node3D = stood["body"]
	left_behind.global_position = body.global_position + Vector3(2000.0, 0.0, 0.0)
	assert_eq(_tree().get_first_node_in_group("player"), left_behind, "the streamer follows the one left behind")
	streamer.refresh()
	assert_true(_still_her(body), "and the Warden three metres from the player is not taken away")


func _streamer_by_hand() -> NpcStreamer:
	var streamer := _tree().get_first_node_in_group(NpcStreamer.GROUP) as NpcStreamer
	if streamer == null:
		streamer = NpcStreamer.ensure()
		_made_streamer = streamer
	streamer.enabled = false
	return streamer


## The Warden stood up in Merrowby in the last minutes before bed, the player `d` metres off.
func _counting_the_bells(d: float) -> Dictionary:
	var t0 := _last_hour_at(KINDLEDAY, "core:place/merrowby", 19.0, 20.95)
	assert_true(t0 > 0.0, "of an evening her day has her in Merrowby counting the bells")
	if t0 < 0.0:
		return {}
	WorldClock.set_time(t0, KINDLEDAY)
	var stood: Dictionary = await _stand_her_up(d)
	assert_false(stood.is_empty(), "the Warden is stood up")
	if not stood.is_empty():
		assert_false(registry.is_indoors(WREN), "out of doors")
	return stood


## Steps the world until the body has walked to where it was sent, for as long as walking 40 m
## takes. Untyped, like _still_her: a body taken away is a freed object.
func _until_arrived(body: Variant) -> bool:
	for i in 60 * 20:
		if not is_instance_valid(body) or not bool((body as Node).get("has_target")):
			break
		await _tree().physics_frame
	return is_instance_valid(body) and not bool((body as Node).get("has_target"))


## A cell coming up along a traveller's road put them down at the far end: a traveller's spot is
## the one they are walking to, and a body stood up before its place's marker existed is moved
## onto the marker when it comes up.
func test_a_traveller_is_not_put_down_at_the_far_end_when_a_cell_comes_up() -> void:
	var who := _someone_half_way_along_a_road()
	if who.is_empty():
		# a world whose roads are not built has nobody on them to put down anywhere
		return
	var id := str(who["id"])
	WorldClock.set_time(float(who["hour"]), int(who["day"]))
	registry.simulate(id, "clear")
	assert_true(registry.is_travelling(id), "%s is on the road" % id)
	var body := registry.spawn(id) as Node3D
	assert_true(body != null, "and stood up on it")
	if body == null:
		return
	var before := body.global_position
	var there := WorldProbe.place_position(registry.place_of(id))
	var marker := Marker3D.new()
	marker.name = str(registry.state(id).get("spot", ""))
	marker.set_meta("place", registry.place_of(id))
	marker.add_to_group(NpcRegistry.SPOT_GROUP)
	host.add_child(marker)
	marker.global_position = there
	assert_gt(_flat(there, before), 50.0, "the spot they are walking to is well along the road")
	registry._on_cell_loaded(registry.cell_of(id))
	assert_true(_flat(body.global_position, before) < 0.5,
			"a cell coming up does not put them down there (moved %.1f m)" % _flat(body.global_position, before))


## Somebody of the pack half way along a road of more than 300 m between two places of their day,
## as {id, day, hour}; {} when the built world has no roads to walk.
func _someone_half_way_along_a_road() -> Dictionary:
	if not FileAccess.file_exists(RoadRoutes.ROADS_PATH):
		return {}
	for def in ContentDB.all("npc"):
		var id := str(def["id"])
		if registry.is_gone(id):
			continue
		for day in range(1, 8):
			for k in range(0, 24 * 12):
				var hour := float(k) / 12.0
				var e := Schedules.entry_for_def(def, day, hour)
				if not bool(e.get("travelling", false)):
					continue
				var lead := float(e.get("travel_hours", 0.0))
				var left := float(e.get("arrives_in_hours", 0.0))
				if lead < 0.5 or left > lead * 0.6 or left < lead * 0.4:
					continue
				var r := RoadRoutes.route(str(e["travel_from"]), str(e["place"]))
				if r.size() > 3 and RoadRoutes.length_of(r) > 300.0:
					return {"id": id, "day": day, "hour": hour}
	return {}
