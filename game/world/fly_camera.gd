class_name FlyCamera
extends Camera3D
## Free camera used when there is no player: WASD to move, Q/E down/up, mouse to look
## (hold right mouse or press Tab to capture), Shift for fast, Alt for slow.
## It is also the capture runner's and the smoke runner's eye, so it exposes
## `move_to(pos, look_at)` and `settle()` for scripted use.

@export var speed: float = 24.0
@export var fast_multiplier: float = 6.0
@export var slow_multiplier: float = 0.2
@export var mouse_sensitivity: float = 0.0022
@export var accelerate: float = 9.0
@export var keep_above_ground: bool = true
@export var ground_clearance: float = 1.6

var provider: TerrainProvider = null
var _velocity := Vector3.ZERO
var _yaw := 0.0
var _pitch := -0.15
var _looking := false


func _ready() -> void:
	add_to_group("fly_camera")
	# flown every frame in _process, and placed outright by the capture and smoke runners
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_yaw = rotation.y
	_pitch = rotation.x
	current = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_set_looking(event.pressed)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_set_looking(not _looking)
	elif event is InputEventMouseMotion and _looking:
		var motion: InputEventMouseMotion = event
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.5, 1.5)


func _set_looking(on: bool) -> void:
	_looking = on
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)
	var dir := Vector3.ZERO
	if not Input.is_anything_pressed():
		_velocity = _velocity.lerp(Vector3.ZERO, clampf(delta * accelerate, 0.0, 1.0))
	else:
		dir += transform.basis.z * (Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
		dir += transform.basis.x * (Input.get_action_strength("move_right") - Input.get_action_strength("move_left"))
		dir.y += Input.get_action_strength("jump") - Input.get_action_strength("sneak")
		if Input.is_key_pressed(KEY_E):
			dir.y += 1.0
		if Input.is_key_pressed(KEY_Q):
			dir.y -= 1.0
	var mult := 1.0
	if Input.is_action_pressed("sprint"):
		mult = fast_multiplier
	elif Input.is_key_pressed(KEY_ALT):
		mult = slow_multiplier
	var target := dir.normalized() * speed * mult
	_velocity = _velocity.lerp(target, clampf(delta * accelerate, 0.0, 1.0))
	position += _velocity * delta
	if keep_above_ground and provider != null:
		var floor_y := provider.get_height(position.x, position.z) + ground_clearance
		if position.y < floor_y:
			position.y = floor_y


## Places the camera and points it somewhere (used by the capture and smoke runners).
func move_to(pos: Vector3, look_target: Variant = null) -> void:
	position = pos
	_velocity = Vector3.ZERO
	if look_target is Vector3:
		look_at_point(look_target)
	rotation = Vector3(_pitch, _yaw, 0.0)


func look_at_point(target: Vector3) -> void:
	var to := target - position
	if to.length_squared() < 0.0001:
		return
	_yaw = atan2(-to.x, -to.z)
	_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.5, 1.5)
	rotation = Vector3(_pitch, _yaw, 0.0)


func set_yaw_pitch(yaw_deg: float, pitch_deg: float) -> void:
	_yaw = deg_to_rad(yaw_deg)
	_pitch = clampf(deg_to_rad(pitch_deg), -1.5, 1.5)
	rotation = Vector3(_pitch, _yaw, 0.0)


func yaw_degrees() -> float:
	return rad_to_deg(_yaw)


func pitch_degrees() -> float:
	return rad_to_deg(_pitch)
