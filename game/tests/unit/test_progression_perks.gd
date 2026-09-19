extends TestCase
## Perks, the Modifiers aggregation, the Progression node and the Callings content.

const GRIP := "core:perk/wardens_grip"
const QUICK := "core:perk/quick_steel"
const RINGING := "core:perk/ringing_blow"


func test_the_pack_holds_thirty_perks_spread_over_the_skills() -> void:
	var ids := Perks.all_ids()
	assert_true(ids.size() >= 30, "at least thirty perks, found %d" % ids.size())
	var skills_with_perks := {}
	for id in ids:
		var d := Perks.def(id)
		skills_with_perks[str(d["skill"])] = true
		assert_true(ContentDB.has(str(d["skill"])), "%s names unknown skill %s" % [id, d["skill"]])
		assert_gt(d["effects"].size(), 0, "%s has no effects" % id)
		for e in d["effects"]:
			assert_has(e, "stat")
			assert_true(e.has("mult") or e.has("add"), "%s effect needs mult or add" % id)
	assert_true(skills_with_perks.size() >= 12, "perks should cover most skills")


func test_perks_are_gated_by_skill_level() -> void:
	var p := Perks.new()
	var s := Skills.new()
	assert_false(p.can_take(GRIP, s), "level 5 is not level 20")
	assert_eq(p.blocker(GRIP, s), "skill_too_low")
	s.set_level("core:skill/one_handed", 20)
	assert_true(p.can_take(GRIP, s))
	assert_eq(p.blocker(GRIP, s), "")


func test_prerequisite_perks_are_enforced() -> void:
	var p := Perks.new()
	var s := Skills.new()
	s.set_level("core:skill/one_handed", 60)
	assert_eq(p.blocker(QUICK, s), "missing_prerequisite")
	p.take(GRIP, s)
	assert_true(p.can_take(QUICK, s))
	p.take(QUICK, s)
	assert_true(p.can_take(RINGING, s))


func test_a_perk_cannot_be_taken_twice() -> void:
	var p := Perks.new()
	var s := Skills.new()
	s.set_level("core:skill/one_handed", 20)
	assert_true(p.take(GRIP, s))
	assert_eq(p.blocker(GRIP, s), "already_taken")
	assert_false(p.take(GRIP, s))
	assert_eq(p.count(), 1)


func test_untaking_a_perk_removes_what_depended_on_it() -> void:
	var p := Perks.new()
	var s := Skills.new()
	s.set_level("core:skill/one_handed", 60)
	p.take(GRIP, s)
	p.take(QUICK, s)
	p.take(RINGING, s)
	var removed := p.untake(GRIP)
	assert_eq(removed.size(), 3, "the whole chain comes off")
	assert_eq(p.count(), 0)


func test_perk_summaries_describe_the_tree() -> void:
	var p := Perks.new()
	var s := Skills.new()
	s.set_level("core:skill/one_handed", 20)
	var list := p.summaries("core:skill/one_handed", s)
	assert_eq(list.size(), 3)
	assert_eq(str(list[0]["id"]), GRIP, "ordered by required level")
	assert_true(bool(list[0]["available"]))
	assert_false(bool(list[0]["taken"]))
	assert_false(bool(list[1]["available"]))
	assert_eq(str(list[1]["blocker"]), "skill_too_low", "level is checked before the prerequisite")
	s.set_level("core:skill/one_handed", 40)
	list = p.summaries("core:skill/one_handed", s)
	assert_eq(str(list[1]["blocker"]), "missing_prerequisite")
	assert_true(str(list[0]["description"]).length() > 20)


func test_modifiers_multiply_and_add_across_sources() -> void:
	var m := Modifiers.new()
	m.set_source("perks", [{"stat": "damage_one_handed", "mult": 1.1}])
	m.set_source("potion", [{"stat": "damage_one_handed", "mult": 1.2}, {"stat": "armour", "add": 15.0}])
	assert_near(m.get_mult("damage_one_handed"), 1.32, 0.0001, "multipliers compound")
	assert_near(m.get_add("armour"), 15.0)
	m.set_source("gear", [{"stat": "armour", "add": 5.0}])
	assert_near(m.get_add("armour"), 20.0, 0.001, "additions sum")
	assert_near(m.get_mult("nothing_here"), 1.0)
	assert_near(m.get_add("nothing_here"), 0.0)


func test_replacing_a_source_replaces_its_whole_contribution() -> void:
	var m := Modifiers.new()
	m.set_source("gear", [{"stat": "armour", "add": 10.0}, {"stat": "noise", "mult": 0.8}])
	m.set_source("gear", [{"stat": "armour", "add": 4.0}])
	assert_near(m.get_add("armour"), 4.0)
	assert_near(m.get_mult("noise"), 1.0, 0.001, "the old noise modifier is gone")
	m.clear_source("gear")
	assert_near(m.get_add("armour"), 0.0)


func test_apply_and_scale_helpers() -> void:
	var m := Modifiers.new()
	m.set_source("perks", [{"stat": "max_stamina", "add": 15.0}, {"stat": "stamina_cost_light", "mult": 0.85}])
	assert_near(m.apply("max_stamina", 140.0), 155.0, 0.001)
	assert_near(m.scale("stamina_cost_light", 18.0), 15.3, 0.001)
	assert_true(m.has("max_stamina"))
	assert_false(m.has("prices_buy"))


func test_explain_names_the_sources() -> void:
	var m := Modifiers.new()
	m.set_source("perks", [{"stat": "armour", "mult": 1.1, "source": "Broken In"}])
	m.set_source("gear", [{"stat": "armour", "add": 15.0}])
	var why := m.explain("armour")
	assert_eq(why.size(), 2)


func test_taken_perks_become_modifiers() -> void:
	var p := Perks.new()
	var s := Skills.new()
	s.set_level("core:skill/one_handed", 40)
	p.take(GRIP, s)
	p.take(QUICK, s)
	var m := Modifiers.new()
	m.set_source("perks", p.modifiers())
	assert_near(m.get_mult("damage_one_handed"), 1.1, 0.001)
	assert_near(m.get_mult("stamina_cost_light"), 0.85, 0.001)


func test_progression_node_awards_xp_and_levels_the_character() -> void:
	var prog := Progression.new()
	prog.listen_to_event_bus = false
	add_node(prog)
	var level_ups: Array = []
	prog.level_changed.connect(func(l: int) -> void: level_ups.append(l))
	var gained := 0
	for i in 60:
		gained += prog.award("one_handed", 120.0)
	assert_gt(gained, 20)
	assert_gt(prog.level, 1, "skill gains buy character levels")
	assert_eq(prog.level, Leveling.level_for(prog.skill_set.total_gains))
	assert_eq(prog.attribute_points, prog.level - 1)
	assert_eq(prog.perk_points, prog.level - 1)
	assert_gt(level_ups.size(), 0)
	prog.free()


func test_progression_spends_points_on_attributes_and_perks() -> void:
	var prog := Progression.new()
	prog.listen_to_event_bus = false
	add_node(prog)
	for i in 60:
		prog.award("one_handed", 120.0)
	assert_gt(prog.attribute_points, 0)
	var before := prog.max_stamina()
	assert_true(prog.spend_attribute("endurance"))
	assert_near(prog.max_stamina(), before + Leveling.STAMINA_PER_ENDURANCE, 0.001)
	assert_true(prog.skill_level("one_handed") >= 20)
	var points := prog.perk_points
	assert_true(prog.take_perk(GRIP))
	assert_eq(prog.perk_points, points - 1)
	assert_true(prog.has_perk(GRIP))
	assert_near(prog.mods.get_mult("damage_one_handed"), 1.1, 0.001)
	assert_false(prog.take_perk(RINGING), "the chain is not complete")
	prog.free()


func test_perks_feed_the_derived_pools_and_carry_capacity() -> void:
	var prog := Progression.new()
	prog.listen_to_event_bus = false
	add_node(prog)
	var base_capacity := prog.load_capacity()
	var base_stamina := prog.max_stamina()
	prog.perks.taken.append("core:perk/strong_back")
	prog.perks.taken.append("core:perk/wind_in_the_chest")
	prog._refresh_perk_modifiers()
	assert_near(prog.load_capacity(), base_capacity + 20.0, 0.001)
	assert_near(prog.max_stamina(), base_stamina + 15.0, 0.001)
	prog.free()


func test_effective_skill_includes_fortify_effects() -> void:
	var prog := Progression.new()
	prog.listen_to_event_bus = false
	add_node(prog)
	assert_near(prog.effective_skill("speech"), float(Skills.BASE_LEVEL), 0.001)
	prog.mods.set_source("potion", [{"stat": "skill_speech", "add": 15.0}])
	assert_near(prog.effective_skill("speech"), float(Skills.BASE_LEVEL) + 15.0, 0.001)
	prog.free()


func test_skill_used_on_the_event_bus_is_picked_up() -> void:
	var prog := Progression.new()
	add_node(prog)
	EventBus.skill_used.emit("core:skill/sneak", 30.0)
	assert_true(prog.skill_set.xp("core:skill/sneak") > 0.0)
	prog.free()


func test_the_six_callings_are_complete_and_grant_their_kit() -> void:
	var callings := Progression.callings()
	assert_eq(callings.size(), 6, "DESIGN 5.1 names six callings")
	for c in callings:
		assert_eq(c["skill_bonuses"].size(), 3, "%s should boost three skills" % c["id"])
		for key in c["skill_bonuses"]:
			assert_ne(Skills.normalise(str(key)), "", "%s boosts unknown skill %s" % [c["id"], key])
		assert_true(ContentDB.has(str(c["signature_item"])), "%s has no signature item" % c["id"])
		assert_true(str(c["description"]).length() > 100, "%s needs a real description" % c["id"])
		for f in c.get("starting_reputation", {}):
			assert_true(ContentDB.has(str(f)), "%s names unknown faction %s" % [c["id"], f])


func test_applying_a_calling_sets_skills_and_hands_over_the_kit() -> void:
	var prog := Progression.new()
	prog.listen_to_event_bus = false
	add_node(prog)
	var inv := Inventory.new()
	add_node(inv)
	assert_true(prog.apply_calling("core:calling/cragborn", inv))
	assert_eq(prog.skill_level("two_handed"), Skills.BASE_LEVEL + 10)
	assert_eq(prog.skill_level("block"), Skills.BASE_LEVEL + 10)
	assert_eq(prog.skill_level("smithing"), Skills.BASE_LEVEL + 10)
	assert_eq(prog.skill_level("speech"), Skills.BASE_LEVEL, "untouched skills stay put")
	assert_true(inv.has("core:item/ring_cragborn_bone"), "the signature item is given")
	assert_true(inv.has("core:item/iron_axe"))
	assert_eq(inv.marks, 30)
	assert_eq(prog.level, 1, "a Calling does not hand out levels")
	inv.free()
	prog.free()


func test_progression_save_round_trip() -> void:
	var prog := Progression.new()
	prog.listen_to_event_bus = false
	add_node(prog)
	prog.apply_calling("core:calling/hearthkeeper")
	for i in 80:
		prog.award("one_handed", 200.0)
	assert_gt(prog.level, 1, "the awards should buy at least one level")
	assert_true(prog.spend_attribute("vigour"))
	assert_true(prog.take_perk(GRIP))
	var text := JSON.stringify(prog.to_save())
	var prog2 := Progression.new()
	prog2.listen_to_event_bus = false
	add_node(prog2)
	prog2.from_save(JSON.parse_string(text))
	assert_eq(prog2.level, prog.level)
	assert_eq(prog2.skill_level("one_handed"), prog.skill_level("one_handed"))
	assert_eq(prog2.attribute("vigour"), prog.attribute("vigour"))
	assert_eq(prog2.attribute_points, prog.attribute_points)
	assert_eq(prog2.perk_points, prog.perk_points)
	assert_true(prog2.has_perk(GRIP))
	assert_near(prog2.mods.get_mult("damage_one_handed"), 1.1, 0.001, "perk modifiers are rebuilt")
	assert_eq(prog2.calling_id, "core:calling/hearthkeeper")
	assert_near(prog2.max_health(), prog.max_health(), 0.001)
	prog2.free()
	prog.free()


func test_saved_perks_that_no_longer_exist_are_dropped() -> void:
	var p := Perks.new()
	p.from_save({"taken": [GRIP, "core:perk/ghost_perk"]})
	assert_eq(p.count(), 1)
	assert_true(p.has(GRIP))


func add_node(n: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(n)
