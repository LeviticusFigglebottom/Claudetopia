class_name HorizonBands
extends Node3D
## The two things on the skyline that are not objects (docs/HORIZON.md, "Features that are not
## objects"): the Thornmarch, the Briar wall along the east edge, and the Hushline's mist over
## the Hush below the south cliffs. Built once, always loaded, by the horizon layer.
##
## The Thornmarch is a wood: the Briarwold black ash's own picture (the impostor its scattered
## trees become past 70 m), stood thick along the ridge line between x 3925 and 4030 wherever the
## ground there is Briarwold, a MultiMesh a cell, so a cell of the wall gives way to the cell's own
## scatter when it is built, as the horizon's stand-ins do.
##
## The Hushline is not a line: from the Stair Head and the Choir it is a pale, colourless haze
## over everything south. A curtain out over the Hush, 130 m off the Landing, runs along the whole
## south coast. It stands from the water to 260 m and is thick to 170 m. It has to be that tall to
## be seen at all. From the Stair Head the knoll's own shoulder hides everything out there below
## about 100 m, and from the middle of the Choir's Crown everything below about 115 m. A bank that
## has thinned out by then shows only its thin top over the brow, and the south looks as it did
## without it. Thick to 170 m, it rises about twelve degrees over the brow from the Stair Head and
## about five from the Crown, and thins out above that. It also thins away along its length at
## either end, and as the eye comes near it, so walking into the Hush is walking into mist and not
## into a painted sheet. It is cut into lengths, so each is culled and sorted on its own.

const THORNMARCH_X := Vector2(3925.0, 4030.0)
const THORNMARCH_REGION := "core:region/briarwold"
const THORNMARCH_TREE := "res://assets/models/trees/briarwold_black_ash_a/briarwold_black_ash_a.glb"
## Metres between trees along the wall, and how far either side of it a row is thrown.
const THORNMARCH_STEP := 9.0
const THORNMARCH_ROWS := 3
## Out over the Hush's water: the Landing is at z 3870, the Stair Head at 3670, the world's edge
## at 4096.
const HUSHLINE_Z := 4000.0
## The south coast, from past the south-west corner, where the coast turns north, to the Briar
## wall's corner in the east.
const HUSHLINE_X := Vector2(-3600.0, 4080.0)
## Metres above the sea: the curtain's top, and how high it is thick.
const HUSHLINE_TOP := 260.0
const HUSHLINE_THICK_TO := 170.0
## One mesh a length, so the lengths out of view are culled.
const HUSHLINE_PIECE := 512.0
const HUSHLINE_STEP := 64.0
const HUSHLINE_SHADER := preload("res://assets/shaders/hushline_haze.gdshader")

var provider: TerrainProvider = null
var streamer: WorldStreamer = null
## cell -> the Thornmarch's MultiMeshInstance3D in it
var wall: Dictionary = {}
## Where the wall's trees stand (a headless renderer keeps no MultiMesh buffer to read back).
var points := PackedVector3Array()
## The Hushline's lengths, west to east.
var haze: Array[MeshInstance3D] = []


func build(p: TerrainProvider, s: WorldStreamer) -> void:
	provider = p
	streamer = s
	_build_thornmarch()
	_build_hushline()


## Trees in the wall, over all its cells.
func wall_trees() -> int:
	var n := 0
	for c in wall:
		n += (wall[c] as MultiMeshInstance3D).multimesh.instance_count
	return n


## The bands in words, for a capture's log: the wall's cells shown, and the mist's box and reach.
func describe() -> String:
	var shown := 0
	for c in wall:
		if (wall[c] as Node3D).visible:
			shown += 1
	var mist := "no mist"
	if not haze.is_empty():
		var box := mist_box()
		var up := 0
		for m in haze:
			if m.is_visible_in_tree():
				up += 1
		mist = "the mist in %d of %d lengths, %.0f m along at z %.0f, %.0f to %.0f m up, drawn to %.0f m" % [
				up, haze.size(), box.size.x, box.get_center().z, box.position.y, box.end.y,
				haze[0].visibility_range_end]
	return "the Thornmarch in %d of %d cells, %s" % [shown, wall.size(), mist]


## The Hushline's lengths together, in world space.
func mist_box() -> AABB:
	var box := AABB()
	for i in haze.size():
		var b := haze[i].global_transform * haze[i].get_aabb() if haze[i].is_inside_tree() \
				else haze[i].get_aabb()
		box = b if i == 0 else box.merge(b)
	return box


func set_reach(r: float) -> void:
	for c in wall:
		var mmi := wall[c] as MultiMeshInstance3D
		mmi.visibility_range_end = r
		mmi.visibility_range_end_margin = r * 0.1
	# the mist melts away at the reach, as the stand-ins do, rather than going out a length at once
	for m in haze:
		m.visibility_range_end = r
		m.visibility_range_end_margin = r * 0.1
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func hand_over(cell: Vector2i, to_cell: bool) -> void:
	if wall.has(cell):
		(wall[cell] as MultiMeshInstance3D).visible = not to_cell


func _build_thornmarch() -> void:
	if provider == null or not ResourceLoader.exists(THORNMARCH_TREE):
		return
	var lad := ScatterLod.ladder_for(THORNMARCH_TREE, load(THORNMARCH_TREE) as PackedScene, 1.0)
	if lad == null or not lad.has_impostor():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4031
	var by_cell: Dictionary = {}
	var z := float(provider.origin.y)
	var z_end := z + float(provider.size_m)
	while z < z_end:
		for row in THORNMARCH_ROWS:
			var x := rng.randf_range(THORNMARCH_X.x, THORNMARCH_X.y)
			var zz := z + rng.randf_range(-THORNMARCH_STEP * 0.5, THORNMARCH_STEP * 0.5)
			if provider.nearest_region_id_at(x, zz) != THORNMARCH_REGION:
				continue
			var at := Vector3(x, provider.get_height(x, zz), zz)
			var cell := _cell_of(at)
			var size := rng.randf_range(1.3, 1.9)
			var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), at)
			(by_cell.get_or_add(cell, []) as Array).append(t)
			points.append(at)
		z += THORNMARCH_STEP
	for cell in by_cell:
		var ts: Array = by_cell[cell]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = lad.impostor
		mm.instance_count = ts.size()
		for i in ts.size():
			mm.set_instance_transform(i, ts[i])
			mm.set_instance_color(i, Color(0.62, 0.62, 0.6))    # the wall is darker than a lone ash
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Thornmarch_%d_%d" % [cell.x, cell.y]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		wall[cell] = mmi
		if streamer != null:
			mmi.visible = not streamer.has_cell(cell)


func _build_hushline() -> void:
	if provider == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = HUSHLINE_SHADER
	mat.set_shader_parameter("thick_to", HUSHLINE_THICK_TO)
	mat.set_shader_parameter("top", HUSHLINE_TOP)
	mat.set_shader_parameter("from_x", HUSHLINE_X.x)
	mat.set_shader_parameter("to_x", HUSHLINE_X.y)
	var x0 := HUSHLINE_X.x
	while x0 < HUSHLINE_X.y - 1.0:
		var x1 := minf(x0 + HUSHLINE_PIECE, HUSHLINE_X.y)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var x := x0
		while x < x1 - 0.5:
			var x2 := minf(x + HUSHLINE_STEP, x1)
			# the foot a little under the sea floor, so no edge shows at the water; the top level
			var a := Vector3(x, provider.get_height(x, HUSHLINE_Z) - 6.0, HUSHLINE_Z)
			var b := Vector3(x2, provider.get_height(x2, HUSHLINE_Z) - 6.0, HUSHLINE_Z)
			var a_top := Vector3(x, HUSHLINE_TOP, HUSHLINE_Z)
			var b_top := Vector3(x2, HUSHLINE_TOP, HUSHLINE_Z)
			for v in [a, b, b_top, a, b_top, a_top]:
				st.add_vertex(v)
			x = x2
		var m := MeshInstance3D.new()
		m.name = "Hushline_%d" % haze.size()
		m.mesh = st.commit()
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		haze.append(m)
		x0 = x1


func _cell_of(pos: Vector3) -> Vector2i:
	if streamer != null:
		return streamer.cell_of(pos)
	return Vector2i(int(floor((pos.x - provider.origin.x) / 256.0)), int(floor((pos.z - provider.origin.y) / 256.0)))
