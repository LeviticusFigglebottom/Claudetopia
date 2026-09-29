extends RefCounted
## The outsides of the large sites: fortified places you walk round, into and up (a fort, a bandit
## stockade, a watchtower, a ruined castle, a walled camp), and the way into a site's inside from
## the country (`delve`: a mouth in rock with the door at the back of its throat).
##
## Like the other builders this has no class_name (see poi_builders.gd): PoiBuilders reaches it by
## path. A POI def chooses it by its `kind` and says the rest in its `site` block:
##
##   "site": {"style": "fort|stockade|watchtower|castle_ruin|walled_camp",
##            "radius": 18, "keep": "core:interior/<id>", "gate_bearing_deg": 200,
##            "garrison": {"rank": [ids], "archers": [ids], "heavy": [ids], "count": 8},
##            "interior": "core:interior/<id>"   (delve: the inside its door leads to),
##            "hook": "core:dialogue/<id>"         (a notice or a thing at the gate that starts its quest)}
##
## Walls follow the ground in bays with one walkway level for the whole circuit, so a walkway never
## steps; stairs go up the inside of the curtain beside the gate; the towers stand at the corners at
## walkway height with a parapet round their tops. Everything you stand on has a box under it the
## size of what you see. Laid a step at a time (PoiKit.step), silhouettes kept for the far ring.

const LAND := preload("res://world/pois/poi_builders_land.gd")

const STYLES := {
	"fort": {"wall_h": 5.5, "thick": 2.6, "walkway": true, "crenels": true, "towers": "square", "broken": 0.0,
			"material": "stone", "radius": 18.0, "sides": 4},
	"castle_ruin": {"wall_h": 6.5, "thick": 2.8, "walkway": true, "crenels": true, "towers": "drum", "broken": 0.45,
			"material": "stone", "radius": 22.0, "sides": 5},
	"stockade": {"wall_h": 3.6, "thick": 0.5, "walkway": true, "crenels": false, "towers": "timber", "broken": 0.0,
			"material": "timber", "radius": 16.0, "sides": 6},
	"walled_camp": {"wall_h": 1.7, "thick": 0.9, "walkway": false, "crenels": false, "towers": "none", "broken": 0.1,
			"material": "stone", "radius": 14.0, "sides": 7},
	"watchtower": {"wall_h": 1.2, "thick": 0.7, "walkway": false, "crenels": false, "towers": "none", "broken": 0.2,
			"material": "stone", "radius": 9.0, "sides": 6, "tower": true},
}


static func build(d: PoiDressing) -> void:
	var def := ContentDB.get_or_empty(d.poi_id)
	var site: Dictionary = def.get("site", {})
	if d.kind == "delve":
		await delve(d, site)
		return
	var style := str(site.get("style", d.kind))
	await enclosure(d, site, style)


# --- the way into an inside -------------------------------------------------------------------------

## A mouth in rock (the cave builder's own), and at the back of its throat the door to the inside the
## def names. Its inside's rock is worked out on a worker thread as soon as this is raised, so the
## way in finds it ready.
static func delve(d: PoiDressing, site: Dictionary) -> void:
	await LAND.cave(d)
	var k := d.kit
	if k.far:
		return
	var interior := str(site.get("interior", ""))
	var mouth := d.find_child("the_mouth", true, false) as Node3D
	var at := mouth.position if mouth != null else Vector3.ZERO
	var out := Vector2(-at.x, -at.z).normalized() if Vector2(at.x, at.z).length() > 0.5 else Vector2(0, -1)
	# further in than where its foes wait: the back of the lit part of the throat
	var p := Vector3(at.x, at.y, at.z) - Vector3(out.x, 0.0, out.y) * 3.0
	if interior != "" and ContentDB.has(interior):
		var door := Door.new()
		door.name = "Door_" + Ids.name_of(interior)
		door.interior_id = interior
		door.display_name = str(ContentDB.get_or_empty(interior).get("name", "the dark"))
		door.position = p
		door.rotation.y = atan2(out.x, out.y)
		d.add_child(door)
		SiteInterior.prefetch(ContentDB.get_or_empty(interior))
	var theme := str(site.get("mouth", ""))
	if theme == "lava" or d.region.ends_with("cinderlea"):
		# the tube still breathes: heat in the cracks at its lip, a thread of smoke
		var st := d.masonry.begin()
		for i in 7:
			var q := Vector2(at.x, at.z) + out * k.rng.randf_range(0.5, 5.0) + Vector2(out.y, -out.x) * k.rng.randf_range(-2.5, 2.5)
			var g := k.on_ground(q.x, q.y, 0.02)
			d.masonry.block(st, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), g), Vector3(0.1, 0.05, k.rng.randf_range(0.6, 1.4)))
		await k.step()
		d.masonry.commit(st, PoiKit.plain(Color(0.3, 0.08, 0.02), 0.6, 0.0, Color(1.0, 0.32, 0.06), 2.2), "Cracks")
		k.puffs(Vector3(at.x, at.y + 3.0, at.z) + Vector3(out.x, 0.0, out.y) * 2.0, Vector3(1.0, 0.4, 1.0), 3.0, 8, Color(0.35, 0.33, 0.3, 0.35), 2.2, 6.0)
	await _hook(d, site, Vector3(at.x, 0.0, at.z) + Vector3(out.x, 0.0, out.y) * 7.5)


## Whatever at the way in starts the site's quest: a notice nailed to a post, or a pilgrim's cairn
## with a note under its top stone; touching it puts the hook's conversation.
static func _hook(d: PoiDressing, site: Dictionary, near: Vector3) -> void:
	var hook := str(site.get("hook", ""))
	if hook == "" or not ContentDB.has(hook) or d.kit.far:
		return
	var k := d.kit
	var at := k.on_ground(near.x, near.z)
	var timber := d.masonry.begin()
	var top := d.masonry.post(timber, Vector2(at.x, at.z), 1.7, 0.16)
	d.masonry.block(timber, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), top + Vector3.DOWN * 0.35), Vector3(0.55, 0.4, 0.04))
	await k.step()
	d.masonry.commit(timber, k.surface("timber", 0.6), "HookPost")
	k.collider(Vector3(0.2, 1.7, 0.2), Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.85), "wood")
	k.touchable("Hook", top + Vector3.DOWN * 0.3, str(site.get("hook_prompt", "Read the notice")), hook)


# --- walls, gates, walkways, towers -----------------------------------------------------------------

static func enclosure(d: PoiDressing, site: Dictionary, style: String) -> void:
	var k := d.kit
	var m := d.masonry
	var prof: Dictionary = (STYLES.get(style, STYLES["fort"]) as Dictionary).duplicate()
	for key in site.get("profile", {}):
		prof[key] = site["profile"][key]
	var radius := float(site.get("radius", prof["radius"]))
	radius = minf(radius, maxf(d.pad_radius - 3.0, 9.0))
	var sides := int(prof["sides"])
	var timber := str(prof["material"]) == "timber"
	var stone_mat: Material = k.surface("stone", 0.75)
	var wood_mat: Material = k.surface("timber", 0.6)
	var plank_mat: Material = k.surface("planks", 0.6)
	var wall_mat: Material = wood_mat if timber else stone_mat
	# the gate faces the road where there is one, else downhill
	var gate_dir := k.road_direction(120.0)
	if site.has("gate_bearing_deg"):
		var b := deg_to_rad(float(site["gate_bearing_deg"]))
		gate_dir = Vector2(sin(b), cos(b))
	if gate_dir == Vector2.ZERO:
		gate_dir = k.downhill()
	if gate_dir == Vector2.ZERO:
		gate_dir = Vector2(0, 1)
	gate_dir = gate_dir.normalized()
	var gate_a := atan2(gate_dir.x, gate_dir.y)
	# the corners, the gate in the middle of the first side
	var corners: Array[Vector2] = []
	for i in sides:
		var a := gate_a + PI / float(sides) + TAU * float(i) / float(sides)
		var wob := 1.0 + k.rng.randf_range(-0.06, 0.06)
		corners.append(Vector2(sin(a), cos(a)) * radius * wob)
	# the walkway's one level: the highest ground under the circuit and the wall's height over it
	var high := -INF
	var low := INF
	for i in sides:
		var a := corners[i]
		var b := corners[(i + 1) % sides]
		for t in 9:
			var p := a.lerp(b, float(t) / 8.0)
			var g := k.on_ground(p.x, p.y).y
			high = maxf(high, g)
			low = minf(low, g)
	var walk_y := high + float(prof["wall_h"])
	var thick := float(prof["thick"])
	var broken := float(prof["broken"])
	var walk_points: Array = []   # where the garrison walks the walls, in local space
	var tower_tops: Array = []
	var gate_at := Vector3.ZERO
	var walls := m.begin()
	var trim := m.begin()
	for i in sides:
		var a := corners[i]
		var b := corners[(i + 1) % sides]
		var gate := i == sides - 1
		var run := a.distance_to(b)
		var dir := (b - a) / run
		var yaw := atan2(dir.x, dir.y)
		var basis := Basis(Vector3.UP, yaw)
		var inward := Vector2(-dir.y, dir.x)
		if inward.dot(-(a + b) * 0.5) < 0.0:
			inward = -inward
		var bays := maxi(int(run / 4.0), 2)
		for j in bays:
			var t0 := float(j) / float(bays)
			var t1 := float(j + 1) / float(bays)
			var mid_t := (t0 + t1) * 0.5
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var mid := (p0 + p1) * 0.5
			var in_gate := gate and absf(mid_t - 0.5) < 0.5 / float(bays) + 0.01 and bays >= 3
			var foot := minf(k.on_ground(p0.x, p0.y).y, k.on_ground(p1.x, p1.y).y) - 0.8
			var top := walk_y
			if broken > 0.0:
				var tear := 0.5 + 0.5 * sin(float(i) * 2.3 + float(j) * 1.7 + k.rng.randf() * 0.4)
				top = walk_y - (walk_y - high - 1.0) * broken * 1.6 * clampf(tear - 0.3, 0.0, 1.0)
			var bay_len := run / float(bays) + (0.02 if timber else 0.1)
			var centre := Vector3(mid.x, 0.0, mid.y) + Vector3(inward.x, 0.0, inward.y) * 0.0
			if in_gate:
				gate_at = Vector3(mid.x, k.on_ground(mid.x, mid.y).y, mid.y)
				await _gate(d, gate_at, basis, inward, bay_len, walk_y, thick, timber, walls, trim)
				continue
			if timber:
				await _palisade(d, walls, p0, p1, foot, top)
			else:
				var h := top - foot
				m.block(walls, Transform3D(basis, Vector3(centre.x, foot + h * 0.5, centre.z)), Vector3(thick, h, bay_len))
				k.collider(Vector3(thick, h, bay_len), Transform3D(basis, Vector3(centre.x, foot + h * 0.5, centre.z)), "stone")
				# a plinth at the foot, where the wall meets the hill
				m.block(trim, Transform3D(basis, Vector3(centre.x, foot + 1.1, centre.z)), Vector3(thick + 0.35, 0.5, bay_len + 0.02))
			if bool(prof["crenels"]) and top >= walk_y - 0.01:
				# merlons along the outer lip, a low kerb along the inner
				var outer := Vector3(-inward.x, 0.0, -inward.y) * (thick * 0.5 - 0.25)
				var n := maxi(int(bay_len / 1.6), 1)
				for q in n:
					var s := (float(q) + 0.5) / float(n) - 0.5
					var mp := Vector3(centre.x, walk_y + 0.55, centre.z) + outer + basis * Vector3(0.0, 0.0, s * bay_len)
					m.block(walls, Transform3D(basis, mp), Vector3(0.5, 1.1, bay_len / float(n) * 0.55))
				k.collider(Vector3(0.5, 1.1, bay_len), Transform3D(basis, Vector3(centre.x, walk_y + 0.55, centre.z) + outer), "stone")
				var kerb := Vector3(inward.x, 0.0, inward.y) * (thick * 0.5 - 0.15)
				m.block(trim, Transform3D(basis, Vector3(centre.x, walk_y + 0.2, centre.z) + kerb), Vector3(0.3, 0.4, bay_len))
			if bool(prof["walkway"]) and top >= walk_y - 0.01:
				walk_points.append(Vector3(mid.x, walk_y, mid.y) + Vector3(inward.x, 0.0, inward.y) * (0.3 if not timber else 1.2))
		# stairs up the inside of the wall either side of the gate
		if gate and bool(prof["walkway"]):
			await _wall_stairs(d, a, b, inward, walk_y, thick, timber, walls if not timber else trim)
		await k.step()
	m.commit(walls, wall_mat, "Walls", true)
	m.commit(trim, stone_mat if not timber else plank_mat, "WallTrim", true)
	# towers at the corners
	var tower_kind := str(prof["towers"])
	for i in sides:
		if tower_kind == "none":
			break
		var c := corners[i]
		var g := k.on_ground(c.x, c.y).y
		var tumbled := broken > 0.0 and k.rng.randf() < broken * 0.8
		var top := await _tower(d, c, g, walk_y, tower_kind, tumbled, stone_mat, wood_mat, plank_mat)
		if top != Vector3.INF:
			tower_tops.append(top)
	if bool(prof.get("tower", false)):
		var top2 := await _tall_tower(d, stone_mat, wood_mat)
		tower_tops.append(top2)
	# the yard: a keep with the way into its undercroft, the garrison's shelter, fire and stores
	await _yard(d, site, gate_dir, radius, walk_y, timber)
	await _hook(d, site, gate_at + Vector3(gate_dir.x, 0.0, gate_dir.y) * 5.0 + Vector3(gate_dir.y, 0.0, -gate_dir.x) * 3.0)
	if not k.far:
		await _garrison(d, site, walk_points, tower_tops, gate_at, gate_dir)


## The gate: two piers, a lintel carrying the walkway over, and the leaves swung open.
static func _gate(d: PoiDressing, at: Vector3, basis: Basis, inward: Vector2, width: float, walk_y: float,
		thick: float, timber: bool, walls: SurfaceTool, trim: SurfaceTool) -> void:
	var k := d.kit
	var m := d.masonry
	var open := 3.6
	var pier := maxf((width - open) * 0.5, 0.6)
	var t := maxf(thick, 1.2) + 0.6
	var foot := at.y - 0.8
	var h := walk_y - foot
	for s in [-1.0, 1.0]:
		var c := at + basis * Vector3(0.0, 0.0, float(s) * (open * 0.5 + pier * 0.5))
		c.y = foot + h * 0.5
		m.block(walls, Transform3D(basis, c), Vector3(t, h + (0.0 if timber else 1.2), pier))
		k.collider(Vector3(t, h + (0.0 if timber else 1.2), pier), Transform3D(basis, c), "wood" if timber else "stone")
	# the lintel and the walkway over it
	var lintel_y := at.y + 4.2
	var over := at
	over.y = (lintel_y + walk_y) * 0.5
	var lh := walk_y - lintel_y
	if lh > 0.2:
		m.block(walls, Transform3D(basis, over), Vector3(t, lh, open + 0.1))
		k.collider(Vector3(t, lh, open + 0.1), Transform3D(basis, over), "wood" if timber else "stone")
	# the leaves, swung back inside
	var leaves := m.begin()
	var into := Vector3(inward.x, 0.0, inward.y)
	for s in [-1.0, 1.0]:
		var hinge := at + basis * Vector3(0.0, 0.0, float(s) * open * 0.5) + into * (t * 0.5)
		var leaf_dir := into.rotated(Vector3.UP, float(s) * 0.25)
		var c := hinge + leaf_dir * (open * 0.25) + Vector3.UP * 1.9
		c.y = at.y + 1.9
		m.block(leaves, Transform3D(Basis(Vector3.UP, atan2(leaf_dir.x, leaf_dir.z)), c), Vector3(0.16, 3.8, open * 0.5))
	await k.step()
	m.commit(leaves, k.surface("planks", 0.7), "GateLeaves")


## Stairs up the inside of the curtain from the yard to the walkway, one either side of the gate,
## running along the wall.
static func _wall_stairs(d: PoiDressing, a: Vector2, b: Vector2, inward: Vector2, walk_y: float, thick: float,
		timber: bool, st: SurfaceTool) -> void:
	var k := d.kit
	var m := d.masonry
	var dir := (b - a).normalized()
	for s in [0, 1]:
		# from beside the gate toward the corner, climbing
		var start_on := (a + b) * 0.5 + dir * (3.2 if s == 0 else -3.2)
		var run_dir := dir if s == 0 else -dir
		var off := inward * (thick * 0.5 + 0.8)
		var start := start_on + off
		var g := k.on_ground(start.x, start.y).y
		var rise := walk_y - g
		var count := maxi(int(ceil(rise / 0.3)), 1)
		var step_rise := rise / float(count)
		m.steps(st, start, run_dir, g, count, step_rise, 0.36, 1.5, 0.9 if not timber else 0.25)
		# the flight's own slope as one walkable ramp over the treads, for a smooth foot and the foes
		var len := 0.36 * float(count)
		var mid := start + run_dir * (len * 0.5)
		var pitch := atan2(rise, len)
		var xf := Transform3D(Basis(Vector3.UP, atan2(run_dir.x, run_dir.y)) * Basis(Vector3.RIGHT, pitch),
				Vector3(mid.x, g + rise * 0.5 - 0.05, mid.y))
		k.collider(Vector3(1.5, 0.1, sqrt(len * len + rise * rise)), xf, "wood" if timber else "stone")
		# the landing into the walkway
		var land := start + run_dir * (len + 0.6)
		k.collider(Vector3(1.8, 0.3, 1.4), Transform3D(Basis(Vector3.UP, atan2(run_dir.x, run_dir.y)), Vector3(land.x, walk_y - 0.15, land.y)), "stone")
		m.block(st, Transform3D(Basis(Vector3.UP, atan2(run_dir.x, run_dir.y)), Vector3(land.x, walk_y - 0.15, land.y)), Vector3(1.8, 0.3, 1.4))
		await k.step()


## A palisade bay: stakes of split timber with sharpened tops, a walkway of planks behind it.
static func _palisade(d: PoiDressing, st: SurfaceTool, p0: Vector2, p1: Vector2, foot: float, top: float) -> void:
	var k := d.kit
	var m := d.masonry
	var run := p0.distance_to(p1)
	var dir := (p1 - p0) / run
	var n := maxi(int(run / 0.34), 2)
	for i in n:
		var p := p0.lerp(p1, (float(i) + 0.5) / float(n))
		var h := top + 1.2 + k.rng.randf_range(-0.2, 0.25) - foot
		m.rod(st, Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), Vector3(p.x, foot + h * 0.5, p.y)), 0.16, h)
		m.limb(st, Vector3(p.x, foot + h - 0.02, p.y), Vector3(p.x, foot + h + 0.35, p.y), 0.07)
	var yaw := atan2(dir.x, dir.y)
	var mid := (p0 + p1) * 0.5
	k.collider(Vector3(0.36, top + 1.2 - foot, run), Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, (foot + top + 1.2) * 0.5, mid.y)), "wood")
	# the fighting step behind it
	var inward := -mid.normalized()
	var deck := m.begin()
	var posts := m.begin()
	var a := p0 + inward * 1.2
	var b := p1 + inward * 1.2
	m.plank_deck(deck, posts, a, b, 1.8, top, 2.5, false)
	await k.step()
	m.commit(deck, k.surface("planks", 0.6), "FightingStep", true)
	m.commit(posts, k.surface("timber", 0.6), "FightingStepPosts")


## A corner tower at walkway height with a parapet round its top (square or round), a timber
## platform on posts, or a tumbled stump. Returns where a watcher stands on it (INF: nowhere).
static func _tower(d: PoiDressing, c: Vector2, g: float, walk_y: float, kind: String, tumbled: bool,
		stone: Material, wood: Material, planks: Material) -> Vector3:
	var k := d.kit
	var m := d.masonry
	var st := m.begin()
	var top_y := walk_y + 0.0
	var out := Vector3.INF
	match kind:
		"square", "drum":
			var side := 5.2
			var foot := g - 1.0
			var h := (top_y - foot) * (0.55 if tumbled else 1.0)
			var yaw := atan2(c.x, c.y)
			var basis := Basis(Vector3.UP, yaw)
			if kind == "drum":
				m.drum(st, Transform3D(Basis.IDENTITY, Vector3(c.x, foot, c.y)), side * 0.55, h + (0.0 if tumbled else 1.3), 0.25 if tumbled else 0.0)
				if not tumbled:
					m.block(st, Transform3D(basis, Vector3(c.x, top_y - 0.2, c.y)), Vector3(side * 0.95, 0.4, side * 0.95))
					k.collider(Vector3(side, h, side), Transform3D(basis, Vector3(c.x, foot + h * 0.5, c.y)), "stone")
			else:
				m.block(st, Transform3D(basis, Vector3(c.x, foot + h * 0.5, c.y)), Vector3(side, h, side))
				k.collider(Vector3(side, h, side), Transform3D(basis, Vector3(c.x, foot + h * 0.5, c.y)), "stone")
				if not tumbled:
					for s in 4:
						var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(s))
						var e := bb * Vector3(0.0, 0.0, side * 0.5 - 0.25)
						for q in 3:
							var along := bb * Vector3((float(q) - 1.0) * side * 0.33, 0.0, 0.0)
							m.block(st, Transform3D(bb, Vector3(c.x, top_y + 0.6, c.y) + e + along), Vector3(side * 0.2, 1.2, 0.5))
						k.collider(Vector3(side, 1.2, 0.5), Transform3D(bb, Vector3(c.x, top_y + 0.6, c.y) + e), "stone")
					m.block(st, Transform3D(basis, Vector3(c.x, foot + 1.4, c.y)), Vector3(side + 0.4, 0.6, side + 0.4))
			if not tumbled:
				out = Vector3(c.x, top_y, c.y) * Vector3(0.96, 1.0, 0.96)
			await k.step()
			m.commit(st, stone, "Tower", true)
		"timber":
			var tall := top_y + 2.4
			var posts := m.begin()
			for s in 4:
				var a := PI * 0.25 + PI * 0.5 * float(s)
				var p := c + Vector2(sin(a), cos(a)) * 1.6
				var pg := k.on_ground(p.x, p.y).y
				m.rod(posts, Transform3D(Basis.IDENTITY, Vector3(p.x, (pg + tall + 1.4) * 0.5, p.y)), 0.14, tall + 1.4 - pg)
			var deck := m.begin()
			m.block(deck, Transform3D(Basis(Vector3.UP, atan2(c.x, c.y)), Vector3(c.x, tall - 0.05, c.y)), Vector3(3.6, 0.12, 3.6))
			k.collider(Vector3(3.6, 0.2, 3.6), Transform3D(Basis(Vector3.UP, atan2(c.x, c.y)), Vector3(c.x, tall - 0.1, c.y)), "wood")
			# a roof of boards over it
			m.block(deck, Transform3D(Basis(Vector3.UP, atan2(c.x, c.y)) * Basis(Vector3.RIGHT, 0.25), Vector3(c.x, tall + 2.6, c.y)), Vector3(4.0, 0.1, 4.2))
			# a stair from the fighting step
			var inward := -c.normalized()
			var foot2 := c + inward * 2.2
			m.steps(deck, foot2 + Vector2(inward.y, -inward.x) * 0.0, Vector2(-inward.y, inward.x), top_y - 0.05, 8, 0.3, 0.3, 1.0, 0.12)
			await k.step()
			m.commit(posts, wood, "WatchPosts", true)
			m.commit(deck, planks, "WatchDeck", true)
			out = Vector3(c.x, tall, c.y)
	return out


## A tall watchtower in the middle: a square stone shaft with a stair of flights up its outside to
## a platform with a parapet and a beacon basket.
static func _tall_tower(d: PoiDressing, stone: Material, wood: Material) -> Vector3:
	var k := d.kit
	var m := d.masonry
	var st := m.begin()
	var g := k.on_ground(0.0, 0.0).y
	var side := 4.6
	var h := 12.0
	var yaw := k.grain().angle()
	var basis := Basis(Vector3.UP, yaw)
	m.block(st, Transform3D(basis, Vector3(0.0, g - 1.0 + (h + 1.0) * 0.5, 0.0)), Vector3(side, h + 1.0, side))
	k.collider(Vector3(side, h + 1.0, side), Transform3D(basis, Vector3(0.0, g - 1.0 + (h + 1.0) * 0.5, 0.0)), "stone")
	var top := g + h
	for s in 4:
		var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(s))
		var e := bb * Vector3(0.0, 0.0, side * 0.5 + 0.2)
		m.block(st, Transform3D(bb, Vector3(0.0, top + 0.5, 0.0) + e), Vector3(side + 0.8, 1.0, 0.4))
		k.collider(Vector3(side + 0.8, 1.0, 0.4), Transform3D(bb, Vector3(0.0, top + 0.5, 0.0) + e), "stone")
	m.block(st, Transform3D(basis, Vector3(0.0, top - 0.1, 0.0)), Vector3(side + 1.2, 0.3, side + 1.2))
	# flights round the outside, one per face, each climbing a quarter of the height
	var steps_st := m.begin()
	for s in 4:
		var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(s))
		var y0 := g + h * float(s) / 4.0
		var start3 := bb * Vector3(side * 0.5 + 0.75, 0.0, -side * 0.5 - 0.75)
		var dir3 := bb * Vector3(0.0, 0.0, 1.0)
		var count := int((h / 4.0) / 0.3)
		m.steps(steps_st, Vector2(start3.x, start3.z), Vector2(dir3.x, dir3.z), y0, count, (h / 4.0) / float(count), (side + 1.5) / float(count), 1.4, 0.35)
	await k.step()
	m.commit(st, stone, "Watchtower", true)
	m.commit(steps_st, stone, "WatchtowerStair", true)
	var basket := m.begin()
	m.rod(basket, Transform3D(Basis.IDENTITY, Vector3(0.0, top + 0.8, 0.0)), 0.12, 1.6)
	m.block(basket, Transform3D(Basis.IDENTITY, Vector3(0.0, top + 1.7, 0.0)), Vector3(0.9, 0.3, 0.9))
	m.commit(basket, wood, "Beacon")
	k.light(Vector3(0.0, top + 2.0, 0.0), Color(1.0, 0.6, 0.3), 2.5, 14.0)
	return Vector3(1.2, top, 1.2)


## The yard: the keep (and the door into its undercroft), the garrison's lean-tos along the wall, a
## fire, stores, a cart and a banner.
static func _yard(d: PoiDressing, site: Dictionary, gate_dir: Vector2, radius: float, walk_y: float, timber: bool) -> void:
	var k := d.kit
	var m := d.masonry
	var back := -gate_dir
	var keep_id := str(site.get("keep", ""))
	if keep_id != "" or bool(site.get("keep_building", not timber)):
		# the keep against the back wall, its door facing the gate
		var kc := back * (radius * 0.42)
		var g := k.on_ground(kc.x, kc.y).y
		var w := minf(radius * 0.6, 11.0)
		var dpt := minf(radius * 0.45, 8.5)
		var h := walk_y - g + 4.5
		var basis := Basis(Vector3.UP, atan2(gate_dir.x, gate_dir.y))
		var st := m.begin()
		m.block(st, Transform3D(basis, Vector3(kc.x, g - 1.0 + (h + 1.0) * 0.5, kc.y)), Vector3(w, h + 1.0, dpt))
		k.collider(Vector3(w, h + 1.0, dpt), Transform3D(basis, Vector3(kc.x, g - 1.0 + (h + 1.0) * 0.5, kc.y)), "stone")
		# its parapet and a plinth
		for s in [-1.0, 1.0]:
			for q in 5:
				var x := (float(q) - 2.0) * w * 0.22
				m.block(st, Transform3D(basis, Vector3(kc.x, g + h + 0.5, kc.y) + basis * Vector3(x, 0.0, float(s) * (dpt * 0.5 - 0.25))), Vector3(w * 0.12, 1.0, 0.5))
		m.block(st, Transform3D(basis, Vector3(kc.x, g + 0.4, kc.y)), Vector3(w + 0.5, 0.8, dpt + 0.5))
		# the door: a stone surround proud of the front, dark boards in it
		var front := kc + gate_dir * (dpt * 0.5)
		var fr := Vector3(front.x, g, front.y)
		for s in [-1.0, 1.0]:
			m.block(st, Transform3D(basis, fr + basis * Vector3(float(s) * 1.0, 1.4, 0.2)), Vector3(0.5, 2.8, 0.5))
		m.block(st, Transform3D(basis, fr + basis * Vector3(0.0, 3.0, 0.2)), Vector3(2.5, 0.5, 0.55))
		# narrow windows up the face
		var dark := m.begin()
		for q in 3:
			m.block(dark, Transform3D(basis, fr + basis * Vector3((float(q) - 1.0) * w * 0.3, h * 0.72, 0.03)), Vector3(0.35, 1.1, 0.1))
		m.block(dark, Transform3D(basis, fr + basis * Vector3(0.0, 1.3, 0.04)), Vector3(1.5, 2.6, 0.1))
		await k.step()
		m.commit(st, k.surface("stone", 0.8), "Keep", true)
		m.commit(dark, PoiKit.plain(Color(0.06, 0.05, 0.045), 0.9), "KeepDark", true)
		if keep_id != "" and ContentDB.has(keep_id) and not k.far:
			var door := Door.new()
			door.name = "Door_" + Ids.name_of(keep_id)
			door.interior_id = keep_id
			door.display_name = str(ContentDB.get_or_empty(keep_id).get("name", "the keep"))
			door.position = fr + basis * Vector3(0.0, 0.0, 0.3)
			door.rotation.y = atan2(gate_dir.x, gate_dir.y)
			d.add_child(door)
			SiteInterior.prefetch(ContentDB.get_or_empty(keep_id))
			k.light(fr + basis * Vector3(1.6, 2.4, 0.8), Color(1.0, 0.66, 0.35), 1.8, 8.0)
	if k.far:
		return
	# lean-tos along the side walls
	var side := Vector2(gate_dir.y, -gate_dir.x)
	var roofs := m.begin()
	var posts := m.begin()
	for s in [-1.0, 1.0]:
		var c := side * float(s) * (radius * 0.62) + back * (radius * 0.05)
		var g := k.on_ground(c.x, c.y).y
		var yaw := atan2(side.x * float(s), side.y * float(s))
		var basis := Basis(Vector3.UP, yaw)
		for q in 3:
			var p := Vector3(c.x, g, c.y) + basis * Vector3((float(q) - 1.0) * 2.4, 0.0, -1.3)
			m.post(posts, Vector2(p.x, p.z), 2.1, 0.15)
		m.block(roofs, Transform3D(basis * Basis(Vector3.RIGHT, -0.32), Vector3(c.x, g + 2.5, c.y) + basis * Vector3(0.0, 0.0, 0.2)), Vector3(6.0, 0.1, 3.4))
		k.collider(Vector3(6.0, 0.1, 3.4), Transform3D(basis * Basis(Vector3.RIGHT, -0.32), Vector3(c.x, g + 2.5, c.y) + basis * Vector3(0.0, 0.0, 0.2)), "wood")
		for q in 2:
			var bp := Vector3(c.x, g, c.y) + basis * Vector3((float(q) - 0.5) * 2.2, 0.0, 0.6)
			var roll := k.prop("bedroll")
			if roll != "":
				k.place(roll, k.on_ground(bp.x, bp.z), yaw + k.rng.randf_range(-0.2, 0.2), 1.0, false)
		await k.step()
	m.commit(roofs, k.surface("planks", 0.7), "LeanTos")
	m.commit(posts, k.surface("timber", 0.7), "LeanToPosts")
	# the fire in the yard and what stands round it
	var fire := gate_dir * (radius * 0.12)
	var fg := k.on_ground(fire.x, fire.y)
	var fp := k.prop("campfire")
	if fp != "":
		k.place(fp, fg, 0.0, 1.0, false)
		k.light(fg + Vector3.UP * 0.8, Color(1.0, 0.6, 0.28), 2.4, 12.0)
		k.puffs(fg + Vector3.UP * 1.0, Vector3(0.3, 0.2, 0.3), 3.0, 10, Color(0.35, 0.33, 0.3, 0.35), 1.4, 5.0)
	d.set_meta("yard_fire", fg)
	for kind in ["barrel", "barrel", "crate", "crate", "sack", "cart", "banner", "chopping_block"]:
		var a := k.rng.randf() * TAU
		var p := side * (k.rng.randf_range(-1.0, 1.0) * radius * 0.45) + back * (k.rng.randf_range(-0.1, 0.25) * radius)
		if p.distance_to(fire) < 3.0:
			p += side * 3.0
		var path := k.prop(kind)
		if path != "":
			k.place(path, k.on_ground(p.x, p.y), a, 1.0, kind != "banner")
		await k.step()
	var rack := k.prop("spear")
	if rack != "":
		for q in 3:
			var p := side * (radius * 0.35) + back * (float(q) * 0.5)
			k.place(rack, k.on_ground(p.x, p.y), k.rng.randf() * TAU, 1.0, false, Vector3(0.25, 0.0, 0.0))


## Who holds it: archers on the towers, a pair walking the walls, guards at the gate, the rest by
## the fire (asleep at night, awake by day). Foes named in `garrison`, or the region's.
static func _garrison(d: PoiDressing, site: Dictionary, walk: Array, towers: Array, gate_at: Vector3, gate_dir: Vector2) -> void:
	var g: Dictionary = site.get("garrison", {})
	if g.is_empty() and not site.has("garrison"):
		return
	var region := Ids.name_of(d.region) if d.region.contains("/") else d.region
	var dflt: Array = SiteKinds.REGION_FOES.get(region, SiteKinds.REGION_FOES["hearthvale"])
	var rank: Array = g.get("rank", dflt[0])
	var archers: Array = g.get("archers", dflt[1])
	var heavy: Array = g.get("heavy", dflt[2])
	var k := d.kit
	var sp := EnemySpawner.new()
	sp.name = "Garrison"
	sp.spawn_on_ready = false
	d.add_child(sp)
	await k.step()
	var pick := func(list: Array) -> String: return str(list[k.rng.randi() % list.size()]) if not list.is_empty() else ""
	var stand := func(id: String, at: Vector3, yaw: float, opts: Dictionary) -> Enemy:
		if id == "" or not ContentDB.has(id):
			return null
		return sp.spawn_one(id, d.to_global(at + Vector3.UP * 0.1), yaw, opts)
	# archers on the tower tops
	for i in mini(towers.size(), int(g.get("tower_archers", 3))):
		var t: Vector3 = towers[i]
		var e: Enemy = stand.call(pick.call(archers), t, atan2(t.x, t.z), {"group": d.poi_id + "/towers"})
		if e != null:
			e.brain.post = e.global_position
		await k.step()
	# a pair walking the walls, round half the circuit and back
	if walk.size() >= 4:
		var route: Array = []
		for i in walk.size() / 2 + 1:
			route.append(d.to_global(walk[i]))
		stand.call(pick.call(rank), walk[0], 0.0, {"group": d.poi_id + "/walls", "patrol": route})
		var back_route := route.duplicate()
		back_route.reverse()
		stand.call(pick.call(rank), walk[walk.size() / 2], PI, {"group": d.poi_id + "/walls", "patrol": back_route})
		await k.step()
	# the gate's guards, facing out
	var out_yaw := atan2(-gate_dir.x, -gate_dir.y)
	for s in [-1.0, 1.0]:
		var p := gate_at - Vector3(gate_dir.x, 0.0, gate_dir.y) * 2.5 + Vector3(gate_dir.y, 0.0, -gate_dir.x) * float(s) * 2.2
		stand.call(pick.call(rank if s < 0.0 else heavy), k.on_ground(p.x, p.z), out_yaw, {"group": d.poi_id + "/gate"})
	await k.step()
	# the rest round the fire
	var fire: Vector3 = d.get_meta("yard_fire", Vector3.ZERO)
	var rest := int(g.get("count", 8)) - 6
	for i in maxi(rest, 1):
		var a := TAU * float(i) / float(maxi(rest, 1))
		var p := fire + Vector3(sin(a), 0.0, cos(a)) * 2.4
		var e: Enemy = stand.call(pick.call(rank), k.on_ground(p.x, p.z), a + PI, {"group": d.poi_id + "/yard"})
		if e != null and _is_night():
			e.inactive = true
		await k.step()


static func _is_night() -> bool:
	return WorldClock.is_night()
