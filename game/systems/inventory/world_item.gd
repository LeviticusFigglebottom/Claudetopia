class_name WorldItem
extends StaticBody3D
## A pickup lying in the world: an item stack (with instance data) or a purse of marks.
## Interaction: the node is in group "interactable" on physics layer 5; the player's interaction
## ray calls prompt_text() and interact(actor). The actor must carry an Inventory
## (see Inventory.for_actor). The visual is the item def's `model` when the file exists,
## otherwise a generated placeholder mesh coloured by category.

signal picked_up(actor: Node)

const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"

@export var item_id: String = ""
@export var count: int = 1
@export var marks: int = 0
@export var bob: bool = true
## Whose it is, if it is anybody's. A loaf on a stranger's table is theirs; a loaf dropped by a
## bandit is nobody's, and taking the second is not a crime.
@export var owner_npc: String = ""
@export var owner_faction: String = ""
var data: Dictionary = {}

var _visual: Node3D = null
var _phase := 0.0
var _rest_y := 0.0


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = INTERACT_LAYER
	collision_mask = 0
	_phase = randf() * TAU
	rebuild()


func _process(delta: float) -> void:
	if not bob or _visual == null:
		return
	_phase += delta
	_visual.rotation.y += delta * 0.8
	_visual.position.y = _rest_y + sin(_phase * 2.0) * 0.03


## Configure before or after adding to the tree.
func setup(id: String, amount: int = 1, instance_data: Dictionary = {}, purse: int = 0) -> void:
	item_id = id
	count = amount
	data = instance_data.duplicate(true)
	marks = purse
	if is_inside_tree():
		rebuild()


func def() -> Dictionary:
	return ContentDB.get_or_empty(item_id)


func is_purse() -> bool:
	return item_id == "" and marks > 0


func display_name() -> String:
	if is_purse():
		return "%d marks" % marks
	var stack := ItemStack.new(item_id, count, data)
	var label := stack.display_name()
	if count > 1:
		label += " x%d" % count
	if marks > 0:
		label += " and %d marks" % marks
	return label


func prompt_text() -> String:
	return "Take %s" % display_name()


## Moves the contents into the actor's inventory and removes this node. Returns false if the
## actor has no inventory or the item is unknown (nothing is taken then).
func interact(actor: Node) -> bool:
	var inv := Inventory.for_actor(actor)
	if inv == null:
		Log.warn("WorldItem", "%s interacted with by an actor without an Inventory" % name)
		return false
	if item_id != "" and count > 0:
		if inv.add(item_id, count, data) == null:
			return false
	if marks > 0:
		inv.add_marks(marks)
	CrimeReports.theft(actor, global_position, _worth(), owner_npc, owner_faction, item_id)
	picked_up.emit(actor)
	queue_free()
	return true


## What taking this is worth to whoever owned it, in marks.
func _worth() -> int:
	if marks > 0:
		return marks
	if item_id == "":
		return 0
	return int(ContentDB.get_or_empty(item_id).get("value", 0)) * maxi(count, 1)


## (Re)builds the visual and collision from the current item.
func rebuild() -> void:
	if _visual != null:
		_visual.queue_free()
		_visual = null
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var d := def()
	var model := str(d.get("model", ""))
	if model != "" and ResourceLoader.exists(model):
		var res: Resource = load(model)
		if res is PackedScene:
			_visual.add_child((res as PackedScene).instantiate())
		elif res is Mesh:
			var mi := MeshInstance3D.new()
			mi.mesh = res
			_visual.add_child(mi)
	if _visual.get_child_count() == 0:
		_visual.add_child(placeholder_mesh(d, is_purse()))
	_rest_y = _visual.position.y
	var shape := get_node_or_null("Shape") as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new()
		shape.name = "Shape"
		add_child(shape)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	shape.shape = sphere
	shape.position = Vector3(0, 0.2, 0)


## A generated stand-in mesh: shape and colour by category (no asset files needed).
static func placeholder_mesh(d: Dictionary, purse: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Placeholder"
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.7
	var color := Color(0.6, 0.6, 0.6)
	var mesh: Mesh = null
	var tags: Array = d.get("tags", [])
	if purse:
		var sp := SphereMesh.new()
		sp.radius = 0.1
		sp.height = 0.2
		mesh = sp
		color = Color(0.85, 0.68, 0.25)
		mat.metallic = 0.6
		mat.roughness = 0.35
	else:
		match str(d.get("category", "misc")):
			"weapon":
				var b := BoxMesh.new()
				var long := 0.9
				if d.has("weapon"):
					long = clampf(float(d["weapon"].get("reach", 1.5)) * 0.5, 0.35, 1.2)
					if str(d["weapon"].get("class", "")) == "shield":
						long = 0.6
				b.size = Vector3(0.08, long, 0.04)
				mesh = b
				color = Color(0.55, 0.57, 0.6)
				if tags.has("bell_bronze"):
					color = Color(0.72, 0.52, 0.28)
				elif tags.has("ashen"):
					color = Color(0.22, 0.22, 0.24)
				elif tags.has("bow") or tags.has("staff"):
					color = Color(0.45, 0.32, 0.2)
				mat.metallic = 0.5
				mat.roughness = 0.45
				mi.rotation_degrees = Vector3(0, 0, 80)
			"armour":
				var b := BoxMesh.new()
				b.size = Vector3(0.35, 0.25, 0.15)
				if tags.has("ring") or tags.has("amulet"):
					var t := TorusMesh.new()
					t.inner_radius = 0.04
					t.outer_radius = 0.07
					mesh = t
					color = Color(0.8, 0.65, 0.3)
					mat.metallic = 0.7
					mat.roughness = 0.3
				else:
					mesh = b
					color = Color(0.45, 0.32, 0.22)
					if tags.has("iron") or tags.has("brigandine"):
						color = Color(0.4, 0.42, 0.45)
					elif tags.has("bone") or tags.has("clan_plate"):
						color = Color(0.85, 0.82, 0.72)
					elif tags.has("wool") or tags.has("linen") or tags.has("gambeson"):
						color = Color(0.78, 0.72, 0.6)
			"consumable":
				if tags.has("potion"):
					var c := CylinderMesh.new()
					c.top_radius = 0.035
					c.bottom_radius = 0.05
					c.height = 0.18
					mesh = c
					color = Color(0.7, 0.2, 0.25) if not tags.has("poison") else Color(0.3, 0.55, 0.2)
					mat.roughness = 0.2
				else:
					var b := BoxMesh.new()
					b.size = Vector3(0.16, 0.08, 0.16)
					mesh = b
					color = Color(0.78, 0.6, 0.35)
			"ingredient":
				var sp := SphereMesh.new()
				sp.radius = 0.07
				sp.height = 0.14
				mesh = sp
				color = Color(0.35, 0.6, 0.25)
				if tags.has("poison"):
					color = Color(0.55, 0.2, 0.5)
				elif tags.has("fungus") or tags.has("moss"):
					color = Color(0.5, 0.5, 0.3)
			"material":
				var b := BoxMesh.new()
				b.size = Vector3(0.25, 0.08, 0.1)
				mesh = b
				color = Color(0.5, 0.45, 0.4)
				if tags.has("metal"):
					color = Color(0.5, 0.5, 0.55)
					mat.metallic = 0.6
				elif tags.has("wood"):
					color = Color(0.5, 0.36, 0.22)
				elif tags.has("cloth"):
					color = Color(0.85, 0.82, 0.75)
				elif tags.has("ember"):
					color = Color(1.0, 0.55, 0.2)
					mat.emission_enabled = true
					mat.emission = Color(1.0, 0.45, 0.1)
					mat.emission_energy_multiplier = 1.5
			"key":
				var b := BoxMesh.new()
				b.size = Vector3(0.12, 0.03, 0.02)
				mesh = b
				color = Color(0.3, 0.3, 0.32)
				mat.metallic = 0.6
			"tool":
				var c := CylinderMesh.new()
				c.top_radius = 0.05
				c.bottom_radius = 0.05
				c.height = 0.3
				mesh = c
				color = Color(0.45, 0.35, 0.25)
			"book":
				var b := BoxMesh.new()
				b.size = Vector3(0.18, 0.04, 0.24)
				mesh = b
				color = Color(0.5, 0.3, 0.2)
			_:
				var b := BoxMesh.new()
				b.size = Vector3(0.12, 0.12, 0.12)
				mesh = b
	mat.albedo_color = color
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = 0.15
	return mi
