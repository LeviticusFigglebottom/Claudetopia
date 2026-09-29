class_name RoadRoute
extends RefCounted
## The way by road between two points of the built world: the shortest run along game/world/generated
## roads.json, where two roads count as joined wherever their points come within LINK_M of each
## other (the atlas's roads meet at a junction or a pad's edge, not at a shared point). What a lead
## walks south (Leads), so the grey hart keeps to the road the fingerposts name.
##
## Measured on w4096e: Wardens' Rest to the Stair Head 4.6 km, Fernhold 9.3, Gullhithe 7.4 and
## Moreva 8.3, within a few hundred metres of the cartographer's rides (docs/FIGHTING_STYLE_STARTS.md
## §3.1a-§3.4a).

const LINK_M := 35.0
## A link across between roads costs this much more than its length, so a route keeps to a road
## where it can rather than hopping between parallel ones.
const LINK_COST := 1.5
const CELL := 40.0

static var _points: PackedVector2Array = PackedVector2Array()
static var _edges: Array = []          # node -> [[node, cost]]
static var _grid: Dictionary = {}      # Vector2i -> [node]
static var _built := false


static func reset() -> void:
	_points = PackedVector2Array()
	_edges.clear()
	_grid.clear()
	_built = false


static func _build() -> void:
	if _built:
		return
	_built = true
	var road_of: PackedInt32Array = PackedInt32Array()
	var ri := 0
	for line_v in WorldPois.roads_from_disk():
		var line: Array = line_v
		var first := _points.size()
		for p_v in line:
			var p: Array = p_v
			_points.append(Vector2(float(p[0]), float(p[1])))
			road_of.append(ri)
			_edges.append([])
		for i in range(first, _points.size() - 1):
			var d := _points[i].distance_to(_points[i + 1])
			_edges[i].append([i + 1, d])
			_edges[i + 1].append([i, d])
		ri += 1
	for i in _points.size():
		var c := Vector2i(floori(_points[i].x / CELL), floori(_points[i].y / CELL))
		if not _grid.has(c):
			_grid[c] = []
		(_grid[c] as Array).append(i)
	for i in _points.size():
		var c := Vector2i(floori(_points[i].x / CELL), floori(_points[i].y / CELL))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for j in _grid.get(c + Vector2i(dx, dz), []):
					if j <= i or road_of[j] == road_of[i]:
						continue
					var d := _points[i].distance_to(_points[j])
					if d < LINK_M:
						_edges[i].append([j, d * LINK_COST])
						_edges[j].append([i, d * LINK_COST])


static func nearest(at: Vector2) -> int:
	_build()
	var best := -1
	var best_d := INF
	for i in _points.size():
		var d := _points[i].distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = i
	return best


## The route's points from `a` to `b` (both ends included as given), or an empty array when the
## roads do not join them.
static func between(a: Vector2, b: Vector2) -> PackedVector2Array:
	_build()
	var out := PackedVector2Array()
	var s := nearest(a)
	var t := nearest(b)
	if s < 0 or t < 0:
		return out
	var dist := {s: 0.0}
	var prev := {}
	var heap: Array = [[0.0, s]]
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var u := int(top[1])
		if u == t:
			break
		if float(top[0]) > float(dist.get(u, INF)):
			continue
		for e in _edges[u]:
			var v := int(e[0])
			var nd := float(top[0]) + float(e[1])
			if nd < float(dist.get(v, INF)):
				dist[v] = nd
				prev[v] = u
				_push(heap, [nd, v])
	if not dist.has(t):
		return out
	var rev: Array[int] = [t]
	while rev[rev.size() - 1] != s:
		rev.append(int(prev[rev[rev.size() - 1]]))
	out.append(a)
	for k in range(rev.size() - 1, -1, -1):
		out.append(_points[rev[k]])
	out.append(b)
	return out


static func length_of(line: PackedVector2Array) -> float:
	var m := 0.0
	for i in range(line.size() - 1):
		m += line[i].distance_to(line[i + 1])
	return m


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if float(heap[parent][0]) <= float(heap[i][0]):
			break
		var tmp: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < heap.size() and float(heap[l][0]) < float(heap[m][0]):
			m = l
		if r < heap.size() and float(heap[r][0]) < float(heap[m][0]):
			m = r
		if m == i:
			break
		var tmp: Array = heap[m]
		heap[m] = heap[i]
		heap[i] = tmp
		i = m
	return top
