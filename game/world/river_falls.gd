class_name RiverFalls
extends Node3D
## The rivers' falls, drawn from rivers.json's `falls` (tools/world/worldgen/hydro.py find_falls):
## each one's sheet of water from the lip to the foot, the white water where it lands, and for a
## tall one the mist that hangs over its pool. A river ribbon runs down a fall as a steep ramp of
## the same water as the reach above it, which reads as a slide rather than a fall.
##
## A fall is {"top": [x, y, z], "foot": [x, y, z], "height_m", "width_m", "run_m", "facing_deg",
## "kind": "fall"|"cascade", "pool"?: {...}}. A "fall" (the drop is more than the run) leaves
## the lip and arcs out and down; a "cascade" follows the rock down in steps of white water.
##
## Places that raise their own rock and water at a fall (PoiBuilders' waterfall dressing) ask
## `RiverFalls.near(position)` and leave the water to this.

const SHEET_ROWS := 12
const SHEET_COLS := 4
## Past this the sheet is not drawn: a fall is a thread of white at a kilometre, and the far
## ring's grain is coarser than the falls.
const SHEET_RANGE_M := 900.0
const SPRAY_RANGE_M := 220.0

## Every fall in the world as [top, foot, width], so a place can ask whether one is its own.
static var all: Array = []


static func near(pos: Vector3, radius := 30.0) -> bool:
	for f in all:
		var top: Vector3 = f[0]
		var foot: Vector3 = f[1]
		if Vector2(pos.x - top.x, pos.z - top.z).length() < radius \
				or Vector2(pos.x - foot.x, pos.z - foot.z).length() < radius:
			return true
	return false


static func read_falls(rivers: Array) -> Array:
	var out: Array = []
	for r in rivers:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		for f in r.get("falls", []):
			if typeof(f) == TYPE_DICTIONARY and f.has("top") and f.has("foot"):
				out.append(f)
	return out


func build(rivers: Array) -> int:
	all.clear()
	var n := 0
	for f in read_falls(rivers):
		_one(f, n)
		n += 1
	return n


static func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _one(f: Dictionary, index: int) -> void:
	var top := _v3(f["top"])
	var foot := _v3(f["foot"])
	var width := maxf(float(f.get("width_m", 4.0)), 1.5)
	var height := maxf(top.y - foot.y, 0.5)
	var facing := deg_to_rad(float(f.get("facing_deg", 0.0)))
	var out := Vector3(sin(facing), 0.0, cos(facing))
	var sheer := str(f.get("kind", "fall")) == "fall"
	all.append([top, foot, width])
	var node := Node3D.new()
	node.name = "Fall%d" % index
	node.position = top
	add_child(node)
	# the sheet: from the lip, out along the facing and down to the foot. A fall's water leaves
	# the lip moving and arcs out (a parabola from the lip); a cascade hugs the run to the foot,
	# bulging a little over each step.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var across := out.cross(Vector3.UP).normalized()
	var run := Vector3(foot.x - top.x, 0.0, foot.z - top.z)
	var grid: Array = []
	for i in SHEET_ROWS + 1:
		var v := float(i) / float(SHEET_ROWS)
		var p: Vector3
		if sheer:
			# water leaving the lip at a steady speed: the distance out goes as the root of the drop
			var reach := run if run.length() >= 0.4 else out * 0.4
			p = reach * sqrt(v) + Vector3(0.0, -height * v, 0.0)
		else:
			p = run * v + Vector3(0.0, -height * v, 0.0) + out * 0.25 * sin(v * PI)
		var row: Array = []
		for j in SHEET_COLS + 1:
			var u := float(j) / float(SHEET_COLS)
			# the water spreads a little as it falls
			row.append(p + across * (u - 0.5) * width * (1.0 + 0.18 * v))
		grid.append(row)
	for i in SHEET_ROWS:
		for j in SHEET_COLS:
			var v0 := float(i) / SHEET_ROWS
			var v1 := float(i + 1) / SHEET_ROWS
			var u0 := float(j) / SHEET_COLS
			var u1 := float(j + 1) / SHEET_COLS
			for q in [[grid[i][j], Vector2(u0, v0)], [grid[i][j + 1], Vector2(u1, v0)], [grid[i + 1][j + 1], Vector2(u1, v1)],
					[grid[i][j], Vector2(u0, v0)], [grid[i + 1][j + 1], Vector2(u1, v1)], [grid[i + 1][j], Vector2(u0, v1)]]:
				st.set_uv(q[1])
				st.add_vertex(q[0])
	st.generate_normals()
	var sheet := MeshInstance3D.new()
	sheet.name = "Sheet"
	sheet.mesh = st.commit()
	sheet.material_override = PoiKit.falling_water(false, clampf(1.6 + 0.12 * height, 1.8, 3.4))
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.visibility_range_end = SHEET_RANGE_M
	node.add_child(sheet)
	# the white water where it lands, and on a tall fall the mist over the pool
	var landing := foot - top + out * 0.4
	node.add_child(_spray(landing, Vector3(width * 0.45, 0.2, width * 0.3), 0.6 + 0.05 * height,
			int(clampf(6.0 + width * 1.5, 8.0, 40.0)), Color(0.93, 0.95, 0.96, 0.55), 1.1 + 0.05 * width, 1.6))
	if height >= 6.0:
		node.add_child(_spray(landing + Vector3(0.0, 0.6, 0.0), Vector3(width * 0.8, 0.5, width * 0.8),
				0.35, int(clampf(height, 8.0, 30.0)), Color(0.88, 0.91, 0.93, 0.22), 2.6 + 0.08 * height, 4.5))


func _spray(at: Vector3, spread: Vector3, rise: float, amount: int, colour: Color, size: float,
		life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Spray"
	p.position = at
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.visibility_range_end = SPRAY_RANGE_M
	p.visibility_aabb = AABB(Vector3(-spread.x - size, -1.0, -spread.z - size),
			Vector3(spread.x * 2.0 + size * 2.0, spread.y + rise * life + size * 2.0 + 1.0, spread.z * 2.0 + size * 2.0))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = spread
	mat.direction = Vector3.UP
	mat.spread = 35.0
	mat.initial_velocity_min = rise * 0.6
	mat.initial_velocity_max = rise * 1.4
	mat.gravity = Vector3(0.0, -0.15, 0.0)
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(colour.r, colour.g, colour.b, 0.0))
	ramp.add_point(0.2, colour)
	ramp.set_color(1, Color(colour.r, colour.g, colour.b, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	mat.color_ramp = tex
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = _puff_texture()
	qm.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = qm
	p.draw_pass_1 = quad
	return p


static var _puff: Texture2D = null


static func _puff_texture() -> Texture2D:
	if _puff != null:
		return _puff
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_puff = t
	return _puff
