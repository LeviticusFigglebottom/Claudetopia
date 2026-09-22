extends Node3D
## Headless fights (`./run.sh fights`): a scripted player of a starting Calling takes on one enemy
## of every archetype DESIGN §5.4 names that the pack has, one fight after another on a flat floor,
## and the run reports how long each fight took, how many blows the player took, and which are
## trivial or cannot be won. It runs with `--fixed-fps 60`, so a minute of fighting costs whatever
## the machine needs rather than a minute, and every run of it is the same run.
##
## The player is scripted, not good. It sees a telegraph a quarter second after it starts, and rolls
## so the blow lands a fifth of a second into the roll, inside the i-frames; it swings when nothing
## is about to land and it has a roll's stamina in hand, uses a heavy to finish a foe's poise, and
## closes the distance otherwise, running when it is more than a step out of reach. It never
## blocks, because no starting kit carries a shield, and it never heals, because the flask DESIGN
## §5.5 refills at a Hearthstone does not exist yet and a loaf mends 8. So the numbers are a floor
## for a patient player at level 1, not a measure of what anybody will feel.
##
## Flags: "trivial" is under TRIVIAL_SECONDS without a blow taken; "not won in 120 s" is a fight
## still going at the limit (the row says how much of the foes' health was left); "unwinnable for
## this player" is a fight the player died in.
##
## Along the way it checks what DESIGN promises and a playthrough would notice first:
##   * every blow that reaches the player was telegraphed for at least as long as its attack says;
##   * lock-on takes a target inside the 30 m cone and cycles only among targets inside it;
##   * a parry pressed inside the window opens a riposte, and one pressed outside it does not;
##   * a roll's i-frames take a blow without a scratch;
##   * a foe whose poise reaches zero staggers.
## Any of those failing fails the run (exit 1). The table is printed either way; a fight lost or
## run out of time is reported as that, not as a failure, because it is a finding about the
## numbers, and the numbers are the design's to change.

const PLAYER_SCENE := "res://actors/player/player.tscn"
const FRAME := 1.0 / 60.0
const TIME_LIMIT := 120.0
const REACTION := 0.25
const ROLL_LEAD := 0.2
const START := Vector3(0.0, 0.05, 0.0)
const FOE_DISTANCE := 9.0
## Trivial: over quickly and nothing landed. A finding, not a failure.
const TRIVIAL_SECONDS := 8.0
## The enemies roll dice (which attack, whether to swing this frame); the dice are seeded so that
## a run can be repeated and a change measured against the run before it.
const SEED := 5150
const CALLINGS: Array[String] = ["core:calling/hearthkeeper", "core:calling/cragborn"]
## One foe per archetype, the first a traveller meets: the start region's where it has one, then
## the next region by danger.
const ROSTER := [
	{"archetype": "skirmisher", "enemy": "core:enemy/roadside_bandit", "count": 1},
	{"archetype": "pack", "enemy": "core:enemy/down_wolf", "count": 3},
	{"archetype": "brute", "enemy": "core:enemy/hedge_wight", "count": 1},
	{"archetype": "charger", "enemy": "core:enemy/bristleback", "count": 1},
	{"archetype": "ambusher", "enemy": "core:enemy/sallowjaw", "count": 1},
	{"archetype": "caster", "enemy": "core:enemy/smuggler_sayer", "count": 1},
	{"archetype": "sentinel", "enemy": "core:enemy/warden", "count": 1},
	{"archetype": "swarm", "enemy": "core:enemy/gutter_drake", "count": 4},
	{"archetype": "elite", "enemy": "core:enemy/bravo", "count": 1},
	{"archetype": "boss", "enemy": "core:boss/barrow_reeve", "count": 1},
]

var results: Array[Dictionary] = []
var checks: Dictionary = {}          # name -> {"pass": bool, "seen": int, "detail": String}

# per-fight state
var _player: Player = null
var _foes: Array[Enemy] = []
var _threats: Array[Dictionary] = []
var _telegraphs: Dictionary = {}     # attacker id -> {attack name -> frame}
var _taps: Dictionary = {}           # action -> frames left to hold
var _held: Dictionary = {}           # action -> true, this frame
var _stats: Dictionary = {}
var _parry_plan: Array[String] = []  # "inside", "outside" still to try, this fight
var _trace := ""                     # --trace=<archetype>: print the fight twice a second
var _partial := false                # --only=<archetype,...>: a check that never came up is not a failure


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160.0, 1.0, 160.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	add_child(floor_body)
	for c in ["telegraphed", "lock_on", "parry_inside", "parry_outside", "dodge", "stagger"]:
		checks[c] = {"pass": true, "seen": 0, "detail": ""}
	# A script error inside a fight abandons the coroutine and would leave the run idling for ever;
	# this ends it instead, as a failure, well after the longest honest run could have finished.
	get_tree().create_timer(TIME_LIMIT * float(ROSTER.size() * CALLINGS.size()) * 1.5, true, true).timeout.connect(
		func() -> void:
			print("FIGHTS: FAIL (the run never reached its verdict)")
			get_tree().quit(2))
	call_deferred("_run")


func _run() -> void:
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	await get_tree().physics_frame
	seed(SEED)
	var only := ""
	var archetypes: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--calling="):
			only = a.substr(10)
		elif a.begins_with("--trace="):
			_trace = a.substr(8)
		elif a.begins_with("--only="):
			archetypes = Array(a.substr(7).split(","))
			_partial = true
	print("FIGHTS: calling | archetype | enemy | outcome | time s | blows taken | damage taken | player hits/swings | dealt per hit | foe hp left | foes standing | rolled | staggered")
	for calling in CALLINGS:
		if only != "" and not calling.ends_with(only):
			continue
		for fight in ROSTER:
			if not archetypes.is_empty() and not archetypes.has(str(fight["archetype"])):
				continue
			var r: Dictionary = await _fight(calling, fight)
			results.append(r)
			print("FIGHT | %s | %s | %s | %s | %.1f | %d | %.0f | %d/%d | %.1f | %.0f%% | %d/%d | %d | %d%s" % [
				Ids.name_of(calling), r["archetype"], Ids.name_of(str(r["enemy"])), r["outcome"], float(r["seconds"]),
				int(r["blows"]), float(r["damage"]), int(r["landed"]), int(r["swings"]),
				float(r["dealt"]) / maxf(float(r["landed"]), 1.0), float(r["left"]) * 100.0, int(r["standing"]), int(r["foes"]),
				int(r["rolled"]), int(r["staggered"]),
				("  <- " + str(r["flag"])) if str(r["flag"]) != "" else ""])
	_verdict()


# --- one fight -----------------------------------------------------------------------------------

func _fight(calling: String, fight: Dictionary) -> Dictionary:
	Hearth.rest_at("fights", START, 0.0, false)
	var stage := Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	var spawner := EnemySpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_on_ready = false
	spawner.respawn_on_rest = false
	stage.add_child(spawner)
	_player = _make_player(calling, stage)
	_foes.clear()
	_threats.clear()
	_telegraphs.clear()
	_taps.clear()
	_stats = {"blows": 0, "damage": 0.0, "landed": 0, "swings": 0, "rolled": 0, "staggered": 0, "riposted": 0}
	_player.attack_started.connect(func(_k: String, _i: int) -> void: _stats["swings"] = int(_stats["swings"]) + 1)
	_parry_plan.clear()
	if str(fight["archetype"]) == "skirmisher":
		_parry_plan.append_array(["inside", "outside"])
	await _frames(3)
	spawner.spawned.connect(_watch_foe)
	var count := int(fight["count"])
	for i in count:
		var a := TAU * float(i) / float(count)
		var at := START + Vector3(sin(a) * 2.0 if count > 1 else 0.0, 0.0, -FOE_DISTANCE + (cos(a) * 2.0 if count > 1 else 0.0))
		spawner.spawn_one(str(fight["enemy"]), at, PI)
	await _frames(2)
	for e in _foes:
		e.perception.alert_to(_player.global_position, _player)
	if str(fight["archetype"]) == "pack":
		_check_lock_on()
	_player.hit_taken.connect(_on_player_hit)
	var start_frame := Engine.get_physics_frames()
	var hp_start := _player.health
	var outcome := "timeout"
	while true:
		await get_tree().physics_frame
		var so_far := float(Engine.get_physics_frames() - start_frame) * FRAME
		if _player.is_dead():
			outcome = "lost"
			break
		if _living().is_empty():
			outcome = "won"
			break
		if so_far > TIME_LIMIT:
			break
		_drive()
		if _trace == str(fight["archetype"]) and Engine.get_physics_frames() % 30 == 0:
			_print_trace(so_far)
	var seconds := float(Engine.get_physics_frames() - start_frame) * FRAME
	_release_all()
	if _player.hit_taken.is_connected(_on_player_hit):
		_player.hit_taken.disconnect(_on_player_hit)
	# What the player took off them, and what was left standing: a timeout reads very differently
	# at 90% left than at 5%.
	var dealt := 0.0
	var pool := 0.0
	var standing := 0
	for e in _foes:
		if is_instance_valid(e):
			pool += e.max_health
			dealt += e.max_health - maxf(e.health, 0.0) if not e.is_dead() else e.max_health
			if not e.is_dead():
				standing += 1
	var r := {
		"calling": calling, "archetype": fight["archetype"], "enemy": fight["enemy"], "outcome": outcome,
		"dealt": dealt, "left": 1.0 - dealt / maxf(pool, 1.0), "standing": standing, "foes": _foes.size(),
		"seconds": seconds, "blows": _stats["blows"], "damage": maxf(hp_start - _player.health, 0.0) if outcome != "lost" else hp_start,
		"landed": _stats["landed"], "swings": _stats["swings"], "rolled": _stats["rolled"], "staggered": _stats["staggered"],
	}
	match outcome:
		"lost": r["flag"] = "unwinnable for this player: it died"
		"timeout": r["flag"] = "not won in %d s" % int(TIME_LIMIT)
		_: r["flag"] = "trivial" if seconds < TRIVIAL_SECONDS and int(r["blows"]) == 0 else ""
	var died := outcome == "lost"
	stage.queue_free()
	_player = null
	_foes.clear()
	await _frames(3)
	if died:
		# Hearth's respawn timer cannot be cancelled; let it fire into an empty world rather than
		# into the next fight's player.
		await _frames(int((Hearth.RESPAWN_DELAY + 0.5) / FRAME))
	return r


func _make_player(calling: String, parent: Node) -> Player:
	GameState.set_flag("new_game", false)
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	parent.add_child(p)
	p.global_position = START
	p.rotation.y = 0.0
	p.camera_rig.yaw = 0.0
	var prog := p.get_node("Progression") as Progression
	var bag := p.get_node("Inventory") as Inventory
	var doll := p.get_node("Equipment") as Equipment
	prog.apply_calling(calling, bag)
	for s in bag.stacks():
		if s.is_weapon() and not s.is_ranged():
			doll.equip(s)
			break
	for s in bag.stacks():
		if s.is_armour():
			doll.equip(s)
	p.full_restore()
	return p


func _watch_foe(e: Node3D) -> void:
	if not (e is Enemy):
		return
	var foe := e as Enemy
	_foes.append(foe)
	foe.telegraph.connect(_on_telegraph.bind(foe))
	foe.staggered.connect(_on_foe_staggered.bind(foe))
	foe.hit_taken.connect(_on_foe_hit.bind(foe))


func _living() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in _foes:
		if is_instance_valid(e) and not e.is_dead():
			out.append(e)
	return out


# --- what the foes do --------------------------------------------------------------------------

func _attack_named(e: Enemy, attack_name: String) -> Dictionary:
	for a in e.current_attacks:
		if str(a.get("name", "")) == attack_name:
			return a
	for a in e.attacks:
		if str(a.get("name", "")) == attack_name:
			return a
	return {}


## When a telegraphed blow will land where the player is standing: the wind-up, and for a thing
## that crosses the floor (a charge, an arrow, a saying) the time it takes to cross it.
func _on_telegraph(attack_name: String, duration: float, foe: Enemy) -> void:
	var id := foe.get_instance_id()
	if not _telegraphs.has(id):
		_telegraphs[id] = {}
	(_telegraphs[id] as Dictionary)[attack_name] = Engine.get_physics_frames()
	if _player == null:
		return
	var a := _attack_named(foe, attack_name)
	var dist := foe.global_position.distance_to(_player.global_position)
	var lands := Actor.now() + duration
	match str(a.get("kind", "")):
		"charge", "leap":
			lands += dist / maxf(foe.speed * Enemy.CHARGE_SPEED_MULT, 0.1)
		"projectile":
			lands += dist / maxf(float(a.get("speed", Enemy.PROJECTILE_SPEED)), 0.1)
		"spell":
			var spell := ContentDB.get_or_empty(str(a.get("spell", "")))
			lands += dist / maxf(SpellRuntime.speed_of(spell), 0.1)
	_threats.append({"foe": foe, "name": attack_name, "seen": Actor.now() + REACTION, "lands": lands,
		"reach": float(a.get("range", 2.5)) + 1.0, "kind": str(a.get("kind", "")), "handled": false})


func _on_player_hit(hit: HitData, outcome: String) -> void:
	var attacker := hit.attacker as Enemy
	if outcome == "dodged":
		_stats["rolled"] = int(_stats["rolled"]) + 1
		_mark("dodge", true, "")
	if outcome == "hit" or outcome == "blocked":
		_stats["blows"] = int(_stats["blows"]) + 1
	# Every blow that reached the player was telegraphed for as long as its attack says.
	if attacker == null or not is_instance_valid(attacker):
		return
	# A shockwave is the follow-through of the blow that threw it, and was telegraphed with it.
	var attack_name := hit.label.get_slice(":", 1).trim_suffix("_shockwave")
	var said: Dictionary = _telegraphs.get(attacker.get_instance_id(), {})
	var a := _attack_named(attacker, attack_name)
	var authored := float(a.get("telegraph", 0.3))
	if str(a.get("kind", "")) == "spell":
		authored = SpellRuntime.cast_time_of(ContentDB.get_or_empty(str(a.get("spell", ""))))
	if not said.has(attack_name):
		_mark("telegraphed", false, "%s's %s landed with no telegraph" % [attacker.display_name, attack_name])
		return
	var waited := float(Engine.get_physics_frames() - int(said[attack_name])) * FRAME
	var ok := waited >= authored - FRAME * 1.01
	_mark("telegraphed", ok, "" if ok else "%s's %s: telegraphed %.3f s before it landed, authored %.3f" % [attacker.display_name, attack_name, waited, authored])


func _on_foe_hit(hit: HitData, outcome: String, _foe: Enemy) -> void:
	if hit.attacker == _player and (outcome == "hit" or outcome == "blocked"):
		_stats["landed"] = int(_stats["landed"]) + 1
		if hit.crit_kind == "riposte":
			_stats["riposted"] = int(_stats["riposted"]) + 1


func _on_foe_staggered(foe: Enemy) -> void:
	_stats["staggered"] = int(_stats["staggered"]) + 1
	# A stagger from the footing going: poise was spent and has been put back to full.
	_mark("stagger", foe.poise >= foe.max_poise - 0.001, "")


func _mark(check: String, ok: bool, detail: String) -> void:
	var c: Dictionary = checks[check]
	c["seen"] = int(c["seen"]) + 1
	if not ok:
		c["pass"] = false
		if str(c["detail"]).is_empty():
			c["detail"] = detail


# --- the player's hands --------------------------------------------------------------------------

func _drive() -> void:
	_decide()
	_apply_inputs()


func _decide() -> void:
	var p := _player
	var living := _living()
	if living.is_empty():
		return
	var nearest := living[0]
	for e in living:
		if e.global_position.distance_to(p.global_position) < nearest.global_position.distance_to(p.global_position):
			nearest = e
	var to := nearest.global_position - p.global_position
	to.y = 0.0
	# The mouse: look at the nearest foe, and lock on to what is in front.
	p.camera_rig.yaw = atan2(-to.x, -to.z)
	if not p.lock.is_locked() or (p.lock.target as Actor).is_dead():
		p.lock.acquire(p.lock_point(), p.camera_rig.forward_flat())
	var target: Enemy = p.lock.target as Enemy if p.lock.is_locked() else nearest
	var tto := target.global_position - p.global_position
	tto.y = 0.0
	var dist := tto.length()
	p.camera_rig.yaw = atan2(-tto.x, -tto.z)
	var now := Actor.now()
	# What is about to land, that the player has seen and that can reach them.
	var threat := {}
	var kept: Array[Dictionary] = []
	for t in _threats:
		var foe: Enemy = t["foe"]
		if not is_instance_valid(foe) or foe.is_dead() or float(t["lands"]) < now - 0.2:
			continue
		kept.append(t)
		if bool(t["handled"]) or now < float(t["seen"]):
			continue
		var reach := float(t["reach"])
		var ranged: bool = str(t["kind"]) in ["projectile", "spell", "charge", "leap", "burst"]
		if not ranged and foe.global_position.distance_to(p.global_position) > reach:
			continue
		if threat.is_empty() or float(t["lands"]) < float(threat["lands"]):
			threat = t
	_threats = kept
	var weapon := p.weapon
	var light_cost := weapon.stamina_cost("light")
	var reach_now := weapon.reach + 0.35
	if not threat.is_empty():
		var until := float(threat["lands"]) - now
		if not _parry_plan.is_empty() and threat["foe"] == target and p.can_parry_with_equipment():
			# The parry check, on this fight's first two blows: one pressed inside the window,
			# one pressed early enough to be outside it.
			var plan := _parry_plan[0]
			var press_at := 0.1 if plan == "inside" else 0.34
			if until <= press_at:
				threat["handled"] = true
				_parry_plan.pop_front()
				_tap("block", 2)
				_check_parry_later(plan, target)
				return
		elif until <= ROLL_LEAD and p.stamina > 0.0 and p.state in [Player.State.FREE, Player.State.ATTACK]:
			threat["handled"] = true
			_tap("dodge", 2)
			return
	# A foe a parry opened is ripe for the riposte.
	if target.is_riposte_open() and dist <= Player.RIPOSTE_RANGE and p.state == Player.State.FREE:
		_tap("attack_light", 2)
		return
	var danger_soon := false
	for t in _threats:
		if float(t["lands"]) - now < 0.6 and not bool(t["handled"]):
			danger_soon = true
	var reserve := DamageModel.STAMINA_DODGE if not danger_soon else DamageModel.STAMINA_DODGE + light_cost
	if dist <= reach_now and p.state == Player.State.FREE and not danger_soon:
		var heavy_poise := weapon.poise_damage * DamageModel.HEAVY_POISE_MULT
		if target.poise <= heavy_poise and p.stamina >= weapon.stamina_cost("heavy") + DamageModel.STAMINA_DODGE:
			_tap("attack_heavy", 2)
		elif p.stamina >= light_cost + reserve:
			_tap("attack_light", 2)
	if dist > reach_now * 0.85:
		_held["move_forward"] = true
		# Out of reach by more than a step, and with two rolls and a swing to spare: run. A caster
		# that keeps its distance backs off at about 3 m/s, which a walk (4.2 m/s) barely gains on.
		if dist > reach_now * 1.6 and p.stamina > DamageModel.STAMINA_DODGE * 2.0 + light_cost:
			_held["sprint"] = true


func _tap(action: String, frames: int) -> void:
	_taps[action] = frames


func _apply_inputs() -> void:
	for a in _taps.keys():
		if int(_taps[a]) > 0:
			_held[a] = true
			_taps[a] = int(_taps[a]) - 1
		else:
			_taps.erase(a)
	for a in Player.ACTIONS + ["move_forward", "move_back", "move_left", "move_right"]:
		var want := _held.has(a)
		if want and not Input.is_action_pressed(a):
			Input.action_press(a)
		elif not want and Input.is_action_pressed(a):
			Input.action_release(a)
	_held.clear()


func _release_all() -> void:
	_taps.clear()
	_held.clear()
	for a in Player.ACTIONS + ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await get_tree().physics_frame



## One line per half second of a traced fight: where everybody is and what they are doing.
func _print_trace(t: float) -> void:
	var p := _player
	var line := "TRACE %5.1f | player %s %s hp %.0f st %.0f lock %s" % [t, _v(p.global_position), Player.State.keys()[p.state],
		p.health, p.stamina, (p.lock.target as Node).name if p.lock.is_locked() else "-"]
	for e in _foes:
		if not is_instance_valid(e) or e.is_dead():
			continue
		line += " || %s %s d %.1f %s hp %.0f po %.0f atk %s" % [e.name, _v(e.global_position),
			e.global_position.distance_to(p.global_position), e.brain.state, e.health, e.poise, str(e.is_busy())]
	print(line)


static func _v(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]

# --- the checks that need watching ---------------------------------------------------------------

## A parry pressed inside the window opens the foe for a riposte; one pressed early does not.
func _check_parry_later(plan: String, foe: Enemy) -> void:
	for i in 40:
		await get_tree().physics_frame
		if not is_instance_valid(foe) or foe.is_dead():
			return
		if foe.is_riposte_open():
			break
	var opened := is_instance_valid(foe) and foe.is_riposte_open()
	if plan == "inside":
		_mark("parry_inside", opened, "a parry pressed 0.10 s before the blow did not open a riposte")
	else:
		_mark("parry_outside", not opened, "a parry pressed 0.34 s before the blow opened a riposte")


## Lock-on, against a pack standing in front: the first target is inside 30 m and the cone, and
## cycling visits the others without leaving it.
func _check_lock_on() -> void:
	var p := _player
	var origin := p.lock_point()
	var fwd := p.camera_rig.forward_flat()
	p.lock.acquire(origin, fwd)
	var visited := {}
	var ok := p.lock.is_locked()
	var detail := "nothing was taken" if not ok else ""
	for i in 6:
		if not p.lock.is_locked():
			break
		var t := p.lock.target
		visited[t] = true
		var d := origin.distance_to(LockOn.point_of(t))
		var ang := absf(LockOn.signed_angle(origin, fwd, LockOn.point_of(t)))
		if d > DamageModel.LOCK_ON_RANGE or ang > DamageModel.LOCK_ON_CONE_DEG:
			ok = false
			detail = "the lock went to something %.1f m away at %.0f degrees" % [d, ang]
		p.lock.cycle(origin, fwd, 1 if i % 2 == 0 else -1)
	if visited.size() < 2:
		ok = false
		detail = "cycling never moved off the first target (%d visited)" % visited.size()
	_mark("lock_on", ok, detail)


# --- the verdict ---------------------------------------------------------------------------------

func _verdict() -> void:
	var failed := 0
	print("")
	for c in checks:
		var d: Dictionary = checks[c]
		var seen := int(d["seen"])
		var ok := bool(d["pass"]) and (seen > 0 or _partial)
		if not ok:
			failed += 1
		var why := str(d["detail"])
		if why == "" and seen == 0:
			why = "not in the fights run" if _partial else "never happened"
		print("CHECK | %s | %s | %d seen%s" % [c, "PASS" if ok else "FAIL", seen, (" | " + why) if why != "" else ""])
	var flagged := results.filter(func(r: Dictionary) -> bool: return str(r["flag"]) != "")
	print("FIGHTS: %d fights, %d flagged, %d checks failed" % [results.size(), flagged.size(), failed])
	print("FIGHTS: %s" % ("PASS" if failed == 0 else "FAIL"))
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(1 if failed > 0 else 0)
