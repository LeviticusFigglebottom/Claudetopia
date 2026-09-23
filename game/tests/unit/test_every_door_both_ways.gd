extends TestCase
## Every door into every interior, walked both ways in the built world by the world's own player.
##
## In through the door the world put up: the body stands just inside the interior's own door
## (the one the way back is through), on the floor, clear of the furniture, facing into the room.
## Out through that door: the body stands just outside the door it came in by, on the ground,
## facing away from it. Houses used to put the player in the corner of their first room, a
## metre up; deep places put them in the middle of the mouth chamber, three to five metres from
## the way out; and leaving faced the player back at the door it had just come out of.

const WORLD_SCENE := "res://world/world.tscn"
## In: this near the interior's own door (a step inside a wall, or a pace from a cave's way out).
const IN_NEAR := 0.6
const IN_FAR := 2.4
## Out: a pace and a half in front of the door.
const OUT_NEAR := 1.0
const OUT_FAR := 2.0
## On the floor: this far above what a ray down finds.
const FLOOR_LOW := -0.02
const FLOOR_HIGH := 0.15
## Facing: the body's forward against the way from the door to the body.
const FACING_IN := 0.5
const FACING_OUT := 0.9
## The player's capsule radius, for the furniture it must not stand in.
const BODY_RADIUS := 0.35

var _lines: Array[String] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## The body's forward on the ground (Godot's -Z).
static func _forward(body: Node3D) -> Vector3:
	return _flat(-body.global_transform.basis.z).normalized()


## How far the body stands above whatever is under it (a floor, the rock, the paving).
static func _above_floor(body: Node3D) -> float:
	var space := body.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 0.5, body.global_position + Vector3.DOWN * 3.0, 1)
	q.exclude = [(body as CollisionObject3D).get_rid()] if body is CollisionObject3D else []
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return INF
	return body.global_position.y - (hit["position"] as Vector3).y


## The interior's own door: the one inside `root` that leads back out.
func _way_out(root: Node) -> Door:
	for n in _tree().get_nodes_in_group("door"):
		if n is Door and (n as Door).is_exit and root.is_ancestor_of(n):
			return n as Door
	return null


## Anything the house or cave stood on the floor that the body stands inside: the meshes of its
## props, furnishings and dressing, taller than a rug, within a capsule's radius of the body.
func _standing_in(root: Node, body: Node3D) -> Array[String]:
	var out: Array[String] = []
	var feet := body.global_position
	for holder_name in ["Props", "Furnishings", "Features"]:
		for holder in root.find_children(holder_name, "", true, false):
			for mi_v in (holder as Node).find_children("*", "MeshInstance3D", true, false):
				var mi := mi_v as MeshInstance3D
				if mi.mesh == null or not mi.is_visible_in_tree():
					continue
				var box: AABB = mi.global_transform * mi.get_aabb()
				if box.end.y < feet.y + 0.15 or box.position.y > feet.y + 1.8:
					continue
				var dx := maxf(maxf(box.position.x - feet.x, feet.x - box.end.x), 0.0)
				var dz := maxf(maxf(box.position.z - feet.z, feet.z - box.end.z), 0.0)
				if Vector2(dx, dz).length() < BODY_RADIUS:
					out.append(str(mi.get_parent().name))
	return out


func test_every_door_is_walked_in_and_out_of_as_a_player_would() -> void:
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	await _frames(2)
	var spawn: Node = w.get_node_or_null("PlayerSpawn")
	var player: Node3D = spawn.get("player") if spawn != null else null
	var doors := _tree().get_first_node_in_group("world_doors") as WorldDoors
	assert_true(player != null, "somebody stands in the world")
	assert_true(doors != null, "the world puts its doors up")
	if player == null or doors == null:
		_tree().root.remove_child(w)
		w.queue_free()
		return
	var planned := 0
	for plan in ContentDB.all("table"):
		if str(plan.get("role", "")) == WorldDoors.PLAN_ROLE:
			planned += (plan.get("rows", []) as Array).size()
	assert_eq(doors.placed.size(), planned, "every door the plans name stands in the world")
	var kinds := {}
	var walked := 0
	for door in doors.placed:
		if not is_instance_valid(door):
			continue
		var id := door.interior_id
		var kind := str(ContentDB.get_or_empty(id).get("scene", "")).get_file().get_basename()
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		var lock := door.get_node_or_null("DoorLock")
		if lock != null:
			lock.set("locked", false)
		var face := _flat(door.global_transform.basis.z).normalized()
		# Walk up to it: two paces out, facing it.
		(player as Player).teleport(door.global_position + face * 2.0 + Vector3.UP * 0.1, atan2(face.x, face.z))
		await _frames(2)
		var warned := Log.warning_count
		door.interact(player)
		assert_eq(Interiors.current_id, id, "%s: the door leads in" % id)
		assert_eq(Log.warning_count, warned, "%s: going in warned of nothing (a doorway with nowhere clear to stand says so)" % id)
		if Interiors.current_id != id:
			continue
		await _frames(2)
		var root: Node = Interiors._loaded.get(id)
		var inner := _way_out(root) if root != null else null
		assert_true(inner != null, "%s has a way back out" % id)
		if inner == null:
			Interiors.exit()
			continue
		var from_inner := _flat(player.global_position - inner.global_position)
		var in_dist := from_inner.length()
		var in_above := _above_floor(player)
		var in_facing := _forward(player).dot(from_inner.normalized())
		var in_the_way := _standing_in(root, player)
		assert_true(in_dist >= IN_NEAR and in_dist <= IN_FAR, "%s: in, %.2f m from its door" % [id, in_dist])
		assert_true(in_above >= FLOOR_LOW and in_above <= FLOOR_HIGH, "%s: in, %.2f m above the floor" % [id, in_above])
		assert_true(in_facing >= FACING_IN, "%s: in, facing into the room (%.2f)" % [id, in_facing])
		assert_true(in_the_way.is_empty(), "%s: in, standing in %s" % [id, str(in_the_way)])
		# And out again, through the interior's own door.
		inner.interact(player)
		assert_eq(Interiors.current_id, "", "%s: its door leads out" % id)
		await _frames(2)
		var from_door := _flat(player.global_position - door.global_position)
		var out_dist := from_door.length()
		var out_side := from_door.dot(face)
		var out_facing := _forward(player).dot(from_door.normalized())
		var out_above := _above_floor(player)
		var terrain_above := player.global_position.y - World.terrain().get_height(player.global_position.x, player.global_position.z)
		var settled_at := player.global_position.y
		await _frames(10)
		var dropped := settled_at - player.global_position.y
		assert_true(out_dist >= OUT_NEAR and out_dist <= OUT_FAR, "%s: out, %.2f m from its door" % [id, out_dist])
		assert_gt(out_side, OUT_NEAR * 0.9, "%s: out, on the door's outside" % id)
		assert_true(out_facing >= FACING_OUT, "%s: out, facing away from the door (%.2f)" % [id, out_facing])
		assert_true(minf(absf(terrain_above), absf(out_above)) <= FLOOR_HIGH,
				"%s: out, on the ground (%.2f over the terrain, %.2f over what is under it)" % [id, terrain_above, out_above])
		assert_true(absf(dropped) < 0.1, "%s: out, stood rather than dropped (%.2f m in ten frames)" % [id, dropped])
		_lines.append("DOOR | %s | in %.2f m from its door, %.2f over the floor, facing %.2f | out %.2f m, %.2f over the ground, facing %.2f"
				% [id, in_dist, in_above, in_facing, out_dist, minf(absf(terrain_above), absf(out_above)), out_facing])
		walked += 1
		Interiors.unload_all()
		await _frames(1)
	for line in _lines:
		print(line)
	print("MEASURE | doors walked both ways | %d | %s" % [walked, str(kinds)])
	assert_eq(walked, planned, "every door was walked both ways")
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame
