class_name ArmRoom
extends SkeletonModifier3D
## Holds the arms out from a padded or heavy body by `degrees`, and in under a long cloak by `hold`.
##
## The clips are authored on the default body, and its relaxed Idle hangs the wrists 5 cm
## outside the hip. A gambeson puts 3 cm of padding on the body and 3 cm more on the sleeve, and
## the hands of everyone wearing one hung inside its skirt, out of sight; plate and a brigandine
## did the same, and the heavy body's hips stand 2.5 cm wider on the same skeleton. After the
## clips have posed the skeleton this turns each upper arm out about the body's forward axis,
## so the whole arm hangs clear, in every clip, walking as standing.
##
## A cloak to the knee hangs over the arms, and the Walk swings a hand 30 cm ahead of the hip:
## the cloth that lies on an arm takes most of its swing, and the hand still came out through the
## front of the cloak at every step. `hold` takes that share of the clip's pose of the upper arms
## and forearms back to how they hang in the Idle (`hang`), so under a cloak the arms swing less,
## as they do when cloth lies on them. HumanoidModel sets it while the body walks or runs in a
## long cloak and leaves it at 0 for everything else -- a blow, a guard, a fall needs the whole arm.

var degrees := 0.0
## 0..1: the share of the arms' pose taken back to `hang`.
var hold := 0.0
## bone index -> the local rotation the bone hangs at in the Idle (the upper arms and forearms).
var hang: Dictionary = {}
var _bones: Array[int] = []
var _fore: Array[int] = []
## what this wrote last, per bone: a pose still equal to it was not re-posed since, and turning
## it again would add the turn up frame after frame while an animation is held
var _last: Dictionary = {}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var holding := hold > 0.001 and not hang.is_empty()
	if is_zero_approx(degrees) and not holding:
		return
	if _bones.is_empty():
		_bones = [sk.find_bone("UpperArm.L"), sk.find_bone("UpperArm.R")]
		_fore = [sk.find_bone("LowerArm.L"), sk.find_bone("LowerArm.R")]
	for k in _bones.size():
		if holding:
			_hold_in(sk, _fore[k])
		var bone: int = _bones[k]
		if bone < 0:
			continue
		var rot := sk.get_bone_pose_rotation(bone)
		if _last.has(bone) and rot.is_equal_approx(_last[bone]):
			continue
		if holding and hang.has(bone):
			rot = rot.slerp(hang[bone], clampf(hold, 0.0, 1.0))
		if not is_zero_approx(degrees):
			# the body's forward axis (+Z in the rig's own space), in the frame the pose is in:
			# the parent's. The left arm (+X) turns out about it one way, the right the other.
			var parent := sk.get_bone_parent(bone)
			var frame := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
			var axis := (frame.inverse() * Vector3(0, 0, 1)).normalized()
			var turn := deg_to_rad(degrees) * (1.0 if k == 0 else -1.0)
			rot = Quaternion(axis, turn) * rot
		rot = rot.normalized()
		sk.set_bone_pose_rotation(bone, rot)
		_last[bone] = rot


## A forearm taken `hold` of the way back to how it hangs.
func _hold_in(sk: Skeleton3D, bone: int) -> void:
	if bone < 0 or not hang.has(bone):
		return
	var rot := sk.get_bone_pose_rotation(bone)
	if _last.has(bone) and rot.is_equal_approx(_last[bone]):
		return
	var out := rot.slerp(hang[bone], clampf(hold, 0.0, 1.0)).normalized()
	sk.set_bone_pose_rotation(bone, out)
	_last[bone] = out
