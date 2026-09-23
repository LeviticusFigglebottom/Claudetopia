extends TestCase

var _nodes: Array[Node] = []


func before_each() -> void:
	Peers.overrides.clear()
	GameState.reset_for_new_game(1)
	WorldClock.set_time(12.0, 3)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


# --- light -------------------------------------------------------------------------------------

func test_sun_light_maths() -> void:
	assert_near(Stealth.sun_light(1.0, 1.0), 1.0)
	assert_near(Stealth.sun_light(0.0, 1.0), Stealth.MOONLIGHT, 0.0001, "moonlight floor at night")
	assert_near(Stealth.sun_light(1.0, Stealth.SHADOW_FACTOR), 0.06 + 0.35 * 0.94, 0.001, "in shadow")
	assert_near(Stealth.sun_light(1.0, 1.0, 0.5), 0.06 + 0.5 * 0.94, 0.001, "rain dims the sun")
	assert_near(Stealth.combine_light(0.2, 0.5), 0.6)
	assert_near(Stealth.combine_light(1.0, 1.0), 1.0)


func test_local_light_falloff() -> void:
	var src := [{"position": Vector3.ZERO, "range": 6.0, "energy": 1.0}]
	assert_near(Stealth.local_light(Vector3.ZERO, src), 1.0)
	assert_near(Stealth.local_light(Vector3(3, 0, 0), src), 0.25)
	assert_near(Stealth.local_light(Vector3(6, 0, 0), src), 0.0)
	assert_near(Stealth.local_light(Vector3(9, 0, 0), src), 0.0)
	var two := src + [{"position": Vector3(1, 0, 0), "range": 4.0, "energy": 2.0}]
	assert_near(Stealth.local_light(Vector3(1, 0, 0), two), 1.0, 0.001, "clamped at 1")
	assert_near(Stealth.local_light(Vector3.ZERO, [{"position": Vector3.ZERO, "range": 0.0, "energy": 5.0}]), 0.0)


func test_sun_direction() -> void:
	var dawn := Stealth.sun_direction(6.0, 0.0)
	assert_near(dawn.x, 1.0, 0.001, "rises in the east")
	assert_near(dawn.y, 0.0, 0.001)
	var noon := Stealth.sun_direction(12.0, 60.0)
	assert_true(noon.z > 0.0, "noon sun stands in the south (+z)")
	assert_near(noon.y, sin(deg_to_rad(60.0)), 0.001)
	var dusk := Stealth.sun_direction(18.0, 0.0)
	assert_near(dusk.x, -1.0, 0.001, "sets in the west")


# --- noise and visibility ----------------------------------------------------------------------

func test_noise_model() -> void:
	assert_near(Stealth.noise_level(0.0), 0.0)
	assert_near(Stealth.noise_level(Stealth.SPRINT_SPEED), 1.0)
	# the noise model's speeds are the player's own gaits, not a copy left behind when they change
	assert_near(Stealth.JOG_SPEED, Player.JOG_SPEED, 0.0001)
	assert_near(Stealth.SPRINT_SPEED, Player.SPRINT_SPEED, 0.0001)
	var jog := Stealth.JOG_SPEED
	var walk := Stealth.noise_level(jog)
	assert_near(walk, pow(5.0 / 7.8, 1.5), 0.001)
	assert_gt(Stealth.noise_level(jog, "heavy"), walk, "armour is loud")
	assert_near(Stealth.noise_level(jog, "heavy"), minf(1.0, walk * 1.7), 0.001)
	assert_near(Stealth.noise_level(jog, "light", true), walk * 0.5, 0.001, "crouching halves noise")
	assert_near(Stealth.noise_level(jog, "light", false, "wood"), walk * 1.2, 0.001)
	assert_near(Stealth.noise_level(jog, "light", false, "snow"), walk * 0.7, 0.001)
	assert_near(Stealth.noise_level(jog, "light", false, "", true), walk * 0.7, 0.001, "rain masks noise")
	assert_near(Stealth.noise_radius_m(0.5), 15.0)
	assert_near(Stealth.noise_radius_m(2.0), 30.0)


func test_visibility_model() -> void:
	assert_near(Stealth.visibility(1.0, 0.0, false, 0), 0.8)
	var hidden := Stealth.visibility(Stealth.MOONLIGHT, 0.0, true, 50)
	assert_near(hidden, (0.1 + 0.7 * 0.06) * 0.55 * 0.75, 0.001)
	assert_gt(Stealth.visibility(1.0, 1.0, false, 0), Stealth.visibility(1.0, 0.0, false, 0), "noise adds")
	assert_near(Stealth.visibility(1.0, 1.0, false, 0), 1.0, 0.0001, "clamped")
	assert_near(Stealth.visibility(0.0, 0.0, true, 100), maxf(0.02, 0.1 * 0.55 * 0.5), 0.001)
	assert_gt(Stealth.visibility(0.5, 0.0, false, 0), Stealth.visibility(0.5, 0.0, false, 60), "Sneak skill helps")
	assert_gt(Stealth.visibility(0.5, 0.0, false, 0), Stealth.visibility(0.5, 0.0, true, 0), "crouching helps")


# --- detection meter -----------------------------------------------------------------------------

func test_detection_geometry() -> void:
	assert_near(DetectionMeter.facing_factor(1.0, 110.0), 1.0)
	assert_near(DetectionMeter.facing_factor(cos(deg_to_rad(70.0)), 110.0), DetectionMeter.PERIPHERAL_FACTOR, 0.001, "peripheral band")
	assert_near(DetectionMeter.facing_factor(-1.0, 110.0), 0.0)
	assert_near(DetectionMeter.distance_falloff(0.0, 18.0), 1.0)
	assert_near(DetectionMeter.distance_falloff(9.0, 18.0), 0.75)
	assert_near(DetectionMeter.distance_falloff(18.0, 18.0), 0.0)
	assert_near(DetectionMeter.distance_falloff(5.0, 0.0), 0.0)


func test_detection_meter_dynamics() -> void:
	var m := DetectionMeter.new()
	assert_eq(m.state(), "unaware")
	m.update(0.5, 1.0, 0.0, 18.0, 1.0, 110.0, true)
	assert_near(m.level, 0.45)
	assert_eq(m.state(), "suspicious")
	m.update(0.5, 1.0, 0.0, 18.0, 1.0, 110.0, true)
	assert_near(m.level, 0.9)
	assert_eq(m.state(), "alert")
	assert_true(m.is_witness())
	m.update(1.0, 1.0, 0.0, 18.0, 1.0, 110.0, true)
	assert_near(m.level, 1.0)
	assert_eq(m.state(), "detected")
	m.update(1.0, 1.0, 0.0, 18.0, 1.0, 110.0, false)
	assert_near(m.level, 1.0, 0.001, "memory holds for a moment after losing sight")
	m.update(1.0, 1.0, 0.0, 18.0, 1.0, 110.0, false)
	m.update(1.0, 1.0, 0.0, 18.0, 1.0, 110.0, false)
	assert_near(m.level, 0.75, 0.001, "then it falls at 0.25/s")
	var slow := DetectionMeter.new()
	slow.update(1.0, 0.1, 9.0, 18.0, 1.0, 110.0, true)
	assert_near(slow.level, 0.1 * 0.75 * 0.9, 0.001, "visibility x falloff x rate")
	var behind := DetectionMeter.new()
	behind.update(5.0, 1.0, 1.0, 18.0, -1.0, 110.0, true)
	assert_near(behind.level, 0.0, 0.0001, "nobody sees behind themselves")


func test_hearing_never_makes_a_witness() -> void:
	var m := DetectionMeter.new()
	m.hear(1.0, 0.0, 12.0)
	assert_near(m.level, 0.5)
	assert_eq(m.state(), "suspicious")
	m.hear(1.0, 0.0, 12.0)
	assert_near(m.level, DetectionMeter.WITNESS - 0.01, 0.0001, "capped just under the witness line")
	assert_false(m.is_witness())
	var far := DetectionMeter.new()
	far.hear(0.2, 10.0, 12.0)
	assert_near(far.level, 0.0, 0.0001, "a whisper 10 m off (radius 6 m) is not heard")
	var mid := DetectionMeter.new()
	mid.hear(1.0, 6.0, 12.0)
	assert_near(mid.level, 0.5 * (1.0 - 6.0 / 12.0), 0.001)


# --- sneak attacks, pickpocket, locks ------------------------------------------------------------

func test_sneak_multiplier() -> void:
	assert_near(Stealth.sneak_multiplier_for("dagger", 0.0), 6.0)
	assert_near(Stealth.sneak_multiplier_for("1H", 0.3), 3.0)
	assert_near(Stealth.sneak_multiplier_for("dagger", 0.6), 1.0, 0.0001, "an alert target is not surprised")
	var attacker := Node.new()
	attacker.set_script(_script("extends Node\nvar weapon_class := \"dagger\"\n"))
	var target := Node.new()
	target.set_script(_script("extends Node\nvar detection := 0.1\n"))
	var dummy := Node.new()
	_nodes.append_array([attacker, target, dummy])
	var st := Stealth.new()
	_root().add_child(st)
	_nodes.append(st)
	assert_near(st.sneak_multiplier(attacker, target), 6.0)
	assert_near(st.sneak_multiplier(attacker, dummy), 1.0, 0.0001, "no perception means aware")
	assert_near(st.sneak_multiplier(dummy, target), 3.0, 0.0001, "unarmed still surprises")
	var armed := Node.new()
	armed.set_script(_script("extends Node\nvar main_hand := \"core:item/iron_dagger\"\n"))
	_nodes.append(armed)
	assert_eq(Stealth.weapon_class_of(armed), "dagger", "weapon class read from the item def")


func test_pickpocket_model_is_deterministic() -> void:
	assert_near(Stealth.pickpocket_chance(0, 0.0, 10), 0.28)
	assert_near(Stealth.pickpocket_chance(100, 0.0, 0), 0.9)
	assert_near(Stealth.pickpocket_chance(100, 1.0, 0), 0.4)
	assert_near(Stealth.pickpocket_chance(0, 1.0, 1000), 0.02, 0.0001, "floor")
	assert_near(Stealth.pickpocket_chance(100, 0.0, 0), 0.9)
	assert_gt(Stealth.pickpocket_chance(50, 0.2, 10), Stealth.pickpocket_chance(50, 0.2, 200), "dearer things are harder")
	var a := RandomNumberGenerator.new()
	a.seed = 42
	var b := RandomNumberGenerator.new()
	b.seed = 42
	var seq_a: Array[bool] = []
	var seq_b: Array[bool] = []
	var successes := 0
	for i in 200:
		var ra := Stealth.pickpocket_roll(0.5, a)
		seq_a.append(ra)
		seq_b.append(Stealth.pickpocket_roll(0.5, b))
		if ra:
			successes += 1
	assert_eq(seq_a, seq_b, "same seed, same outcomes")
	assert_true(successes > 60 and successes < 140, "roughly half succeed at 0.5: %d" % successes)


func test_pickpocket_resolution_moves_goods_and_records_the_crime() -> void:
	var st := Stealth.new()
	_root().add_child(st)
	_nodes.append(st)
	var b := Bounty.new()
	_root().add_child(b)
	_nodes.append(b)
	var bag_script := "extends Node3D\nvar npc_id := \"core:npc/mark\"\nvar detection := 0.0\nvar bag := {}\nfunc add(id: String, n: int) -> void:\n\tbag[id] = bag.get(id, 0) + n\nfunc remove(id: String, n: int) -> int:\n\tvar have: int = bag.get(id, 0)\n\tvar t: int = mini(have, n)\n\tbag[id] = have - t\n\treturn t\nfunc count(id: String) -> int:\n\treturn bag.get(id, 0)\n"
	var victim := Node3D.new()
	victim.set_script(_script(bag_script))
	_root().add_child(victim)
	_nodes.append(victim)
	victim.global_position = Vector3(900, 40, 2350)
	victim.call("add", "core:item/rope", 1)
	var thief := Node3D.new()
	thief.set_script(_script(bag_script))
	_root().add_child(thief)
	_nodes.append(thief)
	var chance := Stealth.pickpocket_chance(0, 0.0, ContentQuery.item_value("core:item/rope"))
	var r := st.pickpocket(thief, victim, "core:item/rope", _rng_rolling(chance, true))
	assert_true(r["ok"], "a sleeping mark and a cheap rope")
	assert_eq(thief.call("count", "core:item/rope"), 1)
	assert_eq(victim.call("count", "core:item/rope"), 0)
	assert_eq(b.history.back()["kind"], "pickpocket")
	assert_eq(int(b.history.back()["severity"]), 25)
	assert_false(bool(b.history.back()["witnessed"]), "done cleanly, nobody saw")
	assert_eq(b.pending_count(), 0)
	victim.call("add", "core:item/rope", 1)
	var caught := st.pickpocket(thief, victim, "core:item/rope", _rng_rolling(chance, false))
	assert_false(caught["ok"])
	assert_true(caught["caught"])
	assert_eq(victim.call("count", "core:item/rope"), 1, "he keeps his rope")
	assert_near(float(victim.get("detection")), 1.0, 0.0001, "and he has your measure now")
	assert_true(bool(b.history.back()["witnessed"]), "the mark is always a witness to a fumble")
	assert_eq(b.pending_count(), 1)


## An RNG whose first randf() is below `chance` (succeed) or at/above it (fail), found by
## probing seeds, so the outcome of a roll is fixed without stubbing the model.
func _rng_rolling(chance: float, succeed: bool) -> RandomNumberGenerator:
	for s in range(1, 2000):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		var roll := probe.randf()
		if (roll < chance) == succeed:
			var rng := RandomNumberGenerator.new()
			rng.seed = s
			return rng
	fail("no seed rolls %s against %f" % ["below" if succeed else "above", chance])
	return RandomNumberGenerator.new()


func test_lockpick_model() -> void:
	assert_near(Stealth.lockpick_window(0, 1), 0.29)
	assert_near(Stealth.lockpick_window(100, 1), 0.6, 0.0001, "capped")
	assert_near(Stealth.lockpick_window(50, 5), 0.25)
	assert_near(Stealth.lockpick_window(0, 5), 0.05)
	var hit := Stealth.lockpick_attempt(0, 1, 0.1)
	assert_true(hit["success"])
	assert_false(hit["broke"])
	var miss := Stealth.lockpick_attempt(0, 1, 0.3)
	assert_false(miss["success"])
	assert_false(miss["broke"], "a near miss keeps the pick")
	var snap := Stealth.lockpick_attempt(0, 1, 0.6)
	assert_false(snap["success"])
	assert_true(snap["broke"])
	var skilled := Stealth.lockpick_attempt(100, 1, 0.6)
	assert_true(skilled["success"], "a master's window is 0.6 wide")
	assert_eq(Stealth.lock_level_name(3), "clever")
	assert_eq(Stealth.lock_level_name(99), "oroth")


# --- the service node ---------------------------------------------------------------------------

func test_service_samples_lights_weather_and_player() -> void:
	var st := Stealth.new()
	_root().add_child(st)
	_nodes.append(st)
	assert_true(st.is_in_group("stealth"))
	assert_eq(Stealth.instance, st)
	st.sky_exposure_override = 0.5
	var here := Vector3(900, 40, 2350)
	assert_near(st.light_level(here), Stealth.sun_light(1.0, 0.5), 0.001, "noon, half sky")
	var lamp := StealthLight.new()
	lamp.auto_from_light = false
	lamp.range_m = 4.0
	lamp.energy = 1.0
	_root().add_child(lamp)
	_nodes.append(lamp)
	lamp.global_position = here
	assert_near(st.light_level(here), 1.0, 0.001, "standing in the lamp")
	assert_near(st.light_level(here + Vector3(2, 0, 0)), Stealth.combine_light(Stealth.sun_light(1.0, 0.5), 0.25), 0.001)
	lamp.enabled = false
	assert_near(st.light_level(here), Stealth.sun_light(1.0, 0.5), 0.001, "a doused lamp counts for nothing")
	st.set_weather("rain")
	assert_true(st.raining)
	assert_near(st.weather_factor, 0.5)
	assert_near(st.light_level(here), Stealth.sun_light(1.0, 0.5, 0.5), 0.001)
	st.set_weather("clear")
	var player := CharacterBody3D.new()
	player.set_script(_script("extends CharacterBody3D\nvar crouched := true\nvar weight_class := \"heavy\"\nvar surface := \"wood\"\n"))
	_root().add_child(player)
	_nodes.append(player)
	player.global_position = here
	Peers.overrides["player"] = player
	assert_near(st.player_noise(), 0.0, 0.0001, "standing still")
	player.velocity = Vector3(0, 0, Stealth.SPRINT_SPEED)
	assert_near(st.player_noise(), 1.0 * 1.7 * 1.2 * 0.5 if 1.0 * 1.7 * 1.2 * 0.5 < 1.0 else 1.0, 0.001)
	player.velocity = Vector3.ZERO
	var expected := Stealth.visibility(Stealth.sun_light(1.0, 0.5), 0.0, true, 0)
	assert_near(st.player_visibility(), expected, 0.001)
	WorldClock.set_time(0.0, 3)
	assert_near(st.player_light(), Stealth.MOONLIGHT, 0.001, "midnight")
	GameState.current_interior_id = "x"
	st.sky_exposure_override = -1.0
	assert_near(st.sky_exposure(here), 0.0, 0.0001, "no sun indoors")
	GameState.current_interior_id = ""


func test_door_lock_component() -> void:
	var bounty := Bounty.new()
	_root().add_child(bounty)
	_nodes.append(bounty)
	var door := StaticBody3D.new()
	var lock := DoorLock.new()
	lock.lock_level = 1
	lock.owner_npc = "core:npc/someone"
	door.add_child(lock)
	_root().add_child(door)
	_nodes.append(door)
	door.global_position = Vector3(0, 10, -150)
	assert_eq(Ownership.owner_of(door)["npc"], "core:npc/someone", "the lock tags its door")
	var actor := Node.new()
	actor.set_script(_script("extends Node\nvar bag := {}\nvar marks := 0\nfunc add(id: String, n: int) -> void:\n\tbag[id] = bag.get(id, 0) + n\nfunc remove(id: String, n: int) -> int:\n\tvar have: int = bag.get(id, 0)\n\tvar take: int = mini(have, n)\n\tbag[id] = have - take\n\treturn take\nfunc count(id: String) -> int:\n\treturn bag.get(id, 0)\n"))
	_nodes.append(actor)
	var pick := lock.lockpick_item_id()
	assert_eq(pick, "core:item/lockpick", "the core pack ships a lockpick")
	var r0 := lock.interact(actor)
	assert_eq(r0["state"], "no_pick")
	actor.call("add", pick, 2)
	var started := [false]
	lock.lockpick_started.connect(func(_l: DoorLock) -> void: started[0] = true)
	var r1 := lock.interact(actor)
	assert_eq(r1["state"], "locked")
	assert_true(started[0])
	assert_eq(lock.prompt_text(actor), "Pick lock (simple)")
	var snap := lock.attempt(actor, 0.95)
	assert_true(snap["broke"])
	assert_eq(actor.call("count", pick), 1, "a snapped pick is gone")
	assert_true(lock.locked)
	var xp: Array = []
	var cb := func(s: String, x: float) -> void: xp.append([s, x])
	EventBus.skill_used.connect(cb)
	var ok := lock.attempt(actor, 0.05)
	assert_true(ok["success"])
	assert_false(lock.locked)
	assert_eq(lock.prompt_text(actor), "Open")
	assert_eq(xp.size(), 1)
	assert_eq(xp[0][0], "sneak")
	assert_eq(bounty.history.back()["kind"], "lockpicking", "picking another's lock is a crime")
	EventBus.skill_used.disconnect(cb)
	lock.lock()
	lock.key_item = "core:item/rope"
	actor.call("add", "core:item/rope", 1)
	assert_eq(lock.prompt_text(actor), "Unlock")
	assert_eq(lock.interact(actor)["state"], "unlocked_with_key")


func test_door_lock_fits_the_door_contract() -> void:
	var door: Door = load("res://systems/interiors/door.tscn").instantiate()
	door.display_name = "Wren's cottage"
	door.owner_npc = "core:npc/wren_tallow"
	var lock := DoorLock.new()
	lock.name = "DoorLock"
	lock.lock_level = 2
	door.add_child(lock)
	_root().add_child(door)
	_nodes.append(door)
	assert_true(lock.is_locked())
	assert_eq(lock.owner_npc, "core:npc/wren_tallow", "the lock adopts the door's owner")
	assert_true(Ownership.is_owned_by_other(door))
	assert_eq(door.prompt_text(), "Wren's cottage (locked)", "Door asks the lock")
	var actor := Node.new()
	actor.set_script(_script("extends Node\nvar bag := {}\nfunc add(id: String, n: int) -> void:\n\tbag[id] = bag.get(id, 0) + n\nfunc remove(id: String, n: int) -> int:\n\tvar have: int = bag.get(id, 0)\n\tbag[id] = have - mini(have, n)\n\treturn mini(have, n)\nfunc count(id: String) -> int:\n\treturn bag.get(id, 0)\n"))
	_nodes.append(actor)
	assert_false(lock.try_open(actor), "no key, no pick: stays shut")
	lock.key_item = "core:item/rope"
	actor.call("add", "core:item/rope", 1)
	assert_true(lock.try_open(actor), "the key opens it")
	assert_false(lock.is_locked())
	assert_eq(door.prompt_text(), "Enter Wren's cottage")
