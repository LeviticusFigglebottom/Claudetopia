extends TestCase
## Foes take turns on one body (AttackTokens; playtest 2026-09-27, 8: "several enemies at once is
## near impossible"): no more than AttackTokens.MOST of them are in an attack on it at once, two
## attacks do not begin on it within AttackTokens.GAP_S, and the ones kept waiting hold off outside
## their reach rather than standing at arm's length; the turns go round, so every foe gets one.

const FOE := "core:enemy/roadside_bandit"

var root: Node3D
var player: Player


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	AttackTokens.clear()
	root = Node3D.new()
	root.name = "TurnsYard"
	_tree().root.add_child(root)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	root.add_child(ground)
	player = (load("res://actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.02, 0.0)
	player.set_input_enabled(false)


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	AttackTokens.clear()


func test_the_tokens_are_given_by_turns() -> void:
	var target := Node3D.new()
	var a := Node3D.new()
	var b := Node3D.new()
	var c := Node3D.new()
	var boss := Node3D.new()
	for n in [target, a, b, c, boss]:
		root.add_child(n)
	assert_true(AttackTokens.take(target, a), "the first foe is refused")
	assert_false(AttackTokens.take(target, b), "a second attack began at once, inside the gap")
	assert_true(AttackTokens.take(target, a), "a holder asking again loses its turn")
	AttackTokens._by_target[target.get_instance_id()]["last"] = -100.0
	assert_true(AttackTokens.take(target, b), "the second foe is refused after the gap")
	AttackTokens._by_target[target.get_instance_id()]["last"] = -100.0
	assert_false(AttackTokens.take(target, c), "a third foe attacked while two were at it")
	assert_true(AttackTokens.take(target, boss, true), "a boss was kept waiting")
	assert_eq(AttackTokens.held_on(target), 3)
	AttackTokens.give_back(null, a)
	AttackTokens.give_back(target, boss)
	AttackTokens._by_target[target.get_instance_id()]["last"] = -100.0
	assert_true(AttackTokens.take(target, c), "a token given back was not free again")
	b.free()
	assert_eq(AttackTokens.held_on(target), 1, "a freed holder kept its token")


func test_three_bandits_take_turns() -> void:
	var foes: Array[Enemy] = []
	for i in 3:
		var e := Enemy.new()
		e.configure(FOE)
		var at := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(i) / 3.0) * 2.0 + Vector3(0.0, 0.02, 0.0)
		e.position = at
		root.add_child(e)
		e.spawn_position = at
		e.brain.post = at
		foes.append(e)
	await _tree().physics_frame
	for e in foes:
		e.perception.alert_to(player.global_position, player)
	var most := 0
	var began: Array[float] = []
	var who: Dictionary = {}
	var was := {}
	var near_idle := 0.0
	var idle_samples := 0
	for f in 600:
		player.full_restore()
		await _tree().physics_frame
		var now_in := 0
		for e in foes:
			var busy: bool = e._attacking or e._charging
			if busy:
				now_in += 1
			if busy and not bool(was.get(e, false)):
				began.append(Actor.now())
				who[e.get_instance_id()] = true
			was[e] = busy
			if not busy and e.now() < e._await_turn_until:
				idle_samples += 1
				near_idle += (e.global_position - player.global_position).length()
		most = maxi(most, now_in)
	began.sort()
	var closest_gap := INF
	for i in range(1, began.size()):
		closest_gap = minf(closest_gap, began[i] - began[i - 1])
	var waiting_at := near_idle / float(maxi(idle_samples, 1))
	print("    ten seconds of three bandits: %d attacks, by %d of them, at most %d at once, the closest two %.2f s apart; a waiting bandit stood %.1f m off" % [
			began.size(), who.size(), most, closest_gap, waiting_at])
	assert_gt(began.size(), 3, "the bandits hardly fought")
	assert_true(most <= AttackTokens.MOST, "%d bandits were in an attack at once" % most)
	assert_true(closest_gap >= AttackTokens.GAP_S - 0.02, "two attacks began %.2f s apart" % closest_gap)
	assert_eq(who.size(), 3, "the turns did not go round: %d of the three attacked" % who.size())
	if idle_samples > 0:
		assert_gt(waiting_at, foes[0].brain.engage_range(), "a bandit waiting its turn stood inside its own reach")


## A kind may keep to fewer turns, further apart (its behaviour's `turns` and `turn_gap`): the
## down-wolf pack bites one at a time with a breath between, and a slow two-hander had nothing left
## to swing with when three bit 0.45 s apart (triage 38).
func test_a_wolf_pack_bites_one_at_a_time() -> void:
	var target := Node3D.new()
	root.add_child(target)
	var wolves: Array[Enemy] = []
	for i in 2:
		var e := Enemy.new()
		e.configure("core:enemy/down_wolf")
		e.position = Vector3(2.0 + float(i), 0.02, 0.0)
		root.add_child(e)
		wolves.append(e)
	assert_eq(wolves[0].attack_turns(), 1, "a wolf keeps to one turn at a time")
	assert_true(wolves[0].attack_turn_gap() > AttackTokens.GAP_S, "and a longer breath between turns")
	assert_true(AttackTokens.take(target, wolves[0]))
	var tid := target.get_instance_id()
	AttackTokens._by_target[tid]["last"] = Actor.now() - AttackTokens.GAP_S - 0.01
	# (held while it is in its bite)
	wolves[0]._attacking = true
	assert_false(AttackTokens.take(target, wolves[1]), "a second wolf bit while the first was at it")
	wolves[0]._attacking = false
	AttackTokens.give_back(target, wolves[0])
	assert_false(AttackTokens.take(target, wolves[1]), "the next bite came inside the pack's own gap")
	AttackTokens._by_target[tid]["last"] = Actor.now() - wolves[1].attack_turn_gap() - 0.01
	assert_true(AttackTokens.take(target, wolves[1]), "the next wolf's turn never came")
	var bandit := Enemy.new()
	bandit.configure(FOE)
	root.add_child(bandit)
	assert_eq(bandit.attack_turns(), AttackTokens.MOST, "a kind that says nothing keeps the common turns")
