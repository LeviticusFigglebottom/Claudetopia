extends RefCounted
## Hearthvale's own place builders (docs/WORLD_LIFE.md). A POI def with `"builder": "<name>"` is built
## by the static function of that name here, in place of its kind's builder. Only the Hearthvale
## region's author edits this file, so six regions can build at once without meeting.
##
##   static func drovers_hall(d: PoiDressing) -> void:
##       await PoiDressing.kind_builders().LAND.farmstead(d)    # its kind's, then more
##       var k := d.kit                                          # PoiKit: on_ground, prop, masonry ...
##
## The kind stays the def's `kind` (what the tests, the map and the audit call it); a builder named
## here that is missing is said in the log and the place is built as its kind.
##
## World life, phase 1 (2026-09-29): the places the empty downs were given, and the few old ones that
## wanted something to touch. Each is the chalk country's own: flint and chalk-cob, hurdles, thatch,
## bells, trestles, the Vale's things set out as the place's sentence says. Masonry is merged a
## material at a time and repeated props go in one MultiMesh, so a place stays a few dozen draws.

const IRON := Color(0.16, 0.15, 0.14)
const CHALK := Color(0.9, 0.88, 0.82)
const SOOT := Color(0.07, 0.06, 0.055)
const TURF := Color(0.36, 0.42, 0.22)
const SOIL := Color(0.36, 0.29, 0.2)
const WHITEWASH := Color(0.93, 0.92, 0.88)


# --- shared hands ---------------------------------------------------------------------------------

static func _builders() -> GDScript:
	return PoiDressing.kind_builders()


## The unit direction the place faces: toward the nearest road where one is near, else downhill,
## else along the grain.
static func _facing(k: PoiKit) -> Vector2:
	var f := k.road_direction(80.0)
	if f == Vector2.ZERO:
		f = k.downhill()
	if f == Vector2.ZERO:
		f = k.grain()
	return f.normalized() if f != Vector2.ZERO else Vector2(0.0, 1.0)


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


## A cart wheel standing upright at `at` (local, on the ground), its axle along `axis`: a rim of
## twelve felloes and six spokes about a hub, into `st`.
static func _wheel(m: PoiMasonry, st: SurfaceTool, at: Vector3, axis: Vector2, r := 0.62, sunk := 0.18) -> void:
	var yaw := PoiKit.yaw_of(axis)
	var face := Basis(Vector3.UP, yaw)
	var c := at + Vector3(0.0, r - sunk, 0.0)
	for i in 12:
		var a := TAU * (float(i) + 0.5) / 12.0
		var p := c + face * Vector3(sin(a) * r, cos(a) * r, 0.0)
		m.block(st, Transform3D(face * Basis(Vector3.BACK, -a), p), Vector3(r * 0.56, 0.09, 0.08))
	for i in 6:
		var a := TAU * float(i) / 6.0
		var p := c + face * Vector3(sin(a) * r * 0.5, cos(a) * r * 0.5, 0.0)
		m.block(st, Transform3D(face * Basis(Vector3.BACK, -a), p), Vector3(0.05, r, 0.05))
	m.rod(st, Transform3D(face * Basis(Vector3.RIGHT, PI * 0.5), c), 0.1, 0.22)


## Crows about a place, sat on the perches it stood up.
static func _crows(d: PoiDressing, perches: Array[Vector3], centre: Vector3, count: int) -> void:
	if d.kit.far or perches.is_empty():
		return
	var crows := Crows.new()
	crows.name = "Crows"
	crows.radius = 10.0
	crows.height = 10.0
	d.add_child(crows)
	# every bird on a perch: one left wheeling is a piece in the air to the seat audit
	crows.setup(perches, centre, mini(count, perches.size()), d.kit.rng.randi())


## Many of one prop, in one MultiMesh: `spots` are [Vector2 local xz, yaw] pairs.
static func _row(k: PoiKit, kind: String, spots: Array, collide := true, scale := 1.0) -> void:
	var path := k.prop(kind, 0)
	if path == "" or spots.is_empty():
		return
	var xfs: Array = []
	for s in spots:
		var p: Vector2 = s[0]
		xfs.append(PoiKit.transform_at(k.on_ground(p.x, p.y), float(s[1]), scale))
	await k.step()
	if k.scatter(path, xfs, collide) == null and not k.far:
		# an asset of several meshes has no one mesh for a MultiMesh: stood one by one instead
		for xf_v in xfs:
			var xf: Transform3D = xf_v
			k.place(path, xf.origin, xf.basis.get_euler().y, scale, collide)


# --- the Lime Bay Kilns -----------------------------------------------------------------------------

## A chalk cut (the quarry's own) with two squat round kilns of flint at its foot, each with a
## draw-arch glowing low and smoke going up from its crown, white lime heaped by them, the south cart
## loaded and standing with its shafts on the ground, and the kiln-store to open.
static func lime_kilns(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.downhill()
	if face == Vector2.ZERO:
		face = k.grain()
	var side := Vector2(face.y, -face.x)
	# the bank the kilns are cut into: a long turfed rise behind them, the chalk showing raw where
	# it was dug back, so the charge can be tipped in from the top
	var turf := PoiKit.plain(TURF.darkened(0.1), 0.95)
	for s in [-1.0, 0.0, 1.0]:
		var b := face * 4.0 + side * float(s) * 7.0
		m.mound(k.on_ground(b.x, b.y, -0.4), 6.5, 3.6, turf, "KilnBank%d" % int(s + 1.0), true, 1.4, 7, 20, true, 0.1)
	var scar := m.begin()
	for s in [-1.0, 1.0]:
		var c := face * 7.0 + side * float(s) * 6.5
		var g := k.on_ground(c.x, c.y)
		m.block(scar, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)) * Basis(Vector3.RIGHT, -0.5), g + Vector3(0.0, 1.4, 0.0) - Vector3(face.x, 0.0, face.y) * 1.2), Vector3(5.6, 3.2, 0.3))
	await k.step()
	m.commit(scar, PoiKit.painted(0, {"base": "#cfc8b4", "accent": "#a89f88", "grout": "#7d7564", "unit": 0.7}, 0.8, 0.8), "ChalkFace")
	var flint := m.begin()
	var dark := m.begin()
	var glow := m.begin()
	var kilns: Array[Vector2] = [face * 9.0 - side * 6.5, face * 9.0 + side * 6.5]
	for c in kilns:
		var g := k.on_ground(c.x, c.y)
		var basis := Basis(Vector3.UP, PoiKit.yaw_of(face))
		m.drum(flint, Transform3D(Basis.IDENTITY, g + Vector3(0.0, -0.3, 0.0)), 2.3, 3.9, 0.0, NAN, false)
		k.collider(Vector3(4.2, 3.6, 4.2), Transform3D(Basis.IDENTITY, g + Vector3(0.0, 1.5, 0.0)), "stone")
		# the draw-arch on the face side: a dark mouth with the fire low in it
		var mouth := g + basis * Vector3(0.0, 0.75, 2.2)
		m.block(dark, Transform3D(basis, mouth), Vector3(1.1, 1.5, 0.3))
		m.block(glow, Transform3D(basis, mouth + basis * Vector3(0.0, -0.45, -0.05)), Vector3(0.8, 0.35, 0.28))
		# the crown's lip, a course proud of the drum
		m.block(dark, Transform3D(basis, g + Vector3(0.0, 3.62, 0.0)), Vector3(3.2, 0.12, 3.2))
		k.puffs(g + Vector3(0.0, 4.0, 0.0), Vector3(0.6, 0.2, 0.6), 4.5, 12, Color(0.86, 0.85, 0.82, 0.35), 2.0, 6.0)
		k.light(mouth + basis * Vector3(0.0, 0.0, 0.8), Color(1.0, 0.55, 0.25), 1.6, 7.0)
		await k.step()
	m.commit(flint, PoiKit.painted(0, {"base": "#bdb8ac", "accent": "#5e5a55", "grout": "#3b3935", "unit": 0.22}, 0.8, 0.8), "Kilns")
	m.commit(dark, PoiKit.plain(SOOT, 0.95), "DrawArches")
	m.commit(glow, PoiKit.plain(Color(0.4, 0.12, 0.03), 0.8, 0.0, Color(1.0, 0.42, 0.12), 2.2), "KilnFire")
	# lime heaped between the kilns, and the sacks of it
	var lime := PoiKit.plain(CHALK.darkened(0.12), 0.95)
	for i in 3:
		var p := face * (10.5 + float(i) * 1.6) + side * (float(i) - 1.0) * 1.9
		m.mound(k.on_ground(p.x, p.y, -0.1), 1.3 - float(i) * 0.2, 0.8, lime, "LimeHeap%d" % i, false)
	await k.step()
	var sacks: Array = []
	for i in 6:
		var p := face * 12.5 - side * (2.5 + float(i % 3) * 0.7) + face * float(int(i / 3.0)) * 0.7
		sacks.append([p, k.rng.randf() * TAU])
	await _row(k, "sack", sacks, true)
	# the south cart, loaded, its shafts down
	var cart_at := face * 14.5 + side * 4.0
	var cart := k.prop("cart")
	if cart != "":
		await k.step()
		k.place(cart, k.on_ground(cart_at.x, cart_at.y), PoiKit.yaw_of(side) + 0.15, 1.0, true)
	k.marker("the_near_kiln", k.on_ground(kilns[0].x + face.x * 4.0 + side.x * 1.5, kilns[0].y + face.y * 4.0 + side.y * 1.5), true)
	k.marker("the_south_cart", k.on_ground(cart_at.x - side.x * 2.4 + face.x * 1.0, cart_at.y - side.y * 2.4 + face.y * 1.0), true)
	var store := face * 12.0 + side * 1.2
	_container(d, "kiln_store", k.on_ground(store.x, store.y), PoiKit.yaw_of(-face), "core:loot/common_chest", "Kiln Store", "crate")


# --- the Hound's Swallet ---------------------------------------------------------------------------

## The delve (the site's own crag, throat and door, and the cord's post), and about it what makes a
## swallow-hole on a chalk down read from the road: hawthorns grown out of the lip, chalk boulders
## split out of the ground round the throat, the turf worn bare to the earth where the wolves go in.
static func hounds_swallet(d: PoiDressing) -> void:
	await _builders().SITES.build(d)
	var k := d.kit
	var m := d.masonry
	var mouth := d.find_child("the_mouth", true, false) as Node3D
	var at := Vector2(mouth.position.x, mouth.position.z) if mouth != null else Vector2.ZERO
	var out := at.normalized() if at.length() > 0.5 else Vector2(0.0, -1.0)
	var side := Vector2(out.y, -out.x)
	var thorn := k.tree("hawthorn_veteran")
	if thorn == "":
		thorn = k.tree("hawthorn")
	if thorn != "":
		for p in [-out * 6.0 + side * 4.0, -out * 7.5 - side * 3.5, out * 3.0 + side * 9.5]:
			var q: Vector2 = p
			await k.step()
			k.place(thorn, k.on_ground(q.x, q.y), k.rng.randf() * TAU, k.rng.randf_range(0.9, 1.2), true, Vector3.ZERO, true)
	var yew := k.tree("yew")
	if yew != "":
		var q := -out * 11.0 - side * 8.0
		await k.step()
		k.place(yew, k.on_ground(q.x, q.y), k.rng.randf() * TAU, 1.0, true, Vector3.ZERO, true)
	# the wolves' way in: turf worn to the chalky earth in a fan from the throat
	var worn := m.begin()
	for i in 7:
		var q := at + out * (2.0 + float(i) * 1.4) + side * k.rng.randf_range(-0.8, 0.8)
		m.block(worn, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(out) + k.rng.randf_range(-0.3, 0.3)), k.on_ground(q.x, q.y, 0.02)),
				Vector3(2.4 + float(i) * 0.25, 0.03, 1.6))
	await k.step()
	m.commit(worn, PoiKit.plain(SOIL.lerp(CHALK, 0.25), 0.98), "WolfRun")
	await _builders().LAND._grass(d, "cow_parsley", -out * 4.0, 7.0, 18)
	_part_props(d)


# --- the Brow Long Table ----------------------------------------------------------------------------

## A hundred paces of trestles end to end along the crest, benches down both sides, the head's
## hawthorn with its handbell, and at the foot a mound of turf with the handles of buried bells
## standing up out of it and one empty hole. The crows sit the table.
static func long_table(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var along := k.grain()
	if along == Vector2.ZERO:
		along = Vector2(1.0, 0.0)
	var across := Vector2(along.y, -along.x)
	var yaw := PoiKit.yaw_of(across)
	var n := 14
	var step_m := 2.35
	var half := float(n - 1) * step_m * 0.5
	var tables: Array = []
	var benches: Array = []
	for i in n:
		var p := along * (float(i) * step_m - half)
		tables.append([p, yaw])
		benches.append([p + across * 1.15, yaw])
		benches.append([p - across * 1.15, yaw + PI])
	await _row(k, "table_trestle", tables, true)
	await _row(k, "bench", benches, false)
	# what is on the table: a few plates and mugs left from the last sitting
	var plates: Array = []
	for i in range(0, n, 3):
		var p := along * (float(i) * step_m - half)
		plates.append([p + across * 0.35, k.rng.randf() * TAU])
	var table_top := 0.78
	var plate_path := k.prop("plate_stack", 0)
	if plate_path != "" and not k.far:
		var xfs: Array = []
		for s in plates:
			var q: Vector2 = s[0]
			xfs.append(PoiKit.transform_at(k.on_ground(q.x, q.y, table_top), float(s[1])))
		await k.step()
		k.scatter(plate_path, xfs, false)
	# the head: a hawthorn and the Table-Warden's post with its handbell
	var head := along * (half + 4.0)
	var thorn := k.tree("hawthorn")
	if thorn != "":
		await k.step()
		k.place(thorn, k.on_ground(head.x + across.x * 2.0, head.y + across.y * 2.0), k.rng.randf() * TAU, 1.0, true)
	var timber := m.begin()
	var top := m.post(timber, head - across * 1.2, 1.9, 0.14)
	m.block(timber, Transform3D(Basis(Vector3.UP, yaw), top + Vector3(0.0, -0.05, 0.0)), Vector3(0.7, 0.1, 0.1))
	var bell := k.prop("bell_small")
	if bell != "":
		k.place(bell, top + Vector3(0.0, -0.45, 0.0) + Vector3(across.x, 0.0, across.y) * 0.25, yaw, 0.8, false)
	k.marker("the_table_head", k.on_ground(head.x - along.x * 2.0, head.y - along.y * 2.0), true)
	# the foot: the turf mound, the bells' handles out of it, and the hole
	var foot := -along * (half + 4.5)
	var fg := k.on_ground(foot.x, foot.y)
	m.mound(fg + Vector3(0.0, -0.25, 0.0), 2.2, 0.8, PoiKit.plain(TURF, 0.95), "BellMound", false, 1.5, 7, 20, false, 0.12)
	var bronze := m.begin()
	for i in 3:
		var p := foot + across * (float(i) - 1.5) * 0.9 + along * 0.3
		var g := k.on_ground(p.x, p.y)
		m.rod(bronze, Transform3D(Basis.IDENTITY, g + Vector3(0.0, 0.45, 0.0)), 0.035, 0.5)
		m.rod(bronze, Transform3D(Basis(Vector3.BACK, PI * 0.5), g + Vector3(0.0, 0.7, 0.0)), 0.05, 0.16)
	var hole := foot + across * 1.2 + along * 0.3
	var hole_g := k.on_ground(hole.x, hole.y)
	var pit := m.begin()
	m.block(pit, Transform3D(Basis.IDENTITY, hole_g + Vector3(0.0, 0.52, 0.0)), Vector3(0.55, 0.06, 0.55))
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "HeadPost")
	m.commit(bronze, PoiKit.plain(Color(0.33, 0.42, 0.33), 0.5, 0.6), "BellHandles")
	m.commit(pit, PoiKit.plain(SOIL.darkened(0.4), 0.95), "EmptyHole")
	k.touchable("TheBellsAtTheFoot", fg + Vector3(0.0, 0.8, 0.0), "Look at the bells at the table's foot", "core:dialogue/long_table_bells", "", false)
	var perches: Array[Vector3] = []
	for i in [1, 5, 9, 12]:
		var p := along * (float(i) * step_m - half)
		perches.append(k.on_ground(p.x, p.y, 0.82))
	_crows(d, perches, k.on_ground(0.0, 0.0, 3.0), 5)
	await _builders().LAND._grass(d, "grass_clump", Vector2.ZERO, 16.0, 28)


# --- the Bram Down Wheelhouse -----------------------------------------------------------------------

## A shepherd's hut on four iron wheels: a plank body under a curved roof of two pitches, a step to
## its door with the tar-pot on it, a ring of wattle hurdles for the flock, and the lantern on a crook.
static func wheelhouse(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(face.y, -face.x)
	var yaw := PoiKit.yaw_of(face)
	var basis := Basis(Vector3.UP, yaw)
	var c := Vector2.ZERO
	var low := INF
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := c + side * 1.9 * float(sx) + face * 1.2 * float(sz)
			low = minf(low, k.on_ground(p.x, p.y).y)
	var floor_y := low + 0.75
	var body := m.begin()
	var roof := m.begin()
	var iron := m.begin()
	m.block(body, Transform3D(basis, Vector3(c.x, floor_y + 1.0, c.y)), Vector3(4.0, 2.0, 2.3))
	for s in [-1.0, 1.0]:
		m.block(roof, Transform3D(basis * Basis(Vector3.RIGHT, float(s) * 0.42), Vector3(c.x, floor_y + 2.3, c.y) + basis * Vector3(0.0, 0.0, float(s) * 0.62)),
				Vector3(4.3, 0.08, 1.45))
	# the door and its step, on the face side
	var door := c + face * 1.2 + side * 0.9
	m.block(iron, Transform3D(basis, Vector3(door.x, floor_y + 0.9, door.y) + Vector3(face.x, 0.0, face.y) * 0.02), Vector3(0.8, 1.7, 0.06))
	var step_at := door + face * 0.55
	m.block(body, Transform3D(basis, k.on_ground(step_at.x, step_at.y, 0.18)), Vector3(0.9, 0.36, 0.5))
	# the wheels, iron-shod, one at each corner
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := c + side * 1.35 * float(sx) + face * 1.2 * float(sz)
			_wheel(m, iron, k.on_ground(w.x, w.y), face, 0.45, 0.06)
	k.collider(Vector3(4.0, 2.6, 2.4), Transform3D(basis, Vector3(c.x, floor_y + 1.0, c.y)), "wood")
	await k.step()
	m.commit(body, k.surface("planks", 0.7), "WheelhouseBody")
	m.commit(roof, PoiKit.plain(Color(0.3, 0.32, 0.3), 0.6, 0.4), "WheelhouseRoof")
	m.commit(iron, PoiKit.plain(IRON, 0.7, 0.4), "WheelhouseIron")
	var pot := k.prop("cooking_pot")
	if pot != "":
		k.place(pot, k.on_ground(step_at.x + side.x * 0.8, step_at.y + side.y * 0.8), yaw, 0.8, true)
	k.marker("the_wheelhouse_step", k.on_ground(step_at.x + face.x * 0.9, step_at.y + face.y * 0.9), true)
	# the hurdles: an open ring on the Hush side
	var fold_c := -face * 6.5
	var wattle := m.begin()
	for i in 14:
		var a0 := TAU * float(i) / 16.0
		var a1 := TAU * float(i + 1) / 16.0
		var p0 := fold_c + Vector2(sin(a0), cos(a0)) * 4.6
		var p1 := fold_c + Vector2(sin(a1), cos(a1)) * 4.6
		var g0 := k.on_ground(p0.x, p0.y)
		var g1 := k.on_ground(p1.x, p1.y)
		var hb := Basis(Vector3.UP, atan2(p1.x - p0.x, p1.y - p0.y))
		m.block(wattle, Transform3D(hb, (g0 + g1) * 0.5 + Vector3(0.0, 0.55, 0.0)), Vector3(0.08, 1.0, p0.distance_to(p1)))
		m.post(wattle, p0, 1.15, 0.08)
		k.collider(Vector3(0.1, 1.1, p0.distance_to(p1)), Transform3D(hb, (g0 + g1) * 0.5 + Vector3(0.0, 0.55, 0.0)), "wood")
	await k.step()
	m.commit(wattle, PoiKit.plain(Color(0.45, 0.36, 0.22), 0.95), "Hurdles")
	var chest_at := c - face * 1.9 - side * 2.4
	_container(d, "enids_chest", k.on_ground(chest_at.x, chest_at.y), yaw, "core:loot/pockets_common", "Enid's Chest", "chest")
	var crook := face * 2.4 - side * 2.2
	var timber := m.begin()
	var top := m.post(timber, crook, 2.1, 0.07, Vector3(0.0, 0.0, 0.08))
	m.commit(timber, k.surface("timber", 0.6), "Crook")
	var lamp := k.prop("lantern_hand")
	if lamp != "":
		k.place(lamp, top + Vector3(0.12, -0.35, 0.0), 0.0, 1.0, false)
	await _builders().LAND._grass(d, "grass_clump", fold_c, 5.0, 14)


# --- the Southcote Lynchets -------------------------------------------------------------------------

## Old field terraces stepped down toward the Hush: three long lips each faced with flint and topped
## by a hedge, the strips between them freshly turned, and at each hedge line the Southcotes' graves
## with the tools they are known by.
static func lynchets(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var down := k.downhill()
	if down == Vector2.ZERO:
		down = k.grain()
	var across := Vector2(down.y, -down.x)
	var lips := m.begin()
	var furrows := m.begin()
	var hedges: Array = []
	var stones: Array = []
	var tools: Array = []
	for t in 3:
		var off := (float(t) - 1.0) * 8.5
		var length := 30.0 - absf(float(t) - 1.0) * 5.0
		var segs := 8
		for s in segs:
			var u := (float(s) + 0.5) / float(segs) - 0.5
			var p := down * off + across * u * length
			var g := k.on_ground(p.x, p.y)
			var basis := Basis(Vector3.UP, PoiKit.yaw_of(down))
			m.block(lips, Transform3D(basis, g + Vector3(0.0, 0.25, 0.0)), Vector3(length / float(segs) + 0.1, 0.9, 0.9))
			if s % 2 == 0:
				hedges.append([p - down * 0.2, PoiKit.yaw_of(across)])
			# the furrows below the lip: strips of turned soil down the slope
			for f in 4:
				var q := p + down * (1.6 + float(f) * 1.3)
				m.block(furrows, Transform3D(basis, k.on_ground(q.x, q.y, 0.03)), Vector3(length / float(segs) - 0.2, 0.08, 0.45))
		# the family's graves at the hedge line, a tool leant on each
		for gi in 2:
			var p := down * (off - 0.9) + across * (float(gi) * 2.2 - 1.1 + float(t) * 1.7)
			stones.append([p, PoiKit.yaw_of(-down) + k.rng.randf_range(-0.15, 0.15)])
			tools.append([p + across * 0.6, k.rng.randf() * TAU])
		k.collider(Vector3(length, 1.0, 0.9), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(down)), k.on_ground((down * off).x, (down * off).y, 0.3)), "stone")
		await k.step()
	m.commit(lips, k.surface("stone", 0.8), "LynchetLips")
	m.commit(furrows, PoiKit.plain(SOIL, 0.95), "Furrows")
	await _row(k, "hedge_segment", hedges, true)
	await _row(k, "gravestone", stones, true)
	var fork := k.prop("pitchfork")
	if fork != "":
		for s in tools:
			var q: Vector2 = s[0]
			k.place(fork, k.on_ground(q.x, q.y), float(s[1]), 1.0, false, Vector3(0.2, 0.0, 0.0))
		await k.step()
	k.marker("the_terraces", k.on_ground(down.x * 3.0, down.y * 3.0))
	k.marker("the_top_hedge", k.on_ground(-down.x * 9.8, -down.y * 9.8))
	await _builders().LAND._grass(d, "meadow_grass", -down * 12.0, 6.0, 16)


# --- Briarfoot Watch --------------------------------------------------------------------------------

## The watchtower (the site's own) and at its foot the Wardens' tally-board with a bench, and where
## the two keepers stand: one at the board, one on the stair.
static func briarfoot_watch(d: PoiDressing) -> void:
	await _builders().SITES.build(d)
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(face.y, -face.x)
	var at := face * 6.2 + side * 2.0
	var timber := m.begin()
	var board := m.begin()
	var yaw := PoiKit.yaw_of(face)
	var basis := Basis(Vector3.UP, yaw)
	for s in [-0.7, 0.7]:
		m.post(timber, at + side * float(s), 1.9, 0.12)
	var mid := k.on_ground(at.x, at.y, 1.3)
	m.block(board, Transform3D(basis, mid), Vector3(1.6, 1.0, 0.05))
	m.block(timber, Transform3D(basis, mid + Vector3(0.0, 0.58, 0.0)), Vector3(1.8, 0.1, 0.16))
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "TallyPosts")
	m.commit(board, PoiKit.plain(Color(0.08, 0.09, 0.08), 0.9), "TallyBoard")
	k.touchable("TallyBoard", mid + Vector3(face.x, 0.0, face.y) * 0.4, "Read the tally-board", "core:dialogue/briarfoot_tally_board", "", false)
	var bench := k.prop("bench")
	if bench != "":
		var b := at + face * 1.8
		k.place(bench, k.on_ground(b.x, b.y), yaw, 1.0, true)
	var chest_at := at - side * 2.4
	_container(d, "wardens_chest", k.on_ground(chest_at.x, chest_at.y), yaw, "core:loot/common_chest", "Wardens' Chest", "chest")
	k.marker("the_tally_board", k.on_ground(at.x + face.x * 1.1 - side.x * 1.3, at.y + face.y * 1.1 - side.y * 1.3), true)
	k.marker("the_tower_stair", k.on_ground(face.x * 4.8 - side.x * 3.4, face.y * 4.8 - side.y * 3.4), true)


# --- the Mother Pippin ------------------------------------------------------------------------------

## The first apple tree, lain down along the ground and rooted again where it touched: a veteran
## apple leant far over, its limb running along the turf to a second trunk; about it the orchard's
## rows, the grafter's baskets and barrel, and the windfalls where the boars come.
static func mother_pippin(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lean := k.grain()
	if lean == Vector2.ZERO:
		lean = Vector2(0.0, 1.0)
	var across := Vector2(lean.y, -lean.x)
	var old := k.tree("apple_veteran", 0)
	if old == "":
		old = k.tree("apple", 0)
	if old != "":
		await k.step()
		k.place(old, k.on_ground(0.0, 0.0), PoiKit.yaw_of(lean), 1.35, true, Vector3(0.0, 0.0, 0.0), true)
		var again := lean * 9.5 + across * 0.8
		await k.step()
		k.place(old, k.on_ground(again.x, again.y), PoiKit.yaw_of(lean) + 2.2, 1.05, true, Vector3.ZERO, true)
	# the limb along the ground between them, bark-dark, with the turf over its back
	var bark := m.begin()
	var a := k.on_ground(lean.x * 1.0, lean.y * 1.0, 0.35)
	var b := k.on_ground(lean.x * 8.6 + across.x * 0.7, lean.y * 8.6 + across.y * 0.7, 0.3)
	m.limb(bark, a, (a + b) * 0.5 + Vector3(0.0, 0.25, 0.0), 0.42)
	m.limb(bark, (a + b) * 0.5 + Vector3(0.0, 0.25, 0.0), b, 0.36)
	k.collider(Vector3(0.8, 0.8, a.distance_to(b)), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(lean)), (a + b) * 0.5), "wood")
	await k.step()
	m.commit(bark, PoiKit.plain(Color(0.25, 0.2, 0.15), 0.95), "LyingLimb", true)
	# the orchard's rows about her, clear of her crown
	var apple := k.tree("apple", 0)
	if apple != "" and not k.far:
		var xfs: Array = []
		for r in [-2, -1, 1, 2]:
			for c in range(-3, 4, 2):
				var p := across * float(r) * 7.0 + lean * (float(c) * 6.0 + 3.0) + k.jitter(0.6)
				if p.length() < 9.0 or p.length() > 24.0:
					continue
				xfs.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf() * TAU, k.rng.randf_range(0.85, 1.1)))
		for xf_v in xfs:
			var xf: Transform3D = xf_v
			await k.step()
			k.place(apple, xf.origin, xf.basis.get_euler().y, xf.basis.get_scale().x, true)
	var baskets: Array = []
	for i in 4:
		var p := -lean * 3.8 - across * (3.5 + float(i) * 0.8)
		baskets.append([p, k.rng.randf() * TAU])
	await _row(k, "basket", baskets, false)
	var barrel := k.prop("barrel")
	if barrel != "":
		var p := -lean * 4.5 + across * 2.6
		k.place(barrel, k.on_ground(p.x, p.y), 0.0, 1.0, true)
	k.marker("the_mother", k.on_ground(-lean.x * 2.4 - across.x * 1.8, -lean.y * 2.4 - across.y * 1.8), true)
	k.marker("the_windfalls", k.on_ground(lean.x * 4.0 + across.x * 3.5, lean.y * 4.0 + across.y * 3.5))
	await _builders().LAND._grass(d, "meadow_grass", Vector2.ZERO, 14.0, 26)
	_part_props(d)


# --- the Scourers' Lodge ----------------------------------------------------------------------------

## A farmstead (the kind's own house, barn and yard) given over to the scouring: chalk carts heaped
## white, the rakes and rammers racked along the wall, the gate with its seventy-one cords to touch,
## and the scourers' chest.
static func scourers_lodge(d: PoiDressing) -> void:
	await _builders().LAND.farmstead(d)
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(face.y, -face.x)
	# the chalk carts outside the yard wall, heaped white
	var cart := k.prop("cart")
	var lime := PoiKit.plain(CHALK, 0.95)
	for i in 2:
		var p := face * 16.5 + side * (float(i) * 5.0 - 2.5)
		if cart != "":
			await k.step()
			k.place(cart, k.on_ground(p.x, p.y), PoiKit.yaw_of(side) + k.rng.randf_range(-0.2, 0.2), 1.0, true)
		m.mound(k.on_ground(p.x, p.y, 0.55), 0.8, 0.45, lime, "ChalkLoad%d" % i, false)
	# the rakes: a rack of long-handled rakes leant against a rail
	var rack := face * 14.0 - side * 7.0
	var timber := m.begin()
	var rg := k.on_ground(rack.x, rack.y)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(face))
	for s in [-1.6, 1.6]:
		m.post(timber, rack + side * float(s), 1.3, 0.12)
	m.block(timber, Transform3D(basis, rg + Vector3(0.0, 1.2, 0.0)), Vector3(3.5, 0.1, 0.1))
	for i in 9:
		var x := (float(i) - 4.0) * 0.36
		var foot := rg + basis * Vector3(x, 0.0, 0.7)
		var tip := rg + basis * Vector3(x, 1.25, 0.05)
		m.limb(timber, foot, tip, 0.025)
		m.block(timber, Transform3D(basis, tip + Vector3(0.0, 0.08, 0.0)), Vector3(0.34, 0.06, 0.06))
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "RakeRack")
	k.marker("the_rakes", k.on_ground(rack.x + face.x * 1.6, rack.y + face.y * 1.6), true)
	# the cords on the gate: a rail of white knots by the yard gate
	var g_at := face * 12.8 + side * 3.2
	var cords := m.begin()
	var cg := k.on_ground(g_at.x, g_at.y)
	for s in [-1.1, 1.1]:
		m.post(cords, g_at + side * float(s), 1.25, 0.1)
	var rail_mat := m.begin()
	m.block(rail_mat, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), cg + Vector3(0.0, 1.15, 0.0)), Vector3(2.3, 0.08, 0.08))
	var white := m.begin()
	for i in 36:
		var x := (float(i) / 35.0 - 0.5) * 2.1
		var q := cg + Basis(Vector3.UP, PoiKit.yaw_of(face)) * Vector3(x, 1.02, 0.0)
		m.block(white, Transform3D(Basis(Vector3.BACK, k.rng.randf_range(-0.2, 0.2)), q), Vector3(0.025, 0.24, 0.025))
	await k.step()
	m.commit(cords, k.surface("timber", 0.6), "CordPosts")
	m.commit(rail_mat, k.surface("timber", 0.5), "CordRail")
	m.commit(white, PoiKit.plain(WHITEWASH, 0.9), "Cords")
	k.touchable("GateCords", cg + Vector3(0.0, 1.1, 0.0), "Look at the cords on the gate", "core:dialogue/scourers_gate_cords", "", false)
	k.marker("the_gate", k.on_ground(g_at.x + face.x * 1.2, g_at.y + face.y * 1.2), true)
	var chest_at := rack - side * 2.6
	_container(d, "scourers_chest", k.on_ground(chest_at.x, chest_at.y), PoiKit.yaw_of(face), "core:loot/common_chest", "Scourers' Chest", "chest")


# --- the Listener's Shieling ------------------------------------------------------------------------

## The shieling's own turf hut, and out on the grass before its door the Listener's writing table:
## a stool, her papers under a stone, the book, and the lantern on its crook.
static func listeners_shieling(d: PoiDressing) -> void:
	await _builders().LAND.shieling(d)
	var k := d.kit
	var m := d.masonry
	var face := k.grain()
	var side := Vector2(face.y, -face.x)
	var at := face * 4.5 - side * 1.5
	var yaw := PoiKit.yaw_of(face)
	var table := k.prop("table_round")
	if table == "":
		table = k.prop("table_trestle")
	if table != "":
		await k.step()
		k.place(table, k.on_ground(at.x, at.y), yaw, 1.0, true)
	var stool := k.prop("stool")
	if stool != "":
		var s := at - face * 0.9
		k.place(stool, k.on_ground(s.x, s.y), yaw, 1.0, true)
	var top := k.on_ground(at.x, at.y, 0.76)
	for kind in ["paper_stack", "book", "candle_stub"]:
		var path := k.prop(kind)
		if path != "":
			k.place(path, top + Vector3(k.rng.randf_range(-0.3, 0.3), 0.0, k.rng.randf_range(-0.2, 0.2)), k.rng.randf() * TAU, 1.0, false)
	await k.step()
	var timber := m.begin()
	var crook := at + side * 1.4
	var ctop := m.post(timber, crook, 2.2, 0.07)
	m.block(timber, Transform3D(Basis(Vector3.UP, yaw), ctop + Vector3(0.0, 0.0, 0.0) + Vector3(side.x, 0.0, side.y) * -0.2), Vector3(0.06, 0.06, 0.5))
	m.commit(timber, k.surface("timber", 0.6), "LanternCrook")
	var lamp := k.prop("lantern_hand")
	if lamp != "":
		k.place(lamp, ctop + Vector3(-side.x * 0.4, -0.3, -side.y * 0.4), 0.0, 1.0, false)
	k.touchable("Listen", k.on_ground(at.x + face.x * 1.6, at.y + face.y * 1.6, 1.0), "Sit still and listen", "core:dialogue/listen_on_the_brow", "", false)
	var box := at - side * 1.8
	_container(d, "listeners_chest", k.on_ground(box.x, box.y), yaw, "core:loot/pockets_common", "The Listener's Chest", "chest")
	k.marker("the_writing_table", k.on_ground(at.x - face.x * 1.0 + side.x * 0.1, at.y - face.y * 1.0 + side.y * 0.1), true)


# --- the Wheel Graves -------------------------------------------------------------------------------

## Five fresh graves in a row on the open down, turf mounds each with a cart wheel set upright at its
## head, the widow's tin under the third.
static func wheel_graves(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var toward := _facing(k)
	var along := Vector2(toward.y, -toward.x)
	var wood := m.begin()
	var iron := m.begin()
	var earth := k.surface("earth", 0.5)
	for i in 5:
		var p := along * (float(i) - 2.0) * 3.4
		var g := k.on_ground(p.x, p.y)
		m.mound(g + Vector3(0.0, -0.1, 0.0) - Vector3(toward.x, 0.0, toward.y) * 0.9, 1.05, 0.38, earth, "Grave%d" % i, false, 1.6, 5, 14)
		var head := p + toward * 0.5
		_wheel(m, wood, k.on_ground(head.x, head.y), along, 0.62, 0.2)
		m.block(iron, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(along)), k.on_ground(head.x, head.y, 0.44 + 0.62 - 0.2)), Vector3(0.06, 0.06, 0.06))
		k.collider(Vector3(0.2, 1.1, 1.3), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(toward)), k.on_ground(head.x, head.y, 0.5)), "wood")
		await k.step()
	m.commit(wood, k.surface("timber", 0.55), "Wheels")
	m.commit(iron, PoiKit.plain(IRON, 0.6, 0.5), "WheelIron")
	var tin := toward * 1.4 + along * 0.8
	_container(d, "bels_tin", k.on_ground(tin.x, tin.y), PoiKit.yaw_of(toward), "core:loot/pockets_common", "Bel's Tin", "jar")
	k.marker("the_third_wheel", k.on_ground(toward.x * 2.2, toward.y * 2.2), true)
	var flowers := k.flora("poppy")
	if flowers != "" and not k.far:
		var xfs: Array = []
		for i in 10:
			var p := along * k.rng.randf_range(-5.5, 5.5) - toward * k.rng.randf_range(0.2, 1.5)
			xfs.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf() * TAU, 0.9))
		k.scatter(flowers, xfs, false)
	var perches: Array[Vector3] = []
	for i in [0, 2, 4]:
		var p := along * (float(i) - 2.0) * 3.4 + toward * 0.5
		perches.append(k.on_ground(p.x, p.y, 1.3))
	_crows(d, perches, k.on_ground(0.0, 0.0, 2.0), 3)


# --- the Roadmen's Lodge ----------------------------------------------------------------------------

## The ruined lodge (the kind's own hall) with one corner roofed again for the old roadman, the crew's
## pay-table in the yard with its benches, and a toll-bar across nothing on two posts.
static func roadmens_lodge(d: PoiDressing) -> void:
	await _builders().ruins(d)
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(face.y, -face.x)
	var yaw := PoiKit.yaw_of(face)
	var yard := face * 11.0
	var table := k.prop("table_trestle")
	if table != "":
		await k.step()
		k.place(table, k.on_ground(yard.x, yard.y), PoiKit.yaw_of(side), 1.1, true)
	var benches: Array = [[yard + face * 1.1, PoiKit.yaw_of(side)], [yard - face * 1.1, PoiKit.yaw_of(side) + PI]]
	await _row(k, "bench", benches, false)
	var book := k.prop("book")
	if book != "":
		k.place(book, k.on_ground(yard.x, yard.y, 0.8), yaw, 1.0, false)
	k.marker("the_pay_table", k.on_ground(yard.x + side.x * 2.6, yard.y + side.y * 2.6))
	# the toll-bar: two posts and a bar, standing in the grass with no road through it
	var bar := face * 15.5 - side * 6.0
	var timber := m.begin()
	var tops: Array = []
	for s in [-2.2, 2.2]:
		tops.append(m.post(timber, bar + side * float(s), 1.4, 0.2))
	var mid: Vector3 = ((tops[0] as Vector3) + (tops[1] as Vector3)) * 0.5
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), mid + Vector3(0.0, -0.2, 0.0)), Vector3(4.8, 0.16, 0.16))
	# a lean-to roof over the one room still roofed, against the hall's gable
	var room := -face * 3.0 + side * 5.5
	var rg := k.on_ground(room.x, room.y)
	m.block(timber, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.28), rg + Vector3(0.0, 2.7, 0.0)), Vector3(4.2, 0.12, 4.0))
	for sx in [-1.8, 1.8]:
		m.post(timber, room + side * float(sx) + face * 1.8, 2.5, 0.14)
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "TollBar")
	k.collider(Vector3(4.2, 0.12, 4.0), Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.28), rg + Vector3(0.0, 2.7, 0.0)), "wood")
	var stone := k.prop("milestone")
	if stone != "":
		var p := bar + side * 3.2
		k.place(stone, k.on_ground(p.x, p.y), yaw, 1.0, true)
	k.marker("the_roofed_room", k.on_ground(room.x + face.x * 2.8, room.y + face.y * 2.8), true)


# --- the Wardens' Kennels ---------------------------------------------------------------------------

## The walled camp (the site's own flint ring) with a row of kennel huts along its back wall, the
## feeding trough with its bowls, and where the kennel-master sits by his chained gate.
static func wardens_kennels(d: PoiDressing) -> void:
	await _builders().SITES.build(d)
	var k := d.kit
	_part_the_stores(d)
	var m := d.masonry
	var gate := k.road_direction(120.0)
	if gate == Vector2.ZERO:
		gate = k.downhill()
	if gate == Vector2.ZERO:
		gate = Vector2(0.0, 1.0)
	gate = gate.normalized()
	var side := Vector2(gate.y, -gate.x)
	var planks := m.begin()
	var roofs := m.begin()
	var dark := m.begin()
	var yaw := PoiKit.yaw_of(gate)
	var basis := Basis(Vector3.UP, yaw)
	for i in 4:
		var c := -gate * 8.6 + side * (float(i) - 1.5) * 2.6
		var g := k.on_ground(c.x, c.y)
		m.block(planks, Transform3D(basis, g + Vector3(0.0, 0.55, 0.0)), Vector3(2.0, 1.1, 1.6))
		m.block(roofs, Transform3D(basis * Basis(Vector3.RIGHT, -0.25), g + Vector3(0.0, 1.25, 0.1)), Vector3(2.3, 0.07, 1.9))
		m.block(dark, Transform3D(basis, g + basis * Vector3(0.0, 0.4, 0.81)), Vector3(0.55, 0.7, 0.04))
		k.collider(Vector3(2.0, 1.2, 1.6), Transform3D(basis, g + Vector3(0.0, 0.6, 0.0)), "wood")
		await k.step()
	m.commit(planks, k.surface("planks", 0.7), "Kennels")
	m.commit(roofs, PoiKit.plain(Color(0.5, 0.42, 0.26), 0.95), "KennelRoofs")
	m.commit(dark, PoiKit.plain(SOOT, 0.95), "KennelDoors")
	var trough_at := -gate * 6.2 - side * 4.2
	var tg := k.on_ground(trough_at.x, trough_at.y)
	var trough := m.begin()
	m.block(trough, Transform3D(basis, tg + Vector3(0.0, 0.25, 0.0)), Vector3(2.2, 0.5, 0.6))
	await k.step()
	m.commit(trough, k.surface("stone", 0.7), "Trough")
	k.collider(Vector3(2.2, 0.5, 0.6), Transform3D(basis, tg + Vector3(0.0, 0.25, 0.0)), "stone")
	var bowls: Array = []
	for i in 5:
		bowls.append([trough_at + gate * 0.8 + side * (float(i) - 2.0) * 0.45, 0.0])
	await _row(k, "bowl", bowls, false)
	k.marker("the_feeding_trough", k.on_ground(trough_at.x + gate.x * 1.6, trough_at.y + gate.y * 1.6), true)
	k.marker("the_kennel_gate", k.on_ground(gate.x * 9.0 + side.x * 2.6, gate.y * 9.0 + side.y * 2.6), true)


## The yard's stores (the site's own barrels, crates and sacks, set down at random) moved apart
## where two were set down in one place: a barrel standing in a sack. Each is moved out from the
## middle until it is clear, and set down on the ground there.
static func _part_the_stores(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		return
	var stores: Array[Node3D] = []
	for c in d.get_children():
		var n := c as Node3D
		if n == null:
			continue
		var nm := str(n.name)
		for kind in ["barrel", "crate", "sack", "chopping_block", "cart"]:
			if nm.contains("_" + kind + "_"):
				stores.append(n)
				break
	for i in stores.size():
		var a := stores[i]
		for j in i:
			var b := stores[j]
			var gap := Vector2(a.position.x - b.position.x, a.position.z - b.position.z)
			if gap.length() >= 1.3:
				continue
			var out := Vector2(a.position.x, a.position.z)
			out = out.normalized() if out.length() > 0.1 else Vector2(1.0, 0.0)
			var p := Vector2(a.position.x, a.position.z) + out * 1.6
			a.position = k.on_ground(p.x, p.y)


# --- the Struck Gibbet ------------------------------------------------------------------------------

## Three gibbets on the drove, posts and arms of weathered oak, each arm hung with name-boards on
## short chains, the boards black with white names, most struck through; the crows on the beams.
static func struck_gibbet(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var along := k.road_direction(80.0)
	if along == Vector2.ZERO:
		along = k.grain()
	if along == Vector2.ZERO:
		along = Vector2(1.0, 0.0)
	along = along.normalized()
	var out := Vector2(along.y, -along.x)
	var timber := m.begin()
	var iron := m.begin()
	var boards := m.begin()
	var names := m.begin()
	var perches: Array[Vector3] = []
	for gi in 3:
		var foot := along * (float(gi) - 1.0) * 7.2 + out * (0.6 if gi == 1 else 0.0)
		var top := m.post(timber, foot, 4.2, 0.26)
		var arm_dir := Vector3(out.x, 0.0, out.y)
		var arm_mid := top + Vector3(0.0, -0.3, 0.0) + arm_dir * 0.9
		m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(out) + PI * 0.5), arm_mid), Vector3(2.2, 0.2, 0.2))
		m.limb(timber, top + Vector3(0.0, -1.2, 0.0), arm_mid + arm_dir * 0.4 + Vector3(0.0, -0.08, 0.0), 0.06)
		perches.append(top + Vector3(0.0, 0.05, 0.0))
		for bi in 3:
			var hang := top + Vector3(0.0, -0.3, 0.0) + arm_dir * (0.4 + float(bi) * 0.6)
			var chain := 0.45 + k.rng.randf() * 0.3
			m.block(iron, Transform3D(Basis.IDENTITY, hang + Vector3(0.0, -chain * 0.5, 0.0)), Vector3(0.025, chain, 0.025))
			var turn := Basis(Vector3.UP, PoiKit.yaw_of(out) + k.rng.randf_range(-0.5, 0.5))
			var bc := hang + Vector3(0.0, -chain - 0.2, 0.0)
			m.block(boards, Transform3D(turn, bc), Vector3(0.75, 0.32, 0.03))
			for side in [-1.0, 1.0]:
				m.block(names, Transform3D(turn, bc + turn * Vector3(0.0, 0.0, 0.018 * float(side))), Vector3(0.58, 0.06, 0.005))
				if gi != 1 or bi != 1:
					m.block(names, Transform3D(turn * Basis(Vector3.BACK, 0.35), bc + turn * Vector3(0.0, 0.0, 0.02 * float(side))), Vector3(0.68, 0.035, 0.005))
		await k.step()
	m.commit(timber, k.surface("timber", 0.8), "Gibbets")
	m.commit(iron, PoiKit.plain(IRON, 0.6, 0.5), "Chains")
	m.commit(boards, PoiKit.plain(Color(0.07, 0.07, 0.07), 0.85), "NameBoards")
	m.commit(names, PoiKit.plain(WHITEWASH, 0.8), "Names")
	var mid := k.on_ground(out.x * 1.8, out.y * 1.8, 1.4)
	k.touchable("NameBoards", mid, "Read the name-boards", "core:dialogue/struck_gibbet_boards", "", false)
	k.marker("the_gibbet", k.on_ground(out.x * 3.5, out.y * 3.5), true)
	_crows(d, perches, k.on_ground(0.0, 0.0, 4.0), 5)
	await _builders().LAND._grass(d, "grass_clump", Vector2.ZERO, 7.0, 20)


# --- the Deneholes ----------------------------------------------------------------------------------

## Grain-pits of the Ash Winter sunk into the top of the down: round shafts ringed with chalk blocks,
## most fallen in to a hollow, one kept, with its windlass over it and a lid of hurdles, and the kept
## pit's store to open. Spoil heaped white beside them.
static func deneholes(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var dark := m.begin()
	var chalk := m.begin()
	var shafts: Array[Vector2] = []
	for i in 6:
		var a := TAU * float(i) / 6.0 + k.rng.randf_range(-0.3, 0.3)
		shafts.append(Vector2(sin(a), cos(a)) * k.rng.randf_range(7.0, 13.0))
	var kept := shafts[0]
	for i in shafts.size():
		var c := shafts[i]
		var g := k.on_ground(c.x, c.y)
		var r := 1.0 if i == 0 else k.rng.randf_range(1.2, 2.2)
		m.block(dark, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), g + Vector3(0.0, 0.02, 0.0)), Vector3(r * 1.7, 0.04, r * 1.7))
		var stones := 10 if i == 0 else 7
		for s in stones:
			var a := TAU * float(s) / float(stones)
			var q := c + Vector2(sin(a), cos(a)) * (r + 0.25)
			if i != 0 and k.rng.randf() < 0.35:
				continue
			m.block(chalk, Transform3D(Basis(Vector3.UP, a), k.on_ground(q.x, q.y, 0.12)), Vector3(0.7, 0.34 if i == 0 else 0.22, 0.4))
		if i != 0:
			m.mound(k.on_ground(c.x + 2.5, c.y + 1.0, -0.2), 1.4, 0.6, PoiKit.plain(CHALK, 0.95), "Spoil%d" % i, false)
		await k.step()
	m.commit(dark, PoiKit.plain(SOOT, 0.98), "PitMouths")
	m.commit(chalk, k.surface("stone", 0.7), "PitRims")
	# the kept pit: a windlass on two posts, the rope going down, a lid of hurdles leant beside it
	var timber := m.begin()
	var axis := Vector2(1.0, 0.0)
	var ends: Array = []
	for s in [-1.0, 1.0]:
		ends.append(m.post(timber, kept + axis * 1.4 * float(s), 1.3, 0.16))
	var mid: Vector3 = ((ends[0] as Vector3) + (ends[1] as Vector3)) * 0.5
	m.rod(timber, Transform3D(Basis(Vector3.BACK, PI * 0.5), mid + Vector3(0.0, -0.1, 0.0)), 0.12, 2.8)
	m.block(timber, Transform3D(Basis.IDENTITY, mid + Vector3(1.5, -0.3, 0.0)), Vector3(0.06, 0.5, 0.06))
	var rope := m.begin()
	m.rod(rope, Transform3D(Basis.IDENTITY, mid + Vector3(0.0, -0.9, 0.0)), 0.02, 1.4)
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "Windlass")
	m.commit(rope, PoiKit.plain(Color(0.55, 0.47, 0.32), 0.9), "Rope")
	var lid := m.begin()
	var lp := kept + Vector2(0.0, 2.0)
	var lg := k.on_ground(lp.x, lp.y)
	m.block(lid, Transform3D(Basis(Vector3.RIGHT, -0.35), lg + Vector3(0.0, 0.35, 0.0)), Vector3(1.8, 0.07, 1.2))
	for s in 5:
		m.block(lid, Transform3D(Basis(Vector3.RIGHT, -0.35), lg + Vector3(-0.8 + float(s) * 0.4, 0.4, 0.0)), Vector3(0.05, 0.06, 1.3))
	await k.step()
	m.commit(lid, PoiKit.plain(Color(0.45, 0.36, 0.22), 0.95), "PitLid")
	var stick := kept - Vector2(0.0, 2.2)
	_container(d, "kept_pit", k.on_ground(stick.x, stick.y), 0.0, "core:loot/common_chest", "The Kept Pit's Sacks", "sack")
	await _builders().LAND._grass(d, "grass_clump", Vector2.ZERO, 14.0, 24)


# --- the Rookdown Bee-Garth -------------------------------------------------------------------------

## A round garth of drystone on the down, its wall pierced with niches and a straw skep in each, the
## telling-bench by the gate, and the honey crock in its niche.
static func bee_garth(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var gate := _facing(k)
	var r := 5.2
	var wall := m.begin()
	var niches := m.begin()
	var skeps: Array = []
	var n := 20
	var gate_a := atan2(gate.x, gate.y)
	for i in n:
		var a := gate_a + TAU * (float(i) + 0.5) / float(n)
		var off := wrapf(a - gate_a, -PI, PI)
		if absf(off) < 0.3:
			continue
		var p := Vector2(sin(a), cos(a)) * r
		var g := k.on_ground(p.x, p.y)
		var basis := Basis(Vector3.UP, a)
		m.block(wall, Transform3D(basis, g + Vector3(0.0, 0.7, 0.0)), Vector3(1.7, 1.6, 0.7))
		if i % 2 == 0:
			var inner := Vector2(sin(a), cos(a)) * (r - 0.3)
			var ng := k.on_ground(inner.x, inner.y)
			m.block(niches, Transform3D(basis, ng + Vector3(0.0, 0.85, 0.0)), Vector3(0.62, 0.6, 0.12))
			skeps.append(ng + Vector3(0.0, 0.58, 0.0) - Vector3(sin(a), 0.0, cos(a)) * 0.1)
		k.collider(Vector3(1.7, 1.6, 0.7), Transform3D(basis, g + Vector3(0.0, 0.7, 0.0)), "stone")
	await k.step()
	m.commit(wall, k.surface("stone", 0.8), "GarthWall")
	m.commit(niches, PoiKit.plain(SOOT, 0.95), "BeeBoles")
	var basket := k.prop("basket", 0)
	if basket != "" and not k.far:
		var xfs: Array = []
		for s in skeps:
			xfs.append(Transform3D(Basis(Vector3.RIGHT, PI), (s as Vector3) + Vector3(0.0, 0.42, 0.0)))
		await k.step()
		k.scatter(basket, xfs, false)
	var bench_at := gate * (r + 1.4) + Vector2(gate.y, -gate.x) * 1.6
	var bench := k.prop("bench")
	if bench != "":
		k.place(bench, k.on_ground(bench_at.x, bench_at.y), PoiKit.yaw_of(gate), 1.0, true)
	k.touchable("TellTheBees", k.on_ground(bench_at.x, bench_at.y, 0.9), "Tell the bees", "core:dialogue/tell_the_bees", "", false)
	k.marker("the_telling_bench", k.on_ground(bench_at.x + gate.x * 1.1, bench_at.y + gate.y * 1.1), true)
	var crock := -gate * (r - 1.2)
	_container(d, "honey_crock", k.on_ground(crock.x, crock.y), PoiKit.yaw_of(gate), "core:loot/pockets_common", "Honey Crock", "jar")
	await _builders().LAND._grass(d, "oxeye_daisy", Vector2.ZERO, 4.0, 16)


# --- Hushwatch --------------------------------------------------------------------------------------

## The stones (the kind's own), and between them where a body stands to look south and say one name.
static func hushwatch(d: PoiDressing) -> void:
	await _builders().standing_stones(d)
	var k := d.kit
	k.touchable("SayAName", k.on_ground(0.0, 0.0, 1.2), "Say a name to the Hush", "core:dialogue/hushwatch_say_a_name", "", false)


# ===================================================================================================
# World life, phase 2 (2026-10-01): the large places with an inside, and the second pass over the
# places that were a ruin and nothing else. Every one here tells its sentence in its layout.
# ===================================================================================================

const FLINT := Color(0.17, 0.18, 0.2)
const SPOIL := {"base": "#a8a08c", "accent": "#878070", "grout": "#5e594d", "unit": 0.45}


## A bank of turf in a ring about `c` (local xz), `r` to its crest, `width` across and `height` at
## the crest, following the ground: the lip thrown up round a shaft filled in long ago, or a barrow's
## ditch. One mesh, no body (it is under a knee).
static func _ring_bank(d: PoiDressing, st: SurfaceTool, c: Vector2, r: float, width: float, height: float, segments := 24) -> void:
	var k := d.kit
	var rows := 5
	var pts: Array = []
	for i in rows + 1:
		var f := float(i) / float(rows)
		var rr := r + (f - 0.5) * width
		var y := height * sin(f * PI)
		var row: Array = []
		for j in segments:
			var a := TAU * float(j) / float(segments)
			var wob := 1.0 + 0.06 * sin(a * 3.0 + r)
			var p := c + Vector2(sin(a), cos(a)) * rr * wob
			row.append(k.on_ground(p.x, p.y, y - 0.04))
		pts.append(row)
	for i in rows:
		for j in segments:
			var j1 := (j + 1) % segments
			for p in [pts[i][j], pts[i + 1][j1], pts[i + 1][j], pts[i][j], pts[i][j1], pts[i + 1][j1]]:
				st.add_vertex(p)


## A trodden way on the ground from point to point (local xz), `width` across, lifted a hair over the
## grass so it reads, into `st`.
static func _track(d: PoiDressing, st: SurfaceTool, pts: Array, width: float) -> void:
	var k := d.kit
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(int(a.distance_to(b) / 1.5), 1)
		var dir := (b - a).normalized()
		var across := Vector2(-dir.y, dir.x) * width * 0.5
		for s in n:
			var p0 := a.lerp(b, float(s) / float(n))
			var p1 := a.lerp(b, float(s + 1) / float(n))
			var w0 := 1.0 + 0.12 * sin(float(s) * 1.7 + float(i))
			var w1 := 1.0 + 0.12 * sin(float(s + 1) * 1.7 + float(i))
			var q := [k.on_ground(p0.x - across.x * w0, p0.y - across.y * w0, 0.03), k.on_ground(p0.x + across.x * w0, p0.y + across.y * w0, 0.03),
					k.on_ground(p1.x + across.x * w1, p1.y + across.y * w1, 0.03), k.on_ground(p1.x - across.x * w1, p1.y - across.y * w1, 0.03)]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.add_vertex(q[idx])


## Flint nodules: the chalk's black stones with their white rind, a few or a heap, as the forge's
## boulder made small and dark (one MultiMesh).
static func _flints(d: PoiDressing, spots: Array, scale_lo := 0.07, scale_hi := 0.16, node_name := "Flints") -> void:
	var k := d.kit
	var path := k.rock("boulder")
	if path == "" or k.far or spots.is_empty():
		return
	var xfs: Array = []
	for s in spots:
		var p: Vector2 = s
		xfs.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.03), k.rng.randf() * TAU, k.rng.randf_range(scale_lo, scale_hi),
				Vector3(k.rng.randf_range(-0.5, 0.5), 0.0, k.rng.randf_range(-0.5, 0.5))))
	await k.step()
	var mm := k.scatter(path, xfs, false, false, false)
	if mm != null:
		mm.name = node_name
		mm.material_override = PoiKit.plain(FLINT, 0.35)


## A round timber from `a` to `b` (local) with a body along it, so the legs of a frame can be bumped.
static func _timber(d: PoiDressing, st: SurfaceTool, a: Vector3, b: Vector3, r: float, collide := true) -> void:
	d.masonry.limb(st, a, b, r)
	if not collide or d.kit.far:
		return
	var dir := b - a
	var length := dir.length()
	if length < 0.05:
		return
	var y := dir / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	d.kit.collider(Vector3(r * 2.0, length, r * 2.0), Transform3D(Basis(x, y, z), (a + b) * 0.5), "wood")


## A tapered block into `st`: a foot `w0` by `d0`, a head `w1` by `d1`, `h` high, in `xf` (its origin at
## the middle of the foot, y up). Each face wound outward, so its normals face out.
static func _frustum(st: SurfaceTool, xf: Transform3D, w0: float, d0: float, w1: float, d1: float, h: float) -> void:
	var lo := [Vector3(-w0, 0.0, -d0), Vector3(w0, 0.0, -d0), Vector3(w0, 0.0, d0), Vector3(-w0, 0.0, d0)]
	var hi := [Vector3(-w1, h, -d1), Vector3(w1, h, -d1), Vector3(w1, h, d1), Vector3(-w1, h, d1)]
	var mid := Vector3(0.0, h * 0.5, 0.0)
	var quads: Array = []
	for i in 4:
		quads.append([lo[i] * Vector3(0.5, 1.0, 0.5), lo[(i + 1) % 4] * Vector3(0.5, 1.0, 0.5), hi[(i + 1) % 4] * Vector3(0.5, 1.0, 0.5), hi[i] * Vector3(0.5, 1.0, 0.5)])
	quads.append([hi[0] * Vector3(0.5, 1.0, 0.5), hi[1] * Vector3(0.5, 1.0, 0.5), hi[2] * Vector3(0.5, 1.0, 0.5), hi[3] * Vector3(0.5, 1.0, 0.5)])
	for q in quads:
		var a: Vector3 = q[0]
		var b: Vector3 = q[1]
		var c: Vector3 = q[2]
		var d: Vector3 = q[3]
		var centre := (a + b + c + d) * 0.25
		# Godot's front faces wind clockwise seen from outside: flip a quad that winds the other way
		var n := (b - a).cross(c - a)
		if n.dot(centre - mid) > 0.0:
			var t := b
			b = d
			d = t
		for v in [a, b, c, a, c, d]:
			st.add_vertex(xf * (v as Vector3))


## A band of ground in an arc about `c` (local xz): `r` to its middle, `width` across, from bearing
## `a0` to `a1` (radians, as PoiKit.yaw_of measures), lying a hair over the ground, into `st`.
static func _arc_band(d: PoiDressing, st: SurfaceTool, c: Vector2, r: float, width: float, a0: float, a1: float, segs := 24) -> void:
	var k := d.kit
	var pts: Array = []
	for i in 3:
		var rr := r + (float(i) - 1.0) * width * 0.5
		var row: Array = []
		for j in segs + 1:
			var a := lerpf(a0, a1, float(j) / float(segs))
			var taper := sin(PI * float(j) / float(segs))
			var rw := r + (rr - r) * (0.35 + 0.65 * taper)
			var p := c + Vector2(sin(a), cos(a)) * rw
			row.append(k.on_ground(p.x, p.y, 0.035))
		pts.append(row)
	for i in 2:
		for j in segs:
			for v in [pts[i][j], pts[i + 1][j + 1], pts[i + 1][j], pts[i][j], pts[i][j + 1], pts[i + 1][j + 1]]:
				st.add_vertex(v)


## The grey come up over the grass on one side of a place: a sheet over the ground (the ash country's
## own mosaic, PoiBuilders' ash_drift shader, in the downs' greys and with no char), present in a
## crescent about `c` from `r0` to `r1` toward `dir` and `half` radians either side of it, its edges
## ragged, thickest at the middle of the crescent.
static func _grey_sheet(d: PoiDressing, c: Vector2, dir: Vector2, r0: float, r1: float, half: float) -> void:
	var k := d.kit
	if k.far:
		return
	const STEP := 1.5
	var cells := int(ceil(r1 * 2.0 / STEP)) + 2
	var n := cells + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var live := PackedByteArray()
	live.resize(n * n)
	var a0 := atan2(dir.x, dir.y)
	for j in n:
		if j % 12 == 11:
			await k.step()
		for i in n:
			var q := c + Vector2((float(i) - float(cells) * 0.5) * STEP, (float(j) - float(cells) * 0.5) * STEP)
			var off := q - c
			var r := off.length()
			var da := absf(wrapf(atan2(off.x, off.y) - a0, -PI, PI))
			var wob := 1.5 * sin(3.0 * atan2(off.x, off.y) + 1.1) + sin(7.0 * atan2(off.x, off.y))
			var mask := smoothstep(r0 - 1.0, r0 + 2.5, r + wob) * (1.0 - smoothstep(r1 - 5.0, r1 + wob, r)) \
					* (1.0 - smoothstep(half * 0.7, half, da))
			live[j * n + i] = 1 if mask > 0.0 else 0
			st.set_color(Color(mask, 1.0 - smoothstep(r0, r1, r), 0.0, 1.0))
			st.set_uv(off)
			st.add_vertex(k.on_ground(q.x, q.y, 0.05))
	for j in cells:
		for i in cells:
			var i0 := j * n + i
			if live[i0] + live[i0 + 1] + live[i0 + n] + live[i0 + n + 1] == 0:
				continue
			for idx in [i0, i0 + 1, i0 + n + 1, i0, i0 + n + 1, i0 + n]:
				st.add_index(idx)
	await k.step()
	var mat := ShaderMaterial.new()
	mat.shader = _builders().ASH_DRIFT_SHADER
	mat.set_shader_parameter("ash", Color(0.47, 0.48, 0.44))
	mat.set_shader_parameter("char_rim", Color(0.36, 0.38, 0.32))
	mat.set_shader_parameter("patch_m", 6.0)
	var mi := MeshInstance3D.new()
	k.finish_mesh(mi, st)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "TheGrey"
	mi.visibility_range_end = 220.0
	k.root.add_child(mi)


# --- Knappers' Deep ---------------------------------------------------------------------------------

## A flint mine on the lip of Hound Down. Over the deep shaft a timber headframe eleven metres high
## with its winding wheel against the sky, raked legs braced in two lifts and a pair of back-stays;
## the rope from the wheel down the shaft and back to the horse-gin's drum, the gin's sweep over its
## trodden ring. The shaft's head built up in chalk blocks and timber with its ladder going down into
## the black. A hundred years of spoil tipped white down the down's face. Round about the grassed
## rings of older shafts nobody counts. The knapper's hut with its smoke, her knapping floor under a
## lean-to, flint nodules in heaps and squared flints stacked for the builders' carts, and the shift
## board on the headframe's leg with the night shift's names chalked on it and never rubbed out.
static func knappers_deep(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var down := k.downhill()
	if down == Vector2.ZERO:
		down = k.grain()
	var up := -down
	var side := Vector2(down.y, -down.x)
	var road := k.road_direction(120.0)
	if road == Vector2.ZERO:
		road = side
	var interior := str((ContentDB.get_or_empty(d.poi_id).get("site", {}) as Dictionary).get("interior", ""))
	# the shaft and its head, a little back from the lip
	var shaft := up * 3.0
	var sg := k.on_ground(shaft.x, shaft.y)
	var syaw := PoiKit.yaw_of(up)
	var sb := Basis(Vector3.UP, syaw)
	var collar_h := 0.75
	var chalk = _builders().SITES.Stones.new(k, k.rng.randi())
	var timber := m.begin()
	var black := m.begin()
	# the collar: four walls of the Vale's stone round a square of black, the timber lining inside them,
	# laid as the forts lay theirs (weathered, the grime rising from the ground, moss in the joints)
	var lo := INF
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var q := shaft + side * 2.0 * float(sx) + up * 2.0 * float(sz)
			lo = minf(lo, k.on_ground(q.x, q.y).y)
	var top_y := maxf(sg.y, lo) + collar_h
	for i in 4:
		var n := sb * (Basis(Vector3.UP, float(i) * PI * 0.5) * Vector3(0.0, 0.0, 1.0))
		var c := Vector3(sg.x, (lo - 0.3 + top_y) * 0.5, sg.z) + n * 1.65
		var bb := Basis(Vector3.UP, syaw + float(i) * PI * 0.5)
		chalk.top = top_y
		chalk.block(Transform3D(bb, c), Vector3(4.0, top_y - lo + 0.3, 0.7))
		m.block(timber, Transform3D(bb, Vector3(sg.x, top_y - 0.45, sg.z) + n * 1.22), Vector3(2.5, 0.9, 0.16))
		m.block(timber, Transform3D(bb, Vector3(sg.x, top_y + 0.06, sg.z) + n * 1.55), Vector3(3.6, 0.14, 0.36))
	m.block(black, Transform3D(sb, Vector3(sg.x, top_y - 0.62, sg.z)), Vector3(2.4, 0.05, 2.4))
	k.collider(Vector3(4.0, top_y - lo + 0.3, 4.0), Transform3D(sb, Vector3(sg.x, (lo - 0.3 + top_y) * 0.5, sg.z)), "stone")
	# the ladder's head standing up out of the hole on the road side, and two steps up to it
	var lad := Vector3(sg.x, 0.0, sg.z) + Vector3(road.x, 0.0, road.y) * 0.7
	for s in [-0.28, 0.28]:
		var o := Vector3(-road.y, 0.0, road.x) * float(s)
		m.limb(timber, lad + o + Vector3(0.0, top_y - 1.0, 0.0), lad + o + Vector3(0.0, top_y + 1.1, 0.0), 0.045)
	for r_i in 4:
		m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(road)), lad + Vector3(0.0, top_y - 0.6 + float(r_i) * 0.4, 0.0)), Vector3(0.6, 0.05, 0.05))
	var step_from := shaft + road * 2.3
	var steps := m.begin()
	m.steps(steps, step_from + road * 1.4, -road, k.on_ground(step_from.x + road.x * 1.4, step_from.y + road.y * 1.4).y - 0.05, 2, (top_y - k.on_ground(step_from.x, step_from.y).y) / 2.2, 0.55, 1.6)
	if interior != "":
		_builders().SITES._door(d, interior, Vector3(lad.x, top_y, lad.z) + Vector3(road.x, 0.0, road.y) * 0.35, PoiKit.yaw_of(-road))
	k.marker("the_shaft_head", k.on_ground(step_from.x + road.x * 2.2, step_from.y + road.y * 2.2), true)
	await k.step()
	# the headframe: four raked legs from the collar's corners to a head two metres square
	var H := 13.5
	var legs: Array[Vector3] = []
	var heads: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var foot := shaft + side * 2.25 * float(sx) + up * 2.25 * float(sz)
			var head := shaft + side * 0.95 * float(sx) + up * 0.95 * float(sz)
			var fg := k.on_ground(foot.x, foot.y, -0.2)
			legs.append(fg)
			heads.append(Vector3(head.x, sg.y + H, head.y))
	for i in 4:
		_timber(d, timber, legs[i], heads[i], 0.17)
	# girts in two lifts, and a cross of braces on each face between them
	var order := [0, 1, 3, 2]
	for lift in [0.33, 0.66, 1.0]:
		for i in 4:
			var a: Vector3 = legs[order[i]].lerp(heads[order[i]], lift)
			var b: Vector3 = legs[order[(i + 1) % 4]].lerp(heads[order[(i + 1) % 4]], lift)
			m.limb(timber, a, b, 0.11)
	for i in 4:
		var a0: Vector3 = legs[order[i]].lerp(heads[order[i]], 0.33)
		var b0: Vector3 = legs[order[(i + 1) % 4]].lerp(heads[order[(i + 1) % 4]], 0.33)
		var a1: Vector3 = legs[order[i]].lerp(heads[order[i]], 0.66)
		var b1: Vector3 = legs[order[(i + 1) % 4]].lerp(heads[order[(i + 1) % 4]], 0.66)
		m.limb(timber, a0, b1, 0.07)
		m.limb(timber, b0, a1, 0.07)
	# the head: two bearers across the wheel's axle, the wheel on them, and the back-stays raking
	# down toward the gin so the pull of the rope has something to lean on
	var head_c := Vector3(sg.x, sg.y + H, sg.z)
	var axle := side
	for s in [-1.0, 1.0]:
		m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(up)), head_c + Vector3(axle.x, 0.0, axle.y) * 0.75 * float(s) + Vector3(0.0, 0.15, 0.0)), Vector3(0.24, 0.3, 2.6))
	var wheel_r := 1.8
	var wc := head_c + Vector3(0.0, 0.3 + wheel_r, 0.0)
	var wface := Basis(Vector3.UP, PoiKit.yaw_of(axle))
	for i in 20:
		var a := TAU * (float(i) + 0.5) / 20.0
		var p := wc + wface * Vector3(sin(a) * wheel_r, cos(a) * wheel_r, 0.0)
		m.block(timber, Transform3D(wface * Basis(Vector3.BACK, -a), p), Vector3(wheel_r * 0.34, 0.14, 0.12))
	for i in 8:
		var a := TAU * float(i) / 8.0
		m.limb(timber, wc, wc + wface * Vector3(sin(a) * wheel_r, cos(a) * wheel_r, 0.0), 0.045)
	m.rod(timber, Transform3D(wface * Basis(Vector3.RIGHT, PI * 0.5), wc), 0.12, 1.7)
	var gin := up * 14.0
	var gg := k.on_ground(gin.x, gin.y)
	for s in [-1.0, 1.0]:
		var foot := shaft + up * 8.0 + side * 2.4 * float(s)
		_timber(d, timber, k.on_ground(foot.x, foot.y, -0.2), heads[2 if s < 0.0 else 3].lerp(head_c, 0.3) + Vector3(0.0, -0.2, 0.0), 0.15)
	await k.step()
	m.commit(timber, k.surface("timber", 0.65), "Headframe", true)
	_builders().SITES._commit(d, chalk, _builders().SITES.stone_look(k, sg.y), "ShaftHead", true)
	m.commit(steps, PoiKit.painted(2, {"base": "#55565a", "accent": "#7d7b76", "grout": "#a39d8c", "unit": 0.2}, 0.6, 0.7), "ShaftSteps")
	m.commit(black, PoiKit.plain(Color(0.015, 0.014, 0.013), 1.0), "TheDark")
	# the rope: down the shaft from the front of the wheel, and from its back to the gin's drum
	var rope := m.begin()
	m.limb(rope, wc + Vector3(-up.x, 0.0, -up.y) * wheel_r, Vector3(sg.x, top_y - 0.9, sg.z) + Vector3(-up.x, 0.0, -up.y) * 0.4, 0.035)
	m.limb(rope, wc + Vector3(up.x, 0.0, up.y) * wheel_r * 0.9 + Vector3(0.0, 0.2, 0.0), gg + Vector3(0.0, 2.0, 0.0) + Vector3(-up.x, 0.0, -up.y) * 1.1, 0.035)
	m.commit(rope, PoiKit.plain(Color(0.5, 0.42, 0.3), 0.9), "WindingRope")
	await k.step()
	# the horse-gin: its post, the drum the rope winds on, the sweep, and the ring the horse wore
	var gin_t := m.begin()
	m.rod(gin_t, Transform3D(Basis.IDENTITY, gg + Vector3(0.0, 1.8, 0.0)), 0.22, 3.6)
	m.rod(gin_t, Transform3D(Basis.IDENTITY, gg + Vector3(0.0, 2.0, 0.0)), 1.1, 0.8)
	m.rod(gin_t, Transform3D(Basis.IDENTITY, gg + Vector3(0.0, 2.45, 0.0)), 1.25, 0.1)
	m.rod(gin_t, Transform3D(Basis.IDENTITY, gg + Vector3(0.0, 1.55, 0.0)), 1.25, 0.1)
	var sweep_yaw := PoiKit.yaw_of(side) + 0.5
	m.block(gin_t, Transform3D(Basis(Vector3.UP, sweep_yaw), gg + Vector3(0.0, 1.35, 0.0)), Vector3(0.18, 0.2, 10.5))
	var sw := Basis(Vector3.UP, sweep_yaw)
	for s in [-1.0, 1.0]:
		m.limb(gin_t, gg + Vector3(0.0, 3.4, 0.0), gg + sw * Vector3(0.0, 1.4, 3.4 * float(s)), 0.06)
	k.collider(Vector3(0.5, 3.6, 0.5), Transform3D(Basis.IDENTITY, gg + Vector3(0.0, 1.8, 0.0)), "wood")
	await k.step()
	m.commit(gin_t, k.surface("timber", 0.7), "HorseGin", true)
	var earth := m.begin()
	_ring_bank(d, earth, gin, 5.4, 1.5, 0.05, 28)
	# the cart way: from the shaft's steps out toward the road across the pad
	var way_end := road * (d.pad_radius * 0.92)
	_track(d, earth, [step_from + road * 1.6, step_from + road * 9.0 + side * 1.5, way_end], 2.6)
	await k.step()
	m.commit(earth, k.surface("earth", 0.4), "Trodden")
	# the spoil: a hundred years tipped white down the face, three tongues of it, flints in it
	var spoil_mat := PoiKit.painted(5, SPOIL, 0.85, 0.9)
	var heaps := [[down * 22.0 + side * 10.0, 6.5, 3.6], [down * 27.0 - side * 3.0, 7.5, 4.4], [down * 18.0 - side * 15.0, 5.0, 2.6], [down * 30.0 + side * 6.0, 4.5, 2.2]]
	var flint_spots: Array = []
	for i in heaps.size():
		var h: Array = heaps[i]
		var c: Vector2 = h[0]
		var r: float = h[1]
		# a tip-heap: tipped from the barrow-run, its crest along the way it was tipped, lumpy, the old
		# tips' flanks grassing over at their feet
		_hump(d, c, down, r * 1.35, r * 0.85, float(h[2]), spoil_mat, "Spoil%d" % i, true, 1.9, true, 0.2)
		await _builders().LAND._grass(d, "grass_clump", c + down * r * 0.9, r * 0.6, 14)
		await _builders().LAND._grass(d, "meadow_grass", c - side * r * 0.7, r * 0.4, 8)
		for j in 14:
			var a := k.rng.randf() * TAU
			flint_spots.append(c + Vector2(sin(a), cos(a)) * r * sqrt(k.rng.randf()) * 0.85)
		await k.step()
	# grass taking the old heap, and the tips' edges
	await _builders().LAND._grass(d, "grass_clump", heaps[2][0], 6.0, 18)
	# the old shafts: rings of turf round hollows, in every direction but the face
	var rings := m.begin()
	var placed: Array[Vector2] = []
	for i in 9:
		var a := PoiKit.yaw_of(up) + k.rng.randf_range(-1.9, 1.9)
		var p := Vector2(sin(a), cos(a)) * k.rng.randf_range(15.0, d.pad_radius * 0.78)
		var clear := p.distance_to(gin) > 9.0 and p.distance_to(shaft) > 8.0
		for q in placed:
			clear = clear and p.distance_to(q) > 7.0
		if not clear:
			continue
		placed.append(p)
		_ring_bank(d, rings, p, k.rng.randf_range(2.2, 3.4), k.rng.randf_range(1.6, 2.4), k.rng.randf_range(0.35, 0.6), 20)
	await k.step()
	m.commit(rings, _turf(), "OldShafts")
	var hollow_mat := PoiKit.plain(Color(0.24, 0.29, 0.15), 0.95)
	for p in placed:
		m.pool(p, 1.7, k.on_ground(p.x, p.y).y + 0.03, hollow_mat, "Hollow", 14)
	# the knapper's hut, its lean-to and her floor, on the road side of the shaft
	var hut_c := shaft + side * 11.0 + road * 4.0
	var fabric := FabricMesh.new()
	var hut_face := road
	await _builders().LAND._house(d, fabric, _builders().LAND._frame(d, hut_c, hut_face, 5.4, 4.0), 5.4, 4.0, 1)
	await _builders().LAND._commit_fabric(d, fabric)
	k.marker("home", k.on_ground(hut_c.x + hut_face.x * 3.2, hut_c.y + hut_face.y * 3.2), true)
	var floor_c := hut_c + hut_face * 5.5 - side * 3.5
	var lean := m.begin()
	var fyaw := PoiKit.yaw_of(hut_face)
	var fb := Basis(Vector3.UP, fyaw)
	for sx in [-1.6, 1.6]:
		for sz in [-1.0, 1.0]:
			var p := floor_c + side * float(sx) + hut_face * float(sz)
			m.post(lean, p, 2.1 if sz < 0.0 else 1.7, 0.12)
	var lg := k.on_ground(floor_c.x, floor_c.y)
	m.block(lean, Transform3D(fb * Basis(Vector3.RIGHT, -0.2), lg + Vector3(0.0, 2.0, 0.0)), Vector3(3.8, 0.08, 2.6))
	k.collider(Vector3(3.8, 0.08, 2.6), Transform3D(fb * Basis(Vector3.RIGHT, -0.2), lg + Vector3(0.0, 2.0, 0.0)), "wood")
	await k.step()
	m.commit(lean, k.surface("timber", 0.6), "LeanTo")
	var block := k.prop("chopping_block")
	if block != "":
		k.place(block, lg, fyaw, 1.0, true)
	var stool := k.prop("stool")
	if stool != "":
		k.place(stool, k.on_ground(floor_c.x - hut_face.x * 0.8, floor_c.y - hut_face.y * 0.8), fyaw, 1.0, true)
	k.marker("the_knapping_floor", k.on_ground(floor_c.x + hut_face.x * 1.6, floor_c.y + hut_face.y * 1.6), true)
	# the floor's leavings: flakes everywhere under the lean-to, nodules heaped, squared flints stacked
	var flakes: Array = []
	for i in 40:
		flakes.append(floor_c + k.jitter(2.2))
	await _flints(d, flakes, 0.025, 0.06, "Flakes")
	var heap_c := floor_c + side * 3.0
	for i in 22:
		flint_spots.append(heap_c + k.jitter(0.9))
	await _flints(d, flint_spots, 0.08, 0.17, "Nodules")
	var squared := m.begin()
	var stack_c := floor_c - side * 3.2 + hut_face * 0.4
	var stack_g := k.on_ground(stack_c.x, stack_c.y)
	for lay in 4:
		for row in 3:
			for col in 6:
				var o := Vector3((float(col) - 2.5) * 0.19, float(lay) * 0.17 + 0.09, (float(row) - 1.0) * 0.19)
				m.block(squared, Transform3D(fb, stack_g + fb * o), Vector3(0.17, 0.15, 0.17))
	m.commit(squared, PoiKit.painted(2, {"base": "#2f3034", "accent": "#4a4b50", "grout": "#d8d2c0", "unit": 0.17}, 0.5, 0.6), "SquaredFlints")
	k.collider(Vector3(1.2, 0.7, 0.6), Transform3D(fb, stack_g + Vector3(0.0, 0.35, 0.0)), "stone")
	var cart := k.prop("cart")
	if cart != "":
		var cp := stack_c - side * 3.0 + hut_face * 1.5
		await k.step()
		k.place(cart, k.on_ground(cp.x, cp.y), PoiKit.yaw_of(road) + 0.3, 1.0, true)
	await _row(k, "basket", [[heap_c + side * 1.4, 0.3], [heap_c + side * 1.4 + hut_face * 0.8, 1.2]], true)
	# the shift board on the headframe's road-side leg: seven names in chalk and one more
	var leg_foot: Vector3 = legs[0] if (Vector2(legs[0].x, legs[0].z) - shaft).dot(road) > 0.0 else legs[3]
	var board_at := leg_foot.lerp(heads[0] if leg_foot == legs[0] else heads[3], 0.13) + Vector3(road.x, 0.0, road.y) * 0.25
	var board := m.begin()
	m.block(board, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(road)), board_at), Vector3(0.9, 0.7, 0.05))
	m.commit(board, PoiKit.plain(Color(0.16, 0.15, 0.14), 0.9), "ShiftBoard")
	var marks := m.begin()
	for i in 8:
		var y := 0.24 - float(i) * 0.065
		var w := 0.5 if i < 7 else 0.22
		m.block(marks, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(road)), board_at + Vector3(0.0, y, 0.0) + Vector3(road.x, 0.0, road.y) * 0.03), Vector3(w, 0.022, 0.01))
	m.commit(marks, PoiKit.plain(CHALK, 0.9), "ShiftNames")
	k.touchable("ShiftBoard", board_at + Vector3(road.x, 0.0, road.y) * 0.3, "Read the shift board", "core:dialogue/knappers_shift_board", "", false)
	# a lantern hung at the shaft head, lit day and night: the knapper keeps it for them
	var lamp := k.prop("lantern_hanging")
	if lamp == "":
		lamp = k.prop("lantern_hand")
	var lamp_at := heads[0].lerp(legs[0], 0.8) + Vector3(0.0, -0.4, 0.0)
	if lamp != "":
		k.place(lamp, lamp_at + Vector3(0.0, -0.3, 0.0), 0.0, 1.0, false)
	k.light(lamp_at + Vector3(0.0, -0.5, 0.0), Color(1.0, 0.75, 0.45), 1.2, 8.0)
	# the store: the knapper's chest by her hut, and a hawthorn bent over the old shafts by the wind
	var store := hut_c - hut_face * 0.2 + side * 3.6
	_container(d, "knappers_store", k.on_ground(store.x, store.y), fyaw, "core:loot/common_chest", "The Knapper's Store", "chest")
	var thorn := k.tree("hawthorn_veteran")
	if thorn == "":
		thorn = k.tree("hawthorn")
	if thorn != "":
		for p in [up * 24.0 - side * 14.0, up * 18.0 + side * 21.0]:
			if (p as Vector2).length() < d.pad_radius * 0.9:
				await k.step()
				k.place(thorn, k.on_ground(p.x, p.y, -0.1), k.rng.randf() * TAU, k.rng.randf_range(0.9, 1.15), true)
	await _builders().LAND._grass(d, "cow_parsley", up * 10.0 - side * 10.0, 7.0, 16)


# --- the Hum Stone ----------------------------------------------------------------------------------

## The Builders' marker on the lip of the Brow over the Hush: a monolith of their dark fused stone
## fourteen metres high, leaning a little toward the grey, banded with bronze at four heights, two of
## the bands hacked away to bright metal. It stands on a turfed hump ringed by their kerb, half the
## kerb gone. On the down side the barrow-diggers have cut their way in between two banks of spoil
## shored with planks, down to a door of the Builders' at the hump's foot: a frame of three great
## stones with no hinge, its slab slid aside, and the dark. Their camp beside the cut: a windlass, a
## sieve, the bronze they have cut heaped on a cloth. Along the lip, the bellwright from Merrowby with
## his frame of tuning bells, come to take the stone's note. On the Hush side the grass has gone grey
## where the Hush's dead stand at night to listen.
static func hum_stone(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var hush := k.downhill()
	if hush == Vector2.ZERO:
		hush = Vector2(0.0, 1.0)
	var land := -hush
	var side := Vector2(hush.y, -hush.x)
	var interior := str((ContentDB.get_or_empty(d.poi_id).get("site", {}) as Dictionary).get("interior", ""))
	var oroth := k.surface("oroth", 0.35)
	var bronze := PoiKit.plain(PoiKit.BRONZE.darkened(0.15).lerp(Color(0.3, 0.45, 0.38), 0.35), 0.55, 0.6)
	var bright := PoiKit.plain(PoiKit.BRONZE.lightened(0.25), 0.3, 0.9)
	var turf := PoiKit.painted(5, {"base": "#6c7742", "accent": "#56602f", "grout": "#3b4422", "unit": 0.35}, 0.6)
	# the hump the stone stands on
	var foot := hush * 2.0
	var fg := k.on_ground(foot.x, foot.y)
	m.mound(fg + Vector3(0.0, -0.3, 0.0), 8.0, 2.6, turf, "Hump", true, 1.5, 7, 24, true, 0.07)
	var base_y := fg.y + 2.2
	# the stone: one tapering shaft of the fused stone, a little swollen a third of the way up as
	# their columns are, leaning toward the Hush, its crown cut on the slant
	var stone := m.begin()
	var lean := Basis(Vector3(side.x, 0.0, side.y), -0.055)
	var sy := PoiKit.yaw_of(hush) + 0.2
	var H := 15.0
	var sb := lean * Basis(Vector3.UP, sy)
	# the stone goes down through its hump into the chalk under it
	var foot_c := Vector3(foot.x, fg.y - 0.25, foot.y)
	_frustum(stone, Transform3D(sb, foot_c), 3.0, 2.1, 3.1, 2.2, H * 0.3)
	_frustum(stone, Transform3D(sb, foot_c + sb * Vector3(0.0, H * 0.3, 0.0)), 3.1, 2.2, 1.8, 1.25, H * 0.7)
	var crown := foot_c + sb * Vector3(0.0, H, 0.0)
	_frustum(stone, Transform3D(sb * Basis(Vector3.BACK, 0.32), crown + sb * Vector3(0.0, -0.25, 0.0)), 1.8, 1.25, 1.2, 0.9, 0.9)
	# a step of the same stone round its foot, half in the turf
	_frustum(stone, Transform3D(Basis(Vector3.UP, sy), Vector3(foot.x, base_y - 0.65, foot.y)), 4.4, 3.4, 3.8, 2.9, 0.75)
	await k.step()
	m.commit(stone, oroth, "HumStone", true)
	k.collider(Vector3(2.8, H, 2.0), Transform3D(sb, foot_c + sb * Vector3(0.0, H * 0.5, 0.0)), "stone")
	k.collider(Vector3(4.4, 0.95, 3.4), Transform3D(Basis(Vector3.UP, sy), Vector3(foot.x, base_y - 0.3, foot.y)), "stone")
	# the bronze: four bands, the second and third cut through and peeled, bright where the chisel went
	var bands := m.begin()
	var cut := m.begin()
	for b in 4:
		var t := 0.4 + float(b) * 0.15
		var y := H * t
		var u := clampf((t - 0.3) / 0.7, 0.0, 1.0)
		var w := lerpf(3.1, 1.8, u) + 0.08
		var dd := lerpf(2.2, 1.25, u) + 0.08
		var c := foot_c + sb * Vector3(0.0, y, 0.0)
		if b == 1 or b == 2:
			# a stub of the band either side of where it was cut away, the cut edges bright
			for sgn in [-1.0, 1.0]:
				m.block(bands, Transform3D(sb, c + sb * Vector3(float(sgn) * w * 0.33, 0.0, dd * 0.5)), Vector3(w * 0.34, 0.3, 0.05))
				m.block(cut, Transform3D(sb, c + sb * Vector3(float(sgn) * w * 0.165, 0.0, dd * 0.5 + 0.01)), Vector3(0.04, 0.3, 0.06))
		else:
			for f in 4:
				var fb := sb * Basis(Vector3.UP, float(f) * PI * 0.5)
				var depth := (dd if f % 2 == 0 else w) * 0.5 + 0.02
				m.block(bands, Transform3D(fb, c + fb * Vector3(0.0, 0.0, depth)), Vector3((w if f % 2 == 0 else dd) + 0.06, 0.3, 0.05))
	await k.step()
	m.commit(bands, bronze, "BronzeBands", true)
	m.commit(cut, bright, "CutBronze")
	k.touchable("TheStone", Vector3(foot.x, base_y + 0.6, foot.y) + Vector3(land.x, 0.0, land.y) * 2.4, "Lay a hand on the stone", "core:dialogue/hum_stone_hand", "", false)
	# the kerb: the Builders' ring of dressed blocks about the hump, half of it gone
	var kerb := m.begin()
	var n := 18
	for i in n:
		if k.rng.randf() < 0.4:
			continue
		var a := TAU * float(i) / float(n)
		var p := foot + Vector2(sin(a), cos(a)) * 12.5
		if p.dot(land) > 10.0 and absf(p.dot(side)) < 5.0:
			continue
		var tilt := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.18, 0.12))
		var g := k.on_ground(p.x, p.y, 0.15)
		m.block(kerb, Transform3D(tilt, g), Vector3(1.6, 0.8, 0.7))
		k.collider(Vector3(1.6, 0.6, 0.7), Transform3D(Basis(Vector3.UP, a), g), "stone")
	await k.step()
	m.commit(kerb, oroth, "Kerb", true)
	# the cut: two banks of spoil either side of a way from the camp to the door, plank shoring on
	# their inner faces, the door of three stones at the hump's foot
	var door_at := foot + land * 7.4
	var spoil := PoiKit.painted(5, SPOIL, 0.85, 0.9)
	for s in [-1.0, 1.0]:
		var b := foot + land * 12.5 + side * 3.7 * float(s)
		m.mound(k.on_ground(b.x, b.y, -0.5), 3.2, 1.9, spoil, "CutBank%d" % int(s + 1.0), true, 1.3, 6, 18, false, 0.1)
	var plank := m.begin()
	var cy := PoiKit.yaw_of(land)
	for s in [-1.0, 1.0]:
		for j in 4:
			var p := foot + land * (9.3 + float(j) * 1.5) + side * 1.75 * float(s)
			m.block(plank, Transform3D(Basis(Vector3.UP, cy), k.on_ground(p.x, p.y, 0.55)), Vector3(0.08, 1.2, 1.45))
			m.post(plank, p + side * 0.12 * float(s) + land * 0.7, 1.3, 0.12)
	await k.step()
	m.commit(plank, k.surface("planks", 0.7), "Shoring")
	var dg := k.on_ground(door_at.x, door_at.y)
	var db := Basis(Vector3.UP, cy)
	var frame := m.begin()
	for s in [-1.0, 1.0]:
		var jamb := dg + db * Vector3(float(s) * 1.25, 1.5, 0.0)
		m.block(frame, Transform3D(db * Basis(Vector3.BACK, float(s) * -0.04), jamb), Vector3(0.8, 3.1, 1.4))
		k.collider(Vector3(0.8, 3.1, 1.4), Transform3D(db, jamb), "stone")
	m.block(frame, Transform3D(db, dg + Vector3(0.0, 3.35, 0.0)), Vector3(3.6, 0.7, 1.6))
	# the slab slid aside, and behind it the dark
	m.block(frame, Transform3D(db * Basis(Vector3.UP, 0.15), dg + db * Vector3(2.2, 1.4, -0.5)), Vector3(1.8, 2.8, 0.35))
	await k.step()
	m.commit(frame, oroth, "BuildersDoor", true)
	var dark := m.begin()
	m.block(dark, Transform3D(db, dg + db * Vector3(0.0, 1.45, -0.45)), Vector3(1.75, 2.9, 0.1))
	m.commit(dark, PoiKit.plain(Color(0.015, 0.014, 0.016), 1.0), "TheDark")
	if interior != "":
		_builders().SITES._door(d, interior, dg + db * Vector3(0.0, 0.0, -0.3), cy + PI)
	k.marker("the_door", k.on_ground(door_at.x + land.x * 3.0, door_at.y + land.y * 3.0), true)
	# the diggers' camp beside the cut: tent, fire, windlass over the cut's head, sieve, spades, bronze
	var camp := foot + land * 18.0 + side * 8.0
	var tent := k.prop("tent")
	if tent != "":
		await k.step()
		k.place(tent, k.on_ground(camp.x + side.x * 2.5, camp.y + side.y * 2.5), PoiKit.yaw_of(-side), 1.0, true)
	var fire := k.prop("campfire")
	var fire_at := camp - side * 1.0 + land * 1.5
	if fire != "":
		k.place(fire, k.on_ground(fire_at.x, fire_at.y), 0.0, 1.0, false)
	k.light(k.on_ground(fire_at.x, fire_at.y, 0.6), Color(1.0, 0.62, 0.32), 1.6, 9.0)
	k.puffs(k.on_ground(fire_at.x, fire_at.y, 1.0), Vector3(0.2, 0.1, 0.2), 2.5, 10, Color(0.6, 0.58, 0.55, 0.35), 1.4, 5.0)
	var tools := m.begin()
	for i in 5:
		var p := camp - side * 3.6 + land * (float(i) * 0.45 - 1.0)
		var g := k.on_ground(p.x, p.y)
		var top := g + Vector3(-side.x * 0.45, 1.25, -side.y * 0.45)
		m.limb(tools, g + Vector3(0.0, 0.05, 0.0), top, 0.025)
		m.block(tools, Transform3D(Basis(Vector3.UP, cy) * Basis(Vector3.BACK, 0.35), g + Vector3(side.x * 0.08, 0.18, side.y * 0.08)), Vector3(0.24, 0.3, 0.03))
	# the sieve on its legs, and the windlass at the cut's head
	var sieve := camp + land * 4.0 - side * 1.0
	for s in [[-0.5, -0.4], [0.5, -0.4], [-0.5, 0.4], [0.5, 0.4]]:
		m.post(tools, sieve + side * float(s[0]) + land * float(s[1]), 0.8, 0.06)
	m.block(tools, Transform3D(Basis(Vector3.UP, cy), k.on_ground(sieve.x, sieve.y, 0.82)), Vector3(1.2, 0.08, 0.95))
	var wind := foot + land * 15.0
	var ends: Array = []
	for s in [-1.0, 1.0]:
		ends.append(m.post(tools, wind + side * 1.3 * float(s), 1.4, 0.14))
	var wmid: Vector3 = ((ends[0] as Vector3) + (ends[1] as Vector3)) * 0.5
	m.rod(tools, Transform3D(Basis(Vector3(land.x, 0.0, land.y), PI * 0.5), wmid + Vector3(0.0, -0.1, 0.0)), 0.11, 2.6)
	await k.step()
	m.commit(tools, k.surface("timber", 0.6), "DiggersTools")
	var heap := m.begin()
	var heap_at := camp + land * 2.5 + side * 2.0
	var hg := k.on_ground(heap_at.x, heap_at.y)
	m.block(heap, Transform3D(Basis(Vector3.UP, 0.3), hg + Vector3(0.0, 0.02, 0.0)), Vector3(2.0, 0.03, 1.5))
	m.commit(heap, PoiKit.plain(Color(0.42, 0.36, 0.28), 0.95), "Cloth")
	var scrap := m.begin()
	for i in 14:
		var p := hg + Vector3(k.rng.randf_range(-0.8, 0.8), 0.06 + k.rng.randf() * 0.12, k.rng.randf_range(-0.6, 0.6))
		m.block(scrap, Transform3D(Basis.from_euler(Vector3(k.rng.randf_range(-0.4, 0.4), k.rng.randf() * TAU, k.rng.randf_range(-0.4, 0.4))), p),
				Vector3(k.rng.randf_range(0.3, 0.7), 0.05, k.rng.randf_range(0.12, 0.3)))
	m.commit(scrap, bronze, "CutBands")
	k.marker("the_diggers_fire", k.on_ground(fire_at.x + land.x * 1.4, fire_at.y + land.y * 1.4))
	_container(d, "diggers_take", k.on_ground(heap_at.x - side.x * 1.8, heap_at.y - side.y * 1.8), cy, "core:loot/tithe_strongbox", "The Diggers' Take", "crate")
	# the bellwright's frame along the lip: five tuning bells on a beam, his handcart and his stool
	var bw := foot - side * 17.0 + land * 4.0
	var btimber := m.begin()
	var bm := m.frame(btimber, bw, PoiKit.yaw_of(side), 3.2, 2.1, 0.14)
	await k.step()
	m.commit(btimber, k.surface("timber", 0.55), "BellFrame")
	var bell := k.prop("bell_small")
	if bell != "":
		for i in 5:
			var o := Basis(Vector3.UP, PoiKit.yaw_of(side)) * Vector3((float(i) - 2.0) * 0.6, -0.35 - float(i) * 0.04, 0.0)
			k.place(bell, bm + o + Vector3(0.0, -0.25, 0.0), 0.0, 0.75 + float(i) * 0.08, false)
	k.touchable("TuningBells", bm + Vector3(0.0, -0.9, 0.0), "Strike the tuning bells", "core:dialogue/hum_stone_tuning_bells", "", false)
	var cart := k.prop("wheelbarrow")
	if cart != "":
		var cp := bw + land * 3.0
		k.place(cart, k.on_ground(cp.x, cp.y), PoiKit.yaw_of(hush), 1.0, true)
	var bstool := k.prop("stool")
	if bstool != "":
		var sp := bw + land * 1.6 + side * 0.6
		k.place(bstool, k.on_ground(sp.x, sp.y), PoiKit.yaw_of(-land), 1.0, true)
	var btent := k.prop("tent")
	var home_at := bw + land * 7.0 - side * 2.0
	if btent != "":
		await k.step()
		k.place(btent, k.on_ground(home_at.x, home_at.y), PoiKit.yaw_of(hush), 0.85, true)
	k.marker("home", k.on_ground(home_at.x + hush.x * 2.2, home_at.y + hush.y * 2.2), true)
	k.marker("the_bell_frame", k.on_ground(bw.x + land.x * 1.5, bw.y + land.y * 1.5), true)
	# on the Hush side, where they stand at night: the grass gone grey in a crescent, and the marker
	var stand := foot + hush * 13.0
	k.marker("where_they_listen", k.on_ground(stand.x, stand.y))
	await _grey_sheet(d, foot, hush, 8.0, 24.0, 1.4)
	await _builders().LAND._grass(d, "grass_clump", foot + land * 14.0, 14.0, 30)


# --- the second pass: shared hands for barrows, folds and fields -----------------------------------

## A long dome of ground on the ground: a barrow, a drift, a bank. Elliptical, `rx` along `axis` and
## `rz` across it, `height` at its crown, every vertex standing `profile * height` over the ground
## under it (so its rim lies on the land however the land goes), its rim a hand under the turf.
## Walkable when `collide`. Built at once (not deferred), as `PoiMasonry.mound` is, for its body.
static func _hump(d: PoiDressing, c: Vector2, axis: Vector2, rx: float, rz: float, height: float, mat: Material,
		node_name: String, collide := true, power := 1.4, silhouette := true, rough := 0.06, phase := NAN) -> MeshInstance3D:
	var k := d.kit
	if k.far and not silhouette:
		return null
	var ax := axis.normalized() if axis != Vector2.ZERO else Vector2(0.0, 1.0)
	# across, the way round that winds the faces as PoiMasonry.mound winds them (front side up)
	var ac := Vector2(ax.y, -ax.x)
	var rings := 8
	var segs := 28
	var ph := k.rng.randf() * TAU if is_nan(phase) else phase
	var pts: Array = []
	for i in rings + 1:
		var f := float(i) / float(rings)
		var row: Array = []
		for j in segs:
			var a := TAU * float(j) / float(segs)
			var swell := 1.0 + rough * sin(a * 3.0 + ph)
			var p := c + ax * (cos(a) * rx * f) + ac * (sin(a) * rz * f)
			var y := height * pow(maxf(1.0 - f * f, 0.0), power * 0.5) * swell - 0.12 * f * f
			row.append(k.on_ground(p.x, p.y, y))
		pts.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		for j in segs:
			var j1 := (j + 1) % segs
			st.add_vertex(pts[i][j])
			st.add_vertex(pts[i + 1][j1])
			st.add_vertex(pts[i + 1][j])
			if i > 0:
				st.add_vertex(pts[i][j])
				st.add_vertex(pts[i][j1])
				st.add_vertex(pts[i + 1][j1])
	st.generate_normals()
	var inst := MeshInstance3D.new()
	inst.mesh = st.commit()
	inst.material_override = mat
	inst.name = node_name
	k.root.add_child(inst)
	if k.far:
		k._far_range(inst)
	elif collide:
		k.collider_shape(inst.mesh.create_trimesh_shape(), Transform3D.IDENTITY, "dirt")
	return inst


## The height of a `_hump`'s crown profile at local xz `p` over the ground (0 off it).
static func _hump_y(c: Vector2, axis: Vector2, rx: float, rz: float, height: float, p: Vector2, power := 1.4) -> float:
	var ax := axis.normalized()
	var q := p - c
	var u := q.dot(ax) / rx
	var v := q.dot(Vector2(-ax.y, ax.x)) / rz
	var f2 := u * u + v * v
	if f2 >= 1.0:
		return 0.0
	return height * pow(1.0 - f2, power * 0.5)


## Ground-like stuff that must not catch the sky at a low angle (ash, ruts, a grey furrow): plain and
## fully rough, no specular.
static func _matte(c: Color) -> StandardMaterial3D:
	var mat := PoiKit.plain(c, 1.0)
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


## The height over the ground of a `_hump`'s surface at local xz `p` (one laid with `phase` given), as
## its mesh has it there to a few centimetres: what a tree on a barrow is set down on.
static func _hump_surface(c: Vector2, axis: Vector2, rx: float, rz: float, height: float, p: Vector2, power: float,
		rough: float, phase: float) -> float:
	var ax := axis.normalized()
	var ac := Vector2(ax.y, -ax.x)
	var q := p - c
	var u := q.dot(ax) / rx
	var v := q.dot(ac) / rz
	var f := sqrt(u * u + v * v)
	if f >= 1.0:
		return 0.0
	var a := atan2(v, u)
	return height * pow(maxf(1.0 - f * f, 0.0), power * 0.5) * (1.0 + rough * sin(a * 3.0 + phase)) - 0.12 * f * f


## A turf for barrows and banks: the downs' sward, a shade darker for being heaped.
static func _turf() -> ShaderMaterial:
	return PoiKit.painted(5, {"base": "#55612f", "accent": "#444e25", "grout": "#2e361a", "unit": 0.35}, 0.6)


## A sarsen: a rough grey-white slab standing, of `size`, leaning by `lean` (radians about its face),
## into `st` (the stone surface), with a body.
static func _sarsen(d: PoiDressing, st: SurfaceTool, at: Vector2, yaw: float, size: Vector3, lean := 0.0, sink := 0.4) -> void:
	var k := d.kit
	var g := k.on_ground(at.x, at.y)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean)
	# a slab tapering to a rounded head, a little off true: a stone the downs left, not a block cut
	var foot := g + b * Vector3(0.0, -sink, 0.0)
	var twist := b * Basis(Vector3.UP, k.rng.randf_range(-0.12, 0.12))
	_frustum(st, Transform3D(twist, foot), size.x, size.z, size.x * k.rng.randf_range(0.62, 0.8), size.z * k.rng.randf_range(0.7, 0.9), size.y * 0.9)
	d.masonry.ellipsoid(st, foot + b * Vector3(k.rng.randf_range(-0.08, 0.08), size.y * 0.9, 0.0),
			Vector3(size.x * 0.36, size.y * 0.13, size.z * 0.4), twist)
	k.collider(Vector3(size.x, size.y - sink, size.z), Transform3D(Basis(Vector3.UP, yaw), g + Vector3(0.0, (size.y - sink) * 0.5, 0.0)), "stone")


## The downs' sarsen stone: grey-white, lichened.
static func _sarsen_look(k: PoiKit) -> ShaderMaterial:
	return PoiKit.painted(2, {"base": "#9a968a", "accent": "#7b7a68", "grout": "#4f4d44", "unit": 1.4}, 0.85, 0.9)


## Furrows: ridges of turned earth `length` long along `along`, `n` of them `pitch` apart, from `start`
## (local xz, the first furrow's middle), into `st`; each a low ridge following the ground.
static func _furrows(d: PoiDressing, st: SurfaceTool, start: Vector2, along: Vector2, length: float, n: int, pitch: float, h := 0.22) -> void:
	var k := d.kit
	var ac := Vector2(-along.y, along.x)
	for i in n:
		var mid := start + ac * pitch * float(i)
		var steps := maxi(int(length / 2.0), 2)
		for s in steps:
			var p0 := mid + along * (length * (float(s) / float(steps) - 0.5))
			var p1 := mid + along * (length * (float(s + 1) / float(steps) - 0.5))
			var q := [k.on_ground(p0.x - ac.x * pitch * 0.5, p0.y - ac.y * pitch * 0.5, 0.02), k.on_ground(p0.x, p0.y, h),
					k.on_ground(p0.x + ac.x * pitch * 0.5, p0.y + ac.y * pitch * 0.5, 0.02),
					k.on_ground(p1.x - ac.x * pitch * 0.5, p1.y - ac.y * pitch * 0.5, 0.02), k.on_ground(p1.x, p1.y, h),
					k.on_ground(p1.x + ac.x * pitch * 0.5, p1.y + ac.y * pitch * 0.5, 0.02)]
			for idx in [0, 4, 1, 0, 3, 4, 1, 5, 2, 1, 4, 5]:
				st.add_vertex(q[idx])


## A kerb of sarsens round an ellipse (`rx` along `axis`, `rz` across), `n` places, some left out
## (`gaps` of them) and none across `keep_clear` (a local xz the kerb leaves open, with its radius).
static func _kerb(d: PoiDressing, st: SurfaceTool, c: Vector2, axis: Vector2, rx: float, rz: float, n: int, gaps := 0.25,
		keep_clear := Vector2.INF, clear_r := 0.0, size := Vector3(1.0, 1.0, 0.55)) -> void:
	var k := d.kit
	var ax := axis.normalized()
	var ac := Vector2(ax.y, -ax.x)
	for i in n:
		if k.rng.randf() < gaps:
			continue
		var a := TAU * float(i) / float(n)
		var p := c + ax * cos(a) * rx + ac * sin(a) * rz
		if keep_clear != Vector2.INF and p.distance_to(keep_clear) < clear_r:
			continue
		var out := (ax * cos(a) / rx + ac * sin(a) / rz).normalized()
		_sarsen(d, st, p, PoiKit.yaw_of(out) + PI * 0.5, size * k.rng.randf_range(0.8, 1.15), k.rng.randf_range(-0.12, 0.12), 0.3)


# --- Orm's Long Barrow ------------------------------------------------------------------------------

## A long barrow on the down, a whaleback of turf with its sarsen kerb, a yew grown on its west end.
## The robbers cut across its middle to the cist and took nothing: the raw earth of their cut, the cist
## open in it, and beside the barrow its capstones stacked as neatly as a dropped deck of cards.
static func orms_long_barrow(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var axis := k.grain()
	var across := Vector2(axis.y, -axis.x)
	var rx := 12.5
	var rz := 4.6
	var h := 2.4
	_hump(d, Vector2.ZERO, axis, rx, rz, h, _turf(), "Barrow", true, 1.4, true, 0.06, 0.0)
	await k.step()
	var stone := m.begin()
	_kerb(d, stone, Vector2.ZERO, axis, rx + 0.6, rz + 0.6, 26, 0.3, axis * (rx + 0.6), 2.0)
	# the forecourt at its east end: a shallow arc of tall stones, the entrance between the middle two
	for i in 5:
		var t := (float(i) - 2.0) / 2.0
		var p := axis * (rx + 1.2 - absf(t) * 1.4) + across * t * 3.6
		if i == 2:
			continue
		_sarsen(d, stone, p, PoiKit.yaw_of(axis), Vector3(1.3, 2.3 - absf(t) * 0.5, 0.6), k.rng.randf_range(-0.06, 0.06))
	await k.step()
	# the cist in the robbers' cut: four slabs on edge round a box of dark
	var crown := k.on_ground(0.0, 0.0).y + h
	var cb := Basis(Vector3.UP, PoiKit.yaw_of(axis))
	var cist_c := Vector3(0.0, crown - 0.45, 0.0)
	for s in [-1.0, 1.0]:
		m.block(stone, Transform3D(cb, cist_c + cb * Vector3(0.62 * float(s), 0.0, 0.0)), Vector3(0.16, 1.15, 2.0))
		m.block(stone, Transform3D(cb, cist_c + cb * Vector3(0.0, 0.0, 0.95 * float(s))), Vector3(1.4, 1.15, 0.16))
	m.commit(stone, _sarsen_look(k), "Stones", true)
	var dark := m.begin()
	m.block(dark, Transform3D(cb, cist_c + Vector3(0.0, -0.2, 0.0)), Vector3(1.1, 0.06, 1.75))
	m.commit(dark, PoiKit.plain(Color(0.05, 0.045, 0.04), 1.0), "CistFloor")
	_hump(d, Vector2.ZERO, axis, 2.0, rz * 1.02, h + 0.06, k.surface("earth", 0.6), "RobbersCut", false, 1.4, false, 0.02)
	# their spoil either side of the cut, and the capstones stacked beside the barrow, each a hand
	# round from the one under it
	for s in [-1.0, 1.0]:
		var sp := across * (rz + 1.6) * float(s) + axis * 1.2 * float(s)
		_hump(d, sp, axis, 1.8, 1.2, 0.7, k.surface("earth", 0.6), "Spoil%d" % int(s + 1.0), false, 1.6, false)
	var deck := m.begin()
	var dk := -across * (rz + 3.4) - axis * 1.5
	var dg := k.on_ground(dk.x, dk.y)
	for i in 6:
		var yaw := PoiKit.yaw_of(axis) + float(i) * 0.11
		m.block(deck, Transform3D(Basis(Vector3.UP, yaw), dg + Vector3(float(i) * 0.05, 0.14 + float(i) * 0.27, float(i) * 0.03)), Vector3(1.4, 0.26, 2.3))
	await k.step()
	m.commit(deck, _sarsen_look(k), "Capstones", true)
	k.collider(Vector3(1.6, 1.65, 2.5), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(axis)), dg + Vector3(0.0, 0.82, 0.0)), "stone")
	# the robbers' ladder still down the cist
	var lad := m.begin()
	for s in [-0.22, 0.22]:
		var o := Vector3(across.x, 0.0, across.y) * float(s)
		m.limb(lad, cist_c + o + Vector3(0.0, -0.4, 0.0), cist_c + o + Vector3(axis.x, 0.0, axis.y) * 0.9 + Vector3(0.0, 1.8, 0.0), 0.04)
	for r in 4:
		var t := 0.15 + float(r) * 0.22
		m.block(lad, Transform3D(cb, cist_c + Vector3(axis.x, 0.0, axis.y) * 0.9 * t + Vector3(0.0, -0.4 + 2.2 * t, 0.0)), Vector3(0.5, 0.04, 0.04))
	m.commit(lad, k.surface("timber", 0.6), "Ladder")
	k.touchable("TheCist", cist_c + Vector3(0.0, 0.9, 0.0), "Look into the cist", "core:dialogue/orms_cist", "", false)
	k.marker("the_cist", k.on_ground(across.x * (rz + 1.5), across.y * (rz + 1.5)))
	var yew := k.tree("yew_veteran")
	if yew == "":
		yew = k.tree("yew")
	if yew != "":
		# grown at the barrow's west end, its roots in the ditch at the mound's foot
		var yp := -axis * (rx + 1.8) + across * 0.8
		await k.step()
		k.place(yew, k.on_ground(yp.x, yp.y, -0.05), k.rng.randf() * TAU, 0.85, true)
	await _builders().LAND._grass(d, "grass_clump", Vector2.ZERO, rx + 4.0, 26)


# --- Tallow Barrow ----------------------------------------------------------------------------------

## A long barrow (the downs' own whaleback and kerb) with its forecourt of tall stones, and the way in
## between them walled up with new flint from the inside: courses laid by somebody who knew how, with
## a gap in them this spring the shape of a door, warm air coming out of the dark. The diggers' barrow
## and lantern where they dropped them in the forecourt in 1012.
static func tallow_barrow(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var axis := _facing(k)
	var across := Vector2(axis.y, -axis.x)
	var rx := 11.0
	var rz := 4.4
	var h := 2.5
	var c := -axis * 4.0
	_hump(d, c, axis, rx, rz, h, _turf(), "Barrow")
	await k.step()
	var stone := m.begin()
	var mouth := c + axis * (rx - 0.6)
	_kerb(d, stone, c, axis, rx + 0.6, rz + 0.6, 24, 0.2, mouth, 3.2)
	# the forecourt: tall stones in a horned arc out from the barrow's end
	for i in 6:
		var t := (float(i) - 2.5) / 2.5
		var p := mouth + axis * (1.0 + absf(t) * 2.2) + across * t * 4.4
		_sarsen(d, stone, p, PoiKit.yaw_of(axis) - t * 0.5, Vector3(1.2, 2.6 - absf(t) * 0.7, 0.6), k.rng.randf_range(-0.05, 0.05))
	# the jambs and lintel of the way in
	var mb := Basis(Vector3.UP, PoiKit.yaw_of(axis))
	var mg := k.on_ground(mouth.x, mouth.y)
	for s in [-1.0, 1.0]:
		m.block(stone, Transform3D(mb, mg + mb * Vector3(1.0 * float(s), 0.9, 0.2)), Vector3(0.55, 2.0, 0.8))
	m.block(stone, Transform3D(mb, mg + Vector3(0.0, 2.0, 0.0) + mb * Vector3(0.0, 0.0, 0.2)), Vector3(2.8, 0.5, 1.0))
	await k.step()
	m.commit(stone, _sarsen_look(k), "Stones", true)
	# the new wall: flint courses between the jambs, a door-shaped gap in them, the dark behind
	var flint := m.begin()
	for s in [-1.0, 1.0]:
		m.block(flint, Transform3D(mb, mg + mb * Vector3(0.52 * float(s), 0.9, 0.25)), Vector3(0.5, 1.8, 0.5))
	m.block(flint, Transform3D(mb, mg + mb * Vector3(0.0, 1.65, 0.25)), Vector3(0.6, 0.3, 0.5))
	m.commit(flint, PoiKit.painted(2, {"base": "#3a3b40", "accent": "#55565c", "grout": "#cfc8b6", "unit": 0.16}, 0.4, 0.7), "NewWall")
	for s in [-1.0, 1.0]:
		k.collider(Vector3(0.6, 1.9, 0.5), Transform3D(mb, mg + mb * Vector3(0.62 * float(s), 0.95, 0.25)), "stone")
	k.collider(Vector3(0.5, 1.6, 0.3), Transform3D(mb, mg + mb * Vector3(0.0, 0.8, -0.2)), "stone")
	var dark := m.begin()
	m.block(dark, Transform3D(mb, mg + mb * Vector3(0.0, 0.75, -0.05)), Vector3(0.56, 1.5, 0.1))
	m.commit(dark, PoiKit.plain(Color(0.02, 0.018, 0.016), 1.0), "TheGap")
	k.puffs(mg + mb * Vector3(0.0, 1.0, 0.6), Vector3(0.2, 0.4, 0.1), 1.2, 6, Color(0.9, 0.88, 0.84, 0.12), 0.9, 4.0)
	k.touchable("TheNewWall", mg + mb * Vector3(0.75, 1.1, 0.8), "Put a hand to the new wall", "core:dialogue/tallow_wall", "", false)
	k.marker("the_gap", k.on_ground(mouth.x + axis.x * 3.5, mouth.y + axis.y * 3.5))
	# what the diggers dropped when they came out: a barrow on its side, a lantern, no spades
	var wb := k.prop("wheelbarrow")
	if wb != "":
		var p := mouth + axis * 5.5 + across * 2.8
		await k.step()
		k.place(wb, k.on_ground(p.x, p.y), PoiKit.yaw_of(across) + 0.7, 1.0, true)
	var lamp := k.prop("lantern_hand")
	if lamp != "":
		var p := mouth + axis * 4.2 - across * 1.9
		k.place(lamp, k.on_ground(p.x, p.y), 1.1, 1.0, false)
	await _builders().LAND._grass(d, "cow_parsley", c, rx, 14)


# --- the Warden Barrow ------------------------------------------------------------------------------

## The first Wardens' round barrow on their own down, facing the Rest: a bowl of turf with a ditch and
## bank round it, its kerb of sarsens, and the way in on the Rest side under a lintel. Along the kerb
## either side of the way in, the nine hand-bells, each on its own oak post with an arm, that the
## youngest at the Rest rings on Tollday. A Wardens' path trodden to them.
static func warden_barrow(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var rest := PlaceRef.xz("core:place/wardens_rest")
	var face := Vector2(rest.x - k.origin.x, rest.y - k.origin.z)
	face = face.normalized() if face.length() > 1.0 and face.length() < 4000.0 else _facing(k)
	var side := Vector2(face.y, -face.x)
	var r := 8.5
	var h := 2.8
	_hump(d, Vector2.ZERO, face, r, r, h, _turf(), "Barrow", true, 1.2, true, 0.06, 0.0)
	var bank := m.begin()
	_ring_bank(d, bank, Vector2.ZERO, r + 3.2, 1.8, 0.45, 32)
	await k.step()
	m.commit(bank, _turf(), "Bank")
	var stone := m.begin()
	var door := face * (r - 0.2)
	_kerb(d, stone, Vector2.ZERO, face, r + 0.3, r + 0.3, 28, 0.1, door, 1.8, Vector3(0.9, 0.9, 0.5))
	var db := Basis(Vector3.UP, PoiKit.yaw_of(face))
	var dg := k.on_ground(door.x, door.y)
	for s in [-1.0, 1.0]:
		m.block(stone, Transform3D(db, dg + db * Vector3(0.85 * float(s), 0.85, 0.0)), Vector3(0.5, 1.9, 0.7))
	m.block(stone, Transform3D(db, dg + Vector3(0.0, 1.95, 0.0)), Vector3(2.4, 0.45, 0.9))
	await k.step()
	m.commit(stone, _sarsen_look(k), "Kerb", true)
	var dark := m.begin()
	m.block(dark, Transform3D(db, dg + db * Vector3(0.0, 0.85, -0.25)), Vector3(1.2, 1.7, 0.1))
	m.commit(dark, PoiKit.plain(Color(0.03, 0.028, 0.025), 1.0), "Doorway")
	k.collider(Vector3(1.2, 1.7, 0.3), Transform3D(db, dg + db * Vector3(0.0, 0.85, -0.3)), "stone")
	# the nine bells on their posts, in an arc along the kerb either side of the door
	var posts := m.begin()
	var bells: Array[Vector3] = []
	for i in 9:
		var a := PoiKit.yaw_of(face) + (float(i) - 4.0) * 0.21 + (0.12 if i >= 4 else -0.12) * (0.0 if i == 4 else 1.0)
		if i == 4:
			continue
		var p := Vector2(sin(a), cos(a)) * (r + 1.6)
		var top := m.post(posts, p, 1.6, 0.13)
		var arm := Vector3(sin(a), 0.0, cos(a)) * 0.45
		m.block(posts, Transform3D(Basis(Vector3.UP, a), top + arm * 0.5 + Vector3(0.0, -0.08, 0.0)), Vector3(0.08, 0.08, 0.55))
		bells.append(top + arm + Vector3(0.0, -0.32, 0.0))
	# the ninth hangs over the door from the lintel
	bells.append(dg + Vector3(0.0, 2.05, 0.0) + Vector3(face.x, 0.0, face.y) * 0.55)
	await k.step()
	m.commit(posts, k.surface("timber", 0.6), "BellPosts")
	var bell := k.prop("bell_small")
	if bell != "" and not k.far:
		for b in bells:
			k.place(bell, b, k.rng.randf() * TAU, 0.8, false)
	k.touchable("NineBells", dg + Vector3(face.x, 0.0, face.y) * 2.2 + Vector3(0.0, 1.2, 0.0), "Ring the nine bells", "core:dialogue/warden_barrow_bells", "", false)
	k.marker("the_bells", k.on_ground(door.x + face.x * 3.0, door.y + face.y * 3.0))
	# the path the youngest walks from the Rest every Tollday
	var way := m.begin()
	_track(d, way, [face * (r + 2.4), face * (r + 8.0) + side * 1.2, face * (d.pad_radius * 0.92)], 1.4)
	m.commit(way, k.surface("earth", 0.4), "WardensPath")
	var yew := k.tree("yew")
	if yew != "":
		# in the ditch behind the barrow, between the mound and its bank
		var yp := -face * (r + 1.5) + side * 1.2
		await k.step()
		k.place(yew, k.on_ground(yp.x, yp.y, -0.05), k.rng.randf() * TAU, 0.9, true)


# --- the Pinfold ------------------------------------------------------------------------------------

## Merrowby's round drystone pound by the Eastway: a ring of wall shoulder-high with a hurdle gate on
## two posts, the hand-bell hung on the gate-post for owners to ring, the hayward's board, a trough and
## hay, and in it the strays, always one more than were put there.
static func the_pinfold(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var fabric := FabricMesh.new()
	var gate := _facing(k)
	var side := Vector2(gate.y, -gate.x)
	var r := 6.5
	# keep the pound off a road through the place's middle
	var c: Vector2 = side * float(_builders()._off_the_road(k, r + 4.0, side))
	var segs := 16
	var gate_a := atan2(gate.x, gate.y)
	for i in segs:
		var a0 := gate_a + TAU * (float(i) + 0.5) / float(segs)
		var a1 := gate_a + TAU * (float(i) + 1.5) / float(segs)
		if i == segs - 1:
			continue
		_builders().LAND._dry_wall(d, fabric, c + Vector2(sin(a0), cos(a0)) * r, c + Vector2(sin(a1), cos(a1)) * r, 1.5)
	await _builders().LAND._commit_fabric(d, fabric)
	# the gate: two posts and a hurdle across the gap, the bell on the left post
	var gc := c + gate * r
	var timber := m.begin()
	var tops: Array = []
	for s in [-1.0, 1.0]:
		tops.append(m.post(timber, gc + side * 1.25 * float(s), 1.7, 0.2))
	var gb := Basis(Vector3.UP, PoiKit.yaw_of(gate))
	var gg := k.on_ground(gc.x, gc.y)
	for y in [0.35, 0.75, 1.15]:
		m.block(timber, Transform3D(gb, gg + Vector3(0.0, y, 0.0)), Vector3(2.3, 0.08, 0.06))
	for x in [-0.9, -0.3, 0.3, 0.9]:
		m.block(timber, Transform3D(gb, gg + gb * Vector3(x, 0.75, 0.0)), Vector3(0.06, 0.9, 0.06))
	k.collider(Vector3(2.3, 1.3, 0.2), Transform3D(gb, gg + Vector3(0.0, 0.65, 0.0)), "wood")
	var arm_top: Vector3 = tops[0]
	m.block(timber, Transform3D(gb, arm_top + Vector3(gate.x, 0.0, gate.y) * 0.25 + Vector3(0.0, -0.1, 0.0)), Vector3(0.07, 0.07, 0.5))
	# the hayward's board on its own post outside the gate
	var bp := gc + gate * 2.2 + side * 2.4
	var btop := m.post(timber, bp, 1.5, 0.12)
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(gate)), btop + Vector3(0.0, -0.25, 0.0)), Vector3(0.7, 0.45, 0.04))
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "Gate")
	var bell := k.prop("bell_small")
	if bell != "":
		k.place(bell, arm_top + Vector3(gate.x, 0.0, gate.y) * 0.45 + Vector3(0.0, -0.42, 0.0), 0.0, 0.8, false)
	k.touchable("PoundBell", arm_top + Vector3(gate.x, 0.0, gate.y) * 0.6 + Vector3(0.0, -0.4, 0.0), "Ring the pound-bell", "core:dialogue/pinfold_bell", "", false)
	k.touchable("PoundBoard", btop + Vector3(gate.x, 0.0, gate.y) * 0.2, "Read the hayward's board", "core:dialogue/pinfold_board", "", false)
	# a trough of stone and the hay inside the wall
	var trough_at := c - gate * (r - 1.3)
	var trough := m.begin()
	m.block(trough, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)), k.on_ground(trough_at.x, trough_at.y, 0.3)), Vector3(2.0, 0.6, 0.7))
	m.commit(trough, k.surface("stone", 0.7), "Trough")
	k.collider(Vector3(2.0, 0.6, 0.7), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)), k.on_ground(trough_at.x, trough_at.y, 0.3)), "stone")
	var hay := k.prop("hay_bale")
	if hay != "":
		var hp := c + side * (r - 1.6) - gate * 1.0
		k.place(hay, k.on_ground(hp.x, hp.y), PoiKit.yaw_of(gate) + 0.4, 1.0, true)
	if not k.far:
		var sheep := Livestock.paths_of("sheep")
		if not sheep.is_empty():
			var flock := Livestock.new()
			flock.name = "Strays"
			flock.seed_with(absi(("strays:" + d.poi_id).hash()))
			flock.keep("sheep", sheep, k.on_ground(c.x, c.y), r - 2.0, 4)
			d.add_child(flock)
	k.marker("the_gate", k.on_ground(gc.x + gate.x * 1.5, gc.y + gate.y * 1.5))


# --- Wolf Holt and Lamb's Bottom: what the wolves took back ----------------------------------------

## Small bones about a den: the forge's giant rib and vertebra made sheep-sized, scattered in the turf.
static func _den_bones(d: PoiDressing, c: Vector2, r: float, n: int) -> void:
	var k := d.kit
	if k.far:
		return
	for kind in ["bone_rib", "bone_vertebra"]:
		var path := k.rock(kind)
		if path == "":
			continue
		var full := maxf(PoiKit.height_of(path), 0.5)
		var xfs: Array = []
		for i in n:
			var a := k.rng.randf() * TAU
			var p := c + Vector2(sin(a), cos(a)) * r * sqrt(k.rng.randf())
			xfs.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.02), k.rng.randf() * TAU, (0.45 if kind == "bone_rib" else 0.18) / full,
					Vector3(PI * 0.5 + k.rng.randf_range(-0.3, 0.3), 0.0, k.rng.randf_range(-0.3, 0.3))))
		await k.step()
		k.scatter(path, xfs, false, false, false)


## A sheepfold of flint walls on the marsh edge of the West Downs, its far corner thrown down where the
## marsh came up, the shepherds' lean-to fallen in, and the wolves' den in the corner they kept: a
## scrape under the wall, bones in the nettles, a Warden's collar-bell caught on a stone.
static func wolf_holt(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var fabric := FabricMesh.new()
	var face := _facing(k)
	var side := Vector2(face.y, -face.x)
	var off: float = _builders()._off_the_road(k, 9.0, side)
	var c := side * off
	var w := 16.0
	var dpt := 11.0
	var corners: Array[Vector2] = []
	for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		corners.append(c + side * (w * 0.5 * float(s[0])) + face * (dpt * 0.5 * float(s[1])))
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if i == 2:
			# the gate side, toward the road: a gap in the middle
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_builders().LAND._dry_wall(d, fabric, a, mid - dir * 1.3, 1.4)
			_builders().LAND._dry_wall(d, fabric, mid + dir * 1.3, b, 1.4)
		elif i == 0:
			# the marsh side, thrown down for half its length
			_builders().LAND._dry_wall(d, fabric, a, a.lerp(b, 0.45), 1.4)
			_builders().LAND._dry_wall(d, fabric, a.lerp(b, 0.62), b, 0.6)
		else:
			_builders().LAND._dry_wall(d, fabric, a, b, 1.4)
	await _builders().LAND._commit_fabric(d, fabric)
	# the stones of the fallen stretch, lying out toward the marsh
	var fallen: Array = []
	var fa: Vector2 = corners[0].lerp(corners[1], 0.53)
	for i in 14:
		var p := fa + side * k.rng.randf_range(-1.6, 1.6) - face * k.rng.randf_range(0.3, 2.6)
		fallen.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.05), k.rng.randf() * TAU, k.rng.randf_range(0.22, 0.4)))
	await k.step()
	k.scatter(k.rock("boulder", 1), fallen, true)
	# the shepherds' lean-to in the far corner, its roof down on its rafters
	var lt: Vector2 = corners[1] + face * 2.0 - side * 2.0
	var timber := m.begin()
	var lb := Basis(Vector3.UP, PoiKit.yaw_of(face))
	var lg := k.on_ground(lt.x, lt.y)
	for s in [-1.2, 1.2]:
		m.post(timber, lt + side * float(s) + face * 1.0, 1.1, 0.12)
	m.block(timber, Transform3D(lb * Basis(Vector3.RIGHT, 0.55) * Basis(Vector3.BACK, 0.15), lg + Vector3(0.0, 0.8, 0.0)), Vector3(3.0, 0.08, 2.4))
	for i in 4:
		m.limb(timber, lg + lb * Vector3(-1.3 + float(i) * 0.85, 1.35, -1.0), lg + lb * Vector3(-1.2 + float(i) * 0.8, 0.05, 1.4), 0.05)
	await k.step()
	m.commit(timber, k.surface("timber", 0.75), "FallenLeanTo")
	# the den: a scrape of bare earth under the wall in the kept corner, bones in the nettles round it
	var den: Vector2 = corners[2] - face * 2.0 - side * 2.2
	var scrape := m.begin()
	m.block(scrape, Transform3D(Basis(Vector3.UP, 0.4), k.on_ground(den.x, den.y, 0.01)), Vector3(3.0, 0.03, 2.2))
	m.commit(scrape, k.surface("earth", 0.7), "Scrape")
	await _den_bones(d, den, 3.0, 9)
	k.marker("the_den", k.on_ground(den.x - side.x * 2.5, den.y - side.y * 2.5))
	# the marsh coming up to the thrown-down side
	var reed := k.flora("meadow_grass")
	if reed != "" and not k.far:
		var xfs: Array = []
		for i in 34:
			var p := c - face * (dpt * 0.5 + k.rng.randf_range(1.0, 7.0)) + side * k.rng.randf_range(-w * 0.6, w * 0.6)
			xfs.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf() * TAU, k.rng.randf_range(0.7, 1.0)))
		await k.step()
		k.scatter(reed, xfs, false, false, false)
	await _builders().LAND._grass(d, "grass_clump", c, 7.0, 22)


## A shepherd's hut of stone in a dry valley, its turf roof fallen in at one end, the down-wolves'
## den: the door's sill worn by them, the yard of bones before it, the shepherd's crook still against
## the wall with a struck name on it, and his hurdles rotting where he stacked them.
static func lambs_bottom(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var fabric := FabricMesh.new()
	var face := _facing(k)
	var side := Vector2(face.y, -face.x)
	var w := 5.6
	var dpt := 4.2
	var corners: Array[Vector2] = []
	for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		corners.append(side * (w * 0.5 * float(s[0])) + face * (dpt * 0.5 * float(s[1])))
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if i == 2:
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_builders().LAND._dry_wall(d, fabric, a, mid - dir * 0.55, 1.7)
			_builders().LAND._dry_wall(d, fabric, mid + dir * 0.55, b, 1.7)
		else:
			_builders().LAND._dry_wall(d, fabric, a, b, 1.7 if i != 3 else 1.1)
	await _builders().LAND._commit_fabric(d, fabric)
	# the roof: turf on the near half still, the far half fallen into the hut
	var g := k.on_ground(0.0, 0.0).y
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(face))
	var roof := m.begin()
	m.ellipsoid(roof, Vector3(side.x * 1.2, g + 1.75, side.y * 1.2), Vector3(1.9, 0.75, dpt * 0.62), basis)
	m.commit(roof, _turf(), "TurfRoof", true)
	k.collider(Vector3(2.6, 0.6, dpt), Transform3D(basis, Vector3(side.x * 1.2, g + 1.9, side.y * 1.2)), "dirt")
	var timber := m.begin()
	for i in 4:
		var x := -2.2 + float(i) * 0.7
		m.limb(timber, Vector3(0.0, g, 0.0) + basis * Vector3(x, 1.65, -dpt * 0.4), Vector3(0.0, g, 0.0) + basis * Vector3(x + 0.2, 0.15, dpt * 0.1), 0.06)
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "RoofTimbers")
	# the hurdles he stacked against the back wall, rotting where they lean
	var wattle := k.prop("fence_wattle")
	if wattle != "":
		for i in 2:
			var p := -face * (dpt * 0.5 + 0.55 + float(i) * 0.18) + side * (0.6 + float(i) * 0.9)
			k.place(wattle, k.on_ground(p.x, p.y), PoiKit.yaw_of(face) + PI * 0.5, 1.0, true, Vector3(-0.22, 0.0, 0.0))
	# the crook against the wall by the door
	var crook := m.begin()
	var cp := face * (dpt * 0.5 + 0.2) + side * 1.1
	var cg := k.on_ground(cp.x, cp.y)
	m.limb(crook, cg + Vector3(0.0, 0.02, 0.0), cg + Vector3(-face.x * 0.25, 1.55, -face.y * 0.25), 0.025)
	m.limb(crook, cg + Vector3(-face.x * 0.25, 1.55, -face.y * 0.25), cg + Vector3(-face.x * 0.25 + side.x * 0.15, 1.7, -face.y * 0.25 + side.y * 0.15), 0.025)
	m.commit(crook, k.surface("timber", 0.4), "Crook")
	# the yard before the door: bare earth worn by the pack, bones
	var yard := face * (dpt * 0.5 + 2.4)
	var scrape := m.begin()
	m.block(scrape, Transform3D(basis, k.on_ground(yard.x, yard.y, 0.01)), Vector3(3.4, 0.03, 2.8))
	m.commit(scrape, k.surface("earth", 0.7), "Worn")
	await _den_bones(d, yard, 3.2, 10)
	await _builders().LAND._grass(d, "cow_parsley", Vector2.ZERO, 9.0, 14)


# --- the Old Sheepwash ------------------------------------------------------------------------------

## A wash-pool walled with drystone and dammed across the dry spring-head: its floor cracked earth and
## a last puddle, the ramp the sheep were driven down with the sheep-gate still hung across it, the
## spout in the bank where the spring came out, dry, and a line of buckets carried up the hill after it.
static func old_sheepwash(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var fabric := FabricMesh.new()
	var down := k.downhill()
	if down == Vector2.ZERO:
		down = k.grain()
	var side := Vector2(down.y, -down.x)
	var w := 9.0
	var l := 6.0
	# the pool: three walls and the dam across its low side
	var c := Vector2.ZERO
	var corners: Array[Vector2] = []
	for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		corners.append(c + side * (w * 0.5 * float(s[0])) + down * (l * 0.5 * float(s[1])))
	_builders().LAND._dry_wall(d, fabric, corners[0], corners[1], 1.0)
	_builders().LAND._dry_wall(d, fabric, corners[1], corners[2], 1.0)
	_builders().LAND._dry_wall(d, fabric, corners[2], corners[3], 1.5)
	_builders().LAND._dry_wall(d, fabric, corners[3], corners[3].lerp(corners[0], 0.55), 1.0)
	await _builders().LAND._commit_fabric(d, fabric)
	# the floor: dried and cracked, a puddle left in its lowest corner
	var pool_floor := m.begin()
	m.block(pool_floor, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(down)), k.on_ground(c.x, c.y, 0.02)), Vector3(w - 0.9, 0.03, l - 0.9))
	m.commit(pool_floor, PoiKit.painted(5, {"base": "#8a7d63", "accent": "#6c6049", "grout": "#4a4132", "unit": 0.45}, 0.9), "DryFloor")
	var pud := corners[2].lerp(c, 0.35)
	var py := k.on_ground(pud.x, pud.y).y + 0.06
	m.pool(pud, 1.2, py, k.still_water(py - 0.25), "LastWater", 16)
	# the ramp the flock came down, and the sheep-gate on its posts across the top of it
	var ramp := corners[3].lerp(corners[0], 0.78) - side * 1.2
	var timber := m.begin()
	var tops: Array = []
	for s in [-1.0, 1.0]:
		tops.append(m.post(timber, ramp + down * 1.1 * float(s), 1.4, 0.16))
	var rb := Basis(Vector3.UP, PoiKit.yaw_of(side))
	var rg := k.on_ground(ramp.x, ramp.y)
	for y in [0.3, 0.7, 1.05]:
		m.block(timber, Transform3D(rb * Basis(Vector3.UP, 0.25), rg + Vector3(0.0, y, 0.0) + Vector3(side.x, 0.0, side.y) * 0.25), Vector3(0.06, 0.08, 2.0))
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "SheepGate")
	k.collider(Vector3(0.2, 1.1, 2.0), Transform3D(rb, rg + Vector3(0.0, 0.55, 0.0)), "wood")
	# the spout in the bank above the pool, dry, a lip of stone over a stain
	var spout := c - down * (l * 0.5 + 2.6)
	var sg := k.on_ground(spout.x, spout.y)
	_hump(d, spout - down * 1.6, side, 3.6, 2.4, 1.5, _turf(), "SpringBank", true, 1.2)
	var bank := m.begin()
	var spb := Basis(Vector3.UP, PoiKit.yaw_of(down))
	m.block(bank, Transform3D(spb, sg + Vector3(0.0, 0.45, 0.0) - Vector3(down.x, 0.0, down.y) * 0.3), Vector3(1.6, 0.9, 0.5))
	m.block(bank, Transform3D(spb, sg + Vector3(0.0, 0.62, 0.0) + Vector3(down.x, 0.0, down.y) * 0.1), Vector3(0.4, 0.1, 0.6))
	m.commit(bank, PoiKit.painted(2, {"base": "#55565a", "accent": "#7d7b76", "grout": "#cfc8b4", "unit": 0.2}, 0.6, 0.7), "SpringHead")
	# the buckets, set down one after another up the hill toward where the spring is now
	var bucket := k.prop("bucket")
	if bucket != "":
		var spots: Array = []
		for i in 6:
			var p := spout - down * (2.0 + float(i) * 2.6) + side * sin(float(i) * 0.9) * 1.4
			spots.append([p, k.rng.randf() * TAU])
		await _row(k, "bucket", spots, false)
	k.marker("the_spout", k.on_ground(spout.x + down.x * 2.0, spout.y + down.y * 2.0))
	await _builders().LAND._grass(d, "meadow_grass", c, 10.0, 18)


# --- the Last Field ---------------------------------------------------------------------------------

## The Southcotes' farmhouse left standing at the top of their field, its door shut, and the field
## ploughed in long furrows down toward the cliff: brown for the first half, then grey where the grey
## came up, and the plough left standing in the middle furrow where the grey begins.
static func the_last_field(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var down := k.downhill()
	if down == Vector2.ZERO:
		down = k.grain()
	var side := Vector2(down.y, -down.x)
	# the house up at the field's head, off the road through the place
	var off: float = _builders()._off_the_road(k, 8.5, side)
	var house := -down * 13.0 + side * off
	var fabric := FabricMesh.new()
	await _builders().LAND._house(d, fabric, _builders().LAND._frame(d, house, down, 7.5, 5.0), 7.5, 5.0, 1, {}, false)
	await _builders().LAND._commit_fabric(d, fabric)
	# the field: two blocks of furrows, brown then grey, running down to the pad's edge
	var brown := m.begin()
	var grey := m.begin()
	var n := 16
	var pitch := 1.2
	var start := -side * (pitch * float(n - 1) * 0.5) + side * off
	_furrows(d, brown, start - down * 3.0, down, 10.0, n, pitch, 0.32)
	_furrows(d, grey, start + down * 8.5, down, 13.0, n, pitch, 0.16)
	await k.step()
	m.commit(brown, PoiKit.painted(5, {"base": "#5a4632", "accent": "#463626", "grout": "#2e2419", "unit": 0.3}, 0.8), "Furrows")
	m.commit(grey, _matte(Color(0.19, 0.19, 0.18)), "GreyFurrows")
	# the plough in the middle furrow where the grey begins: beam, handles, share, the mould-board
	var pl := down * 2.2 + side * off
	var pg := k.on_ground(pl.x, pl.y)
	var pb := Basis(Vector3.UP, PoiKit.yaw_of(down))
	var plough := m.begin()
	m.limb(plough, pg + pb * Vector3(0.0, 0.25, -1.4), pg + pb * Vector3(0.0, 0.55, 1.2), 0.07)
	for s in [-0.3, 0.3]:
		m.limb(plough, pg + pb * Vector3(0.0, 0.3, -1.0), pg + pb * Vector3(float(s), 1.0, -1.9), 0.04)
	m.block(plough, Transform3D(pb * Basis(Vector3.RIGHT, 0.4), pg + pb * Vector3(0.0, 0.18, -0.9)), Vector3(0.12, 0.35, 0.7))
	m.block(plough, Transform3D(pb * Basis(Vector3.UP, 0.5), pg + pb * Vector3(0.18, 0.25, -0.6)), Vector3(0.04, 0.32, 0.8))
	await k.step()
	m.commit(plough, k.surface("timber", 0.7), "Plough")
	k.collider(Vector3(0.6, 0.8, 3.0), Transform3D(pb, pg + Vector3(0.0, 0.4, 0.0)), "wood")
	k.touchable("ThePlough", pg + Vector3(0.0, 0.9, 0.0), "Look at the plough", "core:dialogue/last_field_plough", "", false)
	k.marker("the_plough", k.on_ground(pl.x + side.x * 2.0, pl.y + side.y * 2.0))
	# the field's thorn hedge down its two sides, gappy where the grey has got at it
	var thorn := k.tree("hawthorn")
	if thorn != "":
		for s in [-1.0, 1.0]:
			for i in 5:
				var hp: Vector2 = start + side * (s * 1.6 + (0.0 if s < 0.0 else pitch * float(n - 1) + 3.2)) - down * 6.0 + down * float(i) * 5.0
				if (i >= 3 and k.rng.randf() < 0.5) or k.road_distance(hp) < 5.0:
					continue
				await k.step()
				k.place(thorn, k.on_ground(hp.x, hp.y), k.rng.randf() * TAU, k.rng.randf_range(0.7, 0.95), true)


# --- the Cliff Graves -------------------------------------------------------------------------------

## Rookdown's drowned in a row along the cliff's lip, each a turf mound with its headstone at the inland
## end so the dead face the Hush; the one headstone that has turned in the night to face the down. Crows
## on the stones.
static func cliff_graves(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var hush := k.downhill()
	if hush == Vector2.ZERO:
		hush = k.grain()
	var along := Vector2(hush.y, -hush.x)
	var stone := k.prop("gravestone")
	var earth := _turf()
	var perches: Array[Vector3] = []
	var turned := 7
	for i in 12:
		var p := along * (float(i) - 5.5) * 2.4 + hush * sin(float(i) * 0.7) * 0.6
		var g := k.on_ground(p.x, p.y)
		m.mound(g + Vector3(0.0, -0.12, 0.0) + Vector3(hush.x, 0.0, hush.y) * 0.8, 0.85, 0.32, earth, "Grave%d" % i, false, 1.6, 4, 12)
		var head := p - hush * 0.35
		var yaw := PoiKit.yaw_of(hush) if i != turned else PoiKit.yaw_of(-hush)
		if stone != "":
			k.place(stone, k.on_ground(head.x, head.y), yaw + k.rng.randf_range(-0.08, 0.08), k.rng.randf_range(0.9, 1.1), true)
		if i % 3 == 0:
			perches.append(k.on_ground(head.x, head.y, 1.05))
		await k.step()
	# a low wall of the Brow's flint inland of the row, so the sheep keep off them, a gap to come in by
	var fabric := FabricMesh.new()
	for s in [-1.0, 1.0]:
		var a0 := -hush * 2.4 + along * float(s) * 1.4
		var a1 := -hush * 2.4 + along * float(s) * 15.0 + hush * 1.5
		_builders().LAND._dry_wall(d, fabric, a0, a1, 0.75)
	await _builders().LAND._commit_fabric(d, fabric)
	var tp := along * (float(turned) - 5.5) * 2.4 + hush * sin(float(turned) * 0.7) * 0.6 - hush * 0.35
	k.touchable("TurnedStone", k.on_ground(tp.x, tp.y, 0.8) - Vector3(hush.x, 0.0, hush.y) * 0.6, "Read the turned headstone", "core:dialogue/cliff_graves_turned", "", false)
	k.marker("the_turned_stone", k.on_ground(tp.x - hush.x * 2.0, tp.y - hush.y * 2.0))
	_crows(d, perches, k.on_ground(0.0, 0.0, 2.0), 3)
	await _builders().LAND._grass(d, "grass_clump", Vector2.ZERO, 14.0, 20)
	var thrift := k.flora("oxeye_daisy")
	if thrift != "":
		await _builders().LAND._grass(d, "oxeye_daisy", hush * 2.5, 8.0, 14)


# --- the Chalk Cell ---------------------------------------------------------------------------------

## A hermit's cell cut into a bank of the Whitecut's chalk: a white face with a low door and one square
## window looking out over the Mere, a flagged step before the door with a bench on it facing the
## water, a loaf on the doorstone where the Vale leaves its bread, and her herbs gone wild.
static func chalk_cell(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var out := k.downhill()
	if out == Vector2.ZERO:
		out = k.grain()
	var side := Vector2(out.y, -out.x)
	var face_c := -out * 3.0
	var fg := k.on_ground(face_c.x, face_c.y)
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(out))
	# the bank: a hump of turf behind, the chalk face cut sheer on the near side
	_hump(d, -out * 6.5, side, 11.0, 6.0, 3.8, _turf(), "Bank", true, 1.0)
	var chalk := m.begin()
	for j in 7:
		var x := (float(j) - 3.0) * 1.7
		var hh := 3.3 - absf(float(j) - 3.0) * 0.28 + k.rng.randf_range(-0.12, 0.12)
		var back := 0.8 + k.rng.randf_range(-0.25, 0.3)
		m.block(chalk, Transform3D(fb * Basis(Vector3.UP, k.rng.randf_range(-0.05, 0.05)) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.05, 0.02)),
				fg + Vector3(0.0, hh * 0.5 - 0.3, 0.0) - Vector3(out.x, 0.0, out.y) * back + Vector3(side.x, 0.0, side.y) * x), Vector3(2.6, hh, 1.8))
	await k.step()
	m.commit(chalk, PoiKit.painted(5, {"base": "#d2ccbb", "accent": "#b3ab96", "grout": "#8d8572", "unit": 0.7}, 0.85, 0.9), "ChalkFace", true)
	k.collider(Vector3(11.0, 4.4, 1.8), Transform3D(fb, fg + Vector3(0.0, 1.7, 0.0) - Vector3(out.x, 0.0, out.y) * 0.8), "stone")
	# the door, ajar, and the window: dark in the white
	var dark := m.begin()
	m.block(dark, Transform3D(fb, fg + Vector3(0.0, 0.95, 0.0) + Vector3(out.x, 0.0, out.y) * 0.13 - Vector3(side.x, 0.0, side.y) * 1.2), Vector3(1.0, 1.9, 0.02))
	m.block(dark, Transform3D(fb, fg + Vector3(0.0, 2.1, 0.0) + Vector3(out.x, 0.0, out.y) * 0.13 + Vector3(side.x, 0.0, side.y) * 1.6), Vector3(0.7, 0.6, 0.02))
	m.commit(dark, PoiKit.plain(Color(0.06, 0.055, 0.05), 1.0), "Openings")
	var wood := m.begin()
	m.block(wood, Transform3D(fb * Basis(Vector3.UP, 0.6), fg + Vector3(0.0, 0.95, 0.0) + Vector3(out.x, 0.0, out.y) * 0.45 - Vector3(side.x, 0.0, side.y) * 1.55), Vector3(0.9, 1.8, 0.06))
	m.block(wood, Transform3D(fb, fg + Vector3(0.0, 1.78, 0.0) + Vector3(out.x, 0.0, out.y) * 0.18 + Vector3(side.x, 0.0, side.y) * 1.6), Vector3(0.85, 0.07, 0.12))
	m.commit(wood, k.surface("timber", 0.7), "DoorAndSill")
	# the flagged step, the doorstone with the loaf on it, the bench facing the water
	var flags := m.begin()
	for i in 6:
		var p := face_c + out * (1.3 + float(i % 2) * 1.0) + side * (float(i >> 1) - 1.0) * 1.1
		m.block(flags, Transform3D(Basis(Vector3.UP, k.rng.randf_range(-0.1, 0.1)), k.on_ground(p.x, p.y, 0.02)), Vector3(1.0, 0.08, 0.95))
	m.commit(flags, k.surface("stone", 0.7), "Flags")
	var door_stone := face_c + out * 1.0 - side * 1.2
	var loaf := k.prop("loaf")
	if loaf != "":
		k.place(loaf, k.on_ground(door_stone.x, door_stone.y, 0.07), k.rng.randf() * TAU, 1.0, false)
	k.touchable("TheDoorstone", k.on_ground(door_stone.x, door_stone.y, 0.6), "Leave something on the doorstone", "core:dialogue/chalk_cell_doorstone", "", false)
	var bench := k.prop("bench")
	if bench != "":
		var bp := face_c + out * 3.6 + side * 1.4
		k.place(bench, k.on_ground(bp.x, bp.y), PoiKit.yaw_of(out), 1.0, true)
	k.marker("the_bench", k.on_ground(face_c.x + out.x * 4.6, face_c.y + out.y * 4.6))
	await _builders().LAND._grass(d, "oxeye_daisy", face_c + out * 3.0 + side * 4.0, 3.0, 12)
	await _builders().LAND._grass(d, "cow_parsley", face_c + out * 2.0 - side * 4.5, 2.5, 8)


# --- the Turned Hut ---------------------------------------------------------------------------------

## A shepherd's hut on the Brow's west slope with the ash drifted grey against it to the eaves on the
## side that looks at the Choir, its door on the other side; round the door the ash swept back in a
## half-circle, fresh straw on the sill, and a hurdle across the way in. Somebody is keeping it.
static func turned_hut(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var fabric := FabricMesh.new()
	# the Choir is south-east of the Brow; the door turns its back on it
	var choir := PlaceRef.xz("core:place/sunken_choir")
	var to_choir := Vector2(choir.x - k.origin.x, choir.y - k.origin.z)
	to_choir = to_choir.normalized() if to_choir.length() > 1.0 and to_choir.length() < 20000.0 else Vector2(0.6, 0.8)
	var door := -to_choir
	var side := Vector2(door.y, -door.x)
	var w := 5.0
	var dpt := 3.8
	var corners: Array[Vector2] = []
	for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		corners.append(side * (w * 0.5 * float(s[0])) + door * (dpt * 0.5 * float(s[1])))
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if i == 2:
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_builders().LAND._dry_wall(d, fabric, a, mid - dir * 0.55, 1.6)
			_builders().LAND._dry_wall(d, fabric, mid + dir * 0.55, b, 1.6)
		else:
			_builders().LAND._dry_wall(d, fabric, a, b, 1.6)
	await _builders().LAND._commit_fabric(d, fabric)
	var g := k.on_ground(0.0, 0.0).y
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(door))
	var roof := m.begin()
	m.ellipsoid(roof, Vector3(0.0, g + 1.7, 0.0), Vector3(w * 0.62, 0.95, dpt * 0.66), basis)
	m.commit(roof, _turf(), "TurfRoof", true)
	k.collider(Vector3(w, 0.8, dpt), Transform3D(basis, Vector3(0.0, g + 1.95, 0.0)), "dirt")
	# the ash: drifts heaped against the Choir side to the eaves, and thinner round the ends
	var ash := _matte(Color(0.23, 0.225, 0.215))
	_hump(d, to_choir * (dpt * 0.5 + 1.4), side, 4.8, 2.6, 1.45, ash, "AshDrift", true, 2.2, true, 0.1)
	_hump(d, to_choir * 3.2 + side * 4.0, side, 2.6, 1.8, 0.6, ash, "AshDrift2", true, 2.0, false, 0.1)
	_hump(d, to_choir * 2.4 - side * 4.2, side, 2.2, 1.7, 0.45, ash, "AshDrift3", true, 2.0, false, 0.1)
	await _grey_sheet(d, Vector2.ZERO, to_choir, 2.0, 15.0, 2.2)
	# the door side: swept, a half-circle of bare earth with the ash pushed back into a rim round it
	var dp := door * (dpt * 0.5 + 1.6)
	var swept := m.begin()
	m.block(swept, Transform3D(basis, k.on_ground(dp.x, dp.y, 0.01)), Vector3(3.2, 0.03, 2.4))
	m.commit(swept, k.surface("earth", 0.5), "Swept")
	var rim := m.begin()
	for i in 9:
		var a := PoiKit.yaw_of(door) + (float(i) - 4.0) * 0.32
		var p := dp + Vector2(sin(a), cos(a)) * 2.1
		m.ellipsoid(rim, k.on_ground(p.x, p.y, -0.05), Vector3(0.6, 0.22, 0.4), Basis(Vector3.UP, a))
	m.commit(rim, ash, "SweptRim")
	var hay := k.prop("hay_bale")
	if hay != "":
		var hp := door * (dpt * 0.5 + 0.6) + side * 1.6
		k.place(hay, k.on_ground(hp.x, hp.y), PoiKit.yaw_of(side), 0.7, true)
	var hurdle := m.begin()
	var hpos := door * (dpt * 0.5 + 0.35)
	m.block(hurdle, Transform3D(basis * Basis(Vector3.RIGHT, -0.12), k.on_ground(hpos.x, hpos.y, 0.6)), Vector3(1.2, 1.1, 0.06))
	m.commit(hurdle, k.surface("timber", 0.6), "Hurdle")
	k.marker("the_door", k.on_ground(dp.x + door.x * 1.4, dp.y + door.y * 1.4))


# --- the Malting Floor ------------------------------------------------------------------------------

## The roofless malting house (the ruin's own hall), and on its flagged floor this spring's barley come
## up between the flags in the shape of a man lying on his back.
static func malting_floor(d: PoiDressing) -> void:
	await _builders().ruins(d)
	var k := d.kit
	var path := k.flora("barley_tuft")
	if path == "" or k.far:
		return
	var grain := k.grain()
	var perp := Vector2(-grain.y, grain.x)
	var off: float = _builders()._off_the_road(k, 7.0 * 0.5 + 4.0, perp)
	var c := perp * off
	var a := grain
	var b := Vector2(a.y, -a.x)
	# a body of barley: head, trunk, two arms out a little, two legs
	var shape: Array[Vector2] = []
	# in the far room, past the cross wall, clear of the hearth
	var c2 := c + a * 3.6
	for i in 6:
		shape.append(c2 + a * 0.8 * 2.6 + Vector2(sin(float(i)), cos(float(i))) * 0.3)
	for i in 14:
		shape.append(c2 + a * 0.8 * (2.0 - float(i) * 0.14) + b * k.rng.randf_range(-0.35, 0.35))
	for s in [-1.0, 1.0]:
		for i in 6:
			shape.append(c2 + a * 0.8 * (1.6 - float(i) * 0.2) + b * float(s) * (0.5 + float(i) * 0.16))
		for i in 9:
			shape.append(c2 + a * 0.8 * (0.0 - float(i) * 0.22) + b * float(s) * (0.25 + float(i) * 0.04))
	var xfs: Array = []
	for p in shape:
		xfs.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf() * TAU, k.rng.randf_range(0.6, 0.85)))
	await k.step()
	k.scatter(path, xfs, false, false, false)
	k.marker("the_barley_man", k.on_ground(c2.x + b.x * 2.0, c2.y + b.y * 2.0))


# --- single stones that were three -----------------------------------------------------------------

## One of the forge's standing stones, made tall, set with its packing stones, facing `yaw`.
static func _one_stone(d: PoiDressing, at: Vector2, yaw: float, height_m: float, tilt := Vector3.ZERO) -> float:
	var k := d.kit
	var path := k.rock("standing_stone")
	if path == "":
		return 0.0
	var s := height_m / maxf(PoiKit.height_of(path), 0.5)
	await k.step()
	k.place(path, k.on_ground(at.x, at.y), yaw, s, true, tilt, true)
	var packing: Array = []
	for j in 6:
		var q := at + Vector2(sin(TAU * float(j) / 6.0), cos(TAU * float(j) / 6.0)) * k.rng.randf_range(0.8, 1.2)
		packing.append(PoiKit.transform_at(k.on_ground(q.x, q.y, -0.08), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.12, 0.2)))
	await k.step()
	k.scatter(k.rock("boulder"), packing)
	return s


## The Roll Stone: one stone at the foot of Wardens' Down, the four quiet villages cut down its face
## and each struck through, and room left under them; candle stubs and a Warden's bench before it.
static func roll_stone(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(face.y, -face.x)
	var off: float = _builders()._off_the_road(k, 3.5, side)
	var at := side * off
	await _one_stone(d, at, PoiKit.yaw_of(face), 4.2)
	# the names: four cut lines down the face, a struck stroke through each, and the bare stone under
	var cut := m.begin()
	var g := k.on_ground(at.x, at.y)
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(face))
	for i in 4:
		var y := 2.35 - float(i) * 0.32
		m.block(cut, Transform3D(fb, g + Vector3(0.0, y, 0.0) + Vector3(face.x, 0.0, face.y) * 0.36), Vector3(0.62 - float(i % 2) * 0.1, 0.07, 0.03))
		m.block(cut, Transform3D(fb * Basis(Vector3.BACK, 0.12), g + Vector3(0.0, y, 0.0) + Vector3(face.x, 0.0, face.y) * 0.37), Vector3(0.78, 0.02, 0.03))
	m.commit(cut, PoiKit.plain(Color(0.28, 0.27, 0.25), 0.95), "StruckNames")
	k.touchable("TheNames", g + Vector3(0.0, 1.8, 0.0) + Vector3(face.x, 0.0, face.y) * 0.8, "Read the names on the stone", "core:dialogue/roll_stone_names", "", false)
	var stubs: Array = []
	for i in 9:
		var p := at + face * k.rng.randf_range(0.7, 1.3) + side * k.rng.randf_range(-0.8, 0.8)
		stubs.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf() * TAU, k.rng.randf_range(0.9, 1.3)))
	await k.step()
	k.scatter(k.prop("candle_stub"), stubs, false, false, false)
	k.light(k.on_ground(at.x + face.x, at.y + face.y, 0.3), Color(1.0, 0.76, 0.5), 0.8, 4.0)
	var bench := k.prop("bench")
	if bench != "":
		var bp := at + face * 3.6
		k.place(bench, k.on_ground(bp.x, bp.y), PoiKit.yaw_of(-face), 1.0, true)
	k.marker("the_stone", k.on_ground(at.x + face.x * 2.2, at.y + face.y * 2.2))
	await _builders().LAND._grass(d, "poppy", at, 3.5, 12)


## The Hare Stone: the boundary between the Vale and the Wold, one stone with a hare cut on its Vale
## face and an oak leaf on its Wold face, both worn smooth where every carter going over has put his
## hand; the boundary hedge running off from it both ways, a gap where the road goes through.
static func hare_stone(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var tamwick := PlaceRef.xz("core:place/tamwick")
	var vale := Vector2(tamwick.x - k.origin.x, tamwick.y - k.origin.z)
	vale = vale.normalized() if vale.length() > 1.0 and vale.length() < 20000.0 else _facing(k)
	var along := Vector2(vale.y, -vale.x)
	# the stone: a dressed slab of the downs' sarsen, its broad faces to the Vale and the Wold
	var g := k.on_ground(0.0, 0.0)
	var vb := Basis(Vector3.UP, PoiKit.yaw_of(vale))
	var slab := m.begin()
	_frustum(slab, Transform3D(vb * Basis(Vector3.BACK, 0.03), g + Vector3(0.0, -0.25, 0.0)), 1.05, 0.56, 0.78, 0.4, 2.65)
	m.commit(slab, _sarsen_look(k), "HareStone", true)
	k.collider(Vector3(1.0, 2.4, 0.55), Transform3D(vb, g + Vector3(0.0, 1.2, 0.0)), "stone")
	var packing: Array = []
	for j in 6:
		var q := Vector2(sin(TAU * float(j) / 6.0), cos(TAU * float(j) / 6.0)) * k.rng.randf_range(0.8, 1.1)
		packing.append(PoiKit.transform_at(k.on_ground(q.x, q.y, -0.08), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.12, 0.2)))
	await k.step()
	k.scatter(k.rock("boulder"), packing)
	# the hare on the Vale face and the leaf on the Wold face, cut shallow and rubbed pale by hands:
	# each sits a hair proud of its face (the face's half depth where it is cut, the slab tapering)
	var face_at := func(y: float) -> float: return lerpf(0.28, 0.2, (y + 0.25) / 2.65) + 0.004
	var worn := m.begin()
	var vz := Vector3(vale.x, 0.0, vale.y)
	m.ellipsoid(worn, g + Vector3(0.0, 1.1, 0.0) + vz * face_at.call(1.1), Vector3(0.22, 0.13, 0.012), vb)
	m.ellipsoid(worn, g + Vector3(0.0, 1.27, 0.0) + vz * face_at.call(1.27) + vb * Vector3(0.2, 0.0, 0.0), Vector3(0.09, 0.08, 0.012), vb)
	for e in [0.0, 0.06]:
		m.ellipsoid(worn, g + Vector3(0.0, 1.43, 0.0) + vz * face_at.call(1.43) + vb * Vector3(0.18 + e, 0.0, 0.0), Vector3(0.025, 0.11, 0.012), vb * Basis(Vector3.BACK, -0.3 - e * 3.0))
	m.ellipsoid(worn, g + Vector3(0.0, 1.15, 0.0) - vz * face_at.call(1.15), Vector3(0.12, 0.26, 0.012), vb)
	for i in 3:
		for e in [-1.0, 1.0]:
			var y := 1.0 + float(i) * 0.14
			m.ellipsoid(worn, g + Vector3(0.0, y, 0.0) - vz * face_at.call(y) + vb * Vector3(float(e) * 0.11, 0.0, 0.0), Vector3(0.07, 0.05, 0.012), vb)
	m.commit(worn, PoiKit.plain(Color(0.78, 0.76, 0.7), 0.35), "WornCarvings")
	var front := vz * 0.3
	k.touchable("TheHare", g + Vector3(0.0, 1.2, 0.0) + front * 3.0, "Put your hand on the hare", "core:dialogue/hare_stone_hare", "", false)
	# the boundary either way, a low wall with a thorn grown in it, the gap where the road goes over
	var fabric := FabricMesh.new()
	for sgn in [-1.0, 1.0]:
		var a0: Vector2 = along * float(sgn) * 1.6
		var a1: Vector2 = along * float(sgn) * 12.0 + vale * float(sgn) * 0.6
		if k.road_distance(a0.lerp(a1, 0.5)) > 4.0:
			_builders().LAND._dry_wall(d, fabric, a0, a1, 0.9)
	await _builders().LAND._commit_fabric(d, fabric)
	var thorn := k.tree("hawthorn")
	if thorn != "":
		for sgn in [-1.0, 1.0]:
			var tp: Vector2 = along * float(sgn) * 7.5 + vale * 0.9
			if k.road_distance(tp) > 4.0:
				await k.step()
				k.place(thorn, k.on_ground(tp.x, tp.y), k.rng.randf() * TAU, 0.75, true)
	k.marker("the_boundary", k.on_ground(vale.x * 2.5, vale.y * 2.5))
	await _builders().LAND._grass(d, "buttercup", vale * 4.0, 3.0, 10)
	await _builders().LAND._grass(d, "grass_clump", -vale * 4.0, 3.0, 10)


## The Weighing Stone: a great slab laid on three stones, a table the height of a cart's bed, and on
## it the carters' weighing-beam on its post: a long oak beam, a hook and chains at the short end, a
## stone weight hung at the long, the notches of the weights cut along it. A cart drawn up to be weighed.
static func the_weighing_stone(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := _facing(k)
	var side := Vector2(face.y, -face.x)
	var off: float = _builders()._off_the_road(k, 4.0, side)
	var c := side * off
	var g := k.on_ground(c.x, c.y)
	var stone := m.begin()
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(side))
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.4
		var p := c + Vector2(sin(a), cos(a)) * 1.25
		_sarsen(d, stone, p, a, Vector3(0.7, 1.4, 0.6), 0.0, 0.25)
	var top := g.y + 1.22
	m.block(stone, Transform3D(fb * Basis(Vector3.BACK, 0.03), Vector3(c.x, top + 0.2, c.y)), Vector3(3.6, 0.4, 2.4))
	k.collider(Vector3(3.6, 0.4, 2.4), Transform3D(fb, Vector3(c.x, top + 0.2, c.y)), "stone")
	await k.step()
	m.commit(stone, _sarsen_look(k), "Table", true)
	# the beam on its post, a hook and chains one end, the weight the other
	var timber := m.begin()
	var post_foot := Vector3(c.x, top + 0.4, c.y)
	var pivot := post_foot + Vector3(0.0, 2.1, 0.0)
	m.block(timber, Transform3D(fb, post_foot + Vector3(0.0, 1.05, 0.0)), Vector3(0.22, 2.1, 0.22))
	var beam_b := fb * Basis(Vector3.BACK, 0.06)
	m.block(timber, Transform3D(beam_b, pivot + beam_b * Vector3(0.9, 0.0, 0.0)), Vector3(4.6, 0.18, 0.16))
	var short_end := pivot + beam_b * Vector3(-1.2, 0.0, 0.0)
	var long_end := pivot + beam_b * Vector3(3.0, 0.0, 0.0)
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "Beam", true)
	var iron := m.begin()
	for s in [-0.15, 0.15]:
		m.limb(iron, short_end, short_end + Vector3(0.0, -1.3, 0.0) + Vector3(side.x, 0.0, side.y) * float(s), 0.015)
	m.block(iron, Transform3D(fb, short_end + Vector3(0.0, -1.35, 0.0)), Vector3(0.5, 0.05, 0.05))
	m.limb(iron, long_end, long_end + Vector3(0.0, -0.9, 0.0), 0.015)
	for i in 10:
		m.block(iron, Transform3D(beam_b, pivot + beam_b * Vector3(0.3 + float(i) * 0.25, 0.1, 0.0)), Vector3(0.015, 0.06, 0.17))
	m.commit(iron, PoiKit.plain(IRON, 0.6, 0.5), "Chains")
	var weight := m.begin()
	_frustum(weight, Transform3D(fb, long_end + Vector3(0.0, -1.4, 0.0)), 0.5, 0.42, 0.34, 0.3, 0.5)
	m.commit(weight, _sarsen_look(k), "Weight")
	k.touchable("TheBeam", Vector3(c.x, top + 1.0, c.y) + Vector3(face.x, 0.0, face.y) * 1.6, "Read the weights cut on the beam", "core:dialogue/weighing_stone_beam", "", false)
	var cart := k.prop("cart")
	if cart != "":
		var cp := c + face * 4.5 + side * 2.5
		await k.step()
		k.place(cart, k.on_ground(cp.x, cp.y), PoiKit.yaw_of(side), 1.0, true)
	var sacks: Array = []
	for i in 4:
		sacks.append([c - face * 2.4 + side * (float(i) - 1.5) * 0.7, k.rng.randf() * TAU])
	await _row(k, "sack", sacks, true)
	k.marker("the_table", k.on_ground(c.x + face.x * 2.8, c.y + face.y * 2.8))


## Sets a placed piece down on the lowest ground under its footprint (`r` metres round its foot), so
## on a slope no edge of it stands in the air.
static func _seat_low(k: PoiKit, node: Node3D, r: float, sink := 0.03) -> void:
	if node == null:
		return
	var p := node.position
	var low := k.on_ground(p.x, p.z).y
	for i in 6:
		var a := TAU * float(i) / 6.0
		low = minf(low, k.on_ground(p.x + sin(a) * r, p.z + cos(a) * r).y)
	node.position.y = low - sink


# --- the Hush Steps ---------------------------------------------------------------------------------

## The Builders' steps down the Brow's face (the ruin's own colonnade), with the rope that was tied to
## the last dry step set down on the stone rather than in the air, and the lantern on the last step
## tied with a Sedgish lantern-knot, as the hook says.
static func hush_steps(d: PoiDressing) -> void:
	await _builders().ruins(d)
	var k := d.kit
	if k.far:
		return
	var post: Node3D = null
	for c in d.get_children():
		if c is Node3D and str(c.name).contains("rope_coil"):
			_seat_low(k, c as Node3D, 0.45)
		elif c is Node3D and str(c.name).contains("dock_post"):
			post = c as Node3D
	var lamp := k.prop("lantern_hand")
	if lamp != "" and post != null:
		var at := post.position + Vector3(0.0, 0.0, 0.0)
		var lp := k.place(lamp, Vector3(at.x + 0.45, k.on_ground(at.x + 0.45, at.z).y, at.z), 0.4, 1.0, false)
		_seat_low(k, lp, 0.15)
		if lp != null:
			k.light(lp.position + Vector3(0.0, 0.35, 0.0), Color(1.0, 0.78, 0.5), 0.9, 5.0)


# --- three wayside Hearthstones, each its own ------------------------------------------------------

## Candle Cross: the shrine's own Hearthstone, and at the crossing a square pillar with a candle niche
## cut in each of its four faces, a candle burning in each, one for each way a traveller came from.
static func candle_cross(d: PoiDressing) -> void:
	await _builders().shrine(d)
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var side := Vector2(grain.y, -grain.x)
	var at := side * 3.2 + grain * 0.4
	var g := k.on_ground(at.x, at.y)
	var pb := Basis(Vector3.UP, PoiKit.yaw_of(grain))
	var pillar := m.begin()
	m.block(pillar, Transform3D(pb, g + Vector3(0.0, 1.05, 0.0)), Vector3(0.75, 2.3, 0.75))
	m.block(pillar, Transform3D(pb, g + Vector3(0.0, 2.3, 0.0)), Vector3(0.95, 0.2, 0.95))
	m.block(pillar, Transform3D(pb, g + Vector3(0.0, 0.08, 0.0)), Vector3(1.1, 0.25, 1.1))
	m.commit(pillar, k.surface("stone", 0.7), "CrossPillar", true)
	k.collider(Vector3(0.8, 2.4, 0.8), Transform3D(pb, g + Vector3(0.0, 1.2, 0.0)), "stone")
	var niche := m.begin()
	var candle := k.prop("candle")
	for i in 4:
		var n := pb * (Basis(Vector3.UP, float(i) * PI * 0.5) * Vector3(0.0, 0.0, 0.36))
		m.block(niche, Transform3D(pb * Basis(Vector3.UP, float(i) * PI * 0.5), g + Vector3(0.0, 1.45, 0.0) + n), Vector3(0.34, 0.42, 0.06))
		if candle != "":
			k.place(candle, g + Vector3(0.0, 1.26, 0.0) + n * 0.78, 0.0, 1.0, false)
	m.commit(niche, PoiKit.plain(SOOT, 0.95), "Niches")
	k.light(g + Vector3(0.0, 1.5, 0.0), Color(1.0, 0.76, 0.48), 1.0, 5.0)


## The Naming Stone: the shrine's own, and before its stone the step the children stand on to be
## named, the hollows of small hands worn in the stone's face at a child's height, and the naming
## ribbons tied in the hawthorn beside it, one for every child named here this spring.
static func the_naming_stone(d: PoiDressing) -> void:
	await _builders().shrine(d)
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var side := Vector2(grain.y, -grain.x)
	var stone_at := -grain * 1.2
	var g := k.on_ground(stone_at.x, stone_at.y)
	var step := m.begin()
	var sp := stone_at + grain * 0.9
	m.block(step, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(grain)), k.on_ground(sp.x, sp.y, 0.1)), Vector3(1.0, 0.22, 0.6))
	m.commit(step, k.surface("stone", 0.9), "NamingStep")
	k.collider(Vector3(1.0, 0.22, 0.6), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(grain)), k.on_ground(sp.x, sp.y, 0.1)), "stone")
	var hands := m.begin()
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(grain))
	for i in 7:
		var o := fb * Vector3(k.rng.randf_range(-0.3, 0.3), 0.75 + k.rng.randf_range(-0.12, 0.15), 0.32)
		m.ellipsoid(hands, g + o, Vector3(0.06, 0.08, 0.02), fb)
	m.commit(hands, PoiKit.plain(Color(0.88, 0.86, 0.8), 0.3), "WornHands")
	k.touchable("SmallHands", g + Vector3(0.0, 0.8, 0.0) + Vector3(grain.x, 0.0, grain.y) * 0.9, "Put your hand where the children put theirs", "core:dialogue/naming_stone_hands", "", false)
	var thorn := k.tree("hawthorn")
	var tp := stone_at + side * 3.4 - grain * 0.6
	if k.road_distance(tp) < 5.0:
		tp = stone_at - side * 3.4 - grain * 0.6
	if thorn == "" or k.road_distance(tp) < 5.0:
		return
	await k.step()
	k.place(thorn, k.on_ground(tp.x, tp.y), k.rng.randf() * TAU, 1.0, true)
	var rib := m.begin()
	var colours := m.begin()
	for i in 12:
		var a := k.rng.randf() * TAU
		var p := k.on_ground(tp.x, tp.y, k.rng.randf_range(1.4, 2.4)) + Vector3(sin(a), 0.0, cos(a)) * k.rng.randf_range(0.5, 1.1)
		m.block(rib if i % 2 == 0 else colours, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.BACK, k.rng.randf_range(-0.2, 0.2)), p + Vector3(0.0, -0.18, 0.0)), Vector3(0.04, 0.36, 0.005))
	m.commit(rib, PoiKit.plain(Color(0.78, 0.2, 0.18), 0.8), "RibbonsRed")
	m.commit(colours, PoiKit.plain(Color(0.85, 0.72, 0.25), 0.8), "RibbonsGold")


## The Southgate Stone: the shrine's own, facing the Briar's shut south gate, and the old cart way east
## from it toward the gate: two ruts worn deep in the turf, grassing over, running out to nothing, a
## wheel off a cart that tried it last lying in them.
static func southgate_stone(d: PoiDressing) -> void:
	await _builders().shrine(d)
	var k := d.kit
	# the road the carts took ends at the stone: the shrine's own standing stone is set back off its
	# carriageway onto the verge, which way is further from the road
	var road_dir := k.road_direction(20.0)
	for c in d.get_children():
		if not (c is Node3D) or not str(c.name).contains("standing_stone"):
			continue
		var n3 := c as Node3D
		var at := Vector2(n3.position.x, n3.position.z)
		if road_dir == Vector2.ZERO or k.road_distance(at) >= 3.5:
			continue
		var perp := Vector2(road_dir.y, -road_dir.x)
		var best := at
		for step in range(1, 13):
			for sgn in [-1.0, 1.0]:
				var q: Vector2 = at + perp * float(sgn) * 0.5 * float(step)
				if k.road_distance(q) >= 3.5 and best == at:
					best = q
			if best != at:
				break
		n3.position = k.on_ground(best.x, best.y) - Vector3(0.0, PoiKit.buried_m(k.rock("standing_stone")) * n3.scale.y, 0.0)
	var m := d.masonry
	var east := Vector2(1.0, 0.0)
	var across := Vector2(0.0, 1.0)
	var road := k.road_direction(30.0)
	var start := east * 5.0 + across * (6.0 if road == Vector2.ZERO or absf(road.dot(across)) < 0.7 else 0.0)
	var ruts := m.begin()
	for s in [-0.75, 0.75]:
		var pts: Array = []
		for i in 6:
			pts.append(start + across * float(s) + east * float(i) * 3.2 + across * sin(float(i) * 0.5) * 0.5)
		_track(d, ruts, pts, 0.38)
	await k.step()
	m.commit(ruts, _matte(Color(0.27, 0.23, 0.17)), "OldRuts")
	var wood := m.begin()
	var wheel_at := start + east * 12.0 + across * 0.9
	var wg := k.on_ground(wheel_at.x, wheel_at.y)
	for i in 12:
		var a := TAU * (float(i) + 0.5) / 12.0
		m.block(wood, Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.UP, a), wg + Vector3(0.0, 0.08, 0.0) + Basis(Vector3.UP, 0.4) * Vector3(sin(a) * 0.62, 0.0, cos(a) * 0.62)), Vector3(0.36, 0.08, 0.09))
	for i in 6:
		var a := TAU * float(i) / 6.0
		m.limb(wood, wg + Vector3(0.0, 0.1, 0.0), wg + Vector3(0.0, 0.1, 0.0) + Basis(Vector3.UP, 0.4) * Vector3(sin(a) * 0.6, 0.0, cos(a) * 0.6), 0.035)
	m.commit(wood, k.surface("timber", 0.8), "LostWheel")
	await _builders().LAND._grass(d, "grass_clump", start + east * 8.0, 6.0, 18)



# --- the second pass's mending: things that stood in each other ------------------------------------

## The things a builder sets down that can be moved a little without changing what a place is.
const MOVABLE := ["barrel", "crate", "sack", "chopping_block", "wheelbarrow", "bucket", "jug", "basket",
		"bell_small", "gravestone", "boulder", "bench", "stool", "hay_bale", "cart"]


## The footprint of a placed asset in the dressing's xz, from its meshes: [centre, half x, half z].
static func _footprint(n: Node3D) -> Array:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		var t := Transform3D.IDENTITY
		var cur: Node = m3
		while cur != null and cur != n:
			if cur is Node3D:
				t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		var b := (n.transform * t) * m3.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return [Vector2(n.position.x, n.position.z), 0.3, 0.3]
	var c := box.get_center()
	return [Vector2(c.x, c.z), box.size.x * 0.5, box.size.z * 0.5]


## Whether a placed asset's name says it is one of `MOVABLE`.
static func _movable(nm: String) -> bool:
	for kind in MOVABLE:
		if nm.contains("_" + kind + "_"):
			return true
	return false


## Parts the props a builder set into one another (the seat audit's `overlap`: a chopping block in a
## barrel, a barrel in an apple tree's crown, a bell in a standing stone): each movable thing whose
## foot is inside another placed thing's footprint is walked out of it, away from that thing's
## middle, to clear ground, and set down there. The other is left where it stands.
static func _part_props(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		return
	var things: Array[Node3D] = []
	for c in d.get_children():
		if c is Node3D and not (c is MeshInstance3D) and str(c.name).contains("_") and c.get_child_count() > 0:
			things.append(c as Node3D)
	var feet := {}
	for n in things:
		feet[n] = _footprint(n)
	for n in things:
		if not _movable(str(n.name)):
			continue
		for pass_i in 3:
			var mine: Array = feet[n]
			var moved := false
			for o in things:
				if o == n:
					continue
				var theirs: Array = feet[o]
				var oc: Vector2 = theirs[0]
				var ohx: float = theirs[1]
				var ohz: float = theirs[2]
				var mc: Vector2 = mine[0]
				var mr := maxf(float(mine[1]), float(mine[2]))
				# the share of mine inside theirs: only a real overlap is mended
				if absf(mc.x - oc.x) > ohx + mr * 0.2 or absf(mc.y - oc.y) > ohz + mr * 0.2:
					continue
				var away := mc - oc
				away = away.normalized() if away.length() > 0.05 else Vector2(1.0, 0.0)
				var reach := Vector2(absf(away.x) * ohx, absf(away.y) * ohz).length() + mr + 0.25
				var to := oc + away * reach
				var shift := to - mc
				n.position = k.on_ground(n.position.x + shift.x, n.position.z + shift.y) - Vector3(0.0, PoiKit.buried_m(str(n.scene_file_path)) * n.scale.y, 0.0)
				feet[n] = [to, mine[1], mine[2]]
				mine = feet[n]
				moved = true
			if not moved:
				break


## A builder that is its kind's, with the props parted after.
static func _kind_then_part(d: PoiDressing, kind_builder: Callable) -> void:
	await kind_builder.call(d)
	_part_props(d)


## Bell Meadow Stones: the kind's three leaning stones and the bronze, the Toll's bell out of the stone.
static func bell_meadow_stones(d: PoiDressing) -> void:
	await _kind_then_part(d, Callable(_builders(), "standing_stones"))


## Ansel's Hedge Shrine: the kind's stone chair and hawthorn, its gravestones out of the thorn.
static func hedge_shrine_of_ansel(d: PoiDressing) -> void:
	await _kind_then_part(d, Callable(_builders(), "shrine"))


## Pennywort Fields and Southgate Farm: the kind's farmstead, its yard's things out of each other.
static func pennywort_fields(d: PoiDressing) -> void:
	await _kind_then_part(d, Callable(_builders().LAND, "farmstead"))


static func southgate_farm(d: PoiDressing) -> void:
	await _kind_then_part(d, Callable(_builders().LAND, "farmstead"))
