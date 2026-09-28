class_name HorseLeapPose
extends SkeletonModifier3D
## A horse's legs in a jump (triage 59), laid over whatever gait the clips are playing: at take-off
## the forelegs fold up and the hind legs drive out behind; over the top all four are folded under;
## coming down the forelegs reach for the ground while the hind stay tucked. The forge has no jump
## clip, so the pose is made here from the Mount's own leap (`leap`: 1 leaving the ground .. -1
## landing) and eased in and out by `weight`.
##
## It aims whole bones (RideSeat's way) in the skeleton's own space: +Z the horse's front, +Y up.

var leap := 0.0
var weight := 0.0

## Each leg bone's direction, knee or hock to the next joint, in the three moments of a leap.
const FORE_TUCK := {"Humerus": Vector3(0.0, -0.55, 0.83), "Forearm": Vector3(0.0, 0.15, 0.99), "FrontCannon": Vector3(0.0, -0.45, -0.89)}
const FORE_REACH := {"Humerus": Vector3(0.0, -0.97, 0.15), "Forearm": Vector3(0.0, -0.85, 0.53), "FrontCannon": Vector3(0.0, -0.9, 0.44)}
const HIND_PUSH := {"Thigh": Vector3(0.0, -0.97, -0.24), "Gaskin": Vector3(0.0, -0.7, -0.71), "HindCannon": Vector3(0.0, -0.6, -0.8)}
const HIND_TUCK := {"Thigh": Vector3(0.0, -0.55, 0.83), "Gaskin": Vector3(0.0, -0.5, -0.87), "HindCannon": Vector3(0.0, -0.6, 0.8)}

var _ids: Dictionary = {}


func _process_modification() -> void:
	if weight <= 0.001:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	if _ids.is_empty():
		for side in [".L", ".R"]:
			for n in FORE_TUCK.keys() + HIND_TUCK.keys():
				_ids[str(n) + side] = sk.find_bone(str(n) + side)
	# the forelegs reach for the ground once the body is coming down; the hind legs push until it
	# is well up, and then fold
	var reach := clampf((-leap - 0.45) / 0.4, 0.0, 1.0)
	var push := clampf((leap - 0.55) / 0.35, 0.0, 1.0)
	for side in [".L", ".R"]:
		for n in FORE_TUCK:
			_aim(sk, int(_ids[str(n) + side]), (FORE_TUCK[n] as Vector3).lerp(FORE_REACH[n], reach))
		for n in HIND_TUCK:
			_aim(sk, int(_ids[str(n) + side]), (HIND_TUCK[n] as Vector3).lerp(HIND_PUSH[n], push))


## Turns `bone` so that it points along `dir` (skeleton space), by `weight`; the leg's own spread
## (its x) is kept.
func _aim(sk: Skeleton3D, bone: int, dir: Vector3) -> void:
	if bone < 0:
		return
	var g := sk.get_bone_global_pose(bone)
	var along := g.basis.y.normalized()
	var want := Vector3(along.x, dir.y, dir.z).normalized()
	if along.dot(want) > 0.9999:
		return
	var turn := Quaternion(along, want)
	turn = Quaternion.IDENTITY.slerp(turn, clampf(weight, 0.0, 1.0))
	var parent := sk.get_bone_parent(bone)
	var pg := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := (pg.inverse() * (Basis(turn) * g.basis)).orthonormalized()
	sk.set_bone_pose_rotation(bone, local.get_rotation_quaternion())
