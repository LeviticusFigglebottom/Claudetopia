extends TestCase
## The horse comes to the whistle (the owner's three asks, 2026-09-30): pressing H whistles and the
## horse answers; it finds its way to the player over the ground, round a line of trees, through the
## gap in a wall, up the one way onto a bank, down off it without falling, over a stream by its ford,
## and from far off out of sight; and the first time in the saddle the player is told, once, how to
## whistle for it, with the key bound now.
##
## The ground is one Terrain3D (SPACING m a vertex) with an arena for each case, and StaticBody3D
## trunks and walls on the world layer. Each walk is asserted to arrive within a time, beside the
## player and facing them, without the body ever inside a solid, and without a fall of more than a step.

const PLAYER := preload("res://actors/player/player.tscn")
const KEYS: Array[Key] = [KEY_E, KEY_H, KEY_J]
const SPACING := 2.0
const VERTS := 256
const BASE := 2.0
const HORSE := "core:mount/wardens_cob"
## The bank: a plateau BANK_H over the base for z < BANK_Z, a cliff down off it, and one ramp.
const BANK_X := Vector2(270.0, 370.0)
const RAMP_X := Vector2(352.0, 368.0)
const BANK_Z := 80.0
const BANK_H := 6.0
## The stream: along z = STREAM_Z the width of the map, too deep to wade but at its ford.
const STREAM_Z := 240.0
const FORD_X := Vector2(440.0, 452.0)
## The most a horse may come down in the air before it is on the ground again (m): a step.
const STEP_M := 0.6

var player: Player = null
var horse: Mount = null
var _terrain: Node3D = null
var _provider: TerrainProvider = null
var _world: World = null
var _was_world: World = null
var _stable: Stable = null
var _solids: Array[Node] = []
var _notes: Array[String] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(7)
	SaveSystem.pending.clear()
	Settings.load_settings()
	Settings._load_binding_defs()
	Settings.apply_bindings()
	_notes.clear()
	if not EventBus.notify.is_connected(_on_notify):
		EventBus.notify.connect(_on_notify)


func after_each() -> void:
	if EventBus.notify.is_connected(_on_notify):
		EventBus.notify.disconnect(_on_notify)
	for k in KEYS:
		_key(k, false)
	for n in _solids:
		if is_instance_valid(n):
			n.queue_free()
	_solids.clear()
	for n in [horse, player, _stable, _terrain]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	horse = null
	player = null
	_stable = null
	_terrain = null
	if World.instance == _world:
		World.instance = _was_world
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	if _provider != null and is_instance_valid(_provider):
		_provider.free()
	_provider = null
	Settings.load_settings()
	Settings._load_binding_defs()
	Settings.apply_bindings()
	GameState.reset_for_new_game(7)


func _on_notify(text: String, _kind: String) -> void:
	_notes.append(text)


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.physical_keycode = code as Key
	ev.key_label = code as Key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _tap(code: int) -> void:
	_key(code, true)
	await _ticks(4)
	_key(code, false)
	await _ticks(2)


func _ticks(n: int) -> void:
	for i in n:
		await _tree().physics_frame


static func ground_at(x: float, z: float) -> float:
	# the stream, across the whole map
	var s := absf(z - STREAM_Z)
	if s < 12.0:
		var floor_h := -0.3 if x >= FORD_X.x and x <= FORD_X.y else -2.0
		return floor_h if s < 4.0 else lerpf(floor_h, BASE, (s - 4.0) / 8.0)
	# the bank: a cliff, and a ramp up it
	if x >= BANK_X.x and x <= BANK_X.y and z < BANK_Z + 40.0:
		var run := 30.0 if x >= RAMP_X.x and x <= RAMP_X.y else 4.0
		return BASE + BANK_H * (1.0 - clampf((z - BANK_Z) / run, 0.0, 1.0))
	return BASE


func _ground() -> bool:
	if not ClassDB.class_exists("Terrain3D"):
		print("    SKIPPED: no Terrain3D in this build")
		return false
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	_terrain = ClassDB.instantiate("Terrain3D") as Node3D
	_terrain.name = "CallGround"
	_tree().root.add_child(_terrain)
	_terrain.call("set_camera", player.camera_rig.camera)
	await _tree().process_frame
	_terrain.call("change_region_size", VERTS)
	_terrain.set("vertex_spacing", SPACING)
	var img := Image.create_empty(VERTS, VERTS, false, Image.FORMAT_RF)
	for pz in VERTS:
		for px in VERTS:
			img.set_pixel(px, pz, Color(ground_at(float(px) * SPACING, float(pz) * SPACING), 0.0, 0.0))
	var images: Array[Image] = [img, null, null]
	_terrain.get("data").call("import_images", images, Vector3.ZERO, 0.0, 1.0)
	var col: Object = _terrain.get("collision")
	col.set("mode", 3)
	if col.has_method("build"):
		col.call("build")
	_provider = TerrainProvider.new()
	_provider.bind_terrain(_terrain)
	_provider.sea_level = 0.0
	_world = World.new()
	_world.provider = _provider
	_world.is_world_ready = true
	_was_world = World.instance
	World.instance = _world
	_stable = Stable.new()
	_stable.name = "Stable"
	_tree().root.add_child(_stable)
	for i in 120:
		if bool(_stable.get("_ready_to_stand")):
			break
		await _tree().process_frame
	horse = _stable.give(HORSE, false)
	await _ticks(3)
	if horse == null:
		fail("the Stable stood no horse")
	return horse != null


## Something solid on the world layer: a box (`size`) or a trunk (`size.x` its radius).
func _solid(at: Vector3, size: Vector3, trunk := false) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	if trunk:
		var c := CylinderShape3D.new()
		c.radius = size.x
		c.height = size.y
		cs.shape = c
	else:
		var b := BoxShape3D.new()
		b.size = size
		cs.shape = b
	body.add_child(cs)
	_tree().root.add_child(body)
	body.global_position = Vector3(at.x, ground_at(at.x, at.z) + size.y * 0.5 - 0.2, at.z)
	_solids.append(body)


func _put(horse_at: Vector2, player_at: Vector2, player_yaw: float) -> void:
	horse.place(Vector3(horse_at.x, ground_at(horse_at.x, horse_at.y), horse_at.y), 0.0)
	player.teleport(Vector3(player_at.x, ground_at(player_at.x, player_at.y) + 0.02, player_at.y), player_yaw)
	player.camera_rig.yaw = player_yaw
	player.camera_rig.pitch = -0.2
	await _ticks(20)


## Whistles with H and follows the horse until it has come and stood, for up to `limit` s. Returns
## what happened: arrived (s, or -1), the worst fall in the air, the solids it was found in, how
## far and how turned from the player it stood, and whether it answered.
func _whistle_and_watch(limit: float) -> Dictionary:
	var heard: Array[String] = []
	var listen := func(id: String, _at: Vector3) -> void: heard.append(id)
	Foley.played.connect(listen)
	await _tap(KEY_H)
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 1.0, 1.6)
	var space := horse.get_world_3d().direct_space_state
	var worst_fall := 0.0
	var deepest := 0.0
	var fall := 0.0
	var most_points := 0
	var inside := 0
	var arrived := -1.0
	var hz := Engine.physics_ticks_per_second
	for i in int(limit * hz):
		await _tree().physics_frame
		# in the air over the ground under it (a fall off a bank leaves it high over the foot)
		var y := horse.global_position.y
		# the ground under its middle and under each pair of hooves: it stands on the highest
		var g := -INF
		for k in [-1.0, 0.0, 1.0]:
			var p := horse.global_position + horse.forward() * Mount.HALF_BASE * float(k)
			g = maxf(g, float(World.terrain().call("get_height", p.x, p.z)))
		fall = y - g
		worst_fall = maxf(worst_fall, fall)
		most_points = maxi(most_points, horse.way_points().size())
		deepest = maxf(deepest, horse.water_depth(horse.global_position))
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = box
		q.transform = Transform3D(Basis(Vector3.UP, horse.heading), horse.global_position + Vector3(0.0, 0.75, 0.0))
		q.collision_mask = Actor.LAYER_WORLD
		for hit in space.intersect_shape(q, 4):
			if _solids.has(hit.get("collider")):
				inside += 1
				break
		if horse.mode == Mount.Mode.STAND and i > hz:
			arrived = float(i) / float(hz)
			break
	Foley.played.disconnect(listen)
	var to := player.global_position - horse.global_position
	to.y = 0.0
	var facing := rad_to_deg(absf(wrapf(atan2(-to.x, -to.z) - horse.heading, -PI, PI)))
	return {"arrived": arrived, "fall": worst_fall, "inside": inside, "dist": to.length(),
			"facing": facing, "heard": heard, "way": most_points, "deepest": deepest}


func _assert_came(r: Dictionary, what: String, limit: float) -> void:
	assert_true(float(r["arrived"]) > 0.0, "%s: the horse had not come after %.0f s (%.1f m off)" % [what, limit, float(r["dist"])])
	assert_eq(int(r["inside"]), 0, "%s: the horse was inside a solid for %d ticks" % [what, int(r["inside"])])
	assert_true(float(r["fall"]) < STEP_M, "%s: the horse fell %.2f m" % [what, float(r["fall"])])
	assert_true(float(r["dist"]) > 1.8 and float(r["dist"]) < Mount.ARRIVE_M + 0.8,
			"%s: it stood %.1f m from the player" % [what, float(r["dist"])])
	assert_true(float(r["facing"]) < 20.0, "%s: it stood turned %.0f° from the player" % [what, float(r["facing"])])
	assert_true((r["heard"] as Array).has("horse_whistle"), "%s: no whistle was heard: %s" % [what, str(r["heard"])])
	assert_true((r["heard"] as Array).has("horse_whinny") or (r["heard"] as Array).has("horse_snort"),
			"%s: the horse did not answer: %s" % [what, str(r["heard"])])
	print("    %s: came in %.1f s by %d points, stood %.1f m off facing %.0f°, worst fall %.2f m" % [
			what, float(r["arrived"]), int(r["way"]), float(r["dist"]), float(r["facing"]), float(r["fall"])])


# --- the whistle ---------------------------------------------------------------------------------

func test_the_whistle_and_the_answer_are_the_projects_own_sounds() -> void:
	for id in ["horse_whistle", "horse_whinny", "horse_snort"]:
		assert_true(Foley.has(id), "no sfx row for %s (tools/audio/gen_sfx.py)" % id)
		var row: Dictionary = Foley.rows.get(id, {})
		assert_true((row.get("files", []) as Array).size() >= 3, "%s has too few variants to vary" % id)
		assert_eq(str(row.get("bus", "")), "SFX", "%s is not a world sound" % id)
		for f in row.get("files", []):
			assert_true(ResourceLoader.exists(str(f)), "missing %s" % str(f))


func test_a_whistle_with_no_horse_still_whistles_and_says_so() -> void:
	_stable = Stable.new()
	_tree().root.add_child(_stable)
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	await _ticks(5)
	var heard: Array[String] = []
	var listen := func(id: String, _at: Vector3) -> void: heard.append(id)
	Foley.played.connect(listen)
	await _tap(KEY_H)
	Foley.played.disconnect(listen)
	assert_true(heard.has("horse_whistle"), "no whistle: %s" % str(heard))
	assert_true(_notes.any(func(t: String) -> bool: return t.contains("no horse")), "no notice: %s" % str(_notes))


# --- the way over the ground ---------------------------------------------------------------------

func test_the_horse_comes_round_a_line_of_trees() -> void:
	if not await _ground():
		return
	var x := 50.0
	while x <= 110.0:
		_solid(Vector3(x, 0.0, 80.0), Vector3(0.35, 6.0, 0.0), true)
		x += 1.2
	await _put(Vector2(80.0, 100.0), Vector2(80.0, 60.0), 0.0)
	_assert_came(await _whistle_and_watch(35.0), "behind a line of trees", 35.0)


func test_the_horse_comes_through_the_gap_in_a_wall() -> void:
	if not await _ground():
		return
	_solid(Vector3(186.75, 0.0, 80.0), Vector3(53.5, 1.8, 0.6))     # 160 .. 213.5
	_solid(Vector3(228.25, 0.0, 80.0), Vector3(23.5, 1.8, 0.6))     # 216.5 .. 240
	await _put(Vector2(190.0, 100.0), Vector2(190.0, 60.0), 0.0)
	var r := await _whistle_and_watch(35.0)
	_assert_came(r, "across a wall with a gap", 35.0)


func test_the_horse_comes_up_the_one_way_onto_a_bank() -> void:
	if not await _ground():
		return
	await _put(Vector2(310.0, 100.0), Vector2(310.0, 66.0), 0.0)
	_assert_came(await _whistle_and_watch(45.0), "below a steep bank", 45.0)


func test_the_horse_comes_down_off_a_bank_without_falling() -> void:
	if not await _ground():
		return
	await _put(Vector2(310.0, 66.0), Vector2(310.0, 100.0), PI)
	_assert_came(await _whistle_and_watch(45.0), "above a steep bank", 45.0)


func test_the_horse_crosses_a_stream_by_its_ford() -> void:
	if not await _ground():
		return
	await _put(Vector2(430.0, STREAM_Z + 25.0), Vector2(430.0, STREAM_Z - 25.0), 0.0)
	var r := await _whistle_and_watch(45.0)
	_assert_came(r, "across a stream", 45.0)
	assert_true(float(r["deepest"]) < Mount.WALK_DEPTH, "it went %.2f m deep: not by the ford" % float(r["deepest"]))


func test_the_horse_comes_from_far_off_out_of_sight() -> void:
	if not await _ground():
		return
	# facing +X down the open ground: the horse is brought round from behind, unseen
	await _put(Vector2(480.0, 500.0), Vector2(100.0, 400.0), -PI * 0.5)
	await _ticks(40)     # the Stable sleeps a horse so far off
	var cam := player.camera_rig.camera
	var was := horse.global_position
	await _tap(KEY_H)
	assert_true(horse.global_position.distance_to(was) > 50.0, "the far horse was not brought round")
	var at := horse.global_position
	for up in [0.3, 1.2, 2.0]:
		assert_false(cam.is_position_in_frustum(at + Vector3(0.0, float(up), 0.0)),
				"the horse was brought round in plain view, at %s" % str(at.round()))
	assert_true(at.distance_to(player.global_position) < 70.0, "brought round %.0f m off" % at.distance_to(player.global_position))
	# the rest of the way it comes itself (the whistle already went: count the walk)
	var t := 0
	var hz := Engine.physics_ticks_per_second
	while horse.mode != Mount.Mode.STAND and t < 30 * hz:
		await _tree().physics_frame
		t += 1
	assert_eq(horse.mode, Mount.Mode.STAND, "brought round, it had not come after 30 s (%.1f m off)" % horse.global_position.distance_to(player.global_position))
	var d := Vector2(horse.global_position.x - player.global_position.x, horse.global_position.z - player.global_position.z).length()
	assert_true(d < Mount.ARRIVE_M + 0.8, "it stood %.1f m off" % d)
	print("    from %.0f m off: brought round to %.0f m behind, came in %.1f s" % [was.distance_to(player.global_position), at.distance_to(player.global_position), float(t) / hz])


func test_a_horse_too_far_off_does_not_hear() -> void:
	if not await _ground():
		return
	await _put(Vector2(100.0, 100.0), Vector2(100.0, 110.0), 0.0)
	horse.place(Vector3(100.0 + Stable.FAR_M + 100.0, BASE, 100.0), 0.0)
	await _tap(KEY_H)
	assert_true(_notes.any(func(t: String) -> bool: return t.contains("too far")), "no notice: %s" % str(_notes))
	assert_ne(horse.mode, Mount.Mode.COMING, "a horse past hearing came")


# --- the hint ------------------------------------------------------------------------------------

func test_the_first_mount_teaches_the_whistle_once_with_its_key() -> void:
	if not await _ground():
		return
	# the whistle rebound: the hint names the key it is on now
	Settings.bindings["call_mount"] = ["key:J"]
	Settings.apply_bindings()
	horse.place(Vector3(200.0, BASE, 320.0), 0.0)
	player.teleport(Vector3(198.3, BASE + 0.02, 319.8), -PI * 0.5)
	player.camera_rig.pitch = -0.25
	await _ticks(20)
	assert_false(bool(GameState.get_flag(Rider.RIDE_TAUGHT_FLAG, false)), "a new game was already taught")
	for pass_n in 2:
		if pass_n == 0:
			# the first time up, from the keys
			for i in 30:
				if player.interactor.has_target():
					break
				await _ticks(1)
			await _tap(KEY_E)
			for i in 200:
				if player.rider.is_seated():
					break
				await _ticks(1)
		else:
			player.rider.seat_now(horse)
		assert_true(player.rider.is_seated(), "not in the saddle (time %d)" % (pass_n + 1))
		await _ticks(10)
		await _tap(KEY_E)
		for i in 150:
			if not player.rider.riding():
				break
			await _ticks(1)
		await _ticks(20)
	var taught := _notes.filter(func(t: String) -> bool: return t.contains("whistles for"))
	assert_eq(taught.size(), 1, "the riding hint was shown %d times: %s" % [taught.size(), str(_notes)])
	if taught.size() > 0:
		assert_true(str(taught[0]).contains("J whistles"), "the hint does not name the bound key: %s" % str(taught[0]))
	assert_true(bool(GameState.get_flag(Rider.RIDE_TAUGHT_FLAG, false)), "the hint was not remembered")
	# remembered with the game: in the save's flags
	var saved := GameState.to_save()
	GameState.reset_for_new_game(7)
	GameState.from_save(saved)
	assert_true(bool(GameState.get_flag(Rider.RIDE_TAUGHT_FLAG, false)), "the flag did not come back with the save")


func test_the_riding_hint_waits_for_a_quiet_moment() -> void:
	var r := Rider.new()
	r.set("_teach_owed", true)
	# no player in the tree: never a quiet moment, and nothing is said
	assert_false(r._quiet(), "a rider with no body found a quiet moment")
	r.free()
