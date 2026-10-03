extends TestCase
## Ground cover is drawn wherever the eye stands (world/ground_cover.gd). A visibility range is
## measured from the camera to the centre of a node's box, and a cell's grass of one kind was one
## MultiMesh over the whole 256 m cell, so standing anywhere but near a cell's middle the grass at
## your feet was not drawn: it came and went a cell at a time along every road. These tests stand an
## eye at the corners, edges and middle of a cell of grass and ask, by the renderer's own rule, that
## every plant near it is in a MultiMesh that is drawn.

const GRASS := "res://assets/models/flora/hearthvale_grass_clump_a/hearthvale_grass_clump_a.glb"
const CELL := Vector2i(16, 16)

var _holder: Node3D
var _streamer: WorldStreamer
var _eye: Node3D
var _saved: Dictionary = {}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_saved = Settings.data.duplicate(true)


func after_each() -> void:
	Settings.data = _saved.duplicate(true)
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null


## A streamer following an eye, and a cell (0..256 m in x and z) of grass every 8 m.
func _stage(eye_at: Vector3) -> void:
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	_streamer = WorldStreamer.new()
	_holder.add_child(_streamer)
	_eye = Node3D.new()
	_holder.add_child(_eye)
	_eye.position = eye_at
	_streamer.target = _eye
	var rows: Array = []
	for i in 32:
		for j in 32:
			rows.append([4.0 + 8.0 * i, 0.0, 4.0 + 8.0 * j, 0.0, 1.0, "#ffffff"])
	_streamer._build_cell(CELL, 0, {"instances": {GRASS: rows}})


func _cell() -> Node3D:
	return _streamer._loaded.get(CELL, null)


func _cover() -> GroundCover.Group:
	for g in _streamer._lod_groups:
		if g is GroundCover.Group:
			return g
	return null


## Each grass MultiMesh in the cell and the positions it holds now, in world metres.
func _drawn_sets() -> Array:
	var out: Array = []
	var cover := _cover()
	for c in _cell().get_children():
		if not (c is MultiMeshInstance3D) or str(c.get_meta("asset_path", "")) != GRASS:
			continue
		var held := PackedVector3Array()
		if cover != null and cover.mmis.get("cover") == c:
			for t in cover.picked(_streamer.lod_eye()):
				for i in range(cover.tile_start[t], cover.tile_end[t]):
					held.append(cover.positions[i])
		else:
			# a plain MultiMesh holds every row it was built with (the headless renderer keeps no
			# buffer to read back)
			for i in 32:
				for j in 32:
					held.append(Vector3(4.0 + 8.0 * i, 0.0, 4.0 + 8.0 * j))
		out.append({"mmi": c, "held": held})
	return out


## How many plants within `radius` of the eye are in a MultiMesh the renderer would draw: visible,
## and its box's centre within its visibility range of the camera.
func _drawn_near(radius: float) -> Vector2i:
	var eye := _streamer.lod_eye()
	var near := 0
	var drawn := 0
	for s in _drawn_sets():
		var mmi: MultiMeshInstance3D = s["mmi"]
		var held: PackedVector3Array = s["held"]
		if held.is_empty():
			continue
		var lo := held[0]
		var hi := held[0]
		for p in held:
			lo = lo.min(p)
			hi = hi.max(p)
		var centre := (lo + hi) * 0.5
		var shown := mmi.visible and (mmi.visibility_range_end <= 0.0 \
				or eye.distance_to(centre) <= mmi.visibility_range_end)
		for p in held:
			if Vector2(p.x - eye.x, p.z - eye.z).length() <= radius:
				drawn += 1 if shown else 0
	# every plant near the eye, whatever holds it
	for i in 32:
		for j in 32:
			if Vector2(4.0 + 8.0 * i - eye.x, 4.0 + 8.0 * j - eye.z).length() <= radius:
				near += 1
	return Vector2i(near, drawn)


func test_the_grass_near_the_eye_is_drawn_wherever_the_eye_is_in_the_cell() -> void:
	var reach := float(WorldStreamer.VIEW_RANGE["herb"])
	# a corner, the middle of an edge, half way in, the middle
	for at in [Vector3(2.0, 1.7, 2.0), Vector3(128.0, 1.7, 3.0), Vector3(60.0, 1.7, 200.0),
			Vector3(128.0, 1.7, 128.0)]:
		_stage(at)
		var counts := _drawn_near(reach * (1.0 - GroundCover.FADE_SHARE))
		assert_gt(counts.x, 0, "grass round the eye at %s" % str(at))
		assert_eq(counts.y, counts.x, "every plant within the cover's reach of %s is drawn" % str(at))
		_holder.free()
		_holder = null


func test_the_eye_walking_across_the_cell_keeps_the_grass_at_its_feet() -> void:
	_stage(Vector3(2.0, 1.7, 128.0))
	var reach := float(WorldStreamer.VIEW_RANGE["herb"])
	var x := 2.0
	while x < 256.0:
		_eye.position.x = x
		_streamer.update_lods(0)
		var counts := _drawn_near(reach * (1.0 - GroundCover.FADE_SHARE))
		assert_eq(counts.y, counts.x, "all the grass in reach drawn at x = %.0f" % x)
		x += 10.0


func test_one_multimesh_a_kind_and_only_the_plants_in_reach() -> void:
	_stage(Vector3(2.0, 1.7, 2.0))
	var sets := _drawn_sets()
	assert_eq(sets.size(), 1, "one MultiMesh for the kind in the cell, not one a tile: the draw calls stay")
	var cover := _cover()
	assert_true(cover != null, "the grass is drawn as ground cover")
	if cover == null:
		return
	var far := cover.reach + GroundCover.SLACK + GroundCover.TILE_M * sqrt(2.0)
	var held: PackedVector3Array = sets[0]["held"]
	assert_gt(1024, held.size(), "a corner's eye does not draw the whole cell")
	var furthest := 0.0
	for p in held:
		furthest = maxf(furthest, Vector2(p.x - 2.0, p.z - 2.0).length())
	assert_true(furthest <= far, "nothing held past the reach and a tile (%.0f m)" % furthest)
	assert_eq(_streamer.instance_count(), 1024, "and the cell still counts every plant once")
	assert_eq((cover.mmis["cover"] as MultiMeshInstance3D).multimesh.instance_count, held.size(),
			"what the MultiMesh holds is what was picked")


func test_the_edge_is_a_dissolve_per_plant_that_follows_the_view_range() -> void:
	_stage(Vector3(128.0, 1.7, 128.0))
	var cover := _cover()
	assert_true(cover != null)
	if cover == null:
		return
	var reach := float(WorldStreamer.VIEW_RANGE["herb"])
	var bands := 0
	for si in cover.cover_mesh.get_surface_count():
		var mat := cover.cover_mesh.surface_get_material(si) as ShaderMaterial
		if mat != null and GroundCover._has_uniform(mat.shader, "lod_fade_out"):
			bands += 1
			assert_eq(mat.get_shader_parameter("lod_fade_out"), Vector2(reach * 0.8, reach),
					"the grass thins over the last fifth of its reach")
	assert_gt(bands, 0, "the grass's foliage takes the dissolve")
	Settings.set_value("graphics", "view_range", 0.6)
	assert_near(cover.reach, reach * 0.6, 0.01, "the view range moves the reach")
	for si in cover.cover_mesh.get_surface_count():
		var mat := cover.cover_mesh.surface_get_material(si) as ShaderMaterial
		if mat != null and GroundCover._has_uniform(mat.shader, "lod_fade_out"):
			assert_eq(mat.get_shader_parameter("lod_fade_out"), Vector2(reach * 0.48, reach * 0.6))
	# the plant's own mesh, which a place's dressing may draw, keeps no band
	var mesh := _streamer._mesh_for(GRASS, 0)
	for si in mesh.get_surface_count():
		var mat := mesh.surface_get_material(si) as ShaderMaterial
		if mat != null and GroundCover._has_uniform(mat.shader, "lod_fade_out"):
			var band: Variant = mat.get_shader_parameter("lod_fade_out")
			assert_true(band == null or band == Vector2.ZERO, "the shared material untouched (%s)" % str(band))



# --- the rest of the scatter: a neighbour's props, the far ring's bushes, a corner cell's trees ---

const PROP := "res://assets/models/props/hearthvale_milestone_a/hearthvale_milestone_a.glb"
const CRATE := "res://assets/models/props/briarwold_crate_a/briarwold_crate_a.glb"
const BUSH := "res://assets/models/flora/briarwold_bracken_a/briarwold_bracken_a.glb"
const TREE := "res://assets/models/trees/hearthvale_hawthorn_a/hearthvale_hawthorn_a.glb"


## A streamer following an eye, with nothing built yet.
func _bare(eye_at: Vector3) -> void:
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	_streamer = WorldStreamer.new()
	_holder.add_child(_streamer)
	_eye = Node3D.new()
	_holder.add_child(_eye)
	_eye.position = eye_at
	_streamer.target = _eye


## Rows every `step` metres over a cell's square.
func _grid(cell: Vector2i, step: float) -> Array:
	var rows: Array = []
	var x0 := float(cell.x - 16) * 256.0
	var z0 := float(cell.y - 16) * 256.0
	var k := int(256.0 / step)
	for i in k:
		for j in k:
			rows.append([x0 + step * (0.5 + i), 0.0, z0 + step * (0.5 + j), 0.0, 1.0, "#ffffff"])
	return rows


func _group_for(asset: String, cell: Vector2i) -> ScatterLod.Group:
	var node: Node3D = _streamer._loaded.get(cell, null)
	for g in _streamer._lod_groups:
		var group := g as ScatterLod.Group
		if group.cell != node:
			continue
		if group is GroundCover.Group and (group as GroundCover.Group).asset_path == asset:
			return group
		if group.ladder != null and group.ladder.asset_path == asset:
			return group
	return null


func _cover_of(t: GroundCover.Tier) -> GroundCover.Group:
	for g in _streamer._lod_groups:
		if g is GroundCover.Group and (g as GroundCover.Group).tiers.has(t):
			return g
	return null


## The rows a ground-cover tier holds now, by the picked tiles or plants.
func _tier_held(t: GroundCover.Tier) -> PackedVector3Array:
	var held := PackedVector3Array()
	var g := _cover_of(t)
	var picked := t.pick(_streamer.lod_eye(), GroundCover.slack_for(g._outer()), false)
	if t.by_tile:
		for k in picked:
			for i in range(t.tile_start[k], t.tile_end[k]):
				held.append(t.positions[i])
	else:
		for i in picked:
			held.append(t.positions[i])
	return held


## Whether the renderer draws a MultiMesh holding `held`: visible, and its box's centre within range.
func _shown(mmi: MultiMeshInstance3D, held: PackedVector3Array) -> bool:
	if held.is_empty() or not mmi.visible:
		return false
	var lo := held[0]
	var hi := held[0]
	for p in held:
		lo = lo.min(p)
		hi = hi.max(p)
	var eye := _streamer.lod_eye()
	return mmi.visibility_range_end <= 0.0 or eye.distance_to((lo + hi) * 0.5) <= mmi.visibility_range_end


func test_a_neighbouring_cells_props_are_drawn_out_to_their_reach() -> void:
	# the eye in the middle of one cell; the next cell's milestones from its near edge, 128 m off, out
	var eye := Vector3(128.0, 1.7, 128.0)
	_bare(eye)
	var cell := Vector2i(17, 16)
	_streamer._build_cell(cell, 0, {"instances": {PROP: _grid(cell, 16.0)}})
	var g := _group_for(PROP, cell)
	assert_true(g is GroundCover.Group, "a milestone (no ladder) is drawn as ground cover")
	if not (g is GroundCover.Group):
		return
	var cover := g as GroundCover.Group
	var reach := float(WorldStreamer.VIEW_RANGE["prop"])
	var t: GroundCover.Tier = cover.tiers[0]
	var held := _tier_held(t)
	var shown := _shown(t.mmi, held)
	var near := 0
	var drawn := 0
	for r in _grid(cell, 16.0):
		var d := Vector2(float(r[0]) - eye.x, float(r[2]) - eye.z).length()
		if d <= reach:
			near += 1
			drawn += 1 if (shown and held.has(Vector3(float(r[0]), 0.0, float(r[2])))) else 0
	assert_gt(near, 0)
	assert_eq(drawn, near, "every milestone of the next cell within %.0f m is drawn" % reach)
	assert_eq(t.mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "and casts, as the near ring's props do")


func test_a_far_cells_bushes_stand_out_to_the_far_reach_and_no_further() -> void:
	var eye := Vector3(250.0, 1.7, 128.0)
	_bare(eye)
	var cell := Vector2i(18, 16)     # 512-768 m in x: the far ring
	_streamer._build_cell(cell, 2, {"instances": {BUSH: _grid(cell, 8.0)}})
	var g := _group_for(BUSH, cell)
	assert_true(g is GroundCover.Group, "the far ring's bracken is drawn as ground cover")
	if not (g is GroundCover.Group):
		return
	var cover := g as GroundCover.Group
	var reach := float(WorldStreamer.VIEW_RANGE_FAR["bush"])
	var t: GroundCover.Tier = cover.tiers[0]
	assert_eq(t.key, "far", "a far-ring cell draws the far share alone")
	var held := _tier_held(t)
	assert_true(_shown(t.mmi, held), "what is in reach is drawn")
	var past := reach + GroundCover.slack_for(reach) + GroundCover.TILE_M * sqrt(2.0)
	var furthest := 0.0
	var within := 0
	for p in held:
		var d := Vector2(p.x - eye.x, p.z - eye.z).length()
		furthest = maxf(furthest, d)
		within += 1 if d <= reach * (1.0 - GroundCover.FADE_SHARE) else 0
	assert_true(furthest <= past, "no bush held past the far reach and a tile (%.0f m)" % furthest)
	# every far-share bush within the reach's solid part is held
	var want := 0
	var share := int(ceil(1024.0 * float(WorldStreamer.FAR_KEEP["bush"])))
	for r in WorldStreamer._every_nth(_grid(cell, 8.0), share):
		if Vector2(float(r[0]) - eye.x, float(r[2]) - eye.z).length() <= reach * (1.0 - GroundCover.FADE_SHARE):
			want += 1
	assert_gt(want, 0)
	assert_eq(within, want, "every far-share bush within the reach is held")
	var band: Variant = (t.mesh.surface_get_material(0) as ShaderMaterial).get_shader_parameter("lod_fade_out")
	assert_eq(band, GroundCover.band_for(reach), "it dissolves at the far reach")


func test_a_cell_crossing_into_the_near_ring_keeps_its_far_share() -> void:
	_bare(Vector3(128.0, 1.7, 128.0))
	var near_cell := Vector2i(17, 16)
	var far_cell := Vector2i(18, 16)
	# the same rows built as a near cell and as a far one
	_streamer._build_cell(near_cell, 0, {"instances": {BUSH: _grid(near_cell, 8.0)}})
	_streamer._build_cell(far_cell, 2, {"instances": {BUSH: _grid(near_cell, 8.0)}})
	var near_g := _group_for(BUSH, near_cell) as GroundCover.Group
	var far_g := _group_for(BUSH, far_cell) as GroundCover.Group
	assert_true(near_g != null and far_g != null)
	if near_g == null or far_g == null:
		return
	assert_eq(near_g.tiers.size(), 2, "a near cell draws every bush near and the far share past that")
	var mid: GroundCover.Tier = near_g.tiers[1]
	var far: GroundCover.Tier = far_g.tiers[0]
	var a := Array(mid.positions)
	var b := Array(far.positions)
	a.sort()
	b.sort()
	assert_eq(a, b, "the same bushes past the near reach in either ring")
	var reach := float(WorldStreamer.VIEW_RANGE["bush"])
	var m := mid.mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(m.get_shader_parameter("lod_fade_in"), GroundCover.band_for(reach),
			"the far share fades in where the near tier fades out")
	var n := (near_g.tiers[0] as GroundCover.Tier).mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(n.get_shader_parameter("lod_fade_out"), GroundCover.band_for(reach))


func test_a_near_corner_cells_trees_are_drawn_however_far_off() -> void:
	# the eye at the far corner of the near ring: the cell's trees 360-720 m away, within the far
	# ring's reach, where the far ring's trees beyond them stand
	_bare(Vector3(-250.0, 1.7, -250.0))
	var cell := Vector2i(16, 16)
	_streamer._build_cell(cell, 0, {"instances": {TREE: _grid(cell, 32.0)}})
	var g := _group_for(TREE, cell)
	assert_true(g != null and g.ladder != null, "the hawthorns are drawn down their ladder")
	if g == null:
		return
	var mmi := g.mmis.get("impostor") as MultiMeshInstance3D
	assert_true(mmi != null, "with their pictures")
	if mmi == null:
		return
	var held := PackedVector3Array()
	for i in g.count():
		if g.level_of[i] == g.ladder.levels.size():
			held.append(g.positions[i])
	assert_eq(held.size(), g.count(), "every hawthorn this far off is a picture")
	assert_eq(mmi.multimesh.instance_count, g.count())
	assert_true(_shown(mmi, held), "and the pictures are drawn")


func test_a_neighbouring_cells_heavy_props_stand_out_to_their_reach() -> void:
	# a crate is heavy enough for a ladder (ScatterLod): its group holds each crate at its level out
	# to the near reach, the far share out to the far ring's, and no range on the MultiMeshes cuts it
	var eye := Vector3(128.0, 1.7, 128.0)
	_bare(eye)
	var cell := Vector2i(17, 16)
	_streamer._build_cell(cell, 0, {"instances": {CRATE: _grid(cell, 16.0)}})
	var g := _group_for(CRATE, cell)
	assert_true(g != null and g.ladder != null and not g.ladder.has_impostor(), "the crates are on a solid ladder")
	if g == null or g.ladder == null:
		return
	var near_m := float(WorldStreamer.VIEW_RANGE["prop"])
	var far_m := float(WorldStreamer.VIEW_RANGE_FAR["prop"])
	assert_near(g.reach_near, near_m, 0.01)
	assert_near(g.reach_far, far_m, 0.01)
	var near := 0
	var placed := 0
	for i in g.count():
		var d := g.positions[i].distance_to(_streamer.lod_eye())
		if d <= near_m:
			near += 1
			placed += 1 if int(g.level_of[i]) != ScatterLod.OUT else 0
		elif d > far_m:
			assert_eq(int(g.level_of[i]), ScatterLod.OUT, "nothing drawn past the far reach")
	assert_gt(near, 0)
	assert_eq(placed, near, "every crate within the near reach is at a level")
	for key in g.mmis:
		assert_near((g.mmis[key] as GeometryInstance3D).visibility_range_end, 0.0, 0.001,
				"%s: no range measured to the box's centre" % key)
