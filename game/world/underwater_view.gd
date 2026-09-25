class_name UnderwaterView
extends CanvasLayer
## What the camera sees when it goes under the water: the frame washed toward the water's own deep
## colour, wavering, with the surface's light playing across the top. It checks the camera against
## `WaterSurface.under` once a frame and is drawn only while the camera is under. The water sheet
## already draws its own underside (painted_water's `from_below`): the surface seen from beneath.

## The water's colour under the surface, by the region's look (WaterSurface.set_region_look).
var water_colour := Color(0.06, 0.20, 0.24)
## How far under the surface the camera is, in metres (0 above it).
var depth := 0.0
var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 1
	_rect = ColorRect.new()
	_rect.name = "Underwater"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/underwater.gdshader")
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# a few centimetres of margin, so the camera skimming the surface does not flicker in and out
	depth = WaterSurface.under(cam.global_position + Vector3(0.0, 0.05, 0.0))
	var under := depth > 0.0
	if under != _rect.visible:
		_rect.visible = under
	if under:
		_mat.set_shader_parameter("depth_m", depth)
		_mat.set_shader_parameter("water_colour", water_colour)


func is_under() -> bool:
	return _rect != null and _rect.visible
