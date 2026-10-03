class_name CinderCountry
extends Node
## The ash country's own ground, laid at runtime over every Cinderlea cell as it streams in (TRIAGE
## item 60: "the ashen area's magma vents in the whole region, not just the old starting area").
##
## The Stair Head's burn (PoiBuilders._ash_field) was the only warm ground in the region. Now each
## Cinderlea cell gets, from its own cell coordinates and nothing else (so the same every time):
##
## * the vent country: a low-frequency field over the heath (`heat_at`) marks where the ground is
##   still warm, a fifth or so of the region, in broad tongues. In it lie ember cracks in smouldering
##   clusters and alone, a few larger vents -- a mouth of glowing crust, cracks radiating from it, a
##   ring of black cinders, a thread of smoke or steam, a warm light at night and a soft hiss -- a
##   rarer ember pool, and obsidian shards where the heat glassed the ash;
## * across the whole region: pale ash drifts lying down the wind, burnt stands of charred stumps
##   round a dead ash tree, a standing stone half sunk in the ash and leaning, wind-carved ash
##   pillars, and at the roadside a pilgrims' cairn with prayer-rags on a pole.
##
## Everything stands on believable ground: vents and pools in hollows or on the flat, nothing on a
## road, a pad, a landmark's foot, water or a steep slope (`clear_at`). What the scatter already
## draws (stumps, dead trees, stones, cairn boulders, cinders) is added to the cell's own rows, so it
## is drawn, LOD'd, culled and made solid exactly as the builder's scatter is; the rest is a handful
## of meshes a cell with visibility ranges, and the smoke is near-ring only. The vents' light is
## NightLights' (a glow, and one of its pool of real lights while among the nearest), so the night's
## light count stays the pool's.
##
## The streamer builds it as two paced pieces of a Cinderlea cell (WorldStreamer._build_piece):
## the plan, whose rows join the cell's before its MultiMeshes are made, and the meshes. One node of
## this class under the streamer moves a single hiss to the nearest vent and drifts ash motes round
## the camera while it is in the ash country.

const REGION := "core:region/cinderlea"
## A fixed salt, so a cell's plan is its own and nobody else's.
const SEED := 1043866
## The candidate sites: one per STEP metres square of a cell, jittered.
const STEP := 22.0
const JITTER := 8.0
## Rows of sites planned a piece in the streamer (a cell has eleven).
const PLAN_ROWS := 1
## The vent country: where `heat_at` is over this. Its tongues are a few hundred metres across.
## The field is fixed in world space and the region is the atlas's: at 0.26 it warmed about 15% of
## the 202-cell region it was tuned on (w4096f), but the hand-drawn atlas's Cinderlea is 137 cells
## and the cold ground is what it lost, so 0.26 warmed 21% of it and put cracks in 76% of its
## cells. 0.32 gives the warm share back (15% of the sites).
const HEAT_VENTS := 0.32
const HEAT_FREQUENCY := 1.0 / 420.0
## The steepest ground each thing stands on (degrees).
const CRACK_SLOPE := 16.0
const VENT_SLOPE := 9.0
const THING_SLOPE := 14.0
## How far off a road's carriageway (m), past each thing's own radius.
const ROAD_CLEAR := 2.5
## How far off a place's pad: past its flat radius by this share and these metres.
const PAD_SHARE := 1.2
const PAD_CLEAR := 6.0
## And off a landmark's foot.
const LANDMARK_CLEAR := 14.0
## Cracks in one cell, at most (one mesh's worth).
const MAX_CRACKS := 110
## Of a kind in one cell, at most.
const MAX_PER_CELL := {"vent": 2, "pool": 1, "stone": 1, "pillar": 2, "cairn": 1, "stand": 2}
## Seen out to (m).
const EMBERS_RANGE := 170.0
const SHARDS_RANGE := 110.0
const DRIFTS_RANGE := 240.0
const PILLARS_RANGE := 420.0
const RAGS_RANGE := 90.0
const SMOKE_RANGE := 320.0
## The hiss: heard from this far (m), and looked for this often (s).
const HEAR_M := 38.0
const HEAR_EVERY := 0.4
const HISS := "res://assets/audio/ambience/vent_hiss/vent_hiss.ogg"

const EMBER_SHADER := preload("res://assets/shaders/ember_crack.gdshader")
const POOL_SHADER := preload("res://assets/shaders/ember_pool.gdshader")
const OBSIDIAN_SHADER := preload("res://assets/shaders/obsidian.gdshader")
const DRIFT_SHADER := preload("res://assets/shaders/ash_drift.gdshader")
const RAG_SHADER := preload("res://assets/shaders/prayer_rag.gdshader")

const STUMPS := ["res://assets/models/trees/cinderlea_char_stump_a/cinderlea_char_stump_a.glb",
		"res://assets/models/trees/cinderlea_char_stump_b/cinderlea_char_stump_b.glb"]
const DEAD_ASH := ["res://assets/models/trees/cinderlea_dead_ash_tree_a/cinderlea_dead_ash_tree_a.glb",
		"res://assets/models/trees/cinderlea_dead_ash_tree_b/cinderlea_dead_ash_tree_b.glb",
		"res://assets/models/trees/cinderlea_dead_ash_tree_c/cinderlea_dead_ash_tree_c.glb"]
const STONES := ["res://assets/models/rocks/hearthvale_standing_stone_a/hearthvale_standing_stone_a.glb",
		"res://assets/models/rocks/hearthvale_standing_stone_b/hearthvale_standing_stone_b.glb",
		"res://assets/models/rocks/skerrow_standing_stone_a/skerrow_standing_stone_a.glb",
		"res://assets/models/rocks/skerrow_standing_stone_b/skerrow_standing_stone_b.glb"]
const BOULDERS := ["res://assets/models/rocks/cinderlea_boulder_a/cinderlea_boulder_a.glb",
		"res://assets/models/rocks/cinderlea_boulder_b/cinderlea_boulder_b.glb"]
const CINDERS := ["res://assets/models/rocks/cinderlea_scree_a/cinderlea_scree_a.glb",
		"res://assets/models/rocks/cinderlea_scree_b/cinderlea_scree_b.glb"]
## The rags' cloth: grey, bone, soot, and the faded red the Order wears at its throat.
const RAG_COLOURS := [Color(0.52, 0.50, 0.47), Color(0.70, 0.66, 0.58), Color(0.30, 0.29, 0.28),
		Color(0.50, 0.20, 0.15), Color(0.62, 0.58, 0.50)]

## Off for a measurement without it (`--no-cinder-country`, the perf sheet's "before").
static var enabled := not OS.get_cmdline_user_args().has("--no-cinder-country")

static var _heat: FastNoiseLite = null
## Every place's pad, [Vector2 xz, radius], read once.
static var _pads: Array = []
static var _pads_read := false
## Standing vents, for the hiss: holder instance id -> Array of world positions.
static var vents: Dictionary = {}
## What building has cost, for the accounts: plans, meshes, and the longest of each (µs).
static var stats := {"plans": 0, "plan_us_max": 0, "builds": 0, "build_us_max": 0}


# --- the plan ------------------------------------------------------------------------------------

## How warm the ground is at world xz, about -0.7 to 0.7: the vent country is over HEAT_VENTS.
static func heat_at(p: Vector2) -> float:
	if _heat == null:
		_heat = FastNoiseLite.new()
		_heat.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_heat.seed = 866
		_heat.frequency = HEAT_FREQUENCY
		_heat.fractal_type = FastNoiseLite.FRACTAL_FBM
		_heat.fractal_octaves = 3
		_heat.fractal_gain = 0.45
	return _heat.get_noise_2d(p.x, p.y)


## Every place's pad in the world, [Vector2 xz, flat radius]: the built ones and those the content
## has that the land does not yet (as WorldPois.unbuilt_entries).
static func pads(ground: TerrainProvider) -> Array:
	if _pads_read:
		return _pads
	_pads_read = true
	_pads = []
	var path := "res://world/generated/pois.json"
	var pois: Array = []
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			pois = parsed
	var all := pois.duplicate()
	if ContentDB.is_loaded:
		# (as WorldPois.unbuilt_entries, not named: the streamer reads this class, and naming
		# WorldPois from here closes the cycle WorldStreamer._world_pois describes)
		var built := {}
		for e in pois:
			if e is Dictionary:
				built[str((e as Dictionary).get("place_id", ""))] = true
		for def in ContentDB.all("poi"):
			var id := str(def.get("id", ""))
			var xz := WorldProbe.xz_of(def)
			if id.is_empty() or built.has(id) or xz == Vector2.ZERO:
				continue
			all.append({"pos": [xz.x, 0.0, xz.y], "radius_flat_m": float(def.get("radius_m", 18.0))})
	for e_v in all:
		if not (e_v is Dictionary):
			continue
		var e: Dictionary = e_v
		var pos: Array = e.get("pos", [])
		if pos.size() < 3:
			continue
		_pads.append([Vector2(float(pos[0]), float(pos[2])), float(e.get("radius_flat_m", 25.0))])
	return _pads


## For a test: forget the pads read, and use these ([Vector2, radius]) instead.
static func use_pads(list: Array) -> void:
	_pads = list
	_pads_read = true


static func forget_pads() -> void:
	_pads = []
	_pads_read = false


## The things to lay in one cell, from its coordinates alone (the same every time it streams in):
## {"cracks": [[xz, size, bearing, seed, glow]], "pools": [{at, r, heat}], "vents": [{at, r, steam}],
##  "shards": [[at, height, yaw, tilt, seed]], "drifts": [[xz, size, bearing, density]],
##  "pillars": [{at, h, r, seed}], "cairns": [{at, rags, seed}], "rows": {asset path: [rows]},
##  "sites": [[xz, kind, radius]]}. Positions are world. `landmarks` are world xz a thing keeps
## clear of (the cell's scenes).
static func plan(cell: Vector2i, ground: TerrainProvider, cell_size: float, landmarks: Array = []) -> Dictionary:
	var state := plan_start(cell, ground, cell_size, landmarks)
	while not plan_more(state, 1 << 20):
		pass
	return state["out"]


## A plan begun, to go on with a few rows of sites at a time (`plan_more`): the streamer lays a
## cell's plan over several paced pieces rather than in one.
static func plan_start(cell: Vector2i, ground: TerrainProvider, cell_size: float, landmarks: Array = []) -> Dictionary:
	var out := {"cracks": [], "pools": [], "vents": [], "shards": [], "drifts": [], "pillars": [],
			"cairns": [], "rows": {}, "sites": []}
	var n := int(cell_size / STEP) if ground != null else 0
	var lo := ground.origin + Vector2(cell) * cell_size if ground != null else Vector2.ZERO
	var box := Rect2(lo, Vector2.ONE * cell_size)
	var near_pads: Array = []
	if ground != null:
		for pad in pads(ground):
			if box.grow(float(pad[1]) * PAD_SHARE + 40.0).has_point(pad[0]):
				near_pads.append(pad)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([cell.x, cell.y, SEED])
	return {"out": out, "rng": rng, "n": n, "gz": 0, "lo": lo, "us": 0,
			"ctx": {"ground": ground, "pads": near_pads, "landmarks": landmarks, "box": box, "count": {}}}


## Plans up to `rows` more rows of a cell's sites; true when the plan is whole (`state["out"]`).
static func plan_more(state: Dictionary, rows: int) -> bool:
	var t0 := Time.get_ticks_usec()
	var ctx: Dictionary = state["ctx"]
	var out: Dictionary = state["out"]
	var ground: TerrainProvider = ctx["ground"]
	var rng: RandomNumberGenerator = state["rng"]
	var n := int(state["n"])
	var lo: Vector2 = state["lo"]
	var gz := int(state["gz"])
	var stop := mini(gz + rows, n)
	while gz < stop:
		for gx in n:
			# the same draws at every site whatever is laid there, so one kind's rules never move
			# another's sites
			var p := lo + (Vector2(gx, gz) + Vector2(0.5, 0.5)) * STEP \
					+ Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER))
			var roll := rng.randf()
			var drift_roll := rng.randf()
			var site := RandomNumberGenerator.new()
			site.seed = rng.randi()
			if ground.region_id_at(p.x, p.y) != REGION:
				continue
			var heat := heat_at(p)
			var laid := false
			if heat > HEAT_VENTS:
				laid = _vent_country(ctx, out, p, heat, roll, site)
			elif heat > HEAT_VENTS - 0.12 and roll < 0.05:
				laid = _cluster(ctx, out, p, site, 1)
			if not laid and roll >= 0.7:
				laid = _open_heath(ctx, out, p, heat, roll, site)
			if not laid and drift_roll > 0.93:
				_drift(ctx, out, p, site)
			elif not laid and drift_roll < 0.5 and _room(ctx, "cairn"):
				# a pilgrims' cairn stands a few metres off a road, where a site falls there
				var off := RoadNetwork.edge_distance(p)
				if off > 4.0 and off < 7.0:
					_cairn(ctx, out, p, site)
		gz += 1
	state["gz"] = gz
	var us := int(state["us"]) + Time.get_ticks_usec() - t0
	state["us"] = us
	if gz < n:
		return false
	stats["plans"] = int(stats["plans"]) + 1
	stats["plan_us_max"] = maxi(int(stats["plan_us_max"]), us)
	return true


## One site in the vent country: a vent, a pool, a cluster of cracks, a lone crack or shards.
static func _vent_country(ctx: Dictionary, out: Dictionary, p: Vector2, heat: float, roll: float,
		site: RandomNumberGenerator) -> bool:
	var ground: TerrainProvider = ctx["ground"]
	if roll < 0.07 and heat > HEAT_VENTS + 0.08 and _room(ctx, "vent"):
		if _hollow_or_flat(ground, p) and clear_at(ctx, p, 7.0, VENT_SLOPE):
			_vent(ctx, out, p, site)
			return true
	if roll < 0.1 and _room(ctx, "pool"):
		if clear_at(ctx, p, 5.0, VENT_SLOPE * 0.7):
			_pool(ctx, out, p, site)
			return true
	if (out["cracks"] as Array).size() >= MAX_CRACKS:
		return false
	if roll < 0.32:
		# smouldering clusters lie in the hollows, where the ash is deepest and the heat held
		if not _hollow_or_flat(ground, p) and site.randf() < 0.5:
			return false
		return _cluster(ctx, out, p, site, site.randi_range(3, 6))
	if roll < 0.44:
		return _cluster(ctx, out, p, site, 1)
	if roll < 0.52:
		return _shards(ctx, out, p, site, 1.0)
	return false


## One site anywhere on the heath: a burnt stand, a standing stone, or ash pillars.
static func _open_heath(ctx: Dictionary, out: Dictionary, p: Vector2, heat: float, roll: float,
		site: RandomNumberGenerator) -> bool:
	if roll > 0.975 and _room(ctx, "stand") and clear_at(ctx, p, 8.0, THING_SLOPE):
		_stand(ctx, out, p, site)
		return true
	if roll > 0.965 and roll <= 0.975 and _room(ctx, "stone") and clear_at(ctx, p, 3.0, THING_SLOPE):
		_stone(ctx, out, p, site)
		return true
	if roll > 0.95 and roll <= 0.965 and heat < -0.1 and _room(ctx, "pillar") \
			and clear_at(ctx, p, 6.0, THING_SLOPE * 0.7):
		_pillars(ctx, out, p, site)
		return true
	return false


static func _room(ctx: Dictionary, kind: String) -> bool:
	return int((ctx["count"] as Dictionary).get(kind, 0)) < int(MAX_PER_CELL.get(kind, 1 << 20))


static func _counted(ctx: Dictionary, out: Dictionary, p: Vector2, kind: String, radius: float) -> void:
	var c: Dictionary = ctx["count"]
	c[kind] = int(c.get(kind, 0)) + 1
	(out["sites"] as Array).append([p, kind, radius])


## Whether a thing of `radius` may stand at world xz `p`: in the ash country, in the cell, on dry
## ground no steeper than `max_slope` degrees, off the roads, the pads and the landmarks.
static func clear_at(ctx: Dictionary, p: Vector2, radius: float, max_slope: float) -> bool:
	var ground: TerrainProvider = ctx["ground"]
	if not (ctx["box"] as Rect2).has_point(p) or not ground.in_bounds(p.x, p.y):
		return false
	if ground.region_id_at(p.x, p.y) != REGION or ground.is_water(p.x, p.y):
		return false
	if rad_to_deg(ground.get_slope(p.x, p.y)) > max_slope:
		return false
	for a in 4:
		var q := p + Vector2.from_angle(TAU * float(a) / 4.0 + 0.4) * radius
		if ground.is_water(q.x, q.y) or ground.region_id_at(q.x, q.y) != REGION:
			return false
		if RoadNetwork.edge_distance(q) < ROAD_CLEAR:
			return false
	if RoadNetwork.edge_distance(p) < ROAD_CLEAR + minf(radius, 5.0):
		return false
	for pad in ctx["pads"]:
		if p.distance_to(pad[0]) < float(pad[1]) * PAD_SHARE + PAD_CLEAR + radius:
			return false
	for m in ctx["landmarks"]:
		if p.distance_to(m) < LANDMARK_CLEAR + radius:
			return false
	return true


## A small thing's own footing (one crack, one stump): dry, off the road, in the ash country.
static func _footing(ctx: Dictionary, p: Vector2) -> bool:
	var ground: TerrainProvider = ctx["ground"]
	return (ctx["box"] as Rect2).has_point(p) and ground.region_id_at(p.x, p.y) == REGION \
			and not ground.is_water(p.x, p.y) and RoadNetwork.edge_distance(p) >= ROAD_CLEAR


## A hollow (the ground lower than round it) or the flat: where heat and ash collect.
static func _hollow_or_flat(ground: TerrainProvider, p: Vector2) -> bool:
	var h := ground.get_height(p.x, p.y)
	var ring := 0.0
	for a in 4:
		var q := p + Vector2.from_angle(TAU * float(a) / 4.0) * 12.0
		ring += ground.get_height(q.x, q.y)
	return h - ring * 0.25 < -0.15 or rad_to_deg(ground.get_slope(p.x, p.y)) < 5.0


static func _at(ground: TerrainProvider, p: Vector2) -> Vector3:
	return Vector3(p.x, ground.get_height(p.x, p.y), p.y)


static func _crack(p: Vector2, site: RandomNumberGenerator, glow: float, bearing := NAN) -> Array:
	var length := site.randf_range(0.8, 2.8)
	return [p, Vector2(length, length * 0.5), site.randf_range(0.0, TAU) if is_nan(bearing) else bearing,
			site.randf(), clampf(glow, 0.0, 1.0)]


## Cracks in a smouldering cluster of `count` round `p` (one: a lone crack).
static func _cluster(ctx: Dictionary, out: Dictionary, p: Vector2, site: RandomNumberGenerator, count: int) -> bool:
	if not clear_at(ctx, p, 2.5 if count > 1 else 1.0, CRACK_SLOPE):
		return false
	var cracks: Array = out["cracks"]
	for j in count:
		var q := p if count == 1 else p + Vector2(site.randf_range(-2.4, 2.4), site.randf_range(-2.4, 2.4))
		if j == 0 or _footing(ctx, q):
			cracks.append(_crack(q, site, site.randf_range(0.55, 0.95) if count > 1 else site.randf_range(0.4, 0.8)))
	_counted(ctx, out, p, "cluster" if count > 1 else "crack", 2.5 if count > 1 else 1.0)
	return true


## A vent: a mouth of glowing crust, cracks radiating from it, a ring of cinders, smoke or steam.
static func _vent(ctx: Dictionary, out: Dictionary, p: Vector2, site: RandomNumberGenerator) -> void:
	var ground: TerrainProvider = ctx["ground"]
	var r := site.randf_range(0.9, 1.5)
	(out["pools"] as Array).append({"at": _at(ground, p), "r": r, "heat": 1.0, "seed": site.randf()})
	(out["vents"] as Array).append({"at": _at(ground, p), "r": r, "steam": site.randf() < 0.4})
	var arms := site.randi_range(4, 6)
	var turn := site.randf_range(0.0, TAU)
	for k in arms:
		var a := turn + TAU * float(k) / float(arms) + site.randf_range(-0.3, 0.3)
		var length := site.randf_range(1.6, 3.4)
		var q := p + Vector2.from_angle(a) * (r + length * 0.42)
		if _footing(ctx, q):
			(out["cracks"] as Array).append([q, Vector2(length, length * 0.45), a, site.randf(), site.randf_range(0.8, 1.0)])
	# the cinders the vent has thrown up round its mouth: black, loose (scree: walked over)
	for k in site.randi_range(6, 10):
		var a := site.randf_range(0.0, TAU)
		var q := p + Vector2.from_angle(a) * (r + site.randf_range(0.5, 2.2))
		if _footing(ctx, q):
			_row(out, CINDERS[k % CINDERS.size()], _at(ground, q) - Vector3(0.0, 0.05, 0.0),
					site.randf_range(0.0, 360.0), site.randf_range(0.14, 0.3), "#474240")
	_shards(ctx, out, p + Vector2.from_angle(site.randf_range(0.0, TAU)) * (r + 2.5), site, 0.7, false)
	_counted(ctx, out, p, "vent", 7.0)


## An ember pool: a wider, cooler mouth, cracks round its rim, no smoke.
static func _pool(ctx: Dictionary, out: Dictionary, p: Vector2, site: RandomNumberGenerator) -> void:
	var ground: TerrainProvider = ctx["ground"]
	var r := site.randf_range(1.6, 2.6)
	(out["pools"] as Array).append({"at": _at(ground, p), "r": r, "heat": site.randf_range(0.5, 0.75), "seed": site.randf()})
	for k in site.randi_range(2, 4):
		var a := site.randf_range(0.0, TAU)
		var q := p + Vector2.from_angle(a) * (r + site.randf_range(0.6, 1.6))
		if _footing(ctx, q):
			(out["cracks"] as Array).append(_crack(q, site, site.randf_range(0.5, 0.8), a))
	_counted(ctx, out, p, "pool", 5.0)


## Obsidian shards where the heat glassed the ash: a scatter of black blades out of the ground.
static func _shards(ctx: Dictionary, out: Dictionary, p: Vector2, site: RandomNumberGenerator, amount: float,
		counted := true) -> bool:
	if counted and not clear_at(ctx, p, 3.0, THING_SLOPE):
		return false
	var ground: TerrainProvider = ctx["ground"]
	var shards: Array = out["shards"]
	for k in int(round(site.randf_range(5.0, 11.0) * amount)):
		var q := p + Vector2(site.randf_range(-2.8, 2.8), site.randf_range(-2.8, 2.8))
		if not _footing(ctx, q):
			continue
		shards.append([_at(ground, q), site.randf_range(0.18, 0.75) * (1.4 if k == 0 else 1.0),
				site.randf_range(0.0, TAU), site.randf_range(4.0, 34.0), site.randf()])
	if counted:
		_counted(ctx, out, p, "shards", 3.0)
	return true


## A drift of pale ash lying down the wind, on the flat.
static func _drift(ctx: Dictionary, out: Dictionary, p: Vector2, site: RandomNumberGenerator) -> void:
	var length := site.randf_range(8.0, 18.0)
	if not clear_at(ctx, p, length * 0.35, 11.0):
		return
	var wind := atan2(0.6, 0.8)
	(out["drifts"] as Array).append([p, Vector2(length, length * site.randf_range(0.3, 0.5)),
			wind + site.randf_range(-0.35, 0.35), site.randf_range(0.45, 1.0)])
	_counted(ctx, out, p, "drift", length * 0.35)


## A burnt stand: charred stumps round a dead ash tree or two.
static func _stand(ctx: Dictionary, out: Dictionary, p: Vector2, site: RandomNumberGenerator) -> void:
	var ground: TerrainProvider = ctx["ground"]
	for k in site.randi_range(4, 9):
		var q := p + Vector2.from_angle(site.randf_range(0.0, TAU)) * site.randf_range(1.0, 7.5)
		if _footing(ctx, q):
			_row(out, STUMPS[k % STUMPS.size()], _at(ground, q), site.randf_range(0.0, 360.0),
					site.randf_range(0.6, 1.05), "#7e7873")
	for k in site.randi_range(1, 2):
		var q := p + Vector2(site.randf_range(-3.0, 3.0), site.randf_range(-3.0, 3.0))
		if _footing(ctx, q):
			_row(out, DEAD_ASH[site.randi() % DEAD_ASH.size()], _at(ground, q), site.randf_range(0.0, 360.0),
					site.randf_range(0.75, 1.05), "#8a8884")
	_counted(ctx, out, p, "stand", 8.0)


## A standing stone the ash has half buried, leaning; now and then a pair.
static func _stone(ctx: Dictionary, out: Dictionary, p: Vector2, site: RandomNumberGenerator) -> void:
	var ground: TerrainProvider = ctx["ground"]
	var pair := site.randf() < 0.3
	for k in (2 if pair else 1):
		var q := p + (Vector2.from_angle(site.randf_range(0.0, TAU)) * 2.6 if k == 1 else Vector2.ZERO)
		if k == 1 and not _footing(ctx, q):
			continue
		var path: String = STONES[site.randi() % STONES.size()]
		var s := site.randf_range(0.8, 1.1)
		var tall := _height_of(path) * s
		var sunk := tall * site.randf_range(0.3, 0.5)
		_row(out, path, _at(ground, q) - Vector3(0.0, sunk, 0.0), site.randf_range(0.0, 360.0), s, "#9a948d",
				site.randf_range(4.0, 14.0), site.randf_range(0.0, 360.0))
	_counted(ctx, out, p, "stone", 3.0)


## Wind-carved ash pillars, one to three.
static func _pillars(ctx: Dictionary, out: Dictionary, p: Vector2, site: RandomNumberGenerator) -> void:
	var ground: TerrainProvider = ctx["ground"]
	for k in site.randi_range(1, 3):
		var q := p + (Vector2(site.randf_range(-4.0, 4.0), site.randf_range(-4.0, 4.0)) if k > 0 else Vector2.ZERO)
		if k > 0 and not _footing(ctx, q):
			continue
		(out["pillars"] as Array).append({"at": _at(ground, q) - Vector3(0.0, 0.3, 0.0),
				"h": site.randf_range(2.2, 4.6) * (1.0 if k == 0 else 0.75), "r": site.randf_range(0.5, 0.85),
				"seed": site.randf()})
	_counted(ctx, out, p, "pillar", 6.0)


## A pilgrims' cairn at `p`, a few metres off a road, most with prayer-rags on a pole.
static func _cairn(ctx: Dictionary, out: Dictionary, p: Vector2, site: RandomNumberGenerator) -> void:
	var ground: TerrainProvider = ctx["ground"]
	if not clear_at(ctx, p, 1.2, THING_SLOPE):
		return
	var base := _at(ground, p)
	# stones stacked: a ring at the foot, a course on it, a cap
	var y := base.y - 0.08
	for course in [[3, 0.2, 0.42], [2, 0.15, 0.22], [1, 0.1, 0.0]]:
		for k in int(course[0]):
			var a := TAU * float(k) / float(course[0]) + site.randf_range(-0.4, 0.4)
			var q := p + Vector2.from_angle(a) * float(course[2])
			_row(out, BOULDERS[k % BOULDERS.size()], Vector3(q.x, y, q.y), site.randf_range(0.0, 360.0),
					float(course[1]) * site.randf_range(0.9, 1.1), "#8f8a85")
		y += float(course[1]) * 2.4
	(out["cairns"] as Array).append({"at": base, "top": y, "rags": site.randf() < 0.8, "seed": site.randf()})
	_counted(ctx, out, p, "cairn", 1.2)


static func _row(out: Dictionary, path: String, at: Vector3, yaw: float, s: float, tint: String,
		lean := 0.0, toward := 0.0) -> void:
	var rows: Dictionary = out["rows"]
	var row := [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01), snappedf(yaw, 0.1), snappedf(s, 0.001), tint]
	if lean != 0.0:
		row.append_array([snappedf(lean, 0.1), snappedf(toward, 0.1)])
	(rows.get_or_add(path, []) as Array).append(row)


static func _height_of(path: String) -> float:
	var m := ScatterSolids.meta(path)
	var b: Dictionary = m.get("bounds", {})
	return float(b.get("height", 3.5))


## The plan's rows joined to a cell's own (`instances`: asset path -> rows), each list copied, so
## the cell's parsed data is never written to.
static func add_rows(instances: Dictionary, p: Dictionary) -> void:
	var rows: Dictionary = p.get("rows", {})
	for path in rows:
		var mine: Array = (instances.get(path, []) as Array).duplicate()
		mine.append_array(rows[path])
		instances[path] = mine


## Every asset a plan may add, for the loader to read ahead.
static func assets() -> Array:
	return STUMPS + DEAD_ASH + STONES + BOULDERS + CINDERS


# --- the meshes --------------------------------------------------------------------------------

## Stands a cell's plan under `cell` (its node): the embers, pools, shards, drifts, pillars and rags
## in the near ring (`near`), with the smoke; the vents' and pools' light in any ring. `solids` is
## the cell's list of built solids ([Shape3D, Transform3D] relative to the cell): the pillars join it.
static func build(cell: Node3D, p: Dictionary, ground: TerrainProvider, near: bool, solids: Array = []) -> Node3D:
	var t0 := Time.get_ticks_usec()
	var holder := Node3D.new()
	holder.name = "CinderCountry"
	cell.add_child(holder)
	var o := cell.position
	if near:
		_patches(holder, p.get("cracks", []), ground, o, EMBER_SHADER, "Embers", 0.05, EMBERS_RANGE, 2)
		_pools(holder, p.get("pools", []), ground, o)
		_shard_mesh(holder, p.get("shards", []), o)
		_drift_mesh(holder, p.get("drifts", []), ground, o)
		_pillar_mesh(holder, p.get("pillars", []), o, solids)
		_rag_mesh(holder, p.get("cairns", []), o)
		for v in p.get("vents", []):
			_smoke(holder, (v["at"] as Vector3) - o + Vector3(0.0, 0.15, 0.0), bool(v["steam"]))
	var lights: Array = []
	var hot: Array = []
	for v in p.get("vents", []):
		lights.append((v["at"] as Vector3) + Vector3(0.0, 0.4, 0.0))
		hot.append(v["at"])
	var pools: Array = []
	for pool in p.get("pools", []):
		if float(pool["heat"]) < 0.99:
			pools.append((pool["at"] as Vector3) + Vector3(0.0, 0.3, 0.0))
	if holder.is_inside_tree():
		NightLights.add(holder, lights, "vent")
		NightLights.add(holder, pools, "vent", Color(1.0, 0.4, 0.13, 1.0), 0.7, 5.0)
	if not hot.is_empty():
		var id := holder.get_instance_id()
		vents[id] = hot
		holder.tree_exiting.connect(func() -> void: vents.erase(id), CONNECT_ONE_SHOT)
	var us := Time.get_ticks_usec() - t0
	stats["builds"] = int(stats["builds"]) + 1
	stats["build_us_max"] = maxi(int(stats["build_us_max"]), us)
	return holder


## Patches lying on the ground, as PoiBuilders._ground_patches lays the Stair Head's, in the cell's
## space: each [world xz, size, bearing, seed, strength], draped a metre a vertex.
static func _patches(holder: Node3D, patches: Array, ground: TerrainProvider, o: Vector3, shader: Shader,
		node_name: String, lift: float, reach: float, priority: int) -> MeshInstance3D:
	if patches.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for patch in patches:
		var at: Vector2 = patch[0]
		var size: Vector2 = patch[1]
		var along := Vector2.from_angle(float(patch[2]))
		var across := Vector2(-along.y, along.x)
		var tag := Color(float(patch[3]), float(patch[4]), 0.0, 1.0)
		var nu := clampi(int(ceil(size.x)), 2, 12)
		var nv := clampi(int(ceil(size.y)), 2, 12)
		for j in nv + 1:
			for i in nu + 1:
				var u := float(i) / float(nu)
				var v := float(j) / float(nv)
				var q := at + along * (u - 0.5) * size.x + across * (v - 0.5) * size.y
				st.set_color(tag)
				st.set_uv(Vector2(u, v))
				st.add_vertex(Vector3(q.x - o.x, ground.get_height(q.x, q.y) + lift, q.y - o.z))
		for j in nv:
			for i in nu:
				var i0 := base + j * (nu + 1) + i
				var i2 := i0 + nu + 1
				for idx in [i0, i0 + 1, i2 + 1, i0, i2 + 1, i2]:
					st.add_index(idx)
		base += (nu + 1) * (nv + 1)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = priority
	return _mesh_node(holder, st.commit(), mat, node_name, reach)


static func _mesh_node(holder: Node3D, mesh: Mesh, mat: Material, node_name: String, reach: float,
		shadows := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = node_name
	mi.visibility_range_end = reach
	holder.add_child(mi)
	return mi


## The vents' mouths and the ember pools: draped discs of the pool shader.
static func _pools(holder: Node3D, pools: Array, ground: TerrainProvider, o: Vector3) -> void:
	if pools.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const RINGS := 4
	const SIDES := 14
	var base := 0
	for pool in pools:
		var at: Vector3 = pool["at"]
		var r := float(pool["r"]) * 1.35
		var tag := Color(float(pool["seed"]), float(pool["heat"]), 0.0, 1.0)
		st.set_color(tag)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(Vector3(at.x - o.x, ground.get_height(at.x, at.z) + 0.06, at.z - o.z))
		for ring in range(1, RINGS + 1):
			for k in SIDES:
				var d := Vector2.from_angle(TAU * float(k) / float(SIDES)) * float(ring) / float(RINGS)
				var q := Vector2(at.x, at.z) + d * r
				st.set_color(tag)
				st.set_uv(Vector2(0.5, 0.5) + d * 0.5)
				st.add_vertex(Vector3(q.x - o.x, ground.get_height(q.x, q.y) + 0.06, q.y - o.z))
		for k in SIDES:
			st.add_index(base)
			st.add_index(base + 1 + k)
			st.add_index(base + 1 + (k + 1) % SIDES)
		for ring in range(1, RINGS):
			var a0 := base + 1 + (ring - 1) * SIDES
			var b0 := base + 1 + ring * SIDES
			for k in SIDES:
				var k1 := (k + 1) % SIDES
				for idx in [a0 + k, b0 + k, b0 + k1, a0 + k, b0 + k1, a0 + k1]:
					st.add_index(idx)
		base += 1 + RINGS * SIDES
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = POOL_SHADER
	mat.render_priority = 3
	_mesh_node(holder, st.commit(), mat, "Pools", EMBERS_RANGE * 1.4)


## Obsidian shards: each a four-sided blade, leaning, its foot under the ash.
static func _shard_mesh(holder: Node3D, shards: Array, o: Vector3) -> void:
	if shards.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in shards:
		var at: Vector3 = (s[0] as Vector3) - o
		var h := float(s[1])
		var yaw := float(s[2])
		var tilt := deg_to_rad(float(s[3]))
		var seed_v := float(s[4])
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
		var w := h * (0.22 + 0.14 * seed_v)
		var foot := [Vector3(-w, -0.12, -w * 0.45), Vector3(w * 0.8, -0.12, -w * 0.6), Vector3(w, -0.12, w * 0.5),
				Vector3(-w * 0.7, -0.12, w * 0.55)]
		var tip := Vector3(w * (seed_v - 0.5) * 0.6, h, w * 0.1)
		for k in 4:
			var a: Vector3 = at + b * (foot[k] as Vector3)
			var c: Vector3 = at + b * (foot[(k + 1) % 4] as Vector3)
			var t: Vector3 = at + b * tip
			var n := (c - a).cross(t - a).normalized()
			for v in [a, t, c]:
				st.set_normal(n)
				st.set_uv(Vector2((v as Vector3).x + (v as Vector3).y, (v as Vector3).z))
				st.add_vertex(v)
	var mat := ShaderMaterial.new()
	mat.shader = OBSIDIAN_SHADER
	mat.set_shader_parameter("ash", 0.15)
	mat.set_shader_parameter("ropes", 0.0)
	mat.set_shader_parameter("ripples", 0.0)
	mat.set_shader_parameter("conchoidal", 1.0)
	_mesh_node(holder, st.commit(), mat, "Shards", SHARDS_RANGE)


## Drifts of pale ash: the burn's own mosaic (ash_drift.gdshader) on draped patches, fading at
## their edges, in world metres so the grain runs on across neighbours.
static func _drift_mesh(holder: Node3D, drifts: Array, ground: TerrainProvider, o: Vector3) -> void:
	if drifts.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for d in drifts:
		var at: Vector2 = d[0]
		var size: Vector2 = d[1]
		var along := Vector2.from_angle(float(d[2]))
		var across := Vector2(-along.y, along.x)
		var nu := clampi(int(ceil(size.x / 1.5)), 3, 14)
		var nv := clampi(int(ceil(size.y / 1.5)), 3, 8)
		for j in nv + 1:
			for i in nu + 1:
				var u := float(i) / float(nu) - 0.5
				var v := float(j) / float(nv) - 0.5
				var q := at + along * u * size.x + across * v * size.y
				# a tongue: full in its middle, gone at its edge
				var e := Vector2(u * 2.0, v * 2.0).length()
				st.set_color(Color(1.0 - smoothstep(0.55, 1.0, e), float(d[3]), 0.0, 1.0))
				st.set_uv(q)
				st.add_vertex(Vector3(q.x - o.x, ground.get_height(q.x, q.y) + 0.04, q.y - o.z))
		for j in nv:
			for i in nu:
				var i0 := base + j * (nu + 1) + i
				var i2 := i0 + nu + 1
				for idx in [i0, i0 + 1, i2 + 1, i0, i2 + 1, i2]:
					st.add_index(idx)
		base += (nu + 1) * (nv + 1)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = DRIFT_SHADER
	mat.set_shader_parameter("ash", Color(0.47, 0.455, 0.44))
	mat.set_shader_parameter("threshold_far", 0.56)
	mat.set_shader_parameter("threshold_near", 0.47)
	mat.set_shader_parameter("patch_m", 6.0)
	mat.render_priority = 1
	_mesh_node(holder, st.commit(), mat, "Drifts", DRIFTS_RANGE)


## Wind-carved ash pillars: a column waisted by the wind under a harder cap, banded where the ash
## fell in layers; one mesh a cell, and a cylinder each for a body to walk into.
static func _pillar_mesh(holder: Node3D, pillars: Array, o: Vector3, solids: Array) -> void:
	if pillars.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES := 9
	const RINGS := 9
	var base := 0
	for pl in pillars:
		var at: Vector3 = (pl["at"] as Vector3) - o
		var h := float(pl["h"])
		var r := float(pl["r"])
		var seed_v := float(pl["seed"])
		for ring in RINGS + 1:
			var t := float(ring) / float(RINGS)
			# wide at the foot, waisted, swelling to the cap, the cap's lip, then its top
			var prof := 1.25 - 0.55 * sin(t * PI * 0.9) + 0.25 * smoothstep(0.78, 0.86, t)
			if ring == RINGS:
				prof = 0.35
			var y := h * minf(t, 0.93) + (0.06 if ring == RINGS else 0.0)
			var band := 0.5 + 0.5 * sin(y * 5.3 + seed_v * 9.0)
			var shade := lerpf(0.52, 0.66, band) * (0.72 if t > 0.8 else 1.0)
			for k in SIDES + 1:
				var a := TAU * float(k) / float(SIDES)
				var wob := 1.0 + 0.12 * sin(a * 3.0 + seed_v * 13.0 + t * 4.0)
				var d := Vector3(cos(a), 0.0, sin(a))
				st.set_color(Color(shade, shade * 0.97, shade * 0.93))
				st.set_normal((d + Vector3(0.0, 0.25, 0.0)).normalized())
				st.set_uv(Vector2(float(k) / float(SIDES), t))
				st.add_vertex(at + d * r * prof * wob + Vector3(0.0, y, 0.0))
		for ring in RINGS:
			for k in SIDES:
				var i0 := base + ring * (SIDES + 1) + k
				var i2 := i0 + SIDES + 1
				for idx in [i0, i2, i2 + 1, i0, i2 + 1, i0 + 1]:
					st.add_index(idx)
		base += (RINGS + 1) * (SIDES + 1)
		var shape := CylinderShape3D.new()
		shape.radius = r * 0.9
		shape.height = minf(h, ScatterSolids.TRUNK_TOP_M) + ScatterSolids.SINK_M
		solids.append([shape, Transform3D(Basis(), at + Vector3(0.0, shape.height * 0.5 - ScatterSolids.SINK_M, 0.0))])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.92, 0.9, 0.87)
	mat.roughness = 1.0
	_mesh_node(holder, st.commit(), mat, "Pillars", PILLARS_RANGE, true)


## The pilgrims' rags: a pole in the cairn, strips of cloth tied at its top.
static func _rag_mesh(holder: Node3D, cairns: Array, o: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for c in cairns:
		if not bool(c["rags"]):
			continue
		any = true
		var at: Vector3 = (c["at"] as Vector3) - o
		var top := float(c["top"]) - o.y + 1.3
		var rng := RandomNumberGenerator.new()
		rng.seed = int(float(c["seed"]) * 1000003.0)
		# the pole, a thin square post
		var w := 0.035
		var foot := at.y - 0.2
		for k in 4:
			var a := Vector3(cos(TAU * float(k) / 4.0), 0.0, sin(TAU * float(k) / 4.0)) * w
			var b := Vector3(cos(TAU * float(k + 1) / 4.0), 0.0, sin(TAU * float(k + 1) / 4.0)) * w
			var base_a := Vector3(at.x, foot, at.z) + a
			var base_b := Vector3(at.x, foot, at.z) + b
			var top_a := Vector3(at.x, top, at.z) + a
			var top_b := Vector3(at.x, top, at.z) + b
			for v in [base_a, top_a, top_b, base_a, top_b, base_b]:
				st.set_color(Color(0.22, 0.2, 0.18))
				st.set_uv(Vector2(0.0, 0.0))
				st.add_vertex(v)
		# the rags: tied round the top third, hanging
		for k in rng.randi_range(4, 7):
			var a := rng.randf_range(0.0, TAU)
			var d := Vector3(cos(a), 0.0, sin(a))
			var side := Vector3(-d.z, 0.0, d.x) * rng.randf_range(0.03, 0.05)
			var knot := Vector3(at.x, top - rng.randf_range(0.05, 0.45), at.z) + d * w
			var hang := Vector3(0.0, -rng.randf_range(0.3, 0.55), 0.0) + d * 0.04
			var col: Color = RAG_COLOURS[rng.randi() % RAG_COLOURS.size()]
			col = Color(col.r, col.g, col.b).darkened(rng.randf_range(0.0, 0.2))
			var u := rng.randf()
			var quad := [[knot - side, Vector2(u, 0.0)], [knot + side, Vector2(u, 0.0)],
					[knot + side + hang, Vector2(u, 1.0)], [knot - side + hang, Vector2(u, 1.0)]]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.set_uv(quad[idx][1])
				st.add_vertex(quad[idx][0])
	if not any:
		return
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = RAG_SHADER
	_mesh_node(holder, st.commit(), mat, "Rags", RAGS_RANGE)


static var _disc: Texture2D = null


## A soft round dot for a puff or a mote (as PoiKit's, which this does not name: see `pads`).
static func _soft_disc() -> Texture2D:
	if _disc != null:
		return _disc
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	_disc = t
	return t


static var _smoke_process: ParticleProcessMaterial = null
static var _steam_process: ParticleProcessMaterial = null
static var _puff: QuadMesh = null


## A thread of smoke (or steam, paler and quicker to go) off a vent: a few puffs a second, rising,
## spreading, leaning down the wind. One material and one quad for every vent.
static func _smoke(holder: Node3D, at: Vector3, steam: bool) -> GPUParticles3D:
	if _puff == null:
		_puff = QuadMesh.new()
		_puff.size = Vector2(1.6, 1.6)
		var qm := StandardMaterial3D.new()
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.vertex_color_use_as_albedo = true
		qm.albedo_texture = _soft_disc()
		_puff.material = qm
		_smoke_process = _puff_process(Color(0.40, 0.38, 0.37), 0.34, 0.9)
		_steam_process = _puff_process(Color(0.80, 0.79, 0.77), 0.26, 1.3)
	var p := GPUParticles3D.new()
	p.name = "Steam" if steam else "Smoke"
	p.position = at
	p.amount = 12 if steam else 16
	p.lifetime = 6.0 if steam else 9.0
	p.preprocess = p.lifetime
	p.visibility_range_end = SMOKE_RANGE
	p.visibility_aabb = AABB(Vector3(-5.0, -1.0, -5.0), Vector3(14.0, 14.0, 14.0))
	p.process_material = _steam_process if steam else _smoke_process
	p.draw_pass_1 = _puff
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(p)
	return p


static func _puff_process(colour: Color, alpha: float, speed: float) -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3
	mat.direction = Vector3.UP
	mat.spread = 8.0
	mat.initial_velocity_min = speed * 0.8
	mat.initial_velocity_max = speed * 1.1
	mat.gravity = Vector3(0.8, 0.0, 0.6).normalized() * 0.16
	mat.damping_min = 0.04
	mat.damping_max = 0.08
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	mat.scale_curve = grow_tex
	mat.scale_min = 0.8
	mat.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(colour.r, colour.g, colour.b, 0.0))
	ramp.set_color(1, Color(colour.r * 1.1, colour.g * 1.1, colour.b * 1.1, 0.0))
	ramp.add_point(0.12, Color(colour.r, colour.g, colour.b, alpha))
	ramp.add_point(0.55, Color(colour.r * 1.05, colour.g * 1.05, colour.b * 1.05, alpha * 0.55))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	return mat


# --- the hiss and the motes ----------------------------------------------------------------------

var _hiss: AudioStreamPlayer3D = null
var _hissing_at := Vector3.INF
var _timer := 0.0
var _motes: CPUParticles3D = null
## How many times the hiss has been started, and moved: a test holds these still while the camera
## stands by a vent (the droning of TRIAGE item 53 was a sound restarted over and over).
var hiss_starts := 0
var hiss_moves := 0


func _ready() -> void:
	add_to_group("cinder_country")


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = HEAR_EVERY
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	listen(cam.global_position)


## Moves the one hiss to the vent nearest `eye` within HEAR_M, starting it if it is not playing; a
## vent only a little nearer than the one hissing does not take it (no hopping between two), and
## with none in reach it stops. And the ash motes follow the eye while it is over the ash country.
func listen(eye: Vector3) -> void:
	var best := Vector3.INF
	var best_d := HEAR_M
	for id in vents:
		for v in vents[id]:
			var d := eye.distance_to(v)
			if d < best_d:
				best_d = d
				best = v
	if best == Vector3.INF:
		if _hiss != null and _hiss.playing:
			_hiss.stop()
			_hissing_at = Vector3.INF
	else:
		if _hiss == null:
			if not ResourceLoader.exists(HISS):
				return
			_hiss = AudioStreamPlayer3D.new()
			_hiss.name = "VentHiss"
			_hiss.stream = load(HISS)
			_hiss.bus = &"Ambience" if AudioServer.get_bus_index(&"Ambience") >= 0 else &"Master"
			_hiss.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			_hiss.unit_size = 3.0
			_hiss.max_distance = HEAR_M
			_hiss.volume_db = -9.0
			add_child(_hiss)
		if _hissing_at == Vector3.INF or eye.distance_to(best) + 4.0 < eye.distance_to(_hissing_at) \
				or not _still_venting(_hissing_at):
			if _hissing_at != best:
				hiss_moves += 1
			_hissing_at = best
			_hiss.global_position = best + Vector3(0.0, 0.4, 0.0)
		if not _hiss.playing:
			_hiss.play()
			hiss_starts += 1
	_drift_motes(eye)


static func _still_venting(at: Vector3) -> bool:
	for id in vents:
		if (vents[id] as Array).has(at):
			return true
	return false


## A few motes of ash drifting in the air round the eye while it is in the ash country, whatever
## the weather (the bible's "drifting ash motes"); the ashfall's own flakes come on top.
func _drift_motes(eye: Vector3) -> void:
	var ground := World.terrain()
	var here := ground != null and ground.region_id_at(eye.x, eye.z) == REGION
	if _motes == null:
		if not here:
			return
		_motes = CPUParticles3D.new()
		_motes.name = "AshMotes"
		_motes.amount = 48
		_motes.lifetime = 10.0
		_motes.preprocess = 10.0
		_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_motes.emission_box_extents = Vector3(16.0, 5.0, 16.0)
		_motes.direction = Vector3(0.8, -0.15, 0.6)
		_motes.spread = 40.0
		_motes.gravity = Vector3(0.0, -0.03, 0.0)
		_motes.initial_velocity_min = 0.15
		_motes.initial_velocity_max = 0.5
		_motes.scale_amount_min = 0.5
		_motes.scale_amount_max = 1.3
		var qm := QuadMesh.new()
		qm.size = Vector2(0.05, 0.05)
		_motes.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_color = Color(0.55, 0.52, 0.49, 0.5)
		mat.albedo_texture = _soft_disc()
		_motes.material_override = mat
		_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_motes)
	_motes.emitting = here
	if here:
		_motes.global_position = eye + Vector3(0.0, 1.5, 0.0)
