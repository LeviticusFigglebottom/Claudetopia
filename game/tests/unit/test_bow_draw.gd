extends TestCase
## The bow, drawn and loosed on the player's real body (triage 55):
##   * the draw is the upper body's (HumanoidModel.STANCE_CLIPS): the legs walk under it;
##   * a draw after a loose plays from its start, as a heavy does (test_clips_play_again);
##   * the arrow is in the draw hand from the quiver to the loose, the string follows the hand, the
##     limbs bend with the pull and spring back;
##   * the body turns up to an aim above it;
##   * the crosshair is up while the bow is drawn, closes as the draw comes to full, marks a body
##     under it, and goes when the arrow is loosed; the HUD draws it;
##   * the arrow goes where the crosshair is, near and far, and a held draw tires the arm.

const BOW := "core:item/hunting_bow"
const IRON_ARROW := "core:item/iron_arrow"
const FRAME := 1.0 / 60.0

var root: Node3D
var player: Player


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	root = Node3D.new()
	root.name = "Butts"
	_tree().root.add_child(root)
	_box(Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))
	player = (load("res://actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.02, 0.0)
	player.camera_rig.yaw = 0.0
	player.camera_rig.pitch = 0.0
	player.equip_weapon(BOW)
	(player.get_node("Inventory") as Inventory).add(IRON_ARROW, 30)


func after_each() -> void:
	for a in Player.ACTIONS:
		Input.action_release(a)
	if is_instance_valid(root):
		root.free()
	root = null
	player = null


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.global_position = at
	return body


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _until(predicate: Callable, timeout: float) -> bool:
	for i in int(timeout / FRAME):
		if bool(predicate.call()):
			return true
		await _tree().physics_frame
	return bool(predicate.call())


func _model() -> HumanoidModel:
	return player.anim.model as HumanoidModel


func _rig_built() -> bool:
	return ResourceLoader.exists(HumanoidModel.RIG_PATH) and player.anim.model != null


func _draw_full() -> void:
	Input.action_press("attack_light")
	await _until(func() -> bool: return player.bow_draw() >= 1.0, 3.0)
	await _frames(10)


func _loose() -> void:
	Input.action_release("attack_light")
	await _frames(2)


func _arrows() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for n in _tree().current_scene.get_children() if _tree().current_scene != null else []:
		if n is Projectile:
			out.append(n as Projectile)
	for n in root.get_children():
		if n is Projectile:
			out.append(n as Projectile)
	return out


func test_the_bow_is_drawn_over_the_legs() -> void:
	if not _rig_built():
		return
	await _frames(5)
	Input.action_press("attack_light")
	await _frames(12)
	assert_eq(player.state, Player.State.BOW, "holding the attack draws the bow")
	assert_eq(_model().current_stance(), "Bow_Draw", "the draw is the upper body's")
	Input.action_press("move_forward")
	await _frames(70)
	assert_eq(_model().current_stance(), "Bow_Aim", "held at full draw, it is held")
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	assert_near(v, Player.AIM_MOVE_SPEED, 0.4, "the archer walks with the bow drawn, slowly")
	assert_eq(str(_model().anim_tree.get("parameters/playback").get_current_node()), HumanoidModel.LOCOMOTION_STATE,
			"and the legs are the legs' (Locomotion), not a still one-shot")
	assert_gt(float(_model().anim_tree.get("parameters/Locomotion/move/blend_amount")), 0.8, "the legs walk")
	Input.action_release("move_forward")
	await _loose()


func test_a_draw_after_a_loose_plays_from_its_start() -> void:
	if not _rig_built():
		return
	await _frames(5)
	for n in 3:
		player.stamina_comp.refill()
		Input.action_press("attack_light")
		var least := INF
		var most := -INF
		for i in 70:
			await _tree().physics_frame
			if _model().current_stance() == "Bow_Draw":
				least = minf(least, _model().stance_time())
				most = maxf(most, _model().stance_time())
		Input.action_release("attack_light")
		await _until(func() -> bool: return player.state == Player.State.FREE, 2.0)
		await _frames(30)
		print("    draw %d: the rig drew Bow_Draw from %.2f to %.2f s" % [n + 1, least, most])
		assert_lt(least, 0.1, "draw %d began %.2f s into its clip" % [n + 1, least])
		assert_gt(most, 0.8, "draw %d never came to full" % (n + 1))


func test_the_arrow_is_nocked_drawn_and_loosed() -> void:
	if not _rig_built():
		return
	await _frames(5)
	var hands := _model().bow_hands
	assert_true(hands != null, "a body holding a bow works it")
	assert_true(HeldItems.quiver_of(_model()) != null or not ResourceLoader.exists(HeldItems.path_of(HeldItems.QUIVER_MODEL)),
			"and wears its quiver")
	assert_false(hands.arrow_shown, "no arrow in hand before the draw")
	await _draw_full()
	assert_true(hands.arrow_shown, "an arrow in the draw hand at full draw")
	assert_true(hands.string_held, "the string in the draw hand")
	assert_gt(hands.bend(), 0.75, "the limbs bent at full draw (%.2f)" % hands.bend())
	var nock := hands.nock_point()
	var fingers := (_model().socket("WeaponR") as Node3D).global_transform * HumanoidModel.grip_offset("R")
	assert_lt(nock.distance_to(fingers), 0.03, "the string is pulled to the fingers")
	# the arrow points where the bow's does: ahead of the body, the way it faces
	var arrow := hands.arrow()
	assert_true(arrow != null and arrow.visible)
	var way := -arrow.global_transform.basis.z.normalized()
	assert_gt(way.dot(player.forward()), 0.9, "the nocked arrow points ahead (%.2f)" % way.dot(player.forward()))
	var bow_way := hands.bow.global_transform.basis.y.normalized()
	assert_gt(bow_way.dot(player.forward()), 0.9, "the bow's arrow way is ahead (%.2f)" % bow_way.dot(player.forward()))
	var before := _arrows().size()
	await _loose()
	assert_eq(_arrows().size(), before + 1, "the loose sends an arrow")
	await _frames(6)
	assert_false(hands.arrow_shown, "and the hand is empty after it")
	assert_eq(_model().current_stance(), "Bow_Release", "the loose is played")
	await _frames(70)
	assert_lt(absf(hands.bend()), 0.05, "the limbs have sprung back (%.2f)" % hands.bend())
	assert_eq(_model().current_stance(), "", "and the upper body is the legs' again")


func test_the_body_turns_up_to_an_aim_above() -> void:
	if not _rig_built():
		return
	await _frames(5)
	var sk := _model().skeleton
	var chest := sk.find_bone("Chest")
	await _draw_full()
	var level := (sk.global_transform.basis * sk.get_bone_global_pose(chest).basis).y.normalized()
	player.camera_rig.pitch = 0.5
	await _frames(30)
	var up := (sk.global_transform.basis * sk.get_bone_global_pose(chest).basis).y.normalized()
	var tipped := rad_to_deg(level.angle_to(up))
	assert_gt(_model().aim_pitch, 0.3, "the body's aim follows the view up (%.2f)" % _model().aim_pitch)
	assert_gt(tipped, 15.0, "the chest leans back to aim up (%.1f degrees)" % tipped)
	await _loose()


func test_the_crosshair_closes_with_the_draw_and_goes_with_the_arrow() -> void:
	await _frames(5)
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await _frames(2)
	hud.call("_connect_world")
	hud.set("_player", player)
	await _frames(2)
	assert_false(bool(player.crosshair()["visible"]), "no crosshair with the bow let down")
	assert_false(bool(hud.call("crosshair_shown")["visible"]))
	Input.action_press("attack_light")
	await _until(func() -> bool: return player.bow_draw() >= 0.4, 2.0)
	var early: Dictionary = player.crosshair()
	await _until(func() -> bool: return player.bow_draw() >= 1.0, 2.0)
	await _frames(8)
	var full: Dictionary = player.crosshair()
	var shown: Dictionary = hud.call("crosshair_shown")
	assert_true(bool(early["visible"]) and bool(full["visible"]), "the crosshair is up while the bow is drawn")
	assert_true(bool(shown["visible"]), "and the HUD draws it")
	assert_gt(float(early["spread"]), float(full["spread"]) + 0.02, "it closes as the draw comes to full (%.3f then %.3f)" % [early["spread"], full["spread"]])
	assert_lt(float(full["spread"]), 0.005, "to a point at full draw")
	assert_lt(float(shown["gap"]), Crosshair.GAP_LEAST + 2.0, "and the HUD's ticks close in (%.1f px)" % float(shown["gap"]))
	assert_false(bool(full["on_target"]), "nothing under it yet")
	await _loose()
	await _frames(3)
	assert_false(bool(player.crosshair()["visible"]), "it goes when the arrow is loosed")
	assert_false(bool(hud.call("crosshair_shown")["visible"]))


func test_the_crosshair_marks_a_body_under_it() -> void:
	await _frames(5)
	var foe := Enemy.new()
	foe.configure("core:enemy/roadside_bandit")
	foe.position = Vector3(8.0, 0.02, -12.0)
	foe.rotation.y = PI
	root.add_child(foe)
	foe.perception.enabled = false
	foe.set_physics_process(false)
	await _frames(3)
	Input.action_press("attack_light")
	await _until(func() -> bool: return player.bow_draw() >= 1.0, 2.0)
	await _frames(20)
	assert_false(bool(player.crosshair()["on_target"]), "nothing under it off to the side")
	# stood 12 m down the view's middle, at chest height on the ray
	var along := player.camera_rig.camera_position() + player.camera_rig.aim_direction() * 12.0
	foe.global_position = Vector3(along.x, along.y - 1.15, along.z)
	await _frames(4)
	var ch: Dictionary = player.crosshair()
	print("    the aim: %s, on target %s" % [str(player.aim_hit().get("collider")), str(ch["on_target"])])
	assert_true(bool(ch["on_target"]), "a body under the crosshair marks it")
	await _loose()


func test_the_arrow_goes_where_the_crosshair_is() -> void:
	if not _rig_built():
		return
	await _frames(5)
	# a wall 25 m off and one 8 m off to the side, and the view on each in turn
	_box(Vector3(12.0, 8.0, 0.5), Vector3(0.0, 3.0, -25.0))
	for case in [[0.0, 0.0, "the far wall, level"], [0.0, 0.12, "the far wall, higher up"], [0.35, 0.02, "left of the far wall"]]:
		player.camera_rig.yaw = float(case[0])
		player.camera_rig.pitch = float(case[1])
		await _frames(20)
		await _draw_full()
		var aim := player.aim_point()
		var before := _arrows()
		await _loose()
		var shot: Projectile = null
		for a in _arrows():
			if not before.has(a):
				shot = a
		assert_true(shot != null, "%s: an arrow flew" % case[2])
		if shot == null:
			continue
		await _until(func() -> bool: return not is_instance_valid(shot) or bool(shot.get("_stuck")), 3.0)
		if is_instance_valid(shot):
			var off := shot.global_position.distance_to(aim)
			print("    %s: the aim at %s, the arrow in at %s (%.2f m off)" % [case[2], aim, shot.global_position, off])
			assert_lt(off, 0.45, "%s: the arrow lands where the crosshair was, not %.2f m off" % [case[2], off])
		await _until(func() -> bool: return player.state == Player.State.FREE and _model().current_stance() == "", 2.0)
		await _frames(10)


func test_a_draw_held_long_tires_and_trembles() -> void:
	await _frames(5)
	await _draw_full()
	assert_eq(player.bow_tremble(), 0.0, "steady at first")
	var had := player.stamina_comp.current
	await _frames(int((Player.BOW_STEADY_S + 1.5) * 60.0))
	assert_gt(player.bow_tremble(), 0.0, "held past its steady time the arm trembles")
	assert_lt(player.stamina_comp.current, had - 3.0, "and the hold costs stamina")
	assert_gt(float(player.crosshair()["spread"]), 0.0, "the crosshair opens with the tremble")
	if player.anim.model != null:
		assert_gt(float(player.anim.model.get("aim_tremble")), 0.0, "and the body shakes with it")
	await _loose()


func assert_lt(a: float, b: float, msg := "") -> void:
	assert_true(a < b, "%s (%.3f is not under %.3f)" % [msg, a, b])
