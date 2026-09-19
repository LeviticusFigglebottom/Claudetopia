class_name Building
extends Node3D
## The outside of a house, built from the inside of it.
##
## Every interior the house forge makes records its ground-floor rooms, its front door and its
## windows. That is enough to raise the building you walk up to: the rooms become masses, the
## masses take a pitched roof, the hearth room takes a chimney, and the windows and the door
## are where the interior says they are. So the house you see is the house you enter — a
## cottage with one room is small outside, and the steward's house with eight is not.
##
## It is deliberately plain geometry with painted surfaces rather than a modelled asset: what
## a village needs first is mass, silhouette, and a door in the right wall.

const WALL_SHADER := "res://assets/shaders/painted_surface.gdshader"
const STOREY_M := 2.6
const EAVES_M := 0.45
const ROOF_PITCH := 1.0             # rise over half-span, when a culture does not say
const WALL_THICK := 0.22
const CHIMNEY_W := 0.7
const PLINTH_H := 0.4

## Roof by culture: thatch in the Vale and the reeds, slate in the lake city and the hills,
## shingle in the wood. Patterns are the painted_surface ones (CONTRACTS §7).
##
## `pitch` is rise over half-span and it is the single number that decides whether a building
## reads as a cottage or a shed: thatch has to be steep or it holds water, and a steep roof is
## most of a cottage's silhouette. `thick` is the depth of the covering — thatch is most of a
## foot of straw with a rolled ridge, slate is a skin — and it is what puts a shadow under the
## eaves instead of a knife edge.
const ROOF_BY_CULTURE := {
	"vale": {"pattern": 4, "base": "#b8a172", "accent": "#8e7749", "grout": "#5d4c2c",
			 "pitch": 1.05, "thick": 0.38, "ridge": true},
	"lakefolk": {"pattern": 2, "base": "#6d7078", "accent": "#53565d", "grout": "#33353a", "unit": 0.3,
				 "pitch": 0.82, "thick": 0.13},
	"reedfolk": {"pattern": 4, "base": "#a89566", "accent": "#7d6c44", "grout": "#4a3f28",
				 "pitch": 1.12, "thick": 0.42, "ridge": true},
	"clans": {"pattern": 2, "base": "#7c7a74", "accent": "#5e5c57", "grout": "#3a3936", "unit": 0.42,
			  "pitch": 0.72, "thick": 0.16},
	"woodfolk": {"pattern": 1, "base": "#5c4a32", "accent": "#3f3221", "grout": "#241c12", "unit": 0.3,
				 "pitch": 0.95, "thick": 0.17},
	"pilgrims": {"pattern": 2, "base": "#726f69", "accent": "#56534e", "grout": "#343230", "unit": 0.5,
				 "pitch": 0.75, "thick": 0.15},
}

## The stone a wall stands on, by culture. A house with no plinth looks placed on the grass;
## a course of dark stone under the limewash is what makes it look built into the ground.
const PLINTH_BY_CULTURE := {
	"vale": {"pattern": 2, "base": "#8b8274", "accent": "#6f6759", "grout": "#4a453c", "unit": 0.34},
	"lakefolk": {"pattern": 2, "base": "#7c8088", "accent": "#61656c", "grout": "#3e4146", "unit": 0.38},
	"reedfolk": {"pattern": 2, "base": "#6a6354", "accent": "#514b3f", "grout": "#332f28", "unit": 0.3},
	"clans": {"pattern": 2, "base": "#8e8880", "accent": "#6e6961", "grout": "#464240", "unit": 0.45},
	"woodfolk": {"pattern": 2, "base": "#6f6a5c", "accent": "#565145", "grout": "#36322a", "unit": 0.32},
	"pilgrims": {"pattern": 2, "base": "#8a857e", "accent": "#6a6660", "grout": "#454240", "unit": 0.5},
}

@export var interior_id := ""

var meta: Dictionary = {}
var culture := "vale"
var footprint := Rect2()
## One number per building, from its own id, that shifts its limewash a little. A street where
## every house is the same cream is a terrace of one house printed nine times; real limewash is
## mixed in a bucket and no two buckets match.
var tone := 0.0


## A building for an interior, standing at `at` with its front door facing `yaw`.
static func raise_for(id: String, at: Vector3, yaw: float) -> Building:
	var b := Building.new()
	b.interior_id = id
	b.name = "Building_" + Ids.name_of(id)
	b.rotation.y = yaw
	b.position = at
	return b


func _ready() -> void:
	add_to_group("building")
	meta = _read_meta()
	if meta.is_empty():
		return
	culture = str(meta.get("culture", "vale"))
	tone = float(int(abs(interior_id.hash())) % 1000) / 1000.0
	var rooms := _ground_rooms()
	if rooms.is_empty():
		return
	footprint = _bounds(rooms)
	# The door the plan placed is this building's front door, so the house is offset to put
	# its own entrance under that point.
	var front := _front_door_local()
	for room in rooms:
		_raise_room(room, front)
	_add_chimney(rooms, front)
	_add_door()
	_add_windows(front)


# --- the parts ------------------------------------------------------------------------------------

func _raise_room(room: Dictionary, front: Vector2) -> void:
	var w := float(room["w"])
	var d := float(room["d"])
	var storeys := 2 if _has_upper(room) else 1
	var h := STOREY_M * storeys
	var centre := Vector3(float(room["x"]) + w * 0.5 - front.x, 0.0, float(room["z"]) + d * 0.5 - front.y)
	var walls := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w + WALL_THICK, h, d + WALL_THICK)
	walls.mesh = box
	walls.position = centre + Vector3(0.0, h * 0.5, 0.0)
	walls.material_override = _surface(_wall_spec(), 0.35, true)
	walls.name = "Walls_" + str(room.get("id", "room"))
	add_child(walls)
	_add_plinth(centre, w, d)
	_add_body(walls.position, box.size)
	_add_roof(centre, w, d, h)


## A pitched roof over one mass, ridged along its longer axis.
##
## Two slabs with real depth rather than a folded sheet, so the eaves overhang the wall and
## throw a shadow line along it, and the gable ends are filled in the wall's own surface. A
## thatching culture gets a rolled ridge along the top. This is the silhouette a village is
## read by at four hundred metres, so it is built rather than implied.
func _add_roof(centre: Vector3, w: float, d: float, wall_h: float) -> void:
	var spec := _roof_spec()
	var pitch := float(spec.get("pitch", ROOF_PITCH))
	var thick := float(spec.get("thick", 0.2))
	var along_x := w >= d
	var wall_span := (d if along_x else w) + WALL_THICK
	var span := wall_span + EAVES_M * 2.0
	var length := (w if along_x else d) + WALL_THICK + EAVES_M * 2.0
	var rise := span * 0.5 * pitch
	var hs := span * 0.5
	var slope := sqrt(hs * hs + rise * rise)
	var angle := atan2(rise, hs)
	var mat := _surface(spec, 0.5, false)

	var roof := Node3D.new()
	roof.name = "Roof"
	roof.position = centre + Vector3(0.0, wall_h, 0.0)
	if not along_x:
		roof.rotation.y = PI * 0.5
	add_child(roof)

	for side in [-1.0, 1.0]:
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		# a little past the ridge so the two slabs meet in a closed apex
		box.size = Vector3(length, thick, slope + thick * 0.6)
		slab.mesh = box
		slab.material_override = mat
		slab.name = "Slope%d" % int(side)
		# the top face runs ridge -> eave; drop the slab half its depth along that face's normal
		var mid := Vector3(0.0, rise * 0.5, side * hs * 0.5)
		var normal := Vector3(0.0, hs, side * rise).normalized()
		slab.position = mid - normal * (thick * 0.5)
		# +side tilts the slab down toward its own eave; the sign is the difference between a
		# roof and a pair of open wings.
		slab.rotation.x = side * angle
		roof.add_child(slab)

	# the triangle of wall between the eaves and the ridge, at each gable end
	var hl := length * 0.5 - EAVES_M
	var hw := wall_span * 0.5
	var gable_rise := hw * pitch
	for end in [-1.0, 1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a := Vector3(end * hl, 0.0, -hw)
		var b := Vector3(end * hl, 0.0, hw)
		var c := Vector3(end * hl, gable_rise, 0.0)
		if end > 0.0:
			_tri(st, a, b, c)
		else:
			_tri(st, b, a, c)
		st.generate_normals()
		var gable := MeshInstance3D.new()
		gable.mesh = st.commit()
		gable.material_override = _surface(_wall_spec(), 0.35, true)
		gable.name = "Gable%d" % int(end)
		roof.add_child(gable)

	if bool(spec.get("ridge", false)):
		var cap := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(length * 0.98, thick * 0.9, thick * 2.2)
		cap.mesh = cbox
		var cap_spec := spec.duplicate()
		cap_spec["base"] = str(spec.get("accent", spec.get("base", "#8e7749")))
		cap.material_override = _surface(cap_spec, 0.62, false)
		cap.position = Vector3(0.0, rise - thick * 0.25, 0.0)
		cap.name = "Ridge"
		roof.add_child(cap)


## A course of stone under the walls, so the house stands in the ground rather than on it.
func _add_plinth(centre: Vector3, w: float, d: float) -> void:
	var plinth := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w + WALL_THICK + 0.16, PLINTH_H, d + WALL_THICK + 0.16)
	plinth.mesh = box
	plinth.name = "Plinth"
	plinth.material_override = _surface(
			PLINTH_BY_CULTURE.get(culture, PLINTH_BY_CULTURE["vale"]), 0.55, false)
	# sunk a little, so the grass meets stone and not a floating edge
	plinth.position = centre + Vector3(0.0, PLINTH_H * 0.5 - 0.14, 0.0)
	add_child(plinth)


func _add_chimney(rooms: Array, front: Vector2) -> void:
	var hearth: Dictionary = {}
	for r in rooms:
		var room: Dictionary = r
		if str(room.get("kind", "")).contains("hearth") or str(room.get("id", "")).contains("hearth"):
			hearth = room
			break
	if hearth.is_empty():
		hearth = rooms[0]
	var w := float(hearth["w"])
	var d := float(hearth["d"])
	var pitch := float(_roof_spec().get("pitch", ROOF_PITCH))
	var top := STOREY_M * (2 if _has_upper(hearth) else 1) + minf(w, d) * 0.5 * pitch + 1.1
	var stack := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CHIMNEY_W, top, CHIMNEY_W)
	stack.mesh = box
	stack.name = "Chimney"
	stack.material_override = _surface(
			PLINTH_BY_CULTURE.get(culture, PLINTH_BY_CULTURE["vale"]), 0.7, false)
	# On the gable end rather than in the middle of the roof.
	stack.position = Vector3(float(hearth["x"]) + w - 0.5 - front.x, top * 0.5,
			float(hearth["z"]) + d * 0.5 - front.y)
	add_child(stack)


## The way in, where the interior's own front door is: a plank door in a timber frame under a
## lintel. A dark rectangle painted on a wall reads as a hole; a frame reads as a door, and the
## door is the thing a player walks toward from across the green.
func _add_door() -> void:
	var face := -WALL_THICK * 0.5
	var frame := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(1.34, 2.28, 0.14)
	frame.mesh = fbox
	frame.name = "DoorFrame"
	frame.material_override = _timber(0.34, 0.26, 0.18)
	frame.position = Vector3(0.0, 1.14, face - 0.03)
	add_child(frame)

	var lintel := MeshInstance3D.new()
	var lbox := BoxMesh.new()
	lbox.size = Vector3(1.6, 0.2, 0.24)
	lintel.mesh = lbox
	lintel.name = "DoorLintel"
	lintel.material_override = _timber(0.24, 0.18, 0.12)
	lintel.position = Vector3(0.0, 2.34, face - 0.05)
	add_child(lintel)

	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.05, 2.05, 0.12)
	panel.mesh = box
	panel.name = "DoorPanel"
	panel.material_override = _timber(0.2, 0.14, 0.085)
	panel.position = Vector3(0.0, 1.03, face - 0.08)
	add_child(panel)

	var step := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(1.5, 0.16, 0.6)
	step.mesh = sbox
	step.name = "DoorStep"
	step.material_override = _surface(
			PLINTH_BY_CULTURE.get(culture, PLINTH_BY_CULTURE["vale"]), 0.8, false)
	step.position = Vector3(0.0, 0.05, face - 0.3)
	add_child(step)


func _add_windows(front: Vector2) -> void:
	for entry in meta.get("windows", []):
		var win: Dictionary = entry
		var at: Array = win.get("at", [])
		if at.size() < 3 or float(at[1]) > STOREY_M * 2.2:
			continue
		var normal: Array = win.get("normal", [0, 0, 1])
		var n := Vector3(float(normal[0]), 0.0, float(normal[2])).normalized()
		var base := Vector3(float(at[0]) - front.x, float(at[1]), float(at[2]) - front.y)
		var yaw := atan2(n.x, n.z)

		var frame := MeshInstance3D.new()
		var fbox := BoxMesh.new()
		fbox.size = Vector3(1.06, 0.96, 0.1)
		frame.mesh = fbox
		frame.name = "WindowFrame"
		frame.material_override = _timber(0.33, 0.27, 0.2)
		frame.position = base + n * (WALL_THICK * 0.5 + 0.02)
		frame.rotation.y = yaw
		add_child(frame)

		var pane := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.86, 0.76, 0.1)
		pane.mesh = box
		var mat := StandardMaterial3D.new()
		# Not glass: a shutter-dark opening that the interior's own lamps warm at night.
		mat.albedo_color = Color(0.1, 0.095, 0.088)
		mat.roughness = 0.6
		pane.material_override = mat
		pane.name = "Window"
		pane.position = base + n * (WALL_THICK * 0.5 + 0.045)
		pane.rotation.y = yaw
		add_child(pane)

		var sill := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(1.24, 0.11, 0.3)
		sill.mesh = sbox
		sill.name = "WindowSill"
		sill.material_override = _surface(
				PLINTH_BY_CULTURE.get(culture, PLINTH_BY_CULTURE["vale"]), 0.5, false)
		sill.position = base + n * (WALL_THICK * 0.5 + 0.06) + Vector3(0.0, -0.53, 0.0)
		sill.rotation.y = yaw
		add_child(sill)


# --- reading the interior ---------------------------------------------------------------------

func _read_meta() -> Dictionary:
	var def := ContentDB.get_or_empty(interior_id)
	var path := str(def.get("meta", ""))
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _ground_rooms() -> Array:
	var out: Array = []
	for r in meta.get("rooms", []):
		if int((r as Dictionary).get("storey", 0)) == 0:
			out.append(r)
	return out


func _has_upper(room: Dictionary) -> bool:
	var rect := Rect2(float(room["x"]), float(room["z"]), float(room["w"]), float(room["d"]))
	for r in meta.get("rooms", []):
		var other: Dictionary = r
		if int(other.get("storey", 0)) != 1:
			continue
		if rect.intersects(Rect2(float(other["x"]), float(other["z"]), float(other["w"]), float(other["d"]))):
			return true
	return false


func _front_door_local() -> Vector2:
	for d in meta.get("doors", []):
		var door: Dictionary = d
		if str(door.get("kind", "")) == "front":
			var at: Array = door.get("at", [0, 0, 0])
			return Vector2(float(at[0]), float(at[2]))
	var b := _bounds(_ground_rooms())
	return Vector2(b.position.x + b.size.x * 0.5, b.position.y)


static func _bounds(rooms: Array) -> Rect2:
	if rooms.is_empty():
		return Rect2()
	var first: Dictionary = rooms[0]
	var r := Rect2(float(first["x"]), float(first["z"]), float(first["w"]), float(first["d"]))
	for room in rooms:
		var other: Dictionary = room
		r = r.merge(Rect2(float(other["x"]), float(other["z"]), float(other["w"]), float(other["d"])))
	return r


# --- surfaces and bodies ------------------------------------------------------------------------

func _wall_spec() -> Dictionary:
	var by_culture: Dictionary = HouseInterior.CULTURE_SURFACES.get(culture, HouseInterior.CULTURE_SURFACES["vale"])
	return by_culture.get("wall", {})


func _roof_spec() -> Dictionary:
	return ROOF_BY_CULTURE.get(culture, ROOF_BY_CULTURE["vale"])


## This house's own mix of the culture's colour. Limewash is mixed in a bucket, and the bucket
## is never twice the same, so a row of cottages is a row of slightly different creams. The
## shift is small on purpose: enough to break the terrace, not enough to break the culture.
func _toned(hex: String) -> Color:
	var c := Color.html(hex)
	var hsv := Vector3(c.h, c.s, c.v)
	var k := tone * 2.0 - 1.0
	return Color.from_hsv(fposmod(hsv.x + k * 0.018, 1.0),
			clampf(hsv.y * (1.0 + k * 0.16), 0.0, 1.0),
			clampf(hsv.z * (1.0 + k * 0.085), 0.03, 1.0))


## The painted_surface uniforms are spelled `base_color`, not `base_colour`; setting the other
## spelling is silently a no-op and every surface comes out the shader's default grey, which is
## exactly what the first village looked like.
func _surface(spec: Dictionary, wear: float, vary: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(WALL_SHADER)
	mat.set_shader_parameter("pattern", int(spec.get("pattern", 0)))
	var base := str(spec.get("base", "#cccccc"))
	var accent := str(spec.get("accent", "#999999"))
	mat.set_shader_parameter("base_color", _toned(base) if vary else Color.html(base))
	mat.set_shader_parameter("accent_color", _toned(accent) if vary else Color.html(accent))
	mat.set_shader_parameter("grout_color", Color.html(str(spec.get("grout", "#555555"))))
	mat.set_shader_parameter("unit_size", float(spec.get("unit", 0.32)))
	mat.set_shader_parameter("wear", wear)
	mat.set_shader_parameter("variation", 0.5)
	return mat


## Worked timber: door, frame, lintel, shutters. Plain material, since a door is small and what
## it has to do is read as a different substance from the wall around it.
static func _timber(r: float, g: float, b: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(r, g, b)
	mat.roughness = 0.88
	return mat


## Walls you cannot walk through: the only collision a settlement has until its props grow one.
func _add_body(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child(body)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
