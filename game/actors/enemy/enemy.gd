class_name Enemy
extends Actor
## A hostile actor driven by its enemy def (CONTRACTS §7) and a Brain (DESIGN §5.4).
## Steering is direct with ground snapping, using a NavigationAgent3D only when the scene has a
## NavigationRegion3D. Attacks are chosen by range and cooldown and always telegraph before the
## hit window. Archetype flavour: pack spread/flank, charger line charge with knockdown, caster
## keeps distance, ambusher waits inactive, sentinel never leaves its post, brute hyper-armour,
## skirmisher hits and retreats. Bosses swap attack sets at hp thresholds.
## The bestiary's special behaviours — voice attacks a silence stops, radial bursts, loosed
## projectiles, pounces, cut purses, drained stamina, lures, guarded shrines, duellists' guards
## and limbs that break off — decide themselves in EnemyAbilities and act here. So do the boss
## fights (WORLD_BIBLE §9): held notes that heal until they are cut short, shockwaves that
## follow a landed blow out across the floor, two-beat combos, and an arena that closes in.

signal state_changed(from: String, to: String)
signal telegraph(attack_name: String, duration: float)
signal attack_launched(attack_name: String)
signal phase_changed(index: int, phase: Dictionary)
signal limb_broken(index: int, limb: Dictionary)
signal mark_dropped(enemy_id: String, position: Vector3)
signal summoned(enemies: Array)
signal channel_started(attack_name: String, seconds: float)
signal channel_pulse(attack_name: String, healed: float)
signal channel_ended(attack_name: String, reason: String)

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
## The fastest a circling enemy sweeps round its target, radians per second (about 80 degrees).
const MAX_CIRCLE_RATE := 1.4
## Where summoned help stands up, and how many of them a summoner may have out at once.
const SUMMON_RADIUS := 4.5
const SUMMON_DEFAULT_CAP := 6
const GROUND_MASK := (1 << 0) | (1 << 10)
const MASK_HURTBOX := 1 << 5
const BURST_MAX_TARGETS := 24
const FLEE_TIME := 7.0
const PROJECTILE_SPEED := 30.0

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
## Sitting at its post and minding its own business (a POI group that `sits`: the Mossbridge
## Wardens, the Long Stride's toll-keeper): it sees whoever comes and starts nothing. A blow, the
## greed rule or its group's `wake` ends it; seeing somebody does not.
var minding: bool = false
## Goes back to minding its post when it is reset after a rest, however the last visit ended.
var sits: bool = false
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
var _flee_timer: float = 0.0
var _lure_engaged: bool = false
var _lure_closed: float = 0.0
var _limbs: Array = []
var _limbs_broken: int = 0
var _damage_since_limb: float = 0.0
var _roused_by_greed: bool = false
## This foe's tags, for the ground a ward keeps it off (Wards): the Singing Yew's, to a wight.
var _ward_tags: Array = []
var _watched_target: Node = null
var _channel_left: float = 0.0
var _channel_next_pulse: float = 0.0
var _channel_damage: float = 0.0
var _last_attack_name: String = ""
var _last_attack_at: float = -999.0
var _arena: BossArena = null
## Where this dressed foe wears plate (EnemyDress.armour_of), and the heights, as shares of its
## height, where its chest and its head begin.
var _armoured: Dictionary = {}
const TORSO_FROM := 0.5
const HEAD_FROM := 0.84


# --- construction -------------------------------------------------------------------------------

func _ready() -> void:
	if faction == "neutral":
		faction = "hostile"
	collision_layer = LAYER_ENEMY
	if not enemy_id.is_empty():
		_read_def(ContentDB.get_or_empty(enemy_id))
	super()
	# the rig on its own is the forge's mannequin: a foe wears what its def and its tags say, and
	# holds what its def names (`held`); a foe whose def names nothing holds the weapon of its
	# attacks' class
	if body_kind == "humanoid" and anim != null and anim.model != null:
		EnemyDress.dress(anim.model, def)
	if typeof(def.get("held", null)) != TYPE_DICTIONARY:
		_dress_hands()
	if anim != null:
		# a foe's telegraph is held at the cocked weapon, not played in slow motion (AnimationDriver)
		anim.hold_windup = true
	if body_kind == "humanoid":
		_armoured = EnemyDress.armour_of(def)
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
	perception.noise.connect(_on_noise_heard)
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
	if not EnemyAbilities.guard_params(brain.params).is_empty():
		EventBus.container_opened.connect(_on_container_opened)
		EventBus.item_acquired.connect(_on_item_acquired)
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
	will = int(stats.get("will", will))
	resists = def.get("resists", {})
	attacks = def.get("attacks", [])
	current_attacks = attacks
	marks_range = def.get("marks", [0, 0])
	_limbs = def.get("limbs", [])
	_limbs_broken = 0
	_damage_since_limb = 0.0
	phases = def.get("phases", [])
	is_boss = archetype == "boss" or not phases.is_empty()
	var rig := str(def.get("rig", "humanoid"))
	body_kind = "humanoid" if rig == "humanoid" else str(def.get("body", "quadruped"))
	body_variant = str(def.get("body_variant", ""))
	body_scale = float(def.get("scale", 1.0))
	if def.has("tint"):
		tint = Color(str(def["tint"]))
	body_material = Foley.material_for(def, armour_flat)
	capsule_radius = float(def.get("radius", 0.35 if body_kind == "humanoid" else 0.45))
	capsule_height = float(def.get("height", 1.8 if body_kind == "humanoid" else 1.0))
	if def.has("faction"):
		faction = str(def["faction"])
	_ward_tags = def.get("tags", [])


func content_id() -> String:
	return enemy_id


## What a blow at `point` strikes on this foe (Impact): plate where a dressed foe wears it (its
## chest, under a helm its head), and elsewhere what its body is. A dressed humanoid's material
## follows what it wears, not its armour value: a robed caster with armour 12 is cloth and flesh,
## and a raider in plate with armour 10 is plate.
func material_at(point: Vector3) -> String:
	if body_kind != "humanoid" or _armoured.is_empty():
		return body_material
	var h := (point.y - global_position.y) / maxf(capsule_height, 0.1)
	if bool(_armoured.get("head", false)) and h >= HEAD_FROM:
		return "metal"
	if bool(_armoured.get("torso", false)) and h >= TORSO_FROM and h < HEAD_FROM:
		return "metal"
	var own := str(def.get("material", ""))
	if own in ["flesh", "metal", "stone", "wood"]:
		return own
	var tags: Array = def.get("tags", [])
	if tags.has("construct") or tags.has("stone"):
		return "stone"
	if tags.has("treant") or tags.has("plant"):
		return "wood"
	return "flesh"


## Whether a blow on this foe's flesh draws blood: not the dead, whose rags give dust.
func bleeds() -> bool:
	var tags: Array = def.get("tags", [])
	return not (tags.has("undead") or tags.has("construct") or tags.has("stone"))


## A humanoid foe holds the weapon its attacks are made with: the first of them whose
## `weapon_class` the forge makes a model of (HeldItems). A claw, a bite or a fist holds nothing.
func _dress_hands() -> void:
	if anim == null or anim.model == null or not anim.model.has_method("attach_to_socket"):
		return
	# `holds` names what is seen in the hand when the attacks do not (an item id, or
	# "class:<weapon class>"); it changes nothing a blow does
	var holds := str(def.get("holds", ""))
	if not holds.is_empty():
		var held := HeldItems.for_class(holds.trim_prefix("class:")) if holds.begins_with("class:") else ContentDB.get_or_empty(holds)
		if not held.is_empty():
			HeldItems.dress(anim.model, held)
			return
	var item := held_for(attacks)
	if not item.is_empty():
		HeldItems.dress(anim.model, item)


## What a foe whose def names nothing holds: the weapon of its first attack swung with an attack
## clip, else of its first attack of any kind whose class the forge makes ({} for none). A caster
## that sings with a staff and swings a censer holds the censer: the chorister held its staff
## through its censer swing, and the staff's butt went 7.5 cm into its chest.
static func held_for(attack_defs: Array) -> Dictionary:
	for melee_only in [true, false]:
		for a in attack_defs:
			var ad: Dictionary = a
			if melee_only and not str(ad.get("clip", "")).begins_with("Attack_"):
				continue
			var item := HeldItems.for_class(str(ad.get("weapon_class", "")))
			if not item.is_empty():
				return item
	return {}


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
		snap_to_terrain()
		return
	_tick_timers(delta)
	_check_phase()
	target = perception.target if perception.target != null and is_instance_valid(perception.target) else null
	_watch_for_swings()
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
	snap_to_terrain()
	step_sounds(delta, -3.0 if body_kind == "humanoid" else -5.0)
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
	_flee_timer = maxf(_flee_timer - delta, 0.0)
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
		"warded": target != null and not _ward_tags.is_empty() and not Wards.keeping(_ward_tags, target.global_position).is_empty(),
		"time_unseen": perception.time_since_seen,
	}


func state_name() -> String:
	return brain.state


## Has not noticed anybody: not fighting, and its eyes have not filled the meter. A blow from
## somebody it has not noticed is a sneak attack (DESIGN §5.3).
func is_unaware() -> bool:
	if dead or brain == null:
		return false
	return brain.state != Brain.COMBAT and (perception == null or perception.detection < 1.0)


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
		_guard(false)
		return
	if inactive:
		inactive = false
		anim.play_intent("Get_Up", {"length": AMBUSH_ROUSE})
		stunned_until = maxf(stunned_until, now() + AMBUSH_ROUSE)
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	# A cutpurse with your marks is not interested in a fight; it runs, and it does not look back.
	if _flee_timer > 0.0:
		_guard(false)
		var away := -_to_target_flat()
		face_toward(global_position + away, TURN_SPEED, delta)
		_step(away, speed * 1.2, delta)
		return
	face_toward(target.global_position, TURN_SPEED, delta)
	if _charging:
		_tick_charge(delta)
		return
	if _retreat_timer > 0.0:
		_guard(false)
		_strafe_or_retreat(delta, dist, true)
		return
	var attack := _select_attack(dist)
	if not attack.is_empty() and _global_cooldown <= 0.0 and can_act():
		_guard(false)
		_begin_attack(attack)
		return
	_guard(true)
	if _tick_lure(delta, dist):
		return
	_approach_or_hold(delta, dist)


## A duelist keeps its guard up between its own swings (and only then): the openings it gives
## you are the attacks it commits to, which is how a rapier fight is supposed to read.
func _guard(up: bool) -> void:
	if not EnemyAbilities.parries(brain.params):
		return
	var p := EnemyAbilities.parry_params(brain.params)
	var want := up and not dead and can_act() and target != null
	if want != is_blocking:
		is_blocking = want
		anim.play_intent("Block_Idle" if want else "Idle_Combat")
		stamina_comp.regen_multiplier = 0.5 if want else 1.0
	block_stability = float(p["guard_stability"]) if want else 0.0
	can_parry = want


## The lure: a wisp keeps its distance and goes on keeping it, which is the point of a wisp.
## Returns true when it has handled this frame's movement. Once it turns and fights, it fights.
func _tick_lure(delta: float, dist: float) -> bool:
	if _lure_engaged or not EnemyAbilities.lures(brain.params):
		return false
	var p := EnemyAbilities.lure_params(brain.params)
	if dist <= float(p["lure_break"]):
		_lure_closed += delta
	else:
		_lure_closed = 0.0
	match EnemyAbilities.lure_decision(dist, brain.params, _lure_closed):
		EnemyAbilities.ENGAGE:
			_lure_engaged = true
			return false
		EnemyAbilities.WITHDRAW:
			_step(-_to_target_flat(), speed * float(p["lure_speed"]), delta)
			return true
		_:
			_strafe_or_retreat(delta, dist, false)
			return true


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
	if bool(brain.param("flank", false)) and not _pack_mates().is_empty():
		# A pack member keeps to its own slot round the target (_approach_goal): it waits on the
		# ring and comes in along its own bearing when it has a blow ready, so a pack bites from
		# several sides by turns rather than circling in a knot at arm's length.
		var slot := _approach_goal() - global_position
		slot.y = 0.0
		if slot.length() > ARRIVE:
			_move_towards(global_position + slot, speed, delta)
		else:
			_damp(delta, 12.0)
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
	var slot := _pack_slot(reference, mates)
	var offset := (float(slot) / float(count - 1) - 0.5) * arc
	var bearing := reference.rotated(Vector3.UP, offset)
	# The ring is where a pack member waits for its turn; with a blow ready it closes in along its
	# own bearing, so it still comes from the flank. The ring alone is wider than a wolf's bite
	# (3.2 m against 1.9), and a pack held on it never bit anybody who did not walk into it.
	var ring := maxf(float(brain.param("spread", 2.6)), brain.engage_range())
	if _attack_ready():
		ring = maxf(brain.engage_range() - 0.3, 0.5)
	return target.global_position + bearing * ring


## Whether a blow could be thrown now, range aside: nothing cooling down that stops every attack.
func _attack_ready() -> bool:
	if _global_cooldown > 0.0 or not can_act():
		return false
	var silenced := status != null and status.has("silenced")
	var since := now() - _last_attack_at
	for a in current_attacks:
		var attack: Dictionary = a
		if not EnemyAbilities.is_usable(attack, silenced):
			continue
		if not EnemyAbilities.combo_ready(attack, _last_attack_name, since):
			continue
		if float(_attack_cooldowns.get(str(attack.get("name", "attack")), 0.0)) <= 0.0:
			return true
	return false


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


## This member's place in the fan: the pack in the order it stands round the target, so each keeps
## the side it already holds and nobody crosses in front of the target to reach its slot. (Slots
## used to go by instance id, which sent a wolf standing on the left to the far right.)
func _pack_slot(reference: Vector3, mates: Array[Node]) -> int:
	var mine := _bearing_round_target(reference, global_position)
	var slot := 0
	for m in mates:
		var theirs := _bearing_round_target(reference, (m as Node3D).global_position)
		if theirs < mine or (is_equal_approx(theirs, mine) and m.get_instance_id() < get_instance_id()):
			slot += 1
	return slot


func _bearing_round_target(reference: Vector3, point: Vector3) -> float:
	var to := point - target.global_position
	to.y = 0.0
	return reference.signed_angle_to(to, Vector3.UP) if to.length_squared() > 0.0001 else 0.0


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
	# Circling is held to a sweep a person can follow, not only to what the legs can do: a wolf at
	# arm's length going at its full strafe speed (5.5 m/s) went round the player about once a
	# second, faster than a camera turns or a sword is aimed.
	var circle_speed := minf(speed * strafe_speed, MAX_CIRCLE_RATE * maxf(dist, 1.0))
	_step((side * circle + drift).normalized(), circle_speed, delta)


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
	# A leap is a charge that leaves the ground: gravity brings it down on whatever it aimed at.
	if EnemyAbilities.is_leap(attack):
		velocity.y = EnemyAbilities.leap_lift(attack)
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
## `min_range`; melee ones just use `range`. An attack made with the voice is off the table while
## this creature is silenced, which is how a Hush answers a chorister.
func _select_attack(dist: float) -> Dictionary:
	var options: Array = []
	var silenced := status != null and status.has("silenced")
	var since := now() - _last_attack_at
	for a in current_attacks:
		var attack: Dictionary = a
		if not EnemyAbilities.is_usable(attack, silenced):
			continue
		# The second beat of a pair only exists after the first one.
		if not EnemyAbilities.combo_ready(attack, _last_attack_name, since):
			continue
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
		"charge", "leap":
			_current_attack = attack
			_attacking = true
			_attack_phase = "telegraph"
			telegraph.emit(str(attack.get("name", "attack")), CHARGE_WINDUP)
			anim.play_intent(str(attack.get("clip", "Attack_1")), {"length": CHARGE_WINDUP, "events": [{"t": CHARGE_WINDUP * 0.95, "name": "charge_go"}]})
		"spell":
			_begin_spell_attack(attack)
		_:
			# burst and projectile share the melee shape: telegraph, act on hit_start, recover.
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
## A channelled attack holds the note between the wind-up and the recovery: `channel_start` opens
## it, the pulses run off a timer, and `channel_end` closes it if nothing has cut it short.
static func attack_timing(attack: Dictionary) -> Dictionary:
	var tel := maxf(float(attack.get("telegraph", 0.6)), 0.05)
	var window := maxf(float(attack.get("hit_window", 0.18)), 0.05)
	var rec := maxf(float(attack.get("recovery", 0.6)), 0.05)
	var held := EnemyAbilities.channel_seconds(attack)
	if held > 0.0:
		return {"length": tel + held + rec, "events": [
			{"t": tel, "name": "channel_start"},
			{"t": tel + held, "name": "channel_end"},
			{"t": tel + held + rec * 0.6, "name": "cancel_ok"},
		]}
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


# --- channelled attacks ---------------------------------------------------------------------------

## The held note begins. From here it pulses on a beat until it runs out, or until something
## stops it: a silence in a throat that needs one, or enough damage to break the concentration.
func _start_channel(a: Dictionary) -> void:
	_attack_phase = "channel"
	_channel_left = EnemyAbilities.channel_seconds(a)
	_channel_next_pulse = 0.0
	_channel_damage = 0.0
	channel_started.emit(str(a.get("name", "attack")), _channel_left)


func _tick_channel(delta: float) -> void:
	_damp(delta, 14.0)
	if target != null and is_instance_valid(target):
		face_toward(target.global_position, TURN_SPEED * 0.4, delta)
	var a := _current_attack
	var reason := EnemyAbilities.channel_break_reason(a, status != null and status.has("silenced"), _channel_damage, max_health)
	if not reason.is_empty():
		_end_channel(reason)
		return
	_channel_next_pulse -= delta
	_channel_left -= delta
	# The note runs out before it can take another beat: `channel` seconds is exactly
	# `channel_pulses` pulses, so the healing it is worth is the healing it can give.
	if _channel_left <= 0.0:
		_end_channel("finished")
		return
	if _channel_next_pulse <= 0.0:
		_channel_next_pulse = EnemyAbilities.channel_tick(a)
		_channel_pulse(a)


## One beat of the note: it takes back a share of what the whole note is worth, and everything
## inside its reach hears it. Cut the note short and the rest of the healing never happens.
func _channel_pulse(a: Dictionary) -> void:
	var healed := EnemyAbilities.channel_heal_per_pulse(a)
	if healed > 0.0 and health < max_health:
		heal(healed)
	if float(a.get("damage", 0.0)) > 0.0:
		var pulse := a.duplicate(true)
		pulse["kind"] = "burst"
		pulse["radius"] = EnemyAbilities.radial_radius(a, arena_radius())
		pulse["unparryable"] = true
		_burst(pulse)
	channel_pulse.emit(str(a.get("name", "attack")), healed)


func _end_channel(reason: String) -> void:
	if _attack_phase != "channel":
		return
	var name := str(_current_attack.get("name", "attack"))
	var open_for := float(_current_attack.get("interrupt_stagger", 1.1))
	_attack_phase = "recovery"
	_channel_left = 0.0
	channel_ended.emit(name, reason)
	if reason == "finished":
		return
	# A note that was cut off leaves its singer open, which is the whole reward for cutting it.
	anim.stop()
	_finish_attack()
	stagger(open_for)
	EventBus.notify.emit("%s's note breaks off." % display_name, "combat")


func is_channelling() -> bool:
	return _attack_phase == "channel"


func channel_remaining() -> float:
	return maxf(_channel_left, 0.0)


# --- the arena ------------------------------------------------------------------------------------

## The bound this fight is being held inside, made on demand around where the boss was standing
## when it woke. A designer-placed BossArena for this id wins over an improvised one.
func arena() -> BossArena:
	if _arena != null and is_instance_valid(_arena):
		return _arena
	_arena = BossArena.for_boss(self)
	return _arena


## The floor this fight is being held on. An arena nobody has measured is the default circle,
## not a circle of nothing: `arena_wide` has to mean something before the Briar has taken a step.
func arena_radius() -> float:
	var a := arena()
	if a != null and a.is_bounded():
		return a.radius
	return EnemyAbilities.DEFAULT_ARENA_RADIUS


func _tick_attack(delta: float) -> void:
	if target != null and _attack_phase == "telegraph" and not _charging:
		face_toward(target.global_position, TURN_SPEED * 0.6, delta)
	if _attack_phase == "channel":
		_tick_channel(delta)
		return
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
				# What the blow itself sounds like, over its whoosh: a bell struck or rung, when the
				# attack says so (the Bell-bearer's "ringing stuns in a radius").
				var own := str(_current_attack.get("sound", ""))
				if not own.is_empty():
					Foley.play(own, attack_origin.global_position)
				if EnemyAbilities.is_burst(_current_attack):
					_burst(_current_attack)
				elif EnemyAbilities.is_projectile(_current_attack):
					_loose(_current_attack)
				else:
					_open_hitbox()
				# The floor answers a blow whether or not the blow found you.
				if EnemyAbilities.has_shockwave(_current_attack):
					_burst(EnemyAbilities.shockwave_attack(_current_attack, arena_radius()))
				var taken := EnemyAbilities.shrinks_arena_by(_current_attack)
				if taken > 0.0:
					var bound := arena()
					if bound != null:
						bound.shrink(taken)
		"hit_end":
			if _attacking:
				_attack_phase = "recovery"
				_close_hitbox()
		"channel_start":
			if _attacking:
				_start_channel(_current_attack)
		"channel_end":
			if _attacking and _attack_phase == "channel":
				_end_channel("finished")
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
	# What was just thrown, and when: a combo's second beat asks about both.
	if not _current_attack.is_empty():
		_last_attack_name = name
		_last_attack_at = now()
	_attacking = false
	_attack_phase = ""
	_channel_left = 0.0
	_current_attack = {}


func on_action_interrupted() -> void:
	is_blocking = false
	can_parry = false
	block_stability = 0.0
	stamina_comp.regen_multiplier = 1.0
	if _attack_phase == "channel":
		channel_ended.emit(str(_current_attack.get("name", "attack")), EnemyAbilities.BROKE_INTERRUPTED)
	if _attacking or _charging:
		_close_hitbox()
		poise_comp.clear_hyper_armour()
		_attacking = false
		_charging = false
		_attack_phase = ""
		_channel_left = 0.0
		_current_attack = {}
	caster.interrupt()


## One hit in flight from an attack definition. Shared by the swing, the burst and the arrow.
func build_hit(a: Dictionary) -> HitData:
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
	hit.weapon_class = str(a.get("weapon_class", "claw"))
	hit.weight = Impact.weight_of_class(hit.weapon_class)
	hit.statuses = a.get("statuses", [])
	hit.origin = global_position
	return hit


## Enemies swing with a hitbox in front of them sized by the attack's range.
func _open_hitbox() -> void:
	var a := _current_attack
	var whoosh := Foley.swing_for(str(a.get("weapon_class", "claw")), bool(a.get("heavy", false)))
	if not whoosh.is_empty():
		Foley.play(whoosh, attack_origin.global_position)
	_weapon_hitbox().begin_swing(build_hit(a))
	if bool(a.get("heavy", false)):
		Impact.trail(self, true)
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


## A shriek, a ring, a note: everything in a radius is hit at once and nothing in front of it
## is hit twice. Used by the scree-hag's silence and the bell-bearer's toll.
func _burst(a: Dictionary) -> void:
	var radius := EnemyAbilities.burst_radius(a)
	var hit := build_hit(a)
	var lit_share := EnemyAbilities.lit_damage_share(a)
	var bound := arena() if lit_share < 1.0 else null
	for victim in _actors_within(radius):
		if not is_hostile_to(victim) or not victim.has_method("take_hit"):
			continue
		var h := hit.copy()
		h.dodgeable = bool(a.get("dodgeable", true))
		h.origin = global_position
		# Only what you are known for stays lit, and standing in it is worth something.
		if bound != null and victim is Node3D and bound.lit_at((victim as Node3D).global_position):
			h.amount *= lit_share
			h.poise_damage *= lit_share
		var outcome: String = victim.take_hit(h)
		_after_hit_landed(a, victim, outcome)
	attack_launched.emit(str(a.get("name", "attack")))
	_make_noise(float(a.get("noise", 1.0)))


## A loosed arrow, a thrown stone, a sung note that crosses the room.
func _loose(a: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var p := Projectile.make_bolt(Color(str(a.get("projectile_colour", "#d8d2c0"))), float(a.get("projectile_radius", 0.09)))
	p.sticks = bool(a.get("sticks", false))
	p.max_range = float(a.get("range", 24.0)) + 12.0
	var tree := get_tree()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(p)
	var origin := global_position + Vector3.UP * (1.4 * body_scale)
	var aim: Vector3 = target.lock_point() if target.has_method("lock_point") else target.global_position + Vector3.UP
	var speed_ms := float(a.get("speed", PROJECTILE_SPEED))
	var gravity_ms := float(a.get("gravity", 0.0))
	var dir := (aim - origin)
	# Lead the shot and raise the nose enough that a heavy arrow still arrives where it was aimed.
	if gravity_ms > 0.0 and dir.length() > 0.5:
		dir.y += 0.5 * gravity_ms * pow(dir.length() / maxf(speed_ms, 1.0), 2.0)
	dir = dir.normalized()
	p.launch(origin + dir * 0.6, dir, speed_ms, build_hit(a), gravity_ms)
	if str(a.get("weapon_class", "")) == "bow" or p.sticks:
		p.impact_sound = "arrow_hit"
		Foley.play("bow_release", origin)
		Foley.play("arrow_whoosh", origin)
	p.struck.connect(_on_projectile_struck.bind(a))
	attack_launched.emit(str(a.get("name", "attack")))
	_make_noise(float(a.get("noise", 0.4)))


## Every actor with a hurtbox inside `radius` of this one.
func _actors_within(radius: float) -> Array[Node]:
	var out: Array[Node] = []
	if not is_inside_tree():
		return out
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 0.9)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = MASK_HURTBOX
	for r in space.intersect_shape(q, BURST_MAX_TARGETS):
		var c: Object = r.get("collider")
		if c is Hurtbox and (c as Hurtbox).actor != null and (c as Hurtbox).actor != self and not out.has((c as Hurtbox).actor):
			out.append((c as Hurtbox).actor)
	return out


# --- what a landed hit costs the victim -----------------------------------------------------------

func _on_swing_landed(hurtbox: Hurtbox, _hit: HitData, outcome: String) -> void:
	if hurtbox != null and hurtbox.actor != null:
		_after_hit_landed(_current_attack, hurtbox.actor, outcome)


func _on_projectile_struck(victim: Node, _hit: HitData, outcome: String, attack: Dictionary) -> void:
	_after_hit_landed(attack, victim, outcome)


## Consequences an attack carries beyond damage: a cut purse, a drained bar. Runs for swings,
## bursts and arrows alike, and only for hits that actually got through.
func _after_hit_landed(a: Dictionary, victim: Node, outcome: String) -> void:
	if a.is_empty() or victim == null or not is_instance_valid(victim):
		return
	if outcome == "dodged" or outcome == "parried" or outcome == "immune":
		return
	if EnemyAbilities.drain_amount(a) > 0.0:
		_drain(a, victim)
	if EnemyAbilities.steals(a):
		_cut_purse(a, victim)


## Stamina off the bar, and a mouthful back for whatever drank it.
func _drain(a: Dictionary, victim: Node) -> void:
	var pool: Node = victim.get("stamina_comp")
	if pool == null or not pool.has_method("spend"):
		return
	var want := EnemyAbilities.drain_amount(a)
	var took := minf(want, float(pool.get("current")))
	if took <= 0.0:
		return
	pool.spend(took)
	var back := EnemyAbilities.drain_heal(a, took)
	if back > 0.0:
		heal(back)


## The cutpurse's whole trade: take what is in the purse and be somewhere else. It only works
## on a bag that is the player's (CONTRACTS §8: only the player's Inventory joins that group).
func _cut_purse(a: Dictionary, victim: Node) -> void:
	if not victim.is_in_group("player"):
		return
	var bag: Node = null
	for n in get_tree().get_nodes_in_group("inventory"):
		bag = n
		break
	if bag == null or not bag.has_method("remove_marks"):
		return
	var purse := int(bag.get("marks"))
	var want := EnemyAbilities.steal_amount(a, purse, randf())
	var taken := 0
	if want > 0:
		taken = int(bag.remove_marks(want))
	if taken > 0:
		# What it took, it carries: kill it before it gets away and the purse comes back.
		marks_range = [int(marks_range[0]) + taken, int(marks_range[1]) + taken]
		EventBus.notify.emit("%s cuts your purse: %d marks." % [display_name, taken], "warn")
	# It runs whether or not there was anything in the purse; that is what makes it a cutpurse
	# and not a murderer. Killing it before it reaches the leash is how you get the marks back.
	if bool(brain.param("flee_after_steal", false)):
		_flee_timer = float(brain.param("flee_time", FLEE_TIME))
		_retreat_timer = 0.0
		on_action_interrupted()


func _close_hitbox() -> void:
	_weapon_hitbox().end_swing()
	Impact.trail(self, false)


func _weapon_hitbox() -> Hitbox:
	var hb := attack_origin.get_node_or_null("Hitbox") as Hitbox
	if hb == null:
		hb = Hitbox.create(self, 0.45, 2.0)
		attack_origin.add_child(hb)
		hb.hit_landed.connect(_on_swing_landed)
	# `hit_range` lets an attack whose selection range is long (a charge) keep a short hitbox.
	var reach := float(_current_attack.get("hit_range", _current_attack.get("range", brain.engage_range()))) + 0.4
	# From the ground to a little over its own top, whatever height the origin sits at: a drake's
	# bite and a wight's overhead both reach whoever stands in front of them (Hitbox.set_swing).
	var half := 0.45 * body_scale
	var origin_y := attack_origin.position.y
	hb.set_swing(half, reach, maxf(origin_y - 0.05, 0.1), maxf(capsule_height - origin_y, 0.0) + half)
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
	# ground a ward keeps this foe off it does not step onto, whatever it is doing
	if not _ward_tags.is_empty() and Wards.bars(_ward_tags, global_position, global_position + dir * maxf(s * 0.3, 0.5)):
		target_v = Vector3.ZERO
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_v, ACCEL * delta * maxf(s, 1.0))
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _damp(delta: float, rate: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _update_anim() -> void:
	# ground velocity in the body's frame, m/s: the model picks the gait and the rate from it
	var local := global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	anim.set_locomotion(Vector2(local.x, -local.z), false)


# --- reactions ----------------------------------------------------------------------------------

func take_hit(hit: HitData) -> String:
	var before := health
	var outcome := super.take_hit(hit)
	var dealt := maxf(before - health, 0.0)
	if dealt > 0.0:
		# Damage counts twice over: against the concentration of anything mid-note, and against
		# whatever is next to come off a thing that is put together.
		if _attack_phase == "channel":
			_channel_damage += dealt
		_damage_since_limb += dealt
		_check_damage_limb()
	if outcome != "dead" and hit.attacker is Node3D:
		perception.alert_to((hit.attacker as Node3D).global_position, hit.attacker as Node3D)
		minding = false
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
	if minding:
		return
	inactive = false
	_call_pack(perception.last_known)
	if is_boss and not boss_started:
		start_boss()


func _on_noise_heard(position: Vector3, _loudness: float) -> void:
	_remember(position)


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
	# A blow in progress belongs to the fight, so leaving the fight calls it off. Replacing its clip
	# with an idle loop used to strand it in its active phase for ever: a wolf that lost sight of
	# you mid-lunge went on lunging, across the arena and out of it.
	if from == Brain.COMBAT and (_attacking or _charging):
		on_action_interrupted()
	if to == Brain.COMBAT:
		EventBus.enemy_engaged.emit(self, true)
	elif from == Brain.COMBAT:
		EventBus.enemy_engaged.emit(self, false)
	match to:
		Brain.SEARCH:
			brain.has_search_point = false
			anim.play_intent("Idle")
		Brain.COMBAT:
			# A foe roused by the blow it is taking goes on taking it: its flinch, its stagger, a
			# crit's reaction, its fall or its death plays out, and the fight's idle waits. The idle
			# used to replace it at once. An unaware foe's backstab or sneak attack was never seen
			# to land, and one killed unaware stood back up in its guard.
			if not dead and not is_stunned() and not anim.is_busy():
				anim.play_intent("Idle_Combat")
		_:
			pass
	if from == Brain.COMBAT:
		_guard(false)


func _on_hearthstone_rested(_id: String) -> void:
	reset_to_spawn()


## Non-boss enemies reset when the player rests (DESIGN §5.4/§5.5).
func reset_to_spawn() -> void:
	if is_boss and boss_started:
		return
	global_position = spawn_position
	rotation.y = spawn_yaw
	velocity = Vector3.ZERO
	reset_physics_interpolation()     # put back, not walked back: no smear across the map
	perception.reset()
	brain.force(Brain.PATROL if patrol_points.size() > 1 else Brain.IDLE)
	inactive = archetype == "ambusher" or sits
	minding = sits
	_attacking = false
	_charging = false
	_flee_timer = 0.0
	_lure_engaged = false
	_lure_closed = 0.0
	_roused_by_greed = false
	is_blocking = false
	can_parry = false
	block_stability = 0.0
	stamina_comp.regen_multiplier = 1.0
	_attack_cooldowns.clear()
	if not _limbs.is_empty() and _limbs_broken > 0:
		# A thrall the player walked away from is whole again by the time they come back.
		_limbs_broken = 0
		current_attacks = attacks
		poise_max = float(def.get("stats", {}).get("poise", poise_max))
		poise_comp.setup(poise_max)
		speed = float(def.get("stats", {}).get("speed", speed))
	brain.params = Brain.params_for(archetype, def.get("behaviour", {}))
	marks_range = def.get("marks", marks_range)
	if dead:
		revive()
		collision_layer = LAYER_ENEMY
	else:
		full_restore()
	anim.play_intent("Idle")


# --- limbs --------------------------------------------------------------------------------------

## Poise is the lever that takes a stone-thrall apart: every time its footing goes, something
## comes off, and what comes off decides what it can still do to you.
func _on_poise_broken() -> void:
	super()
	# Only the pieces that come off when the footing goes. The King's arms have to be broken.
	var limb := EnemyAbilities.next_limb(_limbs, _limbs_broken)
	if not limb.is_empty() and EnemyAbilities.limb_breaks_on_poise(limb):
		_break_next_limb()


func _break_next_limb() -> void:
	var limb := EnemyAbilities.next_limb(_limbs, _limbs_broken)
	if limb.is_empty():
		return
	var index := _limbs_broken
	_limbs_broken += 1
	_damage_since_limb = 0.0
	current_attacks = EnemyAbilities.apply_broken_limbs(_phase_attacks(), _limbs, _limbs_broken)
	poise_max = EnemyAbilities.poise_after_limb(poise_max, limb)
	poise_comp.setup(poise_max)
	speed = EnemyAbilities.speed_after_limb(speed, limb)
	_attack_cooldowns.clear()
	limb_broken.emit(index, limb)
	if limb.has("say"):
		EventBus.notify.emit(str(limb["say"]), "combat")


## A limb that comes off by being hit enough rather than by the footing going: the Stone-Thrall
## King's arms, which the bible says you break to change what it can do.
func _check_damage_limb() -> void:
	var limb := EnemyAbilities.next_limb(_limbs, _limbs_broken)
	if limb.is_empty() or EnemyAbilities.limb_breaks_on_poise(limb):
		return
	if _damage_since_limb >= EnemyAbilities.limb_damage_needed(limb):
		_break_next_limb()


## The attack set this phase would have if nothing had been broken off yet.
func _phase_attacks() -> Array:
	if phase_index >= 0 and phase_index < phases.size():
		var phase: Dictionary = phases[phase_index]
		if phase.has("attacks"):
			return phase["attacks"]
	return attacks


func limbs_broken() -> int:
	return _limbs_broken


# --- guarded ground -------------------------------------------------------------------------------

## A Warden does not chase and does not care what you are. It cares what you take. Opening
## anything inside its radius rouses it, and a roused Warden fights harder than a watching one.
func _on_container_opened(container: Node, actor: Node) -> void:
	if container is Node3D:
		_greed(container.global_position, actor)


func _on_item_acquired(_item_id: String, _count: int) -> void:
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node3D:
			_greed((n as Node3D).global_position, n)
			return


func _greed(at: Vector3, thief: Node) -> void:
	if dead or not is_inside_tree():
		return
	if not EnemyAbilities.greed_rouses(brain.post, at, brain.params):
		return
	if not _roused_by_greed:
		_roused_by_greed = true
		brain.params["aggression"] = EnemyAbilities.guard_aggression(float(brain.param("aggression", 0.8)), brain.params)
	minding = false
	inactive = false
	perception.alert_to(at, thief as Node3D if thief is Node3D else null)
	brain.force(Brain.COMBAT)


func is_roused() -> bool:
	return _roused_by_greed


# --- the duelist's answer ---------------------------------------------------------------------

## A bravo that has seen a swing begin sometimes gets its guard there in time. The press is
## scheduled, not instant: DamageModel.parry_succeeds still decides whether it was early enough.
func _watch_for_swings() -> void:
	if not EnemyAbilities.parries(brain.params):
		return
	if _watched_target == target:
		return
	if _watched_target != null and is_instance_valid(_watched_target) and _watched_target.has_signal("attack_started"):
		if _watched_target.attack_started.is_connected(_on_target_swing):
			_watched_target.attack_started.disconnect(_on_target_swing)
	_watched_target = target
	if _watched_target != null and _watched_target.has_signal("attack_started"):
		_watched_target.attack_started.connect(_on_target_swing)


func _on_target_swing(_kind: String, _index: int) -> void:
	if dead or not is_blocking:
		return
	var at := EnemyAbilities.parry_press_at(now(), brain.params, randf())
	if at >= 0.0:
		_schedule_parry(at - now())


func _schedule_parry(delay: float) -> void:
	if delay <= 0.0:
		_press_guard()
		return
	# Bound to a method rather than a closure: freeing the enemy takes the connection with it,
	# so a bravo that dies mid-swing leaves nothing behind to fire into.
	get_tree().create_timer(delay, false, true).timeout.connect(_press_guard)


func _press_guard() -> void:
	if not dead and is_blocking:
		parry_pressed_at = now()


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
	# A new phase does not grow back what has already come off: the phase's own attack set goes
	# through the same filter the broken limbs applied to the last one.
	current_attacks = EnemyAbilities.apply_broken_limbs(phase.get("attacks", attacks), _limbs, _limbs_broken)
	for key in ["engage_range", "circle", "aggression", "hyper_armour", "retreat_threshold"]:
		if phase.has(key):
			brain.params[key] = phase[key]
	if phase.has("speed"):
		speed = float(phase["speed"])
	_attack_cooldowns.clear()
	if EnemyAbilities.lights_by_renown(phase):
		var bound := arena()
		if bound != null:
			bound.light_by_renown(true)
	phase_changed.emit(index, phase)
	if is_boss and index > 0:
		EventBus.boss_phase_changed.emit(enemy_id, index)
	if phase.has("say"):
		EventBus.notify.emit(str(phase["say"]), "boss")
	# A phase that begins with a sound (the Barrow Reeve ringing his hammer on the floor) makes it.
	if phase.has("sound") and index > 0 and is_inside_tree():
		Foley.play(str(phase["sound"]), global_position + Vector3.UP * 1.5)


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
	EventBus.enemy_engaged.emit(self, false)
	queue_free()


func _on_died(killer: Node) -> void:
	if brain != null and brain.state == Brain.COMBAT:
		EventBus.enemy_engaged.emit(self, false)
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
	d["limbs_broken"] = _limbs_broken
	d["roused"] = _roused_by_greed
	return d


func from_save(d: Dictionary) -> void:
	super.from_save(d)
	brain.from_save(d.get("brain", {}))
	var s: Array = d.get("spawn", [spawn_position.x, spawn_position.y, spawn_position.z])
	spawn_position = Vector3(float(s[0]), float(s[1]), float(s[2]))
	spawn_yaw = float(d.get("spawn_yaw", spawn_yaw))
	inactive = bool(d.get("inactive", inactive))
	_roused_by_greed = bool(d.get("roused", false))
	if _roused_by_greed:
		brain.params["aggression"] = EnemyAbilities.guard_aggression(float(brain.param("aggression", 0.8)), brain.params)
	var want_broken := int(d.get("limbs_broken", 0))
	while _limbs_broken < want_broken and _limbs_broken < _limbs.size():
		_break_next_limb()
	var p := int(d.get("phase", -1))
	if p >= 0 and p < phases.size():
		_enter_phase(p)
