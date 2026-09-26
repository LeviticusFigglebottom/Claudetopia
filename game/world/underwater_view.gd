class_name UnderwaterView
extends Node3D
## What the camera sees when it goes under the water (assets/shaders/underwater.gdshader): what is
## behind murked toward the water's colour by its distance, a window of light straight overhead,
## the picture wavering. It checks the camera against `WaterSurface.under` once a frame and is drawn
## only while the camera is under. A pass over the whole frame in 3D, so it can read the frame's
## depth; a canvas layer cannot, and washed everything one flat colour whatever its distance.

## The water's colour under the surface, by the region's look (WaterSurface.set_region_look).
var water_colour := Color(0.06, 0.20, 0.24)
## How far under the surface the camera is, in metres (0 above it).
var depth := 0.0
var _quad: MeshInstance3D
var _mat: ShaderMaterial


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/underwater.gdshader")
	_mat.render_priority = 120
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	_quad = MeshInstance3D.new()
	_quad.name = "Underwater"
	_quad.mesh = mesh
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# drawn over the whole frame from the shader: never culled
	_quad.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	_quad.visible = false
	add_child(_quad)


func _process(_delta: float) -> void:
	var vp := get_viewport() if is_inside_tree() else null
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	# a few centimetres of margin, so the camera skimming the surface does not flicker in and out
	depth = WaterSurface.under(cam.global_position + Vector3(0.0, 0.05, 0.0))
	var under := depth > 0.0
	if under != _quad.visible:
		_quad.visible = under
	if under:
		_quad.global_position = cam.global_position
		_mat.set_shader_parameter("depth_m", depth)
		_mat.set_shader_parameter("water_colour", water_colour)


func is_under() -> bool:
	return _quad != null and _quad.visible
