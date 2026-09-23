@tool
extends EditorScenePostImport
## Runs on every forge GLB (set as import_script/path in the .import sidecars).
##
## Three jobs, all from the forge contract (CONTRACTS.md §4):
##   1. materials named *_foliage become the wind shader (res://assets/shaders/foliage_wind.gdshader)
##      with the baked textures copied into its uniforms;
##   2. meshes named <mesh>_LOD1/_LOD2 are folded into the LOD0 MeshInstance3D's visibility
##      ranges instead of all rendering at once, and <name>_col meshes become collision;
##   3. a tree's LOD2, whose material is named *_impostor (tools/forge/gen_impostors.py), becomes
##      the billboard (res://assets/shaders/tree_impostor.gdshader) with the frame and the normal
##      atlas the tree's meta.json records under "impostor", and a culling box it can turn in.
##
## Everything else keeps Godot's StandardMaterial3D import, which is what the Principled-only
## materials the forge exports are meant to produce.

const FOLIAGE_SHADER := "res://assets/shaders/foliage_wind.gdshader"
const IMPOSTOR_SHADER := "res://assets/shaders/tree_impostor.gdshader"
const LOD1_DISTANCE := 28.0
const LOD2_DISTANCE := 75.0
const LOD_END := 260.0
## A tree's own bands when a scene of it is instanced whole (a point of interest's hawthorn or
## yew), sized by its height the way world/scatter_lod.gd sizes the scattered ones at a level of
## detail bias of one: the mid level from four heights away or 50 m, the impostor from ten or
## 70 m. Kept in step with ScatterLod.NEAR_MIN/NEAR_PER_METRE/FAR_MIN/FAR_PER_METRE by hand; an
## import script is no place to lean on runtime classes.
const TREE_LOD1_MIN := 50.0
const TREE_LOD1_PER_M := 4.0
const TREE_LOD2_MIN := 70.0
const TREE_LOD2_PER_M := 10.0

var _impostor: Dictionary = {}
var _height := 0.0
var _source_dir := ""


## Only the categories the world scatters from MultiMeshes may take their albedo from the
## instance colour. The cave forge bakes its cavity shading into vertex colours
## (tools/interiors/cave_forge.py), so switching this on for everything would multiply that
## shading into the albedo of every interior in the game -- a change to somebody else's work,
## made by accident, in the dark.
const INSTANCE_TINTED := ["/models/props/", "/models/rocks/", "/models/trees/", "/models/flora/"]

var _instance_tinted := false


func _post_import(scene: Node) -> Object:
	var source := get_source_file()
	_instance_tinted = false
	for prefix in INSTANCE_TINTED:
		if source.contains(prefix):
			_instance_tinted = true
			break
	_source_dir = source.get_base_dir()
	_impostor = {}
	_height = 0.0
	var meta_path := source.get_basename() + ".meta.json"
	if FileAccess.file_exists(meta_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_impostor = (parsed as Dictionary).get("impostor", {})
			_height = float((parsed as Dictionary).get("bounds", {}).get("height", 0.0))
	var meshes := _all_mesh_instances(scene)
	var names: Dictionary = {}
	for node in meshes:
		names[str(node.name)] = true
	var by_base: Dictionary = {}
	for node in meshes:
		_convert_materials(node)
		var base := _base_name(node.name, names)
		if not by_base.has(base):
			by_base[base] = {}
		var level := _lod_level(node.name)
		if not by_base[base].has(level):
			by_base[base][level] = []
		(by_base[base][level] as Array).append(node)
	for base in by_base:
		_apply_lod_ranges(by_base[base], source.contains("/models/trees/") and not _impostor.is_empty())
	return scene


func _all_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


## The LOD group a mesh belongs to. A tree's canopy cards at LOD1 are `<tree>_cards_LOD1`, and
## taking the suffix off left `<tree>_cards`, a group of one with no bands at all -- so a tree
## instanced whole drew its LOD1 canopy over its LOD0 one at every distance. A grass clump's
## LOD0 really is `<clump>_cards`, which is why the `_cards` is only dropped when no mesh of that
## name exists.
func _base_name(n: String, names: Dictionary = {}) -> String:
	for suffix in ["_LOD1", "_LOD2", "_LOD3"]:
		if n.ends_with(suffix):
			var base := n.substr(0, n.length() - suffix.length())
			if base.ends_with("_cards") and not names.has(base):
				return base.substr(0, base.length() - "_cards".length())
			return base
	return n


func _lod_level(n: String) -> int:
	if n.ends_with("_LOD1"):
		return 1
	if n.ends_with("_LOD2"):
		return 2
	if n.ends_with("_LOD3"):
		return 3
	return 0


func _apply_lod_ranges(levels: Dictionary, tree: bool = false) -> void:
	## Godot's visibility ranges cross-fade by distance; the forge exports each level as a
	## separate mesh so we set the bands here rather than relying on auto-generated LODs.
	if levels.size() < 2:
		return
	var lod1 := LOD1_DISTANCE
	var lod2 := LOD2_DISTANCE
	if tree and _height > 0.0:
		lod1 = maxf(TREE_LOD1_MIN, TREE_LOD1_PER_M * _height)
		lod2 = maxf(TREE_LOD2_MIN, TREE_LOD2_PER_M * _height)
	var bands := {
		0: [0.0, lod1],
		1: [lod1, lod2],
		2: [lod2, LOD_END],
		3: [LOD_END, 0.0],
	}
	var keys: Array = levels.keys()
	keys.sort()
	var last: int = keys[keys.size() - 1]
	for level in keys:
		var band: Array = bands.get(level, [0.0, 0.0])
		for node in levels[level]:
			var mi: MeshInstance3D = node
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
		if mat.resource_name.ends_with("_impostor") and not _impostor.is_empty():
			var billboard := _make_impostor_material(mat)
			if billboard != null:
				mesh.surface_set_material(i, billboard)
				mi.set_surface_override_material(i, billboard)
				_impostor_bounds(mesh)
			continue
		if not mat.resource_name.ends_with("_foliage") and not mat.resource_name.contains("_foliage"):
			_tune_standard(mat)
			continue
		var swapped := _make_foliage_material(mat)
		if swapped != null:
			mesh.surface_set_material(i, swapped)
			mi.set_surface_override_material(i, swapped)


func _make_impostor_material(src: Material) -> ShaderMaterial:
	var shader: Shader = load(IMPOSTOR_SHADER) as Shader
	if shader == null:
		push_warning("glb_post_import: impostor shader missing, leaving %s as imported" % src.resource_name)
		return null
	var sm := ShaderMaterial.new()
	sm.shader = shader
	sm.resource_name = src.resource_name
	if src is StandardMaterial3D:
		sm.set_shader_parameter("albedo_atlas", (src as StandardMaterial3D).albedo_texture)
	var nrm_path := _source_dir.path_join(str(_impostor.get("normal", "")))
	if ResourceLoader.exists(nrm_path):
		sm.set_shader_parameter("normal_atlas", load(nrm_path))
	else:
		push_warning("glb_post_import: impostor normal atlas missing: %s" % nrm_path)
	var axis: Array = _impostor.get("axis", [0.0, 0.0])
	sm.set_shader_parameter("frame_axis", Vector2(float(axis[0]), float(axis[1])))
	sm.set_shader_parameter("views", int(_impostor.get("views", 8)))
	sm.set_shader_parameter("grid", int(_impostor.get("grid", 3)))
	return sm


## The quad is authored flat, facing +Z; the billboard turns it about the trunk, so the box it
## is culled by has to hold it at every turn.
func _impostor_bounds(mesh: Mesh) -> void:
	var box := mesh.get_aabb()
	var axis: Array = _impostor.get("axis", [0.0, 0.0])
	var half := box.size.x * 0.5
	mesh.custom_aabb = AABB(Vector3(float(axis[0]) - half, box.position.y, float(axis[1]) - half),
			Vector3(box.size.x, box.size.y, box.size.x))


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
	# Rocks, stumps and the rest of the scattered opaque assets are drawn from MultiMeshes
	# that carry a per-instance tint (worldgen/cells.py), and a StandardMaterial3D ignores it
	# unless it is told to use the vertex colour. No gen_* generator bakes a colour attribute
	# into a mesh, so for anything of theirs not in a MultiMesh this reads as white and
	# changes nothing -- but the cave forge does bake one, hence the category check.
	sm.vertex_color_use_as_albedo = _instance_tinted


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
