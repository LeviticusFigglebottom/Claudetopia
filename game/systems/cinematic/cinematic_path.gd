class_name CinematicPath
extends RefCounted
## One shot's camera, resolved against the ground it will be played over: a position, a point
## to look at and a field of view per key, and a smooth eased pose for any moment of the shot.
##
## Resolution takes two questions as callables, so the same code answers them from the live
## world (`CinematicPlayer`), from the runtime maps with no world at all (the tests), or from
## the full-resolution heights (the clearance test):
##   ground(x: float, z: float) -> float     the surface under a point: ground, or water on it
##   place(id: String) -> Vector3            where a place or POI stands; Vector3.INF if nowhere
## "player" is answered by `player_at`, the spot control is handed back on, and the last key of
## the hand-over shot by `player_camera`, the gameplay camera's own transform, so the shot ends
## on exactly the frame play begins with.
##
## Between keys the path is a cubic Hermite spline whose tangents respect the keys' times, so it
## passes through every key with no kink and no change of pace at one; the whole shot is then
## eased, so every camera move starts and ends at rest.

## A camera looking along the gameplay camera's forward looks at a point this far down it.
const LOOK_REACH := 40.0

var shot_id := ""
var times := PackedFloat32Array()
var points := PackedVector3Array()
var looks := PackedVector3Array()
var fovs := PackedFloat32Array()
@warning_ignore("shadowed_global_identifier")
var ease := "in_out"
## Keys that could not be placed (a place the world does not have). A path with any is not
## played; the player holds the previous picture instead of flying to the origin.
var unresolved: Array[String] = []


## Resolves `shot`'s keys. `player_camera` is only consulted for a key that names it.
static func resolve(shot: Dictionary, ground: Callable, place: Callable, player_at := Vector3.INF,
		player_camera := Transform3D(), player_fov := 75.0) -> CinematicPath:
	var path := CinematicPath.new()
	path.shot_id = str(shot.get("id", ""))
	path.ease = str(shot.get("ease", "in_out"))
	var shot_fov := float(shot.get("fov", CinematicDef.DEFAULT_FOV))
	for key_v in shot.get("keys", []):
		var key: Dictionary = key_v
		var cam: Variant = key.get("at", null)
		var at := Vector3.INF
		var look := Vector3.INF
		var fov := float(key.get("fov", shot_fov))
		if cam is String and str(cam) == CinematicDef.PLAYER_CAMERA:
			at = player_camera.origin
			look = at - player_camera.basis.z * LOOK_REACH
			fov = float(key.get("fov", player_fov))
		elif cam is Dictionary:
			at = point_of(cam, ground, place, player_at)
			look = point_of(key.get("look", {}), ground, place, player_at)
		if at == Vector3.INF or look == Vector3.INF:
			path.unresolved.append("%s key at t %s" % [path.shot_id, str(key.get("t", "?"))])
			continue
		path.times.append(float(key.get("t", 0.0)))
		path.points.append(at)
		path.looks.append(look)
		path.fovs.append(fov)
	return path


## Where a key's point is: a place, moved `distance` metres along `bearing`, `height` metres
## above whatever is under it.
static func point_of(spec_v: Variant, ground: Callable, place: Callable, player_at := Vector3.INF) -> Vector3:
	if not (spec_v is Dictionary):
		return Vector3.INF
	var spec: Dictionary = spec_v
	var anchor_id := str(spec.get("place", ""))
	var anchor: Vector3 = player_at if anchor_id == CinematicDef.PLAYER_ANCHOR else place.call(anchor_id)
	if anchor == Vector3.INF:
		return Vector3.INF
	var bearing := deg_to_rad(float(spec.get("bearing", 0.0)))
	var distance := float(spec.get("distance", 0.0))
	var x := anchor.x + sin(bearing) * distance
	var z := anchor.z - cos(bearing) * distance
	return Vector3(x, float(ground.call(x, z)) + float(spec.get("height", 0.0)), z)


func is_playable() -> bool:
	return unresolved.is_empty() and points.size() >= 2


## The shot's own time, 0..1, bent by its ease.
func eased(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	match ease:
		"linear":
			return u
		"in":
			return 1.0 - cos(u * PI * 0.5)
		"out":
			return sin(u * PI * 0.5)
	return 0.5 - 0.5 * cos(u * PI)


## Whether `u` is in the last stretch of the path, between the last two keys: for a hand-over
## that is the camera arriving at the gameplay camera, which stands where its own rig puts it.
func arriving(u: float) -> bool:
	return times.size() >= 2 and eased(u) > times[times.size() - 2]


func position_at(u: float) -> Vector3:
	return _hermite(points, eased(u))


func look_point_at(u: float) -> Vector3:
	return _hermite(looks, eased(u))


func fov_at(u: float) -> float:
	if fovs.is_empty():
		return CinematicDef.DEFAULT_FOV
	var e := eased(u)
	var i := _segment(e)
	if i >= fovs.size() - 1:
		return fovs[fovs.size() - 1]
	var span := maxf(times[i + 1] - times[i], 0.00001)
	return lerpf(fovs[i], fovs[i + 1], clampf((e - times[i]) / span, 0.0, 1.0))


func pose(u: float) -> Transform3D:
	var at := position_at(u)
	var look := look_point_at(u)
	var dir := look - at
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	# a camera looking straight up or down has no way to know which way is up
	if absf(dir.normalized().y) > 0.995:
		dir = Vector3(dir.x + 0.01, dir.y, dir.z + 0.01)
	return Transform3D(Basis.looking_at(dir, Vector3.UP), at)


## `n` positions spread evenly over the shot's own time, for the clearance test and the probes.
func samples(n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		out.append(position_at(float(i) / float(maxi(n - 1, 1))))
	return out


func _segment(e: float) -> int:
	var i := 0
	while i < times.size() - 2 and e > times[i + 1]:
		i += 1
	return i


func _hermite(p: PackedVector3Array, e: float) -> Vector3:
	var n := p.size()
	if n == 0:
		return Vector3.ZERO
	if n == 1:
		return p[0]
	var i := _segment(e)
	var h := maxf(times[i + 1] - times[i], 0.00001)
	var s := clampf((e - times[i]) / h, 0.0, 1.0)
	var m0 := _tangent(p, i) * h
	var m1 := _tangent(p, i + 1) * h
	var s2 := s * s
	var s3 := s2 * s
	return p[i] * (2.0 * s3 - 3.0 * s2 + 1.0) + m0 * (s3 - 2.0 * s2 + s) \
			+ p[i + 1] * (-2.0 * s3 + 3.0 * s2) + m1 * (s3 - s2)


## The velocity through key `i` in path units per unit of shot time: one-sided at the ends, the
## chord across the key's neighbours in between, so a key reached late is left late.
func _tangent(p: PackedVector3Array, i: int) -> Vector3:
	var n := p.size()
	if i == 0:
		return (p[1] - p[0]) / maxf(times[1] - times[0], 0.00001)
	if i == n - 1:
		return (p[n - 1] - p[n - 2]) / maxf(times[n - 1] - times[n - 2], 0.00001)
	return (p[i + 1] - p[i - 1]) / maxf(times[i + 1] - times[i - 1], 0.00001)
