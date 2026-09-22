class_name ScatterLod
extends RefCounted
## Level of detail per instance for the scattered trees, by distance from the camera.
##
## A MultiMesh picks one level of detail for all of its instances, from its bounding box, and a
## cell's box holds the camera whenever the camera is in the cell or beside it. So every tree in
## the cells around the eye was drawn whole: on Merrowby's street, 1,937 trees in the near ring
## of which 43 were within eighty metres, and 650 thousand of the frame's 1.56 million primitives
## were trees and their shadows. The fix is not fewer trees. It is to draw each tree at the level
## its own distance deserves:
##
##   level 0  the full mesh                        up to  max(30 m, 4 x its height)
##   level 1  the forge's LOD1: trunk and cards    up to  max(70 m, 10 x its height)
##   beyond   the forge's impostor: eight views of the tree on one quad that turns to face you
##            (tools/forge/gen_impostors.py, assets/shaders/tree_impostor.gdshader)
##
## both multiplied by the level-of-detail bias in the graphics settings. Each cell's trees of one
## asset are a `Group`: one MultiMesh per level and part, refilled with the instances in that
## level whenever the camera has moved a couple of metres. The canopy and the impostor dissolve
## into each other across a band (assets/shaders/lod_fade.gdshaderinc), so a tree changing level
## neither pops nor is ever drawn twice; the bark has no dissolve and switches outright in the
## middle of the band, where the canopy covers it.
##
## An opaque asset with a LOD ladder and weight to lose (a drystone wall, a boulder) takes the
## same treatment without the dissolve, at distances set by its size.

## Where a tree leaves its full mesh, and where it becomes a picture, at a bias of one.
const NEAR_MIN := 30.0
const NEAR_PER_METRE := 4.0
const FAR_MIN := 70.0
const FAR_PER_METRE := 10.0
## Opaque ladders: by bounding radius, not height.
const SOLID_NEAR_MIN := 25.0
const SOLID_NEAR_PER_METRE := 10.0
const SOLID_FAR_MIN := 60.0
const SOLID_FAR_PER_METRE := 25.0
## An opaque asset lighter than this is not worth the extra draw calls its levels cost.
const SOLID_MIN_TRIS := 1500
## Each dissolve is this share of the distance it happens at, and at least this many metres.
const FADE_SHARE := 0.2
const FADE_MIN := 4.0
## How far the eye may move before a group is sorted again, and how much slack each level's
## membership carries beyond its band so an instance is already there when the eye arrives.
const STEP := 2.0
const SLACK := 3.0
## The bark has no dissolve, so it switches outright, this far either side of its line.
const HYSTERESIS := 1.5
## Floats a MultiMesh instance takes with a 3D transform and a colour.
const STRIDE := 16
const IMPOSTOR_SHADER := "res://assets/shaders/tree_impostor.gdshader"


## The meshes one asset is drawn with at each level.
class Ladder extends RefCounted:
	var asset_path := ""
	## Per level: {"solid": Mesh or null, "leaves": Mesh or null}.
	var levels: Array = []
	var impostor: Mesh = null
	var tree := false
	var size := 1.0
	var bias := 1.0
	var near := 0.0
	var far := 0.0
	var near_fade := 0.0
	var far_fade := 0.0
	## Leaf materials per level, and the impostor's, whose dissolve bands `set_bias` writes.
	var leaf_materials: Array = []
	var impostor_material: ShaderMaterial = null

	func has_impostor() -> bool:
		return impostor != null

	func set_bias(b: float) -> void:
		bias = clampf(b, 0.1, 4.0)
		if tree:
			near = maxf(NEAR_MIN, NEAR_PER_METRE * size) * bias
			far = maxf(FAR_MIN, FAR_PER_METRE * size) * bias
		else:
			near = maxf(SOLID_NEAR_MIN, SOLID_NEAR_PER_METRE * size) * bias
			far = maxf(SOLID_FAR_MIN, SOLID_FAR_PER_METRE * size) * bias
		near_fade = maxf(FADE_MIN, near * FADE_SHARE)
		far_fade = maxf(FADE_MIN, far * FADE_SHARE)
		var near_band := Vector2(near - near_fade * 0.5, near + near_fade * 0.5)
		var far_band := Vector2(far - far_fade * 0.5, far + far_fade * 0.5)
		for level in leaf_materials.size():
			for m in leaf_materials[level]:
				var mat := m as ShaderMaterial
				mat.set_shader_parameter("lod_fade_in", near_band if level == 1 else Vector2.ZERO)
				var fades_out := level == 0 or (level == 1 and has_impostor())
				mat.set_shader_parameter("lod_fade_out", (near_band if level == 0 else far_band) \
						if fades_out else Vector2.ZERO)
		if impostor_material != null:
			impostor_material.set_shader_parameter("lod_fade_in", far_band)


## The trees of one asset in one cell.
class Group extends RefCounted:
	var ladder: Ladder
	var cell: Node3D
	var positions := PackedVector3Array()
	var rows := PackedFloat32Array()
	var level_of := PackedByteArray()
	## slot name -> MultiMeshInstance3D: solid0, leaves0, solid1, leaves1, solid2, impostor
	var mmis: Dictionary = {}
	var signatures: Dictionary = {}
	var box := AABB()
	var last_eye := Vector3(INF, INF, INF)
	var far_ring := false

	func count() -> int:
		return positions.size()

	## True when the eye has moved far enough that some instance may have changed level.
	func wants_update(eye: Vector3) -> bool:
		if far_ring:
			return false
		if last_eye.distance_to(eye) < STEP:
			return false
		# a group wholly past the impostor line, and sorted as such, stays as it is
		var reach := ladder.far + ladder.far_fade * 0.5 + SLACK + STEP
		if _box_distance(eye) > reach and _all_far():
			last_eye = eye
			return false
		return true

	func _all_far() -> bool:
		var last := ladder.levels.size() if ladder.has_impostor() else ladder.levels.size() - 1
		for i in level_of.size():
			if level_of[i] < last:
				return false
		return true

	func _box_distance(eye: Vector3) -> float:
		var p := eye.clamp(box.position, box.end)
		return p.distance_to(eye)

	## Sorts every instance into its level for an eye at `eye` and refills the MultiMeshes whose
	## membership changed.
	func update(eye: Vector3) -> void:
		last_eye = eye
		var n := positions.size()
		var lad := ladder
		var imp := lad.has_impostor()
		var nlev := lad.levels.size()
		var near := lad.near
		var far := lad.far
		var nh := lad.near_fade * 0.5
		var fh := lad.far_fade * 0.5
		# the solid part's lines: the middle of the near dissolve, and the far end of the far one
		# (the mid-level trunk stays until the picture is whole)
		var line1 := near
		var line2 := far + fh if imp else far
		# packed arrays are values: kept as locals and gathered at the end, never appended to
		# through a dictionary
		var solid0 := PackedInt32Array()
		var solid1 := PackedInt32Array()
		var solid2 := PackedInt32Array()
		var leaves0 := PackedInt32Array()
		var leaves1 := PackedInt32Array()
		var pictures := PackedInt32Array()
		for i in n:
			var d := positions[i].distance_to(eye)
			var was := int(level_of[i])
			var lvl := 0
			if d >= line1:
				lvl = 1
			if (nlev > 2 or imp) and d >= line2:
				lvl = 2
			if lvl != was:
				# hysteresis at whichever line lies between the old level and the new
				var line := line1 if mini(lvl, was) == 0 else line2
				if absf(d - line) < HYSTERESIS:
					lvl = was
			level_of[i] = lvl
			match lvl:
				0:
					solid0.append(i)
				1:
					solid1.append(i)
				_:
					solid2.append(i)
			if lad.tree:
				if d < near + nh + SLACK:
					leaves0.append(i)
				if d > near - nh - SLACK and (not imp or d < far + fh + SLACK):
					leaves1.append(i)
				if imp and d > far - fh - SLACK:
					pictures.append(i)
		var idx := {"solid0": solid0, "solid1": solid1, "solid2": solid2, "leaves0": leaves0,
				"leaves1": leaves1, "impostor": pictures}
		for key in mmis:
			var list: PackedInt32Array = idx[key]
			var sig := hash(list)
			if signatures.get(key, -1) == sig:
				continue
			signatures[key] = sig
			ScatterLod._fill(mmis[key] as MultiMeshInstance3D, rows, list)

	## The far ring: everything is a picture, sorted once.
	func fill_far() -> void:
		var all := PackedInt32Array()
		all.resize(positions.size())
		for i in positions.size():
			all[i] = i
			level_of[i] = ladder.levels.size()
		ScatterLod._fill(mmis["impostor"] as MultiMeshInstance3D, rows, all)


## Every ladder the streamer has asked for, by asset path; null where an asset has none.
static var _ladders: Dictionary = {}


## The ladder for a scatter asset, or null when it is drawn as it always was: no LOD1 in the
## file, or too light to be worth the levels.
static func ladder_for(asset_path: String, packed: PackedScene, bias: float) -> Ladder:
	if _ladders.has(asset_path):
		var cached: Ladder = _ladders[asset_path]
		if cached != null and not is_equal_approx(cached.bias, bias):
			cached.set_bias(bias)
		return cached
	var lad := _build_ladder(asset_path, packed)
	if lad != null:
		lad.set_bias(bias)
	_ladders[asset_path] = lad
	return lad


static func set_bias_all(bias: float) -> void:
	for key in _ladders:
		var lad: Ladder = _ladders[key]
		if lad != null:
			lad.set_bias(bias)


static func _build_ladder(asset_path: String, packed: PackedScene) -> Ladder:
	if packed == null:
		return null
	var meshes := _meshes_by_name(packed)
	var base := asset_path.get_file().get_basename()
	var lod0: Mesh = meshes.get(base, null)
	var lod1: Mesh = meshes.get(base + "_LOD1", null)
	if lod0 == null or lod1 == null:
		return null
	var meta := _meta(asset_path)
	var lad := Ladder.new()
	lad.asset_path = asset_path
	lad.tree = asset_path.contains("/trees/")
	var bounds: Dictionary = meta.get("bounds", {})
	if lad.tree:
		lad.size = maxf(float(bounds.get("height", 4.0)), 1.0)
		var parts0 := _split_leaves(lod0)
		var leaves1: Mesh = meshes.get(base + "_cards_LOD1", null)
		lad.levels = [
			{"solid": parts0[0], "leaves": _with_own_materials(parts0[1])},
			{"solid": lod1, "leaves": _with_own_materials(leaves1)},
		]
		var lod2: Mesh = meshes.get(base + "_LOD2", null)
		if lod2 != null and _is_impostor(lod2):
			var mat := (lod2.surface_get_material(0) as ShaderMaterial).duplicate() as ShaderMaterial
			lad.impostor = _with_material(lod2, mat)
			lad.impostor_material = mat
		for level in lad.levels:
			var mats: Array = []
			var leaves: Mesh = level["leaves"]
			if leaves != null:
				for i in leaves.get_surface_count():
					var m := leaves.surface_get_material(i)
					if m is ShaderMaterial:
						mats.append(m)
			lad.leaf_materials.append(mats)
	else:
		var lod2: Mesh = meshes.get(base + "_LOD2", null)
		var tris := _tri_count(lod0)
		if lod2 == null or tris < SOLID_MIN_TRIS:
			return null
		lad.size = maxf(float(bounds.get("radius", 1.0)), 0.3)
		lad.levels = [{"solid": lod0, "leaves": null}, {"solid": lod1, "leaves": null},
				{"solid": lod2, "leaves": null}]
	return lad


static func _meshes_by_name(packed: PackedScene) -> Dictionary:
	var out: Dictionary = {}
	var state := packed.get_state()
	for i in state.get_node_count():
		if state.get_node_type(i) != "MeshInstance3D":
			continue
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) != "mesh":
				continue
			var v: Variant = state.get_node_property_value(i, p)
			if v is Mesh:
				out[str(state.get_node_name(i))] = v
	return out


static func _meta(asset_path: String) -> Dictionary:
	var meta_path := asset_path.get_basename() + ".meta.json"
	if not FileAccess.file_exists(meta_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func _is_impostor(mesh: Mesh) -> bool:
	if mesh.get_surface_count() != 1:
		return false
	var mat := mesh.surface_get_material(0)
	return mat is ShaderMaterial and (mat as ShaderMaterial).shader != null \
			and (mat as ShaderMaterial).shader.resource_path == IMPOSTOR_SHADER


static func _is_leaf(mat: Material) -> bool:
	return mat is ShaderMaterial


## LOD0 as [bark, leaves]: the surfaces drawn with the foliage shader apart from the rest. Either
## may be null (a dead ash has no leaves).
static func _split_leaves(mesh: Mesh) -> Array:
	var solid: Array[int] = []
	var leaves: Array[int] = []
	for i in mesh.get_surface_count():
		if _is_leaf(mesh.surface_get_material(i)):
			leaves.append(i)
		else:
			solid.append(i)
	if leaves.is_empty():
		return [mesh, null]
	return [_subset(mesh, solid), _subset(mesh, leaves)]


## A mesh made of some of another's surfaces, sharing their data (and their own LODs).
static func _subset(mesh: Mesh, keep: Array[int]) -> Mesh:
	if keep.is_empty():
		return null
	var am := mesh as ArrayMesh
	if am == null:
		return null
	var all: Array = am.get("_surfaces")
	var picked: Array = []
	for i in keep:
		picked.append((all[i] as Dictionary).duplicate())
	var out := ArrayMesh.new()
	out.set("_surfaces", picked)
	return out


## A copy of the mesh whose leaf surfaces carry materials of their own, so one level's dissolve
## band does not become another's. The vertex data is shared.
static func _with_own_materials(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var am := mesh as ArrayMesh
	if am == null:
		return mesh
	var all: Array = am.get("_surfaces")
	var copied: Array = []
	for s in all:
		var d := (s as Dictionary).duplicate()
		var m: Variant = d.get("material")
		if m is ShaderMaterial:
			d["material"] = (m as ShaderMaterial).duplicate()
		copied.append(d)
	var out := ArrayMesh.new()
	out.set("_surfaces", copied)
	out.custom_aabb = am.custom_aabb
	return out


static func _with_material(mesh: Mesh, mat: Material) -> Mesh:
	var am := mesh as ArrayMesh
	var all: Array = am.get("_surfaces")
	var d := (all[0] as Dictionary).duplicate()
	d["material"] = mat
	var out := ArrayMesh.new()
	out.set("_surfaces", [d])
	out.custom_aabb = am.custom_aabb
	return out


static func _tri_count(mesh: Mesh) -> int:
	var am := mesh as ArrayMesh
	if am == null:
		return 0
	var tris := 0
	for si in am.get_surface_count():
		var n := am.surface_get_array_index_len(si)
		if n == 0:
			n = am.surface_get_array_len(si)
		tris += n / 3
	return tris


## A group for one asset's instances in one cell. `rows` are the cell's CONTRACTS §6 rows;
## `origin` is the cell node's position.
static func make_group(lad: Ladder, cell: Node3D, rows: Array, far_ring: bool, cast_shadows: bool,
		range_end: float, asset_path: String) -> Group:
	var g := Group.new()
	g.ladder = lad
	g.cell = cell
	g.far_ring = far_ring
	var n := rows.size()
	var probe := MultiMesh.new()
	probe.transform_format = MultiMesh.TRANSFORM_3D
	probe.use_colors = true
	probe.instance_count = n
	var origin := cell.position
	g.positions.resize(n)
	g.level_of.resize(n)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in n:
		var row: Array = rows[i]
		probe.set_instance_transform(i, WorldStreamer.instance_transform(row, origin))
		probe.set_instance_color(i, WorldStreamer.instance_tint(row))
		var p := Vector3(float(row[0]), float(row[1]), float(row[2]))
		g.positions[i] = p
		lo = lo.min(p)
		hi = hi.max(p)
		g.level_of[i] = 0
	g.rows = probe.buffer
	g.box = AABB(lo, hi - lo)
	var base := asset_path.get_file().get_basename()
	if far_ring:
		if lad.has_impostor():
			g.mmis["impostor"] = _mmi(cell, "%s_far" % base, lad.impostor, false, range_end, asset_path)
		return g
	for level in lad.levels.size():
		var parts: Dictionary = lad.levels[level]
		if parts["solid"] != null:
			g.mmis["solid%d" % level] = _mmi(cell, "%s_lod%d" % [base, level], parts["solid"],
					cast_shadows, range_end, asset_path)
		if parts["leaves"] != null:
			g.mmis["leaves%d" % level] = _mmi(cell, "%s_lod%d_leaves" % [base, level], parts["leaves"],
					cast_shadows, range_end, asset_path)
	if lad.has_impostor():
		g.mmis["impostor"] = _mmi(cell, "%s_impostor" % base, lad.impostor, cast_shadows, range_end,
				asset_path)
	return g


static func _mmi(cell: Node3D, node_name: String, mesh: Mesh, cast_shadows: bool, range_end: float,
		asset_path: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.set_meta("asset_path", asset_path)
	mmi.set_meta("range_base", range_end)
	mmi.set_meta("lod_group", true)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = range_end
	mmi.visibility_range_end_margin = range_end * 0.15
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.visible = false
	cell.add_child(mmi)
	return mmi


static func _fill(mmi: MultiMeshInstance3D, rows: PackedFloat32Array, idx: PackedInt32Array) -> void:
	var mm := mmi.multimesh
	var n := idx.size()
	if n == 0:
		mm.instance_count = 0
		mmi.visible = false
		return
	var buf := PackedFloat32Array()
	for i in idx:
		buf.append_array(rows.slice(i * STRIDE, i * STRIDE + STRIDE))
	mm.instance_count = n
	mm.buffer = buf
	mmi.visible = true
