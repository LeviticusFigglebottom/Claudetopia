class_name RoadFolk
extends Npc
## Somebody met on the road who is nobody's in the registry: a pilgrim, a lost traveller, a carter
## by a broken cart, a pedlar walking the roads, a runaway. A plain Npc body -- dressed, walking,
## passing round people -- stood up by a RoadEvent from its cast entry's `folk` block ({name,
## appearance, tags, home}), with no npc id, so no schedule, registry or quest reaches for them,
## and gone when the event is. The interact key is the event's: the entry's `talk.prompt`, and the
## press goes to RoadEvent.talk. A `pose` (Sit_Idle, Cower, Sleep_Idle) holds them in it instead
## of the idle life's beats.

var event: Node = null
var prompt := ""
var pose := ""
var cast_index := -1


## A body for `folk`, before it enters the tree (its def is read in _ready).
static func make(folk: Dictionary, seed_value: int, home_place: String) -> RoadFolk:
	var node := (load(NPC_SCENE_PATH) as PackedScene).instantiate()
	node.set_script(load("res://systems/roads/road_folk.gd"))
	var body := node as RoadFolk
	var look: Dictionary = (folk.get("appearance", {}) as Dictionary).duplicate(true) if folk.get("appearance") is Dictionary else {}
	if not look.has("seed"):
		look["seed"] = seed_value
	body.def = {"name": str(folk.get("name", "A traveller")), "tags": folk.get("tags", ["person"]),
			"appearance": look, "home_place": str(folk.get("home", home_place))}
	body.name = "RoadFolk"
	return body


const NPC_SCENE_PATH := "res://actors/npc/npc.tscn"


func _ready() -> void:
	add_to_group("road_folk_people")
	super._ready()
	place_id = ""


func prompt_text() -> String:
	if not alive:
		return "%s (dead)" % display_name()
	return prompt


func interact(actor: Node) -> void:
	if not alive or prompt == "":
		return
	stop()
	if actor is Node3D:
		face_direction((actor as Node3D).global_position - global_position)
	if pose == "":
		play_intent("Talk_1", true)
	if event != null and is_instance_valid(event):
		event.call("talk", self, actor)


func _can_live() -> bool:
	if pose != "":
		play_intent(pose)
		return false
	return super._can_live()


## Holds `clip` (or lets go of a held pose with "").
func hold_pose(clip: String) -> void:
	pose = clip
	if clip != "":
		stop()
		play_intent(clip, true)
	else:
		play_intent("Idle", true)
