class_name Interactor
extends RayCast3D
## Interaction probe (physics layer "interactable"). Any collider (or an ancestor of it) with
## `interact(player: Node)` is a target; `prompt_text() -> String` (or a `prompt` property)
## labels it. Emits prompt_changed("" when nothing) and EventBus.notify(text, "prompt") on acquire.

signal prompt_changed(text: String)
signal target_changed(target: Node)

const MASK_INTERACT := 1 << 4

var reach: float = 2.6
var target: Node = null
var prompt: String = ""


func _ready() -> void:
	enabled = true
	collision_mask = MASK_INTERACT
	collide_with_areas = true
	collide_with_bodies = true
	target_position = Vector3(0.0, 0.0, -reach)
	var p := get_parent()
	if p is CollisionObject3D:
		add_exception(p as CollisionObject3D)


## Points the ray along a world direction (the camera's view direction).
func update_aim(direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		return
	target_position = to_local(global_position + direction.normalized() * reach)


func _physics_process(_delta: float) -> void:
	var found := _resolve(get_collider()) if is_colliding() else null
	if found != target:
		target = found
		prompt = _prompt_for(found)
		target_changed.emit(target)
		prompt_changed.emit(prompt)
		if target != null and not prompt.is_empty():
			EventBus.notify.emit(prompt, "prompt")


func _resolve(collider: Object) -> Node:
	var n := collider as Node
	while n != null:
		if n.has_method("interact"):
			return n
		n = n.get_parent()
	return null


func _prompt_for(n: Node) -> String:
	if n == null:
		return ""
	var text := "Interact"
	if n.has_method("prompt_text"):
		text = str(n.prompt_text())
	elif n.get("prompt") != null:
		text = str(n.get("prompt"))
	var key: String = Settings.prompt_for("interact", Input.get_connected_joypads().size() > 0)
	return "[%s] %s" % [key, text]


func has_target() -> bool:
	return target != null and is_instance_valid(target)


func try_interact(player: Node) -> bool:
	if not has_target():
		return false
	# While somebody is talking, the interact key goes on through the conversation (the dialogue UI
	# takes it). The press that closes the conversation must not open it again on the same frame.
	var talk: Node = Social.dialogue if Social != null else null
	if talk != null and (bool(talk.call("is_running")) or bool(talk.call("just_ended"))):
		return false
	target.interact(player)
	return true
