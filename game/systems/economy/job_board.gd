class_name JobBoard
extends StaticBody3D
## A charter-board or notice post. Interacting lists the day's radiant work for the board's
## place: quests from the quest system when one is registered, else simple deliveries.
## The UI stream listens for `jobs_listed` to draw the board; `take(index, actor)` accepts
## one, `deliver(job, actor)` completes a delivery when the carrier reaches the other town.
## Offers refresh once per game day, so a board read twice in an afternoon reads the same.

const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"

signal jobs_listed(jobs: Array)
signal job_taken(job: Dictionary)

## How near a settlement's centre counts as being in it, for delivery.
const ARRIVAL_M := 120.0

@export var place_id := ""
@export var count := Jobs.BOARD_JOB_COUNT
@export var display_name := "Job board"

var taken: Array[Dictionary] = []
var _cache: Array[Dictionary] = []
var _cache_day := -1


func _ready() -> void:
	add_to_group("interactable")
	# The physics layer the player's interaction ray masks. It used to be set only in this
	# class's .tscn, so a node built with `.new()` kept Godot's default layer 1 and the ray
	# went straight through it — visible, in the group, with an `interact()` method, and
	# impossible to walk up to. `container.gd` and `world_item.gd` always set their own.
	collision_layer = INTERACT_LAYER
	add_to_group("job_board")
	if place_id.is_empty():
		var near := WorldProbe.nearest_place(global_position, 500.0)
		place_id = str(near.get("id", ""))
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 1.4, 0.15)
		col.shape = box
		col.position.y = 1.2
		add_child(col)


## The settlement the carrier is standing in, or "" when they are out in the country.
static func place_of_carrier(actor: Node) -> String:
	if actor == null or not is_instance_valid(actor) or not (actor is Node3D):
		return ""
	var near := WorldProbe.nearest_place((actor as Node3D).global_position, ARRIVAL_M)
	return str(near.get("id", ""))


func offers() -> Array[Dictionary]:
	if _cache_day == WorldClock.day and not _cache.is_empty():
		return _cache
	_cache = Jobs.board_offers(place_id, count)
	_cache_day = WorldClock.day
	return _cache


func prompt_text() -> String:
	return "%s (%d notices)" % [display_name, offers().size()]


func interact(actor: Node) -> Array[Dictionary]:
	var list := offers()
	jobs_listed.emit(list)
	# The signal is for anything that wants the list; this is what puts it in front of a
	# player, and without it the board was a post you could walk up to and read nothing on.
	EventBus.job_board_opened.emit(self, actor)
	return list


func has_taken(job_id: String) -> bool:
	for j in taken:
		if str(j.get("id", "")) == job_id:
			return true
	return false


## Accepts the job at `index`: hands over the parcel for a delivery, or starts the quest.
func take(index: int, actor: Node = null) -> Dictionary:
	var list := offers()
	if index < 0 or index >= list.size():
		return {}
	var job: Dictionary = list[index].duplicate()
	if has_taken(str(job.get("id", ""))):
		EventBus.notify.emit("You are already carrying that one.", "info")
		return {}
	if str(job.get("kind", "")) == "delivery":
		var item := str(job.get("item", Jobs.DELIVERY_PARCEL))
		if not Peers.give_item(actor, item, 1):
			EventBus.notify.emit("You have no room for it.", "info")
			return {}
		taken.append(job)
	else:
		var q := Peers.quests()
		if q != null and q.has_method("start"):
			q.call("start", str(job.get("id", "")))
		EventBus.quest_started.emit(str(job.get("id", "")))
	job_taken.emit(job)
	EventBus.notify.emit("Taken: %s" % str(job.get("title", "work")), "job")
	return job


## Completes a delivery, but only where it was addressed. `at_place` names where the carrier
## is; left out, it is read from the carrier's own position, so handing a parcel back over
## the counter it came from pays nothing.
func deliver(job: Dictionary, actor: Node = null, at_place := "") -> int:
	if at_place.is_empty():
		at_place = place_of_carrier(actor)
	if str(job.get("to", "")) != at_place or at_place.is_empty():
		EventBus.notify.emit("That is not where it is going.", "info")
		return 0
	var item := str(job.get("item", Jobs.DELIVERY_PARCEL))
	if Peers.item_count(actor, item) < 1:
		EventBus.notify.emit("The parcel is gone.", "info")
		return 0
	Peers.take_item(actor, item, 1)
	for i in taken.size():
		if taken[i].get("id", "") == job.get("id", ""):
			taken.remove_at(i)
			break
	return Jobs.complete(job, actor)
