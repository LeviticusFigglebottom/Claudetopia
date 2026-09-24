class_name Stable
extends Node3D
## The player's horses, in the world (DECISIONS 2026-09-24, "A starter horse").
##
## A horse is owned by a flag (`give_mount` sets `mount_owned/<id>`) and stood up here when the
## world is ready: where the save left it, or at its content def's `home` -- a few paces off a
## named door, in the clear. It is not cell data: it stays where it was left, sleeps (hidden, no
## physics) past SLEEP_M from the player, and wakes on the ground when the player comes back.
## The whistle (`call_mount`, heard through the Rider) brings it over the ground from within
## WHISTLE_M, and from farther, or when it is stuck, it comes in from behind the player out of
## the view. The save section `mounts` holds each horse's place, heading and stamina, and which
## one is being ridden, so a game saved in the saddle loads in the saddle.

const SAVE_SECTION := "mounts"
const FLAG_PREFIX := SocialContext.MOUNT_FLAG_PREFIX
const SLEEP_M := 300.0
const WAKE_M := 280.0
const WHISTLE_M := 250.0
## A horse brought round comes in from this far behind the player, out of the camera's view.
const FROM_BEHIND_M := 60.0
const CHECK_S := 0.5

var horses: Dictionary = {}         # mount id -> Mount
var last_ridden := ""
var _saved: Dictionary = {}         # mount id -> its save, until it is stood up
var _riding_saved := ""
var _ready_to_stand := false
var _check := 0.0


static func find(_from: Node = null) -> Stable:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("stable") as Stable


func _ready() -> void:
	add_to_group("stable")
	SaveSystem.register(SAVE_SECTION, self)
	if Social != null and Social.has_method("bind"):
		Social.bind("stable", self)
	var world := _world()
	if world != null and not world.is_world_ready:
		await world.world_ready
	# after the doors are up: a horse's home is found by its door
	await get_tree().process_frame
	_ready_to_stand = true
	stand_owned()
	if not EventBus.player_spawned.is_connected(_on_player_spawned):
		EventBus.player_spawned.connect(_on_player_spawned)
	var p := _player()
	if p != null:
		_on_player_spawned(p)


func _exit_tree() -> void:
	if SaveSystem.participants.get(SAVE_SECTION) == self:
		SaveSystem.unregister(SAVE_SECTION)


func _world() -> World:
	var n := get_parent()
	while n != null:
		if n is World:
			return n as World
		n = n.get_parent()
	return World.instance


## Every horse the flags say the player owns, stood up if it is not already.
func stand_owned() -> void:
	for key in GameState.flags.keys():
		var k := str(key)
		if k.begins_with(FLAG_PREFIX) and bool(GameState.flags[key]):
			give(k.trim_prefix(FLAG_PREFIX))


## The player owns this horse: stand it up (at its save's place, or at home). Idempotent.
func give(mount_id: String) -> Mount:
	GameState.set_flag(FLAG_PREFIX + mount_id, true)
	if horses.has(mount_id):
		return horses[mount_id]
	if not _ready_to_stand or not ContentDB.has(mount_id):
		return null
	var m := Mount.new()
	m.mount_id = mount_id
	m.name = "Mount_" + Ids.name_of(mount_id)
	add_child(m)
	horses[mount_id] = m
	if _saved.has(mount_id):
		m.from_save(_saved[mount_id])
		_saved.erase(mount_id)
	else:
		var spot := home_of(mount_id)
		m.place(spot[0], spot[1])
		Log.info("Stable", "%s stands at %s" % [m.display_name, str((spot[0] as Vector3).round())])
	if last_ridden.is_empty():
		last_ridden = mount_id
	return m


## Where a horse stands when it is first given: a few paces off its def's `home.door`, alongside
## the house front, on clear level ground; or by its home place's middle.
func home_of(mount_id: String) -> Array:
	var def := ContentDB.get_or_empty(mount_id)
	var home: Dictionary = def.get("home", {})
	var door_id := str(home.get("door", ""))
	var door := _door(door_id)
	if door != null:
		var out := door.global_transform.basis.z
		out.y = 0.0
		out = out.normalized() if out.length() > 0.01 else Vector3.BACK
		var side := out.cross(Vector3.UP).normalized()
		for off in [[5.0, 3.5], [5.0, -3.5], [7.0, 5.5], [7.0, -5.5], [9.0, 0.0], [4.0, 7.0], [4.0, -7.0], [11.0, 3.0]]:
			var p: Vector3 = door.global_position + out * float(off[0]) + side * float(off[1])
			p.y = _ground(p)
			# standing along the house front, its head the way the side goes
			var yaw := atan2(side.x, side.z) if float(off[1]) >= 0.0 else atan2(-side.x, -side.z)
			if _clear(p, yaw):
				return [p, yaw]
	var place := str(home.get("place", ""))
	var world := _world()
	var c := world.place_position(place) if world != null and not place.is_empty() else Vector3.ZERO
	c += Vector3(6.0, 0.0, 6.0)
	c.y = _ground(c)
	return [c, 0.0]


func _door(interior_id: String) -> Node3D:
	if interior_id.is_empty():
		return null
	for wd in get_tree().get_nodes_in_group("world_doors"):
		for d in wd.get("placed"):
			if d != null and is_instance_valid(d) and str(d.get("interior_id")) == interior_id:
				return d as Node3D
	return null


## Room for a horse here: nothing solid in its body's box, level enough, and dry.
func _clear(p: Vector3, yaw: float) -> bool:
	var t: Object = World.terrain()
	if t != null and t.has_method("water_depth_at") and float(t.call("water_depth_at", p.x, p.z)) > 0.2:
		return false
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	if absf(_ground(p + fwd * 1.1) - _ground(p - fwd * 1.1)) > 0.8:
		return false
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.5, 2.7)
	q.shape = box
	q.transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0.0, 1.0, 0.0))
	q.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_NPC | Actor.LAYER_ENEMY
	return space.intersect_shape(q, 1).is_empty()


func _ground(p: Vector3) -> float:
	var t: Object = World.terrain()
	if t == null or not t.has_method("get_height"):
		return p.y
	return float(t.call("get_height", p.x, p.z))


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null


# --- the whistle ------------------------------------------------------------------------------

## The player whistles: the last horse ridden comes. Says why when it cannot.
func whistle(player: Node3D) -> Mount:
	if horses.is_empty():
		EventBus.emit_notify("You have no horse to whistle for.", "info")
		return null
	if Interiors != null and Interiors.has_method("in_interior") and bool(Interiors.call("in_interior")):
		EventBus.emit_notify("No horse will hear you in here.", "info")
		return null
	var id := last_ridden if horses.has(last_ridden) else str(horses.keys()[0])
	var m: Mount = horses[id]
	if m.is_ridden():
		return m
	var t: Object = World.terrain()
	if t != null and t.has_method("water_depth_at") and float(t.call("water_depth_at", player.global_position.x, player.global_position.z)) > Mount.WALK_DEPTH:
		EventBus.emit_notify("%s won't come into water this deep." % m.display_name, "info")
		return null
	var d := m.global_position.distance_to(player.global_position)
	if d > WHISTLE_M or m.sleeping:
		_bring_round(m, player)
	m.call_to(player)
	return m


## Brings a horse to FROM_BEHIND_M behind the player, where the camera is not looking, on dry
## ground it can stand on; it then comes the rest of the way itself.
func _bring_round(m: Mount, player: Node3D) -> void:
	var back := Vector3.BACK
	var rig: Node = player.get("camera_rig")
	if rig != null and rig.has_method("forward_flat"):
		back = -(rig.call("forward_flat") as Vector3)
	for turn in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
		var dir := back.rotated(Vector3.UP, float(turn))
		var p := player.global_position + dir * FROM_BEHIND_M
		p.y = _ground(p)
		var yaw := atan2(dir.x, dir.z)      # facing back toward the player
		if _clear(p, yaw):
			m.wake()
			m.place(p, yaw)
			return
	var q := player.global_position + back * 12.0
	q.y = _ground(q)
	m.wake()
	m.place(q, atan2(back.x, back.z))


# --- sleeping and waking ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_check += delta
	if _check < CHECK_S:
		return
	_check = 0.0
	var p := _player()
	if p == null:
		return
	for id in horses:
		var m: Mount = horses[id]
		if not is_instance_valid(m):
			continue
		if m.is_ridden():
			last_ridden = str(id)
			continue
		if m.is_stuck():
			_bring_round(m, p)
			m.call_to(p)
			continue
		var d := m.global_position.distance_to(p.global_position)
		if d > SLEEP_M and m.mode != Mount.Mode.COMING:
			m.sleep()
		elif d < WAKE_M and m.sleeping:
			m.wake()


func _on_player_spawned(player: Node) -> void:
	if _riding_saved.is_empty() or not horses.has(_riding_saved):
		return
	var r := Rider.of(player)
	var m: Mount = horses[_riding_saved]
	_riding_saved = ""
	if r != null:
		m.wake()
		r.seat_now(m)


# --- the save -------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	var out := {}
	var riding := ""
	for id in horses:
		var m: Mount = horses[id]
		if is_instance_valid(m):
			out[id] = m.to_save()
			if m.is_ridden():
				riding = str(id)
	for id in _saved:
		if not out.has(id):
			out[id] = _saved[id]
	return {"horses": out, "riding": riding, "last_ridden": last_ridden}


func from_save(d: Dictionary) -> void:
	_saved = (d.get("horses", {}) as Dictionary).duplicate(true)
	_riding_saved = str(d.get("riding", ""))
	last_ridden = str(d.get("last_ridden", last_ridden))
	# horses already standing are moved to where the save has them
	for id in _saved.keys():
		if horses.has(id):
			(horses[id] as Mount).from_save(_saved[id])
			_saved.erase(id)
	if _ready_to_stand:
		stand_owned()
		var p := _player()
		if p != null:
			_on_player_spawned(p)
