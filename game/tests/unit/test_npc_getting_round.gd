extends TestCase
## A villager's walk is a straight line (there is no navigation mesh), and one whose line ran into a
## house leant on its wall with its legs going for the rest of the hour: in Merrowby at ten the
## grocer, stood up inside her own stall, and a man bound for the green did so for the whole of the
## probe (playtest 2026-09-27, 18). These put a wall in the way and a destination inside a box.

const BRAM := "core:npc/example_thatcher_bram"

var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	Peers.overrides.clear()
	var reg := NpcRegistry.instance
	if reg != null:
		reg.despawn_all()
		reg.abstract_only = true


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_tree().root.add_child(body)
	body.global_position = at
	_nodes.append(body)
	return body


## Far from any world, on a floor of its own a kilometre below the map, with somebody watching (so
## giving up does not put them where they were going).
func _yard() -> Vector3:
	var o := Vector3(0.0, -1000.0, 0.0)
	_box(o + Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	var watcher := Node3D.new()
	_tree().root.add_child(watcher)
	_nodes.append(watcher)
	watcher.global_position = o + Vector3(0, 0, 6)
	Peers.overrides["player"] = watcher
	return o


func _npc(at: Vector3) -> Npc:
	var n: Npc = load("res://actors/npc/npc.tscn").instantiate()
	n.npc_id = BRAM
	_tree().root.add_child(n)
	_nodes.append(n)
	n.global_position = at
	return n


func test_a_wall_in_the_way_is_walked_round() -> void:
	if WorldProbe.has_world():
		return  # the ground here is the test's own floor
	var o := _yard()
	# a house front five metres wide square across the line
	_box(o + Vector3(0.4, 1.25, -4.0), Vector3(5.0, 2.5, 0.6))
	var n := _npc(o)
	await _tree().physics_frame
	var goal := o + Vector3(0, 0, -9.0)
	n.set_move_target(goal)
	var arrived := false
	for i in 60 * 16:
		await _tree().physics_frame
		if not n.has_target:
			arrived = n._flat_distance(goal) <= Npc.ARRIVE_M + 0.2
			break
	assert_false(n.has_target, "the walk ends, one way or the other, instead of leaning on the wall")
	assert_true(arrived, "and ends where it was going, round the end of the wall (%.1f m off)" % n._flat_distance(goal))


func test_a_destination_inside_a_box_is_moved_beside_it() -> void:
	if WorldProbe.has_world():
		return
	var o := _yard()
	var stall := o + Vector3(6.0, 0.0, 0.0)
	_box(stall + Vector3(0, 0.6, 0), Vector3(1.6, 1.2, 1.0))
	var n := _npc(o)
	await _tree().physics_frame
	await _tree().physics_frame
	assert_true(n.blocked_at(stall), "a body cannot stand in the stall")
	n.set_move_target(stall)
	assert_false(n.blocked_at(n.target_position), "so the walk is to beside it")
	assert_gt(n._flat_distance(stall), n._flat_distance(n.target_position), "on the near side")
	assert_gt(2.0, n.target_position.distance_to(stall), "close by")
	for i in 60 * 6:
		await _tree().physics_frame
		if not n.has_target:
			break
	assert_false(n.has_target, "and they get there")


func test_somebody_stood_up_inside_a_house_steps_out() -> void:
	if WorldProbe.has_world():
		return
	var o := _yard()
	_box(o + Vector3(0, 1.5, 0), Vector3(4, 3, 4))
	var n := _npc(o + Vector3(0.5, 0, 0.2))
	await _tree().physics_frame
	n.apply_state({"place": "core:place/merrowby", "activity": "idle", "spot": "", "alive": true, "hostile": false})
	assert_false(n.blocked_at(n.global_position), "out of the walls")
	assert_gt(4.5, n._flat_distance(o), "and beside the house, not across the map")


func test_whoever_fled_walks_again_once_away() -> void:
	if WorldProbe.has_world():
		return
	var o := _yard()
	var n := _npc(o)
	await _tree().physics_frame
	var from := Node3D.new()
	_tree().root.add_child(from)
	_nodes.append(from)
	from.global_position = o + Vector3(0, 0, 1)
	n.flee_from(from)
	assert_eq(n.current_speed(), Npc.FLEE_SPEED)
	for i in 60 * 6:
		await _tree().physics_frame
		if not n.has_target:
			break
	assert_false(n.has_target, "got away")
	assert_eq(n.current_speed(), Npc.WALK_SPEED, "and walks from here on")
