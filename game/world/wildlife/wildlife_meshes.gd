class_name WildlifeMeshes
extends RefCounted
## The wild birds' bodies, one mesh a kind, built here from rounded parts the way the forge builds
## a hen, and posed by the wildlife shader rather than by a skeleton: every vertex carries what it
## is part of, so the one mesh stands, flies, folds its wings on the water and draws its neck in.
##
##   UV2.x  a wing: the side (+1 left, -1 right) times how far out along the span (0 root .. 1 tip)
##   UV2.y  the neck and head: how much of the neck's movement it takes (0 .. 1); -1 is a leg
##   COLOR  the painted colour, linear
##
## +Z is forward, +Y up, the wings open along X: the forge's props face +Z. A bird is sized in
## metres. The wings are built open, as seen from below in flight; the shader folds them.
##
## A bird is 140-420 triangles, and a flock is one draw.

## What the shader needs to know of each body: the wing root (x across, y up), how far a folded wing
## sweeps back along the body, where the neck goes when it is drawn in (or the head goes down to
## feed), the hip the legs swing from and how far they trail, and the wingbeat.
const RIGS := {
	"heron": {"draft": 0.0, "root": Vector2(0.07, 0.60), "sweep": 0.45, "neck": Vector3(0.0, -0.24, -0.06), "hip": Vector3(0.0, 0.52, -0.02),
			"trail_deg": 80.0, "hz": 1.7, "flap_deg": 34.0},
	"duck": {"draft": 0.05, "root": Vector2(0.08, 0.16), "sweep": 0.22, "neck": Vector3(0.0, -0.10, 0.08), "hip": Vector3(0.0, 0.10, -0.04),
			"trail_deg": 60.0, "hz": 5.2, "flap_deg": 52.0},
	"swan": {"draft": 0.1, "root": Vector2(0.16, 0.30), "sweep": 0.55, "neck": Vector3(0.0, -0.30, 0.25), "hip": Vector3(0.0, 0.1, -0.1),
			"trail_deg": 60.0, "hz": 2.2, "flap_deg": 40.0},
	"gull": {"draft": 0.035, "root": Vector2(0.05, 0.12), "sweep": 0.30, "neck": Vector3(0.0, -0.05, 0.05), "hip": Vector3(0.0, 0.06, -0.02),
			"trail_deg": 70.0, "hz": 2.6, "flap_deg": 40.0},
	"crow": {"draft": 0.0, "root": Vector2(0.045, 0.14), "sweep": 0.22, "neck": Vector3(0.0, -0.09, 0.07), "hip": Vector3(0.0, 0.10, 0.0),
			"trail_deg": 70.0, "hz": 3.3, "flap_deg": 46.0},
	"raven": {"draft": 0.0, "root": Vector2(0.061, 0.189), "sweep": 0.30, "neck": Vector3(0.0, -0.08, 0.06), "hip": Vector3(0.0, 0.12, 0.0),
			"trail_deg": 70.0, "hz": 2.4, "flap_deg": 38.0},
}

static var _cache: Dictionary = {}


static func mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var b := _Builder.new()
	match kind:
		"heron":
			_heron(b)
		"duck":
			_duck(b)
		"swan":
			_swan(b)
		"gull":
			_gull(b)
		"crow":
			_crow(b, 1.0, false)
		"raven":
			_crow(b, 1.35, true)
		_:
			return null
	var m := b.commit()
	_cache[kind] = m
	return m


static func triangles(kind: String) -> int:
	var m := mesh(kind)
	if m == null:
		return 0
	var n := 0
	for s in m.get_surface_count():
		n += int((m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3.0)
	return n


static func _c(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


## A grey heron standing in the shallows: a long neck up in a stoop, a dagger bill, a black crest,
## grey back and wings with black flight feathers, and long legs. About 0.95 m to the crown.
static func _heron(b: _Builder) -> void:
	var grey := _c("#8e959b")
	var pale := _c("#dcdcd4")
	var dark := _c("#26282c")
	var bill := _c("#c99a3c")
	var leg := _c("#8a7c52")
	b.blob(Vector3(0.0, 0.60, 0.0), Vector3(0.11, 0.12, 0.25), grey, 0.0, 8, 6, Vector3(0.0, 0.0, -0.1))
	b.blob(Vector3(0.0, 0.62, -0.26), Vector3(0.06, 0.04, 0.12), grey.darkened(0.1), 0.0, 6, 4)   # tail
	b.blob(Vector3(0.0, 0.66, 0.16), Vector3(0.08, 0.1, 0.1), pale, 0.1, 6, 4)                    # breast
	# the neck in its stoop: up and forward, a kink, the head forward
	b.tube([Vector3(0.0, 0.70, 0.18), Vector3(0.0, 0.82, 0.22), Vector3(0.0, 0.88, 0.18), Vector3(0.0, 0.94, 0.24)],
			[0.045, 0.035, 0.032, 0.03], pale, [0.2, 0.5, 0.8, 1.0], 6)
	b.blob(Vector3(0.0, 0.955, 0.27), Vector3(0.035, 0.035, 0.055), pale, 1.0, 6, 4)            # head
	b.blob(Vector3(0.0, 0.975, 0.24), Vector3(0.02, 0.012, 0.07), dark, 1.0, 5, 3, Vector3(0.0, 0.0, -0.06))  # crest
	b.cone(Vector3(0.0, 0.95, 0.31), Vector3(0.0, 0.94, 0.45), 0.014, bill, 1.0, 5)             # bill
	for s in [-1.0, 1.0]:
		b.tube([Vector3(s * 0.04, 0.55, 0.0), Vector3(s * 0.045, 0.28, 0.01), Vector3(s * 0.045, 0.0, 0.02)],
				[0.012, 0.009, 0.008], leg, [-1.0, -1.0, -1.0], 4)
		b.wing(s, 0.07, 0.60, [[0.0, 0.12], [0.35, 0.10], [0.65, 0.04], [0.92, -0.08]],
				[[0.0, -0.22], [0.35, -0.24], [0.65, -0.22], [0.92, -0.16]], grey, dark, 0.62)


## A mallard on the water: a boat of a body, a round head on a short neck, a flat bill. Drakes have
## the green head, the white collar and the chestnut breast; ducks are the mottled brown. The
## variant is given by the flock, one mesh for both would have needed a colour per instance.
static func _duck(b: _Builder) -> void:
	var body := _c("#7a6248")
	var head := _c("#6d5338")
	var bill := _c("#c28a2e")
	var wing_c := _c("#6f5a44")
	var tip := _c("#3a3128")
	b.blob(Vector3(0.0, 0.10, 0.0), Vector3(0.12, 0.09, 0.24), body, 0.0, 8, 6, Vector3(0.0, 0.0, 0.02))
	b.blob(Vector3(0.0, 0.13, -0.22), Vector3(0.05, 0.03, 0.07), body.darkened(0.2), 0.0, 5, 3)   # tail
	b.tube([Vector3(0.0, 0.15, 0.16), Vector3(0.0, 0.22, 0.19)], [0.045, 0.04], head, [0.4, 0.8], 6)
	b.blob(Vector3(0.0, 0.25, 0.21), Vector3(0.045, 0.045, 0.06), head, 1.0, 6, 4)
	b.blob(Vector3(0.0, 0.235, 0.29), Vector3(0.028, 0.009, 0.045), bill, 1.0, 5, 3)
	for s in [-1.0, 1.0]:
		b.wing(s, 0.08, 0.16, [[0.0, 0.07], [0.18, 0.06], [0.34, 0.0], [0.45, -0.07]],
				[[0.0, -0.10], [0.18, -0.12], [0.34, -0.12], [0.45, -0.10]], wing_c, tip, 0.6)


## A mute swan: a big white body low on the water, the neck up in its S, an orange bill with the
## black knob. 1.5 m long.
static func _swan(b: _Builder) -> void:
	var white := _c("#eeece4")
	var shade := _c("#d4d2ca")
	var bill := _c("#d2622a")
	var black := _c("#1c1c1e")
	b.blob(Vector3(0.0, 0.18, -0.05), Vector3(0.26, 0.17, 0.52), white, 0.0, 10, 7, Vector3(0.0, 0.04, -0.12))
	b.blob(Vector3(0.0, 0.34, -0.20), Vector3(0.2, 0.1, 0.3), shade, 0.0, 8, 5)       # the wings raised over the back
	b.tube([Vector3(0.0, 0.26, 0.38), Vector3(0.0, 0.46, 0.46), Vector3(0.0, 0.66, 0.40), Vector3(0.0, 0.78, 0.44)],
			[0.07, 0.055, 0.045, 0.04], white, [0.2, 0.5, 0.8, 1.0], 7)
	b.blob(Vector3(0.0, 0.80, 0.49), Vector3(0.045, 0.045, 0.08), white, 1.0, 6, 4)
	b.blob(Vector3(0.0, 0.79, 0.54), Vector3(0.022, 0.028, 0.03), black, 1.0, 5, 3)
	b.cone(Vector3(0.0, 0.785, 0.55), Vector3(0.0, 0.765, 0.65), 0.022, bill, 1.0, 5)
	for s in [-1.0, 1.0]:
		b.wing(s, 0.16, 0.30, [[0.0, 0.15], [0.5, 0.12], [0.85, 0.0], [1.05, -0.15]],
				[[0.0, -0.3], [0.5, -0.34], [0.85, -0.3], [1.05, -0.24]], white, shade, 0.7)


## A herring gull: white head and body, grey wings long and narrow with black tips, a yellow bill.
static func _gull(b: _Builder) -> void:
	var white := _c("#eeeeea")
	var grey := _c("#a3aab1")
	var black := _c("#202024")
	var bill := _c("#d9b43a")
	b.blob(Vector3(0.0, 0.10, 0.0), Vector3(0.075, 0.075, 0.2), white, 0.0, 8, 6, Vector3(0.0, 0.0, -0.05))
	b.blob(Vector3(0.0, 0.11, -0.2), Vector3(0.05, 0.02, 0.08), white, 0.0, 5, 3)
	b.blob(Vector3(0.0, 0.16, 0.17), Vector3(0.045, 0.045, 0.055), white, 1.0, 6, 4)
	b.cone(Vector3(0.0, 0.155, 0.215), Vector3(0.0, 0.145, 0.27), 0.012, bill, 1.0, 4)
	for s in [-1.0, 1.0]:
		b.wing(s, 0.05, 0.12, [[0.0, 0.07], [0.25, 0.06], [0.48, 0.02], [0.70, -0.06]],
				[[0.0, -0.08], [0.25, -0.10], [0.48, -0.10], [0.70, -0.09]], grey, black, 0.72)


## A crow (or a raven, bigger, with the wedge of a tail and a heavier bill): black all over.
static func _crow(b: _Builder, k: float, raven: bool) -> void:
	var black := _c("#16161b")
	var sheen := _c("#20222c")
	var bill := _c("#0e0e10")
	b.blob(Vector3(0.0, 0.13, 0.0) * k, Vector3(0.065, 0.065, 0.15) * k, sheen, 0.0, 8, 6, Vector3(0.0, 0.0, -0.04) * k)
	var tail_w := 0.075 if raven else 0.05
	b.blob(Vector3(0.0, 0.13, -0.19) * k, Vector3(tail_w, 0.015, 0.09) * k, black, 0.0, 5, 3)
	b.blob(Vector3(0.0, 0.17, 0.14) * k, Vector3(0.042, 0.042, 0.05) * k, black, 1.0, 6, 4)
	b.cone(Vector3(0.0, 0.165, 0.18) * k, Vector3(0.0, 0.155, 0.24 if raven else 0.23) * k, (0.018 if raven else 0.014) * k, bill, 1.0, 4)
	for s in [-1.0, 1.0]:
		b.tube([Vector3(s * 0.025, 0.1, 0.02) * k, Vector3(s * 0.03, 0.0, 0.03) * k], [0.007 * k, 0.006 * k], bill, [-1.0, -1.0], 3)
		b.wing(s, 0.045 * k, 0.14 * k, [[0.0, 0.06 * k], [0.2 * k, 0.05 * k], [0.36 * k, 0.0], [0.48 * k, -0.07 * k]],
				[[0.0, -0.08 * k], [0.2 * k, -0.1 * k], [0.36 * k, -0.1 * k], [0.48 * k, -0.08 * k]], black, black, 0.8)


class _Builder:
	var st := SurfaceTool.new()

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func _v(p: Vector3, n: Vector3, c: Color, uv2: Vector2) -> void:
		st.set_color(c)
		st.set_normal(n)
		st.set_uv2(uv2)
		st.add_vertex(p)

	## An ellipsoid, with its normals its own; `neck` is the neck weight of every vertex in it, and
	## `taper` pulls its back end in (a body narrows to the tail).
	func blob(centre: Vector3, r: Vector3, colour: Color, neck: float, segs: int, rings: int, taper := Vector3.ZERO) -> void:
		var grid: Array = []
		for i in rings + 1:
			var phi := PI * float(i) / float(rings)
			var row: Array = []
			for j in segs:
				var th := TAU * float(j) / float(segs)
				var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
				# the long axis is Z: swap y and z so the rings run round the body
				d = Vector3(d.x, d.z, d.y)
				var p := Vector3(d.x * r.x, d.y * r.y, d.z * r.z)
				if d.z < 0.0:
					p += taper * (-d.z)
					p.x *= 1.0 + 0.35 * d.z
				var n := Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized()
				row.append([centre + p, n])
			grid.append(row)
		var uv := Vector2(0.0, neck)
		for i in rings:
			for j in segs:
				var a: Array = grid[i][j]
				var b2: Array = grid[i][(j + 1) % segs]
				var c: Array = grid[i + 1][j]
				var d2: Array = grid[i + 1][(j + 1) % segs]
				if i > 0:
					_v(a[0], a[1], colour, uv)
					_v(b2[0], b2[1], colour, uv)
					_v(c[0], c[1], colour, uv)
				if i < rings - 1:
					_v(b2[0], b2[1], colour, uv)
					_v(d2[0], d2[1], colour, uv)
					_v(c[0], c[1], colour, uv)

	## A tube through `pts` with a radius at each; `weights` is each point's UV2.y (neck weight, or
	## -1 for a leg).
	func tube(pts: Array, radii: Array, colour: Color, weights: Array, segs: int) -> void:
		var rings: Array = []
		for i in pts.size():
			var p: Vector3 = pts[i]
			var ahead: Vector3 = (pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)
			var t := ahead.normalized()
			var side := t.cross(Vector3.UP if absf(t.y) < 0.95 else Vector3.RIGHT).normalized()
			var up := side.cross(t).normalized()
			var ring: Array = []
			for j in segs:
				var a := TAU * float(j) / float(segs)
				var n := side * cos(a) + up * sin(a)
				ring.append([p + n * float(radii[i]), n])
			rings.append(ring)
		for i in pts.size() - 1:
			var w0 := Vector2(0.0, float(weights[i]))
			var w1 := Vector2(0.0, float(weights[i + 1]))
			for j in segs:
				var a: Array = rings[i][j]
				var b2: Array = rings[i][(j + 1) % segs]
				var c: Array = rings[i + 1][j]
				var d: Array = rings[i + 1][(j + 1) % segs]
				_v(a[0], a[1], colour, w0)
				_v(b2[0], b2[1], colour, w0)
				_v(c[0], c[1], colour, w1)
				_v(b2[0], b2[1], colour, w0)
				_v(d[0], d[1], colour, w1)
				_v(c[0], c[1], colour, w1)

	## A cone from `base` to `tip` (a bill).
	func cone(base: Vector3, tip: Vector3, radius: float, colour: Color, neck: float, segs: int) -> void:
		var t := (tip - base).normalized()
		var side := t.cross(Vector3.UP).normalized()
		var up := side.cross(t).normalized()
		var uv := Vector2(0.0, neck)
		for j in segs:
			var a0 := TAU * float(j) / float(segs)
			var a1 := TAU * float(j + 1) / float(segs)
			var n0 := side * cos(a0) + up * sin(a0)
			var n1 := side * cos(a1) + up * sin(a1)
			_v(base + n0 * radius, n0, colour, uv)
			_v(base + n1 * radius, n1, colour, uv)
			_v(tip, ((n0 + n1) * 0.5 + t * 0.3).normalized(), colour, uv)

	## One wing, open: a strip from the root out to the tip, its leading edge `front` and trailing
	## edge `back` given as [span out from the root, z] pairs. The outer part (past `dark_from` of
	## the span) takes `tip_colour`: a heron's and a gull's black flight feathers. Thin, not flat:
	## a slight camber so it does not vanish edge-on.
	func wing(side: float, root_x: float, root_y: float, front: Array, back: Array, colour: Color, tip_colour: Color, dark_from: float) -> void:
		var span := float(front[front.size() - 1][0])
		for i in front.size() - 1:
			var quad: Array = []
			for k in [[front, i], [front, i + 1], [back, i + 1], [back, i]]:
				var e: Array = (k[0] as Array)[int(k[1])]
				var out := float(e[0])
				var w := out / maxf(span, 0.001)
				var camber := 0.012 * sin(clampf(w, 0.0, 1.0) * PI) * (1.0 if k[0] == front else 0.0)
				var p := Vector3(side * (root_x + out), root_y + camber, float(e[1]))
				var c := colour.lerp(tip_colour, smoothstep(dark_from - 0.08, dark_from + 0.08, w))
				quad.append([p, c, Vector2(side * maxf(w, 0.001), 0.0)])
			var n := Vector3.UP
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for idx in tri:
					var q: Array = quad[idx]
					_v(q[0], n, q[1], q[2])

	func commit() -> ArrayMesh:
		return st.commit()
