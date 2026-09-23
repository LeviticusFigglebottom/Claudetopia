class_name Footfalls
extends RefCounted
## The steps a walking body takes, as sounds: one footstep per stride, on whatever is underfoot
## (Foley.surface_at). A body calls advance() once per physics frame, after it has moved.
##
## Strides are counted in distance, not in animation events: a placeholder body has no feet to
## put down and the forged rig's footstep events are not the driver's timeline (see
## AnimationDriver), while distance over the ground is the same for every body. A stroll takes
## short steps and a run long ones; a smaller body takes shorter steps.

## Below this speed a body is shuffling, not walking, and makes no steps (m/s).
const MIN_SPEED := 0.6
## Further than this from the player, nobody hears a footstep, so none is made (metres).
const HEAR_RANGE := 30.0

## Distance walked since the last step.
var travelled := 0.0
## The surface the last step landed on ("" before the first).
var surface := ""
## Steps made, for tests and for anybody counting.
var steps := 0


## Stride length at a pace: 0.35·speed + 0.6 m, between 0.8 and 2.4 m, scaled by the body.
## A walk (4.2 m/s) is a step every 0.48 s, a run (6.5 m/s) every 0.37 s.
static func stride_for(speed: float, body_scale: float = 1.0) -> float:
	return clampf(0.35 * speed + 0.6, 0.8, 2.4) * clampf(body_scale, 0.3, 3.0)


## Counts the ground covered this frame and makes a step when a stride is done. Returns the
## surface stepped on, or "" when no step fell in this frame.
func advance(body: Node3D, delta: float, speed: float, on_floor: bool, body_scale: float = 1.0,
		volume_db: float = 0.0) -> String:
	if not on_floor or speed < MIN_SPEED:
		# Standing still, the next step is half a stride away: starting to walk makes a sound
		# at once rather than a full stride later.
		travelled = stride_for(maxf(speed, MIN_SPEED), body_scale) * 0.5
		return ""
	travelled += speed * delta
	var stride := stride_for(speed, body_scale)
	if travelled < stride:
		return ""
	travelled -= stride
	var at := body.global_position
	if not Foley.near_listener(at, HEAR_RANGE):
		return ""
	var under := Foley.surface_at(at)
	if under == "water" and surface != "water":
		Foley.play("water_splash", at, volume_db)
	surface = under
	steps += 1
	Foley.footstep(under, at, volume_db)
	return under
