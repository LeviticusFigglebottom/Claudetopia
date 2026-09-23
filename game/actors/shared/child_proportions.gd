class_name ChildProportions
extends SkeletonModifier3D
## Holds a rig at a child's proportions while it plays the grown rig's clips.
##
## A child's skeleton is not a scaled adult's: its hips are at 0.646 m against 0.980, its upper
## arm 192 mm against 292, and its head proportionally larger. The clips are authored on the
## default proportions and retarget by bone-local rotation (CONTRACTS.md §2), but the exporter
## also writes every bone's own translation into every clip, which would stretch a child back
## into a grown body on the first frame. So after the clips have posed the skeleton, this puts
## every bone back where the child's skeleton has it, carries each rotation over as a turn from
## the rest pose rather than an absolute one, scales the hips' travel to the child's height,
## and scales the head to the child's: the head parts are the grown ones, worn on it.
##
## Everything here is read off the two forge skeletons, never typed in.

## bone index -> the child's rest position, rotation and the grown rest rotation it replaces
var _rest_pos: Dictionary = {}
var _rest_rot: Dictionary = {}
var _grown_rot: Dictionary = {}
var _hips := -1
var _head := -1
var _grown_hips := Vector3.ZERO
var _hips_ratio := 1.0
var _head_scale := 1.0
## what this wrote last, per bone: a pose still equal to it was not re-posed since
var _last: Dictionary = {}


## Reads the child's rest pose off `child_skeleton` (the forge's child body) for the bones of
## `grown` (the rig this modifier sits under) and the head scale the child's body is cut for.
func setup(grown: Skeleton3D, child_skeleton: Skeleton3D, head_scale: float) -> void:
	_rest_pos.clear()
	_rest_rot.clear()
	_grown_rot.clear()
	_last.clear()
	for i in grown.get_bone_count():
		var j := child_skeleton.find_bone(grown.get_bone_name(i))
		if j < 0:
			continue
		var child_rest := child_skeleton.get_bone_rest(j)
		_rest_pos[i] = child_rest.origin
		_rest_rot[i] = child_rest.basis.get_rotation_quaternion()
		_grown_rot[i] = grown.get_bone_rest(i).basis.get_rotation_quaternion()
	_hips = grown.find_bone("Hips")
	_head = grown.find_bone("Head")
	if _hips >= 0 and _rest_pos.has(_hips):
		# the hips hang off Root, which stands on the ground: their rest offset is their height
		_grown_hips = grown.get_bone_rest(_hips).origin
		_hips_ratio = (_rest_pos[_hips] as Vector3).length() / maxf(_grown_hips.length(), 0.001)
	_head_scale = head_scale


func hips_ratio() -> float:
	return _hips_ratio


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for i in _rest_pos:
		var bone: int = i
		var pos := sk.get_bone_pose_position(bone)
		var rot := sk.get_bone_pose_rotation(bone)
		var last: Array = _last.get(bone, [])
		if not last.is_empty() and pos.is_equal_approx(last[0]) and rot.is_equal_approx(last[1]):
			continue
		var out_pos: Vector3 = _rest_pos[bone]
		if bone == _hips:
			out_pos = out_pos + (pos - _grown_hips) * _hips_ratio
		var turn: Quaternion = (_grown_rot[bone] as Quaternion).inverse() * rot
		var out_rot: Quaternion = ((_rest_rot[bone] as Quaternion) * turn).normalized()
		sk.set_bone_pose_position(bone, out_pos)
		sk.set_bone_pose_rotation(bone, out_rot)
		_last[bone] = [out_pos, out_rot]
	if _head >= 0:
		sk.set_bone_pose_scale(_head, Vector3.ONE * _head_scale)
