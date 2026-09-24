extends TestCase
## The player walks into the scatter from real keys: playtest 5 (on batch 3) walked through trees,
## fences and rocks. On a flat Terrain3D with its own collision, a near-ring cell of scatter is
## stood by ScatterSolids as the streamer stands one (Wayside.prepare, then add_cell): an oak, a
## run of roadside rails, a drystone wall, a hedge and a boulder, each in a lane of its own, and a
## lane of long grass. The body is put in front of each facing it and W is held (walk, jog and
## sprint): it never gets through or into any of the five, and it goes through the grass at its
## full pace. The camera's arm, looking over the body's shoulder past a trunk, is not pulled in.

const PLAYER := preload("res://actors/player/player.tscn")
const KEYS: Array[Key] = [KEY_W, KEY_SHIFT, KEY_ALT, KEY_SPACE]
const TREE := "res://assets/models/trees/hearthvale_oak_a/hearthvale_oak_a.glb"
const BOULDER := "res://assets/models/rocks/hearthvale_boulder_a/hearthvale_boulder_a.glb"
const WALL := "res://assets/models/props/skerrow_drystone_wall_a/skerrow_drystone_wall_a.glb"
const HEDGE := "res://assets/models/props/hearthvale_hedge_segment_a/hearthvale_hedge_segment_a.glb"
const RAIL := "res://assets/models/props/hearthvale_fence_post_rail_a/hearthvale_fence_post_rail_a.glb"
const GRASS := "res://assets/models/flora/hearthvale_grass_clump_a/hearthvale_grass_clump_a.glb"
const SPACING := 2.0
const VERTS := 256
## Every obstacle stands on this line; the body starts RUN_UP metres on the +z side of it and W
## (yaw 0) walks it toward -z.
const LINE_Z := 200.0
## How far in front of the line each gait starts (m): each is up to its pace well before it.
const RUN_UP := {"walk": 2.5, "jog": 6.0, "sprint": 8.0}
const HOLD_S := 2.2
const LANES := {"tree": 60.0, "fence": 140.0, "wall": 220.0, "hedge": 300.0, "boulder": 380.0, "grass": 460.0}
const GAIT_KEYS := {"walk": [KEY_ALT, KEY_W], "jog": [KEY_W], "sprint": [KEY_SHIFT, KEY_W]}
const CAPSULE_R := 0.35

var player: Player = null
var _terrain: Node3D = null
var _provider: TerrainProvider = null
var _world: World = null
var _was_world: World = null
var _cell: Node3D = null
var _solids: ScatterSolids = null


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
	for k in KEYS:
		_key(k, false)
	if player != null and is_instance_valid(player):
		player.queue_free()
	player = null
	for n: Node in [_cell, _solids]:
		if n != null and is_instance_valid(n):
			n.free()
	_cell = null
	_solids = null
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
	await _tree().physics_frame
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


static func _all_there() -> bool:
	for p in [TREE, BOULDER, WALL, HEDGE, RAIL, GRASS]:
		if not ResourceLoader.exists(p):
			return false
	return true


## The rows of each lane's scatter, as a cell's instance table has them.
static func _instances() -> Dictionary:
	var tint := "#ffffff"
	var rails: Array = []
	for i in 9:
		rails.append([LANES["fence"] - 9.4 + 2.35 * float(i), 0.0, LINE_Z, 0.0, 1.0, tint])
	var walls: Array = []
	var hedges: Array = []
	for i in 7:
		walls.append([LANES["wall"] - 7.5 + 2.5 * float(i), 0.0, LINE_Z, 0.0, 1.0, tint])
		hedges.append([LANES["hedge"] - 7.5 + 2.5 * float(i), 0.0, LINE_Z, 0.0, 1.0, tint])
	var grass: Array = []
	for i in 60:
		grass.append([LANES["grass"] - 2.0 + float(i % 5), 0.0, LINE_Z + 4.0 - float(i / 5), float(i * 37 % 360), 1.3, tint])
	return {
		TREE: [[LANES["tree"], 0.0, LINE_Z, 30.0, 1.0, tint]],
		RAIL: rails,
		WALL: walls,
		HEDGE: hedges,
		BOULDER: [[LANES["boulder"], 0.0, LINE_Z, 0.0, 1.0, tint]],
		GRASS: grass,
	}


## A flat Terrain3D with its collision built, the body on it with its camera, and one near-ring
## cell of scatter stood as the streamer stands one.
func _stand_up() -> bool:
	if not ClassDB.class_exists("Terrain3D") or not _all_there():
		print("    (no Terrain3D or no forge assets here; skipped)")
		return false
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	_terrain = ClassDB.instantiate("Terrain3D") as Node3D
	_terrain.name = "FlatGround"
	_tree().root.add_child(_terrain)
	_terrain.call("set_camera", player.camera_rig.camera)
	await _tree().process_frame
	_terrain.call("change_region_size", VERTS)
	_terrain.set("vertex_spacing", SPACING)
	var img := Image.create_empty(VERTS, VERTS, false, Image.FORMAT_RF)
	img.fill(Color(0.0, 0.0, 0.0))
	var images: Array[Image] = [img, null, null]
	_terrain.get("data").call("import_images", images, Vector3.ZERO, 0.0, 1.0)
	var col: Object = _terrain.get("collision")
	col.set("mode", 3)
	if col.has_method("build"):
		col.call("build")
	_provider = TerrainProvider.new()
	_provider.bind_terrain(_terrain)
	_world = World.new()
	_world.provider = _provider
	_was_world = World.instance
	World.instance = _world
	# the cell, as WorldStreamer._build_cell stands it: the wayside builds the rails' runs, and what
	# is left is drawn and stood
	_solids = ScatterSolids.new()
	_tree().root.add_child(_solids)
	_cell = Node3D.new()
	_cell.name = "Cell_walk"
	_cell.position = Vector3(256.0, 0.0, 256.0)
	_tree().root.add_child(_cell)
	var built: Array = []
	var drawn := Wayside.prepare(_instances(), _cell, true, built)
	_solids.add_cell(_cell, drawn, built)
	# stood as the game stands them, a tick's budget at a time
	for i in 600:
		_solids.build(player.global_position)
		if _solids.pending() == 0:
			break
		await _tree().physics_frame
	await _ticks(3)
	return _solids.pending() == 0


## The body put its gait's RUN_UP in front of `lane`'s line facing it, `gait`'s keys held for HOLD_S: the
## nearest it came to the line (m, the body's middle; negative is past it), how far it went, and
## the nearest it came to `point` on the flat (m), when one is given.
func _walk_at(lane: String, gait: String, offset := 0.0, point := Vector3.INF) -> Dictionary:
	var x := float(LANES[lane]) + offset
	player.teleport(Vector3(x, 0.02, LINE_Z + float(RUN_UP[gait])), 0.0)
	await _ticks(8)
	var start := player.global_position
	for k in GAIT_KEYS[gait]:
		_key(k, true)
	var nearest_line := INF
	var nearest_point := INF
	for i in int(HOLD_S * Engine.physics_ticks_per_second):
		await _tree().physics_frame
		var p := player.global_position
		nearest_line = minf(nearest_line, p.z - LINE_Z)
		if point != Vector3.INF:
			nearest_point = minf(nearest_point, Vector2(p.x - point.x, p.z - point.z).length())
	for k in GAIT_KEYS[gait]:
		_key(k, false)
	var went := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	await _ticks(10)
	return {"line": nearest_line, "point": nearest_point, "went": went, "end": player.global_position}


## Where a body walking toward -z along x = `row`'s x first meets the drawn mesh (its full level of
## detail, as the row stands it): the z at which the body's middle stops if it stops on the visible
## surface. A capsule of CAPSULE_R touches a point `dx` to its side at sqrt(r² - dx²) in front of
## its middle, over the height of its straight side.
static func _visible_stop_z(path: String, row: Array) -> float:
	var meshes: Array = ScatterSolids._meshes_of(path)
	if meshes.is_empty():
		return NAN
	var t := ScatterSolids.row_transform(row, Vector3.ZERO)
	var faces := (meshes[-1] as Mesh).get_faces()
	var x := float(row[0])
	var best := -INF
	for dxi in range(-6, 7):
		var dx := CAPSULE_R * float(dxi) / 6.5
		var reach := sqrt(CAPSULE_R * CAPSULE_R - dx * dx)
		for hi in range(0, 12):
			var from := Vector3(x + dx, CAPSULE_R + 0.1 * float(hi), float(row[2]) + 50.0)
			for i in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3(0.0, 0.0, -1.0),
						t * faces[i], t * faces[i + 1], t * faces[i + 2])
				if hit != null:
					best = maxf(best, (hit as Vector3).z + reach)
	return best


func test_walking_into_a_trunk_a_fence_a_wall_a_hedge_and_a_boulder_from_the_keys() -> void:
	if not await _stand_up():
		return
	assert_true(_solids.body_count() >= 5, "a body for each block with something solid in it: one or two for each lane but the grass (%d)" % _solids.body_count())
	assert_eq(_solids.bodies_in_space(), _solids.body_count(), "all of them in the physics space")
	var r := float(ScatterSolids.meta(TREE)["collision_params"]["radius"])
	var trunk := Vector3(LANES["tree"], 0.0, LINE_Z)
	var report: Array[String] = []
	var rock_z := _visible_stop_z(BOULDER, (_instances()[BOULDER] as Array)[0])
	var oak_z := _visible_stop_z(TREE, (_instances()[TREE] as Array)[0])
	report.append("the drawn boulder stops a body's middle %.2f m from its own, the drawn oak %.2f m" % [rock_z - LINE_Z, oak_z - LINE_Z])
	for gait in ["walk", "jog", "sprint"]:
		# square on at the trunk, and a little off its middle, where a body slides round it
		for offset in [0.0, 0.3]:
			var got := await _walk_at("tree", gait, offset, trunk)
			report.append("%s at the oak%s: %.2f m from its middle" % [gait, "" if offset == 0.0 else " (off centre)", float(got["point"])])
			assert_true(float(got["point"]) > r + CAPSULE_R - 0.08,
					"%s into the oak (trunk %.2f m): the body's middle came %.2f m from the trunk's" % [gait, r, float(got["point"])])
			assert_true(float(got["point"]) < r + CAPSULE_R + 0.3, "%s: the body got to the oak (%.2f m off)" % [gait, float(got["point"])])
		for lane in ["fence", "wall", "hedge"]:
			var got := await _walk_at(lane, gait)
			report.append("%s at the %s: stopped %.2f m short of its line" % [gait, lane, float(got["line"])])
			assert_true(float(got["line"]) > CAPSULE_R, "%s into the %s: the body came to %.2f m of its line (past it if negative)" % [gait, lane, float(got["line"])])
			assert_true(float(got["line"]) < 1.2, "%s: the body got to the %s (%.2f m off)" % [gait, lane, float(got["line"])])
			assert_true(float(got["went"]) < float(RUN_UP[gait]), "%s into the %s: it went %.1f m of a %.1f m run-up" % [gait, lane, float(got["went"]), float(RUN_UP[gait])])
		# the boulder is stopped at by its hull; the body stands where it would touch the rock drawn
		var rock := await _walk_at("boulder", gait)
		var gap := float((rock["end"] as Vector3).z) - rock_z
		report.append("%s at the boulder: %.2f m from its middle, %+.2f m off its drawn face" % [
				gait, (rock["end"] as Vector3).z - LINE_Z, gap])
		assert_true(absf(gap) < 0.1, "%s into the boulder: the body stopped %+.2f m off the rock drawn (a gap if positive, in the stone if negative)" % [gait, gap])
	print("    " + "; ".join(report))


func test_the_grass_is_walked_through_at_full_pace() -> void:
	if not await _stand_up():
		return
	for gait in ["jog", "sprint"]:
		var got := await _walk_at("grass", gait)
		var speed := Player.JOG_SPEED if gait == "jog" else Player.SPRINT_SPEED
		# HOLD_S less the time to get up to pace
		assert_true(float(got["line"]) < -4.0, "%s through the grass: it got %.2f m past the line" % [gait, -float(got["line"])])
		assert_true(float(got["went"]) > speed * (HOLD_S - 0.6),
				"%s through the grass went %.1f m in %.1f s (%.1f m/s is its pace)" % [gait, float(got["went"]), HOLD_S, speed])


## A jump at a roadside fence climbs it, as it climbs a house's low wall; a jump at the oak does not.
func test_a_jump_at_the_fence_climbs_it_and_the_oak_is_not_climbed() -> void:
	if not await _stand_up():
		return
	player.teleport(Vector3(LANES["fence"], 0.02, LINE_Z + 0.7), 0.0)
	await _ticks(8)
	_key(KEY_W, true)
	await _ticks(4)
	_key(KEY_SPACE, true)
	await _ticks(2)
	_key(KEY_SPACE, false)
	await _ticks(90)
	_key(KEY_W, false)
	await _ticks(10)
	assert_true(player.global_position.z < LINE_Z - CAPSULE_R,
			"a jump at the fence took the body over it (z %.2f, the line at %.2f)" % [player.global_position.z, LINE_Z])
	player.teleport(Vector3(LANES["tree"], 0.02, LINE_Z + 1.2), 0.0)
	await _ticks(8)
	_key(KEY_W, true)
	await _ticks(4)
	_key(KEY_SPACE, true)
	await _ticks(2)
	_key(KEY_SPACE, false)
	await _ticks(60)
	_key(KEY_W, false)
	await _ticks(20)
	var p := player.global_position
	assert_true(Vector2(p.x - LANES["tree"], p.z - LINE_Z).length() > 0.5 and p.y < 1.0,
			"a jump at the oak stays at its foot (%.2f, %.2f, %.2f)" % [p.x, p.y, p.z])


## The camera's arm does not see the scatter: the body with its back to the oak, a pace in front of
## it, and the camera behind looking past the trunk keeps its full length.
func test_the_camera_is_not_pulled_in_by_a_trunk() -> void:
	if not await _stand_up():
		return
	player.teleport(Vector3(LANES["tree"], 0.02, LINE_Z - 1.2), 0.0)
	await _ticks(60)
	var cam := player.camera_rig.camera
	var behind := cam.global_position.z - player.global_position.z
	assert_true(cam.global_position.z > LINE_Z, "the camera stands behind the trunk (z %.2f, the trunk at %.2f)" % [cam.global_position.z, LINE_Z])
	assert_true(behind > 2.0, "and keeps its arm's length past it (%.2f m behind the body)" % behind)
