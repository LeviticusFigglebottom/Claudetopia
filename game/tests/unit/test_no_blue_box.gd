extends TestCase
## No mesh the world draws is untextured or blue. A playtest saw "a blue box" on Hearthvale's
## hillsides: the forge's cool tint had painted Cinderlea's cliff ledges slate blue (their mean
## albedo twice as blue as red), and a sea cliff's ledges run over the border into Hearthvale,
## where, dark and lit mostly by the sky, they stood as navy boxes; Brightwater's lake-stone slabs
## and boulders were bluer still. RockPaint now leans a blue stone's hue to its country's
## (RockPaint.hue_pull_for). This walks every asset every cell of the built world scatters, as the
## streamer loads it, and checks each surface of the mesh it draws: it has a material, the material
## has a picture (or a colour of its own), and a stone is drawn no bluer than stone is, in every
## region it stands in.

const CELLS := "res://world/generated/cells"
## A stone's drawn mean (linear), blue over red, at the most: grey granite and slate are 1.0 to
## 1.1; the navy ledges were 1.33 in Hearthvale and 1.53 at home, the slabs 2.
const BLUE_MAX := 1.15
const LEDGE := "res://assets/models/rocks/cinderlea_cliff_ledge_a/cinderlea_cliff_ledge_a.glb"
const GRANITE := "res://assets/models/rocks/briarwold_boulder_a/briarwold_boulder_a.glb"


## Every asset the cells scatter, and the regions whose cells it stands in.
func _scattered() -> Dictionary:
	var out := {}
	var dir := DirAccess.open(CELLS)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CELLS + "/" + file))
		if not (parsed is Dictionary):
			continue
		var region := str((parsed as Dictionary).get("region", "")).get_slice("/", 1)
		var inst: Variant = (parsed as Dictionary).get("instances", {})
		if not (inst is Dictionary):
			continue
		for path in inst:
			if not out.has(path):
				out[path] = {}
			out[path][region] = true
	return out


func test_every_mesh_the_world_scatters_is_textured_and_no_stone_is_blue() -> void:
	var assets := _scattered()
	if assets.is_empty():
		skip("no built world in %s" % CELLS)
		return
	var streamer := WorldStreamer.new()
	streamer.lod_enabled = false
	var checked := 0
	var stones := 0
	for path in assets:
		var mesh := streamer._mesh_for(str(path), 0)
		if mesh == null:
			continue
		checked += 1
		var nm := str(path).get_file().get_basename()
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			assert_true(mat != null, "%s surface %d has a material (none draws in the engine's default)" % [nm, s])
			if mat is StandardMaterial3D:
				var std := mat as StandardMaterial3D
				var textured := std.albedo_texture != null or std.vertex_color_use_as_albedo
				assert_true(textured or std.albedo_color != Color.WHITE,
						"%s surface %d (%s) has a picture or a colour of its own" % [nm, s, std.resource_name])
				if not textured and not str(path).contains("/flora/"):
					var c := std.albedo_color.srgb_to_linear()
					assert_true(c.b <= c.r * BLUE_MAX + 0.01,
							"%s surface %d is not a flat blue (%s)" % [nm, s, std.albedo_color.to_html(false)])
			elif mat is ShaderMaterial and (mat as ShaderMaterial).shader == RockPaint.SHADER:
				assert_true((mat as ShaderMaterial).get_shader_parameter("albedo_texture") is Texture2D,
						"%s surface %d keeps the forge's picture" % [nm, s])
		if RockPaint.mean_of(str(path), Color.WHITE).a > 0.0 and RockPaint.stone_of(str(path)) not in RockPaint.NOT_STONE:
			stones += 1
			for region in assets[path]:
				var d := RockPaint.drawn_mean(str(path), str(region))
				assert_true(d.b <= d.r * BLUE_MAX,
						"%s in %s is drawn stone, not blue (blue %.2f times its red)" % [nm, region, d.b / maxf(d.r, 1e-4)])
	streamer.free()
	assert_gt(checked, 100, "the world's scatter was found and loaded (%d assets)" % checked)
	assert_gt(stones, 20, "and its stones among them (%d)" % stones)


func test_the_slate_blue_ledge_leans_to_the_country_and_grey_granite_keeps_its_own() -> void:
	if not ResourceLoader.exists(LEDGE) or not ResourceLoader.exists(GRANITE):
		skip("the forge's ledge or boulder is not built")
		return
	var ledge := RockPaint.mean_of(LEDGE, Color.WHITE)
	assert_gt(ledge.b, ledge.r * 1.6, "the forge painted the ledge slate blue (the case this guards)")
	var m := PoiKit.scene(LEDGE)
	var mat: Material = null
	var state := m.get_state()
	for i in state.get_node_count():
		for p in state.get_node_property_count(i):
			var v: Variant = state.get_node_property_value(i, p)
			if mat == null and state.get_node_property_name(i, p) == "mesh" and v is Mesh:
				mat = (v as Mesh).surface_get_material(0)
	assert_true(mat is ShaderMaterial, "the ledge is the painted stone")
	assert_near(float((mat as ShaderMaterial).get_shader_parameter("hue_pull")), 1.0, 0.01,
			"its hue goes the whole way to the country's")
	var d := RockPaint.drawn_mean(LEDGE, "hearthvale")
	assert_true(d.b <= d.r, "on Hearthvale's hillside it is drawn in Hearthvale's warm stone")
	assert_near(RockPaint.hue_pull_for(RockPaint.mean_of(GRANITE, Color.WHITE)), 0.0, 0.0001,
			"a grey granite keeps its own hue")
