extends TestCase
## The owner's Briar crash (2026-09-30): a villager's position went to NaN by Fernhold, the terrain
## was asked its height at x = NaN (an index of -2^63 into the height map), and the game went down.
## Nothing non-finite may reach the height map, and a body that goes to NaN, sinks through the
## ground or falls with nothing under it is put back on its last good ground (BodyGuard).

var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	if NpcRegistry.instance != null:
		NpcRegistry.instance.despawn_all()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _provider() -> TerrainProvider:
	var t := TerrainProvider.new()
	t._grid = 4
	t._spacing = 8.0
	t._height_origin = Vector2(0.0, 0.0)
	var h := PackedFloat32Array()
	for i in 16:
		h.append(10.0 + float(i))
	t._heights = h
	_nodes.append(t)
	return t


func test_the_height_map_is_never_indexed_at_a_point_that_is_not_a_number() -> void:
	var t := _provider()
	for p: Vector2 in [Vector2(NAN, 4.0), Vector2(4.0, NAN), Vector2(INF, 0.0), Vector2(0.0, -INF),
			Vector2(NAN, NAN), Vector2(-1.0e30, 1.0e30)]:
		var h := t.sample_height(p.x, p.y)
		assert_true(is_finite(h), "sample_height(%s) = %s" % [str(p), str(h)])
		var g := t.get_height(p.x, p.y)
		assert_true(is_finite(g), "get_height(%s) = %s" % [str(p), str(g)])
		assert_true(t.get_normal(p.x, p.y).is_finite(), "get_normal(%s)" % str(p))
	# and a real point still reads the map
	assert_near(t.sample_height(0.0, 0.0), 10.0, 0.001)


func _npc() -> Npc:
	var n: Npc = load("res://actors/npc/npc.tscn").instantiate()
	n.npc_id = "core:npc/example_reeve_ansel"
	_root().add_child(n)
	_nodes.append(n)
	n.global_position = Vector3(12.0, 3.0, -7.0)
	return n


func test_a_person_whose_position_goes_to_nan_is_put_back_where_they_stood() -> void:
	var n := _npc()
	# stood a moment on something (the guard keeps where)
	n._guard.check(n, 1.0, true)
	var good := n.global_position
	n.global_position = Vector3(NAN, 3.0, -7.0)
	n.velocity = Vector3(NAN, NAN, 0.0)
	n._physics_process(1.0 / 60.0)
	assert_true(n.global_position.is_finite(), "still NaN: %s" % str(n.global_position))
	assert_true(n.velocity.is_finite(), "velocity still NaN")
	assert_near(n.global_position.distance_to(good), 0.0, 0.01, "not put back where they stood")
	assert_eq(n._guard.recoveries, 1)


func test_a_person_falling_with_no_floor_is_put_back_in_a_few_seconds() -> void:
	var n := _npc()
	n._guard.check(n, 1.0, true)
	var good := n.global_position
	# over a void: no world, nothing under them, and let go
	n.global_position = good + Vector3(0.0, -2.0, 0.0)
	var frames := 0
	while n._guard.recoveries == 0 and frames < 60 * 12:
		if n._guard.check(n, 1.0 / 60.0, false):
			break
		n.velocity.y -= 9.8 / 60.0
		n.global_position += n.velocity / 60.0
		frames += 1
	assert_eq(n._guard.recoveries, 1, "a fall with no floor went on for %d frames" % frames)
	assert_gt(60.0 * (BodyGuard.FALL_S + 0.5), float(frames), "put back only after %d frames" % frames)
	assert_near(n.global_position.distance_to(good), 0.0, 0.01)
	assert_eq(n.velocity, Vector3.ZERO)


func test_a_person_with_no_good_ground_goes_home() -> void:
	var n := _npc()
	n.global_position = Vector3(INF, 0.0, 0.0)
	var home := Vector3(5.0, 1.0, 5.0)
	assert_true(n._guard.check(n, 1.0 / 60.0, true, func() -> Vector3: return home))
	assert_near(n.global_position.distance_to(home), 0.0, 0.01)


func test_a_walk_to_nowhere_is_not_taken() -> void:
	var n := _npc()
	n.set_move_target(Vector3(NAN, 0.0, 0.0), false)
	assert_false(n.has_target, "a walk to NaN was taken")
	n.set_move_target(Vector3.INF, false)
	assert_false(n.has_target, "a walk to Vector3.INF was taken")
