extends TestCase
## "Roll through his swing" (the warrior's ring, playtest 2026-09-27, 5): a blow that goes live at
## the player while the player rolls, near enough that the roll is what took the body out of its
## way, is a dodge as a lesson counts it (EventBus.act_done "dodge", Actor.count_dodge), whether or
## not the blow's hitbox touched the rolling body; one blow counts once; a blow far off, or one at
## a body standing still, does not.

const SPARRING := "core:enemy/sparring_dole"

var root: Node3D
var player: Player
var foe: Enemy
var dodges: Array = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	root = Node3D.new()
	root.name = "RingYard"
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
	foe = Enemy.new()
	foe.configure(SPARRING)
	foe.position = Vector3(0.0, 0.02, -2.0)
	root.add_child(foe)
	foe.perception.enabled = false
	foe.set_physics_process(false)
	foe.target = player
	foe._current_attack = foe.attacks[0]
	dodges.clear()
	EventBus.act_done.connect(_on_act)


func after_each() -> void:
	if EventBus.act_done.is_connected(_on_act):
		EventBus.act_done.disconnect(_on_act)
	for a in Player.ACTIONS:
		Input.action_release(a)
	if is_instance_valid(root):
		root.free()


func _on_act(act: String, by: Node, on: Node, _detail: String) -> void:
	if act == "dodge" and by == player:
		dodges.append(on)


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _swing() -> void:
	foe._open_hitbox()
	await _frames(2)
	foe._weapon_hitbox().end_swing()


func test_a_blow_at_a_body_standing_still_is_no_dodge() -> void:
	await _frames(3)
	player.global_position = Vector3(0.0, 0.02, 3.5)     # out of reach, not rolling
	await _swing()
	assert_eq(dodges.size(), 0, "a blow at a body standing out of reach counted as a dodge")


func test_a_roll_out_of_the_blow_s_reach_is_a_dodge() -> void:
	await _frames(3)
	# rolled back away from him: by the time his blow goes live the body is out of its reach
	Input.action_press("move_back")
	Input.action_press("dodge")
	await _frames(2)
	Input.action_release("dodge")
	assert_eq(player.state, Player.State.DODGE, "the roll did not start")
	await _frames(24)
	Input.action_release("move_back")
	var d := (player.global_position - foe.global_position).length()
	print("    the body is %.2f m from him as his blow goes live (its reach %.1f m)" % [d, float(foe._current_attack["range"])])
	await _swing()
	assert_eq(dodges.size(), 1, "a roll out of his swing's reach was not a dodge")
	if dodges.size() == 1:
		assert_true(dodges[0] == foe, "the dodge was not counted against him (a lesson's `against`)")
	# the same blow finding the body in its i-frames is the same dodge, not a second
	player.count_dodge(foe)
	assert_eq(dodges.size(), 1, "one blow counted twice")


func test_a_roll_far_from_the_blow_is_no_dodge() -> void:
	await _frames(3)
	player.global_position = Vector3(0.0, 0.02, 12.0)
	Input.action_press("dodge")
	await _frames(2)
	Input.action_release("dodge")
	await _frames(6)
	await _swing()
	assert_eq(dodges.size(), 0, "a roll twelve metres off counted as rolling through his blow")
