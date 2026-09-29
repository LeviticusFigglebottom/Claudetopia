extends RefCounted
## Cinderlea's own place builders (docs/WORLD_LIFE.md). A POI def with `"builder": "<name>"` is built
## by the static function of that name here, in place of its kind's builder. Only the Cinderlea
## region's author edits this file, so six regions can build at once without meeting.
##
##   static func drovers_hall(d: PoiDressing) -> void:
##       await PoiDressing.kind_builders().LAND.farmstead(d)    # its kind's, then more
##       var k := d.kit                                          # PoiKit: on_ground, prop, masonry ...
##
## The kind stays the def's `kind` (what the tests, the map and the audit call it); a builder named
## here that is missing is said in the log and the place is built as its kind.
##
## Here: Turnback Keep (the ruin's own walls, and Elsbet Ash's fire outside its gate), the Salt
## Landing (a Salt Isles boat hauled up on the heath), the Bell-Rope Walk (the Order's ropewalk on
## the cliff-top) and the Rooftop Shaft (a scavengers' headframe over a hole into a buried hall).

## The Salt Isles' sailcloth, weathered, and the grey flax of the Order's ropes.
const SAIL := Color(0.78, 0.74, 0.64)
const FLAX := Color(0.52, 0.5, 0.45)
const HOLE := Color(0.02, 0.02, 0.025)
const BRONZE := Color(0.5, 0.4, 0.22)


# --- Turnback Keep ----------------------------------------------------------------------------------

## The keep is the castle_ruin's own (world/sites/site_exterior.gd), its gate on the bearing the def
## gives (towards the Choir). Outside the gate, on the side away from the notice post, the last
## knight's fire: stones, a stool, a bedroll, her helm on a stake, a lantern, and the spot she keeps.
static func turnback_keep(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().SITES.build(d)
	var k := d.kit
	if k.far:
		return
	var site: Dictionary = ContentDB.get_or_empty(d.poi_id).get("site", {})
	var b := deg_to_rad(float(site.get("gate_bearing_deg", 81.0)))
	var out := Vector2(sin(b), cos(b))
	var side := Vector2(out.y, -out.x)
	var fire := out * minf(d.pad_radius - 6.0, 28.0) - side * 5.0
	if k.road_distance(fire) < PoiKit.ROAD_CLEAR_M + 2.0:
		fire = out * minf(d.pad_radius - 6.0, 28.0) - side * 9.0
	await _gate_fire(d, fire, out, "elsbet_fire")


static func _gate_fire(d: PoiDressing, fire: Vector2, facing: Vector2, spot: String) -> void:
	var k := d.kit
	var m := d.masonry
	await k.step()
	k.place(k.prop("campfire"), k.on_ground(fire.x, fire.y), k.rng.randf_range(0.0, TAU), 1.0)
	k.marker("the_fire", k.on_ground(fire.x, fire.y))
	var stones: Array = []
	for p in k.ring(8, 0.9, fire, 0.1):
		var pp: Vector2 = p
		stones.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.09, 0.13)))
	await k.step()
	k.scatter(k.rock("boulder"), stones)
	k.light(k.on_ground(fire.x, fire.y, 0.9), Color(1.0, 0.68, 0.35), 2.4, 11.0)
	k.puffs(k.on_ground(fire.x, fire.y, 0.7), Vector3(0.15, 0.1, 0.15), 0.6, 6, Color(0.55, 0.55, 0.55, 0.28), 1.0, 5.0)
	# she sits with the fire between her and the gate, facing it
	var seat := fire + facing * 1.9
	await k.step()
	k.place(k.prop("stool"), k.on_ground(seat.x, seat.y), PoiKit.yaw_of(-facing))
	var behind := seat + facing * 0.8
	k.marker(spot, k.on_ground(behind.x, behind.y), true)
	var roll := fire + facing * 2.2 + Vector2(facing.y, -facing.x) * 2.0
	await k.step()
	k.place(k.prop("bedroll"), k.on_ground(roll.x, roll.y), PoiKit.yaw_of(facing) + PI * 0.5)
	var pot := fire + Vector2(facing.y, -facing.x) * 1.4
	await k.step()
	k.place(k.prop("cooking_pot"), k.on_ground(pot.x, pot.y), k.rng.randf_range(0.0, TAU))
	var lamp := seat + Vector2(-facing.y, facing.x) * 0.9
	await k.step()
	k.place(k.prop("lantern_hand"), k.on_ground(lamp.x, lamp.y), 0.0, 1.0, false)
	# a stake with her helm on it, the way a knight of the Order leaves it when not on watch
	var timber := m.begin()
	var stake := fire + facing * 2.0 - Vector2(facing.y, -facing.x) * 2.2
	var top := m.post(timber, stake, 1.5, 0.08)
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "Stake")
	var helm := m.begin()
	m.ellipsoid(helm, top + Vector3(0.0, 0.14, 0.0), Vector3(0.17, 0.2, 0.19))
	await k.step()
	m.commit(helm, PoiKit.plain(Color(0.42, 0.43, 0.45), 0.45, 0.7), "Helm")


# --- the Salt Landing -------------------------------------------------------------------------------

## A camp of two Salt Isles traders on the heath above the strand: their boat hauled up on log
## rollers with its bow to the sea, the sail rigged as a lean-to over the salt and the
## glass, an oar planted upright with a lantern on it for the ship that has not come, and a fire.
static func salt_landing(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(260.0)
	if sea == Vector2.ZERO:
		sea = Vector2(-1.0, 0.0)
	sea = sea.normalized()
	var side := Vector2(sea.y, -sea.x)
	var timber := m.begin()
	var fire := k.jitter(0.8)

	if not k.far:
		await k.step()
		k.place(k.prop("campfire"), k.on_ground(fire.x, fire.y), k.rng.randf_range(0.0, TAU), 1.05)
		k.marker("the_fire", k.on_ground(fire.x, fire.y))
		var stones: Array = []
		for p in k.ring(9, 0.95, fire, 0.1):
			var pp: Vector2 = p
			stones.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.09, 0.14)))
		await k.step()
		k.scatter(k.rock("boulder"), stones)
		k.light(k.on_ground(fire.x, fire.y, 0.9), Color(1.0, 0.7, 0.4), 2.4, 11.0)
		k.puffs(k.on_ground(fire.x, fire.y, 0.7), Vector3(0.15, 0.1, 0.15), 0.6, 6, Color(0.55, 0.55, 0.55, 0.28), 1.1, 5.0)
		for p in k.ring(3, 2.2, fire, 0.15):
			var pp: Vector2 = p
			await k.step()
			k.place(k.prop("stool"), k.on_ground(pp.x, pp.y), PoiKit.yaw_of(fire - pp))
		var by := fire - sea * 2.9
		k.marker("landing_fire", k.on_ground(by.x, by.y), true)

	# the boat, bow to the sea, on three log rollers
	var boat := fire + sea * 9.5 + side * 2.5
	var rollers := m.begin()
	for i in 3:
		var along := boat + sea * (float(i) - 1.0) * 1.6
		var a := k.on_ground(along.x + side.x * 1.3, along.y + side.y * 1.3, 0.14)
		var bb := k.on_ground(along.x - side.x * 1.3, along.y - side.y * 1.3, 0.14)
		m.limb(rollers, a, bb, 0.14)
	await k.step()
	m.commit(rollers, k.surface("timber", 0.8), "Rollers")
	var hull := k.prop("rowboat")
	if hull != "":
		await k.step()
		k.place(hull, k.on_ground(boat.x, boat.y, 0.22), PoiKit.yaw_of(sea), 1.35, true, Vector3.ZERO, true)
	if not k.far:
		var beside := boat - side * 2.6
		k.marker("ossul_boat", k.on_ground(beside.x, beside.y), true)
		var coil := boat - side * 1.8 - sea * 2.0
		await k.step()
		k.place(k.prop("rope_coil"), k.on_ground(coil.x, coil.y), k.rng.randf_range(0.0, TAU))

	# the awning: the boat's sail over the salt, up on two poles to the sea and pegged down behind
	var aw := fire - sea * 7.5 - side * 1.0
	var half_w := 3.2
	var half_d := 2.3
	var corners: Array = []
	for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		var c: Vector2 = aw + side * (half_w * float(s[0])) + sea * (half_d * float(s[1]))
		# a lean-to: the sail up on two poles on the sea side, pegged to the ground at the back
		var h := 2.7 if float(s[1]) > 0.0 else 0.12
		corners.append(m.post(timber, c, h, 0.12))
	var sail := m.begin()
	var ca: Vector3 = corners[0]
	var cb: Vector3 = corners[1]
	var cc: Vector3 = corners[2]
	var cd: Vector3 = corners[3]
	# the cloth as a thin slab between the low and the high edge
	var mid := (ca + cb + cc + cd) * 0.25 + Vector3(0.0, 0.05, 0.0)
	var across := (cb - ca)
	var up_slope := ((cc + cd) * 0.5 - (ca + cb) * 0.5)
	var x_axis := across.normalized()
	var z_axis := up_slope.normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	m.block(sail, Transform3D(Basis(x_axis, y_axis, z_axis), mid), Vector3(across.length() + 0.5, 0.03, up_slope.length() + 0.5))
	await k.step()
	m.commit(sail, PoiKit.plain(SAIL, 0.9), "Sail", true)
	if not k.far:
		var under := aw + sea * 1.4
		k.marker("thalisse_awning", k.on_ground(under.x, under.y), true)
		# the salt, in sacks, and the glass in crates
		for i in 5:
			var at := aw + side * (-2.2 + float(i) * 0.75) + sea * 1.0
			await k.step()
			k.place(k.prop("sack"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.05))
		for i in 2:
			var at := aw + side * (1.6 + float(i) * 1.0) + sea * 1.9
			await k.step()
			k.place(k.prop("crate"), k.on_ground(at.x, at.y), PoiKit.yaw_of(sea) + k.rng.randf_range(-0.2, 0.2))
		var roll := aw - side * 2.0 + sea * 1.7
		await k.step()
		k.place(k.prop("bedroll"), k.on_ground(roll.x, roll.y), PoiKit.yaw_of(side))

	# an oar stood upright in a cairn, the lantern hung from its blade, for the ship
	var oar := fire + sea * 4.5 - side * 5.0
	var oar_top := m.post(timber, oar, 3.4, 0.09)
	m.block(timber, Transform3D(Basis.IDENTITY, oar_top + Vector3(0.0, 0.35, 0.0)), Vector3(0.22, 0.7, 0.05))
	var arm := Vector3(sea.x, 0.0, sea.y) * 0.4
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(sea)), oar_top - Vector3(0.0, 0.2, 0.0) + arm * 0.5), Vector3(0.05, 0.05, 0.5))
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "Timber", true)
	if not k.far:
		var cairn: Array = []
		for p in k.ring(6, 0.45, oar, 0.1):
			var pp: Vector2 = p
			cairn.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.12, 0.16)))
		await k.step()
		k.scatter(k.rock("boulder"), cairn)
		var lantern := k.prop("lantern_hanging")
		var lamp_at := oar_top - Vector3(0.0, 0.55, 0.0) + arm
		if lantern != "":
			await k.step()
			k.place(lantern, lamp_at, PoiKit.yaw_of(sea), 1.0, false)
		k.light(lamp_at + Vector3(0.0, 0.2, 0.0), Color(1.0, 0.82, 0.55), 1.4, 8.0)
		var foot := oar - sea * 1.2
		k.marker("the_oar_lantern", k.on_ground(foot.x, foot.y), true)
		k.touchable("the_lantern", lamp_at, "Look at the lantern on the oar", "core:dialogue/salt_landing_lantern", "", false)


# --- the Bell-Rope Walk -----------------------------------------------------------------------------

const WALK_HALF_M := 31.0
const TRESTLE_EVERY_M := 5.6
const STRANDS := [-0.42, -0.14, 0.14, 0.42]

## The Order's ropewalk: a spinning-wheel at one end, a weighted sledge at the other, trestles between
## with pegs across their tops, and grey strands of flax laid over them the length of the walk,
## sagging a little between each; a rope-shed at the wheel end with the finished coils, and a fire.
static func bellrope_walk(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var axis := k.grain()
	if axis == Vector2.ZERO:
		axis = Vector2(1.0, 0.0)
	axis = axis.normalized()
	var across := Vector2(axis.y, -axis.x)
	var yaw := PoiKit.yaw_of(axis)
	var basis := Basis(Vector3.UP, yaw)
	var timber := m.begin()
	var half := minf(WALK_HALF_M, d.pad_radius - 3.0)

	# the wheel end: two uprights, an axle, a spoked wheel standing across the walk's line
	var wheel_at := -axis * half
	var hub := k.on_ground(wheel_at.x, wheel_at.y, 1.08)
	for s in [-1.0, 1.0]:
		var foot: Vector2 = wheel_at + axis * 0.35 * float(s)
		m.post(timber, foot, 2.1, 0.14)
	m.block(timber, Transform3D(basis, hub), Vector3(0.1, 0.1, 0.9))
	var wheel := m.begin()
	var spokes := 8
	for i in spokes:
		var a := TAU * float(i) / float(spokes)
		var dir := basis * Vector3(cos(a), sin(a), 0.0)
		var rim_a := hub + dir * 1.0
		m.limb(wheel, hub, rim_a, 0.035)
		var a2 := TAU * float(i + 1) / float(spokes)
		var dir2 := basis * Vector3(cos(a2), sin(a2), 0.0)
		m.limb(wheel, rim_a, hub + dir2 * 1.0, 0.05)
	await k.step()
	m.commit(wheel, k.surface("timber", 0.6), "Wheel", true)
	# the hooks the strands start from, on a bar at the wheel's side
	var bar_at := wheel_at + axis * 0.9
	var bar_top := m.post(timber, bar_at, 1.1, 0.12)
	m.block(timber, Transform3D(basis, bar_top), Vector3(1.3, 0.1, 0.1))

	# the sledge end: runners, a deck, and a boulder on it for the weight that keeps the lay taut
	var sledge_at := axis * half
	var sledge := m.begin()
	for s in [-1.0, 1.0]:
		var run: Vector2 = sledge_at + across * 0.55 * float(s)
		var g := k.on_ground(run.x, run.y, 0.1)
		m.block(sledge, Transform3D(basis, g), Vector3(0.1, 0.2, 1.8))
	var deck := k.on_ground(sledge_at.x, sledge_at.y, 0.26)
	m.block(sledge, Transform3D(basis, deck), Vector3(1.3, 0.08, 1.5))
	var post_top := deck + Vector3(0.0, 0.62, 0.0) - Vector3(axis.x, 0.0, axis.y) * 0.6
	m.block(sledge, Transform3D(basis, (deck + post_top) * 0.5), Vector3(0.12, 0.62, 0.12))
	m.block(sledge, Transform3D(basis, post_top), Vector3(1.3, 0.1, 0.1))
	await k.step()
	m.commit(sledge, k.surface("planks", 0.7), "Sledge", true)
	k.collider(Vector3(1.4, 0.5, 1.8), Transform3D(basis, deck), "wood")
	var weight := k.rock("boulder")
	if weight != "" and not k.far:
		await k.step()
		k.place(weight, deck + Vector3(axis.x, 0.0, axis.y) * 0.3, k.rng.randf_range(0.0, TAU), 0.7 / maxf(PoiKit.height_of(weight), 0.3), false)

	# trestles down the walk, each a post and a peg-bar across the line
	var supports: Array = []   # [along, top y]
	supports.append([-half + 0.9, bar_top.y + 0.05])
	var n := int((2.0 * half - 3.0) / TRESTLE_EVERY_M)
	for i in n:
		var t := -half + 1.5 + TRESTLE_EVERY_M * (float(i) + 0.5)
		var at := axis * t
		if k.road_distance(at) < PoiKit.ROAD_CLEAR_M:
			continue
		var top := m.post(timber, at, 1.0, 0.12)
		m.block(timber, Transform3D(basis, top), Vector3(1.25, 0.08, 0.1))
		for s in STRANDS:
			var peg := top + basis * Vector3(float(s) + 0.07, 0.07, 0.0)
			m.block(timber, Transform3D(basis, peg), Vector3(0.03, 0.12, 0.03))
		supports.append([t, top.y + 0.05])
		if i % 3 == 1:
			await k.step()
	supports.append([half - 0.6, post_top.y + 0.05])
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "Timber", true)
	k.collider(Vector3(0.3, 2.1, 1.0), Transform3D(basis, k.on_ground(wheel_at.x, wheel_at.y, 1.05)), "wood")

	# the strands: grey flax laid over the pegs from hook to sledge, a small sag between supports
	if not k.far:
		var flax := m.begin()
		for s in STRANDS:
			for i in range(1, supports.size()):
				var p0: Array = supports[i - 1]
				var p1: Array = supports[i]
				var a := axis * float(p0[0]) + across * float(s)
				var b := axis * float(p1[0]) + across * float(s)
				var ya := float(p0[1])
				var yb := float(p1[1])
				var span := absf(float(p1[0]) - float(p0[0]))
				var sag := minf(0.12, span * 0.02)
				var mid2 := (a + b) * 0.5
				var va := Vector3(a.x, ya, a.y)
				var vm := Vector3(mid2.x, (ya + yb) * 0.5 - sag, mid2.y)
				var vb := Vector3(b.x, yb, b.y)
				m.limb(flax, va, vm, 0.018)
				m.limb(flax, vm, vb, 0.018)
		await k.step()
		m.commit(flax, PoiKit.plain(FLAX, 0.95), "Strands")

	# the rope-shed at the wheel end, to the side: posts, a back wall of planks and a roof
	var shed := wheel_at + axis * 3.0 + across * 5.0
	var shed_basis := Basis(Vector3.UP, yaw)
	var planks := m.begin()
	var shed_timber := m.begin()
	var tops: Array = []
	for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		var c: Vector2 = shed + axis * 1.8 * float(s[0]) + across * 1.3 * float(s[1])
		tops.append(m.post(shed_timber, c, 2.4 if float(s[1]) > 0.0 else 2.0, 0.14))
	var back_a: Vector3 = tops[2]
	var back_b: Vector3 = tops[3]
	var back_mid := (back_a + back_b) * 0.5
	var back_foot := k.on_ground((shed + across * 1.3).x, (shed + across * 1.3).y)
	var wall_h := back_mid.y - back_foot.y
	m.block(planks, Transform3D(shed_basis, Vector3(back_mid.x, back_foot.y + wall_h * 0.5, back_mid.z)), Vector3(0.08, wall_h, 3.6))
	k.collider(Vector3(0.1, wall_h, 3.6), Transform3D(shed_basis, Vector3(back_mid.x, back_foot.y + wall_h * 0.5, back_mid.z)), "wood")
	var roof_mid := ((tops[0] as Vector3) + (tops[1] as Vector3) + back_a + back_b) * 0.25 + Vector3(0.0, 0.08, 0.0)
	var slope := atan2(back_mid.y - ((tops[0] as Vector3) + (tops[1] as Vector3)).y * 0.5, 2.6)
	var roof_basis := shed_basis * Basis(Vector3.FORWARD, -slope)
	m.block(planks, Transform3D(roof_basis, roof_mid), Vector3(3.3, 0.07, 4.2))
	await k.step()
	m.commit(planks, k.surface("planks", 0.7), "Shed")
	m.commit(shed_timber, k.surface("timber", 0.6), "ShedTimber")
	if not k.far:
		k.marker("home", k.on_ground(shed.x, shed.y), true)
		for i in 3:
			var at := shed + axis * (-1.1 + float(i) * 1.1) + across * 0.7
			await k.step()
			k.place(k.prop("rope_coil"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(1.0, 1.25))
		var barrel := shed - axis * 1.2 - across * 0.8
		await k.step()
		k.place(k.prop("barrel"), k.on_ground(barrel.x, barrel.y), 0.0)
		# the wheel's spot, the sledge's, and the fire by the shed
		var at_wheel := wheel_at + across * 1.4
		k.marker("the_wheel", k.on_ground(at_wheel.x, at_wheel.y), true)
		var at_sledge := sledge_at - axis * 1.6 + across * 1.2
		k.marker("the_sledge", k.on_ground(at_sledge.x, at_sledge.y), true)
		k.touchable("the_strand", k.on_ground(at_wheel.x, at_wheel.y, 1.0), "Run a strand through your fist", "core:dialogue/bellrope_walk_strand", "", false)
		var fire := shed + axis * 4.0 + across * 1.0
		if k.road_distance(fire) >= PoiKit.ROAD_CLEAR_M + 1.0:
			await k.step()
			k.place(k.prop("campfire"), k.on_ground(fire.x, fire.y), k.rng.randf_range(0.0, TAU), 0.9)
			k.light(k.on_ground(fire.x, fire.y, 0.8), Color(1.0, 0.7, 0.4), 2.0, 9.0)
			var st := fire + across * 1.6
			await k.step()
			k.place(k.prop("stool"), k.on_ground(st.x, st.y), PoiKit.yaw_of(fire - st))
		# a finished rope, coiled on the sledge end's trestle for carrying up to the Choir
		var done := sledge_at - axis * 3.0 - across * 1.5
		await k.step()
		k.place(k.prop("rope_coil"), k.on_ground(done.x, done.y), k.rng.randf_range(0.0, TAU), 1.3)


# --- the Rooftop Shaft ------------------------------------------------------------------------------

## A scavengers' shaft through the ash onto a Builders' roof: the hole, ringed by the broken tiles of
## the roof it went through, a timber headframe with a windlass and a rope going down, the top of a
## ladder, the spoil in heaps round it, the scavengers' sieves and a crate of bronze, and at the lip
## the way down into the inside the def names (a Door, as a delve's is), with the tally-stick hook.
static func rooftop_shaft(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var site: Dictionary = ContentDB.get_or_empty(d.poi_id).get("site", {})
	var road := k.road_direction(160.0)
	var out := road.normalized() if road != Vector2.ZERO else k.downhill()
	if out == Vector2.ZERO:
		out = Vector2(0.0, 1.0)
	var side := Vector2(out.y, -out.x)
	var ground := k.on_ground(0.0, 0.0).y

	# the hole, and the Builders' roof it broke through: dark fused tiles tilted round its lip
	if not k.far:
		await k.step()
		m.pool(Vector2.ZERO, 1.55, ground + 0.03, PoiKit.plain(HOLE, 1.0), "Shaft", 18)
	var tiles := m.begin()
	for i in 12:
		var a := TAU * float(i) / 12.0 + k.rng.randf_range(-0.12, 0.12)
		var r := k.rng.randf_range(1.8, 2.3)
		var at := Vector2(sin(a), cos(a)) * r
		var g := k.on_ground(at.x, at.y, 0.08)
		var tilt := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.35, -0.12))
		m.block(tiles, Transform3D(tilt, g), Vector3(k.rng.randf_range(0.8, 1.2), 0.18, k.rng.randf_range(0.5, 0.8)))
	await k.step()
	m.commit(tiles, k.surface("oroth", 0.6), "RoofTiles", true)

	# the headframe: four legs leaning in to a crown, a windlass across two of them, the rope down
	var timber := m.begin()
	var crown := Vector3(0.0, ground + 4.3, 0.0)
	var legs: Array = []
	for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		var foot := out * 2.5 * float(s[0]) + side * 2.5 * float(s[1])
		var f := k.on_ground(foot.x, foot.y, -0.2)
		legs.append(f)
		m.limb(timber, f, crown + Vector3(out.x * 0.35 * float(s[0]), 0.0, out.y * 0.35 * float(s[0])), 0.11)
		k.collider(Vector3(0.24, 0.24, 0.24), Transform3D(Basis.IDENTITY, f + Vector3(0.0, 0.3, 0.0)), "wood")
	m.limb(timber, crown - Vector3(out.x, 0.0, out.y) * 0.5, crown + Vector3(out.x, 0.0, out.y) * 0.5, 0.12)
	var wl_a: Vector3 = (legs[0] as Vector3).lerp(crown, 0.28)
	var wl_b: Vector3 = (legs[3] as Vector3).lerp(crown, 0.28)
	m.limb(timber, wl_a, wl_b, 0.16)
	var crank := wl_b + Vector3(side.x, 0.0, side.y) * -0.1 + Vector3(0.0, -0.35, 0.0)
	m.limb(timber, wl_b, crank, 0.04)
	# the ladder's top, going down into the dark on the far side from the road
	var lad := -out * 1.0
	for s in [-1.0, 1.0]:
		var r0 := lad + side * 0.3 * float(s)
		m.limb(timber, Vector3(r0.x, ground + 0.9, r0.y), Vector3(r0.x - out.x * 0.15, ground - 2.6, r0.y - out.y * 0.15), 0.04)
	for i in 5:
		var y := ground + 0.6 - float(i) * 0.7
		var c := lad - out * (0.03 * float(i))
		m.limb(timber, Vector3(c.x + side.x * -0.3, y, c.y + side.y * -0.3), Vector3(c.x + side.x * 0.3, y, c.y + side.y * 0.3), 0.025)
	await k.step()
	m.commit(timber, k.surface("timber", 0.75), "Headframe", true)
	var rope := m.begin()
	m.limb(rope, crown + Vector3(0.0, -0.1, 0.0), Vector3(0.0, ground - 3.0, 0.0), 0.02)
	await k.step()
	m.commit(rope, PoiKit.plain(FLAX, 0.95), "Rope")
	if k.far:
		return

	# the way down: at the ladder's head, facing out of the hole
	var interior := str(site.get("interior", ""))
	if interior != "" and ContentDB.has(interior):
		var door := Door.new()
		door.name = "Door_" + Ids.name_of(interior)
		door.interior_id = interior
		door.display_name = str(ContentDB.get_or_empty(interior).get("name", "the dark"))
		var at := k.on_ground(lad.x, lad.y)
		door.position = Vector3(at.x, ground - 0.9, at.z)
		door.rotation.y = atan2(out.x, out.y)
		d.add_child(door)
		SiteInterior.prefetch(ContentDB.get_or_empty(interior))
	k.marker("the_headframe", k.on_ground(out.x * 3.4, out.y * 3.4))

	# the spoil: ash heaped where it came up, the heaps further out the older
	var ash := k.surface("earth", 0.9)
	ash.set_shader_parameter("base_color", Color(0.46, 0.45, 0.43))
	ash.set_shader_parameter("accent_color", Color(0.36, 0.35, 0.34))
	var heaps := [[-0.9, 5.5, 1.9, 1.3], [0.6, 7.5, 2.6, 1.7], [2.1, 10.5, 3.2, 2.0], [3.6, 12.5, 2.6, 1.4]]
	for h in heaps:
		var a := float(h[0]) + PoiKit.yaw_of(-out)
		var at := Vector2(sin(a), cos(a)) * float(h[1])
		if k.road_distance(at) < float(h[2]) + PoiKit.ROAD_CLEAR_M:
			continue
		await k.step()
		m.mound(k.on_ground(at.x, at.y, -0.1), float(h[2]), float(h[3]), ash, "Spoil", true, 1.4, 6, 16)

	# the scavengers' leavings: sieves, a crate of bronze, a barrel, a cut rope, a lamp gone out
	var gear := out * 4.2 + side * 2.6
	await k.step()
	k.place(k.prop("basket"), k.on_ground(gear.x, gear.y), k.rng.randf_range(0.0, TAU))
	var gear2 := gear + side * 1.0 - out * 0.4
	await k.step()
	k.place(k.prop("basket"), k.on_ground(gear2.x, gear2.y), k.rng.randf_range(0.0, TAU), 0.9)
	var crate_at := out * 5.6 - side * 2.4
	await k.step()
	k.place(k.prop("crate"), k.on_ground(crate_at.x, crate_at.y), PoiKit.yaw_of(out))
	var bronze := m.begin()
	var ctop := k.on_ground(crate_at.x, crate_at.y).y + 0.62
	for i in 5:
		var at := crate_at + k.jitter(0.25)
		m.block(bronze, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), Vector3(at.x, ctop + 0.05 * float(i), at.y)),
				Vector3(k.rng.randf_range(0.18, 0.35), 0.05, k.rng.randf_range(0.1, 0.2)))
	await k.step()
	m.commit(bronze, PoiKit.plain(BRONZE, 0.45, 0.8), "Bronze")
	var barrel := out * 6.4 - side * 3.4
	await k.step()
	k.place(k.prop("barrel"), k.on_ground(barrel.x, barrel.y), 0.0)
	var coil := side * 3.3 - out * 1.2
	await k.step()
	k.place(k.prop("rope_coil"), k.on_ground(coil.x, coil.y), k.rng.randf_range(0.0, TAU))
	var lamp := side * -2.9 + out * 1.4
	await k.step()
	k.place(k.prop("lantern_hand"), k.on_ground(lamp.x, lamp.y), 0.0, 1.0, false)
	# the tally-stick on its post, where the site's quest starts
	await PoiDressing.kind_builders().SITES._hook(d, site, Vector3(out.x, 0.0, out.y) * 3.6 - Vector3(side.x, 0.0, side.y) * 3.2)


# --- Ashcombe Mill ----------------------------------------------------------------------------------

## The kind's windmill (its sails turning), and by the door the miller's sack-tally: a board on a
## post, chalked a line a sack, the last line fresh. Touching it reads it.
static func ashcombe_mill(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().LAND.mill(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var face: Vector2 = -PoiDressing.kind_builders().LAND.WIND
	var side := Vector2(face.y, -face.x)
	var door := face * 3.6
	var at := door + face * 1.9 - side * 1.3
	if k.road_distance(at) < PoiKit.ROAD_CLEAR_M:
		at = door + face * 1.9 - side * 3.4
	var timber := m.begin()
	var top := m.post(timber, at, 1.7, 0.14)
	var board_at := top + Vector3.DOWN * 0.45
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), board_at + Vector3(face.x, 0.0, face.y) * 0.09), Vector3(0.7, 0.55, 0.04))
	await k.step()
	m.commit(timber, k.surface("planks", 0.8), "TallyBoard")
	# the chalk: a white stroke for each sack, rows of them, on the side of the board facing out
	var chalk := m.begin()
	var right := Vector3(side.x, 0.0, side.y)
	var fwd := Vector3(face.x, 0.0, face.y)
	for row in 5:
		for i in (9 if row < 4 else 4):
			var p := board_at + fwd * 0.115 + right * (-0.28 + float(i) * 0.065) + Vector3.UP * (0.2 - float(row) * 0.1)
			m.block(chalk, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(face)), p), Vector3(0.012, 0.07, 0.004))
	await k.step()
	m.commit(chalk, PoiKit.plain(Color(0.88, 0.87, 0.84), 0.95), "Chalk")
	k.touchable("the_tally", board_at + fwd * 0.3, "Read the sack-tally", "core:dialogue/ashcombe_mill_tally", "", false)


# --- the places whose people keep a spot ------------------------------------------------------------

## The kind's own place, and the spots its people stand at by day (NpcRegistry.spot_marker): without
## one a person of a place the world was not built with has nowhere to stand. `spots` is
## [[name, metres out, bearing off the way to the road in radians], ...].
static func _kind_with_spots(d: PoiDressing, build: Callable, spots: Array) -> void:
	await build.call(d)
	var k := d.kit
	if k.far:
		return
	var road := k.road_direction(160.0)
	var face := road.normalized() if road != Vector2.ZERO else k.downhill()
	if face == Vector2.ZERO:
		face = Vector2(0.0, 1.0)
	for s in spots:
		var at := face.rotated(float(s[2])) * float(s[1])
		if k.road_distance(at) < PoiKit.ROAD_CLEAR_M + 0.5:
			at = face.rotated(float(s[2]) + PI) * float(s[1])
		k.marker(str(s[0]), k.on_ground(at.x, at.y), true)


## Morwen Tarrant's shieling: she works at the fold, off the hut's side.
static func greyfleece_shieling(d: PoiDressing) -> void:
	await _kind_with_spots(d, Callable(PoiDressing.kind_builders().LAND, "shieling"), [["the_fold", 7.0, 1.2]])


## Eddery Wray's shelter: he counts facing his boulder, a pace or two in front of it.
static func bell_counters_hut(d: PoiDressing) -> void:
	await _kind_with_spots(d, Callable(PoiDressing.kind_builders().WAYSIDE, "hut"), [["the_stone", 3.2, 0.6]])


## The Scavengers' Ring: Coll at the roof-boss hearth in the yard, Jory at the gate.
static func scavengers_ring(d: PoiDressing) -> void:
	await _kind_with_spots(d, Callable(PoiDressing.kind_builders().SITES, "build"), [["ring_hearth", 3.5, 0.9], ["the_gate", 11.0, 0.0]])


## The Sayers' Gauge: the Surveyor at the foot of the tower's outside stair, outside its low wall.
static func sayers_gauge(d: PoiDressing) -> void:
	await _kind_with_spots(d, Callable(PoiDressing.kind_builders().SITES, "build"), [["the_gauge_foot", 12.0, 0.5]])
