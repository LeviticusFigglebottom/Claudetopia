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
## from where the nearest road passes it; two places with no roads between them at all get the
## straight line. With no built world (a headless test with no roads file) there are no routes and
## every question answers as though the places were a straight line apart, or not at all.

const ROADS_PATH := "res://world/generated/roads.json"
## Road ends this close together are one junction.
const JOIN_M := 22.0
## How far from a place's pad a road end may be and still be that place's road.
const REACH_M := 140.0
## A place with no road end within REACH_M is joined where the nearest road within this passes it;
## one further than this from every road is walked to straight.
const ACROSS_M := 900.0
## What a metre walked off the road counts for, against one along it, when a walk is chosen.
const OFF_ROAD_COST := 1.5
## A walk joined to a road at its middle that is longer than this many times the straight line is
## a long way round (`_round_about`): the straight line is walked instead.
const DETOUR_MAX := 2.0

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


## How a point is joined to the roads: {"joins": [[junction, cost, points from the point to it,
## whether it is joined at a road's middle]],
## "near": the road it is joined to at its middle ({} when it is joined at road ends only)}.
## A place with road ends within REACH_M is joined at each of them, straight. One with none is
## joined at the nearest road end within ACROSS_M, straight, as it always was, and also where the
## nearest road within ACROSS_M passes closest, and along that road both ways to its junctions;
## the walk takes whichever is shorter. Only the road end had been tried, and the one nearest
## Eelfathom Pool is the end of Moreva's street, which no road joins: no walk reached it, and
## Tallissa Oul went from Isseva to the pool straight across the marsh, through 52 m of water,
## with the road from Nauve's Landing to Moreva passing 266 m from the pool. Metres off the road
## cost OFF_ROAD_COST each, so the way along a road is taken over a shorter one across country.
static func _joins(p: Vector2) -> Dictionary:
	var out: Array = []
	for i in _nodes.size():
		var d := _nodes[i].distance_to(p)
		if d <= REACH_M:
			out.append([i, d * OFF_ROAD_COST, PackedVector2Array([p, _nodes[i]]), false])
	if not out.is_empty():
		return {"joins": out, "near": {}}
	var nearest := -1
	var nearest_d := ACROSS_M
	for i in _nodes.size():
		var d := _nodes[i].distance_to(p)
		if d <= nearest_d:
			nearest_d = d
			nearest = i
	if nearest >= 0:
		out.append([nearest, nearest_d * OFF_ROAD_COST, PackedVector2Array([p, _nodes[nearest]]), false])
	var near := _nearest_on_road(p)
	if near.is_empty():
		return {"joins": out, "near": near}
	var pts: PackedVector2Array = near["pts"]
	var seg := int(near["seg"])
	var q: Vector2 = near["at"]
	var off := p.distance_to(q) * OFF_ROAD_COST
	var back := PackedVector2Array([p, q])
	for k in range(seg, -1, -1):
		_add(back, pts[k])
	out.append([int(near["from"]), off + float(near["s"]), back, true])
	var on := PackedVector2Array([p, q])
	for k in range(seg + 1, pts.size()):
		_add(on, pts[k])
	out.append([int(near["to"]), off + float(near["length"]) - float(near["s"]), on, true])
	return {"joins": out, "near": near}


## The nearest point to `p` of any road within ACROSS_M, as {from, to (its junctions), pts (from
## `from` to `to`), seg (the segment it is on), at, s (metres along pts to it), length}; {} when no
## road is that near.
static func _nearest_on_road(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := ACROSS_M
	for a_v in _edges:
		var a := int(a_v)
		for e in _edges[a_v]:
			var b := int(e[0])
			if b < a:
				continue      # each road once, from its lower junction
			var pts: PackedVector2Array = e[2]
			var run := 0.0
			for k in range(pts.size() - 1):
				var u := pts[k]
				var v := pts[k + 1]
				var seg_len := u.distance_to(v)
				var t := 0.0 if seg_len == 0.0 else clampf((p - u).dot(v - u) / (seg_len * seg_len), 0.0, 1.0)
				var at := u.lerp(v, t)
				var d := at.distance_to(p)
				if d < best_d:
					best_d = d
					best = {"from": a, "to": b, "pts": pts, "seg": k, "at": at, "s": run + t * seg_len,
							"length": float(e[1])}
				run += seg_len
	return best


static func _add(r: PackedVector2Array, p: Vector2) -> void:
	if r.is_empty() or r[r.size() - 1].distance_to(p) > 0.5:
		r.append(p)


static func _walk(a: Vector2, b: Vector2) -> PackedVector2Array:
	_build()
	var straight := PackedVector2Array([a, b])
	# A place is reached by every road end on its pad: at the Choir three roads end round the
	# ring, each a junction of its own, and a walk from the Last Camp's road to the Pilgrim Road
	# goes across the pad between them. So the walk may start at any junction within reach of
	# `a` and end at any within reach of `b`, the few metres to each counted; a place with none
	# within reach is joined where the nearest road passes it (`_joins`).
	var from_a := _joins(a)
	var to_b := _joins(b)
	var starts: Array = from_a["joins"]
	var ends: Array = to_b["joins"]
	if starts.is_empty() or ends.is_empty():
		return straight
	var dist: Dictionary = {}
	var prev: Dictionary = {}
	var done: Dictionary = {}
	var lead_in: Dictionary = {}      # start junction -> [the points from `a` to it, at a road's middle]
	for j in starts:
		var n := int(j[0])
		if float(j[1]) < float(dist.get(n, INF)):
			dist[n] = float(j[1])
			lead_in[n] = [j[2], bool(j[3])]
	var lead_out: Dictionary = {}     # end junction -> [cost, the points from it to `b`, at a road's middle]
	for j in ends:
		var n := int(j[0])
		if not lead_out.has(n) or float(j[1]) < float(lead_out[n][0]):
			var back: PackedVector2Array = (j[2] as PackedVector2Array).duplicate()
			back.reverse()
			lead_out[n] = [float(j[1]), back, bool(j[3])]
	var best_end := -1
	var best_total := INF
	while true:
		var cur := -1
		var cur_d := INF
		for k in dist:
			if not done.has(k) and float(dist[k]) < cur_d:
				cur_d = float(dist[k])
				cur = int(k)
		if cur < 0 or cur_d >= best_total:
			break
		done[cur] = true
		if lead_out.has(cur):
			var total := cur_d + float(lead_out[cur][0])
			if total < best_total:
				best_total = total
				best_end = cur
		for e in _edges.get(cur, []):
			var to := int(e[0])
			var nd := cur_d + float(e[1])
			if nd < float(dist.get(to, INF)):
				dist[to] = nd
				prev[to] = [cur, e[2]]
	# both ends joined to one road at its middle: along it between them, if that is shorter
	var along := _along_one_road(a, b, from_a["near"], to_b["near"])
	if not along.is_empty():
		var off := a.distance_to(from_a["near"]["at"]) + b.distance_to(to_b["near"]["at"])
		if length_of(along) + off * (OFF_ROAD_COST - 1.0) <= best_total:
			return straight if _round_about(along, a, b) else along
	if best_end < 0:
		return straight
	var legs: Array = []
	var at := best_end
	while prev.has(at):
		var step: Array = prev[at]
		legs.push_front(step[1])
		at = int(step[0])
	var start_join: Array = lead_in.get(at, [PackedVector2Array([a, _nodes[at]]), false])
	var first: PackedVector2Array = start_join[0]
	var last: PackedVector2Array = lead_out[best_end][1]
	# two places sharing a road end, each a few metres from it: they are walked between straight
	if legs.is_empty() and first.size() <= 2 and last.size() <= 2:
		return straight
	var out := PackedVector2Array()
	for p in first:
		_add(out, p)
	for leg in legs:
		for p in (leg as PackedVector2Array):
			_add(out, p)
	for p in last:
		_add(out, p)
	_add(out, b)
	# a road that runs past the start or the end first would be walked out and back: take the
	# route from its nearest point to each place instead
	out = _trim_ends(out, a, b)
	if (bool(start_join[1]) or bool(lead_out[best_end][2])) and _round_about(out, a, b):
		return straight
	return out


## Whether a walk joined to a road at its middle goes a long way round: the road passing Rudd Mill
## goes four kilometres round to Kharrow Hold, 668 m off, and the miller walks across the fields,
## as everybody off a road's end did before a road was joined at its middle. Only such walks are
## asked: one between road ends takes the roads however they go.
static func _round_about(r: PackedVector2Array, a: Vector2, b: Vector2) -> bool:
	return length_of(r) > DETOUR_MAX * a.distance_to(b)


## The walk from `a` to `b` along the one road both are joined to at its middle (their `near`s
## from `_joins`); empty when they are not joined to the same road.
static func _along_one_road(a: Vector2, b: Vector2, na: Dictionary, nb: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	if na.is_empty() or nb.is_empty() or int(na["from"]) != int(nb["from"]) or int(na["to"]) != int(nb["to"]) \
			or na["pts"] != nb["pts"]:
		return out
	var pts: PackedVector2Array = na["pts"]
	_add(out, a)
	_add(out, na["at"])
	if float(na["s"]) <= float(nb["s"]):
		for k in range(int(na["seg"]) + 1, int(nb["seg"]) + 1):
			_add(out, pts[k])
	else:
		for k in range(int(na["seg"]), int(nb["seg"]), -1):
			_add(out, pts[k])
	_add(out, nb["at"])
	_add(out, b)
	return out


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
