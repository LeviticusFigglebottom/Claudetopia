class_name PoiBuilders
extends RefCounted
## One builder per kind of point of interest. Each takes the dressing (its kit, its masonry,
## its brief) and stands the place up out of the forge's assets and a little runtime masonry.
##
## A builder reads the POI's `unique_feature` as its brief: the thing the data names should be
## the thing you see. So a camp with "a stolen mill wheel as a table" gets a millstone laid on
## a barrel, and a shrine "built of lake pebbles" is a cairn rather than a standing stone.
## Everything else follows from the kind and the region's culture.

## The kinds a builder exists for. `PoiDressing.KINDS` is the whole list the design names;
## `test_pois.gd` reports the difference as still to be dressed.
const KINDS_BUILT := ["camp", "shrine", "hearth"]


static func build(d: PoiDressing) -> void:
	match d.kind:
		"camp":
			camp(d)
		"shrine":
			shrine(d)
		"hearth":
			hearth(d)
		_:
			Log.warn("PoiDressing", "%s: no builder for kind '%s'" % [d.poi_id, d.kind])


# --- camps ----------------------------------------------------------------------------------------

## A fire ring with a light and smoke, tents facing the fire, bedrolls, stores, a cart, a lantern
## on a post; who camps here decides the rest. A fire that "went out" is cold: no light, ash,
## and the cups its sitters were passing set down around it.
static func camp(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var cold := PoiKit.brief_says(d.brief, ["went out", "cold"])
	var fighters := PoiKit.brief_says(d.encounter + " " + d.brief, ["bandit", "raider", "brute", "skirmisher", "warrior", "thie"])
	var fire := k.jitter(1.2)
	var grain := k.grain()
	var timber := m.begin()

	# the fire, its ring of stones, its light and its smoke
	k.place(k.prop("campfire"), k.on_ground(fire.x, fire.y), k.rng.randf_range(0.0, TAU), 1.15)
	var stones: Array = []
	for p in k.ring(9, 0.95, fire, 0.1):
		var pp: Vector2 = p
		stones.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y), k.rng.randf_range(0.0, TAU),
				k.rng.randf_range(0.09, 0.14)))
	k.scatter(k.rock("boulder"), stones)
	if cold:
		# ash: a dark disc where the fire was, and the cup still going round
		var ash := k.surface("earth", 0.9)
		ash.set_shader_parameter("base_color", Color(0.22, 0.21, 0.2))
		ash.set_shader_parameter("accent_color", Color(0.3, 0.29, 0.28))
		m.pool(fire, 1.6, k.on_ground(fire.x, fire.y).y + 0.03, ash, "Ash", 16)
		for p in k.ring(6, 2.4, fire, 0.15):
			var pp: Vector2 = p
			k.place(k.prop("stool"), k.on_ground(pp.x, pp.y), PoiKit.yaw_of(fire - pp), 1.0)
			var cup := pp + (fire - pp).normalized() * 0.6
			k.place(k.prop("mug"), k.on_ground(cup.x, cup.y), k.rng.randf_range(0.0, TAU))
	else:
		k.light(k.on_ground(fire.x, fire.y, 0.9), Color(1.0, 0.68, 0.35), 2.8, 13.0)
		k.puffs(k.on_ground(fire.x, fire.y, 0.7), Vector3(0.15, 0.1, 0.15), 0.6, 8,
				Color(0.55, 0.55, 0.55, 0.28), 1.1, 5.0)
		for p in k.ring(3 + k.rng.randi_range(0, 2), 2.1, fire, 0.2):
			var pp: Vector2 = p
			k.place(k.prop("stool"), k.on_ground(pp.x, pp.y), PoiKit.yaw_of(fire - pp) + k.rng.randf_range(-0.3, 0.3))

	# tents on a ring, each turned to the fire, with a bedroll in its mouth
	var tents := 3 + (1 if k.rng.randf() > 0.55 else 0)
	var tent_ring := k.ring(tents, 7.6, fire, 0.14)
	var tent_spots: Array = []
	for p in tent_ring:
		var pp: Vector2 = p
		var yaw := PoiKit.yaw_of(fire - pp) + k.rng.randf_range(-0.25, 0.25)
		var scale := k.rng.randf_range(0.95, 1.12)
		k.place(k.prop("tent"), k.on_ground(pp.x, pp.y), yaw, scale, true, Vector3.ZERO, true)
		tent_spots.append(pp)
		var mouth := pp + (fire - pp).normalized() * (2.4 * scale)
		k.place(k.prop("bedroll"), k.on_ground(mouth.x, mouth.y), yaw + PI * 0.5 + k.rng.randf_range(-0.2, 0.2))

	# stores against the tents
	for i in range(tent_spots.size()):
		var t: Vector2 = tent_spots[i]
		var side := Vector2(-(fire - t).y, (fire - t).x).normalized()
		var at := t + side * k.rng.randf_range(2.6, 3.4) + (fire - t).normalized() * k.rng.randf_range(-0.5, 1.5)
		match i % 3:
			0:
				k.place(k.prop("crate"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU))
				var at2 := at + side * 0.85
				k.place(k.prop("crate"), k.on_ground(at2.x, at2.y), k.rng.randf_range(0.0, TAU), 0.9)
			1:
				k.place(k.prop("barrel"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU))
			_:
				k.place(k.prop("sack"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU))
				var at3 := at + side * 0.6
				k.place(k.prop("sack"), k.on_ground(at3.x, at3.y), k.rng.randf_range(0.0, TAU), 0.9)

	# a lantern on a post beside the fire, lit
	var lp := fire + Vector2(-grain.y, grain.x) * 3.2
	var top := m.post(timber, lp, 2.7, 0.16)
	var arm := Vector3(grain.x, 0.0, grain.y) * 0.45
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(grain)), top + arm * 0.5 - Vector3(0.0, 0.06, 0.0)),
			Vector3(0.08, 0.08, 0.9))
	var lantern := k.prop("lantern_hanging")
	if lantern == "":
		lantern = k.prop("lantern_standing")
	k.place(lantern, top + arm - Vector3(0.0, 0.55, 0.0), PoiKit.yaw_of(grain), 1.0, false)
	if not cold:
		k.light(top + arm - Vector3(0.0, 0.3, 0.0), Color(1.0, 0.8, 0.5), 1.6, 8.0)

	# a cart at the edge, on the road side, and a hitching rail
	var edge := fire - grain * 11.0 + Vector2(-grain.y, grain.x) * k.rng.randf_range(-3.0, 3.0)
	k.place(k.prop("cart"), k.on_ground(edge.x, edge.y), PoiKit.yaw_of(grain) + k.rng.randf_range(-0.3, 0.3))
	var rail := edge + Vector2(-grain.y, grain.x) * 5.5
	k.place(k.prop("fence_post_rail"), k.on_ground(rail.x, rail.y), PoiKit.yaw_of(grain) + PI * 0.5)

	# fighters keep their arms where they can reach them
	if fighters and not cold:
		for i in 3:
			var at := fire + Vector2(sin(0.9 * i + 1.1), cos(0.9 * i + 1.1)) * 3.6
			k.place(k.prop("spear"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), 1.0, false,
					Vector3(k.rng.randf_range(-0.12, 0.12), 0.0, k.rng.randf_range(-0.12, 0.12)))
		var shield_at: Vector2 = tent_spots[0] + Vector2(1.6, 0.4)
		k.place(k.prop("shield"), k.on_ground(shield_at.x, shield_at.y), k.rng.randf_range(0.0, TAU), 1.0, false,
				Vector3(-0.35, 0.0, 0.0))

	# the brief
	if PoiKit.brief_says(d.brief, ["mill wheel", "millstone"]):
		var at := fire + grain.rotated(0.8) * 4.2
		var barrel := k.place(k.prop("barrel"), k.on_ground(at.x, at.y), 0.0)
		var h := PoiKit.height_of(k.prop("barrel", 0)) if barrel != null else 0.9
		k.place(k.prop("millstone"), k.on_ground(at.x, at.y, h), k.rng.randf_range(0.0, TAU), 1.0, false)
		k.place(k.prop("mug"), k.on_ground(at.x + 0.3, at.y + 0.2, h + 0.42), 0.0, 1.0, false)
		k.place(k.prop("plate"), k.on_ground(at.x - 0.35, at.y - 0.1, h + 0.42), 0.0, 1.0, false)
	if PoiKit.brief_says(d.brief, ["kiln"]):
		var earth := k.surface("earth", 0.7)
		for p in k.ring(3, 9.5, fire, 0.1, 0.4):
			var pp: Vector2 = p
			var base := k.on_ground(pp.x, pp.y)
			m.mound(base, 2.3, 1.9, earth, "Kiln", true, 1.1, 5, 14, true)
			k.puffs(base + Vector3(0.0, 1.9, 0.0), Vector3(0.5, 0.1, 0.5), 0.9, 14, Color(0.7, 0.68, 0.64, 0.4), 1.8, 7.0)
			var logs := pp + (pp - fire).normalized() * 3.2
			k.place(k.prop("chopping_block"), k.on_ground(logs.x, logs.y), k.rng.randf_range(0.0, TAU))
	if PoiKit.brief_says(d.brief, ["chain", "wind chime"]):
		# loosened links hung to ring in the wind: small bells on a line between two posts
		var a := fire + grain.rotated(-1.2) * 5.5
		var b := a + Vector2(-grain.y, grain.x) * 4.0
		var ta := m.post(timber, a, 3.0, 0.14)
		var tb := m.post(timber, b, 3.0, 0.14)
		var line := m.begin()
		var mid := (ta + tb) * 0.5
		m.rod(line, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(b - a)) * Basis(Vector3.RIGHT, PI * 0.5), mid),
				0.012, ta.distance_to(tb))
		m.commit(line, PoiKit.plain(Color(0.35, 0.3, 0.26), 0.8), "Line")
		var bells: Array = []
		for i in 5:
			var t := (float(i) + 0.5) / 5.0
			bells.append(PoiKit.transform_at(ta.lerp(tb, t) - Vector3(0.0, 0.32 + k.rng.randf_range(0.0, 0.2), 0.0),
					k.rng.randf_range(0.0, TAU), 1.0))
		k.scatter(k.prop("bell_small"), bells)
		# a drystone windbreak on the weather side
		var wall := m.begin()
		var w0 := fire - grain.rotated(0.6) * 6.5
		var w1 := fire - grain.rotated(-0.6) * 6.5
		m.wall(wall, w0, w1, 1.3, 0.35)
		m.commit(wall, k.surface("stone"), "Windbreak", true)
	m.commit(timber, k.surface("timber"), "Timber")


# --- shrines ----------------------------------------------------------------------------------------

## A place a name is kept: the stone, its Hearthstone at the foot, candles, a small bell, the
## offerings people leave; and whatever the brief says this shrine actually is.
static func shrine(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var approach := PoiKit.yaw_of(grain) + PI       # things face the way you come in
	var centre := Vector2.ZERO
	var stone_at := centre - grain * 1.2
	var hearth_at := centre + grain * 1.6
	var brief := d.brief
	var timber := m.begin()
	var stonework := m.begin()
	var placed_hearth := false

	if PoiKit.brief_says(brief, ["hawthorn"]):
		# a stone chair with the tree grown up through its back; the stone sits in its lap
		var basis := Basis(Vector3.UP, approach)
		var g := k.on_ground(stone_at.x, stone_at.y)
		m.block(stonework, Transform3D(basis, g + Vector3(0.0, 0.28, 0.0)), Vector3(1.5, 0.56, 1.1))
		m.block(stonework, Transform3D(basis, g + basis * Vector3(0.0, 1.0, -0.55) + Vector3(0.0, 0.0, 0.0)), Vector3(1.5, 2.0, 0.42))
		for s in [-1.0, 1.0]:
			m.block(stonework, Transform3D(basis, g + basis * Vector3(float(s) * 0.66, 0.62, 0.0)), Vector3(0.22, 0.68, 1.1))
		k.collider(Vector3(1.5, 2.0, 1.2), Transform3D(basis, g + Vector3(0.0, 1.0, 0.0) + basis * Vector3(0.0, 0.0, -0.2)))
		var behind := stone_at - grain * 0.9
		k.place(k.tree("hawthorn"), k.on_ground(behind.x, behind.y), k.rng.randf_range(0.0, TAU), 1.9, true, Vector3.ZERO, true)
		var lap := stone_at + grain * 0.95
		k.hearthstone(k.on_ground(lap.x, lap.y), approach, d.poi_id, d.display_name)
		placed_hearth = true
		var pie := stone_at + grain * 0.2 + Vector2(-grain.y, grain.x) * 0.45
		k.place(k.prop("plate"), Vector3(pie.x, g.y + 0.56, pie.y), 0.0, 1.0, false)
		k.place(k.prop("loaf"), Vector3(pie.x, g.y + 0.6, pie.y), 0.3, 1.0, false)
	elif PoiKit.brief_says(brief, ["pebble", "shingle"]):
		# a cairn of lake pebbles, each a name; the stone stands out of its top
		var pebbles: Array = []
		var cairn_r := 1.7
		for i in 110:
			var u := k.rng.randf()
			var r := cairn_r * sqrt(u)
			var a := k.rng.randf_range(0.0, TAU)
			var h := 1.05 * maxf(1.0 - r / cairn_r, 0.0) * k.rng.randf_range(0.75, 1.0)
			pebbles.append(PoiKit.transform_at(k.on_ground(stone_at.x + sin(a) * r, stone_at.y + cos(a) * r, h),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.11, 0.19),
					Vector3(k.rng.randf_range(-0.5, 0.5), 0.0, k.rng.randf_range(-0.5, 0.5))))
		k.scatter(k.rock("boulder"), pebbles, false, true)
		var cyl := CylinderShape3D.new()
		cyl.radius = cairn_r * 0.9
		cyl.height = 0.9
		k.collider_shape(cyl, Transform3D(Basis.IDENTITY, k.on_ground(stone_at.x, stone_at.y, 0.45)))
		k.hearthstone(k.on_ground(stone_at.x, stone_at.y, 0.55), approach, d.poi_id, d.display_name)
		placed_hearth = true
		# the newest pebbles, not yet on the heap
		var spill: Array = []
		for i in 14:
			var a := k.rng.randf_range(0.0, TAU)
			var r := cairn_r + k.rng.randf_range(0.2, 1.6)
			spill.append(PoiKit.transform_at(k.on_ground(stone_at.x + sin(a) * r, stone_at.y + cos(a) * r),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.1, 0.16)))
		k.scatter(k.rock("boulder", 1), spill)
	elif PoiKit.brief_says(brief, ["peat island", "under the water"]):
		# a hummock of peat with the stone on top, lantern poles about it, and the old bell
		# just breaking the surface of the pool beside
		var base := k.on_ground(stone_at.x, stone_at.y)
		m.mound(base, 6.5, 1.15, k.surface("earth", 0.6), "Island", true, 1.4, 6, 18, true)
		k.hearthstone(base + Vector3(0.0, 1.12, 0.0), approach, d.poi_id, d.display_name)
		placed_hearth = true
		for p in k.ring(4, 5.2, stone_at, 0.08):
			var pp: Vector2 = p
			var top := m.post(timber, pp, 2.6, 0.14)
			k.place(k.prop("lantern_hanging"), top - Vector3(0.0, 0.5, 0.0), k.rng.randf_range(0.0, TAU), 1.0, false)
			k.light(top - Vector3(0.0, 0.3, 0.0), Color(1.0, 0.78, 0.45), 1.5, 8.0)
		var pool_at := stone_at + Vector2(-grain.y, grain.x) * 9.5
		var pg := k.on_ground(pool_at.x, pool_at.y)
		m.pool(pool_at, 4.2, pg.y + 0.12, k.still_water(pg.y - 2.5, Color.WHITE, 0.6), "Pool")
		var bell := k.prop("bell_medium")
		k.place(bell, Vector3(pool_at.x, pg.y + 0.3 - PoiKit.height_of(bell) * 2.4, pool_at.y), 0.4, 2.4, false,
				Vector3(0.12, 0.0, -0.08))
		var reeds: Array = []
		for i in 40:
			var a := k.rng.randf_range(0.0, TAU)
			var r := k.rng.randf_range(4.2, 6.5)
			reeds.append(PoiKit.transform_at(k.on_ground(pool_at.x + sin(a) * r, pool_at.y + cos(a) * r),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
		k.scatter(k.flora("reeds"), reeds, false, false, false)
	elif PoiKit.brief_says(brief, ["oil"]):
		# oiled till it shines like a chestnut
		var stone := k.place(k.rock("standing_stone"), k.on_ground(stone_at.x, stone_at.y), approach, 1.2, true, Vector3.ZERO, true)
		if stone != null:
			var oiled := PoiKit.plain(Color(0.36, 0.2, 0.11), 0.18)
			for mi in stone.find_children("*", "MeshInstance3D", true, false):
				var mesh_inst := mi as MeshInstance3D
				var src := mesh_inst.mesh.surface_get_material(0) if mesh_inst.mesh != null and mesh_inst.mesh.get_surface_count() > 0 else null
				if src is StandardMaterial3D:
					oiled.albedo_texture = (src as StandardMaterial3D).albedo_texture
					oiled.normal_enabled = (src as StandardMaterial3D).normal_enabled
					oiled.normal_texture = (src as StandardMaterial3D).normal_texture
				mesh_inst.material_override = oiled
		for i in 3:
			var at := stone_at + Vector2(-grain.y, grain.x) * (1.1 + 0.35 * i) + grain * 0.6
			k.place(k.prop("jug"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), 1.0, false)
		var rag := stone_at + Vector2(-grain.y, grain.x) * -1.2 + grain * 0.7
		k.place(k.prop("cloth"), k.on_ground(rag.x, rag.y), k.rng.randf_range(0.0, TAU), 1.0, false)
		var moss: Array = []
		for i in 26:
			var a := k.rng.randf_range(0.0, TAU)
			var r := k.rng.randf_range(1.6, 7.0)
			moss.append(PoiKit.transform_at(k.on_ground(stone_at.x + sin(a) * r, stone_at.y + cos(a) * r, 0.02),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
		k.scatter(k.flora("moss_patch"), moss, false, false, false)
	elif PoiKit.brief_says(brief, ["finger"]):
		# the sinkhole's rim: slabs leaning in; the giant's finger stands in the middle
		var slabs: Array = []
		for p in k.ring(11, 8.6, stone_at, 0.1):
			var pp: Vector2 = p
			var to_c := (stone_at - pp).normalized()
			slabs.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y, -0.4), PoiKit.yaw_of(to_c),
					k.rng.randf_range(0.8, 1.15), Vector3(k.rng.randf_range(0.25, 0.4), 0.0, k.rng.randf_range(-0.1, 0.1))))
		k.scatter(k.rock("cliff_slab"), slabs, true, true)
		var finger := k.rock("bone_finger")
		var fh := PoiKit.height_of(finger)
		var fs := 2.6
		k.place(finger, k.on_ground(stone_at.x, stone_at.y, 0.42 * fs), approach, fs, true, Vector3(0.0, 0.0, PI * 0.5), true)
		var cyl := CylinderShape3D.new()
		cyl.radius = fh * fs * 0.45
		cyl.height = 6.0 * fs
		k.collider_shape(cyl, Transform3D(Basis.IDENTITY, k.on_ground(stone_at.x, stone_at.y, 3.0 * fs)))
		var foot := stone_at + grain * (fh * fs * 0.5 + 1.2)
		k.hearthstone(k.on_ground(foot.x, foot.y), approach, d.poi_id, d.display_name)
		placed_hearth = true
		var crust: Array = []
		for i in 30:
			var a := k.rng.randf_range(0.0, TAU)
			var r := k.rng.randf_range(2.0, 7.5)
			crust.append(PoiKit.transform_at(k.on_ground(stone_at.x + sin(a) * r, stone_at.y + cos(a) * r, 0.02),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.4)))
		k.scatter(k.flora("lichen_crust"), crust, false, false, false)
	elif PoiKit.brief_says(brief, ["fallen bell", "inside a", "crack in its side"]):
		# a bell the size of a house on its side, its mouth to the approach; the stone inside
		var bell := k.prop("bell_medium")
		var bs := 6.0
		var br := PoiKit.radius_of(bell) * bs
		var bh := PoiKit.height_of(bell) * bs
		# the bell lies along the grain with its mouth toward the approach: the standing bell's
		# up (mouth to crown) is turned onto local +Z, and local +Z faces away from the approach
		var mouth := centre + grain * (bh * 0.5)
		var g := k.on_ground(centre.x, centre.y)
		var axis := Basis(Vector3.UP, approach)
		var basis := axis * Basis(Vector3.RIGHT, PI * 0.5)
		var bell_node := k.place(bell, Vector3(mouth.x, g.y + br, mouth.y), 0.0, bs, false, Vector3.ZERO, true)
		if bell_node != null:
			bell_node.transform = Transform3D(basis.scaled(Vector3.ONE * bs), Vector3(mouth.x, g.y + br, mouth.y))
		# its shell as a ring of slabs around that axis, open at the bottom where it rests on
		# the ground, so you can walk in through the mouth and stand inside
		var segs := 12
		var middle := g + Vector3(0.0, br, 0.0)
		for i in segs:
			var a := TAU * (float(i) + 0.5) / float(segs)
			if absf(angle_difference(a, PI)) < 0.5:
				continue
			var around := axis * Basis(Vector3.BACK, a)
			var at := middle + around * Vector3(0.0, br * 0.92, 0.0)
			k.collider(Vector3(br * TAU / float(segs) * 1.05, 0.5, bh * 0.9), Transform3D(around, at))
		var inside := centre - grain * (bh * 0.1)
		k.hearthstone(k.on_ground(inside.x, inside.y), approach, d.poi_id, d.display_name)
		placed_hearth = true
		for s in [-1.0, 1.0]:
			var bz := mouth + grain * 0.8 + Vector2(-grain.y, grain.x) * float(s) * (br + 0.8)
			k.place(k.prop("brazier"), k.on_ground(bz.x, bz.y), 0.0)
			k.light(k.on_ground(bz.x, bz.y, 1.1), Color(1.0, 0.62, 0.3), 2.0, 9.0)
		var bench := mouth + grain * 3.4
		k.place(k.prop("bench"), k.on_ground(bench.x, bench.y), approach + PI)
	else:
		k.place(k.rock("standing_stone"), k.on_ground(stone_at.x, stone_at.y), approach, 1.25, true,
				Vector3(0.0, 0.0, k.rng.randf_range(-0.05, 0.05)), true)

	if not placed_hearth:
		k.hearthstone(k.on_ground(hearth_at.x, hearth_at.y), approach, d.poi_id, d.display_name)

	# candles, a bell, offerings and flowers: what tending looks like
	var candles: Array = []
	for i in 10 + k.rng.randi_range(0, 8):
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(0.9, 2.2)
		var at := hearth_at + Vector2(sin(a), cos(a)) * r
		candles.append(PoiKit.transform_at(k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.6)))
	k.scatter(k.prop("candle"), candles, false, false, false)
	k.light(k.on_ground(hearth_at.x, hearth_at.y, 0.5), Color(1.0, 0.76, 0.5), 1.1, 6.0)
	if not PoiKit.brief_says(brief, ["bell"]):
		var frame_at := stone_at + Vector2(-grain.y, grain.x) * 2.6
		var hang := m.frame(timber, frame_at, approach, 0.9, 2.1, 0.12)
		k.place(k.prop("bell_small"), hang - Vector3(0.0, 0.3, 0.0), approach, 1.0, false)
	var gifts := ["mug", "jug", "plate", "book", "loaf", "candlestick"]
	for i in 5:
		var a := approach + k.rng.randf_range(-1.1, 1.1)
		var at := hearth_at + Vector2(sin(a), cos(a)) * k.rng.randf_range(0.9, 1.5)
		k.place(k.prop(gifts[i % gifts.size()]), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), 1.0, false)
	var flower := k.flora("poppy")
	match k.region:
		"skerrow":
			flower = k.flora("heather")
		"sedgemire":
			flower = k.flora("marsh_marigold")
		"briarwold":
			flower = k.flora("foxglove")
		"cinderlea":
			flower = k.flora("grey_grass")
	var flowers: Array = []
	for i in 24:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(2.2, 5.5)
		var at := centre + Vector2(sin(a), cos(a)) * r
		flowers.append(PoiKit.transform_at(k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.3)))
	k.scatter(flower, flowers, false, false, false)
	if k.culture == "vale":
		for p in k.ring(3, 4.6, stone_at, 0.2, approach + 2.2):
			var pp: Vector2 = p
			k.place(k.prop("gravestone"), k.on_ground(pp.x, pp.y), PoiKit.yaw_of(stone_at - pp) + k.rng.randf_range(-0.3, 0.3),
					1.0, true, Vector3(k.rng.randf_range(-0.08, 0.08), 0.0, k.rng.randf_range(-0.1, 0.1)))
	m.commit(stonework, k.surface("stone", 0.6), "Stonework", true)
	m.commit(timber, k.surface("timber"), "Timber")


# --- the Hearthstone a settlement keeps ---------------------------------------------------------------

## A place tagged `shrine` keeps a Hearthstone: on its green, a little off the middle so nothing
## else that stands at the centre (a landmark, a spawning body) stands inside it, with the
## candles and the bench that say it is tended. Its id is the place's, which is what the main
## quest's `rest_at` objectives name.
static func hearth(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var approach := PoiKit.yaw_of(grain) + PI
	var off := maxf(7.0, _landmark_clearance(d) + 4.0)
	var at := grain.rotated(0.9) * off
	var stone := at - grain * 0.9
	k.place(k.rock("standing_stone"), k.on_ground(stone.x, stone.y), approach, 0.9, true, Vector3.ZERO, true)
	k.hearthstone(k.on_ground(at.x, at.y), approach, d.poi_id, d.display_name)
	var candles: Array = []
	for i in 8:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(0.8, 1.6)
		var c := at + Vector2(sin(a), cos(a)) * r
		candles.append(PoiKit.transform_at(k.on_ground(c.x, c.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.prop("candle"), candles, false, false, false)
	k.light(k.on_ground(at.x, at.y, 0.5), Color(1.0, 0.76, 0.5), 1.0, 5.0)
	var bench := at + grain * 2.6
	k.place(k.prop("bench"), k.on_ground(bench.x, bench.y), approach + PI)
	var timber := m.begin()
	var hang := m.frame(timber, at + Vector2(-grain.y, grain.x) * 2.2, approach, 0.9, 2.1, 0.12)
	k.place(k.prop("bell_small"), hang - Vector3(0.0, 0.3, 0.0), approach, 1.0, false)
	m.commit(timber, k.surface("timber"), "Timber")


## How far a landmark standing on this place's centre reaches, from the forge's own meta,
## so the stone is set beyond the Grandfather's trunk rather than inside it.
static func _landmark_clearance(d: PoiDressing) -> float:
	var world := World.instance
	if world == null:
		return 0.0
	var reach := 0.0
	for entry_v in world.pois():
		var entry: Dictionary = entry_v
		if not entry.has("scene"):
			continue
		var p: Array = entry.get("pos", [0, 0, 0])
		var at := Vector3(float(p[0]), float(p[1]), float(p[2]))
		if at.distance_to(d.world_position) > 6.0:
			continue
		reach = maxf(reach, PoiKit.radius_of(str(entry["scene"])))
	return reach
