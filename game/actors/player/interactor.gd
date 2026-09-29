class_name Interactor
extends Node3D
## Interaction probe (physics layer "interactable"). Any collider (or an ancestor of it) with
## `interact(player: Node)` is a target; `prompt_text() -> String` (or a `prompt` property)
## labels it. Emits prompt_changed("" when nothing) and EventBus.notify(text, "prompt") on acquire,
## once each time the player comes to something. While a conversation runs it offers nothing.
##
## How it finds things. It was one 2.6 m ray down the camera's view from the chest, and the
## playtest of 09-27 said it plainly: prompts "don't appear unless you're at a very particular
## angle or distance". A knife on the ground was under the ray; a person beside you was off it;
## a chest came and went as the camera swung. Now it asks the physics for everything on the
## interaction layer (bodies and areas) within `reach` of a point a little below the chest, and
## chooses among them: nearer is better, and in front is better -- in front of the body or of the
## camera, whichever the thing is more in front of, so that walking up to something and looking
## at something both work. A thing behind you is offered only when you are all but touching it.
## Nothing is offered through a wall (one ray on the world layer from the chest to the thing).
## What is already offered is kept a little longer than a new thing would be taken (a margin
## of reach and of score), so that two things side by side do not flicker between each other.

signal prompt_changed(text: String)
signal target_changed(target: Node)

const MASK_INTERACT := 1 << 4
## Walls, floors, furniture: what the line of sight from the chest to a thing is tested against.
const MASK_SIGHT := 1 << 0
## How far below this node's own height the search is centred: it rides at the chest (1.3 m),
## and a thing lying on the ground a stride off must be as near as a face.
const CENTRE_DROP_M := 0.4
## How much further than `reach` what is already offered stays offered, and how much better a
## new thing must score to take its place.
const KEEP_EXTRA_M := 0.35
const KEEP_SCORE := 0.2
## A thing behind the body and the camera both is offered only nearer than this.
const BEHIND_M := 0.7
const MAX_FOUND := 32

var reach: float = 2.75
var target: Node = null
var prompt: String = ""
## What the prompt was last announced for (EventBus.notify), as an instance id, so that a
## conversation ending with the player still facing the person does not announce them again.
var _announced_id := 0
## The camera's view, flat (update_aim); zero until one is given, and then the body's facing
## stands in for it.
var _aim := Vector3.ZERO
var _sphere := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	_query.collision_mask = MASK_INTERACT
	_query.collide_with_areas = true
	_query.collide_with_bodies = true
	_query.shape = _sphere
	var p := get_parent()
	if p is CollisionObject3D:
		_query.exclude = [(p as CollisionObject3D).get_rid()]
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


## The camera's view direction, which counts as much as the body's facing in choosing.
func update_aim(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return
	_aim = flat.normalized()


func _physics_process(_delta: float) -> void:
	# Nothing is offered while somebody is talking. The prompt had stayed on the screen under the
	# conversation, and a toast repeated it, saying that the key going on through the talk would
	# start it.
	var talking := _talking()
	var busy := talking or _menu_up()
	var found := _choose() if not busy else null
	_offer(found, busy)


## The best thing within reach, or null. See the head of the file for how it chooses.
func _choose() -> Node:
	if not is_inside_tree():
		return null
	var space := get_world_3d().direct_space_state
	var centre := global_position - Vector3(0.0, CENTRE_DROP_M, 0.0)
	_sphere.radius = reach + KEEP_EXTRA_M
	_query.transform = Transform3D(Basis.IDENTITY, centre)
	var hits := space.intersect_shape(_query, MAX_FOUND)
	var facing := _facing()
	var view := _aim if _aim != Vector3.ZERO else facing
	var best: Node = null
	var best_score := INF
	for hit in hits:
		var co := hit.get("collider") as CollisionObject3D
		if co == null:
			continue
		var thing := _resolve(co)
		if thing == null or _prompt_for(thing).is_empty():
			continue
		var at := _shape_point(co, int(hit.get("shape", 0)))
		var origin: Vector3 = at["origin"]
		var gap := maxf(centre.distance_to(origin) - float(at["radius"]), 0.0)
		var current := thing == target
		if gap > reach + (KEEP_EXTRA_M if current else 0.0):
			continue
		var to := Vector3(origin.x - centre.x, 0.0, origin.z - centre.z)
		var front := 1.0
		if to.length_squared() > 0.0001:
			to = to.normalized()
			front = maxf(facing.dot(to), view.dot(to))
		if front < -0.2 and gap > BEHIND_M:
			continue
		var score := gap / reach + (1.0 - front) * 0.5 - (KEEP_SCORE if current else 0.0)
		if score >= best_score:
			continue
		if not _in_sight(space, co, thing, origin):
			continue
		best = thing
		best_score = score
	return best


## Where a hit shape is, and roughly how far it reaches out from there (a person's capsule, a
## horse's flank), so that a big thing is as near as its near side.
func _shape_point(co: CollisionObject3D, shape_index: int) -> Dictionary:
	var owner_id := co.shape_find_owner(shape_index)
	var node := co.shape_owner_get_owner(owner_id) as Node3D
	var origin := node.global_position if node != null else co.global_position
	var shape: Shape3D = null
	if co.shape_owner_get_shape_count(owner_id) > 0:
		shape = co.shape_owner_get_shape(owner_id, 0)
	var r := 0.0
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		r = minf(size.x, size.z) * 0.5
	elif shape is SphereShape3D:
		r = (shape as SphereShape3D).radius
	elif shape is CapsuleShape3D:
		r = (shape as CapsuleShape3D).radius
	elif shape is CylinderShape3D:
		r = (shape as CylinderShape3D).radius
	return {"origin": origin, "radius": r}


## Which way the body faces, flat: its own forward() when it has one (an actor's), else this
## node's.
func _facing() -> Vector3:
	var p := get_parent()
	var f := -global_transform.basis.z
	if p != null and p.has_method("forward"):
		f = p.call("forward")
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


## Whether the thing can be seen from the chest: nothing on the world layer stands between,
## other than the thing itself (a Hearthstone is on both layers) or something at its very side.
func _in_sight(space: PhysicsDirectSpaceState3D, co: CollisionObject3D, thing: Node, at: Vector3) -> bool:
	var to := at + Vector3(0.0, 0.15, 0.0)
	var ray := PhysicsRayQueryParameters3D.create(global_position, to, MASK_SIGHT)
	var excl: Array[RID] = [co.get_rid()]
	var p := get_parent()
	if p is CollisionObject3D:
		excl.append((p as CollisionObject3D).get_rid())
	ray.exclude = excl
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return true
	if _resolve(hit.get("collider")) == thing:
		return true
	return (hit.get("position") as Vector3).distance_to(to) < 0.35


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
