class_name BowHands
extends RefCounted
## The bow in a body's left hand, worked as its clips draw it (triage 55): the arrow in the draw
## hand from the moment it is taken from the quiver to the loose, the string from nock to nock
## through the draw hand's fingers, and the limbs bending with the pull and springing back at the
## loose. HeldItems.dress gives a body one when it holds a bow; HumanoidModel updates it every
## frame it is posed, after the clips and the aim have set the bones.
##
## The forge's bow has its string as one straight tube (gen_weapons.bow), which cannot bend round
## the fingers, so while the bow is in the hand its own string is drawn in onto its line (the morph
## `unstrung`, tools/forge/bow_draw_morph.py) and this draws the string instead, as two thin rods
## from the nocks to the pull. The limbs bend by the morph `drawn`, set at the share of the full
## draw the hand has pulled.
##
## Everything is in the bow model's own frame (glTF axes): the stave along Z through the grip, the
## arrow's way +Y, the string behind the grip at y = -BRACE.

const ARROW_SCENE := "res://systems/combat/arrow.tscn"
## tools/forge/bow_draw_morph.py: the string's rest, the pull the morph is made for, and how far the
## tips go back and in at it (the square of the way out from the grip's bound GRIP_HALF).
const BRACE := 0.1296
const FULL_PULL := 0.69
const TIP_BACK := 0.15
const TIP_IN := 0.09
const GRIP_HALF := 0.06
const STRING_RADIUS := 0.0022
const STRING_COLOUR := Color(0.78, 0.72, 0.58)
## The loose: the limbs spring back past straight and settle (a spring at LIMB_HZ, damped to
## LIMB_DAMPING of critical), and the string hums, STRING_HUM metres at first, fading over STRING_FADE_S.
const LIMB_HZ := 7.0
const LIMB_DAMPING := 0.22
const STRING_HUM := 0.035
const STRING_HZ := 24.0
const STRING_FADE_S := 0.14
## The nocked arrow: its nock at the draw hand's grip, laid along the hand's line
## (HeldItems.HAND_LINE), its middle this far out.
const ARROW_HALF := 0.39

var bow: Node3D = null
var _meshes: Array[MeshInstance3D] = []
var _half := 0.76
var _string_end := 0.745
var _rods: Array[MeshInstance3D] = []
var _arrow: Node3D = null
var _held := false
var _w := 0.0
var _v := 0.0
var _loosed_s := -1.0
## What the last update saw, for tests and the motion studio.
var arrow_shown := false
var string_held := false


## Seconds into the stance clip at which `event` falls, or `fallback`.
static func _event(model: Node, event: String, fallback: float) -> float:
	return float(model.call("stance_event", event, fallback))


func update(model: Node, delta: float) -> void:
	var found := _find_bow(model)
	if found != bow:
		_forget()
		bow = found
		if bow != null:
			_take(bow)
	if bow == null:
		_show_arrow(model, false)
		return
	var stance := str(model.call("current_stance"))
	var t := float(model.call("stance_time"))
	arrow_shown = (stance == "Bow_Draw" and t >= _event(model, "arrow_drawn", 0.12)) or stance == "Bow_Aim" \
			or (stance == "Bow_Release" and t < _event(model, "release", 0.02))
	string_held = (stance == "Bow_Draw" and t >= _event(model, "nocked", 0.3)) or stance == "Bow_Aim"
	_show_arrow(model, arrow_shown)
	if model.has_method("set_grip"):
		model.call("set_grip", "R", 1.0 if arrow_shown else 0.0)
	var pull_at := Vector3(0.0, -BRACE, 0.0)
	var hum := 0.0
	if string_held:
		pull_at = _hand_in_bow(model)
		pull_at.y = minf(pull_at.y, -BRACE)
		_w = clampf((-pull_at.y - BRACE) / (FULL_PULL - BRACE), 0.0, 1.1)
		_v = 0.0
		_held = true
		_loosed_s = -1.0
	else:
		if _held:
			_held = false
			_loosed_s = 0.0
		# the limbs spring back, past straight, and settle
		var k := pow(TAU * LIMB_HZ, 2.0)
		var c := 2.0 * LIMB_DAMPING * sqrt(k)
		var steps := maxi(int(ceil(delta / 0.004)), 1)
		var h := delta / float(steps)
		for i in steps:
			_v += (-k * _w - c * _v) * h
			_w += _v * h
		if absf(_w) < 0.0005 and absf(_v) < 0.01:
			_w = 0.0
			_v = 0.0
		if _loosed_s >= 0.0:
			_loosed_s += delta
			hum = STRING_HUM * exp(-_loosed_s / STRING_FADE_S) * sin(TAU * STRING_HZ * _loosed_s)
			if _loosed_s > STRING_FADE_S * 6.0:
				_loosed_s = -1.0
	for m in _meshes:
		if is_instance_valid(m):
			m.set_blend_shape_value(m.find_blend_shape_by_name(&"drawn"), _w)
	var fe := pow(clampf((_string_end - GRIP_HALF) / maxf(_half - GRIP_HALF, 0.01), 0.0, 1.0), 2.0)
	var tip_y := -BRACE - TIP_BACK * fe * _w
	var tip_z := _string_end - TIP_IN * fe * _w
	var top := Vector3(0.0, tip_y, tip_z)
	var bottom := Vector3(0.0, tip_y, -tip_z)
	var mid := pull_at if string_held else Vector3(0.0, tip_y + hum, 0.0)
	_rod(0, top, mid)
	_rod(1, mid, bottom)


## How far the limbs are bent (the morph's weight), for tests.
func bend() -> float:
	return _w


## Where the string is pulled to, in the world (the draw hand's fingers while it is held).
func nock_point() -> Vector3:
	if bow == null or _rods.size() < 2:
		return Vector3.ZERO
	return _rods[0].global_transform.origin + _rods[0].global_transform.basis.y * 0.5


func _find_bow(model: Node) -> Node3D:
	var s: Node = model.call("socket", "WeaponL") if model.has_method("socket") else null
	if s == null:
		return null
	for c in s.get_children():
		if c is Node3D and c.has_meta(HeldItems.TAG) and not c.is_queued_for_deletion() \
				and str(c.name).begins_with("Held_bow"):
			return c as Node3D
	return null


func _take(b: Node3D) -> void:
	_meshes.clear()
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.find_blend_shape_by_name(&"drawn") < 0:
			continue
		_meshes.append(m)
		m.set_blend_shape_value(m.find_blend_shape_by_name(&"unstrung"), 1.0)
		var box := m.mesh.get_aabb()
		_half = maxf(absf(box.position.z), absf(box.end.z))
	if not _meshes.is_empty():
		_string_end = _string_ends(_meshes[0].mesh)
	for i in 2:
		var rod := MeshInstance3D.new()
		rod.name = "BowString%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = STRING_RADIUS
		cyl.bottom_radius = STRING_RADIUS
		cyl.height = 1.0
		cyl.radial_segments = 5
		cyl.rings = 1
		cyl.cap_top = false
		cyl.cap_bottom = false
		var mat := StandardMaterial3D.new()
		mat.albedo_color = STRING_COLOUR
		mat.roughness = 0.8
		cyl.material = mat
		rod.mesh = cyl
		rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rod.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		b.add_child(rod)
		_rods.append(rod)
	_w = 0.0
	_v = 0.0
	_held = false


## The string's ends (z) off the mesh: the vertices on the string's line behind the grip.
static func _string_ends(mesh: Mesh) -> float:
	var end := 0.0
	var arrays := mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return 0.745
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for v in verts:
		if absf(v.x) < 0.004 and absf(v.y + BRACE) < 0.004:
			end = maxf(end, absf(v.z))
	return end if end > 0.1 else 0.745


func _forget() -> void:
	for r in _rods:
		if is_instance_valid(r):
			r.queue_free()
	_rods.clear()
	for m in _meshes:
		if is_instance_valid(m):
			m.set_blend_shape_value(m.find_blend_shape_by_name(&"unstrung"), 0.0)
			m.set_blend_shape_value(m.find_blend_shape_by_name(&"drawn"), 0.0)
	_meshes.clear()
	bow = null


## A rod of the string from `a` to `b`, in the bow's frame.
func _rod(i: int, a: Vector3, b: Vector3) -> void:
	if i >= _rods.size() or not is_instance_valid(_rods[i]):
		return
	var along := b - a
	var length := maxf(along.length(), 0.001)
	var y := along / length
	var x := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	x = (x - y * x.dot(y)).normalized()
	var z := x.cross(y)
	_rods[i].transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)


## The draw hand's grip, in the bow's frame: where the fingers hold the string.
func _hand_in_bow(model: Node) -> Vector3:
	var s := model.call("socket", "WeaponR") as Node3D
	if s == null or bow == null:
		return Vector3(0.0, -BRACE, 0.0)
	var at := s.global_transform * HumanoidModel.grip_offset("R")
	return bow.global_transform.affine_inverse() * at


func _show_arrow(model: Node, on: bool) -> void:
	if not on:
		if _arrow != null and is_instance_valid(_arrow):
			_arrow.visible = false
		return
	if _arrow == null or not is_instance_valid(_arrow):
		_arrow = _make_arrow()
		if _arrow == null:
			return
		var s := model.call("socket", "WeaponR") as Node3D
		if s == null:
			_arrow.free()
			_arrow = null
			return
		s.add_child(_arrow)
	_arrow.visible = true


## The arrow the draw hand holds: the flying arrow's look, without its flight.
func _make_arrow() -> Node3D:
	if not ResourceLoader.exists(ARROW_SCENE):
		return null
	var node := (load(ARROW_SCENE) as PackedScene).instantiate() as Node3D
	node.set_script(null)
	node.name = "NockedArrow"
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var way: Vector3 = HeldItems.HAND_LINE["R"]
	node.transform = Transform3D(Basis.looking_at(way, Vector3.UP), HumanoidModel.grip_offset("R") + way * ARROW_HALF)
	return node


## The nocked arrow, for tests and the loose (null when there is none).
func arrow() -> Node3D:
	return _arrow if _arrow != null and is_instance_valid(_arrow) else null


## Takes away what this made (the body lets go of its bow).
func clear() -> void:
	_forget()
	if _arrow != null and is_instance_valid(_arrow):
		_arrow.queue_free()
	_arrow = null
