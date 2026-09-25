class_name RideSeat
extends SkeletonModifier3D
## The rider's legs astride the barrel and hands forward on the reins, laid over whatever the clips
## pose, for as long as the body has no seat clip of its own (`Ride`, player-feel's, CONTRACTS §3).
##
## Without it a body in the saddle stood in its Idle with its legs through the horse, or sat in its
## Sit_Idle with them out along the neck as on a bench. This turns each thigh out and forward round
## the barrel, each shin down the horse's side toward the stirrup, and the arms forward to where the
## reins are held (Rider's figures: knees 0.31 m out, stirrups 0.65 m below the seat, hands 0.30 m
## ahead and 0.25 m up). It aims whole bones, in the skeleton's own space (+Z ahead, +X the body's
## left, +Y up), after the clips and every other modifier.

## 0 off, 1 fully astride; the Rider eases it in and out as the body gets up and down.
var amount := 0.0
## Directions in the skeleton's space, for the left side (+X); the right side mirrors X.
const THIGH := Vector3(0.52, -0.50, 0.69)
const SHIN := Vector3(0.10, -0.96, -0.20)
const FOOT := Vector3(0.12, -0.25, 0.96)
const UPPER_ARM := Vector3(0.18, -0.78, 0.60)
const FOREARM := Vector3(-0.22, -0.18, 0.96)

var _ids: Dictionary = {}


func _process_modification() -> void:
	if amount <= 0.001:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	if _ids.is_empty():
		for n in ["UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R",
				"UpperArm.L", "LowerArm.L", "UpperArm.R", "LowerArm.R"]:
			_ids[n] = sk.find_bone(n)
	for side in ["L", "R"]:
		var sx := 1.0 if side == "L" else -1.0
		var m := Vector3(sx, 1.0, 1.0)
		_aim(sk, int(_ids["UpperLeg." + side]), THIGH * m)
		_aim(sk, int(_ids["LowerLeg." + side]), SHIN * m)
		_aim(sk, int(_ids["Foot." + side]), FOOT * m)
		_aim(sk, int(_ids["UpperArm." + side]), UPPER_ARM * m)
		_aim(sk, int(_ids["LowerArm." + side]), FOREARM * m)


## Turns `bone` (its whole pose) so that it points along `dir` in skeleton space, by `amount`.
func _aim(sk: Skeleton3D, bone: int, dir: Vector3) -> void:
	if bone < 0:
		return
	var g := sk.get_bone_global_pose(bone)
	var along := g.basis.y.normalized()
	var want := dir.normalized()
	if along.dot(want) > 0.9999:
		return
	var turn := Quaternion(along, want)
	turn = Quaternion.IDENTITY.slerp(turn, clampf(amount, 0.0, 1.0))
	var parent := sk.get_bone_parent(bone)
	var pg := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var new_global := Basis(turn) * g.basis
	var local := (pg.inverse() * new_global).orthonormalized()
	sk.set_bone_pose_rotation(bone, local.get_rotation_quaternion())
