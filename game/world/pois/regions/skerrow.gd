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


# --- places of their own ------------------------------------------------------------------------------

## Pennant's Weather-House: a turf bothy by the tarn, and round it a Sayer's instruments on posts, a
## wind-vane, a rain-gauge, a glass in a box and a ribbon over a shakehole, and a bell on a frame that
## rings when the wind turns.
static func pennants_weather_house(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().WAYSIDE.hut(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var solids := _solids(d)
	var away := _away(d)
	var yard := _open_spot(d, away.rotated(1.2), 6.0, 11.0, 1.8, solids)
	var toward := -yard.normalized()
	var side := Vector2(toward.y, -toward.x)
	var timber := m.begin()
	var brass := m.begin()
	# the vane: a tall post, a cross-arm, a tail-fin
	var vane_at := yard + side * 1.8
	var vane_top := m.post(timber, vane_at, 3.2, 0.1)
	m.block(brass, Transform3D(Basis(Vector3.UP, k.rng.randf_range(0.0, TAU)), vane_top + Vector3(0.0, 0.1, 0.0)), Vector3(0.05, 0.05, 1.1))
	m.block(brass, Transform3D(Basis(Vector3.UP, k.rng.randf_range(0.0, TAU)), vane_top + Vector3(0.0, 0.18, 0.4)), Vector3(0.02, 0.26, 0.34))
	# the rain-gauge: a short post and a funnelled can
	var gauge_at := yard - side * 1.4
	var gauge_top := m.post(timber, gauge_at, 1.0, 0.09)
	m.block(brass, Transform3D(Basis(), gauge_top + Vector3(0.0, 0.14, 0.0)), Vector3(0.18, 0.28, 0.18))
	# the glass in its box on a stand
	var glass_at := yard + toward * 1.2
	var glass_top := m.post(timber, glass_at, 1.25, 0.1)
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(toward)), glass_top + Vector3(0.0, 0.2, 0.0)), Vector3(0.32, 0.42, 0.16))
	# the bell on its frame, where the wind turns it
	var bell_at := yard - toward * 1.4
	var hang := m.frame(timber, bell_at, PoiKit.yaw_of(side), 0.9, 1.7, 0.08)
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "Instruments")
	await k.step()
	m.commit(brass, PoiKit.plain(PoiKit.BRONZE, 0.45, 0.8), "Brass")
	var bell := k.prop("bell_small")
	if bell != "":
		await k.step()
		k.place(bell, hang - Vector3(0.0, 0.3, 0.0), 0.0, 1.0, false)
	# the ribbon over a shakehole in the turf, leaning in
	var hole := yard + toward * 3.2 + side * 1.0
	var dark := m.begin()
	m.ellipsoid(dark, k.on_ground(hole.x, hole.y, -0.02), Vector3(0.5, 0.05, 0.42))
	await k.step()
	m.commit(dark, PoiKit.plain(Color(0.08, 0.08, 0.07), 0.95), "Shakehole")
	var stick := m.begin()
	var tip := m.post(stick, hole + side * 0.55, 0.7, 0.03, Vector3(0.0, 0.0, 0.3))
	m.block(stick, Transform3D(Basis(), tip + Vector3(-0.1, -0.15, 0.0)), Vector3(0.025, 0.3, 0.01))
	await k.step()
	m.commit(stick, PoiKit.plain(Color(0.62, 0.16, 0.14), 0.8), "Ribbon")
	k.touchable("Gauges", glass_top + Vector3(0.0, 0.2, 0.0), "Read the gauges", DIALOGUE + "weather_house_gauges", "", false)
	_spot(d, "the_instruments", yard + toward * 0.2 - side * 0.2)


## Skerrfall Quarry: the kind's quarry, and in the foot of its first bench the long white bone the
## last face was cut round, half out of the rock like a lintel over nothing, and Hodd ko-Brindle's
## bench facing it.
static func skerrfall_quarry(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().LAND.quarry(d)
	var k := d.kit
	if k.far:
		return
	# the face as the quarry laid it (poi_builders_land.gd quarry): its arc round `centre`, uphill
	var face := k.downhill()
	if face == Vector2.ZERO:
		face = k.grain()
	var side := Vector2(face.y, -face.x)
	var arc_r := minf(d.pad_radius * 0.75, 16.0)
	var centre := face * 2.0
	var foot := centre - face * (arc_r - 1.5)
	var bone := k.rock("bone_finger", 1)
	if bone != "":
		var s := 0.62
		var at := foot - side * (3.3 * s)
		await k.step()
		k.place(bone, k.on_ground(at.x, at.y, -0.25), _yaw_x(side), s, true)
	k.marker("the_new_face", k.on_ground(foot.x + face.x * 3.5, foot.y + face.y * 3.5))
	var seat := foot + face * 5.5 + side * 2.6
	await _prop(d, "bench", seat, PoiKit.yaw_of(side))
	await _prop(d, "whetstone", seat + side * 0.9 + face * 0.3, k.rng.randf_range(0.0, TAU))
	_spot(d, "the_quarry_bench", seat + face * 0.9)


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
	var snow := PoiKit.plain(SNOW, 0.7)
	var north := Vector2(0.0, -1.0)
	var east := Vector2(1.0, 0.0)
	# the drifts the wind piled among them, long and low across the slope
	for i in 6:
		var p := north * k.rng.randf_range(-10.0, 10.0) + east * k.rng.randf_range(-13.0, 13.0)
		await k.step()
		m.mound(k.on_ground(p.x, p.y, -0.3), k.rng.randf_range(2.6, 4.4), k.rng.randf_range(0.6, 1.1), snow, "Drift", true,
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
						k.rng.randf_range(0.95, 1.08))
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
				herd.material_override = PoiKit.plain(Color(0.86, 0.88, 0.9), 0.85)
	# the drover's crook, upright, its handle to the north
	var timber := m.begin()
	var top := m.post(timber, Vector2.ZERO, 1.7, 0.045)
	m.block(timber, Transform3D(Basis(), top + Vector3(0.0, 0.06, -0.09)), Vector3(0.045, 0.045, 0.22))
	m.block(timber, Transform3D(Basis(), top + Vector3(0.0, -0.04, -0.2)), Vector3(0.045, 0.2, 0.045))
	await k.step()
	m.commit(timber, k.surface("timber", 0.9), "Crook")
	k.touchable("Crook", top + Vector3(0.0, -0.4, 0.0), "Look at the drover's crook", DIALOGUE + "frozen_drove_crook", "", false)
	k.marker("the_drove", k.on_ground(0.0, 3.0))


## The Sorting Ground: a pavement of limestone clints on the moor, and on it a giant laid out by kind,
## largest to smallest: a line of vertebrae stopping a bone short, ribs lying flat in a rank, the long
## bones in another, the skull's pieces at the head, and at the line's end a space swept clean.
static func sorting_ground(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var along := k.grain()
	var across := Vector2(along.y, -along.x)
	# the pavement: clints with grikes between, each laid on its own ground
	var clint := m.begin()
	for i in 12:
		for j in 6:
			var c := along * (-20.0 + 3.6 * float(i) + k.rng.randf_range(-0.3, 0.3)) + across * (-9.5 + 3.8 * float(j) + k.rng.randf_range(-0.3, 0.3))
			if absf(c.dot(across)) > 10.5 or absf(c.dot(along)) > 21.0:
				continue
			var size := Vector3(k.rng.randf_range(2.6, 3.3), 0.34, k.rng.randf_range(2.8, 3.4))
			var g := k.on_ground(c.x, c.y)
			m.block(clint, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(along) + k.rng.randf_range(-0.05, 0.05)), g + Vector3(0.0, 0.05, 0.0)), size)
	await k.step()
	m.commit(clint, PoiKit.painted(0, {"base": "#b3aea2", "accent": "#9a958a", "grout": "#6c685f", "unit": 0.9}, 0.7, 0.7), "Pavement", true)
	k.collider(Vector3(42.0, 0.3, 21.0), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(along) + PI * 0.5), k.on_ground(0.0, 0.0, 0.07)), "stone")
	if k.far:
		return
	var top := 0.22
	# the line of vertebrae, largest to smallest, a hand apart, and the space after the last
	var vert := k.rock("bone_vertebra", 0)
	var end := Vector2.ZERO
	if vert != "":
		var line: Array = []
		var x := -19.0
		for i in 20:
			var s := 0.55 - 0.016 * float(i)
			x += 1.4 * s
			var p := along * x + across * -5.5
			line.append(PoiKit.transform_at(k.on_ground(p.x, p.y, top), _yaw_x(across), s))
			x += 1.4 * s + 0.3
			end = along * (x + 0.9) + across * -5.5
		await k.step()
		k.scatter(vert, line, true)
	# the ribs lying flat in a rank, longest first
	var rib := k.rock("bone_rib", 0)
	if rib != "":
		var rank: Array = []
		for i in 6:
			var s := 0.46 - 0.04 * float(i)
			var p := along * (-15.0 + 5.4 * float(i)) + across * 1.5
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
			var s := 0.62 - 0.05 * float(i)
			var p := along * (-17.0 + 5.2 * float(i)) + across * 6.5 - across * (2.7 * s)
			bones.append(PoiKit.transform_at(k.on_ground(p.x, p.y, top), _yaw_x(across), s))
		await k.step()
		k.scatter(long, bones, true)
	var skull := k.rock("bone_skull_fragment", 0)
	if skull != "":
		var pieces: Array = []
		for i in 3:
			var p := along * (18.5 + k.rng.randf_range(-0.6, 0.6)) + across * (-5.5 + 5.5 * float(i))
			pieces.append(PoiKit.transform_at(k.on_ground(p.x, p.y, top), k.rng.randf_range(0.0, TAU), 0.5 - 0.08 * float(i)))
		await k.step()
		k.scatter(skull, pieces, true)
	k.touchable("TheGap", k.on_ground(end.x, end.y, top + 0.3), "Look at the end of the line", DIALOGUE + "sorting_ground_gap", "", false)
	k.marker("the_line", k.on_ground(end.x - along.x * 3.0, end.y - along.y * 3.0, top))
