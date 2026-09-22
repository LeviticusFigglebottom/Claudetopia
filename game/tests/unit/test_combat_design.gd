extends TestCase
## DESIGN §5.3 Combat, measured rather than read.
##
## Nobody has played the combat, so these stand in for hands. Every number in the Combat section
## is produced by the real thing -- the Player controller's own states, fed through the real input
## actions on a real floor, hitting and being hit by a real Enemy, with its StaminaComponent,
## PoiseComponent, WeaponInstance, StatusEffects and SpellCaster -- and the value the game actually
## gave is compared with the design's.
##
## Timings are counted in physics frames, which is what the game counts them in, so every timing
## here has the resolution of one frame (16.7 ms at 60 Hz). Frames are read off the engine at the
## moment something happens -- a signal the controller emits, or the frame a value first changes
## -- never off a loop counter, because a coroutine resumes at the *start* of a physics frame,
## before the nodes have processed it, and a loop index is therefore one frame out in a direction
## that depends on what is being watched.
##
## Each measurement prints a MEASURE line, so the audit table can be rebuilt from any run:
##     ./run.sh test --filter=test_combat_design | grep MEASURE

const FRAME := 1.0 / 60.0
const SWORD := "core:item/iron_sword"
const DAGGER := "core:item/iron_dagger"
const ROUND_SHIELD := "core:item/round_shield"
const CLAN_SHIELD := "core:item/clan_shield"
const FOE := "core:enemy/roadside_bandit"
const KNIGHT := "core:enemy/tolling_knight"
const MOVES: Array[String] = ["move_forward", "move_back", "move_left", "move_right"]

var root: Node3D
var player: Player


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	root = Node3D.new()
	root.name = "DesignAudit"
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
	_release_all()
	if is_instance_valid(root):
		root.free()
	root = null
	player = null


# --- harness --------------------------------------------------------------------------------------

static func _frame() -> int:
	return Engine.get_physics_frames()


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


func _until(predicate: Callable, timeout: float) -> bool:
	for i in int(timeout / FRAME):
		if bool(predicate.call()):
			return true
		await _tree().physics_frame
	return bool(predicate.call())


func _tap(action: String, frames: int = 2) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)
	await _frames(1)


func _release_all() -> void:
	for a in Player.ACTIONS:
		Input.action_release(a)
	for a in MOVES:
		Input.action_release(a)


func _free_again() -> void:
	_release_all()
	await _until(func() -> bool: return player.state == Player.State.FREE and player.can_act(), 4.0)
	player.stamina_comp.refill()
	await _frames(2)


## A foe that stands where it is put and does nothing on its own: its brain and its steering are
## off, its hurtbox, poise, statuses and animation are the real ones.
func _foe(id: String, at: Vector3, yaw := PI) -> Enemy:
	var e := Enemy.new()
	e.configure(id)
	root.add_child(e)
	e.global_position = at
	e.rotation.y = yaw
	e.spawn_position = at
	e.spawn_yaw = yaw
	e.brain.post = at
	e.perception.enabled = false
	e.set_physics_process(false)
	return e


## The hit a foe's named attack delivers, built the way its own hitbox builds it.
func _foe_hit(e: Enemy, attack_name: String, amount := -1.0) -> HitData:
	var attack := {}
	for a in e.attacks:
		if str(a.get("name", "")) == attack_name:
			attack = a
	var hit := e.build_hit(attack)
	if amount >= 0.0:
		hit.amount = amount
	hit.origin = e.global_position
	return hit


func _check(what: String, design: float, measured: float, tolerance: float, unit := "", note := "") -> void:
	print("MEASURE | %s | %s | %s | %s" % [what, _fmt(design, unit), _fmt(measured, unit), note])
	assert_near(measured, design, tolerance, "%s: design %s, measured %s" % [what, _fmt(design, unit), _fmt(measured, unit)])


func _say(what: String, design: String, measured: String, note := "") -> void:
	print("MEASURE | %s | %s | %s | %s" % [what, design, measured, note])


static func _fmt(v: float, unit: String) -> String:
	match unit:
		"s": return "%.3f s" % v
		"/s": return "%.2f/s" % v
		"x": return "%.3f×" % v
		"%": return "%.1f%%" % (v * 100.0)
	return ("%.2f" % v) + (" " + unit if unit != "" else "")


static func _event_time(timing: Dictionary, event_name: String) -> float:
	for e in timing.get("events", []):
		if str(e["name"]) == event_name:
			return float(e["t"])
	return -1.0


# --- pools ----------------------------------------------------------------------------------------

## Stamina is 100 + 8·Endurance and mana 60 + 6·Will, and "each level: +1 attribute ... Endurance
## → stamina, Will → mana" (§5.6). The attributes are the character's -- the ones a level raises
## and the skills screen shows -- so the pools have to follow them.
func test_stamina_and_mana_follow_the_characters_attributes() -> void:
	await _frames(2)
	var prog := player.progression() as Progression
	assert_true(prog != null, "the player carries a Progression")
	if prog == null:
		return
	var e := prog.attribute("endurance")
	var w := prog.attribute("will")
	var v := prog.attribute("vigour")
	_check("stamina pool at the character's Endurance %d" % e, 100.0 + 8.0 * e, player.max_stamina, 0.01, "", "100 + 8·Endurance")
	_check("mana pool at the character's Will %d" % w, 60.0 + 6.0 * w, player.max_mana, 0.01, "", "60 + 6·Will")
	_check("health at the character's Vigour %d" % v, DamageModel.hp_max(v), player.max_health, 0.01, "", "DamageModel.hp_max")
	prog.leveling.attribute_points += 2
	assert_true(prog.spend_attribute("endurance"))
	assert_true(prog.spend_attribute("will"))
	await _frames(1)
	_check("stamina pool after a level's point in Endurance", 100.0 + 8.0 * (e + 1), player.max_stamina, 0.01)
	_check("mana pool after a level's point in Will", 60.0 + 6.0 * (w + 1), player.max_mana, 0.01)


# --- stamina costs, regen -------------------------------------------------------------------------

func test_what_each_action_costs() -> void:
	player.equip_weapon(SWORD)
	await _frames(3)
	var s0 := player.stamina
	await _tap("attack_light")
	_check("light attack, iron sword", 18.0, s0 - player.stamina, 0.01, "st")
	await _free_again()
	s0 = player.stamina
	Input.action_press("attack_heavy")
	await _frames(3)
	var heavy := s0 - player.stamina
	Input.action_release("attack_heavy")
	_check("heavy attack, iron sword", 32.0, heavy, 0.01, "st")
	await _free_again()
	s0 = player.stamina
	await _tap("dodge")
	_check("dodge", 22.0, s0 - player.stamina, 0.01, "st")
	await _free_again()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(12)
	assert_true(player.is_sprinting, "holding sprint on the floor sprints")
	s0 = player.stamina
	await _frames(60)
	var drained := s0 - player.stamina
	Input.action_release("sprint")
	Input.action_release("move_forward")
	_check("sprint, per second", 8.0, drained, 0.15, "st")
	await _free_again()
	# A weapon states its own costs (CONTRACTS §7): the design's 18 and 32 are a sword's.
	player.equip_weapon(DAGGER)
	await _frames(2)
	s0 = player.stamina
	await _tap("attack_light")
	var dagger_def: Dictionary = ContentDB.get_or_empty(DAGGER).get("weapon", {})
	_check("light attack, iron dagger (its own data)", float(dagger_def.get("stamina_light", 18.0)), s0 - player.stamina, 0.01, "st")


## Regen 30/s after 0.8 s: from the frame the dodge spent it to the first frame that gave any back,
## then the rate over the half second after that.
func test_stamina_comes_back_at_30_a_second_after_0_8_s() -> void:
	await _frames(3)
	var spent := {"at": -1}
	var on_dodge := func(_d: Vector3) -> void: spent["at"] = _frame()
	player.dodge_started.connect(on_dodge)
	Input.action_press("dodge")
	await _frames(2)
	Input.action_release("dodge")
	await _until(func() -> bool: return int(spent["at"]) >= 0, 1.0)
	player.dodge_started.disconnect(on_dodge)
	var prev := player.stamina
	var back_at := -1
	var at_back := 0.0
	for i in 120:
		await _tree().physics_frame
		if player.stamina > prev + 0.0001:
			back_at = _frame() - 1          # the frame that just ran is the one that gave it back
			at_back = player.stamina
			break
		prev = player.stamina
	await _frames(30)
	var rate := (player.stamina - at_back) / (30.0 * FRAME)
	assert_true(back_at > int(spent["at"]), "the dodge spent stamina and it came back")
	_check("stamina regen delay", 0.8, float(back_at - int(spent["at"])) * FRAME, FRAME * 1.01, "s")
	_check("stamina regen rate", 30.0, rate, 0.2, "/s")


# --- commitment: buffer, chain, charge, cancel ----------------------------------------------------

## "Input buffered 0.25 s": a dodge pressed while staggered comes out the moment the stagger lets
## go, if it was pressed no more than a quarter second before the body could act on it.
func test_a_press_waits_a_quarter_second_for_the_body() -> void:
	await _frames(3)
	var waited_and_fired: Array[float] = []
	var dropped := 0
	for early in [9, 13, 14, 15, 17, 21]:
		player.stamina_comp.refill()
		player.stagger(1.0)
		var free_at := Actor.now() + 1.0
		var started := {"at": -1}
		var on_dodge := func(_d: Vector3) -> void: started["at"] = _frame()
		player.dodge_started.connect(on_dodge)
		var pressed_at := -1
		for i in 120:
			var left := int(round((free_at - Actor.now()) / FRAME))
			if pressed_at < 0 and left <= early:
				Input.action_press("dodge")
				pressed_at = _frame()            # the controller reads it on this frame
			elif pressed_at >= 0 and _frame() >= pressed_at + 2:
				Input.action_release("dodge")
			await _tree().physics_frame
			if int(started["at"]) >= 0 or (pressed_at >= 0 and _frame() > pressed_at + 40):
				break
		player.dodge_started.disconnect(on_dodge)
		if int(started["at"]) >= 0:
			waited_and_fired.append(float(int(started["at"]) - pressed_at) * FRAME)
		else:
			dropped += 1
		await _free_again()
	var longest := 0.0
	for a in waited_and_fired:
		longest = maxf(longest, a)
	_check("input buffer (longest wait that still fired)", 0.25, longest, FRAME * 1.01, "s",
		"%d of 6 early presses fired, %d dropped" % [waited_and_fired.size(), dropped])
	assert_true(dropped >= 1, "a press made well before the body could act is dropped")


## "Chains of up to 3 lights": pressed at every chance, a one-handed weapon strings three and the
## fourth press begins a new chain.
func test_a_one_handed_chain_is_three_lights() -> void:
	player.equip_weapon(SWORD)
	await _frames(3)
	var seen: Array[int] = []
	var on_attack := func(kind: String, index: int) -> void:
		if kind == "light":
			seen.append(index)
	player.attack_started.connect(on_attack)
	for i in 300:
		if i % 5 == 0:
			Input.action_press("attack_light")
		elif i % 5 == 2:
			Input.action_release("attack_light")
		player.stamina_comp.refill()
		await _tree().physics_frame
		if seen.size() >= 4:
			break
	player.attack_started.disconnect(on_attack)
	Input.action_release("attack_light")
	var longest := 0
	var run := 0
	var prev := -1
	for idx in seen:
		run = run + 1 if idx == prev + 1 else 1
		longest = maxi(longest, run)
		prev = idx
	_check("light chain length, one-handed", 3.0, float(longest), 0.0, "", "indices %s" % str(seen))
	assert_true(seen.size() >= 4 and seen[3] == 0, "the fourth light begins a new chain: %s" % str(seen))


## "Heavies charge": a heavy tapped and a heavy held to full, each measured as the charge factor in
## the raw hit it put on a foe -- the hit before armour, over the same heavy with no charge at all.
func test_a_held_heavy_hits_harder_than_a_tapped_one() -> void:
	player.equip_weapon(SWORD)
	var foe := _foe(FOE, Vector3(0.0, 0.02, -1.4))
	await _frames(3)
	var uncharged := player.weapon.build_hit("heavy", 0, 0.0, player.get_skill(player.weapon.skill_id)).amount
	var got := {"raw": 0.0, "at": -1}
	var on_hit := func(h: HitData, _o: String) -> void:
		got["raw"] = h.amount * h.crit_mult
		got["at"] = _frame()
	foe.hit_taken.connect(on_hit)
	var start := _frame()
	await _tap("attack_heavy", 2)
	await _until(func() -> bool: return int(got["at"]) >= 0, 3.0)
	var tapped := float(got["raw"]) / uncharged
	var tapped_after := float(int(got["at"]) - start) * FRAME
	await _free_again()
	foe.full_restore()
	got["at"] = -1
	start = _frame()
	Input.action_press("attack_heavy")
	for i in int(round((DamageModel.HEAVY_CHARGE_TIME + 0.4) / FRAME)):
		await _tree().physics_frame
		if int(got["at"]) >= 0:
			break
	Input.action_release("attack_heavy")
	await _until(func() -> bool: return int(got["at"]) >= 0, 3.0)
	var held := float(got["raw"]) / uncharged
	var held_after := float(int(got["at"]) - start) * FRAME
	foe.hit_taken.disconnect(on_hit)
	_check("charge factor, heavy tapped", 1.0, tapped, 0.03, "x", "landed %.3f s after the press" % tapped_after)
	_check("charge factor, heavy held to full", 1.5, held, 0.01, "x", "landed %.3f s after the press" % held_after)
	assert_gt(held_after, tapped_after + 0.05, "a held heavy lands later than a tapped one")


## "Cancel only into dodge after the active frames": a dodge pressed in the wind-up of a swing does
## not come out before the hit window has closed, and one pressed inside the window comes out as
## it closes.
func test_a_swing_is_cancelled_into_a_dodge_only_after_it_has_swung() -> void:
	player.equip_weapon(SWORD)
	await _frames(3)
	var timing := player.weapon.timing_for("light", 0)
	var hit_start := _event_time(timing, "hit_start")
	var hit_end := _event_time(timing, "hit_end")
	var outs: Array[float] = []
	for press_at in [0.08, hit_start + 0.5 * (hit_end - hit_start)]:
		var marks := {"attack": -1, "dodge": -1}
		var on_attack := func(_k: String, _i: int) -> void:
			if int(marks["attack"]) < 0:
				marks["attack"] = _frame()
		var on_dodge := func(_d: Vector3) -> void: marks["dodge"] = _frame()
		player.attack_started.connect(on_attack)
		player.dodge_started.connect(on_dodge)
		Input.action_press("attack_light")
		await _frames(2)
		Input.action_release("attack_light")
		await _until(func() -> bool: return int(marks["attack"]) >= 0, 1.0)
		var pressed := -1
		for i in 120:
			var since := float(_frame() - int(marks["attack"])) * FRAME
			if pressed < 0 and since >= press_at:
				Input.action_press("dodge")
				pressed = _frame()
			elif pressed >= 0 and _frame() >= pressed + 2:
				Input.action_release("dodge")
			await _tree().physics_frame
			if int(marks["dodge"]) >= 0:
				break
		player.attack_started.disconnect(on_attack)
		player.dodge_started.disconnect(on_dodge)
		if int(marks["dodge"]) >= 0:
			outs.append(float(int(marks["dodge"]) - int(marks["attack"])) * FRAME)
		await _free_again()
	var earliest := INF
	for o in outs:
		earliest = minf(earliest, o)
	_say("dodges out of a light swing (pressed in the wind-up, and in the hit window)",
		"none before hit_end %.3f s" % hit_end, str(outs.map(func(o: float) -> String: return "%.3f s" % o)),
		"hit window %.3f-%.3f s" % [hit_start, hit_end])
	assert_false(outs.is_empty(), "a dodge pressed in the hit window comes out")
	assert_true(earliest >= hit_end - FRAME * 0.5, "no dodge came out before the hit window closed")
	_check("earliest dodge out of a light swing", hit_end, earliest, FRAME * 1.5, "s")


# --- the roll and load ----------------------------------------------------------------------------

## "0.6 s roll, i-frames 0.08–0.38 s. Heavy load lengthens it and cuts i-frames": the roll's
## length and the frames it is invulnerable on, at a load inside each band.
func test_the_roll_and_its_iframes_at_each_load() -> void:
	await _frames(3)
	for band in [[0.1, "light"], [0.5, "medium"], [0.9, "heavy"], [1.2, "overloaded"]]:
		var expected := DamageModel.dodge_params(float(band[0]))
		player.stamina_comp.refill()
		player.load_ratio = float(band[0])
		var marks := {"at": -1}
		var on_dodge := func(_d: Vector3) -> void: marks["at"] = _frame()
		player.dodge_started.connect(on_dodge)
		var first := -1
		var last := -1
		var ended := -1
		Input.action_press("dodge")
		for i in 100:
			await _tree().physics_frame
			if i == 1:
				Input.action_release("dodge")
			if int(marks["at"]) < 0:
				continue
			# A hit landing on this frame is judged at this frame's clock: that is what counts.
			if player.is_invulnerable():
				if first < 0:
					first = _frame()
				last = _frame()
			if player.state != Player.State.DODGE:
				ended = _frame() - 1
				break
		player.dodge_started.disconnect(on_dodge)
		var d := int(marks["at"])
		var tier := str(band[1])
		_check("roll length, %s load" % tier, float(expected["duration"]), float(ended - d) * FRAME, FRAME * 1.01, "s")
		_check("i-frames open, %s load" % tier, float(expected["iframe_start"]), float(first - d) * FRAME, FRAME * 1.01, "s")
		_check("i-frames close, %s load" % tier, float(expected["iframe_end"]), float(last + 1 - d) * FRAME, FRAME * 1.01, "s")
		if tier == "light":
			assert_near(float(expected["duration"]), DamageModel.DODGE_DURATION, 0.0001, "the light roll is the design's 0.6 s")
		await _free_again()


## What counts as load: everything worn and wielded, against the character's own Endurance; and a
## bag carried past what the character can carry puts the roll in the overloaded band.
func test_load_is_everything_worn_and_what_is_carried() -> void:
	await _frames(2)
	var bag := player.get_node("Inventory") as Inventory
	var doll := player.get_node("Equipment") as Equipment
	var worn := 0.0
	for id in ["core:item/clan_bone_helm", "core:item/clan_plate", "core:item/clan_plate_gauntlets", "core:item/clan_plate_sabatons", SWORD]:
		bag.add(id, 1)
		assert_true(doll.equip(id), "equips %s" % id)
		worn += float(ContentDB.get_or_empty(id).get("weight", 0.0))
	await _frames(2)
	var prog := player.progression() as Progression
	var e := float(prog.attribute("endurance"))
	var capacity := Player.LOAD_CAPACITY_BASE + Player.LOAD_CAPACITY_PER_ENDURANCE * e
	_check("load, a full plate kit and a sword", worn / capacity, player.load_ratio, 0.005, "%",
		"%.1f kg worn over %.0f" % [worn, capacity])
	var ingot := maxf(float(ContentDB.get_or_empty("core:item/iron_ingot").get("weight", 1.0)), 0.1)
	bag.add("core:item/iron_ingot", int(ceil(bag.capacity() / ingot)) + 2)
	await _frames(2)
	assert_true(bag.is_overloaded(), "the bag is past what the character can carry")
	_say("load with the bag past its capacity", "> 100% (overloaded roll)", _fmt(player.load_ratio, "%"))
	assert_gt(player.load_ratio, 1.0, "carrying past capacity puts the roll in the overloaded band")


## DESIGN §5.7: "Load affects dodge and stamina regen".
func test_load_slows_stamina_regen() -> void:
	await _frames(2)
	var rates := {}
	for band in [0.1, 0.9, 1.2]:
		player.load_ratio = band
		player.stamina_comp.spend(80.0)
		await _frames(int(round((DamageModel.STAMINA_REGEN_DELAY + 0.1) / FRAME)))
		var s0 := player.stamina
		await _frames(30)
		rates[band] = (player.stamina - s0) / (30.0 * FRAME)
		player.stamina_comp.refill()
	_say("stamina regen at a light / heavy / overloaded load", "slower as the load rises",
		"%.1f / %.1f / %.1f per s" % [float(rates[0.1]), float(rates[0.9]), float(rates[1.2])])
	assert_near(float(rates[0.1]), 30.0, 0.3, "a light load regenerates at the full rate")
	assert_true(float(rates[0.9]) < float(rates[0.1]) - 1.0, "a heavy load regenerates more slowly")
	assert_true(float(rates[1.2]) < float(rates[0.9]) - 1.0, "an overloaded one more slowly still")


# --- defence: block, parry, riposte --------------------------------------------------------------

## "Block: stability scales damage and stamina cost" -- damage·(1−s) through the guard and
## damage·0.6·(1−s) off the bar, for a shield worn as armour, a shield carried as a weapon, and a
## sword on its own.
func test_a_guard_takes_what_its_stability_says() -> void:
	var foe := _foe(FOE, Vector3(0.0, 0.02, -2.0))
	await _frames(3)
	for c in [[SWORD, ""], [SWORD, ROUND_SHIELD], [SWORD, CLAN_SHIELD]]:
		player.equip_weapon(str(c[0]))
		player.equip_offhand(str(c[1]))
		player.equip_armour("")
		player.full_restore()
		await _frames(2)
		var off_def := ContentDB.get_or_empty(str(c[1])) if str(c[1]) != "" else {}
		var stability := float(ContentDB.get_or_empty(str(c[0])).get("weapon", {}).get("stability", 0.0))
		if not off_def.is_empty():
			stability = float(off_def.get("armour", off_def.get("weapon", {})).get("stability", 0.0))
		Input.action_press("block")
		await _frames(int(0.35 / FRAME))
		var hp0 := player.health
		var st0 := player.stamina
		var outcome := player.take_hit(_foe_hit(foe, "slash", 20.0))
		var through := hp0 - player.health
		var cost := st0 - player.stamina
		Input.action_release("block")
		var label := Ids.name_of(str(c[1]) if str(c[1]) != "" else str(c[0]))
		assert_eq(outcome, "blocked", "%s raised is a block" % label)
		_check("damage through the guard of a 20 hit, %s (stability %.2f)" % [label, stability], maxf(1.0, 20.0 * (1.0 - stability)), through, 0.01)
		_check("stamina that guard cost, %s" % label, 20.0 * 0.6 * (1.0 - stability), cost, 0.01)
		await _frames(3)


## "Parry: block pressed within 0.18 s before a hit with a parry-capable item → attacker enters
## riposte_open for 2 s; riposte deals 3× damage."
func test_the_parry_window_the_riposte_and_its_damage() -> void:
	player.equip_weapon(SWORD)
	player.equip_offhand(ROUND_SHIELD)
	var foe := _foe(FOE, Vector3(0.0, 0.02, -2.0))
	await _frames(3)
	var parried: Array[float] = []
	var missed: Array[float] = []
	for k in [2, 6, 9, 10, 11, 12, 15]:
		foe.riposte_open_until = -100.0
		foe.stunned_until = -100.0
		player.full_restore()
		Input.action_release("block")
		await _frames(3)
		Input.action_press("block")
		await _frames(k)
		var dt := Actor.now() - player.parry_pressed_at
		var outcome := player.take_hit(_foe_hit(foe, "slash"))
		if outcome == "parried":
			parried.append(dt)
		else:
			missed.append(dt)
		Input.action_release("block")
		await _frames(2)
	var longest := 0.0
	for p in parried:
		longest = maxf(longest, p)
	var shortest_miss := INF
	for m in missed:
		shortest_miss = minf(shortest_miss, m)
	_check("parry window (latest press that parries)", DamageModel.PARRY_WINDOW, longest, FRAME * 1.01, "s",
		"a press %.3f s before the hit is too early" % shortest_miss)
	assert_true(shortest_miss > longest, "a press further back than the window does not parry")
	# How long the attacker stays open.
	foe.riposte_open_until = -100.0
	foe.stunned_until = -100.0
	player.full_restore()
	Input.action_press("block")
	await _frames(3)
	assert_eq(player.take_hit(_foe_hit(foe, "slash")), "parried")
	var opened := _frame()
	Input.action_release("block")
	await _until(func() -> bool: return not foe.is_riposte_open(), 4.0)
	_check("riposte_open after a parry", DamageModel.RIPOSTE_OPEN_DURATION, float(_frame() - opened) * FRAME, FRAME * 1.01, "s")
	# The riposte itself, against an ordinary first light from the same sword.
	foe.full_restore()
	foe.riposte_open_until = -100.0
	foe.stunned_until = -100.0
	player.full_restore()
	await _frames(2)
	Input.action_press("block")
	await _frames(3)
	player.take_hit(_foe_hit(foe, "slash"))
	Input.action_release("block")
	await _frames(2)
	var got := {"raw": 0.0, "crit": "-"}
	var hp0 := foe.health
	var on_hit := func(h: HitData, _o: String) -> void:
		got["raw"] = h.amount * h.crit_mult
		got["crit"] = h.crit_kind
	foe.hit_taken.connect(on_hit)
	await _tap("attack_light")
	await _until(func() -> bool: return str(got["crit"]) != "-", 3.0)
	foe.hit_taken.disconnect(on_hit)
	var dealt := hp0 - foe.health
	var light := player.weapon.build_hit("light", 0, 0.0, player.get_skill(player.weapon.skill_id))
	assert_eq(str(got["crit"]), "riposte", "a light pressed at an open foe is a riposte")
	_check("riposte over a first light (raw)", 3.0, float(got["raw"]) / maxf(light.amount, 0.001), 0.01, "x")
	_check("riposte damage, crit before armour", maxf(1.0, float(got["raw"]) - foe.armour_flat), dealt, 0.01, "",
		"armour %.0f comes off the tripled hit" % foe.armour_flat)


# --- poise ----------------------------------------------------------------------------------------

## "poise regens 4/s after 1.5 s. At 0 → stagger, poise resets."
func test_poise_comes_back_and_breaks_at_zero() -> void:
	var foe := _foe(FOE, Vector3(0.0, 0.02, -2.0))
	await _frames(3)
	var hit := HitData.new()
	hit.amount = 1.0
	hit.poise_damage = 10.0
	hit.attacker = player
	hit.origin = player.global_position
	var hit_at := _frame()
	foe.take_hit(hit)
	var prev := foe.poise
	var back_at := -1
	var at_back := 0.0
	for i in 150:
		await _tree().physics_frame
		if foe.poise > prev + 0.0001:
			back_at = _frame() - 1
			at_back = foe.poise
			break
		prev = foe.poise
	await _frames(30)
	var rate := (foe.poise - at_back) / (30.0 * FRAME)
	_check("poise regen delay", DamageModel.POISE_REGEN_DELAY, float(back_at - hit_at) * FRAME, FRAME * 1.01, "s")
	_check("poise regen rate", DamageModel.POISE_REGEN_PER_S, rate, 0.05, "/s")
	foe.poise_comp.reset()
	var broke := {"n": 0}
	var on_stagger := func() -> void: broke["n"] = int(broke["n"]) + 1
	foe.staggered.connect(on_stagger)
	var hits := 0
	while int(broke["n"]) == 0 and hits < 10:
		foe.take_hit(hit.copy())
		foe.health = foe.max_health
		hits += 1
	foe.staggered.disconnect(on_stagger)
	_say("stagger at zero poise", "stagger, poise back to %.0f" % foe.max_poise,
		"stagger on hit %d, poise %.0f, stunned %s" % [hits, foe.poise, str(foe.is_stunned())])
	assert_eq(int(broke["n"]), 1, "poise at zero staggers once")
	assert_near(foe.poise, foe.max_poise, 0.001, "and resets to full")
	assert_true(foe.is_stunned())


## "hyper-armour frames on heavies ignore poise damage below a threshold": a small hit landing in a
## heavy's wind-up takes no poise off the one swinging it -- the player's heavy as much as a
## brute's.
func test_a_heavy_in_its_wind_up_shrugs_off_a_small_hit() -> void:
	player.equip_weapon(SWORD)
	var foe := _foe(FOE, Vector3(0.0, 0.02, -2.0))
	await _frames(3)
	Input.action_press("attack_heavy")
	await _frames(6)
	assert_eq(player.state, Player.State.ATTACK, "the heavy is winding up")
	var p0 := player.poise
	var small := _foe_hit(foe, "slash", 5.0)
	small.poise_damage = 8.0
	player.take_hit(small)
	var lost := p0 - player.poise
	Input.action_release("attack_heavy")
	_check("poise a player's heavy loses to an 8-poise hit in its wind-up", 0.0, lost, 0.001)
	await _free_again()
	var brute := _foe("core:enemy/hedge_wight", Vector3(6.0, 0.02, -2.0))
	await _frames(2)
	var reaping := {}
	for a in brute.attacks:
		if str(a.get("name", "")) == "reaping_step":
			reaping = a
	brute._begin_melee(reaping)
	await _frames(3)
	var bp0 := brute.poise
	var poke := HitData.new()
	poke.amount = 1.0
	poke.poise_damage = 8.0
	poke.attacker = player
	poke.origin = player.global_position
	brute.take_hit(poke)
	_check("poise a brute's heavy loses to an 8-poise hit in its wind-up", 0.0, bp0 - brute.poise, 0.001)


# --- damage ---------------------------------------------------------------------------------------

## "Damage = weapon_base · skill_mult(1 + skill/200) · attack_mult · charge − armour_flat, then
## · (1 − resist), minimum 1" -- with the character's own skill, the one use raises.
func test_a_swing_deals_what_the_formula_says() -> void:
	player.equip_weapon(SWORD)
	var foe := _foe(FOE, Vector3(0.0, 0.02, -1.4))
	await _frames(3)
	var prog := player.progression() as Progression
	var skill := prog.effective_skill("one_handed") if prog != null else 10.0
	var base := float(ContentDB.get_or_empty(SWORD)["weapon"]["damage"])
	var hp0 := foe.health
	await _tap("attack_light")
	await _until(func() -> bool: return foe.health < hp0, 2.0)
	var expected := maxf(1.0, (base * (1.0 + skill / 200.0) - foe.armour_flat) * (1.0 - DamageModel.resist_of(foe.resists, "slash")))
	_check("first light, iron sword, on a bandit (armour %.0f)" % foe.armour_flat, expected, hp0 - foe.health, 0.01, "",
		"one-handed %.0f, the character's own" % skill)
	await _free_again()
	player.equip_weapon(DAGGER)
	var king := _foe(KNIGHT, Vector3(4.0, 0.02, -1.4))
	await _frames(2)
	var kh := HitData.new()
	var k_hp := king.health
	kh.amount = player.weapon.build_hit("light", 0, 0.0, player.get_skill(player.weapon.skill_id)).amount
	kh.kind = "pierce"
	kh.attacker = player
	kh.origin = player.global_position
	king.take_hit(kh)
	_check("a dagger light on a tolling knight's %.0f armour" % king.armour_flat, 1.0, k_hp - king.health, 0.001, "", "the design's minimum")


## Armour is what the character wears: a helm counts as much as a coat.
func test_armour_is_everything_worn() -> void:
	await _frames(2)
	var bag := player.get_node("Inventory") as Inventory
	var doll := player.get_node("Equipment") as Equipment
	var total := 0.0
	for id in ["core:item/clan_bone_helm", "core:item/wool_tunic", "core:item/leather_gloves", "core:item/leather_boots"]:
		bag.add(id, 1)
		doll.equip(id)
		total += float(ContentDB.get_or_empty(id)["armour"]["armour"])
	await _frames(2)
	_check("armour_flat wearing a helm, a tunic, gloves and boots", total, player.armour_flat, 0.001)


## "Crit (backstab, riposte, sneak attack) multiplies before armour": all three have to be things
## the game can do. The riposte is measured above; these are the other two.
func test_a_backstab_and_a_sneak_attack_are_crits() -> void:
	player.equip_weapon(DAGGER)
	var foe := _foe(FOE, Vector3(0.0, 0.02, -1.2), 0.0)     # facing away from the player
	await _frames(3)
	var got := {"crit": "-", "mult": 0.0}
	var on_hit := func(h: HitData, _o: String) -> void:
		got["crit"] = h.crit_kind
		got["mult"] = h.crit_mult
	foe.hit_taken.connect(on_hit)
	await _tap("attack_light")
	await _until(func() -> bool: return str(got["crit"]) != "-", 3.0)
	_say("a light from behind a foe", "backstab ×%.0f" % DamageModel.CRIT["backstab"],
		"%s ×%.1f" % [str(got["crit"]) if str(got["crit"]) != "" else "a plain hit", float(got["mult"])])
	assert_eq(str(got["crit"]), "backstab")
	await _free_again()
	foe.reset_to_spawn()
	foe.perception.enabled = false
	foe.rotation.y = PI            # facing the player now, but it has not noticed them
	foe.spawn_yaw = PI
	got["crit"] = "-"
	player.is_sneaking = true
	await _frames(3)
	await _tap("attack_light")
	await _until(func() -> bool: return str(got["crit"]) != "-", 3.0)
	foe.hit_taken.disconnect(on_hit)
	_say("a sneaking dagger light on a foe that has not noticed", "sneak ×%.0f" % DamageModel.CRIT["sneak_dagger"],
		"%s ×%.1f" % [str(got["crit"]) if str(got["crit"]) != "" else "a plain hit", float(got["mult"])])
	assert_eq(str(got["crit"]), "sneak")
	assert_near(float(got["mult"]), float(DamageModel.CRIT["sneak_dagger"]), 0.001)


# --- lock-on ------------------------------------------------------------------------------------

## "Lock-on: targets in a 30 m cone, cycle with stick flick / mouse wheel". Acquiring picks inside
## the cone; cycling keeps to it and never turns the lock round to something behind the player.
func test_lock_on_acquires_and_cycles_inside_the_cone() -> void:
	await _frames(2)
	var ahead := _foe(FOE, Vector3(0.0, 0.02, -8.0))
	var left := _foe(FOE, Vector3(-9.0, 0.02, -16.0))
	var behind := _foe(FOE, Vector3(0.0, 0.02, 12.0))
	var far := _foe(FOE, Vector3(2.0, 0.02, -34.0))
	await _frames(2)
	var origin := player.lock_point()
	var fwd := player.camera_rig.forward_flat()
	player.lock.acquire(origin, fwd)
	assert_eq(player.lock.target, ahead, "the nearest thing straight ahead is taken first")
	var visited := {}
	for i in 6:
		player.lock.cycle(origin, fwd, 1 if i % 2 == 0 else -1)
		visited[player.lock.target] = true
	var names: Array[String] = []
	for t in visited:
		names.append("ahead" if t == ahead else ("ahead-left" if t == left else ("behind" if t == behind else "past 30 m")))
	_say("lock-on cycling over foes 8 m ahead, 18 m ahead-left, 12 m behind and 34 m ahead",
		"ahead, ahead-left", ", ".join(names))
	assert_false(visited.has(behind), "cycling turned the lock round to a foe behind the player")
	assert_false(visited.has(far), "cycling reached a foe past 30 m")
	assert_true(visited.has(left), "cycling reaches the other foe inside the cone")
	player.lock.clear()
	player.global_position = Vector3(0.0, 0.02, 60.0)     # everything ahead is now past 30 m
	await _frames(2)
	player.lock.acquire(player.lock_point(), fwd)
	assert_true(player.lock.target == null, "nothing past 30 m is taken")


# --- status effects -----------------------------------------------------------------------------

## The nine the design lists, each doing what it says, on the player.
func test_the_nine_status_effects_do_what_they_say() -> void:
	await _frames(2)
	for id in ["burning", "chilled", "webbed", "silenced", "bleeding", "poisoned", "quieted", "stagger", "knockdown"]:
		assert_true(StatusEffects.RULES.has(id), "%s is a status the game knows" % id)
	var st := player.status
	var hp0 := player.health
	st.apply("burning")
	st.advance(4.0)
	_check("burning, its 4 s of 3 fire a second", 12.0, hp0 - player.health, 0.01)
	player.full_restore()
	st.apply("chilled")
	_check("chilled, speed", 0.6, player.speed_multiplier(), 0.001, "x")
	st.clear_all()
	st.apply("webbed")
	_check("webbed, speed", 0.45, player.speed_multiplier(), 0.001, "x")
	st.clear_all()
	var prog := player.progression() as Progression
	prog.learn_spell("core:spell/kindle_bolt")
	st.apply("silenced")
	var refused := {"why": ""}
	var on_fail := func(_id: String, why: String) -> void: refused["why"] = why
	player.caster.cast_failed.connect(on_fail)
	player.caster.cast("core:spell/kindle_bolt")
	player.caster.cast_failed.disconnect(on_fail)
	_say("silenced, and a saying the character knows", "refused", str(refused["why"]))
	assert_eq(str(refused["why"]), "silenced")
	st.clear_all()
	hp0 = player.health
	st.apply("bleeding")
	st.apply("bleeding")
	st.apply("bleeding")
	st.advance(1.0)
	_check("bleeding, three stacks, one second", 6.0, hp0 - player.health, 0.01)
	st.clear_all()
	hp0 = player.health
	st.apply("poisoned")
	st.advance(10.0)
	_check("poisoned, its 10 s", 15.0, hp0 - player.health, 0.01)
	st.clear_all()
	var standing: Node = Social.standing
	var r_was := int(standing.call("renown"))
	standing.call("set_renown", 50)          # renown cannot fall below nothing, so start with some
	st.apply("quieted")
	st.advance(10.0)
	_check("renown lost to 10 s of quieted", 2.0, float(50 - int(standing.call("renown"))), 0.001)
	standing.call("set_renown", r_was)
	st.clear_all()
	player.full_restore()
	player.stagger(0.8)
	assert_false(player.can_act(), "a staggered body cannot act")
	player.full_restore()
	player.knock_down(Vector3.FORWARD)
	assert_false(player.can_act(), "a knocked-down body cannot act")
	player.full_restore()
