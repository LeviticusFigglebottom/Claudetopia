extends TestCase
## First person (triage 57): the player's own body seen from its own eyes.
##   * the camera stands at the body's eyes; the body stays drawn and its head is in the shadows
##     only (it had a white box for an arm and a grey bar for a sword, on the camera, and the body
##     hidden), and none of that is left;
##   * a drawn weapon is carried up in the guard: the hands and the blade are in the picture,
##     standing and walking, and a swing's blade crosses it;
##   * every action plays its own clip seen from the eyes: the light and heavy swing, the guard, the
##     roll, the jump, the bow drawn, a saying;
##   * looking down, the feet are in the picture;
##   * the head bob setting takes the step out of the view, the view's own field of view is the
##     setting's, and a wall keeps the eye out of it;
##   * the toggle goes there and back, the head's shadows as they were.

const SWORD := "core:item/iron_sword"
const BOW := "core:item/hunting_bow"
const IRON_ARROW := "core:item/iron_arrow"
const KINDLE := "core:spell/kindle_bolt"
const FRAME := 1.0 / 60.0

var root: Node3D
var player: Player


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	root = Node3D.new()
	root.name = "FirstPerson"
	_tree().root.add_child(root)
	_box(Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))
	player = (load("res://actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.02, 0.0)
	player.camera_rig.yaw = 0.0
	player.camera_rig.pitch = 0.0


func after_each() -> void:
	for a in Player.ACTIONS:
		Input.action_release(a)
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)
	Settings.set_value("accessibility", "head_bob", 1.0)
	Settings.set_value("video", "fov_first_person", CameraRig.FP_FOV)
	if is_instance_valid(root):
		root.free()
	root = null
	player = null


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.global_position = at
	return body


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _until(predicate: Callable, timeout: float) -> bool:
	for i in int(timeout / FRAME):
		if bool(predicate.call()):
			return true
		await _tree().physics_frame
	return bool(predicate.call())


func _model() -> HumanoidModel:
	return player.anim.model as HumanoidModel


func _rig_built() -> bool:
	return ResourceLoader.exists(HumanoidModel.RIG_PATH) and player.anim.model != null


## Into first person with a weapon drawn, settled.
func _first_person(item := SWORD) -> void:
	player.equip_weapon(item)
	player.weapon_drawn = true
	player._last_fight_act = player.now()
	player._dress_hands()
	player.camera_rig.set_first_person(true)
	await _frames(40)


func _cam() -> Camera3D:
	return player.camera_rig.camera


## A point is in the picture: ahead of the camera and inside its frustum.
func _seen(p: Vector3) -> bool:
	var cam := _cam()
	return not cam.is_position_behind(p) and cam.is_position_in_frustum(p)


func _bone(bone_name: String) -> Vector3:
	var sk := _model().skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone_name)).origin


## The held weapon's tip: the far end of its mesh along the socket's +Y.
func _blade_tip() -> Vector3:
	var socket := _model().socket("WeaponR") as Node3D
	var reach := 0.0
	for mi in socket.find_children("*", "MeshInstance3D", true, false):
		var box := (mi as MeshInstance3D).get_aabb()
		reach = maxf(reach, box.end.y)
	return socket.global_transform * Vector3(0.0, reach * 0.8, 0.0)


func test_the_camera_is_at_the_eyes_the_body_drawn_and_its_head_hidden() -> void:
	if not _rig_built():
		return
	await _first_person()
	var m := _model()
	assert_true(player.model.visible and m.visible, "the body is drawn in first person")
	assert_true(m.first_person, "and knows it is seen from its own eyes")
	var eye := player.first_person_eye()
	assert_lt(_cam().global_position.distance_to(eye), 0.08,
			"the camera is at the eyes (%.3f m off)" % _cam().global_position.distance_to(eye))
	assert_near(eye.y - player.global_position.y, 1.62, 0.15, "the eyes are at a standing man's height")
	var hidden := m.first_person_hidden()
	assert_gt(hidden.size(), 0, "the head has meshes to hide")
	for mi in hidden:
		assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
				"%s is in the shadows only" % mi.name)
	var body := m.worn_mesh("body")
	if body != null:
		assert_ne(body.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "the body is drawn")
		assert_ne(body.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "and casts its shadow")


func test_no_placeholder_arm_or_blade_is_left() -> void:
	await _frames(3)
	player.camera_rig.set_first_person(true)
	await _frames(10)
	assert_true(player.camera_rig.camera.get_node_or_null("FPArms") == null, "no FPArms on the camera")
	assert_eq(player.camera_rig.camera.find_children("*", "MeshInstance3D", true, false).size(), 0,
			"nothing drawn hangs off the camera")
	assert_false("fp_arms" in player.camera_rig, "the rig has no placeholder arms")


func test_a_drawn_weapon_is_carried_in_view_standing_and_walking() -> void:
	if not _rig_built():
		return
	await _first_person()
	await _frames(20)
	var m := _model()
	assert_gt(m.carry_weight(), 0.95, "the drawn sword is carried up in first person")
	assert_true(_seen(_bone("Hand.R")), "the sword hand is in the picture")
	assert_true(_seen(_blade_tip()), "and so is the blade")
	var socket := m.socket("WeaponR") as Node3D
	assert_gt(socket.find_children("*", "MeshInstance3D", true, false).size(), 0, "the real sword is in the hand")
	Input.action_press("move_forward")
	var seen := 0
	for i in 60:
		await _tree().physics_frame
		if _seen(_bone("Hand.R")) and _seen(_blade_tip()):
			seen += 1
	Input.action_release("move_forward")
	assert_gt(seen, 54, "walking, the hand and the blade stay in the picture (%d of 60 ticks)" % seen)
	# third person lets the arms go back to the clips'
	player.camera_rig.set_first_person(false)
	await _frames(20)
	assert_lt(m.carry_weight(), 0.01, "no carry in third person")


func test_each_action_plays_its_clip_in_first_person() -> void:
	if not _rig_built():
		return
	await _first_person()
	var m := _model()
	# a light swing: its clip, and the blade crosses the picture
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	assert_eq(player.state, Player.State.ATTACK, "a light attack")
	assert_true(m.current_intent().begins_with("Attack_"), "plays a swing (%s)" % m.current_intent())
	var crossed := 0
	while player.state == Player.State.ATTACK:
		if _seen(_blade_tip()):
			crossed += 1
		await _tree().physics_frame
	assert_gt(crossed, 10, "the swing's blade is in the picture (%d ticks)" % crossed)
	await _frames(20)
	# the chain's second
	player.stamina_comp.refill()
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	await _until(func() -> bool: return player._chain_open, 1.5)
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	await _frames(6)
	assert_eq(player._attack_index, 1, "the chain goes on to its second swing")
	await _until(func() -> bool: return player.state == Player.State.FREE, 2.0)
	await _frames(20)
	# a heavy
	player.stamina_comp.refill()
	Input.action_press("attack_heavy")
	await _frames(4)
	assert_true(m.current_intent().ends_with("Heavy"), "a heavy plays the heavy (%s)" % m.current_intent())
	Input.action_release("attack_heavy")
	await _until(func() -> bool: return player.state == Player.State.FREE, 2.5)
	await _frames(20)
	# the parry on the press, then the guard held, raised in view
	Input.action_press("block")
	await _frames(3)
	assert_eq(m.current_intent(), "Parry", "a press parries")
	await _until(func() -> bool: return m.current_stance() == "Block_Idle", 1.5)
	await _frames(10)
	assert_eq(m.current_stance(), "Block_Idle", "the guard is raised")
	assert_true(_seen(_bone("Hand.R")) or _seen(_bone("Hand.L")), "and a hand of it is in the picture")
	Input.action_release("block")
	await _frames(20)
	# a roll
	player.stamina_comp.refill()
	var eye_y := _cam().global_position.y
	Input.action_press("dodge")
	await _frames(2)
	Input.action_release("dodge")
	assert_eq(player.state, Player.State.DODGE, "a roll")
	assert_true(m.current_intent().begins_with("Dodge_"), "plays a roll (%s)" % m.current_intent())
	var lowest := eye_y
	while player.state == Player.State.DODGE:
		lowest = minf(lowest, _cam().global_position.y)
		await _tree().physics_frame
	assert_gt(lowest, eye_y - CameraRig.FP_STEADY_DROP - 0.1,
			"the view goes down with the roll only a little way (%.2f m)" % (eye_y - lowest))
	await _frames(30)
	# a jump
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	assert_true(player.anim.current_clip in ["Jump_Start", "Jump_Loop"], "a jump (%s)" % player.anim.current_clip)
	await _until(func() -> bool: return player._on_ground() and player.state == Player.State.FREE, 2.0)
	await _frames(30)


func test_a_bow_is_drawn_and_a_saying_said_in_first_person() -> void:
	if not _rig_built():
		return
	(player.get_node("Inventory") as Inventory).add(IRON_ARROW, 20)
	await _first_person(BOW)
	var m := _model()
	Input.action_press("attack_light")
	await _until(func() -> bool: return player.bow_draw() >= 1.0, 3.0)
	await _frames(6)
	assert_eq(player.state, Player.State.BOW, "the bow is drawn")
	assert_true(m.current_stance() in ["Bow_Draw", "Bow_Aim"], "with the draw's clip (%s)" % m.current_stance())
	var bow := m.socket("WeaponL") as Node3D
	assert_true(_seen(bow.global_position), "the bow hand is in the picture at full draw")
	Input.action_release("attack_light")
	await _frames(4)
	assert_eq(m.current_stance(), "Bow_Release", "the loose is played")
	await _until(func() -> bool: return player.state == Player.State.FREE and m.current_stance() == "", 2.0)
	# a saying
	var prog := player.progression() as Progression
	prog.learn_spell(KINDLE)
	player.equipped_spell = KINDLE
	player.stamina_comp.refill()
	player.full_restore()
	Input.action_press("cast")
	await _frames(3)
	Input.action_release("cast")
	await _frames(2)
	assert_eq(player.state, Player.State.CAST, "a saying is said")
	assert_true(m.current_intent().begins_with("Cast_"), "with its clip (%s)" % m.current_intent())


func test_looking_down_the_feet_are_seen() -> void:
	if not _rig_built():
		return
	await _first_person()
	player.camera_rig.pitch = -1.3
	await _frames(30)
	assert_true(_seen(_bone("Foot.L")) or _seen(_bone("Foot.R")), "looking down, a foot is in the picture")
	var shin := (_bone("LowerLeg.L") + _bone("Foot.L")) * 0.5
	var shin_r := (_bone("LowerLeg.R") + _bone("Foot.R")) * 0.5
	assert_true(_seen(shin) or _seen(shin_r), "and a shin")


func test_head_bob_off_keeps_the_step_out_of_the_view() -> void:
	if not _rig_built():
		return
	var spans := []
	for bob in [1.0, 0.0]:
		Settings.set_value("accessibility", "head_bob", bob)
		player.camera_rig.set_first_person(false)
		await _frames(2)
		player.global_position = Vector3(0.0, 0.02, 0.0)
		player.velocity = Vector3.ZERO
		player.camera_rig.set_first_person(true)
		await _frames(30)
		Input.action_press("move_forward")
		await _frames(40)
		var low := INF
		var high := -INF
		for i in 60:
			await _tree().process_frame
			var y := _cam().global_position.y - player.get_global_transform_interpolated().origin.y
			low = minf(low, y)
			high = maxf(high, y)
		Input.action_release("move_forward")
		await _frames(30)
		spans.append(high - low)
	print("    the eye's rise and fall walking: bob on %.3f m, off %.3f m" % [spans[0], spans[1]])
	assert_gt(float(spans[0]), 0.008, "with the head bob on, the walk's step is felt")
	assert_lt(float(spans[1]), float(spans[0]) * 0.5, "with it off, most of it is gone")


func test_the_first_person_field_of_view_is_its_own() -> void:
	await _frames(3)
	Settings.set_value("video", "fov", 70.0)
	Settings.set_value("video", "fov_first_person", 90.0)
	player.camera_rig.set_first_person(true)
	await _frames(40)
	assert_near(_cam().fov, 90.0, 0.5, "first person is seen at its own field of view")
	player.camera_rig.set_first_person(false)
	await _frames(40)
	assert_near(_cam().fov, 70.0, 0.5, "and third person at its")
	Settings.set_value("video", "fov", 75.0)


func test_a_wall_keeps_the_eye_out_of_it() -> void:
	await _frames(3)
	_box(Vector3(4.0, 3.0, 0.2), Vector3(0.0, 1.5, -0.6))
	await _frames(3)
	var rig := player.camera_rig
	var from := Vector3(0.0, 1.6, 0.0)
	var put := rig._eye_clear_of_walls(from, Vector3(0.0, 1.6, -0.9))
	assert_gt(put.z, -0.5 + 0.0001, "the eye stops at the wall's face (%.2f)" % put.z)
	var free := rig._eye_clear_of_walls(from, Vector3(0.0, 1.6, 0.3))
	assert_near(free.z, 0.3, 0.001, "and goes where it likes away from it")


func test_the_toggle_goes_there_and_back() -> void:
	if not _rig_built():
		return
	await _first_person()
	var m := _model()
	var hidden := m.first_person_hidden()
	player.camera_rig.set_first_person(false)
	await _frames(40)
	assert_false(m.first_person, "third person again")
	assert_true(m.visible, "the body drawn")
	for mi in hidden:
		assert_ne(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "%s is drawn again" % mi.name)
	var gap := _cam().global_position.distance_to(player.global_position + Vector3.UP * CameraRig.TP_HEIGHT)
	assert_gt(gap, 2.0, "the camera is back over the shoulder (%.2f m)" % gap)
	player.camera_rig.toggle_mode()
	await _frames(40)
	assert_true(m.first_person, "and through the eyes once more")
	assert_lt(_cam().global_position.distance_to(player.first_person_eye()), 0.08, "at the eyes")


func assert_lt(a: float, b: float, msg := "") -> void:
	assert_gt(b, a, msg)
