extends TestCase
## Skills and Leveling: the XP curve, diminishing returns, level thresholds, attributes and pools.

const ONE_HANDED := "core:skill/one_handed"
const ALCHEMY := "core:skill/alchemy"


func test_the_content_pack_holds_the_sixteen_design_skills() -> void:
	var ids := Skills.ids()
	assert_eq(ids.size(), 16, "fifteen skills plus Calling (DESIGN 5.6)")
	for expected in ["one_handed", "two_handed", "archery", "block", "armour", "sneak", "speech", "alchemy", "smithing", "enchanting", "athletics", "kindling", "hush", "binding", "mending", "calling"]:
		assert_true(ids.has("core:skill/" + expected), "missing skill %s" % expected)


func test_xp_curve_matches_the_design_formula() -> void:
	assert_near(Skills.xp_for_level(0), 40.0, 0.001)
	assert_near(Skills.xp_for_level(1), 44.8, 0.001)
	assert_near(Skills.xp_for_level(5), 40.0 * pow(1.12, 5.0), 0.001)
	assert_near(Skills.xp_for_level(10), 124.234, 0.01)
	assert_near(Skills.xp_for_level(50), 40.0 * pow(1.12, 50.0), 0.01)
	assert_gt(Skills.xp_for_level(20), Skills.xp_for_level(19))


func test_xp_to_reach_sums_the_curve() -> void:
	var expected := Skills.xp_for_level(5) + Skills.xp_for_level(6) + Skills.xp_for_level(7)
	assert_near(Skills.xp_to_reach(8), expected, 0.001)
	assert_near(Skills.xp_to_reach(Skills.BASE_LEVEL), 0.0)


func test_diminishing_returns_fall_from_one_to_the_floor() -> void:
	assert_near(Skills.gain_multiplier(Skills.BASE_LEVEL), 1.0, 0.001)
	assert_near(Skills.gain_multiplier(Skills.MAX_LEVEL), Skills.DIMINISH_FLOOR, 0.001)
	assert_true(Skills.gain_multiplier(50) < Skills.gain_multiplier(20))


func test_skills_start_at_the_base_level() -> void:
	var s := Skills.new()
	assert_eq(s.level(ONE_HANDED), Skills.BASE_LEVEL)
	assert_eq(s.level("one_handed"), Skills.BASE_LEVEL, "short names resolve")
	assert_near(s.fraction(ONE_HANDED), 0.0)
	assert_eq(s.total_gains, 0)


func test_exact_xp_levels_a_skill_once() -> void:
	var s := Skills.new()
	var needed := Skills.xp_for_level(Skills.BASE_LEVEL)
	assert_eq(s.add_xp(ONE_HANDED, needed), 1)
	assert_eq(s.level(ONE_HANDED), Skills.BASE_LEVEL + 1)
	assert_near(s.xp(ONE_HANDED), 0.0, 0.001)
	assert_eq(s.total_gains, 1)


func test_one_short_of_the_curve_does_not_level() -> void:
	var s := Skills.new()
	assert_eq(s.add_xp(ONE_HANDED, Skills.xp_for_level(Skills.BASE_LEVEL) - 0.5), 0)
	assert_eq(s.level(ONE_HANDED), Skills.BASE_LEVEL)
	assert_true(s.fraction(ONE_HANDED) > 0.98)


func test_a_large_award_can_carry_several_levels() -> void:
	var s := Skills.new()
	var gained := s.add_xp(ONE_HANDED, 1000.0)
	assert_gt(gained, 1)
	assert_eq(s.level(ONE_HANDED), Skills.BASE_LEVEL + gained)
	assert_eq(s.total_gains, gained)


func test_calling_and_mending_share_their_xp() -> void:
	var s := Skills.new()
	assert_eq(s.add_xp("core:skill/calling", 30.0), 0, "not enough to level")
	assert_near(s.xp("core:skill/calling"), 30.0, 0.01)
	assert_near(s.xp("core:skill/mending"), 15.0, 0.01, "Mending gets half of Calling's use")
	var s2 := Skills.new()
	s2.add_xp("core:skill/mending", 30.0)
	assert_near(s2.xp("core:skill/calling"), 15.0, 0.01, "and the other way round")
	assert_eq(s2.use_count("core:skill/calling"), 1, "shared use counts as practice")


func test_unrelated_skills_do_not_share() -> void:
	var s := Skills.new()
	s.add_xp(ONE_HANDED, 50.0)
	assert_near(s.xp(ALCHEMY), 0.0)


func test_calling_bonuses_raise_levels_without_granting_character_levels() -> void:
	var s := Skills.new()
	s.apply_bonuses({"speech": 10, "alchemy": 10, "one_handed": 10})
	assert_eq(s.level("core:skill/speech"), Skills.BASE_LEVEL + 10)
	assert_eq(s.level(ALCHEMY), Skills.BASE_LEVEL + 10)
	assert_eq(s.total_gains, 0, "a Calling is not earned progress")


func test_skills_cap_at_a_hundred() -> void:
	var s := Skills.new()
	s.set_level(ONE_HANDED, Skills.MAX_LEVEL)
	assert_eq(s.add_xp(ONE_HANDED, 99999.0), 0)
	assert_eq(s.level(ONE_HANDED), Skills.MAX_LEVEL)
	assert_near(s.fraction(ONE_HANDED), 1.0)


func test_summaries_describe_every_skill() -> void:
	var s := Skills.new()
	var list := s.summaries()
	assert_eq(list.size(), 16)
	assert_has(list[0], "name")
	assert_has(list[0], "progress")
	assert_has(list[0], "governs")
	assert_true(str(list[0]["description"]).length() > 20, "skills carry lore")


func test_level_thresholds_follow_the_design_formula() -> void:
	assert_eq(Leveling.threshold_for(1), 0)
	assert_eq(Leveling.threshold_for(2), 15, "10*1 + 5*1^2")
	assert_eq(Leveling.threshold_for(3), 40, "10*2 + 5*2^2")
	assert_eq(Leveling.threshold_for(4), 75)
	assert_eq(Leveling.threshold_for(5), 120)
	assert_eq(Leveling.threshold_for(11), 600, "10*10 + 5*100")


func test_level_for_gains_crosses_thresholds() -> void:
	assert_eq(Leveling.level_for(0), 1)
	assert_eq(Leveling.level_for(14), 1)
	assert_eq(Leveling.level_for(15), 2)
	assert_eq(Leveling.level_for(39), 2)
	assert_eq(Leveling.level_for(40), 3)
	assert_eq(Leveling.level_for(120), 5)


func test_level_progress_and_gains_to_next() -> void:
	assert_near(Leveling.fraction_for(0), 0.0)
	assert_near(Leveling.fraction_for(15), 0.0, 0.001, "just levelled: no progress into the next")
	assert_near(Leveling.fraction_for(27), 12.0 / 25.0, 0.001)
	assert_eq(Leveling.gains_to_next(0), 15)
	assert_eq(Leveling.gains_to_next(15), 25)


func test_each_level_grants_one_attribute_point_and_one_perk_point() -> void:
	var l := Leveling.new()
	assert_eq(l.level, 1)
	assert_eq(l.attribute_points, 0)
	assert_eq(l.update_from_gains(15), 1)
	assert_eq(l.level, 2)
	assert_eq(l.attribute_points, 1)
	assert_eq(l.perk_points, 1)
	assert_eq(l.update_from_gains(15), 0, "the same gains do not grant twice")
	assert_eq(l.update_from_gains(120), 3, "reaching level 5 grants three more")
	assert_eq(l.level, 5)
	assert_eq(l.attribute_points, 4)
	assert_eq(l.perk_points, 4)


## Ten, where the body has always stood: a character is born with the 100 health, 180 stamina
## and 120 mana the game has always given a new one.
func test_attributes_start_at_ten_and_spend_points() -> void:
	var l := Leveling.new()
	assert_eq(Leveling.BASE_ATTRIBUTE, 10)
	assert_eq(l.attribute("vigour"), Leveling.BASE_ATTRIBUTE)
	assert_false(l.spend_attribute("vigour"), "no points yet")
	l.update_from_gains(15)
	assert_false(l.spend_attribute("luck"), "there is no such attribute")
	assert_true(l.spend_attribute("vigour"))
	assert_eq(l.attribute("vigour"), Leveling.BASE_ATTRIBUTE + 1)
	assert_eq(l.attribute_points, 0)


## One set of formulas, DamageModel's, which is what the body has always been built from.
func test_derived_pools_follow_the_design_formulas() -> void:
	assert_near(Leveling.max_health_for(10), DamageModel.hp_max(10), 0.001, "one health formula, not two")
	assert_near(Leveling.max_health_for(10), 100.0)
	assert_near(Leveling.max_stamina_for(5), 140.0, 0.001, "100 + 8*Endurance")
	assert_near(Leveling.max_mana_for(5), 90.0, 0.001, "60 + 6*Will")
	assert_near(Leveling.load_capacity_for(5), 80.0, 0.001)
	var l := Leveling.new()
	l.update_from_gains(120)
	l.spend_attribute("endurance")
	assert_near(l.max_stamina(), 188.0, 0.001, "100 + 8*11")
	assert_near(l.load_capacity(), 104.0, 0.001, "60 + 4*11")


func test_skills_save_round_trip() -> void:
	var s := Skills.new()
	s.apply_bonuses({"speech": 10})
	s.add_xp(ONE_HANDED, 300.0)
	s.add_xp(ALCHEMY, 20.0)
	var text := JSON.stringify(s.to_save())
	var s2 := Skills.new()
	s2.from_save(JSON.parse_string(text))
	assert_eq(s2.level(ONE_HANDED), s.level(ONE_HANDED))
	assert_near(s2.xp(ONE_HANDED), s.xp(ONE_HANDED), 0.001)
	assert_eq(s2.level("core:skill/speech"), Skills.BASE_LEVEL + 10)
	assert_eq(s2.total_gains, s.total_gains)
	assert_eq(s2.use_count(ALCHEMY), 1)


func test_leveling_save_round_trip() -> void:
	var l := Leveling.new()
	l.update_from_gains(120)
	l.spend_attribute("will")
	l.spend_perk_point()
	var text := JSON.stringify(l.to_save())
	var l2 := Leveling.new()
	l2.from_save(JSON.parse_string(text))
	assert_eq(l2.level, 5)
	assert_eq(l2.attribute("will"), Leveling.BASE_ATTRIBUTE + 1)
	assert_eq(l2.attribute_points, 3)
	assert_eq(l2.perk_points, 3)
