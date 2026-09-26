class_name WorldItem
extends StaticBody3D
## A pickup lying in the world: an item stack (with instance data) or a purse of marks.
## Interaction: the node is in group "interactable" on physics layer 5; the player's interaction
## ray calls prompt_text() and interact(actor). The actor must carry an Inventory
## (see Inventory.for_actor). The visual is the item def's `model` when the file exists, otherwise
## the forge's own prop that fits it (systems/inventory/item_look.gd). The generated stand-in box
## (placeholder_mesh) is drawn only in a debug build, for an item nothing answers, which is logged
## as a content error; a release build draws nothing there rather than a test cube.

signal picked_up(actor: Node)

const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"
const ITEM_LOOK := preload("res://systems/inventory/item_look.gd")

@export var item_id: String = ""
@export var count: int = 1
@export var marks: int = 0
@export var bob: bool = true
## Whose it is, if it is anybody's. A loaf on a stranger's table is theirs; a loaf dropped by a
## bandit is nobody's, and taking the second is not a crime.
@export var owner_npc: String = ""
@export var owner_faction: String = ""
## A forge prop to wear instead of the item's own model: a deep place's meta names the asset its
## `item` feature was set down as (a book on a cist's ledge), and that is what should be picked up.
@export var visual_path: String = ""
var data: Dictionary = {}
## Let fall from somebody's bag (Inventory.drop) rather than found where it grew or fell.
var from_bag: bool = false

var _visual: Node3D = null
var _phase := 0.0
var _rest_y := 0.0
## The glint (see _make_glint): a soft painted star that flares now and then, so a sword in the
## ash can be seen from further than it can be told apart.
var _glint: MeshInstance3D = null
var _glint_mat: StandardMaterial3D = null
var _glint_strong := false

## Seconds between glints, the flare's length, and how far a glint is seen (weapons, armour and
## what a quest asks for further). It fades out as you come within GLINT_NEAR_M, where the thing
## itself is plain to see.
const GLINT_EVERY_S := 3.2
const GLINT_FLARE_S := 0.7
const GLINT_FAR_M := 26.0
const GLINT_FAR_STRONG_M := 40.0
const GLINT_NEAR_M := 4.0


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = INTERACT_LAYER
	collision_mask = 0
	_phase = randf() * TAU
	rebuild()


func _process(delta: float) -> void:
	_phase += delta
	if _glint != null:
		_glint_step()
	if not bob or _visual == null:
		return
	_visual.rotation.y += delta * 0.8
	_visual.position.y = _rest_y + sin(_phase * 2.0) * 0.03


## A glint flares for GLINT_FLARE_S every GLINT_EVERY_S, each item at its own moment, and fades as
## the eye comes near; off with the setting gameplay/pickup_glint.
func _glint_step() -> void:
	var on := bool(Settings.get_value("gameplay", "pickup_glint", true))
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if not on or cam == null:
		_glint.visible = false
		return
	var t := fmod(_phase, GLINT_EVERY_S)
	var flare := 0.0
	if t < GLINT_FLARE_S:
		flare = sin(t / GLINT_FLARE_S * PI)
		flare *= flare
	var d := cam.global_position.distance_to(global_position)
	var near := clampf((d - GLINT_NEAR_M * 0.5) / (GLINT_NEAR_M * 0.5), 0.0, 1.0)
	var a := flare * near * (0.9 if _glint_strong else 0.6)
	_glint.visible = a > 0.01
	if _glint.visible:
		_glint_mat.albedo_color.a = a
		# the star grows a little with distance, so it reads at the edge of its range
		var s := clampf(d / 18.0, 0.6, 1.6) * (1.25 if _glint_strong else 1.0)
		_glint.scale = Vector3.ONE * s


## A soft four-pointed star, warm white, additive, always facing the eye: the painted kind of
## glint, not a lens flare. Seen to GLINT_FAR_M, or GLINT_FAR_STRONG_M for weapons, armour and
## a quest's things.
func _make_glint(top: float) -> void:
	if _glint != null:
		_glint.queue_free()
	var d := def()
	_glint_strong = str(d.get("category", "")) in ["weapon", "armour"] or (d.get("tags", []) as Array).has("quest") 			or str(name).begins_with("QuestItem_")
	_glint = MeshInstance3D.new()
	_glint.name = "Glint"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	_glint.mesh = quad
	_glint_mat = StandardMaterial3D.new()
	_glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glint_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glint_mat.no_depth_test = false
	_glint_mat.albedo_color = Color(1.0, 0.93, 0.78, 0.0)
	_glint_mat.albedo_texture = _star_texture()
	_glint.material_override = _glint_mat
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.position = Vector3(0.0, top + 0.12, 0.0)
	_glint.visibility_range_end = GLINT_FAR_STRONG_M if _glint_strong else GLINT_FAR_M
	_glint.visibility_range_end_margin = 6.0
	_glint.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_glint.visible = false
	add_child(_glint)


static var _star: Texture2D = null


## Made once: a soft round glow with a thin cross through it, brightest at the middle.
static func _star_texture() -> Texture2D:
	if _star != null:
		return _star
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var glow := pow(clampf(1.0 - r, 0.0, 1.0), 2.2)
			var cross := pow(clampf(1.0 - absf(u) * 9.0, 0.0, 1.0), 2.0) * clampf(1.0 - absf(v), 0.0, 1.0) 					+ pow(clampf(1.0 - absf(v) * 9.0, 0.0, 1.0), 2.0) * clampf(1.0 - absf(u), 0.0, 1.0)
			var a := clampf(glow * 0.8 + cross * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_star = ImageTexture.create_from_image(img)
	return _star


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
		var amount := count
		if is_gathering():
			# Forager: one more of every ingredient picked.
			amount += maxi(int(round((actor as Actor).stat_add("ingredient_yield"))), 0) if actor is Actor else 0
		if inv.add(item_id, amount, data) == null:
			return false
	if marks > 0:
		inv.add_marks(marks)
	CrimeReports.theft(actor, global_position, _worth(), owner_npc, owner_faction, item_id)
	picked_up.emit(actor)
	queue_free()
	return true


## Whether taking this is gathering it: an ingredient lying where it grew or fell, not one somebody
## owns and not one the taker let fall from a bag.
func is_gathering() -> bool:
	return not from_bag and owner_npc.is_empty() and owner_faction.is_empty() and str(def().get("category", "")) == "ingredient"


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
	# bobbed and turned every frame in _process: interpolating it between ticks would stutter it
	_visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_visual)
	var d := def()
	var region := World.region_id_at(global_position) if is_inside_tree() else ""
	if visual_path != "" and ResourceLoader.exists(visual_path):
		var res: Resource = load(visual_path)
		if res is PackedScene:
			_visual.add_child((res as PackedScene).instantiate())
		elif res is Mesh:
			var mi := MeshInstance3D.new()
			mi.mesh = res
			_visual.add_child(mi)
	if _visual.get_child_count() == 0:
		# the forge's own thing that fits (ItemLook), never the stand-in box
		var model := ITEM_LOOK.purse_model(region) if is_purse() else ITEM_LOOK.model_for(d, region)
		var shown: Node3D = ITEM_LOOK.instance(model, 0.35 if is_purse() else ITEM_LOOK.MOST_M) if model != "" else null
		if shown != null:
			_visual.add_child(shown)
		else:
			Log.error("WorldItem", "content: no model for %s (ItemLook found no forge prop for it)" % (item_id if item_id != "" else "a purse"))
			if OS.is_debug_build():
				_visual.add_child(placeholder_mesh(d, is_purse()))
	_rest_y = _visual.position.y
	_make_glint(_top_of(_visual))
	var shape := get_node_or_null("Shape") as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new()
		shape.name = "Shape"
		add_child(shape)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	shape.shape = sphere
	shape.position = Vector3(0, 0.2, 0)


func _top_of(n: Node3D) -> float:
	var top := 0.25
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := (n.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if mi.is_inside_tree() and n.is_inside_tree() 				else mi.transform * mi.get_aabb()
		top = maxf(top, box.end.y)
	return minf(top, 1.2)


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
