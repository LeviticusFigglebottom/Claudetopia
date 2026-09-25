class_name GroundMist
extends MeshInstance3D
## The mist that lies on the land, each region's own (assets/shaders/ground_mist.gdshader): a
## layer marched along every pixel's line of sight over the ground it crosses, reading the runtime
## region, height and water maps, so the Sedgemire's marsh mist lies on the Sedgemire whichever
## region the camera stands in, and it lies in the hollows and on the water rather than at one
## height over the whole world, which is all Godot's own height fog can do (the Atmosphere's haze,
## held under the eye, is the camera region's and stays as it was).
##
## One quad the shader stretches over the screen, drawn after everything else that is see-through;
## the Atmosphere owns it and hands it the hour, the weather and whether the player is indoors.
## Each region's layer is `identity.light`'s mist keys (systems/atmosphere/README.md):
##   mist_color    its colour in the air (sRGB), lit by the sky and the sun
##   mist_density  how thick it is at the ground, per metre (0: none)
##   mist_depth    how fast it thins with the height over the ground (metres, e-folding)
##   mist_morning  how much thicker it lies after sunrise (x (1 + it))
##   mist_water    how much thicker it lies over open water and the marsh's pools (x (1 + it))
## `graphics/fog` (Distance haze) off turns it off with the rest of the haze.

const SHADER := preload("res://assets/shaders/ground_mist.gdshader")
## A region that says nothing has none.
const NO_MIST := {"mist_color": "#c8ccd0", "mist_density": 0.0, "mist_depth": 3.0, "mist_morning": 0.0,
		"mist_water": 0.0}
## How the mist's body drifts over the ground, metres a second at the wind's full strength.
const DRIFT_MPS := 1.2
## WM_GROUND_MIST=0 in the environment leaves it off: the before of a before-and-after.
static var enabled := OS.get_environment("WM_GROUND_MIST") != "0"

var material: ShaderMaterial
## The region order the table was made in (the world's manifest order).
var order: Array = []
var _bound := false
var _drift := Vector2.ZERO
var _last_region := 0


func _ready() -> void:
	name = "GroundMist"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mesh = quad
	# the shader places it over the whole screen: it must never be culled, wherever it stands
	custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0e6), Vector3(2.0e6, 2.0e6, 2.0e6))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	material = ShaderMaterial.new()
	material.shader = SHADER
	# after the water, the smoke and every other see-through thing, which it lies over
	material.render_priority = Material.RENDER_PRIORITY_MAX
	material_override = material
	visible = false
	_try_bind()


## Bind the world's runtime maps and each region's layer, once the world has loaded them.
func _try_bind() -> bool:
	if _bound:
		return true
	var provider := World.terrain()
	if provider == null or not provider.has_runtime_maps():
		return false
	var regions := provider.runtime_regions()
	var grid := provider.runtime_grid()
	if regions.size() != grid * grid:
		return false
	order.clear()
	for id in provider.region_ids:
		order.append(str(id))
	var rimg := Image.create_from_data(grid, grid, false, Image.FORMAT_R8, regions)
	material.set_shader_parameter("region_map", ImageTexture.create_from_image(rimg))
	material.set_shader_parameter("world_rect", Vector4(provider.origin.x, provider.origin.y,
			provider.size_m / float(grid), float(grid)))
	var himg := Image.create_from_data(grid, grid, false, Image.FORMAT_RF,
			provider.runtime_heights().to_byte_array())
	material.set_shader_parameter("height_map", ImageTexture.create_from_image(himg))
	var ho := provider.height_origin()
	material.set_shader_parameter("height_rect", Vector4(ho.x, ho.y, provider.runtime_spacing(), float(grid)))
	material.set_shader_parameter("water_map", ImageTexture.create_from_image(
			Image.create_from_data(grid, grid, false, Image.FORMAT_RF, water_levels(provider).to_byte_array())))
	material.set_shader_parameter("mist_table", ImageTexture.create_from_image(table(order)))
	material.set_shader_parameter("region_count", order.size())
	_bound = true
	return true


## Each texel the surface of the water there, or -1000 where it is dry: the mist lies on the
## water, not on the bed under it, and none of it lies under the surface.
static func water_levels(provider: TerrainProvider) -> PackedFloat32Array:
	var grid := provider.runtime_grid()
	var out := PackedFloat32Array()
	out.resize(grid * grid)
	out.fill(TerrainProvider.NO_WATER)
	var wet := provider.runtime_water()
	var levels := provider.runtime_levels()
	if wet.size() != grid * grid or levels.size() != grid * grid:
		return out
	for i in wet.size():
		if wet[i] != 0:
			out[i] = levels[i]
	return out


## Each region's layer from its pack def.
static func layer_of(region_id: String) -> Dictionary:
	var out := NO_MIST.duplicate()
	var def := ContentDB.get_def(region_id) if ContentDB.has(region_id) else {}
	var light: Dictionary = def.get("identity", {}).get("light", {})
	for key in NO_MIST:
		if light.has(key):
			out[key] = light[key]
	return out


## The table the shader reads, one column a region: (colour, density x 10) and (depth / 16,
## morning / 4, water / 4, 0).
static func table(region_order: Array) -> Image:
	var n := maxi(region_order.size(), 1)
	var img := Image.create(n, 2, false, Image.FORMAT_RGBAF)
	for i in n:
		var l := layer_of(str(region_order[i]) if i < region_order.size() else "")
		var c := Color.html(str(l["mist_color"])).srgb_to_linear()
		img.set_pixel(i, 0, Color(c.r, c.g, c.b, float(l["mist_density"]) * 10.0))
		img.set_pixel(i, 1, Color(float(l["mist_depth"]) / 16.0, float(l["mist_morning"]) / 4.0,
				float(l["mist_water"]) / 4.0, 0.0))
	return img


## What the Atmosphere hands over each frame: the morning (1 just after sunrise, 0 by noon), the
## weather's fog multiplier, the wind, the camera's own region (for the open water, which
## belongs to none), and whether it is to be drawn at all.
func set_state(morning: float, fog_mult: float, wind: Vector2, camera_region: String, on: bool,
		delta: float) -> void:
	if not on or not enabled or not _try_bind():
		visible = false
		return
	visible = true
	_drift += wind * DRIFT_MPS * delta
	material.set_shader_parameter("morning", morning)
	material.set_shader_parameter("weather", clampf(fog_mult, 0.5, 3.0))
	material.set_shader_parameter("drift", _drift)
	var idx := order.find(camera_region)
	if idx >= 0:
		_last_region = idx
	material.set_shader_parameter("camera_region", _last_region)
