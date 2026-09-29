class_name RoadTalk
extends Area3D
## What the interact key finds on somebody met on the road who is stood up as a foe's body (a
## caravan's trader and guards, a patrol, the hunters after a fugitive): a sphere on the
## interaction layer (Interactor) that says the cast entry's `talk.prompt` and hands the press to
## its event (RoadEvent.talk). Gone once its body is fighting, dead, or has nothing to say.

const INTERACT_LAYER := 1 << 4

var event: Node = null
var actor: Node3D = null
var prompt := ""


func _init() -> void:
	name = "RoadTalk"
	collision_layer = INTERACT_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	shape.shape = sphere
	shape.position.y = 1.1
	add_child(shape)


var _look := 0.0


func _process(delta: float) -> void:
	_look -= delta
	if _look > 0.0:
		return
	_look = 0.5
	collision_layer = INTERACT_LAYER if available() else 0


func prompt_text() -> String:
	return prompt if available() else ""


## Whether there is anything to say: the body alive and not fighting, and a prompt.
func available() -> bool:
	if prompt == "" or event == null or not is_instance_valid(event):
		return false
	if actor is Enemy:
		var e := actor as Enemy
		if e.dead or (e.brain != null and e.brain.is_fighting()):
			return false
	return true


func interact(who: Node) -> void:
	if available():
		event.call("talk", actor, who)
