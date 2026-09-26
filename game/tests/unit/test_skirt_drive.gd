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
	for b in ["Skirt.F", "Skirt.B", "Skirt.L", "Skirt.R"]:
		assert_true(_turn(b) < 1.0, "%s at rest with the drive off" % b)
