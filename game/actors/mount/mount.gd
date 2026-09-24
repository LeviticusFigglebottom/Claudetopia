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

signal mounted(by: Node3D)
signal dismounted(by: Node3D)
signal refused(reason: String)

enum Mode { STAND, RIDDEN, COMING, BOLT }

const LAYER_INTERACT := 1 << 4
## What the horse stands in and runs into: the world, the terrain, people and foes. Not the player's
## own body (layer 2): its rider sits on it, and a player on foot walks round it by its own mask.
const BODY_MASK := Actor.LAYER_WORLD | Actor.LAYER_ENEMY | Actor.LAYER_NPC | Actor.LAYER_TERRAIN
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
## The steepest ground each gait takes, degrees, up or down; above WALL_DEG the horse refuses.
const SLOPE_CAP := {"Gallop": 15.0, "Canter": 22.0, "Trot": 28.0, "Walk": 36.0}
const WALL_DEG := 36.0
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
## A called horse stops this far from whoever called it, and gives up after STUCK_S of no headway.
const ARRIVE_M := 3.2
const STUCK_S := 8.0
const BOLT_M := 30.0
const REAR_PUSH_S := 0.6
const REAR_EVERY_S := 3.0

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
var _pull_up := false
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


func _ready() -> void:
	add_to_group("mounts")
	# the horse moves before anybody's frame reads its saddle: its rider (Player, priority 0) is
	# set on the seat after the horse has gone forward, not a frame behind it
	process_physics_priority = -10
	collision_layer = Actor.LAYER_NPC
	collision_mask = BODY_MASK
	floor_max_angle = deg_to_rad(44.0)
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
	pivot.add_child(model)
	# what the Interactor's ray finds: the horse's side, head to tail
	var reach := Area3D.new()
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
	_call_to = null
	_bolt_to = Vector3.INF
	model.grazing = false
	mounted.emit(who)


func drop_rider() -> void:
	var who := rider
	rider = null
	mode = Mode.STAND
	_wish = Vector3.ZERO
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
	reset_physics_interpolation()


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
	var slope := absf(slope_ahead())
	while i > 0 and slope > float(SLOPE_CAP[order[i]]):
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


## The rise of the ground from the hind hooves to the front ones along the way the horse faces,
## in degrees (+ uphill).
func slope_ahead() -> float:
	var f := forward()
	var a := _ground(global_position + f * HALF_BASE)
	var b := _ground(global_position - f * HALF_BASE)
	if a == -INF or b == -INF:
		return 0.0
	var s := rad_to_deg(atan2(a - b, 2.0 * HALF_BASE))
	return s if speed >= 0.0 else -s


func water_depth(at := Vector3.INF) -> float:
	var t: Object = World.terrain()
	if t == null or not t.has_method("water_depth_at"):
		return 0.0
	var p := global_position + forward() * HALF_BASE if at == Vector3.INF else at
	return float(t.call("water_depth_at", p.x, p.z))


## Why the horse will not go on ("" when it will): too steep, or too deep, just ahead.
func _refusal() -> String:
	var f := forward() * (1.0 if speed >= -0.1 else -1.0)
	var t: Object = World.terrain()
	if t == null:
		return ""
	var ahead := global_position + f * (HALF_BASE + 0.8)
	var a := _ground(ahead)
	var b := _ground(global_position)
	if a != -INF and b != -INF and rad_to_deg(atan2(absf(a - b), HALF_BASE + 0.8)) > WALL_DEG:
		return "slope"
	if t.has_method("water_depth_at") and float(t.call("water_depth_at", ahead.x, ahead.z)) > REFUSE_DEPTH:
		return "water"
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
	_pitch = lerpf(_pitch, want, 1.0 - exp(-8.0 * delta))
	rotation = Vector3(0.0, heading, 0.0)
	tilt.rotation = Vector3(_pitch, 0.0, 0.0)
	# the pitch is about the middle of the body, which stands on the ground under it
	if model != null:
		model.set_motion(speed, _turning, gait)


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
