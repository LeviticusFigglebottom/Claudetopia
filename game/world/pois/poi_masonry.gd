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
var _unit := BoxMesh.new()
var _cyl := CylinderMesh.new()


func _init(k: PoiKit) -> void:
	kit = k
	_unit.size = Vector3.ONE
	_cyl.top_radius = 0.5
	_cyl.bottom_radius = 0.5
	_cyl.height = 1.0
	_cyl.radial_segments = 10
	_cyl.rings = 1


func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## One block: a unit box scaled to `size` at `xform` (the transform's own scale is ignored).
func block(st: SurfaceTool, xform: Transform3D, size: Vector3) -> void:
	st.append_from(_unit, 0, xform.scaled_local(size))


func rod(st: SurfaceTool, xform: Transform3D, radius: float, length: float) -> void:
	st.append_from(_cyl, 0, xform.scaled_local(Vector3(radius * 2.0, length, radius * 2.0)))


## Finishes a batch into one MeshInstance3D under the dressing. A silhouette piece is built
## in the far ring as well and drawn out to the far range; anything else is near-ring only.
func commit(st: SurfaceTool, mat: Material, node_name: String, silhouette := false) -> MeshInstance3D:
	if kit.far and not silhouette:
		return null
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
func drum(st: SurfaceTool, frame: Transform3D, r: float, height: float, broken := 0.0,
		door_yaw := NAN, collide := true, course_h := COURSE) -> void:
	var courses := int(ceil(height / course_h))
	var per := maxi(int(round(TAU * r / BLOCK)), 6)
	var sectors := 24
	var tops: Array[float] = []
	var phase := kit.rng.randf_range(0.0, TAU)
	var freq := kit.rng.randf_range(1.0, 2.2)
	for i in sectors:
		var a := TAU * float(i) / float(sectors)
		var tear := 0.5 + 0.5 * sin(a * freq + phase) + 0.25 * sin(a * 3.7 + phase * 1.7)
		tops.append(height * (1.0 - broken * clampf(tear, 0.0, 1.0)))
	for c in courses:
		var y := course_h * (float(c) + 0.5)
		var offset := 0.5 if c % 2 == 1 else 0.0
		for i in per:
			var a := TAU * (float(i) + offset) / float(per)
			var sector := int(floor(a / TAU * float(sectors))) % sectors
			if y > tops[sector]:
				continue
			if not is_nan(door_yaw) and absf(angle_difference(a, door_yaw)) < 0.7 / maxf(r, 1.0) + 0.18 and y < 2.2:
				continue
			var rr := r + kit.rng.randf_range(-0.04, 0.04)
			var local := Transform3D(Basis(Vector3.UP, a + PI * 0.5),
					Vector3(sin(a) * rr, y, cos(a) * rr))
			block(st, frame * local, Vector3(BLOCK * 0.94 * (TAU * r / BLOCK) / float(per),
					course_h * 0.94, THICK))
	if collide and not kit.far:
		var segs := 12
		for i in segs:
			var a := TAU * (float(i) + 0.5) / float(segs)
			var sector := int(floor(a / TAU * float(sectors))) % sectors
			var h := tops[sector]
			if not is_nan(door_yaw) and absf(angle_difference(a, door_yaw)) < TAU / float(segs):
				continue
			var local := Transform3D(Basis(Vector3.UP, a + PI * 0.5), Vector3(sin(a) * r, h * 0.5, cos(a) * r))
			kit.collider(Vector3(TAU * r / float(segs) * 1.02, h, THICK), frame * local)


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
	var per := maxi(int(round(length / BLOCK)), 1)
	var courses := int(ceil(height / course_h))
	var ya := kit.ground(kit.origin.x + a.x, kit.origin.z + a.y) - kit.origin.y
	var yb := kit.ground(kit.origin.x + b.x, kit.origin.z + b.y) - kit.origin.y
	var tear_from := kit.rng.randf_range(0.2, 0.8)
	var min_h := height
	for c in courses:
		var offset := 0.5 if c % 2 == 1 else 0.0
		for i in per:
			var t := (float(i) + 0.5 + offset) / float(per)
			if t > 1.0:
				continue
			var top := height * (1.0 - broken * clampf((t - tear_from) / maxf(1.0 - tear_from, 0.05), 0.0, 1.0)
					* kit.rng.randf_range(0.6, 1.2))
			var y := lerpf(ya, yb, t) + course_h * (float(c) + 0.5)
			if y - lerpf(ya, yb, t) > top:
				continue
			min_h = minf(min_h, top)
			var p := a + dir * (length * t)
			block(st, Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(p.x, y, p.y)),
					Vector3(BLOCK * 0.94 * length / (float(per) * BLOCK), course_h * 0.94, THICK))
	if collide:
		var mid := (a + b) * 0.5
		var h := maxf(min_h, course_h)
		kit.collider(Vector3(length, h, THICK),
				Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(mid.x, (ya + yb) * 0.5 + h * 0.5, mid.y)))


## A doorway: two jambs and a lintel of stone, standing on the ground at `at`, facing `yaw`.
func doorway(st: SurfaceTool, at: Vector2, yaw: float, width := 1.4, height := 2.3) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var ground := kit.ground(kit.origin.x + at.x, kit.origin.z + at.y) - kit.origin.y
	for side in [-1.0, 1.0]:
		var p := Vector3(at.x, ground + height * 0.5, at.y) + basis * Vector3(float(side) * (width * 0.5 + 0.22), 0.0, 0.0)
		block(st, Transform3D(basis, p), Vector3(0.44, height, THICK))
		kit.collider(Vector3(0.44, height, THICK), Transform3D(basis, p))
	var lintel := Vector3(at.x, ground + height + 0.2, at.y)
	block(st, Transform3D(basis, lintel), Vector3(width + 0.9, 0.4, THICK + 0.1))


# --- crossings -------------------------------------------------------------------------------

## A humped stone bridge whose deck runs from `a` to `b` (local xz), `width` across, rising
## `rise` at the middle above the straight line between its ends (which stand on the ground,
## or on `deck_y` where given). Parapets either side, an arch ring beneath, abutments at the
## ends. Collision follows the deck so it can be crossed.
func arch_bridge(st: SurfaceTool, a: Vector2, b: Vector2, width: float, rise: float,
		deck_y := NAN, parapet := true, arch := true) -> void:
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
		kit.collider(Vector3(width, deck_t, seg_len * 1.02), xf)
		if parapet:
			for side in [-1.0, 1.0]:
				var q := xf.origin + basis * Vector3(float(side) * (width * 0.5 - 0.17), deck_t * 0.5 + 0.42, 0.0)
				block(st, Transform3D(basis, q), Vector3(0.34, 0.84, seg_len * 1.02))
				kit.collider(Vector3(0.34, 0.84, seg_len * 1.02), Transform3D(basis, q))
	if arch:
		# the ring under the deck: voussoirs on an arc from one abutment to the other
		var span := length * 0.72
		var sag := maxf(rise, 0.8) + 1.6
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
		kit.collider(Vector3(width + 0.5, depth, 2.2), xf)


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
	kit.collider(Vector3(width, 0.2, length), Transform3D(basis, Vector3((a.x + b.x) * 0.5, y - 0.1, (a.y + b.y) * 0.5)))


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
		kit.collider(Vector3(width, block_depth, tread * 1.02), xf)


# --- earth, water and timber --------------------------------------------------------------------

## A dome of ground: an island, a peat hummock, a turf kiln, a drift of snow. Radius `r`,
## `height` at the centre, sitting at local height `base_y`; `power` shapes it (1 = round,
## 3 = flat-topped). Walkable when `collide`.
func mound(centre: Vector3, r: float, height: float, mat: Material, node_name: String,
		collide := true, power := 1.6, rings := 7, segments := 20, silhouette := false) -> MeshInstance3D:
	if kit.far and not silhouette:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for i in rings + 1:
		var f := float(i) / float(rings)
		var rr := r * f
		var y := height * pow(maxf(1.0 - f * f, 0.0), power * 0.5)
		var row: Array = []
		for j in segments:
			var a := TAU * float(j) / float(segments)
			var wob := 1.0 + (kit.rng.randf_range(-0.05, 0.05) if i > 0 else 0.0)
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
		kit.collider_shape(m.create_trimesh_shape(), Transform3D.IDENTITY)
	return inst


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
		node_name := "Sheet", belly := 0.6, silhouette := true) -> MeshInstance3D:
	if kit.far and not silhouette:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var basis := Basis(Vector3.UP, yaw)
	var cols := 4
	var rows := 6
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
	kit.collider(Vector3(side, height, side), xf)
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
