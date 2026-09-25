class_name Rider
extends Node
## The player in the saddle (DECISIONS 2026-09-24, "A starter horse"). A child of the Player.
##
## While riding, the Player hands its physics frame here (the hook in `Player._physics_process`):
## the keys become the horse's controls (`Mount.drive`), the body sits on the saddle socket and
## plays the seat, the camera takes its riding profile, and the fighting keys do nothing. Getting
## up and down are short blends from the ground to the seat and back, over the horse's own Mount
## and Dismount clips. A blow that would stagger or floor the rider throws them off.
##
## Out of the saddle it only listens for the whistle (`call_mount`).

signal state_changed(state: String)

const MOUNT_S := 1.3
const DISMOUNT_S := 1.0
## With the rig's own clips (player feel's, made on the saddle with their root at the seat): the walk
## to the near side before Mount_Horse starts, and the gait from which the seat is Ride_Gallop.
const TO_THE_SIDE_S := 0.3
const GALLOP_SEAT_FROM := ["Gallop"]
## Landed from Dismount_Horse on the near side, the body steps out to the landing spot in this long.
const STEP_OFF_S := 0.35
## Where a body stands to get up: on the horse's near (left) side, this far out from its middle.
const NEAR_SIDE := 0.55
## The body's hips sit this far above the saddle socket (the seat's lowest point).
const HIPS_ABOVE_SEAT := 0.09
## Dismounting at more than this ground speed first pulls the horse up.
const STILL_ENOUGH := 1.0
## The camera in the saddle: a longer arm, the pivot higher, a wider view at speed.
const CAMERA_ARM := 1.6
const CAMERA_HEIGHT := 0.25
const CAMERA_FOV_GALLOP := 9.0
const RECENTRE_AFTER_S := 1.5
const RECENTRE_FROM := 3.0
const FIGHT_ACTIONS: Array[String] = ["attack_light", "attack_heavy", "block", "cast", "dodge", "quick_1", "quick_2", "quick_3", "quick_4"]

var player: Node3D = null
var horse: Mount = null
## "", "mounting", "riding", "dismounting"
var state := ""
var _t := 0.0
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _layer := 0
var _mask := 0
var _after_dismount: Node = null
var _thrown := false
var _cam_idle := 0.0
var _cam_yaw_set := INF
var _said_no_fighting := false
var _seat_clip := ""
var _seat: RideSeat = null
var _prev_keys: Dictionary = {}
## Getting up or down on the rig's own clip (Mount_Horse, Dismount_Horse), and how long it runs.
var _clip_way := ""
var _clip_s := 0.0


static func of(actor: Node) -> Rider:
	if actor == null:
		return null
	return actor.get_node_or_null("Rider") as Rider


func _ready() -> void:
	player = get_parent() as Node3D
	if player != null:
		for sig in ["staggered", "knocked_down"]:
			if player.has_signal(sig):
				player.connect(sig, _on_thrown)
		if player.has_signal("died"):
			player.connect("died", func(_k: Node) -> void: _drop_now())


## Asked by Player._physics_process each frame: while this is true the Player does nothing else.
func riding() -> bool:
	return state != ""


func is_seated() -> bool:
	return state == "riding"


# --- getting up and down --------------------------------------------------------------------------

func mount(h: Mount) -> bool:
	if h == null or state != "" or h.is_ridden() or player == null:
		return false
	if player.has_method("is_dead") and bool(player.call("is_dead")):
		return false
	horse = h
	h.take_rider(player)
	_from = player.global_transform
	_t = 0.0
	_set_state("mounting")
	_hold_body(true)
	_clip_way = "Mount_Horse" if _has_clip("Mount_Horse") else ""
	_clip_s = 0.0
	if _clip_way.is_empty():
		_play_seat()
	h.model.play_action("Mount")
	return true


## Down on the near side, or whichever side is clear. At speed, the first press pulls up.
func dismount(then_interact: Node = null) -> bool:
	if state != "riding" or horse == null:
		return false
	if absf(horse.speed) > STILL_ENOUGH:
		horse.drive(Vector3.ZERO, "Walk")
		return false
	_after_dismount = then_interact
	_from = player.global_transform
	_to = Transform3D(Basis(Vector3.UP, horse.heading), landing_spot())
	_t = 0.0
	# the rig's Dismount_Horse lands on the near side: played when that is where there is room
	_clip_way = ""
	var near := _near_side_spot()
	# landing_spot's near side is 1.05 m out; the clip lands at NEAR_SIDE, then steps out to it
	if _has_clip("Dismount_Horse") and near.distance_to(_to.origin) < 0.7:
		_clip_way = "Dismount_Horse"
		_clip_s = _clip_length("Dismount_Horse", DISMOUNT_S)
		var anim: Node = player.get("anim")
		if anim != null:
			anim.call("play_intent", "Dismount_Horse")
	_set_state("dismounting")
	horse.model.play_action("Dismount")
	return true


## Where a rider gets down: the near (left) side, then the off side, then behind, whichever has
## room for a body; the near side when none has.
func landing_spot() -> Vector3:
	var basis := Basis(Vector3.UP, horse.heading)
	var tries: Array[Vector3] = [Vector3(-1.05, 0.0, -0.1), Vector3(1.05, 0.0, -0.1), Vector3(0.0, 0.0, 2.1)]
	for local in tries:
		var p := horse.global_position + basis * local
		var g := _ground(p)
		if g > -INF:
			p.y = g
		if _room_for_body(p):
			return p
	var q := horse.global_position + basis * tries[0]
	var gq := _ground(q)
	if gq > -INF:
		q.y = gq
	return q


func _room_for_body(p: Vector3) -> bool:
	var space := (player as Node3D).get_world_3d().direct_space_state if player != null and player.is_inside_tree() else null
	if space == null:
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.7
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0.0, 0.95, 0.0))
	q.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_NPC | Actor.LAYER_ENEMY
	var ex: Array[RID] = []
	if horse != null:
		ex.append(horse.get_rid())
	if player is CollisionObject3D:
		ex.append((player as CollisionObject3D).get_rid())
	q.exclude = ex
	return space.intersect_shape(q, 1).is_empty()


func _on_thrown() -> void:
	if state == "":
		return
	_thrown = true
	_drop_now()


## Off at once: a fall, a death, a teleport. The body lands beside the horse; the horse bolts.
func _drop_now() -> void:
	if state == "" or horse == null:
		return
	var from := player.global_position
	var at := landing_spot()
	var h := horse
	_finish_dismount(at)
	if _thrown:
		h.bolt(from)
	_thrown = false


func _finish_dismount(at: Vector3) -> void:
	_clip_way = ""
	_clip_s = 0.0
	var h := horse
	player.global_transform = Transform3D(Basis(Vector3.UP, h.heading if h != null else 0.0), at)
	player.reset_physics_interpolation()
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	_hold_body(false)
	_release_camera()
	_astride(0.0)
	if h != null:
		h.drop_rider()
	horse = null
	_set_state("")
	var anim: Node = player.get("anim")
	if anim != null and anim.has_method("stop"):
		anim.call("stop")
	var next := _after_dismount
	_after_dismount = null
	if next != null and is_instance_valid(next) and next.has_method("interact"):
		next.call("interact", player)


func _set_state(s: String) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)


## In the saddle the body is carried: it collides with nothing, and nothing pushes it.
func _hold_body(held: bool) -> void:
	var body := player as CollisionObject3D
	if body == null:
		return
	if held:
		_layer = body.collision_layer
		_mask = body.collision_mask
		body.collision_layer = 0
		body.collision_mask = 0
	else:
		body.collision_layer = _layer
		body.collision_mask = _mask


func _play_seat() -> void:
	var anim: Node = player.get("anim")
	if anim == null:
		return
	var model: Node = anim.get("model")
	_seat_clip = ""
	if _has_clip("Ride"):
		_seat_clip = _seat_clip_for_gait()
		anim.call("play_intent", _seat_clip)
		return
	# no seat clip yet: the body's standing Idle, legs laid astride and hands on the reins by RideSeat
	if anim.has_method("stop"):
		anim.call("stop")
	if anim.has_method("set_locomotion"):
		anim.call("set_locomotion", Vector2.ZERO, false)
	var sk: Skeleton3D = model.get("skeleton") if model != null else null
	if sk != null:
		_seat = sk.get_node_or_null("RideSeat") as RideSeat
		if _seat == null:
			_seat = RideSeat.new()
			_seat.name = "RideSeat"
			sk.add_child(_seat)


## The seat the horse's gait asks for: two-point out of the saddle at the gallop, else sat down.
func _seat_clip_for_gait() -> String:
	if horse != null and str(horse.gait) in GALLOP_SEAT_FROM and _has_clip("Ride_Gallop"):
		return "Ride_Gallop"
	return "Ride"


func _has_clip(clip: String) -> bool:
	var anim: Node = player.get("anim") if player != null else null
	var model: Node = anim.get("model") if anim != null else null
	return model != null and model.has_method("has_clip") and bool(model.call("has_clip", clip))


func _clip_length(clip: String, fallback: float) -> float:
	var anim: Node = player.get("anim") if player != null else null
	var model: Node = anim.get("model") if anim != null else null
	if model != null and model.has_method("clip_length"):
		var l := float(model.call("clip_length", clip))
		if l > 0.0:
			return l
	return fallback


## Where a body stands on the near side to get up, and lands getting down: on the ground there.
func _near_side_spot() -> Vector3:
	var p := horse.global_position + Basis(Vector3.UP, horse.heading) * Vector3(-NEAR_SIDE, 0.0, -0.05)
	var g := _ground(p)
	if g > -INF:
		p.y = g
	return p


## The saddle's own frame: the rig's riding clips are made with their root here.
func _saddle_frame() -> Transform3D:
	var seat := horse.seat_transform()
	var basis := horse.tilt.global_transform.basis.orthonormalized() if horse.tilt != null else Basis(Vector3.UP, horse.heading)
	return Transform3D(basis, seat.origin)


## How far astride the body sits (RideSeat), 0..1.
func _astride(w: float) -> void:
	if _seat != null and is_instance_valid(_seat):
		_seat.amount = clampf(w, 0.0, 1.0)


# --- each frame -----------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if state == "" and _just("call_mount"):
		var stable := Stable.find(player)
		if stable != null:
			stable.whistle(player)


## The Player's frame while riding (called from Player._physics_process).
func ride_tick(delta: float) -> void:
	if horse == null or not is_instance_valid(horse):
		_set_state("")
		_hold_body(false)
		return
	match state:
		"mounting":
			# the keys held to get up must be let go before they mean anything in the saddle
			for a in ["interact", "jump"] + FIGHT_ACTIONS:
				_just(a)
			_t += delta
			if not _clip_way.is_empty():
				_mount_on_clip()
				if player is CharacterBody3D:
					(player as CharacterBody3D).velocity = Vector3.ZERO
				_camera(delta)
				return
			var w := clampf(_t / MOUNT_S, 0.0, 1.0)
			# to the near side first, then up
			var side := Transform3D(Basis(Vector3.UP, horse.heading),
					horse.global_position + Basis(Vector3.UP, horse.heading) * Vector3(-NEAR_SIDE, 0.0, -0.05))
			var seat := _seat_body_transform()
			if w < 0.3:
				player.global_transform = _from.interpolate_with(side, _ease(w / 0.3))
			else:
				player.global_transform = side.interpolate_with(seat, _ease((w - 0.3) / 0.7))
			_astride(_ease((w - 0.3) / 0.7))
			if w >= 1.0:
				_set_state("riding")
		"riding":
			_ride(delta)
			_astride(1.0)
			if not _seat_clip.is_empty() and state == "riding":
				var want := _seat_clip_for_gait()
				if want != _seat_clip:
					_seat_clip = want
					player.get("anim").call("play_intent", want)
			player.global_transform = _seat_body_transform()
		"dismounting":
			_t += delta
			if not _clip_way.is_empty():
				# the whole way down is the clip's, on the saddle; landed on the near side, the body
				# steps out from the horse's flank to where it has room (STEP_OFF_S)
				if _t < _clip_s:
					player.global_transform = _saddle_frame()
				else:
					var landed := Transform3D(Basis(Vector3.UP, horse.heading), _near_side_spot())
					var w := clampf((_t - _clip_s) / STEP_OFF_S, 0.0, 1.0)
					player.global_transform = landed.interpolate_with(_to, _ease(w))
					var anim: Node = player.get("anim")
					if anim != null and _t - _clip_s < 0.05:
						anim.call("stop")
					if anim != null:
						var away := landed.origin.distance_to(_to.origin) / STEP_OFF_S
						anim.call("set_locomotion", Vector2(-away, 0.0) if w < 1.0 else Vector2.ZERO, false)
					if w >= 1.0:
						_clip_way = ""
						_finish_dismount(_to.origin)
						return
				if player is CharacterBody3D:
					(player as CharacterBody3D).velocity = Vector3.ZERO
				_camera(delta)
				return
			var w := clampf(_t / DISMOUNT_S, 0.0, 1.0)
			var seat := _seat_body_transform()
			player.global_transform = seat.interpolate_with(_to, _ease(w))
			_astride(1.0 - _ease(w / 0.7))
			if w >= 1.0:
				_finish_dismount(_to.origin)
				return
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	_camera(delta)


## Getting up on Mount_Horse: a walk to the near side, and then the clip, the body held on the
## saddle's frame (the clip carries it from the ground up into the seat).
func _mount_on_clip() -> void:
	var side := Transform3D(Basis(Vector3.UP, horse.heading), _near_side_spot())
	if _t < TO_THE_SIDE_S:
		player.global_transform = _from.interpolate_with(side, _ease(_t / TO_THE_SIDE_S))
		return
	var anim: Node = player.get("anim")
	if _clip_s <= 0.0:
		_clip_s = _clip_length("Mount_Horse", MOUNT_S)
		if anim != null:
			anim.call("play_intent", "Mount_Horse")
	player.global_transform = _saddle_frame()
	if _t >= TO_THE_SIDE_S + _clip_s:
		_clip_way = ""
		_clip_s = 0.0
		_play_seat()
		_set_state("riding")


func _ride(_delta: float) -> void:
	# the fighting keys do nothing from the saddle, and say so once
	for a in FIGHT_ACTIONS:
		if _just(a) and not _said_no_fighting:
			_said_no_fighting = true
			EventBus.emit_notify("You can't fight from the saddle. Get down first (%s)." % _key_for("interact"), "info")
	if _just("interact"):
		var interactor: Node = player.get("interactor")
		var target: Node = null
		if interactor != null and bool(interactor.call("has_target")):
			target = interactor.get("target")
			if target == horse:
				target = null
		dismount(target)
		return
	if _just("jump") and absf(horse.speed) < 0.5 and not horse.model.is_acting():
		horse.model.play_action("Rear")
	horse.drive(wish(), wanted_gait())


## Where the keys point, flat and camera-relative, as the player's own walking is (unit or zero).
func wish() -> Vector3:
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var rig: Node = player.get("camera_rig")
	var fwd := Vector3(0.0, 0.0, -1.0)
	var right := Vector3(1.0, 0.0, 0.0)
	if rig != null and rig.has_method("forward_flat"):
		fwd = rig.call("forward_flat")
		right = rig.call("right_flat")
	var w := fwd * -mv.y + right * mv.x
	return w.normalized() * minf(mv.length(), 1.0) if w.length() > 0.01 else Vector3.ZERO


## The gait the keys ask for: sprint gallops, sneak trots, the walk key walks, forward canters. A
## stick walks, trots or canters by how far it is pushed.
func wanted_gait() -> String:
	if Input.is_action_pressed("sprint"):
		return "Gallop"
	if InputMap.has_action("sneak") and Input.is_action_pressed("sneak"):
		return "Trot"
	if Input.is_action_pressed("walk"):
		return "Walk"
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Input.get_connected_joypads().size() > 0 and mv.length() < 0.98:
		if mv.length() < 0.55:
			return "Walk"
		if mv.length() < 0.9:
			return "Trot"
	return "Canter"


## The body's transform in the saddle: the seat socket where the clips have it, turned with the
## horse (its heading and the pitch of the ground), the hips HIPS_ABOVE_SEAT over it.
func _seat_body_transform() -> Transform3D:
	if not _seat_clip.is_empty():
		# the rig's seat clips are made on the saddle: the root at the seat, whatever the hips do
		# (up out of it at the gallop)
		return _saddle_frame()
	var seat := horse.seat_transform()
	var basis := horse.tilt.global_transform.basis.orthonormalized() if horse.tilt != null else Basis(Vector3.UP, horse.heading)
	var hips := _hips_local()
	var origin := seat.origin + basis * (Vector3(0.0, HIPS_ABOVE_SEAT, 0.0) - hips)
	return Transform3D(basis, origin)


## Where the body's hips are in its own frame in the seated clip (so its origin can be put under
## the saddle wherever the clip holds them). Read off the skeleton; a guess without one.
func _hips_local() -> Vector3:
	var anim: Node = player.get("anim")
	var model: Node = anim.get("model") if anim != null else null
	var sk: Skeleton3D = model.get("skeleton") if model != null else null
	if sk != null:
		var b := sk.find_bone("Hips")
		if b >= 0:
			var g := sk.global_transform * sk.get_bone_global_pose(b)
			return player.global_transform.affine_inverse() * g.origin
	return Vector3(0.0, 0.55, 0.05)


func _camera(delta: float) -> void:
	var rig: Node = player.get("camera_rig")
	if rig == null:
		return
	var gallop := clampf((absf(horse.speed) - 7.0) / 4.5, 0.0, 1.0)
	rig.set("ride_arm", CAMERA_ARM)
	rig.set("ride_height", CAMERA_HEIGHT)
	rig.set("ride_fov", CAMERA_FOV_GALLOP * gallop)
	# back behind the horse when the rider has left the view alone a while at speed
	var yaw := float(rig.get("yaw"))
	if _cam_yaw_set != INF and absf(wrapf(yaw - _cam_yaw_set, -PI, PI)) > 0.002:
		_cam_idle = 0.0
	else:
		_cam_idle += delta
	if _cam_idle > RECENTRE_AFTER_S and absf(horse.speed) > RECENTRE_FROM:
		var want := horse.heading
		yaw = lerp_angle(yaw, want, 1.0 - exp(-1.6 * delta))
		rig.set("yaw", yaw)
	_cam_yaw_set = float(rig.get("yaw"))


func _release_camera() -> void:
	var rig: Node = player.get("camera_rig") if player != null else null
	if rig == null:
		return
	rig.set("ride_arm", 0.0)
	rig.set("ride_height", 0.0)
	rig.set("ride_fov", 0.0)
	_cam_yaw_set = INF


# --- helpers ----------------------------------------------------------------------------------------

func _just(action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	var enabled := player == null or player.get("input_enabled") == null or bool(player.get("input_enabled"))
	var now := enabled and Input.is_action_pressed(action)
	var was := bool(_prev_keys.get(action, false))
	_prev_keys[action] = now
	return now and not was


func _key_for(action: String) -> String:
	return str(Settings.prompt_for(action, Input.get_connected_joypads().size() > 0)) if Settings != null else action


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _ground(p: Vector3) -> float:
	var t: Object = World.terrain()
	if t == null or not t.has_method("get_height"):
		return -INF
	return float(t.call("get_height", p.x, p.z))


func to_save() -> Dictionary:
	return {"riding": horse.mount_id if horse != null and state == "riding" else ""}


## Player.teleport's hook: off the horse where it stands, before the body is put elsewhere.
func drop_for_teleport() -> void:
	_thrown = false
	_drop_now()


## In the saddle at once, with no getting up: a game loaded that was saved riding.
func seat_now(h: Mount) -> bool:
	if h == null or state != "" or h.is_ridden() or player == null:
		return false
	horse = h
	h.take_rider(player)
	_hold_body(true)
	_play_seat()
	_astride(1.0)
	_set_state("riding")
	player.global_transform = _seat_body_transform()
	player.reset_physics_interpolation()
	return true
