class_name MaterialCensus
extends Node
## Every material the running game draws with, gathered while it runs and written as a warm set
## (ShaderWarmSet, `res://assets/shader_warm/warm_set.tres`) the export's shader baker compiles
## ahead of time, so a first launch on a machine with an empty shader cache compiles nothing the
## census saw (docs/FIRST_LAUNCH.md).
##
##   godot ... -- --material-census=<file.tres>     (any run: the Debug autoload attaches this)
##
## The file is added to, never replaced: several runs pointed at one file make one set. A material
## is kept once per feature key (`key_of`): its class, every stored bool and enum or int, which
## texture slots are set, and for a ShaderMaterial its shader's file or a hash of its code; never
## its colours, floats or vectors, which are uniforms and do not change the shader. Terrain3D's
## shader is taken from the rendering server as code (only a drawn run can; headless gives none).
## `./run.sh shader-warm` runs the census over the title, the smoke, the flow, the fights and the
## journey and writes the set.

const DEFAULT_OUT := "res://assets/shader_warm/warm_set.tres"
## Real seconds between walks of the whole tree (a node's material can change after it is added).
const WALK_S := 3.0
## Real seconds between writes while something new has been seen.
const FLUSH_S := 10.0
## Properties that are stored but do not change a material's shader.
const SKIP_PROPS := ["render_priority", "next_pass", "resource_local_to_scene", "resource_name",
		"resource_path", "resource_scene_unique_id", "script"]

var out_path := DEFAULT_OUT

var _set: ShaderWarmSet = null
var _by_key: Dictionary = {}          # key -> index in _set.materials
var _queue: Array[Node] = []
var _last_walk_ms := 0
var _last_flush_ms := 0
var _dirty := false
var _added := 0

static var _placeholders: Dictionary = {}


# --- the key --------------------------------------------------------------------------------------

## What decides a material's shader, as a string; "" for one that has none to bake.
static func key_of(m: Material) -> String:
	if m == null:
		return ""
	var parts: PackedStringArray = [m.get_class()]
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		if sh == null:
			return ""
		parts.append(sh.resource_path if _is_file(sh.resource_path) else "code:%s" % sh.code.md5_text())
		return "|".join(parts)
	for p: Dictionary in m.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE):
			continue
		var n := str(p["name"])
		if n in SKIP_PROPS:
			continue
		match int(p["type"]):
			TYPE_BOOL, TYPE_INT:
				parts.append("%s=%s" % [n, str(m.get(n))])
			TYPE_OBJECT:
				var v: Variant = m.get(n)
				if v is Texture or str(p.get("hint_string", "")).contains("Texture"):
					parts.append("%s=%s" % [n, "1" if v != null else "0"])
	return "|".join(parts)


## A key for a shader known only by its code (Terrain3D's, from the rendering server).
static func code_key(code: String) -> String:
	return "ShaderMaterial|code:%s" % code.md5_text()


static func _is_file(path: String) -> bool:
	return not path.is_empty() and not path.contains("::")


# --- what a node draws with -----------------------------------------------------------------------

## Every material `node` draws with (not its next passes: `_add` follows those).
static func materials_of(node: Node) -> Array[Material]:
	var out: Array[Material] = []
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		_push(out, gi.material_override)
		_push(out, gi.material_overlay)
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					_push(out, mi.get_surface_override_material(i))
			_mesh_materials(out, mi.mesh)
		elif node is MultiMeshInstance3D:
			var mm := (node as MultiMeshInstance3D).multimesh
			if mm != null:
				_mesh_materials(out, mm.mesh)
		elif node is GPUParticles3D:
			var gp := node as GPUParticles3D
			_push(out, gp.process_material)
			for i in gp.draw_passes:
				_mesh_materials(out, gp.get_draw_pass_mesh(i))
		elif node is CPUParticles3D:
			_mesh_materials(out, (node as CPUParticles3D).mesh)
		elif node is CSGPrimitive3D:
			_push(out, node.get("material") as Material)
		if (node is Label3D or node is SpriteBase3D) and gi.material_override == null:
			_push(out, material_for_2d(node))
	elif node is FogVolume:
		_push(out, (node as FogVolume).material)
	if node is CanvasItem:
		_push(out, (node as CanvasItem).material)
		if node is GPUParticles2D:
			_push(out, (node as GPUParticles2D).process_material)
	if node is WorldEnvironment:
		_env_materials(out, (node as WorldEnvironment).environment)
	elif node is Camera3D:
		_env_materials(out, (node as Camera3D).environment)
	return out


static func _push(out: Array[Material], m: Material) -> void:
	if m != null:
		out.append(m)


static func _mesh_materials(out: Array[Material], mesh: Mesh) -> void:
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		_push(out, mesh.surface_get_material(i))


static func _env_materials(out: Array[Material], env: Environment) -> void:
	if env != null and env.sky != null:
		_push(out, env.sky.sky_material)


## The material Godot makes inside a Label3D or Sprite3D with no override
## (BaseMaterial3D.get_material_for_2d): not reachable from a script, so made again from its flags.
static func material_for_2d(node: Node) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var shaded := bool(node.get("shaded"))
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if shaded else BaseMaterial3D.SHADING_MODE_UNSHADED
	match int(node.get("alpha_cut")):
		1: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		2: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		3: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		_: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED if bool(node.get("double_sided")) else BaseMaterial3D.CULL_BACK
	m.vertex_color_is_srgb = true
	m.vertex_color_use_as_albedo = true
	var msdf := false
	if node is Label3D:
		var font: Font = (node as Label3D).font
		if font != null and "multichannel_signed_distance_field" in font:
			msdf = bool(font.get("multichannel_signed_distance_field"))
	m.albedo_texture_msdf = msdf
	m.no_depth_test = bool(node.get("no_depth_test"))
	m.fixed_size = bool(node.get("fixed_size"))
	m.alpha_antialiasing_mode = int(node.get("alpha_antialiasing_mode")) as BaseMaterial3D.AlphaAntiAliasing
	m.texture_filter = int(node.get("texture_filter")) as BaseMaterial3D.TextureFilter
	var bb := int(node.get("billboard"))
	if bb != BaseMaterial3D.BILLBOARD_DISABLED:
		m.billboard_keep_scale = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if bb == BaseMaterial3D.BILLBOARD_FIXED_Y else BaseMaterial3D.BILLBOARD_ENABLED
	return m


## Terrain3D's shader, as code from the rendering server ("" when there is none to read).
static func terrain_code(node: Node) -> String:
	if node == null or node.get_class() != "Terrain3D":
		return ""
	var tm: Object = node.get("material")
	if tm == null or not tm.has_method("get_shader_rid"):
		return ""
	var rid: RID = tm.call("get_shader_rid")
	return RenderingServer.shader_get_code(rid) if rid.is_valid() else ""


# --- the warm copy --------------------------------------------------------------------------------

## A material with `m`'s shader and nothing else of it worth keeping: the same flags and enums, its
## textures swapped for a shared placeholder of the same kind, no next pass. For a ShaderMaterial,
## its shader (by file, or its code copied into a new one) and no parameters.
static func warm_copy(m: Material) -> Material:
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		var out := ShaderMaterial.new()
		if _is_file(sh.resource_path):
			out.shader = sh
		else:
			var s := Shader.new()
			s.code = sh.code
			out.shader = s
		return out
	var c := m.duplicate(false) as Material
	c.next_pass = null
	c.render_priority = 0
	for p: Dictionary in c.get_property_list():
		if int(p["type"]) != TYPE_OBJECT or not (int(p["usage"]) & PROPERTY_USAGE_STORAGE):
			continue
		var n := str(p["name"])
		var v: Variant = c.get(n)
		if v is Texture:
			c.set(n, placeholder_for(v as Texture))
	return c


## One shared placeholder for each kind of texture.
static func placeholder_for(t: Texture) -> Texture:
	var kind := "2d"
	if t is Texture3D:
		kind = "3d"
	elif t is CubemapArray:
		kind = "cube_array"
	elif t is Cubemap:
		kind = "cube"
	elif t is TextureLayered:
		kind = "2d_array"
	if not _placeholders.has(kind):
		var p: Texture
		match kind:
			"3d": p = PlaceholderTexture3D.new()
			"cube_array": p = PlaceholderCubemapArray.new()
			"cube": p = PlaceholderCubemap.new()
			"2d_array": p = PlaceholderTexture2DArray.new()
			_: p = PlaceholderTexture2D.new()
		p.resource_name = "placeholder_" + kind
		_placeholders[kind] = p
	return _placeholders[kind]


static func shader_material_from_code(code: String) -> ShaderMaterial:
	var s := Shader.new()
	s.code = code
	var out := ShaderMaterial.new()
	out.shader = s
	return out


# --- the run --------------------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set = load_set(out_path)
	for i in _set.materials.size():
		_by_key[key_of(_set.materials[i])] = i
	print("[census] %d materials already in %s" % [_set.materials.size(), out_path])
	get_tree().node_added.connect(_on_node_added)
	_last_flush_ms = Time.get_ticks_msec()
	_add_settings_variants()
	_walk()


## Shaders a graphics setting swaps in that one run would not see: the water's with the mirror and
## without it (Low turns reflections off), for open water and for rivers (WaterSurface.shader_for).
func _add_settings_variants() -> void:
	for mirrored in [true, false]:
		for river in [false, true]:
			var m := ShaderMaterial.new()
			m.shader = WaterSurface.shader_for(mirrored, river)
			_add(m, self)


## The set at `path`, its textures made the shared placeholders again; a new one if there is none.
static func load_set(path: String) -> ShaderWarmSet:
	var out := ShaderWarmSet.new()
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		return out
	var old := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderWarmSet
	if old == null:
		return out
	for i in old.materials.size():
		var m := old.materials[i]
		if m == null or key_of(m).is_empty():
			continue
		out.materials.append(warm_copy(m))
		out.seen_at.append(old.seen_at[i] if i < old.seen_at.size() else "")
	return out


func _on_node_added(node: Node) -> void:
	_queue.append(node)


func _process(_delta: float) -> void:
	# a node's materials are read the frame after it was added (most are set before or in _ready)
	var q := _queue
	_queue = []
	for n in q:
		if is_instance_valid(n) and n.is_inside_tree():
			_look_at(n)
	var now := Time.get_ticks_msec()
	if now - _last_walk_ms > int(WALK_S * 1000.0):
		_walk()
	if _dirty and now - _last_flush_ms > int(FLUSH_S * 1000.0):
		flush()


func _walk() -> void:
	_last_walk_ms = Time.get_ticks_msec()
	var root := get_tree().root
	_look_at(root)
	for n in root.find_children("*", "", true, false):
		_look_at(n)


func _look_at(node: Node) -> void:
	for m in materials_of(node):
		_add(m, node)
	var code := terrain_code(node)
	if not code.is_empty():
		_add_code(code, node)


func _add(m: Material, node: Node, depth := 0) -> void:
	if m == null or depth > 4:
		return
	var key := key_of(m)
	if not key.is_empty() and not _by_key.has(key):
		_keep(key, warm_copy(m), node)
	if m.next_pass != null:
		_add(m.next_pass, node, depth + 1)


func _add_code(code: String, node: Node) -> void:
	var key := code_key(code)
	if not _by_key.has(key):
		_keep(key, shader_material_from_code(code), node)


func _keep(key: String, m: Material, node: Node) -> void:
	_by_key[key] = _set.materials.size()
	_set.materials.append(m)
	var scene := get_tree().current_scene
	_set.seen_at.append("%s @ %s" % [scene.scene_file_path.get_file() if scene != null else "?",
			str(node.get_path()).substr(0, 160)])
	_dirty = true
	_added += 1


## Writes the set, its materials in key order so a regeneration's diff says what changed.
func flush() -> void:
	_last_flush_ms = Time.get_ticks_msec()
	if not _dirty:
		return
	var keys := _by_key.keys()
	keys.sort()
	var out := ShaderWarmSet.new()
	for k: String in keys:
		var i := int(_by_key[k])
		out.materials.append(_set.materials[i])
		out.seen_at.append(_set.seen_at[i])
	var err := ResourceSaver.save(out, out_path)
	if err != OK:
		push_error("[census] could not write %s (%s)" % [out_path, error_string(err)])
		return
	_dirty = false
	print("[census] %d materials (%d new this run) -> %s" % [out.materials.size(), _added, out_path])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		flush()
