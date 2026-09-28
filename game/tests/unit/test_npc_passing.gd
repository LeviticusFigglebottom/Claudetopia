extends TestCase
## People walked through each other, did not find the gate of a fenced yard, and one who gave a walk
## up in the player's sight stood where it stopped, often with its face to a wall, until the next
## hour (playtest 2026-09-28, item 26). These walk two people at each other, one past somebody
## standing, one into a yard whose way in is round the back (on NpcNav's mesh), and set two down on
## one spot; and stand somebody in a house's pocket, which is not the country's ground.

const BRAM := "core:npc/example_thatcher_bram"
const TIBB := "core:npc/example_child_tibb"

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
	var nav := NpcNav.instance
	for n in _nodes:
		if is_instance_valid(n):
			if nav != null:
				nav.forget(n)
			n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()


func _box(at: Vector3, size: Vector3, parent: Node = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if parent != null:
		parent.add_child(body)
	else:
		_tree().root.add_child(body)
		_nodes.append(body)
	body.global_position = at
	return body


## A floor off the edge of the map with somebody watching, as test_npc_getting_round's.
func _yard(o: Vector3) -> Node3D:
	var root := Node3D.new()
	_tree().root.add_child(root)
	_nodes.append(root)
	root.global_position = o
	_box(o + Vector3(0, -0.5, 0), Vector3(60, 1, 60), root)
	var watcher := Node3D.new()
	root.add_child(watcher)
	watcher.global_position = o + Vector3(0, 0, 14)
	Peers.overrides["player"] = watcher
	return root


func _npc(id: String, at: Vector3) -> Npc:
	var n: Npc = load("res://actors/npc/npc.tscn").instantiate()
	n.npc_id = id
	_tree().root.add_child(n)
	_nodes.append(n)
	n.global_position = at
	return n


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_two_walking_at_each_other_pass_without_meeting() -> void:
	var o := Vector3(6000, 0, 6000)
	_yard(o)
	var a := _npc(BRAM, o + Vector3(0, 0, 7))
	var b := _npc(TIBB, o + Vector3(0.1, 0, -7))
	await _tree().physics_frame
	a.set_move_target(o + Vector3(0, 0, -7))
	b.set_move_target(o + Vector3(0.1, 0, 7))
	var closest := INF
	for i in 60 * 20:
		await _tree().physics_frame
		closest = minf(closest, _flat(a.global_position, b.global_position))
		if not a.has_target and not b.has_target:
			break
	assert_false(a.has_target or b.has_target, "both get where they were going")
	# two capsules touch at 0.64 m: the way bends before they do
	assert_gt(closest, 0.75, "and pass with room between them (closest %.2f m)" % closest)


func test_a_walker_goes_round_somebody_standing_and_does_not_shove_them() -> void:
	var o := Vector3(6100, 0, 6000)
	_yard(o)
	var stood := _npc(TIBB, o)
	var a := _npc(BRAM, o + Vector3(0, 0, 7))
	await _tree().physics_frame
	var was := stood.global_position
	a.set_move_target(o + Vector3(0, 0, -7))
	var closest := INF
	for i in 60 * 15:
		await _tree().physics_frame
		closest = minf(closest, _flat(a.global_position, stood.global_position))
		if not a.has_target:
			break
	assert_false(a.has_target, "gets past")
	assert_gt(closest, 0.7, "round them, not through them (closest %.2f m)" % closest)
	assert_gt(0.15, _flat(stood.global_position, was), "and the one standing stays where they stood")


func test_two_set_down_on_one_spot_do_not_stand_in_each_other() -> void:
	var o := Vector3(6200, 0, 6000)
	_yard(o)
	var a := _npc(BRAM, o)
	var b := _npc(TIBB, o + Vector3(0.2, 0, 0.1))
	await _tree().physics_frame
	b.make_room()
	assert_gt(_flat(a.global_position, b.global_position), Npc.ROOM_M - 0.01, "the second is set down beside the first")


## A yard fenced on three sides, its gate on the far side: the straight line and the detours met its
## back fence; the way round goes to the gate.
func test_the_way_into_a_yard_goes_round_to_its_gate() -> void:
	var o := Vector3(6300, 0, 6000)
	var root := _yard(o)
	_box(o + Vector3(0, 1, -1), Vector3(9, 2, 0.2), root)
	_box(o + Vector3(-4.5, 1, -8), Vector3(0.2, 2, 14), root)
	_box(o + Vector3(4.5, 1, -8), Vector3(0.2, 2, 14), root)
	var nav := await _mesh_over(root, o + Vector3(0, 0, 6))
	assert_true(nav.is_ready(root) and NpcNav.on_mesh(o + Vector3(0, 0, 6)), "a mesh stands over the yard")
	var n := _npc(BRAM, o + Vector3(0, 0, 6))
	await _tree().physics_frame
	await _tree().physics_frame
	var goal := o + Vector3(0, 0, -5)
	var way := NpcNav.path(n.global_position, goal)
	assert_gt(way.size(), 3, "the way has corners (%d)" % way.size())
	n.set_move_target(goal)
	for i in 60 * 40:
		await _tree().physics_frame
		if not n.has_target:
			break
	assert_false(n.has_target, "the walk ends")
	assert_gt(Npc.ARRIVE_M + 0.3, _flat(n.global_position, goal), "inside the yard (%.1f m off)" % _flat(n.global_position, goal))
	assert_eq(n.give_ups, 0, "without giving up")


## A yard with no gate at all: the way ends at its fence, and they stop there turned to it, rather
## than leaning on it until they give up.
func test_a_yard_with_no_way_in_is_walked_to_its_fence() -> void:
	var o := Vector3(6400, 0, 6000)
	var root := _yard(o)
	# a garden's fence, a metre high: seen over, not walked through
	_box(o + Vector3(0, 0.5, -1), Vector3(9, 1, 0.2), root)
	_box(o + Vector3(0, 0.5, -12), Vector3(9, 1, 0.2), root)
	_box(o + Vector3(-4.5, 0.5, -6.5), Vector3(0.2, 1, 11), root)
	_box(o + Vector3(4.5, 0.5, -6.5), Vector3(0.2, 1, 11), root)
	var nav := await _mesh_over(root, o + Vector3(0, 0, 6))
	var n := _npc(BRAM, o + Vector3(0, 0, 6))
	await _tree().physics_frame
	await _tree().physics_frame
	var goal := o + Vector3(0, 0, -6)
	n.set_move_target(goal)
	for i in 60 * 20:
		await _tree().physics_frame
		if not n.has_target:
			break
	assert_false(n.has_target, "the walk ends")
	assert_eq(n.give_ups, 0, "at the nearest the way comes, not given up")
	assert_gt(7.0, _flat(n.global_position, goal), "by its fence (%.1f m from the spot)" % _flat(n.global_position, goal))
	var to := goal - n.global_position
	assert_gt(0.3, absf(wrapf(n._home_yaw - Npc._yaw_of(to), -PI, PI)), "turned to the spot over the fence")


func _mesh_over(root: Node3D, stand_at: Vector3) -> NpcNav:
	# the fences join the physics space at the tick after they are made
	await _tree().physics_frame
	await _tree().physics_frame
	var nav := NpcNav.ensure()
	nav.stand(root)
	for i in 600:
		if nav.is_ready(root) and NpcNav.on_mesh(stand_at):
			break
		await _tree().physics_frame
	return nav


func test_given_up_in_sight_they_turn_from_the_wall_and_try_again_later() -> void:
	var o := Vector3(6500, 0, 6000)
	_yard(o)
	_box(o + Vector3(0, 1.25, -0.7), Vector3(6, 2.5, 0.4))
	var n := _npc(BRAM, o)
	await _tree().physics_frame
	n.target_position = o + Vector3(0, 0, -5)
	n.has_target = true
	n.face_direction(Vector3(0, 0, -1))
	assert_true(n._wall_ahead(n._model.rotation.y, Npc.WALL_NEAR_M), "they stand with their face to the wall")
	n._give_up_leg()
	assert_false(n.has_target, "the leg is given up")
	assert_false(n._wall_ahead(n._home_yaw, Npc.WALL_NEAR_M), "and they turn from the wall")
	assert_ne(n._retry_goal, Vector3.INF, "the walk is to be tried again")
	n._retry_left = 0.0
	n._live(0.1)
	assert_true(n.has_target, "and when the time comes they walk again")


## A house's pocket is a kilometre up in the air over the edge of the map; the ground the terrain
## gives there is not the house's floor.
func test_somebody_in_a_house_stands_on_its_floor() -> void:
	var o := Vector3(6600, 300, 6000)
	var root := _yard(o)
	var n := _npc(BRAM, o + Vector3(0, 0.1, 0))
	n.indoors = root
	for i in 90:
		await _tree().physics_frame
	assert_gt(0.3, absf(n.global_position.y - o.y), "on the floor (y %.2f, floor %.2f)" % [n.global_position.y, o.y])


## Triage 32: a dozen sent to one well queued round it as "stuck" for 10-24 s, two at a time given
## the same random place (some in the well). They stand in slots of their own round the well.
func test_a_crowd_at_the_well_stands_round_it_in_places_of_its_own() -> void:
	var o := Vector3(6700, 0, 6000)
	var root := _yard(o)
	var well := o
	var marker := Marker3D.new()
	marker.name = "test_well_spot"
	root.add_child(marker)
	marker.global_position = well + Vector3(1.6, 0, 0.8)
	marker.set_meta("gather", true)
	marker.set_meta("gather_from", -Vector3(1.6, 0, 0.8))
	marker.set_meta("gather_r", 1.9)
	var clear := func(p: Vector3) -> bool: return _flat(p, well) > 1.2
	var at: Array[Vector3] = []
	for i in 12:
		at.append(marker.global_position + NpcRegistry.gather_offset("test:npc/gatherer_%d" % i, marker, Vector3.INF, clear))
	for i in at.size():
		assert_gt(_flat(at[i], well), 1.85, "round the well, not in it (%.2f m)" % _flat(at[i], well))
		for j in range(i + 1, at.size()):
			assert_gt(_flat(at[i], at[j]), 0.9, "two not in one place (%d, %d: %.2f m)" % [i, j, _flat(at[i], at[j])])
	var again := marker.global_position + NpcRegistry.gather_offset("test:npc/gatherer_3", marker, Vector3.INF, clear)
	assert_gt(0.01, _flat(again, at[3]), "the same place asked again")
	# one held up in the crowd takes the free slot nearest where they are
	var from := well + Vector3(0, 0, -4.2)
	var settled := marker.global_position + NpcRegistry.gather_offset("test:npc/gatherer_3", marker, from, clear)
	for i in at.size():
		if i != 3:
			assert_gt(_flat(settled, at[i]), 0.9, "a slot nobody else holds")
	assert_gt(_flat(at[3], from) + 0.01, _flat(settled, from), "nearer where they stood")
	for i in 12:
		NpcRegistry._held.erase("test:npc/gatherer_%d" % i)


## Triage 32: solid scatter that joins the physics space inside a town after its mesh was baked is
## told of (the town is baked again then), and a town waits for what is still to join.
func test_solid_scatter_joining_is_told_of_by_where() -> void:
	var solids := ScatterSolids.new()
	_tree().root.add_child(solids)
	_nodes.append(solids)
	var cell := Node3D.new()
	_tree().root.add_child(cell)
	_nodes.append(cell)
	cell.global_position = Vector3(6800, 0, 6000)
	var box := BoxShape3D.new()
	box.size = Vector3(1, 3, 1)
	var since := Time.get_ticks_msec() - 1
	solids.add_cell(cell, {}, [[box, Transform3D(Basis(), Vector3(5, 1.5, 5))]])
	var town := Rect2(6780, 5980, 60, 60)
	var elsewhere := Rect2(7400, 5980, 60, 60)
	assert_eq(solids.pending_in(town), 1, "a block still to stand over the town")
	assert_eq(solids.pending_in(elsewhere), 0, "and none elsewhere")
	assert_eq(solids.last_join_in(town, since), -1, "nothing joined yet")
	solids.flush()
	assert_eq(solids.pending_in(town), 0, "stood")
	assert_gt(solids.last_join_in(town, since), since - 1, "joined over the town")
	assert_eq(solids.last_join_in(elsewhere, since), -1, "and not elsewhere")
	assert_eq(solids.last_join_in(town, Time.get_ticks_msec()), -1, "and nothing since")


## Baked again, a mesh takes in what stood after its first bake, and stays on the map meanwhile.
func test_baked_again_the_way_goes_round_what_stood_after() -> void:
	var o := Vector3(6900, 0, 6000)
	var root := _yard(o)
	var nav := await _mesh_over(root, o + Vector3(0, 0, 6))
	assert_eq(nav.bakes(root), 1, "baked once")
	var straight := NpcNav.path(o + Vector3(0, 0, 6), o + Vector3(0, 0, -6))
	assert_gt(4, straight.size(), "the way is straight across the open yard (%d)" % straight.size())
	# a hedge across the yard, standing up after the bake
	_box(o + Vector3(-3, 1, 0), Vector3(20, 2, 0.6), root)
	await _tree().physics_frame
	await _tree().physics_frame
	nav.stand(root, true)
	assert_true(nav.is_ready(root), "the first mesh stays on the map while the new one bakes")
	for i in 600:
		if nav.bakes(root) >= 2:
			break
		await _tree().physics_frame
	assert_eq(nav.bakes(root), 2, "baked again")
	# the map takes the region's new mesh at its next sync
	for i in 4:
		await _tree().physics_frame
	var way := NpcNav.path(o + Vector3(0, 0, 6), o + Vector3(0, 0, -6))
	var length := 0.0
	for i in range(1, way.size()):
		length += way[i].distance_to(way[i - 1])
	assert_gt(length, 14.0, "the way goes round the hedge's end (%.1f m)" % length)
