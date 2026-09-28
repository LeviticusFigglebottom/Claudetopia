class_name TravelPlaces
extends RefCounted
## Where the road sets somebody down at a place they have been (triage 43: fast travel to any
## explored place, not only a lit Hearthstone).
##
## Every entry in the built world's pois.json is somewhere a body can be set down: a point of
## interest, a settlement, a landmark, a deep place's hill. Where a dressing stands there (every
## POI, and a place whose data raises a Hearthstone) it is that dressing's own arrival
## (PoiDressing.arrival_for: open, dry ground clear of everything it stood up), as the stones'
## road always was. Anywhere else, and wherever that arrival lands on something this cannot see
## from the dressing alone (a landmark's own bulk, a deep place's mouth, water), it is the edge of
## the place on the road in: a town's fabric stands inside its flattened pad, its houses front
## the streets and its gardens run back from them, so the carriageway a few paces past the pad's
## lip is ground nobody built on. With no road, a ring round the pad. Either way on the terrain
## itself (never a roof), dry, not steep, outside every other place's pad, and facing into the
## place. `Hearth._travel` checks the body once the country stands and steps it clear if the
## world's own colliders (a tree, a rock) are where it was put.

const POIS_PATH := "res://world/generated/pois.json"
const DOOR_PLANS_ROLE := "door_plan"
## How far past the pad's lip the road's set-down wants to be, and how far out along a road, or
## round a ring, it looks.
const EDGE_OUT_M := 6.0
const ROAD_FROM_M := 2.0
const ROAD_REACH_M := 45.0
const RING_FROM_M := 9.0
const RING_OUT_M := 90.0
const SHORE_OUT_M := 450.0
const SAMPLE_M := 2.0
## A settlement's gardens reach this far past its pad (StreetPlan.GARDEN_PAST_EDGE_M) and a little.
const FABRIC_PAST_EDGE_M := 8.0
## Kept clear of a deep place's mouth (WorldDoors reserves 22 m square round one) and of a landmark
## model's footprint (a tall one only: the Chalk Hound is cut into the turf and is walked on).
const MOUTH_CLEAR_M := 11.0
const LANDMARK_CLEAR_M := 2.5
const LANDMARK_TALL_M := 2.0
## Steepest ground a body is set down on: the rise across a stride either way.
const STEEP_RISE_M := 1.1
const STRIDE_M := 1.5

static var _entries: Dictionary = {}       # id -> pois.json entry
static var _landmarks: Array = []          # [{id, xz: Vector2, r: float}]
static var _mouths: Array = []             # [{id, xz: Vector2}]


## The pois.json entries, by id: every place the world stands up, read once.
static func entries() -> Dictionary:
	if not _entries.is_empty() or not FileAccess.file_exists(POIS_PATH):
		return _entries
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POIS_PATH))
	if typeof(parsed) != TYPE_ARRAY:
		return _entries
	for e_v in parsed:
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_v
		var pos: Array = e.get("pos", [])
		if pos.size() < 3:
			continue
		var id := str(e.get("place_id", ""))
		_entries[id] = e
		if e.has("scene"):
			var b: Dictionary = PoiKit.meta(str(e["scene"])).get("bounds", {})
			if float(b.get("height", 0.0)) > LANDMARK_TALL_M:
				var lo: Array = b.get("min", [0.0, 0.0, 0.0])
				var hi: Array = b.get("max", [0.0, 0.0, 0.0])
				var r := Vector2(maxf(absf(float(lo[0])), absf(float(hi[0]))),
						maxf(absf(float(lo[2])), absf(float(hi[2])))).length()
				_landmarks.append({"id": id, "xz": Vector2(float(pos[0]), float(pos[2])), "r": r})
	for plan in ContentDB.all("table"):
		if str(plan.get("role", "")) != DOOR_PLANS_ROLE:
			continue
		var e: Dictionary = _entries.get(str(plan.get("place", "")), {})
		if e.is_empty():
			continue
		var c: Array = e["pos"]
		for row_v in plan.get("rows", []):
			var row: Dictionary = row_v if typeof(row_v) == TYPE_DICTIONARY else {}
			if row.is_empty() or str(row.get("kind", "")) == "house":
				continue
			var bearing := deg_to_rad(float(row.get("bearing_deg", 0.0)))
			var ring := float(row.get("ring_radius", 20.0))
			_mouths.append({"id": str(plan.get("place", "")),
					"xz": Vector2(float(c[0]) + sin(bearing) * ring, float(c[2]) + cos(bearing) * ring)})
	return _entries


static func has(id: String) -> bool:
	return entries().has(id)


## Where the place stands (its pois.json centre), or INF.
static func centre_of(id: String) -> Vector3:
	var e: Dictionary = entries().get(id, {})
	if e.is_empty():
		return Vector3.INF
	var p: Array = e["pos"]
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


## Where somebody arriving at `id` is set down, and what they face (the place's centre):
## {at: Vector3, face: Vector3}, or {} for a place the world does not have. `terrain` and `roads`
## default to the running world's; a test hands in its own.
static func set_down(id: String, terrain: TerrainProvider = null, roads: Array = []) -> Dictionary:
	if not has(id):
		return {}
	if terrain == null:
		terrain = World.terrain()
	var centre := centre_of(id)
	var at := PoiDressing.arrival_for(id, terrain, roads)
	if at != Vector3.INF and open_ground(at, id, terrain):
		return {"at": at, "face": centre, "how": "dressing"}
	var edge := edge_of(id, terrain, roads)
	if edge != Vector3.INF:
		return {"at": edge, "face": centre, "how": "edge"}
	if at != Vector3.INF:
		return {"at": at, "face": centre, "how": "dressing"}
	var y := terrain.get_height(centre.x, centre.z) if terrain != null else centre.y
	return {"at": Vector3(centre.x, y, centre.z), "face": centre + Vector3(0.0, 0.0, -1.0), "how": "centre"}


## Whether `at` is somewhere a body may be put for `id`: dry, not steep (where it is on the
## terrain), and clear of a tall landmark's footprint and a deep place's mouth.
static func open_ground(at: Vector3, id: String, terrain: TerrainProvider) -> bool:
	entries()
	var xz := Vector2(at.x, at.z)
	for lm in _landmarks:
		if xz.distance_to(lm["xz"]) < float(lm["r"]) + LANDMARK_CLEAR_M:
			return false
	for m in _mouths:
		if xz.distance_to(m["xz"]) < MOUTH_CLEAR_M:
			return false
	if terrain == null:
		return true
	if is_wet(at, terrain):
		return false
	var ground := terrain.get_height(at.x, at.z)
	if absf(at.y - ground) < 0.5 and is_steep(at, terrain):
		return false
	return true


## Standing in water: the water's surface over the feet at all, so a bridge's deck is dry and a
## ford is not (stricter than PoiKit.in_water, which lets a prop's foot stand a hand deep).
static func is_wet(at: Vector3, terrain: TerrainProvider) -> bool:
	if terrain == null or not terrain.is_water(at.x, at.z):
		return false
	var level := terrain.water_level_at(at.x, at.z)
	return level > TerrainProvider.NO_WATER * 0.5 and at.y < level - WET_M


## Water this shallow over the feet is a puddle, not a place to be set down in.
const WET_M := 0.05


## Ground that rises more than a step across a stride, any way.
static func is_steep(at: Vector3, terrain: TerrainProvider) -> bool:
	var h := terrain.get_height(at.x, at.z)
	for d in [Vector2(STRIDE_M, 0.0), Vector2(0.0, STRIDE_M), Vector2(-STRIDE_M, 0.0), Vector2(0.0, -STRIDE_M)]:
		if absf(terrain.get_height(at.x + d.x, at.z + d.y) - h) > STEEP_RISE_M:
			return true
	return false


## The edge of the place on a road in, or on a ring round it: INF where nowhere is open.
static func edge_of(id: String, terrain: TerrainProvider, roads: Array = []) -> Vector3:
	var e: Dictionary = entries().get(id, {})
	if e.is_empty():
		return Vector3.INF
	var c3 := centre_of(id)
	var c := Vector2(c3.x, c3.z)
	var r := float(e.get("radius_flat_m", 25.0))
	var kind := str(ContentDB.get_or_empty(id).get("kind", ""))
	var fabric := Settlement.FABRIC.has(kind)
	if roads.is_empty():
		roads = WorldPois.roads_from_disk()
	# on a road in, nearest to a few paces past the lip first
	var want := r + EDGE_OUT_M
	var on_road: Array = []
	for line_v in roads:
		if typeof(line_v) != TYPE_ARRAY:
			continue
		var line: Array = line_v
		for i in range(line.size() - 1):
			var a := _xz(line[i])
			var b := _xz(line[i + 1])
			var n := maxi(1, int(ceil(a.distance_to(b) / SAMPLE_M)))
			for k in n:
				var p := a.lerp(b, float(k) / float(n))
				var d := p.distance_to(c)
				if d >= r + ROAD_FROM_M and d <= r + ROAD_REACH_M:
					on_road.append({"p": p, "score": absf(d - want)})
	on_road.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["score"]) < float(y["score"]))
	for cand in on_road:
		var at := _try(cand["p"], id, terrain)
		if at != Vector3.INF:
			return at
	# no road in (a landmark on a moor, a deep place's hill): a ring round the pad, nearest first
	var from := r + (FABRIC_PAST_EDGE_M if fabric else 0.0) + RING_FROM_M * (0.0 if fabric else 1.0)
	from = maxf(from, r + 3.0)
	var rr := from
	while rr <= r + RING_OUT_M:
		var steps := 32
		for i in steps:
			var ang := TAU * float(i) / float(steps)
			var at := _try(c + Vector2(sin(ang), cos(ang)) * rr, id, terrain)
			if at != Vector3.INF:
				return at
		rr += 3.0
	# out on the water (the Bell Field's buoys): the nearest open shore, however far
	while rr <= SHORE_OUT_M:
		for i in 48:
			var ang := TAU * float(i) / 48.0
			var at := _try(c + Vector2(sin(ang), cos(ang)) * rr, id, terrain)
			if at != Vector3.INF:
				return at
		rr += 6.0
	return Vector3.INF


static func _try(p: Vector2, id: String, terrain: TerrainProvider) -> Vector3:
	if not _outside_other_places(p, id):
		return Vector3.INF
	var y := terrain.get_height(p.x, p.y) if terrain != null else centre_of(id).y
	var at := Vector3(p.x, y, p.y)
	return at if open_ground(at, id, terrain) else Vector3.INF


## Outside every other place's flattened pad (what a dressing or a town builds stays inside its
## own; a town's gardens a few paces past it).
static func _outside_other_places(p: Vector2, id: String) -> bool:
	for other_id in entries():
		if other_id == id:
			continue
		var e: Dictionary = _entries[other_id]
		var pos: Array = e["pos"]
		var r := float(e.get("radius_flat_m", 25.0))
		if Settlement.FABRIC.has(str(ContentDB.get_or_empty(str(other_id)).get("kind", ""))):
			r += FABRIC_PAST_EDGE_M
		if p.distance_to(Vector2(float(pos[0]), float(pos[2]))) < r + PoiDressing.ARRIVAL_RADIUS_M:
			return false
	return true


static func _xz(v: Variant) -> Vector2:
	var a: Array = v if typeof(v) == TYPE_ARRAY else [0.0, 0.0]
	return Vector2(float(a[0]), float(a[1]))
