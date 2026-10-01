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
const SPOIL := {"base": "#7b8170", "accent": "#5d6656", "grout": "#3b4135", "unit": 0.32}
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
	for i in n / 2:
		var a := TAU * float(i) / float(n / 2)
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
	for s in [-1.0, 1.0]:
		var head := crown + Vector3(face.x, 0.0, face.y) * 0.7 * float(s)
		var foot2 := Vector2(shaft.x, shaft.y) + side * 6.8 + face * 1.2 * float(s)
		m.limb(timber, head, k.on_ground(foot2.x, foot2.y, -0.3), 0.15)
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
	m.limb(timber, beam_top, beam_foot, 0.32)
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "Headframe", true)
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
		m.mound(Vector3(at.x, minf(lo, k.on_ground(at.x, at.y).y) - 0.35, at.y), r, float(h[2]), spoil, "Spoil", true, 1.3, 7, 22)
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
	m.commit(paint, PoiKit.plain(Color(0.86, 0.84, 0.78), 0.8), "BoardPaint")
	m.commit(hooks, PoiKit.plain(Color(0.25, 0.23, 0.2), 0.5, 0.6), "BoardHooks")
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
	var door_d := clampf(float(gully[1]), 12.0, d.pad_radius * 0.85)
	var out := -into
	var side := Vector2(-into.y, into.x)
	var yaw_out := PoiKit.yaw_of(out)
	var bo := Basis(Vector3.UP, yaw_out)
	var door := into * door_d
	var gd := k.on_ground(door.x, door.y).y
	var lime := PoiKit.painted(0, LIMEWASH, 0.8, 0.7)
	var dressed := m.begin()

	# the facade: a wall of dressed stone across the gully's head with the hill behind it, the door in it
	var fw := 8.4
	var fh := 4.6
	var ft := 1.3
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
	var segs := 6
	for i in segs:
		var w := lerpf(1.18, 0.74, (float(i) + 0.5) / float(segs))
		var h := shaft_h / float(segs)
		m.block(needle, Transform3D(bo, Vector3(nd.x, y + h * 0.5, nd.y)), Vector3(w, h + 0.01, w))
		y += h
	k.collider(Vector3(1.1, shaft_h, 1.1), Transform3D(bo, Vector3(nd.x, y - shaft_h * 0.5, nd.y)), "stone")
	var top_y := y
	await k.step()
	m.commit(needle, lime, "TallyNeedle", true)
	var cap := m.begin()
	for i in 5:
		var w := 0.78 * (1.0 - float(i) / 5.0)
		m.block(cap, Transform3D(bo, Vector3(nd.x, top_y + 0.13 + float(i) * 0.25, nd.y)), Vector3(w, 0.26, w))
	await k.step()
	m.commit(cap, PoiKit.plain(BRASS, 0.35, 0.85), "NeedleCap", true)
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
	m.commit(nums, PoiKit.plain(Color(0.2, 0.19, 0.17), 0.9), "MarkerNumbers")

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
	var water_y := g + 0.3
	var runnel := m.begin()
	for i in 9:
		var p := r0 + down * (float(i) * 1.6 + 0.8)
		var rg := k.on_ground(p.x, p.y).y
		for s in [-1.0, 1.0]:
			var q := p + side * float(s) * 0.55
			m.block(kerb, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(down)), k.on_ground(q.x, q.y, 0.05)), Vector3(0.3, 0.3, 1.55))
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
		var bt := Vector3(at.x, ty + 0.07, at.y) + Vector3(-dir.y, 0.0, dir.x) * 0.55
		m.block(beetles, Transform3D(Basis(Vector3.UP, yaw + 0.4), bt), Vector3(0.13, 0.11, 0.42))
		m.block(beetles, Transform3D(Basis(Vector3.UP, yaw + 0.4), bt + Basis(Vector3.UP, yaw + 0.4) * Vector3(0.0, -0.02, 0.36)), Vector3(0.05, 0.05, 0.32))
		stones.append(at)
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
	m.sheet(lip + Vector3(down.x, 0.0, down.y) * 0.18, PoiKit.yaw_of(down), 0.18, lip.y - water_y, PoiKit.falling_water(), "Spout", 0.15, false, 1, 3)
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
		var lc := pc - cop_side * (6.5 + float(row) * 3.2) - down * 1.5
		var ends: Array[Vector3] = []
		for s in [-1.0, 1.0]:
			var pp := lc + down * float(s) * 3.3
			ends.append(m.post(timber, pp, 2.0, 0.12))
		var a3: Vector3 = ends[0]
		var b3: Vector3 = ends[1]
		m.limb(timber, a3 - Vector3(0.0, 0.12, 0.0), b3 - Vector3(0.0, 0.12, 0.0), 0.012)
		for c in 3:
			var t := 0.2 + float(c) * 0.3
			var hang := a3.lerp(b3, t) - Vector3(0.0, 0.14, 0.0)
			var lowest := minf(k.on_ground(hang.x, hang.z).y + 0.35, hang.y - 0.5)
			var h := hang.y - lowest
			m.block(linen, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(down) + PI * 0.5), hang - Vector3(0.0, h * 0.5, 0.0)), Vector3(1.4, h, 0.025))
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "LinePosts")
	m.commit(linen, PoiKit.painted(0, {"base": "#e9e6dc", "accent": "#d6d2c5", "grout": "#b7b3a6", "unit": 0.2}, 0.3, 0.5), "Linen", true)
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
