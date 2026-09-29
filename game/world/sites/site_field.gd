class_name SiteField
extends RefCounted
## The rock of a site's inside as a signed distance field, meshed by surface nets: the plan's `ops`
## (rooms, passages, shafts, basins, rifts carved out; ledges, ramps, pillars, rubble filled back)
## are evaluated on a grid only inside each op's own box, and the surface between rock (> 0) and air
## (< 0) is made into chunked meshes whose faces are also the collision, so what you see is what you
## stand on. All of it is plain arrays and math, safe on a worker thread (SiteInterior runs it there);
## nothing here touches a node or a server.
##
## The mesh carries the rock's colour in its vertex colour (floor and wall tints from the kind's
## palette, a slow mottle) and how open the rock is in front of it in the alpha (cave_rock.gdshader
## reads that as cavity occlusion).

const ROCK := 3.0
## Chunks of this many metres across (x and z), each its own mesh and collision shape, so a chunk
## out of view is not drawn and no one mesh gathers every light in the place.
const CHUNK_M := 14.0
## What changes the mesh made from a plan: bumped when this file's output changes, so a cached shell
## is not reused.
const VERSION := 3

var voxel := 0.55
var origin := Vector3.ZERO
var nx := 0
var ny := 0
var nz := 0
var f := PackedFloat32Array()
var noise := FastNoiseLite.new()
var palette: Array[Color] = [Color("#8c8577"), Color("#5f5a50"), Color("#a39b8a")]
var _vid := PackedInt32Array()
var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _quads: Array[PackedInt32Array] = []   # per chunk: 4 vertex ids a quad
var _chunk_of: Dictionary = {}              # Vector2i -> chunk index
var _chunk_keys: Array[Vector2i] = []


## Meshes the plan's rock: [{"key": Vector2i, "verts", "normals", "colors", "indices", "faces"}].
static func build(plan_ops: Array, bounds: AABB, voxel_m: float, seed_i: int, freq: float, pal: Array) -> Array:
	var sf := SiteField.new()
	sf.voxel = voxel_m
	sf.noise.seed = seed_i
	sf.noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	sf.noise.frequency = freq
	sf.noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	sf.noise.fractal_octaves = 3
	if pal.size() >= 3:
		sf.palette = [Color(str(pal[0])), Color(str(pal[1])), Color(str(pal[2]))]
	sf._grid(bounds)
	for op in plan_ops:
		sf._apply(op)
	sf._seal()
	sf._mesh(plan_ops)
	return sf._chunks()


func _grid(bounds: AABB) -> void:
	origin = (bounds.position / voxel).floor() * voxel - Vector3.ONE * voxel * 2.0
	var size := bounds.size + Vector3.ONE * voxel * 4.0
	nx = int(ceil(size.x / voxel)) + 1
	ny = int(ceil(size.y / voxel)) + 1
	nz = int(ceil(size.z / voxel)) + 1
	f.resize(nx * ny * nz)
	f.fill(ROCK)
	_vid.resize(nx * ny * nz)
	_vid.fill(-1)


## An op's box on the grid: [x0, y0, z0, x1, y1, z1] (inclusive), clamped.
func _range(lo: Vector3, hi: Vector3) -> Array[int]:
	var a := ((lo - origin) / voxel).floor()
	var b := ((hi - origin) / voxel).ceil()
	return [clampi(int(a.x), 1, nx - 2), clampi(int(a.y), 1, ny - 2), clampi(int(a.z), 1, nz - 2),
			clampi(int(b.x), 1, nx - 2), clampi(int(b.y), 1, ny - 2), clampi(int(b.z), 1, nz - 2)]


static func _smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func _ellipsoid(q: Vector3, r: Vector3) -> float:
	var k0 := (q / r).length()
	var k1 := (q / (r * r)).length()
	if k1 < 0.00001:
		return -minf(r.x, minf(r.y, r.z))
	return k0 * (k0 - 1.0) / k1


## The world's box an op can change, with room for its noise and smoothing.
static func op_box(op: Dictionary, top_y: float) -> AABB:
	var pad := float(op.get("noise", 0.0)) + float(op.get("k", 0.0)) + 1.5
	match str(op["type"]):
		"dome", "vault":
			var c: Vector3 = op["c"]
			var h: Vector3 = op["half"]
			var r := (Vector2(h.x, h.z).length() if str(op["type"]) == "vault" else maxf(h.x, h.z)) + pad
			return AABB(Vector3(c.x - r, c.y - pad, c.z - r), Vector3(r * 2.0, h.y + pad * 2.0, r * 2.0))
		"tube", "corridor":
			var a: Vector3 = op["a"]
			var b: Vector3 = op["b"]
			var w := float(op.get("r", op.get("w", 1.5))) + pad
			var hh := float(op.get("h", float(op.get("r", 1.5)) * 2.2)) + pad
			var box := AABB(a, Vector3.ZERO).expand(b)
			return AABB(box.position - Vector3(w, pad, w), box.size + Vector3(w * 2.0, hh + pad, w * 2.0))
		"shaft":
			var c: Vector3 = op["c"]
			var r := float(op["r"]) + pad
			return AABB(Vector3(c.x - r, c.y - pad, c.z - r), Vector3(r * 2.0, maxf(top_y - c.y, 1.0) + pad, r * 2.0))
		"bowl":
			var c: Vector3 = op["c"]
			var r := float(op["r"]) + pad
			var d := float(op["depth"]) + pad
			return AABB(Vector3(c.x - r, c.y - d, c.z - r), Vector3(r * 2.0, d * 2.0, r * 2.0))
		"box", "ramp":
			var c: Vector3 = op["c"]
			var h: Vector3 = op["half"]
			var r := Vector2(h.x, h.z).length() + pad
			return AABB(Vector3(c.x - r, c.y - h.y - pad - 1.0, c.z - r), Vector3(r * 2.0, h.y * 2.0 + pad * 2.0 + 2.0, r * 2.0))
		"mound":
			var c: Vector3 = op["c"]
			var r: Vector3 = op["r"]
			return AABB(c - r - Vector3.ONE * pad, (r + Vector3.ONE * pad) * 2.0)
		"pillar":
			var c: Vector3 = op["c"]
			var r := float(op["r"]) + pad
			return AABB(Vector3(c.x - r, c.y - 1.5, c.z - r), Vector3(r * 2.0, float(op["top"]) + 3.0, r * 2.0))
	return AABB()


func _apply(op: Dictionary) -> void:
	var top_y := origin.y + float(ny - 1) * voxel
	var box := op_box(op, top_y)
	var rg := _range(box.position, box.end)
	var carve := str(op["op"]) == "carve"
	var k := float(op.get("k", 0.0))
	var amp := float(op.get("noise", 0.0))
	var type := str(op["type"])
	var c: Vector3 = op.get("c", Vector3.ZERO)
	var half: Vector3 = op.get("half", Vector3.ONE)
	var yaw := float(op.get("yaw", 0.0))
	var cy := cos(-yaw)
	var sy := sin(-yaw)
	# per type constants
	var a: Vector3 = op.get("a", Vector3.ZERO)
	var b: Vector3 = op.get("b", Vector3.ZERO)
	var u := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var run := u.length()
	u = u / run if run > 0.0001 else Vector3.FORWARD
	var side := Vector3(u.z, 0.0, -u.x)
	var r := float(op.get("r", 1.5)) if typeof(op.get("r", 0.0)) == TYPE_FLOAT else 1.5
	var rv: Vector3 = op.get("r", Vector3.ONE) if typeof(op.get("r", 0.0)) == TYPE_VECTOR3 else Vector3.ONE
	var w := float(op.get("w", 1.5))
	var hgt := float(op.get("h", 3.0))
	var arched := bool(op.get("arched", false))
	var depth := float(op.get("depth", 1.0))
	var rise := float(op.get("rise", 1.0))
	var top := float(op.get("top", 4.0))
	var lift := r * 0.75
	var axis_a := a + Vector3.UP * lift
	var axis_ab := (b + Vector3.UP * lift) - axis_a
	var ab2 := maxf(axis_ab.length_squared(), 0.0001)
	# the vault: its long axis, the wall's height and the arch's radii
	var long_x := half.x >= half.z
	var hw := half.y * 0.62
	var hs := minf(half.x, half.z)
	var arch_h := maxf(half.y - hw, 0.5)
	var dome_r := Vector3(half.x, half.y * 1.15, half.z)
	var dome_c := -0.15 * half.y
	for z in range(rg[2], rg[5] + 1):
		for y in range(rg[1], rg[4] + 1):
			var row := (z * ny + y) * nx
			for x in range(rg[0], rg[3] + 1):
				var p := origin + Vector3(float(x), float(y), float(z)) * voxel
				var d := 0.0
				var n := 0.0
				if amp > 0.0:
					n = noise.get_noise_3dv(p) * amp
				match type:
					"dome":
						var o := p - c
						var q := Vector3(o.x * cy - o.z * sy, o.y, o.x * sy + o.z * cy)
						d = maxf(_ellipsoid(Vector3(q.x, q.y - dome_c, q.z), dome_r) + n, -q.y)
					"vault":
						var o := p - c
						var q := Vector3(o.x * cy - o.z * sy, o.y, o.x * sy + o.z * cy)
						var dx := absf(q.x) - half.x
						var dz := absf(q.z) - half.z
						var walls := maxf(maxf(dx, dz), q.y - hw)
						var across := q.z if long_x else q.x
						var e := Vector2(across / hs, (q.y - hw) / arch_h).length()
						var arch := (e - 1.0) * minf(hs, arch_h)
						d = minf(walls, maxf(arch, maxf(dx, dz)))
						d = maxf(d + n, -q.y)
					"corridor":
						var o := p - a
						var s := o.x * u.x + o.z * u.z
						var t := clampf(s / maxf(run, 0.0001), 0.0, 1.0)
						var yl := p.y - lerpf(a.y, b.y, t)
						var acr := o.x * side.x + o.z * side.z
						var dx := absf(s - run * 0.5) - run * 0.5
						var dz := absf(acr) - w
						if arched:
							var wall_h := maxf(hgt - w, 1.8)
							var walls := maxf(maxf(dx, dz), yl - wall_h)
							var arch := maxf(Vector2(acr, yl - wall_h).length() - w, dx)
							d = minf(walls, arch)
						else:
							d = maxf(maxf(dx, dz), yl - hgt)
						d = maxf(d + n, -yl)
					"tube":
						var ap := p - axis_a
						var t := clampf(ap.dot(axis_ab) / ab2, 0.0, 1.0)
						var near := axis_a + axis_ab * t
						var yl := p.y - lerpf(a.y, b.y, t)
						d = maxf(p.distance_to(near) - r + n, -yl)
					"shaft":
						d = maxf(Vector2(p.x - c.x, p.z - c.z).length() - r + n, c.y - p.y)
					"bowl":
						d = _ellipsoid(p - c, Vector3(r, depth, r)) + n
					"box":
						var o := p - c
						var q := Vector3(o.x * cy - o.z * sy, o.y, o.x * sy + o.z * cy)
						d = maxf(maxf(absf(q.x) - half.x, absf(q.y) - half.y), absf(q.z) - half.z) + n
					"ramp":
						var o := p - c
						var q := Vector3(o.x * cy - o.z * sy, o.y, o.x * sy + o.z * cy)
						var y_top := rise * (q.z + half.z) / (half.z * 2.0)
						var slope := 1.0 / sqrt(1.0 + pow(rise / (half.z * 2.0), 2.0))
						d = maxf(maxf(absf(q.x) - half.x, absf(q.z) - half.z), maxf((q.y - y_top) * slope, -q.y - 1.0))
					"mound":
						d = _ellipsoid(p - c, rv) + n
					"pillar":
						d = maxf(Vector2(p.x - c.x, p.z - c.z).length() - r + n, maxf(c.y - 1.0 - p.y, p.y - c.y - top))
				var i := row + x
				if carve:
					f[i] = _smin(f[i], d, k)
				else:
					f[i] = maxf(f[i], -d) if k <= 0.0 else -_smin(-f[i], d, k)


## The grid's own faces are rock, so the shell is closed wherever an op ran to its edge (a shaft).
func _seal() -> void:
	for z in nz:
		for y in ny:
			var row := (z * ny + y) * nx
			if z == 0 or z == nz - 1 or y == 0 or y == ny - 1:
				for x in nx:
					f[row + x] = maxf(f[row + x], voxel)
			else:
				f[row] = maxf(f[row], voxel)
				f[row + nx - 1] = maxf(f[row + nx - 1], voxel)


func _idx(x: int, y: int, z: int) -> int:
	return (z * ny + y) * nx + x


## The corners of a cell, in the order (x, y, z) bits.
const CORNERS := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
		Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
const EDGES := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]


## The surface net's vertex of a cell: the mean of where its edges cross the surface. -1 for a
## cell the surface does not pass through.
func _vertex(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= nx - 1 or y >= ny - 1 or z >= nz - 1:
		return -1
	var ci := _idx(x, y, z)
	if _vid[ci] >= 0:
		return _vid[ci]
	var v: Array[float] = []
	v.resize(8)
	var inside := 0
	for k in 8:
		var cc: Vector3i = CORNERS[k]
		v[k] = f[_idx(x + cc.x, y + cc.y, z + cc.z)]
		if v[k] < 0.0:
			inside += 1
	if inside == 0 or inside == 8:
		return -1
	var sum := Vector3.ZERO
	var hits := 0
	for e in EDGES:
		var va := v[e[0]]
		var vb := v[e[1]]
		if (va < 0.0) == (vb < 0.0):
			continue
		var t := va / (va - vb)
		var ca: Vector3i = CORNERS[e[0]]
		var cb: Vector3i = CORNERS[e[1]]
		sum += Vector3(ca).lerp(Vector3(cb), t)
		hits += 1
	var pos := origin + (Vector3(x, y, z) + sum / float(hits)) * voxel
	# the rock's gradient across the cell: the normal faces the air, up the fall of the field
	var g := Vector3(
		(v[1] + v[3] + v[5] + v[7]) - (v[0] + v[2] + v[4] + v[6]),
		(v[2] + v[3] + v[6] + v[7]) - (v[0] + v[1] + v[4] + v[5]),
		(v[4] + v[5] + v[6] + v[7]) - (v[0] + v[1] + v[2] + v[3]))
	var nrm := -g.normalized() if g.length() > 0.00001 else Vector3.UP
	var id := _verts.size()
	_verts.append(pos)
	_norms.append(nrm)
	_vid[ci] = id
	return id


func _mesh(plan_ops: Array) -> void:
	var visited := PackedByteArray()
	visited.resize(nx * ny * nz)
	var top_y := origin.y + float(ny - 1) * voxel
	for op in plan_ops:
		var box := op_box(op, top_y)
		var rg := _range(box.position - Vector3.ONE * voxel, box.end + Vector3.ONE * voxel)
		for z in range(rg[2], mini(rg[5] + 1, nz - 1)):
			for y in range(rg[1], mini(rg[4] + 1, ny - 1)):
				for x in range(rg[0], mini(rg[3] + 1, nx - 1)):
					var i := _idx(x, y, z)
					if visited[i] != 0:
						continue
					visited[i] = 1
					var here := f[i] < 0.0
					# the three edges out of this sample, +x, +y, +z
					if (f[i + 1] < 0.0) != here:
						_quad(here, _vertex(x, y, z), _vertex(x, y - 1, z), _vertex(x, y - 1, z - 1), _vertex(x, y, z - 1), Vector3.RIGHT)
					if (f[i + nx] < 0.0) != here:
						_quad(here, _vertex(x, y, z), _vertex(x, y, z - 1), _vertex(x - 1, y, z - 1), _vertex(x - 1, y, z), Vector3.UP)
					if (f[i + nx * ny] < 0.0) != here:
						_quad(here, _vertex(x, y, z), _vertex(x - 1, y, z), _vertex(x - 1, y - 1, z), _vertex(x, y - 1, z), Vector3.BACK)


## A quad across one crossing edge, wound so its front faces the air (Godot's front faces are
## clockwise seen from the front).
func _quad(start_air: bool, a: int, b: int, c: int, d: int, axis: Vector3) -> void:
	if a < 0 or b < 0 or c < 0 or d < 0:
		return
	var toward_air := -axis if start_air else axis
	var pa := _verts[a]
	var geo := (_verts[b] - pa).cross(_verts[c] - pa)
	var q := PackedInt32Array([a, b, c, d])
	if geo.dot(toward_air) > 0.0:
		q = PackedInt32Array([a, d, c, b])
	var centre := (pa + _verts[c]) * 0.5
	var key := Vector2i(int(floor(centre.x / CHUNK_M)), int(floor(centre.z / CHUNK_M)))
	if not _chunk_of.has(key):
		_chunk_of[key] = _quads.size()
		_chunk_keys.append(key)
		_quads.append(PackedInt32Array())
	_quads[_chunk_of[key]].append_array(q)


## The field at a world point, nearest sample (for the openness of the rock).
func sample(p: Vector3) -> float:
	var g := ((p - origin) / voxel).round()
	var x := clampi(int(g.x), 0, nx - 1)
	var y := clampi(int(g.y), 0, ny - 1)
	var z := clampi(int(g.z), 0, nz - 1)
	return f[_idx(x, y, z)]


func _colour(p: Vector3, n: Vector3) -> Color:
	var floorish := clampf((n.y - 0.35) / 0.5, 0.0, 1.0)
	var mottle := noise.get_noise_3d(p.x * 0.35, p.y * 0.8, p.z * 0.35) * 0.5 + 0.5
	var base := palette[0].lerp(palette[1], mottle * 0.55)
	base = base.lerp(palette[2], floorish * 0.55)
	# how much air lies in front of the rock: a cleft is dark, an open wall is lit
	var open := 0.0
	for dist in [0.9, 2.2]:
		open += clampf(-sample(p + n * float(dist)) / float(dist), 0.0, 1.0)
	var ao := clampf(0.3 + 0.35 * open, 0.3, 1.0)
	return Color(base.r, base.g, base.b, ao)


var _cv := PackedVector3Array()
var _cn := PackedVector3Array()
var _cc := PackedColorArray()
var _stamp := PackedInt32Array()
var _local := PackedInt32Array()


func _remap(v: int, ci: int) -> int:
	if _stamp[v] != ci:
		_stamp[v] = ci
		_local[v] = _cv.size()
		_cv.append(_verts[v])
		_cn.append(_norms[v])
		_cc.append(_colour(_verts[v], _norms[v]))
	return _local[v]


func _chunks() -> Array:
	var out: Array = []
	_stamp.resize(_verts.size())
	_stamp.fill(-1)
	_local.resize(_verts.size())
	for ci in _quads.size():
		var quads: PackedInt32Array = _quads[ci]
		_cv = PackedVector3Array()
		_cn = PackedVector3Array()
		_cc = PackedColorArray()
		var idx := PackedInt32Array()
		for q in range(0, quads.size(), 4):
			var a := _remap(quads[q], ci)
			var b := _remap(quads[q + 1], ci)
			var c := _remap(quads[q + 2], ci)
			var d := _remap(quads[q + 3], ci)
			# split along the shorter diagonal
			if _cv[a].distance_squared_to(_cv[c]) <= _cv[b].distance_squared_to(_cv[d]):
				idx.append_array([a, b, c, a, c, d])
			else:
				idx.append_array([a, b, d, b, c, d])
		var faces := PackedVector3Array()
		faces.resize(idx.size())
		for t in idx.size():
			faces[t] = _cv[idx[t]]
		out.append({"key": _chunk_keys[ci], "verts": _cv, "normals": _cn, "colors": _cc,
				"indices": idx, "faces": faces})
	return out
