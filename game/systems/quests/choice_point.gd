class_name ChoicePoint
extends StaticBody3D
## A decision with nobody left to put it to you.
##
## The main thread ends on a choice — let the note end, hold it, or sing a new one — made in the
## Cantor's Seat after its holder has fallen, and there was no button for it anywhere, because
## there is nobody left in the room to have a conversation with. `QuestItems` puts one of these
## where the choice's `with` names; while the choice is open it is a cold light you can walk up
## to, and walking up to it puts the open options as a conversation with nobody in it, headed
## with the stage's own journal. Once decided, it goes dark and cannot be walked up to.

const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"
const COLD := Color(0.62, 0.78, 1.0)

@export var quest_id := ""
@export var stage_id := ""
@export var objective_index := 0
## What the interaction prompt says (the objective's own text).
@export var prompt := ""
## Who the nameplate says is speaking: the place, since there is nobody.
@export var speaker := ""

var _light: OmniLight3D = null
var _mote: MeshInstance3D = null


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("choice_point")
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	shape.shape = sphere
	shape.position.y = 1.1
	add_child(shape)
	_mote = MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.16
	orb.height = 0.32
	_mote.mesh = orb
	_mote.position.y = 1.25
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLD
	mat.emission_enabled = true
	mat.emission = COLD
	mat.emission_energy_multiplier = 3.0
	_mote.material_override = mat
	add_child(_mote)
	_light = OmniLight3D.new()
	_light.light_color = COLD
	_light.omni_range = 7.0
	_light.light_energy = 1.6
	_light.position.y = 1.4
	add_child(_light)
	# method references, not closures: the bus outlives this node
	EventBus.quest_stage_changed.connect(_on_quest_changed)
	EventBus.quest_completed.connect(_on_quest_finished)
	refresh()


func _on_quest_changed(_quest: String, _stage: int) -> void:
	refresh()


func _on_quest_finished(_quest: String, _outcome: String) -> void:
	refresh()


## Open while the quest is at the stage and something is left to decide.
func is_open() -> bool:
	var log_node: Node = Social.quests
	if log_node == null or not log_node.is_active(quest_id) or log_node.stage_id_of(quest_id) != stage_id:
		return false
	return not log_node.open_options(quest_id).is_empty()


## Something to walk up to only while there is something to decide.
func refresh() -> void:
	var open := is_open()
	collision_layer = INTERACT_LAYER if open else 0
	visible = open


func prompt_text() -> String:
	return prompt if prompt != "" else "Decide"


func interact(_actor: Node) -> void:
	if not is_open():
		return
	Social.dialogue.start_def(conversation(), "", "")


## The stage's journal, its open options, and a way to leave it for now.
func conversation() -> Dictionary:
	var log_node: Node = Social.quests
	var stage: Dictionary = log_node.stage_def(quest_id, log_node.stage_of(quest_id))
	var choices: Array = []
	for option in log_node.open_options(quest_id):
		choices.append({"text": str(option["text"]), "next": "end",
				"effects": [{"quest_choice": [quest_id, str(option["id"])]}]})
	choices.append({"text": "Not yet.", "next": "end"})
	return {"id": "", "speaker_name": speaker if speaker != "" else prompt_text(), "start": "put",
			"nodes": {"put": {"speaker": "npc", "text": str(stage.get("journal", "")), "choices": choices}}}
