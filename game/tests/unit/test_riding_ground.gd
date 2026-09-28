extends TestCase
## The horse over the ground (triage 58, 59): ridden down slopes of 5° to 34° at every gait, and
## jumping -- a rail at a gallop and a canter, a hedge at a gallop, a house wall refused, the
## stamina it costs, the rider in the saddle all the way.
##
## The ground is a real Terrain3D with its collision (test_riding's way): lanes of planar ramp side
## by side, each rising toward -z from FOOT_Z, and a flat field east of them where the fences stand.

const PLAYER := preload("res://actors/player/player.tscn")
const KEYS: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_ALT, KEY_C, KEY_E, KEY_SPACE]
const ANGLES: Array[float] = [5.0, 10.0, 20.0, 30.0, 34.0]
const SPACING := 2.0
const VERTS := 256
const LANE := 24.0
const LANE_HALF := 10.0
const FIRST_LANE_X := 30.0
const FOOT_Z := 440.0
## The flat field: everything east of this is level ground at 0.
const FIELD_X := 200.0
const HORSE := "core:mount/wardens_cob"
## The keys each gait is asked for with (Rider.wanted_gait).
const GAIT_KEYS := {"Walk": [KEY_W, KEY_ALT], "Trot": [KEY_W, KEY_C], "Canter": [KEY_W], "Gallop": [KEY_W, KEY_SHIFT]}

var player: Player = null
var horse: Mount = null
var _terrain: Node3D = null
var _provider: TerrainProvider = null
var _world: World = null
var _was_world: World = null
var _stable: Stable = null
var _solids: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(7)
	SaveSystem.pending.clear()
	Settings.load_settings()
	Settings._load_binding_defs()
	Settings.apply_bindings()
	Settings.data["controls"]["sprint_tap_rolls"] = false
	Settings.data["controls"]["toggle_sprint"] = false


func after_each() -> void:
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
	Settings.apply_bindings()
	GameState.reset_for_new_game(7)


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.physical_keycode = code as Key
	ev.key_label = code as Key
	ev.pressed = pressed
	ev.shift_pressed = pressed and code == KEY_SHIFT
	ev.alt_pressed = pressed and code == KEY_ALT
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _ticks(n: int) -> void:
	for i in n:
		await _tree().physics_frame


static func _lane_x(lane: int) -> float:
	return FIRST_LANE_X + LANE * float(lane)


static func ground_at(x: float, z: float) -> float:
	if x >= FIELD_X:
		return 0.0
	var lane := int(floor((x - FIRST_LANE_X + LANE * 0.5) / LANE))
	if lane < 0 or lane >= ANGLES.size() or absf(x - _lane_x(lane)) > LANE_HALF:
		return 0.0
	return tan(deg_to_rad(ANGLES[lane])) * maxf(0.0, FOOT_Z - z)


func _ground() -> bool:
	if not ClassDB.class_exists("Terrain3D"):
		print("    SKIPPED: no Terrain3D in this build")
		return false
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	_terrain = ClassDB.instantiate("Terrain3D") as Node3D
	_terrain.name = "RideGround"
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
	_provider.sea_level = -50.0
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


## In the saddle at `at` facing `yaw`, the view behind the horse so that W is the way it faces.
func _seat(at: Vector3, yaw: float) -> bool:
	if player.rider.riding():
		player.rider.drop_for_teleport()
	player.teleport(at + Vector3(3.0, 1.0, 0.0), yaw)
	horse.place(Vector3(at.x, ground_at(at.x, at.z), at.z), yaw)
	horse.stamina = horse.max_stamina
	horse.spent = false
	await _ticks(10)
	if not player.rider.seat_now(horse):
		fail("could not get into the saddle")
		return false
	player.camera_rig.yaw = yaw
	await _ticks(2)
	return true


func _hold(keys: Array, down: bool) -> void:
	for k in keys:
		_key(k, down)


## A solid box standing on the ground, on `layer`: a run of rails, a hedge, a house wall.
func _solid(centre: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	_tree().root.add_child(body)
	body.global_position = centre
	_solids.append(body)
	return body


# --- downhill -----------------------------------------------------------------------------------

## Down one lane at one gait for `seconds`: speeds each half second, the lowest speed once up to
## pace, the gaits shown, what held it back, how far the body strayed from the ground under it.
func _downhill(lane: int, gait: String, seconds: float) -> Dictionary:
	var run_len := float(Mount.SPEEDS[gait]) * seconds + 12.0
	var start := Vector3(_lane_x(lane), 0.0, FOOT_Z - run_len)
	if not await _seat(start, PI):     # facing +z: down the lane
		return {}
	var keys: Array = GAIT_KEYS[gait]
	_hold(keys, true)
	var n := int(seconds * Engine.physics_ticks_per_second)
	var speeds: Array[String] = []
	var gaits: Array[String] = []
	var held := {}
	var off_floor := 0
	var worst_gap := 0.0
	var worst_sink := 0.0
	var slowest_after := INF
	var up_to_pace := -1.0
	var jitter := 0.0
	var last_y := horse.global_position.y
	var last_dy := 0.0
	# a lambda holds its own copy of a local: what it hears goes in a dictionary both share
	var said := {"n": 0}
	var on_ref := func(_r: String) -> void: said["n"] = int(said["n"]) + 1
	horse.refused.connect(on_ref)
	for i in n:
		await _tree().physics_frame
		var p := horse.global_position
		if p.z > FOOT_Z - 2.0:
			break
		var g := ground_at(p.x, p.z)
		# the model's middle (the body let down onto the hill) against the ground under it
		var stood := horse.stands_at().y
		if i > 20:
			worst_gap = maxf(worst_gap, stood - g)
			worst_sink = maxf(worst_sink, maxf(g - stood, g - p.y))
		if not horse.is_on_floor():
			off_floor += 1
		var dy := p.y - last_y
		jitter = maxf(jitter, absf(dy - last_dy))
		last_dy = dy
		last_y = p.y
		if horse.gait != "" and (gaits.is_empty() or gaits[-1] != horse.gait):
			gaits.append(horse.gait)
		if horse.held_back != "":
			held[horse.held_back] = true
		if i % int(Engine.physics_ticks_per_second / 2) == 0:
			speeds.append("%.1f" % horse.speed)
		var t := float(i) / Engine.physics_ticks_per_second
		if up_to_pace < 0.0 and horse.speed >= float(Mount.SPEEDS[gait]) * 0.9:
			up_to_pace = t
		elif up_to_pace >= 0.0:
			slowest_after = minf(slowest_after, horse.speed)
	horse.refused.disconnect(on_ref)
	_hold(keys, false)
	var out := {"gait": gait, "angle": ANGLES[lane], "speeds": speeds, "gaits": gaits, "held": held.keys(),
			"off_floor": off_floor, "gap": worst_gap, "sink": worst_sink, "up_to_pace": up_to_pace,
			"slowest": slowest_after, "jitter": jitter, "refused": int(said["n"]), "final": horse.speed}
	return out


func test_the_horse_goes_down_hill_at_the_gait_asked() -> void:
	if not await _ground():
		return
	# what each gait may be slowed to going down, by the angle (a walk is a walk anywhere)
	var report: Array[String] = []
	for lane in ANGLES.size():
		for gait in ["Walk", "Trot", "Canter", "Gallop"]:
			var r := await _downhill(lane, gait, 5.0)
			if r.is_empty():
				return
			var a: float = r["angle"]
			var cap := Mount.downhill_cap(gait)
			var should := a <= cap
			report.append("%2.0f° %-6s up %.1fs slowest %.1f final %.1f gaits %s held %s off-floor %d gap %.2f sink %.2f jitter %.3f refused %d  [%s]" % [
					a, gait, float(r["up_to_pace"]), float(r["slowest"]), float(r["final"]), " > ".join(PackedStringArray(r["gaits"])),
					str(r["held"]), int(r["off_floor"]), float(r["gap"]), float(r["sink"]), float(r["jitter"]), int(r["refused"]),
					" ".join(PackedStringArray(r["speeds"]))])
			assert_eq(int(r["refused"]), 0, "%.0f° down at a %s: the horse refused" % [a, gait])
			assert_true(float(r["final"]) > 1.2, "%.0f° down at a %s: the horse stalled (%.2f m/s at the end)" % [a, gait, float(r["final"])])
			assert_true(float(r["gap"]) < 0.25, "%.0f° down at a %s: the horse left the ground by %.2f m" % [a, gait, float(r["gap"])])
			assert_true(float(r["sink"]) < 0.2, "%.0f° down at a %s: the horse sank %.2f m into it" % [a, gait, float(r["sink"])])
			if should:
				assert_true(float(r["up_to_pace"]) >= 0.0, "%.0f° down at a %s: never got up to pace: %s" % [a, gait, str(r)])
				assert_true(float(r["slowest"]) > float(Mount.SPEEDS[gait]) * 0.85, "%.0f° down at a %s: slowed to %.2f m/s once up to pace" % [a, gait, float(r["slowest"])])
	print("    down hill, each gait asked:\n      " + "\n      ".join(report))


# --- jumping ------------------------------------------------------------------------------------

## A run at a fence on the flat field: up to `gait` over `run_up` m, jump pressed `press_at` m
## short of the obstacle's near face, held for a few ticks. What happened.
func _run_at(obstacle_z: float, gait: String, press_at: float, run_up := 34.0) -> Dictionary:
	var x := 360.0
	if not await _seat(Vector3(x, 0.0, obstacle_z + run_up), 0.0):   # facing -z
		return {}
	var keys: Array = GAIT_KEYS[gait]
	_hold(keys, true)
	var pressed := false
	var pressed_at := -1
	# the legs folded under (HorseLeapPose) over the top: the fore and hind hooves up off the body's
	# feet. A modifier's pose is only there while the skeleton is being updated, so it is read then.
	var folded := {"fore": INF, "hind": INF}
	var on_pose := func() -> void:
		if horse.jump_phase() == "air":
			folded["fore"] = minf(float(folded["fore"]), _hoof_up(horse, "FrontHoof.L"))
			folded["hind"] = minf(float(folded["hind"]), _hoof_up(horse, "HindHoof.R"))
	horse.model.skeleton.skeleton_updated.connect(on_pose)
	var jumped := false
	var top := 0.0
	var stamina_before := 0.0
	var seated := true
	var rider_off := 0.0
	var said := {"why": ""}
	var on_ref := func(r: String) -> void: said["why"] = r
	horse.refused.connect(on_ref)
	var landed_speed := -1.0
	var was_air := false
	var worst_sink := 0.0
	var clip_seen := {}
	var spent := 0.0
	var biggest_cost := 0.0
	var stamina_prev := horse.stamina
	for i in int(9.0 * Engine.physics_ticks_per_second):
		await _tree().physics_frame
		var p := horse.global_position
		var front := p.z - 1.0
		if not pressed and front - obstacle_z <= press_at:
			pressed = true
			pressed_at = i
			stamina_before = horse.stamina
			_key(KEY_SPACE, true)
		if pressed and i == pressed_at + 4:
			_key(KEY_SPACE, false)
		if horse.is_jumping():
			if not jumped:
				spent = stamina_prev - horse.stamina
			jumped = true
			was_air = true
			top = maxf(top, p.y)
			clip_seen[horse.jump_phase()] = true
		elif was_air:
			was_air = false
			landed_speed = horse.speed
		worst_sink = maxf(worst_sink, -p.y)
		biggest_cost = maxf(biggest_cost, stamina_prev - horse.stamina)
		stamina_prev = horse.stamina
		seated = seated and player.rider.is_seated()
		var hips := player.global_transform * player.rider._hips_local()
		# (from half a second in: the first ticks in the saddle are the seat being taken)
		if i > 30:
			rider_off = maxf(rider_off, hips.distance_to(horse.seat_transform().origin))
		if p.z < obstacle_z - 14.0 or (not str(said["why"]).is_empty() and absf(horse.speed) < 0.2):
			break
	horse.refused.disconnect(on_ref)
	horse.model.skeleton.skeleton_updated.disconnect(on_pose)
	var tuck := minf(float(folded["fore"]), float(folded["hind"]))
	_hold(keys, false)
	_key(KEY_SPACE, false)
	return {"jumped": jumped, "top": top, "z": horse.global_position.z, "refused": str(said["why"]), "spent": spent if jumped else stamina_before - horse.stamina,
			"seated": seated, "rider_off": rider_off, "landed_speed": landed_speed, "sink": worst_sink, "phases": clip_seen.keys(), "tuck": tuck, "fore": folded["fore"], "hind": folded["hind"], "biggest_cost": biggest_cost,
			"gait": gait}


## How far a hoof bone is over the body's origin (m): 0 standing, up with the legs folded.
static func _hoof_up(h: Mount, bone: String) -> float:
	var sk := h.model.skeleton
	var b := sk.find_bone(bone) if sk != null else -1
	if b < 0:
		return INF
	return (sk.global_transform * sk.get_bone_global_pose(b).origin).y - h.global_position.y


func test_the_horse_clears_a_rail_at_a_gallop_and_a_canter() -> void:
	if not await _ground():
		return
	# a run of rails as the wayside stands them (wayside.gd: the box 1.6 m tall, sunk 0.4, 0.2 thick)
	var rail_z := 200.0
	_solid(Vector3(360.0, 0.4, rail_z), Vector3(12.0, 1.6, 0.2), Actor.LAYER_SCATTER)
	for gait in ["Gallop", "Canter"]:
		# pressed early (the horse times its own stride) and pressed late
		for press_at in [9.0, 3.0]:
			var r := await _run_at(rail_z, gait, press_at)
			if r.is_empty():
				return
			print("    at a %s, pressed %.0f m out: %s" % [gait, press_at, str(r)])
			assert_true(bool(r["jumped"]), "at a %s the horse never left the ground: %s" % [gait, str(r)])
			assert_true(float(r["z"]) < rail_z - 3.0, "at a %s the horse did not get over the rail (stopped at z %.1f): %s" % [gait, float(r["z"]), str(r)])
			assert_eq(str(r["refused"]), "", "at a %s it refused the rail" % gait)
			assert_true(float(r["top"]) > 1.0 and float(r["top"]) < 1.8, "at a %s the jump rose %.2f m" % [gait, float(r["top"])])
			assert_true(float(r["spent"]) >= Mount.JUMP_COST * 0.9, "the jump cost %.1f stamina" % float(r["spent"]))
			assert_true(bool(r["seated"]), "the rider left the saddle over the rail")
			assert_true(float(r["rider_off"]) < 0.45, "the rider's hips went %.2f m from the seat" % float(r["rider_off"]))
			assert_true(float(r["landed_speed"]) > float(Mount.SPEEDS[gait]) * 0.75, "at a %s the landing stalled it to %.1f m/s" % [gait, float(r["landed_speed"])])
			assert_true(float(r["sink"]) < 0.2, "the horse landed %.2f m into the ground" % float(r["sink"]))
			assert_true(float(r["tuck"]) > 0.3 and float(r["tuck"]) != INF, "over the top the hooves hung %.2f m off the body's feet: the legs are not folded" % float(r["tuck"]))
			assert_true(r["phases"].has("takeoff") and r["phases"].has("land"), "the leap's phases: %s" % str(r["phases"]))


func test_the_horse_clears_a_hedge_at_a_gallop() -> void:
	if not await _ground():
		return
	# a hedge as ScatterSolids stands it: the box of the forge's bounds (1.88 m tall, 0.7 thick)
	var hedge_z := 200.0
	_solid(Vector3(360.0, 0.94 - 0.2, hedge_z), Vector3(12.0, 1.88 + 0.4, 0.7), Actor.LAYER_SCATTER)
	var r := await _run_at(hedge_z, "Gallop", 10.0)
	if r.is_empty():
		return
	print("    a hedge at a gallop: %s" % str(r))
	assert_true(float(r["z"]) < hedge_z - 3.0, "the horse did not get over the hedge: %s" % str(r))
	assert_true(bool(r["seated"]), "the rider left the saddle over the hedge")


func test_the_horse_refuses_a_wall_and_never_lands_in_one() -> void:
	if not await _ground():
		return
	# a house wall, 3 m of it: refused, and the horse stops short of it, not in it
	var wall_z := 200.0
	_solid(Vector3(360.0, 1.5, wall_z), Vector3(12.0, 3.0, 0.4), Actor.LAYER_WORLD)
	var r := await _run_at(wall_z, "Gallop", 6.0)
	if r.is_empty():
		return
	print("    a wall at a gallop: %s" % str(r))
	assert_false(bool(r["jumped"]), "the horse jumped at a 3 m wall")
	assert_ne(str(r["refused"]), "", "the horse did not refuse the wall")
	assert_true(float(r["z"]) > wall_z + 0.9, "the horse went into the wall (z %.2f against %.2f)" % [float(r["z"]), wall_z])
	assert_true(float(r["biggest_cost"]) < 1.0, "a refusal cost %.1f stamina at once" % float(r["biggest_cost"]))
	# a rail with a wall 4 m past it: nowhere to land, refused
	for n in _solids:
		n.queue_free()
	_solids.clear()
	await _ticks(2)
	_solid(Vector3(360.0, 0.4, wall_z), Vector3(12.0, 1.6, 0.2), Actor.LAYER_SCATTER)
	_solid(Vector3(360.0, 1.5, wall_z - 4.0), Vector3(12.0, 3.0, 4.0), Actor.LAYER_WORLD)
	var boxed := await _run_at(wall_z, "Canter", 4.0)
	print("    a rail with a wall behind it: %s" % str(boxed))
	assert_false(bool(boxed["jumped"]), "the horse jumped into a wall")
	assert_true(float(boxed["z"]) > wall_z, "the horse is past the rail, in the wall's lee: z %.2f" % float(boxed["z"]))


func test_a_standing_hop_and_a_tired_horse() -> void:
	if not await _ground():
		return
	if not await _seat(Vector3(360.0, 0.0, 300.0), 0.0):
		return
	var y0 := horse.global_position.y
	_key(KEY_SPACE, true)
	var top := 0.0
	var went := false
	for i in 60:
		await _tree().physics_frame
		if i == 3:
			_key(KEY_SPACE, false)
		went = went or horse.is_jumping()
		top = maxf(top, horse.global_position.y - y0)
	assert_true(went, "a standing horse did not hop")
	assert_true(top > 0.25 and top < 0.8, "the standing hop rose %.2f m" % top)
	assert_false(horse.is_jumping(), "the hop never came down")
	assert_true(player.rider.is_seated(), "the hop threw the rider")
	# spent: no jump, and it says so
	horse.stamina = Mount.HOP_COST * 0.5
	var said := {"why": ""}
	var on_ref := func(r: String) -> void: said["why"] = r
	horse.refused.connect(on_ref)
	_key(KEY_SPACE, true)
	await _ticks(4)
	_key(KEY_SPACE, false)
	await _ticks(20)
	horse.refused.disconnect(on_ref)
	assert_eq(str(said["why"]), "tired", "a tired horse jumped (or refused for '%s')" % str(said["why"]))
