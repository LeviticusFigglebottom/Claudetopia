extends Node3D
## Test double for the player: counts restores/respawns.

var restores := 0
var respawns := 0


func _ready() -> void:
	add_to_group("player")


func full_restore() -> void:
	restores += 1


func respawn(position: Vector3, _yaw: float) -> void:
	global_position = position
	respawns += 1


func is_dead() -> bool:
	return false
