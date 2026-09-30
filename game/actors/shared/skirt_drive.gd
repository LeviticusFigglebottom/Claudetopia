class_name SkirtDrive
extends SkeletonModifier3D
## Poses a skirt's bones from the thighs, after the clips (rig.CLOTH_BONES in the forge).
##
## A skirt weighted to the two thighs alone is at best half of each at the front: in a run the
## raised knee stood in front of the cloth and a long skirt stretched between the legs into a sheet.
## Here the front panel (Skirt.F) swings with whichever thigh is ahead and the back (Skirt.B) with
## whichever is behind, each side (Skirt.L, Skirt.R) with its own thigh, and below the knee the
## front and the sides (Skirt.F2, L2, R2) fall back from a raised knee while the back (Skirt.B2)
## lifts with a heel kicked up behind. No clip keys these bones. tools/forge/preview/clipcheck.py
## poses them the same way in numpy (Rig._skirt_drive): change both together.
##
## `amount` is how much of that is laid on: 1 walking and running, 0 when the thighs are no guide to
## where the cloth hangs -- swimming (prone, the legs trailing) and seated in the saddle (the thighs
## round the barrel): the skirt then follows the hips alone. HumanoidModel eases it.
## `lag` (seconds, 0 off) lets the panels trail the thighs a little; off everywhere by default.

var amount := 1.0
var lag := 0.0

const SMOOTH := 0.18        ## rad over which the front and back hand over between the thighs
const SIDE_SHARE := 1.0     ## of a thigh's swing that the panel beside it takes
const SIDE_SPREAD := 0.80   ## of a thigh's spread out to the side that the panel beside it takes
const FALL_BACK := 0.60     ## of a panel's forward swing the cloth below the knee gives back
const HEEL_LIFT := 0.80     ## of the trailing knee's bend the back below the knee takes
const SIDE_HEEL := 0.55     ## of its own knee's bend a side below the knee takes, its leg behind
const HEEL_MAX := 1.0       ## rad: the most a heel lifts the cloth below the knee (a roll folds the
                            ## knees shut, and the lower back stood out behind the feet as a fin)

var _ids: Dictionary = {}
var _ok := false
var _rest_pitch := {"L": 0.0, "R": 0.0}
var _rest_ab := {"L": 0.0, "R": 0.0}
var _now: Dictionary = {}   ## bone -> Vector2(pitch, abduction) laid on last frame, for the lag


func _setup(sk: Skeleton3D) -> void:
	_ids.clear()
	for n in ["Hips", "UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R", "Foot.L", "Foot.R",
			"Skirt.F", "Skirt.B", "Skirt.L", "Skirt.R", "Skirt.F2", "Skirt.B2", "Skirt.L2", "Skirt.R2"]:
		_ids[n] = sk.find_bone(n)
	_ok = true
	for n in _ids:
		if int(_ids[n]) < 0:
			_ok = false
	if not _ok:
		return
	for side in ["L", "R"]:
		var d := _thigh_dir(sk, side, true)
		_rest_pitch[side] = _pitch(d)
		_rest_ab[side] = _abduction(d, side)


## True when the skeleton has the skirt's bones (a rig built before them has none).
func has_skirt_bones() -> bool:
	var sk := get_skeleton()
	if sk != null and _ids.is_empty():
		_setup(sk)
	return _ok


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _ids.is_empty():
		_setup(sk)
	if not _ok:
		return
	var a := clampf(amount, 0.0, 1.0)
	var hips := int(_ids["Hips"])
	var hips_pose := sk.get_bone_global_pose(hips).basis.get_rotation_quaternion()
	# the body's frame: the skeleton's axes (+X left, +Y up, +Z ahead) carried by the hips' turn
	_body = hips_pose * sk.get_bone_global_rest(hips).basis.get_rotation_quaternion().inverse()
	var p := {}
	var ab := {}
	for side in ["L", "R"]:
		var d := _thigh_dir(sk, side, false)
		p[side] = (_pitch(d) - float(_rest_pitch[side])) * a
		ab[side] = (_abduction(d, side) - float(_rest_ab[side])) * a
	var front := maxf(_smax(float(p["L"]), float(p["R"]), SMOOTH), 0.0)
	var back := minf(-_smax(-float(p["L"]), -float(p["R"]), SMOOTH), 0.0)
	# the back below the knee: the bend of the knee of the leg that is behind
	var trailing := "L" if float(p["L"]) < float(p["R"]) else "R"
	var heel := _knee_bend(sk, trailing) * a
	var g_f := _pose_panel(sk, "Skirt.F", front, 0.0, hips_pose)
	var g_b := _pose_panel(sk, "Skirt.B", back, 0.0, hips_pose)
	for side in ["L", "R"]:
		var sp := float(p[side]) * SIDE_SHARE
		var spread := float(ab[side]) * SIDE_SPREAD
		var g_s := _pose_panel(sk, "Skirt." + side, sp, spread, hips_pose)
		# below the knee: falls back from a raised knee, lifts a little with a heel behind
		var behind := clampf(-sp / 0.3, 0.0, 1.0)
		var low := maxf(sp, 0.0) * (1.0 - FALL_BACK) + minf(sp, 0.0) \
				- minf(_knee_bend(sk, side) * a * SIDE_HEEL, HEEL_MAX) * behind
		_pose_panel(sk, "Skirt.%s2" % side, low, spread, g_s)
	# below the knee each panel is turned in the body's frame, hung from the one above it
	_pose_panel(sk, "Skirt.F2", front * (1.0 - FALL_BACK), 0.0, g_f)
	_pose_panel(sk, "Skirt.B2", back - minf(heel * HEEL_LIFT, HEEL_MAX), 0.0, g_b)


var _body := Quaternion.IDENTITY


## The thigh's direction (hip to knee) in the body's frame, posed (or at rest).
func _thigh_dir(sk: Skeleton3D, side: String, rest: bool) -> Vector3:
	var up := int(_ids["UpperLeg." + side])
	var lo := int(_ids["LowerLeg." + side])
	if rest:
		return (sk.get_bone_global_rest(lo).origin - sk.get_bone_global_rest(up).origin).normalized()
	var v := sk.get_bone_global_pose(lo).origin - sk.get_bone_global_pose(up).origin
	return (_body.inverse() * v).normalized()


## Forward swing about the body's left-right axis, radians, + ahead (+Z is ahead in the rig).
static func _pitch(d: Vector3) -> float:
	return atan2(d.z, -d.y)


## Out to the side, radians, + away from the body's midline: the angle out of the plane the thigh
## swings in. (As atan2 of the side over the drop it ran to 90 degrees as a thigh came up level in
## a sprint, and past it in a roll, and the side panels stood out as boards.)
static func _abduction(d: Vector3, side: String) -> float:
	return asin(clampf(d.x * (1.0 if side == "L" else -1.0), -1.0, 1.0))


## How far the knee is bent, radians: the angle between thigh and shin.
func _knee_bend(sk: Skeleton3D, side: String) -> float:
	var a := sk.get_bone_global_pose(int(_ids["UpperLeg." + side])).origin
	var b := sk.get_bone_global_pose(int(_ids["LowerLeg." + side])).origin
	var c := sk.get_bone_global_pose(int(_ids["Foot." + side])).origin
	var t := (b - a).normalized()
	var s := (c - b).normalized()
	return acos(clampf(t.dot(s), -1.0, 1.0))


## A soft maximum: the larger, eased into the other over `k` where they are close. Never more than
## the larger (with the usual bump, two thighs at rest set the front 2.6 degrees out).
static func _smax(x: float, y: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (x - y) / k, 0.0, 1.0)
	return lerpf(y, x, h)


## A skirt bone turned from its rest by `pitch` about the body's left-right axis (+ ahead) and
## `ab` out to its side, in the body's frame; its pose is that turn taken into its parent's frame
## (`parent`, the parent's posed rotation in the skeleton's space). Returns the bone's own posed
## rotation in the skeleton's space, for a bone hanging below it.
func _pose_panel(sk: Skeleton3D, bone: String, pitch: float, ab: float, parent: Quaternion) -> Quaternion:
	var id := int(_ids[bone])
	var target := Vector2(pitch, ab)
	if lag > 0.0 and _now.has(bone):
		var dt := get_process_delta_time() if is_inside_tree() else 0.0
		var k := 1.0 - exp(-dt / maxf(lag, 1e-3))
		target = (_now[bone] as Vector2).lerp(target, k)
	_now[bone] = target
	var side_sign := -1.0 if bone.ends_with(".R") or bone.ends_with(".R2") else 1.0
	# about +X by -pitch swings a hanging bone toward +Z (ahead); about +Z by +ab toward +X (left)
	var turn := Quaternion(Vector3.RIGHT, -target.x) * Quaternion(Vector3.BACK, target.y * side_sign)
	var rest := sk.get_bone_global_rest(id).basis.get_rotation_quaternion()
	var g := (_body * turn * rest).normalized()
	sk.set_bone_pose_rotation(id, (parent.inverse() * g).normalized())
	return g
