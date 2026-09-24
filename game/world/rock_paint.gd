class_name RockPaint
extends RefCounted
## The painted stone (assets/shaders/painted_rock.gdshader) swapped in for the forge's
## StandardMaterial3D on every rock the world draws, the first time a rock's scene is loaded
## (WorldStreamer._scene_for, PoiKit.scene). It is done here and not at import so that no
## re-import is needed anywhere: the forge's albedo, normal and occlusion are kept, and every
## mesh of the scene (its levels of detail too) is given the painted material once, which every
## scatter and every placed copy then shares.
##
## Each stone keeps its own character (STONES, by the forge's material: chalk, granite, limestone,
## basalt, fused stone...), and its weathering is the country's where it stands: the shader reads
## the runtime region map at the rock's own position and a table of each region's moss, lichen,
## soil and weather (REGION_ROCK), so a stone lent from another region's set wears the ground it
## is set in. Wood in the rocks folder (fallen logs, driftwood) is left as the forge made it.

const SHADER := preload("res://assets/shaders/painted_rock.gdshader")

## The stone's own character, by the forge's material name (the rock's meta `materials_used`).
## edge: how pale its edges wear; streaks: rain down its faces; speckle: its grain; sheen: how it
## glints; moss: how readily moss takes on it.
const STONES := {
	"chalk_rock": {"edge": 0.8, "streaks": 0.2, "speckle": 0.25, "sheen": 0.0, "moss": 1.0},
	"granite": {"edge": 0.6, "streaks": 0.3, "speckle": 0.55, "sheen": 0.05, "moss": 1.0},
	"limestone": {"edge": 0.55, "streaks": 0.7, "speckle": 0.15, "sheen": 0.0, "moss": 0.8},
	"basalt": {"edge": 0.35, "streaks": 0.2, "speckle": 0.1, "sheen": 0.35, "moss": 0.6},
	"fused_stone": {"edge": 0.5, "streaks": 0.12, "speckle": 0.05, "sheen": 0.55, "moss": 0.4},
	"lake_stone": {"edge": 0.3, "streaks": 0.25, "speckle": 0.3, "sheen": 0.1, "moss": 1.1},
	"stone_blocks": {"edge": 0.6, "streaks": 0.45, "speckle": 0.2, "sheen": 0.0, "moss": 1.4},
	"drowned_stone": {"edge": 0.4, "streaks": 0.5, "speckle": 0.15, "sheen": 0.1, "moss": 1.6},
	"bone": {"edge": 0.45, "streaks": 0.35, "speckle": 0.1, "sheen": 0.05, "moss": 0.35},
}
const DEFAULT_STONE := {"edge": 0.5, "streaks": 0.3, "speckle": 0.2, "sheen": 0.0, "moss": 1.0}
## Not stone: left as the forge made it.
const NOT_STONE := ["black_ash_bark", "oak_bark", "driftwood_log", "moss"]

## Each region's weathering on its stone: moss (or, in Cinderlea, the ash dust that lies where
## moss would) and how much of it, lichen and how much, the soil at a rock's foot and how high it
## reaches (metres), and the bearing the weather comes from (degrees, 0 = north, clockwise).
const REGION_ROCK := {
	"hearthvale": {"moss": "#5c6a33", "moss_amt": 0.3, "lichen": "#bdb27c", "lichen_amt": 0.45,
			"soil": "#463d2c", "foot_m": 0.4, "weather_deg": 225.0},
	"brightwater": {"moss": "#52603a", "moss_amt": 0.3, "lichen": "#aeb296", "lichen_amt": 0.4,
			"soil": "#4a4535", "foot_m": 0.45, "weather_deg": 260.0},
	"sedgemire": {"moss": "#4b5a2a", "moss_amt": 0.6, "lichen": "#9ea27c", "lichen_amt": 0.2,
			"soil": "#2e2a1f", "foot_m": 0.7, "weather_deg": 250.0},
	"briarwold": {"moss": "#476a28", "moss_amt": 0.75, "lichen": "#a3b08e", "lichen_amt": 0.25,
			"soil": "#382e20", "foot_m": 0.5, "weather_deg": 225.0},
	"skerrow": {"moss": "#5c6441", "moss_amt": 0.2, "lichen": "#b89a55", "lichen_amt": 0.55,
			"soil": "#4b4840", "foot_m": 0.35, "weather_deg": 300.0},
	"cinderlea": {"moss": "#8e8a85", "moss_amt": 0.45, "lichen": "#8a857d", "lichen_amt": 0.08,
			"soil": "#26221f", "foot_m": 0.5, "weather_deg": 270.0},
}
## The manifest's region order, for a world with no provider (a headless test).
const REGION_ORDER := ["hearthvale", "brightwater", "sedgemire", "briarwold", "skerrow", "cinderlea"]

static var _made: Dictionary = {}           # source material instance id -> ShaderMaterial
static var _region_map: Texture2D = null
static var _height_map: Texture2D = null
static var _height_rect := Vector4(-4096.0, -4096.0, 8.0, 1024.0)
static var _region_table: Texture2D = null
static var _world_rect := Vector4(-4096.0, -4096.0, 8.0, 1024.0)
static var _order: Array = REGION_ORDER.duplicate()
static var _bound := false


## Give every mesh in a rock's scene the painted material (once; later calls cost a lookup).
static func paint_scene(packed: PackedScene, path: String) -> void:
	if packed == null or not path.contains("/rocks/"):
		return
	var stone := stone_of(path)
	if stone in NOT_STONE:
		return
	_try_bind()
	var state := packed.get_state()
	for i in state.get_node_count():
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) != "mesh":
				continue
			var m: Variant = state.get_node_property_value(i, p)
			if m is Mesh:
				_paint_mesh(m as Mesh, path, stone)


static func _paint_mesh(mesh: Mesh, path: String, stone: String) -> void:
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat is StandardMaterial3D:
			mesh.surface_set_material(s, material_for(mat as StandardMaterial3D, path, stone))


## The painted material for one of the forge's rock materials (made once, then shared).
static func material_for(src: StandardMaterial3D, path: String, stone: String) -> ShaderMaterial:
	var key := src.get_instance_id()
	if _made.has(key):
		return _made[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.resource_name = src.resource_name
	m.set_shader_parameter("albedo_texture", src.albedo_texture)
	m.set_shader_parameter("albedo_tint", src.albedo_color)
	m.set_shader_parameter("has_normal", src.normal_enabled and src.normal_texture != null)
	if src.normal_texture != null:
		m.set_shader_parameter("normal_texture", src.normal_texture)
	var orm: Texture2D = src.ao_texture if src.ao_texture != null else src.roughness_texture
	if orm != null:
		m.set_shader_parameter("orm_texture", orm)
	m.set_shader_parameter("roughness_base", clampf(src.roughness, 0.5, 1.0))
	var ch: Dictionary = STONES.get(stone, DEFAULT_STONE)
	m.set_shader_parameter("edge_wear", float(ch["edge"]))
	m.set_shader_parameter("streaks", float(ch["streaks"]))
	m.set_shader_parameter("speckle", float(ch["speckle"]))
	m.set_shader_parameter("sheen", float(ch["sheen"]))
	m.set_shader_parameter("moss_mult", float(ch["moss"]))
	m.set_shader_parameter("own_region", maxi(_order.find(region_of(path)), 0))
	_bind_material(m)
	_made[key] = m
	return m


## The forge's material for a rock, from its meta (`materials_used`), or "" when it says none.
static func stone_of(path: String) -> String:
	var used: Array = PoiKit.meta(path).get("materials_used", [])
	return str(used[0]) if not used.is_empty() else ""


## The region whose set a rock is from: <region>_<kind>_<variant>.
static func region_of(path: String) -> String:
	return path.get_file().get_basename().get_slice("_", 0)


## The region map and the weathering table, once the world's runtime maps are loaded.
static func _try_bind() -> void:
	if _bound:
		return
	var provider := World.terrain()
	var regions := provider.runtime_regions() if provider != null else PackedByteArray()
	var grid := int(round(sqrt(float(regions.size()))))
	if regions.is_empty() or grid * grid != regions.size():
		if _region_table == null:
			_make_table()
		return
	_order.clear()
	for id in provider.region_ids:
		_order.append(str(id).get_slice("/", 1) if str(id).contains("/") else str(id))
	var img := Image.create_from_data(grid, grid, false, Image.FORMAT_R8, regions)
	_region_map = ImageTexture.create_from_image(img)
	_world_rect = Vector4(provider.origin.x, provider.origin.y, provider.size_m / float(grid), float(grid))
	var heights := provider.runtime_heights()
	var hg := provider.runtime_grid()
	if hg > 1 and heights.size() == hg * hg:
		var himg := Image.create_from_data(hg, hg, false, Image.FORMAT_RF, heights.to_byte_array())
		_height_map = ImageTexture.create_from_image(himg)
		var ho := provider.height_origin()
		_height_rect = Vector4(ho.x, ho.y, provider.runtime_spacing(), float(hg))
	_make_table()
	_bound = true
	for key in _made:
		_bind_material(_made[key])


## One column a region, four rows: moss (rgb, amount), lichen (rgb, amount), soil (rgb, foot
## height / 2 m), weather (the direction it comes from, x and z, as 0-1).
static func _make_table() -> void:
	var n := maxi(_order.size(), 1)
	var img := Image.create(n, 4, false, Image.FORMAT_RGBA8)
	for i in n:
		var r: Dictionary = REGION_ROCK.get(_order[i] if i < _order.size() else "", REGION_ROCK["hearthvale"])
		var moss := Color.html(str(r["moss"]))
		var lichen := Color.html(str(r["lichen"]))
		var soil := Color.html(str(r["soil"]))
		var a := deg_to_rad(float(r["weather_deg"]))
		# a bearing: 0 north (-z), 90 east (+x)
		var from := Vector2(sin(a), -cos(a))
		img.set_pixel(i, 0, Color(moss.r, moss.g, moss.b, float(r["moss_amt"])))
		img.set_pixel(i, 1, Color(lichen.r, lichen.g, lichen.b, float(r["lichen_amt"])))
		img.set_pixel(i, 2, Color(soil.r, soil.g, soil.b, clampf(float(r["foot_m"]) / 2.0, 0.0, 1.0)))
		img.set_pixel(i, 3, Color(from.x * 0.5 + 0.5, from.y * 0.5 + 0.5, 0.0, 1.0))
	_region_table = ImageTexture.create_from_image(img)


static func _bind_material(m: ShaderMaterial) -> void:
	if _region_table == null:
		_make_table()
	m.set_shader_parameter("region_table", _region_table)
	m.set_shader_parameter("region_count", _order.size())
	if _region_map != null:
		m.set_shader_parameter("region_map", _region_map)
		m.set_shader_parameter("world_rect", _world_rect)
		m.set_shader_parameter("regions_bound", 1.0)
	if _height_map != null:
		m.set_shader_parameter("height_map", _height_map)
		m.set_shader_parameter("height_rect", _height_rect)
		m.set_shader_parameter("heights_bound", 1.0)


## Carry each scattered rock's ground correction in its tint's alpha: the exact ground height at
## the rock less the runtime map's bilinear there, which is what the shader reads the ground line
## from. (The tint's alpha is otherwise unused: rocks are opaque.) Rows are CONTRACTS §6 rows; the
## tint, when a row has none, is white. Recomputed from the row's own position each time, so a
## cell built twice comes out the same.
static func seat_rows(rows: Array, provider: TerrainProvider) -> void:
	if provider == null or not provider.has_runtime_maps():
		return
	for row in rows:
		if typeof(row) != TYPE_ARRAY or (row as Array).size() < 3:
			continue
		var r: Array = row
		var x := float(r[0])
		var z := float(r[2])
		var corr := provider.get_height(x, z) - provider.sample_height(x, z)
		var alpha := clampf(0.5 + corr / 4.0, 0.0, 0.996)
		var tint := Color.from_string(str(r[5]), Color.WHITE) if r.size() > 5 else Color.WHITE
		tint.a = alpha
		var hex := "#" + tint.to_html(true)
		while r.size() < 6:
			r.append(1.0 if r.size() == 4 else (0.0 if r.size() == 3 else "#ffffff"))
		r[5] = hex
