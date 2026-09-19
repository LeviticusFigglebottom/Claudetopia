extends TestCase
## The join between the character and the ground: a body that stands in the world at the place
## the story opens, and doors in the terrain that lead into the twenty-four hand-built
## interiors. Until this existed, the Naming made a character, the builder made eight kilometres
## of country, and nothing put one in the other.

const WORLD_SCENE := "res://world/world.tscn"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _world() -> World:
	var packed := load(WORLD_SCENE) as PackedScene
	var w := packed.instantiate() as World
	_tree().root.add_child(w)
	return w


## The world holds threads and signal connections; taking it out of the tree and letting the
## engine free it on the next frame avoids freeing something mid-call.
func _drop(w: Node) -> void:
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame


# --- the door plans ------------------------------------------------------------------------------

func test_every_shipping_interior_has_a_way_in() -> void:
	var planned := {}
	for plan in ContentDB.all("table"):
		if str(plan.get("role", "")) != WorldDoors.PLAN_ROLE:
			continue
		assert_true(ContentDB.has(str(plan.get("place", ""))), "%s stands at a place that does not exist" % plan["id"])
		for row in plan.get("rows", []):
			var interior := str((row as Dictionary).get("interior", ""))
			assert_true(ContentDB.has(interior), "%s: unknown interior %s" % [plan["id"], interior])
			planned[interior] = true
	for interior in ContentDB.all("interior"):
		var id := str(interior["id"])
		if bool(interior.get("test_only", false)) or bool(interior.get("no_door", false)):
			continue
		assert_true(planned.has(id), "%s has no door anywhere in the world" % id)


func test_a_door_plan_says_where_on_the_ring_each_door_stands() -> void:
	for plan in ContentDB.all("table"):
		if str(plan.get("role", "")) != WorldDoors.PLAN_ROLE:
			continue
		var bearings: Array[float] = []
		for row in plan.get("rows", []):
			var r: Dictionary = row
			assert_gt(float(r.get("ring_radius", 0.0)), 0.0, "%s: a door needs a distance from the centre" % plan["id"])
			var bearing := float(r.get("bearing_deg", -1.0))
			assert_true(bearing >= 0.0 and bearing < 360.0, "%s: bearing out of the compass" % plan["id"])
			for other in bearings:
				assert_true(absf(other - bearing) > 4.0, "%s: two doors in the same doorway" % plan["id"])
			bearings.append(bearing)


# --- standing in it ------------------------------------------------------------------------------

func test_a_character_is_put_on_the_ground_at_the_opening() -> void:
	var w := _world()
	await w.world_ready
	var spawn: Node = w.get_node("PlayerSpawn")
	var body: Node3D = spawn.player
	assert_true(body != null, "somebody is standing in the world")
	assert_true(body.is_in_group("player"))
	var opening := str(ContentDB.get_or_empty(PlayerSpawn.OPENING).get("place", ""))
	var want := w.place_position(opening)
	if want != Vector3.ZERO:
		assert_true(Vector2(body.global_position.x - want.x, body.global_position.z - want.z).length() < 5.0,
				"they start where the story opens")
	var ground := World.terrain().get_height(body.global_position.x, body.global_position.z)
	assert_true(absf(body.global_position.y - ground) < 2.0, "on the ground, not in it or above it")
	assert_false(World.terrain().is_water(body.global_position.x, body.global_position.z), "and not in the water")
	await _drop(w)


func test_the_world_follows_the_body_rather_than_the_fly_camera() -> void:
	var w := _world()
	await w.world_ready
	var spawn: Node = w.get_node("PlayerSpawn")
	assert_eq(w.streamer.target, spawn.player, "the streaming follows the player")
	await _drop(w)


func test_the_law_and_the_market_are_installed_with_them() -> void:
	var w := _world()
	await w.world_ready
	assert_true(_tree().get_first_node_in_group("crime") != null, "there is law")
	assert_true(_tree().get_first_node_in_group("economy") != null, "and a market")
	await _drop(w)


func test_doors_stand_in_the_ground_where_their_plans_say() -> void:
	var w := _world()
	await w.world_ready
	var doors: Node = w.get_node("Doors")
	assert_gt(doors.placed.size(), 20, "twenty-four interiors, twenty-four ways in")
	var seen := {}
	for door in doors.placed:
		assert_true(ContentDB.has(door.interior_id))
		seen[door.interior_id] = true
		var ground := World.terrain().get_height(door.global_position.x, door.global_position.z)
		assert_true(absf(door.global_position.y - ground) < 1.0, "%s is not buried" % door.interior_id)
		assert_true(door.is_in_group("interactable"), "and can be walked up to")
	assert_eq(seen.size(), doors.placed.size(), "no interior has two front doors")
	await _drop(w)


func test_a_locked_house_is_somebody_in_particular_s_house() -> void:
	var w := _world()
	await w.world_ready
	var doors: Node = w.get_node("Doors")
	var locked := 0
	for door in doors.placed:
		var lock: Node = door.get_node_or_null("DoorLock")
		if lock == null:
			continue
		locked += 1
		assert_true(lock.is_locked())
		if lock.owner_npc != "":
			assert_true(ContentDB.has(lock.owner_npc), "%s is locked against a nobody" % door.interior_id)
	assert_gt(locked, 0, "some doors in the Vale are shut")
	await _drop(w)
