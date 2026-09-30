class_name RoadSites
extends RefCounted
## Where things can happen on the roads: the built road network read as a set of polylines with
## the features along each that an ambush or a scene wants (docs/WORLD_LIFE_ROADS.md).
##
## Every road the world was built with (RoadNetwork, world/generated/roads.json) but a town's own
## streets is walked at STEP_M, and a point along it is named for what it is:
##   `bend`   the road turns more than BEND_DEG within BEND_SPAN_M either side
##   `bridge` the road crosses a river (world/generated/rivers.json), or a POI of kind bridge
##   `pass`   the ground either side, PASS_SIDE_M out, stands PASS_RISE_M above the road
##   `woods`  the ground either side is painted forest floor or moss (the terrain's texture)
## Heights and paint are only there with a world; without one (a unit test) only bends and bridges
## are found, which is what the tests give roads for. Features are worked out a road at a time the
## first time something asks about that road, and kept.
##
## Content adds its own: a region's roadtable `sites` ([{at: {place, offset}, kind, tell}]) are sites on
## the nearest road, found as well as the land's.

const STEP_M := 20.0
const BEND_SPAN_M := 30.0
const BEND_DEG := 35.0
const PASS_SIDE_M := 22.0
const PASS_RISE_M := 5.0
const WOODS := ["forest_floor", "moss"]
const RIVERS_PATH := "res://world/generated/rivers.json"
const POIS_PATH := "res://world/generated/pois.json"
const BUCKET_M := 64.0

static var _roads: Array = []          # [{id, points: PackedVector2Array, length, cum: PackedFloat32Array}]
static var _built := false
static var _buckets: Dictionary = {}   # Vector2i -> Array of [road index, segment index]
static var _features: Dictionary = {}  # road index -> Array of {along, kind, at: Vector2, dir: Vector2}
static var _extra: Array = []          # content sites, {road, along, kind, at, dir, tell}
static var _rivers: Array = []         # PackedVector2Array each
static var _bridges: Array = []        # Vector2 of bridge pois


static func reset() -> void:
	_roads = []
	_built = false
	_buckets = {}
	_features = {}
	_extra = []
	_rivers = []
	_bridges = []


## The roads (not streets), indexed.
static func roads() -> Array:
	_build()
	return _roads


static func _build() -> void:
	if _built:
		return
	_built = true
	for r in RoadNetwork.roads():
		if RoadNetwork.is_street(str(r["id"])):
			continue
		var pts: PackedVector2Array = r["points"]
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
		_roads.append({"id": str(r["id"]), "points": pts, "length": cum[cum.size() - 1], "cum": cum,
				"width": float(r.get("width", 4.0))})
	for ri in _roads.size():
		var pts: PackedVector2Array = _roads[ri]["points"]
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			for bx in range(floori(minf(a.x, b.x) / BUCKET_M), floori(maxf(a.x, b.x) / BUCKET_M) + 1):
				for bz in range(floori(minf(a.y, b.y) / BUCKET_M), floori(maxf(a.y, b.y) / BUCKET_M) + 1):
					(_buckets.get_or_add(Vector2i(bx, bz), []) as Array).append([ri, i])
	if FileAccess.file_exists(RIVERS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RIVERS_PATH))
		if parsed is Array:
			for river in parsed:
				var line := PackedVector2Array()
				for p in (river as Dictionary).get("points", []):
					if p is Array and (p as Array).size() >= 2:
						line.append(Vector2(float(p[0]), float(p[-1])))
				if line.size() >= 2:
					_rivers.append(line)
	if FileAccess.file_exists(POIS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POIS_PATH))
		if parsed is Array:
			for p in parsed:
				var id := str((p as Dictionary).get("place_id", ""))
				if str(ContentDB.get_or_empty(id).get("kind", "")) == "bridge":
					var pos: Array = (p as Dictionary).get("pos", [])
					if pos.size() >= 3:
						_bridges.append(Vector2(float(pos[0]), float(pos[2])))


## For a test: rivers to use instead of the world's (lines of Vector2).
static func use_rivers(lines: Array) -> void:
	_build()
	_rivers = lines
	_features = {}


# --- where on the roads -------------------------------------------------------------------------

## The nearest point on any road to `p` within `reach` metres: {road, along, at, dir, dist}, or {}
## when no road is that near. `dir` points the way the road's points run.
static func nearest(p: Vector2, reach := 60.0) -> Dictionary:
	_build()
	var best: Dictionary = {}
	var best_d := reach
	var seen := {}
	for bx in range(floori((p.x - reach) / BUCKET_M), floori((p.x + reach) / BUCKET_M) + 1):
		for bz in range(floori((p.y - reach) / BUCKET_M), floori((p.y + reach) / BUCKET_M) + 1):
			for e in _buckets.get(Vector2i(bx, bz), []):
				var key := "%d/%d" % [e[0], e[1]]
				if seen.has(key):
					continue
				seen[key] = true
				var r: Dictionary = _roads[int(e[0])]
				var pts: PackedVector2Array = r["points"]
				var i := int(e[1])
				var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
				var d := q.distance_to(p)
				if d < best_d:
					best_d = d
					var cum: PackedFloat32Array = r["cum"]
					best = {"road": int(e[0]), "along": cum[i] + pts[i].distance_to(q), "at": q,
							"dir": (pts[i + 1] - pts[i]).normalized(), "dist": d}
	return best


## The point `along` metres down road `road` (clamped to its ends): {at, dir}.
static func point_at(road: int, along: float) -> Dictionary:
	_build()
	if road < 0 or road >= _roads.size():
		return {"at": Vector2.INF, "dir": Vector2.ZERO}
	var r: Dictionary = _roads[road]
	var pts: PackedVector2Array = r["points"]
	var cum: PackedFloat32Array = r["cum"]
	var s := clampf(along, 0.0, float(r["length"]))
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := maxf(cum[hi] - cum[lo], 0.001)
	return {"at": pts[lo].lerp(pts[hi], (s - cum[lo]) / seg), "dir": (pts[hi] - pts[lo]).normalized()}


static func length_of(road: int) -> float:
	_build()
	return float(_roads[road]["length"]) if road >= 0 and road < _roads.size() else 0.0


static func road_id(road: int) -> String:
	_build()
	return str(_roads[road]["id"]) if road >= 0 and road < _roads.size() else ""


# --- features -----------------------------------------------------------------------------------

## The features along one road, worked out the first time: [{along, kind, at, dir}].
static func features(road: int) -> Array:
	_build()
	if _features.has(road):
		return _features[road]
	var out: Array = []
	if road < 0 or road >= _roads.size():
		return out
	var r: Dictionary = _roads[road]
	var length := float(r["length"])
	var s := STEP_M
	var last_kind_at := {}
	while s < length - STEP_M:
		var here := point_at(road, s)
		var at: Vector2 = here["at"]
		var dir: Vector2 = here["dir"]
		for kind in _kinds_at(road, s, at, dir):
			# one of a kind every 80 m is enough: a long bend is one bend
			if s - float(last_kind_at.get(kind, -INF)) < 80.0:
				continue
			last_kind_at[kind] = s
			out.append({"along": s, "kind": kind, "at": at, "dir": dir})
		s += STEP_M
	for e in _extra:
		if int(e["road"]) == road:
			out.append(e)
	_features[road] = out
	return out


static func _kinds_at(road: int, s: float, at: Vector2, dir: Vector2) -> Array:
	var kinds: Array = []
	var before: Vector2 = point_at(road, s - BEND_SPAN_M)["at"]
	var after: Vector2 = point_at(road, s + BEND_SPAN_M)["at"]
	var a := (at - before)
	var b := (after - at)
	if a.length() > 1.0 and b.length() > 1.0 and rad_to_deg(absf(a.angle_to(b))) >= BEND_DEG:
		kinds.append("bend")
	if _crosses_river(before, after) or _near_bridge(at):
		kinds.append("bridge")
	var side := Vector2(-dir.y, dir.x)
	if WorldProbe.has_world() and World.instance != null:
		var h := World.get_height(at.x, at.y)
		var l := World.get_height(at.x + side.x * PASS_SIDE_M, at.y + side.y * PASS_SIDE_M)
		var rr := World.get_height(at.x - side.x * PASS_SIDE_M, at.y - side.y * PASS_SIDE_M)
		if l - h >= PASS_RISE_M and rr - h >= PASS_RISE_M:
			kinds.append("pass")
		var t := World.terrain()
		if t != null:
			var p1 := at + side * 10.0
			var p2 := at - side * 10.0
			if t.texture_at(p1.x, p1.y) in WOODS and t.texture_at(p2.x, p2.y) in WOODS:
				kinds.append("woods")
	return kinds


static func _crosses_river(a: Vector2, b: Vector2) -> bool:
	for line in _rivers:
		var pts: PackedVector2Array = line
		for i in range(pts.size() - 1):
			if Geometry2D.segment_intersects_segment(a, b, pts[i], pts[i + 1]) != null:
				return true
	return false


static func _near_bridge(at: Vector2) -> bool:
	for p in _bridges:
		if (p as Vector2).distance_to(at) < 25.0:
			return true
	return false


## A site content names: on the nearest road to `at`, of `kind`, and whatever else it carries.
static func add_site(site: Dictionary) -> bool:
	var raw: Variant = site.get("at", [])
	var p := Vector2.INF
	if PlaceRef.is_spec(raw):
		# said beside a place ({"place", "offset"}), so it goes where the place goes when the map is
		# redrawn (docs/COORDINATES.md)
		p = PlaceRef.point_xz(raw as Dictionary)
	elif raw is Array and (raw as Array).size() >= 2:
		p = Vector2(float(raw[0]), float(raw[1]))
	if p == Vector2.INF:
		return false
	var near := nearest(p, 120.0)
	if near.is_empty():
		return false
	var e := site.duplicate(true)
	e["road"] = int(near["road"])
	e["along"] = float(near["along"])
	e["at"] = near["at"]
	e["dir"] = near["dir"]
	e["kind"] = str(site.get("kind", "bend"))
	_extra.append(e)
	_features.erase(int(near["road"]))
	return true


## The first feature of one of `kinds` (any kind when empty) on `road` between `from_m` and `to_m`
## along it, going the way `way` (+1 down the road's points, -1 up them); {} when none.
static func feature_ahead(road: int, from_m: float, way: int, lo_m: float, hi_m: float, kinds: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for f in features(road):
		var d := (float(f["along"]) - from_m) * float(way)
		if d < lo_m or d > hi_m:
			continue
		if not kinds.is_empty() and not kinds.has(str(f["kind"])):
			continue
		if d < best_d:
			best_d = d
			best = f
	return best


## The kind of ground beside the road at `at`: what a roadtable row's `biome` is matched against.
## `woods`, `marsh`, `upland`, `ash`, `shore` or `fields`; `open` with no world to ask.
static func biome_at(at: Vector2) -> String:
	var t := World.terrain() if World.instance != null else null
	if t == null:
		return "open"
	var counts := {}
	for off in [Vector2(12, 0), Vector2(-12, 0), Vector2(0, 12), Vector2(0, -12)]:
		var p: Vector2 = at + off
		var b := biome_of_paint(t.texture_at(p.x, p.y))
		counts[b] = int(counts.get(b, 0)) + 1
	var best := "open"
	var n := 0
	for k in counts:
		if int(counts[k]) > n:
			n = int(counts[k])
			best = str(k)
	return best


static func biome_of_paint(paint: String) -> String:
	match paint:
		"forest_floor", "moss":
			return "woods"
		"mud", "peat", "lake_bed":
			return "marsh"
		"granite", "limestone", "scree", "snow", "heather", "crag", "talus":
			return "upland"
		"ash_soil", "grey_grass", "fused_stone":
			return "ash"
		"shingle", "sand_flats":
			return "shore"
		"vale_grass", "chalk", "barley", "orchard_grass", "cobbles", "dirt_path":
			return "fields"
	return "open"
