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
## glints; moss: how readily moss takes on it; flatten: how far a stone lifted off its floor has its
## picture pulled toward its own mean, so the fused stone's flow bands stay faint.
##
## Every stone is drawn between VALUE_FLOOR and its ceiling (VALUE_CEILING, or its own `ceiling`)
## of mean linear albedo, measured per rock by tools/world/rock_values.py. The forge painted
## Cinderlea's fused stone and basalt near black (0.016-0.02, half the ash ground's 0.038), and at
## the start they read as holes in the frame, as the ash did before it was relit; and it painted
## Hearthvale's and Skerrow's ledges and slabs near white (0.3-0.44, four to eight times the green
## slope they stand in), which the user's playtest 6 saw as "flat and out of place": thin white
## paper on a hillside. Bone is allowed paler than stone.
const STONES := {
	"chalk_rock": {"edge": 0.8, "streaks": 0.2, "speckle": 0.25, "sheen": 0.0, "moss": 1.0},
	"granite": {"edge": 0.6, "streaks": 0.3, "speckle": 0.55, "sheen": 0.05, "moss": 1.0},
	"limestone": {"edge": 0.55, "streaks": 0.7, "speckle": 0.15, "sheen": 0.0, "moss": 0.8},
	"basalt": {"edge": 0.35, "streaks": 0.2, "speckle": 0.1, "sheen": 0.35, "moss": 0.6, "flatten": 0.4},
	"fused_stone": {"edge": 0.5, "streaks": 0.12, "speckle": 0.05, "sheen": 0.55, "moss": 0.4, "flatten": 0.55},
	"lake_stone": {"edge": 0.3, "streaks": 0.25, "speckle": 0.3, "sheen": 0.1, "moss": 1.1},
	"stone_blocks": {"edge": 0.6, "streaks": 0.45, "speckle": 0.2, "sheen": 0.0, "moss": 1.4},
	"drowned_stone": {"edge": 0.4, "streaks": 0.5, "speckle": 0.15, "sheen": 0.1, "moss": 1.6},
	"bone": {"edge": 0.45, "streaks": 0.35, "speckle": 0.1, "sheen": 0.05, "moss": 0.35, "ceiling": 0.3},
	# old bell metal, and the ground it lies in (one baked picture): the forge's own verdigris
	# runs, bare bronze rubbed pale only on the proudest edges, a dull glint -- not the smooth CG
	# sheen of the forge's metal, which read as a plastic dome over the trees (playtest 6) -- and
	# the region's turf and soil where the mound meets the ground
	"bell_bronze_patina": {"edge": 0.35, "streaks": 0.5, "speckle": 0.12, "sheen": 0.2, "moss": 0.15,
			"ceiling": 0.22},
}
## Landmarks drawn in the painted stone as well, by name, with the material their meta names.
## Empty until the Toll's regenerated mesh lands (tools/forge/gen_landmarks.py): the shipped
## Toll's picture carries its chalk mound, which the bronze's ceiling would darken with it.
const LANDMARKS := {}
const VALUE_FLOOR := 0.028
const VALUE_CEILING := 0.24
## The measured means (tools/world/rock_values.py).
const VALUES := "res://world/rock_values.json"
const DEFAULT_STONE := {"edge": 0.5, "streaks": 0.3, "speckle": 0.2, "sheen": 0.0, "moss": 1.0}
## Not stone: left as the forge made it.
const NOT_STONE := ["black_ash_bark", "oak_bark", "driftwood_log", "moss"]

## Each region's weathering on its stone: moss (or, in Cinderlea, the ash dust that lies where
## moss would) and how much of it, lichen and how much, the soil at a rock's foot and how high it
## reaches (metres), the bearing the weather comes from (degrees, 0 = north, clockwise); the hue
## its stone takes (a lent or a pale stone leans to the country's own: `stone`, and how far), and
## the turf that grows up onto a rock's ledges from the slope round it (`turf`, how far up it
## reaches, metres; none in the ash country).
const REGION_ROCK := {
	"hearthvale": {"moss": "#5c6a33", "moss_amt": 0.3, "lichen": "#bdb27c", "lichen_amt": 0.45,
			"soil": "#463d2c", "foot_m": 0.4, "weather_deg": 225.0,
			"stone": "#9c9480", "stone_amt": 0.45, "turf": "#5e6e2e", "turf_m": 1.6},
	"brightwater": {"moss": "#52603a", "moss_amt": 0.3, "lichen": "#aeb296", "lichen_amt": 0.4,
			"soil": "#4a4535", "foot_m": 0.45, "weather_deg": 260.0,
			"stone": "#8e949a", "stone_amt": 0.35, "turf": "#56683a", "turf_m": 1.2},
	"sedgemire": {"moss": "#4b5a2a", "moss_amt": 0.6, "lichen": "#9ea27c", "lichen_amt": 0.2,
			"soil": "#2e2a1f", "foot_m": 0.7, "weather_deg": 250.0,
			"stone": "#6e7466", "stone_amt": 0.4, "turf": "#4e5c2c", "turf_m": 1.4},
	"briarwold": {"moss": "#3e5230", "moss_amt": 0.5, "lichen": "#a3b08e", "lichen_amt": 0.25,
			"soil": "#382e20", "foot_m": 0.5, "weather_deg": 225.0,
			"stone": "#7a8070", "stone_amt": 0.4, "turf": "#40582a", "turf_m": 1.8},
	"skerrow": {"moss": "#5c6441", "moss_amt": 0.2, "lichen": "#b89a55", "lichen_amt": 0.55,
			"soil": "#4b4840", "foot_m": 0.35, "weather_deg": 300.0,
			"stone": "#8c8a88", "stone_amt": 0.3, "turf": "#6a6a48", "turf_m": 0.8},
	"cinderlea": {"moss": "#6b6660", "moss_amt": 0.3, "lichen": "#76716a", "lichen_amt": 0.08,
			"soil": "#26221f", "foot_m": 0.5, "weather_deg": 270.0,
			"stone": "#4a4440", "stone_amt": 0.3, "turf": "#26221f", "turf_m": 0.0},
}
## The manifest's region order, for a world with no provider (a headless test).
const REGION_ORDER := ["hearthvale", "brightwater", "sedgemire", "briarwold", "skerrow", "cinderlea"]

static var _made: Dictionary = {}           # source material instance id -> ShaderMaterial
static var _values: Dictionary = {}         # rock name -> mean linear albedo [r, g, b]
static var _region_map: Texture2D = null
static var _height_map: Texture2D = null
static var _height_rect := Vector4(-4096.0, -4096.0, 8.0, 1024.0)
static var _region_table: Texture2D = null
static var _world_rect := Vector4(-4096.0, -4096.0, 8.0, 1024.0)
static var _order: Array = REGION_ORDER.duplicate()
static var _bound := false
## WM_ROCK_PAINT=0 in the environment leaves every rock as the forge made it: the before of a
## before-and-after, on the same build.
static var enabled := OS.get_environment("WM_ROCK_PAINT") != "0"


## Give every mesh in a rock's scene the painted material (once; later calls cost a lookup).
static func paint_scene(packed: PackedScene, path: String) -> void:
	if not enabled or packed == null:
		return
	var landmark := str(LANDMARKS.get(path.get_file().get_basename(), ""))
	if not path.contains("/rocks/") and landmark == "":
		return
	var stone := landmark if landmark != "" else stone_of(path)
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
	var mean := mean_of(path, src.albedo_color)
	if mean.a > 0.0:
		var lift := lift_for(mean, VALUE_FLOOR, float(ch.get("ceiling", VALUE_CEILING)))
		m.set_shader_parameter("value_lift", lift)
		if lift > 1.0:
			m.set_shader_parameter("value_mean", Color(mean.r * lift, mean.g * lift, mean.b * lift).linear_to_srgb())
			m.set_shader_parameter("value_flatten", float(ch.get("flatten", 0.0)))
	m.set_shader_parameter("own_region", maxi(_order.find(region_of(path)), 0))
	_bind_material(m)
	_made[key] = m
	return m


## A rock's measured mean albedo (linear, times the material's tint; tools/world/rock_values.py),
## alpha 0 when the table has none for it.
static func mean_of(path: String, tint: Color) -> Color:
	if _values.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VALUES)) \
				if FileAccess.file_exists(VALUES) else null
		_values = (parsed as Dictionary).get("rocks", {}) if parsed is Dictionary else {"": []}
	var v: Array = _values.get(path.get_file().get_basename(), [])
	if v.size() < 3:
		return Color(0, 0, 0, 0)
	return Color(float(v[0]) * tint.r, float(v[1]) * tint.g, float(v[2]) * tint.b, 1.0)


## What a stone's albedo is multiplied by for its mean to lie between `floor_value` and
## `ceiling` (linear): up at most four times, down to whatever the ceiling asks.
static func lift_for(mean: Color, floor_value: float, ceiling: float) -> float:
	var lum := (mean.r + mean.g + mean.b) / 3.0
	if lum <= 0.0:
		return 1.0
	if lum < floor_value:
		return minf(floor_value / lum, 4.0)
	if lum > ceiling:
		return ceiling / lum
	return 1.0


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


## The colours are written linear (the shader reads the table raw), the amounts as they are.
## One column a region, six rows: moss (rgb, amount), lichen (rgb, amount), soil (rgb, foot
## height / 2 m), weather (the direction it comes from, x and z, as 0-1), the country's stone
## (rgb, how far a stone leans to it) and its turf (rgb, how far up it grows / 4 m).
static func _make_table() -> void:
	var n := maxi(_order.size(), 1)
	var img := Image.create(n, 6, false, Image.FORMAT_RGBA8)
	for i in n:
		var r: Dictionary = REGION_ROCK.get(_order[i] if i < _order.size() else "", REGION_ROCK["hearthvale"])
		var moss := Color.html(str(r["moss"])).srgb_to_linear()
		var lichen := Color.html(str(r["lichen"])).srgb_to_linear()
		var soil := Color.html(str(r["soil"])).srgb_to_linear()
		var a := deg_to_rad(float(r["weather_deg"]))
		# a bearing: 0 north (-z), 90 east (+x)
		var from := Vector2(sin(a), -cos(a))
		img.set_pixel(i, 0, Color(moss.r, moss.g, moss.b, float(r["moss_amt"])))
		img.set_pixel(i, 1, Color(lichen.r, lichen.g, lichen.b, float(r["lichen_amt"])))
		img.set_pixel(i, 2, Color(soil.r, soil.g, soil.b, clampf(float(r["foot_m"]) / 2.0, 0.0, 1.0)))
		img.set_pixel(i, 3, Color(from.x * 0.5 + 0.5, from.y * 0.5 + 0.5, 0.0, 1.0))
		var stone := Color.html(str(r.get("stone", "#808080")))
		img.set_pixel(i, 4, Color(stone.r, stone.g, stone.b, float(r.get("stone_amt", 0.0))))
		var turf := Color.html(str(r.get("turf", "#556633"))).srgb_to_linear()
		img.set_pixel(i, 5, Color(turf.r, turf.g, turf.b, clampf(float(r.get("turf_m", 0.0)) / 4.0, 0.0, 1.0)))
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
	if not enabled or provider == null or not provider.has_runtime_maps():
		return
	for row in rows:
		if typeof(row) != TYPE_ARRAY or (row as Array).size() < 3:
			continue
		var r: Array = row
		var x := float(r[0])
		var z := float(r[2])
		var alpha := corr_alpha(provider.get_height(x, z) - provider.sample_height(x, z))
		var tint := Color.from_string(str(r[5]), Color.WHITE) if r.size() > 5 else Color.WHITE
		tint.a = alpha
		var hex := "#" + tint.to_html(true)
		while r.size() < 6:
			r.append(1.0 if r.size() == 4 else (0.0 if r.size() == 3 else "#ffffff"))
		r[5] = hex


## A ground correction (metres, +-2) as a tint alpha: 0.5 is none. Kept under 0.999, which the
## shader reads as a tint that carries none (a POI's placed rock, white).
static func corr_alpha(corr: float) -> float:
	return clampf(0.5 + corr / 4.0, 0.0, 0.996)


## What the shader reads back from a tint's alpha (painted_rock.gdshader, vertex()).
static func alpha_corr(alpha: float) -> float:
	return (alpha - 0.5) * 4.0 if alpha < 0.999 else 0.0
