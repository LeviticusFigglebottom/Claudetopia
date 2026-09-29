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
	await _builders().LAND.quarry(d)
	var k := d.kit
	var m := d.masonry
	var face := k.downhill()
	if face == Vector2.ZERO:
		face = k.grain()
	var side := Vector2(face.y, -face.x)
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
		m.block(flint, Transform3D(basis, g + Vector3(0.0, 3.55, 0.0)), Vector3(4.8, 0.3, 4.8))
		k.puffs(g + Vector3(0.0, 4.0, 0.0), Vector3(0.6, 0.2, 0.6), 4.5, 12, Color(0.86, 0.85, 0.82, 0.35), 2.0, 6.0)
		k.light(mouth + basis * Vector3(0.0, 0.0, 0.8), Color(1.0, 0.55, 0.25), 1.6, 7.0)
		await k.step()
	m.commit(flint, PoiKit.painted(0, {"base": "#bdb8ac", "accent": "#5e5a55", "grout": "#3b3935", "unit": 0.22}, 0.8, 0.8), "Kilns")
	m.commit(dark, PoiKit.plain(SOOT, 0.95), "DrawArches")
	m.commit(glow, PoiKit.plain(Color(0.4, 0.12, 0.03), 0.8, 0.0, Color(1.0, 0.42, 0.12), 2.2), "KilnFire")
	# lime heaped between the kilns, and the sacks of it
	var lime := PoiKit.plain(CHALK, 0.95)
	for i in 3:
		var p := face * (10.5 + float(i) * 1.6) + side * (float(i) - 1.0) * 1.9
		m.mound(k.on_ground(p.x, p.y, -0.1), 1.3 - float(i) * 0.2, 0.8, lime, "LimeHeap%d" % i, false)
	await k.step()
	var sacks: Array = []
	for i in 6:
		var p := face * 12.5 - side * (2.5 + float(i % 3) * 0.7) + face * float(i / 3) * 0.7
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
	var step_m := 3.1
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
	m.mound(fg + Vector3(0.0, -0.15, 0.0), 2.4, 0.55, k.surface("earth", 0.4), "BellMound", false)
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
		var again := lean * 7.5 + across * 0.8
		await k.step()
		k.place(old, k.on_ground(again.x, again.y), PoiKit.yaw_of(lean) + 2.2, 1.05, true, Vector3.ZERO, true)
	# the limb along the ground between them, bark-dark, with the turf over its back
	var bark := m.begin()
	var a := k.on_ground(lean.x * 1.0, lean.y * 1.0, 0.35)
	var b := k.on_ground(lean.x * 6.8 + across.x * 0.7, lean.y * 6.8 + across.y * 0.7, 0.3)
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
		var p := -lean * 3.2 + across * (float(i) - 1.5) * 0.8
		baskets.append([p, k.rng.randf() * TAU])
	await _row(k, "basket", baskets, false)
	var barrel := k.prop("barrel")
	if barrel != "":
		var p := -lean * 4.5 + across * 2.6
		k.place(barrel, k.on_ground(p.x, p.y), 0.0, 1.0, true)
	k.marker("the_mother", k.on_ground(-lean.x * 2.4 - across.x * 1.8, -lean.y * 2.4 - across.y * 1.8), true)
	k.marker("the_windfalls", k.on_ground(lean.x * 4.0 + across.x * 3.5, lean.y * 4.0 + across.y * 3.5))
	await _builders().LAND._grass(d, "meadow_grass", Vector2.ZERO, 14.0, 26)


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
	var trough_at := -gate * 3.5 - side * 5.5
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
		var foot := along * (float(gi) - 1.0) * 4.2 + out * (0.6 if gi == 1 else 0.0)
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
	var lid := k.prop("fence_wattle")
	if lid != "":
		var p := kept + Vector2(0.0, 1.9)
		k.place(lid, k.on_ground(p.x, p.y), 0.0, 1.0, true, Vector3(-1.1, 0.0, 0.0))
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
