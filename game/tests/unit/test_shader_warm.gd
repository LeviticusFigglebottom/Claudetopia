extends TestCase
## The warm set the export's shader baker compiles (tools_gd/material_census.gd,
## assets/shader_warm/warm_set.tres, docs/FIRST_LAUNCH.md): a material's key is what decides its
## shader and nothing else, its warm copy keeps that key without its pictures, and the committed set
## loads, holds one material per key and covers the shaders the game builds in code.

const WARM_SET := "res://assets/shader_warm/warm_set.tres"


func test_the_key_is_the_shader_not_the_colours() -> void:
	var a := StandardMaterial3D.new()
	var b := StandardMaterial3D.new()
	b.albedo_color = Color(0.2, 0.9, 0.1)
	b.roughness = 0.1
	b.uv1_scale = Vector3(4, 4, 4)
	b.render_priority = 3
	assert_eq(MaterialCensus.key_of(a), MaterialCensus.key_of(b), "colours, floats, vectors and the priority do not change the shader")
	b.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	assert_ne(MaterialCensus.key_of(a), MaterialCensus.key_of(b), "the transparency does")
	var c := StandardMaterial3D.new()
	c.vertex_color_use_as_albedo = true
	assert_ne(MaterialCensus.key_of(a), MaterialCensus.key_of(c), "a flag does")
	var d := StandardMaterial3D.new()
	d.normal_enabled = true
	var e := d.duplicate() as StandardMaterial3D
	e.normal_texture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	assert_ne(MaterialCensus.key_of(d), MaterialCensus.key_of(e), "whether a texture slot is set does")
	assert_ne(MaterialCensus.key_of(a), MaterialCensus.key_of(ORMMaterial3D.new()), "and the class")


func test_a_shader_material_is_keyed_by_its_file_or_its_code() -> void:
	var a := ShaderMaterial.new()
	a.shader = WaterSurface.shader_for(true)
	var b := ShaderMaterial.new()
	b.shader = WaterSurface.shader_for(true)
	b.set_shader_parameter("mirror", 0.0)
	assert_eq(MaterialCensus.key_of(a), MaterialCensus.key_of(b), "its parameters do not change the shader")
	assert_true(MaterialCensus.key_of(a).ends_with(WaterSurface.shader_for(true).resource_path), "a shader from a file is known by its path")
	var c := ShaderMaterial.new()
	c.shader = WaterSurface.shader_for(false)
	assert_true(MaterialCensus.key_of(c).contains("code:"), "one made in code is known by its code")
	assert_ne(MaterialCensus.key_of(a), MaterialCensus.key_of(c), "and the two differ")
	assert_eq(MaterialCensus.key_of(ShaderMaterial.new()), "", "a ShaderMaterial with no shader has nothing to bake")


func test_the_warm_copy_keeps_the_key_without_the_pictures() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	m.normal_enabled = true
	m.normal_texture = m.albedo_texture
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.next_pass = StandardMaterial3D.new()
	var w := MaterialCensus.warm_copy(m) as StandardMaterial3D
	assert_eq(MaterialCensus.key_of(w), MaterialCensus.key_of(m), "the same key")
	assert_true(w.albedo_texture is PlaceholderTexture2D, "its texture is a placeholder (%s)" % str(w.albedo_texture))
	assert_true(w.albedo_texture == w.normal_texture, "one shared placeholder")
	assert_eq(w.next_pass, null, "its next pass is a material of its own, not carried")
	var water := ShaderMaterial.new()
	water.shader = WaterSurface.shader_for(false, true)
	var ww := MaterialCensus.warm_copy(water) as ShaderMaterial
	assert_eq(ww.shader.code, water.shader.code, "a shader made in code is copied as code")
	assert_eq(MaterialCensus.key_of(ww), MaterialCensus.key_of(water), "and keeps its key")


func test_a_label_is_warmed_with_the_material_godot_makes_for_it() -> void:
	var label := Label3D.new()
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	var mats := MaterialCensus.materials_of(label)
	assert_eq(mats.size(), 1, "one material, made from its flags")
	var m := mats[0] as StandardMaterial3D
	assert_eq(m.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "cut, not blended")
	assert_eq(m.shading_mode, BaseMaterial3D.SHADING_MODE_PER_PIXEL, "shaded")
	assert_eq(m.cull_mode, BaseMaterial3D.CULL_BACK, "one-sided")
	assert_true(m.vertex_color_use_as_albedo and m.vertex_color_is_srgb, "its colour from the vertices")
	label.free()


func test_the_committed_set_holds_one_material_a_key_and_the_code_made_shaders() -> void:
	if not ResourceLoader.exists(WARM_SET):
		fail("%s is missing: ./run.sh shader-warm writes it" % WARM_SET)
		return
	var ws := load(WARM_SET) as ShaderWarmSet
	assert_true(ws != null, "it loads as a ShaderWarmSet")
	if ws == null:
		return
	assert_gt(ws.materials.size(), 40, "it holds the census's materials (%d)" % ws.materials.size())
	var keys := {}
	var dupes: Array[String] = []
	for m in ws.materials:
		var k := MaterialCensus.key_of(m)
		if keys.has(k):
			dupes.append(k.substr(0, 120))
		keys[k] = true
	assert_eq(dupes, [] as Array[String], "one material a key")
	for mirrored in [true, false]:
		for river in [false, true]:
			var m := ShaderMaterial.new()
			m.shader = WaterSurface.shader_for(mirrored, river)
			assert_true(keys.has(MaterialCensus.key_of(m)), "the water's shader with mirror %s, river %s is in it" % [mirrored, river])
	var embedded: Array[String] = []
	for m in ws.materials:
		for p: Dictionary in m.get_property_list():
			if int(p["type"]) == TYPE_OBJECT:
				var v: Variant = m.get(str(p["name"]))
				if v is Texture and not (v is PlaceholderTexture2D or v is PlaceholderTexture3D \
						or v is PlaceholderTexture2DArray or v is PlaceholderCubemap or v is PlaceholderCubemapArray):
					embedded.append("%s.%s" % [m.get_class(), str(p["name"])])
	assert_eq(embedded, [] as Array[String], "no picture is carried, only placeholders")
