extends RefCounted
## Briarwold's own place builders (docs/WORLD_LIFE.md). A POI def with `"builder": "<name>"` is built
## by the static function of that name here, in place of its kind's builder. Only the Briarwold
## region's author edits this file, so six regions can build at once without meeting.
##
##   static func drovers_hall(d: PoiDressing) -> void:
##       await PoiDressing.kind_builders().LAND.farmstead(d)    # its kind's, then more
##       var k := d.kit                                          # PoiKit: on_ground, prop, masonry ...
##
## The kind stays the def's `kind` (what the tests, the map and the audit call it); a builder named
## here that is missing is said in the log and the place is built as its kind.

## Brass gone brown in the Northwold's rain, still bright where hands have held it.
const BRASS := Color(0.50, 0.38, 0.19)
## The grey of cold ash that the Greyed Ring's leaves, bark and moss have all gone.
const ASH_GREY := Color(0.47, 0.47, 0.46)


# --- the Listening Horns ------------------------------------------------------------------------

## The Circle's Listeners' cold camp (camp, "cold") and, on its far side from the road, their three
## brass listening-horns as tall as a man, each on a tripod, all three turned on the Briar's
## northern gate: the one thing in the camp that is not the camp builder's, and the thing the place
## is named for. Legs and horns are one mesh, so from every side it stands on its own feet.
static func listening_horns(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().camp(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	# the northern gate, from the def's own position: the horns listen at it
	var def := ContentDB.get_or_empty(d.poi_id)
	var here: Array = def.get("position", [0, 0])
	var gate := ContentDB.get_or_empty("core:poi/northgate_stone").get("position", [float(here[0]) + 400.0, float(here[1])]) as Array
	var east := Vector2(float(gate[0]) - float(here[0]), float(gate[1]) - float(here[1]))
	east = east.normalized() if east.length() > 1.0 else Vector2(1.0, 0.0)
	var across := Vector2(-east.y, east.x)
	var brass := m.begin()
	var spots: Array = []
	for i in 3:
		# in a shallow arc across the camp's east side, the middle horn a little further out
		var c := east * (7.2 + (0.8 if i == 1 else 0.0)) + across * (float(i) - 1.0) * 3.4
		spots.append(c)
		var ground := k.on_ground(c.x, c.y).y
		var apex := Vector3(c.x, ground + 1.55, c.y)
		# the tripod: three legs from a little into the ground to the apex
		for leg in 3:
			var a := TAU * float(leg) / 3.0 + k.rng.randf_range(-0.2, 0.2) + PoiKit.yaw_of(east)
			var foot := Vector2(c.x + sin(a) * 0.75, c.y + cos(a) * 0.75)
			m.limb(brass, k.on_ground(foot.x, foot.y, -0.06), apex, 0.035)
		# the horn: a throat at the back, flaring to a bell toward the gate, tipped a little up
		var aim := Vector3(east.x, 0.12, east.y).normalized()
		var back := apex - aim * 0.9 + Vector3.UP * 0.12
		var steps := 6
		for s in steps:
			var t0 := float(s) / float(steps)
			var t1 := float(s + 1) / float(steps)
			var r := lerpf(0.05, 0.30, pow(t1, 1.8))
			m.limb(brass, back + aim * (2.1 * t0), back + aim * (2.1 * t1), r)
		# the bell's lip: a flattened ring of balls round the mouth
		var mouth := back + aim * 2.1
		var basis := Basis.looking_at(aim, Vector3.UP)
		for j in 12:
			var b := TAU * float(j) / 12.0
			var off := basis * Vector3(cos(b) * 0.42, sin(b) * 0.42, 0.0)
			m.ellipsoid(brass, mouth + off, Vector3(0.07, 0.07, 0.05), basis)
		# the ear-piece at the back, where Merel Quill puts her ear
		m.ellipsoid(brass, back - aim * 0.05, Vector3(0.09, 0.09, 0.09))
		await k.step()
	m.commit(brass, PoiKit.plain(BRASS, 0.42, 0.75), "ListeningHorns")
	for c in spots:
		var sc: Vector2 = c
		var at := k.on_ground(sc.x, sc.y)
		k.collider(Vector3(1.2, 1.9, 1.2), Transform3D(Basis(), at + Vector3.UP * 0.95), "metal")
	# where Merel Quill stands with her ear to the brass, and where the porter sits
	var mid: Vector2 = spots[1]
	var stand := mid - east * 1.9
	k.marker("the_horns", k.on_ground(stand.x, stand.y), true)
	k.marker("the_east_horn", k.on_ground(mid.x, mid.y), false)


# --- the Greyed Ring --------------------------------------------------------------------------------

## The ring of sallows rooted again (strange_tree, "ring") and the grey that has come up under it:
## the moss and the leaf-litter inside the ring gone the grey of cold ash in patches that stop at its
## edge, and a few withies standing dead-grey among them, still upright, that do not bleed when cut.
static func greyed_ring(d: PoiDressing) -> void:
	await PoiDressing.kind_builders().strange_tree(d)
	var k := d.kit
	if k.far:
		return
	var m := d.masonry
	var litter := m.begin()
	var reach := minf(d.pad_radius * 0.55, 13.0)
	var patches := 26
	for i in patches:
		# denser toward the middle, and none past the ring's edge
		var a := k.rng.randf_range(0.0, TAU)
		var r := reach * sqrt(k.rng.randf_range(0.0, 1.0))
		var c := Vector2(sin(a) * r, cos(a) * r)
		var size := k.rng.randf_range(0.7, 1.3)
		# tilted to the ground under it, so it lies on the slope rather than cutting into it
		var hx := k.on_ground(c.x + size, c.y).y - k.on_ground(c.x - size, c.y).y
		var hz := k.on_ground(c.x, c.y + size).y - k.on_ground(c.x, c.y - size).y
		var normal := Vector3(-hx / (2.0 * size), 1.0, -hz / (2.0 * size)).normalized()
		var x := normal.cross(Vector3.BACK).normalized()
		var basis := Basis(x, normal, x.cross(normal).normalized()) * Basis(Vector3.UP, k.rng.randf() * TAU)
		m.ellipsoid(litter, k.on_ground(c.x, c.y, 0.025), Vector3(size, 0.04, size * k.rng.randf_range(0.6, 1.0)), basis)
	await k.step()
	m.commit(litter, PoiKit.plain(ASH_GREY.darkened(0.08), 0.95, 0.0), "GreyMoss")
	# the dead-grey withies: straight rods from the ground, a hand into it, a few crooked
	var withies := m.begin()
	for i in 14:
		var a := k.rng.randf_range(0.0, TAU)
		var r := reach * k.rng.randf_range(0.25, 0.9)
		var foot := Vector2(sin(a) * r, cos(a) * r)
		var base := k.on_ground(foot.x, foot.y, -0.12)
		var lean := Vector3(k.rng.randf_range(-0.1, 0.1), 1.0, k.rng.randf_range(-0.1, 0.1)).normalized()
		var tip := base + lean * k.rng.randf_range(1.4, 2.6)
		m.limb(withies, base, tip, k.rng.randf_range(0.018, 0.03))
	await k.step()
	m.commit(withies, PoiKit.plain(ASH_GREY, 0.9, 0.0), "GreyWithies")
	k.marker("the_grey_ring", k.on_ground(0.0, 0.0), false)
