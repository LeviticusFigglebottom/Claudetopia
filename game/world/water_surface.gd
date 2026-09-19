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

## Region look: deep colour, shallow colour, and how quickly depth reads as deep.
const REGION_WATER := {
	"core:region/brightwater": {"deep": "#12405f", "shallow": "#4d93a8", "fade": 6.5},
	"core:region/sedgemire": {"deep": "#14322f", "shallow": "#3f7f72", "fade": 2.2},
	"core:region/hearthvale": {"deep": "#1b4a52", "shallow": "#5a9a86", "fade": 3.0},
	"core:region/briarwold": {"deep": "#12301f", "shallow": "#3f6f4a", "fade": 3.0},
	"core:region/skerrow": {"deep": "#1b3550", "shallow": "#5c8fae", "fade": 4.0},
	"core:region/cinderlea": {"deep": "#25292c", "shallow": "#5c6a70", "fade": 3.0},
}

@export var sheet_subdivisions: int = 96

var provider: TerrainProvider
var sheet: MeshInstance3D
var rivers_root: Node3D
var _sheet_material: ShaderMaterial
var _river_materials: Array[ShaderMaterial] = []
var _level_tex: ImageTexture
var _mask_tex: ImageTexture
var _height_tex: ImageTexture


func build(p: TerrainProvider) -> void:
	provider = p
	if provider == null:
		return
	_build_textures()
	_build_sheet()
	_build_rivers()
	set_region_look(GameState.current_region_id)


func _build_textures() -> void:
	var rt: Dictionary = provider.manifest.get("runtime", {})
	var n := int(rt.get("grid", 1024))
	_level_tex = _texture_rf("%s/%s" % [GENERATED, rt.get("water_level", "")], n)
	_height_tex = _texture_rf("%s/%s" % [GENERATED, rt.get("heights", "")], n)
	_mask_tex = _texture_r8("%s/%s" % [GENERATED, rt.get("water", "")], n)


func _texture_rf(path: String, n: int) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < n * n * 4:
		Log.error("WaterSurface", "cannot read %s" % path)
		return null
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, bytes)
	return ImageTexture.create_from_image(img)


func _texture_r8(path: String, n: int) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < n * n:
		Log.error("WaterSurface", "cannot read %s" % path)
		return null
	var img := Image.create_from_data(n, n, false, Image.FORMAT_R8, bytes)
	return ImageTexture.create_from_image(img)


func _make_material(follow_level: bool, use_mask: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("level_tex", _level_tex)
	mat.set_shader_parameter("mask_tex", _mask_tex)
	mat.set_shader_parameter("height_tex", _height_tex)
	mat.set_shader_parameter("world_origin", provider.origin)
	mat.set_shader_parameter("world_size", provider.size_m)
	mat.set_shader_parameter("follow_level", follow_level)
	mat.set_shader_parameter("use_mask", use_mask)
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
		if provider != null:
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
		if mat == _sheet_material:
			mat.set_shader_parameter("depth_fade_m", fade)


func _all_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if _sheet_material:
		out.append(_sheet_material)
	out.append_array(_river_materials)
	return out
