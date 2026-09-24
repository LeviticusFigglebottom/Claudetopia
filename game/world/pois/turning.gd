class_name Turning
extends Node3D
## Something that goes round: a mill's wheel in its leat, a windmill's sails. It turns about its
## own local `axis` at `rate` radians a second while a camera is near enough to see it, and stands
## still past that, so a wheel nobody is looking at costs nothing.
##
## It is turned from _process, a frame at a time, so it is kept out of the physics interpolation,
## which would have it moved from the physics ticks (and the engine says so in the log).

## How far off a camera still sees it go round.
const AWAKE_M := 220.0

var axis := Vector3.RIGHT
var rate := 0.6


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or cam.global_position.distance_to(global_position) > AWAKE_M:
		return
	turn(delta)


## Turns it on by `seconds` of going round.
func turn(seconds: float) -> void:
	rotate_object_local(axis.normalized(), rate * seconds)
