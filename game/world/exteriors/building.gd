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
	_hang_sign(fabric, front)
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
	var trade := str(ContentDB.get_or_empty(interior_id).get("trade", ""))
	door_at(fabric, Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, -WALL_THICK * 0.5)),
			HouseKit.door_timber(culture, trade), Color.WHITE)


## Somebody lives in every house that has an inside, so most of its windows are lit after dark;
## which ones follows from the interior's id, so the same house shows the same lit rooms every
## night. The lit panes are glows for NightLights, and the front door carries a real lamp.
func _add_windows(fabric: FabricMesh, front: Vector2) -> void:
	var timber := timber_tints(culture)
	var lights := RandomNumberGenerator.new()
	lights.seed = abs(("lights:" + interior_id).hash())
	var glows: Array = []
	var rooms: Array = meta.get("rooms", [])
	var ground := _ground_rooms()
	var drawn: Array = []   # [wall key, along] of every ground-floor window, for the shut ones
	for entry in meta.get("windows", []):
		var win: Dictionary = entry
		var at: Array = win.get("at", [])
		if at.size() < 3 or float(at[1]) > STOREY_M * 2.2:
			continue
		var n := outward(win, rooms)
		var ground_floor := float(at[1]) < STOREY_M
		var p := Vector2(float(at[0]), float(at[2]))
		# the forge cut one window in the front wall across the front door's own opening
		if ground_floor and n.z < -0.5 and absf(p.y - front.y) < 0.6 and absf(p.x - front.x) < 1.3:
			continue
		var base := Vector3(p.x - front.x, float(at[1]), p.y - front.y)
		var face := Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)), base + n * (WALL_THICK * 0.5))
		var lit := lights.randf_range(0.5, 0.95) if lights.randf() < (0.85 if ground_floor else 0.55) else 0.0
		var pane := window_at(fabric, face, timber, Color.WHITE, ground_floor, lit)
		if lit > 0.0:
			glows.append(to_global(pane))
		if ground_floor:
			drawn.append(p)
	# every other outside wall a window with its shutters closed on it: the forge cut as many
	# windows as the household could pay for and put them where it liked, and a cottage with one
	# window showed the street three blank walls
	for spot in shut_windows(ground, drawn, front):
		var s: Dictionary = spot
		var sn: Vector3 = s["normal"]
		var sp: Vector2 = s["at"]
		var sface := Transform3D(Basis(Vector3.UP, atan2(sn.x, sn.z)),
				Vector3(sp.x - front.x, 1.48, sp.y - front.y) + sn * (WALL_THICK * 0.5))
		shut_at(fabric, sface, timber, Color.WHITE)
	if is_inside_tree():
		NightLights.add(self, glows, "window")
		# the front door faces -z in this building's space; the lamp hangs over it
		NightLights.add(self, [to_global(Vector3(0.0, 2.3, -WALL_THICK * 0.5 - 0.6))], "door")


## Which way a window the house forge wrote looks out. Its `normal` names the wall's axis and not
## its side: a window in the front or the left-hand wall of a room says +z or +x like one in the
## back or the right, and was drawn a hand's breadth inside the wall, where nobody saw it. The
## side is the one of its room's walls the window stands on.
static func outward(win: Dictionary, rooms: Array) -> Vector3:
	var normal: Array = win.get("normal", [0, 0, 1])
	var n := Vector3(float(normal[0]), 0.0, float(normal[2])).normalized()
	var at: Array = win.get("at", [])
	if at.size() < 3:
		return n
	for r_v in rooms:
		var r: Dictionary = r_v
		if str(r.get("id", "")) != str(win.get("room", "")):
			continue
		if absf(n.x) > 0.5:
			var x := float(at[0])
			return Vector3.LEFT if absf(x - float(r["x"])) < absf(x - float(r["x"]) - float(r["w"])) else Vector3.RIGHT
		var z := float(at[2])
		return Vector3.FORWARD if absf(z - float(r["z"])) < absf(z - float(r["z"]) - float(r["d"])) else Vector3.BACK
	return n


## Where the shut windows go, in the interior's own plan: the middle of every outside wall of the
## ground floor long enough to take one that has no window of its own and no front door, each
## {at: Vector2 (x, z), normal: Vector3}. `drawn` is where the real windows are.
static func shut_windows(ground: Array, drawn: Array, door: Vector2) -> Array:
	var out: Array = []
	for r_v in ground:
		var r: Dictionary = r_v
		var x0 := float(r["x"])
		var z0 := float(r["z"])
		var x1 := x0 + float(r["w"])
		var z1 := z0 + float(r["d"])
		for wall in [[Vector2(x0, (z0 + z1) * 0.5), Vector3.LEFT, z1 - z0], [Vector2(x1, (z0 + z1) * 0.5), Vector3.RIGHT, z1 - z0],
				[Vector2((x0 + x1) * 0.5, z0), Vector3.FORWARD, x1 - x0], [Vector2((x0 + x1) * 0.5, z1), Vector3.BACK, x1 - x0]]:
			var mid: Vector2 = wall[0]
			var n: Vector3 = wall[1]
			if float(wall[2]) < 2.2:
				continue
			var out_n := Vector2(n.x, n.z)
			# another room on the far side of this wall: it is inside the house
			var beyond := mid + out_n * 0.4
			var inside := false
			for o_v in ground:
				var o: Dictionary = o_v
				if o != r and Rect2(float(o["x"]), float(o["z"]), float(o["w"]), float(o["d"])).grow(0.05).has_point(beyond):
					inside = true
					break
			if inside:
				continue
			var along := Vector2(-out_n.y, out_n.x)
			var free := true
			for p_v in drawn:
				var p: Vector2 = p_v
				if absf((p - mid).dot(out_n)) < 0.6 and absf((p - mid).dot(along)) < float(wall[2]) * 0.5:
					free = false
					break
			if free and absf((door - mid).dot(out_n)) < 0.6 and absf((door - mid).dot(along)) < 1.4:
				free = false
			if free:
				out.append({"at": mid, "normal": n})
	return out


# --- the openings, shared with the fabric -----------------------------------------------------------

## A window with its shutters closed over it: the frame and the sill of `window_at`, and the two
## ledged leaves meeting in the middle.
static func shut_at(fabric: FabricMesh, at: Transform3D, timber: Dictionary, stone: Color) -> void:
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		fabric.box("joinery", at * Transform3D(Basis(), Vector3(side * 0.45, 0.0, 0.05)), Vector3(0.1, 1.0, 0.1), timber["frame"])
		fabric.box("joinery", at * Transform3D(Basis(), Vector3(side * 0.205, 0.0, 0.035)), Vector3(0.4, 0.88, 0.05), timber["shutter"])
		for y in [-0.3, 0.3]:
			fabric.box("joinery", at * Transform3D(Basis(), Vector3(side * 0.205, float(y), 0.065)), Vector3(0.36, 0.08, 0.02), timber["lintel"])
	fabric.box("joinery", at * Transform3D(Basis(), Vector3(0.0, 0.47, 0.05)), Vector3(1.0, 0.1, 0.1), timber["frame"])
	fabric.box("stone", at * Transform3D(Basis(), Vector3(0.0, -0.5, 0.09)), Vector3(1.18, 0.1, 0.26), stone)


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
static func timber_tints(for_culture: String) -> Dictionary:
	var by_culture: Dictionary = HouseInterior.CULTURE_SURFACES.get(for_culture, HouseInterior.CULTURE_SURFACES["vale"])
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


## A house that keeps a trade hangs out its sign: an iron bracket beside the door, a board on it
## painted with the house's own name both sides, so it is read from along the street, and the
## trade's emblem under it -- the loaf, the hammer, the jug (Settlement.EMBLEM). A house with no
## trade has no sign. The board goes on the side of the door with more wall to it.
func _hang_sign(fabric: FabricMesh, front: Vector2) -> void:
	var def := ContentDB.get_or_empty(interior_id)
	var trade := str(def.get("trade", ""))
	if trade == "" or trade == "none" or not Settlement.EMBLEM.has(trade):
		return
	var b := footprint
	var left := front.x - b.position.x
	var right := b.end.x - front.x
	var sx := 1.15 if right >= left else -1.15
	var at := Transform3D(Basis(), Vector3(sx, 2.35, -WALL_THICK * 0.5))
	HouseKit.sign_bracket(fabric, at, timber_tints(culture), true)
	HouseKit.name_board(self, at, str(def.get("name", "")))
	var paths := Settlement._prop_paths(str(Settlement.PROP_PREFIX.get(culture, "hearthvale")), str(Settlement.EMBLEM[trade]))
	if paths.is_empty():
		paths = Settlement._prop_paths("hearthvale", str(Settlement.EMBLEM[trade]))
	if paths.is_empty():
		return
	var packed := load(paths[0]) as PackedScene
	var mesh: Mesh = WorldStreamer._mesh_of(packed, 0) if packed != null else null
	if mesh == null:
		return
	var box := mesh.get_aabb()
	var k := 0.42 / maxf(maxf(box.size.x, box.size.y), maxf(box.size.z, 0.05))
	var hang := HouseKit.emblem_frame(at) * Transform3D(Basis(), Vector3(0.0, -0.58, 0.0))
	var top := Vector3(box.get_center().x, box.end.y, box.get_center().z)
	var inst := MeshInstance3D.new()
	inst.name = "Emblem"
	inst.mesh = mesh
	inst.transform = Transform3D(hang.basis * Basis.from_scale(Vector3.ONE * k), hang.origin) * Transform3D(Basis(), -top)
	FabricMesh.near_only(inst, FabricMesh.PROP_RANGE_M * 0.5, false)
	add_child(inst)


## The ground floor of an interior's house in its front door's own frame, eaves included: x along
## the front (the door at 0), y back from the door. Rect2() when the interior has no plan. This is
## what `WorldDoors` asks a street for room for.
static func footprint_of(id: String) -> Rect2:
	var def := ContentDB.get_or_empty(id)
	var path := str(def.get("meta", ""))
	if path == "" or not FileAccess.file_exists(path):
		return Rect2()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return Rect2()
	var meta_d: Dictionary = parsed
	var rooms: Array = []
	for r in meta_d.get("rooms", []):
		if int((r as Dictionary).get("storey", 0)) == 0:
			rooms.append(r)
	if rooms.is_empty():
		return Rect2()
	var b := _bounds(rooms)
	var front := Vector2(b.position.x + b.size.x * 0.5, b.position.y)
	for d in meta_d.get("doors", []):
		var door: Dictionary = d
		if str(door.get("kind", "")) == "front":
			var at: Array = door.get("at", [0, 0, 0])
			front = Vector2(float(at[0]), float(at[2]))
			break
	var eaves := EAVES_M + WALL_THICK
	return Rect2(b.position.x - front.x - eaves, b.position.y - front.y,
			b.size.x + eaves * 2.0, b.size.y + eaves)


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
