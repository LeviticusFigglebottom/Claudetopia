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
		node_name := "StiltHouse") -> Dictionary:
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
			m.block(posts, Transform3D(Basis(Vector3.UP, yaw + 0.3 * float(sx)), Vector3(p.x, g - 0.4 + h * 0.5, p.y)), Vector3(0.2, h, 0.2))
			k.collider(Vector3(0.2, h, 0.2), Transform3D(basis, Vector3(p.x, g - 0.4 + h * 0.5, p.y)), "wood")
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
	var n := clampi(int(ceil(rise_total / 0.28)), 2, 9)
	var tread := 0.34
	var start := edge + face * (tread * float(n))
	m.steps(planks, start, -face, foot_g, n, rise_total / float(n), tread, 1.1, 0.25)
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
	var stage_y := maxf(k.on_ground(stage_a.x, stage_a.y).y, k.on_ground(stage_b.x, stage_b.y).y) + 0.45
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
	m.mound(k.on_ground(0.0, 0.0, -0.4), 10.5, 1.2, turf, "Hummock", true, 2.2, 6, 20, true, 0.05)
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
			var gy := k.on_ground(p.x, p.y).y + _hummock_lift(p, 10.5, 1.2)
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
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y, _hummock_lift(q, 10.5, 1.2) - 0.05), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.2)))
		await k.step()
		k.scatter(sedge, xfs, false, false, false)
	await reeds(d, 11.0, 18.0, 55, [])


static func _hummock_lift(p: Vector2, r: float, h: float) -> float:
	var f := clampf(p.length() / r, 0.0, 1.0)
	return h * pow(maxf(1.0 - f * f, 0.0), 2.2 * 0.5) - 0.4


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
	m.commit(old, PoiKit.plain(Color(0.62, 0.6, 0.57), 0.95), "GreyRows", true)
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
