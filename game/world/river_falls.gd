class_name RiverFalls
extends Node3D
## The world's falls: every fall rivers.json records (tools/world/worldgen/hydro.py find_falls),
## and the falls a waterfall place raises over its own rock where no river runs.
##
## Each is a sheet of falling water from the lip to the foot, with a looser veil of spray in front
## of it (waterfall.gdshader: streaks that stretch as the water accelerates, a green tongue at the
## lip breaking to white, ragged see-through edges, white water at the lip and the foot); a
## churning disc where it lands, over the plunge pool when the fall has one
## (plunge_pool.gdshader); white water thrown up at the foot and, on a drop of 6 m or more, mist
## hanging over it, both scaled by the height. A `cascade` (the drop less than twice the run) is
## water down a stepped face: its sheet follows the river's own carved line down the slope, a
## step of white water every couple of metres of drop. The river's ribbon stops at the lip and
## starts again at the foot (WaterSurface), so the fall is drawn once.
##
## A fall is {"top": [x, y, z], "foot": [x, y, z], "height_m", "width_m", "run_m", "facing_deg",
## "kind": "fall"|"cascade", "pool"?: {"centre", "radius_m", "depth_m"}} (docs/CONTRACTS.md 6).
##
## A waterfall place (PoiBuilders' waterfall dressing) asks `RiverFalls.near(position)` and leaves
## its water to this where a river's fall is drawn; where there is none it puts a `lip` marker
## and its own `Fall` and `Pool`, and `dress_place` draws this fall there instead of them.

const WATERFALL_SHADER := preload("res://assets/shaders/waterfall.gdshader")
const POOL_SHADER := preload("res://assets/shaders/plunge_pool.gdshader")
const SPRAY_SHADER := preload("res://assets/shaders/water_spray.gdshader")
const FALL_SOUND := "res://assets/audio/ambience/waterfall/waterfall.ogg"

## Past this the sheet is not drawn: a fall is a thread of white at a kilometre, and the far
## ring's grain is coarser than the falls.
const SHEET_RANGE_M := 900.0
const POOL_RANGE_M := 420.0
const SPRAY_RANGE_M := 220.0
## Mist a drop must have to raise (CONTRACTS 6's plunge pools start at the same height).
const MIST_FROM_M := 6.0
## The graphics setting `water_quality` (0 Low .. 3 Painted): how many particles the white water
## and the mist are drawn with, and how much of the finest streak the shaders draw.
const QUALITY_PARTICLES := [0.35, 0.65, 1.0, 1.4]
const QUALITY_DETAIL := [0.0, 0.6, 1.0, 1.0]
## How far a fall is heard, and how many are heard at once.
const HEAR_M := 260.0

## Every fall in the world as [top, foot, width], so a place can ask whether one is its own.
static var all: Array = []
## The region's water colours, for the falls places raise after the region look was set.
static var deep_colour := Color("#123239")
static var shallow_colour := Color("#3f7a6a")

var quality := 2
var _sheet_materials: Array[ShaderMaterial] = []
var _pool_materials: Array[ShaderMaterial] = []
## [GPUParticles3D, its amount at quality 1.0]
var _emitters: Array = []
var _roar: AudioStreamPlayer3D
var _hear_timer := 0.0


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


## Every river's falls as the indices of its points that each spans: [river index, first point
## at or below the lip, first point at or past the foot]. The ribbon leaves out the points in
## between, and a cascade's sheet follows them.
static func spans(entry: Dictionary) -> Array:
	var pts: Array = entry.get("points", [])
	var out: Array = []
	if pts.size() < 2:
		return out
	for f in entry.get("falls", []):
		if typeof(f) != TYPE_DICTIONARY or not f.has("top") or not f.has("foot"):
			continue
		var top := _v3(f["top"])
		var foot := _v3(f["foot"])
		var a := _nearest_point(pts, Vector2(top.x, top.z))
		var b := _nearest_point(pts, Vector2(foot.x, foot.z))
		if b < a:
			var s := a
			a = b
			b = s
		out.append([a, b])
	return out


static func _nearest_point(pts: Array, at: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in pts.size():
		var p: Array = pts[i]
		var d := Vector2(float(p[0]) - at.x, float(p[1]) - at.y).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


func _ready() -> void:
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)


func build(rivers: Array) -> int:
	all.clear()
	quality = clampi(int(Settings.get_value("graphics", "water_quality", 2)), 0, 3)
	var n := 0
	for r in rivers:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		for f in r.get("falls", []):
			if typeof(f) == TYPE_DICTIONARY and f.has("top") and f.has("foot"):
				_one(f, n, r)
				n += 1
	return n


static func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _one(f: Dictionary, index: int, river: Dictionary) -> void:
	var top := _v3(f["top"])
	var foot := _v3(f["foot"])
	var width := maxf(float(f.get("width_m", 4.0)), 1.5)
	var height := maxf(top.y - foot.y, 0.5)
	var facing := deg_to_rad(float(f.get("facing_deg", 0.0)))
	var out := Vector3(sin(facing), 0.0, cos(facing))
	var cascade := str(f.get("kind", "fall")) != "fall"
	all.append([top, foot, width])
	var node := Node3D.new()
	node.name = "Fall%d" % index
	node.position = top
	add_child(node)
	# a cascade follows the river's own carved line down the face, where the file has it
	var line := PackedVector3Array()
	if cascade:
		line = _channel_line(river, top, foot)
	var sheet := MeshInstance3D.new()
	sheet.name = "Sheet"
	sheet.mesh = sheet_mesh(Vector3.ZERO, foot - top, width, out, cascade, line)
	var mat := sheet_material(height, width, cascade, quality)
	_sheet_materials.append(mat)
	sheet.material_override = mat
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.visibility_range_end = SHEET_RANGE_M
	node.add_child(sheet)
	# where it lands: the pool when the fall has one, the river at its foot when it has not
	var pool: Dictionary = f.get("pool", {}) if typeof(f.get("pool", {})) == TYPE_DICTIONARY else {}
	var landing := foot - top
	var centre := landing + out * minf(width * 0.3, 1.5)
	var radius := clampf(width * 0.85, 2.0, 9.0)
	var depth := 0.8
	if pool.has("centre"):
		centre = _v3(pool["centre"]) - top
		radius = maxf(float(pool.get("radius_m", radius)), radius * 0.8)
		depth = float(pool.get("depth_m", 2.0))
	var disc := pool_disc(centre + Vector3(0.0, 0.03, 0.0), radius, landing, width, height, depth, not pool.has("centre"), quality)
	disc.visibility_range_end = POOL_RANGE_M
	_pool_materials.append(disc.material_override as ShaderMaterial)
	node.add_child(disc)
	for p in white_water(landing, out, width, height):
		node.add_child(p)
		_emitters.append([p, p.amount])
	apply_quality(quality)


## The river's surface line between a fall's lip and its foot, from its points: a cascade's sheet
## lies on it, so it sits in the channel the builder carved and not on a straight line across it.
## Relative to the lip. Empty when the file does not say.
static func _channel_line(river: Dictionary, top: Vector3, foot: Vector3) -> PackedVector3Array:
	var pts: Array = river.get("points", [])
	var surf: Array = river.get("surface_m", [])
	var line := PackedVector3Array()
	if pts.size() < 2 or surf.size() != pts.size():
		return line
	var a := _nearest_point(pts, Vector2(top.x, top.z))
	var b := _nearest_point(pts, Vector2(foot.x, foot.z))
	line.append(Vector3.ZERO)
	for i in range(a + 1, b):
		var p: Array = pts[i]
		var y := float(surf[i])
		if y >= top.y or y <= foot.y:
			continue
		line.append(Vector3(float(p[0]), y, float(p[1])) - top)
	line.append(foot - top)
	return line


## The falling water's mesh, from `top` to `foot` in whatever space they are given in, `width`
## across and facing `out`: two layers in one surface, the body and the veil in front of it
## (UV2.y 0 and 1), UV.y 0 at the lip and 1 at the foot, UV2.x the metres fallen.
##
## A fall leaves its lip moving and arcs out: the distance out goes as the root of the drop, eased
## toward a straight line so it keeps near its face. A cascade lies on `line` (the channel's own
## surface down the face) where it is given and the straight line where it is not, stepped: every
## couple of metres of drop a short shelf, then the break.
static func sheet_mesh(top: Vector3, foot: Vector3, width: float, out: Vector3, cascade: bool,
		line := PackedVector3Array()) -> ArrayMesh:
	var height := maxf(top.y - foot.y, 0.5)
	out = Vector3(out.x, 0.0, out.z).normalized() if Vector3(out.x, 0.0, out.z).length() > 0.01 else Vector3.FORWARD
	var run := Vector3(foot.x - top.x, 0.0, foot.z - top.z)
	var steps := clampi(roundi(height / 2.4), 1, 24) if cascade else 1
	var rows := clampi(int(height / 1.2), 10, 48)
	if cascade:
		rows = clampi(steps * 4, 10, 64)
	var cols := 6
	# the centre line, row by row
	var centre: Array[Vector3] = []
	var dirs: Array[Vector3] = []
	var poly := line if line.size() >= 2 else PackedVector3Array([top, foot])
	var poly_len := 0.0
	for i in range(1, poly.size()):
		poly_len += poly[i].distance_to(poly[i - 1])
	for i in rows + 1:
		var v := float(i) / float(rows)
		var p: Vector3
		if cascade:
			p = _along(poly, poly_len * v)
			if line.size() >= 2:
				p += top - poly[0]
			# the steps: the drop held back along each shelf, then taken at the break
			var s := v * float(steps)
			var k := floorf(s)
			var stair := (k + smoothstep(0.45, 0.85, s - k)) / float(steps)
			p.y += (v - stair) * height * 0.35
			# the water stands off the rock a little over each break
			p += out * 0.18 * sin(fposmod(s, 1.0) * PI)
		else:
			var reach := run if run.length() >= 0.4 else out * 0.4
			p = top + reach * lerpf(sqrt(v), v, 0.35) + Vector3(0.0, -height * v, 0.0)
		centre.append(p)
	for i in rows + 1:
		var a := centre[maxi(i - 1, 0)]
		var b := centre[mini(i + 1, rows)]
		var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
		dirs.append(d.normalized() if d.length() > 0.05 else out)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for layer in 2:
		var base := verts.size()
		for i in rows + 1:
			var v := float(i) / float(rows)
			var ahead: Vector3 = dirs[i]
			var across := ahead.cross(Vector3.UP).normalized()
			# the water spreads a little as it falls; the veil more, and it hangs in front
			var spread := 1.0 + (0.18 if layer == 0 else 0.45) * v
			var lift := Vector3.ZERO
			if layer == 1:
				lift = ahead * (0.35 + 0.9 * v) + Vector3.UP * 0.05
			var fallen := (top.y - centre[i].y) if not cascade else height * v
			for j in cols + 1:
				var u := float(j) / float(cols)
				verts.append(centre[i] + lift + across * (u - 0.5) * width * spread)
				uvs.append(Vector2(u, v))
				uv2s.append(Vector2(fallen, float(layer)))
				normals.append(ahead)
		for i in rows:
			for j in cols:
				var k := base + i * (cols + 1) + j
				indices.append_array([k, k + 1, k + cols + 2, k, k + cols + 2, k + cols + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The point `dist` metres along a polyline.
static func _along(poly: PackedVector3Array, dist: float) -> Vector3:
	var left := dist
	for i in range(1, poly.size()):
		var seg := poly[i].distance_to(poly[i - 1])
		if left <= seg or i == poly.size() - 1:
			return poly[i - 1].lerp(poly[i], clampf(left / maxf(seg, 0.0001), 0.0, 1.0))
		left -= seg
	return poly[poly.size() - 1]


static func sheet_material(height: float, width: float, cascade: bool, q := 2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WATERFALL_SHADER
	mat.set_shader_parameter("height_m", height)
	mat.set_shader_parameter("width_m", width)
	mat.set_shader_parameter("cascade", 1.0 if cascade else 0.0)
	mat.set_shader_parameter("steps", float(clampi(roundi(height / 2.4), 1, 24)))
	mat.set_shader_parameter("lip_speed", clampf(1.0 + width * 0.12, 1.0, 3.0))
	mat.set_shader_parameter("detail", QUALITY_DETAIL[clampi(q, 0, 3)])
	_colour_sheet(mat)
	return mat


static func _colour_sheet(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("water_colour", shallow_colour.lightened(0.15))
	mat.set_shader_parameter("deep_colour", deep_colour.lerp(shallow_colour, 0.35))


static func _colour_pool(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("deep_colour", deep_colour)
	mat.set_shader_parameter("shallow_colour", shallow_colour)


## The churning water where a fall lands: a disc of `radius` round `centre`, the water coming down
## at `impact`. `thin` (no pool under it, only the river) keeps the disc to its white water and
## lets the river show through beyond it.
static func pool_disc(centre: Vector3, radius: float, impact: Vector3, width: float, height: float,
		depth: float, thin: bool, q := 2) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 6
	var segs := 28
	var ring_pts: Array = []
	for r in rings + 1:
		var row: Array = []
		var rr := radius * float(r) / float(rings)
		for s in segs:
			var a := TAU * float(s) / float(segs)
			row.append(Vector2(sin(a), cos(a)) * rr)
		ring_pts.append(row)
	for r in rings:
		for s in segs:
			var s1 := (s + 1) % segs
			var quad: Array = [ring_pts[r][s], ring_pts[r + 1][s], ring_pts[r + 1][s1], ring_pts[r][s],
					ring_pts[r + 1][s1], ring_pts[r][s1]]
			for q2 in quad:
				var p: Vector2 = q2
				st.set_normal(Vector3.UP)
				st.set_uv(p)
				st.add_vertex(Vector3(p.x, 0.0, p.y))
	var mi := MeshInstance3D.new()
	mi.name = "Pool"
	mi.mesh = st.commit()
	mi.position = centre
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = POOL_SHADER
	var hit := impact - centre
	mat.set_shader_parameter("impact", Vector2(hit.x, hit.z))
	mat.set_shader_parameter("radius_m", radius)
	mat.set_shader_parameter("fall_width_m", width)
	mat.set_shader_parameter("depth_m", depth)
	mat.set_shader_parameter("churn", clampf(height / 30.0, 0.25, 1.0))
	mat.set_shader_parameter("detail", QUALITY_DETAIL[clampi(q, 0, 3)])
	if thin:
		mat.set_shader_parameter("opacity", 0.0)
		mat.set_shader_parameter("rim_fade", 0.6)
	_colour_pool(mat)
	mi.material_override = mat
	return mi


## The white water thrown up where a fall lands and, on a drop of MIST_FROM_M or more, the mist
## that hangs over it: both scaled by the height, their amounts at quality High (the caller
## scales them).
static func white_water(landing: Vector3, out: Vector3, width: float, height: float) -> Array[GPUParticles3D]:
	var list: Array[GPUParticles3D] = []
	var spray := _particles("Spray", landing + out * 0.4, Vector3(width * 0.45, 0.2, maxf(width * 0.25, 0.6)),
			(out * 0.35 + Vector3.UP).normalized(), 55.0, Vector2(1.6, 3.2) * (1.0 + height / 40.0), -6.0,
			int(clampf(12.0 + width * 1.4 + height * 0.5, 14.0, 72.0)), Color(0.95, 0.97, 0.98, 0.6),
			clampf(0.9 + 0.035 * height + 0.04 * width, 0.9, 3.2), 1.3)
	spray.visibility_range_end = SPRAY_RANGE_M
	list.append(spray)
	if height >= MIST_FROM_M:
		var mist_size := clampf(3.0 + 0.11 * height, 3.0, 14.0)
		var mist := _particles("Mist", landing + out * (1.0 + height * 0.04) + Vector3.UP * 0.8,
				Vector3(width * 0.8 + height * 0.05, 0.6, width * 0.6 + height * 0.05),
				(out * 0.5 + Vector3.UP).normalized(), 25.0, Vector2(0.3, 0.9) * (1.0 + height / 60.0), 0.05,
				int(clampf(8.0 + height * 0.35, 8.0, 48.0)), Color(0.9, 0.93, 0.95, 0.2), mist_size, 5.5)
		mist.visibility_range_end = clampf(SPRAY_RANGE_M + height * 1.5, SPRAY_RANGE_M, 420.0)
		list.append(mist)
	return list


static func _particles(node_name: String, at: Vector3, spread: Vector3, direction: Vector3, cone: float,
		speed: Vector2, gravity: float, amount: int, colour: Color, size: float, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.position = at
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.preprocess = life
	var reach := speed.y * life + size * 2.0 + 1.0
	p.visibility_aabb = AABB(Vector3(-spread.x - reach, -2.0, -spread.z - reach),
			Vector3(spread.x * 2.0 + reach * 2.0, spread.y + reach + 2.0, spread.z * 2.0 + reach * 2.0))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = spread
	mat.direction = direction
	mat.spread = cone
	mat.initial_velocity_min = speed.x
	mat.initial_velocity_max = speed.y
	mat.gravity = Vector3(0.0, gravity, 0.0)
	mat.damping_min = 0.4
	mat.damping_max = 1.2
	mat.scale_min = 0.6
	mat.scale_max = 1.5
	# turned every which way, so no two puffs are the same shape (the spray shader breaks each
	# one's edge by its angle)
	mat.angle_min = -180.0
	mat.angle_max = 180.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	mat.scale_curve = grow_tex
	var ramp := Gradient.new()
	ramp.set_color(0, Color(colour.r, colour.g, colour.b, 0.0))
	ramp.add_point(0.15, colour)
	ramp.set_color(1, Color(colour.r, colour.g, colour.b, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	mat.color_ramp = tex
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var qm := ShaderMaterial.new()
	qm.shader = SPRAY_SHADER
	quad.material = qm
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## The region's water colours on every fall and pool drawn here, and on those places raise later.
func set_colours(deep: Color, shallow: Color) -> void:
	deep_colour = deep
	shallow_colour = shallow
	for m in _sheet_materials:
		_colour_sheet(m)
	for m in _pool_materials:
		_colour_pool(m)


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section == "graphics" and key == "water_quality":
		apply_quality(int(value))


## Water quality, live: how many particles each fall's white water and mist are drawn with, and
## how much fine streak and ripple the shaders draw.
func apply_quality(q: int) -> void:
	quality = clampi(q, 0, 3)
	for e in _emitters:
		var p: GPUParticles3D = e[0]
		if is_instance_valid(p):
			p.amount = maxi(int(round(float(e[1]) * QUALITY_PARTICLES[quality])), 1)
	for m in _sheet_materials:
		m.set_shader_parameter("detail", QUALITY_DETAIL[quality])
	for m in _pool_materials:
		m.set_shader_parameter("detail", QUALITY_DETAIL[quality])


static func particle_scale() -> float:
	return QUALITY_PARTICLES[clampi(int(Settings.get_value("graphics", "water_quality", 2)), 0, 3)]


# --- the roar ---------------------------------------------------------------------------------

## The nearest fall is heard: one looping 3D voice on the Ambience bus, moved to whichever fall is
## nearest the camera and as loud as its height. The mixer's beds are the country's sound; this
## is the one fall in front of you.
func _process(delta: float) -> void:
	_hear_timer -= delta
	if _hear_timer > 0.0 or all.is_empty() or not is_inside_tree():
		return
	_hear_timer = 0.5
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return
	var at := cam.global_position
	var best := -1
	var best_d := HEAR_M
	for i in all.size():
		var f: Array = all[i]
		var mid: Vector3 = ((f[0] as Vector3) + (f[1] as Vector3)) * 0.5
		var d := at.distance_to(mid)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		if _roar != null and _roar.playing:
			_roar.stop()
		return
	if _roar == null:
		if not ResourceLoader.exists(FALL_SOUND):
			return
		_roar = AudioStreamPlayer3D.new()
		_roar.name = "Roar"
		_roar.stream = load(FALL_SOUND)
		_roar.bus = &"Ambience" if AudioServer.get_bus_index(&"Ambience") >= 0 else &"Master"
		_roar.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(_roar)
	var fb: Array = all[best]
	var top: Vector3 = fb[0]
	var foot: Vector3 = fb[1]
	var h := maxf(top.y - foot.y, 1.0)
	_roar.global_position = foot + Vector3.UP * minf(h * 0.3, 20.0)
	_roar.unit_size = clampf(4.0 + h * 0.25, 4.0, 30.0)
	_roar.max_distance = HEAR_M
	_roar.volume_db = clampf(-10.0 + h * 0.12, -10.0, 0.0)
	if not _roar.playing:
		_roar.play()


# --- a place's own fall -----------------------------------------------------------------------

## A waterfall place's own falls, drawn as the river's are. The dressing raises its rock and marks
## each lip with a `lip` marker (`width_m`, `drop_m`); where no river's fall is drawn it also puts
## a plain sheet (`Fall`, or `Fall0`..`Fall2` down the terraces), a `Pool` under each and puffs of
## spray. Those are hidden and freed, and in their place: this fall's sheet, reusing the `Fall`
## node (a mesh from the lip to the pool, so whatever frames the fall still finds it), its churning
## pool and its white water and mist. A dressing whose water the river draws has no `Fall` to
## replace and is left as it is, and a lip with no water under it (the Glass Falls is black glass
## the fall left behind) has none either.
static func dress_place(d: Node3D) -> int:
	var done := 0
	var puffs: Array[Node] = d.find_children("*Puffs*", "GPUParticles3D", false, false)
	for m in d.get_children():
		if not (m is Marker3D) or not str(m.name).begins_with("lip"):
			continue
		var tier := str(m.name).trim_prefix("lip")
		var fall := d.get_node_or_null("Fall" + tier) as MeshInstance3D
		if fall == null or not (fall.material_override is ShaderMaterial):
			continue
		var glass: Variant = (fall.material_override as ShaderMaterial).get_shader_parameter("glass")
		if glass != null and float(glass) > 0.5:
			continue
		var pool := d.get_node_or_null("Pool" + tier) as MeshInstance3D
		var lip: Vector3 = (m as Marker3D).position
		var width := float(m.get_meta("width_m", 4.0))
		var drop := float(m.get_meta("drop_m", 6.0))
		var foot_y := lip.y - drop
		var pool_c := lip
		var pool_r := maxf(width * 0.8, 2.0)
		if pool != null and pool.mesh != null:
			var box := pool.mesh.get_aabb()
			pool_c = pool.position + box.get_center()
			foot_y = pool_c.y
			pool_r = maxf(box.size.x, box.size.z) * 0.5
		var out := Vector3(pool_c.x - lip.x, 0.0, pool_c.z - lip.z)
		var dist := out.length()
		out = out / dist if dist > 0.05 else Vector3.BACK
		if pool == null:
			pool_c = lip + out * maxf(width * 0.6, 2.0)
			pool_c.y = foot_y
		var height := maxf(lip.y - foot_y, 0.5)
		var foot := Vector3(lip.x, foot_y, lip.z) + out * maxf(dist - pool_r * 0.5, 0.8)
		# the dressing's own sheet, pool and spray, gone: this draws them
		fall.mesh = sheet_mesh(lip, foot, width, out, false)
		fall.material_override = sheet_material(height, width, false,
				clampi(int(Settings.get_value("graphics", "water_quality", 2)), 0, 3))
		fall.visibility_range_end = SHEET_RANGE_M
		if pool != null:
			pool.visible = false
			pool.queue_free()
			pool.name = "PoolReplaced" + tier
		var disc := pool_disc(Vector3(pool_c.x, foot_y + 0.04, pool_c.z), maxf(pool_r, width * 0.8), foot, width,
				height, 1.6, false, clampi(int(Settings.get_value("graphics", "water_quality", 2)), 0, 3))
		disc.name = "Pool" + tier
		disc.visibility_range_end = POOL_RANGE_M
		d.add_child(disc)
		for p in puffs:
			if is_instance_valid(p) and (p as Node3D).position.distance_to(pool_c) < pool_r + 4.0:
				(p as Node3D).visible = false
				p.queue_free()
		var many := particle_scale()
		for p in white_water(foot, out, width, height):
			p.amount = maxi(int(round(float(p.amount) * many)), 1)
			p.name = str(p.name) + tier
			d.add_child(p)
		done += 1
	return done
