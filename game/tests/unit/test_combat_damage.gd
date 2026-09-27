extends TestCase
## DamageModel: the DESIGN §5.3 formulas. Pure statics, no scene.


func test_pools_match_design() -> void:
	# stamina = 100 + 8*Endurance, mana = 60 + 6*Will
	assert_near(DamageModel.stamina_max(0), 100.0)
	assert_near(DamageModel.stamina_max(10), 180.0)
	assert_near(DamageModel.mana_max(0), 60.0)
	assert_near(DamageModel.mana_max(10), 120.0)


func test_skill_multiplier() -> void:
	assert_near(DamageModel.skill_mult(0.0), 1.0)
	assert_near(DamageModel.skill_mult(100.0), 1.5)
	assert_near(DamageModel.skill_mult(200.0), 2.0)
	assert_near(DamageModel.skill_mult(-50.0), 1.0, 0.001, "negative skill must not reduce damage")


func test_damage_formula() -> void:
	# weapon_base * skill_mult * attack_mult * charge - armour, then * (1 - resist)
	var raw := DamageModel.raw_damage(20.0, 50.0, 1.5, 1.0)
	assert_near(raw, 20.0 * 1.25 * 1.5)
	assert_near(DamageModel.apply_defence(raw, 7.5, 0.0), 30.0)
	assert_near(DamageModel.apply_defence(100.0, 0.0, 0.25), 75.0)
	assert_near(DamageModel.damage(20.0, 50.0, 1.5, 1.0, 7.5, 0.5), 15.0)


func test_damage_never_below_one() -> void:
	assert_near(DamageModel.apply_defence(5.0, 100.0, 0.0), DamageModel.MIN_DAMAGE)
	assert_near(DamageModel.apply_defence(10.0, 0.0, 0.99), DamageModel.MIN_DAMAGE, 0.001, "resist is capped at 0.95")


func test_negative_resist_is_a_weakness() -> void:
	assert_near(DamageModel.apply_defence(10.0, 0.0, -0.5), 15.0)


func test_crit_multipliers() -> void:
	assert_near(DamageModel.crit_multiplier(""), 1.0)
	assert_near(DamageModel.crit_multiplier("riposte"), 3.0)
	assert_near(DamageModel.crit_multiplier("backstab"), 3.0)
	assert_near(DamageModel.crit_multiplier("sneak"), 3.0)
	assert_near(DamageModel.crit_multiplier("sneak", "dagger"), 6.0, 0.001, "daggers sneak for 6x")


func test_crit_applies_before_armour() -> void:
	var crit := DamageModel.damage(20.0, 0.0, 1.0, 1.0, 10.0, 0.0, 3.0)
	assert_near(crit, 50.0, 0.001, "(20*3) - 10")


func test_light_chain_and_heavy_charge() -> void:
	assert_near(DamageModel.light_chain_mult(0), 1.0)
	assert_near(DamageModel.light_chain_mult(1), 1.0)
	assert_near(DamageModel.light_chain_mult(2), 1.2)
	assert_near(DamageModel.light_chain_mult(9), 1.2, 0.001, "clamped to the last entry")
	assert_near(DamageModel.heavy_charge(0.0), 1.0)
	assert_near(DamageModel.heavy_charge(1.0), 1.5)
	assert_near(DamageModel.heavy_charge(2.0), 1.5)


func test_poise_damage_and_hyper_armour() -> void:
	assert_near(DamageModel.poise_damage(10.0, false), 10.0)
	assert_near(DamageModel.poise_damage(10.0, true), 15.0, 0.001, "heavies deal 1.5x poise damage")
	assert_near(DamageModel.poise_damage(8.0, false, 12.0), 0.0, 0.001, "hyper-armour ignores small hits")
	assert_near(DamageModel.poise_damage(20.0, false, 12.0), 20.0, 0.001, "big hits break through")


func test_stamina_costs() -> void:
	assert_near(DamageModel.attack_stamina("light", {}), 18.0)
	assert_near(DamageModel.attack_stamina("heavy", {}), 32.0)
	assert_near(DamageModel.attack_stamina("light", {"stamina_light": 12.0}), 12.0)
	assert_near(DamageModel.STAMINA_DODGE, 22.0)
	assert_near(DamageModel.STAMINA_SPRINT_PER_S, 8.0)


func test_block_scales_with_stability() -> void:
	# block-hit stamina = damage * 0.6 * (1 - stability)
	assert_near(DamageModel.block_stamina_cost(50.0, 0.0), 30.0)
	assert_near(DamageModel.block_stamina_cost(50.0, 0.8), 6.0)
	assert_near(DamageModel.block_stamina_cost(50.0, 1.0), 0.0)
	assert_near(DamageModel.block_damage(50.0, 0.8), 10.0)
	assert_near(DamageModel.block_damage(50.0, 1.0), 0.0, 0.001, "a perfect guard lets nothing through")


func test_parry_window() -> void:
	# block pressed within 0.25 s BEFORE the hit
	assert_true(DamageModel.parry_succeeds(1.0, 1.0), "same instant parries")
	assert_true(DamageModel.parry_succeeds(1.0, 1.24))
	assert_true(DamageModel.parry_succeeds(1.0, 1.25), "the window edge counts")
	assert_false(DamageModel.parry_succeeds(1.0, 1.26), "too late")
	assert_false(DamageModel.parry_succeeds(1.0, 0.9), "pressed after the hit")
	assert_near(DamageModel.RIPOSTE_OPEN_DURATION, 2.0)


func test_input_buffer() -> void:
	assert_true(DamageModel.buffer_valid(1.0, 1.24))
	assert_true(DamageModel.buffer_valid(1.0, 1.25), "0.25 s buffer")
	assert_false(DamageModel.buffer_valid(1.0, 1.26))
	assert_false(DamageModel.buffer_valid(-1.0, 0.1), "no press buffered")


func test_dodge_params_by_load() -> void:
	var light := DamageModel.dodge_params(0.0)
	assert_near(float(light["duration"]), 0.6)
	assert_near(float(light["iframe_start"]), 0.08)
	assert_near(float(light["iframe_end"]), 0.38)
	var heavy := DamageModel.dodge_params(0.9)
	assert_gt(float(heavy["duration"]), float(light["duration"]), "heavy load lengthens the roll")
	var light_window := float(light["iframe_end"]) - float(light["iframe_start"])
	var heavy_window := float(heavy["iframe_end"]) - float(heavy["iframe_start"])
	assert_gt(light_window, heavy_window, "heavy load cuts i-frames")
	var overloaded := DamageModel.dodge_params(1.5)
	assert_eq(str(overloaded["tier"]), "overloaded")
	assert_gt(float(overloaded["duration"]), float(heavy["duration"]))


func test_iframe_window() -> void:
	var p := DamageModel.dodge_params(0.0)
	assert_false(DamageModel.in_iframes(0.05, p))
	assert_true(DamageModel.in_iframes(0.08, p))
	assert_true(DamageModel.in_iframes(0.2, p))
	assert_true(DamageModel.in_iframes(0.38, p))
	assert_false(DamageModel.in_iframes(0.39, p))


func test_facing_and_behind() -> void:
	var forward := Vector3(0, 0, -1)
	assert_true(DamageModel.is_facing(forward, Vector3(0, 0, -5)), "hit from straight ahead")
	assert_false(DamageModel.is_facing(forward, Vector3(0, 0, 5)), "hit from behind is not blocked")
	assert_true(DamageModel.is_behind(forward, Vector3(0, 0, 5)), "attacker behind the victim")
	assert_false(DamageModel.is_behind(forward, Vector3(0, 0, -5)))


func test_hit_kinds_cover_the_design_list() -> void:
	for kind in ["slash", "pierce", "blunt", "fire", "frost", "poison", "silence"]:
		assert_true(DamageModel.KINDS.has(kind), "missing hit kind %s" % kind)
	assert_eq(DamageModel.kind_for_class("sword"), "slash")
	assert_eq(DamageModel.kind_for_class("dagger"), "pierce")
	assert_eq(DamageModel.kind_for_class("mace"), "blunt")
	assert_eq(DamageModel.resist_of({"fire": 0.5}, "fire"), 0.5)
	assert_eq(DamageModel.resist_of({}, "fire"), 0.0)


func test_skill_for_clips_set() -> void:
	assert_eq(DamageModel.skill_for_clips("1H"), "one_handed")
	assert_eq(DamageModel.skill_for_clips("2H"), "two_handed")
	assert_eq(DamageModel.skill_for_clips("bow"), "archery")
