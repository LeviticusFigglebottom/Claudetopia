class_name Settlement
extends Node3D
## The built fabric of a town: the houses nobody lives in.
##
## Twenty-four interiors are hand-built, and each one gets a real building raised around its
## door by `Building`. That is not a settlement. A settlement is fifty roofs, of which four
## open — the rest are somebody else's, shuttered, and their job is to make a street out of a
## flat circle of paving.
##
## So the fabric is laid along the roads that run through the place, because that is how towns
## are actually built: plots front the road, the road decides the grain, and the buildings turn
## their gable or their long wall to it depending on how tight the frontage is. Where no road
## crosses the pad the fallback is a ring around a green, which is also a real village plan.
##
## The whole fabric is four draw calls, however many houses are in it: everything in the wall
## surface is one mesh, the roofs another, the stone (plinths, chimneys, sills, steps) a third
## and the joinery (doors, frames, shutters) a fourth, each house carrying its own tint as a
## vertex colour so the street is not one house printed fifty times. The props are one
## `MultiMesh` per forge asset. Only the collision bodies, and the boards, stations and signs
## you can walk up to, are nodes of their own.

const STOREY_M := 2.6
const SETBACK_M := 3.2                ## from the road edge to the front wall
const ROAD_HALF_M := 3.0
const GAP_M := 2.4                    ## between neighbours along a frontage
const PLINTH_H := 0.4
const EAVES_M := 0.5                  ## how far the roof overhangs the wall

## How many roofs a place of each kind carries, and how big they are. A city house is tall and
## narrow because land inside a wall is dear; a hamlet's is wide and low because it is not.
const FABRIC := {
	"city": {"count": 54, "w": [5.0, 7.5], "d": [7.0, 10.0], "storeys": [2, 3], "ring": 26.0},
	"town": {"count": 34, "w": [5.5, 8.0], "d": [6.0, 9.0], "storeys": [1, 2], "ring": 20.0},
	"village": {"count": 16, "w": [6.0, 8.5], "d": [5.0, 7.5], "storeys": [1, 1], "ring": 16.0},
	"hamlet": {"count": 8, "w": [6.0, 8.5], "d": [5.0, 7.0], "storeys": [1, 1], "ring": 14.0},
	"fort": {"count": 10, "w": [6.0, 9.0], "d": [6.0, 9.0], "storeys": [1, 2], "ring": 18.0},
	"lodge": {"count": 5, "w": [6.0, 8.0], "d": [5.0, 7.0], "storeys": [1, 1], "ring": 13.0},
	"camp": {"count": 0, "w": [0.0, 0.0], "d": [0.0, 0.0], "storeys": [1, 1], "ring": 0.0},
	"ruin_village": {"count": 9, "w": [5.5, 7.5], "d": [5.0, 7.0], "storeys": [1, 1], "ring": 15.0},
}

## What is lying about the place, by culture. A village with no bucket, cart, hay bale or well
## is a model of a village; the props are most of what says somebody was here this morning.
## `where`: "green" is the open middle, "yard" is beside a house, "edge" is out on the verge.
##
## Briarwold has no props of its own in the forge yet, so the Woodfolk borrow the Vale's — the
## nearest honest neighbour, and a barrel is a barrel.
const PROPS_BY_CULTURE := {
	"vale": [{"kind": "well", "n": 1, "where": "green"},
			 {"kind": "cart", "n": 2, "where": "yard"},
			 {"kind": "hay_bale", "n": 6, "where": "edge"},
			 {"kind": "barrel", "n": 4, "where": "yard"},
			 {"kind": "crate", "n": 3, "where": "yard"},
			 {"kind": "wheelbarrow", "n": 1, "where": "yard"},
			 {"kind": "signpost", "n": 1, "where": "edge"},
			 {"kind": "bench", "n": 2, "where": "green"},
			 {"kind": "fence_wattle", "n": 18, "where": "edge"}],
	"lakefolk": [{"kind": "market_stall", "n": 5, "where": "green"},
				 {"kind": "barrel", "n": 5, "where": "yard"},
				 {"kind": "crate", "n": 5, "where": "yard"},
				 {"kind": "lantern_standing", "n": 4, "where": "green"},
				 {"kind": "banner", "n": 3, "where": "green"}],
	"reedfolk": [{"kind": "dock_post", "n": 5, "where": "edge"},
				 {"kind": "rope_coil", "n": 3, "where": "yard"},
				 {"kind": "rowboat", "n": 2, "where": "edge"},
				 {"kind": "lantern_hanging", "n": 2, "where": "green"},
				 {"kind": "basket", "n": 3, "where": "yard"},
				 {"kind": "boardwalk_plank", "n": 6, "where": "green"}],
	"clans": [{"kind": "drystone_wall", "n": 16, "where": "edge"},
			  {"kind": "drystone_wall_end", "n": 2, "where": "edge"}],
	"pilgrims": [{"kind": "tent", "n": 4, "where": "green"},
				 {"kind": "brazier", "n": 4, "where": "green"},
				 {"kind": "bedroll", "n": 4, "where": "yard"},
				 {"kind": "sarcophagus", "n": 1, "where": "green"}],
	"woodfolk": [{"kind": "cart", "n": 2, "where": "yard"},
				 {"kind": "hay_bale", "n": 3, "where": "edge"},
				 {"kind": "barrel", "n": 3, "where": "yard"},
				 {"kind": "fence_wattle", "n": 14, "where": "edge"},
				 {"kind": "well", "n": 1, "where": "green"}],
}

## Which region's props a culture reaches for. Not always its own: see above.
const PROP_PREFIX := {
	"vale": "hearthvale", "lakefolk": "brightwater", "reedfolk": "sedgemire",
	"clans": "skerrow", "pilgrims": "cinderlea", "woodfolk": "hearthvale",
}

## Region to the surface keys `HouseInterior` and `Building` already speak.
const CULTURE_BY_REGION := {
	"core:region/hearthvale": "vale",
	"core:region/brightwater": "lakefolk",
	"core:region/sedgemire": "reedfolk",
	"core:region/briarwold": "woodfolk",
	"core:region/skerrow": "clans",
	"core:region/cinderlea": "pilgrims",
}

## Work you can stand up and do. `Jobs` knows five kinds of station and `JobBoard` lists the
## day's radiant work, and both were complete, tested and placed by nothing at all: no notice
## post stood in any village and no bellows, mash tun or eel trap existed outside a unit test.
## The interiors know every resident's trade, so a settlement's work follows from who lives in
## it rather than from a second list that can disagree.
const STATION_FOR_TRADE := {
	"smith": "smith", "brewer": "brew", "fisher": "fish", "farmer": "chop", "baker": "chop",
}
## Every settlement has work of its own even where nobody in it has an authored trade: the
## reed beds are cut, the Briarwold is coppiced, the Skerrow digs peat off the ledges.
const STATION_BY_CULTURE := {
	"vale": "chop", "lakefolk": "fish", "reedfolk": "dig",
	"woodfolk": "chop", "clans": "dig", "pilgrims": "dig",
}
## What the forge has that reads as the work from a few paces off. The chopping block and the
## peat stack were owed and are built now — a nine-flat hewn billet with an axe bitten into it,
## and crossed courses of cut turves with the tusker standing beside them — so nothing here is
## standing in for anything any more.
const STATION_PROP := {
	"smith": "anvil", "brew": "barrel", "fish": "dock_post",
	"chop": "chopping_block", "dig": "peat_stack",
}
## The peat stack is a metre across and 1.27 m tall with its spade, so it wants its own ground
## rather than a doorstep; the block is 0.6 m and can sit anywhere a cart could.
const ROOMY_STATIONS := ["dig"]
## A hamlet of eight houses has no charter-board; a lodge in the woods has no notices.
const BOARD_KINDS := ["city", "town", "village", "fort"]
## The most stations one settlement gets, so Merrowby's ten authored interiors do not turn the
## green into a workshop floor.
const MAX_STATIONS := 4


var place_id := ""
var kind := "village"
var culture := "vale"
var pad_radius := 40.0
## Footprints already spoken for: the real houses, and the mouths of deep places.
var taken: Array[Rect2] = []
var roads: Array = []
var ruined := false

var _rng := RandomNumberGenerator.new()
var _plots: Array[Rect2] = []
var _yaws: Array[float] = []


## A settlement's fabric around `centre`. Nothing is built until it enters the tree.
static func raise_at(id: String, place_kind: String, region: String, centre: Vector3,
		radius: float, road_lines: Array, reserved: Array[Rect2]) -> Settlement:
	var s := Settlement.new()
	s.place_id = id
	s.kind = place_kind
	s.culture = str(CULTURE_BY_REGION.get(region, "vale"))
	s.pad_radius = radius
	s.roads = road_lines
	s.taken = reserved
	s.ruined = place_kind == "ruin_village"
	s.position = centre
	s.name = "Fabric_" + Ids.name_of(id)
	return s


func _ready() -> void:
	add_to_group("settlement")
	var plan: Dictionary = FABRIC.get(kind, {})
	if plan.is_empty() or int(plan.get("count", 0)) <= 0:
		return
	_rng.seed = abs(place_id.hash())
	_lay_out(plan)
	if _plots.is_empty():
		return
	_build(plan)
	_strew(plan)
	_put_to_work()
	_offer_the_empty_houses()


# --- where the houses go --------------------------------------------------------------------

func _lay_out(plan: Dictionary) -> void:
	var want := int(plan.get("count", 0))
	var wr: Array = plan.get("w", [6.0, 8.0])
	var dr: Array = plan.get("d", [5.0, 8.0])
	for line in roads:
		if _plots.size() >= want:
			break
		_along_road(line, plan, wr, dr, want)
	if _plots.size() < want:
		_around_a_green(plan, wr, dr, want)


## Plots either side of a road, fronting it. The road's own direction is the grain of the
## street, so a house's long wall lies along it and its door looks at it.
func _along_road(line_v: Variant, _plan: Dictionary, wr: Array, dr: Array, want: int) -> void:
	if typeof(line_v) != TYPE_ARRAY:
		return
	var line: Array = line_v
	var here := Vector2(global_position.x, global_position.z)
	for i in range(line.size() - 1):
		if _plots.size() >= want:
			return
		var a_v: Array = line[i]
		var b_v: Array = line[i + 1]
		var a := Vector2(float(a_v[0]), float(a_v[1]))
		var b := Vector2(float(b_v[0]), float(b_v[1]))
		var seg := b - a
		var seg_len := seg.length()
		if seg_len < 0.5:
			continue
		var dir := seg / seg_len
		var normal := Vector2(-dir.y, dir.x)
		var t := 0.0
		while t < seg_len:
			var on_road := a + dir * t
			t += _rng.randf_range(4.0, 9.0)
			if on_road.distance_to(here) > pad_radius - 6.0:
				continue
			for side_v in [-1.0, 1.0]:
				if _plots.size() >= want:
					return
				var side := float(side_v)
				var w := _rng.randf_range(float(wr[0]), float(wr[1]))
				var d := _rng.randf_range(float(dr[0]), float(dr[1]))
				var off := ROAD_HALF_M + SETBACK_M + d * 0.5
				var c: Vector2 = on_road + normal * side * off
				if c.distance_to(here) > pad_radius - 3.0:
					continue
				# the long wall lies along the road, the door faces it
				var yaw := atan2(dir.x, dir.y) + (0.0 if side > 0.0 else PI)
				_try_plot(c, w, d, yaw)


## The fallback and the oldest village plan there is: a ring of houses looking in at a green.
func _around_a_green(plan: Dictionary, wr: Array, dr: Array, want: int) -> void:
	var here := Vector2(global_position.x, global_position.z)
	var ring := float(plan.get("ring", 18.0))
	var guard := 0
	while _plots.size() < want and guard < want * 40:
		guard += 1
		var band := ring + float(_plots.size() / 7) * 13.0
		if band > pad_radius - 8.0:
			break
		var angle := _rng.randf_range(0.0, TAU)
		var w := _rng.randf_range(float(wr[0]), float(wr[1]))
		var d := _rng.randf_range(float(dr[0]), float(dr[1]))
		var c := here + Vector2(sin(angle), cos(angle)) * (band + _rng.randf_range(-2.5, 2.5))
		_try_plot(c, w, d, angle + PI)


## Keeps a plot if nothing already stands there. The rectangle is axis-aligned and a little
## generous, which is the cheap way to keep buildings from clipping without a real solver.
func _try_plot(centre: Vector2, w: float, d: float, yaw: float) -> void:
	var reach := maxf(w, d) + GAP_M
	var rect := Rect2(centre.x - reach * 0.5, centre.y - reach * 0.5, reach, reach)
	for other in _plots:
		if other.intersects(rect):
			return
	for other in taken:
		if other.intersects(rect):
			return
	_plots.append(rect)
	_yaws.append(yaw)


# --- raising them ---------------------------------------------------------------------------

func _build(plan: Dictionary) -> void:
	var storeys: Array = plan.get("storeys", [1, 1])
	var fabric := FabricMesh.new()
	var raised := 0
	for i in range(_plots.size()):
		var rect := _plots[i]
		var reach := rect.size.x
		var centre := rect.get_center()
		var w := reach - GAP_M
		var d := w * _rng.randf_range(0.72, 1.0)
		var n := int(_rng.randi_range(int(storeys[0]), int(storeys[1])))
		# A ruin is a house with its roof gone and a wall down; it is still a plan on the ground.
		var standing := not ruined or _rng.randf() > 0.45
		_one_house(fabric, centre, w, d, n, _yaws[i], standing)
		raised += 1
	if raised == 0:
		return
	fabric.commit(self, "wall", _surface(_wall_spec(), 0.45), "Walls")
	fabric.commit(self, "roof", _surface(_roof_spec(), 0.5), "Roofs")
	fabric.commit(self, "stone", _surface(_stone_spec(), 0.6), "Stone")
	var joinery := fabric.commit(self, "joinery", FabricMesh.joinery_material(), "Joinery")
	if joinery != null:
		FabricMesh.near_only(joinery, FabricMesh.JOINERY_RANGE_M, false)


## One house in the fabric. House space has x along the ridge, -z toward the street, y up
## from the ground; everything goes into the shared meshes and only the body is a node.
func _one_house(fabric: FabricMesh, centre: Vector2, w: float, d: float, storeys: int,
		yaw: float, standing: bool) -> void:
	var ground := _ground_at(centre) - global_position.y
	var h := STOREY_M * storeys
	var basis := Basis(Vector3.UP, yaw)
	var origin := Vector3(centre.x - global_position.x, ground, centre.y - global_position.z)
	var at := Transform3D(basis, origin)
	var wash := _wash()
	var stone := _stone_tint()

	# a plinth that varies: a course of dark stone, higher here and wider there
	var plinth_h := _rng.randf_range(0.28, 0.55)
	var plinth_out := _rng.randf_range(0.1, 0.22)
	fabric.box("stone", at * Transform3D(Basis(), Vector3(0.0, plinth_h * 0.5 - 0.14, 0.0)),
			Vector3(w + plinth_out * 2.0, plinth_h, d + plinth_out * 2.0), stone)
	fabric.box("wall", at * Transform3D(Basis(), Vector3(0.0, h * 0.5, 0.0)), Vector3(w, h, d), wash)
	_body(origin + Vector3(0.0, h * 0.5, 0.0), basis, Vector3(w, h, d))
	if not standing:
		return

	var pitch := _pitch()
	var thick := _roof_thick()
	var span := d + EAVES_M * 2.0
	var length := w + EAVES_M * 2.0
	var rise := span * 0.5 * pitch
	# the triangle of wall under each end of the roof, in the wall's own surface
	var apex := h + d * 0.5 * pitch
	var ne := at * Vector3(w * 0.5, h, -d * 0.5)
	var se := at * Vector3(w * 0.5, h, d * 0.5)
	var te := at * Vector3(w * 0.5, apex, 0.0)
	fabric.tri("wall", ne, se, te, wash)
	var nw := at * Vector3(-w * 0.5, h, -d * 0.5)
	var sw := at * Vector3(-w * 0.5, h, d * 0.5)
	var tw := at * Vector3(-w * 0.5, apex, 0.0)
	fabric.tri("wall", sw, nw, tw, wash)
	# two slabs with depth, overhanging the wall, meeting in a closed apex
	var slope := sqrt(span * span * 0.25 + rise * rise)
	var angle := atan2(rise, span * 0.5)
	var eaves := at * Transform3D(Basis(), Vector3(0.0, h, 0.0))
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		var normal := Vector3(0.0, span * 0.5, side * rise).normalized()
		var mid := Vector3(0.0, rise * 0.5, side * span * 0.25)
		var local := Transform3D(Basis(Vector3.RIGHT, side * angle), mid - normal * (thick * 0.5))
		fabric.box("roof", eaves * local, Vector3(length, thick, slope + thick * 0.6))
	if bool(_roof_spec().get("ridge", false)):
		fabric.box("roof", eaves * Transform3D(Basis(), Vector3(0.0, rise - thick * 0.25, 0.0)),
				Vector3(length * 0.98, thick * 0.9, thick * 2.2), Building.accent_tint(_roof_spec()))
	# the chimney stands at the hearth end, against the gable, clear of the ridge
	var hearth := 1.0 if _rng.randf() < 0.5 else -1.0
	var top := h + rise + 0.8
	fabric.box("stone", at * Transform3D(Basis(), Vector3(hearth * (w * 0.5 + 0.16), top * 0.5, 0.0)),
			Vector3(0.72, top, 0.72), stone)
	# the street front is bays: the door takes one, the windows the rest, framed and shuttered
	var timber := Building.timber_tints(culture)
	var slots := _window_slots(w)
	var door_slot := _rng.randi_range(0, slots.size() - 1)
	var door_x := slots[door_slot]
	Building.door_at(fabric, at * Transform3D(Basis(Vector3.UP, PI), Vector3(door_x, 0.0, -d * 0.5)), timber, stone)
	# upstairs every bay has a window; at the back fewer; one in the gable away from the hearth
	for s in range(storeys):
		var cy := STOREY_M * float(s) + 1.45
		for i in range(slots.size()):
			if s == 0 and i == door_slot:
				continue
			Building.window_at(fabric, at * Transform3D(Basis(Vector3.UP, PI), Vector3(slots[i], cy, -d * 0.5)),
					timber, stone, s == 0)
		for x_v in slots:
			if _rng.randf() < 0.55:
				Building.window_at(fabric, at * Transform3D(Basis(), Vector3(float(x_v), cy, d * 0.5)),
						timber, stone, false)
		if d > 4.5:
			Building.window_at(fabric, at * Transform3D(Basis(Vector3.UP, -hearth * PI * 0.5),
					Vector3(-hearth * w * 0.5, cy, 0.0)), timber, stone, false)


## The bays along a frontage: evenly spaced, two metres or more apart, so a door with its
## frame and a shuttered window can stand side by side without touching.
func _window_slots(w: float) -> Array[float]:
	var out: Array[float] = []
	var n := clampi(int((w - 1.8) / 2.0), 1, 3)
	for i in range(n):
		out.append(-w * 0.5 + 0.9 + (w - 1.8) * (float(i) + 0.5) / float(n))
	return out


## This house's bucket of limewash: a little warmer and lighter, or cooler and darker, than
## its neighbour's. Enough to break the terrace, not enough to break the culture. A vertex
## colour is stored at eight bits and clamps at one, so the range sits just under white.
func _wash() -> Color:
	var k := _rng.randf_range(-1.0, 1.0)
	return Color(0.93 + 0.07 * k, 0.945 + 0.055 * k, 0.97 + 0.03 * k)


func _stone_tint() -> Color:
	var k := _rng.randf_range(-1.0, 1.0)
	return Color(0.93 + 0.07 * k, 0.935 + 0.065 * k, 0.94 + 0.06 * k)


func _body(at: Vector3, basis: Basis, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.transform = Transform3D(basis, at)
	add_child(body)


# --- what is lying about -----------------------------------------------------------------------

## Buckets, carts, hay, a well. Scaled to the size of the place, so a hamlet gets a cart and a
## city gets a market; a prop the forge has not built is skipped rather than faked. Every prop
## of one forge asset is one `MultiMesh`, so eighteen hurdles of wattle fence are one draw.
func _strew(plan: Dictionary) -> void:
	var share := clampf(float(int(plan.get("count", 10))) / 26.0, 0.35, 1.6)
	var prefix := str(PROP_PREFIX.get(culture, "hearthvale"))
	# Everything is placed against the houses, not against the pad. The flattened ground is far
	# wider than the village standing on it, and props strewn across the pad end up in an empty
	# field a hundred metres from the nearest door.
	var green := maxf(_inner_radius() - 2.0, 3.0)
	var placed: Dictionary = {}          # asset path -> Array[Transform3D]
	for entry in PROPS_BY_CULTURE.get(culture, []):
		var row: Dictionary = entry
		var paths := _prop_paths(prefix, str(row.get("kind", "")))
		if paths.is_empty():
			continue
		var n := int(round(float(int(row.get("n", 1))) * share))
		for i in range(n):
			var path: String = paths[_rng.randi_range(0, paths.size() - 1)]
			var spot := _prop_spot(str(row.get("where", "green")), green)
			var yaw := _rng.randf_range(0.0, TAU)
			if not placed.has(path):
				placed[path] = []
			(placed[path] as Array).append(Transform3D(Basis(Vector3.UP, yaw), spot))
	for path in placed:
		_strew_one_kind(str(path), placed[path])


func _strew_one_kind(path: String, transforms: Array) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var mesh := WorldStreamer._mesh_of(packed, 0)
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	# The forge exports a standing prop with its feet at y = 0 (CONTRACTS §4). One that reaches
	# below is lifted by its own box, so a cart centred on its axle still sits on the ground.
	var lift := maxf(0.0, -mesh.get_aabb().position.y)
	for i in transforms.size():
		var xf: Transform3D = transforms[i]
		xf.origin.y += lift
		mm.set_instance_transform(i, xf)
	var inst := MultiMeshInstance3D.new()
	inst.name = path.get_file().get_basename()
	inst.multimesh = mm
	FabricMesh.near_only(inst, FabricMesh.PROP_RANGE_M, true)
	add_child(inst)


## Both variants of a prop, if the forge built them. Naming is `<region>_<kind>_<a|b>` and a
## one-off has only an `_a`, so asking for both and keeping what exists covers either case.
static func _prop_paths(prefix: String, kind: String) -> Array[String]:
	var out: Array[String] = []
	for variant in ["a", "b"]:
		var slug := "%s_%s_%s" % [prefix, kind, variant]
		var path := "res://assets/models/props/%s/%s.glb" % [slug, slug]
		if ResourceLoader.exists(path):
			out.append(path)
	return out


## How far out the houses actually reach, and how much open ground they leave in the middle.
## Both are measured off the plots rather than off the pad, because the pad is the ground the
## world flattened and the village is only the part of it anybody built on.
func _built_radius() -> float:
	var far := 0.0
	for rect in _plots:
		var c := rect.get_center()
		far = maxf(far, Vector2(c.x - global_position.x, c.y - global_position.z).length())
	return maxf(far, 12.0)


func _inner_radius() -> float:
	var near := 1e9
	for rect in _plots:
		var c := rect.get_center()
		near = minf(near, Vector2(c.x - global_position.x, c.y - global_position.z).length())
	return 12.0 if near > 1e8 else maxf(near - rect_margin(), 4.0)


static func rect_margin() -> float:
	return 5.0


## Where a prop of this sort belongs, in this node's local space.
func _prop_spot(where: String, green: float) -> Vector3:
	var local := Vector2.ZERO
	if where == "green" or _plots.is_empty():
		var angle := _rng.randf_range(0.0, TAU)
		local = Vector2(sin(angle), cos(angle)) * _rng.randf_range(1.5, maxf(green, 3.0))
	elif where == "edge":
		var angle2 := _rng.randf_range(0.0, TAU)
		var out := _built_radius()
		local = Vector2(sin(angle2), cos(angle2)) * _rng.randf_range(out * 0.86, out + 7.0)
	else:
		var rect := _plots[_rng.randi_range(0, _plots.size() - 1)]
		var c := rect.get_center()
		local = Vector2(c.x - global_position.x, c.y - global_position.z) \
				+ Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized() \
				* (rect.size.x * 0.5 + _rng.randf_range(0.6, 2.0))
	var world := Vector2(local.x + global_position.x, local.y + global_position.z)
	return Vector3(local.x, _ground_at(world) - global_position.y, local.y)


# --- work -------------------------------------------------------------------------------------

## A notice post on the green and a place to do the settlement's own work in the yards.
func _put_to_work() -> void:
	var green := maxf(_inner_radius() - 2.0, 3.0)
	if kind in BOARD_KINDS:
		var board := JobBoard.new()
		board.name = "JobBoard"
		board.place_id = place_id
		board.display_name = "the charter-board" if kind == "city" else "the notice post"
		board.position = _prop_spot("green", green)
		_give_a_body(board, "signpost")
		add_child(board)
	for station_kind in _work_here():
		var station := JobStation.new()
		station.kind = station_kind
		station.name = "JobStation_" + station_kind
		station.position = _prop_spot("edge" if ROOMY_STATIONS.has(station_kind) else "yard", green)
		station.rotation.y = _rng.randf_range(0.0, TAU)
		_give_a_body(station, str(STATION_PROP.get(station_kind, "crate")))
		add_child(station)


## A "for sale" board outside each house in this settlement that has a deed behind it.
## `PropertySign` was another complete, tested, self-placing node that nothing placed: six
## deeds are authored and the only way to buy one was to call `PropertyRegistry.buy()`, which
## a player cannot do. A steward still sells the same deed through dialogue; this is the board
## you walk past.
func _offer_the_empty_houses() -> void:
	var green := maxf(_inner_radius() - 2.0, 3.0)
	for def in ContentDB.all("item"):
		var property: Dictionary = def.get("property", {})
		if property.is_empty() or str(property.get("place", "")) != place_id:
			continue
		var sign_node := PropertySign.new()
		sign_node.property_id = str(def.get("id", ""))
		sign_node.name = "ForSale_" + Ids.name_of(str(def.get("id", "")))
		sign_node.position = _prop_spot("yard", green)
		sign_node.rotation.y = _rng.randf_range(0.0, TAU)
		add_child(sign_node)


## The kinds of work this settlement offers: one per trade among the people who live here,
## and its region's own work when nobody in it has an authored trade at all.
func _work_here() -> Array[String]:
	var out: Array[String] = []
	for def in ContentDB.all("interior"):
		if str(def.get("place", "")) != place_id:
			continue
		var station := str(STATION_FOR_TRADE.get(str(def.get("trade", "")), ""))
		if station != "" and not out.has(station) and out.size() < MAX_STATIONS:
			out.append(station)
	if out.is_empty():
		var own := str(STATION_BY_CULTURE.get(culture, ""))
		if own != "":
			out.append(own)
	return out


## A `JobBoard` and a `JobStation` are a collision shape and a signal each, with nothing to
## look at: they were written to be dropped into a hand-built scene beside a mesh. Out here
## they have to carry their own, so each takes the forge prop that reads as the work.
func _give_a_body(node: Node3D, prop_kind: String) -> void:
	var paths := _prop_paths(str(PROP_PREFIX.get(culture, "hearthvale")), prop_kind)
	if paths.is_empty():
		paths = _prop_paths("hearthvale", prop_kind)
	if paths.is_empty():
		return
	var packed := load(paths[0]) as PackedScene
	if packed == null:
		return
	var body := packed.instantiate()
	if body is Node3D:
		node.add_child(body)
	else:
		body.queue_free()


# --- surfaces -------------------------------------------------------------------------------

func _wall_spec() -> Dictionary:
	var by_culture: Dictionary = HouseInterior.CULTURE_SURFACES.get(
			culture, HouseInterior.CULTURE_SURFACES["vale"])
	return by_culture.get("wall", {})


func _roof_spec() -> Dictionary:
	return Building.ROOF_BY_CULTURE.get(culture, Building.ROOF_BY_CULTURE["vale"])


func _stone_spec() -> Dictionary:
	return Building.PLINTH_BY_CULTURE.get(culture, Building.PLINTH_BY_CULTURE["vale"])


func _pitch() -> float:
	return float(_roof_spec().get("pitch", 1.0))


func _roof_thick() -> float:
	return float(_roof_spec().get("thick", 0.2))


func _surface(spec: Dictionary, wear: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(Building.WALL_SHADER)
	mat.set_shader_parameter("pattern", int(spec.get("pattern", 0)))
	mat.set_shader_parameter("base_color", Color.html(str(spec.get("base", "#cccccc"))))
	mat.set_shader_parameter("accent_color", Color.html(str(spec.get("accent", "#999999"))))
	mat.set_shader_parameter("grout_color", Color.html(str(spec.get("grout", "#555555"))))
	mat.set_shader_parameter("unit_size", float(spec.get("unit", 0.32)))
	mat.set_shader_parameter("wear", wear)
	mat.set_shader_parameter("variation", 0.62)
	return mat


func _ground_at(at: Vector2) -> float:
	var provider: Object = World.terrain()
	if provider == null or not provider.has_method("get_height"):
		return global_position.y
	return float(provider.call("get_height", at.x, at.y))
