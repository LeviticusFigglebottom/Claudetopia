extends RefCounted
## The kinds of place the drawn map asked the kit for next (docs/ATLAS.md, section 10), which it
## had been faking out of the kinds it had: a cave's mouth in a slope, the worked land out between
## the villages -- a farmstead, a mill, a quarry, a shieling and its fold, a market field -- and
## the marks along a road, a waystone and a place to stop and look.
##
## Each is built out of the forge's props and rock, the POI kit's masonry, and where somebody lives
## or works under a roof, the settlements' own fabric (`HouseKit`, in the region's surfaces through
## `Settlement.fabric_material`), so a farmstead in the Vale is cob and thatch like the Vale's
## villages and a shieling on the fells is Skerrow's drystone.
##
## **No `class_name`**, for the reason `poi_builders.gd` has none: every builder takes a
## `PoiDressing`, and that script names its builders by path. `poi_builders.gd` preloads this.


## The way the wind blows, as the smoke leans and the grass bends (Atmosphere's `wm_wind_dir`).
const WIND := Vector2(0.8, 0.6)


# --- shared hands --------------------------------------------------------------------------------

## A building's frame standing on the ground at local `c`, its front toward `face`: origin on the
## ground at the middle of its footprint, x along its front, -z out of its door (HouseKit's frame).
## The ground under it is its low corner's, so no corner floats on a slope.
static func _frame(d: PoiDressing, c: Vector2, face: Vector2, w: float, depth: float) -> Transform3D:
	var k := d.kit
	var v := -face.normalized()
	var u := Vector2(v.y, -v.x)
	var low := INF
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := c + u * (w * 0.5 * float(sx)) + v * (depth * 0.5 * float(sz))
			low = minf(low, k.on_ground(p.x, p.y).y)
	var y := minf(k.on_ground(c.x, c.y).y, low + 0.25)
	return Transform3D(Basis(Vector3(u.x, 0.0, u.y), Vector3.UP, Vector3(v.x, 0.0, v.y)), Vector3(c.x, y, c.y))


## A building of the region's own kind at `at` (see `_frame`), `w` along its front and `depth`
## back, built into `fabric`: a body to bump into, and smoke from its chimneys when somebody is in.
## `style` is a HouseKit.STYLES row, or empty for the region's usual. Returns HouseKit.build's
## answer (door, chimneys, body).
static func _house(d: PoiDressing, fabric: FabricMesh, at: Transform3D, w: float, depth: float,
		storeys: int, style: Dictionary = {}, home := true) -> Dictionary:
	var k := d.kit
	var row := style if not style.is_empty() else HouseKit.pick_style(k.culture, k.rng)
	var lights := RandomNumberGenerator.new()
	lights.seed = k.rng.randi()
	var spec := {"w": w, "d": depth, "storeys": storeys, "culture": k.culture, "style": row,
			"tint": HouseKit.pick_tint(row, k.rng), "stone": Color(0.95, 0.95, 0.93),
			"roof": Building.ROOF_BY_CULTURE.get(k.culture, Building.ROOF_BY_CULTURE["vale"]),
			"standing": true, "home": home, "trade": ""}
	var made := HouseKit.build(fabric, at, spec, k.rng, lights)
	var body: Array = made["body"]
	if body.size() == 2:
		k.collider(body[1], Transform3D(at.basis, body[0]), "stone")
	if home:
		for top in made["chimneys"]:
			k.puffs((top as Vector3) + Vector3(0.0, 0.3, 0.0), Vector3(0.15, 0.1, 0.15), 0.9, 10,
					Color(0.82, 0.8, 0.78, 0.32), 1.3, 5.0)
	return made


## Commits what was built into `fabric` under the dressing, each key in the region's own surface
## the way a settlement commits its own. The far ring keeps the walls and roofs, drawn to the far
## range, and nothing smaller.
static func _commit_fabric(d: PoiDressing, fabric: FabricMesh) -> void:
	var k := d.kit
	for key in ["wall", "wall_alt", "roof", "stone", "drystone", "coping", "joinery"]:
		var small: bool = key in ["coping", "joinery"]
		if k.far and small:
			continue
		var node_name := "Fabric" + str(key).capitalize().replace(" ", "")
		var inst := fabric.commit(d, key, Settlement.fabric_material(k.culture, key), node_name)
		if inst == null:
			continue
		if k.far:
			k._far_range(inst)
		elif key == "joinery":
			FabricMesh.near_only(inst, FabricMesh.JOINERY_RANGE_M, false)
		elif key == "coping":
			FabricMesh.near_only(inst, Settlement.COPING_RANGE_M, true)


## A drystone wall from `a` to `b` (local xz), `h` high, laid into `fabric` the way the villages
## lay theirs -- two courses stepped in, and a coping of stones on edge -- with a body along it.
static func _dry_wall(d: PoiDressing, fabric: FabricMesh, a: Vector2, b: Vector2, h := 1.1) -> void:
	var k := d.kit
	var length := a.distance_to(b)
	if length < 0.4:
		return
	var dir := (b - a) / length
	var yaw := atan2(-dir.y, dir.x)
	var n := maxi(1, int(ceil(length / 3.0)))
	for i in range(n):
		var q0 := a + dir * (length * float(i) / float(n))
		var q1 := a + dir * (length * float(i + 1) / float(n))
		var p0 := k.on_ground(q0.x, q0.y)
		var p1 := k.on_ground(q1.x, q1.y)
		var mid := (p0 + p1) * 0.5
		var seg := p0.distance_to(p1) + 0.12
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, atan2(p1.y - p0.y, Vector2(p1.x - p0.x, p1.z - p0.z).length()))
		var tint := Color(0.93, 0.935, 0.94).darkened(k.rng.randf_range(0.0, 0.1))
		fabric.box("drystone", Transform3D(basis, mid + Vector3(0.0, h * 0.3 - 0.1, 0.0)), Vector3(seg, h * 0.6 + 0.2, 0.62), tint)
		fabric.box("drystone", Transform3D(basis, mid + Vector3(0.0, h * 0.74, 0.0)), Vector3(seg, h * 0.3, 0.48), tint)
		var stones := int(seg / 0.19)
		for s in range(stones):
			var q := p0.lerp(p1, (float(s) + 0.5) / float(stones))
			var lean := Basis(Vector3.UP, yaw + k.rng.randf_range(-0.12, 0.12)) * Basis(Vector3.BACK, k.rng.randf_range(-0.38, 0.38))
			var tall := h * 0.15 + k.rng.randf_range(0.0, 0.1)
			fabric.box("coping", Transform3D(lean, q + Vector3(0.0, h * 0.9 + tall * 0.3, 0.0)),
					Vector3(k.rng.randf_range(0.15, 0.22), tall, k.rng.randf_range(0.34, 0.44)), tint.darkened(k.rng.randf_range(0.04, 0.2)))
	var c := (a + b) * 0.5
	k.collider(Vector3(length, h + 0.2, 0.62), Transform3D(Basis(Vector3.UP, yaw), k.on_ground(c.x, c.y, h * 0.5)), "stone")


## A post-and-rail fence from `a` to `b`, `h` high, into `fabric`'s joinery, with a body along it.
static func _rails(d: PoiDressing, fabric: FabricMesh, a: Vector2, b: Vector2, h := 1.15) -> void:
	var k := d.kit
	var length := a.distance_to(b)
	if length < 0.4:
		return
	var dir := (b - a) / length
	var yaw := atan2(-dir.y, dir.x)
	var n := maxi(1, int(ceil(length / 2.6)))
	var timber := Color(0.58, 0.46, 0.32)
	var feet: Array[Vector3] = []
	for i in range(n + 1):
		var q := a + dir * (length * float(i) / float(n))
		var p := k.on_ground(q.x, q.y)
		feet.append(p)
		fabric.box("joinery", Transform3D(Basis(Vector3.UP, yaw + k.rng.randf_range(-0.06, 0.06)), p + Vector3(0.0, h * 0.5, 0.0)),
				Vector3(0.14, h + 0.1, 0.14), FabricMesh.shade(timber, k.rng.randf_range(0.7, 0.85)))
	for i in range(n):
		var p0 := feet[i]
		var p1 := feet[i + 1]
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, atan2(p1.y - p0.y, Vector2(p1.x - p0.x, p1.z - p0.z).length()))
		for y in [h * 0.42, h * 0.84]:
			fabric.box("joinery", Transform3D(basis, (p0 + p1) * 0.5 + Vector3(0.0, float(y), 0.0)),
					Vector3(p0.distance_to(p1) + 0.1, 0.1, 0.07), FabricMesh.shade(timber, k.rng.randf_range(0.85, 1.05)))
	var c := (a + b) * 0.5
	k.collider(Vector3(length, h, 0.2), Transform3D(Basis(Vector3.UP, yaw), k.on_ground(c.x, c.y, h * 0.5)), "wood")


## Grass or flowers of the region scattered over a disc, no shadow and no body.
static func _grass(d: PoiDressing, kind: String, c: Vector2, r: float, count: int) -> void:
	var k := d.kit
	var path := k.flora(kind)
	if path == "":
		return
	var tufts: Array = []
	for i in count:
		var a := k.rng.randf_range(0.0, TAU)
		var rr := sqrt(k.rng.randf()) * r
		var p := c + Vector2(sin(a), cos(a)) * rr
		tufts.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
	k.scatter(path, tufts, false, false, false)


## The region's own grass for a verge or a field: grey grass on the ash, the Vale's clumps
## elsewhere (the forge falls back to them where a region has none of its own).
static func _verge(d: PoiDressing) -> String:
	return "grey_grass" if d.kit.region == "cinderlea" else "grass_clump"


## Where the view is from here: the way the ground falls away furthest over the next few hundred
## metres (the lowest ground along the bearing, on average), or the grain where it falls nowhere.
static func _view(d: PoiDressing) -> Vector2:
	var k := d.kit
	var h0 := k.on_ground(0.0, 0.0).y
	var best := -INF
	var dir := Vector2.ZERO
	for a in range(0, 360, 10):
		var u := Vector2(sin(deg_to_rad(a)), cos(deg_to_rad(a)))
		var drop := 0.0
		for r in [40.0, 90.0, 160.0, 260.0, 400.0]:
			drop += h0 - k.on_ground(u.x * float(r), u.y * float(r)).y
		if drop > best:
			best = drop
			dir = u
	return dir if best > 4.0 else k.grain()


# --- a waystone ----------------------------------------------------------------------------------

## One stone at the side of the road, with the notches the pilgrims cut in it, one for each time
## they have passed it, and a stone bowl at its foot for the coins they leave. The pilgrims' road
## counts its waystones, so each one is somewhere a walker stops.
static func waystone(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var along := k.road_direction(30.0)
	if along == Vector2.ZERO:
		along = k.grain()
	# it stands a pace off the road, broad face to the walker
	var side := Vector2(-along.y, along.x)
	var at := side * 1.6
	var yaw := PoiKit.yaw_of(-side)
	var path := k.prop("milestone")
	var scale := 1.55
	# the stone's two broad faces, front and back, from what the forge measured of it
	var faces := [0.18 * scale, -0.18 * scale]
	var height := 1.4
	var broken := PoiKit.brief_says(d.brief, ["broken"])
	if path != "":
		height = PoiKit.height_of(path) * scale
		if broken:
			# a stump of it standing, half its height, and the top lying where it fell at its foot,
			# face up, so the cut words on it can still be read
			k.place(path, k.on_ground(at.x, at.y, -height * 0.5), yaw, scale, true, Vector3(0.0, 0.0, k.rng.randf_range(-0.06, 0.06)), true)
			var fell := at - side * 1.1 + along * 0.4
			var top := k.place(path, k.on_ground(fell.x, fell.y, 0.18), yaw + k.rng.randf_range(0.3, 0.7), scale * 0.95, true,
					Vector3(-PI * 0.5 + 0.08, 0.0, 0.0), false)
			if top != null:
				top.name = "FallenTop"
			height *= 0.5
		else:
			k.place(path, k.on_ground(at.x, at.y), yaw, scale, true, Vector3.ZERO, true)
		var bounds: Dictionary = PoiKit.meta(path).get("bounds", {})
		var lo: Array = bounds.get("min", [])
		var hi: Array = bounds.get("max", [])
		if lo.size() == 3 and hi.size() == 3:
			faces = [float(hi[2]) * scale, float(lo[2]) * scale]
	else:
		var st := m.begin()
		m.block(st, Transform3D(Basis(Vector3.UP, yaw), k.on_ground(at.x, at.y, height * 0.5)), Vector3(0.6, height, 0.36 * scale))
		m.commit(st, k.surface("stone", 0.7), "Waystone", true)
		k.collider(Vector3(0.6, height, 0.36 * scale), Transform3D(Basis(Vector3.UP, yaw), k.on_ground(at.x, at.y, height * 0.5)), "stone")
	# the tally: a nick cut into both broad faces for every crossing, in rows down the stone
	var nicks := m.begin()
	var count := 7 + k.rng.randi_range(0, 11)
	var basis := Basis(Vector3.UP, yaw)
	var foot := k.on_ground(at.x, at.y)
	for i in count:
		var row := floori(float(i) / 6.0)
		var col := i % 6
		var y := height * 0.78 - float(row) * 0.13
		if y < height * 0.3:
			break
		for face in faces:
			var out := float(face) + (0.004 if float(face) > 0.0 else -0.004)
			var p := foot + basis * Vector3(-0.15 + float(col) * 0.06, y, out)
			m.block(nicks, Transform3D(basis * Basis(Vector3.BACK, k.rng.randf_range(-0.2, 0.2)), p), Vector3(0.018, 0.1, 0.012))
	m.commit(nicks, PoiKit.plain(Color(0.13, 0.12, 0.11), 0.95), "Notches")
	# the bowl at its foot, hollowed, with what the last walkers left in it
	var bowl_at := at - side * 0.75 + along * 0.2
	var bowl := m.begin()
	m.drum(bowl, Transform3D(Basis(), k.on_ground(bowl_at.x, bowl_at.y, -0.05)), 0.32, 0.26, 0.0, NAN, false, 0.13)
	m.commit(bowl, k.surface("stone", 0.8), "Bowl")
	var coins := m.begin()
	for i in 4 + k.rng.randi_range(0, 5):
		var c := bowl_at + k.jitter(0.14)
		m.rod(coins, Transform3D(Basis(Vector3.RIGHT, k.rng.randf_range(-0.3, 0.3)), k.on_ground(c.x, c.y, 0.2 + k.rng.randf_range(0.0, 0.03))), 0.03, 0.006)
	m.commit(coins, PoiKit.plain(PoiKit.BRONZE, 0.35, 0.8), "Coins")
	k.marker("the_bowl", k.on_ground(bowl_at.x, bowl_at.y))
	# a worn place where walkers stop, and the verge grown round it
	_grass(d, _verge(d), at, 4.0, 18)


# --- a vista ---------------------------------------------------------------------------------------

## A place where the view is the point: a bench on the edge, turned to the country below, and the
## cairn walkers add a stone to. `cairn` in the sentence and there is no bench.
static func vista(d: PoiDressing) -> void:
	var k := d.kit
	var view := _view(d)
	var yaw := PoiKit.yaw_of(view)
	var edge := view * minf(d.pad_radius * 0.5, 7.0)
	var only_cairn := PoiKit.brief_says(d.brief, ["cairn"]) and not PoiKit.brief_says(d.brief, ["bench"])
	var across := Vector2(-view.y, view.x)
	if not only_cairn:
		# The seat: a bench on a plinth of flags, with a length of drystone wall at its back to keep
		# the wind off, in a worn clearing. A bench alone is a plank half a metre high, and in the
		# grass on the edge it was not there at ten metres; the wall and the flags are.
		var m := d.masonry
		var clearing := PoiKit.painted(5, k._spec("earth"), 0.9, 0.7)
		m.mound(k.on_ground(edge.x - view.x * 0.4, edge.y - view.y * 0.4, -0.12), 3.4, 0.16, clearing, "Clearing", false, 2.2, 4, 16, false, 0.03)
		var flags := m.begin()
		var g := k.on_ground(edge.x, edge.y).y
		for sx in [-1.0, 0.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var q := edge + across * (float(sx) * 0.95) + view * (float(sz) * 0.5)
				var top := maxf(g, k.on_ground(q.x, q.y).y) + 0.22
				var xf := Transform3D(Basis(Vector3.UP, yaw + k.rng.randf_range(-0.05, 0.05)), Vector3(q.x, top - 0.3, q.y))
				m.block(flags, xf, Vector3(0.92 + k.rng.randf_range(-0.05, 0.05), 0.6, 0.97))
		m.commit(flags, k.surface("stone", 0.6), "Plinth", true)
		var plinth_top := g + 0.22
		k.collider(Vector3(2.9, 0.6, 2.0), Transform3D(Basis(Vector3.UP, yaw), Vector3(edge.x, plinth_top - 0.3, edge.y)), "stone")
		var bench := k.prop("bench")
		if bench != "":
			# the bench's seat faces its -z, so its back is to the ground behind and its front to the view
			k.place(bench, Vector3(edge.x, plinth_top, edge.y), yaw + PI, 1.15, true, Vector3.ZERO, true)
		var fabric := FabricMesh.new()
		var back := edge - view * 1.35
		_dry_wall(d, fabric, back - across * 1.8, back + across * 1.8, 1.05)
		_commit_fabric(d, fabric)
		k.marker("the_view", Vector3(edge.x - view.x * 0.6, plinth_top, edge.y - view.y * 0.6), true)
	# the cairn: stones heaped by everybody who stopped, the biggest at the foot, as tall as a man
	var cairn_at := edge + across * (3.2 if not only_cairn else 0.0)
	var stones: Array = []
	var tiers := 8
	for t in tiers:
		var r := 0.9 * (1.0 - float(t) / float(tiers)) + 0.12
		var n := maxi(1, int(round(7.0 * (1.0 - float(t) / float(tiers)))))
		for i in n:
			var a := TAU * float(i) / float(n) + k.rng.randf_range(-0.3, 0.3) + float(t)
			var p := cairn_at + Vector2(sin(a), cos(a)) * r * k.rng.randf_range(0.6, 1.0)
			stones.append(PoiKit.transform_at(k.on_ground(p.x, p.y, 0.14 + float(t) * 0.22), k.rng.randf_range(0.0, TAU),
					k.rng.randf_range(0.16, 0.24) * (1.0 - float(t) * 0.06),
					Vector3(k.rng.randf_range(-0.3, 0.3), 0.0, k.rng.randf_range(-0.3, 0.3))))
	k.scatter(k.rock("boulder"), stones, true, true)
	if only_cairn:
		k.marker("the_view", k.on_ground(cairn_at.x - view.x * 1.8, cairn_at.y - view.y * 1.8), true)
	# the verge behind, where nobody sits, and the flowers round the cairn's foot, not the seat's
	_grass(d, _verge(d), -view * 9.0, d.pad_radius * 0.4, 26)
	_grass(d, "heather" if k.region == "skerrow" else ("foxglove" if k.region == "briarwold" else "cow_parsley"),
			cairn_at + across * 1.6, 2.4, 12)


# --- a cave --------------------------------------------------------------------------------------

## A mouth in a slope or a cliff, four to eight metres high, and dark going in ten. The hill is
## a heightmap and cannot be holed, so the mouth is in a shoulder of rock that stands out from the
## slope, facing downhill, deep enough for the dark to go back into: its throat is a passage of the
## rock's own stone darkening to black at ten metres. In Skerrow the rock is limestone, pale and in
## beds; in the Briarwold it is a root-cave, the roots of the tree above arching over the mouth; by
## the sea it is a sea-cave, with the tide's pool in its mouth.
static func cave(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.downhill()
	if face == Vector2.ZERO:
		face = k.grain()
	# the cave's own frame: +z runs into the hill, x across the mouth
	var into := -face
	var basis := Basis(Vector3.UP, PoiKit.yaw_of(into))
	var across := Vector2(into.y, -into.x)
	var roots := k.region == "briarwold" or PoiKit.brief_says(d.brief, ["root"])
	var sea := PoiKit.brief_says(d.brief, ["sea", "tide", "surf", "hushline"]) or k.water_direction(40.0) != Vector2.ZERO
	# A mouth three to four and a half metres high: the slope rises two or three metres in the ten
	# the throat goes in, and a mouth of eight stood a box of dark out of the hill that no rock
	# round it could hide.
	var high := 3.0 + k.rng.randf_range(0.0, 1.6)
	var wide := high * k.rng.randf_range(0.8, 1.05)
	var deep := 10.0
	# the mouth stands a little uphill of the middle, its floor on the ground there
	var mouth := into * 3.0
	var o := k.on_ground(mouth.x, mouth.y)
	# The throat: floor, walls and roof of the passage, ring by ring back into the hill, each ring's
	# floor on the ground there (so the hill never rises through it) and each darker than the last,
	# black at ten metres. It is the dark of the cave; the rock round it is the forge's own.
	var rings := 5
	var floors: Array[float] = []
	var hh_last := high
	for i in rings:
		var t0 := float(i) / float(rings)
		var t1 := float(i + 1) / float(rings)
		var z0 := 0.8 + t0 * deep
		var z1 := 0.8 + t1 * deep
		var mid := (z0 + z1) * 0.5
		var span := z1 - z0 + 0.05
		var at := mouth + into * mid
		var g := k.on_ground(at.x, at.y).y
		if not floors.is_empty():
			g = maxf(g, floors[-1])
		floors.append(g)
		var hh := high * (1.0 - t0 * 0.45)
		hh_last = hh
		var ww := wide * (1.0 - t0 * 0.35)
		var base := Vector3(o.x, g, o.z)
		var lining := m.begin()
		m.block(lining, Transform3D(basis, base + basis * Vector3(0.0, -0.2, mid)), Vector3(ww + 0.6, 0.4, span))
		m.block(lining, Transform3D(basis, base + basis * Vector3(0.0, hh + 0.35, mid)), Vector3(ww + 1.2, 0.7, span))
		for s in [-1.0, 1.0]:
			m.block(lining, Transform3D(basis, base + basis * Vector3(float(s) * (ww * 0.5 + 0.35), hh * 0.5, mid)), Vector3(0.7, hh + 0.6, span))
			k.collider(Vector3(0.7, hh + 0.6, span), Transform3D(basis, base + basis * Vector3(float(s) * (ww * 0.5 + 0.35), hh * 0.5, mid)), "stone")
		var dark := lerpf(0.26, 0.02, t1)
		m.commit(lining, PoiKit.plain(Color(dark, dark * 0.97, dark * 0.92), 0.95), "Throat%d" % i)
		k.collider(Vector3(ww + 0.6, 0.4, span), Transform3D(basis, base + basis * Vector3(0.0, -0.2, mid)), "stone")
	var g_end: float = floors[-1]
	var back := m.begin()
	m.block(back, Transform3D(basis, Vector3(o.x, g_end, o.z) + basis * Vector3(0.0, hh_last * 0.5, deep + 0.75)), Vector3(wide + 1.2, hh_last + 0.8, 0.3))
	m.commit(back, PoiKit.plain(Color(0.01, 0.01, 0.012), 1.0), "ThroatEnd", true)
	k.collider(Vector3(wide, hh_last + 0.4, 0.4), Transform3D(basis, Vector3(o.x, g_end, o.z) + basis * Vector3(0.0, hh_last * 0.5, deep + 0.75)), "stone")
	# The crag the mouth is cut into, of the region's own rock and nothing squared: boulders of
	# every size, each turned and canted its own way so no two faces agree, sunk into the slope so
	# the hill closes over their feet. Either side of the mouth a cheek rises in three steps up the
	# slope, two capstones lie across the top resting on the throat's roof, and a brow stands back
	# into the hill above them, so the mouth is a cleft in rock the hill breaks into and not a
	# thing stood on the grass. Two leaning slabs read as a tent, and a lintel as a doorway.
	_crag(d, mouth, into, across, o, high, wide)
	# over the passage, standing on its roof, so the hill has a crag where the passage runs
	for i in rings:
		var z := 0.8 + (float(i) + 0.5) * deep / float(rings)
		var hh := high * (1.0 - float(i) / float(rings) * 0.45)
		var at := mouth + into * z + across * k.rng.randf_range(-0.8, 0.8)
		var path := k.rock("boulder")
		if path == "":
			break
		var bh := maxf(PoiKit.height_of(path), 1.0)
		var sc := (wide + 4.0) / (bh * 1.3)
		var roof: float = floors[i] + hh + 0.7
		k.place(path, Vector3(at.x, maxf(roof - 0.3, k.on_ground(at.x, at.y).y - bh * sc * 0.55), at.y),
				k.rng.randf_range(0.0, TAU), sc, true, Vector3(k.rng.randf_range(-0.2, 0.2), 0.0, k.rng.randf_range(-0.2, 0.2)), true)
	# along the flanks, stepping down into the slope
	for s in [-1.0, 1.0]:
		for z in [0.5, 4.0]:
			var path := k.rock("boulder")
			if path == "":
				break
			var bh := maxf(PoiKit.height_of(path), 1.0)
			var at := mouth + across * float(s) * (wide * 0.5 + 5.0 + k.rng.randf_range(0.0, 1.5)) + into * float(z)
			var sc := k.rng.randf_range(1.2, 2.0)
			k.place(path, k.on_ground(at.x, at.y, -bh * sc * 0.4), k.rng.randf_range(0.0, TAU), sc, true,
					Vector3(k.rng.randf_range(-0.25, 0.25), 0.0, k.rng.randf_range(-0.25, 0.25)), true)
	# Light back off the ground in front of the mouth. With the sun behind the hill the crag's faces
	# are in its shadow, and in the painted grade a shadow that has nothing to lift it goes black,
	# so the mouth read as a hole cut in the frame. A bounce is a real light by day and no glow.
	var bounce := mouth - into * 5.0
	k.bounce_light(k.on_ground(bounce.x, bounce.y, 3.2), _bounce_colour(k.region), 2.6, 16.0)
	# where whatever lives in it waits, a little way in out of the light
	var den := mouth + into * 3.5
	k.marker("the_mouth", Vector3(den.x, floors[1], den.y), false, true, wide * 0.5)
	# the fall of rock at its foot
	var scree := k.rock("scree")
	if scree != "":
		var heap: Array = []
		for i in 8:
			var p := mouth - into * k.rng.randf_range(1.5, 6.0) + across * k.rng.randf_range(-wide, wide)
			heap.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.1), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.6, 1.1)))
		k.scatter(scree, heap, true)
	var boulder := k.rock("boulder")
	if boulder != "":
		var small: Array = []
		for i in 5:
			var p := mouth - into * k.rng.randf_range(2.5, 7.0) + across * k.rng.randf_range(-wide * 1.2, wide * 1.2)
			small.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.2), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.3, 0.6)))
		k.scatter(boulder, small, true, true)
	if roots:
		# the roots of what grows on the hill above, down over the brow and into the ground
		var wood := m.begin()
		for i in 5:
			# down the outsides of the cheeks and over their shoulders, never across the mouth
			var side := -1.0 if i % 2 == 0 else 1.0
			var x := side * (wide * 0.5 + k.rng.randf_range(0.6, 2.4))
			var top := o + basis * Vector3(x * 0.7, high + 3.0, 1.8)
			var bend := o + basis * Vector3(x, high * 0.7, -1.2)
			var q := mouth + across * (x * 1.2) - into * 1.8
			m.limb(wood, top, bend, k.rng.randf_range(0.1, 0.22))
			m.limb(wood, bend, k.on_ground(q.x, q.y), k.rng.randf_range(0.08, 0.16))
		m.commit(wood, k.surface("timber", 0.7), "Roots", true)
		_grass(d, "fern", mouth - into * 2.0, 6.0, 20)
	if sea:
		# The tide's pool in the mouth and out past it, with a bar of pale shell-sand the tide
		# leaves at its edge and the surf breaking on it. On Cinderlea's black ash, dark rock over
		# dark ground was a hole in the frame; the sky in the water and the pale sand are what the
		# mouth is seen by.
		var pool_at := mouth - into * 1.2
		var sand_at := mouth - into * (wide * 0.55 + 2.4)
		var sand := PoiKit.painted(5, {"base": "#bdb5a2", "accent": "#a39a86", "grout": "#7d7564", "unit": 0.18}, 0.7)
		m.mound(k.on_ground(sand_at.x, sand_at.y, -0.15), wide * 0.9 + 1.5, 0.35, sand, "ShellSand", false, 1.4, 5, 18, false, 0.05)
		m.pool(pool_at, wide * 0.75, o.y - 0.1, k.still_water(-1.2, Color(1.0, 1.05, 1.08), 0.55), "TidePool")
		var surf := Vector3(sand_at.x, o.y + 0.1, sand_at.y) + Vector3(into.x, 0.0, into.y) * 1.2
		k.puffs(surf, Vector3(wide * 0.6, 0.15, 0.6), 0.3, 18, Color(0.96, 0.98, 1.0, 0.45), 1.4, 2.4)
	else:
		_grass(d, _verge(d), mouth - into * 6.0, 7.0, 16)


## The rock a cave's mouth is cut into (see `cave`): the cheeks either side, stepping up the slope,
## the capstones over the mouth resting on the throat's roof, and the brow standing back into the
## hill. Every piece is its own boulder, turned and canted its own way, so its faces are broken and
## no two agree; each is sunk so the slope closes over its foot, and none stands clear of the ground.
static func _crag(d: PoiDressing, mouth: Vector2, into: Vector2, across: Vector2, o: Vector3,
		high: float, wide: float) -> void:
	var k := d.kit
	# [across (in the mouth's half-widths past its edge), into, top over the mouth's floor, height as
	# a share of the mouth's, whether it rests on the roof rather than the ground]
	var pieces: Array = []
	for s in [-1.0, 1.0]:
		pieces.append([float(s), 0.6, high * 0.95, 1.05, false])
		pieces.append([float(s) * 1.5, 3.2, high + 1.0, 0.85, false])
		pieces.append([float(s) * 1.9, -1.4, high * 0.45, 0.55, false])
	pieces.append([-0.35, 1.3, high + 1.6, 0.55, true])
	pieces.append([0.4, 2.2, high + 1.8, 0.6, true])
	pieces.append([0.0, 5.0, high + 2.6, 0.9, false])
	for piece in pieces:
		var path := k.rock("boulder")
		if path == "":
			return
		var bh := maxf(PoiKit.height_of(path), 1.0)
		var bw := maxf(PoiKit.half_width_of(path), 0.8)
		var sc := high * float(piece[3]) / bh * k.rng.randf_range(0.9, 1.15)
		var x := float(piece[0])
		var off := 0.0
		if absf(x) >= 1.0:
			# a cheek: its inner face at the mouth's edge, its bulges a little into it, so the cleft
			# is ragged and still open
			off = signf(x) * (wide * 0.5 + bw * sc * (0.95 + (absf(x) - 1.0) * 0.7))
		else:
			off = x * wide
		var at := mouth + across * off + into * float(piece[1])
		var g := k.on_ground(at.x, at.y).y
		var y := o.y + float(piece[2]) - bh * sc
		if bool(piece[4]):
			y = maxf(y, o.y + high - 0.3)
		else:
			# never standing on the grass: at least a quarter of it is under the slope
			y = minf(y, g - bh * sc * 0.25)
		# and never under it altogether
		y = maxf(y, g + 0.6 - bh * sc)
		var tilt := Vector3(k.rng.randf_range(-0.3, 0.3), 0.0, k.rng.randf_range(-0.3, 0.3))
		k.place(path, Vector3(at.x, y, at.y), k.rng.randf_range(0.0, TAU), sc, true, tilt, true)


## A quarry's spoil in the rock's own colours: the cut face's look (`face`) gone halfway to the
## region's earth, since the spoil is the rock broken small with the soil it came off with.
static func _spoil_look(k: PoiKit, face: Dictionary) -> Dictionary:
	var earth := k._spec("earth")
	var out := {"unit": 0.3}
	for key in ["base", "accent", "grout"]:
		var rock := Color.html(str(face.get(key, "#999999")))
		var soil := Color.html(str(earth.get(key, "#555555")))
		out[key] = "#" + rock.lerp(soil, 0.45).darkened(0.08).to_html(false)
	return out


## The light a mouth's surroundings throw back into it: the grey of the ash, the green of the
## wood, the pale of limestone, the warm of the Vale's earth.
static func _bounce_colour(region: String) -> Color:
	match region:
		"cinderlea":
			return Color(0.86, 0.82, 0.78)
		"skerrow":
			return Color(0.86, 0.88, 0.9)
		"briarwold":
			return Color(0.76, 0.86, 0.7)
		"sedgemire":
			return Color(0.8, 0.86, 0.78)
	return Color(0.92, 0.86, 0.74)


# --- a quarry ------------------------------------------------------------------------------------

## A face cut back into the hill, white where it is chalk and grey where it is flint or slate,
## with the blocks it gives up lying squared on the floor, a spoil heap of what was no use, and a
## crane of timber to lift them onto the carts.
static func quarry(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var face := k.downhill()
	if face == Vector2.ZERO:
		face = k.grain()
	var side := Vector2(face.y, -face.x)
	var chalk := k.region == "hearthvale" or PoiKit.brief_says(d.brief, ["chalk", "white"])
	var look := {"base": "#e6e2d6", "accent": "#cfc9b8", "grout": "#a39c88", "unit": 0.7} if chalk \
			else {"base": "#9a9892", "accent": "#7d7b76", "grout": "#55544f", "unit": 0.6}
	if PoiKit.brief_says(d.brief, ["flint"]):
		look = {"base": "#bdb8ac", "accent": "#5e5a55", "grout": "#3b3935", "unit": 0.22}
	# cut rock, one stone: the plaster's mottle and hairline cracks, not the courses of a wall
	var stone := PoiKit.painted(0, look, 0.8, 0.8)
	var turf := PoiKit.painted(5, {"base": "#5d6a3c", "accent": "#46522c", "grout": "#2f3a1d", "unit": 0.3}, 0.6)
	# The face: an arc of cut benches stepping back into the slope, behind the floor. A bench stands
	# no prouder than the hill a pace behind it, with the turf over its lip, so the face is the hill
	# cut back and not a wall stood in front of it; where the hill does not rise, there is no bench.
	var arc_r := minf(d.pad_radius * 0.75, 16.0)
	var centre := face * 2.0
	var cut := m.begin()
	var lips := m.begin()
	var floor_y := k.on_ground(centre.x, centre.y).y
	var benches := 3
	var bench_h := 3.2
	var n := 9
	var lower: Array[float] = []
	lower.resize(n)
	lower.fill(floor_y)
	for b in benches:
		var r := arc_r + float(b) * 2.6
		for i in n:
			var a0 := -1.25 + 2.5 * float(i) / float(n)
			var a1 := -1.25 + 2.5 * float(i + 1) / float(n)
			var am := (a0 + a1) * 0.5
			var dir := (-face).rotated(am)
			var p := centre + dir * r
			var behind := p + dir * 2.0
			var top := minf(floor_y + bench_h * float(b + 1) + k.rng.randf_range(-0.3, 0.3),
					k.on_ground(behind.x, behind.y).y + 0.6)
			if b == 0:
				# the first bench is cut however level the ground: a pit, if nothing else
				top = maxf(top, floor_y + 1.6)
			if top < lower[i] + 0.8:
				continue
			lower[i] = top
			var h := maxf(top - floor_y + 0.4, 1.0)
			var chord := 2.0 * r * sin((a1 - a0) * 0.5) + 0.3
			var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(dir)), Vector3(p.x, floor_y + h * 0.5 - 0.4, p.y))
			m.block(cut, xf, Vector3(chord, h, 2.8))
			m.block(lips, Transform3D(xf.basis, Vector3(p.x, top + 0.08, p.y)), Vector3(chord + 0.2, 0.22, 3.0))
			if b == 0:
				k.collider(Vector3(chord, h, 2.8), xf, "stone")
	m.commit(cut, stone, "Face", true)
	m.commit(lips, turf, "FaceTurf")
	# the floor it was cut down to: a level of chalk and spoil from the face out past the middle,
	# standing proud where the hill falls away below it
	var worked := PoiKit.painted(5, {"base": "#c9c2ae", "accent": "#aca48f", "grout": "#857e6b", "unit": 0.4}, 0.8)
	var along_len := arc_r + 3.0
	var across_len := arc_r * 1.9
	var floor_at := centre - face * (arc_r - 3.0) * 0.5
	var low := floor_y
	for sx in [-0.5, 0.0, 0.5]:
		for sz in [-0.5, 0.0, 0.5]:
			var q := floor_at + side * (across_len * float(sx)) + face * (along_len * float(sz))
			low = minf(low, k.on_ground(q.x, q.y).y)
	var slab_d := floor_y - low + 0.6
	var level := m.begin()
	var fxf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side)), Vector3(floor_at.x, floor_y - slab_d * 0.5, floor_at.y))
	m.block(level, fxf, Vector3(along_len, slab_d, across_len))
	m.commit(level, worked, "QuarryFloor", true)
	k.collider(Vector3(along_len, slab_d, across_len), fxf, "gravel")
	# the blocks it gave up: squared, in a row where they wait, and some still lying where they fell
	var blocks := m.begin()
	for i in 7:
		var p := centre + side * (-5.0 + float(i) * 1.7) - face * k.rng.randf_range(1.5, 3.0)
		var size := Vector3(k.rng.randf_range(0.9, 1.4), k.rng.randf_range(0.6, 0.9), k.rng.randf_range(0.8, 1.2))
		var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(side) + k.rng.randf_range(-0.15, 0.15)),
				Vector3(p.x, maxf(floor_y, k.on_ground(p.x, p.y).y) + size.y * 0.5 - 0.05, p.y))
		m.block(blocks, xf, size)
		k.collider(size, xf, "stone")
		if i % 3 == 0:
			# a second course on the stack
			var up := xf.translated(Vector3(0.0, size.y, 0.0))
			m.block(blocks, up, size * Vector3(0.85, 0.9, 0.85))
	for i in 4:
		var p := centre - face * (arc_r * 0.6) + side * k.rng.randf_range(-arc_r * 0.6, arc_r * 0.6)
		var size := Vector3(k.rng.randf_range(1.0, 2.0), k.rng.randf_range(0.7, 1.3), k.rng.randf_range(1.0, 1.8))
		var xf := Transform3D(Basis(Vector3.UP, k.rng.randf_range(0.0, TAU)) * Basis(Vector3.BACK, k.rng.randf_range(-0.25, 0.25)),
				Vector3(p.x, floor_y + size.y * 0.45, p.y))
		m.block(blocks, xf, size)
		k.collider(size, xf, "stone")
	m.commit(blocks, stone, "Blocks")
	# The spoil heap: what was no use, tipped to one side. It is the face's own rock broken small
	# and gone grey with the earth it came off with, so it is the rock's colour and not the cut
	# face's fresh white, and it is a barrow-load a day for a season, not a hill.
	var spoil_at := centre + side * (arc_r * 0.8) + face * 3.0
	var spoil := PoiKit.painted(5, _spoil_look(k, look), 0.9, 0.9)
	var spoil_r := 2.6
	var spoil_h := 1.2
	m.mound(k.on_ground(spoil_at.x, spoil_at.y, -0.15), spoil_r, spoil_h, spoil, "Spoil", true, 1.3, 6, 18, false, 0.16)
	var scree := k.rock("scree")
	if scree != "":
		# the broken stone lying on it and round its foot, down its slope
		var heap: Array = []
		for i in 9:
			var a := k.rng.randf_range(0.0, TAU)
			var rr := sqrt(k.rng.randf()) * (spoil_r + 0.8)
			var p := spoil_at + Vector2(sin(a), cos(a)) * rr
			var on := maxf(1.0 - rr / spoil_r, 0.0)
			heap.append(PoiKit.transform_at(k.on_ground(p.x, p.y, spoil_h * pow(on, 1.3) - 0.15), k.rng.randf_range(0.0, TAU),
					k.rng.randf_range(0.45, 0.8)))
		k.scatter(scree, heap)
	# the crane: a mast, a jib out over the floor, and a block hanging from its rope
	var timber := m.begin()
	var mast_at := centre - side * (arc_r * 0.45) - face * 1.5
	var foot := Vector3(mast_at.x, maxf(floor_y, k.on_ground(mast_at.x, mast_at.y).y), mast_at.y)
	var mast_h := 7.5
	m.rod(timber, Transform3D(Basis(), foot + Vector3(0.0, mast_h * 0.5, 0.0)), 0.16, mast_h)
	var jib_dir := (side * 0.8 + face * 0.4).normalized()
	var jib_foot := foot + Vector3(0.0, 1.6, 0.0)
	var jib_tip := foot + Vector3(jib_dir.x * 6.0, mast_h - 0.6, jib_dir.y * 6.0)
	m.limb(timber, jib_foot, jib_tip, 0.12)
	m.limb(timber, foot + Vector3(0.0, mast_h, 0.0), jib_tip, 0.04)
	# stays down to the ground, pegged
	for a in [0.0, 2.1, 4.2]:
		var peg := mast_at + Vector2(sin(a), cos(a)) * 3.2
		m.limb(timber, foot + Vector3(0.0, mast_h - 0.2, 0.0), k.on_ground(peg.x, peg.y, 0.1), 0.025)
	var hang := Vector3(jib_tip.x, foot.y + 1.6, jib_tip.z)
	m.limb(timber, jib_tip, hang + Vector3(0.0, 0.5, 0.0), 0.02)
	m.commit(timber, k.surface("timber", 0.6), "Crane", true)
	k.collider(Vector3(0.35, mast_h, 0.35), Transform3D(Basis(), foot + Vector3(0.0, mast_h * 0.5, 0.0)), "wood")
	var lifted := m.begin()
	m.block(lifted, Transform3D(Basis(Vector3.UP, 0.3), hang), Vector3(1.1, 0.8, 0.9))
	m.commit(lifted, stone, "Lifted")
	k.marker("the_face", k.on_ground(centre.x - face.x * (arc_r * 0.5), centre.y - face.y * (arc_r * 0.5)), true)
	# the carts the blocks go out on, and the dust of it
	var cart := k.prop("cart")
	if cart != "":
		var p := centre + face * 7.0 + side * 3.0
		k.place(cart, k.on_ground(p.x, p.y), PoiKit.yaw_of(face) + 1.2, 1.0, true)
	for kind in ["wheelbarrow", "pitchfork"]:
		var path := k.prop(kind)
		if path != "":
			var p := centre + face * k.rng.randf_range(2.0, 5.0) + side * k.rng.randf_range(-4.0, 4.0)
			k.place(path, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.0, true)


# --- a shieling ------------------------------------------------------------------------------------

## A summer hut on the high fell, of drystone with a roof of turf, and the round fold beside it
## the flock is brought into at night: a peat stack by the door, smoke from the roof when somebody
## is up there, sheep in the fold.
static func shieling(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var fabric := FabricMesh.new()
	var face := k.grain()
	var side := Vector2(face.y, -face.x)
	var yaw := PoiKit.yaw_of(face)
	var basis := Basis(Vector3.UP, yaw)
	# the hut: low walls of drystone, the door in the long side, a turf roof on them
	var hut_c := side * 3.0
	var w := 5.0
	var depth := 3.6
	var wall_h := 1.5
	var corners: Array[Vector2] = []
	for s in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
		corners.append(hut_c + side * (w * 0.5 * float(s[0])) + face * (depth * 0.5 * float(s[1])))
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if i == 2:
			# the front, toward `face`: a doorway in its middle
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_dry_wall(d, fabric, a, mid - dir * 0.55, wall_h)
			_dry_wall(d, fabric, mid + dir * 0.55, b, wall_h)
		else:
			_dry_wall(d, fabric, a, b, wall_h)
	var ground := k.on_ground(hut_c.x, hut_c.y).y
	var turf := PoiKit.painted(5, {"base": "#5d6a3c", "accent": "#46522c", "grout": "#2f3a1d", "unit": 0.3}, 0.6)
	var roof := m.begin()
	m.ellipsoid(roof, Vector3(hut_c.x, ground + wall_h + 0.1, hut_c.y), Vector3(w * 0.62, 1.05, depth * 0.66), basis)
	m.commit(roof, turf, "TurfRoof", true)
	k.collider(Vector3(w, 0.8, depth), Transform3D(basis, Vector3(hut_c.x, ground + wall_h + 0.4, hut_c.y)), "dirt")
	# the door: a hurdle of boards in the gap
	var door_at := hut_c + face * (depth * 0.5)
	fabric.box("joinery", Transform3D(basis, k.on_ground(door_at.x, door_at.y, 0.7)), Vector3(0.95, 1.35, 0.08), Color(0.45, 0.36, 0.26))
	# smoke from the roof's hole, when somebody is up here
	k.puffs(Vector3(hut_c.x, ground + wall_h + 1.2, hut_c.y), Vector3(0.1, 0.1, 0.1), 0.8, 8, Color(0.8, 0.78, 0.76, 0.3), 1.1, 5.0)
	k.marker("the_hut", k.on_ground(door_at.x + face.x * 1.2, door_at.y + face.y * 1.2), true)
	var peat := k.prop("peat_stack")
	if peat != "":
		var p := door_at + side * 1.8 + face * 0.4
		k.place(peat, k.on_ground(p.x, p.y), yaw, 1.0, true)
	# the fold: a round of drystone the flock is brought into at night, its gap to the hut
	var fold_c := -side * 6.0 + face * 1.0
	var fold_r := 5.2
	var segs := 14
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		# the gap toward the hut
		var toward := PoiKit.yaw_of(hut_c - fold_c)
		if absf(wrapf((a0 + a1) * 0.5 - toward, -PI, PI)) < PI / float(segs):
			continue
		_dry_wall(d, fabric, fold_c + Vector2(sin(a0), cos(a0)) * fold_r, fold_c + Vector2(sin(a1), cos(a1)) * fold_r, 1.0)
	if not k.far:
		var sheep := Livestock.paths_of("sheep")
		if not sheep.is_empty():
			var flock := Livestock.new()
			flock.name = "Flock"
			flock.seed_with(absi(("flock:" + d.poi_id).hash()))
			flock.keep("sheep", sheep, k.on_ground(fold_c.x, fold_c.y), fold_r - 1.4, 4 + k.rng.randi_range(0, 3))
			d.add_child(flock)
	_commit_fabric(d, fabric)
	_grass(d, "heather" if k.region == "skerrow" else _verge(d), Vector2.ZERO, d.pad_radius * 0.7, 28)


# --- a farmstead ---------------------------------------------------------------------------------

## A house and a barn round a yard walled in the region's way, a well in the yard, and what a yard
## has in it: a cart, the hay, the hens, the chopping block. Where its sentence says there is work,
## the notice post is by the gate.
static func farmstead(d: PoiDressing) -> void:
	var k := d.kit
	var fabric := FabricMesh.new()
	var face := k.road_direction(60.0)
	var toward_road := Vector2.ZERO
	if face != Vector2.ZERO:
		# the yard opens toward the road
		toward_road = _toward_line(d)
	if toward_road == Vector2.ZERO:
		toward_road = k.grain()
	var side := Vector2(toward_road.y, -toward_road.x)
	# the yard: a square walled all round, its gate on the road side
	var half := clampf(d.pad_radius * 0.45, 11.5, 13.0)
	var yard := [Vector2.ZERO + (-side - toward_road) * half, Vector2.ZERO + (side - toward_road) * half,
			Vector2.ZERO + (side + toward_road) * half, Vector2.ZERO + (-side + toward_road) * half]
	var drystone := k.culture in ["clans", "pilgrims"] or k.region == "skerrow"
	for i in 4:
		var a: Vector2 = yard[i]
		var b: Vector2 = yard[(i + 1) % 4]
		if i == 2:
			# the road side: a gate in the middle
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_yard_wall(d, fabric, a, mid - dir * 1.8, drystone)
			_yard_wall(d, fabric, mid + dir * 1.8, b, drystone)
			Wayside.hang_gate(fabric, k.on_ground(mid.x - dir.x * 1.8, mid.y - dir.y * 1.8), dir, k.rng.randf() < 0.6, k.rng.randf())
			if PoiKit.brief_says(d.encounter + " " + d.brief, ["jobs", "work"]):
				var post := mid + toward_road * 2.5 + dir * 3.0
				k.job_board(k.on_ground(post.x, post.y), PoiKit.yaw_of(toward_road))
		else:
			_yard_wall(d, fabric, a, b, drystone)
	# the house across the back of the yard, its door on the yard; the barn down one side
	var house_w := 8.0
	var house_d := 6.0
	var house_c := -toward_road * (half - house_d * 0.5 - 0.8)
	var house := _house(d, fabric, _frame(d, house_c, toward_road, house_w, house_d), house_w, house_d, k.rng.randi_range(1, 2))
	var barn_w := 11.0
	var barn_d := 7.0
	var barn_c := -side * (half - barn_d * 0.5 - 0.8) + toward_road * 1.5
	var barn_style := {"style": "barn", "weight": 1, "wall": "wall_alt" if drystone else "wall", "frame": not drystone,
			"porch": "", "tints": [[0.86, 0.84, 0.8]]}
	if k.culture == "woodfolk" or k.culture == "reedfolk":
		barn_style["wall"] = "wall"
	_house(d, fabric, _frame(d, barn_c, side, barn_w, barn_d), barn_w, barn_d, 1, barn_style, false)
	_commit_fabric(d, fabric)
	# the yard's things
	var well := k.prop("well")
	if well != "":
		var p := side * (half * 0.35) + toward_road * 1.0
		k.place(well, k.on_ground(p.x, p.y), PoiKit.yaw_of(-side), 1.0, true)
	var cart := k.prop("cart")
	if cart != "":
		var p := side * (half * 0.5) - toward_road * 2.0
		k.place(cart, k.on_ground(p.x, p.y), PoiKit.yaw_of(side) + 0.3, 1.0, true)
	var hay := k.prop("hay_bale")
	if hay != "":
		for i in 4:
			var p := barn_c + side * 4.8 + toward_road * (float(i) * 1.3 - 2.0)
			k.place(hay, k.on_ground(p.x, p.y), PoiKit.yaw_of(side) + k.rng.randf_range(-0.2, 0.2), 1.0, true)
	for kind in ["chopping_block", "wheelbarrow", "barrel", "pitchfork"]:
		var path := k.prop(kind)
		if path == "":
			continue
		var p := house_c + toward_road * (house_d * 0.5 + k.rng.randf_range(1.2, 3.0)) + side * k.rng.randf_range(-3.5, 3.5)
		k.place(path, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.0, true)
	k.marker("the_yard", k.on_ground(toward_road.x * 1.5, toward_road.y * 1.5), true)
	var door: Vector3 = house.get("door", Vector3.INF)
	if door != Vector3.INF:
		k.marker("the_door", door, true)
	if not k.far:
		var stock := Livestock.new()
		stock.name = "Yard"
		stock.seed_with(absi(("yard:" + d.poi_id).hash()))
		var hens := Livestock.paths_of("hen")
		if not hens.is_empty():
			stock.keep("hen", hens, k.on_ground(side.x * 3.0, side.y * 3.0), 3.0, 5 + k.rng.randi_range(0, 3))
		var geese := Livestock.paths_of("goose")
		if not geese.is_empty() and k.rng.randf() < 0.5:
			stock.keep("goose", geese, k.on_ground(-side.x * 2.0 + toward_road.x * 4.0, -side.y * 2.0 + toward_road.y * 4.0), 2.5, 3)
		d.add_child(stock)
	_grass(d, _verge(d), toward_road * (half + 6.0), 8.0, 24)


## The yard's own wall: drystone where the country builds in stone, rails where it builds in timber.
static func _yard_wall(d: PoiDressing, fabric: FabricMesh, a: Vector2, b: Vector2, drystone: bool) -> void:
	if drystone:
		_dry_wall(d, fabric, a, b, 1.2)
	else:
		_rails(d, fabric, a, b, 1.15)


## The unit direction from the middle toward the nearest road (not along it), or ZERO.
static func _toward_line(d: PoiDressing) -> Vector2:
	var k := d.kit
	var best := INF
	var out := Vector2.ZERO
	var here := Vector2(k.origin.x, k.origin.z)
	for line_v in k.roads:
		if typeof(line_v) != TYPE_ARRAY:
			continue
		var line: Array = line_v
		for i in range(line.size() - 1):
			var a: Array = line[i]
			var b: Array = line[i + 1]
			var pa := Vector2(float(a[0]), float(a[1]))
			var pb := Vector2(float(b[0]), float(b[1]))
			var seg := pb - pa
			if seg.length() < 0.5:
				continue
			var t := clampf((here - pa).dot(seg) / seg.length_squared(), 0.0, 1.0)
			var near := pa + seg * t
			var dist := near.distance_to(here)
			if dist < best and dist > 0.5 and dist <= 80.0:
				best = dist
				out = (near - here).normalized()
	return out


# --- a mill ----------------------------------------------------------------------------------------

## A mill: a building of two floors with its wheel in a leat, the water let down a stone channel
## to turn it -- or, where the sentence says sails or a windmill, a round tower with its cap and
## four sails. Either goes round while somebody is near enough to see it (`Turning`). Millstones
## lie by the door, and the sacks of what was ground.
static func mill(d: PoiDressing) -> void:
	var k := d.kit
	if PoiKit.brief_says(d.brief, ["sail", "windmill", "wind mill"]):
		_windmill(d)
		return
	var m := d.masonry
	var fabric := FabricMesh.new()
	# the leat runs along the water's way where there is water, else along the grain
	var water := k.water_direction(80.0)
	var run := Vector2(water.y, -water.x) if water != Vector2.ZERO else k.grain()
	var across := Vector2(run.y, -run.x)
	var w := 8.0
	var depth := 7.0
	var mill_c := across * 2.0
	var at := _frame(d, mill_c, across, w, depth)
	var made := _house(d, fabric, at, w, depth, 2)
	_commit_fabric(d, fabric)
	# the leat: a stone channel past the mill's side wall, the water in it
	var leat_y := at.origin.y
	var chan := m.begin()
	var lo := -12.0
	var hi := 12.0
	var wall_x := mill_c - across * (depth * 0.5 + 1.2)
	for s in [-1.0, 1.0]:
		var off := wall_x + across * float(s) * 0.95
		var a := off + run * lo
		var b := off + run * hi
		var mid := (a + b) * 0.5
		var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(run)), Vector3(mid.x, leat_y + 0.1, mid.y))
		m.block(chan, xf, Vector3(0.45, 1.3, hi - lo))
		k.collider(Vector3(0.45, 1.3, hi - lo), xf, "stone")
	m.commit(chan, k.surface("stone", 0.7), "Leat")
	var sheet := m.begin()
	var water_c := wall_x + run * ((lo + hi) * 0.5)
	m.block(sheet, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(run)), Vector3(water_c.x, leat_y + 0.25, water_c.y)), Vector3(1.4, 0.02, hi - lo))
	var still := k.still_water(-0.6, Color(0.9, 1.0, 1.0), 0.55)
	var water_mesh := m.commit(sheet, still, "LeatWater")
	if water_mesh != null:
		water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the wheel, in the leat against the mill's wall: two rims, spokes and paddles, on its axle
	var hub := Vector3(wall_x.x, leat_y + 2.0, wall_x.y)
	var wheel := Turning.new()
	wheel.name = "Wheel"
	wheel.position = hub
	# the wheel's own frame: its axle along `across`, so it turns in the plane of the leat
	wheel.basis = Basis(Vector3.UP, PoiKit.yaw_of(across))
	wheel.axis = Vector3.BACK
	wheel.rate = 0.7
	d.add_child(wheel)
	var parts := m.begin()
	var r := 2.1
	var spokes := 8
	for i in spokes:
		var a := TAU * float(i) / float(spokes)
		m.limb(parts, Vector3.ZERO, Vector3(cos(a), sin(a), 0.0) * r, 0.06)
	for rim in [-0.45, 0.45]:
		var n := 24
		for i in n:
			var a0 := TAU * float(i) / float(n)
			var a1 := TAU * float(i + 1) / float(n)
			m.limb(parts, Vector3(cos(a0) * r, sin(a0) * r, float(rim)), Vector3(cos(a1) * r, sin(a1) * r, float(rim)), 0.07)
	for i in 16:
		var a := TAU * float(i) / 16.0
		m.block(parts, Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a), sin(a), 0.0) * (r + 0.15)), Vector3(0.5, 0.06, 1.0))
	m.rod(parts, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, 0.6)), 0.12, 2.0)
	parts.generate_normals()
	var wheel_mesh := MeshInstance3D.new()
	wheel_mesh.mesh = parts.commit()
	wheel_mesh.material_override = k.surface("timber", 0.65)
	wheel_mesh.name = "WheelMesh"
	wheel.add_child(wheel_mesh)
	if k.far:
		k._far_range(wheel_mesh)
	k.collider(Vector3(r * 2.0, r * 2.0, 1.2), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(across)), hub), "wood")
	k.marker("the_wheel", Vector3(wall_x.x + run.x * 3.0, leat_y, wall_x.y + run.y * 3.0), true)
	_millyard(d, made, across)


## A windmill: a tower of stone courses narrowing to its cap, a door at its foot, and four sails
## of lattice and cloth on the shaft turning into the wind.
static func _windmill(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	# the cap is turned to put the sails into the wind, which blows toward WIND
	var face := -WIND
	var tower := m.begin()
	var foot := k.on_ground(0.0, 0.0)
	var r := 3.2
	var h := 9.5
	m.drum(tower, Transform3D(Basis(), foot), r, h, 0.0, PoiKit.yaw_of(face), true)
	m.commit(tower, k.surface("stone", 0.55), "Tower", true)
	var cap := m.begin()
	m.ellipsoid(cap, foot + Vector3(0.0, h + 0.6, 0.0), Vector3(r * 1.05, 1.6, r * 1.05))
	m.commit(cap, Settlement.fabric_material(k.culture, "roof"), "Cap", true)
	# the sails on their shaft out of the cap, turning into the wind
	var hub := foot + Vector3(face.x, 0.0, face.y) * (r + 0.6) + Vector3(0.0, h + 0.4, 0.0)
	var sails := Turning.new()
	sails.name = "Sails"
	sails.position = hub
	sails.basis = Basis(Vector3.UP, PoiKit.yaw_of(face))
	sails.axis = Vector3.BACK
	sails.rate = 0.45
	d.add_child(sails)
	var frame := m.begin()
	var cloth := m.begin()
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.3
		var along := Vector3(cos(a), sin(a), 0.0)
		var across3 := Vector3(-sin(a), cos(a), 0.0)
		m.limb(frame, Vector3.ZERO, along * 7.5, 0.1)
		for j in 6:
			var t := 1.5 + float(j) * 1.1
			m.limb(frame, along * t, along * t + across3 * 1.4, 0.03)
		m.block(cloth, Transform3D(Basis(across3, along, Vector3.FORWARD), along * 4.8 + across3 * 0.75 + Vector3(0.0, 0.0, 0.05)), Vector3(1.4, 5.4, 0.03))
	m.rod(frame, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -0.8)), 0.18, 1.8)
	for pair in [[frame, k.surface("timber", 0.6), "SailFrames"], [cloth, PoiKit.plain(Color(0.86, 0.83, 0.74), 0.9), "SailCloth"]]:
		var st: SurfaceTool = pair[0]
		st.generate_normals()
		var inst := MeshInstance3D.new()
		inst.mesh = st.commit()
		inst.material_override = pair[1]
		inst.name = str(pair[2])
		sails.add_child(inst)
		if k.far:
			k._far_range(inst)
	k.marker("the_wheel", foot + Vector3(face.x, 0.0, face.y) * (r + 2.0), true)
	_millyard(d, {"door": foot + Vector3(face.x, 0.0, face.y) * (r + 0.4)}, face)


## What lies about a mill's door: its spare millstones, the sacks of what was ground, a cart.
static func _millyard(d: PoiDressing, made: Dictionary, face: Vector2) -> void:
	var k := d.kit
	var door: Vector3 = made.get("door", Vector3.INF)
	if door == Vector3.INF:
		door = k.on_ground(face.x * 5.0, face.y * 5.0)
	var side := Vector2(face.y, -face.x)
	var d2 := Vector2(door.x, door.z)
	var stone := k.prop("millstone")
	if stone != "":
		var p := d2 + face * 2.2 + side * 2.6
		# one leaning against the wall, one flat
		k.place(stone, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 0.8, true)
		var q := d2 + face * 0.9 - side * 2.4
		k.place(stone, k.on_ground(q.x, q.y, 0.9), PoiKit.yaw_of(side), 0.8, true, Vector3(PI * 0.42, 0.0, 0.0))
	var sack := k.prop("sack")
	if sack != "":
		for i in 6:
			var p := d2 + face * k.rng.randf_range(1.0, 2.2) + side * (1.0 + float(i) * 0.5)
			k.place(sack, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.0, false)
	var cart := k.prop("cart")
	if cart != "":
		var p := d2 + face * 5.0 - side * 3.0
		k.place(cart, k.on_ground(p.x, p.y), PoiKit.yaw_of(side) + 0.4, 1.0, true)
	k.marker("the_door", k.on_ground(d2.x + face.x * 1.2, d2.y + face.y * 1.2), true)


# --- a market field --------------------------------------------------------------------------------

## A walled field outside a town where the market is held: its gate to the road, the bell-post that
## opens and closes the market, and on market day (`MarketDays`) the stalls in their rows with the
## carts behind them. The rest of the week it is a field with a bell in it.
static func market_field(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var fabric := FabricMesh.new()
	var toward_road := _toward_line(d)
	if toward_road == Vector2.ZERO:
		toward_road = k.grain()
	var side := Vector2(toward_road.y, -toward_road.x)
	var half_w := minf(d.pad_radius * 0.8, 20.0)
	var half_d := half_w * 0.7
	var corners := [(-side * half_w - toward_road * half_d), (side * half_w - toward_road * half_d),
			(side * half_w + toward_road * half_d), (-side * half_w + toward_road * half_d)]
	var drystone := k.culture in ["clans", "pilgrims", "vale", "lakefolk"]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if i == 2:
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_yard_wall(d, fabric, a, mid - dir * 2.2, drystone)
			_yard_wall(d, fabric, mid + dir * 2.2, b, drystone)
			Wayside.hang_gate(fabric, k.on_ground(mid.x - dir.x * 2.2, mid.y - dir.y * 2.2), dir, true, k.rng.randf())
		else:
			_yard_wall(d, fabric, a, b, drystone)
	_commit_fabric(d, fabric)
	# the bell-post: two posts and a head beam by the gate, the bell hung from it
	var posts := m.begin()
	var bell_at := toward_road * (half_d - 3.0) + side * 4.0
	var hang := m.frame(posts, bell_at, PoiKit.yaw_of(side), 1.4, 3.4, 0.2)
	m.commit(posts, k.surface("timber", 0.6), "BellPost", true)
	var bell := k.prop("bell_medium")
	var bell_scale := 0.55
	if bell == "":
		bell = k.prop("bell_small")
		bell_scale = 2.4
	if bell != "":
		var h := PoiKit.height_of(bell) * bell_scale
		k.place(bell, hang - Vector3(0.0, h + 0.05, 0.0), PoiKit.yaw_of(side), bell_scale, false, Vector3.ZERO, true)
	k.marker("the_bell", k.on_ground(bell_at.x - toward_road.x * 1.5, bell_at.y - toward_road.y * 1.5), true)
	# market day: the stalls in two rows facing each other across the middle, the carts behind
	var market := MarketDays.new()
	market.name = "MarketDay"
	d.add_child(market)
	var stall := k.prop("market_stall")
	var rows := [[-toward_road * 3.2, toward_road], [toward_road * 3.2, -toward_road]]
	var count := int(clampf(half_w / 3.2, 3.0, 6.0))
	for row in rows:
		var line_at: Vector2 = row[0]
		var facing: Vector2 = row[1]
		for i in count:
			var p := line_at + side * ((float(i) - float(count - 1) * 0.5) * 3.4)
			if stall != "":
				var node := k.place(stall, k.on_ground(p.x, p.y), PoiKit.yaw_of(facing), 1.0, true)
				if node != null:
					node.reparent(market)
			for kind in ["basket", "crate", "sack"]:
				if k.rng.randf() < 0.5:
					continue
				var path := k.prop(kind)
				if path == "":
					continue
				var q := p - facing * 1.3 + side * k.rng.randf_range(-1.0, 1.0)
				var node2 := k.place(path, k.on_ground(q.x, q.y), k.rng.randf_range(0.0, TAU), 1.0, false)
				if node2 != null:
					node2.reparent(market)
	var cart := k.prop("cart")
	if cart != "":
		for s in [-1.0, 1.0]:
			var p := -toward_road * (half_d - 3.5) + side * float(s) * (half_w * 0.5)
			var node := k.place(cart, k.on_ground(p.x, p.y), PoiKit.yaw_of(side) + k.rng.randf_range(-0.3, 0.3), 1.0, true)
			if node != null:
				node.reparent(market)
	k.marker("the_market", k.on_ground(0.0, 0.0), true)
	_grass(d, _verge(d), Vector2.ZERO, half_w, 40)
