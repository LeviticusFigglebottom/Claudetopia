extends TestCase
## SkirtDrive: a skirt's bones follow the thighs walking and running, and stand at rest (the skirt
## following the hips alone) while the body swims or sits a horse. Skips on a rig built before the
## skirt's bones (rig.CLOTH_BONES).

const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"

var _root: Node
var _m: HumanoidModel


func before_each() -> void:
	_root = Node3D.new()
	Engine.get_main_loop().root.add_child(_root)
	_m = (load(MODEL_SCENE) as PackedScene).instantiate() as HumanoidModel
	_root.add_child(_m)


func after_each() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null
	_m = null


func _ready_or_skip() -> bool:
	if _m == null or _m.skirt_drive == null or not _m.skirt_drive.has_skirt_bones():
		skip("the rig has no skirt bones yet (rebuild it with rig.CLOTH_BONES)")
		return false
	return true


## How far a skirt bone is turned from its rest, degrees.
func _turn(bone: String) -> float:
	var sk := _m.skeleton
	var id := sk.find_bone(bone)
	var rest := sk.get_bone_rest(id).basis.get_rotation_quaternion()
	var pose := sk.get_bone_pose_rotation(id)
	return rad_to_deg(rest.angle_to(pose))


func test_the_front_follows_the_forward_thigh_in_a_run() -> void:
	if not _ready_or_skip():
		return
	_m.skirt_drive.amount = 1.0
	_m.skeleton.reset_bone_poses()
	var sk := _m.skeleton
	# the left thigh forward 50 degrees, as a run's reaching leg: the front panel goes with it
	var up := sk.find_bone("UpperLeg.L")
	var q := sk.get_bone_rest(up).basis.get_rotation_quaternion()
	var ahead := Quaternion(Vector3.RIGHT, deg_to_rad(-50.0))
	var parent := sk.get_bone_global_rest(sk.get_bone_parent(up)).basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(up, (parent.inverse() * ahead * parent * q).normalized())
	sk.force_update_all_bone_transforms()
	_m.skirt_drive._process_modification()
	assert_gt(_turn("Skirt.F"), 30.0, "the front panel swings with the thigh ahead")
	assert_true(_turn("Skirt.B") < 5.0, "the back stays with the thigh that did not go back")


## Lays the left thigh `deg` degrees forward of its rest, about the body's left-right axis.
func _raise_left_thigh(deg: float) -> void:
	var sk := _m.skeleton
	sk.reset_bone_poses()
	var up := sk.find_bone("UpperLeg.L")
	var q := sk.get_bone_rest(up).basis.get_rotation_quaternion()
	var ahead := Quaternion(Vector3.RIGHT, deg_to_rad(-deg))
	var parent := sk.get_bone_global_rest(sk.get_bone_parent(up)).basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(up, (parent.inverse() * ahead * parent * q).normalized())
	sk.force_update_all_bone_transforms()
	_m.skirt_drive.amount = 1.0
	_m.skirt_drive._process_modification()


## Where a skirt bone points (head to tail) in the skeleton's space, posed.
func _dir(bone: String) -> Vector3:
	var sk := _m.skeleton
	var id := sk.find_bone(bone)
	var g := sk.get_bone_global_pose(id)
	return (g.basis * Vector3.UP).normalized()


func test_a_thigh_raised_level_does_not_turn_its_side_out() -> void:
	if not _ready_or_skip():
		return
	# a sprint's knee lift: the side panel swings forward with the thigh and stays beside it (it
	# stood out sideways as a board when the spread was read as the side over the drop)
	_raise_left_thigh(85.0)
	var d := _dir("Skirt.L")
	assert_gt(d.z, 0.8, "the side swings forward with the thigh")
	assert_true(absf(d.x) < 0.35, "and does not turn out to the side (x %.2f)" % d.x)


func test_below_the_knee_the_front_and_side_fall_back() -> void:
	if not _ready_or_skip():
		return
	_raise_left_thigh(70.0)
	assert_gt(_turn("Skirt.L"), 50.0, "the side above the knee goes with the thigh")
	for pair in [["Skirt.F", "Skirt.F2"], ["Skirt.L", "Skirt.L2"]]:
		var upper := _dir(pair[0])
		var lower := _dir(pair[1])
		assert_true(lower.z < upper.z - 0.2, "%s hangs down more than %s from a raised knee" % [pair[1], pair[0]])


func test_swimming_and_the_saddle_ease_it_off() -> void:
	if not _ready_or_skip():
		return
	_m.set_swimming(true)
	if _m.is_swimming():
		assert_eq(_m.skirt_amount_now(), 0.0, "swimming: the skirt follows the hips")
	_m.set_swimming(false)
	assert_eq(_m.skirt_amount_now(), 1.0, "on foot: the skirt follows the thighs")
	var seat := RideSeat.new()
	seat.name = "RideSeat"
	_m.skeleton.add_child(seat)
	seat.amount = 1.0
	assert_eq(_m.skirt_amount_now(), 0.0, "astride the RideSeat: the skirt follows the hips")
	seat.amount = 0.0
	if _m.has_clip("Ride"):
		_m.play_intent("Ride", 0.0)
		assert_eq(_m.skirt_amount_now(), 0.0, "in the Ride clip: the skirt follows the hips")
	# at amount 0 the skirt's bones stand at rest whatever the thighs do
	_m.skirt_drive.amount = 0.0
	_m.skirt_drive._process_modification()
	for b in ["Skirt.F", "Skirt.B", "Skirt.L", "Skirt.R", "Skirt.F2", "Skirt.B2", "Skirt.L2", "Skirt.R2"]:
		assert_true(_turn(b) < 1.0, "%s at rest with the drive off" % b)


## A coat over a long skirt is the coat cut to hang from the skirt's bones (as the skirt under it
## does); over trousers it is the plain coat, on the legs (HumanoidModel.OVER_SKIRT).
func test_a_coat_is_cut_for_what_is_worn_under_it() -> void:
	if not _ready_or_skip():
		return
	if not ResourceLoader.exists("res://assets/models/characters/clothing/coat_skirt/coat_skirt.glb"):
		skip("coat_skirt not built")
		return
	_m.apply_appearance({"feminine": 1.0, "parts": {"torso": "coat", "legs": "long_skirt", "feet": "shoes"}})
	var mi := _m.worn_mesh("torso")
	assert_true(mi != null, "a coat is worn")
	if mi != null:
		assert_eq(str(mi.get_meta("part", "")), "coat_skirt", "over a long skirt: the skirt-boned coat")
	_m.apply_appearance({"parts": {"torso": "coat", "legs": "trousers", "feet": "shoes"}})
	mi = _m.worn_mesh("torso")
	if mi != null:
		assert_eq(str(mi.get_meta("part", "")), "coat", "over trousers: the plain coat")
