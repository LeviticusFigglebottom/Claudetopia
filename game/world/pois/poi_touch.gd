class_name PoiTouch
extends StaticBody3D
## Something at a point of interest that can be touched, and what touching it sets off.
##
## The Cold Fire Camp's sentence is "they only rise if you touch the cup": Greyfold's dead sit
## round a fire that went out a hundred and seventy years ago, passing a cup, and wave. A
## `PoiEncounters` group with `rises_when` naming one of these sits deaf and blind until it is
## touched. The dressing puts it down (`PoiKit.touchable`) where the thing it stands for lies.

signal touched(actor: Node)

const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"

## What the interaction prompt says.
@export var prompt := "Touch it"
## Once touched, is that the end of it? (The cup, yes: they have risen.)
@export var once := true

var times_touched := 0


func _ready() -> void:
	add_to_group("interactable")
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


func prompt_text() -> String:
	return prompt


func interact(actor: Node) -> void:
	if once and times_touched > 0:
		return
	times_touched += 1
	touched.emit(actor)
	if once:
		# nothing left to walk up to
		collision_layer = 0
