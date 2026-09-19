extends TestCase
## Brain transitions, Perception maths, LockOn picking and enemy attack timing: the pure parts
## of the AI, checked without a scene.

const P := preload("res://actors/enemy/brain.gd")


func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"detection": 0.0, "can_see": false, "alerted": false, "target_alive": true,
		"distance_to_post": 0.0, "distance_to_target": 10.0, "time_in_state": 0.0,
		"inactive": false, "patrol": false,
	}
	base.merge(overrides, true)
	return base


func _params(arch: String = "skirmisher", overrides: Dictionary = {}) -> Dictionary:
	return Brain.params_for(arch, overrides)


# --- archetype parameters ------------------------------------------------------------------

func test_every_design_archetype_has_parameters() -> void:
	for arch in ["brute", "skirmisher", "pack", "charger", "ambusher", "caster", "sentinel", "swarm", "elite", "boss"]:
		assert_has(Brain.ARCHETYPES, arch, "missing archetype %s" % arch)
		var p := Brain.params_for(arch)
		for key in ["engage_range", "circle", "retreat_threshold", "patience", "leash"]:
			assert_has(p, key, "%s is missing %s" % [arch, key])


func test_def_overrides_archetype_defaults() -> void:
	var p := Brain.params_for("pack", {"leash": 12.0})
	assert_near(float(p["leash"]), 12.0)
	assert_true(bool(p["flank"]), "archetype defaults still apply")


# --- transitions ----------------------------------------------------------------------------

func test_idle_to_suspicious_on_partial_detection() -> void:
	var next := Brain.decide(Brain.IDLE, _params(), _ctx({"detection": 0.5}))
	assert_eq(next, Brain.SUSPICIOUS)


func test_full_detection_enters_combat() -> void:
	assert_eq(Brain.decide(Brain.IDLE, _params(), _ctx({"detection": 1.0})), Brain.COMBAT)
	assert_eq(Brain.decide(Brain.SUSPICIOUS, _params(), _ctx({"detection": 1.0})), Brain.COMBAT)
	assert_eq(Brain.decide(Brain.SEARCH, _params(), _ctx({"detection": 1.0})), Brain.COMBAT)


func test_a_dead_target_ends_the_fight() -> void:
	assert_eq(Brain.decide(Brain.COMBAT, _params(), _ctx({"detection": 1.0, "target_alive": false})), Brain.RETURN)


func test_combat_holds_while_the_target_is_visible() -> void:
	var ctx := _ctx({"detection": 1.0, "can_see": true, "time_in_state": 30.0})
	assert_eq(Brain.decide(Brain.COMBAT, _params(), ctx), Brain.COMBAT)


func test_losing_sight_leads_to_search_after_patience() -> void:
	var p := _params("skirmisher")      # patience 3.5
	var ctx := _ctx({"detection": 0.9, "can_see": false, "time_in_state": 2.0})
	assert_eq(Brain.decide(Brain.COMBAT, p, ctx), Brain.COMBAT, "still hunting within patience")
	ctx["time_in_state"] = 4.0
	assert_eq(Brain.decide(Brain.COMBAT, p, ctx), Brain.SEARCH)


func test_leash_breaks_the_chase() -> void:
	var p := _params("skirmisher")      # leash 34
	var ctx := _ctx({"detection": 1.0, "can_see": true, "distance_to_post": 40.0})
	assert_eq(Brain.decide(Brain.COMBAT, p, ctx), Brain.RETURN, "deep-place enemies do not chase past the threshold")


func test_search_gives_up_and_returns() -> void:
	var p := _params("skirmisher")
	var ctx := _ctx({"detection": 0.2, "time_in_state": 20.0})
	assert_eq(Brain.decide(Brain.SEARCH, p, ctx), Brain.RETURN)


func test_return_ends_at_the_post() -> void:
	var ctx := _ctx({"distance_to_post": 0.5})
	assert_eq(Brain.decide(Brain.RETURN, _params(), ctx), Brain.IDLE)
	ctx["patrol"] = true
	assert_eq(Brain.decide(Brain.RETURN, _params(), ctx), Brain.PATROL, "patrollers resume their route")
	ctx["distance_to_post"] = 10.0
	ctx["patrol"] = false
	assert_eq(Brain.decide(Brain.RETURN, _params(), ctx), Brain.RETURN, "still walking home")


func test_noise_on_the_way_home_makes_it_suspicious_again() -> void:
	var ctx := _ctx({"distance_to_post": 10.0, "detection": 0.6})
	assert_eq(Brain.decide(Brain.RETURN, _params(), ctx), Brain.SUSPICIOUS)


func test_ambusher_waits_until_the_target_is_close() -> void:
	var p := _params("ambusher")        # ambush_range 4.5
	var ctx := _ctx({"inactive": true, "detection": 1.0, "can_see": true, "distance_to_target": 10.0})
	assert_eq(Brain.decide(Brain.IDLE, p, ctx), Brain.IDLE, "stays inactive even in plain sight")
	ctx["distance_to_target"] = 4.0
	assert_eq(Brain.decide(Brain.IDLE, p, ctx), Brain.COMBAT, "springs when they step close")


func test_sentinel_never_leaves_its_post() -> void:
	var p := _params("sentinel")        # leash 8, never_leaves_post
	var ctx := _ctx({"detection": 1.0, "can_see": true, "distance_to_target": 20.0})
	assert_ne(Brain.decide(Brain.IDLE, p, ctx), Brain.COMBAT, "will not be baited out")
	ctx["distance_to_target"] = 3.0
	assert_eq(Brain.decide(Brain.IDLE, p, ctx), Brain.COMBAT, "punishes greed within reach")


func test_runtime_tick_changes_state_and_emits() -> void:
	var brain := Brain.new()
	brain.setup("skirmisher", {}, Vector3.ZERO)
	var seen := {"to": ""}
	brain.state_changed.connect(func(_from: String, to: String) -> void: seen["to"] = to)
	assert_eq(brain.state, Brain.IDLE)
	brain.tick(0.1, _ctx({"detection": 1.0}))
	assert_eq(brain.state, Brain.COMBAT)
	assert_eq(str(seen["to"]), Brain.COMBAT)
	assert_near(brain.time_in_state, 0.0, 0.001, "the clock restarts on a change")
	assert_true(brain.is_fighting())
	brain.free()


func test_patrol_points_cycle() -> void:
	var brain := Brain.new()
	brain.patrol_points = PackedVector3Array([Vector3.ZERO, Vector3(5, 0, 0), Vector3(5, 0, 5)])
	brain.setup("skirmisher", {}, Vector3.ZERO)
	assert_eq(brain.state, Brain.PATROL, "a route means patrolling, not idling")
	assert_eq(brain.next_patrol_point(), Vector3(5, 0, 0))
	assert_eq(brain.next_patrol_point(), Vector3(5, 0, 5))
	assert_eq(brain.next_patrol_point(), Vector3.ZERO, "wraps")
	brain.free()


func test_brain_save_round_trip() -> void:
	var brain := Brain.new()
	brain.setup("pack", {}, Vector3(1, 2, 3))
	brain.force(Brain.SEARCH)
	var d := brain.to_save()
	var other := Brain.new()
	other.setup("pack", {}, Vector3.ZERO)
	other.from_save(d)
	assert_eq(other.state, Brain.SEARCH)
	assert_eq(other.post, Vector3(1, 2, 3))
	brain.free()
	other.free()


# --- perception -----------------------------------------------------------------------------

func test_sight_cone() -> void:
	var origin := Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	assert_true(Perception.in_cone(origin, forward, Vector3(0, 0, -10), 20.0, 110.0), "straight ahead")
	assert_false(Perception.in_cone(origin, forward, Vector3(0, 0, -30), 20.0, 110.0), "out of range")
	assert_false(Perception.in_cone(origin, forward, Vector3(0, 0, 10), 20.0, 110.0), "behind")
	assert_true(Perception.in_cone(origin, forward, Vector3(-4, 0, -5), 20.0, 110.0), "inside the cone edge")
	assert_false(Perception.in_cone(origin, forward, Vector3(-10, 0, -1), 20.0, 60.0), "outside a narrow cone")


func test_detection_gain_rises_with_closeness_and_visibility() -> void:
	var near := Perception.gain_rate(2.0, 20.0, 1.0, 1.0)
	var far := Perception.gain_rate(18.0, 20.0, 1.0, 1.0)
	assert_gt(near, far, "close targets are spotted faster")
	var hidden := Perception.gain_rate(2.0, 20.0, 0.2, 1.0)
	assert_gt(near, hidden, "low visibility (the stealth stream's input) slows detection")
	assert_near(Perception.gain_rate(2.0, 20.0, 0.0, 1.0), 0.0, 0.001, "invisible is never spotted")
	var alert := Perception.gain_rate(2.0, 20.0, 1.0, 2.0)
	assert_gt(alert, near, "alertness scales the rate")


# --- attack timing --------------------------------------------------------------------------

func test_attacks_telegraph_before_the_hit_window() -> void:
	var timing := Enemy.attack_timing({"telegraph": 0.8, "hit_window": 0.2, "recovery": 0.6})
	assert_near(float(timing["length"]), 1.6)
	var events: Array = timing["events"]
	var hit_start := 0.0
	var hit_end := 0.0
	for e in events:
		if str(e["name"]) == "hit_start":
			hit_start = float(e["t"])
		elif str(e["name"]) == "hit_end":
			hit_end = float(e["t"])
	assert_near(hit_start, 0.8, 0.001, "the wind-up is readable before the hit")
	assert_near(hit_end, 1.0, 0.001)
	assert_gt(hit_start, 0.0, "no instant hits")
	assert_gt(hit_end, hit_start)


func test_every_core_enemy_attack_has_a_readable_wind_up() -> void:
	for enemy_def in ContentDB.all("enemy"):
		for attack in enemy_def.get("attacks", []):
			var telegraph := float(attack.get("telegraph", 0.0))
			assert_gt(telegraph, 0.3, "%s/%s telegraphs for only %.2f s" % [enemy_def["id"], attack.get("name", "?"), telegraph])
			var timing := Enemy.attack_timing(attack)
			assert_gt(float(timing["length"]), telegraph, "%s/%s has no hit window" % [enemy_def["id"], attack.get("name", "?")])


func test_heavier_attacks_telegraph_longer() -> void:
	var wight := ContentDB.get_or_empty("core:enemy/hedge_wight")
	var light := 0.0
	var heavy := 0.0
	for a in wight.get("attacks", []):
		if str(a.get("name", "")) == "scythe_sweep":
			light = float(a["telegraph"])
		elif str(a.get("name", "")) == "reaping_step":
			heavy = float(a["telegraph"])
	assert_gt(heavy, light, "the big one is signposted more")


# --- lock-on --------------------------------------------------------------------------------

func test_lock_on_picks_the_best_target_in_the_cone() -> void:
	var origin := Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	var positions := PackedVector3Array([
		Vector3(0, 0, -25),      # 0: straight ahead, far
		Vector3(2, 0, -6),       # 1: near, slightly right  <- best
		Vector3(0, 0, 8),        # 2: behind
		Vector3(0, 0, -50),      # 3: out of range
	])
	var i := LockOn.pick_index(origin, forward, positions, DamageModel.LOCK_ON_RANGE, DamageModel.LOCK_ON_CONE_DEG)
	assert_eq(i, 1)
	assert_near(DamageModel.LOCK_ON_RANGE, 30.0, 0.001, "DESIGN says a 30 m cone")


func test_lock_on_ignores_targets_outside_range_and_cone() -> void:
	var positions := PackedVector3Array([Vector3(0, 0, 10), Vector3(0, 0, -45)])
	assert_eq(LockOn.pick_index(Vector3.ZERO, Vector3(0, 0, -1), positions, 30.0, 70.0), -1)


func test_cycling_moves_right_then_wraps() -> void:
	var origin := Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	# left, centre, right
	var positions := PackedVector3Array([Vector3(-6, 0, -6), Vector3(0, 0, -6), Vector3(6, 0, -6)])
	assert_gt(LockOn.signed_angle(origin, forward, positions[2]), 0.0, "right is positive")
	assert_gt(0.0, LockOn.signed_angle(origin, forward, positions[0]), "left is negative")
	assert_eq(LockOn.cycle_index(origin, forward, positions, 1, 1, 30.0), 2, "next to the right")
	assert_eq(LockOn.cycle_index(origin, forward, positions, 1, -1, 30.0), 0, "next to the left")
	assert_eq(LockOn.cycle_index(origin, forward, positions, 2, 1, 30.0), 0, "wraps around")
