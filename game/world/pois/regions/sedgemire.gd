extends RefCounted
## Sedgemire's own place builders (docs/WORLD_LIFE.md). A POI def with `"builder": "<name>"` is built
## by the static function of that name here, in place of its kind's builder. Only the Sedgemire
## region's author edits this file, so six regions can build at once without meeting.
##
##   static func drovers_hall(d: PoiDressing) -> void:
##       await PoiDressing.kind_builders().LAND.farmstead(d)    # its kind's, then more
##       var k := d.kit                                          # PoiKit: on_ground, prop, masonry ...
##
## The kind stays the def's `kind` (what the tests, the map and the audit call it); a builder named
## here that is missing is said in the log and the place is built as its kind.
##
## The marsh's own pieces, shared by the builders below: a reedfolk stilt-house (a plank deck on
## posts, reed walls, a thatch of reed, a flight of plank steps and a lantern on an arm by the
## door), a lantern pole with its lantern hung from the arm, and a heap of cold burial lanterns.
## Everything masonry is merged a material at a time, so a stilt-house is four draws.

## Reed thatch and reed walls: the hut skin the wayside builder gives Sedgemire's huts.
const THATCH := {"base": "#8a7a4a", "accent": "#6b5d36", "grout": "#3e3520", "unit": 0.2}
const REED_WALL := {"base": "#6f6a45", "accent": "#555132", "grout": "#2e2b1a", "unit": 0.16}
## Marsh indigo, the one dye: cloth on a line, a rag on a pole.
const INDIGO := Color(0.17, 0.2, 0.42)
const DOOR_DARK := Color(0.05, 0.045, 0.04)
## The clay of a bloomery, and the rust of bog ore.
const CLAY := {"base": "#7a5a3e", "accent": "#5e432d", "grout": "#3a281a", "unit": 0.3}
const ORE := Color(0.46, 0.2, 0.1)
const SLAG := Color(0.08, 0.075, 0.07)


# --- the marsh's pieces -----------------------------------------------------------------------------

## A reedfolk house on stilts at local `c`, its door toward `face`: `w` across the door, `depth`
## back from it, its deck `lift` over the highest ground under it. Returns {deck_y, door (local
## Vector3 on the deck at the door), foot (local Vector3 at the steps' foot), basis}.
static func stilt_house(d: PoiDressing, c: Vector2, face: Vector2, w := 4.2, depth := 3.6, lift := 1.5,
		node_name := "StiltHouse", max_steps := 9, crook := 0.0) -> Dictionary:
	var k := d.kit
	var m := d.masonry
	face = face.normalized() if face.length() > 0.01 else Vector2(0, 1)
	var side := Vector2(face.y, -face.x)
	var yaw := PoiKit.yaw_of(face)
	var basis := Basis(Vector3.UP, yaw)
	var top_g := -INF
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var p := c + side * (w * float(sx)) + face * (depth * float(sz))
			top_g = maxf(top_g, k.on_ground(p.x, p.y).y)
	var deck_y := top_g + lift
	var planks := m.begin()
	var posts := m.begin()
	var walls := m.begin()
	var roof := m.begin()
	var dark := m.begin()
	# the deck, a little wider than the house at the front: a porch to sit on
	var porch := 1.2
	var deck_c := c + face * (porch * 0.5)
	var deck_xf := Transform3D(basis, Vector3(deck_c.x, deck_y - 0.06, deck_c.y))
	m.block(planks, deck_xf, Vector3(w + 0.4, 0.12, depth + porch))
	k.collider(Vector3(w + 0.4, 0.2, depth + porch), Transform3D(basis, Vector3(deck_c.x, deck_y - 0.1, deck_c.y)), "wood")
	# bearers, and the stilts under them, down into the mud
	for sz in [-0.5, 0.0, 0.5]:
		var bc := deck_c + face * ((depth + porch) * float(sz) * 0.92)
		m.block(posts, Transform3D(basis, Vector3(bc.x, deck_y - 0.2, bc.y)), Vector3(w + 0.3, 0.14, 0.16))
		for sx in [-0.5, 0.5]:
			var p := bc + side * ((w - 0.1) * float(sx))
			var g := k.on_ground(p.x, p.y).y
			var h := deck_y - 0.12 - g + 0.4
			if crook <= 0.0:
				m.block(posts, Transform3D(Basis(Vector3.UP, yaw + 0.3 * float(sx)), Vector3(p.x, g - 0.4 + h * 0.5, p.y)), Vector3(0.2, h, 0.2))
				k.collider(Vector3(0.2, h, 0.2), Transform3D(basis, Vector3(p.x, g - 0.4 + h * 0.5, p.y)), "wood")
			else:
				# crooked: each stilt leaning its own way from under the deck, its foot kicked out
				var pb := Basis.from_euler(Vector3(k.rng.randf_range(-crook, crook), yaw + 0.3 * float(sx), k.rng.randf_range(-crook, crook)))
				var top3 := Vector3(p.x, deck_y - 0.12, p.y)
				var hl := h / maxf(pb.y.y, 0.5)
				var mid3 := top3 - pb.y * (hl * 0.5)
				m.block(posts, Transform3D(pb, mid3), Vector3(0.2, hl, 0.2))
				k.collider(Vector3(0.2, hl, 0.2), Transform3D(pb, mid3), "wood")
			if lift > 2.6 and sz < 0.4:
				# tall stilts are braced: a cross of poles to the next pair along the side
				var p1 := deck_c + face * ((depth + porch) * (float(sz) + 0.5) * 0.92) + side * ((w - 0.1) * float(sx))
				var g1b := k.on_ground(p1.x, p1.y).y
				m.limb(posts, Vector3(p.x, g + 0.3, p.y), Vector3(p1.x, deck_y - 0.45, p1.y), 0.06)
				m.limb(posts, Vector3(p1.x, g1b + 0.3, p1.y), Vector3(p.x, deck_y - 0.45, p.y), 0.06)
	# the walls of reed panels on a frame, the door in the front one
	var wall_h := 2.1
	var hc := c
	for s in [-1.0, 1.0]:
		# the side walls
		var p := hc + side * (w * 0.5 - 0.06) * float(s)
		var xf := Transform3D(basis, Vector3(p.x, deck_y + wall_h * 0.5, p.y))
		m.block(walls, xf, Vector3(0.12, wall_h, depth))
		k.collider(Vector3(0.12, wall_h, depth), xf, "wood")
	var back := hc - face * (depth * 0.5 - 0.06)
	var back_xf := Transform3D(basis, Vector3(back.x, deck_y + wall_h * 0.5, back.y))
	m.block(walls, back_xf, Vector3(w, wall_h, 0.12))
	k.collider(Vector3(w, wall_h, 0.12), back_xf, "wood")
	var front := hc + face * (depth * 0.5 - 0.06)
	var door_w := 1.0
	for s in [-1.0, 1.0]:
		var pw := (w - door_w) * 0.5
		var p := front + side * (door_w * 0.5 + pw * 0.5) * float(s)
		var xf := Transform3D(basis, Vector3(p.x, deck_y + wall_h * 0.5, p.y))
		m.block(walls, xf, Vector3(pw, wall_h, 0.12))
		k.collider(Vector3(pw, wall_h, 0.12), xf, "wood")
	m.block(walls, Transform3D(basis, Vector3(front.x, deck_y + wall_h - 0.2, front.y)), Vector3(door_w + 0.1, 0.4, 0.12))
	m.block(dark, Transform3D(basis, Vector3(front.x, deck_y + (wall_h - 0.4) * 0.5, front.y) - Vector3(face.x, 0.0, face.y) * 0.04), Vector3(door_w, wall_h - 0.4, 0.06))
	# corner posts proud of the panels, and a sill
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var p := hc + side * (w * float(sx)) + face * (depth * float(sz))
			m.block(posts, Transform3D(basis, Vector3(p.x, deck_y + wall_h * 0.5 + 0.1, p.y)), Vector3(0.16, wall_h + 0.2, 0.16))
	# a steep reed roof, its eaves well out past the walls and over the porch
	var pitch := 0.72
	var half_span := w * 0.5 + 0.45
	var slope_len := half_span / cos(pitch)
	var ridge_y := deck_y + wall_h + half_span * tan(pitch)
	for s in [-1.0, 1.0]:
		var mid := hc + side * (half_span * 0.5) * float(s) + face * (porch * 0.35)
		var xf := Transform3D(basis * Basis(Vector3.BACK, -pitch * float(s)), Vector3(mid.x, (ridge_y + deck_y + wall_h) * 0.5 + 0.08, mid.y))
		m.block(roof, xf, Vector3(slope_len + 0.2, 0.22, depth + porch * 0.7 + 0.8))
	# the gable ends: triangles of reed panel stepped in courses
	for e in [-1.0, 1.0]:
		var gc := hc + face * (depth * 0.5 - 0.06) * float(e)
		for i in 4:
			var t := (float(i) + 0.5) / 4.0
			var gw := (w - 0.1) * (1.0 - t)
			var gy := deck_y + wall_h + (ridge_y - deck_y - wall_h) * t
			m.block(walls, Transform3D(basis, Vector3(gc.x, gy - 0.02, gc.y)), Vector3(gw, (ridge_y - deck_y - wall_h) / 4.0 + 0.04, 0.1))
	# the steps down from the porch to the ground
	var edge := deck_c + face * ((depth + porch) * 0.5)
	var foot_g := k.on_ground(edge.x + face.x * 2.0, edge.y + face.y * 2.0).y
	var rise_total := deck_y - foot_g
	var n := clampi(int(ceil(rise_total / (0.28 if max_steps <= 9 else 0.25))), 2, max_steps)
	var tread := 0.34
	var start := edge + face * (tread * float(n))
	m.steps(planks, start, -face, foot_g, n, rise_total / float(n), tread, 1.1, 0.25)
	if n > 9:
		# a long flight stands on a pair of posts at its middle
		var mid_s := start - face * (tread * float(n) * 0.5)
		for s2 in [-1.0, 1.0]:
			var q := mid_s + side * 0.45 * float(s2)
			var qg := k.on_ground(q.x, q.y).y
			var qh := foot_g + rise_total * 0.5 - 0.3 - qg
			if qh > 0.3:
				m.block(posts, Transform3D(basis, Vector3(q.x, qg + qh * 0.5, q.y)), Vector3(0.14, qh, 0.14))
	for s in [-1.0, 1.0]:
		var sa := Vector3(start.x + side.x * 0.62 * float(s), foot_g, start.y + side.y * 0.62 * float(s))
		var sb := Vector3(edge.x + side.x * 0.62 * float(s), deck_y, edge.y + side.y * 0.62 * float(s))
		m.limb(posts, sa + Vector3.UP * 0.05, sb, 0.06)
	# the lantern on its arm by the door
	var arm_root := front + side * (door_w * 0.5 + 0.35) + face * 0.06
	var arm_top := Vector3(arm_root.x, deck_y + wall_h - 0.1, arm_root.y)
	var arm_end := arm_top + Vector3(face.x, 0.0, face.y) * 0.5
	m.block(posts, Transform3D(basis, (arm_top + arm_end) * 0.5), Vector3(0.07, 0.07, 0.55))
	await k.step()
	m.commit(planks, k.surface("planks", 0.7), node_name + "Planks", true)
	await k.step()
	m.commit(posts, k.surface("timber", 0.7), node_name + "Timber", true)
	await k.step()
	m.commit(walls, PoiKit.painted(5, REED_WALL, 0.6), node_name + "Walls", true)
	await k.step()
	m.commit(roof, PoiKit.painted(5, THATCH, 0.6), node_name + "Thatch", true)
	m.commit(dark, PoiKit.plain(DOOR_DARK, 0.95), node_name + "Door")
	var lamp := k.prop("lantern_hanging")
	if lamp != "":
		await k.step()
		k.place(lamp, arm_end - Vector3(0.0, 0.52, 0.0), yaw, 1.0, false)
		k.light(arm_end - Vector3(0.0, 0.7, 0.0), Color(1.0, 0.74, 0.42), 1.6, 9.0)
	var door3 := Vector3(front.x, deck_y, front.y) + Vector3(face.x, 0.0, face.y) * 0.6
	return {"deck_y": deck_y, "door": door3, "foot": Vector3(start.x, foot_g, start.y) + Vector3(face.x, 0.0, face.y) * 0.4,
			"inside": Vector3(hc.x, deck_y, hc.y), "basis": basis, "reach": maxf(w, depth + porch) * 0.5 + tread * float(n)}


## A lantern pole at local `at`: a post, an arm toward `toward`, and the region's lantern hung from
## the arm's end, lit or cold; with `rag`, an indigo rag tied under it.
static func lantern_pole(d: PoiDressing, st: SurfaceTool, at: Vector2, toward: Vector2, lit := true, height := 2.6,
		lean := 0.0) -> Vector3:
	var k := d.kit
	var m := d.masonry
	var dir := toward.normalized() if toward.length() > 0.01 else Vector2(0, 1)
	var top := m.post(st, at, height, 0.12, Vector3(lean * dir.y, 0.0, -lean * dir.x))
	var arm_end := top + Vector3(dir.x, 0.0, dir.y) * 0.45
	m.block(st, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(dir)), (top + arm_end) * 0.5 - Vector3(0.0, 0.08, 0.0)), Vector3(0.07, 0.07, 0.5))
	var lamp := k.prop("lantern_hanging")
	if lamp != "":
		k.place(lamp, arm_end - Vector3(0.0, 0.52, 0.0), PoiKit.yaw_of(dir), 1.0, false)
	if lit:
		k.light(arm_end - Vector3(0.0, 0.7, 0.0), Color(1.0, 0.72, 0.4), 1.5, 9.0)
	return arm_end


## Cold burial lanterns heaped on the ground at local `c`, `count` of them within `r`: each an indigo
## paper box on an alder frame (masonry, two draws for the whole heap, where the forge's hanging
## lantern is some thousands of triangles apiece and a heap of sixty of them was a million).
static func lantern_heap(d: PoiDressing, c: Vector2, r: float, count: int) -> void:
	var k := d.kit
	var m := d.masonry
	var paper := m.begin()
	var frames := m.begin()
	for i in count:
		var a := k.rng.randf_range(0.0, TAU)
		var rr := sqrt(k.rng.randf()) * r
		var lift := 0.14 + (0.3 * (1.0 - rr / maxf(r, 0.01))) * k.rng.randf()
		var p := k.on_ground(c.x + sin(a) * rr, c.y + cos(a) * rr, lift)
		var b := Basis.from_euler(Vector3(k.rng.randf_range(-1.2, 1.2), k.rng.randf_range(0.0, TAU), k.rng.randf_range(-1.2, 1.2)))
		var s := k.rng.randf_range(0.85, 1.1)
		m.block(paper, Transform3D(b, p), Vector3(0.26, 0.34, 0.26) * s)
		m.block(frames, Transform3D(b, p + b * Vector3(0.0, 0.19 * s, 0.0)), Vector3(0.3, 0.04, 0.3) * s)
		m.block(frames, Transform3D(b, p - b * Vector3(0.0, 0.19 * s, 0.0)), Vector3(0.3, 0.04, 0.3) * s)
	await k.step()
	m.commit(paper, PoiKit.plain(INDIGO, 0.85), "LanternPaper")
	m.commit(frames, k.surface("timber", 0.8), "LanternFrames")


## Reeds round the place, `count` of them in a ring from `r0` to `r1`, kept off `keep_off` (local
## xz points with a radius each: [Vector2, r]).
static func reeds(d: PoiDressing, r0: float, r1: float, count: int, keep_off: Array = []) -> void:
	var k := d.kit
	var path := k.flora("reeds")
	if path == "":
		return
	var xfs: Array = []
	for i in count:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(r0, r1)
		var p := Vector2(sin(a), cos(a)) * r
		var clear := true
		for ko in keep_off:
			if p.distance_to(ko[0]) < float(ko[1]):
				clear = false
				break
		if clear:
			xfs.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
	await k.step()
	k.scatter(path, xfs, false, false, false)


## A cloth line between two posts with indigo cloths hung on it to dry.
static func dye_line(d: PoiDressing, a: Vector2, b: Vector2, cloths := 3) -> void:
	var k := d.kit
	var m := d.masonry
	var posts := m.begin()
	var ta := m.post(posts, a, 2.1, 0.1)
	var tb := m.post(posts, b, 2.1, 0.1)
	m.limb(posts, ta - Vector3(0, 0.1, 0), tb - Vector3(0, 0.1, 0), 0.02)
	await k.step()
	m.commit(posts, k.surface("timber", 0.7), "DyeLine")
	var along := (b - a)
	var yaw := PoiKit.yaw_of(Vector2(along.y, -along.x))
	var cloth_mat := PoiKit.plain(INDIGO, 0.9)
	for i in cloths:
		var t := (float(i) + 0.6) / (float(cloths) + 0.3)
		var top := ta.lerp(tb, t) - Vector3(0, 0.1, 0)
		m.sheet(top, yaw, 0.7, k.rng.randf_range(0.9, 1.3), cloth_mat, "Cloth%d" % i, 0.15, false, 2, 3)


# --- Greylag Fold -------------------------------------------------------------------------------------

## A round fold of withy hurdles full of grey geese on a dry rise of the North Fen, the goose-herd's
## stilt-house beside it with its porch toward the gate, her punt drawn up under the reeds, a lantern
## pole at the gate she sings from, and a line of indigo cloth.
static func greylag_fold(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var g0 := k.grain()
	var west := Vector2(-1.0, 0.0)   # the carr, and the Vault, which the geese face
	var gate_dir := (g0 + west * 0.4).normalized()
	var fc := -gate_dir * 2.0
	var r := 5.2
	if k.far:
		await stilt_house(d, fc + Vector2(gate_dir.y, -gate_dir.x) * 10.0, gate_dir, 4.2, 3.6, 1.6, "Herd")
		return
	# the hurdles: withy panels round the fold, the gap for the gate on the side toward the house
	var wattle := k.prop("fence_wattle")
	var segs := 9
	var pts: Array[Vector2] = []
	for i in segs + 1:
		var a := PoiKit.yaw_of(gate_dir) + TAU * (float(i) + 0.5) / float(segs)
		pts.append(fc + Vector2(sin(a), cos(a)) * r)
	var withy := m.begin()
	for i in segs:
		if i == segs - 1:
			continue          # the gate
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var mid := (a + b) * 0.5
		var dir := b - a
		if wattle != "":
			var wl := maxf(PoiKit.half_width_of(wattle) * 2.0, 1.0)
			await k.step()
			k.place(wattle, k.on_ground(mid.x, mid.y, -0.12), atan2(-dir.y, dir.x), dir.length() / wl * 1.02, false,
					Vector3(0.0, 0.0, atan2(k.on_ground(b.x, b.y).y - k.on_ground(a.x, a.y).y, dir.length())))
		else:
			m.block(withy, Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), k.on_ground(mid.x, mid.y, 0.55)), Vector3(dir.length(), 1.1, 0.12))
		k.collider(Vector3(dir.length(), 1.2, 0.15), Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), k.on_ground(mid.x, mid.y, 0.6)), "wood")
	var ga: Vector2 = pts[segs - 1]
	var gb: Vector2 = pts[segs]
	for p in [ga, gb]:
		var q: Vector2 = p
		m.post(withy, q, 1.5, 0.14)
	# the gate hurdle swung open against the fold
	var gdir := (gb - ga).normalized().rotated(-1.1)
	var gmid := ga + gdir * 0.8
	m.block(withy, Transform3D(Basis(Vector3.UP, atan2(-gdir.y, gdir.x)), k.on_ground(gmid.x, gmid.y, 0.55)), Vector3(ga.distance_to(gb) * 0.85, 0.95, 0.07))
	await k.step()
	m.commit(withy, k.surface("timber", 0.8), "Hurdles")
	# the geese
	var geese := Livestock.paths_of("goose", "sedgemire")
	if geese.is_empty():
		geese = Livestock.paths_of("goose", "hearthvale")
	if not geese.is_empty():
		var flock := Livestock.new()
		flock.name = "Geese"
		flock.seed_with(absi(("geese:" + d.poi_id).hash()))
		flock.keep("goose", geese, k.on_ground(fc.x, fc.y), r - 1.4, 9)
		d.add_child(flock)
	var gate_mid := (ga + gb) * 0.5
	k.marker("the_fold", k.on_ground(gate_mid.x + gate_dir.x * 1.2, gate_mid.y + gate_dir.y * 1.2), true)
	# the goose-herd's house, its porch looking at the gate
	var side := Vector2(gate_dir.y, -gate_dir.x)
	var hc := gate_mid + side * 8.5 + gate_dir * 3.0
	var to_gate := (gate_mid - hc).normalized()
	var house: Dictionary = await stilt_house(d, hc, to_gate, 4.2, 3.6, 1.6, "Herd")
	k.marker("the_deck", house["door"], true, true, 1.2)
	k.marker("home", house["inside"], true, true, 1.5)
	# the lantern pole she sings from, at the gate
	var poles := m.begin()
	var pole_at := gate_mid + gate_dir * 2.2 - side * 1.4
	lantern_pole(d, poles, pole_at, -side, true, 2.7)
	await k.step()
	m.commit(poles, k.surface("timber", 0.8), "GatePole")
	# the punt drawn up under the reeds, the far side of the house
	var boat := k.prop("rowboat")
	var punt := hc - to_gate * 5.5 + side * 2.5
	if boat != "":
		await k.step()
		k.place(boat, k.on_ground(punt.x, punt.y, 0.05), PoiKit.yaw_of(side) + 0.3, 1.0, true)
	k.marker("the_punt", k.on_ground(punt.x + to_gate.x * 1.5, punt.y + to_gate.y * 1.5), true)
	# a feed basket and a water trough of a half barrel by the gate, the herd's cloth drying
	var basket := k.prop("basket")
	if basket != "":
		var bp := gate_mid + gate_dir * 1.4 + side * 1.2
		await k.step()
		k.place(basket, k.on_ground(bp.x, bp.y), k.rng.randf() * TAU, 1.0, false)
	var bucket := k.prop("bucket")
	if bucket != "":
		var tp := gate_mid + gate_dir * 1.0 + side * 2.0
		await k.step()
		k.place(bucket, k.on_ground(tp.x, tp.y), k.rng.randf() * TAU, 1.1, false)
	await dye_line(d, hc - to_gate * 3.8 - side * 3.2, hc - to_gate * 0.8 - side * 4.4, 3)
	await reeds(d, 8.0, 17.0, 70, [[fc, r + 2.0], [hc, 5.5], [punt, 2.5], [gate_mid + gate_dir * 3.0, 3.0]])


# --- The Eel Tally ------------------------------------------------------------------------------------

## The Guild's counting-house on stilts at the head of the stews' channel: the tally-house with its
## brass lantern, the barrels ranked below it in rows, the clerk's table at the foot of the steps
## with the book on it, the tally-post notched for the tithe, the Guild's banner, and the landing
## stage where the reedfolk pole their catch in.
static func eel_tally(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.grain()
	var water := k.water_direction(60.0)
	if water != Vector2.ZERO:
		face = water
	var side := Vector2(face.y, -face.x)
	var hc := -face * 4.5
	var house: Dictionary = await stilt_house(d, hc, face, 5.0, 4.0, 1.8, "Tally")
	if k.far:
		return
	k.marker("home", house["inside"], true, true, 1.5)
	var foot: Vector3 = house["foot"]
	var foot2 := Vector2(foot.x, foot.z)
	# the clerk's table at the foot of the steps, the book and papers on it, a stool behind
	var table := k.prop("table_trestle")
	var tp := foot2 + side * 2.2 + face * 0.6
	if table != "":
		await k.step()
		k.place(table, k.on_ground(tp.x, tp.y), PoiKit.yaw_of(side), 1.0, true)
	for kind in ["book", "paper_stack"]:
		var pk := k.prop(kind)
		if pk != "":
			var q := tp + side * (0.3 if kind == "book" else -0.35)
			await k.step()
			k.place(pk, k.on_ground(q.x, q.y, 0.78), PoiKit.yaw_of(side) + k.rng.randf_range(-0.3, 0.3), 1.0, false)
	var stool := k.prop("stool")
	if stool != "":
		var sp := tp + side * 0.9
		await k.step()
		k.place(stool, k.on_ground(sp.x, sp.y), 0.0, 1.0, true)
	k.marker("the_tally_desk", k.on_ground(tp.x + side.x * 0.9, tp.y + side.y * 0.9), true)
	k.marker("the_tally_steps", k.on_ground(foot2.x - side.x * 1.6, foot2.y - side.y * 1.6))
	# the barrels, ranked in three rows by the landing, each row chalked for a landing
	var barrel := k.prop("barrel")
	if barrel != "":
		var xfs: Array = []
		for row in 3:
			for i in 5:
				var bp := foot2 + face * (2.6 + float(row) * 1.1) - side * (1.2 + float(i) * 0.95) + k.jitter(0.08)
				xfs.append(PoiKit.transform_at(k.on_ground(bp.x, bp.y), k.rng.randf_range(0.0, TAU), 0.95))
		await k.step()
		k.scatter(barrel, xfs, true, false, true)
	# the tally-post: a tall squared post notched in tens, by the table
	var timber := m.begin()
	var post_at := tp + face * 1.4
	var post_top := m.post(timber, post_at, 2.4, 0.2)
	var notches := timber
	var pbasis := Basis(Vector3.UP, PoiKit.yaw_of(face))
	for i in 14:
		var y := post_top.y - 0.25 - float(i) * 0.14
		var long := (i % 5) == 4
		m.block(notches, Transform3D(pbasis, Vector3(post_at.x, y, post_at.y) + pbasis * Vector3(0.0, 0.0, 0.105)), Vector3(0.16 if long else 0.09, 0.025, 0.02))
	# the Guild's banner on a pole by the steps
	var banner_at := foot2 - side * 0.3 + face * 0.2
	var btop := m.post(timber, banner_at + side * 3.0, 4.2, 0.12)
	m.block(timber, Transform3D(pbasis, btop - Vector3(0, 0.1, 0) + Vector3(face.x, 0, face.y) * 0.45), Vector3(0.06, 0.06, 0.9))
	# the landing stage: planks out on posts toward the water, the reedfolk's punts tied to it
	var planks := m.begin()
	var stage_a := foot2 + face * 6.2
	var stage_b := foot2 + face * 13.5
	var stage_y := maxf(k.on_ground(stage_a.x, stage_a.y).y, k.on_ground(stage_b.x, stage_b.y).y) + 0.12
	m.plank_deck(planks, timber, stage_a, stage_b, 1.8, stage_y, 2.4, false)
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "TallyTimber")
	await k.step()
	m.commit(planks, k.surface("planks", 0.8), "Landing")
	var guild := PoiKit.plain(Color(0.42, 0.12, 0.1), 0.85)
	m.sheet(btop - Vector3(0, 0.12, 0) + Vector3(face.x, 0, face.y) * 0.8, PoiKit.yaw_of(side), 0.8, 1.4, guild, "GuildBanner", 0.08, true, 2, 3)
	var boat := k.prop("rowboat")
	if boat != "":
		var bp := stage_b + side * 1.8 - face * 0.5
		await k.step()
		k.place(boat, k.on_ground(bp.x, bp.y, 0.05), PoiKit.yaw_of(face) + 0.15, 1.0, true)
	var lamp := k.prop("lantern_standing")
	if lamp != "":
		var lp := tp - face * 0.5 - side * 0.6
		await k.step()
		k.place(lamp, k.on_ground(lp.x, lp.y), 0.0, 1.0, false)
	# the Guild's notice post: work for whoever will do it, at Guild rates
	var jb := foot2 + side * 4.2 - face * 1.4
	k.job_board(k.on_ground(jb.x, jb.y), PoiKit.yaw_of(face))
	var crate := k.prop("crate")
	if crate != "":
		var cp := foot2 + face * 1.2 + side * 3.9
		await k.step()
		k.place(crate, k.on_ground(cp.x, cp.y), PoiKit.yaw_of(face) + 0.2, 1.0, true)
	await reeds(d, 9.0, 17.0, 50, [[stage_a.lerp(stage_b, 0.5), 5.0], [hc, 5.0], [foot2 + face * 3.5, 5.0]])


# --- The Stakes at Oulnauve -------------------------------------------------------------------------

## The stockade, and in its yard the burial lanterns the Flood-Callers cut from the water, heaped
## unlit; outside the gate, poles with cut lanterns hung dark; the yard marked for the Caller.
static func oulnauve_stakes(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().SITES.build(d)
	var k := d.kit
	if k.far:
		return
	var def := ContentDB.get_or_empty(d.poi_id)
	var site: Dictionary = def.get("site", {})
	var radius := float(site.get("radius", 15.0))
	# the gate's bearing as the enclosure lays it (the def gives it, so the two agree)
	var b := deg_to_rad(float(site.get("gate_bearing_deg", 0.0)))
	var gate_dir := Vector2(sin(b), cos(b))
	var side := Vector2(gate_dir.y, -gate_dir.x)
	# the heaps in the yard, off the middle where the fire is and clear of the lean-tos
	for s in [-1.0, 1.0]:
		var c := -gate_dir * (radius * 0.38) + side * (radius * 0.28) * float(s)
		await lantern_heap(d, c, 1.6, 26)
	await lantern_heap(d, -gate_dir * (radius * 0.12) + side * (radius * 0.05), 1.0, 12)
	k.marker("the_yard", k.on_ground(-gate_dir.x * radius * 0.2, -gate_dir.y * radius * 0.2))
	# outside the gate, two poles with cut lanterns hung dark from them, and the Callers' cloths
	var m := d.masonry
	var poles := m.begin()
	for s in [-1.0, 1.0]:
		var at := gate_dir * (radius + 4.5) + side * 2.6 * float(s)
		lantern_pole(d, poles, at, side * float(s), false, 2.9, 0.06 * float(s))
	await k.step()
	m.commit(poles, k.surface("timber", 0.9), "CutPoles")
	await dye_line(d, -gate_dir * (radius * 0.55) - side * (radius * 0.5), -gate_dir * (radius * 0.72) - side * (radius * 0.15), 4)


# --- The Unsung Vault -------------------------------------------------------------------------------

## The delve's mouth in its hummock, with the Builders' black doorway set round it, the approach lined
## with lantern poles whose lanterns are all cold, and a heap of the Vault's cold lanterns by the door.
static func unsung_vault(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().SITES.build(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var mouth := d.find_child("the_mouth", true, false) as Node3D
	var at := mouth.position if mouth != null else Vector3.ZERO
	var out := Vector2(-at.x, -at.z).normalized() if Vector2(at.x, at.z).length() > 0.5 else Vector2(0, -1)
	var across := Vector2(out.y, -out.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(out))
	# the Builders' doorway: two black jambs and a lintel, a little proud of the rock at the mouth
	var oroth := m.begin()
	var door_c := Vector2(at.x, at.z) + out * 0.9
	var g := k.on_ground(door_c.x, door_c.y).y
	for s in [-1.0, 1.0]:
		var jc := door_c + across * 2.3 * float(s)
		var jg := k.on_ground(jc.x, jc.y).y
		var xf := Transform3D(basis, Vector3(jc.x, jg + 1.6, jc.y))
		m.block(oroth, xf, Vector3(0.9, 4.4, 1.1))
		k.collider(Vector3(0.9, 4.4, 1.1), xf, "stone")
	m.block(oroth, Transform3D(basis, Vector3(door_c.x, g + 4.05, door_c.y)), Vector3(5.8, 0.9, 1.3))
	m.block(oroth, Transform3D(basis * Basis(Vector3.FORWARD, 0.06), Vector3(door_c.x + across.x * 3.8, g + 0.35, door_c.y + across.y * 3.8) + Vector3(out.x, 0, out.y) * 1.5), Vector3(1.6, 0.7, 1.0))
	await k.step()
	m.commit(oroth, k.surface("oroth", 0.7), "OrothDoor", true)
	# the approach: poles in two rows going out from the door, every lantern cold
	var poles := m.begin()
	for i in 4:
		for s in [-1.0, 1.0]:
			var p := door_c + out * (4.0 + float(i) * 2.8) + across * (2.2 + 0.25 * float(i)) * float(s) + k.jitter(0.2)
			lantern_pole(d, poles, p, -across * float(s), false, 2.5 + k.rng.randf_range(-0.2, 0.2), k.rng.randf_range(-0.05, 0.05))
	await k.step()
	m.commit(poles, k.surface("timber", 0.9), "ColdPoles")
	await lantern_heap(d, door_c + out * 2.0 + across * 3.4, 1.2, 18)
	# peat and carr round the hummock
	await reeds(d, 6.0, 18.0, 60, [[door_c + out * 8.0, 4.0], [Vector2(at.x, at.z), 6.0]])


# --- Isse's Chair -------------------------------------------------------------------------------------

## Nine black stilts of bog-oak, stone at the foot, leaning a little each its own way, in a ring round
## a low seat of green Builders' stone heaped with cut reeds and knots; a naming-cord on a rail, and a
## lantern pole at the way in.
static func isses_chair(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.grain()
	var side := Vector2(face.y, -face.x)
	var ring_r := 5.2
	var oak := m.begin()
	var stone := m.begin()
	for i in 9:
		var a := PoiKit.yaw_of(face) + TAU * (float(i) + 0.5) / 9.0
		var p := Vector2(sin(a), cos(a)) * ring_r
		var gp := k.on_ground(p.x, p.y).y
		var h := 3.4 + k.rng.randf_range(-0.5, 0.9)
		var lean := Vector3(k.rng.randf_range(-0.08, 0.08), 0.0, k.rng.randf_range(-0.08, 0.08))
		var lb := Basis.from_euler(lean) * Basis(Vector3.UP, k.rng.randf() * TAU)
		m.block(oak, Transform3D(lb, Vector3(p.x, gp + h * 0.5 - 0.3, p.y)), Vector3(0.42, h, 0.42))
		# the foot gone to stone, where the water keeps it
		m.block(stone, Transform3D(lb, Vector3(p.x, gp + 0.35, p.y)), Vector3(0.56, 1.1, 0.56))
		k.collider(Vector3(0.5, h, 0.5), Transform3D(lb, Vector3(p.x, gp + h * 0.5 - 0.3, p.y)), "wood")
	await k.step()
	m.commit(oak, PoiKit.plain(Color(0.09, 0.08, 0.07), 0.8), "Stilts", true)
	m.commit(stone, k.surface("stone", 0.8), "StiltFeet", true)
	# the seat: a low block of green Builders' stone with a back, in the middle
	var green := m.begin()
	var g := k.on_ground(0.0, 0.0).y
	var sb := Basis(Vector3.UP, PoiKit.yaw_of(face))
	m.block(green, Transform3D(sb, Vector3(0.0, g + 0.25, 0.0)), Vector3(2.0, 0.9, 1.3))
	m.block(green, Transform3D(sb, Vector3(0.0, g + 0.9, 0.0) - Vector3(face.x, 0, face.y) * 0.5), Vector3(2.0, 1.4, 0.35))
	k.collider(Vector3(2.0, 0.9, 1.3), Transform3D(sb, Vector3(0.0, g + 0.25, 0.0)), "stone")
	k.collider(Vector3(2.0, 1.4, 0.35), Transform3D(sb, Vector3(0.0, g + 0.9, 0.0) - Vector3(face.x, 0, face.y) * 0.5), "stone")
	await k.step()
	m.commit(green, PoiKit.painted(2, {"base": "#3f5a4a", "accent": "#2f463a", "grout": "#1a2620", "unit": 0.9}, 0.5), "Seat", true)
	if k.far:
		return
	# cut reeds laid on the seat and at its foot, bundled
	var bundles := m.begin()
	for i in 7:
		var p := Vector2(k.rng.randf_range(-0.8, 0.8), k.rng.randf_range(-0.3, 0.9)).rotated(-PoiKit.yaw_of(face))
		var y := g + (0.72 if i < 3 else 0.06)
		if i >= 3:
			p = face * k.rng.randf_range(1.0, 1.6) + side * k.rng.randf_range(-1.2, 1.2)
			y = k.on_ground(p.x, p.y).y + 0.06
		m.limb(bundles, Vector3(p.x, y, p.y) - Vector3(side.x, 0, side.y) * 0.45, Vector3(p.x, y + 0.02, p.y) + Vector3(side.x, 0, side.y) * 0.45, 0.08)
	await k.step()
	m.commit(bundles, PoiKit.painted(5, THATCH, 0.4), "ReedBundles")
	# the rail with the naming-cord, and the lantern pole at the way in
	var timber := m.begin()
	var rail_c := face * (ring_r + 1.6) + side * 2.0
	for s in [-1.0, 1.0]:
		m.post(timber, rail_c + side * 1.3 * float(s), 1.1, 0.1)
	var rg := k.on_ground(rail_c.x, rail_c.y).y
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), Vector3(rail_c.x, rg + 1.05, rail_c.y)), Vector3(2.8, 0.08, 0.08))
	lantern_pole(d, timber, face * (ring_r + 1.8) - side * 1.6, face, true, 2.8)
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "ChairTimber")
	var cord := m.begin()
	for i in 9:
		var t := float(i) / 8.0
		var top := Vector3(rail_c.x, rg + 1.0, rail_c.y) + Vector3(side.x, 0, side.y) * lerpf(-1.25, 1.25, t)
		var hang := 0.4 + k.rng.randf_range(0.0, 0.35)
		m.limb(cord, top, top - Vector3(0, hang, 0), 0.02)
		m.ellipsoid(cord, top - Vector3(0, hang * 0.6, 0), Vector3(0.05, 0.05, 0.05))
	await k.step()
	m.commit(cord, PoiKit.plain(INDIGO, 0.9), "NamingCord")
	# the way in: a boardwalk out through the reeds, the way the couples come
	var walk := m.begin()
	var walk_posts := m.begin()
	var wa := face * (ring_r + 0.8)
	var wb := face * (ring_r + 11.0) + side * 1.5
	var wy := maxf(k.on_ground(wa.x, wa.y).y, k.on_ground(wb.x, wb.y).y) + 0.3
	m.plank_deck(walk, walk_posts, wa, wb, 1.3, wy, 2.6, false)
	await k.step()
	m.commit(walk, k.surface("planks", 0.85), "ChairWalk")
	m.commit(walk_posts, k.surface("timber", 0.85), "ChairWalkPosts")
	k.marker("the_chair", k.on_ground(face.x * 2.4 + side.x * 0.8, face.y * 2.4 + side.y * 0.8), true)
	k.marker("home", k.on_ground(face.x * 2.8 - side.x * 2.4, face.y * 2.8 - side.y * 2.4), true)
	await lantern_heap(d, -face * 1.6 + side * 1.4, 0.5, 4)
	await reeds(d, 8.0, 17.0, 60, [[face * (ring_r + 2.0), 4.0], [(wa + wb) * 0.5, 6.5]])


# --- The Leech-Wife's Stilts ------------------------------------------------------------------------

## Her stilt-house over a ring of sunken leech-tubs (half barrels let into the ground, water in
## them), the empty wattle kennels, the pole of collars by the door with one hook bare.
static func leech_wifes_stilts(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.grain()
	var side := Vector2(face.y, -face.x)
	var hc := -face * 3.0
	var house: Dictionary = await stilt_house(d, hc, face, 4.4, 3.8, 1.7, "Leech")
	if k.far:
		return
	k.marker("home", house["inside"], true, true, 1.5)
	var foot: Vector3 = house["foot"]
	var foot2 := Vector2(foot.x, foot.z)
	# the tubs: a ring of half barrels sunk in the mud in front, each with its lid of withy
	var barrel := k.prop("barrel")
	var water_mat := k.still_water(0.0, Color(0.55, 0.5, 0.4), 0.85)
	var tub_c := foot2 + face * 5.0
	for i in 6:
		var a := TAU * float(i) / 6.0
		var p := tub_c + Vector2(sin(a), cos(a)) * 2.6
		if barrel != "":
			await k.step()
			k.place(barrel, k.on_ground(p.x, p.y, -0.35), k.rng.randf() * TAU, 1.05, true)
		m.pool(p, 0.3, k.on_ground(p.x, p.y).y + 0.58, water_mat, "Tub%d" % i, 10)
	k.marker("the_tubs", k.on_ground(tub_c.x - face.x * 1.2, tub_c.y - face.y * 1.2), true)
	# the kennels: three wattle pens along one side, empty, their doors open
	var kennels := m.begin()
	for i in 3:
		var kc := foot2 + side * 5.2 + face * (float(i) * 2.4 - 1.0)
		var kg := k.on_ground(kc.x, kc.y).y
		var kb := Basis(Vector3.UP, PoiKit.yaw_of(-side))
		m.block(kennels, Transform3D(kb, Vector3(kc.x, kg + 0.45, kc.y) - Vector3(side.x, 0, side.y) * 0.0 + kb * Vector3(0, 0, -0.8)), Vector3(1.8, 0.9, 0.08))
		for s in [-1.0, 1.0]:
			m.block(kennels, Transform3D(kb, Vector3(kc.x, kg + 0.45, kc.y) + kb * Vector3(0.9 * float(s), 0, 0)), Vector3(0.08, 0.9, 1.6))
		m.block(kennels, Transform3D(kb * Basis(Vector3.RIGHT, 0.2), Vector3(kc.x, kg + 1.0, kc.y)), Vector3(2.0, 0.08, 1.9))
		k.collider(Vector3(2.0, 1.0, 1.8), Transform3D(kb, Vector3(kc.x, kg + 0.5, kc.y)), "wood")
	await k.step()
	m.commit(kennels, PoiKit.painted(5, REED_WALL, 0.7), "Kennels")
	# the collar pole: a post with pegs, the collars on all but one
	var timber := m.begin()
	var cp := foot2 - side * 1.8 + face * 0.4
	var top := m.post(timber, cp, 2.0, 0.14)
	var irons := m.begin()
	for i in 8:
		var a := TAU * float(i) / 8.0
		var y := top.y - 0.3 - float(i % 4) * 0.35
		var dir := Vector3(sin(a), 0, cos(a))
		m.block(timber, Transform3D(Basis(Vector3.UP, a), Vector3(cp.x, y, cp.y) + dir * 0.14), Vector3(0.04, 0.04, 0.22))
		if i != 5:
			m.ellipsoid(irons, Vector3(cp.x, y - 0.12, cp.y) + dir * 0.22, Vector3(0.12, 0.13, 0.04), Basis(Vector3.UP, a))
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "CollarPole")
	m.commit(irons, PoiKit.plain(Color(0.23, 0.2, 0.18), 0.6, 0.6), "Collars")
	k.marker("the_collars", k.on_ground(cp.x + face.x * 1.0, cp.y + face.y * 1.0), true)
	# her landing: planks out through the reeds past the tubs, where Isseva's bleeders pole over
	var planks := m.begin()
	var ptimber := m.begin()
	var la := tub_c + face * 3.6 - side * 1.0
	var lb := tub_c + face * 10.5 - side * 2.2
	var ly := maxf(k.on_ground(la.x, la.y).y, k.on_ground(lb.x, lb.y).y) + 0.4
	m.plank_deck(planks, ptimber, la, lb, 1.4, ly, 2.4, false)
	await k.step()
	m.commit(planks, k.surface("planks", 0.85), "LeechLanding")
	m.commit(ptimber, k.surface("timber", 0.85), "LeechLandingPosts")
	var boat := k.prop("rowboat")
	if boat != "":
		var bp := hc - face * 4.8 + side * 2.2
		await k.step()
		k.place(boat, k.on_ground(bp.x, bp.y, 0.05), PoiKit.yaw_of(side) + 0.4, 1.0, true)
	await reeds(d, 9.0, 17.0, 60, [[tub_c, 4.5], [hc, 5.0], [(la + lb) * 0.5, 4.5]])


# --- The Drylanders' Hummock ------------------------------------------------------------------------

## A low green hummock crowded with earth graves: each a turf mound with a board in a stranger's
## letters at its head and, beside it, a reedfolk lantern pole; the newest grave dug and left open.
static func drylanders_hummock(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.grain()
	var side := Vector2(face.y, -face.x)
	var turf := PoiKit.painted(5, {"base": "#2e3a24", "accent": "#232d1a", "grout": "#151b0f", "unit": 0.3}, 0.5)
	m.mound(k.on_ground(0.0, 0.0, -0.55), 11.5, 1.35, turf, "Hummock", true, 1.6, 6, 20, true, 0.08)
	if k.far:
		return
	var boards := m.begin()
	var poles := m.begin()
	var mounds := m.begin()
	var n := 0
	for row in 3:
		for i in 4:
			if row == 2 and i == 3:
				continue
			var p := face * (float(row) - 1.0) * 3.2 + side * (float(i) - 1.5) * 2.4 + k.jitter(0.25)
			var gy := k.on_ground(p.x, p.y).y + _hummock_lift(p, 11.5, 1.35)
			var gb := Basis(Vector3.UP, PoiKit.yaw_of(face) + k.rng.randf_range(-0.08, 0.08))
			var head := p - face * 1.0
			if row == 2 and i == 2:
				# the newest: dug and turned and left open, its board pale
				m.block(mounds, Transform3D(gb, Vector3(p.x, gy + 0.05, p.y) + gb * Vector3(0.75, 0, 0)), Vector3(0.6, 0.35, 1.8))
				await k.step()
				m.commit(mounds, turf, "Graves")
				mounds = m.begin()
				m.block(boards, Transform3D(gb, Vector3(head.x, gy + 0.55, head.y)), Vector3(0.7, 0.9, 0.06))
				m.pool(p, 0.45, gy - 0.02, PoiKit.plain(Color(0.07, 0.06, 0.05), 1.0), "OpenGrave", 8)
			else:
				m.block(mounds, Transform3D(gb, Vector3(p.x, gy + 0.1, p.y)), Vector3(0.9, 0.3, 1.9))
				m.block(boards, Transform3D(gb * Basis(Vector3.RIGHT, k.rng.randf_range(-0.12, 0.08)), Vector3(head.x, gy + 0.5, head.y)), Vector3(0.6 + k.rng.randf() * 0.2, 0.8 + k.rng.randf() * 0.3, 0.06))
			if n % 2 == 0:
				lantern_pole(d, poles, head + side * 0.8, face, n % 4 == 0, 2.2)
			n += 1
	await k.step()
	m.commit(mounds, turf, "Graves2")
	m.commit(boards, k.surface("planks", 0.95), "Boards", true)
	await k.step()
	m.commit(poles, k.surface("timber", 0.9), "GravePoles")
	k.marker("the_newest", k.on_ground(face.x * 3.2 + side.x * 1.2, face.y * 3.2 + side.y * 1.2))
	# sedge on the hummock between the graves
	var sedge := k.flora("sedge_tussock")
	if sedge != "":
		var xfs: Array = []
		for i in 40:
			var a := k.rng.randf_range(0.0, TAU)
			var r := k.rng.randf_range(1.0, 9.5)
			var q := Vector2(sin(a), cos(a)) * r
			if absf(q.dot(side)) < 4.8 and absf(q.dot(face)) < 4.6:
				continue
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y, _hummock_lift(q, 11.5, 1.35) - 0.05), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.2)))
		await k.step()
		k.scatter(sedge, xfs, false, false, false)
	await reeds(d, 11.0, 18.0, 55, [])


static func _hummock_lift(p: Vector2, r: float, h: float) -> float:
	var f := clampf(p.length() / r, 0.0, 1.0)
	return h * pow(maxf(1.0 - f * f, 0.0), 1.6 * 0.5) - 0.55


# --- The Bog-Iron Bloomery ---------------------------------------------------------------------------

## A squat clay furnace smoking on a hummock, its bellows and its door; heaps of red ore and black
## charcoal round it, the slag run down the bank, and the flooded ore-pits below where the sallowjaws
## lie warm; the bloomers' camp beside.
static func bog_iron_bloomery(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().camp(d)
	var k := d.kit
	var m := d.masonry
	var face := k.grain()
	var side := Vector2(face.y, -face.x)
	var fc := face * 8.0 + side * 3.0
	var g := k.on_ground(fc.x, fc.y).y
	# the furnace: a tapering drum of clay courses
	var clay := m.begin()
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(face))
	for i in 6:
		var t := float(i) / 6.0
		var rr := lerpf(1.1, 0.55, t)
		m.drum(clay, Transform3D(Basis.IDENTITY, Vector3(fc.x, g + t * 2.6 - 0.2, fc.y)), rr, 2.6 / 6.0 + 0.05, 0.0)
	k.collider(Vector3(1.8, 2.6, 1.8), Transform3D(Basis.IDENTITY, Vector3(fc.x, g + 1.2, fc.y)), "stone")
	await k.step()
	m.commit(clay, PoiKit.painted(5, CLAY, 0.7), "Bloomery", true)
	if k.far:
		return
	var mouth := fc - face * 1.05
	var glow := m.begin()
	m.block(glow, Transform3D(fb, Vector3(mouth.x, g + 0.35, mouth.y)), Vector3(0.6, 0.6, 0.2))
	await k.step()
	m.commit(glow, PoiKit.plain(Color(0.9, 0.35, 0.08), 0.5, 0.0, Color(1.0, 0.4, 0.1), 2.0), "BloomDoor")
	k.light(Vector3(mouth.x, g + 0.6, mouth.y) - Vector3(face.x, 0, face.y) * 0.4, Color(1.0, 0.5, 0.2), 1.8, 8.0)
	k.puffs(Vector3(fc.x, g + 2.8, fc.y), Vector3(0.3, 0.2, 0.3), 3.5, 8, Color(0.3, 0.29, 0.27, 0.45), 1.8, 5.0)
	# ore and charcoal heaps, and the slag
	var ore := PoiKit.plain(ORE, 0.95)
	m.mound(k.on_ground(fc.x + side.x * 2.6, fc.y + side.y * 2.6, -0.1), 1.3, 0.7, ore, "Ore", true, 1.4, 4, 12, false, 0.12)
	m.mound(k.on_ground(fc.x - side.x * 2.4 + face.x * 0.8, fc.y - side.y * 2.4 + face.y * 0.8, -0.1), 1.1, 0.6, PoiKit.plain(Color(0.06, 0.055, 0.05), 0.95), "Charcoal", true, 1.4, 4, 12, false, 0.12)
	var slag := m.begin()
	for i in 10:
		var p := fc + face * (1.4 + float(i) * 0.45) + side * k.rng.randf_range(-0.6, 0.6)
		m.ellipsoid(slag, k.on_ground(p.x, p.y, 0.02), Vector3(0.35, 0.08, 0.28), Basis(Vector3.UP, k.rng.randf() * TAU))
	await k.step()
	m.commit(slag, PoiKit.plain(SLAG, 0.35, 0.3), "Slag")
	# the ore-pits: three flooded holes below the hummock, the water dark and still
	var pit_mat := k.still_water(0.0, Color(0.5, 0.35, 0.25), 0.8)
	var rims := m.begin()
	for i in 3:
		var pc := -face * (7.0 + float(i) * 1.5) + side * (float(i) - 1.0) * 4.6
		var pg := k.on_ground(pc.x, pc.y).y
		m.pool(pc, 1.6, pg - 0.12, pit_mat, "OrePit%d" % i, 14)
		for j in 7:
			var a := TAU * float(j) / 7.0 + k.rng.randf()
			var q := pc + Vector2(sin(a), cos(a)) * 1.75
			m.ellipsoid(rims, k.on_ground(q.x, q.y, 0.02), Vector3(0.45, 0.14, 0.3), Basis(Vector3.UP, a))
	await k.step()
	m.commit(rims, ore, "PitRims")
	k.marker("the_pits", k.on_ground(-face.x * 8.5, -face.y * 8.5))
	var bellows := k.prop("sack")
	if bellows != "":
		var bp := fc + side * 1.3 - face * 0.4
		await k.step()
		k.place(bellows, k.on_ground(bp.x, bp.y), PoiKit.yaw_of(side), 1.0, false)
	var barrow := k.prop("wheelbarrow")
	if barrow != "":
		var wp := fc + side * 3.8 - face * 1.2
		await k.step()
		k.place(barrow, k.on_ground(wp.x, wp.y), PoiKit.yaw_of(face) + 0.6, 1.0, true)


# --- The Grey Line -----------------------------------------------------------------------------------

## Rows of withy stakes driven across the reed-beds, a row for every year, each stake tied with a knot;
## the rows toward the grey gone white, their knots gone; beyond the last row the reeds are ash.
static func grey_line(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	# the grey is south (the Hushline); the rows run east to west across it
	var south := Vector2(0.0, 1.0)
	var across := Vector2(1.0, 0.0)
	var fresh := m.begin()
	var old := m.begin()
	var knots := m.begin()
	var rows := 9
	for row in rows:
		var t := float(row) / float(rows - 1)
		var off := south * lerpf(-7.5, 9.0, t)
		var mat_st := fresh if t < 0.35 else old
		var count := 11
		for i in count:
			var p := off + across * lerpf(-12.0, 12.0, float(i) / float(count - 1)) + k.jitter(0.25)
			var h := 1.7 + k.rng.randf_range(-0.2, 0.25) - t * 0.4
			var lean := Vector3(k.rng.randf_range(-0.06, 0.06), 0, k.rng.randf_range(-0.06, 0.06) + t * 0.08)
			var top := m.post(mat_st, p, h, 0.11, lean)
			if t < 0.8:
				m.ellipsoid(knots, top - Vector3(0, 0.14, 0), Vector3(0.09, 0.07, 0.09))
	await k.step()
	m.commit(fresh, k.surface("timber", 0.6), "NewRows", true)
	m.commit(old, PoiKit.painted(3, {"base": "#6d6a62", "accent": "#55524b"}, 0.9), "GreyRows", true)
	if k.far:
		return
	await k.step()
	m.commit(knots, PoiKit.plain(Color(0.35, 0.45, 0.28), 0.9), "Knots")
	# the reeds: green on the village side; past the last row the ash country's grey grass
	var path := k.flora("reeds")
	var ash := k.flora("grey_grass")
	if path != "":
		var green: Array = []
		var grey: Array = []
		for i in 120:
			var p := Vector2(k.rng.randf_range(-15.0, 15.0), k.rng.randf_range(-15.0, 16.0))
			if absf(p.y - (-7.5)) < 0.7:
				continue
			var xf := PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4))
			if p.y > 9.5:
				grey.append(xf)
			elif p.y < 5.0:
				green.append(xf)
		await k.step()
		k.scatter(path, green, false, false, false)
		if ash != "":
			await k.step()
			k.scatter(ash, grey, false, false, false)
	# the stake-drivers' mallet and a bundle of new stakes, at the village end
	var timber := m.begin()
	for i in 6:
		var p := -south * 10.0 + across * (2.0 + float(i) * 0.12)
		var gy := k.on_ground(p.x, p.y).y
		m.block(timber, Transform3D(Basis(Vector3.UP, 0.05 * float(i)) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(p.x, gy + 0.06 + 0.1 * float(i % 2), p.y)), Vector3(0.06, 1.6, 0.06))
	lantern_pole(d, timber, -south * 10.5 - across * 2.0, south, true, 2.5)
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "Drivers")
	k.marker("the_last_row", k.on_ground(-south.x * 8.5, -south.y * 8.5))


# --- the marsh's pieces, the second pass ----------------------------------------------------------

## Bark gone to bone: a sallow dead so long its bark has fallen and the wood weathered grey.
const BONE_WOOD := {"base": "#9c968a", "accent": "#7c766b", "grout": "#4a463f", "unit": 0.35}
## Rush cord as the reedfolk twist it: undyed, and dyed in the one dye.
const RUSH := Color(0.55, 0.52, 0.38)

## A dead sallow at local `at`, `height` tall: a leaning trunk forking into limbs that fork again,
## all in one batch `st`. Returns the tips of its smallest limbs (local Vector3), where things hang.
static func dead_tree(d: PoiDressing, st: SurfaceTool, at: Vector2, height: float, lean_dir: Vector2,
		limbs := 6) -> Array:
	var k := d.kit
	var m := d.masonry
	var g := k.on_ground(at.x, at.y).y
	var lean := lean_dir.normalized() if lean_dir.length() > 0.01 else Vector2(1, 0)
	var base := Vector3(at.x, g - 0.4, at.y)
	var trunk_top := base + Vector3(lean.x * height * 0.12, height * 0.48, lean.y * height * 0.12)
	var r0 := height * 0.055
	m.limb(st, base, trunk_top, r0)
	# the root-flare: a few knuckles where the trunk meets the peat
	for i in 5:
		var a := TAU * float(i) / 5.0 + k.rng.randf()
		var rd := Vector3(sin(a), 0.0, cos(a))
		m.limb(st, base + Vector3.UP * 0.9, base + rd * (r0 * 3.2) + Vector3.UP * 0.15, r0 * 0.45)
	k.collider(Vector3(r0 * 1.6, height * 0.5, r0 * 1.6), Transform3D(Basis.IDENTITY, (base + trunk_top) * 0.5), "wood")
	var tips: Array = []
	for i in limbs:
		var a := TAU * float(i) / float(limbs) + k.rng.randf_range(-0.3, 0.3)
		var out := Vector3(sin(a), 0.0, cos(a))
		var rise := k.rng.randf_range(0.35, 0.8)
		var l1 := height * k.rng.randf_range(0.22, 0.32)
		var root := trunk_top + Vector3.UP * k.rng.randf_range(-height * 0.08, height * 0.06)
		var mid := root + (out + Vector3.UP * rise).normalized() * l1
		m.limb(st, root, mid, r0 * 0.55)
		for j in 3:
			var b := a + k.rng.randf_range(-0.7, 0.7)
			var out2 := Vector3(sin(b), 0.0, cos(b))
			var l2 := height * k.rng.randf_range(0.12, 0.2)
			# the outer limbs droop the way a sallow's do, so the cords hang clear of the trunk
			var tip := mid + (out2 + Vector3.UP * k.rng.randf_range(-0.35, 0.25)).normalized() * l2
			m.limb(st, mid, tip, r0 * 0.28)
			tips.append(tip)
			var twig := tip + (out2 + Vector3.DOWN * 0.5).normalized() * l2 * 0.4
			m.limb(st, tip, twig, r0 * 0.14)
			tips.append(twig)
	return tips


## Knotted cords hung from the points `from` (local Vector3): each a thin cord `lengths` long with
## knots down it, into `cord` (thin limbs) and `knots` (small balls). One name a cord.
static func cords(d: PoiDressing, cord: SurfaceTool, knots: SurfaceTool, from: Array, lengths := Vector2(0.5, 1.8),
		knot_every := 0.28) -> void:
	var k := d.kit
	var m := d.masonry
	for p in from:
		var top: Vector3 = p
		var l := k.rng.randf_range(lengths.x, lengths.y)
		var sway := Vector3(k.rng.randf_range(-0.06, 0.06), 0.0, k.rng.randf_range(-0.06, 0.06))
		var bottom := top + Vector3.DOWN * l + sway * l
		# a cord and its knots are boxes (twelve triangles each): a few hundred names hang here,
		# and a rounded cord with rounded knots was some hundreds of thousands of triangles
		var basis := _along(bottom - top)
		m.block(cord, Transform3D(basis, (top + bottom) * 0.5), Vector3(0.025, l, 0.025))
		var n := maxi(int(l / knot_every), 1)
		for q in n:
			if k.rng.randf() < 0.3:
				continue
			var t := (float(q) + 0.6) / float(n + 0.4)
			m.block(knots, Transform3D(basis.rotated(Vector3.UP, k.rng.randf() * TAU), top.lerp(bottom, t)), Vector3(0.06, 0.07, 0.06))


## A basis whose Y runs along `dir`.
static func _along(dir: Vector3) -> Basis:
	var y := dir.normalized() if dir.length() > 0.001 else Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y).normalized())


## Points spread along the limbs of a tree (the segments from `tips` back toward `centre`) and
## under its tips, for cords to hang from.
static func hang_points(d: PoiDressing, tips: Array, centre: Vector3, count: int) -> Array:
	var k := d.kit
	var out: Array = []
	for i in count:
		var tip: Vector3 = tips[k.rng.randi() % tips.size()]
		var t := k.rng.randf_range(0.0, 0.55)
		out.append(tip.lerp(centre, t) + Vector3.DOWN * 0.04)
	return out


## Flat stepping-stones from `a` to `b` (local xz), a stride apart, set into the peat.
static func stepping_stones(d: PoiDressing, st: SurfaceTool, a: Vector2, b: Vector2, stride := 1.15) -> void:
	var k := d.kit
	var m := d.masonry
	var n := maxi(int(a.distance_to(b) / stride), 1)
	var dir := (b - a).normalized()
	var side := Vector2(dir.y, -dir.x)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n)) + side * k.rng.randf_range(-0.25, 0.25)
		var g := k.on_ground(p.x, p.y).y
		m.ellipsoid(st, Vector3(p.x, g + 0.02, p.y), Vector3(k.rng.randf_range(0.32, 0.42), 0.09, k.rng.randf_range(0.26, 0.36)),
				Basis(Vector3.UP, k.rng.randf() * TAU))


# --- The Name-Wife's Hollow -------------------------------------------------------------------------

## The marsh-hag's hollow in the South Scarp: the cave's mouth at the foot of the scarp where it
## curls round a cove, the scarp weeping a thread of water over the mouth into a pool; a bog-oak
## beam across the mouth hung with knotted name-cords; in front, a dead sallow so hung with them it
## reads from the delta as a grey cloud against the scarp; under it what people brought to pay with
## besides names; and her stepping-stones out across the cove to the reeds.
static func name_wifes_hollow(d: PoiDressing) -> void:
	var k0 := d.kit
	if d.cave.is_empty():
		# The world raises no face for a delve: this one stands at the head of a gully in the scarp, and
		# its mouth is cut into a face of the scarp's own rock, the gully's walls either side of it.
		var into := k0.uphill()
		if into == Vector2.ZERO:
			into = Vector2(0, 1)
		var face := -into
		# the floor at the gully's lowest along the throat, so no ring of it stands proud of the ground
		var floor_y := k0.on_ground(into.x * 3.0, into.y * 3.0).y
		for i in 10:
			var q := into * (5.0 + float(i) * 2.0)
			floor_y = minf(floor_y, k0.on_ground(q.x, q.y).y)
		floor_y += d.world_position.y
		d.cave = {"facing_deg": rad_to_deg(atan2(face.x, face.y)), "mouth_m": floor_y, "face_top_m": floor_y + 9.5,
				"mouth_behind_m": 3.0, "face_half_width_m": 7.0}
	await PoiDressing.kind_builders().SITES.build(d)
	var k := d.kit
	var m := d.masonry
	var mouth := d.find_child("the_mouth", true, false) as Node3D
	var at := mouth.position if mouth != null else Vector3.ZERO
	var out := Vector2(-at.x, -at.z).normalized() if Vector2(at.x, at.z).length() > 0.5 else Vector2(0, -1)
	if mouth == null:
		out = k.downhill() if k.downhill() != Vector2.ZERO else Vector2(0, -1)
	var across := Vector2(out.y, -out.x)
	var m2 := Vector2(at.x, at.z)
	var g0 := k.on_ground(m2.x, m2.y).y
	# the gully's floor runs on level behind the mouth before the headwall rises, and would leave the
	# throat standing out of it: a knoll of the scarp's rock heaped over it, its foot in the gully floor
	var knoll_c := m2 - out * 14.0
	var kg := k.on_ground(knoll_c.x, knoll_c.y).y
	if kg < g0 + 5.0:
		m.mound(Vector3(knoll_c.x, kg - 0.6, knoll_c.y), 10.0, g0 - kg + 7.5, k.surface("stone", 0.9), "Knoll", true, 1.3, 7, 22, true, 0.14)
		var boulder := k.rock("boulder")
		if boulder != "":
			var bx: Array = []
			for i in 7:
				var a := k.rng.randf() * TAU
				var r := k.rng.randf_range(3.0, 8.0)
				var q := knoll_c + Vector2(sin(a), cos(a)) * r
				if (q - m2).dot(out) > -2.5:
					continue
				var hy := (g0 - kg + 7.5) * sqrt(maxf(1.0 - pow(r / 10.0, 2.0), 0.0))
				bx.append(PoiKit.transform_at(Vector3(q.x, kg - 0.6 + hy - 0.4, q.y), k.rng.randf() * TAU, k.rng.randf_range(1.0, 1.8)))
			await k.step()
			k.scatter(boulder, bx, true, true, true)
	# the Name-Tree: in front of the mouth and to one side, leaning out over the cove
	var tree_at := m2 + out * 10.0 - across * 6.5
	var wood := m.begin()
	var tips: Array = dead_tree(d, wood, tree_at, 12.5, out - across * 0.3, 7)
	await k.step()
	m.commit(wood, PoiKit.painted(3, BONE_WOOD, 0.85), "NameTree", true)
	var tc := Vector3(tree_at.x, k.on_ground(tree_at.x, tree_at.y).y + 6.0, tree_at.y)
	var cord := m.begin()
	var knots := m.begin()
	cords(d, cord, knots, tips, Vector2(0.8, 2.6))
	cords(d, cord, knots, hang_points(d, tips, tc, 110 if not k.far else 40), Vector2(0.6, 2.2))
	await k.step()
	m.commit(cord, PoiKit.plain(RUSH.lerp(Color(0.8, 0.78, 0.7), 0.35), 0.95), "TreeCords", true)
	m.commit(knots, PoiKit.plain(INDIGO.lerp(Color(0.6, 0.6, 0.62), 0.3), 0.9), "TreeKnots", true)
	# the weep: a thread of water off the brow beside the mouth, into a pool at its foot
	var fall_at := m2 + across * 4.6 + out * 1.0
	var fg := k.on_ground(fall_at.x, fall_at.y).y
	var fall_h := maxf(float(d.cave.get("face_top_m", 0.0)) - d.world_position.y - fg - 0.3, 7.5)
	m.sheet(Vector3(fall_at.x, fg + fall_h, fall_at.y), PoiKit.yaw_of(out), 1.3, fall_h + 0.2, PoiKit.falling_water(false, 2.2),
			"Weep", 0.5, true, 3, 6)
	if k.far:
		return
	var pool_c := fall_at + out * 1.4
	m.pool(pool_c, 1.9, k.on_ground(pool_c.x, pool_c.y).y + 0.06, k.still_water(-0.6, Color(0.8, 0.95, 0.9), 0.8), "WeepPool", 18)
	k.puffs(Vector3(fall_at.x, fg + 0.6, fall_at.y) + Vector3(out.x, 0, out.y) * 0.8, Vector3(0.8, 0.3, 0.8), 1.4, 6,
			Color(0.8, 0.84, 0.82, 0.25), 1.6, 3.5)
	k.marker("the_fall", k.on_ground(pool_c.x + out.x * 2.5, pool_c.y + out.y * 2.5))
	var rims := m.begin()
	for j in 9:
		var a := TAU * float(j) / 9.0 + k.rng.randf()
		var q := pool_c + Vector2(sin(a), cos(a)) * 2.05
		m.ellipsoid(rims, k.on_ground(q.x, q.y, 0.03), Vector3(0.4, 0.16, 0.3), Basis(Vector3.UP, a))
	await k.step()
	m.commit(rims, k.surface("stone", 0.9), "PoolStones")
	# the beam across the mouth on two bog-oak posts, hung with cords from end to end
	var beam_c := m2 + out * 1.6
	var timber := m.begin()
	var tops: Array = []
	for s in [-1.0, 1.0]:
		var p := beam_c + across * 2.9 * float(s)
		tops.append(m.post(timber, p, 3.6, 0.3, Vector3(k.rng.randf_range(-0.03, 0.03), 0.0, k.rng.randf_range(-0.03, 0.03))))
	var ta: Vector3 = tops[0]
	var tb: Vector3 = tops[1]
	m.limb(timber, ta + Vector3.DOWN * 0.15 - Vector3(across.x, 0, across.y) * 0.4, tb + Vector3.DOWN * 0.15 + Vector3(across.x, 0, across.y) * 0.4, 0.19)
	await k.step()
	m.commit(timber, PoiKit.plain(Color(0.09, 0.08, 0.07), 0.8), "BogOakBeam", true)
	var beam_points: Array = []
	for i in 46:
		var t := (float(i) + 0.5) / 46.0
		beam_points.append(ta.lerp(tb, t) + Vector3.DOWN * 0.3)
	var cord2 := m.begin()
	var knots2 := m.begin()
	cords(d, cord2, knots2, beam_points, Vector2(0.9, 2.3))
	await k.step()
	m.commit(cord2, PoiKit.plain(RUSH, 0.95), "BeamCords")
	m.commit(knots2, PoiKit.plain(INDIGO, 0.9), "BeamKnots")
	var mid := (ta + tb) * 0.5
	k.touchable("Hook", Vector3(mid.x, g0 + 1.3, mid.z) + Vector3(out.x, 0, out.y) * 0.5, "Read the knots on the beam",
			"core:dialogue/name_wifes_beam", "", false)
	# what people brought besides names, heaped at the tree's foot: baskets, a coil, a lantern, a pot
	var gifts := tree_at + out * 1.8 + across * 1.2
	for kind in ["basket", "rope_coil", "bucket", "basket", "lantern_hand", "cooking_pot"]:
		var pk := k.prop(kind)
		if pk == "":
			continue
		var q := gifts + k.jitter(1.1)
		await k.step()
		k.place(pk, k.on_ground(q.x, q.y), k.rng.randf() * TAU, 1.0, false)
	k.marker("the_gifts", k.on_ground(gifts.x + out.x * 1.5, gifts.y + out.y * 1.5))
	# the hounds' bones by the mouth, gnawed
	var bones := m.begin()
	for i in 9:
		var q := m2 + out * k.rng.randf_range(2.5, 5.0) + across * k.rng.randf_range(-3.5, -1.5)
		var a := k.rng.randf() * TAU
		var p := k.on_ground(q.x, q.y, 0.04)
		m.limb(bones, p, p + Vector3(sin(a), 0.02, cos(a)) * k.rng.randf_range(0.25, 0.5), 0.025)
	await k.step()
	m.commit(bones, PoiKit.plain(Color(0.78, 0.74, 0.64), 0.8), "Bones")
	k.marker("the_den", k.on_ground(m2.x + out.x * 4.0 - across.x * 2.5, m2.y + out.y * 4.0 - across.y * 2.5))
	# her stepping-stones out across the cove toward the reeds, and a pole by them with a cold light
	var steps := m.begin()
	stepping_stones(d, steps, m2 + out * 3.0 + across * 1.0, m2 + out * 21.0 + across * 3.5)
	await k.step()
	m.commit(steps, k.surface("stone", 0.9), "SteppingStones")
	var poles := m.begin()
	var pole_at := m2 + out * 14.0 + across * 5.0
	var arm := lantern_pole(d, poles, pole_at, -across, false, 2.7, 0.05)
	await k.step()
	m.commit(poles, PoiKit.plain(Color(0.09, 0.08, 0.07), 0.85), "WispPole")
	k.light(arm - Vector3(0.0, 0.7, 0.0), Color(0.55, 0.9, 0.85), 1.2, 7.0)
	# the throat breathes cold: a teal light in it
	k.light(Vector3(at.x, g0 + 1.8, at.z) - Vector3(out.x, 0, out.y) * 2.0, Color(0.5, 0.85, 0.8), 1.4, 7.0)
	# sedge and fern at the scarp's foot, reeds out on the cove
	var fern := k.flora("fern")
	if fern != "":
		var xfs: Array = []
		for i in 26:
			var q := m2 + across * k.rng.randf_range(-11.0, 11.0) + out * k.rng.randf_range(-1.0, 3.0)
			if absf((q - m2).dot(across)) < 3.6:
				continue
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, k.rng.randf_range(0.8, 1.3)))
		await k.step()
		k.scatter(fern, xfs, false, false, false)
	await reeds(d, 12.0, 19.5, 60, [[m2 + out * 12.0, 4.0], [tree_at, 3.0], [m2 - out * 14.0, 17.0]])


# --- The South Stilts ---------------------------------------------------------------------------------

## Nauvissa's watch-house on tall braced stilts on a shelf of the South Scarp, its porch and stair to
## the scarp's lip where the grey sits; the watchman's knot-rail along the porch, a cold beacon basket
## on a pole to warn the village, and up the slope a row of withies tagged grey where he has seen it
## come down to.
static func south_stilts(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.uphill()
	if face == Vector2.ZERO:
		face = Vector2(0, 1)
	var side := Vector2(face.y, -face.x)
	var hc := -face * 2.5
	var house: Dictionary = await stilt_house(d, hc, face, 3.8, 3.4, 4.2, "Watch", 20)
	var deck_y := float(house["deck_y"])
	# the beacon: an iron basket on a tall pole beside the house, laid and not lit
	var timber := m.begin()
	var bp := hc + side * 4.2 - face * 0.5
	var btop := m.post(timber, bp, 8.2, 0.24)
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "BeaconPole", true)
	var iron := m.begin()
	for i in 8:
		var a := TAU * float(i) / 8.0
		m.limb(iron, btop + Vector3(sin(a) * 0.3, -0.1, cos(a) * 0.3), btop + Vector3(sin(a) * 0.55, 0.6, cos(a) * 0.55), 0.035)
	m.limb(iron, btop + Vector3(0.0, -0.05, 0.0), btop + Vector3(0.0, 0.05, 0.0), 0.34)
	await k.step()
	m.commit(iron, PoiKit.plain(Color(0.13, 0.12, 0.11), 0.55, 0.5), "BeaconBasket", true)
	if k.far:
		return
	var faggots := m.begin()
	for i in 7:
		var a := k.rng.randf() * TAU
		m.limb(faggots, btop + Vector3(sin(a) * 0.3, 0.12, cos(a) * 0.3), btop + Vector3(-sin(a) * 0.2, 0.5, -cos(a) * 0.2), 0.05)
	await k.step()
	m.commit(faggots, k.surface("timber", 0.9), "BeaconWood")
	k.marker("home", house["inside"], true, true, 1.5)
	# the porch rail, and the knot-cords hung on it: a cord for each week the grey has moved
	var front: Vector3 = house["door"]
	var rail := m.begin()
	var porch_front := Vector2(front.x, front.z) + face * 0.75
	var ra := porch_front - side * 2.0
	var rb := porch_front + side * 2.0
	for p in [ra, rb]:
		var q: Vector2 = p
		m.block(rail, Transform3D(Basis.IDENTITY, Vector3(q.x, deck_y + 0.5, q.y)), Vector3(0.1, 1.0, 0.1))
	var rail_a := Vector3(ra.x, deck_y + 0.98, ra.y)
	var rail_b := Vector3(rb.x, deck_y + 0.98, rb.y)
	m.limb(rail, rail_a, rail_b, 0.045)
	await k.step()
	m.commit(rail, k.surface("timber", 0.8), "KnotRail")
	var cord := m.begin()
	var knots := m.begin()
	var pts: Array = []
	for i in 9:
		# not where the stair comes up
		var t := float(i) / 8.0
		if absf(t - 0.5) < 0.12:
			continue
		pts.append(rail_a.lerp(rail_b, t))
	cords(d, cord, knots, pts, Vector2(0.4, 0.75), 0.12)
	await k.step()
	m.commit(cord, PoiKit.plain(RUSH, 0.95), "RailCords")
	m.commit(knots, PoiKit.plain(Color(0.55, 0.55, 0.53), 0.9), "RailKnots")
	k.marker("the_watch", Vector3(front.x, deck_y, front.z) + Vector3(face.x, 0.0, face.y) * 0.4, true, true, 1.2)
	k.touchable("KnotRail", rail_a.lerp(rail_b, 0.2) - Vector3(0, 0.3, 0), "Count the knots on the rail", "core:dialogue/south_stilts_knots", "", false)
	# the withies up the slope, tagged grey where he saw it come down to
	var stakes := m.begin()
	var tags := m.begin()
	for i in 5:
		var p := face * (8.0 + float(i) * 2.6) + side * (float(i) - 2.0) * 1.4 + k.jitter(0.3)
		var top := m.post(stakes, p, 1.4 + k.rng.randf_range(-0.1, 0.2), 0.08, Vector3(k.rng.randf_range(-0.05, 0.05), 0.0, 0.05))
		m.block(tags, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), top - Vector3(0, 0.15, 0)), Vector3(0.12, 0.2, 0.05))
	await k.step()
	m.commit(stakes, k.surface("timber", 0.7), "Withies")
	m.commit(tags, PoiKit.plain(Color(0.6, 0.6, 0.58), 0.95), "GreyTags")
	# at the stair's foot: his bench, the fire he cooks at, an eel-basket
	var foot: Vector3 = house["foot"]
	var f2 := Vector2(foot.x, foot.z)
	var hearth := f2 - side * 3.0 - face * 1.0
	var fire := k.prop("campfire")
	if fire != "":
		await k.step()
		k.place(fire, k.on_ground(hearth.x, hearth.y), k.rng.randf() * TAU, 0.9, false)
		k.light(k.on_ground(hearth.x, hearth.y, 0.5), Color(1.0, 0.62, 0.32), 1.6, 8.0)
	var bench := k.prop("bench")
	if bench != "":
		var bq := hearth - side * 1.6
		await k.step()
		k.place(bench, k.on_ground(bq.x, bq.y), PoiKit.yaw_of(side), 1.0, true)
	for kind in ["basket", "cooking_pot"]:
		var pk := k.prop(kind)
		if pk != "":
			var q := hearth + face * 1.3 + k.jitter(0.5)
			await k.step()
			k.place(pk, k.on_ground(q.x, q.y), k.rng.randf() * TAU, 1.0, false)
	k.marker("the_foot", k.on_ground(hearth.x - side.x * 1.6 + face.x * 0.9, hearth.y - side.y * 1.6 + face.y * 0.9), true)
	var grass := k.flora("sedge_tussock")
	if grass != "":
		var xfs: Array = []
		for i in 40:
			var a := k.rng.randf() * TAU
			var r := k.rng.randf_range(6.0, 16.0)
			var q := Vector2(sin(a), cos(a)) * r
			if q.distance_to(hc) < 5.5 or q.distance_to(hearth) < 2.5:
				continue
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, k.rng.randf_range(0.8, 1.2)))
		await k.step()
		k.scatter(grass, xfs, false, false, false)


# --- Crookstilts --------------------------------------------------------------------------------------

## The marsh-hag's trading stilts in the carr: a small hut on stilts each leaning its own way, a ladder
## of a stair, cords hung under the deck from the bearers (the names not yet carried south), the slate
## of her price on a post at the ladder's foot by the flat stone you stand on to say a name, the
## offerings left there, a little dead sallow with a few cords, and her lantern pole with its cold light.
static func crookstilts(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.grain()
	var side := Vector2(face.y, -face.x)
	var hc := -face * 1.5
	var house: Dictionary = await stilt_house(d, hc, face, 3.6, 3.2, 2.4, "Crook", 12, 0.16)
	var deck_y := float(house["deck_y"])
	var tree_at := hc - face * 5.5 + side * 5.0
	var wood := m.begin()
	var tips: Array = dead_tree(d, wood, tree_at, 6.5, -face + side, 5)
	await k.step()
	m.commit(wood, PoiKit.painted(3, BONE_WOOD, 0.85), "CrookTree", true)
	if k.far:
		return
	k.marker("home", house["inside"], true, true, 1.5)
	# under the deck, from the bearers, the names she has not yet carried south
	var cord := m.begin()
	var knots := m.begin()
	var under: Array = []
	for i in 22:
		var p := hc + side * k.rng.randf_range(-1.6, 1.6) + face * k.rng.randf_range(-1.6, 2.0)
		under.append(Vector3(p.x, deck_y - 0.28, p.y))
	cords(d, cord, knots, under, Vector2(0.6, 1.5))
	cords(d, cord, knots, tips, Vector2(0.5, 1.4))
	await k.step()
	m.commit(cord, PoiKit.plain(RUSH, 0.95), "Cords")
	m.commit(knots, PoiKit.plain(INDIGO, 0.9), "Knots")
	# the price: a slate on a post at the stair's foot, and the flat stone you stand on to say a name
	var foot: Vector3 = house["foot"]
	var f2 := Vector2(foot.x, foot.z) + face * 0.6
	var timber := m.begin()
	var post_at := f2 + side * 1.4
	var top := m.post(timber, post_at, 1.6, 0.14)
	await k.step()
	m.commit(timber, PoiKit.plain(Color(0.09, 0.08, 0.07), 0.8), "SlatePost")
	var slate := m.begin()
	m.block(slate, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), top - Vector3(0, 0.35, 0) + Vector3(face.x, 0, face.y) * 0.1), Vector3(0.5, 0.36, 0.03))
	await k.step()
	m.commit(slate, PoiKit.plain(Color(0.17, 0.18, 0.2), 0.6), "PriceSlate")
	k.marker("the_slate", k.on_ground(post_at.x + face.x * 0.8, post_at.y + face.y * 0.8))
	var stone := m.begin()
	m.ellipsoid(stone, k.on_ground(f2.x + face.x * 1.2, f2.y + face.y * 1.2, 0.02), Vector3(0.75, 0.12, 0.6), Basis(Vector3.UP, 0.4))
	await k.step()
	m.commit(stone, k.surface("stone", 0.8), "SayingStone")
	k.marker("the_saying_stone", k.on_ground(f2.x + face.x * 1.2, f2.y + face.y * 1.2, 0.1), true)
	k.touchable("SayingStone", k.on_ground(f2.x + face.x * 1.2, f2.y + face.y * 1.2, 0.6), "Stand on the flat stone",
			"core:dialogue/crookstilts_saying_stone", "", false)
	# what was left at the foot to sweeten it: baskets, a pot, a lantern, a pair of boots
	for kind in ["basket", "cooking_pot", "lantern_hand", "boots", "basket"]:
		var pk := k.prop(kind)
		if pk == "":
			continue
		var q := f2 - side * 1.6 + face * k.rng.randf_range(0.0, 1.4) + k.jitter(0.4)
		await k.step()
		k.place(pk, k.on_ground(q.x, q.y), k.rng.randf() * TAU, 1.0, false)
	# her lantern pole, its light cold
	var poles := m.begin()
	var arm := lantern_pole(d, poles, f2 + face * 3.4 - side * 2.6, side, false, 2.6, 0.08)
	await k.step()
	m.commit(poles, PoiKit.plain(Color(0.09, 0.08, 0.07), 0.85), "HagPole")
	k.light(arm - Vector3(0.0, 0.7, 0.0), Color(0.55, 0.9, 0.85), 1.1, 7.0)
	await reeds(d, 7.0, 16.0, 70, [[f2 + face * 2.0, 3.5], [tree_at, 2.5], [hc, 4.0]])


# --- The Sounding -----------------------------------------------------------------------------------

## The Flood-Callers' bell-tower on the North Shore: a drowned Builders' platform of black fused stone
## standing out of a mere inside the stumps of its ring-wall, and on it a tower of black bog-oak raised
## by the Callers, braced in four stages, a stair of four flights climbing round its outside to a
## railed deck, and over the deck a hood with their bell hung under it, cast from the brass of a
## thousand lantern-hooks, cut burial lanterns strung round its eaves. The door into the platform's
## undercroft is at its back, in a recess of the Builders' black stone; the Callers' camp is at its
## foot by the steps, their lanterns heaped, their punts drawn up.
const SOUNDING_PLINTH := 7.5     ## the platform's half-width
const SOUNDING_TOP := 2.8        ## its height over the pad
const SOUNDING_LEG := 3.0        ## the tower's legs' offset from the middle
const SOUNDING_DECK := 15.0      ## the deck over the platform

static func the_sounding(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var front := Vector2(-0.95, 0.3).normalized()      # toward Mor'oul and Moreva, the way people come
	var side := Vector2(front.y, -front.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(front))
	var g := k.on_ground(0.0, 0.0).y
	var top := g + SOUNDING_TOP
	var P := SOUNDING_PLINTH
	# the platform: a slab of fused black stone with a recess in its back for the door, broken at one
	# corner where a block has slid into the mere
	var oroth := m.begin()
	var recess_w := 2.0
	var recess_d := 1.2
	var main_c := Vector3(0.0, (g - 1.0 + top) * 0.5, 0.0) + basis * Vector3(0.0, 0.0, recess_d * 0.5)
	var main_size := Vector3(P * 2.0, top - g + 1.0, P * 2.0 - recess_d)
	m.block(oroth, Transform3D(basis, main_c), main_size)
	k.collider(main_size, Transform3D(basis, main_c), "stone")
	for s in [-1.0, 1.0]:
		var w := P - recess_w * 0.5
		var c := Vector3(0.0, (g - 1.0 + top) * 0.5, 0.0) + basis * Vector3(float(s) * (recess_w * 0.5 + w * 0.5), 0.0, -P + recess_d * 0.5)
		m.block(oroth, Transform3D(basis, c), Vector3(w, top - g + 1.0, recess_d))
		k.collider(Vector3(w, top - g + 1.0, recess_d), Transform3D(basis, c), "stone")
	var lintel_c := Vector3(0.0, top - 0.25, 0.0) + basis * Vector3(0.0, 0.0, -P + recess_d * 0.5)
	m.block(oroth, Transform3D(basis, lintel_c), Vector3(recess_w + 0.1, 0.5, recess_d))
	# a coping course stood a little proud all round, and the Builders' jambs either side of the door
	for q in 4:
		var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(q))
		m.block(oroth, Transform3D(bb, Vector3(0.0, top + 0.08, 0.0) + bb * Vector3(0.0, 0.0, P - 0.3)), Vector3(P * 2.0 + 0.3, 0.22, 0.75))
	for s in [-1.0, 1.0]:
		var jc := Vector3(0.0, g + 1.3, 0.0) + basis * Vector3(float(s) * (recess_w * 0.5 + 0.3), 0.0, -P - 0.15)
		m.block(oroth, Transform3D(basis, jc), Vector3(0.6, 2.9, 0.5))
	# the slid block at the corner, canted into the mere
	var corner := basis * Vector3(P + 0.9, 0.0, P - 1.5)
	m.block(oroth, Transform3D(basis * Basis(Vector3.FORWARD, 0.22) * Basis(Vector3.RIGHT, -0.1), Vector3(corner.x, g + 0.4, corner.z)), Vector3(2.4, 1.6, 2.8))
	# the steps up the front, the full stair of the Builders' width
	var steps_n := 12
	var rise := (top - g) / float(steps_n)
	var tread := 0.4
	var st_start := front * (P + tread * float(steps_n))
	m.steps(oroth, st_start, -front, g, steps_n, rise, tread, 4.2, 0.6)
	await k.step()
	m.commit(oroth, k.surface("oroth", 0.75), "Platform", true)
	var dark := m.begin()
	m.block(dark, Transform3D(basis, Vector3(0.0, g + (top - g - 0.5) * 0.5, 0.0) + basis * Vector3(0.0, 0.0, -P + recess_d + 0.02)), Vector3(recess_w, top - g - 0.5, 0.05))
	await k.step()
	m.commit(dark, PoiKit.plain(DOOR_DARK, 0.95), "UndercroftDoor")
	# the tower: four legs of bog-oak on the platform, girts and crosses in four stages
	var oak := m.begin()
	var L := SOUNDING_LEG
	var deck := top + SOUNDING_DECK
	var legs: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			legs.append(Vector3(0.0, 0.0, 0.0) + basis * Vector3(float(sx) * L, 0.0, float(sz) * L))
	for leg in legs:
		# each leg is sunk through the platform to the peat under it, the way the Callers stepped it
		var lc := Vector3(leg.x, (g - 0.3 + deck + 0.4) * 0.5, leg.z)
		m.block(oak, Transform3D(basis, lc), Vector3(0.5, deck + 0.7 - g, 0.5))
		k.collider(Vector3(0.5, deck + 0.4 - top, 0.5), Transform3D(basis, Vector3(leg.x, (top + deck + 0.4) * 0.5, leg.z)), "wood")
		m.block(oak, Transform3D(basis, Vector3(leg.x, top + 0.25, leg.z)), Vector3(0.9, 0.5, 0.9))
	var stages := 4
	var order := [legs[0], legs[1], legs[3], legs[2]]
	for st_i in stages + 1:
		var y := top + SOUNDING_DECK * float(st_i) / float(stages)
		for q in 4:
			var a: Vector3 = order[q]
			var b: Vector3 = order[(q + 1) % 4]
			if st_i > 0:
				m.limb(oak, Vector3(a.x, y - 0.1, a.z), Vector3(b.x, y - 0.1, b.z), 0.13)
			if st_i < stages:
				var y1 := top + SOUNDING_DECK * float(st_i + 1) / float(stages)
				m.limb(oak, Vector3(a.x, y + 0.2, a.z), Vector3(b.x, y1 - 0.3, b.z), 0.09)
				m.limb(oak, Vector3(b.x, y + 0.2, b.z), Vector3(a.x, y1 - 0.3, a.z), 0.09)
	# the deck, railed, and the hood over it on four posts, the bell's beam under the hood
	var deck_half := L + 0.45
	m.block(oak, Transform3D(basis, Vector3(0.0, deck - 0.1, 0.0)), Vector3(deck_half * 2.0, 0.2, deck_half * 2.0))
	k.collider(Vector3(deck_half * 2.0, 0.25, deck_half * 2.0), Transform3D(basis, Vector3(0.0, deck - 0.12, 0.0)), "wood")
	for q in 4:
		var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(q))
		var e := bb * Vector3(0.0, 0.0, deck_half - 0.05)
		# the rail, open beside the stair's head (the last flight comes up along the fourth face)
		var gap := 2.4 if q == 3 else 0.0
		var run := deck_half * 2.0 - gap
		var off := bb * Vector3(gap * 0.5, 0.0, 0.0)
		m.block(oak, Transform3D(bb, Vector3(0.0, deck + 1.0, 0.0) + e + off), Vector3(run, 0.12, 0.12))
		k.collider(Vector3(run, 1.1, 0.15), Transform3D(bb, Vector3(0.0, deck + 0.55, 0.0) + e + off), "wood")
	var hood_y := deck + 3.6
	var apex := Vector3(0.0, hood_y + 3.0, 0.0)
	for leg in legs:
		m.block(oak, Transform3D(basis, Vector3(leg.x, (deck + hood_y) * 0.5, leg.z)), Vector3(0.32, hood_y - deck, 0.32))
		m.limb(oak, Vector3(leg.x * 1.25, hood_y - 0.3, leg.z * 1.25), apex, 0.12)
	m.limb(oak, Vector3(legs[0].x, hood_y - 0.4, legs[0].z), Vector3(legs[3].x, hood_y - 0.4, legs[3].z), 0.14)
	# the stair: four flights round the outside, each climbing a quarter of the height along a face,
	# a landing at every corner
	var so := L + 0.9
	var corners: Array[Vector3] = []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var cv: Vector2 = c
		corners.append(basis * Vector3(cv.x * so, 0.0, cv.y * so))
	var flight_rise := SOUNDING_DECK / 4.0
	var n_steps := 15
	for f in 4:
		var a: Vector3 = corners[f]
		var b: Vector3 = corners[(f + 1) % 4]
		var y0 := top + flight_rise * float(f)
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var dir := (b2 - a2).normalized()
		var run := a2.distance_to(b2) - 1.3
		var start := a2 + dir * 0.65
		m.steps(oak, start, dir, y0, n_steps, flight_rise / float(n_steps), run / float(n_steps), 1.1, 0.16)
		# the stringers under it
		for s in [-1.0, 1.0]:
			var off := Vector2(dir.y, -dir.x) * 0.5 * float(s)
			m.limb(oak, Vector3(start.x + off.x, y0 - 0.1, start.y + off.y), Vector3(start.x + off.x + dir.x * run, y0 + flight_rise - 0.12, start.y + off.y + dir.y * run), 0.07)
		# the landing at its head, on a bracket off the leg
		var land := Vector3(b.x, y0 + flight_rise - 0.08, b.z)
		m.block(oak, Transform3D(basis, land), Vector3(1.3, 0.16, 1.3))
		k.collider(Vector3(1.3, 0.2, 1.3), Transform3D(basis, land), "wood")
		m.limb(oak, land + Vector3(0, -0.1, 0), Vector3(b.x * 0.82, y0 + flight_rise - 1.4, b.z * 0.82), 0.08)
	# the first landing, on the platform
	m.block(oak, Transform3D(basis, Vector3(corners[0].x, top + 0.05, corners[0].z)), Vector3(1.3, 0.1, 1.3))
	await k.step()
	m.commit(oak, PoiKit.plain(Color(0.085, 0.075, 0.065), 0.8), "Tower", true)
	var hood := m.begin()
	for q in 4:
		var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(q))
		var e := bb * Vector3(0.0, 0.0, (L + 1.2) * 0.5)
		m.block(hood, Transform3D(bb * Basis(Vector3.RIGHT, -0.75), Vector3(0.0, hood_y + 1.45, 0.0) + e), Vector3((L + 1.2) * 2.0, 0.12, (L + 1.2) * 1.45))
	await k.step()
	m.commit(hood, k.surface("planks", 0.9), "Hood", true)
	# the bell under the hood, and the Callers' cut lanterns strung round its eaves
	var bell := k.prop("bell_medium")
	if bell != "":
		# a great bell, two metres of it, hung from the beam under the hood
		var bs := 2.0 / maxf(PoiKit.height_of(bell), 0.3)
		await k.step()
		k.place(bell, Vector3(0.0, hood_y - 0.45 - PoiKit.height_of(bell) * bs, 0.0), PoiKit.yaw_of(front), bs, false, Vector3.ZERO, true)
	if k.far:
		return
	var cord := m.begin()
	var paper := m.begin()
	for q in 4:
		var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(q))
		for i in 5:
			var t := (float(i) + 0.5) / 5.0 - 0.5
			var at := Vector3(0.0, hood_y - 0.2, 0.0) + bb * Vector3(t * (L + 1.2) * 1.9, 0.0, L + 1.25)
			var l := k.rng.randf_range(0.5, 1.2)
			m.block(cord, Transform3D(Basis.IDENTITY, at - Vector3(0, l * 0.5, 0)), Vector3(0.025, l, 0.025))
			var lb := Basis(Vector3.UP, k.rng.randf() * TAU)
			m.block(paper, Transform3D(lb, at - Vector3(0, l + 0.18, 0)), Vector3(0.26, 0.34, 0.26))
	await k.step()
	m.commit(cord, PoiKit.plain(RUSH, 0.95), "EaveCords")
	m.commit(paper, PoiKit.plain(INDIGO, 0.85), "CutLanterns")
	k.marker("the_bell_deck", Vector3(0.0, deck, 0.0) + basis * Vector3(L * 0.5, 0.0, L * 0.4), false, true, 2.0)
	k.marker("the_stair_foot", Vector3(corners[0].x, top, corners[0].z) + basis * Vector3(1.0, 0.0, -0.4))
	k.touchable("Hook", Vector3(legs[0].x, top + 1.3, legs[0].z) + basis * Vector3(0.0, 0.0, 0.4), "Look at the marks cut up the leg",
			"core:dialogue/the_sounding_marks", "", false)
	# the door into the undercroft, in the recess at the back
	var door_at := basis * Vector3(0.0, 0.0, -P + recess_d - 0.15) + Vector3(0.0, g, 0.0)
	PoiDressing.kind_builders().SITES._door(d, "core:interior/the_sounding_undercroft", door_at, PoiKit.yaw_of(-front))
	k.light(door_at + basis * Vector3(1.2, 2.1, -0.6), Color(0.55, 0.85, 1.0), 1.2, 6.0)
	k.marker("the_back_door", door_at + basis * Vector3(0.0, 0.0, -2.5))
	# the ring of the Builders' wall, drowned to its stumps, the mere in it and round it
	var stumps := m.begin()
	var ring_r := 14.5
	var gaps := [1, 5]
	for i in 10:
		if i in gaps:
			continue
		var a0 := PoiKit.yaw_of(front) + TAU * (float(i) + 0.1) / 10.0
		var a1 := PoiKit.yaw_of(front) + TAU * (float(i) + 0.8) / 10.0
		var pa := Vector2(sin(a0), cos(a0)) * ring_r
		var pb := Vector2(sin(a1), cos(a1)) * ring_r
		m.wall(stumps, pa, pb, k.rng.randf_range(0.6, 1.9), 0.6)
	await k.step()
	m.commit(stumps, k.surface("oroth", 0.85), "RingStumps", true)
	var mere := k.still_water(-0.8, Color(0.75, 0.82, 0.8), 0.75)
	for i in 5:
		var a := PoiKit.yaw_of(front) + PI * 0.6 + float(i) * 0.75 + k.rng.randf_range(-0.15, 0.15)
		var c := Vector2(sin(a), cos(a)) * k.rng.randf_range(10.0, 12.5)
		m.pool(c, k.rng.randf_range(2.4, 3.6), k.on_ground(c.x, c.y).y + 0.05, mere, "Mere%d" % i, 18)
	# the Callers' camp at the foot of the steps: a lean-to, the fire, bedrolls, the lanterns heaped
	var camp := front * (P + 6.5) + side * 5.0
	var fire := k.prop("campfire")
	if fire != "":
		await k.step()
		k.place(fire, k.on_ground(camp.x, camp.y), 0.0, 1.0, false)
		k.light(k.on_ground(camp.x, camp.y, 0.6), Color(1.0, 0.6, 0.3), 1.8, 9.0)
	var roll := k.prop("bedroll")
	for i in 3:
		if roll == "":
			break
		var a := float(i) * 1.1 - 1.1
		var q := camp + Vector2(sin(a + PoiKit.yaw_of(side)), cos(a + PoiKit.yaw_of(side))) * 2.6
		await k.step()
		k.place(roll, k.on_ground(q.x, q.y), a + PoiKit.yaw_of(side) + PI * 0.5, 1.0, false)
	k.marker("the_camp", k.on_ground(camp.x - side.x * 1.5, camp.y - side.y * 1.5))
	await lantern_heap(d, camp + front * 3.2 - side * 2.0, 1.4, 22)
	await lantern_heap(d, front * (P + 1.6) - side * 4.5, 1.0, 12)
	await dye_line(d, camp - side * 3.5 + front * 1.5, camp - side * 3.5 + front * 5.0, 3)
	# dark poles out along the way in, each with a cut lantern
	var poles := m.begin()
	for i in 3:
		for s in [-1.0, 1.0]:
			var p := front * (P + 6.0 + float(i) * 3.4) + side * 2.6 * float(s) + k.jitter(0.2)
			if p.distance_to(camp) < 3.0:
				continue
			lantern_pole(d, poles, p, -side * float(s), false, 2.7, k.rng.randf_range(-0.05, 0.05))
	await k.step()
	m.commit(poles, PoiKit.plain(Color(0.09, 0.08, 0.07), 0.85), "CallersPoles")
	# their punts drawn up on the mere's edge
	var boat := k.prop("rowboat")
	if boat != "":
		for i in 2:
			var bp := -side * (ring_r + 1.5) + front * (float(i) * 2.6 - 1.0)
			await k.step()
			k.place(boat, k.on_ground(bp.x, bp.y, 0.05), PoiKit.yaw_of(front) + 0.2 * float(i), 1.0, true)
	await reeds(d, 15.5, 24.0, 80, [[front * 20.0, 4.5]])


## Black standing water at local `c`, `r` across: a sheet at the ground's height there that reads as
## deep (its depth fade taken from a floor `depth` under it), the pad being level and the land not dug
## at runtime. Returns the water's height.
static func black_water(d: PoiDressing, c: Vector2, r: float, depth := 2.5, node_name := "BlackWater", segments := 26) -> float:
	var k := d.kit
	var y := k.on_ground(c.x, c.y).y + 0.07
	for i in 6:
		var a := TAU * float(i) / 6.0
		y = maxf(y, k.on_ground(c.x + sin(a) * r * 0.6, c.y + cos(a) * r * 0.6).y + 0.05)
	# dark: peat water stands black and takes the sky only at a low angle; its ripples small and few
	# (the shader's own, wide and strong, made a big pool read as a sheet of mottled plastic)
	var mat := k.still_water(y - depth, Color(0.45, 0.55, 0.55), 0.95)
	mat.set_shader_parameter("wave_scale", 1.3)
	mat.set_shader_parameter("wave_strength", 0.08)
	mat.set_shader_parameter("sheen_color", Color(0.35, 0.42, 0.42))
	d.masonry.pool(c, r, y, mat, node_name, segments)
	return y


## Stones round the edge of water at `c`, `r` out: the rim that hides where a sheet meets the peat.
static func rim_stones(d: PoiDressing, st: SurfaceTool, c: Vector2, r: float, count: int, size := 0.4) -> void:
	var k := d.kit
	for j in count:
		var a := TAU * float(j) / float(count) + k.rng.randf_range(-0.15, 0.15)
		var q := c + Vector2(sin(a), cos(a)) * r * k.rng.randf_range(0.97, 1.05)
		d.masonry.ellipsoid(st, k.on_ground(q.x, q.y, 0.03), Vector3(size, size * 0.38, size * 0.75) * k.rng.randf_range(0.8, 1.25), Basis(Vector3.UP, a))


# --- The Sunken Tower -----------------------------------------------------------------------------------

## A Builders' tower drowned to its third course in black water: what stands of it is fused black
## stone, the fourth course carved round with a face that looks out to sea; the reedfolk children's
## diving plank off its broken top and a rope down it, the drowned courses of its outer wall a ring of
## stones awash round it where the sallowjaws bask.
static func sunken_tower(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(160.0)
	if sea == Vector2.ZERO:
		sea = Vector2(-1, 0)
	var y := black_water(d, Vector2.ZERO, 10.5, 3.5, "Drowning")
	var oroth := m.begin()
	var r := 3.4
	# the tower: courses of fused stone from under the water to its broken top, nine metres over it
	var h := 9.0
	m.drum(oroth, Transform3D(Basis.IDENTITY, Vector3(0.0, y - 1.5, 0.0)), r, h + 1.5, 0.28, PoiKit.yaw_of(sea) + PI)
	# the fourth course: a band standing out, and on the seaward side the face, a brow, two eyes, a
	# nose and a mouth of blocks, worn
	var band_y := y + 1.4
	m.drum(oroth, Transform3D(Basis.IDENTITY, Vector3(0.0, band_y, 0.0)), r + 0.2, 0.7, 0.0, NAN, false)
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(sea))
	var fc := Vector3(sea.x, 0.0, sea.y) * (r + 0.25) + Vector3(0.0, band_y + 0.35, 0.0)
	m.block(oroth, Transform3D(fb, fc + Vector3(0.0, 0.32, 0.05)), Vector3(1.5, 0.16, 0.22))
	for s in [-1.0, 1.0]:
		m.ellipsoid(oroth, fc + fb * Vector3(float(s) * 0.38, 0.12, 0.02), Vector3(0.18, 0.1, 0.08))
	m.block(oroth, Transform3D(fb, fc + fb * Vector3(0.0, -0.05, 0.12)), Vector3(0.22, 0.42, 0.2))
	m.block(oroth, Transform3D(fb, fc + fb * Vector3(0.0, -0.32, 0.06)), Vector3(0.62, 0.08, 0.12))
	await k.step()
	m.commit(oroth, k.surface("oroth", 0.75), "SunkenTower", true)
	if k.far:
		return
	# the drowned courses of the outer wall: a ring of black blocks just awash
	var ring := m.begin()
	for i in 16:
		if i % 5 == 2:
			continue
		var a := TAU * float(i) / 16.0
		var p := Vector2(sin(a), cos(a)) * 7.6
		m.block(ring, Transform3D(Basis(Vector3.UP, a), Vector3(p.x, y - 0.25 + k.rng.randf_range(0.0, 0.25), p.y)), Vector3(2.4, 0.6, 1.1))
		k.collider(Vector3(2.4, 0.6, 1.1), Transform3D(Basis(Vector3.UP, a), Vector3(p.x, y - 0.25, p.y)), "stone")
	await k.step()
	m.commit(ring, k.surface("oroth", 0.85), "DrownedCourses")
	k.marker("the_courses", Vector3(-sea.x * 7.6, y, -sea.y * 7.6))
	k.touchable("Face", Vector3(sea.x, 0.0, sea.y) * (r + 1.2) + Vector3(0.0, y + 0.3, 0.0), "Look at the face on the fourth course",
			"core:dialogue/sunken_tower_face", "", false)
	# the diving plank off the broken top, a knotted rope down the landward side to the water
	var timber := m.begin()
	var top_y := y + h * 0.78
	var plank_dir := -sea
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(plank_dir)), Vector3(plank_dir.x * (r + 0.6), top_y, plank_dir.y * (r + 0.6))), Vector3(0.45, 0.08, 2.4))
	var rope_top := Vector3(plank_dir.x * (r + 0.05), top_y - 0.2, plank_dir.y * (r + 0.05)) + Vector3(plank_dir.y, 0.0, -plank_dir.x) * 1.0
	m.block(timber, Transform3D(Basis.IDENTITY, (rope_top + Vector3(rope_top.x, y, rope_top.z)) * 0.5 + Vector3(plank_dir.x, 0, plank_dir.y) * 0.08), Vector3(0.05, top_y - 0.2 - y, 0.05))
	for i in 8:
		var t := float(i) / 8.0
		m.ellipsoid(timber, Vector3(rope_top.x, lerpf(top_y - 0.6, y + 0.4, t), rope_top.z) + Vector3(plank_dir.x, 0, plank_dir.y) * 0.08, Vector3(0.08, 0.07, 0.08))
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "DivingPlank")
	# the children's punt tied up at the landward stones, and their clothes on a stone
	var boat := k.prop("rowboat")
	if boat != "":
		var bp := plank_dir * 9.4 + Vector2(plank_dir.y, -plank_dir.x) * 2.0
		await k.step()
		k.place(boat, Vector3(bp.x, y + 0.02, bp.y), PoiKit.yaw_of(Vector2(plank_dir.y, -plank_dir.x)), 1.0, true)
	var stones := m.begin()
	rim_stones(d, stones, Vector2.ZERO, 10.6, 22, 0.5)
	await k.step()
	m.commit(stones, k.surface("stone", 0.9), "WaterRim")
	await reeds(d, 11.5, 19.0, 70, [[plank_dir * 12.0, 3.0]])


# --- The Fog Bell -------------------------------------------------------------------------------------

## A bell-frame of tall timber on stilts by the channel, its bell under a little reed roof and its
## rope down to the ringer's hut at the foot; the quarter-glass on the hut's sill, his pay in eel
## baskets stacked by the door, and the door open and the hut cold. A lantern on the landing stage
## for the boats coming up in the fog.
static func fog_bell(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.water_direction(80.0)
	if face == Vector2.ZERO:
		face = k.grain()
	var side := Vector2(face.y, -face.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(face))
	var g := k.on_ground(0.0, 0.0).y
	var frame := m.begin()
	var fy := g + 7.5
	var legs: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector2.ZERO + side * 1.3 * float(sx) + face * 1.3 * float(sz)
			var foot := k.on_ground(p.x * 1.25, p.y * 1.25)
			var top := Vector3(p.x, fy, p.y)
			m.limb(frame, foot + Vector3.DOWN * 0.3, top, 0.13)
			legs.append(foot)
	for st_y in [g + 2.6, g + 5.2]:
		for q in 4:
			var a: Vector3 = legs[[0, 1, 3, 2][q]]
			var b: Vector3 = legs[[0, 1, 3, 2][(q + 1) % 4]]
			var t := (float(st_y) - g) / 7.5
			m.limb(frame, a.lerp(Vector3(a.x * 0.8, fy, a.z * 0.8), t) * Vector3(1, 0, 1) + Vector3(0, float(st_y), 0),
					b.lerp(Vector3(b.x * 0.8, fy, b.z * 0.8), t) * Vector3(1, 0, 1) + Vector3(0, float(st_y), 0), 0.07)
	m.block(frame, Transform3D(basis, Vector3(0.0, fy, 0.0)), Vector3(3.0, 0.16, 3.0))
	m.block(frame, Transform3D(basis, Vector3(0.0, fy + 2.0, 0.0)), Vector3(2.6, 0.18, 0.2))
	for s in [-1.0, 1.0]:
		m.block(frame, Transform3D(basis, Vector3(0.0, fy + 1.0, 0.0) + basis * Vector3(float(s) * 1.2, 0.0, 0.0)), Vector3(0.18, 2.0, 0.18))
	k.collider(Vector3(2.6, 7.5, 2.6), Transform3D(basis, Vector3(0.0, g + 3.75, 0.0)), "wood")
	await k.step()
	m.commit(frame, k.surface("timber", 0.75), "BellFrame", true)
	var roof := m.begin()
	for s in [-1.0, 1.0]:
		m.block(roof, Transform3D(basis * Basis(Vector3.BACK, float(s) * 0.6), Vector3(0.0, fy + 2.6, 0.0) + basis * Vector3(float(s) * 0.85, 0.0, 0.0)), Vector3(2.1, 0.2, 3.2))
	await k.step()
	m.commit(roof, PoiKit.painted(5, THATCH, 0.6), "BellRoof", true)
	var bell := k.prop("bell_medium")
	if bell != "":
		var bs := 1.1 / maxf(PoiKit.height_of(bell), 0.3)
		await k.step()
		k.place(bell, Vector3(0.0, fy + 1.9 - PoiKit.height_of(bell) * bs, 0.0), PoiKit.yaw_of(face), bs, false, Vector3.ZERO, true)
	if k.far:
		return
	# the rope, from the bell's crown down through the frame to the ringer's hut
	var hut_c := -face * 5.5 + side * 2.0
	var rope := m.begin()
	var rope_foot := Vector3(hut_c.x, g + 2.0, hut_c.y) + Vector3(face.x, 0, face.y) * 1.6
	m.limb(rope, Vector3(0.0, fy + 1.7, 0.0), Vector3(0.0, fy - 0.1, 0.0), 0.025)
	m.limb(rope, Vector3(0.0, fy - 0.1, 0.0), rope_foot, 0.025)
	await k.step()
	m.commit(rope, PoiKit.plain(RUSH, 0.95), "BellRope")
	# the ringer's hut: a reed hut on low stilts, its door open
	var hut: Dictionary = await stilt_house(d, hut_c, face, 3.2, 3.0, 0.9, "Ringer")
	k.marker("home", hut["inside"], true, true, 1.4)
	var hut_foot: Vector3 = hut["foot"]
	var f2 := Vector2(hut_foot.x, hut_foot.z)
	# his pay, in eel baskets by the door; the quarter-glass on the sill
	var basket := k.prop("basket")
	if basket != "":
		var xfs: Array = []
		for i in 5:
			var q := f2 + side * (1.2 + float(i % 3) * 0.55) + face * (floorf(float(i) / 3.0) * 0.5)
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, 1.0))
		await k.step()
		k.scatter(basket, xfs, false, false, true)
	k.marker("the_door", k.on_ground(f2.x - side.x * 1.0, f2.y - side.y * 1.0))
	k.touchable("BellRope", rope_foot + Vector3(0.0, -0.9, 0.0), "Pull the bell-rope", "core:dialogue/fog_bell_rope", "", false)
	# the landing stage out into the channel, a lantern on its end post
	var planks := m.begin()
	var posts := m.begin()
	var la := face * 3.2 - side * 1.5
	var lb := face * 11.0 - side * 2.5
	var ly := maxf(k.on_ground(la.x, la.y).y, k.on_ground(lb.x, lb.y).y) + 0.25
	m.plank_deck(planks, posts, la, lb, 1.4, ly, 2.6, false)
	var arm := lantern_pole(d, posts, lb + face * 0.3 + side * 0.5, side, true, 2.6)
	await k.step()
	m.commit(planks, k.surface("planks", 0.85), "Landing")
	m.commit(posts, k.surface("timber", 0.85), "LandingPosts")
	k.marker("the_landing", k.on_ground(la.x, la.y))
	await reeds(d, 8.0, 17.0, 60, [[(la + lb) * 0.5, 4.0], [hut_c, 4.5]])
	var _unused := arm


# --- Heron Watch --------------------------------------------------------------------------------------

## The reedfolk lookout on tall stilts by the channel, a little bell-cote on its roof where the bittern
## nests in the bell (a heap of reed in its mouth), Tuo Lissa's knotted bell-rope hanging all the way
## to the ladder's foot, where he sits. Keeps the kind's spots: home, the_ladder_foot.
static func heron_watch(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.water_direction(90.0)
	if face == Vector2.ZERO:
		face = k.grain()
	var side := Vector2(face.y, -face.x)
	var hc := -face * 1.5
	var house: Dictionary = await stilt_house(d, hc, face, 3.4, 3.2, 4.8, "Heron", 20)
	var deck_y := float(house["deck_y"])
	var basis: Basis = house["basis"]
	# the bell-cote on the ridge
	var cote := m.begin()
	var ridge_y := deck_y + 2.1 + (3.4 * 0.5 + 0.45) * tan(0.72)
	var cc := Vector3(hc.x, ridge_y, hc.y)
	for s in [-1.0, 1.0]:
		m.block(cote, Transform3D(basis, cc + basis * Vector3(float(s) * 0.55, 0.7, 0.0)), Vector3(0.14, 1.5, 0.14))
	m.block(cote, Transform3D(basis, cc + Vector3(0, 1.45, 0)), Vector3(1.4, 0.14, 0.2))
	m.block(cote, Transform3D(basis * Basis(Vector3.BACK, 0.5), cc + Vector3(0, 1.75, 0) + basis * Vector3(-0.35, 0, 0)), Vector3(0.9, 0.08, 0.8))
	m.block(cote, Transform3D(basis * Basis(Vector3.BACK, -0.5), cc + Vector3(0, 1.75, 0) + basis * Vector3(0.35, 0, 0)), Vector3(0.9, 0.08, 0.8))
	await k.step()
	m.commit(cote, k.surface("timber", 0.75), "BellCote", true)
	var bell := k.prop("bell_small")
	if bell != "":
		await k.step()
		k.place(bell, cc + Vector3(0, 1.38 - PoiKit.height_of(bell), 0), PoiKit.yaw_of(face), 1.0, false, Vector3.ZERO, true)
	if k.far:
		return
	var nest := m.begin()
	for i in 9:
		var a := k.rng.randf() * TAU
		m.limb(nest, cc + Vector3(sin(a) * 0.25, 1.0, cos(a) * 0.25), cc + Vector3(-sin(a) * 0.28, 1.08, -cos(a) * 0.28), 0.04)
	await k.step()
	m.commit(nest, PoiKit.painted(5, THATCH, 0.4), "BitternNest")
	k.marker("home", house["inside"], true, true, 1.5)
	# the knotted bell-rope, from the cote down past the porch to the ladder's foot
	var foot: Vector3 = house["foot"]
	var f2 := Vector2(foot.x, foot.z)
	var rope_foot := Vector3(f2.x, k.on_ground(f2.x, f2.y).y + 0.9, f2.y) + Vector3(side.x, 0, side.y) * 1.3
	var eave := Vector3(hc.x, deck_y + 2.3, hc.y) + Vector3(face.x, 0, face.y) * 2.6 + Vector3(side.x, 0, side.y) * 1.3
	var rope := m.begin()
	var knots := m.begin()
	m.limb(rope, cc + Vector3(0, 1.2, 0), eave, 0.022)
	m.limb(rope, eave, rope_foot, 0.022)
	for i in 30:
		var t := float(i) / 30.0
		m.block(knots, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), eave.lerp(rope_foot, t)), Vector3(0.07, 0.06 if i % 4 else 0.14, 0.07))
	await k.step()
	m.commit(rope, PoiKit.plain(RUSH, 0.95), "WatchRope")
	m.commit(knots, PoiKit.plain(RUSH.darkened(0.25), 0.95), "WatchKnots")
	k.marker("the_ladder_foot", k.on_ground(f2.x + side.x * 1.8 + face.x * 0.6, f2.y + side.y * 1.8 + face.y * 0.6), true)
	var stool := k.prop("stool")
	if stool != "":
		var sp := f2 + side * 1.8 + face * 0.6
		await k.step()
		k.place(stool, k.on_ground(sp.x, sp.y), PoiKit.yaw_of(face), 1.0, true)
	var boat := k.prop("rowboat")
	if boat != "":
		var bp := face * 8.5 - side * 2.0
		await k.step()
		k.place(boat, k.on_ground(bp.x, bp.y, 0.05), PoiKit.yaw_of(side) + 0.3, 1.0, true)
	await reeds(d, 7.0, 16.0, 60, [[face * 8.5 - side * 2.0, 2.5], [f2, 3.0]])


## A thatch roof's ridge at local `c` along `along`, its top `top_y`: the two pitches and the gable
## ends, as a sunk house shows over the water. Into `st`.
static func roof_ridge(d: PoiDressing, st: SurfaceTool, c: Vector2, along: Vector2, length: float, top_y: float, span := 3.6) -> void:
	var m := d.masonry
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(along))
	var pitch := 0.72
	var half := span * 0.5
	var slope_len := half / cos(pitch)
	for s in [-1.0, 1.0]:
		var mid := Vector3(c.x, top_y - half * tan(pitch) * 0.5, c.y) + basis * Vector3(float(s) * half * 0.5, 0.0, 0.0)
		m.block(st, Transform3D(basis * Basis(Vector3.BACK, -pitch * float(s)), mid), Vector3(slope_len, 0.22, length))
	m.block(st, Transform3D(basis, Vector3(c.x, top_y + 0.04, c.y)), Vector3(0.34, 0.2, length + 0.1))


# --- Mor'oul ------------------------------------------------------------------------------------------

## A stilt-village gone under in a flood nobody recorded: black water over all of it, the ridges of its
## roofs just breaking the surface, the tops of its stilts and its lantern poles standing out of it, and
## under the water its own lanterns still lit. A punt tied to a pole-top.
static func mor_oul(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var y := black_water(d, Vector2.ZERO, 17.0, 4.0, "Flood")
	var thatch := m.begin()
	var posts := m.begin()
	var houses: Array = []
	for i in 6:
		var a := TAU * float(i) / 6.0 + k.rng.randf_range(-0.3, 0.3)
		var rr := 6.5 + k.rng.randf_range(0.0, 5.5)
		var c := Vector2(sin(a), cos(a)) * rr
		var along := Vector2(cos(a), -sin(a)).rotated(k.rng.randf_range(-0.4, 0.4))
		var tilt := k.rng.randf_range(-0.25, 0.4)
		houses.append([c, along])
		roof_ridge(d, thatch, c, along, k.rng.randf_range(3.6, 4.8), y + 1.0 + tilt, 3.6)
		# the stilts' tops at the corners, gone black, standing out round the drowned eaves
		for s in [-1.0, 1.0]:
			for t in [-1.0, 1.0]:
				var p := c + Vector2(along.y, -along.x) * 2.3 * float(s) + along * 2.2 * float(t)
				if k.rng.randf() < 0.35:
					continue
				var h := k.rng.randf_range(0.6, 1.6)
				m.block(posts, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), Vector3(p.x, y + h * 0.5 - 0.5, p.y)), Vector3(0.2, h + 0.5, 0.2))
	# the lantern poles of the village, standing to their arms out of the water
	var poles: Array = []
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		var p := Vector2(sin(a), cos(a)) * 9.0
		poles.append(p)
		m.block(posts, Transform3D(Basis.IDENTITY, Vector3(p.x, y + 0.9, p.y)), Vector3(0.14, 2.6, 0.14))
		m.block(posts, Transform3D(Basis(Vector3.UP, a), Vector3(p.x, y + 2.1, p.y) + Vector3(sin(a + PI * 0.5), 0, cos(a + PI * 0.5)) * 0.25), Vector3(0.07, 0.07, 0.5))
	await k.step()
	m.commit(thatch, PoiKit.painted(5, {"base": "#4a4632", "accent": "#36321f", "grout": "#1f1c10", "unit": 0.2}, 0.7), "DrownedRidges", true)
	m.commit(posts, PoiKit.plain(Color(0.07, 0.065, 0.06), 0.85), "DrownedStilts", true)
	if k.far:
		return
	# under the water, the village's own lanterns, still lit: a glow at each door
	var glow := m.begin()
	for h in houses:
		var c: Vector2 = h[0]
		var along: Vector2 = h[1]
		var door := c + Vector2(along.y, -along.x) * 2.6
		m.block(glow, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), Vector3(door.x, y - 0.45, door.y)), Vector3(0.24, 0.32, 0.24))
	await k.step()
	m.commit(glow, PoiKit.plain(Color(0.9, 0.62, 0.3), 0.6, 0.0, Color(1.0, 0.6, 0.25), 2.2), "UnderLanterns")
	for i in 3:
		var h: Array = houses[i * 2]
		var c: Vector2 = h[0]
		k.light(Vector3(c.x, y - 0.2, c.y), Color(1.0, 0.62, 0.3), 1.2, 7.0)
	var ridge0: Vector2 = houses[0][0]
	k.marker("the_ridge", Vector3(ridge0.x, y + 0.4, ridge0.y))
	k.marker("the_doors", Vector3(0.0, y, 0.0))
	var look_at: Vector2 = houses[1][0]
	k.touchable("UnderWater", Vector3(look_at.x, y + 0.6, look_at.y), "Look down into the water", "core:dialogue/mor_oul_under_water", "", false)
	var boat := k.prop("rowboat")
	if boat != "":
		var bp: Vector2 = poles[1] + Vector2(1.2, 0.6)
		await k.step()
		k.place(boat, Vector3(bp.x, y + 0.02, bp.y), k.rng.randf() * TAU, 1.0, false)
	var stones := m.begin()
	rim_stones(d, stones, Vector2.ZERO, 17.2, 30, 0.45)
	await k.step()
	m.commit(stones, k.surface("stone", 0.9), "Rim")
	await reeds(d, 17.5, 24.0, 80, [])


# --- Saoul --------------------------------------------------------------------------------------------

## The lantern-pool: a ring of a dozen empty stilts standing in a black pool where Sa'oul is, the
## platform they held long gone, a lantern hung lit from a hook on every one. A shrine-post at the edge
## with the knots of the village that moved to Saeva.
static func saoul(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var y := black_water(d, Vector2.ZERO, 12.0, 5.0, "SaoulPool")
	var stilts := m.begin()
	var paper := m.begin()
	var n := 12
	var ring_r := 7.5
	var hooks: Array = []
	for i in n:
		var a := TAU * float(i) / float(n)
		var p := Vector2(sin(a), cos(a)) * ring_r
		var h := 3.4 + k.rng.randf_range(-0.4, 0.6)
		var lean := Vector3(k.rng.randf_range(-0.05, 0.05), 0.0, k.rng.randf_range(-0.05, 0.05))
		var top := m.post(stilts, p, h, 0.24, lean)
		# a stub of the cross-beam it once carried, and the hook the lantern hangs from
		var inward := -Vector3(p.x, 0.0, p.y).normalized()
		m.block(stilts, Transform3D(Basis(Vector3.UP, a), top - Vector3(0, 0.25, 0) + inward * 0.35), Vector3(0.12, 0.12, 0.7))
		var hook := top - Vector3(0, 0.32, 0) + inward * 0.62
		hooks.append(hook)
		m.block(stilts, Transform3D(Basis.IDENTITY, hook - Vector3(0, 0.12, 0)), Vector3(0.025, 0.24, 0.025))
		var lb := Basis(Vector3.UP, k.rng.randf() * TAU)
		m.block(paper, Transform3D(lb, hook - Vector3(0, 0.42, 0)), Vector3(0.26, 0.34, 0.26))
	await k.step()
	m.commit(stilts, PoiKit.plain(Color(0.08, 0.07, 0.06), 0.85), "EmptyStilts", true)
	m.commit(paper, PoiKit.plain(Color(0.95, 0.7, 0.4), 0.6, 0.0, Color(1.0, 0.62, 0.3), 1.8), "Lanterns", true)
	if k.far:
		return
	for i in 4:
		var hook: Vector3 = hooks[i * 3]
		k.light(hook - Vector3(0, 0.5, 0), Color(1.0, 0.68, 0.36), 1.4, 8.0)
	k.marker("the_pool", Vector3(0.0, y, 0.0))
	# the shrine-post at the pool's edge, hung with Saeva's knots, a step of stones out to it
	var near := k.road_direction(200.0)
	var toward := Vector2(near.y, -near.x) if near != Vector2.ZERO else Vector2(0, 1)
	var sp := toward * (12.8)
	var timber := m.begin()
	var post_top := m.post(timber, sp, 1.9, 0.2)
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "ShrinePost")
	var cord := m.begin()
	var knots := m.begin()
	var pts: Array = []
	for i in 7:
		var a := TAU * float(i) / 7.0
		pts.append(post_top - Vector3(0, 0.15, 0) + Vector3(sin(a), 0, cos(a)) * 0.13)
	cords(d, cord, knots, pts, Vector2(0.5, 0.9), 0.15)
	await k.step()
	m.commit(cord, PoiKit.plain(INDIGO, 0.95), "SaevaCords")
	m.commit(knots, PoiKit.plain(RUSH, 0.9), "SaevaKnots")
	k.marker("the_shrine_post", k.on_ground(sp.x * 1.12, sp.y * 1.12))
	k.touchable("ShrinePost", post_top - Vector3(0, 0.6, 0), "Count the lanterns", "core:dialogue/saoul_lanterns", "", false)
	var stones := m.begin()
	rim_stones(d, stones, Vector2.ZERO, 12.1, 26, 0.45)
	await k.step()
	m.commit(stones, k.surface("stone", 0.9), "Rim")
	await reeds(d, 12.6, 21.0, 70, [[sp, 2.0]])


# --- The Eel Stews ------------------------------------------------------------------------------------

## Stone-walled ponds in the fen where the live eels are kept for the Tollmere market: six square
## stews in two rows with plank walks between, their water black, eel-baskets and a keeper's hand-net
## by them; the sixth walled higher than the rest, its sluice-board down, the water gone out of it and
## its wall wet on the outside.
static func eel_stews(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.water_direction(80.0)
	if face == Vector2.ZERO:
		face = k.grain()
	var side := Vector2(face.y, -face.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(face))
	var stone := m.begin()
	var wet := m.begin()
	var pond := Vector2(4.6, 3.8)
	var g := k.on_ground(0.0, 0.0).y
	var water := k.still_water(-2.0, Color(0.85, 0.9, 0.85), 0.88)
	var high_at := Vector2.ZERO
	var wst := m.begin()
	for row in 2:
		for col in 3:
			var c := side * (float(col) - 1.0) * (pond.x + 1.4) + face * (float(row) - 0.5) * (pond.y + 1.6)
			var high := row == 1 and col == 2
			var wall_h := 1.5 if high else 0.55
			for q in 4:
				var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(q))
				var span := pond.x if q % 2 == 0 else pond.y
				var off := pond.y if q % 2 == 0 else pond.x
				var e := bb * Vector3(0.0, 0.0, off * 0.5)
				var xf := Transform3D(bb, Vector3(c.x, g + wall_h * 0.5 - 0.2, c.y) + e)
				m.block(stone, xf, Vector3(span + 0.5, wall_h + 0.4, 0.5))
				k.collider(Vector3(span + 0.5, wall_h + 0.4, 0.5), xf, "stone")
				if high:
					# wet on the outside: a dark skin on the wall's outer face where the water went over
					m.block(wet, Transform3D(bb, Vector3(c.x, g + wall_h * 0.4, c.y) + e * 1.0 + e.normalized() * 0.27), Vector3(span + 0.4, wall_h * 0.85, 0.03))
			if high:
				high_at = c
			else:
				m.block(wst, Transform3D(basis, Vector3(c.x, g + 0.3, c.y)), Vector3(pond.x - 0.45, 0.02, pond.y - 0.45))
	await k.step()
	m.commit(stone, k.surface("stone", 0.8), "StewWalls", true)
	m.commit(wet, PoiKit.plain(Color(0.12, 0.14, 0.12), 0.25), "WetSkin")
	var wmi := m.commit(wst, water, "StewWater")
	if wmi != null:
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if k.far:
		return
	# the high stew: dry mud in it, its sluice-board shut, the keeper's lantern left on the wall
	var mud := m.begin()
	m.block(mud, Transform3D(basis, Vector3(high_at.x, g + 0.02, high_at.y)), Vector3(pond.x - 0.2, 0.05, pond.y - 0.2))
	await k.step()
	m.commit(mud, PoiKit.plain(Color(0.2, 0.17, 0.12), 0.95), "DryMud")
	var timber := m.begin()
	var sluice := high_at + face * (pond.y * 0.5 + 0.25)
	for s in [-1.0, 1.0]:
		m.post(timber, sluice + side * 0.55 * float(s), 2.0, 0.16)
	m.block(timber, Transform3D(basis, Vector3(sluice.x, g + 1.0, sluice.y)), Vector3(1.0, 1.6, 0.1))
	m.block(timber, Transform3D(basis, Vector3(sluice.x, g + 2.05, sluice.y)), Vector3(1.4, 0.14, 0.18))
	# plank walks between the rows
	var planks := m.begin()
	m.plank_deck(planks, timber, -side * (pond.x * 1.6 + 2.0), side * (pond.x * 1.6 + 2.0), 1.1, g + 0.18, 3.0, false)
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "StewTimber")
	m.commit(planks, k.surface("planks", 0.85), "StewWalks")
	k.marker("the_high_stew", Vector3(high_at.x, g, high_at.y) + Vector3(-face.x, 0, -face.y) * 0.4)
	k.touchable("HighStew", Vector3(high_at.x, g + 1.2, high_at.y) - Vector3(face.x, 0, face.y) * (pond.y * 0.5 + 0.3), "Look over the high stew's wall",
			"core:dialogue/eel_stews_high_stew", "", false)
	k.marker("the_sluice", k.on_ground(sluice.x + face.x * 1.2, sluice.y + face.y * 1.2))
	var basket := k.prop("basket")
	if basket != "":
		var xfs: Array = []
		for i in 6:
			var q := -side * (pond.x * 1.6 + 1.0) + face * k.rng.randf_range(-1.2, 1.2) + k.jitter(0.3)
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, 1.0))
		await k.step()
		k.scatter(basket, xfs, false, false, true)
	var lamp := k.prop("lantern_standing")
	if lamp != "":
		var lp := high_at - side * (pond.x * 0.5 + 0.2) + face * 0.6
		await k.step()
		k.place(lamp, Vector3(lp.x, g + 1.5, lp.y), 0.0, 0.9, false)
	# the drag-marks: two furrows from the channel to the high stew's wall, where something heavy came
	var drag := m.begin()
	for s in [-1.0, 1.0]:
		var a := high_at + face * (pond.y * 0.5 + 1.2) + side * 0.5 * float(s)
		var b := a + face * 14.0 + side * 1.0 * float(s)
		var n := 10
		for i in n:
			var p := a.lerp(b, float(i) / float(n))
			m.block(drag, Transform3D(basis, k.on_ground(p.x, p.y, 0.005)), Vector3(0.28, 0.02, 1.5))
	await k.step()
	m.commit(drag, PoiKit.plain(Color(0.12, 0.1, 0.07), 0.95), "DragMarks")
	await reeds(d, 13.0, 20.0, 60, [])


# --- The Drowned Arch ---------------------------------------------------------------------------------

## One arch of the Builders' black stone standing at the edge of Mormere with nothing either side of it:
## two piers and the span, a keystone hung with eel-boat luck-knots, the water lapping through it from
## the mere's side; on the landward side the boats' tally-pole and a drawn-up eel-boat, and the stones
## of the wall it stood in lying half sunk in the reeds.
static func drowned_arch(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var mere := k.water_direction(70.0)
	if mere == Vector2.ZERO:
		mere = k.grain()
	var across := Vector2(mere.y, -mere.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(across))
	var g := k.on_ground(0.0, 0.0).y
	var oroth := m.begin()
	var span := 4.6
	var pier_h := 4.4
	for s in [-1.0, 1.0]:
		var pc := across * (span * 0.5 + 0.8) * float(s)
		var pg := k.on_ground(pc.x, pc.y).y
		var xf := Transform3D(basis, Vector3(pc.x, (pg - 0.6 + g + pier_h) * 0.5, pc.y))
		m.block(oroth, xf, Vector3(1.6, g + pier_h - pg + 0.6, 1.7))
		k.collider(Vector3(1.6, g + pier_h - pg + 0.6, 1.7), xf, "stone")
		m.block(oroth, Transform3D(basis, Vector3(pc.x, g + pier_h + 0.1, pc.y)), Vector3(1.85, 0.25, 1.95))
	# the span: voussoirs on a half-circle, the keystone standing proud
	var n := 9
	for i in n:
		var a := PI * (float(i) + 0.5) / float(n)
		var p := basis * Vector3(cos(a) * (span * 0.5 + 0.55), sin(a) * (span * 0.5 + 0.55), 0.0)
		var key := i * 2 + 1 == n
		m.block(oroth, Transform3D(basis * Basis(Vector3.BACK, a - PI * 0.5), Vector3(p.x, g + pier_h + p.y, p.z)), Vector3(0.62 if not key else 0.78, 1.1 if not key else 1.4, 1.6 if not key else 1.8))
	m.block(oroth, Transform3D(basis, Vector3(0.0, g + pier_h + span * 0.5 + 1.25, 0.0)), Vector3(span + 3.4, 0.5, 1.5))
	await k.step()
	m.commit(oroth, k.surface("oroth", 0.75), "Arch", true)
	if k.far:
		return
	# the water of the mere lapping in under it
	black_water(d, mere * 3.5, 6.0, 2.0, "Lap")
	# luck-knots hung from the keystone and the soffit
	var cord := m.begin()
	var knots := m.begin()
	var pts: Array = []
	for i in 7:
		var t := (float(i) - 3.0) / 3.0
		var a := PI * 0.5 + t * 0.9
		pts.append(basis * Vector3(cos(a) * (span * 0.5), sin(a) * (span * 0.5), k.rng.randf_range(-0.5, 0.5)) + Vector3(0.0, g + pier_h, 0.0))
	cords(d, cord, knots, pts, Vector2(0.5, 1.3), 0.2)
	await k.step()
	m.commit(cord, PoiKit.plain(INDIGO, 0.95), "LuckCords")
	m.commit(knots, PoiKit.plain(RUSH, 0.9), "LuckKnots")
	k.marker("the_arch", k.on_ground(-mere.x * 1.5, -mere.y * 1.5))
	k.touchable("Arch", Vector3(0.0, g + 1.2, 0.0), "Go under the arch", "core:dialogue/drowned_arch_under", "", false)
	# the wall it stood in, lying in the reeds either side
	var masonry := k.rock("sunken_masonry")
	if masonry != "":
		var xfs: Array = []
		for s in [-1.0, 1.0]:
			for i in 3:
				var q := across * (span * 0.5 + 3.0 + float(i) * 2.6) * float(s) + mere * k.rng.randf_range(-1.0, 1.5)
				xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y, -0.35), k.rng.randf() * TAU, k.rng.randf_range(0.8, 1.2)))
		await k.step()
		k.scatter(masonry, xfs, true, false, true)
	# the boats' tally-pole and a drawn-up eel-boat, landward
	var timber := m.begin()
	var tp := -mere * 4.5 + across * 2.5
	var top := m.post(timber, tp, 2.2, 0.16)
	for i in 12:
		var y := top.y - 0.2 - float(i) * 0.13
		m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(mere)), Vector3(tp.x, y, tp.y) + Vector3(mere.x, 0, mere.y) * 0.09), Vector3(0.12 if i % 5 == 4 else 0.07, 0.02, 0.02))
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "TallyPole")
	k.marker("the_tally_pole", k.on_ground(tp.x - mere.x * 0.8, tp.y - mere.y * 0.8))
	var boat := k.prop("rowboat")
	if boat != "":
		var bp := -mere * 3.0 - across * 3.5
		await k.step()
		k.place(boat, k.on_ground(bp.x, bp.y, 0.05), PoiKit.yaw_of(mere) + 0.25, 1.0, true)
	await reeds(d, 7.0, 16.0, 55, [[mere * 3.5, 6.5], [-mere * 3.0 - across * 3.5, 2.5]])


# --- The Knuckle Cairn ----------------------------------------------------------------------------------

## The Oskel clan's boundary cairn on the last dry stone before the fen: a rise of grey rock with the
## cairn on it, capped with a giant's knuckle-bone turned to point into the fen; the clan's sign-cords
## on stakes round it, a lead-carrier's offering of ore at its foot, and the fen beginning a pace on.
static func knuckle_cairn(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var fen := Vector2(0.0, 1.0)      # the fen is south of the clans' country
	var side := Vector2(fen.y, -fen.x)
	var g := k.on_ground(0.0, 0.0).y
	# the rise: boulders heaped and sunk, the cairn on them
	var boulder := k.rock("boulder")
	if boulder != "":
		var xfs: Array = []
		for i in 9:
			var a := TAU * float(i) / 9.0 + k.rng.randf_range(-0.2, 0.2)
			var q := Vector2(sin(a), cos(a)) * k.rng.randf_range(3.4, 4.6)
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y, -0.45), k.rng.randf() * TAU, k.rng.randf_range(0.6, 0.95)))
		await k.step()
		k.scatter(boulder, xfs, true, true, true)
	var stones := m.begin()
	var y := g + 0.2
	var r := 2.2
	for c in 8:
		var count := maxi(10 - c, 3)
		for i in count:
			var a := TAU * float(i) / float(count) + float(c) * 0.4
			m.ellipsoid(stones, Vector3(sin(a) * r * 0.7, y + 0.24, cos(a) * r * 0.7), Vector3(0.55, 0.32, 0.42) * (1.0 - float(c) * 0.05), Basis(Vector3.UP, a + k.rng.randf()))
		m.ellipsoid(stones, Vector3(0.0, y + 0.2, 0.0), Vector3(r * 0.6, 0.3, r * 0.6))
		y += 0.45
		r *= 0.84
	k.collider(Vector3(2.8, y - g, 2.8), Transform3D(Basis.IDENTITY, Vector3(0.0, (g + y) * 0.5, 0.0)), "stone")
	await k.step()
	m.commit(stones, k.surface("stone", 0.6), "Cairn", true)
	# the knuckle: three bones of a giant's finger-joint laid together on the top, the end pointing fen-ward
	var bone := m.begin()
	var tb := Basis(Vector3.UP, PoiKit.yaw_of(fen))
	m.ellipsoid(bone, Vector3(0.0, y + 0.5, 0.0), Vector3(0.8, 0.62, 1.35), tb)
	m.ellipsoid(bone, Vector3(0.0, y + 0.62, 0.0) + Vector3(fen.x, 0, fen.y) * 1.35, Vector3(0.7, 0.52, 0.8), tb)
	m.ellipsoid(bone, Vector3(0.0, y + 0.45, 0.0) - Vector3(fen.x, 0, fen.y) * 1.15, Vector3(0.9, 0.66, 0.75), tb)
	await k.step()
	m.commit(bone, PoiKit.plain(Color(0.82, 0.78, 0.68), 0.7), "Knuckle", true)
	if k.far:
		return
	k.marker("the_cairn", k.on_ground(fen.x * 3.2, fen.y * 3.2))
	k.touchable("Knuckle", Vector3(0.0, y + 0.2, 0.0) + Vector3(fen.x, 0, fen.y) * 1.6, "Look at the knuckle-bone", "core:dialogue/knuckle_cairn_bone", "", false)
	# the sign-cords on stakes round it: the clans' knots in red and undyed wool, tokens of bone
	var timber := m.begin()
	var cord := m.begin()
	var tokens := m.begin()
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		var q := Vector2(sin(a), cos(a)) * 4.6
		var top := m.post(timber, q, 1.3, 0.09, Vector3(k.rng.randf_range(-0.06, 0.06), 0.0, k.rng.randf_range(-0.06, 0.06)))
		m.limb(cord, top - Vector3(0, 0.08, 0), top - Vector3(0, 0.55, 0) + Vector3(k.rng.randf_range(-0.1, 0.1), 0, k.rng.randf_range(-0.1, 0.1)), 0.02)
		m.ellipsoid(tokens, top - Vector3(0, 0.5, 0), Vector3(0.06, 0.09, 0.03))
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "SignStakes")
	m.commit(cord, PoiKit.plain(Color(0.5, 0.15, 0.12), 0.9), "SignCords")
	m.commit(tokens, PoiKit.plain(Color(0.85, 0.8, 0.7), 0.7), "BoneTokens")
	# the lead-carriers' offering: pigs of lead and a lump of ore on a flat stone at the fen side
	var lead := m.begin()
	var op := fen * 2.8 + side * 1.2
	var og := k.on_ground(op.x, op.y).y
	m.ellipsoid(lead, Vector3(op.x, og + 0.06, op.y), Vector3(0.7, 0.1, 0.5), Basis(Vector3.UP, 0.3))
	for i in 3:
		m.block(lead, Transform3D(Basis(Vector3.UP, 0.3 + float(i) * 0.1), Vector3(op.x, og + 0.2 + float(i) * 0.1, op.y) + Vector3(side.x, 0, side.y) * (float(i) - 1.0) * 0.18), Vector3(0.42, 0.1, 0.16))
	await k.step()
	m.commit(lead, PoiKit.plain(Color(0.36, 0.37, 0.4), 0.45, 0.6), "LeadPigs")
	# heather and stone on the dry side, sedge and reeds on the fen side
	var tuft := k.flora("sedge_tussock")
	if tuft != "":
		var xfs2: Array = []
		for i in 30:
			var q := fen * k.rng.randf_range(5.0, 15.0) + side * k.rng.randf_range(-12.0, 12.0)
			xfs2.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, k.rng.randf_range(0.8, 1.3)))
		await k.step()
		k.scatter(tuft, xfs2, false, false, false)


# --- The Round Stones -----------------------------------------------------------------------------------

## Three stones on three peat islets in black water, where the Round of Sa'oul is sung at midsummer, a
## choir on each: each islet a hummock with its stone and the singers' reed mats round it, a lantern pole
## at each; the islets a long stone's throw apart, so a voice has to carry over water to the next.
static func round_stones(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var y := black_water(d, Vector2.ZERO, 15.0, 2.5, "RoundWater")
	var turf := PoiKit.painted(5, {"base": "#33402a", "accent": "#26301e", "grout": "#151b0f", "unit": 0.3}, 0.5)
	var stone := m.begin()
	var mats := m.begin()
	var poles := m.begin()
	var start := k.rng.randf() * TAU
	for i in 3:
		var a := start + TAU * float(i) / 3.0
		var c := Vector2(sin(a), cos(a)) * 8.0
		var cg := maxf(k.on_ground(c.x, c.y).y, y - 0.3)
		m.mound(Vector3(c.x, cg - 0.3, c.y), 3.6, 0.95, turf, "Islet%d" % i, true, 2.2, 6, 18, true, 0.08)
		var top := cg + 0.6
		var sb := Basis(Vector3.UP, a + k.rng.randf_range(-0.3, 0.3)) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.05, 0.05))
		var h := 2.4 + float(i) * 0.35
		m.block(stone, Transform3D(sb, Vector3(c.x, top + h * 0.5 - 0.3, c.y)), Vector3(0.9, h, 0.55))
		m.block(stone, Transform3D(sb * Basis(Vector3.BACK, 0.04), Vector3(c.x, top + h - 0.35, c.y)), Vector3(0.75, 0.3, 0.5))
		k.collider(Vector3(0.9, h, 0.55), Transform3D(sb, Vector3(c.x, top + h * 0.5 - 0.3, c.y)), "stone")
		# the singers' mats in a crescent facing the next islet
		var to_next := (Vector2(sin(a + TAU / 3.0), cos(a + TAU / 3.0)) * 8.0 - c).normalized()
		for j in 5:
			var b := PoiKit.yaw_of(to_next) + (float(j) - 2.0) * 0.45
			var q := c + Vector2(sin(b), cos(b)) * 1.7
			m.block(mats, Transform3D(Basis(Vector3.UP, b), Vector3(q.x, top + 0.04, q.y)), Vector3(0.7, 0.04, 0.5))
		lantern_pole(d, poles, c - to_next * 2.0, to_next, i == 0, 2.4)
	await k.step()
	m.commit(stone, k.surface("stone", 0.7), "Stones", true)
	if k.far:
		return
	m.commit(mats, PoiKit.painted(5, THATCH, 0.5), "SingersMats")
	m.commit(poles, k.surface("timber", 0.8), "IsletPoles")
	k.marker("the_round", Vector3(0.0, y, 0.0))
	k.touchable("Round", Vector3(0.0, y + 1.2, 0.0), "Sing a voice of the round", "core:dialogue/round_stones_sing", "", false)
	var stones := m.begin()
	rim_stones(d, stones, Vector2.ZERO, 15.1, 30, 0.4)
	await k.step()
	m.commit(stones, k.surface("stone", 0.9), "Rim")
	await reeds(d, 15.4, 22.0, 70, [])


# --- The Tideflat Stones --------------------------------------------------------------------------------

## Three stones in a line at the sea's edge marking a shoreline that is no longer there: the first on
## the flats, the second in the shallows, the third out in the water; the line of an old quay's facing
## stones along where the shore was; the western chart's survey-cairn with its pole and rag; driftwood,
## crabs, wrack.
static func tideflat_stones(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(120.0)
	if sea == Vector2.ZERO:
		sea = Vector2(-1, 0)
	var along := Vector2(sea.y, -sea.x)
	var stone := m.begin()
	for i in 3:
		var p := sea * (-3.0 + float(i) * 6.0) + along * k.rng.randf_range(-0.6, 0.6)
		var g := k.on_ground(p.x, p.y).y
		var h := 2.8 - float(i) * 0.2
		var sb := Basis(Vector3.UP, PoiKit.yaw_of(along) + k.rng.randf_range(-0.15, 0.15)) * Basis(Vector3.RIGHT, 0.04 * float(i))
		m.block(stone, Transform3D(sb, Vector3(p.x, g + h * 0.5 - 0.4, p.y)), Vector3(1.1, h, 0.7))
		k.collider(Vector3(1.1, h, 0.7), Transform3D(sb, Vector3(p.x, g + h * 0.5 - 0.4, p.y)), "stone")
	await k.step()
	m.commit(stone, k.surface("stone", 0.85), "TideStones", true)
	if k.far:
		return
	# the old quay's facing stones, a line along where the shore was, half buried in the flats
	var quay := m.begin()
	for i in 14:
		var p := sea * 1.5 + along * (float(i) - 6.5) * 1.3
		var g := k.on_ground(p.x, p.y).y
		if k.rng.randf() < 0.2:
			continue
		m.block(quay, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(sea) + k.rng.randf_range(-0.08, 0.08)), Vector3(p.x, g + 0.05, p.y)), Vector3(0.6, 0.45, 1.2))
	await k.step()
	m.commit(quay, k.surface("stone", 0.95), "OldQuay")
	# the survey-cairn on the landward side, a pole with a rag on it
	var cairn := m.begin()
	var cp := -sea * 7.0 + along * 3.0
	var cg := k.on_ground(cp.x, cp.y).y
	for i in 4:
		m.ellipsoid(cairn, Vector3(cp.x, cg + 0.15 + float(i) * 0.24, cp.y), Vector3(0.55 - float(i) * 0.1, 0.16, 0.45 - float(i) * 0.08), Basis(Vector3.UP, float(i)))
	await k.step()
	m.commit(cairn, k.surface("stone", 0.9), "SurveyCairn")
	var timber := m.begin()
	var top := m.post(timber, cp, 2.6, 0.08)
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "SurveyPole")
	m.sheet(top - Vector3(0, 0.05, 0) + Vector3(along.x, 0, along.y) * 0.25, PoiKit.yaw_of(sea), 0.5, 0.35, PoiKit.plain(Color(0.6, 0.2, 0.15), 0.9), "SurveyPennant", 0.1, false, 2, 2)
	k.marker("the_survey_cairn", k.on_ground(cp.x - sea.x * 1.0, cp.y - sea.y * 1.0))
	k.touchable("SightLine", Vector3(cp.x, cg + 1.3, cp.y), "Sight along the stones", "core:dialogue/tideflat_stones_sight", "", false)
	# driftwood, crabs, wrack along the tide line
	var drift := m.begin()
	for i in 5:
		var q := sea * k.rng.randf_range(-1.0, 2.0) + along * k.rng.randf_range(-9.0, 9.0)
		var a := k.rng.randf() * TAU
		var p := k.on_ground(q.x, q.y, 0.08)
		m.limb(drift, p, p + Vector3(sin(a), 0.05, cos(a)) * k.rng.randf_range(1.2, 2.6), 0.12)
	await k.step()
	m.commit(drift, PoiKit.plain(Color(0.6, 0.57, 0.5), 0.9), "Driftwood")
	# nothing to fight here: the crabs on the old strand, going about sideways at each stone's foot
	var crabs := Livestock.paths_of("crab", "sedgemire")
	if not crabs.is_empty():
		var shore := Livestock.new()
		shore.name = "Crabs"
		shore.seed_with(absi(("crabs:" + d.poi_id).hash()))
		for i in 3:
			var at := sea * (-4.5 + float(i) * 3.0) + along * k.rng.randf_range(1.5, 3.0) * (1.0 if i % 2 == 0 else -1.0)
			shore.keep("crab", crabs, k.on_ground(at.x, at.y), 3.2, 3 + k.rng.randi_range(0, 2))
		d.add_child(shore)
	var wrack := k.flora("wrack")
	if wrack != "":
		var xfs2: Array = []
		for i in 18:
			var q := sea * k.rng.randf_range(0.5, 2.5) + along * k.rng.randf_range(-12.0, 12.0)
			xfs2.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, k.rng.randf_range(0.8, 1.2)))
		await k.step()
		k.scatter(wrack, xfs2, false, false, false)


# --- The Drowned Road ------------------------------------------------------------------------------------

## The Builders' road of fused black slabs running dead straight out of the carr and into the sea: its
## kerbs, its slabs lower and lower toward the water and the last of them under it; a milestone standing
## out in the shallows past the end, cut with a number; the carr closing in over its landward end.
static func drowned_road(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(160.0)
	if sea == Vector2.ZERO:
		sea = Vector2(-1, 0)
	var across := Vector2(sea.y, -sea.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(sea))
	var slabs := m.begin()
	var kerbs := m.begin()
	var width := 6.0
	var n := 14
	for i in n:
		var t := float(i) / float(n - 1)
		var along := lerpf(-21.0, 19.0, t)
		var c := sea * along
		var g := k.on_ground(c.x, c.y).y
		# landward the road stands a hand proud of the peat; seaward it goes down under the water
		var y := g + 0.12 - maxf(t - 0.55, 0.0) * 1.3
		var sb := basis * Basis(Vector3.RIGHT, k.rng.randf_range(-0.012, 0.012)) * Basis(Vector3.FORWARD, k.rng.randf_range(-0.01, 0.01))
		var xf := Transform3D(sb, Vector3(c.x, y - 0.3, c.y))
		m.block(slabs, xf, Vector3(width, 0.6, 2.85))
		if y > g - 0.2:
			k.collider(Vector3(width, 0.6, 2.85), xf, "stone")
		for s in [-1.0, 1.0]:
			if k.rng.randf() < 0.15:
				continue
			m.block(kerbs, Transform3D(basis, Vector3(c.x, y - 0.1, c.y) + basis * Vector3(float(s) * (width * 0.5 + 0.3), 0.0, 0.0)), Vector3(0.6, 0.7, 2.8))
	await k.step()
	m.commit(slabs, k.surface("oroth", 0.7), "Road", true)
	m.commit(kerbs, k.surface("oroth", 0.85), "Kerbs", true)
	if k.far:
		return
	# the sea over its far end
	var wc := sea * 17.0
	black_water(d, wc, 9.5, 2.5, "Sea")
	# the milestone out in the shallows past the end, cut with a number
	var ms := sea * 24.5 + across * (width * 0.5 + 0.7)
	var mg := k.on_ground(ms.x, ms.y).y
	var mstone := m.begin()
	m.block(mstone, Transform3D(basis * Basis(Vector3.BACK, 0.05), Vector3(ms.x, mg + 0.6, ms.y)), Vector3(0.7, 1.7, 0.5))
	m.ellipsoid(mstone, Vector3(ms.x, mg + 1.45, ms.y), Vector3(0.36, 0.18, 0.26), basis)
	await k.step()
	m.commit(mstone, k.surface("oroth", 0.8), "Milestone")
	var cut := m.begin()
	for i in 4:
		m.block(cut, Transform3D(basis, Vector3(ms.x, mg + 0.9 + float(i) * 0.12, ms.y) - Vector3(sea.x, 0, sea.y) * 0.26), Vector3(0.05 + 0.05 * float(i % 2), 0.06, 0.01))
	await k.step()
	m.commit(cut, PoiKit.plain(Color(0.5, 0.75, 0.7), 0.5, 0.0, Color(0.4, 0.8, 0.75), 0.6), "Number")
	k.marker("the_milestone", Vector3(ms.x, mg, ms.y) - Vector3(sea.x, 0, sea.y) * 1.2)
	k.touchable("Milestone", Vector3(ms.x, mg + 1.0, ms.y) - Vector3(sea.x, 0, sea.y) * 0.5, "Read the milestone", "core:dialogue/drowned_road_milestone", "", false)
	k.marker("the_road_end", k.on_ground(-sea.x * 18.0, -sea.y * 18.0))
	# the carr closing over the landward end
	var alder := k.tree("alder")
	if alder != "":
		var xfs: Array = []
		for i in 5:
			var q := -sea * k.rng.randf_range(16.0, 23.0) + across * (width * 0.5 + k.rng.randf_range(2.5, 8.0)) * (1.0 if i % 2 == 0 else -1.0)
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, k.rng.randf_range(0.7, 1.0)))
		await k.step()
		k.scatter(alder, xfs, false, false, true)
	await reeds(d, 8.0, 20.0, 60, [[Vector2.ZERO, 5.0], [sea * 10.0, 5.0], [-sea * 10.0, 5.0], [sea * 20.0, 6.0], [-sea * 20.0, 5.0]])


# --- Oskel Ford --------------------------------------------------------------------------------------------

## The Builders' footbridge of column-drums over the Oskel, as its kind lays it, and in the fen beside it
## an ore-cart run off the causeway and left, the silver still in it, the carters' boots in the mud, and
## the clan's watch-post the Oskel want kept: a stake with a horn on it.
static func oskel_ford(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().bridge(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var river := k.water_direction(40.0)
	if river == Vector2.ZERO:
		river = k.grain()
	var bank := -river
	var side := Vector2(bank.y, -bank.x)
	var cart := k.prop("cart")
	var cp := bank * 11.0 + side * 6.0
	if cart != "":
		await k.step()
		k.place(cart, k.on_ground(cp.x, cp.y, -0.25), PoiKit.yaw_of(side) + 0.5, 1.0, true, Vector3(0.08, 0.0, -0.12))
	var ore := m.begin()
	for i in 6:
		var q := cp + k.jitter(0.8)
		m.ellipsoid(ore, k.on_ground(q.x, q.y, 0.25 + k.rng.randf() * 0.3), Vector3(0.2, 0.14, 0.17), Basis(Vector3.UP, k.rng.randf() * TAU))
	await k.step()
	m.commit(ore, PoiKit.plain(Color(0.62, 0.62, 0.66), 0.35, 0.7), "SilverOre")
	k.marker("the_cart", k.on_ground(cp.x - side.x * 2.0, cp.y - side.y * 2.0))
	k.touchable("Cart", k.on_ground(cp.x, cp.y, 1.0), "Look in the ore-cart", "core:dialogue/oskel_ford_cart", "", false)
	var boots := k.prop("boots")
	if boots != "":
		for i in 2:
			var q := cp - side * (2.4 + float(i) * 1.1) + bank * 0.8
			await k.step()
			k.place(boots, k.on_ground(q.x, q.y), k.rng.randf() * TAU, 1.0, false)
	var timber := m.begin()
	var wp := bank * 7.0 - side * 4.5
	var top := m.post(timber, wp, 2.0, 0.14)
	m.limb(timber, top + Vector3(0, -0.1, 0), top + Vector3(0.3, 0.15, 0.1), 0.06)
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "WatchStake")
	k.marker("the_watch_stake", k.on_ground(wp.x + bank.x, wp.y + bank.y), true)


# --- The Traders' Post ------------------------------------------------------------------------------------

## The beach where the Salt Isles traders drew their boats up for three hundred years: the frames of
## their tents still standing bare in the sand in a row along the strand, one tent put up again by
## Oulea for the longest day with a trader's chart pinned to its pole; the keel-grooves of the boats
## down to the water, the old trading fire, shells and wrack.
static func traders_post(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(140.0)
	if sea == Vector2.ZERO:
		sea = Vector2(-1, 0)
	var along := Vector2(sea.y, -sea.x)
	var timber := m.begin()
	var frames := 6
	var tent_at := Vector2.ZERO
	for i in frames:
		var c := along * (float(i) - 2.5) * 4.2 - sea * 3.0 + k.jitter(0.4)
		if k.road_distance(c) < 4.5:
			# the street the Oulea folk walk down to the strand runs through here: no frame stands in it
			continue
		if tent_at == Vector2.ZERO:
			tent_at = c
			continue
		# a frame: two crossed pole-pairs and a ridge, weathered grey, one leaning
		var yaw := PoiKit.yaw_of(sea) + k.rng.randf_range(-0.2, 0.2)
		var fb := Basis(Vector3.UP, yaw)
		var g := k.on_ground(c.x, c.y).y
		var ridge_h := 2.3 + k.rng.randf_range(-0.2, 0.2)
		var lean := k.rng.randf_range(-0.15, 0.15) if i != 4 else 0.35
		for e in [-1.0, 1.0]:
			var end := Vector3(c.x, g, c.y) + fb * Vector3(0.0, 0.0, 1.4 * float(e))
			var apex := end + Vector3(0.0, ridge_h, 0.0) + fb * Vector3(lean, 0.0, 0.0)
			for s in [-1.0, 1.0]:
				m.limb(timber, end + fb * Vector3(float(s) * 1.3, -0.2, 0.0), apex + Vector3(0, 0.25, 0) + fb * Vector3(float(s) * -0.25, 0.0, 0.0), 0.06)
		if i != 5:
			m.limb(timber, Vector3(c.x, g + ridge_h, c.y) + fb * Vector3(lean, 0.0, -1.5), Vector3(c.x, g + ridge_h, c.y) + fb * Vector3(lean, 0.0, 1.5), 0.05)
	await k.step()
	m.commit(timber, PoiKit.plain(Color(0.58, 0.55, 0.5), 0.9), "TentFrames", true)
	if k.far:
		return
	var tent := k.prop("tent")
	if tent != "":
		await k.step()
		k.place(tent, k.on_ground(tent_at.x, tent_at.y), PoiKit.yaw_of(sea), 1.0, true)
	# the pole with the chart pinned to it, by the tent's door
	var pole := m.begin()
	var pp := tent_at + sea * 2.2 + along * 1.0
	if k.road_distance(pp) < 3.0:
		pp = tent_at + sea * 2.2 - along * 1.0
	var ptop := m.post(pole, pp, 2.4, 0.11)
	await k.step()
	m.commit(pole, k.surface("timber", 0.8), "ChartPole")
	var chart := m.begin()
	m.block(chart, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(sea)), ptop - Vector3(0, 0.7, 0) + Vector3(sea.x, 0, sea.y) * 0.07), Vector3(0.45, 0.55, 0.01))
	await k.step()
	m.commit(chart, PoiKit.plain(Color(0.84, 0.78, 0.62), 0.9), "PinnedChart")
	k.marker("the_chart_pole", k.on_ground(pp.x + sea.x * 0.9, pp.y + sea.y * 0.9))
	# keel-grooves down to the water, the old trading fire, shells along the tide line
	var grooves := m.begin()
	for i in 3:
		var a := along * (float(i) - 1.0) * 5.0 + sea * 1.0
		if k.road_distance(a) < 3.0:
			continue
		for j in 8:
			var p := a + sea * float(j) * 1.4
			m.block(grooves, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(sea)), k.on_ground(p.x, p.y, 0.005)), Vector3(0.35, 0.015, 1.3))
	await k.step()
	m.commit(grooves, PoiKit.plain(Color(0.45, 0.42, 0.34), 0.95), "KeelGrooves")
	var ring := m.begin()
	var fire_at := -sea * 7.5 + along * 2.0
	if k.road_distance(fire_at) < 3.0:
		fire_at = -sea * 7.5 - along * 6.0
	rim_stones(d, ring, fire_at, 0.9, 9, 0.22)
	m.ellipsoid(ring, k.on_ground(fire_at.x, fire_at.y, 0.0), Vector3(0.7, 0.05, 0.7))
	await k.step()
	m.commit(ring, PoiKit.plain(Color(0.15, 0.14, 0.13), 0.95), "OldFire")
	var crab := k.prop("crab")
	if crab != "":
		var xfs: Array = []
		for i in 5:
			var q := sea * k.rng.randf_range(4.0, 8.0) + along * k.rng.randf_range(-10.0, 10.0)
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, 1.0))
		await k.step()
		k.scatter(crab, xfs, false, false, false)
	var boat := k.prop("rowboat")
	if boat != "":
		var bp := sea * 6.0 - along * 8.0
		await k.step()
		k.place(boat, k.on_ground(bp.x, bp.y, 0.05), PoiKit.yaw_of(sea) + 0.4, 1.0, true, Vector3(0.0, 0.0, 0.25))


# --- The Saltgate -----------------------------------------------------------------------------------------

## The Tallymen's sluice-fort on the headland at the Outfall's mouth, as the fort kind lays it (its
## yard "abandoned": no fire, no table, no hens), and then the sea's: standing water in the yard with
## wrack along the walls' feet, and out past the gate on the channel's bank the great sluice the fort
## was built to hold, two piers of weathered ashlar with a walkway and the windlass-house over them and
## the sea-gates hanging open between, a broken chain down into the water.
static func the_saltgate(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().SITES.build(d)
	var k := d.kit
	var m := d.masonry
	var def := ContentDB.get_or_empty(d.poi_id)
	var site: Dictionary = def.get("site", {})
	var radius := float(site.get("radius", 18.0))
	var b := deg_to_rad(float(site.get("gate_bearing_deg", 0.0)))
	var gate_dir := Vector2(sin(b), cos(b))
	var side := Vector2(gate_dir.y, -gate_dir.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(gate_dir))
	var SITES: GDScript = PoiDressing.kind_builders().SITES
	# the sluice: two piers on the bank past the gate, the walkway and the windlass-house over them
	var sc := gate_dir * (radius + 10.0)
	var g := k.on_ground(sc.x, sc.y).y
	var piers := m.begin()
	var top := g + 4.2
	for s in [-1.0, 1.0]:
		var pc := sc + side * 3.4 * float(s)
		var pg := k.on_ground(pc.x, pc.y).y
		var xf := Transform3D(basis, Vector3(pc.x, (pg - 1.5 + top) * 0.5, pc.y))
		m.block(piers, xf, Vector3(2.0, top - pg + 1.5, 4.2))
		k.collider(Vector3(2.0, top - pg + 1.5, 4.2), xf, "stone")
		# a cutwater on the sea side
		m.block(piers, Transform3D(basis * Basis(Vector3.UP, PI * 0.25), Vector3(pc.x, (pg - 1.5 + top - 1.0) * 0.5, pc.y) + Vector3(gate_dir.x, 0, gate_dir.y) * 2.1), Vector3(1.45, top - pg + 0.5, 1.45))
	# the walkway across, and the windlass-house on it
	var walk := Transform3D(basis, Vector3(sc.x, top + 0.15, sc.y))
	m.block(piers, walk, Vector3(8.8, 0.3, 2.6))
	k.collider(Vector3(8.8, 0.3, 2.6), walk, "stone")
	var house_c := Vector3(sc.x, top + 0.3, sc.y) + Vector3(side.x, 0, side.y) * 2.4
	for q in 4:
		var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(q))
		var e := bb * Vector3(0.0, 0.0, 1.15)
		if q == 2:
			continue          # its open side, toward the windlass's crank
		m.block(piers, Transform3D(bb, house_c + Vector3(0.0, 1.2, 0.0) + e), Vector3(2.5, 2.4, 0.3))
	m.block(piers, Transform3D(basis, house_c + Vector3(0.0, 2.55, 0.0)), Vector3(2.9, 0.3, 2.9))
	await k.step()
	SITES._commit(d, piers, SITES.stone_look(k, g), "Sluice", true)
	# the sea-gates: two leaves of black oak hanging open toward the sea, one off its upper hinge
	var oak := m.begin()
	for s in [-1.0, 1.0]:
		var hinge := sc + side * 2.35 * float(s) + gate_dir * 1.7
		var open := 1.15 + (0.25 if s > 0.0 else 0.0)
		var leaf_dir := (-side * float(s)).rotated(open * float(s))
		var lc := hinge + leaf_dir * 1.15
		var tilt := Basis(Vector3.UP, PoiKit.yaw_of(Vector2(leaf_dir.y, -leaf_dir.x))) * Basis(Vector3.BACK, 0.08 if s > 0.0 else 0.0)
		m.block(oak, Transform3D(tilt, Vector3(lc.x, g + 1.4, lc.y)), Vector3(2.3, 3.4, 0.28))
		for i in 4:
			m.block(oak, Transform3D(tilt, Vector3(lc.x, g + 0.2 + float(i) * 0.9, lc.y)), Vector3(2.35, 0.14, 0.36))
	# the windlass: an oak drum on its axle in the house, and its chain down into the water, snapped
	var drum_at := house_c + Vector3(0.0, 0.9, 0.0) - Vector3(side.x, 0, side.y) * 0.4
	m.rod(oak, Transform3D(basis * Basis(Vector3.FORWARD, PI * 0.5), drum_at), 0.55, 1.6)
	await k.step()
	m.commit(oak, PoiKit.plain(Color(0.1, 0.085, 0.07), 0.8), "SeaGates", true)
	if k.far:
		return
	var iron := m.begin()
	var chain_top := Vector3(sc.x, top, sc.y) + Vector3(side.x, 0, side.y) * 0.8
	for i in 9:
		var t := float(i) / 9.0
		var p := chain_top.lerp(Vector3(sc.x, g - 0.2, sc.y) + Vector3(gate_dir.x, 0, gate_dir.y) * 0.8, t)
		m.block(iron, Transform3D(Basis(Vector3.UP, float(i) * PI * 0.5), p), Vector3(0.08, 0.38, 0.22))
	await k.step()
	m.commit(iron, PoiKit.plain(Color(0.2, 0.15, 0.12), 0.6, 0.5), "Chain")
	# the race between the piers and the sea past them
	black_water(d, sc + gate_dir * 1.5, 6.5, 3.0, "Race")
	k.marker("the_sluice", Vector3(sc.x, top + 0.3, sc.y) - Vector3(side.x, 0, side.y) * 1.5, false, true, 1.5)
	# the yard: standing water in three pools, the drowned stand up out of it at night
	var back := -gate_dir
	var pools := [side * (radius * 0.34) + back * (radius * 0.02), -side * (radius * 0.36) + gate_dir * (radius * 0.08),
			gate_dir * (radius * 0.42) + side * (radius * 0.1)]
	for i in pools.size():
		var pc: Vector2 = pools[i]
		black_water(d, pc, 2.4 + float(i) * 0.4, 1.2, "YardWater%d" % i, 18)
	var pc0: Vector2 = pools[0]
	k.marker("the_yard_water", k.on_ground(pc0.x, pc0.y))
	# wrack and salt along the walls' feet inside, where the sea stood
	var wrack := k.flora("wrack")
	if wrack != "":
		var xfs: Array = []
		for i in 40:
			var a := k.rng.randf() * TAU
			var q := Vector2(sin(a), cos(a)) * (radius - 2.2 + k.rng.randf_range(-0.6, 0.4))
			if q.dot(gate_dir) > radius * 0.8:
				continue
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, k.rng.randf_range(0.9, 1.4)))
		await k.step()
		k.scatter(wrack, xfs, false, false, false)
	# reeds on the bank either side of the sluice
	var reed := k.flora("reeds")
	if reed != "":
		var xfs2: Array = []
		for i in 40:
			var q := sc + side * k.rng.randf_range(5.0, 11.0) * (1.0 if i % 2 == 0 else -1.0) + gate_dir * k.rng.randf_range(-3.0, 3.0)
			xfs2.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, k.rng.randf_range(0.9, 1.4)))
		await k.step()
		k.scatter(reed, xfs2, false, false, false)


# --- The Tide Hearth ----------------------------------------------------------------------------------------

## The Hearthstone on the Outfall's south bank hung round with lantern-knots, as the shrine kind lays it,
## and beside it the shelter Hal Ruddock has made of a sluice-boat's sail over two oars, his bedroll, and
## the line between two posts where he ties a knot for each of the Saltgate's watch, facing the walls.
static func tide_hearth(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().shrine(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	# across the water: the Saltgate, north-west over the Outfall
	var toward := Vector2(-82.0, -210.0).normalized()
	var side := Vector2(toward.y, -toward.x)
	var camp := toward * 9.0 + side * 6.5
	var timber := m.begin()
	var ta := m.post(timber, camp - side * 1.4, 1.9, 0.08, Vector3(0.0, 0.0, 0.12))
	var tb := m.post(timber, camp + side * 1.4, 1.9, 0.08, Vector3(0.0, 0.0, -0.12))
	await k.step()
	m.commit(timber, k.surface("timber", 0.75), "Oars")
	var ridge := (ta + tb) * 0.5
	for s in [-1.0, 1.0]:
		m.sheet(ridge + Vector3(toward.x, 0.0, toward.y) * 0.05 * float(s), PoiKit.yaw_of(side) + (0.0 if s > 0.0 else PI), 3.0, 2.0,
				PoiKit.plain(Color(0.62, 0.5, 0.4), 0.9), "Sail%d" % (0 if s > 0.0 else 1), 0.9, false, 3, 3)
	var roll := k.prop("bedroll")
	if roll != "":
		await k.step()
		k.place(roll, k.on_ground(camp.x, camp.y), PoiKit.yaw_of(side), 1.0, false)
	k.marker("home", k.on_ground(camp.x - toward.x * 0.6, camp.y - toward.y * 0.6), true, true, 1.2)
	# the knot-line facing the walls: twelve cords, the last loose
	var line := m.begin()
	var la := toward * 12.0 - side * 2.6
	var lb := toward * 12.0 + side * 2.6
	var pa := m.post(line, la, 1.6, 0.1)
	var pb := m.post(line, lb, 1.6, 0.1)
	m.limb(line, pa - Vector3(0, 0.1, 0), pb - Vector3(0, 0.1, 0), 0.025)
	await k.step()
	m.commit(line, k.surface("timber", 0.75), "KnotLine")
	var cord := m.begin()
	var knots := m.begin()
	var pts: Array = []
	for i in 12:
		pts.append(pa.lerp(pb, (float(i) + 0.5) / 12.0) - Vector3(0, 0.12, 0))
	cords(d, cord, knots, pts, Vector2(0.35, 0.6), 0.5)
	await k.step()
	m.commit(cord, PoiKit.plain(RUSH, 0.95), "WatchCords")
	m.commit(knots, PoiKit.plain(Color(0.42, 0.12, 0.1), 0.9), "WatchKnots")
	k.marker("the_knots", k.on_ground(toward.x * 10.6, toward.y * 10.6), true)
	k.marker("the_bank", k.on_ground(toward.x * 15.0 - side.x * 4.0, toward.y * 15.0 - side.y * 4.0), true)


# --- ships the marsh kept ------------------------------------------------------------------------------------

## A ship's hull of strakes on her keel at local `c`, lying along `lie`: `length` long, `beam` across, its
## sides `depth` deep, heeled `heel` radians over to starboard and sunk `sink` metres into the mud.
## Strakes are boards along the curve of her side; the weather side is broken off `broken` of the way up
## (0 none). Into `st`. Returns {deck_y (local, at her middle), bow (local Vector3 at the stem head),
## stern (Vector3), basis}.
static func hull(d: PoiDressing, st: SurfaceTool, c: Vector2, lie: Vector2, length: float, beam: float, depth: float,
		heel: float, sink: float, broken := 0.0) -> Dictionary:
	var k := d.kit
	var m := d.masonry
	var g := k.on_ground(c.x, c.y).y
	var keel_y := g - sink
	var yaw := PoiKit.yaw_of(lie)
	var frame := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, heel)
	var origin := Vector3(c.x, keel_y, c.y)
	var segs := 10
	var strakes := 6
	# her keel and her stem and sternpost
	m.block(st, Transform3D(frame, origin), Vector3(0.45, 0.5, length * 0.96))
	var stem_top := origin + frame * Vector3(0.0, depth + 1.2, length * 0.5 + 0.5)
	m.limb(st, origin + frame * Vector3(0.0, 0.0, length * 0.46), stem_top, 0.22)
	var stern_top := origin + frame * Vector3(0.0, depth + 0.9, -length * 0.5 - 0.2)
	m.limb(st, origin + frame * Vector3(0.0, 0.0, -length * 0.46), stern_top, 0.24)
	for side in [-1.0, 1.0]:
		var weather := float(side) > 0.0
		for j in strakes:
			var v := (float(j) + 0.5) / float(strakes)
			if weather and broken > 0.0 and v > 1.0 - broken and (j % 2 == 0 or v > 1.0 - broken * 0.6):
				continue
			for i in segs:
				var t0 := float(i) / float(segs)
				var t1 := float(i + 1) / float(segs)
				var p0 := _hull_point(t0, v, length, beam, depth) * Vector3(float(side), 1.0, 1.0)
				var p1 := _hull_point(t1, v, length, beam, depth) * Vector3(float(side), 1.0, 1.0)
				var mid := (p0 + p1) * 0.5
				var dir := (p1 - p0)
				var l := dir.length()
				if l < 0.05:
					continue
				var zb := dir / l
				var xb := Vector3(float(side), 0.0, 0.0)
				var yb := zb.cross(xb).normalized()
				xb = yb.cross(zb).normalized()
				var b := frame * Basis(xb, yb, zb)
				m.block(st, Transform3D(b, origin + frame * mid), Vector3(0.12, depth / float(strakes) * 1.08, l * 1.04))
	# her deck, a few planks across at the gunwale, the rest gone
	var deck_y := depth * 0.92
	for i in 6:
		var t := 0.2 + float(i) * 0.12
		var z := (t - 0.5) * length
		var half := _hull_point(t, 0.92, length, beam, depth).x
		m.block(st, Transform3D(frame, origin + frame * Vector3(0.0, deck_y, z)), Vector3(half * 2.0, 0.1, 0.5))
	k.collider(Vector3(beam * 0.9, depth, length * 0.85), Transform3D(frame, origin + frame * Vector3(0.0, depth * 0.5, 0.0)), "wood")
	return {"deck_y": (origin + frame * Vector3(0.0, deck_y, 0.0)).y, "bow": stem_top, "stern": stern_top, "basis": frame,
			"origin": origin, "yaw": yaw}


## A point on a hull's side: `t` from stern (0) to bow (1), `v` from keel (0) to gunwale (1).
static func _hull_point(t: float, v: float, length: float, beam: float, depth: float) -> Vector3:
	var z := (t - 0.5) * length
	# fuller aft than forward, as a trader is, the bow drawn fine
	var along := 1.0 - pow(absf(t - 0.45) * 2.0 / 1.1, 2.2)
	along = clampf(along, 0.05, 1.0)
	var rnd := sqrt(clampf(v, 0.0, 1.0))
	var x := beam * 0.5 * along * (0.25 + 0.75 * rnd)
	var y := depth * v + (absf(t - 0.5) * 2.0) * (absf(t - 0.5) * 2.0) * 0.9
	return Vector3(x, y, z)


## A mast stepped at `foot` and leaning along `lean` (a unit Vector3 from upright), `height` tall, with a
## yard across near its head and shrouds down to her sides. Into `st`. Returns its head.
static func mast(d: PoiDressing, st: SurfaceTool, foot: Vector3, lean: Vector3, height: float, across: Vector3,
		shroud_feet: Array, yard := true) -> Vector3:
	var m := d.masonry
	var dir := (Vector3.UP + lean).normalized()
	var head := foot + dir * height
	m.limb(st, foot, head, 0.22)
	if yard:
		var yc := foot + dir * (height * 0.82)
		m.limb(st, yc - across * 3.2, yc + across * 3.2, 0.11)
	for f in shroud_feet:
		m.limb(st, head - dir * 0.6, f, 0.03)
	return head


# --- The Reed Wreck -----------------------------------------------------------------------------------------

## A Salt Isles trader stranded three miles inland, sitting nearly upright in the reeds with the reeds
## grown up through her, her mast standing with its yard and shrouds, her deckhouse aft with its door
## swung open, and under her bow the crate with the chart nobody has read (`the_chart`); leech-hounds
## have made a den of her hold.
static func reed_wreck(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lie := k.grain()
	var across := Vector2(lie.y, -lie.x)
	var wood := m.begin()
	var h: Dictionary = hull(d, wood, Vector2.ZERO, lie, 20.0, 6.0, 3.0, 0.08, 0.7, 0.3)
	var frame: Basis = h["basis"]
	var o: Vector3 = h["origin"]
	var shrouds: Array = []
	for s in [-1.0, 1.0]:
		for z in [-1.5, 1.2]:
			shrouds.append(o + frame * Vector3(float(s) * 2.6, 2.9, float(z)))
	var mast_foot := o + frame * Vector3(0.0, 0.4, 1.0)
	mast(d, wood, mast_foot, Vector3(across.x, 0.0, across.y) * 0.08, 15.0, frame * Vector3(1, 0, 0), shrouds)
	# the deckhouse aft, its door swung open
	var dh := o + frame * Vector3(0.0, 2.75, -6.4)
	m.block(wood, Transform3D(frame, dh + frame * Vector3(0, 1.0, 0)), Vector3(3.6, 2.0, 3.2))
	m.block(wood, Transform3D(frame, dh + frame * Vector3(0, 2.1, 0)), Vector3(4.0, 0.2, 3.6))
	# the deckhouse door, swung open on its hinge
	m.block(wood, Transform3D(frame * Basis(Vector3.UP, 1.2), dh + frame * Vector3(-0.85, 0.85, 1.95)), Vector3(0.9, 1.7, 0.06))
	await k.step()
	m.commit(wood, k.surface("planks", 0.9), "Hull", true)
	if k.far:
		return
	k.touchable("Deckhouse", dh + frame * Vector3(0.0, 0.9, 2.1), "Look into the deckhouse", "core:dialogue/reed_wreck_deckhouse", "", false)
	# under the bow, the crate with the chart on it
	var bow: Vector3 = h["bow"]
	var crate_at := Vector2(bow.x, bow.z) + lie * 1.8 + across * 2.2
	var crate := k.prop("crate")
	if crate != "":
		await k.step()
		k.place(crate, k.on_ground(crate_at.x, crate_at.y), PoiKit.yaw_of(lie), 1.0, true)
		var scroll := k.prop("scroll")
		if scroll != "":
			await k.step()
			k.place(scroll, k.on_ground(crate_at.x, crate_at.y, PoiKit.height_of(crate)), PoiKit.yaw_of(lie) + 0.3, 1.0, false)
	k.marker("the_chart", k.on_ground(crate_at.x - across.x * 0.8, crate_at.y - across.y * 0.8, 0.6))
	# the hounds' den in her hold: bones, and a way in through a sprung strake on the weather side
	var bones := m.begin()
	for i in 10:
		var q := Vector2(o.x, o.z) + across * k.rng.randf_range(3.2, 5.0) + lie * k.rng.randf_range(-3.0, 3.0)
		var a := k.rng.randf() * TAU
		var p := k.on_ground(q.x, q.y, 0.04)
		m.limb(bones, p, p + Vector3(sin(a), 0.02, cos(a)) * k.rng.randf_range(0.25, 0.5), 0.025)
	await k.step()
	m.commit(bones, PoiKit.plain(Color(0.78, 0.74, 0.64), 0.8), "Bones")
	k.marker("the_den", k.on_ground(o.x + across.x * 4.0, o.z + across.y * 4.0))
	# the reeds grown up round her and through her
	var reed := k.flora("reeds")
	if reed != "":
		var xfs: Array = []
		for i in 90:
			var q := lie * k.rng.randf_range(-16.0, 16.0) + across * k.rng.randf_range(-13.0, 13.0)
			if absf(q.dot(across)) < 3.4 and absf(q.dot(lie)) < 10.5 and k.rng.randf() < 0.7:
				continue
			if q.distance_to(crate_at) < 2.0:
				continue
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, k.rng.randf_range(1.0, 1.6)))
		await k.step()
		k.scatter(reed, xfs, false, false, false)


# --- The Grey Gull ----------------------------------------------------------------------------------------

## A Salt Isles trader driven onto the carr's edge and lying hard over on her side, her weather strakes
## gone, her mast snapped and fallen along the shingle, and at her bow her figurehead: a gull with its
## wings swept back and a woman's face, staring up the carr.
static func grey_gull(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(90.0)
	var lie := Vector2(sea.y, -sea.x) if sea != Vector2.ZERO else k.grain()
	var across := Vector2(lie.y, -lie.x)
	var wood := m.begin()
	var h: Dictionary = hull(d, wood, Vector2.ZERO, lie, 19.0, 5.8, 2.9, 0.48, 0.45, 0.55)
	var frame: Basis = h["basis"]
	var o: Vector3 = h["origin"]
	# the mast, snapped a man's height up, the rest of it lying along the shingle
	var foot := o + frame * Vector3(0.0, 0.4, 1.0)
	var stump := foot + frame * Vector3(0.0, 2.6, 0.0)
	m.limb(wood, foot, stump, 0.22)
	var fallen_a := k.on_ground(stump.x + across.x * 2.0, stump.z + across.y * 2.0, 0.25)
	var fallen_b := k.on_ground(stump.x + across.x * 3.0 + lie.x * 12.0, stump.z + across.y * 3.0 + lie.y * 12.0, 0.2)
	m.limb(wood, fallen_a, fallen_b, 0.2)
	await k.step()
	m.commit(wood, PoiKit.plain(Color(0.42, 0.4, 0.36), 0.9), "Hull", true)
	# the figurehead under her bowsprit: a gull's body and swept wings, and a woman's face
	var bow: Vector3 = h["bow"]
	var fig := m.begin()
	var fb := frame * Basis(Vector3.RIGHT, -0.5)
	var fc := bow + frame * Vector3(0.0, -0.9, 0.7)
	m.ellipsoid(fig, fc, Vector3(0.45, 0.55, 0.9), fb)
	for s in [-1.0, 1.0]:
		m.block(fig, Transform3D(fb * Basis(Vector3.UP, 0.5 * float(s)) * Basis(Vector3.BACK, 0.3 * float(s)), fc + fb * Vector3(0.55 * float(s), 0.2, -0.5)), Vector3(1.4, 0.12, 0.7))
	m.ellipsoid(fig, fc + fb * Vector3(0.0, 0.35, 0.95), Vector3(0.24, 0.3, 0.26), fb)
	# the stem's knee under her, carved and painted with the figure, down into the shingle
	var knee_foot := k.on_ground(fc.x - lie.x * 0.8, fc.z - lie.y * 0.8, -0.3)
	m.limb(fig, fc + Vector3(0.0, -0.3, 0.0), knee_foot, 0.2)
	await k.step()
	m.commit(fig, PoiKit.plain(Color(0.86, 0.84, 0.78), 0.7), "Figurehead", true)
	if k.far:
		return
	k.marker("the_figurehead", k.on_ground(bow.x + lie.x * 2.0, bow.z + lie.y * 2.0))
	k.touchable("Figurehead", fc + frame * Vector3(0.0, 0.2, 0.9), "Look at the figurehead's face", "core:dialogue/grey_gull_figurehead", "", false)
	# her cargo strewn up the carr: barrels split, a chest wedged in her side
	for i in 4:
		var q := across * k.rng.randf_range(4.0, 9.0) + lie * k.rng.randf_range(-7.0, 7.0)
		var pk := k.prop(["barrel", "crate", "barrel", "sack"][i])
		if pk != "":
			await k.step()
			k.place(pk, k.on_ground(q.x, q.y), k.rng.randf() * TAU, 1.0, true, Vector3(k.rng.randf_range(-0.4, 0.4), 0.0, k.rng.randf_range(-0.4, 0.4)))
	var chest := k.prop("chest")
	if chest != "":
		var q := Vector2(o.x, o.z) - across * 2.6 + lie * 2.0
		await k.step()
		k.place(chest, k.on_ground(q.x, q.y), PoiKit.yaw_of(lie) + 0.3, 1.0, true)
	k.marker("the_hold", k.on_ground(o.x - across.x * 3.5, o.z - across.y * 3.5))
	var wrack := k.flora("wrack")
	if wrack != "":
		var xfs: Array = []
		for i in 26:
			var q := lie * k.rng.randf_range(-13.0, 13.0) + across * k.rng.randf_range(-11.0, -4.0)
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, k.rng.randf_range(0.8, 1.3)))
		await k.step()
		k.scatter(wrack, xfs, false, false, false)
	await reeds(d, 11.0, 19.0, 50, [[Vector2.ZERO, 10.0]])


# --- The Drowned Trader ---------------------------------------------------------------------------------

## A trader sunk to her rails in the Delta's mud by the Saeva road: only her gunwales and the stumps of
## her deck stand out of the peat, black water lying on what is left of her deck, her mast leaning far
## over with indigo rags tied to its shrouds, and her lantern on its pole in the mud at her bow.
static func drowned_trader(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lie := k.grain()
	var across := Vector2(lie.y, -lie.x)
	var wood := m.begin()
	var h: Dictionary = hull(d, wood, Vector2.ZERO, lie, 15.0, 5.0, 2.6, 0.12, 2.2, 0.2)
	var frame: Basis = h["basis"]
	var o: Vector3 = h["origin"]
	var lean := Vector3(across.x, 0.0, across.y) * 0.42 + Vector3(lie.x, 0.0, lie.y) * 0.1
	var shrouds: Array = []
	for s in [-1.0, 1.0]:
		shrouds.append(o + frame * Vector3(float(s) * 2.2, 2.5, 0.6))
	var head := mast(d, wood, o + frame * Vector3(0.0, 1.4, 0.8), lean, 9.5, frame * Vector3(1, 0, 0), shrouds, false)
	await k.step()
	m.commit(wood, k.surface("planks", 0.95), "Hull", true)
	if k.far:
		return
	# the water lying on her deck, inside her rails
	var deck_y := float(h["deck_y"])
	var wst := m.begin()
	m.block(wst, Transform3D(frame, o + frame * Vector3(0.0, 2.25, 0.4)), Vector3(3.4, 0.02, 9.0))
	await k.step()
	m.commit(wst, k.still_water(deck_y - 2.0, Color(0.85, 0.9, 0.85), 0.88), "DeckWater")
	# indigo rags tied along the shrouds
	var rag := PoiKit.plain(INDIGO, 0.9)
	for i in 4:
		var s0: Vector3 = shrouds[i % 2]
		var t := 0.3 + 0.15 * float(i)
		var at := s0.lerp(head, t)
		m.sheet(at, PoiKit.yaw_of(lie) + k.rng.randf_range(-0.4, 0.4), 0.35, 0.6, rag, "RagBunting%d" % i, 0.15, false, 1, 2)
	# her lantern on a pole in the mud at her bow
	var bow: Vector3 = h["bow"]
	var poles := m.begin()
	lantern_pole(d, poles, Vector2(bow.x, bow.z) + lie * 1.6 + across * 1.2, -across, true, 2.5)
	await k.step()
	m.commit(poles, k.surface("timber", 0.85), "BowPole")
	k.marker("the_rails", k.on_ground(o.x + across.x * 3.6, o.z + across.y * 3.6))
	var s_first: Vector3 = shrouds[0]
	k.touchable("Rags", s_first.lerp(head, 0.35) - Vector3(0, 0.8, 0), "Look at the knots in the rags", "core:dialogue/drowned_trader_rags", "", false)
	await reeds(d, 8.0, 15.0, 40, [[Vector2.ZERO, 9.0]])


# --- The Old Crannog -------------------------------------------------------------------------------------------

## An island-house older than any stilt: a heap of stones raised in a black pool of the carr, on it a round
## house of wattle under a cone of reed, the fire laid ready at its door, and a causeway of stones and laid
## logs out to the bank, three of them loose. Keeps Aue Sa's spots: home, the_fire, the_causeway.
static func old_crannog(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var bank := k.grain()
	var y := black_water(d, Vector2.ZERO, 13.0, 3.0, "CarrPool")
	# the islet: a heap of stones under turf
	var turf := PoiKit.painted(5, {"base": "#3a3f2a", "accent": "#2a2f1d", "grout": "#171a10", "unit": 0.3}, 0.5)
	m.mound(Vector3(0.0, y - 0.4, 0.0), 6.2, 1.0, turf, "Islet", true, 2.6, 6, 22, true, 0.08)
	var top := y + 0.6
	var stones := m.begin()
	rim_stones(d, stones, Vector2.ZERO, 6.0, 26, 0.55)
	# the house: a drum of wattle, its door toward the causeway, under a cone of reed
	var wall := m.begin()
	var roof := m.begin()
	var r := 3.0
	var door_a := PoiKit.yaw_of(bank)
	m.drum(wall, Transform3D(Basis.IDENTITY, Vector3(0.0, top - 0.1, 0.0)), r, 2.0, 0.0, door_a, true, 0.4)
	var cone_h := 3.2
	for i in 14:
		var a := TAU * float(i) / 14.0
		var eave := Vector3(sin(a) * (r + 0.55), top + 1.75, cos(a) * (r + 0.55))
		var apex := Vector3(0.0, top + 1.9 + cone_h, 0.0)
		var mid := (eave + apex) * 0.5
		var dir := (apex - eave).normalized()
		var xb := Vector3(cos(a), 0.0, -sin(a))
		var zb := dir.cross(xb).normalized()
		m.block(roof, Transform3D(Basis(xb, dir, zb), mid), Vector3(TAU * (r + 0.6) / 14.0 * 1.15, eave.distance_to(apex), 0.25))
	k.collider(Vector3(r * 1.4, 0.3, r * 1.4), Transform3D(Basis.IDENTITY, Vector3(0.0, top + 3.2, 0.0)), "wood")
	await k.step()
	m.commit(stones, k.surface("stone", 0.9), "IsletStones", true)
	m.commit(wall, PoiKit.painted(5, REED_WALL, 0.7), "Wattle", true)
	m.commit(roof, PoiKit.painted(5, THATCH, 0.6), "Cone", true)
	if k.far:
		return
	var dark := m.begin()
	var dp := bank * (r - 0.05)
	m.block(dark, Transform3D(Basis(Vector3.UP, door_a), Vector3(dp.x, top + 0.8, dp.y)), Vector3(0.9, 1.6, 0.08))
	m.commit(dark, PoiKit.plain(DOOR_DARK, 0.95), "Door")
	k.marker("home", Vector3(0.0, top, 0.0), true, true, 1.5)
	# the fire laid at the door, unlit: a ring of stones and the sticks in a cone
	var fire := bank * (r + 1.6) + Vector2(bank.y, -bank.x) * 1.2
	var fg := Vector3(fire.x, top, fire.y)
	var ring := m.begin()
	for i in 8:
		var a := TAU * float(i) / 8.0
		m.ellipsoid(ring, fg + Vector3(sin(a) * 0.55, 0.06, cos(a) * 0.55), Vector3(0.18, 0.1, 0.14))
	var sticks := m.begin()
	for i in 7:
		var a := TAU * float(i) / 7.0
		m.limb(sticks, fg + Vector3(sin(a) * 0.35, 0.05, cos(a) * 0.35), fg + Vector3(0.0, 0.5, 0.0), 0.035)
	# the hearth-stones go down through the islet's turf to the stone heap under it
	var hg := k.on_ground(fire.x, fire.y).y
	m.block(ring, Transform3D(Basis.IDENTITY, Vector3(fire.x, (hg - 0.2 + fg.y) * 0.5, fire.y)), Vector3(0.7, fg.y - hg + 0.2, 0.7))
	await k.step()
	m.commit(ring, k.surface("stone", 0.9), "FireRing")
	m.commit(sticks, k.surface("timber", 0.9), "FireLaid")
	k.marker("the_fire", fg + Vector3(bank.y, 0.0, -bank.x) * 1.0, true)
	# the causeway: stones and logs laid out to the bank, the loose three a little canted
	var cw := m.begin()
	var a2 := bank * 6.0
	var b2 := bank * 14.5
	var n := 9
	for i in n:
		var p := a2.lerp(b2, float(i) / float(n - 1))
		var loose := i == 2 or i == 5 or i == 6
		var tilt := Basis(Vector3.UP, PoiKit.yaw_of(bank) + k.rng.randf_range(-0.2, 0.2)) * Basis(Vector3.RIGHT, (0.12 if loose else 0.0))
		var py := maxf(k.on_ground(p.x, p.y).y, y - 0.1) + 0.08
		if i % 3 == 1:
			m.limb(cw, Vector3(p.x, py, p.y) - Vector3(bank.y, 0, -bank.x) * 0.6, Vector3(p.x, py, p.y) + Vector3(bank.y, 0, -bank.x) * 0.6, 0.16)
		else:
			m.ellipsoid(cw, Vector3(p.x, py, p.y), Vector3(0.45, 0.14, 0.38), tilt)
		k.collider(Vector3(0.9, 0.3, 0.8), Transform3D(tilt, Vector3(p.x, py - 0.05, p.y)), "stone")
	await k.step()
	m.commit(cw, k.surface("stone", 0.85), "Causeway")
	k.marker("the_causeway", k.on_ground(b2.x + bank.x * 1.2, b2.y + bank.y * 1.2), true)
	k.touchable("FireLaid", fg + Vector3(0, 0.4, 0), "Look at the fire laid by the door", "core:dialogue/old_crannog_fire", "", false)
	await reeds(d, 13.5, 20.0, 60, [[b2 + bank * 1.5, 2.5]])
	var alder := k.tree("alder")
	if alder != "":
		var xfs: Array = []
		for i in 4:
			var a := k.rng.randf() * TAU
			var q := Vector2(sin(a), cos(a)) * k.rng.randf_range(15.0, 19.0)
			if q.dot(bank) > 10.0:
				continue
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, k.rng.randf_range(0.7, 1.0)))
		await k.step()
		k.scatter(alder, xfs, false, false, true)


# --- The Cockle Beds ----------------------------------------------------------------------------------------

## The tideflats' cockle-beds staked out in family rows, each stake tied with its family's knot: and
## every stake moved one row toward the sea in the night, the old holes plain in the mud a row behind
## each. Rakes and cockle-baskets left where the rakers dropped them, heaps of shell by the sorting board.
static func cockle_beds(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(150.0)
	if sea == Vector2.ZERO:
		sea = Vector2(-1, 0)
	var along := Vector2(sea.y, -sea.x)
	var stakes := m.begin()
	var holes := m.begin()
	var knot_mats := [m.begin(), m.begin(), m.begin()]
	var rows := 5
	var per := 11
	for r in rows:
		var fam := r % 3
		for i in per:
			var base := sea * ((float(r) - 2.0) * 3.4) + along * ((float(i) - 5.0) * 2.0) + k.jitter(0.15)
			# where it was: a dark hole in the mud a row back toward the land
			var was := base - sea * 3.4
			var hg := k.on_ground(was.x, was.y).y
			m.ellipsoid(holes, Vector3(was.x, hg + 0.005, was.y), Vector3(0.14, 0.02, 0.14))
			# where it is now, a row toward the sea
			var top := m.post(stakes, base + sea * 0.0, 1.25 + k.rng.randf_range(-0.1, 0.15), 0.07, Vector3(k.rng.randf_range(-0.04, 0.04), 0.0, k.rng.randf_range(-0.04, 0.04)))
			m.block(knot_mats[fam], Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), top - Vector3(0, 0.12, 0)), Vector3(0.12, 0.1, 0.12))
	await k.step()
	m.commit(stakes, k.surface("timber", 0.75), "Stakes", true)
	if k.far:
		return
	m.commit(holes, PoiKit.plain(Color(0.08, 0.07, 0.06), 0.95), "OldHoles")
	m.commit(knot_mats[0], PoiKit.plain(INDIGO, 0.9), "KnotsIndigo")
	m.commit(knot_mats[1], PoiKit.plain(RUSH, 0.9), "KnotsRush")
	m.commit(knot_mats[2], PoiKit.plain(Color(0.5, 0.16, 0.12), 0.9), "KnotsRed")
	k.marker("the_rows", k.on_ground(-sea.x * 6.0, -sea.y * 6.0))
	# the sorting board and the shell heaps on the landward side
	var shore := -sea * 12.5
	var table := k.prop("table_trestle")
	if table != "":
		await k.step()
		k.place(table, k.on_ground(shore.x, shore.y), PoiKit.yaw_of(along), 1.0, true)
	var shell := PoiKit.plain(Color(0.86, 0.84, 0.78), 0.6)
	for i in 3:
		var q := shore + along * (2.6 + float(i) * 1.8) - sea * 0.8
		m.mound(k.on_ground(q.x, q.y, -0.05), 0.75 - float(i) * 0.12, 0.45, shell, "Shells%d" % i, false, 1.6, 4, 12, false, 0.1)
	var basket := k.prop("basket")
	if basket != "":
		var xfs: Array = []
		for i in 5:
			var q := sea * k.rng.randf_range(-6.0, 4.0) + along * k.rng.randf_range(-9.0, 9.0)
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, 1.0))
		await k.step()
		k.scatter(basket, xfs, false, false, true)
	var rakes := m.begin()
	for i in 3:
		var q := sea * k.rng.randf_range(-4.0, 3.0) + along * k.rng.randf_range(-8.0, 8.0)
		var a := k.rng.randf() * TAU
		var p := k.on_ground(q.x, q.y, 0.04)
		var dir := Vector3(sin(a), 0.0, cos(a))
		m.limb(rakes, p, p + dir * 1.6, 0.025)
		m.block(rakes, Transform3D(Basis(Vector3.UP, a), p + dir * 1.65), Vector3(0.5, 0.05, 0.08))
	await k.step()
	m.commit(rakes, k.surface("timber", 0.7), "Rakes")
	k.touchable("Rows", k.on_ground(-sea.x * 3.4, -sea.y * 3.4, 0.6), "Look at the stakes", "core:dialogue/cockle_beds_stakes", "", false)
	var crab := k.prop("crab")
	if crab != "":
		var xfs2: Array = []
		for i in 6:
			var q := sea * k.rng.randf_range(4.0, 9.0) + along * k.rng.randf_range(-10.0, 10.0)
			xfs2.append(PoiKit.transform_at(k.on_ground(q.x, q.y), k.rng.randf() * TAU, 1.0))
		await k.step()
		k.scatter(crab, xfs2, false, false, false)


# --- The Salt Pans --------------------------------------------------------------------------------------------

## Square brine pools on the tideflats in rows behind clay banks, the near ones still wet, the far ones
## drying white; the rakers' huts on legs, the salt heaped by them under reed; and one pan dried to a crust
## overnight with a line of footprints across it from the sea side, and none coming back.
static func salt_pans(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(150.0)
	if sea == Vector2.ZERO:
		sea = Vector2(-1, 0)
	var along := Vector2(sea.y, -sea.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(sea))
	var banks := m.begin()
	var brine := m.begin()
	var crust := m.begin()
	var size := 4.2
	var the_pan := Vector2.ZERO
	for r in 3:
		for c in 4:
			var pc := sea * ((float(r) - 1.0) * (size + 0.8)) + along * ((float(c) - 1.5) * (size + 0.8))
			var g := k.on_ground(pc.x, pc.y).y
			for q in 4:
				var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(q))
				m.block(banks, Transform3D(bb, Vector3(pc.x, g + 0.08, pc.y) + bb * Vector3(0.0, 0.0, size * 0.5)), Vector3(size + 0.5, 0.32, 0.5))
			var dry := r == 2 or (r == 1 and c >= 2)
			if r == 2 and c == 1:
				the_pan = pc
			m.block(crust if dry else brine, Transform3D(basis, Vector3(pc.x, g + (0.03 if dry else 0.12), pc.y)), Vector3(size - 0.3, 0.02, size - 0.3))
	await k.step()
	m.commit(banks, PoiKit.painted(5, CLAY, 0.8), "PanBanks", true)
	m.commit(crust, PoiKit.plain(Color(0.92, 0.91, 0.88), 0.5), "SaltCrust", true)
	if k.far:
		return
	var bmi := m.commit(brine, k.still_water(-0.3, Color(1.05, 1.05, 1.0), 0.75), "Brine")
	if bmi != null:
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the footprints across the dried pan, from the sea side, none back
	var marks_st := m.begin()
	var pg := k.on_ground(the_pan.x, the_pan.y).y
	for i in 8:
		var t := float(i) / 7.0
		var p := the_pan + sea * lerpf(size * 0.45, -size * 0.45, t) + along * (0.16 if i % 2 == 0 else -0.16)
		m.block(marks_st, Transform3D(basis, Vector3(p.x, pg + 0.045, p.y)), Vector3(0.12, 0.01, 0.28))
	await k.step()
	m.commit(marks_st, PoiKit.plain(Color(0.25, 0.24, 0.22), 0.9), "Footprints")
	k.marker("the_crusted_pan", Vector3(the_pan.x, pg, the_pan.y) - Vector3(sea.x, 0, sea.y) * (size * 0.5 + 0.8))
	k.touchable("Footprints", Vector3(the_pan.x, pg + 0.4, the_pan.y) - Vector3(sea.x, 0, sea.y) * (size * 0.5 + 0.4), "Look at the footprints in the salt",
			"core:dialogue/salt_pans_footprints", "", false)
	# the rakers' huts on legs at the landward end, salt heaped under reed between them
	var landward := -sea * (size * 1.5 + 7.0)
	for s in [-1.0, 1.0]:
		await stilt_house(d, landward + along * 5.5 * float(s), sea, 3.0, 2.8, 1.1, "Raker")
	var salt := PoiKit.plain(Color(0.9, 0.89, 0.86), 0.55)
	m.mound(k.on_ground(landward.x + sea.x * 2.4, landward.y + sea.y * 2.4, -0.05), 1.3, 0.9, salt, "SaltHeap", true, 1.2, 5, 14, false, 0.08)
	var reed := m.begin()
	var hc := landward + sea * 2.4
	for s in [-1.0, 1.0]:
		m.block(reed, Transform3D(basis * Basis(Vector3.BACK, 0.6 * float(s)), k.on_ground(hc.x, hc.y, 1.2) + basis * Vector3(float(s) * 0.7, 0.0, 0.0)), Vector3(1.8, 0.12, 2.6))
	await k.step()
	m.commit(reed, PoiKit.painted(5, THATCH, 0.6), "SaltThatch")
	var rakes := m.begin()
	for i in 4:
		var p := k.on_ground(landward.x + along.x * (float(i) - 1.5) * 0.4 - sea.x * 1.2, landward.y + along.y * (float(i) - 1.5) * 0.4 - sea.y * 1.2)
		m.limb(rakes, p, p + Vector3(sea.x * 0.3, 2.0, sea.y * 0.3), 0.03)
	await k.step()
	m.commit(rakes, k.surface("timber", 0.7), "SaltRakes")


# --- The Greyreed Decoy -----------------------------------------------------------------------------------------

## A wildfowlers' decoy: a black pool in the reeds, and curving off it three pipes, channels narrowing under
## hoops of withy hung with net, with wattle screens staggered along each where the decoyman and his dog
## show and hide; the decoyman's hut, and at the end of one pipe the net torn open from inside.
static func greyreed_decoy(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var y := black_water(d, Vector2.ZERO, 8.5, 2.0, "DecoyPool")
	var hoops := m.begin()
	var net := m.begin()
	var screens := m.begin()
	var torn_at := Vector3.ZERO
	var start := k.rng.randf() * TAU
	for p in 3:
		var a0 := start + TAU * float(p) / 3.0
		var bend := 0.9 * (1.0 if p % 2 == 0 else -1.0)
		var n := 9
		var prev := Vector2.ZERO
		for i in n:
			var t := float(i) / float(n - 1)
			var a := a0 + bend * t
			var r := 8.0 + t * 12.0
			var c := Vector2(sin(a), cos(a)) * r
			var w := lerpf(3.6, 1.0, t)
			var h := lerpf(2.6, 0.9, t)
			var dir := (c - prev).normalized() if i > 0 else Vector2(sin(a0), cos(a0))
			var across := Vector2(dir.y, -dir.x)
			var g := maxf(k.on_ground(c.x, c.y).y, y - 0.05)
			# the hoop: a half-ring of withy over the channel
			var segs := 6
			for j in segs:
				var u0 := PI * float(j) / float(segs)
				var u1 := PI * float(j + 1) / float(segs)
				var q0 := Vector3(c.x, g, c.y) + Vector3(across.x, 0, across.y) * cos(u0) * w * 0.5 + Vector3.UP * sin(u0) * h
				var q1 := Vector3(c.x, g, c.y) + Vector3(across.x, 0, across.y) * cos(u1) * w * 0.5 + Vector3.UP * sin(u1) * h
				m.limb(hoops, q0, q1, 0.035)
			# the net between this hoop and the last: a few long strands over the top
			if i > 0 and not (p == 1 and i == n - 1):
				for j in 5:
					var u := PI * (float(j) + 0.5) / 5.0
					var qa := Vector3(c.x, g, c.y) + Vector3(across.x, 0, across.y) * cos(u) * w * 0.5 + Vector3.UP * sin(u) * h
					var wp := lerpf(3.6, 1.0, float(i - 1) / float(n - 1))
					var hp := lerpf(2.6, 0.9, float(i - 1) / float(n - 1))
					var gp := maxf(k.on_ground(prev.x, prev.y).y, y - 0.05)
					var qb := Vector3(prev.x, gp, prev.y) + Vector3(across.x, 0, across.y) * cos(u) * wp * 0.5 + Vector3.UP * sin(u) * hp
					m.block(net, Transform3D(_along(qb - qa), (qa + qb) * 0.5), Vector3(0.02, qa.distance_to(qb), 0.02))
			elif p == 1 and i == n - 1:
				torn_at = Vector3(c.x, g, c.y)
			# a wattle screen beside every other hoop, on the outside of the bend
			if i % 2 == 1:
				var sc := c + across * (w * 0.5 + 1.2) * (1.0 if p % 2 == 0 else -1.0)
				var sg := k.on_ground(sc.x, sc.y).y
				m.block(screens, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(dir)), Vector3(sc.x, sg + 0.9, sc.y)), Vector3(0.12, 1.8, 2.2))
				k.collider(Vector3(0.15, 1.8, 2.2), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(dir)), Vector3(sc.x, sg + 0.9, sc.y)), "wood")
			prev = c
	await k.step()
	m.commit(hoops, k.surface("timber", 0.8), "Hoops", true)
	if k.far:
		return
	m.commit(net, PoiKit.plain(Color(0.4, 0.38, 0.32), 0.95), "Nets")
	m.commit(screens, PoiKit.painted(5, REED_WALL, 0.7), "Screens")
	# the torn net at the end of the second pipe, hanging in rags, torn from inside
	var rags := m.begin()
	for i in 6:
		var a := k.rng.randf() * TAU
		var top := torn_at + Vector3(sin(a) * 0.5, 0.8, cos(a) * 0.5)
		m.block(rags, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.15), top - Vector3(0, 0.45, 0)), Vector3(0.4, 1.0, 0.02))
	await k.step()
	m.commit(rags, PoiKit.plain(Color(0.4, 0.38, 0.32), 0.95), "TornNet")
	k.marker("the_torn_pipe", torn_at + Vector3(0.0, 0.0, 0.0))
	# the decoyman's hut, back from the pool, and his dog's bowl
	var hut_dir := Vector2(sin(start + PI / 3.0), cos(start + PI / 3.0))
	var hut: Dictionary = await stilt_house(d, hut_dir * 14.0, -hut_dir, 3.2, 3.0, 0.8, "Decoyman")
	k.marker("home", hut["inside"], true, true, 1.4)
	var bowl := k.prop("bowl")
	if bowl != "":
		var foot: Vector3 = hut["foot"]
		await k.step()
		k.place(bowl, k.on_ground(foot.x + 1.0, foot.z), 0.0, 1.0, false)
	await reeds(d, 9.0, 22.0, 90, [[hut_dir * 14.0, 4.5]])


# --- The Indigo Beds -------------------------------------------------------------------------------------------

## Isseva's north dye beds: long reed troughs of steeping indigo in rows, the liquor near-black in most of
## them and gone pale in the row nearest the Nave; cloth drying on lines between, the dyers' vat on its
## fire and the paddles leaning on it.
static func indigo_beds(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	# the dyers' hut, the vat on its fire, the paddles leaning on it
	var hut: Dictionary = await stilt_house(d, Vector2(-5.0, -6.0), Vector2(0.6, 0.8), 3.6, 3.2, 0.7, "Dyers")
	if k.far:
		return
	k.marker("home", hut["inside"], true, true, 1.4)
	var vat_at := Vector2(-2.0, 1.5)
	var vat := k.prop("barrel")
	if vat != "":
		await k.step()
		k.place(vat, k.on_ground(vat_at.x, vat_at.y), 0.0, 1.5, true)
	var fire := k.prop("campfire")
	if fire != "":
		await k.step()
		k.place(fire, k.on_ground(vat_at.x + 1.6, vat_at.y), 0.0, 0.8, false)
		k.light(k.on_ground(vat_at.x + 1.6, vat_at.y, 0.5), Color(1.0, 0.6, 0.3), 1.4, 7.0)
	var paddles := m.begin()
	for i in 3:
		var p := k.on_ground(vat_at.x - 0.9 + float(i) * 0.3, vat_at.y - 0.9)
		m.limb(paddles, p, p + Vector3(0.1, 1.6, 0.25), 0.03)
		m.block(paddles, Transform3D(Basis.IDENTITY, p + Vector3(0.02, 0.2, 0.05)), Vector3(0.14, 0.4, 0.03))
	await k.step()
	m.commit(paddles, k.surface("timber", 0.8), "Paddles")
	k.marker("the_vat", k.on_ground(vat_at.x, vat_at.y - 1.8), true)
	# the Nave is away north-west of the beds
	var nave := Vector2(-3300.0 - d.world_position.x, -1420.0 - d.world_position.z).normalized()
	var across := Vector2(nave.y, -nave.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(across))
	var troughs := m.begin()
	var deep := m.begin()
	var pale := m.begin()
	for r in 5:
		var c := nave * ((float(r) - 2.0) * 2.4) + across * 9.0
		var g := k.on_ground(c.x, c.y).y
		for s in [-1.0, 1.0]:
			m.block(troughs, Transform3D(basis, Vector3(c.x, g + 0.25, c.y) + Vector3(nave.x, 0, nave.y) * 0.55 * float(s)), Vector3(7.5, 0.5, 0.12))
		for s in [-1.0, 1.0]:
			m.block(troughs, Transform3D(basis, Vector3(c.x, g + 0.25, c.y) + Vector3(across.x, 0, across.y) * 3.7 * float(s)), Vector3(0.12, 0.5, 1.2))
		m.block(pale if r == 4 else deep, Transform3D(basis, Vector3(c.x, g + 0.21, c.y)), Vector3(7.3, 0.42, 0.98))
	await k.step()
	m.commit(troughs, PoiKit.painted(5, REED_WALL, 0.7), "Troughs")
	m.commit(deep, PoiKit.plain(Color(0.08, 0.09, 0.2), 0.5), "IndigoLiquor")
	m.commit(pale, PoiKit.plain(Color(0.42, 0.46, 0.58), 0.5), "PaleLiquor")
	k.marker("the_pale_trough", k.on_ground(nave.x * 7.2 + across.x * 9.0, nave.y * 7.2 + across.y * 9.0))
	k.touchable("PaleTrough", k.on_ground(nave.x * 5.6 + across.x * 9.0, nave.y * 5.6 + across.y * 9.0, 0.7), "Look into the pale trough",
			"core:dialogue/indigo_beds_pale", "", false)
	await dye_line(d, across * 2.0 - nave * 6.5, across * 2.0 + nave * 0.5, 5)
	await dye_line(d, across * 16.0 - nave * 5.0, across * 16.0 + nave * 2.0, 4)


# --- The Withy Beds ---------------------------------------------------------------------------------------------

## Osier-beds cut to stools in long rows, each stool a knuckle of old wood with this year's withies standing
## up out of it; bundles cut and stacked, a cutter's knife on the block; at the east end the stools trodden
## flat and the withies broken where the old bitch's pack lies up by day.
static func withy_beds(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var rowd := k.grain()
	var across := Vector2(rowd.y, -rowd.x)
	var stools := m.begin()
	var shoots := m.begin()
	var lair := across * 9.0
	for r in 6:
		for i in 9:
			var p := across * ((float(r) - 2.5) * 3.2) + rowd * ((float(i) - 4.0) * 2.4) + k.jitter(0.25)
			var g := k.on_ground(p.x, p.y).y
			m.ellipsoid(stools, Vector3(p.x, g + 0.12, p.y), Vector3(0.35, 0.3, 0.35))
			var trodden := p.distance_to(lair) < 4.5
			var count := 3 if trodden else 9
			for j in count:
				var a := TAU * float(j) / float(count) + k.rng.randf()
				var lean := 0.12 + k.rng.randf() * 0.18
				var h := k.rng.randf_range(1.6, 2.6) * (0.35 if trodden else 1.0)
				var tip := Vector3(p.x, g + 0.3, p.y) + Vector3(sin(a) * lean * h, h, cos(a) * lean * h)
				if trodden:
					tip = Vector3(p.x, g + 0.25, p.y) + Vector3(sin(a), 0.1, cos(a)) * h
				m.block(shoots, Transform3D(_along(tip - Vector3(p.x, g + 0.3, p.y)), (tip + Vector3(p.x, g + 0.3, p.y)) * 0.5), Vector3(0.03, h, 0.03))
	await k.step()
	m.commit(stools, k.surface("timber", 0.85), "Stools", true)
	m.commit(shoots, PoiKit.plain(Color(0.42, 0.3, 0.2), 0.8), "Withies", true)
	if k.far:
		return
	k.marker("the_lair", k.on_ground(lair.x, lair.y))
	# bundles cut and stacked at the west end, the knife on the block
	var bundles := m.begin()
	var stack := -across * 11.5
	for i in 5:
		var p := stack + rowd * (float(i) - 2.0) * 0.5
		var g := k.on_ground(p.x, p.y).y
		m.limb(bundles, Vector3(p.x, g + 0.18 + float(i % 2) * 0.3, p.y) - Vector3(across.x, 0, across.y) * 1.4, Vector3(p.x, g + 0.18 + float(i % 2) * 0.3, p.y) + Vector3(across.x, 0, across.y) * 1.4, 0.16)
	await k.step()
	m.commit(bundles, PoiKit.plain(Color(0.45, 0.33, 0.22), 0.85), "Bundles")
	var block := k.prop("chopping_block")
	if block != "":
		var bp := stack + rowd * 2.6
		await k.step()
		k.place(block, k.on_ground(bp.x, bp.y), 0.0, 1.0, true)
	k.marker("the_cutting", k.on_ground(stack.x + rowd.x * 3.4, stack.y + rowd.y * 3.4), true)
	var bones := m.begin()
	for i in 8:
		var q := lair + k.jitter(2.5)
		var a := k.rng.randf() * TAU
		var p := k.on_ground(q.x, q.y, 0.04)
		m.limb(bones, p, p + Vector3(sin(a), 0.02, cos(a)) * k.rng.randf_range(0.25, 0.45), 0.025)
	await k.step()
	m.commit(bones, PoiKit.plain(Color(0.78, 0.74, 0.64), 0.8), "Bones")


# --- The Eel Hurdles ----------------------------------------------------------------------------------------------

## Oulea's trappers' summer raft moored on the channel: a deck of logs on the black water with two reed huts on
## it, and out from it lines of wattle hurdles standing in the water in long vees that steer the eels into the
## traps at their points; the traps (baskets) lifted on the raft, a punt tied to it.
static func eel_hurdles(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var flow := k.water_direction(80.0)
	if flow == Vector2.ZERO:
		flow = k.grain()
	var across := Vector2(flow.y, -flow.x)
	# the Oulea road runs past the moorings: the raft and its water are laid off on the far side of it
	var away := Vector2.ZERO
	var best := -1.0
	for i in 8:
		var dir := Vector2(sin(TAU * float(i) / 8.0), cos(TAU * float(i) / 8.0))
		var rd := k.road_distance(dir * 10.0)
		if rd > best:
			best = rd
			away = dir
	var o2 := away * 8.0 if k.road_distance(Vector2.ZERO) < 18.0 else Vector2.ZERO
	var wr := clampf(k.road_distance(o2) - 3.0, 8.0, 15.0)
	var y := black_water(d, o2, wr, 2.5, "Channel")
	var o3 := Vector3(o2.x, 0.0, o2.y)
	# the raft
	var raft := m.begin()
	var rb := Basis(Vector3.UP, PoiKit.yaw_of(flow))
	for i in 12:
		var z := (float(i) - 5.5) * 0.55
		m.limb(raft, o3 + Vector3(0, y + 0.12, 0) + rb * Vector3(-4.0, 0.0, z), o3 + Vector3(0, y + 0.12, 0) + rb * Vector3(4.0, 0.0, z), 0.24)
	k.collider(Vector3(8.4, 0.4, 6.8), Transform3D(rb, o3 + Vector3(0.0, y + 0.1, 0.0)), "wood")
	await k.step()
	m.commit(raft, k.surface("timber", 0.85), "Raft", true)
	# two reed huts on the raft
	var huts := m.begin()
	var roofs := m.begin()
	for s in [-1.0, 1.0]:
		var hc := o3 + Vector3(0, y + 0.36, 0) + rb * Vector3(2.0 * float(s), 0.0, -0.8)
		m.block(huts, Transform3D(rb, hc + Vector3(0, 0.9, 0)), Vector3(2.6, 1.8, 2.4))
		for q in [-1.0, 1.0]:
			m.block(roofs, Transform3D(rb * Basis(Vector3.BACK, 0.65 * float(q)), hc + Vector3(0, 2.25, 0) + rb * Vector3(0.75 * float(q), 0, 0)), Vector3(1.9, 0.18, 2.9))
		k.collider(Vector3(2.6, 1.8, 2.4), Transform3D(rb, hc + Vector3(0, 0.9, 0)), "wood")
	await k.step()
	m.commit(huts, PoiKit.painted(5, REED_WALL, 0.7), "RaftHuts", true)
	m.commit(roofs, PoiKit.painted(5, THATCH, 0.6), "RaftRoofs", true)
	if k.far:
		return
	var dark := m.begin()
	for s in [-1.0, 1.0]:
		var hc := o3 + Vector3(0, y + 0.36, 0) + rb * Vector3(2.0 * float(s), 0.0, -0.8)
		m.block(dark, Transform3D(rb, hc + rb * Vector3(0.0, 0.8, 1.22)), Vector3(0.8, 1.5, 0.04))
	m.commit(dark, PoiKit.plain(DOOR_DARK, 0.95), "RaftDoors")
	k.marker("home", o3 + Vector3(0, y + 0.36, 0) + rb * Vector3(0.0, 0.0, 2.0), true, true, 1.5)
	k.marker("the_raft", o3 + Vector3(0, y + 0.36, 0) + rb * Vector3(-2.8, 0.0, 2.2), false, true, 1.5)
	# the hurdles: three vees of wattle out in the water, a trap at each point
	var hurd := m.begin()
	var traps: Array = []
	for v in 3:
		var tip := o2 + across * ((float(v) - 1.0) * 0.7 * wr) + flow * (wr * 0.62)
		for s in [-1.0, 1.0]:
			var mouth := tip - flow * (wr * 0.4) + across * 3.2 * float(s)
			var n := 6
			for i in n:
				var p0 := mouth.lerp(tip, float(i) / float(n))
				var p1 := mouth.lerp(tip, float(i + 1) / float(n))
				var mid := (p0 + p1) * 0.5
				m.block(hurd, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(p1 - p0)), Vector3(mid.x, y + 0.35, mid.y)), Vector3(0.1, 1.3, p0.distance_to(p1) * 1.02))
		traps.append(tip)
	await k.step()
	m.commit(hurd, PoiKit.painted(5, REED_WALL, 0.8), "Hurdles")
	var basket := k.prop("basket")
	if basket != "":
		var xfs: Array = []
		for t in traps:
			var tp: Vector2 = t
			xfs.append(PoiKit.transform_at(Vector3(tp.x, y - 0.1, tp.y), k.rng.randf() * TAU, 1.3, Vector3(PI * 0.5, 0.0, 0.0)))
		for i in 3:
			var q := o3 + Vector3(0, y + 0.36, 0) + rb * Vector3(-3.0 + float(i) * 0.7, 0.0, 2.4)
			xfs.append(Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), q))
		await k.step()
		k.scatter(basket, xfs, false, false, true)
	var boat := k.prop("rowboat")
	if boat != "":
		var bp := o3 + Vector3(0, y + 0.02, 0) + rb * Vector3(5.2, 0.0, 0.0)
		await k.step()
		k.place(boat, bp, PoiKit.yaw_of(flow), 1.0, false)
	var stones := m.begin()
	rim_stones(d, stones, o2, wr + 0.1, 34, 0.45)
	await k.step()
	m.commit(stones, k.surface("stone", 0.9), "Rim")
	await reeds(d, 6.0, 22.0, 70, [[o2, wr + 0.6]])


# --- boardwalks -------------------------------------------------------------------------------------------------

## A marsh boardwalk from `a` to `b` (local xz), its deck `lift` over the highest ground along it, poles on
## alternate sides every `every` metres each with a lantern hung from its arm (lit or not), and a rope run
## from pole-top to pole-top -- in the poles' own batch, so the rope is the poles' and not a thing hung in
## the air. Returns {deck_y, tops (Array of the poles' heads, local Vector3)}.
static func boardwalk(d: PoiDressing, a: Vector2, b: Vector2, lift: float, every := 6.0, lit := true, width := 2.4,
		node_name := "Boardwalk") -> Dictionary:
	var k := d.kit
	var m := d.masonry
	var axis := (b - a).normalized()
	var perp := Vector2(-axis.y, axis.x)
	var yaw := PoiKit.yaw_of(axis)
	var deck_y := -INF
	for i in 5:
		var q := a.lerp(b, float(i) / 4.0)
		deck_y = maxf(deck_y, k.on_ground(q.x, q.y).y)
	deck_y += lift
	var planks := m.begin()
	var posts := m.begin()
	m.plank_deck(planks, posts, a, b, width, deck_y, 3.0, false)
	var n := maxi(int(a.distance_to(b) / every), 1)
	var tops: Array = []
	var lamps: Array = []
	var last := Vector3.INF
	for i in n + 1:
		var t := float(i) / float(n)
		var side := 1.0 if i % 2 == 0 else -1.0
		var p := a.lerp(b, t) + perp * side * (width * 0.5 - 0.2)
		var top := m.post(posts, p, deck_y - k.on_ground(p.x, p.y).y + 2.6, 0.13)
		var arm := Vector3(perp.x, 0.0, perp.y) * side * 0.5
		m.block(posts, Transform3D(Basis(Vector3.UP, yaw), top + arm * 0.5 - Vector3(0.0, 0.05, 0.0)), Vector3(0.9, 0.07, 0.07))
		lamps.append(PoiKit.transform_at(top + arm - Vector3(0.0, 0.5, 0.0), yaw, 1.0))
		if lit and i % 2 == 0:
			k.light(top + arm - Vector3(0.0, 0.3, 0.0), Color(1.0, 0.78, 0.45), 1.5, 8.0)
		if last != Vector3.INF:
			var sag := (last + top) * 0.5 - Vector3(0.0, 0.3, 0.0)
			m.limb(posts, last - Vector3(0, 0.15, 0), sag, 0.018)
			m.limb(posts, sag, top - Vector3(0, 0.15, 0), 0.018)
		last = top
		tops.append(top)
	await k.step()
	m.commit(planks, k.surface("planks", 0.7), node_name, true)
	m.commit(posts, k.surface("timber", 0.6), node_name + "Poles", true)
	var lamp := k.prop("lantern_hanging")
	if lamp != "" and not k.far:
		await k.step()
		k.scatter(lamp, lamps, false, false, true)
	return {"deck_y": deck_y, "tops": tops}


# --- The Lantern Causeway -----------------------------------------------------------------------------------------

## The boardwalk of lantern poles Lissane lights each dusk, as long as the road's crossing of the wet, and at its
## Isseva end her lamplighter's hut, her ladder against the first pole, the oil-jar and the long wick-pole.
## Keeps her spots: home, the_lamp_round.
static func lantern_causeway(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var axis := k.road_direction(90.0)
	if axis == Vector2.ZERO:
		axis = k.grain()
	var perp := Vector2(-axis.y, axis.x)
	var a := -axis * 18.0
	var b := axis * 18.0
	var bw: Dictionary = await boardwalk(d, a, b, 1.45, 6.0, true)
	var deck_y := float(bw["deck_y"])
	if k.far:
		return
	var round_at := a.lerp(b, 0.35)
	k.marker("the_lamp_round", Vector3(round_at.x, deck_y + 0.1, round_at.y), true, true, 18.0)
	var hut_c := a - axis * 2.0 + perp * 6.0
	var hut: Dictionary = await stilt_house(d, hut_c, -perp, 3.2, 3.0, 1.2, "Lamplighter")
	k.marker("home", hut["inside"], true, true, 1.4)
	var timber := m.begin()
	var tops: Array = bw["tops"]
	var t0: Vector3 = tops[0]
	var lfoot := k.on_ground(t0.x - axis.x * 1.4, t0.z - axis.y * 1.4)
	for s in [-1.0, 1.0]:
		var off := Vector3(perp.x, 0, perp.y) * 0.25 * float(s)
		m.limb(timber, lfoot + off, t0 - Vector3(0, 0.6, 0) + off, 0.04)
	for i in 8:
		var t := (float(i) + 0.5) / 8.0
		var p := lfoot.lerp(t0 - Vector3(0, 0.6, 0), t)
		m.limb(timber, p - Vector3(perp.x, 0, perp.y) * 0.25, p + Vector3(perp.x, 0, perp.y) * 0.25, 0.025)
	var wp := Vector2(hut_c.x, hut_c.y) + axis * 2.4
	var wg := k.on_ground(wp.x, wp.y)
	m.limb(timber, wg, wg + Vector3(0.4, 3.4, 0.2), 0.03)
	await k.step()
	m.commit(timber, k.surface("timber", 0.75), "LadderAndWickPole")
	var jar := k.prop("jug")
	if jar != "":
		await k.step()
		k.place(jar, k.on_ground(wp.x + perp.x * 0.6, wp.y + perp.y * 0.6), 0.0, 1.4, false)


# --- The Boardwalk Gate ------------------------------------------------------------------------------------------

## Where the Westway leaves the downs and goes out onto the delta: a reedfolk gate of two tall posts and a lintel
## hung with lanterns and indigo cloth, the boardwalk going on from it over the wet, and on its planks the wet
## prints of bare feet coming out of the delta.
static func boardwalk_gate(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var axis := k.road_direction(90.0)
	if axis == Vector2.ZERO:
		axis = k.grain()
	var perp := Vector2(-axis.y, axis.x)
	var a := -axis * 6.0
	var b := axis * 20.0
	var bw: Dictionary = await boardwalk(d, a, b, 1.2, 6.5, true)
	var deck_y := float(bw["deck_y"])
	# the gate: two tall posts either side of the boardwalk's landward end and a lintel over
	var gate := m.begin()
	var tops: Array = []
	for s in [-1.0, 1.0]:
		var p := a + perp * 1.7 * float(s)
		tops.append(m.post(gate, p, deck_y - k.on_ground(p.x, p.y).y + 4.3, 0.28))
	var ta: Vector3 = tops[0]
	var tb: Vector3 = tops[1]
	m.block(gate, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(axis)), (ta + tb) * 0.5 - Vector3(0, 0.25, 0)), Vector3(4.4, 0.32, 0.32))
	await k.step()
	m.commit(gate, k.surface("timber", 0.7), "Gate", true)
	if k.far:
		return
	var lamp := k.prop("lantern_hanging")
	var lamps: Array = []
	for i in 3:
		var p := ta.lerp(tb, (float(i) + 1.0) / 4.0) - Vector3(0, 0.95, 0)
		lamps.append(PoiKit.transform_at(p, PoiKit.yaw_of(axis), 1.0))
	if lamp != "":
		await k.step()
		k.scatter(lamp, lamps, false, false, true)
	k.light((ta + tb) * 0.5 - Vector3(0, 1.3, 0), Color(1.0, 0.76, 0.42), 1.8, 10.0)
	var cloth := PoiKit.plain(INDIGO, 0.9)
	for s in [-1.0, 1.0]:
		var at := ta.lerp(tb, 0.5 + 0.38 * float(s)) - Vector3(0, 0.4, 0)
		m.sheet(at, PoiKit.yaw_of(axis), 0.5, 1.3, cloth, "GateCloth%d" % (0 if s < 0.0 else 1), 0.12, false, 1, 3)
	# the wet prints on the planks, coming out of the delta toward the gate
	var marks_st := m.begin()
	for i in 14:
		var t := 1.0 - float(i) / 13.0
		var p := a.lerp(b, t * 0.9) + perp * (0.14 if i % 2 == 0 else -0.14)
		m.block(marks_st, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(axis)), Vector3(p.x, deck_y + 0.005, p.y)), Vector3(0.11, 0.01, 0.26))
	await k.step()
	m.commit(marks_st, PoiKit.plain(Color(0.18, 0.15, 0.12), 0.2), "WetPrints")
	k.marker("the_gate", k.on_ground(a.x - axis.x * 2.0, a.y - axis.y * 2.0))
	k.touchable("Prints", Vector3(b.x, deck_y + 0.4, b.y).lerp(Vector3(a.x, deck_y + 0.4, a.y), 0.5), "Look at the prints on the planks",
			"core:dialogue/boardwalk_gate_prints", "", false)
	await reeds(d, 4.0, 14.0, 60, [[(a + b) * 0.5, 2.0]])


# --- The Long Jetty -------------------------------------------------------------------------------------------------

## The burial boardwalk running out into Lissane Mere, its posts hung with the knots of the unmourned and its
## last post hung thick with lanterns, a name on each. Keeps its spot: last_post (on the deck at the last post).
static func long_jetty(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var mere := k.water_direction(80.0)
	if mere == Vector2.ZERO:
		mere = k.grain()
	var a := -mere * 10.0
	var b := mere * 22.0
	var bw: Dictionary = await boardwalk(d, a, b, 0.9, 5.0, false, 2.0, "Jetty")
	var deck_y := float(bw["deck_y"])
	if k.far:
		return
	var tops: Array = bw["tops"]
	# the last post, taller, hung thick with lanterns, each a name
	var timber := m.begin()
	var lp := b + mere * 0.6
	var top := m.post(timber, lp, deck_y - k.on_ground(lp.x, lp.y).y + 3.6, 0.22)
	for i in 4:
		var a2 := TAU * float(i) / 4.0
		m.block(timber, Transform3D(Basis(Vector3.UP, a2), top - Vector3(0, 0.3 + float(i) * 0.25, 0) + Vector3(sin(a2), 0, cos(a2)) * 0.45), Vector3(0.07, 0.07, 0.9))
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "LastPost", true)
	var paper := m.begin()
	var cord := m.begin()
	for i in 16:
		var a2 := TAU * float(i % 4) / 4.0 + k.rng.randf_range(-0.2, 0.2)
		var hang := top - Vector3(0, 0.3 + float(i % 4) * 0.25, 0) + Vector3(sin(a2), 0, cos(a2)) * k.rng.randf_range(0.3, 0.85)
		var l := k.rng.randf_range(0.2, 0.6)
		m.block(cord, Transform3D(Basis.IDENTITY, hang - Vector3(0, l * 0.5, 0)), Vector3(0.02, l, 0.02))
		m.block(paper, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), hang - Vector3(0, l + 0.17, 0)), Vector3(0.24, 0.32, 0.24))
	await k.step()
	m.commit(cord, PoiKit.plain(RUSH, 0.95), "LanternCords")
	m.commit(paper, PoiKit.plain(Color(0.95, 0.72, 0.42), 0.6, 0.0, Color(1.0, 0.62, 0.3), 1.2), "UnmournedLanterns")
	k.light(top - Vector3(0, 1.0, 0), Color(1.0, 0.66, 0.34), 1.6, 9.0)
	var last_post := b - mere * 1.2
	k.marker("last_post", Vector3(last_post.x, deck_y + 0.05, last_post.y), false, true, 2.0)
	# knots on every post, the unmourned's
	var knots := m.begin()
	for t in tops:
		var tp: Vector3 = t
		for j in 3:
			m.block(knots, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), tp - Vector3(0, 0.6 + float(j) * 0.2, 0)), Vector3(0.18, 0.08, 0.18))
	await k.step()
	m.commit(knots, PoiKit.plain(INDIGO, 0.9), "PostKnots")
	k.touchable("LastPost", Vector3(lp.x, deck_y + 1.3, lp.y) - Vector3(mere.x, 0, mere.y) * 0.6, "Read the names on the lanterns",
			"core:dialogue/long_jetty_names", "", false)


# --- The Peat Hags --------------------------------------------------------------------------------------------

## The peat-cutters' camp on a drying island: the cutting-bank stepped down where the turves come out, the turves
## stacked to dry in rows like loaves, the cutters' reed hut and fire, the finds-board where what the peat gives up
## is set out for the buyers. Keeps Deo and Lia Oul's spots: home, the_cuttings, the_fire, the_stacks.
static func peat_hags(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.grain()
	var side := Vector2(face.y, -face.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(face))
	# the cutting: the bank's face stepped down in three cuts, the floor wet
	var peat := PoiKit.painted(5, {"base": "#2b2118", "accent": "#1f1811", "grout": "#120d08", "unit": 0.3}, 0.6)
	var bank := m.begin()
	var cut_c := face * 9.0
	var g := k.on_ground(cut_c.x, cut_c.y).y
	for i in 3:
		var off := face * (float(i) * 1.4)
		var c := cut_c + off
		# the cut face steps down toward the water: each step's top lower, its face the black peat
		var top_y := g + 0.45 - float(i) * 0.2
		m.block(bank, Transform3D(basis, Vector3(c.x, (top_y + g - 0.3) * 0.5, c.y)), Vector3(12.0, top_y - g + 0.3, 1.4))
		k.collider(Vector3(12.0, top_y - g + 0.3, 1.4), Transform3D(basis, Vector3(c.x, (top_y + g - 0.3) * 0.5, c.y)), "dirt")
	await k.step()
	m.commit(bank, peat, "CuttingBank", true)
	if k.far:
		return
	var wet := cut_c + face * 4.6
	var water := m.begin()
	m.block(water, Transform3D(basis, k.on_ground(wet.x, wet.y, 0.04)), Vector3(11.0, 0.02, 2.4))
	await k.step()
	m.commit(water, k.still_water(-0.8, Color(0.8, 0.75, 0.65), 0.9), "CuttingWater")
	k.marker("the_cuttings", k.on_ground(cut_c.x - face.x * 1.2, cut_c.y - face.y * 1.2), true)
	# the stacks: turves in rows of little pyramids, drying
	var turves := m.begin()
	var stacks_c := -face * 2.0 + side * 6.5
	for r in 3:
		for i in 6:
			var c := stacks_c + side * (float(i) - 2.5) * 1.5 + face * (float(r) - 1.0) * 1.8
			var sg := k.on_ground(c.x, c.y).y
			for layer in 3:
				var n := 3 - layer
				for j in n:
					var p := c + side * ((float(j) - float(n - 1) * 0.5) * 0.36)
					m.block(turves, Transform3D(basis * Basis(Vector3.UP, k.rng.randf_range(-0.1, 0.1)), Vector3(p.x, sg + 0.1 + float(layer) * 0.19, p.y)), Vector3(0.32, 0.18, 0.5))
	await k.step()
	m.commit(turves, peat, "Turves")
	k.marker("the_stacks", k.on_ground(stacks_c.x - face.x * 3.2, stacks_c.y - face.y * 3.2), true)
	# the hut and the fire
	var hut: Dictionary = await stilt_house(d, -face * 6.0 - side * 5.0, face, 3.6, 3.2, 0.6, "Cutters")
	k.marker("home", hut["inside"], true, true, 1.4)
	var fire_at := -face * 1.5 - side * 1.5
	var fire := k.prop("campfire")
	if fire != "":
		await k.step()
		k.place(fire, k.on_ground(fire_at.x, fire_at.y), 0.0, 1.0, false)
		k.light(k.on_ground(fire_at.x, fire_at.y, 0.6), Color(1.0, 0.6, 0.3), 1.8, 9.0)
	k.marker("the_fire", k.on_ground(fire_at.x + side.x * 1.6, fire_at.y + side.y * 1.6), true)
	# the finds-board: a plank on two posts, what the peat gave up laid out on it
	var timber := m.begin()
	var fb := -face * 1.0 + side * 2.5
	for s in [-1.0, 1.0]:
		m.post(timber, fb + face * 0.9 * float(s), 0.85, 0.1)
	var fbg := k.on_ground(fb.x, fb.y).y
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)), Vector3(fb.x, fbg + 0.88, fb.y)), Vector3(0.5, 0.06, 2.2))
	await k.step()
	m.commit(timber, k.surface("timber", 0.75), "FindsBoard")
	var finds := m.begin()
	for i in 6:
		var p := fb + face * ((float(i) - 2.5) * 0.32)
		m.ellipsoid(finds, Vector3(p.x, fbg + 0.96, p.y), Vector3(0.08, 0.05, 0.11) * k.rng.randf_range(0.8, 1.4), Basis(Vector3.UP, k.rng.randf() * TAU))
	await k.step()
	m.commit(finds, PoiKit.plain(Color(0.35, 0.26, 0.18), 0.6), "Finds")
	var tools := m.begin()
	for i in 2:
		var p := k.on_ground(cut_c.x + side.x * (3.0 + float(i)), cut_c.y + side.y * (3.0 + float(i)) - 0.0)
		m.limb(tools, p, p + Vector3(face.x * 0.3, 1.5, face.y * 0.3), 0.03)
		m.block(tools, Transform3D(basis, p + Vector3(0, 0.12, 0)), Vector3(0.18, 0.3, 0.03))
	await k.step()
	m.commit(tools, k.surface("timber", 0.7), "Slanes")


# --- the small ruins by the ways -------------------------------------------------------------------------------

## The roofless stone byre of a farm the fen came up over: its long walls broken down to the knee, one gable
## standing whole out of the reeds, a manger along the back wall, reeds grown up inside.
static func drowned_byre(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.grain()
	var side := Vector2(face.y, -face.x)
	var stone := m.begin()
	var L := 9.0
	var W := 5.0
	var c0 := -side * (L * 0.5) - face * (W * 0.5)
	var c1 := side * (L * 0.5) - face * (W * 0.5)
	var c2 := side * (L * 0.5) + face * (W * 0.5)
	var c3 := -side * (L * 0.5) + face * (W * 0.5)
	m.wall(stone, c0, c1, 1.4, 0.7)
	m.wall(stone, c3, c2, 1.0, 0.8)
	m.wall(stone, c1, c2, 1.2, 0.5)
	# the gable: whole, its peak standing up out of the reeds
	var g := k.on_ground(c3.x, c3.y).y
	var gb := Basis(Vector3.UP, PoiKit.yaw_of(side))
	for i in 7:
		var t := float(i) / 7.0
		var w := W * (1.0 - t * 0.85)
		var mid := (c0 + c3) * 0.5
		var xf := Transform3D(gb, Vector3(mid.x, g + 0.3 + t * 5.0, mid.y))
		m.block(stone, xf, Vector3(0.6, 5.0 / 7.0 + 0.02, w))
	k.collider(Vector3(0.6, 3.5, W), Transform3D(gb, Vector3(((c0 + c3) * 0.5).x, g + 1.75, ((c0 + c3) * 0.5).y)), "stone")
	await k.step()
	m.commit(stone, k.surface("stone", 0.85), "Byre", true)
	if k.far:
		return
	var manger := m.begin()
	var mc := -face * (W * 0.5 - 0.6)
	var mg := k.on_ground(mc.x, mc.y).y
	m.block(manger, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), Vector3(mc.x, mg + 0.45, mc.y)), Vector3(L * 0.7, 0.12, 0.7))
	await k.step()
	m.commit(manger, k.surface("timber", 0.9), "Manger")
	var bones := m.begin()
	for i in 5:
		var q := side * k.rng.randf_range(-3.0, 3.0) + face * k.rng.randf_range(-1.5, 1.5)
		var p := k.on_ground(q.x, q.y, 0.05)
		var a := k.rng.randf() * TAU
		m.limb(bones, p, p + Vector3(sin(a), 0.02, cos(a)) * 0.6, 0.04)
	await k.step()
	m.commit(bones, PoiKit.plain(Color(0.78, 0.74, 0.64), 0.8), "Bones")
	k.marker("the_byre", k.on_ground(face.x * 4.0, face.y * 4.0))
	await reeds(d, 1.0, 12.0, 60, [[(c0 + c3) * 0.5, 1.0]])


## A Moreva family's stilt-house whose stilts rotted under it: the house come down whole onto the peat and
## settled askew, its walls standing and its roof slid half off; the stumps of its stilts standing round it.
static func settled_house(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.grain()
	var side := Vector2(face.y, -face.x)
	var g := k.on_ground(0.0, 0.0).y
	var tilt := Basis(Vector3.UP, PoiKit.yaw_of(face)) * Basis(Vector3.BACK, 0.09) * Basis(Vector3.RIGHT, -0.05)
	var walls := m.begin()
	var roof := m.begin()
	var dark := m.begin()
	var w := 4.2
	var dp := 3.6
	var o := Vector3(0.0, g - 0.25, 0.0)
	for s in [-1.0, 1.0]:
		m.block(walls, Transform3D(tilt, o + tilt * Vector3(float(s) * w * 0.5, 1.0, 0.0)), Vector3(0.12, 2.0, dp))
		m.block(walls, Transform3D(tilt, o + tilt * Vector3(0.0, 1.0, float(s) * dp * 0.5)), Vector3(w, 2.0, 0.12))
	m.block(dark, Transform3D(tilt, o + tilt * Vector3(0.0, 0.85, dp * 0.5 + 0.03)), Vector3(0.9, 1.6, 0.04))
	k.collider(Vector3(w, 2.0, dp), Transform3D(tilt, o + tilt * Vector3(0, 1.0, 0)), "wood")
	# the roof slid half off to one side, its ridge resting on the wall-top and its eave in the mud
	var rb := tilt * Basis(Vector3.BACK, 0.55)
	m.block(roof, Transform3D(rb, o + tilt * Vector3(w * 0.75, 1.6, 0.0)), Vector3(3.4, 0.22, dp + 0.8))
	m.block(roof, Transform3D(tilt * Basis(Vector3.BACK, -0.75), o + tilt * Vector3(-w * 0.2, 2.6, 0.0)), Vector3(2.8, 0.22, dp + 0.8))
	await k.step()
	m.commit(walls, PoiKit.painted(5, REED_WALL, 0.75), "SettledWalls", true)
	m.commit(roof, PoiKit.painted(5, THATCH, 0.7), "SlidRoof", true)
	if k.far:
		return
	m.commit(dark, PoiKit.plain(DOOR_DARK, 0.95), "Door")
	var stumps := m.begin()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 0.0, 1.0]:
			var p := side * (w * 0.5 + 0.6) * float(sx) + face * (dp * 0.5) * float(sz)
			var h := k.rng.randf_range(0.3, 1.1)
			m.post(stumps, p, h, 0.2, Vector3(k.rng.randf_range(-0.15, 0.15), 0.0, k.rng.randf_range(-0.15, 0.15)))
	await k.step()
	m.commit(stumps, PoiKit.plain(Color(0.1, 0.09, 0.08), 0.85), "RottedStilts")
	k.marker("the_door", k.on_ground(face.x * (dp * 0.5 + 1.2), face.y * (dp * 0.5 + 1.2)))
	await reeds(d, 5.0, 12.0, 50, [[face * 3.5, 1.6]])


## A ring of broken stilts by the causeway where a platform stood, the water round them black and still: the
## stilts snapped at every height, the platform's last bearer lying across two of them.
static func broken_stilts(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var y := black_water(d, Vector2.ZERO, 7.0, 3.0, "BlackStill")
	var posts := m.begin()
	var tops: Array = []
	for i in 10:
		var a := TAU * float(i) / 10.0
		var p := Vector2(sin(a), cos(a)) * 4.4
		var h := k.rng.randf_range(0.6, 3.2)
		tops.append(m.post(posts, p, h + (y - k.on_ground(p.x, p.y).y), 0.22, Vector3(k.rng.randf_range(-0.08, 0.08), 0.0, k.rng.randf_range(-0.08, 0.08))))
	var t0: Vector3 = tops[2]
	var t1: Vector3 = tops[3]
	m.limb(posts, t0 + Vector3(0, 0.1, 0), t1 + Vector3(0, 0.1, 0), 0.14)
	await k.step()
	m.commit(posts, PoiKit.plain(Color(0.08, 0.075, 0.07), 0.85), "BrokenStilts", true)
	if k.far:
		return
	k.marker("the_stilts", Vector3(0.0, y, 0.0))
	var stones := m.begin()
	rim_stones(d, stones, Vector2.ZERO, 7.1, 18, 0.4)
	await k.step()
	m.commit(stones, k.surface("stone", 0.9), "Rim")
	await reeds(d, 7.4, 12.0, 40, [])
