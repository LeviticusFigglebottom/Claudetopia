class_name Mount
extends CharacterBody3D
## A horse: its body on the ground, its gaits, and what it does when nobody is on it
## (DECISIONS 2026-09-24, "A starter horse").
##
## Ridden, it takes the Rider's controls (`drive`): a way to go (camera-relative, as the player's
## own walking is), and the gait asked for. It gets there with weight: each gait is reached through
## the ones below it, it turns itself at a rate that falls with speed, and the ground caps what it
## will do -- a slope too steep for the gait, water too deep. Nothing ridden, it stands (and grazes
## now and then), comes when whistled for (`call_to`), or bolts from a fall (`bolt`).
##
## It is not cell data: the Stable owns it, keeps it where it was left and sleeps it when the
## player is far (`sleep`), and saves it (`to_save`).
##
## It jumps when asked (`ask_jump`, the rider's jump key): a hop standing, a leap at a trot, a long
## jump at a canter or a gallop, over what the flight it plans clears. It times its own stride to
## an obstacle ahead, and refuses one it cannot clear or land beyond (triage 59).

signal mounted(by: Node3D)
signal dismounted(by: Node3D)
signal refused(reason: String)

enum Mode { STAND, RIDDEN, COMING, BOLT }

const LAYER_INTERACT := 1 << 4
## What the horse stands in and runs into: the world, the terrain, people and foes. Not the player's
## own body (layer 2): its rider sits on it, and a player on foot walks round it by its own mask.
## The streamed ring's trunks, walls, hedges and fences (the scatter layer) too, as DECISIONS says:
## a fence stops it, unless it is jumped.
const BODY_MASK := Actor.LAYER_WORLD | Actor.LAYER_ENEMY | Actor.LAYER_NPC | Actor.LAYER_TERRAIN | Actor.LAYER_SCATTER
## In the air the body meets only the ground: what it flies over, its plan has cleared already.
const AIR_MASK := Actor.LAYER_TERRAIN
## What a jump must clear, and land clear of.
const SOLID_MASK := Actor.LAYER_WORLD | Actor.LAYER_ENEMY | Actor.LAYER_NPC | Actor.LAYER_SCATTER
const GROUND_SKIN := 0.15
## Ground speeds of the gaits, m/s, unless its content def says otherwise.
const SPEEDS := {"Walk": 1.8, "Trot": 3.8, "Canter": 7.0, "Gallop": 11.5}
const BACK_SPEED := 1.0
## The gait's clip is picked by the speed the body is really going, with this much hysteresis.
const GAIT_EDGES := {"Walk": 2.7, "Trot": 5.3, "Canter": 9.2}
const GAIT_HYST := 0.35
## Getting up to speed (m/s²), per gait being made for: about 0.6 s a gait.
const ACCEL := {"Walk": 2.4, "Trot": 3.4, "Canter": 5.2, "Gallop": 7.0}
## Easing off when nothing is asked (a gait at a time) and pulling up hard (the sliding Stop).
const EASE_OFF := 3.6
const PULL_UP := 7.0
const STOP_CLIP_FROM := 5.0
## Turn rate (deg/s) against ground speed (m/s): 200 standing (the turns on the spot), 45 at a gallop.
const TURN_CURVE := [[0.0, 200.0], [1.8, 120.0], [7.0, 75.0], [11.5, 45.0]]
## The steepest ground each gait takes uphill, degrees; above WALL_DEG the horse refuses.
const SLOPE_CAP := {"Gallop": 15.0, "Canter": 22.0, "Trot": 28.0, "Walk": 36.0}
const WALL_DEG := 36.0
## Downhill a horse keeps its gait further (triage 58: it slowed on any fall at all): the steepest
## fall each gait is taken down, and past DROP_DEG it will not go on.
const DOWN_CAP := {"Gallop": 22.0, "Canter": 28.0, "Trot": 33.0, "Walk": 40.0}
const DROP_DEG := 40.0
## Water: slowed to a trot past TROT_DEPTH, a walk past WALK_DEPTH, refused past REFUSE_DEPTH (m).
const TROT_DEPTH := 0.5
const WALK_DEPTH := 0.8
const REFUSE_DEPTH := 1.2
## Stamina: a gallop spends GALLOP_COST a second; it refills at REGEN a second from REGEN_DELAY
## after; spent, the horse will not gallop until it is back to RECOVER of its full.
const GALLOP_COST := 9.0
const REGEN := 14.0
const REGEN_DELAY := 1.0
const RECOVER := 0.3
## Half the length between the front and hind hooves, m: where the ground under each is read.
const HALF_BASE := 0.9
## The most the model is let down under the body onto a steep hill (m; see `_pose`).
const MAX_SINK := 0.5
## A called horse stops this far from whoever called it, and gives up after STUCK_S of no headway.
const ARRIVE_M := 3.2
const STUCK_S := 8.0
const BOLT_M := 30.0
const REAR_PUSH_S := 0.6
const REAR_EVERY_S := 3.0
## Jumping. How high the body rises at the top of the leap (m) by the gait it is going at ("" is a
## standing hop), under JUMP_G (m/s², stronger than the world's so a leap is quick, not floaty).
const JUMP_RISE := {"": 0.4, "Walk": 0.5, "Trot": 0.85, "Canter": 1.3, "Gallop": 1.45}
const JUMP_G := 14.0
## Stamina a leap costs (a hop, a leap at a walk, a fraction of it); a horse with less refuses.
const JUMP_COST := 12.0
const HOP_COST := 5.0
## In the air the legs are folded under: the body's lowest point is TUCK over its origin. Over the
## scatter (a hedge's twigs, a rail's top) the belly may brush BRUSH into it.
const TUCK := 0.5
const BRUSH := 0.2
## The part of the body that has to clear an obstacle (the belly between the folded legs; the head
## and the quarters go over in an arc of their own), and the whole body where it lands.
const BELLY := Vector3(0.84, 1.75 - TUCK, 1.4)
const LANDING := Vector3(0.84, 1.5, 2.0)
## What is stepped over rather than jumped (ScatterSolids.MIN_HEIGHT_M).
const STEP_OVER := 0.45
## Asked early, the horse carries on to the stride that puts the top of the leap over what is ahead,
## for up to this long; asked with nothing ahead, it goes at once.
const JUMP_WAIT_S := 1.2
## The farthest fall a leap is taken down (m), and the speed kept through the landing.
const MAX_DROP := 4.0
const LAND_KEEP := 0.94
## A landing's folded forelegs and pitched body ease back over this long (s).
const LAND_S := 0.3

@export var mount_id := "core:mount/wardens_cob"

var def: Dictionary = {}
var display_name := "the horse"
var mode := Mode.STAND
var speed := 0.0           # forward ground speed, m/s
var heading := 0.0         # yaw of the horse's forward (-Z)
var gait := ""             # the gait being shown: Walk, Trot, Canter, Gallop, or ""
var stamina := 100.0
var max_stamina := 100.0
var spent := false
var rider: Node3D = null
var model: HorseModel = null
var tilt: Node3D = null
## What is capping the horse this frame ("" when nothing): "slope", "water", "tired".
var held_back := ""
var sleeping := false

var speeds := SPEEDS.duplicate()
var _wish := Vector3.ZERO        # where the rider wants to go (flat, unit or zero)
var _want_gait := "Canter"
var _since_gallop := 10.0
var _pitch := 0.0
var _call_to: Node3D = null
var _call_t := 0.0
var _last_progress := Vector3.INF
var _stuck := 0.0
var _bolt_to := Vector3.INF
var _refuse_push := 0.0
var _last_rear := -100.0
var _graze_t := 0.0
var _clock := 0.0
## A jump asked for and not yet taken off (the clock it was asked at), and the leap in the air:
## {"v0": take-off climb m/s, "t": s in the air}. Empty on the ground.
var _jump_asked := -1.0
var _leap: Dictionary = {}
var _landed_at := -100.0
var _leap_checked := false
## After a refused jump at speed: pulling up hard for this much longer (s).
var _balk := 0.0


func _ready() -> void:
	add_to_group("mounts")
	# the horse moves before anybody's frame reads its saddle: its rider (Player, priority 0) is
	# set on the seat after the horse has gone forward, not a frame behind it
	process_physics_priority = -10
	collision_layer = Actor.LAYER_NPC
	collision_mask = BODY_MASK
	# ground steeper than the horse will take is a wall to its body too, not only to its brain
	floor_max_angle = deg_to_rad(WALL_DEG + 2.0)
	floor_snap_length = 0.6
	floor_constant_speed = true
	_load_def()
	_build()
	heading = rotation.y
	rotation = Vector3.ZERO


func _load_def() -> void:
	def = ContentDB.get_or_empty(mount_id) if ContentDB != null else {}
	display_name = str(def.get("name", display_name))
	var g: Dictionary = def.get("gaits", {})
	for k in g:
		var key := str(k).capitalize()
		if speeds.has(key):
			speeds[key] = float(g[k])
	max_stamina = float(def.get("stamina", 100.0))
	stamina = max_stamina


func _build() -> void:
	# two capsules, fore and hind, standing on the ground: a single upright capsule let the head
	# and the quarters through walls, and one lying down caught on every step of the ground
	for z in [-0.55, 0.5]:
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.42
		cap.height = 1.75
		cs.shape = cap
		cs.position = Vector3(0.0, 0.875, z)
		add_child(cs)
	tilt = Node3D.new()
	tilt.name = "Tilt"
	add_child(tilt)
	var pivot := Node3D.new()
	pivot.name = "Model"
	pivot.rotation.y = PI      # CONTRACTS §1: the model's +Z to the body's -Z
	tilt.add_child(pivot)
	model = HorseModel.new()
	model.name = "Horse"
	# kin of the cob (a start town's horse): the same forge body, at its own size and in its own
	# coat and cloth (the def's `look`)
	var look: Dictionary = def.get("look", {})
	if not look.is_empty():
		pivot.scale = Vector3.ONE * float(look.get("scale", 1.0))
		model.coat_tint = Color(str(look.get("coat", "#ffffff")))
		model.cloth_tint = Color(str(look.get("cloth", "#ffffff")))
	pivot.add_child(model)
	# what the Interactor's ray finds: the horse's side, head to tail
	var reach := Area3D.new()
	_reach = reach
	reach.name = "Reach"
	reach.collision_layer = LAYER_INTERACT
	reach.collision_mask = 0
	var rs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 1.5, 2.5)
	rs.shape = box
	rs.position = Vector3(0.0, 1.2, -0.1)
	reach.add_child(rs)
	add_child(reach)


# --- being interacted with ------------------------------------------------------------------------

## Its mount id, so a lesson's `against` (the style starts' "get up on Hollin") names this horse.
func content_id() -> String:
	return mount_id


func prompt_text() -> String:
	if mode == Mode.RIDDEN:
		return ""
	return "Ride %s" % display_name


func interact(actor: Node) -> void:
	var r := Rider.of(actor)
	if r != null and mode != Mode.RIDDEN:
		r.mount(self)


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func is_ridden() -> bool:
	return mode == Mode.RIDDEN and rider != null


# --- what the rider asks ------------------------------------------------------------------------

## The rider's hands, each physics frame: `wish` a flat direction in the world (zero for none),
## `gait_wanted` one of Walk/Trot/Canter/Gallop.
func drive(wish: Vector3, gait_wanted: String) -> void:
	_wish = Vector3(wish.x, 0.0, wish.z)
	if _wish.length() > 1.0:
		_wish = _wish.normalized()
	_want_gait = gait_wanted if speeds.has(gait_wanted) else "Canter"


func take_rider(who: Node3D) -> void:
	rider = who
	mode = Mode.RIDDEN
	# the rider's own interaction ray starts inside her: offer nothing while ridden, or the
	# prompt shows "[E]" with nothing after it the whole ride
	if _reach != null:
		_reach.collision_layer = 0
	_call_to = null
	_bolt_to = Vector3.INF
	model.grazing = false
	mounted.emit(who)


func drop_rider() -> void:
	var who := rider
	rider = null
	mode = Mode.STAND
	if _reach != null:
		_reach.collision_layer = LAYER_INTERACT
	_wish = Vector3.ZERO
	_jump_asked = -1.0
	dismounted.emit(who)


## Whistled for: come over the ground to `who`.
func call_to(who: Node3D) -> void:
	if mode == Mode.RIDDEN:
		return
	wake()
	_call_to = who
	_call_t = 0.0
	_stuck = 0.0
	_last_progress = global_position
	mode = Mode.COMING
	model.grazing = false


## Frightened (its rider thrown): off at a gallop, away from `from`, then it stands.
func bolt(from: Vector3) -> void:
	if mode == Mode.RIDDEN:
		return
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.1:
		away = -forward()
	_bolt_to = global_position + away.normalized() * BOLT_M
	mode = Mode.BOLT


## Puts the horse at `pos` facing `yaw`, on the ground, stopped.
func place(pos: Vector3, yaw: float) -> void:
	global_position = pos
	heading = yaw
	speed = 0.0
	velocity = Vector3.ZERO
	_end_leap()
	reset_physics_interpolation()


## Down from any leap at once, solid again, nothing asked.
func _end_leap() -> void:
	_leap = {}
	_jump_asked = -1.0
	_balk = 0.0
	collision_mask = BODY_MASK


func sleep() -> void:
	if sleeping or mode == Mode.RIDDEN:
		return
	sleeping = true
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true


func wake() -> void:
	if not sleeping:
		return
	sleeping = false
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = false
	var g := _ground(global_position)
	if g > -INF:
		global_position.y = g
	reset_physics_interpolation()


# --- the body -----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	match mode:
		Mode.RIDDEN: _think_ridden()
		Mode.COMING: _think_coming(delta)
		Mode.BOLT: _think_bolting()
		_: _think_standing(delta)
	if _jump_asked >= 0.0 and _leap.is_empty():
		_think_jump()
	if not _leap.is_empty():
		_fly(delta)
	else:
		_move(delta)
	_update_stamina(delta)
	_pose(delta)


func _think_ridden() -> void:
	pass       # the rider sets _wish and _want_gait through drive()


func _think_standing(delta: float) -> void:
	_wish = Vector3.ZERO
	_graze_t += delta
	# now and then it puts its head down to the grass, and lifts it again
	if _graze_t > 9.0:
		_graze_t = 0.0
		model.grazing = not model.grazing and randf() < 0.6


func _think_coming(delta: float) -> void:
	if _call_to == null or not is_instance_valid(_call_to):
		mode = Mode.STAND
		return
	_call_t += delta
	var to := _call_to.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d <= ARRIVE_M:
		_wish = Vector3.ZERO
		if absf(speed) < 0.3:
			mode = Mode.STAND
			_call_to = null
		return
	_wish = to / d
	_want_gait = "Canter" if d > 25.0 else ("Trot" if d > 9.0 else "Walk")
	# no headway for STUCK_S: the Stable brings it round another way
	if _last_progress == Vector3.INF or global_position.distance_to(_last_progress) > 1.5:
		_last_progress = global_position
		_stuck = 0.0
	else:
		_stuck += delta


func is_stuck() -> bool:
	return mode == Mode.COMING and _stuck >= STUCK_S


func _think_bolting() -> void:
	if _bolt_to == Vector3.INF:
		mode = Mode.STAND
		return
	var to := _bolt_to - global_position
	to.y = 0.0
	if to.length() < 2.0:
		_bolt_to = Vector3.INF
		mode = Mode.STAND
		_wish = Vector3.ZERO
		return
	_wish = to.normalized()
	_want_gait = "Gallop"


## The gait this horse will give now, given what is asked and what the ground allows.
func allowed_gait(asked: String) -> String:
	held_back = ""
	var order: Array[String] = ["Walk", "Trot", "Canter", "Gallop"]
	var i := order.find(asked)
	if i < 0:
		i = 2
	if asked == "Gallop" and spent:
		i = 2
		held_back = "tired"
	var slope := slope_ahead()
	while i > 0 and slope > float(SLOPE_CAP[order[i]]) or i > 0 and -slope > downhill_cap(order[i]):
		i -= 1
		held_back = "slope"
	var depth := water_depth()
	if depth > WALK_DEPTH and i > 0:
		i = 0
		held_back = "water"
	elif depth > TROT_DEPTH and i > 1:
		i = 1
		held_back = "water"
	return order[i]


func _move(delta: float) -> void:
	if model != null and model.is_acting() and model.current_clip() in ["Rear", "Mount", "Dismount"]:
		_wish = Vector3.ZERO if model.current_clip() != "Rear" else _wish
		speed = move_toward(speed, 0.0, PULL_UP * delta)
		_integrate(delta)
		return
	var target := 0.0
	var fwd := forward()
	var want_heading := heading
	var hard := false
	if _wish.length() > 0.15:
		var ahead := _wish.dot(fwd)
		var wish_yaw := atan2(-_wish.x, -_wish.z)
		if ahead < -0.7 and mode == Mode.RIDDEN:
			# asked straight back: pull up, and at a stand rein back
			if absf(speed) > 0.4 and speed > 0.0:
				hard = true
				target = 0.0
			else:
				target = -BACK_SPEED
		else:
			want_heading = wish_yaw
			var g := allowed_gait(_want_gait)
			target = float(speeds[g]) * clampf(_wish.length(), 0.0, 1.0) if mode != Mode.RIDDEN else float(speeds[g])
			# a sharp turn is not made at a canter
			var off := absf(wrapf(wish_yaw - heading, -PI, PI))
			if off > deg_to_rad(70.0):
				target = minf(target, float(speeds["Trot"]))
			if off > deg_to_rad(120.0):
				target = minf(target, float(speeds["Walk"]))
	# a jump refused at speed: pulled up hard
	if _balk > 0.0:
		_balk -= delta
		target = minf(target, 0.0)
		hard = true
	# refusing: a wall of slope, or water too deep, straight ahead
	var refuse := _refusal()
	if not refuse.is_empty() and target > 0.0:
		target = 0.0
		hard = true
		_refuse_push += delta
		if _refuse_push > REAR_PUSH_S and _clock - _last_rear > REAR_EVERY_S and mode == Mode.RIDDEN:
			_last_rear = _clock
			_refuse_push = 0.0
			refused.emit(refuse)
			model.play_action("Rear")
	else:
		_refuse_push = 0.0
	# speed: up a gait at a time, down gently, or hard when pulled up
	if hard and speed > STOP_CLIP_FROM and not model.is_acting():
		model.play_action("Stop")
	var rate: float
	if target > speed:
		# the gait being gone into sets the pace: each gait is reached through the ones below it
		rate = float(ACCEL.get(_gait_for(maxf(speed, 0.0) + 0.5), 4.0))
	elif hard:
		rate = PULL_UP
	else:
		rate = EASE_OFF
	speed = move_toward(speed, target, rate * delta)
	# turning: at a rate that falls with speed
	var turn := deg_to_rad(_turn_rate_deg(absf(speed)))
	var diff := wrapf(want_heading - heading, -PI, PI)
	var step := clampf(diff, -turn * delta, turn * delta)
	heading = wrapf(heading + step, -PI, PI)
	_turning = step / maxf(delta, 1e-4)
	_integrate(delta)


var _turning := 0.0
var _reach: Area3D = null


func _integrate(delta: float) -> void:
	var fwd := forward()
	var v := fwd * speed
	velocity.x = v.x
	velocity.z = v.z
	if not is_on_floor():
		velocity.y -= 9.81 * delta
	move_and_slide()
	# into a wall: the horse stops against it rather than running on the spot
	var real := get_real_velocity()
	var along := Vector3(real.x, 0.0, real.z).dot(fwd)
	if absf(speed) > 0.5 and absf(along) < absf(speed) * 0.5 and get_slide_collision_count() > 0:
		speed = move_toward(speed, along, 12.0 * delta)
	_snap()
	# the gait shown: by the speed the body is really making, with hysteresis
	gait = _gait_for(absf(speed), gait)


## The steepest fall `g` is taken down at, degrees.
static func downhill_cap(g: String) -> float:
	return float(DOWN_CAP.get(g, DROP_DEG))


# --- jumping ------------------------------------------------------------------------------------

## The rider's jump key. Taken off at once, or at the stride that clears what is ahead; refused
## (the `refused` signal: "tired", "too high", "no landing", "drop") when it cannot be made.
func ask_jump() -> void:
	if not _leap.is_empty() or mode != Mode.RIDDEN:
		return
	if model != null and model.is_acting() and model.current_clip() in ["Rear", "Mount", "Dismount"]:
		return
	_jump_asked = _clock
	_leap_checked = false


func is_jumping() -> bool:
	return not _leap.is_empty()


## Where in a leap the body is: "takeoff" (rising hard), "air", "land" (coming down, and the
## moment after), or "" on the ground.
func jump_phase() -> String:
	if _leap.is_empty():
		return "land" if _clock - _landed_at < LAND_S else ""
	var s := velocity.y / maxf(float(_leap["v0"]), 0.1)
	if s > 0.45:
		return "takeoff"
	if s < -0.45:
		return "land"
	return "air"


## -1 at the landing .. 1 at take-off: how the leap is going (0 on the ground).
func leap_amount() -> float:
	if _leap.is_empty():
		return 0.0
	return clampf(velocity.y / maxf(float(_leap["v0"]), 0.1), -1.0, 1.0)


func _jump_cost() -> float:
	return JUMP_COST if speed > float(speeds["Walk"]) + 0.5 else HOP_COST


func _think_jump() -> void:
	if not is_on_floor():
		# a tick off the floor over a bump: taken when it is back on it; off it longer (going over
		# a drop), the ask is let go -- nothing leaps from the air
		if _clock - _jump_asked > 0.25:
			_jump_asked = -1.0
		return
	var cost := _jump_cost()
	if stamina < cost:
		_refuse_jump("tired")
		return
	var rise := float(JUMP_RISE.get(gait if speed > 0.5 else "", JUMP_RISE[""]))
	var v0 := sqrt(2.0 * JUMP_G * rise)
	var v := maxf(speed, 0.0)
	# the stride that puts the top of the leap over the middle of what is ahead
	var mid := _obstacle_ahead(v * (2.0 * v0 / JUMP_G) + 4.0) if v > 1.0 else INF
	if mid != INF and _clock - _jump_asked < JUMP_WAIT_S:
		var lead := mid - v * (v0 / JUMP_G)
		if lead > v * get_physics_process_delta_time() * 1.5 + 0.1:
			# not yet: but a leap that will not go from there is refused now, with room to pull up
			if not _leap_checked:
				_leap_checked = true
				var early := _plan_leap(v, v0, global_position + forward() * lead)
				if not early.is_empty():
					_refuse_jump(early)
			return
	var why := _plan_leap(v, v0)
	if not why.is_empty():
		_refuse_jump(why)
		return
	_jump_asked = -1.0
	stamina -= cost
	_since_gallop = 0.0
	_leap = {"v0": v0, "t": 0.0, "from": global_position}
	velocity.y = v0
	collision_mask = AIR_MASK


func _refuse_jump(why: String) -> void:
	_jump_asked = -1.0
	refused.emit(why)
	if why == "tired":
		return
	# at speed it pulls up short, sliding; slow, it goes up on its hind legs
	if speed > STOP_CLIP_FROM:
		_balk = speed / PULL_UP + 0.2
		if model != null and not model.is_acting():
			model.play_action("Stop")
	elif speed > 0.5:
		_balk = speed / PULL_UP + 0.2
	elif model != null and not model.is_acting() and _clock - _last_rear > 1.0:
		_last_rear = _clock
		model.play_action("Rear")


## The middle of the nearest thing ahead the horse would have to jump (m from its middle, along
## its way), within `reach`; INF when the way is clear. Its far side is where the body is clear of
## it again, up to 3 m on.
func _obstacle_ahead(reach: float) -> float:
	var f := forward()
	var d := HALF_BASE + 0.1
	var first := INF
	var last := INF
	var box := BoxShape3D.new()
	box.size = Vector3(BELLY.x, 1.75 - STEP_OVER, 0.3)
	while d <= minf(reach, 18.0):
		var p := global_position + f * d
		var g := _ground(p)
		if g == -INF:
			g = global_position.y
		var hit := _hits(box, Vector3(p.x, g + STEP_OVER + box.size.y * 0.5, p.z), SOLID_MASK)
		if hit:
			if first == INF:
				first = d
			last = d
		elif first != INF:
			break
		if first != INF and d - first > 3.0:
			break
		d += 0.25
	return INF if first == INF else (first + last) * 0.5


## Whether the leap from here at `v` m/s forward, `v0` up, clears everything on its way and lands
## where a horse can stand: "" when it does, else why not.
func _plan_leap(v: float, v0: float, from := Vector3.INF) -> String:
	var f := forward()
	var p0 := global_position if from == Vector3.INF else from
	if from != Vector3.INF:
		var g0 := _ground(p0)
		if g0 != -INF:
			p0.y = g0
	var belly := BoxShape3D.new()
	belly.size = BELLY
	var brushed := BoxShape3D.new()
	brushed.size = Vector3(BELLY.x, BELLY.y - BRUSH, BELLY.z)
	var dt := 0.04
	var t := dt
	var land := Vector3.INF
	while t < 3.0:
		var p := p0 + f * (v * t)
		p.y = p0.y + v0 * t - 0.5 * JUMP_G * t * t
		var g := _ground(p)
		if g != -INF and p.y <= g and t > 0.1:
			land = Vector3(p.x, g, p.z)
			break
		# rising, what is hit is too high to clear; coming down, there is nowhere to come down
		var why := "too high" if t < v0 / JUMP_G else "no landing"
		var low := p.y + TUCK
		if _hits(belly, Vector3(p.x, low + BELLY.y * 0.5, p.z), SOLID_MASK & ~Actor.LAYER_SCATTER):
			return why
		if _hits(brushed, Vector3(p.x, low + BRUSH + brushed.size.y * 0.5, p.z), Actor.LAYER_SCATTER):
			return why
		t += dt
	if land == Vector3.INF or p0.y - land.y > MAX_DROP:
		return "drop"
	var whole := BoxShape3D.new()
	whole.size = LANDING
	if _hits(whole, land + Vector3(0.0, 0.25 + LANDING.y * 0.5, 0.0), SOLID_MASK):
		return "no landing"
	var a := _ground(land + f * HALF_BASE)
	var b := _ground(land - f * HALF_BASE)
	if a != -INF and b != -INF:
		var s := rad_to_deg(atan2(a - b, 2.0 * HALF_BASE))
		if s > WALL_DEG or -s > DROP_DEG:
			return "no landing"
	if water_depth(land) > REFUSE_DEPTH:
		return "no landing"
	return ""


## Whether `shape`, turned the way the horse faces and centred at `at`, overlaps anything on `mask`
## but the horse itself.
func _hits(shape: Shape3D, at: Vector3, mask: int) -> bool:
	if not is_inside_tree():
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(Vector3.UP, heading), at)
	q.collision_mask = mask
	var ex: Array[RID] = [get_rid()]
	q.exclude = ex
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## In the air: on at the speed it left the ground with, the way it faced, under JUMP_G, meeting
## only the ground; down on it, the speed carried on and the body solid again.
func _fly(delta: float) -> void:
	_leap["t"] = float(_leap["t"]) + delta
	var fwd := forward()
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	# half the pull before the move and half after: the flight is the parabola the plan cleared
	velocity.y -= JUMP_G * delta * 0.5
	move_and_slide()
	velocity.y -= JUMP_G * delta * 0.5
	_turning = 0.0
	var g := _ground(global_position)
	var down := is_on_floor() or (g != -INF and global_position.y <= g + 0.02 and velocity.y <= 0.0)
	if down and float(_leap["t"]) > 0.1:
		if g != -INF and global_position.y < g:
			global_position.y = g
		velocity.y = 0.0
		speed *= LAND_KEEP
		_leap = {}
		_landed_at = _clock
		collision_mask = BODY_MASK
	elif float(_leap["t"]) > 4.0:
		# never down (over a hole in the ground): put back on it
		_leap = {}
		collision_mask = BODY_MASK
		if g != -INF:
			global_position.y = g
		velocity = Vector3.ZERO
	gait = _gait_for(absf(speed), gait)


func _gait_for(v: float, current := "") -> String:
	if v < 0.2:
		return ""
	var order: Array[String] = ["Walk", "Trot", "Canter"]
	for g in order:
		var edge := float(GAIT_EDGES[g])
		if current == g:
			edge += GAIT_HYST
		elif order.find(current) > order.find(g) and current != "":
			edge -= GAIT_HYST
		if v < edge:
			return g
	return "Gallop"


func _turn_rate_deg(v: float) -> float:
	for i in range(1, TURN_CURVE.size()):
		var a: Array = TURN_CURVE[i - 1]
		var b: Array = TURN_CURVE[i]
		if v <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (v - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(TURN_CURVE[-1][1])


func _snap() -> void:
	if is_on_floor():
		return
	var g := _ground(global_position)
	if g == -INF:
		return
	if global_position.y < g or (global_position.y <= g + GROUND_SKIN and velocity.y <= 0.0):
		global_position.y = g
		if velocity.y < 0.0:
			velocity.y = 0.0


func _ground(p: Vector3) -> float:
	var t: Object = World.terrain()
	if t == null or not t.has_method("get_height"):
		return -INF
	return float(t.call("get_height", p.x, p.z))


## Where the model stands (its middle, in the world): the body's origin, let down onto a hill.
func stands_at() -> Vector3:
	return tilt.global_position if tilt != null else global_position


## The rise of the ground from the hind hooves to the front ones along the way the horse faces,
## in degrees (+ uphill). Going, the front of the measure is the ground the next half second
## covers (up to 4 m on): a gait is capped by the hill it is on, not by every hummock of it (a
## 20° hillside read 11° to 34° hoof to hoof, and a canter down it fell to a trot and back).
func slope_ahead() -> float:
	var f := forward() * (1.0 if speed >= 0.0 else -1.0)
	var ahead := HALF_BASE + clampf(absf(speed) * 0.5, 0.0, 4.0)
	var a := _ground(global_position + f * ahead)
	var b := _ground(global_position - f * HALF_BASE)
	if a == -INF or b == -INF:
		return 0.0
	return rad_to_deg(atan2(a - b, ahead + HALF_BASE))


func water_depth(at := Vector3.INF) -> float:
	var t: Object = World.terrain()
	if t == null or not t.has_method("water_depth_at"):
		return 0.0
	var p := global_position + forward() * HALF_BASE if at == Vector3.INF else at
	return float(t.call("water_depth_at", p.x, p.z))


## Why the horse will not go on ("" when it will): ground too steep, or water too deep, within
## the distance it needs to pull up from the speed it is going (and never less than a length).
func _refusal() -> String:
	var dir := 1.0 if speed >= -0.1 else -1.0
	var f := forward() * dir
	var t: Object = World.terrain()
	if t == null:
		return ""
	var reach := HALF_BASE + 0.8 + speed * speed / (2.0 * PULL_UP)
	var step := 0.8
	var prev := _ground(global_position + f * HALF_BASE * 0.5)
	var d := HALF_BASE * 0.5 + step
	while d <= reach + 0.01:
		var p := global_position + f * d
		var g := _ground(p)
		if prev != -INF and g != -INF:
			var rise := rad_to_deg(atan2(g - prev, step))
			if rise > WALL_DEG or -rise > DROP_DEG:
				return "slope"
		if t.has_method("water_depth_at") and float(t.call("water_depth_at", p.x, p.z)) > REFUSE_DEPTH:
			return "water"
		prev = g
		d += step
	return ""


func _update_stamina(delta: float) -> void:
	if gait == "Gallop":
		stamina = maxf(0.0, stamina - GALLOP_COST * delta)
		_since_gallop = 0.0
		if stamina <= 0.0:
			spent = true
	else:
		_since_gallop += delta
		if _since_gallop >= REGEN_DELAY:
			stamina = minf(max_stamina, stamina + REGEN * delta)
	if spent and stamina >= max_stamina * RECOVER:
		spent = false


## The body tilted to the ground under its hooves, and the model told what the legs are doing.
func _pose(delta: float) -> void:
	var f := forward()
	var a := _ground(global_position + f * HALF_BASE)
	var b := _ground(global_position - f * HALF_BASE)
	var want := 0.0
	if a != -INF and b != -INF:
		want = atan2(a - b, 2.0 * HALF_BASE)
	# a leap: the forehand up leaving the ground, level over the top, the nose down coming in
	var leaping := is_jumping()
	var lw := 1.0 if leaping else clampf(1.0 - (_clock - _landed_at) / LAND_S, 0.0, 1.0)
	var s := leap_amount() if leaping else -1.0
	if leaping:
		want = deg_to_rad(16.0) * s
	_pitch = lerpf(_pitch, want, 1.0 - exp(-(14.0 if lw > 0.0 else 8.0) * delta))
	rotation = Vector3(0.0, heading, 0.0)
	tilt.rotation = Vector3(_pitch, 0.0, 0.0)
	# on a steep hill the body rides on its uphill capsule, its middle up to 0.4 m over the ground
	# (half the base times the slope): the model is let down onto the ground under its middle, so
	# the hooves stand on the hill and not in the air over it
	var sink := 0.0
	var gc := _ground(global_position)
	if not leaping and gc != -INF and is_on_floor():
		sink = clampf(gc - global_position.y, -MAX_SINK, 0.0)
	tilt.position.y = lerpf(tilt.position.y, sink, 1.0 - exp(-12.0 * delta))
	# the pitch is about the middle of the body, which stands on the ground under it
	if model != null:
		model.set_motion(speed, _turning, gait)
		model.leap = s
		# in over the first tenth of a second in the air, out over LAND_S on the ground
		model.leap_weight = move_toward(model.leap_weight, lw, delta * 10.0) if leaping else lw


# --- the saddle -----------------------------------------------------------------------------------

## Where the rider's seat is now, in the world: the saddle socket as the clips move it.
func seat_transform() -> Transform3D:
	var s := model.socket("Socket.Saddle") if model != null else null
	if s == null:
		return global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.595, 0.02))
	return s.global_transform


func to_save() -> Dictionary:
	return {"id": mount_id, "name": display_name, "pos": [global_position.x, global_position.y, global_position.z],
			"yaw": heading, "stamina": stamina}


func from_save(d: Dictionary) -> void:
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		place(Vector3(float(p[0]), float(p[1]), float(p[2])), float(d.get("yaw", 0.0)))
	stamina = float(d.get("stamina", max_stamina))
	display_name = str(d.get("name", display_name))
