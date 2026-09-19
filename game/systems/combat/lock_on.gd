class_name LockOn
extends Node
## Targeting service (DESIGN §5.3): picks a target inside a 30 m cone in front of the viewer,
## cycles left/right by angle, and drops targets that die or leave 40 m. Candidates are nodes in
## group "lockable" that report is_alive(); they may offer lock_point() for the reticle.
## The pure picking maths works on positions so it is testable without a scene.

signal target_changed(target: Node3D)

const GROUP := "lockable"

var max_range: float = DamageModel.LOCK_ON_RANGE
var cone_deg: float = DamageModel.LOCK_ON_CONE_DEG
var break_range: float = DamageModel.LOCK_ON_BREAK_RANGE
var owner_actor: Node = null
var target: Node3D = null


# --- pure -----------------------------------------------------------------------------------

## Score of a candidate (lower is better) or -1.0 when it is outside the cone/range.
static func score(origin: Vector3, forward: Vector3, pos: Vector3, range_m: float, cone_degrees: float) -> float:
	var to := pos - origin
	var dist := to.length()
	if dist > range_m or dist < 0.001:
		return -1.0
	var f := Vector3(forward.x, 0.0, forward.z).normalized()
	var t := Vector3(to.x, 0.0, to.z)
	if t.length_squared() < 0.0001:
		return dist * 0.02
	var ang := rad_to_deg(acos(clampf(f.dot(t.normalized()), -1.0, 1.0)))
	if ang > cone_degrees:
		return -1.0
	return ang / cone_degrees + dist / range_m * 0.5


## Index of the best candidate position, or -1.
static func pick_index(origin: Vector3, forward: Vector3, positions: PackedVector3Array, range_m: float, cone_degrees: float) -> int:
	var best := -1
	var best_score := INF
	for i in positions.size():
		var s := score(origin, forward, positions[i], range_m, cone_degrees)
		if s >= 0.0 and s < best_score:
			best_score = s
			best = i
	return best


## Signed yaw angle (degrees) of a position relative to forward: negative = left, positive = right.
static func signed_angle(origin: Vector3, forward: Vector3, pos: Vector3) -> float:
	var f := Vector3(forward.x, 0.0, forward.z).normalized()
	var t := Vector3(pos.x - origin.x, 0.0, pos.z - origin.z).normalized()
	return rad_to_deg(atan2(f.cross(t).y, f.dot(t))) * -1.0


## Next candidate to the right (direction > 0) or left (< 0) of the current one, within range.
## Wraps around when nothing lies further in that direction. Returns -1 when no alternative exists.
static func cycle_index(origin: Vector3, forward: Vector3, positions: PackedVector3Array, current: int, direction: int, range_m: float) -> int:
	var cur_angle := signed_angle(origin, forward, positions[current]) if current >= 0 and current < positions.size() else 0.0
	var best := -1
	var best_delta := INF
	var wrap := -1
	var wrap_delta := INF
	for i in positions.size():
		if i == current or origin.distance_to(positions[i]) > range_m:
			continue
		var a := signed_angle(origin, forward, positions[i])
		var delta := (a - cur_angle) * float(sign(direction))
		if delta > 0.001 and delta < best_delta:
			# The nearest target further in the requested direction.
			best_delta = delta
			best = i
		elif delta <= 0.001 and delta < wrap_delta:
			# Nothing further that way: wrap to the one furthest back the other way.
			wrap_delta = delta
			wrap = i
	return best if best >= 0 else wrap


# --- runtime --------------------------------------------------------------------------------

func candidates() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(GROUP):
		if n == owner_actor or not (n is Node3D):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		out.append(n)
	return out


static func point_of(n: Node3D) -> Vector3:
	if n.has_method("lock_point"):
		return n.lock_point()
	return n.global_position + Vector3.UP * 1.0


func acquire(origin: Vector3, forward: Vector3) -> bool:
	var list := candidates()
	var positions := PackedVector3Array()
	for n in list:
		positions.append(point_of(n))
	var i := pick_index(origin, forward, positions, max_range, cone_deg)
	set_target(list[i] if i >= 0 else null)
	return target != null


func cycle(origin: Vector3, forward: Vector3, direction: int) -> void:
	var list := candidates()
	if list.is_empty():
		return
	var positions := PackedVector3Array()
	var current := -1
	for i in list.size():
		positions.append(point_of(list[i]))
		if list[i] == target:
			current = i
	var next := cycle_index(origin, forward, positions, current, direction, max_range)
	if next >= 0:
		set_target(list[next])


func set_target(t: Node3D) -> void:
	if t == target:
		return
	target = t
	target_changed.emit(target)


func clear() -> void:
	set_target(null)


func is_locked() -> bool:
	return target != null and is_instance_valid(target)


## Drops the target when it died, was freed, or moved beyond break_range.
func validate(origin: Vector3) -> void:
	if target == null:
		return
	if not is_instance_valid(target) or (target.has_method("is_alive") and not target.is_alive()):
		set_target(null)
		return
	if origin.distance_to(target.global_position) > break_range:
		set_target(null)


func target_point() -> Vector3:
	if is_locked():
		return point_of(target)
	return Vector3.ZERO
