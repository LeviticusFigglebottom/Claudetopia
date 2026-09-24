class_name FabricMesh
extends RefCounted
## One mesh per material, however many things are in it.
##
## A village is boxes: walls, plinths, roof slabs, gables, chimneys, sills, lintels, frames. As a
## `MeshInstance3D` each, the eleven entered houses in view on Merrowby's street were 358 draws
## for the eye and about twice that again for the sun's cascades — the worst frame in the game.
## As one mesh per material they are four draws a house, and four a settlement for every house
## nobody lives in. This gathers geometry under a surface key and commits each key as a single
## `MeshInstance3D`, carrying a vertex colour per piece so a street of one plaster is still a
## street of different buckets of limewash (the painted shader multiplies its result by
## `COLOR`, which is white on any mesh that carries none).
##
## Winding follows the engine's own: a box is emitted from `BoxMesh`'s triangles, so its faces
## are front faces by construction, and the normal of each is computed from that winding.

## Door frames, shutters and props are a pixel past this, and a merged mesh that is drawn is
## drawn whole; walls and roofs carry no range, because a village is read by its roofs from
## the next hill.
const JOINERY_RANGE_M := 420.0
const PROP_RANGE_M := 360.0

## The unit box's triangles, taken once from the engine's BoxMesh so the winding is its own.
static var _unit_faces: PackedVector3Array = PackedVector3Array()

var _tools: Dictionary = {}       # key -> SurfaceTool
var _triangles: Dictionary = {}   # key -> int
var _split: Dictionary = {}       # key -> Vector3: gathered in four quarters round that point
## The quarters' names, by index: west or east of the centre, then north or south of it.
const QUARTERS := ["sw", "se", "nw", "ne"]


static func _faces() -> PackedVector3Array:
	if _unit_faces.is_empty():
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		_unit_faces = cube.get_faces()
	return _unit_faces


## Gathers what is put under `key` from now on in four meshes, one for each quarter round `centre`
## a piece stands in, so a camera in the middle of a town draws the quarters in front of it and not
## the whole town. For the many small things that throw no shadow (a settlement's gardens).
func split(key: String, centre: Vector3) -> void:
	_split[key] = centre


func _key_at(key: String, at: Vector3) -> String:
	if not _split.has(key):
		return key
	var c: Vector3 = _split[key]
	return "%s@%d" % [key, (1 if at.x >= c.x else 0) + (2 if at.z >= c.z else 0)]


## A box of `size`, placed by `xf` (its centre at the origin), in `tint`.
func box(key: String, xf: Transform3D, size: Vector3, tint := Color.WHITE) -> void:
	key = _key_at(key, xf.origin)
	var st := _tool(key)
	var faces := _faces()
	var scaled := xf.scaled_local(size)
	var i := 0
	while i + 2 < faces.size():
		var a := scaled * faces[i]
		var b := scaled * faces[i + 1]
		var c := scaled * faces[i + 2]
		_emit(st, a, b, c, tint)
		i += 3
	_triangles[key] = int(_triangles.get(key, 0)) + int(faces.size() / 3.0)


## A window pane: a box like any other, except that its vertex colour is not a colour. Red and
## green carry where each corner lies across the pane (0..1, left to right and bottom to top),
## which the joinery shader interpolates into the pane's own coordinates and paints a mullion
## and a hearth-lit gradient with; alpha is how brightly the room behind is lit, 0 (nobody home)
## to PANE_LIT_MAX, because alpha 1 is what marks timber.
## By day a pane is drawn in the shader's own shutter-dark, so the colour is free to carry this.
func pane(key: String, xf: Transform3D, size: Vector3, lit: float) -> void:
	key = _key_at(key, xf.origin)
	var st := _tool(key)
	var faces := _faces()
	var scaled := xf.scaled_local(size)
	var alpha := clampf(lit, 0.0, PANE_LIT_MAX)
	var i := 0
	while i + 2 < faces.size():
		var corners := [faces[i], faces[i + 1], faces[i + 2]]
		var a: Vector3 = scaled * corners[0]
		var b: Vector3 = scaled * corners[1]
		var c: Vector3 = scaled * corners[2]
		var n := (c - a).cross(b - a)
		if n.length_squared() >= 1e-12:
			n = n.normalized()
			for k in 3:
				var p: Vector3 = corners[k]
				st.set_color(Color(p.x + 0.5, p.y + 0.5, 0.0, alpha))
				st.set_normal(n)
				st.add_vertex(scaled * p)
		i += 3
	_triangles[key] = int(_triangles.get(key, 0)) + int(faces.size() / 3.0)


## One triangle, corners clockwise as seen from its front.
func tri(key: String, a: Vector3, b: Vector3, c: Vector3, tint := Color.WHITE) -> void:
	key = _key_at(key, a)
	_emit(_tool(key), a, b, c, tint)
	_triangles[key] = int(_triangles.get(key, 0)) + 1


## A quad, corners clockwise as seen from its front.
func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint := Color.WHITE) -> void:
	tri(key, a, b, c, tint)
	tri(key, a, c, d, tint)


## A leaf, a blade, a card: a quad `size` wide (x) and tall (y) in the local XY plane of `xf`,
## drawn from both sides. Four triangles, where a box of no thickness is twelve and two thirds of
## them are its edges, which nobody sees.
func card(key: String, xf: Transform3D, size: Vector2, tint := Color.WHITE) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var a := xf * Vector3(-hx, -hy, 0.0)
	var b := xf * Vector3(-hx, hy, 0.0)
	var c := xf * Vector3(hx, hy, 0.0)
	var d := xf * Vector3(hx, -hy, 0.0)
	quad(key, a, b, c, d, tint)
	quad(key, d, c, b, a, tint)


## A log, a pole, a round: a prism of `sides` faces lying along the local X axis of `xf`, `length`
## long and `radius` across, its sides in `tint` and its two ends in `ends` (the pale of a sawn
## face, where a box's end would read as a brick).
func prism(key: String, xf: Transform3D, radius: float, length: float, tint: Color, ends: Color, sides := 6) -> void:
	var h := length * 0.5
	var rim: Array[Vector2] = []
	for k in range(sides + 1):
		var a := TAU * float(k) / float(sides)
		rim.append(Vector2(cos(a), sin(a)) * radius)
	var head := xf * Vector3(h, 0.0, 0.0)
	var foot := xf * Vector3(-h, 0.0, 0.0)
	for k in range(sides):
		var p0 := rim[k]
		var p1 := rim[k + 1]
		var a := xf * Vector3(-h, p0.x, p0.y)
		var b := xf * Vector3(h, p0.x, p0.y)
		var c := xf * Vector3(h, p1.x, p1.y)
		var d := xf * Vector3(-h, p1.x, p1.y)
		quad(key, a, b, c, d, tint)
		tri(key, head, c, b, ends)
		tri(key, foot, a, d, ends)


func has(key: String) -> bool:
	if _split.has(key):
		for q in 4:
			if has("%s@%d" % [key, q]):
				return true
		return false
	return _tools.has(key) and int(_triangles.get(key, 0)) > 0


func triangles(key: String) -> int:
	if _split.has(key):
		var n := 0
		for q in 4:
			n += int(_triangles.get("%s@%d" % [key, q], 0))
		return n
	return int(_triangles.get(key, 0))


## The finished mesh for one key as a child of `parent`, or null when nothing was drawn in it. A
## split key is committed as its quarters (`node_name` with the quarter after it: Garden_ne), and
## the first of them is returned; `commit_all` returns them all.
func commit(parent: Node, key: String, material: Material, node_name: String) -> MeshInstance3D:
	var all := commit_all(parent, key, material, node_name)
	return all[0] if not all.is_empty() else null


func commit_all(parent: Node, key: String, material: Material, node_name: String) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if _split.has(key):
		for q in 4:
			var mi := _commit_one(parent, "%s@%d" % [key, q], material, "%s_%s" % [node_name, QUARTERS[q]])
			if mi != null:
				out.append(mi)
		return out
	var one := _commit_one(parent, key, material, node_name)
	if one != null:
		out.append(one)
	return out


func _commit_one(parent: Node, key: String, material: Material, node_name: String) -> MeshInstance3D:
	if not _tools.has(key) or int(_triangles.get(key, 0)) <= 0:
		return null
	var st: SurfaceTool = _tools[key]
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = material
	inst.name = node_name
	parent.add_child(inst)
	return inst


## The material for worked timber and shuttered openings: the vertex colour is the colour, which
## is what lets a dark door panel and a paler frame share one draw, and a vertex alpha under one
## marks a window pane and how brightly the room behind it is lit after dark (joinery.gdshader).
static func joinery_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = JOINERY_SHADER
	return mat


const JOINERY_SHADER := preload("res://assets/shaders/joinery.gdshader")
## A pane's vertex alpha is its lit strength, and one means timber, so a lit pane tops out here.
const PANE_LIT_MAX := 0.98


## A timber's colour a shade lighter or darker. `Color * float` scales the alpha too, and in the
## joinery an alpha under one is not timber but a window pane: a hurdle tinted that way came out
## as a row of dark glass that lit up after dark.
static func shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), c.a)


## Shown near, dropped far, and for the small stuff no shadow: a shutter's shadow is a line
## nobody sees and a whole extra pass for the sun.
static func near_only(inst: GeometryInstance3D, reach: float, shadows: bool) -> void:
	inst.visibility_range_end = reach
	inst.visibility_range_end_margin = reach * 0.12
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not shadows:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _tool(key: String) -> SurfaceTool:
	if not _tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
	return _tools[key]


## Godot's front faces wind clockwise, so `(c - a) x (b - a)` is the outward normal.
static func _emit(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	st.set_color(tint)
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
