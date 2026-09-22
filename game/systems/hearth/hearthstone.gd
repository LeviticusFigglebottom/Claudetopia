class_name Hearthstone
extends StaticBody3D
## A Hearthstone: a place where a name is kept. Rest to restore, set your return point and
## reset the deep places. The flame lights when first used.

const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"

@export var hearthstone_id := ""
@export var display_name := "Hearthstone"
@export var place_id := ""

var _flame: OmniLight3D
var _ember: MeshInstance3D


func _ready() -> void:
	add_to_group("interactable")
	# The physics layer the player's interaction ray masks. It used to be set only in this
	# class's .tscn, so a node built with `.new()` kept Godot's default layer 1 and the ray
	# went straight through it — visible, in the group, with an `interact()` method, and
	# impossible to walk up to. `container.gd` and `world_item.gd` always set their own.
	collision_layer = INTERACT_LAYER
	add_to_group("hearthstone")
	if hearthstone_id.is_empty():
		hearthstone_id = name
	_build_visual()
	_update_flame()
	# A method reference, not a closure: stones are streamed in and out with the world, and
	# a closure on the bus outlives the stone that made it.
	EventBus.hearthstone_rested.connect(_on_hearthstone_rested)


func _on_hearthstone_rested(_id: String) -> void:
	_update_flame()


func prompt_text() -> String:
	return "Rest at the %s" % display_name


func interact(actor: Node) -> void:
	if not actor.is_in_group("player"):
		return
	var yaw := 0.0
	if actor is Node3D:
		yaw = (actor as Node3D).global_rotation.y
	Hearth.rest_at(hearthstone_id, global_position + global_transform.basis.z * 1.2 + Vector3.UP * 0.1, yaw)
	if not place_id.is_empty():
		GameState.discover(place_id)
	EventBus.notify.emit("You rest at the %s. Your name is kept here." % display_name, "info")


func _build_visual() -> void:
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = 1.4
	col.shape = shape
	col.position.y = 0.7
	add_child(col)
	var stone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.42
	cm.height = 1.3
	stone.mesh = cm
	stone.position.y = 0.65
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.42, 0.40, 0.38)
	sm.roughness = 0.9
	stone.material_override = sm
	add_child(stone)
	_ember = MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.12
	em.height = 0.24
	_ember.mesh = em
	_ember.position.y = 1.42
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(1.0, 0.75, 0.35)
	emat.emission_enabled = true
	emat.emission = Color(1.0, 0.6, 0.2)
	emat.emission_energy_multiplier = 3.0
	_ember.material_override = emat
	add_child(_ember)
	_flame = OmniLight3D.new()
	_flame.position.y = 1.6
	_flame.light_color = Color(1.0, 0.72, 0.4)
	_flame.omni_range = 9.0
	_flame.light_energy = 2.2
	_flame.shadow_enabled = false
	add_child(_flame)


func _update_flame() -> void:
	var lit := Hearth.is_lit(hearthstone_id)
	_flame.visible = lit
	_ember.visible = lit


func _process(delta: float) -> void:
	if _flame.visible:
		_flame.light_energy = 2.0 + 0.35 * sin(Time.get_ticks_msec() * 0.011) + 0.15 * sin(Time.get_ticks_msec() * 0.037)
