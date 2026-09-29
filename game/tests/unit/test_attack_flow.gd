extends TestCase
## What comes after a blow (playtest 2026-09-27, 7: "too much delay after and between attacks").
## Once a swing's recovery may be cut short (cancel_ok) the next thing asked for comes at once:
##   * a light pressed early in the swing, longer ago than the input buffer, still chains;
##   * a heavy pressed during a light starts at the light's cancel_ok, not at its last frame;
##   * a direction held gives the body back its feet at cancel_ok.

const SWORD := "core:item/iron_sword"

var root: Node3D
var player: Player


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	root = Node3D.new()
	root.name = "FlowYard"
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
	player.equip_weapon(SWORD)


func after_each() -> void:
	for a in Player.ACTIONS:
		Input.action_release(a)
	if is_instance_valid(root):
		root.free()


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)


## The seconds from the first light's start to `what` happening, or -1 within two seconds.
func _after_a_light(then: Callable, what: Callable) -> float:
	await _frames(5)
	player.stamina_comp.refill()
	var t0 := Actor.now()
	await _tap("attack_light")
	await then.call()
	for i in 120:
		await _tree().physics_frame
		if bool(what.call()):
			return Actor.now() - t0
	return -1.0


func test_a_light_pressed_early_in_the_swing_still_chains() -> void:
	var seen: Array[int] = []
	player.attack_started.connect(func(_k: String, i: int) -> void: seen.append(i))
	var cancel_at := float(player.weapon.timing_for("light", 0)["events"].filter(
			func(e: Dictionary) -> bool: return e["name"] == "cancel_ok")[0]["t"])
	# pressed 3 frames into the first light (the key let go a frame between): far more than INPUT_BUFFER before its cancel_ok
	var at := await _after_a_light(func() -> void:
			await _frames(1)
			await _tap("attack_light"),
			func() -> bool: return seen.size() >= 2)
	print("    the second light began %.2f s after the first (its cancel_ok at %.2f s)" % [at, cancel_at])
	assert_true(cancel_at - 0.05 > DamageModel.INPUT_BUFFER, "the press is not early enough to test the buffer")
	assert_eq(seen, [0, 1] as Array[int], "a light pressed early in the swing did not chain")
	assert_true(at > 0.0 and at <= cancel_at + 0.05, "the chained light waited past cancel_ok (%.2f s)" % at)


func test_a_heavy_after_a_light_comes_at_cancel_ok() -> void:
	var kinds: Array[String] = []
	player.attack_started.connect(func(k: String, _i: int) -> void: kinds.append(k))
	var light := player.weapon.timing_for("light", 0)
	var cancel_at := float(light["events"].filter(func(e: Dictionary) -> bool: return e["name"] == "cancel_ok")[0]["t"])
	var at := await _after_a_light(func() -> void:
			await _frames(18)
			await _tap("attack_heavy"),
			func() -> bool: return kinds.has("heavy"))
	print("    the heavy began %.2f s after the light (cancel_ok %.2f s, the clip ends %.2f s)" % [at, cancel_at, float(light["length"])])
	assert_true(at > 0.0, "a heavy pressed during a light never came")
	assert_true(at <= cancel_at + 0.05, "the heavy waited for the light's last frame (%.2f s)" % at)


func test_a_direction_held_frees_the_body_at_cancel_ok() -> void:
	var light := player.weapon.timing_for("light", 0)
	var cancel_at := float(light["events"].filter(func(e: Dictionary) -> bool: return e["name"] == "cancel_ok")[0]["t"])
	var at := await _after_a_light(func() -> void: Input.action_press("move_forward"),
			func() -> bool: return player.state == Player.State.FREE)
	Input.action_release("move_forward")
	print("    free to walk %.2f s after the light (cancel_ok %.2f s, the clip ends %.2f s)" % [at, cancel_at, float(light["length"])])
	assert_true(at > 0.0 and at <= cancel_at + 0.05, "the body stood out the swing's last frames (%.2f s)" % at)
