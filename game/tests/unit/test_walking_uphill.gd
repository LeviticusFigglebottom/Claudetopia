extends TestCase
## The player walks, runs and sprints up the ground and jumps off it, from real key events, on a
## real Terrain3D: once standing on its own collision (as the game has it, Terrain3D building
## HeightMapShape3D collision round the body's camera) and once on the heightfield alone (no
## collider under the body, `Actor.snap_to_terrain` holding it up), which is what every other
## test's ground was.
##
## The ground is ten lanes of planar ramp side by side, 5° to 50°, on the 2 m vertex spacing the
## world uses, each with a flat run-up. Reported from a playtest on Terrain3D's collision: "walking
## upwards, at any incline, seems impossible", and "jump doesn't work".

const PLAYER := preload("res://actors/player/player.tscn")
const KEYS: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_ALT, KEY_SPACE]
## The slope of each lane, degrees. Below the walkable limit every gait climbs at its pace along
## the ground; 50° is above it.
const ANGLES: Array[float] = [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 50.0]
const SPACING := 2.0
const VERTS := 256
const LANE := 20.0
const LANE_HALF := 8.0
const FIRST_LANE_X := 30.0
## Each ramp rises toward -z (where W goes at yaw 0) from this line.
const FOOT_Z := 440.0
## How far before the foot each gait starts, to be up to speed at it (m).
const RUN_UP := {"walk": 2.5, "jog": 6.0, "sprint": 10.0}
const GAIT_KEYS := {"walk": [KEY_ALT, KEY_W], "jog": [KEY_W], "sprint": [KEY_SHIFT, KEY_W]}
## Measured from this far up the ramp (m, along the ground plan), for this long (s).
const INTO_RAMP := 1.5
const WINDOW_S := 0.8

var player: Player = null
var _terrain: Node3D = null
var _provider: TerrainProvider = null
var _world: World = null
var _was_world: World = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(7)
	SaveSystem.pending.clear()
	Settings.load_settings()
	Settings._load_binding_defs()
	Settings.apply_bindings()
	Settings.data["controls"]["sprint_tap_rolls"] = true
	Settings.data["controls"]["toggle_sprint"] = false


func after_each() -> void:
	_clear()
	Settings.load_settings()
	Settings.apply_bindings()
	GameState.reset_for_new_game(7)


## Lets go of every key and takes the body, the ground and the stand-in world away.
func _clear() -> void:
	for k in KEYS:
		_key(k, false)
	if player != null and is_instance_valid(player):
		player.queue_free()
	player = null
	if World.instance == _world:
		World.instance = _was_world
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = null
	if _provider != null and is_instance_valid(_provider):
		_provider.free()
	_provider = null
	if _terrain != null and is_instance_valid(_terrain):
		_terrain.queue_free()
	_terrain = null


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


## The ground's height at a world point: each lane a plane rising toward -z from FOOT_Z, flat
## before it and between the lanes.
static func ground_at(x: float, z: float) -> float:
	var lane := int(floor((x - FIRST_LANE_X + LANE * 0.5) / LANE))
	if lane < 0 or lane >= ANGLES.size() or absf(x - _lane_x(lane)) > LANE_HALF:
		return 0.0
	return tan(deg_to_rad(ANGLES[lane])) * maxf(0.0, FOOT_Z - z)


## A Terrain3D of the lanes, with its collision built for the whole of it (`collide`) or none, and
## the world's ground questions answered from it, as `World.terrain()` answers them in the game.
## The body is stood up first, so the terrain has its camera from its first frame (World.follow
## gives it the body's own camera in the game).
func _ground(collide: bool) -> bool:
	if not ClassDB.class_exists("Terrain3D"):
		return false
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	_terrain = ClassDB.instantiate("Terrain3D") as Node3D
	_terrain.name = "SlopeLanes"
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
	var data: Object = _terrain.get("data")
	data.call("import_images", images, Vector3.ZERO, 0.0, 1.0)
	var col: Object = _terrain.get("collision")
	col.set("mode", 3 if collide else 0)          # FULL_GAME: every region's collision, or none
	if collide and col.has_method("build"):
		col.call("build")
	_provider = TerrainProvider.new()
	_provider.bind_terrain(_terrain)
	_world = World.new()
	_world.provider = _provider
	_was_world = World.instance
	World.instance = _world
	await _ticks(3)
	return true


## Whether a ray down finds a collider on the ground at a point, and where.
func _collider_under(x: float, z: float) -> Variant:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 900.0, z), Vector3(x, -50.0, z))
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	return null if hit.is_empty() else (hit["position"] as Vector3).y


## One climb: the body put on `lane`'s run-up facing uphill, `gait`'s keys held, and measured
## from INTO_RAMP up the ramp for WINDOW_S: {climbed, along m/s, level m/s, rise m, on_ground share}.
func _climb(lane: int, gait: String) -> Dictionary:
	var x := _lane_x(lane)
	player.teleport(Vector3(x, 0.02, FOOT_Z + float(RUN_UP[gait])), 0.0)
	await _ticks(6)
	for k in GAIT_KEYS[gait]:
		_key(k, true)
	var out := {"climbed": false, "along": 0.0, "level": 0.0, "rise": 0.0, "on_ground": 0.0, "highest": 0.0}
	var window := int(WINDOW_S * Engine.physics_ticks_per_second)
	var speed := _gait_speed(gait)
	var limit := int(((float(RUN_UP[gait]) + INTO_RAMP) / speed + 0.8 + WINDOW_S + 1.0) * Engine.physics_ticks_per_second)
	var started := -1
	var last := player.global_position
	var first := last
	var grounded := 0
	for i in limit:
		await _tree().physics_frame
		var p := player.global_position
		out["highest"] = maxf(float(out["highest"]), p.y)
		if started < 0 and p.z <= FOOT_Z - INTO_RAMP:
			started = i
			first = p
		elif started >= 0:
			out["along"] = float(out["along"]) + p.distance_to(last)
			out["level"] = float(out["level"]) + Vector2(p.x - last.x, p.z - last.z).length()
			grounded += 1 if player._on_ground() else 0
			if i - started >= window:
				out["climbed"] = true
				out["rise"] = p.y - first.y
				break
		last = p
	for k in GAIT_KEYS[gait]:
		_key(k, false)
	out["along"] = float(out["along"]) / WINDOW_S
	out["level"] = float(out["level"]) / WINDOW_S
	out["on_ground"] = float(grounded) / float(window)
	await _ticks(20)
	return out


func _gait_speed(gait: String) -> float:
	return {"walk": Player.WALK_SPEED, "jog": Player.JOG_SPEED, "sprint": Player.SPRINT_SPEED}[gait]


## On Terrain3D's own collision, every gait climbs every slope under the walkable limit at its own
## pace along the ground, standing on it all the way; 50° is a wall.
func test_every_gait_climbs_every_walkable_slope_on_terrain3d_collision() -> void:
	if not await _ground(true):
		return
	var at: Variant = _collider_under(_lane_x(5), FOOT_Z - 10.0)
	assert_true(at != null, "Terrain3D built no collision to stand on")
	if at == null:
		return
	assert_near(float(at), ground_at(_lane_x(5), FOOT_Z - 10.0), 0.05, "the collider is the ramp")
	var report: Array[String] = []
	for gait in ["walk", "jog", "sprint"]:
		var row: Array[String] = []
		for lane in ANGLES.size():
			var angle: float = ANGLES[lane]
			var got := await _climb(lane, gait)
			var share := float(got["along"]) / _gait_speed(gait)
			if angle > Actor.WALKABLE_SLOPE_DEG:
				row.append("%.0f° wall (rose %.2f m)" % [angle, float(got["highest"])])
				assert_true(float(got["highest"]) < 0.5, "%s into a %.0f° slope climbed %.2f m of it" % [gait, angle, float(got["highest"])])
				continue
			row.append("%.0f° %.0f%%" % [angle, share * 100.0])
			assert_true(bool(got["climbed"]), "%s up %.0f°: the body never got %.1f m up the slope" % [gait, angle, INTO_RAMP])
			assert_true(share > 0.9, "%s up %.0f°: %.2f m/s along the ground, %.0f%% of its %.1f m/s" % [
					gait, angle, float(got["along"]), share * 100.0, _gait_speed(gait)])
			assert_true(float(got["on_ground"]) > 0.95, "%s up %.0f°: on the ground %.0f%% of the way" % [gait, angle, float(got["on_ground"]) * 100.0])
		report.append("%s: %s" % [gait, ", ".join(row)])
	print("    on Terrain3D's collision, speed along the ground as a share of the gait's: %s" % "; ".join(report))


## On the heightfield alone (no collider: `snap_to_terrain` holds the body up), a jog climbs every
## walkable slope at its pace along the ground.
func test_a_jog_climbs_on_the_heightfield_alone() -> void:
	if not await _ground(false):
		return
	assert_true(_collider_under(_lane_x(5), FOOT_Z - 10.0) == null, "there is a collider after all")
	var report: Array[String] = []
	for gait in ["jog"]:
		var row: Array[String] = []
		for lane in ANGLES.size():
			var angle: float = ANGLES[lane]
			if angle > Actor.WALKABLE_SLOPE_DEG:
				continue
			var got := await _climb(lane, gait)
			var share := float(got["along"]) / _gait_speed(gait)
			row.append("%.0f° %.0f%%" % [angle, share * 100.0])
			assert_true(bool(got["climbed"]) and share > 0.9, "%s up %.0f° on the heightfield: %.2f m/s along the ground, %.0f%% of its %.1f m/s" % [
					gait, angle, float(got["along"]), share * 100.0, _gait_speed(gait)])
		report.append("%s: %s" % [gait, ", ".join(row)])
	print("    on the heightfield alone: %s" % "; ".join(report))


## Space jumps the body JUMP_HEIGHT off the ground and it lands again, playing its take-off and its
## landing: on Terrain3D's collision and on the heightfield alone.
func test_a_jump_leaves_the_ground_and_lands_on_either() -> void:
	var report: Array[String] = []
	for collide in [true, false]:
		if not await _ground(collide):
			return
		var where := "on Terrain3D's collision" if collide else "on the heightfield alone"
		player.teleport(Vector3(_lane_x(0), 0.02, FOOT_Z + 6.0), 0.0)
		await _ticks(20)
		var floor_y := player.global_position.y
		_key(KEY_SPACE, true)
		await _ticks(2)
		_key(KEY_SPACE, false)
		var peak := floor_y
		var clips: Array[String] = []
		var left_at := -1
		var landed_at := -1
		for i in 120:
			await _tree().physics_frame
			var up := player.global_position.y - floor_y
			peak = maxf(peak, player.global_position.y)
			var clip := str(player.anim.current_clip)
			if clip != "" and (clips.is_empty() or clips[-1] != clip):
				clips.append(clip)
			if left_at < 0 and up > 0.02:
				left_at = i + 2
			if left_at > 0 and landed_at < 0 and i > left_at and player._on_ground() and up < 0.05:
				landed_at = i + 2
		var rose := peak - floor_y
		var hz := float(Engine.physics_ticks_per_second)
		report.append("%s left the ground %.2f s after the press, rose %.2f m and landed %.2f s after the press (%s)" % [
				where, float(left_at) / hz, rose, float(landed_at) / hz, ", ".join(clips)])
		assert_near(rose, Player.JUMP_HEIGHT, 0.15, "%s a jump rose %.2f m" % [where, rose])
		assert_true(left_at > 0 and absf(float(left_at) / hz - Player.JUMP_WINDUP_S) < 0.05,
				"%s the feet left the ground %.2f s after the press, not at the push (%.2f s)" % [where, float(left_at) / hz, Player.JUMP_WINDUP_S])
		assert_true(landed_at > 0, "%s the body did not come down" % where)
		assert_eq(clips, ["Jump_Start", "Jump_Loop", "Jump_Land"], "%s the jump played %s" % [where, ", ".join(clips)])
		_clear()
		await _tree().process_frame
	print("    a jump: %s" % "; ".join(report))
