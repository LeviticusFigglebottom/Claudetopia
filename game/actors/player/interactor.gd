class_name Interactor
extends RayCast3D
## Interaction probe (physics layer "interactable"). Any collider (or an ancestor of it) with
## `interact(player: Node)` is a target; `prompt_text() -> String` (or a `prompt` property)
## labels it. Emits prompt_changed("" when nothing) and EventBus.notify(text, "prompt") on acquire,
## once each time the player comes to something. While a conversation runs it offers nothing.

signal prompt_changed(text: String)
signal target_changed(target: Node)

const MASK_INTERACT := 1 << 4

var reach: float = 2.6
var target: Node = null
var prompt: String = ""
## What the prompt was last announced for (EventBus.notify), as an instance id, so that a
## conversation ending with the player still facing the person does not announce them again.
var _announced_id := 0


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
	# Nothing is offered while somebody is talking. The prompt had stayed on the screen under the
	# conversation, and a toast repeated it, saying that the key going on through the talk would
	# start it.
	var talking := _talking()
	var found := _resolve(get_collider()) if is_colliding() and not talking else null
	if found == null and not talking:
		_announced_id = 0
	if found != target:
		target = found
		prompt = _prompt_for(found)
		target_changed.emit(target)
		prompt_changed.emit(prompt)
		if target != null and not prompt.is_empty() and target.get_instance_id() != _announced_id:
			_announced_id = target.get_instance_id()
			EventBus.notify.emit(prompt, "prompt")


func _talking() -> bool:
	var talk: Node = Social.dialogue if Social != null else null
	return talk != null and bool(talk.call("is_running"))


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
