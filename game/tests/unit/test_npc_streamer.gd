extends TestCase
## The people are actually standing there. `NpcRegistry` could always stand somebody up and
## nothing outside a test ever asked it to, so every village in Wickmere was empty while its
## schedules ran. `NpcStreamer` is what asks. These pin the behaviour that matters: the nearby
## are up, the distant are not, and walking away takes them down again.

const MERROWBY := "core:place/merrowby"
const FAR_AWAY := Vector3(-3600.0, 40.0, -3600.0)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


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
