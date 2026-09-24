class_name WaterSurface
extends Node3D
## The Mere, the Grey Sea, the marsh pools and the rivers, as stylised surfaces.
##
## One subdivided sheet covers the whole world and takes its height from the builder's water
## level map, discarding wherever the water mask says there is no water; the rivers are ribbon
## meshes built from rivers.json, which carries each river's own falling surface profile.
## Region tinting comes from the region palettes, so the Mere is not the same blue as the sea.

const SHADER := preload("res://assets/shaders/painted_water.gdshader")
const GENERATED := "res://world/generated"

## Region look: deep colour, shallow colour, how quickly depth reads as deep, how much of the
## world the surface mirrors (`reflect`, and `cap`, the most it gives back at the grazing angle),
## how hard the sun glitters on it, how rough the open water is (`waves`, the lake and the sea
## only; a river keeps its own), and how much foam its edges raise (`foam`). The Mere is Lake
## Glass: calm enough that the island and the far shore stand in it upside down, with the
## glittering path WORLD_BIBLE 6.2 asks for; the marsh's pools are still and brown, give back
## little and raise no surf (they are shallower than the foam band everywhere, and at the sea's
## foam the whole Sedgemire was white); the Grey Sea stays rough.
const REGION_WATER := {
	"core:region/brightwater": {"deep": "#09243c", "shallow": "#2d6a86", "fade": 5.0, "reflect": 0.9, "cap": 0.85, "glint": 4.0, "waves": 0.14, "foam": 0.5},
	"core:region/sedgemire": {"deep": "#0c221f", "shallow": "#2b5f55", "fade": 2.0, "reflect": 0.5, "cap": 0.65, "glint": 1.2, "waves": 0.12, "foam": 0.08},
	"core:region/hearthvale": {"deep": "#123239", "shallow": "#3f7a6a", "fade": 2.6, "reflect": 0.85, "cap": 0.7, "glint": 3.0, "waves": 0.3, "foam": 0.5},
	"core:region/briarwold": {"deep": "#0b2016", "shallow": "#2b5236", "fade": 2.6, "reflect": 0.7, "cap": 0.65, "glint": 2.0, "waves": 0.2, "foam": 0.3},
	"core:region/skerrow": {"deep": "#111f33", "shallow": "#3d6b8c", "fade": 3.4, "reflect": 0.9, "cap": 0.65, "glint": 3.5, "waves": 0.42, "foam": 0.8},
	"core:region/cinderlea": {"deep": "#16191b", "shallow": "#3f4a50", "fade": 2.6, "reflect": 0.6, "cap": 0.6, "glint": 1.5, "waves": 0.25, "foam": 0.4},
}

@export var sheet_subdivisions: int = 96

## The graphics setting `water_quality` (0 Low .. 3 Painted): how finely the sheet is cut, which
## is what the swell and the depth colour have to interpolate over, and how much of the finest
## ripple layer the shader draws. High (2) is the water as it was built.
const QUALITY_SUBDIVISIONS := [48, 64, 96, 160]
const QUALITY_DETAIL := [0.0, 0.6, 1.0, 1.0]
var quality := 2

var provider: TerrainProvider
var sheet: MeshInstance3D
var skirt: MeshInstance3D
var rivers_root: Node3D
var _sheet_material: ShaderMaterial
var _skirt_material: ShaderMaterial
var _river_materials: Array[ShaderMaterial] = []
var _level_tex: ImageTexture
var _mask_tex: ImageTexture
var _height_tex: ImageTexture

static var _unmirrored: Shader = null


## The water shader, with the mirror or without it. Without it is the same code built with
## WATER_NO_MIRROR defined, so the screen texture is never named: a material that names it makes
## the renderer copy the frame before the water is drawn, whatever its `mirror` uniform says, and
## the setting that turns reflections off is there to save that copy.
static func shader_for(mirrored: bool) -> Shader:
	if mirrored:
		return SHADER
	if _unmirrored == null:
		_unmirrored = Shader.new()
		_unmirrored.code = SHADER.code.replace("shader_type spatial;", "shader_type spatial;\n#define WATER_NO_MIRROR")
	return _unmirrored


func _ready() -> void:
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)


## Puts every water material on the shader `graphics/water_reflections` asks for, keeping what
## the region look and the builder set on it.
func apply_reflections() -> void:
	var mirrored := bool(Settings.get_value("graphics", "water_reflections", true))
	var shader := shader_for(mirrored)
	for mat in _all_materials():
		if mat.shader != shader:
			var keep := {}
			if mat.shader != null:
				for u in mat.shader.get_shader_uniform_list():
					keep[str(u["name"])] = mat.get_shader_parameter(str(u["name"]))
			mat.shader = shader
			for k in keep:
				if keep[k] != null:
					mat.set_shader_parameter(k, keep[k])
		mat.set_shader_parameter("mirror", 1.0 if mirrored else 0.0)


func build(p: TerrainProvider) -> void:
	provider = p
	if provider == null:
		return
	quality = clampi(int(Settings.get_value("graphics", "water_quality", 2)), 0, 3)
	sheet_subdivisions = QUALITY_SUBDIVISIONS[quality]
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	_build_textures()
	_build_sheet()
	_build_skirt()
	_build_rivers()
	set_region_look(GameState.current_region_id)
	var skirt_aabb := skirt.get_aabb() if skirt else AABB()
	Log.info("WaterSurface", "sheet %.0f m, sea skirt %.0f m (%d verts), %d rivers, sea level %.1f m"
		% [provider.size_m + 512.0, skirt_aabb.size.x, 0 if skirt == null else skirt.mesh.get_faces().size(),
			_river_materials.size(), provider.sea_level])


func _build_textures() -> void:
	var rt: Dictionary = provider.manifest.get("runtime", {})
	var n := int(rt.get("grid", 1024))
	_level_tex = _texture_rf("%s/%s" % [GENERATED, rt.get("water_level", "")], n)
	_height_tex = _texture_rf("%s/%s" % [GENERATED, rt.get("heights", "")], n)
	_mask_tex = _mask_texture(mask_path(provider.manifest), n)


func _texture_rf(path: String, n: int) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < n * n * 4:
		Log.error("WaterSurface", "cannot read %s" % path)
		return null
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, bytes)
	return ImageTexture.create_from_image(img)


func _mask_texture(path: String, n: int) -> ImageTexture:
	var img := mask_image(path, n)
	if img == null:
		Log.error("WaterSurface", "cannot read %s" % path)
		return null
	return ImageTexture.create_from_image(img)


## Where the water mask the game loads lives, from the world manifest.
static func mask_path(manifest: Dictionary) -> String:
	var rt: Dictionary = manifest.get("runtime", {})
	return "%s/%s" % [GENERATED, rt.get("water", "")]


## The water mask exactly as the shader will sample it (see `mask_bytes`), or null if it cannot
## be read. The water shader discards wherever this is under 0.5.
static func mask_image(path: String, n: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < n * n:
		return null
	return Image.create_from_data(n, n, false, Image.FORMAT_R8, mask_bytes(bytes))


## The water mask as the shader reads it: 0 dry, 255 wet. The world builder writes it as 0 and 1,
## and an R8 texture reads a byte as byte/255, so a wet texel was 0.004 to the shader -- under its
## 0.5 test everywhere. Every lake and the sea were discarded, from the first runtime world on, and
## what the camera saw on the Mere was the lake bed's own terrain texture under no water at all:
## the water shader's reflections, glints and colours never reached a frame outside the rivers.
## Stretched to 255, the mask's linear filter still puts the waterline midway between a wet texel
## and a dry one. A mask already written as 0 and 255 is left as it is.
static func mask_bytes(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.has(255) or not bytes.has(1):
		return bytes
	var out := bytes.duplicate()
	for i in out.size():
		if out[i] != 0:
			out[i] = 255
	return out


func _make_material(follow_level: bool, use_mask: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var mirrored := bool(Settings.get_value("graphics", "water_reflections", true))
	mat.shader = shader_for(mirrored)
	mat.set_shader_parameter("level_tex", _level_tex)
	mat.set_shader_parameter("mask_tex", _mask_tex)
	mat.set_shader_parameter("height_tex", _height_tex)
	mat.set_shader_parameter("world_origin", provider.origin)
	mat.set_shader_parameter("world_size", provider.size_m)
	mat.set_shader_parameter("follow_level", follow_level)
	mat.set_shader_parameter("use_mask", use_mask)
	mat.set_shader_parameter("detail", QUALITY_DETAIL[quality])
	# the lake gives back the far shore and the hills; a machine that cannot spare the frame copy
	# the lookup needs can turn it off, and the water keeps the sky's own colours
	mat.set_shader_parameter("mirror", 1.0 if mirrored else 0.0)
	return mat


func _build_sheet() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(provider.size_m + 512.0, provider.size_m + 512.0)
	mesh.subdivide_width = sheet_subdivisions
	mesh.subdivide_depth = sheet_subdivisions
	sheet = MeshInstance3D.new()
	sheet.name = "WaterSheet"
	sheet.mesh = mesh
	sheet.position = Vector3.ZERO
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the sheet spans the world, so its own bounds must not cull it when the camera is inside
	sheet.extra_cull_margin = provider.size_m
	_sheet_material = _make_material(true, true)
	sheet.material_override = _sheet_material
	add_child(sheet)


## The Grey Sea runs to the horizon, not to the edge of the heightmap.
##
## The sheet stops where the world does, so from any hill the far edge of the ocean was a
## straight grey bar with sky under it. This is a flat ring of water outside the world, at sea
## level, big enough that its own edge is over the horizon. The shader's maps are sampled with
## clamp-to-edge, so a skirt texel takes the mask, level and ground height of the nearest world
## edge texel: it is water exactly where the coast is water, and discards where the world ends
## in land (the mountain wall north, the cliffs south).
func _build_skirt() -> void:
	var r_in := (provider.size_m + 512.0) * 0.5
	var r_out := provider.size_m * 6.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# eight pieces: four sides and four corners, each subdivided so distance fog has something
	# to interpolate over
	var bands: Array = [
		[-r_out, -r_out, -r_in, -r_in], [-r_in, -r_out, r_in, -r_in], [r_in, -r_out, r_out, -r_in],
		[-r_out, -r_in, -r_in, r_in], [r_in, -r_in, r_out, r_in],
		[-r_out, r_in, -r_in, r_out], [-r_in, r_in, r_in, r_out], [r_in, r_in, r_out, r_out],
	]
	for b in bands:
		_add_quad(st, float(b[0]), float(b[1]), float(b[2]), float(b[3]), 6)
	skirt = MeshInstance3D.new()
	skirt.name = "SeaSkirt"
	skirt.mesh = st.commit()
	skirt.position = Vector3(0.0, provider.sea_level, 0.0)
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skirt.extra_cull_margin = r_out
	_skirt_material = _make_material(false, true)
	skirt.material_override = _skirt_material
	add_child(skirt)


func _add_quad(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, steps: int) -> void:
	for i in steps:
		for j in steps:
			var ax := lerpf(x0, x1, float(i) / float(steps))
			var bx := lerpf(x0, x1, float(i + 1) / float(steps))
			var az := lerpf(z0, z1, float(j) / float(steps))
			var bz := lerpf(z0, z1, float(j + 1) / float(steps))
			for corner in [[ax, az], [ax, bz], [bx, bz], [ax, az], [bx, bz], [bx, az]]:
				# the shader culls nothing, so the winding does not matter, but the normal
				# does: a generated one could come out pointing at the sea bed
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(float(corner[0]), float(corner[1])))
				st.add_vertex(Vector3(float(corner[0]), 0.0, float(corner[1])))


func _build_rivers() -> void:
	rivers_root = Node3D.new()
	rivers_root.name = "Rivers"
	add_child(rivers_root)
	var path := "%s/rivers.json" % GENERATED
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		return
	for entry in parsed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var mesh := _river_mesh(entry)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = str(entry.get("id", "river")).get_file()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _make_material(false, false)
		mat.set_shader_parameter("depth_fade_m", 1.6)
		mat.set_shader_parameter("foam_width_m", 0.8)
		mat.set_shader_parameter("wave_scale", 0.35)
		mat.set_shader_parameter("wave_speed", 1.1)
		mat.set_shader_parameter("opacity_shallow", 0.5)
		mat.set_shader_parameter("opacity_deep", 0.8)
		mat.set_shader_parameter("flow_along_uv", true)
		# steeper rivers run faster: the Skerrow water drops far more than the Mere's outflow
		var drop := absf(float(entry.get("surface_from_m", 0.0)) - float(entry.get("surface_to_m", 0.0)))
		mat.set_shader_parameter("flow_speed", clampf(0.25 + drop * 0.002, 0.25, 0.9))
		mi.material_override = mat
		_river_materials.append(mat)
		rivers_root.add_child(mi)


## A ribbon along the river's centre line at its own (falling) water surface.
func _river_mesh(entry: Dictionary) -> ArrayMesh:
	var pts: Array = entry.get("points", [])
	if pts.size() < 2:
		return null
	var w_from := float(entry.get("width_from_m", entry.get("width_m", 6.0)))
	var w_to := float(entry.get("width_to_m", entry.get("width_m", 6.0)))
	var s_from := float(entry.get("surface_from_m", 0.0))
	var s_to := float(entry.get("surface_to_m", 0.0))
	# the builder's own surface at every point (CONTRACTS 6), where the file has it
	var surface: Array = entry.get("surface_m", [])
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var count := pts.size()
	for i in count:
		var t := float(i) / float(count - 1)
		var p: Array = pts[i]
		var here := Vector2(float(p[0]), float(p[1]))
		var prev: Vector2 = here
		var next: Vector2 = here
		if i > 0:
			var pp: Array = pts[i - 1]
			prev = Vector2(float(pp[0]), float(pp[1]))
		if i < count - 1:
			var np: Array = pts[i + 1]
			next = Vector2(float(np[0]), float(np[1]))
		var dir := (next - prev)
		if dir.length_squared() < 0.0001:
			dir = Vector2(1.0, 0.0)
		dir = dir.normalized()
		var side := Vector2(-dir.y, dir.x)
		var half: float = lerpf(w_from, w_to, pow(t, 0.7)) * 0.5 + 0.35
		# the surface follows the river's own profile; a touch below the banks it cut
		var y: float = lerpf(s_from, s_to, t) + 0.05
		if surface.size() == count:
			# A mountain river falls in its gorge and runs level across its plain; a straight
			# ramp between its two ends stood the Skerrow Water 158 m over the dales.
			y = float(surface[i]) + 0.05
		elif provider != null:
			y = maxf(provider.nearest_water_level(here.x, here.y), y - 0.35)
		var a := here - side * half
		var b := here + side * half
		verts.append(Vector3(a.x, y, a.y))
		verts.append(Vector3(b.x, y, b.y))
		uvs.append(Vector2(0.0, t * 40.0))
		uvs.append(Vector2(1.0, t * 40.0))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		if i < count - 1:
			var k := i * 2
			indices.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Tints every water surface for the region the camera is in.
func set_region_look(region_id: String) -> void:
	var look: Dictionary = REGION_WATER.get(region_id, REGION_WATER["core:region/brightwater"])
	var deep := Color.html(str(look["deep"]))
	var shallow := Color.html(str(look["shallow"]))
	var fade := float(look.get("fade", 5.0))
	for mat in _all_materials():
		mat.set_shader_parameter("deep_colour", deep)
		mat.set_shader_parameter("shallow_colour", shallow)
		mat.set_shader_parameter("reflect_strength", float(look.get("reflect", 0.85)))
		mat.set_shader_parameter("fresnel_cap", float(look.get("cap", 0.65)))
		mat.set_shader_parameter("glint_strength", float(look.get("glint", 3.0)))
		mat.set_shader_parameter("foam_strength", float(look.get("foam", 0.7)))
		if mat == _sheet_material or mat == _skirt_material:
			mat.set_shader_parameter("depth_fade_m", fade)
			mat.set_shader_parameter("wave_strength", float(look.get("waves", 0.42)))


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section != "graphics":
		return
	if key == "water_quality":
		apply_quality(int(value))
	elif key == "water_reflections":
		apply_reflections()


## Water quality, live: the sheet re-cut to its new subdivision and every surface's ripple
## detail set. Nothing else is rebuilt.
func apply_quality(q: int) -> void:
	quality = clampi(q, 0, 3)
	sheet_subdivisions = QUALITY_SUBDIVISIONS[quality]
	if sheet != null and sheet.mesh is PlaneMesh:
		(sheet.mesh as PlaneMesh).subdivide_width = sheet_subdivisions
		(sheet.mesh as PlaneMesh).subdivide_depth = sheet_subdivisions
	for mat in _all_materials():
		mat.set_shader_parameter("detail", QUALITY_DETAIL[quality])


func _all_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if _sheet_material:
		out.append(_sheet_material)
	if _skirt_material:
		out.append(_skirt_material)
	out.append_array(_river_materials)
	return out
