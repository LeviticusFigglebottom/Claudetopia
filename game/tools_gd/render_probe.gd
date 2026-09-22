extends SceneTree
## Which of the Environment's features the renderer in use actually honours, measured.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy --resolution 1280x720 -s res://tools_gd/render_probe.gd -- --out=<abs dir>
##
## The class reference this engine ships has the property names and not the notes that say
## "not supported in the Compatibility renderer", and a property the renderer ignores does not
## warn: it takes the value and draws the frame without it. So every feature the look leans on
## is switched on against a stage and the frame is compared with the frame without it. A mean
## difference of zero is a feature this renderer does not draw, whatever the inspector says.
##
## It also counts what lights cost: draw calls with no omni lights, with eight unshadowed ones,
## and with one of them shadowed, which is the number the night-light pool is sized from.
## Writes <out>/probe_<feature>.png for looking at and prints one line per feature.

const W := 320
const H := 180

var out_dir := "user://render_probe"
var stage: Node3D
var env: Environment
var cam: Camera3D
var sun: DirectionalLight3D
var baseline: Image
var results: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	_build_stage()
	await _frames(6)
	print("PROBE renderer: %s" % RenderingServer.get_current_rendering_method())
	baseline = await _shot("baseline")
	for feature in ["fog_exponential", "fog_height_only", "fog_depth_mode", "glow", "adjust_saturation",
			"adjust_lut_3d", "adjust_lut_1d", "tonemap_aces", "tonemap_agx", "tonemap_exposure",
			"ambient_sky_contribution", "screen_texture_canvas", "depth_texture_spatial"]:
		await _measure(baseline, feature)
	# aerial perspective, sun scatter and sky affect are measured against fog that is already on
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_color = Color(0.9, 0.2, 0.2)
	var fogged := await _shot("fog_reference")
	for feature in ["fog_aerial_perspective", "fog_sun_scatter", "fog_sky_affect"]:
		await _measure(fogged, feature)
	env.fog_enabled = false
	env.fog_light_color = Color(0.518, 0.553, 0.608)
	await _normal_map_convention()
	await _count_lights()
	var f := FileAccess.open("%s/probe.txt" % out_dir, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(results) + "\n")
	quit(0)


func _toggle(feature: String, on: bool) -> void:
	match feature:
		"fog_exponential":
			env.fog_enabled = on
			env.fog_density = 0.004
		"fog_height_only":
			env.fog_enabled = on
			env.fog_density = 0.0 if on else 0.004
			env.fog_height = 6.0
			env.fog_height_density = 0.25 if on else 0.0
		"fog_depth_mode":
			env.fog_enabled = on
			env.fog_mode = Environment.FOG_MODE_DEPTH if on else Environment.FOG_MODE_EXPONENTIAL
			env.fog_density = 1.0 if on else 0.004
			env.fog_depth_begin = 20.0
			env.fog_depth_end = 400.0
		"fog_aerial_perspective":
			env.fog_aerial_perspective = 1.0 if on else 0.0
		"fog_sun_scatter":
			env.fog_sun_scatter = 1.0 if on else 0.0
		"fog_sky_affect":
			env.fog_sky_affect = 0.0 if on else 1.0
		"glow":
			env.glow_enabled = on
			env.glow_intensity = 1.0
			env.glow_bloom = 0.3
			env.glow_hdr_threshold = 0.8
		"adjust_saturation":
			env.adjustment_enabled = on
			env.adjustment_saturation = 0.0 if on else 1.0
		"adjust_lut_3d":
			env.adjustment_enabled = on
			env.adjustment_color_correction = _swap_lut() if on else null
		"adjust_lut_1d":
			env.adjustment_enabled = on
			env.adjustment_color_correction = _invert_ramp() if on else null
		"tonemap_aces":
			env.tonemap_mode = Environment.TONE_MAPPER_ACES if on else Environment.TONE_MAPPER_LINEAR
		"tonemap_agx":
			env.tonemap_mode = Environment.TONE_MAPPER_AGX if on else Environment.TONE_MAPPER_LINEAR
		"tonemap_exposure":
			env.tonemap_exposure = 1.6 if on else 1.0
		"ambient_sky_contribution":
			env.ambient_light_color = Color(1.0, 0.1, 0.1) if on else Color(0, 0, 0)
			env.ambient_light_sky_contribution = 0.0 if on else 1.0
		"screen_texture_canvas":
			if on:
				_add_screen_reader()
			else:
				_remove_named("ScreenReader")
		"depth_texture_spatial":
			if on:
				_add_depth_reader()
			else:
				_remove_named("DepthReader")


# --- the stage ------------------------------------------------------------------------------

func _build_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	stage.add_child(we)
	sun = DirectionalLight3D.new()
	# low and in front of the camera, so sun scatter (which brightens the fog toward the light)
	# has something to show: with the sun behind the lens it draws nothing on any renderer
	sun.rotation_degrees = Vector3(-12.0, 180.0, 0.0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.45, 0.25)
	ground.material_override = gm
	stage.add_child(ground)
	var dists := [8.0, 20.0, 45.0, 90.0, 180.0, 360.0, 700.0]
	for i in dists.size():
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 3.0, 1.0) * (1.0 + float(i) * 1.6)
		b.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(float(i) / 7.0, 0.6, 0.8)
		b.material_override = m
		b.position = Vector3(-6.0 + float(i) * 2.0 * (1.0 + float(i)), bm.size.y * 0.5, -float(dists[i]))
		stage.add_child(b)
	var glow_ball := MeshInstance3D.new()
	var sp := SphereMesh.new()
	glow_ball.mesh = sp
	var em := StandardMaterial3D.new()
	em.emission_enabled = true
	em.emission = Color(1.0, 0.6, 0.2)
	em.emission_energy_multiplier = 8.0
	glow_ball.material_override = em
	glow_ball.position = Vector3(2.0, 1.5, -12.0)
	stage.add_child(glow_ball)
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 2.0, 6.0)
	cam.far = 4000.0
	stage.add_child(cam)
	cam.look_at(Vector3(4.0, 3.0, -100.0))
	cam.current = true


func _swap_lut() -> ImageTexture3D:
	# a 3D LUT that swaps red and blue: impossible to mistake for "no change"
	var n := 16
	var images: Array[Image] = []
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for g in n:
			for r in n:
				img.set_pixel(r, g, Color(float(b) / float(n - 1), float(g) / float(n - 1), float(r) / float(n - 1)))
		images.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGBA8, n, n, n, false, images)
	return tex


func _invert_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1))
	g.set_color(1, Color(0, 0, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func _add_screen_reader() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ScreenReader"
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\n" \
		+ "void fragment() { COLOR = vec4(vec3(1.0) - texture(screen_tex, SCREEN_UV).rgb, 1.0); }\n"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	layer.add_child(rect)
	root.add_child(layer)


func _add_depth_reader() -> void:
	var quad := MeshInstance3D.new()
	quad.name = "DepthReader"
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	quad.mesh = qm
	quad.extra_cull_margin = 16384.0
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled;\n" \
		+ "uniform sampler2D depth_tex : hint_depth_texture;\n" \
		+ "void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }\n" \
		+ "void fragment() { float d = texture(depth_tex, SCREEN_UV).r; ALBEDO = vec3(fract(d * 37.0)); }\n"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	quad.material_override = mat
	stage.add_child(quad)


func _remove_named(node_name: String) -> void:
	var n := root.find_child(node_name, true, false)
	if n:
		n.get_parent().remove_child(n)
		n.free()


# --- measuring ------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw


func _shot(label: String) -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.save_png("%s/probe_%s.png" % [out_dir, label])
	img.resize(W, H, Image.INTERPOLATE_BILINEAR)
	return img


func _measure(reference: Image, feature: String) -> void:
	_toggle(feature, true)
	var img := await _shot(feature)
	_toggle(feature, false)
	var d := _mean_diff(reference, img)
	var line := "PROBE %-26s mean difference %.4f  %s" % [feature, d, "draws" if d > 0.002 else "NOT DRAWN"]
	print(line)
	results.append(line)


static func _mean_diff(a: Image, b: Image) -> float:
	var total := 0.0
	for y in H:
		for x in W:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
	return total / float(W * H)


## What the water shader's first normal did. It wrote a world-space normal, up in green, as
## NORMAL_MAP = n * 0.5 + 0.5. A flat plane under a sun straight overhead is drawn three ways --
## no normal map, that encoding of a flat "up", and the true flat tangent-space value (0.5, 0.5,
## 1) -- and the mean brightness of each is printed. If the first two differ, the encoding tilted
## every water surface in the game.
func _normal_map_convention() -> void:
	for n in stage.get_children():
		if n is MeshInstance3D or n is Light3D:
			(n as Node3D).visible = false
	var over := DirectionalLight3D.new()
	over.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	stage.add_child(over)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40.0, 40.0)
	plane.mesh = pm
	stage.add_child(plane)
	var old_cam := cam.transform
	cam.transform = Transform3D.IDENTITY
	cam.position = Vector3(0.0, 6.0, 8.0)
	cam.look_at(Vector3(0.0, 0.0, -2.0))
	var results_line := "PROBE normal map, flat plane under an overhead sun, mean brightness:"
	for case in ["none", "old_water_encoding", "true_flat"]:
		var sh := Shader.new()
		var body := "ALBEDO = vec3(0.6);"
		if case == "old_water_encoding":
			body += " NORMAL_MAP = vec3(0.0, 1.0, 0.0) * 0.5 + 0.5;"
		elif case == "true_flat":
			body += " NORMAL_MAP = vec3(0.5, 0.5, 1.0);"
		sh.code = "shader_type spatial;\nvoid fragment() { %s }\n" % body
		var mat := ShaderMaterial.new()
		mat.shader = sh
		plane.material_override = mat
		var img := await _shot("normal_%s" % case)
		var total := 0.0
		for y in range(H / 2, H):
			for x in W:
				total += img.get_pixel(x, y).get_luminance()
		results_line += " %s %.3f" % [case, total / float(W * (H - H / 2))]
	print(results_line)
	results.append(results_line)
	plane.queue_free()
	over.queue_free()
	cam.transform = old_cam
	for n in stage.get_children():
		if n is MeshInstance3D or n is Light3D:
			(n as Node3D).visible = true


func _count_lights() -> void:
	await _frames(4)
	var base := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var lights: Array[OmniLight3D] = []
	for i in 8:
		var l := OmniLight3D.new()
		l.omni_range = 10.0
		l.light_energy = 2.0
		l.position = Vector3(-8.0 + float(i) * 2.5, 1.5, -10.0 - float(i))
		stage.add_child(l)
		lights.append(l)
	await _frames(4)
	var eight := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	lights[0].shadow_enabled = true
	await _frames(4)
	var shadowed := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-40.0, -60.0, 0.0)
	moon.shadow_enabled = true
	stage.add_child(moon)
	await _frames(4)
	var two_suns := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var line := "PROBE draw calls: no omni %d, eight unshadowed %d, one of them shadowed %d, plus a second shadowed directional %d" \
		% [base, eight, shadowed, two_suns]
	print(line)
	results.append(line)
