class_name BodyGuard
extends RefCounted

## Keeps a body's position and velocity real. The owner's Briar crash (2026-09-30): a villager's
## position went to NaN by Fernhold, the terrain was asked its height at x = NaN (an index of -2^63
## into the height map), and a NaN body in Jolt's broadphase flooded its job queue. Whatever made
## the first NaN, one body with one must never carry it on into the physics or the world's lookups.
##
## Each body with its own gravity or snap holds one and calls `check` once a physics frame (before
## its move and after it). A body is put back when its position or velocity is not finite, when
## it stands further than FAR_M from the world's middle, when it has sunk more than BELOW_M under
## the ground it stands over, or when it has been falling for more than FALL_S: on its last good
## ground (where it last stood, finite, on the floor or the terrain), or `home` when it has none.
## Its velocity is zeroed. The first time for each body it is said, with where it was.

## a body under the ground by more than this has gone through it
const BELOW_M := 30.0
## falling this long with nothing under it: a fall with no floor (six seconds is 176 m)
const FALL_S := 6.0
## the world is 8.2 km across, centred on the origin; nothing stands 20 km out
const FAR_M := 20000.0
## how often the last good ground is taken, seconds (it need not be every frame)
const KEEP_EVERY_S := 0.25

var last_good := Vector3.INF
var falling_s := 0.0
var recoveries := 0
var _warned := false
var _keep_left := 0.0


## Whether `v` is a real place: finite, and within the world's reach.
static func sane(v: Vector3) -> bool:
	return v.is_finite() and absf(v.x) < FAR_M and absf(v.y) < FAR_M and absf(v.z) < FAR_M


## The ground under `p` from the world, or NAN without one (or at a point that is not finite).
static func ground_at(p: Vector3) -> float:
	if not p.is_finite() or not WorldProbe.has_world():
		return NAN
	var h := WorldProbe.get_height(p.x, p.z, NAN)
	return h if is_finite(h) else NAN


## One physics frame's check. `grounded`: the body stands on something this frame (a floor, or the
## terrain it is snapped to). `home` (() -> Vector3) is asked only when a body with no last good
## ground must be put back: its spawn, its spot. Returns true when the body was put back.
func check(body: CharacterBody3D, delta: float, grounded: bool, home := Callable()) -> bool:
	if body == null or not body.is_inside_tree():
		return false
	var p := body.global_position
	var why := ""
	if not p.is_finite() or not body.velocity.is_finite():
		why = "its position or velocity went to NaN or inf"
	elif not sane(p):
		why = "it was %.0f m from the world's middle" % Vector2(p.x, p.z).length()
	else:
		if grounded or body.velocity.y >= -0.5:
			falling_s = 0.0
		else:
			falling_s += delta
		# the ground is asked only of a body going down (one standing on it is on it)
		var g := ground_at(p) if falling_s > 0.0 else NAN
		if not is_nan(g) and p.y < g - BELOW_M:
			why = "it was %.0f m under the ground" % (g - p.y)
		elif falling_s > FALL_S:
			why = "it had been falling for %.1f s" % falling_s
	if why.is_empty():
		_keep_left -= delta
		if grounded and _keep_left <= 0.0:
			_keep_left = KEEP_EVERY_S
			last_good = p
		return false
	_put_back(body, why, home)
	return true


func _put_back(body: CharacterBody3D, why: String, home: Callable) -> void:
	var to := last_good
	if not sane(to) and home.is_valid():
		var h: Variant = home.call()
		to = h if h is Vector3 else Vector3.INF
	if not sane(to):
		to = Vector3.ZERO
	var g := ground_at(to)
	if not is_nan(g) and to.y < g:
		to.y = g
	recoveries += 1
	falling_s = 0.0
	if not _warned:
		_warned = true
		Log.warn("BodyGuard", "%s put back at (%.1f, %.1f, %.1f): %s (from %s)" % [
				body.name, to.x, to.y, to.z, why, str(body.global_position)])
	body.velocity = Vector3.ZERO
	body.global_position = to
	last_good = to
