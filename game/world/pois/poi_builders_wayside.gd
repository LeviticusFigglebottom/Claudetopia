extends RefCounted
## The small things by a road that make the walk between two places worth taking: the finds the
## cartographer's gap map asks for where a road runs a minute and more past nothing (a cairn, a
## tally post, a grave, a gibbet, a fold, a well, a lantern post, a cart gone over in the verge,
## a hut, a crossroads, a peat cut and a beacon). Each is a wayside place, and the world gives a wayside place a pad of 14 m on a dale
## side of 25 to 45 degrees. So everything here stands within PAD_M of the centre, and whatever
## stands on the ground has its foot in the slope on its low side, never on air.
##
## Each is built in its region's way (WORLD_BIBLE section 6): a Skerrow grave under bone lintels
## and a Cinderlea grave under a bell on a stake are told apart at thirty metres. The pieces are
## the forge's props and rock and the POI kit's masonry; nothing here is drawn in the far ring,
## since none of it is big enough to be seen from there.
##
## **No `class_name`**, for the reason `poi_builders.gd` has none. `poi_builders.gd` preloads this.

const LAND := preload("res://world/pois/poi_builders_land.gd")

## How far from the centre anything stands: half the 14 m pad, less a margin.
const PAD_M := 6.5
const ROPE := Color(0.44, 0.36, 0.26)
const BONE := Color(0.84, 0.8, 0.7)
const IRON := Color(0.14, 0.13, 0.13)
## The marsh's own dye (WORLD_BIBLE 6.3: "the only indigo").
const INDIGO := Color(0.14, 0.19, 0.44)
## The ash pilgrims' faded gilding.
const ASH_GOLD := Color(0.64, 0.53, 0.3)
const LIME := Color(0.93, 0.92, 0.87)
const LANTERN := Color(1.0, 0.7, 0.36)


# --- shared hands --------------------------------------------------------------------------------

## Where the road is from here: `to_road` points from the centre toward the nearest road (or
## downhill, where no road is near: a path runs along a slope's foot), `along` runs with it.
static func _road(d: PoiDressing) -> Dictionary:
	var k := d.kit
	var along := k.road_direction(60.0)
	if along == Vector2.ZERO:
		along = k.grain()
	var to_road := LAND._toward_line(d)
	if to_road == Vector2.ZERO:
		var down := k.downhill()
		to_road = down if down != Vector2.ZERO else Vector2(-along.y, along.x)
	return {"to_road": to_road, "along": along}


## The lowest ground within `r` of local `c`, as a local height: what a thing standing there has
## to reach down to so that none of its foot is in the air.
static func _low(k: PoiKit, c: Vector2, r: float) -> float:
	var low := k.on_ground(c.x, c.y).y
	for i in 8:
		var a := TAU * float(i) / 8.0
		low = minf(low, k.on_ground(c.x + sin(a) * r, c.y + cos(a) * r).y)
	return low


## A heap of the region's stones, `height` high and `r` across its foot, draped over the slope: the
## foot's stones each on their own ground, the top at the centre's ground plus `height`, each stone
## between on the cone joining them. Returns the top (local). One body for the whole heap.
static func _heap(d: PoiDressing, c: Vector2, height: float, r: float, path: String, node_name := "Heap") -> float:
	var k := d.kit
	var base := k.on_ground(c.x, c.y).y
	var top := base + height
	if path == "":
		return top
	var bh := maxf(PoiKit.height_of(path), 0.3)
	var tiers := maxi(5, int(height / 0.22))
	var stones: Array = []
	for t in tiers:
		var f := float(t) / float(tiers)
		var rr := r * (1.0 - f) + 0.08
		var n := maxi(1, int(round(8.0 * (1.0 - f) * r)))
		for i in n:
			var a := TAU * float(i) / float(n) + k.rng.randf_range(-0.3, 0.3) + float(t) * 0.9
			var p := c + Vector2(sin(a), cos(a)) * rr * k.rng.randf_range(0.7, 1.0)
			var reach := clampf(p.distance_to(c) / (r + 0.08), 0.0, 1.0)
			var y := lerpf(top - 0.12, k.on_ground(p.x, p.y).y + 0.08, reach)
			var size := k.rng.randf_range(0.34, 0.5) * (1.0 - f * 0.45)
			stones.append(PoiKit.transform_at(Vector3(p.x, y - size * 0.3, p.y), k.rng.randf_range(0.0, TAU), size / bh,
					Vector3(k.rng.randf_range(-0.35, 0.35), 0.0, k.rng.randf_range(-0.35, 0.35))))
	await k.step()
	var mm := k.scatter(path, stones, false)
	if mm != null:
		mm.name = node_name
	k.collider(Vector3(r * 1.3, height, r * 1.3), Transform3D(Basis(), Vector3(c.x, base + height * 0.5 - 0.2, c.y)), "stone")
	return top


## Loose stones in the grass round `c`, out to `r`: what fell off a heap or a wall.
static func _strew(d: PoiDressing, c: Vector2, r: float, count: int, path: String) -> void:
	var k := d.kit
	if path == "":
		return
	var bh := maxf(PoiKit.height_of(path), 0.3)
	var out: Array = []
	for i in count:
		var a := k.rng.randf_range(0.0, TAU)
		var p := c + Vector2(sin(a), cos(a)) * k.rng.randf_range(r * 0.4, r)
		var size := k.rng.randf_range(0.18, 0.34)
		out.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -size * 0.35), k.rng.randf_range(0.0, TAU), size / bh,
				Vector3(k.rng.randf_range(-0.4, 0.4), 0.0, k.rng.randf_range(-0.4, 0.4))))
	await k.step()
	k.scatter(path, out, false, false, false)


## What grows round a wayside thing in this region: heather on the fells, grey grass on the ash,
## sedge in the marsh, fern in the wood, the Vale's clumps elsewhere.
static func _verge(k: PoiKit) -> String:
	match k.region:
		"skerrow":
			return "heather"
		"cinderlea":
			return "grey_grass"
		"sedgemire":
			return "sedge_tussock"
		"briarwold":
			return "fern"
	return "grass_clump"


## A post of timber from the ground at `at`, `height` tall, its foot sunk to the lowest ground under
## it; `lean` tips it. Into `st`, with a body. Returns its top (local).
static func _post(d: PoiDressing, st: SurfaceTool, at: Vector2, height: float, side: float, lean := Vector3.ZERO) -> Vector3:
	var k := d.kit
	var foot := Vector3(at.x, _low(k, at, side) - 0.25, at.y)
	var b := Basis.from_euler(lean)
	var xf := Transform3D(b, foot + b * Vector3(0.0, (height + 0.25) * 0.5, 0.0))
	d.masonry.block(st, xf, Vector3(side, height + 0.25, side))
	k.collider(Vector3(side, height + 0.25, side), xf, "wood")
	return foot + b * Vector3(0.0, height + 0.25, 0.0)


## Cords hanging from `points` (local), each `lengths[i]` long, knotted, with something tied at
## the end, gathered under a `Turning` that swings them to and fro in the wind while somebody is
## near. `token` is the colour of what is tied on. Returns the node.
static func _cords(d: PoiDressing, node_name: String, pivot: Vector3, points: Array, lengths: Array, token: Color,
		cord := ROPE, token_size := Vector3(0.07, 0.09, 0.04)) -> Node3D:
	var k := d.kit
	var m := d.masonry
	var swing := Turning.new()
	swing.name = node_name
	swing.position = pivot
	swing.axis = Vector3(LAND.WIND.y, 0.0, -LAND.WIND.x)
	swing.swing = 0.16
	swing.rate = k.rng.randf_range(1.1, 1.6)
	swing.phase = k.rng.randf_range(0.0, TAU)
	d.add_child(swing)
	var strands := m.begin()
	var tokens := m.begin()
	for i in points.size():
		var top: Vector3 = (points[i] as Vector3) - pivot
		var length := float(lengths[i])
		m.rod(strands, Transform3D(Basis(), top - Vector3(0.0, length * 0.5, 0.0)), 0.012, length)
		# the knots down it, one for each thing it counts
		var knots := 1 + k.rng.randi_range(0, 3)
		for j in knots:
			var y := length * (0.25 + 0.6 * float(j) / float(maxi(knots, 1)))
			await k.step()
			m.ellipsoid(strands, top - Vector3(0.0, y, 0.0), Vector3(0.028, 0.035, 0.028))
		var end := top - Vector3(0.0, length + token_size.y * 0.5, 0.0)
		m.block(tokens, Transform3D(Basis(Vector3.UP, k.rng.randf_range(0.0, TAU)) * Basis(Vector3.BACK, k.rng.randf_range(-0.3, 0.3)), end),
				token_size * k.rng.randf_range(0.8, 1.3))
	for pair in [[strands, PoiKit.plain(cord, 0.95), "Cords"], [tokens, PoiKit.plain(token, 0.8), "Tokens"]]:
		await k.step()
		var mi := m.commit(pair[0], pair[1], str(pair[2]))
		if mi != null:
			mi.get_parent().remove_child(mi)
			swing.add_child(mi)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return swing


# --- a cairn -------------------------------------------------------------------------------------

## A heap of stones about a man high a pace off the track, each stone put there by somebody
## passing: a grave, a boundary or a debt. The stones are the region's own (the Vale's chalk, the
## fells' limestone, the ash's black), and what is left on top is the region's: a slab set on end
## and a giant's knucklebone on the fells, a wand of white ash with a pilgrim's strip of faded gold
## on the pilgrims' way, a round white stone and a posy on the downs.
static func cairn(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		# too small to be seen from the far ring
		return
	var m := d.masonry
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	var across := Vector2(-to_road.y, to_road.x)
	var yaw := PoiKit.yaw_of(to_road)
	var at := Vector2.ZERO
	var stone := k.rock("boulder")
	var top := await _heap(d, at, k.rng.randf_range(1.7, 1.95), 1.1, stone, "Cairn")
	d.set_meta("cairn_top", top)
	var crown := Vector3(at.x, top, at.y)
	match k.region:
		"skerrow":
			# a slab of the fell's limestone stood on end in the top, and a giant's knucklebone at its
			# foot on the track side: the clans' mark
			var cap := m.begin()
			m.block(cap, Transform3D(Basis(Vector3.UP, yaw + 0.3) * Basis(Vector3.BACK, 0.06), crown + Vector3(0.0, 0.32, 0.0)),
					Vector3(0.46, 0.78, 0.13))
			await k.step()
			m.commit(cap, k.surface("stone", 0.7), "Capstone")
			var bone := k.rock("bone_vertebra")
			if bone != "":
				var p := at + to_road * 1.35 + across * 0.4
				await k.step()
				k.place(bone, k.on_ground(p.x, p.y, -0.12), yaw + 1.1, 0.62 / maxf(PoiKit.height_of(bone), 0.5), false,
						Vector3(0.25, 0.0, 0.15))
		"cinderlea":
			# a wand of white ash in the top with a strip of faded gold on it, and the stubs of the
			# candles the pilgrims burned at its foot
			var wand := m.begin()
			m.rod(wand, Transform3D(Basis(Vector3.BACK, 0.12), crown + Vector3(0.0, 0.45, 0.0)), 0.025, 1.3)
			await k.step()
			m.commit(wand, PoiKit.plain(Color(0.86, 0.85, 0.8), 0.9), "Wand")
			await _cords(d, "Strip", crown + Vector3(0.07, 1.05, 0.0), [crown + Vector3(0.07, 1.05, 0.0)], [0.02],
					ASH_GOLD, ASH_GOLD, Vector3(0.07, 0.55, 0.012))
			var stub := k.prop("candle_stub")
			if stub != "":
				var stubs: Array = []
				for i in 5:
					var p := at + to_road * k.rng.randf_range(1.2, 1.5) + across * k.rng.randf_range(-0.8, 0.8)
					stubs.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.6))
				await k.step()
				k.scatter(stub, stubs, false, false, false)
		_:
			# a round white stone on top that somebody carried up from the stream, and flowers at the foot
			var cap := m.begin()
			await k.step()
			m.ellipsoid(cap, crown + Vector3(0.0, 0.14, 0.0), Vector3(0.22, 0.17, 0.2))
			await k.step()
			m.commit(cap, PoiKit.plain(Color(0.9, 0.89, 0.84), 0.85), "Capstone")
			await LAND._grass(d, "cow_parsley" if k.region != "briarwold" else "foxglove", at + to_road * 1.4, 0.9, 6)
	# what the sentence says it is for
	if PoiKit.brief_says(d.brief, ["grave", "buried", "lies here"]):
		# a slab at its head, on the side away from the track
		var head := at - to_road * 1.45
		var slab := m.begin()
		var g := _low(k, head, 0.3)
		m.block(slab, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.08), Vector3(head.x, g + 0.35, head.y)),
				Vector3(0.55, 1.1, 0.14))
		await k.step()
		m.commit(slab, k.surface("stone", 0.8), "HeadSlab")
	if PoiKit.brief_says(d.brief, ["debt", "owed", "blood"]):
		var side := Vector3(across.x, 0.0, across.y) * 0.2
		await _cords(d, "Debt", crown + Vector3(0.0, 0.1, 0.0), [crown + side, crown - side],
				[0.5, 0.7], BONE)
	await _strew(d, at, 2.6, 7, stone)
	await LAND._grass(d, _verge(k), at, 4.5, 22)
	k.marker("the_cairn", k.on_ground(at.x + to_road.x * 1.8, at.y + to_road.y * 1.8), true)


# --- a tally post --------------------------------------------------------------------------------

## A tall post on the fells hung with knotted cords and bone tokens: a debt or a blood-price
## recorded where it was incurred, a knot for each part of it paid, the tokens the clan's own. It
## is stepped into a socket of stones, notched down its face like a waystone, and topped with a
## giant's knucklebone. The cords stir in the wind.
static func tally_post(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		# too small to be seen from the far ring
		return
	var m := d.masonry
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	var yaw := PoiKit.yaw_of(to_road)
	var b := Basis(Vector3.UP, yaw)
	var at := Vector2.ZERO
	var height := 3.6 + k.rng.randf_range(-0.2, 0.3)
	var timber := m.begin()
	var lean := Vector3(k.rng.randf_range(-0.02, 0.02), 0.0, k.rng.randf_range(-0.02, 0.02))
	var top := _post(d, timber, at, height, 0.26, lean)
	# the yoke across the top, a little down from it, and a second, shorter one under it
	var arms: Array[Vector3] = []
	for level in [[0.35, 2.0], [1.05, 1.3]]:
		var y := top - Vector3(0.0, float(level[0]), 0.0)
		var w := float(level[1])
		m.block(timber, Transform3D(b, y), Vector3(w, 0.14, 0.16))
		arms.append(y)
	await k.step()
	m.commit(timber, k.surface("timber", 0.8), "TallyPost")
	var bone := k.rock("bone_vertebra")
	if bone != "":
		await k.step()
		k.place(bone, top + Vector3(0.0, -0.05, 0.0), yaw + 0.4, 0.55 / maxf(PoiKit.height_of(bone), 0.5), false)
	# the socket: a heap of stones round its foot, knee high
	var stone := k.rock("boulder")
	await _heap(d, at, 0.55, 0.85, stone, "Socket")
	# the tally cut down its face: rows of notches toward the track
	var nicks := m.begin()
	var face := b * Vector3(0.0, 0.0, 0.131)
	var foot := k.on_ground(at.x, at.y)
	var rows := 6 + k.rng.randi_range(0, 5)
	for i in rows:
		for j in 1 + k.rng.randi_range(0, 3):
			var p := foot + face + b * Vector3(-0.08 + float(j) * 0.05, 0.9 + float(i) * 0.14, 0.0)
			m.block(nicks, Transform3D(b * Basis(Vector3.BACK, k.rng.randf_range(-0.3, 0.3)), p), Vector3(0.02, 0.1, 0.012))
	await k.step()
	m.commit(nicks, PoiKit.plain(Color(0.12, 0.11, 0.1), 0.95), "Notches")
	# the cords, hung along both yokes, gathered in a hand each side of each yoke that swings about
	# the yoke, so a gust moves them together and none leaves the timber it is tied to
	var along := b * Vector3.RIGHT
	for arm_i in arms.size():
		var arm: Vector3 = arms[arm_i]
		var half := 1.0 if arm_i == 0 else 0.65
		for side in [-1.0, 1.0]:
			var points: Array = []
			var lengths: Array = []
			for c in 3 + k.rng.randi_range(0, 1):
				var t := (0.2 + 0.8 * float(c) / 4.0) * half * float(side)
				points.append(arm + along * t - Vector3(0.0, 0.07, 0.0))
				lengths.append(k.rng.randf_range(0.45, 1.25) * (1.0 if arm_i == 0 else 0.7))
			await _cords(d, "Cords%d%s" % [arm_i, "L" if side < 0.0 else "R"], arm + along * (0.5 * half * float(side)), points, lengths, BONE)
	await LAND._grass(d, "heather", at, 5.0, 24)
	await _strew(d, at, 2.4, 6, stone)
	k.marker("the_tally", k.on_ground(at.x + to_road.x * 1.6, at.y + to_road.y * 1.6), true)


# --- a grave -------------------------------------------------------------------------------------

## A single grave by the road: a mound lying along the slope's contour with its marker at the
## head, in its people's way. The Vale's has a stone or a board and flowers; the Lakefolk's a
## lime-washed stone with a brass plate; the clans' two standing slabs with a giant's bone laid
## across them for a lintel over a mound of stones; the Reedfolk's a lantern on a pole with an
## indigo rag; the pilgrims' a bell on a stake over a mound of black ash stones; the Woodfolk's a
## mossed boulder with a staff of antler-hooked ash.
static func grave(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		# too small to be seen from the far ring
		return
	var m := d.masonry
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	# a grave lies along the slope, not down it, and parallel to the road that passes it
	var along: Vector2 = road["along"]
	var yaw := PoiKit.yaw_of(along)
	var at := Vector2.ZERO
	var head := at - along * 1.3
	var ga := k.on_ground(head.x, head.y).y
	var foot_end := at + along * 1.2
	var low := minf(_low(k, at, 0.9), minf(ga, k.on_ground(foot_end.x, foot_end.y).y))
	var high := maxf(k.on_ground(at.x, at.y).y, ga)
	var stony := k.region in ["skerrow", "cinderlea"]
	if stony:
		# a long heap of stones, not turf: nothing is dug deep on the fells or in the ash
		var stone := k.rock("boulder")
		if stone != "":
			var bh := maxf(PoiKit.height_of(stone), 0.3)
			var stones: Array = []
			for i in 16:
				var t := k.rng.randf_range(-1.0, 1.0)
				var s := k.rng.randf_range(-1.0, 1.0)
				var p := at + along * (t * 1.1) + to_road * (s * 0.5)
				var hump := (1.0 - t * t) * (1.0 - s * s * 0.6)
				var size := k.rng.randf_range(0.32, 0.46)
				stones.append(PoiKit.transform_at(k.on_ground(p.x, p.y, hump * 0.28 - size * 0.25), k.rng.randf_range(0.0, TAU), size / bh,
						Vector3(k.rng.randf_range(-0.3, 0.3), 0.0, k.rng.randf_range(-0.3, 0.3))))
			await k.step()
			var mm := k.scatter(stone, stones, false)
			if mm != null:
				mm.name = "GraveMound"
	else:
		var turf := PoiKit.painted(5, k._spec("earth"), 0.5) if k.region != "sedgemire" else PoiKit.painted(5, {"base": "#3b3a26", "accent": "#2c2b1b", "grout": "#1b1a10", "unit": 0.3}, 0.5)
		var mound := m.begin()
		var rise := high - low
		await k.step()
		m.ellipsoid(mound, Vector3(at.x, low - 0.1, at.y), Vector3(0.62, 0.42 + rise, 1.25), Basis(Vector3.UP, yaw))
		await k.step()
		m.commit(mound, turf, "GraveMound")
	k.collider(Vector3(1.1, 0.5, 2.3), Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, high + 0.05, at.y)), "dirt")
	var hb := Basis(Vector3.UP, yaw)
	match k.region:
		"skerrow":
			# two slabs of the fell on end at the head and a giant's finger-bone laid over them
			var slabs := m.begin()
			for s in [-1.0, 1.0]:
				var p := head + to_road * (0.45 * float(s))
				var g := _low(k, p, 0.2)
				m.block(slabs, Transform3D(hb * Basis(Vector3.BACK, 0.04 * float(s)), Vector3(p.x, g + 0.55, p.y)), Vector3(0.18, 1.5, 0.34))
				k.collider(Vector3(0.18, 1.5, 0.34), Transform3D(hb, Vector3(p.x, g + 0.55, p.y)), "stone")
			await k.step()
			m.commit(slabs, k.surface("stone", 0.8), "Uprights")
			var lintel_y := ga + 1.3
			var bone := k.rock("bone_finger")
			if bone != "":
				var bl := maxf(PoiKit.half_width_of(bone) * 2.0, 1.0)
				await k.step()
				k.place(bone, Vector3(head.x, lintel_y, head.y) - Vector3(to_road.x, 0.0, to_road.y) * 0.62,
						PoiKit.yaw_of(to_road) - PI * 0.5, 1.35 / bl, false)
			else:
				var lintel := m.begin()
				m.block(lintel, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(to_road)), Vector3(head.x, lintel_y + 0.08, head.y)), Vector3(0.24, 0.16, 1.35))
				await k.step()
				m.commit(lintel, PoiKit.plain(BONE, 0.8), "Lintel")
			await LAND._grass(d, "heather", at, 3.5, 16)
		"sedgemire":
			# the lantern on its pole at the head, lit, with an indigo rag tied under it
			var pole := m.begin()
			var top := _post(d, pole, head, 2.6, 0.1, Vector3(0.0, 0.0, 0.06))
			var arm_end := top + Vector3(to_road.x, 0.0, to_road.y) * 0.45
			m.block(pole, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(to_road)), (top + arm_end) * 0.5 - Vector3(0.0, 0.08, 0.0)), Vector3(0.07, 0.07, 0.5))
			await k.step()
			m.commit(pole, k.surface("timber", 0.9), "LanternPole")
			var lamp := k.prop("lantern_hanging")
			if lamp != "":
				await k.step()
				k.place(lamp, arm_end - Vector3(0.0, 0.52, 0.0), 0.0, 1.1, false)
			k.light(arm_end - Vector3(0.0, 0.35, 0.0), LANTERN, 1.2, 7.0)
			await _cords(d, "Rag", top - Vector3(0.0, 0.5, 0.0), [top - Vector3(0.0, 0.5, 0.0)], [0.02], INDIGO, INDIGO, Vector3(0.12, 0.62, 0.015))
			await LAND._grass(d, "sedge_tussock", at, 3.5, 14)
			await LAND._grass(d, "marsh_marigold", at, 1.5, 5)
		"cinderlea":
			# a stake at the head with a crosspiece and a bell under it, and the candle stubs
			var stake := m.begin()
			var top := _post(d, stake, head, 1.9, 0.12)
			m.block(stake, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(to_road)), top - Vector3(0.0, 0.1, 0.0)), Vector3(0.08, 0.08, 0.7))
			await k.step()
			m.commit(stake, PoiKit.plain(Color(0.8, 0.79, 0.75), 0.9), "Stake")
			var bell := k.prop("bell_small")
			if bell != "":
				await k.step()
				k.place(bell, top - Vector3(0.0, 0.62, 0.0) + Vector3(to_road.x, 0.0, to_road.y) * 0.22, 0.0, 1.9, false)
			var stub := k.prop("candle_stub")
			if stub != "":
				var stubs: Array = []
				for i in 4:
					var p := head + along * k.rng.randf_range(0.3, 0.6) + to_road * k.rng.randf_range(-0.5, 0.5)
					stubs.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.6))
				await k.step()
				k.scatter(stub, stubs, false, false, false)
			await LAND._grass(d, "grey_grass", at, 3.5, 14)
		"briarwold":
			# a mossed boulder at the head, and a staff of ash stuck in the mound with its hooks
			var rock := k.rock("boulder")
			if rock != "":
				await k.step()
				k.place(rock, k.on_ground(head.x, head.y, -0.25), yaw, 0.85 / maxf(PoiKit.height_of(rock), 0.5), true)
			var staff := m.begin()
			var top := _post(d, staff, head + along * 0.55, 1.7, 0.07, Vector3(0.1, 0.0, 0.0))
			for s in [-1.0, 1.0]:
				m.block(staff, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, 0.7 * float(s)), top - Vector3(0.0, 0.2, 0.0)), Vector3(0.04, 0.35, 0.04))
			await k.step()
			m.commit(staff, k.surface("timber", 0.9), "Staff")
			await LAND._grass(d, "moss_patch", at, 2.0, 6)
			await LAND._grass(d, "foxglove", at, 3.0, 6)
		"brightwater":
			# a lime-washed stone with a brass plate on it, the Lakefolk's name and their price
			var st := m.begin()
			var g := _low(k, head, 0.3)
			m.block(st, Transform3D(hb, Vector3(head.x, g + 0.5, head.y)), Vector3(0.7, 1.2, 0.18))
			m.block(st, Transform3D(hb, Vector3(head.x, g + 1.1, head.y)), Vector3(0.78, 0.08, 0.22))
			await k.step()
			m.commit(st, PoiKit.plain(LIME, 0.9), "Headstone")
			var plate := m.begin()
			var front := Vector3(head.x, g + 0.72, head.y) + hb * Vector3(0.0, 0.0, 0.1)
			m.block(plate, Transform3D(hb, front), Vector3(0.38, 0.26, 0.02))
			await k.step()
			m.commit(plate, PoiKit.plain(PoiKit.BRONZE, 0.35, 0.8), "Plate")
			k.collider(Vector3(0.7, 1.2, 0.18), Transform3D(hb, Vector3(head.x, g + 0.5, head.y)), "stone")
			await LAND._grass(d, "cow_parsley", at, 3.0, 8)
		_:
			# the Vale's: a board with a little roof where the sentence says a board, else a stone,
			# and flowers somebody still brings
			if PoiKit.brief_says(d.brief, ["board", "wooden", "cross"]):
				var board := m.begin()
				var top := _post(d, board, head, 1.25, 0.09)
				m.block(board, Transform3D(hb, top - Vector3(0.0, 0.35, 0.0) + hb * Vector3(0.0, 0.0, 0.06)), Vector3(0.52, 0.42, 0.04))
				for s in [-1.0, 1.0]:
					m.block(board, Transform3D(hb * Basis(Vector3.BACK, 0.55 * float(s)), top + hb * Vector3(0.17 * float(s), 0.02, 0.06)), Vector3(0.42, 0.04, 0.14))
				await k.step()
				m.commit(board, k.surface("timber", 0.9), "Board")
			else:
				var gs := k.prop("gravestone")
				if gs != "":
					await k.step()
					k.place(gs, k.on_ground(head.x, head.y, -0.12), yaw + PI, 1.25, true, Vector3(k.rng.randf_range(-0.06, 0.06), 0.0, 0.05))
			var jar := k.prop("jar")
			if jar != "":
				var p := head + along * 0.4 + to_road * 0.25
				await k.step()
				k.place(jar, k.on_ground(p.x, p.y), 0.0, 1.0, false)
			await LAND._grass(d, "poppy" if k.region == "hearthvale" else "cow_parsley", at, 1.4, 7)
	await LAND._grass(d, _verge(k), at, 5.0, 18)
	k.marker("the_grave", k.on_ground(at.x + to_road.x * 1.5, at.y + to_road.y * 1.5), true)


# --- a gibbet ------------------------------------------------------------------------------------

## A post by the road with an arm out from its top and an iron cage hung from the arm on a chain,
## where the Wardens or the Tollmere watch hanged somebody and left them for the crows. The Vale's
## is rough oak in a heap of flints; the Lakefolk's stands on a lime-washed step with the
## charter's brass plate nailed to it, because even this has a price.
static func gibbet(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		# too small to be seen from the far ring
		return
	var m := d.masonry
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	var along: Vector2 = road["along"]
	var yaw := PoiKit.yaw_of(along)
	var b := Basis(Vector3.UP, yaw)
	var at := -to_road * 0.8
	var lake := k.region == "brightwater"
	var timber := m.begin()
	var foot_y := _low(k, at, 0.8)
	if lake:
		var step := m.begin()
		m.block(step, Transform3D(b, Vector3(at.x, foot_y + 0.1, at.y)), Vector3(1.4, 0.8, 1.4))
		await k.step()
		m.commit(step, PoiKit.plain(LIME, 0.9), "Step")
		k.collider(Vector3(1.4, 0.8, 1.4), Transform3D(b, Vector3(at.x, foot_y + 0.1, at.y)), "stone")
	else:
		await _heap(d, at, 0.6, 0.8, k.rock("boulder"), "Socket")
	var top := _post(d, timber, at, 4.3, 0.3)
	# the arm, out over the road's side, and its brace
	var out := b * Vector3.RIGHT * (1.0 if k.rng.randf() < 0.5 else -1.0)
	var arm_end := top + out * 1.7 - Vector3(0.0, 0.2, 0.0)
	m.block(timber, Transform3D(Basis.looking_at(out, Vector3.UP), top + out * 0.8 - Vector3(0.0, 0.2, 0.0)), Vector3(0.2, 0.2, 1.95))
	var brace_a := top - Vector3(0.0, 1.1, 0.0)
	var brace_b := top + out * 0.9 - Vector3(0.0, 0.25, 0.0)
	m.block(timber, Transform3D(Basis.looking_at((brace_b - brace_a).normalized(), Vector3.UP), (brace_a + brace_b) * 0.5),
			Vector3(0.12, 0.12, brace_a.distance_to(brace_b)))
	await k.step()
	m.commit(timber, k.surface("timber", 0.95), "Gibbet")
	if lake:
		var plate := m.begin()
		m.block(plate, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(to_road)), Vector3(at.x, foot_y + 1.9, at.y) + Vector3(to_road.x, 0.0, to_road.y) * 0.16),
				Vector3(0.34, 0.44, 0.02))
		await k.step()
		m.commit(plate, PoiKit.plain(PoiKit.BRONZE, 0.35, 0.8), "Charter")
	# the cage on its chain, swinging a little: bands and bars of iron, and what is left in it
	var hang := arm_end - Vector3(0.0, 0.05, 0.0)
	var cage := Turning.new()
	cage.name = "Cage"
	cage.position = hang
	cage.axis = Vector3(LAND.WIND.y, 0.0, -LAND.WIND.x)
	cage.swing = 0.06
	cage.rate = 0.9
	cage.phase = k.rng.randf_range(0.0, TAU)
	d.add_child(cage)
	var iron := m.begin()
	var chain := 0.7
	m.rod(iron, Transform3D(Basis(), Vector3(0.0, -chain * 0.5, 0.0)), 0.02, chain)
	var h := 1.75
	var r := 0.34
	var c0 := Vector3(0.0, -chain - h * 0.5, 0.0)
	for i in 8:
		var a := TAU * float(i) / 8.0
		m.rod(iron, Transform3D(Basis(), c0 + Vector3(sin(a) * r, 0.0, cos(a) * r)), 0.016, h)
	for y in [-h * 0.5, -h * 0.12, h * 0.3, h * 0.5]:
		for i in 8:
			var a0 := TAU * float(i) / 8.0
			var a1 := TAU * float(i + 1) / 8.0
			var p0 := c0 + Vector3(sin(a0) * r, float(y), cos(a0) * r)
			var p1 := c0 + Vector3(sin(a1) * r, float(y), cos(a1) * r)
			m.block(iron, Transform3D(Basis.looking_at((p1 - p0).normalized(), Vector3.UP), (p0 + p1) * 0.5), Vector3(0.03, 0.03, p0.distance_to(p1)))
	# the crown of the cage, a hoop to the chain
	m.block(iron, Transform3D(Basis(), c0 + Vector3(0.0, h * 0.5 + 0.04, 0.0)), Vector3(0.05, 0.08, 0.05))
	var bones := m.begin()
	await k.step()
	m.ellipsoid(bones, c0 + Vector3(0.0, h * 0.28, 0.02), Vector3(0.1, 0.12, 0.11))
	for i in 5:
		m.block(bones, Transform3D(Basis(Vector3.RIGHT, 0.3), c0 + Vector3(0.0, h * 0.1 - float(i) * 0.08, -0.05)), Vector3(0.26 - float(i) * 0.02, 0.02, 0.03))
	m.block(bones, Transform3D(Basis(Vector3.BACK, 0.2), c0 + Vector3(0.08, -h * 0.25, 0.0)), Vector3(0.04, 0.5, 0.04))
	m.block(bones, Transform3D(Basis(Vector3.BACK, -0.1), c0 + Vector3(-0.1, -h * 0.3, 0.05)), Vector3(0.04, 0.45, 0.04))
	var rags := m.begin()
	m.block(rags, Transform3D(Basis(Vector3.UP, 0.4), c0 + Vector3(0.0, -h * 0.02, 0.0)), Vector3(0.36, 0.5, 0.3))
	for pair in [[iron, PoiKit.plain(IRON, 0.6, 0.5), "CageIron"], [bones, PoiKit.plain(BONE, 0.8), "CageBones"],
			[rags, PoiKit.plain(Color(0.2, 0.18, 0.15), 0.95), "CageRags"]]:
		await k.step()
		var mi := m.commit(pair[0], pair[1], str(pair[2]))
		if mi != null:
			mi.get_parent().remove_child(mi)
			cage.add_child(mi)
	# the crows that keep it
	var perches: Array[Vector3] = [top + Vector3(0.0, 0.05, 0.0), arm_end + Vector3(0.0, 0.12, 0.0) - out * 0.4,
			hang + Vector3(0.0, -chain + 0.05, 0.0)]
	var crows := Crows.new()
	crows.name = "Crows"
	crows.radius = 9.0
	crows.height = 9.0
	d.add_child(crows)
	crows.setup(perches, Vector3(at.x, foot_y + 2.0, at.y), 4, k.rng.randi())
	await LAND._grass(d, _verge(k), at, 5.0, 20)
	k.marker("the_gibbet", k.on_ground(to_road.x * 1.2, to_road.y * 1.2), true)


# --- a fold --------------------------------------------------------------------------------------

## A ring of wall 8 to 10 m across with a gate, where a flock is brought in off the fell or the
## down: drystone on the fells, as the shieling's fold is; on the Vale's downs a round of wattle
## hurdles staked into the chalk. Some have a lean-to of stone against the wall for the shepherd,
## and some have the flock in them.
static func fold(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		# too small to be seen from the far ring
		return
	var m := d.masonry
	var fabric := FabricMesh.new()
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	var r := k.rng.randf_range(4.0, 4.8)
	var c := Vector2.ZERO
	var gate_yaw := PoiKit.yaw_of(to_road)
	var hurdles := k.region in ["hearthvale", "brightwater"]
	var wattle := k.prop("fence_wattle") if hurdles else ""
	# a hurdle is three and a half metres and is not cut, so a round of them has eight sides
	var segs := 8 if wattle != "" else 14
	var ring_pts: Array[Vector2] = []
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		ring_pts.append(c + Vector2(sin(a), cos(a)) * r * (1.0 + 0.04 * sin(a * 3.0 + 1.0)))
	var gate_seg := -1
	var best := INF
	for i in segs:
		var mid := ((ring_pts[i] + ring_pts[i + 1]) * 0.5).normalized()
		var off := absf(wrapf(PoiKit.yaw_of(mid) - gate_yaw, -PI, PI))
		if off < best:
			best = off
			gate_seg = i
	for i in segs:
		if i == gate_seg:
			continue
		var a: Vector2 = ring_pts[i]
		var bb: Vector2 = ring_pts[i + 1]
		if wattle != "":
			var mid := (a + bb) * 0.5
			var dir := (bb - a)
			var len_w := dir.length()
			var wl := maxf(PoiKit.half_width_of(wattle) * 2.0, 1.0)
			await k.step()
			k.place(wattle, k.on_ground(mid.x, mid.y, -0.12), atan2(-dir.y, dir.x), len_w / wl * 1.02, false,
					Vector3(0.0, 0.0, atan2(k.on_ground(bb.x, bb.y).y - k.on_ground(a.x, a.y).y, len_w)))
			k.collider(Vector3(len_w, 1.2, 0.15), Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), k.on_ground(mid.x, mid.y, 0.6)), "wood")
		else:
			LAND._dry_wall(d, fabric, a, bb, 1.2)
	# the gate: two posts and a hurdle swung half open
	var ga: Vector2 = ring_pts[gate_seg]
	var gb: Vector2 = ring_pts[gate_seg + 1]
	var posts := k.prop("gate_post")
	for p in [ga, gb]:
		var q: Vector2 = p
		if posts != "":
			await k.step()
			k.place(posts, k.on_ground(q.x, q.y, -0.15), gate_yaw, 1.0, true)
	var hinge := ga
	var gdir := (gb - ga).normalized().rotated(-0.9)
	var gate_mid := hinge + gdir * 0.8
	var gate_len := ga.distance_to(gb) * 0.9
	fabric.box("joinery", Transform3D(Basis(Vector3.UP, atan2(-gdir.y, gdir.x)), k.on_ground(gate_mid.x, gate_mid.y, 0.55)),
			Vector3(gate_len, 0.95, 0.06), Color(0.52, 0.42, 0.3))
	# a lean-to of stone against the wall across from the gate, for a night up here in lambing
	var lean_to := PoiKit.brief_says(d.brief, ["lean-to", "shelter", "bothy"]) or (not hurdles and k.rng.randf() < 0.5)
	if lean_to:
		var back := -to_road
		var side := Vector2(-back.y, back.x)
		var lc := c + back * (r - 1.0)
		var roof := m.begin()
		var gy := k.on_ground(lc.x, lc.y).y
		for s in [-1.0, 1.0]:
			var p := lc + side * (0.9 * float(s))
			LAND._dry_wall(d, fabric, p + back * 0.7, p - back * 0.5, 1.1)
		m.block(roof, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(back)) * Basis(Vector3.RIGHT, 0.22), Vector3(lc.x, gy + 1.2, lc.y)),
				Vector3(2.3, 0.14, 1.6))
		await k.step()
		m.commit(roof, k.surface("stone", 0.7), "LeanTo")
		k.collider(Vector3(2.3, 0.14, 1.6), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(back)), Vector3(lc.x, gy + 1.2, lc.y)), "stone")
	await LAND._commit_fabric(d, fabric)
	if not k.far and (PoiKit.brief_says(d.brief, ["sheep", "flock", "ewes"]) or k.rng.randf() < 0.5):
		var sheep := Livestock.paths_of("sheep")
		if not sheep.is_empty():
			var flock := Livestock.new()
			flock.name = "Flock"
			flock.seed_with(absi(("flock:" + d.poi_id).hash()))
			flock.keep("sheep", sheep, k.on_ground(c.x, c.y), r - 1.6, 3 + k.rng.randi_range(0, 3))
			d.add_child(flock)
	await LAND._grass(d, "heather" if k.region == "skerrow" else "meadow_grass", c, r - 0.8, 16)
	await LAND._grass(d, _verge(k), c, PAD_M - 0.7, 14)
	k.marker("the_fold", k.on_ground((ga.x + gb.x) * 0.5 + to_road.x, (ga.y + gb.y) * 0.5 + to_road.y), true)


# --- a well --------------------------------------------------------------------------------------

## Water for the road: on the level, a wellhead with its windlass and bucket; where the ground falls,
## a spring let out of the bank through a spout into a stone trough. A cup hangs by it on a chain
## for whoever is passing. The Lakefolk's trough is lime-washed with a brass spout and cup.
static func well(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		# too small to be seen from the far ring
		return
	var m := d.masonry
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	var down := k.downhill()
	var at := Vector2.ZERO
	var lake := k.region == "brightwater"
	var drop := k.on_ground(-down.x * 3.0, -down.y * 3.0).y - k.on_ground(down.x * 3.0, down.y * 3.0).y if down != Vector2.ZERO else 0.0
	var spring := drop > 1.2 or PoiKit.brief_says(d.brief, ["spring", "trough"]) or lake
	var cup_at := Vector3.ZERO
	if not spring:
		var head := k.prop("well")
		var yaw := PoiKit.yaw_of(to_road)
		if head != "":
			await k.step()
			k.place(head, Vector3(at.x, _low(k, at, 1.0) - 0.1, at.y), yaw, 1.0, true)
		var bucket := k.prop("bucket")
		if bucket != "":
			var p := at + to_road * 1.4 + Vector2(-to_road.y, to_road.x) * 0.6
			await k.step()
			k.place(bucket, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.0, true)
		var post := m.begin()
		var pt := at + to_road * 1.05 + Vector2(to_road.y, -to_road.x) * 0.7
		var top := _post(d, post, pt, 1.2, 0.1)
		await k.step()
		m.commit(post, k.surface("timber", 0.9), "CupPost")
		cup_at = top - Vector3(0.0, 0.35, 0.0) + Vector3(to_road.x, 0.0, to_road.y) * 0.08
	else:
		# the spring: a back wall set into the bank uphill, a spout out of it, and the trough against
		# the wall under it, its lip level and a hand over the ground at its uphill edge
		var into := -down if down != Vector2.ZERO else -to_road
		var out := -into
		var across := Vector2(-out.y, out.x)
		var yaw := PoiKit.yaw_of(out)
		var b := Basis(Vector3.UP, yaw)
		var back_c := at + into * 0.9
		var front := back_c + out * 0.25
		var tc := back_c + out * 0.7
		var t_low := _low(k, tc, 0.9)
		var lip := k.on_ground(tc.x + into.x * 0.4, tc.y + into.y * 0.4).y + 0.4
		var t_h := lip - t_low + 0.25
		var stone_mat := _lake_or(k, lake, PoiKit.plain(LIME, 0.9), "stone", 0.7)
		var wall_top := maxf(lip + 1.0, k.on_ground(back_c.x, back_c.y).y + 0.4)
		var wall_bottom := t_low - 0.3
		var wall_xf := Transform3D(b, Vector3(back_c.x, (wall_top + wall_bottom) * 0.5, back_c.y))
		var wall := m.begin()
		m.block(wall, wall_xf, Vector3(2.4, wall_top - wall_bottom, 0.5))
		for s in [-1.0, 1.0]:
			m.block(wall, Transform3D(b, Vector3(tc.x, lip - t_h * 0.5, tc.y) + b * Vector3(0.0, 0.0, 0.33 * float(s))), Vector3(1.7, t_h, 0.14))
			m.block(wall, Transform3D(b, Vector3(tc.x, lip - t_h * 0.5, tc.y) + b * Vector3(0.8 * float(s), 0.0, 0.0)), Vector3(0.14, t_h, 0.8))
		await k.step()
		m.commit(wall, stone_mat, "Spring")
		k.collider(Vector3(2.4, wall_top - wall_bottom, 0.5), wall_xf, "stone")
		k.collider(Vector3(1.7, t_h, 0.8), Transform3D(b, Vector3(tc.x, lip - t_h * 0.5, tc.y)), "stone")
		var water := m.begin()
		m.block(water, Transform3D(b, Vector3(tc.x, lip - 0.08, tc.y)), Vector3(1.48, 0.02, 0.54))
		await k.step()
		m.commit(water, k.still_water(lip - 0.6), "TroughWater")
		# the spout out of the wall and the water falling from it into the trough
		var spout_at := Vector3(front.x, lip + 0.5, front.y) + Vector3(out.x, 0.0, out.y) * 0.17
		var spout := m.begin()
		m.block(spout, Transform3D(b, spout_at), Vector3(0.09, 0.06, 0.4))
		await k.step()
		m.commit(spout, _lake_or(k, lake, PoiKit.plain(PoiKit.BRONZE, 0.35, 0.8), "stone", 0.8), "Spout")
		var fall_top := spout_at + Vector3(out.x, 0.0, out.y) * 0.2 - Vector3(0.0, 0.03, 0.0)
		await k.step()
		m.sheet(fall_top, yaw, 0.07, fall_top.y - (lip - 0.08), PoiKit.falling_water(), "Trickle", 0.0, false, 1, 4)
		cup_at = Vector3(front.x, lip + 0.4, front.y) + Vector3(across.x, 0.0, across.y) * 0.95 + Vector3(out.x, 0.0, out.y) * 0.04
	# the cup on its chain
	var chain := m.begin()
	m.rod(chain, Transform3D(Basis(), cup_at + Vector3(0.0, 0.12, 0.0)), 0.008, 0.24)
	await k.step()
	m.commit(chain, PoiKit.plain(IRON, 0.6, 0.5), "Chain")
	var cup := m.begin()
	await k.step()
	m.drum(cup, Transform3D(Basis(), cup_at - Vector3(0.0, 0.1, 0.0)), 0.05, 0.09, 0.0, NAN, false, 0.09)
	await k.step()
	m.commit(cup, _lake_or(k, lake, PoiKit.plain(PoiKit.BRONZE, 0.35, 0.8), "timber", 0.8), "Cup")
	await LAND._grass(d, "cow_parsley" if not lake else "reeds", at, 3.0, 8)
	await LAND._grass(d, _verge(k), at, 5.5, 18)
	k.marker("the_well", k.on_ground(at.x + to_road.x * 1.8, at.y + to_road.y * 1.8), true)


## The Lakefolk's material where `lake`, else the region's painted `kind` at `wear`.
static func _lake_or(k: PoiKit, lake: bool, theirs: Material, kind: String, wear: float) -> Material:
	if lake:
		return theirs
	return k.surface(kind, wear)


# --- a lantern post ------------------------------------------------------------------------------

## A tall pole of the marsh's alder with a lantern on its arm and indigo rags tied under it, the
## Reedfolk's mark for the safe way over the fen, with short stakes ragged the same way leading on
## along the road. Where the sentence says somebody drowned, it is their lantern instead, leaning out
## toward the water, lower, with a wreath of reeds on the pole.
static func lantern_post(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		# from the far ring, only the lantern's glow at night, which is what marks the way
		k.light(k.on_ground(0.0, 0.0, 4.1), LANTERN, 1.6, 9.0)
		return
	var m := d.masonry
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	var along: Vector2 = road["along"]
	var drowned := PoiKit.brief_says(d.brief, ["drown", "lost", "mourn"])
	var water := k.water_direction(20.0)
	var lean_to := water if water != Vector2.ZERO else -to_road
	var at := Vector2.ZERO
	var pole := m.begin()
	var lean := Vector3.ZERO
	var height := 4.4 + k.rng.randf_range(-0.2, 0.4)
	if drowned:
		height = 3.0
		# tipped out toward the water it stands for
		lean = Vector3(lean_to.y * 0.2, 0.0, -lean_to.x * 0.2)
	var top := _post(d, pole, at, height, 0.14, lean)
	# a crook of an arm out at the top, the lantern hung from its end
	var arm_dir := Vector3(lean_to.x, 0.0, lean_to.y) if drowned else Vector3(to_road.x, 0.0, to_road.y)
	var arm_end := top + arm_dir * 0.62 + Vector3(0.0, -0.1, 0.0)
	m.block(pole, Transform3D(Basis.looking_at(arm_end - top + Vector3(0.0, 0.001, 0.0), Vector3.UP), (top + arm_end) * 0.5), Vector3(0.08, 0.08, top.distance_to(arm_end) + 0.1))
	await k.step()
	m.commit(pole, k.surface("timber", 0.95), "LanternPole")
	var lamp := k.prop("lantern_hanging")
	var lamp_at := arm_end - Vector3(0.0, 0.55, 0.0)
	if lamp != "":
		await k.step()
		k.place(lamp, lamp_at, 0.0, 1.25, false)
	k.light(lamp_at + Vector3(0.0, 0.2, 0.0), LANTERN, 1.6, 9.0)
	# the rags: indigo strips knotted round the pole under the arm, which the wind takes
	var ties: Array = []
	var lengths: Array = []
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.4
		ties.append(top - Vector3(0.0, 0.55 + float(i) * 0.12, 0.0) + Vector3(sin(a), 0.0, cos(a)) * 0.08)
		lengths.append(0.02)
	await _cords(d, "Rags", top - Vector3(0.0, 0.6, 0.0), ties, lengths, INDIGO, INDIGO, Vector3(0.1, 0.7, 0.012))
	if drowned:
		# a wreath of reeds bound round the pole at a man's height
		var wreath := m.begin()
		var wy := k.on_ground(at.x, at.y).y + 1.5
		for i in 10:
			var a0 := TAU * float(i) / 10.0
			var p := Vector3(at.x + sin(a0) * 0.2, wy, at.y + cos(a0) * 0.2)
			await k.step()
			m.ellipsoid(wreath, p, Vector3(0.07, 0.05, 0.07))
		await k.step()
		m.commit(wreath, PoiKit.plain(Color(0.55, 0.5, 0.26), 0.9), "Wreath")
	else:
		# the stakes on along the way, each with a rag, a few paces apart, up to the pad's edge
		var stakes := m.begin()
		var tops: Array = []
		var tlen: Array = []
		for s in [-1.0, 1.0]:
			for j in 2:
				var p := at + along * (float(s) * (2.8 + float(j) * 2.6)) + to_road * 0.4
				var st_top := _post(d, stakes, p, 1.05, 0.08, Vector3(k.rng.randf_range(-0.08, 0.08), 0.0, k.rng.randf_range(-0.08, 0.08)))
				tops.append(st_top - Vector3(0.0, 0.08, 0.0))
				tlen.append(0.02)
		await k.step()
		m.commit(stakes, k.surface("timber", 0.95), "Stakes")
		for i in tops.size():
			await _cords(d, "StakeRag%d" % i, tops[i], [tops[i]], [tlen[i]], INDIGO, INDIGO, Vector3(0.08, 0.42, 0.01))
	await LAND._grass(d, "reeds", at, 3.0, 12)
	await LAND._grass(d, "sedge_tussock", at, 5.5, 12)
	k.marker("the_lantern", k.on_ground(at.x + to_road.x * 1.4, at.y + to_road.y * 1.4), true)


# --- a cart gone over ----------------------------------------------------------------------------

## A cart gone over in the verge with its load spilled down the bank: on its side, one wheel off
## and lying in the grass, the sacks and crates and barrels where they fell. Carts are the Vale's,
## and the load is the region's own. `wreck` builds this where its sentence says a cart.
static func cart_wreck(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		# too small to be seen from the far ring
		return
	var m := d.masonry
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	var along: Vector2 = road["along"]
	var down := k.downhill()
	var off := -to_road if down == Vector2.ZERO else down
	var at := off * 0.6
	var cart := k.prop("cart")
	var yaw := PoiKit.yaw_of(Vector2(along.y, -along.x))
	if cart != "":
		# on its side: rolled a quarter turn about its length (its x), the bed toward the road
		var gy := _low(k, at, 1.6)
		await k.step()
		k.place(cart, Vector3(at.x, gy + 0.62, at.y), yaw, 0.85, true, Vector3(1.45, 0.0, 0.0))
	# the wheel off, lying in the grass further down
	var wheel_at := at + off * 2.2 + along * 1.4
	var wheel := m.begin()
	var wy := k.on_ground(wheel_at.x, wheel_at.y).y + 0.06
	var wf := Transform3D(Basis(), Vector3(wheel_at.x, wy, wheel_at.y))
	await k.step()
	m.drum(wheel, wf, 0.62, 0.1, 0.0, NAN, false, 0.1)
	for i in 6:
		m.block(wheel, Transform3D(Basis(Vector3.UP, TAU * float(i) / 12.0), wf.origin + Vector3(0.0, 0.05, 0.0)), Vector3(1.2, 0.05, 0.06))
	await k.step()
	m.commit(wheel, k.surface("timber", 0.9), "Wheel")
	# the load, spilled down the bank
	for kind_n in [["sack", 4], ["crate", 2], ["barrel", 2], ["basket", 1]]:
		var path := k.prop(str(kind_n[0]))
		if path == "":
			continue
		for i in int(kind_n[1]):
			var p := at + off * k.rng.randf_range(0.8, 3.2) + along * k.rng.randf_range(-2.6, 2.6)
			var tip := Vector3(k.rng.randf_range(-0.6, 0.6), 0.0, k.rng.randf_range(-1.4, 1.4)) if kind_n[0] != "crate" else Vector3(0.0, 0.0, k.rng.randf_range(-0.3, 0.3))
			await k.step()
			k.place(path, k.on_ground(p.x, p.y, -0.08), k.rng.randf_range(0.0, TAU), 1.0, i == 0, tip)
	await LAND._grass(d, _verge(k), at, 5.0, 18)
	k.marker("the_cart", k.on_ground(to_road.x * 1.5, to_road.y * 1.5), true)


# --- a hut ---------------------------------------------------------------------------------------

## Somebody's hut out on its own: in the wood a charcoal-burner's cone of poles under turf with the
## clamp smoking beside it and the cordwood stacked, or where the sentence says a hermit, a lean-to
## of boughs against a boulder with a stool and a bundle of herbs hung up; on the fells and the
## downs a bothy of drystone under turf; in the marsh a cone of poles thatched with reed.
static func hut(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		# too small to be seen from the far ring
		return
	var m := d.masonry
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	var across := Vector2(-to_road.y, to_road.x)
	var hermit := PoiKit.brief_says(d.brief, ["hermit", "anchorite", "recluse"])
	var at := -to_road * 1.0
	var door := to_road
	if hermit:
		# a boulder at its back and boughs leant against a ridge-pole from it to two forked sticks
		var rock := k.rock("boulder")
		var back := at - to_road * 1.6
		if rock != "":
			await k.step()
			k.place(rock, k.on_ground(back.x, back.y, -0.5), PoiKit.yaw_of(to_road), 2.4 / maxf(PoiKit.height_of(rock), 0.5), true)
		var boughs := m.begin()
		var ridge_a := k.on_ground(back.x, back.y, 1.7)
		var fork := at + to_road * 1.2
		var fork_top := _post(d, boughs, fork, 1.3, 0.08)
		var ridge_b := fork_top
		m.block(boughs, Transform3D(Basis.looking_at((ridge_b - ridge_a).normalized(), Vector3.UP), (ridge_a + ridge_b) * 0.5),
				Vector3(0.1, 0.1, ridge_a.distance_to(ridge_b)))
		for i in 11:
			var t := float(i) / 10.0
			var on_ridge := ridge_a.lerp(ridge_b, t)
			for s in [-1.0, 1.0]:
				var foot := at.lerp(fork, t) + across * (1.3 * float(s))
				var gf := k.on_ground(foot.x, foot.y)
				m.block(boughs, Transform3D(Basis.looking_at((on_ridge - gf).normalized(), Vector3.UP), (on_ridge + gf) * 0.5),
						Vector3(0.07, 0.07, on_ridge.distance_to(gf) + 0.2))
		await k.step()
		m.commit(boughs, k.surface("timber", 0.95), "Boughs")
		k.collider(Vector3(2.8, 1.6, 3.0), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(to_road)), k.on_ground(at.x, at.y, 0.8)), "wood")
		var stool := k.prop("stool")
		if stool != "":
			var p := at + to_road * 2.0 + across * 0.9
			await k.step()
			k.place(stool, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.0, true)
		await _cords(d, "Herbs", fork_top - Vector3(0.0, 0.1, 0.0), [fork_top - Vector3(0.0, 0.1, 0.0)], [0.25],
				Color(0.42, 0.5, 0.28), ROPE, Vector3(0.16, 0.3, 0.12))
		await LAND._grass(d, _verge(k), Vector2.ZERO, 5.0, 18)
		k.marker("the_hut", k.on_ground(at.x + to_road.x * 2.2, at.y + to_road.y * 2.2), true)
		return
	match k.region:
		"skerrow", "hearthvale", "brightwater", "cinderlea":
			# a bothy: drystone walls to the shoulder, a door toward the track, a turf roof
			var fabric := FabricMesh.new()
			var w := 3.8
			var depth := 3.0
			var wall_h := 1.5
			var corners: Array[Vector2] = []
			for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
				corners.append(at + across * (w * 0.5 * float(s[0])) + door * (depth * 0.5 * float(s[1])))
			for i in 4:
				var a: Vector2 = corners[i]
				var bb: Vector2 = corners[(i + 1) % 4]
				if i == 2:
					var mid := (a + bb) * 0.5
					var dir := (bb - a).normalized()
					LAND._dry_wall(d, fabric, a, mid - dir * 0.5, wall_h)
					LAND._dry_wall(d, fabric, mid + dir * 0.5, bb, wall_h)
				else:
					LAND._dry_wall(d, fabric, a, bb, wall_h)
			await LAND._commit_fabric(d, fabric)
			var ground := k.on_ground(at.x, at.y).y
			var turf := PoiKit.painted(5, {"base": "#5d6a3c", "accent": "#46522c", "grout": "#2f3a1d", "unit": 0.3}, 0.6)
			var roof := m.begin()
			await k.step()
			m.ellipsoid(roof, Vector3(at.x, ground + wall_h + 0.1, at.y), Vector3(w * 0.64, 0.9, depth * 0.68), Basis(Vector3.UP, PoiKit.yaw_of(door)))
			await k.step()
			m.commit(roof, turf, "TurfRoof")
			k.collider(Vector3(w, 0.8, depth), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(door)), Vector3(at.x, ground + wall_h + 0.4, at.y)), "dirt")
			await k.step()
			k.puffs(Vector3(at.x, ground + wall_h + 1.0, at.y), Vector3(0.1, 0.1, 0.1), 0.8, 8, Color(0.8, 0.78, 0.76, 0.3), 1.1, 5.0)
			var peat := k.prop("peat_stack") if k.region == "skerrow" else k.prop("chopping_block")
			if peat != "":
				var p := at + door * (depth * 0.5 + 0.8) + across * (w * 0.5 + 0.4)
				await k.step()
				k.place(peat, k.on_ground(p.x, p.y, -0.05), PoiKit.yaw_of(door), 1.0, true)
		_:
			# a cone of poles, under turf in the wood, reed-thatched in the marsh, with a door-gap
			var cone_c := at
			var g := _low(k, cone_c, 1.8)
			var h := 3.2
			var cone := m.begin()
			var apex := Vector3(cone_c.x, g + h, cone_c.y)
			var poles := m.begin()
			for i in 16:
				var a := TAU * float(i) / 16.0
				var dir := Vector2(sin(a), cos(a))
				if dir.dot(door) > 0.93:
					continue
				var foot := cone_c + dir * 1.8
				var gf := k.on_ground(foot.x, foot.y)
				m.block(poles, Transform3D(Basis.looking_at((apex - gf).normalized(), Vector3.UP), (apex + gf) * 0.5 + Vector3(0.0, 0.2, 0.0)),
						Vector3(0.08, 0.08, apex.distance_to(gf) + 0.5))
			await k.step()
			m.commit(poles, k.surface("timber", 0.95), "Poles")
			var skin := PoiKit.painted(5, {"base": "#8a7a4a", "accent": "#6b5d36", "grout": "#3e3520", "unit": 0.2}, 0.6) if k.region == "sedgemire" \
					else PoiKit.painted(5, {"base": "#4f5a34", "accent": "#3d4628", "grout": "#262c18", "unit": 0.3}, 0.6)
			# the cone's skin: a squat cone of rings, open at the door
			var rings := 5
			for r_i in rings:
				var f0 := float(r_i) / float(rings)
				var f1 := float(r_i + 1) / float(rings)
				for i in 16:
					var a0 := TAU * float(i) / 16.0
					var dir := Vector2(sin(a0 + TAU / 32.0), cos(a0 + TAU / 32.0))
					if dir.dot(door) > 0.9 and r_i < 3:
						continue
					var r0 := 1.75 * (1.0 - f0)
					var r1 := 1.75 * (1.0 - f1)
					var p0 := Vector3(cone_c.x + dir.x * r0, g + h * f0 * 0.95, cone_c.y + dir.y * r0)
					var p1 := Vector3(cone_c.x + dir.x * r1, g + h * f1 * 0.95, cone_c.y + dir.y * r1)
					m.block(cone, Transform3D(Basis.looking_at((p1 - p0).normalized(), Vector3(dir.x, 0.0, dir.y)), (p0 + p1) * 0.5),
							Vector3(0.75, 0.12, p0.distance_to(p1) + 0.05))
			await k.step()
			m.commit(cone, skin, "HutSkin")
			k.collider(Vector3(3.0, h * 0.7, 3.0), Transform3D(Basis(), Vector3(cone_c.x, g + h * 0.35, cone_c.y)), "wood")
			if k.region == "sedgemire":
				# the reedman's boat pulled up by his door, turned over, and his eel-traps
				var boat := k.prop("rowboat")
				if boat != "":
					var p := at + across * 3.4 + to_road * 0.8
					await k.step()
					k.place(boat, k.on_ground(p.x, p.y, 0.55), PoiKit.yaw_of(to_road), 0.9, true, Vector3(0.0, 0.0, PI))
				var trap := k.prop("basket")
				if trap != "":
					for i in 3:
						var p := at - across * (2.8 + float(i) * 0.5) + to_road * (0.6 + float(i % 2) * 0.4)
						await k.step()
						k.place(trap, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.1, i == 0, Vector3(PI * 0.5, 0.0, 0.0))
			if k.region == "briarwold":
				# the clamp: a low dome of turf over the stacked wood, smoking at its vents, and the
				# cordwood waiting for the next
				var clamp_c := at + across * 3.8 + to_road * 0.6
				var turf := PoiKit.painted(5, {"base": "#3e3a2a", "accent": "#2d2a1e", "grout": "#1a1810", "unit": 0.3}, 0.6)
				await k.step()
				m.mound(k.on_ground(clamp_c.x, clamp_c.y, -0.2), 1.7, 1.25, turf, "Clamp", true, 1.3, 6, 18)
				await k.step()
				k.puffs(k.on_ground(clamp_c.x, clamp_c.y, 1.1), Vector3(0.9, 0.2, 0.9), 0.5, 14, Color(0.72, 0.7, 0.68, 0.28), 1.4, 6.0)
				var wood := m.begin()
				var stack_c := at - across * 3.4 + to_road * 0.4
				for row in 4:
					for i in 7:
						var p := stack_c + across * (float(i) * 0.24 - 0.72)
						var q := k.on_ground(p.x, p.y, 0.12 + float(row) * 0.23)
						m.rod(wood, Transform3D(Basis(Vector3(across.x, 0.0, across.y).cross(Vector3.UP).normalized(), PI * 0.5), q), 0.11, 1.1)
				await k.step()
				m.commit(wood, k.surface("timber", 0.95), "Cordwood")
	await LAND._grass(d, _verge(k), Vector2.ZERO, 5.5, 20)
	k.marker("the_hut", k.on_ground(at.x + door.x * 2.6, at.y + door.y * 2.6), true)


# --- a crossroads --------------------------------------------------------------------------------

## Where two ways meet out in the country: a fingerpost naming the places down each road, a stone
## at its foot to sit on or leave a coin on, and the region's own mark by it (a Hearthstone-candle
## niche in the Vale, a cairn on the fells, a bell on its stake on the ash).
static func crossroads(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		# too small to be seen from the far ring
		return
	var m := d.masonry
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	var across := Vector2(-to_road.y, to_road.x)
	var at := to_road * 0.5
	if k.root.is_inside_tree():
		var post := Fingerpost.new()
		post.name = "Fingerpost"
		post.position = k.on_ground(at.x, at.y, -0.1)
		k.root.add_child(post)
		k.collider(Vector3(0.16, Fingerpost.POST_H, 0.16), Transform3D(Basis(), k.on_ground(at.x, at.y, Fingerpost.POST_H * 0.5)), "wood")
	# the stone at its foot, and what the last walkers left on it
	var seat := at - to_road * 1.4 + across * 0.7
	var st := m.begin()
	var g := _low(k, seat, 0.5)
	m.block(st, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(to_road) + 0.2), Vector3(seat.x, g + 0.2, seat.y)), Vector3(1.1, 0.8, 0.55))
	await k.step()
	m.commit(st, k.surface("stone", 0.8), "Stone")
	k.collider(Vector3(1.1, 0.8, 0.55), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(to_road) + 0.2), Vector3(seat.x, g + 0.2, seat.y)), "stone")
	var coins := m.begin()
	for i in 3 + k.rng.randi_range(0, 4):
		var c := seat + k.jitter(0.3)
		m.rod(coins, Transform3D(Basis(), Vector3(c.x, g + 0.61, c.y)), 0.03, 0.006)
	await k.step()
	m.commit(coins, PoiKit.plain(PoiKit.BRONZE, 0.35, 0.8), "Coins")
	var mark := at - to_road * 0.6 - across * 1.6
	match k.region:
		"skerrow":
			await _heap(d, mark, 1.1, 0.7, k.rock("boulder"), "Cairn")
		"cinderlea":
			var stake := m.begin()
			var top := _post(d, stake, mark, 1.8, 0.1)
			await k.step()
			m.commit(stake, PoiKit.plain(Color(0.8, 0.79, 0.75), 0.9), "Stake")
			var bell := k.prop("bell_small")
			if bell != "":
				await k.step()
				k.place(bell, top - Vector3(0.0, 0.55, 0.0) + Vector3(to_road.x, 0.0, to_road.y) * 0.1, 0.0, 1.8, false)
		"sedgemire":
			var pole := m.begin()
			var top := _post(d, pole, mark, 2.4, 0.1)
			await k.step()
			m.commit(pole, k.surface("timber", 0.9), "Stake")
			await _cords(d, "Rag", top - Vector3(0.0, 0.2, 0.0), [top - Vector3(0.0, 0.2, 0.0)], [0.02], INDIGO, INDIGO, Vector3(0.1, 0.5, 0.012))
		_:
			var ws := k.prop("milestone")
			if ws != "":
				await k.step()
				k.place(ws, k.on_ground(mark.x, mark.y, -0.1), PoiKit.yaw_of(to_road), 1.2, true)
	await LAND._grass(d, _verge(k), at - to_road * 2.0, 4.0, 16)
	k.marker("the_crossroads", k.on_ground(at.x + to_road.x * 1.0, at.y + to_road.y * 1.0), true)


# --- a peat cut ----------------------------------------------------------------------------------

## Where the fell's peat is cut for the winter: a bank cut square into the moss, the turves laid
## out in rows on the heather to dry and the dry ones stacked, a barrow and a peat-spade stuck in the
## bank, and black water standing in the floor of the cut.
static func peat_cut(d: PoiDressing) -> void:
	var k := d.kit
	if k.far:
		# too small to be seen from the far ring
		return
	var m := d.masonry
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	var across := Vector2(-to_road.y, to_road.x)
	var up := k.uphill()
	var into := up if up != Vector2.ZERO else -to_road
	var yaw := PoiKit.yaw_of(into)
	var b := Basis(Vector3.UP, yaw)
	var peat := PoiKit.painted(5, {"base": "#3a2a1c", "accent": "#2a1e14", "grout": "#150e08", "unit": 0.28}, 0.5)
	# the bank: a face of peat 0.9 m high, 6 m long, cut square, its top the moss
	var bank_c := -into * 0.4
	var gb := _low(k, bank_c, 3.2)
	var hi := k.on_ground(bank_c.x + into.x * 1.2, bank_c.y + into.y * 1.2).y
	var bank_top := maxf(hi, gb + 0.9)
	var bank := m.begin()
	var bank_xf := Transform3D(b, Vector3(bank_c.x, (bank_top + gb - 0.4) * 0.5, bank_c.y) + b * Vector3(0.0, 0.0, 0.7))
	m.block(bank, bank_xf, Vector3(6.0, bank_top - gb + 0.4, 1.4))
	# the cut's floor, a spit lower than the ground before it, and the turves cut from its face
	await k.step()
	m.commit(bank, peat, "Bank")
	k.collider(Vector3(6.0, bank_top - gb + 0.4, 1.4), bank_xf, "dirt")
	var water := m.begin()
	var pool_c := bank_c - into * 0.8
	m.block(water, Transform3D(b, Vector3(pool_c.x, gb + 0.03, pool_c.y)), Vector3(4.6, 0.02, 0.9))
	await k.step()
	m.commit(water, k.still_water(gb - 0.5, Color(0.5, 0.4, 0.3), 0.8), "CutWater")
	# the turves drying, laid in rows on the slope below, and the dry ones footed in little stacks
	var turves := m.begin()
	for row in 3:
		for i in 9:
			var p := bank_c - into * (2.2 + float(row) * 0.9) + across * (float(i) * 0.55 - 2.2)
			var q := k.on_ground(p.x, p.y, 0.05)
			m.block(turves, Transform3D(b * Basis(Vector3.UP, k.rng.randf_range(-0.2, 0.2)), q), Vector3(0.4, 0.1, 0.24))
	for s in 3:
		var p := bank_c - into * 5.0 + across * (float(s) * 1.4 - 1.4)
		var q := k.on_ground(p.x, p.y)
		for j in 5:
			var a := TAU * float(j) / 5.0
			m.block(turves, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.4), q + Vector3(sin(a) * 0.12, 0.2, cos(a) * 0.12)), Vector3(0.26, 0.42, 0.1))
	await k.step()
	m.commit(turves, peat, "Turves")
	var stack := k.prop("peat_stack")
	if stack != "":
		var p := bank_c - into * 1.8 + across * 3.6
		await k.step()
		k.place(stack, k.on_ground(p.x, p.y, -0.05), yaw, 1.0, true)
	var barrow := k.prop("wheelbarrow")
	if barrow != "":
		var p := bank_c - into * 1.6 - across * 3.3
		await k.step()
		k.place(barrow, k.on_ground(p.x, p.y), yaw + 1.2, 1.0, true)
	# the spade stuck in the bank's top
	var spade := m.begin()
	var sp := bank_c + into * 0.6 + across * 1.1
	var sy := k.on_ground(sp.x, sp.y).y
	m.block(spade, Transform3D(b * Basis(Vector3.RIGHT, 0.2), Vector3(sp.x, sy + 0.55, sp.y)), Vector3(0.05, 1.1, 0.05))
	m.block(spade, Transform3D(b * Basis(Vector3.RIGHT, 0.2), Vector3(sp.x, sy - 0.02, sp.y)), Vector3(0.2, 0.3, 0.02))
	await k.step()
	m.commit(spade, k.surface("timber", 0.9), "Spade")
	await LAND._grass(d, "heather", bank_c + into * 3.0, 3.5, 22)
	await LAND._grass(d, "grass_clump", bank_c - into * 3.0, 2.5, 10)
	k.marker("the_cut", k.on_ground(pool_c.x - into.x * 1.0, pool_c.y - into.y * 1.0), true)


# --- a beacon ------------------------------------------------------------------------------------

## A beacon on a rise, laid and not lit: a round of drystone knee high with a cone of cordwood
## stacked on it ready, the pitch in a barrel beside it, and a fire-basket on a pole to carry the
## light up. Where the sentence says it is lit, it burns.
static func beacon(d: PoiDressing) -> void:
	var k := d.kit
	var lit := PoiKit.brief_says(d.brief, ["lit", "burning", "burns"]) and not PoiKit.brief_says(d.brief, ["unlit"])
	var at := Vector2.ZERO
	if k.far:
		if lit:
			k.light(k.on_ground(at.x, at.y, 2.2), Color(1.0, 0.6, 0.3), 3.0, 16.0)
		return
	var m := d.masonry
	var road := _road(d)
	var to_road: Vector2 = road["to_road"]
	var across := Vector2(-to_road.y, to_road.x)
	var g := _low(k, at, 1.8)
	var top := k.on_ground(at.x, at.y).y + 0.55
	var plinth := m.begin()
	await k.step()
	m.drum(plinth, Transform3D(Basis(), Vector3(at.x, g - 0.2, at.y)), 1.7, top - g + 0.2, 0.0, NAN, true)
	await k.step()
	m.commit(plinth, k.surface("stone", 0.7), "Plinth")
	# the round's inside, filled level with its top
	await k.step()
	m.mound(Vector3(at.x, top - 0.3, at.y), 1.62, 0.32, k.surface("earth", 0.6), "Hearth", false, 3.0, 4, 20)
	k.collider(Vector3(3.0, 0.3, 3.0), Transform3D(Basis(), Vector3(at.x, top - 0.1, at.y)), "stone")
	# the cone of cordwood, leant in to a point
	var wood := m.begin()
	var apex := Vector3(at.x, top + 2.1, at.y)
	for i in 22:
		var a := TAU * float(i) / 22.0 + k.rng.randf_range(-0.05, 0.05)
		var foot := Vector3(at.x + sin(a) * 1.1, top, at.y + cos(a) * 1.1)
		var tip := apex + Vector3(sin(a) * 0.12, k.rng.randf_range(-0.2, 0.1), cos(a) * 0.12)
		m.block(wood, Transform3D(Basis.looking_at((tip - foot).normalized(), Vector3.UP), (foot + tip) * 0.5), Vector3(0.12, 0.12, foot.distance_to(tip)))
	await k.step()
	m.commit(wood, k.surface("timber", 0.95), "Stack")
	k.collider(Vector3(1.8, 2.0, 1.8), Transform3D(Basis(), Vector3(at.x, top + 1.0, at.y)), "wood")
	# the fire-basket on its pole, and the pitch
	var pole := m.begin()
	var pole_at := at + to_road * 2.6 + across * 1.2
	var pole_top := _post(d, pole, pole_at, 3.4, 0.14)
	await k.step()
	m.commit(pole, k.surface("timber", 0.9), "Pole")
	var basket := k.prop("brazier")
	if basket != "":
		await k.step()
		k.place(basket, pole_top - Vector3(0.0, 0.05, 0.0), 0.0, 0.9, false)
	var barrel := k.prop("barrel")
	if barrel != "":
		var p := at + to_road * 2.4 - across * 1.4
		await k.step()
		k.place(barrel, k.on_ground(p.x, p.y, -0.05), k.rng.randf_range(0.0, TAU), 0.9, true)
	if lit:
		k.light(apex - Vector3(0.0, 0.9, 0.0), Color(1.0, 0.6, 0.3), 3.0, 16.0)
		await k.step()
		k.puffs(apex, Vector3(0.6, 0.2, 0.6), 2.2, 20, Color(0.35, 0.33, 0.32, 0.4), 2.0, 5.0)
	await LAND._grass(d, _verge(k), at, 5.5, 20)
	k.marker("the_beacon", k.on_ground(to_road.x * 3.2, to_road.y * 3.2), true)
