class_name PoiMasonry
extends RefCounted
## Things a point of interest is built of that the forge does not ship as one asset: a drum
## of drystone courses, a humped arch bridge, a flight of steps, a ruined wall, a mound of
## earth, a pool, a sheet of falling water, a post and lintel.
##
## Everything is blocks and boards appended into one SurfaceTool per material, the way
## `Settlement` raises its filler houses, so a tower is one draw call however many stones it
## has. The painted surface shader reads world position, so the blocks need no UVs and a
## course of stone reads as a course of stone whichever way the block is turned.

const COURSE := 0.42          ## height of one course of stone
const BLOCK := 0.86           ## length of one block along a course
const THICK := 0.55           ## wall thickness

var kit: PoiKit
var _unit: Mesh = null
var _cyl: ArrayMesh = null


func _init(k: PoiKit) -> void:
	kit = k
	_unit = _unindexed_box()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1
	_cyl = unindexed(cyl)


## The unit box that `block` lays, with no index. A drum's and a wall's courses are laid vertex by
## vertex with no index, and a SurfaceTool that is given an indexed mesh as well draws only what
## its index names: a watch's merlons laid into its drum's mesh left the merlons in the air and no
## drum, and a colonnade's columns went with its steps. Every face of a box has its own corners,
## so the box looks the same without its index.
static var _box_cache: ArrayMesh = null


static func _unindexed_box() -> ArrayMesh:
	if _box_cache != null:
		return _box_cache
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_box_cache = unindexed(box)
	return _box_cache


## Any primitive mesh without its index, so it can be laid into a batch with everything else. The
## capsules of a cooking tripod laid into the Stair Head's timber (Masonry.limb) took the index and
## left only the tripod: the camp's poles, the lamp posts along the waystones and the ewe's stake all
## went, and their lanterns and banners hung in the air (the user's playtest, 2026-09-25).
static func unindexed(mesh: PrimitiveMesh) -> ArrayMesh:
	var src := mesh.get_mesh_arrays()
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var v: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = src[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = src[Mesh.ARRAY_TANGENT]
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ouv := PackedVector2Array()
	var otan := PackedFloat32Array()
	for i in idx:
		ov.append(v[i])
		on.append(n[i])
		ouv.append(uv[i])
		for c in 4:
			otan.append(tangents[i * 4 + c])
	out[Mesh.ARRAY_VERTEX] = ov
	out[Mesh.ARRAY_NORMAL] = on
	out[Mesh.ARRAY_TEX_UV] = ouv
	out[Mesh.ARRAY_TANGENT] = otan
	var made := ArrayMesh.new()
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return made


func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## One block: a unit box scaled to `size` at `xform` (the transform's own scale is ignored).
func block(st: SurfaceTool, xform: Transform3D, size: Vector3) -> void:
	st.append_from(_unit, 0, xform.scaled_local(size))


func rod(st: SurfaceTool, xform: Transform3D, radius: float, length: float) -> void:
	st.append_from(_cyl, 0, xform.scaled_local(Vector3(radius * 2.0, length, radius * 2.0)))


# --- carved figures ------------------------------------------------------------------------

## A rounded limb, for something carved rather than laid: a capsule from `a` to `b` (local) of
## radius `r`. Boxes and drums made the Thirteenth a wall; a body is round.
func limb(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.01:
		return
	var y := dir / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	st.append_from(_capsule(r, length), 0, Transform3D(Basis(x, y, z), (a + b) * 0.5))


## A capsule's mesh, made once for each radius and length to the centimetre: a beacon's cage is
## forty bars of two sizes, and making each afresh was most of what a tower cost (TRIAGE item 36).
static var _capsules: Dictionary = {}
## Under these radii a limb is drawn coarser (`_capsule`).
const THIN_LIMB_M := 0.075
const SLENDER_LIMB_M := 0.2


static func _capsule(r: float, length: float) -> ArrayMesh:
	var key := Vector2i(roundi(r * 100.0), roundi(length * 100.0))
	if _capsules.has(key):
		return _capsules[key]
	var capsule := CapsuleMesh.new()
	capsule.radius = float(key.x) / 100.0
	capsule.height = float(key.y) / 100.0 + capsule.radius * 2.0
	# a limb no thicker than a thumb's breadth (a taken hart's tines on their poles, hair-roots, a
	# nest's sticks) on six sides and two rings: the full 14 x 5 was 364 triangles a twig, and
	# Tinehold's forty-odd tine-tips on their poles, drawn again into each of the sun's cascades,
	# were 0.28 M primitives of a 1.57 M frame. Six sides on a 6 cm stick are not seen as sides.
	# An arm's thickness (most of a root plate's roots) takes ten sides and three rings, half the
	# triangles: the Windthrow's 300-odd root pieces were 0.1 M triangles before the sun's passes.
	var thin := capsule.radius < THIN_LIMB_M
	var slender := capsule.radius < SLENDER_LIMB_M
	capsule.radial_segments = 6 if thin else (10 if slender else 14)
	capsule.rings = 2 if thin else (3 if slender else 5)
	var made := unindexed(capsule)
	if _capsules.size() > 4096:
		_capsules.clear()
	_capsules[key] = made
	return made


## A rounded mass: a sphere scaled to `radii` (x across, y up, z along `basis`) at `centre`.
func ellipsoid(st: SurfaceTool, centre: Vector3, radii: Vector3, basis := Basis.IDENTITY) -> void:
	if _ball == null:
		var ball := SphereMesh.new()
		ball.radius = 1.0
		ball.height = 2.0
		ball.radial_segments = 22
		ball.rings = 11
		_ball = unindexed(ball)
	st.append_from(_ball, 0, Transform3D(basis, centre).scaled_local(radii))


static var _ball: ArrayMesh = null


## Finishes a batch into one MeshInstance3D under the dressing. A silhouette piece is built
## in the far ring as well and drawn out to the far range; anything else is near-ring only.
func commit(st: SurfaceTool, mat: Material, node_name: String, silhouette := false) -> MeshInstance3D:
	if kit.far and not silhouette:
		return null
	if kit.deferred:
		# a place raised while the world is drawn: its meshes are made on a worker thread after its
		# builder has run (PoiDressing.meshes_ready), so the frame it is raised in is its layout alone
		var later := MeshInstance3D.new()
		later.material_override = mat
		later.name = node_name
		kit.root.add_child(later)
		kit.pending.append([later, st])
		if kit.far:
			kit._far_range(later)
		return later
	st.generate_normals()
	var m := st.commit()
	if m == null or m.get_surface_count() == 0:
		return null
	var inst := MeshInstance3D.new()
	inst.mesh = m
	inst.material_override = mat
	inst.name = node_name
	kit.root.add_child(inst)
	if kit.far:
		kit._far_range(inst)
	return inst


# --- courses of stone ------------------------------------------------------------------------

## A drum of stone courses in the space of `frame` (its Y is up the drum), of radius `r` and
## `height`. `broken` (0..1) tears the top down raggedly by up to that fraction; `door_yaw`
## leaves a doorway in the ring at that bearing. Collision is a ring of wall segments, so the
## inside is somewhere you can stand. Returns the mesh.
func drum(st: SurfaceTool, ring_frame: Transform3D, r: float, height: float, broken := 0.0,
		door_yaw := NAN, collide := true, course_h := COURSE) -> void:
	# A wall is a wall, not a heap of bricks. The shell is one ring of quads inside and out,
	# stepped in a little at every course so the courses read in silhouette, and the painted
	# surface's stone-block pattern draws the individual stones. Laying each stone as its own
	# box instead cost six hundred boxes a tower and photographed as a pile of pillows.
	var sectors := maxi(int(round(TAU * r / 0.55)), 16)
	if kit.far:
		# a silhouette, past 384 m: a course's few millimetres' step and a sector's half metre are
		# under a pixel there, and laying them was up to 0.6 s of one frame for one tower on the
		# skyline (the Tumbled Watch, TRIAGE item 36); it keeps its outline and its broken top
		sectors = maxi(int(sectors * 0.5), 12)
		course_h = maxf(course_h, height / 4.0)
	var courses := maxi(int(ceil(height / course_h)), 1)
	var tops: Array[float] = []
	var phase := kit.rng.randf_range(0.0, TAU)
	var freq := kit.rng.randf_range(1.0, 2.2)
	var door_half := (0.75 / maxf(r, 1.0)) + 0.16
	for i in sectors:
		var a := TAU * float(i) / float(sectors)
		var tear := 0.5 + 0.5 * sin(a * freq + phase) + 0.25 * sin(a * 3.7 + phase * 1.7)
		tops.append(height * (1.0 - broken * clampf(tear, 0.0, 1.0)))
	var floors: Array[float] = []
	for i in sectors:
		var a := TAU * float(i) / float(sectors)
		# the doorway: the wall starts above the lintel over the width of the door
		var in_door := not is_nan(door_yaw) and absf(angle_difference(a, door_yaw)) < door_half
		floors.append(2.3 if in_door else 0.0)

	# where the ground under a sector's foot is below the ring's (a pad that tilts and rolls, up to
	# 0.45 m), a footing reaches down to it, so no side of a tower or a round stands on air
	if ring_frame.basis.y.normalized().y > 0.95 and not kit.far:
		for i in sectors:
			if floors[i] > 0.0:
				continue
			var a0 := TAU * float(i) / float(sectors)
			var a1 := TAU * float(i + 1) / float(sectors)
			var drop := 0.0
			for a in [a0, a1]:
				var w: Vector3 = ring_frame * Vector3(sin(a) * r, 0.0, cos(a) * r)
				drop = maxf(drop, ring_frame.origin.y - (kit.ground(kit.origin.x + w.x, kit.origin.z + w.z) - kit.origin.y))
			if drop > 0.03:
				_shell_quads(st, ring_frame, a0, a1, -drop - 0.08, 0.0, r, r - THICK, true, false)
	for c in courses:
		var y0 := course_h * float(c)
		var y1 := minf(course_h * float(c + 1), height)
		# every course sits a few millimetres inside the one below, which is what makes a
		# drystone drum read as courses rather than as a pipe
		var out_r := r - float(c) * 0.012
		var in_r := out_r - THICK
		for i in sectors:
			var a0 := TAU * float(i) / float(sectors)
			var a1 := TAU * float(i + 1) / float(sectors)
			var top: float = minf(tops[i], tops[(i + 1) % sectors])
			var floor_y: float = maxf(floors[i], floors[(i + 1) % sectors])
			if y1 <= floor_y or y0 >= top:
				continue
			var lo := maxf(y0, floor_y)
			var hi := minf(y1, top)
			var wob := kit.rng.randf_range(-0.02, 0.02)
			_shell_quads(st, ring_frame, a0, a1, lo, hi, out_r + wob, in_r + wob,
					y0 <= floor_y + 0.001, y1 >= top - 0.001)
	if not is_nan(door_yaw):
		# the lintel over the door, and the jambs down its sides
		var a_mid := door_yaw
		for s in [-1.0, 1.0]:
			var a := a_mid + door_half * float(s)
			_shell_quads(st, ring_frame, a - 0.04, a + 0.04, 0.0, 2.3, r, r - THICK, true, true)
	if collide and not kit.far:
		var segs := 12
		for i in segs:
			var a := TAU * (float(i) + 0.5) / float(segs)
			var sector := int(floor(a / TAU * float(sectors))) % sectors
			var h := tops[sector]
			if not is_nan(door_yaw) and absf(angle_difference(a, door_yaw)) < TAU / float(segs):
				continue
			var local := Transform3D(Basis(Vector3.UP, a + PI * 0.5), Vector3(sin(a) * r, h * 0.5, cos(a) * r))
			kit.collider(Vector3(TAU * r / float(segs) * 1.02, h, THICK), ring_frame * local, "stone")


## One sector of a drum's wall: the outer face, the inner face, and the floor and cap where
## the wall begins and ends, all in `frame`'s space (its Y runs up the drum).
func _shell_quads(st: SurfaceTool, ring_frame: Transform3D, a0: float, a1: float, y0: float, y1: float,
		out_r: float, in_r: float, floor_face: bool, cap: bool) -> void:
	var o0 := Vector3(sin(a0) * out_r, 0.0, cos(a0) * out_r)
	var o1 := Vector3(sin(a1) * out_r, 0.0, cos(a1) * out_r)
	var i0 := Vector3(sin(a0) * in_r, 0.0, cos(a0) * in_r)
	var i1 := Vector3(sin(a1) * in_r, 0.0, cos(a1) * in_r)
	var lo := Vector3(0.0, y0, 0.0)
	var hi := Vector3(0.0, y1, 0.0)
	_quad(st, ring_frame, o0 + lo, o1 + lo, o1 + hi, o0 + hi)          # outside
	_quad(st, ring_frame, i1 + lo, i0 + lo, i0 + hi, i1 + hi)          # inside
	if cap:
		_quad(st, ring_frame, o0 + hi, o1 + hi, i1 + hi, i0 + hi)
	if floor_face:
		_quad(st, ring_frame, i0 + lo, i1 + lo, o1 + lo, o0 + lo)


static func _quad(st: SurfaceTool, ring_frame: Transform3D, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	for p in [p0, p1, p2, p0, p2, p3]:
		st.add_vertex(ring_frame * (p as Vector3))


## A straight run of courses from `a` to `b` (local xz) standing on the ground, `height` high,
## torn down by `broken` toward one end. Returns nothing; collides as one box.
func wall(st: SurfaceTool, a: Vector2, b: Vector2, height: float, broken := 0.0,
		collide := true, course_h := COURSE) -> void:
	var seg := b - a
	var length := seg.length()
	if length < 0.3:
		return
	var dir := seg / length
	var yaw := atan2(dir.x, dir.y)
	# As with the drum: one slab per bay, stepped in at each course, with the stones drawn by
	# the painted surface rather than modelled.
	var bays := maxi(int(round(length / 1.1)), 1)
	var courses := maxi(int(ceil(height / course_h)), 1)
	var ya := kit.ground(kit.origin.x + a.x, kit.origin.z + a.y) - kit.origin.y
	var yb := kit.ground(kit.origin.x + b.x, kit.origin.z + b.y) - kit.origin.y
	# the ground under each bay's two ends: a pad tilts and rolls now (up to 0.45 m), and a wall
	# laid on the straight line between its ends stood on air in the hollows and in the ground on
	# the rises; each bay stands from the lower of its ends, a hand into it
	var feet: Array[float] = []
	for i in bays + 1:
		var q := a + dir * (length * float(i) / float(bays))
		feet.append(kit.ground(kit.origin.x + q.x, kit.origin.z + q.y) - kit.origin.y)
	var tear_from := kit.rng.randf_range(0.2, 0.8)
	var min_h := height
	var tops: Array[float] = []
	for i in bays + 1:
		var t := float(i) / float(bays)
		tops.append(height * (1.0 - broken * clampf((t - tear_from) / maxf(1.0 - tear_from, 0.05), 0.0, 1.0)
				* kit.rng.randf_range(0.6, 1.2)))
	for c in courses:
		var y0 := course_h * float(c)
		var y1 := course_h * float(c + 1)
		var thick := THICK - float(c) * 0.012
		for i in bays:
			var top: float = minf(tops[i], tops[i + 1])
			if y0 >= top:
				continue
			var hi := minf(y1, top)
			min_h = minf(min_h, top)
			var t := (float(i) + 0.5) / float(bays)
			var p := a + dir * (length * t)
			var mid_g := (feet[i] + feet[i + 1]) * 0.5
			# the first course reaches down a hand into the lower of the bay's two feet; every course
			# rides on the bay's own ground, so the courses step with the land
			var bottom := (minf(feet[i], feet[i + 1]) - 0.08) if c == 0 else mid_g + y0
			var top_y := mid_g + hi
			var xf := Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(p.x, (bottom + top_y) * 0.5, p.y))
			block(st, xf, Vector3(length / float(bays) * 1.01, top_y - bottom, thick))
	if collide:
		var mid := (a + b) * 0.5
		var h := maxf(min_h, course_h)
		kit.collider(Vector3(length, h, THICK),
				Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(mid.x, (ya + yb) * 0.5 + h * 0.5, mid.y)), "stone")


## A doorway: two jambs and a lintel of stone, standing on the ground at `at`, facing `yaw`.
func doorway(st: SurfaceTool, at: Vector2, yaw: float, width := 1.4, height := 2.3) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var ground := kit.ground(kit.origin.x + at.x, kit.origin.z + at.y) - kit.origin.y
	for side in [-1.0, 1.0]:
		var p := Vector3(at.x, ground + height * 0.5, at.y) + basis * Vector3(float(side) * (width * 0.5 + 0.22), 0.0, 0.0)
		block(st, Transform3D(basis, p), Vector3(0.44, height, THICK))
		kit.collider(Vector3(0.44, height, THICK), Transform3D(basis, p), "stone")
	var lintel := Vector3(at.x, ground + height + 0.2, at.y)
	block(st, Transform3D(basis, lintel), Vector3(width + 0.9, 0.4, THICK + 0.1))


# --- crossings -------------------------------------------------------------------------------

## A humped stone bridge whose deck runs from `a` to `b` (local xz), `width` across, rising
## `rise` at the middle above the straight line between its ends (which stand on the ground,
## or on `deck_y` where given). Parapets either side, an arch ring beneath, abutments at the
## ends. Collision follows the deck so it can be crossed, and says `surface` underfoot (stone, or
## wood for a timber span built on the same bones).
func arch_bridge(st: SurfaceTool, a: Vector2, b: Vector2, width: float, rise: float,
		deck_y := NAN, parapet := true, arch := true, arch_sag := NAN, surface := "stone") -> void:
	var seg := b - a
	var length := seg.length()
	if length < 2.0:
		return
	var dir := seg / length
	var yaw := atan2(dir.x, dir.y)
	var ya := deck_y if not is_nan(deck_y) else kit.ground(kit.origin.x + a.x, kit.origin.z + a.y) - kit.origin.y
	var yb := deck_y if not is_nan(deck_y) else kit.ground(kit.origin.x + b.x, kit.origin.z + b.y) - kit.origin.y
	var n := maxi(int(ceil(length / 1.6)), 4)
	var deck_t := 0.42
	for i in n:
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n)
		var tm := (t0 + t1) * 0.5
		var y0 := _hump(t0, ya, yb, rise)
		var y1 := _hump(t1, ya, yb, rise)
		var seg_len := sqrt(pow(length / float(n), 2.0) + pow(y1 - y0, 2.0))
		var pitch := atan2(y1 - y0, length / float(n))
		var p := a + dir * (length * tm)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
		var xf := Transform3D(basis, Vector3(p.x, (y0 + y1) * 0.5, p.y))
		block(st, xf, Vector3(width, deck_t, seg_len * 1.02))
		kit.collider(Vector3(width, deck_t, seg_len * 1.02), xf, surface)
		if parapet:
			for side in [-1.0, 1.0]:
				var q := xf.origin + basis * Vector3(float(side) * (width * 0.5 - 0.17), deck_t * 0.5 + 0.42, 0.0)
				block(st, Transform3D(basis, q), Vector3(0.34, 0.84, seg_len * 1.02))
				kit.collider(Vector3(0.34, 0.84, seg_len * 1.02), Transform3D(basis, q), surface)
	if arch:
		# the ring under the deck: voussoirs on an arc from one abutment to the other
		var span := length * 0.72
		var sag := arch_sag if not is_nan(arch_sag) else maxf(rise, 0.8) + 1.6
		var k := maxi(int(span / 0.9), 6)
		for i in k:
			var t := (float(i) + 0.5) / float(k)
			var along := (t - 0.5) * span
			var y := _hump(0.5 + along / length, ya, yb, rise) - deck_t - sag * (1.0 - pow(2.0 * t - 1.0, 2.0)) * 0.5 - 0.3
			var p := a + dir * (length * 0.5 + along)
			var slope := -sag * 2.0 * (2.0 * t - 1.0) / span
			var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -atan(slope))
			block(st, Transform3D(basis, Vector3(p.x, y, p.y)), Vector3(width * 0.94, 0.5, span / float(k) * 1.05))
	# abutments: a pier at each end down to the ground
	for end in [[a, ya], [b, yb]]:
		var p: Vector2 = end[0]
		var y: float = end[1]
		var g := kit.ground(kit.origin.x + p.x, kit.origin.z + p.y) - kit.origin.y
		var depth := maxf(y - g, 0.3) + 0.4
		var basis := Basis(Vector3.UP, yaw)
		var xf := Transform3D(basis, Vector3(p.x, y - depth * 0.5 + 0.1, p.y))
		block(st, xf, Vector3(width + 0.5, depth, 2.2))
		kit.collider(Vector3(width + 0.5, depth, 2.2), xf, surface)


static func _hump(t: float, ya: float, yb: float, rise: float) -> float:
	return lerpf(ya, yb, t) + rise * (1.0 - pow(2.0 * t - 1.0, 2.0))


## A flat deck of planks on posts from `a` to `b`, `width` across, its walking surface at
## local height `y` (constant). Posts every few metres go down to the ground or the bed.
func plank_deck(planks: SurfaceTool, posts: SurfaceTool, a: Vector2, b: Vector2, width: float,
		y: float, post_every := 3.0, rail := false) -> void:
	var seg := b - a
	var length := seg.length()
	if length < 1.0:
		return
	var dir := seg / length
	var yaw := atan2(dir.x, dir.y)
	var basis := Basis(Vector3.UP, yaw)
	var n := maxi(int(ceil(length / 0.32)), 3)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var p := a + dir * (length * t)
		var xf := Transform3D(basis, Vector3(p.x, y - 0.04 + kit.rng.randf_range(-0.012, 0.012), p.y))
		block(planks, xf, Vector3(width * kit.rng.randf_range(0.97, 1.0), 0.07, length / float(n) * 0.9))
	# two bearers under the planks, and the posts
	for side in [-1.0, 1.0]:
		var mid := (a + b) * 0.5
		var q := Vector3(mid.x, y - 0.16, mid.y) + basis * Vector3(float(side) * (width * 0.5 - 0.25), 0.0, 0.0)
		block(posts, Transform3D(basis, q), Vector3(0.16, 0.16, length))
	var k := maxi(int(ceil(length / post_every)), 2)
	for i in k + 1:
		var t := float(i) / float(k)
		var p := a + dir * (length * t)
		for side in [-1.0, 1.0]:
			var foot := Vector3(p.x, 0.0, p.y) + basis * Vector3(float(side) * (width * 0.5 - 0.22), 0.0, 0.0)
			var g := kit.ground(kit.origin.x + foot.x, kit.origin.z + foot.z) - kit.origin.y
			var top := y + (0.95 if rail else -0.1)
			var h := top - g
			if h <= 0.1:
				continue
			block(posts, Transform3D(basis, Vector3(foot.x, g + h * 0.5, foot.z)), Vector3(0.2, h, 0.2))
	if rail:
		for side in [-1.0, 1.0]:
			var mid := (a + b) * 0.5
			var q := Vector3(mid.x, y + 0.9, mid.y) + basis * Vector3(float(side) * (width * 0.5 - 0.22), 0.0, 0.0)
			block(posts, Transform3D(basis, q), Vector3(0.1, 0.1, length))
	kit.collider(Vector3(width, 0.2, length), Transform3D(basis, Vector3((a.x + b.x) * 0.5, y - 0.1, (a.y + b.y) * 0.5)), "wood")


## A flight of `count` steps from `start` (local xz, at local height `y0`) along `dir`, each
## `rise` up (negative: down) and `tread` along, `width` across. Every step is walkable.
func steps(st: SurfaceTool, start: Vector2, dir: Vector2, y0: float, count: int, rise: float,
		tread: float, width: float, block_depth := 0.9) -> void:
	var yaw := atan2(dir.x, dir.y)
	var basis := Basis(Vector3.UP, yaw)
	for i in count:
		var p := start + dir * (tread * (float(i) + 0.5))
		var top := y0 + rise * float(i + 1)
		var xf := Transform3D(basis, Vector3(p.x, top - block_depth * 0.5, p.y))
		block(st, xf, Vector3(width, block_depth, tread * 1.02))
		kit.collider(Vector3(width, block_depth, tread * 1.02), xf, "stone")


# --- earth, water and timber --------------------------------------------------------------------

## A dome of ground: an island, a peat hummock, a turf kiln, a drift of snow. Radius `r`,
## `height` at the centre, sitting at local height `base_y`; `power` shapes it (1 = round,
## 3 = flat-topped). Walkable when `collide`.
func mound(centre: Vector3, r: float, height: float, mat: Material, node_name: String,
		collide := true, power := 1.6, rings := 7, segments := 20, silhouette := false,
		rough := 0.06) -> MeshInstance3D:
	if kit.far and not silhouette:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A dome with no variation in it is a marshmallow, which is exactly how the first drifts of
	# snow at the Windgate toll-house photographed. `rough` lifts and drops the surface in a
	# few broad lobes as well as jittering the rim, so it reads as something the wind piled.
	var lobes := kit.rng.randf_range(2.0, 4.0)
	var phase := kit.rng.randf_range(0.0, TAU)
	var pts: Array = []
	for i in rings + 1:
		var f := float(i) / float(rings)
		var rr := r * f
		var row: Array = []
		for j in segments:
			var a := TAU * float(j) / float(segments)
			var swell := 1.0 + rough * (sin(a * lobes + phase) + 0.6 * sin(a * (lobes * 2.3) - phase))
			var y := height * pow(maxf(1.0 - f * f, 0.0), power * 0.5) * swell
			y += height * rough * 0.5 * sin(a * (lobes + 1.7) + phase * 1.3) * f
			var wob := 1.0 + (kit.rng.randf_range(-rough, rough) if i > 0 else 0.0) \
					+ (rough * 1.4 * sin(a * lobes + phase) if i == rings else 0.0)
			row.append(centre + Vector3(sin(a) * rr * wob, y, cos(a) * rr * wob))
		pts.append(row)
	for i in rings:
		for j in segments:
			var j1 := (j + 1) % segments
			var p00: Vector3 = pts[i][j]
			var p01: Vector3 = pts[i][j1]
			var p10: Vector3 = pts[i + 1][j]
			var p11: Vector3 = pts[i + 1][j1]
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p10)
			if i > 0:
				st.add_vertex(p00)
				st.add_vertex(p01)
				st.add_vertex(p11)
	st.generate_normals()
	var m := st.commit()
	var inst := MeshInstance3D.new()
	inst.mesh = m
	inst.material_override = mat
	inst.name = node_name
	kit.root.add_child(inst)
	if kit.far:
		kit._far_range(inst)
	elif collide:
		kit.collider_shape(m.create_trimesh_shape(), Transform3D.IDENTITY, "dirt")
	return inst


## A tip's profile, its height as a share of the tip's over the ground, `f` of the way out from the
## crown to the toe: the level top the barrows or the wagons tipped from, a steep face, a bench where
## an older tip stops, a face, a lower bench, the toe.
const TIP_PROFILE := [Vector2(0.0, 1.0), Vector2(0.28, 0.97), Vector2(0.4, 0.62), Vector2(0.55, 0.57),
		Vector2(0.67, 0.27), Vector2(0.8, 0.22), Vector2(0.93, 0.04), Vector2(1.0, 0.0)]
## Spoil's colours as multipliers of its painted material (vertex colours): the fresh-tipped top,
## two streaks run down its faces, and the green an old tip takes from its foot. A region passes its
## own: the Crown Drift's calamine streaks verdigris and rust, a chalk tip flint-grey and ochre.
const SPOIL_TINTS := {"fresh": Color(0.92, 0.95, 1.0), "streak_a": Color(0.78, 1.18, 1.0),
		"streak_b": Color(1.22, 0.92, 0.7), "grass": Color(0.62, 1.12, 0.52)}


static func tip_share(f: float) -> float:
	for i in TIP_PROFILE.size() - 1:
		var a: Vector2 = TIP_PROFILE[i]
		var b: Vector2 = TIP_PROFILE[i + 1]
		if f <= b.x:
			return lerpf(a.y, b.y, (f - a.x) / maxf(b.x - a.x, 0.0001))
	return 0.0


## A heap of mine or quarry waste at local `at`, `r` out to its toe across the way it spills (and
## `stretch` times that along it, for a tongue tipped down a slope), its top `h` over the ground at
## its middle and level (it was tipped from there), spilling further `spill`-ward: on its top the
## little cones each load made, then a steep face, a bench where an older tip stopped short of the
## last, a face, a lower bench, the toe; rain-rills down its faces; streaked in `tints` (SPOIL_TINTS's
## keys), the faces darker than the benches; an old one (`old`) softer and greening from its foot.
## One draw, built in the far ring too, and a trimesh collider. Returns local points on it and round
## its toe for its loose stone (spoil_stones), which is most of what makes it read as rubble.
## (PoiMasonry.mound's dome, and the regions' own humps, read as tarpaulins over a heap: smooth
## cones the owner photographed at the Crown Drift, Knappers' Deep and Ghaleld alike; a first heap
## flat-shaded in big facets read as a crumpled boulder.)
func spoil_heap(at: Vector2, spill: Vector2, r: float, h: float, mat: Material, tints: Dictionary = SPOIL_TINTS,
		old := false, node_name := "Spoil", stretch := 1.0) -> Array:
	var k := kit
	var rings := 22
	var segs := 56
	var sp := spill.normalized() if spill != Vector2.ZERO else Vector2(0.0, 1.0)
	var a_spill := atan2(sp.x, sp.y)
	var top := k.on_ground(at.x, at.y).y + h
	var ph := k.rng.randf_range(0.0, TAU)
	var ph2 := k.rng.randf_range(0.0, TAU)
	var rills := 11 + k.rng.randi() % 6
	var lump := 0.03 if old else 0.065
	# the loads tipped on its top, each a little cone where a barrow or a wagon was emptied
	var loads: Array = []
	for n in (4 if old else 9):
		var la := k.rng.randf_range(0.0, TAU)
		loads.append(Vector4(sin(la), cos(la), k.rng.randf_range(0.0, 0.22), k.rng.randf_range(0.14, 0.24)))
	var fresh: Color = tints.get("fresh", SPOIL_TINTS["fresh"])
	var streak_a: Color = tints.get("streak_a", SPOIL_TINTS["streak_a"])
	var streak_b: Color = tints.get("streak_b", SPOIL_TINTS["streak_b"])
	var grass: Color = tints.get("grass", SPOIL_TINTS["grass"])
	var pts: Array = []
	var cols: Array = []
	for i in rings + 1:
		var f := float(i) / float(rings)
		var row: Array = []
		var crow: Array = []
		for j in segs:
			var a := TAU * float(j) / float(segs)
			var da := a - a_spill
			# an ellipse `stretch` long along the spill, reaching further down it, its outline ragged
			var ell := 1.0 / sqrt(pow(cos(da) / stretch, 2.0) + pow(sin(da), 2.0))
			var reach := r * ell * (1.0 + 0.32 * cos(da)) * (1.0 + 0.07 * sin(3.0 * a + ph) + 0.04 * sin(7.0 * a - ph2))
			var fw := f
			if i > 0 and i < rings:
				fw = clampf(f + k.rng.randf_range(-0.012, 0.012), 0.0, 1.0)
			var p := at + Vector2(sin(a), cos(a)) * reach * fw
			var gp := k.on_ground(p.x, p.y).y
			# the benches wander round the heap
			var fb := clampf(f + 0.03 * sin(2.0 * a + ph2) + 0.02 * sin(5.0 * a + ph), 0.0, 1.0)
			var share := tip_share(fb)
			var steep := clampf((tip_share(maxf(fb - 0.03, 0.0)) - tip_share(minf(fb + 0.03, 1.0))) / 0.09, 0.0, 1.0)
			var y := gp + maxf(top - gp, h * 0.4) * share
			if i == rings:
				y = gp - 0.35
			else:
				# the loads on the top, the middle point too: raised round a middle left low, the
				# top read as a sack's neck drawn in
				for l: Vector4 in loads:
					var lc := Vector2(l.x, l.y) * l.z
					var dd := (Vector2(sin(a), cos(a)) * f - lc).length() / l.w
					if dd < 1.6:
						y += h * 0.07 * exp(-dd * dd * 1.6) * (1.0 - steep)
			if i > 0 and i < rings:
				# lumps everywhere, rougher on the faces; rills down the faces. Both come in over the
				# level top (TIP_PROFILE's first 0.28): at full strength round the one middle point
				# they folded in to it like a sack's neck.
				var crown := smoothstep(0.0, 0.3, f)
				y += crown * h * lump * (0.6 + steep) * (0.5 * sin(a * 14.0 + f * 23.0 + ph) * sin(f * 31.0 - a * 9.0 + ph2)
						+ k.rng.randf_range(-0.6, 0.6))
				var rill := pow(maxf(cos(a * float(rills) + ph + 3.0 * f), 0.0), 10.0)
				y -= crown * h * (0.04 if old else 0.09) * steep * rill
			row.append(Vector3(p.x, y, p.y))
			# the faces fresh and darker, the benches and the top weathered paler; the streaks run
			# down the faces; an old tip greens from its foot
			var tint := fresh * lerpf(1.04, 0.86, steep)
			var streak := sin(a * 13.0 + ph) * sin(a * 5.0 - ph2) + 0.15 * sin(f * 9.0 + a * 2.0)
			if streak > 0.3:
				tint = tint.lerp(streak_a, clampf((streak - 0.3) * 2.2, 0.0, 1.0) * (0.35 + 0.65 * steep))
			elif streak < -0.5:
				tint = tint.lerp(streak_b, clampf((-streak - 0.5) * 2.2, 0.0, 1.0) * (0.35 + 0.65 * steep))
			if old:
				tint = tint.lerp(grass, clampf(1.2 - share * 1.5, 0.0, 0.92))
			else:
				tint = tint.lerp(grass, clampf((f - 0.9) * 6.0, 0.0, 0.5))
			tint = tint * k.rng.randf_range(0.9, 1.05)
			tint.a = 1.0
			crow.append(tint)
		pts.append(row)
		cols.append(crow)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for i in rings:
		for j in segs:
			var j1 := (j + 1) % segs
			var quad: Array = [[i, j], [i + 1, j1], [i + 1, j]]
			if i > 0:
				quad.append_array([[i, j], [i, j1], [i + 1, j1]])
			for ij: Array in quad:
				var v: Vector3 = pts[ij[0]][ij[1]]
				st.set_color(cols[ij[0]][ij[1]])
				st.add_vertex(v)
				faces.append(v)
	commit(st, mat, node_name, true)
	if not k.far:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		k.collider_shape(shape, Transform3D.IDENTITY, "dirt")
	# loose stone: over its faces and benches, and round the toe where it rolled further down the land
	var out: Array = []
	# (each stone is one of the forge's, some 2500 triangles near: 64 a tip took the Charter Delf's
	# three from 33k triangles to 433k)
	for n in (6 if old else 16):
		var i := k.rng.randi_range(int(rings * 0.3), rings - 1)
		if n % 4 == 0:
			i = rings - k.rng.randi_range(0, 1)
		var p: Vector3 = pts[i][k.rng.randi() % segs]
		if i >= rings - 1:
			# past the toe, more of it on the downhill side
			var o := Vector2(p.x - at.x, p.z - at.y).normalized()
			var q := Vector2(p.x, p.z) + o * k.rng.randf_range(0.3, 2.5 + 2.5 * maxf(o.dot(sp), 0.0))
			p = k.on_ground(q.x, q.y)
		out.append(p)
	return out


## Loose stone at `points` (local, as spoil_heap returns them): every third one of the region's
## boulders at a small scale, the rest its scree. The two scatters, either of them null where the
## region has no such rock or in the far ring.
func spoil_stones(points: Array, big_scale := Vector2(0.4, 0.9)) -> Array:
	var k := kit
	if k.far or points.is_empty():
		return [null, null]
	var rock := k.rock("boulder")
	var scree := k.rock("scree")
	var big: Array = []
	var small: Array = []
	for i in points.size():
		var p: Vector3 = points[i]
		if rock != "" and (i % 3 == 0 or scree == ""):
			var sc := k.rng.randf_range(big_scale.x, big_scale.y)
			big.append(PoiKit.transform_at(p - Vector3(0.0, 0.3 * sc, 0.0), k.rng.randf_range(0.0, TAU), sc))
		elif scree != "":
			small.append(PoiKit.transform_at(p - Vector3(0.0, 0.08, 0.0), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.7, 1.3)))
	var a: MultiMeshInstance3D = k.scatter(rock, big, true) if not big.is_empty() else null
	var b: MultiMeshInstance3D = k.scatter(scree, small, false) if not small.is_empty() else null
	return [a, b]


## A round sheet of standing water at local height `y`.
func pool(centre: Vector2, r: float, y: float, mat: Material, node_name := "Pool", segments := 24) -> MeshInstance3D:
	if kit.far:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(centre.x, y, centre.y)
	for j in segments:
		var a0 := TAU * float(j) / float(segments)
		var a1 := TAU * float(j + 1) / float(segments)
		var w0 := r * kit.rng.randf_range(0.9, 1.08)
		var w1 := r * kit.rng.randf_range(0.9, 1.08)
		st.add_vertex(c)
		st.add_vertex(c + Vector3(sin(a1) * w1, 0.0, cos(a1) * w1))
		st.add_vertex(c + Vector3(sin(a0) * w0, 0.0, cos(a0) * w0))
	st.generate_normals()
	var inst := MeshInstance3D.new()
	inst.mesh = st.commit()
	inst.material_override = mat
	inst.name = node_name
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.root.add_child(inst)
	return inst


## A hanging sheet — falling water, or the glass it froze into — `width` across and `height`
## tall, its top edge centred at `top` (local), facing `yaw`, bellying out a little at the
## foot the way a fall does. UV v runs down the fall so the shader can scroll along it.
func sheet(top: Vector3, yaw: float, width: float, height: float, mat: Material,
		node_name := "Sheet", belly := 0.6, silhouette := true, cols := 4, rows := 6) -> MeshInstance3D:
	if kit.far and not silhouette:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var basis := Basis(Vector3.UP, yaw)
	var grid: Array = []
	for i in rows + 1:
		var v := float(i) / float(rows)
		var row: Array = []
		for j in cols + 1:
			var u := float(j) / float(cols)
			var out := belly * v * v
			var x := (u - 0.5) * width * (1.0 + 0.25 * v)
			row.append(top + basis * Vector3(x, -height * v, out))
		grid.append(row)
	for i in rows:
		for j in cols:
			var v0 := float(i) / float(rows)
			var v1 := float(i + 1) / float(rows)
			var u0 := float(j) / float(cols)
			var u1 := float(j + 1) / float(cols)
			st.set_uv(Vector2(u0, v0))
			st.add_vertex(grid[i][j])
			st.set_uv(Vector2(u1, v0))
			st.add_vertex(grid[i][j + 1])
			st.set_uv(Vector2(u1, v1))
			st.add_vertex(grid[i + 1][j + 1])
			st.set_uv(Vector2(u0, v0))
			st.add_vertex(grid[i][j])
			st.set_uv(Vector2(u1, v1))
			st.add_vertex(grid[i + 1][j + 1])
			st.set_uv(Vector2(u0, v1))
			st.add_vertex(grid[i + 1][j])
	st.generate_normals()
	var inst := MeshInstance3D.new()
	inst.mesh = st.commit()
	inst.material_override = mat
	inst.name = node_name
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.root.add_child(inst)
	if kit.far:
		kit._far_range(inst)
	return inst


## A timber post standing on the ground at local xz, `height` tall and `side` square.
func post(st: SurfaceTool, at: Vector2, height: float, side := 0.18, lean := Vector3.ZERO) -> Vector3:
	var g := kit.ground(kit.origin.x + at.x, kit.origin.z + at.y) - kit.origin.y
	var basis := Basis.from_euler(lean)
	var xf := Transform3D(basis, Vector3(at.x, g, at.y) + basis * Vector3(0.0, height * 0.5, 0.0))
	block(st, xf, Vector3(side, height, side))
	kit.collider(Vector3(side, height, side), xf, "wood")
	return Vector3(at.x, g, at.y) + basis * Vector3(0.0, height, 0.0)


## Two posts and a lintel: a frame to hang a bell or a lantern from. Returns the lintel's
## midpoint, where the thing hangs.
func frame(st: SurfaceTool, at: Vector2, yaw: float, width: float, height: float, side := 0.16) -> Vector3:
	var basis := Basis(Vector3.UP, yaw)
	var tops: Array = []
	for s in [-1.0, 1.0]:
		var foot := Vector3(at.x, 0.0, at.y) + basis * Vector3(float(s) * width * 0.5, 0.0, 0.0)
		tops.append(post(st, Vector2(foot.x, foot.z), height, side))
	var mid: Vector3 = ((tops[0] as Vector3) + (tops[1] as Vector3)) * 0.5 + Vector3(0.0, side * 0.5, 0.0)
	block(st, Transform3D(basis, mid), Vector3(width + side * 2.0, side, side))
	return mid - Vector3(0.0, side, 0.0)
