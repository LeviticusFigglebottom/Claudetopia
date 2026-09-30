extends RefCounted
## The outsides of the large sites: fortified places you walk round, into and up (a fort, a bandit
## stockade, a watchtower, a ruined castle, a walled camp), and the way into a site's inside from
## the country (`delve`: a mouth in rock with the door at the back of its throat, or with `"mouth":
## "lava"` a lava tube breaking out of the heath).
##
## Like the other builders this has no class_name (see poi_builders.gd): PoiBuilders reaches it by
## path. A POI def chooses it by its `kind` and says the rest in its `site` block:
##
##   "site": {"style": "fort|stockade|watchtower|castle_ruin|walled_camp",
##            "radius": 18, "keep": "core:interior/<id>", "gate_bearing_deg": 200,
##            "garrison": {"rank": [ids], "archers": [ids], "heavy": [ids], "count": 8},
##            "interior": "core:interior/<id>"   (delve: the inside its door leads to),
##            "mouth": "lava"                      (delve: a lava tube's mouth, not a cave's),
##            "hook": "core:dialogue/<id>"         (a notice or a thing at the gate that starts its quest)}
##
## Walls follow the ground in bays with one walkway level for the whole circuit, so a walkway never
## steps; stairs go up the inside of the curtain beside the gate; the towers stand at the corners at
## walkway height with a parapet round their tops. Everything you stand on has a box under it the
## size of what you see. Laid a step at a time (PoiKit.step), silhouettes kept for the far ring.
##
## The stone is the region's own, weathered (site_stone.gdshader): each block laid carries the height
## of the ground under it and of the top of its wall, so the grime rises from the real ground and the
## rain runs down from the real parapet. The first fort was clean white blocks with even crenels, like
## a toy (the 0-C review sheet): now its merlons are of uneven height, some broken and some fallen
## at its foot; its courses stand on a stepped plinth under a string course, with buttresses,
## repairs in a paler stone, putlog holes and the odd crack; the gate is a gatehouse with an arch, a
## portcullis and a box over it; the keep has a corbelled parapet, corner turrets, dressed windows
## and a pentice over its door; the yard is trodden earth with a well, a table, hay, firewood and
## hens, and weeds grow along the walls' feet.

const LAND := preload("res://world/pois/poi_builders_land.gd")
const STONE_SHADER := preload("res://world/sites/site_stone.gdshader")
const LAVA_GROUND_SHADER := preload("res://world/sites/site_lava_ground.gdshader")
const EMBER_SHADER := preload("res://assets/shaders/ember_crack.gdshader")

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

## How a region's weather marks its stone: the stone's value against the painted surface's (the
## Vale's chalk is near white there; a wall of it two hundred years on the down is not), and how
## much moss, lichen and grime it carries. Skerrow's limestone is lichen country, the marsh and
## the wood are moss, the ash country is soot and hardly anything grows on it.
const WEATHER := {
	"hearthvale": {"value": 0.74, "moss": 0.6, "lichen": 0.55, "grime": 0.75, "warm": "#e0c79f"},
	"brightwater": {"value": 0.95, "moss": 0.6, "lichen": 0.5, "grime": 0.7, "warm": "#d8c6a6"},
	"sedgemire": {"value": 1.05, "moss": 0.9, "lichen": 0.3, "grime": 0.8, "warm": "#c9c2a4"},
	"briarwold": {"value": 1.0, "moss": 0.85, "lichen": 0.45, "grime": 0.7, "warm": "#cdc3a0"},
	"skerrow": {"value": 0.86, "moss": 0.35, "lichen": 0.85, "grime": 0.55, "warm": "#d9c9aa"},
	"cinderlea": {"value": 0.95, "moss": 0.06, "lichen": 0.25, "grime": 0.9, "warm": "#c4a88f"},
}


static func build(d: PoiDressing) -> void:
	var def := ContentDB.get_or_empty(d.poi_id)
	var site: Dictionary = def.get("site", {})
	if d.kind == "delve":
		await delve(d, site)
		return
	var style := str(site.get("style", d.kind))
	await enclosure(d, site, style)


# --- weathered stone --------------------------------------------------------------------------------

## A batch of stone blocks for site_stone.gdshader: each vertex carries the ground's height under it
## (UV2.x, with UV2.y set) and the top of its wall (UV.x), and each block a tint (COLOR). One batch
## is one mesh, one draw call.
class Stones:
	extends RefCounted
	var st := SurfaceTool.new()
	var kit: PoiKit
	## the top of the wall the next blocks belong to (local height), for the rain's streaks
	var top := 0.0
	var rng := RandomNumberGenerator.new()
	var blocks := 0
	var _ground: Dictionary = {}
	static var _box_v := PackedVector3Array()
	static var _box_n := PackedVector3Array()

	func _init(k: PoiKit, seed_i: int) -> void:
		kit = k
		rng.seed = seed_i
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		if _box_v.is_empty():
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			var a := box.get_mesh_arrays()
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			for i in idx:
				_box_v.append(v[i])
				_box_n.append(n[i])

	func ground(x: float, z: float) -> float:
		var key := Vector2i(roundi(x * 2.0), roundi(z * 2.0))
		if not _ground.has(key):
			_ground[key] = kit.on_ground(float(key.x) * 0.5, float(key.y) * 0.5).y
		return _ground[key]

	## One block of `size` at `xf` (its scale ignored), tinted a shade of its own unless `tint` says.
	func block(xf: Transform3D, size: Vector3, tint := Color(0, 0, 0, 0), top_y := NAN) -> void:
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			return
		var nb := xf.basis.orthonormalized()
		var t := Transform3D(nb, xf.origin).scaled_local(size)
		var ty := top if is_nan(top_y) else top_y
		var c := tint
		if c.a == 0.0:
			var v := rng.randf_range(0.93, 1.05)
			c = Color(v, v * rng.randf_range(0.985, 1.01), v * rng.randf_range(0.97, 1.0))
		var uv := Vector2(ty, 0.0)
		for i in _box_v.size():
			var p := t * _box_v[i]
			st.set_normal(nb * _box_n[i])
			st.set_color(c)
			st.set_uv(uv)
			st.set_uv2(Vector2(ground(p.x, p.z), 1.0))
			st.add_vertex(p)
		blocks += 1


static var _stone_looks: Dictionary = {}


## The region's stone, weathered: its colours from PoiKit.SURFACES brought to a weathered value, and
## the region's moss, lichen and grime (WEATHER). `ground_y` is the ground's height for a mesh whose
## vertices do not carry it (a drum tower's courses).
static func stone_look(k: PoiKit, ground_y := 0.0) -> ShaderMaterial:
	var key := "%s/%.2f" % [k.region, ground_y]
	if _stone_looks.has(key):
		return _stone_looks[key]
	var by_region: Dictionary = PoiKit.SURFACES.get(k.region, PoiKit.SURFACES["hearthvale"])
	var spec: Dictionary = by_region.get("stone", {})
	var w: Dictionary = WEATHER.get(k.region, WEATHER["hearthvale"])
	var value := float(w["value"])
	var mat := ShaderMaterial.new()
	mat.shader = STONE_SHADER
	var base := Color.html(str(spec.get("base", "#b0a89a")))
	var accent := Color.html(str(spec.get("accent", "#8f887a")))
	var grout := Color.html(str(spec.get("grout", "#5a554c")))
	mat.set_shader_parameter("base_color", Color(base.r * value, base.g * value, base.b * value * 0.97))
	mat.set_shader_parameter("accent_color", Color(accent.r * value * 0.96, accent.g * value * 0.95, accent.b * value * 0.9))
	mat.set_shader_parameter("grout_color", Color(grout.r * value * 0.8, grout.g * value * 0.8, grout.b * value * 0.78))
	mat.set_shader_parameter("unit_size", float(spec.get("unit", 0.42)))
	mat.set_shader_parameter("warm_tint", Color.html(str(w["warm"])))
	mat.set_shader_parameter("moss_amount", float(w["moss"]))
	mat.set_shader_parameter("lichen_amount", float(w["lichen"]))
	mat.set_shader_parameter("grime_amount", float(w["grime"]))
	if k.region == "cinderlea":
		mat.set_shader_parameter("grime_color", Color(0.22, 0.2, 0.19))
		mat.set_shader_parameter("moss_color", Color(0.36, 0.36, 0.3))
		mat.set_shader_parameter("moss_dark", Color(0.24, 0.24, 0.2))
	mat.set_shader_parameter("ground_y", ground_y)
	_stone_looks[key] = mat
	return mat


## A block into a batch: weathered stone (Stones) or any masonry batch.
static func _blk(d: PoiDressing, st: Variant, xf: Transform3D, size: Vector3) -> void:
	if st is Stones:
		(st as Stones).block(xf, size)
	else:
		d.masonry.block(st as SurfaceTool, xf, size)


static func _commit(d: PoiDressing, st: Variant, mat: Material, node_name: String, silhouette := false) -> MeshInstance3D:
	if st is Stones:
		return d.masonry.commit((st as Stones).st, stone_look(d.kit), node_name, silhouette)
	return d.masonry.commit(st as SurfaceTool, mat, node_name, silhouette)


const DARK := Color(0.05, 0.045, 0.04)


# --- the way into an inside -------------------------------------------------------------------------

## A mouth in rock (the cave builder's own, or a lava tube's), and at the back of its throat the door
## to the inside the def names. Its inside's rock is worked out on a worker thread as soon as this is
## raised, so the way in finds it ready.
static func delve(d: PoiDressing, site: Dictionary) -> void:
	if str(site.get("mouth", "")) == "lava":
		await lava_mouth(d, site)
		return
	await LAND.cave(d)
	var k := d.kit
	if k.far:
		return
	var interior := str(site.get("interior", ""))
	var mouth := d.find_child("the_mouth", true, false) as Node3D
	var at := mouth.position if mouth != null else Vector3.ZERO
	var out := Vector2(-at.x, -at.z).normalized() if Vector2(at.x, at.z).length() > 0.5 else Vector2(0, -1)
	# further in than where its foes wait: the back of the lit part of the throat
	_door(d, interior, Vector3(at.x, at.y, at.z) - Vector3(out.x, 0.0, out.y) * 3.0, atan2(out.x, out.y))
	if d.region.ends_with("cinderlea"):
		# the rock still breathes: heat in the cracks at its lip, a thread of smoke
		var cracks: Array = []
		for i in 4:
			var q := Vector2(at.x, at.z) + out * k.rng.randf_range(1.0, 5.0) + Vector2(out.y, -out.x) * k.rng.randf_range(-2.5, 2.5)
			cracks.append([q, Vector2(k.rng.randf_range(1.2, 2.4), 0.8), k.rng.randf() * TAU, k.rng.randf(), 0.7])
		await _embers(d, cracks)
		k.puffs(Vector3(at.x, at.y + 3.0, at.z) + Vector3(out.x, 0.0, out.y) * 2.0, Vector3(1.0, 0.4, 1.0), 3.0, 8, Color(0.35, 0.33, 0.3, 0.35), 2.2, 6.0)
	# the cairn to one side of the way in, not in it
	await _hook(d, site, Vector3(at.x, 0.0, at.z) + Vector3(out.x, 0.0, out.y) * 7.0 + Vector3(out.y, 0.0, -out.x) * 3.5)


static func _door(d: PoiDressing, interior: String, at: Vector3, yaw: float) -> void:
	if interior == "" or not ContentDB.has(interior) or d.kit.far:
		return
	var door := Door.new()
	door.name = "Door_" + Ids.name_of(interior)
	door.interior_id = interior
	door.display_name = str(ContentDB.get_or_empty(interior).get("name", "the dark"))
	door.position = at
	door.rotation.y = yaw
	d.add_child(door)
	SiteInterior.prefetch(ContentDB.get_or_empty(interior))


## Ember cracks on the ground (the ash country's own, ember_crack.gdshader): each [centre (local xz),
## size (length, width), angle, seed 0..1, glow 0..1]. One mesh, following the ground.
static func _embers(d: PoiDressing, cracks: Array, lift := 0.04, floor_y := NAN) -> void:
	var k := d.kit
	if k.far or cracks.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for c in cracks:
		var p: Vector2 = c[0]
		var size: Vector2 = c[1]
		var along := Vector2(cos(float(c[2])), sin(float(c[2])))
		var across := Vector2(-along.y, along.x)
		var tag := Color(float(c[3]), float(c[4]), 0.0, 1.0)
		var nu := clampi(int(ceil(size.x * 1.5)), 2, 10)
		var nv := 2
		for j in nv + 1:
			for i in nu + 1:
				var u := float(i) / float(nu)
				var v := float(j) / float(nv)
				var q := p + along * (u - 0.5) * size.x + across * (v - 0.5) * size.y
				st.set_color(tag)
				st.set_uv(Vector2(u, v))
				st.add_vertex(Vector3(q.x, floor_y + lift, q.y) if not is_nan(floor_y) else k.on_ground(q.x, q.y, lift))
		for j in nv:
			for i in nu:
				var i0 := base + j * (nu + 1) + i
				for idx in [i0, i0 + 1, i0 + nu + 2, i0, i0 + nu + 2, i0 + nu + 1]:
					st.add_index(idx)
		base += (nu + 1) * (nv + 1)
	await k.step()
	var mat := ShaderMaterial.new()
	mat.shader = EMBER_SHADER
	mat.render_priority = 1
	var mi := MeshInstance3D.new()
	mi.name = "Embers"
	k.finish_mesh(mi, st)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	k.root.add_child(mi)


## Whatever at the way in starts the site's quest: a notice nailed to a post (two, where the prompt
## says notices), or a pilgrim's cairn with a note under its top stone where it says cairn; touching
## it puts the hook's conversation.
static func _hook(d: PoiDressing, site: Dictionary, near: Vector3, on_y := NAN) -> void:
	var hook := str(site.get("hook", ""))
	if hook == "" or not ContentDB.has(hook) or d.kit.far:
		return
	var k := d.kit
	var prompt := str(site.get("hook_prompt", "Read the notice"))
	# on the ground, or on what a builder laid over it (the lava tube's rise)
	var at := k.on_ground(near.x, near.z) if is_nan(on_y) else Vector3(near.x, on_y, near.z)
	if prompt.to_lower().contains("cairn"):
		# a pilgrim's cairn: flat stones of the place, each smaller, the top one a slab with a
		# corner of paper showing under it
		var stones := d.masonry.begin()
		var y := at.y - 0.1
		var r := 0.62
		for i in 6:
			var h := 0.2 + k.rng.randf() * 0.08
			var tilt := Basis(Vector3.UP, k.rng.randf() * TAU) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.12, 0.12))
			d.masonry.ellipsoid(stones, Vector3(at.x, y + h * 0.5, at.z) + Vector3(k.rng.randf_range(-0.06, 0.06), 0.0, k.rng.randf_range(-0.06, 0.06)),
					Vector3(r, h * 0.6, r * k.rng.randf_range(0.75, 0.95)), tilt)
			y += h * 0.8
			r *= 0.8
		var top := Vector3(at.x, y + 0.05, at.z)
		d.masonry.ellipsoid(stones, top, Vector3(0.34, 0.07, 0.26), Basis(Vector3.UP, k.rng.randf() * TAU))
		await k.step()
		d.masonry.commit(stones, stone_look(k, at.y), "Cairn")
		var note := d.masonry.begin()
		d.masonry.block(note, Transform3D(Basis(Vector3.UP, 0.4), top + Vector3(0.18, -0.06, 0.1)), Vector3(0.16, 0.012, 0.12))
		d.masonry.commit(note, PoiKit.plain(Color(0.82, 0.78, 0.66), 0.9), "CairnNote")
		k.collider(Vector3(1.1, y - at.y + 0.2, 1.1), Transform3D(Basis.IDENTITY, at + Vector3.UP * (y - at.y) * 0.5), "stone")
		k.touchable("Hook", top + Vector3.UP * 0.1, prompt, hook)
		return
	var timber := d.masonry.begin()
	var top2 := d.masonry.post(timber, Vector2(at.x, at.z), 1.7, 0.16)
	var yaw := k.rng.randf() * TAU
	var board := Transform3D(Basis(Vector3.UP, yaw), top2 + Vector3.DOWN * 0.35)
	d.masonry.block(timber, board, Vector3(0.55, 0.4, 0.04))
	await k.step()
	d.masonry.commit(timber, k.surface("timber", 0.6), "HookPost")
	# the notices on it: one, or two where the prompt says notices, the second lower and askew
	var paper := d.masonry.begin()
	for s in [-1.0, 1.0]:
		var face := board.basis * Vector3(0.0, 0.0, 0.03 * s)
		d.masonry.block(paper, Transform3D(board.basis * Basis(Vector3.BACK, 0.05), board.origin + face + board.basis * Vector3(-0.08, 0.04, 0.0)), Vector3(0.26, 0.3, 0.01))
		if prompt.to_lower().contains("notices"):
			d.masonry.block(paper, Transform3D(board.basis * Basis(Vector3.BACK, -0.18), board.origin + face * 1.4 + board.basis * Vector3(0.12, -0.08, 0.0)), Vector3(0.22, 0.24, 0.01))
	d.masonry.commit(paper, PoiKit.plain(Color(0.8, 0.76, 0.64), 0.9), "Notices")
	k.collider(Vector3(0.2, 1.7, 0.2), Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.85), "wood")
	k.touchable("Hook", top2 + Vector3.DOWN * 0.3, prompt, hook)


# --- a lava tube's mouth ------------------------------------------------------------------------------

## A lava tube breaking out of the heath. The land rises a little over the tube, so little it reads
## as the lie of the heath (a couple of metres over twenty), and the tube's roof has fallen in
## where it came near the surface: a trench cut down into the rise, walled by the tube's broken
## sides of black crust, floored with the fallen roof, a ramp of rubble at its foot to walk down.
## At its head the mouth: an arch rimmed with black glass where the lava's skin chilled, drips
## hanging from it, and the tube going in and bending away, its walls glassy black and lit by the
## ember cracks in them, a haze in it, the light of the fire coming round the bend. Ash and cinders
## and shards of the glass lie about the rim and the heath round it, fewer further out; the crust
## breaks through the soil in patches. The skirts are the terrain's own soil at the terrain's own
## scale, going under it at their edges: no edge to find.
##
## The land cannot be dug at runtime, so the trench is cut into the rise rather than the ground:
## its floor is the ground. (The world build could sink it for real; see WORLD_LIFE_INTERIORS.)
## The first mouth was the cave builder's crag and bank on a flat pad (a raw lumpy mound, an odd
## bank, a boulder in a black box at the door); the second a mound with a painted glow in its throat.
const TUBE_W := 3.0          ## the tube's half-width at its mouth
const TUBE_H := 3.2          ## its height at its mouth
const TRENCH := 12.0         ## how far the trench runs out in front of the mouth
const RISE := 2.3            ## how high the land stands over the trench's floor at its rim
const SKIRT := 21.0          ## over how far the rise goes back into the heath


## The tube's shape in the mouth's frame (u across, v into the land): its path, the land over it.
class Tube:
	extends RefCounted
	var noise := FastNoiseLite.new()
	var broad := FastNoiseLite.new()
	var path: Array[Vector2] = []     # the throat's centre line, (u, v), from the mouth in
	var lengths: Array[float] = []

	func _init(seed_i: int, side: float) -> void:
		noise.seed = seed_i
		noise.frequency = 0.16
		broad.seed = seed_i + 7
		broad.frequency = 0.045
		# straight in, then bending away to one side, out of sight of the mouth
		var pts: Array[Vector2] = [Vector2(0.0, -0.3), Vector2(0.0, 6.0), Vector2(side * 1.6, 9.2), Vector2(side * 4.4, 12.0), Vector2(side * 7.6, 13.8)]
		# smoothed into short runs
		for i in pts.size() - 1:
			for t in 4:
				path.append(pts[i].lerp(pts[i + 1], float(t) / 4.0))
		path.append(pts[-1])
		var total := 0.0
		lengths.append(0.0)
		for i in range(1, path.size()):
			total += path[i].distance_to(path[i - 1])
			lengths.append(total)

	func total_length() -> float:
		return lengths[-1]

	## The point `s` metres along the throat, and its heading (unit, u v).
	func along(s: float) -> Array:
		for i in range(1, path.size()):
			if lengths[i] >= s or i == path.size() - 1:
				var seg := lengths[i] - lengths[i - 1]
				var t := clampf((s - lengths[i - 1]) / maxf(seg, 0.001), 0.0, 1.0)
				return [path[i - 1].lerp(path[i], t), (path[i] - path[i - 1]).normalized()]
		return [path[-1], Vector2(0, 1)]

	## How far (u, v) is from the throat's centre line.
	func to_path(p: Vector2) -> float:
		var best := INF
		for i in range(1, path.size()):
			var a := path[i - 1]
			var ab := path[i] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, (a + ab * t).distance_to(p))
		return best

	## The land's height over the trench floor at (u, v), and its look: [height, rock, glass, warm].
	func height(u: float, v: float) -> Array:
		var au := absf(u)
		var p := Vector2(u, v)
		var lump := noise.get_noise_2d(u, v)
		var fine := noise.get_noise_2d(u * 3.1 + 40.0, v * 3.1)
		var dp := to_path(p)
		# how far from the trench and the throat: the rise falls away over SKIRT from them
		var dt := Vector2(maxf(au - TUBE_W, 0.0), maxf(maxf(-TRENCH - v, v - 0.0), 0.0)).length()
		var fd := minf(dt, maxf(dp - TUBE_W, 0.0) if v > 0.0 else INF)
		var base := RISE * (1.0 - smoothstep(0.5, SKIRT, fd)) * (1.0 + 0.25 * broad.get_noise_2d(u, v))
		# a low swell over the tube itself, its roof never thinner than a hand's breadth or two
		var roof := (TUBE_H + 0.65) * (1.0 - smoothstep(TUBE_W + 1.0, TUBE_W + 6.0, dp)) if v > 0.4 else 0.0
		var h := maxf(base, roof)
		if v > 0.4 and dp < TUBE_W + 0.9:
			h = maxf(h, TUBE_H + 0.65)
		# the trench, cut down into the rise to the ground: steep broken walls, a floor of rubble,
		# a ramp at its foot
		var in_trench := au < TUBE_W + 1.1 and v < 0.6 and v > -TRENCH - 2.0
		var rock := 0.0
		if in_trench:
			var wall := smoothstep(TUBE_W - 0.5, TUBE_W + 1.1, au + lump * 0.4)
			var floor_h := 0.12 + 0.18 * fine
			# the ramp down into it at its foot
			floor_h = maxf(floor_h, RISE * smoothstep(-TRENCH + 6.0, -TRENCH - 1.8, v))
			h = lerpf(floor_h, h, wall)
			rock = maxf(rock, wall * (1.0 - wall) * 4.0)
			rock = maxf(rock, smoothstep(TUBE_W - 0.8, TUBE_W + 0.4, au) * smoothstep(-TRENCH + 2.0, -TRENCH + 5.0, v))
		h += lump * 0.22 * smoothstep(0.3, 1.2, h) + fine * 0.06
		# the crust breaking through the soil in patches, most near the mouth, fewer out on the heath
		var patches := smoothstep(0.5, 0.72, broad.get_noise_2d(u * 2.3 + 17.0, v * 2.3)) * (1.0 - smoothstep(3.0, 11.0, fd))
		rock = maxf(rock, patches)
		# the rim of the trench and the ground over the mouth: crust
		rock = maxf(rock, (1.0 - smoothstep(0.3, 2.2, dt)) * smoothstep(0.6, 1.4, h) * 0.9)
		rock = maxf(rock, (1.0 - smoothstep(TUBE_W + 0.5, TUBE_W + 4.0, Vector2(u, maxf(v, 0.0)).length())) * smoothstep(-2.0, 0.5, v))
		var glass := (1.0 - smoothstep(0.4, 2.6, Vector2(maxf(au - TUBE_W, 0.0), absf(v)).length())) * 0.85
		var warm := (1.0 - smoothstep(1.0, 7.0, p.length())) * 0.45
		return [h, clampf(rock, 0.0, 1.0), glass, warm]


static func lava_mouth(d: PoiDressing, site: Dictionary) -> void:
	var k := d.kit
	var face := k.downhill()
	if face == Vector2.ZERO:
		face = k.grain()
	if face == Vector2.ZERO:
		face = Vector2(0, 1)
	face = face.normalized()
	var into := -face
	var across := Vector2(into.y, -into.x)
	var mouth := into * 4.0
	var o := k.on_ground(mouth.x, mouth.y)
	var tube := Tube.new(int(k.rng.randi() % 100000), -1.0 if k.rng.randf() < 0.5 else 1.0)
	var crust := _lava_material(d, mouth - into * 12.0)
	var ys: Dictionary = await _tube_ground(d, tube, mouth, into, across, o, crust)
	await _headwall(d, tube, mouth, into, across, o, crust)
	# where whatever lives in it waits, a little way in out of the light
	var den := mouth + into * 3.5
	k.marker("the_mouth", Vector3(den.x, o.y, den.y), false, true, TUBE_W)
	if k.far:
		return
	var door_at: Array = await _throat(d, tube, mouth, into, across, o, crust)
	await _lip(d, mouth, into, across, o, crust)
	await _trench_floor(d, mouth, into, across, o, crust)
	await _shards(d, tube, mouth, into, across, o, crust)
	var at: Vector3 = door_at[0]
	var back: Vector3 = door_at[1]
	_door(d, str(site.get("interior", "")), at, atan2(back.x, back.z))
	var door := d.find_child("Door_" + Ids.name_of(str(site.get("interior", ""))), false, false) as Node3D
	if door != null:
		door.set_meta("view_from", at + back * 5.5)
	# the day's light back into the mouth, the fire's at the bend
	var bounce := mouth - into * 5.0
	k.bounce_light(k.on_ground(bounce.x, bounce.y, 3.0), LAND._bounce_colour(k.region), 2.0, 14.0)
	# heat off the mouth: smoke from the crust over it
	k.puffs(Vector3(mouth.x, o.y + TUBE_H + 0.9, mouth.y) + Vector3(into.x, 0.0, into.y) * 1.2, Vector3(1.4, 0.3, 0.8), 3.2, 10,
			Color(0.36, 0.34, 0.32, 0.32), 2.2, 6.5)
	# the cairn at the head of the ramp, to one side of it, on the rise
	var cu := TUBE_W + 3.0
	var cv := -TRENCH - 3.0
	var cairn := mouth + across * cu + into * cv
	await _hook(d, site, Vector3(cairn.x, 0.0, cairn.y), float(ys.get(Vector2i(roundi(cu), roundi(cv)), NAN)))


static func _lava_material(d: PoiDressing, at: Vector2) -> ShaderMaterial:
	var builders: GDScript = load(PoiDressing.BUILDERS_PATH)
	var look: Material = builders.call("_ground_look", d.kit, at)
	var mat := ShaderMaterial.new()
	mat.shader = LAVA_GROUND_SHADER
	if look is StandardMaterial3D:
		var sm := look as StandardMaterial3D
		mat.set_shader_parameter("soil", sm.albedo_texture)
		mat.set_shader_parameter("soil_scale", sm.uv1_scale.x)
		mat.set_shader_parameter("soil_value", sm.albedo_color.r)
	return mat


## The crust's look with its mask fixed, for a mesh with no vertex colours: [rock, glass, warm].
static func _crust_as(crust: Material, mask: Color) -> Material:
	if not (crust is ShaderMaterial):
		return PoiKit.plain(Color(0.03, 0.028, 0.034), 0.5)
	var sm := (crust as ShaderMaterial).duplicate() as ShaderMaterial
	sm.set_shader_parameter("fixed_mask", Color(mask.r, mask.g, mask.b, 1.0))
	return sm


## The land the tube runs under, one mesh a metre a vertex (Tube.height), its skirts going under the
## heath, the mouth's front left open. Returns the heights it laid, by whole metre (u, v), local.
static func _tube_ground(d: PoiDressing, tube: Tube, mouth: Vector2, into: Vector2, across: Vector2, o: Vector3,
		mat: Material) -> Dictionary:
	var k := d.kit
	var step := 1.0 if not k.far else 2.0
	var u0 := -(TUBE_W + SKIRT + 2.0)
	var u1 := TUBE_W + SKIRT + 2.0
	var v0 := -TRENCH - SKIRT - 2.0
	var v1 := 14.0 + SKIRT
	var nu := int(ceil((u1 - u0) / step)) + 1
	var nv := int(ceil((v1 - v0) / step)) + 1
	var pts: Array[Vector3] = []
	var cols: Array[Color] = []
	var up: Array[bool] = []
	var hole: Array[bool] = []
	var ys := {}
	for j in nv:
		for i in nu:
			var u := u0 + float(i) * step
			var v := v0 + float(j) * step
			var at := mouth + across * u + into * v
			var g := k.on_ground(at.x, at.y).y
			var hr: Array = tube.height(u, v)
			var h := float(hr[0])
			# level with the mouth's floor near it, the land's own further out, so on a slope the rise
			# neither stands off the hill nor sinks into it
			var y := lerpf(o.y, g, smoothstep(8.0, SKIRT, Vector2(u, clampf(v, -TRENCH, 14.0) - v).length() + maxf(absf(u) - 8.0, 0.0))) + h
			var raised := h > 0.1 and y > g + 0.05
			pts.append(Vector3(at.x, y if raised else g - 0.3, at.y))
			ys[Vector2i(roundi(u), roundi(v))] = y if raised else g
			cols.append(Color(float(hr[1]), float(hr[2]), float(hr[3]), 1.0))
			up.append(raised)
			# the mouth's front, where the arch and the throat are
			hole.append(absf(u) < TUBE_W + 0.25 and v > -0.8 and v < 1.4)
		if j % 6 == 0:
			await k.step()
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
			var order: Array = [a, b, c, b, e, c] if n.y >= 0.0 else [a, c, b, b, c, e]
			for idx in order:
				st.set_color(cols[int(idx)])
				st.add_vertex(pts[int(idx)])
			quads += 1
	if quads == 0:
		return ys
	await k.step()
	st.generate_normals()
	var mesh := st.commit()
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.name = "TubeGround"
	k.root.add_child(inst)
	if k.far:
		k._far_range(inst)
		return ys
	k.collider_shape(mesh.create_trimesh_shape(), Transform3D.IDENTITY, "stone")
	# the heath's own growth on the rise, never on the crust, thinning toward the mouth
	var tufts: Array = []
	var grass := k.flora(LAND._verge(d))
	for t in 140:
		var u := k.rng.randf_range(u0 * 0.9, u1 * 0.9)
		var v := k.rng.randf_range(v0 + 2.0, v1 - 2.0)
		var hr: Array = tube.height(u, v)
		if float(hr[1]) > 0.25 or Vector2(u, v).length() < 5.0 + k.rng.randf() * 6.0:
			continue
		var q := pts[clampi(int(round((v - v0) / step)), 0, nv - 1) * nu + clampi(int(round((u - u0) / step)), 0, nu - 1)]
		tufts.append(PoiKit.transform_at(q - Vector3(0.0, 0.06, 0.0), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.7, 1.2)))
	if grass != "":
		await k.step()
		k.scatter(grass, tufts, false, false, false)
	return ys


## The face of crust over the mouth's arch, up to the land over the throat: without it the gap
## between the lip and the ground over the throat showed the sky through the hill.
static func _headwall(d: PoiDressing, tube: Tube, mouth: Vector2, into: Vector2, across: Vector2, o: Vector3,
		mat: Material) -> void:
	var k := d.kit
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	var rows := 4
	var grid: Array = []
	var cols: Array = []
	for r in rows + 1:
		var f := float(r) / float(rows)
		var row: Array = []
		var crow: Array = []
		for i in n + 1:
			var a := PI * float(i) / float(n)
			var u := cos(a) * (TUBE_W + 0.9)
			var y0 := pow(sin(a), 0.7) * (TUBE_H + 0.1)
			var hr: Array = tube.height(u, 1.6)
			var y1 := maxf(float(hr[0]), y0 + 0.3) + 0.15
			var y := lerpf(y0, y1, f)
			# the face bulges and hollows as the crust set, most in the middle of its height
			var bulge := tube.noise.get_noise_2d(u * 1.7 + 11.0, y * 1.7) * 0.45 * sin(f * PI)
			var v := lerpf(0.35, 1.3, f) - bulge
			var c := mouth + across * u + into * v
			row.append(Vector3(c.x, o.y + y, c.y))
			crow.append(Color(1.0, lerpf(0.7, 0.1, f), lerpf(0.12, 0.0, f), 1.0))
		grid.append(row)
		cols.append(crow)
	for r in rows:
		for i in n:
			var a_: Vector3 = grid[r][i]
			var b_: Vector3 = grid[r][i + 1]
			var c_: Vector3 = grid[r + 1][i + 1]
			var d_: Vector3 = grid[r + 1][i]
			var ca: Color = cols[r][i]
			var cb: Color = cols[r][i + 1]
			var cc: Color = cols[r + 1][i + 1]
			var cd: Color = cols[r + 1][i]
			for pc in [[a_, ca], [d_, cd], [b_, cb], [b_, cb], [d_, cd], [c_, cc]]:
				st.set_color(pc[1])
				st.add_vertex(pc[0])
	await k.step()
	var mi := MeshInstance3D.new()
	mi.name = "Headwall"
	k.finish_mesh(mi, st)
	mi.material_override = mat
	k.root.add_child(mi)
	if k.far:
		k._far_range(mi)


## The throat: the tube going in under the rise and bending away, oval, its floor level, its walls
## the crust gone to glass and lit by the ember cracks in them, a haze hanging in it, the fire's
## light at the bend. Walked on its own faces. Returns [where the door stands, the way back out].
static func _throat(d: PoiDressing, tube: Tube, mouth: Vector2, into: Vector2, across: Vector2, o: Vector3,
		crust: Material) -> Array:
	var k := d.kit
	var into3 := Vector3(into.x, 0.0, into.y)
	var across3 := Vector3(across.x, 0.0, across.y)
	var total := tube.total_length()
	var rings := int(ceil(total / 0.8))
	var arch_n := 12
	var floor_n := 4
	var ring_pts: Array = []
	var centres: Array = []
	for i in rings + 1:
		var s := total * float(i) / float(rings)
		var al: Array = tube.along(s)
		var c2: Vector2 = al[0]
		var h2: Vector2 = al[1]
		var t := s / total
		var w := TUBE_W * (1.0 - 0.15 * t) + 0.3 * tube.noise.get_noise_1d(s * 2.0)
		var h := TUBE_H * (1.0 - 0.12 * t) + 0.25 * tube.noise.get_noise_1d(s * 1.7 + 50.0)
		# across the heading, in the mouth's frame
		var side3 := (across3 * h2.y - into3 * h2.x).normalized() if h2.length() > 0.0 else across3
		var centre := Vector3(mouth.x, o.y, mouth.y) + across3 * c2.x + into3 * c2.y
		centres.append(centre + Vector3.UP * h * 0.45)
		var ring: Array = []
		# the arch, right to left over the top, then the floor back across
		for j in arch_n + 1:
			var a := PI * float(j) / float(arch_n)
			var wob := 1.0 + 0.1 * tube.noise.get_noise_2d(s * 1.3, float(j) * 2.1)
			ring.append(centre + side3 * (cos(a) * (w + 0.3) * wob) + Vector3.UP * (pow(sin(a), 0.7) * h * wob - 0.05))
		for j in range(1, floor_n):
			var f := float(j) / float(floor_n)
			ring.append(centre + side3 * lerpf(-(w + 0.3), w + 0.3, f) + Vector3.UP * (0.02 + 0.06 * tube.noise.get_noise_2d(s * 2.0, f * 5.0)))
		ring_pts.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var per := (ring_pts[0] as Array).size()
	for i in rings:
		var mid := ((centres[i] as Vector3) + (centres[i + 1] as Vector3)) * 0.5
		for j in per:
			var j1 := (j + 1) % per
			var p00: Vector3 = ring_pts[i][j]
			var p01: Vector3 = ring_pts[i][j1]
			var p10: Vector3 = ring_pts[i + 1][j]
			var p11: Vector3 = ring_pts[i + 1][j1]
			var quad_c := (p00 + p01 + p10 + p11) * 0.25
			# wound to be seen from inside the tube
			var tri := [p00, p10, p11, p00, p11, p01]
			if (p10 - p00).cross(p11 - p00).dot(quad_c - mid) < 0.0:
				tri = [p00, p11, p10, p00, p01, p11]
			for p in tri:
				st.add_vertex(p)
		if i % 6 == 0:
			await k.step()
	# closed at the far end: the way goes on down past the door, black
	var last: Array = ring_pts[-1]
	var cap_c: Vector3 = centres[-1]
	for j in per:
		var p0: Vector3 = last[j]
		var p1: Vector3 = last[(j + 1) % per]
		var tri2 := [cap_c, p0, p1]
		var al_end: Array = tube.along(total)
		var head: Vector2 = al_end[1]
		var fwd := across3 * head.x + into3 * head.y
		if (p0 - cap_c).cross(p1 - cap_c).dot(fwd) < 0.0:
			tri2 = [cap_c, p1, p0]
		for p in tri2:
			st.add_vertex(p)
	await k.step()
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Throat"
	mi.mesh = mesh
	# the crust gone to glass, warm in its cracks
	mi.material_override = _crust_as(crust, Color(1.0, 0.55, 0.6))
	k.root.add_child(mi)
	k.collider_shape(mesh.create_trimesh_shape(), Transform3D.IDENTITY, "stone")
	# the ember cracks along its floor, brighter as it goes in
	var cracks: Array = []
	for i in 12:
		var s := k.rng.randf_range(0.5, total - 0.6)
		var al: Array = tube.along(s)
		var c2: Vector2 = al[0]
		var h2: Vector2 = al[1]
		var q := mouth + across * c2.x + into * c2.y + (across * h2.y - into * h2.x) * k.rng.randf_range(-TUBE_W * 0.6, TUBE_W * 0.6)
		var heading := across * h2.x + into * h2.y
		cracks.append([q, Vector2(k.rng.randf_range(1.2, 2.6), 0.9), atan2(heading.y, heading.x) + k.rng.randf_range(-0.6, 0.6),
				k.rng.randf(), lerpf(0.45, 1.0, s / total)])
	await _embers(d, cracks, 0.03, o.y)
	# the fire's light round the bend, a lesser one at its elbow, and a haze in the air
	var bend: Array = tube.along(total - 1.5)
	var bc: Vector2 = bend[0]
	var bend_at := Vector3(mouth.x, o.y, mouth.y) + across3 * bc.x + into3 * bc.y
	k.light(bend_at + Vector3.UP * 1.4, Color(1.0, 0.4, 0.12), 3.2, 11.0)
	var elbow: Array = tube.along(total * 0.55)
	var ec: Vector2 = elbow[0]
	var elbow_at := Vector3(mouth.x, o.y, mouth.y) + across3 * ec.x + into3 * ec.y
	k.light(elbow_at + Vector3.UP * 2.2, Color(1.0, 0.46, 0.16), 1.6, 8.0)
	k.puffs(elbow_at + Vector3.UP * 1.6, Vector3(1.6, 0.8, 1.6), 0.25, 14, Color(0.42, 0.22, 0.14, 0.16), 3.2, 9.0)
	# the door, a little short of the far end, facing back up the tube
	var door_al: Array = tube.along(total - 1.2)
	var dc: Vector2 = door_al[0]
	var dh: Vector2 = door_al[1]
	var back3 := -(across3 * dh.x + into3 * dh.y).normalized()
	var door_at := Vector3(mouth.x, o.y, mouth.y) + across3 * dc.x + into3 * dc.y
	var view: Array = tube.along(total - 7.0)
	var vc: Vector2 = view[0]
	var view_at := Vector3(mouth.x, o.y, mouth.y) + across3 * vc.x + into3 * vc.y
	return [door_at, (view_at - door_at).normalized() if view_at.distance_to(door_at) > 0.5 else back3]


## Ash, cinders and shards of the black glass lying about the mouth and out over the rise, fewer the
## further out: nothing stops at an edge.
static func _shards(d: PoiDressing, tube: Tube, mouth: Vector2, into: Vector2, across: Vector2, o: Vector3,
		crust: Material) -> void:
	var k := d.kit
	var glass := d.masonry.begin()
	var cinder := d.masonry.begin()
	for i in 420:
		# denser near the mouth and the trench: distance drawn toward the near end
		var r := pow(k.rng.randf(), 1.8) * 20.0 + 0.5
		var a := k.rng.randf() * TAU
		var u := sin(a) * r
		var v := cos(a) * r - TRENCH * 0.4
		var hr: Array = tube.height(u, v)
		if tube.to_path(Vector2(u, v)) < TUBE_W + 0.3 and v > 0.0:
			continue
		var at := mouth + across * u + into * v
		var g := k.on_ground(at.x, at.y).y
		var y := maxf(o.y + float(hr[0]), g) if float(hr[0]) > 0.1 else g
		var p := Vector3(at.x, y + 0.02, at.y)
		var b := Basis(Vector3.UP, k.rng.randf() * TAU) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.5, 0.5))
		if i % 3 == 0:
			var sz := k.rng.randf_range(0.06, 0.2)
			d.masonry.ellipsoid(glass, p, Vector3(sz, sz * 0.35, sz * k.rng.randf_range(0.5, 1.2)), b)
		else:
			var sz := k.rng.randf_range(0.05, 0.16)
			d.masonry.ellipsoid(cinder, p, Vector3(sz, sz * 0.6, sz * k.rng.randf_range(0.7, 1.1)), b)
		if i % 60 == 0:
			await k.step()
	d.masonry.commit(glass, _crust_as(crust, Color(1.0, 1.0, 0.0)), "Shards")
	d.masonry.commit(cinder, _crust_as(crust, Color(1.0, 0.1, 0.0)), "Cinders")


## The mouth's lip: a rim of black glass rolled round the arch where the lava's skin chilled, one
## piece swelling and thinning as it goes (lumps set round it read as a string of beads, then as
## sausages), drips hanging from its crown, its feet in the trench floor. The crust's own look,
## gone to glass.
static func _lip(d: PoiDressing, mouth: Vector2, into: Vector2, across: Vector2, o: Vector3, crust: Material) -> void:
	var k := d.kit
	var noise := FastNoiseLite.new()
	noise.seed = d.poi_id.hash() & 0xffff
	noise.frequency = 0.9
	var n := 30
	var sides := 10
	var up3 := Vector3.UP
	var into3 := Vector3(into.x, 0.0, into.y)
	var across3 := Vector3(across.x, 0.0, across.y)
	var base := Vector3(mouth.x, o.y, mouth.y)
	var arch := func(a: float) -> Vector3:
		return base + across3 * (cos(a) * (TUBE_W + 0.4)) + up3 * (pow(sin(a), 0.7) * (TUBE_H + 0.25) - 0.35 * (1.0 - sin(a)))
	var rings: Array = []
	var centres: Array = []
	for i in n + 1:
		var a := PI * float(i) / float(n)
		var c: Vector3 = arch.call(a)
		var c2: Vector3 = arch.call(clampf(a + 0.02, 0.0, PI))
		var c1: Vector3 = arch.call(clampf(a - 0.02, 0.0, PI))
		var tangent := (c2 - c1).normalized()
		var radial := tangent.cross(into3).normalized()
		if radial.dot(c - (base + up3 * 0.5)) < 0.0:
			radial = -radial
		var swell := 1.0 + noise.get_noise_1d(float(i) * 1.3) * 0.45
		var r1 := 0.42 * swell
		var r2 := 0.75 * swell
		# rolled outward and forward, as the skin curled over the edge
		var centre := c + radial * 0.15 - into3 * (0.15 + 0.2 * noise.get_noise_1d(float(i) * 0.7 + 30.0))
		centres.append(centre)
		var ring: Array = []
		for j in sides:
			var t := TAU * float(j) / float(sides)
			var wob := 1.0 + 0.18 * noise.get_noise_2d(float(i) * 1.1, float(j) * 1.7)
			ring.append(centre + (radial * cos(t) * r1 + into3 * sin(t) * r2) * wob)
		rings.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for j in sides:
			var j1 := (j + 1) % sides
			var p00: Vector3 = rings[i][j]
			var p01: Vector3 = rings[i][j1]
			var p10: Vector3 = rings[i + 1][j]
			var p11: Vector3 = rings[i + 1][j1]
			var mid := ((centres[i] as Vector3) + (centres[i + 1] as Vector3)) * 0.5
			var quad_c := (p00 + p01 + p10 + p11) * 0.25
			# wound to face out of the rim
			var tri := [p00, p10, p11, p00, p11, p01]
			if (p10 - p00).cross(p11 - p00).dot(quad_c - mid) > 0.0:
				tri = [p00, p11, p10, p00, p01, p11]
			for p in tri:
				st.add_vertex(p)
	# drips, hanging from the crown
	for q in 7:
		var a := k.rng.randf_range(0.7, PI - 0.7)
		var c: Vector3 = arch.call(a)
		var dp := c + Vector3.DOWN * 0.35 - into3 * k.rng.randf_range(0.0, 0.3)
		d.masonry.limb(st, dp, dp + Vector3.DOWN * k.rng.randf_range(0.35, 0.9), k.rng.randf_range(0.06, 0.12))
	await k.step()
	var mi := MeshInstance3D.new()
	mi.name = "GlassLip"
	k.finish_mesh(mi, st)
	mi.material_override = _crust_as(crust, Color(1.0, 0.8, 0.05))
	k.root.add_child(mi)
	# its feet: collision either side of the way in
	var yaw := PoiKit.yaw_of(into)
	for s in [-1.0, 1.0]:
		var c := mouth + across * float(s) * (TUBE_W + 0.6)
		k.collider(Vector3(1.0, TUBE_H * 0.7, 1.4), Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, o.y + TUBE_H * 0.35, c.y)), "stone")


## The trench's floor: the roof that fell, in slabs and blocks heaped along the walls, a way clear
## down the middle, the heat's cracks spilling out of the mouth across it.
static func _trench_floor(d: PoiDressing, mouth: Vector2, into: Vector2, across: Vector2, o: Vector3, crust: Material) -> void:
	var k := d.kit
	var yaw := PoiKit.yaw_of(into)
	# the roof's slabs, broken as they fell, tipped against the walls and on one another: the tube's
	# own crust (the ground's material, all rock), in the shader's ropes
	var slabs := Stones.new(k, d.poi_id.hash() + 17)
	var tint := Color(1.0, 0.04, 0.0, 1.0)
	for i in 16:
		var side := -1.0 if i % 2 == 0 else 1.0
		var v := -k.rng.randf_range(0.8, TRENCH - 0.5)
		var u := side * k.rng.randf_range(TUBE_W - 0.9, TUBE_W + 1.4)
		var q := mouth + into * v + across * u
		var g := k.on_ground(q.x, q.y).y
		var size := Vector3(k.rng.randf_range(0.8, 1.5), k.rng.randf_range(0.45, 0.8), k.rng.randf_range(0.7, 1.2))
		# leaning into the wall: tipped up on the side toward it, and broken: a second piece of it
		# set against the first at another angle, so no slab is one clean box
		var lean := Basis(Vector3.UP, yaw + k.rng.randf_range(-0.8, 0.8)) * Basis(Vector3.FORWARD, side * k.rng.randf_range(0.15, 0.55)) \
				* Basis(Vector3.RIGHT, k.rng.randf_range(-0.3, 0.3))
		var at3 := Vector3(q.x, g + size.y * 0.15 + k.rng.randf_range(0.0, 0.25), q.y)
		slabs.block(Transform3D(lean, at3), size, tint)
		# its broken faces: two more pieces through it at other angles, so it is a faceted rock
		for piece in 2:
			var chip := lean * Basis(Vector3(k.rng.randf_range(-1, 1), k.rng.randf_range(-1, 1), k.rng.randf_range(-1, 1)).normalized(), k.rng.randf_range(0.5, 1.2))
			slabs.block(Transform3D(chip, at3 + lean * Vector3(size.x * k.rng.randf_range(-0.25, 0.25), size.y * 0.05, size.z * k.rng.randf_range(-0.25, 0.25))),
					size * Vector3(k.rng.randf_range(0.6, 0.85), k.rng.randf_range(0.75, 1.0), k.rng.randf_range(0.6, 0.85)), tint)
		if i % 3 == 0:
			k.collider(size, Transform3D(lean, Vector3(q.x, g + size.y * 0.2, q.y)), "stone")
		if i % 4 == 0:
			await k.step()
	d.masonry.commit(slabs.st, crust, "RoofFall")
	# a few boulders of it, sunk, and loose stuff between: scree, off the way down the middle
	var boulder := k.rock("boulder")
	if boulder != "":
		var bh := maxf(PoiKit.height_of(boulder), 0.3)
		for i in 5:
			var side := -1.0 if i % 2 == 0 else 1.0
			var q := mouth - into * k.rng.randf_range(2.0, TRENCH) + across * side * k.rng.randf_range(TUBE_W - 0.5, TUBE_W + 1.5)
			var sc := clampf(k.rng.randf_range(0.8, 1.4) / bh, 0.3, 2.0)
			await k.step()
			k.place(boulder, k.on_ground(q.x, q.y, -bh * sc * 0.45), k.rng.randf() * TAU, sc, true,
					Vector3(k.rng.randf_range(-0.4, 0.4), 0.0, k.rng.randf_range(-0.4, 0.4)))
	var scree := k.rock("scree")
	if scree != "":
		var heap: Array = []
		for i in 16:
			var q := mouth - into * k.rng.randf_range(0.8, TRENCH) + across * k.rng.randf_range(-TUBE_W, TUBE_W)
			if absf((q - mouth).dot(across)) < 1.2:
				continue
			heap.append(PoiKit.transform_at(k.on_ground(q.x, q.y, -0.1), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.5, 0.9)))
		await k.step()
		k.scatter(scree, heap, true)
	# the heat spilling out of the mouth across the trench
	var cracks: Array = []
	for i in 12:
		var v := -k.rng.randf_range(0.0, 8.0)
		var q := mouth + into * v + across * k.rng.randf_range(-TUBE_W * 0.9, TUBE_W * 0.9)
		cracks.append([q, Vector2(k.rng.randf_range(1.2, 3.0), 1.0), atan2(into.y, into.x) + k.rng.randf_range(-0.9, 0.9),
				k.rng.randf(), lerpf(0.85, 0.35, -v / 8.0)])
	await _embers(d, cracks)


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
	var seed_i := d.poi_id.hash()
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
	var fallen: Array = []        # merlons fallen off the walls: where they lie at the foot
	# stone: one weathered batch for the walls and their trim; timber: the stakes and the steps
	var walls: Variant
	var trim: Variant
	if timber:
		walls = m.begin()
		trim = m.begin()
	else:
		walls = Stones.new(k, seed_i)
		trim = walls
	var dark := m.begin()
	if walls is Stones:
		(walls as Stones).top = walk_y + 1.2
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
		var outward3 := Vector3(-inward.x, 0.0, -inward.y)
		var bays := maxi(int(run / 4.0), 2)
		if gate and bays % 2 == 0:
			# an odd number of bays, so one is the middle one and the gate stands in it
			bays += 1
		for j in bays:
			var t0 := float(j) / float(bays)
			var t1 := float(j + 1) / float(bays)
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var mid := (p0 + p1) * 0.5
			var in_gate := gate and j == (bays >> 1)
			var g_low := minf(k.on_ground(p0.x, p0.y).y, k.on_ground(p1.x, p1.y).y)
			var foot := g_low - 0.8
			var top := walk_y
			if broken > 0.0:
				var tear := 0.5 + 0.5 * sin(float(i) * 2.3 + float(j) * 1.7 + k.rng.randf() * 0.4)
				top = walk_y - (walk_y - high - 1.0) * broken * 1.6 * clampf(tear - 0.3, 0.0, 1.0)
			var bay_len := run / float(bays) + (0.02 if timber else 0.1)
			var centre := Vector3(mid.x, 0.0, mid.y)
			if in_gate:
				gate_at = Vector3(mid.x, k.on_ground(mid.x, mid.y).y, mid.y)
				await _gate(d, gate_at, basis, inward, bay_len, walk_y, thick, timber, walls, dark)
				continue
			var crenellated := bool(prof["crenels"]) and top >= walk_y - 0.01
			if timber:
				await _palisade(d, walls, p0, p1, foot, top)
			else:
				var h := top - foot
				var body := Transform3D(basis, Vector3(centre.x, foot + h * 0.5, centre.z))
				(walls as Stones).top = top + (1.2 if crenellated else 0.0)
				_blk(d, walls, body, Vector3(thick, h, bay_len))
				k.collider(Vector3(thick, h, bay_len), body, "stone")
				_bay_dressing(d, walls, dark, centre, basis, outward3, thick, bay_len, g_low, top, walk_y, j, bays, gate, crenellated)
			if crenellated:
				# merlons along the outer lip, of uneven height, some broken, the odd one fallen;
				# a low kerb along the inner
				var outer := outward3 * (thick * 0.5 - 0.25)
				var n := maxi(int(bay_len / 1.6), 1)
				for q in n:
					var s := (float(q) + 0.5) / float(n) - 0.5
					var mp := Vector3(centre.x, walk_y, centre.z) + outer + basis * Vector3(0.0, 0.0, s * bay_len)
					var fate := k.rng.randf()
					var mw := bay_len / float(n) * k.rng.randf_range(0.5, 0.6)
					if fate < 0.07:
						# gone: it lies at the wall's foot outside
						var lie := Vector2(mp.x, mp.z) + Vector2(outward3.x, outward3.z) * k.rng.randf_range(1.8, 3.5) + dir * k.rng.randf_range(-1.0, 1.0)
						fallen.append([lie, mw])
						continue
					var mh := k.rng.randf_range(1.0, 1.28)
					var tilt := Basis.IDENTITY
					if fate < 0.2:
						# broken: its top gone, what is left leaning a little
						mh = k.rng.randf_range(0.35, 0.7)
						tilt = Basis(Vector3.RIGHT, k.rng.randf_range(-0.06, 0.06)) * Basis(Vector3.FORWARD, k.rng.randf_range(-0.05, 0.05))
						if k.rng.randf() < 0.6:
							fallen.append([Vector2(mp.x, mp.z) + Vector2(outward3.x, outward3.z) * k.rng.randf_range(1.6, 3.0), mw * 0.7])
					var mb := basis * tilt * Basis(Vector3.UP, k.rng.randf_range(-0.03, 0.03))
					_blk(d, walls, Transform3D(mb, mp + Vector3.UP * mh * 0.5), Vector3(0.55, mh, mw))
					if mh > 0.9 and walls is Stones and k.rng.randf() < 0.45:
						# a coping stone on it, a little proud
						_blk(d, walls, Transform3D(mb, mp + Vector3.UP * (mh + 0.06)), Vector3(0.66, 0.12, mw + 0.1))
					if mh > 0.9 and k.rng.randf() < 0.3:
						# a loop in it for a bow
						m.block(dark, Transform3D(basis, mp + Vector3.UP * mh * 0.5 + outward3 * 0.28), Vector3(0.02, 0.62, 0.1))
				k.collider(Vector3(0.5, 1.1, bay_len), Transform3D(basis, Vector3(centre.x, walk_y + 0.55, centre.z) + outer), "stone")
				var kerb := Vector3(inward.x, 0.0, inward.y) * (thick * 0.5 - 0.15)
				_blk(d, trim, Transform3D(basis, Vector3(centre.x, walk_y + 0.2, centre.z) + kerb), Vector3(0.3, 0.4, bay_len))
			if bool(prof["walkway"]) and top >= walk_y - 0.01:
				walk_points.append(Vector3(mid.x, walk_y, mid.y) + Vector3(inward.x, 0.0, inward.y) * (0.3 if not timber else 1.2))
			await k.step()
		# stairs up the inside of the wall either side of the gate
		if gate and bool(prof["walkway"]):
			await _wall_stairs(d, a, b, inward, walk_y, thick, timber, walls if not timber else trim, run / float(bays) * 0.5,
					{"square": 3.8, "drum": 3.8, "timber": 2.4}.get(str(prof["towers"]), 0.5))
		await k.step()
	if walls is Stones:
		_commit(d, walls, null, "Walls", true)
	else:
		m.commit(walls, wood_mat, "Walls", true)
		m.commit(trim, plank_mat, "WallTrim", true)
	m.commit(dark, PoiKit.plain(DARK, 0.95), "Slits")
	# the merlons that came down, lying where they fell, and the rubble with them
	await _fallen(d, fallen)
	# towers at the corners
	var tower_kind := str(prof["towers"])
	for i in sides:
		if tower_kind == "none":
			break
		var c := corners[i]
		var g := k.on_ground(c.x, c.y).y
		var tumbled := broken > 0.0 and k.rng.randf() < broken * 0.8
		var top := await _tower(d, c, g, walk_y, tower_kind, tumbled, stone_mat, wood_mat, plank_mat, gate_a)
		if top != Vector3.INF:
			tower_tops.append(top)
	if bool(prof.get("tower", false)):
		var top2 := await _tall_tower(d, stone_mat, wood_mat)
		tower_tops.append(top2)
	# the yard: a keep with the way into its undercroft, the garrison's shelter, fire and stores
	await _yard(d, site, gate_dir, radius, walk_y, timber, gate_at)
	if not timber:
		await _wall_growth(d, corners, gate_at, thick)
	await _hook(d, site, gate_at + Vector3(gate_dir.x, 0.0, gate_dir.y) * 5.0 + Vector3(gate_dir.y, 0.0, -gate_dir.x) * 3.0)
	if not k.far:
		await _garrison(d, site, walk_points, tower_tops, gate_at, gate_dir)


## What makes a bay of stone curtain a wall that has stood a long time: a stepped plinth where it
## meets the ground, a string course under the walkway, now and then a buttress, a patch of repair
## in a paler stone, putlog holes and a crack.
static func _bay_dressing(d: PoiDressing, sw: Stones, dark: SurfaceTool, centre: Vector3, basis: Basis, outward: Vector3,
		thick: float, bay_len: float, g_low: float, top: float, walk_y: float, j: int, bays: int, gate_side: bool,
		crenellated: bool) -> void:
	var m := d.masonry
	var tall := top - g_low
	# the plinth: two courses stepping back, outside and in
	sw.block(Transform3D(basis, Vector3(centre.x, g_low - 0.35, centre.z)), Vector3(thick + 0.8, 1.3, bay_len + 0.04))
	sw.block(Transform3D(basis, Vector3(centre.x, g_low + 0.52, centre.z)), Vector3(thick + 0.4, 0.44, bay_len + 0.03))
	# the string course on the outer face, a hand under the walkway
	if crenellated:
		sw.block(Transform3D(basis, Vector3(centre.x, walk_y - 0.45, centre.z) + outward * (thick * 0.5 + 0.06)), Vector3(0.2, 0.24, bay_len + 0.02))
	# a buttress every other bay on a long side, off the gate's side
	if tall > 4.0 and not gate_side and bays >= 4 and j % 2 == 1 and j < bays - 1:
		var bp := centre - basis * Vector3(0.0, 0.0, bay_len * 0.5)
		var lower := tall * 0.5
		var low_at := bp + outward * (thick * 0.5 + 0.55) + Vector3.UP * (g_low - 0.5 + (lower + 0.5) * 0.5)
		sw.block(Transform3D(basis, low_at), Vector3(1.1, lower + 0.5, 1.5))
		var upper := tall - lower - 1.4
		if upper > 0.3:
			sw.block(Transform3D(basis, bp + outward * (thick * 0.5 + 0.3) + Vector3.UP * (g_low + lower + upper * 0.5)), Vector3(0.6, upper, 1.2))
		sw.block(Transform3D(basis, bp + outward * (thick * 0.5 + 0.55) + Vector3.UP * (g_low + lower + 0.05)), Vector3(1.18, 0.2, 1.58))
		d.kit.collider(Vector3(1.1, lower + 0.5, 1.5), Transform3D(basis, low_at), "stone")
	var roll := sw.rng.randf()
	if tall > 3.5:
		# a repair in another stone: a patch of the face relaid, paler and cleaner
		if roll < 0.3:
			var pw := sw.rng.randf_range(1.2, maxf(1.3, minf(bay_len - 0.6, 3.0)))
			var ph := sw.rng.randf_range(1.0, maxf(1.2, tall * 0.45))
			var py := g_low + sw.rng.randf_range(1.2, maxf(1.3, tall - ph - 0.4)) + ph * 0.5
			var pz := sw.rng.randf_range(-(bay_len - pw) * 0.5, (bay_len - pw) * 0.5)
			sw.block(Transform3D(basis, Vector3(centre.x, py, centre.z) + outward * (thick * 0.5 + 0.015) + basis * Vector3(0.0, 0.0, pz)),
					Vector3(0.03, ph, pw), Color(1.1, 1.08, 1.02))
		# putlog holes: where the scaffold's poles went in, a row of them
		if sw.rng.randf() < 0.55:
			var py2 := g_low + sw.rng.randf_range(2.0, maxf(2.1, tall - 1.2))
			var count := sw.rng.randi_range(1, 3)
			for q in count:
				var pz2 := (float(q) - float(count - 1) * 0.5) * 1.3
				m.block(dark, Transform3D(basis, Vector3(centre.x, py2, centre.z) + outward * (thick * 0.5 + 0.005) + basis * Vector3(0.0, 0.0, pz2)), Vector3(0.02, 0.2, 0.22))
		# a crack: a dark jagged line down from the parapet
		if roll > 0.8:
			var y := top - 0.1
			var z := sw.rng.randf_range(-bay_len * 0.35, bay_len * 0.35)
			for q in sw.rng.randi_range(4, 7):
				var run := sw.rng.randf_range(0.3, 0.6)
				var dz := sw.rng.randf_range(-0.18, 0.18)
				m.block(dark, Transform3D(basis * Basis(Vector3.RIGHT, atan2(dz, run)), Vector3(centre.x, y - run * 0.5, centre.z) + outward * (thick * 0.5 + 0.006) + basis * Vector3(0.0, 0.0, z + dz * 0.5)),
						Vector3(0.015, run, 0.035))
				y -= run
				z += dz


## The merlons that came down, and rubble of the walls, lying at the foot where they fell, half in
## the turf.
static func _fallen(d: PoiDressing, fallen: Array) -> void:
	var k := d.kit
	if k.far or fallen.is_empty():
		return
	var sw := Stones.new(k, d.poi_id.hash() + 5)
	for f in fallen:
		var at: Vector2 = f[0]
		var w: float = f[1]
		var g := k.on_ground(at.x, at.y).y
		var b := Basis(Vector3.UP, k.rng.randf() * TAU) * Basis(Vector3.RIGHT, k.rng.randf_range(0.2, 1.3)) * Basis(Vector3.FORWARD, k.rng.randf_range(-0.3, 0.3))
		sw.top = g + 1.0
		sw.block(Transform3D(b, Vector3(at.x, g + 0.1, at.y)), Vector3(0.55, 1.0, w))
		for q in k.rng.randi_range(2, 4):
			var p := at + Vector2(k.rng.randf_range(-1.4, 1.4), k.rng.randf_range(-1.4, 1.4))
			var s := k.rng.randf_range(0.25, 0.5)
			sw.block(Transform3D(Basis.from_euler(Vector3(k.rng.randf_range(-0.6, 0.6), k.rng.randf() * TAU, k.rng.randf_range(-0.6, 0.6))),
					k.on_ground(p.x, p.y, s * 0.15)), Vector3(s * 1.3, s, s * 0.9))
		k.collider(Vector3(0.9, 0.7, w), Transform3D(Basis.IDENTITY, Vector3(at.x, g + 0.3, at.y)), "stone")
	await k.step()
	_commit(d, sw, null, "Fallen")


## The gate: a gatehouse. Two piers carrying the walkway over an arch, a portcullis drawn up in its
## crown, towers either side standing out from the wall at walkway height with their own parapets,
## a box over the arch to drop things through, and the leaves swung open, bound with iron.
static func _gate(d: PoiDressing, at: Vector3, basis: Basis, inward: Vector2, width: float, walk_y: float,
		thick: float, timber: bool, walls: Variant, dark: SurfaceTool) -> void:
	var k := d.kit
	var m := d.masonry
	var open := 3.6
	var pier := maxf((width - open) * 0.5, 0.6)
	var t := maxf(thick, 1.2) + 0.6
	var foot := at.y - 0.8
	var h := walk_y - foot
	var into := Vector3(inward.x, 0.0, inward.y)
	var out := -into
	var mat_kind := "wood" if timber else "stone"
	if walls is Stones:
		(walls as Stones).top = walk_y + 1.3
	for s in [-1.0, 1.0]:
		var c := at + basis * Vector3(0.0, 0.0, float(s) * (open * 0.5 + pier * 0.5))
		c.y = foot + h * 0.5
		_blk(d, walls, Transform3D(basis, c), Vector3(t, h + (0.0 if timber else 1.2), pier))
		k.collider(Vector3(t, h + (0.0 if timber else 1.2), pier), Transform3D(basis, c), mat_kind)
	# the lintel and the walkway over it
	var lintel_y := at.y + 4.2
	var over := at
	over.y = (lintel_y + walk_y) * 0.5
	var lh := walk_y - lintel_y
	if lh > 0.2:
		_blk(d, walls, Transform3D(basis, over), Vector3(t, lh, open + 0.1))
		k.collider(Vector3(t, lh, open + 0.1), Transform3D(basis, over), mat_kind)
	if not timber:
		await _gatehouse(d, at, basis, out, into, open, t, foot, lintel_y, walk_y, walls, dark)
	# the leaves, swung back inside, bound with iron
	var leaves := m.begin()
	var straps := m.begin()
	for s in [-1.0, 1.0]:
		var hinge := at + basis * Vector3(0.0, 0.0, float(s) * open * 0.5) + into * (t * 0.5)
		var leaf_dir := into.rotated(Vector3.UP, float(s) * 0.25)
		var c := hinge + leaf_dir * (open * 0.25)
		c.y = at.y + 1.9
		var lb := Basis(Vector3.UP, atan2(leaf_dir.x, leaf_dir.z))
		m.block(leaves, Transform3D(lb, c), Vector3(0.16, 3.8, open * 0.5))
		for y in [0.7, 2.0, 3.2]:
			m.block(straps, Transform3D(lb, Vector3(c.x, at.y + float(y), c.z)), Vector3(0.2, 0.1, open * 0.5 - 0.1))
	await k.step()
	m.commit(leaves, k.surface("planks", 0.7), "GateLeaves")
	m.commit(straps, PoiKit.plain(Color(0.12, 0.11, 0.1), 0.6, 0.5), "GateIron")


## A stone gate's gatehouse: the arch in the opening, the portcullis, the towers either side and the
## box over the arch.
static func _gatehouse(d: PoiDressing, at: Vector3, basis: Basis, out: Vector3, into: Vector3, open: float, t: float,
		foot: float, lintel_y: float, walk_y: float, walls: Variant, dark: SurfaceTool) -> void:
	var k := d.kit
	var m := d.masonry
	# the arch: its haunches filling the opening's upper corners, voussoirs round both its faces
	var spring := at.y + 2.5
	var r := open * 0.5
	var rise := lintel_y - spring
	for s in [-1.0, 1.0]:
		for q in 6:
			var x0 := r - r * float(q) / 6.0
			var x1 := r - r * float(q + 1) / 6.0
			var xm := (x0 + x1) * 0.5
			var arch_y := spring + sqrt(maxf(r * r - xm * xm, 0.0)) * (rise / r)
			var hgt := lintel_y - arch_y + 0.05
			if hgt > 0.02:
				_blk(d, walls, Transform3D(basis, Vector3(at.x, arch_y + hgt * 0.5, at.z) + basis * Vector3(0.0, 0.0, float(s) * xm)), Vector3(t, hgt, x0 - x1 + 0.03))
	for face in [-1.0, 1.0]:
		for q in 9:
			var a := PI * (float(q) + 0.5) / 9.0
			var p := Vector3(0.0, sin(a) * rise, cos(a) * r)
			var vb := basis * Basis(Vector3.RIGHT, (PI * 0.5 - a) * 0.9)
			_blk(d, walls, Transform3D(vb, Vector3(at.x, spring, at.z) + basis * p + out * float(face) * (t * 0.5 + 0.04)), Vector3(0.12, 0.62, 0.46))
	# the portcullis, drawn up: its teeth in the arch's crown by the outer face
	var iron := m.begin()
	var pz := out * (t * 0.5 - 0.5)
	for q in 7:
		var z := (float(q) - 3.0) * 0.5
		var ytop := lintel_y + 0.3
		var ybot := spring + sqrt(maxf(r * r - z * z, 0.0)) * (rise / r) - 0.3
		m.block(iron, Transform3D(basis, Vector3(at.x, (ytop + ybot) * 0.5, at.z) + pz + basis * Vector3(0.0, 0.0, z)), Vector3(0.08, ytop - ybot, 0.08))
		m.limb(iron, Vector3(at.x, ybot, at.z) + pz + basis * Vector3(0.0, 0.0, z), Vector3(at.x, ybot - 0.22, at.z) + pz + basis * Vector3(0.0, 0.0, z), 0.035)
	await k.step()
	m.commit(iron, PoiKit.plain(Color(0.14, 0.13, 0.12), 0.6, 0.6), "Portcullis")
	# the gate towers, standing out from the wall's face at the walkway's height
	var along := basis * Vector3(0.0, 0.0, 1.0)
	for s in [-1.0, 1.0]:
		var tc := at + along * (float(s) * (open * 0.5 + 1.7)) + out * (t * 0.5 + 1.1)
		var th := walk_y - foot
		var body := Transform3D(basis, Vector3(tc.x, foot + th * 0.5, tc.z))
		_blk(d, walls, body, Vector3(2.8, th, 3.0))
		k.collider(Vector3(2.8, th, 3.0), body, "stone")
		_blk(d, walls, Transform3D(basis, Vector3(tc.x, at.y - 0.35, tc.z)), Vector3(3.5, 1.3, 3.7))
		_blk(d, walls, Transform3D(basis, Vector3(tc.x, at.y + 0.52, tc.z)), Vector3(3.15, 0.44, 3.35))
		_blk(d, walls, Transform3D(basis, Vector3(tc.x, walk_y - 0.55, tc.z)), Vector3(3.1, 0.28, 3.3))
		# its parapet: along its outer face, and its far side
		for q in 3:
			var mh := k.rng.randf_range(0.95, 1.25)
			_blk(d, walls, Transform3D(basis, Vector3(tc.x, walk_y + mh * 0.5, tc.z) + out * 1.15 + along * ((float(q) - 1.0) * 0.95)), Vector3(0.5, mh, 0.55))
		k.collider(Vector3(0.5, 1.1, 3.0), Transform3D(basis, Vector3(tc.x, walk_y + 0.55, tc.z) + out * 1.15), "stone")
		var sd := along * float(s)
		for q in 3:
			var mh := k.rng.randf_range(0.95, 1.25)
			_blk(d, walls, Transform3D(basis, Vector3(tc.x, walk_y + mh * 0.5, tc.z) + sd * 1.25 + out * ((float(q) - 1.0) * 0.9)), Vector3(0.55, mh, 0.5))
		k.collider(Vector3(2.8, 1.1, 0.5), Transform3D(basis, Vector3(tc.x, walk_y + 0.55, tc.z) + sd * 1.25), "stone")
		# a loop low in its face, and one high
		for y in [at.y + 2.2, walk_y - 1.6]:
			m.block(dark, Transform3D(basis, Vector3(tc.x, float(y), tc.z) + out * 1.405), Vector3(0.02, 0.9, 0.12))
	# the box over the arch, on corbels, with a slot in its floor for what is dropped
	var bx := Vector3(at.x, walk_y, at.z) + out * (t * 0.5 + 0.45)
	for q in 4:
		_blk(d, walls, Transform3D(basis, bx + Vector3.DOWN * 0.6 + along * ((float(q) - 1.5) * 1.0)), Vector3(0.9, 0.45, 0.3))
	_blk(d, walls, Transform3D(basis, bx + Vector3.DOWN * 0.2), Vector3(0.9, 0.3, open + 0.2))
	_blk(d, walls, Transform3D(basis, bx + out * 0.28 + Vector3.UP * 0.55), Vector3(0.35, 1.2, open + 0.2))
	k.collider(Vector3(0.9, 0.3, open + 0.2), Transform3D(basis, bx + Vector3.DOWN * 0.2), "stone")
	k.collider(Vector3(0.35, 1.2, open + 0.2), Transform3D(basis, bx + out * 0.28 + Vector3.UP * 0.55), "stone")
	m.block(dark, Transform3D(basis, bx + Vector3.DOWN * 0.36 - out * 0.15), Vector3(0.25, 0.01, open - 0.5))


## Stairs up the inside of the curtain from the yard to the walkway, one either side of the gate,
## running along the wall; where the wall is too short for one flight, two, doubling back at a
## landing. Each flight's slope is also one walkable ramp over its treads (a smooth foot, and a way
## for the navigation mesh), and it ends on a landing that overlaps the walkway's inner edge.
static func _wall_stairs(d: PoiDressing, a: Vector2, b: Vector2, inward: Vector2, walk_y: float, thick: float,
		timber: bool, st: Variant, gate_half: float, corner_clear: float) -> void:
	var k := d.kit
	var dir := (b - a).normalized()
	var edge := 2.1 if timber else thick * 0.5
	var avail := a.distance_to(b) * 0.5 - gate_half - 1.2 - corner_clear
	var tread := 0.42
	for s in [0, 1]:
		var run_dir := dir if s == 0 else -dir
		var base := (a + b) * 0.5 + run_dir * (gate_half + 1.2)
		var lane1 := base + inward * (edge + 1.05)
		var g := k.on_ground(lane1.x, lane1.y).y
		var rise := walk_y - g
		var count := maxi(int(ceil(rise / 0.28)), 1)
		if st is Stones:
			(st as Stones).top = walk_y
		if float(count) * tread + 1.8 <= avail:
			_flight(d, st, lane1, run_dir, g, rise, count, tread, timber)
			_landing(d, st, lane1 + run_dir * (float(count) * tread + 0.9) - inward * 0.45, run_dir, walk_y, Vector2(2.9, 1.8), timber)
		else:
			var first := int(ceil(count / 2.0))
			var lane2 := lane1 + inward * 2.1
			var mid_y := g + rise * float(first) / float(count)
			_flight(d, st, lane2, run_dir, g, mid_y - g, first, tread, timber)
			var turn_at := float(first) * tread
			_landing(d, st, lane1 + inward * 1.05 + run_dir * (turn_at + 1.0), run_dir, mid_y, Vector2(4.2, 2.0), timber)
			_flight(d, st, lane1 + run_dir * turn_at, -run_dir, mid_y, walk_y - mid_y, count - first, tread, timber)
			_landing(d, st, lane1 - inward * 0.45 - run_dir * 0.9, run_dir, walk_y, Vector2(2.9, 1.8), timber)
		await k.step()


static func _flight(d: PoiDressing, st: Variant, start: Vector2, run_dir: Vector2, y0: float, rise: float,
		count: int, tread: float, timber: bool) -> void:
	var span := tread * float(count)
	var riser := rise / float(count)
	var yaw := atan2(run_dir.x, run_dir.y)
	# the treads, seen: a solid flight of stone to the ground, or timber treads on two stringers
	for i in count:
		var p := start + run_dir * (tread * (float(i) + 0.5))
		var top := y0 + riser * float(i + 1)
		var h := (top - y0 + 0.4) if not timber else 0.1
		_blk(d, st, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, top - h * 0.5, p.y)), Vector3(2.0, h, tread * 1.02))
	if timber:
		for s in [-1.0, 1.0]:
			var side := Vector2(run_dir.y, -run_dir.x) * float(s) * 0.9
			var a := start + side
			var b := start + side + run_dir * span
			d.masonry.limb(st as SurfaceTool, Vector3(a.x, y0 + 0.1, a.y), Vector3(b.x, y0 + rise - 0.05, b.y), 0.09)
	# what is walked: one ramp from the foot of the flight to its head, under the treads' noses (a foot
	# never catches one, and the navigation mesh has one slope rather than a sawtooth)
	var mid := start + run_dir * (span * 0.5)
	var pitch := atan2(rise, span)
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch),
			Vector3(mid.x, y0 + rise * 0.5 - 0.05, mid.y))
	d.kit.collider(Vector3(2.0, 0.1, sqrt(span * span + rise * rise)), xf, "wood" if timber else "stone")


static func _landing(d: PoiDressing, st: Variant, at: Vector2, run_dir: Vector2, top: float, size: Vector2, timber: bool) -> void:
	var xf := Transform3D(Basis(Vector3.UP, atan2(run_dir.x, run_dir.y)), Vector3(at.x, top - 0.15, at.y))
	d.kit.collider(Vector3(size.x, 0.3, size.y), xf, "wood" if timber else "stone")
	_blk(d, st, xf, Vector3(size.x, 0.3, size.y))


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
		_stake(st, Vector3(p.x, foot, p.y), h, 0.16, k.rng.randf() * TAU, k.rng.randf_range(0.3, 0.45))
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


## A split stake, sharpened: six faces and a point, 18 triangles. A stake laid as a round rod with a
## capsule for its point was ~400, and a stockade has near three hundred of them, drawn again in
## every shadow split: Sedgemire's Stakes at Oulnauve came to over 2 M primitives a view.
static func _stake(st: SurfaceTool, foot: Vector3, h: float, r: float, yaw: float, point: float) -> void:
	var ring: Array[Vector3] = []
	for i in 6:
		var a := yaw + TAU * float(i) / 6.0
		ring.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	var tip := foot + Vector3.UP * (h + point)
	for i in 6:
		var a0: Vector3 = foot + ring[i]
		var a1: Vector3 = foot + ring[(i + 1) % 6]
		var b0 := a0 + Vector3.UP * h
		var b1 := a1 + Vector3.UP * h
		# wound to face out
		for q in [a0, a1, b0, a1, b1, b0, b0, b1, tip]:
			st.add_vertex(q)


## A corner tower at walkway height with a parapet round its top (square or round), a timber
## platform on posts, or a tumbled stump. Returns where a watcher stands on it (INF: nowhere). A
## square one stands on a stepped plinth, has loops up its outer faces, and its parapet carried out
## on a row of corbels, its merlons of uneven height and now and then one broken.
static func _tower(d: PoiDressing, c: Vector2, g: float, walk_y: float, kind: String, tumbled: bool,
		_stone: Material, wood: Material, planks: Material, wall_yaw := 0.0) -> Vector3:
	var k := d.kit
	var m := d.masonry
	var top_y := walk_y + 0.0
	var out := Vector3.INF
	match kind:
		"square":
			var sw := Stones.new(k, d.poi_id.hash() + int(c.x * 7.0 + c.y * 13.0))
			sw.top = top_y + 1.3
			var dark := m.begin()
			var side := 5.2
			var foot := g - 1.0
			var h := (top_y - foot) * (0.55 if tumbled else 1.0)
			# square to the walls, so the walkways run straight onto its top
			var basis := Basis(Vector3.UP, wall_yaw)
			var outward := Vector3(c.x, 0.0, c.y).normalized()
			sw.block(Transform3D(basis, Vector3(c.x, foot + h * 0.5, c.y)), Vector3(side, h, side))
			k.collider(Vector3(side, h, side), Transform3D(basis, Vector3(c.x, foot + h * 0.5, c.y)), "stone")
			sw.block(Transform3D(basis, Vector3(c.x, g - 0.3, c.y)), Vector3(side + 0.9, 1.4, side + 0.9))
			sw.block(Transform3D(basis, Vector3(c.x, g + 0.62, c.y)), Vector3(side + 0.45, 0.45, side + 0.45))
			if not tumbled:
				for s in 4:
					var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(s))
					var e := bb * Vector3(0.0, 0.0, side * 0.5)
					var en := e.normalized()
					if en.dot(outward) < 0.2:
						# the edges toward the yard stay open: the walkways come in there
						continue
					# corbels under a parapet band standing a little out
					for q in 6:
						var al := bb * Vector3((float(q) - 2.5) * side * 0.17, 0.0, 0.0)
						sw.block(Transform3D(bb, Vector3(c.x, top_y - 0.62, c.y) + e + en * 0.12 + al), Vector3(0.32, 0.36, 0.3))
					sw.block(Transform3D(bb, Vector3(c.x, top_y - 0.3, c.y) + e + en * 0.16), Vector3(side + 0.6, 0.3, 0.36))
					# loops up the face
					for y in [g + 2.4, g + (top_y - g) * 0.62]:
						m.block(dark, Transform3D(bb, Vector3(c.x, float(y), c.y) + e + en * 0.005), Vector3(0.12, 0.95, 0.02))
					for q in 3:
						var al2 := bb * Vector3((float(q) - 1.0) * side * 0.33, 0.0, 0.0)
						var mh := k.rng.randf_range(1.05, 1.35) if k.rng.randf() > 0.18 else k.rng.randf_range(0.4, 0.75)
						sw.block(Transform3D(bb * Basis(Vector3.UP, k.rng.randf_range(-0.03, 0.03)), Vector3(c.x, top_y + mh * 0.5, c.y) + e - en * 0.12 + al2),
								Vector3(side * k.rng.randf_range(0.18, 0.22), mh, 0.55))
					k.collider(Vector3(side, 1.2, 0.5), Transform3D(bb, Vector3(c.x, top_y + 0.6, c.y) + e - en * 0.25), "stone")
				out = Vector3(c.x, top_y, c.y) * Vector3(0.96, 1.0, 0.96)
			await k.step()
			_commit(d, sw, null, "Tower", true)
			m.commit(dark, PoiKit.plain(DARK, 0.95), "TowerLoops")
		"drum":
			var st := m.begin()
			var side := 5.2
			var foot := g - 1.0
			var h := (top_y - foot) * (0.55 if tumbled else 1.0)
			var basis := Basis(Vector3.UP, wall_yaw)
			m.drum(st, Transform3D(Basis.IDENTITY, Vector3(c.x, foot, c.y)), side * 0.55, h + (0.0 if tumbled else 1.3), 0.25 if tumbled else 0.0)
			if not tumbled:
				m.block(st, Transform3D(basis, Vector3(c.x, top_y - 0.2, c.y)), Vector3(side * 0.95, 0.4, side * 0.95))
				k.collider(Vector3(side, h, side), Transform3D(basis, Vector3(c.x, foot + h * 0.5, c.y)), "stone")
				out = Vector3(c.x, top_y, c.y) * Vector3(0.96, 1.0, 0.96)
			await k.step()
			m.commit(st, stone_look(k, g), "Tower", true)
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
static func _tall_tower(d: PoiDressing, _stone: Material, wood: Material) -> Vector3:
	var k := d.kit
	var m := d.masonry
	var st := Stones.new(k, d.poi_id.hash() + 11)
	var g := k.on_ground(0.0, 0.0).y
	var side := 4.6
	var h := 12.0
	st.top = g + h + 1.0
	var yaw := k.grain().angle()
	var basis := Basis(Vector3.UP, yaw)
	st.block(Transform3D(basis, Vector3(0.0, g - 1.0 + (h + 1.0) * 0.5, 0.0)), Vector3(side, h + 1.0, side))
	k.collider(Vector3(side, h + 1.0, side), Transform3D(basis, Vector3(0.0, g - 1.0 + (h + 1.0) * 0.5, 0.0)), "stone")
	st.block(Transform3D(basis, Vector3(0.0, g - 0.3, 0.0)), Vector3(side + 0.8, 1.4, side + 0.8))
	var top := g + h
	for s in 4:
		var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(s))
		var e := bb * Vector3(0.0, 0.0, side * 0.5 + 0.2)
		st.block(Transform3D(bb, Vector3(0.0, top + 0.5, 0.0) + e), Vector3(side + 0.8, 1.0, 0.4))
		k.collider(Vector3(side + 0.8, 1.0, 0.4), Transform3D(bb, Vector3(0.0, top + 0.5, 0.0) + e), "stone")
	st.block(Transform3D(basis, Vector3(0.0, top - 0.1, 0.0)), Vector3(side + 1.2, 0.3, side + 1.2))
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
	_commit(d, st, null, "Watchtower", true)
	m.commit(steps_st, stone_look(k, g), "WatchtowerStair", true)
	var basket := m.begin()
	m.rod(basket, Transform3D(Basis.IDENTITY, Vector3(0.0, top + 0.8, 0.0)), 0.12, 1.6)
	m.block(basket, Transform3D(Basis.IDENTITY, Vector3(0.0, top + 1.7, 0.0)), Vector3(0.9, 0.3, 0.9))
	m.commit(basket, wood, "Beacon")
	k.light(Vector3(0.0, top + 2.0, 0.0), Color(1.0, 0.6, 0.3), 2.5, 14.0)
	return Vector3(1.2, top, 1.2)


## The yard: the keep (and the door into its undercroft), the ground trodden to earth, the
## garrison's lean-tos along the wall, a fire, a well, a table, hay, firewood and hens, and the
## stores of whoever holds it.
static func _yard(d: PoiDressing, site: Dictionary, gate_dir: Vector2, radius: float, walk_y: float, timber: bool,
		gate_at: Vector3) -> void:
	var k := d.kit
	var m := d.masonry
	var back := -gate_dir
	var side := Vector2(gate_dir.y, -gate_dir.x)
	var keep_id := str(site.get("keep", ""))
	var keep_front := Vector2.INF
	if keep_id != "" or bool(site.get("keep_building", not timber)):
		keep_front = await _keep(d, keep_id, gate_dir, radius, walk_y)
	if k.far:
		return
	# the ground inside trodden to earth, and the ways across it worn: gate to fire to keep
	if not timber:
		await _trodden(d, gate_dir, radius, gate_at, keep_front)
	# lean-tos along the side walls
	var roofs := m.begin()
	var posts := m.begin()
	var lean_at: Array = []
	for s in [-1.0, 1.0]:
		var c := side * float(s) * (radius * 0.62) + back * (radius * 0.05)
		var g := k.on_ground(c.x, c.y).y
		var yaw := atan2(side.x * float(s), side.y * float(s))
		var basis := Basis(Vector3.UP, yaw)
		lean_at.append([c, basis, g, yaw])
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
	# what stands about the yard: [prop, where, yaw, collide, how high over the ground]
	var things: Array = []
	# the table by the fire, where they eat and dice, benches either side, a mug and a bowl on it
	var table := k.prop("table_trestle")
	var table_at := fire + side * 4.2 + back * 1.0
	var table_yaw := atan2(side.x, side.y)
	if table != "":
		var tw := maxf(PoiKit.half_width_of(table), 0.4)
		var th := PoiKit.height_of(table)
		things.append(["table_trestle", table_at, table_yaw, true, 0.0])
		for s in [-1.0, 1.0]:
			things.append(["bench", table_at + gate_dir * float(s) * (tw + 0.45), table_yaw, true, 0.0])
		things.append(["mug", table_at + side * 0.25, k.rng.randf() * TAU, false, th])
		things.append(["bowl", table_at - side * 0.35, 0.0, false, th])
		things.append(["jug", table_at + side * 0.6 + gate_dir * 0.1, 0.0, false, th])
	things.append(["cooking_pot", fire + side * 1.1, 0.0, false, 0.0])
	# a well against one side, hay and a cart on the other, a block and a barrow by the keep
	var well_at := side * (radius * 0.36) + gate_dir * (radius * 0.18)
	things.append(["well", well_at, k.rng.randf() * TAU, true, 0.0])
	things.append(["bucket", well_at + gate_dir * 1.3, 0.0, false, 0.0])
	var hay_at := -side * (radius * 0.4) + gate_dir * (radius * 0.24)
	things.append(["hay_bale", hay_at, k.rng.randf_range(-0.3, 0.3) + table_yaw, true, 0.0])
	things.append(["hay_bale", hay_at + gate_dir * 1.4, k.rng.randf_range(-0.3, 0.3) + table_yaw, true, 0.0])
	things.append(["cart", -side * (radius * 0.3) + gate_dir * (radius * 0.44), k.rng.randf_range(-0.4, 0.4) + atan2(gate_dir.x, gate_dir.y), true, 0.0])
	things.append(["chopping_block", back * (radius * 0.12) - side * (radius * 0.3), 0.0, true, 0.0])
	things.append(["wheelbarrow", back * (radius * 0.02) - side * (radius * 0.22), k.rng.randf() * TAU, true, 0.0])
	# the stores, never one inside another (a barrel stood in a sack)
	for kind in ["barrel", "barrel", "crate", "crate", "sack", "sack", "basket", "banner"]:
		var p := Vector2.ZERO
		for attempt in 8:
			p = side * (k.rng.randf_range(-1.0, 1.0) * radius * 0.45) + back * (k.rng.randf_range(0.0, 0.25) * radius)
			var clear := true
			for t in things:
				if (t[1] as Vector2).distance_to(p) < 1.4:
					clear = false
					break
			if clear:
				break
		things.append([kind, p, k.rng.randf() * TAU, kind != "banner", 0.0])
	# hens scratching about the yard, a goose
	for q in 5:
		var a := k.rng.randf() * TAU
		var p := fire + Vector2(sin(a), cos(a)) * k.rng.randf_range(4.0, 8.5)
		things.append(["hen" if q < 4 else "goose", p, k.rng.randf() * TAU, false, 0.0])
	for t in things:
		var p: Vector2 = t[1]
		var kind := str(t[0])
		var lift := float(t[4])
		if lift == 0.0:
			# nothing on the fire, on the keep's step, in the gate's way or on the table
			if p.distance_to(fire) < 2.2 and kind != "cooking_pot":
				p += side * 2.4
			if keep_front != Vector2.INF and p.distance_to(keep_front) < 2.8:
				p += side * 3.0
			if gate_at != Vector3.ZERO and p.distance_to(Vector2(gate_at.x, gate_at.z)) < 5.0:
				p += back * 3.5
			if kind != "table_trestle" and kind != "bench" and p.distance_to(table_at) < 1.8:
				p += side * 2.2
		var path := k.prop(kind)
		if path != "":
			k.place(path, k.on_ground(p.x, p.y, lift), float(t[2]), 1.0, bool(t[3]))
		await k.step()
	var rack := k.prop("spear")
	if rack != "":
		for q in 3:
			var p := side * (radius * 0.35) + back * (float(q) * 0.5)
			k.place(rack, k.on_ground(p.x, p.y), k.rng.randf() * TAU, 1.0, false, Vector3(0.25, 0.0, 0.0))
	# shields hung under one lean-to, firewood stacked under the other
	var shield := k.prop("shield")
	if shield != "" and lean_at.size() > 0:
		var la: Array = lean_at[0]
		var lc: Vector2 = la[0]
		var lb: Basis = la[1]
		for q in 3:
			var p := Vector3(lc.x, float(la[2]) + 1.3, lc.y) + lb * Vector3((float(q) - 1.0) * 1.6, 0.0, -1.45)
			k.place(shield, p, float(la[3]) + PI, 1.0, false, Vector3(0.12, 0.0, 0.0))
	if lean_at.size() > 1:
		var la2: Array = lean_at[1]
		var lc2: Vector2 = la2[0]
		var lb2: Basis = la2[1]
		var logs := m.begin()
		var base := Vector3(lc2.x, float(la2[2]), lc2.y) + lb2 * Vector3(1.2, 0.0, -1.45)
		for row in 4:
			for q in 7 - row:
				var p := base + lb2 * Vector3((float(q) - float(6 - row) * 0.5) * 0.29, 0.14 + float(row) * 0.25, 0.0)
				m.rod(logs, Transform3D(lb2 * Basis(Vector3.RIGHT, PI * 0.5), p), k.rng.randf_range(0.11, 0.14), 0.9)
		await k.step()
		m.commit(logs, k.surface("timber", 0.8), "Firewood")


## The keep against the back wall, its door facing the gate: a stepped plinth, string courses at
## each storey, windows in dressed surrounds, corner turrets standing up past its parapet, the
## parapet carried out on corbels, a chimney, and a pentice over the door. Returns where its door's
## threshold is (local xz).
static func _keep(d: PoiDressing, keep_id: String, gate_dir: Vector2, radius: float, walk_y: float) -> Vector2:
	var k := d.kit
	var m := d.masonry
	var back := -gate_dir
	var kc := back * (radius * 0.42)
	var g := k.on_ground(kc.x, kc.y).y
	var w := minf(radius * 0.6, 11.0)
	var dpt := minf(radius * 0.45, 8.5)
	var h := walk_y - g + 4.5
	var basis := Basis(Vector3.UP, atan2(gate_dir.x, gate_dir.y))
	var sw := Stones.new(k, d.poi_id.hash() + 3)
	sw.top = g + h + 1.0
	var dark := m.begin()
	var body := Transform3D(basis, Vector3(kc.x, g - 1.0 + (h + 1.0) * 0.5, kc.y))
	sw.block(body, Vector3(w, h + 1.0, dpt))
	k.collider(Vector3(w, h + 1.0, dpt), body, "stone")
	# plinth, two courses
	sw.block(Transform3D(basis, Vector3(kc.x, g - 0.2, kc.y)), Vector3(w + 0.9, 1.2, dpt + 0.9))
	sw.block(Transform3D(basis, Vector3(kc.x, g + 0.62, kc.y)), Vector3(w + 0.45, 0.45, dpt + 0.45))
	# string courses at each storey
	var storey := 3.4
	var y := g + storey
	while y < g + h - 1.2:
		sw.block(Transform3D(basis, Vector3(kc.x, y, kc.y)), Vector3(w + 0.22, 0.22, dpt + 0.22))
		y += storey
	# corner turrets: proud of the corners, standing up past the parapet with their own merlons
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var cc := Vector3(kc.x, 0.0, kc.y) + basis * Vector3(float(sx) * (w * 0.5 - 0.3), 0.0, float(sz) * (dpt * 0.5 - 0.3))
			var th := h + 2.0
			var tb := Transform3D(basis, Vector3(cc.x, g - 1.0 + (th + 1.0) * 0.5, cc.z))
			sw.block(tb, Vector3(1.6, th + 1.0, 1.6))
			k.collider(Vector3(1.6, th + 1.0, 1.6), tb, "stone")
			sw.block(Transform3D(basis, Vector3(cc.x, g + th - 0.15, cc.z)), Vector3(1.85, 0.25, 1.85))
			for q in 4:
				var e: Vector3 = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][q]
				sw.block(Transform3D(basis, Vector3(cc.x, g + th + 0.4, cc.z) + basis * (e * 0.66)), Vector3(0.45 if e.x != 0.0 else 0.8, 0.8, 0.8 if e.x != 0.0 else 0.45))
	# the parapet, carried out on corbels, all four sides, its merlons uneven
	for s in 4:
		var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(s))
		var half_len := (w if s % 2 == 0 else dpt) * 0.5
		var half_dep := (dpt if s % 2 == 0 else w) * 0.5
		var e := bb * Vector3(0.0, 0.0, half_dep)
		var en := e.normalized()
		var run := half_len * 2.0 - 1.6
		var nc := int(run / 0.75)
		for q in nc:
			var al := bb * Vector3((float(q) + 0.5 - float(nc) * 0.5) * 0.75, 0.0, 0.0)
			sw.block(Transform3D(bb, Vector3(kc.x, g + h - 0.45, kc.y) + e + en * 0.14 + al), Vector3(0.3, 0.34, 0.28))
		sw.block(Transform3D(bb, Vector3(kc.x, g + h - 0.12, kc.y) + e + en * 0.18), Vector3(run, 0.3, 0.4))
		var nm := int(run / 1.3)
		for q in nm:
			var al := bb * Vector3((float(q) + 0.5 - float(nm) * 0.5) * 1.3, 0.0, 0.0)
			var mh := k.rng.randf_range(0.9, 1.2) if k.rng.randf() > 0.12 else k.rng.randf_range(0.35, 0.6)
			sw.block(Transform3D(bb, Vector3(kc.x, g + h + mh * 0.5, kc.y) + e + en * 0.05 + al), Vector3(0.7, mh, 0.45))
	# windows up the faces: a dark opening in a dressed surround with a sill
	var surround := Color(1.08, 1.06, 1.0)
	for s in 4:
		var bb := basis.rotated(Vector3.UP, PI * 0.5 * float(s))
		var half_len := (w if s % 2 == 0 else dpt) * 0.5
		var e := bb * Vector3(0.0, 0.0, (dpt if s % 2 == 0 else w) * 0.5)
		var en := e.normalized()
		var count := 3 if half_len > 4.0 else 2
		for row in [storey + 1.3, storey * 2.0 + 1.1]:
			if float(row) > h - 1.6:
				continue
			for q in count:
				var al := bb * Vector3((float(q) - float(count - 1) * 0.5) * half_len * 0.6, 0.0, 0.0)
				var wc := Vector3(kc.x, g + float(row), kc.y) + e + al
				m.block(dark, Transform3D(bb, wc + en * 0.02), Vector3(0.36, 1.05, 0.04))
				sw.block(Transform3D(bb, wc + en * 0.04 + Vector3.UP * 0.62), Vector3(0.7, 0.2, 0.12), surround)
				sw.block(Transform3D(bb, wc + en * 0.06 + Vector3.DOWN * 0.6), Vector3(0.72, 0.12, 0.2), surround)
				for sx in [-1.0, 1.0]:
					sw.block(Transform3D(bb, wc + en * 0.035 + bb * Vector3(float(sx) * 0.27, 0.0, 0.0)), Vector3(0.16, 1.1, 0.1), surround)
	# the chimney, off-centre on the roof
	var ch := Vector3(kc.x, 0.0, kc.y) + basis * Vector3(w * 0.22, 0.0, -dpt * 0.18)
	sw.block(Transform3D(basis, Vector3(ch.x, g + h + 0.9, ch.z)), Vector3(1.0, 1.9, 1.0))
	sw.block(Transform3D(basis, Vector3(ch.x, g + h + 1.9, ch.z)), Vector3(1.2, 0.18, 1.2))
	await k.step()
	# the door: a round-headed surround proud of the front, dark boards in it
	var front := kc + gate_dir * (dpt * 0.5)
	var fr := Vector3(front.x, g, front.y)
	for s in [-1.0, 1.0]:
		sw.block(Transform3D(basis, fr + basis * Vector3(float(s) * 1.0, 1.25, 0.2)), Vector3(0.5, 2.5, 0.5), surround)
	for q in 7:
		var a := PI * (float(q) + 0.5) / 7.0
		var p := Vector3(cos(a) * 1.0, 2.5 + sin(a) * 0.75, 0.22)
		sw.block(Transform3D(basis * Basis(Vector3.BACK, a - PI * 0.5), fr + basis * p), Vector3(0.28, 0.5, 0.52), surround)
	m.block(dark, Transform3D(basis, fr + basis * Vector3(0.0, 1.35, 0.04)), Vector3(1.5, 2.7, 0.1))
	m.block(dark, Transform3D(basis, fr + basis * Vector3(0.0, 2.8, 0.04)), Vector3(1.1, 0.5, 0.1))
	_commit(d, sw, null, "Keep", true)
	m.commit(dark, PoiKit.plain(Color(0.06, 0.05, 0.045), 0.9), "KeepDark", true)
	if k.far:
		return front
	# the pentice over the door: a sloping board roof on two posts
	var pent := m.begin()
	var pposts := m.begin()
	for s in [-1.0, 1.0]:
		var pp := fr + basis * Vector3(float(s) * 1.9, 0.0, 2.2)
		m.post(pposts, Vector2(pp.x, pp.z), 3.1, 0.18)
	var roof_xf := Transform3D(basis * Basis(Vector3.RIGHT, 0.35), fr + basis * Vector3(0.0, 3.55, 1.2))
	m.block(pent, roof_xf, Vector3(4.6, 0.1, 2.9))
	m.block(pposts, Transform3D(basis, fr + basis * Vector3(0.0, 3.15, 2.2)), Vector3(4.2, 0.18, 0.18))
	await k.step()
	m.commit(pent, k.surface("planks", 0.8), "Pentice")
	m.commit(pposts, k.surface("timber", 0.7), "PenticePosts")
	k.collider(Vector3(4.6, 0.1, 2.9), roof_xf, "wood")
	k.puffs(Vector3(ch.x, g + h + 2.2, ch.z), Vector3(0.2, 0.1, 0.2), 2.6, 8, Color(0.34, 0.32, 0.3, 0.3), 1.2, 6.0)
	if keep_id != "" and ContentDB.has(keep_id):
		var door := Door.new()
		door.name = "Door_" + Ids.name_of(keep_id)
		door.interior_id = keep_id
		door.display_name = str(ContentDB.get_or_empty(keep_id).get("name", "the keep"))
		door.position = fr + basis * Vector3(0.0, 0.0, 0.3)
		door.rotation.y = atan2(gate_dir.x, gate_dir.y)
		d.add_child(door)
		SiteInterior.prefetch(ContentDB.get_or_empty(keep_id))
		k.light(fr + basis * Vector3(1.6, 2.4, 0.8), Color(1.0, 0.66, 0.35), 1.8, 8.0)
	return front + gate_dir * 0.8


## The yard's ground trodden to bare earth, the ways across it (gate to fire, fire to keep) worn,
## and the track out of the gate going off into the grass: one sheet on the ground, its edge dipping
## under the turf so the grass takes it back raggedly.
static func _trodden(d: PoiDressing, gate_dir: Vector2, radius: float, gate_at: Vector3, keep_front: Vector2) -> void:
	var k := d.kit
	# trodden, not polished: the painted surface's wear makes a floor shine, and in the sun the yard
	# came out as pale as the sky
	var earth := k.surface("earth", 0.08)
	var noise := FastNoiseLite.new()
	noise.seed = d.poi_id.hash() & 0xffff
	noise.frequency = 0.22
	var side := Vector2(gate_dir.y, -gate_dir.x)
	var gate2 := Vector2(gate_at.x, gate_at.z)
	var segs: Array = [[gate2 + gate_dir * 17.0, gate2, 2.2], [gate2, gate_dir * (radius * 0.12), 3.0]]
	if keep_front != Vector2.INF:
		segs.append([gate_dir * (radius * 0.12), keep_front, 2.4])
	var reach := radius * 0.6
	var step := 1.0
	var span := radius + 18.0
	var n := int(ceil(span * 2.0 / step)) + 1
	var start := -span
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ys: Array[float] = []
	var inside: Array[bool] = []
	for j in n:
		for i in n:
			var p := Vector2(start + float(i) * step, start + float(j) * step)
			var wob := noise.get_noise_2d(p.x, p.y)
			# the yard: a square inside the walls, its edge ragged
			var yard := (reach + wob * 2.2) - maxf(absf(p.dot(gate_dir)), absf(p.dot(side)))
			var way := -INF
			for sgm in segs:
				var a: Vector2 = sgm[0]
				var b: Vector2 = sgm[1]
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
				way = maxf(way, float(sgm[2]) * (0.8 + 0.5 * wob) - (a + ab * t).distance_to(p))
			var e := maxf(yard, way)
			inside.append(e > -0.9)
			ys.append(k.on_ground(p.x, p.y).y + (0.035 if e > 0.0 else -0.14) if e > -0.9 else 0.0)
		if j % 10 == 0:
			await k.step()
	var quads := 0
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var idx := [a, a + 1, a + n, a + n + 1]
			if not (inside[a] and inside[a + 1] and inside[a + n] and inside[a + n + 1]):
				continue
			var pts: Array = []
			for q in idx:
				var qi := int(q)
				pts.append(Vector3(start + float(qi % n) * step, ys[qi], start + floorf(float(qi) / float(n)) * step))
			for q in [0, 1, 2, 1, 3, 2]:
				st.add_vertex(pts[q])
			quads += 1
	if quads == 0:
		return
	await k.step()
	var mi := MeshInstance3D.new()
	mi.name = "TroddenEarth"
	k.finish_mesh(mi, st)
	mi.material_override = earth
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	k.root.add_child(mi)


## Weeds along the walls' feet, inside and out, where the scythe never reached: the region's grass
## in tussocks, and its flowers here and there.
static func _wall_growth(d: PoiDressing, corners: Array[Vector2], gate_at: Vector3, thick: float) -> void:
	var k := d.kit
	if k.far:
		return
	var grass := k.flora("meadow_grass") if k.region == "hearthvale" else k.flora(LAND._verge(d))
	if grass == "":
		grass = k.flora("grass_clump")
	var flower := k.flora("cow_parsley") if k.region == "hearthvale" else ""
	var tufts: Array = []
	var flowers: Array = []
	var gate2 := Vector2(gate_at.x, gate_at.z)
	for i in corners.size():
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % corners.size()]
		var run := a.distance_to(b)
		var inward := (-(a + b) * 0.5).normalized()
		for q in int(run / 1.0):
			var p := a.lerp(b, k.rng.randf())
			if p.distance_to(gate2) < 5.5 or p.distance_to(a) < 3.6 or p.distance_to(b) < 3.6:
				continue
			for s in [-1.0, 1.0]:
				if k.rng.randf() < 0.35:
					continue
				var q2 := p + inward * float(s) * (thick * 0.5 + 0.55 + k.rng.randf_range(0.0, 0.9))
				var xf := PoiKit.transform_at(k.on_ground(q2.x, q2.y, -0.03), k.rng.randf() * TAU, k.rng.randf_range(0.8, 1.3))
				if flower != "" and k.rng.randf() < 0.12:
					flowers.append(xf)
				else:
					tufts.append(xf)
	await k.step()
	if grass != "":
		k.scatter(grass, tufts, false, false, false)
	if flower != "" and not flowers.is_empty():
		k.scatter(flower, flowers, false, false, false)


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
	# each has a place in the garrison (`<poi>/<group>/<n>`), and whoever was killed there stays dead
	# when the fort is raised again, until a rest (SiteFallen)
	var slots := {}
	var stand := func(id: String, at: Vector3, yaw: float, opts: Dictionary) -> Enemy:
		var group := str(opts.get("group", d.poi_id + "/yard"))
		var n := int(slots.get(group, 0))
		slots[group] = n + 1
		var key := "%s/%d" % [group, n]
		if id == "" or not ContentDB.has(id) or SiteFallen.is_fallen(key):
			return null
		var e := sp.spawn_one(id, d.to_global(at + Vector3.UP * 0.1), yaw, opts)
		SiteFallen.watch(e, key)
		return e
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
		for i in (walk.size() >> 1) + 1:
			route.append(d.to_global(walk[i]))
		stand.call(pick.call(rank), walk[0], 0.0, {"group": d.poi_id + "/walls", "patrol": route})
		var back_route := route.duplicate()
		back_route.reverse()
		stand.call(pick.call(rank), walk[(walk.size() >> 1)], PI, {"group": d.poi_id + "/walls", "patrol": back_route})
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
