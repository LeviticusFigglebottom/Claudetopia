class_name CameraRig
extends Node3D
## First/third-person camera rig (DESIGN §5.2): an orbit with a shoulder offset, lock-on framing,
## sneak lowers the pivot, sprint draws the camera back and widens the view, and FOV,
## sensitivity, invert and camera side come from Settings. Builds its own
## Yaw > Pitch > Arm > Camera3D chain.
##
## `yaw` is a WORLD yaw: where the player is looking, which the mouse turns and nothing else
## does. The rig is `top_level` and follows its body's position every frame; it never takes the
## body's rotation. It used to be a plain child of the body, so the view looked along
## body yaw + `yaw` while movement, respawn and saves all read `yaw` as the whole of it: W went
## one way and the camera looked another whenever the body was not facing north, every turn of
## the body swung the view and the compass with it, and a 90-degree strafe turned the camera by
## 90 degrees in 1 s with nobody touching the mouse (DECISIONS 2026-09-23).
##
## Everything here runs once per rendered frame from the body's interpolated position, so it is
## as smooth at 144 Hz as at 60: the follow (a gentle lag across the ground, a softer one up and
## down), and the collision, a sphere cast from the pivot to where the camera wants to be, pulled
## in at once so the camera never looks through a wall and let back out over about a third of a
## second so it never pops back. The SpringArm3D this replaces resolved collision on physics
## ticks only.

signal mode_changed(first_person: bool)

const TP_ARM_LENGTH := 3.6
const TP_SHOULDER := 0.4
const TP_HEIGHT := 1.55
const TP_HEIGHT_SNEAK := 1.15
const FP_HEIGHT := 1.65
const FP_HEIGHT_SNEAK := 1.15
const AIM_ARM_LENGTH := 1.5
const AIM_SHOULDER := 0.7
## Sprinting draws the camera back and widens the view, in step with the actual speed between a
## jog and a sprint (Player.JOG_SPEED 5.0 and SPRINT_SPEED 7.8), eased in and out.
const SPRINT_ARM := 0.5
const SPRINT_FOV := 7.0
const SPRINT_FROM := 5.2
const SPRINT_FULL := 7.6
const SPRINT_IN_S := 0.45
const SPRINT_OUT_S := 0.6
## Follow rates, 1/s. Across the ground 20 trails a jog by ~0.25 m and a sprint by ~0.39 m,
## and closes that up in about 0.15 s when the body stops; up and down it is softer, which takes
## the edge off steps and the heightfield. At 14 the view drew 0.4 m away at every start and
## came back at every stop, and read as a camera on a rubber band.
const FOLLOW_XZ := 20.0
const FOLLOW_Y := 9.0
## Collision: the camera is a ball this size, never nearer the pivot than ARM_MIN, and eases back
## out with this time constant once the way is clear.
const COLLIDE_RADIUS := 0.22
const ARM_MIN := 0.35
const ARM_OUT_S := 0.35
## Over open country the camera stays at least this high above the heightfield.
const GROUND_CLEARANCE := 0.35
const PITCH_MIN_TP := -1.05
const PITCH_MAX_TP := 0.95
const PITCH_MIN_FP := -1.48
const PITCH_MAX_FP := 1.4
const MASK_CAMERA := (1 << 0) | (1 << 9) | (1 << 10)   # world | camera_blocker | terrain
const LOCK_FOLLOW_SPEED := 5.0
const MOUSE_RAD_PER_PX := 0.008
const RENDER_LAYER_FP_ARMS := 1 << 1
## A body that moves further than this between two frames was put somewhere, not walked there:
## the rig jumps with it instead of following.
const SNAP_DISTANCE := 4.0

var yaw: float = 0.0
var pitch: float = -0.18
var first_person: bool = false
var aiming: bool = false
var sneak_low: bool = false
var stick: Vector2 = Vector2.ZERO         # gamepad look, set by the player each frame
var lock_point: Vector3 = Vector3.ZERO
var has_lock: bool = false
var look_enabled: bool = true
## The body the rig follows: its parent, unless something says otherwise.
var target: Node3D = null

var yaw_node: Node3D
var pitch_node: Node3D
## Carries the shoulder offset; the camera sits back along its +Z.
var arm: Node3D
var camera: Camera3D
var fp_arms: Node3D

var _mouse_delta: Vector2 = Vector2.ZERO
var _arm_length: float = TP_ARM_LENGTH     # what the mode asks for, eased
var _arm_scale: float = 1.0                 # share of it the collision allows, as drawn
var _shoulder: float = TP_SHOULDER
var _shoulder_now: float = TP_SHOULDER
var _height: float = TP_HEIGHT
var _sprint_w: float = 0.0
var _base_fov: float = 75.0
var _pivot := Vector3.ZERO
var _placed := false
var _last_target := Vector3.ZERO
var _ball := SphereShape3D.new()
var _exclude: Array[RID] = []


func _ready() -> void:
	_build()
	var parent := get_parent()
	if target == null:
		target = parent as Node3D
	# The view turns with the mouse and not with the body: see the class comment.
	top_level = true
	# Placed every frame from the body's interpolated transform, so it must not be interpolated
	# a second time between physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ball.radius = COLLIDE_RADIUS
	if parent is CollisionObject3D:
		_exclude = [(parent as CollisionObject3D).get_rid()]
	yaw = parent.rotation.y if parent is Node3D else 0.0
	_apply_settings()
	if Settings.has_signal("changed"):
		Settings.changed.connect(_on_setting_changed)
	camera.make_current()
	snap_to_target()


func _build() -> void:
	yaw_node = get_node_or_null("Yaw") as Node3D
	if yaw_node == null:
		yaw_node = Node3D.new()
		yaw_node.name = "Yaw"
		add_child(yaw_node)
	pitch_node = yaw_node.get_node_or_null("Pitch") as Node3D
	if pitch_node == null:
		pitch_node = Node3D.new()
		pitch_node.name = "Pitch"
		yaw_node.add_child(pitch_node)
	arm = pitch_node.get_node_or_null("Arm") as Node3D
	if arm == null:
		arm = Node3D.new()
		arm.name = "Arm"
		pitch_node.add_child(arm)
	camera = arm.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.near = 0.05
		camera.far = 3000.0
		arm.add_child(camera)
	camera.position = Vector3(0.0, 0.0, TP_ARM_LENGTH)
	camera.cull_mask = (1 << 0) | RENDER_LAYER_FP_ARMS | (1 << 2)
	fp_arms = camera.get_node_or_null("FPArms") as Node3D
	if fp_arms == null:
		fp_arms = Node3D.new()
		fp_arms.name = "FPArms"
		camera.add_child(fp_arms)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.82, 0.7, 0.58)
		var arm_box := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.09, 0.09, 0.45)
		arm_box.mesh = arm_mesh
		arm_box.material_override = mat
		arm_box.position = Vector3(0.26, -0.24, -0.42)
		arm_box.layers = RENDER_LAYER_FP_ARMS
		fp_arms.add_child(arm_box)
		var blade := MeshInstance3D.new()
		var blade_mesh := BoxMesh.new()
		blade_mesh.size = Vector3(0.035, 0.035, 0.8)
		blade.mesh = blade_mesh
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.6, 0.62, 0.66)
		bmat.metallic = 0.8
		bmat.roughness = 0.35
		blade.material_override = bmat
		blade.position = Vector3(0.27, -0.2, -1.0)
		blade.layers = RENDER_LAYER_FP_ARMS
		fp_arms.add_child(blade)
	fp_arms.visible = first_person


func _apply_settings() -> void:
	_base_fov = clampf(float(Settings.get_value("video", "fov", 75.0)), 50.0, 110.0)
	camera.fov = _base_fov + SPRINT_FOV * _sprint_w
	var side := int(Settings.get_value("controls", "camera_side", 1))
	_shoulder = TP_SHOULDER * (1.0 if side >= 0 else -1.0)


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if section == "video" and key == "fov" or section == "controls" and key == "camera_side":
		_apply_settings()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and look_enabled:
		add_mouse_look((event as InputEventMouseMotion).relative)


## Adds raw mouse motion (pixels, as InputEventMouseMotion.relative reports it). Moving the hand
## right turns the view right (yaw falls: a clockwise turn seen from above, so the compass heading
## rises) and moving it toward you pitches the view down, unless Settings asks for inverted Y.
func add_mouse_look(relative: Vector2) -> void:
	_mouse_delta += relative


func set_lock_point(point: Vector3, active: bool) -> void:
	lock_point = point
	has_lock = active


## Compass heading of the view in degrees: 0 north (-Z), 90 east (+X). Where the player looks,
## which is what the compass strip shows.
func heading_degrees() -> float:
	return fposmod(rad_to_deg(-yaw), 360.0)


## Puts the rig on its body at once, with no follow lag: after a teleport, a respawn, a load or
## the first frame.
func snap_to_target() -> void:
	_placed = false
	_follow(0.0)


func _follow(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var at := target.get_global_transform_interpolated().origin
	var want := Vector3(at.x, at.y + _height, at.z)
	if not _placed or first_person or at.distance_to(_last_target) > SNAP_DISTANCE:
		_pivot = want
	else:
		var kx := 1.0 - exp(-FOLLOW_XZ * delta)
		var ky := 1.0 - exp(-FOLLOW_Y * delta)
		_pivot = Vector3(lerpf(_pivot.x, want.x, kx), lerpf(_pivot.y, want.y, ky), lerpf(_pivot.z, want.z, kx))
	_last_target = at
	_placed = true
	global_position = _pivot
	global_rotation = Vector3.ZERO


## 0 at a jog or slower, 1 at a sprint, from how fast the body is really going -- while it is
## sprinting. A roll peaks at 11 m/s and a knockback can match it; neither is a sprint, and a view
## that breathed out at every roll read as the camera lurching.
func _sprint_amount() -> float:
	var body := target as CharacterBody3D
	if body == null or not is_instance_valid(body):
		return 0.0
	if "is_sprinting" in body and not bool(body.get("is_sprinting")):
		return 0.0
	var v := body.get_real_velocity()
	return clampf((Vector2(v.x, v.z).length() - SPRINT_FROM) / (SPRINT_FULL - SPRINT_FROM), 0.0, 1.0)


func _process(delta: float) -> void:
	var mouse_sens := float(Settings.get_value("controls", "mouse_sensitivity", 0.25))
	var pad_sens := float(Settings.get_value("controls", "gamepad_sensitivity", 2.6))
	var invert := -1.0 if bool(Settings.get_value("controls", "invert_y", false)) else 1.0
	if look_enabled:
		yaw -= _mouse_delta.x * mouse_sens * MOUSE_RAD_PER_PX
		pitch -= _mouse_delta.y * mouse_sens * MOUSE_RAD_PER_PX * invert
		yaw -= stick.x * pad_sens * delta
		pitch -= stick.y * pad_sens * delta * invert
	_mouse_delta = Vector2.ZERO
	var sprint_to := 0.0 if first_person or aiming else _sprint_amount()
	var tau := SPRINT_IN_S if sprint_to > _sprint_w else SPRINT_OUT_S
	_sprint_w = lerpf(_sprint_w, sprint_to, 1.0 - exp(-delta / tau))
	var target_height := FP_HEIGHT if first_person else TP_HEIGHT
	var target_arm := 0.0 if first_person else (AIM_ARM_LENGTH if aiming else TP_ARM_LENGTH + SPRINT_ARM * _sprint_w)
	var target_shoulder := 0.0 if first_person else (_shoulder * (AIM_SHOULDER / TP_SHOULDER) if aiming else _shoulder)
	if sneak_low:
		target_height = FP_HEIGHT_SNEAK if first_person else TP_HEIGHT_SNEAK
	var k := clampf(10.0 * delta, 0.0, 1.0)
	_height = lerpf(_height, target_height, k)
	_arm_length = lerpf(_arm_length, target_arm, k)
	_shoulder_now = lerpf(_shoulder_now, target_shoulder, k)
	_follow(delta)
	if has_lock and not first_person:
		var origin := global_position
		var to := lock_point - origin
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() > 0.5:
			var want_yaw := atan2(-flat.x, -flat.z)
			yaw = lerp_angle(yaw, want_yaw, clampf(LOCK_FOLLOW_SPEED * delta, 0.0, 1.0))
			var want_pitch := clampf(atan2(to.y, flat.length()) * 0.5 - 0.22, PITCH_MIN_TP, 0.1)
			pitch = lerpf(pitch, want_pitch, clampf(LOCK_FOLLOW_SPEED * 0.6 * delta, 0.0, 1.0))
	yaw = wrapf(yaw, -PI, PI)
	pitch = clampf(pitch, PITCH_MIN_FP if first_person else PITCH_MIN_TP, PITCH_MAX_FP if first_person else PITCH_MAX_TP)
	yaw_node.rotation.y = yaw
	pitch_node.rotation.x = pitch
	_collide(delta)
	_keep_above_ground()
	camera.fov = _base_fov + SPRINT_FOV * _sprint_w
	fp_arms.visible = first_person


## Where the arm and the camera sit this frame: the whole offset from the pivot (shoulder and
## length together) is shortened to what a ball cast along it allows, at once when something is
## in the way, and let out again slowly when it is gone.
func _collide(delta: float) -> void:
	var lift := 0.12 if not first_person else 0.0
	if first_person or _arm_length <= 0.01:
		_arm_scale = 1.0
		arm.position = Vector3(_shoulder_now, lift, 0.0)
		camera.position = Vector3(0.0, 0.0, maxf(_arm_length, 0.0))
		return
	var allowed := 1.0
	var desired := yaw_node.global_transform * (pitch_node.transform * Vector3(_shoulder_now, lift, _arm_length))
	var from := global_position
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null and from.distance_to(desired) > 0.01:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _ball
		q.transform = Transform3D(Basis.IDENTITY, from)
		q.motion = desired - from
		q.collision_mask = MASK_CAMERA
		q.exclude = _exclude
		var hit := space.cast_motion(q)
		if hit.size() >= 1 and float(hit[0]) < 1.0:
			allowed = maxf(float(hit[0]), minf(ARM_MIN / maxf(from.distance_to(desired), 0.01), 1.0))
	if allowed < _arm_scale:
		_arm_scale = allowed
	else:
		_arm_scale = lerpf(_arm_scale, allowed, 1.0 - exp(-delta / ARM_OUT_S))
	arm.position = Vector3(_shoulder_now, lift, 0.0) * _arm_scale
	camera.position = Vector3(0.0, 0.0, _arm_length * _arm_scale)


## Open country has no collider under it (Terrain3D's collision only follows the camera), so the
## camera is also held above the heightfield itself.
func _keep_above_ground() -> void:
	if first_person:
		return
	var provider: Object = World.terrain()
	if provider == null or not provider.has_method("get_height"):
		return
	var p := camera.global_position
	var floor_y := float(provider.call("get_height", p.x, p.z)) + GROUND_CLEARANCE
	if p.y < floor_y:
		camera.global_position = Vector3(p.x, floor_y, p.z)


func toggle_mode() -> void:
	set_first_person(not first_person)


func set_first_person(value: bool) -> void:
	if first_person == value:
		return
	first_person = value
	fp_arms.visible = value
	mode_changed.emit(first_person)


func set_aiming(value: bool) -> void:
	aiming = value


## Horizontal camera forward (gameplay −Z convention).
func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func right_flat() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## True view direction, for aiming projectiles and interaction.
func aim_direction() -> Vector3:
	return -camera.global_transform.basis.z


func camera_position() -> Vector3:
	return camera.global_position


func shake(_strength: float) -> void:
	pass
