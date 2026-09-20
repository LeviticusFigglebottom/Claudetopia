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
## Each filler building is two draw calls: everything in the wall material merged into one
## mesh, everything in the roof material into another. Fifty of them cost what six of
## `Building`'s full houses would, which is the whole reason they are a separate thing.

const STOREY_M := 2.6
const SETBACK_M := 3.2                ## from the road edge to the front wall
const ROAD_HALF_M := 3.0
const GAP_M := 2.4                    ## between neighbours along a frontage
const PLINTH_H := 0.4

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
## What the forge has that reads as the work from a few paces off. A chopping block and a peat
## bank are still owed — a crate of billets and a bucket at the cut are standing in, and they
## are written down here rather than quietly chosen.
const STATION_PROP := {
	"smith": "anvil", "brew": "barrel", "fish": "dock_post", "chop": "crate", "dig": "bucket",
}
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
	var walls := SurfaceTool.new()
	var roofs := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	roofs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
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
		_one_house(walls, roofs, unit, centre, w, d, n, _yaws[i], standing)
		raised += 1
	if raised == 0:
		return
	_commit(walls, _surface(_wall_spec(), 0.45), "Walls")
	_commit(roofs, _surface(_roof_spec(), 0.5), "Roofs")


func _one_house(walls: SurfaceTool, roofs: SurfaceTool, unit: BoxMesh, centre: Vector2,
		w: float, d: float, storeys: int, yaw: float, standing: bool) -> void:
	var ground := _ground_at(centre) - global_position.y
	var h := STOREY_M * storeys
	var basis := Basis(Vector3.UP, yaw)
	var origin := Vector3(centre.x - global_position.x, ground, centre.y - global_position.z)

	var plinth := Transform3D(basis, origin + Vector3(0.0, PLINTH_H * 0.5 - 0.14, 0.0))
	walls.append_from(unit, 0, plinth.scaled_local(Vector3(w + 0.16, PLINTH_H, d + 0.16)))
	var body := Transform3D(basis, origin + Vector3(0.0, h * 0.5, 0.0))
	walls.append_from(unit, 0, body.scaled_local(Vector3(w, h, d)))
	var stack := Transform3D(basis, origin + basis * Vector3(w * 0.5 - 0.5, 0.0, 0.0)
			+ Vector3(0.0, (h + d * 0.5 * _pitch() + 1.0) * 0.5, 0.0))
	walls.append_from(unit, 0, stack.scaled_local(
			Vector3(0.62, h + d * 0.5 * _pitch() + 1.0, 0.62)))
	# a shuttered opening, so the wall is not blank from the street
	var face := Transform3D(basis, origin + basis * Vector3(0.0, 0.0, -d * 0.5 - 0.06)
			+ Vector3(0.0, 1.05, 0.0))
	walls.append_from(unit, 0, face.scaled_local(Vector3(1.1, 2.1, 0.12)))
	if not standing:
		return

	var pitch := _pitch()
	var thick := _roof_thick()
	var span := d + 0.9
	var length := w + 0.9
	var rise := span * 0.5 * pitch
	var slope := sqrt(span * span * 0.25 + rise * rise)
	var angle := atan2(rise, span * 0.5)
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		var normal := Vector3(0.0, span * 0.5, side * rise).normalized()
		var mid := Vector3(0.0, rise * 0.5, side * span * 0.25)
		var local := Transform3D(Basis(Vector3.RIGHT, side * angle), mid - normal * (thick * 0.5))
		var xf := Transform3D(basis, origin + Vector3(0.0, h, 0.0)) * local
		roofs.append_from(unit, 0, xf.scaled_local(Vector3(length, thick, slope + thick * 0.6)))
	_body(origin + Vector3(0.0, h * 0.5, 0.0), basis, Vector3(w, h, d))


func _commit(st: SurfaceTool, mat: Material, node_name: String) -> void:
	st.generate_normals()
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.name = node_name
	add_child(inst)


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
## city gets a market; a prop the forge has not built is skipped rather than faked.
func _strew(plan: Dictionary) -> void:
	var share := clampf(float(int(plan.get("count", 10))) / 26.0, 0.35, 1.6)
	var prefix := str(PROP_PREFIX.get(culture, "hearthvale"))
	# Everything is placed against the houses, not against the pad. The flattened ground is far
	# wider than the village standing on it, and props strewn across the pad end up in an empty
	# field a hundred metres from the nearest door.
	var green := maxf(_inner_radius() - 2.0, 3.0)
	for entry in PROPS_BY_CULTURE.get(culture, []):
		var row: Dictionary = entry
		var kind := str(row.get("kind", ""))
		var paths := _prop_paths(prefix, kind)
		if paths.is_empty():
			continue
		var n := int(round(float(int(row.get("n", 1))) * share))
		for i in range(n):
			var packed := load(paths[_rng.randi_range(0, paths.size() - 1)]) as PackedScene
			if packed == null:
				continue
			var node := packed.instantiate()
			if not (node is Node3D):
				node.queue_free()
				continue
			var prop: Node3D = node
			prop.position = _prop_spot(str(row.get("where", "green")), green)
			prop.rotation.y = _rng.randf_range(0.0, TAU)
			add_child(prop)


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
		station.position = _prop_spot("yard", green)
		station.rotation.y = _rng.randf_range(0.0, TAU)
		_give_a_body(station, str(STATION_PROP.get(station_kind, "crate")))
		add_child(station)


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
