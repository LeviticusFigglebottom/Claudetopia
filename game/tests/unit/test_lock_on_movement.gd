extends TestCase
## Locked on, the body faces the foe and goes at the pace each way allows: a jog straight at it,
## a side-step across, a backpedal away, the ellipse between. The combat round's headless fights
## found that at the old 2.6 m/s every way, a locked-on player could not close on a caster
## backing away at about 3 m/s without letting go of the lock.

const PLAYER := preload("res://actors/player/player.tscn")
const ACTIONS: Array[String] = ["move_forward", "move_back", "move_left", "move_right", "sprint", "block"]
const FOE_AT := Vector3(0.0, 0.0, -25.0)

var player: Player = null
var floor_body: StaticBody3D = null
var foe: Node3D = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(7)
	SaveSystem.pending.clear()


func after_each() -> void:
	for a in ACTIONS:
		if InputMap.has_action(a):
			Input.action_release(a)
	for n in [player, floor_body, foe]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	player = null
	floor_body = null
	foe = null
	GameState.reset_for_new_game(7)


func _ticks(n: int) -> void:
	for i in n:
		await _tree().physics_frame


## A body standing at the origin facing north, locked on to a foe 25 m ahead of it.
func _stand_locked() -> void:
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	_tree().root.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	player.teleport(Vector3(0.0, 0.02, 0.0), 0.0)
	foe = Node3D.new()
	_tree().root.add_child(foe)
	foe.global_position = FOE_AT
	await _ticks(8)
	player.lock.set_target(foe)
	await _ticks(20)


func _gap() -> float:
	var d := foe.global_position - player.global_position
	return Vector2(d.x, d.z).length()


## Ground speed with `actions` held, measured over half a second after a second and a half.
func _pace(actions: Array) -> float:
	for a in actions:
		Input.action_press(str(a))
	await _ticks(90)
	var from := player.global_position
	await _ticks(30)
	var v := player.global_position - from
	for a in actions:
		Input.action_release(str(a))
	await _ticks(30)
	return Vector2(v.x, v.z).length() / 0.5


func test_a_locked_on_body_closes_on_a_foe_backing_away() -> void:
	await _stand_locked()
	var away := (foe.global_position - player.global_position)
	away.y = 0.0
	away = away.normalized()
	var start := _gap()
	Input.action_press("move_forward")
	for i in 180:
		foe.global_position += away * 3.0 / Engine.physics_ticks_per_second
		await _tree().physics_frame
	Input.action_release("move_forward")
	var closed := start - _gap()
	print("    locked on, W for 3 s at a foe backing away at 3.0 m/s: the gap closed by %.2f m, and the lock %s" % [
		closed, "held" if player.lock.is_locked() else "was lost"])
	assert_true(player.lock.is_locked(), "the lock was lost")
	assert_gt(closed, 4.0, "a locked-on player cannot catch a foe backing away at 3 m/s (the gap closed %.2f m in 3 s)" % closed)


func test_the_locked_on_pace_goes_by_the_way_it_goes() -> void:
	await _stand_locked()
	var at := await _pace(["move_forward"])
	var across := await _pace(["move_right"])
	var back := await _pace(["move_back"])
	var diagonal := await _pace(["move_forward", "move_left"])
	var want_diagonal := Player.locked_speed(Vector2(-1.0, 1.0))
	print("    locked on: %.2f m/s at the foe, %.2f across, %.2f backing off, %.2f on the diagonal (the ellipse says %.2f)" % [
		at, across, back, diagonal, want_diagonal])
	assert_near(at, Player.LOCKED_FORWARD, 0.15, "straight at the foe")
	assert_near(across, Player.LOCKED_SIDE, 0.15, "across it")
	assert_near(back, Player.LOCKED_BACK, 0.15, "backing off")
	assert_near(diagonal, want_diagonal, 0.2, "on the diagonal")
	assert_true(player.lock.is_locked(), "the lock was lost")


func test_blocking_is_still_a_guard_walk() -> void:
	await _stand_locked()
	var pace := await _pace(["block", "move_forward"])
	print("    blocking, locked on, W: %.2f m/s" % pace)
	assert_near(pace, Player.STRAFE_SPEED * Player.BLOCK_MOVE_MULT, 0.12, "a raised guard walks")


## Sprint breaks the strafe and keeps the lock: the body runs where it is pushed, and turns back
## to the foe when Sprint is let go.
func test_a_sprint_while_locked_on_runs_and_keeps_the_lock() -> void:
	await _stand_locked()
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _ticks(90)
	var v := Vector2(player.velocity.x, player.velocity.z)
	var facing := Vector2(-sin(player.rotation.y), -cos(player.rotation.y))
	var off_run := rad_to_deg(absf(facing.angle_to(v)))
	var speed := v.length()
	Input.action_release("sprint")
	await _ticks(30)
	Input.action_release("move_right")
	var to_foe := foe.global_position - player.global_position
	var face_foe := rad_to_deg(absf(wrapf(player.rotation.y - atan2(-to_foe.x, -to_foe.z), -PI, PI)))
	print("    sprinting while locked on: %.2f m/s, facing %.0f deg off the run; Sprint let go, %.0f deg off the foe" % [
		speed, off_run, face_foe])
	assert_gt(speed, Player.JOG_SPEED + 1.5, "a sprint while locked on did not sprint")
	assert_true(off_run < 20.0, "the sprinting body did not face where it ran")
	assert_true(player.lock.is_locked(), "sprinting let go of the lock")
	assert_true(face_foe < 10.0, "with Sprint let go, the body did not turn back to the foe")
