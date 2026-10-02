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
const SAIL := Color(0.47, 0.43, 0.36)
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
	m.commit(sail, PoiKit.painted(6, {"base": "#776d5b", "accent": "#5d5546", "grout": "#3f392f", "unit": 0.6}, 0.9), "Sail", true)
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
	# grey ash turned up from below, weathered to the heath's own colour (the plain earth shader
	# lit white in the first sheet: the colours set after it was made did not take)
	var ash := PoiKit.painted(5, {"base": "#5c5955", "accent": "#46443f", "grout": "#2e2c29", "unit": 0.35}, 0.85)
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
	_settle(d)


## The Sayers' Gauge: the Surveyor at the foot of the tower's outside stair, outside its low wall.
static func sayers_gauge(d: PoiDressing) -> void:
	await _kind_with_spots(d, Callable(PoiDressing.kind_builders().SITES, "build"), [["the_gauge_foot", 12.0, 0.5]])


# === the Builders' city and the heath, second pass (world life phase 2) =============================
#
# The first pass left eighteen of the region's ruins as one of two shared shapes: the kind's hall
# (a box of courses with one gable and a campfire in it, which read the same at Bell Street as at
# the Weighhouse) or the kind's colonnade (steps out of water, with reeds, on a dry plateau). Each
# place here is built from its own sentence instead, in the Builders' fused stone and their bronze,
# with something to find in it: the bell that is not hollow, the fountain's count, the stall with
# fresh bread on it, the scales with the other pan down.

## Bell bronze gone green: a dark bronze mottled with verdigris (painted_surface's plaster mottle).
const VERDIGRIS := {"base": "#4e4029", "accent": "#3f6f5f", "grout": "#231d14", "unit": 0.55}
## Ash heaped by the wind, the heath's own colour.
const ASH_HEAP := {"base": "#5c5955", "accent": "#46443f", "grout": "#2e2c29", "unit": 0.35}
## A great bell's profile: [radius, height] as fractions of its mouth's radius and its height, from
## the lip up (a sound-bow, a waist narrowing to the shoulder, the crown).
const BELL := [Vector2(1.0, 0.0), Vector2(1.06, 0.03), Vector2(1.06, 0.055), Vector2(0.99, 0.075),
		Vector2(0.98, 0.1), Vector2(0.87, 0.17), Vector2(0.77, 0.3), Vector2(0.7, 0.46), Vector2(0.67, 0.6),
		Vector2(0.69, 0.615), Vector2(0.69, 0.64), Vector2(0.66, 0.655), Vector2(0.64, 0.75), Vector2(0.61, 0.82),
		Vector2(0.63, 0.84), Vector2(0.6, 0.86), Vector2(0.52, 0.91), Vector2(0.33, 0.965), Vector2(0.0, 0.985)]
## Its inside, a bronze's thickness in, from the crown down to the lip (so it faces in).
const BELL_IN := [Vector2(0.0, 0.93), Vector2(0.45, 0.88), Vector2(0.55, 0.8), Vector2(0.58, 0.62),
		Vector2(0.62, 0.46), Vector2(0.69, 0.3), Vector2(0.79, 0.17), Vector2(0.9, 0.07), Vector2(0.93, 0.0)]


## One mesh of several surfaces, each its own material: a thing and what is fixed to it (a pole and
## its rag, a wall and the chalk on it, a tower and its rope) are one piece standing on the ground,
## not a mark hung in the air beside a wall. Made at once, even for a place raised while the world
## is drawn (they are small). `parts` is [[SurfaceTool, Material], ...].
static func _commit_parts(d: PoiDressing, parts: Array, node_name: String, silhouette := false) -> MeshInstance3D:
	var k := d.kit
	if k.far and not silhouette:
		return null
	var mesh := ArrayMesh.new()
	for part in parts:
		var st: SurfaceTool = part[0]
		st.generate_normals()
		var arrays := st.commit_to_arrays()
		if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, part[1])
	if mesh.get_surface_count() == 0:
		return null
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.name = node_name
	k.root.add_child(inst)
	if k.far:
		k._far_range(inst)
	return inst


## One block of stone with its faces flat. The kit's `block` is smoothed with everything round it
## when the batch's normals are made (SurfaceTool shares a normal between faces that meet at a
## corner), and a wall of them photographed as a stack of sandbags at the Hermit's Gate; these are
## laid in no smoothing group, each face its own.
static var _cube := PackedVector3Array()


static func _box(st: SurfaceTool, xform: Transform3D, size: Vector3) -> void:
	if _cube.is_empty():
		var arrays := PoiMasonry._unindexed_box().surface_get_arrays(0)
		_cube = arrays[Mesh.ARRAY_VERTEX]
	var xf := xform.orthonormalized().scaled_local(size)
	st.set_smooth_group(0xFFFFFFFF)
	for v in _cube:
		st.add_vertex(xf * v)
	st.set_smooth_group(0)


## A straight run of courses from `a` to `b` (local xz) on the ground, as the kit's `wall`, its blocks
## flat-faced (`_box`): a bay a metre long, each course stepped in a hand, torn down by `broken`
## from a point along it. Collides as one box to its lowest top.
static func _wall(d: PoiDressing, st: SurfaceTool, a: Vector2, b: Vector2, height: float, broken := 0.0) -> void:
	var k := d.kit
	var seg := b - a
	var length := seg.length()
	if length < 0.3:
		return
	var dir := seg / length
	var yaw := atan2(dir.x, dir.y)
	var course := PoiMasonry.COURSE * 1.6
	var bays := maxi(int(round(length / 1.1)), 1)
	var courses := maxi(int(ceil(height / course)), 1)
	var tear_from := k.rng.randf_range(0.2, 0.8)
	var tops: Array[float] = []
	for i in bays + 1:
		var t := float(i) / float(bays)
		tops.append(height * (1.0 - broken * clampf((t - tear_from) / maxf(1.0 - tear_from, 0.05), 0.0, 1.0) * k.rng.randf_range(0.6, 1.2)))
	var min_h := height
	for i in bays:
		var top: float = minf(tops[i], tops[i + 1])
		min_h = minf(min_h, top)
		var q0 := a + dir * (length * float(i) / float(bays))
		var q1 := a + dir * (length * float(i + 1) / float(bays))
		var g0 := k.on_ground(q0.x, q0.y).y
		var g1 := k.on_ground(q1.x, q1.y).y
		var foot := minf(g0, g1) - 0.1
		var mid_g := (g0 + g1) * 0.5
		var p := (q0 + q1) * 0.5
		for c in courses:
			var y0 := foot if c == 0 else mid_g + course * float(c)
			var y1 := minf(mid_g + course * float(c + 1), mid_g + top)
			if y1 <= y0 + 0.02:
				break
			var thick := PoiMasonry.THICK + 0.1 - float(c) * 0.02
			_box(st, Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(p.x, (y0 + y1) * 0.5, p.y)),
					Vector3(length / float(bays) * 1.01, y1 - y0 - 0.015, thick))
	var mid := (a + b) * 0.5
	var h := maxf(min_h, course)
	var ga := k.on_ground(mid.x, mid.y).y
	k.collider(Vector3(length, h, PoiMasonry.THICK + 0.1), Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(mid.x, ga + h * 0.5, mid.y)), "stone")


static func _bronze() -> ShaderMaterial:
	return PoiKit.painted(0, VERDIGRIS, 0.8, 0.85)


static func _ash() -> ShaderMaterial:
	return PoiKit.painted(5, ASH_HEAP, 0.85)


## A surface of revolution about `xf`'s Y: `profile` is [Vector2(radius, height)] in order, swept
## round in `segments`; it faces out (or in, with `inward`). Each triangle also goes into `faces`
## when given, for a collision shape that follows it.
static func _lathe(st: SurfaceTool, xf: Transform3D, profile: Array, segments := 20, inward := false,
		faces: Variant = null) -> void:
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		for s in segments:
			var a0 := TAU * float(s) / float(segments)
			var a1 := TAU * float(s + 1) / float(segments)
			var a := xf * Vector3(sin(a0) * p0.x, p0.y, cos(a0) * p0.x)
			var b := xf * Vector3(sin(a1) * p0.x, p0.y, cos(a1) * p0.x)
			var c := xf * Vector3(sin(a1) * p1.x, p1.y, cos(a1) * p1.x)
			var dd := xf * Vector3(sin(a0) * p1.x, p1.y, cos(a0) * p1.x)
			# Godot's front faces wind clockwise seen from the side they face
			var tris := [a, b, dd, b, c, dd] if inward else [a, dd, b, b, dd, c]
			for v in tris:
				st.add_vertex(v)
			if faces != null:
				(faces as PackedVector3Array).append_array(PackedVector3Array(tris))


## A frame whose Y runs along `up`, standing at `at`.
static func _frame_up(at: Vector3, up: Vector3, turn := 0.0) -> Transform3D:
	var y := up.normalized()
	var x := y.cross(Vector3.BACK)
	if x.length() < 0.1:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z) * Basis(Vector3.UP, turn), at)


## One of the Builders' bells: its mouth's middle at `base`, its crown along `up`, `mouth_r` across
## the mouth and `h` high, lathed in bronze with its inside and the loop on its crown. Collides as a
## hull unless `walk_in` (a bell on its side you can go into), which collides as drawn. Returns the
## crown's top.
static func _bell(d: PoiDressing, st: SurfaceTool, base: Vector3, up: Vector3, mouth_r: float, h: float,
		inside := true, walk_in := false) -> Vector3:
	var k := d.kit
	var xf := _frame_up(base, up, k.rng.randf_range(0.0, TAU))
	var outer: Array = []
	for p: Vector2 in BELL:
		outer.append(Vector2(p.x * mouth_r, p.y * h))
	var faces: Variant = null
	if walk_in:
		faces = PackedVector3Array()
	var segs := 22 if mouth_r > 1.5 else 16
	_lathe(st, xf, outer, segs, false, faces)
	if inside:
		var inner: Array = []
		for p: Vector2 in BELL_IN:
			inner.append(Vector2(p.x * mouth_r, p.y * h))
		# the inside runs crown to lip, so its faces are the outer's turned in already
		_lathe(st, xf, inner, segs, false, faces)
		# the lip's own face, between the outside and the in
		_lathe(st, xf, [Vector2(mouth_r * 0.93, 0.0), Vector2(mouth_r * 1.0, 0.0)], segs, false, faces)
	# the canons: a loop of bronze on the crown
	var top := xf * Vector3(0.0, h * 0.985, 0.0)
	var r := mouth_r * 0.16
	for i in 6:
		var a0 := PI * float(i) / 6.0
		var a1 := PI * float(i + 1) / 6.0
		d.masonry.limb(st, xf * Vector3(cos(a0) * r, h * 0.97 + sin(a0) * r * 1.3, 0.0),
				xf * Vector3(cos(a1) * r, h * 0.97 + sin(a1) * r * 1.3, 0.0), mouth_r * 0.045)
	if k.far:
		return top
	if walk_in:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces as PackedVector3Array)
		k.collider_shape(shape, Transform3D.IDENTITY, "metal")
	else:
		var pts := PackedVector3Array()
		for p: Vector2 in outer:
			for s in 10:
				var a := TAU * float(s) / 10.0
				pts.append(xf * Vector3(sin(a) * p.x, p.y, cos(a) * p.x))
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		k.collider_shape(hull, Transform3D.IDENTITY, "metal")
	return top


## The nearest road through the place within `reach`: [its nearest point to the middle (local), its
## direction there], or [] where none runs near.
static func _road_line(k: PoiKit, reach := 40.0) -> Array:
	var here := Vector2(k.origin.x, k.origin.z)
	var best := INF
	var out: Array = []
	for s in k.roads_near(reach):
		var a := s[0] - here
		var b := s[1] - here
		if a.distance_to(b) < 0.5:
			continue
		var q := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, a, b)
		if q.length() < best and q.length() <= reach:
			best = q.length()
			out = [q, (b - a).normalized()]
	return out


## The way a place is laid along: its road's direction where one runs through it, else the grain.
static func _lie(k: PoiKit) -> Array:
	var line := _road_line(k)
	if not line.is_empty():
		return [line[0], line[1]]
	var g := k.grain()
	if g == Vector2.ZERO:
		g = Vector2(1.0, 0.0)
	return [Vector2.ZERO, g.normalized()]


## Clear of every road's carriageway by `margin` beyond a body's verge.
static func _off_road(k: PoiKit, at: Vector2, margin := 0.0) -> bool:
	return k.road_distance(at) >= PoiKit.ROAD_CLEAR_M + 1.2 + margin


## A round arch of fused stone: two piers `pier` square and `spring` high standing either side of
## `at` across `axis`'s normal, the opening `span` wide, and a ring of voussoirs over it `ring`
## deep. All of it collides. Returns the arch's crown (local).
static func _arch(d: PoiDressing, st: SurfaceTool, at: Vector2, axis: Vector2, span: float, spring: float,
		pier := 1.6, depth := 1.6, ring := 0.9, voussoirs := 11) -> Vector3:
	var k := d.kit

	var across := Vector2(axis.y, -axis.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(axis))
	var g := INF
	for s in [-1.0, 1.0]:
		var foot: Vector2 = at + across * (span * 0.5 + pier * 0.5) * float(s)
		g = minf(g, k.on_ground(foot.x, foot.y).y)
	for s in [-1.0, 1.0]:
		var foot: Vector2 = at + across * (span * 0.5 + pier * 0.5) * float(s)
		var fg := k.on_ground(foot.x, foot.y).y
		var xf := Transform3D(basis, Vector3(foot.x, (fg - 0.3 + g + spring) * 0.5, foot.y))
		var size := Vector3(pier, g + spring - fg + 0.3, depth)
		_box(st, xf, size)
		k.collider(size, xf, "stone")
		# an impost course where the arch springs, stepped out a hand
		_box(st, Transform3D(basis, Vector3(foot.x, g + spring - 0.15, foot.y)), Vector3(pier + 0.3, 0.3, depth + 0.3))
	var r := span * 0.5 + ring * 0.5
	var centre := Vector3(at.x, g + spring, at.y)
	# the arch's plane: x across the opening, y up, z along `axis`
	var plane := Basis(Vector3.UP, PoiKit.yaw_of(axis))
	for i in voussoirs:
		var a := PI * (float(i) + 0.5) / float(voussoirs)
		var p := centre + plane * Vector3(cos(a) * r, sin(a) * r, 0.0)
		var b := plane * Basis(Vector3.BACK, a - PI * 0.5)
		var size := Vector3(PI * r / float(voussoirs) * 1.03, ring, depth)
		_box(st, Transform3D(b, p), size)
		k.collider(size, Transform3D(b, p), "stone")
	return centre + Vector3(0.0, r + ring * 0.5, 0.0)


## Triangles drawn from both sides: `tris` as given in smoothing group 1, and turned over in group 2.
static func _two_sided(st: SurfaceTool, tris: Array) -> void:
	st.set_smooth_group(1)
	for v in tris:
		st.add_vertex(v)
	st.set_smooth_group(2)
	for i in range(0, tris.size(), 3):
		st.add_vertex(tris[i])
		st.add_vertex(tris[i + 2])
		st.add_vertex(tris[i + 1])
	st.set_smooth_group(0)


## Ash heaped against something by the wind: a low drift, walkable.
static func _drift(d: PoiDressing, at: Vector2, r: float, h: float, collide := true) -> void:
	await d.kit.step()
	d.masonry.mound(d.kit.on_ground(at.x, at.y, -0.15), r, h, _ground(d.kit, at), "AshDrift", collide, 1.3, 5, 14, false, 0.12)


## The ground's own look where a drift or a bank of it is heaped: the terrain's texture there, so
## the ash a builder heaps is the ash the land is made of (a painted ash read as snow beside it).
static func _ground(k: PoiKit, at: Vector2) -> Material:
	return PoiDressing.kind_builders()._ground_look(k, at)


## Something to open: a chest, a crate, a sarcophagus or a barrel, its contents rolled from `table`
## once and kept (WorldContainer, keyed by the place and `label`, so what was taken stays taken).
static func _cache(d: PoiDressing, at: Vector3, yaw: float, kind: String, table: String, label: String) -> void:
	var k := d.kit
	if k.far:
		return
	await k.step()
	var look := k.place(k.prop(kind), at, yaw, 1.0, false)
	var box := WorldContainer.new()
	box.name = "Container_" + label
	box.container_id = "%s/%s" % [d.poi_id, label]
	box.loot_table = table
	box.display_name = {"chest": "Chest", "crate": "Crate", "sarcophagus": "Sarcophagus", "barrel": "Barrel",
			"basket": "Basket"}.get(kind, "Chest")
	var cs := CollisionShape3D.new()
	var form := BoxShape3D.new()
	form.size = {"sarcophagus": Vector3(2.2, 0.9, 1.0), "barrel": Vector3(0.7, 1.0, 0.7),
			"basket": Vector3(0.6, 0.5, 0.6)}.get(kind, Vector3(1.0, 0.7, 0.6))
	cs.shape = form
	cs.position.y = form.size.y * 0.5
	box.add_child(cs)
	box.position = at
	box.rotation.y = yaw
	k.root.add_child(box)
	if look != null:
		look.set_meta("container", box.container_id)


## Footprints in the ash from `a` to `b` (local), a pace apart, left and right: little dark
## hollows, one mesh. `stop` of the way along they end, as if whoever made them went on in air.
static func _footprints(d: PoiDressing, a: Vector2, b: Vector2, stop := 1.0) -> void:
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var st := m.begin()
	var dir := (b - a).normalized()
	var side := Vector2(dir.y, -dir.x)
	var n := int(a.distance_to(b) * stop / 0.75)
	for i in n:
		var p := a + dir * (0.75 * float(i)) + side * (0.14 if i % 2 == 0 else -0.14)
		var g := k.on_ground(p.x, p.y, 0.02)
		_box(st, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(dir) + k.rng.randf_range(-0.12, 0.12)), g),
				Vector3(0.13, 0.025, 0.29))
	await k.step()
	m.commit(st, PoiKit.plain(Color(0.09, 0.085, 0.08), 0.95), "Footprints")


## The Builders' broken stone lying about: lumps of fused masonry, half in the ash.
static func _rubble(d: PoiDressing, centre: Vector2, reach: float, count: int, size := Vector2(0.25, 0.6)) -> void:
	var k := d.kit
	var lumps: Array = []
	for i in count:
		var p := centre + Vector2(k.rng.randf_range(-reach, reach), k.rng.randf_range(-reach, reach))
		if not _off_road(k, p):
			continue
		lumps.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.1), k.rng.randf_range(0.0, TAU),
				k.rng.randf_range(size.x, size.y), Vector3(k.rng.randf_range(-0.3, 0.3), 0.0, k.rng.randf_range(-0.3, 0.3))))
	await k.step()
	k.scatter(k.rock("boulder"), lumps, true)


## Grey grass in tufts round a place, kept off the roads.
static func _grey_grass(d: PoiDressing, reach: float, count: int, centre := Vector2.ZERO) -> void:
	var k := d.kit
	var tufts: Array = []
	for i in count:
		var p := centre + k.jitter(reach)
		if k.road_distance(p) < 2.5:
			continue
		tufts.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.7, 1.2)))
	await k.step()
	k.scatter(k.flora("grey_grass"), tufts, false, false, false)


# --- Bell Street --------------------------------------------------------------------------------------

## A street of the dead city, the Greyfold road still running down it, lined both sides with bells
## the size of houses sunk to their shoulders in the ash: green bronze domes six to eight metres
## across, each a house's lintel showing between it and the next, the kerbs of the old street
## broken along the road's edges, ash drifted against the bells' windward sides. One bell has
## gone over onto its side by the road with its mouth to the street: the wights shelter in it, and
## somebody's sack of scavenged bronze is in it too. Knock on the bells and they ring hollow, all
## but one, which answers like a hill (the rumour the Sayers and the Order argue over).
static func bell_street(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lie := _lie(k)
	var mid: Vector2 = lie[0]
	var along: Vector2 = lie[1]
	var across := Vector2(-along.y, along.x)
	# [along, side, mouth radius, height]: house-sized bells, not one alike
	var row := [[-15.0, 1.0, 3.2, 8.4], [-4.0, 1.0, 3.7, 9.4], [8.0, 1.0, 3.0, 7.8],
			[-10.0, -1.0, 3.5, 9.0], [2.5, -1.0, 2.9, 7.4], [15.5, -1.0, 3.4, 8.8]]
	var solid := 2          # the one that is not hollow
	var sides := {1.0: m.begin(), -1.0: m.begin()}
	var tops: Array = []
	for i in row.size():
		var b: Array = row[i]
		var mouth_r: float = b[2]
		var h: float = b[3]
		# its waist at the ground (about 0.7 of its mouth) stands clear of the road's verge
		var at: Vector2 = mid + along * float(b[0]) + across * float(b[1]) * (mouth_r * 0.72 + 4.2)
		var sink := h * k.rng.randf_range(0.48, 0.56)
		var g := k.on_ground(at.x, at.y)
		var lean := Vector3(k.rng.randf_range(-0.05, 0.05), 1.0, k.rng.randf_range(-0.05, 0.05))
		await k.step()
		var top := _bell(d, sides[float(b[1])], g - Vector3(0.0, sink, 0.0), lean, mouth_r, h, false)
		tops.append([at, top, mouth_r, h - sink])
		# the wind's drift against it, on the side away from the street
		var lee := at + across * float(b[1]) * (mouth_r * 0.7 + 0.6) + along * k.rng.randf_range(-1.0, 1.0)
		await _drift(d, lee, mouth_r * 0.75, 0.9 + k.rng.randf() * 0.5)
	await k.step()
	m.commit(sides[1.0], _bronze(), "BellsNorth", true)
	m.commit(sides[-1.0], _bronze(), "BellsSouth", true)

	# the one gone over, mouth to the street: a bell you can stand in
	var fs := 1.0
	var fallen := mid + along * 17.5 + across * 7.0
	if not _off_road(k, fallen, 2.5):
		fs = -1.0
		fallen = mid - along * 17.5 - across * 7.0
	# from the bell's crown towards the street, which its mouth faces
	var into := -across * fs
	var fr := 2.4
	var fh := 6.2
	var lying := m.begin()
	var mouth_at := k.on_ground(fallen.x, fallen.y, fr * 0.78)
	_bell(d, lying, mouth_at + Vector3(into.x, 0.0, into.y) * 0.4, Vector3(-into.x, -0.08, -into.y), fr, fh, true, true)
	await k.step()
	m.commit(lying, _bronze(), "FallenBell", true)
	if not k.far:
		var inside := fallen - into * 2.6
		k.marker("in_the_bell", k.on_ground(inside.x, inside.y, 0.0))
		await _cache(d, k.on_ground(inside.x - into.x * 1.2, inside.y - into.y * 1.2, 0.05), PoiKit.yaw_of(into), "crate",
				"core:loot/oroth_cache", "bell_sack")
		await _drift(d, fallen - into * 4.6, 2.2, 0.8)

	if k.far:
		return
	# the street's kerbs, broken, along both edges of the road, and the houses' lintels between the bells
	var stone := m.begin()
	for s in [-1.0, 1.0]:
		var t := -20.0
		while t < 20.0:
			var run := k.rng.randf_range(1.6, 3.8)
			if k.rng.randf() < 0.75:
				var c := mid + along * (t + run * 0.5) + across * float(s) * 3.3
				if _off_road(k, c, -0.8):
					_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(along)), k.on_ground(c.x, c.y, 0.08)),
							Vector3(0.5, 0.45, run))
			t += run + k.rng.randf_range(0.2, 1.4)
	for i in range(tops.size() - 1):
		var a: Array = tops[i]
		var b: Array = tops[i + 1]
		if (a[0] as Vector2).distance_to(b[0] as Vector2) > 16.0:
			continue
		var at: Vector2 = ((a[0] as Vector2) + (b[0] as Vector2)) * 0.5
		var face := (mid - at).normalized()
		var yaw := PoiKit.yaw_of(face)
		var g := k.on_ground(at.x, at.y)
		# the head of a buried doorway: two jambs a hand out of the ash and the lintel over them
		for s in [-1.0, 1.0]:
			var j := at + Vector2(face.y, -face.x) * 0.95 * float(s)
			_box(stone, Transform3D(Basis(Vector3.UP, yaw), k.on_ground(j.x, j.y, 0.35)), Vector3(0.5, 1.1, 0.6))
		_box(stone, Transform3D(Basis(Vector3.UP, yaw), g + Vector3(0.0, 1.05, 0.0)), Vector3(2.6, 0.5, 0.7))
		k.collider(Vector3(2.6, 1.3, 0.7), Transform3D(Basis(Vector3.UP, yaw), g + Vector3(0.0, 0.65, 0.0)), "stone")
		await _drift(d, at - face * 1.2, 1.8, 0.7, false)
	await k.step()
	m.commit(stone, k.surface("oroth", 0.7), "Kerbs")
	# the bell that is not hollow
	var sb: Array = tops[solid]
	var knock := (sb[0] as Vector2) + (mid - (sb[0] as Vector2)).normalized() * (float(sb[2]) * 0.68 + 0.6)
	k.touchable("the_solid_bell", k.on_ground(knock.x, knock.y, 1.2), "Knock on the bell",
			"core:dialogue/bell_street_knock", "", false)
	k.marker("the_street", k.on_ground(mid.x, mid.y))
	await _rubble(d, mid, 18.0, 16)
	await _grey_grass(d, 20.0, 40)


# --- the Sunk Plaza -----------------------------------------------------------------------------------

const PLAZA_HALF := 8.0
const PLAZA_STEPS := 6
const PLAZA_RISE := 0.28
const PLAZA_TREAD := 0.55

## A Builders' square sunk six steps into the ash: the paving where the two tracks meet, a flight
## of six steps all the way round rising to the ash's level, the ash heaped over the rim, a headless
## chorister on a plinth at each corner (the Choir's figures, small), and off the middle the dry
## fountain, its basin full of pilgrims' hand-bells to the brim. The Order counts them every spring;
## this year there is one more bell than there were pilgrims.
static func sunk_plaza(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lie := _lie(k)
	var along: Vector2 = lie[1]
	var across := Vector2(-along.y, along.x)
	var yaw := PoiKit.yaw_of(along)
	var basis := Basis(Vector3.UP, yaw)
	var g := k.on_ground(0.0, 0.0).y
	var floor_y := g + 0.06
	var paving := m.begin()
	# the floor, a hand proud of the pad, and the steps going up all round it as nested courses
	var floor_xf := Transform3D(basis, Vector3(0.0, floor_y - 0.25, 0.0))
	_box(paving, floor_xf, Vector3(PLAZA_HALF * 2.0, 0.5, PLAZA_HALF * 2.0))
	k.collider(Vector3(PLAZA_HALF * 2.0, 0.5, PLAZA_HALF * 2.0), floor_xf, "stone")
	for i in PLAZA_STEPS:
		var inner := PLAZA_HALF + PLAZA_TREAD * float(i)
		var outer := inner + PLAZA_TREAD
		var top := floor_y + PLAZA_RISE * float(i + 1)
		var h := top - (g - 0.4)
		var cy := (top + g - 0.4) * 0.5
		var side_len := outer * 2.0
		for s in [-1.0, 1.0]:
			var c1 := basis * Vector3(0.0, 0.0, (inner + PLAZA_TREAD * 0.5) * float(s))
			var x1 := Transform3D(basis, Vector3(c1.x, cy, c1.z))
			_box(paving, x1, Vector3(side_len, h, PLAZA_TREAD))
			k.collider(Vector3(side_len, h, PLAZA_TREAD), x1, "stone")
			var c2 := basis * Vector3((inner + PLAZA_TREAD * 0.5) * float(s), 0.0, 0.0)
			var x2 := Transform3D(basis, Vector3(c2.x, cy, c2.z))
			_box(paving, x2, Vector3(PLAZA_TREAD, h, inner * 2.0))
			k.collider(Vector3(PLAZA_TREAD, h, inner * 2.0), x2, "stone")
		if i % 2 == 1:
			await k.step()
	await k.step()
	m.commit(paving, k.surface("oroth", 0.55), "PlazaPaving", true)
	var rim := PLAZA_HALF + PLAZA_TREAD * float(PLAZA_STEPS)

	# the ash the square was dug out of, banked from the rim down to the heath all round, and
	# heaped deeper in drifts on it, never across the tracks
	await _skirt(d, basis, rim, rim + 4.5, floor_y + PLAZA_RISE * float(PLAZA_STEPS))
	for i in 8:
		var a := TAU * float(i) / 8.0 + k.rng.randf_range(-0.15, 0.15)
		var p := Vector2(sin(a), cos(a)) * (rim + 2.4)
		if _off_road(k, p, 3.0):
			await _drift(d, p, k.rng.randf_range(2.0, 2.8), k.rng.randf_range(0.6, 1.0))

	# a headless chorister at each corner of the floor, on a plinth, its hands at its breast
	var figures := m.begin()
	var plinths := m.begin()
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var c := along * (PLAZA_HALF - 1.4) * float(cz) + across * (PLAZA_HALF - 1.4) * float(cx)
			if not _off_road(k, c, 0.5):
				continue
			var base := Vector3(c.x, floor_y, c.y)
			_box(plinths, Transform3D(basis, base + Vector3(0.0, 0.5, 0.0)), Vector3(1.6, 1.0, 1.6))
			k.collider(Vector3(1.6, 3.6, 1.6), Transform3D(basis, base + Vector3(0.0, 1.8, 0.0)), "stone")
			await k.step()
			_chorister(d, figures, base + Vector3(0.0, 1.0, 0.0), PoiKit.yaw_of(-c), 2.6, cx * cz > 0.0)
	await k.step()
	m.commit(plinths, k.surface("oroth", 0.7), "Plinths")
	m.commit(figures, k.surface("oroth", 0.85), "Choristers", true)

	# the fountain, off the tracks' line: a round basin, a column with the Order's count-bell on it
	var f := across * 5.6
	if not _off_road(k, f, 2.6):
		f = -across * 5.6
	var fountain := m.begin()
	var fx := Transform3D(Basis.IDENTITY, Vector3(f.x, floor_y, f.y))
	_lathe(fountain, fx, [Vector2(2.9, 0.0), Vector2(3.0, 0.55), Vector2(2.85, 0.8), Vector2(2.55, 0.82),
			Vector2(2.45, 0.35), Vector2(0.0, 0.3)], 28)
	_lathe(fountain, fx, [Vector2(0.55, 0.3), Vector2(0.42, 1.2), Vector2(0.38, 2.6), Vector2(0.62, 2.8),
			Vector2(0.62, 3.0), Vector2(0.0, 3.05)], 14)
	await k.step()
	m.commit(fountain, k.surface("oroth", 0.6), "Fountain", true)
	var ring := CylinderShape3D.new()
	ring.radius = 3.0
	ring.height = 0.85
	k.collider_shape(ring, Transform3D(Basis.IDENTITY, Vector3(f.x, floor_y + 0.42, f.y)), "stone")
	if not k.far:
		var count_bell := k.prop("bell_small")
		await k.step()
		k.place(count_bell, Vector3(f.x, floor_y + 3.05, f.y), k.rng.randf_range(0.0, TAU), 1.3, false)
		# the hand-bells, heaped in the dry basin
		var bells: Array = []
		for i in 70:
			var a := k.rng.randf_range(0.0, TAU)
			var r := sqrt(k.rng.randf()) * 2.2 + 0.4
			var y := floor_y + 0.32 + k.rng.randf_range(0.0, 0.35) * (1.0 - r / 2.8)
			bells.append(PoiKit.transform_at(Vector3(f.x + sin(a) * r, y, f.y + cos(a) * r), k.rng.randf_range(0.0, TAU),
					k.rng.randf_range(0.7, 1.0), Vector3(k.rng.randf_range(-1.6, 1.6), 0.0, k.rng.randf_range(-1.6, 1.6))))
		await k.step()
		k.scatter(count_bell, bells, false)
		k.marker("the_fountain", k.on_ground(f.x - across.x * 4.0, f.y - across.y * 4.0))
		k.touchable("the_count", Vector3(f.x, floor_y + 1.0, f.y) - Vector3(across.x, 0.0, across.y) * 3.2,
				"Count the bells in the fountain", "core:dialogue/sunk_plaza_count", "", false)
		# a pilgrim's stub of candle and a cup on the rim, where the counter sits
		var sit := f - across * 3.1 + along * 1.0
		await k.step()
		k.place(k.prop("candle_stub"), Vector3(sit.x, floor_y + 0.82, sit.y), 0.0, 1.0, false)
		await _rubble(d, Vector2.ZERO, rim + 1.0, 12)
		await _grey_grass(d, rim + 3.0, 36)


## A headless chorister of the Builders' stone, `h` tall from `base`, facing `yaw`: a robe like a
## bell, shoulders, the arms in the sleeves meeting at the breast (or one raised, `raised`), the neck
## broken off clean.
static func _chorister(d: PoiDressing, st: SurfaceTool, base: Vector3, yaw: float, h: float, raised := false) -> void:
	var m := d.masonry
	var xf := Transform3D(Basis(Vector3.UP, yaw), base)
	_lathe(st, xf, [Vector2(0.62 * h / 2.6, 0.0), Vector2(0.55 * h / 2.6, h * 0.3), Vector2(0.4 * h / 2.6, h * 0.62),
			Vector2(0.36 * h / 2.6, h * 0.78), Vector2(0.42 * h / 2.6, h * 0.86), Vector2(0.3 * h / 2.6, h * 0.94),
			Vector2(0.12 * h / 2.6, h * 0.97), Vector2(0.0, h * 0.97)], 14)
	var s := h / 2.6
	var sh_l := xf * Vector3(-0.38 * s, h * 0.86, 0.0)
	var sh_r := xf * Vector3(0.38 * s, h * 0.86, 0.0)
	var breast := xf * Vector3(0.0, h * 0.7, 0.28 * s)
	m.limb(st, sh_l, xf * Vector3(-0.3 * s, h * 0.66, 0.22 * s), 0.13 * s)
	m.limb(st, xf * Vector3(-0.3 * s, h * 0.66, 0.22 * s), breast, 0.12 * s)
	if raised:
		m.limb(st, sh_r, xf * Vector3(0.5 * s, h * 1.08, 0.1 * s), 0.13 * s)
		m.limb(st, xf * Vector3(0.5 * s, h * 1.08, 0.1 * s), xf * Vector3(0.42 * s, h * 1.32, 0.18 * s), 0.11 * s)
	else:
		m.limb(st, sh_r, xf * Vector3(0.3 * s, h * 0.66, 0.22 * s), 0.13 * s)
		m.limb(st, xf * Vector3(0.3 * s, h * 0.66, 0.22 * s), breast, 0.12 * s)
	# the stump of the neck, broken
	m.limb(st, xf * Vector3(0.0, h * 0.95, 0.0), xf * Vector3(0.02 * s, h * 1.0, 0.03 * s), 0.12 * s)


## A bank of ash round a square, `basis`'s, from its inner edge `half_in` out (local half-widths) at
## `top_y` down to the ground at `half_out`: the ground a sunk court was dug out of. Walkable, its
## edge ragged, one mesh.
static func _skirt(d: PoiDressing, basis: Basis, half_in: float, half_out: float, top_y: float) -> void:
	var k := d.kit
	var m := d.masonry
	var st := m.begin()
	var faces := PackedVector3Array()
	var n := 12
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	# three rings round the square: the rim, a lumpy shoulder, the heath
	var rings: Array = []
	for ring in 3:
		var row: Array = []
		for c in 4:
			var c0: Vector2 = corners[c]
			var c1: Vector2 = corners[(c + 1) % 4]
			for i in n:
				var q := c0.lerp(c1, float(i) / float(n))
				var a := atan2(q.y, q.x)
				var wob := 1.0 + 0.07 * sin(a * 5.0 + 1.3) + 0.05 * sin(a * 11.0 + 0.4)
				var p: Vector3
				if ring == 0:
					var inner := basis * Vector3(q.x * half_in, 0.0, q.y * half_in)
					p = Vector3(inner.x, top_y - 0.04, inner.z)
				elif ring == 1:
					var hw := lerpf(half_in, half_out, 0.45) * wob
					var mid := basis * Vector3(q.x * hw, 0.0, q.y * hw)
					var gy := k.on_ground(mid.x, mid.z).y
					p = Vector3(mid.x, lerpf(gy, top_y, 0.62 + 0.18 * sin(a * 7.0 + 2.0)), mid.z)
				else:
					var outer := basis * Vector3(q.x * half_out * wob, 0.0, q.y * half_out * wob)
					p = k.on_ground(outer.x, outer.z, -0.15)
				row.append(p)
		rings.append(row)
	var count: int = (rings[0] as Array).size()
	# a mesh a side, so each is only as big as its own bank
	var sides: Array = [st, m.begin(), m.begin(), m.begin()]
	for ring in 2:
		for i in count:
			var side_st: SurfaceTool = sides[floori(float(i) / float(n))]
			var i1 := (i + 1) % count
			var a: Vector3 = rings[ring][i]
			var b: Vector3 = rings[ring][i1]
			var ao: Vector3 = rings[ring + 1][i]
			var bo: Vector3 = rings[ring + 1][i1]
			var tris := [a, b, ao, b, bo, ao]
			if (b - a).cross(ao - a).y > 0.0:
				tris = [a, ao, b, b, ao, bo]
			for v in tris:
				side_st.add_vertex(v)
			faces.append_array(PackedVector3Array(tris))
	await k.step()
	for si in 4:
		m.commit(sides[si], _ground(k, Vector2.ZERO), "AshBank%d" % si, true)
	if not k.far:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		k.collider_shape(shape, Transform3D.IDENTITY, "dirt")


# --- the Anthem Hall ----------------------------------------------------------------------------------

## The Builders' choir-school, roofless: five tiers of stone benches in a half-round rising from a
## singer's stone, all still facing it, with the broken shell of the apse that threw the singer's
## voice out over them standing behind the stone. Ash lies in the benches' backs. A lecture given
## from the stone carries over the whole heath, and the choristers come at dusk to rehearse to the
## singer who is not there.
static func anthem_hall(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var line := _road_line(k)
	# the benches rise away from the road, the stone and its shell on the road's side
	var out := k.grain()
	if not line.is_empty():
		var q: Vector2 = line[0]
		out = -q.normalized() if q.length() > 0.5 else Vector2((line[1] as Vector2).y, -(line[1] as Vector2).x)
	if out == Vector2.ZERO:
		out = Vector2(0.0, 1.0)
	out = out.normalized()
	var side := Vector2(out.y, -out.x)
	# the singer's stone stands off the road, and everything else beyond it
	var focus := out * 2.0
	while not _off_road(k, focus, 4.5) and focus.length() < 14.0:
		focus += out * 1.0
	var g := k.on_ground(focus.x, focus.y).y
	var stone := m.begin()
	# the benches: five tiers in a half-round, each a step higher, broken here and there
	var tiers := 5
	# two aisles up through the tiers, and the back of the top tiers fallen in two places
	var aisles := [-0.42, 0.38]
	var falls := [k.rng.randf_range(-1.2, -0.7), k.rng.randf_range(0.6, 1.15)]
	for t in tiers:
		var r := 5.6 + float(t) * 1.35
		var top := g + 0.42 * float(t + 1)
		var segs := int(PI * 0.92 * r / 1.9)
		for i in segs:
			var a := lerpf(-PI * 0.46, PI * 0.46, (float(i) + 0.5) / float(segs))
			var gap := false
			for ai: float in aisles:
				gap = gap or absf(a - ai) * r < 0.9
			for fa: float in falls:
				gap = gap or (t >= 3 and absf(a - fa) * r < 1.4 + 0.6 * float(t - 3))
			if gap or k.rng.randf() < 0.06:
				continue                    # an aisle, or a seat gone, fallen into the tier below
			var dir := out.rotated(-a)
			var p := focus + dir * r
			if not _off_road(k, p, 0.4):
				continue
			var pg := k.on_ground(p.x, p.y).y
			var tall := top - (pg - 0.3)
			var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(dir)), Vector3(p.x, (top + pg - 0.3) * 0.5, p.y))
			_box(stone, xf, Vector3(PI * 0.92 * r / float(segs) * 1.02, tall, 1.3))
			k.collider(Vector3(PI * 0.92 * r / float(segs) * 1.02, tall, 1.3), xf, "stone")
		await k.step()
	# the singer's stone, round, two steps up, and the lectern on it
	var podium := Transform3D(Basis.IDENTITY, Vector3(focus.x, g, focus.y))
	_lathe(stone, podium, [Vector2(1.9, -0.3), Vector2(1.9, 0.3), Vector2(1.45, 0.3), Vector2(1.45, 0.6), Vector2(0.0, 0.6)], 22)
	var disc := CylinderShape3D.new()
	disc.radius = 1.9
	disc.height = 0.9
	k.collider_shape(disc, Transform3D(Basis.IDENTITY, Vector3(focus.x, g + 0.15, focus.y)), "stone")
	var lect := focus - out * 0.6
	_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(out)) * Basis(Vector3.RIGHT, -0.35), Vector3(lect.x, g + 1.55, lect.y)), Vector3(0.9, 0.08, 0.6))
	_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(out)), Vector3(lect.x, g + 1.05, lect.y)), Vector3(0.3, 0.95, 0.3))
	await k.step()
	m.commit(stone, k.surface("oroth", 0.6), "Benches", true)
	# the shell: a half-round of wall behind the stone, tall at its middle, torn down at its ends, ribbed
	var shell := m.begin()
	var sr := 4.2
	var n := 22
	var tops: Array = []
	for i in n + 1:
		var u := float(i) / float(n)
		var tall := lerpf(1.6, 7.8, pow(sin(u * PI), 1.4)) * (1.0 - 0.18 * absf(sin(u * 23.0 + 1.7)))
		tops.append(tall)
	for i in n:
		var a0 := lerpf(PI * 0.5, PI * 1.5, float(i) / float(n))
		var a1 := lerpf(PI * 0.5, PI * 1.5, float(i + 1) / float(n))
		var d0 := out.rotated(-a0)
		var d1 := out.rotated(-a1)
		var p0 := focus + d0 * sr
		var p1 := focus + d1 * sr
		if not _off_road(k, (p0 + p1) * 0.5, 0.2):
			continue
		var thick := 0.8
		var hb := (float(tops[i]) + float(tops[i + 1])) * 0.5
		var cm := (p0 + p1) * 0.5
		var cd := (d0 + d1).normalized()
		var cg := k.on_ground(cm.x, cm.y).y - 0.3
		_box(shell, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(cd)), Vector3(cm.x - cd.x * thick * 0.5, (cg + g + hb) * 0.5, cm.y - cd.y * thick * 0.5)),
				Vector3(p0.distance_to(p1) + 0.12, g + hb - cg, thick))
		var mid := (p0 + p1) * 0.5
		var md := (d0 + d1).normalized()
		var hgt := (float(tops[i]) + float(tops[i + 1])) * 0.5
		k.collider(Vector3(p0.distance_to(p1) + 0.1, hgt + 0.3, thick), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(md)),
				Vector3(mid.x - md.x * thick * 0.5, g + hgt * 0.5 - 0.15, mid.y - md.y * thick * 0.5)), "stone")
		# a rib on its inside every third bay, where the singer's voice was thrown back
		if i % 3 == 1:
			var rib := focus + md * (sr - thick - 0.12)
			_box(shell, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(md)), Vector3(rib.x, g + hgt * 0.45, rib.y)), Vector3(0.35, hgt * 0.9, 0.3))
	await k.step()
	m.commit(shell, k.surface("oroth", 0.75), "Shell", true)
	if k.far:
		return
	# ash in the benches' backs, and the slates the novices wrote their parts on
	for i in 5:
		var a := k.rng.randf_range(-1.2, 1.2)
		var p := focus + out.rotated(-a) * k.rng.randf_range(7.0, 11.0)
		if _off_road(k, p, 1.0):
			await _drift(d, p, k.rng.randf_range(1.2, 2.0), 0.5, false)
	k.marker("the_benches", k.on_ground(focus.x + out.x * 8.0, focus.y + out.y * 8.0, 2.1), false, true, 6.0)
	k.marker("the_stone", k.on_ground(focus.x + out.x * 2.6, focus.y + out.y * 2.6))
	k.touchable("the_singers_stone", Vector3(focus.x, g + 1.4, focus.y), "Stand on the singer's stone and sing",
			"core:dialogue/anthem_hall_sing", "", false)
	await _cache(d, k.on_ground(focus.x + side.x * 9.5 + out.x * 3.0, focus.y + side.y * 9.5 + out.y * 3.0), PoiKit.yaw_of(-side),
			"chest", "core:loot/oroth_cache", "precentors_chest")
	await _rubble(d, focus + out * 7.0, 14.0, 14)
	await _grey_grass(d, 18.0, 34, focus + out * 5.0)


# --- the Cistern of Isse ------------------------------------------------------------------------------

## The cistern's stair-house: a square plinth of the Builders' stone with steps up its road side
## and a broken colonnade round its top, and in its middle the well: a stair going down its inside
## wall into the dark, which is the way down to the dry cistern under the Ashgrid (the def's
## `site.interior`). A bucket on a rope, wet to the knot; a pilgrim's offering of water in a jar at
## the stair head. At night the wights come up the stair out of the dry dark, wet to the knee.
static func cistern_of_isse(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lie := _lie(k)
	var along: Vector2 = lie[1]
	var across := Vector2(-along.y, along.x)
	# the stair-house stands to the side of the road the place is on
	var c := across * 11.0
	if not _off_road(k, c, 7.0):
		c = -across * 11.0
	var to_road := (-c).normalized()
	var face := to_road
	var side := Vector2(face.y, -face.x)
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(face))
	var g := k.on_ground(c.x, c.y).y
	var hgt := 1.8
	var half := 5.0
	var well := Vector2(1.6, 2.4)          # the well's half-widths across and along the face
	var stone := m.begin()
	var top := g + hgt
	# the plinth, four blocks round the well
	var parts := [[Vector2(0.0, (half + well.y) * 0.5), Vector2(half * 2.0, half - well.y)],
			[Vector2(0.0, -(half + well.y) * 0.5), Vector2(half * 2.0, half - well.y)],
			[Vector2((half + well.x) * 0.5, 0.0), Vector2(half - well.x, well.y * 2.0)],
			[Vector2(-(half + well.x) * 0.5, 0.0), Vector2(half - well.x, well.y * 2.0)]]
	for p in parts:
		var off: Vector2 = p[0]
		var size: Vector2 = p[1]
		var at := c + side * off.x + face * off.y
		var xf := Transform3D(basis, Vector3(at.x, (top + g - 0.5) * 0.5, at.y))
		_box(stone, xf, Vector3(size.x, top - g + 0.5, size.y))
		k.collider(Vector3(size.x, top - g + 0.5, size.y), xf, "stone")
	# the steps up the road side, and the parapet's broken columns round the top
	await k.step()
	m.steps(stone, c + face * (half + 0.3 + 0.55 * 6.0), -face, g - 0.02, 6, hgt / 6.0, 0.55, 3.6)
	for i in 8:
		var a := TAU * float(i) / 8.0 + PI / 8.0
		var p := c + Vector2(sin(a), cos(a)) * (half - 0.6) * Vector2(1.0, 1.0)
		if absf((p - c).dot(face)) > half - 1.0 and (p - c).dot(face) > 0.0 and absf((p - c).dot(side)) < 2.2:
			continue                # leave the stair head open
		var colh := k.rng.randf_range(1.0, 3.6) if i % 3 != 0 else 4.6
		await k.step()
		m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(p.x, top, p.y)), 0.42, colh, 0.25, NAN, true, 0.5)
	await k.step()
	m.commit(stone, k.surface("oroth", 0.6), "StairHouse", true)
	# the well: its stair down the inside wall, and the dark under it
	var dark := m.begin()
	_box(dark, Transform3D(basis, Vector3(c.x, g + 0.02, c.y)), Vector3(well.x * 2.0, 0.04, well.y * 2.0))
	await k.step()
	m.commit(dark, PoiKit.plain(HOLE, 1.0), "WellDark")
	var stair := m.begin()
	var steps := 7
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var at := c + side * (well.x - 0.65) + face * lerpf(well.y - 0.3, -well.y + 0.6, t)
		var y := lerpf(top - 0.22, g + 0.1, t)
		var xf := Transform3D(basis, Vector3(at.x, (y + g - 0.3) * 0.5, at.y))
		_box(stair, xf, Vector3(1.2, y - g + 0.3, (well.y * 2.0 - 0.9) / float(steps) * 1.02))
		k.collider(Vector3(1.2, y - g + 0.3, (well.y * 2.0 - 0.9) / float(steps) * 1.02), xf, "stone")
	await k.step()
	m.commit(stair, k.surface("oroth", 0.8), "WellStair")
	if k.far:
		return
	var site: Dictionary = ContentDB.get_or_empty(d.poi_id).get("site", {})
	var interior := str(site.get("interior", ""))
	var foot := c + side * (well.x - 0.65) - face * (well.y - 0.5)
	if interior != "" and ContentDB.has(interior):
		PoiDressing.kind_builders().SITES._door(d, interior, Vector3(foot.x, g + 0.1, foot.y), PoiKit.yaw_of(-face))
	# the jar of water at the head of the stair, and the bucket beside it, wet to the rim
	var jar := c + face * (well.y + 0.6) + side * 1.2
	await k.step()
	k.place(k.prop("jar"), Vector3(jar.x, top, jar.y), 0.0, 1.0, false)
	await k.step()
	k.place(k.prop("bucket"), Vector3(jar.x, top, jar.y) + Vector3(side.x, 0.0, side.y) * 0.8, 0.4, 1.0, false)
	k.marker("the_stair_head", Vector3(jar.x, top, jar.y), false, true, 4.0)
	k.marker("the_well_foot", Vector3(foot.x, g + 0.1, foot.y))
	k.touchable("the_well", Vector3(c.x, top + 0.6, c.y) + Vector3(face.x, 0.0, face.y) * (well.y + 0.3),
			"Listen down the stair", "core:dialogue/cistern_of_isse_listen", "", false)
	await _drift(d, c - face * (half + 2.0) + side * 2.0, 3.0, 1.2)
	await _rubble(d, c, 12.0, 14)
	await _grey_grass(d, 16.0, 30, c)


# --- the Weighhouse -----------------------------------------------------------------------------------

## The dead city's weighhouse: a roofless hall of the Builders' stone beside the road, its great
## doorway onto a yard, and in the yard the scales the city's bronze was weighed on, fused solid by
## the Ash Winter: a pillar three times a man's height, the beam across it tipped, one pan down on
## the paving and the other up in the air on its chains. The weights stand stacked by the low pan.
## The rumour has it the other pan was down last year.
static func weighhouse(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lie := _lie(k)
	var along: Vector2 = lie[1]
	var across := Vector2(-along.y, along.x)
	var yard := across * 7.0
	if not _off_road(k, yard, 4.5):
		yard = -across * 7.0
	var out := yard.normalized()             # from the road into the yard and on to the hall
	var side := Vector2(out.y, -out.x)
	var g := k.on_ground(yard.x, yard.y).y
	var stone := m.begin()
	# the yard's paving, and the scales' pillar on a stepped base in its middle
	_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(out)), Vector3(yard.x, g - 0.15, yard.y)), Vector3(12.0, 0.4, 8.0))
	_lathe(stone, Transform3D(Basis.IDENTITY, Vector3(yard.x, g, yard.y)), [Vector2(1.6, 0.0), Vector2(1.6, 0.4),
			Vector2(1.1, 0.4), Vector2(1.1, 0.8), Vector2(0.62, 0.8), Vector2(0.5, 5.6), Vector2(0.75, 5.8),
			Vector2(0.75, 6.2), Vector2(0.0, 6.3)], 16)
	k.collider(Vector3(1.2, 6.2, 1.2), Transform3D(Basis.IDENTITY, Vector3(yard.x, g + 3.1, yard.y)), "stone")
	# the hall behind the yard: three walls and a great doorway, roofless
	var hall := yard + out * 9.0
	var hw := 6.0
	var hl := 4.8
	var corners := [hall - side * hw - out * hl, hall + side * hw - out * hl, hall + side * hw + out * hl, hall - side * hw + out * hl]
	await k.step()
	# the front, with the doorway: two lengths either side of it, and the lintel
	_wall(d, stone, corners[0], corners[0] + side * (hw - 1.7), 5.4, 0.15)
	_wall(d, stone, corners[1] - side * (hw - 1.7), corners[1], 4.2, 0.4)
	_arch(d, stone, hall - out * hl, out, 3.0, 3.4, 0.6, 0.6, 0.7, 9)
	await k.step()
	_wall(d, stone, corners[1], corners[2], 3.6, 0.6)
	_wall(d, stone, corners[2], corners[3], 6.0, 0.3)
	_wall(d, stone, corners[3], corners[0], 2.4, 0.7)
	await k.step()
	m.commit(stone, k.surface("oroth", 0.65), "Weighhouse", true)
	# the beam, tipped, and the two pans on their chains
	var bronze := m.begin()
	var pivot := Vector3(yard.x, g + 6.0, yard.y)
	var tilt := 0.32
	var arm := 4.4
	var dir3 := Vector3(side.x, 0.0, side.y)
	var low_end := pivot + dir3 * cos(tilt) * arm - Vector3(0.0, sin(tilt) * arm, 0.0)
	var high_end := pivot - dir3 * cos(tilt) * arm + Vector3(0.0, sin(tilt) * arm, 0.0)
	m.limb(bronze, high_end, low_end, 0.2)
	m.limb(bronze, pivot - Vector3(out.x, 0.0, out.y) * 0.5, pivot + Vector3(out.x, 0.0, out.y) * 0.5, 0.16)
	var low_pan := Vector3(low_end.x, g + 0.05, low_end.z)
	var high_pan := Vector3(high_end.x, high_end.y - 2.6, high_end.z)
	for pan in [low_pan, high_pan]:
		var p: Vector3 = pan
		_lathe(bronze, Transform3D(Basis.IDENTITY, p), [Vector2(0.0, 0.0), Vector2(1.2, 0.08), Vector2(1.65, 0.45), Vector2(1.55, 0.48),
				Vector2(1.1, 0.16), Vector2(0.0, 0.1)], 22)
		var end: Vector3 = low_end if p == low_pan else high_end
		for i in 3:
			var a := TAU * float(i) / 3.0
			m.limb(bronze, end, p + Vector3(sin(a) * 1.5, 0.45, cos(a) * 1.5), 0.035)
	await k.step()
	m.commit(bronze, _bronze(), "Scales", true)
	var pan_shape := CylinderShape3D.new()
	pan_shape.radius = 1.6
	pan_shape.height = 0.5
	k.collider_shape(pan_shape, Transform3D(Basis.IDENTITY, low_pan + Vector3(0.0, 0.25, 0.0)), "metal")
	k.collider_shape(pan_shape, Transform3D(Basis.IDENTITY, high_pan + Vector3(0.0, 0.25, 0.0)), "metal")
	if k.far:
		return
	# the weights: blocks of the Builders' stone, each cut with its mark, stacked by the low pan
	var weights := m.begin()
	for i in 7:
		var w := low_pan + dir3 * 2.4 + Vector3(out.x, 0.0, out.y) * (float(i % 3) - 1.0) * 0.9
		var sz := 0.5 + 0.12 * float(i % 4)
		var y := g + sz * 0.5 + (sz if i >= 4 else 0.0)
		_box(weights, Transform3D(Basis(Vector3.UP, k.rng.randf_range(-0.3, 0.3)), Vector3(w.x, y, w.z)), Vector3(sz, sz, sz))
	k.collider(Vector3(1.0, 1.2, 2.6), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(out)), low_pan + dir3 * 2.4 + Vector3(0.0, 0.6, 0.0)), "stone")
	await k.step()
	m.commit(weights, k.surface("oroth", 0.5), "Weights")
	k.touchable("the_pans", Vector3(yard.x, g + 1.2, yard.y) - Vector3(out.x, 0.0, out.y) * 1.6, "Look at the pans",
			"core:dialogue/weighhouse_pans", "", false)
	k.marker("the_yard", k.on_ground(yard.x - out.x * 3.0, yard.y - out.y * 3.0))
	k.marker("the_tally_desk", k.on_ground(hall.x + side.x * 4.0, hall.y + side.y * 4.0))
	# the Tallymen's desk, still in the hall's corner, and the strongbox under it
	var desk := hall + side * 3.8 + out * 1.6
	await k.step()
	k.place(k.prop("table_trestle"), k.on_ground(desk.x, desk.y), PoiKit.yaw_of(side))
	await _cache(d, k.on_ground(desk.x - out.x * 1.3, desk.y - out.y * 1.3), PoiKit.yaw_of(-out), "chest",
			"core:loot/oroth_cache", "tallymens_box")
	await _drift(d, hall + side * 5.0 - out * 3.0, 2.6, 1.0)
	await _drift(d, yard - side * 5.0, 2.0, 0.6)
	await _rubble(d, hall, 12.0, 16)
	await _grey_grass(d, 18.0, 30, yard)


# --- the Silent Market --------------------------------------------------------------------------------

## The dead city's market square: two rows of stalls in fused stone round the square, their counters
## and awnings the Builders' stone, and on every counter the goods left on it in the Ash Winter,
## gone to ash the shape of what they were: loaves, fish, jars, a bolt of cloth. A market cross in
## the middle with a handbell on it. At the edge of the square one stall has fresh goods on it every
## morning: bread, a knife, a child's shoe.
static func silent_market(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var axis := k.grain()
	if axis == Vector2.ZERO:
		axis = Vector2(1.0, 0.0)
	axis = axis.normalized()
	var side := Vector2(axis.y, -axis.x)
	var stone := m.begin()
	var goods := m.begin()
	var stalls: Array = []
	# eight stalls facing in across the square, four a side, and the odd one at the end
	for s in [-1.0, 1.0]:
		for i in 4:
			stalls.append([axis * (-7.5 + 5.0 * float(i)) + side * 8.0 * float(s), -side * float(s)])
	stalls.append([axis * 13.0 + side * 2.0, -axis])
	var fresh := stalls.size() - 1
	for i in stalls.size():
		var at: Vector2 = stalls[i][0]
		var face: Vector2 = stalls[i][1]
		var b := Basis(Vector3.UP, PoiKit.yaw_of(face))
		var g := k.on_ground(at.x, at.y).y
		var broken := k.rng.randf() < 0.3 and i != fresh
		# the counter: a slab on two piers
		_box(stone, Transform3D(b, Vector3(at.x, g + 0.45, at.y)), Vector3(3.2, 0.9, 1.0))
		k.collider(Vector3(3.2, 0.9, 1.0), Transform3D(b, Vector3(at.x, g + 0.45, at.y)), "stone")
		_box(stone, Transform3D(b, Vector3(at.x, g + 0.96, at.y)), Vector3(3.5, 0.12, 1.25))
		# the back posts and the awning slab, leaning where one post went
		var back := at - face * 1.3
		var awning_h := 2.6
		for sx in [-1.0, 1.0]:
			if broken and sx > 0.0:
				continue
			var p := back + Vector2(face.y, -face.x) * 1.5 * float(sx)
			_box(stone, Transform3D(b, k.on_ground(p.x, p.y, awning_h * 0.5)), Vector3(0.3, awning_h, 0.3))
			k.collider(Vector3(0.3, awning_h, 0.3), Transform3D(b, k.on_ground(p.x, p.y, awning_h * 0.5)), "stone")
		var awn := Vector3(at.x, g + awning_h + 0.1, at.y) - Vector3(face.x, 0.0, face.y) * 0.6
		var tip := Basis(Vector3.RIGHT, 0.18) if not broken else Basis(Vector3.RIGHT, 0.18) * Basis(Vector3.BACK, 0.35)
		var awn_y := awn - (Vector3(0.0, 0.7, 0.0) if broken else Vector3.ZERO)
		_box(stone, Transform3D(b * tip, awn_y), Vector3(3.6, 0.14, 2.0))
		# the goods, ash in their shapes, on the counter
		if i != fresh:
			for j in 5:
				var q := at + Vector2(face.y, -face.x) * k.rng.randf_range(-1.3, 1.3) + face * k.rng.randf_range(-0.25, 0.3)
				var kind := k.rng.randi() % 3
				var top := Vector3(q.x, g + 1.04, q.y)
				match kind:
					0:
						m.ellipsoid(goods, top + Vector3(0.0, 0.08, 0.0), Vector3(0.18, 0.1, 0.12), Basis(Vector3.UP, k.rng.randf() * TAU))
					1:
						m.ellipsoid(goods, top + Vector3(0.0, 0.05, 0.0), Vector3(0.32, 0.06, 0.09), Basis(Vector3.UP, k.rng.randf() * TAU))
					_:
						m.rod(goods, Transform3D(Basis.IDENTITY, top + Vector3(0.0, 0.14, 0.0)), 0.09, 0.28)
		await k.step()
	m.commit(stone, k.surface("oroth", 0.6), "Stalls", true)
	await k.step()
	m.commit(goods, PoiKit.plain(Color(0.52, 0.5, 0.47), 0.98), "AshGoods")
	# the market cross, and its bell
	var cross := m.begin()
	var cg := k.on_ground(0.0, 0.0).y
	_lathe(cross, Transform3D(Basis.IDENTITY, Vector3(0.0, cg, 0.0)), [Vector2(1.5, 0.0), Vector2(1.5, 0.35),
			Vector2(1.0, 0.35), Vector2(1.0, 0.7), Vector2(0.38, 0.7), Vector2(0.3, 4.2), Vector2(0.5, 4.35), Vector2(0.0, 4.4)], 14)
	_box(cross, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(axis)), Vector3(0.0, cg + 3.7, 0.0)), Vector3(1.8, 0.2, 0.2))
	await k.step()
	m.commit(cross, k.surface("oroth", 0.55), "MarketCross", true)
	k.collider(Vector3(0.8, 4.4, 0.8), Transform3D(Basis.IDENTITY, Vector3(0.0, cg + 2.2, 0.0)), "stone")
	var steps_ring := CylinderShape3D.new()
	steps_ring.radius = 1.5
	steps_ring.height = 0.7
	k.collider_shape(steps_ring, Transform3D(Basis.IDENTITY, Vector3(0.0, cg + 0.35, 0.0)), "stone")
	if k.far:
		return
	var hang := Vector3(axis.x, 0.0, axis.y) * 0.75 + Vector3(0.0, cg + 3.55, 0.0)
	await k.step()
	k.place(k.prop("bell_small"), hang - Vector3(0.0, 0.3, 0.0), 0.0, 1.0, false)
	# the stall with fresh goods on it: a loaf, a knife, a child's shoe, on a clean cloth
	var fs: Array = stalls[fresh]
	var fat: Vector2 = fs[0]
	var ff: Vector2 = fs[1]
	var fg := k.on_ground(fat.x, fat.y).y + 1.02
	var fside := Vector2(ff.y, -ff.x)
	await k.step()
	k.place(k.prop("cloth"), Vector3(fat.x, fg, fat.y), PoiKit.yaw_of(ff), 1.0, false)
	await k.step()
	k.place(k.prop("loaf"), Vector3(fat.x + fside.x * 0.7, fg + 0.02, fat.y + fside.y * 0.7), k.rng.randf_range(0.0, TAU), 1.0, false)
	await k.step()
	k.place(k.prop("boots"), Vector3(fat.x - fside.x * 0.8, fg + 0.02, fat.y - fside.y * 0.8), PoiKit.yaw_of(ff) + 0.4, 0.6, false)
	k.marker("the_fresh_stall", Vector3(fat.x, fg + 0.05, fat.y) + Vector3(ff.x, 0.0, ff.y) * 0.1)
	k.touchable("the_fresh_goods", Vector3(fat.x, fg + 0.3, fat.y) + Vector3(ff.x, 0.0, ff.y) * 0.8, "Look at the goods on the stall",
			"core:dialogue/silent_market_stall", "", false)
	k.marker("the_square", k.on_ground(axis.x * 4.0, axis.y * 4.0))
	await _cache(d, k.on_ground(-axis.x * 11.5 + side.x * 8.0, -axis.y * 11.5 + side.y * 8.0), PoiKit.yaw_of(axis), "chest",
			"core:loot/oroth_cache", "stallholders_box")
	for i in 5:
		var p := Vector2(k.rng.randf_range(-12.0, 12.0), k.rng.randf_range(-9.0, 9.0))
		await _drift(d, axis * p.x + side * p.y * 1.4, k.rng.randf_range(1.4, 2.6), k.rng.randf_range(0.4, 0.9), false)
	await _rubble(d, Vector2.ZERO, 16.0, 18)
	await _grey_grass(d, 20.0, 40)


# --- the North Gate -----------------------------------------------------------------------------------

## The dead city's north gate, alone on the heath: a great round arch of the Builders' stone on two
## piers, nine metres to its crown, the wall gone either side of it but for the ridge of rubble its
## line left in the ash, and the guards' niches in its piers. Through it, every night at the same
## hour, something passes: the ash in the gateway is trodden in a track that comes from nowhere and
## goes nowhere, and has no footprints in it.
static func north_gate(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var axis := k.grain()
	if axis == Vector2.ZERO:
		axis = Vector2(0.0, 1.0)
	axis = axis.normalized()
	var across := Vector2(axis.y, -axis.x)
	var stone := m.begin()
	var crown := _arch(d, stone, Vector2.ZERO, axis, 5.2, 5.6, 2.6, 3.4, 1.3, 13)
	# the cornice over the arch, and the stump of the gate-tower's floor above it, broken off
	var g := k.on_ground(0.0, 0.0).y
	var top_y := crown.y + 0.2
	_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(axis)), Vector3(0.0, top_y + 0.35, 0.0)), Vector3(5.2 + 2.6 * 2.0 + 0.8, 0.7, 3.8))
	for s in [-1.0, 1.0]:
		var p := across * (2.6 + 1.3) * float(s)
		var h := k.rng.randf_range(1.2, 2.8)
		_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(axis)), Vector3(p.x, top_y + 0.7 + h * 0.5, p.y)), Vector3(2.6, h, 3.4))
		# the guard's niche in the pier, on the outward face
		var niche := p + axis * 1.72
		_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(axis)), Vector3(niche.x, g + 3.6, niche.y)), Vector3(1.4, 0.2, 0.3))
	# the spandrels between the arch and the cornice, so it reads as a gate and not a hoop
	for s in [-1.0, 1.0]:
		var p := across * (2.6 + 0.9) * float(s)
		_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(axis)), Vector3(p.x, g + 5.6 + (top_y - g - 5.6) * 0.5, p.y)), Vector3(1.8, top_y - g - 5.6, 3.3))
	await k.step()
	m.commit(stone, k.surface("oroth", 0.6), "Gate", true)
	if k.far:
		return
	# where the wall ran: a ridge of its rubble going away either side
	for s in [-1.0, 1.0]:
		for i in 4:
			var p := across * (7.5 + float(i) * 3.4) * float(s) + axis * k.rng.randf_range(-0.6, 0.6)
			await _drift(d, p, k.rng.randf_range(2.0, 2.8), k.rng.randf_range(0.7, 1.3))
		await _rubble(d, across * 12.0 * float(s), 6.0, 10, Vector2(0.35, 0.8))
	# the trodden track through it: the ash scuffed in a band, and not a footprint in it
	var band := m.begin()
	for i in 14:
		var t := -14.0 + float(i) * 2.15
		var p := axis * t + across * sin(t * 0.21) * 0.3
		_box(band, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(axis) + k.rng.randf_range(-0.1, 0.1)), k.on_ground(p.x, p.y, 0.015)),
				Vector3(1.1 + k.rng.randf() * 0.4, 0.02, 2.3))
	await k.step()
	m.commit(band, PoiKit.plain(Color(0.16, 0.155, 0.15), 0.98), "TrackInTheAsh")
	k.marker("the_gateway", k.on_ground(0.0, 0.0))
	k.marker("beyond_the_gate", k.on_ground(axis.x * 9.0, axis.y * 9.0))
	k.touchable("the_track", k.on_ground(axis.x * 3.0, axis.y * 3.0, 0.4), "Look at the track through the gate",
			"core:dialogue/north_gate_track", "", false)
	await _grey_grass(d, 22.0, 40)


# --- the Bell Pit -------------------------------------------------------------------------------------

## Where the dead city buried its broken bells: a hollow in the ash ringed by the spoil banked round
## it, and in the hollow the bells' rims and shoulders showing every way up, cracked ones, half
## ones, a tongue of bronze standing out of the ash like a fin. The bell-bearers come at night and
## dig. A scavenger's rope and sieve where somebody tried it by day.
static func bell_pit(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var r := 11.0
	# the bank round the hollow, with a gap where the diggers walk in
	var gap := k.road_direction(200.0)
	if gap == Vector2.ZERO:
		gap = k.downhill() if k.downhill() != Vector2.ZERO else Vector2(0.0, 1.0)
	gap = gap.normalized()
	for i in 14:
		var a := TAU * float(i) / 14.0
		var dir := Vector2(sin(a), cos(a))
		if dir.dot(gap) > 0.93:
			continue
		await _drift(d, dir * (r + 1.5), k.rng.randf_range(3.6, 4.4), k.rng.randf_range(1.6, 2.2))
	# the bells, rims and crowns, every way up, sunk deep
	var bronze := m.begin()
	var spots: Array = []
	for i in 9:
		var a := k.rng.randf_range(0.0, TAU)
		var rr := sqrt(k.rng.randf()) * (r - 3.0)
		var p := Vector2(sin(a), cos(a)) * rr
		var near := false
		for q: Vector2 in spots:
			if q.distance_to(p) < 3.6:
				near = true
		if near:
			continue
		spots.append(p)
		var mouth_r := k.rng.randf_range(0.9, 1.8)
		var h := mouth_r * 2.5
		var up := Vector3(k.rng.randf_range(-1.0, 1.0), k.rng.randf_range(-0.6, 1.0), k.rng.randf_range(-1.0, 1.0)).normalized()
		var g := k.on_ground(p.x, p.y)
		# sunk so that a third to a half of it shows
		var show := k.rng.randf_range(0.5, 0.75)
		var base := g - up * h * (1.0 - show)
		if up.y < 0.0:
			base = g - up * h * 0.2 - Vector3(0.0, h * (1.0 - show) * 0.6, 0.0)
		_bell(d, bronze, base, up, mouth_r, h, true)
		await k.step()
	# a tongue of bronze, a clapper as long as a man, standing out of the ash
	var fin := Vector2(2.0, 0.0)
	if not spots.is_empty():
		fin = (spots[0] as Vector2) + Vector2(1.6, 0.4)
	var fg := k.on_ground(fin.x, fin.y)
	m.limb(bronze, fg - Vector3(0.0, 0.5, 0.0), fg + Vector3(0.3, 1.9, 0.2), 0.16)
	m.ellipsoid(bronze, fg + Vector3(0.35, 2.05, 0.23), Vector3(0.32, 0.38, 0.32))
	k.collider(Vector3(0.5, 2.4, 0.5), Transform3D(Basis.IDENTITY, fg + Vector3(0.15, 1.0, 0.1)), "metal")
	await k.step()
	m.commit(bronze, _bronze(), "BuriedBells", true)
	if k.far:
		return
	# shards of bronze in the ash
	var shards := m.begin()
	for i in 18:
		var p := k.jitter(r - 1.0)
		_box(shards, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.6, 0.6)),
				k.on_ground(p.x, p.y, 0.05)), Vector3(k.rng.randf_range(0.3, 0.9), 0.06, k.rng.randf_range(0.2, 0.5)))
	await k.step()
	m.commit(shards, _bronze(), "Shards")
	# the scavengers' try at it: a rope from a stake, a sieve, a spade-cut
	var dig := gap * (r - 3.5)
	var timber := m.begin()
	m.post(timber, dig + Vector2(gap.y, -gap.x) * 1.5, 1.1, 0.1)
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "Stake")
	await k.step()
	k.place(k.prop("rope_coil"), k.on_ground(dig.x, dig.y), k.rng.randf_range(0.0, TAU), 1.0, false)
	await k.step()
	k.place(k.prop("basket"), k.on_ground(dig.x - gap.y * 1.2, dig.y + gap.x * 1.2), 0.3)
	await _cache(d, k.on_ground(-gap.x * 4.0, -gap.y * 4.0, 0.0), PoiKit.yaw_of(gap), "crate", "core:loot/oroth_cache", "diggers_crate")
	k.marker("the_pit", k.on_ground(0.0, 0.0))
	k.marker("the_diggers", k.on_ground(dig.x, dig.y))
	await _grey_grass(d, 20.0, 30)


# --- the Hermit's Gate --------------------------------------------------------------------------------

## A Builders' gatehouse on the heath with no city round it now: two square towers' stumps and the
## vaulted way between them, and in the way, against one wall, Garrow Lune's cell (a screen of
## wattle, his bed, his shelf, his candle, his names written up the wall), and across its inner end
## the door: one slab of the Builders' stone filling the arch, with no hinges and no handle. He
## says he opened it once.
static func hermits_gate(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var axis := k.road_direction(250.0)
	if axis == Vector2.ZERO:
		axis = k.grain()
	if axis == Vector2.ZERO:
		axis = Vector2(0.0, 1.0)
	axis = axis.normalized()          # the gate's way runs from the road side (out) inwards (-axis)
	var across := Vector2(axis.y, -axis.x)
	var b := Basis(Vector3.UP, PoiKit.yaw_of(axis))
	var g := k.on_ground(0.0, 0.0).y
	var stone := m.begin()
	var way := 3.4               # the vaulted way's width
	var deep := 8.0              # its length along the axis
	var tower := 4.2
	# the two towers' stumps either side of the way
	for s in [-1.0, 1.0]:
		var c := across * (way * 0.5 + tower * 0.5) * float(s)
		var h := 7.5 if s < 0.0 else 5.2
		await k.step()
		_wall(d, stone, c - across * tower * 0.5 + axis * deep * 0.5, c + across * tower * 0.5 + axis * deep * 0.5, h, 0.3)
		_wall(d, stone, c - across * tower * 0.5 - axis * deep * 0.5, c + across * tower * 0.5 - axis * deep * 0.5, h * 0.8, 0.5)
		var outer := c + across * tower * 0.5 * float(s)
		_wall(d, stone, outer + axis * deep * 0.5, outer - axis * deep * 0.5, h * 0.9, 0.35)
		var inner := c - across * tower * 0.5 * float(s)
		_wall(d, stone, inner + axis * deep * 0.5, inner - axis * deep * 0.5, 4.6, 0.0)
	# the vault over the way, and its outer arch
	var vault_y := g + 3.6
	for i in 6:
		var t := -deep * 0.5 + deep * (float(i) + 0.5) / 6.0
		var p := axis * t
		_box(stone, Transform3D(b, Vector3(p.x, vault_y + 0.7, p.y)), Vector3(way + 0.6, 0.5, deep / 6.0 * 1.02))
	_arch(d, stone, axis * (deep * 0.5 + 0.2), axis, way, 3.2, 0.7, 0.8, 0.7, 9)
	# the door across the inner end: one slab, no hinges, shut
	var door_at := -axis * (deep * 0.5 - 0.3)
	var door_xf := Transform3D(b, Vector3(door_at.x, g + 2.1, door_at.y))
	_box(stone, door_xf, Vector3(way + 0.1, 4.2, 0.45))
	k.collider(Vector3(way + 0.1, 4.2, 0.45), door_xf, "stone")
	# the door's face: a ring cut in it, the Builders' sign, and the hermit's chalk tries round it
	var marks := m.begin()
	var face := door_at + axis * 0.24
	for i in 20:
		var a := TAU * float(i) / 20.0
		_box(marks, Transform3D(b * Basis(Vector3.BACK, a), Vector3(face.x, g + 2.4, face.y) + b * Vector3(cos(a) * 0.9, sin(a) * 0.9, 0.0)),
				Vector3(0.3, 0.05, 0.02))
	for i in 34:
		var p := b * Vector3(k.rng.randf_range(-1.5, 1.5), k.rng.randf_range(0.5, 3.8), 0.0)
		_box(marks, Transform3D(b * Basis(Vector3.BACK, k.rng.randf_range(-0.2, 0.2)), Vector3(face.x, g, face.y) + p + Vector3(axis.x, 0.0, axis.y) * 0.01),
				Vector3(k.rng.randf_range(0.2, 0.5), 0.035, 0.012))
	await k.step()
	_commit_parts(d, [[stone, k.surface("oroth", 0.6)], [marks, PoiKit.plain(Color(0.82, 0.8, 0.74), 0.95)]], "Gatehouse", true)
	if k.far:
		return
	# his cell, against the way's left wall: a wattle screen, bed, shelf, candle, his pot
	var cell := -across * (way * 0.5 - 0.7) - axis * 1.0
	# a screen of ash-poles and sacking between his bed and the way
	var screen := m.begin()
	var sc := cell + across * 1.2
	for i in 4:
		var q := sc + axis * (float(i) - 1.5) * 0.9
		_box(screen, Transform3D(Basis.IDENTITY, k.on_ground(q.x, q.y, 0.85)), Vector3(0.07, 1.7, 0.07))
	_box(screen, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(axis)), k.on_ground(sc.x, sc.y, 0.95)), Vector3(0.04, 1.3, 2.9))
	k.collider(Vector3(0.1, 1.7, 2.9), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(axis)), k.on_ground(sc.x, sc.y, 0.85)), "wood")
	await k.step()
	m.commit(screen, PoiKit.painted(6, {"base": "#6a6358", "accent": "#524c43", "grout": "#36322c", "unit": 0.3}, 0.9), "Screen")
	await k.step()
	k.place(k.prop("bedroll"), k.on_ground(cell.x, cell.y), PoiKit.yaw_of(axis))
	var shelf := cell - axis * 1.6
	await k.step()
	k.place(k.prop("shelf"), k.on_ground(shelf.x - across.x * 0.35, shelf.y - across.y * 0.35), PoiKit.yaw_of(across))
	await k.step()
	k.place(k.prop("candle"), k.on_ground(cell.x + axis.x * 1.4, cell.y + axis.y * 1.4), 0.0, 1.0, false)
	k.light(k.on_ground(cell.x + axis.x * 1.4, cell.y + axis.y * 1.4, 0.4), Color(1.0, 0.75, 0.45), 1.2, 6.0)
	await k.step()
	k.place(k.prop("cooking_pot"), k.on_ground(cell.x + axis.x * 2.2 + across.x * 0.6, cell.y + axis.y * 2.2 + across.y * 0.6), 0.0)
	k.marker("home", k.on_ground(cell.x, cell.y), true)
	k.marker("the_arch", k.on_ground(door_at.x + axis.x * 1.3, door_at.y + axis.y * 1.3), true)
	k.touchable("the_door", Vector3(face.x, g + 1.4, face.y) + Vector3(axis.x, 0.0, axis.y) * 0.4, "Put your hand to the door",
			"core:dialogue/hermits_gate_door", "", false)
	await _rubble(d, Vector2.ZERO, 14.0, 16)
	await _grey_grass(d, 18.0, 30)


# --- Hesk-Morn ----------------------------------------------------------------------------------------

## An Oroth door with no hinges standing upright on the cliff's edge, its frame and its slab, the slab
## swung a hand's breadth open on nothing, with the Hush beyond; three steps up to its sill. The ash
## before it holds footprints that go up the steps and through, and do not come back.
static func hesk_morn(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(400.0)
	if sea == Vector2.ZERO:
		sea = k.downhill()
	if sea == Vector2.ZERO:
		sea = Vector2(0.0, 1.0)
	sea = sea.normalized()
	var across := Vector2(sea.y, -sea.x)
	var b := Basis(Vector3.UP, PoiKit.yaw_of(sea))
	# the door stands at the lip: as far towards the sea as the ground stays up
	var at := Vector2.ZERO
	var g0 := k.on_ground(0.0, 0.0).y
	for i in 12:
		var q := sea * float(i + 1)
		if k.on_ground(q.x, q.y).y < g0 - 0.6 or k.is_water(q.x, q.y):
			break
		at = q
	if not _off_road(k, at, 1.0):
		at += across * 4.0
	var g := k.on_ground(at.x, at.y).y
	var stone := m.begin()
	# the sill's three steps up from the land side
	m.steps(stone, at - sea * 2.4, sea, g - 0.05, 3, 0.25, 0.6, 3.6)
	var sill := g + 0.75
	_box(stone, Transform3D(b, Vector3(at.x, sill - 0.4, at.y)), Vector3(4.4, 0.8, 1.4))
	k.collider(Vector3(4.4, 0.8, 1.4), Transform3D(b, Vector3(at.x, sill - 0.4, at.y)), "stone")
	# the frame: two jambs and a lintel, tall and plain, the Builders' proportion
	var jamb_h := 6.4
	for s in [-1.0, 1.0]:
		var p := at + across * 1.85 * float(s)
		var xf := Transform3D(b, Vector3(p.x, sill + jamb_h * 0.5, p.y))
		_box(stone, xf, Vector3(0.8, jamb_h, 1.1))
		k.collider(Vector3(0.8, jamb_h, 1.1), xf, "stone")
	_box(stone, Transform3D(b, Vector3(at.x, sill + jamb_h + 0.4, at.y)), Vector3(5.0, 0.8, 1.3))
	await k.step()
	m.commit(stone, k.surface("oroth", 0.55), "DoorFrame", true)
	# the slab: one stone, swung a hand open on its edge, no hinge on it anywhere
	var slab := m.begin()
	var swing := 0.32
	var edge := at + across * 1.4
	var sb := b * Basis(Vector3.UP, swing)
	var centre := Vector3(edge.x, sill + 2.95, edge.y) + sb * Vector3(-1.45, 0.0, 0.15)
	_box(slab, Transform3D(sb, centre), Vector3(2.9, 5.9, 0.35))
	k.collider(Vector3(2.9, 5.9, 0.35), Transform3D(sb, centre), "stone")
	await k.step()
	m.commit(slab, k.surface("oroth", 0.4), "DoorSlab", true)
	if k.far:
		return
	await _footprints(d, at - sea * 9.0 + across * 0.3, at - sea * 2.6, 1.0)
	k.marker("the_door", k.on_ground(at.x - sea.x * 3.5, at.y - sea.y * 3.5))
	# where the footprints end, on the sill, and what lies there face down
	k.marker("the_threshold", Vector3(at.x, sill + 0.02, at.y) - Vector3(sea.x, 0.0, sea.y) * 0.45, false, true, 1.5)
	k.touchable("the_slab", Vector3(at.x, sill + 1.4, at.y) - Vector3(sea.x, 0.0, sea.y) * 0.6, "Look through the door",
			"core:dialogue/hesk_morn_door", "", false)
	await _rubble(d, at - sea * 6.0, 8.0, 10)
	await _grey_grass(d, 14.0, 24, -sea * 6.0)


# --- Ashcombe -----------------------------------------------------------------------------------------

## A hamlet emptied in the Ash Winter, standing as it was left: four houses of the grey country
## along the West Walk, their doors shut, ash grey on their roofs, garden walls round plots of grey
## stalks, a well on the green with its bucket down, a dead ash over the last house -- and smoke
## going up from every chimney, though nobody has lit a fire in them for a hundred and seventy years.
## Put your hand on a chimney's stones and they are cold. After dark the wights sit at the hearths.
static func ashcombe(d: PoiDressing) -> void:
	var k := d.kit
	var LAND: GDScript = PoiDressing.kind_builders().LAND
	var lie := _lie(k)
	var mid: Vector2 = lie[0]
	var along: Vector2 = lie[1]
	var across := Vector2(-along.y, along.x)
	var fabric := FabricMesh.new()
	var houses := [[-11.0, 1.0, 7.5, 5.5], [1.0, 1.0, 8.5, 6.0], [-4.5, -1.0, 7.0, 5.5], [8.5, -1.0, 9.5, 6.0]]
	var doors: Array = []
	var chimneys: Array = []
	for h in houses:
		var w: float = h[2]
		var dep: float = h[3]
		var c: Vector2 = mid + along * float(h[0]) + across * float(h[1]) * (dep * 0.5 + 5.6)
		if not _off_road(k, c, dep * 0.5):
			continue
		var face := -across * float(h[1])
		var frame: Transform3D = LAND._frame(d, c, face, w, dep)
		await k.step()
		var made: Dictionary = await LAND._house(d, fabric, frame, w, dep, 1, {}, true)
		doors.append([c + face * (dep * 0.5 + 0.6), face])
		chimneys.append_array(made.get("chimneys", []))
		# the garden behind it: a low wall round a plot of grey stalks
		var back := c - face * (dep * 0.5 + 3.4)
		var gs := Vector2(face.y, -face.x)
		var plot := [back - gs * w * 0.5 + face * 2.2, back + gs * w * 0.5 + face * 2.2, back + gs * w * 0.5 - face * 2.6, back - gs * w * 0.5 - face * 2.6]
		for i in 3:
			LAND._dry_wall(d, fabric, plot[i + 1], plot[(i + 2) % 4] if i < 2 else plot[0], 0.9)
	await LAND._commit_fabric(d, fabric)
	if k.far:
		return
	# the stalks in the gardens: the last year's crop, grey
	await _grey_grass(d, 22.0, 60)
	# the green, the well with its bucket down, the dead ash over the far house
	var green := mid + along * 15.0 + across * 6.5
	if not _off_road(k, green, 2.0):
		green = mid - along * 17.0 - across * 6.5
	await k.step()
	k.place(k.prop("well"), k.on_ground(green.x, green.y), PoiKit.yaw_of(along))
	var tree_at := green + along * 5.0 + across * 2.5
	if _off_road(k, tree_at, 1.0):
		await k.step()
		k.place(k.tree("dead_ash_tree"), k.on_ground(tree_at.x, tree_at.y), k.rng.randf_range(0.0, TAU), 1.1)
	# a bench by the first door, and a pair of boots on the step, left for the morning
	if not doors.is_empty():
		var dd: Array = doors[0]
		var at: Vector2 = dd[0]
		var face: Vector2 = dd[1]
		await k.step()
		k.place(k.prop("bench"), k.on_ground(at.x + face.y * 2.0, at.y - face.x * 2.0), PoiKit.yaw_of(face) + PI * 0.5)
		await k.step()
		k.place(k.prop("boots"), k.on_ground(at.x - face.x * 0.3, at.y - face.y * 0.3), PoiKit.yaw_of(face), 1.0, false)
		k.touchable("the_chimney", k.on_ground(at.x, at.y, 1.3), "Put your hand to the chimney stones",
				"core:dialogue/ashcombe_chimney", "", false)
		await _cache(d, k.on_ground(at.x + face.y * 3.6, at.y - face.x * 3.6), PoiKit.yaw_of(face), "barrel",
				"core:loot/pilgrims_bundle", "hearth_barrel")
	for i in mini(doors.size(), 4):
		var dd: Array = doors[i]
		k.marker("hearth_%d" % i, k.on_ground((dd[0] as Vector2).x, (dd[0] as Vector2).y))
	k.marker("the_green", k.on_ground(green.x, green.y))


# --- the Ash-Winter Carts -----------------------------------------------------------------------------

## A carters' waystation on the old Ash Road, roofless since the Ash Winter: its long range down one
## side of a walled yard, a gate onto the road, and the yard full of the grain carts that came in
## from Greyfold's fields and were never unloaded, standing in their rows with their sacks gone
## grey and hard, a cart's shafts down where the horse was led away. The trough by the gate. The
## carter's day-book is still on its peg: it lists a delivery to Greyfold made after Greyfold had
## walked south.
static func ashwinter_carts(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var LAND: GDScript = PoiDressing.kind_builders().LAND
	var lie := _lie(k)
	var mid: Vector2 = lie[0]
	var along: Vector2 = lie[1]
	var across := Vector2(-along.y, along.x)
	var yard := mid + across * 10.0
	if not _off_road(k, yard, 6.5):
		yard = mid - across * 10.0
	var into := (yard - mid).normalized()
	var side := Vector2(into.y, -into.x)
	var half := Vector2(10.0, 6.8)       # along the road, and back from it
	var fabric := FabricMesh.new()
	var c := [yard - side * half.x - into * half.y, yard + side * half.x - into * half.y,
			yard + side * half.x + into * half.y, yard - side * half.x + into * half.y]
	# the yard wall, its gate on the road side
	var gate := yard - into * half.y
	LAND._dry_wall(d, fabric, c[0], gate - side * 2.2, 1.4)
	LAND._dry_wall(d, fabric, gate + side * 2.2, c[1], 1.4)
	LAND._dry_wall(d, fabric, c[1], c[2], 1.4)
	LAND._dry_wall(d, fabric, c[3], c[0], 1.4)
	await k.step()
	await LAND._commit_fabric(d, fabric)
	# the range across the back: a long roofless hall of the grey stone, doors onto the yard
	var stone := m.begin()
	var r0 := c[3] as Vector2
	var r1 := c[2] as Vector2
	var back := into * 4.2
	_wall(d, stone, r0, r0 + (r1 - r0) * 0.42, 3.4, 0.3)
	_wall(d, stone, r0 + (r1 - r0) * 0.52, r1, 3.0, 0.5)
	_wall(d, stone, r0 + back, r1 + back, 4.2, 0.4)
	_wall(d, stone, r0, r0 + back, 4.6, 0.2)
	_wall(d, stone, r1, r1 + back, 2.4, 0.6)
	await k.step()
	m.commit(stone, k.surface("stone", 0.7), "Range", true)
	if k.far:
		return
	# the carts in two rows, their beds heaped with sacks gone grey and hard
	var sacks := m.begin()
	var cart := k.prop("cart")
	for row in 2:
		for i in 3:
			var at := yard + side * (-6.0 + 6.0 * float(i)) + into * (-2.4 + 4.0 * float(row)) + k.jitter(0.3)
			var yaw := PoiKit.yaw_of(into) + k.rng.randf_range(-0.15, 0.15)
			if row == 1 and i == 2:
				yaw += 0.6           # the one whose horse was led off, shafts down
			await k.step()
			k.place(cart, k.on_ground(at.x, at.y), yaw)
			for j in 4:
				var q := at + Vector2(sin(yaw), cos(yaw)) * k.rng.randf_range(-0.8, 0.8) + Vector2(cos(yaw), -sin(yaw)) * k.rng.randf_range(-0.45, 0.45)
				m.ellipsoid(sacks, k.on_ground(q.x, q.y, 1.0 + 0.12 * float(j % 2)), Vector3(0.38, 0.24, 0.3), Basis(Vector3.UP, k.rng.randf() * TAU))
	await k.step()
	m.commit(sacks, PoiKit.plain(Color(0.45, 0.43, 0.4), 0.98), "GreySacks")
	# the trough by the gate, the carter's peg-board in the range's doorway
	var trough := gate + side * 3.4 + into * 1.4
	await k.step()
	k.place(k.prop("trough") if k.prop("trough") != "" else k.prop("crate"), k.on_ground(trough.x, trough.y), PoiKit.yaw_of(side))
	var book_at := r0 + (r1 - r0) * 0.47 + into * 0.6
	k.marker("the_day_book", k.on_ground(book_at.x, book_at.y, 0.0))
	k.touchable("the_book_peg", k.on_ground(book_at.x, book_at.y, 1.4), "Read the carter's day-book",
			"core:dialogue/ashwinter_carts_book", "", false)
	k.marker("the_cart_beds", k.on_ground(yard.x, yard.y))
	await _cache(d, k.on_ground(r1.x - side.x * 2.0 + into.x * 2.5, r1.y - side.y * 2.0 + into.y * 2.5), PoiKit.yaw_of(-into),
			"chest", "core:loot/pilgrims_bundle", "carters_chest")
	await _drift(d, yard + side * 8.0 + into * 5.0, 2.2, 0.8)
	await _grey_grass(d, 14.0, 40, yard)


# --- the Bell Garden ----------------------------------------------------------------------------------

## A Builders' garden on the rim: bells planted mouth-down in the ash in rows like cabbages, every
## one a different size and so a different note, small at one end and great at the other, with a
## gardener's path between the rows and a bronze rod hung on a post at its head for striking them.
## Struck in the right order, the garden plays a line, and the Cantor's Seat's door answers.
static func bell_garden(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lie := _lie(k)
	var along: Vector2 = lie[1]
	var across := Vector2(-along.y, along.x)

	# the garden lies off the road on the side the place is on
	var g0 := across * 9.0
	if not _off_road(k, g0, 6.0):
		g0 = -across * 9.0
	var away := g0.normalized()
	var rows := 5
	var per := 7
	var bronze := m.begin()
	for r in rows:
		for i in per:
			var t := float(i) / float(per - 1)
			var at := g0 + along * (-9.0 + 18.0 * t) + away * (-4.0 + 2.2 * float(r)) + k.jitter(0.15)
			if not _off_road(k, at, 0.6):
				continue
			var mouth_r := lerpf(0.32, 0.95, t) * k.rng.randf_range(0.9, 1.08)
			var h := mouth_r * 2.4
			var g := k.on_ground(at.x, at.y)
			# planted mouth-down a hand deep, a little askew, every one
			_bell(d, bronze, g - Vector3(0.0, 0.15, 0.0), Vector3(k.rng.randf_range(-0.06, 0.06), 1.0, k.rng.randf_range(-0.06, 0.06)),
					mouth_r, h, false)
		await k.step()
	m.commit(bronze, _bronze(), "BellRows", true)
	if k.far:
		return
	# the gardener's path and the striking-post at the head of the rows
	var head := g0 - along * 11.0
	var timber := m.begin()
	var top := m.post(timber, head, 1.8, 0.14)
	_box(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(along)), top - Vector3(0.0, 0.1, 0.0) + Vector3(along.x, 0.0, along.y) * 0.3), Vector3(0.1, 0.1, 0.7))
	await k.step()
	m.commit(timber, k.surface("timber", 0.7), "StrikingPost")
	var rod := m.begin()
	var hook := top + Vector3(along.x, 0.0, along.y) * 0.6
	m.limb(rod, hook - Vector3(0.0, 0.05, 0.0), hook - Vector3(0.0, 1.0, 0.0), 0.03)
	m.ellipsoid(rod, hook - Vector3(0.0, 1.05, 0.0), Vector3(0.07, 0.07, 0.07))
	await k.step()
	m.commit(rod, _bronze(), "StrikingRod")
	var path := m.begin()
	for i in 12:
		var p := head + along * (1.5 + float(i) * 1.6) + away * k.rng.randf_range(-0.2, 0.2)
		_box(path, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), k.on_ground(p.x, p.y, 0.03)), Vector3(0.7, 0.08, 0.55))
	await k.step()
	m.commit(path, k.surface("oroth", 0.5), "GardenPath")
	k.marker("the_rows", k.on_ground(g0.x, g0.y))
	k.marker("the_striking_post", k.on_ground(head.x - along.x * 1.2, head.y - along.y * 1.2))
	k.touchable("the_garden", hook - Vector3(0.0, 0.6, 0.0), "Strike the bells in their rows",
			"core:dialogue/bell_garden_strike", "", false)
	await _grey_grass(d, 16.0, 30, g0)


# --- the Row of Mouths --------------------------------------------------------------------------------

## A colonnade of the Builders' pillars along the road west from the Choir, two rows facing across
## it, each pillar carved near its top as an open mouth, black inside, the lips worn; some whole to
## their capitals, some broken at the mouth. At dusk one mouth is heard singing one note, a different
## pillar every night. The Order chalks a tally at the foot of the one that sang.
static func row_of_mouths(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lie := _lie(k)
	var mid: Vector2 = lie[0]
	var along: Vector2 = lie[1]
	var across := Vector2(-along.y, along.x)
	var stone := m.begin()
	var mouths := m.begin()
	var chalk := m.begin()
	var pillars := 8
	var singer := k.rng.randi_range(1, pillars - 2)
	for i in pillars:
		for s in [-1.0, 1.0]:
			var at: Vector2 = mid + along * (-17.5 + 5.0 * float(i)) + across * 4.6 * float(s)
			if not _off_road(k, at, 0.4):
				at += across * float(s) * 1.5
			var g := k.on_ground(at.x, at.y)
			var whole := (i + (1 if s > 0.0 else 0)) % 3 != 0
			var h := 6.6 if whole else k.rng.randf_range(2.4, 4.2)
			var face := -across * float(s)
			var b := Basis(Vector3.UP, PoiKit.yaw_of(face))
			# the base, the shaft, the capital where it stands whole
			_box(stone, Transform3D(b, g + Vector3(0.0, 0.3, 0.0)), Vector3(1.5, 0.6, 1.5))
			m.drum(stone, Transform3D(Basis.IDENTITY, g + Vector3(0.0, 0.6, 0.0)), 0.6, h - 0.6, 0.0 if whole else 0.4, NAN, true, 0.6)
			if whole:
				_box(stone, Transform3D(b, g + Vector3(0.0, h + 0.2, 0.0)), Vector3(1.6, 0.4, 1.6))
				# the mouth: lips standing out of the shaft, the dark of it inside
				var mo := g + Vector3(0.0, h - 1.3, 0.0) + Vector3(face.x, 0.0, face.y) * 0.55
				m.ellipsoid(stone, mo + Vector3(0.0, 0.38, 0.0), Vector3(0.45, 0.13, 0.16), b)
				m.ellipsoid(stone, mo - Vector3(0.0, 0.38, 0.0), Vector3(0.42, 0.14, 0.16), b)
				m.ellipsoid(mouths, mo + Vector3(face.x, 0.0, face.y) * 0.04, Vector3(0.36, 0.3, 0.06), b)
			if i == singer and s > 0.0:
				# the Order's chalk tally on a flag at the foot of the one that sang
				var flag := g + Vector3(face.x, 0.0, face.y) * 1.25
				_box(stone, Transform3D(b, flag + Vector3(0.0, 0.05, 0.0)), Vector3(1.0, 0.16, 0.7))
				k.collider(Vector3(1.0, 0.16, 0.7), Transform3D(b, flag + Vector3(0.0, 0.05, 0.0)), "stone")
				for j in 6:
					var q := flag + Vector3(0.0, 0.135, 0.0) + b * Vector3(-0.3 + 0.12 * float(j), 0.0, 0.0)
					_box(chalk, Transform3D(b * Basis(Vector3.UP, 0.5 if j == 5 else 0.0), q), Vector3(0.025, 0.012, 0.32))
				k.marker("the_singing_mouth", g + Vector3(face.x, 0.0, face.y) * 1.6)
				if not k.far:
					k.touchable("the_mouth", g + Vector3(0.0, 1.2, 0.0) + Vector3(face.x, 0.0, face.y) * 0.9, "Put your ear to the pillar",
							"core:dialogue/row_of_mouths_ear", "", false)
		await k.step()
	_commit_parts(d, [[stone, k.surface("oroth", 0.65)], [mouths, PoiKit.plain(Color(0.015, 0.014, 0.016), 1.0)],
			[chalk, PoiKit.plain(Color(0.86, 0.85, 0.8), 0.95)]], "Colonnade", true)
	if k.far:
		return
	# drums fallen out of the broken ones, lying where they rolled, off the road
	var drums := m.begin()
	for i in 6:
		var at: Vector2 = mid + along * k.rng.randf_range(-18.0, 18.0) + across * k.rng.randf_range(6.0, 9.0) * (1.0 if i % 2 == 0 else -1.0)
		var dir := Vector2(sin(k.rng.randf() * TAU), cos(k.rng.randf() * TAU)).normalized()
		var g := k.on_ground(at.x, at.y, 0.5)
		m.drum(drums, Transform3D(Basis(Vector3(dir.x, 0.0, dir.y).cross(Vector3.UP).normalized(), Vector3(dir.x, 0.0, dir.y), Vector3.UP), g - Vector3(dir.x, 0.0, dir.y) * 0.6), 0.58, 1.2, 0.0, NAN, false, 0.6)
		k.collider(Vector3(1.2, 1.1, 1.2), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(dir)), g), "stone")
	await k.step()
	m.commit(drums, k.surface("oroth", 0.7), "FallenDrums")
	k.marker("the_colonnade", k.on_ground(mid.x, mid.y))
	await _grey_grass(d, 22.0, 40)


# --- Hesk Pool ----------------------------------------------------------------------------------------

## The Builders' basin on the heath, square once: along the shore a broad flight of their steps going
## down into the still water, a coping along the top, two obelisks flanking the flight (one fallen
## across the steps), and the water at the foot of the steps black and still, giving back nothing,
## not the sky, not you. The Sayers say Hesk Pool and Eelfathom are the same water.
static func hesk_pool(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var water := k.water_direction(60.0)
	if water == Vector2.ZERO:
		water = -k.uphill() if k.uphill() != Vector2.ZERO else Vector2(0.0, 1.0)
	water = water.normalized()
	var across := Vector2(water.y, -water.x)
	var b := Basis(Vector3.UP, PoiKit.yaw_of(water))
	# the shore: walk towards the water until it is under foot
	var shore := Vector2.ZERO
	for i in 19:
		var q := water * float(i)
		if k.is_water(q.x, q.y):
			break
		shore = q
	var g := k.on_ground(shore.x, shore.y).y
	var stone := m.begin()
	var width := 16.0
	# the coping along the top, and the flight down into the water
	_box(stone, Transform3D(b, Vector3(shore.x, g + 0.25, shore.y) - Vector3(water.x, 0.0, water.y) * 1.2), Vector3(width + 4.0, 0.5, 1.4))
	k.collider(Vector3(width + 4.0, 0.5, 1.4), Transform3D(b, Vector3(shore.x, g + 0.25, shore.y) - Vector3(water.x, 0.0, water.y) * 1.2), "stone")
	m.steps(stone, shore - water * 0.5, water, g + 0.5, 7, -0.36, 0.65, width)
	# the side walls of the flight
	for s in [-1.0, 1.0]:
		var a := shore + across * (width * 0.5 + 0.5) * float(s) - water * 0.8
		var e := a + water * 6.8
		_box(stone, Transform3D(b, Vector3((a.x + e.x) * 0.5, g - 0.6, (a.y + e.y) * 0.5)), Vector3(1.0, 2.6, a.distance_to(e)))
		k.collider(Vector3(1.0, 2.6, a.distance_to(e)), Transform3D(b, Vector3((a.x + e.x) * 0.5, g - 0.6, (a.y + e.y) * 0.5)), "stone")
	# the obelisks at the head of the flight, one standing, one fallen across the steps
	var ob_at := shore + across * (width * 0.5 + 2.6) - water * 2.4
	_box(stone, Transform3D(b, Vector3(ob_at.x, g + 0.4, ob_at.y)), Vector3(1.8, 0.8, 1.8))
	var shaft := m.begin()
	_lathe(shaft, Transform3D(Basis.IDENTITY, Vector3(ob_at.x, g + 0.8, ob_at.y)), [Vector2(0.75, 0.0), Vector2(0.62, 6.6), Vector2(0.0, 7.4)], 4)
	k.collider(Vector3(1.4, 7.4, 1.4), Transform3D(b, Vector3(ob_at.x, g + 4.5, ob_at.y)), "stone")
	var fallen := shore - across * (width * 0.5 - 1.5) + water * 1.0
	var lying := Basis(Vector3.UP, PoiKit.yaw_of(across) + 0.35) * Basis(Vector3.RIGHT, PI * 0.5 - 0.1)
	_lathe(shaft, Transform3D(lying, k.on_ground(fallen.x, fallen.y, 0.2) - lying * Vector3(0.0, 3.4, 0.0)), [Vector2(0.72, 0.0), Vector2(0.62, 6.0), Vector2(0.0, 6.8)], 4)
	k.collider(Vector3(1.2, 1.2, 6.6), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(across) + 0.35), k.on_ground(fallen.x, fallen.y, 0.5)), "stone")
	await k.step()
	m.commit(stone, k.surface("oroth", 0.55), "BasinSteps", true)
	m.commit(shaft, k.surface("oroth", 0.4), "Obelisks", true)
	if k.far:
		return
	# the black water at the foot of the flight: no sky in it, no face
	var foot := shore + water * 5.0
	var wy := k.water_y(foot.x, foot.y)
	if not is_nan(wy) and wy > -1000.0:
		var black := m.begin()
		var dark_r := 4.0
		_lathe(black, Transform3D(Basis.IDENTITY, Vector3(foot.x, wy + 0.02, foot.y)), [Vector2(dark_r, 0.0), Vector2(0.0, 0.0)], 28, true)
		await k.step()
		m.commit(black, PoiKit.plain(Color(0.012, 0.012, 0.014), 0.05), "NoReflection")
	k.marker("the_steps", k.on_ground(shore.x - water.x * 2.5, shore.y - water.y * 2.5))
	k.touchable("the_black_water", Vector3(shore.x, g + 0.3, shore.y) + Vector3(water.x, 0.0, water.y) * 2.0, "Look into the water",
			"core:dialogue/hesk_pool_water", "", false)
	await _rubble(d, shore - water * 6.0, 10.0, 12)
	await _grey_grass(d, 16.0, 30, shore - water * 8.0)


# --- the Builders' Harbour ----------------------------------------------------------------------------

## The dead city's quay at the foot of its harbour road: a long wall of fused stone along the water,
## its top paved, a flight of steps going down the quay's face into the Grey Sea, and along the edge
## the mooring posts, which are bells: great bronze bells set mouth-down on stone drums, green to
## the waterline, a ring of iron through each crown. The harbour bells rang last night, the reedfolk
## say, and no ship has come in forty years.
static func builders_harbour(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(120.0)
	if sea == Vector2.ZERO:
		sea = k.downhill() if k.downhill() != Vector2.ZERO else Vector2(-1.0, 0.0)
	sea = sea.normalized()
	var along := Vector2(sea.y, -sea.x)
	var b := Basis(Vector3.UP, PoiKit.yaw_of(sea))
	# the quay's edge: as far towards the sea as the land stays dry, at most 18 m out
	var edge := Vector2.ZERO
	for i in 18:
		var q := sea * float(i)
		if k.is_water(q.x, q.y):
			break
		edge = q
	var g := k.on_ground(edge.x, edge.y).y
	var stone := m.begin()
	var length := 22.0
	# the quay top, a deck of paving along the edge, its face going down into the water
	var deck_c := edge - sea * 2.0
	var depth := 6.0
	var xf := Transform3D(b, Vector3(deck_c.x, g - 1.6, deck_c.y))
	_box(stone, xf, Vector3(length, 3.8, depth))
	k.collider(Vector3(length, 3.8, depth), xf, "stone")
	# the steps down its face into the sea, at one end
	var s_at := edge + along * (length * 0.5 - 3.0)
	m.steps(stone, s_at - sea * 0.2, sea, g + 0.3, 8, -0.38, 0.6, 2.4)
	# the bell-posts along the edge, and the iron rings through their crowns
	var bronze := m.begin()
	var iron := m.begin()
	for i in 5:
		var at := edge - sea * 0.9 + along * (-length * 0.5 + 3.0 + float(i) * (length - 6.0) / 4.0)
		var drum_h := 0.9
		m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(at.x, g + 0.25, at.y)), 0.75, drum_h, 0.0, NAN, true, 0.45)
		var mouth_r := 0.68
		var top := _bell(d, bronze, Vector3(at.x, g + 0.25 + drum_h, at.y), Vector3.UP, mouth_r, 1.7, false)
		for j in 10:
			var a0 := TAU * float(j) / 10.0
			var a1 := TAU * float(j + 1) / 10.0
			var rx := Vector3(along.x, 0.0, along.y)
			m.limb(iron, top + rx * cos(a0) * 0.22 + Vector3(0.0, sin(a0) * 0.22 + 0.2, 0.0), top + rx * cos(a1) * 0.22 + Vector3(0.0, sin(a1) * 0.22 + 0.2, 0.0), 0.035)
		await k.step()
	await k.step()
	m.commit(stone, k.surface("oroth", 0.6), "Quay", true)
	m.commit(bronze, _bronze(), "BellPosts", true)
	m.commit(iron, PoiKit.plain(Color(0.16, 0.12, 0.1), 0.6, 0.5), "Rings")
	if k.far:
		return
	# a hawser still made fast to one, frayed off short; the crane's stump; a harbour-master's box
	await k.step()
	k.place(k.prop("rope_coil"), k.on_ground(edge.x - sea.x * 2.4 + along.x * 2.0, edge.y - sea.y * 2.4 + along.y * 2.0, 0.0), 0.5, 1.2, false)
	var crane := edge - sea * 3.6 - along * (length * 0.5 - 2.0)
	var timber := m.begin()
	m.post(timber, crane, 3.2, 0.4, Vector3(0.1, 0.0, 0.05))
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "CraneStump")
	await _cache(d, k.on_ground(crane.x + along.x * 2.0 - sea.x * 1.5, crane.y + along.y * 2.0 - sea.y * 1.5), PoiKit.yaw_of(sea),
			"chest", "core:loot/oroth_cache", "harbour_box")
	k.marker("the_quay", Vector3(edge.x, g + 0.3, edge.y) - Vector3(sea.x, 0.0, sea.y) * 3.0, false, true, 8.0)
	k.touchable("the_bell_post", Vector3(edge.x, g + 1.4, edge.y) - Vector3(sea.x, 0.0, sea.y) * 1.6, "Look at the bell-posts",
			"core:dialogue/builders_harbour_bells", "", false)
	await _rubble(d, edge - sea * 8.0, 6.0, 12)


# --- the stones of the rim and the heath --------------------------------------------------------------

## Where the Choir stands from here, as a local direction.
static func _to_choir(k: PoiKit) -> Vector2:
	var v := Vector2(-210.0 - k.origin.x, 3240.0 - k.origin.z)
	return v.normalized() if v.length() > 1.0 else Vector2(0.0, 1.0)


## A slab of the place's stone standing in the ground at `at`, `h` out of it, its broad face to
## `face`, leaning by `lean` (radians, towards its face): one block, colliding, with packing stones
## at its foot. Into `st`.
static func _slab(d: PoiDressing, st: SurfaceTool, at: Vector2, face: Vector2, h: float, w: float, thick: float,
		lean := 0.0, sunk := 0.6) -> Transform3D:
	var k := d.kit
	var g := k.on_ground(at.x, at.y)
	var b := Basis(Vector3.UP, PoiKit.yaw_of(face)) * Basis(Vector3.RIGHT, lean)
	var xf := Transform3D(b, g + b * Vector3(0.0, (h - sunk) * 0.5, 0.0))
	_box(st, xf, Vector3(w, h + sunk, thick))
	# its shoulders, broken a little out of square
	_box(st, Transform3D(b, g + b * Vector3(w * 0.18, h - sunk * 0.5 + 0.12, 0.0)), Vector3(w * 0.6, 0.26, thick * 0.92))
	k.collider(Vector3(w, h + sunk, thick), xf, "stone")
	return xf


## Greywatch: three tall stones in a line on the rim with their backs to the Hush, a reading-stone
## before them like a lectern, and on the stones' faces, in the Order's chalk, the names of the ones
## who walked down, read aloud here at dusk; candle-stubs along the reading-stone's foot, kneeling
## mats worn into the ash. A name has been read here every night for a month that is on no roll.
static func greywatch(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(500.0)
	if sea == Vector2.ZERO:
		sea = Vector2(0.0, 1.0)
	sea = sea.normalized()
	var along := Vector2(sea.y, -sea.x)
	var back := sea * 4.0
	if not _off_road(k, back, 1.5):
		back += along * 5.0
	var stone := m.begin()
	var faces: Array = []
	for i in 3:
		var at := back + along * (float(i) - 1.0) * 3.4
		var h := [4.6, 5.8, 4.2][i] as float
		var xf := _slab(d, stone, at, -sea, h, 1.5, 0.7, k.rng.randf_range(-0.04, 0.04))
		faces.append([xf, h])
	var lect := back - sea * 4.2
	_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(sea)), k.on_ground(lect.x, lect.y, 0.45)), Vector3(0.7, 1.1, 0.6))
	_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(sea)) * Basis(Vector3.RIGHT, 0.4), k.on_ground(lect.x, lect.y, 1.1)), Vector3(1.0, 0.12, 0.7))
	k.collider(Vector3(0.8, 1.2, 0.7), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(sea)), k.on_ground(lect.x, lect.y, 0.6)), "stone")
	await k.step()
	m.commit(stone, k.surface("stone", 0.75), "Greywatch", true)
	if k.far:
		return
	# the names, in columns of chalk on the stones' faces
	var chalk := m.begin()
	for f in faces:
		var xf: Transform3D = f[0]
		var h: float = f[1]
		for col in 3:
			for row in int(h * 2.2):
				if k.rng.randf() < 0.15:
					continue
				var p := xf * Vector3(-0.45 + 0.45 * float(col), -h * 0.5 + 0.5 + float(row) * 0.38, 0.36)
				_box(chalk, Transform3D(xf.basis, p), Vector3(k.rng.randf_range(0.18, 0.38), 0.05, 0.01))
	await k.step()
	m.commit(chalk, PoiKit.plain(Color(0.86, 0.85, 0.8), 0.95), "Names")
	# the candle-stubs along the reading-stone, the mats before it
	for i in 5:
		var p := lect + along * (float(i) - 2.0) * 0.5 + sea * 0.5
		await k.step()
		k.place(k.prop("candle_stub"), k.on_ground(p.x, p.y), 0.0, 1.0, false)
	k.light(k.on_ground(lect.x, lect.y, 0.6), Color(1.0, 0.78, 0.5), 0.9, 5.0)
	var mats := m.begin()
	for i in 3:
		var p := lect - sea * 1.6 + along * (float(i) - 1.0) * 1.1
		_box(mats, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(sea) + k.rng.randf_range(-0.2, 0.2)), k.on_ground(p.x, p.y, 0.02)), Vector3(0.7, 0.04, 1.0))
	await k.step()
	m.commit(mats, PoiKit.painted(6, {"base": "#55504a", "accent": "#433f3a", "grout": "#2e2b27", "unit": 0.4}, 0.9), "Mats")
	k.marker("the_reading", k.on_ground(lect.x - sea.x * 1.2, lect.y - sea.y * 1.2))
	k.touchable("the_names", k.on_ground(lect.x, lect.y, 1.2), "Read the names on the stones",
			"core:dialogue/greywatch_names", "", false)
	await _grey_grass(d, 14.0, 24, back - sea * 4.0)


## The Ninth Waystone: three of the pilgrims' waystones beside the road from the West Downs, set
## one behind the other, every face of them scratched with the Order's bell-count, a tally a year;
## a bowl in the top of the middle one where the pilgrims leave a coin, and a stool for the Order's
## counter, who comes once a year to add the year.
static func ninth_waystone(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lie := _lie(k)
	var mid: Vector2 = lie[0]
	var along: Vector2 = lie[1]
	var across := Vector2(-along.y, along.x)
	var side := 1.0 if _off_road(k, mid + across * 5.0, 0.5) else -1.0
	var stone := m.begin()
	var marks := m.begin()
	for i in 3:
		var at: Vector2 = mid + along * (float(i) - 1.0) * 3.2 + across * side * (4.6 + 0.6 * float(i % 2))
		var h := [1.9, 2.4, 1.7][i] as float
		var xf := _slab(d, stone, at, -across * side, h, 0.9, 0.55, k.rng.randf_range(-0.06, 0.06), 0.4)
		# the tallies, both broad faces, rows of short strokes and a long one through each five
		for face in [-1.0, 1.0]:
			for row in int(h * 4.0):
				for j in 5:
					var p := xf * Vector3(-0.32 + 0.07 * float(j), -h * 0.5 + 0.3 + float(row) * 0.22, 0.285 * float(face))
					_box(marks, Transform3D(xf.basis * Basis(Vector3.BACK, 0.9 if j == 4 else 0.0), p), Vector3(0.012, 0.13, 0.008))
		if i == 1:
			# the coin-bowl on its top, and coins in it
			var top := xf * Vector3(0.0, h * 0.5 - 0.2 + 0.25, 0.0)
			_box(stone, Transform3D(xf.basis, top), Vector3(0.7, 0.12, 0.45))
	await k.step()
	m.commit(stone, k.surface("stone", 0.7), "Waystones", true)
	m.commit(marks, PoiKit.plain(Color(0.78, 0.76, 0.7), 0.95), "Tallies")
	if k.far:
		return
	var stool := mid + across * side * 3.0 + along * 1.4
	await k.step()
	k.place(k.prop("stool"), k.on_ground(stool.x, stool.y), PoiKit.yaw_of(across * side))
	k.marker("the_count", k.on_ground(stool.x, stool.y))
	k.touchable("the_tallies", k.on_ground(mid.x + across.x * side * 4.0, mid.y + across.y * side * 4.0, 1.1), "Read the count",
			"core:dialogue/ninth_waystone_count", "", false)
	await _grey_grass(d, 12.0, 20, mid + across * side * 5.0)


## The Greyline Stones: a line of the Wardens' chalk stones across the heath where the grey begins,
## each set a little further back towards the Vale than the one before, a year to a stone: the
## oldest far out in the grey and gone grey themselves, the newest white. A Warden's pole with the
## year's rag on it at the newest, and the measuring-rod lying in the grass.
static func greyline_stones(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var vale := Vector2(1.0, -0.6).normalized()     # the Vale lies north-east of the grey
	var line := Vector2(vale.y, -vale.x)
	var chalk := m.begin()
	var grey := m.begin()
	var n := 11
	var newest := Vector2.ZERO
	for i in n:
		var t := float(i) / float(n - 1)
		# the oldest out in the grey (south-west), each year's a stride further back
		var at := line * (float(i) - float(n - 1) * 0.5) * 2.6 + vale * lerpf(-11.0, 9.0, t) + k.jitter(0.3)
		if not _off_road(k, at, 0.3):
			continue
		var h := k.rng.randf_range(0.9, 1.4)
		var st := chalk if t > 0.55 else grey
		_slab(d, st, at, vale, h, 0.55, 0.4, k.rng.randf_range(-0.08, 0.08), 0.35)
		newest = at
	await k.step()
	m.commit(chalk, PoiKit.plain(Color(0.86, 0.84, 0.78), 0.85), "ChalkStones", true)
	m.commit(grey, k.surface("stone", 0.8), "GreyStones", true)
	if k.far:
		return
	# the Warden's pole at the newest, the year's rag tied on it, and the rod in the grass
	var timber := m.begin()
	var pole := newest + vale * 1.2
	var top := m.post(timber, pole, 2.6, 0.08)
	_box(timber, Transform3D(Basis.IDENTITY, k.on_ground((newest - vale * 2.5).x, (newest - vale * 2.5).y, 0.04)), Vector3(0.05, 0.05, 2.2))
	var rag := m.begin()
	var rb := Basis(Vector3.UP, PoiKit.yaw_of(line))
	_box(rag, Transform3D(rb * Basis(Vector3.FORWARD, 0.12), top - Vector3(0.0, 0.32, 0.0) + Vector3(line.x, 0.0, line.y) * 0.32), Vector3(0.03, 0.5, 0.6))
	_box(rag, Transform3D(rb * Basis(Vector3.FORWARD, -0.2), top - Vector3(0.0, 0.55, 0.0) + Vector3(line.x, 0.0, line.y) * 0.55), Vector3(0.025, 0.35, 0.3))
	await k.step()
	_commit_parts(d, [[timber, k.surface("timber", 0.7)], [rag, PoiKit.painted(6, {"base": "#6f7a5e", "accent": "#56604a", "grout": "#3a4032", "unit": 0.3}, 0.8)]], "WardensPole")
	k.marker("the_newest", k.on_ground(newest.x + vale.x * 2.0, newest.y + vale.y * 2.0))
	k.touchable("the_line", k.on_ground(newest.x, newest.y, 0.9), "Look along the line of stones",
			"core:dialogue/greyline_stones_line", "", false)
	await _grey_grass(d, 18.0, 30, -vale * 8.0)


## The Last Milestone: three of the Builders' milestones on their road west, counting down in their
## numerals, three, two, one, to a harbour that is not there; the last and smallest at the end of
## the paving, and on its back, low down, where you would only see them sitting against it, four
## names cut by four hands: the four who came back up the Stair.
static func last_milestone(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var west := Vector2(-1.0, 0.15).normalized()
	var across := Vector2(west.y, -west.x)
	var stone := m.begin()
	var numerals := m.begin()
	var last_xf := Transform3D.IDENTITY
	for i in 3:
		var at := -west * 9.0 + west * 9.0 * float(i)
		var h := [2.6, 2.2, 1.8][i] as float
		var xf := _slab(d, stone, at + across * 1.8, west, h, 1.1, 0.8, 0.0, 0.5)
		# its count, cut deep in the Builders' strokes: three, two, one
		for j in 3 - i:
			var p := xf * Vector3(-0.2 * float(2 - i) * 0.5 + 0.2 * float(j), h * 0.12, -0.41)
			_box(numerals, Transform3D(xf.basis, p), Vector3(0.07, 0.6, 0.02))
		last_xf = xf
	# the old road's paving between them, broken
	for i in 9:
		var p := -west * 12.0 + west * 3.0 * float(i) + k.jitter(0.25)
		if k.rng.randf() < 0.3:
			continue
		_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(west) + k.rng.randf_range(-0.1, 0.1)), k.on_ground(p.x, p.y, 0.02)),
				Vector3(2.6, 0.12, 2.6))
	await k.step()
	m.commit(stone, k.surface("oroth", 0.6), "Milestones", true)
	m.commit(numerals, PoiKit.plain(Color(0.04, 0.04, 0.045), 0.9), "Numerals")
	if k.far:
		return
	# the four names on the back of the last, low: a marker where they are read sitting down
	var names_at := last_xf * Vector3(0.0, -0.4, 0.75)
	var cut := m.begin()
	for j in 4:
		_box(cut, Transform3D(last_xf.basis, last_xf * Vector3(-0.1, -0.2 - 0.14 * float(j), 0.41)), Vector3(0.6, 0.035, 0.01))
	await k.step()
	m.commit(cut, PoiKit.plain(Color(0.07, 0.07, 0.075), 0.9), "FourNames")
	k.marker("the_names", Vector3(names_at.x, k.on_ground(names_at.x, names_at.z).y + 0.05, names_at.z))
	k.marker("the_road_west", k.on_ground(-west.x * 6.0, -west.y * 6.0))
	await _grey_grass(d, 14.0, 22)


## The Novices' Seats: three seats cut in the plateau's lip over the Hush, each a block of the
## Builders' stone with arms and a back, hollowed by novices of the Order sitting their first night
## with their backs to the Choir; and the third, a single stone the size of a cart, turned in the
## night to face the Choir, its seat towards the ring and its back to the sea.
static func novices_seats(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(500.0)
	if sea == Vector2.ZERO:
		sea = -_to_choir(k)
	sea = sea.normalized()
	var along := Vector2(sea.y, -sea.x)
	var stone := m.begin()
	var lip := Vector2.ZERO
	var g0 := k.on_ground(0.0, 0.0).y
	for i in 10:
		var q := sea * float(i + 1)
		if k.on_ground(q.x, q.y).y < g0 - 0.8 or k.is_water(q.x, q.y):
			break
		lip = q
	for i in 3:
		var at := lip - sea * 1.6 + along * (float(i) - 1.0) * 3.4
		var facing := sea if i != 2 else -sea
		if i == 2:
			at -= sea * 0.8
		_seat(d, stone, at, facing, 1.35 if i == 2 else 1.0)
	await k.step()
	m.commit(stone, k.surface("oroth", 0.5), "Seats", true)
	if k.far:
		return
	# the scrape in the ash where the third was turned, still showing
	var scrape := m.begin()
	var at2 := lip - sea * 1.6 + along * 3.4
	for j in 6:
		var p := at2 - sea * (0.3 + float(j) * 0.25) + along * sin(float(j)) * 0.3
		_box(scrape, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(along) + float(j) * 0.25), k.on_ground(p.x, p.y, 0.015)), Vector3(2.4, 0.02, 0.3))
	await k.step()
	m.commit(scrape, PoiKit.plain(Color(0.14, 0.135, 0.13), 0.98), "Scrape")
	k.marker("the_seats", k.on_ground(lip.x - sea.x * 4.4, lip.y - sea.y * 4.4))
	k.marker("home", k.on_ground(lip.x - sea.x * 9.0 - along.x * 6.0, lip.y - sea.y * 9.0 - along.y * 6.0))
	var tent := lip - sea * 10.0 - along * 7.5
	await k.step()
	k.place(k.prop("tent"), k.on_ground(tent.x, tent.y), PoiKit.yaw_of(sea))
	k.touchable("the_turned_seat", k.on_ground(at2.x - sea.x * 1.8, at2.y - sea.y * 1.8, 0.8), "Look at the turned seat",
			"core:dialogue/novices_seats_turned", "", false)
	await _grey_grass(d, 14.0, 20, -sea * 6.0)


## One seat of the Builders' stone, `s` times a man's, facing `face`: the seat, a back, two arms, the
## seat hollowed where the novices sat (a darker dish).
static func _seat(d: PoiDressing, st: SurfaceTool, at: Vector2, face: Vector2, s: float) -> void:
	var k := d.kit

	var g := k.on_ground(at.x, at.y)
	var b := Basis(Vector3.UP, PoiKit.yaw_of(face))
	_box(st, Transform3D(b, g + b * Vector3(0.0, 0.3 * s, 0.0)), Vector3(2.0 * s, 0.9 * s, 1.6 * s))
	_box(st, Transform3D(b, g + b * Vector3(0.0, 1.25 * s, -0.65 * s)), Vector3(2.0 * s, 1.9 * s, 0.4 * s))
	for x in [-1.0, 1.0]:
		_box(st, Transform3D(b, g + b * Vector3(0.85 * s * float(x), 0.95 * s, 0.05 * s)), Vector3(0.32 * s, 0.5 * s, 1.5 * s))
	k.collider(Vector3(2.0 * s, 0.9 * s, 1.6 * s), Transform3D(b, g + b * Vector3(0.0, 0.3 * s, 0.0)), "stone")
	k.collider(Vector3(2.0 * s, 1.9 * s, 0.4 * s), Transform3D(b, g + b * Vector3(0.0, 1.25 * s, -0.65 * s)), "stone")


## The Bowing Stones: three leaning stones by the Choir road under the Headless Watch, bent towards
## the Choir the way the colossi bow, the furthest lowest.
static func bowing_stones(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var choir := _to_choir(k)
	var across := Vector2(choir.y, -choir.x)
	var stone := m.begin()
	for i in 3:
		var at := across * (float(i) - 1.0) * 2.6 - choir * float(i) * 0.6
		_slab(d, stone, at, choir, [2.6, 2.3, 2.0][i] as float, 0.95, 0.55, 0.22 + 0.1 * float(i), 0.5)
	await k.step()
	m.commit(stone, k.surface("stone", 0.75), "BowingStones", true)


# --- the towers ---------------------------------------------------------------------------------------

## A square tower of the Builders' stone at `c` (local), `side` at its foot narrowing to `side_top` at
## `h`, its door to `face`, the corners buttressed, slit windows up it; into `st`. Collides as its
## four walls (you can stand in the door). Returns the top's middle.
static func _square_tower(d: PoiDressing, st: SurfaceTool, c: Vector2, face: Vector2, side: float, side_top: float,
		h: float, courses := 9) -> Vector3:
	var k := d.kit

	var b := Basis(Vector3.UP, PoiKit.yaw_of(face))
	var g := INF
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := c + Vector2(face.y, -face.x) * side * 0.5 * float(sx) + face * side * 0.5 * float(sz)
			g = minf(g, k.on_ground(p.x, p.y).y)
	var base := Vector3(c.x, g - 0.4, c.y)
	var lift := (h + 0.4) / float(courses)
	var wall := 0.9
	for i in courses:
		var t0 := float(i) / float(courses)
		var w := lerpf(side, side_top, t0 + 0.5 / float(courses))
		var y := base.y + lift * (float(i) + 0.5)
		for f in 4:
			var dir := b * Basis(Vector3.UP, PI * 0.5 * float(f))
			var off := dir * Vector3(0.0, 0.0, w * 0.5 - wall * 0.5)
			var size := Vector3(w, lift * 1.01, wall)
			# the door, two courses high, in the face
			if f == 0 and i < 2:
				for sx in [-1.0, 1.0]:
					var piece := Vector3(w * 0.5 - 0.8, lift * 1.01, wall)
					var px := dir * Vector3((0.8 + piece.x * 0.5) * float(sx), 0.0, w * 0.5 - wall * 0.5)
					_box(st, Transform3D(dir, Vector3(c.x, y, c.y) + px), piece)
				continue
			_box(st, Transform3D(dir, Vector3(c.x, y, c.y) + off), size)
			# a slit window every third course, on the faces that are not the door's
			if i % 3 == 2 and f != 0:
				_box(st, Transform3D(dir, Vector3(c.x, y, c.y) + dir * Vector3(0.0, 0.0, w * 0.5 + 0.01)), Vector3(0.22, lift * 0.75, 0.04))
		if i % 3 == 1:
			await k.step()
	# the buttresses at the corners, stepped in as they climb
	for f in 4:
		var dir := b * Basis(Vector3.UP, PI * 0.5 * float(f) + PI * 0.25)
		for j in 3:
			var bh := h * (0.42 - 0.12 * float(j))
			var out := side * 0.71 - 0.1 * float(j)
			_box(st, Transform3D(dir, Vector3(c.x, base.y + bh * 0.5, c.y) + dir * Vector3(0.0, 0.0, out - 0.2)), Vector3(1.0 - 0.2 * float(j), bh, 1.2))
	# a lintel over the door
	_box(st, Transform3D(b, Vector3(c.x, base.y + lift * 2.0 + 0.2, c.y) + b * Vector3(0.0, 0.0, side * 0.5 - wall * 0.5 + 0.05)), Vector3(2.2, 0.4, wall + 0.1))
	for f in 4:
		var dir := b * Basis(Vector3.UP, PI * 0.5 * float(f))
		var tall := h + 0.4 if f != 0 else h + 0.4
		var cxf := Transform3D(dir, Vector3(c.x, base.y + tall * 0.5, c.y) + dir * Vector3(0.0, 0.0, side * 0.5 - wall * 0.5))
		if f == 0:
			# the door's face collides either side of the door and over it
			for sx in [-1.0, 1.0]:
				k.collider(Vector3(side * 0.5 - 0.8, tall, wall), Transform3D(dir, cxf.origin + dir * Vector3((0.8 + (side * 0.5 - 0.8) * 0.5) * float(sx), 0.0, 0.0)), "stone")
			k.collider(Vector3(1.8, tall - lift * 2.0, wall), Transform3D(dir, cxf.origin + Vector3(0.0, lift, 0.0)), "stone")
		else:
			k.collider(Vector3(side, tall, wall), cxf, "stone")
	return Vector3(c.x, base.y + h + 0.4, c.y)


## The Tower of Vaelost: the Builders' tower still standing over the dead city, twenty-four metres of
## their stone tapering to a broken crown, buttressed at its corners, slit windows up it, its door to
## the track from the Sunk Plaza; round the top a course of bronze plates hung by their corners,
## which ring when the wind crosses them, and at its foot the pieces of the top course that fell,
## one with letters on it, a name nobody has read.
static func tower_of_vaelost(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lie := _lie(k)
	var along: Vector2 = lie[1]
	var road_at: Vector2 = lie[0]
	var face := (-road_at).normalized() if road_at.length() > 1.0 else along
	# the track ends at the door: the tower stands off it, its door towards where it comes in
	var c := Vector2(along.y, -along.x) * 6.5
	if not _off_road(k, c, 4.0):
		c = -Vector2(along.y, -along.x) * 6.5
	face = (road_at - c).normalized() if road_at.distance_to(c) > 1.0 else face
	var stone := m.begin()
	var top := await _square_tower(d, stone, c, face, 6.0, 4.6, 24.0, 12)
	# the broken crown: merlons standing on two faces, gone on the others
	var b := Basis(Vector3.UP, PoiKit.yaw_of(face))
	for f in 4:
		var dir := b * Basis(Vector3.UP, PI * 0.5 * float(f))
		for j in 4:
			if (f + j) % 3 == 0:
				continue
			var x := -1.7 + 1.15 * float(j)
			var mh := k.rng.randf_range(0.6, 1.4)
			_box(stone, Transform3D(dir, top + dir * Vector3(x, mh * 0.5, 2.0)), Vector3(0.8, mh, 0.6))
	await k.step()
	m.commit(stone, k.surface("oroth", 0.6), "Vaelost", true)
	# the ringing course: bronze plates hung from pins round the top, a little askew
	var plates := m.begin()
	for f in 4:
		var dir := b * Basis(Vector3.UP, PI * 0.5 * float(f))
		for j in 6:
			var x := -1.9 + 0.76 * float(j)
			var p := top - Vector3(0.0, 0.9, 0.0) + dir * Vector3(x, 0.0, 2.42)
			_box(plates, Transform3D(dir * Basis(Vector3.BACK, k.rng.randf_range(-0.12, 0.12)), p), Vector3(0.55, 0.9, 0.04))
	await k.step()
	m.commit(plates, _bronze(), "RingingCourse", true)
	if k.far:
		return
	# the fallen pieces of the top course at its foot, one face-up with its letters
	var fallen := c - face * 5.5 + Vector2(face.y, -face.x) * 3.0
	var chunks := m.begin()
	for i in 4:
		var p := fallen + k.jitter(2.2)
		_box(chunks, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.3, 0.3)), k.on_ground(p.x, p.y, 0.25)),
				Vector3(1.4, 0.6, 0.7))
		k.collider(Vector3(1.4, 0.6, 0.7), Transform3D(Basis.IDENTITY, k.on_ground(p.x, p.y, 0.3)), "stone")
	await k.step()
	m.commit(chunks, k.surface("oroth", 0.7), "FallenCourse")
	var letters := m.begin()
	var lp := k.on_ground(fallen.x, fallen.y, 0.6)
	_box(letters, Transform3D(Basis(Vector3.UP, 0.4), lp + Vector3(0.0, 0.01, 0.0)), Vector3(1.2, 0.02, 0.5))
	await k.step()
	m.commit(letters, PoiKit.plain(Color(0.07, 0.07, 0.075), 0.9), "Letters")
	k.marker("the_fallen_course", lp + Vector3(0.0, 0.05, 0.0))
	k.marker("the_foot", k.on_ground(c.x + face.x * 6.0, c.y + face.y * 6.0))
	k.touchable("the_course", lp + Vector3(0.0, 0.3, 0.0), "Read the letters on the fallen stone",
			"core:dialogue/vaelost_course", "", false)
	await _rubble(d, c, 12.0, 16)
	await _grey_grass(d, 16.0, 30)


## Sulion: the dead city's harbour light, a round tower narrowing to a gallery, and on the gallery the
## lamp-socket, a great ring of the Builders' stone standing on its edge facing the sea with nothing in
## it, staring out; a stair cut up the tower's outside to the gallery, its treads every way broken.
static func sulion(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(600.0)
	if sea == Vector2.ZERO:
		sea = Vector2(-1.0, 0.0)
	sea = sea.normalized()
	var lie := _lie(k)
	var along: Vector2 = lie[1]
	var c := Vector2(along.y, -along.x) * 7.5
	if not _off_road(k, c, 4.5):
		c = -c
	var g := k.on_ground(c.x, c.y).y
	var stone := m.begin()
	var h := 17.0
	m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(c.x, g, c.y)), 3.4, h * 0.55, 0.0, PoiKit.yaw_of(-sea), true, 0.6)
	m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(c.x, g + h * 0.55, c.y)), 2.9, h * 0.45, 0.0, NAN, true, 0.6)
	# the gallery: a corbelled ring and a floor
	m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(c.x, g + h, c.y)), 3.5, 0.6, 0.0, NAN, false, 0.3)
	_lathe(stone, Transform3D(Basis.IDENTITY, Vector3(c.x, g + h + 0.25, c.y)), [Vector2(3.5, 0.0), Vector2(0.0, 0.0)], 24, true)
	_lathe(stone, Transform3D(Basis.IDENTITY, Vector3(c.x, g + h + 0.3, c.y)), [Vector2(3.4, 0.0), Vector2(0.0, 0.0)], 24, false)
	k.collider(Vector3(6.6, 0.4, 6.6), Transform3D(Basis.IDENTITY, Vector3(c.x, g + h + 0.1, c.y)), "stone")
	# the socket: a ring on its edge facing the sea, the empty middle black
	var ring_c := Vector3(c.x, g + h + 3.0, c.y)
	var rb := Basis(Vector3.UP, PoiKit.yaw_of(sea))
	var r := 2.3
	for i in 16:
		var a0 := TAU * float(i) / 16.0
		var a1 := TAU * float(i + 1) / 16.0
		m.limb(stone, ring_c + rb * Vector3(cos(a0) * r, sin(a0) * r, 0.0), ring_c + rb * Vector3(cos(a1) * r, sin(a1) * r, 0.0), 0.42)
	for s in [-1.0, 1.0]:
		_box(stone, Transform3D(rb, ring_c + rb * Vector3(float(s) * 1.3, -2.1, 0.0)), Vector3(0.6, 1.6, 0.8))
	await k.step()
	m.commit(stone, k.surface("oroth", 0.55), "Sulion", true)
	var socket := m.begin()
	_lathe(socket, Transform3D(rb * Basis(Vector3.RIGHT, PI * 0.5), ring_c - Vector3(sea.x, 0.0, sea.y) * 0.05), [Vector2(r - 0.3, 0.0), Vector2(0.0, 0.0)], 20, true)
	await k.step()
	m.commit(socket, PoiKit.plain(Color(0.02, 0.02, 0.024), 1.0), "Socket", true)
	# the stair cut up its outside, a spiral of broken treads
	var treads := m.begin()
	var n := 30
	for i in n:
		var t := float(i) / float(n)
		if i % 7 == 5:
			continue
		var a := PoiKit.yaw_of(-sea) + 0.6 + t * TAU * 1.1
		var rr := lerpf(3.4, 2.9, clampf((t - 0.5) * 3.0, 0.0, 1.0)) + 0.55
		var y := g + 0.35 + t * (h - 0.4)
		var p := Vector3(c.x + sin(a) * rr, y, c.y + cos(a) * rr)
		var tb := Basis(Vector3.UP, a)
		_box(treads, Transform3D(tb, p), Vector3(1.2, 0.22, 0.8))
		k.collider(Vector3(1.2, 0.22, 0.8), Transform3D(tb, p), "stone")
	await k.step()
	m.commit(treads, k.surface("oroth", 0.7), "Stair", true)
	if k.far:
		return
	k.marker("the_socket", Vector3(c.x, g + h + 0.35, c.y) - Vector3(sea.x, 0.0, sea.y) * 1.0, false, true, 3.0)
	k.marker("the_foot", k.on_ground(c.x - sea.x * 6.0, c.y - sea.y * 6.0))
	await _rubble(d, c, 12.0, 14)


## The Hush Bell: a bell-tower on the cliff's edge, square and plain, and from its top a stone arm
## reaching out over the Hush with the pilgrims' great bell hung from its end above the sea, the new
## rope going down from it wet. At the arm's root the rope is made fast to a ring; whoever wants the
## rope's end cuts it there.
static func hush_bell(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(500.0)
	if sea == Vector2.ZERO:
		sea = k.downhill() if k.downhill() != Vector2.ZERO else Vector2(0.0, 1.0)
	sea = sea.normalized()
	# the tower stands back from the lip, the arm reaching out past it
	var g0 := k.on_ground(0.0, 0.0).y
	var lip := Vector2.ZERO
	for i in 20:
		var q := sea * float(i + 1)
		if k.on_ground(q.x, q.y).y < g0 - 1.0 or k.is_water(q.x, q.y):
			break
		lip = q
	var c := lip - sea * 3.5
	var stone := m.begin()
	var top := await _square_tower(d, stone, c, -sea, 4.4, 3.8, 11.0, 8)
	# the arm: corbelled out from the top course over the edge, a beam of stone
	var reach := 7.5
	var arm_y := top.y - 0.6
	var b := Basis(Vector3.UP, PoiKit.yaw_of(sea))
	for i in 5:
		var t := float(i) / 5.0
		var p := Vector3(c.x, arm_y, c.y) + Vector3(sea.x, 0.0, sea.y) * (1.6 + reach * (t + 0.1))
		var thick := lerpf(1.3, 0.7, t)
		_box(stone, Transform3D(b, p + Vector3(0.0, -thick * 0.25, 0.0)), Vector3(1.1, thick, reach / 5.0 * 1.04))
	# a cap course round the top
	_box(stone, Transform3D(b, top + Vector3(0.0, 0.2, 0.0)), Vector3(4.4, 0.4, 4.4))
	# the bell, hung from the arm's end, out over the drop
	var bronze := m.begin()
	var end := Vector3(c.x, arm_y - 0.5, c.y) + Vector3(sea.x, 0.0, sea.y) * (1.6 + reach)
	var bell_h := 2.6
	m.limb(bronze, end + Vector3(0.0, 0.3, 0.0), end - Vector3(0.0, 0.7, 0.0), 0.06)
	_bell(d, bronze, end - Vector3(0.0, 0.7 + bell_h, 0.0), Vector3.UP, 1.15, bell_h, true)
	# the rope: up from the bell along the arm, over the top course, and down the tower's land face to
	# the ring by the door it is made fast to, its end coiled there, wet
	var rope := m.begin()
	var over := Vector3(c.x, top.y + 0.45, c.y)
	var face_foot := c - sea * (2.2 + 0.25) + Vector2(sea.y, -sea.x) * 1.5
	var ring := k.on_ground(face_foot.x, face_foot.y, 1.1)
	m.limb(rope, end - Vector3(0.0, 0.4, 0.0), over + Vector3(sea.x, 0.0, sea.y) * 1.4, 0.035)
	m.limb(rope, over + Vector3(sea.x, 0.0, sea.y) * 1.4, over - Vector3(sea.x, 0.0, sea.y) * 2.2, 0.035)
	m.limb(rope, over - Vector3(sea.x, 0.0, sea.y) * 2.25, ring, 0.035)
	var iron := m.begin()
	for i in 10:
		var a0 := TAU * float(i) / 10.0
		var a1 := TAU * float(i + 1) / 10.0
		var ax := Vector3(-sea.y, 0.0, sea.x)
		m.limb(iron, ring + ax * cos(a0) * 0.14 + Vector3(0.0, sin(a0) * 0.14, 0.0), ring + ax * cos(a1) * 0.14 + Vector3(0.0, sin(a1) * 0.14, 0.0), 0.025)
	# the ring's own stone, a block set in the ground under it
	_box(stone, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(sea)), ring - Vector3(0.0, 0.62, 0.0)), Vector3(0.45, 1.0, 0.35))
	k.collider(Vector3(0.45, 1.0, 0.35), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(sea)), ring - Vector3(0.0, 0.62, 0.0)), "stone")
	await k.step()
	_commit_parts(d, [[stone, k.surface("stone", 0.65)], [bronze, _bronze()], [rope, PoiKit.plain(Color(0.36, 0.33, 0.27), 0.95)],
			[iron, PoiKit.plain(Color(0.16, 0.12, 0.1), 0.6, 0.5)]], "HushBell", true)
	if k.far:
		return
	var coil := face_foot - sea * 0.9 + Vector2(sea.y, -sea.x) * 0.8
	await k.step()
	k.place(k.prop("rope_coil"), k.on_ground(coil.x, coil.y), k.rng.randf_range(0.0, TAU), 1.0, false)
	k.marker("the_bell_arm", k.on_ground(coil.x, coil.y, 0.05))
	k.marker("the_tower_door", k.on_ground(c.x - sea.x * 4.0, c.y - sea.y * 4.0))
	k.touchable("the_bell", ring + Vector3(0.0, 0.2, 0.0) - Vector3(sea.x, 0.0, sea.y) * 0.3, "Look up at the bell", "core:dialogue/hush_bell_look", "", false)
	await _rubble(d, c - sea * 6.0, 8.0, 10)


## The Strand Beacon: the salt-traders' beacon on the strand, a squat drum of the grey stone with a
## stair up its landward side to the fire-bowl on top (an Oroth bell upturned in an iron cage), and
## the driftwood for it stacked at its foot, more than anyone has been seen to bring. It is lit every
## night by nobody anyone has met.
static func strand_beacon(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var sea := k.water_direction(400.0)
	if sea == Vector2.ZERO:
		sea = Vector2(-1.0, 0.0)
	sea = sea.normalized()
	var lie := _lie(k)
	var along: Vector2 = lie[1]
	var c := Vector2(along.y, -along.x) * 7.0
	if not _off_road(k, c, 4.0) or k.is_water(c.x, c.y):
		c = -c
	var g := k.on_ground(c.x, c.y).y
	var stone := m.begin()
	var r := 3.2
	var h := 7.2
	m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(c.x, g, c.y)), r, h, 0.0, NAN, true, 0.5)
	m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(c.x, g + h, c.y)), r + 0.3, 0.45, 0.0, NAN, false, 0.45)
	_lathe(stone, Transform3D(Basis.IDENTITY, Vector3(c.x, g + h + 0.3, c.y)), [Vector2(r + 0.2, 0.0), Vector2(0.0, 0.0)], 22, false)
	k.collider(Vector3(r * 1.9, 0.4, r * 1.9), Transform3D(Basis.IDENTITY, Vector3(c.x, g + h + 0.15, c.y)), "stone")
	# the stair round its landward side, solid steps of the stone, to the top
	var land := -sea
	var n := 18
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var a := PoiKit.yaw_of(land) - 1.4 + t * 2.8
		var y := g + t * (h + 0.3)
		var p := Vector3(c.x + sin(a) * (r + 0.6), (y + g - 0.3) * 0.5, c.y + cos(a) * (r + 0.6))
		var tb := Basis(Vector3.UP, a)
		var size := Vector3(1.0, y - g + 0.3, 1.25)
		_box(stone, Transform3D(tb, p), size)
		k.collider(size, Transform3D(tb, p), "stone")
		if i % 6 == 5:
			await k.step()
	await k.step()
	m.commit(stone, k.surface("stone", 0.7), "Beacon", true)
	# the fire-bowl: a Builders' bell upturned on the top, mouth to the sky, in its cage
	var bronze := m.begin()
	var top := Vector3(c.x, g + h + 0.3, c.y)
	_bell(d, bronze, top + Vector3(0.0, 1.9, 0.0), Vector3.DOWN, 1.25, 2.4, true)
	await k.step()
	m.commit(bronze, _bronze(), "FireBowl", true)
	var iron := m.begin()
	for i in 8:
		var a := TAU * float(i) / 8.0
		m.limb(iron, top + Vector3(sin(a) * 1.6, 0.0, cos(a) * 1.6), top + Vector3(sin(a) * 1.9, 2.4, cos(a) * 1.9), 0.06)
	for hoop in [1.1, 2.3]:
		var rr := lerpf(1.6, 1.9, float(hoop) / 2.4)
		for i in 14:
			var a0 := TAU * float(i) / 14.0
			var a1 := TAU * float(i + 1) / 14.0
			m.limb(iron, top + Vector3(sin(a0) * rr, float(hoop), cos(a0) * rr), top + Vector3(sin(a1) * rr, float(hoop), cos(a1) * rr), 0.045)
	await k.step()
	m.commit(iron, PoiKit.plain(Color(0.12, 0.11, 0.1), 0.55, 0.6), "Cage", true)
	k.light(top + Vector3(0.0, 2.2, 0.0), Color(1.0, 0.6, 0.28), 4.5, 26.0)
	k.puffs(top + Vector3(0.0, 2.1, 0.0), Vector3(0.4, 0.1, 0.4), 1.4, 16, Color(0.4, 0.38, 0.36, 0.45), 2.2, 6.0)
	if k.far:
		return
	# the driftwood stacked at its foot, more of it than anyone brings
	var pile := c + land * (r + 2.6) + Vector2(land.y, -land.x) * 2.6
	var logs: Array = []
	for i in 14:
		var p := pile + k.jitter(1.0)
		logs.append(PoiKit.transform_at(k.on_ground(p.x, p.y, 0.1 + 0.25 * floorf(float(i) / 5.0)), k.rng.randf_range(0.0, TAU),
				k.rng.randf_range(0.7, 1.0), Vector3(0.0, 0.0, PI * 0.5)))
	await k.step()
	k.scatter(k.rock("driftwood"), logs, true)
	k.marker("the_stair_foot", k.on_ground(c.x + land.x * (r + 2.0), c.y + land.y * (r + 2.0)))
	k.touchable("the_ashes", top + Vector3(0.0, 1.2, 0.0) + Vector3(land.x, 0.0, land.y) * 1.8, "Look in the fire-bowl",
			"core:dialogue/strand_beacon_bowl", "", false)
	await _cache(d, k.on_ground(pile.x - land.y * 2.2, pile.y + land.x * 2.2), PoiKit.yaw_of(sea), "crate",
			"core:loot/pilgrims_bundle", "salt_crate")


# --- setting the kinds' own pieces straight -------------------------------------------------------------

## A loose prop's box in the dressing's space: its meshes' boxes together.
static func _box_of(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi_v in n.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_v as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := mi.transform
		var p: Node = mi.get_parent()
		while p != null and p != n:
			if p is Node3D:
				t = (p as Node3D).transform * t
			p = p.get_parent()
		var b := n.transform * t * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## After a kind's own builder: its loose props (each a forge asset with its collision under it) set
## straight where they met trouble. One standing in a road's carriageway is moved out to the verge;
## one sharing most of its footprint with another is moved off it; each is stood on the ground
## where it comes to. The seat audit found a stool in the Pilgrim Road at the Sweeper's Lean-To, a
## barrow in a barrel at the Last Furrow, a chopping block in a basket at the Scavengers' Ring.
static func _settle(d: PoiDressing, roads := true) -> void:
	var k := d.kit
	if k.far:
		return
	var props: Array = []
	for c in k.root.get_children():
		if not (c is Node3D) or c is GeometryInstance3D or c is CollisionObject3D or c is Marker3D \
				or c is Light3D or c is GPUParticles3D or c is Area3D:
			continue
		var n := c as Node3D
		var box := _box_of(n)
		if box.size == Vector3.ZERO or box.size.y > 2.6 or maxf(box.size.x, box.size.z) > 3.4:
			continue
		props.append([n, box])
	# out of the carriageway, square to the road
	for e in (props if roads else []):
		var n: Node3D = e[0]
		var box: AABB = e[1]
		var at := Vector2(box.get_center().x, box.get_center().z)
		var need := PoiKit.ROAD_CLEAR_M + 1.2 + maxf(box.size.x, box.size.z) * 0.5
		var dist := k.road_distance(at)
		if dist >= need:
			continue
		var line := _road_line(k, 60.0)
		if line.is_empty():
			continue
		var dir: Vector2 = line[1]
		var across := Vector2(-dir.y, dir.x)
		var off := (at - (line[0] as Vector2)).dot(across)
		var sgn := 1.0 if off >= 0.0 else -1.0
		_shift(k, n, across * sgn * (need - dist + 0.2))
		e[1] = _box_of(n)
	# off each other
	for i in props.size():
		for j in range(i + 1, props.size()):
			var a: AABB = props[i][1]
			var b: AABB = props[j][1]
			var ix := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
			var iz := minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z)
			if ix <= 0.0 or iz <= 0.0:
				continue
			var small := minf(a.size.x * a.size.z, b.size.x * b.size.z)
			if ix * iz < 0.4 * small:
				continue
			var mover: Array = props[j] if b.size.x * b.size.z <= a.size.x * a.size.z else props[i]
			var other: AABB = a if mover == props[j] else b
			var mb: AABB = mover[1]
			var away := Vector2(mb.get_center().x - other.get_center().x, mb.get_center().z - other.get_center().z)
			if away.length() < 0.05:
				away = Vector2(1.0, 0.0)
			away = away.normalized()
			var push := (minf(ix, iz) + 0.15)
			_shift(k, mover[0], away * push)
			mover[1] = _box_of(mover[0])


static func _shift(k: PoiKit, n: Node3D, by: Vector2) -> void:
	var from := Vector2(n.position.x, n.position.z)
	var to := from + by
	var dy := k.on_ground(to.x, to.y).y - k.on_ground(from.x, from.y).y
	n.position += Vector3(by.x, dy, by.y)


## The Sweeper's Lean-To, with its stools out of the Pilgrim Road.
static func sweepers_lean_to(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().camp(d)
	_settle(d)


## The Stair Head, the first camp every player sees, with its sack off the charred stump the burn
## stood under it (the seat audit's one overlap in the region). Nothing else of it is moved.
static func stair_head(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().camp(d)
	_settle(d, false)


## The Last Furrow: the farmstead, its barrow out of the barrel.
static func ploughed_ash(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().LAND.farmstead(d)
	_settle(d)


## The Tower-Road Bell, its bell set down on its stones (the shrine stood it a hand over them).
static func tower_road_bell(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().shrine(d)
	var k := d.kit
	if k.far:
		return
	for c in k.root.get_children():
		if c is Node3D and str((c as Node).name).contains("bell_medium"):
			var n := c as Node3D
			var box := _box_of(n)
			var g := k.on_ground(box.get_center().x, box.get_center().z).y
			# down onto what it stands on: the three stones' tops are a little under its rim
			if box.position.y > g + 0.12:
				n.position.y -= minf(box.position.y - g - 0.1, 0.3)
	_settle(d)


# === the large places (world life phase 2) ===========================================================
#
# Three places a body sees from a long way off and goes into: the Undertone, a doorway cut in the
# Choir plateau's western cliff over the dark the note comes out of; the Founders' Delf, the dead
# city's bell-foundry, its last great bell still in its mould under a gantry, its stacks over the
# Ashgrid; and Chalkwatch, a Wardens' fort on the west heath the grey took with its garrison in it.

const NOTE_BLUE := Color(0.56, 0.72, 0.9)
const CLAY := {"base": "#5a4a3e", "accent": "#463a30", "grout": "#2a221c", "unit": 0.6}
const BRICK := {"base": "#5d3f33", "accent": "#4a3128", "grout": "#2a1c17", "unit": 0.32}
const SLAG := {"base": "#1d1b1d", "accent": "#2c292c", "grout": "#0d0c0d", "unit": 0.3}
## The Undertone's facade: the Builders' dark stone in courses 4.2 m high, and its choristers carved
## whole from it.
const CARVED := {"base": "#3a3734", "accent": "#4a4540", "grout": "#1b1918", "unit": 4.2}
const CHORISTER_STONE := {"base": "#45413c", "accent": "#35322e", "grout": "#1e1c1a", "unit": 0.8}


## A surface of revolution over part of the round only: `a0` to `a1` (radians), both faces drawn
## (each its own smoothing group), for a thing broken open (the mould with a side gone).
static func _lathe_part(st: SurfaceTool, xf: Transform3D, profile: Array, a0: float, a1: float, segments := 20) -> void:
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		for s in segments:
			var b0 := lerpf(a0, a1, float(s) / float(segments))
			var b1 := lerpf(a0, a1, float(s + 1) / float(segments))
			var a := xf * Vector3(sin(b0) * p0.x, p0.y, cos(b0) * p0.x)
			var b := xf * Vector3(sin(b1) * p0.x, p0.y, cos(b1) * p0.x)
			var c := xf * Vector3(sin(b1) * p1.x, p1.y, cos(b1) * p1.x)
			var dd := xf * Vector3(sin(b0) * p1.x, p1.y, cos(b0) * p1.x)
			_two_sided(st, [a, dd, b, b, dd, c])


## Where the land in front of a cliff meets it: along `into` from the middle, the last point whose
## ground is within `rise` of the middle's, at most `reach` out. Returns its distance.
static func _cliff_foot(k: PoiKit, into: Vector2, rise := 2.5, reach := 24.0) -> float:
	var g0 := k.on_ground(0.0, 0.0).y
	var best := 0.0
	var t := 1.0
	while t <= reach:
		var q := into * t
		if k.on_ground(q.x, q.y).y > g0 + rise:
			break
		best = t
		t += 1.0
	return best


# --- the Undertone ------------------------------------------------------------------------------------

## A doorway cut into the western cliff of the Choir plateau: two pilasters fifteen metres high either
## side of an opening eleven high, a lintel and a stepped crown over it, a headless chorister carved
## standing against each pilaster with its hands at its breast, the doors (two slabs of the Builders'
## stone, hingeless) fallen outward across the forecourt, black glass run down the rock from a crack
## over the crown as if the cliff had wept; inside, the throat going in dark and a cold blue light
## at the back of it, the note-light. In the forecourt the Order's braziers, cold, burning blue.
## To one side the Sayer's camp: her tent, her tuning-board (the site's hook), her brass fork on its
## stand, aimed at the door.
static func the_undertone(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var site: Dictionary = ContentDB.get_or_empty(d.poi_id).get("site", {})
	var into := k.uphill()
	if into == Vector2.ZERO:
		into = Vector2(1.0, 0.0)
	into = into.normalized()
	var across := Vector2(into.y, -into.x)
	var b := Basis(Vector3.UP, PoiKit.yaw_of(-into))         # its front faces out of the cliff
	# the cliff's foot. The facade's front stands a little short of it and its pilasters run back into
	# the rise, the cliff's own rock heaped against their outer sides (below), so the doorway is cut
	# into the plateau's face. (Its front at the foot less seven metres stood it out on the plain, a
	# block twenty-two metres high with eleven-metre sides, and from the side that was all it was.)
	var foot := clampf(_cliff_foot(k, into), 14.0, 26.0)
	var face := into * (foot - 2.0)                           # the facade's front
	var g := k.on_ground(face.x, face.y).y
	var stone := m.begin()
	# big enough to read as a door in the plateau from the far side of the Ashgrid: the cliff is fifty
	# metres, and a facade of seventeen read as a notch in it at a quarter of a kilometre
	var open_w := 8.0
	var open_h := 15.0
	var pil := 4.2
	var deep := 8.0                                            # from its front back into the rock
	var back := face + into * deep * 0.5
	var out3 := -Vector3(into.x, 0.0, into.y)
	# the pilasters, the lintel over the opening, the stepped crown
	for s in [-1.0, 1.0]:
		var p := back + across * (open_w * 0.5 + pil * 0.5) * float(s)
		var xf := Transform3D(b, Vector3(p.x, g + 10.0 - 1.0, p.y))
		_box(stone, xf, Vector3(pil, 22.0, deep))
		k.collider(Vector3(pil, 22.0, deep), xf, "stone")
		# its plinth and capital, stepped out
		_box(stone, Transform3D(b, Vector3(p.x, g + 0.4, p.y) + out3 * 0.35), Vector3(pil + 0.7, 1.6, deep + 0.6))
		_box(stone, Transform3D(b, Vector3(p.x, g + open_h + 0.3, p.y) + out3 * 0.3), Vector3(pil + 0.6, 0.8, deep + 0.5))
		# the architrave: a band cut proud round the opening, up each side
		var jamb := face + across * (open_w * 0.5 + 0.45) * float(s)
		_box(stone, Transform3D(b, Vector3(jamb.x, g + open_h * 0.5, jamb.y) + out3 * 0.25), Vector3(0.9, open_h, 0.5))
	# three flutes down each pilaster's face, from its plinth to its capital: the eye reads the height
	# off them, where a flat face gave it nothing to measure by
	var flutes := m.begin()
	for s in [-1.0, 1.0]:
		for f in 3:
			# (clear of the architrave band round the opening)
			var fx := face + across * (open_w * 0.5 + 1.4 + float(f) * pil * 0.24) * float(s)
			_box(flutes, Transform3D(b, Vector3(fx.x, g + 1.2 + (open_h - 1.4) * 0.5, fx.y) + out3 * 0.02), Vector3(0.38, open_h - 1.4, 0.1))
	await k.step()
	m.commit(flutes, PoiKit.plain(Color(0.06, 0.055, 0.05), 0.95), "Flutes", true)
	var lintel := Transform3D(b, Vector3(back.x, g + open_h + 1.4, back.y))
	_box(stone, lintel, Vector3(open_w + pil * 2.0 + 0.6, 2.8, deep))
	k.collider(Vector3(open_w + pil * 2.0, 2.8, deep), lintel, "stone")
	# (and across the head, under the lintel's face)
	_box(stone, Transform3D(b, Vector3(face.x, g + open_h + 0.45, face.y) + out3 * 0.25), Vector3(open_w + 1.8, 0.9, 0.5))
	for i in 4:
		var w := open_w + pil * 2.0 - 2.6 * float(i + 1)
		_box(stone, Transform3D(b, Vector3(back.x, g + open_h + 3.4 + 1.5 * float(i), back.y)), Vector3(w, 1.5, deep - 0.6 * float(i)))
	# the doorway's floor, paved, going in to the dark at the cliff's foot
	var floor_at := face + into * 3.5
	_box(stone, Transform3D(b, Vector3(floor_at.x, g - 0.15, floor_at.y)), Vector3(open_w + 0.4, 0.4, 7.0))
	k.collider(Vector3(open_w + 0.4, 0.4, 7.0), Transform3D(b, Vector3(floor_at.x, g - 0.15, floor_at.y)), "stone")
	var throat := 6.5
	await k.step()
	# the Builders' stone carved whole, one face of it: in courses (of a metre, of two, of four) the
	# facade read as a brick house a few metres high, the courses the scale the eye took from it
	var carved := PoiKit.painted(0, CARVED, 0.5, 0.55)
	m.commit(stone, carved, "Undertone", true)
	var dark := m.begin()
	var end_at := face + into * throat
	_box(dark, Transform3D(b, Vector3(end_at.x, g + open_h * 0.5, end_at.y)), Vector3(open_w + 0.4, open_h + 0.4, 0.3))
	k.collider(Vector3(open_w + 0.4, open_h + 0.4, 0.3), Transform3D(b, Vector3(end_at.x, g + open_h * 0.5, end_at.y)), "stone")
	await k.step()
	m.commit(dark, PoiKit.plain(HOLE, 1.0), "TheDark", true)
	# The face the Builders cut the door into. The plateau's west side is a slope here, not a cliff, and
	# a facade stood at its foot read as a small house at the bottom of a hill: so the cliff's own rock
	# stands either side of the pilasters to the facade's height and over its crown, a face of rock the
	# doorway is carved into. Each piece by its bounds (a cliff piece is fifteen to thirty metres across
	# and twelve deep): its inner edge at the pilaster, its front no more than a metre proud of it.
	# (two narrow pieces a side: the wide ones reached forty metres along the foot, out to where a body
	# coming along the cliff stands, and stood it inside the rock)
	var band := [[1, 25.0, 0.0], [1, 18.0, 1.0]]
	for s in [-1.0, 1.0]:
		var out_at := open_w * 0.5 + pil
		for piece: Array in band:
			var rp := k.rock("cliff_face", int(piece[0]))
			if rp == "":
				continue
			var bd: Dictionary = PoiKit.meta(rp).get("bounds", {})
			var bmin: Array = bd.get("min", [-8.0, 0.0, -6.0])
			var bmax: Array = bd.get("max", [8.0, 16.0, 6.0])
			var sc := clampf(float(piece[1]) / maxf(float(bd.get("height", 16.0)), 0.5), 0.3, 3.0)
			var half := maxf(-float(bmin[0]), float(bmax[0])) * sc
			var fore := float(bmax[2]) * sc
			var at := face + into * (fore - 1.0 + 2.0 * float(piece[2])) + across * (out_at + half * 0.85) * float(s)
			out_at += half * 1.7
			await k.step()
			k.place(rp, k.on_ground(at.x, at.y, -1.0), PoiKit.yaw_of(-into) + 0.08 * float(s), sc, true, Vector3.ZERO, true)
	var over := k.rock("cliff_face", 0)
	if over != "":
		var bd: Dictionary = PoiKit.meta(over).get("bounds", {})
		var bmax: Array = bd.get("max", [8.0, 16.0, 6.0])
		var sc := clampf(26.0 / maxf(float(bd.get("height", 16.0)), 0.5), 0.3, 3.0)
		var at := face + into * (deep - 3.0 + float(bmax[2]) * sc)
		var base := k.on_ground(at.x, at.y, -1.0)
		# its top some metres over the crown's, whatever the rise behind
		sc = clampf((g + open_h + 10.0 + 6.0 - base.y) / maxf(float(bd.get("height", 16.0)), 0.5), 0.3, 3.0)
		await k.step()
		k.place(over, base, PoiKit.yaw_of(-into), sc, true, Vector3.ZERO, true)
	# the choristers: two of the Choir's own, headless, eleven and a half metres of carved stone each on
	# a stepped plinth out in the forecourt before the pilasters, the doorway's guards
	var figures := m.begin()
	var plinths := m.begin()
	var fig_yaw := PoiKit.yaw_of(-into)
	for s in [-1.0, 1.0]:
		var p := face - into * 7.0 + across * (open_w * 0.5 + 4.0) * float(s)
		var pg := k.on_ground(p.x, p.y).y
		var lo := pg
		for c: Vector2 in [Vector2(-3.2, -3.2), Vector2(3.2, -3.2), Vector2(-3.2, 3.2), Vector2(3.2, 3.2)]:
			var q := p + across * c.x + into * c.y
			lo = minf(lo, k.on_ground(q.x, q.y).y)
		var top := pg + 1.7
		var t1 := Transform3D(b, Vector3(p.x, (lo - 0.3 + pg + 0.8) * 0.5, p.y))
		_box(plinths, t1, Vector3(6.4, pg + 0.8 - (lo - 0.3), 6.4))
		var t2 := Transform3D(b, Vector3(p.x, pg + 1.25, p.y))
		_box(plinths, t2, Vector3(5.7, 0.9, 5.7))
		k.collider(Vector3(6.4, top - lo + 0.3, 6.4), Transform3D(b, Vector3(p.x, (top + lo - 0.3) * 0.5, p.y)), "stone")
		_chorister(d, figures, Vector3(p.x, top, p.y), fig_yaw, 11.5, false)
		k.collider(Vector3(4.6, 11.0, 4.6), Transform3D(b, Vector3(p.x, top + 5.5, p.y)), "stone")
	await k.step()
	m.commit(plinths, carved, "ChoristerPlinths", true)
	# carved whole, not coursed: a statue of blocks read as a brick chimney
	m.commit(figures, PoiKit.painted(0, CHORISTER_STONE, 0.35, 0.75), "Choristers", true)
	# black glass run down the rock from the crack over the crown
	var glass := m.begin()
	for i in 14:
		var x := k.rng.randf_range(-7.0, 7.0)
		var y := g + open_h + k.rng.randf_range(7.0, 13.0)
		var run := k.rng.randf_range(4.0, 10.0)
		# on the rock: as far in as the cliff stands that high
		var t := foot - 1.0
		while t < foot + 30.0:
			var q := into * t + across * x
			if k.on_ground(q.x, q.y).y >= y:
				break
			t += 0.5
		# only where the rock is near enough to run on: no further in than the facade goes
		if t > foot + 4.0:
			continue
		var at := into * (t - 0.3) + across * x
		m.ellipsoid(glass, Vector3(at.x, y, at.y), Vector3(k.rng.randf_range(0.4, 1.1), run * 0.5, 0.35), b * Basis(Vector3.RIGHT, -0.5))
	await k.step()
	m.commit(glass, PoiKit.plain(PoiKit.GLASS, 0.06, 0.3), "WeptGlass", true)
	if k.far:
		return
	# the fallen doors across the forecourt, one broken in two
	var doors := m.begin()
	for s in [-1.0, 1.0]:
		var p := face - into * (5.5 + 1.0 * float(s)) + across * 2.0 * float(s)
		var tilt := Basis(Vector3.UP, PoiKit.yaw_of(-into) + 0.12 * float(s)) * Basis(Vector3.RIGHT, PI * 0.5 - 0.06 * float(s))
		if s < 0.0:
			_box(doors, Transform3D(tilt, k.on_ground(p.x, p.y, 0.45)), Vector3(3.1, 10.5, 0.9))
			k.collider(Vector3(3.1, 0.9, 10.5), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(-into) - 0.12), k.on_ground(p.x, p.y, 0.45)), "stone")
		else:
			for h in [-1.0, 1.0]:
				var q := p - into * 2.8 * float(h) + across * 0.4 * float(h)
				var t2 := Basis(Vector3.UP, PoiKit.yaw_of(-into) + 0.12 + 0.2 * float(h)) * Basis(Vector3.RIGHT, PI * 0.5 + 0.1 * float(h))
				_box(doors, Transform3D(t2, k.on_ground(q.x, q.y, 0.45)), Vector3(3.1, 5.0, 0.9))
				k.collider(Vector3(3.1, 0.9, 5.0), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(-into) + 0.12 + 0.2 * float(h)), k.on_ground(q.x, q.y, 0.45)), "stone")
	# the forecourt's paving, broken
	for i in 16:
		var p := face - into * k.rng.randf_range(1.0, 13.0) + across * k.rng.randf_range(-6.0, 6.0)
		_box(doors, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(into) + k.rng.randf_range(-0.15, 0.15)), k.on_ground(p.x, p.y, 0.03)),
				Vector3(k.rng.randf_range(1.4, 2.4), 0.14, k.rng.randf_range(1.4, 2.4)))
	await k.step()
	m.commit(doors, k.surface("oroth", 0.45), "FallenDoors")
	# the way in, at the back of the throat's lit part
	var interior := str(site.get("interior", ""))
	var door_at := face + into * (throat - 2.2)
	PoiDressing.kind_builders().SITES._door(d, interior, Vector3(door_at.x, g + 0.05, door_at.y), PoiKit.yaw_of(-into))
	k.marker("the_mouth", Vector3(door_at.x, g + 0.05, door_at.y))
	k.light(Vector3(door_at.x, g + 2.5, door_at.y) - Vector3(into.x, 0.0, into.y) * 1.0, NOTE_BLUE, 2.2, 14.0)
	k.puffs(Vector3(door_at.x, g + 1.5, door_at.y) - Vector3(into.x, 0.0, into.y) * 4.0, Vector3(2.5, 1.0, 2.0), 0.6, 10,
			Color(0.62, 0.7, 0.8, 0.22), 2.6, 7.0)
	# the Order's braziers either side of the forecourt, burning the cold blue the Seat burns
	for s in [-1.0, 1.0]:
		var p := face - into * 13.0 + across * 4.6 * float(s)
		await k.step()
		k.place(k.prop("brazier"), k.on_ground(p.x, p.y), 0.0)
		k.light(k.on_ground(p.x, p.y, 1.4), NOTE_BLUE, 1.6, 9.0)
	k.marker("the_forecourt", k.on_ground(face.x - into.x * 6.0, face.y - into.y * 6.0))
	# the Sayer's camp, off to the side out of the doors' way
	var camp := face - into * 17.0 + across * 11.0
	if not _off_road(k, camp, 2.0):
		camp = face - into * 17.0 - across * 11.0
	await k.step()
	k.place(k.prop("tent"), k.on_ground(camp.x, camp.y), PoiKit.yaw_of(-across))
	var fire := camp - across * 3.0 - into * 1.5
	await k.step()
	k.place(k.prop("campfire"), k.on_ground(fire.x, fire.y), 0.0, 0.9)
	k.light(k.on_ground(fire.x, fire.y, 0.8), Color(1.0, 0.7, 0.4), 1.8, 9.0)
	var st_at := fire + into * 1.6
	await k.step()
	k.place(k.prop("stool"), k.on_ground(st_at.x, st_at.y), PoiKit.yaw_of(into))
	k.marker("merrin_camp", k.on_ground(fire.x - across.x * 1.4, fire.y - across.y * 1.4), true)
	# her tuning-fork on its stand, a long brass fork aimed at the door
	var fork := m.begin()
	var fa := camp - across * 1.0 + into * 3.0
	var fb := k.on_ground(fa.x, fa.y)
	for i in 3:
		var a := TAU * float(i) / 3.0
		m.limb(fork, fb + Vector3(sin(a) * 0.5, 0.0, cos(a) * 0.5), fb + Vector3(0.0, 1.3, 0.0), 0.03)
	var aim := Vector3(into.x, 0.12, into.y).normalized()
	var sideway := Vector3(across.x, 0.0, across.y)
	m.limb(fork, fb + Vector3(0.0, 1.3, 0.0), fb + Vector3(0.0, 1.3, 0.0) + aim * 0.4, 0.04)
	for s in [-1.0, 1.0]:
		m.limb(fork, fb + Vector3(0.0, 1.3, 0.0) + aim * 0.4 + sideway * 0.08 * float(s), fb + Vector3(0.0, 1.3, 0.0) + aim * 1.3 + sideway * 0.08 * float(s), 0.03)
	await k.step()
	m.commit(fork, PoiKit.plain(PoiKit.BRONZE, 0.35, 0.8), "TuningFork")
	await PoiDressing.kind_builders().SITES._hook(d, site, Vector3(camp.x, 0.0, camp.y) - Vector3(across.x, 0.0, across.y) * 1.2 + Vector3(into.x, 0.0, into.y) * 1.8)
	# (between the fallen doors, and out past the choristers' plinths)
	await _rubble(d, face - into * 6.0, 4.0, 7, Vector2(0.4, 0.9))
	await _rubble(d, face - into * 16.0, 7.0, 9, Vector2(0.4, 0.9))


# --- the Founders' Delf -------------------------------------------------------------------------------

## The dead city's bell-foundry: a casting pit ringed by its spoil, and in the pit the last great bell
## the Builders poured, still in its mould -- a cope of fired clay twelve metres high cracked open
## down one side, the green bronze showing through the break -- with the founders' gantry over it,
## two A-frames of black timber and a beam across, the block and chains still hanging to the cope's
## crown. Behind it the furnace-house, squat, its two stacks going up twenty metres over the Ashgrid,
## its fire-mouth open on the dark of the galleries under the pit (the way in). Slag heaps black and
## glassy. Clemency Brazier's camp by the furnace: a Vale bell-founder come to see the last casting.
static func founders_delf(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var site: Dictionary = ContentDB.get_or_empty(d.poi_id).get("site", {})
	var road := k.road_direction(160.0)
	var out := road.normalized() if road != Vector2.ZERO else Vector2(0.0, -1.0)
	var side := Vector2(out.y, -out.x)
	var g := k.on_ground(0.0, 0.0).y
	# the casting pit's rim of spoil, open towards the road
	var pit_r := 9.0
	for i in 12:
		var a := TAU * float(i) / 12.0
		var dir := Vector2(sin(a), cos(a))
		if dir.dot(out) > 0.9:
			continue
		await _drift(d, dir * (pit_r + 1.8), k.rng.randf_range(3.0, 3.8), k.rng.randf_range(1.3, 1.9))
	# the bell, and the cope round it broken open on the road side
	var bronze := m.begin()
	var bell_r := 4.6
	var bell_h := 11.5
	var base := Vector3(0.0, g - 1.2, 0.0)
	var face_a := PoiKit.yaw_of(out)
	_lathe(bronze, Transform3D(Basis(Vector3.UP, face_a), base), _scaled(BELL, bell_r, bell_h), 26)
	await k.step()
	m.commit(bronze, _bronze(), "TheLastBell", true)
	var clay := m.begin()
	var cope := []
	for p: Vector2 in BELL:
		cope.append(Vector2(p.x * (bell_r + 0.55) + 0.25, p.y * (bell_h + 0.6)))
	# the break: a wedge of the cope gone towards the road, ragged
	_lathe_part(clay, Transform3D(Basis(Vector3.UP, face_a), base), cope, 0.75, TAU - 0.75, 22)
	# bands of iron round the cope
	for y in [0.18, 0.5, 0.78]:
		var r := _bell_r_at(float(y)) * (bell_r + 0.55) + 0.35
		_lathe_part(clay, Transform3D(Basis(Vector3.UP, face_a), base + Vector3(0.0, float(y) * (bell_h + 0.6), 0.0)),
				[Vector2(r, -0.15), Vector2(r + 0.05, 0.0), Vector2(r, 0.15)], 0.7, TAU - 0.7, 22)
	await k.step()
	m.commit(clay, PoiKit.painted(0, CLAY, 0.85, 0.7), "Cope", true)
	var hull := PackedVector3Array()
	for p: Vector2 in cope:
		for s in 10:
			var a := TAU * float(s) / 10.0
			hull.append(base + Vector3(sin(a) * p.x, p.y, cos(a) * p.x))
	var cs := ConvexPolygonShape3D.new()
	cs.points = hull
	k.collider_shape(cs, Transform3D.IDENTITY, "stone")
	# the gantry: two A-frames either side, a beam across, the block and chains to the crown
	var timber := m.begin()
	var top_y := g + bell_h + 4.5
	var tops: Array = []
	for s in [-1.0, 1.0]:
		var c := side * 11.0 * float(s)
		var apex := Vector3(c.x, top_y, c.y)
		for l in [-1.0, 1.0]:
			var f := c + out * 4.5 * float(l) + side * 1.4 * float(s)
			var fg := k.on_ground(f.x, f.y, -0.3)
			m.limb(timber, fg, apex, 0.32)
			k.collider(Vector3(0.6, 1.2, 0.6), Transform3D(Basis.IDENTITY, fg + Vector3(0.0, 0.6, 0.0)), "wood")
		# a brace across each frame
		m.limb(timber, k.on_ground(c.x + out.x * 3.0, c.y + out.y * 3.0, 5.0), k.on_ground(c.x - out.x * 3.0, c.y - out.y * 3.0, 5.0), 0.2)
		tops.append(apex)
	m.limb(timber, tops[0], tops[1], 0.38)
	m.limb(timber, (tops[0] as Vector3) - Vector3(0.0, 1.2, 0.0), (tops[1] as Vector3) - Vector3(0.0, 1.2, 0.0), 0.26)
	for t: Vector3 in tops:
		var inward := Vector3(-t.x, 0.0, -t.z).normalized()
		m.limb(timber, t - Vector3(0.0, 4.0, 0.0), t + inward * 3.5 - Vector3(0.0, 1.2, 0.0), 0.18)
	var block := Vector3(0.0, top_y - 0.8, 0.0)
	_box(timber, Transform3D(Basis.IDENTITY, block), Vector3(0.9, 1.2, 0.6))
	var iron := m.begin()
	var crown := base + Vector3(0.0, bell_h + 0.6, 0.0)
	for s in [-1.0, 1.0]:
		m.limb(iron, block + Vector3(0.2 * float(s), -0.6, 0.0), crown + Vector3(0.6 * float(s), 0.3, 0.0), 0.06)
	await k.step()
	# the chains hang from the gantry, so they are one piece with it
	_commit_parts(d, [[timber, PoiKit.painted(3, {"base": "#2b2622", "accent": "#1c1916"}, 0.8)],
			[iron, PoiKit.plain(Color(0.14, 0.12, 0.11), 0.5, 0.6)]], "Gantry", true)
	# the furnace-house behind the pit, its two stacks, its fire-mouth to the pit
	var fh := -out * 19.0
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(out))
	var fg2 := k.on_ground(fh.x, fh.y).y
	var brick := m.begin()
	_box(brick, Transform3D(fb, Vector3(fh.x, fg2 + 2.6, fh.y)), Vector3(12.0, 6.2, 7.0))
	k.collider(Vector3(12.0, 6.2, 7.0), Transform3D(fb, Vector3(fh.x, fg2 + 2.6, fh.y)), "stone")
	_box(brick, Transform3D(fb, Vector3(fh.x, fg2 + 5.9, fh.y)), Vector3(12.6, 0.5, 7.6))
	for s in [-1.0, 1.0]:
		var sc := fh + side * 3.6 * float(s) - out * 1.0
		m.drum(brick, Transform3D(Basis.IDENTITY, Vector3(sc.x, fg2 + 5.5, sc.y)), 1.25 - 0.1 * float(s), 15.5 + 2.0 * float(s), 0.03, NAN, false, 0.5)
		m.drum(brick, Transform3D(Basis.IDENTITY, Vector3(sc.x, fg2 + 20.5 + 2.0 * float(s), sc.y)), 1.45, 0.6, 0.0, NAN, false, 0.3)
		k.collider(Vector3(2.4, 16.0, 2.4), Transform3D(Basis.IDENTITY, Vector3(sc.x, fg2 + 13.0, sc.y)), "stone")
	# the fire-mouth: an arch in the furnace's front, the dark going down behind it
	var mouth := fh + out * 3.6
	_arch(d, brick, mouth, out, 2.8, 2.2, 0.8, 0.9, 0.6, 9)
	await k.step()
	m.commit(brick, PoiKit.painted(2, BRICK, 0.8), "Furnace", true)
	var dark := m.begin()
	_box(dark, Transform3D(fb, Vector3(mouth.x, fg2 + 1.5, mouth.y) - Vector3(out.x, 0.0, out.y) * 0.6), Vector3(2.8, 3.6, 0.2))
	await k.step()
	m.commit(dark, PoiKit.plain(HOLE, 1.0), "FireMouth", true)
	if k.far:
		return
	for s in [-1.0, 1.0]:
		var sc := fh + side * 3.6 * float(s) - out * 1.0
		k.puffs(Vector3(sc.x, fg2 + 22.0 + 2.0 * float(s), sc.y), Vector3(0.4, 0.2, 0.4), 2.0, 8, Color(0.42, 0.4, 0.38, 0.3), 3.0, 8.0)
	var interior := str(site.get("interior", ""))
	var door_at := mouth - out * 0.2
	PoiDressing.kind_builders().SITES._door(d, interior, Vector3(door_at.x, fg2 + 0.05, door_at.y), PoiKit.yaw_of(out))
	k.marker("the_mouth", Vector3(door_at.x, fg2 + 0.05, door_at.y) + Vector3(out.x, 0.0, out.y) * 1.5)
	k.light(Vector3(mouth.x, fg2 + 1.2, mouth.y) + Vector3(out.x, 0.0, out.y) * 0.5, Color(1.0, 0.45, 0.2), 1.6, 7.0)
	# slag heaps, black and glassy, beside the furnace
	for s in [-1.0, 1.0]:
		var p := fh + side * 10.5 * float(s) + out * 2.0
		await k.step()
		m.mound(k.on_ground(p.x, p.y, -0.2), 3.6, 2.4, PoiKit.painted(5, SLAG, 0.4, 0.7), "Slag", true, 1.2, 6, 16)
	# the founders' gear: an anvil, moulding boards, a barrow of loam, crucibles
	var gear := fh + out * 6.5 + side * 6.0
	await k.step()
	k.place(k.prop("anvil"), k.on_ground(gear.x, gear.y), PoiKit.yaw_of(out))
	await k.step()
	k.place(k.prop("wheelbarrow"), k.on_ground(gear.x + side.x * 2.0, gear.y + side.y * 2.0), PoiKit.yaw_of(side))
	# Clemency's camp, the road side of the pit
	var camp := out * 15.0 + side * 9.0
	if not _off_road(k, camp, 2.0):
		camp = out * 15.0 - side * 9.0
	await k.step()
	k.place(k.prop("tent"), k.on_ground(camp.x, camp.y), PoiKit.yaw_of(-side))
	var fire := camp - side * 3.0
	await k.step()
	k.place(k.prop("campfire"), k.on_ground(fire.x, fire.y), 0.0, 0.9)
	k.light(k.on_ground(fire.x, fire.y, 0.8), Color(1.0, 0.7, 0.4), 1.8, 9.0)
	k.marker("clemency_camp", k.on_ground(fire.x + out.x * 1.6, fire.y + out.y * 1.6), true)
	await _cache(d, k.on_ground(camp.x + out.x * 2.0, camp.y + out.y * 2.0), PoiKit.yaw_of(side), "crate", "core:loot/oroth_cache", "founders_crate")
	k.marker("the_pit", k.on_ground(out.x * 6.0, out.y * 6.0))
	k.touchable("the_bell", Vector3(out.x, 0.0, out.y) * (bell_r + 1.6) + Vector3(0.0, g + 2.0, 0.0), "Look into the break in the mould",
			"core:dialogue/founders_delf_bell", "", false)
	await PoiDressing.kind_builders().SITES._hook(d, site, Vector3(out.x, 0.0, out.y) * 13.0 - Vector3(side.x, 0.0, side.y) * 4.0)
	await _rubble(d, Vector2.ZERO, 22.0, 18, Vector2(0.4, 0.9))


static func _scaled(profile: Array, r: float, h: float) -> Array:
	var out: Array = []
	for p: Vector2 in profile:
		out.append(Vector2(p.x * r, p.y * h))
	return out


## A bell's radius (as a fraction of its mouth's) at `y` (a fraction of its height).
static func _bell_r_at(y: float) -> float:
	for i in BELL.size() - 1:
		var a: Vector2 = BELL[i]
		var b: Vector2 = BELL[i + 1]
		if y >= a.y and y <= b.y:
			return lerpf(a.x, b.x, (y - a.y) / maxf(b.y - a.y, 0.0001))
	return 0.6


# --- Chalkwatch ---------------------------------------------------------------------------------------

## The Wardens' fort on the west heath, built to hold the grey line and taken by it with its garrison
## in it: the kind's square fort (world/sites/site_exterior.gd), and over its keep the thing that is
## seen from the West Walk, a beacon-mast twice the keep's height with the Wardens' green still on
## it, rags now, and the fire-basket at its head cold. Outside the gate Warden Ysolde Penn's fire:
## the relief, thirty years late.
static func chalkwatch(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().SITES.build(d)
	var k := d.kit
	var m := d.masonry
	var site: Dictionary = ContentDB.get_or_empty(d.poi_id).get("site", {})
	var bdeg := deg_to_rad(float(site.get("gate_bearing_deg", 0.0)))
	var gate_dir := Vector2(sin(bdeg), cos(bdeg))
	var radius := float(site.get("radius", 18.0))
	var wall_h := float((site.get("profile", {}) as Dictionary).get("wall_h", 5.5))
	# the keep stands at the back of the yard (SiteExterior._keep: radius x 0.42 behind the middle)
	var kc := -gate_dir * (radius * 0.42)
	var g := k.on_ground(kc.x, kc.y).y
	var keep_top := g + wall_h + 4.5
	var timber := m.begin()
	var mast_foot := Vector3(kc.x, keep_top - 0.5, kc.y)
	var mast_top := mast_foot + Vector3(0.0, 14.0, 0.0)
	m.limb(timber, mast_foot, mast_top, 0.22)
	# the yard and its stays
	m.limb(timber, mast_top - Vector3(0.0, 2.5, 0.0) + Vector3(gate_dir.y, 0.0, -gate_dir.x) * 1.6,
			mast_top - Vector3(0.0, 2.5, 0.0) - Vector3(gate_dir.y, 0.0, -gate_dir.x) * 1.6, 0.1)
	var rags := m.begin()
	var flag_at := mast_top - Vector3(0.0, 3.4, 0.0) + Vector3(gate_dir.y, 0.0, -gate_dir.x) * 0.9
	var fb := Basis(Vector3.UP, PoiKit.yaw_of(gate_dir))
	_box(rags, Transform3D(fb * Basis(Vector3.BACK, 0.1), flag_at), Vector3(1.6, 1.4, 0.04))
	_box(rags, Transform3D(fb * Basis(Vector3.BACK, -0.25), flag_at + Vector3(0.6, -1.1, 0.0)), Vector3(0.5, 0.9, 0.03))
	var iron := m.begin()
	for i in 8:
		var a := TAU * float(i) / 8.0
		m.limb(iron, mast_top + Vector3(sin(a) * 0.4, 0.0, cos(a) * 0.4), mast_top + Vector3(sin(a) * 0.8, 1.3, cos(a) * 0.8), 0.05)
	for i in 12:
		var a0 := TAU * float(i) / 12.0
		var a1 := TAU * float(i + 1) / 12.0
		m.limb(iron, mast_top + Vector3(sin(a0) * 0.8, 1.3, cos(a0) * 0.8), mast_top + Vector3(sin(a1) * 0.8, 1.3, cos(a1) * 0.8), 0.04)
	await k.step()
	_commit_parts(d, [[timber, k.surface("timber", 0.8)], [rags, PoiKit.painted(6, {"base": "#4d5a3f", "accent": "#3c4632", "grout": "#2a3022", "unit": 0.3}, 0.9)],
			[iron, PoiKit.plain(Color(0.12, 0.11, 0.1), 0.55, 0.6)]], "BeaconMast", true)
	if k.far:
		return
	# Ysolde's fire, outside the gate and off the track to it
	var fire := gate_dir * (radius + 9.0) + Vector2(gate_dir.y, -gate_dir.x) * 7.0
	if not _off_road(k, fire, 2.0):
		fire = gate_dir * (radius + 9.0) - Vector2(gate_dir.y, -gate_dir.x) * 7.0
	await _gate_fire(d, fire, gate_dir, "ysolde_fire")
