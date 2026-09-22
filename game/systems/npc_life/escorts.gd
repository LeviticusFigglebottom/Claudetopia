class_name Escorts
extends Node
## Walking somebody somewhere.
##
## A quest can ask the player to see a person safely to a place — `{"type": "escort", "target":
## npc, "place": place}` — and `QuestLog` has listened for `EventBus.escort_arrived` since the day
## it was written. Nothing in the game ever said it, so the Tolling Order's first quest and every
## escort a job board posts could be taken and never finished. This is what says it.
##
## An escort comes due when its stage is the quest's current one, anybody the same stage asks you
## to speak to first — the traveller themselves, usually — has been spoken to, and the objective's
## own `requires` hold: Aud Fennick will not set out until she has said she will. From then the
## person falls in behind the player (`Npc.follow`), and one of three things happens, each of
## which writes a line in the journal:
##
## * **They arrive.** Within the objective's `radius` (45 m unless it says) of the place, the bus
##   hears `escort_arrived` and the quest log closes the objective. They stay where you brought
##   them for as long as you are there, and go back to their own life once you have gone.
## * **You leave them behind.** More than `LEFT_BEHIND_M` away and they stop and wait where they
##   stand, and the journal says near where. Come back within `RESUME_M` and they fall in again.
## * **They die.** The quest fails, and the journal says who, and on the way to where.
##
## The walking is the person's own; what this keeps is the roster's record of it — `escort`,
## `escort_pos` and `escort_left` on their state in the `npcs` save section — so a save made on
## the road loads on the road, with them standing where they were.

const GROUP := "escorts"
const LEFT_BEHIND_M := 60.0
const RESUME_M := 14.0
const DEFAULT_RADIUS_M := 45.0
const INTERVAL := 0.25

@export var enabled := true

var _since := 0.0


static func ensure() -> Escorts:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is Escorts:
		return found as Escorts
	var made := Escorts.new()
	made.name = "Escorts"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


func _ready() -> void:
	add_to_group(GROUP)


func _process(delta: float) -> void:
	if not enabled:
		return
	_since += delta
	if _since < INTERVAL:
		return
	_since = 0.0
	tick()


## Every escort, advanced by one look. Safe to call at any time, and what the tests drive.
func tick() -> void:
	var log_node := _quest_log()
	var registry := NpcRegistry.instance
	if log_node == null or registry == null or not is_instance_valid(registry):
		return
	var due := due_escorts(log_node)
	# anybody still walking for an escort that is no longer due goes back to their own life:
	# the quest failed, was abandoned, or an author's line closed the objective by hand
	for npc_id in registry.escorted_ids():
		if not due.has(npc_id):
			_release(registry, npc_id)
	for npc_id in due:
		_advance(log_node, registry, str(npc_id), due[npc_id])


## {npc_id: {quest_id, index, objective}} for every escort objective that is under way now.
static func due_escorts(log_node: Object) -> Dictionary:
	var out: Dictionary = {}
	if log_node == null or not log_node.has_method("current_objectives"):
		return out
	for entry in log_node.call("current_objectives", "escort"):
		if bool(entry["done"]):
			continue
		var o: Dictionary = entry["objective"]
		var npc_id := str(o.get("target", ""))
		if npc_id == "" or out.has(npc_id):
			continue
		if not _spoken_to(log_node, str(entry["quest_id"]), npc_id):
			continue
		var requires: Variant = o.get("requires", [])
		if typeof(requires) == TYPE_ARRAY and not (requires as Array).is_empty():
			if Social.ctx == null or not Conditions.all_of(requires, Social.ctx):
				continue
		out[npc_id] = {"quest_id": str(entry["quest_id"]), "index": int(entry["index"]), "objective": o}
	return out


## Whether every `talk` objective in the same stage that is aimed at the traveller is done.
static func _spoken_to(log_node: Object, quest_id: String, npc_id: String) -> bool:
	for entry in log_node.call("current_objectives", "talk"):
		if str(entry["quest_id"]) != quest_id:
			continue
		if str((entry["objective"] as Dictionary).get("target", "")) == npc_id and not bool(entry["done"]):
			return false
	return true


func _advance(log_node: Node, registry: NpcRegistry, npc_id: String, job: Dictionary) -> void:
	var quest_id: String = job["quest_id"]
	var o: Dictionary = job["objective"]
	var place := str(o.get("place", ""))
	var who := _name_of(npc_id)
	if not registry.is_alive(npc_id):
		registry.end_escort(npc_id)
		log_node.call("fail", quest_id, "%s died on the road to %s." % [who, _name_of(place)])
		return
	var body := registry.actor(npc_id) as Node3D
	if not registry.is_escorted(npc_id):
		var from := body.global_position if body != null else WorldProbe.place_position(registry.place_of(npc_id))
		registry.begin_escort(npc_id, quest_id, from)
		log_node.call("note", quest_id, "%s falls in beside you." % who)
	var player := Peers.player() as Node3D
	if body == null or player == null or not body.is_inside_tree():
		# Nobody is stood up: the roster keeps where they were, and the streamer brings them up
		# there when the player comes back near enough to see them.
		return
	registry.set_escort_position(npc_id, body.global_position)
	if place == "":
		return
	var there := WorldProbe.place_position(place)
	if _flat(body.global_position, there) <= float(o.get("radius", DEFAULT_RADIUS_M)):
		_arrive(registry, body, npc_id, place)
		return
	var gap := _flat(body.global_position, player.global_position)
	if registry.escort_left(npc_id):
		if gap <= RESUME_M:
			registry.set_escort_left(npc_id, false)
			_follow(body, player)
			log_node.call("note", quest_id, "%s falls in beside you again." % who)
		return
	if gap > LEFT_BEHIND_M:
		registry.set_escort_left(npc_id, true)
		if body.has_method("stop_following"):
			body.call("stop_following")
		var near := WorldProbe.nearest_place(body.global_position, 1500.0)
		var where := " near %s" % str(near.get("name", "")) if not near.is_empty() else ""
		log_node.call("note", quest_id, "You left %s behind on the road%s, waiting where you last walked together." % [who, where])
		EventBus.notify.emit("%s has stopped. You have left them behind." % who, "quest")
		return
	_follow(body, player)


## They are there. The roster stops walking them and has them stand at the place while the player
## is about; then the bus says so, and the quest log closes the objective.
func _arrive(registry: NpcRegistry, body: Node3D, npc_id: String, place: String) -> void:
	if body.has_method("stop_following"):
		body.call("stop_following")
	registry.end_escort(npc_id, place)
	Log.info("Escorts", "%s arrived at %s" % [npc_id, place])
	EventBus.escort_arrived.emit(npc_id, place)


func _release(registry: NpcRegistry, npc_id: String) -> void:
	var body := registry.actor(npc_id)
	if body != null and body.has_method("stop_following"):
		body.call("stop_following")
	registry.end_escort(npc_id)


static func _follow(body: Node3D, player: Node3D) -> void:
	if not body.has_method("follow"):
		return
	if body.has_method("is_following") and bool(body.call("is_following")):
		return
	body.call("follow", player)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _name_of(id: String) -> String:
	var def := ContentDB.get_or_empty(id)
	return str(def.get("name", Ids.name_of(id).replace("_", " ").capitalize()))


func _quest_log() -> Node:
	var social := Peers.social()
	if social != null and "quests" in social:
		return social.get("quests") as Node
	return get_tree().get_first_node_in_group("quest_log") if is_inside_tree() else null
