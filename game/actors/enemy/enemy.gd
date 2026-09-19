class_name Enemy
extends Actor
## A hostile actor driven by its enemy def (CONTRACTS §7) and a Brain (DESIGN §5.4).
## Steering is direct with ground snapping, using a NavigationAgent3D only when the scene has a
## NavigationRegion3D. Attacks are chosen by range and cooldown and always telegraph before the
## hit window. Archetype flavour: pack spread/flank, charger line charge with knockdown, caster
## keeps distance, ambusher waits inactive, sentinel never leaves its post, brute hyper-armour,
## skirmisher hits and retreats. Bosses swap attack sets at hp thresholds.

signal state_changed(from: String, to: String)
signal telegraph(attack_name: String, duration: float)
signal attack_launched(attack_name: String)
signal phase_changed(index: int, phase: Dictionary)
signal mark_dropped(enemy_id: String, position: Vector3)
signal summoned(enemies: Array)

const TURN_SPEED := 7.0
const ACCEL := 12.0
const ARRIVE := 0.6
const REPATH := 0.35
const SEARCH_RADIUS := 7.0
const STRAFE_FLIP := 2.5
const CHARGE_SPEED_MULT := 2.4
const CHARGE_WINDUP := 0.9
const CHARGE_MAX_TIME := 2.2
const AMBUSH_ROUSE := 0.35
const RETREAT_DISTANCE := 5.0
const PACK_CALL_RADIUS := 18.0
## Where summoned help stands up, and how many of them a summoner may have out at once.
const SUMMON_RADIUS := 4.5
const SUMMON_DEFAULT_CAP := 6
const GROUND_MASK := (1 << 0) | (1 << 10)

@export var enemy_id: String = ""
@export var patrol_points: PackedVector3Array = PackedVector3Array()

var def: Dictionary = {}
var archetype: String = "skirmisher"
var attacks: Array = []
var current_attacks: Array = []
var brain: Brain = null
var perception: Perception = null
var agent: NavigationAgent3D = null
var speed: float = 3.2
var marks_range: Array = [0, 0]
var phases: Array = []
var phase_index: int = -1
var is_boss: bool = false
var boss_started: bool = false
var spawn_position: Vector3 = Vector3.ZERO
var spawn_yaw: float = 0.0
var target: Node3D = null
var inactive: bool = false            # ambusher waiting
var pack_group: String = ""
var summons_alive: Array[Enemy] = []
## Seconds a called thing has left before it goes back where it came from; 0 means it stays.
var life_left: float = 0.0

var _attack_cooldowns: Dictionary = {}
var _current_attack: Dictionary = {}
var _attack_phase: String = ""
var _attacking: bool = false
var _global_cooldown: float = 0.0
var _strafe_sign: float = 1.0
var _strafe_timer: float = 0.0
var _retreat_timer: float = 0.0
var _repath: float = 0.0
var _charging: bool = false
var _charge_dir: Vector3 = Vector3.ZERO
var _charge_time: float = 0.0
var _has_nav: bool = false
var _desired: Vector3 = Vector3.ZERO
var _last_state: String = ""


# --- construction -------------------------------------------------------------------------------

func _ready() -> void:
	if faction == "neutral":
		faction = "hostile"
	collision_layer = LAYER_ENEMY
	if not enemy_id.is_empty():
		_read_def(ContentDB.get_or_empty(enemy_id))
	super()
	brain = get_node_or_null("Brain") as Brain
	if brain == null:
		brain = Brain.new()
		brain.name = "Brain"
		add_child(brain)
	perception = get_node_or_null("Perception") as Perception
	if perception == null:
		perception = Perception.new()
		perception.name = "Perception"
		add_child(perception)
	perception.setup(self, def)
	perception.detected.connect(_on_detected)
	perception.suspicion_raised.connect(_on_suspicion)
	perception.noise.connect(func(pos: Vector3, _l: float) -> void: _remember(pos))
	brain.patrol_points = patrol_points
	spawn_position = global_position
	spawn_yaw = rotation.y
	brain.setup(archetype, def.get("behaviour", {}), spawn_position)
	brain.state_changed.connect(_on_brain_state)
	if archetype == "ambusher":
		inactive = true
	if bool(brain.param("hyper_armour", 0.0) > 0.0):
		pass
	_setup_navigation()
	add_to_group("enemy")
	add_to_group("lockable")
	add_to_group("perceivers")
	add_to_group("actors")
	EventBus.hearthstone_rested.connect(_on_hearthstone_rested)
	died.connect(_on_died)
	if is_boss and not phases.is_empty():
		_enter_phase(0)


func _read_def(d: Dictionary) -> void:
	def = d
	if def.is_empty():
		return
	display_name = str(def.get("name", display_name))
	archetype = str(def.get("archetype", archetype))
	var stats: Dictionary = def.get("stats", {})
	max_health = float(stats.get("hp", 60.0))
	poise_max = float(stats.get("poise", 30.0))
	armour_flat = float(stats.get("armour", 0.0))
	speed = float(stats.get("speed", 3.2))
	endurance = int(stats.get("stamina", 80.0) / 8.0)
	resists = def.get("resists", {})
	attacks = def.get("attacks", [])
	current_attacks = attacks
	marks_range = def.get("marks", [0, 0])
	phases = def.get("phases", [])
	is_boss = archetype == "boss" or not phases.is_empty()
	var rig := str(def.get("rig", "humanoid"))
	body_kind = "humanoid" if rig == "humanoid" else str(def.get("body", "quadruped"))
	body_variant = str(def.get("body_variant", ""))
	body_scale = float(def.get("scale", 1.0))
	if def.has("tint"):
		tint = Color(str(def["tint"]))
	capsule_radius = float(def.get("radius", 0.35 if body_kind == "humanoid" else 0.45))
	capsule_height = float(def.get("height", 1.8 if body_kind == "humanoid" else 1.0))
	if def.has("faction"):
		faction = str(def["faction"])


func content_id() -> String:
	return enemy_id


## Spawner hook: configure from a def id before the node enters the tree.
func configure(id: String) -> void:
	enemy_id = id
	_read_def(ContentDB.get_or_empty(id))


func _setup_navigation() -> void:
	agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	_has_nav = false
	var map := get_world_3d().navigation_map
	if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
		_has_nav = true
	if _has_nav and agent == null:
		agent = NavigationAgent3D.new()
		agent.name = "NavigationAgent3D"
		agent.path_desired_distance = 0.6
		agent.target_desired_distance = ARRIVE
		agent.radius = capsule_radius
		agent.avoidance_enabled = false
		add_child(agent)
	elif not _has_nav and agent != null:
		agent.queue_free()
		agent = null


# --- main loop ----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		_damp(delta, 8.0)
		apply_gravity(delta)
		move_and_slide()
		return
	_tick_timers(delta)
	_check_phase()
	target = perception.target if perception.target != null and is_instance_valid(perception.target) else null
	var state := brain.tick(delta, _context())
	if state != _last_state:
		_last_state = state
	if is_stunned():
		_damp(delta, 10.0)
	elif _attacking:
		_tick_attack(delta)
	else:
		match state:
			Brain.IDLE: _tick_idle(delta)
			Brain.PATROL: _tick_patrol(delta)
			Brain.SUSPICIOUS: _tick_suspicious(delta)
			Brain.SEARCH: _tick_search(delta)
			Brain.COMBAT: _tick_combat(delta)
			Brain.RETURN: _tick_return(delta)
	apply_gravity(delta)
	integrate_shove(delta)
	move_and_slide()
	_update_anim()


func _tick_timers(delta: float) -> void:
	if life_left > 0.0:
		life_left -= delta
		if life_left <= 0.0:
			dismiss()
			return
	_global_cooldown = maxf(_global_cooldown - delta, 0.0)
	_strafe_timer -= delta
	_retreat_timer = maxf(_retreat_timer - delta, 0.0)
	_repath -= delta
	for k in _attack_cooldowns.keys():
		_attack_cooldowns[k] = maxf(float(_attack_cooldowns[k]) - delta, 0.0)
	if _strafe_timer <= 0.0:
		_strafe_timer = STRAFE_FLIP + randf() * 2.0
		_strafe_sign = 1.0 if randf() < 0.5 else -1.0


func _context() -> Dictionary:
	var d_target := INF
	var alive := false
	if target != null:
		d_target = global_position.distance_to(target.global_position)
		alive = not (target.has_method("is_alive") and not target.is_alive())
	return {
		"detection": perception.detection,
		"can_see": perception.can_see_target,
		"alerted": perception.has_last_known and perception.detection > 0.0,
		"target_alive": alive,
		"distance_to_post": global_position.distance_to(brain.post),
		"distance_to_target": d_target,
		"inactive": inactive,
	}


func state_name() -> String:
	return brain.state


func is_busy() -> bool:
	return _attacking


# --- states -------------------------------------------------------------------------------------

func _tick_idle(delta: float) -> void:
	_damp(delta, 8.0)
	if inactive:
		return
	rotation.y = lerp_angle(rotation.y, spawn_yaw, clampf(2.0 * delta, 0.0, 1.0))


func _tick_patrol(delta: float) -> void:
	var point := brain.current_patrol_point()
	if _move_towards(point, speed * 0.45, delta) <= ARRIVE + 0.4:
		brain.next_patrol_point()


func _tick_suspicious(delta: float) -> void:
	_damp(delta, 8.0)
	var look := perception.last_known if perception.has_last_known else global_position + forward()
	face_toward(look, TURN_SPEED * 0.6, delta)


func _tick_search(delta: float) -> void:
	if not brain.has_search_point:
		_pick_search_point()
	if _move_towards(brain.search_point, speed * 0.6, delta) <= ARRIVE + 0.5:
		_pick_search_point()


func _pick_search_point() -> void:
	var base := perception.last_known if perception.has_last_known else brain.post
	var a := randf() * TAU
	var r := randf() * SEARCH_RADIUS
	brain.search_point = base + Vector3(cos(a) * r, 0.0, sin(a) * r)
	brain.has_search_point = true


func _tick_return(delta: float) -> void:
	perception.reset()
	var home := brain.post
	if _move_towards(home, speed * 0.7, delta) <= ARRIVE + 0.3:
		_damp(delta, 10.0)
		rotation.y = lerp_angle(rotation.y, spawn_yaw, clampf(3.0 * delta, 0.0, 1.0))
		if health < max_health:
			health = minf(max_health, health + 6.0 * delta)


func _tick_combat(delta: float) -> void:
	if target == null:
		_damp(delta, 8.0)
		return
	if inactive:
		inactive = false
		anim.play_intent("Get_Up", {"length": AMBUSH_ROUSE})
		stunned_until = maxf(stunned_until, now() + AMBUSH_ROUSE)
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	face_toward(target.global_position, TURN_SPEED, delta)
	if _charging:
		_tick_charge(delta)
		return
	if _retreat_timer > 0.0:
		_strafe_or_retreat(delta, dist, true)
		return
	var attack := _select_attack(dist)
	if not attack.is_empty() and _global_cooldown <= 0.0 and can_act():
		_begin_attack(attack)
		return
	_approach_or_hold(delta, dist)


func _approach_or_hold(delta: float, dist: float) -> void:
	var keep := float(brain.param("keep_distance", 0.0))
	var engage := brain.engage_range()
	var retreat_hp := float(brain.param("retreat_threshold", 0.0))
	if retreat_hp > 0.0 and health / max_health < retreat_hp and randf() < 0.01:
		_retreat_timer = float(brain.param("retreat_time", 1.6))
		return
	if keep > 0.0:
		# caster: hold a ring around the target
		if dist < keep - 1.0:
			_step(-_to_target_flat(), speed * 0.9, delta)
			return
		if dist > keep + 2.0:
			_move_towards(target.global_position, speed, delta)
			return
		_strafe_or_retreat(delta, dist, false)
		return
	var want := engage - 0.3
	if dist > want:
		var goal := _approach_goal()
		_move_towards(goal, speed, delta)
	else:
		_strafe_or_retreat(delta, dist, false)


## Pack members take distinct bearings around the target instead of piling onto one point:
## the pack's slots are fanned evenly across `flank_arc` degrees, centred on the bearing the
## pack is approaching from, so a wolf that already holds a side keeps it and the others go wide.
func _approach_goal() -> Vector3:
	if target == null:
		return global_position
	if not bool(brain.param("flank", false)):
		return target.global_position
	var mates := _pack_mates()
	var count := mates.size() + 1
	if count <= 1:
		return target.global_position
	# Reference bearing: from the target towards the pack's centre of mass.
	var centroid := global_position
	for m in mates:
		centroid += (m as Node3D).global_position
	centroid /= float(count)
	var reference := centroid - target.global_position
	reference.y = 0.0
	if reference.length_squared() < 0.01:
		reference = Vector3.FORWARD
	reference = reference.normalized()
	var arc := deg_to_rad(float(brain.param("flank_arc", 200.0)))
	var slot := _pack_slot()
	var offset := (float(slot) / float(count - 1) - 0.5) * arc
	var bearing := reference.rotated(Vector3.UP, offset)
	var ring := maxf(float(brain.param("spread", 2.6)), brain.engage_range())
	return target.global_position + bearing * ring


func _pack_mates() -> Array[Node]:
	var out: Array[Node] = []
	for n in get_tree().get_nodes_in_group("enemy"):
		if n == self or not (n is Enemy):
			continue
		var e := n as Enemy
		if e.dead or e.enemy_id != enemy_id:
			continue
		if global_position.distance_to(e.global_position) <= PACK_CALL_RADIUS:
			out.append(e)
	return out


func _pack_size() -> int:
	return _pack_mates().size() + 1


func _pack_slot() -> int:
	var mates := _pack_mates()
	var ids: Array[int] = [get_instance_id()]
	for m in mates:
		ids.append(m.get_instance_id())
	ids.sort()
	return ids.find(get_instance_id())


func _strafe_or_retreat(delta: float, dist: float, retreating: bool) -> void:
	var circle := float(brain.param("circle", 0.4))
	var strafe_speed := float(brain.param("strafe_speed", 0.8))
	if retreating:
		_step(-_to_target_flat(), speed * 0.9, delta)
		return
	if circle <= 0.01:
		_damp(delta, 10.0)
		return
	var side := _to_target_flat().cross(Vector3.UP) * _strafe_sign
	var drift := Vector3.ZERO
	if dist > brain.engage_range() + 1.0:
		drift = _to_target_flat() * 0.5
	elif dist < brain.engage_range() - 0.8:
		drift = -_to_target_flat() * 0.5
	_step((side * circle + drift).normalized(), speed * strafe_speed, delta)


func _to_target_flat() -> Vector3:
	if target == null:
		return forward()
	var to := target.global_position - global_position
	to.y = 0.0
	return to.normalized() if to.length_squared() > 0.0001 else forward()


# --- charging (charger archetype) -----------------------------------------------------------------

func _start_charge(attack: Dictionary) -> void:
	_charging = true
	_charge_time = 0.0
	_charge_dir = _to_target_flat()
	_current_attack = attack
	poise_comp.set_hyper_armour(float(brain.param("hyper_armour", 10.0)))


func _tick_charge(delta: float) -> void:
	_charge_time += delta
	var v := _charge_dir * speed * CHARGE_SPEED_MULT
	velocity.x = v.x
	velocity.z = v.z
	snap_facing(_charge_dir)
	var hit_any := false
	if target != null:
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() <= brain.engage_range() + 0.4:
			hit_any = true
	if hit_any or _charge_time > CHARGE_MAX_TIME or is_on_wall():
		_end_charge(hit_any)


func _end_charge(connected: bool) -> void:
	_charging = false
	poise_comp.clear_hyper_armour()
	if connected:
		# The charge landed: swing the attack itself (never re-enter the wind-up).
		_begin_melee(_current_attack)
	else:
		_global_cooldown = 1.2
		anim.play_intent("Hit_Light")
		_damp(0.016, 30.0)


# --- attacks ------------------------------------------------------------------------------------

## Picks an off-cooldown attack whose range brackets the target. Ranged/charge attacks declare
## `min_range`; melee ones just use `range`.
func _select_attack(dist: float) -> Dictionary:
	var options: Array = []
	for a in current_attacks:
		var attack: Dictionary = a
		var name := str(attack.get("name", "attack"))
		if float(_attack_cooldowns.get(name, 0.0)) > 0.0:
			continue
		var reach := float(attack.get("range", 2.0))
		var min_range := float(attack.get("min_range", 0.0))
		if dist <= reach and dist >= min_range:
			options.append(attack)
	if options.is_empty():
		return {}
	if randf() > float(brain.param("aggression", 0.7)):
		return {}
	var total := 0.0
	for a in options:
		total += float(a.get("weight", 1.0))
	var roll := randf() * total
	for a in options:
		roll -= float(a.get("weight", 1.0))
		if roll <= 0.0:
			return a
	return options[0]


## Dispatches by attack kind: a charge winds up then runs; a spell goes through the caster;
## everything else is a melee swing.
func _begin_attack(attack: Dictionary) -> void:
	match str(attack.get("kind", "")):
		"charge":
			_current_attack = attack
			_attacking = true
			_attack_phase = "telegraph"
			telegraph.emit(str(attack.get("name", "attack")), CHARGE_WINDUP)
			anim.play_intent(str(attack.get("clip", "Attack_1")), {"length": CHARGE_WINDUP, "events": [{"t": CHARGE_WINDUP * 0.95, "name": "charge_go"}]})
		"spell":
			_begin_spell_attack(attack)
		_:
			_begin_melee(attack)


func _begin_melee(attack: Dictionary) -> void:
	var name := str(attack.get("name", "attack"))
	_current_attack = attack
	_attacking = true
	_attack_phase = "telegraph"
	var timing := attack_timing(attack)
	if bool(attack.get("hyper_armour", false)) or (archetype == "brute" and bool(attack.get("heavy", false))):
		poise_comp.set_hyper_armour(float(brain.param("hyper_armour", 10.0)))
	telegraph.emit(name, float(attack.get("telegraph", 0.6)))
	anim.play_intent(str(attack.get("clip", "Attack_1")), timing)


## Telegraph → hit window → recovery, as placeholder clip timing (CONTRACTS §3 event names).
static func attack_timing(attack: Dictionary) -> Dictionary:
	var tel := maxf(float(attack.get("telegraph", 0.6)), 0.05)
	var window := maxf(float(attack.get("hit_window", 0.18)), 0.05)
	var rec := maxf(float(attack.get("recovery", 0.6)), 0.05)
	var length := tel + window + rec
	return {"length": length, "events": [
		{"t": tel, "name": "hit_start"},
		{"t": tel + window, "name": "hit_end"},
		{"t": tel + window + rec * 0.6, "name": "cancel_ok"},
	]}


func _begin_spell_attack(attack: Dictionary) -> void:
	var spell_id := str(attack.get("spell", ""))
	if spell_id.is_empty() or not caster.cast(spell_id, target):
		_global_cooldown = 1.0
		return
	_current_attack = attack
	_attacking = true
	_attack_phase = "telegraph"
	var def := ContentDB.get_or_empty(spell_id)
	var ct := SpellRuntime.cast_time_of(def)
	telegraph.emit(str(attack.get("name", "cast")), ct)
	anim.play_intent(SpellRuntime.clip_for(def), {"length": ct})
	_attack_cooldowns[str(attack.get("name", "cast"))] = float(attack.get("cooldown", 3.0))
	_global_cooldown = ct + 0.4


func _tick_attack(delta: float) -> void:
	if target != null and _attack_phase == "telegraph" and not _charging:
		face_toward(target.global_position, TURN_SPEED * 0.6, delta)
	if _attack_phase == "active":
		var lunge := float(_current_attack.get("lunge", 0.0))
		if lunge > 0.0:
			var v := forward() * lunge
			velocity.x = v.x
			velocity.z = v.z
		else:
			_damp(delta, 16.0)
	else:
		_damp(delta, 14.0)


func _on_clip_event(event_name: String) -> void:
	match event_name:
		"charge_go":
			_attacking = false
			_start_charge(_current_attack)
		"hit_start":
			if _attacking:
				_attack_phase = "active"
				_open_hitbox()
		"hit_end":
			if _attacking:
				_attack_phase = "recovery"
				_close_hitbox()
		_:
			pass


func _on_clip_finished(_clip: String) -> void:
	if _attacking:
		_finish_attack()


func _finish_attack() -> void:
	_close_hitbox()
	poise_comp.clear_hyper_armour()
	var name := str(_current_attack.get("name", "attack"))
	_attack_cooldowns[name] = float(_current_attack.get("cooldown", 2.0))
	_global_cooldown = float(_current_attack.get("gcd", 0.5))
	if archetype == "skirmisher":
		_retreat_timer = float(brain.param("retreat_time", 1.4))
	_attacking = false
	_attack_phase = ""
	_current_attack = {}


func on_action_interrupted() -> void:
	if _attacking or _charging:
		_close_hitbox()
		poise_comp.clear_hyper_armour()
		_attacking = false
		_charging = false
		_attack_phase = ""
		_current_attack = {}
	caster.interrupt()


## Enemies swing with a hitbox in front of them sized by the attack's range.
func _open_hitbox() -> void:
	var a := _current_attack
	var hit := HitData.new()
	hit.amount = float(a.get("damage", 10.0))
	hit.kind = str(a.get("kind_damage", DamageModel.kind_for_class(str(a.get("weapon_class", "claw")))))
	hit.poise_damage = float(a.get("poise_damage", 10.0))
	hit.heavy = bool(a.get("heavy", false))
	hit.attacker = self
	hit.knockdown = bool(a.get("knockdown", false))
	hit.knockback = float(a.get("knockback", 0.0))
	hit.parryable = not bool(a.get("unparryable", false))
	hit.label = "%s:%s" % [Ids.name_of(enemy_id), str(a.get("name", "attack"))]
	hit.statuses = a.get("statuses", [])
	_weapon_hitbox().begin_swing(hit)
	if a.has("summons"):
		_summon(a["summons"])
	attack_launched.emit(str(a.get("name", "attack")))
	_make_noise(0.5)


## Calls up help in a ring, at the moment the attack lands: {enemy, count, radius, cap}.
## The ring is walked outward from the summoner so nobody arrives inside them, and the spawner
## that placed this enemy is reused so the adds reset and save like any other encounter.
func _summon(spec_v: Variant) -> void:
	if typeof(spec_v) != TYPE_DICTIONARY:
		return
	var spec: Dictionary = spec_v
	var add_id := str(spec.get("enemy", ""))
	if add_id.is_empty():
		return
	var spawner := EnemySpawner.for_node(self)
	if spawner == null:
		Log.warn("Enemy", "%s has nowhere to put its summons" % enemy_id)
		return
	var still: Array[Enemy] = []
	for e in summons_alive:
		if is_instance_valid(e) and not e.dead:
			still.append(e)
	summons_alive = still
	var cap := int(spec.get("cap", SUMMON_DEFAULT_CAP))
	var want := mini(int(spec.get("count", 1)), maxi(cap - summons_alive.size(), 0))
	if want <= 0:
		return
	var radius := float(spec.get("radius", SUMMON_RADIUS))
	var made: Array = []
	for i in want:
		var a := TAU * (float(i) + randf() * 0.35) / float(want) + rotation.y
		var at := global_position + Vector3(cos(a), 0.0, sin(a)) * radius
		var add := spawner.spawn_one(add_id, at, a + PI, {"group": "summons:" + enemy_id})
		if add == null:
			continue
		add.rotation.y = a + PI
		if target != null:
			add.perception.alert_to(target.global_position, target)
		summons_alive.append(add)
		made.append(add)
	if not made.is_empty():
		summoned.emit(made)


func _close_hitbox() -> void:
	_weapon_hitbox().end_swing()


func _weapon_hitbox() -> Hitbox:
	var hb := attack_origin.get_node_or_null("Hitbox") as Hitbox
	if hb == null:
		hb = Hitbox.create(self, 0.45, 2.0)
		attack_origin.add_child(hb)
	# `hit_range` lets an attack whose selection range is long (a charge) keep a short hitbox.
	var reach := float(_current_attack.get("hit_range", _current_attack.get("range", brain.engage_range()))) + 0.4
	hb.set_capsule(0.45 * body_scale, reach)
	return hb


# --- movement -----------------------------------------------------------------------------------

## Steers toward a world point; returns the remaining distance. Uses NavigationAgent3D when the
## scene provides a NavigationRegion3D, otherwise direct steering with a small obstacle slide.
func _move_towards(point: Vector3, move_speed: float, delta: float) -> float:
	var to := point - global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= ARRIVE:
		_damp(delta, 12.0)
		return dist
	var dir := to.normalized()
	if agent != null:
		if _repath <= 0.0:
			agent.target_position = point
			_repath = REPATH
		if not agent.is_navigation_finished():
			var next := agent.get_next_path_position() - global_position
			next.y = 0.0
			if next.length_squared() > 0.0001:
				dir = next.normalized()
	_step(dir, move_speed, delta)
	face_toward(global_position + dir, TURN_SPEED, delta)
	return dist


func _step(dir: Vector3, move_speed: float, delta: float) -> void:
	var s := move_speed * speed_multiplier()
	var target_v := dir * s
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_v, ACCEL * delta * maxf(s, 1.0))
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _damp(delta: float, rate: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _update_anim() -> void:
	var local := global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	anim.set_locomotion(Vector2(local.x, -local.z) / maxf(speed, 0.1), false)


# --- reactions ----------------------------------------------------------------------------------

func take_hit(hit: HitData) -> String:
	var outcome := super.take_hit(hit)
	if outcome != "dead" and hit.attacker is Node3D:
		perception.alert_to((hit.attacker as Node3D).global_position, hit.attacker as Node3D)
		inactive = false
		brain.force(Brain.COMBAT)
		_call_pack((hit.attacker as Node3D).global_position)
	return outcome


func _call_pack(position: Vector3) -> void:
	if not bool(brain.param("flank", false)) and archetype != "pack" and archetype != "swarm":
		return
	for m in _pack_mates():
		var e := m as Enemy
		if e.perception.detection < 1.0:
			e.perception.alert_to(position, target)


func _on_detected(_t: Node3D) -> void:
	inactive = false
	_call_pack(perception.last_known)
	if is_boss and not boss_started:
		start_boss()


func _on_suspicion(position: Vector3) -> void:
	_remember(position)


func _remember(position: Vector3) -> void:
	brain.search_point = position
	brain.has_search_point = true


func noise_heard(position: Vector3, loudness: float) -> void:
	if not dead and perception != null:
		perception.noise_heard(position, loudness)


func _make_noise(loudness: float) -> void:
	for n in get_tree().get_nodes_in_group("perceivers"):
		if n != self and n.has_method("noise_heard"):
			n.noise_heard(global_position, loudness)


func _on_brain_state(from: String, to: String) -> void:
	state_changed.emit(from, to)
	match to:
		Brain.SEARCH:
			brain.has_search_point = false
			anim.play_intent("Idle")
		Brain.COMBAT:
			anim.play_intent("Idle_Combat")
		_:
			pass


func _on_hearthstone_rested(_id: String) -> void:
	reset_to_spawn()


## Non-boss enemies reset when the player rests (DESIGN §5.4/§5.5).
func reset_to_spawn() -> void:
	if is_boss and boss_started:
		return
	global_position = spawn_position
	rotation.y = spawn_yaw
	velocity = Vector3.ZERO
	perception.reset()
	brain.force(Brain.PATROL if patrol_points.size() > 1 else Brain.IDLE)
	inactive = archetype == "ambusher"
	_attacking = false
	_charging = false
	_attack_cooldowns.clear()
	if dead:
		revive()
		collision_layer = LAYER_ENEMY
	else:
		full_restore()
	anim.play_intent("Idle")


# --- boss ---------------------------------------------------------------------------------------

func start_boss() -> void:
	if boss_started:
		return
	boss_started = true
	EventBus.boss_started.emit(enemy_id)


func _check_phase() -> void:
	if phases.is_empty():
		return
	var ratio := health / maxf(max_health, 1.0)
	var want := phase_index
	for i in phases.size():
		var threshold := float(phases[i].get("hp", 1.0))
		if ratio <= threshold:
			want = i
	if want != phase_index and want >= 0:
		_enter_phase(want)


func _enter_phase(index: int) -> void:
	phase_index = index
	var phase: Dictionary = phases[index]
	current_attacks = phase.get("attacks", attacks)
	for key in ["engage_range", "circle", "aggression", "hyper_armour", "retreat_threshold"]:
		if phase.has(key):
			brain.params[key] = phase[key]
	if phase.has("speed"):
		speed = float(phase["speed"])
	_attack_cooldowns.clear()
	phase_changed.emit(index, phase)
	if phase.has("say"):
		EventBus.notify.emit(str(phase["say"]), "boss")


## Turns this one into something the player called: it fights for them, hostiles hunt it, and
## after `seconds` it lets go. Called before the body enters the tree where possible.
func become_ally(seconds: float = 0.0) -> void:
	faction = "player"
	life_left = maxf(seconds, 0.0)
	add_to_group(Perception.ALLY_GROUP)
	marks_range = [0, 0]
	if perception != null:
		perception.target = null


## The end of a called thing's time: no death, no marks, no loot — it simply stops being here.
func dismiss() -> void:
	if dead:
		return
	dead = true
	life_left = 0.0
	if perception != null:
		perception.enabled = false
	EventBus.summon_dismissed.emit(enemy_id, self)
	queue_free()


func _on_died(killer: Node) -> void:
	if is_boss and boss_started:
		EventBus.boss_defeated.emit(enemy_id)
	mark_dropped.emit(enemy_id, global_position)
	if killer != null and killer.is_in_group("player"):
		GameState.inc("kills")
	perception.enabled = false
	set_deferred("visible", true)


# --- save ---------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	var d := super.to_save()
	d["enemy_id"] = enemy_id
	d["brain"] = brain.to_save()
	d["spawn"] = [spawn_position.x, spawn_position.y, spawn_position.z]
	d["spawn_yaw"] = spawn_yaw
	d["phase"] = phase_index
	d["inactive"] = inactive
	return d


func from_save(d: Dictionary) -> void:
	super.from_save(d)
	brain.from_save(d.get("brain", {}))
	var s: Array = d.get("spawn", [spawn_position.x, spawn_position.y, spawn_position.z])
	spawn_position = Vector3(float(s[0]), float(s[1]), float(s[2]))
	spawn_yaw = float(d.get("spawn_yaw", spawn_yaw))
	inactive = bool(d.get("inactive", inactive))
	var p := int(d.get("phase", -1))
	if p >= 0 and p < phases.size():
		_enter_phase(p)
