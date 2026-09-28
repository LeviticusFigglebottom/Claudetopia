extends TestCase
## The horse over the ground (triage 58): ridden down slopes of 5° to 34° at every gait.
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
