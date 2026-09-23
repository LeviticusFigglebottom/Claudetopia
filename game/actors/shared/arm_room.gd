class_name ArmRoom
extends SkeletonModifier3D
## Holds the arms out from a padded or heavy body by `degrees`.
##
## The clips are authored on the default body, and its relaxed Idle hangs the wrists 5 cm
## outside the hip. A gambeson puts 3 cm of padding on the body and 3 cm more on the sleeve, and
## the hands of everyone wearing one hung inside its skirt, out of sight; plate and a brigandine
## did the same, and the heavy body's hips stand 2.5 cm wider on the same skeleton. After the
## clips have posed the skeleton this turns each upper arm out about the body's forward axis,
## so the whole arm hangs clear, in every clip, walking as standing.

var degrees := 0.0
var _bones: Array[int] = []
## what this wrote last, per bone: a pose still equal to it was not re-posed since, and turning
## it again would add the turn up frame after frame while an animation is held
var _last: Dictionary = {}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or is_zero_approx(degrees):
		return
	if _bones.is_empty():
		_bones = [sk.find_bone("UpperArm.L"), sk.find_bone("UpperArm.R")]
	for k in _bones.size():
		var bone: int = _bones[k]
		if bone < 0:
			continue
		var rot := sk.get_bone_pose_rotation(bone)
		if _last.has(bone) and rot.is_equal_approx(_last[bone]):
			continue
		# the body's forward axis (+Z in the rig's own space), in the frame the pose is in: the
		# parent's. The left arm (+X) turns out about it one way, the right the other.
		var parent := sk.get_bone_parent(bone)
		var frame := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var axis := (frame.inverse() * Vector3(0, 0, 1)).normalized()
		var turn := deg_to_rad(degrees) * (1.0 if k == 0 else -1.0)
		var out := (Quaternion(axis, turn) * rot).normalized()
		sk.set_bone_pose_rotation(bone, out)
		_last[bone] = out
