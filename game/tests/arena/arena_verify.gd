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
	_report("=== Wickmere combat arena verification ===")
	await _settle(SETTLE_FRAMES)
	await _check_attack_damages_bandit()
	await _check_stamina_drain_and_regen()
	await _check_parry_opens_riposte()
	await _check_dodge_iframes()
	await _check_poise_stagger()
	await _check_wolf_pack_flanks()
	await _check_charger_knockdown()
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
