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
			await k.step()
			k.puffs((top as Vector3) + Vector3(0.0, 0.3, 0.0), Vector3(0.15, 0.1, 0.15), 0.9, 10,
					Color(0.82, 0.8, 0.78, 0.32), 1.3, 5.0)
	return made


## Commits what was built into `fabric` under the dressing, each key in the region's own surface
## the way a settlement commits its own. The far ring keeps the walls and roofs, drawn to the far
## range, and nothing smaller.
static func _commit_fabric(d: PoiDressing, fabric: FabricMesh, materials: Dictionary = {}) -> void:
	var k := d.kit
	# stepwise, the arrays are gathered on a worker thread first (a mill's commit was 20-40 ms here)
	await k.gather(fabric)
	for key in ["wall", "wall_alt", "roof", "stone", "drystone", "coping", "joinery"]:
		var small: bool = key in ["coping", "joinery"]
		if k.far and small:
			continue
		await k.step()
		var node_name := "Fabric" + str(key).capitalize().replace(" ", "")
		var mat: Material = materials.get(key, Settlement.fabric_material(k.culture, key))
		var inst := fabric.commit(d, key, mat, node_name)
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
	await k.step()
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
			await k.step()
			k.place(path, k.on_ground(at.x, at.y, -height * 0.5), yaw, scale, true, Vector3(0.0, 0.0, k.rng.randf_range(-0.06, 0.06)), true)
			var fell := at - side * 1.1 + along * 0.4
			await k.step()
			var top := k.place(path, k.on_ground(fell.x, fell.y, 0.18), yaw + k.rng.randf_range(0.3, 0.7), scale * 0.95, true,
					Vector3(-PI * 0.5 + 0.08, 0.0, 0.0), false)
			if top != null:
				top.name = "FallenTop"
			height *= 0.5
		else:
			await k.step()
			k.place(path, k.on_ground(at.x, at.y), yaw, scale, true, Vector3.ZERO, true)
		var bounds: Dictionary = PoiKit.meta(path).get("bounds", {})
		var lo: Array = bounds.get("min", [])
		var hi: Array = bounds.get("max", [])
		if lo.size() == 3 and hi.size() == 3:
			faces = [float(hi[2]) * scale, float(lo[2]) * scale]
	else:
		var st := m.begin()
		m.block(st, Transform3D(Basis(Vector3.UP, yaw), k.on_ground(at.x, at.y, height * 0.5)), Vector3(0.6, height, 0.36 * scale))
		await k.step()
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
	await k.step()
	m.commit(nicks, PoiKit.plain(Color(0.13, 0.12, 0.11), 0.95), "Notches")
	# the bowl at its foot, hollowed, with what the last walkers left in it
	var bowl_at := at - side * 0.75 + along * 0.2
	var bowl := m.begin()
	await k.step()
	m.drum(bowl, Transform3D(Basis(), k.on_ground(bowl_at.x, bowl_at.y, -0.05)), 0.32, 0.26, 0.0, NAN, false, 0.13)
	await k.step()
	m.commit(bowl, k.surface("stone", 0.8), "Bowl")
	var coins := m.begin()
	for i in 4 + k.rng.randi_range(0, 5):
		var c := bowl_at + k.jitter(0.14)
		m.rod(coins, Transform3D(Basis(Vector3.RIGHT, k.rng.randf_range(-0.3, 0.3)), k.on_ground(c.x, c.y, 0.2 + k.rng.randf_range(0.0, 0.03))), 0.03, 0.006)
	await k.step()
	m.commit(coins, PoiKit.plain(PoiKit.BRONZE, 0.35, 0.8), "Coins")
	k.marker("the_bowl", k.on_ground(bowl_at.x, bowl_at.y))
	# a worn place where walkers stop, and the verge grown round it
	await _grass(d, _verge(d), at, 4.0, 18)


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
		await k.step()
		m.mound(k.on_ground(edge.x - view.x * 0.4, edge.y - view.y * 0.4, -0.12), 3.4, 0.16, clearing, "Clearing", false, 2.2, 4, 16, false, 0.03)
		var flags := m.begin()
		var g := k.on_ground(edge.x, edge.y).y
		for sx in [-1.0, 0.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var q := edge + across * (float(sx) * 0.95) + view * (float(sz) * 0.5)
				var top := maxf(g, k.on_ground(q.x, q.y).y) + 0.22
				var xf := Transform3D(Basis(Vector3.UP, yaw + k.rng.randf_range(-0.05, 0.05)), Vector3(q.x, top - 0.3, q.y))
				m.block(flags, xf, Vector3(0.92 + k.rng.randf_range(-0.05, 0.05), 0.6, 0.97))
		await k.step()
		m.commit(flags, k.surface("stone", 0.6), "Plinth", true)
		var plinth_top := g + 0.22
		k.collider(Vector3(2.9, 0.6, 2.0), Transform3D(Basis(Vector3.UP, yaw), Vector3(edge.x, plinth_top - 0.3, edge.y)), "stone")
		var bench := k.prop("bench")
		if bench != "":
			# the bench's seat faces its -z, so its back is to the ground behind and its front to the view
			await k.step()
			k.place(bench, Vector3(edge.x, plinth_top, edge.y), yaw + PI, 1.15, true, Vector3.ZERO, true)
		var fabric := FabricMesh.new()
		var back := edge - view * 1.35
		_dry_wall(d, fabric, back - across * 1.8, back + across * 1.8, 1.05)
		await _commit_fabric(d, fabric)
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
	await k.step()
	k.scatter(k.rock("boulder"), stones, true, true)
	if only_cairn:
		k.marker("the_view", k.on_ground(cairn_at.x - view.x * 1.8, cairn_at.y - view.y * 1.8), true)
	# the verge behind, where nobody sits, and the flowers round the cairn's foot, not the seat's
	await _grass(d, _verge(d), -view * 9.0, d.pad_radius * 0.4, 26)
	await _grass(d, "heather" if k.region == "skerrow" else ("foxglove" if k.region == "briarwold" else "cow_parsley"),
			cairn_at + across * 1.6, 2.4, 12)


# --- a cave --------------------------------------------------------------------------------------

## A mouth in a slope or a cliff, four to eight metres high, and dark going in ten. The hill is
## a heightmap and cannot be holed, so the mouth is in a shoulder of rock that stands out from the
## slope, facing downhill, deep enough for the dark to go back into: its throat is a passage of the
## rock's own stone darkening to black at ten metres. In Skerrow the rock is limestone, pale and in
## beds; in the Briarwold it is a root-cave, the roots of the tree above arching over the mouth; by
## the sea it is a sea-cave, with the tide's pool in its mouth.
## How far a throat runs in where the world raised a face for the cave: it stands in front of the face,
## so this much of the pad is its (`cave`).
const FACE_THROAT_M := 7.0


static func cave(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var rise := _cave_of(d)
	var face := k.downhill()
	if face == Vector2.ZERO:
		# A level shelf at a cliff's foot has no fall to face down: the mouth turns its back to the
		# rise. The Tide Mouth's shelf under the Hushline is flat for 24 m round, and asked for
		# the nearest water instead, its mouth looked west along the cliff's foot.
		face = -k.uphill()
	if face == Vector2.ZERO:
		face = k.grain()
	if not rise.is_empty():
		face = rise["facing"]
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
	# The mouth stands a little uphill of the middle, its floor on the ground there. Where the world
	# raised a face for it, the throat stands on the level ground in front of that face and ends at
	# its foot, under a bank of the ground's own that meets the face: the land is a heightmap and
	# cannot be holed, and a throat run on into the face was under the ground from its second ring
	# (the seat audit's buried throats at the Horn Hole, the Wrist Hole, the Kharrow Hole, the Oskel
	# Drip, the Root Hollow and the Briar Root, and 53-115 m under the Hushline's cliff), its mouth
	# filled by the face's slope. Its floor is the ground under it, which is the pad's: the Rafters'
	# Locker's face said a floor 14 m over its pad, and its throat stood 4-5 m in the air.
	var face_line := float(rise["behind"]) if not rise.is_empty() else 0.0
	if not rise.is_empty():
		deep = FACE_THROAT_M
	var mouth := into * (face_line - deep - 0.8 if not rise.is_empty() else 3.0)
	var o := k.on_ground(mouth.x, mouth.y)
	if not rise.is_empty():
		high = clampf(high, 2.4, maxf(float(rise["top"]) - o.y - 1.4, 2.4))
		wide = high * k.rng.randf_range(0.85, 1.05)
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
		# the rock of the region at the mouth, going dark as it goes in: the first ring is the stone's
		# own, lit by what comes in, so the mouth is a hole in rock and not a black box
		var dark := lerpf(0.26, 0.02, t1)
		# (the face cave's first ring was the painted stone's courses, which stood in front of the face
		# as a squared doorway once the throat came out of the hill)
		var lining_mat: Material = PoiKit.plain(Color(dark, dark * 0.97, dark * 0.92), 0.95)
		await k.step()
		m.commit(lining, lining_mat, "Throat%d" % i)
		k.collider(Vector3(ww + 0.6, 0.4, span), Transform3D(basis, base + basis * Vector3(0.0, -0.2, mid)), "stone")
	var g_end: float = floors[-1]
	var back := m.begin()
	m.block(back, Transform3D(basis, Vector3(o.x, g_end, o.z) + basis * Vector3(0.0, hh_last * 0.5, deep + 0.75)), Vector3(wide + 1.2, hh_last + 0.8, 0.3))
	await k.step()
	m.commit(back, PoiKit.plain(Color(0.01, 0.01, 0.012), 1.0), "ThroatEnd", true)
	k.collider(Vector3(wide, hh_last + 0.4, 0.4), Transform3D(basis, Vector3(o.x, g_end, o.z) + basis * Vector3(0.0, hh_last * 0.5, deep + 0.75)), "stone")
	# The crag the mouth is cut into, of the region's own rock and nothing squared: boulders of
	# every size, each turned and canted its own way so no two faces agree, sunk into the slope so
	# the hill closes over their feet. Either side of the mouth a cheek rises in three steps up the
	# slope, two capstones lie across the top resting on the throat's roof, and a brow stands back
	# into the hill above them, so the mouth is a cleft in rock the hill breaks into and not a
	# thing stood on the grass. Two leaning slabs read as a tent, and a lintel as a doorway.
	# every boulder of the mouth as it is put down (_crag_crowded), so none is laid inside another
	var laid: Array = []
	# (a brow over the bank, unless the face behind is a cliff, which is its own: the Hushline's brow
	# stood in its cliff's foot, two-thirds under the ground)
	var cliff := not rise.is_empty() and float(rise["top"]) - o.y > high + 8.0
	await _crag(d, mouth, into, across, o, high, wide, cliff, laid)
	# The hill over the passage: a bank of the ground's own over the throat, meeting the face the world
	# raised for it (with the region's rock either side of the throat's end, on the face's line), or the
	# slope where it raised none. Boulders were heaped on the throat's roof instead, and on flat ground
	# the throat stood as a black box with rubble on top (the w4096c shots of the Kharrow Hole, the Horn
	# Hole and the Briar Root).
	if not rise.is_empty():
		var foot := into * face_line
		await _cave_face(d, rise, foot, into, across, k.on_ground(foot.x, foot.y), wide + 2.0)
	await _cave_bank(d, mouth, into, across, o, high, wide, deep)
	# along the flanks, stepping down into the slope
	for s in [-1.0, 1.0]:
		for z in [0.5, 4.0]:
			var path := k.rock("boulder")
			if path == "":
				break
			var bh := maxf(PoiKit.height_of(path), 1.0)
			var at := mouth + across * float(s) * (wide * 0.5 + 5.0 + k.rng.randf_range(0.0, 1.5)) + into * float(z)
			var sc := k.rng.randf_range(1.2, 2.0)
			var half := maxf(PoiKit.half_width_of(path), 0.8) * sc * 1.2
			var yaw := k.rng.randf_range(0.0, TAU)
			var tilt := Vector3(k.rng.randf_range(-0.25, 0.25), 0.0, k.rng.randf_range(-0.25, 0.25))
			var foot := k.on_ground(at.x, at.y, -bh * sc * 0.3)
			for attempt in 5:
				foot = k.on_ground(at.x, at.y, -bh * sc * 0.3)
				if not _crag_crowded(laid, at, half) and _crag_share(laid, _rock_box(path, foot, yaw, sc, tilt)) <= CRAG_SHARE:
					break
				at += across * float(s) * half * 0.6
			var box := _rock_box(path, foot, yaw, sc, tilt)
			# still in another, or moved out along the foot of a cliff onto its face (the Hushline's
			# stood 22 m out, two-thirds under the cliff's slope): left out
			if _crag_crowded(laid, at, half) or _crag_share(laid, box) > CRAG_SHARE \
					or absf(k.on_ground(at.x, at.y).y - o.y) > bh * sc * 2.0 + 3.0:
				continue
			laid.append(box)
			await k.step()
			var rock := k.place(path, foot, yaw, sc, true, tilt, true)
			if rock != null:
				rock.set_meta(PoiKit.SEATED_META, true)
	# Light back off the ground in front of the mouth. With the sun behind the hill the crag's faces
	# are in its shadow, and in the painted grade a shadow that has nothing to lift it goes black,
	# so the mouth read as a hole cut in the frame. A bounce is a real light by day and no glow.
	var bounce := mouth - into * 5.0
	k.bounce_light(k.on_ground(bounce.x, bounce.y, 3.2), _bounce_colour(k.region), 2.6, 16.0)
	# where whatever lives in it waits, a little way in out of the light
	var den := mouth + into * 3.5
	k.marker("the_mouth", Vector3(den.x, floors[1], den.y), false, true, wide * 0.5)
	# the fall of rock at its foot: a lip of stones across the threshold and ferns in them, not a heap
	var scree := k.rock("scree")
	if scree != "":
		var heap: Array = []
		for i in 8:
			var p := mouth - into * k.rng.randf_range(0.6, 3.5) + across * k.rng.randf_range(-wide * 0.8, wide * 0.8)
			heap.append(PoiKit.transform_at(Vector3(p.x, o.y - 0.1, p.y) if not rise.is_empty() else k.on_ground(p.x, p.y, -0.1),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.5, 0.9)))
		await k.step()
		k.scatter(scree, heap, true)
		await _grass(d, "fern" if k.region != "cinderlea" else "grey_grass", mouth - into * 1.4, wide * 0.9, 10)
	var boulder := k.rock("boulder")
	if boulder != "":
		var small: Array = []
		var bw := maxf(PoiKit.half_width_of(boulder), 0.3)
		for i in 5:
			var p := mouth - into * k.rng.randf_range(2.5, 7.0) + across * k.rng.randf_range(-wide * 1.2, wide * 1.2)
			var sc := k.rng.randf_range(0.3, 0.6)
			var yaw := k.rng.randf_range(0.0, TAU)
			var half := bw * sc * 1.2
			# a small one lying inside a big one is not a stone at its foot: left out
			if _crag_crowded(laid, p, half):
				continue
			laid.append(_rock_box(boulder, k.on_ground(p.x, p.y, -0.2), yaw, sc))
			small.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.2), yaw, sc))
		await k.step()
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
			await k.step()
			m.limb(wood, top, bend, k.rng.randf_range(0.1, 0.22))
			await k.step()
			m.limb(wood, bend, k.on_ground(q.x, q.y), k.rng.randf_range(0.08, 0.16))
		await k.step()
		m.commit(wood, k.surface("timber", 0.7), "Roots", true)
		await _grass(d, "fern", mouth - into * 2.0, 6.0, 20)
	if sea:
		# The tide's pool in the mouth and out past it, with a bar of pale shell-sand the tide
		# leaves at its edge and the surf breaking on it. On Cinderlea's black ash, dark rock over
		# dark ground was a hole in the frame; the sky in the water and the pale sand are what the
		# mouth is seen by.
		var pool_at := mouth - into * 1.2
		var sand_at := mouth - into * (wide * 0.55 + 2.4)
		var sand := PoiKit.painted(5, {"base": "#bdb5a2", "accent": "#a39a86", "grout": "#7d7564", "unit": 0.18}, 0.7)
		await k.step()
		m.mound(k.on_ground(sand_at.x, sand_at.y, -0.15), wide * 0.9 + 1.5, 0.35, sand, "ShellSand", false, 1.4, 5, 18, false, 0.05)
		await k.step()
		m.pool(pool_at, wide * 0.75, o.y - 0.1, k.still_water(-1.2, Color(1.0, 1.05, 1.08), 0.55), "TidePool")
		var surf := Vector3(sand_at.x, o.y + 0.1, sand_at.y) + Vector3(into.x, 0.0, into.y) * 1.2
		await k.step()
		k.puffs(surf, Vector3(wide * 0.6, 0.15, 0.6), 0.3, 18, Color(0.96, 0.98, 1.0, 0.45), 1.4, 2.4)
	else:
		await _grass(d, _verge(d), mouth - into * 6.0, 7.0, 16)


## The rise the world raised for a cave (`PoiDressing.cave`), read for the builder: {facing (unit
## local xz), floor and top (local heights), behind (the mouth's line), half (the knoll's half-width,
## or 0 for a shelf across the pad)}, or empty where there is none or it cannot be read.
static func _cave_of(d: PoiDressing) -> Dictionary:
	var c := d.cave
	if c.is_empty() or not c.has("facing_deg") or not c.has("mouth_m") or not c.has("face_top_m"):
		return {}
	var a := deg_to_rad(float(c["facing_deg"]))
	var half: Variant = c.get("face_half_width_m", null)
	return {"facing": Vector2(sin(a), cos(a)), "floor": float(c["mouth_m"]) - d.world_position.y,
			"top": float(c["face_top_m"]) - d.world_position.y, "behind": float(c.get("mouth_behind_m", 3.0)),
			"half": float(half) if half != null else 0.0}


## The face the world raised behind a cave's mouth, in the region's rock either side of the mouth:
## columns of the forge's cliff ledges from the floor to the top of the face (the land stands behind
## them from three metres back), as wide as the knoll, the cheeks and the arch in the middle.
static func _cave_face(d: PoiDressing, rise: Dictionary, mouth: Vector2, into: Vector2, across: Vector2,
		o: Vector3, wide: float) -> void:
	var k := d.kit
	var builders: GDScript = load(PoiDressing.BUILDERS_PATH)
	var kinds: Array[String] = builders.call("_ledge_paths", k)
	if kinds.is_empty():
		return
	var face_h := float(rise["top"]) - o.y
	var half := float(rise["half"])
	var reach := (half + 4.0) if half > 0.0 else minf(d.pad_radius, 16.0)
	var facing := -into
	var yaw := PoiKit.yaw_of(facing)
	var by_path: Dictionary = {}
	var x := wide * 0.5 + 2.6
	while x < reach:
		for s in [-1.0, 1.0]:
			var along := x * float(s)
			# lower toward the knoll's ends, as the land is
			var share := 1.0 if half <= 0.0 or absf(along) < half else maxf(0.15, 1.0 - (absf(along) - half) / 10.0)
			var want := face_h * share * k.rng.randf_range(0.85, 1.05)
			var p := mouth + across * along - into * k.rng.randf_range(-0.2, 0.3)
			var top := o.y - 0.5
			var r := 0
			while top - o.y < want - 0.5 and r < 6:
				var path: String = kinds[k.rng.randi_range(0, kinds.size() - 1)]
				var dims: Vector3 = builders.call("_ledge_dims", path)
				# each set a little back into the land as it goes up, so the land's ramp stays behind
				var q := p + into * (dims.z + 0.45 * float(r) - 0.3)
				var basis := Basis(Vector3.UP, yaw + k.rng.randf_range(-0.08, 0.08)).scaled(Vector3(k.rng.randf_range(0.9, 1.12), 1.0, 1.0))
				if not by_path.has(path):
					by_path[path] = []
				(by_path[path] as Array).append(Transform3D(basis, Vector3(q.x, top - (0.18 if r > 0 else 0.0), q.y)))
				top += dims.y - (0.18 if r > 0 else 0.0)
				r += 1
		x += 4.4
	for pth in by_path:
		await k.step()
		k.scatter(pth, by_path[pth], true, true)


## Where no face was raised for it, the cave's own bank: the ground itself raised over the throat
## and round the mouth, in the ground's own look, meeting the land at its edges with no rim, so the
## passage is in the hill and the mouth's rock half in the bank. The first try was a dome over the
## throat, which read as a smooth green hemisphere and buried the mouth under its front.
static func _cave_bank(d: PoiDressing, mouth: Vector2, into: Vector2, across: Vector2, o: Vector3,
		high: float, wide: float, deep: float) -> void:
	var k := d.kit
	var builders: GDScript = load(PoiDressing.BUILDERS_PATH)
	var look: Material = builders.call("_ground_look", k, mouth + into * deep * 0.5)
	var top := high + 1.3
	var roof := high + 0.9
	var half := wide * 0.5
	var u0 := -(half + 11.0)
	var u1 := half + 11.0
	var v0 := -2.5
	var v1 := deep + 10.0
	var step := 1.0
	var nu := int(ceil((u1 - u0) / step)) + 1
	var nv := int(ceil((v1 - v0) / step)) + 1
	var wob := k.rng.randf_range(0.0, TAU)
	var pts: Array[Vector3] = []
	var up: Array[bool] = []
	var hole: Array[bool] = []
	for j in nv:
		for i in nu:
			var u := u0 + float(i) * step
			var v := v0 + float(j) * step
			var at := mouth + across * u + into * v
			var g := k.on_ground(at.x, at.y).y
			var fu := 1.0 - smoothstep(half + 2.0, half + 10.5, absf(u))
			var fv := smoothstep(-2.4, 0.6, v) * (1.0 - smoothstep(deep + 1.5, deep + 9.5, v))
			var h := top * fu * fv * (1.0 + 0.14 * sin(u * 0.47 + wob) * cos(v * 0.39 - wob))
			var in_mouth := absf(u) < half + 0.4 and v < 0.9
			if absf(u) < half + 0.6 and v >= 0.9 and v <= deep + 1.5:
				# over the throat: never under its roof
				h = maxf(h, roof)
			var y := o.y + h
			var raised := h > 0.25 and y > g + 0.15
			pts.append(Vector3(at.x, y if raised else g - 0.3, at.y))
			up.append(raised)
			hole.append(in_mouth)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	for j in nv - 1:
		for i in nu - 1:
			var a := j * nu + i
			var b := a + 1
			var c := a + nu
			var e := c + 1
			if hole[a] or hole[b] or hole[c] or hole[e]:
				continue
			if not (up[a] or up[b] or up[c] or up[e]):
				continue
			# wound so the faces look up whichever way `into` runs
			var n := (pts[c] - pts[a]).cross(pts[b] - pts[a])
			if n.y >= 0.0:
				for idx in [a, b, c, b, e, c]:
					st.add_vertex(pts[int(idx)])
			else:
				for idx in [a, c, b, b, c, e]:
					st.add_vertex(pts[int(idx)])
			quads += 1
	if quads == 0:
		return
	st.generate_normals()
	var mesh := st.commit()
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = look
	inst.name = "Bank"
	k.root.add_child(inst)
	k.collider_shape(mesh.create_trimesh_shape(), Transform3D.IDENTITY, "dirt")
	var tufts: Array = []
	var grass := k.flora(_verge(d))
	for t in 40:
		var u := k.rng.randf_range(u0 * 0.7, u1 * 0.7)
		var v := k.rng.randf_range(1.0, deep + 6.0)
		var q := pts[clampi(int(round((v - v0) / step)), 0, nv - 1) * nu + clampi(int(round((u - u0) / step)), 0, nu - 1)]
		tufts.append(PoiKit.transform_at(q - Vector3(0.0, 0.05, 0.0), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
	if grass != "":
		await k.step()
		k.scatter(grass, tufts, false, false, false)


## The rock a cave's mouth is cut into (see `cave`): the cheeks either side, stepping up the slope,
## the capstones over the mouth resting on the throat's roof, and the brow standing back into the
## hill. Every piece is its own boulder, turned and canted its own way, so its faces are broken and
## no two agree; each is sunk so the slope closes over its foot, and none stands clear of the ground.
## `in_face` (the world raised a face for the mouth): no brow, since the face's own top is its brow.
static func _crag(d: PoiDressing, mouth: Vector2, into: Vector2, across: Vector2, o: Vector3,
		high: float, wide: float, in_face := false, laid: Array = []) -> void:
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
	if not in_face:
		pieces.append([0.0, 5.0, high + 2.6, 0.9, false])
	# each boulder's footprint as it has been put down, so the next is moved off one it would sit
	# inside: two of them sharing most of a box read as one rock through another (the seat audit's
	# `overlap`: twelve at the Unsung Vault)
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
		# turned any way, a boulder's box is up to its width over again on the diagonal
		var half := bw * sc * 1.2
		# a capstone keeps its place on the roof, crowded or not: moved back it was rubble heaped on
		# the passage, moved aside it sat in a cheek, made smaller it sat inside the other, and left
		# out the mouth lost its lintel
		var crowded := _crag_crowded(laid, at, half) and not bool(piece[4])
		for attempt in 8:
			if not crowded:
				break
			# a cheek further round the mouth's side; the brow further back into the hill
			at += (across * signf(x) if absf(x) >= 1.0 else into) * half * 0.6
			crowded = _crag_crowded(laid, at, half)
		var tilt := Vector3(k.rng.randf_range(-0.3, 0.3), 0.0, k.rng.randf_range(-0.3, 0.3))
		var yaw := k.rng.randf_range(0.0, TAU)
		var y := _crag_y(k, at, o, piece, high, bh * sc)
		var box := _rock_box(path, Vector3(at.x, y, at.y), yaw, sc, tilt)
		# Turned and canted, a boulder's drawn box is not the footprint above, and two of them still
		# shared most of one (the seat audit's overlaps at the Horn Hole, the Wrist Hole, the Briar
		# Root, Orrdun): a capstone rests a little higher on the roof, any other moves on round the
		# mouth or back into the hill, and one that still lies in another is left out.
		for attempt in 6:
			if _crag_share(laid, box) <= CRAG_SHARE:
				break
			if bool(piece[4]):
				y += 0.3
			else:
				at += (across * signf(x) if absf(x) >= 1.0 else into) * half * 0.4
				y = _crag_y(k, at, o, piece, high, bh * sc)
			box = _rock_box(path, Vector3(at.x, y, at.y), yaw, sc, tilt)
		if _crag_share(laid, box) > CRAG_SHARE:
			continue
		laid.append(box)
		await k.step()
		var rock := k.place(path, Vector3(at.x, y, at.y), yaw, sc, true, tilt, true)
		if rock != null:
			# every piece of the crag is where the mouth wants it, the capstones on the roof
			rock.set_meta(PoiKit.SEATED_META, true)


## Where a boulder of the mouth's crag (`_crag`) stands: `piece`'s top over the mouth's floor, a
## capstone on the roof, anything else with a quarter to under half of its `h` in the slope.
static func _crag_y(k: PoiKit, at: Vector2, o: Vector3, piece: Array, high: float, h: float) -> float:
	var g := k.on_ground(at.x, at.y).y
	var y := o.y + float(piece[2]) - h
	if bool(piece[4]):
		return maxf(y, o.y + high - 0.3)
	# never standing on the grass: at least a quarter of it is under the slope
	y = minf(y, g - h * 0.25)
	# and never most of it under: over half of a boulder in the slope reads as a bump, not a rock (the
	# seat audit's `sunk`, 60% at its box's middle, which a canted one's box puts further down)
	return maxf(y, g - h * 0.45)


## How much of a crag's boulder another may share, of the smaller one's drawn box (the seat audit
## calls 60% an overlap): rocks of a crag lean on each other, and their turned boxes share a good deal
## where the rocks themselves only touch.
const CRAG_SHARE := 0.55


## A rock's drawn box, set down at `at` turned `yaw`, canted `tilt` and scaled `sc` as PoiKit.place
## sets it, from the forge's bounds.
static func _rock_box(path: String, at: Vector3, yaw: float, sc: float, tilt := Vector3.ZERO) -> AABB:
	var b: Dictionary = PoiKit.meta(path).get("bounds", {})
	var lo: Array = b.get("min", [-0.5, 0.0, -0.5])
	var hi: Array = b.get("max", [0.5, 1.0, 0.5])
	var local := AABB(Vector3(float(lo[0]), float(lo[1]), float(lo[2])),
			Vector3(float(hi[0]) - float(lo[0]), float(hi[1]) - float(lo[1]), float(hi[2]) - float(lo[2])))
	var basis := Basis.from_euler(Vector3(tilt.x, yaw, tilt.z)).scaled(Vector3.ONE * sc)
	return Transform3D(basis, at - Vector3(0.0, PoiKit.buried_m(path) * sc, 0.0)) * local


## The most of the smaller drawn box that `box` shares with any of `laid`.
static func _crag_share(laid: Array, box: AABB) -> float:
	var most := 0.0
	for b_v in laid:
		var b: AABB = b_v
		if not box.intersects(b):
			continue
		var smaller := maxf(minf(box.get_volume(), b.get_volume()), 0.0001)
		most = maxf(most, box.intersection(b).get_volume() / smaller)
	return most


## Whether a boulder `half` wide at `at` would share a fifth of the smaller footprint with one
## already put down (`_crag`), the boxes seen from above.
static func _crag_crowded(laid: Array, at: Vector2, half: float) -> bool:
	var mine := Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0)
	for b_v in laid:
		var b: AABB = b_v
		var r := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		var shared := mine.intersection(r).get_area()
		if shared > 0.2 * minf(mine.get_area(), r.get_area()):
			return true
	return false


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
	await k.step()
	m.commit(cut, stone, "Face", true)
	await k.step()
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
	await k.step()
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
	await k.step()
	m.commit(blocks, stone, "Blocks")
	# The spoil heap: what was no use, tipped to one side. It is the face's own rock broken small
	# and gone grey with the earth it came off with, so it is the rock's colour and not the cut
	# face's fresh white, and it is a barrow-load a day for a season, not a hill.
	var spoil_at := centre + side * (arc_r * 0.8) + face * 3.0
	var spoil := PoiKit.painted(5, _spoil_look(k, look), 0.9, 0.9)
	var spoil_r := 2.6
	var spoil_h := 1.2
	await k.step()
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
		await k.step()
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
	await k.step()
	m.limb(timber, jib_foot, jib_tip, 0.12)
	await k.step()
	m.limb(timber, foot + Vector3(0.0, mast_h, 0.0), jib_tip, 0.04)
	# stays down to the ground, pegged
	for a in [0.0, 2.1, 4.2]:
		var peg := mast_at + Vector2(sin(a), cos(a)) * 3.2
		await k.step()
		m.limb(timber, foot + Vector3(0.0, mast_h - 0.2, 0.0), k.on_ground(peg.x, peg.y, 0.1), 0.025)
	var hang := Vector3(jib_tip.x, foot.y + 1.6, jib_tip.z)
	await k.step()
	m.limb(timber, jib_tip, hang + Vector3(0.0, 0.5, 0.0), 0.02)
	await k.step()
	m.commit(timber, k.surface("timber", 0.6), "Crane", true)
	k.collider(Vector3(0.35, mast_h, 0.35), Transform3D(Basis(), foot + Vector3(0.0, mast_h * 0.5, 0.0)), "wood")
	var lifted := m.begin()
	m.block(lifted, Transform3D(Basis(Vector3.UP, 0.3), hang), Vector3(1.1, 0.8, 0.9))
	await k.step()
	m.commit(lifted, stone, "Lifted")
	k.marker("the_face", k.on_ground(centre.x - face.x * (arc_r * 0.5), centre.y - face.y * (arc_r * 0.5)), true)
	# the carts the blocks go out on, and the dust of it
	var cart := k.prop("cart")
	if cart != "":
		var p := centre + face * 7.0 + side * 3.0
		await k.step()
		k.place(cart, k.on_ground(p.x, p.y), PoiKit.yaw_of(face) + 1.2, 1.0, true)
	for kind in ["wheelbarrow", "pitchfork"]:
		var path := k.prop(kind)
		if path != "":
			var p := centre + face * k.rng.randf_range(2.0, 5.0) + side * k.rng.randf_range(-4.0, 4.0)
			await k.step()
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
	await k.step()
	m.ellipsoid(roof, Vector3(hut_c.x, ground + wall_h + 0.1, hut_c.y), Vector3(w * 0.62, 1.05, depth * 0.66), basis)
	await k.step()
	m.commit(roof, turf, "TurfRoof", true)
	k.collider(Vector3(w, 0.8, depth), Transform3D(basis, Vector3(hut_c.x, ground + wall_h + 0.4, hut_c.y)), "dirt")
	# the door: a hurdle of boards in the gap
	var door_at := hut_c + face * (depth * 0.5)
	fabric.box("joinery", Transform3D(basis, k.on_ground(door_at.x, door_at.y, 0.7)), Vector3(0.95, 1.35, 0.08), Color(0.45, 0.36, 0.26))
	# smoke from the roof's hole, when somebody is up here
	await k.step()
	k.puffs(Vector3(hut_c.x, ground + wall_h + 1.2, hut_c.y), Vector3(0.1, 0.1, 0.1), 0.8, 8, Color(0.8, 0.78, 0.76, 0.3), 1.1, 5.0)
	k.marker("the_hut", k.on_ground(door_at.x + face.x * 1.2, door_at.y + face.y * 1.2), true)
	var peat := k.prop("peat_stack")
	if peat != "":
		var p := door_at + side * 1.8 + face * 0.4
		await k.step()
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
	await _commit_fabric(d, fabric)
	await _grass(d, "heather" if k.region == "skerrow" else _verge(d), Vector2.ZERO, d.pad_radius * 0.7, 28)


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
				await k.step()
				k.job_board(k.on_ground(post.x, post.y), PoiKit.yaw_of(toward_road))
		else:
			_yard_wall(d, fabric, a, b, drystone)
	# the house across the back of the yard, its door on the yard; the barn down one side
	var house_w := 8.0
	var house_d := 6.0
	var house_c := -toward_road * (half - house_d * 0.5 - 0.8)
	var house := await _house(d, fabric, _frame(d, house_c, toward_road, house_w, house_d), house_w, house_d, k.rng.randi_range(1, 2))
	# Where whoever keeps the house stands at its door: out on the yard, a pace in front of it.
	# HouseKit's door is on the wall's face, and a person stood there was half inside the house.
	var door: Vector3 = house.get("door", Vector3.INF)
	var door_spot := Vector2.INF
	if door != Vector3.INF:
		door_spot = Vector2(door.x, door.z) + toward_road * 1.2
	var barn_w := 11.0
	var barn_d := 7.0
	var barn_c := -side * (half - barn_d * 0.5 - 0.8) + toward_road * 1.5
	var barn_style := {"style": "barn", "weight": 1, "wall": "wall_alt" if drystone else "wall", "frame": not drystone,
			"porch": "", "tints": [[0.86, 0.84, 0.8]]}
	if k.culture == "woodfolk" or k.culture == "reedfolk":
		barn_style["wall"] = "wall"
	await _house(d, fabric, _frame(d, barn_c, side, barn_w, barn_d), barn_w, barn_d, 1, barn_style, false)
	# a dovecote in the yard's far corner, where the sentence keeps one (Hatchmoor): a small square
	# tower of the farm's own walls under its own roof, with a row of holes under the eaves
	if PoiKit.brief_says(d.brief, ["dovecote", "doves", "pigeon"]):
		var cote_c := side * (half - 2.6) - toward_road * (half - 2.6)
		await _house(d, fabric, _frame(d, cote_c, toward_road, 2.8, 2.8), 2.8, 2.8, 2, barn_style, false)
		var holes := d.masonry.begin()
		var hg := k.on_ground(cote_c.x, cote_c.y).y
		for face_dir in [toward_road, -toward_road, side, -side]:
			var fd: Vector2 = face_dir
			var along := Vector2(fd.y, -fd.x)
			for i in 3:
				var q := cote_c + fd * 1.42 + along * (float(i) - 1.0) * 0.6
				d.masonry.block(holes, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(fd)), Vector3(q.x, hg + 4.3, q.y)), Vector3(0.22, 0.2, 0.06))
		await k.step()
		d.masonry.commit(holes, PoiKit.plain(Color(0.05, 0.05, 0.05), 0.95), "DovecoteHoles")
		k.marker("the_dovecote", k.on_ground(cote_c.x + toward_road.x * 2.0, cote_c.y + toward_road.y * 2.0), true)
	await _commit_fabric(d, fabric)
	# a door-quern by the house door, where the sentence has one (Pennywort): the two stones of a
	# hand-mill, the upper on the lower, its handle up
	if PoiKit.brief_says(d.brief, ["quern"]):
		var stone := k.prop("millstone")
		var door_at: Vector3 = house.get("door", Vector3.INF)
		if stone != "" and door_at != Vector3.INF:
			var q := Vector2(door_at.x, door_at.z) + toward_road * 0.9 + side * 1.4
			var base := k.on_ground(q.x, q.y)
			var sh := PoiKit.height_of(stone) * 0.32
			await k.step()
			k.place(stone, base, 0.0, 0.32, true)
			await k.step()
			var upper := k.place(stone, base + Vector3(0.0, sh, 0.0), 0.7, 0.3, false)
			if upper != null:
				upper.name = "Quern"
			var handle := d.masonry.begin()
			d.masonry.rod(handle, Transform3D(Basis(), base + Vector3(0.16, sh * 2.0 + 0.12, 0.0)), 0.025, 0.26)
			await k.step()
			d.masonry.commit(handle, k.surface("timber", 0.6), "QuernHandle")
	# a stone water trough by the well, where the sentence has one (Southgate)
	if PoiKit.brief_says(d.brief, ["trough"]):
		var tq := side * (half * 0.35) + toward_road * 3.2
		var tg := k.on_ground(tq.x, tq.y)
		var tb := Basis(Vector3.UP, PoiKit.yaw_of(side))
		var trough := d.masonry.begin()
		d.masonry.block(trough, Transform3D(tb, tg + Vector3(0.0, 0.08, 0.0)), Vector3(0.66, 0.16, 2.1))
		for sx in [-1.0, 1.0]:
			d.masonry.block(trough, Transform3D(tb, tg + tb * Vector3(float(sx) * 0.28, 0.33, 0.0)), Vector3(0.1, 0.5, 2.1))
			d.masonry.block(trough, Transform3D(tb, tg + tb * Vector3(0.0, 0.33, float(sx) * 1.0)), Vector3(0.66, 0.5, 0.1))
		await k.step()
		d.masonry.commit(trough, k.surface("stone", 0.7), "Trough", true)
		k.collider(Vector3(0.66, 0.58, 2.1), Transform3D(tb, tg + Vector3(0.0, 0.29, 0.0)), "stone")
		var wet := d.masonry.begin()
		d.masonry.block(wet, Transform3D(tb, tg + Vector3(0.0, 0.5, 0.0)), Vector3(0.46, 0.02, 1.9))
		await k.step()
		d.masonry.commit(wet, k.still_water(0.2, Color(0.9, 1.0, 1.0), 0.5), "TroughWater")
	# the yard's things
	var well := k.prop("well")
	if well != "":
		var p := side * (half * 0.35) + toward_road * 1.0
		await k.step()
		k.place(well, k.on_ground(p.x, p.y), PoiKit.yaw_of(-side), 1.0, true)
	var cart := k.prop("cart")
	if cart != "":
		var p := side * (half * 0.5) - toward_road * 2.0
		await k.step()
		k.place(cart, k.on_ground(p.x, p.y), PoiKit.yaw_of(side) + 0.3, 1.0, true)
	var hay := k.prop("hay_bale")
	if hay != "":
		for i in 4:
			var p := barn_c + side * 4.8 + toward_road * (float(i) * 1.3 - 2.0)
			await k.step()
			k.place(hay, k.on_ground(p.x, p.y), PoiKit.yaw_of(side) + k.rng.randf_range(-0.2, 0.2), 1.0, true)
	for kind in ["chopping_block", "wheelbarrow", "barrel", "pitchfork"]:
		var path := k.prop(kind)
		if path == "":
			continue
		var p := house_c + toward_road * (house_d * 0.5 + k.rng.randf_range(1.2, 3.0)) + side * k.rng.randf_range(-3.5, 3.5)
		p = _clear_of(p, door_spot, 1.6, toward_road)
		await k.step()
		k.place(path, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.0, true)
	k.marker("the_yard", k.on_ground(toward_road.x * 1.5, toward_road.y * 1.5), true)
	if door_spot != Vector2.INF:
		k.marker("the_door", k.on_ground(door_spot.x, door_spot.y), true)
	# lived in: its windows lit after dark, as a village's are; and where the sentence keeps a lamp
	# in the window (the Last Farm's, facing the grey), that window has a lamp's real light at dusk
	var panes: Array = house.get("glows", [])
	if not k.far and not panes.is_empty() and d.is_inside_tree():
		var world_panes: Array = []
		for pane in panes:
			world_panes.append(d.to_global(pane as Vector3))
		NightLights.add(d, world_panes, "window")
		if PoiKit.brief_says(d.brief, ["lamp"]):
			NightLights.add(d, [world_panes[0]], "lantern")
			k.marker("the_lamp", panes[0] as Vector3)
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
	await _grass(d, _verge(d), toward_road * (half + 6.0), 8.0, 24)


## `p` moved out along `out` (away from the house, never back toward it) until it is `r` from
## `spot`, if it was nearer; `p` as it was when it is far enough already or there is no spot (INF).
## Keeps what stands about a yard off the place somebody stands to work.
static func _clear_of(p: Vector2, spot: Vector2, r: float, out: Vector2) -> Vector2:
	if spot == Vector2.INF or p.distance_to(spot) >= r:
		return p
	var across := Vector2(out.y, -out.x)
	var a := (p - spot).dot(across)
	return spot + across * a + out * sqrt(maxf(r * r - a * a, 0.0))


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
	for s in k.roads_near(80.0):
		var pa := s[0]
		var pb := s[1]
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
		await _windmill(d)
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
	var made := await _house(d, fabric, at, w, depth, 2)
	# a mill "housed in a turf long-house" (Rudd Mill) is roofed in turf, not the country's thatch
	var roofs := {}
	if PoiKit.brief_says(d.brief, ["turf"]):
		roofs["roof"] = PoiKit.painted(5, {"base": "#5f6b3c", "accent": "#48532c", "grout": "#2f381c", "unit": 0.3}, 0.7)
	await _commit_fabric(d, fabric, roofs)
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
	await k.step()
	m.commit(chan, k.surface("stone", 0.7), "Leat")
	var sheet := m.begin()
	var water_c := wall_x + run * ((lo + hi) * 0.5)
	m.block(sheet, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(run)), Vector3(water_c.x, leat_y + 0.25, water_c.y)), Vector3(1.4, 0.02, hi - lo))
	var still := k.still_water(-0.6, Color(0.9, 1.0, 1.0), 0.55)
	await k.step()
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
		await k.step()
		m.limb(parts, Vector3.ZERO, Vector3(cos(a), sin(a), 0.0) * r, 0.06)
	for rim in [-0.45, 0.45]:
		await k.step()
		var n := 24
		for i in n:
			var a0 := TAU * float(i) / float(n)
			var a1 := TAU * float(i + 1) / float(n)
			await k.step()
			m.limb(parts, Vector3(cos(a0) * r, sin(a0) * r, float(rim)), Vector3(cos(a1) * r, sin(a1) * r, float(rim)), 0.07)
	for i in 16:
		var a := TAU * float(i) / 16.0
		m.block(parts, Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a), sin(a), 0.0) * (r + 0.15)), Vector3(0.5, 0.06, 1.0))
	m.rod(parts, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, 0.6)), 0.12, 2.0)
	await k.step()
	var wheel_mesh := MeshInstance3D.new()
	k.finish_mesh(wheel_mesh, parts)
	wheel_mesh.material_override = k.surface("timber", 0.65)
	wheel_mesh.name = "WheelMesh"
	wheel.add_child(wheel_mesh)
	if k.far:
		k._far_range(wheel_mesh)
	k.collider(Vector3(r * 2.0, r * 2.0, 1.2), Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(across)), hub), "wood")
	k.marker("the_wheel", Vector3(wall_x.x + run.x * 3.0, leat_y, wall_x.y + run.y * 3.0), true)
	await _millyard(d, made, across)


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
	await k.step()
	m.drum(tower, Transform3D(Basis(), foot), r, h, 0.0, PoiKit.yaw_of(face), true)
	await k.step()
	m.commit(tower, k.surface("stone", 0.55), "Tower", true)
	var cap := m.begin()
	await k.step()
	m.ellipsoid(cap, foot + Vector3(0.0, h + 0.6, 0.0), Vector3(r * 1.05, 1.6, r * 1.05))
	await k.step()
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
		await k.step()
		var a := TAU * float(i) / 4.0 + 0.3
		var along := Vector3(cos(a), sin(a), 0.0)
		var across3 := Vector3(-sin(a), cos(a), 0.0)
		await k.step()
		m.limb(frame, Vector3.ZERO, along * 7.5, 0.1)
		for j in 6:
			var t := 1.5 + float(j) * 1.1
			await k.step()
			m.limb(frame, along * t, along * t + across3 * 1.4, 0.03)
		m.block(cloth, Transform3D(Basis(across3, along, Vector3.FORWARD), along * 4.8 + across3 * 0.75 + Vector3(0.0, 0.0, 0.05)), Vector3(1.4, 5.4, 0.03))
	m.rod(frame, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -0.8)), 0.18, 1.8)
	for pair in [[frame, k.surface("timber", 0.6), "SailFrames"], [cloth, PoiKit.plain(Color(0.86, 0.83, 0.74), 0.9), "SailCloth"]]:
		var st: SurfaceTool = pair[0]
		await k.step()
		var inst := MeshInstance3D.new()
		k.finish_mesh(inst, st)
		inst.material_override = pair[1]
		inst.name = str(pair[2])
		sails.add_child(inst)
		if k.far:
			k._far_range(inst)
	k.marker("the_wheel", foot + Vector3(face.x, 0.0, face.y) * (r + 2.0), true)
	await _millyard(d, {"door": foot + Vector3(face.x, 0.0, face.y) * (r + 0.4)}, face)


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
		await k.step()
		k.place(stone, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 0.8, true)
		var q := d2 + face * 0.9 - side * 2.4
		await k.step()
		k.place(stone, k.on_ground(q.x, q.y, 0.9), PoiKit.yaw_of(side), 0.8, true, Vector3(PI * 0.42, 0.0, 0.0))
	var sack := k.prop("sack")
	if sack != "":
		for i in 6:
			var p := d2 + face * k.rng.randf_range(1.0, 2.2) + side * (1.0 + float(i) * 0.5)
			await k.step()
			k.place(sack, k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.0, false)
	var cart := k.prop("cart")
	if cart != "":
		var p := d2 + face * 5.0 - side * 3.0
		await k.step()
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
	await _commit_fabric(d, fabric)
	# the bell-post: two posts and a head beam by the gate, the bell hung from it
	var posts := m.begin()
	var bell_at := toward_road * (half_d - 3.0) + side * 4.0
	var hang := m.frame(posts, bell_at, PoiKit.yaw_of(side), 1.4, 3.4, 0.2)
	await k.step()
	m.commit(posts, k.surface("timber", 0.6), "BellPost", true)
	var bell := k.prop("bell_medium")
	var bell_scale := 0.55
	if bell == "":
		bell = k.prop("bell_small")
		bell_scale = 2.4
	if bell != "":
		var h := PoiKit.height_of(bell) * bell_scale
		await k.step()
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
				await k.step()
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
				await k.step()
				var node2 := k.place(path, k.on_ground(q.x, q.y), k.rng.randf_range(0.0, TAU), 1.0, false)
				if node2 != null:
					node2.reparent(market)
	var cart := k.prop("cart")
	if cart != "":
		for s in [-1.0, 1.0]:
			var p := -toward_road * (half_d - 3.5) + side * float(s) * (half_w * 0.5)
			await k.step()
			var node := k.place(cart, k.on_ground(p.x, p.y), PoiKit.yaw_of(side) + k.rng.randf_range(-0.3, 0.3), 1.0, true)
			if node != null:
				node.reparent(market)
	k.marker("the_market", k.on_ground(0.0, 0.0), true)
	await _grass(d, _verge(d), Vector2.ZERO, half_w, 40)
