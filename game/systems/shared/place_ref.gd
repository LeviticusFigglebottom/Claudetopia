class_name PlaceRef
## A point on the map said as a place and where from it, so that it goes where the place goes.
##
## The map is drawn by hand (tools/world/atlas) and it will be drawn again. A place that moves
## takes along everything said relative to it; anything that wrote down coordinates stays behind
## in the old country. docs/COORDINATES.md lists who holds which. These are the ways to say
## "near that place":
##
##   {"place": id, "bearing": deg, "distance": m, "height": m}
##       a compass bearing from the place (0 north = -z, 90 east = +x) and a distance, `height`
##       metres above the ground there: the opening's cinematic says its cameras this way
##       (`CinematicPath.point_of`), and so do the capture plans.
##   {"place": id, "offset": [dx, dz]}
##       metres east (+x) and south (+z) of the place; may carry a bearing and distance too.
##   a way's `shape`: [[along, across], ...] in the frame that runs from one place, (0, 0), to
##       another, (1, 0); `across` is to the right of somebody walking it, in the same units.
##       The way stretches and turns with its two ends (`along`).
##   `pin(pos)` and `follow(pos, pin)`: a remembered position (a save) kept beside the place
##       nearest it, so a load into a redrawn map puts it back beside that place.
##
## A place's position is its definition's `position` (a place's or a POI's), which is what the
## atlas writes; the ground comes from `WorldProbe`.

## A place that has moved less than this has not moved: a save loads exactly where it was made.
const MOVED_M := 0.5
## Beyond this in x or z is not the map: an interior's pocket, say, which no place moves.
const MAP_HALF_M := 4096.0
## Definitions that stand somewhere on the map, in the order a pin prefers them at equal range.
const ANCHOR_TYPES: Array[String] = ["place", "poi"]


## Where a place or a POI stands on the map as [x, z]; Vector2.INF when it says nowhere.
static func xz(place_id: String) -> Vector2:
	if place_id == "":
		return Vector2.INF
	return _xz_of(ContentDB.get_or_empty(place_id))


static func _xz_of(def: Dictionary) -> Vector2:
	var raw: Variant = def.get("position", null)
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 2:
		return Vector2.INF
	return Vector2(float(raw[0]), float(raw[1]))


## Whether a value is a place-relative spec rather than coordinates.
static func is_spec(v: Variant) -> bool:
	return typeof(v) == TYPE_DICTIONARY and str((v as Dictionary).get("place", "")) != ""


## A spec as a point on the map, [x, z]; Vector2.INF when its place says nowhere.
static func point_xz(spec: Dictionary) -> Vector2:
	var at := xz(str(spec.get("place", "")))
	if at == Vector2.INF:
		return Vector2.INF
	var o: Variant = spec.get("offset", null)
	if typeof(o) == TYPE_ARRAY and (o as Array).size() >= 2:
		at += Vector2(float(o[0]), float(o[1]))
	var b := deg_to_rad(float(spec.get("bearing", 0.0)))
	var d := float(spec.get("distance", 0.0))
	return at + Vector2(sin(b) * d, -cos(b) * d)


## A spec as a point in the world, `height` metres above the ground there; Vector3.INF when its
## place says nowhere.
static func point(spec: Dictionary) -> Vector3:
	var p := point_xz(spec)
	if p == Vector2.INF:
		return Vector3.INF
	return Vector3(p.x, WorldProbe.get_height(p.x, p.y) + float(spec.get("height", 0.0)), p.y)


## A way's `shape` as map points, in the frame from `from_id` (0, 0) to `to_id` (1, 0). Empty
## when either end says nowhere, or the two stand on each other.
static func along(from_id: String, to_id: String, shape: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var a := xz(from_id)
	var b := xz(to_id)
	if a == Vector2.INF or b == Vector2.INF or a.distance_to(b) < 0.01:
		return out
	var u := b - a
	var right := Vector2(-u.y, u.x)
	for p in shape:
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
			out.append(a + u * float(p[0]) + right * float(p[1]))
	return out


## The inverse of `along` for one point: where `p` stands in the frame from `a` to `b`.
static func shape_of(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var u := b - a
	var len2 := u.length_squared()
	if len2 < 0.0001:
		return Vector2.ZERO
	var right := Vector2(-u.y, u.x)
	return Vector2((p - a).dot(u) / len2, (p - a).dot(right) / len2)


## The place or POI nearest a map point, as its id; "" when none stands within `max_m`.
static func nearest(at: Vector2, max_m := INF) -> String:
	var best := ""
	var best_d := max_m
	for type in ANCHOR_TYPES:
		for def in ContentDB.all(type):
			var p := _xz_of(def)
			if p == Vector2.INF:
				continue
			var d := at.distance_to(p)
			if d < best_d:
				best_d = d
				best = str(def.get("id", ""))
	return best


## A remembered position as the place nearest it: {"place", "at": [x, z] where that place
## stood, "rise": metres above the ground}. Empty for a point off the map (an interior's pocket),
## or on a map with no places at all: such a position is simply kept.
static func pin(pos: Vector3) -> Dictionary:
	if not pos.is_finite() or absf(pos.x) > MAP_HALF_M or absf(pos.z) > MAP_HALF_M:
		return {}
	var id := nearest(Vector2(pos.x, pos.z))
	if id == "":
		return {}
	var at := xz(id)
	return {"place": id, "at": [at.x, at.y], "rise": snappedf(pos.y - WorldProbe.get_height(pos.x, pos.z, pos.y), 0.01)}


## Where a pinned position stands in this world. While its place has not moved, exactly where it
## was; once the place has moved, moved with it and set down at the height it had above the
## ground. A pin that names a place this world lacks, or no pin at all, keeps the position.
static func follow(pos: Vector3, pin_v: Variant) -> Vector3:
	if typeof(pin_v) != TYPE_DICTIONARY:
		return pos
	var p: Dictionary = pin_v
	var now := xz(str(p.get("place", "")))
	var then_v: Variant = p.get("at", null)
	if now == Vector2.INF or typeof(then_v) != TYPE_ARRAY or (then_v as Array).size() < 2:
		return pos
	var shift := now - Vector2(float(then_v[0]), float(then_v[1]))
	if shift.length() < MOVED_M:
		return pos
	var x := pos.x + shift.x
	var z := pos.z + shift.y
	var rise := maxf(float(p.get("rise", 0.0)), 0.0)
	return Vector3(x, WorldProbe.get_height(x, z, pos.y) + rise, z)
