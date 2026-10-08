class_name GroundCover
extends RefCounted
## The scatter that is not drawn down a level-of-detail ladder -- grass, herbs, bushes, the lighter
## rocks and props, fences and hedges -- drawn out to its reach from the eye, wherever the eye is.
##
## A visibility range is measured from the camera to the centre of the node's bounding box, not to
## the nearest of its instances (Godot's scene cull, the same under Forward+ and Compatibility). A
## cell's grass of one kind was one MultiMesh spread over the whole 256 m cell, so its box's centre
## was the cell's middle, up to 181 m from a player standing in the same cell; the herbs' reach is
## 110 m (82 m on Low). So a cell's grass was drawn only while the eye was within reach of the
## cell's middle, and then all of it at once: walking along the Tamwick road out of Merrowby, 19 of
## 51 stops 16 m apart had under half of the herbs within 40 m drawn, five had none, and on Low 37
## did (PROGRESS "Ground cover in patches"). The same rule dropped a neighbouring cell's fences and
## stones 130-200 m off (8% of them within 0.8 of their reach along that road, 22% on Low), and
## switched a far-ring cell's bushes on and off whole at 380-670 m (7% of those within reach missing
## and a tenth of those past it drawn; on Low, 65% missing).
##
## So each cell's scatter of one kind keeps its rows sorted into 32 m tiles and draws only what is
## within its reach of the eye (plus a little slack for the eye's next steps), refilled as the eye
## moves like the trees' levels (world/scatter_lod.gd; these groups ride in the streamer's
## `_lod_groups`). A kind is drawn in up to two tiers, each one MultiMesh:
##   near  every row, out to the near ring's reach (VIEW_RANGE)
##   far   the far ring's share of the rows (FAR_KEEP, picked exactly as a far-ring cell picks
##         them), from the near reach out to the far ring's (VIEW_RANGE_FAR)
## A near-ring cell draws both and a far-ring cell only the second, so a cell crossing from one
## ring to the other draws the same plants at the same distances. A foliage mesh dissolves per
## plant at each edge (`lod_fade_in` / `lod_fade_out`, assets/shaders/lod_fade.gdshaderinc): the far
## tier fades in across the band the near tier fades out over, with the same noise, so a plant in
## both is drawn once. A mesh without the dissolve (stone, wood) is sorted plant by plant into
## exactly one tier at its line and is not faded. The MultiMeshes' own visibility ranges are only a
## backstop well past anything they hold. `-- --cover-by-cell` draws it the old way, for an A/B.

## The kinds this draws (WorldStreamer.asset_kind). Trees, and the heavy rocks and props with a
## forge ladder, are ScatterLod's.
const KINDS := ["herb", "bush", "rock", "prop"]
## The side of a tile the rows are sorted into, in metres.
const TILE_M := 32.0
## How far the eye may move before the tiles are picked again, and how far past the reach a tile is
## taken in, so a plant within reach is always held however the eye has moved since: at least these,
## and more for a long reach (`step_for`), whose edge is far enough off not to need the precision.
const STEP := 4.0
const SLACK := 8.0
const STEP_SHARE := 1.0 / 30.0
## The dissolve at an edge: this share of the reach, ending at the reach.
const FADE_SHARE := 0.2
## The MultiMesh's own visibility range is this many times the outer reach: a backstop only.
## Everything it holds lies within reach + slack + a tile's diagonal of the eye, so its box's centre
## does too, and three reaches holds that down to a view-range setting of a quarter.
const BACKSTOP := 3.0

static var enabled := not OS.get_cmdline_user_args().has("--cover-by-cell")
## Per asset path and tier, the mesh drawn with materials of its own (the dissolve's band is written
## into them, and the same plant elsewhere -- a place's dressing -- draws without one).
static var _meshes: Dictionary = {}


## Whether the streamer draws an asset of this kind through a group.
static func takes(kind: String) -> bool:
	return enabled and kind in KINDS


static func step_for(reach: float) -> float:
	return maxf(STEP, reach * STEP_SHARE)


static func slack_for(reach: float) -> float:
	return maxf(SLACK, 2.0 * step_for(reach))


## The mesh with its own foliage materials for one tier (`key`), its bands set.
static func mesh_for(asset_path: String, mesh: Mesh, key: String, fade_in: Vector2, fade_out: Vector2) -> Mesh:
	var id := "%s#%s" % [asset_path, key]
	var own: Mesh = _meshes.get(id)
	if own == null:
		own = ScatterLod._with_own_materials(mesh)
		_meshes[id] = own
	set_bands(own, fade_in, fade_out)
	return own


## Writes the dissolve's bands into every foliage surface of `mesh`.
static func set_bands(mesh: Mesh, fade_in: Vector2, fade_out: Vector2) -> void:
	if mesh == null:
		return
	for si in mesh.get_surface_count():
		var mat := mesh.surface_get_material(si) as ShaderMaterial
		if mat != null and mat.shader != null and _has_uniform(mat.shader, "lod_fade_out"):
			mat.set_shader_parameter("lod_fade_in", fade_in)
			mat.set_shader_parameter("lod_fade_out", fade_out)


## Whether every surface of `mesh` dissolves (a foliage mesh), so a tier can be picked by the tile.
static func dissolves(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	for si in mesh.get_surface_count():
		var mat := mesh.surface_get_material(si) as ShaderMaterial
		if mat == null or mat.shader == null or not _has_uniform(mat.shader, "lod_fade_out"):
			return false
	return true


static func band_for(reach: float) -> Vector2:
	return Vector2(reach * (1.0 - FADE_SHARE), reach)


static func _has_uniform(shader: Shader, uniform_name: String) -> bool:
	for u in shader.get_shader_uniform_list():
		if str((u as Dictionary).get("name", "")) == uniform_name:
			return true
	return false


## One tier of a group: its rows sorted by tile, drawn between `inner` and `outer` metres.
class Tier extends RefCounted:
	var mmi: MultiMeshInstance3D
	var mesh: Mesh
	## The tier's material key, and whether it fades in at `inner` (the far tier of a near cell).
	var key := "near"
	var fades_in := false
	var rows := PackedFloat32Array()
	var positions := PackedVector3Array()
	var tile_start := PackedInt32Array()
	var tile_end := PackedInt32Array()
	var tile_lo := PackedVector2Array()
	var tile_hi := PackedVector2Array()
	var inner := 0.0
	var outer := 110.0
	## By the tile (the mesh dissolves at both edges) or plant by plant at the lines (it does not).
	var by_tile := true
	var sig := -1

	## What this tier draws for an eye at `eye`: by the tile, [tile, ...]; plant by plant, [row, ...].
	func pick(eye: Vector3, slack: float, everything: bool) -> PackedInt32Array:
		var out := PackedInt32Array()
		if everything:
			for t in tile_start.size():
				out.append(t)
			return out
		var e := Vector2(eye.x, eye.z)
		var r := outer + slack
		var r2 := r * r
		# by the tile, a tile wholly inside where the inner dissolve begins is the near tier's
		var lo := (inner * (1.0 - GroundCover.FADE_SHARE) - slack) if by_tile else (inner - slack)
		var lo2 := lo * lo if lo > 0.0 else -1.0
		for t in tile_start.size():
			var a := tile_lo[t]
			var b := tile_hi[t]
			if e.clamp(a, b).distance_squared_to(e) > r2:
				continue
			if lo2 > 0.0:
				var far_corner := Vector2(maxf(absf(e.x - a.x), absf(e.x - b.x)), maxf(absf(e.y - a.y), absf(e.y - b.y)))
				if far_corner.length_squared() < lo2:
					continue
			if by_tile:
				out.append(t)
			else:
				var o2 := outer * outer
				var i2 := inner * inner
				for i in range(tile_start[t], tile_end[t]):
					var d2 := Vector2(positions[i].x, positions[i].z).distance_squared_to(e)
					if d2 <= o2 and (inner <= 0.0 or d2 > i2):
						out.append(i)
		return out

	func fill(picked: PackedInt32Array, everything: bool) -> void:
		var s := hash(picked) ^ (1 if (by_tile or everything) else 2)
		if s == sig:
			return
		sig = s
		var st := ScatterLod.STRIDE
		var buf := PackedFloat32Array()
		var n := 0
		if by_tile or everything:
			for t in picked:
				buf.append_array(rows.slice(tile_start[t] * st, tile_end[t] * st))
				n += tile_end[t] - tile_start[t]
		else:
			buf.resize(picked.size() * st)
			for k in picked.size():
				var o := picked[k] * st
				for j in st:
					buf[k * st + j] = rows[o + j]
			n = picked.size()
		var mm := mmi.multimesh
		mm.instance_count = n
		if n > 0:
			mm.buffer = buf
		mmi.visible = n > 0

	func set_down(p: TerrainProvider, origin: Vector3) -> void:
		for i in positions.size():
			var at := positions[i]
			at.y = p.get_height(at.x, at.z)
			positions[i] = at
			rows[i * ScatterLod.STRIDE + 7] = at.y - origin.y
		sig = -1


## One kind of scatter in one cell. Rides with the trees' groups, so the streamer's re-sorting,
## unloading and setting down (FallbackTerrain) take it as they take a tree. `rows`, `positions`
## and the tile arrays are the first tier's (the near one in a near-ring cell).
class Group extends ScatterLod.Group:
	var asset_path := ""
	var kind := "herb"
	var cover_mesh: Mesh = null
	var tiers: Array = []
	## The reaches in metres, the view-range setting applied: the near ring's (0 in a far-ring cell)
	## and the far ring's (0 for a kind the far ring does not draw).
	var reach := 110.0
	# `reach_far` is ScatterLod.Group's own field, set here always
	var tile_start := PackedInt32Array()
	var tile_end := PackedInt32Array()
	## False when built by a streamer that follows nothing (a tool, a test): every plant is drawn,
	## since there is no eye to measure from.
	var follows_eye := true

	func count() -> int:
		return positions.size()

	func _outer() -> float:
		return maxf(reach, reach_far)

	func wants_update(eye: Vector3) -> bool:
		return follows_eye and last_eye.distance_to(eye) >= GroundCover.step_for(_outer())

	## The first tier's tiles within its reach + slack of the eye.
	func picked(eye: Vector3) -> PackedInt32Array:
		var t: Tier = tiers[0]
		var keep := t.by_tile
		t.by_tile = true
		var out := t.pick(eye, GroundCover.slack_for(_outer()), false)
		t.by_tile = keep
		return out

	func update(eye: Vector3) -> void:
		if not eye.is_finite():
			follows_eye = false
		last_eye = eye
		var slack := GroundCover.slack_for(_outer())
		for t: Tier in tiers:
			t.fill(t.pick(eye, slack, not follows_eye), not follows_eye)

	## The reaches changed (the view-range setting): the bands and the tiers follow.
	func set_reach(near_m: float, far_m: float) -> void:
		var near_cell := tiers.size() > 0 and (tiers[0] as Tier).key == "near"
		reach = near_m if near_cell else 0.0
		reach_far = far_m
		for t: Tier in tiers:
			_set_tier(t)
			t.sig = -1
		if follows_eye:
			last_eye = Vector3(INF, INF, INF)
		else:
			update(last_eye)

	func _set_tier(t: Tier) -> void:
		match t.key:
			"near":
				t.inner = 0.0
				t.outer = reach
				GroundCover.set_bands(t.mesh, Vector2.ZERO, GroundCover.band_for(reach))
			"mid":
				t.inner = reach
				t.outer = reach_far
				GroundCover.set_bands(t.mesh, GroundCover.band_for(reach), GroundCover.band_for(reach_far))
			_:
				t.inner = 0.0
				t.outer = reach_far
				GroundCover.set_bands(t.mesh, Vector2.ZERO, GroundCover.band_for(reach_far))
		t.mmi.visibility_range_end = t.outer * GroundCover.BACKSTOP
		t.mmi.visibility_range_end_margin = 0.0

	func set_down(p: TerrainProvider) -> void:
		var origin := cell.position
		for t: Tier in tiers:
			t.set_down(p, origin)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for i in positions.size():
			lo = lo.min(positions[i])
			hi = hi.max(positions[i])
		if not positions.is_empty():
			box = AABB(lo, hi - lo)
		if last_eye.is_finite() or not follows_eye:
			update(last_eye)


## A group for one asset's rows in one cell (CONTRACTS §6 rows). In a near-ring cell `near_rows`
## (thinned by the density setting) are drawn out to `near_m` and `far_rows` from there to `far_m`;
## in a far-ring cell `near_rows` is empty and `far_rows` are drawn out to `far_m`. `near_mesh` and
## `far_mesh` are the asset's meshes for each ring; `near_base` and `far_base` the reaches before the
## view-range setting (the backstops' meta, which the streamer's view range multiplies).
static func make_group(cell: Node3D, asset_path: String, kind: String, near_mesh: Mesh, far_mesh: Mesh,
		near_rows: Array, far_rows: Array, near_m: float, far_m: float, near_base: float, far_base: float,
		casts: bool) -> Group:
	var g := Group.new()
	g.cell = cell
	g.asset_path = asset_path
	g.kind = kind
	g.reach = near_m
	g.reach_far = far_m if not far_rows.is_empty() else 0.0
	var plan: Array = []
	if not near_rows.is_empty() and near_m > 0.0:
		plan.append(["near", near_mesh, near_rows])
		if g.reach_far > near_m:
			plan.append(["mid", far_mesh, far_rows])
	elif g.reach_far > 0.0:
		plan.append(["far", far_mesh, far_rows])
	var base := asset_path.get_file().get_basename()
	for entry in plan:
		var key: String = entry[0]
		# only the near tier casts: the far ring's share never has, and past 200 m a crate's shadow
		# is a few pixels at the shadow distance's edge
		var t := _tier(cell, asset_path, "%s_%s" % [base, key] if key != "near" else base, entry[1], entry[2],
				near_base if key == "near" else far_base, casts and key == "near")
		t.key = key
		t.mesh = mesh_for(asset_path, entry[1], key, Vector2.ZERO, Vector2.ZERO)
		t.mmi.multimesh.mesh = t.mesh
		t.by_tile = dissolves(t.mesh)
		g._set_tier(t)
		g.tiers.append(t)
		g.mmis["cover" if g.tiers.size() == 1 else "far"] = t.mmi
	if g.tiers.is_empty():
		return g
	var first: Tier = g.tiers[0]
	g.cover_mesh = first.mesh
	g.rows = first.rows
	g.positions = first.positions
	g.tile_start = first.tile_start
	g.tile_end = first.tile_end
	g.level_of.resize(first.positions.size())
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in first.positions:
		lo = lo.min(p)
		hi = hi.max(p)
	g.box = AABB(lo, hi - lo)
	return g


## A tier's rows sorted into tiles (each tile's rows run together, so a pick is a few slices), and
## its MultiMesh.
static func _tier(cell: Node3D, asset_path: String, node_name: String, mesh: Mesh, rows: Array,
		range_base: float, casts: bool) -> Tier:
	var t := Tier.new()
	var origin := cell.position
	var by_tile: Dictionary = {}
	for i in rows.size():
		var row: Array = rows[i]
		var key := Vector2i(floori(float(row[0]) / TILE_M), floori(float(row[2]) / TILE_M))
		if not by_tile.has(key):
			by_tile[key] = PackedInt32Array()
		var list: PackedInt32Array = by_tile[key]
		list.append(i)
		by_tile[key] = list
	var n := rows.size()
	var st := ScatterLod.STRIDE
	t.positions.resize(n)
	t.rows.resize(n * st)
	var at := 0
	for key: Vector2i in by_tile:
		var list: PackedInt32Array = by_tile[key]
		t.tile_start.append(at)
		var tlo := Vector2(INF, INF)
		var thi := -tlo
		for i in list:
			var row: Array = rows[i]
			var xf := WorldStreamer.instance_transform(row, origin)
			var c := WorldStreamer.instance_tint(row)
			var b := xf.basis
			var o := at * st
			t.rows[o] = b.x.x
			t.rows[o + 1] = b.y.x
			t.rows[o + 2] = b.z.x
			t.rows[o + 3] = xf.origin.x
			t.rows[o + 4] = b.x.y
			t.rows[o + 5] = b.y.y
			t.rows[o + 6] = b.z.y
			t.rows[o + 7] = xf.origin.y
			t.rows[o + 8] = b.x.z
			t.rows[o + 9] = b.y.z
			t.rows[o + 10] = b.z.z
			t.rows[o + 11] = xf.origin.z
			t.rows[o + 12] = c.r
			t.rows[o + 13] = c.g
			t.rows[o + 14] = c.b
			t.rows[o + 15] = c.a
			var p := Vector3(float(row[0]), float(row[1]), float(row[2]))
			t.positions[at] = p
			tlo = tlo.min(Vector2(p.x, p.z))
			thi = thi.max(Vector2(p.x, p.z))
			at += 1
		t.tile_end.append(at)
		t.tile_lo.append(tlo)
		t.tile_hi.append(thi)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.set_meta("asset_path", asset_path)
	mmi.set_meta("range_base", range_base * BACKSTOP)
	mmi.set_meta("lod_group", true)
	mmi.set_meta("ground_cover", true)
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mmi.visible = false
	cell.add_child(mmi)
	t.mmi = mmi
	return t
