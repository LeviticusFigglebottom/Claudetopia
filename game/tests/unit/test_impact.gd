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
## How near the body's middle the blade is when a blow is shown: its radius (0.35 m) and a
## frame of a swing's travel.
const REACHED_M := 0.65

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
	var sword_gap := float(Impact.last.get("blade_gap", -1.0))
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
	var body := player.body_model()
	var shown := int(Impact.last.get("shown_at", -1))
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	for i in 240:
		await _tree().process_frame
		if int(Impact.last.get("shown_at", -1)) != shown:
			owed = float(body.call("hit_stop_owed")) if body != null and body.has_method("hit_stop_owed") else 0.0
			break
	var heavy_stop := float(Impact.last.get("stop", 0.0))
	var heavy_gap := float(Impact.last.get("blade_gap", -1.0))
	print("    a greatsword's light holds %.3f s (a sword's %.3f s); owed at the blow %.3f s" % [heavy_stop, stop, owed])
	assert_gt(heavy_stop, stop, "a greatsword holds no longer than a sword")
	# and it was shown as the blade reached the body (a frame before it would be inside it: the
	# blade is then within its radius and one frame's travel), not while it was still over the head
	print("    the greatsword's blow was shown with the blade %.2f m from the foe's middle (a sword's %.2f m)" % [heavy_gap, sword_gap])
	assert_true(heavy_gap >= 0.0 and heavy_gap <= REACHED_M, "the greatsword's blow was shown with the blade %.2f m off the body" % heavy_gap)
	assert_true(sword_gap >= 0.0 and sword_gap <= REACHED_M, "the sword's blow was shown with the blade %.2f m off the body" % sword_gap)
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
	hit.attacker = null     # a blow with no blade to wait for is shown at once
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
	# the bare materials: the foe's dressing set aside, so its body_material decides
	foe._armoured = {}
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



## What a blow leaves outlives what it hit, and a blow can outlive its body. Stains free themselves
## when they have faded, or go with the scene they lie in, and a later blow must not trip on them.
## The list of stains kept the freed ones, so past MOST_STAINS every bloody blow asked whether a
## freed stain was a Node: a SCRIPT ERROR each time (eleven in a full run, after this file's blows;
## in play, every blow after the 24th stain had faded). A blow still waiting for the blade to reach
## a body that is freed, or about to be, is not shown at all.
func test_a_blow_after_its_stains_and_its_foe_are_gone_says_nothing_wrong() -> void:
	var errors_before := ErrorLog.count("script_error") + ErrorLog.count("error")
	var logged_before := Log.error_count
	var foe := _foe(FOE, Vector3(0.0, 0.02, -1.4))
	await _frames(3)
	foe._armoured = {}
	foe.body_material = "flesh"
	var hit := HitData.new()
	hit.kind = "slash"
	hit.weapon_class = "sword"
	hit.weight = 3.0
	hit.attacker = player
	hit.origin = player.global_position
	# more stains than are kept, then all of them gone at once, as their fades or the scene's end
	# free them; then more blows
	for i in ImpactFx.MOST_STAINS + 4:
		Impact.land(foe, hit, "hit")
	_clear_bursts()
	for i in 3:
		Impact.land(foe, hit, "hit")
	await _frames(2)
	# (a stain is the group's only mesh; siblings of one name are renamed, so not by name)
	var stains := 0
	for n in _tree().get_nodes_in_group(ImpactFx.GROUP):
		if n is MeshInstance3D and not n.is_queued_for_deletion():
			stains += 1
	assert_eq(stains, 3, "the blows after the stains were freed left %d stains" % stains)
	# a blow waiting for the blade in the hand to reach its body, and the body freed, or queued to
	# be, before it does
	player.equip_weapon(SWORD)
	player.weapon_drawn = true
	player._last_fight_act = Actor.now()
	player._dress_hands()
	await _frames(2)
	assert_false(Impact.blade_of(player).is_empty(), "the sword is not in the hand, so no blow waits for it")
	for how: String in ["freed", "queued"]:
		var gone := _foe(FOE, Vector3(0.6, 0.02, -2.4))
		await _frames(2)
		Impact.last = {}
		Impact.land(gone, hit, "hit")
		assert_eq(gone.find_children("ImpactContact", "", false, false).size(), 1, "the blow did not wait for the blade")
		if how == "freed":
			gone.free()
		else:
			gone.queue_free()
		await _frames(int(Impact.MOST_WAIT_S / FRAME) + 4)
		assert_true(Impact.last.is_empty(), "a blow was shown on a foe %s before the blade reached it" % how)
	var errors := ErrorLog.count("script_error") + ErrorLog.count("error") - errors_before
	assert_eq(errors, 0, "the blows after their stains and their foe were gone reported %d errors" % errors)
	assert_eq(Log.error_count - logged_before, 0, "the blows logged errors")

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



## Sparks and blood follow what a foe is dressed in (EnemyDress), not its armour value: plate on
## the chest and a helm spark, the legs under them bleed, a robed caster with armour 12 bleeds, a
## raider in plate with armour 10 sparks, and the dead give dust.
func test_sparks_and_blood_follow_what_a_foe_wears() -> void:
	var rows := [
		# [foe, height as a share of its height, the kind of burst it must give, one it must not]
		["core:enemy/tolling_knight", 0.65, "sparks", "blood"],
		["core:enemy/tolling_knight", 0.92, "sparks", "blood"],
		["core:enemy/tolling_knight", 0.3, "", "sparks"],
		["core:enemy/hart_knight", 0.3, "blood", "sparks"],
		["core:enemy/clanless_outrider", 0.65, "sparks", "blood"],
		["core:boss/she_who_waits", 0.65, "dust", "sparks"],
		["core:enemy/roadside_bandit", 0.65, "blood", "sparks"],
		["core:enemy/bell_bearer", 0.3, "dust", "blood"],
	]
	var seen: Array[String] = []
	for row: Array in rows:
		if not ContentDB.has(str(row[0])):
			continue
		var foe := _foe(str(row[0]), Vector3(0.0, 0.02, -1.4))
		await _frames(2)
		_clear_bursts()
		var point := foe.global_position + Vector3.UP * foe.capsule_height * float(row[1]) + Vector3(0, 0, 0.3)
		var blow := {"victim": foe, "attacker": player, "force": 0.5, "result": "hit", "push": Vector3(0, 0, -1),
				"kind": "slash", "material": foe.body_material, "sound": false}
		Impact.show(blow, point)
		seen.append("%s at %.2f: %s (armour %.0f)" % [Ids.name_of(str(row[0])), float(row[1]), Impact.last.get("material", "?"), foe.armour_flat])
		if str(row[2]) != "":
			assert_gt(_bursts(str(row[2])), 0, "%s struck at %.2f of its height gave no %s" % [row[0], row[1], row[2]])
		assert_eq(_bursts(str(row[3])), 0, "%s struck at %.2f of its height gave %s" % [row[0], row[1], row[3]])
		foe.free()
		_clear_bursts()
	print("    %s" % "; ".join(seen))
