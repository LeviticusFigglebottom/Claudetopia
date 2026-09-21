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


static func _faces() -> PackedVector3Array:
	if _unit_faces.is_empty():
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		_unit_faces = box.get_faces()
	return _unit_faces


## A box of `size`, placed by `xf` (its centre at the origin), in `tint`.
func box(key: String, xf: Transform3D, size: Vector3, tint := Color.WHITE) -> void:
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
	_triangles[key] = int(_triangles.get(key, 0)) + faces.size() / 3


## One triangle, corners clockwise as seen from its front.
func tri(key: String, a: Vector3, b: Vector3, c: Vector3, tint := Color.WHITE) -> void:
	_emit(_tool(key), a, b, c, tint)
	_triangles[key] = int(_triangles.get(key, 0)) + 1


## A quad, corners clockwise as seen from its front.
func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint := Color.WHITE) -> void:
	tri(key, a, b, c, tint)
	tri(key, a, c, d, tint)


func has(key: String) -> bool:
	return _tools.has(key) and int(_triangles.get(key, 0)) > 0


func triangles(key: String) -> int:
	return int(_triangles.get(key, 0))


## The finished mesh for one key as a child of `parent`, or null when nothing was drawn in it.
func commit(parent: Node, key: String, material: Material, node_name: String) -> MeshInstance3D:
	if not has(key):
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


## The plain material for worked timber and shuttered openings: white, so the vertex colour
## is the colour, which is what lets a dark door panel and a paler frame share one draw.
static func joinery_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.86
	return mat


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
