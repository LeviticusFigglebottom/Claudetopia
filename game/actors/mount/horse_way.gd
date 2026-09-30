class_name HorseWay
extends RefCounted
## The way a called horse finds to whoever whistled for it, over the ground as it lies.
##
## Nothing baked covers the open country (NpcNav meshes stand only over towns, and for a person's
## width), so the horse reads it for itself: a grid of CELL_M squares between it and the caller,
## searched A* from where it stands, each square looked at only when the search reaches it. A square
## is closed to it when the ground there is under deeper water than it wades, or something solid (a
## trunk, a wall, a rock, a fence, a house) stands in a horse's body there above the height it steps
## over; a step between two squares is closed when it climbs steeper than the horse will go up, or
## falls steeper than it will go down (a bank, a cliff's edge). Wading is dear, a road is cheap, and
## a hillside costs more the steeper it is, so the way it takes is the one a horse would.
##
## The search is spread over physics frames (`step`, with a budget of squares looked at a frame),
## and the way it finds is pulled straight wherever the squares between two of its points are all
## open, so the horse goes from bend to bend rather than square to square.

const CELL_M := 1.5
## Round the horse and the caller, the grid runs this far out (m), and never past MAX_CELLS a side.
const MARGIN_M := 30.0
const MAX_CELLS := 220
## What a square costs to look at is a shape query and two height reads: this many a frame.
const LOOKS_A_FRAME := 90
## A search that has looked at this many squares and not arrived gives up.
const MAX_LOOKS := 16000
## A horse's body above what it steps over, turned any way (m): what must be clear in a square.
const BODY := Vector3(1.05, 1.2, 1.05)
## Steepest step between squares, up and down (degrees): a little under the horse's own refusals,
## so the way never leads it to one.
const UP_DEG := 32.0
const DOWN_DEG := 36.0
## Water: a square deeper than this is closed; deeper than WADE_M it is dear (a ford, not a swim).
const DEEP_M := 1.0
const WADE_M := 0.45
const WADE_COST := 5.0
const WET_COST := 1.6
## A road's carriageway (RoadNetwork) is cheap, and so is its verge.
const ROAD_COST := 0.6
const VERGE_COST := 0.8
const VERGE_M := 3.0

## A way is pulled straight across at most this many squares at once (the line checks' cost).
const PULL_CELLS := 40

enum { WORKING, FOUND, FAILED }

var state := WORKING
## The way found: points on the ground from the horse's square to the caller's (world space).
var points: PackedVector3Array = PackedVector3Array()
var looks := 0

var _space: PhysicsDirectSpaceState3D = null
var _exclude: Array[RID] = []
var _mask := 0
var _origin := Vector2.ZERO          # world xz of cell (0, 0)'s corner
var _w := 0
var _h := 0
var _start := Vector2i.ZERO
var _goal := Vector3.ZERO
var _arrive := 0.0
## cell index -> cost to stand in it (INF closed), and its ground height
var _cost: Dictionary = {}
var _height: Dictionary = {}
var _closed: Dictionary = {}          # cells a stuck horse found shut, whatever they look like
var _g: Dictionary = {}
var _came: Dictionary = {}
var _done: Dictionary = {}
var _open: Array = []                 # binary heap of [f, cell index]
var _box := BoxShape3D.new()
var _roads := false


## A search from `from` to within `arrive` m of `to`, in `space`, for a body `rid` (left out of the
## shape queries) that is stopped by `mask`. `shut` is cells found closed before (by a stuck horse).
func _init(space: PhysicsDirectSpaceState3D, rid: RID, mask: int, from: Vector3, to: Vector3,
		arrive: float, shut: Dictionary = {}) -> void:
	_space = space
	_exclude = [rid]
	_mask = mask
	_goal = to
	_arrive = arrive
	_closed = shut
	_box.size = BODY
	_roads = not RoadNetwork.roads().is_empty()
	var lo := Vector2(minf(from.x, to.x), minf(from.z, to.z)) - Vector2.ONE * MARGIN_M
	var hi := Vector2(maxf(from.x, to.x), maxf(from.z, to.z)) + Vector2.ONE * MARGIN_M
	var size := ((hi - lo) / CELL_M).ceil()
	_w = mini(int(size.x), MAX_CELLS)
	_h = mini(int(size.y), MAX_CELLS)
	# a grid wider than the cap is centred between the two
	var mid := (Vector2(from.x, from.z) + Vector2(to.x, to.z)) * 0.5
	_origin = Vector2(lo.x if int(size.x) <= MAX_CELLS else mid.x - _w * CELL_M * 0.5,
			lo.y if int(size.y) <= MAX_CELLS else mid.y - _h * CELL_M * 0.5)
	_start = cell_of(from)
	if not _inside(_start):
		state = FAILED
		return
	var s := _index(_start)
	_g[s] = 0.0
	_push(_heuristic(_start), s)


## Where the cell of world point `p` is.
func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - _origin.x) / CELL_M)), int(floor((p.z - _origin.y) / CELL_M)))


## The middle of cell `c` on the ground.
func centre(c: Vector2i) -> Vector3:
	var x := _origin.x + (float(c.x) + 0.5) * CELL_M
	var z := _origin.y + (float(c.y) + 0.5) * CELL_M
	return Vector3(x, _ground_of(c), z)


## Looks at up to `budget` squares; returns the state (WORKING, FOUND, FAILED).
func step(budget := LOOKS_A_FRAME) -> int:
	if state != WORKING:
		return state
	var spent := 0
	while spent < budget:
		if _open.is_empty():
			state = FAILED
			return state
		var top: Array = _pop()
		var i := int(top[1])
		if _done.has(i):
			continue
		_done[i] = true
		var c := _cell(i)
		var here := centre(c)
		if Vector2(here.x - _goal.x, here.z - _goal.z).length() <= _arrive:
			_finish(i)
			return state
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var n := c + Vector2i(dx, dy)
				if not _inside(n):
					continue
				var ni := _index(n)
				if _done.has(ni):
					continue
				var was := _cost.has(ni)
				var cost := _step_cost(c, n)
				if not was:
					spent += 1
					looks += 1
				if cost == INF:
					continue
				# no corner is cut past something closed
				if dx != 0 and dy != 0:
					if cost_of(Vector2i(c.x + dx, c.y)) == INF or cost_of(Vector2i(c.x, c.y + dy)) == INF:
						continue
				var g := float(_g[i]) + cost
				if g < float(_g.get(ni, INF)):
					_g[ni] = g
					_came[ni] = i
					_push(g + _heuristic(n), ni)
		if looks > MAX_LOOKS:
			state = FAILED
			return state
	return state


## Whether the straight line between two world points crosses only open squares, with no step
## too steep on it (the squares it crosses are looked at if they were not yet).
func line_open(a: Vector3, b: Vector3) -> bool:
	var ca := cell_of(a)
	var cb := cell_of(b)
	var steps := maxi(absi(cb.x - ca.x), absi(cb.y - ca.y)) * 2
	var prev := ca
	for k in range(1, steps + 1):
		var p := a.lerp(b, float(k) / float(steps))
		var c := cell_of(p)
		if c == prev:
			continue
		if not _inside(c) or _step_cost(prev, c) == INF:
			return false
		# a diagonal slip between two closed squares is not open
		if c.x != prev.x and c.y != prev.y:
			if cost_of(Vector2i(c.x, prev.y)) == INF and cost_of(Vector2i(prev.x, c.y)) == INF:
				return false
		prev = c
	return true


## What standing in cell `c` costs (INF closed), looking at it if nobody has.
func cost_of(c: Vector2i) -> float:
	if not _inside(c):
		return INF
	var i := _index(c)
	if _cost.has(i):
		return float(_cost[i])
	var v := _look(c)
	_cost[i] = v
	return v


## Marks the cells round world point `p` closed (a horse stuck there), `r` cells out.
func shut_round(p: Vector3, r := 0) -> void:
	var c := cell_of(p)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := c + Vector2i(dx, dy)
			if _inside(n):
				_closed[_index(n)] = true
				_cost[_index(n)] = INF


func shut_cells() -> Dictionary:
	return _closed


# --- the search -----------------------------------------------------------------------------

func _step_cost(a: Vector2i, b: Vector2i) -> float:
	var cb := cost_of(b)
	if cb == INF:
		return INF
	var run := CELL_M * (1.41421356 if a.x != b.x and a.y != b.y else 1.0)
	var rise := _ground_of(b) - _ground_of(a)
	var deg := rad_to_deg(atan2(rise, run))
	if deg > UP_DEG or -deg > DOWN_DEG:
		return INF
	# a hillside is dear the steeper it is, up more than down
	var hill := 1.0 + pow(absf(deg) / (24.0 if deg > 0.0 else 30.0), 2.0)
	return run * cb * hill


func _look(c: Vector2i) -> float:
	var i := _index(c)
	if _closed.has(i):
		return INF
	var p := centre(c)
	if p.y == -INF:
		return INF
	var cost := 1.0
	var t: Object = World.terrain()
	if t != null and t.has_method("water_depth_at"):
		var depth := float(t.call("water_depth_at", p.x, p.z))
		if depth > DEEP_M:
			return INF
		if depth > WADE_M:
			cost = WADE_COST
		elif depth > 0.05:
			cost = WET_COST
	if _space != null:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _box
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0.0, Mount.STEP_OVER + BODY.y * 0.5, 0.0))
		q.collision_mask = _mask
		q.exclude = _exclude
		if not _space.intersect_shape(q, 1).is_empty():
			return INF
	if _roads and cost < WADE_COST:
		var e := RoadNetwork.edge_distance(Vector2(p.x, p.z))
		if e < 0.0:
			cost *= ROAD_COST
		elif e < VERGE_M:
			cost *= VERGE_COST
	return cost


func _ground_of(c: Vector2i) -> float:
	var i := _index(c)
	if _height.has(i):
		return float(_height[i])
	var x := _origin.x + (float(c.x) + 0.5) * CELL_M
	var z := _origin.y + (float(c.y) + 0.5) * CELL_M
	var h := -INF
	var t: Object = World.terrain()
	if t != null and t.has_method("get_height"):
		h = float(t.call("get_height", x, z))
	_height[i] = h
	return h


func _heuristic(c: Vector2i) -> float:
	var p := Vector2(_origin.x + (float(c.x) + 0.5) * CELL_M, _origin.y + (float(c.y) + 0.5) * CELL_M)
	var d := maxf(0.0, p.distance_to(Vector2(_goal.x, _goal.z)) - _arrive)
	return d * (ROAD_COST if _roads else 1.0)


func _finish(last: int) -> void:
	var cells: Array[int] = [last]
	while _came.has(cells[-1]):
		cells.append(int(_came[cells[-1]]))
	cells.reverse()
	var raw := PackedVector3Array()
	for i in cells:
		raw.append(centre(_cell(i)))
	# pulled straight: from each point, on to the farthest one in an open line from it
	points = PackedVector3Array()
	var k := 0
	points.append(raw[0])
	while k < raw.size() - 1:
		var best := k + 1
		var j := mini(raw.size() - 1, k + PULL_CELLS)
		while j > k + 1:
			if line_open(raw[k], raw[j]):
				best = j
				break
			j -= 1
		points.append(raw[best])
		k = best
	state = FOUND


func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _w and c.y < _h


func _index(c: Vector2i) -> int:
	return c.y * _w + c.x


func _cell(i: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(i % _w, i / _w)


func _push(f: float, i: int) -> void:
	_open.append([f, i])
	var k := _open.size() - 1
	while k > 0:
		var parent := (k - 1) >> 1
		if float(_open[parent][0]) <= f:
			break
		_open[k] = _open[parent]
		_open[parent] = [f, i]
		k = parent


func _pop() -> Array:
	var top: Array = _open[0]
	var last: Array = _open.pop_back()
	if not _open.is_empty():
		_open[0] = last
		var k := 0
		var n := _open.size()
		while true:
			var l := 2 * k + 1
			var r := l + 1
			var m := k
			if l < n and float(_open[l][0]) < float(_open[m][0]):
				m = l
			if r < n and float(_open[r][0]) < float(_open[m][0]):
				m = r
			if m == k:
				break
			var tmp: Array = _open[k]
			_open[k] = _open[m]
			_open[m] = tmp
			k = m
	return top
