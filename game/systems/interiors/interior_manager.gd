extends Node
## Interiors: loads interior cells into a pocket and moves the player through doors.

signal transition(phase: String, interior_id: String)   # "fade_out", "fade_in"

const POCKET_ORIGIN := Vector3(50000.0, 3000.0, 50000.0)
const POCKET_STRIDE := 1000.0
const MAX_CACHED := 2

var current_id := ""
var return_point := Vector3.ZERO
var return_yaw := 0.0
var _loaded: Dictionary = {}    # interior_id -> Node3D
var _slots: Dictionary = {}     # interior_id -> int
var _next_slot := 0
var _busy := false


func _ready() -> void:
	SaveSystem.register("interiors", self)


func in_interior() -> bool:
	return not current_id.is_empty()


func pocket_for(interior_id: String) -> Vector3:
	if not _slots.has(interior_id):
		_slots[interior_id] = _next_slot
		_next_slot += 1
	return POCKET_ORIGIN + Vector3(float(_slots[interior_id]) * POCKET_STRIDE, 0.0, 0.0)


## Enter an interior through `door` (or from a saved position when door is null).
func enter(interior_id: String, door: Node3D = null, spawn_marker := "Entrance") -> bool:
	if _busy:
		return false
	if not ContentDB.has(interior_id):
		Log.error("Interiors", "unknown interior %s" % interior_id)
		return false
	var player := _player()
	if player == null:
		return false
	_busy = true
	if not in_interior():
		return_point = player.global_position
		return_yaw = player.global_rotation.y
		if door:
			return_point = door.global_position + door.global_transform.basis.z * 1.5
			return_yaw = door.global_rotation.y
	var root := _load(interior_id)
	if root == null:
		_busy = false
		return false
	transition.emit("fade_out", interior_id)
	var marker := root.find_child(spawn_marker, true, false) as Node3D
	var pos: Vector3 = marker.global_position if marker else root.global_position + Vector3.UP
	var yaw: float = marker.global_rotation.y if marker else 0.0
	_teleport(player, pos, yaw)
	var previous := current_id
	current_id = interior_id
	GameState.current_interior_id = interior_id
	if not previous.is_empty() and previous != interior_id:
		EventBus.interior_exited.emit(previous)
	EventBus.interior_entered.emit(interior_id)
	_set_atmosphere_interior(true)
	transition.emit("fade_in", interior_id)
	_busy = false
	return true


func exit() -> bool:
	if _busy or not in_interior():
		return false
	var player := _player()
	if player == null:
		return false
	_busy = true
	var leaving := current_id
	transition.emit("fade_out", "")
	_teleport(player, return_point, return_yaw)
	current_id = ""
	GameState.current_interior_id = ""
	EventBus.interior_exited.emit(leaving)
	_set_atmosphere_interior(false)
	_trim_cache(leaving)
	transition.emit("fade_in", "")
	_busy = false
	return true


func _load(interior_id: String) -> Node3D:
	if _loaded.has(interior_id) and is_instance_valid(_loaded[interior_id]):
		return _loaded[interior_id]
	var def := ContentDB.get_def(interior_id)
	var scene_path := str(def.get("scene", ""))
	if not ResourceLoader.exists(scene_path):
		Log.error("Interiors", "%s scene missing: %s" % [interior_id, scene_path])
		return null
	var packed: PackedScene = load(scene_path)
	var root := packed.instantiate() as Node3D
	if root == null:
		Log.error("Interiors", "%s root is not a Node3D" % interior_id)
		return null
	root.name = "Interior_%s" % Ids.name_of(interior_id)
	root.set_meta("interior_id", interior_id)
	# The house and deep-place wrappers build from the def's meta file the moment they enter the
	# tree, and looked for it in the current interior id, which is only set once the player is
	# through the door: every first way in from the overworld built nothing, and the player stood
	# in an empty pocket at 50 km.
	if def.has("meta"):
		root.set_meta("meta_path", str(def["meta"]))
	# The NPC streamer looks up loaded interiors by this group and falls back to matching the
	# node's name. Nothing ever joined the group, so the name was load-bearing and a rename
	# would have quietly emptied every house of the people who live in it.
	root.add_to_group("interior_root")
	var parent := _dynamic_parent()
	parent.add_child(root)
	root.global_position = pocket_for(interior_id)
	_loaded[interior_id] = root
	return root


func _trim_cache(keep: String) -> void:
	var ids := _loaded.keys()
	while ids.size() > MAX_CACHED:
		var victim: String = ids.pop_front()
		if victim == keep and ids.size() > 0:
			continue
		if is_instance_valid(_loaded[victim]):
			_loaded[victim].queue_free()
		_loaded.erase(victim)


func unload_all() -> void:
	for id in _loaded:
		if is_instance_valid(_loaded[id]):
			_loaded[id].queue_free()
	_loaded.clear()


func _teleport(player: Node3D, pos: Vector3, yaw: float) -> void:
	if player.has_method("teleport"):
		player.teleport(pos, yaw)
	else:
		player.global_position = pos
		player.global_rotation.y = yaw


func _set_atmosphere_interior(inside: bool) -> void:
	var atm := get_tree().get_first_node_in_group("atmosphere")
	if atm and atm.has_method("set_interior"):
		atm.set_interior(inside)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _dynamic_parent() -> Node:
	var n := get_tree().get_first_node_in_group("world_dynamic")
	return n if n else get_tree().current_scene


func to_save() -> Dictionary:
	return {"current_id": current_id, "return_point": [return_point.x, return_point.y, return_point.z], "return_yaw": return_yaw}


func from_save(d: Dictionary) -> void:
	var rp: Array = d.get("return_point", [0, 0, 0])
	return_point = Vector3(float(rp[0]), float(rp[1]), float(rp[2]))
	return_yaw = float(d.get("return_yaw", 0.0))
	var saved := str(d.get("current_id", ""))
	current_id = ""
	if not saved.is_empty():
		# Re-enter once the player exists (the world scene spawns the player after load).
		if _player():
			enter(saved)
		else:
			EventBus.player_spawned.connect(func(_p: Node) -> void: enter(saved), CONNECT_ONE_SHOT)
