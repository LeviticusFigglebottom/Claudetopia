class_name Perception
extends Node3D
## Sight cone + hearing for one enemy, and the `detection` 0..1 meter the stealth system reads.
## Detection rises while a hostile target is visible (faster when close, in the open and lit) and
## decays when it is not. `noise_heard(pos, loudness)` is the hook noisy actors call.

signal detected(target: Node3D)           # detection reached 1.0
signal suspicion_raised(position: Vector3)
signal lost(last_known: Vector3)
signal noise(position: Vector3, loudness: float)

const MASK_SIGHT := (1 << 0) | (1 << 10)          # world | terrain block line of sight
const SUSPICION_LEVEL := 0.35
const EYE_HEIGHT := 1.55
const BASE_GAIN := 0.9
const BASE_DECAY := 0.22
const MEMORY := 6.0
## Group a summoned ally joins: hostiles hunt it, and it hunts them (DESIGN §5.3, Calling).
const ALLY_GROUP := "summon_ally"
## How often the candidate sweep runs. Between sweeps the current quarry is kept if it lives.
const SCAN_INTERVAL := 0.4

@export var sight_range: float = 22.0
@export var sight_fov: float = 110.0
@export var hearing: float = 14.0
## Multiplies detection gain; archetypes and difficulty tune it.
@export var alertness: float = 1.0

var owner_actor: Node3D = null
var eye_offset: float = EYE_HEIGHT
## 0 = unaware, 1 = fully detected. The stealth stream reads this.
var detection: float = 0.0
var target: Node3D = null
var last_known: Vector3 = Vector3.ZERO
var has_last_known: bool = false
var can_see_target: bool = false
var time_since_seen: float = 999.0
var enabled: bool = true

var _was_detected: bool = false
var _was_suspicious: bool = false
var _scan_left: float = 0.0
var _candidate: Node3D = null
var _candidate_group: String = "player"


func setup(actor: Node3D, def: Dictionary) -> void:
	owner_actor = actor
	var p: Dictionary = def.get("perception", {})
	sight_range = float(p.get("sight_range", sight_range))
	sight_fov = float(p.get("sight_fov", sight_fov))
	hearing = float(p.get("hearing", hearing))
	alertness = float(p.get("alertness", alertness))
	eye_offset = float(p.get("eye_height", EYE_HEIGHT))


# --- pure helpers ---------------------------------------------------------------------------

## Is `point` inside the cone (range + fov) around `origin` facing `forward`?
static func in_cone(origin: Vector3, forward: Vector3, point: Vector3, range_m: float, fov_degrees: float) -> bool:
	var to := point - origin
	var dist := to.length()
	if dist > range_m or dist < 0.001:
		return dist <= range_m
	var f := Vector3(forward.x, 0.0, forward.z).normalized()
	var t := Vector3(to.x, 0.0, to.z)
	if t.length_squared() < 0.0001:
		return true
	var ang := rad_to_deg(acos(clampf(f.dot(t.normalized()), -1.0, 1.0)))
	return ang <= fov_degrees * 0.5


## Detection gained per second at this distance and visibility (1 = plain sight, 0 = invisible).
static func gain_rate(distance: float, range_m: float, visibility: float, alert: float) -> float:
	var closeness := clampf(1.0 - distance / maxf(range_m, 0.01), 0.0, 1.0)
	return BASE_GAIN * (0.35 + 1.3 * closeness) * clampf(visibility, 0.0, 2.0) * alert


func _physics_process(delta: float) -> void:
	if not enabled or owner_actor == null:
		return
	time_since_seen += delta
	_scan_left -= delta
	var t := _find_target()
	can_see_target = t != null and can_see(t)
	if can_see_target:
		target = t
		last_known = t.global_position
		has_last_known = true
		time_since_seen = 0.0
		var vis: float = float(t.get("stealth_visibility")) if t.get("stealth_visibility") != null else 1.0
		detection = clampf(detection + gain_rate(eye_position().distance_to(t.global_position), sight_range, vis, alertness) * delta, 0.0, 1.0)
	else:
		detection = clampf(detection - BASE_DECAY * delta, 0.0, 1.0)
		if time_since_seen > MEMORY and _was_detected:
			_was_detected = false
			lost.emit(last_known)
	if detection >= 1.0 and not _was_detected:
		_was_detected = true
		_was_suspicious = true
		detected.emit(target)
		EventBus.detection_changed.emit(owner_actor, detection)
	elif detection >= SUSPICION_LEVEL and not _was_suspicious:
		_was_suspicious = true
		suspicion_raised.emit(last_known if has_last_known else global_position)
	elif detection < SUSPICION_LEVEL * 0.5:
		_was_suspicious = false


func eye_position() -> Vector3:
	return owner_actor.global_position + Vector3.UP * eye_offset


## The nearest living thing this one is hostile to. The player is always a candidate; summoned
## allies are candidates for anything that hunts them, and anything hostile is a candidate for
## an ally. The sweep is throttled because it runs per enemy per frame and the answer rarely
## changes between sweeps.
func _find_target() -> Node3D:
	if owner_actor == null or not owner_actor.is_inside_tree():
		return null
	if _scan_left > 0.0 and _is_live_quarry(_candidate, _candidate_group):
		return _candidate
	_scan_left = SCAN_INTERVAL
	var tree := owner_actor.get_tree()
	var groups: Array[String] = ["player"]
	if not tree.get_nodes_in_group(ALLY_GROUP).is_empty():
		groups.append(ALLY_GROUP)
		if owner_actor.is_in_group(ALLY_GROUP):
			groups.append("enemy")
	var best: Node3D = null
	var best_d := INF
	for group: String in groups:
		for n in tree.get_nodes_in_group(group):
			if not _is_live_quarry(n, group):
				continue
			var d: float = owner_actor.global_position.distance_to((n as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = n as Node3D
				_candidate_group = group
	_candidate = best
	return best


## A candidate has to be a living body. Everything hunts the player by default — that rule
## predates factions and stand-in player nodes in tests rely on it — but an ally the player
## called does not, and the ally/hostile groups are filtered by the faction rule.
func _is_live_quarry(n: Variant, group: String) -> bool:
	# Validity first: `is` on a freed body (the last candidate, gone since the last sweep) is a
	# script error, not a false.
	if not is_instance_valid(n) or not (n is Node3D) or n == owner_actor:
		return false
	var node := n as Node3D
	# A body out of the tree (the player between the world and an interior) is nowhere to be seen:
	# its transform is an engine error a frame, fourteen of them in one suite run.
	if not node.is_inside_tree():
		return false
	if node.has_method("is_alive") and not node.is_alive():
		return false
	if group == "player" and not owner_actor.is_in_group(ALLY_GROUP):
		return true
	if owner_actor.has_method("is_hostile_to") and not owner_actor.is_hostile_to(node):
		return false
	return true


func can_see(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	var origin := eye_position()
	var point: Vector3 = t.global_position + Vector3.UP
	var forward := -owner_actor.global_transform.basis.z
	var vis: float = float(t.get("stealth_visibility")) if t.get("stealth_visibility") != null else 1.0
	var effective_range := sight_range * clampf(vis, 0.15, 1.5)
	if not in_cone(origin, forward, point, effective_range, sight_fov):
		return false
	return has_line_of_sight(point)


func has_line_of_sight(point: Vector3) -> bool:
	if owner_actor == null or not owner_actor.is_inside_tree():
		return false
	var space := owner_actor.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if owner_actor is CollisionObject3D:
		exclude.append((owner_actor as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(eye_position(), point, MASK_SIGHT, exclude)
	return space.intersect_ray(q).is_empty()


## Hook for noisy events (footsteps, swings, breaking things). Loudness ~0..1.
func noise_heard(at: Vector3, loudness: float) -> void:
	if not enabled or owner_actor == null:
		return
	var d := owner_actor.global_position.distance_to(at)
	var radius := hearing * clampf(loudness, 0.0, 2.0)
	if d > radius:
		return
	last_known = at
	has_last_known = true
	detection = clampf(detection + 0.35 * (1.0 - d / maxf(radius, 0.01)), 0.0, 0.95)
	noise.emit(at, loudness)
	if detection >= SUSPICION_LEVEL and not _was_suspicious:
		_was_suspicious = true
		suspicion_raised.emit(at)


## Called when the enemy is hit from somewhere: full alert without a sight check.
func alert_to(at: Vector3, t: Node3D = null) -> void:
	last_known = at
	has_last_known = true
	detection = 1.0
	time_since_seen = 0.0
	if t != null:
		target = t
	if not _was_detected:
		_was_detected = true
		_was_suspicious = true
		detected.emit(target)


func reset() -> void:
	detection = 0.0
	target = null
	has_last_known = false
	can_see_target = false
	time_since_seen = 999.0
	_was_detected = false
	_was_suspicious = false
