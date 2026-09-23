extends TestCase
## Smooth at any refresh rate: physics interpolation is on, the camera follows the body as it is
## drawn (not as the last physics tick left it) with a gentle lag, a teleport leaves no smear,
## a sprint draws the view back and widens it, and a wall pulls the camera in at once and lets it
## out slowly. Before: interpolation was off, the body stepped at 60 Hz on any faster display,
## and the camera was glued to the body's physics position and turned with it.

const PLAYER := preload("res://actors/player/player.tscn")
const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const KEYS: Array[String] = ["move_forward", "move_back", "move_left", "move_right", "sprint", "walk"]

var player: Player = null
var floor_body: StaticBody3D = null
var wall: StaticBody3D = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(7)
	SaveSystem.pending.clear()


func after_each() -> void:
	for a in KEYS:
		if InputMap.has_action(a):
			Input.action_release(a)
	for n in [player, floor_body, wall]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	player = null
	floor_body = null
	wall = null
	GameState.reset_for_new_game(7)


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_tree().root.add_child(body)
	body.global_position = at
	return body


func _stand() -> void:
	floor_body = _box(Vector3(800.0, 1.0, 800.0), Vector3(0.0, -0.5, 0.0))
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	player.teleport(Vector3(0.0, 0.02, 0.0), 0.0)
	for i in 8:
		await _tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await _tree().process_frame


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func test_physics_interpolation_is_on() -> void:
	assert_true(bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)),
			"physics/common/physics_interpolation must be on: without it a body moved at 60 Hz steps on any faster display")
	assert_true(_tree().physics_interpolation, "the scene tree is not interpolating")
	assert_near(float(ProjectSettings.get_setting("physics/common/physics_jitter_fix", 0.5)), 0.0, 0.0001,
			"the jitter fix fights interpolation and is off with it")


## The rig trails a jog by a gentle, bounded amount, and from one rendered frame to the next the
## camera never moves further than the body can. Read from the rig's own frame (its pivot against
## the body position it followed, `_last_target`), because the test resumes before the rig's
## _process each frame and would otherwise compare this frame's body with last frame's camera.
func test_the_camera_follows_with_a_gentle_lag() -> void:
	await _stand()
	var rig := player.camera_rig
	Input.action_press("move_forward")
	for i in 60:
		await _tree().physics_frame
	var lag := 0.0
	var worst_excess := 0.0
	var last_cam := rig.global_position
	var last_body: Vector3 = rig.get("_last_target")
	var last_lag := _flat(last_cam).distance_to(_flat(last_body))
	for i in 60:
		await _tree().process_frame
		var body: Vector3 = rig.get("_last_target")
		var cam := rig.global_position
		var now_lag := _flat(cam).distance_to(_flat(body))
		lag = maxf(lag, now_lag)
		# a camera may catch up the lag it carried, never more: anything beyond is a jump
		worst_excess = maxf(worst_excess, cam.distance_to(last_cam) - body.distance_to(last_body) - last_lag)
		last_cam = cam
		last_body = body
		last_lag = now_lag
	Input.action_release("move_forward")
	print("    at a jog the camera's pivot trails the drawn body by up to %.2f m; largest frame step beyond body step + lag %.3f m" % [
		lag, worst_excess])
	assert_true(lag > 0.05, "no lag at all: the follow is rigid (%.3f m)" % lag)
	assert_true(lag < Player.JOG_SPEED / CameraRig.FOLLOW_XZ + 0.1, "the camera trails a jog by %.2f m" % lag)
	assert_true(worst_excess < 0.02, "the camera jumped %.3f m beyond the body's step and its own lag in one frame" % worst_excess)


## A teleport (a door, a Hearthstone, a load) leaves nothing behind: the body is drawn where it
## was put on the very next frame, and the camera is with it rather than trailing across the map.
func test_a_teleport_leaves_no_smear() -> void:
	await _stand()
	Input.action_press("move_forward")
	for i in 30:
		await _tree().physics_frame
	Input.action_release("move_forward")
	var far := Vector3(420.0, 0.02, -310.0)
	floor_body.global_position = Vector3(far.x, -0.5, far.z)
	player.teleport(far, PI * 0.5)
	await _tree().process_frame
	var drawn := player.get_global_transform_interpolated().origin
	assert_true(drawn.distance_to(far) < 0.05, "the body is drawn %.2f m from where it was put" % drawn.distance_to(far))
	assert_true(_flat(player.camera_rig.global_position).distance_to(_flat(far)) < 0.05,
			"the camera is %.2f m from the body after the teleport" % _flat(player.camera_rig.global_position).distance_to(_flat(far)))
	assert_near(player.camera_rig.yaw, PI * 0.5, 0.001, "the view faces the way the body was put")


## Sprinting draws the camera back and widens the view, in step with the speed; stopping returns
## both, eased, not snapped.
func test_a_sprint_draws_the_view_back_and_widens_it() -> void:
	await _stand()
	var rig := player.camera_rig
	await _frames(4)
	var base_fov := rig.camera.fov
	var base_arm := rig.camera.position.z
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in 120:
		await _tree().physics_frame
	await _frames(2)
	var sprint_fov := rig.camera.fov
	var sprint_arm := rig.camera.position.z
	Input.action_release("sprint")
	Input.action_release("move_forward")
	for i in 3:
		await _tree().physics_frame
	await _frames(1)
	var just_after := rig.camera.fov
	for i in 150:
		await _tree().physics_frame
	await _frames(2)
	print("    fov %.1f -> sprinting %.1f -> a moment after stopping %.1f -> %.1f; arm %.2f -> %.2f m" % [
		base_fov, sprint_fov, just_after, rig.camera.fov, base_arm, sprint_arm])
	assert_near(sprint_fov - base_fov, CameraRig.SPRINT_FOV, 0.8, "the view widens by about %.0f degrees at a sprint" % CameraRig.SPRINT_FOV)
	assert_near(sprint_arm - base_arm, CameraRig.SPRINT_ARM, 0.1, "the camera draws back about %.1f m at a sprint" % CameraRig.SPRINT_ARM)
	assert_true(just_after > base_fov + 3.0, "stopping must not snap the view back (%.1f a moment after)" % just_after)
	assert_near(rig.camera.fov, base_fov, 0.3, "and after the stop the view settles back")


## A wall behind the player pulls the camera in at once (it never looks through the wall) and,
## taken away, lets it back out over a third of a second rather than popping.
func test_a_wall_pulls_the_camera_in_and_it_eases_back_out() -> void:
	await _stand()
	var rig := player.camera_rig
	rig.pitch = 0.0
	await _frames(6)
	var full := rig.camera.global_position.distance_to(rig.global_position)
	# the camera sits behind the body, which faces north: a wall 1.6 m south of it
	wall = _box(Vector3(12.0, 6.0, 0.4), Vector3(0.0, 2.0, 1.8))
	await _tree().physics_frame
	await _frames(2)
	var blocked := rig.camera.global_position.distance_to(rig.global_position)
	wall.queue_free()
	wall = null
	await _tree().physics_frame
	await _frames(1)
	var one_frame := rig.camera.global_position.distance_to(rig.global_position)
	for i in 90:
		await _tree().physics_frame
	await _frames(2)
	var later := rig.camera.global_position.distance_to(rig.global_position)
	print("    camera distance: clear %.2f m, wall 1.6 m behind %.2f m, a frame after it goes %.2f m, then %.2f m" % [
		full, blocked, one_frame, later])
	assert_true(blocked < 1.6, "the camera must stay on this side of the wall (%.2f m out)" % blocked)
	assert_true(one_frame < full - 0.5, "with the wall gone the camera must ease out, not pop (%.2f of %.2f m at once)" % [one_frame, full])
	assert_near(later, full, 0.05, "and it gets all the way back")


## The weapon and lantern sockets are moved by the animation every frame, so they are placed
## exactly on the bone rather than interpolated between physics ticks (which trails the hand).
func test_the_sockets_follow_the_hand_not_the_tick() -> void:
	if not ResourceLoader.exists(HumanoidModel.RIG_PATH):
		return
	var root := Node3D.new()
	_tree().root.add_child(root)
	var m := (load(MODEL_SCENE) as PackedScene).instantiate() as HumanoidModel
	root.add_child(m)
	for name in m.socket_names():
		assert_eq(m.socket(str(name)).physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF,
				"%s is interpolated between ticks and will trail the hand" % str(name))
	root.free()
