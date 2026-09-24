extends TestCase
## The planted feet of a standing body (FootPlanter): held where they stand while the body settles
## or turns on the spot, stepped when they have to move, and handed back to the clips when the
## body moves off, leaves the ground, plays a one-shot or is carried away.

const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const FootContact := preload("res://tests/unit/foot_contact.gd")
const DT := 1.0 / 120.0

var _root: Node3D = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	HumanoidModel.plant_feet = true
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null


func _rig_built() -> bool:
	return ResourceLoader.exists(HumanoidModel.RIG_PATH)


func _model() -> HumanoidModel:
	_root = Node3D.new()
	_tree().root.add_child(_root)
	var m := (load(MODEL_SCENE) as PackedScene).instantiate() as HumanoidModel
	_root.add_child(m)
	m.anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return m


func _tick(m: HumanoidModel, v: Vector2 = Vector2.ZERO) -> void:
	m.set_locomotion(v)
	m._process(DT)


## The heel and ball of each foot, in the world (FootContact).
func _soles(m: HumanoidModel) -> Dictionary:
	return FootContact.soles(m.skeleton, m.skeleton.global_transform)


## How far the points of the feet that were on the ground in both `a` and `b` slid (m).
func _slid(m: HumanoidModel, a: Dictionary, b: Dictionary) -> float:
	return FootContact.slid(m.skeleton, _root.global_position.y, a, b)


## The turn (rad) of each foot about the vertical, against the body's.
func _foot_turns(m: HumanoidModel) -> Array[float]:
	var sk := m.skeleton
	var body := sk.global_transform.basis.get_euler().y
	var out: Array[float] = []
	for side in ["L", "R"]:
		var ahead := sk.global_transform.basis * (sk.get_bone_global_pose(sk.find_bone("Toe." + side)).origin
				- sk.get_bone_global_pose(sk.find_bone("Foot." + side)).origin)
		var yaw := atan2(ahead.x, ahead.z)
		out.append(absf(wrapf(yaw - body, -PI, PI)))
	return out


## A body turning slowly on the spot, as a villager turns to face someone, steps round on its
## feet: no foot slides on the ground, and the feet never lag the body by more than the turn it
## steps at. (Faster than HumanoidModel.TURN_FROM, the turn clips have the feet.)
func test_turning_on_the_spot_steps_round() -> void:
	if not _rig_built():
		return
	var m := _model()
	for i in 60:
		_tick(m)
	var planter := m.foot_planter()
	assert_true(planter != null and planter.is_planted(), "a standing body has its feet planted")
	var rest_turns := _foot_turns(m)
	var slid := 0.0
	var worst := 0.0
	var last := _soles(m)
	# 90 degrees over 3 s (30 degrees a second), then half a second to settle
	for i in 420:
		if i < 360:
			_root.rotate_y(deg_to_rad(90.0) / 360.0)
		_tick(m)
		var now := _soles(m)
		slid += _slid(m, last, now)
		last = now
		var turns := _foot_turns(m)
		for s in 2:
			worst = maxf(worst, absf(turns[s] - rest_turns[s]))
	print("    turning 90 degrees on the spot over 3 s: %d steps, the feet slid %.1f cm, a foot lagged the body %.0f degrees at most" % [
			planter.steps, slid * 100.0, rad_to_deg(worst)])
	assert_true(planter.steps >= 2, "turning 90 degrees the feet took %d steps" % planter.steps)
	assert_true(slid < 0.01, "turning on the spot the feet slid %.1f cm on the ground" % (slid * 100.0))
	assert_true(worst < FootPlanter.RETURN_FROM + deg_to_rad(8.0), "a foot lagged the body %.0f degrees" % rad_to_deg(worst))


## Moving off hands the feet back to the clips within RELEASE_S, and the gait takes them.
func test_moving_off_lets_the_feet_go() -> void:
	if not _rig_built():
		return
	var m := _model()
	for i in 60:
		_tick(m)
	assert_true(m.foot_planter().is_planted(), "standing, the feet are planted")
	var ticks := 0
	while m.foot_planter().is_planted() and ticks < 60:
		_tick(m, Vector2(0.0, Player.WALK_SPEED))
		_root.position.z += Player.WALK_SPEED * DT
		ticks += 1
	print("    moving off, the clips had the feet back after %.2f s" % (ticks * DT))
	assert_true(ticks * DT <= FootPlanter.RELEASE_S + 2.0 * DT, "moving off, the feet were held %.2f s" % (ticks * DT))


## A one-shot has the feet to itself, and when it ends with the body standing, the feet are
## planted where it left them and step back into the stance without sliding.
func test_a_one_shot_has_the_feet_and_they_step_back_after_it() -> void:
	if not _rig_built():
		return
	var m := _model()
	for i in 60:
		_tick(m)
	var clip := "Attack_1H_Light_1"
	if not m.has_clip(clip):
		return
	assert_true(m.play_intent(clip), "the attack plays")
	for i in int(ceil(FootPlanter.RELEASE_S / DT)) + 1:
		_tick(m)
	assert_false(m.foot_planter().is_planted(), "a one-shot has the feet to itself")
	var ticks := 0
	while m.current_intent() != "" and ticks < 600:
		_tick(m)
		ticks += 1
	assert_true(m.foot_planter().is_planted(), "the one-shot over, the feet are planted where it left them")
	var slid := 0.0
	var last := _soles(m)
	for i in 120:
		_tick(m)
		var now := _soles(m)
		slid += _slid(m, last, now)
		last = now
	var left := 0.0
	for off in m.foot_planter().offsets():
		left = maxf(left, off)
	print("    after %s: %d steps back into the stance, the feet slid %.1f cm, a foot left %.1f cm from its place" % [
			clip, m.foot_planter().steps, slid * 100.0, left * 100.0])
	assert_true(slid < 0.01, "after the attack the feet slid %.1f cm back into the stance" % (slid * 100.0))
	assert_true(left <= FootPlanter.STEP_FROM + 0.005, "after the attack a foot was left %.1f cm from its place" % (left * 100.0))


## A body carried off (a teleport) does not drag its legs after it: the feet are the clips' again
## on the same frame, and planted there.
func test_a_teleport_does_not_drag_the_legs() -> void:
	if not _rig_built():
		return
	var m := _model()
	for i in 60:
		_tick(m)
	_root.position += Vector3(40.0, 0.0, -25.0)
	_tick(m)
	var left := 0.0
	for off in m.foot_planter().offsets():
		left = maxf(left, off)
	assert_true(left < 0.005, "after a teleport a foot was shown %.2f m from where the clips put it" % left)
	assert_true(m.foot_planter().is_planted(), "after a teleport the feet are planted where the body landed")


## Leaving the ground lets the feet go on the frame the body rises.
func test_a_jump_lets_the_feet_go() -> void:
	if not _rig_built():
		return
	var m := _model()
	for i in 60:
		_tick(m)
	_root.position.y += 4.0 * DT
	_tick(m)
	assert_false(m.foot_planter().is_planted(), "rising at 4 m/s, the feet were still held")


## Off, the planter leaves the pose alone: the clips' feet are the feet shown.
func test_off_it_leaves_the_clips_alone() -> void:
	if not _rig_built():
		return
	HumanoidModel.plant_feet = false
	var m := _model()
	for i in 30:
		_tick(m, Vector2(0.0, Player.JOG_SPEED))
		_root.position.z += Player.JOG_SPEED * DT
	for i in 60:
		_tick(m)
	assert_false(m.foot_planter().is_planted(), "switched off, the planter held the feet")
