extends TestCase
## The locomotion graph as the eye meets it: the model is told the body's ground velocity in m/s
## and has to keep its planted feet planted, keep its gaits in step with each other while it
## blends them, stand on the idle, and crouch only when it sneaks.
##
## Measured on the first graph (one 2D blend space fed velocity / 6.5): at the default 4.2 m/s the
## planted foot moved at 3.32 m/s (79% of the ground) with the hips 15.2 cm below standing; the
## sprint played the Walk clip and slid at 76%; a villager walking at 2.2 m/s stood in its idle.

const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"
const NPC_SCENE := "res://actors/npc/npc.tscn"
const DT := 1.0 / 120.0

var _root: Node3D = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null


func _rig_built() -> bool:
	return ResourceLoader.exists(HumanoidModel.RIG_PATH)


## A model under a root that is walked through the world at `v` (the model's frame: x right, y
## ahead), stepped by hand at 120 Hz. Returns the model; `_root` carries it.
func _model() -> HumanoidModel:
	_root = Node3D.new()
	_tree().root.add_child(_root)
	var m := (load(MODEL_SCENE) as PackedScene).instantiate() as HumanoidModel
	_root.add_child(m)
	m.anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return m


## One tick: the model is told the velocity and steps its own tree (`_process` advances it by
## hand, on the combat clock), and the root is carried along the ground by the same amount.
func _step(m: HumanoidModel, v: Vector2, sneaking: bool, travelled: Vector2) -> Vector2:
	m.set_locomotion(v, sneaking)
	# the model advances its own tree in _process (manual mode, on the combat clock), so the test
	# must not advance it again: a second advance plays every gait at twice its rate, and the
	# planted foot slides backwards at exactly the ground speed
	m._process(DT)
	var next := travelled + v * DT
	# the model faces +Z, so its right is -X
	_root.position = Vector3(-next.x, 0.0, next.y)
	return next


## [median planted-foot ground speed m/s, mean hips below standing m, hips peak to peak m] over
## four seconds at `v`.
func _walk(m: HumanoidModel, v: Vector2, sneaking: bool) -> Array:
	var sk := m.skeleton
	var hips_rest := sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y
	var travelled := Vector2.ZERO
	for i in 240:
		travelled = _step(m, v, sneaking, travelled)
	var feet := {"L": [], "R": []}
	var hips := 0.0
	var hips_lo := 99.0
	var hips_hi := -99.0
	var n := 480
	for i in n:
		travelled = _step(m, v, sneaking, travelled)
		var xf := _root.global_transform * sk.transform
		var hy := (xf * sk.get_bone_global_pose(sk.find_bone("Hips")).origin).y
		hips += hy / n
		hips_lo = minf(hips_lo, hy)
		hips_hi = maxf(hips_hi, hy)
		for side in ["L", "R"]:
			feet[side].append(xf * sk.get_bone_global_pose(sk.find_bone("Foot." + side)).origin)
	var slides: Array[float] = []
	for side in ["L", "R"]:
		var arr: Array = feet[side]
		var lo := 99.0
		for p in arr:
			lo = minf(lo, (p as Vector3).y)
		for i in range(1, arr.size()):
			var a: Vector3 = arr[i - 1]
			var b: Vector3 = arr[i]
			if a.y < lo + 0.015 and b.y < lo + 0.015:
				slides.append(Vector2(b.x - a.x, b.z - a.z).length() / DT)
	slides.sort()
	var median := slides[slides.size() / 2] if not slides.is_empty() else 99.0
	return [median, hips_rest - hips, hips_hi - hips_lo]


## The planted foot stands still under the gaits the game moves at, and under the blends between
## them. The threshold is 5% of the ground speed at a gait and 8% in a blend.
func test_the_planted_foot_stays_planted() -> void:
	if not _rig_built():
		return
	var cases := [
		["walk", Vector2(0.0, Player.WALK_SPEED), false, 0.05],
		["brisk walk", Vector2(0.0, 2.4), false, 0.08],
		["walk to jog", Vector2(0.0, 3.4), false, 0.08],
		["jog", Vector2(0.0, Player.JOG_SPEED), false, 0.05],
		["jog to sprint", Vector2(0.0, 6.4), false, 0.08],
		["sprint", Vector2(0.0, Player.SPRINT_SPEED), false, 0.05],
		["sneak", Vector2(0.0, Player.SNEAK_SPEED), true, 0.05],
		["villager", Vector2(0.0, 2.2), false, 0.08],
		["strafe right", Vector2(Player.LOCKED_SIDE, 0.0), false, 0.08],
		["backpedal, locked on", Vector2(0.0, -Player.LOCKED_BACK), false, 0.08],
		["backpedal", Vector2(0.0, -1.5), false, 0.08],
	]
	var report: Array[String] = []
	for c in cases:
		var m := _model()
		var got: Array = _walk(m, c[1], c[2])
		var ground := (c[1] as Vector2).length()
		var share := float(got[0]) / ground
		report.append("%s %.0f%%" % [c[0], share * 100.0])
		assert_true(share < float(c[3]), "%s at %.1f m/s: the planted foot moves at %.2f m/s (%.0f%% of the ground)" % [
			c[0], ground, float(got[0]), share * 100.0])
		after_each()
	print("    planted-foot speed as a share of ground speed: %s" % ", ".join(report))


## The moving clips share one stride timeline and every blend keeps its silent inputs running,
## so whatever the weights, every gait is at the same phase: the walk's left foot is down when
## the run's is. Read from the tree's own playback positions, not inferred from a pose.
func test_the_gaits_stay_in_step_while_they_blend() -> void:
	if not _rig_built():
		return
	var m := _model()
	var travelled := Vector2.ZERO
	# walk, speed up through the jog to a sprint, turn to a strafe, and back down
	var plan := [Vector2(0.0, 1.8), Vector2(0.0, 3.4), Vector2(0.0, 5.0), Vector2(0.0, 7.8), Vector2(2.0, 1.0), Vector2(0.0, -1.2)]
	var worst := 0.0
	var paths: Array[String] = []
	for point in m._gait_points:
		paths.append("gait/%s" % str(point[2]))
	paths.append_array(["sneak_walk", "back", "strafe_l", "strafe_r"])
	for v in plan:
		for i in 90:
			travelled = _step(m, v, false, travelled)
			var first := float(m.anim_tree.get("parameters/%s/%s/current_position" % [HumanoidModel.LOCOMOTION_STATE, paths[0]]))
			for p in paths:
				var at := float(m.anim_tree.get("parameters/%s/%s/current_position" % [HumanoidModel.LOCOMOTION_STATE, p]))
				var d := absf(at - first)
				worst = maxf(worst, minf(d, 1.0 - d))
	assert_true(worst < 0.001, "two gaits drifted %.4f of a stride apart while blending" % worst)


## Standing is the idle (the hips where they stand), a jog is not a crouch, and a sneak is.
func test_standing_is_idle_and_only_a_sneak_crouches() -> void:
	if not _rig_built():
		return
	var stand: Array = _walk(_model(), Vector2.ZERO, false)
	after_each()
	var walk: Array = _walk(_model(), Vector2(0.0, Player.SNEAK_SPEED), false)
	after_each()
	var sneak: Array = _walk(_model(), Vector2(0.0, Player.SNEAK_SPEED), true)
	print("    hips below standing: standing %.1f cm, walking at the sneak speed %.1f cm, sneaking %.1f cm" % [
		float(stand[1]) * 100.0, float(walk[1]) * 100.0, float(sneak[1]) * 100.0])
	assert_true(absf(float(stand[1])) < 0.01, "standing still, the hips are %.1f cm off standing" % (float(stand[1]) * 100.0))
	assert_true(float(walk[1]) < 0.07, "walking upright, the hips are %.1f cm low: a crouch has leaked into the walk" % (float(walk[1]) * 100.0))
	assert_true(float(sneak[1]) > 0.14, "sneaking, the hips are only %.1f cm low" % (float(sneak[1]) * 100.0))


## The gaits stand up. Each is played at the speed it was made for, so what the eye meets is the
## clip itself: the hips ride a few centimetres below standing and rise and fall a few more with
## each step. The first Walk sank 13.5 cm at every contact and the first Run 25.2 cm, which is
## what read as a crouch-walk.
func test_the_gaits_stand_up() -> void:
	if not _rig_built():
		return
	var report: Array[String] = []
	for c in [["walk", Player.WALK_SPEED], ["jog", Player.JOG_SPEED], ["sprint", Player.SPRINT_SPEED]]:
		var got: Array = _walk(_model(), Vector2(0.0, float(c[1])), false)
		after_each()
		var low := float(got[1]) * 100.0
		var swing := float(got[2]) * 100.0
		report.append("%s %.1f cm low, %.1f cm peak to peak" % [c[0], low, swing])
		assert_true(low < 6.0, "at a %s the hips ride %.1f cm below standing: a crouch" % [c[0], low])
		assert_true(swing < 8.0, "at a %s the hips rise and fall %.1f cm with each step" % [c[0], swing])
	print("    hips: %s" % "; ".join(report))


## A stop. The body comes down from a jog at the player's own deceleration (20 m/s², a quarter
## of a second). While it is still moving, a foot on the ground keeps pace with the ground, as it
## does at any speed; once it stands, the legs stop stepping and settle into the idle. Before,
## the stride was timed off a speed smoothed over 0.08 s, which under that deceleration runs up
## to 1.6 m/s ahead of the body, and it kept stepping at half pace after the body had stopped.
func test_a_stop_stops_the_legs() -> void:
	if not _rig_built():
		return
	var m := _model()
	var sk := m.skeleton
	var travelled := Vector2.ZERO
	for i in 240:
		travelled = _step(m, Vector2(0.0, Player.JOG_SPEED), false, travelled)
	var speed := Player.JOG_SPEED
	var moving_skate := 0.0
	var settle_skate := 0.0
	var steps_after := 0.0
	var phase_path := "parameters/%s/gait/%s/current_position" % [HumanoidModel.LOCOMOTION_STATE, str(m._gait_points[0][2])]
	var last_phase := float(m.anim_tree.get(phase_path))
	var last := {}
	var lowest := {"L": 99.0, "R": 99.0}
	var samples: Array = []
	for i in 96:
		speed = maxf(speed - Player.DECEL * DT, 0.0)
		travelled = _step(m, Vector2(0.0, speed), false, travelled)
		var xf := _root.global_transform * sk.transform
		var feet := {"moving": speed > 0.0}
		for side in ["L", "R"]:
			var p: Vector3 = xf * sk.get_bone_global_pose(sk.find_bone("Foot." + side)).origin
			feet[side] = p
			lowest[side] = minf(float(lowest[side]), p.y)
		samples.append(feet)
		var phase := float(m.anim_tree.get(phase_path))
		if speed <= 0.0:
			steps_after += fposmod(phase - last_phase, 1.0)
		last_phase = phase
	for i in range(1, samples.size()):
		for side in ["L", "R"]:
			var a: Vector3 = samples[i - 1][side]
			var b: Vector3 = samples[i][side]
			if a.y < float(lowest[side]) + 0.02 and b.y < float(lowest[side]) + 0.02:
				var d := Vector2(b.x - a.x, b.z - a.z).length()
				if bool(samples[i]["moving"]):
					moving_skate += d
				else:
					settle_skate += d
	print("    a stop from a jog: planted feet skated %.1f cm while the body moved, the legs stepped %.2f of a stride after it stood, and the feet settled %.1f cm into the idle" % [
		moving_skate * 100.0, steps_after, settle_skate * 100.0])
	assert_true(moving_skate < 0.03, "stopping, a planted foot skated %.1f cm while the body was still moving" % (moving_skate * 100.0))
	assert_true(steps_after < 0.05, "the legs went on stepping %.2f of a stride after the body stood" % steps_after)


## A raised guard walks on its legs. The guard is held over the upper body while the legs go on
## walking under it; played as a whole-body state it froze the legs in its stance, and a player
## walking behind a shield at 1.56 m/s glided with still feet.
func test_a_raised_guard_walks_on_its_legs() -> void:
	if not _rig_built():
		return
	var m := _model()
	var pace := Player.STRAFE_SPEED * Player.BLOCK_MOVE_MULT
	var sk := m.skeleton
	var open: Array = _walk(m, Vector2(0.0, pace), false)
	var hand_open := (sk.get_bone_global_pose(sk.find_bone("Hand.R")).origin - sk.get_bone_global_pose(sk.find_bone("Chest")).origin).y
	after_each()
	m = _model()
	sk = m.skeleton
	assert_true(m.play_intent("Block_Idle"), "the rig has no guard")
	var guarded: Array = _walk(m, Vector2(0.0, pace), false)
	var hand_guard := (sk.get_bone_global_pose(sk.find_bone("Hand.R")).origin - sk.get_bone_global_pose(sk.find_bone("Chest")).origin).y
	var share := float(guarded[0]) / pace
	print("    walking at %.2f m/s: planted foot %.0f%% of the ground with the guard up (%.0f%% without); the right hand %.2f m from the chest's height with it, %.2f without" % [
		pace, share * 100.0, float(open[0]) / pace * 100.0, hand_guard, hand_open])
	assert_eq(m.current_stance(), "Block_Idle", "the guard is not held")
	assert_eq(m.anim_tree.get("parameters/playback").get_current_node(), HumanoidModel.LOCOMOTION_STATE,
			"the guard took the whole body out of the walk")
	assert_true(share < 0.08, "with the guard up the planted foot moves at %.0f%% of the ground: the legs are not walking" % (share * 100.0))
	assert_true(hand_guard > hand_open + 0.2, "the hands are not up in the guard (%.2f against %.2f)" % [hand_guard, hand_open])
	m.stop_intent()
	for i in 30:
		_step(m, Vector2(0.0, pace), false, Vector2.ZERO)
	var hand_down := (sk.get_bone_global_pose(sk.find_bone("Hand.R")).origin - sk.get_bone_global_pose(sk.find_bone("Chest")).origin).y
	assert_eq(m.current_stance(), "", "the guard stayed up")
	assert_true(hand_down < hand_guard - 0.2, "lowered, the hands stayed up (%.2f)" % hand_down)


## A villager on its way somewhere walks: its model is told how fast (it used to stay at 0, so the
## whole village glided about in its idle pose).
func test_a_walking_villager_is_given_its_gait() -> void:
	if not _rig_built():
		return
	var ids := ContentDB.ids_of("npc")
	if ids.is_empty():
		return
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	_root = Node3D.new()
	_tree().root.add_child(_root)
	_root.add_child(floor_body)
	var npc := (load(NPC_SCENE) as PackedScene).instantiate()
	npc.set("npc_id", str(ids[0]))
	_root.add_child(npc)
	(npc as Node3D).global_position = Vector3(0.0, 0.05, 0.0)
	npc.set("target_position", Vector3(0.0, 0.0, -40.0))
	npc.set("has_target", true)
	for i in 40:
		await _tree().physics_frame
	var models := npc.find_children("*", "HumanoidModel", true, false)
	assert_false(models.is_empty(), "the villager has no forge body")
	if models.is_empty():
		return
	var hm := models[0] as HumanoidModel
	var v: Vector3 = npc.get("velocity")
	var told: Vector2 = hm._locomotion
	assert_gt(Vector2(v.x, v.z).length(), 1.0, "the villager should be walking")
	assert_near(told.y, Vector2(v.x, v.z).length(), 0.05, "the model is told the speed the villager walks at")
	var moving := float(hm.locomotion_params(told, 0.0)["move/blend_amount"])
	assert_near(moving, 1.0, 0.001, "at %.1f m/s it is all gait and no idle" % told.y)
