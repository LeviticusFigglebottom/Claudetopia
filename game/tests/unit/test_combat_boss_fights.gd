extends TestCase
## The five boss fights (WORLD_BIBLE §9) as mechanics rather than as lore: the drop the fight
## was for, the hymn that heals until it is cut short, the shockwave that follows a landed blow
## out across the floor, the two-beat combo, the King's arms coming off, the Briar closing in,
## and the room going dark around whatever the player is known for.
## Pure decisions are checked on their own; everything that needs a body gets one, parented to
## the runner's root and freed afterwards.

const REEVE := "core:boss/barrow_reeve"
const NAVE := "core:boss/she_who_waits"
const HART := "core:boss/hart_of_thorns"
const KING := "core:boss/stone_thrall_king"
const CANTOR := "core:boss/last_cantor"
const BOSSES: Array[String] = [REEVE, NAVE, HART, KING, CANTOR]

var _spawned: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func _keep(n: Node) -> Node:
	_spawned.append(n)
	return n


## A boss with its own clock stopped: these tests drive the pieces they are about by hand, so
## nothing depends on how many physics frames happened to go by.
func _boss(id: String) -> Enemy:
	var e := Enemy.new()
	e.configure(id)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	_tree().root.add_child(e)
	_spawned.append(e)
	return e


func _victim(at: Vector3 = Vector3.ZERO) -> Actor:
	var a := Actor.new()
	a.faction = "player"
	a.add_to_group("player")
	_tree().root.add_child(a)
	_spawned.append(a)
	a.global_position = at
	return a


## Every attack a boss can throw, base and in any phase.
func _attacks(def: Dictionary) -> Array:
	var out: Array = []
	out.append_array(def.get("attacks", []))
	for p in def.get("phases", []):
		out.append_array((p as Dictionary).get("attacks", []))
	for limb in def.get("limbs", []):
		out.append_array((limb as Dictionary).get("add_attacks", []))
	return out


## Hits it with a hammer until `wanted` limbs have come away. Going through take_hit means
## armour and resists apply exactly as they would in the fight, so the test never has to
## reproduce the damage formula to know how hard to hit.
func _hammer_until_a_limb_goes(e: Enemy, wanted: int) -> void:
	var swings := 0
	while e.limbs_broken() < wanted and swings < 400 and not e.dead:
		var hit := HitData.new()
		hit.amount = 60.0
		hit.kind = "blunt"                        # rock is broken, not cut
		hit.poise_damage = 0.0
		e.take_hit(hit)
		swings += 1
	assert_true(swings < 400, "hammering it did nothing at all")


func _attack(def: Dictionary, name: String) -> Dictionary:
	for a in _attacks(def):
		if str((a as Dictionary).get("name", "")) == name:
			return a
	return {}


# --- the drop the fight was for ---------------------------------------------------------------

func test_every_boss_names_drops_that_exist() -> void:
	for id in BOSSES:
		var def := ContentDB.get_or_empty(id)
		var drops: Array = def.get("drops", [])
		assert_false(drops.is_empty(), "%s is a boss with nothing to show for it" % id)
		for item_id in drops:
			assert_true(ContentDB.has(str(item_id)), "%s drops missing item %s" % [id, item_id])


func test_a_boss_hands_over_its_unique_drop() -> void:
	var drops := LootDrops.new()
	_keep(drops)
	_tree().root.add_child(drops)
	for id in BOSSES:
		var def := ContentDB.get_or_empty(id)
		var results := drops.drops_for(def, {"region": "", "level": 10, "luck": 0.0, "flags": {}, "quests": {}})
		var got: Array[String] = []
		for r in results:
			if (r as Dictionary).has("item"):
				got.append(str((r as Dictionary)["item"]))
		for wanted in def.get("drops", []):
			assert_true(got.has(str(wanted)), "%s did not hand over %s" % [id, wanted])


func test_the_nave_bell_comes_off_she_who_waits_every_single_time() -> void:
	# The Circle asks for the bell before it gives its verdict, so a roll that sometimes fails
	# would be a main thread that sometimes cannot be finished.
	var drops := LootDrops.new()
	_keep(drops)
	_tree().root.add_child(drops)
	var def := ContentDB.get_or_empty(NAVE)
	for i in 25:
		drops.rng.seed = i * 7919
		var results := drops.drops_for(def, {"region": "", "level": i, "luck": 0.0, "flags": {}, "quests": {}})
		var found := false
		for r in results:
			if str((r as Dictionary).get("item", "")) == "core:item/nave_bell":
				found = true
		assert_true(found, "roll %d left the Nave Bell in the water" % i)


func test_an_unknown_drop_is_refused_rather_than_invented() -> void:
	var drops := LootDrops.new()
	_keep(drops)
	_tree().root.add_child(drops)
	var made := drops.guaranteed_drops({"id": "core:boss/nobody", "drops": ["core:item/not_a_thing"]})
	assert_empty(made, "an id nothing knows must not become a pickup")
	var counted := drops.guaranteed_drops({"id": "x", "drops": [{"item": "core:item/kingbone", "count": 3}]})
	assert_eq(counted.size(), 1)
	assert_eq(int((counted[0] as Dictionary)["count"]), 3, "a drop may name a count")


# --- the hymn -------------------------------------------------------------------------------------

func test_a_channel_spreads_its_healing_across_its_pulses() -> void:
	var hymn := _attack(ContentDB.get_or_empty(NAVE), "the_hymn")
	assert_true(EnemyAbilities.is_channel(hymn), "the hymn is a held note")
	var pulses := EnemyAbilities.channel_pulses(hymn)
	assert_gt(pulses, 1)
	assert_near(EnemyAbilities.channel_heal_per_pulse(hymn) * float(pulses), float(hymn["heals_self"]), 0.01,
		"the whole heal only lands if the whole note does")
	assert_near(EnemyAbilities.channel_heal_per_pulse({}), 0.0, 0.001, "an ordinary swing heals nobody")


func test_silence_stops_a_note_made_with_the_voice_and_nothing_else() -> void:
	var hymn := _attack(ContentDB.get_or_empty(NAVE), "the_hymn")
	var note := _attack(ContentDB.get_or_empty(CANTOR), "the_held_note")
	assert_eq(EnemyAbilities.channel_break_reason(hymn, true, 0.0, 900.0), EnemyAbilities.BROKE_SILENCED)
	assert_eq(EnemyAbilities.channel_break_reason(hymn, false, 0.0, 900.0), "")
	# "Unsilenceable: this is the note, not a spell."
	assert_eq(EnemyAbilities.channel_break_reason(note, true, 0.0, 2000.0), "", "the Cantor's note is the note")


func test_damage_breaks_a_channel_that_admits_it() -> void:
	var hymn := _attack(ContentDB.get_or_empty(NAVE), "the_hymn")
	var needed := EnemyAbilities.interrupt_damage(hymn, 900.0)
	assert_true(needed < INF, "the hymn says it can be interrupted")
	assert_eq(EnemyAbilities.channel_break_reason(hymn, false, needed - 1.0, 900.0), "", "not enough yet")
	assert_eq(EnemyAbilities.channel_break_reason(hymn, false, needed, 900.0), EnemyAbilities.BROKE_DAMAGE)
	var note := _attack(ContentDB.get_or_empty(CANTOR), "the_held_note")
	assert_eq(EnemyAbilities.interrupt_damage(note, 2000.0), INF, "nothing shakes the Cantor off it")


func test_an_uninterrupted_hymn_heals_her_and_an_interrupted_one_does_not() -> void:
	var e := _boss(NAVE)
	var hymn := _attack(ContentDB.get_or_empty(NAVE), "the_hymn")
	e.health = e.max_health * 0.5
	var hurt := e.health
	e._current_attack = hymn
	e._attacking = true
	e._start_channel(hymn)
	assert_true(e.is_channelling())
	# Run the whole note through.
	var guard := 0
	while e.is_channelling() and guard < 2000:
		e._tick_channel(0.05)
		guard += 1
	assert_gt(e.health, hurt, "she closed what you opened")
	var full_gain := e.health - hurt
	assert_near(full_gain, float(hymn["heals_self"]), 2.0)

	# And again, cut off after one beat.
	var f := _boss(NAVE)
	f.health = f.max_health * 0.5
	var hurt2 := f.health
	f._current_attack = hymn
	f._attacking = true
	f._start_channel(hymn)
	f._tick_channel(EnemyAbilities.channel_tick(hymn) + 0.01)
	var after_one := f.health - hurt2
	f._channel_damage = EnemyAbilities.interrupt_damage(hymn, f.max_health)
	f._tick_channel(0.05)
	assert_false(f.is_channelling(), "the note broke off")
	assert_true(f.health - hurt2 <= after_one + 0.01, "and she got nothing more out of it")
	assert_true(full_gain > f.health - hurt2, "interrupting it is worth doing")


func test_a_broken_channel_leaves_its_singer_open() -> void:
	var e := _boss(NAVE)
	var hymn := _attack(ContentDB.get_or_empty(NAVE), "the_hymn")
	var reasons: Array[String] = []
	e.channel_ended.connect(func(_n: String, why: String) -> void: reasons.append(why))
	e._current_attack = hymn
	e._attacking = true
	e._start_channel(hymn)
	e.status.apply("silenced", 6.0)
	e._tick_channel(0.05)
	assert_eq(reasons, [EnemyAbilities.BROKE_SILENCED])
	assert_true(e.is_stunned(), "cutting the hymn off is the opening it gives you")


func test_a_singer_that_is_already_silenced_does_not_start() -> void:
	var e := _boss(NAVE)
	e._enter_phase(2)                                 # the hymn phase
	e.status.apply("silenced", 8.0)
	for _i in 200:
		e._attack_cooldowns.clear()
		var picked := e._select_attack(6.0)
		assert_ne(str(picked.get("name", "")), "the_hymn", "she cannot sing with no voice")


# --- shockwaves ------------------------------------------------------------------------------------

func test_a_shockwave_carries_a_share_of_the_blow_that_threw_it() -> void:
	var slam := _attack(ContentDB.get_or_empty(KING), "overhead_slam")
	assert_true(EnemyAbilities.has_shockwave(slam))
	var ring := EnemyAbilities.shockwave_attack(slam)
	assert_near(float(ring["radius"]), float(slam["shockwave"]))
	assert_near(float(ring["damage"]), float(slam["damage"]) * EnemyAbilities.SHOCKWAVE_SHARE)
	assert_eq(str(ring["kind"]), "burst")
	assert_true(bool(ring["unparryable"]), "you do not parry a floor")
	assert_false(ring.has("knockdown"), "the knockdown belongs to the hammer, not to the ring")


func test_arena_wide_takes_the_arenas_radius() -> void:
	var echo := _attack(ContentDB.get_or_empty(KING), "the_echo")
	assert_true(EnemyAbilities.is_arena_wide(echo))
	assert_near(EnemyAbilities.radial_radius(echo, 26.0), 26.0)
	var slam := _attack(ContentDB.get_or_empty(KING), "overhead_slam")
	assert_near(EnemyAbilities.radial_radius(slam, 26.0), float(slam["shockwave"]), 0.001,
		"a shockwave is its own size, not the room's")


func test_the_slam_catches_somebody_who_rolled_out_of_the_hammer() -> void:
	var e := _boss(KING)
	e.global_position = Vector3.ZERO
	var slam := _attack(ContentDB.get_or_empty(KING), "overhead_slam")
	var inside := _victim(Vector3(float(slam["shockwave"]) - 1.0, 0.0, 0.0))
	var outside := _victim(Vector3(float(slam["shockwave"]) + 8.0, 0.0, 0.0))
	await _tree().physics_frame
	await _tree().physics_frame
	e._burst(EnemyAbilities.shockwave_attack(slam, e.arena_radius()))
	assert_true(inside.health < inside.max_health, "the floor reached them")
	assert_near(outside.health, outside.max_health, 0.01, "and stopped where it said it would")


# --- the two-beat combo ------------------------------------------------------------------------------

func test_a_combo_beat_waits_for_the_beat_it_follows() -> void:
	var second := {"name": "bell_blade_two", "combo_from": "bell_blade"}
	assert_false(EnemyAbilities.combo_ready(second, "", 0.0), "it is not an opener")
	assert_false(EnemyAbilities.combo_ready(second, "quarter_tone", 0.1), "and not after just anything")
	assert_true(EnemyAbilities.combo_ready(second, "bell_blade", 0.4))
	assert_false(EnemyAbilities.combo_ready(second, "bell_blade", 99.0), "the window closes")
	assert_true(EnemyAbilities.combo_ready({"name": "plain"}, "", 99.0), "an ordinary attack needs no cue")


func test_the_cantor_only_throws_the_second_bell_blade_after_the_first() -> void:
	var e := _boss(CANTOR)
	e._enter_phase(0)
	var seen := {}
	for _i in 300:
		e._attack_cooldowns.clear()
		e._last_attack_name = ""
		e._last_attack_at = -999.0
		var picked := e._select_attack(2.5)
		if not picked.is_empty():
			seen[str(picked["name"])] = true
	assert_false(seen.has("bell_blade_two"), "the second beat cannot open the fight")
	e._last_attack_name = "bell_blade"
	e._last_attack_at = Actor.now()
	var found := false
	for _i in 300:
		e._attack_cooldowns.clear()
		var picked := e._select_attack(2.5)
		if str(picked.get("name", "")) == "bell_blade_two":
			found = true
	assert_true(found, "and it must be reachable once the first has landed")


# --- the King's arms ----------------------------------------------------------------------------------

func test_the_kings_limbs_come_off_by_being_hit() -> void:
	var limbs: Array = ContentDB.get_or_empty(KING).get("limbs", [])
	assert_eq(limbs.size(), 3, "left arm, right arm, jaw")
	for limb in limbs:
		assert_false(EnemyAbilities.limb_breaks_on_poise(limb), "the King's parts break by damage")
		assert_gt(EnemyAbilities.limb_damage_needed(limb), 1.0)
		assert_false((limb as Dictionary).get("remove_attacks", []).is_empty(), "each takes something away")


func test_hitting_the_king_enough_takes_an_arm_off_and_the_attack_with_it() -> void:
	var e := _boss(KING)
	var limbs: Array = ContentDB.get_or_empty(KING).get("limbs", [])
	var first: Dictionary = limbs[0]
	var lost := str((first["remove_attacks"] as Array)[0])
	var names := func() -> Array[String]:
		var out: Array[String] = []
		for a in e.current_attacks:
			out.append(str((a as Dictionary).get("name", "")))
		return out
	assert_true((names.call() as Array).has(lost), "it starts with the arm")
	_hammer_until_a_limb_goes(e, 1)
	assert_eq(e.limbs_broken(), 1, "the arm went")
	assert_false((names.call() as Array).has(lost), "and took %s with it" % lost)


func test_poise_does_not_take_the_kings_arms_off() -> void:
	# The small stone-thrall loses a limb when its footing goes; the King's come off by being
	# broken. One vocabulary, two triggers, and they must not be confused.
	var e := _boss(KING)
	e.poise_comp.apply(e.poise_max + 1.0)
	assert_eq(e.limbs_broken(), 0)
	var thrall := Enemy.new()
	thrall.configure("core:enemy/stone_thrall")
	_tree().root.add_child(thrall)
	_spawned.append(thrall)
	thrall.poise_comp.apply(thrall.poise_max + 1.0)
	assert_eq(thrall.limbs_broken(), 1, "the little one still breaks on poise")


func test_a_new_phase_does_not_grow_the_arms_back() -> void:
	var e := _boss(KING)
	var limbs: Array = ContentDB.get_or_empty(KING).get("limbs", [])
	# The right arm is the one that swings the overhead slam, which phase 1 also uses.
	var index := -1
	for i in limbs.size():
		if (limbs[i] as Dictionary).get("remove_attacks", []).has("overhead_slam"):
			index = i
	assert_gt(index, -1, "one of the King's arms swings the slam")
	_hammer_until_a_limb_goes(e, index + 1)
	assert_eq(e.limbs_broken(), index + 1)
	e._enter_phase(1)
	for a in e.current_attacks:
		assert_ne(str((a as Dictionary).get("name", "")), "overhead_slam",
			"phase one must not hand the arm back")


func test_apply_broken_limbs_is_stable_and_additive() -> void:
	var limbs: Array = [
		{"remove_attacks": ["a"], "add_attacks": [{"name": "a_stump"}]},
		{"remove_attacks": ["b"], "add_attacks": [{"name": "b_stump"}]},
	]
	var base: Array = [{"name": "a"}, {"name": "b"}, {"name": "c"}]
	var after_none := EnemyAbilities.apply_broken_limbs(base, limbs, 0)
	assert_eq(after_none.size(), 3)
	var after_two := EnemyAbilities.apply_broken_limbs(base, limbs, 2)
	var names: Array[String] = []
	for a in after_two:
		names.append(str((a as Dictionary)["name"]))
	assert_eq(names, ["c", "a_stump", "b_stump"] as Array[String])
	# Applying it twice to an already-filtered set must not duplicate the stumps.
	var again := EnemyAbilities.apply_broken_limbs(after_two, limbs, 2)
	assert_eq(again.size(), after_two.size())


# --- the Briar ------------------------------------------------------------------------------------------

func test_an_arena_starts_unbounded_and_shrinking_gives_it_an_edge() -> void:
	var arena := BossArena.new()
	_keep(arena)
	_tree().root.add_child(arena)
	assert_false(arena.is_bounded(), "an ordinary fight has the whole room")
	assert_false(arena.is_outside(Vector3(400.0, 0.0, 0.0)), "and nothing is out of bounds in it")
	var after := arena.shrink(3.0)
	assert_true(arena.is_bounded())
	assert_near(after, BossArena.DEFAULT_RADIUS - 3.0)
	arena.shrink(3.0)
	assert_near(arena.radius, BossArena.DEFAULT_RADIUS - 6.0, 0.01, "and it keeps what it takes")


func test_the_briar_never_closes_to_nothing() -> void:
	var arena := BossArena.new()
	_keep(arena)
	_tree().root.add_child(arena)
	for _i in 40:
		arena.shrink(3.0)
	assert_near(arena.radius, arena.min_radius, 0.01, "there is always floor left to fight on")


func test_standing_in_the_thorns_costs_you() -> void:
	var arena := BossArena.new()
	_keep(arena)
	_tree().root.add_child(arena)
	arena.centre = Vector3.ZERO
	arena.set_bound(6.0)
	var inside := _victim(Vector3(2.0, 0.0, 0.0))
	var outside := _victim(Vector3(20.0, 0.0, 0.0))
	assert_false(arena.is_outside(inside.global_position))
	assert_true(arena.is_outside(outside.global_position))
	arena._physics_process(1.0)
	assert_near(inside.health, inside.max_health, 0.01, "the circle is safe")
	assert_true(outside.health < outside.max_health, "the Briar is not")
	assert_true(outside.status.has("bleeding"), "and it leaves thorns in you")


func test_the_harts_thorn_wall_is_what_takes_the_floor() -> void:
	var wall := _attack(ContentDB.get_or_empty(HART), "thorn_wall")
	assert_false(wall.is_empty())
	assert_near(EnemyAbilities.shrinks_arena_by(wall), 3.0, 0.001, "the circle loses three metres")
	assert_near(EnemyAbilities.shrinks_arena_by({}), 0.0, 0.001)
	var hart := _boss(HART)
	var before := hart.arena_radius()
	hart._current_attack = wall
	hart._attacking = true
	hart._attack_phase = "telegraph"
	hart._on_clip_event("hit_start")
	assert_true(hart.arena_radius() < before, "and the Hart is the one who takes it")


func test_winning_gives_the_floor_back() -> void:
	var hart := _boss(HART)
	var bound := hart.arena()
	bound.shrink(6.0)
	assert_true(bound.is_bounded())
	EventBus.boss_defeated.emit(HART)
	await _tree().process_frame
	assert_false(bound.is_bounded(), "the thorns die back when he does")


# --- what stays lit ---------------------------------------------------------------------------------------

func test_renown_decides_how_many_lights_survive() -> void:
	assert_eq(EnemyAbilities.lights_for_renown(0), 1, "nobody is known for nothing")
	assert_eq(EnemyAbilities.lights_for_renown(4), 5)
	assert_eq(EnemyAbilities.lights_for_renown(99), 5, "the tiers stop at four")
	var phase: Dictionary = (ContentDB.get_or_empty(CANTOR)["phases"] as Array)[2]
	assert_true(EnemyAbilities.lights_by_renown(phase), "the Cantor's third phase puts the room out")
	assert_false(EnemyAbilities.lights_by_renown({}))


func test_the_room_goes_out_except_for_what_you_are_known_for() -> void:
	var arena := BossArena.new()
	_keep(arena)
	_tree().root.add_child(arena)
	arena.centre = Vector3.ZERO
	arena.set_bound(30.0)
	var lamps: Array[OmniLight3D] = []
	for i in 6:
		var lamp := OmniLight3D.new()
		lamp.light_energy = 1.0 + float(i)
		lamp.omni_range = 4.0
		_tree().root.add_child(lamp)
		_spawned.append(lamp)
		lamp.global_position = Vector3(float(i), 0.0, 0.0)
		lamps.append(lamp)
	arena.dim_to(2)
	var burning := 0
	for lamp in lamps:
		if lamp.light_energy > 0.0:
			burning += 1
	assert_eq(burning, 2, "two deeds, two lamps")
	# The brightest survive, which is what "what you are known for" means here.
	assert_gt(lamps[5].light_energy, 0.0)
	assert_near(lamps[0].light_energy, 0.0)
	arena.restore_lights()
	for i in lamps.size():
		assert_near(lamps[i].light_energy, 1.0 + float(i), 0.01, "and they come back as they were")


func test_standing_in_a_surviving_light_is_worth_something() -> void:
	var arena := BossArena.new()
	_keep(arena)
	_tree().root.add_child(arena)
	arena.centre = Vector3.ZERO
	arena.set_bound(40.0)
	assert_true(arena.lit_at(Vector3(100.0, 0.0, 0.0)), "an undimmed room is lit everywhere")
	var kept := OmniLight3D.new()
	kept.light_energy = 9.0
	kept.omni_range = 5.0
	_tree().root.add_child(kept)
	_spawned.append(kept)
	kept.global_position = Vector3(10.0, 0.0, 0.0)
	var doused := OmniLight3D.new()
	doused.light_energy = 1.0
	doused.omni_range = 5.0
	_tree().root.add_child(doused)
	_spawned.append(doused)
	doused.global_position = Vector3(-10.0, 0.0, 0.0)
	arena.dim_to(1)
	assert_true(arena.lit_at(Vector3(11.0, 0.0, 0.0)), "under the lamp that is still burning")
	assert_false(arena.lit_at(Vector3(-11.0, 0.0, 0.0)), "under the one that is not")


func test_the_held_note_spares_whoever_is_standing_in_the_light() -> void:
	var note := _attack(ContentDB.get_or_empty(CANTOR), "the_held_note")
	assert_true(EnemyAbilities.lit_damage_share(note) < 1.0, "the note reads the lights")
	assert_near(EnemyAbilities.lit_damage_share({}), 1.0, 0.001, "an ordinary attack does not")

	var e := _boss(CANTOR)
	e.global_position = Vector3.ZERO
	var bound := e.arena()
	bound.centre = Vector3.ZERO
	bound.set_bound(40.0)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 5.0
	lamp.omni_range = 4.0
	_tree().root.add_child(lamp)
	_spawned.append(lamp)
	lamp.global_position = Vector3(6.0, 0.0, 0.0)
	var dark_lamp := OmniLight3D.new()
	dark_lamp.light_energy = 1.0
	dark_lamp.omni_range = 4.0
	_tree().root.add_child(dark_lamp)
	_spawned.append(dark_lamp)
	dark_lamp.global_position = Vector3(-6.0, 0.0, 0.0)
	bound.dim_to(1)

	var in_light := _victim(Vector3(6.0, 0.0, 0.0))
	var in_dark := _victim(Vector3(-6.0, 0.0, 0.0))
	await _tree().physics_frame
	await _tree().physics_frame
	e._burst(note)
	var lit_loss := in_light.max_health - in_light.health
	var dark_loss := in_dark.max_health - in_dark.health
	assert_gt(dark_loss, 0.0, "the note reaches the dark")
	assert_true(lit_loss < dark_loss, "and reaches it harder than it reaches the lit ground")


# --- the fights as a whole -----------------------------------------------------------------------------------

func test_every_boss_starts_in_its_first_phase_and_walks_down_them() -> void:
	for id in BOSSES:
		var e := _boss(id)
		assert_true(e.is_boss, "%s should be a boss" % id)
		assert_eq(e.phase_index, 0, "%s should start in its first phase" % id)
		var phases: Array = ContentDB.get_or_empty(id).get("phases", [])
		var last := 1.1
		for p in phases:
			var threshold := float((p as Dictionary).get("hp", 1.0))
			assert_true(threshold < last, "%s phases must step down in hp" % id)
			last = threshold
		e.health = e.max_health * 0.01
		e._check_phase()
		assert_eq(e.phase_index, phases.size() - 1, "%s should be in its last phase at death's door" % id)


# --- the clip seam ---------------------------------------------------------------------------------

func test_the_clip_timing_of_a_channel_opens_and_closes_it() -> void:
	# The wind-up, the held note and the recovery, as CONTRACTS §3 placeholder timing. This is
	# the seam where a channel could silently behave like an ordinary swing.
	var hymn := _attack(ContentDB.get_or_empty(NAVE), "the_hymn")
	var timing := Enemy.attack_timing(hymn)
	var names: Array[String] = []
	var at := {}
	for e in timing["events"]:
		names.append(str((e as Dictionary)["name"]))
		at[str((e as Dictionary)["name"])] = float((e as Dictionary)["t"])
	assert_true(names.has("channel_start"), "a channel must open")
	assert_true(names.has("channel_end"), "and close")
	assert_false(names.has("hit_start"), "and not also swing")
	assert_near(float(at["channel_start"]), float(hymn["telegraph"]), 0.001)
	assert_near(float(at["channel_end"]) - float(at["channel_start"]), EnemyAbilities.channel_seconds(hymn), 0.001)
	assert_gt(float(timing["length"]), float(at["channel_end"]), "with a recovery after it")

	# An ordinary swing is untouched.
	var swing := Enemy.attack_timing({"telegraph": 0.5, "hit_window": 0.2, "recovery": 0.4})
	var swing_names: Array[String] = []
	for e in swing["events"]:
		swing_names.append(str((e as Dictionary)["name"]))
	assert_true(swing_names.has("hit_start"))
	assert_false(swing_names.has("channel_start"))


func test_a_channel_runs_from_its_clip_events_end_to_end() -> void:
	var e := _boss(NAVE)
	var hymn := _attack(ContentDB.get_or_empty(NAVE), "the_hymn")
	var opened: Array[String] = []
	var closed: Array[String] = []
	e.channel_started.connect(func(n: String, _s: float) -> void: opened.append(n))
	e.channel_ended.connect(func(n: String, why: String) -> void: closed.append("%s:%s" % [n, why]))
	e.health = e.max_health * 0.5
	var hurt := e.health

	e._begin_melee(hymn)
	assert_true(e._attacking, "committed to it")
	assert_false(e.is_channelling(), "but it has not begun singing yet")
	e._on_clip_event("channel_start")
	assert_eq(opened, ["the_hymn"] as Array[String])
	assert_true(e.is_channelling())
	var guard := 0
	while e.is_channelling() and guard < 2000:
		e._tick_channel(0.05)
		guard += 1
	assert_eq(closed, ["the_hymn:finished"] as Array[String])
	assert_gt(e.health, hurt, "an uninterrupted hymn is worth singing")
	# The clip's own close arrives after the tick already closed it, and must do nothing.
	e._on_clip_event("channel_end")
	assert_eq(closed.size(), 1, "the note does not end twice")


func test_staggering_a_singer_ends_the_note() -> void:
	var e := _boss(NAVE)
	var hymn := _attack(ContentDB.get_or_empty(NAVE), "the_hymn")
	var closed: Array[String] = []
	e.channel_ended.connect(func(_n: String, why: String) -> void: closed.append(why))
	e._begin_melee(hymn)
	e._on_clip_event("channel_start")
	assert_true(e.is_channelling())
	e.stagger(0.8)
	assert_false(e.is_channelling(), "a stagger takes the note with it")
	assert_eq(closed, [EnemyAbilities.BROKE_INTERRUPTED] as Array[String])
