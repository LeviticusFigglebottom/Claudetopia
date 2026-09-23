extends TestCase
## What `./run.sh fights` found the first time a scripted player fought one foe of every archetype,
## each pinned by the real controller and a real Enemy on a real floor:
##
##   * a swing's volume sat at chest height and missed anything low (no sword touched a drake);
##   * knockback was added to the velocity every frame, so a knockdown threw the player off the map;
##   * an enemy that left the fight in the middle of a blow went on lunging for ever;
##   * patience ran from the start of a fight rather than from the last sight of the target;
##   * a pack waited on a ring wider than its bite and so never closed to bite;
##   * a circling wolf went round the player about once a second.

const FRAME := 1.0 / 60.0
const SWORD := "core:item/iron_sword"
const DRAKE := "core:enemy/gutter_drake"
const WOLF := "core:enemy/down_wolf"
const BANDIT := "core:enemy/roadside_bandit"

var root: Node3D
var player: Player


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	root = Node3D.new()
	root.name = "FightsFound"
	_tree().root.add_child(root)
	var ground := StaticBody3D.new()
	ground.name = "Floor"
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	root.add_child(ground)
	player = (load("res://actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.02, 0.0)
	player.rotation.y = 0.0
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


## A foe that stands where it is put: brain, eyes and steering off; body, hurtbox and poise real.
## It is placed before it enters the tree. Added at the origin and then moved, it is a floor the
## player is standing on that jumps 1.2 m and turns half round in one frame, and a CharacterBody3D
## leaves a moving floor with the floor's speed: the player went off at 230 m/s.
func _still_foe(id: String, at: Vector3) -> Enemy:
	var e := _placed(id, at)
	e.perception.enabled = false
	e.set_physics_process(false)
	return e


## A foe that thinks for itself, told where the player is.
func _live_foe(id: String, at: Vector3) -> Enemy:
	var e := _placed(id, at)
	e.perception.alert_to(player.global_position, player)
	return e


func _placed(id: String, at: Vector3) -> Enemy:
	var e := Enemy.new()
	e.configure(id)
	e.position = at
	e.rotation.y = PI
	root.add_child(e)
	e.spawn_position = at
	e.brain.post = at
	return e


func _attack(e: Enemy, attack_name: String) -> Dictionary:
	for a in e.attacks:
		if str(a.get("name", "")) == attack_name:
			return a
	return {}


# --- reach ------------------------------------------------------------------------------------------

func test_a_sword_reaches_a_gutter_drake_and_a_wolf() -> void:
	player.equip_weapon(SWORD)
	await _frames(3)
	for id in [DRAKE, WOLF]:
		var foe := _still_foe(id, Vector3(0.0, 0.02, -1.2))
		await _frames(3)
		var before := foe.health
		player.stamina_comp.refill()
		Input.action_press("attack_light")
		await _frames(2)
		Input.action_release("attack_light")
		for i in 90:
			if foe.health < before:
				break
			await _tree().physics_frame
		assert_true(foe.health < before, "a light swing at %s standing 1.2 m ahead lands (hp %.1f -> %.1f)" % [id, before, foe.health])
		foe.free()
		await _frames(40)


func test_a_swing_sweeps_from_near_the_ground_to_over_the_head() -> void:
	player.equip_weapon(SWORD)
	await _frames(2)
	var span := player.weapon.hitbox.vertical_span()
	var origin_y := player.attack_origin.position.y
	assert_true(origin_y + span.x <= 0.15, "the swing reaches down to %.2f m" % (origin_y + span.x))
	assert_true(origin_y + span.y >= 1.8, "and up to %.2f m" % (origin_y + span.y))
	var drake := _still_foe(DRAKE, Vector3(0.0, 0.02, -1.5))
	drake._current_attack = _attack(drake, "ankle_snap")
	var hb := drake._weapon_hitbox()
	var d_span := hb.vertical_span()
	var d_origin := drake.attack_origin.position.y
	assert_true(d_origin + d_span.x <= 0.1, "a drake's bite reaches the ground (%.2f m)" % (d_origin + d_span.x))
	assert_true(d_origin + d_span.y >= 0.5, "and its own height (%.2f m)" % (d_origin + d_span.y))


# --- knockback --------------------------------------------------------------------------------------

func test_knockback_moves_the_body_the_metres_it_says() -> void:
	await _frames(3)
	var start := player.global_position
	var hit := HitData.new()
	hit.amount = 1.0
	hit.poise_damage = 0.0
	hit.knockback = 3.4
	hit.origin = start + Vector3(0.0, 0.0, -1.0)
	player.take_hit(hit)
	await _frames(90)
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	assert_near(moved, 3.4, 0.35, "a knockback of 3.4 m carried the body %.2f m" % moved)
	assert_true(player.global_position.z > start.z, "away from the blow")


func test_a_knockdown_throws_a_body_metres_not_the_length_of_the_map() -> void:
	await _frames(3)
	var start := player.global_position
	var hit := HitData.new()
	hit.amount = 1.0
	hit.poise_damage = 0.0
	hit.knockback = 3.4
	hit.knockdown = true
	hit.origin = start + Vector3(0.0, 0.0, -1.0)
	player.take_hit(hit)
	assert_eq(player.state, Player.State.STUNNED, "knocked down")
	await _frames(150)
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	# The blow's 3.4 m already carries more than a knockdown's own 1.2 m, so it adds nothing.
	assert_near(moved, 3.4, 0.4, "knocked down and thrown %.2f m" % moved)


func test_two_shoves_add_as_distances() -> void:
	player._add_shove(Vector3.BACK, 1.0)
	player._add_shove(Vector3.BACK, 2.0)
	assert_near(player.shove_left(), 3.0, 0.001)
	player._add_shove(Vector3.FORWARD, 3.0)
	assert_near(player.shove_left(), 0.0, 0.001, "opposite shoves cancel")


# --- a blow outlived by its fight ----------------------------------------------------------------

func test_leaving_the_fight_mid_blow_calls_the_blow_off() -> void:
	var wolf := _live_foe(WOLF, Vector3(0.0, 0.02, -1.6))
	await _frames(3)
	assert_eq(wolf.brain.state, Brain.COMBAT)
	wolf._begin_attack(_attack(wolf, "bite"))
	await _frames(int(0.45 / FRAME))
	assert_true(wolf.is_busy(), "the bite is under way")
	wolf.brain.force(Brain.SEARCH)
	assert_false(wolf.is_busy(), "leaving the fight ends the blow")
	var at := wolf.global_position
	wolf.perception.enabled = false
	wolf.perception.reset()
	await _frames(60)
	assert_true(wolf.global_position.distance_to(at) < 4.0, "and it does not lunge on across the floor (moved %.1f m)" % wolf.global_position.distance_to(at))


# --- patience -----------------------------------------------------------------------------------

func test_patience_runs_from_the_last_sight() -> void:
	var p := Brain.params_for("skirmisher")      # patience 3.5
	var ctx := {"detection": 1.0, "can_see": false, "target_alive": true, "distance_to_post": 1.0,
		"distance_to_target": 2.0, "time_in_state": 30.0, "time_unseen": 0.5}
	assert_eq(Brain.decide(Brain.COMBAT, p, ctx), Brain.COMBAT, "half a second unseen, thirty seconds in: still fighting")
	ctx["time_unseen"] = 4.0
	assert_eq(Brain.decide(Brain.COMBAT, p, ctx), Brain.SEARCH, "unseen for longer than its patience: it searches")


# --- packs --------------------------------------------------------------------------------------

func test_a_pack_member_with_a_blow_ready_closes_to_bite() -> void:
	var wolves: Array[Enemy] = []
	for x in [-3.0, 0.0, 3.0]:
		wolves.append(_still_foe(WOLF, Vector3(x, 0.02, -8.0)))
	await _frames(2)
	var w := wolves[1]
	w.target = player
	var spread := float(w.brain.param("spread", 2.6))
	w._global_cooldown = 1.0
	var waiting := w._approach_goal().distance_to(player.global_position)
	assert_near(waiting, maxf(spread, w.brain.engage_range()), 0.01, "cooling down, it waits on the ring")
	w._global_cooldown = 0.0
	var closing := w._approach_goal().distance_to(player.global_position)
	assert_true(closing <= float(_attack(w, "bite")["range"]), "with a bite ready it comes in to %.2f m, inside the bite's %.1f" % [closing, float(_attack(w, "bite")["range"])])


func test_circling_is_held_to_a_sweep_a_person_can_follow() -> void:
	var wolf := _still_foe(WOLF, Vector3(0.0, 0.02, -1.2))
	wolf.target = player
	await _frames(1)
	for i in 60:
		wolf._strafe_or_retreat(FRAME, 1.2, false)
	var v := Vector2(wolf.velocity.x, wolf.velocity.z).length()
	assert_true(v <= Enemy.MAX_CIRCLE_RATE * 1.2 + 0.01, "circling at 1.2 m it moves %.2f m/s, at most %.2f" % [v, Enemy.MAX_CIRCLE_RATE * 1.2])
	assert_true(v > 0.5, "but it does circle (%.2f m/s)" % v)


# --- the leash ----------------------------------------------------------------------------------

func test_a_broken_leash_holds_until_the_fighter_is_home() -> void:
	var p := Brain.params_for("caster")      # leash 30, engage 12
	var ctx := {"detection": 1.0, "can_see": true, "target_alive": true, "distance_to_post": 31.0,
		"distance_to_target": 7.0, "time_in_state": 1.0}
	assert_eq(Brain.decide(Brain.COMBAT, p, ctx), Brain.RETURN, "past the leash it turns for home")
	assert_eq(Brain.decide(Brain.RETURN, p, ctx), Brain.RETURN, "and seeing its quarry does not turn it back")
	ctx["distance_to_post"] = 20.0
	assert_eq(Brain.decide(Brain.RETURN, p, ctx), Brain.RETURN, "not while it is still more than halfway out")
	ctx["distance_to_target"] = 2.0
	assert_eq(Brain.decide(Brain.RETURN, p, ctx), Brain.COMBAT, "somebody at arm's reach does")
	ctx["distance_to_target"] = 7.0
	ctx["distance_to_post"] = 12.0
	assert_eq(Brain.decide(Brain.RETURN, p, ctx), Brain.COMBAT, "back inside its ground, it fights what it sees")
