extends TestCase
## The starter horse (DECISIONS 2026-09-24): the forge's horse, mounted, ridden and got down from
## with real key events on a real Terrain3D; the gaits it gives on slopes and in water; the whistle;
## `give_mount`; and a game saved in the saddle.
##
## The ground is lanes of planar ramp side by side (as test_walking_uphill's), each rising toward -z
## from FOOT_Z, and a pond lane that goes down under the sea level instead.

const PLAYER := preload("res://actors/player/player.tscn")
const KEYS: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_ALT, KEY_C, KEY_E, KEY_H, KEY_SPACE]
const ANGLES: Array[float] = [0.0, 12.0, 20.0, 26.0, 32.0, 42.0]
## The pond: this lane goes down at POND_DEG into water under sea level 0.
const POND_LANE := 6
const POND_DEG := 8.0
const SPACING := 2.0
const VERTS := 256
const LANE := 24.0
const LANE_HALF := 10.0
const FIRST_LANE_X := 30.0
const FOOT_Z := 440.0
const HORSE := "core:mount/wardens_cob"
## Where the hips were, in the horse's frame from the seat, a few ticks into Mount_Horse.
var _mount_hips: Array = []

var player: Player = null
var horse: Mount = null
var _terrain: Node3D = null
var _provider: TerrainProvider = null
var _world: World = null
var _was_world: World = null
var _stable: Stable = null


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
	_clear()
	Settings.load_settings()
	Settings.apply_bindings()
	GameState.reset_for_new_game(7)


func _clear() -> void:
	for k in KEYS:
		_key(k, false)
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


func _tap(code: int) -> void:
	_key(code, true)
	await _ticks(4)
	_key(code, false)
	await _ticks(2)


func _ticks(n: int) -> void:
	for i in n:
		await _tree().physics_frame


static func _lane_x(lane: int) -> float:
	return FIRST_LANE_X + LANE * float(lane)


static func ground_at(x: float, z: float) -> float:
	var lane := int(floor((x - FIRST_LANE_X + LANE * 0.5) / LANE))
	if lane < 0 or lane > POND_LANE or absf(x - _lane_x(lane)) > LANE_HALF:
		return 0.0
	var up := maxf(0.0, FOOT_Z - z)
	if lane == POND_LANE:
		return -minf(tan(deg_to_rad(POND_DEG)) * up, 3.0)
	return tan(deg_to_rad(ANGLES[lane])) * up


## The lanes as a Terrain3D with its collision, the world's ground questions answered from it, the
## player standing in it and the horse (the Stable's own, given as `give_mount` gives it).
func _ground() -> bool:
	if not ClassDB.class_exists("Terrain3D"):
		print("    SKIPPED: no Terrain3D in this build")
		return false
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	_terrain = ClassDB.instantiate("Terrain3D") as Node3D
	_terrain.name = "RideLanes"
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
		fail("the Stable stood no horse (ready %s)" % str(_stable.get("_ready_to_stand")))
	return horse != null


## The horse at `at` facing -Z, the player a pace off its near side, looking at it.
func _stand(at: Vector3) -> void:
	horse.place(Vector3(at.x, ground_at(at.x, at.z), at.z), 0.0)
	var side := at + Vector3(-1.7, 0.0, -0.2)
	player.teleport(Vector3(side.x, ground_at(side.x, side.z) + 0.02, side.z), -PI * 0.5)   # facing +X
	player.camera_rig.pitch = -0.25
	await _ticks(20)


func _mount() -> bool:
	for i in 30:
		if player.interactor.has_target():
			break
		await _ticks(1)
	if player.interactor.target != horse:
		fail("the interactor never found the horse (found %s)" % str(player.interactor.target))
		return false
	await _tap(KEY_E)
	_mount_hips.clear()
	for i in 150:
		if player.rider.state == "mounting" and player.anim.current_clip == "Mount_Horse" and _mount_hips.is_empty():
			await _ticks(3)
			var h := player.global_transform * player.rider._hips_local()
			_mount_hips.append(Basis(Vector3.UP, horse.heading).inverse() * (h - horse.seat_transform().origin))
		if player.rider.is_seated():
			# the view behind the horse, so that W is the way it faces
			player.camera_rig.yaw = horse.heading
			await _ticks(2)
			return true
		await _ticks(1)
	fail("the player was not in the saddle 2.5 s after pressing E (rider state '%s')" % player.rider.state)
	return false


## Holds `keys` for `seconds`, and returns the horse's ground speed at the end and its top speed.
func _ride(keys: Array, seconds: float) -> Dictionary:
	for k in keys:
		_key(k, true)
	var top := 0.0
	var start := horse.global_position
	var n := int(seconds * Engine.physics_ticks_per_second)
	for i in n:
		await _tree().physics_frame
		top = maxf(top, horse.speed)
	var out := {"speed": horse.speed, "top": top, "gait": horse.gait, "moved": horse.global_position.distance_to(start),
			"held_back": horse.held_back}
	for k in keys:
		_key(k, false)
	return out


func test_the_horse_is_the_forges() -> void:
	var m := HorseModel.new()
	_tree().root.add_child(m)
	assert_true(m.skeleton != null, "the horse GLB has no skeleton")
	if m.skeleton != null:
		for b in ["Hips", "Spine2", "Neck1", "Head", "Scapula.L", "FrontCannon.R", "Gaskin.L", "HindHoof.R", "Tail3", "Socket.Saddle", "Socket.Bit"]:
			assert_true(m.skeleton.find_bone(b) >= 0, "no bone %s (CONTRACTS §2b)" % b)
	for c in ["Idle", "Graze", "Walk", "Trot", "Canter", "Gallop", "Walk_Back", "Turn_L90", "Turn_R90", "Stop", "Rear", "Mount", "Dismount"]:
		assert_true(m.has_clip(c), "no clip %s (CONTRACTS §3b)" % c)
	for g in Mount.SPEEDS:
		assert_near(m.gait_speed(g), float(Mount.SPEEDS[g]), 0.01, "%s's sidecar speed is not the game's" % g)
	var names: Array[String] = []
	for mi in m.meshes():
		names.append(String((mi as MeshInstance3D).name))
	for want in ["Horse_Body", "Horse_Tack", "Horse_LOD1", "Horse_LOD2"]:
		var found := false
		for n in names:
			found = found or n.begins_with(want)
		assert_true(found, "no %s mesh among %s" % [want, str(names)])
	var seat := m.socket("Socket.Saddle")
	assert_true(seat != null, "no saddle socket")
	m.queue_free()


func test_mounting_riding_and_getting_down_from_the_keys() -> void:
	if not await _ground():
		return
	await _stand(Vector3(_lane_x(0), 0.0, FOOT_Z + 60.0))
	if not await _mount():
		return
	var seat := horse.seat_transform().origin
	assert_near(seat.y - horse.global_position.y, 1.6, 0.12, "the saddle is %.2f m up" % (seat.y - horse.global_position.y))
	assert_eq(player.collision_layer, 0, "a body in the saddle collides")
	await _ticks(3)
	assert_eq(player.interactor.prompt, "", "in the saddle the prompt says '%s'" % player.interactor.prompt)
	# W canters, Shift gallops, letting go comes down a gait at a time
	var canter := await _ride([KEY_W], 3.0)
	assert_near(float(canter["speed"]), Mount.SPEEDS["Canter"], 0.3, "W: %s" % str(canter))
	assert_eq(str(canter["gait"]), "Canter", "W: %s" % str(canter))
	var gallop := await _ride([KEY_W, KEY_SHIFT], 2.5)
	assert_near(float(gallop["speed"]), Mount.SPEEDS["Gallop"], 0.4, "Shift+W: %s" % str(gallop))
	assert_true(horse.stamina < horse.max_stamina, "a gallop spent no stamina")
	var walk := await _ride([KEY_W, KEY_ALT], 4.0)
	assert_near(float(walk["speed"]), Mount.SPEEDS["Walk"], 0.2, "Alt+W: %s" % str(walk))
	# the body rides with the saddle, wherever the horse has gone
	var hips := player.rider._hips_local()
	var sat := player.global_transform * hips
	assert_near(sat.y - horse.seat_transform().origin.y, Rider.HIPS_ABOVE_SEAT, 0.08, "the hips are not on the seat")
	var coast := await _ride([], 4.0)
	assert_true(float(coast["speed"]) < 0.3, "let go, the horse was still going at %.2f m/s after 4 s" % float(coast["speed"]))
	await _tap(KEY_E)
	for i in 120:
		if not player.rider.riding():
			break
		await _ticks(1)
	assert_false(player.rider.riding(), "E did not get the player down")
	var off := Vector2(player.global_position.x - horse.global_position.x, player.global_position.z - horse.global_position.z).length()
	assert_true(off > 0.7 and off < 2.5, "got down %.2f m from the horse's middle" % off)
	assert_near(player.global_position.y, ground_at(player.global_position.x, player.global_position.z), 0.15, "got down in the air")
	assert_eq(player.collision_layer, Actor.LAYER_PLAYER, "the body did not get its collision back")
	await _ticks(10)
	assert_eq(player.state, Player.State.FREE, "the body is not free on its feet")


func test_the_gaits_the_ground_allows() -> void:
	if not await _ground():
		return
	# asked to gallop up each lane: what it gives, and a wall it refuses
	var want := {0.0: "Gallop", 12.0: "Gallop", 20.0: "Canter", 26.0: "Trot", 32.0: "Walk"}
	var report: Array[String] = []
	for lane in ANGLES.size():
		var a: float = ANGLES[lane]
		await _stand(Vector3(_lane_x(lane), 0.0, FOOT_Z + 8.0))
		if not await _mount():
			return
		var start_y := horse.global_position.y
		var got := await _ride([KEY_W, KEY_SHIFT], 5.0)
		var rise := horse.global_position.y - start_y
		if a > Mount.WALL_DEG:
			report.append("%.0f° refused (rose %.2f m)" % [a, rise])
			assert_true(rise < 1.0, "a %.0f° slope: the horse climbed %.2f m of a wall" % [a, rise])
		else:
			report.append("%.0f° %s %.1f m/s" % [a, str(got["gait"]), float(got["speed"])])
			assert_eq(str(got["gait"]), str(want[a]), "a %.0f° slope asked for a gallop: %s" % [a, str(got)])
			if a > 0.0:
				assert_true(rise > 1.0, "a %.0f° slope: the horse rose only %.2f m" % [a, rise])
		await _ride([KEY_S], 2.0)
		await _tap(KEY_E)
		await _ticks(90)
	print("    asked to gallop uphill: %s" % ", ".join(report))


func test_the_horse_wades_but_will_not_swim() -> void:
	if not await _ground():
		return
	await _stand(Vector3(_lane_x(POND_LANE), 0.0, FOOT_Z + 10.0))
	if not await _mount():
		return
	var deepest := 0.0
	var gaits: Array[String] = []
	_key(KEY_W, true)
	for i in int(8.0 * Engine.physics_ticks_per_second):
		await _tree().physics_frame
		deepest = maxf(deepest, horse.water_depth(horse.global_position))
		if horse.gait != "" and (gaits.is_empty() or gaits[-1] != horse.gait):
			gaits.append(horse.gait)
	_key(KEY_W, false)
	print("    into the pond at a canter: %s, deepest %.2f m" % [" > ".join(gaits), deepest])
	assert_true(deepest > Mount.WALK_DEPTH, "the horse never went into the water (deepest %.2f m)" % deepest)
	assert_true(deepest < Mount.REFUSE_DEPTH + 0.15, "the horse went %.2f m deep: it swims" % deepest)
	assert_true(gaits.has("Walk"), "it never came down to a walk in the water: %s" % str(gaits))


func test_a_whistle_brings_the_horse_over_the_ground() -> void:
	if not await _ground():
		return
	horse.place(Vector3(_lane_x(0), 0.0, FOOT_Z + 100.0), 0.0)
	player.teleport(Vector3(_lane_x(0) + 4.0, 0.02, FOOT_Z + 60.0), PI)
	await _ticks(10)
	await _tap(KEY_H)
	var worst_step := 0.0
	var last := horse.global_position
	var arrived := -1.0
	for i in int(14.0 * Engine.physics_ticks_per_second):
		await _tree().physics_frame
		worst_step = maxf(worst_step, horse.global_position.distance_to(last))
		last = horse.global_position
		if horse.global_position.distance_to(player.global_position) < Mount.ARRIVE_M + 0.6 and absf(horse.speed) < 0.3:
			arrived = float(i) / float(Engine.physics_ticks_per_second)
			break
	assert_true(arrived > 0.0, "whistled from 40 m, the horse was still %.1f m off after 14 s" % horse.global_position.distance_to(player.global_position))
	assert_true(worst_step < 0.4, "the horse jumped %.2f m in one tick: it did not come over the ground" % worst_step)
	print("    whistled from 40 m: here in %.1f s" % arrived)


func test_give_mount_stands_the_horse_once_at_its_door() -> void:
	# a door for the Toll's Lip, as WorldDoors would place it, with open ground in front
	var doors := Node3D.new()
	doors.set_script(load("res://world/bootstrap/doors.gd"))
	doors.set("place_doors", false)
	_tree().root.add_child(doors)
	var door := Door.new()
	door.interior_id = "core:interior/tolls_lip"
	doors.add_child(door)
	door.global_position = Vector3(500.0, 0.0, 500.0)
	(doors.get("placed") as Array).append(door)
	_stable = Stable.new()
	_tree().root.add_child(_stable)
	for i in 120:
		if bool(_stable.get("_ready_to_stand")):
			break
		await _tree().process_frame
	var ctx := SocialContext.new()
	ctx.set_provider("flags", GameState)
	ctx.set_provider("stable", _stable)
	Effects.apply_all([{"give_mount": HORSE}], ctx, "quest")
	Effects.apply_all([{"give_mount": HORSE}], ctx, "quest")
	assert_empty(ctx.problems, "give_mount")
	assert_eq(_stable.horses.size(), 1, "two gifts of one horse")
	assert_true(bool(GameState.get_flag(SocialContext.MOUNT_FLAG_PREFIX + HORSE, false)), "the horse is not owned")
	var m: Mount = _stable.horses.get(HORSE)
	if m != null:
		var d := Vector2(m.global_position.x - 500.0, m.global_position.z - 500.0).length()
		assert_true(d > 3.0 and d < 13.0, "the cob stands %.1f m from the Toll's Lip's door" % d)
		assert_eq(m.display_name, "Hollin")
	# and the quest that gives it
	var toll: Dictionary = ContentDB.get_or_empty("core:quest/the_toll_hums")
	var gives := false
	for st in toll.get("stages", []):
		if str(st.get("id", "")) == "arrive":
			for e in st.get("on_complete", []):
				gives = gives or (typeof(e) == TYPE_DICTIONARY and str(e.get("give_mount", "")) == HORSE)
				# to a character with no horse of their own yet (a style's start gives one)
				for then_e in (e as Dictionary).get("then", []):
					gives = gives or str((then_e as Dictionary).get("give_mount", "")) == HORSE
	assert_true(gives, "the_toll_hums' arrive stage does not give the cob")
	doors.queue_free()


func test_any_giver_can_stand_the_horse_at_its_own_door() -> void:
	# a start town's stable, say: give_mount with a home of the giver's own, over the def's
	GameState.flags.erase(SocialContext.MOUNT_FLAG_PREFIX + HORSE)
	var doors := Node3D.new()
	doors.set_script(load("res://world/bootstrap/doors.gd"))
	doors.set("place_doors", false)
	_tree().root.add_child(doors)
	var door := Door.new()
	door.interior_id = "core:interior/a_start_town_stable"
	doors.add_child(door)
	door.global_position = Vector3(-700.0, 0.0, 300.0)
	(doors.get("placed") as Array).append(door)
	_stable = Stable.new()
	_tree().root.add_child(_stable)
	for i in 120:
		if bool(_stable.get("_ready_to_stand")):
			break
		await _tree().process_frame
	var ctx := SocialContext.new()
	ctx.set_provider("flags", GameState)
	ctx.set_provider("stable", _stable)
	Effects.apply_all([{"give_mount": {"mount": HORSE, "door": "core:interior/a_start_town_stable", "notes": "in the stable yard"}}], ctx, "quest")
	assert_empty(ctx.problems, "give_mount with a home")
	var m: Mount = _stable.horses.get(HORSE)
	assert_true(m != null, "no horse stood")
	if m != null:
		var d := Vector2(m.global_position.x + 700.0, m.global_position.z - 300.0).length()
		assert_true(d > 3.0 and d < 13.0, "the cob stands %.1f m from the giver's door" % d)
	# the giver's home is kept with the save
	var saved := _stable.to_save()
	assert_eq(str(((saved.get("homes", {}) as Dictionary).get(HORSE, {}) as Dictionary).get("door", "")),
		"core:interior/a_start_town_stable", "the giver's home is not saved")
	doors.queue_free()


func test_a_game_saved_in_the_saddle_loads_in_the_saddle() -> void:
	if not await _ground():
		return
	await _stand(Vector3(_lane_x(0), 0.0, FOOT_Z + 60.0))
	if not await _mount():
		return
	await _ride([KEY_W], 1.5)
	var saved := _stable.to_save()
	assert_eq(str(saved.get("riding", "")), HORSE, "the save does not say who is ridden")
	var at := horse.global_position
	# the next game: down, moved away, and the save read back
	player.teleport(at + Vector3(30.0, 0.0, 30.0), 0.0)
	horse.place(at + Vector3(50.0, 0.0, 0.0), 1.0)
	await _ticks(5)
	assert_false(player.rider.riding(), "a teleport left the body in the saddle")
	_stable.from_save(saved)
	await _ticks(5)
	assert_true(player.rider.is_seated(), "loaded, the body is not in the saddle")
	assert_true(horse.global_position.distance_to(at) < 0.5, "loaded, the horse is %.1f m from where it was saved" % horse.global_position.distance_to(at))


## Player feel's clips on the saddle (anim_clips.riding_clips): getting up plays Mount_Horse, the seat
## is Ride and stands in the stirrups (Ride_Gallop) at the gallop, and getting down plays
## Dismount_Horse, landing on the near side. Through all of it the body is held on the saddle's frame,
## the clips' root, and the hips sit HIPS_ABOVE_SEAT over the seat while riding.
func test_the_rig_mounts_rides_and_gets_down_on_its_own_clips() -> void:
	if not await _ground():
		return
	var model: Node = player.anim.model
	if model == null or not bool(model.call("has_clip", "Mount_Horse")):
		print("    (no rider clips on this rig; skipped)")
		return
	await _stand(Vector3(_lane_x(1), 0.0, FOOT_Z + 60.0))
	var seen := {}
	var on_clip := func(c: String) -> void: seen[c] = true
	player.anim.clip_started.connect(on_clip)
	if not await _mount():
		player.anim.clip_started.disconnect(on_clip)
		return
	assert_true(seen.has("Mount_Horse"), "getting up played %s" % str(seen.keys()))
	if not _mount_hips.is_empty():
		var h: Vector3 = _mount_hips[0]
		print("    starting to get up, the hips stand at %s from the seat, in the horse's frame" % str(h.snapped(Vector3.ONE * 0.01)))
		assert_true(h.x < -0.35 and h.x > -0.8, "the body gets up from the near (left) side (%.2f m across)" % h.x)
		assert_true(absf(h.z) < 0.25, "and beside the saddle, not ahead of it or behind (%.2f m along)" % h.z)
	assert_eq(player.anim.current_clip, "Ride", "sat, the body plays %s" % player.anim.current_clip)
	var frame := player.rider._saddle_frame()
	assert_true(player.global_position.distance_to(frame.origin) < 0.02, "the body's root is on the saddle")
	var gallop := await _ride([KEY_W, KEY_SHIFT], 4.0)
	assert_eq(str(gallop["gait"]), "Gallop", "Shift+W: %s" % str(gallop))
	assert_eq(player.anim.current_clip, "Ride_Gallop", "at the gallop the body plays %s" % player.anim.current_clip)
	var hips := player.global_transform * player.rider._hips_local()
	var up := hips.y - horse.seat_transform().origin.y
	assert_true(up > Rider.HIPS_ABOVE_SEAT + 0.04, "at the gallop the hips are out of the saddle (%.2f m over the seat)" % up)
	await _ride([], 4.0)
	await _tap(KEY_E)
	for i in 150:
		if not player.rider.riding():
			break
		await _ticks(1)
	player.anim.clip_started.disconnect(on_clip)
	assert_true(seen.has("Dismount_Horse"), "getting down played %s" % str(seen.keys()))
	assert_false(player.rider.riding(), "E did not get the player down")
	var local := Basis(Vector3.UP, horse.heading).inverse() * (player.global_position - horse.global_position)
	print("    down at %s in the horse's frame" % str(local.snapped(Vector3.ONE * 0.01)))
	assert_true(local.x < -0.7, "got down on the near (left) side, clear of the flank (%.2f m across)" % local.x)
	assert_near(player.global_position.y, ground_at(player.global_position.x, player.global_position.z), 0.15, "got down in the air")
