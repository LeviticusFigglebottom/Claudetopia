extends TestCase
## A one-shot plays from its start every time it is played, not only the first (playtest
## 2026-09-27, 4 and 6). The edge from the legs into a one-shot did not reset the clip, so a clip
## played before went on from where it was last left, its last frame: every heavy after the first
## stood in its follow-through with the blade out in front for the whole swing, and every roll after
## the first slid along in the roll's last pose, which read as a dash.
##
## The player's real heavies and rolls, on a floor, each played two and three times over, watched in
## the rig's own AnimationTree: its play position has to start near 0 and go most of the way through.

const FRAME := 1.0 / 60.0

var root: Node3D
var player: Player


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	root = Node3D.new()
	root.name = "ReplayYard"
	_tree().root.add_child(root)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	root.add_child(ground)
	player = (load("res://actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.02, 0.0)
	player.camera_rig.yaw = 0.0


func after_each() -> void:
	for a in Player.ACTIONS:
		Input.action_release(a)
	if is_instance_valid(root):
		root.free()
	root = null
	player = null


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _until(predicate: Callable, timeout: float) -> bool:
	for i in int(timeout / FRAME):
		if bool(predicate.call()):
			return true
		await _tree().physics_frame
	return bool(predicate.call())


func _playback() -> AnimationNodeStateMachinePlayback:
	return player.anim.model.get("_state_machine") as AnimationNodeStateMachinePlayback


## Presses `action` for `hold_frames`, then watches the rig until the body is free again: the
## least and the most of the tree's play position while it plays `clip`, and the clip's length.
func _play_and_watch(action: String, hold_frames: int, clip: String) -> Dictionary:
	player.stamina_comp.refill()
	Input.action_press(action)
	var least := INF
	var most := -INF
	for i in 240:
		if i == hold_frames:
			Input.action_release(action)
		await _tree().physics_frame
		var pb := _playback()
		if str(pb.get_current_node()) == clip:
			var at := pb.get_current_play_position()
			least = minf(least, at)
			most = maxf(most, at)
		if i > hold_frames and player.state == Player.State.FREE and not player.anim.is_busy():
			break
	Input.action_release(action)
	await _until(func() -> bool: return player.state == Player.State.FREE and player.can_act(), 3.0)
	await _frames(20)
	var length := float(player.anim.model.call("clip_length", clip))
	return {"least": least, "most": most, "length": length}


func test_every_heavy_swings_from_its_start() -> void:
	player.equip_weapon("core:item/iron_sword")
	await _frames(5)
	var clip := player.weapon.clip_for("heavy", 0)
	# a tap, a full charge, and a tap again
	for hold: int in [4, 80, 4]:
		var seen := await _play_and_watch("attack_heavy", hold, clip)
		print("    heavy held %d frames: the rig played %s from %.2f to %.2f s of %.2f" % [hold, clip, seen["least"], seen["most"], seen["length"]])
		assert_true(float(seen["least"]) < 0.15, "a heavy (held %d frames) began %.2f s into its clip, not at its start" % [hold, seen["least"]])
		assert_gt(float(seen["most"]), 0.7 * float(seen["length"]), "a heavy (held %d frames) never swung through" % hold)


func test_every_roll_rolls_from_its_start() -> void:
	player.equip_weapon("core:item/iron_sword")
	await _frames(5)
	for n in 3:
		var seen := await _play_and_watch("dodge", 3, "Dodge_F")
		print("    roll %d: the rig played Dodge_F from %.2f to %.2f s of %.2f" % [n + 1, seen["least"], seen["most"], seen["length"]])
		assert_true(float(seen["least"]) < 0.15, "roll %d began %.2f s into its clip: the body slid in the roll's last pose" % [n + 1, seen["least"]])
		assert_gt(float(seen["most"]), 0.6 * float(seen["length"]), "roll %d never rolled through" % (n + 1))


## The staff swings its own clips now (triage 56), not the fists': a light, the chain's second, and
## a heavy, each from its start every time.
func test_the_staff_swings_its_own_clips_from_their_start() -> void:
	player.equip_weapon("core:item/ash_staff")
	await _frames(5)
	assert_eq(player.weapon.clip_for("light", 0), "Attack_Staff_1")
	assert_eq(player.weapon.clip_for("light", 1), "Attack_Staff_2")
	assert_eq(player.weapon.clip_for("heavy", 0), "Attack_Staff_Heavy")
	for hold: int in [4, 80, 4]:
		var seen := await _play_and_watch("attack_heavy", hold, "Attack_Staff_Heavy")
		print("    staff heavy held %d frames: the rig played it from %.2f to %.2f s of %.2f" % [hold, seen["least"], seen["most"], seen["length"]])
		assert_true(float(seen["least"]) < 0.15, "a staff heavy (held %d frames) began %.2f s into its clip" % [hold, seen["least"]])
		assert_gt(float(seen["most"]), 0.7 * float(seen["length"]), "a staff heavy (held %d frames) never swung through" % hold)
	for n in 2:
		var seen := await _play_and_watch("attack_light", 3, "Attack_Staff_1")
		assert_true(float(seen["least"]) < 0.15, "staff light %d began %.2f s into its clip" % [n + 1, seen["least"]])
		assert_gt(float(seen["most"]), 0.6 * float(seen["length"]), "staff light %d never swung through" % (n + 1))
