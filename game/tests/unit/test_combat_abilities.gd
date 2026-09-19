extends TestCase
## EnemyAbilities and the Enemy wiring that carries the bestiary's special behaviours: the
## silence that shuts a chorister up, the purse a cutpurse takes, the stamina a leech-hound
## drinks, the wisp's lure, the greed that wakes a Warden, the duelist's guard, and the limbs
## that come off a stone-thrall. The pure decisions are checked on their own; the ones that need
## bodies get bodies, parented to the runner's root and freed afterwards.

const CUTPURSE := "core:enemy/cutpurse"
const LEECH := "core:enemy/leech_hound"
const WISP := "core:enemy/wisp"
const WARDEN := "core:enemy/warden"
const THRALL := "core:enemy/stone_thrall"
const BRAVO := "core:enemy/bravo"
const HAG := "core:enemy/scree_hag"
const CHORISTER := "core:enemy/chorister"

var _spawned: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()


func _enemy(id: String) -> Enemy:
	var e := Enemy.new()
	e.configure(id)
	_tree().root.add_child(e)
	_spawned.append(e)
	return e


func _attack(def: Dictionary, name: String) -> Dictionary:
	for a in def.get("attacks", []):
		if str((a as Dictionary).get("name", "")) == name:
			return a
	return {}


# --- voice: silence answers a singer ---------------------------------------------------------

func test_a_voice_attack_is_refused_while_silenced() -> void:
	var shriek := {"name": "the_shriek", "voice": true}
	var stone := {"name": "thrown_stone"}
	assert_true(EnemyAbilities.is_usable(shriek, false))
	assert_false(EnemyAbilities.is_usable(shriek, true), "a silenced throat cannot shriek")
	assert_true(EnemyAbilities.is_usable(stone, true), "a silenced hag can still throw")


func test_usable_filters_a_whole_attack_set() -> void:
	var def := ContentDB.get_or_empty(CHORISTER)
	var all: Array = def["attacks"]
	assert_eq(EnemyAbilities.usable(all, false).size(), all.size())
	var quiet := EnemyAbilities.usable(all, true)
	assert_true(quiet.size() < all.size(), "silence should take the singing away")
	for a in quiet:
		assert_false(bool((a as Dictionary).get("voice", false)))


func test_a_silenced_chorister_falls_back_to_its_censer() -> void:
	# Selection is deliberately loose (aggression lets an enemy hold its swing), so this asks
	# the question many times: it must never sing while silenced, and it must still swing.
	var e := _enemy(CHORISTER)
	e.status.apply("silenced", 6.0)
	var swung := false
	for _i in 200:
		e._attack_cooldowns.clear()
		var picked := e._select_attack(2.0)
		if picked.is_empty():
			continue
		swung = true
		assert_false(bool(picked.get("voice", false)), "a silenced chorister picked '%s'" % picked.get("name", "?"))
	assert_true(swung, "it still has hands and a censer")


# --- the cutpurse ----------------------------------------------------------------------------

func test_steal_amount_stays_inside_the_purse_and_the_range() -> void:
	var a := {"steal": {"marks": [10, 30]}}
	assert_eq(EnemyAbilities.steal_amount(a, 500, 0.0), 10)
	assert_eq(EnemyAbilities.steal_amount(a, 500, 1.0), 30)
	assert_eq(EnemyAbilities.steal_amount(a, 7, 1.0), 7, "it cannot take more than is there")
	assert_eq(EnemyAbilities.steal_amount(a, 0, 1.0), 0, "an empty purse gives nothing")
	assert_eq(EnemyAbilities.steal_amount({}, 500, 1.0), 0, "an attack that does not steal takes nothing")


func test_a_rich_purse_loses_a_share_rather_than_a_pittance() -> void:
	var a := {"steal": {"marks": [10, 30], "share": 0.2}}
	assert_eq(EnemyAbilities.steal_amount(a, 1000, 0.0), 200, "a fifth of a fat purse beats the floor")
	assert_eq(EnemyAbilities.steal_amount(a, 50, 0.0), 10, "a thin one still gives the floor")


func test_the_cutpurse_cuts_a_real_purse_carries_it_and_runs() -> void:
	var bag := Inventory.new()
	bag.is_player = true                            # only the player's bag joins the "inventory" group
	_tree().root.add_child(bag)
	_spawned.append(bag)
	bag.add_marks(400)
	var victim := Actor.new()
	victim.faction = "player"
	victim.add_to_group("player")
	_tree().root.add_child(victim)
	_spawned.append(victim)

	var e := _enemy(CUTPURSE)
	var before: Array = e.marks_range.duplicate()
	var cut := _attack(ContentDB.get_or_empty(CUTPURSE), "purse_cut")
	assert_false(cut.is_empty(), "the cutpurse must have a purse_cut")
	e._after_hit_landed(cut, victim, "hit")

	assert_true(bag.marks < 400, "the purse is lighter (%d)" % bag.marks)
	var taken := 400 - bag.marks
	assert_eq(int(e.marks_range[0]), int(before[0]) + taken, "what it took, it carries")
	assert_eq(int(e.marks_range[1]), int(before[1]) + taken)
	assert_gt(e._flee_timer, 0.0, "and then it runs")


func test_a_dodged_cut_takes_nothing() -> void:
	var bag := Inventory.new()
	bag.is_player = true                            # only the player's bag joins the "inventory" group
	_tree().root.add_child(bag)
	_spawned.append(bag)
	bag.add_marks(400)
	var victim := Actor.new()
	victim.faction = "player"
	victim.add_to_group("player")
	_tree().root.add_child(victim)
	_spawned.append(victim)
	var e := _enemy(CUTPURSE)
	e._after_hit_landed(_attack(ContentDB.get_or_empty(CUTPURSE), "purse_cut"), victim, "dodged")
	assert_eq(bag.marks, 400, "rolling out of it keeps your money")
	assert_near(e._flee_timer, 0.0)


# --- the leech-hound --------------------------------------------------------------------------

func test_drain_reads_its_attack() -> void:
	assert_near(EnemyAbilities.drain_amount({"drain_stamina": 16.0}), 16.0)
	assert_near(EnemyAbilities.drain_amount({}), 0.0)
	assert_near(EnemyAbilities.drain_heal({"drain_heal": 0.5}, 20.0), 10.0)
	assert_near(EnemyAbilities.drain_heal({}, 20.0), 0.0, 0.001, "a drain is not a heal by default")


func test_a_bite_takes_stamina_off_the_bar_and_puts_some_of_it_back() -> void:
	var victim := Actor.new()
	victim.faction = "player"
	victim.endurance = 10
	_tree().root.add_child(victim)
	_spawned.append(victim)
	var e := _enemy(LEECH)
	e.health = e.max_health - 30.0
	var hurt := e.health
	var before := victim.stamina
	e._after_hit_landed(_attack(ContentDB.get_or_empty(LEECH), "latch"), victim, "hit")
	assert_true(victim.stamina < before, "the bar went down")
	assert_near(before - victim.stamina, 16.0, 0.01)
	assert_gt(e.health, hurt, "and the hound got a mouthful back")


func test_a_drain_cannot_take_more_than_is_left() -> void:
	var victim := Actor.new()
	victim.faction = "player"
	_tree().root.add_child(victim)
	_spawned.append(victim)
	victim.stamina = 5.0
	var e := _enemy(LEECH)
	e._after_hit_landed(_attack(ContentDB.get_or_empty(LEECH), "worry"), victim, "hit")
	assert_near(victim.stamina, 0.0, 0.01)


# --- the wisp ---------------------------------------------------------------------------------

func test_the_lure_keeps_its_distance_until_you_corner_it() -> void:
	var b: Dictionary = ContentDB.get_or_empty(WISP)["behaviour"]
	assert_eq(EnemyAbilities.lure_decision(20.0, b, 0.0), EnemyAbilities.HOLD, "far off it just waits")
	assert_eq(EnemyAbilities.lure_decision(6.0, b, 0.0), EnemyAbilities.WITHDRAW, "closing makes it back away")
	assert_eq(EnemyAbilities.lure_decision(2.0, b, 0.2), EnemyAbilities.WITHDRAW, "one step inside is not enough")
	assert_eq(EnemyAbilities.lure_decision(2.0, b, 2.0), EnemyAbilities.ENGAGE, "stay on it and it turns")


func test_only_a_luring_creature_lures() -> void:
	assert_true(EnemyAbilities.lures(ContentDB.get_or_empty(WISP)["behaviour"]))
	assert_false(EnemyAbilities.lures(ContentDB.get_or_empty(CUTPURSE)["behaviour"]))


func test_a_wisp_that_has_turned_stays_turned() -> void:
	var e := _enemy(WISP)
	e.target = e                                   # any node: the lure only reads the distance
	assert_true(e._tick_lure(0.016, 6.0), "it is still leading")
	e._lure_closed = 99.0
	assert_false(e._tick_lure(0.016, 1.0), "cornered, it fights")
	assert_true(e._lure_engaged)
	assert_false(e._tick_lure(0.016, 20.0), "and it does not go back to leading")


# --- the Warden ---------------------------------------------------------------------------------

func test_greed_inside_the_radius_rouses_a_guardian_and_nothing_outside_it_does() -> void:
	var b: Dictionary = ContentDB.get_or_empty(WARDEN)["behaviour"]
	var post := Vector3(10.0, 0.0, 10.0)
	assert_true(EnemyAbilities.greed_rouses(post, post + Vector3(5.0, 0.0, 0.0), b))
	assert_false(EnemyAbilities.greed_rouses(post, post + Vector3(40.0, 0.0, 0.0), b))
	assert_false(EnemyAbilities.greed_rouses(post, post, {}), "a creature that guards nothing never cares")


func test_a_roused_guardian_fights_harder_but_never_past_certainty() -> void:
	var b: Dictionary = ContentDB.get_or_empty(WARDEN)["behaviour"]
	assert_gt(EnemyAbilities.guard_aggression(0.7, b), 0.7)
	assert_true(EnemyAbilities.guard_aggression(0.95, b) <= 1.0)
	assert_near(EnemyAbilities.guard_aggression(0.7, {}), 0.7)


func test_opening_a_chest_at_the_shrine_wakes_the_warden() -> void:
	var e := _enemy(WARDEN)
	e.brain.post = e.global_position
	assert_eq(e.brain.state, Brain.IDLE)
	var chest := Node3D.new()
	_tree().root.add_child(chest)
	_spawned.append(chest)
	chest.global_position = e.global_position + Vector3(4.0, 0.0, 0.0)
	var thief := Node3D.new()
	_tree().root.add_child(thief)
	_spawned.append(thief)
	var calm := float(e.brain.param("aggression", 0.7))
	e._on_container_opened(chest, thief)
	assert_eq(e.brain.state, Brain.COMBAT, "it has been counting")
	assert_true(e.is_roused())
	assert_gt(float(e.brain.param("aggression", 0.0)), calm)


func test_a_chest_opened_out_of_sight_of_the_stones_is_none_of_its_business() -> void:
	var e := _enemy(WARDEN)
	e.brain.post = e.global_position
	var chest := Node3D.new()
	_tree().root.add_child(chest)
	_spawned.append(chest)
	chest.global_position = e.global_position + Vector3(60.0, 0.0, 0.0)
	e._on_container_opened(chest, null)
	assert_eq(e.brain.state, Brain.IDLE)
	assert_false(e.is_roused())


func test_the_warden_does_not_chase() -> void:
	var b := Brain.params_for("sentinel", ContentDB.get_or_empty(WARDEN)["behaviour"])
	assert_true(bool(b["never_leaves_post"]))
	var ctx := {"detection": 1.0, "can_see": true, "target_alive": true, "distance_to_target": 40.0, "distance_to_post": 0.0}
	assert_ne(Brain.decide(Brain.IDLE, b, ctx), Brain.COMBAT, "it lets you walk away")


# --- the duelist ----------------------------------------------------------------------------------

func test_a_duelist_answers_some_swings_and_not_others() -> void:
	var b: Dictionary = ContentDB.get_or_empty(BRAVO)["behaviour"]
	assert_true(EnemyAbilities.parries(b))
	assert_true(EnemyAbilities.parry_press_at(10.0, b, 0.99) < 0.0, "it does not catch everything")
	var at := EnemyAbilities.parry_press_at(10.0, b, 0.0)
	assert_gt(at, 10.0, "the press comes after the swing starts, not with it")
	assert_true(at - 10.0 < DamageModel.PARRY_WINDOW + 0.25, "and not so late that nothing could land in the window")


func test_a_bravo_raises_and_drops_its_guard() -> void:
	var e := _enemy(BRAVO)
	var victim := Actor.new()
	victim.faction = "player"
	_tree().root.add_child(victim)
	_spawned.append(victim)
	e.target = victim
	e._guard(true)
	assert_true(e.is_blocking, "guard up between swings")
	assert_true(e.can_parry)
	assert_gt(e.block_stability, 0.0)
	e._guard(false)
	assert_false(e.is_blocking, "and down when it commits")
	assert_near(e.block_stability, 0.0)


func test_only_a_duelist_guards() -> void:
	var e := _enemy(CUTPURSE)
	e._guard(true)
	assert_false(e.is_blocking, "a cutpurse has no interest in standing and trading")


# --- the stone-thrall -------------------------------------------------------------------------------

func test_limbs_come_off_in_order_and_then_stop() -> void:
	var limbs: Array = ContentDB.get_or_empty(THRALL)["limbs"]
	assert_gt(limbs.size(), 2)
	for i in limbs.size():
		assert_false(EnemyAbilities.next_limb(limbs, i).is_empty())
	assert_true(EnemyAbilities.next_limb(limbs, limbs.size()).is_empty(), "there is nothing left to break")


func test_a_broken_limb_swaps_the_moveset() -> void:
	var current: Array = [{"name": "hammerfall"}, {"name": "backhand"}]
	var limb := {"remove_attacks": ["hammerfall"], "add_attacks": [{"name": "stone_sweep"}], "poise_loss": 20.0, "speed_mult": 1.2}
	var after := EnemyAbilities.attacks_after_limb(current, limb)
	var names: Array[String] = []
	for a in after:
		names.append(str((a as Dictionary)["name"]))
	assert_false(names.has("hammerfall"), "the arm it swung with is gone")
	assert_true(names.has("backhand"))
	assert_true(names.has("stone_sweep"), "and the stump has its own answer")
	assert_near(EnemyAbilities.poise_after_limb(90.0, limb), 70.0)
	assert_near(EnemyAbilities.speed_after_limb(2.0, limb), 2.4)
	assert_true(EnemyAbilities.poise_after_limb(10.0, {"poise_loss": 999.0}) >= 1.0, "poise never reaches zero")


func test_breaking_a_thralls_poise_breaks_a_limb() -> void:
	var e := _enemy(THRALL)
	var broken: Array = []
	e.limb_broken.connect(func(i: int, _l: Dictionary) -> void: broken.append(i))
	var names_before := e.current_attacks.size()
	var poise_before := e.poise_max
	var speed_before := e.speed

	e.poise_comp.apply(e.poise_max + 1.0)           # one clean stagger

	assert_eq(e.limbs_broken(), 1, "a limb went")
	assert_eq(broken, [0])
	assert_true(e.poise_max < poise_before, "and it is easier to stagger now")
	assert_gt(e.speed, speed_before, "and lighter on its feet without the arm")
	assert_eq(e.current_attacks.size(), names_before, "one attack traded for another")
	var names: Array[String] = []
	for a in e.current_attacks:
		names.append(str((a as Dictionary)["name"]))
	assert_false(names.has("hammerfall"))
	assert_true(names.has("stone_sweep"))


func test_a_thrall_survives_a_save_with_its_limbs_where_it_left_them() -> void:
	var e := _enemy(THRALL)
	e.poise_comp.apply(e.poise_max + 1.0)
	e.poise_comp.apply(e.poise_max + 1.0)
	assert_eq(e.limbs_broken(), 2)
	var saved := e.to_save()

	var fresh := _enemy(THRALL)
	fresh.from_save(saved)
	assert_eq(fresh.limbs_broken(), 2, "it does not grow them back over a save")
	var names: Array[String] = []
	for a in fresh.current_attacks:
		names.append(str((a as Dictionary)["name"]))
	assert_true(names.has("headbutt"))


func test_resting_puts_a_thrall_back_together() -> void:
	var e := _enemy(THRALL)
	e.poise_comp.apply(e.poise_max + 1.0)
	assert_eq(e.limbs_broken(), 1)
	e.reset_to_spawn()
	assert_eq(e.limbs_broken(), 0, "a thrall you walked away from is whole when you come back")
	assert_near(e.poise_max, float(ContentDB.get_or_empty(THRALL)["stats"]["poise"]))
	assert_near(e.speed, float(ContentDB.get_or_empty(THRALL)["stats"]["speed"]))


# --- bursts and projectiles ---------------------------------------------------------------------------

func test_a_burst_knows_its_radius() -> void:
	var shriek := _attack(ContentDB.get_or_empty(HAG), "the_shriek")
	assert_true(EnemyAbilities.is_burst(shriek))
	assert_near(EnemyAbilities.burst_radius(shriek), float(shriek["radius"]))
	assert_false(EnemyAbilities.is_burst(_attack(ContentDB.get_or_empty(HAG), "clawing")))
	# An attack with no radius falls back on its reach rather than hitting nothing.
	assert_near(EnemyAbilities.burst_radius({"range": 4.0}), 4.0)


func test_a_shriek_reaches_everyone_in_the_circle_and_silences_them() -> void:
	var e := _enemy(HAG)
	e.global_position = Vector3.ZERO
	var near := Actor.new()
	near.faction = "player"
	_tree().root.add_child(near)
	_spawned.append(near)
	near.global_position = Vector3(3.0, 0.0, 0.0)
	var far := Actor.new()
	far.faction = "player"
	_tree().root.add_child(far)
	_spawned.append(far)
	far.global_position = Vector3(40.0, 0.0, 0.0)
	await _tree().physics_frame
	await _tree().physics_frame

	e._burst(_attack(ContentDB.get_or_empty(HAG), "the_shriek"))
	assert_true(near.status.has("silenced"), "the one in the gorge with her loses the word")
	assert_true(near.health < near.max_health)
	assert_false(far.status.has("silenced"), "the one up the path keeps it")
	assert_near(far.health, far.max_health)


func test_a_leap_lifts_and_a_charge_does_not() -> void:
	var drop := {"kind": "leap", "leap_up": 5.5}
	assert_true(EnemyAbilities.is_leap(drop))
	assert_near(EnemyAbilities.leap_lift(drop), 5.5)
	assert_false(EnemyAbilities.is_leap({"kind": "charge"}))
	assert_gt(EnemyAbilities.leap_lift({}), 0.0, "a leap with no height still leaves the ground")


func test_a_weaver_that_drops_is_actually_in_the_air() -> void:
	var e := _enemy("core:enemy/weaver")
	var victim := Actor.new()
	victim.faction = "player"
	_tree().root.add_child(victim)
	_spawned.append(victim)
	victim.global_position = e.global_position + Vector3(6.0, 0.0, 0.0)
	e.target = victim
	e._start_charge(_attack(ContentDB.get_or_empty("core:enemy/weaver"), "the_drop"))
	assert_gt(e.velocity.y, 0.0, "it left the branch")


func test_a_loosed_arrow_becomes_a_projectile_in_the_world() -> void:
	var e := _enemy("core:enemy/poacher")
	var victim := Actor.new()
	victim.faction = "player"
	_tree().root.add_child(victim)
	_spawned.append(victim)
	victim.global_position = e.global_position + Vector3(0.0, 0.0, 18.0)
	e.target = victim
	var before := _tree().root.get_tree().get_nodes_in_group("player").size()
	e._loose(_attack(ContentDB.get_or_empty("core:enemy/poacher"), "loosed_arrow"))
	var found: Projectile = null
	for n in (_tree().current_scene if _tree().current_scene != null else _tree().root).get_children():
		if n is Projectile:
			found = n
	assert_true(found != null, "an arrow is in the air")
	assert_gt(found.velocity.length(), 1.0, "and it is going somewhere")
	assert_true(found.hit != null and found.hit.attacker == e, "and it belongs to the poacher who loosed it")
	assert_eq(before, _tree().root.get_tree().get_nodes_in_group("player").size())
	if found != null:
		found.queue_free()
