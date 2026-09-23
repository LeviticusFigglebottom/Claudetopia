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
##
## However many rooms and windows it has, a building is four draw calls: one mesh in the wall
## surface (masses and gables), one roof (slabs and ridge), one stone (plinths, chimney, sills,
## step) and one of joinery (door, frames, shutters). Before that every part was its own
## MeshInstance3D, and the eleven houses in view on Merrowby's street were 358 of them, drawn
## again for each of the sun's cascades — the worst frame in the game.

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
	var fabric := FabricMesh.new()
	for room in rooms:
		_raise_room(fabric, room, front)
	_add_chimney(fabric, rooms, front)
	_add_door(fabric)
	_add_windows(fabric, front)
	fabric.commit(self, "wall", _surface(_wall_spec(), 0.35, true), "Walls")
	fabric.commit(self, "roof", _surface(_roof_spec(), 0.5, false), "Roof")
	fabric.commit(self, "stone", _surface(_plinth_spec(), 0.6, false), "Stone")
	var joinery := fabric.commit(self, "joinery", FabricMesh.joinery_material(), "Joinery")
	if joinery != null:
		FabricMesh.near_only(joinery, FabricMesh.JOINERY_RANGE_M, false)


# --- the parts ------------------------------------------------------------------------------------

func _raise_room(fabric: FabricMesh, room: Dictionary, front: Vector2) -> void:
	var w := float(room["w"])
	var d := float(room["d"])
	var storeys := 2 if _has_upper(room) else 1
	var h := STOREY_M * storeys
	var centre := Vector3(float(room["x"]) + w * 0.5 - front.x, 0.0, float(room["z"]) + d * 0.5 - front.y)
	var size := Vector3(w + WALL_THICK, h, d + WALL_THICK)
	fabric.box("wall", Transform3D(Basis(), centre + Vector3(0.0, h * 0.5, 0.0)), size)
	_add_plinth(fabric, centre, w, d)
	_add_body(centre + Vector3(0.0, h * 0.5, 0.0), size)
	_add_roof(fabric, centre, w, d, h)


## A pitched roof over one mass, ridged along its longer axis.
##
## Two slabs with real depth rather than a folded sheet, so the eaves overhang the wall and
## throw a shadow line along it, and the gable ends are filled in the wall's own surface. A
## thatching culture gets a rolled ridge along the top. This is the silhouette a village is
## read by at four hundred metres, so it is built rather than implied.
func _add_roof(fabric: FabricMesh, centre: Vector3, w: float, d: float, wall_h: float) -> void:
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
	# roof space: x along the ridge, the origin at the eaves line over the middle of the mass
	var roof := Transform3D(Basis(Vector3.UP, 0.0 if along_x else PI * 0.5), centre + Vector3(0.0, wall_h, 0.0))

	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		# the top face runs ridge -> eave; drop the slab half its depth along that face's normal.
		# +side tilts the slab down toward its own eave; the sign is the difference between a
		# roof and a pair of open wings.
		var mid := Vector3(0.0, rise * 0.5, side * hs * 0.5)
		var normal := Vector3(0.0, hs, side * rise).normalized()
		var local := Transform3D(Basis(Vector3.RIGHT, side * angle), mid - normal * (thick * 0.5))
		# a little past the ridge so the two slabs meet in a closed apex
		fabric.box("roof", roof * local, Vector3(length, thick, slope + thick * 0.6))

	# the triangle of wall between the eaves and the ridge, at each gable end
	var hl := length * 0.5 - EAVES_M
	var hw := wall_span * 0.5
	var gable_rise := hw * pitch
	for end_v in [-1.0, 1.0]:
		var end := float(end_v)
		var a := roof * Vector3(end * hl, 0.0, -hw)
		var b := roof * Vector3(end * hl, 0.0, hw)
		var c := roof * Vector3(end * hl, gable_rise, 0.0)
		if end > 0.0:
			fabric.tri("wall", a, b, c)
		else:
			fabric.tri("wall", b, a, c)

	if bool(spec.get("ridge", false)):
		fabric.box("roof", roof * Transform3D(Basis(), Vector3(0.0, rise - thick * 0.25, 0.0)),
				Vector3(length * 0.98, thick * 0.9, thick * 2.2), accent_tint(spec))


## A course of stone under the walls, so the house stands in the ground rather than on it.
func _add_plinth(fabric: FabricMesh, centre: Vector3, w: float, d: float) -> void:
	# sunk a little, so the grass meets stone and not a floating edge
	fabric.box("stone", Transform3D(Basis(), centre + Vector3(0.0, PLINTH_H * 0.5 - 0.14, 0.0)),
			Vector3(w + WALL_THICK + 0.16, PLINTH_H, d + WALL_THICK + 0.16))


func _add_chimney(fabric: FabricMesh, rooms: Array, front: Vector2) -> void:
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
	# On the gable end rather than in the middle of the roof.
	var at := Vector3(float(hearth["x"]) + w - 0.5 - front.x, top * 0.5, float(hearth["z"]) + d * 0.5 - front.y)
	fabric.box("stone", Transform3D(Basis(), at), Vector3(CHIMNEY_W, top, CHIMNEY_W))


## The way in, where the interior's own front door is. A dark rectangle painted on a wall reads
## as a hole; a frame reads as a door, and the door is the thing a player walks toward from
## across the green.
func _add_door(fabric: FabricMesh) -> void:
	door_at(fabric, Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, -WALL_THICK * 0.5)),
			timber_tints(culture), Color.WHITE)


## Somebody lives in every house that has an inside, so most of its windows are lit after dark;
## which ones follows from the interior's id, so the same house shows the same lit rooms every
## night. The lit panes are glows for NightLights, and the front door carries a real lamp.
func _add_windows(fabric: FabricMesh, front: Vector2) -> void:
	var timber := timber_tints(culture)
	var lights := RandomNumberGenerator.new()
	lights.seed = abs(("lights:" + interior_id).hash())
	var glows: Array = []
	for entry in meta.get("windows", []):
		var win: Dictionary = entry
		var at: Array = win.get("at", [])
		if at.size() < 3 or float(at[1]) > STOREY_M * 2.2:
			continue
		var normal: Array = win.get("normal", [0, 0, 1])
		var n := Vector3(float(normal[0]), 0.0, float(normal[2])).normalized()
		var base := Vector3(float(at[0]) - front.x, float(at[1]), float(at[2]) - front.y)
		var face := Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)), base + n * (WALL_THICK * 0.5))
		var ground_floor := float(at[1]) < STOREY_M
		var lit := lights.randf_range(0.5, 0.95) if lights.randf() < (0.85 if ground_floor else 0.55) else 0.0
		var pane := window_at(fabric, face, timber, Color.WHITE, ground_floor, lit)
		if lit > 0.0:
			glows.append(to_global(pane))
	if is_inside_tree():
		NightLights.add(self, glows, "window")
		# the front door faces -z in this building's space; the lamp hangs over it
		NightLights.add(self, [to_global(Vector3(0.0, 2.3, -WALL_THICK * 0.5 - 0.6))], "door")


# --- the openings, shared with the fabric -----------------------------------------------------------

## A plank door in a timber frame under a lintel, on a stone step. `at` has its origin at the
## foot of the opening on the wall's face and +z pointing out of the wall. The panel sits back
## behind the frame's lips, so the doorway reads as a doorway and not as paint.
static func door_at(fabric: FabricMesh, at: Transform3D, timber: Dictionary, stone: Color) -> void:
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		fabric.box("joinery", at * Transform3D(Basis(), Vector3(side * 0.61, 1.12, 0.05)),
				Vector3(0.12, 2.24, 0.1), timber["frame"])
	fabric.box("joinery", at * Transform3D(Basis(), Vector3(0.0, 2.3, 0.05)), Vector3(1.34, 0.14, 0.1), timber["frame"])
	fabric.box("joinery", at * Transform3D(Basis(), Vector3(0.0, 1.03, 0.02)), Vector3(1.06, 2.06, 0.04), timber["panel"])
	fabric.box("joinery", at * Transform3D(Basis(), Vector3(0.0, 2.47, 0.07)), Vector3(1.7, 0.2, 0.14), timber["lintel"])
	fabric.box("stone", at * Transform3D(Basis(), Vector3(0.0, 0.06, 0.32)), Vector3(1.5, 0.16, 0.6), stone)


## A shuttered opening: a dark pane set back behind a timber frame, on a stone sill, with a
## shutter leaf either side where asked. `at` has its origin at the centre of the opening on
## the wall's face and +z pointing out of the wall.
## `lit` is how brightly the room behind glows after dark (0 is nobody home); it rides in the
## pane's vertex alpha (FabricMesh.pane). Returns the pane's centre, in the fabric's space, for
## whoever wants to hang a glow on it.
static func window_at(fabric: FabricMesh, at: Transform3D, timber: Dictionary, stone: Color,
		shutters: bool, lit := 0.0) -> Vector3:
	fabric.pane("joinery", at * Transform3D(Basis(), Vector3(0.0, 0.0, 0.012)), Vector3(0.8, 0.84, 0.024), lit)
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		fabric.box("joinery", at * Transform3D(Basis(), Vector3(side * 0.45, 0.0, 0.05)),
				Vector3(0.1, 1.0, 0.1), timber["frame"])
	fabric.box("joinery", at * Transform3D(Basis(), Vector3(0.0, 0.47, 0.05)), Vector3(1.0, 0.1, 0.1), timber["frame"])
	fabric.box("stone", at * Transform3D(Basis(), Vector3(0.0, -0.5, 0.09)), Vector3(1.18, 0.1, 0.26), stone)
	if shutters:
		for side_v in [-1.0, 1.0]:
			var side := float(side_v)
			fabric.box("joinery", at * Transform3D(Basis(), Vector3(side * 0.74, 0.02, 0.04)),
					Vector3(0.44, 0.92, 0.05), timber["shutter"])
	return at * Vector3(0.0, 0.0, 0.25)


## Worked timber in the culture's own wood: the interior's beam colour, lighter for a frame,
## darker for a lintel and darker still for a plank door. The pane between them is not a tint:
## it is drawn in the joinery shader's own shutter-dark by day and lit from inside after dark.
static func timber_tints(culture: String) -> Dictionary:
	var by_culture: Dictionary = HouseInterior.CULTURE_SURFACES.get(culture, HouseInterior.CULTURE_SURFACES["vale"])
	var beam: Dictionary = by_culture.get("beam", {})
	var c := Color.html(str(beam.get("base", "#5e452c")))
	return {
		"frame": _scaled(c, 1.12), "lintel": _scaled(c, 0.82), "panel": _scaled(c, 0.6),
		"shutter": _scaled(c, 0.9),
	}


## What multiplies a surface's base colour into its accent: the tint a ridge takes so it can
## share the roof's draw.
static func accent_tint(spec: Dictionary) -> Color:
	var base := Color.html(str(spec.get("base", "#cccccc")))
	var accent := Color.html(str(spec.get("accent", "#999999")))
	return Color(clampf(accent.r / maxf(base.r, 0.01), 0.0, 1.0),
			clampf(accent.g / maxf(base.g, 0.01), 0.0, 1.0),
			clampf(accent.b / maxf(base.b, 0.01), 0.0, 1.0))


static func _scaled(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0))


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


func _plinth_spec() -> Dictionary:
	return PLINTH_BY_CULTURE.get(culture, PLINTH_BY_CULTURE["vale"])


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
