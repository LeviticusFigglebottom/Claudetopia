class_name Door
extends StaticBody3D
## A door between the overworld and an interior (or an exit inside one).

const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"

@export var interior_id := ""
@export var spawn_marker := "Entrance"
@export var is_exit := false
@export var display_name := "Door"
@export var owner_faction := ""
@export var owner_npc := ""


func _ready() -> void:
	add_to_group("interactable")
	# The physics layer the player's interaction ray masks. It used to be set only in this
	# class's .tscn, so a node built with `.new()` kept Godot's default layer 1 and the ray
	# went straight through it — visible, in the group, with an `interact()` method, and
	# impossible to walk up to. `container.gd` and `world_item.gd` always set their own.
	collision_layer = INTERACT_LAYER
	add_to_group("door")
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 2.2, 0.3)
		col.shape = box
		col.position.y = 1.1
		add_child(col)


func prompt_text() -> String:
	var lock := get_node_or_null("DoorLock")
	if lock and lock.has_method("is_locked") and lock.is_locked():
		return "%s (locked)" % display_name
	return "Leave" if is_exit else "Enter %s" % display_name


func interact(actor: Node) -> void:
	if not actor.is_in_group("player"):
		return
	var lock := get_node_or_null("DoorLock")
	if lock and lock.has_method("is_locked") and lock.is_locked():
		if not (lock.has_method("try_open") and lock.try_open(actor)):
			EventBus.notify.emit("%s is locked." % display_name, "warning")
			return
	if is_exit:
		Interiors.exit()
	elif not interior_id.is_empty():
		Interiors.enter(interior_id, self, spawn_marker)
