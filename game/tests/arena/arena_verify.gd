class_name ArenaVerify
extends Node
## Scripted verification of the combat loop in the test arena. Added by arena.gd and started
## with the `arena_verify [out_dir]` debug command (see the arena README section in
## systems/combat/README.md). Player actions go through Input.action_press/release so the real
## input path (buffering, edge detection, committed states) is what is exercised.
##
## Each check prints PASS/FAIL with the numbers it measured; the run exits non-zero on any
## failure so it can gate a build. Screenshots land in <out_dir>/ (default user://).

signal finished(passed: int, failed: int)

const SETTLE_FRAMES := 6
const MAX_WAIT := 8.0

var arena: Node3D = null
var player: Player = null
var out_dir: String = "user://"
var results: Array[Dictionary] = []
var shots: int = 0


func run(arena_node: Node3D, output_dir: String) -> void:
	arena = arena_node
	player = arena.player
	out_dir = output_dir if not output_dir.is_empty() else "user://"
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Clear screenshots from an earlier run so the output directory only shows this one.
	for f in DirAccess.get_files_at(out_dir):
		if f.ends_with(".png"):
			DirAccess.remove_absolute("%s/%s" % [out_dir.rstrip("/"), f])
	_report("=== Wickmere combat arena verification ===")
	await _settle(SETTLE_FRAMES)
	await _check_attack_damages_bandit()
	await _check_stamina_drain_and_regen()
	await _check_parry_opens_riposte()
	await _check_dodge_iframes()
	await _check_block_reduces_damage()
	await _check_poise_stagger()
	await _check_spell_cost_and_silence()
	await _check_bow_arrow()
	await _check_mantle()
	await _check_interaction_prompt()
	await _check_wolf_pack_flanks()
	await _check_charger_knockdown()
	await _check_boss_phases()
	await _check_death_hands_over_to_hearth()
	_summary()


# --- checks -------------------------------------------------------------------------------------

func _check_attack_damages_bandit() -> void:
	var bandit := _enemy("core:enemy/roadside_bandit")
	if bandit == null:
		_record("attack damages a bandit", false, "no bandit in the arena")
		return
	arena.reset()
	_isolate(["core:enemy/roadside_bandit"])
	await _settle(4)
	_place_player_near(bandit, 1.7)
	await _settle(4)
	var hp_before := bandit.health
	var stamina_before := player.stamina
	await _tap("attack_light")
	var landed := await _wait_until(func() -> bool: return bandit.health < hp_before, 3.0)
	await _shot("attack")
	var dealt := hp_before - bandit.health
	_record("attack damages a bandit", landed and dealt > 0.0,
		"hp %.1f -> %.1f (dealt %.1f), stamina %.1f -> %.1f" % [hp_before, bandit.health, dealt, stamina_before, player.stamina])


func _check_stamina_drain_and_regen() -> void:
	arena.reset()
	_isolate([])
	await _settle(4)
	var full := player.stamina
	await _tap("attack_light")
	await _settle(4)
	var after_attack := player.stamina
	var drained := full - after_attack
	# DESIGN §5.3: light attack costs 18, regen 30/s after 0.8 s.
	var drained_ok := absf(drained - DamageModel.STAMINA_LIGHT) < 1.5
	await _wait_seconds(1.6)
	var regenerated := player.stamina
	var regen_ok := regenerated > after_attack + 10.0
	_record("stamina drains on attack and regenerates", drained_ok and regen_ok,
		"%.1f -> %.1f (drained %.1f, expected %.1f) -> %.1f after 1.6 s" % [full, after_attack, drained, DamageModel.STAMINA_LIGHT, regenerated])


func _check_parry_opens_riposte() -> void:
	var bandit := _enemy("core:enemy/roadside_bandit")
	if bandit == null:
		_record("parry opens a riposte", false, "no bandit")
		return
	arena.reset()
	_isolate([])
	await _settle(4)
	_place_player_near(bandit, 2.0)
	player.snap_facing(bandit.global_position - player.global_position)
	await _settle(4)
	var hp_before := player.health
	# Press block: this is the parry press the window is measured from.
	Input.action_press("block")
	await _settle(2)
	# The bandit's own attack data, delivered the moment the swing would connect.
	var hit := _enemy_hit(bandit, "slash")
	var outcome := player.take_hit(hit)
	Input.action_release("block")
	await _settle(2)
	var opened := bandit.is_riposte_open()
	await _shot("parry")
	_record("parry opens a riposte", outcome == "parried" and opened,
		"outcome '%s', attacker riposte_open %s, player hp %.1f -> %.1f (window %.2f s)" % [outcome, str(opened), hp_before, player.health, DamageModel.PARRY_WINDOW])
	# The riposte itself: a 3x crit from the same weapon.
	var bandit_hp := bandit.health
	var riposte := player.weapon.build_hit("riposte", 0, 0.0, player.get_skill(player.weapon.skill_id), "riposte")
	var normal := player.weapon.build_hit("light", 0, 0.0, player.get_skill(player.weapon.skill_id))
	_record("riposte multiplies damage by 3", absf(riposte.crit_mult - 3.0) < 0.001 and absf(riposte.amount * riposte.crit_mult - normal.amount * 3.0) < 0.01,
		"normal %.1f, riposte %.1f x%.1f" % [normal.amount, riposte.amount, riposte.crit_mult])
	bandit.health = bandit_hp


func _check_dodge_iframes() -> void:
	var bandit := _enemy("core:enemy/roadside_bandit")
	arena.reset()
	_isolate([])
	await _settle(4)
	_place_player_near(bandit, 2.2)
	await _settle(4)
	var hp_before := player.health
	await _tap("dodge")
	var in_iframes := await _wait_until(func() -> bool: return player.is_in_iframes(), 1.0)
	var outcome := ""
	if in_iframes:
		outcome = player.take_hit(_enemy_hit(bandit, "slash"))
	await _shot("dodge")
	# And the same hit outside the window must land.
	await _wait_until(func() -> bool: return not player.is_in_iframes(), 2.0)
	await _settle(2)
	var hp_mid := player.health
	var outcome_after := player.take_hit(_enemy_hit(bandit, "slash"))
	_record("dodge i-frames block a hit, and the roll ends", in_iframes and outcome == "dodged" and outcome_after == "hit" and player.health < hp_mid,
		"during roll: '%s' (hp %.1f -> %.1f); after roll: '%s' (hp %.1f -> %.1f); window %.2f-%.2f s of %.2f" % [
			outcome, hp_before, hp_mid, outcome_after, hp_mid, player.health,
			DamageModel.DODGE_IFRAME_START, DamageModel.DODGE_IFRAME_END, DamageModel.DODGE_DURATION])


func _check_poise_stagger() -> void:
	var bandit := _enemy("core:enemy/roadside_bandit")
	if bandit == null:
		_record("enemy staggers at zero poise", false, "no bandit")
		return
	arena.reset()
	_isolate([])
	await _settle(4)
	_place_player_near(bandit, 1.8)
	await _settle(4)
	# Lambdas capture locals by value, so signal flags live in a Dictionary (captured by reference).
	var flags := {"staggered": false}
	bandit.staggered.connect(func() -> void: flags["staggered"] = true, CONNECT_ONE_SHOT)
	var poise_before := bandit.poise
	var swings := 0
	var per_hit := DamageModel.poise_damage(player.weapon.poise_damage, true)
	# Heavy swings: 12 poise damage x1.5 = 18 against 24 poise breaks on the second. The bandit
	# would die of the damage first, so it is topped up between swings: this checks poise, not HP.
	while swings < 4 and not bool(flags["staggered"]):
		var hit := player.weapon.build_hit("heavy", 0, 1.0, player.get_skill(player.weapon.skill_id))
		bandit.take_hit(hit)
		bandit.health = bandit.max_health
		swings += 1
		await _settle(2)
	await _shot("stagger")
	_record("enemy staggers at zero poise", bool(flags["staggered"]) and bandit.is_stunned(),
		"poise %.1f, %.1f poise damage per heavy hit, broke after %d hits, stunned %s, poise reset to %.1f" % [
			poise_before, per_hit, swings, str(bandit.is_stunned()), bandit.poise])


func _check_block_reduces_damage() -> void:
	var bandit := _enemy("core:enemy/roadside_bandit")
	if bandit == null:
		_record("blocking scales with shield stability", false, "no bandit")
		return
	arena.reset()
	_isolate([])
	await _settle(4)
	_place_player_near(bandit, 2.0)
	await _settle(4)
	# Unblocked reference hit.
	var hp0 := player.health
	var unblocked_outcome := player.take_hit(_enemy_hit(bandit, "slash"))
	var unblocked := hp0 - player.health
	player.full_restore()
	await _settle(2)
	# Same hit onto a raised round shield (stability 0.8). The guard must be held past the
	# 0.18 s parry window, or this would test the parry instead.
	Input.action_press("block")
	await _wait_seconds(0.4)
	var blocking := player.is_blocking
	var stability := player.block_stability
	var stamina0 := player.stamina
	var hp1 := player.health
	var outcome := player.take_hit(_enemy_hit(bandit, "slash"))
	var blocked := hp1 - player.health
	var stamina_cost := stamina0 - player.stamina
	Input.action_release("block")
	await _settle(2)
	await _shot("block")
	_record("blocking scales with shield stability", blocking and outcome == "blocked" and blocked < unblocked and stamina_cost > 0.0,
		"stability %.2f: unblocked %.1f hp ('%s'), blocked %.1f hp ('%s'), stamina cost %.1f" % [
			stability, unblocked, unblocked_outcome, blocked, outcome, stamina_cost])


func _check_spell_cost_and_silence() -> void:
	var bandit := _enemy("core:enemy/roadside_bandit")
	arena.reset()
	_isolate([])
	await _settle(4)
	_place_player_near(bandit, 6.0)
	player.camera_rig.pitch = 0.0
	player.equip_spell("core:spell/kindle_bolt")
	await _settle(6)
	var mana0 := player.mana
	var hp0 := bandit.health if bandit != null else 0.0
	await _tap("cast")
	await _wait_until(func() -> bool: return not player.caster.casting, 3.0)
	var spent := mana0 - player.mana
	var hit_landed := await _wait_until(func() -> bool: return bandit != null and bandit.health < hp0, 2.5)
	await _shot("spell")
	# The cost is discounted by the caster's school skill, so compare against the rule.
	var bolt := ContentDB.get_or_empty("core:spell/kindle_bolt")
	var expected := SpellRuntime.cost_of(bolt, player.get_skill("kindling"))
	_record("casting costs mana and the bolt damages its target", absf(spent - expected) < 0.5 and hit_landed,
		"mana %.1f -> %.1f (spent %.1f, expected %.1f at skill %.0f), target hp %.1f -> %.1f" % [
			mana0, player.mana, spent, expected, player.get_skill("kindling"), hp0, bandit.health if bandit else 0.0])
	# Silenced: no casting at all (DESIGN §5.3).
	var mana1 := player.mana
	player.status.apply("silenced", 5.0)
	var refused := {"reason": ""}
	player.caster.cast_failed.connect(func(_id: String, reason: String) -> void: refused["reason"] = reason, CONNECT_ONE_SHOT)
	await _tap("cast")
	await _settle(4)
	_record("silence stops casting", str(refused["reason"]) == "silenced" and absf(player.mana - mana1) < 0.6 and not player.caster.casting,
		"refusal '%s', mana unchanged (%.1f -> %.1f)" % [str(refused["reason"]), mana1, player.mana])
	player.status.clear("silenced")


func _check_bow_arrow() -> void:
	var bandit := _enemy("core:enemy/roadside_bandit")
	if bandit == null:
		_record("the bow looses an arrow that damages its target", false, "no bandit")
		return
	arena.reset()
	_isolate([])
	await _settle(4)
	_place_player_near(bandit, 5.0)
	player.camera_rig.pitch = 0.0
	player.equip_weapon("core:item/hunting_bow")
	player.arrows = 5
	await _settle(6)
	var hp0 := bandit.health
	var arrows0 := player.arrows
	# Hold to draw, then release to loose.
	Input.action_press("attack_light")
	await _wait_seconds(1.1)
	var drawing := player.state == Player.State.BOW
	Input.action_release("attack_light")
	var landed := await _wait_until(func() -> bool: return bandit.health < hp0, 3.0)
	await _shot("bow")
	_record("the bow looses an arrow that damages its target", drawing and landed and player.arrows == arrows0 - 1,
		"drawn %s, arrows %d -> %d, target hp %.1f -> %.1f" % [str(drawing), arrows0, player.arrows, hp0, bandit.health])
	player.equip_weapon("core:item/iron_sword")


func _check_mantle() -> void:
	arena.reset()
	_isolate([])
	await _settle(4)
	# The low crate at (7, 1) in the arena: 0.9 m top, inside the 0.4-1.3 m mantle band.
	player.global_position = Vector3(7.0, 0.6, 3.6)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player.camera_rig.yaw = 0.0
	await _settle(8)
	var y0 := player.global_position.y
	Input.action_press("move_forward")
	await _wait_seconds(0.8)
	Input.action_press("jump")
	await _settle(3)
	Input.action_release("jump")
	var climbed := await _wait_until(func() -> bool: return player.global_position.y > y0 + 0.25, 3.0)
	Input.action_release("move_forward")
	await _settle(10)
	await _shot("mantle")
	_record("the player mantles a low ledge", climbed and player.global_position.y > y0 + 0.25,
		"y %.2f -> %.2f (ledge at 0.90, mantle band %.1f-%.1f m)" % [y0, player.global_position.y, Player.MANTLE_MIN, Player.MANTLE_MAX])


func _check_wolf_pack_flanks() -> void:
	arena.reset()
	_isolate(["core:enemy/down_wolf"])
	await _settle(4)
	var wolves: Array[Enemy] = []
	for e in arena.spawner.all():
		if e.enemy_id == "core:enemy/down_wolf" and not e.dead:
			wolves.append(e)
	if wolves.size() < 3:
		_record("wolf pack flanks", false, "need 3 wolves, have %d" % wolves.size())
		return
	# Put the player in the open near the pack and alert them.
	player.global_position = wolves[0].global_position + Vector3(6.0, 0.6, 6.0)
	player.velocity = Vector3.ZERO
	await _settle(4)
	for w in wolves:
		w.perception.alert_to(player.global_position, player)
	# Let them close and take up their slots.
	await _wait_seconds(4.5)
	await _shot("wolves")
	var bearings: Array[float] = []
	for w in wolves:
		var to := w.global_position - player.global_position
		bearings.append(rad_to_deg(atan2(to.x, to.z)))
	bearings.sort()
	var min_gap := 360.0
	for i in bearings.size():
		var gap: float = bearings[(i + 1) % bearings.size()] - bearings[i]
		if i == bearings.size() - 1:
			gap += 360.0
		min_gap = minf(min_gap, absf(gap))
	var engaged := 0
	for w in wolves:
		if w.brain.is_fighting():
			engaged += 1
	# Flanking = they do not stack on one bearing. Three piled up would give a gap near 0.
	_record("wolf pack spreads and flanks", engaged >= 3 and min_gap > 25.0,
		"%d/3 in combat, bearings %s, smallest gap %.0f deg" % [engaged, str(bearings.map(func(b: float) -> String: return "%.0f" % b)), min_gap])


func _check_charger_knockdown() -> void:
	var boar := _enemy("core:enemy/bristleback")
	if boar == null:
		_record("charger knocks the player down", false, "no bristleback")
		return
	arena.reset()
	_isolate(["core:enemy/bristleback"])
	await _settle(4)
	# A clear lane: the arena's obstacles sit between the boar's post and the player, and a
	# charge that meets terrain correctly aborts, so the check needs open ground.
	var lane := Vector3(15.0, 0.6, 18.0)
	boar.global_position = lane
	boar.spawn_position = lane
	boar.brain.post = lane
	boar.velocity = Vector3.ZERO
	# Stand in its lane, well beyond the charge's minimum range.
	player.global_position = lane + Vector3(0.0, 0.0, -9.0)
	player.velocity = Vector3.ZERO
	await _settle(4)
	# Signal flags go in a Dictionary: GDScript lambdas capture plain locals by value.
	var flags := {"knocked": false, "telegraph": "", "telegraph_time": 0.0, "status": false}
	player.knocked_down.connect(func() -> void:
		flags["knocked"] = true
		flags["status"] = player.status.has("knockdown"), CONNECT_ONE_SHOT)
	boar.telegraph.connect(func(n: String, d: float) -> void:
		flags["telegraph"] = n
		flags["telegraph_time"] = d, CONNECT_ONE_SHOT)
	var log_hits: Array[String] = []
	player.hit_taken.connect(func(h: HitData, outcome: String) -> void:
		log_hits.append("%s/%s%s" % [h.label, outcome, "/KD" if h.knockdown else ""]))
	boar.perception.alert_to(player.global_position, player)
	var hp_before := player.health
	var got := await _wait_until(func() -> bool: return bool(flags["knocked"]), MAX_WAIT)
	_report("        hits on the player: %s" % str(log_hits))
	await _shot("charge")
	_record("charger telegraphs, charges and knocks the player down",
		got and bool(flags["status"]) and str(flags["telegraph"]) == "tusk_charge",
		"telegraph '%s' (%.2f s wind-up before the hit window), knockdown %s, player hp %.1f -> %.1f" % [
			str(flags["telegraph"]), float(flags["telegraph_time"]), str(flags["knocked"]), hp_before, player.health])


# --- helpers ------------------------------------------------------------------------------------

func _check_interaction_prompt() -> void:
	arena.reset()
	_isolate([])
	await _settle(4)
	var post: StaticBody3D = arena.signpost
	if post == null:
		_record("looking at an interactable shows a prompt", false, "no signpost in the arena")
		return
	# Stand in front of the signpost, looking at it.
	player.global_position = post.global_position + Vector3(0.0, 0.6, 1.8)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player.camera_rig.yaw = 0.0
	player.camera_rig.pitch = 0.0
	var seen := {"prompt": "", "notified": ""}
	player.interactor.prompt_changed.connect(func(text: String) -> void:
		if not text.is_empty():
			seen["prompt"] = text)
	var on_notify := func(text: String, kind: String) -> void:
		if kind == "read":
			seen["notified"] = text
	EventBus.notify.connect(on_notify)
	await _wait_until(func() -> bool: return player.interactor.has_target(), 2.0)
	var targeted := player.interactor.has_target()
	var used_before: int = post.get("times_used")
	await _tap("interact")
	await _settle(6)
	await _shot("interact")
	var used_after: int = post.get("times_used")
	# Walk away: the prompt must clear.
	player.global_position += Vector3(0.0, 0.0, 12.0)
	await _settle(6)
	var cleared := not player.interactor.has_target()
	EventBus.notify.disconnect(on_notify)
	_record("looking at an interactable shows a prompt, and interacting fires it",
		targeted and str(seen["prompt"]).contains("signpost") and used_after == used_before + 1 and cleared,
		"prompt '%s', interacted %d -> %d, notify '%s', prompt cleared on walking away: %s" % [
			str(seen["prompt"]), used_before, used_after, str(seen["notified"]).left(28), str(cleared)])


## Boss machinery: no core boss content exists yet (bosses belong to the world stream), so the
## phase table is applied to a spawned enemy here to prove the swap and the EventBus signals.
func _check_boss_phases() -> void:
	arena.reset()
	_isolate([])
	await _settle(4)
	var boss: Enemy = arena.spawner.spawn_one("core:enemy/hedge_wight", Vector3(-20.0, 0.6, 20.0), 0.0)
	if boss == null:
		_record("boss phases swap attack sets and emit boss events", false, "could not spawn")
		return
	boss.is_boss = true
	boss.phases = [
		{"hp": 1.0, "attacks": boss.attacks.slice(0, 1), "aggression": 0.5},
		{"hp": 0.5, "attacks": boss.attacks, "aggression": 1.0, "say": "The second phase."},
	]
	var seen := {"started": "", "defeated": "", "phase": -1}
	EventBus.boss_started.connect(func(id: String) -> void: seen["started"] = id, CONNECT_ONE_SHOT)
	EventBus.boss_defeated.connect(func(id: String) -> void: seen["defeated"] = id, CONNECT_ONE_SHOT)
	boss.phase_changed.connect(func(index: int, _p: Dictionary) -> void: seen["phase"] = index)
	boss._enter_phase(0)
	await _settle(2)
	var first_set: int = boss.current_attacks.size()
	boss.start_boss()
	# Drive it past the 50% threshold.
	boss.health = boss.max_health * 0.4
	await _settle(4)
	var second_set: int = boss.current_attacks.size()
	var swapped: bool = int(seen["phase"]) == 1 and second_set > first_set
	boss.die(player)
	await _settle(4)
	_record("boss phases swap attack sets and emit boss events",
		swapped and str(seen["started"]) == boss.enemy_id and str(seen["defeated"]) == boss.enemy_id,
		"phase 0 had %d attacks, phase 1 has %d at <=50%% hp; boss_started '%s', boss_defeated '%s'" % [
			first_set, second_set, str(seen["started"]), str(seen["defeated"])])
	boss.queue_free()


## The hand-off to systems/hearth: combat emits player_died and implements full_restore()/
## respawn(); the Hearth autoload owns the respawn point, the delay and the Echo.
func _check_death_hands_over_to_hearth() -> void:
	arena.reset()
	_isolate([])
	await _settle(4)
	player.global_position = Vector3(-18.0, 0.6, -18.0)
	await _settle(4)
	var seen := {"died": false, "respawned": false, "deaths": Hearth.deaths}
	EventBus.player_died.connect(func(_p: Vector3) -> void: seen["died"] = true, CONNECT_ONE_SHOT)
	EventBus.player_respawned.connect(func(_id: String) -> void: seen["respawned"] = true, CONNECT_ONE_SHOT)
	player.kill()
	await _settle(2)
	var died_once := bool(seen["died"]) and player.is_dead()
	var death_spot := player.global_position
	# Hearth waits RESPAWN_DELAY before putting the player back.
	var back := await _wait_until(func() -> bool: return bool(seen["respawned"]), 8.0)
	await _settle(8)
	await _shot("respawn")
	var at_respawn := player.global_position.distance_to(Hearth.respawn_position) < 2.0
	var moved_back := player.global_position.distance_to(death_spot) > 5.0
	_record("death emits player_died and the Hearth autoload respawns the player",
		died_once and back and at_respawn and moved_back and not player.is_dead() and player.health == player.max_health,
		"died at %s, respawned at %s (point %s), hp %.1f/%.1f, deaths %d -> %d" % [
			str(death_spot.round()), str(player.global_position.round()), str(Hearth.respawn_position.round()),
			player.health, player.max_health, int(seen["deaths"]), Hearth.deaths])


## Test-harness isolation: everything not under test stops perceiving and goes home, so a check
## measures its own subject instead of whatever else wandered into the fight.
func _isolate(keep_ids: Array) -> void:
	for e in arena.spawner.all():
		var keep: bool = keep_ids.has(e.enemy_id)
		e.perception.enabled = keep
		if not keep:
			e.perception.reset()
			e.on_action_interrupted()
			e.brain.force(Brain.RETURN)


func _enemy(id: String) -> Enemy:
	for e in arena.spawner.all():
		if e.enemy_id == id:
			return e
	return null


## Builds the HitData an enemy's named attack would deliver (same path its hitbox uses).
func _enemy_hit(enemy: Enemy, attack_name: String) -> HitData:
	var attack := {}
	for a in enemy.attacks:
		if str(a.get("name", "")) == attack_name:
			attack = a
	var hit := HitData.new()
	hit.amount = float(attack.get("damage", 10.0))
	hit.kind = DamageModel.kind_for_class(str(attack.get("weapon_class", "sword")))
	hit.poise_damage = float(attack.get("poise_damage", 10.0))
	hit.heavy = bool(attack.get("heavy", false))
	hit.attacker = enemy
	hit.origin = enemy.global_position
	hit.label = "%s:%s" % [Ids.name_of(enemy.enemy_id), attack_name]
	return hit


func _place_player_near(enemy: Enemy, distance: float) -> void:
	if enemy == null:
		return
	var dir := Vector3(0.0, 0.0, 1.0)
	player.global_position = enemy.global_position + dir * distance + Vector3.UP * 0.6
	player.velocity = Vector3.ZERO
	player.snap_facing(enemy.global_position - player.global_position)
	player.camera_rig.yaw = player.rotation.y


func _tap(action: String, frames: int = 3) -> void:
	Input.action_press(action)
	await _settle(frames)
	Input.action_release(action)
	await _settle(1)


func _settle(frames: int) -> void:
	for i in maxi(frames, 1):
		await get_tree().physics_frame


func _wait_seconds(seconds: float) -> void:
	await _settle(int(seconds * Engine.physics_ticks_per_second))


func _wait_until(predicate: Callable, timeout: float) -> bool:
	var frames := int(timeout * Engine.physics_ticks_per_second)
	for i in frames:
		if bool(predicate.call()):
			return true
		await get_tree().physics_frame
	return bool(predicate.call())


func _shot(label: String) -> void:
	await get_tree().process_frame
	var vp := get_viewport()
	if vp == null:
		return
	var image := vp.get_texture().get_image()
	if image == null:
		return
	shots += 1
	var path := "%s/%02d_%s.png" % [out_dir.rstrip("/"), shots, label]
	image.save_png(path)


func _record(name: String, passed: bool, detail: String) -> void:
	results.append({"name": name, "passed": passed, "detail": detail})
	_report("%s  %s\n        %s" % ["PASS" if passed else "FAIL", name, detail])


func _report(line: String) -> void:
	print(line)


func _summary() -> void:
	var passed := 0
	for r in results:
		if bool(r["passed"]):
			passed += 1
	var failed := results.size() - passed
	_report("=== %d checks, %d passed, %d failed, %d screenshots in %s ===" % [results.size(), passed, failed, shots, out_dir])
	finished.emit(passed, failed)
