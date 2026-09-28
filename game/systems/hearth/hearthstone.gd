class_name Hearthstone
extends StaticBody3D
## A Hearthstone: a place where a name is kept. Rest to restore, set your return point and
## reset the deep places. The flame lights when first used.
## Once rested at, while you stay by it, it offers the road to every other lit stone as its own
## use ("Travel from the Hearthstone"; triage 30), so a rest is only a rest.

const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"
const WORLD_LAYER := 1           # 3d_physics/layer_1 "world"

@export var hearthstone_id := ""
@export var display_name := "Hearthstone"
@export var place_id := ""

const FLAME_SHADER := preload("res://assets/shaders/hearth_flame.gdshader")
## The plinth's height, the standing stone's, and where the stone and the bowl stand front to back
## (+Z is the front, where the player rests).
const PLINTH_H := 0.4
const SLAB_H := 1.85
const SLAB_Z := -0.3
const BOWL_Z := 0.26
## How far in front of the stone somebody resting at it is set down (clear of the plinth).
const REST_M := 1.4
## How far the body may go from a stone it has rested at and still be offered the road from it.
const TRAVEL_OFFER_M := 5.0

var _flame: OmniLight3D
var _ember: MeshInstance3D
var _coals: MeshInstance3D
var _coals_lit: Material
var _coals_cold: Material
var _names: MeshInstance3D
var _names_lit: Material
var _names_cold: Material
## The body that has rested here and not walked off: the stone offers it the road (triage 30).
var _rested_by: Node3D = null


func _ready() -> void:
	add_to_group("interactable")
	# The physics layer the player's interaction ray masks. It used to be set only in this
	# class's .tscn, so a node built with `.new()` kept Godot's default layer 1 and the ray
	# went straight through it — visible, in the group, with an `interact()` method, and
	# impossible to walk up to. `container.gd` and `world_item.gd` always set their own.
	# And on "world" as well, so it is solid: on the interact layer alone every body walked through it.
	collision_layer = INTERACT_LAYER | WORLD_LAYER
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
	if offers_travel():
		return "Travel from the %s" % display_name
	return "Rest at the %s" % display_name


## True when the body that rested here is still by the stone and another lit stone is on the road:
## the stone's second use, the road (resting only rests; triage 30).
func offers_travel() -> bool:
	if _rested_by == null or not is_instance_valid(_rested_by):
		return false
	return not Hearth.travel_targets(hearthstone_id).is_empty()


func interact(actor: Node) -> void:
	if not actor.is_in_group("player"):
		return
	if offers_travel() and actor == _rested_by:
		_offer_the_road()
		return
	var yaw := 0.0
	if actor is Node3D:
		yaw = (actor as Node3D).global_rotation.y
	Hearth.rest_at(hearthstone_id, global_position + global_transform.basis.z * REST_M + Vector3.UP * 0.1, yaw)
	if not place_id.is_empty():
		GameState.discover(place_id)
	EventBus.notify.emit("You rest at the %s. Your name is kept here." % display_name, "info")
	# Resting only rests. From now until the body walks off, the stone offers the road to every
	# other lit stone as its own choice (prompt_text), rather than putting the list at every rest.
	_rested_by = actor as Node3D


## The road from here to every other lit stone, as a conversation with the stone; or why not.
func _offer_the_road() -> void:
	var why := Hearth.why_no_travel()
	if not why.is_empty():
		EventBus.notify.emit(why, "warning")
		return
	var road: Dictionary = Hearth.travel_conversation(hearthstone_id, display_name)
	if not road.is_empty():
		Social.dialogue.start_def(road, "", place_id)


## What a Hearthstone is, to look at (playtest 09-27: "they look like primitive candles"; they were
## a grey cylinder with a glowing ball on it). A stone that keeps a name: a standing slab, rough
## and a little out of true, on a two-step plinth of dressed blocks, with a panel sunk in its face
## where the names are cut (it warms when the stone is lit); before it, on the plinth, a bronze bowl of coals, and when the stone is
## lit a flame in the bowl (assets/shaders/hearth_flame.gdshader) that licks and sways, with the
## warm light it throws. Unlit, the bowl holds cold grey ash. The player rests facing it from the
## front (+Z), where the bowl is. Built from the forge's painted surface in Hearthvale's stone
## colours, like the POIs' masonry, and all in code so every stone is the same stone.
func _build_visual() -> void:
	var blocks := PoiKit.painted(2, {"base": "#b9b3a4", "accent": "#9c9585", "grout": "#6f695d", "unit": 0.3}, 0.7)
	var slab_mat := PoiKit.painted(0, {"base": "#8f8b82", "accent": "#7d796f", "grout": "#86827a", "unit": 0.5}, 0.6)
	# the plinth: two steps of dressed stone, seven-sided, the upper turned against the lower
	_part(_cylinder(0.84, 0.8, 0.22, 7), Vector3(0.0, 0.11, 0.0), blocks)
	var step := _part(_cylinder(0.66, 0.62, 0.18, 7), Vector3(0.0, 0.31, 0.0), blocks)
	step.rotation.y = 0.45
	# the standing stone: a rough slab, broad across and thin front to back, narrowing to a head
	# cut on the slant, set a little out of true
	var slab := _part(_slab_mesh(), Vector3(0.0, PLINTH_H, SLAB_Z), slab_mat)
	slab.rotation = Vector3(-0.03, 0.1, 0.02)
	# where the names are cut: a sunk panel on its face, that warms when the stone is lit
	var panel := BoxMesh.new()
	panel.size = Vector3(0.3, 0.5, 0.03)
	_names_cold = PoiKit.plain(Color(0.3, 0.29, 0.27), 1.0)
	_names_lit = PoiKit.plain(Color(0.3, 0.25, 0.2), 0.95, 0.0, Color(1.0, 0.55, 0.25), 0.12)
	_names = MeshInstance3D.new()
	_names.mesh = panel
	_names.position = Vector3(0.0, SLAB_H * 0.56, 0.165)
	_names.material_override = _names_cold
	slab.add_child(_names)
	# the bowl, on a short foot, in front of the stone
	var bronze := PoiKit.plain(Color(0.27, 0.21, 0.15), 0.6, 0.5)
	_part(_cylinder(0.12, 0.15, 0.08, 10), Vector3(0.0, PLINTH_H + 0.04, BOWL_Z), bronze)
	_part(_cylinder(0.36, 0.2, 0.2, 14), Vector3(0.0, PLINTH_H + 0.18, BOWL_Z), bronze)
	# what is in the bowl: cold ash, or coals when the stone is lit (_update_flame)
	_coals_lit = PoiKit.plain(Color(0.16, 0.06, 0.03), 0.9, 0.0, Color(0.9, 0.28, 0.06), 0.9)
	_coals_cold = PoiKit.plain(Color(0.42, 0.4, 0.38), 1.0)
	_coals = _part(_cylinder(0.31, 0.31, 0.03, 14), Vector3(0.0, PLINTH_H + 0.245, BOWL_Z), _coals_cold)
	# the flame: one quad the shader turns to the eye
	_ember = MeshInstance3D.new()
	_ember.name = "Flame"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.62, 0.95)
	_ember.mesh = quad
	var fm := ShaderMaterial.new()
	fm.shader = FLAME_SHADER
	fm.set_shader_parameter("seed", float(absi(hash(hearthstone_id)) % 97) / 9.7)
	_ember.material_override = fm
	_ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ember.position = Vector3(0.0, PLINTH_H + 0.26 + 0.44, BOWL_Z)
	add_child(_ember)
	_flame = OmniLight3D.new()
	_flame.position = Vector3(0.0, PLINTH_H + 0.8, BOWL_Z + 0.15)
	_flame.light_color = Color(1.0, 0.68, 0.36)
	_flame.omni_range = 9.0
	_flame.light_energy = 2.2
	_flame.shadow_enabled = false
	add_child(_flame)
	# solid as it looks: the plinth, the stone and the bowl
	_shape(_cyl_shape(0.82, PLINTH_H), Vector3(0.0, PLINTH_H * 0.5, 0.0))
	var slab_box := BoxShape3D.new()
	slab_box.size = Vector3(0.9, SLAB_H, 0.46)
	_shape(slab_box, Vector3(0.0, PLINTH_H + SLAB_H * 0.5, SLAB_Z))
	_shape(_cyl_shape(0.36, 0.3), Vector3(0.0, PLINTH_H + 0.15, BOWL_Z))


## The standing stone's own mesh: eight corners, the foot wider than the head, the head cut on
## a slant and set a little off the foot's middle, flat-shaded so its faces read as dressed.
func _slab_mesh() -> ArrayMesh:
	var foot := [Vector3(-0.44, 0.0, -0.21), Vector3(0.44, 0.0, -0.21), Vector3(0.44, 0.0, 0.21), Vector3(-0.44, 0.0, 0.21)]
	var head := [Vector3(-0.28, SLAB_H, -0.15), Vector3(0.33, SLAB_H * 0.87, -0.14),
			Vector3(0.33, SLAB_H * 0.87, 0.14), Vector3(-0.28, SLAB_H, 0.15)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# sides: foot i -> foot i+1 -> head i+1 -> head i
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, foot[i], foot[j], head[j], head[i])
	_quad(st, head[0], head[1], head[2], head[3])
	st.generate_normals()
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


func _cylinder(bottom: float, top: float, height: float, sides: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = bottom
	m.top_radius = top
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	return m


func _part(mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.material_override = mat
	add_child(mi)
	return mi


func _cyl_shape(radius: float, height: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	return c


func _shape(shape: Shape3D, at: Vector3) -> void:
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = at
	add_child(col)


func _update_flame() -> void:
	var lit := Hearth.is_lit(hearthstone_id)
	_flame.visible = lit
	_ember.visible = lit
	_coals.material_override = _coals_lit if lit else _coals_cold
	_names.material_override = _names_lit if lit else _names_cold


func _process(_delta: float) -> void:
	if _rested_by != null and (not is_instance_valid(_rested_by)
			or _rested_by.global_position.distance_to(global_position) > TRAVEL_OFFER_M):
		_rested_by = null
	if _flame.visible:
		_flame.light_energy = 2.0 + 0.35 * sin(Time.get_ticks_msec() * 0.011) + 0.15 * sin(Time.get_ticks_msec() * 0.037)
