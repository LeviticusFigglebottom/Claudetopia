extends TestCase
## A parry the player can make (playtest 2026-09-27, 9: "parry nearly impossible, even against
## Dole"):
##   * a foe's melee blow glints on its weapon Enemy.TELL_LEAD_S before it goes live (Impact.tell),
##     pale for a blow a guard turns, so a press on the glint lands in the parry window;
##   * the guard's press is the parry's clock in any state, not only while the body is free: a
##     block pressed in the last of a swing counts.

const SPARRING := "core:enemy/sparring_dole"
const SWORD := "core:item/iron_sword"
const SHIELD := "core:item/round_shield"

var root: Node3D
var player: Player
var foe: Enemy


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	root = Node3D.new()
	root.name = "TellYard"
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
	player.equip_offhand(SHIELD)
	foe = Enemy.new()
	foe.configure(SPARRING)
	foe.position = Vector3(0.0, 0.02, -6.0)
	foe.rotation.y = PI
	root.add_child(foe)
	foe.perception.enabled = false


func after_each() -> void:
	for a in Player.ACTIONS:
		Input.action_release(a)
	if is_instance_valid(root):
		root.free()


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _tells() -> Array[Node]:
	var out: Array[Node] = []
	for n in foe.find_children("Tell", "MeshInstance3D", true, false):
		if not n.is_queued_for_deletion():
			out.append(n)
	return out


func test_a_blow_glints_before_it_goes_live() -> void:
	await _frames(3)
	foe.target = player
	foe._begin_melee(foe.attacks[0])
	var live_in := foe.anim.time_to_event("hit_start")
	var told_at := -1.0
	var live_at := -1.0
	var t0 := Actor.now()
	for i in 150:
		await _tree().physics_frame
		if told_at < 0.0 and not _tells().is_empty():
			told_at = Actor.now() - t0
		if live_at < 0.0 and foe._attack_phase == "active":
			live_at = Actor.now() - t0
		if live_at >= 0.0:
			break
	print("    the cut's wind-up %.2f s: the glint at %.2f s, the blow live at %.2f s" % [live_in, told_at, live_at])
	assert_true(told_at >= 0.0, "the blow never glinted")
	assert_true(live_at - told_at >= Enemy.TELL_LEAD_S - 0.04 and live_at - told_at <= Enemy.TELL_LEAD_S + 0.04,
			"the glint came %.2f s before the blow, not %.2f s" % [live_at - told_at, Enemy.TELL_LEAD_S])


func test_a_block_pressed_during_a_swing_is_the_parry_s_clock() -> void:
	await _frames(5)
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	await _frames(6)
	assert_eq(player.state, Player.State.ATTACK, "the swing did not start")
	var before := player.parry_pressed_at
	Input.action_press("block")
	await _frames(1)
	assert_eq(player.state, Player.State.ATTACK, "the block was pressed after the swing")
	assert_gt(player.parry_pressed_at, before, "a block pressed during a swing was not counted for a parry")
