class_name GroundCover
extends RefCounted
## Grass, herbs and bushes drawn out to their reach from the eye, wherever the eye is in a cell.
##
## A visibility range is measured from the camera to the centre of the node's bounding box, not to
## the nearest of its instances (Godot's scene cull, the same under Forward+ and Compatibility). A
## cell's grass of one kind was one MultiMesh spread over the whole 256 m cell, so its box's centre
## was the cell's middle, up to 181 m from a player standing in the same cell; the herbs' reach is
## 110 m (82 m on Low). So a cell's grass was drawn only while the eye was within reach of the
## cell's middle, and then all of it at once: walking along the Tamwick road out of Merrowby, 19 of
## 51 stops 16 m apart had under half of the herbs within 40 m drawn, five had none, and on Low 37
## did (tools: the route count in PROGRESS "Ground cover in patches"). The grass came on and went
## off by the cell, a whole 256 m square at a time, as you walked.
##
## So each cell's cover of one kind keeps its rows sorted into 32 m tiles and draws, in one
## MultiMesh as before, only the tiles that reach within the cover's range of the eye (plus a
## little slack for the eye's next steps), refilled as the eye moves like the trees' levels
## (world/scatter_lod.gd; these groups ride in the streamer's `_lod_groups`). The edge is a dissolve
## per plant, measured from the camera to each plant in the foliage shader (`lod_fade_out`,
## assets/shaders/lod_fade.gdshaderinc), so the cover thins out over the last fifth of its reach
## instead of arriving a 256 m square at a time. The MultiMesh's own visibility range is now only a
## backstop well past anything it holds. Draw calls are what they were (one a kind and cell with
## anything in reach), and the plants drawn are a disc round the eye rather than whole cells.
## `-- --cover-by-cell` draws it the old way, for an A/B.

## The kinds this draws (WorldStreamer.asset_kind), in the near ring.
const KINDS := ["herb", "bush"]
## The side of a tile the rows are sorted into, in metres.
const TILE_M := 32.0
## How far the eye may move before the tiles are picked again, and how far past the reach a tile is
## taken in, so a plant within reach is always held however the eye has moved since.
const STEP := 4.0
const SLACK := 8.0
## The dissolve at the edge: this share of the reach, ending at the reach.
const FADE_SHARE := 0.2
## The MultiMesh's own visibility range is this many times the reach: a backstop only. Everything
## it holds lies within reach + SLACK + a tile's diagonal of the eye, so its box's centre does too,
## and three reaches holds that down to a view-range setting of a quarter.
const BACKSTOP := 3.0

static var enabled := not OS.get_cmdline_user_args().has("--cover-by-cell")
## Per asset path, the mesh drawn with materials of its own (the dissolve's band is written into
## them, and the same plant elsewhere -- a place's dressing -- draws without one).
static var _meshes: Dictionary = {}


## Whether the streamer draws an asset of this kind in this ring through a group.
static func takes(kind: String, near_ring: bool) -> bool:
	return enabled and near_ring and kind in KINDS


## The plant's mesh with its own foliage materials, the dissolve's band set for `reach` metres.
static func mesh_for(asset_path: String, mesh: Mesh, reach: float) -> Mesh:
	var own: Mesh = _meshes.get(asset_path)
	if own == null:
		own = ScatterLod._with_own_materials(mesh)
		_meshes[asset_path] = own
	set_band(own, reach)
	return own


## Writes the dissolve's band into every foliage surface of `mesh`.
static func set_band(mesh: Mesh, reach: float) -> void:
	if mesh == null:
		return
	var band := band_for(reach)
	for si in mesh.get_surface_count():
		var mat := mesh.surface_get_material(si) as ShaderMaterial
		if mat != null and mat.shader != null and _has_uniform(mat.shader, "lod_fade_out"):
			mat.set_shader_parameter("lod_fade_out", band)


static func band_for(reach: float) -> Vector2:
	return Vector2(reach * (1.0 - FADE_SHARE), reach)


static func _has_uniform(shader: Shader, uniform_name: String) -> bool:
	for u in shader.get_shader_uniform_list():
		if str((u as Dictionary).get("name", "")) == uniform_name:
			return true
	return false


## One kind of plant in one cell. Rides with the trees' groups, so the streamer's re-sorting,
## unloading and setting down (FallbackTerrain) take it as they take a tree.
class Group extends ScatterLod.Group:
	var asset_path := ""
	var cover_mesh: Mesh = null
	## The reach in metres, the view-range setting applied.
	var reach := 110.0
	## Per tile: its rows are [start, end) in the sorted rows; its rect on the ground.
	var tile_start := PackedInt32Array()
	var tile_end := PackedInt32Array()
	var tile_lo := PackedVector2Array()
	var tile_hi := PackedVector2Array()
	var picked_sig := -1
	## False when built by a streamer that follows nothing (a tool, a test): every plant is drawn,
	## since there is no eye to measure from.
	var follows_eye := true

	func count() -> int:
		return positions.size()

	func wants_update(eye: Vector3) -> bool:
		return follows_eye and last_eye.distance_to(eye) >= GroundCover.STEP

	## The tiles that reach within `reach` + SLACK of the eye (on the ground's plane: the plant's
	## own distance, which the dissolve reads, is never shorter).
	func picked(eye: Vector3) -> PackedInt32Array:
		var out := PackedInt32Array()
		var r := reach + GroundCover.SLACK
		var r2 := r * r
		var e := Vector2(eye.x, eye.z)
		for t in tile_start.size():
			var near := e.clamp(tile_lo[t], tile_hi[t])
			if near.distance_squared_to(e) <= r2:
				out.append(t)
		return out

	func update(eye: Vector3) -> void:
		if not eye.is_finite():
			follows_eye = false
		last_eye = eye
		var tiles := picked(eye)
		if not follows_eye:
			tiles.resize(tile_start.size())
			for t in tiles.size():
				tiles[t] = t
		var sig := hash(tiles)
		if sig == picked_sig:
			return
		picked_sig = sig
		var mmi := mmis["cover"] as MultiMeshInstance3D
		var buf := PackedFloat32Array()
		var n := 0
		for t in tiles:
			buf.append_array(rows.slice(tile_start[t] * ScatterLod.STRIDE, tile_end[t] * ScatterLod.STRIDE))
			n += tile_end[t] - tile_start[t]
		var mm := mmi.multimesh
		mm.instance_count = n
		if n > 0:
			mm.buffer = buf
		mmi.visible = n > 0

	## The reach changed (the view-range setting): the band and the tiles follow.
	func set_reach(r: float) -> void:
		reach = r
		GroundCover.set_band(cover_mesh, r)
		var mmi := mmis["cover"] as MultiMeshInstance3D
		mmi.visibility_range_end = r * GroundCover.BACKSTOP
		mmi.visibility_range_end_margin = 0.0
		picked_sig = -1
		if follows_eye:
			last_eye = Vector3(INF, INF, INF)
		else:
			update(last_eye)

	func set_down(p: TerrainProvider) -> void:
		var origin := cell.position
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for i in positions.size():
			var at := positions[i]
			at.y = p.get_height(at.x, at.z)
			positions[i] = at
			rows[i * ScatterLod.STRIDE + 7] = at.y - origin.y
			lo = lo.min(at)
			hi = hi.max(at)
		if not positions.is_empty():
			box = AABB(lo, hi - lo)
		picked_sig = -1
		if last_eye.is_finite() or not follows_eye:
			update(last_eye)


## A group for one plant's rows in one near-ring cell (CONTRACTS §6 rows, already thinned by the
## density setting). `range_base` is the kind's reach before the view-range setting.
static func make_group(cell: Node3D, asset_path: String, mesh: Mesh, rows: Array, range_base: float,
		view_range: float) -> Group:
	var g := Group.new()
	g.cell = cell
	g.asset_path = asset_path
	g.reach = range_base * view_range
	g.cover_mesh = mesh_for(asset_path, mesh, g.reach)
	var origin := cell.position
	# sorted into tiles: each tile's rows run together, so a pick is a few slices
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
	g.positions.resize(n)
	g.rows.resize(n * ScatterLod.STRIDE)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var at := 0
	for key: Vector2i in by_tile:
		var list: PackedInt32Array = by_tile[key]
		g.tile_start.append(at)
		var tlo := Vector2(INF, INF)
		var thi := -tlo
		for i in list:
			var row: Array = rows[i]
			var t := WorldStreamer.instance_transform(row, origin)
			var c := WorldStreamer.instance_tint(row)
			var b := t.basis
			var o := at * ScatterLod.STRIDE
			g.rows[o] = b.x.x
			g.rows[o + 1] = b.y.x
			g.rows[o + 2] = b.z.x
			g.rows[o + 3] = t.origin.x
			g.rows[o + 4] = b.x.y
			g.rows[o + 5] = b.y.y
			g.rows[o + 6] = b.z.y
			g.rows[o + 7] = t.origin.y
			g.rows[o + 8] = b.x.z
			g.rows[o + 9] = b.y.z
			g.rows[o + 10] = b.z.z
			g.rows[o + 11] = t.origin.z
			g.rows[o + 12] = c.r
			g.rows[o + 13] = c.g
			g.rows[o + 14] = c.b
			g.rows[o + 15] = c.a
			var p := Vector3(float(row[0]), float(row[1]), float(row[2]))
			g.positions[at] = p
			lo = lo.min(p)
			hi = hi.max(p)
			tlo = tlo.min(Vector2(p.x, p.z))
			thi = thi.max(Vector2(p.x, p.z))
			at += 1
		g.tile_end.append(at)
		g.tile_lo.append(tlo)
		g.tile_hi.append(thi)
	g.box = AABB(lo, hi - lo)
	g.level_of.resize(n)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = g.cover_mesh
	mm.instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = asset_path.get_file().get_basename()
	mmi.multimesh = mm
	mmi.set_meta("asset_path", asset_path)
	mmi.set_meta("range_base", range_base * BACKSTOP)
	mmi.set_meta("lod_group", true)
	mmi.set_meta("ground_cover", true)
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# grass shadows cost more than they show
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = g.reach * BACKSTOP
	mmi.visibility_range_end_margin = 0.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mmi.visible = false
	cell.add_child(mmi)
	g.mmis["cover"] = mmi
	return g
