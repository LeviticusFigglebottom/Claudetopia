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

## Tollmere, which the pier-house door faces across the water.
const CITY := Vector2(40.0, -300.0)


# --- shared hands -------------------------------------------------------------------------------------

## A dry spot clear of the roads near local `want`, trying further out along `dir` and then round
## it: where a person stands, or a thing is set down. With `body`, room for a person too: nothing
## solid the dressing has put down so far stands in a column 0.8 m across and a man's height over
## the ground there. `want` itself when nothing better is found.
static func _clear_spot(k: PoiKit, want: Vector2, dir: Vector2, clear := 3.0, body := true) -> Vector2:
	var solids: Array[AABB] = []
	if body:
		solids = _solids(k)
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
	m.commit(lime, PoiKit.painted(0, {"base": "#d8d5c9", "accent": "#b9b6aa", "grout": "#8c897e", "unit": 0.1}, 0.7, 0.6), "GullLime")
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
	# linen in the sun: off-white with the weave's faint grain and the damp's grey where it was watered
	m.commit(linen, PoiKit.painted(0, {"base": "#e8e5da", "accent": "#d3cfc2", "grout": "#b5b1a4", "unit": 0.2}, 0.35, 0.5), "Linen", true)
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
	# slaked lime gone grey-white and cracked in the sun, with the green's mud trodden into its edge
	m.commit(pit, PoiKit.painted(5, {"base": "#c9c6b8", "accent": "#a8a597", "grout": "#6e6b5e", "unit": 0.28}, 0.85, 0.8), "LimePit")
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
	# the floor and the squared blocks are slate here, blue-grey and split, not a chalk pit's white
	var spoil := PoiKit.painted(5, {"base": "#5d6168", "accent": "#474b52", "grout": "#2c2f34", "unit": 0.22}, 0.8, 0.7)
	for part in ["QuarryFloor", "Blocks"]:
		var mi := d.find_child(part, true, false) as MeshInstance3D
		if mi != null:
			mi.material_override = spoil
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


## The gibbet as the wayside builds it, with its crows. The crows' bodies and wings are made as
## unnamed meshes (world/pois/crows.gd), which the seat audit cannot tell from a thing hung in the
## air; named for what they are, they read as birds (seat_audit.gd AIRBORNE_RE) and not as floating.
static func the_priced_gibbet(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().WAYSIDE.gibbet(d)
	var crows := d.find_child("Crows", true, false)
	if crows == null:
		return
	var i := 0
	for n in crows.find_children("*", "MeshInstance3D", true, false):
		n.name = "crow_%d" % i
		i += 1


## The delve as the site builder raises it, and then the Hush Hole's own ground: on unbuilt ground the
## cave raises a bank of its own over its throat in the ground's paint, which reads as a pale square
## lifted off the fen; here it is the fen cliff's dark, wet turf, and the cliff's boulders lie
## half-sunk along its brow and cheeks so the mouth is in rock.
static func the_hush_hole(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().SITES.build(d)
	var k := d.kit
	var bank := d.find_child("Bank", true, false) as MeshInstance3D
	if bank == null or k.far:
		return
	bank.material_override = PoiKit.painted(5, {"base": "#44503a", "accent": "#343d2c", "grout": "#23291d", "unit": 0.35}, 0.8, 0.8)
	var box := bank.get_aabb()
	var mouth := d.find_child("the_mouth", true, false) as Node3D
	var rock := k.rock("boulder")
	if rock == "":
		return
	var stones: Array = []
	for i in 20:
		var x := k.rng.randf_range(box.position.x, box.end.x)
		var z := k.rng.randf_range(box.position.z, box.end.z)
		if mouth != null and Vector2(x - mouth.position.x, z - mouth.position.z).length() < 7.0:
			continue
		var sc := k.rng.randf_range(0.6, 1.3)
		# on the ground round the bank's foot and under its flanks, a third sunk
		stones.append(PoiKit.transform_at(k.on_ground(x, z, -0.35 * sc), k.rng.randf_range(0.0, TAU), sc))
	await k.step()
	k.scatter(rock, stones, true)


# --- phase 2: the large sites ------------------------------------------------------------------------

## Calamine spoil: grey earth gone green where the rain has been at it, the colour of an old lamp.
const SPOIL := {"base": "#3d3d33", "accent": "#2f3429", "grout": "#1d2018", "unit": 0.28}
## The engine-house's killas: a warm grey rubble stone, not the city's cool lime-and-slate.
const KILLAS := {"base": "#8e897e", "accent": "#6d685f", "grout": "#433f39", "unit": 0.44}
## The Tally Needle's lime-wash, gone the grey of old teeth where the rain runs.
const LIMEWASH := {"base": "#dcd8cb", "accent": "#c3bfb1", "grout": "#8f8b7e", "unit": 0.3}
const BRASS := Color(0.71, 0.56, 0.27)
const SHAFT_DARK := Color(0.02, 0.02, 0.025)


## A run of wall from `a` to `b` (local xz), `thick` through, standing from `foot` (local height)
## to `top`, with `openings` cut through it: each [metres along from a, width, sill, head] (sill and
## head over `foot`). Piers between the openings go the full height; under an opening a breast,
## over it the wall goes on. Each solid piece is its own box with a collider.
static func _wall_run(k: PoiKit, m: PoiMasonry, st: SurfaceTool, a: Vector2, b: Vector2, foot: float, top: float,
		thick: float, openings: Array = []) -> void:
	var seg := b - a
	var length := seg.length()
	if length < 0.2:
		return
	var dir := seg / length
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(dir) + PI * 0.5)
	var cuts := openings.duplicate()
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	var pieces: Array = []      # [from_m, to_m, y0, y1]
	var at := 0.0
	for o in cuts:
		var c := float(o[0])
		var w := float(o[1])
		var lo := clampf(c - w * 0.5, 0.0, length)
		var hi := clampf(c + w * 0.5, 0.0, length)
		if lo > at:
			pieces.append([at, lo, foot, top])
		if float(o[2]) > 0.05:
			pieces.append([lo, hi, foot, foot + float(o[2])])
		if foot + float(o[3]) < top - 0.05:
			pieces.append([lo, hi, foot + float(o[3]), top])
		at = hi
	if at < length:
		pieces.append([at, length, foot, top])
	for p in pieces:
		var l0 := float(p[0])
		var l1 := float(p[1])
		var y0 := float(p[2])
		var y1 := float(p[3])
		if l1 - l0 < 0.05 or y1 - y0 < 0.05:
			continue
		var mid := a + dir * ((l0 + l1) * 0.5)
		var xf := Transform3D(basis, Vector3(mid.x, (y0 + y1) * 0.5, mid.y))
		var size := Vector3(l1 - l0 + 0.02, y1 - y0, thick)
		m.block(st, xf, size)
		k.collider(size, xf, "stone")


## The lowest ground under the corners and the middle of a box `size` (xz) at local `at` turned `yaw`.
static func _ground_low(k: PoiKit, at: Vector2, yaw: float, size: Vector2) -> float:
	var lo := k.on_ground(at.x, at.y).y
	var basis := Basis(Vector3.UP, yaw)
	for sx in [-0.5, 0.0, 0.5]:
		for sz in [-0.5, 0.0, 0.5]:
			var c := Vector3(at.x, 0.0, at.y) + basis * Vector3(size.x * float(sx), 0.0, size.y * float(sz))
			lo = minf(lo, k.on_ground(c.x, c.z).y)
	return lo


## A spoked wheel standing upright with its middle at `c` (local), its face across `axis` (the axle's
## line, local xz): a rim of `n` felloes about a hub, into `st`.
static func _sheave(m: PoiMasonry, st: SurfaceTool, c: Vector3, axis: Vector2, r: float, n := 16) -> void:
	var face := Basis(Vector3.UP, PoiKit.yaw_of(axis))
	for i in n:
		var a := TAU * (float(i) + 0.5) / float(n)
		var p := c + face * Vector3(sin(a) * r, cos(a) * r, 0.0)
		m.block(st, Transform3D(face * Basis(Vector3.BACK, -a), p), Vector3(TAU * r / float(n) * 1.08, 0.14, 0.14))
	var spokes := n >> 1
	for i in spokes:
		var a := TAU * float(i) / float(spokes)
		var p := c + face * Vector3(sin(a) * r * 0.5, cos(a) * r * 0.5, 0.0)
		m.block(st, Transform3D(face * Basis(Vector3.BACK, -a), p), Vector3(0.07, r, 0.07))
	m.rod(st, Transform3D(face * Basis(Vector3.RIGHT, PI * 0.5), c), 0.16, 0.5)


# --- the Crown Drift --------------------------------------------------------------------------------

## The Tallymen's calamine mine as it was left in 1012: over the shaft a timber headframe with its
## winding-wheel, raked back by two stays toward the engine-house, whose roofless stone walls stand
## three storeys with the beam's opening high in the end that faces the shaft and the engine's
## great beam fallen out of it; the chimney at the engine-house's far corner, the tallest thing on
## the North Shore's terrace. The shaft in its stone collar with a rotten cover half off it and the
## ladder's head showing, the way down. The spoil spilling toward the Mere, grey-green, with the
## tramway that tipped it and a wagon left on its lip; two round buddles where the ore was washed;
## the drift-captain's roofless count-house, and by the shaft the shift-board with nine rings painted
## round nine empty hooks.
static func the_crown_drift(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var site: Dictionary = ContentDB.get_or_empty(d.poi_id).get("site", {})
	var face := k.downhill()
	if face == Vector2.ZERO:
		face = k.grain()
	face = face.normalized()
	# the engine-house to the side of the shaft the road is not
	var side := Vector2(-face.y, face.x)
	if not k.roads.is_empty() and k.road_distance(side * 14.0) < k.road_distance(-side * 14.0):
		side = -side
	var shaft := -face * 3.0
	var g0 := k.on_ground(shaft.x, shaft.y).y
	var yaw_f := PoiKit.yaw_of(face)
	var stone := m.begin()
	var timber := m.begin()
	var planks := m.begin()

	# the collar: a ring of dressed stone round the shaft, knee high, the hole 2.6 m across
	var basis_f := Basis(Vector3.UP, yaw_f)
	for s in [-1.0, 1.0]:
		for along in [true, false]:
			var off := (Vector3(0.0, 0.0, 1.55 * float(s)) if along else Vector3(1.55 * float(s), 0.0, 0.0))
			var size := Vector3(3.6, 0.65, 0.5) if along else Vector3(0.5, 0.65, 2.6)
			var xf := Transform3D(basis_f, Vector3(shaft.x, g0 + 0.2, shaft.y) + basis_f * off)
			m.block(stone, xf, size)
			k.collider(size, xf, "stone")
	# the dark down the shaft, and its cover: three rotten planks across one half, one fallen in
	var dark := m.begin()
	m.block(dark, Transform3D(basis_f, Vector3(shaft.x, g0 + 0.04, shaft.y)), Vector3(2.62, 0.04, 2.62))
	for i in 3:
		var off := Vector3(0.45 + float(i) * 0.4, 0.52, 0.55)
		m.block(planks, Transform3D(basis_f * Basis(Vector3.FORWARD, k.rng.randf_range(-0.04, 0.04)),
				Vector3(shaft.x, g0, shaft.y) + basis_f * off), Vector3(0.38, 0.06, 3.3))
	m.block(planks, Transform3D(basis_f * Basis(Vector3.RIGHT, 0.9), Vector3(shaft.x, g0 - 0.3, shaft.y) + basis_f * Vector3(0.9, 0.0, -0.4)),
			Vector3(0.36, 0.06, 2.4))
	# the ladder's head, on the shaft's side toward the Mere, going down into the dark
	var lad := shaft + face * 0.95
	for s in [-1.0, 1.0]:
		var r0 := lad + side * 0.32 * float(s)
		m.limb(timber, Vector3(r0.x, g0 + 1.1, r0.y), Vector3(r0.x - face.x * 0.25, g0 - 3.0, r0.y - face.y * 0.25), 0.045)
	for i in 5:
		var y := g0 + 0.8 - float(i) * 0.7
		var c := lad - face * (0.05 * float(i))
		m.limb(timber, Vector3(c.x - side.x * 0.32, y, c.y - side.y * 0.32), Vector3(c.x + side.x * 0.32, y, c.y + side.y * 0.32), 0.03)

	# the headframe: four legs from the collar's corners to a crown 11 m up, braced every 3.5 m, and two
	# back-stays raking down toward the engine-house
	var crown_y := g0 + 11.0
	var legs: Array[Vector3] = []
	for c in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		var foot := shaft + face * 1.9 * float(c[0]) + side * 1.9 * float(c[1])
		var f := k.on_ground(foot.x, foot.y, -0.3)
		var head := Vector3(shaft.x, crown_y, shaft.y) + Vector3(face.x, 0.0, face.y) * 0.75 * float(c[0]) + Vector3(side.x, 0.0, side.y) * 0.75 * float(c[1])
		legs.append(f)
		legs.append(head)
		m.limb(timber, f, head, 0.17)
		k.collider(Vector3(0.36, 2.2, 0.36), Transform3D(Basis.IDENTITY, f + Vector3(0.0, 1.1, 0.0)), "wood")
	for level in [0.3, 0.62, 0.97]:
		for i in 4:
			var a: Vector3 = legs[i * 2].lerp(legs[i * 2 + 1], level)
			var b: Vector3 = legs[((i + 1) % 4) * 2].lerp(legs[((i + 1) % 4) * 2 + 1], level)
			m.limb(timber, a, b, 0.11)
	var crown := Vector3(shaft.x, crown_y + 0.25, shaft.y)
	var to_engine := Vector3(side.x, 0.0, side.y)
	var stays := m.begin()
	for s in [-1.0, 1.0]:
		var head := crown + Vector3(face.x, 0.0, face.y) * 0.7 * float(s)
		var foot2 := Vector2(shaft.x, shaft.y) + side * 6.8 + face * 1.2 * float(s)
		m.limb(stays, head, k.on_ground(foot2.x, foot2.y, -0.3), 0.15)
		var ff := k.on_ground(foot2.x, foot2.y)
		k.collider(Vector3(0.34, 1.8, 0.34), Transform3D(Basis.IDENTITY, ff + Vector3(0.0, 0.9, 0.0)), "wood")
	# the sheave on its bearers over the crown, turned to the engine-house, and the rope off it: down
	# into the shaft and across to the drum in the engine-house's bob-wall
	var wheel_c := crown + Vector3(0.0, 1.55, 0.0)
	m.block(timber, Transform3D(Basis(Vector3.UP, yaw_f), crown + Vector3(0.0, 0.2, 0.0)), Vector3(2.0, 0.24, 0.4))
	m.block(timber, Transform3D(Basis(Vector3.UP, yaw_f), crown + Vector3(0.0, 0.2, 0.0) + to_engine * 0.0), Vector3(0.4, 0.24, 2.0))
	_sheave(m, timber, wheel_c, face, 1.35, 16)
	for s in [-1.0, 1.0]:
		var p := wheel_c + Vector3(face.x, 0.0, face.y) * 0.3 * float(s)
		m.limb(timber, crown + Vector3(face.x, 0.0, face.y) * 0.3 * float(s) + Vector3(0.0, 0.2, 0.0), p, 0.08)
	await k.step()

	# the engine-house: its bob-wall a stride from the stays' feet, the long walls along the line
	# to the shaft, three storeys and roofless
	var ec := shaft + side * 13.0 - face * 0.5
	var half := Vector2(4.4, 3.0)       # half along side, half along face
	var ef := _ground_low(k, ec, yaw_f, half * 2.0) - 0.15
	var eh := 9.5
	var th := 0.85
	var c00 := ec - side * half.x - face * half.y
	var c10 := ec + side * half.x - face * half.y
	var c11 := ec + side * half.x + face * half.y
	var c01 := ec - side * half.x + face * half.y
	var killas := m.begin()
	# the long walls: two tiers of tall windows, the door low in the one facing the Mere
	_wall_run(k, m, killas, c01, c11, ef, ef + eh, th, [[2.4, 1.5, 0.0, 2.6], [2.4, 1.1, 4.0, 6.2], [6.4, 1.1, 1.3, 3.4], [6.4, 1.1, 4.0, 6.2]])
	_wall_run(k, m, killas, c00, c10, ef, ef + eh, th, [[2.4, 1.1, 1.3, 3.4], [2.4, 1.1, 4.0, 6.2], [6.4, 1.1, 1.3, 3.4], [6.4, 1.1, 4.0, 6.2]])
	# the bob-wall toward the shaft, thicker and higher, the beam's opening near its head
	_wall_run(k, m, killas, c00, c01, ef, ef + eh + 1.6, 1.5, [[3.0, 1.6, 6.6, 9.2]])
	# the far gable, its apex fallen
	_wall_run(k, m, killas, c10, c11, ef, ef + eh, th, [[3.0, 1.0, 4.4, 6.2]])
	var gc := (c10 + c11) * 0.5
	for i in 3:
		var w := 6.0 - float(i) * 1.7
		var xf := Transform3D(Basis(Vector3.UP, yaw_f + PI * 0.5), Vector3(gc.x, ef + eh + 0.35 + float(i) * 0.7, gc.y))
		m.block(killas, xf, Vector3(w, 0.7, th))
		k.collider(Vector3(w, 0.7, th), xf, "stone")
	# a granite string-course round the walls at the floors, and quoins proud at the corners
	for y in [3.7, 7.0]:
		for pair in [[c00, c10], [c01, c11]]:
			var a: Vector2 = pair[0]
			var b: Vector2 = pair[1]
			var mid := (a + b) * 0.5
			m.block(killas, Transform3D(Basis(Vector3.UP, yaw_f), Vector3(mid.x, ef + y, mid.y)), Vector3((b - a).length() + 0.2, 0.18, th + 0.14))
	for cnr in [c00, c10, c11, c01]:
		var cv: Vector2 = cnr
		for j in 7:
			var y := ef + 0.5 + float(j) * 1.3
			var w2 := 0.62 if j % 2 == 0 else 0.42
			m.block(killas, Transform3D(Basis(Vector3.UP, yaw_f), Vector3(cv.x, y, cv.y)), Vector3(w2 + th, 0.32, w2 + th))
	await k.step()
	m.commit(killas, PoiKit.painted(2, KILLAS, 0.75, 0.7), "EngineHouse", true)

	# the chimney at the far corner from the shaft, a square base built into the corner and a round
	# stack going up out of it, the tallest thing on the shore; a brick band at its head
	var stack := c10 + side * 1.2 - face * 1.2
	var sf := _ground_low(k, stack, yaw_f, Vector2(2.8, 2.8)) - 0.15
	var chim := m.begin()
	var base_xf := Transform3D(Basis(Vector3.UP, yaw_f), Vector3(stack.x, sf + 3.6, stack.y))
	m.block(chim, base_xf, Vector3(2.8, 7.2, 2.8))
	k.collider(Vector3(2.8, 7.2, 2.8), base_xf, "stone")
	m.block(chim, Transform3D(Basis(Vector3.UP, yaw_f), Vector3(stack.x, sf + 7.3, stack.y)), Vector3(3.0, 0.25, 3.0))
	m.drum(chim, Transform3D(Basis.IDENTITY, Vector3(stack.x, sf + 7.2, stack.y)), 1.05, 7.0, 0.0, NAN, false, 0.7)
	m.drum(chim, Transform3D(Basis.IDENTITY, Vector3(stack.x, sf + 14.2, stack.y)), 0.92, 4.6, 0.0, NAN, false, 0.7)
	await k.step()
	m.commit(chim, PoiKit.painted(2, KILLAS, 0.8, 0.7), "Chimney", true)
	var brick := m.begin()
	m.drum(brick, Transform3D(Basis.IDENTITY, Vector3(stack.x, sf + 18.8, stack.y)), 1.0, 0.9, 0.0, NAN, false, 0.3)
	await k.step()
	m.commit(brick, PoiKit.painted(2, {"base": "#7a4a38", "accent": "#5e382b", "grout": "#2e221c", "unit": 0.18}, 0.85, 0.6), "ChimneyHead", true)
	# the engine's great beam, fallen out of the bob-wall's opening to lie with its end on the ground
	var bob := (c00 + c01) * 0.5
	var beam_top := Vector3(bob.x, ef + 7.8, bob.y) + Vector3(side.x, 0.0, side.y) * 0.4
	var beam_foot := k.on_ground(bob.x - side.x * 5.6, bob.y - side.y * 5.6, 0.25) + Vector3(face.x, 0.0, face.y) * 0.8
	m.limb(stays, beam_top, beam_foot, 0.32)
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "Headframe", true)
	m.commit(stays, k.surface("timber", 0.85), "StaysAndBeam", true)
	m.commit(dark, PoiKit.plain(SHAFT_DARK, 1.0), "ShaftDark")
	if k.far:
		m.commit(stone, PoiKit.painted(2, KILLAS, 0.7, 0.7), "Collar", true)
		return

	# the rope from the sheave: down the shaft, and across to the bob-wall's drum
	var rope := m.begin()
	m.limb(rope, wheel_c - to_engine * 1.3, Vector3(shaft.x, g0 - 2.5, shaft.y) - to_engine * 1.0, 0.025)
	m.limb(rope, wheel_c + to_engine * 1.3, Vector3(bob.x, ef + 7.4, bob.y), 0.025)
	await k.step()
	m.commit(rope, PoiKit.plain(Color(0.36, 0.31, 0.24), 0.95), "Rope")

	# the spoil: a long heap spilling toward the Mere from the tramway's end, and an older one grassed
	# over beside it
	var spoil := PoiKit.painted(5, SPOIL, 0.85, 0.8)
	var heaps := [[face * 22.0 + side * 4.0, 12.5, 5.2], [face * 24.0 - side * 14.0, 7.0, 2.6]]
	for h in heaps:
		var at: Vector2 = h[0]
		var r := float(h[1])
		var lo := INF
		for i in 12:
			var a := TAU * float(i) / 12.0
			lo = minf(lo, k.on_ground(at.x + sin(a) * r, at.y + cos(a) * r).y)
		await k.step()
		m.mound(Vector3(at.x, minf(lo, k.on_ground(at.x, at.y).y) - 0.35, at.y), r, float(h[2]), spoil, "Spoil", true, 1.8, 7, 22, true, 0.09)
	# loose stone at the heap's foot, where it rolled
	var rock := k.rock("boulder")
	if rock != "":
		var stones: Array = []
		var h0: Vector2 = heaps[0][0]
		for i in 9:
			var a := k.rng.randf_range(-1.2, 1.2) + PoiKit.yaw_of(face)
			var p := h0 + Vector2(sin(a), cos(a)) * k.rng.randf_range(12.0, 14.5)
			var sc := k.rng.randf_range(0.25, 0.5)
			stones.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.25 * sc), k.rng.randf_range(0.0, TAU), sc))
		await k.step()
		k.scatter(rock, stones, true)
	# the tramway from the collar to the heap's crown: sleepers and two rails, the wagon tipped at its end
	var rail_a := shaft + face * 2.6
	var heap_c: Vector2 = heaps[0][0]
	var rail_b := heap_c - (heap_c - rail_a).normalized() * 13.2
	var run := rail_b - rail_a
	var run_dir := run.normalized()
	var across := Vector2(-run_dir.y, run_dir.x)
	var sleepers := int(run.length() / 1.1)
	var rails := m.begin()
	for i in sleepers:
		var p := rail_a + run_dir * (float(i) + 0.5) * 1.1
		m.block(planks, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(across)), k.on_ground(p.x, p.y, 0.04)), Vector3(0.22, 0.1, 1.5))
	for s in [-0.45, 0.45]:
		for i in sleepers - 1:
			var p0 := rail_a + run_dir * (float(i) + 0.5) * 1.1 + across * float(s)
			var p1 := rail_a + run_dir * (float(i) + 1.5) * 1.1 + across * float(s)
			m.limb(rails, k.on_ground(p0.x, p0.y, 0.13), k.on_ground(p1.x, p1.y, 0.13), 0.035)
	await k.step()
	m.commit(rails, PoiKit.plain(Color(0.32, 0.27, 0.22), 0.6, 0.4), "Rails")
	var wagon := rail_b + run_dir * 0.6
	var cart := k.prop("wheelbarrow")
	if cart != "":
		await k.step()
		k.place(cart, k.on_ground(wagon.x, wagon.y), PoiKit.yaw_of(run_dir), 1.15, true)
	# the buddles: two round stone pits where the ore was washed, green slime dried in their floors
	var buddle_at := face * 7.0 - side * 7.5
	for j in 2:
		var bc := buddle_at - side * (5.2 * float(j))
		var bg := k.on_ground(bc.x, bc.y).y
		m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(bc.x, bg - 0.25, bc.y)), 2.1, 0.75, 0.25)
		await k.step()
		m.pool(bc, 1.6, bg + 0.08, spoil, "BuddleFloor", 14)
	# the ore floor: heaps of picked ore by the buddles, greener than the spoil
	var ore := PoiKit.painted(5, {"base": "#6d7a5e", "accent": "#55634b", "grout": "#33392b", "unit": 0.18}, 0.7, 0.9)
	for j in 3:
		var oc := buddle_at + face * 3.6 - side * (2.4 * float(j) - 1.0)
		await k.step()
		m.mound(k.on_ground(oc.x, oc.y, -0.1), 1.2 + 0.3 * float(j % 2), 0.7, ore, "Ore", false, 1.4, 4, 12)

	# the count-house: four low roofless walls by the engine-house, a door toward the shaft, and inside
	# the drift-captain's table, his stool, his bed and the lamp he never lights
	var ch := shaft - side * 9.0 - face * 2.0
	var cf := _ground_low(k, ch, yaw_f, Vector2(5.0, 4.0)) - 0.1
	var hx := 2.5
	var hz := 2.0
	var q00 := ch - side * hx - face * hz
	var q10 := ch + side * hx - face * hz
	var q11 := ch + side * hx + face * hz
	var q01 := ch - side * hx + face * hz
	var hut := m.begin()
	_wall_run(k, m, hut, q00, q10, cf, cf + 2.5, 0.55, [[3.6, 0.6, 1.0, 1.9]])
	_wall_run(k, m, hut, q10, q11, cf, cf + 2.2, 0.55, [[2.0, 1.1, 0.0, 2.1]])
	_wall_run(k, m, hut, q11, q01, cf, cf + 1.6, 0.55)
	_wall_run(k, m, hut, q01, q00, cf, cf + 2.4, 0.55, [[2.0, 0.6, 1.0, 1.8]])
	await k.step()
	m.commit(hut, PoiKit.painted(2, KILLAS, 0.85, 0.7), "CountHouse")
	var table := ch - side * 0.6 - face * 0.6
	var tpath := k.prop("table_trestle")
	await k.step()
	k.place(tpath, k.on_ground(table.x, table.y), yaw_f, 1.0, true)
	var tt := k.on_ground(table.x, table.y).y + (PoiKit.height_of(tpath) if tpath != "" else 0.8)
	var lamp := k.prop("lantern_hand")
	if lamp != "":
		await k.step()
		k.place(lamp, Vector3(table.x + side.x * 0.4, tt, table.y + side.y * 0.4), 0.0, 1.0, false)
	var paper := k.prop("paper_stack")
	if paper != "":
		await k.step()
		k.place(paper, Vector3(table.x - side.x * 0.3, tt, table.y - side.y * 0.3), k.rng.randf() * TAU, 1.0, false)
	var bed := ch - side * 1.2 + face * 1.1
	await k.step()
	k.place(k.prop("bedroll"), k.on_ground(bed.x, bed.y), PoiKit.yaw_of(side), 1.0, false)
	await k.step()
	k.place(k.prop("stool"), k.on_ground(table.x + face.x * 0.9, table.y + face.y * 0.9), yaw_f, 1.0, true)

	# the shift-board by the shaft: a board on two posts, rows of hooks, nine painted rings round nine
	# empty ones; touching it reads it
	var board_at := shaft - side * 3.4 + face * 1.6
	var byaw := PoiKit.yaw_of(face)
	var bb := Basis(Vector3.UP, byaw)
	var bg2 := k.on_ground(board_at.x, board_at.y).y
	for s in [-1.0, 1.0]:
		var p := Vector3(board_at.x, bg2 + 1.05, board_at.y) + bb * Vector3(float(s) * 0.95, 0.0, 0.0)
		m.block(planks, Transform3D(bb, p), Vector3(0.14, 2.3, 0.14))
		k.collider(Vector3(0.14, 2.3, 0.14), Transform3D(bb, p), "wood")
	var board_c := Vector3(board_at.x, bg2 + 1.55, board_at.y)
	m.block(planks, Transform3D(bb, board_c + bb * Vector3(0.0, 0.0, 0.08)), Vector3(1.9, 1.2, 0.06))
	await k.step()
	m.commit(planks, k.surface("planks", 0.7), "Planks")
	var paint := m.begin()
	var hooks := m.begin()
	m.block(paint, Transform3D(bb, board_c + Vector3(0.0, 0.48, 0.0) + bb * Vector3(0.0, 0.0, 0.115)), Vector3(1.3, 0.12, 0.01))
	for row in 4:
		for col in 8:
			var p := board_c + bb * Vector3(-0.75 + float(col) * 0.215, 0.24 - float(row) * 0.24, 0.12)
			m.block(hooks, Transform3D(bb, p), Vector3(0.025, 0.06, 0.05))
			if (row == 2 and col >= 3) or (row == 3 and col >= 3 and col <= 6):
				for e in 4:
					var a := TAU * float(e) / 4.0
					m.block(paint, Transform3D(bb * Basis(Vector3.BACK, a), p + bb * Vector3(sin(a) * 0.07, cos(a) * 0.07, -0.004)), Vector3(0.06, 0.012, 0.008))
	await k.step()
	# (named as a sign's paint is: it is on the board, which the seat audit cannot see under it)
	m.commit(paint, PoiKit.plain(Color(0.86, 0.84, 0.78), 0.8), "sign_ShiftBoardPaint")
	m.commit(hooks, PoiKit.plain(Color(0.25, 0.23, 0.2), 0.5, 0.6), "sign_ShiftBoardHooks")
	m.commit(stone, PoiKit.painted(2, KILLAS, 0.7, 0.7), "Collar", true)
	k.touchable("Hook", board_c + bb * Vector3(0.0, 0.0, 0.3), str(site.get("hook_prompt", "Read the shift-board")),
			str(site.get("hook", "")))
	# a lamp hung from the headframe's lowest brace over the ladder, lit by the takers at night
	var hang := k.prop("lantern_hanging")
	var brace: Vector3 = legs[0].lerp(legs[1], 0.3).lerp(legs[2].lerp(legs[3], 0.3), 0.5)
	if hang != "":
		await k.step()
		k.place(hang, brace - Vector3(0.0, PoiKit.height_of(hang) + 0.11, 0.0), 0.0, 1.0, false)
	# a kibble and a coil of rope by the collar, a crate the takers left
	var kib := shaft - face * 3.0 + side * 3.0
	await k.step()
	k.place(k.prop("barrel"), k.on_ground(kib.x, kib.y), k.rng.randf() * TAU, 1.0, true)
	var coil := shaft - face * 3.2 - side * 1.0
	await k.step()
	k.place(k.prop("rope_coil"), k.on_ground(coil.x, coil.y), k.rng.randf() * TAU, 1.0, false)
	var crate := ec + face * (half.y + 1.6) + side * 1.0
	await k.step()
	k.place(k.prop("crate"), k.on_ground(crate.x, crate.y), yaw_f + 0.2, 1.0, true)

	# the way down: at the ladder's head, facing out of the shaft
	var door_at := k.on_ground(lad.x, lad.y)
	_sites()._door(d, str(site.get("interior", "")), Vector3(door_at.x, g0 + 0.1, door_at.z), atan2(face.x, face.y))
	k.marker("the_shaft_head", k.on_ground(shaft.x + face.x * 4.0 + side.x * 2.0, shaft.y + face.y * 4.0 + side.y * 2.0))
	# Abel Rowse at his count-house door, with the board in sight
	var door_out := (q10 + q11) * 0.5 + side * 1.2
	_spot(k, "the_count_house", _clear_spot(k, door_out, side, 2.0), board_at - door_out)


## The site builders' script (world/sites/site_exterior.gd), for its door and hook.
static func _sites() -> GDScript:
	return PoiDressing.kind_builders().SITES


# --- the Struck Barrow and the Tally Needle ----------------------------------------------------------

## The way into the hill at a place: the bearing within a wide arc of uphill along which the ground
## goes furthest before it rises `rise` metres (a gully's line, not the scarp's face), and how far
## that is, capped at `reach`. [local xz unit, metres]; [uphill, reach * 0.6] where nothing rises.
static func _gully(k: PoiKit, rise: float, reach: float) -> Array:
	var up := k.uphill()
	if up == Vector2.ZERO:
		up = -k.grain()
	var g0 := k.on_ground(0.0, 0.0).y
	var best := [up, reach * 0.6]
	var best_d := -1.0
	for i in 13:
		var a := deg_to_rad(-60.0 + float(i) * 10.0)
		var u := up.rotated(a)
		var found := -1.0
		var dd := 4.0
		while dd <= reach:
			if k.on_ground(u.x * dd, u.y * dd).y - g0 >= rise:
				found = dd
				break
			dd += 1.0
		if found > best_d:
			best_d = found
			best = [u, found]
	return best


## The Tallymen's barrow for the struck, cut into the south shore's scarp at the head of a gully, and
## at the gully's mouth the Tally Needle: a lime-washed obelisk on a stepped plinth, every face cut
## with names in close rows and every name struck through, one of them chalked back over in a
## laundress's capitals; a brass cap that catches the sun across the Mere. A flight of broad steps
## goes up the gully floor to the portal: a dressed facade with wing walls holding the cutting back,
## a heavy lintel with RECEIVED cut in it, and the dark door. The bier-stone where the struck were set
## down, numbered markers along the gully, and what the resurrection men leave at the door.
static func the_struck_barrow(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var site: Dictionary = ContentDB.get_or_empty(d.poi_id).get("site", {})
	var gully := _gully(k, 2.0, d.pad_radius * 0.85)
	var into: Vector2 = (gully[0] as Vector2).normalized()
	# the door where the gully's floor turns up into the hill's face (steeper than one in two)
	var door_d := clampf(float(gully[1]), 12.0, d.pad_radius * 0.85)
	var dd := 8.0
	while dd < d.pad_radius + 2.0:
		var p0 := into * dd
		var p1 := into * (dd + 2.0)
		if k.on_ground(p1.x, p1.y).y - k.on_ground(p0.x, p0.y).y > 1.0:
			door_d = dd + 0.5
			break
		dd += 1.0
	var out := -into
	var side := Vector2(-into.y, into.x)
	var yaw_out := PoiKit.yaw_of(out)
	var bo := Basis(Vector3.UP, yaw_out)
	var door := into * door_d
	var gd := k.on_ground(door.x, door.y).y
	var lime := PoiKit.painted(0, LIMEWASH, 0.8, 0.7)
	var dressed := m.begin()

	# the facade: a wall of dressed stone across the gully's head with the hill behind it, the door in it
	var fw := 10.5
	var fh := 5.6
	var ft := 1.5
	var face_c := door + into * (ft * 0.5)
	var foot := _ground_low(k, face_c, yaw_out, Vector2(fw, ft)) - 0.2
	_wall_run(k, m, dressed, face_c - side * fw * 0.5, face_c + side * fw * 0.5, foot, gd + fh, ft, [[fw * 0.5, 1.7, gd - foot, gd - foot + 2.7]])
	# a plain cornice along its head, and a pediment over the door
	var corn := Transform3D(Basis(Vector3.UP, yaw_out + PI * 0.5), Vector3(face_c.x, gd + fh + 0.12, face_c.y) + Vector3(out.x, 0.0, out.y) * 0.1)
	m.block(dressed, corn, Vector3(fw + 0.4, 0.25, ft + 0.3))
	for s in [-1.0, 1.0]:
		# the door's jambs, proud of the wall, and the wing walls holding the cutting back
		var j := door + side * float(s) * 1.15 + out * 0.15
		var jxf := Transform3D(bo, Vector3(j.x, gd + 1.45, j.y))
		m.block(dressed, jxf, Vector3(0.55, 2.9, 0.5))
		k.collider(Vector3(0.55, 2.9, 0.5), jxf, "stone")
		var w0 := face_c + side * float(s) * (fw * 0.5 - 0.3)
		var w1 := w0 + (out.rotated(float(s) * 0.55)) * 6.5
		var wf := minf(k.on_ground(w0.x, w0.y).y, k.on_ground(w1.x, w1.y).y) - 0.2
		var wh0 := gd + 3.4
		var wh1 := k.on_ground(w1.x, w1.y).y + 0.9
		var steps_n := 5
		for i in steps_n:
			var t0 := float(i) / float(steps_n)
			var t1 := float(i + 1) / float(steps_n)
			_wall_run(k, m, dressed, w0.lerp(w1, t0), w0.lerp(w1, t1), wf, lerpf(wh0, wh1, (t0 + t1) * 0.5), 0.9)
	var lintel := Transform3D(bo, Vector3(door.x, gd + 3.05, door.y) + Vector3(out.x, 0.0, out.y) * 0.2)
	m.block(dressed, lintel, Vector3(3.3, 0.7, 0.75))
	var ped := Transform3D(bo, Vector3(door.x, gd + 3.65, door.y) + Vector3(out.x, 0.0, out.y) * 0.15)
	m.block(dressed, ped, Vector3(2.4, 0.5, 0.6))
	m.block(dressed, Transform3D(bo, Vector3(door.x, gd + 4.0, door.y) + Vector3(out.x, 0.0, out.y) * 0.15), Vector3(1.2, 0.3, 0.6))
	# the steps up the gully floor to the door's sill, broad, from the bier-stone's level
	var steps_from := door + out * 7.5
	var y_from := k.on_ground(steps_from.x, steps_from.y).y
	var climb := gd - y_from
	var n_steps := clampi(int(round(climb / 0.22)), 2, 14)
	m.steps(dressed, steps_from, into, y_from - 0.02, n_steps, climb / float(n_steps), 7.0 / float(n_steps), 3.6, 1.2)
	await k.step()
	m.commit(dressed, PoiKit.painted(2, {"base": "#a8a397", "accent": "#8b867b", "grout": "#57534b", "unit": 0.5}, 0.8, 0.6), "Portal", true)
	# RECEIVED, cut in the lintel: eight letters, each a few strokes dark in the stone
	var cut := m.begin()
	var lf := lintel.origin + Vector3(out.x, 0.0, out.y) * 0.38
	for i in 8:
		var x := (float(i) - 3.5) * 0.3
		var lc := lf + bo * Vector3(x, 0.0, 0.0)
		m.block(cut, Transform3D(bo, lc + Vector3(-0.07, 0.0, 0.0).rotated(Vector3.UP, yaw_out)), Vector3(0.035, 0.34, 0.02))
		m.block(cut, Transform3D(bo, lc + Vector3(0.0, 0.15, 0.0)), Vector3(0.17, 0.035, 0.02))
		if i % 2 == 0:
			m.block(cut, Transform3D(bo, lc), Vector3(0.14, 0.035, 0.02))
		m.block(cut, Transform3D(bo, lc + Vector3(0.0, -0.15, 0.0)), Vector3(0.17, 0.035, 0.02))
	# the dark in the doorway, a hand's depth back
	m.block(cut, Transform3D(bo, Vector3(door.x, gd + 1.35, door.y) + Vector3(into.x, 0.0, into.y) * 0.45), Vector3(1.75, 2.75, 0.1))
	await k.step()
	m.commit(cut, PoiKit.plain(SHAFT_DARK, 1.0), "Received")

	# the Tally Needle at the gully's mouth, off the line of the steps
	var nd := out * 2.0 + side * 3.2
	var ng := _ground_low(k, nd, yaw_out, Vector2(2.8, 2.8)) - 0.15
	var needle := m.begin()
	var y := ng
	for tier in [[2.8, 0.5], [2.2, 0.45], [1.55, 1.9]]:
		var w := float(tier[0])
		var h := float(tier[1])
		var xf := Transform3D(bo, Vector3(nd.x, y + h * 0.5, nd.y))
		m.block(needle, xf, Vector3(w, h, w))
		k.collider(Vector3(w, h, w), xf, "stone")
		y += h
	var die_top := y
	m.block(needle, Transform3D(bo, Vector3(nd.x, y + 0.1, nd.y)), Vector3(1.75, 0.2, 1.75))
	y += 0.2
	var shaft_h := 9.6
	await k.step()
	m.commit(needle, PoiKit.painted(2, LIMEWASH, 0.75, 0.6), "NeedlePlinth", true)
	var shaft := SurfaceTool.new()
	shaft.begin(Mesh.PRIMITIVE_TRIANGLES)
	_frustum(shaft, Vector3(nd.x, y, nd.y), bo, 1.18, 0.74, shaft_h)
	k.collider(Vector3(1.1, shaft_h, 1.1), Transform3D(bo, Vector3(nd.x, y + shaft_h * 0.5, nd.y)), "stone")
	var top_y := y + shaft_h
	await k.step()
	m.commit(shaft, lime, "TallyNeedle", true)
	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	_frustum(cap, Vector3(nd.x, top_y, nd.y), bo, 0.78, 0.02, 1.25)
	await k.step()
	m.commit(cap, PoiKit.plain(BRASS, 0.3, 0.5, BRASS, 0.25), "NeedleCap", true)
	if k.far:
		return
	# the names: close rows on every face of the die and the shaft's foot, each struck through
	var names := m.begin()
	var chalk := m.begin()
	var chalked := false
	for f in 4:
		var fb := bo * Basis(Vector3.UP, float(f) * PI * 0.5)
		var rows := 22
		for r in rows:
			var ry := ng + 1.2 + float(r) * 0.15
			if ry > die_top + 3.0:
				break
			var half_w := 0.775 if ry < die_top else lerpf(1.18, 0.74, (ry - die_top) / shaft_h) * 0.5
			for col in 2:
				var x0 := -half_w + 0.1 + float(col) * half_w
				var letters := 3 + k.rng.randi() % 4
				var lw := (half_w - 0.2) / 7.0
				for l in letters:
					m.block(names, Transform3D(fb, Vector3(nd.x, ry, nd.y) + fb * Vector3(x0 + (float(l) + 0.5) * lw, 0.0, half_w + 0.004)),
							Vector3(lw * 0.7, 0.07, 0.012))
				var strike := Vector3(x0 + lw * float(letters) * 0.5, 0.0, half_w + 0.008)
				m.block(names, Transform3D(fb, Vector3(nd.x, ry, nd.y) + fb * strike), Vector3(lw * float(letters) + 0.06, 0.012, 0.012))
				if f == 0 and col == 0 and not chalked and absf(ry - (ng + 1.75)) < 0.08:
					chalked = true
					for l in letters + 2:
						m.block(chalk, Transform3D(fb, Vector3(nd.x, ry + 0.005, nd.y) + fb * Vector3(x0 + (float(l) + 0.5) * lw * 0.95, 0.0, half_w + 0.016)),
								Vector3(lw * 0.8, 0.09, 0.008))
	await k.step()
	m.commit(names, PoiKit.plain(Color(0.2, 0.19, 0.17), 0.9), "StruckNames")
	m.commit(chalk, PoiKit.plain(Color(0.95, 0.94, 0.9), 0.95), "Chalk")

	# the bier-stone at the steps' foot, where the struck were set down to be received
	var bier := steps_from + out * 2.2 - side * 2.6
	var biers := m.begin()
	var by := k.on_ground(bier.x, bier.y).y
	for s in [-0.8, 0.8]:
		var p := bier + into * float(s)
		_slab(k, m, biers, p, yaw_out, Vector3(0.5, 0.55, 0.5), 0.1)
	var slab := Transform3D(bo, Vector3(bier.x, by + 0.62, bier.y))
	m.block(biers, slab, Vector3(0.95, 0.16, 2.3))
	k.collider(Vector3(0.95, 0.75, 2.3), Transform3D(bo, Vector3(bier.x, by + 0.35, bier.y)), "stone")
	# numbered marker-stones along both sides of the gully, short and plain, some leaning
	var nums := m.begin()
	for s in [-1.0, 1.0]:
		for i in 5:
			var p := steps_from + out * (1.0 + float(i) * 2.3) + side * float(s) * (3.4 + k.rng.randf_range(-0.2, 0.3))
			if p.distance_to(nd) < 2.6 or p.distance_to(bier) < 1.8:
				continue
			var lean := k.rng.randf_range(-0.12, 0.12)
			var mg := k.on_ground(p.x, p.y).y
			var mxf := Transform3D(bo * Basis(Vector3.RIGHT, lean), Vector3(p.x, mg + 0.18, p.y))
			m.block(biers, mxf, Vector3(0.36, 0.75, 0.16))
			m.block(nums, Transform3D(bo * Basis(Vector3.RIGHT, lean), Vector3(p.x, mg + 0.38, p.y) + bo * Vector3(0.0, 0.0, 0.085)), Vector3(0.22, 0.05, 0.01))
	await k.step()
	m.commit(biers, PoiKit.painted(2, {"base": "#9e998e", "accent": "#827d73", "grout": "#4f4b45", "unit": 0.4}, 0.85, 0.7), "BierStones")
	m.commit(nums, PoiKit.plain(Color(0.2, 0.19, 0.17), 0.9), "sign_MarkerNumbers")

	# what the resurrection men leave at the door: a dark lantern, a sack of paper, a sack
	var leave := door + out * 1.6 + side * 1.9
	var lamp := k.prop("lantern_hand")
	if lamp != "":
		await k.step()
		k.place(lamp, k.on_ground(leave.x, leave.y), k.rng.randf() * TAU, 1.0, false)
	await k.step()
	k.place(k.prop("sack"), k.on_ground(leave.x + side.x * 0.8, leave.y + side.y * 0.8), k.rng.randf() * TAU, 1.0, false)
	var paper := k.prop("paper_stack")
	if paper != "":
		await k.step()
		k.place(paper, k.on_ground(bier.x, bier.y) + Vector3(0.0, 0.7, 0.0), k.rng.randf() * TAU, 1.0, false)

	# the way in, the hook on the Needle, where the night's people stand
	_sites()._door(d, str(site.get("interior", "")), Vector3(door.x, gd + 0.05, door.y) + Vector3(out.x, 0.0, out.y) * 0.5, atan2(out.x, out.y))
	var touch := nd + out * 1.6
	k.touchable("Hook", k.on_ground(touch.x, touch.y) + Vector3(0.0, 1.2, 0.0), str(site.get("hook_prompt", "Read the names on the Needle")),
			str(site.get("hook", "")))
	k.marker("the_portal_step", k.on_ground(steps_from.x + out.x * 1.2, steps_from.y + out.y * 1.2))
	k.marker("the_needle_foot", k.on_ground(nd.x + out.x * 2.6 - side.x * 1.0, nd.y + out.y * 2.6 - side.y * 1.0))


# --- phase 2: the places made over -------------------------------------------------------------------

## The Wash-Stones: a spring coming up soft through the chalk into a kerbed wash-pool above the Mere,
## its water running off down a stone-lined runnel toward the shore; three flat stones set at the
## pool's lip, each worn into a dish by the beating, a beetle left on each; the laundresses' copper on
## its fire, lines of guild linen on posts, baskets of it folded, and where Dorcas Pell beats the sheets.
static func wash_stones(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var down := k.water_direction(140.0)
	if down == Vector2.ZERO:
		down = k.downhill()
	if down == Vector2.ZERO:
		down = k.grain()
	down = down.normalized()
	var side := Vector2(-down.y, down.x)
	# keep the pool off the road
	var pc := down * 2.0
	for t in [0.0, 4.0, 8.0, -4.0]:
		var q := down * 2.0 + side * float(t)
		if k.roads.is_empty() or k.road_distance(q) > 9.0:
			pc = q
			break
	var g := k.on_ground(pc.x, pc.y).y
	var lo := g
	for i in 12:
		var a := TAU * float(i) / 12.0
		lo = minf(lo, k.on_ground(pc.x + sin(a) * 3.2, pc.y + cos(a) * 3.2).y)
	var kerb := m.begin()
	m.drum(kerb, Transform3D(Basis.IDENTITY, Vector3(pc.x, lo - 0.2, pc.y)), 3.0, g - lo + 0.62, 0.0, NAN, true, 0.3)
	# the spring's head on the uphill side: a carved spout-stone with the water falling out of it
	var head := pc - down * 3.1
	var hy := k.on_ground(head.x, head.y).y
	var spout := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(down)), Vector3(head.x, hy + 0.7, head.y))
	m.block(kerb, spout, Vector3(1.3, 1.6, 0.8))
	k.collider(Vector3(1.3, 1.6, 0.8), spout, "stone")
	var lip := Vector3(head.x, hy + 1.05, head.y) + Vector3(down.x, 0.0, down.y) * 0.55
	m.block(kerb, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(down)), lip), Vector3(0.22, 0.1, 0.5))
	# the runnel off the pool's lower side, down toward the Mere, lined with stones
	var r0 := pc + down * 3.3
	var water_y := g + 0.12
	var runnel := m.begin()
	for i in 5:
		var p := r0 + down.rotated(float(i) * 0.06) * (float(i) * 1.6 + 0.8)
		var rg := k.on_ground(p.x, p.y).y
		for s in [-1.0, 1.0]:
			var q := p + side * float(s) * 0.55
			m.block(kerb, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(down)), k.on_ground(q.x, q.y, 0.0)), Vector3(0.24, 0.2, 1.5))
		m.block(runnel, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(down)), Vector3(p.x, rg + 0.06, p.y)), Vector3(0.8, 0.02, 1.62))
	# the three beating-stones on the pool's lip toward the Mere, tilted in to it, each dished
	var dish := m.begin()
	var beetles := m.begin()
	var stones: Array[Vector2] = []
	for i in 3:
		var a := (float(i) - 1.0) * 0.75
		var dir := down.rotated(a)
		var at := pc + dir * 3.75
		var yaw := PoiKit.yaw_of(dir)
		var xf := _slab(k, m, kerb, at, yaw + PI * 0.5, Vector3(1.8, 0.55, 1.15), 0.12)
		k.collider(Vector3(1.8, 0.55, 1.15), xf, "stone")
		var ty := _ground_top(k, at, Basis(Vector3.UP, yaw + PI * 0.5), Vector2(1.8, 1.15)) + 0.43
		m.ellipsoid(dish, Vector3(at.x, ty + 0.01, at.y), Vector3(0.55, 0.035, 0.38), Basis(Vector3.UP, yaw))
		# the ground in front of each stone dark where the water slops over
		var wet_at := at + dir * 1.05
		m.ellipsoid(dish, k.on_ground(wet_at.x, wet_at.y, -0.02), Vector3(0.9, 0.04, 0.55), Basis(Vector3.UP, yaw + PI * 0.5))
		var bt := Vector3(at.x, ty + 0.07, at.y) + Vector3(-dir.y, 0.0, dir.x) * 0.55
		m.block(beetles, Transform3D(Basis(Vector3.UP, yaw + 0.4), bt), Vector3(0.13, 0.11, 0.42))
		m.block(beetles, Transform3D(Basis(Vector3.UP, yaw + 0.4), bt + Basis(Vector3.UP, yaw + 0.4) * Vector3(0.0, -0.02, 0.36)), Vector3(0.05, 0.05, 0.32))
		stones.append(at)
	# one beetle put down on the grass by the middle stone
	var dropped := pc + down * 5.2 + side * 0.9
	var dg := k.on_ground(dropped.x, dropped.y)
	m.block(beetles, Transform3D(Basis(Vector3.UP, 0.7), dg + Vector3(0.0, 0.055, 0.0)), Vector3(0.13, 0.11, 0.42))
	await k.step()
	m.commit(kerb, PoiKit.painted(2, {"base": "#b7b3a6", "accent": "#99958a", "grout": "#5d5a52", "unit": 0.36}, 0.75, 0.7), "WashStones", true)
	m.commit(dish, PoiKit.plain(Color(0.36, 0.37, 0.36), 0.25), "Dishes")
	m.commit(beetles, k.surface("timber", 0.6), "Beetles")
	if k.far:
		return
	await k.step()
	var wet := k.still_water(g - 0.55)
	m.pool(pc, 2.62, water_y, wet, "WashPool", 22)
	m.commit(runnel, wet, "Runnel")
	await k.step()
	m.sheet(lip + Vector3(down.x, 0.0, down.y) * 0.18, PoiKit.yaw_of(down), 0.18, lip.y - g + 0.05, PoiKit.falling_water(), "Spout", 0.15, false, 1, 3)
	# the copper on its fire, steaming, on the side away from the road
	var cop_side := side if (k.roads.is_empty() or k.road_distance(pc + side * 7.0) > k.road_distance(pc - side * 7.0)) else -side
	var copper := _clear_spot(k, pc + cop_side * 6.0 - down * 1.0, cop_side, 3.0)
	await k.step()
	k.place(k.prop("campfire"), k.on_ground(copper.x, copper.y), 0.0, 1.0, false)
	var pot := k.prop("cooking_pot")
	if pot != "":
		await k.step()
		k.place(pot, k.on_ground(copper.x, copper.y, 0.12), 0.0, 1.35, false)
	k.puffs(k.on_ground(copper.x, copper.y, 1.0), Vector3(0.3, 0.1, 0.3), 0.8, 10, Color(0.92, 0.92, 0.9, 0.3), 1.4, 4.5)
	# lines of linen drying, the guild's white: two lines of posts back from the pool
	var timber := m.begin()
	var linen := m.begin()
	for row in 2:
		var lc := pc - down * (7.0 + float(row) * 3.0) + cop_side * 1.5
		if not k.roads.is_empty() and minf(k.road_distance(lc + side * 3.3), k.road_distance(lc - side * 3.3)) < 4.0:
			continue
		var ends: Array[Vector3] = []
		for s in [-1.0, 1.0]:
			var pp := lc + side * float(s) * 3.3
			ends.append(m.post(timber, pp, 2.0, 0.12))
		var a3: Vector3 = ends[0]
		var b3: Vector3 = ends[1]
		m.limb(timber, a3 - Vector3(0.0, 0.12, 0.0), b3 - Vector3(0.0, 0.12, 0.0), 0.012)
		for c in 3:
			var t := 0.2 + float(c) * 0.3
			var hang := a3.lerp(b3, t) - Vector3(0.0, 0.14, 0.0)
			var lowest := minf(k.on_ground(hang.x, hang.z).y + 0.35, hang.y - 0.5)
			var h := hang.y - lowest
			m.block(linen, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(down)), hang - Vector3(0.0, h * 0.5, 0.0)), Vector3(1.4, h, 0.025))
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "LinePosts")
	# (cloth hung from a line, as bunting is: the seat audit's word for what hangs off a line in the air)
	m.commit(linen, PoiKit.painted(0, {"base": "#e9e6dc", "accent": "#d6d2c5", "grout": "#b7b3a6", "unit": 0.2}, 0.3, 0.5), "LinenBunting", true)
	# baskets of folded linen and the buckets by the stones
	for i in 2:
		var bk: Vector2 = stones[i * 2] + (stones[i * 2] - pc).normalized() * 1.5 + side * (0.8 if i == 0 else -0.8)
		bk = _clear_spot(k, bk, side, 2.0, false)
		await k.step()
		k.place(k.prop("basket"), k.on_ground(bk.x, bk.y), k.rng.randf() * TAU, 1.0, true)
		var bu := bk + side * 0.85
		await k.step()
		k.place(k.prop("bucket"), k.on_ground(bu.x, bu.y), k.rng.randf() * TAU, 1.0, false)
	var bench := _clear_spot(k, pc - cop_side * 4.5 + down * 2.5, down, 2.5)
	await k.step()
	k.place(k.prop("bench"), k.on_ground(bench.x, bench.y), PoiKit.yaw_of(pc - bench), 1.0, true)
	# Dorcas at the middle stone, on its landward side, facing the pool
	var mid: Vector2 = stones[1]
	_spot(k, "the_beating_stone", _clear_spot(k, mid + (mid - pc).normalized() * 1.3, side, 2.0), pc - mid)


## A heron, standing: a grey body, the long neck in its S, the dagger of a bill, two stick legs. Into
## `grey` (body and neck), `dark` (bill, legs, crest). `at` is its feet (local), `yaw` the way it faces.
static func _heron(m: PoiMasonry, grey: SurfaceTool, dark: SurfaceTool, at: Vector3, yaw: float, s := 1.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var hip := at + Vector3(0.0, 0.78 * s, 0.0)
	for side in [-0.08, 0.08]:
		m.limb(dark, at + b * Vector3(side * s, 0.0, 0.0), hip + b * Vector3(side * s, 0.0, -0.05 * s), 0.018 * s)
	var body := hip + b * Vector3(0.0, 0.14 * s, 0.02 * s)
	m.ellipsoid(grey, body, Vector3(0.16, 0.17, 0.34) * s, b * Basis(Vector3.RIGHT, -0.5))
	var n0 := body + b * Vector3(0.0, 0.12 * s, 0.22 * s)
	var n1 := n0 + b * Vector3(0.0, 0.22 * s, -0.06 * s)
	var n2 := n1 + b * Vector3(0.0, 0.16 * s, 0.12 * s)
	m.limb(grey, n0, n1, 0.045 * s)
	m.limb(grey, n1, n2, 0.04 * s)
	m.ellipsoid(grey, n2 + b * Vector3(0.0, 0.03 * s, 0.03 * s), Vector3(0.05, 0.05, 0.07) * s, b)
	m.limb(dark, n2 + b * Vector3(0.0, 0.03 * s, 0.08 * s), n2 + b * Vector3(0.0, 0.0, 0.3 * s), 0.014 * s)
	m.limb(dark, n2 + b * Vector3(0.0, 0.06 * s, -0.02 * s), n2 + b * Vector3(0.0, 0.03 * s, -0.16 * s), 0.008 * s)


## A heron's nest: a ragged platform of sticks, wider than a cartwheel, with white dripping down
## whatever it sits on. Sticks into `sticks` (a few dozen limbs laid crossways), its middle at `c`.
static func _nest(k: PoiKit, m: PoiMasonry, sticks: SurfaceTool, c: Vector3, r := 0.9) -> void:
	for i in 14:
		var a := k.rng.randf_range(0.0, TAU)
		var off := Vector3(sin(a), 0.0, cos(a)) * k.rng.randf_range(0.0, r * 0.5)
		var dir := Vector3(sin(a + 1.6), k.rng.randf_range(-0.1, 0.15), cos(a + 1.6)).normalized()
		var p := c + off + Vector3(0.0, k.rng.randf_range(0.0, 0.28), 0.0)
		m.limb(sticks, p - dir * r * 0.75, p + dir * r * 0.75, 0.035)
	m.ellipsoid(sticks, c + Vector3(0.0, 0.12, 0.0), Vector3(r * 0.7, 0.16, r * 0.7))


# --- the Heronry --------------------------------------------------------------------------------------

## A dead Builders' tower in the wet meadows above Sedgehithe: a square stalk of black fused stone,
## broken off raggedly, its top and its ledges a city of herons' nests, white with them down every
## face, herons standing on the nests and on the broken top and stalking the wet ground round its
## foot; fallen sticks and eggshell, a doorway with no door, and the Tallymen's clerk's hat still in
## the nettles where he lost it.
static func the_heronry(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var yaw := PoiKit.yaw_of(grain)
	var b := Basis(Vector3.UP, yaw)
	var half := 2.3
	var foot := _ground_low(k, Vector2.ZERO, yaw, Vector2(half * 2.0, half * 2.0)) - 0.3
	var oroth := m.begin()
	# the stalk, in courses that step in as they go up, each face torn off at its own height
	var tops := [17.5, 15.2, 18.6, 13.4]
	var layers := 12
	for f in 4:
		var fb := b * Basis(Vector3.UP, float(f) * PI * 0.5)
		var top := foot + float(tops[f])
		var lh := (top - foot) / float(layers)
		for l in layers:
			var y0 := foot + float(l) * lh
			var inset := float(l) * 0.03
			var w := half * 2.0 - inset * 2.0
			var door := f == 0 and l < 2
			if door:
				for s in [-1.0, 1.0]:
					var px := fb * Vector3(float(s) * (w * 0.5 - 0.7), y0 + lh * 0.5, half - inset - 0.35)
					m.block(oroth, Transform3D(fb, px), Vector3(1.4, lh, 0.7))
				continue
			m.block(oroth, Transform3D(fb, Vector3(0.0, y0 + lh * 0.5, 0.0) + fb * Vector3(0.0, 0.0, half - inset - 0.35)), Vector3(w, lh, 0.7))
	k.collider(Vector3(half * 2.0, 13.4, half * 2.0), Transform3D(b, Vector3(0.0, foot + 6.7, 0.0)), "stone")
	# a ledge every few metres where a course stands proud: where the nests are
	var ledges: Array[Vector3] = []
	for l in [5.2, 9.4, 12.6]:
		for f in 4:
			if foot + float(l) > foot + float(tops[f]) - 0.6:
				continue
			var fb := b * Basis(Vector3.UP, float(f) * PI * 0.5)
			var at := Vector3(0.0, foot + float(l), 0.0) + fb * Vector3(k.rng.randf_range(-0.8, 0.8), 0.0, half + 0.25)
			m.block(oroth, Transform3D(fb, at), Vector3(1.9, 0.3, 0.6))
			ledges.append(at + Vector3(0.0, 0.15, 0.0) + fb * Vector3(0.0, 0.0, 0.15))
	await k.step()
	m.commit(oroth, PoiKit.painted(2, PoiKit.OROTH, 0.45, 0.35), "DeadTower", true)
	# lime from the herons, in long streaks down every face from the ledges and the top
	var lime := m.begin()
	for f in 4:
		var fb := b * Basis(Vector3.UP, float(f) * PI * 0.5)
		for i in 7:
			var x := k.rng.randf_range(-half + 0.3, half - 0.3)
			var y1 := foot + float(tops[f]) - k.rng.randf_range(0.0, 4.0)
			# the first of each face's streaks runs all the way down to the foot
			var streak := k.rng.randf_range(2.0, 7.0) if i > 0 else y1 - foot - 0.25
			m.block(lime, Transform3D(fb, Vector3(0.0, y1 - streak * 0.5, 0.0) + fb * Vector3(x, 0.0, half + 0.012)), Vector3(k.rng.randf_range(0.12, 0.4), streak, 0.02))
	await k.step()
	m.commit(lime, PoiKit.painted(0, {"base": "#e2dfd4", "accent": "#c8c4b6", "grout": "#9c988a", "unit": 0.12}, 0.6, 0.7), "HeronLime", true)
	# the nests: on the broken top of each face and on the ledges, and herons on some
	var sticks := m.begin()
	var grey := m.begin()
	var dark := m.begin()
	var perches: Array[Vector3] = []
	for f in 4:
		var fb := b * Basis(Vector3.UP, float(f) * PI * 0.5)
		var top := Vector3(0.0, foot + float(tops[f]), 0.0) + fb * Vector3(k.rng.randf_range(-0.6, 0.6), 0.0, half - 0.5)
		perches.append(top)
	perches.append_array(ledges)
	var herons := 0
	for i in perches.size():
		var c: Vector3 = perches[i]
		_nest(k, m, sticks, c, 0.85 + k.rng.randf() * 0.3)
		if i % 2 == 0 and herons < 6:
			_heron(m, grey, dark, c + Vector3(0.0, 0.28, 0.0), k.rng.randf_range(0.0, TAU), 1.0)
			herons += 1
	# two more stalking the wet ground off the tower's foot
	for i in 2:
		var a := k.rng.randf_range(0.0, TAU)
		var p := Vector2(sin(a), cos(a)) * k.rng.randf_range(8.0, 12.0)
		_heron(m, grey, dark, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.05)
	await k.step()
	m.commit(sticks, PoiKit.painted(3, {"base": "#6b5d48", "accent": "#4b3f30"}, 0.8, 0.8), "Nests", true)
	m.commit(grey, PoiKit.plain(Color(0.62, 0.64, 0.66), 0.85), "HeronBirds", true)
	m.commit(dark, PoiKit.plain(Color(0.25, 0.22, 0.17), 0.7), "HeronBirdBills")
	if k.far:
		return
	# fallen sticks and eggshell at the foot, and the dark of the doorway
	var fall := m.begin()
	for i in 22:
		var a := k.rng.randf_range(0.0, TAU)
		var p := Vector2(sin(a), cos(a)) * k.rng.randf_range(half + 0.6, half + 4.5)
		var dir := Vector3(sin(a + k.rng.randf_range(0.5, 2.5)), 0.0, cos(a + k.rng.randf_range(0.5, 2.5)))
		var at := k.on_ground(p.x, p.y, 0.03)
		m.limb(fall, at - dir * 0.5, at + dir * 0.5, 0.03)
	await k.step()
	m.commit(fall, PoiKit.painted(3, {"base": "#6b5d48", "accent": "#4b3f30"}, 0.8, 0.8), "FallenSticks")
	var dk := m.begin()
	m.block(dk, Transform3D(b, Vector3(0.0, foot + 1.3, 0.0) + b * Vector3(0.0, 0.0, half - 0.75)), Vector3(1.6, 2.6, 0.08))
	m.commit(dk, PoiKit.plain(SHAFT_DARK, 1.0), "Doorway")
	# the clerk's hat, in the nettles where it came off
	var hat_at := grain * 6.5 + Vector2(-grain.y, grain.x) * 2.0
	var hat := m.begin()
	var hg := k.on_ground(hat_at.x, hat_at.y)
	m.ellipsoid(hat, hg + Vector3(0.0, 0.03, 0.0), Vector3(0.24, 0.03, 0.24), Basis(Vector3.RIGHT, 0.2))
	m.ellipsoid(hat, hg + Vector3(0.0, 0.13, 0.0), Vector3(0.13, 0.12, 0.13), Basis(Vector3.RIGHT, 0.2))
	m.commit(hat, PoiKit.plain(Color(0.16, 0.15, 0.15), 0.9), "ClerksHat")
	k.marker("the_clerks_hat", hg + Vector3(0.0, 0.05, 0.0))
	# reeds and rushes in the wet ground round it
	var reeds := k.flora("reeds")
	if reeds != "":
		var rs: Array = []
		for i in 30:
			var a := k.rng.randf_range(0.0, TAU)
			var p := Vector2(sin(a), cos(a)) * k.rng.randf_range(6.0, 16.0)
			if k.roads.is_empty() or k.road_distance(p) > 3.0:
				rs.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
		await k.step()
		k.scatter(reeds, rs, false, false, false)


## A wreck's lantern hung properly from the head of its stem-post: the kind stands both through
## `dry_spot`, which may move either off the wet, and the lamp was found in the air 3.4 m up with
## nothing within reach of it. With `keep` false (a wreck nobody has lit since she grounded) the lamp
## and its light are taken away instead.
static func _wreck_lamp(d: PoiDressing, keep: bool) -> void:
	var k := d.kit
	if k.far:
		return
	var lamp: Node3D = null
	var post: Node3D = null
	for n in d.get_children():
		var nm := str(n.name)
		if nm.contains("lantern_hanging"):
			lamp = n as Node3D
		elif nm.contains("dock_post"):
			post = n as Node3D
	if lamp == null:
		return
	NightLights.remove(d.get_instance_id())
	if not keep or post == null:
		lamp.queue_free()
		d.remove_child(lamp)
		return
	var pp := post.scene_file_path
	var top := post.position.y + PoiKit.height_of(pp) * post.scale.y
	var lh := PoiKit.height_of(lamp.scene_file_path) * lamp.scale.y
	var out := Vector3(cos(post.rotation.y), 0.0, -sin(post.rotation.y))
	var reach := PoiKit.radius_of(pp) * post.scale.x
	lamp.position = Vector3(post.position.x, top - 0.12 - lh, post.position.z) + out * (reach + 0.14)
	# the iron it hangs from, out of the post's head
	var iron := d.masonry.begin()
	d.masonry.limb(iron, Vector3(post.position.x, top - 0.1, post.position.z), Vector3(lamp.position.x, top - 0.1, lamp.position.z) + out * 0.04, 0.025)
	d.masonry.commit(iron, PoiKit.plain(Color(0.18, 0.17, 0.16), 0.6, 0.5), "LampIron")
	k.light(lamp.position + Vector3(0.0, lh * 0.4, 0.0), Color(1.0, 0.76, 0.45), 1.4, 8.0)


# --- the Beached Barge --------------------------------------------------------------------------------

## The Woodfolk barge as the wreck kind lays a hull, and then what makes her this one: an oak grown up
## through her hold since 1005 and out over her side, her last cargo of baulks still lashed on her
## deck round its trunk, and nailed to her stem the two claims, the Woodfolk's antler-mark and the
## Tallymen's printed notice, each over the other. Nobody has lit her lamp since she grounded.
static func beached_barge(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().wreck(d)
	var k := d.kit
	var m := d.masonry
	_wreck_lamp(d, false)
	var hull := d.find_child("Hull", true, false) as MeshInstance3D
	var water := k.water_direction(70.0)
	var lie := water if water != Vector2.ZERO else k.grain()
	var perp := Vector2(-lie.y, lie.x)
	var g := k.on_ground(0.0, 0.0)
	# the oak, through the hold amidships, leaning a little out of her over the lee side
	var oak := k.tree("oak")
	if oak != "":
		await k.step()
		k.place(oak, g + Vector3(0.0, -0.4, 0.0), k.rng.randf_range(0.0, TAU), 0.85, false, Vector3(0.06, 0.0, -0.05), true)
		k.collider(Vector3(0.9, 4.0, 0.9), Transform3D(Basis.IDENTITY, g + Vector3(0.0, 1.6, 0.0)), "wood")
	if k.far:
		return
	# her cargo: baulks of Wold oak, squared, lashed in a stack on her deck either side of the trunk
	var baulks := m.begin()
	var lash := m.begin()
	for s in [-1.0]:
		for row in 3:
			for i in 2:
				var c := lie * (float(s) * (2.6 + float(i) * 0.1)) + perp * ((float(row) - 1.0) * 0.36)
				var y := g.y + 0.3 + float(i) * 0.4
				var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(lie)), Vector3(c.x, y, c.y))
				m.block(baulks, xf, Vector3(0.32, 0.32, 3.0))
	for s in [-1.0]:
		for band_i in 2:
			var at := lie * (float(s) * (1.6 + float(band_i) * 1.8))
			m.block(lash, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(lie)), Vector3(at.x, g.y + 0.7, at.y)), Vector3(1.45, 0.92, 0.06))
	k.collider(Vector3(1.2, 0.9, 3.0), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(lie)), Vector3(-lie.x * 2.65, g.y + 0.55, -lie.y * 2.65)), "wood")
	await k.step()
	m.commit(baulks, k.surface("timber", 0.85), "Baulks")
	m.commit(lash, PoiKit.plain(Color(0.42, 0.36, 0.27), 0.95), "Lashings")
	# the two claims on her stem: a board with the Woodfolk's antler cut into it, and over it the
	# Tallymen's printed notice, nailed through the antler
	var bow := lie * 6.5
	var by := k.on_ground(bow.x, bow.y).y
	var claim := m.begin()
	var board := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(-lie)), Vector3(bow.x, by + 1.6, bow.y) - Vector3(lie.x, 0.0, lie.y) * 0.45)
	m.block(claim, board, Vector3(0.7, 0.5, 0.05))
	await k.step()
	m.commit(claim, k.surface("planks", 0.7), "sign_WoodfolkClaim")
	var notice := m.begin()
	m.block(notice, Transform3D(board.basis * Basis(Vector3.BACK, 0.12), board.origin + board.basis * Vector3(0.1, -0.05, 0.035)), Vector3(0.32, 0.4, 0.01))
	m.commit(notice, PoiKit.plain(Color(0.84, 0.8, 0.68), 0.9), "sign_TallymenNotice")
	var antler := m.begin()
	for i in 4:
		var a := -0.6 + float(i) * 0.4
		m.block(antler, Transform3D(board.basis * Basis(Vector3.BACK, a), board.origin + board.basis * Vector3(-0.15 + float(i) * 0.04, 0.05, 0.03)), Vector3(0.025, 0.28, 0.01))
	m.commit(antler, PoiKit.plain(Color(0.2, 0.17, 0.13), 0.9), "sign_AntlerMark")
	k.marker("the_claims", Vector3(bow.x, by, bow.y) - Vector3(lie.x, 0.0, lie.y) * 1.2)
	k.touchable("Claims", board.origin - board.basis.z * 0.1, "Read the claims on her stem", "core:dialogue/beached_barge_claims", "", false)
	# the bargemaster's locker, still under her standing side with the cargo's papers in it
	var locker := perp * 2.6 + lie * 3.4
	locker = _clear_spot(k, locker, lie, 3.0)
	_container(d, "bargemasters_locker", k.on_ground(locker.x, locker.y), PoiKit.yaw_of(perp), "core:loot/common_chest", "the bargemaster's locker")
	if hull != null:
		# acorns' children: a few oak seedlings in the shingle round her, the tree's own
		var sap := k.tree("oak_sapling")
		if sap != "":
			var saps: Array = []
			for i in 3:
				var p := perp * k.rng.randf_range(4.0, 7.0) * (1.0 if i % 2 == 0 else -1.0) + lie * k.rng.randf_range(-5.0, 5.0)
				if k.roads.is_empty() or k.road_distance(p) > 3.0:
					saps.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.5, 0.8)))
			await k.step()
			k.scatter(sap, saps, false)


# --- the Charter Stone ------------------------------------------------------------------------------

## The stone the first Charter was cut on: one tall slab broken across by the clans and stood up
## again, its two halves held by brass staples across the break, the Charter's lines cut in close
## rows on its lake face and a clan chain-link on its fell face; the ground round it trodden bare in a
## ring by two peoples coming to swear, and the swearing-stones, one for each side, where they knelt.
static func charter_stone(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var to_lake := k.water_direction(600.0)
	if to_lake == Vector2.ZERO:
		to_lake = k.downhill() if k.downhill() != Vector2.ZERO else k.grain()
	to_lake = to_lake.normalized()
	var yaw := PoiKit.yaw_of(to_lake)
	var b := Basis(Vector3.UP, yaw)
	var lean := Basis(Vector3.RIGHT, 0.04) * Basis(Vector3.BACK, -0.03)
	var g := _ground_low(k, Vector2.ZERO, yaw, Vector2(2.6, 1.0)) - 0.35
	var slab := m.begin()
	var w := 2.2
	var t := 0.55
	var lower_h := 1.9
	var upper_h := 2.4
	var crack := 0.06
	m.block(slab, Transform3D(b * lean, Vector3(0.0, g + lower_h * 0.5, 0.0)), Vector3(w, lower_h, t))
	# the upper half, set back on the lower a hand out of true where it was stood up again
	var up_c := Vector3(0.0, g + lower_h + crack + upper_h * 0.5, 0.0) + b * Vector3(0.05, 0.0, -0.03)
	var up_b := b * lean * Basis(Vector3.BACK, 0.025)
	m.block(slab, Transform3D(up_b, up_c), Vector3(w * 0.96, upper_h, t * 0.95))
	# its top broken off on one shoulder
	m.block(slab, Transform3D(up_b * Basis(Vector3.BACK, 0.5), up_c + up_b * Vector3(-0.55, upper_h * 0.5 - 0.05, 0.0)), Vector3(1.0, 0.35, t * 0.95))
	k.collider(Vector3(w, lower_h + upper_h, t), Transform3D(b, Vector3(0.0, g + (lower_h + upper_h) * 0.5, 0.0)), "stone")
	# the swearing-stones either side, a kneeling-hollow worn in each
	var kneel := m.begin()
	for s in [-1.0, 1.0]:
		var at := to_lake * (1.9 * float(s))
		_slab(k, m, slab, at, yaw + PI * 0.5, Vector3(1.2, 0.3, 0.8), 0.08)
		var ky := _ground_top(k, at, Basis(Vector3.UP, yaw + PI * 0.5), Vector2(1.2, 0.8)) + 0.22
		m.ellipsoid(kneel, Vector3(at.x, ky, at.y), Vector3(0.34, 0.03, 0.24), b)
	await k.step()
	m.commit(slab, PoiKit.painted(2, {"base": "#9a9790", "accent": "#7e7b74", "grout": "#4c4a45", "unit": 0.7}, 0.85, 0.75), "CharterStone", true)
	m.commit(kneel, PoiKit.plain(Color(0.35, 0.34, 0.31), 0.6), "KneelingHollows")
	if k.far:
		return
	# the brass staples across the break: eight were leaded in, and somebody draws one a night; two
	# are left on the lake face, green where the rain gets at them, and the rest are their sockets
	var brass := m.begin()
	var holes := m.begin()
	var break_y := g + lower_h + crack * 0.5
	for f in [-1.0, 1.0]:
		for i in 4:
			var x := -0.75 + float(i) * 0.5
			var p := Vector3(0.0, break_y, 0.0) + b * Vector3(x, 0.0, float(f) * (t * 0.5 + 0.02))
			if f > 0.0 and i in [1, 2]:
				m.block(brass, Transform3D(b, p), Vector3(0.09, 0.42, 0.03))
				for s in [-1.0, 1.0]:
					m.block(brass, Transform3D(b, p + Vector3(0.0, float(s) * 0.19, 0.0)), Vector3(0.13, 0.05, 0.05))
			else:
				for s in [-1.0, 1.0]:
					m.block(holes, Transform3D(b, p + Vector3(0.0, float(s) * 0.19, 0.0) - b * Vector3(0.0, 0.0, float(f) * 0.012)), Vector3(0.07, 0.06, 0.01))
	await k.step()
	m.commit(brass, PoiKit.plain(Color(0.55, 0.52, 0.36), 0.45, 0.7), "CharterPins")
	m.commit(holes, PoiKit.plain(Color(0.08, 0.08, 0.07), 0.9), "sign_PinSockets")
	# the Charter's lines on the lake face, the clans' chain-link on the fell face
	var cut := m.begin()
	for row in 14:
		var y := g + 0.9 + float(row) * 0.2
		if y > g + lower_h + upper_h - 0.5:
			break
		if absf(y - break_y) < 0.18:
			continue
		var len_m := k.rng.randf_range(1.2, 1.75)
		m.block(cut, Transform3D(b, Vector3(0.0, y, 0.0) + b * Vector3(-0.05, 0.0, t * 0.5 + 0.004)), Vector3(len_m, 0.04, 0.01))
	for i in 3:
		var c := Vector3(0.0, g + 2.2 + float(i) * 0.38, 0.0) + b * Vector3(0.0, 0.0, -(t * 0.5 + 0.004))
		for e in 6:
			var a := TAU * float(e) / 6.0
			m.block(cut, Transform3D(b * Basis(Vector3.BACK, a), c + b * Vector3(sin(a) * 0.16, cos(a) * 0.24, 0.0)), Vector3(0.12, 0.035, 0.01))
	await k.step()
	m.commit(cut, PoiKit.plain(Color(0.25, 0.24, 0.22), 0.9), "sign_CharterLines")
	# the ring of bare ground where two peoples have stood to swear for three hundred years
	var bare := m.begin()
	for i in 16:
		var a := TAU * float(i) / 16.0
		var p := Vector2(sin(a), cos(a)) * 4.2
		var pg := k.on_ground(p.x, p.y)
		m.ellipsoid(bare, pg + Vector3(0.0, -0.02, 0.0), Vector3(1.0, 0.04, 0.7), Basis(Vector3.UP, a))
	await k.step()
	m.commit(bare, PoiKit.painted(5, {"base": "#6f6650", "accent": "#5a523f", "grout": "#3d372a", "unit": 0.25}, 0.9, 0.8), "TroddenRing")
	k.marker("the_charter_face", k.on_ground(to_lake.x * 3.0, to_lake.y * 3.0))
	k.touchable("CharterFace", Vector3(0.0, g + 1.6, 0.0) + b * Vector3(0.0, 0.0, t * 0.5 + 0.3), "Read the Charter on the stone", "core:dialogue/charter_stone_lines", "", false)


# --- the Strandline Stones ------------------------------------------------------------------------------

## The three stones as the kind sets them along the old shore, and the old shore itself: a band of
## lake-rounded shingle and bleached driftwood running along the terrace's lip as if the water had
## gone out yesterday, a heron's-worth of shells in it, and the Sayers' benchmark: a squat dressed
## stone with a brass plug in its top and a notch cut in its face for every ten years the Mere has
## fallen since, which is what the Circle and the Lakefolk argue over.
static func strandline_stones(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().standing_stones(d)
	var k := d.kit
	var m := d.masonry
	if k.far:
		return
	var grain := k.grain()
	var along := Vector2(-grain.y, grain.x)
	var to_lake := k.water_direction(500.0)
	if to_lake == Vector2.ZERO:
		to_lake = k.downhill() if k.downhill() != Vector2.ZERO else grain
	# the shingle band, a stride wide, on the lake side of the stones, following the lie of the land
	var pebble := k.rock("boulder")
	var shingle: Array = []
	for i in 70:
		var t := k.rng.randf_range(-15.0, 15.0)
		var p := along * t + to_lake * (2.6 + k.rng.randf_range(-0.9, 0.9) + sin(t * 0.3) * 0.6)
		if not k.roads.is_empty() and k.road_distance(p) < 3.5:
			continue
		var sc := k.rng.randf_range(0.06, 0.16)
		shingle.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.35 * sc), k.rng.randf_range(0.0, TAU), sc))
	if pebble != "":
		await k.step()
		k.scatter(pebble, shingle, false)
	# driftwood, grey and bleached, lying along the old tide-line
	var drift := m.begin()
	for i in 6:
		var t := k.rng.randf_range(-12.0, 12.0)
		var p := along * t + to_lake * (3.2 + k.rng.randf_range(-0.5, 0.5))
		if not k.roads.is_empty() and k.road_distance(p) < 3.5:
			continue
		var dir := along.rotated(k.rng.randf_range(-0.5, 0.5))
		var l := k.rng.randf_range(1.2, 2.8)
		var a := k.on_ground(p.x - dir.x * l * 0.5, p.y - dir.y * l * 0.5, 0.08)
		var bb := k.on_ground(p.x + dir.x * l * 0.5, p.y + dir.y * l * 0.5, 0.08)
		m.limb(drift, a, bb, k.rng.randf_range(0.07, 0.14))
		if i % 2 == 0:
			var mid := (a + bb) * 0.5
			var off := Vector3(-dir.y, 0.0, dir.x) * 0.5
			m.limb(drift, mid, k.on_ground(mid.x + off.x, mid.z + off.z, 0.05), 0.05)
	await k.step()
	m.commit(drift, PoiKit.painted(3, {"base": "#a8a296", "accent": "#857f73"}, 0.9, 0.7), "Driftwood")
	# the benchmark: dressed, squat, the brass plug in its top and its notches down the lake face
	var bm := grain * 4.5 - along * 6.0
	if not k.roads.is_empty() and k.road_distance(bm) < 4.0:
		bm = -grain * 4.5 - along * 6.0
	var bmy := _ground_low(k, bm, PoiKit.yaw_of(to_lake), Vector2(0.8, 0.8)) - 0.25
	var bxf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(to_lake)), Vector3(bm.x, bmy + 0.6, bm.y))
	var bench := m.begin()
	m.block(bench, bxf, Vector3(0.7, 1.2, 0.7))
	k.collider(Vector3(0.7, 1.2, 0.7), bxf, "stone")
	await k.step()
	m.commit(bench, PoiKit.painted(2, {"base": "#bdb8ab", "accent": "#a19c90", "grout": "#66625a", "unit": 0.5}, 0.6, 0.6), "Benchmark")
	var plug := m.begin()
	m.rod(plug, Transform3D(Basis.IDENTITY, bxf.origin + Vector3(0.0, 0.62, 0.0)), 0.09, 0.05)
	var notches := m.begin()
	for i in 10:
		m.block(notches, Transform3D(bxf.basis, bxf.origin + Vector3(0.0, 0.45 - float(i) * 0.09, 0.0) + bxf.basis * Vector3(0.0, 0.0, 0.354)), Vector3(0.22 if i % 5 == 4 else 0.12, 0.025, 0.01))
	m.commit(plug, PoiKit.plain(Color(0.64, 0.52, 0.28), 0.35, 0.85), "BenchmarkBrass")
	m.commit(notches, PoiKit.plain(Color(0.2, 0.19, 0.17), 0.9), "sign_BenchmarkNotches")
	k.marker("the_benchmark", Vector3(bm.x, bmy + 0.25, bm.y) + Vector3(to_lake.x, 0.0, to_lake.y) * 0.8)
	k.touchable("Benchmark", bxf.origin + Vector3(0.0, 0.3, 0.0) + bxf.basis * Vector3(0.0, 0.0, 0.5), "Read the benchmark's notches", "core:dialogue/strandline_benchmark", "", false)


# --- the Pilgrim Stair ----------------------------------------------------------------------------------

## The Builders' stair from the North Shore's terrace into the Mere: a landing of black fused flags with
## a broken stalk either side, a processional way out to the terrace's lip between low bollards, and
## from the lip the stair itself, broad, kerbed, going down the old beach in one straight flight and on
## into the water without a pause, the last steps under the surface. On the last dry step an iron ring
## with the Sayer's rope tied to it, still taut, going down into the water at a slant.
static func pilgrim_stair(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var dir := k.water_direction(120.0)
	if dir == Vector2.ZERO:
		dir = k.downhill() if k.downhill() != Vector2.ZERO else k.grain()
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)
	var yaw := PoiKit.yaw_of(dir)
	var b := Basis(Vector3.UP, yaw)
	var oroth := m.begin()
	# the water's edge along the stair's line, and where the terrace's lip is (the fall begins)
	var g0 := k.on_ground(0.0, 0.0).y
	var edge := 48.0
	var lip := 18.0
	var dd := 4.0
	var found_lip := false
	while dd < 110.0:
		var p := dir * dd
		if not found_lip and g0 - k.on_ground(p.x, p.y).y > 0.9:
			lip = maxf(dd - 2.0, 8.0)
			found_lip = true
		if k.is_water(p.x, p.y):
			edge = dd
			break
		dd += 1.0
	# the landing and its two broken stalks
	var lg := _ground_low(k, Vector2.ZERO, yaw, Vector2(7.0, 7.0)) - 0.15
	var land := Transform3D(b, Vector3(0.0, lg + 0.2, 0.0))
	m.block(oroth, land, Vector3(7.0, 0.4, 7.0))
	k.collider(Vector3(7.0, 0.4, 7.0), land, "stone")
	for s in [-1.0, 1.0]:
		var p := side * float(s) * 3.0 - dir * 2.6
		var h := 8.5 if s < 0.0 else 5.2
		var xf := Transform3D(b, Vector3(p.x, lg + 0.4 + h * 0.5, p.y))
		m.block(oroth, xf, Vector3(1.0, h, 1.0))
		k.collider(Vector3(1.0, h, 1.0), xf, "stone")
		m.block(oroth, Transform3D(b * Basis(Vector3.BACK, 0.3 * float(s)), Vector3(p.x, lg + 0.4 + h + 0.2, p.y)), Vector3(0.9, 0.45, 0.9))
	# the processional way to the lip, flagged, a bollard each side every four metres
	var way_from := 3.5
	var n_flags := int((lip - way_from) / 1.6)
	for i in n_flags:
		var c := dir * (way_from + 0.8 + float(i) * 1.6)
		var cy := k.on_ground(c.x, c.y).y
		m.block(oroth, Transform3D(b, Vector3(c.x, cy - 0.05, c.y)), Vector3(3.6, 0.22, 1.56))
		if i % 2 == 0:
			for s in [-1.0, 1.0]:
				var bp := c + side * float(s) * 2.4
				var bxf := Transform3D(b, k.on_ground(bp.x, bp.y, 0.35))
				m.block(oroth, bxf, Vector3(0.45, 0.8, 0.45))
				k.collider(Vector3(0.45, 0.8, 0.45), bxf, "stone")
	# the stair: one flight from the lip down the old beach and on under the water
	var top := dir * lip
	var top_y := k.on_ground(top.x, top.y).y
	var wy := k.water_y(dir.x * (edge + 1.0), dir.y * (edge + 1.0))
	if is_nan(wy) or wy < -1000.0:
		wy = k.on_ground(dir.x * edge, dir.y * edge).y
	var bottom_y := wy - 1.0
	var run := edge + 3.0 - lip
	var steps := clampi(int(round((top_y - bottom_y) / 0.2)), 6, 90)
	var rise := (top_y - bottom_y) / float(steps)
	var tread := run / float(steps)
	m.steps(oroth, top, dir, top_y + 0.02, steps, -rise, tread, 4.8, 1.6)
	# its kerbs, a course proud of the treads, down both sides
	for s in [-1.0, 1.0]:
		for i in steps:
			if i % 3 != 0:
				continue
			var p := top + dir * (tread * (float(i) + 1.5)) + side * float(s) * 2.65
			var y := top_y - rise * (float(i) + 1.5) + 0.3
			m.block(oroth, Transform3D(b, Vector3(p.x, y - 0.5, p.y)), Vector3(0.6, 1.8, tread * 3.05))
	await k.step()
	m.commit(oroth, PoiKit.painted(2, PoiKit.OROTH, 0.5, 0.35), "PilgrimStair", true)
	if k.far:
		return
	# the last dry step: its ring, and the rope off it going down into the water
	var dry_i := 0
	for i in steps:
		var p := top + dir * (tread * (float(i) + 0.5))
		if k.is_water(p.x, p.y):
			break
		dry_i = i
	var ring_at := top + dir * (tread * (float(dry_i) + 0.5)) + side * 1.2
	var ring_y := top_y - rise * float(dry_i + 1) + 0.04
	var iron := m.begin()
	m.rod(iron, Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, yaw), Vector3(ring_at.x, ring_y + 0.06, ring_at.y)), 0.09, 0.05)
	m.commit(iron, PoiKit.plain(Color(0.2, 0.18, 0.16), 0.6, 0.6), "RopeRing")
	var rope := m.begin()
	var into_water := Vector3(ring_at.x, ring_y, ring_at.y) + Vector3(dir.x, 0.0, dir.y) * 9.0 + Vector3(0.0, -2.6, 0.0)
	m.limb(rope, Vector3(ring_at.x, ring_y + 0.08, ring_at.y), into_water, 0.03)
	# the knot on the ring and a tail of it lying on the step
	m.ellipsoid(rope, Vector3(ring_at.x, ring_y + 0.1, ring_at.y), Vector3(0.12, 0.08, 0.12))
	m.limb(rope, Vector3(ring_at.x, ring_y + 0.06, ring_at.y), Vector3(ring_at.x, ring_y + 0.04, ring_at.y) + Vector3(-dir.x * 0.4 + side.x * 0.5, 0.0, -dir.y * 0.4 + side.y * 0.5), 0.025)
	m.commit(rope, PoiKit.plain(Color(0.52, 0.47, 0.36), 0.95), "SayersRope")
	k.marker("the_last_dry_step", Vector3(ring_at.x, ring_y, ring_at.y) - Vector3(side.x, 0.0, side.y) * 1.2)
	k.marker("the_landing", k.on_ground(dir.x * 1.5, dir.y * 1.5))


# --- the Ness Market ------------------------------------------------------------------------------------

## A fish on a slab: a silver-grey body, a darker back, laid at `at` (local) along `yaw`, `l` long.
static func _fish(m: PoiMasonry, belly: SurfaceTool, back: SurfaceTool, at: Vector3, yaw: float, l: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	m.ellipsoid(belly, at + Vector3(0.0, l * 0.06, 0.0), Vector3(l * 0.12, l * 0.07, l * 0.5), b)
	m.ellipsoid(back, at + Vector3(0.0, l * 0.1, 0.0), Vector3(l * 0.07, l * 0.04, l * 0.42), b)
	m.block(back, Transform3D(b, at + b * Vector3(0.0, l * 0.06, -l * 0.52)), Vector3(l * 0.22, l * 0.08, l * 0.06))


## The Lakefolk's fish market on the Stride Ness, where a fish sold pays no city toll: awnings and
## trestles in two rows down a lane, the morning's catch laid out silver on the boards, pike and eel
## and perch, baskets and crates and a barrel of eels, a smoking-rack over a slow fire, a net drying on
## poles; and across the Ness's root, where the Tallymen want their toll-line, a row of lime-white
## stones a toll-man has set out himself, his stool and his ledger on a little table beside them.
static func ness_market(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var road := k.road_direction(60.0)
	var lane := road.normalized() if road != Vector2.ZERO else k.grain()
	var across := Vector2(-lane.y, lane.x)
	# the lane runs beside the road, not on it: the market stands to the side the road is not
	var off := 0.0
	if not k.roads.is_empty():
		var near_r := k.road_distance(Vector2.ZERO)
		if near_r < 9.0:
			off = 9.0 - near_r
			if k.road_distance(across * 4.0) < k.road_distance(-across * 4.0):
				across = -across
	var c := across * off
	var yaw_l := PoiKit.yaw_of(lane)
	var stall := k.prop("market_stall")
	var table := k.prop("table_trestle")
	var th := PoiKit.height_of(table) if table != "" else 0.8
	var tables: Array[Vector2] = []
	for row in [-1.0, 1.0]:
		for i in 3:
			var p := c + across * float(row) * 4.2 + lane * (float(i) - 1.0) * 5.4
			if not k.roads.is_empty() and k.road_distance(p) < 3.5:
				continue
			var face := -across * float(row)
			if i == 1 and stall != "":
				await k.step()
				k.place(stall, k.on_ground(p.x, p.y), PoiKit.yaw_of(face), 1.0, true)
				continue
			if table == "":
				continue
			await k.step()
			k.place(table, k.on_ground(p.x, p.y), yaw_l + PI * 0.5, 1.0, true)
			tables.append(p)
			# an awning over it on two poles, the cloth sloping to the lane
			var aw := m.begin()
			var cloth := m.begin()
			var back_side := -face
			var ptop: Array[Vector3] = []
			for s2 in [-1.0, 1.0]:
				var pp := p + back_side * 0.8 + lane * 1.2 * float(s2)
				ptop.append(m.post(aw, pp, 2.6, 0.08))
			var hi_mid := ((ptop[0] as Vector3) + (ptop[1] as Vector3)) * 0.5
			var lo_mid := hi_mid + Vector3(face.x, 0.0, face.y) * 1.9 + Vector3(0.0, -0.55, 0.0)
			var tilt := atan2(0.55, 1.9)
			m.block(cloth, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)) * Basis(Vector3.RIGHT, tilt), (hi_mid + lo_mid) * 0.5), Vector3(2.7, 0.03, 2.0))
			await k.step()
			m.commit(aw, k.surface("timber", 0.6), "AwningPoles%d" % tables.size())
			var hue: Color = [Color(0.62, 0.32, 0.22), Color(0.3, 0.45, 0.58), Color(0.86, 0.84, 0.76), Color(0.55, 0.47, 0.28)][tables.size() % 4]
			m.commit(cloth, PoiKit.plain(hue, 0.9), "Awning_bunting%d" % tables.size())
			if k.far:
				continue
			# the catch on each table its own mesh, so each lies on its own table
			var top := k.on_ground(p.x, p.y).y + th
			var belly := m.begin()
			var back := m.begin()
			for f in 6:
				var fp := p + lane * k.rng.randf_range(-0.7, 0.7) + across * k.rng.randf_range(-0.25, 0.25)
				_fish(m, belly, back, Vector3(fp.x, top, fp.y), PoiKit.yaw_of(across) + k.rng.randf_range(-0.4, 0.4), k.rng.randf_range(0.35, 0.7))
			await k.step()
			m.commit(belly, PoiKit.plain(Color(0.72, 0.74, 0.72), 0.3, 0.3), "FishCatch%d" % tables.size())
			m.commit(back, PoiKit.plain(Color(0.3, 0.34, 0.3), 0.5), "FishBacks%d" % tables.size())
	if k.far:
		return
	# baskets, crates and the eel-barrel down the lane
	for i in 7:
		var p := c + across * (k.rng.randf_range(-2.4, 2.4)) + lane * k.rng.randf_range(-8.5, 8.5)
		p = _clear_spot(k, p, lane, 3.0, true)
		await k.step()
		k.place(k.prop(["basket", "crate", "barrel", "basket", "basket", "crate", "bucket"][i]), k.on_ground(p.x, p.y), k.rng.randf() * TAU, 1.0, true)
	# the smoking-rack: four posts, rails across, split fish hung on them, over a slow fire
	var rack := _clear_spot(k, c + across * 9.5 + lane * 4.0, lane, 3.0)
	var timber := m.begin()
	var smoked := m.begin()
	var tops: Array[Vector3] = []
	for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		tops.append(m.post(timber, rack + lane * 1.1 * float(s[0]) + across * 0.6 * float(s[1]), 1.9, 0.1))
	for r in 3:
		var y := minf(tops[0].y, tops[1].y) - 0.1 - float(r) * 0.32
		var a := (tops[0] + tops[3]) * 0.5
		var bb := (tops[1] + tops[2]) * 0.5
		m.limb(timber, Vector3(a.x, y, a.z), Vector3(bb.x, y, bb.z), 0.03)
		for f in 5:
			var fp: Vector3 = Vector3(a.x, y, a.z).lerp(Vector3(bb.x, y, bb.z), 0.15 + float(f) * 0.17)
			m.ellipsoid(smoked, fp - Vector3(0.0, 0.2, 0.0), Vector3(0.08, 0.2, 0.03), Basis(Vector3.UP, yaw_l + PI * 0.5))
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "SmokingRack")
	m.commit(smoked, PoiKit.plain(Color(0.42, 0.3, 0.17), 0.7), "SmokedFish")
	await k.step()
	k.place(k.prop("campfire"), k.on_ground(rack.x, rack.y), 0.0, 0.8, false)
	k.puffs(k.on_ground(rack.x, rack.y, 1.4), Vector3(0.6, 0.2, 0.4), 1.2, 12, Color(0.7, 0.68, 0.64, 0.35), 1.8, 6.0)
	k.light(k.on_ground(rack.x, rack.y, 0.4), Color(1.0, 0.68, 0.38), 1.6, 9.0)
	# the toll-man's line across the Ness's root: lime-white stones, his stool, his table and ledger
	var line_c := _clear_spot(k, c - lane * 13.0, across, 3.0, false)
	var stones := m.begin()
	for i in 9:
		var p := line_c + across * (float(i) - 4.0) * 1.3
		if not k.roads.is_empty() and k.road_distance(p) < 3.2:
			continue
		var g := k.on_ground(p.x, p.y)
		m.block(stones, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), g + Vector3(0.0, 0.08, 0.0)), Vector3(0.32, 0.22, 0.26))
	await k.step()
	m.commit(stones, PoiKit.painted(0, LIMEWASH, 0.6, 0.6), "TollLineStones")
	var desk := _clear_spot(k, line_c + across * 7.5 - lane * 1.0, lane, 3.0)
	var round_t := k.prop("table_round")
	if round_t != "":
		await k.step()
		k.place(round_t, k.on_ground(desk.x, desk.y), 0.0, 1.0, true)
		var book := k.prop("book")
		if book != "":
			await k.step()
			k.place(book, k.on_ground(desk.x, desk.y) + Vector3(0.0, PoiKit.height_of(round_t), 0.0), k.rng.randf() * TAU, 1.0, false)
	await k.step()
	k.place(k.prop("stool"), k.on_ground(desk.x + lane.x * 0.9, desk.y + lane.y * 0.9), PoiKit.yaw_of(-lane), 1.0, true)
	# where the people stand: the fishwife behind her first table, the toll-man at his line
	var fishwife := c + across * 2.0
	if not tables.is_empty():
		var t0: Vector2 = tables[0]
		fishwife = t0 + across * (1.1 if (t0 - c).dot(across) > 0.0 else -1.1)
	_spot(k, "the_fish_stall", _clear_spot(k, fishwife, lane, 2.0), -across)
	_spot(k, "the_toll_line", _clear_spot(k, desk + lane * 1.6, across, 2.0), across)


# --- the Dry Jetty ------------------------------------------------------------------------------------

## Gullhithe's old landing, left in a hayfield as the Mere fell: a plank jetty on its piles running out
## from where the bank was toward where the water was, level as a jetty is, so the land falls away
## under it and its far end stands high on bare legs over the grass; mooring bollards along it, a
## ladder at its end going down to nothing, a ring for a boat that is a field away, hay in cocks
## round its feet, and on its last post the eel-wives' lantern, hung from an iron, that they still
## light at dusk from habit.
static func dry_jetty(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var out := k.water_direction(260.0)
	if out == Vector2.ZERO:
		out = k.downhill() if k.downhill() != Vector2.ZERO else k.grain()
	out = out.normalized()
	var side := Vector2(-out.y, out.x)
	var yaw := PoiKit.yaw_of(out)
	var a := -out * 6.0
	var b := out * 18.0
	# the deck: level, a little over the bank at its landward end
	var deck_y := k.on_ground(a.x, a.y).y + 0.55
	var planks := m.begin()
	var posts := m.begin()
	await k.step()
	m.plank_deck(planks, posts, a, b, 2.8, deck_y, 2.4, false)
	# the piles at the end stand proud of the deck: bollards for the boats that do not come
	var bollards: Array[Vector3] = []
	for i in 4:
		var t := 0.35 + float(i) * 0.2
		var p := a.lerp(b, t) + side * (1.25 if i % 2 == 0 else -1.25)
		var g := k.on_ground(p.x, p.y).y
		var h := deck_y + 0.6 - g
		m.block(posts, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, g + h * 0.5, p.y)), Vector3(0.28, h, 0.28))
		k.collider(Vector3(0.28, 0.6, 0.28), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, deck_y + 0.3, p.y)), "wood")
		bollards.append(Vector3(p.x, deck_y + 0.6, p.y))
	# the end post, taller, for the lantern
	var lamp_post := b - out * 0.3 + side * 1.2
	var lg := k.on_ground(lamp_post.x, lamp_post.y).y
	var lh := deck_y + 2.4 - lg
	m.block(posts, Transform3D(Basis(Vector3.UP, yaw), Vector3(lamp_post.x, lg + lh * 0.5, lamp_post.y)), Vector3(0.22, lh, 0.22))
	k.collider(Vector3(0.22, 2.4, 0.22), Transform3D(Basis(Vector3.UP, yaw), Vector3(lamp_post.x, deck_y + 1.2, lamp_post.y)), "wood")
	var arm_from := Vector3(lamp_post.x, deck_y + 2.3, lamp_post.y)
	var arm_to := arm_from + Vector3(out.x, 0.0, out.y) * 0.55
	m.block(posts, Transform3D(Basis(Vector3.UP, yaw), (arm_from + arm_to) * 0.5), Vector3(0.08, 0.08, 0.6))
	# the ladder off the end, its foot in the grass
	var lad := b + out * 0.15
	var foot_y := k.on_ground(lad.x, lad.y).y
	for s in [-1.0, 1.0]:
		var r := lad + side * 0.32 * float(s)
		m.limb(posts, Vector3(r.x, foot_y - 0.1, r.y) + Vector3(out.x, 0.0, out.y) * 0.35, Vector3(r.x, deck_y + 0.8, r.y), 0.04)
	var rungs := int((deck_y - foot_y) / 0.32)
	for i in rungs:
		var y := foot_y + 0.3 + float(i) * 0.32
		var t := (y - foot_y) / maxf(deck_y + 0.8 - foot_y, 0.1)
		var c := lad + out * (0.35 * (1.0 - t))
		m.limb(posts, Vector3(c.x - side.x * 0.32, y, c.y - side.y * 0.32), Vector3(c.x + side.x * 0.32, y, c.y + side.y * 0.32), 0.025)
	await k.step()
	m.commit(planks, k.surface("planks", 0.85), "Jetty", true)
	m.commit(posts, k.surface("timber", 0.75), "JettyPiles", true)
	if k.far:
		return
	# a boat's ring on the end bollard, and a cut mooring rope hanging off it
	var ring := m.begin()
	var bl: Vector3 = bollards[bollards.size() - 1]
	m.rod(ring, Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, yaw), bl + Vector3(side.x, 0.0, side.y) * 0.2 + Vector3(0.0, -0.15, 0.0)), 0.07, 0.04)
	m.limb(ring, bl + Vector3(side.x, 0.0, side.y) * 0.22 + Vector3(0.0, -0.2, 0.0), bl + Vector3(side.x, 0.0, side.y) * 0.3 + Vector3(0.0, -1.1, 0.0), 0.02)
	m.commit(ring, PoiKit.plain(Color(0.25, 0.22, 0.19), 0.6, 0.5), "MooringRing")
	# the eel-wives' lantern, hung from the iron
	var hang := k.prop("lantern_hanging")
	if hang != "":
		var hh := PoiKit.height_of(hang)
		await k.step()
		k.place(hang, arm_to - Vector3(0.0, hh + 0.05, 0.0), yaw, 1.0, false)
		k.light(arm_to - Vector3(0.0, hh * 0.6, 0.0), Color(1.0, 0.76, 0.45), 1.3, 8.0)
	# an eel-trap and a basket left on the deck at the landward end, where they walk out from
	var trap_at := a + out * 2.0 - side * 0.7
	await k.step()
	k.place(k.prop("basket"), Vector3(trap_at.x, deck_y + 0.0, trap_at.y), k.rng.randf() * TAU, 1.0, false)
	# hay in cocks round the jetty's feet: it stands in a hayfield
	var hay := k.prop("hay_bale")
	if hay != "":
		for i in 5:
			var p := out * k.rng.randf_range(-4.0, 22.0) + side * k.rng.randf_range(4.5, 9.0) * (1.0 if i % 2 == 0 else -1.0)
			p = _clear_spot(k, p, side, 3.0, false)
			await k.step()
			k.place(hay, k.on_ground(p.x, p.y), k.rng.randf() * TAU, k.rng.randf_range(0.9, 1.1), true)
	var grass := k.flora("meadow_grass")
	if grass == "":
		grass = k.flora("grass_clump")
	var tufts: Array = []
	for i in 40:
		var p := out * k.rng.randf_range(-8.0, 22.0) + side * k.rng.randf_range(-9.0, 9.0)
		if not k.roads.is_empty() and k.road_distance(p) < 3.0:
			continue
		tufts.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf() * TAU, k.rng.randf_range(0.9, 1.4)))
	await k.step()
	k.scatter(grass, tufts, false, false, false)
	k.marker("the_jetty_end", Vector3(b.x, deck_y + 0.05, b.y) - Vector3(out.x, 0.0, out.y) * 1.0, true)
	# the last pile, wet to the knee in a dry field, and the wet ground at its foot where the drakes nest
	var wet := m.begin()
	var pile := b - side * 1.18
	var pg := k.on_ground(pile.x, pile.y)
	m.block(wet, Transform3D(Basis(Vector3.UP, yaw), pg + Vector3(0.0, 0.25, 0.0)), Vector3(0.26, 0.6, 0.26))
	m.ellipsoid(wet, pg + Vector3(0.0, -0.03, 0.0), Vector3(1.3, 0.05, 1.0), Basis(Vector3.UP, yaw))
	m.commit(wet, PoiKit.plain(Color(0.16, 0.15, 0.12), 0.25), "WetPile")
	k.marker("under_the_last_pile", pg + Vector3(side.x, 0.0, side.y) * -1.5)


# --- places the kinds build, set straight (triage 74) -------------------------------------------------

## The children of the dressing whose name says `what` (a placed asset is named for its file).
static func _named(d: PoiDressing, what: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in d.get_children():
		if n is Node3D and str(n.name).contains(what):
			out.append(n as Node3D)
	return out


## A boat the kind set on the lake's bed, floated, and a mooring post driven into the bed brought up
## so it stands out of the water: the probe found Willow Isle's rowboat 120% under the ground at its
## middle and its post 85% (both under the Mere, as they were laid on the bed beneath it).
static func _float_boats(d: PoiDressing) -> void:
	var k := d.kit
	for boat in _named(d, "rowboat"):
		var box := _drawn_local(boat)
		var g := k.on_ground(boat.position.x, boat.position.z).y
		var wy := k.water_y(boat.position.x, boat.position.z)
		# her keel on the bed where the bed is dry, her waterline at the water where it is not
		var floor_y := g - 0.08 if is_nan(wy) or wy < g + 0.15 else wy - box.size.y * 0.35
		boat.position.y += floor_y - box.position.y
	for post in _named(d, "dock_post"):
		var box := _drawn_local(post)
		var g := k.on_ground(post.position.x, post.position.z).y
		var wy := k.water_y(post.position.x, post.position.z)
		var top := maxf(g, wy if not is_nan(wy) else g) + 0.8
		# its head a hand under the water's top or the ground's, its foot a third of it in the bed
		post.position.y += maxf(top - box.end.y, g - box.size.y * 0.3 - box.position.y)


## A placed thing's drawn box in its parent's space (the dressing's).
static func _drawn_local(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if g.mesh == null:
			continue
		var xf := n.transform
		var at: Node = g
		var chain := Transform3D.IDENTITY
		while at != null and at != n:
			if at is Node3D:
				chain = (at as Node3D).transform * chain
			at = at.get_parent()
		var b := (xf * chain) * g.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(n.position, Vector3.ZERO)
	return box


## A stool or a bench the camp set in its own fire (Rafters' Camp: the stool 66-100% in the
## campfire's box), moved out to sit at the fire, not in it.
static func _seats_off_fires(d: PoiDressing) -> void:
	var k := d.kit
	for fire in _named(d, "campfire"):
		for what in ["stool", "bench", "log_seat"]:
			for seat in _named(d, what):
				var off := Vector2(seat.position.x - fire.position.x, seat.position.z - fire.position.z)
				if off.length() < 2.2:
					var dir := off.normalized() if off.length() > 0.05 else Vector2(1.0, 0.0)
					var fc := Vector2(fire.position.x, fire.position.z)
					var at := fc + dir * 1.9
					for t in 8:
						var q := fc + dir.rotated(TAU * float(t) / 8.0) * 1.9
						if k.roads.is_empty() or k.road_distance(q) > 3.5:
							at = q
							break
					seat.position = k.on_ground(at.x, at.y)
					seat.rotation.y = PoiKit.yaw_of(fc - at)


static func hespers_boat(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().build(d)
	# Hesper lived thirty years in her: her lamp is lit, hung from the stem-post's head
	_wreck_lamp(d, true)


static func laundry_punt(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().build(d)
	# nobody has lit the laundresses' punt since she was dragged up the bank
	_wreck_lamp(d, false)


static func gullhithe_wreck(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().build(d)
	_wreck_lamp(d, true)


static func rafters_camp(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().build(d)
	_seats_off_fires(d)


static func willow_isle(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().build(d)
	_float_boats(d)
	_seats_off_fires(d)
	# the hermit's fire out from under the willow's trunk, to the side of it away from the water
	var k := d.kit
	for tree in _named(d, "willow"):
		for fire in _named(d, "campfire"):
			var off := Vector2(fire.position.x - tree.position.x, fire.position.z - tree.position.z)
			if off.length() < 3.5:
				var dir := off.normalized() if off.length() > 0.05 else k.grain()
				var at := Vector2(tree.position.x, tree.position.z) + dir * 3.8
				if k.is_water(at.x, at.y):
					at = Vector2(tree.position.x, tree.position.z) - dir * 3.8
				fire.position = k.on_ground(at.x, at.y)


## The Long Stride's toll: the causeway lays its table and its chest on the deck, and `place` moved
## both off the water as it moves anything stood over water, so the chest hung 1.5 m over the shallows
## beside the deck. Set back on the deck by the table.
static func long_stride(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().build(d)
	var k := d.kit
	var road := k.road_direction(90.0)
	var water := k.water_direction(70.0)
	var axis := road if road != Vector2.ZERO else (water if water != Vector2.ZERO else k.grain())
	var dir := water if water != Vector2.ZERO else axis
	var start := -dir * 8.0
	var wl := k.water_y(dir.x * 30.0, dir.y * 30.0)
	var deck_y := maxf(k.on_ground(start.x, start.y).y + 0.3, (wl if not is_nan(wl) else 0.0) + 1.3)
	var perp := Vector2(-dir.y, dir.x)
	var gate := start + dir * 3.0
	# the chest goes in under the table, where a toll-keeper keeps the day's takings
	for chest in _named(d, "chest"):
		d.remove_child(chest)
		chest.queue_free()
	for table in _named(d, "table_trestle"):
		table.position = Vector3(gate.x + perp.x * 0.9, deck_y + 0.21, gate.y + perp.y * 0.9)


## The Shingle Shrine's Hearthstone, set on its pebbles and not a hand over them.
static func shingle_shrine(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().build(d)
	var k := d.kit
	for n in d.find_children("*", "Hearthstone", true, false):
		var h := n as Node3D
		var g := k.on_ground(h.position.x, h.position.z).y
		if h.position.y > g + 0.1:
			h.position.y = g + 0.02


## The Log Boom: not a bridge of chains but what its name says, a boom of whole logs chained end to
## end across the Wold Water at the level of the water, the rafters walking it from bank to bank;
## its ends chained to posts sunk in either bank, the made-up rafts lying lashed behind it upstream
## waiting their turn to be let go, and on the bank the boom-keeper's brazier and stool and the pole
## he lets them go with.
static func log_boom(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	# across the water by its narrowest line through the middle
	var best := INF
	var across := k.grain()
	var lo := 0.0
	var hi := 0.0
	for i in 18:
		var u := Vector2(sin(PI * float(i) / 18.0), cos(PI * float(i) / 18.0))
		var a := 0.0
		while a > -40.0 and k.is_water(u.x * (a - 1.0), u.y * (a - 1.0)):
			a -= 1.0
		var b := 0.0
		while b < 40.0 and k.is_water(u.x * (b + 1.0), u.y * (b + 1.0)):
			b += 1.0
		if not k.is_water(0.0, 0.0):
			continue
		if b - a < best:
			best = b - a
			across = u
			lo = a
			hi = b
	var along := Vector2(-across.y, across.x)
	var wl := k.water_y(0.0, 0.0)
	if is_nan(wl):
		wl = k.on_ground(0.0, 0.0).y + 0.6
	var p0 := across * (lo - 2.0)
	var p1 := across * (hi + 2.0)
	var span := p0.distance_to(p1)
	var n := maxi(int(ceil(span / 3.4)), 2)
	var logs := m.begin()
	var iron := m.begin()
	var yaw := PoiKit.yaw_of(across)
	for i in n:
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n)
		var a3 := p0.lerp(p1, t0) + along * k.rng.randf_range(-0.12, 0.12)
		var b3 := p0.lerp(p1, t1) + along * k.rng.randf_range(-0.12, 0.12)
		var ya := maxf(wl + 0.12, k.on_ground(a3.x, a3.y).y + 0.3)
		var yb := maxf(wl + 0.12, k.on_ground(b3.x, b3.y).y + 0.3)
		var ea := Vector3(a3.x, ya, a3.y) + Vector3(across.x, 0.0, across.y) * 0.25
		var eb := Vector3(b3.x, yb, b3.y) - Vector3(across.x, 0.0, across.y) * 0.25
		m.limb(logs, ea, eb, 0.3)
		var mid := (ea + eb) * 0.5
		k.collider(Vector3(0.62, 0.5, ea.distance_to(eb) + 0.3), Transform3D(Basis(Vector3.UP, yaw), mid - Vector3(0.0, 0.05, 0.0)), "wood")
		if i > 0:
			# the chain across the joint, two links and a staple
			var j := Vector3(a3.x, ya + 0.28, a3.y)
			m.limb(iron, j - Vector3(across.x, 0.0, across.y) * 0.4, j + Vector3(across.x, 0.0, across.y) * 0.4, 0.035)
	# the posts at either end, sunk in the bank, chained to the boom
	var posts := m.begin()
	for e in [p0 - across * 1.2, p1 + across * 1.2]:
		var ep: Vector2 = e
		var top := m.post(posts, ep, 1.6, 0.3)
		var toward := (Vector2.ZERO - ep).normalized()
		var end_log := ep + toward * 1.4
		m.limb(iron, top - Vector3(0.0, 0.3, 0.0), Vector3(end_log.x, maxf(wl + 0.4, k.on_ground(end_log.x, end_log.y).y + 0.55), end_log.y), 0.035)
	await k.step()
	m.commit(logs, PoiKit.painted(3, {"base": "#5e4f3c", "accent": "#3f3528"}, 0.85, 0.8), "BoomLogs", true)
	m.commit(posts, k.surface("timber", 0.8), "BoomPosts", true)
	m.commit(iron, PoiKit.plain(Color(0.24, 0.22, 0.2), 0.55, 0.7), "BoomChains")
	if k.far:
		return
	# the rafts waiting behind the boom: whichever way the water runs, upstream is the side the logs
	# pile on; here both sides are the Mere's slack water, so the side away from the road
	var up := along
	if not k.roads.is_empty() and k.road_distance(along * 6.0) < k.road_distance(-along * 6.0):
		up = -along
	var rafts := m.begin()
	var lash := m.begin()
	for r in 2:
		var rc := across * ((lo + hi) * 0.5 + (float(r) - 0.5) * 4.2) + up * 2.6
		if not k.is_water(rc.x, rc.y):
			continue
		for i in 6:
			var off := across * ((float(i) - 2.5) * 0.5)
			var a3 := rc + off - up * 1.8
			var b3 := rc + off + up * 1.8
			m.limb(rafts, Vector3(a3.x, wl + 0.08, a3.y), Vector3(b3.x, wl + 0.08, b3.y), 0.22)
		for s in [-1.0, 1.0]:
			var lc := rc + up * 1.2 * float(s)
			m.block(lash, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(up)), Vector3(lc.x, wl + 0.18, lc.y)), Vector3(3.2, 0.06, 0.08))
	await k.step()
	m.commit(rafts, PoiKit.painted(3, {"base": "#6a5a44", "accent": "#4a3e2f"}, 0.8, 0.8), "WaitingRafts")
	m.commit(lash, PoiKit.plain(Color(0.45, 0.39, 0.29), 0.95), "RaftLashings")
	# the keeper's place on the near bank: brazier, stool, his pole
	var bank := p0 - across * 3.2 + along * 2.0
	if not k.roads.is_empty() and k.road_distance(bank) < 3.5:
		bank = p0 - across * 3.2 - along * 2.0
	await k.step()
	k.place(k.prop("brazier"), k.on_ground(bank.x, bank.y), 0.0, 1.0, true)
	k.light(k.on_ground(bank.x, bank.y, 1.1), Color(1.0, 0.62, 0.3), 2.0, 9.0)
	var st_at := bank - along * 1.4
	await k.step()
	k.place(k.prop("stool"), k.on_ground(st_at.x, st_at.y), PoiKit.yaw_of(across), 1.0, true)
	var pole := m.begin()
	var pf := bank + along * 1.2
	m.limb(pole, k.on_ground(pf.x, pf.y, 0.0), k.on_ground(pf.x, pf.y, 0.0) + Vector3(across.x * 0.6, 3.6, across.y * 0.6), 0.04)
	m.commit(pole, k.surface("timber", 0.7), "BoomPole")
	k.marker("the_toll_post", k.on_ground(st_at.x - across.x * 0.8, st_at.y - across.y * 0.8), true)
	k.marker("the_far_approach", k.on_ground(p1.x + across.x * 5.0, p1.y + across.y * 5.0))


# --- the Tallyman's Folly -------------------------------------------------------------------------------

## Guildmaster Pellow's summer house as the masons left it the day building became a paid service:
## not a ruin but a house never finished, its dressed walls standing to uneven courses with their
## ends toothed for the next course that never came; a scaffold of lashed poles still up one wall; the
## doorway finished, lintel and all, and on the lintel the masons' names cut where the bill should have
## gone; ashlar stacked ready, the banker with its half-dressed block, the mortar box gone to stone, a
## pair of sheer-legs with a block still in the sling; and a hatch to the cellars the cutpurses use.
static func tallymans_folly(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var front := _toward_road(k, 60.0)
	if front == Vector2.ZERO:
		front = k.downhill() if k.downhill() != Vector2.ZERO else k.grain()
	front = front.normalized()
	var side := Vector2(-front.y, front.x)
	var yaw := PoiKit.yaw_of(front)
	# its front to the road, and back off it far enough that no corner stands in it
	var c := Vector2.ZERO
	for t in [0.0, 4.0, 8.0, 12.0, 16.0]:
		var q := -front * float(t)
		var clear := true
		for cn in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
			var cv: Vector2 = cn
			var corner: Vector2 = q + Vector2(-front.y, front.x) * 6.5 * cv.x + front * 5.0 * cv.y
			if not k.roads.is_empty() and k.road_distance(corner) < 4.0:
				clear = false
		c = q
		if clear:
			break
	var hw := 6.0
	var hd := 4.5
	var f := _ground_low(k, c, yaw, Vector2(hw * 2.0, hd * 2.0)) - 0.15
	var ashlar := m.begin()
	var p00 := c - side * hw + front * hd
	var p10 := c + side * hw + front * hd
	var p11 := c + side * hw - front * hd
	var p01 := c - side * hw - front * hd
	# the front: the door finished, the walls either side at different courses
	var door_at := hw - 1.6
	_wall_run(k, m, ashlar, p00, p10, f, f + 2.6, 0.6, [[door_at, 1.3, 0.0, 2.3], [2.2, 1.0, 0.9, 2.1]])
	_wall_run(k, m, ashlar, p10 - side * 0.0, p11, f, f + 3.4, 0.6, [[3.0, 1.0, 0.9, 2.2]])
	_wall_run(k, m, ashlar, p11, p01, f, f + 1.4, 0.6)
	_wall_run(k, m, ashlar, p01, p00, f, f + 4.2, 0.6, [[4.5, 1.0, 1.0, 2.3]])
	# the toothing: every other course stopped short at the open ends, waiting for the next
	for i in 4:
		var y := f + 1.4 + float(i) * 0.42 + 0.21
		var at := p11 - side * (0.9 if i % 2 == 0 else 0.45)
		m.block(ashlar, Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y, at.y)), Vector3(0.6, 0.4, 0.6))
	# the doorway's dressed lintel, a step proud, with the names on it
	var dp := p00 + side * door_at
	var lin := Transform3D(Basis(Vector3.UP, yaw), Vector3(dp.x, f + 2.55, dp.y) + Vector3(front.x, 0.0, front.y) * 0.1)
	m.block(ashlar, lin, Vector3(2.2, 0.55, 0.75))
	# stacked ashlar waiting, the banker, the mortar box
	var yard := c + front * (hd + 4.0) - side * 3.5
	if not k.roads.is_empty() and k.road_distance(yard) < 4.0:
		yard = c - front * (hd + 3.5) - side * 3.0
	for r in 2:
		for i in 3:
			var at := yard + side * (float(i) * 0.95) + front * (float(r) * 0.0)
			var xf := _slab(k, m, ashlar, at, yaw, Vector3(0.85, 0.5, 0.6), 0.04)
			if r == 1:
				m.block(ashlar, Transform3D(xf.basis, xf.origin + Vector3(0.0, 0.52, 0.0)), Vector3(0.85, 0.5, 0.6))
	k.collider(Vector3(2.8, 1.1, 0.7), Transform3D(Basis(Vector3.UP, yaw), k.on_ground(yard.x + side.x * 0.95, yard.y + side.y * 0.95) + Vector3(0.0, 0.55, 0.0)), "stone")
	var banker := yard + side * 4.2
	var bxf := _slab(k, m, ashlar, banker, yaw, Vector3(1.4, 0.75, 0.8), 0.05)
	k.collider(Vector3(1.4, 0.75, 0.8), bxf, "stone")
	m.block(ashlar, Transform3D(Basis(Vector3.UP, yaw + 0.2), bxf.origin + Vector3(0.0, 0.62, 0.0)), Vector3(0.7, 0.45, 0.5))
	await k.step()
	m.commit(ashlar, PoiKit.painted(2, {"base": "#c7c1b1", "accent": "#a9a393", "grout": "#6f6a5e", "unit": 0.42}, 0.55, 0.6), "UnfinishedHouse", true)
	# the masons' names on the lintel
	var names := m.begin()
	var lf := lin.origin + Vector3(front.x, 0.0, front.y) * 0.38
	for row in 2:
		var x := -0.85
		while x < 0.8:
			var w := k.rng.randf_range(0.18, 0.4)
			m.block(names, Transform3D(lin.basis, lf + lin.basis * Vector3(x + w * 0.5, 0.1 - float(row) * 0.2, 0.0)), Vector3(w, 0.06, 0.012))
			x += w + 0.12
	m.commit(names, PoiKit.plain(Color(0.22, 0.21, 0.19), 0.9), "sign_MasonsNames")
	if k.far:
		return
	# the scaffold up the high gable wall, lashed poles and putlogs, planks left on its lift
	var timber := m.begin()
	var sc0 := p01 - side * 1.2
	for i in 3:
		var at := sc0 + front * (1.0 + float(i) * 3.4)
		var top := m.post(timber, at, 5.2, 0.12)
		var into := Vector3(side.x, 0.0, side.y) * 1.3
		m.limb(timber, top - Vector3(0.0, 2.0, 0.0), top - Vector3(0.0, 2.0, 0.0) + into, 0.05)
	var lift_y := k.on_ground(sc0.x, sc0.y).y + 3.2
	var l0 := sc0 + front * 1.0 + side * 0.65
	var l1 := sc0 + front * 7.8 + side * 0.65
	m.block(timber, Transform3D(Basis(Vector3.UP, yaw), Vector3((l0.x + l1.x) * 0.5, lift_y + 0.05, (l0.y + l1.y) * 0.5)), Vector3(1.0, 0.06, 6.8))
	for i in 2:
		var a := sc0 + front * (1.0 + float(i) * 6.8)
		var b := sc0 + front * (1.0 + float(i + 1) * 3.4)
		m.limb(timber, k.on_ground(a.x, a.y, 0.4), k.on_ground(b.x, b.y, 4.6), 0.05)
	# the sheer-legs over the yard with a block still in the sling
	var sl := yard + side * 1.0 - front * 1.6
	var apex := k.on_ground(sl.x, sl.y, 4.4)
	for s in [-1.0, 1.0]:
		var foot := sl + side * 1.6 * float(s) + front * 0.6
		m.limb(timber, k.on_ground(foot.x, foot.y, -0.1), apex, 0.09)
	var back := sl - front * 1.8
	m.limb(timber, k.on_ground(back.x, back.y, -0.1), apex, 0.08)
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "ScaffoldAndSheers")
	var sling := m.begin()
	var block_y := k.on_ground(apex.x, apex.z).y + 0.2
	m.limb(sling, apex, Vector3(apex.x, block_y + 0.2, apex.z), 0.02)
	m.block(sling, Transform3D(Basis(Vector3.UP, yaw), Vector3(apex.x, block_y, apex.z)), Vector3(0.7, 0.4, 0.5))
	m.commit(sling, PoiKit.painted(2, {"base": "#c7c1b1", "accent": "#a9a393", "grout": "#6f6a5e", "unit": 0.42}, 0.55, 0.6), "SlungBlock")
	# the cellar hatch inside the walls, its boards prised up, steps going down into the dark
	var hatch := c - front * 1.5 + side * 2.0
	var hy := k.on_ground(hatch.x, hatch.y).y
	var dark := m.begin()
	m.block(dark, Transform3D(Basis(Vector3.UP, yaw), Vector3(hatch.x, hy + 0.03, hatch.y)), Vector3(1.4, 0.04, 1.8))
	m.commit(dark, PoiKit.plain(SHAFT_DARK, 1.0), "CellarHatch")
	var boards := m.begin()
	for i in 3:
		var at := hatch + side * (1.3 + float(i) * 0.3)
		m.block(boards, Transform3D(Basis(Vector3.UP, yaw + k.rng.randf_range(-0.2, 0.2)), k.on_ground(at.x, at.y, 0.03)), Vector3(0.28, 0.05, 1.8))
	m.commit(boards, k.surface("planks", 0.85), "HatchBoards")
	k.marker("the_cellar_hatch", k.on_ground(hatch.x + front.x * 1.5, hatch.y + front.y * 1.5))
	k.marker("the_lintel", k.on_ground(dp.x + front.x * 1.6, dp.y + front.y * 1.6))
	# the mortar box gone hard, and a mason's mallet left on the banker
	var box_at := banker - front * 1.6
	await k.step()
	k.place(k.prop("crate"), k.on_ground(box_at.x, box_at.y), yaw, 1.0, true)
	var hammer := k.prop("hammer")
	if hammer != "":
		await k.step()
		var hp := banker + front * 1.0 + side * 0.6
		k.place(hammer, k.on_ground(hp.x, hp.y), k.rng.randf() * TAU, 1.0, false)


# --- the Smoke Coppice -----------------------------------------------------------------------------------

## The coppicers' camp as a camp is built, and round it the coppice itself: oak stools older than the
## Charter, each a low gnarled boss as wide as a cart-wheel with a fan of straight young poles out of
## it, some cut this winter back to the boss and sprouting again; the cut poles stacked in lengths for
## the smokehouses, the cleaving-brake with a pole half split in it, bundles of brash tied for the clamp.
static func smoke_coppice(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().build(d)
	var k := d.kit
	var m := d.masonry
	var fire := _marker_at(d, "the_fire", Vector2.ZERO)
	var bark := m.begin()
	var poles := m.begin()
	var stools: Array[Vector2] = []
	var tries := 0
	while stools.size() < 9 and tries < 60:
		tries += 1
		var a := k.rng.randf_range(0.0, TAU)
		var p := fire + Vector2(sin(a), cos(a)) * k.rng.randf_range(9.0, 17.0)
		if not k.roads.is_empty() and k.road_distance(p) < 4.0:
			continue
		var ok := true
		for q in stools:
			if q.distance_to(p) < 3.6:
				ok = false
		if not ok:
			continue
		stools.append(p)
	for i in stools.size():
		var p: Vector2 = stools[i]
		var g := k.on_ground(p.x, p.y)
		var r := k.rng.randf_range(0.55, 0.85)
		m.ellipsoid(bark, g + Vector3(0.0, 0.12, 0.0), Vector3(r, 0.32, r * 0.9), Basis(Vector3.UP, k.rng.randf() * TAU))
		k.collider(Vector3(r * 1.6, 0.5, r * 1.6), Transform3D(Basis.IDENTITY, g + Vector3(0.0, 0.25, 0.0)), "wood")
		var cut := i % 3 == 0
		var n := 7 + k.rng.randi() % 4
		for j in n:
			var a := TAU * float(j) / float(n) + k.rng.randf_range(-0.2, 0.2)
			var base := g + Vector3(sin(a) * r * 0.6, 0.3, cos(a) * r * 0.6)
			var lean := Vector3(sin(a), 0.0, cos(a)) * k.rng.randf_range(0.12, 0.3)
			var h := k.rng.randf_range(0.6, 1.1) if cut else k.rng.randf_range(2.4, 3.8)
			m.limb(poles, base, base + (Vector3.UP + lean).normalized() * h, 0.04 if cut else 0.055)
	await k.step()
	m.commit(bark, PoiKit.painted(3, {"base": "#4f4335", "accent": "#352c22"}, 0.8, 0.8), "CoppiceStools")
	m.commit(poles, PoiKit.painted(3, {"base": "#6b6152", "accent": "#4d4539"}, 0.7, 0.7), "CoppicePoles", true)
	if k.far:
		return
	# the leaf on the standing poles: a few young oaks' worth of crown over the fan, the coppice's own
	var oak := k.tree("oak_sapling")
	if oak != "":
		var crowns: Array = []
		for i in stools.size():
			if i % 3 == 0:
				continue
			var p: Vector2 = stools[i]
			crowns.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf() * TAU, k.rng.randf_range(0.9, 1.2)))
		await k.step()
		k.scatter(oak, crowns, false)
	# the cut poles in their stack, the brake, the brash bundles
	var stack_at := _clear_spot(k, fire + k.grain() * 5.5, k.grain(), 3.0)
	var stack := m.begin()
	var along := k.grain()
	var yaw := PoiKit.yaw_of(along)
	var sg := k.on_ground(stack_at.x, stack_at.y).y
	for s in [-1.0, 1.0]:
		var bp := stack_at + along * 1.4 * float(s)
		var post_xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(bp.x, sg + 0.5, bp.y))
		m.block(stack, post_xf, Vector3(0.12, 1.0, 0.12))
	for row in 4:
		for i in 6 - row:
			var off := Vector2(-along.y, along.x) * ((float(i) - float(5 - row) * 0.5) * 0.13)
			var c := stack_at + off
			m.rod(stack, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(c.x, sg + 0.07 + float(row) * 0.12, c.y)), 0.06, 3.6)
	k.collider(Vector3(0.9, 0.55, 3.6), Transform3D(Basis(Vector3.UP, yaw), Vector3(stack_at.x, sg + 0.27, stack_at.y)), "wood")
	var brake := _clear_spot(k, fire - along * 4.5 + Vector2(-along.y, along.x) * 3.0, along, 3.0)
	var bg := k.on_ground(brake.x, brake.y)
	# Hob Tench at his brake
	_spot(k, "the_cleaving_brake", _clear_spot(k, brake - along * 1.3, along, 2.0), along)
	m.limb(stack, bg, bg + Vector3(0.4, 1.1, 0.0), 0.06)
	m.limb(stack, bg + Vector3(0.6, 0.0, 0.0), bg + Vector3(0.2, 1.1, 0.0), 0.06)
	m.limb(stack, bg + Vector3(-1.2, 0.05, 0.3), bg + Vector3(1.6, 1.0, 0.0), 0.05)
	await k.step()
	m.commit(stack, PoiKit.painted(3, {"base": "#7a6c58", "accent": "#5a4f40"}, 0.7, 0.7), "PoleStack")
	var brash := m.begin()
	for i in 4:
		var p := _clear_spot(k, fire + Vector2(-along.y, along.x) * (5.0 + float(i) * 0.9) - along * 2.0, along, 3.0, false)
		var g2 := k.on_ground(p.x, p.y)
		for j in 6:
			var a := k.rng.randf_range(-0.3, 0.3)
			var dir := Vector3(along.x, 0.0, along.y).rotated(Vector3.UP, a)
			m.limb(brash, g2 + Vector3(0.0, 0.15 + float(j % 3) * 0.06, 0.0) - dir * 0.8, g2 + Vector3(0.0, 0.15 + float(j % 3) * 0.06, 0.0) + dir * 0.8, 0.025)
	await k.step()
	m.commit(brash, PoiKit.painted(3, {"base": "#5d5240", "accent": "#463d30"}, 0.8, 0.8), "BrashBundles")


## A four-sided tapering shaft from `base` (local, its foot's middle) up `h`, `w0` across at its foot and
## `w1` at its head, turned by `b`: a needle's stalk or its pyramidion, with a flat top. Into `st`
## (a SurfaceTool begun for triangles). Each face is laid both ways round, so whichever winding the
## renderer takes for the front, the outside shows (the commit makes the normals from the winding).
static func _frustum(st: SurfaceTool, base: Vector3, b: Basis, w0: float, w1: float, h: float) -> void:
	var lo: Array[Vector3] = []
	var hi: Array[Vector3] = []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		lo.append(base + b * Vector3(c.x * w0 * 0.5, 0.0, c.y * w0 * 0.5))
		hi.append(base + b * Vector3(c.x * w1 * 0.5, h, c.y * w1 * 0.5))
	var tris: Array = []
	for i in 4:
		var j := (i + 1) % 4
		tris.append([lo[i], hi[i], hi[j]])
		tris.append([lo[i], hi[j], lo[j]])
	tris.append([hi[0], hi[1], hi[2]])
	tris.append([hi[0], hi[2], hi[3]])
	for t in tris:
		for v in t:
			st.add_vertex(v)
		for v in [t[2], t[1], t[0]]:
			st.add_vertex(v)


## The way from the middle toward the nearest road within `reach` (local xz unit), or ZERO.
static func _toward_road(k: PoiKit, reach: float) -> Vector2:
	if k.roads.is_empty():
		return Vector2.ZERO
	var best := INF
	var dir := Vector2.ZERO
	for i in 36:
		var u := Vector2(sin(TAU * float(i) / 36.0), cos(TAU * float(i) / 36.0))
		var dd := k.road_distance(u * 6.0)
		if dd < best:
			best = dd
			dir = u
	return dir if k.road_distance(Vector2.ZERO) <= reach else Vector2.ZERO


## A chest, crate or locker that opens: the region's prop for the look and a WorldContainer for the
## loot, its id the place's own so what was taken stays taken (hearthvale.gd's way).
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


# --- Holmwatch ---------------------------------------------------------------------------------------

## The Lake-Reeves' castle as the site builder raises a ruined castle (its curtain, drum towers, gate,
## keep and garrison), and over it on the lake side the Reeves' lamp-tower: a tall round tower outside
## the curtain's corner nearest Gull Holm, its head an iron cage round a brass fire-bowl where the
## reeve's light burned before the Lamp at Gullhithe, and at its foot a door to the castle side; the
## tallest thing on the east shore, seen from Merrowhithe and the holm.
static func holmwatch(d: PoiDressing) -> void:
	await _sites().build(d)
	var k := d.kit
	var m := d.masonry
	var site: Dictionary = ContentDB.get_or_empty(d.poi_id).get("site", {})
	var radius := float(site.get("radius", 20.0))
	var holm := (Vector2(1100.0, -980.0) - Vector2(k.origin.x, k.origin.z)).normalized()
	var to_water := k.water_direction(80.0)
	var dir := (holm + to_water).normalized() if to_water != Vector2.ZERO else holm
	var at := dir * (radius * 1.06 + 5.8)
	var g := _ground_low(k, at, 0.0, Vector2(6.4, 6.4)) - 0.2
	var r := 3.1
	var h := 18.5
	var stone := m.begin()
	var door_yaw := PoiKit.yaw_of(-dir)
	m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(at.x, g, at.y)), r, h, 0.06, door_yaw, true, 0.6)
	# a corbelled course under its head, and the head itself a little wider
	m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(at.x, g + h * 0.94 - 0.4, at.y)), r + 0.35, 0.6, 0.0, NAN, false, 0.6)
	await k.step()
	m.commit(stone, _sites().stone_look(k, g), "LampTower", true)
	# the cage at its head: eight iron bars flaring from a ring, two hoops, the brass bowl in it
	var iron := m.begin()
	var top := Vector3(at.x, g + h * 0.94 + 0.2, at.y)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var foot := top + Vector3(sin(a), 0.0, cos(a)) * 1.1
		var head := top + Vector3(sin(a), 0.0, cos(a)) * 1.5 + Vector3(0.0, 2.2, 0.0)
		m.limb(iron, foot, head, 0.05)
	for hoop in [0.9, 2.1]:
		for i in 12:
			var a0 := TAU * float(i) / 12.0
			var a1 := TAU * float(i + 1) / 12.0
			var rr: float = 1.1 + 0.4 * float(hoop) / 2.2
			m.limb(iron, top + Vector3(sin(a0) * rr, hoop, cos(a0) * rr), top + Vector3(sin(a1) * rr, hoop, cos(a1) * rr), 0.035)
	await k.step()
	m.commit(iron, PoiKit.plain(Color(0.16, 0.15, 0.14), 0.6, 0.6), "LampCage", true)
	var bowl := m.begin()
	m.ellipsoid(bowl, top + Vector3(0.0, 0.55, 0.0), Vector3(0.85, 0.4, 0.85))
	m.commit(bowl, PoiKit.plain(BRASS, 0.4, 0.6), "ReevesBowl", true)
	if k.far:
		return
	# the walkway round its head, inside the corbel: where the Loud stand to Say at dusk
	k.collider(Vector3(r * 1.6, 0.3, r * 1.6), Transform3D(Basis.IDENTITY, top - Vector3(0.0, 0.25, 0.0)), "stone")
	k.marker("the_lamp_head", top + Vector3(0.0, 0.1, 0.0))
	# a trumpet's stand and a brass trumpet left leaning at the tower's door, facing the water
	var door := at - dir * (r + 0.9)
	var dg := k.on_ground(door.x, door.y)
	var brass := m.begin()
	m.limb(brass, dg + Vector3(0.0, 0.05, 0.0), dg + Vector3(dir.x * 0.4, 1.3, dir.y * 0.4), 0.05)
	m.limb(brass, dg + Vector3(dir.x * 0.4, 1.3, dir.y * 0.4), dg + Vector3(dir.x * 0.75, 1.55, dir.y * 0.75), 0.16)
	m.commit(brass, PoiKit.plain(BRASS, 0.35, 0.6), "TowerTrumpet")
	k.marker("the_lamp_tower_door", dg)
