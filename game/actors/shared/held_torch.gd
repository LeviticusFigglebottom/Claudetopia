class_name HeldTorch
extends Node3D
## A pitch torch in the hand (HeldItems, for an item tagged `torch`): an ash haft, a pitch-soaked
## wrap at its head and, while it is lit, a flame standing up off the wrap. It is built here, not by
## the forge, because what it is is mostly the fire.
##
## Like every held thing it is made where the hand holds it: the grip's middle at the origin and
## the haft along +Y, the weapon socket's own frame (CONTRACTS §2). The light it gives is the
## carrier's (Player's CarriedLight, with the StealthLight that makes a lit torch cost you the
## dark), stood at the torch's head in the same hand; this flickers it while the flame burns.

## Where the wrap's middle is, and the flame's foot, along the haft from the grip (m).
const HEAD_Y := 0.34
const FLAME_Y := 0.42
const HAFT_LENGTH := 0.56
const HAFT_BELOW := 0.14
const ASH := Color(0.42, 0.31, 0.2)
const PITCH := Color(0.09, 0.07, 0.05)
const FLAME := Color(1.0, 0.56, 0.2)
const FLAME_CORE := Color(1.0, 0.86, 0.5)

## Whether the torch burns (the carrier's `lantern_lit`).
var lit := false:
	set(v):
		lit = v
		if _flame != null:
			_flame.visible = v

## The carrier's light at the torch's head (Player's CarriedLight), flickered while it burns.
var light: OmniLight3D = null
var _flame: Node3D = null
var _outer: MeshInstance3D = null
var _inner: MeshInstance3D = null
var _t := 0.0


func _ready() -> void:
	var haft := MeshInstance3D.new()
	haft.name = "Haft"
	var hm := CylinderMesh.new()
	hm.top_radius = 0.022
	hm.bottom_radius = 0.017
	hm.height = HAFT_LENGTH
	hm.radial_segments = 8
	haft.mesh = hm
	haft.position.y = HAFT_LENGTH * 0.5 - HAFT_BELOW
	haft.material_override = _mat(ASH, 0.85)
	add_child(haft)
	var wrap := MeshInstance3D.new()
	wrap.name = "Wrap"
	var wm := CylinderMesh.new()
	wm.top_radius = 0.04
	wm.bottom_radius = 0.032
	wm.height = 0.14
	wm.radial_segments = 10
	wrap.mesh = wm
	wrap.position.y = HEAD_Y
	wrap.material_override = _mat(PITCH, 0.95)
	add_child(wrap)
	# two turns of cord round the wrap
	for y in [HEAD_Y - 0.045, HEAD_Y + 0.03]:
		var cord := MeshInstance3D.new()
		var cm := TorusMesh.new()
		cm.inner_radius = 0.036
		cm.outer_radius = 0.046
		cm.rings = 10
		cm.ring_segments = 4
		cord.mesh = cm
		cord.position.y = y
		cord.material_override = _mat(Color(0.3, 0.24, 0.16), 0.9)
		add_child(cord)
	_flame = Node3D.new()
	_flame.name = "Flame"
	_flame.position.y = FLAME_Y
	add_child(_flame)
	_outer = _cone(0.055, 0.2, FLAME, 3.2)
	_flame.add_child(_outer)
	_inner = _cone(0.03, 0.12, FLAME_CORE, 5.0)
	_inner.position.y = -0.02
	_flame.add_child(_inner)
	_flame.visible = lit


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## A flame's tongue: a cone standing on its base, glowing, drawn without shadow.
func _cone(radius: float, height: float, c: Color, glow: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.position.y = height * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = glow
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


func _process(delta: float) -> void:
	if not lit or _flame == null:
		return
	_t += delta
	# the flame stands up whichever way the haft leans, and licks
	_flame.global_basis = Basis.IDENTITY.scaled(Vector3.ONE * global_basis.get_scale().x)
	var lick := 1.0 + 0.16 * sin(_t * 17.0) + 0.09 * sin(_t * 29.0 + 1.7)
	_outer.scale = Vector3(1.0 + 0.08 * sin(_t * 23.0), lick, 1.0 + 0.08 * cos(_t * 19.0))
	_inner.scale = Vector3(1.0, 1.0 + 0.12 * sin(_t * 31.0 + 0.4), 1.0)
	if light != null and is_instance_valid(light) and light.has_meta("base_energy"):
		light.light_energy = float(light.get_meta("base_energy")) * (0.9 + 0.07 * sin(_t * 13.0) + 0.05 * sin(_t * 31.0 + 2.1))
