class_name Hitbox
extends Area3D
## A weapon/attack volume (physics layer "hitbox"). Opened by begin_swing(hit) on the hit_start
## clip event and closed by end_swing() on hit_end. Each Hurtbox is hit at most once per swing.
## The capsule lies along local −Z (gameplay forward), from 0 to −length.

signal hit_landed(hurtbox: Hurtbox, hit: HitData, outcome: String)

const LAYER_HITBOX := 1 << 6   # 3d_physics layer 7
const MASK_HURTBOX := 1 << 5   # 3d_physics layer 6

var owner_actor: Node = null
var active: bool = false
var hit: HitData = null
var swing_id: int = 0
var shape_node: CollisionShape3D = null

var _hit_targets: Dictionary = {}   # victim instance id -> true


static func create(actor: Node, radius: float, length: float) -> Hitbox:
	var hb := Hitbox.new()
	hb.name = "Hitbox"
	hb.owner_actor = actor
	hb.set_capsule(radius, length)
	return hb


func _ready() -> void:
	collision_layer = LAYER_HITBOX
	collision_mask = MASK_HURTBOX
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	if shape_node == null:
		set_capsule(0.35, 1.2)


func set_capsule(radius: float, length: float) -> void:
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "Shape"
		add_child(shape_node)
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(radius, 0.05)
	capsule.height = maxf(length, capsule.radius * 2.0)
	shape_node.shape = capsule
	# capsule axis is Y; lay it along Z and push it forward so it spans [0, -length]
	shape_node.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	shape_node.position = Vector3(0.0, 0.0, -length * 0.5)


func begin_swing(new_hit: HitData) -> void:
	swing_id += 1
	hit = new_hit
	hit.swing_id = swing_id
	_hit_targets.clear()
	active = true
	_sweep()


func end_swing() -> void:
	active = false
	hit = null


func _physics_process(_delta: float) -> void:
	if active:
		_sweep()


func _sweep() -> void:
	for a in get_overlapping_areas():
		_try_hit(a)


func _on_area_entered(a: Area3D) -> void:
	if active:
		_try_hit(a)


func _try_hit(a: Area3D) -> void:
	if hit == null or not (a is Hurtbox):
		return
	var hurtbox := a as Hurtbox
	var target: Node = hurtbox.actor
	if target == null or target == owner_actor:
		return
	var key := target.get_instance_id()
	if _hit_targets.has(key):
		return
	if owner_actor != null and owner_actor.has_method("is_hostile_to") and not owner_actor.is_hostile_to(target):
		return
	_hit_targets[key] = true
	var h := hit.copy()
	h.source = self
	if owner_actor is Node3D:
		h.origin = (owner_actor as Node3D).global_position
	else:
		h.origin = global_position
	var outcome := hurtbox.receive_hit(h)
	hit_landed.emit(hurtbox, h, outcome)
