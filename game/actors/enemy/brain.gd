class_name Brain
extends Node
## Enemy state machine (DESIGN §5.4): idle/patrol → suspicious → search → combat → return.
## The transition logic is pure (decide()) so it unit-tests without a scene; the Enemy runs the
## movement and attacks for whatever state this picks. Archetype parameters come from the enemy
## def's `behaviour` block, defaulted per archetype in ARCHETYPES.

signal state_changed(from: String, to: String)

const IDLE := "idle"
const PATROL := "patrol"
const SUSPICIOUS := "suspicious"
const SEARCH := "search"
const COMBAT := "combat"
const RETURN := "return"
const STATES: Array[String] = [IDLE, PATROL, SUSPICIOUS, SEARCH, COMBAT, RETURN]
## A fighter whose leash broke keeps walking home until it is within this share of the leash.
const RETURN_HOME := 0.5
## ... and on the way turns only on somebody this close (metres), whatever its own engage range.
const REENGAGE_REACH := 3.0

## Per-archetype defaults for the `behaviour` block. Any enemy def may override each key.
const ARCHETYPES := {
	"brute":      {"engage_range": 2.4, "circle": 0.05, "retreat_threshold": 0.0,  "patience": 2.5, "leash": 26.0, "strafe_speed": 0.4, "hyper_armour": 12.0, "aggression": 0.85},
	"skirmisher": {"engage_range": 2.2, "circle": 0.55, "retreat_threshold": 0.3,  "patience": 3.5, "leash": 34.0, "strafe_speed": 1.0, "retreat_time": 1.4, "aggression": 0.7},
	"pack":       {"engage_range": 2.0, "circle": 0.8,  "retreat_threshold": 0.25, "patience": 4.0, "leash": 40.0, "strafe_speed": 1.2, "flank": true, "spread": 2.6, "aggression": 0.5},
	"charger":    {"engage_range": 3.0, "circle": 0.1,  "retreat_threshold": 0.0,  "patience": 2.0, "leash": 34.0, "strafe_speed": 0.3, "charge_range": 12.0, "aggression": 0.9},
	"ambusher":   {"engage_range": 2.2, "circle": 0.3,  "retreat_threshold": 0.2,  "patience": 6.0, "leash": 22.0, "strafe_speed": 0.8, "ambush_range": 4.5, "aggression": 1.0},
	"caster":     {"engage_range": 12.0, "circle": 0.5, "retreat_threshold": 0.45, "patience": 5.0, "leash": 30.0, "strafe_speed": 0.9, "keep_distance": 9.0, "aggression": 0.6},
	"sentinel":   {"engage_range": 2.6, "circle": 0.0,  "retreat_threshold": 0.0,  "patience": 1.5, "leash": 8.0,  "strafe_speed": 0.2, "never_leaves_post": true, "aggression": 0.8},
	"swarm":      {"engage_range": 1.8, "circle": 0.4,  "retreat_threshold": 0.1,  "patience": 3.0, "leash": 28.0, "strafe_speed": 0.9, "spread": 1.6, "aggression": 0.9},
	"elite":      {"engage_range": 2.4, "circle": 0.45, "retreat_threshold": 0.15, "patience": 4.0, "leash": 32.0, "strafe_speed": 1.0, "parries": true, "aggression": 0.75},
	"boss":       {"engage_range": 3.0, "circle": 0.3,  "retreat_threshold": 0.0,  "patience": 99.0, "leash": 60.0, "strafe_speed": 0.8, "hyper_armour": 18.0, "aggression": 0.9},
}
const DEFAULTS := {"engage_range": 2.2, "circle": 0.4, "retreat_threshold": 0.2, "patience": 3.0, "leash": 30.0, "strafe_speed": 0.8, "aggression": 0.7}

var archetype: String = "skirmisher"
var params: Dictionary = DEFAULTS.duplicate()
var state: String = IDLE
var time_in_state: float = 0.0
## Where this enemy belongs; leash and return are measured from here.
var post: Vector3 = Vector3.ZERO
var patrol_points: PackedVector3Array = PackedVector3Array()
var patrol_index: int = 0
## Set by the enemy each tick from its perception and body.
var search_point: Vector3 = Vector3.ZERO
var has_search_point: bool = false


static func params_for(arch: String, overrides: Dictionary = {}) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	out.merge(ARCHETYPES.get(arch, {}), true)
	out.merge(overrides, true)
	return out


func setup(arch: String, behaviour: Dictionary, home: Vector3) -> void:
	archetype = arch
	params = params_for(arch, behaviour)
	post = home
	state = PATROL if patrol_points.size() > 1 else IDLE


func param(key: String, fallback: Variant = 0.0) -> Variant:
	return params.get(key, fallback)


func leash() -> float:
	return float(params.get("leash", 30.0))


func patience() -> float:
	return float(params.get("patience", 3.0))


func engage_range() -> float:
	return float(params.get("engage_range", 2.2))


# --- pure transition logic ---------------------------------------------------------------------

## Decides the next state. `ctx` keys:
##   detection (0..1), can_see (bool), alerted (bool: heard/hit/pack call),
##   distance_to_post, distance_to_target, target_alive (bool),
##   time_in_state, patrol (bool: has a patrol route), inactive (ambusher waiting),
##   time_unseen (seconds since the target was last seen; defaults to time_in_state)
static func decide(current: String, p: Dictionary, ctx: Dictionary) -> String:
	var detection := float(ctx.get("detection", 0.0))
	var can_see := bool(ctx.get("can_see", false))
	var alerted := bool(ctx.get("alerted", false))
	var target_alive := bool(ctx.get("target_alive", false))
	var d_post := float(ctx.get("distance_to_post", 0.0))
	var d_target := float(ctx.get("distance_to_target", INF))
	var t := float(ctx.get("time_in_state", 0.0))
	var unseen := float(ctx.get("time_unseen", t))
	var leash_m := float(p.get("leash", 30.0))
	var patience_s := float(p.get("patience", 3.0))
	var never_leaves := bool(p.get("never_leaves_post", false))
	var ambush_range := float(p.get("ambush_range", 0.0))
	# An ambusher stays inactive until the target is close enough, whatever it can see.
	if bool(ctx.get("inactive", false)):
		if target_alive and d_target <= ambush_range:
			return COMBAT
		return current
	# Engaged: hold combat until the target dies, is lost, or the leash breaks.
	if current == COMBAT:
		if not target_alive:
			return RETURN
		if d_post > leash_m or (never_leaves and d_target > leash_m):
			return RETURN
		# Patience runs from the last sight of the target, not from the start of the fight: past
		# `patience` seconds into any fight, one frame without sight (a roll past its shoulder)
		# used to send a fighter off to search, often in the middle of its own blow.
		if not can_see and unseen > patience_s:
			return SEARCH
		return COMBAT
	# A broken leash holds until the fighter is well back inside it. On the way home it turns only
	# on somebody within arm's reach; seeing its quarry is not enough, or the leash lasts a frame and
	# the chase goes on past the threshold DESIGN §5.4 says it stops at (a caster kiting a player
	# walked 50 m from a 32 m leash in `./run.sh fights`).
	if current == RETURN and target_alive and d_post > leash_m * RETURN_HOME:
		if d_target <= REENGAGE_REACH and (detection >= 1.0 or can_see):
			return COMBAT
		return RETURN
	# Anything that fully detects a live target fights it.
	if target_alive and (detection >= 1.0 or (alerted and can_see)):
		if never_leaves and d_target > leash_m:
			return current if current != COMBAT else RETURN
		return COMBAT
	match current:
		SEARCH:
			if t > patience_s * 2.0:
				return RETURN
			if detection >= Perception.SUSPICION_LEVEL:
				return SEARCH
			return SEARCH if t <= patience_s * 2.0 else RETURN
		SUSPICIOUS:
			if detection < Perception.SUSPICION_LEVEL * 0.5:
				return RETURN if d_post > 1.5 else _resting_state(ctx)
			if t > patience_s:
				return SEARCH
			return SUSPICIOUS
		RETURN:
			if detection >= Perception.SUSPICION_LEVEL:
				return SUSPICIOUS
			if d_post <= 1.5:
				return _resting_state(ctx)
			return RETURN
		_:
			if detection >= Perception.SUSPICION_LEVEL or alerted:
				return SUSPICIOUS
			if d_post > leash_m:
				return RETURN
			return _resting_state(ctx)


static func _resting_state(ctx: Dictionary) -> String:
	return PATROL if bool(ctx.get("patrol", false)) else IDLE


# --- runtime ------------------------------------------------------------------------------------

func tick(delta: float, ctx: Dictionary) -> String:
	time_in_state += delta
	ctx["time_in_state"] = time_in_state
	ctx["patrol"] = patrol_points.size() > 1
	var next := decide(state, params, ctx)
	if next != state:
		set_state(next)
	return state


func set_state(next: String) -> void:
	if next == state:
		return
	var prev := state
	state = next
	time_in_state = 0.0
	state_changed.emit(prev, next)


func force(next: String) -> void:
	set_state(next)


func next_patrol_point() -> Vector3:
	if patrol_points.is_empty():
		return post
	patrol_index = (patrol_index + 1) % patrol_points.size()
	return patrol_points[patrol_index]


func current_patrol_point() -> Vector3:
	if patrol_points.is_empty():
		return post
	return patrol_points[patrol_index % patrol_points.size()]


func is_fighting() -> bool:
	return state == COMBAT


func to_save() -> Dictionary:
	return {"state": state, "patrol_index": patrol_index, "post": [post.x, post.y, post.z]}


func from_save(d: Dictionary) -> void:
	state = str(d.get("state", IDLE))
	patrol_index = int(d.get("patrol_index", 0))
	var p: Array = d.get("post", [post.x, post.y, post.z])
	post = Vector3(float(p[0]), float(p[1]), float(p[2]))
	time_in_state = 0.0
