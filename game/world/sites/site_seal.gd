class_name SiteSeal
extends StaticBody3D
## Something across a passage that is opened once and stays open: a wall of loose stones in front
## of a site's secret room, or the bar across its way back out, lifted only from the far side (the
## boss's side), so the short way out opens once the place is done. Whether it is open is a flag
## (`site_open/<interior>/<name>`), so it stays open across leaving, returning and a save.

const INTERACT_LAYER := 1 << 4

var flag := ""
var display_name := "Loose stones"
var open_prompt := "Pull the loose stones away"
var shut_prompt := ""
## Opened only by someone standing on this side of it (world direction); zero from either side.
var from_side := Vector3.ZERO
var opened := false
signal opened_now


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("site_seal")
	collision_layer = 1 | INTERACT_LAYER
	collision_mask = 0
	set_meta("surface", "stone")
	if flag != "" and GameState.has_flag(flag):
		_open(false)


func prompt_text() -> String:
	if opened:
		return ""
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and not may_open(player.global_position):
		return shut_prompt if shut_prompt != "" else display_name
	return open_prompt


func may_open(at: Vector3) -> bool:
	if from_side == Vector3.ZERO:
		return true
	return (at - global_position).dot(from_side) > 0.0


func interact(actor: Node) -> void:
	if opened or not (actor is Node3D):
		return
	if not may_open((actor as Node3D).global_position):
		EventBus.notify.emit(shut_prompt if shut_prompt != "" else "It will not move from this side.", "warning")
		return
	_open(true)


func _open(now: bool) -> void:
	opened = true
	if flag != "":
		GameState.set_flag(flag)
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
		elif c is Node3D:
			(c as Node3D).visible = false
	remove_from_group("interactable")
	if now:
		opened_now.emit()
