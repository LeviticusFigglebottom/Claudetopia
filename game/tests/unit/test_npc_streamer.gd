extends TestCase
## The people are actually standing there. `NpcRegistry` could always stand somebody up and
## nothing outside a test ever asked it to, so every village in Wickmere was empty while its
## schedules ran. `NpcStreamer` is what asks. These pin the behaviour that matters: the nearby
## are up, the distant are not, and walking away takes them down again.

const MERROWBY := "core:place/merrowby"
## The emptiest spot on the map, wherever the map has put its places (see _far_away).
var FAR_AWAY := _far_away()


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## The point of a 256 m grid over the map that is farthest from every place and POI. It used to
## be written down as a corner of the old map (-3600, -3600), which a redrawn map is free to put a
## village in (docs/COORDINATES.md).
static func _far_away() -> Vector3:
	var anchors: Array[Vector2] = []
	for type in PlaceRef.ANCHOR_TYPES:
		for def in ContentDB.all(type):
			var p := PlaceRef.xz(str(def.get("id", "")))
			if p != Vector2.INF:
				anchors.append(p)
	var best := Vector3(-3600.0, 40.0, -3600.0)
	var best_d := -1.0
	var z := -3968.0
	while z <= 3968.0:
		var x := -3968.0
		while x <= 3968.0:
			var nearest := INF
			for a in anchors:
				nearest = minf(nearest, a.distance_squared_to(Vector2(x, z)))
			if nearest > best_d:
				best_d = nearest
				best = Vector3(x, 40.0, z)
			x += 256.0
		z += 256.0
	return best


## The world without its own body in it. `world.tscn` spawns a real Player at the opening
## place, and the streamer follows whoever is in the player group — so leaving it on would
## have these tests measuring the distance from the Hushline Stair instead of from the
## stand-in they place by hand.
func _world() -> World:
	var w := (load("res://world/world.tscn") as PackedScene).instantiate() as World
	var spawn: Node = w.get_node_or_null("PlayerSpawn")
	if spawn != null:
		spawn.set("enabled", false)
	_tree().root.add_child(w)
	return w


func _drop(w: Node) -> void:
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame


## A body in the player's group, which is what the streamer follows. It is not a Player: the
## streamer only ever asks where the anchor is.
func _anchor_at(w: World, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = "StandIn"
	node.add_to_group("player")
	w.add_child(node)
	node.global_position = at
	return node


func _streamer() -> NpcStreamer:
	var s := NpcStreamer.ensure()
	s.enabled = false      # driven by hand in a test, not by the frame clock
	return s


func test_the_village_has_people_standing_in_it() -> void:
	var w := _world()
	await w.world_ready
	var registry := NpcRegistry.ensure()
	registry.despawn_all()
	var anchor := _anchor_at(w, w.place_position(MERROWBY))
	var streamer := _streamer()
	streamer.refresh()
	var here := registry.npcs_at(MERROWBY)
	assert_gt(here.size(), 3, "Merrowby has a roster")
	var standing := 0
	for id in here:
		if registry.is_spawned(id):
			standing += 1
	assert_gt(standing, 3, "and they are bodies in the world, not rows in a table")
	registry.despawn_all()
	anchor.queue_free()
	await _drop(w)


func test_nobody_stands_up_on_the_far_side_of_the_world() -> void:
	var w := _world()
	await w.world_ready
	var registry := NpcRegistry.ensure()
	registry.despawn_all()
	var anchor := _anchor_at(w, FAR_AWAY)
	var streamer := _streamer()
	streamer.refresh()
	for id in registry.npcs_at(MERROWBY):
		assert_false(registry.is_spawned(id), "%s stood up four kilometres away" % id)
	registry.despawn_all()
	anchor.queue_free()
	await _drop(w)


func test_walking_away_takes_them_down_again() -> void:
	var w := _world()
	await w.world_ready
	var registry := NpcRegistry.ensure()
	registry.despawn_all()
	var anchor := _anchor_at(w, w.place_position(MERROWBY))
	var streamer := _streamer()
	streamer.refresh()
	var was := registry.spawned.size()
	assert_gt(was, 0, "somebody was standing there to begin with")
	anchor.global_position = FAR_AWAY
	streamer.refresh()
	assert_eq(registry.spawned.size(), 0, "walking away left %d bodies behind" % registry.spawned.size())
	anchor.queue_free()
	await _drop(w)


func test_asking_twice_does_not_stand_anybody_up_twice() -> void:
	var w := _world()
	await w.world_ready
	var registry := NpcRegistry.ensure()
	registry.despawn_all()
	var anchor := _anchor_at(w, w.place_position(MERROWBY))
	var streamer := _streamer()
	streamer.refresh()
	var first := registry.spawned.size()
	streamer.refresh()
	streamer.refresh()
	assert_eq(registry.spawned.size(), first, "a second look changed who is standing there")
	registry.despawn_all()
	anchor.queue_free()
	await _drop(w)


func test_the_dead_do_not_come_back_out_to_meet_you() -> void:
	var w := _world()
	await w.world_ready
	var registry := NpcRegistry.ensure()
	registry.despawn_all()
	var roster := registry.npcs_at(MERROWBY)
	assert_gt(roster.size(), 0, "somebody lives in Merrowby")
	var gone: String = roster[0]
	registry.kill(gone)
	var anchor := _anchor_at(w, w.place_position(MERROWBY))
	var streamer := _streamer()
	streamer.refresh()
	assert_false(registry.is_spawned(gone), "%s was killed and stood up again" % gone)
	registry.despawn_all()
	registry.rebuild()
	anchor.queue_free()
	await _drop(w)


func test_the_world_installs_the_streamer_with_its_other_services() -> void:
	assert_true(GameServices.ORDER.any(func(pair: Array) -> bool:
			return str(pair[0]) == "NpcStreamer"),
			"nothing installs the streamer, so nothing will stand the villagers up")


# --- indoors -------------------------------------------------------------------------------------

func _set_hour(h: float) -> void:
	WorldClock.set_time(h)
	NpcRegistry.ensure().simulate_all("clear")


func test_a_village_empties_at_three_in_the_morning() -> void:
	var w := _world()
	await w.world_ready
	var registry := NpcRegistry.ensure()
	registry.despawn_all()
	var anchor := _anchor_at(w, w.place_position(MERROWBY))
	var streamer := _streamer()

	_set_hour(13.0)
	streamer.refresh()
	var by_day := registry.spawned.size()
	assert_gt(by_day, 2, "the village has people out in the afternoon")

	_set_hour(3.0)
	streamer.refresh()
	var by_night := registry.spawned.size()
	assert_true(by_night < by_day,
			"at three in the morning %d of %d were still standing outside" % [by_night, by_day])
	for id in registry.spawned.keys():
		assert_false(registry.is_indoors(str(id)), "%s is asleep and standing in the street" % id)

	registry.despawn_all()
	anchor.queue_free()
	_set_hour(9.0)
	await _drop(w)


func test_the_schedule_says_who_is_under_a_roof() -> void:
	var sleeping := {"activity": "sleep", "spot": "bed"}
	var at_home := {"activity": "idle", "spot": "home"}
	var marked := {"activity": "work", "spot": "in:stillroom"}
	var flagged := {"activity": "work", "spot": "forge", "indoors": true}
	var outside := {"activity": "work", "spot": "eel_racks"}
	assert_true(Schedules.is_indoors(sleeping), "asleep is indoors")
	assert_true(Schedules.is_indoors(at_home), "at home is indoors")
	assert_true(Schedules.is_indoors(marked), "an in: spot is indoors")
	assert_true(Schedules.is_indoors(flagged), "an explicit flag is indoors")
	assert_false(Schedules.is_indoors(outside), "the eel racks are not indoors")


func test_the_resolved_entry_carries_indoors_through() -> void:
	var entry := Schedules.resolve({"activity": "sleep", "spot": "bed"}, "clear", "core:place/merrowby")
	assert_true(bool(entry.get("indoors", false)), "resolve() dropped indoors")
	# rain sends an idler home, and home is under a roof
	var wet := Schedules.resolve({"activity": "idle", "spot": "green"}, "rain", "core:place/merrowby")
	assert_true(bool(wet.get("indoors", false)), "rain sent them home but not inside")


func test_you_find_the_resident_at_home() -> void:
	var w := _world()
	await w.world_ready
	var registry := NpcRegistry.ensure()
	registry.despawn_all()
	var anchor := _anchor_at(w, w.place_position(MERROWBY))
	var streamer := _streamer()
	# a house whose resident the roster knows, and an hour they are in it
	var home := ""
	var who := ""
	for def in ContentDB.all("interior"):
		var resident := str(def.get("resident", ""))
		if resident != "" and ContentDB.has(resident):
			home = str(def.get("id", ""))
			who = resident
			break
	assert_true(home != "", "some interior has a named resident")
	_set_hour(3.0)
	assert_true(registry.is_indoors(who), "%s should be asleep at three" % who)

	# Standing inside that building is all the streamer reads; the pocket itself is the
	# interior manager's business and does not have to be loaded for its people to exist.
	GameState.current_interior_id = home
	streamer.refresh()
	assert_true(registry.is_spawned(who), "%s was not at home in their own house" % who)

	GameState.current_interior_id = ""
	registry.despawn_all()
	anchor.queue_free()
	_set_hour(9.0)
	await _drop(w)


## The streamer finds a loaded interior by the "interior_root" group, and falls back to
## matching the node's *name* when the group is empty — which it always was. The fallback
## worked, so renaming the node would have quietly emptied every house in the country of the
## people who live in it and nothing would have gone red.
func test_a_loaded_interior_is_findable_by_its_group() -> void:
	var interiors := ContentDB.all("interior")
	if interiors.is_empty():
		return
	var id := str(interiors[0].get("id", ""))
	var root: Node3D = Interiors.call("_load", id)
	if root == null:
		return
	assert_true(root.is_in_group("interior_root"),
		"a loaded interior is only findable by its node name")
	assert_eq(str(root.get_meta("interior_id", "")), id,
		"the group is no use without the meta that says which interior it is")
	Interiors.unload_all()
