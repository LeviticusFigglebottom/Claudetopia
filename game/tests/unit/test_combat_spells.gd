extends TestCase
## SpellRuntime rules (cost, cast time, silence, schools) and the weapon block reader,
## checked against the real core-pack content.


# --- costs and cast times --------------------------------------------------------------------

func test_cost_and_cast_time_scale_with_skill() -> void:
	var def := ContentDB.get_or_empty("core:spell/kindle_bolt")
	assert_near(SpellRuntime.cost_of(def, 0.0), 12.0)
	assert_near(SpellRuntime.cost_of(def, 100.0), 9.0, 0.001, "-25% at skill 100")
	assert_gt(SpellRuntime.cast_time_of(def, 0.0), SpellRuntime.cast_time_of(def, 100.0))


func test_cannot_cast_without_mana() -> void:
	var def := ContentDB.get_or_empty("core:spell/kindle_bolt")
	var poor := SpellRuntime.can_cast(def, 5.0, false)
	assert_false(bool(poor["ok"]))
	assert_eq(str(poor["reason"]), "mana")
	var rich := SpellRuntime.can_cast(def, 60.0, false)
	assert_true(bool(rich["ok"]))
	assert_eq(str(rich["reason"]), "")


func test_silence_stops_casting() -> void:
	var def := ContentDB.get_or_empty("core:spell/mend")
	var silenced := SpellRuntime.can_cast(def, 100.0, true)
	assert_false(bool(silenced["ok"]), "DESIGN §5.3: silenced means no casting")
	assert_eq(str(silenced["reason"]), "silenced")
	assert_true(bool(SpellRuntime.can_cast(def, 100.0, false)["ok"]))


func test_cannot_cast_while_already_casting() -> void:
	var def := ContentDB.get_or_empty("core:spell/mend")
	var busy := SpellRuntime.can_cast(def, 100.0, false, 0.0, true)
	assert_false(bool(busy["ok"]))
	assert_eq(str(busy["reason"]), "busy")


func test_unknown_spell_is_refused() -> void:
	var r := SpellRuntime.can_cast({}, 100.0, false)
	assert_false(bool(r["ok"]))
	assert_eq(str(r["reason"]), "unknown")


func test_unimplemented_cast_types_are_refused_not_faked() -> void:
	# Summons are not implemented in this pass; they must fail loudly, not pretend.
	var summon := {"name": "x", "school": "calling", "cost": 1, "cast_type": "summon", "effects": []}
	var r := SpellRuntime.can_cast(summon, 100.0, false)
	assert_false(bool(r["ok"]))
	assert_eq(str(r["reason"]), "cast_type")
	for t in ["projectile", "self", "aura", "target"]:
		assert_true(SpellRuntime.IMPLEMENTED_CAST_TYPES.has(t), "%s must be implemented" % t)


# --- schools and effects ----------------------------------------------------------------------

func test_every_core_spell_is_valid() -> void:
	var spells := ContentDB.all("spell")
	assert_gt(spells.size(), 3, "expected the four pass-one spells")
	for s in spells:
		assert_true(SpellRuntime.SCHOOLS.has(str(s["school"])), "%s has unknown school %s" % [s["id"], s["school"]])
		assert_true(SpellRuntime.CAST_TYPES.has(str(s["cast_type"])), "%s has unknown cast type" % s["id"])
		assert_gt(float(s["cost"]), 0.0, "%s must cost something" % s["id"])
		assert_gt(str(s["description"]).length(), 40, "%s needs a lore description" % s["id"])
		for e in s.get("effects", []):
			assert_true(["damage", "status", "heal", "shield", "cleanse"].has(str(e.get("type", ""))), "%s has an unknown effect type" % s["id"])


func test_school_maps_to_a_skill_and_a_damage_kind() -> void:
	var bolt := ContentDB.get_or_empty("core:spell/kindle_bolt")
	assert_eq(SpellRuntime.skill_for(bolt), "kindling")
	var hit := SpellRuntime.build_hit(bolt, null, 0.0)
	assert_eq(hit.kind, "fire")
	assert_false(hit.parryable, "spells cannot be parried")
	var frost := SpellRuntime.build_hit(ContentDB.get_or_empty("core:spell/hush_frost"), null, 0.0)
	assert_eq(frost.kind, "frost")


func test_projectile_hit_carries_damage_and_status() -> void:
	var frost := ContentDB.get_or_empty("core:spell/hush_frost")
	var hit := SpellRuntime.build_hit(frost, null, 0.0)
	assert_near(hit.amount, 12.0)
	assert_eq(hit.statuses.size(), 1)
	assert_eq(str(hit.statuses[0]["id"]), "chilled")


func test_spell_damage_scales_with_skill() -> void:
	var bolt := ContentDB.get_or_empty("core:spell/kindle_bolt")
	assert_near(SpellRuntime.direct_damage(bolt, 0.0), 18.0)
	assert_near(SpellRuntime.direct_damage(bolt, 100.0), 27.0, 0.01, "1 + skill/200")


func test_self_spells_heal_and_ward() -> void:
	var mend := ContentDB.get_or_empty("core:spell/mend")
	assert_eq(str(mend["cast_type"]), "self")
	var healed := false
	for e in mend["effects"]:
		if str(e["type"]) == "heal":
			healed = true
			assert_near(SpellRuntime.heal_amount(e, 0.0), 35.0)
			assert_near(SpellRuntime.heal_amount(e, 100.0), 52.5, 0.01)
	assert_true(healed)
	var ward := ContentDB.get_or_empty("core:spell/ward")
	assert_near(SpellRuntime.duration_of(ward), 12.0)


func test_long_casts_use_the_long_clip() -> void:
	assert_eq(SpellRuntime.clip_for(ContentDB.get_or_empty("core:spell/kindle_bolt")), "Cast_Quick")
	assert_eq(SpellRuntime.clip_for(ContentDB.get_or_empty("core:spell/mend")), "Cast_Long")


# --- weapons ----------------------------------------------------------------------------------

func test_weapon_instance_reads_the_item_block() -> void:
	var w := WeaponInstance.new()
	w.configure(ContentDB.get_or_empty("core:item/iron_sword"), "core:item/iron_sword")
	assert_eq(w.weapon_class, "sword")
	assert_near(w.damage, 14.0)
	assert_eq(w.clips_set, "1H")
	assert_true(w.can_parry)
	assert_eq(w.kind, "slash")
	assert_eq(w.skill_id, "one_handed")
	assert_eq(w.chain_length(), 3, "1H chains three lights")
	assert_false(w.is_ranged())
	w.free()


func test_weapon_clip_names_match_the_contract() -> void:
	var w := WeaponInstance.new()
	w.configure(ContentDB.get_or_empty("core:item/iron_sword"), "core:item/iron_sword")
	assert_eq(w.clip_for("light", 0), "Attack_1H_Light_1")
	assert_eq(w.clip_for("light", 2), "Attack_1H_Light_3")
	assert_eq(w.clip_for("heavy"), "Attack_1H_Heavy")
	assert_eq(w.clip_for("riposte"), "Riposte")
	w.configure(ContentDB.get_or_empty("core:item/ash_greatsword"), "core:item/ash_greatsword")
	assert_eq(w.clip_for("light", 0), "Attack_2H_Light_1")
	assert_eq(w.clip_for("heavy"), "Attack_2H_Heavy")
	assert_true(w.is_two_handed())
	w.free()


func test_attack_multipliers_and_costs_come_from_the_weapon() -> void:
	var w := WeaponInstance.new()
	w.configure(ContentDB.get_or_empty("core:item/ash_greatsword"), "core:item/ash_greatsword")
	assert_near(w.stamina_cost("light"), 26.0)
	assert_near(w.stamina_cost("heavy"), 44.0)
	assert_near(w.stamina_cost("riposte"), 0.0, 0.001, "a riposte is free")
	assert_near(w.attack_mult("light", 0), 1.0)
	assert_near(w.attack_mult("light", 2), 1.2)
	assert_near(w.attack_mult("heavy", 0, 0.0), 1.6)
	assert_near(w.attack_mult("heavy", 0, 1.0), 2.4, 0.001, "1.6 * 1.5 charge")
	w.free()


func test_riposte_hit_is_a_triple_crit_that_cannot_be_blocked() -> void:
	var w := WeaponInstance.new()
	w.configure(ContentDB.get_or_empty("core:item/iron_sword"), "core:item/iron_sword")
	var hit := w.build_hit("riposte", 0, 0.0, 0.0, "riposte")
	assert_near(hit.crit_mult, 3.0)
	assert_false(hit.blockable)
	assert_false(hit.dodgeable)
	w.free()


func test_dagger_hits_cause_bleeding_and_sneak_for_six() -> void:
	var w := WeaponInstance.new()
	w.configure(ContentDB.get_or_empty("core:item/hunting_knife"), "core:item/hunting_knife")
	var hit := w.build_hit("light", 0, 0.0, 0.0)
	assert_eq(hit.statuses.size(), 1)
	assert_eq(str(hit.statuses[0]["id"]), "bleeding")
	assert_near(DamageModel.crit_multiplier("sneak", w.weapon_class), 6.0)
	w.free()


func test_weapon_timing_puts_the_hit_after_the_wind_up() -> void:
	var w := WeaponInstance.new()
	w.configure(ContentDB.get_or_empty("core:item/iron_sword"), "core:item/iron_sword")
	var timing := w.timing_for("light", 0)
	var names: Array[String] = []
	var last_t := -1.0
	for e in timing["events"]:
		names.append(str(e["name"]))
		assert_gt(float(e["t"]), last_t, "events must be ordered")
		last_t = float(e["t"])
		assert_gt(float(timing["length"]), float(e["t"]), "events fall inside the clip")
	assert_eq(names, ["hit_start", "hit_end", "cancel_ok"] as Array[String], "CONTRACTS §3 event names")
	# A faster weapon swings sooner.
	var slow := WeaponInstance.new()
	slow.configure(ContentDB.get_or_empty("core:item/ash_greatsword"), "core:item/ash_greatsword")
	assert_gt(float(slow.timing_for("light", 0)["length"]), float(timing["length"]))
	w.free()
	slow.free()


func test_unarmed_fallback_is_usable() -> void:
	var w := WeaponInstance.new()
	w.configure({}, "")
	assert_eq(w.weapon_class, "unarmed")
	assert_eq(w.clip_for("light", 0), "Attack_Unarmed_1")
	assert_gt(w.damage, 0.0)
	assert_eq(w.display_name(), "Fists")
	w.free()


func test_bow_reads_its_ranged_block_and_ammo_exists() -> void:
	var def := ContentDB.get_or_empty("core:item/hunting_bow")
	var w := WeaponInstance.new()
	w.configure(def, "core:item/hunting_bow")
	assert_true(w.is_ranged())
	assert_eq(w.clips_set, "bow")
	assert_eq(w.skill_id, "archery")
	assert_gt(float(w.ranged.get("draw_time", 0.0)), 0.0, "bows have a draw time")
	assert_true(ContentDB.has(str(w.ranged["ammo_item"])), "the bow's ammo item must exist")
	var arrow := ContentDB.get_or_empty("core:item/arrow")
	assert_has(arrow, "projectile")
	assert_true(ResourceLoader.exists(str(arrow["projectile"]["scene"])), "the arrow scene must exist")
	w.free()


func test_shield_provides_stability_and_parry() -> void:
	var shield := ContentDB.get_or_empty("core:item/round_shield")
	assert_near(float(shield["armour"]["stability"]), 0.8)
	assert_true(bool(shield["armour"]["parry"]))
	# A 0.8-stability guard takes a fifth of the damage and a fifth of the stamina hit.
	assert_near(DamageModel.block_damage(50.0, 0.8), 10.0)
	assert_near(DamageModel.block_stamina_cost(50.0, 0.8), 6.0)


func test_every_core_weapon_and_armour_is_well_formed() -> void:
	for item in ContentDB.all("item"):
		assert_gt(str(item["description"]).length(), 40, "%s needs a lore description" % item["id"])
		if item.has("weapon"):
			var w: Dictionary = item["weapon"]
			for key in ["class", "damage", "poise_damage", "stamina_light", "stamina_heavy", "speed", "reach", "clips_set", "parry", "stability"]:
				assert_has(w, key, "%s weapon block is missing %s" % [item["id"], key])
			assert_true(["1H", "2H", "dagger", "bow", "staff", "unarmed"].has(str(w["clips_set"])), "%s has a bad clips_set" % item["id"])
			assert_gt(float(w["damage"]), 0.0)
		if item.has("armour"):
			var a: Dictionary = item["armour"]
			for key in ["slot", "armour", "weight_class", "stability"]:
				assert_has(a, key, "%s armour block is missing %s" % [item["id"], key])
