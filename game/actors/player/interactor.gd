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
	if not EventBus.menu_opened.is_connected(_on_menu_opened):
		EventBus.menu_opened.connect(_on_menu_opened)


## A prompt must never outlive what it offered (playtest 09-27: "press E to pick up" stayed up,
## through the menus). Three ways it could: the tree pauses under a menu and this stops ticking
## with the prompt still up; the body carrying this leaves the world (a load, a respawn) and the
## HUD keeps the last words it was told; and the toast raised on the way up stays its five
## seconds whatever happened to the thing. So a pause, a menu and leaving the tree all take it
## down at once, and it comes back on its own when the world runs again.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_clear()
		UI.dismiss_toasts("prompt")


func _on_menu_opened(_menu_id: String) -> void:
	_clear()
	UI.dismiss_toasts("prompt")


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
	var busy := talking or _menu_up()
	var found := _resolve(get_collider()) if is_colliding() and not busy else null
	_offer(found, busy)


## Makes `found` the target (or nothing), and says so when it changed. What a thing offers can
## change while it is looked at (a horse mounted, a door opened), so the words are read afresh
## every tick and a change of them is said too; a thing with nothing to say is not offered.
## Coming away from a thing (not merely being busy with a talk or a menu) forgets that it was
## announced, and takes its toast down.
func _offer(found: Node, busy := false) -> void:
	var text := _prompt_for(found)
	if text.is_empty():
		found = null
	if found == null and not busy:
		_forget_announcement()
	if found == target and text == prompt:
		return
	var was := target
	if was != found and was != null and is_instance_valid(was) \
			and was.tree_exiting.is_connected(_on_target_leaving):
		was.tree_exiting.disconnect(_on_target_leaving)
	target = found
	prompt = text
	if target != null and not target.tree_exiting.is_connected(_on_target_leaving):
		target.tree_exiting.connect(_on_target_leaving, CONNECT_ONE_SHOT)
	if was != found:
		target_changed.emit(target)
	prompt_changed.emit(prompt)
	if target != null and target.get_instance_id() != _announced_id:
		_forget_announcement()
		_announced_id = target.get_instance_id()
		EventBus.notify.emit(prompt, "prompt")


## Takes the prompt down now: what it offered is gone, or the game has stopped under a menu.
## The next tick of a running world finds it again if it is still there.
func _clear() -> void:
	if target == null and prompt.is_empty():
		return
	if target != null and is_instance_valid(target) and target.tree_exiting.is_connected(_on_target_leaving):
		target.tree_exiting.disconnect(_on_target_leaving)
	target = null
	prompt = ""
	target_changed.emit(null)
	prompt_changed.emit("")


## The thing offered was picked up, or its cell went: the prompt goes the same frame, not on the
## next tick (which a pause can put off for as long as a menu is up), and so does its toast.
func _on_target_leaving() -> void:
	_forget_announcement()
	_clear()


## The toast that announced the last thing comes down with it: "[E] Pick up the knife" in the
## corner after the knife is in the bag says something untrue for five seconds.
func _forget_announcement() -> void:
	if _announced_id != 0:
		_announced_id = 0
		UI.dismiss_toasts("prompt")


func _menu_up() -> bool:
	return UI != null and UI.is_menu_open()


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
	if n == null or not is_instance_valid(n) or n.is_queued_for_deletion():
		return ""
	var text := "Interact"
	if n.has_method("prompt_text"):
		text = str(n.prompt_text())
	elif n.get("prompt") != null:
		text = str(n.get("prompt"))
	if text.is_empty():
		return ""
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
