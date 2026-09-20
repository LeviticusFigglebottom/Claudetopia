extends TestCase
## The roster in the ground: an NPC stands at their own place, on the terrain, and comes and
## goes with the cells around the player. The registry could always do this; nothing had ever
## run it against real terrain, and every height query fell through to the region's nominal
## base height because the World script did not answer the questions WorldProbe asks.

const MERROWBY := "core:place/merrowby"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _world() -> World:
	var w := (load("res://world/world.tscn") as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	return w


func _drop(w: Node) -> void:
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame


func test_the_world_answers_the_ground_questions_world_probe_asks() -> void:
	var w := _world()
	await w.world_ready
	assert_true(WorldProbe.has_world(), "WorldProbe can see a world")
	var at := w.place_position(MERROWBY)
	var probed := WorldProbe.get_height(at.x, at.z)
	assert_near(probed, World.terrain().get_height(at.x, at.z), 0.01, "and gets the real ground back")
	assert_eq(WorldProbe.region_id_at(at), "core:region/hearthvale")
	await _drop(w)


func test_villagers_stand_at_their_own_place_on_the_ground() -> void:
	var w := _world()
	await w.world_ready
	var registry := NpcRegistry.ensure()
	# `NpcStreamer` is a world service now and may already have stood these people up, and
	# `spawn()` refuses somebody who is already standing. This test is about the standing, so
	# it starts from an empty street.
	registry.despawn_all()
	var living := registry.npcs_at(MERROWBY)
	assert_gt(living.size(), 3, "Merrowby has people in it")
	var stood := 0
	for id in living:
		var node: Node = registry.spawn(id)
		if node == null:
			continue
		stood += 1
		var body := node as Node3D
		var home := w.place_position(MERROWBY)
		assert_true(Vector2(body.global_position.x - home.x, body.global_position.z - home.z).length() < 40.0,
				"%s stands in their own village" % id)
		var ground := World.terrain().get_height(body.global_position.x, body.global_position.z)
		assert_true(absf(body.global_position.y - ground) < 2.0, "%s stands on the ground" % id)
		registry.despawn(id)
	assert_gt(stood, 3, "and they are real bodies, not records")
	await _drop(w)
