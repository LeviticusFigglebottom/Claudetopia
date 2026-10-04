extends RefCounted
## Briarwold's own place builders (docs/WORLD_LIFE.md). A POI def with `"builder": "<name>"` is built
## by the static function of that name here, in place of its kind's builder. Only the Briarwold
## region's author edits this file, so six regions can build at once without meeting.
##
##   static func drovers_hall(d: PoiDressing) -> void:
##       await PoiDressing.kind_builders().LAND.farmstead(d)    # its kind's, then more
##       var k := d.kit                                          # PoiKit: on_ground, prop, masonry ...
##
## The kind stays the def's `kind` (what the tests, the map and the audit call it); a builder named
## here that is missing is said in the log and the place is built as its kind.

## Brass gone brown in the Northwold's rain, still bright where hands have held it.
const BRASS := Color(0.50, 0.38, 0.19)
## The grey of cold ash that the Greyed Ring's leaves, bark and moss have all gone.
const ASH_GREY := Color(0.47, 0.47, 0.46)


# --- the Listening Horns ------------------------------------------------------------------------

## The Circle's Listeners' cold camp (camp, "cold") and, on its far side from the road, their three
## brass listening-horns as tall as a man, each on a tripod, all three turned on the Briar's
## northern gate: the one thing in the camp that is not the camp builder's, and the thing the place
## is named for. Legs and horns are one mesh, so from every side it stands on its own feet.
static func listening_horns(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().camp(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	# the northern gate, from the def's own position: the horns listen at it
	var def := ContentDB.get_or_empty(d.poi_id)
	var here: Array = def.get("position", [0, 0])
	var gate := ContentDB.get_or_empty("core:poi/northgate_stone").get("position", [float(here[0]) + 400.0, float(here[1])]) as Array
	var east := Vector2(float(gate[0]) - float(here[0]), float(gate[1]) - float(here[1]))
	east = east.normalized() if east.length() > 1.0 else Vector2(1.0, 0.0)
	var across := Vector2(-east.y, east.x)
	var brass := m.begin()
	var spots: Array = []
	for i in 3:
		# in a shallow arc across the camp's east side, the middle horn a little further out
		var c := east * (7.2 + (0.8 if i == 1 else 0.0)) + across * (float(i) - 1.0) * 3.4
		spots.append(c)
		var ground := k.on_ground(c.x, c.y).y
		var apex := Vector3(c.x, ground + 1.55, c.y)
		# the tripod: three legs from a little into the ground to the apex
		for leg in 3:
			var a := TAU * float(leg) / 3.0 + k.rng.randf_range(-0.2, 0.2) + PoiKit.yaw_of(east)
			var foot := Vector2(c.x + sin(a) * 0.75, c.y + cos(a) * 0.75)
			m.limb(brass, k.on_ground(foot.x, foot.y, -0.06), apex, 0.035)
		# the horn: a throat at the back, flaring to a bell toward the gate, tipped a little up
		var aim := Vector3(east.x, 0.12, east.y).normalized()
		var back := apex - aim * 0.9 + Vector3.UP * 0.12
		var steps := 6
		for s in steps:
			var t0 := float(s) / float(steps)
			var t1 := float(s + 1) / float(steps)
			var r := lerpf(0.05, 0.30, pow(t1, 1.8))
			m.limb(brass, back + aim * (2.1 * t0), back + aim * (2.1 * t1), r)
		# the bell's lip: a flattened ring of balls round the mouth
		var mouth := back + aim * 2.1
		var basis := Basis.looking_at(aim, Vector3.UP)
		for j in 12:
			var b := TAU * float(j) / 12.0
			var off := basis * Vector3(cos(b) * 0.42, sin(b) * 0.42, 0.0)
			m.ellipsoid(brass, mouth + off, Vector3(0.07, 0.07, 0.05), basis)
		# the ear-piece at the back, where Merel Quill puts her ear
		m.ellipsoid(brass, back - aim * 0.05, Vector3(0.09, 0.09, 0.09))
		await k.step()
	m.commit(brass, PoiKit.plain(BRASS, 0.42, 0.75), "ListeningHorns")
	for c in spots:
		var sc: Vector2 = c
		var at := k.on_ground(sc.x, sc.y)
		k.collider(Vector3(1.2, 1.9, 1.2), Transform3D(Basis(), at + Vector3.UP * 0.95), "metal")
	# where Merel Quill stands with her ear to the brass, and where the porter sits
	var mid: Vector2 = spots[1]
	var stand := mid - east * 1.9
	k.marker("the_horns", k.on_ground(stand.x, stand.y), true)
	k.marker("the_east_horn", k.on_ground(mid.x, mid.y), false)


# --- the Greyed Ring --------------------------------------------------------------------------------

## The ring of sallows rooted again (strange_tree, "ring") and the grey that has come up under it:
## the moss and the leaf-litter inside the ring gone the grey of cold ash in patches that stop at its
## edge, and a few withies standing dead-grey among them, still upright, that do not bleed when cut.
static func greyed_ring(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().strange_tree(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var litter := m.begin()
	var reach := minf(d.pad_radius * 0.55, 13.0)
	var patches := 26
	for i in patches:
		# denser toward the middle, and none past the ring's edge
		var a := k.rng.randf_range(0.0, TAU)
		var r := reach * sqrt(k.rng.randf_range(0.0, 1.0))
		var c := Vector2(sin(a) * r, cos(a) * r)
		var size := k.rng.randf_range(0.7, 1.3)
		# tilted to the ground under it, so it lies on the slope rather than cutting into it
		var hx := k.on_ground(c.x + size, c.y).y - k.on_ground(c.x - size, c.y).y
		var hz := k.on_ground(c.x, c.y + size).y - k.on_ground(c.x, c.y - size).y
		var normal := Vector3(-hx / (2.0 * size), 1.0, -hz / (2.0 * size)).normalized()
		var x := normal.cross(Vector3.BACK).normalized()
		var basis := Basis(x, normal, x.cross(normal).normalized()) * Basis(Vector3.UP, k.rng.randf() * TAU)
		m.ellipsoid(litter, k.on_ground(c.x, c.y, 0.025), Vector3(size, 0.04, size * k.rng.randf_range(0.6, 1.0)), basis)
	await k.step()
	m.commit(litter, PoiKit.plain(ASH_GREY.darkened(0.08), 0.95, 0.0), "GreyMoss")
	# the dead-grey withies: straight rods from the ground, a hand into it, a few crooked
	var withies := m.begin()
	for i in 14:
		var a := k.rng.randf_range(0.0, TAU)
		var r := reach * k.rng.randf_range(0.25, 0.9)
		var foot := Vector2(sin(a) * r, cos(a) * r)
		var base := k.on_ground(foot.x, foot.y, -0.12)
		var lean := Vector3(k.rng.randf_range(-0.1, 0.1), 1.0, k.rng.randf_range(-0.1, 0.1)).normalized()
		var tip := base + lean * k.rng.randf_range(1.4, 2.6)
		m.limb(withies, base, tip, k.rng.randf_range(0.018, 0.03))
	await k.step()
	m.commit(withies, PoiKit.plain(ASH_GREY, 0.9, 0.0), "GreyWithies")
	k.marker("the_grey_ring", k.on_ground(0.0, 0.0), false)


# --- shared hands (world life, phase 2) -------------------------------------------------------------

const LAND := preload("res://world/pois/poi_builders_land.gd")
const SITES := preload("res://world/sites/site_exterior.gd")
## Wood that has been dead twenty years in the rain: silver-grey on top, brown under.
const DEADWOOD := {"base": "#6f695e", "accent": "#4b453c"}
## A living root's bark, dark and wet.
const ROOTBARK := {"base": "#3d3226", "accent": "#251d15"}
## Old antler, gone the yellow-grey of bone left out.
const ANTLER := Color(0.66, 0.6, 0.5)
## Earth torn up with the roots: dark, wet, with stones in it.
const TORN_EARTH := Color(0.27, 0.22, 0.16)


static func _builders() -> GDScript:
	return PoiDressing.kind_builders()


## The unit direction the place faces: toward the nearest road where one is near, else downhill,
## else along the grain.
static func _facing(k: PoiKit) -> Vector2:
	var f := k.road_direction(90.0)
	if f == Vector2.ZERO:
		f = k.downhill()
	if f == Vector2.ZERO:
		f = k.grain()
	return f.normalized() if f != Vector2.ZERO else Vector2(0.0, 1.0)


## The Charter Delf's tips (PoiMasonry.spoil_heap): broken granite, grey fresh, the iron's ochre and a
## darker grey run down it, the oldest greening from its foot.
const GRANITE_TINTS := {"fresh": Color(1.0, 1.0, 1.0), "streak_a": Color(0.74, 0.75, 0.79),
		"streak_b": Color(1.12, 1.0, 0.82), "grass": Color(0.62, 1.0, 0.52)}
## Their ground (PoiKit.painted's beaten earth): broken granite, mid grey.
const GRANITE_SPOIL := {"base": "#5f5f5a", "accent": "#4a4a46", "grout": "#26261f", "unit": 0.35}


## The ground's own texture, darkened: the earth a root plate tore up, a grave's turned soil.
static func _earth_look(k: PoiKit, slot := "mud", value := 0.42) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var path := "res://assets/textures/terrain/%s_albedo_height.png" % slot
	if ResourceLoader.exists(path):
		mat.albedo_texture = load(path)
	mat.albedo_color = Color(value, value * 0.92, value * 0.82)
	mat.roughness = 0.97
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / 2.4
	return mat


## A chest, crate or barrel that opens: the region's prop for the look and a WorldContainer for the
## loot, its id the place's own so what was taken stays taken.
static func _container(d: PoiDressing, key: String, at: Vector3, yaw: float, table: String, shown: String,
		prop_kind := "chest") -> void:
	var k := d.kit
	if k.far:
		return
	var path := k.prop(prop_kind)
	if path != "":
		k.place(path, at, yaw, 1.0, false)
	var box := WorldContainer.new()
	box.name = "Container_" + key
	box.container_id = "%s/%s" % [d.poi_id, key]
	box.loot_table = table
	box.display_name = shown
	var cs := CollisionShape3D.new()
	var form := BoxShape3D.new()
	form.size = Vector3(1.0, 0.8, 0.7)
	cs.shape = form
	cs.position.y = 0.4
	box.add_child(cs)
	box.position = at
	box.rotation.y = yaw
	d.add_child(box)
	k.collider(Vector3(1.0, 0.8, 0.7), Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0.0, 0.4, 0.0)), "wood")


## Many of one prop, in one MultiMesh: `spots` are [Vector3 local, yaw, scale] rows.
static func _row(k: PoiKit, path: String, spots: Array, collide := false) -> void:
	if path == "" or spots.is_empty():
		return
	var xfs: Array = []
	for s in spots:
		xfs.append(PoiKit.transform_at(s[0], float(s[1]), float(s[2]) if s.size() > 2 else 1.0))
	await k.step()
	k.scatter(path, xfs, collide, false, false)


## A tapering log from `a` to `b` (local), radius `ra` at `a` and `rb` at `b`, its bark in ridges
## along it (a bole is fluted, not a pipe), into `st`. `open_end` leaves the `b` end without a cap
## (a broken end is drawn by its splinters); the `a` end is always capped. Smooth-shaded: rings
## share their vertices' positions, so SurfaceTool's normals run round the bole.
static func _bole(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, rng: RandomNumberGenerator,
		segs := 20, rings := 14, open_end := false) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.05:
		return
	var y := axis / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	var phase := rng.randf_range(0.0, TAU)
	var ridge := rng.randi_range(7, 11)
	var pts: Array = []
	for i in rings + 1:
		var t := float(i) / float(rings)
		var r := lerpf(ra, rb, t)
		# a swell at the butt, as a bole flares into its roots
		r *= 1.0 + 0.22 * pow(maxf(0.0, 1.0 - t * 6.0), 2.0)
		var row: Array = []
		for j in segs:
			var ang := TAU * float(j) / float(segs)
			var bump := 1.0 + 0.07 * sin(ang * float(ridge) + phase + t * 3.0) + 0.04 * sin(ang * 3.0 - phase * 2.0 + t * 7.0)
			row.append(a + y * (length * t) + (x * cos(ang) + z * sin(ang)) * r * bump)
		pts.append(row)
	for i in rings:
		for j in segs:
			var j1 := (j + 1) % segs
			var p00: Vector3 = pts[i][j]
			var p01: Vector3 = pts[i][j1]
			var p10: Vector3 = pts[i + 1][j]
			var p11: Vector3 = pts[i + 1][j1]
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p11)
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p01)
	# the butt's cap
	for j in segs:
		var j1 := (j + 1) % segs
		st.add_vertex(a)
		st.add_vertex(pts[0][j1])
		st.add_vertex(pts[0][j])
	if not open_end:
		for j in segs:
			var j1 := (j + 1) % segs
			st.add_vertex(b)
			st.add_vertex(pts[rings][j])
			st.add_vertex(pts[rings][j1])


## The Greatwood oak's own bark, as the forge painted it for the giant oaks (albedo, normal, ORM),
## for a bole drawn by _bark_bole: its UVs run the furrows along the log. Its vertex colours darken
## it and lay the moss on (green on the upper side), so `tint` is the bark's colour as a multiplier.
const OAK_BARK := "res://assets/models/trees/_species/briarwold_giant_oak/briarwold_giant_oak_bark_%s.png"


static func _bark_look(tint := Color(0.64, 0.6, 0.57)) -> BaseMaterial3D:
	var mat := ORMMaterial3D.new()
	if ResourceLoader.exists(OAK_BARK % "albedo"):
		mat.albedo_texture = load(OAK_BARK % "albedo")
		mat.normal_enabled = true
		mat.normal_texture = load(OAK_BARK % "normal")
		mat.normal_scale = 1.4
		mat.orm_texture = load(OAK_BARK % "orm")
	else:
		tint *= Color(0.36, 0.31, 0.25)
	mat.albedo_color = tint
	mat.vertex_color_use_as_albedo = true
	return mat


## Wood's colours as multipliers of the bark (vertex colours, _bark_look): the bark, wet and dark
## where it lies near the ground; moss on its upper side; the pale wood of a break.
const BARK_TINT := Color(1.0, 1.0, 1.0)
const BARK_WET := Color(0.66, 0.64, 0.62)
const BARK_MOSS := Color(0.62, 1.18, 0.34)
const BARK_HEART := Color(1.6, 1.4, 1.1)


## A log like _bole, but barked (UVs for _bark_look, the oak's furrows along it, `tile` m a repeat
## round it) and grown, not turned: bowed `bend` m sideways along its length, its section a little
## flattened, swollen in `burrs` burls, and `moss` (0-1) of moss in vertex colour on its upper side.
## `broken` ends it in a jagged break of pale heartwood, not a cap. Into `st`, with colours and UVs
## on every vertex (so nothing without them, a PoiMasonry.limb, may go in the same SurfaceTool).
static func _bark_bole(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, rng: RandomNumberGenerator,
		segs := 20, rings := 14, broken := false, moss := 0.6, tile := 1.6, bend := 0.0, burrs := 0) -> void:
	var axis := b - a
	var length := axis.length()
	if length < 0.05:
		return
	var y := axis / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	var phase := rng.randf_range(0.0, TAU)
	var phase2 := rng.randf_range(0.0, TAU)
	var ridge := rng.randi_range(7, 11)
	var lumps: Array = []
	for n in burrs:
		lumps.append(Vector4(rng.randf_range(0.12, 0.92), rng.randf_range(0.0, TAU), rng.randf_range(0.05, 0.12),
				rng.randf_range(0.35, 0.7)))
	var around := maxf(1.0, roundf(TAU * (ra + rb) * 0.5 / tile))
	var pts: Array = []
	var cols: Array = []
	for i in rings + 1:
		var t := float(i) / float(rings)
		# the taper eases off along it, and the butt flares into its roots
		var r := lerpf(ra, rb, t) * (1.0 + 0.22 * pow(maxf(0.0, 1.0 - t * 6.0), 2.0))
		var centre := a + y * (length * t) + x * (bend * sin(PI * t))
		var row: Array = []
		var crow: Array = []
		for j in segs:
			var ang := TAU * float(j) / float(segs)
			var bump := 1.0 + 0.07 * sin(ang * float(ridge) + phase + t * 3.0) + 0.04 * sin(ang * 3.0 - phase * 2.0 + t * 7.0)
			bump += 0.035 * sin(ang * 2.0 + phase2 + t * 4.3) * sin(t * 9.0 + phase)
			for l: Vector4 in lumps:
				var dt := (t - l.x) * length / (ra * l.w * 2.0)
				var da := wrapf(ang - l.y, -PI, PI) / l.w
				bump += l.z * exp(-(dt * dt + da * da) * 2.2)
			var out := x * cos(ang) * 1.05 + z * sin(ang) * 0.96
			row.append(centre + out * r * bump)
			# moss on the upper side, in drifts; the underside dark and wet
			var up := (x * cos(ang) + z * sin(ang)).dot(Vector3.UP)
			var drift := 0.5 * sin(ang * 3.0 + t * 11.0 + phase2) * sin(t * 17.0 - ang * 2.0 + phase)
			var c := BARK_TINT.lerp(BARK_WET, clampf(-up * 1.4 - 0.2, 0.0, 1.0))
			c = c.lerp(BARK_MOSS, moss * smoothstep(0.05, 0.55, up + drift * 0.6))
			c *= rng.randf_range(0.92, 1.05)
			c.a = 1.0
			crow.append(c)
		pts.append(row)
		cols.append(crow)
	# a repeat along the log half again its repeat round it: the oak's plates are already long in
	# the texture, and at twice they ran into streaks, a planed board's grain and not a bark
	var vlen := tile * 1.5
	for i in rings:
		for j in segs:
			var j1 := (j + 1) % segs
			var u0 := around * float(j) / float(segs)
			var u1 := around * float(j + 1) / float(segs)
			var v0 := length * float(i) / float(rings) / vlen
			var v1 := length * float(i + 1) / float(rings) / vlen
			for q: Array in [[i, j, u0, v0], [i + 1, j, u0, v1], [i + 1, j1, u1, v1],
					[i, j, u0, v0], [i + 1, j1, u1, v1], [i, j1, u1, v0]]:
				st.set_color(cols[q[0]][q[1]])
				st.set_uv(Vector2(q[2], q[3]))
				st.add_vertex(pts[q[0]][q[1]])
	# the butt's cap
	st.set_color(BARK_WET)
	for j in segs:
		var j1 := (j + 1) % segs
		for v in [a, pts[0][j1], pts[0][j]]:
			st.set_uv(Vector2((v as Vector3).dot(x), (v as Vector3).dot(z)) / vlen)
			st.add_vertex(v)
	var ring_end: Array = pts[rings]
	var c_end := a + axis
	if not broken:
		for j in segs:
			var j1 := (j + 1) % segs
			for v in [c_end, ring_end[j], ring_end[j1]]:
				st.set_uv(Vector2((v as Vector3).dot(x), (v as Vector3).dot(z)) / vlen)
				# (a stub's inner piece ends inside the next: a pale sawn disc showed there as a peg's end)
				st.set_color(BARK_WET)
				st.add_vertex(v)
		return
	# a break: the heartwood torn out in a jagged fan, splinters standing off the rim, the middle
	# drawn out furthest (wood tears along the grain)
	# Its UVs as the sides' (round it, and along it by how far out each point is), so the grain runs
	# along the torn fibres: projected across the log, the texture smeared into zig-zags.
	var mid: Array = []
	var mid_v: Array = []
	for j in segs:
		var ang := TAU * float(j) / float(segs)
		var reach := rb * (0.15 + rng.randf_range(0.0, 0.9) * (1.0 if j % 2 == 0 else 0.35))
		var rr := rb * rng.randf_range(0.45, 0.7)
		mid.append(c_end + (x * cos(ang) + z * sin(ang)) * rr + y * reach)
		mid_v.append((length + reach) / vlen)
	var spike_reach := rb * rng.randf_range(0.5, 0.9)
	var spike := c_end + y * spike_reach + x * rb * rng.randf_range(-0.2, 0.2)
	for j in segs:
		var j1 := (j + 1) % segs
		var u0 := around * float(j) / float(segs)
		var u1 := around * float(j + 1) / float(segs)
		var re0 := [ring_end[j], Vector2(u0, length / vlen), BARK_TINT]
		var re1 := [ring_end[j1], Vector2(u1, length / vlen), BARK_TINT]
		var m0 := [mid[j], Vector2(u0, mid_v[j]), BARK_HEART]
		var m1 := [mid[j1], Vector2(u1, mid_v[j1]), BARK_HEART]
		var sp := [spike, Vector2((u0 + u1) * 0.5, (length + spike_reach) / vlen), BARK_HEART]
		for tri: Array in [[re0, m1, m0], [re0, re1, m1], [m0, m1, sp]]:
			for vtx: Array in tri:
				st.set_uv(vtx[1])
				st.set_color(vtx[2])
				st.add_vertex(vtx[0])


## A broken branch's stub off a bole at `root_at` (local), out along `dir` (unit) `long` m, `r`
## thick where it leaves the bole: a short barked log from inside the bole, bending a little up, its
## end snapped (_bark_bole's break). Into `st`, as _bark_bole.
static func _stub(st: SurfaceTool, root_at: Vector3, dir: Vector3, long: float, r: float,
		rng: RandomNumberGenerator, moss := 0.5) -> void:
	var a := root_at - dir * r * 1.2
	var mid := root_at + dir * long * 0.55
	var tip := mid + (dir + Vector3.UP * rng.randf_range(0.05, 0.3)).normalized() * long * 0.45
	_bark_bole(st, a, mid, r * 1.15, r * 0.82, rng, 10, 3, false, moss, 0.9)
	_bark_bole(st, mid - (mid - a).normalized() * r * 0.3, tip, r * 0.84, r * 0.6, rng, 10, 2, true, moss, 0.9)


## A pair of antlers rising from `base` (local), the head facing `facing` (unit, horizontal), each
## beam sweeping out, back and up with its tines rising off its front: a hart's of `span` metres
## from tip to tip. Bone-coloured capsules into `st`.
static func _antlers(m: PoiMasonry, st: SurfaceTool, base: Vector3, facing: Vector3, span: float,
		rng: RandomNumberGenerator, tines := 5) -> void:
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	if f.length() < 0.1:
		f = Vector3.FORWARD
	var side := f.cross(Vector3.UP).normalized()
	var s := span / 2.4
	for sgn in [-1.0, 1.0]:
		var sd := side * float(sgn)
		var p := base + sd * 0.12 * s
		# the beam: five pieces, out, back and up, curving in at the top
		var dirs := [sd * 0.55 + Vector3.UP * 0.6 - f * 0.1, sd * 0.45 + Vector3.UP * 0.75 - f * 0.35,
				sd * 0.3 + Vector3.UP * 0.8 - f * 0.4, sd * 0.05 + Vector3.UP * 0.85 - f * 0.25,
				-sd * 0.15 + Vector3.UP * 0.7 + f * 0.1]
		var r := 0.075 * s
		for i in dirs.size():
			var dv: Vector3 = dirs[i]
			var q: Vector3 = p + dv.normalized() * (0.42 * s) * (1.0 - 0.08 * float(i))
			m.limb(st, p, q, r)
			# a tine off the front of each joint but the last, the brow tine longest
			if i < tines and i < dirs.size() - 1:
				var tl := (0.45 if i == 0 else 0.34 - 0.03 * float(i)) * s
				var td := (f * 0.8 + Vector3.UP * (0.25 + 0.25 * float(i)) + sd * rng.randf_range(-0.1, 0.25)).normalized()
				m.limb(st, q, q + td * tl, r * 0.62)
			p = q
			r *= 0.86


# --- the Windthrow ----------------------------------------------------------------------------------

## The Grandfather's brother, thrown by the Long Wind of 1019: its root plate stood up out of the
## Greatwood as a wall of earth, stones and roots twenty-odd metres across, and the trunk behind it
## lying down the shelf to where its crown broke off. Under the plate, where the taproot tore out,
## a dark mouth goes down into the root-dark under the Wold (the site's door). The trunk is a way up:
## a broken limb leans on its far end, and its top climbs to the plate's back, where whatever ravens
## or men hid things hid them. All of the plate and the trunk is silhouette: it stands over the
## canopy from the Hollow's ring street.
static func windthrow(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var def := ContentDB.get_or_empty(d.poi_id)
	var site: Dictionary = def.get("site", {})
	# the plate faces the way the land falls (its face over the shelf's lip), the trunk lies back
	# along the shelf behind it
	var out := Vector2.ZERO
	if site.has("facing_deg"):
		var fb := deg_to_rad(float(site["facing_deg"]))
		out = Vector2(sin(fb), cos(fb))
	if out == Vector2.ZERO:
		out = k.downhill()
	if out == Vector2.ZERO:
		out = _facing(k)
	out = out.normalized()
	var into := -out
	var across := Vector2(into.y, -into.x)
	var yaw_in := PoiKit.yaw_of(into)
	var basis := Basis(Vector3.UP, yaw_in)   # +z into the plate, x across it

	# the plate: its foot on a line `hinge` m in from the middle, standing leaned back 10 degrees
	var hinge := into * 2.0
	var g_h := k.on_ground(hinge.x, hinge.y).y
	var pr := 12.5
	var lean := deg_to_rad(10.0)
	var plate_basis := basis * Basis(Vector3.RIGHT, lean)
	var plate_c := Vector3(hinge.x, g_h, hinge.y) + plate_basis * Vector3(0.0, pr - 1.4, 0.0)
	var thick := 2.4
	# the mouth in the plate's foot: an arch where the taproot came out
	var mouth_w := 4.2
	var mouth_h := 4.0
	var plate := m.begin()
	var rings := 14
	var segs := 44
	var outline: Array = []
	for j in segs:
		outline.append(1.0 + 0.11 * sin(float(j) * 0.9 + 1.3) + 0.08 * sin(float(j) * 2.3 + 0.4) + k.rng.randf_range(-0.09, 0.09))
	var grid: Array = []
	for i in rings + 1:
		var row: Array = []
		for j in segs:
			var ang := TAU * float(j) / float(segs)
			var rr := pr * float(i) / float(rings) * float(outline[j])
			# wider than it is tall: a root plate is a bowl turned on its edge, not a wheel
			row.append(Vector2(cos(ang) * rr * 1.14, sin(ang) * rr * 0.93))
		grid.append(row)
	var foot_y := -(pr - 1.4)   # the plate's foot in its own frame (y up the plate)
	for side in [-1.0, 1.0]:
		var zf := float(side) * thick * 0.5
		for i in rings:
			for j in segs:
				var j1 := (j + 1) % segs
				var q00: Vector2 = grid[i][j]
				var q01: Vector2 = grid[i][j1]
				var q10: Vector2 = grid[i + 1][j]
				var q11: Vector2 = grid[i + 1][j1]
				var mid := (q00 + q11) * 0.5
				# the mouth: left open
				if absf(mid.x) < mouth_w * 0.5 and mid.y < foot_y + mouth_h:
					continue
				# a face bulging out of the plate toward its middle: the bowl of the roots (by ring, so
				# neighbouring rings meet: a bulge a quad at a time stepped the face into terraces)
				var z0 := zf + float(side) * (1.0 - float(i) / float(rings)) * 1.6
				var z1 := zf + float(side) * (1.0 - float(i + 1) / float(rings)) * 1.6
				var quad := [Vector3(q00.x, q00.y, z0), Vector3(q01.x, q01.y, z0), Vector3(q10.x, q10.y, z1), Vector3(q11.x, q11.y, z1)]
				var wq: Array = []
				for v in quad:
					var vv: Vector3 = v
					wq.append(plate_c + plate_basis * Vector3(vv.x, vv.y, vv.z))
				if side < 0.0:
					for idx in [0, 2, 3, 0, 3, 1]:
						plate.add_vertex(wq[int(idx)])
				else:
					for idx in [0, 3, 2, 0, 1, 3]:
						plate.add_vertex(wq[int(idx)])
	# the rim between the faces
	for j in segs:
		var j1 := (j + 1) % segs
		var q0: Vector2 = grid[rings][j]
		var q1: Vector2 = grid[rings][j1]
		var a0 := plate_c + plate_basis * Vector3(q0.x, q0.y, -thick * 0.5)
		var a1 := plate_c + plate_basis * Vector3(q1.x, q1.y, -thick * 0.5)
		var b0 := plate_c + plate_basis * Vector3(q0.x, q0.y, thick * 0.5)
		var b1 := plate_c + plate_basis * Vector3(q1.x, q1.y, thick * 0.5)
		for v in [a0, b0, b1, a0, b1, a1]:
			plate.add_vertex(v)
	await k.step()
	m.commit(plate, _earth_look(k, "mud", 0.62), "RootPlate", true)
	# what it stands on: boxes stepped up its height, so nothing walks through it
	if not k.far:
		for i in 6:
			var t := (float(i) + 0.5) / 6.0
			var yy := foot_y + t * pr * 2.0 - 0.5
			var half_w := sqrt(maxf(pr * pr - (yy) * (yy), 1.0))
			var c := plate_c + plate_basis * Vector3(0.0, yy, 0.0)
			if yy < foot_y + mouth_h:
				# beside the mouth only
				for s in [-1.0, 1.0]:
					var w := half_w - mouth_w * 0.5
					var cc := plate_c + plate_basis * Vector3(float(s) * (mouth_w * 0.5 + w * 0.5), yy, 0.0)
					k.collider(Vector3(w, pr * 2.0 / 6.0, thick + 1.0), Transform3D(plate_basis, cc), "dirt")
			else:
				k.collider(Vector3(half_w * 2.0, pr * 2.0 / 6.0, thick + 1.0), Transform3D(plate_basis, c), "dirt")
	# the roots. Out of the rim, the thick ones go out, bend back and droop under their own weight;
	# over the face the great roots wander out from the bowl the bole stood in, forking; the fine
	# ones hang off the face in fringes. A first try ran them straight, and the plate read as a
	# wheel with spokes, or an urchin.
	var roots := m.begin()
	var face_z := -thick * 0.5
	var wander := func(st: SurfaceTool, from: Vector3, heading: Vector3, reach: float, r: float, droop: float, pieces: int) -> void:
		var p := from
		var h := heading.normalized()
		var rr := r
		for i in pieces:
			var bend := Vector3(k.rng.randf_range(-0.35, 0.35), k.rng.randf_range(-0.25, 0.25), k.rng.randf_range(-0.3, 0.3))
			h = (h + bend + Vector3.DOWN * droop * float(i) / float(pieces)).normalized()
			var q := p + h * (reach / float(pieces))
			m.limb(st, p, q, rr)
			if i == 1 and rr > 0.12 and k.rng.randf() < 0.6:
				# a fork
				var fh := (h + Vector3(k.rng.randf_range(-0.8, 0.8), k.rng.randf_range(-0.4, 0.2), 0.0)).normalized()
				m.limb(st, q, q + fh * reach * 0.3, rr * 0.55)
			p = q
			rr *= 0.78
	for j in 40:
		var ang := TAU * (float(j) + k.rng.randf_range(-0.4, 0.4)) / 40.0
		var dir := Vector2(cos(ang) * 1.14, sin(ang) * 0.93)
		if dir.y * pr < foot_y + 2.0:
			continue
		var start := plate_c + plate_basis * Vector3(dir.x * pr * 0.85, dir.y * pr * 0.85, k.rng.randf_range(-0.8, 0.8))
		var out_dir := plate_basis * Vector3(dir.x, dir.y, k.rng.randf_range(0.0, 0.6))
		var r := k.rng.randf_range(0.08, 0.36) if j % 4 != 0 else k.rng.randf_range(0.35, 0.55)
		wander.call(roots, start, out_dir, k.rng.randf_range(2.5, 6.5) * (1.6 if r > 0.3 else 1.0), r, 0.9, 4)
	for j in 14:
		var ang := k.rng.randf_range(0.0, TAU)
		var dir := Vector2(cos(ang), sin(ang))
		if dir.y < -0.6:
			continue
		var a := plate_c + plate_basis * Vector3(dir.x * 1.2, dir.y * 1.2, face_z - 1.6)
		var heading := plate_basis * Vector3(dir.x, dir.y, 0.12)
		wander.call(roots, a, heading, pr * k.rng.randf_range(0.7, 1.05), k.rng.randf_range(0.45, 0.75), 0.15, 5)
	# the bowl the bole stood in: a knot of root-stumps at the face's middle
	for j in 7:
		var a := plate_c + plate_basis * Vector3(k.rng.randf_range(-1.5, 1.5), k.rng.randf_range(-1.0, 2.0), face_z - 1.8)
		m.limb(roots, a, a + plate_basis * Vector3(k.rng.randf_range(-1.0, 1.0), k.rng.randf_range(-1.0, 1.0), -k.rng.randf_range(0.8, 2.0)), k.rng.randf_range(0.4, 0.7))
	# two roots arching down over the mouth either side, its frame
	for s in [-1.0, 1.0]:
		var top := plate_c + plate_basis * Vector3(float(s) * 1.0, foot_y + mouth_h + 1.6, face_z - 0.6)
		var knee := plate_c + plate_basis * Vector3(float(s) * (mouth_w * 0.5 + 0.4), foot_y + mouth_h * 0.6, face_z - 1.0)
		var foot := Vector3(hinge.x, g_h - 0.3, hinge.y) + basis * Vector3(float(s) * (mouth_w * 0.5 + 1.2), 0.0, -1.6)
		m.limb(roots, top, knee, 0.5)
		m.limb(roots, knee, foot, 0.42)
	# the hair-roots hanging off the face in fringes, and the mouth's curtain
	for j in 50:
		var px := k.rng.randf_range(-pr, pr)
		var py := k.rng.randf_range(foot_y + mouth_h * 0.6, pr * 0.85)
		if Vector2(px / 1.14, py / 0.93).length() > pr * 0.92:
			continue
		var a := plate_c + plate_basis * Vector3(px, py, face_z - 0.5 - k.rng.randf_range(0.0, 0.6))
		var b := a + Vector3(k.rng.randf_range(-0.25, 0.25), -k.rng.randf_range(1.0, 3.2), 0.0) - Vector3(into.x, 0.0, into.y) * 0.25
		m.limb(roots, a, b, k.rng.randf_range(0.025, 0.06))
	m.commit(roots, PoiKit.painted(3, ROOTBARK, 0.4), "Roots", true)
	# clods and turves on the face, and the turf of the old forest floor still on the plate's top edge,
	# ferns and grass growing up out of it into the air
	var clods := m.begin()
	for j in 30:
		var px := k.rng.randf_range(-pr, pr)
		var py := k.rng.randf_range(foot_y + mouth_h + 0.5, pr * 0.8)
		if Vector2(px / 1.14, py / 0.93).length() > pr * 0.9:
			continue
		var c := plate_c + plate_basis * Vector3(px, py, -thick * 0.5 - 0.2)
		m.ellipsoid(clods, c, Vector3(k.rng.randf_range(0.5, 1.4), k.rng.randf_range(0.4, 1.0), k.rng.randf_range(0.4, 0.9)), plate_basis * Basis(Vector3.BACK, k.rng.randf() * TAU))
	await k.step()
	m.commit(clods, _earth_look(k, "forest_floor", 0.55), "Clods")
	if not k.far:
		var tops: Array = []
		var hang: Array = []
		for j in 26:
			var ang := k.rng.randf_range(0.2, PI - 0.2)
			var w := plate_c + plate_basis * Vector3(cos(ang) * pr * 1.06, sin(ang) * pr * 0.88, k.rng.randf_range(-0.5, 0.5))
			tops.append([w - Vector3.UP * 0.3, k.rng.randf() * TAU, k.rng.randf_range(0.8, 1.4)])
			if j % 2 == 0:
				hang.append([w - Vector3.UP * 0.6 - Vector3(into.x, 0.0, into.y) * (thick * 0.5 + 0.3), PoiKit.yaw_of(out), k.rng.randf_range(1.0, 1.6)])
		await _row(k, k.flora("fern"), tops)
		await _row(k, k.flora("hanging_moss"), hang)
	# the trunk: from behind the plate's middle, lifted with it, down the shelf to its broken end
	var butt := plate_c + Vector3(into.x, 0.0, into.y) * (thick * 0.5 + 0.8) + Vector3.DOWN * 1.2
	var length := 36.0
	var tip2 := Vector2(butt.x, butt.z) + into * length
	var r0 := 3.5
	var r1 := 2.3
	# how far it bows sideways at its middle (_bark_bole): an oak's bole is not a turned beam
	var bow := 0.7
	var tip := Vector3(tip2.x, k.on_ground(tip2.x, tip2.y).y + r1 * 0.75, tip2.y)
	# lie on the ground where it rises under the line: the bole rests, it does not cut the hill
	for t in [0.3, 0.5, 0.7, 0.9]:
		var q := Vector2(butt.x, butt.z).lerp(tip2, float(t))
		var g := k.on_ground(q.x, q.y).y
		var line_y := lerpf(butt.y, tip.y, float(t))
		var r := lerpf(r0, r1, float(t))
		if line_y - r < g - r * 0.25:
			var need := g - r * 0.25 + r - line_y
			tip.y += need / float(t)
	# the bole in the Greatwood oak's own bark, tapering, bowed, burred, mossed along its top (a
	# smooth pale bole with peg stubs read from the east as a beam, not a tree). The bark repeats every
	# 1.2 m round it: at 2.2 m, seen close and in the sun, its plates were 0.4 m by 1.5 m, smeared
	# into pale streaks, a weathered plank rather than an oak's furrows.
	var bole := m.begin()
	_bark_bole(bole, butt, tip, r0, r1, k.rng, 30, 30, true, 0.8, 1.2, bow, 6)
	var axis := (tip - butt).normalized()
	var ax := axis.cross(Vector3.UP).normalized()
	var az := ax.cross(axis).normalized()
	# splinters standing out of the break, torn along the grain
	for j in 10:
		var ang := TAU * float(j) / 10.0 + k.rng.randf_range(-0.2, 0.2)
		var radial := ax * cos(ang) + az * sin(ang)
		var at := tip + radial * r1 * k.rng.randf_range(0.55, 0.9)
		var reach := k.rng.randf_range(0.8, 3.2)
		var rr := k.rng.randf_range(0.12, 0.3)
		_bark_bole(bole, at - axis * 0.5, at + axis * reach + radial * 0.3, rr, rr * 0.12, k.rng, 5, 1, false, 0.0, 0.6)
	# limbs: broken stubs along its flanks (none straight up: the top is the way to the hoard), and
	# one great limb still reaching up, snapped
	for j in 9:
		var t := k.rng.randf_range(0.3, 0.95)
		var at := butt.lerp(tip, t) + ax * bow * sin(PI * t)
		var s := -1.0 if j % 2 == 0 else 1.0
		var r := lerpf(r0, r1, t)
		var up_ang := k.rng.randf_range(0.2, 1.0)
		var side := ax * float(s) * cos(up_ang) + az * sin(up_ang)
		var dir := (side + axis * k.rng.randf_range(0.1, 0.6)).normalized()
		var root_at := at + side * r * 0.9
		if j == 3:
			_bark_bole(bole, root_at - dir * 1.0, root_at + dir * 11.0, 1.0, 0.45, k.rng, 14, 8, true, 0.6, 1.2, 0.4)
		else:
			_stub(bole, root_at, dir, k.rng.randf_range(1.8, 4.0), k.rng.randf_range(0.4, 0.85), k.rng)
	await k.step()
	m.commit(bole, _bark_look(), "Bole", true)
	if k.far:
		return
	# the bole underfoot: capsules along it, so it is walked on
	for i in 8:
		var t0 := float(i) / 8.0
		var t1 := float(i + 1) / 8.0
		var a := butt.lerp(tip, t0)
		var b := butt.lerp(tip, t1)
		var cap := CapsuleShape3D.new()
		cap.radius = lerpf(r0, r1, (t0 + t1) * 0.5) * 0.97
		cap.height = a.distance_to(b) + cap.radius * 2.0
		var yv := (b - a).normalized()
		var xv := yv.cross(Vector3.UP).normalized()
		var zv := xv.cross(yv).normalized()
		k.collider_shape(cap, Transform3D(Basis(xv, yv, zv), (a + b) * 0.5), "wood")
	# the crown's limbs, broken off and lying beyond the end, one leaned on the bole: the way up
	var limbs := m.begin()
	var lean_foot := tip2 + into * 1.5 + across * 8.5
	var lean_top := tip + Vector3.UP * (r1 * 0.85) - axis * 2.0
	var lf := k.on_ground(lean_foot.x, lean_foot.y, 0.35)
	_bark_bole(limbs, lf, lean_top, 0.8, 0.62, k.rng, 12, 8, false, 0.5, 1.0, 0.25)
	var lcap := CapsuleShape3D.new()
	lcap.radius = 0.75
	lcap.height = lf.distance_to(lean_top) + 1.5
	var ly := (lean_top - lf).normalized()
	var lx := ly.cross(Vector3.UP).normalized()
	k.collider_shape(lcap, Transform3D(Basis(lx, ly, lx.cross(ly).normalized()), (lf + lean_top) * 0.5), "wood")
	for j in 3:
		var sj := -1.0 if j % 2 == 0 else 1.0
		var p0 := tip2 + into * k.rng.randf_range(1.0, 4.0) + across * sj * k.rng.randf_range(2.0, 5.0)
		var dirj := into.rotated(sj * k.rng.randf_range(0.7, 1.4))
		var p1 := p0 + dirj * k.rng.randf_range(5.0, 8.0)
		var rr := k.rng.randf_range(0.45, 0.8)
		var a := k.on_ground(p0.x, p0.y, rr * 0.7)
		var b := k.on_ground(p1.x, p1.y, rr * 0.5)
		_bark_bole(limbs, a, b, rr * 1.05, rr * 0.75, k.rng, 10, 6, true, 0.6, 1.0, rr * 0.4)
		k.collider(Vector3(rr * 1.8, rr * 1.6, a.distance_to(b)), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(dirj)), (a + b) * 0.5), "wood")
	await k.step()
	m.commit(limbs, _bark_look(), "CrownLimbs")
	# the mouth: a black throat a few paces into the bank under the plate, and the door at its back
	var throat := m.begin()
	var mouth_at := Vector3(hinge.x, g_h, hinge.y)
	for z in [-1.0, 0.6, 2.2, 3.8]:
		for s in [-1.0, 1.0]:
			var w := Transform3D(basis, mouth_at + basis * Vector3(float(s) * (mouth_w * 0.5 + 0.2), mouth_h * 0.5 - 0.3, float(z)))
			m.block(throat, w, Vector3(0.6, mouth_h + 0.6, 1.6))
			k.collider(Vector3(0.6, mouth_h + 0.6, 1.6), w, "stone")
		m.block(throat, Transform3D(basis, mouth_at + basis * Vector3(0.0, mouth_h - 0.1, float(z))), Vector3(mouth_w + 1.0, 0.6, 1.6))
	m.block(throat, Transform3D(basis, mouth_at + basis * Vector3(0.0, mouth_h * 0.5, 4.7)), Vector3(mouth_w + 0.8, mouth_h + 0.4, 0.3))
	# the floor going down into the dark, a little under the ground at the back
	m.block(throat, Transform3D(basis * Basis(Vector3.RIGHT, -0.08), mouth_at + basis * Vector3(0.0, -0.12, 2.0)), Vector3(mouth_w + 0.4, 0.2, 5.6))
	await k.step()
	m.commit(throat, PoiKit.plain(Color(0.02, 0.018, 0.015), 1.0), "Throat")
	k.collider(Vector3(mouth_w + 0.8, mouth_h + 0.4, 0.4), Transform3D(basis, mouth_at + basis * Vector3(0.0, mouth_h * 0.5, 4.7)), "stone")
	# the bank of the torn root-ball behind the plate, over the throat: drawn as a mound, stood on
	# as boxes beside and behind the throat (a mound's own body would close the way in)
	var bank_c := hinge + into * 8.0
	await k.step()
	m.mound(k.on_ground(bank_c.x, bank_c.y, -0.6), 8.0, 7.0, _earth_look(k, "mud", 0.36), "RootBall", false, 1.2, 7, 22, false, 0.12)
	for s in [-1.0, 1.0]:
		var side_at := Transform3D(basis, Vector3(hinge.x, g_h, hinge.y) + basis * Vector3(float(s) * (mouth_w * 0.5 + 3.2), 2.0, 5.0))
		k.collider(Vector3(5.0, 4.0, 7.0), side_at, "dirt")
	k.collider(Vector3(10.0, 5.0, 7.0), Transform3D(basis, Vector3(hinge.x, g_h, hinge.y) + basis * Vector3(0.0, 2.5, 9.0)), "dirt")
	var interior := str(site.get("interior", ""))
	SITES._door(d, interior, mouth_at + basis * Vector3(0.0, 0.0, 3.0), yaw_in + PI)
	# whatever waits for the dark waits in the pit, before the mouth
	k.marker("the_mouth", mouth_at + Vector3(out.x, 0.0, out.y) * 3.0, false, true, mouth_w * 0.5)
	# the pit: the torn ground in front of the mouth, clods and stones thrown out of it, ferns already
	var thrown: Array = []
	for i in 22:
		var a := k.rng.randf_range(-PI * 0.75, PI * 0.75)
		var rr := k.rng.randf_range(3.0, 10.0)
		var p := hinge + out.rotated(a) * rr
		thrown.append([k.on_ground(p.x, p.y, -0.25), k.rng.randf() * TAU, k.rng.randf_range(0.35, 0.8)])
	await _row(k, k.rock("boulder"), thrown, true)
	var pit := m.begin()
	for i in 9:
		var p := hinge + out * k.rng.randf_range(1.5, 7.0) + across * k.rng.randf_range(-6.0, 6.0)
		m.ellipsoid(pit, k.on_ground(p.x, p.y, -0.15), Vector3(k.rng.randf_range(1.2, 2.4), 0.35, k.rng.randf_range(1.0, 2.0)), Basis(Vector3.UP, k.rng.randf() * TAU))
	await k.step()
	m.commit(pit, _earth_look(k, "mud", 0.4), "TornGround")
	# stones the plate lifted, still held in its face (one batch with the plate: loose boulders up
	# there read to the seat audit as stones in the air)
	var held := m.begin()
	for i in 6:
		var ang := k.rng.randf_range(0.3, PI - 0.3)
		var rr := pr * k.rng.randf_range(0.3, 0.7)
		var at := plate_c + plate_basis * Vector3(cos(ang) * rr, sin(ang) * rr - 1.5, -thick * 0.5 - 0.3)
		m.ellipsoid(held, at, Vector3(k.rng.randf_range(0.6, 1.1), k.rng.randf_range(0.5, 0.9), k.rng.randf_range(0.5, 0.8)), plate_basis * Basis(Vector3.BACK, k.rng.randf() * TAU))
	# the plate's foot, where its rim meets the ground, in the same stones
	for s in [-1.0, 1.0]:
		var at2 := Vector3(hinge.x, g_h + 0.2, hinge.y) + basis * Vector3(float(s) * (mouth_w * 0.5 + 1.8), 0.0, -0.8)
		m.ellipsoid(held, at2, Vector3(0.9, 0.7, 0.8))
	await k.step()
	m.commit(held, k.surface("stone", 0.7), "PlateStones")
	# the clearing the fall made: foxglove and fern where the light came in, bracket fungus on the bole
	await LAND._grass(d, "foxglove", hinge + out * 9.0, 9.0, 26)
	await LAND._grass(d, "fern", hinge + out * 5.0 + across * 6.0, 6.0, 18)
	await LAND._grass(d, "bracken", tip2 + across * 5.0, 8.0, 20)
	var fungus := k.flora("bracket_fungus")
	if fungus != "":
		var shelves: Array = []
		for i in 14:
			var t := k.rng.randf_range(0.15, 0.95)
			var at := butt.lerp(tip, t)
			var r := lerpf(r0, r1, t)
			var s := -1.0 if i % 2 == 0 else 1.0
			var spot := at + ax * (float(s) * r * 1.02 + bow * sin(PI * t)) + Vector3.UP * k.rng.randf_range(-0.6, 0.6)
			shelves.append([spot, PoiKit.yaw_of(Vector2(ax.x, ax.z) * float(s)), k.rng.randf_range(1.0, 1.8)])
		await _row(k, fungus, shelves)
	# up on the bole by the plate: the hoard. Ravens and worse have carried things up here for
	# twenty years, and somebody has been hiding things among them.
	var hoard := butt + axis * 4.0 + Vector3.UP * (r0 * 0.98)
	var nest := m.begin()
	for i in 18:
		var a := k.rng.randf() * TAU
		var sp := hoard + Vector3(cos(a), 0.0, sin(a)) * k.rng.randf_range(0.5, 1.0)
		m.limb(nest, sp, sp + Vector3(cos(a + 1.6), k.rng.randf_range(-0.05, 0.1), sin(a + 1.6)) * 1.1, 0.035)
	await k.step()
	m.commit(nest, PoiKit.painted(3, DEADWOOD, 0.3), "Nest")
	_container(d, "hoard", hoard, yaw_in, str(site.get("hoard_loot", "core:loot/rich_chest")), "a raven's hoard", "chest")
	k.marker("the_bole_top", hoard + axis * 6.0, false, true, 2.0)
	k.marker("the_lip", k.on_ground(hinge.x + out.x * 9.0 + across.x * 5.0, hinge.y + out.y * 9.0 + across.y * 5.0), true)
	k.bounce_light(Vector3(hinge.x, g_h, hinge.y) + Vector3(out.x, 0.0, out.y) * 6.0 + Vector3.UP * 3.0, Color(0.85, 0.82, 0.7), 1.8, 14.0)
	await SITES._hook(d, site, Vector3(hinge.x, 0.0, hinge.y) + Vector3(out.x, 0.0, out.y) * 10.0 + Vector3(across.x, 0.0, across.y) * 4.0)


# --- Tinehold ----------------------------------------------------------------------------------------

## The Hart-Knights' first hold, on the brink of the Lower Wold's scarp over the Wold Water: the
## castle ruin (site_exterior's pentagon of drum towers, the keep with the stair down to its
## undercroft), and over the keep's back the Tine Tower, twenty-six metres of drum standing whole
## where the curtain fell, crowned with a hart's antlers ten metres across carved in the pale stone:
## the sign the order set up so the Vale could see from the river that the Wold was kept. It is the
## one thing in the Lower Wold that stands over the oaks. Outside the gate the Unvowed have planted
## their own sign: a double row of poles up the track, every one hung with the antlers of a hart
## they took living. Briar has come up the walls' feet.
static func tinehold(d: PoiDressing) -> void:
	await SITES.build(d)
	var k := d.kit
	var m := d.masonry
	var def := ContentDB.get_or_empty(d.poi_id)
	var site: Dictionary = def.get("site", {})
	var radius := minf(float(site.get("radius", 22.0)), maxf(d.pad_radius - 3.0, 9.0))
	var gb := deg_to_rad(float(site.get("gate_bearing_deg", 180.0)))
	var gate_dir := Vector2(sin(gb), cos(gb))
	var across := Vector2(gate_dir.y, -gate_dir.x)
	var back := -gate_dir
	# the keep stands at back * radius * 0.42 (site_exterior._keep); the tower against its back wall
	var dpt := minf(radius * 0.45, 8.5)
	var tc := back * (radius * 0.42 + dpt * 0.5 + 3.2)
	var g := INF
	for i in 8:
		var a := TAU * float(i) / 8.0
		g = minf(g, k.on_ground(tc.x + sin(a) * 3.6, tc.y + cos(a) * 3.6).y)
	var tower_r := 3.6
	var tower_h := 26.0
	var stone := m.begin()
	await k.step()
	m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(tc.x, g - 0.6, tc.y)), tower_r, tower_h + 0.6, 0.0, NAN, true)
	# a plinth at its foot, a string course every storey, and the corbelled crown it carries the
	# antlers on, stepped out over the drum
	m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(tc.x, g - 0.8, tc.y)), tower_r + 0.45, 1.6, 0.0, NAN, false)
	var y := g + 5.0
	while y < g + tower_h - 2.0:
		m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(tc.x, y, tc.y)), tower_r + 0.14, 0.3, 0.0, NAN, false)
		y += 5.0
	var top := g + tower_h
	for i in 16:
		var a := TAU * float(i) / 16.0
		var at := Vector3(tc.x + sin(a) * (tower_r + 0.15), top - 0.9, tc.y + cos(a) * (tower_r + 0.15))
		m.block(stone, Transform3D(Basis(Vector3.UP, a), at), Vector3(0.7, 0.9, 0.7))
	m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(tc.x, top - 0.4, tc.y)), tower_r + 0.5, 1.7, 0.18, NAN, false)
	# slit windows up the side that faces the Vale (dark), a door at the foot into the keep's back
	var dark := m.begin()
	var vale := Vector2(-1.0, 0.0)
	for i in 4:
		var wy := g + 6.5 + float(i) * 4.8
		var a := PoiKit.yaw_of(vale) + (0.5 if i % 2 == 0 else -0.5)
		var at := Vector3(tc.x + sin(a) * (tower_r + 0.02), wy, tc.y + cos(a) * (tower_r + 0.02))
		m.block(dark, Transform3D(Basis(Vector3.UP, a), at), Vector3(0.4, 1.3, 0.12))
	await k.step()
	SITES._commit(d, stone, SITES.stone_look(k, g), "TineTower", true)
	m.commit(dark, PoiKit.plain(Color(0.03, 0.03, 0.03), 1.0), "TineSlits")
	# the crown: a hart's brow of pale stone on the tower's top, the antlers rising out of it,
	# facing the Vale
	var crown := m.begin()
	var brow := Vector3(tc.x, top + 0.9, tc.y)
	var face := Vector3(vale.x, 0.0, vale.y)
	m.ellipsoid(crown, brow, Vector3(1.4, 0.9, 1.0), Basis(Vector3.UP, PoiKit.yaw_of(vale)))
	_antlers(m, crown, brow + Vector3.UP * 0.5, face, 10.0, k.rng, 5)
	await k.step()
	m.commit(crown, PoiKit.plain(ANTLER.lightened(0.15), 0.8), "TheTines", true)
	if k.far:
		return
	# the Unvowed's sign up the track: poles either side of the way out of the gate, each with a
	# hart's antlers on it, newer the further from the gate (and paler)
	var poles := m.begin()
	var tines := m.begin()
	for i in 5:
		for s in [-1.0, 1.0]:
			var p := gate_dir * (radius + 5.5 + float(i) * 2.8) + across * float(s) * 3.3
			var foot := k.on_ground(p.x, p.y, -0.4)
			var head := foot + Vector3(k.rng.randf_range(-0.12, 0.12), 3.4, k.rng.randf_range(-0.12, 0.12))
			m.limb(poles, foot, head, 0.09)
			k.collider(Vector3(0.22, 3.0, 0.22), Transform3D(Basis.IDENTITY, foot + Vector3.UP * 1.9), "wood")
			_antlers(m, tines, head + Vector3.UP * 0.05, Vector3(gate_dir.x, 0.0, gate_dir.y) * -1.0, k.rng.randf_range(0.9, 1.3), k.rng, 4)
	await k.step()
	m.commit(poles, k.surface("timber", 0.6), "AntlerPoles")
	m.commit(tines, PoiKit.plain(ANTLER, 0.75), "TakenTines")
	# briar up the walls' feet, and over the fallen stone
	var briar: Array = []
	for i in 46:
		var a := TAU * float(i) / 46.0 + k.rng.randf_range(-0.05, 0.05)
		var dir := Vector2(sin(a), cos(a))
		if dir.dot(gate_dir) > 0.93:
			continue
		var p := dir * (radius + k.rng.randf_range(1.2, 2.6))
		briar.append([k.on_ground(p.x, p.y), k.rng.randf() * TAU, k.rng.randf_range(1.1, 1.9)])
	await _row(k, k.flora("briar_vine"), briar)
	await LAND._grass(d, "foxglove", gate_dir * (radius + 9.0), 5.0, 14)
	k.marker("the_tine_tower", Vector3(tc.x, g, tc.y) + Vector3(gate_dir.x, 0.0, gate_dir.y) * (tower_r + 1.5), false)


# --- places worked again (world life, phase 2) ---------------------------------------------------
#
# Ten of the Wold's places were the ruins builder's one hall, the same three rooms and one gable
# whether the brief said a grave-mound, a deer park, a burial ground or a barrow, and two camps
# were the camp builder's ring of tents whatever they were for. Each here is built as its brief
# says, on the kind's own pieces where they serve.

## The frame the ruins builder lays its hall in (PoiBuilders._ruins_hall): along the grain, stood
## off a road through the place. {grain, perp, mid (local xz of the hall's middle)}.
static func _hall_frame(k: PoiKit) -> Dictionary:
	var grain := k.grain()
	var perp := Vector2(-grain.y, grain.x)
	var off: float = _builders().call("_off_the_road", k, 7.0 * 0.5 + 4.0, perp)
	return {"grain": grain, "perp": perp, "mid": perp * off}


## A grave-mound of turf over a kerb of stones, laid on the ground at local `c`.
static func _barrow_mound(d: PoiDressing, c: Vector2, r: float, h: float, long_axis := Vector2.ZERO, long := 1.0) -> void:
	var k := d.kit
	var m := d.masonry
	var look: Material = _builders().call("_ground_look", k, c)
	if long_axis == Vector2.ZERO or long <= 1.01:
		await k.step()
		m.mound(k.on_ground(c.x, c.y, -0.35), r, h, look, "Mound", true, 1.3, 7, 22, true, 0.08)
	else:
		# a long barrow: three domes along its axis, overlapping into one ridge
		for i in 3:
			var t := (float(i) - 1.0) * (long - 1.0) * r * 0.55
			var p := c + long_axis * t
			await k.step()
			m.mound(k.on_ground(p.x, p.y, -0.35), r * (1.0 - 0.12 * absf(float(i) - 1.0)), h * (1.0 - 0.15 * absf(float(i) - 1.0)),
					look, "Mound%d" % i, true, 1.3, 7, 22, true, 0.08)
	var kerb: Array = []
	var n := int(r * 2.2 * maxf(long, 1.0))
	for i in n:
		var a := TAU * float(i) / float(n)
		var dir := Vector2(sin(a), cos(a))
		var p := c + dir * r * 0.96
		if long_axis != Vector2.ZERO and long > 1.01:
			var along := dir.dot(long_axis)
			p = c + long_axis * along * r * long * 0.78 + Vector2(-long_axis.y, long_axis.x) * dir.dot(Vector2(-long_axis.y, long_axis.x)) * r * 0.96
		kerb.append([k.on_ground(p.x, p.y, -0.3), k.rng.randf() * TAU, k.rng.randf_range(0.35, 0.55)])
	await _row(k, k.rock("boulder"), kerb, true)


# --- the Knight's Mound -----------------------------------------------------------------------------

## A Hart-Knight's grave-mound in the Greatwood: a turf barrow on a kerb of stones, his antlered helm
## set on its crown and an oak grown up beside it whose roots have come over the mound and closed on
## the helm. His spear stands in the turf before it, and the Mourners' candles burn at its foot.
static func knights_mound(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var r := 7.0
	var h := 3.1
	await _barrow_mound(d, Vector2.ZERO, r, h)
	var crown := k.on_ground(0.0, 0.0, h - 0.4)
	# the oak at the mound's back, and its roots over the top
	var oak_at := -face * (r + 1.2) + Vector2(-face.y, face.x) * 2.0
	await k.step()
	k.place(k.tree("oak"), k.on_ground(oak_at.x, oak_at.y, -0.2), k.rng.randf() * TAU, 1.0, true, Vector3.ZERO, true)
	var roots := m.begin()
	var base := k.on_ground(oak_at.x, oak_at.y, 0.6)
	for i in 6:
		var spread := (float(i) - 2.5) * 0.35
		var dir := (-oak_at).normalized().rotated(spread)
		var mid := Vector2(oak_at.x, oak_at.y) + dir * (r * 0.6)
		var mid3 := k.on_ground(mid.x, mid.y, 0.15)
		mid3.y = maxf(mid3.y, crown.y - 1.2 + 0.0)
		var end := dir * 2.0 + (Vector2.ZERO if i % 2 == 0 else Vector2(-dir.y, dir.x) * 1.2)
		var end3 := crown + Vector3(end.x * 0.3, 0.2, end.y * 0.3)
		m.limb(roots, base, mid3, 0.22 - 0.02 * float(i % 3))
		m.limb(roots, mid3, end3, 0.12)
	await k.step()
	m.commit(roots, PoiKit.painted(3, ROOTBARK, 0.4), "Roots", true)
	# the helm: a dome of black iron, a nasal, and the antlers out of it
	var helm := m.begin()
	m.ellipsoid(helm, crown + Vector3.UP * 0.25, Vector3(0.32, 0.3, 0.36), Basis(Vector3.UP, PoiKit.yaw_of(face)))
	m.block(helm, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), crown + Vector3(face.x, 0.0, face.y) * 0.34 + Vector3.UP * 0.1), Vector3(0.06, 0.32, 0.04))
	await k.step()
	m.commit(helm, PoiKit.plain(Color(0.12, 0.12, 0.11), 0.5, 0.6), "Helm", true)
	var tines := m.begin()
	_antlers(m, tines, crown + Vector3.UP * 0.45, Vector3(face.x, 0.0, face.y), 1.9, k.rng, 5)
	await k.step()
	m.commit(tines, PoiKit.plain(ANTLER, 0.75), "HelmTines", true)
	k.collider(Vector3(0.8, 1.2, 0.8), Transform3D(Basis.IDENTITY, crown + Vector3.UP * 0.6), "metal")
	# his spear in the turf before it, leaning, and the candles at the mound's foot
	var spear_at := face * (r * 0.55)
	await k.step()
	k.place(k.prop("spear"), k.on_ground(spear_at.x, spear_at.y, -0.3), PoiKit.yaw_of(face), 1.3, false, Vector3(-0.25, 0.0, 0.08))
	var foot := face * (r + 0.8)
	var candles: Array = []
	for i in 5:
		var p := foot + Vector2(-face.y, face.x) * (float(i) - 2.0) * 0.45 + k.jitter(0.12)
		candles.append([k.on_ground(p.x, p.y), k.rng.randf() * TAU, 1.0])
	await _row(k, k.prop("candle_stub"), candles)
	k.light(k.on_ground(foot.x, foot.y, 0.3), Color(1.0, 0.75, 0.45), 1.2, 5.0)
	k.marker("the_mound", k.on_ground(foot.x + face.x * 2.0, foot.y + face.y * 2.0), false)
	await LAND._grass(d, "foxglove", face * (r + 3.0), 3.0, 10)
	await LAND._grass(d, "fern", -face * 3.0, r * 0.8, 16)


# --- the Tine Barrow -------------------------------------------------------------------------------

## The first Hart-Knights' long barrow below Moot Tor: a long turf ridge on its kerb, a crescent of
## standing stones round a paved forecourt at its east end, each stone cut with an antler, and the
## tomb's door between two uprights under a lintel, sealed with a slab with a hart's skull set in it.
static func tine_barrow(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var axis := -face
	var r := 6.0
	var c := axis * 7.0
	await _barrow_mound(d, c, r, 3.4, axis, 2.0)
	# the door at the barrow's head, toward the forecourt
	var door_at := c - axis * (r * 1.5)
	var yaw := PoiKit.yaw_of(face)
	var basis := Basis(Vector3.UP, yaw)
	var g := k.on_ground(door_at.x, door_at.y).y
	var stone := m.begin()
	for s in [-1.0, 1.0]:
		var p := Vector3(door_at.x, g + 1.2, door_at.y) + basis * Vector3(float(s) * 1.0, 0.0, 0.0)
		m.block(stone, Transform3D(basis, p), Vector3(0.6, 2.8, 0.7))
		k.collider(Vector3(0.6, 2.8, 0.7), Transform3D(basis, p), "stone")
	m.block(stone, Transform3D(basis, Vector3(door_at.x, g + 2.75, door_at.y)), Vector3(3.0, 0.55, 0.9))
	var slab := Transform3D(basis, Vector3(door_at.x, g + 1.05, door_at.y) + basis * Vector3(0.0, 0.0, -0.1))
	m.block(stone, slab, Vector3(1.45, 2.2, 0.3))
	k.collider(Vector3(1.45, 2.2, 0.4), slab, "stone")
	# the forecourt: a paved half-ring and the crescent of stones round it
	var fc := door_at + face * 4.5
	for i in 7:
		var a := PoiKit.yaw_of(face) - PI * 0.5 + PI * float(i) / 6.0
		var p := fc + Vector2(sin(a), cos(a)) * 5.0
		var sh := k.rng.randf_range(1.6, 2.3)
		var sx := Transform3D(Basis(Vector3.UP, a), k.on_ground(p.x, p.y, sh * 0.5 - 0.4))
		m.block(stone, sx, Vector3(0.9, sh, 0.45))
		k.collider(Vector3(0.9, sh, 0.45), sx, "stone")
	for i in 10:
		var p := fc + k.jitter(3.2)
		m.block(stone, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), k.on_ground(p.x, p.y, -0.06)), Vector3(k.rng.randf_range(0.9, 1.5), 0.16, k.rng.randf_range(0.7, 1.2)))
	await k.step()
	m.commit(stone, k.surface("stone", 0.6), "Forecourt", true)
	# the antlers cut in the crescent's faces (pale, in low relief), and the hart's skull in the door
	var carve := m.begin()
	for i in 7:
		var a := PoiKit.yaw_of(face) - PI * 0.5 + PI * float(i) / 6.0
		var p := fc + Vector2(sin(a), cos(a)) * 5.0
		var inward := Vector3(-sin(a), 0.0, -cos(a))
		_antlers(m, carve, k.on_ground(p.x, p.y, 0.9) + inward * 0.26, inward, 0.55, k.rng, 3)
	var skull_at := Vector3(door_at.x, g + 1.45, door_at.y) + basis * Vector3(0.0, 0.0, 0.1) + Vector3(face.x, 0.0, face.y) * 0.08
	m.ellipsoid(carve, skull_at, Vector3(0.18, 0.24, 0.16), basis)
	m.ellipsoid(carve, skull_at + Vector3(face.x, -0.3, face.y) * 0.25, Vector3(0.09, 0.12, 0.14), basis)
	_antlers(m, carve, skull_at + Vector3.UP * 0.18, Vector3(face.x, 0.0, face.y), 1.4, k.rng, 5)
	await k.step()
	m.commit(carve, PoiKit.plain(ANTLER, 0.8), "Carving", true)
	# the chalk where Kenard writes the names, and where he sits
	k.marker("the_forecourt", k.on_ground(fc.x, fc.y), true)
	k.marker("home", k.on_ground(fc.x + face.y * 3.5, fc.y - face.x * 3.5), true)
	await LAND._grass(d, "fern", c + Vector2(-axis.y, axis.x) * (r + 2.0), 3.0, 10)


# --- Mossgrave ----------------------------------------------------------------------------------

## The Woodfolk's burial ground: rows of low moss mounds, a name-staff of ash with an antler hook at
## each head and the mourner's token hung on it, a yew in the middle older than the Hollow, and the
## seed-bed under bark where the moss for the next is started.
static func mossgrave(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(-face.y, face.x)
	await k.step()
	k.place(k.tree("yew_veteran") if k.tree("yew_veteran") != "" else k.tree("yew"), k.on_ground(0.0, 0.0, -0.2), k.rng.randf() * TAU, 1.0, true, Vector3.ZERO, true)
	var moss_look := _earth_look(k, "moss", 0.42)
	var graves := m.begin()
	var staves := m.begin()
	var hooks := m.begin()
	var spots: Array = []
	for row in 4:
		for col in 6:
			if k.rng.randf() < 0.15:
				continue
			var along := (float(col) - 2.5) * 2.4
			var out := 5.0 + float(row) * 3.0
			for s in [-1.0, 1.0]:
				if row == 3 and s > 0.0 and col > 3:
					continue
				var p := face * out * float(s) + side * along + k.jitter(0.3)
				if p.length() < 4.5:
					continue
				spots.append(p)
	for p in spots:
		var pp: Vector2 = p
		var yaw := PoiKit.yaw_of(side) + k.rng.randf_range(-0.1, 0.1)
		m.ellipsoid(graves, k.on_ground(pp.x, pp.y, -0.12), Vector3(0.7, 0.45, 1.1) * k.rng.randf_range(0.85, 1.1), Basis(Vector3.UP, yaw))
		var head := pp + Vector2(sin(yaw), cos(yaw)) * 1.35
		var top := m.post(staves, head, 1.25 + k.rng.randf_range(-0.15, 0.2), 0.05, Vector3(k.rng.randf_range(-0.05, 0.05), 0.0, k.rng.randf_range(-0.05, 0.05)))
		_antlers(m, hooks, top, Vector3(sin(yaw), 0.0, cos(yaw)), 0.4, k.rng, 2)
	await k.step()
	m.commit(graves, moss_look, "MossGraves")
	m.commit(staves, PoiKit.painted(3, DEADWOOD, 0.4), "NameStaves")
	m.commit(hooks, PoiKit.plain(ANTLER, 0.8), "Hooks")
	# the seed-bed: a flat stone under a roof of bark on four stakes, the moss started on it
	var bed := face * -3.0 + side * 9.5
	var bark := m.begin()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.post(bark, bed + side * float(sx) * 0.9 + face * float(sz) * 0.6, 1.3, 0.08)
	var roof := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)) * Basis(Vector3.RIGHT, 0.2), k.on_ground(bed.x, bed.y, 1.35))
	m.block(bark, roof, Vector3(2.3, 0.06, 1.7))
	await k.step()
	m.commit(bark, PoiKit.painted(3, ROOTBARK, 0.5), "SeedBed")
	var flat := m.begin()
	m.block(flat, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)), k.on_ground(bed.x, bed.y, 0.25)), Vector3(1.6, 0.5, 1.0))
	m.ellipsoid(flat, k.on_ground(bed.x, bed.y, 0.52), Vector3(0.6, 0.06, 0.35))
	await k.step()
	m.commit(flat, k.surface("stone", 0.4), "SeedStone")
	k.collider(Vector3(1.6, 0.5, 1.0), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)), k.on_ground(bed.x, bed.y, 0.25)), "stone")
	k.marker("the_rows", k.on_ground(face.x * 6.0, face.y * 6.0), false)
	await LAND._grass(d, "fern", face * -10.0, 4.0, 14)
	await LAND._grass(d, "foxglove", face * 10.0 + side * 6.0, 3.0, 10)


# --- the Antler Chapel ---------------------------------------------------------------------------

## The ruins builder's roofless hall, and on every wall of it the antlers of every hart that died old
## in the Greatwood, hung in rows on pegs, three hundred of them less the forty; on the gable's inside
## a rack of the oldest; and the broken altar with the knight's count chalked on a board against it.
static func antler_chapel(d: PoiDressing) -> void:
	await _builders().ruins(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var f := _hall_frame(k)
	var grain: Vector2 = f["grain"]
	var perp: Vector2 = f["perp"]
	var mid: Vector2 = f["mid"]
	var tines := m.begin()
	var pegs := m.begin()
	# along both long walls, inside, in two rows where the walls still stand to hold them, and
	# laid in heaps where they do not
	for s in [-1.0, 1.0]:
		for i in 9:
			var along := (float(i) - 4.0) * 1.35
			var wall := mid + grain * along + perp * float(s) * (3.5 - 0.35)
			var g := k.on_ground(wall.x, wall.y).y
			var inward := Vector3(-perp.x, 0.0, -perp.y) * float(s)
			var hgt := 0.75 if absf(along) > 3.0 else 0.9
			var at := Vector3(wall.x, g + hgt, wall.y)
			m.block(pegs, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(perp)), at), Vector3(0.12, 0.12, 0.3))
			_antlers(m, tines, at + inward * 0.12, inward, k.rng.randf_range(0.8, 1.2), k.rng, 4)
	# the gable end that stands (heights[1] in the ruins builder: the far long run's end), its rack
	var gable := mid + grain * (13.0 * 0.5 - 0.4)
	var gg := k.on_ground(gable.x, gable.y).y
	for row in 3:
		for col in 4:
			var at := Vector3(gable.x, gg + 1.4 + float(row) * 0.95, gable.y) + Vector3(perp.x, 0.0, perp.y) * (float(col) - 1.5) * 1.3
			_antlers(m, tines, at, Vector3(-grain.x, 0.0, -grain.y), k.rng.randf_range(0.9, 1.4), k.rng, 5)
			m.block(pegs, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(grain)), at - Vector3.UP * 0.05), Vector3(0.12, 0.12, 0.3))
	await k.step()
	m.commit(tines, PoiKit.plain(ANTLER, 0.78), "HungTines", true)
	m.commit(pegs, k.surface("timber", 0.5), "Pegs")
	# the altar: a broken block, and the count chalked on a board against it
	var altar := mid + grain * 4.4
	var alt := m.begin()
	var axf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(grain)), k.on_ground(altar.x, altar.y, 0.5))
	m.block(alt, axf, Vector3(1.9, 1.0, 0.9))
	m.block(alt, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(grain) + 0.3) * Basis(Vector3.RIGHT, 0.25), k.on_ground(altar.x + perp.x * 1.2, altar.y + perp.y * 1.2, 0.2)), Vector3(0.9, 0.4, 0.8))
	await k.step()
	m.commit(alt, k.surface("stone", 0.5), "Altar")
	k.collider(Vector3(1.9, 1.0, 0.9), axf, "stone")
	k.marker("the_altar", k.on_ground(altar.x - grain.x * 1.4, altar.y - grain.y * 1.4), false)


# --- Pellow's Pale ---------------------------------------------------------------------------------

## A Tallyman's deer-park in the Lower Wold: the pale, a high wall of mossed granite, running off in an
## arc through the oaks and down in long gaps where the oaks have pushed it over; the gate in it still
## shut, iron, chained and padlocked with the Tallyman's lock; and inside, the parker's lodge fallen in,
## his strongbox under the hearth-stone, and the park gone back to the wood.
static func pellows_pale(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	# the pale is a long wall on a wide curve, bellying out toward the road, crossing the place from
	# side to side: what is inside it runs off through the oaks behind. (A ring read as a fort.)
	var big := 70.0
	var centre := -face * (big - 9.0)
	var stone := m.begin()
	var n := 18
	var half_arc := asin(23.0 / big)
	var bays: Array = []
	for i in n + 1:
		var a := PoiKit.yaw_of(face) - half_arc + 2.0 * half_arc * float(i) / float(n)
		bays.append(centre + Vector2(sin(a), cos(a)) * big)
	var gate_i := int(n / 2.0)
	for i in n:
		# the gate's bay, and the stretches the oaks pushed down, are left out or low
		if i == gate_i or i == gate_i - 1:
			continue
		var down := i in [2, 3, 13]
		await k.step()
		m.wall(stone, bays[i], bays[i + 1], 0.6 if down else k.rng.randf_range(2.0, 2.6), 0.8 if down else 0.2)
	# the gate's piers, square and capped
	var gp: Array = [bays[gate_i - 1], bays[gate_i + 1]]
	for p in gp:
		var pp: Vector2 = p
		var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), k.on_ground(pp.x, pp.y, 1.4))
		m.block(stone, xf, Vector3(1.0, 3.0, 1.0))
		m.block(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), k.on_ground(pp.x, pp.y, 3.05)), Vector3(1.25, 0.3, 1.25))
		k.collider(Vector3(1.0, 3.0, 1.0), xf, "stone")
	await k.step()
	m.commit(stone, k.surface("stone", 0.7), "Pale", true)
	var r := 9.0
	# the gate: two leaves of iron bars, shut, a chain round the meeting bars and the lock on it
	var iron := m.begin()
	var a2: Vector2 = gp[0]
	var b2: Vector2 = gp[1]
	var gy := minf(k.on_ground(a2.x, a2.y).y, k.on_ground(b2.x, b2.y).y)
	var span := a2.distance_to(b2) - 1.0
	var gdir := (b2 - a2).normalized()
	for i in 14:
		var t := (float(i) + 0.5) / 14.0
		var p := a2 + gdir * (0.5 + span * t)
		m.rod(iron, Transform3D(Basis.IDENTITY, Vector3(p.x, gy + 1.15, p.y)), 0.03, 2.3)
	for y in [0.35, 1.2, 2.1]:
		var c := (a2 + b2) * 0.5
		m.block(iron, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(gdir) + PI * 0.5), Vector3(c.x, gy + y, c.y)), Vector3(span, 0.06, 0.05))
	var lock_at := (a2 + b2) * 0.5
	m.block(iron, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), Vector3(lock_at.x, gy + 1.15, lock_at.y) + Vector3(face.x, 0.0, face.y) * 0.08), Vector3(0.14, 0.18, 0.08))
	await k.step()
	m.commit(iron, PoiKit.plain(Color(0.2, 0.15, 0.11), 0.6, 0.5), "Gate", true)
	k.collider(Vector3(span, 2.4, 0.2), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(gdir) + PI * 0.5), Vector3(lock_at.x, gy + 1.2, lock_at.y)), "metal")
	# the parker's lodge inside, fallen in: three walls to the knee and a gable, its hearth
	var lodge := -face * 9.0 + Vector2(-face.y, face.x) * 4.0
	var lw := m.begin()
	var ax := Vector2(-face.y, face.x)
	var corners := [lodge - ax * 2.5 - face * 2.0, lodge + ax * 2.5 - face * 2.0, lodge + ax * 2.5 + face * 2.0, lodge - ax * 2.5 + face * 2.0]
	var hs := [3.6, 0.9, 1.3, 0.6]
	for i in 4:
		await k.step()
		m.wall(lw, corners[i], corners[(i + 1) % 4], hs[i], 0.4 if i != 0 else 0.1)
	await k.step()
	m.commit(lw, k.surface("stone", 0.8), "Lodge", true)
	var hearth := lodge - face * 1.2
	await k.step()
	k.place(k.prop("campfire"), k.on_ground(hearth.x, hearth.y), 0.0, 1.0, false)
	_container(d, "parkers_box", k.on_ground(hearth.x + ax.x * 1.4, hearth.y + ax.y * 1.4), PoiKit.yaw_of(face), "core:loot/common_chest", "the parker's strongbox", "chest")
	# the park gone back to wood: a hawthorn, bracken and the oaks' saplings inside the pale
	await k.step()
	k.place(k.tree("hawthorn_veteran") if k.tree("hawthorn_veteran") != "" else k.tree("hawthorn"), k.on_ground(face.x * -2.0 + ax.x * -7.0, face.y * -2.0 + ax.y * -7.0), k.rng.randf() * TAU)
	await LAND._grass(d, "bracken", Vector2.ZERO, r * 0.7, 30)
	k.marker("the_gate", k.on_ground(face.x * 13.0, face.y * 13.0), false)
	k.marker("the_lodge", k.on_ground(lodge.x, lodge.y), false)


# --- the Bark Camp -----------------------------------------------------------------------------------

## Tamwick's bark-strippers' camp: the camp builder's fire and tents, and round it the oaks they have
## stripped, standing white and dead to the height a man on a ladder reaches, their bark drying in
## curls on racks of poles, bundled on a sledge for the tanners.
static func bark_camp(d: PoiDressing) -> void:
	await _builders().camp(d)
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(-face.y, face.x)
	# the stripped oaks: trunks white to 4 m, the bark still on above, their crowns dying back
	var white := m.begin()
	var brown := m.begin()
	var crowns := m.begin()
	var spots: Array = []
	for i in 7:
		var a := TAU * (float(i) + k.rng.randf_range(-0.25, 0.25)) / 7.0
		var p := Vector2(sin(a), cos(a)) * k.rng.randf_range(10.5, 13.0)
		if p.dot(face) > 9.0:
			continue
		spots.append(p)
	for p in spots:
		var pp: Vector2 = p
		var g := k.on_ground(pp.x, pp.y, -0.3)
		var r := k.rng.randf_range(0.35, 0.55)
		var lean := Vector3(k.rng.randf_range(-0.05, 0.05), 1.0, k.rng.randf_range(-0.05, 0.05)).normalized()
		var strip := g + lean * 4.3
		var top := g + lean * k.rng.randf_range(9.0, 12.0)
		_bole(white, g, strip, r * 1.15, r, k.rng, 12, 3)
		_bole(brown, strip, top, r * 1.02, r * 0.45, k.rng, 12, 4)
		for j in 5:
			var aa := k.rng.randf() * TAU
			var from := strip.lerp(top, k.rng.randf_range(0.5, 0.95))
			var to := from + Vector3(cos(aa), k.rng.randf_range(0.4, 0.9), sin(aa)).normalized() * k.rng.randf_range(2.0, 4.0)
			m.limb(crowns, from, to, k.rng.randf_range(0.06, 0.12))
		var cap := CylinderShape3D.new()
		cap.radius = r * 1.1
		cap.height = 9.0
		k.collider_shape(cap, Transform3D(Basis.IDENTITY, g + Vector3.UP * 4.5), "wood")
	await k.step()
	m.commit(white, PoiKit.painted(3, {"base": "#c9bfa6", "accent": "#a8977a"}, 0.2), "StrippedOaks", true)
	m.commit(brown, PoiKit.painted(3, ROOTBARK, 0.5), "Bark", true)
	m.commit(crowns, PoiKit.painted(3, DEADWOOD, 0.5), "DeadCrowns", true)
	if k.far:
		return
	# the drying racks: two rails on forked posts, bark in curls laid over them
	var racks := m.begin()
	var curls := m.begin()
	for rk in 3:
		var c := side * (float(rk) - 1.0) * 5.5 - face * 5.0
		var ends := [c - side * 1.8, c + side * 1.8]
		for e in ends:
			var ee: Vector2 = e
			m.post(racks, ee, 1.4, 0.1)
		var y := k.on_ground(c.x, c.y).y + 1.35
		var ca: Vector2 = ends[0]
		var cb: Vector2 = ends[1]
		m.block(racks, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side) + PI * 0.5), Vector3(c.x, y, c.y)), Vector3(3.8, 0.08, 0.08))
		for j in 9:
			var t := (float(j) + 0.5) / 9.0
			var at := ca.lerp(cb, t)
			var cyl := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(at.x, y + 0.05, at.y))
			m.block(curls, cyl.translated_local(Vector3(0.0, 0.0, 0.0)), Vector3(0.05, 0.36, 0.9))
	await k.step()
	m.commit(racks, k.surface("timber", 0.6), "Racks")
	m.commit(curls, PoiKit.painted(3, ROOTBARK, 0.6), "BarkCurls")
	# a sledge of bundled bark for the tanners
	var sledge := face * -9.5 + side * 6.0
	var sl := m.begin()
	for s in [-1.0, 1.0]:
		m.block(sl, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), k.on_ground(sledge.x + side.x * s * 0.6, sledge.y + side.y * s * 0.6, 0.1)), Vector3(0.12, 0.2, 2.6))
	for b in 4:
		m.limb(sl, k.on_ground(sledge.x, sledge.y, 0.45 + float(b % 2) * 0.35) - Vector3(face.x, 0.0, face.y) * 1.0 + Vector3(side.x, 0.0, side.y) * (floorf(float(b) / 2.0) - 0.5) * 0.6,
				k.on_ground(sledge.x, sledge.y, 0.45 + float(b % 2) * 0.35) + Vector3(face.x, 0.0, face.y) * 1.0 + Vector3(side.x, 0.0, side.y) * (floorf(float(b) / 2.0) - 0.5) * 0.6, 0.28)
	await k.step()
	m.commit(sl, PoiKit.painted(3, ROOTBARK, 0.7), "Sledge")
	k.collider(Vector3(1.6, 1.1, 2.6), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), k.on_ground(sledge.x, sledge.y, 0.55)), "wood")
	var box_at := sledge + side * 1.8
	_container(d, "pay_box", k.on_ground(box_at.x, box_at.y), PoiKit.yaw_of(face), "core:loot/common_chest", "the strippers' pay-box", "chest")
	k.marker("the_racks", k.on_ground(-face.x * 3.5, -face.y * 3.5), true)


# --- the Poachers' Lee ----------------------------------------------------------------------------

## A poachers' camp in the lee of the Thornmarch: the camp builder's fire and tents, and the trade
## laid out round it: deer-hides pegged on frames of poles, a bow-rack with three bows and a quiver
## standing, a hart hung by its heels from a gallows of poles, and antlers sawn and bundled.
static func poachers_lee(d: PoiDressing) -> void:
	await _builders().camp(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(-face.y, face.x)
	var poles := m.begin()
	var hides := m.begin()
	for i in 4:
		var c := -face * 10.0 + side * (float(i) - 1.5) * 3.2 + k.jitter(0.4)
		var yaw := PoiKit.yaw_of(face) + k.rng.randf_range(-0.2, 0.2)
		var top := m.frame(poles, c, yaw, 2.0, 2.1, 0.09)
		var basis := Basis(Vector3.UP, yaw)
		m.block(poles, Transform3D(basis, k.on_ground(c.x, c.y, 0.25)), Vector3(2.0, 0.07, 0.07))
		# the hide, stretched in the frame, a little sag in it
		m.block(hides, Transform3D(basis * Basis(Vector3.RIGHT, 0.06), (top + k.on_ground(c.x, c.y, 0.25)) * 0.5), Vector3(1.75, top.y - k.on_ground(c.x, c.y).y - 0.4, 0.03))
	await k.step()
	m.commit(poles, k.surface("timber", 0.6), "HideFrames")
	m.commit(hides, PoiKit.painted(6, {"base": "#7a5a3c", "accent": "#5a3f28", "grout": "#3a2a1a", "unit": 0.3}, 0.3), "Hides")
	# the gallows and the hart on it
	var gal := side * 9.5 + face * 2.0
	var gw := m.begin()
	var bar := m.frame(gw, gal, PoiKit.yaw_of(side), 2.6, 3.2, 0.12)
	await k.step()
	m.commit(gw, k.surface("timber", 0.5), "Gallows")
	var hart := m.begin()
	var hang := bar - Vector3.UP * 0.3
	m.limb(hart, hang - Vector3.UP * 0.2, hang - Vector3.UP * 1.6, 0.34)
	m.limb(hart, hang - Vector3.UP * 1.5, hang - Vector3.UP * 2.25, 0.13)
	for s in [-1.0, 1.0]:
		m.limb(hart, hang + Vector3(side.x, 0.0, side.y) * 0.15 * s, hang - Vector3.UP * 0.4, 0.07)
	await k.step()
	m.commit(hart, PoiKit.plain(Color(0.42, 0.28, 0.18), 0.85), "Hart")
	# the bow-rack: a rail on two posts, three bows leaned on it
	var br := -side * 8.5 + face * 3.0
	var bw := m.begin()
	var t1 := m.post(bw, br - face * 0.8, 1.2, 0.08)
	var t2 := m.post(bw, br + face * 0.8, 1.2, 0.08)
	m.block(bw, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), (t1 + t2) * 0.5), Vector3(0.07, 0.07, 1.7))
	for j in 3:
		var at := br + face * (float(j) - 1.0) * 0.55 - side * 0.25
		var foot := k.on_ground(at.x, at.y)
		m.limb(bw, foot, foot + Vector3.UP * 1.45 + Vector3(side.x, 0.0, side.y) * 0.25, 0.025)
	await k.step()
	m.commit(bw, k.surface("timber", 0.4), "BowRack")
	var tines := m.begin()
	for j in 4:
		var at := -side * 5.0 - face * 4.0 + k.jitter(0.6)
		_antlers(m, tines, k.on_ground(at.x, at.y, 0.12), Vector3(k.rng.randf_range(-1, 1), 0.0, k.rng.randf_range(-1, 1)), k.rng.randf_range(0.9, 1.2), k.rng, 4)
	await k.step()
	m.commit(tines, PoiKit.plain(ANTLER.darkened(0.1), 0.8), "SawnTines")
	k.marker("the_hides", k.on_ground(-face.x * 8.0, -face.y * 8.0), true)


# --- the wayside lodges --------------------------------------------------------------------------
#
# Five wayside ruins were the same roofless hall. Each keeps the hall and gets the one thing its
# sentence is about, where you see it from the road.

## The burnt lodge: its courses scorched black to the gable's top, charred rafters fallen across the
## floor, and a ring of ash where the fire began.
static func burnt_lodge(d: PoiDressing) -> void:
	await _builders().ruins(d)
	var k := d.kit
	var m := d.masonry
	var f := _hall_frame(k)
	var grain: Vector2 = f["grain"]
	var perp: Vector2 = f["perp"]
	var mid: Vector2 = f["mid"]
	# the courses themselves gone black with the fire: the ruins builder's own stone, scorched
	var courses := d.find_child("Courses", false, false) as MeshInstance3D
	if courses != null:
		courses.material_override = PoiKit.painted(2, {"base": "#2f2c28", "accent": "#1c1a18", "grout": "#0e0d0c", "unit": 0.5}, 0.8)
	var breast := d.find_child("Hearth", false, false) as MeshInstance3D
	if breast != null:
		breast.material_override = PoiKit.painted(2, {"base": "#24211e", "accent": "#141210", "grout": "#0a0908", "unit": 0.5}, 0.8)
	var soot := m.begin()
	for i in 7:
		var a := k.on_ground(mid.x, mid.y, 0.15) + Vector3(grain.x, 0.0, grain.y) * k.rng.randf_range(-5.0, 5.0) + Vector3(perp.x, 0.0, perp.y) * k.rng.randf_range(-2.5, 2.5)
		var dir := Vector3(perp.x, 0.0, perp.y).rotated(Vector3.UP, k.rng.randf_range(-0.6, 0.6))
		m.limb(soot, a - dir * 2.0, a + dir * 2.0 + Vector3.UP * k.rng.randf_range(0.0, 0.8), k.rng.randf_range(0.1, 0.16))
	await k.step()
	m.commit(soot, PoiKit.plain(Color(0.06, 0.055, 0.05), 0.95), "Char", true)
	await LAND._grass(d, "grey_grass", mid, 4.0, 14)


## The webbed lodge: weaver silk in sheets across its doorway and its broken windows, strung from the
## gable to the nearest oak, and egg-sacs hung in it.
static func webbed_lodge(d: PoiDressing) -> void:
	await _builders().ruins(d)
	var k := d.kit
	var m := d.masonry
	var f := _hall_frame(k)
	var grain: Vector2 = f["grain"]
	
	var mid: Vector2 = f["mid"]
	var silk := m.begin()
	var door := mid - grain * 6.5
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(grain))
	m.block(silk, Transform3D(basis, k.on_ground(door.x, door.y, 1.2)), Vector3(1.6, 2.3, 0.02))
	# threads from the gable's top fanning out to the ground and the walls
	var top := k.on_ground(mid.x + grain.x * 6.5, mid.y + grain.y * 6.5, 4.4)
	for i in 16:
		var a := TAU * float(i) / 16.0
		var to := Vector2(mid.x, mid.y) + Vector2(sin(a), cos(a)) * k.rng.randf_range(5.0, 9.0)
		m.limb(silk, top, k.on_ground(to.x, to.y, k.rng.randf_range(0.2, 1.6)), 0.012)
	# sheets between the walls' tops
	for i in 4:
		var p := mid + grain * ((float(i) - 1.5) * 3.0)
		m.block(silk, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(grain)) * Basis(Vector3.FORWARD, k.rng.randf_range(-0.2, 0.2)), k.on_ground(p.x, p.y, 1.4)), Vector3(7.0, 0.015, k.rng.randf_range(1.0, 2.2)))
	await k.step()
	m.commit(silk, PoiKit.plain(Color(0.86, 0.86, 0.82, 1.0), 0.4), "Silk", true)
	var sacs := m.begin()
	for i in 6:
		var p := mid + grain * k.rng.randf_range(-5.0, 5.0) + Vector2(-grain.y, grain.x) * (3.0 if i % 2 == 0 else -3.0)
		m.ellipsoid(sacs, k.on_ground(p.x, p.y, 0.18), Vector3(0.16, 0.26, 0.16))
		m.limb(sacs, k.on_ground(p.x, p.y, 0.3), k.on_ground(p.x, p.y, 1.0), 0.01)
	await k.step()
	m.commit(sacs, PoiKit.plain(Color(0.78, 0.76, 0.66), 0.6), "EggSacs")


## The antler-smith's house: his cold forge in the corner, the anvil, and on the anvil a Hart-Knight's
## helm half-made, its antler sockets empty.
static func antler_smiths_house(d: PoiDressing) -> void:
	await _builders().ruins(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var f := _hall_frame(k)
	var grain: Vector2 = f["grain"]
	var perp: Vector2 = f["perp"]
	var mid: Vector2 = f["mid"]
	var forge := mid + grain * 4.0 + perp * 2.0
	var yaw := PoiKit.yaw_of(-perp)
	await k.step()
	k.place(k.prop("forge_hearth"), k.on_ground(forge.x, forge.y), yaw)
	var anvil := forge - perp * 1.8 - grain * 0.6
	await k.step()
	k.place(k.prop("anvil"), k.on_ground(anvil.x, anvil.y), yaw + 0.3)
	var helm := m.begin()
	var at := k.on_ground(anvil.x, anvil.y, 0.82)
	m.ellipsoid(helm, at + Vector3.UP * 0.18, Vector3(0.24, 0.22, 0.27), Basis(Vector3.UP, yaw))
	for s in [-1.0, 1.0]:
		m.rod(helm, Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.4 + Vector3(perp.x, 0.0, perp.y) * 0.12 * s), 0.04, 0.12)
	await k.step()
	m.commit(helm, PoiKit.plain(Color(0.16, 0.15, 0.14), 0.45, 0.65), "HalfHelm")
	var tongs := forge - grain * 1.2
	await k.step()
	k.place(k.prop("tongs"), k.on_ground(tongs.x, tongs.y, 0.02), k.rng.randf() * TAU, 1.0, false, Vector3(PI * 0.5, 0.0, 0.0))
	var tines := m.begin()
	for i in 3:
		var p := mid - grain * 2.0 + k.jitter(1.2)
		_antlers(m, tines, k.on_ground(p.x, p.y, 0.1), Vector3(k.rng.randf_range(-1, 1), 0.0, 1.0), 0.9, k.rng, 3)
	await k.step()
	m.commit(tines, PoiKit.plain(ANTLER, 0.8), "Tines")


## Wenna's house: the Vale woman's chalk-cob walls, pale among the Wold's granite, her grave inside
## them under a stone lid and a Woodfolk moss started on the lid.
static func wennas_house(d: PoiDressing) -> void:
	await _builders().ruins(d)
	var k := d.kit
	var m := d.masonry
	var f := _hall_frame(k)
	var grain: Vector2 = f["grain"]
	var mid: Vector2 = f["mid"]
	var lid := mid + grain * 1.5
	var slab := m.begin()
	var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(grain)), k.on_ground(lid.x, lid.y, 0.12))
	m.block(slab, xf, Vector3(1.0, 0.28, 2.1))
	await k.step()
	m.commit(slab, k.surface("stone", 0.3), "GraveLid", true)
	k.collider(Vector3(1.0, 0.28, 2.1), xf, "stone")
	var moss := m.begin()
	m.ellipsoid(moss, k.on_ground(lid.x, lid.y, 0.27), Vector3(0.38, 0.06, 0.6), Basis(Vector3.UP, PoiKit.yaw_of(grain)))
	await k.step()
	m.commit(moss, _earth_look(k, "moss", 0.75), "Moss")
	await LAND._grass(d, "cow_parsley", lid, 2.2, 8)


# --- the Charter Delf -------------------------------------------------------------------------------

## A Tollmere company's lead mine under the Northwold's oaks: the headframe of Rafts timber standing
## eighteen metres over its shaft with the winding wheel at its head (the thing seen over the
## canopy from the Skarl road), back-stays raking to the winding house, the cage hung in the shaft's
## collar (the site's door), plank ways and tubs, the spoil heaped grey down the slope with the oaks
## dead in it, and the clerk's office with its lamp lit at noon.
static func charter_delf(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var def := ContentDB.get_or_empty(d.poi_id)
	var site: Dictionary = def.get("site", {})
	var down := k.downhill()
	if down == Vector2.ZERO:
		down = k.grain()
	down = down.normalized()
	var side := Vector2(-down.y, down.x)
	var yaw := PoiKit.yaw_of(down)
	var basis := Basis(Vector3.UP, yaw)
	var g := k.on_ground(0.0, 0.0).y
	# the collar: a square of squared timber round the shaft, the shaft a black square in it
	var timber := m.begin()
	var collar := 3.0
	for i in 4:
		var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(i))
		var at := Vector3(0.0, g + 0.15, 0.0) + bb * Vector3(0.0, 0.0, collar * 0.5 + 0.2)
		m.block(timber, Transform3D(bb, at), Vector3(collar + 0.8, 0.45, 0.4))
		# the downhill side is the way onto the cage: stepped over, not a rail
		if i != 0:
			k.collider(Vector3(collar + 0.8, 1.1, 0.4), Transform3D(bb, at + Vector3.UP * 0.3), "wood")
	# the headframe: four legs leaning in to the head, braced every storey
	var head_y := g + 18.0
	var feet: Array = []
	var tops: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			feet.append(Vector3(0.0, g - 0.3, 0.0) + basis * Vector3(float(sx) * 3.4, 0.0, float(sz) * 3.4))
			tops.append(Vector3(0.0, head_y, 0.0) + basis * Vector3(float(sx) * 1.1, 0.0, float(sz) * 1.1))
	for i in 4:
		m.limb(timber, feet[i], tops[i], 0.2)
		var cap := CapsuleShape3D.new()
		cap.radius = 0.25
		var a3: Vector3 = feet[i]
		var b3: Vector3 = tops[i]
		cap.height = a3.distance_to(b3)
		var yv := (b3 - a3).normalized()
		var xv := yv.cross(Vector3.UP).normalized()
		k.collider_shape(cap, Transform3D(Basis(xv, yv, xv.cross(yv).normalized()), (a3 + b3) * 0.5), "wood")
	var order := [0, 1, 3, 2]
	for lvl in 4:
		var t := (float(lvl) + 1.0) / 4.6
		for e in 4:
			var a: Vector3 = (feet[order[e]] as Vector3).lerp(tops[order[e]], t)
			var b: Vector3 = (feet[order[(e + 1) % 4]] as Vector3).lerp(tops[order[(e + 1) % 4]], t)
			m.limb(timber, a, b, 0.12)
			if lvl < 3:
				var c: Vector3 = (feet[order[(e + 1) % 4]] as Vector3).lerp(tops[order[(e + 1) % 4]], (float(lvl) + 2.0) / 4.6)
				m.limb(timber, a, c, 0.08)
	# the head: a deck, and the wheel standing on it across the fall line
	m.block(timber, Transform3D(basis, Vector3(0.0, head_y + 0.15, 0.0)), Vector3(3.2, 0.3, 3.2))
	var wheel_c := Vector3(0.0, head_y + 2.1, 0.0)
	var wface := Basis(Vector3.UP, yaw + PI * 0.5)
	var wr := 1.9
	for i in 16:
		var a := TAU * (float(i) + 0.5) / 16.0
		m.block(timber, Transform3D(wface * Basis(Vector3.BACK, -a), wheel_c + wface * Vector3(sin(a) * wr, cos(a) * wr, 0.0)), Vector3(wr * 0.42, 0.16, 0.16))
	for i in 6:
		var a := TAU * float(i) / 6.0
		m.block(timber, Transform3D(wface * Basis(Vector3.BACK, -a), wheel_c + wface * Vector3(sin(a) * wr * 0.5, cos(a) * wr * 0.5, 0.0)), Vector3(0.1, wr, 0.1))
	for s in [-1.0, 1.0]:
		m.limb(timber, Vector3(0.0, head_y + 0.3, 0.0) + wface * Vector3(0.0, 0.0, float(s) * 0.4), wheel_c + wface * Vector3(0.0, 0.0, float(s) * 0.25), 0.1)
	# the back-stays, raking down uphill to the winding house's foot
	var house := -down * 12.0
	var stay_foot := k.on_ground(house.x, house.y, -0.2) + Vector3(down.x, 0.0, down.y) * 2.8
	for s in [-1.0, 1.0]:
		var top := Vector3(0.0, head_y - 1.5, 0.0) + basis * Vector3(float(s) * 1.0, 0.0, -1.0)
		m.limb(timber, stay_foot + Vector3(side.x, 0.0, side.y) * float(s) * 1.6, top, 0.16)
	await k.step()
	m.commit(timber, k.surface("timber", 0.55), "Headframe", true)
	if k.far:
		return
	var shaft := m.begin()
	m.block(shaft, Transform3D(basis, Vector3(0.0, g + 0.04, 0.0)), Vector3(collar, 0.05, collar))
	m.commit(shaft, PoiKit.plain(Color(0.01, 0.01, 0.01), 1.0), "Shaft")
	# the rope from the winding house over the wheel and down the shaft to the cage
	var rope := m.begin()
	m.limb(rope, k.on_ground(house.x, house.y, 0.2), wheel_c + Vector3(-down.x, 0.0, -down.y) * wr * 0.2 + Vector3.UP * wr, 0.03)
	var cage_top := Vector3(0.0, g + 2.6, 0.0)
	m.limb(rope, wheel_c + Vector3(down.x, 0.0, down.y) * 0.0 + Vector3.UP * 0.0, cage_top, 0.03)
	# down to the ground at the winding house's drum, so it hangs from something at both ends
	m.limb(rope, k.on_ground(house.x, house.y, 0.2), k.on_ground(house.x, house.y, 1.2), 0.03)
	await k.step()
	m.commit(rope, PoiKit.plain(Color(0.4, 0.34, 0.25), 0.9), "Rope")
	# the cage at the collar: a timber box open on the downhill side, its floor level with the ground
	var cage := m.begin()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.block(cage, Transform3D(basis, Vector3(0.0, g + 1.25, 0.0) + basis * Vector3(float(sx) * 0.8, 0.0, float(sz) * 0.8)), Vector3(0.12, 2.5, 0.12))
	m.block(cage, Transform3D(basis, Vector3(0.0, g + 2.55, 0.0)), Vector3(1.8, 0.12, 1.8))
	m.block(cage, Transform3D(basis, Vector3(0.0, g + 0.08, 0.0)), Vector3(1.7, 0.1, 1.7))
	m.block(cage, Transform3D(basis, Vector3(0.0, g + 1.1, 0.0) + basis * Vector3(0.0, 0.0, -0.8)), Vector3(1.6, 1.0, 0.06))
	await k.step()
	m.commit(cage, k.surface("planks", 0.5), "Cage")
	SITES._door(d, str(site.get("interior", "")), Vector3(0.0, g + 0.15, 0.0), yaw)
	k.marker("the_mouth", k.on_ground(down.x * 4.0 + side.x * 3.0, down.y * 4.0 + side.y * 3.0), false, true, 3.0)
	# the winding house: a plank hut with a roof of boards, its drum showing through the door
	var hut := m.begin()
	var hb := Basis(Vector3.UP, yaw)
	var hg := k.on_ground(house.x, house.y).y
	var hw := 4.6
	var hd := 3.8
	for i in 4:
		var bb := hb.rotated(Vector3.UP, PI * 0.5 * float(i))
		var span := hw if i % 2 == 0 else hd
		var off := (hd if i % 2 == 0 else hw) * 0.5
		var at := Vector3(house.x, hg + 1.3, house.y) + bb * Vector3(0.0, 0.0, off)
		if i == 0:
			# the door side, toward the shaft: two pieces either side of the door
			for s in [-1.0, 1.0]:
				var p := at + bb * Vector3(float(s) * (span * 0.5 - 0.9) * 0.5 + float(s) * 0.45, 0.0, 0.0)
				m.block(hut, Transform3D(bb, p), Vector3(span * 0.5 - 0.65, 2.6, 0.14))
				k.collider(Vector3(span * 0.5 - 0.65, 2.6, 0.14), Transform3D(bb, p), "wood")
			continue
		m.block(hut, Transform3D(bb, at), Vector3(span, 2.6, 0.14))
		k.collider(Vector3(span, 2.6, 0.14), Transform3D(bb, at), "wood")
	for s in [-1.0, 1.0]:
		var roof := Transform3D(hb * Basis(Vector3.RIGHT, float(s) * 0.45), Vector3(house.x, hg + 3.25, house.y) + hb * Vector3(0.0, 0.0, float(s) * hd * 0.24))
		m.block(hut, roof, Vector3(hw + 0.5, 0.08, hd * 0.6))
	await k.step()
	m.commit(hut, k.surface("planks", 0.6), "WindingHouse")
	var drum := m.begin()
	m.rod(drum, Transform3D(hb * Basis(Vector3.BACK, PI * 0.5), Vector3(house.x, hg + 1.2, house.y)), 0.6, 2.4)
	m.commit(drum, k.surface("timber", 0.5), "WindingDrum")
	# the spoil: grey heaps of broken granite down the slope, the oaks standing dead in them
	# (tips, PoiMasonry.spoil_heap: a smooth mound of it read as a tarpaulin over a heap)
	# (the painted beaten earth the other mines' tips have: the ground's scree texture, darkened, read
	# as brown cloth on a tip, puckered at its top like a sack's neck)
	var spoil_look := PoiKit.painted(5, GRANITE_SPOIL, 0.85, 0.85)
	var heaps := [[down * 10.0 + side * 2.0, 8.5, 3.6], [down * 17.0 - side * 3.0, 7.0, 2.8], [down * 23.0 + side * 1.5, 5.5, 1.8]]
	var loose: Array = []
	for hi in heaps.size():
		var h: Array = heaps[hi]
		await k.step()
		loose.append_array(m.spoil_heap(h[0], down, float(h[1]) * 0.85, float(h[2]), spoil_look, GRANITE_TINTS, hi == 2, "Spoil", 1.2))
	await k.step()
	m.spoil_stones(loose)
	var dead := m.begin()
	for i in 5:
		var p := down * k.rng.randf_range(8.0, 22.0) + side * k.rng.randf_range(-9.0, 9.0)
		var foot := k.on_ground(p.x, p.y, -0.5)
		var top := foot + Vector3(k.rng.randf_range(-0.4, 0.4), k.rng.randf_range(6.0, 9.0), k.rng.randf_range(-0.4, 0.4))
		_bole(dead, foot, top, 0.42, 0.18, k.rng, 10, 4)
		for j in 3:
			var from := foot.lerp(top, k.rng.randf_range(0.5, 0.9))
			var aa := k.rng.randf() * TAU
			m.limb(dead, from, from + Vector3(cos(aa), k.rng.randf_range(0.2, 0.8), sin(aa)).normalized() * k.rng.randf_range(1.5, 3.0), 0.07)
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.45
		cyl.height = 6.0
		k.collider_shape(cyl, Transform3D(Basis.IDENTITY, foot + Vector3.UP * 3.0), "wood")
	await k.step()
	m.commit(dead, PoiKit.painted(3, DEADWOOD, 0.6), "DeadOaks", true)
	# plank ways from the collar to the tip, and the tubs left on them
	var ways := m.begin()
	for s in [-1.0, 1.0]:
		var a := down * 2.2 + side * float(s) * 0.5
		var b := down * 9.0 + side * (2.0 + float(s) * 0.5)
		var mid := (a + b) * 0.5
		m.block(ways, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(b - a)), k.on_ground(mid.x, mid.y, 0.05)), Vector3(0.35, 0.08, a.distance_to(b)))
	await k.step()
	m.commit(ways, k.surface("planks", 0.8), "PlankWays")
	for t in [4.0, 7.0]:
		var p := down * float(t) + side * (float(t) - 2.0) * 0.28
		await k.step()
		k.place(k.prop("wheelbarrow"), k.on_ground(p.x, p.y), yaw + k.rng.randf_range(-0.2, 0.2))
	# the clerk's office: a stone hut with a lamp in its window, its door to the shaft
	var office := side * 10.0 - down * 3.0
	var ost := m.begin()
	var ob := Basis(Vector3.UP, PoiKit.yaw_of(-side))
	var og := k.on_ground(office.x, office.y).y
	for i in 4:
		var bb := ob.rotated(Vector3.UP, PI * 0.5 * float(i))
		var at := Vector3(office.x, og + 1.2, office.y) + bb * Vector3(0.0, 0.0, 1.8)
		var w := Transform3D(bb, at)
		m.block(ost, w, Vector3(3.8, 2.6, 0.4))
		k.collider(Vector3(3.8, 2.6, 0.4), w, "stone")
	m.block(ost, Transform3D(ob, Vector3(office.x, og + 2.6, office.y)), Vector3(4.2, 0.3, 4.2))
	await k.step()
	m.commit(ost, k.surface("stone", 0.6), "Office")
	var win := m.begin()
	var win_at := Vector3(office.x, og + 1.5, office.y) + ob * Vector3(0.6, 0.0, 2.02)
	m.block(win, Transform3D(ob, win_at), Vector3(0.7, 0.6, 0.04))
	m.commit(win, PoiKit.plain(Color(1.0, 0.8, 0.45), 0.5, 0.0, Color(1.0, 0.7, 0.35), 1.6), "OfficeLamp")
	k.light(win_at + ob * Vector3(0.0, 0.0, 0.6), Color(1.0, 0.75, 0.45), 1.4, 7.0)
	var desk_at := Vector3(office.x, og, office.y) + ob * Vector3(-0.6, 0.0, 2.9)
	k.marker("the_office", desk_at, true)
	await SITES._hook(d, site, Vector3(office.x, 0.0, office.y) + Vector3(-side.x, 0.0, -side.y) * 3.4 + Vector3(down.x, 0.0, down.y) * 2.0)
	await LAND._grass(d, "bracken", -down * 6.0 + side * -8.0, 6.0, 18)


## The masons' lodge: the Builders' quarrymen's hall, and before its door the block they were dressing
## when they left, squared on three faces and rough on the rest, on its rollers, the masons' marks cut
## in its face, a mallet still on it.
static func masons_lodge(d: PoiDressing) -> void:
	await _builders().ruins(d)
	var k := d.kit
	var m := d.masonry
	var f := _hall_frame(k)
	var grain: Vector2 = f["grain"]
	var perp: Vector2 = f["perp"]
	var mid: Vector2 = f["mid"]
	var at := mid - grain * 9.5 + perp * 1.5
	var yaw := PoiKit.yaw_of(grain)
	var basis := Basis(Vector3.UP, yaw + 0.12)
	var g := k.on_ground(at.x, at.y).y
	var stone := m.begin()
	var block_xf := Transform3D(basis, Vector3(at.x, g + 0.35 + 0.8, at.y))
	m.block(stone, block_xf, Vector3(1.8, 1.6, 3.2))
	# the rough end, not yet dressed
	m.ellipsoid(stone, Vector3(at.x, g + 1.1, at.y) + basis * Vector3(0.0, 0.0, -1.7), Vector3(1.0, 0.85, 0.5), basis)
	await k.step()
	m.commit(stone, k.surface("stone", 0.3), "DressedBlock", true)
	k.collider(Vector3(1.8, 1.6, 3.6), block_xf, "stone")
	var wood := m.begin()
	for z in [-1.0, 0.3, 1.4]:
		m.rod(wood, Transform3D(basis * Basis(Vector3.BACK, PI * 0.5), Vector3(at.x, g + 0.17, at.y) + basis * Vector3(0.0, 0.0, float(z))), 0.17, 2.4)
	await k.step()
	m.commit(wood, k.surface("timber", 0.5), "Rollers")
	var marks := m.begin()
	for i in 5:
		var p := Vector3(at.x, g + 0.6 + float(i % 2) * 0.55, at.y) + basis * Vector3(0.91, 0.0, -1.0 + float(i) * 0.5)
		m.block(marks, Transform3D(basis * Basis(Vector3.RIGHT, float(i) * 0.7), p), Vector3(0.02, 0.28, 0.05))
		m.block(marks, Transform3D(basis * Basis(Vector3.RIGHT, -float(i) * 0.5 + 0.9), p), Vector3(0.02, 0.24, 0.05))
	await k.step()
	m.commit(marks, PoiKit.plain(Color(0.12, 0.12, 0.11), 0.9), "MasonsMarks")
	if not k.far:
		k.place(k.prop("hammer"), Vector3(at.x, g + 1.95, at.y), yaw + 0.8, 1.0, false)


# --- the novel places (2026-10-04) --------------------------------------------------------------------
# The Told Hives, the Swainmote, the Silk Walk, the Noon Owl and the Knar: each a kind of place the
# game had none of, built from its own sentence. Kept apart from the builders above (new functions
# only), and cheap: a few batched meshes each, the kit's props where they serve.

## Dead oak, bleached: the Noon Owl's tree.
const BONEWOOD := {"base": "#d7d2c4", "accent": "#aaa392"}
## Turf on the Swainmote's benches.
const TURF := Color(0.24, 0.31, 0.15)
## Weaver silk on the posts: pale, with a wet shine.
const SILK := Color(0.9, 0.9, 0.93)
## Iron gone brown.
const RUSTED := Color(0.27, 0.19, 0.13)


## The point on a bole's axis (from `foot` to `top`) at height `y`, and the bole's radius there (as
## _bole draws it, before its ridges).
static func _axis_at(foot: Vector3, top: Vector3, ra: float, rb: float, y: float) -> Array:
	var t := clampf((y - foot.y) / maxf(top.y - foot.y, 0.01), 0.0, 1.0)
	var r := lerpf(ra, rb, t) * (1.0 + 0.22 * pow(maxf(0.0, 1.0 - t * 6.0), 2.0))
	return [foot.lerp(top, t), r]


## A trunk's collision: an upright cylinder from `foot_y` up `height`, `r` round, at local xz.
static func _trunk_collider(k: PoiKit, at: Vector2, foot_y: float, height: float, r: float, underfoot := "wood") -> void:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = height
	k.collider_shape(c, Transform3D(Basis(), Vector3(at.x, foot_y + height * 0.5, at.y)), underfoot)


## A ring of `n` limbs round `centre` in the plane whose normal is `normal`, radius `r`, rod `t` thick.
static func _hoop(m: PoiMasonry, st: SurfaceTool, centre: Vector3, normal: Vector3, r: float, t: float, n := 10) -> void:
	var nn := normal.normalized()
	var u := nn.cross(Vector3.UP)
	if u.length() < 0.01:
		u = Vector3.RIGHT
	u = u.normalized()
	var v := u.cross(nn).normalized()
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		m.limb(st, centre + (u * cos(a0) + v * sin(a0)) * r, centre + (u * cos(a1) + v * sin(a1)) * r, t)


## A small plank hut with a pitched bark roof and a door gap facing `face`: where somebody sleeps.
## Returns the floor's middle (local), for the `home` marker.
static func _bothy(d: PoiDressing, c: Vector2, face: Vector2, w := 3.0, l := 3.4) -> Vector3:
	var k := d.kit
	var m := d.masonry
	var b := Basis(Vector3.UP, PoiKit.yaw_of(face))
	var g := k.on_ground(c.x, c.y).y
	var walls := m.begin()
	var h := 1.9
	var parts := [
		[Vector3(0.0, 0.0, -l * 0.5), Vector3(w, h, 0.14)],
		[Vector3(-w * 0.5, 0.0, 0.0), Vector3(0.14, h, l)],
		[Vector3(w * 0.5, 0.0, 0.0), Vector3(0.14, h, l)],
		[Vector3(-w * 0.32, 0.0, l * 0.5), Vector3(w * 0.36, h, 0.14)],
		[Vector3(w * 0.32, 0.0, l * 0.5), Vector3(w * 0.36, h, 0.14)],
	]
	for p in parts:
		var off: Vector3 = p[0]
		var size: Vector3 = p[1]
		var xf := Transform3D(b, Vector3(c.x, g - 0.1 + h * 0.5, c.y) + b * off)
		m.block(walls, xf, size + Vector3(0.0, 0.2, 0.0))
		k.collider(size, xf, "wood")
	# the gables
	for s in [-1.0, 1.0]:
		var gx := Transform3D(b, Vector3(c.x, g + h + 0.4, c.y) + b * Vector3(0.0, 0.0, float(s) * l * 0.5))
		m.block(walls, gx, Vector3(w * 0.55, 0.8, 0.12))
	await k.step()
	m.commit(walls, k.surface("planks", 0.6), "Bothy")
	var roof := m.begin()
	for s in [-1.0, 1.0]:
		var rb := b * Basis(Vector3.BACK, float(s) * 0.62)
		var at := Vector3(c.x, g + h + 0.45, c.y) + b * Vector3(float(s) * w * 0.27, 0.0, 0.0)
		m.block(roof, Transform3D(rb, at), Vector3(w * 0.66, 0.12, l + 0.5))
	await k.step()
	m.commit(roof, PoiKit.painted(3, ROOTBARK, 0.5), "BothyRoof")
	k.collider(Vector3(w + 0.4, 0.3, l + 0.5), Transform3D(b, Vector3(c.x, g + h + 0.75, c.y)), "wood")
	return Vector3(c.x, g, c.y)


# --- the Told Hives -----------------------------------------------------------------------------------

## The Ashbys' bee-tree (strange_tree): a dead oak's bole thirteen metres tall, silver, with three
## broken limbs, girdled with log hives at every height and more hung on ropes from the limbs, a band
## of black cloth round every one; the low log standing on a stone at its foot (where the bees are
## told), a ladder up the bole, the skep bench under its bark roof, Linnet's bothy, foxgloves.
static func told_hives(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(-face.y, face.x)
	var g := k.on_ground(0.0, 0.0).y
	var foot := Vector3(0.0, g - 0.4, 0.0)
	var top := Vector3(0.3, g + 13.0, -0.2)
	var ra := 1.35
	var rb := 0.7
	var wood := m.begin()
	_bole(wood, foot, top, ra, rb, k.rng, 18, 12)
	# the broken limbs, high on three sides, each a stub with its end torn
	var tips: Array = []
	for i in 3:
		var h: float = [8.4, 10.3, 11.9][i]
		var a := TAU * float(i) / 3.0 + 0.5
		var ax: Array = _axis_at(foot, top, ra, rb, g + h)
		var root: Vector3 = ax[0]
		var dir := Vector3(sin(a), 0.32, cos(a)).normalized()
		var tip := root + dir * (float(ax[1]) + 2.8)
		m.limb(wood, root, tip, 0.3 - 0.05 * float(i))
		tips.append(tip)
	await k.step()
	m.commit(wood, PoiKit.painted(3, DEADWOOD, 0.35), "BeeTree", true)
	_trunk_collider(k, Vector2.ZERO, g - 0.2, 13.0, ra * 0.95)
	if k.far:
		return
	# the hives: hollow logs lashed upright to the bole at every height, and three hung on ropes
	var hives := m.begin()
	var lids := m.begin()
	var crepe := m.begin()
	var ropes := m.begin()
	var mouths := m.begin()
	var spots: Array = []   # [centre, outward, radius, length]
	for i in 7:
		var h := 2.6 + float(i) * 1.35
		var a := float(i) * 2.2 + 0.3
		var ax: Array = _axis_at(foot, top, ra, rb, g + h)
		var out := Vector3(sin(a), 0.0, cos(a))
		spots.append([(ax[0] as Vector3) + out * (float(ax[1]) * 1.12 + 0.3), out, 0.3, 1.05])
	for i in tips.size():
		var tip: Vector3 = tips[i]
		var hang := tip + Vector3.DOWN * (1.4 + 0.3 * float(i))
		m.limb(ropes, tip, hang + Vector3.UP * 0.5, 0.025)
		spots.append([hang, Vector3(tip.x, 0.0, tip.z).normalized(), 0.27, 0.9])
	for s in spots:
		var c: Vector3 = s[0]
		var out: Vector3 = s[1]
		var r: float = s[2]
		var length: float = s[3]
		m.rod(hives, Transform3D(Basis(), c), r, length)
		m.block(lids, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), c + Vector3.UP * (length * 0.5 + 0.04)), Vector3(r * 2.4, 0.08, r * 2.4))
		for y in [-0.22, 0.22]:
			m.rod(crepe, Transform3D(Basis(), c + Vector3.UP * float(y) * length), r + 0.015, 0.09)
		# the flight hole, a dark slot on the outer side
		m.block(mouths, Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)), c + out * (r - 0.02) + Vector3.DOWN * length * 0.3), Vector3(0.14, 0.05, 0.06))
		# the lashing back to the bole (the lashed ones)
		if length > 1.0:
			m.limb(ropes, c + Vector3.UP * length * 0.35 + out * r, c + Vector3.UP * length * 0.35 - out * (r + 0.35), 0.022)
	# the low log, on a flat stone at the bole's foot on the clearing's side: where the bees are told
	var low := face * (ra + 0.95)
	var lg := k.on_ground(low.x, low.y).y
	var low_c := Vector3(low.x, lg + 0.2 + 0.65, low.y)
	m.rod(hives, Transform3D(Basis(), low_c), 0.4, 1.3)
	m.block(lids, Transform3D(Basis(Vector3.UP, 0.4), low_c + Vector3.UP * 0.69), Vector3(0.95, 0.08, 0.95))
	for y in [-0.3, 0.3]:
		m.rod(crepe, Transform3D(Basis(), low_c + Vector3.UP * float(y)), 0.415, 0.1)
	m.block(mouths, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), low_c + Vector3(face.x, 0.0, face.y) * 0.39 + Vector3.DOWN * 0.4), Vector3(0.18, 0.05, 0.06))
	k.collider(Vector3(0.8, 1.5, 0.8), Transform3D(Basis(), low_c + Vector3.DOWN * 0.1), "wood")
	await k.step()
	m.commit(hives, PoiKit.painted(3, DEADWOOD, 0.6), "BeeHives")
	m.commit(lids, PoiKit.painted(3, ROOTBARK, 0.5), "BeeHiveLids")
	m.commit(crepe, PoiKit.plain(Color(0.03, 0.03, 0.035), 0.95), "BeeCrepe")
	m.commit(ropes, PoiKit.plain(Color(0.42, 0.36, 0.26), 0.9), "BeeRopes")
	m.commit(mouths, PoiKit.plain(Color(0.02, 0.015, 0.01), 1.0), "BeeMouths")
	var stone := m.begin()
	m.ellipsoid(stone, Vector3(low.x, lg + 0.02, low.y), Vector3(0.62, 0.2, 0.55))
	m.commit(stone, k.surface("stone", 0.6), "LowLogStone")
	k.touchable("KnockLowLog", low_c + Vector3(face.x, 0.0, face.y) * 0.5, "Knock on the low log", "core:dialogue/told_hives_knock", "", false)
	# the bees at their mouths: a haze of them round three of the hives and the low log
	for i in [1, 4, 8]:
		var s: Array = spots[mini(i, spots.size() - 1)]
		k.puffs((s[0] as Vector3) + (s[1] as Vector3) * 0.6, Vector3(0.7, 0.6, 0.7), 0.12, 26, Color(0.1, 0.08, 0.03, 0.9), 0.07, 3.0)
	k.puffs(low_c + Vector3(face.x, 0.0, face.y) * 0.7, Vector3(0.5, 0.4, 0.5), 0.1, 18, Color(0.1, 0.08, 0.03, 0.9), 0.07, 3.0)
	# the ladder up the bole on the far side from the low log
	var lad := m.begin()
	var lf := -face * (ra + 2.6) + side * 0.4
	var lfg := k.on_ground(lf.x, lf.y).y
	var lax: Array = _axis_at(foot, top, ra, rb, g + 4.2)
	var ltop: Vector3 = (lax[0] as Vector3) - Vector3(face.x, 0.0, face.y) * (float(lax[1]) + 0.15) + Vector3(side.x, 0.0, side.y) * 0.4
	var lbase := Vector3(lf.x, lfg - 0.05, lf.y)
	var across := Vector3(side.x, 0.0, side.y) * 0.24
	for s in [-1.0, 1.0]:
		m.limb(lad, lbase + across * float(s), ltop + across * float(s), 0.04)
	for r in 11:
		var p := lbase.lerp(ltop, (float(r) + 0.6) / 12.0)
		m.limb(lad, p - across, p + across, 0.025)
	await k.step()
	m.commit(lad, k.surface("timber", 0.5), "Ladder")
	# the skep bench under its bark roof, out in the clearing toward the road
	var bc := face * 8.5 + side * 3.0
	var by := k.on_ground(bc.x, bc.y).y
	var bb := Basis(Vector3.UP, PoiKit.yaw_of(side))
	var bench := m.begin()
	m.block(bench, Transform3D(bb, Vector3(bc.x, by + 0.58, bc.y)), Vector3(2.8, 0.09, 0.65))
	for sx in [-1.2, 1.2]:
		m.block(bench, Transform3D(bb, Vector3(bc.x, by + 0.27, bc.y) + bb * Vector3(float(sx), 0.0, 0.0)), Vector3(0.12, 0.6, 0.55))
	for p in [Vector3(-1.5, 0.0, -0.6), Vector3(1.5, 0.0, -0.6), Vector3(-1.5, 0.0, 0.55), Vector3(1.5, 0.0, 0.55)]:
		var ph := 2.05 if p.z < 0.0 else 1.6
		var pp: Vector3 = Vector3(bc.x, 0.0, bc.y) + bb * p
		var pg := k.on_ground(pp.x, pp.z).y
		m.block(bench, Transform3D(bb, Vector3(pp.x, pg + ph * 0.5 - 0.05, pp.z)), Vector3(0.12, ph + 0.1, 0.12))
	await k.step()
	m.commit(bench, k.surface("timber", 0.5), "SkepBench")
	k.collider(Vector3(2.8, 0.62, 0.65), Transform3D(bb, Vector3(bc.x, by + 0.31, bc.y)), "wood")
	var broof := m.begin()
	m.block(broof, Transform3D(bb * Basis(Vector3.RIGHT, -0.26), Vector3(bc.x, by + 1.9, bc.y)), Vector3(3.5, 0.08, 1.75))
	m.commit(broof, PoiKit.painted(3, ROOTBARK, 0.5), "SkepRoof")
	var skeps := m.begin()
	for i in 4:
		var sp := Vector3(bc.x, by + 0.63, bc.y) + bb * Vector3(-1.0 + float(i) * 0.66, 0.0, 0.0)
		m.ellipsoid(skeps, sp + Vector3.UP * 0.2, Vector3(0.27, 0.36, 0.27))
	m.commit(skeps, PoiKit.plain(Color(0.66, 0.53, 0.3), 0.95), "BeeSkeps")
	var stand := Vector3(bc.x, 0.0, bc.y) + bb * Vector3(0.0, 0.0, 1.3)
	k.marker("the_skeps", k.on_ground(stand.x, stand.z), true)
	var pot := Vector3(bc.x, 0.0, bc.y) + bb * Vector3(1.9, 0.0, 0.9)
	k.place(k.prop("bucket"), k.on_ground(pot.x, pot.z), 0.3, 1.0, false)
	k.puffs(k.on_ground(pot.x, pot.z, 0.5), Vector3(0.08, 0.05, 0.08), 0.5, 10, Color(0.75, 0.74, 0.7, 0.35), 0.5, 3.0)
	# Linnet's bothy across the clearing from the bench, its door to the tree
	var hc := -face * 9.0 + side * 6.5
	var floor_at: Vector3 = await _bothy(d, hc, (-hc).normalized())
	k.marker("home", floor_at, true)
	# foxgloves in the clearing, clover by the bench
	await LAND._grass(d, "foxglove", -side * 8.0 + face * 2.0, 6.0, 26)
	await LAND._grass(d, "foxglove", side * 9.0 - face * 2.0, 5.0, 18)
	await LAND._grass(d, "clover", face * 10.0, 5.0, 20)
	k.marker("the_bee_tree", k.on_ground(face.x * 3.2, face.y * 3.2), false)


# --- the Swainmote ------------------------------------------------------------------------------------

## The Woodfolk's court of custom (market_field): three tiers of turf benches edged with split oak in
## a horseshoe open to the road, a pollard oak as broad as a cottage at the closed end with the
## steward's chair cut into its bole and its poles cut back last winter, the dog-gauge on its post
## before the chair with the customs board beside it, the hound pound of woven hazel off to one side,
## and the steward's bothy behind the oak.
static func swainmote(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(-face.y, face.x)
	# the pollard at the ring's closed end
	var oc := -face * 10.5
	var og := k.on_ground(oc.x, oc.y).y
	var foot := Vector3(oc.x, og - 0.4, oc.y)
	var top := Vector3(oc.x, og + 4.6, oc.y)
	var ra := 2.15
	var wood := m.begin()
	_bole(wood, foot, top, ra, 1.85, k.rng, 22, 8)
	# the boll: the knuckle the poles come out of, and the poles, cut back last winter
	m.ellipsoid(wood, top + Vector3.UP * 0.2, Vector3(2.3, 1.0, 2.2))
	for i in 9:
		var a := TAU * float(i) / 9.0 + k.rng.randf_range(-0.2, 0.2)
		var root := top + Vector3(sin(a) * 1.3, 0.5, cos(a) * 1.3)
		var lean := Vector3(sin(a) * 0.45, 1.0, cos(a) * 0.45).normalized()
		m.limb(wood, root, root + lean * k.rng.randf_range(4.0, 6.5), k.rng.randf_range(0.12, 0.2))
	await k.step()
	m.commit(wood, PoiKit.painted(3, ROOTBARK, 0.35), "Pollard", true)
	_trunk_collider(k, oc, og - 0.2, 5.6, ra * 0.95)
	# the tiers: a horseshoe of three steps of turf round the floor, open toward the road
	var turf := m.begin()
	var edges := m.begin()
	for tier in 3:
		var r := 7.2 + float(tier) * 1.9
		var hgt := 0.38 * float(tier + 1)
		var bays := 9 + tier * 2
		var a0 := deg_to_rad(40.0)
		var a1 := deg_to_rad(320.0)
		for b in bays:
			var t0 := lerpf(a0, a1, float(b) / float(bays))
			var t1 := lerpf(a0, a1, float(b + 1) / float(bays))
			var tm := (t0 + t1) * 0.5
			# angles measured from the road side (face), round through the sides to the oak and back
			var dir := face * cos(tm) + side * sin(tm)
			var c := dir * r
			# the bay at the oak is left for the pollard and the chair
			if absf(tm - PI) < deg_to_rad(26.0 if tier == 0 else 34.0):
				continue
			var bg := minf(k.on_ground(c.x, c.y).y, k.on_ground(c.x + dir.x * 0.9, c.y + dir.y * 0.9).y)
			var chord := 2.0 * r * sin((t1 - t0) * 0.5) + 0.12
			var bas := Basis(Vector3.UP, PoiKit.yaw_of(dir))
			var xf := Transform3D(bas, Vector3(c.x, bg - 0.2 + (hgt + 0.2) * 0.5, c.y))
			m.block(turf, xf, Vector3(chord, hgt + 0.2, 1.9))
			k.collider(Vector3(chord, hgt + 0.2, 1.9), xf, "dirt")
			# the split oak along its front edge
			var ef := Transform3D(bas, Vector3(c.x, bg + hgt - 0.12, c.y) - Vector3(dir.x, 0.0, dir.y) * 0.95)
			m.block(edges, ef, Vector3(chord, 0.3, 0.14))
		await k.step()
	m.commit(turf, PoiKit.plain(TURF, 0.97), "MoteTiers", true)
	m.commit(edges, PoiKit.painted(3, DEADWOOD, 0.4), "MoteTierEdges")
	if k.far:
		return
	# the chair cut into the bole, facing the floor
	var into := (Vector2.ZERO - oc).normalized()
	var cb := Basis(Vector3.UP, PoiKit.yaw_of(into))
	var cr: float = _axis_at(foot, top, ra, 1.85, og + 0.8)[1]
	var chair_at := Vector3(oc.x, og, oc.y) + Vector3(into.x, 0.0, into.y) * (cr - 0.05)
	var chair := m.begin()
	m.block(chair, Transform3D(cb, chair_at + Vector3.UP * 1.1 + cb * Vector3(0.0, 0.0, 0.02)), Vector3(1.3, 1.9, 0.08))
	var seat := m.begin()
	m.block(seat, Transform3D(cb, chair_at + Vector3.UP * 0.5 + cb * Vector3(0.0, 0.0, 0.32)), Vector3(1.1, 0.12, 0.62))
	for s in [-1.0, 1.0]:
		m.block(seat, Transform3D(cb, chair_at + Vector3.UP * 0.75 + cb * Vector3(float(s) * 0.6, 0.0, 0.28)), Vector3(0.14, 0.5, 0.6))
	m.block(seat, Transform3D(cb, chair_at + Vector3.UP * 0.22 + cb * Vector3(0.0, 0.0, 0.32)), Vector3(1.0, 0.44, 0.55))
	await k.step()
	m.commit(chair, PoiKit.plain(Color(0.1, 0.07, 0.05), 0.95), "ChairHollow")
	m.commit(seat, PoiKit.painted(3, ROOTBARK, 0.25), "StewardsChair")
	k.collider(Vector3(1.3, 0.56, 0.7), Transform3D(cb, chair_at + Vector3.UP * 0.28 + cb * Vector3(0.0, 0.0, 0.3)), "wood")
	var chair_floor := Vector2(oc.x, oc.y) + into * (cr + 1.4)
	k.marker("the_chair", k.on_ground(chair_floor.x, chair_floor.y), true)
	# the dog-gauge: an oak post with the iron stirrup on its hook, before the chair
	var gc := into * 0.0 + oc + into * (cr + 4.2)
	var post := m.begin()
	var ptop := m.post(post, gc, 1.05, 0.2)
	var iron := m.begin()
	m.limb(iron, ptop + Vector3(into.x, 0.0, into.y) * 0.1 + Vector3.DOWN * 0.05, ptop + Vector3(into.x, 0.0, into.y) * 0.22 + Vector3.UP * 0.03, 0.025)
	var ring_c := ptop + Vector3(into.x, 0.0, into.y) * 0.24 - Vector3.UP * 0.22
	_hoop(m, iron, ring_c, Vector3(side.x, 0.0, side.y), 0.19, 0.022, 10)
	# the customs board beside it on two posts
	var bd := gc + side * 1.6
	var bdb := Basis(Vector3.UP, PoiKit.yaw_of(into))
	for s in [-1.0, 1.0]:
		var bp := bd + Vector2(side.x, side.y) * 0.55 * float(s)
		m.post(post, bp, 1.5, 0.12)
	m.block(post, Transform3D(bdb, k.on_ground(bd.x, bd.y, 1.12)), Vector3(1.3, 0.62, 0.06))
	await k.step()
	m.commit(post, PoiKit.painted(3, DEADWOOD, 0.4), "GaugePost")
	m.commit(iron, PoiKit.plain(RUSTED, 0.7, 0.5), "DogGauge")
	k.touchable("Gauge", ring_c, "Look at the dog-gauge", "core:dialogue/swainmote_gauge", "", false)
	k.marker("the_gauge", k.on_ground(gc.x + into.x * 1.0 + side.x * 0.8, gc.y + into.y * 1.0 + side.y * 0.8), false)
	# the hound pound: a ring of hazel stakes woven round, a gap for its gate, off the horseshoe's side
	var pc := side * 14.5 + face * 1.0
	var pg := k.on_ground(pc.x, pc.y).y
	var weave := m.begin()
	var stakes: Array = []
	var n := 12
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		var p := pc + Vector2(sin(a), cos(a)) * 2.0
		stakes.append(k.on_ground(p.x, p.y))
	for i in n:
		var a: Vector3 = stakes[i]
		var b: Vector3 = stakes[i + 1]
		m.limb(weave, a + Vector3.DOWN * 0.1, a + Vector3.UP * 1.15, 0.045)
		# the gate gap faces the floor
		var mid := (a + b) * 0.5
		if Vector2(mid.x - pc.x, mid.z - pc.y).normalized().dot(-side) > 0.93:
			continue
		for y in [0.3, 0.6, 0.9]:
			m.limb(weave, a + Vector3.UP * float(y), b + Vector3.UP * float(y) + Vector3.UP * 0.03, 0.035)
		var span := b - a
		var bb2 := Basis(Vector3.UP, atan2(span.x, span.z))
		k.collider(Vector3(0.12, 1.15, span.length()), Transform3D(bb2, mid + Vector3.UP * 0.58), "wood")
	await k.step()
	m.commit(weave, PoiKit.painted(3, DEADWOOD, 0.6), "HoundPound")
	k.place(k.prop("bowl"), Vector3(pc.x, pg, pc.y) + Vector3(0.6, 0.0, 0.3), 0.0, 1.0, false)
	k.place(k.prop("hay_bale"), Vector3(pc.x, pg, pc.y) + Vector3(-0.5, 0.0, -0.6), 0.5, 0.7, true)
	var pound_stand := pc - side * 2.9
	k.marker("the_pound", k.on_ground(pound_stand.x, pound_stand.y), true)
	# the steward's bothy behind the oak, and the notice post for the mote's work at the road side
	var hc := -face * 19.0 + side * 6.5
	var floor_at: Vector3 = await _bothy(d, hc, (oc - hc).normalized())
	k.marker("home", floor_at, true)
	var jb := face * 11.5 + side * 2.6
	k.job_board(k.on_ground(jb.x, jb.y), PoiKit.yaw_of(face))
	await LAND._grass(d, "bracken", -face * 15.0 - side * 8.0, 5.0, 16)
	await LAND._grass(d, "clover", Vector2.ZERO, 4.5, 26)


# --- the Silk Walk ------------------------------------------------------------------------------------

## Margery Laithe's ropewalk (mill): fifty-six metres ruled straight across the approach, a post with a
## crossed head every five, three strands of weaver silk shining along the heads; the twisting jack at
## the head (a wheel on an oak frame, three hooks on its face) under a bark shed; the top on its sledge
## partway down; the anchor post at the foot; racks of white hanks by the shed and a basket of black
## ones she will not lay; her bothy beside the head.
static func silk_walk(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var along := Vector2(-face.y, face.x)
	var half := 26.0
	var head := -along * half
	var foot_end := along * half
	var posts := m.begin()
	var heads: Array = []
	var count := 11
	for i in count + 1:
		var p := head.lerp(foot_end, float(i) / float(count)) + face * k.rng.randf_range(-0.05, 0.05)
		var tp := m.post(posts, p, 1.45, 0.16)
		var hb := Basis(Vector3.UP, PoiKit.yaw_of(along))
		m.block(posts, Transform3D(hb, tp + Vector3.DOWN * 0.08), Vector3(1.0, 0.1, 0.12))
		heads.append(tp)
	await k.step()
	m.commit(posts, k.surface("timber", 0.45), "WalkPosts", true)
	# the strands: three, a span at a time, sagging a hand between the heads
	var silk := m.begin()
	var lanes := [-0.32, 0.0, 0.32]
	for i in heads.size() - 1:
		var a: Vector3 = heads[i]
		var b: Vector3 = heads[i + 1]
		for off in lanes:
			var o := Vector3(face.x, 0.0, face.y) * float(off)
			var sag := (a + b) * 0.5 + o + Vector3.DOWN * 0.12
			m.limb(silk, a + o + Vector3.UP * 0.0, sag, 0.012)
			m.limb(silk, sag, b + o, 0.012)
	await k.step()
	m.commit(silk, PoiKit.plain(SILK, 0.18, 0.35, Color(0.55, 0.55, 0.6), 0.25), "SilkStrands", true)
	if k.far:
		return
	# the jack at the head: an oak frame, the wheel standing across the walk, three hooks on its face
	var jb := Basis(Vector3.UP, PoiKit.yaw_of(along))
	var jg := k.on_ground(head.x, head.y).y
	var jack_c := Vector3(head.x, jg, head.y) - Vector3(along.x, 0.0, along.y) * 1.6
	var frame := m.begin()
	for s in [-1.0, 1.0]:
		var fp := jack_c + jb * Vector3(float(s) * 0.85, 0.0, 0.0)
		var fpg := k.on_ground(fp.x, fp.z).y
		m.block(frame, Transform3D(jb, Vector3(fp.x, fpg + 0.75, fp.z)), Vector3(0.16, 1.6, 0.5))
	var wheel_c := jack_c + Vector3.UP * 1.1
	m.block(frame, Transform3D(jb, wheel_c), Vector3(1.85, 0.12, 0.12))
	var wheel := m.begin()
	_hoop(m, wheel, wheel_c + Vector3(along.x, 0.0, along.y) * 0.12, Vector3(along.x, 0.0, along.y), 0.72, 0.04, 14)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var spoke := jb * Vector3(cos(a), sin(a), 0.0) * 0.72
		m.limb(wheel, wheel_c + Vector3(along.x, 0.0, along.y) * 0.12, wheel_c + Vector3(along.x, 0.0, along.y) * 0.12 + spoke, 0.03)
	m.limb(wheel, wheel_c - Vector3(along.x, 0.0, along.y) * 0.1 + jb * Vector3(0.55, 0.0, 0.0), wheel_c - Vector3(along.x, 0.0, along.y) * 0.1 + jb * Vector3(0.55, -0.35, 0.0), 0.03)
	var hooks := m.begin()
	for off in lanes:
		var hk := wheel_c + Vector3(along.x, 0.0, along.y) * 0.3 + Vector3(face.x, 0.0, face.y) * float(off) * 0.6 + Vector3.UP * 0.3
		m.limb(hooks, hk - Vector3(along.x, 0.0, along.y) * 0.18, hk, 0.02)
		# the strand from the hook to the first post's head
		var first: Vector3 = heads[0]
		m.limb(silk, hk, first + Vector3(face.x, 0.0, face.y) * float(off), 0.012)
	await k.step()
	m.commit(frame, k.surface("timber", 0.5), "JackFrame")
	m.commit(wheel, k.surface("timber", 0.4), "JackWheel")
	m.commit(hooks, PoiKit.plain(RUSTED, 0.6, 0.6), "JackHooks")
	k.collider(Vector3(1.9, 1.6, 0.6), Transform3D(jb, jack_c + Vector3.UP * 0.8), "wood")
	k.touchable("TurnJack", wheel_c + Vector3(along.x, 0.0, along.y) * -0.5, "Turn the jack", "core:dialogue/silk_walk_jack", "", false)
	var jstand := Vector2(jack_c.x, jack_c.z) - along * 1.2 + face * 1.0
	k.marker("the_jack", k.on_ground(jstand.x, jstand.y), true)
	# the shed over the jack: four posts and a bark roof
	var shed := m.begin()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var sp := Vector2(jack_c.x, jack_c.z) + face * 1.9 * float(sx) + along * 1.6 * float(sz)
			m.post(shed, sp, 2.3 if sz < 0.0 else 2.0, 0.14)
	await k.step()
	m.commit(shed, k.surface("timber", 0.5), "ShedPosts")
	var sroof := m.begin()
	m.block(sroof, Transform3D(jb * Basis(Vector3.RIGHT, 0.09), jack_c + Vector3.UP * 2.25), Vector3(4.4, 0.1, 3.9))
	m.commit(sroof, PoiKit.painted(3, ROOTBARK, 0.5), "ShedRoof")
	# the top on its sledge, partway down the walk, the strands running into its grooves
	var tc := head.lerp(foot_end, 0.38)
	var tg := k.on_ground(tc.x, tc.y).y
	var sledge := m.begin()
	for s in [-1.0, 1.0]:
		m.block(sledge, Transform3D(jb, Vector3(tc.x, tg + 0.08, tc.y) + Vector3(face.x, 0.0, face.y) * 0.45 * float(s)), Vector3(0.12, 0.16, 1.6))
	m.block(sledge, Transform3D(jb, Vector3(tc.x, tg + 0.2, tc.y)), Vector3(1.1, 0.08, 1.3))
	m.block(sledge, Transform3D(jb, Vector3(tc.x, tg + 0.7, tc.y)), Vector3(0.14, 1.0, 0.14))
	var top_c := Vector3(tc.x, tg + 1.25, tc.y)
	m.limb(sledge, top_c - Vector3(along.x, 0.0, along.y) * 0.3, top_c + Vector3(along.x, 0.0, along.y) * 0.2, 0.2)
	await k.step()
	m.commit(sledge, k.surface("timber", 0.55), "TopSledge")
	k.collider(Vector3(1.1, 0.3, 1.6), Transform3D(jb, Vector3(tc.x, tg + 0.15, tc.y)), "wood")
	k.marker("the_top", k.on_ground(tc.x + face.x * 3.0, tc.y + face.y * 3.0), false)
	# the anchor at the foot: a heavy post braced back, an iron ring at its head
	var ac := foot_end + along * 1.5
	var anchor := m.begin()
	var atop := m.post(anchor, ac, 1.7, 0.3)
	var ag := k.on_ground(ac.x, ac.y).y
	m.limb(anchor, Vector3(ac.x, ag - 0.1, ac.y) + Vector3(along.x, 0.0, along.y) * 1.4, atop + Vector3.DOWN * 0.3, 0.09)
	m.commit(anchor, k.surface("timber", 0.6), "AnchorPost")
	var ring_iron := m.begin()
	_hoop(m, ring_iron, atop + Vector3.DOWN * 0.25 - Vector3(along.x, 0.0, along.y) * 0.17, Vector3(along.x, 0.0, along.y), 0.1, 0.02, 8)
	m.commit(ring_iron, PoiKit.plain(RUSTED, 0.6, 0.6), "AnchorRing")
	# the hank racks by the shed: white hanks hung on pegs, and a basket of the black ones
	var rc := Vector2(jack_c.x, jack_c.z) + face * 4.2
	var rg := k.on_ground(rc.x, rc.y).y
	var rack := m.begin()
	m.frame(rack, rc, PoiKit.yaw_of(face), 2.4, 1.7, 0.1)
	await k.step()
	m.commit(rack, k.surface("timber", 0.5), "HankRack")
	var hanks := m.begin()
	for i in 5:
		var hp := Vector3(rc.x, rg + 1.25, rc.y) + Vector3(along.x, 0.0, along.y) * (-0.9 + float(i) * 0.45)
		m.ellipsoid(hanks, hp, Vector3(0.07, 0.38, 0.07))
	m.commit(hanks, PoiKit.plain(SILK, 0.3, 0.2), "SilkHanks")
	var basket_at := Vector2(rc.x, rc.y) + along * 1.8 + face * 0.6
	k.place(k.prop("basket"), k.on_ground(basket_at.x, basket_at.y), 0.4, 1.0, true)
	var black := m.begin()
	var bkg := k.on_ground(basket_at.x, basket_at.y).y
	for i in 3:
		m.ellipsoid(black, Vector3(basket_at.x, bkg + 0.42 + float(i) * 0.06, basket_at.y) + Vector3(k.rng.randf_range(-0.1, 0.1), 0.0, k.rng.randf_range(-0.1, 0.1)), Vector3(0.16, 0.08, 0.12))
	m.commit(black, PoiKit.plain(Color(0.05, 0.04, 0.035), 0.4), "BlackHanks")
	# her bothy beside the head, its door to the walk
	var hc := Vector2(jack_c.x, jack_c.z) - face * 7.5 - along * 2.0
	var floor_at: Vector3 = await _bothy(d, hc, face)
	k.marker("home", floor_at, true)
	await LAND._grass(d, "bracken", face * 7.0, 5.0, 14)
	await LAND._grass(d, "bracken", -face * 6.0 + along * 10.0, 5.0, 14)


# --- the Noon Owl -------------------------------------------------------------------------------------

## The white oak (strange_tree): a dead oak bleached to bone, its top torn off in splinters, two broken
## limbs, and high in its bole one round hollow, black, with two points of yellow far in it; under it
## the listening ring of hazel hurdles with a gap toward the road and log seats inside, the ground in
## the ring grey with owl-pellets and feathers; Gammer Hoole's bothy off to one side.
static func noon_owl(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(-face.y, face.x)
	var g := k.on_ground(0.0, 0.0).y
	var foot := Vector3(0.0, g - 0.4, 0.0)
	var top := Vector3(-0.2, g + 11.5, 0.25)
	var ra := 1.3
	var rb := 0.85
	var wood := m.begin()
	_bole(wood, foot, top, ra, rb, k.rng, 18, 11, true)
	# the torn top: splinters standing up out of the break
	for i in 7:
		var a := TAU * float(i) / 7.0 + k.rng.randf_range(-0.3, 0.3)
		var base := top + Vector3(sin(a), 0.0, cos(a)) * rb * 0.7 + Vector3.DOWN * 0.3
		var tip := base + Vector3(sin(a) * 0.2, k.rng.randf_range(0.6, 2.2), cos(a) * 0.2)
		m.limb(wood, base, tip, k.rng.randf_range(0.07, 0.16))
	# a lid over the break, so it is not hollow from above
	m.ellipsoid(wood, top + Vector3.DOWN * 0.15, Vector3(rb * 0.95, 0.25, rb * 0.95))
	for i in 2:
		var h: float = [6.2, 8.9][i]
		var a := PoiKit.yaw_of(side) + PI * float(i) + 0.4
		var ax: Array = _axis_at(foot, top, ra, rb, g + h)
		var dir := Vector3(sin(a), 0.5, cos(a)).normalized()
		m.limb(wood, ax[0], (ax[0] as Vector3) + dir * (float(ax[1]) + 1.8), 0.24)
	await k.step()
	m.commit(wood, PoiKit.painted(3, BONEWOOD, 0.25), "WhiteOak", true)
	_trunk_collider(k, Vector2.ZERO, g - 0.2, 11.5, ra * 0.95)
	# the hollow, high on the bole on the ring's side: a black mouth, its lip proud of the bark
	var hax: Array = _axis_at(foot, top, ra, rb, g + 8.0)
	var out := Vector3(face.x, 0.0, face.y)
	var hb := Basis(Vector3.UP, PoiKit.yaw_of(face))
	var mouth_at: Vector3 = (hax[0] as Vector3) + out * (float(hax[1]) * 1.02)
	var lip := m.begin()
	m.ellipsoid(lip, mouth_at - out * 0.05, Vector3(0.78, 0.82, 0.22), hb)
	m.commit(lip, PoiKit.painted(3, BONEWOOD, 0.5), "HollowLip", true)
	var dark := m.begin()
	m.ellipsoid(dark, mouth_at + out * 0.06, Vector3(0.6, 0.64, 0.14), hb)
	m.commit(dark, PoiKit.plain(Color(0.01, 0.01, 0.012), 1.0), "Hollow", true)
	if k.far:
		return
	var eyes := m.begin()
	for s in [-1.0, 1.0]:
		m.ellipsoid(eyes, mouth_at + out * 0.17 + Vector3(side.x, 0.0, side.y) * 0.09 * float(s) + Vector3.UP * 0.05, Vector3(0.035, 0.035, 0.02), hb)
	m.commit(eyes, PoiKit.plain(Color(0.9, 0.7, 0.2), 0.4, 0.0, Color(1.0, 0.75, 0.2), 1.4), "OwlEyes")
	# the listening ring: hurdles of woven hazel on a circle, a gap toward the road
	var ring_r := 6.2
	var weave := m.begin()
	var n := 14
	var pts: Array = []
	for i in n + 1:
		var a := PoiKit.yaw_of(face) + deg_to_rad(18.0) + (TAU - deg_to_rad(36.0)) * float(i) / float(n)
		var p := Vector2(sin(a), cos(a)) * ring_r
		pts.append(k.on_ground(p.x, p.y))
	for i in n:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		m.limb(weave, a + Vector3.DOWN * 0.1, a + Vector3.UP * 0.95, 0.04)
		for y in [0.25, 0.5, 0.75]:
			m.limb(weave, a + Vector3.UP * float(y), b + Vector3.UP * (float(y) + 0.03), 0.03)
		var span := b - a
		k.collider(Vector3(0.1, 0.95, span.length()), Transform3D(Basis(Vector3.UP, atan2(span.x, span.z)), (a + b) * 0.5 + Vector3.UP * 0.47), "wood")
	var last: Vector3 = pts[n]
	m.limb(weave, last + Vector3.DOWN * 0.1, last + Vector3.UP * 0.95, 0.04)
	await k.step()
	m.commit(weave, PoiKit.painted(3, DEADWOOD, 0.6), "ListeningRing")
	# log seats inside the ring, facing the bole
	var seats := m.begin()
	for i in 5:
		var a := PoiKit.yaw_of(face) + deg_to_rad(-70.0 + float(i) * 35.0)
		var c := Vector2(sin(a), cos(a)) * 4.1
		var tang := Vector2(cos(a), -sin(a))
		var cg := k.on_ground(c.x, c.y).y
		var e1 := Vector3(c.x + tang.x * 0.8, cg + 0.2, c.y + tang.y * 0.8)
		var e2 := Vector3(c.x - tang.x * 0.8, cg + 0.2, c.y - tang.y * 0.8)
		m.limb(seats, e1, e2, 0.22)
		k.collider(Vector3(0.44, 0.42, 1.9), Transform3D(Basis(Vector3.UP, atan2(tang.x, tang.y)), Vector3(c.x, cg + 0.21, c.y)), "wood")
	await k.step()
	m.commit(seats, k.surface("timber", 0.6), "LogSeats")
	var gammer := face * 3.1 + side * 0.6
	k.marker("the_ring", k.on_ground(gammer.x, gammer.y), true)
	# pellets and feathers on the ground in the ring
	var pellets := m.begin()
	for i in 46:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(ra + 0.4, ring_r - 0.6)
		var p := Vector2(sin(a), cos(a)) * r
		m.ellipsoid(pellets, k.on_ground(p.x, p.y, 0.02), Vector3(0.05, 0.035, 0.08), Basis(Vector3.UP, k.rng.randf() * TAU))
	m.commit(pellets, PoiKit.plain(Color(0.45, 0.43, 0.4), 0.95), "OwlPellets")
	var feathers := m.begin()
	for i in 18:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(ra + 0.3, ring_r - 0.5)
		var p := Vector2(sin(a), cos(a)) * r
		m.block(feathers, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), k.on_ground(p.x, p.y, 0.015)), Vector3(0.05, 0.008, 0.22))
	m.commit(feathers, PoiKit.plain(Color(0.7, 0.68, 0.64), 0.9), "OwlFeathers")
	k.touchable("WhiteOak", k.on_ground(face.x * (ra + 0.6), face.y * (ra + 0.6), 1.2), "Put your hand on the white oak", "core:dialogue/noon_owl_hollow", "", false)
	# Gammer Hoole's bothy off to the side, door to the ring
	var hc := side * 12.0 - face * 2.0
	var floor_at: Vector3 = await _bothy(d, hc, (-hc).normalized(), 2.6, 3.0)
	k.marker("home", floor_at, true)
	await LAND._grass(d, "bracken", -side * 10.0, 5.0, 16)
	await LAND._grass(d, "fern", -face * 9.0, 5.0, 16)


# --- the Knar -----------------------------------------------------------------------------------------

## The gall's flesh: the oak's own bark, swollen and gone the brown of a cut cork.
static func _gall_look() -> BaseMaterial3D:
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(OAK_BARK % "albedo"):
		mat.albedo_texture = load(OAK_BARK % "albedo")
	mat.albedo_color = Color(0.74, 0.55, 0.38)
	mat.roughness = 0.93
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / 2.6
	return mat


## The Knar (delve): an oak of the Greatwood with a gall grown round its foot as big as a barn, warted
## and bored, the black weeping out of the bores; the oak standing up out of its top with its crown
## gone grey on one side; the split in its front where the wrights cut their door (the site's door);
## the vats steaming on their fires before it and a smoke over them that stands above the canopy; the
## Circle's barrels, the gall-strings drying on their racks, the wrights' notice.
static func the_knar(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var def := ContentDB.get_or_empty(d.poi_id)
	var site: Dictionary = def.get("site", {})
	var face := _facing(k)
	var side := Vector2(-face.y, face.x)
	var yaw := PoiKit.yaw_of(face)
	var fb := Basis(Vector3.UP, yaw)
	var gc := -face * 4.0
	var gg := k.on_ground(gc.x, gc.y).y
	var big_r := 9.0
	var big_h := 7.0
	var cy := gg + 1.5
	var centre := Vector3(gc.x, cy, gc.y)
	var gall := m.begin()
	m.ellipsoid(gall, centre, Vector3(big_r, big_h, big_r))
	# the warts: lumps on its shoulders and flanks, none over the split in its front
	var warts: Array = []
	for i in 15:
		var a := TAU * float(i) / 15.0 + k.rng.randf_range(-0.15, 0.15)
		var el := k.rng.randf_range(-0.05, 0.8)
		var dir2 := Vector2(sin(a), cos(a))
		if dir2.dot(face) > 0.88 and el < 0.45:
			continue
		var ce := sqrt(1.0 - el * el)
		var p := centre + Vector3(dir2.x * big_r * ce, el * big_h, dir2.y * big_r * ce)
		var n := (p - centre).normalized()
		var s := k.rng.randf_range(1.8, 3.6)
		var c := p + n * s * 0.2
		m.ellipsoid(gall, c, Vector3(s, s * 0.8, s * 1.1), Basis(Vector3.UP, k.rng.randf() * TAU))
		warts.append([c, s])
	# the split's lips either side of the door
	var door_d := big_r * sqrt(1.0 - pow((gg + 1.2 - cy) / big_h, 2.0))
	for s in [-1.0, 1.0]:
		var lc := centre + Vector3(face.x, 0.0, face.y) * (door_d - 0.4) + Vector3(side.x, 0.0, side.y) * 1.45 * float(s) + Vector3.DOWN * 0.2
		m.ellipsoid(gall, lc, Vector3(1.0, 2.4, 1.1), fb)
	await k.step()
	m.commit(gall, _gall_look(), "Knar", true)
	# the oak standing up out of the gall's top
	var oak := k.tree("giant_oak")
	if oak != "":
		k.place(oak, Vector3(gc.x, cy + big_h * 0.45, gc.y), k.rng.randf() * TAU, 1.15, false, Vector3.ZERO, true)
	# its crown gone grey on the side away from the road: dead limbs out of the bole
	var dead := m.begin()
	for i in 6:
		var a := PoiKit.yaw_of(-face) + k.rng.randf_range(-1.0, 1.0)
		var h := cy + big_h + 3.0 + float(i) * 1.4
		var root := Vector3(gc.x, h, gc.y)
		var dir := Vector3(sin(a), k.rng.randf_range(0.25, 0.6), cos(a)).normalized()
		var tip := root + dir * k.rng.randf_range(6.0, 8.5)
		m.limb(dead, root, tip, k.rng.randf_range(0.22, 0.34))
		var fork := tip + Vector3(k.rng.randf_range(-1.0, 1.0), 1.5, k.rng.randf_range(-1.0, 1.0))
		m.limb(dead, tip, fork, 0.1)
	await k.step()
	m.commit(dead, PoiKit.painted(3, DEADWOOD, 0.3), "DeadCrown", true)
	# the gall's collision: its body where a body can walk into it, and the low warts
	_trunk_collider(k, gc, gg - 1.0, big_h * 0.6 + 2.5, big_r * 0.96, "wood")
	for w in warts:
		var wc: Vector3 = w[0]
		if wc.y - gg < 4.0:
			var sph := SphereShape3D.new()
			sph.radius = float(w[1]) * 0.85
			k.collider_shape(sph, Transform3D(Basis(), wc), "wood")
	if k.far:
		return
	# the split and the door in it
	var split := m.begin()
	var split_at := centre + Vector3(face.x, 0.0, face.y) * (door_d - 0.3) + Vector3.DOWN * 0.1
	m.ellipsoid(split, Vector3(split_at.x, gg + 1.6, split_at.z), Vector3(1.05, 1.9, 0.45), fb)
	# the bores, black and wet, and the black run down from some of them
	for i in 22:
		var a := TAU * float(i) / 22.0 + k.rng.randf_range(-0.12, 0.12)
		var el := k.rng.randf_range(-0.02, 0.62)
		var dir2 := Vector2(sin(a), cos(a))
		if dir2.dot(face) > 0.9 and el < 0.45:
			continue
		var ce := sqrt(1.0 - el * el)
		var n := Vector3(dir2.x * ce, el * big_h / big_r, dir2.y * ce).normalized()
		var p := centre + Vector3(dir2.x * big_r * ce, el * big_h, dir2.y * big_r * ce)
		var bb := Basis.looking_at(-n, Vector3.UP if absf(n.y) < 0.95 else Vector3.BACK)
		var r := k.rng.randf_range(0.35, 0.6)
		m.ellipsoid(split, p + n * 0.02, Vector3(r, r, 0.12), bb)
		if k.rng.randf() < 0.6:
			var run := k.rng.randf_range(0.8, 2.0)
			m.ellipsoid(split, p + n * 0.0 + Vector3.DOWN * (r + run * 0.5), Vector3(0.12, run * 0.5, 0.1), bb)
	await k.step()
	m.commit(split, PoiKit.plain(Color(0.025, 0.02, 0.018), 0.25), "GallBores")
	var door_at := k.on_ground(gc.x + face.x * (door_d + 0.2), gc.y + face.y * (door_d + 0.2), 0.1)
	SITES._door(d, str(site.get("interior", "")), door_at, yaw)
	k.marker("the_split", door_at + Vector3(face.x, 0.0, face.y) * 3.0, false, false)
	k.bounce_light(Vector3(split_at.x, gg + 1.6, split_at.z) + Vector3(face.x, 0.0, face.y) * 1.5, Color(0.95, 0.75, 0.5), 0.8, 6.0)
	# the vats, three on their fire-rings in an arc before the gall, steaming
	var vats := m.begin()
	var hoops := m.begin()
	var stones := m.begin()
	var smoke_at := Vector3.ZERO
	for i in 3:
		var a := yaw + deg_to_rad(-48.0 + 48.0 * float(i))
		var vc := gc + Vector2(sin(a), cos(a)) * (big_r + 7.0)
		var vg := k.on_ground(vc.x, vc.y).y
		var base := Vector3(vc.x, vg, vc.y)
		for j in 7:
			var sa := TAU * float(j) / 7.0
			m.ellipsoid(stones, base + Vector3(sin(sa) * 1.15, 0.12, cos(sa) * 1.15), Vector3(0.32, 0.26, 0.28), Basis(Vector3.UP, sa))
		m.rod(vats, Transform3D(Basis(), base + Vector3.UP * 0.95), 0.95, 1.1)
		for y in [0.6, 1.3]:
			m.rod(hoops, Transform3D(Basis(), base + Vector3.UP * float(y)), 0.97, 0.07)
		# the black in it, level with its lip
		m.rod(hoops, Transform3D(Basis(), base + Vector3.UP * 1.46), 0.88, 0.03)
		k.collider(Vector3(2.1, 1.5, 2.1), Transform3D(Basis(), base + Vector3.UP * 0.75), "wood")
		k.light(base + Vector3.UP * 0.35, Color(1.0, 0.6, 0.3), 1.6, 7.0)
		k.puffs(base + Vector3.UP * 1.6, Vector3(0.5, 0.1, 0.5), 0.9, 10, Color(0.62, 0.6, 0.57, 0.4), 1.4, 4.5)
		if i == 1:
			smoke_at = base
	await k.step()
	m.commit(vats, k.surface("planks", 0.7), "Vats")
	m.commit(hoops, PoiKit.plain(Color(0.06, 0.05, 0.045), 0.3, 0.4), "VatHoops")
	m.commit(stones, k.surface("stone", 0.7), "FireRings")
	# the smoke that stands over the Greatwood: a slow dark column from the middle vat's fire
	k.puffs(smoke_at + Vector3.UP * 2.0, Vector3(0.8, 0.3, 0.8), 2.4, 16, Color(0.36, 0.34, 0.32, 0.42), 3.6, 9.0)
	k.marker("the_vats", k.on_ground(gc.x + face.x * (big_r + 11.0), gc.y + face.y * (big_r + 11.0)), false)
	# the Circle's barrels, stacked by the track
	var bar_c := gc + face * (big_r + 6.0) + side * 9.5
	var rows: Array = []
	for i in 6:
		var bp := bar_c + side * (float(i % 3) * 0.85) + face * (floorf(float(i) / 3.0) * 0.9)
		rows.append([k.on_ground(bp.x, bp.y), k.rng.randf() * TAU, 1.0])
	await _row(k, k.prop("barrel"), rows, true)
	# the gall-strings drying on their racks, the far side from the barrels
	var rack := m.begin()
	for j in 2:
		var rc := gc + face * (big_r + 4.5 + float(j) * 2.6) - side * 10.0
		var lintel := m.frame(rack, rc, yaw, 2.6, 1.9, 0.12)
		for s in 6:
			var hang := lintel + fb * Vector3(-1.05 + float(s) * 0.42, 0.0, 0.0)
			m.limb(rack, hang, hang + Vector3.DOWN * 0.9, 0.012)
			for b in 4:
				m.ellipsoid(rack, hang + Vector3.DOWN * (0.18 + float(b) * 0.2), Vector3(0.07, 0.07, 0.07))
	await k.step()
	m.commit(rack, k.surface("timber", 0.6), "GallRacks")
	# the wrights' notice by the track to the split
	await SITES._hook(d, site, Vector3(face.x * (big_r + 3.5) + side.x * 3.0 + gc.x, 0.0, face.y * (big_r + 3.5) + side.y * 3.0 + gc.y))
	await LAND._grass(d, "bracken", gc + side * 15.0 - face * 2.0, 6.0, 18)
	await LAND._grass(d, "fern", gc - side * 15.0 - face * 3.0, 6.0, 18)


# --- the Casting Dell ---------------------------------------------------------------------------------

## One cast antler lying on the ground: a curved beam and its tines, flat on the turf, into `st`.
static func _cast_antler(m: PoiMasonry, st: SurfaceTool, k: PoiKit, at: Vector2, yaw: float, size: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var pts: Array = []
	for i in 5:
		var t := float(i) / 4.0
		var p := Vector3(at.x, 0.0, at.y) + b * Vector3(sin(t * 1.4) * 0.35 * size, 0.0, t * 1.0 * size)
		pts.append(k.on_ground(p.x, p.z, 0.05 * size))
	for i in 4:
		m.limb(st, pts[i], pts[i + 1], 0.04 * size)
	for i in [1, 2, 3]:
		var root: Vector3 = pts[i]
		var tip := root + b * Vector3(0.28 * size, 0.06 * size, 0.12 * size)
		m.limb(st, root, tip, 0.025 * size)


## The harts' casting ground (hidden_valley): a hollow of bracken white with cast antlers, ringed by a
## palisade of stakes each crowned with the year's best antler standing up; a flat stone at its head
## with the one the dell gives set apart on it; boulders at the mouth where the Warden stands.
static func casting_dell(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(-face.y, face.x)
	# the stakes: sixteen round the rim, a gap at the mouth toward the road, each with its antler
	var stakes := m.begin()
	var crowns := m.begin()
	var ring_r := 13.0
	for i in 16:
		var a := PoiKit.yaw_of(face) + deg_to_rad(20.0) + (TAU - deg_to_rad(40.0)) * float(i) / 15.0
		var p := Vector2(sin(a), cos(a)) * ring_r
		var top := m.post(stakes, p, 2.2 + k.rng.randf_range(-0.2, 0.3), 0.14)
		# the antler on the stake's head: two beams spreading up and out, tines on each
		var out := Vector3(sin(a), 0.0, cos(a))
		var across := Vector3(cos(a), 0.0, -sin(a))
		for s in [-1.0, 1.0]:
			var beam_top := top + across * 0.55 * float(s) + Vector3.UP * 0.75 + out * 0.15
			m.limb(crowns, top, beam_top, 0.045)
			for t in 3:
				var root := top.lerp(beam_top, 0.35 + 0.25 * float(t))
				m.limb(crowns, root, root + Vector3.UP * 0.3 + out * 0.12 + across * 0.08 * float(s), 0.025)
	await k.step()
	m.commit(stakes, PoiKit.painted(3, DEADWOOD, 0.5), "DellStakes", true)
	m.commit(crowns, PoiKit.plain(ANTLER, 0.75), "DellAntlers", true)
	if k.far:
		return
	# the cast antlers in the bracken, white through the green
	var cast := m.begin()
	for i in 34:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(2.5, ring_r - 1.5)
		var p := Vector2(sin(a), cos(a)) * r
		_cast_antler(m, cast, k, p, k.rng.randf() * TAU, k.rng.randf_range(0.7, 1.15))
	await k.step()
	m.commit(cast, PoiKit.plain(ANTLER.lightened(0.15), 0.8), "CastAntlers")
	k.marker("the_bracken", k.on_ground(side.x * 5.0, side.y * 5.0), false)
	# the stone at the dell's head with the one it gives
	var sc := -face * 8.0
	var sg := k.on_ground(sc.x, sc.y).y
	var stone := m.begin()
	m.ellipsoid(stone, Vector3(sc.x, sg + 0.15, sc.y), Vector3(1.1, 0.42, 0.85), Basis(Vector3.UP, PoiKit.yaw_of(face)))
	m.commit(stone, k.surface("stone", 0.6), "DellStone")
	k.collider(Vector3(2.0, 0.5, 1.5), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), Vector3(sc.x, sg + 0.25, sc.y)), "stone")
	var given := m.begin()
	var gb := Basis(Vector3.UP, PoiKit.yaw_of(side))
	var g0 := Vector3(sc.x, sg + 0.6, sc.y) - gb * Vector3(0.0, 0.0, 0.6)
	var g1 := Vector3(sc.x, sg + 0.62, sc.y) + gb * Vector3(0.0, 0.0, 0.6)
	m.limb(given, g0, g1, 0.06)
	for t in 6:
		var root := g0.lerp(g1, 0.15 + 0.14 * float(t))
		var dir := Vector3(face.x, 0.0, face.y) * (1.0 if t % 2 == 0 else -1.0)
		m.limb(given, root, root + dir * 0.3 + Vector3.UP * 0.18, 0.03)
	m.commit(given, PoiKit.plain(ANTLER.darkened(0.05), 0.6), "GivenAntler")
	k.touchable("DellStone", Vector3(sc.x, sg + 0.8, sc.y) + Vector3(face.x, 0.0, face.y) * 0.9, "Look at the antler on the stone", "core:dialogue/casting_dell_stone", "", false)
	k.marker("the_stone", k.on_ground(sc.x + face.x * 1.8, sc.y + face.y * 1.8), false)
	# boulders either side of the mouth, where the Warden stands rooted
	var rocks: Array = []
	for s in [-1.0, 1.0]:
		var bp := face * ring_r + side * 3.2 * float(s)
		rocks.append([k.on_ground(bp.x, bp.y, -0.3), k.rng.randf() * TAU, k.rng.randf_range(1.1, 1.5)])
	await _row(k, k.rock("boulder"), rocks, true)
	k.marker("the_mouth", k.on_ground(face.x * (ring_r - 2.0), face.y * (ring_r - 2.0)), false)
	await LAND._grass(d, "bracken", Vector2.ZERO, ring_r - 2.0, 60)


# --- the Letter Oak -----------------------------------------------------------------------------------

## The Woodfolk's post (strange_tree): a living oak by the road with a ring of hazel posts round it,
## threads strung from post to post, and on the threads the letters folded small, hundreds, white to
## brown with age; the bark box for new ones at the oak's foot on the road side.
static func letter_oak(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var oak := k.tree("giant_oak")
	if oak != "":
		k.place(oak, k.on_ground(0.0, 0.0, -0.1), k.rng.randf() * TAU, 0.75, true, Vector3.ZERO, true)
	if k.far:
		return
	var posts := m.begin()
	var thread := m.begin()
	var letters := m.begin()
	var old := m.begin()
	var n := 9
	var r := 5.2
	var tops: Array = []
	for i in n:
		var a := PoiKit.yaw_of(face) + TAU * float(i) / float(n) + deg_to_rad(20.0)
		tops.append(m.post(posts, Vector2(sin(a), cos(a)) * r, 1.9, 0.1))
	for i in n:
		var a: Vector3 = tops[i]
		var b: Vector3 = tops[(i + 1) % n]
		for row in 2:
			var drop := 0.12 + 0.45 * float(row)
			var mid := (a + b) * 0.5 + Vector3.DOWN * (drop + 0.15)
			var a2 := a + Vector3.DOWN * drop
			var b2 := b + Vector3.DOWN * drop
			m.limb(thread, a2, mid, 0.008)
			m.limb(thread, mid, b2, 0.008)
			for j in 7:
				var t := (float(j) + 0.5) / 7.0
				var p := a2.lerp(mid, t * 2.0) if t < 0.5 else mid.lerp(b2, t * 2.0 - 1.0)
				var span := (b - a).normalized()
				var lb := Basis(Vector3.UP, atan2(span.x, span.z) + PI * 0.5) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.2, 0.2))
				var target := old if k.rng.randf() < 0.25 else letters
				m.block(target, Transform3D(lb, p + Vector3.DOWN * 0.1), Vector3(0.16, 0.18, 0.01))
	await k.step()
	m.commit(posts, k.surface("timber", 0.5), "LetterPosts")
	m.commit(thread, PoiKit.plain(Color(0.55, 0.5, 0.42), 0.9), "LetterThreads")
	m.commit(letters, PoiKit.plain(Color(0.86, 0.83, 0.74), 0.9), "Letters")
	m.commit(old, PoiKit.plain(Color(0.55, 0.45, 0.32), 0.95), "OldLetters")
	# the bark box at the foot on the road side
	var bx := face * (r + 1.0)
	var bg := k.on_ground(bx.x, bx.y).y
	var box := m.begin()
	var bb := Basis(Vector3.UP, PoiKit.yaw_of(face))
	m.block(box, Transform3D(bb, Vector3(bx.x, bg + 0.55, bx.y)), Vector3(0.12, 1.1, 0.12))
	m.block(box, Transform3D(bb, Vector3(bx.x, bg + 1.2, bx.y)), Vector3(0.5, 0.35, 0.35))
	m.block(box, Transform3D(bb * Basis(Vector3.RIGHT, -0.2), Vector3(bx.x, bg + 1.42, bx.y)), Vector3(0.6, 0.05, 0.45))
	m.commit(box, PoiKit.painted(3, ROOTBARK, 0.5), "LetterBox")
	k.collider(Vector3(0.5, 1.4, 0.4), Transform3D(bb, Vector3(bx.x, bg + 0.7, bx.y)), "wood")
	k.marker("the_box", k.on_ground(bx.x + face.x * 0.9, bx.y + face.y * 0.9), false)
	var near: Vector3 = tops[0]
	k.touchable("LetterThreads", near + Vector3.DOWN * 0.4 + Vector3(face.x, 0.0, face.y) * 0.3, "Look for letters going your way", "core:dialogue/letter_oak_threads", "", false)
	await LAND._grass(d, "clover", face * (r + 3.0), 3.0, 14)


# --- the Pannage Pound --------------------------------------------------------------------------------

## The Lower Wold's pannage ground (fold): a ring of turf bank topped with woven hazel round the oaks,
## a gate toward the road with the agister's tally-post beside it, the commoners' pigs rooting inside,
## a swill-trough, the scald-tub, and the agister's bothy outside the gate.
static func pannage_pound(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(-face.y, face.x)
	var r := 15.0
	var bank := m.begin()
	var weave := m.begin()
	var n := 22
	var pts: Array = []
	for i in n + 1:
		var a := PoiKit.yaw_of(face) + deg_to_rad(9.0) + (TAU - deg_to_rad(18.0)) * float(i) / float(n)
		pts.append(Vector2(sin(a), cos(a)) * r)
	for i in n:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var mid := (p0 + p1) * 0.5
		var span := p1 - p0
		var bb := Basis(Vector3.UP, atan2(span.x, span.y))
		var g := minf(k.on_ground(p0.x, p0.y).y, k.on_ground(p1.x, p1.y).y)
		m.ellipsoid(bank, Vector3(mid.x, g, mid.y), Vector3(1.3, 0.75, span.length() * 0.62), bb)
		var a3 := k.on_ground(p0.x, p0.y, 0.6)
		var b3 := k.on_ground(p1.x, p1.y, 0.6)
		m.limb(weave, a3 + Vector3.DOWN * 0.3, a3 + Vector3.UP * 0.9, 0.05)
		for y in [0.25, 0.55, 0.8]:
			m.limb(weave, a3 + Vector3.UP * float(y), b3 + Vector3.UP * float(y), 0.035)
		k.collider(Vector3(1.6, 1.6, span.length()), Transform3D(bb, Vector3(mid.x, g + 0.8, mid.y)), "dirt")
	var last: Vector2 = pts[n]
	var lg := k.on_ground(last.x, last.y, 0.6)
	m.limb(weave, lg + Vector3.DOWN * 0.3, lg + Vector3.UP * 0.9, 0.05)
	await k.step()
	m.commit(bank, PoiKit.plain(TURF, 0.97), "PannageBank", true)
	m.commit(weave, PoiKit.painted(3, DEADWOOD, 0.6), "PannageHazel", true)
	if k.far:
		return
	# the agister's tally-post at the gate, notched up its faces
	var tc := face * (r + 1.2) + side * 2.6
	var tally := m.begin()
	var ttop := m.post(tally, tc, 2.4, 0.22)
	var tg := k.on_ground(tc.x, tc.y).y
	var notches := m.begin()
	for i in 14:
		var y := tg + 0.5 + float(i) * 0.12
		m.block(notches, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), Vector3(tc.x, y, tc.y) + Vector3(face.x, 0.0, face.y) * 0.112), Vector3(0.16, 0.02, 0.01))
	m.block(tally, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), ttop + Vector3.DOWN * 0.8 + Vector3(face.x, 0.0, face.y) * 0.13), Vector3(0.45, 0.32, 0.03))
	await k.step()
	m.commit(tally, PoiKit.painted(3, DEADWOOD, 0.4), "TallyPost")
	m.commit(notches, PoiKit.plain(Color(0.12, 0.1, 0.08), 0.9), "TallyNotches")
	k.marker("the_tally", k.on_ground(tc.x + face.x * 1.3, tc.y + face.y * 1.3), true)
	# the pigs, rooting
	var pig := k.prop("pig")
	var pigs: Array = []
	for i in 9:
		var a := k.rng.randf_range(0.0, TAU)
		var pr := k.rng.randf_range(3.0, r - 3.0)
		pigs.append(k.on_ground(sin(a) * pr, cos(a) * pr))
	for p in pigs:
		k.place(pig, p, k.rng.randf() * TAU, k.rng.randf_range(0.85, 1.1), true)
		await k.step()
	# the trough, the scald-tub
	var trc := -face * 4.0 + side * 3.0
	var trg := k.on_ground(trc.x, trc.y).y
	var trough := m.begin()
	var trb := Basis(Vector3.UP, PoiKit.yaw_of(side))
	m.block(trough, Transform3D(trb, Vector3(trc.x, trg + 0.22, trc.y)), Vector3(0.7, 0.44, 2.4))
	m.commit(trough, k.surface("timber", 0.6), "SwillTrough")
	k.collider(Vector3(0.7, 0.44, 2.4), Transform3D(trb, Vector3(trc.x, trg + 0.22, trc.y)), "wood")
	var tub_at := face * (r + 4.0) - side * 3.0
	k.place(k.prop("barrel"), k.on_ground(tub_at.x, tub_at.y), 0.2, 1.2, true)
	# the agister's bothy outside the gate
	var hc := face * (r + 6.5) - side * 7.5
	var floor_at: Vector3 = await _bothy(d, hc, side)
	k.marker("home", floor_at, true)
	k.marker("the_bank", k.on_ground(-face.x * (r - 2.0), -face.y * (r - 2.0)), false)
	await LAND._grass(d, "bracken", -face * 6.0 - side * 4.0, 5.0, 16)


# --- the Thornwell ------------------------------------------------------------------------------------

## The Briar's thorn: near black, green where it is young.
const THORN := {"base": "#2e3324", "accent": "#1c2016"}


## A collision capsule along a limb from `a` to `b` (local).
static func _limb_collider(k: PoiKit, a: Vector3, b: Vector3, r: float, underfoot := "wood") -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.1:
		return
	var y := dir / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = length + r * 2.0
	k.collider_shape(cap, Transform3D(Basis(x, y, x.cross(y).normalized()), (a + b) * 0.5), underfoot)


## The Builders' well in the Greatwood (delve): a ring of their black fused stone fourteen paces across
## with the stair's black mouth inside it (the site's door), and out of it the Briar's root burst up in
## a crown of thorn arches higher than the oaks, thorns along them as long as a forearm; the Layers'
## cut thorn stacked round, Edda Layward's bothy, the layers' cairn by the way in.
static func thornwell(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var def := ContentDB.get_or_empty(d.poi_id)
	var site: Dictionary = def.get("site", {})
	var face := _facing(k)
	var side := Vector2(-face.y, face.x)
	var yaw := PoiKit.yaw_of(face)
	var g := k.on_ground(0.0, 0.0).y
	# the ring of black stone, its gap toward the road
	var ring := m.begin()
	m.drum(ring, Transform3D(Basis(), Vector3(0.0, g - 0.2, 0.0)), 7.0, 1.3, 0.25, yaw, true)
	await k.step()
	m.commit(ring, k.surface("oroth", 0.3), "WellRing", true)
	# the crown: arches of the root from the well's mouth out over the ring and down into the wood
	var thorn := m.begin()
	var spikes := m.begin()
	var feet: Array = []
	var arches := 8
	for i in arches:
		var a := yaw + PI / float(arches) + TAU * float(i) / float(arches) + k.rng.randf_range(-0.12, 0.12)
		var b := a + k.rng.randf_range(0.45, 0.7)
		var ra := k.rng.randf_range(2.6, 3.6)
		var rb := k.rng.randf_range(13.0, 17.0)
		var pa := k.on_ground(sin(a) * ra, cos(a) * ra, -0.6)
		var pb := k.on_ground(sin(b) * rb, cos(b) * rb, -0.6)
		var apex := g + k.rng.randf_range(24.0, 34.0)
		var ctrl := (pa + pb) * 0.5
		ctrl.y = 2.0 * apex - (pa.y + pb.y) * 0.5
		var segs := 16
		var prev := pa
		for s in segs:
			var t := float(s + 1) / float(segs)
			var p := pa * (1.0 - t) * (1.0 - t) + ctrl * 2.0 * t * (1.0 - t) + pb * t * t
			var r := lerpf(0.95, 0.65, t) * (1.0 - 0.35 * sin(t * PI))
			m.limb(thorn, prev, p, r)
			# thorns along it, standing out from the bark
			for j in 2:
				var along := (p - prev).normalized()
				var out := along.cross(Vector3(sin(float(j) * 2.4 + t * 9.0), 0.4, cos(float(j) * 2.4 + t * 9.0))).normalized()
				var root := prev.lerp(p, 0.3 + 0.4 * float(j)) + out * r * 0.9
				m.limb(spikes, root, root + out * k.rng.randf_range(0.5, 0.9) + along * 0.15, 0.055)
			if s < 2:
				_limb_collider(k, prev, p, r * 0.9)
			if s >= segs - 2:
				_limb_collider(k, prev, p, r * 0.9)
			prev = p
		feet.append(pb)
		await k.step()
	m.commit(thorn, PoiKit.painted(3, THORN, 0.4), "ThornCrown", true)
	m.commit(spikes, PoiKit.plain(Color(0.2, 0.19, 0.13), 0.7), "Thorns", true)
	if k.far:
		return
	# the stair's mouth inside the ring, black, and the door at its lip
	var mouth := m.begin()
	m.ellipsoid(mouth, Vector3(0.0, g + 0.02, 0.0), Vector3(4.6, 0.05, 4.6))
	m.commit(mouth, PoiKit.plain(Color(0.015, 0.015, 0.02), 1.0), "WellMouth")
	var door_at := k.on_ground(face.x * 4.3, face.y * 4.3, 0.05)
	SITES._door(d, str(site.get("interior", "")), door_at, yaw)
	k.marker("the_stair_head", k.on_ground(face.x * 9.5, face.y * 9.5), false)
	k.bounce_light(door_at + Vector3.UP * 1.5, Color(0.7, 0.85, 0.65), 0.7, 7.0)
	# the Layers' cut thorn, laid in stacks outside the ring
	var cut := m.begin()
	for st in 3:
		var a := yaw + deg_to_rad(70.0 + 55.0 * float(st))
		var c := Vector2(sin(a), cos(a)) * 11.0
		var along := Vector2(cos(a), -sin(a))
		var cg := k.on_ground(c.x, c.y).y
		for j in 7:
			var off := Vector3(sin(a), 0.0, cos(a)) * k.rng.randf_range(-0.6, 0.6) + Vector3.UP * (0.25 + float(j % 3) * 0.3)
			var e1 := Vector3(c.x + along.x * 2.2, cg, c.y + along.y * 2.2) + off
			var e2 := Vector3(c.x - along.x * 2.2, cg, c.y - along.y * 2.2) + off + Vector3.UP * k.rng.randf_range(-0.1, 0.1)
			m.limb(cut, e1, e2, k.rng.randf_range(0.12, 0.2))
		k.collider(Vector3(4.8, 1.2, 1.5), Transform3D(Basis(Vector3.UP, atan2(along.x, along.y)), Vector3(c.x, cg + 0.6, c.y)), "wood")
	await k.step()
	m.commit(cut, PoiKit.painted(3, THORN, 0.6), "CutThorn")
	var stand := side * 12.5 + face * 6.0
	k.marker("the_cut_thorn", k.on_ground(stand.x, stand.y), true)
	k.place(k.prop("hammer"), k.on_ground(stand.x + face.x * 1.2, stand.y + face.y * 1.2), 0.6, 1.0, false)
	# Edda's bothy off to the side, door to the well
	var hc := side * 17.0 + face * 9.0
	var floor_at: Vector3 = await _bothy(d, hc, (-hc).normalized())
	k.marker("home", floor_at, true)
	await SITES._hook(d, site, Vector3(face.x * 10.5 - side.x * 3.0, 0.0, face.y * 10.5 - side.y * 3.0))
	await LAND._grass(d, "bracken", -face * 14.0, 6.0, 18)
	await LAND._grass(d, "briar_vine", -side * 12.0, 5.0, 14)
