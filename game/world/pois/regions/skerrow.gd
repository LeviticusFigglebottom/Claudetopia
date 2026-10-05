extends RefCounted
## Skerrow's own place builders (docs/WORLD_LIFE.md). A POI def with `"builder": "<name>"` is built
## by the static function of that name here, in place of its kind's builder. Only the Skerrow
## region's author edits this file, so six regions can build at once without meeting.
##
##   static func drovers_hall(d: PoiDressing) -> void:
##       await PoiDressing.kind_builders().LAND.farmstead(d)    # its kind's, then more
##       var k := d.kit                                          # PoiKit: on_ground, prop, masonry ...
##
## The kind stays the def's `kind` (what the tests, the map and the audit call it); a builder named
## here that is missing is said in the log and the place is built as its kind.
##
## Most of these build the kind first and then add what the place's people and story need: the
## spot a resident works at (an `NpcSpot` marker the schedule names), a thing to touch that says
## what the place is (a `PoiTouch` with a conversation in dialogues/places_skerrow.json), and the
## few props that make the sentence true. Three are places of their own: the Frozen Drove, the
## Sorting Ground and Pennant's Weather-House.

## Old snow, as the Windgate toll-house's drifts are drawn.
const SNOW := Color(0.82, 0.85, 0.9)
## Where the conversations a place's things put are (dialogues/places_skerrow.json).
const DIALOGUE := "core:dialogue/"


# --- shared hands -----------------------------------------------------------------------------------

## The place's kind, built by the kind's own builder.
static func _kind(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().build(d)


## The boxes of everything solid the dressing has stood up so far, in its own space (as
## `PoiDressing.arrival` reads them): ground laid to be walked on is not in the way.
static func _solids(d: PoiDressing) -> Array[AABB]:
	var out: Array[AABB] = []
	var inv := d.global_transform.affine_inverse() if d.is_inside_tree() else Transform3D.IDENTITY
	for cs_v in d.find_children("*", "CollisionShape3D", true, false):
		var cs := cs_v as CollisionShape3D
		if cs.shape == null or cs.disabled:
			continue
		if cs.shape is ConcavePolygonShape3D and str(cs.get_meta(PoiKit.SURFACE_META, "")) == "dirt":
			continue
		var mesh := cs.shape.get_debug_mesh()
		if mesh == null:
			continue
		var xf := (inv * cs.global_transform) if d.is_inside_tree() else d._local_of(cs)
		out.append(xf * mesh.get_aabb())
	return out


## Whether a body `r` across can stand at local `p`: dry, off the road, clear of what stands.
static func _clear(d: PoiDressing, p: Vector2, r: float, solids: Array[AABB]) -> bool:
	var k := d.kit
	if k.is_water(p.x, p.y) or k.road_distance(p) < PoiKit.ROAD_CLEAR_M + r:
		return false
	var g := k.on_ground(p.x, p.y)
	var body := AABB(g + Vector3(-r, 0.1, -r), Vector3(r * 2.0, 1.6, r * 2.0))
	for box in solids:
		if box.intersects(body):
			return false
	return true


## The nearest clear spot to bearing `dir` between `r0` and `r1` metres out, swinging either side of
## the bearing; the bearing's own point at `r0` when nothing is clear.
static func _open_spot(d: PoiDressing, dir: Vector2, r0: float, r1: float, size: float, solids: Array[AABB]) -> Vector2:
	var base := PoiKit.yaw_of(dir)
	var r := r0
	while r <= r1:
		for i in 17:
			var k_i := ((i + 1) >> 1) * (1 if i % 2 == 1 else -1)
			var a := base + TAU * float(k_i) / 24.0
			var p := Vector2(sin(a), cos(a)) * r
			if _clear(d, p, size, solids):
				return p
		r += 1.0
	return dir * r0


## Away from the road, or uphill, or along the grain: where a person working here would sit.
static func _away(d: PoiDressing) -> Vector2:
	var k := d.kit
	var road := k.road_direction(60.0)
	if road != Vector2.ZERO:
		var here := Vector2(k.origin.x, k.origin.z)
		var best := INF
		var toward := Vector2.ZERO
		for s in k.roads_near(60.0):
			var p := Geometry2D.get_closest_point_to_segment(here, s[0], s[1])
			if p.distance_to(here) < best and p.distance_to(here) > 0.5:
				best = p.distance_to(here)
				toward = (p - here).normalized()
		if toward != Vector2.ZERO:
			return -toward
	var up := k.uphill()
	return up if up != Vector2.ZERO else k.grain()


## A worked spot (group `npc_spot`) for a resident's schedule, at local xz `p`.
static func _spot(d: PoiDressing, spot_name: String, p: Vector2) -> void:
	d.kit.marker(spot_name, d.kit.on_ground(p.x, p.y), true)


## A resident's worked spot beside what the kind stood up, clear of it, toward `dir`.
static func _resident(d: PoiDressing, spot_name: String, dir: Vector2, r0 := 4.0, r1 := 12.0) -> Vector2:
	var p := _open_spot(d, dir, r0, r1, 0.5, _solids(d))
	_spot(d, spot_name, p)
	return p


## A prop of the region's (or a lender's) on the ground at local xz, turned to `yaw`.
static func _prop(d: PoiDressing, kind: String, p: Vector2, yaw: float, scale := 1.0, lift := 0.0) -> Node3D:
	var path := d.kit.prop(kind)
	if path == "":
		return null
	await d.kit.step()
	return d.kit.place(path, d.kit.on_ground(p.x, p.y, lift), yaw, scale, true)


## Yaw that turns a model whose length runs along +x (the forge's bones, its beasts) to lie along `dir`.
static func _yaw_x(dir: Vector2) -> float:
	return atan2(-dir.y, dir.x)


## A heather broom: a shaft and a bound head of heather, leaning at `lean` (radians off upright) toward
## `toward`, its head on the ground at `p`. Laid into `timber` and `heather`.
static func _broom(d: PoiDressing, timber: SurfaceTool, heather: SurfaceTool, p: Vector2, toward: Vector2, lean: float) -> void:
	var k := d.kit
	var foot := k.on_ground(p.x, p.y)
	var up := (Vector3.UP * cos(lean) + Vector3(toward.x, 0.0, toward.y) * sin(lean)).normalized()
	var basis := Basis.looking_at(up, Vector3(toward.x, 0.0, toward.y).cross(Vector3.UP).normalized() if toward != Vector2.ZERO else Vector3.FORWARD)
	d.masonry.block(heather, Transform3D(basis, foot + up * 0.28), Vector3(0.26, 0.2, 0.56))
	d.masonry.block(timber, Transform3D(basis, foot + up * 0.95), Vector3(0.04, 0.04, 1.3))


# --- people's places: the kind's own, and where somebody works in it ---------------------------------

## The Red Moor: the leaning stones, and apart from them the twelfth, new-quarried and unleaning, with
## Haska ko-Ghast's bench and chisels in its lee.
static func red_moor(d: PoiDressing) -> void:
	await _kind(d)
	var k := d.kit
	if k.far:
		return
	var solids := _solids(d)
	var away := _away(d)
	var at := _open_spot(d, away, 8.0, 14.0, 1.4, solids)
	var toward := -at.normalized()
	var side := Vector2(toward.y, -toward.x)
	var stone := k.rock("standing_stone", 0)
	if stone != "":
		await k.step()
		# upright where the others lean, and a hand shorter than the tallest of them
		k.place(stone, k.on_ground(at.x, at.y, -0.2), PoiKit.yaw_of(toward), 0.82, true)
	k.touchable("NewStone", k.on_ground(at.x + toward.x * 0.8, at.y + toward.y * 0.8, 1.1), "Read the new stone",
			DIALOGUE + "red_moor_new_stone", "", false)
	# the chips round its foot, white against the red heather
	var scree := k.rock("scree")
	if scree != "":
		var chips: Array = []
		for i in 5:
			var p := at + toward * k.rng.randf_range(0.9, 1.8) + side * k.rng.randf_range(-1.2, 1.2)
			chips.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.05), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.18, 0.3)))
		await k.step()
		k.scatter(scree, chips, false)
	var bench := at + toward * 3.0 + side * 1.6
	await _prop(d, "bench", bench, PoiKit.yaw_of(side))
	await _prop(d, "hammer", bench + toward * 0.1, k.rng.randf_range(0.0, TAU), 1.0, 0.5)
	_spot(d, "the_cutters_bench", bench + toward * 1.1)


## The Breathing Stones: the ring and its shakehole, and the hole itself to hold a hand over, with a
## Sayer's ribbon on a stick at its lip, pointing down.
static func breathing_stones(d: PoiDressing) -> void:
	await _kind(d)
	var k := d.kit
	if k.far:
		return
	var lip := Vector2(1.1, 0.4)
	k.touchable("TheHole", k.on_ground(0.0, 0.0, 0.3), "Hold a hand over the hole", DIALOGUE + "breathing_stones_hole", "", false)
	var timber := d.masonry.begin()
	var top := d.masonry.post(timber, lip, 0.9, 0.035, Vector3(0.0, 0.0, -0.25))
	await k.step()
	d.masonry.commit(timber, k.surface("timber", 0.7), "RibbonStick")
	var cloth := d.masonry.begin()
	d.masonry.block(cloth, Transform3D(Basis(Vector3.UP, 0.3), top + Vector3(-0.12, -0.18, 0.0)), Vector3(0.03, 0.34, 0.012))
	await k.step()
	d.masonry.commit(cloth, PoiKit.plain(Color(0.62, 0.16, 0.14), 0.8), "Ribbon")


## The Winter Cairns: the fellside of stones, and one cairn of them near the path with the morning's
## pebble on it, to be looked at.
static func winter_cairns(d: PoiDressing) -> void:
	await _kind(d)
	var k := d.kit
	if k.far:
		return
	var solids := _solids(d)
	var scree := k.rock("scree")
	var at := _open_spot(d, _away(d), 6.0, 12.0, 1.0, solids)
	if scree != "":
		# a knee-high cairn: small stones heaped, and a round wet pebble on its top
		var heap: Array = []
		for i in 9:
			var a := k.rng.randf_range(0.0, TAU)
			var rr := k.rng.randf_range(0.0, 0.45)
			var tier := floorf(float(i) / 3.0)
			var up := 0.12 * tier
			heap.append(PoiKit.transform_at(k.on_ground(at.x + sin(a) * rr, at.y + cos(a) * rr, up - 0.04), k.rng.randf_range(0.0, TAU),
					k.rng.randf_range(0.16, 0.24) * (1.0 - 0.2 * tier)))
		await k.step()
		k.scatter(scree, heap, true)
	# the heap is solid underfoot and under the pebble: one box for it
	k.collider(Vector3(0.9, 0.5, 0.9), Transform3D(Basis(), k.on_ground(at.x, at.y, 0.22)), "stone")
	var pebble := d.masonry.begin()
	d.masonry.ellipsoid(pebble, k.on_ground(at.x, at.y, 0.5), Vector3(0.07, 0.05, 0.08))
	await k.step()
	d.masonry.commit(pebble, PoiKit.plain(Color(0.36, 0.38, 0.4), 0.25), "Pebble")
	k.touchable("MorningPebble", k.on_ground(at.x, at.y, 0.45), "Look at the cairn", DIALOGUE + "winter_cairns_pebbles", "", false)


## Skarl Shieling: the hut and its fold, and the singing stone above them where Tamsk ko-Skarl sings the
## herd down at dusk.
static func skarl_shieling(d: PoiDressing) -> void:
	await _kind(d)
	var k := d.kit
	if k.far:
		return
	var solids := _solids(d)
	var up := k.uphill()
	var at := _open_spot(d, up if up != Vector2.ZERO else _away(d), 9.0, 15.0, 1.3, solids)
	var rock := k.rock("boulder", 1)
	if rock != "":
		await k.step()
		k.place(rock, k.on_ground(at.x, at.y, -0.35), k.rng.randf_range(0.0, TAU), 0.8, true)
	var down := -at.normalized()
	_spot(d, "the_singing_stone", at + down * 1.6)


## Skarl Spout: the fall out of the scar, and the keeper's lip beside it, with her net and her rope.
static func skarl_spout(d: PoiDressing) -> void:
	await _kind(d)
	var k := d.kit
	if k.far:
		return
	var at := _resident(d, "the_spout_lip", _away(d), 6.0, 16.0)
	var toward := -at.normalized()
	var side := Vector2(toward.y, -toward.x)
	await _prop(d, "rope_coil", at + side * 1.2, k.rng.randf_range(0.0, TAU))
	await _prop(d, "basket", at - side * 1.1 + toward * 0.3, k.rng.randf_range(0.0, TAU))


## The Skerry Watch: the look-out, a seat on its seaward side, and a heather broom left leaning in
## its door.
static func skerry_watch(d: PoiDressing) -> void:
	await _kind(d)
	var k := d.kit
	if k.far:
		return
	var solids := _solids(d)
	var look := k.water_direction(160.0)
	if look == Vector2.ZERO:
		look = k.downhill()
	if look == Vector2.ZERO:
		look = k.grain()
	var at := _open_spot(d, look, 4.0, 10.0, 0.6, solids)
	var toward := -at.normalized()
	_spot(d, "the_watch_seat", at)
	var timber := d.masonry.begin()
	var heather := d.masonry.begin()
	var lean_at := at + toward * 1.4 + Vector2(toward.y, -toward.x) * 0.8
	_broom(d, timber, heather, lean_at, toward, 0.32)
	await k.step()
	d.masonry.commit(timber, k.surface("timber", 0.8), "BroomShaft")
	d.masonry.commit(heather, PoiKit.painted(5, {"base": "#6a4a5e", "accent": "#4c3a3c", "grout": "#2e2424", "unit": 0.08}, 0.7), "BroomHead")


## The Drovers' Bothy: the camp, and Ottar ko-Skarl's place at its fire.
static func drovers_bothy(d: PoiDressing) -> void:
	await _kind(d)
	if d.kit.far:
		return
	var fire := d.find_child("the_fire", true, false) as Node3D
	var from := Vector2(fire.position.x, fire.position.z) if fire != null else Vector2.ZERO
	var p := _open_spot(d, _away(d), 2.2, 6.0, 0.45, _solids(d))
	_spot(d, "the_bothy_fire", from + (p - from).normalized() * 2.2 if fire != null else p)


## The Tinkers' Camp: the camp, and Pell Kettleby's mending frame at its edge, hung with chains.
static func tinkers_camp(d: PoiDressing) -> void:
	await _kind(d)
	var k := d.kit
	if k.far:
		return
	var at := _open_spot(d, _away(d), 6.0, 12.0, 1.4, _solids(d))
	var toward := -at.normalized()
	var timber := d.masonry.begin()
	var hang := d.masonry.frame(timber, at, PoiKit.yaw_of(Vector2(toward.y, -toward.x)), 2.2, 1.9, 0.12)
	await k.step()
	d.masonry.commit(timber, k.surface("timber", 0.8), "MendingFrame")
	var iron := d.masonry.begin()
	var along := Vector3(toward.y, 0.0, -toward.x)
	for i in 4:
		var x := -0.75 + 0.5 * float(i)
		var drop := k.rng.randf_range(0.5, 0.9)
		d.masonry.block(iron, Transform3D(Basis(), hang + along * x + Vector3(0.0, -drop * 0.5, 0.0)), Vector3(0.05, drop, 0.05))
	await k.step()
	d.masonry.commit(iron, PoiKit.plain(Color(0.28, 0.27, 0.26), 0.5, 0.7), "Chains")
	_spot(d, "the_mending_frame", at + toward * 1.2)


## The Tappers' Camp: the camp, and Aggi ko-Rudd's pitch-pot on its own fire at the edge.
static func tappers_camp(d: PoiDressing) -> void:
	await _kind(d)
	var k := d.kit
	if k.far:
		return
	var at := _open_spot(d, _away(d), 6.0, 12.0, 1.0, _solids(d))
	await _prop(d, "cooking_pot", at, k.rng.randf_range(0.0, TAU))
	_spot(d, "the_pitch_pot", at - at.normalized() * 1.2)


## The Bone Ford: the vertebrae in the beck, and Orsk ko-Rudd's counting stone on the bank.
static func bone_ford(d: PoiDressing) -> void:
	await _kind_tidied(d)
	if d.kit.far:
		return
	_resident(d, "the_count_stone", _away(d), 6.0, 18.0)


## The Rib Cathedral: the ribs, and the oath-keeper's place in the nave.
static func rib_cathedral(d: PoiDressing) -> void:
	await _kind_tidied(d)
	if d.kit.far:
		return
	_resident(d, "the_oath_ribs", d.kit.grain(), 3.0, 14.0)


## The Wall-Keepers' Ring: the drystone ring, a line of white stones across it, and a fire either side,
## one Skarl and one Woodfolk, each with its keeper.
static func wall_keepers_ring(d: PoiDressing) -> void:
	await _kind(d)
	var k := d.kit
	if k.far:
		return
	var axis := k.grain()
	var across := Vector2(axis.y, -axis.x)
	var stones := k.rock("boulder", 1)
	if stones != "":
		var row: Array = []
		for i in 9:
			var p := axis * (-6.0 + 1.5 * float(i)) + across * k.rng.randf_range(-0.1, 0.1)
			row.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.05), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.2, 0.26)))
		await k.step()
		var white := k.scatter(stones, row, false)
		if white != null:
			white.material_override = PoiKit.plain(Color(0.9, 0.88, 0.82), 0.8)
	var solids := _solids(d)
	var skarl := _open_spot(d, across, 4.0, 9.0, 0.8, solids)
	var wood := _open_spot(d, -across, 4.0, 9.0, 0.8, solids)
	var fire := k.prop("campfire")
	for p in [skarl, wood]:
		if fire != "":
			await k.step()
			k.place(fire, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 0.9, false)
	_spot(d, "the_skarl_fire", skarl + axis * 1.3)
	_spot(d, "the_woodfolk_fire", wood + axis * 1.3)


## Pennant's Weather-House: a turf bothy by the tarn inside a drystone yard, and round it everything a
## Sayer brought up from Tollmere to measure the moor: a wind-vane, a rain-gauge, a glass in a box, a
## louvred screen on legs, a ribbon over a shakehole in the turf, a bell on a frame that rings when the
## wind turns, a line of pennants between two poles to show the wind from a mile off, the Circle's
## banner, and her table out of doors with the day's readings weighted under a stone.
static func pennants_weather_house(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().WAYSIDE.hut(d)
	var k := d.kit
	var m := d.masonry
	var away := _away(d)
	var toward := -away
	var side := Vector2(toward.y, -toward.x)
	# the yard: a drystone wall round the bothy and the instruments, its gap toward the tarn's path
	var wall := k.prop("drystone_wall")
	if wall != "":
		var runs: Array = []
		var half := Vector2(8.0, 6.5)
		var corners := [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
		for c_i in 4:
			var a: Vector2 = corners[c_i]
			var b: Vector2 = corners[(c_i + 1) % 4]
			var len_m := a.distance_to(b)
			var count := int(round(len_m / 2.5))
			for j in count:
				if c_i == 2 and (j == int(count * 0.5) or j == int(count * 0.5) - 1):
					continue    # the gate-gap in the front run
				var t := (float(j) + 0.5) / float(count)
				var q2 := a.lerp(b, t)
				var q := side * q2.x + toward * q2.y
				var dir := side * (b - a).normalized().x + toward * (b - a).normalized().y
				runs.append(PoiKit.transform_at(k.on_ground(q.x, q.y, -0.05), _yaw_x(dir), 1.0))
		await k.step()
		k.scatter(wall, runs, true, true)
	if k.far:
		return
	var yard := side * 3.6 - toward * 1.0
	var timber := m.begin()
	var brass := m.begin()
	# the vane: a tall post, a cross-arm, a tail-fin
	var vane_at := yard + side * 1.8
	var vane_top := m.post(timber, vane_at, 3.4, 0.1)
	m.block(brass, Transform3D(Basis(Vector3.UP, k.rng.randf_range(0.0, TAU)), vane_top + Vector3(0.0, 0.1, 0.0)), Vector3(0.05, 0.05, 1.1))
	m.block(brass, Transform3D(Basis(Vector3.UP, k.rng.randf_range(0.0, TAU)), vane_top + Vector3(0.0, 0.18, 0.4)), Vector3(0.02, 0.26, 0.34))
	# the rain-gauge: a short post and a funnelled can
	var gauge_at := yard - side * 1.2 + toward * 2.0
	var gauge_top := m.post(timber, gauge_at, 1.0, 0.09)
	# the can in a mesh of its own, so it is judged standing on its own post
	var can := m.begin()
	m.block(can, Transform3D(Basis(), gauge_top + Vector3(0.0, 0.14, 0.0)), Vector3(0.18, 0.28, 0.18))
	m.commit(can, PoiKit.plain(PoiKit.BRONZE, 0.45, 0.8), "GaugeCan")
	# the glass in its box on a stand
	var glass_at := yard + toward * 1.4
	var glass_top := m.post(timber, glass_at, 1.25, 0.1)
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(toward)), glass_top + Vector3(0.0, 0.2, 0.0)), Vector3(0.32, 0.42, 0.16))
	# the screen: a louvred box on four legs, for the air's warmth out of the sun
	var screen_at := yard - side * 1.4 - toward * 2.0
	var louvres := m.begin()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			# its legs in the same piece as the box, so the box stands on them
			m.post(louvres, screen_at + side * (0.3 * float(sx)) + toward * (0.25 * float(sz)), 1.2, 0.06)
	var box_at := k.on_ground(screen_at.x, screen_at.y, 1.35)
	for i in 5:
		m.block(louvres, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(toward)) * Basis(Vector3.RIGHT, 0.5), box_at + Vector3(0.0, -0.2 + 0.1 * float(i), 0.0)),
				Vector3(0.78, 0.03, 0.62))
	m.block(louvres, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(toward)), box_at + Vector3(0.0, 0.3, 0.0)), Vector3(0.86, 0.06, 0.7))
	# its floor, laid across the legs' tops: what the box stands on
	var floor_xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(toward)), k.on_ground(screen_at.x, screen_at.y, 1.12))
	m.block(louvres, floor_xf, Vector3(0.84, 0.05, 0.68))
	k.collider(Vector3(0.84, 0.05, 0.68), floor_xf, "wood")
	await k.step()
	m.commit(louvres, PoiKit.painted(3, {"base": "#b3ab98", "accent": "#8d8573"}, 0.8), "Screen")
	# the bell on its frame, where the wind turns it
	var bell_at := yard - toward * 1.6 + side * 2.6
	var hang := m.frame(timber, bell_at, PoiKit.yaw_of(side), 0.9, 1.7, 0.08)
	await k.step()
	m.commit(brass, PoiKit.plain(PoiKit.BRONZE, 0.45, 0.8), "Brass")
	var bell := k.prop("bell_small")
	if bell != "":
		await k.step()
		k.place(bell, hang - Vector3(0.0, 0.3, 0.0), 0.0, 1.0, false)
	# the pennant line: two poles and a line between them strung with pennants, all one piece
	var pennants := m.begin()
	var pole_a := side * -6.5 + toward * 4.5
	var pole_b := side * 6.5 + toward * 4.5
	var top_a := m.post(timber, pole_a, 5.6, 0.12)
	var top_b := m.post(timber, pole_b, 5.6, 0.12)
	var cloth := m.begin()
	var line_n := 14
	for i in line_n:
		var t0 := float(i) / float(line_n)
		var t1 := float(i + 1) / float(line_n)
		var sag0 := 0.7 * sin(PI * t0)
		var sag1 := 0.7 * sin(PI * t1)
		var p0 := top_a.lerp(top_b, t0) - Vector3(0.0, 0.15 + sag0, 0.0)
		var p1 := top_a.lerp(top_b, t1) - Vector3(0.0, 0.15 + sag1, 0.0)
		m.block(pennants, Transform3D(Basis.looking_at((p1 - p0).normalized(), Vector3.UP), (p0 + p1) * 0.5), Vector3(0.02, 0.02, p0.distance_to(p1)))
		if i > 0:
			m.block(cloth, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(toward)), p0 - Vector3(0.0, 0.22, 0.0)), Vector3(0.34, 0.42, 0.015))
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "Instruments")
	await k.step()
	m.commit(pennants, PoiKit.plain(Color(0.2, 0.18, 0.16), 0.9), "PennantLine")
	await k.step()
	m.commit(cloth, PoiKit.painted(5, {"base": "#6c7a8a", "accent": "#b9ad8e", "grout": "#3f4650", "unit": 0.25}, 0.7), "Pennants")
	# the ribbon over a shakehole in the turf, leaning in
	var hole := yard - toward * 2.0 - side * 6.1
	var dark := m.begin()
	m.ellipsoid(dark, k.on_ground(hole.x, hole.y, -0.02), Vector3(0.5, 0.05, 0.42))
	await k.step()
	m.commit(dark, PoiKit.plain(Color(0.08, 0.08, 0.07), 0.95), "Shakehole")
	var stick := m.begin()
	var tip := m.post(stick, hole + side * 0.55, 0.7, 0.03, Vector3(0.0, 0.0, 0.3))
	m.block(stick, Transform3D(Basis(), tip + Vector3(-0.1, -0.15, 0.0)), Vector3(0.025, 0.3, 0.01))
	await k.step()
	m.commit(stick, PoiKit.plain(Color(0.62, 0.16, 0.14), 0.8), "Ribbon")
	# her table out of doors: the day's readings under a stone, and the stool she reads them on
	var desk := yard - side * 4.2 + toward * 0.6
	await _prop(d, "table_trestle", desk, PoiKit.yaw_of(side))
	await _prop(d, "paper_stack", desk, PoiKit.yaw_of(side) + 0.3, 1.0, 0.83)
	await _prop(d, "stool", desk + toward * 0.9, k.rng.randf_range(0.0, TAU))
	await _prop(d, "peat_stack", side * -3.4 - toward * 4.4, PoiKit.yaw_of(side))
	var banner := k.prop("banner")
	if banner != "":
		var pole := side * 4.6 + toward * 5.6
		await k.step()
		k.place(banner, k.on_ground(pole.x, pole.y), PoiKit.yaw_of(toward), 1.0, true)
	k.touchable("Gauges", glass_top + Vector3(0.0, 0.2, 0.0), "Read the gauges", DIALOGUE + "weather_house_gauges", "", false)
	_spot(d, "the_instruments", desk + toward * 1.4)


## Skerrfall Quarry: Brindle's quarry cut back into the fell in three benches of weathered limestone,
## the hill's own turf closing over their lips; the floor below them the fell's ground, with spoil
## heaped to one side and the scree run down from it, part-dressed blocks waiting in a row, sheerlegs
## over the floor with a block on its rope, a track of laid flags going down toward Brindlecrag, and in
## the foot of the first bench the long white bone the last face was cut round, half out of the rock
## like a lintel over nothing, with Hodd ko-Brindle's bench facing it. Nothing here is a slab stood on
## the slope: every piece stands on its own ground or is cut back into the hill.
static func skerrfall_quarry(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	# the face goes into the hill: uphill, else against the fall, else the grain
	var into := k.uphill()
	if into == Vector2.ZERO:
		into = -k.downhill()
	if into == Vector2.ZERO:
		into = k.grain()
	var side := Vector2(into.y, -into.x)
	var rock := PoiKit.painted(0, {"base": "#8c877d", "accent": "#747068", "grout": "#4d4a44", "unit": 0.6}, 0.9, 0.8)
	var fresh := PoiKit.painted(0, {"base": "#a09a8e", "accent": "#878276", "grout": "#5c5850", "unit": 0.5}, 0.75, 0.8)
	var turf := PoiKit.painted(5, {"base": "#565a3a", "accent": "#43462c", "grout": "#2c2e1d", "unit": 0.3}, 0.7)
	var floor_c := -into * 3.0
	var floor_y := k.on_ground(floor_c.x, floor_c.y).y
	# the benches: an arc of cut rock stepping back into the hill, each bench no prouder than the hill a
	# pace behind it, so the face is the hill cut back and not a wall stood in front of it
	var arc_r := 9.0
	var cut := m.begin()
	var lips := m.begin()
	var n := 9
	var lower: Array[float] = []
	lower.resize(n)
	lower.fill(floor_y)
	var first_foot := Vector2.ZERO
	for b in 3:
		var r := arc_r + float(b) * 2.8
		for i in n:
			var a0 := -1.1 + 2.2 * float(i) / float(n)
			var a1 := -1.1 + 2.2 * float(i + 1) / float(n)
			var dir := into.rotated((a0 + a1) * 0.5)
			var p := floor_c + dir * r
			var behind := p + dir * 2.0
			var top := minf(floor_y + 3.0 * float(b + 1) + k.rng.randf_range(-0.35, 0.35), k.on_ground(behind.x, behind.y).y + 0.4)
			if b == 0:
				top = maxf(top, floor_y + 1.8)
			if top < lower[i] + 0.8:
				continue
			lower[i] = top
			var h := maxf(top - floor_y + 0.6, 1.0)
			var chord := 2.0 * r * sin((a1 - a0) * 0.5) + 0.35
			var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(dir)), Vector3(p.x, floor_y + h * 0.5 - 0.6, p.y))
			m.block(cut, xf, Vector3(chord, h, 3.0))
			m.block(lips, Transform3D(xf.basis, Vector3(p.x, top + 0.04, p.y)), Vector3(chord + 0.15, 0.12, 3.1))
			if b == 0:
				k.collider(Vector3(chord, h, 3.0), xf, "stone")
				if i == 4:
					first_foot = floor_c + dir * (r - 1.5)
	await k.step()
	m.commit(cut, rock, "Face", true)
	await k.step()
	m.commit(lips, turf, "FaceTurf")
	if k.far:
		return
	# the bone in the foot of the first bench, the face cut round it
	var bone := k.rock("bone_finger", 1)
	if bone != "" and first_foot != Vector2.ZERO:
		var s := 0.62
		var at := first_foot - side * (3.3 * s)
		await k.step()
		k.place(bone, k.on_ground(at.x, at.y, -0.25), _yaw_x(side), s, true)
	k.marker("the_new_face", k.on_ground(first_foot.x - into.x * 3.5, first_foot.y - into.y * 3.5))
	# the part-dressed blocks waiting in a row, some stacked, each on its own ground
	var blocks := m.begin()
	for i in 6:
		var p := floor_c + side * (-6.5 + 2.1 * float(i)) - into * k.rng.randf_range(2.5, 4.0)
		var size := Vector3(k.rng.randf_range(0.9, 1.4), k.rng.randf_range(0.55, 0.85), k.rng.randf_range(0.8, 1.2))
		var g := k.on_ground(p.x, p.y)
		var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side) + k.rng.randf_range(-0.2, 0.2)), g + Vector3(0.0, size.y * 0.5 - 0.08, 0.0))
		m.block(blocks, xf, size)
		k.collider(size, xf, "stone")
		if i % 3 == 1:
			var up := Transform3D(xf.basis.rotated(Vector3.UP, 0.2), xf.origin + Vector3(0.0, size.y * 0.95, 0.0))
			m.block(blocks, up, size * Vector3(0.8, 0.85, 0.8))
			k.collider(size * Vector3(0.8, 0.85, 0.8), up, "stone")
	await k.step()
	m.commit(blocks, fresh, "Blocks")
	# the spoil: the face's rock broken small and gone grey with earth, heaped to one side, and its
	# scree run down from it
	var spoil_at := floor_c + side * 8.5 - into * 1.0
	await k.step()
	m.mound(k.on_ground(spoil_at.x, spoil_at.y, -0.2), 3.2, 1.3, PoiKit.painted(5, {"base": "#6f6b5f", "accent": "#5a574d", "grout": "#3a3832", "unit": 0.3}, 0.9, 0.9),
			"Spoil", true, 1.3, 6, 18, false, 0.16)
	var scree := k.rock("scree")
	if scree != "":
		var heap: Array = []
		for i in 10:
			var a := k.rng.randf_range(0.0, TAU)
			var rr := sqrt(k.rng.randf()) * 4.4
			var p := spoil_at + Vector2(sin(a), cos(a)) * rr
			heap.append(PoiKit.transform_at(k.on_ground(p.x, p.y, 1.3 * pow(maxf(1.0 - rr / 3.2, 0.0), 1.3) - 0.15), k.rng.randf_range(0.0, TAU),
					k.rng.randf_range(0.4, 0.75)))
		await k.step()
		k.scatter(scree, heap, true)
	# the sheerlegs: three poles to a head over the floor, the rope, and a block hanging on it a hand
	# off the ground
	var timber := m.begin()
	var legs_at := floor_c - side * 4.0 + into * 1.5
	var head := k.on_ground(legs_at.x, legs_at.y, 5.2)
	for a in [0.3, 2.4, 4.5]:
		var foot := legs_at + Vector2(sin(a), cos(a)) * 1.9
		await k.step()
		m.limb(timber, k.on_ground(foot.x, foot.y, -0.1), head, 0.1)
	var hang_at := k.on_ground(legs_at.x, legs_at.y, 0.0)
	await k.step()
	m.limb(timber, head, hang_at + Vector3(0.0, 1.05, 0.0), 0.02)
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "Sheerlegs", true)
	var lifted := m.begin()
	m.block(lifted, Transform3D(Basis(Vector3.UP, 0.4), hang_at + Vector3(0.0, 0.62, 0.0)), Vector3(1.0, 0.7, 0.8))
	# a stone rest under it, so it stands on something while it waits to be swung
	m.block(lifted, Transform3D(Basis(Vector3.UP, 0.1), hang_at + Vector3(0.0, 0.12, 0.0)), Vector3(0.7, 0.26, 0.6))
	await k.step()
	m.commit(lifted, fresh, "Lifted")
	k.collider(Vector3(1.0, 0.95, 0.8), Transform3D(Basis(Vector3.UP, 0.4), hang_at + Vector3(0.0, 0.47, 0.0)), "stone")
	# the track down: flags laid on the ground, off toward the fall of the hill
	var flags := m.begin()
	var down := -into
	for i in 9:
		var p := floor_c + down * (5.0 + 1.6 * float(i)) + side * (sin(float(i) * 0.7) * 0.8)
		m.block(flags, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(down) + k.rng.randf_range(-0.3, 0.3)), k.on_ground(p.x, p.y, -0.02)),
				Vector3(k.rng.randf_range(0.8, 1.2), 0.1, k.rng.randf_range(0.7, 1.0)))
	await k.step()
	m.commit(flags, rock, "Track")
	# the tools, and Hodd's bench facing the bone
	for kind in ["wheelbarrow", "pitchfork"]:
		var p := floor_c + side * k.rng.randf_range(-3.0, 3.0) - into * k.rng.randf_range(4.5, 6.0)
		await _prop(d, kind, p, k.rng.randf_range(0.0, TAU))
	var seat := first_foot - into * 5.0 + side * 2.4
	await _prop(d, "bench", seat, PoiKit.yaw_of(side))
	await _prop(d, "whetstone", seat + side * 0.9 - into * 0.3, k.rng.randf_range(0.0, TAU))
	_spot(d, "the_quarry_bench", seat - into * 0.9)
	await PoiDressing.kind_builders().LAND._grass(d, "heather", floor_c - into * 6.0, 9.0, 24)


## The Reckoner's Hut: a turf bothy on the Edge, and beside its door a frame hung with tally-sticks in
## rows, each a price, and one empty peg.
static func reckoners_hut(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().WAYSIDE.hut(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var at := _open_spot(d, _away(d).rotated(-1.0), 4.5, 9.0, 1.6, _solids(d))
	var toward := -at.normalized()
	var along := Vector2(toward.y, -toward.x)
	var yaw := PoiKit.yaw_of(along)
	var timber := m.begin()
	var mid := m.frame(timber, at, yaw, 2.6, 1.9, 0.12)
	var basis := Basis(Vector3.UP, yaw)
	for row in 3:
		var rail := mid + Vector3(0.0, -0.45 - 0.45 * float(row), 0.0)
		m.block(timber, Transform3D(basis, rail), Vector3(2.5, 0.05, 0.05))
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "TallyFrame")
	var sticks := m.begin()
	for row in 3:
		for i in 13:
			if row == 0 and i == 12:
				continue    # the empty peg: this year's, waiting
			var x := -1.15 + 0.19 * float(i)
			var stick_len := k.rng.randf_range(0.28, 0.4)
			var p := mid + basis * Vector3(x, -0.45 - 0.45 * float(row) - stick_len * 0.5, 0.04)
			m.block(sticks, Transform3D(basis * Basis(Vector3.BACK, k.rng.randf_range(-0.08, 0.08)), p), Vector3(0.03, stick_len, 0.03))
	await k.step()
	m.commit(sticks, PoiKit.painted(3, {"base": "#b9ab8c", "accent": "#6e604a"}, 0.7), "TallySticks")
	k.touchable("TallyWall", mid + Vector3(0.0, -0.8, 0.0) + Vector3(toward.x, 0.0, toward.y) * 0.3, "Look at the tally-sticks",
			DIALOGUE + "reckoners_tally_wall", "", false)
	_spot(d, "the_tally_wall", at + toward * 1.1)


## The Broom-Wife's Bield: a shieling's hut and fold, and at the door a stack of heather brooms leant
## against the wall, bound and waiting.
static func broom_wifes_bield(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().LAND.shieling(d)
	var k := d.kit
	if k.far:
		return
	var door := d.find_child("the_hut", true, false) as Node3D
	var from := Vector2(door.position.x, door.position.z) if door != null else Vector2.ZERO
	var at := _open_spot(d, from.normalized() if from != Vector2.ZERO else _away(d), maxf(from.length(), 3.0), maxf(from.length(), 3.0) + 6.0, 0.8, _solids(d))
	var toward := (from - at).normalized() if from.distance_to(at) > 0.5 else -at.normalized()
	var across := Vector2(toward.y, -toward.x)
	var timber := d.masonry.begin()
	var heather := d.masonry.begin()
	for i in 6:
		_broom(d, timber, heather, at + across * (-0.75 + 0.3 * float(i)) - toward * 0.25, toward, 0.2 + k.rng.randf_range(-0.05, 0.05))
	await k.step()
	d.masonry.commit(timber, k.surface("timber", 0.8), "BroomShafts")
	d.masonry.commit(heather, PoiKit.painted(5, {"base": "#6a4a5e", "accent": "#4c3a3c", "grout": "#2e2424", "unit": 0.08}, 0.7), "BroomHeads")
	k.collider(Vector3(1.9, 1.3, 0.6), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(toward)), k.on_ground(at.x, at.y, 0.65)), "wood")
	_spot(d, "the_broom_stack", at - toward * 1.0)


## The Frozen Drove: a Skarl drove standing in the snow on the Wall, every beast facing north with its
## head up, the drifts between them, stragglers further up the slope, and the drover's crook upright
## in the middle with no drover.
static func frozen_drove(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var snow := PoiKit.painted(5, {"base": "#cfd4da", "accent": "#b7bdc5", "grout": "#99a0aa", "unit": 0.6}, 0.5, 0.5)
	var north := Vector2(0.0, -1.0)
	var east := Vector2(1.0, 0.0)
	# the drifts the wind piled among them, long and low across the slope
	for i in 6:
		var p := north * k.rng.randf_range(-10.0, 10.0) + east * k.rng.randf_range(-13.0, 13.0)
		await k.step()
		m.mound(k.on_ground(p.x, p.y, -0.3), k.rng.randf_range(3.4, 5.6), k.rng.randf_range(0.45, 0.85), snow, "Drift", true,
				2.4, 5, 14, i < 3, 0.2)
	if k.far:
		return
	var sheep := Livestock.paths_of("sheep")
	if not sheep.is_empty():
		var rows: Dictionary = {}
		var n := 0
		# the drove: loose ranks across the slope, all facing north, heads up
		for rank in 7:
			for file in 6:
				if k.rng.randf() < 0.18:
					continue
				var p := north * (-9.0 + 2.6 * float(rank) + k.rng.randf_range(-0.6, 0.6)) \
						+ east * (-7.5 + 3.0 * float(file) + k.rng.randf_range(-0.8, 0.8) + 0.9 * float(rank % 2))
				if p.length() < 2.0:
					continue    # the crook's place
				var path: String = sheep[n % sheep.size()]
				n += 1
				var xf := PoiKit.transform_at(k.on_ground(p.x, p.y, -0.04), _yaw_x(north.rotated(k.rng.randf_range(-0.18, 0.18))),
						k.rng.randf_range(1.1, 1.25))
				(rows.get_or_add(path, []) as Array).append(xf)
		# stragglers further up toward the Wall, as if they had gone on ahead
		for i in 4:
			var p := north * k.rng.randf_range(15.0, 20.0) + east * k.rng.randf_range(-9.0, 9.0)
			var path: String = sheep[i % sheep.size()]
			(rows.get_or_add(path, []) as Array).append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.04),
					_yaw_x(north.rotated(k.rng.randf_range(-0.25, 0.25))), 1.0))
		for path: String in rows:
			await k.step()
			var herd := k.scatter(path, rows[path], true)
			if herd != null:
				# rimed white: the frost has had them fifty-five winters
				herd.material_override = PoiKit.painted(5, {"base": "#8e8d88", "accent": "#b9bcbf", "grout": "#5f5d58", "unit": 0.12}, 0.6, 0.7)
	# the drover's crook, upright, its handle to the north
	var timber := m.begin()
	var top := m.post(timber, Vector2.ZERO, 1.7, 0.045)
	m.block(timber, Transform3D(Basis(), top + Vector3(0.0, 0.06, -0.09)), Vector3(0.045, 0.045, 0.22))
	m.block(timber, Transform3D(Basis(), top + Vector3(0.0, -0.04, -0.2)), Vector3(0.045, 0.2, 0.045))
	await k.step()
	m.commit(timber, k.surface("timber", 0.9), "Crook")
	k.touchable("Crook", top + Vector3(0.0, -0.4, 0.0), "Look at the drover's crook", DIALOGUE + "frozen_drove_crook", "", false)
	k.marker("the_drove", k.on_ground(0.0, 3.0))


## The Sorting Ground: a pavement of limestone clints on the moor, broken by grikes, and on it a giant
## laid out by kind, largest to smallest: a line of vertebrae stopping a bone short, ribs lying flat in
## a rank, the long bones in another, the skull's pieces at the head, and at the line's end a space
## swept clean.
static func sorting_ground(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var along := k.grain()
	var across := Vector2(along.y, -along.x)
	# the pavement: clints of every size, each canted a little and laid on its own ground, the grikes
	# between them wide and uneven, and thinning out to bare turf toward the edges
	var clint := m.begin()
	for i in 15:
		for j in 8:
			var c := along * (-22.0 + 3.1 * float(i) + k.rng.randf_range(-0.6, 0.6)) + across * (-12.0 + 3.2 * float(j) + k.rng.randf_range(-0.6, 0.6))
			var edge := maxf(absf(c.dot(along)) / 23.0, absf(c.dot(across)) / 12.5)
			if edge > 1.0 or k.rng.randf() < 0.1 + 0.55 * maxf(edge - 0.6, 0.0) / 0.4:
				continue
			var size := Vector3(k.rng.randf_range(1.6, 3.0), k.rng.randf_range(0.28, 0.5), k.rng.randf_range(1.8, 3.1))
			var g := k.on_ground(c.x, c.y)
			var tilt := Basis(Vector3.RIGHT, k.rng.randf_range(-0.04, 0.04)) * Basis(Vector3.BACK, k.rng.randf_range(-0.04, 0.04))
			var cxf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(along) + k.rng.randf_range(-0.3, 0.3)) * tilt,
					g + Vector3(0.0, size.y * 0.5 - 0.18, 0.0))
			m.block(clint, cxf, size)
			k.collider(size, cxf, "stone")
	await k.step()
	m.commit(clint, PoiKit.painted(0, {"base": "#9c978b", "accent": "#857f73", "grout": "#5d584f", "unit": 0.9}, 0.8, 0.8), "Pavement", true)
	if k.far:
		return
	var top := 0.2
	# the line of vertebrae, largest to smallest, a hand apart, and the space after the last
	var vert := k.rock("bone_vertebra", 0)
	var end := Vector2.ZERO
	if vert != "":
		var line: Array = []
		var x := -20.0
		for i in 16:
			var s := 0.9 - 0.033 * float(i)
			x += 1.4 * s
			var p := along * x + across * -7.0
			line.append(PoiKit.transform_at(k.on_ground(p.x, p.y, top), _yaw_x(across), s))
			x += 1.4 * s + 0.35
			end = along * (x + 1.0) + across * -7.0
		await k.step()
		k.scatter(vert, line, true)
	# the ribs lying flat in a rank, longest first
	var rib := k.rock("bone_rib", 0)
	if rib != "":
		var rank: Array = []
		for i in 6:
			var s := 0.78 - 0.055 * float(i)
			var p := along * (-17.0 + 6.8 * float(i)) + across * 1.2
			var xf := Transform3D(Basis(Vector3.UP, _yaw_x(across)) * Basis(Vector3.RIGHT, PI * 0.5) * Basis().scaled(Vector3.ONE * s),
					k.on_ground(p.x, p.y, top + 0.73 * s))
			rank.append(xf)
		await k.step()
		k.scatter(rib, rank, true)
	# the long bones in their rank, and the skull's pieces at the head of it all
	var long := k.rock("bone_finger", 0)
	if long != "":
		var bones: Array = []
		for i in 7:
			var s := 1.0 - 0.07 * float(i)
			var p := along * (-18.0 + 5.6 * float(i)) + across * 8.4 - across * (2.7 * s)
			bones.append(PoiKit.transform_at(k.on_ground(p.x, p.y, top), _yaw_x(across), s))
		await k.step()
		k.scatter(long, bones, true)
	var skull := k.rock("bone_skull_fragment", 0)
	if skull != "":
		var pieces: Array = []
		for i in 3:
			var p := along * (21.0 + k.rng.randf_range(-0.6, 0.6)) + across * (-6.0 + 6.0 * float(i))
			pieces.append(PoiKit.transform_at(k.on_ground(p.x, p.y, top - 0.1), k.rng.randf_range(0.0, TAU), 0.95 - 0.15 * float(i)))
		await k.step()
		k.scatter(skull, pieces, true)
	k.touchable("TheGap", k.on_ground(end.x, end.y, top + 0.3), "Look at the end of the line", DIALOGUE + "sorting_ground_gap", "", false)
	k.marker("the_line", k.on_ground(end.x - along.x * 3.0, end.y - along.y * 3.0, top))


## The Faceless Graves: a row of long graves on the fell, each with its headstone laid face-down at its
## head and sunk in the turf, and the last one turned face-up, its turf still pale.
static func faceless_graves(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var along := k.grain()
	var across := Vector2(along.y, -along.x)
	var turf := PoiKit.painted(5, {"base": "#5d6a3c", "accent": "#46522c", "grout": "#2f3a1d", "unit": 0.3}, 0.6)
	var stone := k.surface("stone", 0.8)
	var slabs := m.begin()
	var turned := Vector2.ZERO
	for i in 5:
		var c := along * (-4.8 + 2.4 * float(i))
		var head := c + across * 1.6
		await k.step()
		# the grave: a long low mound across the row, lying the way the fell falls
		m.mound(k.on_ground(c.x, c.y, -0.12), 1.0, 0.32, turf, "Grave", true, 2.2, 4, 12, i == 2, 0.08)
		if i < 4:
			# face-down: flat on the turf, a hand proud of it, its back to the sky
			var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(across)), k.on_ground(head.x, head.y, 0.05))
			m.block(slabs, xf, Vector3(0.75, 0.14, 1.1))
			k.collider(Vector3(0.75, 0.14, 1.1), xf, "stone")
		else:
			turned = head
	# the last stone, turned face-up and leant on its own foot, and the pale ground it came off
	var up := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(across)) * Basis(Vector3.RIGHT, -1.1), k.on_ground(turned.x, turned.y, 0.4))
	m.block(slabs, up, Vector3(0.75, 0.14, 1.1))
	k.collider(Vector3(0.75, 0.5, 0.9), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(across)), k.on_ground(turned.x, turned.y, 0.35)), "stone")
	await k.step()
	m.commit(slabs, stone, "Headstones", true)
	if k.far:
		return
	var scar := m.begin()
	var bare := turned + across * 1.0
	m.block(scar, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(across)), k.on_ground(bare.x, bare.y, -0.03)), Vector3(0.8, 0.08, 1.15))
	await k.step()
	m.commit(scar, PoiKit.painted(5, {"base": "#8a8466", "accent": "#6f6a52", "grout": "#4a4636", "unit": 0.2}, 0.8), "PaleTurf")
	k.touchable("TurnedStone", k.on_ground(turned.x, turned.y, 0.7), "Look at the turned headstone",
			DIALOGUE + "faceless_graves_turned", "", false)
	k.marker("the_graves", k.on_ground(-across.x * 2.5, -across.y * 2.5))


## The Unroping Post: a post and arm by the Oskelcrag road like any gibbet, socketed in stones, and hung
## not with a cage but with children's ropes cut short, each at the length its child was when they
## first walked the Edge alone; the oldest gone grey and thin, the newest still with its colour.
static func unroping_post(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var along := k.road_direction(60.0)
	if along == Vector2.ZERO:
		along = k.grain()
	var out := Vector2(along.y, -along.x)
	# stand it off the road, on the side away from it
	var at := _open_spot(d, _away(d), 2.5, 7.0, 1.2, _solids(d))
	var socket := k.rock("boulder", 1)
	if socket != "":
		var stones: Array = []
		for i in 3:
			var a := TAU * float(i) / 3.0 + 0.4
			var p := at + Vector2(sin(a), cos(a)) * 0.55
			stones.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.25), k.rng.randf_range(0.0, TAU), 0.42))
		await k.step()
		k.scatter(socket, stones, true)
	var timber := m.begin()
	var top := m.post(timber, at, 4.1, 0.26)
	var arm := Vector3(out.x, 0.0, out.y)
	m.block(timber, Transform3D(Basis.looking_at(arm, Vector3.UP), top + arm * 0.85 - Vector3(0.0, 0.2, 0.0)), Vector3(0.18, 0.18, 2.0))
	var brace_a := top - Vector3(0.0, 1.1, 0.0)
	var brace_b := top + arm * 0.9 - Vector3(0.0, 0.25, 0.0)
	m.block(timber, Transform3D(Basis.looking_at((brace_b - brace_a).normalized(), Vector3.UP), (brace_a + brace_b) * 0.5),
			Vector3(0.11, 0.11, brace_a.distance_to(brace_b)))
	await k.step()
	m.commit(timber, k.surface("timber", 0.95), "Post")
	# the ropes: tied along the arm and round the post, and the lashing at the post's foot they are
	# tied off to, all one cord, so none of it hangs from nothing
	var rope := m.begin()
	var foot := k.on_ground(at.x, at.y)
	for i in 5:
		m.block(rope, Transform3D(Basis(), foot + Vector3(0.0, 0.25 + 0.18 * float(i), 0.0)), Vector3(0.3, 0.05, 0.3))
	var tie_run := foot + Vector3(0.0, 1.0, 0.0)
	m.block(rope, Transform3D(Basis(), (tie_run + top) * 0.5 + arm * 0.14), Vector3(0.03, top.y - tie_run.y, 0.03))
	for i in 7:
		var t := 0.25 + 0.21 * float(i)
		var hang := top + arm * (1.8 * t) - Vector3(0.0, 0.2, 0.0)
		var drop := k.rng.randf_range(0.45, 1.05)
		var xf := Transform3D(Basis(Vector3.BACK, k.rng.randf_range(-0.06, 0.06)), hang - Vector3(0.0, 0.09 + drop * 0.5, 0.0))
		m.block(rope, xf, Vector3(0.035, drop, 0.035))
		# the knot where each is cut: a thicker end
		m.block(rope, Transform3D(Basis(), hang - Vector3(0.0, 0.09 + drop, 0.0)), Vector3(0.06, 0.07, 0.06))
		# and where it is tied on
		m.block(rope, Transform3D(Basis(), hang - Vector3(0.0, 0.1, 0.0)), Vector3(0.07, 0.08, 0.22))
	await k.step()
	m.commit(rope, PoiKit.plain(Color(0.55, 0.49, 0.38), 0.95), "Ropes")
	await PoiDressing.kind_builders().LAND._grass(d, "heather", at, 5.0, 16)
	k.marker("the_gibbet", k.on_ground(at.x - out.x * 1.2, at.y - out.y * 1.2), true)


## The Whelping Hole: a shakehole on the moor fallen in to the dark, not a mouth in a hillside: a black
## throat in a funnel of trodden turf, a rim of limestone blocks with the scree gone down between
## them, white fur caught everywhere, and round it what the wolves dragged up there, bones and a
## courier's satchel.
static func whelping_hole(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var trodden := PoiKit.painted(5, {"base": "#6b6452", "accent": "#524c3d", "grout": "#34302a", "unit": 0.25}, 0.8)
	# the funnel: a low dish of trodden earth, and the black throat in its bottom
	await k.step()
	m.mound(k.on_ground(0.0, 0.0, -0.3), 6.5, 0.28, trodden, "Funnel", true, 1.1, 5, 18, true, 0.12)
	var throat := m.begin()
	m.ellipsoid(throat, k.on_ground(0.0, 0.0, 0.0), Vector3(2.4, 0.12, 1.9))
	await k.step()
	m.commit(throat, PoiKit.plain(Color(0.02, 0.02, 0.025), 1.0), "Throat", true)
	# the rim: limestone blocks round the dish, a pace apart so the scree runs down between them
	var block := k.rock("boulder", 1)
	var rim: Array = []
	if block != "":
		for i in 7:
			var a := TAU * float(i) / 7.0 + k.rng.randf_range(-0.15, 0.15)
			var r := k.rng.randf_range(6.0, 7.2)
			var p := Vector2(sin(a), cos(a)) * r
			rim.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.35), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.55, 0.8),
					Vector3(k.rng.randf_range(-0.2, 0.2), 0.0, k.rng.randf_range(-0.2, 0.2))))
		await k.step()
		k.scatter(block, rim, true, true)
	var scree := k.rock("scree")
	if scree != "":
		var fall: Array = []
		for i in 7:
			var a := TAU * (float(i) + 0.5) / 7.0
			var p := Vector2(sin(a), cos(a)) * k.rng.randf_range(4.2, 5.2)
			fall.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.12), a, k.rng.randf_range(0.5, 0.7)))
		await k.step()
		k.scatter(scree, fall, true)
	if k.far:
		return
	# white fur on the rim and the turf, where they come and go
	var fur := m.begin()
	for i in 26:
		var a := k.rng.randf_range(0.0, TAU)
		var p := Vector2(sin(a), cos(a)) * k.rng.randf_range(2.8, 9.0)
		m.ellipsoid(fur, k.on_ground(p.x, p.y, 0.02), Vector3(0.12, 0.04, 0.09) * k.rng.randf_range(0.7, 1.4))
	await k.step()
	m.commit(fur, PoiKit.plain(Color(0.9, 0.9, 0.88), 0.95), "Fur")
	# what they dragged up: a giant's small bones gnawed white, a beast's, and further out a satchel
	var bone := k.rock("bone_finger", 0)
	if bone != "":
		var gnawed: Array = []
		for i in 5:
			var a := k.rng.randf_range(0.0, TAU)
			var p := Vector2(sin(a), cos(a)) * k.rng.randf_range(8.0, 15.0)
			gnawed.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.05), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.12, 0.2)))
		await k.step()
		k.scatter(bone, gnawed, false)
	var satchel := Vector2(sin(2.3), cos(2.3)) * 9.5
	await _prop(d, "sack", satchel, k.rng.randf_range(0.0, TAU), 0.8)
	k.marker("the_mouth", k.on_ground(0.0, 2.6))


# --- a thing to touch at a place that had none ----------------------------------------------------------

## The kind's own, and beside it one thing to put a hand on that says what the place is (a
## `PoiTouch` with its conversation): at a clear spot toward `dir`, `r0` to `r1` metres out.
static func _kind_and_touch(d: PoiDressing, touch_name: String, prompt: String, dialogue: String, dir: Vector2,
		r0: float, r1: float, lift := 0.8) -> Vector2:
	await _kind(d)
	if d.kit.far:
		return Vector2.ZERO
	var p := _open_spot(d, dir, r0, r1, 0.4, _solids(d))
	d.kit.touchable(touch_name, d.kit.on_ground(p.x, p.y, lift), prompt, DIALOGUE + dialogue, "", false)
	return p


## The Moot Beacon: the tower, and Varn ko-Skarl's place at its foot, looking north.
static func moot_beacon(d: PoiDressing) -> void:
	await _kind(d)
	if d.kit.far:
		return
	_resident(d, "the_beacon_foot", Vector2(0.0, -1.0), 4.0, 12.0)


## Rudd Pike Beacon: the tower, and the warm ash spilled at its foot.
static func rudd_pike_beacon(d: PoiDressing) -> void:
	var p: Vector2 = await _kind_and_touch(d, "Ash", "Put a hand in the ash", "rudd_pike_ash", Vector2(0.0, -1.0), 3.0, 9.0, 0.3)
	if d.kit.far:
		return
	var ash := d.masonry.begin()
	d.masonry.ellipsoid(ash, d.kit.on_ground(p.x, p.y, 0.0), Vector3(1.1, 0.12, 0.8))
	await d.kit.step()
	d.masonry.commit(ash, PoiKit.plain(Color(0.42, 0.41, 0.4), 0.95), "Ash")


## The Black Keep: the burned tower, and the foot of its relaid stair.
static func black_keep(d: PoiDressing) -> void:
	await _kind_and_touch(d, "Stair", "Look at the relaid stair", "black_keep_stair", Vector2(0.0, -1.0), 2.5, 8.0, 0.9)


## Kharrow Force: the fall, and the iron rope over its lip for the naming.
static func kharrow_force(d: PoiDressing) -> void:
	await _kind_and_touch(d, "IronRope", "Take hold of the iron rope", "kharrow_force_rope", d.kit.grain(), 4.0, 14.0, 0.9)


## The Snow Shelter: the shelter, and its bell on the pole by the door.
static func snow_shelter(d: PoiDressing) -> void:
	await _kind_and_touch(d, "ShelterBell", "Look at the shelter bell", "snow_shelter_bell", _away(d), 3.0, 9.0, 1.2)


## The Watch of the Gate: the toll-house, and its bell frozen mid-swing.
static func watch_of_the_gate(d: PoiDressing) -> void:
	await _kind_and_touch(d, "FrozenBell", "Look at the frozen bell", "watch_gate_bell", Vector2(0.0, -1.0), 3.0, 9.0, 1.2)
	_tidy(d)


# --- the two delves' mouths ------------------------------------------------------------------------------

## Where a cave's mouth is and which way it goes in, read off its `the_mouth` marker (the den a little way
## inside, as the cave builder puts it): [the mouth's lip, the way in], both local xz.
static func _mouth_of(d: PoiDressing) -> Array:
	var den := d.find_child("the_mouth", true, false) as Node3D
	if den == null:
		return []
	var at := Vector2(den.position.x, den.position.z)
	var into := at.normalized() if at.length() > 0.5 else d.kit.uphill()
	if into == Vector2.ZERO:
		into = d.kit.grain()
	return [at - into * 3.5, into]


## The bank a cave raises over its throat where the world raised no face, in `look` rather than the
## ground's: a hump of dark earth read as a raw loaf on the snow and the limestone.
static func _bank_look(d: PoiDressing, look: Material) -> void:
	var bank := d.find_child("Bank", true, false) as MeshInstance3D
	if bank != null:
		bank.material_override = look


## Orrdun: the delve's mouth in the Wall's face, the bank over its throat snowed on like the rest of the
## Wall, and a pair of a giant's ribs arched over the door, leaning together, as the Skarl framed it.
static func orrdun(d: PoiDressing) -> void:
	await _kind(d)
	var k := d.kit
	_bank_look(d, PoiKit.painted(5, {"base": "#c3c8cd", "accent": "#a4a9ae", "grout": "#7a7f84", "unit": 0.7}, 0.6, 0.7))
	var mouth := _mouth_of(d)
	var rib := k.rock("bone_rib", 2)
	if mouth.is_empty() or rib == "":
		return
	var lip: Vector2 = mouth[0]
	var into: Vector2 = mouth[1]
	var across := Vector2(-into.y, into.x)
	var yaw := PoiKit.yaw_of(into)
	var s := 0.75
	var at := lip - into * 1.4
	var ribs: Array = []
	for side in [-1.0, 1.0]:
		var foot := at + across * float(side) * (3.6 * s / 1.35 + 0.5)
		ribs.append(PoiKit.transform_at(k.on_ground(foot.x, foot.y, -0.3), yaw + (0.0 if side > 0.0 else PI), s,
				Vector3(0.0, 0.0, -0.3 * float(side))))
	await k.step()
	k.scatter(rib, ribs, true, true)


## The Brakh's Drink: the delve's mouth in the Skarl scar, its bank the scar's own limestone, and a
## giant's two knee-bones set either side of it like door-posts.
static func brakhs_drink(d: PoiDressing) -> void:
	await _kind(d)
	var k := d.kit
	_bank_look(d, PoiKit.painted(0, {"base": "#a39e93", "accent": "#8a857a", "grout": "#5c5850", "unit": 0.8}, 0.7, 0.8))
	var mouth := _mouth_of(d)
	var knee := k.rock("bone_vertebra", 1)
	if mouth.is_empty() or knee == "":
		return
	var lip: Vector2 = mouth[0]
	var into: Vector2 = mouth[1]
	var across := Vector2(-into.y, into.x)
	var posts: Array = []
	for side in [-1.0, 1.0]:
		var p := lip - into * 1.6 + across * float(side) * 3.4
		var g := k.on_ground(p.x, p.y, -0.4)
		posts.append(PoiKit.transform_at(g, PoiKit.yaw_of(into) + k.rng.randf_range(-0.2, 0.2), 0.42))
	await k.step()
	k.scatter(knee, posts, true, true)


# --- phase 2 (2026-10-01): the large places, and the dull ones built as their briefs say ------------

## Bone, as the giants' is drawn: old ivory going to grey, the grain long.
const BONE := {"base": "#d6cebb", "accent": "#b7ad97", "grout": "#857c69", "unit": 0.6}
## Iron gone black, and iron left out in Skerrow weather.
const IRON := Color(0.16, 0.15, 0.145)
const RUST := Color(0.36, 0.2, 0.12)
## The dark inside a door or a window, and a window with a fire behind it.
const DARK := Color(0.035, 0.032, 0.03)
const LIT := Color(1.0, 0.6, 0.28)


static func _sites() -> GDScript:
	return PoiDressing.kind_builders().SITES


static func _site_of(d: PoiDressing) -> Dictionary:
	return ContentDB.get_or_empty(d.poi_id).get("site", {})


## The unit bearing (local) a def's `site.<key>` gives, measured from +z toward +x; `otherwise` when
## the def gives none.
static func _bearing(site: Dictionary, key: String, otherwise: Vector2) -> Vector2:
	if not site.has(key):
		return otherwise
	var a := deg_to_rad(float(site[key]))
	return Vector2(sin(a), cos(a))


## The unit way (local) from the place's middle to the nearest point of a road within `reach`; ZERO
## when no road runs that near. (PoiKit.road_direction is the road's own run, not the way to it.)
static func _toward_road(k: PoiKit, reach: float) -> Vector2:
	var here := Vector2(k.origin.x, k.origin.z)
	var best := INF
	var toward := Vector2.ZERO
	for seg in k.roads_near(reach):
		var p := Geometry2D.get_closest_point_to_segment(here, seg[0], seg[1])
		var dd := p.distance_to(here)
		if dd < best and dd > 0.5:
			best = dd
			toward = (p - here).normalized()
	return toward


## The nearest road's run through the place: [the closest point on it (local xz), its unit direction];
## empty when no road comes within `reach`.
static func _road_at(k: PoiKit, reach: float) -> Array:
	var here := Vector2(k.origin.x, k.origin.z)
	var best := INF
	var out: Array = []
	for seg in k.roads_near(reach):
		var ab: Vector2 = seg[1] - seg[0]
		if ab.length() < 0.5:
			continue
		var p := Geometry2D.get_closest_point_to_segment(here, seg[0], seg[1])
		if p.distance_to(here) < best:
			best = p.distance_to(here)
			out = [p - here, ab.normalized()]
	return out


## A timber or a bone from `a` to `b` (local) into `st`, with a box to stand against.
static func _limb_solid(d: PoiDressing, st: SurfaceTool, a: Vector3, b: Vector3, r: float, surface := "wood") -> void:
	d.masonry.limb(st, a, b, r)
	var dir := b - a
	var length := dir.length()
	if length < 0.05 or d.kit.far:
		return
	var y := dir / length
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	d.kit.collider(Vector3(r * 1.8, length, r * 1.8), Transform3D(Basis(x, y, z), (a + b) * 0.5), surface)


## A trodden way on the ground through `pts` (local xz), `width` across, a hair over the turf.
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
			var w0 := 1.0 + 0.14 * sin(float(s) * 1.7 + float(i))
			var w1 := 1.0 + 0.14 * sin(float(s + 1) * 1.7 + float(i))
			var q := [k.on_ground(p0.x - across.x * w0, p0.y - across.y * w0, 0.03), k.on_ground(p0.x + across.x * w0, p0.y + across.y * w0, 0.03),
					k.on_ground(p1.x + across.x * w1, p1.y + across.y * w1, 0.03), k.on_ground(p1.x - across.x * w1, p1.y - across.y * w1, 0.03)]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.add_vertex(q[idx])


## A chain of great links hanging from `a` to `b` (local), sagging `sag` metres at its middle: flat
## links laid end to end, every other one turned a quarter about the chain, into `st`.
static func _chain(m: PoiMasonry, st: SurfaceTool, a: Vector3, b: Vector3, link := 0.34, sag := 0.0) -> void:
	var span := a.distance_to(b)
	var n := maxi(int(span / (link * 0.8)), 2)
	var prev := a
	for i in n:
		var t := float(i + 1) / float(n)
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var dir := (p - prev)
		if dir.length() < 0.01:
			continue
		var y := dir.normalized()
		var x := y.cross(Vector3.UP)
		if x.length() < 0.01:
			x = Vector3.RIGHT
		x = x.normalized()
		var z := x.cross(y).normalized()
		var basis := Basis(x, y, z) if i % 2 == 0 else Basis(z, y, -x)
		var c := (prev + p) * 0.5
		# a link: two side bars and the two ends, as an open ring reads at a few metres
		for s in [-1.0, 1.0]:
			m.block(st, Transform3D(basis, c + basis.x * (link * 0.2 * float(s))), Vector3(link * 0.1, link * 1.05, link * 0.1))
		for s in [-1.0, 1.0]:
			m.block(st, Transform3D(basis, c + basis.y * (link * 0.48 * float(s))), Vector3(link * 0.5, link * 0.1, link * 0.1))
		prev = p


## A chest, crate or barrel that opens: the region's prop for the look, and a WorldContainer whose id is
## the place's own (`<poi>/<key>`) so what was taken stays taken.
static func _container(d: PoiDressing, key: String, p: Vector2, yaw: float, table: String, shown: String,
		prop_kind := "chest") -> void:
	var k := d.kit
	if k.far:
		return
	var at := k.on_ground(p.x, p.y)
	var path := k.prop(prop_kind)
	if path != "":
		await k.step()
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


## A heap of something loose on the ground at local xz: a few overlapping low domes of `mat`, one
## mesh, walked over.
static func _heap(d: PoiDressing, st: SurfaceTool, c: Vector2, r: float, h: float, lumps := 4) -> void:
	var k := d.kit
	for i in lumps:
		var o := k.jitter(r * 0.45) if i > 0 else Vector2.ZERO
		var rr := r * (1.0 if i == 0 else k.rng.randf_range(0.45, 0.7))
		var hh := h * (1.0 if i == 0 else k.rng.randf_range(0.5, 0.85))
		var g := k.on_ground(c.x + o.x, c.y + o.y, -hh * 0.25)
		d.masonry.ellipsoid(st, g, Vector3(rr, hh, rr * k.rng.randf_range(0.8, 1.1)), Basis(Vector3.UP, k.rng.randf() * TAU))


# --- Dunnow ------------------------------------------------------------------------------------------

## Dunnow, the Remembered Hold: the seven clans' hold of the Long Tally, cut into the foot of the Wall
## above the Windgate road. Three storeys of dressed limestone front step back up the face, each a
## terrace with a parapet, so that the hold is the cliff's own front made square: a plinth and
## pilasters, rows of windows with dressed surrounds (and a fire behind them again), a great door
## under a giant's thigh-bone for a lintel, up a landing and a flight of steps. Either side of the door
## the Long Tally: rows of notches cut in fives, every blood-price the Moot ever set, and among them
## pale rasped patches where names have lately been ground out, the stone-dust still heaped under
## them. Chains of the Chain Years hang down the storeys from iron rings. On the top terrace the
## beacon basket burns. In the yard the Unwritten's fire, their gear and their grindstone; off to the
## road side, under a boulder, the turf lean-to of the last keeper, who came back up when she saw the
## windows lit, and the Tally Walk of notched stones out toward the road.
static func dunnow(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var site := _site_of(d)
	var interior := str(site.get("interior", ""))
	var into := _bearing(site, "face_bearing_deg", Vector2(0.0, -1.0))
	var out := -into
	var across := Vector2(out.y, -out.x)       # a block's own +x when it is turned to face `out`
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(out))
	var g0 := k.on_ground(0.0, 0.0).y
	# where the face begins: the nearest the ground stands a man's height over the yard along the front
	var foot := 34.0
	for s in [-10.0, -5.0, 0.0, 5.0, 10.0]:
		var r := 6.0
		while r < foot:
			var p := into * r + across * float(s)
			if k.on_ground(p.x, p.y).y - g0 > 2.2:
				foot = r
				break
			r += 0.5
	var front := foot - 1.2
	var gb := INF
	for s in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		var p := into * front + across * float(s)
		gb = minf(gb, k.on_ground(p.x, p.y).y)
	var reach := d.pad_radius + 0.8
	# the storeys: [width, height, set back from the front]; each stands on the one below and goes back
	# into the face until the rock behind it stands over its top
	var tiers := [[24.0, 8.0, 0.0], [17.0, 6.0, 3.2], [10.0, 5.0, 6.4]]
	var sw: Variant = _sites().Stones.new(k, d.poi_id.hash() + 41)
	var dark := m.begin()
	var lit := m.begin()
	var tops: Array[float] = []
	var fronts: Array[float] = []
	var bottom := gb - 1.4
	var top := gb
	for i in tiers.size():
		var t: Array = tiers[i]
		var w := float(t[0])
		var h := float(t[1])
		var fd := front + float(t[2])
		top += h
		var depth := 3.0
		while depth < 18.0:
			var ok := true
			for s in [-0.5, 0.0, 0.5]:
				var q := into * (fd + depth) + across * (w * float(s))
				if k.on_ground(q.x, q.y).y < top + 0.6:
					ok = false
					break
			if ok:
				break
			depth += 0.5
		depth = minf(depth + 1.0, sqrt(maxf(reach * reach - w * w * 0.25, 1.0)) - fd)
		var c := into * (fd + depth * 0.5)
		sw.top = top + 0.9
		var xf := Transform3D(fb, Vector3(c.x, (bottom + top) * 0.5, c.y))
		sw.block(xf, Vector3(w, top - bottom, depth))
		k.collider(Vector3(w, top - bottom, depth), xf, "stone")
		# the cornice and the parapet along the terrace's front, with gaps to look down through
		var fc := into * fd
		sw.block(Transform3D(fb, Vector3(fc.x, top - 0.2, fc.y) + Vector3(out.x, 0.0, out.y) * 0.25), Vector3(w + 0.6, 0.4, 0.6))
		var bays := int(w / 2.0)
		for q in bays:
			if q % 4 == 3:
				continue
			var x := (float(q) + 0.5 - float(bays) * 0.5) * (w / float(bays))
			var ph := 1.0 if k.rng.randf() > 0.15 else k.rng.randf_range(0.4, 0.7)
			sw.block(Transform3D(fb, Vector3(fc.x, top + ph * 0.5, fc.y) + fb * Vector3(x, 0.0, -0.1)), Vector3(w / float(bays) * 0.96, ph, 0.5))
		if not k.far:
			k.collider(Vector3(w, 1.0, 0.5), Transform3D(fb, Vector3(fc.x, top + 0.5, fc.y) + fb * Vector3(0.0, 0.0, -0.1)), "stone")
		# the cheeks: the crag left standing either side of the cut front, rough, to the storey's top (the
		# lower two storeys; the top one stands back in the face), kept inside the pad
		for s in [-1.0, 1.0]:
			for q in (4 if i < 2 else 0):
				var lz := fd + 0.9 + (depth - 0.9) * (float(q) + 0.5) / 4.0
				var lsz := Vector3(k.rng.randf_range(2.4, 3.6), top - bottom + k.rng.randf_range(0.4, 1.6), (depth - 0.9) / 4.0 + 1.2)
				var lp := into * lz + across * (float(s) * (w * 0.5 + lsz.x * 0.35))
				var cheek_b := fb * Basis(Vector3.UP, k.rng.randf_range(-0.25, 0.25)) * Basis(Vector3.BACK, k.rng.randf_range(-0.12, 0.12))
				if lp.length() + lsz.length() * 0.5 > reach + 0.6:
					continue
				sw.block(Transform3D(cheek_b, Vector3(lp.x, (bottom + top) * 0.5 + 0.2, lp.y)), lsz, Color(0.88, 0.87, 0.84))
		tops.append(top)
		fronts.append(fd)
		bottom = top - 0.4
	await k.step()
	# the front: a plinth, pilasters dividing the bays, a string course under each cornice, windows
	var f1 := into * front
	var base := Vector3(f1.x, gb, f1.y)
	var o3 := Vector3(out.x, 0.0, out.y)
	sw.top = tops[0] + 0.9
	sw.block(Transform3D(fb, base + Vector3(0.0, -0.4, 0.0) + o3 * 0.3), Vector3(24.6, 2.0, 0.6))
	for x in [-11.6, -7.6, -3.3, 3.3, 7.6, 11.6]:
		sw.block(Transform3D(fb, base + fb * Vector3(float(x), 3.6, 0.2)), Vector3(0.95, 6.6, 0.4))
	for i in tiers.size():
		var w := float((tiers[i] as Array)[0])
		var fc := into * fronts[i]
		sw.block(Transform3D(fb, Vector3(fc.x, tops[i] - 1.1, fc.y) + o3 * 0.18), Vector3(w + 0.3, 0.3, 0.36))
	# windows: a dark (and, after dark, lit) opening in a dressed surround, a sill under it
	var surround := Color(1.08, 1.06, 1.0)
	var rows := [[0, 5.0, [-9.6, -5.5, 5.5, 9.6]], [1, 2.9, [-6.0, -3.0, 0.0, 3.0, 6.0]], [2, 2.5, [-2.6, 0.0, 2.6]]]
	for row_v in rows:
		var row: Array = row_v
		var i := int(row[0])
		var fc := into * fronts[i]
		var y := (gb if i == 0 else tops[i - 1]) + float(row[1])
		for x_v in row[2]:
			var wc := Vector3(fc.x, y, fc.y) + fb * Vector3(float(x_v), 0.0, 0.0)
			var glow := lit if (i + int(float(x_v) * 3.0)) % 3 != 0 else dark
			m.block(glow, Transform3D(fb, wc + o3 * 0.03), Vector3(0.7, 1.7, 0.06))
			sw.block(Transform3D(fb, wc + o3 * 0.12 + Vector3.UP * 1.0), Vector3(1.25, 0.3, 0.26), surround)
			sw.block(Transform3D(fb, wc + o3 * 0.16 + Vector3.DOWN * 0.95), Vector3(1.3, 0.2, 0.34), surround)
			for s in [-1.0, 1.0]:
				sw.block(Transform3D(fb, wc + o3 * 0.1 + fb * Vector3(float(s) * 0.5, 0.0, 0.0)), Vector3(0.3, 1.9, 0.22), surround)
	# the great door: a dark way in, jambs of single stones, the landing it stands on and steps down
	var sill := gb + 1.2
	m.block(dark, Transform3D(fb, base + fb * Vector3(0.0, 1.2 + 2.6, 0.04)), Vector3(3.6, 5.2, 0.08))
	for s in [-1.0, 1.0]:
		var jxf := Transform3D(fb, base + fb * Vector3(float(s) * 2.25, 1.2 + 2.7, 0.3))
		sw.block(jxf, Vector3(0.9, 5.4, 0.6), surround)
		k.collider(Vector3(0.9, 5.4, 0.6), jxf, "stone")
	var lintel := Transform3D(fb, base + fb * Vector3(0.0, 6.85, 0.32))
	sw.block(lintel, Vector3(5.6, 0.7, 0.64), surround)
	k.collider(Vector3(5.6, 0.7, 0.64), lintel, "stone")
	var landing := Transform3D(fb, base + fb * Vector3(0.0, (1.2 - 1.6) * 0.5, 1.6))
	sw.block(landing, Vector3(8.0, 1.6 + 1.2, 3.2))
	k.collider(Vector3(8.0, 1.6 + 1.2, 3.2), landing, "stone")
	var step_from := f1 + out * 3.2
	var stair_st := m.begin()
	m.steps(stair_st, step_from, out, sill, 4, -0.3, 0.5, 5.0, 1.6)
	_sites()._commit(d, sw, null, "Dunnow", true)
	m.commit(dark, PoiKit.plain(DARK, 0.95), "DunnowDark", true)
	m.commit(lit, PoiKit.plain(Color(0.2, 0.1, 0.05), 0.9, 0.0, LIT, 1.4), "DunnowWindows", true)
	await k.step()
	# the beacon basket on the top terrace, burning: seen from the Windgate road at night
	var bt := into * (fronts[2] + 1.6)
	var bb := Vector3(bt.x, tops[2], bt.y)
	var iron := m.begin()
	m.rod(iron, Transform3D(Basis.IDENTITY, bb + Vector3.UP * 1.0), 0.09, 2.0)
	for q in 8:
		var a := TAU * float(q) / 8.0
		m.limb(iron, bb + Vector3.UP * 1.9 + Vector3(sin(a), 0.0, cos(a)) * 0.25, bb + Vector3.UP * 2.7 + Vector3(sin(a), 0.0, cos(a)) * 0.6, 0.035)
	m.commit(iron, PoiKit.plain(IRON, 0.6, 0.5), "Beacon", true)
	var embers := m.begin()
	m.ellipsoid(embers, bb + Vector3.UP * 2.45, Vector3(0.5, 0.25, 0.5))
	m.commit(embers, PoiKit.plain(Color(0.3, 0.12, 0.04), 0.9, 0.0, Color(1.0, 0.45, 0.12), 3.0), "BeaconFire", true)
	if k.far:
		return
	k.light(bb + Vector3.UP * 2.8, Color(1.0, 0.6, 0.3), 2.6, 16.0)
	k.puffs(bb + Vector3.UP * 3.2, Vector3(0.3, 0.2, 0.3), 7.0, 14, Color(0.32, 0.31, 0.3, 0.35), 2.0, 7.0)
	m.commit(stair_st, _sites().stone_look(k, gb), "DunnowSteps")
	# the bone over the door: a giant's thigh, its knuckles either end, laid on the lintel stone
	var bone := m.begin()
	var lc := base + fb * Vector3(0.0, 7.78, 0.32)
	m.limb(bone, lc + fb * Vector3(-2.6, 0.0, 0.0), lc + fb * Vector3(2.6, 0.0, 0.0), 0.38)
	for s in [-1.0, 1.0]:
		m.ellipsoid(bone, lc + fb * Vector3(float(s) * 3.0, 0.08, 0.0), Vector3(0.62, 0.55, 0.5))
	await k.step()
	m.commit(bone, PoiKit.painted(5, BONE, 0.7, 0.7), "ThighBone")
	# the Long Tally either side of the door: notches in fives, a cut across every fifth; and the pale
	# patches where names have been rasped out of it, the dust heaped below
	var notches := m.begin()
	var scraped := m.begin()
	var dust := m.begin()
	for side in [-1.0, 1.0]:
		var patches: Array[Vector2] = []
		for q in 3:
			patches.append(Vector2(float(side) * k.rng.randf_range(3.9, 6.6), k.rng.randf_range(1.6, 3.4)))
		for r_i in 6:
			var y := 1.5 + 0.42 * float(r_i)
			for c_i in 30:
				var x := float(side) * (3.1 + 0.115 * float(c_i) + 0.12 * floorf(float(c_i) / 5.0))
				if absf(x) > 7.1:
					continue
				var rasped := false
				for p in patches:
					if absf(x - p.x) < 0.5 and absf(y - p.y) < 0.3:
						rasped = true
				if rasped:
					continue
				if c_i % 5 == 4:
					m.block(notches, Transform3D(fb * Basis(Vector3.BACK, 1.0), base + fb * Vector3(x - float(side) * 0.23, y, 0.025)), Vector3(0.04, 0.5, 0.02))
				else:
					m.block(notches, Transform3D(fb, base + fb * Vector3(x, y, 0.025)), Vector3(0.035, 0.3, 0.02))
		for p in patches:
			m.block(scraped, Transform3D(fb, base + fb * Vector3(p.x, p.y, 0.02)), Vector3(1.0, 0.62, 0.02))
			var under := f1 + across * p.x + out * 0.6
			_heap(d, dust, under, 0.5, 0.18, 3)
	m.commit(notches, PoiKit.plain(Color(0.2, 0.19, 0.17), 0.95), "LongTally")
	m.commit(scraped, PoiKit.plain(Color(0.86, 0.84, 0.78), 0.9), "Rasped")
	m.commit(dust, PoiKit.plain(Color(0.82, 0.8, 0.75), 0.95), "StoneDust")
	k.touchable("LongTally", base + fb * Vector3(-5.0, 2.4, 0.6), "Read the Long Tally", DIALOGUE + "dunnow_long_tally", "", false)
	await k.step()
	# the chains of the Chain Years, hung from iron rings: down the storeys, and the door's pair to the ground
	var chain := m.begin()
	for s in [-1.0, 1.0]:
		var f2 := into * fronts[1]
		var hi := Vector3(f2.x, tops[1] - 0.6, f2.y) + fb * Vector3(float(s) * 7.8, 0.0, 0.2)
		var lo := Vector3(f1.x, tops[0] + 0.1, f1.y) + fb * Vector3(float(s) * 10.4, 0.0, -1.6)
		_chain(m, chain, hi, lo, 0.4, 0.6)
		var dh := base + fb * Vector3(float(s) * 3.0, 6.6, 0.55)
		var dl := Vector3(step_from.x, 0.0, step_from.y) + fb * Vector3(float(s) * 4.6, 0.0, 0.6)
		dl.y = k.on_ground(dl.x, dl.z).y + 0.5
		_chain(m, chain, dh, dl, 0.36, 1.2)
		m.rod(chain, Transform3D(Basis.IDENTITY, dl + Vector3.DOWN * 0.2), 0.32, 0.9)
		k.collider(Vector3(0.64, 0.9, 0.64), Transform3D(Basis.IDENTITY, dl + Vector3.DOWN * 0.2), "stone")
	await k.step()
	m.commit(chain, PoiKit.plain(IRON, 0.55, 0.6), "Chains")
	# the door into the hold
	if interior != "":
		_sites()._door(d, interior, base + fb * Vector3(0.0, 1.2, 0.5), PoiKit.yaw_of(out))
	k.light(base + fb * Vector3(0.0, 4.0, 2.0), Color(1.0, 0.66, 0.36), 1.4, 9.0)
	k.marker("the_landing", Vector3(step_from.x, sill, step_from.y) - Vector3(out.x, 0.0, out.y) * 1.4, false, true, 2.5)
	# the yard: the Unwritten's fire, their bedrolls and gear, the grindstone they put an edge on their
	# rasps with, and their chest
	var fire := f1 + out * 11.0 + across * 4.5
	await _prop(d, "campfire", fire, k.rng.randf() * TAU)
	k.light(k.on_ground(fire.x, fire.y, 0.6), Color(1.0, 0.6, 0.3), 2.0, 10.0)
	k.marker("the_yard_fire", k.on_ground(fire.x + out.x * 2.4, fire.y + out.y * 2.4))
	for i in 3:
		var a := PoiKit.yaw_of(out) + 0.9 + float(i) * 0.8
		var p := fire + Vector2(sin(a), cos(a)) * 3.0
		await _prop(d, "bedroll", p, a)
	await _prop(d, "whetstone", fire + across * 3.6 - out * 1.0, PoiKit.yaw_of(across))
	await _prop(d, "sack", fire + across * 4.4 + out * 0.8, k.rng.randf() * TAU)
	await _prop(d, "crate", fire + across * 4.6 - out * 0.4, PoiKit.yaw_of(out))
	await _container(d, "unwritten_chest", fire + across * 5.6 + out * 1.6, PoiKit.yaw_of(-across), "core:loot/common_chest", "The Unwritten's Chest")
	# the keeper's lean-to on the road side: turf on poles against a boulder, her fire and her stool
	var road := _toward_road(k, 320.0)
	if road == Vector2.ZERO or road.dot(out) < -0.2:
		road = -across
	var side := -across if road.dot(-across) > road.dot(across) else across
	var lean := f1 + out * 14.0 + side * 15.0
	var rock := k.rock("boulder", 2)
	if rock != "":
		await k.step()
		k.place(rock, k.on_ground(lean.x - side.x * 2.2, lean.y - side.y * 2.2, -0.6), k.rng.randf() * TAU, 1.3, true)
	var turf := m.begin()
	var poles := m.begin()
	var lb := Basis(Vector3.UP, PoiKit.yaw_of(side))
	var lg := k.on_ground(lean.x, lean.y)
	for s in [-1.0, 1.0]:
		m.post(poles, lean + across * (float(s) * 1.3) + side * 1.0, 1.25, 0.12)
	# boards from the posts back to the boulder, the turf laid on them
	var roof := Transform3D(lb * Basis(Vector3.RIGHT, 0.5), lg + Vector3.UP * 1.35 + Vector3(side.x, 0.0, side.y) * 0.1)
	m.block(poles, roof, Vector3(3.2, 0.08, 2.6))
	k.collider(Vector3(3.2, 0.08, 2.6), roof, "wood")
	m.block(turf, roof.translated_local(Vector3.UP * 0.14), Vector3(3.3, 0.2, 2.7))
	await k.step()
	m.commit(poles, k.surface("timber", 0.8), "LeanToFrame")
	m.commit(turf, PoiKit.painted(5, {"base": "#5d6040", "accent": "#4a4c32", "grout": "#33341f", "unit": 0.3}, 0.7), "LeanToTurf")
	var hearth := lean + side * 3.2 - out * 0.6
	await _prop(d, "campfire", hearth, 0.0, 0.7)
	await _prop(d, "stool", hearth + side * 1.3, PoiKit.yaw_of(-side))
	await _prop(d, "bedroll", lean + side * 0.2, PoiKit.yaw_of(across))
	_spot(d, "home", lean + side * 1.6)
	_spot(d, "the_keepers_seat", hearth + side * 1.4 + into * 0.6)
	# the Tally Walk: notched stones either side of the way out toward the road
	var way: Array = [step_from + out * 2.0, step_from + out * 9.0 + side * 5.0, step_from + out * 15.0 + side * 13.0]
	var edge := (way[2] as Vector2).normalized() * (d.pad_radius * 0.95)
	way.append(edge)
	var earth := m.begin()
	_track(d, earth, way, 2.4)
	await k.step()
	m.commit(earth, k.surface("earth", 0.4), "Trodden")
	var stone := k.rock("standing_stone", 1)
	if stone != "":
		var walk: Array = []
		for i in 5:
			var t := float(i + 1) / 6.0
			var p: Vector2 = (way[2] as Vector2).lerp(edge, t)
			var dirw := (edge - (way[2] as Vector2)).normalized()
			p += Vector2(-dirw.y, dirw.x) * (2.2 if i % 2 == 0 else -2.2)
			walk.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.15), k.rng.randf() * TAU, k.rng.randf_range(0.28, 0.36)))
		await k.step()
		k.scatter(stone, walk, true)


## A drystone bothy: four walls of the kit's courses with a door gap toward `face`, a turf roof of two
## pitches, a smoke-hole. `c` is its middle (local xz). Returns where its door is (local xz).
static func _bothy(d: PoiDressing, c: Vector2, face: Vector2, w: float, depth: float, smoke := true) -> Vector2:
	var k := d.kit
	var m := d.masonry
	var side := Vector2(face.y, -face.x)
	var hw := w * 0.5
	var hd := depth * 0.5
	var stone := m.begin()
	var fl := c + face * hd - side * hw
	var fr := c + face * hd + side * hw
	var bl := c - face * hd - side * hw
	var br := c - face * hd + side * hw
	m.wall(stone, bl, br, 1.9, 0.0)
	m.wall(stone, br, fr, 1.9, 0.0)
	m.wall(stone, bl, fl, 1.9, 0.0)
	var gap := 0.55
	m.wall(stone, fl, c + face * hd - side * gap, 1.9, 0.0)
	m.wall(stone, c + face * hd + side * gap, fr, 1.9, 0.0)
	await k.step()
	m.commit(stone, k.surface("stone", 0.8), "BothyWalls", true)
	var g := -INF
	for p in [fl, fr, bl, br]:
		g = maxf(g, k.on_ground((p as Vector2).x, (p as Vector2).y).y)
	var turf := m.begin()
	var yaw := PoiKit.yaw_of(face)
	for s in [-1.0, 1.0]:
		var pitch := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -0.55 * float(s))
		var at := Vector3(c.x, g + 2.35, c.y) + Vector3(side.x, 0.0, side.y) * (hw * 0.5 * float(s))
		m.block(turf, Transform3D(pitch, at), Vector3(hw * 1.22, 0.32, depth + 0.6))
		k.collider(Vector3(hw * 1.22, 0.32, depth + 0.6), Transform3D(pitch, at), "dirt")
	await k.step()
	m.commit(turf, PoiKit.painted(5, {"base": "#5f6243", "accent": "#4b4d33", "grout": "#34351f", "unit": 0.3}, 0.75), "BothyTurf", true)
	if smoke and not k.far:
		k.puffs(Vector3(c.x, g + 2.9, c.y), Vector3(0.15, 0.1, 0.15), 3.0, 6, Color(0.36, 0.35, 0.33, 0.3), 1.0, 5.0)
	return c + face * (hd + 0.6)


## A rib of a giant from `foot` curving up to `apex` (local), as the ribs are: thick at the head,
## thinning as it goes, bowed outward; into `st`, with boxes to walk into.
static func _rib(d: PoiDressing, st: SurfaceTool, foot: Vector3, apex: Vector3, r0: float, r1: float, segs := 7) -> void:
	var flat := Vector3(apex.x - foot.x, 0.0, apex.z - foot.z)
	var ctrl := foot + Vector3.UP * (apex.y - foot.y) * 0.85 + flat * 0.05
	var prev := foot
	for i in segs:
		var t := float(i + 1) / float(segs)
		var p := foot * (1.0 - t) * (1.0 - t) + ctrl * 2.0 * (1.0 - t) * t + apex * t * t
		_limb_solid(d, st, prev, p, lerpf(r0, r1, (float(i) + 0.5) / float(segs)), "stone")
		prev = p
	d.masonry.ellipsoid(st, foot + Vector3.UP * 0.2, Vector3(r0 * 1.7, r0 * 1.3, r0 * 1.5))


## Ground a place has laid (a spoil tip, a heap of scree) made now rather than on a worker, so it can be
## walked on: one mesh of `st` in `mat`, a trimesh to stand on, drawn far when `silhouette`.
static func _ground_mesh(d: PoiDressing, st: SurfaceTool, mat: Material, node_name: String, silhouette := false) -> void:
	var k := d.kit
	if k.far and not silhouette:
		return
	st.generate_normals()
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = node_name
	k.root.add_child(mi)
	if k.far:
		k._far_range(mi)
	else:
		k.collider_shape(mesh.create_trimesh_shape(), Transform3D.IDENTITY, "dirt")


## A tongue of tipped spoil draped down the ground from `head` (local xz) along `along`: `length` long,
## `width` across, `height` at its crest, highest a third of the way down and running out to nothing
## at its toe and its sides, its edges a hand under the turf. Into `st`, laid on the ground's own shape.
static func _tip(d: PoiDressing, st: SurfaceTool, head: Vector2, along: Vector2, length: float, width: float, height: float) -> void:
	var k := d.kit
	var across := Vector2(-along.y, along.x)
	var nu := 12
	var nv := 8
	var rows: Array = []
	for i in nu + 1:
		var u := float(i) / float(nu)
		var row: Array = []
		var half := width * 0.5 * (0.55 + 0.45 * sin(minf(u * 1.4, 1.0) * PI * 0.5)) * (1.0 - 0.35 * u * u)
		for j in nv + 1:
			var v := float(j) / float(nv) * 2.0 - 1.0
			var wob := 1.0 + 0.12 * sin(u * 9.0 + float(j) * 1.3)
			var p := head + along * (u * length) + across * (v * half * wob)
			var crest := pow(sin(clampf(u * 1.15, 0.0, 1.0) * PI), 0.8) if u > 0.0 else 0.3
			var h := height * crest * (1.0 - pow(absf(v), 1.7)) + height * 0.12 * sin(u * 17.0 + v * 5.0) * sin(u * 7.0 - v * 9.0)
			h = maxf(h, 0.0)
			row.append(k.on_ground(p.x, p.y, h - 0.12))
		rows.append(row)
	for i in nu:
		for j in nv:
			var a: Vector3 = rows[i][j]
			var b: Vector3 = rows[i][j + 1]
			var c: Vector3 = rows[i + 1][j + 1]
			var e: Vector3 = rows[i + 1][j]
			for q in [a, c, b, a, e, c]:
				st.add_vertex(q)


# --- Ghaleld ----------------------------------------------------------------------------------------

## The ore the chains were made of, and what was tipped: red going to purple-black.
const ORE := {"base": "#7a3f2b", "accent": "#5a2c20", "grout": "#2e1a14", "unit": 0.45}
const SPOIL := {"base": "#5c4234", "accent": "#463126", "grout": "#271b15", "unit": 0.5}
## Its tips' streaks (PoiMasonry.spoil_heap): red waste, the iron's dark and an ochre run down it.
const IRON_TINTS := {"fresh": Color(1.08, 0.96, 0.9), "streak_a": Color(0.62, 0.55, 0.55),
		"streak_b": Color(1.25, 1.0, 0.62), "grass": Color(0.62, 1.05, 0.5)}

## Ghaleld, the chain-mine above Brindlecrag, where the iron for every chain bridge in the heights was
## dug and forged. Over the shaft the headframe is two pairs of a giant's ribs, stood up foot to foot
## and lashed at the crown with iron bands, the winding wheel hung between them twelve metres up: the
## Brindle miners stood the bones up because no timber in the heights was long enough. The shaft's
## collar of dressed stone, the miners' cage at its mouth, the rope over the wheel to the capstan the
## men walked round. Rust-red spoil tipped down the fellside toward the village in three tongues. The
## dressing floor with its bucking stones and heaps of ore; the forge with its anvil, where the chain
## was drawn, and the last length of it never carried down, lying in the grass in a long S. The
## chain-smith's bothy, and the board at the collar with the last shift's names under the Moot's order.
static func ghaleld(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var site := _site_of(d)
	var interior := str(site.get("interior", ""))
	var down := _bearing(site, "spoil_bearing_deg", k.downhill())
	if down == Vector2.ZERO:
		down = k.grain()
	var up := -down
	var side := Vector2(up.y, -up.x)
	var shaft := up * 3.0
	var sg := k.on_ground(shaft.x, shaft.y).y
	var lo := INF
	var hi := -INF
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var q := shaft + side * 2.1 * float(sx) + up * 2.1 * float(sz)
			lo = minf(lo, k.on_ground(q.x, q.y).y)
			hi = maxf(hi, k.on_ground(q.x, q.y).y)
	var collar := hi + 0.8
	var sb := Basis(Vector3.UP, PoiKit.yaw_of(down))
	var sw: Variant = _sites().Stones.new(k, d.poi_id.hash() + 7)
	sw.top = collar
	var dark := m.begin()
	# the collar: four walls of dressed stone about the black, a bearer across it
	for i in 4:
		var bb := sb * Basis(Vector3.UP, float(i) * PI * 0.5)
		var n := bb * Vector3(0.0, 0.0, 1.0)
		var c := Vector3(shaft.x, (lo - 0.4 + collar) * 0.5, shaft.y) + n * 1.75
		sw.block(Transform3D(bb, c), Vector3(4.3, collar - lo + 0.4, 0.8))
		k.collider(Vector3(4.3, collar - lo + 0.4, 0.8), Transform3D(bb, c), "stone")
	# the steps up to the collar on the down side, where the cage is boarded from
	var stair_at := shaft + down * 2.15
	var st_g := k.on_ground(stair_at.x + down.x * 2.0, stair_at.y + down.y * 2.0).y
	var n_steps := maxi(int(ceil((collar - st_g) / 0.3)), 1)
	m.steps(dark, stair_at + down * (0.45 * float(n_steps)), up, collar - 0.3 * float(n_steps), n_steps, 0.3, 0.45, 2.2, 1.2)
	_sites()._commit(d, sw, null, "Collar", true)
	await k.step()
	# the headframe: two arches of ribs over the shaft, their feet in the turf either side, crowns
	# lashed, the wheel's bearers across from crown to crown
	var H := 15.0
	var bone := m.begin()
	var crowns: Array[Vector3] = []
	for a_s in [-1.0, 1.0]:
		var crown := Vector3(shaft.x, sg + H, shaft.y) + Vector3(up.x, 0.0, up.y) * 1.5 * float(a_s)
		crowns.append(crown)
		for s in [-1.0, 1.0]:
			var fp := shaft + side * 5.4 * float(s) + up * 1.9 * float(a_s)
			var foot := k.on_ground(fp.x, fp.y, -0.35)
			_rib(d, bone, foot, crown + Vector3(side.x, 0.0, side.y) * 0.25 * float(s), 0.42, 0.24, 8)
	await k.step()
	m.commit(bone, PoiKit.painted(5, BONE, 0.7, 0.7), "RibFrame", true)
	# the wheel and its bearers, the cage at the collar and the capstan the men walked, all of a piece
	# of timber; the crowns' bands, the axle and the rope of iron and tarred hemp
	var timber := m.begin()
	var iron := m.begin()
	for c in crowns:
		m.rod(iron, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c + Vector3.DOWN * 0.2), 0.5, 0.5)
	var wc := Vector3(shaft.x, sg + H - 1.6, shaft.y) + Vector3(side.x, 0.0, side.y) * 1.4
	m.block(timber, Transform3D(sb, (crowns[0] + crowns[1]) * 0.5 + Vector3.DOWN * 0.55), Vector3(0.3, 0.3, 3.6))
	for s in [-1.0, 1.0]:
		m.limb(timber, crowns[0 if s < 0.0 else 1] + Vector3.DOWN * 0.6, wc + Vector3(up.x, 0.0, up.y) * 0.9 * float(s), 0.09)
	var wr := 1.45
	var wface := Basis(Vector3.UP, PoiKit.yaw_of(up))
	for i in 18:
		var a := TAU * (float(i) + 0.5) / 18.0
		var p := wc + wface * Vector3(sin(a) * wr, cos(a) * wr, 0.0)
		m.block(timber, Transform3D(wface * Basis(Vector3.BACK, -a), p), Vector3(wr * 0.37, 0.13, 0.12))
	for i in 8:
		var a := TAU * float(i) / 8.0
		m.limb(timber, wc, wc + wface * Vector3(sin(a) * wr, cos(a) * wr, 0.0), 0.04)
	m.rod(iron, Transform3D(wface * Basis(Vector3.RIGHT, PI * 0.5), wc), 0.1, 2.2)
	var cap := shaft + side * 15.0 + down * 2.0
	var cg := k.on_ground(cap.x, cap.y)
	m.limb(iron, wc - Vector3(side.x, 0.0, side.y) * wr, Vector3(shaft.x, collar + 2.1, shaft.y), 0.04)
	m.limb(iron, wc + Vector3(side.x, 0.0, side.y) * wr, cg + Vector3.UP * 1.0, 0.04)
	# the cage, standing on the collar over the shaft's mouth: posts, a roof, a plank floor, rails
	var cc := Vector3(shaft.x, collar, shaft.y)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.block(timber, Transform3D(sb, cc + sb * Vector3(float(sx) * 1.35, 1.05, float(sz) * 1.35)), Vector3(0.14, 2.1, 0.14))
	m.block(timber, Transform3D(sb, cc + Vector3.UP * 2.12), Vector3(2.9, 0.1, 2.9))
	m.block(timber, Transform3D(sb, cc + Vector3.UP * 0.05), Vector3(2.9, 0.1, 2.9))
	for y in [0.7, 1.4]:
		for sz in [-1.0, 1.0]:
			m.block(timber, Transform3D(sb, cc + sb * Vector3(float(sz) * 1.35, float(y), 0.0)), Vector3(0.06, 0.08, 2.8))
	k.collider(Vector3(2.9, 0.1, 2.9), Transform3D(sb, cc + Vector3.UP * 0.05), "wood")
	# the capstan: its post, its drum, four bars
	m.rod(timber, Transform3D(Basis.IDENTITY, cg + Vector3.UP * 1.1), 0.2, 2.2)
	m.rod(timber, Transform3D(Basis.IDENTITY, cg + Vector3.UP * 1.0), 0.6, 0.7)
	for i in 4:
		var a := float(i) * PI * 0.5 + 0.4
		m.block(timber, Transform3D(Basis(Vector3.UP, a), cg + Vector3.UP * 1.05 + Vector3(sin(a), 0.0, cos(a)) * 1.9), Vector3(0.12, 0.12, 3.0))
	k.collider(Vector3(1.3, 1.6, 1.3), Transform3D(Basis.IDENTITY, cg + Vector3.UP * 0.8), "wood")
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "Winding", true)
	m.commit(iron, PoiKit.plain(Color(0.24, 0.21, 0.18), 0.7, 0.3), "IronAndRope", true)
	m.commit(dark, _sites().stone_look(k, sg), "CollarSteps", true)
	if k.far:
		return
	var black := m.begin()
	m.block(black, Transform3D(sb, k.on_ground(shaft.x, shaft.y, 0.03)), Vector3(2.65, 0.04, 2.65))
	m.commit(black, PoiKit.plain(DARK, 1.0), "TheShaft")
	if interior != "":
		_sites()._door(d, interior, cc + Vector3(down.x, 0.0, down.y) * 0.4, PoiKit.yaw_of(down))
	k.light(cc + Vector3.UP * 1.9, Color(1.0, 0.7, 0.4), 1.2, 7.0)
	# the board at the collar: the last shift's names, and the Moot's order nailed over them
	var board_at := shaft + down * 2.6 + side * 2.0
	var bt := m.begin()
	var bt_top := m.post(bt, board_at, 1.8, 0.14)
	m.block(bt, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(down)), bt_top + Vector3.DOWN * 0.45 + Vector3(down.x, 0.0, down.y) * 0.09), Vector3(0.9, 0.7, 0.05))
	m.commit(bt, k.surface("timber", 0.9), "ShiftBoard")
	k.touchable("ShiftBoard", bt_top + Vector3.DOWN * 0.45 + Vector3(down.x, 0.0, down.y) * 0.3, "Read the board at the collar", DIALOGUE + "ghaleld_shift_board", "", false)
	await k.step()
	# the ring the men wore in the turf walking the capstan
	var earth := m.begin()
	var ring: Array = []
	for i in 25:
		var a := TAU * float(i) / 24.0
		ring.append(cap + Vector2(sin(a), cos(a)) * 3.4)
	_track(d, earth, ring, 1.2)
	# the cart way from the collar down past the floor, toward the village
	var road := _toward_road(k, 320.0)
	if road == Vector2.ZERO:
		road = down
	var way_end := (down * 0.6 + road * 0.4).normalized() * d.pad_radius * 0.95
	_track(d, earth, [stair_at + down * 3.0, stair_at + down * 9.0 - side * 3.0, way_end], 2.6)
	await k.step()
	m.commit(earth, k.surface("earth", 0.45), "Trodden")
	# the spoil: three tongues of red waste tipped down the fell toward Brindlecrag, each a tip with a
	# level top where the barrows ran out, terraced and rilled down its face, the iron's dark and the
	# ochre run down it
	var spoil_mat := PoiKit.painted(5, SPOIL, 0.85, 0.9)
	var lumps_at: Array = []
	for t in [[down * 7.0 + side * 5.5, (down + side * 0.15).normalized(), 21.0, 10.0, 3.0],
			[down * 8.0 - side * 4.0, (down - side * 0.1).normalized(), 24.0, 11.0, 3.4],
			[down * 4.0 - side * 13.0, (down - side * 0.35).normalized(), 15.0, 8.0, 2.2]]:
		var head: Vector2 = t[0]
		var along: Vector2 = t[1]
		var length := float(t[2])
		var width := float(t[3])
		await k.step()
		lumps_at.append_array(m.spoil_heap(head + along * length * 0.42, along, width * 0.5, float(t[4]), spoil_mat,
				IRON_TINTS, false, "Spoil", length / width))
	# lumps of red waste rock on the tips' benches, tumbled to their toes
	await k.step()
	for mm_v in m.spoil_stones(lumps_at):
		if mm_v != null:
			(mm_v as MultiMeshInstance3D).material_override = PoiKit.painted(5, ORE, 0.8, 0.8)
	# the dressing floor: flags laid level, the bucking stones, the ore heaped by grade, baskets, a barrow
	var fl := shaft - side * 8.0 + down * 1.0
	var fg := k.on_ground(fl.x, fl.y)
	var flags := m.begin()
	var fyaw := PoiKit.yaw_of(down)
	var fbas := Basis(Vector3.UP, fyaw)
	for i in 4:
		for j in 3:
			var p := fl + side * (-2.4 + 1.6 * float(i)) + down * (-1.6 + 1.6 * float(j))
			var g := k.on_ground(p.x, p.y)
			m.block(flags, Transform3D(fbas * Basis(Vector3.UP, k.rng.randf_range(-0.05, 0.05)), g + Vector3.DOWN * 0.1), Vector3(1.55, 0.32, 1.55))
	for q in 3:
		var p := fl + side * (-1.6 + 1.6 * float(q)) - down * 2.6
		m.block(flags, Transform3D(fbas, k.on_ground(p.x, p.y, 0.25)), Vector3(0.8, 0.5, 0.7))
		k.collider(Vector3(0.8, 0.5, 0.7), Transform3D(fbas, k.on_ground(p.x, p.y, 0.25)), "stone")
	m.commit(flags, _sites().stone_look(k, fg.y), "DressingFloor")
	var ore := m.begin()
	_heap(d, ore, fl + side * 4.4 + down * 0.5, 1.1, 0.6, 4)
	_heap(d, ore, fl + side * 4.0 - down * 1.8, 0.8, 0.45, 3)
	_heap(d, ore, fl - side * 4.0 + down * 0.4, 1.0, 0.5, 4)
	await k.step()
	m.commit(ore, PoiKit.painted(5, ORE, 0.8, 0.8), "Ore")
	await _prop(d, "hammer", fl - down * 2.6, k.rng.randf() * TAU, 1.0, 0.52)
	await _prop(d, "hammer", fl + side * 1.6 - down * 2.6, k.rng.randf() * TAU, 1.0, 0.52)
	await _prop(d, "basket", fl + side * 3.2 - down * 0.8, 0.4)
	await _prop(d, "basket", fl + side * 3.4 + down * 1.6, 1.3)
	await _prop(d, "wheelbarrow", fl - side * 3.6 - down * 1.5, PoiKit.yaw_of(side))
	# the forge where the chain was drawn: hearth, anvil, the quench, and the last length of chain
	var fo := shaft - side * 10.0 + up * 8.0
	await _prop(d, "forge_hearth", fo, PoiKit.yaw_of(down))
	k.light(k.on_ground(fo.x, fo.y, 0.9), Color(1.0, 0.5, 0.2), 1.6, 8.0)
	await _prop(d, "anvil", fo + down * 2.2 + side * 0.6, PoiKit.yaw_of(side))
	await _prop(d, "tongs", fo + down * 2.2 + side * 1.4, 0.3, 1.0, 0.0)
	await _prop(d, "barrel", fo + side * 2.0 + down * 0.4, 0.0)
	_spot(d, "the_forge", fo + down * 3.2 + side * 0.2)
	var links := m.begin()
	var path: Array[Vector3] = []
	for i in 26:
		var t := float(i) / 25.0
		var p := fo + down * (4.0 + 9.0 * t) + side * (3.0 + 3.2 * sin(t * TAU * 0.85))
		path.append(k.on_ground(p.x, p.y, 0.12))
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var dir := (b - a).normalized()
		var flat := i % 2 == 0
		var yb := Basis.looking_at(dir, Vector3.UP) * (Basis.IDENTITY if flat else Basis(Vector3.BACK, PI * 0.5))
		var c := (a + b) * 0.5
		for s in [-1.0, 1.0]:
			m.block(links, Transform3D(yb, c + yb.x * 0.17 * float(s)), Vector3(0.08, 0.08, 0.62))
		for s in [-1.0, 1.0]:
			m.block(links, Transform3D(yb, c + yb.z * 0.3 * float(s)), Vector3(0.42, 0.08, 0.08))
	await k.step()
	m.commit(links, PoiKit.plain(RUST, 0.8, 0.35), "LastLength")
	k.touchable("LastLength", path[12] + Vector3.UP * 0.4, "Look at the length of chain", DIALOGUE + "ghaleld_last_length", "", false)
	# the chain-smith's bothy, up the slope from her forge, and her store
	var home := fo + up * 7.0 - side * 4.0
	var door: Vector2 = await _bothy(d, home, down, 5.0, 4.0)
	_spot(d, "home", door + down * 0.6)
	await _container(d, "smiths_store", home + side * 3.4, PoiKit.yaw_of(down), "core:loot/common_chest", "The Chain-Smith's Store")
	k.marker("the_spoil", k.on_ground(down.x * 14.0, down.y * 14.0))


# --- the dull places, built as their briefs say (phase 2) -------------------------------------------
# Every ruin in Skerrow was the ruins kind's one roofless hall, and every ring of stones the same three
# leaning stones: a hold of the Bone Clan and a lead-miners' rake and a sealed silver working all looked
# alike. Each now has a builder of its own that tells its sentence: what it was, the heart of it, and
# the thing in it to find or touch.

const LIME := {"base": "#b1ac9f", "accent": "#958f82", "grout": "#5f5a51", "unit": 0.45}
const SLATE := {"base": "#5e6266", "accent": "#4a4e52", "grout": "#2c2f32", "unit": 0.3}
const DEAD_SPOIL := {"base": "#5c5a55", "accent": "#4a4844", "grout": "#2c2b28", "unit": 0.8}
const HEATHER := {"base": "#6a4a5e", "accent": "#4c3a3c", "grout": "#2e2424", "unit": 0.08}


## A cairn of stacked flat stones at local xz `at`: `r` across its foot, `h` high, each course smaller and
## turned; into `st`, with a box to walk into. Returns its top (local).
static func _cairn(d: PoiDressing, st: SurfaceTool, at: Vector2, r: float, h: float) -> Vector3:
	var k := d.kit
	var g := k.on_ground(at.x, at.y)
	var courses := maxi(int(h / (r * 0.38)), 4)
	var step_h := h / float(courses)
	var y := g.y - 0.1
	for i in courses:
		var f := float(i) / float(courses)
		var rr := r * (1.0 - 0.72 * f)
		var n := maxi(int(round(6.0 * (1.0 - f))), 1) if i < courses - 1 else 1
		var turn := k.rng.randf() * TAU
		for j in n:
			var a := turn + TAU * float(j) / float(n)
			var off := Vector3(sin(a), 0.0, cos(a)) * (rr * 0.55 if n > 1 else 0.0)
			var sr := rr * (0.55 if n > 1 else 0.8) * k.rng.randf_range(0.85, 1.15)
			var tilt := Basis(Vector3.UP, k.rng.randf() * TAU) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.25, 0.25)) * Basis(Vector3.BACK, k.rng.randf_range(-0.2, 0.2))
			d.masonry.ellipsoid(st, Vector3(g.x, y + step_h * 0.5, g.z) + off, Vector3(sr, step_h * k.rng.randf_range(0.6, 0.8), sr * k.rng.randf_range(0.7, 0.95)), tilt)
		y += step_h
	k.collider(Vector3(r * 1.5, h, r * 1.5), Transform3D(Basis.IDENTITY, Vector3(g.x, g.y + h * 0.5 - 0.1, g.z)), "stone")
	return Vector3(g.x, y, g.z)


## A doorway cut in a dressed face: its surround (two jambs and a lintel, proud of the face), and in it
## either a dark way on (`open`) or the rougher stone it was walled up with. `at` is the foot of the
## doorway's middle on the face (local), `fb` the face's basis (+z out of it).
static func _cut_door(d: PoiDressing, sw: Variant, dark: SurfaceTool, at: Vector3, fb: Basis, w: float, h: float, open: bool) -> void:
	var sur := Color(1.07, 1.05, 1.0)
	for s in [-1.0, 1.0]:
		sw.block(Transform3D(fb, at + fb * Vector3(float(s) * (w * 0.5 + 0.25), h * 0.5, 0.18)), Vector3(0.5, h, 0.36), sur)
	sw.block(Transform3D(fb, at + fb * Vector3(0.0, h + 0.25, 0.2)), Vector3(w + 1.1, 0.5, 0.4), sur)
	if open:
		d.masonry.block(dark, Transform3D(fb, at + fb * Vector3(0.0, h * 0.5, 0.02)), Vector3(w, h, 0.04))
	else:
		# walled up with whatever was to hand, in courses that do not match the face, a little proud of it
		var rows := int(h / 0.38)
		for r in rows:
			var y := 0.19 + 0.38 * float(r)
			var off := 0.0 if r % 2 == 0 else 0.22
			var n := int(w / 0.44)
			for c in n:
				var x := -w * 0.5 + 0.22 + 0.44 * float(c) + off
				if x > w * 0.5 - 0.1:
					continue
				var v := d.kit.rng.randf_range(0.78, 0.92)
				sw.block(Transform3D(fb, at + fb * Vector3(x, y, 0.08)), Vector3(0.42, 0.36, 0.16), Color(v, v * 0.98, v * 0.94))


## Ghorrow: the eighth hold. A crag of the Wall's limestone stood up in a horseshoe at the lip of the drop,
## dressed on its inner faces into a court, and round the court eight doors: seven walled up in rough
## stone, the eighth open, with steps going down into the dark. Over the way into the court the panel
## where a hold's clan-mark is cut, smoothed and left blank. Bones in the court's corners; the thralls
## that keep the open door stand in front of it.
static func ghorrow(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lip := k.downhill()
	if lip == Vector2.ZERO:
		lip = k.grain()
	var face := -lip                     # the court opens away from the drop, toward the moor
	var side := Vector2(face.y, -face.x)
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(face))
	var c := lip * 3.0
	var g := k.on_ground(c.x, c.y).y
	var low := INF
	for p in [c + side * 8.0, c - side * 8.0, c + lip * 7.0, c - lip * 6.0]:
		low = minf(low, k.on_ground((p as Vector2).x, (p as Vector2).y).y)
	var sw: Variant = _sites().Stones.new(k, d.poi_id.hash() + 3)
	var top := g + 6.5
	sw.top = top
	# the horseshoe: a back mass and two arms, rough outside, dressed in; the court 11 x 9 inside them
	var hw := 5.5
	var hd := 4.5
	var masses := [[c + lip * (hd + 2.5), Vector2(hw * 2.0 + 6.0, 5.0)], [c + side * (hw + 1.8), Vector2(3.6, hd * 2.0 + 1.0)],
			[c - side * (hw + 1.8), Vector2(3.6, hd * 2.0 + 1.0)]]
	for q in masses:
		var mc: Vector2 = q[0]
		var size: Vector2 = q[1]
		var rb := fb
		var xf := Transform3D(rb, Vector3(mc.x, (low - 1.2 + top) * 0.5, mc.y))
		sw.block(xf, Vector3(size.x, top - low + 1.2, size.y))
		k.collider(Vector3(size.x, top - low + 1.2, size.y), xf, "stone")
		# its outside broken up into rough lumps, so it reads as crag, not wall
		for i in 7:
			var lo := Vector3(k.rng.randf_range(-0.5, 0.5) * size.x, k.rng.randf_range(-0.2, 0.45) * (top - g), k.rng.randf_range(-0.5, 0.5) * size.y)
			var lsz := Vector3(k.rng.randf_range(1.4, 2.6), k.rng.randf_range(1.2, 2.4), k.rng.randf_range(1.4, 2.6))
			sw.block(Transform3D(rb * Basis(Vector3.UP, k.rng.randf_range(-0.4, 0.4)), Vector3(mc.x, (low + top) * 0.5, mc.y) + rb * lo), lsz,
					Color(0.9, 0.89, 0.86))
	await k.step()
	# the eight doors: four in the back face, two in each arm's inner face
	var dark := m.begin()
	var doors: Array = []
	for i in 4:
		doors.append([c + lip * hd + side * (-3.9 + 2.6 * float(i)), fb])
	for s in [-1.0, 1.0]:
		for i in 2:
			var at: Vector2 = c + side * (hw * float(s)) + lip * (1.8 - 3.6 * float(i))
			doors.append([at, fb * Basis(Vector3.UP, -PI * 0.5 * float(s))])
	var open_i := 2
	for i in doors.size():
		var dp: Vector2 = doors[i][0]
		var db: Basis = doors[i][1]
		_cut_door(d, sw, dark, Vector3(dp.x, g, dp.y), db, 1.3, 2.2, i == open_i)
	# over the way in, the clan panel smoothed blank, and the court's floor of worn flags
	var gate := c - lip * hd
	for s in [-1.0, 1.0]:
		sw.block(Transform3D(fb, Vector3(gate.x, g + 2.9, gate.y) + fb * Vector3(float(s) * (hw + 0.4), 0.0, 0.0)), Vector3(1.2, 5.8, 1.6))
	sw.block(Transform3D(fb, Vector3(gate.x, g + 5.6, gate.y)), Vector3(hw * 2.0 + 2.0, 1.4, 1.4))
	sw.block(Transform3D(fb, Vector3(gate.x, g + 5.6, gate.y) + fb * Vector3(0.0, 0.0, 0.72)), Vector3(2.4, 1.0, 0.06), Color(1.15, 1.13, 1.08))
	k.collider(Vector3(hw * 2.0 + 2.0, 1.4, 1.4), Transform3D(fb, Vector3(gate.x, g + 5.6, gate.y)), "stone")
	_sites()._commit(d, sw, null, "Ghorrow", true)
	var crag := k.rock("cliff_face")
	if crag != "":
		var spots: Array = [c + lip * (hd + 5.6) + side * 4.0, c + lip * (hd + 5.4) - side * 4.5, c + side * (hw + 4.4) + lip * 2.0,
				c - side * (hw + 4.4) + lip * 1.0, c + side * (hw + 4.0) - lip * 3.5, c - side * (hw + 4.0) - lip * 3.0]
		for i in spots.size():
			var p: Vector2 = spots[i]
			var out_dir := (p - c).normalized()
			var rp := k.rock("cliff_face", i % 3)
			var sc := clampf(6.5 / maxf(PoiKit.height_of(rp), 0.5), 0.2, 1.5) * k.rng.randf_range(0.8, 1.0)
			await k.step()
			k.place(rp, k.on_ground(p.x, p.y, -0.8), PoiKit.yaw_of(out_dir) + k.rng.randf_range(-0.3, 0.3), sc, true, Vector3.ZERO, true)
	if k.far:
		return
	# the open door's steps going down into the dark, cut back into the back mass
	var od: Vector2 = doors[open_i][0]
	var into := lip
	for q in 4:
		m.block(dark, Transform3D(fb, Vector3(od.x, g - 0.2 - 0.32 * float(q), od.y) + Vector3(into.x, 0.0, into.y) * (0.5 + 0.55 * float(q))), Vector3(1.25, 0.1, 0.5))
	m.commit(dark, PoiKit.plain(DARK, 0.95), "TheDark")
	var flags := m.begin()
	for i in 6:
		for j in 5:
			var p := c + side * (-hw + 0.9 + 1.85 * float(i)) + lip * (-hd + 0.9 + 1.8 * float(j)) + k.jitter(0.12)
			if k.rng.randf() < 0.12:
				continue
			m.block(flags, Transform3D(fb * Basis(Vector3.UP, k.rng.randf_range(-0.08, 0.08)), k.on_ground(p.x, p.y, -0.08)), Vector3(1.7, 0.2, 1.65))
	await k.step()
	m.commit(flags, _sites().stone_look(k, g), "CourtFlags")
	k.touchable("OpenDoor", Vector3(od.x, g + 1.2, od.y) - Vector3(into.x, 0.0, into.y) * 0.6, "Look down the open door", DIALOGUE + "ghorrow_open_door", "", false)
	k.touchable("BlankPanel", Vector3(gate.x, g + 1.4, gate.y) - Vector3(lip.x, 0.0, lip.y) * 1.2, "Look up at the panel over the way in", DIALOGUE + "ghorrow_blank_panel", "", false)
	k.marker("the_open_door", k.on_ground(od.x - into.x * 2.6, od.y - into.y * 2.6))
	# bones swept into the court's corners
	var bones := k.rock("bone_vertebra", 0)
	if bones != "":
		var heap: Array = []
		for s in [-1.0, 1.0]:
			var corner := c + side * (hw - 1.0) * float(s) + lip * (hd - 1.0)
			for i in 3:
				var p := corner + k.jitter(0.6)
				heap.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.05), k.rng.randf() * TAU, k.rng.randf_range(0.18, 0.26)))
		await k.step()
		k.scatter(bones, heap, false)


## The Briar's End: where the Thornmarch's briar gives out against the fell. The thicket comes up the
## slope and stops in a ragged edge; across the gap it leaves, a wall of a giant's bones, ribs and
## vertebrae and long bones stacked and lashed with hide between two of the fell's boulders. One run
## of it has been pushed outward from this side in the night: the bones lie tumbled out on the far
## side, the lashings snapped. The Skarl keepers' cairn and their bell at the near end.
static func briars_end(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var along := k.grain()
	var across := Vector2(along.y, -along.x)
	var out := across                      # the side the wall faces, toward the briar
	# the briar: low dark thorny mounds coming up to the gap on the out side and thinning to nothing
	var thorn := m.begin()
	for i in 46:
		var p := out * k.rng.randf_range(5.0, 19.0) + along * k.rng.randf_range(-17.0, 17.0)
		if absf(p.dot(along)) < 7.0 and p.dot(out) < 11.0:
			continue     # the gap itself is bare
		var r := k.rng.randf_range(1.6, 3.0)
		m.ellipsoid(thorn, k.on_ground(p.x, p.y, -0.35), Vector3(r, k.rng.randf_range(0.6, 1.0), r * 0.85), Basis(Vector3.UP, k.rng.randf() * TAU))
	await k.step()
	m.commit(thorn, PoiKit.painted(5, {"base": "#1f2815", "accent": "#3a2419", "grout": "#10150b", "unit": 0.15}, 0.9, 0.9), "Briar", true)
	var briar_mi := d.find_child("Briar", false, false) as MeshInstance3D
	if briar_mi != null:
		briar_mi.material_override = PoiKit.plain(Color(0.11, 0.14, 0.07), 0.95)
	var vine := k.flora("briar_vine")
	if vine != "" and not k.far:
		var vines: Array = []
		for i in 70:
			var p := out * k.rng.randf_range(5.5, 18.0) + along * k.rng.randf_range(-16.0, 16.0)
			if absf(p.dot(along)) < 7.0 and p.dot(out) < 11.0:
				continue
			vines.append(PoiKit.transform_at(k.on_ground(p.x, p.y, 0.0), k.rng.randf() * TAU, k.rng.randf_range(2.0, 3.0)))
		await k.step()
		k.scatter(vine, vines, false)
	# the boulders at the wall's ends, and the wall of bones between them
	var rock := k.rock("boulder", 1)
	for s in [-1.0, 1.0]:
		if rock != "":
			await k.step()
			k.place(rock, k.on_ground(along.x * 8.2 * float(s), along.y * 8.2 * float(s), -0.5), k.rng.randf() * TAU, 1.5, true, Vector3.ZERO, true)
	var bone := m.begin()
	var hide := m.begin()
	var broken_from := 1.0
	var broken_to := 3.6
	for i in 14:
		var x := -6.5 + float(i)
		var pushed := x > broken_from and x < broken_to
		var p := along * x
		if pushed:
			# tumbled out on the far side, lying every way
			var q := p + out * k.rng.randf_range(1.6, 3.2)
			var lb := Basis(Vector3.UP, k.rng.randf() * TAU) * Basis(Vector3.BACK, PI * 0.5)
			m.limb(bone, k.on_ground(q.x, q.y, 0.25), k.on_ground(q.x, q.y, 0.25) + lb * Vector3(0.0, 1.6, 0.0), 0.2)
			continue
		var g := k.on_ground(p.x, p.y)
		# an upright long bone, a rib bowed across the top, and the stack of vertebrae between
		var lean := Vector3(out.x, 0.0, out.y) * k.rng.randf_range(-0.12, 0.08)
		_limb_solid(d, bone, g + Vector3.DOWN * 0.3, g + Vector3.UP * 2.5 + lean, 0.17, "stone")
		m.ellipsoid(bone, g + Vector3.UP * 2.55 + lean, Vector3(0.28, 0.22, 0.24))
		for y in [0.45, 1.15, 1.8]:
			m.ellipsoid(bone, g + Vector3.UP * float(y) + Vector3(along.x, 0.0, along.y) * 0.5, Vector3(0.36, 0.28, 0.32), Basis(Vector3.UP, k.rng.randf() * TAU))
		m.block(hide, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(along)), g + Vector3.UP * 2.0 + lean * 0.8), Vector3(0.06, 0.12, 1.05))
	k.collider(Vector3(0.6, 2.6, broken_from + 6.5), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(along)), k.on_ground(along.x * (broken_from - 6.5) * 0.5, along.y * (broken_from - 6.5) * 0.5, 1.3)), "stone")
	k.collider(Vector3(0.6, 2.6, 7.0 - broken_to), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(along)), k.on_ground(along.x * (broken_to + 7.0) * 0.5, along.y * (broken_to + 7.0) * 0.5, 1.3)), "stone")
	# the top rail: ribs laid along the wall's top where it still stands
	for seg in [[-6.5, broken_from], [broken_to, 7.0]]:
		var a := along * float(seg[0])
		var b := along * float(seg[1])
		m.limb(bone, k.on_ground(a.x, a.y, 2.45), k.on_ground(b.x, b.y, 2.45), 0.12)
	await k.step()
	m.commit(bone, PoiKit.painted(5, BONE, 0.75, 0.75), "BoneWall", true)
	m.commit(hide, PoiKit.plain(Color(0.35, 0.27, 0.2), 0.9), "Lashings")
	if k.far:
		return
	var gap := along * ((broken_from + broken_to) * 0.5)
	k.touchable("Pushed", k.on_ground(gap.x - out.x * 0.8, gap.y - out.y * 0.8, 1.0), "Look at where the wall was pushed out", DIALOGUE + "briars_end_pushed", "", false)
	# the keepers' cairn at the near end, a bell on a crook over it
	var st := m.begin()
	var cp := along * -9.5 - out * 3.0
	_cairn(d, st, cp, 0.8, 1.6)
	await k.step()
	m.commit(st, k.surface("stone", 0.85), "KeepersCairn")
	var crook := m.begin()
	var top2 := m.post(crook, cp - out * 1.2, 2.3, 0.08)
	m.block(crook, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(out)), top2 + Vector3(out.x, 0.0, out.y) * 0.35), Vector3(0.07, 0.07, 0.8))
	m.commit(crook, k.surface("timber", 0.9), "BellCrook")
	await _prop(d, "bell_small", Vector2(top2.x, top2.z) + out * 0.65, 0.0, 1.0, top2.y - k.on_ground(top2.x + out.x * 0.65, top2.z + out.y * 0.65).y - 0.42)
	k.marker("the_gap", k.on_ground(gap.x + out.x * 4.0, gap.y + out.y * 4.0))


## A seat of stone: a slab to sit on on two blocks, and a back of one standing slab, facing `toward`.
## Into `st`, with a box. Returns the seat's top middle (local).
static func _stone_seat(d: PoiDressing, st: SurfaceTool, at: Vector2, toward: Vector2, w := 1.3, back_h := 1.5) -> Vector3:
	var k := d.kit
	var g := k.on_ground(at.x, at.y)
	var b := Basis(Vector3.UP, PoiKit.yaw_of(toward))
	for s in [-1.0, 1.0]:
		d.masonry.block(st, Transform3D(b, g + b * Vector3(float(s) * (w * 0.5 - 0.2), 0.2, 0.0)), Vector3(0.32, 0.65, 0.55))
	d.masonry.block(st, Transform3D(b, g + Vector3.UP * 0.5), Vector3(w, 0.16, 0.7))
	d.masonry.block(st, Transform3D(b * Basis(Vector3.RIGHT, -0.08), g + b * Vector3(0.0, back_h * 0.5 - 0.1, -0.42)), Vector3(w * 0.95, back_h, 0.24))
	k.collider(Vector3(w, 0.6, 0.7), Transform3D(b, g + Vector3.UP * 0.3), "stone")
	k.collider(Vector3(w, back_h, 0.3), Transform3D(b, g + b * Vector3(0.0, back_h * 0.5 - 0.1, -0.42)), "stone")
	return g + Vector3.UP * 0.6


## The Frost Moot: the Old Moot in its hollow under the Wall. A ring bank round a floor of trodden snow,
## eight seats of stone in it facing in (one more than there are clans), the speaking-stone in the
## middle, the clans' rope-post by it. Snow lies on every seat but one, swept clean this morning; the
## broom lies under it.
static func frost_moot(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var snow := PoiKit.painted(5, {"base": "#cfd4da", "accent": "#b7bdc5", "grout": "#99a0aa", "unit": 0.6}, 0.5, 0.5)
	# the bank of the hollow: turf and snow, round the floor
	var bank := m.begin()
	var drift := m.begin()
	var R := 12.5
	for i in 26:
		var a := TAU * float(i) / 26.0
		if i % 9 == 4:
			continue      # the bank broken where the ways in came over it
		var p := Vector2(sin(a), cos(a)) * (R + k.rng.randf_range(-0.6, 1.4))
		var hh := k.rng.randf_range(0.5, 0.95)
		m.ellipsoid(bank, k.on_ground(p.x, p.y, -0.3), Vector3(k.rng.randf_range(1.8, 2.6), hh, k.rng.randf_range(3.2, 4.2)), Basis(Vector3.UP, a + PI * 0.5 + k.rng.randf_range(-0.2, 0.2)))
		if k.rng.randf() < 0.55:
			m.ellipsoid(drift, k.on_ground(p.x, p.y, hh * 0.55 - 0.25) - Vector3(sin(a), 0.0, cos(a)) * 0.6, Vector3(1.3, 0.3, 0.9), Basis(Vector3.UP, a))
	await k.step()
	m.commit(bank, PoiKit.plain(Color(0.25, 0.27, 0.18), 0.95), "TurfBank", true)
	m.commit(drift, snow, "SnowInTheBank", true)
	var floor_st := m.begin()
	var ring: Array = []
	for i in 33:
		var a := TAU * float(i) / 32.0
		ring.append(Vector2(sin(a), cos(a)) * 6.5)
	_track(d, floor_st, ring, 3.2)
	m.commit(floor_st, snow, "TroddenSnow")
	# the eight seats
	var seats := m.begin()
	var tops: Array[Vector3] = []
	var swept := k.rng.randi() % 8
	var start := k.rng.randf() * TAU
	for i in 8:
		var a := start + TAU * float(i) / 8.0
		var p := Vector2(sin(a), cos(a)) * 9.0
		tops.append(_stone_seat(d, seats, p, -p.normalized(), 1.4, 1.7 + 0.25 * float(i % 2)))
	await k.step()
	m.commit(seats, _sites().stone_look(k, k.on_ground(0.0, 0.0).y), "Seats", true)
	if k.far:
		return
	var drifts := m.begin()
	for i in 8:
		if i == swept:
			continue
		var t: Vector3 = tops[i]
		m.ellipsoid(drifts, t + Vector3.UP * 0.02, Vector3(0.62, 0.12, 0.34), Basis(Vector3.UP, k.rng.randf() * TAU))
	m.commit(drifts, snow, "SnowOnSeats")
	# the speaking-stone and the rope-post
	var stone := k.rock("standing_stone", 0)
	if stone != "":
		await k.step()
		k.place(stone, k.on_ground(0.0, 0.0, -0.2), start, 0.55, true)
	var post := m.begin()
	var pt := m.post(post, Vector2(1.6, 0.4), 1.6, 0.12)
	m.commit(post, k.surface("timber", 0.9), "RopePost")
	var rope := m.begin()
	m.limb(rope, pt + Vector3.DOWN * 0.1, pt + Vector3(0.0, -1.4, 0.0) + Vector3(0.18, 0.0, 0.1), 0.025)
	m.commit(rope, PoiKit.plain(Color(0.5, 0.42, 0.3), 0.9), "Rope")
	# the broom left under the swept seat
	var sw_top: Vector3 = tops[swept]
	var toward := -Vector2(sw_top.x, sw_top.z).normalized()
	var timber := m.begin()
	var heather := m.begin()
	_broom(d, timber, heather, Vector2(sw_top.x, sw_top.z) + toward * 0.7 + Vector2(toward.y, -toward.x) * 0.9, -toward, 1.35)
	m.commit(timber, k.surface("timber", 0.8), "BroomShaft")
	m.commit(heather, PoiKit.painted(5, HEATHER, 0.7), "BroomHead")
	k.touchable("SweptSeat", sw_top + Vector3.UP * 0.3, "Look at the swept seat", DIALOGUE + "frost_moot_swept_seat", "", false)


## The Oskel Rake: the lead-miners' trench cut along the dale-side, two banks of grey spoil either side of
## a dark cut running along the grain out past the pad, the winding-stone at its head with its rope
## groove worn deep. The far end of the cut is opened fresh: pale broken rock, the vein's lead showing
## blue-grey, and the picks lying where they were dropped at dawn.
static func oskel_rake(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var along := k.grain()
	var across := Vector2(along.y, -along.x)
	var L := 21.0
	var spoil := m.begin()
	for s in [-1.0, 1.0]:
		_tip(d, spoil, -along * L + across * 3.3 * float(s), along, L * 2.0, 4.4, 1.2)
	var cut := m.begin()
	for i in 14:
		var t := -L + float(i) * (L * 2.0 / 13.0)
		var p := along * t
		m.block(cut, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(along)), k.on_ground(p.x, p.y, 0.02)), Vector3(2.3, 0.04, L * 2.0 / 13.0 + 0.1))
	await k.step()
	_ground_mesh(d, spoil, PoiKit.painted(5, DEAD_SPOIL, 0.85, 0.9), "RakeBanks", true)
	m.commit(cut, PoiKit.plain(Color(0.12, 0.11, 0.1), 0.95), "TheCut", true)
	if k.far:
		return
	var scree := k.rock("scree")
	if scree != "":
		var lumps: Array = []
		for i in 26:
			var p := along * k.rng.randf_range(-L, L) + across * (k.rng.randf_range(2.2, 5.0) * (1.0 if i % 2 == 0 else -1.0))
			lumps.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.05), k.rng.randf() * TAU, k.rng.randf_range(0.15, 0.32)))
		await k.step()
		k.scatter(scree, lumps, false)
	# the winding-stone at the head: a squat pillar, its groove, and the rope's last turn
	var head := -along * (L + 2.5)
	var st := m.begin()
	var hg := k.on_ground(head.x, head.y)
	var hb := Basis(Vector3.UP, PoiKit.yaw_of(along))
	m.block(st, Transform3D(hb, hg + Vector3.UP * 0.7), Vector3(1.1, 1.8, 1.1))
	m.block(st, Transform3D(hb, hg + Vector3.UP * 1.7), Vector3(1.25, 0.25, 1.25))
	k.collider(Vector3(1.1, 1.8, 1.1), Transform3D(hb, hg + Vector3.UP * 0.7), "stone")
	m.commit(st, _sites().stone_look(k, hg.y), "WindingStone")
	var groove := m.begin()
	m.block(groove, Transform3D(hb, hg + Vector3.UP * 1.2), Vector3(1.13, 0.1, 1.13))
	m.commit(groove, PoiKit.plain(Color(0.2, 0.19, 0.17), 0.9), "RopeGroove")
	k.touchable("WindingStone", hg + Vector3.UP * 1.2 - Vector3(along.x, 0.0, along.y) * 0.7, "Look at the winding-stone", DIALOGUE + "oskel_rake_winding_stone", "", false)
	# the fresh end: pale broken rock and the lead showing in it, the picks
	var end := along * (L - 2.0)
	var fresh := m.begin()
	_heap(d, fresh, end + across * 0.6, 1.3, 0.55, 5)
	m.commit(fresh, PoiKit.painted(5, LIME, 0.6, 0.8), "FreshRock")
	var lead := m.begin()
	for i in 6:
		var p := end + k.jitter(1.0)
		m.block(lead, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.3, 0.3)), k.on_ground(p.x, p.y, 0.12)),
				Vector3(k.rng.randf_range(0.2, 0.4), 0.12, k.rng.randf_range(0.15, 0.3)))
	m.commit(lead, PoiKit.plain(Color(0.36, 0.39, 0.44), 0.35, 0.7), "Galena")
	for i in 2:
		await _prop(d, "pitchfork" if i == 0 else "hammer", end - along * 1.6 + across * (0.8 - 1.6 * float(i)), k.rng.randf() * TAU)
	k.marker("the_fresh_end", k.on_ground(end.x - along.x * 3.0, end.y - along.y * 3.0))


## The Deadground: grey spoil below Oskeld, tipped for two hundred years until nothing grew. Grey tongues
## of it over the ground; two ore-sheds with their roofs fallen in; a barrow and a cart left to rust;
## goats' skulls; and across all of it, a single line of green grass a hand wide, running straight
## toward the mine.
static func deadground(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var to_mine := Vector2(OSKELD.x - k.origin.x, OSKELD.y - k.origin.z).normalized()
	var across := Vector2(to_mine.y, -to_mine.x)
	var tips := m.begin()
	# the grey over everything: the waste spread thin across the ground where nothing has grown
	_tip(d, tips, -to_mine * 17.0, to_mine, 34.0, 30.0, 0.12)
	_tip(d, tips, -to_mine * 7.0 + across * 5.0, (-to_mine * 0.6 + across * 0.4).normalized(), 13.0, 7.0, 2.2)
	_tip(d, tips, -to_mine * 2.0 - across * 8.0, (-to_mine * 0.5 - across * 0.5).normalized(), 12.0, 6.0, 1.8)
	_tip(d, tips, to_mine * 8.0 + across * 3.0, (to_mine * 0.2 + across).normalized(), 10.0, 5.5, 1.5)
	await k.step()
	_ground_mesh(d, tips, PoiKit.painted(5, DEAD_SPOIL, 0.9, 0.9), "GreySpoil", true)
	# the sheds: four walls each, no roof, the door gaps toward the line
	var walls := m.begin()
	for q in [[across * -10.0 + to_mine * 6.0, 6.0, 4.5], [across * 10.0 - to_mine * 8.0, 5.0, 4.0]]:
		var c: Vector2 = q[0]
		var w := float(q[1]) * 0.5
		var dp := float(q[2]) * 0.5
		var a := c + across * w + to_mine * dp
		var b := c - across * w + to_mine * dp
		var e := c - across * w - to_mine * dp
		var f := c + across * w - to_mine * dp
		m.wall(walls, a, b, 2.1, 0.4)
		m.wall(walls, b, e, 2.3, 0.2)
		m.wall(walls, e, c - to_mine * dp - across * 0.6, 1.8, 0.3)
		m.wall(walls, c - to_mine * dp + across * 0.6, f, 1.9, 0.3)
		m.wall(walls, f, a, 2.2, 0.5)
	await k.step()
	m.commit(walls, k.surface("stone", 0.9), "OreSheds", true)
	if k.far:
		return
	await _prop(d, "wheelbarrow", across * -7.0 + to_mine * 2.0, PoiKit.yaw_of(across) + 0.4)
	await _prop(d, "cart", across * 7.0 - to_mine * 3.5, PoiKit.yaw_of(to_mine) + 0.7)
	var skull := k.rock("bone_skull_fragment", 1)
	if skull != "":
		var skulls: Array = []
		for i in 4:
			var p := k.jitter(13.0)
			skulls.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.02), k.rng.randf() * TAU, k.rng.randf_range(0.08, 0.12)))
		await k.step()
		k.scatter(skull, skulls, false)
	# the line of grass, straight across the grey toward Oskeld
	var grass := k.flora("grass_clump")
	if grass == "":
		grass = k.flora("grass")
	var strip := m.begin()
	_track(d, strip, [to_mine * -18.0, to_mine * 18.0], 0.55)
	m.commit(strip, PoiKit.painted(5, {"base": "#55703a", "accent": "#41582c", "grout": "#2b3a1d", "unit": 0.2}, 0.6, 0.8), "GrassLine")
	if grass != "":
		var line: Array = []
		for i in 28:
			var t := -17.0 + 1.25 * float(i)
			var p := to_mine * t + across * k.rng.randf_range(-0.12, 0.12)
			line.append(PoiKit.transform_at(k.on_ground(p.x, p.y, 0.0), k.rng.randf() * TAU, k.rng.randf_range(0.7, 0.95)))
		await k.step()
		k.scatter(grass, line, false)
	k.touchable("GrassLine", k.on_ground(to_mine.x * 4.0, to_mine.y * 4.0, 0.4), "Look at the line of grass", DIALOGUE + "deadground_grass_line", "", false)

## Where Oskeld Mine's mouth is (core:place/oskeld_mine), for the Deadground's line of grass.
const OSKELD := Vector2(-2680.0, -3100.0)


## Old Eld: the first silver working on Brindle Edge. A low collar of drystone round the shaft, and laid
## over it for a door a giant's shoulder-blade, a great fan of bone gone yellow, pinned at its corners
## with iron. The heat comes up round its edge: the snow does not lie there, and on a cold morning it
## smokes. A spoil heap of pale silver-rock glinting, a broken windlass, and the thrall's tracks.
static func old_eld(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var up := k.uphill()
	if up == Vector2.ZERO:
		up = k.grain()
	var side := Vector2(up.y, -up.x)
	var c := Vector2.ZERO
	var g := k.on_ground(c.x, c.y)
	var coll := m.begin()
	for i in 12:
		var a := TAU * float(i) / 12.0
		var p := c + Vector2(sin(a), cos(a)) * 2.3
		m.ellipsoid(coll, k.on_ground(p.x, p.y, 0.2), Vector3(0.75, 0.45, 0.55), Basis(Vector3.UP, a))
	k.collider(Vector3(5.2, 0.7, 5.2), Transform3D(Basis.IDENTITY, g + Vector3.UP * 0.2), "stone")
	await k.step()
	m.commit(coll, k.surface("stone", 0.85), "Collar", true)
	# the shoulder-blade: a broad fan of bone, thick at its spine, lying over the collar
	var blade := m.begin()
	var bb := Basis(Vector3.UP, PoiKit.yaw_of(up))
	var top := g.y + 0.6
	for i in 7:
		var t := float(i) / 6.0
		var w := lerpf(1.2, 4.4, t)
		var z := lerpf(-2.2, 2.0, t)
		m.block(blade, Transform3D(bb * Basis(Vector3.RIGHT, 0.05), Vector3(g.x, top + 0.14 - 0.05 * t, g.z) + bb * Vector3(0.0, 0.0, z)), Vector3(w, 0.2, 0.75))
	m.limb(blade, Vector3(g.x, top + 0.3, g.z) + bb * Vector3(0.0, 0.0, -2.3), Vector3(g.x, top + 0.25, g.z) + bb * Vector3(0.0, 0.0, 1.6), 0.22)
	m.ellipsoid(blade, Vector3(g.x, top + 0.3, g.z) + bb * Vector3(0.0, 0.0, -2.5), Vector3(0.6, 0.45, 0.55))
	k.collider(Vector3(4.0, 0.4, 4.6), Transform3D(bb, Vector3(g.x, top + 0.1, g.z)), "stone")
	await k.step()
	m.commit(blade, PoiKit.painted(5, {"base": "#cdbf98", "accent": "#a8986e", "grout": "#6d6145", "unit": 0.5}, 0.7, 0.7), "ShoulderBlade", true)
	if k.far:
		return
	var iron := m.begin()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.block(iron, Transform3D(bb, Vector3(g.x, top + 0.2, g.z) + bb * Vector3(float(sx) * 1.6, 0.0, float(sz) * 1.4)), Vector3(0.12, 0.6, 0.12))
	m.commit(iron, PoiKit.plain(IRON, 0.6, 0.5), "Pins")
	k.puffs(Vector3(g.x, top + 0.3, g.z), Vector3(2.0, 0.1, 2.0), 1.6, 8, Color(0.85, 0.85, 0.85, 0.22), 1.4, 4.0)
	k.touchable("BoneDoor", Vector3(g.x, top + 0.5, g.z) - Vector3(up.x, 0.0, up.y) * 1.8, "Lay a hand on the bone door", DIALOGUE + "old_eld_bone_door", "", false)
	# the spoil, pale with the silver-rock's glitter, and the windlass that fell
	var tips := m.begin()
	_tip(d, tips, -up * 5.0 + side * 3.0, (-up + side * 0.3).normalized(), 13.0, 5.0, 1.6)
	await k.step()
	_ground_mesh(d, tips, PoiKit.painted(5, {"base": "#6f6d68", "accent": "#8f8d87", "grout": "#45433f", "unit": 0.5}, 0.4, 0.9), "SilverSpoil")
	var wind := m.begin()
	for s in [-1.0, 1.0]:
		m.post(wind, side * 3.4 * float(s) + up * 0.6, 1.4 if s < 0.0 else 0.7, 0.16)
	var lying := k.on_ground(side.x * 1.5 + up.x * 3.2, side.y * 1.5 + up.y * 3.2, 0.15)
	m.rod(wind, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(up) + 0.4) * Basis(Vector3.RIGHT, PI * 0.5), lying), 0.18, 2.6)
	k.collider(Vector3(0.36, 0.36, 2.6), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(up) + 0.4), lying), "wood")
	m.commit(wind, k.surface("timber", 0.9), "Windlass")
	k.marker("the_working", k.on_ground(-up.x * 8.0, -up.y * 8.0))


## The Leadhouse: the Salt Isles traders' lead store above the Oskel shore, a long house of grey stone
## standing to its wall-heads with no roof, its gable ends up, the lead-dust grey on everything. Over
## its seaward door the Salt Isles tide-mark painted in blue, a wave over a line. Inside, the clanless
## out of the west wind at a fire, and pigs of lead still stacked against the wall where the last boat
## never came for them; the broom-heather growing thick round the walls' feet.
static func the_leadhouse(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(500.0)
	if sea == Vector2.ZERO:
		sea = Vector2(-1.0, 0.0)
	var along := Vector2(sea.y, -sea.x)
	var w := 6.5
	var l := 14.0
	var hb := Basis(Vector3.UP, PoiKit.yaw_of(sea))
	var c0 := -along * (l * 0.5)
	var c1 := along * (l * 0.5)
	var walls := m.begin()
	var sea_side_a := c0 + sea * (w * 0.5)
	var sea_side_b := c1 + sea * (w * 0.5)
	var land_a := c0 - sea * (w * 0.5)
	var land_b := c1 - sea * (w * 0.5)
	m.wall(walls, land_a, land_b, 3.2, 0.12)
	m.wall(walls, sea_side_a, sea_side_a.lerp(sea_side_b, 0.42), 3.2, 0.0)
	m.wall(walls, sea_side_a.lerp(sea_side_b, 0.58), sea_side_b, 3.2, 0.15)
	# the gables, standing to their points
	for e in [[land_a, sea_side_a], [land_b, sea_side_b]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		m.wall(walls, a, b, 3.2, 0.0)
		var mid := (a + b) * 0.5
		var mg := k.on_ground(mid.x, mid.y)
		for q in 4:
			var ww := w * (1.0 - 0.24 * float(q + 1))
			m.block(walls, Transform3D(hb, mg + Vector3.UP * (3.4 + 0.5 * float(q))), Vector3(ww, 0.5, 0.55))
	await k.step()
	m.commit(walls, PoiKit.painted(2, {"base": "#8e8c88", "accent": "#77756f", "grout": "#4a4845", "unit": 0.42}, 0.85, 0.7), "LeadHouse", true)
	if k.far:
		return
	# the door on the sea side, and the tide-mark over it
	var door := sea_side_a.lerp(sea_side_b, 0.5)
	var dg := k.on_ground(door.x, door.y)
	var stone := m.begin()
	m.doorway(stone, door, PoiKit.yaw_of(sea), 1.6, 2.4)
	m.commit(stone, k.surface("stone", 0.8), "DoorStones")
	var paint := m.begin()
	var mark := dg + Vector3.UP * 3.0 + Vector3(sea.x, 0.0, sea.y) * 0.31
	for i in 7:
		var x := -0.9 + 0.3 * float(i)
		m.block(paint, Transform3D(hb * Basis(Vector3.BACK, 0.45 if i % 2 == 0 else -0.45), mark + hb * Vector3(x, 0.12, 0.0)), Vector3(0.34, 0.07, 0.02))
	m.block(paint, Transform3D(hb, mark + hb * Vector3(0.0, -0.12, 0.0)), Vector3(2.0, 0.07, 0.02))
	m.commit(paint, PoiKit.plain(Color(0.2, 0.36, 0.55), 0.9), "TideMark")
	k.touchable("TideMark", dg + Vector3.UP * 1.6 + Vector3(sea.x, 0.0, sea.y) * 1.2, "Look at the mark over the door", DIALOGUE + "leadhouse_tide_mark", "", false)
	# the pigs of lead stacked on the landward wall, the dust grey round them
	var pigs := m.begin()
	var stack := -sea * (w * 0.5 - 0.8) + along * 3.5
	var sg := k.on_ground(stack.x, stack.y)
	for lay in 4:
		for i in 5 - lay:
			var o := hb * Vector3((float(i) - float(4 - lay) * 0.5) * 0.62, 0.12 + 0.21 * float(lay), 0.0)
			m.block(pigs, Transform3D(hb * Basis(Vector3.UP, 0.04 * float(i % 2)), sg + o), Vector3(0.55, 0.2, 0.26))
			m.block(pigs, Transform3D(hb * Basis(Vector3.UP, 0.04 * float(i % 2)), sg + o + hb * Vector3(0.0, 0.0, 0.32)), Vector3(0.55, 0.2, 0.26))
	k.collider(Vector3(3.2, 0.9, 0.7), Transform3D(hb, sg + Vector3.UP * 0.45 + hb * Vector3(0.0, 0.0, 0.16)), "stone")
	m.commit(pigs, PoiKit.plain(Color(0.33, 0.34, 0.36), 0.5, 0.6), "LeadPigs")
	# the clanless fire in the lee of the landward wall, their bedrolls, and the hearthstone
	var fire := -along * 3.0
	await _prop(d, "campfire", fire, 0.0)
	k.light(k.on_ground(fire.x, fire.y, 0.5), Color(1.0, 0.6, 0.3), 1.6, 9.0)
	for i in 3:
		await _prop(d, "bedroll", fire - sea * 1.8 + along * (-1.4 + 1.4 * float(i)), PoiKit.yaw_of(sea))
	var hs := m.begin()
	var hp := -along * (l * 0.5 - 1.4)
	m.block(hs, Transform3D(hb, k.on_ground(hp.x, hp.y, 0.05)), Vector3(1.6, 0.14, 1.0))
	m.commit(hs, _sites().stone_look(k, k.on_ground(hp.x, hp.y).y), "Hearthstone")
	k.marker("the_hearth", k.on_ground(hp.x + along.x * 1.2, hp.y + along.y * 1.2))
	# the broom-heather thick round the walls
	var heather := m.begin()
	for i in 26:
		var a := k.rng.randf() * TAU
		var p := Vector2(sin(a) * (l * 0.5 + 2.0), cos(a) * (w * 0.5 + 2.0))
		p = along * p.x + sea * p.y + k.jitter(1.2)
		if p.distance_to(door + sea * 1.5) < 2.2:
			continue
		m.ellipsoid(heather, k.on_ground(p.x, p.y, 0.1), Vector3(0.55, 0.32, 0.5), Basis(Vector3.UP, a))
	await k.step()
	m.commit(heather, PoiKit.painted(5, HEATHER, 0.8, 0.9), "BroomHeather")


## Ghastfoot: the Ghast clan's arch over the road at the mouth of their dale. Two piers of dressed stone
## either side of the carriageway and the arch between them, the clay skull set in its keystone
## where the old one was; the bench at its foot where travellers sat to ask leave.
static func ghastfoot(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var road := _road_at(k, 30.0)
	var at := Vector2.ZERO
	var run := k.grain()
	if not road.is_empty():
		at = road[0]
		run = road[1]
	var across := Vector2(run.y, -run.x)
	var span := 8.4
	var pier_h := 4.2
	var g := k.on_ground(at.x, at.y).y
	var ab := Basis(Vector3.UP, PoiKit.yaw_of(run))         # local x across the road
	var sw: Variant = _sites().Stones.new(k, d.poi_id.hash() + 9)
	sw.top = g + pier_h + span * 0.5 + 1.0
	for s in [-1.0, 1.0]:
		var p := at + across * ((span * 0.5 + 0.8) * float(s))
		var pg := k.on_ground(p.x, p.y).y
		var xf := Transform3D(ab, Vector3(p.x, (pg - 0.6 + g + pier_h) * 0.5, p.y))
		sw.block(xf, Vector3(1.6, g + pier_h - pg + 0.6, 1.8))
		k.collider(Vector3(1.6, g + pier_h - pg + 0.6, 1.8), xf, "stone")
		sw.block(Transform3D(ab, Vector3(p.x, g + pier_h + 0.1, p.y)), Vector3(1.9, 0.3, 2.0))
	# the voussoirs on a round arch, and the keystone standing proud
	var n := 13
	var r := span * 0.5 + 0.4
	var centre := Vector3(at.x, g + pier_h, at.y)
	for i in n:
		var a := PI * (float(i) + 0.5) / float(n)
		var p := centre + ab * Vector3(cos(a) * r, sin(a) * r, 0.0)
		var big := i == (n >> 1)
		sw.block(Transform3D(ab * Basis(Vector3.BACK, a - PI * 0.5), p), Vector3(0.75 if big else 0.62, 1.1 if big else 0.8, 1.9 if big else 1.7))
	for s in [-1.0, 1.0]:
		var sp := centre + ab * Vector3(float(s) * (span * 0.5 + 0.55), (r + 0.35) * 0.5, 0.0)
		sw.block(Transform3D(ab, sp), Vector3(1.9, r + 0.35, 1.7))
	sw.block(Transform3D(ab, centre + Vector3.UP * (r + 0.6)), Vector3(span + 3.0, 0.5, 1.9))
	_sites()._commit(d, sw, null, "GateArch", true)
	if k.far:
		return
	k.collider(Vector3(span + 3.0, 1.2, 1.9), Transform3D(ab, centre + Vector3.UP * (r + 0.45)), "stone")
	# the skull in the keystone, both faces
	var skull := m.begin()
	for s in [-1.0, 1.0]:
		var face := centre + Vector3.UP * r + ab * Vector3(0.0, 0.05, 0.98 * float(s))
		m.ellipsoid(skull, face, Vector3(0.24, 0.28, 0.16))
	m.commit(skull, PoiKit.painted(5, {"base": "#c9a688", "accent": "#a9805f", "grout": "#6b4a35", "unit": 0.2}, 0.6, 0.6), "ClaySkull")
	k.touchable("Keystone", centre + Vector3.UP * 0.6 + Vector3(run.x, 0.0, run.y) * 1.8, "Look up at the skull in the keystone", DIALOGUE + "ghastfoot_clay_skull", "", false)
	# the leave-bench at the pier's foot, off the road
	var bench_at := at + across * (span * 0.5 + 2.6) + run * 2.5
	await _prop(d, "bench", bench_at, PoiKit.yaw_of(-across))
	var st := m.begin()
	_cairn(d, st, at - across * (span * 0.5 + 2.4) - run * 2.0, 0.6, 1.2)
	m.commit(st, k.surface("stone", 0.85), "LeaveCairn")


## A standing stone of the region's at local xz, `h` metres out of the ground, turned and leaning; its
## look painted over with `look` when one is given. Returns the stone's node.
static func _stone(d: PoiDressing, p: Vector2, yaw: float, h: float, look: Material = null, tilt := Vector3.ZERO, variant := -1) -> Node3D:
	var k := d.kit
	var path := k.rock("standing_stone", variant)
	if path == "":
		return null
	var s := h / maxf(PoiKit.height_of(path), 0.3)
	await k.step()
	var n := k.place(path, k.on_ground(p.x, p.y, -0.15), yaw, s, true, tilt, true)
	if n != null and look != null:
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = look
	return n


## Brindle Swallow: where Brindle Beck drops out of the world. The water comes over a lip of clints into
## a black hole in the limestone ringed with the pavement's broken edges, spray rising out of it; three
## cairns stand round it, and from a stake leaning over the hole a bell hangs on a cord, for dropping.
static func brindle_swallow(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var inflow := k.water_direction(80.0)
	if inflow == Vector2.ZERO:
		inflow = k.uphill() if k.uphill() != Vector2.ZERO else k.grain()
	var side := Vector2(inflow.y, -inflow.x)
	var g := k.on_ground(0.0, 0.0)
	# the hole: black, and its rim of broken clints
	var hole := m.begin()
	m.ellipsoid(hole, g + Vector3.UP * 0.02, Vector3(2.4, 0.03, 1.9), Basis(Vector3.UP, PoiKit.yaw_of(inflow)))
	m.commit(hole, PoiKit.plain(DARK, 1.0), "Swallow", true)
	var rim := m.begin()
	for i in 16:
		var a := TAU * float(i) / 16.0 + k.rng.randf_range(-0.1, 0.1)
		var p := Vector2(sin(a) * 3.0, cos(a) * 2.5).rotated(-PoiKit.yaw_of(inflow))
		if p.dot(inflow) > 2.0:
			continue    # where the beck comes in
		var size := Vector3(k.rng.randf_range(1.0, 1.7), k.rng.randf_range(0.3, 0.55), k.rng.randf_range(0.8, 1.2))
		var xf := Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.2, 0.05)), k.on_ground(p.x, p.y, size.y * 0.3))
		m.block(rim, xf, size)
		k.collider(size, xf, "stone")
	await k.step()
	m.commit(rim, PoiKit.painted(0, LIME, 0.8, 0.8), "Clints", true)
	if k.far:
		return
	# the beck's last few metres, sliding over the lip
	var water := m.begin()
	for i in 6:
		var p := inflow * (2.4 + 1.2 * float(i))
		m.block(water, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(inflow)), k.on_ground(p.x, p.y, 0.06)), Vector3(1.1, 0.03, 1.3))
	m.commit(water, PoiKit.plain(Color(0.16, 0.22, 0.24), 0.08, 0.1), "BeckLip")
	k.puffs(g + Vector3.UP * 0.4, Vector3(1.6, 0.1, 1.2), 2.2, 10, Color(0.88, 0.9, 0.92, 0.25), 1.2, 3.0)
	# three cairns round it
	var st := m.begin()
	for i in 3:
		var a := PoiKit.yaw_of(inflow) + PI * 0.4 + TAU * float(i) / 3.0
		_cairn(d, st, Vector2(sin(a), cos(a)) * 7.5, 0.9, 2.2 + 0.3 * float(i))
	await k.step()
	m.commit(st, k.surface("stone", 0.8), "Cairns", true)
	# the stake leaning over the hole, and the bell on its cord
	var timber := m.begin()
	var foot := -inflow * 3.6 + side * 1.0
	var tip := m.post(timber, foot, 2.6, 0.09, Vector3(inflow.y * 0.35, 0.0, -inflow.x * 0.35))
	var hang := Vector3(tip.x, tip.y, tip.z) + Vector3(inflow.x, 0.0, inflow.y) * 1.6
	m.limb(timber, tip, hang, 0.05)
	m.commit(timber, k.surface("timber", 0.9), "BellStake")
	var cord := m.begin()
	m.limb(cord, hang, hang + Vector3.DOWN * 1.1, 0.012)
	m.commit(cord, PoiKit.plain(Color(0.5, 0.42, 0.3), 0.9), "Cord")
	var bell := k.prop("bell_small")
	if bell != "":
		await k.step()
		k.place(bell, hang + Vector3.DOWN * 1.35, 0.0, 0.8, false)
	k.touchable("Bell", hang + Vector3.DOWN * 1.1 - Vector3(inflow.x, 0.0, inflow.y) * 0.9, "Take hold of the bell's cord", DIALOGUE + "brindle_swallow_bell", "", false)


## Kharrow's Cairns: three memory-cairns above the gorge, each taller than a man and studded all over with
## flat name-stones, a pale slate wedged in for every Kharrow the mountain kept; the keeper's seat in front
## of them, and the trodden ring she walked singing.
static func kharrows_cairn(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var view := k.downhill()
	if view == Vector2.ZERO:
		view = k.grain()
	var side := Vector2(view.y, -view.x)
	var st := m.begin()
	var names := m.begin()
	for i in 3:
		var p := side * (-5.0 + 5.0 * float(i)) - view * 2.0
		var top := _cairn(d, st, p, 1.2, 2.6 + 0.4 * float(i % 2))
		var g := k.on_ground(p.x, p.y)
		for j in 26:
			var a := k.rng.randf() * TAU
			var y := k.rng.randf_range(0.3, top.y - g.y - 0.3)
			var rr := 1.2 * (1.0 - 0.6 * (y / (top.y - g.y))) + 0.05
			var q := Vector3(g.x, g.y + y, g.z) + Vector3(sin(a), 0.0, cos(a)) * rr
			m.block(names, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.2), q), Vector3(0.24, 0.16, 0.05))
	await k.step()
	m.commit(st, k.surface("stone", 0.8), "MemoryCairns", true)
	m.commit(names, PoiKit.painted(2, SLATE, 0.5, 0.6), "NameStones")
	if k.far:
		return
	var seats := m.begin()
	_stone_seat(d, seats, view * 4.5, -view, 1.2, 1.1)
	m.commit(seats, _sites().stone_look(k, k.on_ground(0.0, 0.0).y), "KeepersSeat")
	var ring := m.begin()
	var pts: Array = []
	for i in 25:
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(sin(a), cos(a)) * 7.5 - view * 2.0)
	_track(d, ring, pts, 1.0)
	m.commit(ring, k.surface("earth", 0.4), "SingingRing")
	k.touchable("Names", k.on_ground(view.x * 0.6 - view.x * 2.0, view.y * 0.6 - view.y * 2.0, 1.2), "Read the names on the cairns", DIALOGUE + "kharrows_cairn_names", "", false)
	_spot(d, "the_keepers_seat", view * 5.2)


## The Rope Cairn: a cairn on Brindle Edge taller than a man, a pole up its middle, and hung all over with
## children's ropes, short and shorter, undyed and red and blue, a hundred years of them; the newest at
## the top, and one knotted in a hitch nobody ties any more.
static func rope_cairn(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var st := m.begin()
	var top := _cairn(d, st, Vector2.ZERO, 1.8, 2.6)
	await k.step()
	m.commit(st, k.surface("stone", 0.85), "RopeCairn", true)
	var pole := m.begin()
	var pt := Vector3(top.x, top.y + 1.6, top.z)
	m.limb(pole, top + Vector3.DOWN * 0.6, pt, 0.07)
	m.block(pole, Transform3D(Basis.IDENTITY, pt + Vector3.DOWN * 0.15), Vector3(1.3, 0.06, 0.06))
	m.block(pole, Transform3D(Basis(Vector3.UP, PI * 0.5), pt + Vector3.DOWN * 0.15), Vector3(1.3, 0.06, 0.06))
	m.commit(pole, k.surface("timber", 0.9), "RopePole", true)
	if k.far:
		return
	var colours := [Color(0.56, 0.48, 0.36), Color(0.6, 0.2, 0.16), Color(0.22, 0.3, 0.5), Color(0.5, 0.45, 0.3)]
	var ropes: Array = []
	for c in colours:
		ropes.append(m.begin())
	var g := k.on_ground(0.0, 0.0)
	# ropes from the pole's arms down onto the stones, and more tied round the cairn in courses
	for i in 16:
		var a := TAU * float(i) / 16.0
		var from := pt + Vector3.DOWN * 0.15 + Vector3(sin(a), 0.0, cos(a)) * 0.6
		var to := Vector3(g.x, top.y - 0.6, g.z) + Vector3(sin(a), 0.0, cos(a)) * 0.9
		m.limb(ropes[i % 4], from, to, 0.022)
	for i in 40:
		var a := k.rng.randf() * TAU
		var y := k.rng.randf_range(0.3, top.y - g.y - 0.5)
		var rr := 1.8 * (1.0 - 0.6 * (y / (top.y - g.y))) + 0.08
		var q := Vector3(g.x, g.y + y, g.z) + Vector3(sin(a), 0.0, cos(a)) * rr
		var len_m := k.rng.randf_range(0.3, 0.9)
		m.limb(ropes[k.rng.randi() % 4], q, q + Vector3.DOWN * len_m + Vector3(sin(a), 0.0, cos(a)) * 0.08, 0.02)
	for i in 4:
		m.commit(ropes[i], PoiKit.plain(colours[i], 0.9), "Ropes%d" % i)
	var knot := m.begin()
	var kp := pt + Vector3.DOWN * 0.5 + Vector3(0.55, 0.0, 0.0)
	m.ellipsoid(knot, kp, Vector3(0.09, 0.12, 0.09))
	m.limb(knot, kp, kp + Vector3(0.05, -0.7, 0.04), 0.025)
	m.commit(knot, PoiKit.plain(Color(0.3, 0.26, 0.18), 0.9), "OldHitch")
	k.touchable("OldHitch", kp + Vector3.DOWN * 0.6, "Look at the knotted rope", DIALOGUE + "rope_cairn_hitch", "", false)


## The Blood-Price Stones: three squat stones by the North Road with their tops worn into grooves where
## blood-price is laid in coin, in public. Coin in one groove; the witnesses' bench across from them;
## the slate the price is chalked on.
static func blood_price_stones(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var road := _toward_road(k, 60.0)
	if road == Vector2.ZERO:
		road = k.grain()
	var along := Vector2(road.y, -road.x)
	var sw: Variant = _sites().Stones.new(k, d.poi_id.hash() + 2)
	var tops: Array[Vector3] = []
	for i in 3:
		var p := along * (-3.4 + 3.4 * float(i)) + road * k.rng.randf_range(-0.4, 0.4)
		var g := k.on_ground(p.x, p.y)
		var h := 1.05 + 0.15 * float(i % 2)
		var b := Basis(Vector3.UP, PoiKit.yaw_of(road) + k.rng.randf_range(-0.15, 0.15))
		sw.top = g.y + h
		# the stone in two halves with the groove between them, worn smooth
		for s in [-1.0, 1.0]:
			sw.block(Transform3D(b, g + b * Vector3(float(s) * 0.36, (h - 0.5) * 0.5, 0.0)), Vector3(0.6, h + 0.5, 0.9))
		sw.block(Transform3D(b, g + Vector3.UP * (h - 0.28 - 0.25)), Vector3(0.14, h - 0.06, 0.9))
		k.collider(Vector3(1.32, h, 0.9), Transform3D(b, g + Vector3.UP * (h * 0.5)), "stone")
		tops.append(g + Vector3.UP * (h - 0.28))
	_sites()._commit(d, sw, null, "PriceStones", true)
	if k.far:
		return
	var coin := m.begin()
	var t: Vector3 = tops[1]
	for i in 9:
		m.rod(coin, Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, 0.0), t + Vector3(k.rng.randf_range(-0.03, 0.03), 0.0, -0.35 + 0.085 * float(i))), 0.07, 0.015)
	m.commit(coin, PoiKit.plain(Color(0.72, 0.58, 0.3), 0.35, 0.8), "Coin")
	k.touchable("Grooves", t + Vector3.UP * 0.25 - Vector3(road.x, 0.0, road.y) * 0.8, "Look at the coin in the grooves", DIALOGUE + "blood_price_grooves", "", false)
	await _prop(d, "bench", -road * 4.0, PoiKit.yaw_of(road))
	var slate := m.begin()
	var sp := along * 5.2
	var stop := m.post(slate, sp, 1.3, 0.12)
	m.commit(slate, k.surface("timber", 0.9), "SlatePost")
	var sl := m.begin()
	m.block(sl, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(-road)), stop + Vector3.DOWN * 0.3 - Vector3(road.x, 0.0, road.y) * 0.08), Vector3(0.5, 0.4, 0.03))
	m.commit(sl, PoiKit.painted(2, SLATE, 0.4, 0.5), "PriceSlate")


## The Clan Stones: seven painted stones in an arc on the fellside, each its clan's colour from the
## ground to the shoulder, renewed every midsummer, and the eighth socket: a ring of packing stones
## round a stone nobody has painted, rough, newer than the rest, standing in it.
const CLANS := [["kharrow", "#7a2d24"], ["skarl", "#2f4a6b"], ["rudd", "#a4682a"], ["oskel", "#3b5e52"],
		["ghast", "#3a3a3e"], ["brindle", "#8a7a2e"], ["dreugh", "#4a5f8a"]]


static func clan_stones(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.downhill()
	if face == Vector2.ZERO:
		face = k.grain()
	var base := PoiKit.yaw_of(face)
	var packing := m.begin()
	for i in 8:
		var a := base + PI + (float(i) - 3.5) * 0.3
		var p := Vector2(sin(a), cos(a)) * 9.0
		if i < 7:
			var spec: Array = CLANS[i]
			var col := Color.html(str(spec[1])).lerp(Color(0.6, 0.58, 0.54), 0.35)
			var look := PoiKit.painted(0, {"base": "#%s" % col.to_html(false), "accent": "#%s" % col.darkened(0.25).to_html(false),
					"grout": "#5c5850", "unit": 0.5}, 0.65, 0.8)
			await _stone(d, p, a, 2.3 + 0.2 * float(i % 3), look, Vector3(k.rng.randf_range(-0.04, 0.04), 0.0, k.rng.randf_range(-0.04, 0.04)))
		else:
			# the eighth socket: packing stones in a ring, and the unpainted stone in it
			for q in 7:
				var aa := TAU * float(q) / 7.0
				m.ellipsoid(packing, k.on_ground(p.x + sin(aa) * 0.85, p.y + cos(aa) * 0.85, 0.05), Vector3(0.3, 0.2, 0.26), Basis(Vector3.UP, aa))
			await _stone(d, p, a + 0.5, 1.9, null, Vector3(0.1, 0.0, -0.06), 1)
			k.touchable("EighthStone", k.on_ground(p.x - sin(a) * 0.9, p.y - cos(a) * 0.9, 1.0), "Look at the stone in the eighth socket", DIALOGUE + "clan_stones_eighth", "", false)
	m.commit(packing, k.surface("stone", 0.85), "Packing")
	if k.far:
		return
	# the paint-pots the eldest left at the foot of their stones
	for i in [0, 3, 5]:
		var a := base + PI + (float(i) - 3.5) * 0.3
		var p := Vector2(sin(a), cos(a)) * 7.8
		await _prop(d, "bucket", p, k.rng.randf() * TAU)


## The Drove Chain: two stones either side of the Low Road with an iron chain between them, lifted for
## the herds. Today it is hooked up on the uphill stone, hanging down its face, and the chain-ward's
## stool and his slate of the news paid stand by it.
static func drove_chain(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var road := _road_at(k, 30.0)
	var at := Vector2.ZERO
	var run := k.grain()
	if not road.is_empty():
		at = road[0]
		run = road[1]
	var across := Vector2(run.y, -run.x)
	var half := 4.6
	var tops: Array[Vector3] = []
	for s in [-1.0, 1.0]:
		var p := at + across * (half * float(s))
		var n: Node3D = await _stone(d, p, PoiKit.yaw_of(run), 1.9, null, Vector3.ZERO, 0)
		var g := k.on_ground(p.x, p.y)
		tops.append(g + Vector3.UP * (1.9 if n != null else 0.0))
	if k.far:
		return
	# the chain, lifted: hooked on the first stone's top, hanging down and coiled at its foot
	var chain := m.begin()
	var hook: Vector3 = tops[0] + Vector3(across.x, 0.0, across.y) * 0.45
	var foot := Vector3(hook.x, k.on_ground(hook.x, hook.z).y + 0.1, hook.z) + Vector3(across.x, 0.0, across.y) * 0.4
	_chain(m, chain, hook, foot, 0.22, 0.0)
	for i in 3:
		var a := float(i) * 2.1
		var c := foot + Vector3(across.x, 0.0, across.y) * 0.5 + Vector3(sin(a), 0.0, cos(a)) * 0.35
		_chain(m, chain, c, c + Vector3(cos(a), 0.0, -sin(a)) * 0.6, 0.22, 0.0)
	m.rod(chain, Transform3D(Basis(Vector3.BACK, PI * 0.5), hook + Vector3.UP * 0.05), 0.04, 0.5)
	m.commit(chain, PoiKit.plain(IRON, 0.6, 0.55), "DroveChain")
	k.touchable("Chain", foot + Vector3.UP * 0.6 + Vector3(across.x, 0.0, across.y) * 0.8, "Look at the drove chain", DIALOGUE + "drove_chain_lifted", "", false)
	var ward := at + across * (half + 3.0) - run * 1.5
	await _prop(d, "stool", ward, PoiKit.yaw_of(-across))
	var slate := m.begin()
	var stop := m.post(slate, ward + run * 1.2 + across * 0.4, 1.4, 0.12)
	m.block(slate, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(-across)), stop + Vector3.DOWN * 0.3 - Vector3(across.x, 0.0, across.y) * 0.08), Vector3(0.5, 0.4, 0.03))
	m.commit(slate, k.surface("timber", 0.9), "NewsSlate")
	_spot(d, "the_chain_ward", ward - across * 0.6)


## The Seven Stones: seven stones in a ring on the high moor, each grown over with a lichen of its own
## colour (rust, sulphur, grey, white, orange, black, and the seventh still green), a survey cairn
## beside them for the long view over the moor.
const LICHENS := ["#9a5a34", "#b8a43c", "#8e948a", "#d6d3c8", "#c77a2e", "#3a3836", "#5f8a3a"]


static func lichen_stones(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var start := k.rng.randf() * TAU
	for i in 7:
		var a := start + TAU * float(i) / 7.0
		var col := Color.html(LICHENS[i])
		var look := PoiKit.painted(5, {"base": "#%s" % col.to_html(false), "accent": "#a9a49a", "grout": "#5c5850", "unit": 0.22}, 0.7, 0.9)
		var n: Node3D = await _stone(d, Vector2(sin(a), cos(a)) * 7.0, a + PI * 0.5, 2.0 + 0.35 * float((i * 3) % 4), look,
				Vector3(k.rng.randf_range(-0.05, 0.05), 0.0, k.rng.randf_range(-0.05, 0.05)))
		if i == 6 and n != null:
			k.touchable("GreenStone", k.on_ground(sin(a) * 5.8, cos(a) * 5.8, 1.1), "Look at the green stone", DIALOGUE + "seven_stones_green", "", false)
	if k.far:
		return
	var st := m.begin()
	var view := k.downhill() if k.downhill() != Vector2.ZERO else k.grain()
	_cairn(d, st, view * 12.0, 0.7, 1.7)
	m.commit(st, k.surface("stone", 0.85), "SurveyCairn")


## Kharrow Gate: the clan gate at the mouth of Kharrow Gorge where the North Road comes into the heights.
## Two square towers of drystone either side of the road, a timber bar between them raised on its chains,
## and on the downhill side a slab with the law cut in it for the gate-ward to read out and the traveller
## to say back: what is taken is paid for in kind, a death in blood-price, and a host is never robbed.
static func kharrow_gate(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var road := _road_at(k, 30.0)
	var at := Vector2.ZERO
	var run := k.grain()
	if not road.is_empty():
		at = road[0]
		run = road[1]
	var across := Vector2(run.y, -run.x)
	var gap := 7.6
	var sw: Variant = _sites().Stones.new(k, d.poi_id.hash() + 5)
	var tb := Basis(Vector3.UP, PoiKit.yaw_of(run))
	var tops: Array[Vector3] = []
	for s in [-1.0, 1.0]:
		var c := at + across * ((gap * 0.5 + 2.0) * float(s))
		var lo := INF
		for q_v in [Vector2(-1.8, -1.8), Vector2(1.8, -1.8), Vector2(-1.8, 1.8), Vector2(1.8, 1.8)]:
			var q: Vector2 = q_v
			var p := c + across * q.x + run * q.y
			lo = minf(lo, k.on_ground(p.x, p.y).y)
		var g := k.on_ground(c.x, c.y).y
		var h := 7.5 + (0.8 if s > 0.0 else 0.0)
		sw.top = g + h + 0.8
		var xf := Transform3D(tb, Vector3(c.x, (lo - 0.6 + g + h) * 0.5, c.y))
		sw.block(xf, Vector3(4.0, g + h - lo + 0.6, 4.0))
		k.collider(Vector3(4.0, g + h - lo + 0.6, 4.0), xf, "stone")
		# a batter at its foot, a string course, the parapet's merlons
		sw.block(Transform3D(tb, Vector3(c.x, lo + 0.3, c.y)), Vector3(4.6, 1.2, 4.6))
		sw.block(Transform3D(tb, Vector3(c.x, g + h - 1.6, c.y)), Vector3(4.25, 0.25, 4.25))
		for e_v in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			var e: Vector3 = e_v
			for q in [-1.0, 1.0]:
				var off := tb * (e * 1.75 + Vector3(e.z, 0.0, e.x) * 0.95 * float(q))
				sw.block(Transform3D(tb, Vector3(c.x, g + h + 0.4, c.y) + off), Vector3(0.8, 0.8, 0.8))
		tops.append(Vector3(c.x, g + h, c.y))
	_sites()._commit(d, sw, null, "GateTowers", true)
	if k.far:
		return
	var dark := m.begin()
	for s in [-1.0, 1.0]:
		var t: Vector3 = tops[0 if s < 0.0 else 1]
		for row in [3.0, 5.4]:
			for face in [run, -run]:
				var f2: Vector2 = face
				m.block(dark, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(f2)), Vector3(t.x, t.y - 7.5 + float(row), t.z) + Vector3(f2.x, 0.0, f2.y) * 2.02), Vector3(0.3, 0.9, 0.04))
	m.commit(dark, PoiKit.plain(DARK, 0.95), "Slits")
	# the bar: a squared timber on a pivot post at the roadside by the first tower, swung up out of the road
	# with its counterweight of stone at the short end, the way it stands from sunrise to sunset
	var timber := m.begin()
	var t0: Vector3 = tops[0]
	var pivot := at - across * (gap * 0.5 - 0.6) + run * 2.6
	var ptop := m.post(timber, pivot, 1.2, 0.3)
	var tilt := deg_to_rad(72.0)
	var boom := Vector3(across.x, 0.0, across.y) * cos(tilt) + Vector3.UP * sin(tilt)
	m.limb(timber, ptop - boom * 1.0, ptop + boom * 7.0, 0.16)
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(across)), ptop + Vector3.UP * 0.05), Vector3(0.5, 0.16, 0.5))
	m.commit(timber, k.surface("timber", 0.7), "GateBar")
	var weight := m.begin()
	var wp := ptop - boom * 1.0
	m.block(weight, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(across)), wp + Vector3.DOWN * 0.1), Vector3(0.7, 0.6, 0.6))
	m.commit(weight, _sites().stone_look(k, t0.y - 7.5), "GateWeight")
	# the law-stone on the downhill side of the gate, off the road, and the ward's bench by it
	var down := k.downhill()
	var out := run if down.dot(run) >= 0.0 else -run
	var lp := at + out * 6.5 + across * (gap * 0.5 + 1.6)
	var law := m.begin()
	var lg := k.on_ground(lp.x, lp.y)
	var lb := Basis(Vector3.UP, PoiKit.yaw_of(-across))
	m.block(law, Transform3D(lb, lg + Vector3.UP * 0.9), Vector3(1.6, 2.2, 0.4))
	k.collider(Vector3(1.6, 2.2, 0.4), Transform3D(lb, lg + Vector3.UP * 0.9), "stone")
	m.commit(law, _sites().stone_look(k, lg.y), "LawStone")
	var cut := m.begin()
	for r in 6:
		m.block(cut, Transform3D(lb, lg + Vector3.UP * (1.55 - 0.2 * float(r)) - Vector3(across.x, 0.0, across.y) * 0.21), Vector3(1.1 - 0.12 * float(r % 2), 0.05, 0.02))
	m.commit(cut, PoiKit.plain(Color(0.22, 0.21, 0.19), 0.95), "TheLaw")
	k.touchable("LawStone", lg + Vector3.UP * 1.1 - Vector3(across.x, 0.0, across.y) * 0.9, "Read the law cut in the stone", DIALOGUE + "kharrow_gate_law", "", false)
	await _prop(d, "bench", lp + out * 1.8 - across * 0.4, PoiKit.yaw_of(-across))
	_spot(d, "the_gate_ward", lp - across * 1.2 + out * 0.6)
	var t1: Vector3 = tops[1]
	var foot := Vector2(t1.x, t1.z) + out * 3.0 + across * 0.6
	_spot(d, "home", foot)


## The Dale Watch: Ghast's watch-house halfway up the dale, a two-storey drystone house under turf with an
## outside stair to its upper door, and at its foot the great horn on a frame, a giant's horn bound with
## iron, that was blown at midnight with nobody in the house.
static func dale_watch(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var view := k.downhill()
	if view == Vector2.ZERO:
		view = k.grain()
	var side := Vector2(view.y, -view.x)
	var w := 6.0
	var dp := 5.0
	var c := Vector2.ZERO
	var hb := Basis(Vector3.UP, PoiKit.yaw_of(view))
	var lo := INF
	var hi := -INF
	for q_v in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var q: Vector2 = q_v
		var p := c + side * (w * 0.5 * q.x) + view * (dp * 0.5 * q.y)
		lo = minf(lo, k.on_ground(p.x, p.y).y)
		hi = maxf(hi, k.on_ground(p.x, p.y).y)
	var h := 5.6
	var sw: Variant = _sites().Stones.new(k, d.poi_id.hash() + 13)
	sw.top = hi + h
	var xf := Transform3D(hb, Vector3(c.x, (lo - 0.5 + hi + h) * 0.5, c.y))
	sw.block(xf, Vector3(w, hi + h - lo + 0.5, dp))
	k.collider(Vector3(w, hi + h - lo + 0.5, dp), xf, "stone")
	# the outside stair along the house's side wall up to the upper door
	var stair_from := c + side * (w * 0.5 + 0.8) + view * (dp * 0.5 - 0.3)
	var sg := k.on_ground(stair_from.x, stair_from.y).y
	var n := int((hi + 2.8 - sg) / 0.32)
	for i in n:
		var p := stair_from - view * (0.42 * float(i) + 0.21)
		var top_y := sg + 0.32 * float(i + 1)
		var sxf := Transform3D(hb, Vector3(p.x, (top_y + lo - 0.3) * 0.5, p.y))
		sw.block(sxf, Vector3(1.4, top_y - lo + 0.3, 0.44))
		k.collider(Vector3(1.4, top_y - lo + 0.3, 0.44), sxf, "stone")
	_sites()._commit(d, sw, null, "WatchHouse", true)
	# the turf roof, pitched
	var turf := m.begin()
	for s in [-1.0, 1.0]:
		var pitch := hb * Basis(Vector3.BACK, -0.6 * float(s))
		var at := Vector3(c.x, hi + h + 0.9, c.y) + Vector3(side.x, 0.0, side.y) * (w * 0.25 * float(s))
		m.block(turf, Transform3D(pitch, at), Vector3(w * 0.62, 0.35, dp + 0.5))
	await k.step()
	m.commit(turf, PoiKit.painted(5, {"base": "#5f6243", "accent": "#4b4d33", "grout": "#34351f", "unit": 0.3}, 0.75), "Turf", true)
	if k.far:
		return
	var dark := m.begin()
	m.block(dark, Transform3D(hb, Vector3(c.x, lo + 1.1, c.y) + Vector3(view.x, 0.0, view.y) * (dp * 0.5 + 0.02)), Vector3(1.1, 2.0, 0.04))
	m.block(dark, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)), Vector3(c.x, hi + 3.6, c.y) + Vector3(side.x, 0.0, side.y) * (w * 0.5 + 0.02) - Vector3(view.x, 0.0, view.y) * 1.4), Vector3(1.0, 1.8, 0.04))
	for q in [-1.6, 1.6]:
		m.block(dark, Transform3D(hb, Vector3(c.x, hi + 3.8, c.y) + Vector3(view.x, 0.0, view.y) * (dp * 0.5 + 0.02) + Vector3(side.x, 0.0, side.y) * float(q)), Vector3(0.35, 0.8, 0.04))
	m.commit(dark, PoiKit.plain(DARK, 0.95), "Openings")
	# the horn on its frame by the door: a giant's horn, curved, bound with iron
	var hp := c + view * (dp * 0.5 + 2.4) - side * 1.8
	var frame := m.begin()
	var mid := m.frame(frame, hp, PoiKit.yaw_of(side), 2.6, 1.9, 0.16)
	m.commit(frame, k.surface("timber", 0.8), "HornFrame")
	var horn := m.begin()
	var prev := mid + Vector3(side.x, 0.0, side.y) * -1.0 + Vector3.DOWN * 0.25
	for i in 8:
		var t := float(i + 1) / 8.0
		var p := mid + Vector3(side.x, 0.0, side.y) * (-1.0 + 2.1 * t) + Vector3.DOWN * (0.25 + 0.45 * sin(t * PI)) + Vector3(view.x, 0.0, view.y) * 0.25 * t * t
		m.limb(horn, prev, p, lerpf(0.07, 0.24, t))
		prev = p
	m.commit(horn, PoiKit.painted(5, {"base": "#b7a888", "accent": "#7d6c50", "grout": "#4a3e2c", "unit": 0.3}, 0.6, 0.6), "GreatHorn")
	var bands := m.begin()
	for s in [-0.5, 0.6]:
		var bp := mid + Vector3(side.x, 0.0, side.y) * float(s) + Vector3.DOWN * 0.15
		m.block(bands, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)), bp), Vector3(0.05, 0.42, 0.05))
	m.commit(bands, PoiKit.plain(IRON, 0.6, 0.5), "HornBands")
	k.touchable("Horn", mid + Vector3.DOWN * 0.5 + Vector3(view.x, 0.0, view.y) * 0.7, "Look at the horn", DIALOGUE + "dale_watch_horn", "", false)
	await _prop(d, "bench", c + view * (dp * 0.5 + 1.2) + side * 1.6, PoiKit.yaw_of(side))


## The Skerr Stone: the first stone of the clans' country on the Low Road, broken across, its top lying
## in the grass beside its stump; Skerrish cut deep on the stump's road face, and on the fallen top's
## other face the Valish chiselled off, and lately cut back in, badly, pale and shallow. A child's
## chisel and a mallet left in the grass.
static func skerr_stone(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var road := _toward_road(k, 40.0)
	if road == Vector2.ZERO:
		road = k.grain()
	var side := Vector2(road.y, -road.x)
	var sb := Basis(Vector3.UP, PoiKit.yaw_of(road))
	var g := k.on_ground(0.0, 0.0)
	var stone := m.begin()
	m.block(stone, Transform3D(sb, g + Vector3.UP * 0.55), Vector3(0.9, 1.5, 0.45))
	k.collider(Vector3(0.9, 1.5, 0.45), Transform3D(sb, g + Vector3.UP * 0.55), "stone")
	var fp := side * 1.5 - road * 0.4
	var fg := k.on_ground(fp.x, fp.y)
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(road) + 0.4) * Basis(Vector3.RIGHT, -PI * 0.5)
	m.block(stone, Transform3D(fb, fg + Vector3.UP * 0.2), Vector3(0.9, 1.2, 0.45))
	k.collider(Vector3(0.9, 0.45, 1.2), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(road) + 0.4), fg + Vector3.UP * 0.2), "stone")
	await k.step()
	m.commit(stone, _sites().stone_look(k, g.y), "SkerrStone", true)
	if k.far:
		return
	var cut := m.begin()
	for r in 4:
		m.block(cut, Transform3D(sb, g + Vector3.UP * (1.0 - 0.18 * float(r)) + Vector3(road.x, 0.0, road.y) * 0.235), Vector3(0.6 - 0.08 * float(r % 2), 0.06, 0.02))
	m.commit(cut, PoiKit.plain(Color(0.2, 0.19, 0.17), 0.95), "Skerrish")
	var fresh := m.begin()
	var up_face := fb * Vector3(0.0, 0.0, 0.235)
	for r in 3:
		m.block(fresh, Transform3D(fb, fg + Vector3.UP * 0.2 + up_face + fb * Vector3(k.rng.randf_range(-0.05, 0.05), 0.3 - 0.22 * float(r), 0.0)), Vector3(0.5 + k.rng.randf_range(-0.1, 0.1), 0.07, 0.015))
	m.commit(fresh, PoiKit.plain(Color(0.86, 0.84, 0.78), 0.9), "NewValish")
	k.touchable("SkerrStone", fg + Vector3.UP * 0.6, "Look at the fallen top of the stone", DIALOGUE + "skerr_stone_valish", "", false)
	await _prop(d, "hammer", side * 2.4 + road * 0.5, 1.1)
	await _prop(d, "tongs", side * 2.1 + road * 0.9, 2.3)


# --- Oskel Gloup -------------------------------------------------------------------------------------

## Oskel Gloup: a sea cave whose roof fell in a long bowshot back from the cliff, leaving a black shaft
## in the moor with the sea booming at its foot and its spray coming up out of it in the wind. Round its
## lip a ring of drystone, broken where the stair goes down, and over it the Oskel's derrick: two legs
## of ship's timber leaning out over the hole, the jib and its block, the rope still reeved, the winch
## behind on its stones; the winchman's house, shut; the lead pigs dropped on the sledge-way from the
## Leadhouse; and on the seaward lip an iron bracket on a post where a lamp hung, new soot on it.
static func oskel_gloup(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var site := _site_of(d)
	var interior := str(site.get("interior", ""))
	var sea := _bearing(site, "sea_bearing_deg", k.water_direction(300.0))
	if sea == Vector2.ZERO:
		sea = Vector2(-1.0, 0.0)
	var land := -sea
	var side := Vector2(sea.y, -sea.x)
	var hb := Basis(Vector3.UP, PoiKit.yaw_of(sea))
	var g := k.on_ground(0.0, 0.0)
	var rx := 6.2
	var rz := 5.0
	# the hole, and the broken rock of its lip leaning in over it
	var hole := m.begin()
	m.ellipsoid(hole, g + Vector3.UP * 0.03, Vector3(rx, 0.03, rz), hb)
	m.commit(hole, PoiKit.plain(DARK, 1.0), "TheGloup", true)
	var lip := m.begin()
	var wall := m.begin()
	for i in 22:
		var a := TAU * float(i) / 22.0
		var p := side * (sin(a) * rx) + sea * (cos(a) * rz)
		var size := Vector3(k.rng.randf_range(1.8, 2.8), k.rng.randf_range(0.6, 1.1), k.rng.randf_range(1.2, 1.8))
		var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(p) + PI * 0.5) * Basis(Vector3.RIGHT, -0.35), k.on_ground(p.x * 1.06, p.y * 1.06, size.y * 0.3))
		m.block(lip, xf, size)
		k.collider(size, xf, "stone")
	# the crater the roof's fall left: a bank of turf round the lip, highest on the seaward side, and a
	# length of the Oskel's drystone on its landward crest either side of the stair
	var bank := m.begin()
	var rows := 5
	var segs := 28
	var ring_pts: Array = []
	for r_i in rows + 1:
		var f := float(r_i) / float(rows)
		var row: Array = []
		for j in segs:
			var a := TAU * float(j) / float(segs)
			var lift := (1.0 + 0.6 * maxf(cos(a), 0.0)) * clampf(absf(angle_difference(a, PI)) / 0.7, 0.15, 1.0)
			var rr := 1.0 + f * 5.0
			var p := side * (sin(a) * (rx + rr)) + sea * (cos(a) * (rz + rr))
			var y := (1.0 * lift) * sin(minf(f * 1.6, 1.0) * PI * 0.5) * (1.0 - f * f) + 0.18 * sin(a * 5.0 + f * 3.0) * sin(a * 3.0 - f * 7.0) * f
			row.append(k.on_ground(p.x, p.y, y - 0.08))
		ring_pts.append(row)
	for r_i in rows:
		for j in segs:
			var j1 := (j + 1) % segs
			var a: Vector3 = ring_pts[r_i][j]
			var b: Vector3 = ring_pts[r_i][j1]
			var c2: Vector3 = ring_pts[r_i + 1][j1]
			var e: Vector3 = ring_pts[r_i + 1][j]
			for q in [a, b, c2, a, c2, e]:
				bank.add_vertex(q)
	await k.step()
	_ground_mesh(d, bank, PoiKit.painted(5, {"base": "#4d4b3a", "accent": "#5d5c45", "grout": "#2a2a1e", "unit": 0.25}, 0.85, 0.9), "Crater", true)
	for s in [-1.0, 1.0]:
		var a0 := PI + 0.42 * float(s)
		var a1 := PI + 1.25 * float(s)
		var p0 := side * (sin(a0) * (rx + 3.2)) + sea * (cos(a0) * (rz + 3.2))
		var p1 := side * (sin(a1) * (rx + 3.2)) + sea * (cos(a1) * (rz + 3.2))
		m.wall(wall, p0, p1, 1.0, 0.3)
	m.commit(lip, PoiKit.painted(0, LIME, 0.8, 0.8), "GloupLip", true)
	m.commit(wall, k.surface("stone", 0.85), "RingWall", true)
	# the derrick: two legs from the landward side leaning out over the hole, the jib, the block, the rope
	var timber := m.begin()
	var legs: Array[Vector3] = []
	for s in [-1.0, 1.0]:
		var fp := land * (rz + 3.6) + side * 2.6 * float(s)
		legs.append(k.on_ground(fp.x, fp.y, -0.3))
	var head := g + Vector3.UP * 9.5 + Vector3(land.x, 0.0, land.y) * 0.6
	for leg in legs:
		_limb_solid(d, timber, leg, head, 0.2)
	m.limb(timber, legs[0].lerp(head, 0.35), legs[1].lerp(head, 0.35), 0.1)
	var jib_end := head + Vector3(sea.x, 0.0, sea.y) * 2.2 + Vector3.DOWN * 0.4
	m.limb(timber, head, jib_end, 0.14)
	# the back-stays down to stakes behind, and the winch on its stones between them
	var stake := land * (rz + 12.0)
	var sg := k.on_ground(stake.x, stake.y)
	m.post(timber, stake, 0.8, 0.18)
	var winch := land * (rz + 7.5)
	var wg := k.on_ground(winch.x, winch.y)
	var wb := Basis(Vector3.UP, PoiKit.yaw_of(side))
	for s in [-1.0, 1.0]:
		m.block(timber, Transform3D(hb, wg + Vector3.UP * 0.55 + Vector3(side.x, 0.0, side.y) * 1.0 * float(s)), Vector3(0.2, 1.1, 1.2))
	m.rod(timber, Transform3D(wb * Basis(Vector3.BACK, PI * 0.5), wg + Vector3.UP * 0.95), 0.32, 1.9)
	for s in [-1.0, 1.0]:
		m.block(timber, Transform3D(wb, wg + Vector3.UP * 0.95 + Vector3(side.x, 0.0, side.y) * 1.25 * float(s) + Vector3.DOWN * 0.25), Vector3(0.08, 0.6, 0.08))
	k.collider(Vector3(2.2, 1.2, 1.3), Transform3D(hb, wg + Vector3.UP * 0.6), "wood")
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "Derrick", true)
	if k.far:
		return
	var rope := m.begin()
	m.limb(rope, head + Vector3.DOWN * 0.1, sg + Vector3.UP * 0.7, 0.03)
	m.limb(rope, jib_end, wg + Vector3.UP * 1.1, 0.025)
	m.limb(rope, jib_end + Vector3.DOWN * 0.3, Vector3(jib_end.x, g.y + 0.04, jib_end.z), 0.03)
	m.ellipsoid(rope, jib_end + Vector3.DOWN * 0.15, Vector3(0.2, 0.28, 0.12))
	m.commit(rope, PoiKit.plain(Color(0.36, 0.31, 0.24), 0.9), "DerrickRope")
	k.puffs(g + Vector3.UP * 0.5, Vector3(rx * 0.6, 0.3, rz * 0.6), 11.0, 36, Color(0.92, 0.94, 0.96, 0.4), 3.6, 5.0)
	# the stair head on the landward side: a landing of planks on posts out over the lip, a rail, and the
	# door down
	var land_at := land * (rz - 0.4)
	var ly := k.on_ground(land_at.x, land_at.y).y + 0.25
	var planks := m.begin()
	var posts := m.begin()
	m.plank_deck(planks, posts, land * (rz + 1.6), land * (rz - 1.2), 2.2, ly, 1.4, true)
	m.commit(planks, k.surface("planks", 0.8), "StairHead")
	m.commit(posts, k.surface("timber", 0.85), "StairPosts")
	if interior != "":
		_sites()._door(d, interior, Vector3(land_at.x, ly, land_at.y) + Vector3(sea.x, 0.0, sea.y) * 0.4, PoiKit.yaw_of(land))
	k.light(Vector3(land_at.x, ly + 1.8, land_at.y), Color(0.9, 0.85, 0.8), 0.8, 6.0)
	# the lamp bracket on the seaward lip, the new soot on it
	var bp := sea * (rz + 1.6)
	var iron := m.begin()
	var bt := m.post(iron, bp, 2.3, 0.1)
	m.block(iron, Transform3D(hb, bt + Vector3(sea.x, 0.0, sea.y) * 0.4 + Vector3.DOWN * 0.05), Vector3(0.06, 0.06, 0.85))
	m.block(iron, Transform3D(hb, bt + Vector3(sea.x, 0.0, sea.y) * 0.8 + Vector3.DOWN * 0.25), Vector3(0.05, 0.4, 0.05))
	m.commit(iron, PoiKit.plain(IRON, 0.6, 0.5), "LampBracket")
	var soot := m.begin()
	m.block(soot, Transform3D(hb, bt + Vector3(sea.x, 0.0, sea.y) * 0.4 + Vector3.UP * 0.04), Vector3(0.09, 0.03, 0.5))
	m.commit(soot, PoiKit.plain(Color(0.05, 0.05, 0.05), 1.0), "Soot")
	k.touchable("LampBracket", bt + Vector3.DOWN * 0.9 - Vector3(sea.x, 0.0, sea.y) * 0.4, "Look at the lamp bracket", DIALOGUE + "oskel_gloup_bracket", "", false)
	# the winchman's house, shut, and the sledge-way from the Leadhouse with the pigs dropped on it
	var home := land * (rz + 9.0) + side * 9.0
	await _bothy(d, home, -side, 5.0, 4.0, false)
	var way := m.begin()
	_track(d, way, [land * (rz + 2.0), land * (rz + 8.5), land * (d.pad_radius * 0.92) + side * 4.0], 2.2)
	m.commit(way, k.surface("earth", 0.45), "SledgeWay")
	var pigs := m.begin()
	for i in 5:
		var p := land * (rz + 13.0 + 0.7 * float(i)) + side * (1.0 + k.rng.randf_range(-0.6, 0.6))
		m.block(pigs, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), k.on_ground(p.x, p.y, 0.06)), Vector3(0.55, 0.2, 0.26))
	m.commit(pigs, PoiKit.plain(Color(0.33, 0.34, 0.36), 0.5, 0.6), "LeadPigs")
	k.marker("the_rim", k.on_ground(side.x * (rx + 4.0), side.y * (rx + 4.0)))


# --- setting the kinds' pieces straight (triage 74) ------------------------------------------------

## What may hang or fly: a lamp judged by what it hangs from, a bird, a bell on a cord.
const AIRY := ["lamp", "lantern", "bell", "crow", "raven", "gull", "banner", "torch"]


## A placed asset's box in the dressing's own space (from its meshes), or an empty AABB.
static func _box_of(d: PoiDressing, n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi_v in n.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_v as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = d._local_of(mi) * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## After a kind's builder: what it stood up that a body would see is wrong, set right. A placed prop
## floating over the ground is set down on it; a standing prop in a road's carriageway is moved off to
## the verge; a length of drystone joined to no other is taken away. Merged masonry is left alone (it
## is meshed later, on a worker, where a place is raised while the world is drawn).
static func _tidy(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		return
	var placed: Array[Node3D] = []
	for c in d.get_children():
		if c is Node3D and not (c is MeshInstance3D) and not (c is MultiMeshInstance3D) and str((c as Node).scene_file_path) != "":
			placed.append(c as Node3D)
	var walls: Array[Node3D] = []
	for n in placed:
		var fam := str(n.name).to_lower()
		if fam.contains("drystone"):
			walls.append(n)
	for w in walls:
		var joined := false
		for o in walls:
			if o != w and o.position.distance_to(w.position) < 3.4:
				joined = true
				break
		if not joined:
			placed.erase(w)
			w.queue_free()
	for n in placed:
		var fam := str(n.name).to_lower()
		# (and a thing its builder seated on what holds it: a cave's capstones on the throat's roof,
		# which set down on the ground under them went into its cheeks and its mouth)
		var airy := n.has_meta(PoiKit.SEATED_META)
		for a in AIRY:
			airy = airy or fam.contains(a)
		var box := _box_of(d, n)
		if box.size == Vector3.ZERO:
			continue
		var c := box.get_center()
		# in a carriageway: off to the nearer verge, its half-width and a step clear
		var at := Vector2(c.x, c.z)
		var rd := k.road_distance(at)
		var half := maxf(box.size.x, box.size.z) * 0.5
		if not airy and rd < PoiKit.ROAD_CLEAR_M + half and box.size.y > 0.35 and not fam.contains("bridge"):
			var road := _road_at(k, 60.0)
			if not road.is_empty():
				var run: Vector2 = road[1]
				var perp := Vector2(-run.y, run.x)
				var rel := at - (road[0] as Vector2)
				var sgn := 1.0 if rel.dot(perp) >= 0.0 else -1.0
				var push := PoiKit.ROAD_CLEAR_M + half + 0.4 - rd
				var to := at + perp * sgn * push
				var dy := k.on_ground(to.x, to.y).y - k.on_ground(at.x, at.y).y
				n.position += Vector3(perp.x * sgn * push, dy, perp.y * sgn * push)
				box = _box_of(d, n)
		# floating: set down on the highest ground under its footprint
		if airy:
			continue
		var gmax := -INF
		var hx := box.size.x * 0.35
		var hz := box.size.z * 0.35
		var bc := box.get_center()
		for q in [Vector2.ZERO, Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
			gmax = maxf(gmax, k.on_ground(bc.x + q.x, bc.z + q.y).y)
		if box.position.y > gmax + 0.1:
			n.position.y -= box.position.y - gmax - 0.03


## A kind built as it is, then set straight.
static func _kind_tidied(d: PoiDressing) -> void:
	await _kind(d)
	_tidy(d)


static func horn_hole(d: PoiDressing) -> void:
	await _kind_tidied(d)


static func kharrow_hole(d: PoiDressing) -> void:
	await _kind_tidied(d)


static func oskel_drip(d: PoiDressing) -> void:
	await _kind_tidied(d)


static func wrist_hole(d: PoiDressing) -> void:
	await _kind_tidied(d)


static func wolf_stones(d: PoiDressing) -> void:
	await _kind_tidied(d)


static func chain_bridge(d: PoiDressing) -> void:
	await _kind_tidied(d)


static func ghasts_broken_bridge(d: PoiDressing) -> void:
	await _kind_tidied(d)


static func giants_stair(d: PoiDressing) -> void:
	await _kind_tidied(d)



# --- the novel places (2026-10-04) --------------------------------------------------------------------
# Eight new kinds of place and two large sites (pois/skerrow.json, the rest of their words in the
# `novel_skerrow.json` files). Every piece that stands off the ground is drawn in one mesh with something
# that stands on it (a post, a ladder, a rope's end), so the seat audit sees what holds it up.

## Pale karst limestone, freshly scarred; black oak; straw; tanned hide; ochre; heather-gold bees.
const LIME_PALE := {"base": "#cdc8bb", "accent": "#aea89a", "grout": "#7a756a", "unit": 0.55}
const OAK_BLACK := {"base": "#2e2924", "accent": "#201c18", "grout": "#110e0c", "unit": 0.4}
const STRAW := {"base": "#b48c4c", "accent": "#8e6b36", "grout": "#5a4422", "unit": 0.1}
const HIDE := {"base": "#8a6a48", "accent": "#6b5038", "grout": "#3e2e20", "unit": 0.7}
const TURF := {"base": "#5f6243", "accent": "#4b4d33", "grout": "#34351f", "unit": 0.3}
const GRAVEL := {"base": "#b9b4a8", "accent": "#97928a", "grout": "#6c685f", "unit": 0.2}
const OCHRE := Color(0.62, 0.32, 0.16)


## The way a place faces: to the nearest road, else downhill, else along the grain (unit, local xz).
static func _facing(k: PoiKit, reach := 400.0) -> Vector2:
	var out := _toward_road(k, reach)
	if out == Vector2.ZERO:
		out = k.downhill()
	if out == Vector2.ZERO:
		out = k.grain()
	if out == Vector2.ZERO:
		out = Vector2(0.0, 1.0)
	return out.normalized()


## One of the forge's cliff faces stood up as a crag at local `at`, its face looking toward `face`, `h`
## metres tall, its foot sunk `sink` into the ground; drawn in the far ring, so it reads from afar.
static func _crag(d: PoiDressing, at: Vector2, face: Vector2, h: float, variant := 0, sink := 1.0) -> Node3D:
	var k := d.kit
	var path := k.rock("cliff_face", variant)
	if path == "":
		return null
	var sc := h / maxf(PoiKit.height_of(path), 0.5)
	await k.step()
	return k.place(path, k.on_ground(at.x, at.y, -sink), PoiKit.yaw_of(face), sc, true, Vector3.ZERO, true)


## A straight pole (a limb) from `a` to `b` (local) into `st`, with a box to walk into.
static func _pole(d: PoiDressing, st: SurfaceTool, a: Vector3, b: Vector3, r: float, surface := "wood") -> void:
	_limb_solid(d, st, a, b, r, surface)


## A rope or a line from `a` to `b` (local), sagging `sag` metres at its middle, in `segs` pieces.
static func _line(m: PoiMasonry, st: SurfaceTool, a: Vector3, b: Vector3, r: float, sag := 0.0, segs := 8) -> void:
	var prev := a
	for i in segs:
		var t := float(i + 1) / float(segs)
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		m.limb(st, prev, p, r)
		prev = p


## A ladder from `foot` to `top` (local) into `st`: two rails and a rung every 0.35 m.
static func _ladder(m: PoiMasonry, st: SurfaceTool, foot: Vector3, top: Vector3, w := 0.5) -> void:
	var up := top - foot
	var side := up.cross(Vector3.UP).normalized() if absf(up.normalized().y) < 0.99 else Vector3.RIGHT
	for s in [-1.0, 1.0]:
		m.limb(st, foot + side * (w * 0.5 * float(s)), top + side * (w * 0.5 * float(s)), 0.04)
	var n := int(up.length() / 0.35)
	for i in n:
		var p := foot + up * ((float(i) + 0.5) / float(n))
		m.limb(st, p - side * w * 0.5, p + side * w * 0.5, 0.025)


# --- the Kinchain --------------------------------------------------------------------------------------

const KIN_JIB_M := 14.0

## The Kinchain: a crag of the Ghast side with a black oak jib leaning out over its foot, and from the
## jib's head the Ghast chain hanging fourteen metres to the ground, where it lies in a coil as high as a
## man; twelve links from the top a plain new ring closes a gap. At its foot Ottar's open hearth, his
## anvil and quench, and a rack of iron bars.
static func the_kinchain(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var out := _facing(k)
	var side := Vector2(out.y, -out.x)
	# the crag behind, and a shoulder of it to one side
	await _crag(d, -out * 9.5, out, 15.0, 0, 1.4)
	await _crag(d, -out * 12.0 + side * 9.0, out.rotated(-0.5), 10.5, 2, 1.0)
	# the jib: two raking masts from the turf in front of the face, leaning back to the rock, and a
	# head-beam run out over the chain's coil, braced; all black oak
	var oak := m.begin()
	var coil := out * 3.0
	var g0 := k.on_ground(coil.x, coil.y).y
	var head := Vector3(coil.x, g0 + KIN_JIB_M, coil.y)
	var heel := -out * 3.4
	for s in [-1.0, 1.0]:
		var foot2 := heel + side * (1.6 * float(s))
		var f3 := k.on_ground(foot2.x, foot2.y, -0.3)
		var t3 := Vector3(heel.x - out.x * 1.6 + side.x * 0.5 * float(s), g0 + KIN_JIB_M + 0.4, heel.y - out.y * 1.6 + side.y * 0.5 * float(s))
		_pole(d, oak, f3, t3, 0.26)
		_pole(d, oak, t3, head + Vector3(side.x, 0.0, side.y) * 0.3 * float(s), 0.2)
		# a stay from the mast's middle out to the head
		_pole(d, oak, f3.lerp(t3, 0.55), head + Vector3.DOWN * 0.3, 0.12)
	m.block(oak, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)), head + Vector3.UP * 0.2), Vector3(0.4, 0.4, 1.4))
	await k.step()
	m.commit(oak, PoiKit.painted(3, OAK_BLACK, 0.8), "Jib", true)
	# the chain: from the jib's head straight down to the coil, and the plain new ring twelve links down
	# (bright, with the bars on Ottar's rack: the iron he has not yet closed on anybody)
	var iron := m.begin()
	var bright := m.begin()
	var link := 0.46
	var top := head + Vector3.DOWN * 0.3
	var gap_at := top + Vector3.DOWN * (link * 0.8 * 12.0)
	_chain(m, iron, top, gap_at + Vector3.UP * link * 0.5, link)
	m.rod(bright, Transform3D(Basis(Vector3.BACK, PI * 0.5), gap_at), 0.05, link * 1.1)
	m.rod(bright, Transform3D(Basis.IDENTITY, gap_at), 0.05, link * 0.9)
	var low := Vector3(coil.x, g0 + 1.5, coil.y)
	_chain(m, iron, gap_at - Vector3.UP * link * 0.5, low, link)
	# the coil: rings of chain laid round and round, each smaller and higher
	for i in 6:
		var rr := 1.7 - 0.2 * float(i)
		var y := g0 + 0.12 + 0.24 * float(i)
		var n := 10
		var prev := Vector3(coil.x + rr, y, coil.y)
		for j in n:
			var a := TAU * float(j + 1) / float(n)
			var p := Vector3(coil.x + cos(a) * rr, y + 0.024 * float(j), coil.y + sin(a) * rr)
			_chain(m, iron, prev, p, link * 0.9)
			prev = p
	k.collider(Vector3(3.4, 1.4, 3.4), Transform3D(Basis.IDENTITY, Vector3(coil.x, g0 + 0.7, coil.y)), "stone")
	await k.step()
	m.commit(iron, PoiKit.plain(IRON, 0.55, 0.6), "Chain", true)
	# Ottar's rack of bars against the crag foot, in the same bright iron as the ring
	var hearth := coil + side * 6.0 + out * 1.5
	var rack := hearth + side * 2.6 + out * 2.2
	var rack_wood := m.begin()
	m.post(rack_wood, rack, 1.4, 0.12)
	m.post(rack_wood, rack + out * 1.6, 1.4, 0.12)
	for i in 7:
		var at := Vector3(rack.x, k.on_ground(rack.x, rack.y).y + 0.02, rack.y) + Vector3(out.x, 0.0, out.y) * (0.2 + 0.2 * float(i))
		m.limb(bright, at, at + Vector3.UP * 1.3 + Vector3(side.x, 0.0, side.y) * 0.25, 0.03)
	await k.step()
	m.commit(bright, PoiKit.plain(Color(0.42, 0.4, 0.38), 0.4, 0.75), "BrightIron", true)
	if k.far:
		return
	m.commit(rack_wood, PoiKit.painted(3, OAK_BLACK, 0.7), "BarRack")
	# Ottar's hearth: a forge-hearth, the anvil, a quench, and a rack of bars against a stone
	await _prop(d, "forge_hearth", hearth, PoiKit.yaw_of(-side))
	k.light(k.on_ground(hearth.x, hearth.y, 1.2) + Vector3(-side.x, 0.0, -side.y) * 0.8, Color(1.0, 0.55, 0.25), 1.6, 8.0)
	await _prop(d, "anvil", hearth - side * 2.2 + out * 0.6, PoiKit.yaw_of(out))
	await _prop(d, "trough", hearth - side * 0.4 + out * 2.4, PoiKit.yaw_of(side))
	await _prop(d, "tongs", hearth - side * 2.0 + out * 1.6, k.rng.randf() * TAU)
	await _prop(d, "chopping_block", hearth + side * 2.0 - out * 1.0, 0.0)
	_spot(d, "ottar_hearth", hearth - side * 1.6 + out * 1.4)
	k.touchable("the_chain", Vector3(coil.x, g0 + 1.4, coil.y) + Vector3(out.x, 0.0, out.y) * 1.9, "Look at the Kinchain", DIALOGUE + "kinchain_chain", "", false)
	k.marker("the_coil", k.on_ground(coil.x + out.x * 3.0, coil.y + out.y * 3.0))


# --- the Kite-Watch --------------------------------------------------------------------------------------

## The Kite-Watch: a knoll over the west moor with two windlasses on it, and riding thirty metres over
## them on their lines the Oskel kites, a hide hawk with its wings swept and tails streaming, and the
## black diamond with its lantern-cage; a pole of red and white streamers, the turf watch-hut in the lee.
static func the_kite_watch(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var out := _facing(k)
	var side := Vector2(out.y, -out.x)
	# the wind is west on the moor: the kites ride east of their windlasses
	var down := Vector2(1.0, 0.0)
	var cross := Vector2(0.0, 1.0)
	var hawk_w := Vector2(-3.0, -1.6)
	var night_w := Vector2(-3.0, 2.2)
	var hawk := Vector3(hawk_w.x + 14.0, k.on_ground(hawk_w.x, hawk_w.y).y + 31.0, hawk_w.y - 3.0)
	var night := Vector3(night_w.x + 11.0, k.on_ground(night_w.x, night_w.y).y + 24.0, night_w.y + 3.5)
	# the windlasses: drums of oak on posts, a handle, a stake in the turf for each line
	var oak := m.begin()
	var lines := m.begin()
	for w in [[hawk_w, hawk], [night_w, night]]:
		var at: Vector2 = w[0]
		var to: Vector3 = w[1]
		var g := k.on_ground(at.x, at.y).y
		for s in [-1.0, 1.0]:
			m.post(oak, at + cross * (0.55 * float(s)), 1.1, 0.14)
		var drum := Vector3(at.x, g + 0.85, at.y)
		m.rod(oak, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), drum), 0.28, 1.0)
		m.block(oak, Transform3D(Basis.IDENTITY, drum + Vector3(0.0, 0.0, 0.62)), Vector3(0.06, 0.5, 0.06))
		m.block(oak, Transform3D(Basis.IDENTITY, drum + Vector3(0.18, -0.22, 0.66)), Vector3(0.3, 0.05, 0.05))
		# the line: off the drum to a stake a pace downwind, and up from the stake to the kite
		var stake := Vector3(at.x + 1.4, g, at.y)
		m.limb(oak, stake + Vector3.DOWN * 0.2, stake + Vector3.UP * 0.5, 0.06)
		m.limb(lines, drum + Vector3(0.3, 0.2, 0.0), stake + Vector3.UP * 0.45, 0.022)
		_line(m, lines, stake + Vector3.UP * 0.45, to, 0.022, 2.4, 10)
	# a pole of streamers, red and white, and the watch-hut in the lee of the knoll
	var pole_at := Vector2(-5.5, -6.0)
	var pole_top := m.post(oak, pole_at, 8.5, 0.16)
	await k.step()
	m.commit(oak, PoiKit.painted(3, OAK_BLACK, 0.7), "Windlasses", true)
	var red := m.begin()
	var white := m.begin()
	for i in 6:
		var st := red if i % 2 == 0 else white
		var y := pole_top.y - 0.3 - 0.5 * float(i)
		var a := 0.35 + 0.08 * float(i)
		var basis := Basis(Vector3.UP, PoiKit.yaw_of(down)) * Basis(Vector3.RIGHT, -a)
		m.block(st, Transform3D(basis, Vector3(pole_top.x, y, pole_top.z) + Vector3(down.x, -0.1, down.y) * 1.3), Vector3(0.18, 0.02, 2.6))
	await k.step()
	m.commit(red, PoiKit.plain(Color(0.6, 0.12, 0.1), 0.85), "KiteStreamersRed", true)
	m.commit(white, PoiKit.plain(Color(0.86, 0.84, 0.78), 0.85), "KiteStreamersWhite", true)
	# the hawk: a body, two swept wings with a little dihedral, a forked tail of streamers
	var hide := m.begin()
	var hb := Basis(Vector3.UP, PoiKit.yaw_of(-down)) * Basis(Vector3.RIGHT, 0.95)
	m.block(hide, Transform3D(hb, hawk), Vector3(0.5, 0.08, 2.4))
	for s in [-1.0, 1.0]:
		var wing := hb * Basis(Vector3.BACK, 0.12 * float(s)) * Basis(Vector3.UP, 0.42 * float(s))
		m.block(hide, Transform3D(wing, hawk + hb * Vector3(1.9 * float(s), 0.0, 0.25)), Vector3(3.6, 0.05, 1.1))
	await k.step()
	m.commit(hide, PoiKit.painted(5, HIDE, 0.6, 0.7), "KiteHawk", true)
	var dark := m.begin()
	var nb := Basis(Vector3.UP, PoiKit.yaw_of(-down)) * Basis(Vector3.RIGHT, 1.05) * Basis(Vector3.UP, PI * 0.25)
	m.block(dark, Transform3D(nb, night), Vector3(2.6, 0.05, 2.6))
	m.block(dark, Transform3D(nb * Basis(Vector3.UP, -PI * 0.25), night + Vector3.DOWN * 0.05), Vector3(0.08, 0.1, 3.6))
	# the tails: ribbons hanging down the wind from both kites
	for t in [[hawk, 3], [night, 2]]:
		var at: Vector3 = t[0]
		for i in int(t[1]):
			var o := Vector3(down.x, 0.0, down.y) * (1.4 + 0.2 * float(i)) + Vector3(cross.x, 0.0, cross.y) * (0.5 * (float(i) - 1.0))
			_line(m, dark, at + Vector3.DOWN * 0.6, at + o * 2.0 + Vector3.DOWN * 3.2, 0.05, 0.0, 3)
	await k.step()
	m.commit(dark, PoiKit.plain(Color(0.08, 0.075, 0.07), 0.8), "KiteBlack", true)
	await k.step()
	m.commit(lines, PoiKit.plain(Color(0.45, 0.42, 0.36), 0.9), "KiteLines", true)
	if k.far:
		return
	# the night kite's lantern in its cage, lit after dark
	var lamp := m.begin()
	m.block(lamp, Transform3D(nb, night + Vector3.DOWN * 0.35), Vector3(0.32, 0.4, 0.32))
	m.commit(lamp, PoiKit.plain(Color(1.0, 0.8, 0.5), 0.5, 0.0, Color(1.0, 0.7, 0.35), 1.6), "KiteLantern")
	var hut := -out * 8.0 + side * 7.0
	var door: Vector2 = await _bothy(d, hut, out.rotated(0.4), 4.4, 3.6)
	_spot(d, "home", door + out * 0.6)
	await _prop(d, "peat_stack", hut - side * 3.4, PoiKit.yaw_of(side))
	await _prop(d, "basket", door + side * 1.1, k.rng.randf() * TAU)
	_spot(d, "runa_windlass", hawk_w + Vector2(-1.2, 0.6))
	k.touchable("the_windlass", k.on_ground(hawk_w.x, hawk_w.y, 1.0), "Work the kite windlass", DIALOGUE + "kite_watch_windlass", "", false)


# --- the Bee-Bole Crag ------------------------------------------------------------------------------------

const BOLE_ROWS := 8
const BOLE_COLS := 9
const BOLE_W := 0.78
const BOLE_H := 0.7

## The Bee-Bole Crag: a scar of white limestone faced and cut in eight rows of square niches, a straw
## skep in nearly every one and the air thick with bees before it, the crag of the hill behind; each row
## with its clan's colour daubed over it, the top row's mark a bone and its niches swept and empty.
## Bannoch's turf hut and smoker at the foot.
static func bee_bole_crag(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var out := _facing(k)
	var side := Vector2(out.y, -out.x)
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(out))
	var wall_at := -out * 8.0
	var span := float(BOLE_COLS) * (BOLE_W + 0.62) + 0.8
	var height := float(BOLE_ROWS) * (BOLE_H + 0.32) + 1.0
	# the crag behind it, and the face: courses of white limestone on the hill's own foot
	await _crag(d, wall_at - out * 7.5, out, 13.0, 2, 1.4)
	var sw: Variant = _sites().Stones.new(k, d.poi_id.hash() + 61)
	var gb := INF
	for s in [-0.5, -0.25, 0.0, 0.25, 0.5]:
		var p := wall_at + side * span * float(s)
		gb = minf(gb, k.on_ground(p.x, p.y).y)
	var base := Vector3(wall_at.x, gb - 0.6, wall_at.y)
	sw.top = base.y + height + 0.6
	var depth := 2.4
	# the face in rows: a solid course under every row of boles, and piers between the boles
	var y := base.y
	sw.block(Transform3D(fb, base + Vector3.UP * 0.9), Vector3(span, 1.8, depth))
	y += 1.8
	var holes: Array = []
	for r in BOLE_ROWS:
		var pier_w := (span - float(BOLE_COLS) * BOLE_W) / float(BOLE_COLS + 1)
		for c in BOLE_COLS + 1:
			var x := -span * 0.5 + pier_w * 0.5 + float(c) * (pier_w + BOLE_W)
			sw.block(Transform3D(fb, Vector3(base.x, y + BOLE_H * 0.5, base.z) + fb * Vector3(x, 0.0, 0.0)), Vector3(pier_w, BOLE_H, depth))
			if c < BOLE_COLS:
				var hx := x + pier_w * 0.5 + BOLE_W * 0.5
				holes.append([r, Vector3(base.x, y, base.z) + fb * Vector3(hx, 0.0, depth * 0.5 - 0.62)])
				# the bole's back, set in
				sw.block(Transform3D(fb, Vector3(base.x, y + BOLE_H * 0.5, base.z) + fb * Vector3(hx, 0.0, -0.45)), Vector3(BOLE_W, BOLE_H, depth - 1.1))
		y += BOLE_H
		# the course over the row, a lip proud of the face
		sw.block(Transform3D(fb, Vector3(base.x, y + 0.16, base.z) + fb * Vector3(0.0, 0.0, 0.06)), Vector3(span + 0.2, 0.32, depth + 0.12))
		y += 0.32
	sw.block(Transform3D(fb, Vector3(base.x, y + 0.5, base.z) + fb * Vector3(0.0, 0.0, -0.2)), Vector3(span - 0.6, 1.0, depth - 0.4))
	_sites()._commit(d, sw, null, "BoleFace", true)
	k.collider(Vector3(span, y - base.y + 1.0, depth), Transform3D(fb, base + Vector3.UP * (y - base.y + 1.0) * 0.5), "stone")
	# the boles' shadow, the skeps in them (all but the top row), and each row's clan colour daubed
	var dark := m.begin()
	var straw := m.begin()
	var daub := m.begin()
	var bone := m.begin()
	for h in holes:
		var r := int(h[0])
		var at: Vector3 = h[1]
		m.block(dark, Transform3D(fb, at + Vector3.UP * BOLE_H * 0.5 + fb * Vector3(0.0, 0.0, -0.1)), Vector3(BOLE_W * 0.96, BOLE_H * 0.96, 0.04))
		if r < BOLE_ROWS - 1 and k.rng.randf() > 0.08:
			m.ellipsoid(straw, at + Vector3.UP * 0.05 + fb * Vector3(0.0, 0.0, 0.18), Vector3(0.3, 0.45, 0.3))
	for r in BOLE_ROWS:
		var ry := base.y + 1.8 + float(r + 1) * (BOLE_H + 0.32) - 0.02
		for c in 3:
			var x := (float(c) - 1.0) * span * 0.32
			m.block(bone if r == BOLE_ROWS - 1 else daub, Transform3D(fb, Vector3(base.x, ry, base.z) + fb * Vector3(x, 0.0, depth * 0.5 + 0.13)), Vector3(0.9, 0.2, 0.02))
	# on the ground at the foot: the bee-master's spare skeps stacked, his smoker, his daub-pot
	var foot0 := wall_at + out * (depth * 0.5 + 2.0) + side * (span * 0.5 - 1.0)
	for i in 3:
		m.ellipsoid(straw, k.on_ground(foot0.x, foot0.y, 0.25 + 0.42 * float(i)), Vector3(0.3, 0.3, 0.3))
	m.block(dark, Transform3D(fb, k.on_ground(foot0.x - side.x * 1.2, foot0.y - side.y * 1.2, 0.2)), Vector3(0.22, 0.4, 0.22))
	m.block(daub, Transform3D(fb, k.on_ground(foot0.x - side.x * 1.7, foot0.y - side.y * 1.7, 0.12)), Vector3(0.24, 0.24, 0.24))
	m.block(bone, Transform3D(fb, k.on_ground(foot0.x - side.x * 2.1, foot0.y - side.y * 2.1, 0.1)), Vector3(0.2, 0.2, 0.2))
	await k.step()
	m.commit(dark, PoiKit.plain(Color(0.05, 0.045, 0.04), 0.95), "BoleShadow")
	await k.step()
	m.commit(straw, PoiKit.painted(5, STRAW, 0.6, 0.8), "Skeps", true)
	await k.step()
	m.commit(daub, PoiKit.plain(OCHRE, 0.9), "ClanDaubs")
	m.commit(bone, PoiKit.plain(Color(0.86, 0.84, 0.78), 0.9), "BoneDaub")
	if k.far:
		return
	# the bees: a slow gold drift in front of the face
	k.puffs(Vector3(base.x, base.y + 4.0, base.z) + Vector3(out.x, 0.0, out.y) * (depth * 0.5 + 1.6), Vector3(span * 0.4, 2.6, 1.2), 0.4, 70,
			Color(0.95, 0.75, 0.25, 0.9), 0.07, 3.0)
	# Bannoch's hut off to one side, his smoker and his bench before the face
	var hut := wall_at + side * (span * 0.5 + 6.0) + out * 5.0
	var door: Vector2 = await _bothy(d, hut, (out - side * 0.5).normalized(), 4.2, 3.4)
	_spot(d, "bannoch_hut", door + out * 0.6)
	var foot := wall_at + out * (depth * 0.5 + 2.4)
	await _prop(d, "bench", foot - side * 3.0, PoiKit.yaw_of(-out))
	await _prop(d, "bucket", foot - side * 1.8 + out * 0.4, 0.4)
	await _prop(d, "basket", foot + side * 2.4, 1.1)
	_spot(d, "bannoch_boles", foot + side * 0.8 + out * 0.6)
	k.touchable("the_boles", Vector3(foot.x, base.y + 2.6, foot.y) - Vector3(out.x, 0.0, out.y) * 1.2, "Look at the bee-boles", DIALOGUE + "bee_bole_boles", "", false)


# --- the Scour -----------------------------------------------------------------------------------------

## The Scour: up the fell a turf dam holding a black pond, a sluice of oak in its throat with a windlass
## on a gantry; below it a raw white gash torn down the fellside by the last flood, bare stone and broken
## rock and boulders the water rolled; at its foot the hushers' sorting-floor with heaps of ore, a sieve
## on its frame, and Wat's tent.
static func the_scour(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var up := k.uphill()
	if up == Vector2.ZERO:
		up = -_facing(k)
	up = up.normalized()
	var side := Vector2(up.y, -up.x)
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(-up))
	# the dam: a long bank of turf across the fell, its throat in the middle
	var dam := up * 13.0
	var gd := k.on_ground(dam.x, dam.y).y
	var turf := m.begin()
	for s in [-1.0, 1.0]:
		var c := dam + side * (5.2 * float(s))
		m.ellipsoid(turf, Vector3(c.x, gd - 0.4, c.y), Vector3(4.6, 2.6, 2.6), fb)
	k.collider(Vector3(9.0, 2.2, 3.4), Transform3D(fb, Vector3(dam.x, gd + 1.0, dam.y) + Vector3(side.x, 0.0, side.y) * 5.2), "dirt")
	k.collider(Vector3(9.0, 2.2, 3.4), Transform3D(fb, Vector3(dam.x, gd + 1.0, dam.y) - Vector3(side.x, 0.0, side.y) * 5.2), "dirt")
	await k.step()
	m.commit(turf, PoiKit.painted(5, TURF, 0.75), "DamBank", true)
	# the pond behind it, brimming
	var pond := up * 19.0
	if not k.far:
		var water := m.pool(pond, 7.0, k.on_ground(pond.x, pond.y).y + 0.12, PoiKit.plain(Color(0.06, 0.07, 0.075), 0.08, 0.0), "Pond", 28)
		if water != null:
			water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the sluice: two oak cheeks in the throat, the plank gate between them shut, a gantry over it and
	# the windlass that lifts the gate
	var oak := m.begin()
	var tops: Array = []
	for s in [-1.0, 1.0]:
		tops.append(m.post(oak, dam + side * (0.9 * float(s)), 4.4, 0.32))
	var mid: Vector3 = ((tops[0] as Vector3) + (tops[1] as Vector3)) * 0.5
	m.block(oak, Transform3D(fb, mid + Vector3.UP * 0.15), Vector3(2.6, 0.3, 0.4))
	for i in 7:
		m.block(oak, Transform3D(fb, Vector3(dam.x, gd + 0.25 + 0.3 * float(i), dam.y)), Vector3(1.55, 0.27, 0.12))
	k.collider(Vector3(1.6, 2.1, 0.2), Transform3D(fb, Vector3(dam.x, gd + 1.05, dam.y)), "wood")
	var drum := mid + Vector3.UP * 0.62
	m.rod(oak, Transform3D(fb * Basis(Vector3.BACK, PI * 0.5), drum), 0.2, 1.6)
	for s in [-1.0, 1.0]:
		m.block(oak, Transform3D(fb, drum + fb * Vector3(0.95 * float(s), -0.3, 0.0)), Vector3(0.12, 0.8, 0.12))
		m.block(oak, Transform3D(fb, drum + fb * Vector3(1.1 * float(s), 0.0, 0.35)), Vector3(0.06, 0.06, 0.6))
	m.limb(oak, drum, Vector3(dam.x, gd + 2.4, dam.y), 0.03)
	await k.step()
	m.commit(oak, PoiKit.painted(3, OAK_BLACK, 0.75), "Sluice", true)
	# the gash: the fell flayed to its bones from the dam's foot down, pale, broken, strewn
	var gash := m.begin()
	var pts: Array = []
	for i in 9:
		var t := float(i) / 8.0
		pts.append(dam - up * (2.0 + 32.0 * t) + side * (1.6 * sin(t * 4.0)))
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var t := float(i) / float(pts.size() - 1)
		_track(d, gash, [a, b], lerpf(4.0, 7.5, t))
	await k.step()
	_ground_mesh(d, gash, PoiKit.painted(5, GRAVEL, 0.9, 0.8), "TheGash", true)
	if k.far:
		return
	var scree := k.rock("scree")
	if scree != "":
		var rows: Array = []
		for i in 8:
			var p: Vector2 = (pts[1 + i % 7] as Vector2) + side * k.rng.randf_range(-2.2, 2.2)
			rows.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.15), k.rng.randf() * TAU, k.rng.randf_range(0.6, 0.9)))
		await k.step()
		k.scatter(scree, rows, false)
	for i in 6:
		var p: Vector2 = (pts[2 + i] as Vector2) + side * k.rng.randf_range(-3.0, 3.0)
		var rock := k.rock("boulder", i % 3)
		if rock != "":
			await k.step()
			k.place(rock, k.on_ground(p.x, p.y, -0.1), k.rng.randf() * TAU, k.rng.randf_range(0.45, 0.7), true)
	# the sorting-floor beside the gash's foot: ore in heaps, a sieve on its frame, the tent
	var floor_at: Vector2 = (pts[7] as Vector2) + side * 7.0
	var ore := m.begin()
	for i in 3:
		_heap(d, ore, floor_at + side * (1.8 * float(i) - 1.8) + up * 1.6, 0.9, 0.55, 3)
	await k.step()
	m.commit(ore, PoiKit.painted(5, {"base": "#55585c", "accent": "#3e4145", "grout": "#26282b", "unit": 0.25}, 0.6), "OreHeaps")
	var sieve := m.begin()
	var sv := floor_at - up * 1.4
	for s in [-1.0, 1.0]:
		m.post(sieve, sv + side * (0.7 * float(s)), 1.0, 0.08)
	m.block(sieve, Transform3D(fb * Basis(Vector3.RIGHT, 0.25), k.on_ground(sv.x, sv.y, 0.95)), Vector3(1.6, 0.08, 1.0))
	await k.step()
	m.commit(sieve, PoiKit.painted(3, OAK_BLACK, 0.7), "Sieve")
	await _prop(d, "tent", floor_at + side * 5.0 - up * 1.0, PoiKit.yaw_of(-side))
	await _prop(d, "campfire", floor_at + side * 3.0 - up * 3.2, 0.0, 0.8)
	await _prop(d, "wheelbarrow", floor_at - side * 2.6, PoiKit.yaw_of(up))
	_spot(d, "wat_sluice", dam - up * 3.2 + side * 2.4)
	_spot(d, "home", floor_at + side * 4.0 - up * 2.2)
	k.touchable("the_sluice", Vector3(dam.x, gd + 1.3, dam.y) - Vector3(up.x, 0.0, up.y) * 1.0, "Look at the sluice", DIALOGUE + "scour_sluice", "", false)
	k.marker("the_gash", k.on_ground((pts[4] as Vector2).x, (pts[4] as Vector2).y))


# --- the Black-Rent Pillar ----------------------------------------------------------------------------------

## The Black-Rent Pillar: a lone limestone pillar by the Rudd road, nine metres of bedded stone, hung with
## black rags and set with iron spikes; an iron arm at its top with a pulley, the rope down it to the
## basket at its foot, tally-sticks jammed into every crack round the rope; Isbel's bench and her sack.
static func black_rent_pillar(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var out := _facing(k)
	var side := Vector2(out.y, -out.x)
	var c := -out * 3.0
	var g := k.on_ground(c.x, c.y).y
	# the pillar: beds of limestone, each a little narrower and turned, leaning a hand to the east
	var sw: Variant = _sites().Stones.new(k, d.poi_id.hash() + 17)
	var y := g - 0.8
	var lean := Vector3(0.05, 0.0, 0.03)
	var beds := 8
	var tops := Vector3.ZERO
	for i in beds:
		var h := 1.15 + k.rng.randf_range(-0.1, 0.25)
		var r := lerpf(2.1, 1.25, float(i) / float(beds - 1))
		var at := Vector3(c.x, y + h * 0.5, c.y) + lean * (y - g)
		var turn := Basis(Vector3.UP, k.rng.randf() * TAU)
		sw.top = g + 9.2
		sw.block(Transform3D(turn, at), Vector3(r * 1.8, h, r * 1.5))
		sw.block(Transform3D(turn * Basis(Vector3.UP, 0.9), at + turn * Vector3(0.2, 0.0, -0.1)), Vector3(r * 1.3, h * 0.92, r * 1.6))
		k.collider(Vector3(r * 1.6, h, r * 1.5), Transform3D(turn, at), "stone")
		y += h
		tops = at + Vector3.UP * h * 0.5
	_sites()._commit(d, sw, null, "Pillar", true)
	# the arm and the pulley at the top, the rope down to the basket, all one dark piece with the basket
	# and the stake the rope is tied off to
	var iron := m.begin()
	var tip := tops + Vector3(out.x, 0.0, out.y) * 1.9 + Vector3.UP * 0.3
	m.limb(iron, tops + Vector3.UP * 0.1, tip, 0.07)
	m.limb(iron, tops - Vector3.UP * 0.7 + Vector3(out.x, 0.0, out.y) * 0.6, tip, 0.05)
	m.rod(iron, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)) * Basis(Vector3.BACK, PI * 0.5), tip + Vector3.DOWN * 0.2), 0.22, 0.08)
	var basket_at := c + out * 1.9
	var bg := k.on_ground(basket_at.x, basket_at.y).y
	m.limb(iron, tip + Vector3.DOWN * 0.35, Vector3(basket_at.x, bg + 0.75, basket_at.y), 0.025)
	var stake := c + out * 1.4 + side * 1.6
	m.limb(iron, tip + Vector3.DOWN * 0.35 + Vector3(side.x, 0.0, side.y) * 0.1, k.on_ground(stake.x, stake.y, 0.5), 0.025)
	m.limb(iron, k.on_ground(stake.x, stake.y, -0.2), k.on_ground(stake.x, stake.y, 0.6), 0.05)
	# the spikes, driven into the beds all the way up
	for i in 10:
		var a := TAU * float(i) / 10.0 + 0.3
		var h := g + 1.5 + 0.75 * float(i)
		var r := lerpf(1.6, 1.0, float(i) / 9.0)
		var base := Vector3(c.x + sin(a) * r, h, c.y + cos(a) * r) + lean * (h - g)
		m.limb(iron, base, base + Vector3(sin(a), 0.15, cos(a)) * 0.6, 0.03)
	await k.step()
	m.commit(iron, PoiKit.plain(IRON, 0.6, 0.5), "PulleyAndRope", true)
	var basket := m.begin()
	var bb := Vector3(basket_at.x, bg + 0.32, basket_at.y)
	for i in 10:
		var a := TAU * float(i) / 10.0
		m.block(basket, Transform3D(Basis(Vector3.UP, a), bb + Vector3(sin(a), 0.0, cos(a)) * 0.5), Vector3(0.3, 0.62, 0.05))
	m.block(basket, Transform3D(Basis.IDENTITY, bb + Vector3.DOWN * 0.28), Vector3(0.95, 0.06, 0.95))
	# the tally-sticks jammed in the cracks round the rope, and stuck in the turf at the foot
	for i in 26:
		var a := k.rng.randf() * TAU
		var h := g + k.rng.randf_range(0.0, 2.2)
		var r := 1.8 if h > g + 0.3 else k.rng.randf_range(2.2, 3.4)
		var p := Vector3(c.x + sin(a) * r, h, c.y + cos(a) * r)
		if h <= g + 0.3:
			p.y = k.on_ground(p.x, p.z).y - 0.1
		m.block(basket, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.4, 0.4)), p + Vector3.UP * 0.2), Vector3(0.04, 0.45, 0.04))
	await k.step()
	m.commit(basket, PoiKit.painted(5, STRAW, 0.7), "BasketAndSticks")
	k.collider(Vector3(1.1, 0.7, 1.1), Transform3D(Basis.IDENTITY, bb), "wood")
	# the black rags tied up it, flying
	var rags := m.begin()
	for i in 14:
		var a := k.rng.randf() * TAU
		var h := g + 1.8 + k.rng.randf() * 6.8
		var r := lerpf(1.7, 1.1, (h - g) / 9.0)
		var at := Vector3(c.x + sin(a) * r, h, c.y + cos(a) * r) + lean * (h - g)
		m.block(rags, Transform3D(Basis(Vector3.UP, a + PI * 0.5) * Basis(Vector3.BACK, k.rng.randf_range(-0.4, 0.4)), at + Vector3(0.5, -0.1, 0.0)), Vector3(1.0, 0.35, 0.02))
	await k.step()
	m.commit(rags, PoiKit.plain(Color(0.07, 0.065, 0.06), 0.9), "BannerRags", true)
	if k.far:
		return
	# Isbel's place: the bench in the pillar's lee, her sack, a blanket
	var seat := c + side * 3.6 + out * 2.0
	await _prop(d, "bench", seat, PoiKit.yaw_of(-side))
	await _prop(d, "sack", seat - out * 1.0 + side * 0.4, 0.3)
	await _prop(d, "bedroll", seat + side * 1.6, PoiKit.yaw_of(out))
	_spot(d, "isbel_seat", seat + side * 0.9 + out * 0.2)
	k.touchable("the_basket", bb + Vector3.UP * 0.6, "Look at the rent-basket", DIALOGUE + "black_rent_pillar_basket", "", false)
	k.marker("the_pillar_foot", k.on_ground(c.x + out.x * 3.2 - side.x * 2.0, c.y + out.y * 3.2 - side.y * 2.0))


# --- the Bucket-Line ---------------------------------------------------------------------------------------

const LINE_HALF_M := 19.0
const TRESTLE_M := 10.0

## The Bucket-Line: two trestles of timber forty metres apart across the dale floor, a cable slung between
## their heads both ways with iron buckets riding it, full going down and empty coming back; at the upper
## trestle the treadwheel in its frame, at the lower a chute and a red heap of ore; Grett's crossbow and
## stool by the wheel.
static func the_bucket_line(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var along := k.downhill()
	if along == Vector2.ZERO:
		along = k.grain()
	if along == Vector2.ZERO:
		along = Vector2(0.0, 1.0)
	along = along.normalized()
	var across := Vector2(along.y, -along.x)
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(along))
	var ends := [-along * LINE_HALF_M, along * LINE_HALF_M]
	var timber := m.begin()
	var heads: Array = []
	for e in ends:
		var at: Vector2 = e
		var g := k.on_ground(at.x, at.y).y
		var top := Vector3(at.x, g + TRESTLE_M, at.y)
		# four legs raking in to the head, braced in two stages
		var feet: Array = []
		for sa in [-1.0, 1.0]:
			for sb in [-1.0, 1.0]:
				var f := at + along * (1.5 * float(sa)) + across * (1.7 * float(sb))
				feet.append(k.on_ground(f.x, f.y, -0.3))
		for f in feet:
			var fv: Vector3 = f
			var head := top + (Vector3(fv.x, 0.0, fv.z) - Vector3(at.x, 0.0, at.y)) * 0.25
			_pole(d, timber, fv, head, 0.16)
		for lvl in [0.33, 0.66]:
			for i in 4:
				var a: Vector3 = feet[i]
				var b: Vector3 = feet[[1, 3, 0, 2][i]]
				var ta := a.lerp(top + (Vector3(a.x, 0.0, a.z) - Vector3(at.x, 0.0, at.y)) * 0.25, float(lvl))
				var tb := b.lerp(top + (Vector3(b.x, 0.0, b.z) - Vector3(at.x, 0.0, at.y)) * 0.25, float(lvl))
				m.limb(timber, ta, tb, 0.08)
		m.block(timber, Transform3D(fb, top + Vector3.UP * 0.2), Vector3(2.4, 0.3, 0.9))
		m.rod(timber, Transform3D(fb * Basis(Vector3.BACK, PI * 0.5), top + Vector3.UP * 0.55), 0.45, 0.2)
		heads.append(top + Vector3.UP * 0.55)
	# the treadwheel at the upper trestle, on the side away from the line: two rims, slats, spokes, its frame
	var wheel_at: Vector2 = (ends[0] as Vector2) - along * 5.5
	var wg := k.on_ground(wheel_at.x, wheel_at.y).y
	var hub := Vector3(wheel_at.x, wg + 2.8, wheel_at.y)
	var wb := Basis(Vector3.UP, PoiKit.yaw_of(across))
	for s in [-1.0, 1.0]:
		var o := wb * Vector3(0.0, 0.0, 0.85 * float(s))
		for i in 18:
			var a0 := TAU * float(i) / 18.0
			var a1 := TAU * float(i + 1) / 18.0
			var p0 := hub + o + fb * Vector3(0.0, cos(a0) * 2.5, sin(a0) * 2.5)
			var p1 := hub + o + fb * Vector3(0.0, cos(a1) * 2.5, sin(a1) * 2.5)
			m.limb(timber, p0, p1, 0.07)
		for i in 6:
			var a := TAU * float(i) / 6.0
			m.limb(timber, hub + o, hub + o + fb * Vector3(0.0, cos(a) * 2.5, sin(a) * 2.5), 0.06)
		# the frame's A either side
		var fs := wheel_at + across * (1.3 * float(s))
		for t in [-1.0, 1.0]:
			var ft := fs + along * (1.6 * float(t))
			m.limb(timber, k.on_ground(ft.x, ft.y, -0.2), hub + wb * Vector3(0.0, 0.0, 1.25 * float(s)), 0.12)
		k.collider(Vector3(0.3, 2.8, 3.2), Transform3D(fb, Vector3(fs.x, wg + 1.4, fs.y)), "wood")
	for i in 24:
		var a := TAU * float(i) / 24.0
		m.block(timber, Transform3D(wb * Basis(Vector3.BACK, 0.0), hub + fb * Vector3(0.0, cos(a) * 2.42, sin(a) * 2.42)), Vector3(0.12, 0.12, 1.9))
	m.rod(timber, Transform3D(wb * Basis(Vector3.RIGHT, PI * 0.5), hub), 0.14, 2.8)
	# the drive rope from the axle up to the trestle head's drum
	m.limb(timber, hub, heads[0] as Vector3, 0.035)
	# the chute at the lower end, and its posts
	var chute: Vector2 = (ends[1] as Vector2) + along * 3.5
	var cg := k.on_ground(chute.x, chute.y).y
	for s in [-1.0, 1.0]:
		m.post(timber, chute + across * (0.7 * float(s)) - along * 1.6, 3.2, 0.14)
		m.post(timber, chute + across * (0.7 * float(s)) + along * 1.6, 1.4, 0.14)
	m.block(timber, Transform3D(fb * Basis(Vector3.RIGHT, -0.6), Vector3(chute.x, cg + 2.4, chute.y)), Vector3(1.5, 0.1, 3.8))
	await k.step()
	m.commit(timber, k.surface("timber", 0.75), "Trestles", true)
	k.collider(Vector3(3.2, 1.0, 1.0), Transform3D(fb, hub + Vector3.DOWN * 2.3), "wood")
	# the winding cable, both ways, and the buckets on it: full going down, empty coming back
	var cable := m.begin()
	var bucket := m.begin()
	var a3: Vector3 = heads[0]
	var b3: Vector3 = heads[1]
	for s in [-1.0, 1.0]:
		var o := Vector3(across.x, 0.0, across.y) * (0.6 * float(s))
		_line(m, cable, a3 + o, b3 + o, 0.04, 1.6, 12)
		for i in 5:
			var t := (float(i) + 0.5 + (0.0 if s < 0.0 else 0.4)) / 5.4
			var p := (a3 + o).lerp(b3 + o, t) + Vector3.DOWN * 1.6 * 4.0 * t * (1.0 - t)
			m.limb(cable, p, p + Vector3.DOWN * 0.9, 0.025)
			m.block(bucket, Transform3D(fb, p + Vector3.DOWN * 1.25), Vector3(0.6, 0.55, 0.5))
	await k.step()
	m.commit(cable, PoiKit.plain(IRON, 0.5, 0.6), "WindingCable", true)
	await k.step()
	m.commit(bucket, PoiKit.plain(RUST, 0.7, 0.3), "WindingCableBuckets", true)
	if k.far:
		return
	# the ore heap under the chute's mouth
	var ore := m.begin()
	_heap(d, ore, chute + along * 3.2, 2.2, 1.3, 5)
	await k.step()
	m.commit(ore, PoiKit.painted(5, ORE, 0.6), "OreHeap")
	# Grett's place by the wheel: a stool, her crossbow on a peg, a coil of spare rope
	var stool := wheel_at + across * 3.2 + along * 0.8
	await _prop(d, "stool", stool, PoiKit.yaw_of(-across))
	await _prop(d, "rope_coil", stool + along * 1.2, 0.4)
	await _prop(d, "crate", stool - along * 1.6 + across * 0.6, PoiKit.yaw_of(along))
	_spot(d, "grett_wheel", stool - across * 0.8)
	_spot(d, "home", stool + across * 1.4)
	k.touchable("the_wheel", hub + Vector3.DOWN * 1.8 + Vector3(across.x, 0.0, across.y) * 1.4, "Look at the treadwheel", DIALOGUE + "bucket_line_wheel", "", false)
	k.marker("the_chute", k.on_ground(chute.x + across.x * 2.6, chute.y + across.y * 2.6))


# --- the Breath-Ledge --------------------------------------------------------------------------------------

const LEDGE_W := 18.0
const LEDGE_H := 11.0

## The Breath-Ledge: a pale scar of bedded limestone on the Skarl fells, and on its face the Skarl dead in
## their coffins, set on iron pegs as high as the ropes would lift them, the oldest grey as the rock and
## the newest yellow; a long ladder against it, a beam at its top with the hanging-ropes down to the foot,
## and at the foot the broken boards of the coffin that fell, and Mags's ropes and her peg-hammer.
static func the_breath_ledge(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var out := _facing(k)
	var side := Vector2(out.y, -out.x)
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(out))
	var face_at := -out * 7.0
	# the crag behind, for the hill's own shoulder; the scar in front of it in beds of pale stone, each
	# bed stepped back and broken along its top
	await _crag(d, face_at - out * 6.0, out, 15.0, 0, 1.6)
	var gb := INF
	for s in [-0.5, -0.25, 0.0, 0.25, 0.5]:
		var p := face_at + side * LEDGE_W * float(s)
		gb = minf(gb, k.on_ground(p.x, p.y).y)
	var sw: Variant = _sites().Stones.new(k, d.poi_id.hash() + 29)
	sw.top = gb + LEDGE_H
	var beds := 9
	var y := gb - 0.8
	var bed_h := (LEDGE_H + 0.8) / float(beds)
	for i in beds:
		var back := 0.12 * float(i)
		var n := 6
		for j in n:
			var w := LEDGE_W / float(n) * k.rng.randf_range(0.95, 1.15)
			var x := -LEDGE_W * 0.5 + LEDGE_W * (float(j) + 0.5) / float(n)
			var hj := bed_h * (1.0 if i < beds - 1 else k.rng.randf_range(0.5, 1.4))
			var at := Vector3(face_at.x, y + hj * 0.5, face_at.y) + fb * Vector3(x, 0.0, -back + k.rng.randf_range(-0.12, 0.12))
			sw.block(Transform3D(fb * Basis(Vector3.UP, k.rng.randf_range(-0.04, 0.04)), at), Vector3(w, hj, 3.2))
		y += bed_h
	_sites()._commit(d, sw, null, "Scar", true)
	k.collider(Vector3(LEDGE_W, LEDGE_H + 0.8, 3.2), Transform3D(fb, Vector3(face_at.x, gb + (LEDGE_H - 0.8) * 0.5, face_at.y)), "stone")
	# the coffins on their pegs, high on the face; the old ones grey, the new yellow. Each coffin's pegs
	# go in with it, and the ladder and the ropes that put them there stand on the ground in the same piece
	var old := m.begin()
	var new_wood := m.begin()
	var front := 1.6
	var slots := [[-6.5, 9.6], [-3.2, 10.1], [0.4, 9.4], [4.0, 10.3], [7.0, 9.0], [-7.4, 7.4], [-4.6, 7.9],
			[-1.2, 7.2], [2.4, 8.1], [5.6, 7.0], [-5.8, 5.6], [1.0, 5.4], [-2.6, 9.9]]
	for i in slots.size():
		var sl: Array = slots[i]
		var st := new_wood if i % 5 == 1 or i == 11 else old
		var at := Vector3(face_at.x, gb + float(sl[1]), face_at.y) + fb * Vector3(float(sl[0]), 0.0, _ledge_face(float(sl[1]), bed_h) + 0.36)
		var tilt := Basis(Vector3.BACK, k.rng.randf_range(-0.05, 0.05))
		m.block(st, Transform3D(fb * tilt, at), Vector3(2.0, 0.5, 0.62))
		m.block(st, Transform3D(fb * tilt, at + Vector3.UP * 0.29), Vector3(2.08, 0.08, 0.7))
	var iron := m.begin()
	for i in slots.size():
		var sl: Array = slots[i]
		for s in [-0.7, 0.7]:
			var p := Vector3(face_at.x, gb + float(sl[1]) - 0.3, face_at.y) + fb * Vector3(float(sl[0]) + float(s), 0.0, _ledge_face(float(sl[1]), bed_h) + 0.2)
			m.block(iron, Transform3D(fb, p), Vector3(0.08, 0.08, 0.9))
	# the beam at the top with its ropes down to the foot, and the long ladder
	var rope := m.begin()
	var beam_y := gb + LEDGE_H + 0.3
	for s in [-1.0, 1.0]:
		var bx := 3.5 * float(s)
		var tip := Vector3(face_at.x, beam_y + 0.6, face_at.y) + fb * Vector3(bx, 0.0, front + 1.2)
		m.limb(iron, Vector3(face_at.x, beam_y, face_at.y) + fb * Vector3(bx, 0.0, -0.8), tip, 0.08)
		var foot := Vector3(face_at.x, 0.0, face_at.y) + fb * Vector3(bx + 0.4, 0.0, front + 2.0)
		foot.y = k.on_ground(foot.x, foot.z).y
		m.limb(rope, tip, foot + Vector3.UP * 0.1, 0.03)
		m.ellipsoid(rope, foot + Vector3.UP * 0.12, Vector3(0.45, 0.12, 0.45))
	var lf := Vector3(face_at.x, 0.0, face_at.y) + fb * Vector3(-1.8, 0.0, front + 2.2)
	lf.y = k.on_ground(lf.x, lf.z).y
	_ladder(m, old, lf, Vector3(face_at.x, gb + 9.4, face_at.y) + fb * Vector3(-1.8, 0.0, _ledge_face(9.4, bed_h) + 0.15), 0.55)
	# iron and rope each with a foot on the ground: the pegs' spare rods leant at the scar's foot
	var spare := Vector3(face_at.x, 0.0, face_at.y) + fb * Vector3(6.0, 0.0, front + 0.9)
	spare.y = k.on_ground(spare.x, spare.z).y
	for i in 4:
		m.limb(iron, spare + fb * Vector3(0.12 * float(i), 0.0, 0.0), spare + fb * Vector3(0.12 * float(i), 0.0, -0.5) + Vector3.UP * 1.3, 0.03)
	# a new coffin waiting on two trestles at the scar's foot, in the new wood
	var wait2 := Vector3(face_at.x, 0.0, face_at.y) + fb * Vector3(-5.2, 0.0, front + 3.2)
	wait2.y = k.on_ground(wait2.x, wait2.z).y
	for s in [-0.7, 0.7]:
		var tp := wait2 + fb * Vector3(float(s), 0.35, 0.0)
		m.block(new_wood, Transform3D(fb, tp), Vector3(0.1, 0.7, 0.7))
	m.block(new_wood, Transform3D(fb, wait2 + Vector3.UP * 0.95), Vector3(2.0, 0.5, 0.62))
	m.block(new_wood, Transform3D(fb, wait2 + Vector3.UP * 1.24), Vector3(2.08, 0.08, 0.7))
	k.collider(Vector3(2.1, 1.3, 0.7), Transform3D(fb, wait2 + Vector3.UP * 0.65), "wood")
	await k.step()
	m.commit(old, PoiKit.painted(3, {"base": "#8b877c", "accent": "#6c695f", "grout": "#46443d", "unit": 0.3}, 0.8), "Coffins", true)
	await k.step()
	m.commit(new_wood, PoiKit.painted(3, {"base": "#b99a5c", "accent": "#957a46", "grout": "#5c4a2a", "unit": 0.3}, 0.4), "NewCoffins", true)
	await k.step()
	m.commit(iron, PoiKit.plain(IRON, 0.6, 0.5), "Pegs", true)
	await k.step()
	m.commit(rope, PoiKit.plain(Color(0.5, 0.45, 0.36), 0.9), "Ropes")
	if k.far:
		return
	# the fallen coffin's boards, broken on the scree
	var fall := face_at + out * 4.6 + side * 3.2
	var boards := m.begin()
	for i in 9:
		var p := fall + k.jitter(1.6)
		m.block(boards, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.2, 0.2)), k.on_ground(p.x, p.y, 0.06)),
				Vector3(k.rng.randf_range(0.8, 1.9), 0.05, 0.28))
	await k.step()
	m.commit(boards, PoiKit.painted(3, {"base": "#7d796f", "accent": "#5f5c54", "grout": "#3a3833", "unit": 0.3}, 0.9), "FallenBoards")
	var waiting := face_at + out * 5.5 - side * 4.0
	await _prop(d, "rope_coil", waiting + out * 1.6, 0.5)
	await _prop(d, "hammer", waiting + out * 1.2 + side * 1.4, 1.2)
	_spot(d, "mags_rope", waiting + out * 2.4 + side * 1.6)
	_spot(d, "home", waiting + out * 3.6 - side * 1.0)
	k.touchable("the_boards", k.on_ground(fall.x, fall.y, 0.6), "Look at the fallen boards", DIALOGUE + "breath_ledge_boards", "", false)
	k.marker("the_fallen_boards", k.on_ground(fall.x + out.x * 2.5, fall.y + out.y * 2.5))


## How far out of the scar's middle its face stands at `h` metres up: each bed is set back 0.12 m.
static func _ledge_face(h: float, bed_h: float) -> float:
	var bed := clampi(int((h + 0.8) / bed_h), 0, 8)
	return 1.6 - 0.12 * float(bed)


# --- the Answering Wall ------------------------------------------------------------------------------------

## The Answering Wall: a curve of white crag on a knoll, cupped like a hand toward the road, and facing it
## across a bowl of turf the speaking-stone with its worn step; at the wall's foot a row of name-stones
## daubed in ochre, and the callers' small cairns round the bowl.
static func the_answering_wall(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var out := _facing(k)
	var side := Vector2(out.y, -out.x)
	var bowl := out * 2.0
	# the wall: three faces on an arc round the bowl, each looking in at it
	for i in 3:
		var a := (float(i) - 1.0) * 0.78
		var dir := (-out).rotated(a)
		var at := bowl + dir * 17.5
		await _crag(d, at, -dir, 12.0, 0, 1.2)
	# the speaking-stone, its step worn into a hollow, facing the wall
	var ss := bowl + out * 6.5
	var stone := m.begin()
	var sg := k.on_ground(ss.x, ss.y).y
	var sb := Basis(Vector3.UP, PoiKit.yaw_of(-out))
	m.block(stone, Transform3D(sb, Vector3(ss.x, sg + 0.45, ss.y)), Vector3(1.6, 1.3, 1.2))
	m.block(stone, Transform3D(sb, Vector3(ss.x, sg + 0.2, ss.y) + sb * Vector3(0.0, 0.0, 0.9)), Vector3(1.3, 0.4, 0.6))
	k.collider(Vector3(1.6, 1.3, 1.2), Transform3D(sb, Vector3(ss.x, sg + 0.45, ss.y)), "stone")
	# the name-stones along the wall's foot
	var names: Array = []
	for i in 11:
		var a := (float(i) - 5.0) * 0.14
		var dir := (-out).rotated(a)
		var p := bowl + dir * 12.5
		var h := k.rng.randf_range(0.7, 1.3)
		var at := k.on_ground(p.x, p.y, h * 0.5 - 0.15)
		var b := Basis(Vector3.UP, PoiKit.yaw_of(-dir) + k.rng.randf_range(-0.2, 0.2))
		m.block(stone, Transform3D(b, at), Vector3(0.6, h, 0.25))
		names.append([at, b, h])
		k.collider(Vector3(0.6, h, 0.25), Transform3D(b, at), "stone")
	await k.step()
	m.commit(stone, PoiKit.painted(5, LIME_PALE, 0.7), "SpeakingStones", true)
	if k.far:
		return
	var ochre := m.begin()
	for n in names:
		var at: Vector3 = n[0]
		var b: Basis = n[1]
		var h := float(n[2])
		for j in 3:
			m.block(ochre, Transform3D(b, at + b * Vector3(k.rng.randf_range(-0.15, 0.15), h * (0.3 - 0.18 * float(j)), 0.135)), Vector3(0.34, 0.06, 0.01))
	# a daub at the foot of each: the ochre-pot the callers leave
	m.block(ochre, Transform3D(Basis.IDENTITY, k.on_ground(ss.x + side.x * 1.4, ss.y + side.y * 1.4, 0.14)), Vector3(0.26, 0.28, 0.26))
	await k.step()
	m.commit(ochre, PoiKit.plain(OCHRE, 0.9), "OchreNames")
	# the callers' cairns round the bowl
	var cairns := m.begin()
	for i in 7:
		var a := PI * 0.5 + float(i) * 0.33 - 1.0
		var p := bowl + out.rotated(a) * 9.0
		var y := k.on_ground(p.x, p.y).y - 0.05
		var r := 0.42
		for q in 4:
			m.ellipsoid(cairns, Vector3(p.x, y + r * 0.5, p.y), Vector3(r, r * 0.55, r * 0.9), Basis(Vector3.UP, k.rng.randf() * TAU))
			y += r * 0.7
			r *= 0.78
	await k.step()
	m.commit(cairns, k.surface("stone", 0.85), "CallersCairns")
	k.touchable("the_speaking_stone", Vector3(ss.x, sg + 1.4, ss.y) + Vector3(out.x, 0.0, out.y) * 0.9, "Stand on the speaking-stone", DIALOGUE + "answering_wall_stone", "", false)
	var top := bowl - out * 14.0 + side * 13.0
	k.marker("the_wall_top", k.on_ground(top.x, top.y))


# --- Corbie Stack --------------------------------------------------------------------------------------------

const STACK_COURSES := 12
const STACK_COURSE_M := 2.45

## Corbie Stack: a needle of bedded limestone thirty metres high alone on the high moor, each bed a little
## narrower and turned on the one under it; on its top the Rudd hold of drystone with a stone-slate roof,
## smoke going up from it and the reivers' black rag on a pole. Beside it a lower crag with steps up its
## side and two iron rings at its lip where the chain bridge was hung, and the bridge itself drawn up, its
## chains and planks hanging down the needle's side to the turf. At the needle's foot an iron-bound door
## cut into the rock, the reivers' roll on a post by it, and their fire under the lower crag.
static func corbie_stack(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var site := _site_of(d)
	var interior := str(site.get("interior", ""))
	var out := _facing(k)
	var side := Vector2(out.y, -out.x)
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(out))
	var c0 := -out * 5.0
	var g := INF
	for q in [Vector2.ZERO, out * 5.0, -out * 5.0, side * 5.0, -side * 5.0]:
		var p: Vector2 = c0 + q
		g = minf(g, k.on_ground(p.x, p.y).y)
	var sw: Variant = _sites().Stones.new(k, d.poi_id.hash() + 83)
	sw.top = g + STACK_COURSES * STACK_COURSE_M + 3.0
	# the needle: the first two beds square to the door, the rest turned and drawn in
	var y := g - 1.0
	var r0 := 6.2
	var top_r := 0.0
	for i in STACK_COURSES:
		var t := float(i) / float(STACK_COURSES - 1)
		var r := lerpf(r0, 3.9, t) * (1.0 + 0.06 * sin(float(i) * 1.7))
		var h := STACK_COURSE_M + (1.0 if i == 0 else 0.0)
		var turn := fb if i < 2 else fb * Basis(Vector3.UP, k.rng.randf_range(-0.5, 0.5))
		var at := Vector3(c0.x, y + h * 0.5, c0.y) + Vector3(k.rng.randf_range(-0.25, 0.25), 0.0, k.rng.randf_range(-0.25, 0.25)) * (0.0 if i < 2 else 1.0)
		sw.block(Transform3D(turn, at), Vector3(r * 2.0, h, r * 1.8))
		if i >= 2:
			sw.block(Transform3D(turn * Basis(Vector3.UP, 1.1), at + Vector3.UP * 0.05), Vector3(r * 1.7, h * 0.96, r * 1.9))
		else:
			sw.block(Transform3D(turn, at + turn * Vector3(0.0, 0.0, -0.8)), Vector3(r * 2.3, h * 0.97, r * 1.5))
		if i % 3 == 1:
			sw.block(Transform3D(turn * Basis(Vector3.UP, 0.5), at + turn * Vector3(r * 0.8, -0.2, -r * 0.4)), Vector3(r * 0.9, h * 0.8, r * 1.0))
		k.collider(Vector3(r * 1.8, h, r * 1.7), Transform3D(turn, at), "stone")
		y += h
		top_r = r
	var top_y := y
	# the hold on the top: four walls of drystone with a door gap, a stone-slate roof of two pitches
	var hold := Vector3(c0.x, top_y, c0.y)
	var hw := minf(top_r * 0.75, 2.9)
	var wall_h := 2.5
	var slate := Color(0.55, 0.55, 0.58)
	for s in [-1.0, 1.0]:
		sw.block(Transform3D(fb, hold + fb * Vector3(hw * float(s), wall_h * 0.5, 0.0)), Vector3(0.6, wall_h, hw * 2.0 + 0.6))
	sw.block(Transform3D(fb, hold + fb * Vector3(0.0, wall_h * 0.5, -hw)), Vector3(hw * 2.0, wall_h, 0.6))
	for s in [-1.0, 1.0]:
		sw.block(Transform3D(fb, hold + fb * Vector3((hw + 0.6) * 0.5 * float(s), wall_h * 0.5, hw)), Vector3(hw - 0.6, wall_h, 0.6))
	for s in [-1.0, 1.0]:
		var pitch := fb * Basis(Vector3.BACK, -0.5 * float(s))
		sw.block(Transform3D(pitch, hold + Vector3.UP * (wall_h + 0.75) + fb * Vector3(hw * 0.5 * float(s), 0.0, 0.0)), Vector3(hw * 1.25, 0.22, hw * 2.0 + 1.0), slate)
	# a chimney stack at the gable, and the parapet stones round the top's edge
	sw.block(Transform3D(fb, hold + fb * Vector3(0.0, wall_h + 1.3, -hw)), Vector3(0.8, 2.0, 0.8))
	for i in 10:
		var a := TAU * float(i) / 10.0
		var p := hold + Vector3(sin(a), 0.0, cos(a)) * (top_r * 0.88)
		if absf(PoiKit.yaw_of(out) - a) < 0.3:
			continue
		sw.block(Transform3D(Basis(Vector3.UP, a), p + Vector3.UP * 0.45), Vector3(1.2, 0.9, 0.6))
	k.collider(Vector3(hw * 2.0, wall_h, hw * 2.0), Transform3D(fb, hold + Vector3.UP * wall_h * 0.5), "stone")
	# the lower crag beside it, with steps up its side to the lip where the bridge was hung
	var crag := c0 + side * 13.5 + out * 1.5
	var cy := g - 0.8
	for i in 4:
		var r := 4.2 - 0.45 * float(i)
		var h := 2.2
		var at := Vector3(crag.x, cy + h * 0.5, crag.y)
		var turn := fb * Basis(Vector3.UP, 0.35 * float(i))
		sw.block(Transform3D(turn, at), Vector3(r * 2.0, h, r * 1.7))
		sw.block(Transform3D(turn * Basis(Vector3.UP, 0.9), at), Vector3(r * 1.6, h * 0.95, r * 1.9))
		k.collider(Vector3(r * 1.7, h, r * 1.6), Transform3D(turn, at), "stone")
		cy += h
	var lip := Vector3(crag.x, cy, crag.y) - Vector3(side.x, 0.0, side.y) * 2.6
	# the steps, up its outer side
	for i in 14:
		var t := float(i) / 13.0
		var p := crag + side * 3.6 - out * lerpf(3.4, -2.2, t)
		var tread := g + 0.6 * float(i + 1)
		var foot := minf(k.on_ground(p.x, p.y).y, g) - 0.5
		sw.block(Transform3D(fb, Vector3(p.x, (tread + foot) * 0.5, p.y)), Vector3(1.4, tread - foot, 0.7))
	_sites()._commit(d, sw, null, "CorbieStack", true)
	# the drawn-up bridge: its two chains from the needle's lip down its side, the planks hanging between
	# them, the last of them lying on the turf; and the chains' far ends hooked on the crag's rings
	var iron := m.begin()
	var planks := m.begin()
	var hang_dir := side
	var hang_r := r0 * 1.25 + 0.8
	var hang := Vector3(c0.x, top_y - 0.5, c0.y) + Vector3(hang_dir.x, 0.0, hang_dir.y) * hang_r
	# the gantry arm it was drawn up to, run out from the hold's edge
	for s in [-1.0, 1.0]:
		var o := Vector3(out.x, 0.0, out.y) * (0.75 * float(s))
		var root := Vector3(c0.x, top_y + 0.4, c0.y) + Vector3(hang_dir.x, 0.0, hang_dir.y) * (top_r * 0.6) + o
		m.limb(iron, root, hang + o + Vector3.UP * 0.4, 0.09)
		var foot2 := Vector3(c0.x, 0.0, c0.y) + Vector3(hang_dir.x, 0.0, hang_dir.y) * hang_r + o
		foot2.y = k.on_ground(foot2.x, foot2.z).y + 0.15
		_chain(m, iron, hang + o, foot2, 0.4)
		var ring := lip + o
		m.rod(iron, Transform3D(fb * Basis(Vector3.RIGHT, PI * 0.5), ring + Vector3.UP * 0.25), 0.22, 0.06)
		_chain(m, iron, ring + Vector3.UP * 0.1, ring - Vector3(side.x, 0.0, side.y) * 0.3 + Vector3.DOWN * 1.4, 0.4)
	var pb := Basis(Vector3.UP, PoiKit.yaw_of(out))
	var ground_at := Vector3(c0.x, 0.0, c0.y) + Vector3(hang_dir.x, 0.0, hang_dir.y) * hang_r
	ground_at.y = k.on_ground(ground_at.x, ground_at.z).y
	for i in 22:
		if i < 18:
			var p := hang.lerp(ground_at + Vector3.UP * 0.6, float(i) / 17.0)
			m.block(planks, Transform3D(pb, p), Vector3(0.08, 0.4, 1.6))
		else:
			var p := ground_at + Vector3(out.x, 0.0, out.y) * (1.6 + 0.45 * float(i - 18)) - Vector3(hang_dir.x, 0.0, hang_dir.y) * 0.4
			p.y = k.on_ground(p.x, p.z).y + 0.05
			m.block(planks, Transform3D(pb, p), Vector3(0.4, 0.08, 1.6))
	await k.step()
	m.commit(iron, PoiKit.plain(IRON, 0.55, 0.6), "DrawnBridgeChains", true)
	await k.step()
	m.commit(planks, k.surface("planks", 0.8), "DrawnBridgePlanks", true)
	# the black rag on its pole over the hold
	var rag := m.begin()
	var pole := hold + fb * Vector3(hw * 0.6, 0.0, hw * 0.6)
	m.limb(rag, pole, pole + Vector3.UP * 6.0, 0.08)
	m.block(rag, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(Vector2(1.0, 0.0))), pole + Vector3.UP * 5.2 + Vector3(0.9, 0.0, 0.0)), Vector3(1.8, 1.2, 0.03))
	await k.step()
	m.commit(rag, PoiKit.plain(Color(0.06, 0.055, 0.05), 0.9), "BlackBanner", true)
	# the door at the foot: jambs and a lintel of dressed stone proud of the rock, the dark of the cut
	# behind, and the iron-bound leaf standing a hand open
	var front := Vector3(c0.x, g, c0.y) + Vector3(out.x, 0.0, out.y) * (r0 * 0.9)
	var dark := m.begin()
	m.block(dark, Transform3D(fb, front + Vector3.UP * 1.25 + Vector3(out.x, 0.0, out.y) * 0.02), Vector3(1.5, 2.5, 0.06))
	var leaf := m.begin()
	var hinge := front + fb * Vector3(-0.75, 1.25, 0.15)
	var lb := fb * Basis(Vector3.UP, -0.35)
	m.block(leaf, Transform3D(lb, hinge + lb * Vector3(0.72, 0.0, 0.0)), Vector3(1.44, 2.4, 0.12))
	for i in 3:
		m.block(leaf, Transform3D(lb, hinge + lb * Vector3(0.72, -0.8 + 0.8 * float(i), 0.08)), Vector3(1.5, 0.1, 0.03))
	var jambs := m.begin()
	for s in [-1.0, 1.0]:
		m.block(jambs, Transform3D(fb, front + fb * Vector3(0.95 * float(s), 1.4, 0.15)), Vector3(0.45, 2.9, 0.5))
	m.block(jambs, Transform3D(fb, front + fb * Vector3(0.0, 3.05, 0.15)), Vector3(2.5, 0.5, 0.6))
	for i in 4:
		m.block(jambs, Transform3D(fb, front + fb * Vector3(0.0, 0.1 - 0.12 * float(i), 0.6 + 0.4 * float(i))), Vector3(2.0, 0.3, 0.45))
	await k.step()
	m.commit(jambs, _sites().stone_look(k, g), "DoorStones", true)
	m.commit(dark, PoiKit.plain(DARK, 0.95), "DoorDark")
	m.commit(leaf, PoiKit.painted(3, OAK_BLACK, 0.8), "DoorLeaf")
	if k.far:
		return
	if interior != "":
		_sites()._door(d, interior, front + Vector3.UP * 1.2 + Vector3(out.x, 0.0, out.y) * 0.5, PoiKit.yaw_of(out))
	k.light(front + Vector3.UP * 3.0 + Vector3(out.x, 0.0, out.y) * 0.5, Color(1.0, 0.62, 0.32), 1.2, 7.0)
	k.puffs(hold + fb * Vector3(0.0, wall_h + 2.6, -hw), Vector3(0.2, 0.2, 0.2), 4.0, 10, Color(0.3, 0.3, 0.3, 0.32), 2.0, 7.0)
	var hp := c0 + out * (r0 + 4.0) + side * 3.2
	await _sites()._hook(d, site, Vector3(hp.x, 0.0, hp.y))
	# the riders' fire under the lower crag, their bedrolls, their chest
	var fire := crag + out * 7.0 - side * 1.0
	await _prop(d, "campfire", fire, 0.0)
	k.light(k.on_ground(fire.x, fire.y, 0.6), Color(1.0, 0.6, 0.3), 1.8, 9.0)
	for i in 3:
		var a := PoiKit.yaw_of(side) + 0.8 * float(i) - 0.8
		await _prop(d, "bedroll", fire + Vector2(sin(a), cos(a)) * 2.8, a)
	await _prop(d, "sack", fire + side * 3.6 + out * 0.6, 0.4)
	await _container(d, "riders_chest", fire + side * 3.8 - out * 1.2, PoiKit.yaw_of(-side), "core:loot/common_chest", "The Riders' Chest")
	k.marker("the_bridge_crag", k.on_ground(fire.x + out.x * 2.0, fire.y + out.y * 2.0))
	k.marker("the_door", k.on_ground(front.x + out.x * 3.0, front.z + out.y * 3.0))


# --- the Unmade Giant ------------------------------------------------------------------------------------------

## The Unmade Giant: behind the warren's mouth, a giant twenty metres high being put together in a cage of
## scaffold poles: legs of boulders lashed with hair-rope on feet of toe-bones, a hip of bone, a spine and
## half a ribcage, a shoulder-bar with one arm hanging and the other socket empty, its skull hoisted half
## way up a gin-pole beside it; ladders and plank stages, the hags' lanterns on the ledgers, bones heaped
## at its feet; and Haskel ko-Ghast's camp off at the pad's edge with his tally-board.
static func the_unmade_giant(d: PoiDressing) -> void:
	var site := _site_of(d)
	await _sites().delve(d, site)
	var k := d.kit
	var m := d.masonry
	var into := Vector2.ZERO
	var mouth := d.find_child("the_mouth", true, false) as Node3D
	if mouth != null and Vector2(mouth.position.x, mouth.position.z).length() > 0.5:
		into = Vector2(mouth.position.x, mouth.position.z).normalized()
	else:
		var face := k.downhill()
		if face == Vector2.ZERO:
			face = -k.uphill()
		if face == Vector2.ZERO:
			face = k.grain()
		into = -face.normalized() if face != Vector2.ZERO else Vector2(0.0, -1.0)
	var fwd := -into
	var right := Vector2(fwd.y, -fwd.x)
	var gp := into * 18.0
	var gg := k.on_ground(gp.x, gp.y).y
	var gb := Basis(Vector3.UP, PoiKit.yaw_of(fwd))
	var G := Vector3(gp.x, gg, gp.y)
	var stone := m.begin()
	var bone := m.begin()
	var lash := m.begin()
	# the feet: toe-bones splayed on the turf; the legs: boulders stacked and lashed
	for sx in [-1.0, 1.0]:
		var x := 2.3 * float(sx)
		for t in 3:
			m.ellipsoid(bone, G + gb * Vector3(x + 0.5 * float(t - 1), 0.28, 1.4 + 0.3 * float(t % 2)), Vector3(0.38, 0.3, 1.2), gb)
		m.ellipsoid(bone, G + gb * Vector3(x, 0.4, 0.0), Vector3(1.1, 0.5, 1.0), gb)
		var yy := 0.95
		for b in 5:
			var rr := 1.35 - 0.05 * float(b)
			m.ellipsoid(stone, G + gb * Vector3(x + k.rng.randf_range(-0.15, 0.15), yy, k.rng.randf_range(-0.15, 0.15)), Vector3(rr, 0.95, rr * 0.95),
					gb * Basis(Vector3.UP, k.rng.randf() * TAU))
			if b < 4:
				m.ellipsoid(lash, G + gb * Vector3(x, yy + 0.8, 0.0), Vector3(rr * 1.02, 0.12, rr * 0.98), gb)
			yy += 1.6
		m.ellipsoid(lash, G + gb * Vector3(x, 0.15, 0.0), Vector3(1.25, 0.12, 1.15), gb)
		k.collider(Vector3(2.4, 8.4, 2.4), Transform3D(gb, G + gb * Vector3(x, 4.2, 0.0)), "stone")
	# the hip, the spine, the shoulder-bar and the neck's two bones
	m.ellipsoid(bone, G + gb * Vector3(0.0, 8.9, 0.0), Vector3(3.5, 1.35, 1.7), gb)
	k.collider(Vector3(6.4, 2.4, 3.0), Transform3D(gb, G + Vector3.UP * 8.9), "stone")
	for i in 7:
		m.ellipsoid(bone, G + gb * Vector3(0.0, 10.1 + 1.0 * float(i), -0.7), Vector3(0.8, 0.42, 0.7), gb)
	m.limb(bone, G + gb * Vector3(-3.7, 16.9, -0.4), G + gb * Vector3(3.7, 16.9, -0.4), 0.42)
	for i in 2:
		m.ellipsoid(bone, G + gb * Vector3(0.0, 17.6 + 0.7 * float(i), -0.5), Vector3(0.55, 0.3, 0.5), gb)
	# the ribs: five on its right, two on its left; the rest not yet found
	for sx in [1.0, -1.0]:
		var n := 5 if sx > 0.0 else 2
		for i in n:
			var y0 := 15.6 - 1.1 * float(i)
			var pts := [Vector3(0.0, y0, -0.6), Vector3(1.8, y0 - 0.2, -0.2), Vector3(2.6, y0 - 0.7, 0.8),
					Vector3(2.0, y0 - 1.3, 1.9), Vector3(0.9, y0 - 1.6, 2.3)]
			for j in pts.size() - 1:
				var a: Vector3 = pts[j]
				var b: Vector3 = pts[j + 1]
				m.limb(bone, G + gb * Vector3(a.x * float(sx), a.y, a.z), G + gb * Vector3(b.x * float(sx), b.y, b.z), lerpf(0.24, 0.15, float(j) / 3.0))
	# the right arm hanging: a bone to the elbow, lashed rock to the wrist, four finger-bones
	var sh := G + gb * Vector3(3.8, 16.5, 0.0)
	var el := G + gb * Vector3(4.4, 11.3, 0.4)
	var wr := G + gb * Vector3(4.2, 6.8, 1.2)
	m.limb(bone, sh, el, 0.48)
	m.ellipsoid(stone, el, Vector3(0.85, 0.8, 0.85))
	m.limb(stone, el, wr, 0.6)
	m.ellipsoid(lash, el.lerp(wr, 0.5), Vector3(0.72, 0.12, 0.72))
	for f in 4:
		var o := gb * Vector3(-0.45 + 0.3 * float(f), 0.0, 0.2)
		m.limb(bone, wr + o, wr + o + gb * Vector3(0.0, -1.6 - 0.2 * float(f % 2), 0.5), 0.13)
	# the skull, hoisted half-way up the gin-pole beside the neck: brow, cheeks, its sockets dark
	var skull := G + gb * Vector3(-3.4, 18.6, 1.2)
	m.ellipsoid(bone, skull, Vector3(1.9, 2.0, 2.3), gb)
	m.ellipsoid(bone, skull + gb * Vector3(0.0, -1.2, 1.2), Vector3(1.3, 0.8, 1.2), gb)
	for s in [-1.0, 1.0]:
		m.ellipsoid(lash, skull + gb * Vector3(0.75 * float(s), 0.3, 1.95), Vector3(0.48, 0.42, 0.3), gb)
	m.ellipsoid(lash, skull + gb * Vector3(0.0, -0.7, 2.25), Vector3(0.28, 0.4, 0.22), gb)
	# a coil of the hag-rope on the turf by its feet
	m.ellipsoid(lash, G + gb * Vector3(0.0, 0.1, 2.6), Vector3(0.8, 0.12, 0.8), gb)
	await k.step()
	m.commit(stone, k.surface("stone", 0.85), "GiantStones", true)
	await k.step()
	m.commit(bone, PoiKit.painted(5, BONE, 0.6, 0.6), "GiantBones", true)
	await k.step()
	m.commit(lash, PoiKit.plain(Color(0.12, 0.11, 0.1), 0.9), "GiantLashings", true)
	# the scaffold: four corner poles, ledgers every four metres, braces, the gin-pole and its rope
	var scaf := m.begin()
	var corners := [Vector3(-5.8, 0.0, -3.4), Vector3(5.8, 0.0, -3.4), Vector3(5.8, 0.0, 3.6), Vector3(-5.8, 0.0, 3.6)]
	for cv in corners:
		var cc: Vector3 = cv
		var fp := G + gb * cc
		fp.y = k.on_ground(fp.x, fp.z).y - 0.3
		_pole(d, scaf, fp, fp + Vector3.UP * 21.5, 0.14)
	for lvl in [4.0, 8.0, 12.0, 16.0, 20.0]:
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			m.limb(scaf, G + gb * Vector3(a.x, lvl, a.z), G + gb * Vector3(b.x, lvl, b.z), 0.08)
	for i in 4:
		var y0 := 4.0 * float(i)
		var a: Vector3 = corners[0]
		var b: Vector3 = corners[1]
		m.limb(scaf, G + gb * Vector3(a.x, y0, a.z), G + gb * Vector3(b.x, y0 + 4.0, b.z), 0.07)
	var gin_foot := G + gb * Vector3(-8.5, 0.0, 2.0)
	gin_foot.y = k.on_ground(gin_foot.x, gin_foot.z).y - 0.3
	var gin_top := G + gb * Vector3(-4.0, 23.0, 1.4)
	_pole(d, scaf, gin_foot, gin_top, 0.2)
	await k.step()
	m.commit(scaf, k.surface("timber", 0.7), "Scaffold", true)
	if k.far:
		return
	# the stages and the ladders up to them, one piece with the ladders' feet on the turf
	var stage := m.begin()
	for st in [[8.0, 3.6], [16.0, -3.4]]:
		var sy := float(st[0])
		var sz := float(st[1])
		var xf := Transform3D(gb, G + gb * Vector3(0.0, sy + 0.08, sz + (0.6 if sz > 0.0 else -0.6)))
		m.block(stage, xf, Vector3(11.4, 0.12, 1.3))
		k.collider(Vector3(11.4, 0.12, 1.3), xf, "wood")
	var l0 := G + gb * Vector3(-4.6, 0.0, 4.6)
	l0.y = k.on_ground(l0.x, l0.z).y
	_ladder(m, stage, l0, G + gb * Vector3(-4.6, 8.1, 3.9), 0.55)
	_ladder(m, stage, G + gb * Vector3(4.6, 8.1, 4.2), G + gb * Vector3(4.6, 16.1, -2.6), 0.55)
	await k.step()
	m.commit(stage, k.surface("planks", 0.8), "Stages")
	# the ropes: the gin-pole's fall to the skull and down to its belay, and a rope where the left arm will go
	var ropes := m.begin()
	var belay := G + gb * Vector3(-9.8, 0.0, 4.4)
	belay.y = k.on_ground(belay.x, belay.z).y
	m.limb(ropes, gin_top, skull + Vector3.UP * 1.9, 0.04)
	m.limb(ropes, gin_top, belay + Vector3.UP * 0.4, 0.04)
	m.limb(ropes, belay + Vector3.DOWN * 0.3, belay + Vector3.UP * 0.6, 0.08)
	m.limb(ropes, G + gb * Vector3(-5.8, 20.0, -0.2), G + gb * Vector3(-4.6, 8.5, 0.2), 0.035)
	await k.step()
	m.commit(ropes, PoiKit.plain(Color(0.36, 0.33, 0.28), 0.9), "HagRopes")
	# the hags' lanterns on the ledgers, lit after dark
	var lamps := m.begin()
	for lp in [Vector3(5.8, 12.25, 0.4), Vector3(-5.8, 16.25, -1.0), Vector3(0.0, 20.25, -3.4)]:
		var at := G + gb * (lp as Vector3)
		m.block(lamps, Transform3D(gb, at), Vector3(0.24, 0.32, 0.24))
		k.light(at + Vector3.UP * 0.25, Color(0.9, 0.75, 0.5), 1.0, 6.0)
	m.commit(lamps, PoiKit.plain(Color(1.0, 0.82, 0.55), 0.5, 0.0, Color(1.0, 0.72, 0.4), 1.4), "HagLanterns")
	# bones heaped at its feet, waiting their turn
	var heaps := [["bone_rib", Vector3(5.5, 0.0, 6.2)], ["bone_vertebra", Vector3(-6.8, 0.0, 6.5)], ["bone_skull_fragment", Vector3(8.2, 0.0, 1.5)]]
	for h in heaps:
		var rock := k.rock(str(h[0]))
		if rock == "":
			continue
		var at := G + gb * (h[1] as Vector3)
		await k.step()
		k.place(rock, k.on_ground(at.x, at.z, -0.2), k.rng.randf() * TAU, 0.55, true)
	# Haskel's camp at the pad's edge, looking at it: his tent, his fire, his tally-board on its post
	var camp := fwd.rotated(1.0) * 27.0
	await _prop(d, "tent", camp + fwd.rotated(1.0) * 3.0, PoiKit.yaw_of(-fwd))
	await _prop(d, "campfire", camp - right * 1.5, 0.0, 0.8)
	await _prop(d, "stool", camp - right * 0.2 - fwd * 1.4, PoiKit.yaw_of(into))
	var board := m.begin()
	var bp := camp + right * 1.8 - fwd * 1.0
	var bt := m.post(board, bp, 1.6, 0.1)
	m.block(board, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(fwd)), bt - Vector3(0.0, 0.4, 0.0)), Vector3(0.8, 0.6, 0.05))
	await k.step()
	m.commit(board, k.surface("timber", 0.7), "TallyBoard")
	_spot(d, "haskel_camp", camp - fwd * 2.2)
	_spot(d, "home", camp + fwd.rotated(1.0) * 1.2)
	k.marker("the_scaffold_foot", k.on_ground(gp.x + fwd.x * 6.0, gp.y + fwd.y * 6.0))
	k.marker("the_bone_way", k.on_ground(gp.x + fwd.x * 9.0 + right.x * 9.0, gp.y + fwd.y * 9.0 + right.y * 9.0))
