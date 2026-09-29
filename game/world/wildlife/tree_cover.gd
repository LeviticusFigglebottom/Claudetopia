class_name TreeCover
extends RefCounted
## Where the trees stand, coarsely: for every world cell the streamer has read, how many trees stand
## in each BIN_M square of it. Noted on the streamer's worker thread as a cell's file is parsed
## (WorldStreamer._parse_cell), so what lives at a wood's edge -- the deer -- can find the edge
## without reading the cells again. A cell is kept once noted (16 x 16 bytes); the whole world is
## 256 KB.

const BIN_M := 16.0
const PREFIX := "res://assets/models/trees/"

static var _cover: Dictionary = {}          # Vector2i (streamer cell) -> PackedByteArray, bins z-major
static var _cell_m := 256.0
static var _origin := Vector2(-4096.0, -4096.0)
static var _mutex := Mutex.new()


## The streamer's grid, so a world position finds its cell.
static func set_grid(origin: Vector2, cell_m: float) -> void:
	_mutex.lock()
	_origin = origin
	_cell_m = cell_m
	_mutex.unlock()


static func bins_per_cell() -> int:
	return int(_cell_m / BIN_M)


## Counts the trees among a parsed cell's instances (any thread).
static func note(cell: Vector2i, data: Dictionary) -> void:
	var n := bins_per_cell()
	if n <= 0:
		return
	var counts := PackedByteArray()
	counts.resize(n * n)
	var x0 := _origin.x + float(cell.x) * _cell_m
	var z0 := _origin.y + float(cell.y) * _cell_m
	var inst: Dictionary = data.get("instances", {})
	for path in inst:
		if not str(path).begins_with(PREFIX):
			continue
		for row in inst[path]:
			if not (row is Array) or (row as Array).size() < 3:
				continue
			var bx := int(floor((float(row[0]) - x0) / BIN_M))
			var bz := int(floor((float(row[2]) - z0) / BIN_M))
			if bx < 0 or bz < 0 or bx >= n or bz >= n:
				continue
			var i := bz * n + bx
			counts[i] = mini(int(counts[i]) + 1, 255)
	_mutex.lock()
	_cover[cell] = counts
	_mutex.unlock()


## Sets a cell's counts directly (tests).
static func put(cell: Vector2i, counts: PackedByteArray) -> void:
	_mutex.lock()
	_cover[cell] = counts
	_mutex.unlock()


static func forget_all() -> void:
	_mutex.lock()
	_cover.clear()
	_mutex.unlock()


static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - _origin.x) / _cell_m), floori((z - _origin.y) / _cell_m))


static func has_cell(cell: Vector2i) -> bool:
	_mutex.lock()
	var h := _cover.has(cell)
	_mutex.unlock()
	return h


## How many trees stand in the bin at (x, z); -1 where the cell has not been read.
static func at(x: float, z: float) -> int:
	var cell := cell_of(x, z)
	_mutex.lock()
	var counts: PackedByteArray = _cover.get(cell, PackedByteArray())
	_mutex.unlock()
	if counts.is_empty():
		return -1
	var n := bins_per_cell()
	var bx := clampi(int(floor((x - _origin.x - float(cell.x) * _cell_m) / BIN_M)), 0, n - 1)
	var bz := clampi(int(floor((z - _origin.y - float(cell.y) * _cell_m) / BIN_M)), 0, n - 1)
	return int(counts[bz * n + bx])


## Trees within `reach` bins of (x, z), the bin itself left out, and how many of those bins are
## open (no tree): [trees, open]; [-1, -1] if any of them is unread.
static func around(x: float, z: float, reach := 2) -> Vector2i:
	var total := 0
	var open := 0
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if dx == 0 and dz == 0:
				continue
			var c := at(x + float(dx) * BIN_M, z + float(dz) * BIN_M)
			if c < 0:
				return Vector2i(-1, -1)
			total += c
			if c == 0:
				open += 1
	return Vector2i(total, open)


## A wood's edge: an open bin with wood beside it (at least `wood_min` trees within two bins) and
## open ground beside it too (at least `open_min` of those bins without a tree) -- not a gap in the
## wood's middle, nor a field's.
static func is_edge(x: float, z: float, wood_min := 6, open_min := 8) -> bool:
	if at(x, z) != 0:
		return false
	var a := around(x, z)
	return a.x >= wood_min and a.y >= open_min


## Every wood's-edge bin of a cell (is_edge's rule), as the bins' centres (x, z): the cell's counts
## and its neighbours' read once, not bin by bin. Empty while the cell or a neighbour is unread.
static func edges_in(cell: Vector2i, wood_min := 6, open_min := 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := bins_per_cell()
	var w := n + 4
	var grid := PackedInt32Array()
	grid.resize(w * w)
	_mutex.lock()
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var counts: PackedByteArray = _cover.get(cell + Vector2i(dx, dz), PackedByteArray())
			if counts.is_empty():
				_mutex.unlock()
				return out
			for bz in n:
				var gz := bz + dz * n + 2
				if gz < 0 or gz >= w:
					continue
				for bx in n:
					var gx := bx + dx * n + 2
					if gx < 0 or gx >= w:
						continue
					grid[gz * w + gx] = counts[bz * n + bx]
	_mutex.unlock()
	var x0 := _origin.x + float(cell.x) * _cell_m
	var z0 := _origin.y + float(cell.y) * _cell_m
	for bz in n:
		for bx in n:
			var gz := bz + 2
			var gx := bx + 2
			if grid[gz * w + gx] != 0:
				continue
			var trees := 0
			var open := 0
			for oz in range(-2, 3):
				for ox in range(-2, 3):
					if ox == 0 and oz == 0:
						continue
					var c := grid[(gz + oz) * w + gx + ox]
					trees += c
					if c == 0:
						open += 1
			if trees >= wood_min and open >= open_min:
				out.append(Vector2(x0 + (float(bx) + 0.5) * BIN_M, z0 + (float(bz) + 0.5) * BIN_M))
	return out
