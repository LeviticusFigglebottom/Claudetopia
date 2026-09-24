class_name RoadRoutes
## The way somebody walks from one place to another: along the built roads.
##
## A schedule that takes a person from Pilgrim's Ash to Merrowby used to have them set out twenty
## game-minutes before they were due and stand up at the far end, whatever lay between; nobody was
## ever met on a road. This reads the roads the world builder laid (`world/generated/roads.json`),
## joins them where their ends meet, and answers two things: how long the walk is, and where along
## it somebody a given share of the way there is standing. `Schedules` asks the first, to set out
## in time; `NpcRegistry` asks the second, to stand a traveller on the road and walk them along it.
##
## A place whose pad no road reaches (a point of interest out on the heath) is walked to straight
## from the nearest road end within reach; two places with no roads between them at all get the
## straight line. With no built world (a headless test with no roads file) there are no routes and
## every question answers as though the places were a straight line apart, or not at all.

const ROADS_PATH := "res://world/generated/roads.json"
## Road ends this close together are one junction.
const JOIN_M := 22.0
## How far from a place's pad a road end may be and still be that place's road.
const REACH_M := 140.0
## A place further than this from any road end is walked to across country from the nearest one.
const ACROSS_M := 900.0

static var _built := false
static var _nodes: Array[Vector2] = []          # junctions
static var _edges: Dictionary = {}              # node index -> [[other index, length, PackedVector2Array from this end]]
static var _routes: Dictionary = {}             # "a|b" -> PackedVector2Array


## Drops everything read, so the next question reads the roads again (a new world was built).
static func reset() -> void:
	_built = false
	_nodes.clear()
	_edges.clear()
	_routes.clear()


## The walk from one place to another as points on the ground ([x, z]), from `from`'s pad to
## `to`'s. Empty when either place is unknown.
static func route(from: String, to: String) -> PackedVector2Array:
	if from == "" or to == "" or from == to:
		return PackedVector2Array()
	var key := "%s|%s" % [from, to]
	if _routes.has(key):
		return _routes[key]
	var a := _xz(from)
	var b := _xz(to)
	var out := PackedVector2Array()
	if a != Vector2.INF and b != Vector2.INF:
		out = _walk(a, b)
	_routes[key] = out
	return out


## Metres from one place to the other along the roads; -1 when either is unknown.
static func length_between(from: String, to: String) -> float:
	var r := route(from, to)
	return length_of(r) if r.size() >= 2 else -1.0


static func length_of(r: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(r.size() - 1):
		total += r[i].distance_to(r[i + 1])
	return total


## The point `metres` along a route (clamped to its ends), and the way the road runs there.
static func point_along(r: PackedVector2Array, metres: float) -> Dictionary:
	if r.size() == 0:
		return {"at": Vector2.INF, "dir": Vector2.ZERO}
	if r.size() == 1:
		return {"at": r[0], "dir": Vector2.ZERO}
	var left := maxf(metres, 0.0)
	for i in range(r.size() - 1):
		var seg := r[i].distance_to(r[i + 1])
		if left <= seg or i == r.size() - 2:
			var t := clampf(left / seg, 0.0, 1.0) if seg > 0.0 else 1.0
			return {"at": r[i].lerp(r[i + 1], t), "dir": (r[i + 1] - r[i]).normalized()}
		left -= seg
	return {"at": r[r.size() - 1], "dir": Vector2.ZERO}


## How far along a route the nearest point to `p` is, in metres.
static func progress_of(r: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var best_s := 0.0
	var run := 0.0
	for i in range(r.size() - 1):
		var a := r[i]
		var b := r[i + 1]
		var seg := a.distance_to(b)
		var t := 0.0
		if seg > 0.0:
			t = clampf((p - a).dot(b - a) / (seg * seg), 0.0, 1.0)
		var d := p.distance_to(a.lerp(b, t))
		if d < best:
			best = d
			best_s = run + t * seg
		run += seg
	return best_s


# --- the graph ---------------------------------------------------------------------------------

static func _xz(place_id: String) -> Vector2:
	var p := WorldProbe.place_position(place_id)
	if p == Vector3.INF or (p == Vector3.ZERO and not ContentDB.has(place_id)):
		return Vector2.INF
	return Vector2(p.x, p.z)


static func _build() -> void:
	if _built:
		return
	_built = true
	if not FileAccess.file_exists(ROADS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROADS_PATH))
	if typeof(parsed) != TYPE_ARRAY:
		return
	for entry in parsed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pts_v: Variant = (entry as Dictionary).get("points", [])
		if typeof(pts_v) != TYPE_ARRAY or (pts_v as Array).size() < 2:
			continue
		var pts := PackedVector2Array()
		for p_v in pts_v:
			var p: Array = p_v
			pts.append(Vector2(float(p[0]), float(p[1])))
		var ia := _node_at(pts[0])
		var ib := _node_at(pts[pts.size() - 1])
		if ia == ib:
			continue      # a ring (Grandfather Hollow's street) joins nothing to anything else
		var length := length_of(pts)
		var back := pts.duplicate()
		back.reverse()
		_link(ia, ib, length, pts)
		_link(ib, ia, length, back)


static func _node_at(p: Vector2) -> int:
	for i in _nodes.size():
		if _nodes[i].distance_to(p) <= JOIN_M:
			return i
	_nodes.append(p)
	return _nodes.size() - 1


static func _link(a: int, b: int, length: float, pts: PackedVector2Array) -> void:
	var list: Array = _edges.get(a, [])
	list.append([b, length, pts])
	_edges[a] = list


## The nearest junction to a point, within `limit`; -1 when there is none.
static func _nearest_node(p: Vector2, limit: float) -> int:
	var best := -1
	var best_d := limit
	for i in _nodes.size():
		var d := _nodes[i].distance_to(p)
		if d <= best_d:
			best_d = d
			best = i
	return best


static func _walk(a: Vector2, b: Vector2) -> PackedVector2Array:
	_build()
	var straight := PackedVector2Array([a, b])
	var na := _nearest_node(a, REACH_M)
	if na < 0:
		na = _nearest_node(a, ACROSS_M)
	var nb := _nearest_node(b, REACH_M)
	if nb < 0:
		nb = _nearest_node(b, ACROSS_M)
	if na < 0 or nb < 0 or na == nb:
		return straight
	# Dijkstra over the junctions; the graph is a few hundred nodes, so a plain scan will do
	var dist: Dictionary = {na: 0.0}
	var prev: Dictionary = {}
	var done: Dictionary = {}
	while true:
		var cur := -1
		var cur_d := INF
		for k in dist:
			if not done.has(k) and float(dist[k]) < cur_d:
				cur_d = float(dist[k])
				cur = int(k)
		if cur < 0 or cur == nb:
			break
		done[cur] = true
		for e in _edges.get(cur, []):
			var to := int(e[0])
			var nd := cur_d + float(e[1])
			if nd < float(dist.get(to, INF)):
				dist[to] = nd
				prev[to] = [cur, e[2]]
	if not dist.has(nb):
		return straight
	var legs: Array = []
	var at := nb
	while at != na:
		var step: Array = prev[at]
		legs.push_front(step[1])
		at = int(step[0])
	var out := PackedVector2Array([a])
	for leg in legs:
		for p in (leg as PackedVector2Array):
			if out[out.size() - 1].distance_to(p) > 0.5:
				out.append(p)
	if out[out.size() - 1].distance_to(b) > 0.5:
		out.append(b)
	# a road that runs past the start or the end first would be walked out and back: take the
	# route from its nearest point to each place instead
	return _trim_ends(out, a, b)


static func _trim_ends(r: PackedVector2Array, a: Vector2, b: Vector2) -> PackedVector2Array:
	if r.size() < 4:
		return r
	var inner := r.slice(1, r.size() - 1)
	var from_s := progress_of(inner, a)
	var to_s := progress_of(inner, b)
	if to_s <= from_s:
		return r
	var out := PackedVector2Array([a])
	var run := 0.0
	for i in range(inner.size() - 1):
		var p := inner[i]
		var q := inner[i + 1]
		var seg := p.distance_to(q)
		if run + seg > from_s and run < to_s:
			var t0 := clampf((from_s - run) / seg, 0.0, 1.0) if seg > 0.0 else 0.0
			var t1 := clampf((to_s - run) / seg, 0.0, 1.0) if seg > 0.0 else 1.0
			var p0 := p.lerp(q, t0)
			if out[out.size() - 1].distance_to(p0) > 0.5:
				out.append(p0)
			var p1 := p.lerp(q, t1)
			if out[out.size() - 1].distance_to(p1) > 0.5:
				out.append(p1)
		run += seg
	if out[out.size() - 1].distance_to(b) > 0.5:
		out.append(b)
	return out
