class_name PoiTouch
extends StaticBody3D
## Something at a point of interest that can be touched, and what touching it sets off.
##
## The Cold Fire Camp's sentence is "they only rise if you touch the cup": Greyfold's dead sit
## round a fire that went out a hundred and seventy years ago, passing a cup, and wave. A
## `PoiEncounters` group with `rises_when` naming one of these sits deaf and blind until it is
## touched. The One Poppy's is "a Hollow deed if picked, a Hearth deed if watered": with a
## `dialogue_id`, touching it puts that conversation, with nobody in it, and what the choices do
## is the dialogue's business. With a `gone_flag`, the thing is gone (and what it holds with it)
## once that flag is set: a poppy picked stays picked. The dressing puts one down
## (`PoiKit.touchable`) where the thing it stands for lies.

signal touched(actor: Node)

const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"

## What the interaction prompt says.
@export var prompt := "Touch it"
## Once touched, is that the end of it? (The cup, yes: they have risen.)
@export var once := true
## A conversation with nobody in it, put when this is touched.
@export var dialogue_id := ""
## Gone, with whatever it holds, once this flag is set.
@export var gone_flag := ""

var times_touched := 0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("poi_touch")
	collision_layer = INTERACT_LAYER
	collision_mask = 0
	if get_node_or_null("Shape") == null:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var sphere := SphereShape3D.new()
		sphere.radius = 0.45
		shape.shape = sphere
		shape.position.y = 0.3
		add_child(shape)
	if gone_flag != "":
		# method reference, not a closure: the bus outlives this node
		EventBus.dialogue_ended.connect(_on_dialogue_ended)
	check_gone()


func prompt_text() -> String:
	return prompt


func interact(actor: Node) -> void:
	if is_gone() or (once and times_touched > 0):
		return
	times_touched += 1
	touched.emit(actor)
	if dialogue_id != "":
		Social.dialogue.start(dialogue_id, "", "")
	elif once:
		# nothing left to walk up to
		collision_layer = 0


func is_gone() -> bool:
	return gone_flag != "" and GameState.has_flag(gone_flag)


## Once its flag is set it is not there: hidden, and nothing to walk up to.
func check_gone() -> void:
	if not is_gone():
		return
	visible = false
	collision_layer = 0


func _on_dialogue_ended(_npc_id: String) -> void:
	check_gone()
