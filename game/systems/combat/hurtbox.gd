class_name Hurtbox
extends Area3D
## The part of an actor that can be hit (physics layer "hurtbox"). It does no detection itself;
## Hitboxes and Projectiles find it and call receive_hit(), which forwards to actor.take_hit().

signal hit_received(hit: HitData, outcome: String)

const LAYER_HURTBOX := 1 << 5   # 3d_physics layer 6

## The actor that owns this hurtbox (anything with take_hit(hit) -> String).
var actor: Node = null
var enabled: bool = true


static func create(owner_actor: Node, radius: float, height: float, centre_y: float) -> Hurtbox:
	var hb := Hurtbox.new()
	hb.name = "Hurtbox"
	hb.actor = owner_actor
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	shape.shape = capsule
	shape.position = Vector3(0.0, centre_y, 0.0)
	hb.add_child(shape)
	return hb


func _ready() -> void:
	collision_layer = LAYER_HURTBOX
	collision_mask = 0
	monitoring = false
	monitorable = true
	if actor == null:
		actor = _find_actor()


func _find_actor() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("take_hit"):
			return n
		n = n.get_parent()
	return null


func receive_hit(hit: HitData) -> String:
	if not enabled or actor == null or not is_instance_valid(actor):
		return "immune"
	var outcome: String = actor.take_hit(hit)
	hit_received.emit(hit, outcome)
	return outcome


func set_enabled(value: bool) -> void:
	enabled = value
	set_deferred("monitorable", value)
