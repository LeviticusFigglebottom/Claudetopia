class_name RoadNetwork
extends RefCounted
## The roads the world was built with (world/generated/roads.json), and where each way along
## them goes.
##
## Every road is built between two places and runs from one to the other, so a point on a road
## knows where it leads both ways: the place at each end. That is what a fingerpost says, and it
## is read here at runtime from the roads and the places rather than written down anywhere, so a
## rebuilt road network is signposted the moment it exists.

const PATH := "res://world/generated/roads.json"
## A way that ends this close to where you stand ends here: the fingerpost in a town's square does
## not point back at the town.
const HERE_M := 45.0
## How far from a road's end its place may stand: roads end on a place's centre, near enough.
const END_M := 70.0
## How far down the road an arm is aimed, so it points along the road rather than across a bend.
const AIM_M := 40.0

static var _roads: Array = []
static var _loaded := false
static var _places: Array = []


## Every road: {id, points (PackedVector2Array, world xz)}.
static func roads() -> Array:
	if _loaded:
		return _roads
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return _roads
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_ARRAY:
		return _roads
	for entry in parsed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pts := PackedVector2Array()
		for p in (entry as Dictionary).get("points", []):
			if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
				pts.append(Vector2(float(p[0]), float(p[1])))
		if pts.size() >= 2:
			_roads.append({"id": str((entry as Dictionary).get("id", "")), "points": pts})
	return _roads


## The Wardens' mile, in metres.
const MILE_M := 1609.344


## A distance as a fingerpost cuts it: miles to the nearest quarter, never less than a quarter
## ("¼", "½", "¾", "1", "1¼" ...). tools/world/atlas/signposts.py says the same.
static func miles(metres: float) -> String:
	var q := maxi(1, int(round(metres / MILE_M * 4.0)))
	var whole := int(floor(q / 4.0))
	var frac: String = ["", "¼", "½", "¾"][q % 4]
	return ("%d%s" % [whole, frac]) if whole > 0 else frac


## For a test: the roads to use instead of the world's.
static func use(road_list: Array, place_list: Array = []) -> void:
	_roads = road_list
	_loaded = true
	_places = place_list


static func forget() -> void:
	_roads = []
	_loaded = false
	_places = []


## A settlement's own street (the world lays one or two through each place) is no road to anywhere.
static func is_street(id: String) -> bool:
	return id.ends_with("_street") or id.ends_with("_street_cross")


## The places a road can end at: {id, name, at (world xz)}, the ones the world has put somewhere.
## A point of interest is one too: the roads to the Three Sisters, the Narrows Bridge and the Rudd
## Mouth end at points of interest, and a fingerpost that named only places left those ways blank.
static func places() -> Array:
	if not _places.is_empty():
		return _places
	var world := World.instance
	if world == null:
		return _places
	for kind in ["place", "poi"]:
		for def in ContentDB.all(kind):
			var id := str(def.get("id", ""))
			var at := world.place_position(id)
			if at == Vector3.ZERO:
				continue
			_places.append({"id": id, "name": str(def.get("name", Ids.name_of(id))), "at": Vector2(at.x, at.z)})
	return _places


## Where the roads that pass within `reach` of `at` go: one entry for each way out that leads
## somewhere else, {dir (unit, world xz, pointing down the road), place, name, metres (along the
## road)}. Two ways to one place keep the shorter; two ways that leave along the same line keep the
## nearer place, which is the one a traveller on that road comes to first.
static func destinations(at: Vector2, reach := 30.0) -> Array:
	var found: Array = []
	for r in roads():
		if is_street(str(r["id"])):
			continue
		var pts: PackedVector2Array = r["points"]
		var k := 0
		var best := INF
		for i in range(pts.size()):
			var d := pts[i].distance_to(at)
			if d < best:
				best = d
				k = i
		if best > reach:
			continue
		for dir_v in [1, -1]:
			var dir := int(dir_v)
			var end := pts[pts.size() - 1] if dir > 0 else pts[0]
			if end.distance_to(at) < HERE_M:
				continue
			var place := _place_near(end)
			if place.is_empty():
				continue
			var aim := _along(pts, k, dir, AIM_M)
			var way := aim - at
			if way.length() < 1.0:
				continue
			found.append({"dir": way.normalized(), "place": place["id"], "name": place["name"],
					"metres": _run(pts, k, dir)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["metres"]) < float(b["metres"]))
	var out: Array = []
	for f in found:
		var keep := true
		for o in out:
			if str(o["place"]) == str(f["place"]) or (o["dir"] as Vector2).dot(f["dir"]) > 0.97:
				keep = false
				break
		if keep:
			out.append(f)
	return out


static func _place_near(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := END_M
	for place in places():
		var d := (place["at"] as Vector2).distance_to(p)
		if d < best_d:
			best_d = d
			best = place
	return best


## The point `metres` along the polyline from point `k` in direction `dir`.
static func _along(pts: PackedVector2Array, k: int, dir: int, metres: float) -> Vector2:
	var left := metres
	var i := k
	while i + dir >= 0 and i + dir < pts.size():
		var a := pts[i]
		var b := pts[i + dir]
		var seg := a.distance_to(b)
		if seg >= left:
			return a.lerp(b, left / maxf(seg, 0.001))
		left -= seg
		i += dir
	return pts[i]


static func _run(pts: PackedVector2Array, k: int, dir: int) -> float:
	var total := 0.0
	var i := k
	while i + dir >= 0 and i + dir < pts.size():
		total += pts[i].distance_to(pts[i + dir])
		i += dir
	return total
