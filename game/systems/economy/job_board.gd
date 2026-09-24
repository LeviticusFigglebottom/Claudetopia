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
## Where the carried boards are kept (`for_place`).
const CARRIED_HOLDER := "CarriedJobBoards"

@export var place_id := ""
@export var count := Jobs.BOARD_JOB_COUNT
@export var display_name := "Job board"
## A board nobody nailed up: the work a hamlet, a lodge or a camp has, which its people tell you
## when you ask (`for_place`). It has no body in the world and nothing walks up to it.
@export var carried := false

## Parcels in hand: these are the rows the board offers to take back off you.
var taken: Array[Dictionary] = []
## Board quests taken on. They are the quest log's business from then on, not the board's, so
## only their ids are kept — enough that the notice comes off the board.
var accepted: Array[String] = []
var _cache: Array[Dictionary] = []
var _cache_day := -1


func _ready() -> void:
	if carried:
		collision_layer = 0
		collision_mask = 0
		return
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


## Where a place's work is read, for somebody who lives there and is asked (`offer_work`): the
## notice post standing in the place, or, where nobody put one up (only towns, cities, villages
## and forts have one: Settlement.FABRIC), the place's carried board, made once and kept, so the
## work a place has is the same whoever there you ask and whenever.
static func for_place(place_id: String) -> JobBoard:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or place_id == "":
		return null
	for n in tree.get_nodes_in_group("job_board"):
		if n is JobBoard and not (n as JobBoard).carried and (n as JobBoard).place_id == place_id:
			return n as JobBoard
	var holder := tree.root.get_node_or_null(CARRIED_HOLDER)
	if holder == null:
		holder = Node.new()
		holder.name = CARRIED_HOLDER
		tree.root.add_child(holder)
	var node_name := "Board_" + Ids.name_of(place_id)
	var kept := holder.get_node_or_null(node_name)
	if kept is JobBoard:
		return kept as JobBoard
	var board := JobBoard.new()
	board.name = node_name
	board.place_id = place_id
	board.carried = true
	board.display_name = str(ContentDB.get_or_empty(place_id).get("name", "The work going"))
	holder.add_child(board)
	return board


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
	return accepted.has(job_id)


## Accepts the job at `index`: hands over the parcel for a delivery, or takes on the quest.
##
## A quest goes through `Social.take_quest()`, which is the front door the social stream put
## there for exactly this and which nothing outside a test had ever opened. This used to
## reach past it to the quest log's `start()` and then emit `quest_started` itself — which
## `QuestLog.start()` already emits, so a taken bounty announced itself twice, and a job that
## could not start (unmet requirement, already done) announced itself anyway. The façade
## answers whether it took, and nothing is said unless it did.
func take(index: int, actor: Node = null) -> Dictionary:
	var list := offers()
	if index < 0 or index >= list.size():
		return {}
	var job: Dictionary = list[index].duplicate()
	var job_id := str(job.get("id", ""))
	if has_taken(job_id):
		EventBus.notify.emit("You have that one already.", "info")
		return {}
	if str(job.get("kind", "")) == "delivery":
		var item := str(job.get("item", Jobs.DELIVERY_PARCEL))
		if not Peers.give_item(actor, item, 1):
			EventBus.notify.emit("You have no room for it.", "info")
			return {}
		taken.append(job)
	elif not _take_quest(job_id):
		EventBus.notify.emit("That one is not for you today.", "info")
		return {}
	job_taken.emit(job)
	EventBus.notify.emit("Taken: %s" % str(job.get("title", "work")), "job")
	return job


## Takes on a board quest, through the social façade where there is one and the quest log's
## own `start()` where there is not (a unit test with no `Social` in the tree). Returns
## whether it was actually taken on.
func _take_quest(job_id: String) -> bool:
	if job_id.is_empty():
		return false
	var social := Peers.social()
	if social != null and social.has_method("take_quest"):
		if not bool(social.call("take_quest", job_id)):
			return false
	else:
		var q := Peers.quests()
		if q == null or not q.has_method("start") or not bool(q.call("start", job_id)):
			return false
	accepted.append(job_id)
	return true


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
