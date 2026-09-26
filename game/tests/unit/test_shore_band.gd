extends TestCase
## The shore band (world/shore_band.gd): the swash, its foam and the wet band are drawn on the
## ground just above the still water, near the eye, and nowhere else.

const LARK := Vector3(170.0, 46.0, 2492.0)


func test_the_band_lies_along_the_waterline_near_the_eye() -> void:
	var p := TerrainProvider.new()
	if not p.load_data() or not p.has_runtime_maps():
		p.free()
		return
	var band := ShoreBand.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(band)
	band.set_process(false)
	band.setup(p, null, null)
	assert_gt(band.shore_cells(), 100, "the lakes' and the sea's shores are found (%d cells)" % band.shore_cells())
	for i in 40:
		band.update(LARK)
	var tris := band.triangles()
	assert_gt(tris, 50, "a band round the Lark Pool (%d triangles)" % tris)
	assert_true(tris < 60000, "and not a field of it (%d)" % tris)
	var verts: PackedVector3Array = band.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var off := 0
	for t in range(0, verts.size(), 3):
		# a triangle has a corner in the band of its still water (a steep bank's quad can have the
		# others well above it)
		var in_band := false
		for k in 3:
			var v := verts[t + k]
			var rise := v.y - ShoreBand.LIFT_M - p.nearest_water_level(v.x, v.z)
			if rise > -ShoreBand.BELOW_M - 0.05 and rise < ShoreBand.ABOVE_M + 0.05:
				in_band = true
		if not in_band:
			off += 1
		assert_true(Vector2(verts[t].x - LARK.x, verts[t].z - LARK.z).length() < ShoreBand.REACH_M + 2.0 * ShoreBand.CELL_M,
				"near the eye")
	assert_eq(off, 0, "every triangle of it touches its band of the still water")
	# far from any water there is none
	var dry := Vector3(-600.0, 0.0, 3300.0)
	var far_off := false
	for c in [Vector2i(floori(dry.x / ShoreBand.CELL_M), floori(dry.z / ShoreBand.CELL_M))]:
		far_off = not band._shore_cells.has(c)
	if far_off:
		for i in 10:
			band.update(dry)
		assert_true(band.triangles() < tris, "the band follows the eye")
	(Engine.get_main_loop() as SceneTree).root.remove_child(band)
	band.free()
	p.free()
