@tool
extends EditorScenePostImport
## Runs on every forge GLB (set as import_script/path in the .import sidecars).
##
## Two jobs, both from the forge contract (CONTRACTS.md §4):
##   1. materials named *_foliage become the wind shader (res://assets/shaders/foliage_wind.gdshader)
##      with the baked textures copied into its uniforms;
##   2. meshes named <mesh>_LOD1/_LOD2 are folded into the LOD0 MeshInstance3D's visibility
##      ranges instead of all rendering at once, and <name>_col meshes become collision.
##
## Everything else keeps Godot's StandardMaterial3D import, which is what the Principled-only
## materials the forge exports are meant to produce.

const FOLIAGE_SHADER := "res://assets/shaders/foliage_wind.gdshader"
const LOD1_DISTANCE := 28.0
const LOD2_DISTANCE := 75.0
const LOD_END := 260.0


func _post_import(scene: Node) -> Object:
	var by_base: Dictionary = {}
	for node in _all_mesh_instances(scene):
		_convert_materials(node)
		var base := _base_name(node.name)
		if not by_base.has(base):
			by_base[base] = {}
		by_base[base][_lod_level(node.name)] = node
	for base in by_base:
		_apply_lod_ranges(by_base[base])
	return scene


func _all_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


func _base_name(n: String) -> String:
	for suffix in ["_LOD1", "_LOD2", "_LOD3"]:
		if n.ends_with(suffix):
			return n.substr(0, n.length() - suffix.length())
	return n


func _lod_level(n: String) -> int:
	if n.ends_with("_LOD1"):
		return 1
	if n.ends_with("_LOD2"):
		return 2
	if n.ends_with("_LOD3"):
		return 3
	return 0


func _apply_lod_ranges(levels: Dictionary) -> void:
	## Godot's visibility ranges cross-fade by distance; the forge exports each level as a
	## separate mesh so we set the bands here rather than relying on auto-generated LODs.
	if levels.size() < 2:
		return
	var bands := {
		0: [0.0, LOD1_DISTANCE],
		1: [LOD1_DISTANCE, LOD2_DISTANCE],
		2: [LOD2_DISTANCE, LOD_END],
		3: [LOD_END, 0.0],
	}
	var keys: Array = levels.keys()
	keys.sort()
	var last: int = keys[keys.size() - 1]
	for level in keys:
		var mi: MeshInstance3D = levels[level]
		var band: Array = bands.get(level, [0.0, 0.0])
		mi.visibility_range_begin = float(band[0])
		mi.visibility_range_end = 0.0 if level == last else float(band[1])
		mi.visibility_range_begin_margin = maxf(float(band[0]) * 0.12, 1.0)
		mi.visibility_range_end_margin = maxf(float(band[1]) * 0.12, 1.0)
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mi.visible = true


func _convert_materials(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat == null:
			continue
		if not mat.resource_name.ends_with("_foliage") and not mat.resource_name.contains("_foliage"):
			_tune_standard(mat)
			continue
		var swapped := _make_foliage_material(mat)
		if swapped != null:
			mesh.surface_set_material(i, swapped)
			mi.set_surface_override_material(i, swapped)


func _tune_standard(mat: Material) -> void:
	if not (mat is StandardMaterial3D):
		return
	var sm := mat as StandardMaterial3D
	# The forge bakes occlusion into the ORM red channel; Godot only enables AO if told.
	if sm.ao_texture != null:
		sm.ao_enabled = true
		sm.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		sm.ao_light_affect = 0.35
	sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	sm.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX


func _make_foliage_material(src: Material) -> ShaderMaterial:
	var shader: Shader = load(FOLIAGE_SHADER) as Shader
	if shader == null:
		push_warning("glb_post_import: foliage shader missing, leaving %s as imported" % src.resource_name)
		return null
	var sm := ShaderMaterial.new()
	sm.shader = shader
	sm.resource_name = src.resource_name
	if src is StandardMaterial3D:
		var std := src as StandardMaterial3D
		sm.set_shader_parameter("albedo_texture", std.albedo_texture)
		sm.set_shader_parameter("normal_texture", std.normal_texture)
		sm.set_shader_parameter("orm_texture", std.ao_texture if std.ao_texture != null else std.roughness_texture)
		sm.set_shader_parameter("tint", std.albedo_color)
		sm.set_shader_parameter("alpha_scissor", maxf(std.alpha_scissor_threshold, 0.5))
	# Grass sways less than a tree crown; the mesh height sets the falloff.
	sm.set_shader_parameter("sway_height", 2.0)
	return sm
