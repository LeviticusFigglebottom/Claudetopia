extends Node
## Does a directional light cast a shadow on this renderer, and what stops it?
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy --resolution 800x600 res://tools_gd/shadow_probe.tscn -- --out=<abs dir>
##
## This exists because "the frame has no shadows" has three unrelated causes and a screenshot
## of the world cannot tell them apart: the light, the receiving surface, or the sun being so
## high that every shadow hides under the thing casting it. Each case below renders a box on a
## plane and changes exactly one thing, so the answer is the first case that goes flat.
##
##   a  a plain light on a plain plane                  -- does this renderer do shadows at all
##   b  the light configured the way Atmosphere does    -- splits, bias, angular distance
##   c  b, plus the WorldEnvironment Atmosphere builds  -- sky ambient, fog, ACES tonemap
##   d  b, receiver using `skip_vertex_transform`       -- what Terrain3D's ground shader does
##   e  b, receiver 8 km across                         -- what Terrain3D's ground instance is
##   f  d and e together
##
## On 2026-09-22, under Compatibility, every case shadowed correctly. That is the finding:
## the shadowless world frames were the sun's elevation and nothing else. The terrain was
## briefly suspected of not receiving shadows at all -- a village street at 16:30 showed a
## house in shadow standing on lit grass -- and that was wrong: with the sun brought down to
## the region's own latitude, a hawthorn lays a dappled leaf shadow across the ground with
## the individual leaf clusters legible in it. What made the ground look unshadowed was a
## sun 60 to 94 degrees up, which puts every shadow underneath the thing that casts it.

const SKIP_VT_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, skip_vertex_transform;
uniform vec4 albedo : source_color = vec4(0.45, 0.6, 0.3, 1.0);
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.9;
}
"""

var out_dir := "captures/shadow_probe"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("[probe] renderer=%s  directional_shadow/size=%s"
		% [RenderingServer.get_current_rendering_method(),
			str(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"))])
	await _case("a_plain", false, false)
	await _case("b_atmosphere_light", true, false)
	await _case("c_atmosphere_light_and_env", true, true)
	await _case("d_skip_vertex_transform", true, false, true)
	await _case("e_world_sized_receiver", true, false, false, 8192.0)
	await _case("f_world_sized_skip_vt", true, false, true, 8192.0)
	print("[probe] look at the PNGs: a case with no dark wedge beside the box is the answer")
	get_tree().quit(0)


func _case(label: String, atmos_light: bool, atmos_env: bool, skip_vt := false,
		plane_m := 40.0) -> void:
	var root := Node3D.new()
	add_child(root)

	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(plane_m, plane_m)
	# subdivided when it is world-sized, so the test is "one enormous instance" and not
	# "one enormous quad"
	if plane_m > 1000.0:
		pm.subdivide_width = 64
		pm.subdivide_depth = 64
	plane.mesh = pm
	if skip_vt:
		var sh := Shader.new()
		sh.code = SKIP_VT_SHADER
		var smat := ShaderMaterial.new()
		smat.shader = sh
		plane.material_override = smat
	else:
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.45, 0.6, 0.3)
		plane.material_override = pmat
	root.add_child(plane)

	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3, 5, 3)
	box.mesh = bm
	box.position = Vector3(0, 2.5, 0)
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(box)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	if atmos_light:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 260.0
		sun.directional_shadow_split_1 = 0.06
		sun.directional_shadow_split_2 = 0.18
		sun.directional_shadow_split_3 = 0.45
		sun.directional_shadow_blend_splits = true
		sun.shadow_bias = 0.03
		sun.shadow_normal_bias = 1.5
		sun.light_angular_distance = 0.8
	sun.light_energy = 1.3
	# a 60 degree sun to the east, which is roughly Hearthvale at nine in the morning
	var e := deg_to_rad(60.0)
	var sun_dir := Vector3(cos(deg_to_rad(45.0)) * cos(e), sin(e), 0.35 * cos(e)).normalized()
	sun.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3.ZERO)
	root.add_child(sun)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	if atmos_env:
		env.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var sm := ShaderMaterial.new()
		sm.shader = load("res://assets/shaders/painted_sky.gdshader")
		sky.sky_material = sm
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.8
		env.ambient_light_energy = 1.0
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_white = 6.0
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = 0.00026
		env.adjustment_enabled = true
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.4, 0.55, 0.8)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.5, 0.5, 0.5)
		env.ambient_light_energy = 0.6
	we.environment = env
	root.add_child(we)

	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(-9, 6, 9), Vector3(0, 2, 0), Vector3.UP)
	cam.make_current()

	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, label])
	print("[probe] %-26s wrote %s.png" % [label, label])
	root.queue_free()
	await get_tree().process_frame
