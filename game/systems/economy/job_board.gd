class_name JobBoard
extends StaticBody3D
## A charter-board or notice post. Interacting lists the day's radiant work for the board's
## place: quests from the quest system when one is registered, else simple deliveries.
## The UI stream listens for `jobs_listed` to draw the board; `take(index, actor)` accepts
## one, `deliver(job, actor)` completes a delivery when the carrier reaches the other town.
## Offers refresh once per game day, so a board read twice in an afternoon reads the same.

signal jobs_listed(jobs: Array)
signal job_taken(job: Dictionary)

@export var place_id := ""
@export var count := Jobs.BOARD_JOB_COUNT
@export var display_name := "Job board"

var taken: Array[Dictionary] = []
var _cache: Array[Dictionary] = []
var _cache_day := -1


func _ready() -> void:
	add_to_group("interactable")
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


func offers() -> Array[Dictionary]:
	if _cache_day == WorldClock.day and not _cache.is_empty():
		return _cache
	_cache = Jobs.board_offers(place_id, count)
	_cache_day = WorldClock.day
	return _cache


func prompt_text() -> String:
	return "%s (%d notices)" % [display_name, offers().size()]


func interact(_actor: Node) -> Array[Dictionary]:
	var list := offers()
	jobs_listed.emit(list)
	return list


## Accepts the job at `index`: hands over the parcel for a delivery, or starts the quest.
func take(index: int, actor: Node = null) -> Dictionary:
	var list := offers()
	if index < 0 or index >= list.size():
		return {}
	var job: Dictionary = list[index].duplicate()
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


## Completes a delivery when the carrier is at (or names) the destination.
func deliver(job: Dictionary, actor: Node = null, at_place := "") -> int:
	if at_place.is_empty():
		at_place = str(job.get("to", ""))
	if str(job.get("to", "")) != at_place:
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
