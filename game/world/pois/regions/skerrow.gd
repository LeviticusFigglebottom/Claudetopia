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
	k.collider(Vector3(0.9, 0.46, 0.9), Transform3D(Basis(), k.on_ground(at.x, at.y, 0.21)), "stone")
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
	await _kind(d)
	if d.kit.far:
		return
	_resident(d, "the_count_stone", _away(d), 6.0, 18.0)


## The Rib Cathedral: the ribs, and the oath-keeper's place in the nave.
static func rib_cathedral(d: PoiDressing) -> void:
	await _kind(d)
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
	m.block(brass, Transform3D(Basis(), gauge_top + Vector3(0.0, 0.14, 0.0)), Vector3(0.18, 0.28, 0.18))
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
	var arm_end := top + arm * 1.8 - Vector3(0.0, 0.2, 0.0)
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


## Ghastfoot: the arch, and the skull in its keystone to ask leave of.
static func ghastfoot(d: PoiDressing) -> void:
	await _kind_and_touch(d, "Keystone", "Look up at the skull in the keystone", "ghastfoot_clay_skull", _away(d), 1.5, 8.0, 1.0)


## The Watch of the Gate: the toll-house, and its bell frozen mid-swing.
static func watch_of_the_gate(d: PoiDressing) -> void:
	await _kind_and_touch(d, "FrozenBell", "Look at the frozen bell", "watch_gate_bell", Vector2(0.0, -1.0), 3.0, 9.0, 1.2)


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
