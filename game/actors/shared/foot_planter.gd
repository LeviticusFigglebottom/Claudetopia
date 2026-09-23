class_name FootPlanter
extends RefCounted
## Plants a standing body's feet where they were put down and steps them into its stance one
## foot at a time, so that no foot slides along the ground when the body stops.
##
## A stop freezes the gait wherever the stride had got to, one foot ahead and one behind, and the
## idle is another stance, the feet side by side under the hips. Cross-faded from the one into
## the other, both feet slid along the ground into the idle: 58.6 cm between them at the end of a
## stop from a jog (test_locomotion_blend). Here each foot is held where it stands, in the world,
## by a two-bone solve of its leg, and the hips come down as far as the wider stance needs; then
## the foot furthest from its place in the stance lifts and steps into it, and the other after
## it if it has to, a quarter of a second each. A foot the stop caught in the air steps first.
##
## Once the body has settled the feet stay held, and step again only when the body turns or
## drifts away from them: a villager turning to face someone shuffles round on its feet.
##
## It works on the pose the clips have just set, after the AnimationTree has advanced, and writes
## straight into the skeleton's pose, which the next advance writes over. It lets go when the
## body moves off, leaves the ground, plays a one-shot or is carried away (a teleport, a snap
## turn), and plants again when the body next stands.

## m/s over the ground below which the body stands and its feet are held
const STANDS_BELOW := 0.05
## m/s up or down above which the body has left the ground (a jump, a fall): let go at once
const AIRBORNE_FROM := 0.6
## seconds a step takes, and how high (m) the foot rises at the top of it
const STEP_S := 0.24
const STEP_LIFT := 0.06
## The share of a step at each end spent lifting the foot off the ground and setting it down,
## straight up and down: it travels only in between, when it is clear of the ground.
const STEP_LIFTING := 0.12
## While the body settles, a foot this far (m) or this turned (rad) from its place steps into it...
const STEP_FROM := 0.03
const TURN_FROM := 0.15
## ...and once it has settled, only when the body has turned or drifted this far from the foot.
const REPLANT_FROM := 0.10
const RETURN_FROM := 0.35
## seconds after planting before the looser thresholds take over
const SETTLE_S := 0.9
## A foot caught in the air (see DOWN_WITHIN) comes down first, and at once, whatever the other
## foot is doing.
const AIRBORNE_NEED := 10.0
## seconds to hand the feet back to the clips when the body moves off
const RELEASE_S := 0.1
## A standing body moved this far (m) along the ground in one frame, or turned this far (rad), was
## carried off (a teleport, a load) or put down facing a new way: the feet go back to the clips at
## once and are planted there. So is a held foot this far (m) from its place, past reaching. That
## was 0.7 m and the only test of a teleport, and a stop from a sprint leaves the back foot 0.9 m
## from its place: it snapped there in a frame.
const CARRIED_FROM := 0.25
const SNAP_TURN := 0.8
const LOST_FROM := 1.4
## Where a foot bears on the ground, as the forge turns it (tests/unit/foot_contact.gd): the heel
## on the ground this far (m) behind the ankle, and the ball at the toe joint. A foot with either
## within DOWN_WITHIN (m) of the height it stands at is on the ground, and is set down on it when
## it is planted; one with neither is in the air. (Measured at the ankle, a foot up on its ball
## counted as in the air, and came down with the other: both feet off the ground at once.)
const HEEL_BACK := 0.06
const DOWN_WITHIN := 0.03
## A body planted with both feet off the ground has the lower set down on it, when it is no higher
## than this (m): the push-off foot of a stop that ended a centimetre into its flight.
const SET_DOWN_FROM := 0.08
## The share of its length a leg may straighten to before the hips come down for it (or the
## clip's own share, when the clip has the leg straighter), and the most they come down.
const STRAIGHT := 0.97
const MOST_DROP := 0.25


class Foot:
	var upper := -1
	var lower := -1
	var bone := -1
	var toe := -1
	var thigh := 0.0
	var shin := 0.0
	## the heel and the ball in the foot bone's own space, and the ball's height at rest (skeleton
	## space)
	var heel := Vector3.ZERO
	var ball := Vector3.ZERO
	var ball_height := 0.0
	## where it is held, in the world
	var pos := Vector3.ZERO
	var rot := Quaternion.IDENTITY
	## where the step it is taking began, and how far through it (0..1; -1 when not stepping)
	var from_pos := Vector3.ZERO
	var from_rot := Quaternion.IDENTITY
	var t := -1.0
	## where it comes down: the clips' place for it, fixed once it starts down so that a body still
	## turning does not drag it along the ground as it lands
	var to := Transform3D()
	var aimed := false
	## where it was shown last frame, in the world
	var shown := Transform3D()


var _sk: Skeleton3D
var _hips := -1
var _feet: Array[Foot] = []
var _active := false
var _weight := 0.0            ## 1 when the feet are held, easing to 0 as they go back to the clips
var _since := 0.0             ## seconds since the feet were planted
var _unsettled := true        ## moved, played a one-shot or left the ground since last planted
var _last_y := NAN
var _last_yaw := NAN
var _last_at := Vector2(NAN, NAN)
## steps taken since the feet were last planted, and the drop (m) given the hips this frame
var steps := 0
var drop := 0.0
var _offsets: Array[float] = [0.0, 0.0]


## A planter for `sk`, or null when the skeleton has no legs to plant.
static func make(sk: Skeleton3D) -> FootPlanter:
	if sk == null:
		return null
	var p := FootPlanter.new()
	p._sk = sk
	p._hips = sk.find_bone("Hips")
	if p._hips < 0:
		return null
	for side in ["L", "R"]:
		var f := Foot.new()
		f.upper = sk.find_bone("UpperLeg." + side)
		f.lower = sk.find_bone("LowerLeg." + side)
		f.bone = sk.find_bone("Foot." + side)
		if f.upper < 0 or f.lower < 0 or f.bone < 0:
			return null
		var a := sk.get_bone_global_rest(f.upper).origin
		var b := sk.get_bone_global_rest(f.lower).origin
		var c := sk.get_bone_global_rest(f.bone).origin
		f.thigh = a.distance_to(b)
		f.shin = b.distance_to(c)
		f.toe = sk.find_bone("Toe." + side)
		var rest := sk.get_bone_global_rest(f.bone)
		f.heel = rest.affine_inverse() * Vector3(rest.origin.x, 0.0, rest.origin.z - HEEL_BACK)
		if f.toe >= 0:
			f.ball = rest.affine_inverse() * sk.get_bone_global_rest(f.toe).origin
			f.ball_height = sk.get_bone_global_rest(f.toe).origin.y
		p._feet.append(f)
	return p


## True while the feet are held (or being handed back to the clips).
func is_planted() -> bool:
	return _active


## How far (m, along the ground) each foot was shown last frame from where the clips put it.
func offsets() -> Array[float]:
	return _offsets.duplicate()


## How many feet the pose now in the skeleton has on the ground: a heel or a ball down.
func feet_down() -> int:
	var n := 0
	for f in _feet:
		var pose := _sk.get_bone_global_pose(f.bone)
		if _sole_height(f, pose.origin, pose.basis.get_rotation_quaternion()) < DOWN_WITHIN:
			n += 1
	return n


## How high (m, skeleton space) the lower of the heel and the ball of `f` is, the foot put at `pos`
## turned `rot` (skeleton space), over the height each stands at.
func _sole_height(f: Foot, pos: Vector3, rot: Quaternion) -> float:
	var b := Basis(rot)
	var h := (pos + b * f.heel).y
	if f.toe >= 0:
		h = minf(h, (pos + b * f.ball).y - f.ball_height)
	return h


## True while a foot is lifted in a step.
func is_stepping() -> bool:
	for f in _feet:
		if f.t >= 0.0:
			return true
	return false


## The feet go back to the clips at once, and are planted again when the body next stands.
func release() -> void:
	_let_go()
	_unsettled = true


## One frame, after the clips have posed the body. `ground_speed` is the body's speed over the
## ground (m/s); `busy` says a one-shot (or anything else that moves the feet itself) has it;
## `hold_still` keeps the feet where they are without starting a step (a turn on the spot coming
## in over them, which takes them from here where they stand).
func update(delta: float, ground_speed: float, busy: bool, hold_still := false) -> void:
	var xf := _sk.global_transform
	var rise := 0.0
	if not is_nan(_last_y) and delta > 0.0:
		rise = (xf.origin.y - _last_y) / delta
	_last_y = xf.origin.y
	var yaw := xf.basis.get_euler().y
	var turned := 0.0 if is_nan(_last_yaw) else absf(wrapf(yaw - _last_yaw, -PI, PI))
	_last_yaw = yaw
	var at := Vector2(xf.origin.x, xf.origin.z)
	var carried := not is_nan(_last_at.x) and at.distance_to(_last_at) > CARRIED_FROM
	_last_at = at
	drop = 0.0
	if absf(rise) > AIRBORNE_FROM or turned > SNAP_TURN:
		release()
		return
	var standing := ground_speed < STANDS_BELOW and not busy
	if not standing:
		_unsettled = true
		if not _active:
			return
		_weight = move_toward(_weight, 0.0, delta / RELEASE_S)
		if _weight <= 0.0:
			_let_go()
			return
	var anim := _animated(xf)
	if standing:
		if not _active or _weight < 1.0:
			if not _active and not _unsettled:
				return
			_plant(anim)
		elif carried or _lost(anim):
			_let_go()
			_plant(anim)
		_since += delta
		if not hold_still or is_stepping():
			_step(delta, anim)
	_pose(xf, anim)


func _let_go() -> void:
	_active = false
	_weight = 0.0
	_offsets.fill(0.0)
	for f in _feet:
		f.t = -1.0


## Holds each foot where it is shown now: where the clips put it, or where this last showed it
## when the feet were still being handed back. A foot just off the ground is set down on it, and
## so is the lower of two feet caught in the air when it is no higher than SET_DOWN_FROM.
func _plant(anim: Array[Transform3D]) -> void:
	var xf := _sk.global_transform
	var inv := xf.affine_inverse()
	var body := xf.basis.get_rotation_quaternion().inverse()
	var heights: Array[float] = []
	for i in _feet.size():
		var f := _feet[i]
		var at: Transform3D = f.shown if _active else anim[i]
		f.pos = at.origin
		f.rot = at.basis.get_rotation_quaternion()
		heights.append(_sole_height(f, inv * f.pos, body * f.rot))
		f.t = -1.0
	var lowest := 0
	for i in _feet.size():
		if heights[i] < heights[lowest]:
			lowest = i
	for i in _feet.size():
		var h := heights[i]
		if h > 0.0 and (h < DOWN_WITHIN or (i == lowest and h < SET_DOWN_FROM)):
			_feet[i].pos -= xf.basis.y * h
	_active = true
	_weight = 1.0
	_since = 0.0
	_unsettled = false
	steps = 0


## Each foot's world transform as the clips have posed it this frame.
func _animated(xf: Transform3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for f in _feet:
		out.append(xf * _sk.get_bone_global_pose(f.bone))
	return out


func _lost(anim: Array[Transform3D]) -> bool:
	for i in _feet.size():
		if _feet[i].pos.distance_to(anim[i].origin) > LOST_FROM:
			return true
	return false


## Moves the steps in progress on and starts the ones most needed. A foot caught in the air comes
## down at once, whatever the other is doing, since it bears no weight: held there while the other
## stepped, a stop from a sprint that ended with both feet off the ground hung one of them in the
## air for a quarter of a second. A foot on the ground waits until the other is down.
func _step(delta: float, anim: Array[Transform3D]) -> void:
	var stepping := false
	for i in _feet.size():
		var f := _feet[i]
		if f.t < 0.0:
			continue
		f.t = minf(f.t + delta / STEP_S, 1.0)
		if f.t >= 1.0 - STEP_LIFTING and not f.aimed:
			f.to = anim[i]
			f.aimed = true
		if f.t >= 1.0:
			f.pos = f.to.origin
			f.rot = f.to.basis.get_rotation_quaternion()
			f.t = -1.0
			steps += 1
		else:
			stepping = true
	var best := -1
	var most := 0.0
	for i in _feet.size():
		if _feet[i].t >= 0.0:
			continue
		var need := _need(i, anim[i])
		if need >= AIRBORNE_NEED:
			_start_step(i)
			stepping = true
		elif need > most:
			best = i
			most = need
	if best >= 0 and not stepping:
		_start_step(best)


func _start_step(i: int) -> void:
	var f := _feet[i]
	f.from_pos = f.pos
	f.from_rot = f.rot
	f.t = 0.0
	f.aimed = false


## How much foot `i` needs a step to where the clips put it (`at`): 0 when it does not, more the
## further off it is, and most when the stop caught it in the air.
func _need(i: int, at: Transform3D) -> float:
	var f := _feet[i]
	var off := at.origin - f.pos
	var flat := Vector2(off.x, off.z).length()
	var turn := f.rot.angle_to(at.basis.get_rotation_quaternion())
	var xf := _sk.global_transform
	var height := _sole_height(f, xf.affine_inverse() * f.pos, xf.basis.get_rotation_quaternion().inverse() * f.rot)
	if height > DOWN_WITHIN and off.length() > 0.01:
		return AIRBORNE_NEED + flat
	var settling := _since < SETTLE_S
	if flat > (STEP_FROM if settling else REPLANT_FROM) or turn > (TURN_FROM if settling else RETURN_FROM):
		return flat + turn * 0.1
	return 0.0


## Where foot `i` is held this frame, in the world: where it stands, or on its way through a step,
## lifted clear of the ground before it travels and set down straight after.
func _held(i: int, at: Transform3D) -> Transform3D:
	var f := _feet[i]
	if f.t < 0.0:
		return Transform3D(Basis(f.rot), f.pos)
	var dest := f.to if f.aimed else at
	var s := smoothstep(STEP_LIFTING, 1.0 - STEP_LIFTING, f.t)
	var p := f.from_pos.lerp(dest.origin, s) + Vector3.UP * (STEP_LIFT * sin(PI * f.t))
	var q := f.from_rot.slerp(dest.basis.get_rotation_quaternion(), s)
	return Transform3D(Basis(q), p)


## Poses the hips and legs so each foot is where it is held.
func _pose(xf: Transform3D, anim: Array[Transform3D]) -> void:
	var inv := xf.affine_inverse()
	var body := xf.basis.get_rotation_quaternion().inverse()
	var targets: Array[Vector3] = []
	var turns: Array[Quaternion] = []
	var off_clip := false
	for i in _feet.size():
		var want := _held(i, anim[i])
		if _weight < 1.0:
			want = anim[i].interpolate_with(want, _weight)
		_offsets[i] = Vector2(want.origin.x - anim[i].origin.x, want.origin.z - anim[i].origin.z).length()
		if want.origin.distance_to(anim[i].origin) > 0.0005 \
				or want.basis.get_rotation_quaternion().angle_to(anim[i].basis.get_rotation_quaternion()) > 0.004:
			off_clip = true
		targets.append(inv * want.origin)
		turns.append(body * want.basis.get_rotation_quaternion())
	if not off_clip:
		# the clips already have each foot where it is held: nothing to write
		for i in _feet.size():
			_feet[i].shown = anim[i]
		return
	drop = _drop_for(targets)
	if drop > 0.0:
		var down := Vector3(0.0, -drop, 0.0)
		var parent := _sk.get_bone_parent(_hips)
		if parent >= 0:
			down = _sk.get_bone_global_pose(parent).basis.inverse() * down
		_sk.set_bone_pose_position(_hips, _sk.get_bone_pose_position(_hips) + down)
	for i in _feet.size():
		_reach(_feet[i], targets[i], turns[i])
		_feet[i].shown = xf * _sk.get_bone_global_pose(_feet[i].bone)


## How far (m) the hips have to come down for both legs to reach their feet: none while each leg
## need straighten no further than STRAIGHT of its length (or than the clip has it).
func _drop_for(targets: Array[Vector3]) -> float:
	var most := 0.0
	for i in _feet.size():
		var f := _feet[i]
		var hip := _sk.get_bone_global_pose(f.upper).origin
		var ankle := _sk.get_bone_global_pose(f.bone).origin
		var length := f.thigh + f.shin
		var reach := clampf(maxf(hip.distance_to(ankle), STRAIGHT * length), 0.0, 0.999 * length)
		var t := targets[i]
		var flat := Vector2(t.x - hip.x, t.z - hip.z).length_squared()
		var need := MOST_DROP
		if flat < reach * reach:
			need = (hip.y - t.y) - sqrt(reach * reach - flat)
		most = maxf(most, clampf(need, 0.0, MOST_DROP))
	return most


## Turns the thigh and shin of `f` so its ankle comes to `target` (skeleton space), the knee kept
## in the plane the clip bends it in, and gives the foot the turn `turn`.
func _reach(f: Foot, target: Vector3, turn: Quaternion) -> void:
	var hip := _sk.get_bone_global_pose(f.upper).origin
	var knee := _sk.get_bone_global_pose(f.lower).origin
	var to := target - hip
	var dist := to.length()
	if dist < 0.0001:
		return
	var u := to / dist
	var d := clampf(dist, absf(f.thigh - f.shin) + 0.001, (f.thigh + f.shin) * 0.9999)
	# the way the knee points: as the clip bends it, out of the line from hip to foot, and ahead
	# of the body when the clip has the leg (all but) straight
	var bend := (knee - hip) - u * (knee - hip).dot(u)
	# the rig faces +Z (its toes point that way)
	var ahead := Vector3(0.0, 0.0, 1.0)
	ahead = ahead - u * ahead.dot(u)
	if ahead.length() > 0.0001:
		bend += ahead.normalized() * maxf(0.0, 0.01 - bend.length())
	if bend.length() < 0.000001:
		return
	bend = bend.normalized()
	var cos_a := clampf((f.thigh * f.thigh + d * d - f.shin * f.shin) / (2.0 * f.thigh * d), -1.0, 1.0)
	var new_knee := hip + u * (f.thigh * cos_a) + bend * (f.thigh * sqrt(1.0 - cos_a * cos_a))
	_turn_bone(f.upper, knee - hip, new_knee - hip)
	var knee_now := _sk.get_bone_global_pose(f.lower).origin
	var ankle_now := _sk.get_bone_global_pose(f.bone).origin
	_turn_bone(f.lower, ankle_now - knee_now, target - knee_now)
	_set_global_rotation(f.bone, turn)


## Turns `bone` (in the skeleton's space) by the shortest arc that takes `from` onto `to`.
func _turn_bone(bone: int, from: Vector3, to: Vector3) -> void:
	if from.length() < 0.000001 or to.length() < 0.000001:
		return
	var arc := Quaternion(from.normalized(), to.normalized())
	var g := _sk.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	_set_global_rotation(bone, arc * g)


## Sets `bone`'s rotation so its turn in the skeleton's space is `q`.
func _set_global_rotation(bone: int, q: Quaternion) -> void:
	var parent := _sk.get_bone_parent(bone)
	var p := Quaternion.IDENTITY
	if parent >= 0:
		p = _sk.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	_sk.set_bone_pose_rotation(bone, (p.inverse() * q).normalized())
