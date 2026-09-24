class_name WeaponTrail
extends MeshInstance3D
## The streak a heavy swing leaves behind its blade while its blow is live (Impact.trail): a ribbon
## from near the guard to the tip, through where the blade was over the last TRAIL_S, fading to
## nothing at its old end. It is restrained: a pale smear the colour of the air the blade cut,
## not a glow. Child of the held weapon (HeldItems), drawn in the world's frame.

## How long a moment of the swing stays in the streak (s).
const TRAIL_S := 0.13
## The streak starts this share of the way up the blade, so it leaves the hand and hilt clear.
const FROM_SHARE := 0.3
## Its opacity at the blade.
const ALPHA := 0.3
const COLOUR := Color(0.86, 0.88, 0.92)

var active := false:
	set(v):
		active = v
		if v:
			_samples.clear()

var _samples: Array = []             # [time, base, tip], oldest first
var _length := -1.0
var _mesh := ImmediateMesh.new()
var _t := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = m


## How long the blade of a held weapon model is (m, in the world), from its grip along its +Y: the
## far end of its meshes' bounds. A forge prop a foe holds is scaled (EnemyDress.hold), so this is
## measured along the node's axis in the world, not in its own units. 0 when it has none.
static func blade_length(node: Node3D) -> float:
	if node.has_meta("blade_length"):
		return float(node.get_meta("blade_length"))
	var most := 0.0
	var origin := node.global_position
	var axis := node.global_transform.basis.y.normalized()
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi is WeaponTrail or not mi.visible:
			continue
		var box := mi.get_aabb()
		for i in 8:
			most = maxf(most, (mi.global_transform * box.get_endpoint(i) - origin).dot(axis))
	node.set_meta("blade_length", most)
	return most


func _process(delta: float) -> void:
	_t += delta
	var holder := get_parent() as Node3D
	if holder == null:
		return
	if active:
		if _length < 0.0:
			_length = blade_length(holder)
		var xf := holder.global_transform
		var up := xf.basis.y.normalized()
		_samples.append([_t, xf.origin + up * _length * FROM_SHARE, xf.origin + up * _length])
	while not _samples.is_empty() and _t - float(_samples[0][0]) > TRAIL_S:
		_samples.pop_front()
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s: Array in _samples:
		var age := clampf((_t - float(s[0])) / TRAIL_S, 0.0, 1.0)
		var a := ALPHA * (1.0 - age) * (1.0 - age)
		_mesh.surface_set_color(Color(COLOUR, a * 0.35))
		_mesh.surface_add_vertex(s[1])
		_mesh.surface_set_color(Color(COLOUR, a))
		_mesh.surface_add_vertex(s[2])
	_mesh.surface_end()


## How many moments the streak holds now (for tests).
func sample_count() -> int:
	return _samples.size()
