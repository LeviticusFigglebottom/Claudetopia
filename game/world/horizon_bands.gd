class_name HorizonBands
extends Node3D
## The two things on the skyline that are not objects (docs/HORIZON.md, "Features that are not
## objects"): the Thornmarch, the Briar wall along the east edge, and the Hushline's mist along
## the south cliff foot. Built once, always loaded, by the horizon layer.
##
## The Thornmarch is a wood: the Briarwold black ash's own picture (the impostor its scattered
## trees become past 70 m), stood thick along the ridge line between x 3925 and 4030 wherever the
## ground there is Briarwold, a MultiMesh a cell, so a cell of the wall gives way to the cell's own
## scatter when it is built, as the horizon's stand-ins do.
##
## The Hushline is not a line: from the Stair Head and the Choir it is a pale, colourless haze
## over everything south. A curtain along the south cliff foot, dense at the ground and gone by
## seventy metres up, that thins away as the eye comes near it, so walking into the Hush is
## walking into mist and not into a painted sheet.

const THORNMARCH_X := Vector2(3925.0, 4030.0)
const THORNMARCH_REGION := "core:region/briarwold"
const THORNMARCH_TREE := "res://assets/models/trees/briarwold_black_ash_a/briarwold_black_ash_a.glb"
## Metres between trees along the wall, and how far either side of it a row is thrown.
const THORNMARCH_STEP := 9.0
const THORNMARCH_ROWS := 3
const HUSHLINE_Z := 3930.0
const HUSHLINE_X := Vector2(-1600.0, 1600.0)
const HUSHLINE_HEIGHT := 70.0
const HUSHLINE_SHADER := preload("res://assets/shaders/hushline_haze.gdshader")

var provider: TerrainProvider = null
var streamer: WorldStreamer = null
## cell -> the Thornmarch's MultiMeshInstance3D in it
var wall: Dictionary = {}
var haze: MeshInstance3D = null


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


func set_reach(r: float) -> void:
	for c in wall:
		var mmi := wall[c] as MultiMeshInstance3D
		mmi.visibility_range_end = r
		mmi.visibility_range_end_margin = r * 0.1
	if haze != null:
		haze.visibility_range_end = r


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
			var scale := rng.randf_range(1.3, 1.9)
			var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale), at)
			(by_cell.get_or_add(cell, []) as Array).append(t)
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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 64.0
	var x := HUSHLINE_X.x
	while x < HUSHLINE_X.y:
		var x2 := x + step
		var g1 := provider.get_height(x, HUSHLINE_Z) - 6.0
		var g2 := provider.get_height(x2, HUSHLINE_Z) - 6.0
		var a := Vector3(x, g1, HUSHLINE_Z)
		var b := Vector3(x2, g2, HUSHLINE_Z)
		var a_top := a + Vector3.UP * HUSHLINE_HEIGHT
		var b_top := b + Vector3.UP * HUSHLINE_HEIGHT
		# UV.y is the height up the curtain, 0 at its foot
		for v in [[a, 0.0], [b, 0.0], [b_top, 1.0], [a, 0.0], [b_top, 1.0], [a_top, 1.0]]:
			st.set_uv(Vector2(((v[0] as Vector3).x - HUSHLINE_X.x) / 256.0, float(v[1])))
			st.add_vertex(v[0])
		x = x2
	haze = MeshInstance3D.new()
	haze.name = "Hushline"
	haze.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = HUSHLINE_SHADER
	haze.material_override = mat
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(haze)


func _cell_of(pos: Vector3) -> Vector2i:
	if streamer != null:
		return streamer.cell_of(pos)
	return Vector2i(int(floor((pos.x - provider.origin.x) / 256.0)), int(floor((pos.z - provider.origin.y) / 256.0)))
