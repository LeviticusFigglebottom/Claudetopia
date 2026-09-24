extends TestCase
## How a blow lands (Impact, ImpactFx, WeaponTrail, HumanoidModel.hit_stop, CameraRig.shake): the
## player's real swings on a real foe on a floor, as test_combat_design fights.
##
##   * a landed blow holds both pictures still for a few frames, longer for a heavier weapon, and
##     the fight's own clock does not move by a frame: every §5.3 event of the swing comes on the
##     same physics frame with the hold as without it;
##   * the camera kicks, and not at all with the Camera kick setting at 0;
##   * flesh bleeds (and not with Blood off), armour sparks (fewer with Less flashing), stone
##     dusts, wood splinters; the stain lies on the floor under the blow;
##   * a heavy swing streaks while its blow is live and not after;
##   * a heavy drives the foe back, more for a greatsword; a light does not.

const FRAME := 1.0 / 60.0
const SWORD := "core:item/iron_sword"
const DAGGER := "core:item/iron_dagger"
const GREATSWORD := "core:item/iron_greatsword"
const FOE := "core:enemy/roadside_bandit"
const KNIGHT := "core:enemy/tolling_knight"

var root: Node3D
var player: Player
var _saved: Dictionary = {}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	for k: Array in [["accessibility", "hit_pause"], ["accessibility", "camera_shake"], ["accessibility", "reduce_flashing"], ["gameplay", "blood"]]:
		_saved[k] = Settings.get_value(k[0], k[1], null)
	Settings.set_value("accessibility", "hit_pause", true, false)
	Settings.set_value("accessibility", "camera_shake", 1.0, false)
	Settings.set_value("accessibility", "reduce_flashing", false, false)
	Settings.set_value("gameplay", "blood", true, false)
	GameState.set_flag("new_game", false)
	root = Node3D.new()
	root.name = "ImpactYard"
	_tree().root.add_child(root)
	var ground := StaticBody3D.new()
	ground.name = "Floor"
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
	for k: Array in _saved:
		if _saved[k] != null:
			Settings.set_value(k[0], k[1], _saved[k], false)
	for n in _tree().get_nodes_in_group(ImpactFx.GROUP):
		n.queue_free()
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


func _foe(id: String, at: Vector3) -> Enemy:
	var e := Enemy.new()
	e.configure(id)
	e.position = at
	e.rotation.y = PI
	root.add_child(e)
	e.spawn_position = at
	e.brain.post = at
	e.perception.enabled = false
	e.set_physics_process(false)
	return e


func _free_again() -> void:
	for a in Player.ACTIONS:
		Input.action_release(a)
	await _until(func() -> bool: return player.state == Player.State.FREE and player.can_act(), 4.0)
	player.stamina_comp.refill()
	await _frames(2)


## One light swing on a fresh foe: the physics frame (from the press) of each of the swing's
## events, and whether it landed.
func _swing_events(weapon: String) -> Dictionary:
	player.equip_weapon(weapon)
	var foe := _foe(FOE, Vector3(0.0, 0.02, -1.4))
	await _frames(3)
	var hp0 := foe.health
	var at := {}
	var f0 := Engine.get_physics_frames()
	var on_event := func(e: String) -> void:
		if not at.has(e):
			at[e] = Engine.get_physics_frames() - f0
	player.anim.clip_event.connect(on_event)
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	await _until(func() -> bool: return player.state == Player.State.FREE, 3.0)
	player.anim.clip_event.disconnect(on_event)
	at["landed"] = foe.health < hp0
	foe.free()
	await _free_again()
	return at


func test_a_landed_blow_holds_the_picture_and_not_the_clock() -> void:
	var held := await _swing_events(SWORD)
	var owed := 0.0
	var stop := float(Impact.last.get("stop", 0.0))
	Settings.set_value("accessibility", "hit_pause", false, false)
	var plain := await _swing_events(SWORD)
	print("    a sword's light: events %s with the hold (%.3f s), %s without" % [str(held), stop, str(plain)])
	assert_true(bool(held.get("landed", false)) and bool(plain.get("landed", false)), "the swing did not land: %s / %s" % [held, plain])
	for e in ["hit_start", "hit_end", "cancel_ok"]:
		assert_eq(held.get(e, -1), plain.get(e, -2), "the hold moved %s off its frame" % e)
	assert_true(stop >= Impact.STOP_LIGHT_S and stop <= Impact.STOP_HEAVY_S, "a sword's hold is %.3f s" % stop)
	# and the picture was held: straight after a landed blow the body owes the time
	Settings.set_value("accessibility", "hit_pause", true, false)
	player.equip_weapon(GREATSWORD)
	var foe := _foe(FOE, Vector3(0.0, 0.02, -1.6))
	await _frames(3)
	var hp0 := foe.health
	var body := player.body_model()
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	for i in 120:
		await _tree().physics_frame
		if foe.health < hp0:
			owed = float(body.call("hit_stop_owed")) if body != null and body.has_method("hit_stop_owed") else 0.0
			break
	var heavy_stop := float(Impact.last.get("stop", 0.0))
	print("    a greatsword's light holds %.3f s (a sword's %.3f s); owed at the blow %.3f s" % [heavy_stop, stop, owed])
	assert_gt(heavy_stop, stop, "a greatsword holds no longer than a sword")
	if body != null:
		assert_gt(owed, 0.0, "the picture was not held on the blow")
		await _frames(30)
		assert_near(float(body.call("hit_stop_owed")), 0.0, 0.0001, "the picture has not caught up half a second on")


func test_the_camera_kicks_on_a_blow_and_not_with_the_setting_off() -> void:
	var rig := player.camera_rig
	var foe := _foe(FOE, Vector3(0.0, 0.02, -1.4))
	await _frames(3)
	var hit := foe.build_hit({"name": "t", "damage": 1.0, "poise_damage": 1.0, "weapon_class": "sword"})
	hit.origin = foe.global_position
	hit.attacker = foe
	Impact.land(player, hit, "hit")
	assert_gt(rig._kick, 0.0, "a blow taken did not kick the camera")
	await _frames(20)
	assert_near(rig._kick * rig._kick_left(), 0.0, 0.001, "the kick has not died away in a third of a second")
	Settings.set_value("accessibility", "camera_shake", 0.0, false)
	rig._kick = 0.0
	Impact.land(player, hit, "hit")
	assert_eq(rig._kick, 0.0, "the kick came with Camera kick at 0")


func _bursts(kind: String) -> int:
	var n := 0
	for p in _tree().get_nodes_in_group(ImpactFx.GROUP):
		if p is CPUParticles3D and str(p.name).begins_with("Impact_%s" % kind) and not p.is_queued_for_deletion():
			n += (p as CPUParticles3D).amount
	return n


func _clear_bursts() -> void:
	for p in _tree().get_nodes_in_group(ImpactFx.GROUP):
		p.free()


func test_what_a_blow_knocks_off_what_it_hits() -> void:
	var foe := _foe(FOE, Vector3(0.0, 0.02, -1.4))
	await _frames(3)
	var hit := HitData.new()
	hit.kind = "slash"
	hit.weapon_class = "sword"
	hit.weight = 3.0
	hit.attacker = player
	hit.origin = player.global_position
	for m: String in ["flesh", "metal", "stone", "wood"]:
		foe.body_material = m
		Impact.land(foe, hit, "hit")
	var blood := _bursts("blood")
	var sparks := _bursts("sparks")
	print("    one sword blow on each: blood %d, sparks %d, dust %d, chips %d, splinters %d, stains %d" % [
			blood, sparks, _bursts("dust"), _bursts("chips"), _bursts("splinters"), _tree().get_nodes_in_group(ImpactFx.GROUP).filter(func(n: Node) -> bool: return str(n.name).begins_with("Impact_stain")).size()])
	assert_gt(blood, 0, "flesh did not bleed")
	assert_gt(sparks, 0, "armour did not spark")
	assert_gt(_bursts("dust"), 0, "stone raised no dust")
	assert_gt(_bursts("chips"), 0, "stone gave no chips")
	assert_gt(_bursts("splinters"), 0, "wood gave no splinters")
	var stain: MeshInstance3D = null
	for n in _tree().get_nodes_in_group(ImpactFx.GROUP):
		if str(n.name).begins_with("Impact_stain"):
			stain = n
	assert_true(stain != null, "the blood left no stain")
	if stain != null:
		assert_near(stain.global_position.y, 0.012, 0.01, "the stain is not on the floor")
		assert_true(stain.global_transform.basis.z.normalized().dot(Vector3.UP) > 0.99, "the stain does not lie flat")
	# where the blow met the body: on its surface, toward the one who struck, at body height
	var p: Vector3 = Impact.last["point"]
	assert_true(p.z > foe.global_position.z and p.y > 0.3 and p.y < 1.9, "the blow met the body at %s" % p)
	_clear_bursts()
	Settings.set_value("gameplay", "blood", false, false)
	foe.body_material = "flesh"
	Impact.land(foe, hit, "hit")
	assert_eq(_bursts("blood"), 0, "flesh bled with Blood off")
	_clear_bursts()
	Settings.set_value("accessibility", "reduce_flashing", true, false)
	foe.body_material = "metal"
	Impact.land(foe, hit, "hit")
	assert_true(_bursts("sparks") > 0 and _bursts("sparks") <= sparks / 2 + 1, "Less flashing threw %d sparks against %d" % [_bursts("sparks"), sparks])


func test_a_heavy_swing_streaks_while_its_blow_is_live() -> void:
	player.equip_weapon(GREATSWORD)
	await _frames(3)
	var most := 0
	var during_light := 0
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	for i in 90:
		await _tree().physics_frame
		var t := _trail()
		if t != null:
			during_light = maxi(during_light, t.sample_count())
	await _free_again()
	Input.action_press("attack_heavy")
	await _frames(2)
	Input.action_release("attack_heavy")
	var live_frames := 0
	for i in 150:
		await _tree().physics_frame
		var t := _trail()
		if t != null and t.active:
			live_frames += 1
			most = maxi(most, t.sample_count())
	var t_end := _trail()
	print("    a greatsword's heavy streaked %d frames, %d moments at most; a light %d" % [live_frames, most, during_light])
	assert_eq(during_light, 0, "a light swing streaked")
	assert_gt(live_frames, 3, "the heavy never streaked")
	assert_gt(most, 3, "the streak holds too little of the swing")
	assert_true(t_end == null or (not t_end.active and t_end.sample_count() == 0), "the streak outlived the swing")


func _trail() -> WeaponTrail:
	var w := Impact.held_weapon(player)
	return w.get_node_or_null("Trail") as WeaponTrail if w != null else null


func test_a_heavy_drives_the_foe_back_and_a_light_does_not() -> void:
	# the shove each blow puts on a foe that stands still (Actor.shove_left: the metres it carries)
	var got := {}
	for row: Array in [[SWORD, "attack_light"], [SWORD, "attack_heavy"], [GREATSWORD, "attack_heavy"]]:
		player.equip_weapon(row[0])
		var foe := _foe(FOE, Vector3(0.0, 0.02, -1.5))
		await _frames(3)
		var hp0 := foe.health
		var most := 0.0
		var away := 0.0
		Input.action_press(row[1])
		await _frames(2)
		Input.action_release(row[1])
		for i in 180:
			await _tree().physics_frame
			if foe.shove_left() > most:
				most = foe.shove_left()
				away = -foe.shove.normalized().z
			if foe.health < hp0 and i > 0 and foe.shove_left() < most:
				break
		got["%s %s" % [str(row[0]).get_file(), row[1]]] = most
		assert_true(most <= 0.0 or away > 0.9, "%s drove the foe some way other than away (%.2f)" % [row, away])
		foe.free()
		await _free_again()
	print("    driven back (m): %s" % str(got))
	assert_near(float(got["iron_sword attack_light"]), 0.0, 0.001, "a light drove the foe back")
	assert_gt(float(got["iron_sword attack_heavy"]), 0.15, "a sword's heavy did not drive the foe back")
	assert_gt(float(got["iron_greatsword attack_heavy"]), float(got["iron_sword attack_heavy"]), "a greatsword drives no further than a sword")
