extends RefCounted
## Brightwater's own place builders (docs/WORLD_LIFE.md). A POI def with `"builder": "<name>"` is built
## by the static function of that name here, in place of its kind's builder. Only the Brightwater
## region's author edits this file, so six regions can build at once without meeting.
##
##   static func drovers_hall(d: PoiDressing) -> void:
##       await PoiDressing.kind_builders().LAND.farmstead(d)    # its kind's, then more
##       var k := d.kit                                          # PoiKit: on_ground, prop, masonry ...
##
## The kind stays the def's `kind` (what the tests, the map and the audit call it); a builder named
## here that is missing is said in the log and the place is built as its kind.
##
## What is here, each its kind's own builder first and then what makes it the place its def says:
##
## * `gull_holm`: the Oroth pier-house's hinge-less door, facing the city across the Mere, the way down
##   into its cellars (core:interior/gull_holm_cellars);
## * `bleaching_green`: the tenter-frames of white linen in rows, one frame bare, the lye-tubs
##   steaming, and where the two bleachers work;
## * `cadbrae_slate_cut`: the black Oroth course showing in the deepest face, slate stacked by the
##   thousand on the floor, and the splitting-bench with the humming slate on it in its sacking;
## * `net_field`, `eggers_camp`, `the_listening_post`, `counting_tower`, `brindle_mill`, `standing_arches`: the kind's
##   own place and a spot where the person who lives there works, so they stand up at it and not on
##   a ring round the middle (which at a tower on a cliff is the air).

## Lime-wash, and the linen the Mere's light bleaches to it.
const LIME := Color(0.93, 0.92, 0.87)
const LINEN := Color(0.95, 0.95, 0.92)
const SLATE := Color(0.29, 0.31, 0.34)
const BRASS := Color(0.72, 0.56, 0.26)
## Tollmere, which the pier-house door faces across the water.
const CITY := Vector2(40.0, -300.0)


# --- shared hands -------------------------------------------------------------------------------------

## A dry spot clear of the roads near local `want`, trying further out along `dir` and then round
## it: where a person stands, or a thing is set down. With `body`, room for a person too: nothing
## solid the dressing has put down so far stands in a column 0.8 m across and a man's height over
## the ground there. `want` itself when nothing better is found.
static func _clear_spot(k: PoiKit, want: Vector2, dir: Vector2, clear := 3.0, body := true) -> Vector2:
	var solids := _solids(k) if body else []
	var steps := [0.0, 1.5, 3.0, -1.5, 4.5, -3.0]
	var turns := [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, PI]
	for t in turns:
		for s in steps:
			var p: Vector2 = want.rotated(float(t)) + dir.rotated(float(t)) * float(s)
			if k.is_water(p.x, p.y):
				continue
			if not k.roads.is_empty() and k.road_distance(p) < clear:
				continue
			if body and _blocked(k, solids, p):
				continue
			return p
	return want


## Every solid shape under the dressing so far, as a box in the dressing's own space.
static func _solids(k: PoiKit) -> Array[AABB]:
	var out: Array[AABB] = []
	for n in k.root.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if cs.shape == null or cs.disabled:
			continue
		var box: AABB
		if cs.shape is BoxShape3D:
			var size := (cs.shape as BoxShape3D).size
			box = AABB(-size * 0.5, size)
		else:
			var dm := cs.shape.get_debug_mesh()
			if dm == null:
				continue
			box = dm.get_aabb()
		var xf := Transform3D.IDENTITY
		var at: Node = cs
		while at != null and at != k.root:
			if at is Node3D:
				xf = (at as Node3D).transform * xf
			at = at.get_parent()
		out.append(xf * box)
	return out


## Whether a person standing at local `p` would stand in one of `solids`.
static func _blocked(k: PoiKit, solids: Array[AABB], p: Vector2) -> bool:
	var g := k.on_ground(p.x, p.y).y
	var person := AABB(Vector3(p.x - 0.45, g + 0.15, p.y - 0.45), Vector3(0.9, 1.7, 0.9))
	for box in solids:
		if box.intersects(person):
			return true
	return false


## A worked spot (NpcSpot group) on the ground at local `at`, facing `face` (local xz).
static func _spot(k: PoiKit, spot_name: String, at: Vector2, face: Vector2) -> void:
	var mk := k.marker(spot_name, k.on_ground(at.x, at.y), true)
	if mk != null and face != Vector2.ZERO:
		mk.rotation.y = PoiKit.yaw_of(face)


## The marker a kind's builder left, as a local xz, or `fallback` if it left none.
static func _marker_at(d: PoiDressing, marker_name: String, fallback: Vector2) -> Vector2:
	var mk := d.find_child(marker_name, true, false) as Node3D
	if mk == null:
		return fallback
	return Vector2(mk.position.x, mk.position.z)


## A block laid on the ground at local `at`, `size` big, turned `yaw`, its foot a little into the
## highest ground under it so no corner of it stands in the air.
static func _slab(k: PoiKit, m: PoiMasonry, st: SurfaceTool, at: Vector2, yaw: float, size: Vector3, sink := 0.05) -> Transform3D:
	var hi := -INF
	var basis := Basis(Vector3.UP, yaw)
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var c := Vector3(at.x, 0.0, at.y) + basis * Vector3(size.x * float(sx), 0.0, size.z * float(sz))
			hi = maxf(hi, k.on_ground(c.x, c.z).y)
	var lo := hi
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var c := Vector3(at.x, 0.0, at.y) + basis * Vector3(size.x * float(sx), 0.0, size.z * float(sz))
			lo = minf(lo, k.on_ground(c.x, c.z).y)
	# its foot reaches down to the lowest ground under it; its top is where the size says, over the highest
	var foot := lo - sink
	var top := hi + size.y - sink
	var xf := Transform3D(basis, Vector3(at.x, (foot + top) * 0.5, at.y))
	m.block(st, xf, Vector3(size.x, top - foot, size.z))
	return xf


# --- Gull Holm: the door with no hinges -----------------------------------------------------------------

## The pier-house's ruin as the kind builds it, and on the far side of it from the city, facing the
## city over the ruin, the Builders' door: a frame of black stone standing on its own on a plinth,
## with nothing in it but dark and no hinge anywhere. It opens onto the cellars.
static func gull_holm(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().ruins(d)
	var k := d.kit
	var m := d.masonry
	var to_city := (CITY - Vector2(k.origin.x, k.origin.z)).normalized()
	# behind the hall from the city, on the islet's dry ground: as far out as the islet allows
	var at := Vector2.ZERO
	for r in [10.5, 9.5, 8.5, 7.5, 6.5, 5.5]:
		var found := false
		for t in [0.0, 0.35, -0.35, 0.7, -0.7]:
			var p := (-to_city).rotated(float(t)) * float(r)
			var ok := true
			for q in [p, p + to_city * 1.6, p - to_city * 1.2, p + Vector2(to_city.y, -to_city.x) * 1.6, p - Vector2(to_city.y, -to_city.x) * 1.6]:
				if k.is_water((q as Vector2).x, (q as Vector2).y):
					ok = false
			if ok:
				at = p
				found = true
				break
		if found:
			break
	var yaw := PoiKit.yaw_of(to_city)
	var basis := Basis(Vector3.UP, yaw)
	var oroth := PoiKit.painted(2, PoiKit.OROTH, 0.35, 0.3)
	var st := m.begin()
	# the plinth, cut from one stone, and a step up to it on the city's side
	var plinth_top := _ground_top(k, at, basis, Vector2(3.6, 2.6)) + 0.35
	_slab(k, m, st, at, yaw, Vector3(3.6, 0.45, 2.6), 0.1)
	var step_front := at + to_city * 1.55
	_slab(k, m, st, step_front, yaw, Vector3(2.8, 0.28, 0.6), 0.1)
	# the jambs and the lintel: square, much taller than a man needs, no hinge-pins, no rebate
	for s in [-1.0, 1.0]:
		var jamb := Vector3(at.x, plinth_top + 1.9, at.y) + basis * Vector3(float(s) * 1.05, 0.0, -0.3)
		m.block(st, Transform3D(basis, jamb), Vector3(0.55, 3.8, 0.8))
		k.collider(Vector3(0.55, 3.8, 0.8), Transform3D(basis, jamb), "stone")
	var lintel := Vector3(at.x, plinth_top + 4.05, at.y) + basis * Vector3(0.0, 0.0, -0.3)
	m.block(st, Transform3D(basis, lintel), Vector3(2.9, 0.6, 0.95))
	k.collider(Vector3(2.9, 0.6, 0.95), Transform3D(basis, lintel), "stone")
	k.collider(Vector3(3.6, 0.35, 2.6), Transform3D(basis, Vector3(at.x, plinth_top - 0.175, at.y)), "stone")
	await k.step()
	m.commit(st, oroth, "HingelessDoor", true)
	if k.far:
		return
	# what is in the frame: the dark, a hand's depth back
	var dark := m.begin()
	m.block(dark, Transform3D(basis, Vector3(at.x, plinth_top + 1.75, at.y) + basis * Vector3(0.0, 0.0, -0.55)), Vector3(1.6, 3.5, 0.08))
	await k.step()
	m.commit(dark, PoiKit.plain(Color(0.02, 0.02, 0.03), 1.0), "DoorDark")
	# gull-lime down the lintel and on the steps: the gulls use it as they use the windows
	var lime := m.begin()
	for i in 5:
		var x := k.rng.randf_range(-1.2, 1.2)
		m.block(lime, Transform3D(basis, lintel + basis * Vector3(x, 0.31, k.rng.randf_range(-0.3, 0.3))), Vector3(0.18, 0.02, 0.14))
	await k.step()
	m.commit(lime, PoiKit.plain(LIME, 0.95), "GullLime")
	var interior := "core:interior/gull_holm_cellars"
	if ContentDB.has(interior):
		var door := Door.new()
		door.name = "Door_" + Ids.name_of(interior)
		door.interior_id = interior
		door.display_name = "the hinge-less door"
		door.position = Vector3(at.x, plinth_top, at.y) + basis * Vector3(0.0, 0.0, -0.35)
		door.rotation.y = yaw
		d.add_child(door)
		SiteInterior.prefetch(ContentDB.get_or_empty(interior))
	# where the egg-collectors' find lies, on the top step, and where anybody sent here stands
	k.marker("the_hinge_less_door", k.on_ground(step_front.x, step_front.y) + Vector3(0.0, 0.02, 0.0) + Vector3(to_city.x, 0.0, to_city.y) * 0.8)


## The highest ground under a box `size` (xz) at local `at` turned by `basis`.
static func _ground_top(k: PoiKit, at: Vector2, basis: Basis, size: Vector2) -> float:
	var hi := -INF
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var c := Vector3(at.x, 0.0, at.y) + basis * Vector3(size.x * float(sx), 0.0, size.y * float(sz))
			hi = maxf(hi, k.on_ground(c.x, c.z).y)
	return hi


# --- the Bleaching Green ------------------------------------------------------------------------------

## The bleachers' camp as a camp is built (their tents, the fire, the lamp on its post), and past it
## the green itself: tenter-frames in two rows with white cloth stretched on them from the rail to
## the grass, one frame bare where the Company took its bolt, the lye-tubs and the lime-pit.
static func bleaching_green(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().camp(d)
	var k := d.kit
	var m := d.masonry
	var fire := _marker_at(d, "the_fire", Vector2.ZERO)
	var along := k.grain()
	var across := Vector2(-along.y, along.x)
	# the frames go on the side of the camp away from the road, where there is one
	var out := along
	if not k.roads.is_empty() and k.road_distance(fire + along * 15.0) < k.road_distance(fire - along * 15.0):
		out = -along
	var timber := m.begin()
	var linen := m.begin()
	var frames: Array = []
	for row in 2:
		for col in 2:
			var c := fire + out * (15.5 + float(row) * 4.4) + across * ((float(col) - 0.5) * 7.6)
			frames.append(c)
	var bare := 3
	var first_frame := Vector2.INF
	for i in frames.size():
		var c: Vector2 = frames[i]
		var ok := true
		for s in [-3.3, 0.0, 3.3]:
			var q := c + across * float(s)
			if k.is_water(q.x, q.y) or (not k.roads.is_empty() and k.road_distance(q) < 3.0):
				ok = false
		if not ok:
			continue
		if first_frame == Vector2.INF:
			first_frame = c
		var yaw := PoiKit.yaw_of(across) + PI * 0.5
		var basis := Basis(Vector3.UP, yaw)
		# posts at the ends and the middle, a top rail between them
		var tops: Array = []
		for s in [-3.1, 0.0, 3.1]:
			var p := c + across * float(s)
			tops.append(m.post(timber, p, 1.75, 0.12))
		var hi := maxf(maxf((tops[0] as Vector3).y, (tops[1] as Vector3).y), (tops[2] as Vector3).y)
		var mid := Vector3(c.x, hi - 0.1, c.y)
		m.block(timber, Transform3D(basis, mid), Vector3(0.1, 0.1, 6.5))
		if i == bare:
			# the Company's bolt: the frame stripped, only the tenter-hooks and a torn selvage left
			m.block(linen, Transform3D(basis, mid + Vector3(0.0, -0.18, 0.0) + basis * Vector3(0.0, 0.0, -2.6)), Vector3(0.02, 0.3, 0.5))
			continue
		# the cloth, from the rail down to the grass: its foot follows the highest ground under it
		var ground_lo := INF
		for s in [-3.0, -1.5, 0.0, 1.5, 3.0]:
			var q := c + across * float(s)
			ground_lo = minf(ground_lo, k.on_ground(q.x, q.y).y)
		var cloth_top := hi - 0.16
		var cloth_foot := ground_lo + 0.05
		var h := maxf(cloth_top - cloth_foot, 0.4)
		var cxf := Transform3D(basis, Vector3(c.x, cloth_foot + h * 0.5, c.y))
		m.block(linen, cxf, Vector3(0.03, h, 6.1))
		k.collider(Vector3(0.12, h, 6.1), cxf, "cloth")
	await k.step()
	m.commit(timber, k.surface("timber", 0.5), "Tenters")
	await k.step()
	m.commit(linen, PoiKit.plain(LINEN, 0.9), "Linen", true)
	# the lye-tubs by the fire, steaming, and the lime-pit beyond them
	var tubs := fire - out * 3.4 + across * 3.0
	tubs = _clear_spot(k, tubs, across)
	var barrel := k.prop("barrel")
	for j in 2:
		var p := tubs + across * (float(j) * 1.3)
		await k.step()
		k.place(barrel, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.05, true)
	await k.step()
	k.puffs(k.on_ground(tubs.x, tubs.y, 1.2), Vector3(0.4, 0.1, 0.4), 0.8, 10, Color(0.9, 0.9, 0.88, 0.3), 1.6, 5.0)
	var pot := k.prop("cooking_pot")
	if pot != "":
		var pp := tubs - across * 1.3
		await k.step()
		k.place(pot, k.on_ground(pp.x, pp.y), 0.0, 1.0, true)
	var pit_at := _clear_spot(k, fire - out * 4.0 - across * 5.0, -across)
	var pit := m.begin()
	_slab(k, m, pit, pit_at, PoiKit.yaw_of(out), Vector3(2.6, 0.06, 1.8), 0.02)
	await k.step()
	m.commit(pit, PoiKit.plain(LIME, 1.0), "LimePit")
	var rim := m.begin()
	for s in [-1.0, 1.0]:
		_slab(k, m, rim, pit_at + out * (float(s) * 1.05), PoiKit.yaw_of(out), Vector3(3.0, 0.18, 0.25), 0.1)
	await k.step()
	m.commit(rim, k.surface("planks", 0.7), "PitBoards")
	# a basket of folded cloth and a watering-can's bucket between the rows
	if first_frame != Vector2.INF:
		var bk := first_frame - out * 1.6 + across * 4.2
		bk = _clear_spot(k, bk, across, 2.5)
		await k.step()
		k.place(k.prop("basket"), k.on_ground(bk.x, bk.y), k.rng.randf_range(0.0, TAU), 1.0, true)
		var bu := bk + across * 0.9
		await k.step()
		k.place(k.prop("bucket"), k.on_ground(bu.x, bu.y), k.rng.randf_range(0.0, TAU), 1.0, true)
		# Linnet walks the frames; Perrin keeps the tubs
		_spot(k, "the_frames", _clear_spot(k, first_frame - out * 1.8, across, 2.5), out)
	else:
		_spot(k, "the_frames", _clear_spot(k, fire + out * 4.0, across, 2.5), out)
	_spot(k, "the_lye_tubs", _clear_spot(k, tubs + out * 1.2, across, 2.5), -out)


# --- the Cadbrae Slate Cut ----------------------------------------------------------------------------

## A quarry as the kind cuts one, and then the Slades' own: the course of black Builders' stone
## showing along the foot of the deepest face, slate stacked on edge in rows waiting for the boats,
## the splitting-bench with the humming slate on it wrapped in sacking, and where the two of them work.
static func cadbrae_slate_cut(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().LAND.quarry(d)
	var k := d.kit
	var m := d.masonry
	var face := k.downhill()
	if face == Vector2.ZERO:
		face = k.grain()
	var side := Vector2(face.y, -face.x)
	var arc_r := minf(d.pad_radius * 0.75, 16.0)
	var centre := face * 2.0
	var floor_y := k.on_ground(centre.x, centre.y).y
	# the black course: a band of dressed Oroth stone proud of the first bench, where the cut met it
	var oroth := PoiKit.painted(2, PoiKit.OROTH, 0.3, 0.25)
	var course := m.begin()
	for i in 5:
		var am := -0.5 + 0.25 * float(i)
		var dir := (-face).rotated(am)
		var p := centre + dir * (arc_r - 1.45)
		var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(dir)), Vector3(p.x, floor_y + 1.05, p.y))
		m.block(course, xf, Vector3(2.0 * (arc_r - 1.45) * sin(0.125) + 0.12, 0.7, 0.12))
	await k.step()
	m.commit(course, oroth, "BlackCourse", true)
	# slate stacked on edge in rows, grey-blue, a thousand to a row
	var slate := PoiKit.painted(2, {"base": "#4b5058", "accent": "#3a3e45", "grout": "#23262b", "unit": 0.12}, 0.4, 0.5)
	var stacks := m.begin()
	var row0 := centre + face * 6.0 - side * 6.5
	for r in 3:
		for c in 4:
			var p := row0 + side * (float(c) * 1.6) + face * (float(r) * 1.3)
			if k.is_water(p.x, p.y) or (not k.roads.is_empty() and k.road_distance(p) < 3.0):
				continue
			var h := k.rng.randf_range(0.55, 0.85)
			var xf := _slab(k, m, stacks, p, PoiKit.yaw_of(side) + k.rng.randf_range(-0.06, 0.06), Vector3(1.2, h, 0.45), 0.04)
			k.collider(Vector3(1.2, h, 0.45), xf, "stone")
	await k.step()
	m.commit(stacks, slate, "SlateStacks")
	# the splitting-bench, with its mallet and chisel, and the humming slate in its sacking
	var bench := _clear_spot(k, centre + face * 3.5 + side * 5.5, side)
	var table := k.prop("table_trestle")
	var top_y := k.on_ground(bench.x, bench.y).y
	if table != "":
		await k.step()
		k.place(table, k.on_ground(bench.x, bench.y), PoiKit.yaw_of(face), 1.0, true)
		top_y += PoiKit.height_of(table)
	else:
		top_y += 0.8
	var wrapped := m.begin()
	m.block(wrapped, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side) + 0.2), Vector3(bench.x, top_y + 0.05, bench.y)), Vector3(0.62, 0.1, 0.4))
	await k.step()
	m.commit(wrapped, PoiKit.plain(Color(0.55, 0.47, 0.34), 0.95), "Sacking")
	var hammer := k.prop("hammer")
	if hammer != "":
		var hp := bench + side * 0.55
		await k.step()
		k.place(hammer, Vector3(hp.x, top_y, hp.y), k.rng.randf_range(0.0, TAU), 1.0, false)
	var stool := _clear_spot(k, bench - face * 1.0, side, 2.0)
	await k.step()
	k.place(k.prop("stool"), k.on_ground(stool.x, stool.y), PoiKit.yaw_of(face), 1.0, true)
	# Barnet at his bench; Jessamy at the face (the quarry's own `the_face`) splitting
	_spot(k, "the_splitting_bench", _clear_spot(k, bench - face * 1.4 + side * 0.9, side, 2.0), face)
	k.marker("the_humming_slate", Vector3(bench.x, top_y + 0.1, bench.y))


# --- a spot for whoever lives there ------------------------------------------------------------------

## The net-field as a camp is built, and the menders' bench beside the fire, out of the wind.
static func net_field(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().camp(d)
	var k := d.kit
	if k.far:
		return
	var fire := _marker_at(d, "the_fire", Vector2.ZERO)
	var g := k.grain()
	var bench := _clear_spot(k, fire + Vector2(-g.y, g.x) * 4.2, g)
	await k.step()
	k.place(k.prop("bench"), k.on_ground(bench.x, bench.y), PoiKit.yaw_of(fire - bench), 1.0, true)
	var coil := bench + g * 1.3
	await k.step()
	k.place(k.prop("rope_coil"), k.on_ground(coil.x, coil.y), k.rng.randf_range(0.0, TAU), 1.0, true)
	_spot(k, "the_menders_bench", _clear_spot(k, bench + (fire - bench).normalized() * 1.0, g, 2.0), bench - fire)
	_spot(k, "the_net_poles", _clear_spot(k, fire - Vector2(-g.y, g.x) * 5.5, g, 2.0), fire)


## The eggers' camp as a camp is built, and the rope-master's post at its seaward side.
static func eggers_camp(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().camp(d)
	var k := d.kit
	if k.far:
		return
	var fire := _marker_at(d, "the_fire", Vector2.ZERO)
	var down := k.downhill()
	if down == Vector2.ZERO:
		down = k.grain()
	var at := _clear_spot(k, fire + down * 4.5, Vector2(down.y, -down.x))
	for j in 3:
		var p := at + Vector2(down.y, -down.x) * (0.9 * float(j) - 0.9) + down * 1.6
		await k.step()
		k.place(k.prop("rope_coil"), k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.0, true)
	_spot(k, "the_rope_coils", _clear_spot(k, at, Vector2(down.y, -down.x), 2.5), down)


## A tower as the kind raises it, and a spot at its foot on the side away from the road.
static func _tower_with_spot(d: PoiDressing, spot_name: String) -> void:
	await PoiDressing.kind_builders().tower(d)
	var k := d.kit
	if k.far:
		return
	var g := k.grain()
	var want := Vector2(-g.y, g.x) * 6.5
	if not k.roads.is_empty() and k.road_distance(want) < k.road_distance(-want):
		want = -want
	var at := _clear_spot(k, want, want.normalized())
	await k.step()
	k.place(k.prop("stool"), k.on_ground(at.x, at.y), PoiKit.yaw_of(-at), 1.0, true)
	var desk := at + at.normalized() * 1.0
	await k.step()
	k.place(k.prop("crate"), k.on_ground(desk.x, desk.y), PoiKit.yaw_of(-at), 1.0, true)
	_spot(k, spot_name, _clear_spot(k, at - at.normalized() * 0.9, Vector2(at.y, -at.x).normalized(), 2.5), -at)


static func the_listening_post(d: PoiDressing) -> void:
	await _tower_with_spot(d, "the_horn_chair")


static func counting_tower(d: PoiDressing) -> void:
	await _tower_with_spot(d, "the_last_window")


## The mill as the kind raises it, and the miller's place at the door, by the sacks.
static func brindle_mill(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().LAND.mill(d)
	var k := d.kit
	if k.far:
		return
	var g := k.grain()
	var at := _clear_spot(k, -g * 6.0 + Vector2(-g.y, g.x) * 3.0, -g)
	for j in 2:
		var p := at + Vector2(-g.y, g.x) * (1.0 + 0.7 * float(j))
		await k.step()
		k.place(k.prop("sack"), k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.0, true)
	_spot(k, "the_mill_door", _clear_spot(k, at, -g, 2.5), g)


## The aqueduct's run as the ruin is raised, and where Ottilie Gannet sits with the holm in view: on
## the side of the arches toward the water, with a smoker's basket beside her.
static func standing_arches(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().ruins(d)
	var k := d.kit
	if k.far:
		return
	var to_water := k.water_direction(120.0)
	if to_water == Vector2.ZERO:
		to_water = k.downhill() if k.downhill() != Vector2.ZERO else k.grain()
	var at := _clear_spot(k, to_water * 9.0, to_water)
	await k.step()
	k.place(k.prop("basket"), k.on_ground(at.x + to_water.y * 0.9, at.y - to_water.x * 0.9), k.rng.randf_range(0.0, TAU), 1.0, true)
	_spot(k, "the_arch_foot", _clear_spot(k, at, Vector2(to_water.y, -to_water.x), 2.5), to_water)
