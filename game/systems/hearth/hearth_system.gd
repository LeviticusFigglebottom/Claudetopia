extends Node
## Hearth: checkpoints, death and the Echo. See README.md.

signal echo_spawned(position: Vector3, marks: int)
signal echo_cleared

const ECHO_SCENE := preload("res://systems/hearth/echo.tscn")
const RESPAWN_DELAY := 3.0

var last_hearthstone_id := ""
var respawn_position := Vector3.ZERO
var respawn_yaw := 0.0
var lit: Array[String] = []
var echo: Dictionary = {}          # {position: Vector3, marks: int, region: String}
var deaths := 0
var _echo_node: Node3D
var _respawning := false
## The body a pending respawn is for: a death's timer that fires after that body is gone (a load,
## a new game, a test's next world) brings nobody back, rather than the next body to the old stone.
var _dying_body_id := 0


func _ready() -> void:
	SaveSystem.register("hearth", self)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_spawned.connect(_on_player_spawned)


func has_echo() -> bool:
	return not echo.is_empty()


# --- resting -------------------------------------------------------------------------------

## Called by a Hearthstone when the player rests. `autosave` is false during respawn.
func rest_at(hearthstone_id: String, position: Vector3, yaw: float, autosave := true) -> void:
	last_hearthstone_id = hearthstone_id
	respawn_position = position
	respawn_yaw = yaw
	if not hearthstone_id in lit:
		lit.append(hearthstone_id)
	var player := _player()
	if player and player.has_method("full_restore"):
		player.full_restore()
	EventBus.hearthstone_rested.emit(hearthstone_id)
	if autosave:
		call_deferred("_autosave")


func is_lit(hearthstone_id: String) -> bool:
	return hearthstone_id in lit


func _autosave() -> void:
	SaveSystem.save_to_slot(SaveSystem.AUTO_SLOT)


# --- death ---------------------------------------------------------------------------------

func _on_player_died(position: Vector3) -> void:
	if _respawning:
		return
	_respawning = true
	var dying := _player()
	_dying_body_id = dying.get_instance_id() if dying != null else 0
	deaths += 1
	GameState.inc("deaths")
	var inv := _inventory()
	var marks := 0
	if inv:
		marks = int(inv.get("marks"))
		if marks > 0 and inv.has_method("remove_marks"):
			inv.remove_marks(marks)
	if has_echo():
		EventBus.notify.emit("Your last Echo went quiet. %d marks are unsaid." % int(echo.get("marks", 0)), "warning")
	_clear_echo_node()
	echo = {"position": position, "marks": marks, "region": GameState.current_region_id}
	_spawn_echo_node()
	echo_spawned.emit(position, marks)
	var timer := get_tree().create_timer(RESPAWN_DELAY)
	timer.timeout.connect(_respawn)


func _respawn() -> void:
	# One death, one coming back. The delay timer fires three seconds after the fall and nothing
	# can cancel it, so anything that brought the player back sooner -- a load, a scripted
	# respawn, the journey's -- was undone by it seconds into whatever they were doing next.
	if not _respawning:
		return
	_respawning = false
	var player := _player()
	if player == null:
		return
	if _dying_body_id != 0 and player.get_instance_id() != _dying_body_id:
		# the body that died is gone: this is somebody else's life, and it is not put anywhere.
		# The full suite found it: a death in one test, and three seconds later the next test's
		# player was taken off the Warden mid-conversation and put down at a stale stone.
		Log.info("Hearth", "a respawn for a body that is gone comes back for nobody")
		_dying_body_id = 0
		return
	_dying_body_id = 0
	if last_hearthstone_id.is_empty():
		respawn_position = player.global_position + Vector3.UP * 0.2
	if player.has_method("respawn"):
		player.respawn(respawn_position, respawn_yaw)
	elif player is Node3D:
		player.global_position = respawn_position
	# The Echo is something you come back to, so it only answers once you have: until here the
	# body was lying on the very spot it stands on.
	if is_instance_valid(_echo_node):
		_echo_node.set("armed", true)
	EventBus.player_respawned.emit(last_hearthstone_id)
	# Coming back is a rest: the world resets around you, but no autosave mid-recovery.
	EventBus.hearthstone_rested.emit(last_hearthstone_id)


# --- echo ----------------------------------------------------------------------------------

func recover_echo() -> void:
	if not has_echo():
		return
	# Not before you have come back for it. While a death is unresolved the player is still on
	# the ground where they fell, which is where the Echo is standing.
	if _respawning:
		return
	var marks := int(echo.get("marks", 0))
	var inv := _inventory()
	if inv and inv.has_method("add_marks"):
		inv.add_marks(marks)
	echo = {}
	_clear_echo_node()
	EventBus.echo_recovered.emit(marks)
	EventBus.notify.emit("You are known again. %d marks recovered." % marks, "info")
	echo_cleared.emit()


func _spawn_echo_node() -> void:
	if not has_echo():
		return
	var parent := _dynamic_parent()
	if parent == null:
		return
	_echo_node = ECHO_SCENE.instantiate()
	parent.add_child(_echo_node)
	_echo_node.global_position = echo["position"]
	_echo_node.set("marks", int(echo["marks"]))
	# An Echo raised by a death appears around the body that just fell and must not notice it;
	# one raised by a load or a spawn is one the player left behind and is live at once.
	_echo_node.set("armed", not _respawning)


func _clear_echo_node() -> void:
	if is_instance_valid(_echo_node):
		_echo_node.queue_free()
	_echo_node = null


func _on_player_spawned(_player: Node) -> void:
	if has_echo() and not is_instance_valid(_echo_node):
		call_deferred("_spawn_echo_node")


func _dynamic_parent() -> Node:
	var n := get_tree().get_first_node_in_group("world_dynamic")
	if n:
		return n
	return get_tree().current_scene


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _inventory() -> Node:
	return get_tree().get_first_node_in_group("inventory")


# --- save ----------------------------------------------------------------------------------

## Both positions are saved with the place they stood beside (`near`), so a load into a redrawn
## map puts the stone's landing and the Echo back beside the same places (PlaceRef).
func to_save() -> Dictionary:
	var e := {}
	if has_echo():
		var p: Vector3 = echo["position"]
		e = {"position": [p.x, p.y, p.z], "marks": int(echo["marks"]), "region": echo.get("region", ""),
			"near": PlaceRef.pin(p)}
	return {
		"last_hearthstone_id": last_hearthstone_id,
		"respawn_position": [respawn_position.x, respawn_position.y, respawn_position.z],
		"respawn_near": PlaceRef.pin(respawn_position) if last_hearthstone_id != "" else {},
		"respawn_yaw": respawn_yaw, "lit": lit.duplicate(), "echo": e, "deaths": deaths,
	}


func from_save(d: Dictionary) -> void:
	last_hearthstone_id = str(d.get("last_hearthstone_id", ""))
	var rp: Array = d.get("respawn_position", [0, 0, 0])
	respawn_position = PlaceRef.follow(Vector3(float(rp[0]), float(rp[1]), float(rp[2])), d.get("respawn_near", null))
	respawn_yaw = float(d.get("respawn_yaw", 0.0))
	lit.assign(d.get("lit", []))
	deaths = int(d.get("deaths", 0))
	_clear_echo_node()
	var e: Dictionary = d.get("echo", {})
	if e.is_empty():
		echo = {}
	else:
		var ep: Array = e.get("position", [0, 0, 0])
		var at := PlaceRef.follow(Vector3(float(ep[0]), float(ep[1]), float(ep[2])), e.get("near", null))
		echo = {"position": at, "marks": int(e.get("marks", 0)), "region": str(e.get("region", ""))}
		if is_inside_tree():
			call_deferred("_spawn_echo_node")
