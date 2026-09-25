class_name Turning
extends Node3D
## Something that goes round: a mill's wheel in its leat, a windmill's sails. It turns about its
## own local `axis` at `rate` radians a second while a camera is near enough to see it, and stands
## still past that, so a wheel nobody is looking at costs nothing. With `swing` it swings to and
## fro about the axis instead, by up to that many radians, as cords and rags do in the wind and a
## cage on its chain.
##
## It is turned from _process, a frame at a time, so it is kept out of the physics interpolation,
## which would have it moved from the physics ticks (and the engine says so in the log).

## How far off a camera still sees it go round.
const AWAKE_M := 220.0

var axis := Vector3.RIGHT
var rate := 0.6
## Over 0: swings to and fro by this many radians rather than going round, gusting a little.
var swing := 0.0
## Where in its swing it starts, so two hung side by side do not swing as one.
var phase := 0.0
var _rest := Basis.IDENTITY
var _rested := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or cam.global_position.distance_to(global_position) > AWAKE_M:
		return
	turn(delta)


## Turns it on by `seconds` of going round.
func turn(seconds: float) -> void:
	if swing <= 0.0:
		rotate_object_local(axis.normalized(), rate * seconds)
		return
	if not _rested:
		_rest = basis
		_rested = true
	phase += rate * seconds
	var angle := swing * (0.8 * sin(phase) + 0.25 * sin(phase * 2.3 + 1.1))
	basis = _rest * Basis(axis.normalized(), angle)
