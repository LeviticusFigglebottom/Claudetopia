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


# --- what is out there -----------------------------------------------------------------------------

func test_the_country_has_things_in_it_that_will_fight_you() -> void:
	var w := _world()
	await w.world_ready
	# Walk the streamer to a piece of country the builder actually put somebody in.
	var where := _a_cell_with_spawns()
	assert_true(where != Vector3.INF, "the built world has encounters in it")
	# Let the world finish standing its own body up first. `PlayerSpawn` also waits on
	# `world_ready` and puts the player at the opening place, and the streamer follows whatever
	# body this world owns — so moving the target in the same frame moved it, and then the
	# spawn put the player back in the Cinderlea and the streaming went with it. Twenty-five
	# cells would load, none of them the one asked for, for thirty seconds.
	var settle := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < settle:
		await _tree().process_frame
		if w.is_ancestor_of(_tree().get_first_node_in_group("player") as Node) if _tree().get_first_node_in_group("player") != null else false:
			break
	w.force_stream_around(where)
	# Cells parse on worker threads and build a bounded number per frame, and a full run has
	# other suites' work in the queue; wait for the cell itself rather than a frame count.
	var wanted := w.streamer.cell_of(where)
	# Wait on the clock, not on a frame count. Cells parse on worker threads, and a headless
	# frame costs almost nothing, so 900 iterations of `process_frame` can pass in under a
	# second on an idle machine and in far less than the parse takes on a loaded one — which is
	# how this test came to fail about one run in three in a full suite and pass every time on
	# its own. Thirty seconds is longer than the parse has ever taken here.
	var loaded := false
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await _tree().process_frame
		if w.streamer.is_loaded(wanted):
			loaded = true
			break
	# If this ever fails, the first question is whether the tree was paused: `process_frame`
	# still fires while paused and `_physics_process` does not, and the streamer drains its
	# parsed cells from physics — so a screen left open by an earlier test stops the world
	# arriving while this loop spins happily.
	assert_true(loaded, "cell %s never finished streaming in 30 s (tree paused: %s, streamer enabled: %s, target: %s, loaded cells: %d), so this test proved nothing"
		% [wanted, _tree().paused, w.streamer.enabled,
			w.streamer.target.name if w.streamer.target != null else "none", w.streamer.loaded_count()])
	# The cell being loaded is not the same as the bodies in it standing up: the spawner builds
	# them over the frames after the parse, so breaking on `is_loaded` and counting immediately
	# is a race that a loaded machine loses. Wait for the thing being asserted on.
	var enemies: Array = []
	var spawn_deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < spawn_deadline:
		enemies = _tree().get_nodes_in_group("enemy")
		if not enemies.is_empty():
			break
		await _tree().process_frame
	assert_gt(enemies.size(), 0, "somebody is out on the downs (cell %s loaded: %s)" % [wanted, loaded])
	for e in enemies:
		var body := e as Node3D
		var ground := World.terrain().get_height(body.global_position.x, body.global_position.z)
		assert_true(absf(body.global_position.y - ground) < 3.0, "%s stands on the ground" % e.name)
	await _drop(w)


func test_encounters_keep_off_the_roads_and_out_of_the_villages() -> void:
	# The rule the placer works to, checked against the built data rather than the code that
	# wrote it: nothing camps in the square outside the inn.
	var spawns := 0
	var dir := DirAccess.open("res://world/generated/cells")
	assert_true(dir != null, "the world has been built")
	var places: Array = []
	for p in ContentDB.all("place"):
		if ["city", "town", "village", "hamlet"].has(str(p.get("kind", ""))):
			places.append(p)
	for file in dir.get_files():
		var text := FileAccess.get_file_as_string("res://world/generated/cells/" + file)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		for entry in (parsed as Dictionary).get("spawns", []):
			spawns += 1
			var p: Array = (entry as Dictionary).get("pos", [0, 0, 0])
			var at := Vector2(float(p[0]), float(p[2]))
			for place in places:
				var xz: Array = place.get("position", [0, 0])
				var d := at.distance_to(Vector2(float(xz[0]), float(xz[1])))
				assert_true(d > 35.0, "%s is camped in %s" % [entry.get("def", "?"), place.get("name", "?")])
	assert_gt(spawns, 100, "the world is not empty")


## The middle of some cell the builder wrote encounters into, in world coordinates.
func _a_cell_with_spawns() -> Vector3:
	var dir := DirAccess.open("res://world/generated/cells")
	if dir == null:
		return Vector3.INF
	for file in dir.get_files():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/cells/" + file))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var spawns: Array = (parsed as Dictionary).get("spawns", [])
		if spawns.size() < 3:
			continue
		var p: Array = (spawns[0] as Dictionary).get("pos", [])
		if p.size() == 3:
			return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Vector3.INF
