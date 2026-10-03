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
