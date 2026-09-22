extends Node3D
## The same tree at each level of detail, side by side, at the distances the streamer switches
## them -- lit by the game's own atmosphere, drawn through the streamer's own LOD code.
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1600x900 res://tools_gd/lod_review.tscn -- \
##     --out=<abs dir> --assets=hearthvale_oak_a,hearthvale_hawthorn_a [--distances=20,40,70,100] \
##     [--region=core:region/hearthvale] [--time=10] [--sweep]
##
## For each asset and distance it writes <asset>_<d>m.png: three copies of the tree the same
## distance away, left to right the full mesh (level 0), the forge's LOD1 (level 1) and the
## impostor, with no dissolve, so a difference between them is a difference you would see at
## that distance. `--sweep` adds <asset>_sweep.png: a row of the tree receding from 15 m to 300 m
## sorted by the real `ScatterLod.Group.update`, dissolves and all, which is how it looks in
## the world. The camera is at eye height with the street plan's 58 degree field of view, and
## each image is cropped to the trees and doubled so a pixel of difference is visible.

const TREES := "res://assets/models/trees"
const ATMOSPHERE := "res://systems/atmosphere/atmosphere.tscn"

var out_dir := "user://lod_review"
var assets: PackedStringArray = ["hearthvale_oak_a", "hearthvale_hawthorn_a"]
var distances: Array = [20.0, 35.0, 50.0, 70.0, 100.0, 150.0]
var region := "core:region/hearthvale"
var hour := 10.0
var sweep := false
var cam: Camera3D
var _stage: Node3D = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--assets="):
			assets = a.substr(9).split(",", false)
		elif a.begins_with("--distances="):
			distances = []
			for part in a.substr(12).split(",", false):
				distances.append(float(part))
		elif a.begins_with("--region="):
			region = a.substr(9)
		elif a.begins_with("--time="):
			hour = float(a.substr(7))
		elif a == "--sweep":
			sweep = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	_ground()
	var atmos: Node = (load(ATMOSPHERE) as PackedScene).instantiate()
	add_child(atmos)
	WorldClock.set_time(hour)
	if atmos.has_method("set_region"):
		atmos.call("set_region", region, true)
	if atmos.has_method("force_weather"):
		atmos.call("force_weather", "core:weather/clear", true)
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.1
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	for asset in assets:
		var path := "%s/%s/%s.glb" % [TREES, asset, asset]
		if not ResourceLoader.exists(path):
			push_error("lod_review: no tree %s" % path)
			continue
		for d in distances:
			await _side_by_side(path, float(d))
		if sweep:
			await _sweep(path)
	get_tree().quit(0)


func _ground() -> void:
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	plane.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.42, 0.20)
	mat.roughness = 1.0
	plane.material_override = mat
	add_child(plane)


func _clear() -> void:
	if _stage != null and is_instance_valid(_stage):
		_stage.queue_free()
	_stage = Node3D.new()
	add_child(_stage)
	await get_tree().process_frame


func _ladder(path: String) -> ScatterLod.Ladder:
	var lad := ScatterLod._build_ladder(path, load(path) as PackedScene)
	if lad != null:
		lad.set_bias(1.0)
	return lad


func _row(x: float, z: float) -> Array:
	return [x, 0.0, z, 0.0, 1.0, "#ffffff"]


## Three copies at `d` metres: full mesh, LOD1, impostor, dissolves switched off.
func _side_by_side(path: String, d: float) -> void:
	await _clear()
	var lad := _ladder(path)
	if lad == null:
		return
	for level in lad.leaf_materials:
		for m in level:
			(m as ShaderMaterial).set_shader_parameter("lod_fade_in", Vector2.ZERO)
			(m as ShaderMaterial).set_shader_parameter("lod_fade_out", Vector2.ZERO)
	if lad.impostor_material != null:
		lad.impostor_material.set_shader_parameter("lod_fade_in", Vector2.ZERO)
	var meta := ScatterLod._meta(path)
	var b: Dictionary = meta.get("bounds", {})
	var lo: Array = b.get("min", [-2, 0, -2])
	var hi: Array = b.get("max", [2, 4, 2])
	var width := maxf(float(hi[0]) - float(lo[0]), float(hi[2]) - float(lo[2]))
	var height := float(b.get("height", 4.0))
	var gap := width * 1.25
	var rows := [_row(-gap, -d), _row(0.0, -d), _row(gap, -d)]
	var g := ScatterLod.make_group(lad, _stage, rows, false, true, 100000.0, path)
	cam.position = Vector3(0.0, 1.7, 0.0)
	cam.look_at(Vector3(0.0, height * 0.5, -d))
	# the empty stage first: what a tree changes against it is what the tree looks like
	var plate := await _shot()
	_put(g, "solid0", [0])
	_put(g, "leaves0", [0])
	_put(g, "solid1", [1])
	_put(g, "leaves1", [1])
	_put(g, "impostor", [2])
	var img := await _shot()
	var name := "%s_%03dm" % [path.get_file().get_basename(), int(d)]
	_save_crop(img, Vector3(-gap - width, 0.0, -d), Vector3(gap + width, height * 1.1, -d), name)
	var stats: Array[String] = []
	for i in 3:
		var x := (float(i) - 1.0) * gap
		var m := _mean_change(plate, img, Vector3(x - width * 0.55, 0.0, -d),
				Vector3(x + width * 0.55, height * 1.05, -d))
		stats.append("%s rgb(%.3f %.3f %.3f) lum %.3f px %d" % [["full", "lod1", "impostor"][i],
				m.r, m.g, m.b, m.get_luminance(), int(m.a)])
	print("LODSTATS %s %dm | %s" % [path.get_file().get_basename(), int(d), " | ".join(stats)])


## The mean colour of the pixels a tree changed against the empty plate, inside its box on
## screen; alpha carries how many pixels that was.
func _mean_change(plate: Image, img: Image, lo: Vector3, hi: Vector3) -> Color:
	var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var a := cam.unproject_position(lo) * k
	var b := cam.unproject_position(hi) * k
	var rect := Rect2i(Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs()))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var sum := Vector3.ZERO
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := img.get_pixel(x, y)
			var p := plate.get_pixel(x, y)
			if absf(c.r - p.r) + absf(c.g - p.g) + absf(c.b - p.b) > 0.06:
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	if n == 0:
		return Color(0, 0, 0, 0)
	sum /= float(n)
	return Color(sum.x, sum.y, sum.z, float(n))


func _put(g: ScatterLod.Group, slot: String, idx: Array) -> void:
	if not g.mmis.has(slot):
		return
	var list := PackedInt32Array(idx)
	ScatterLod._fill(g.mmis[slot] as MultiMeshInstance3D, g.rows, list)


## A row receding from 15 m to 300 m, a little to the side, sorted the way the world sorts it.
func _sweep(path: String) -> void:
	await _clear()
	var lad := _ladder(path)
	if lad == null:
		return
	# fanned across the view, nearest on the left, so no tree stands in front of another
	var rows: Array = []
	var dists: Array = []
	var d := 15.0
	while d <= 300.0:
		dists.append(d)
		d *= 1.22
	for i in dists.size():
		var bearing := deg_to_rad(lerpf(-36.0, 36.0, float(i) / float(maxi(dists.size() - 1, 1))))
		rows.append(_row(sin(bearing) * float(dists[i]), -cos(bearing) * float(dists[i])))
	var g := ScatterLod.make_group(lad, _stage, rows, false, true, 100000.0, path)
	cam.position = Vector3(0.0, 1.7, 0.0)
	cam.look_at(Vector3(0.0, 1.7, -100.0))
	await get_tree().process_frame
	g.update(cam.global_position)
	var img := await _shot()
	img.save_png("%s/%s_sweep.png" % [out_dir, path.get_file().get_basename()])


func _shot() -> Image:
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _save_crop(img: Image, lo: Vector3, hi: Vector3, name: String) -> void:
	# The project stretches its 1280x720 base to the window, so the camera answers in base
	# coordinates and the image is the window's size.
	var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var a := cam.unproject_position(lo) * k
	var b := cam.unproject_position(hi) * k
	var rect := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs()).grow(12.0)
	rect = rect.intersection(Rect2(Vector2.ZERO, Vector2(img.get_size())))
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		img.save_png("%s/%s.png" % [out_dir, name])
		return
	var crop := img.get_region(Rect2i(rect))
	var scale := clampf(480.0 / rect.size.y, 1.0, 4.0)
	crop.resize(int(rect.size.x * scale), int(rect.size.y * scale), Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [out_dir, name])
