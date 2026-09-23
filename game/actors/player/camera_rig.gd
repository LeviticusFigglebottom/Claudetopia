class_name CameraRig
extends Node3D
## First/third-person camera rig (DESIGN §5.2): orbit with shoulder offset, SpringArm3D
## collision, lock-on framing, sneak lowers the pivot, FOV / sensitivity / invert / camera side
## from Settings. Builds its own Yaw > Pitch > SpringArm3D > Camera3D chain when the scene lacks it.
##
## `yaw` is a WORLD yaw: where the player is looking, which the mouse turns and nothing else
## does. The rig is `top_level` and follows its body's position every frame; it never takes the
## body's rotation. It used to be a plain child of the body, so the view looked along
## body yaw + `yaw` while movement, respawn and saves all read `yaw` as the whole of it: W went
## one way and the camera looked another whenever the body was not facing north, every turn of
## the body swung the view and the compass with it, and a 90-degree strafe turned the camera by
## 90 degrees in 1 s with nobody touching the mouse (DECISIONS 2026-09-23).

signal mode_changed(first_person: bool)

const TP_ARM_LENGTH := 3.4
const TP_SHOULDER := 0.55
const TP_HEIGHT := 1.6
const TP_HEIGHT_SNEAK := 1.15
const FP_HEIGHT := 1.65
const FP_HEIGHT_SNEAK := 1.15
const AIM_ARM_LENGTH := 1.5
const AIM_SHOULDER := 0.7
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
var spring: SpringArm3D
var camera: Camera3D
var fp_arms: Node3D

var _mouse_delta: Vector2 = Vector2.ZERO
var _arm_length: float = TP_ARM_LENGTH
var _shoulder: float = TP_SHOULDER
var _height: float = TP_HEIGHT
var _placed := false
var _last_target := Vector3.ZERO


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
	if parent is CollisionObject3D:
		spring.add_excluded_object((parent as CollisionObject3D).get_rid())
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
	spring = pitch_node.get_node_or_null("SpringArm3D") as SpringArm3D
	if spring == null:
		spring = SpringArm3D.new()
		spring.name = "SpringArm3D"
		spring.spring_length = TP_ARM_LENGTH
		spring.margin = 0.15
		var shape := SphereShape3D.new()
		shape.radius = 0.22
		spring.shape = shape
		spring.collision_mask = MASK_CAMERA
		pitch_node.add_child(spring)
	camera = spring.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.near = 0.05
		camera.far = 3000.0
		spring.add_child(camera)
	camera.cull_mask = (1 << 0) | RENDER_LAYER_FP_ARMS | (1 << 2)
	fp_arms = camera.get_node_or_null("FPArms") as Node3D
	if fp_arms == null:
		fp_arms = Node3D.new()
		fp_arms.name = "FPArms"
		camera.add_child(fp_arms)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.82, 0.7, 0.58)
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.09, 0.09, 0.45)
		arm.mesh = arm_mesh
		arm.material_override = mat
		arm.position = Vector3(0.26, -0.24, -0.42)
		arm.layers = RENDER_LAYER_FP_ARMS
		fp_arms.add_child(arm)
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
	camera.fov = clampf(float(Settings.get_value("video", "fov", 75.0)), 50.0, 110.0)
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


## Puts the rig on its body at once: after a teleport, a respawn, a load or the first frame.
func snap_to_target() -> void:
	_placed = false
	_follow()


func _follow() -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var at := target.get_global_transform_interpolated().origin
	if _placed and at.distance_to(_last_target) > SNAP_DISTANCE:
		_placed = false
	_last_target = at
	_placed = true
	global_position = Vector3(at.x, at.y + _height, at.z)
	global_rotation = Vector3.ZERO


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
	var target_height := FP_HEIGHT if first_person else TP_HEIGHT
	var target_arm := 0.0 if first_person else (AIM_ARM_LENGTH if aiming else TP_ARM_LENGTH)
	var target_shoulder := 0.0 if first_person else (_shoulder * (AIM_SHOULDER / TP_SHOULDER) if aiming else _shoulder)
	if sneak_low:
		target_height = FP_HEIGHT_SNEAK if first_person else TP_HEIGHT_SNEAK
	var k := clampf(10.0 * delta, 0.0, 1.0)
	_height = lerpf(_height, target_height, k)
	_arm_length = lerpf(_arm_length, target_arm, k)
	_follow()
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
	var shoulder_now: float = lerpf(spring.position.x, target_shoulder, k)
	yaw_node.rotation.y = yaw
	pitch_node.rotation.x = pitch
	spring.spring_length = _arm_length
	spring.position = Vector3(shoulder_now, 0.12 if not first_person else 0.0, 0.0)
	fp_arms.visible = first_person


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
