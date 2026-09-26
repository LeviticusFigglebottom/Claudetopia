extends TestCase
## Every landmark the world stands up (a cell's `scenes`) is drawn in its own painted picture and
## none of it is blue. The Choir's first colossi took the region palette's "cool" role and stood on
## the ash as slate-blue ribbed tanks on a blue ring (the user's screenshot, 2026-09-26); the
## graphics test (test_no_blue_box) walks only the scatter, so a landmark could go blue unseen.
## Each surface of each level has a material with a picture, and the picture's mean colour (read
## from the forge's albedo, linear) is no bluer than stone is.

const CELLS := "res://world/generated/cells"
## blue over red at the most, linear: grey granite is 1.0 to 1.1; the blue colossi were 1.4
const BLUE_MAX := 1.12
const COLOSSUS := "res://assets/models/landmarks/cinderlea_choir_colossus_a/cinderlea_choir_colossus_a.glb"


func _landmarks() -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(CELLS):
		return out
	for file in DirAccess.get_files_at(CELLS):
		if not file.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CELLS, file]))
		if not (parsed is Dictionary):
			continue
		for entry_v in (parsed as Dictionary).get("scenes", []):
			if entry_v is Dictionary:
				var path := str((entry_v as Dictionary).get("scene", ""))
				if path.contains("/models/landmarks/") and not out.has(path):
					out.append(path)
	return out


## The mean of a forge albedo, linear, straight from its PNG (the imported texture may be compressed
## where a headless run cannot read it back).
static func mean_of(png: String) -> Color:
	var img := Image.load_from_file(ProjectSettings.globalize_path(png))
	if img == null or img.is_empty():
		return Color(0, 0, 0, 0)
	img.convert(Image.FORMAT_RGBA8)
	img.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	var sum := Vector3.ZERO
	for y in 32:
		for x in 32:
			var c := img.get_pixel(x, y).srgb_to_linear()
			sum += Vector3(c.r, c.g, c.b)
	sum /= 1024.0
	return Color(sum.x, sum.y, sum.z, 1.0)


func _albedo_of(mat: Material) -> Texture2D:
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).albedo_texture
	if mat is ShaderMaterial:
		var t: Variant = (mat as ShaderMaterial).get_shader_parameter("albedo_texture")
		return t as Texture2D
	return null


func test_every_landmark_is_painted_and_none_is_blue() -> void:
	var paths := _landmarks()
	if paths.is_empty():
		skip("no built world in %s" % CELLS)
		return
	var checked := 0
	for path in paths:
		var packed := PoiKit.scene(path)
		if packed == null:
			continue
		var inst := packed.instantiate()
		var nm := path.get_file().get_basename()
		for mi_v in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := mi_v as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_surface_override_material(s)
				if mat == null:
					mat = mi.mesh.surface_get_material(s)
				assert_true(mat != null, "%s %s surface %d has a material" % [nm, mi.name, s])
				var tex := _albedo_of(mat)
				assert_true(tex != null, "%s %s surface %d has a picture" % [nm, mi.name, s])
		inst.free()
		var png := path.get_base_dir() + "/" + nm + "_albedo.png"
		if FileAccess.file_exists(png):
			var m := mean_of(png)
			assert_true(m.a > 0.0, "%s's albedo reads" % nm)
			assert_true(m.b <= m.r * BLUE_MAX, "%s is not blue (its picture's blue is %.2f times its red)"
					% [nm, m.b / maxf(m.r, 1e-4)])
			checked += 1
	assert_gt(checked, 5, "the landmarks' pictures were read (%d)" % checked)


func test_the_choir_is_warm_grey_stone() -> void:
	var png := COLOSSUS.get_base_dir() + "/" + COLOSSUS.get_file().get_basename() + "_albedo.png"
	if not FileAccess.file_exists(png):
		skip("the colossus is not built")
		return
	var m := mean_of(png)
	assert_true(m.r >= m.b, "warm, not cool: red %.3f, blue %.3f" % [m.r, m.b])
	var lum := (m.r + m.g + m.b) / 3.0
	assert_true(lum > 0.05 and lum < 0.4, "a mid grey, neither black glass nor white paper (%.3f)" % lum)
