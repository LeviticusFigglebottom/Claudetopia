extends Node3D
## The same tree at each level of detail, side by side, at the distances the streamer switches
## them -- lit by the game's own atmosphere, drawn through the streamer's own LOD code.
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1600x900 res://tools_gd/lod_review.tscn -- \
##     --out=<abs dir> --assets=hearthvale_oak_a,hearthvale_hawthorn_a [--distances=20,40,70,100] \
##     [--region=core:region/hearthvale] [--time=10] [--sweep | --calibrate]
##
## For each asset and distance it writes <asset>_<d>m.png: three copies of the tree the same
## distance away, left to right the full mesh (level 0), the forge's LOD1 (level 1) and the
## impostor, with no dissolve, so a difference between them is a difference you would see at
## that distance. `--sweep` adds <asset>_sweep.png: a row of the tree receding from 15 m to 300 m
## sorted by the real `ScatterLod.Group.update`, dissolves and all, which is how it looks in
## the world. The camera is at eye height with the street plan's 58 degree field of view, and
## each image is cropped to the trees and doubled so a pixel of difference is visible.
##
## `--calibrate` instead stands every tree (or the `--assets` named) at its own picture distance
## in its own region's light, nudges the picture's colour gain and alpha cut until it matches
## LOD1 beside it, writes ScatterLod.CALIBRATION, and leaves <asset>_calibrated.png to look at.

const TREES := "res://assets/models/trees"
const ATMOSPHERE := "res://systems/atmosphere/atmosphere.tscn"
## The hour each region is reviewed at (the street plan's), so a tree is calibrated in the light it
## is most often looked at in.
const REGION_HOURS := {"hearthvale": 9.0, "brightwater": 12.0, "sedgemire": 7.5, "briarwold": 10.5,
		"skerrow": 14.0, "cinderlea": 16.5}

var out_dir := "user://lod_review"
var assets: PackedStringArray = ["hearthvale_oak_a", "hearthvale_hawthorn_a"]
var distances: Array = [20.0, 35.0, 50.0, 70.0, 100.0, 150.0]
var region := "core:region/hearthvale"
var hour := 10.0
var sweep := false
## `--calibrate`: for every tree (or `--assets`), match its picture to its LOD1 at its own switch
## distance, in its own region's light, and write the gains to ScatterLod.CALIBRATION.
var calibrate := false
var cam: Camera3D
var _stage: Node3D = null
var _atmos: Node = null


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
		elif a == "--calibrate":
			calibrate = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	_ground()
	_atmos = (load(ATMOSPHERE) as PackedScene).instantiate()
	add_child(_atmos)
	_light(region, hour)
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.1
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	if calibrate:
		await _calibrate_all()
		get_tree().quit(0)
		return
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


func _light(region_id: String, at_hour: float) -> void:
	# the clock stands still: a sky that moves between a plate and its shot is counted as tree
	WorldClock.running = false
	WorldClock.set_time(at_hour)
	if _atmos.has_method("set_region"):
		_atmos.call("set_region", region_id, true)
	if _atmos.has_method("force_weather"):
		_atmos.call("force_weather", "core:weather/clear", true)


## Every tree with a picture, or the ones named, calibrated in turn; the file is written after each.
func _calibrate_all() -> void:
	var names: Array = []
	if Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--assets=")):
		names = Array(assets)
	else:
		for d in DirAccess.get_directories_at(TREES):
			names.append(d)
	# region by region, so the light is changed six times and has settled before each tree
	names.sort_custom(func(a: String, b: String) -> bool:
			return [_region_of(a), a] < [_region_of(b), b])
	var out: Dictionary = ScatterLod.calibration().duplicate(true)
	var lit := ""
	for n in names:
		var path := "%s/%s/%s.glb" % [TREES, n, n]
		if not ResourceLoader.exists(path):
			continue
		var region_short := _region_of(n)
		if region_short != lit:
			lit = region_short
			_light("core:region/%s" % region_short, float(REGION_HOURS.get(region_short, 10.0)))
			# the sky's light is gathered over many frames (Sky.PROCESS_MODE_INCREMENTAL)
			for i in 150:
				await get_tree().process_frame
		var result: Dictionary = await _calibrate(path)
		if not result.is_empty():
			var entry: Dictionary = out.get(n, {})
			entry[Graphics.renderer()] = result
			out[n] = entry
			# after every tree, so a run cut short keeps what it measured
			_write_calibration(out)
	_write_calibration(out)
	print("CALIBRATION written: %d trees" % out.size())


func _write_calibration(out: Dictionary) -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path(ScatterLod.CALIBRATION), FileAccess.WRITE)
	if f == null:
		push_error("lod_review: cannot write %s" % ScatterLod.CALIBRATION)
		return
	f.store_string(JSON.stringify(out, "  ", true) + "\n")
	f.close()


## One tree: three copies at LOD1 and three as the picture, in pairs turned to three sides, at the tree's
## own switch distance. The picture's colour gain and alpha cut are nudged until the ink it adds
## to the view and its pixel coverage match the mesh's, over four passes against an empty plate.
func _calibrate(path: String) -> Dictionary:
	var name := path.get_file().get_basename()
	var meta := ScatterLod._meta(path)
	var region_short := _region_of(name)
	await _clear()
	var lad := _ladder(path)
	if lad == null or not lad.has_impostor():
		return {}
	for level in lad.leaf_materials:
		for m in level:
			(m as ShaderMaterial).set_shader_parameter("lod_fade_in", Vector2.ZERO)
			(m as ShaderMaterial).set_shader_parameter("lod_fade_out", Vector2.ZERO)
	lad.impostor_material.set_shader_parameter("lod_fade_in", Vector2.ZERO)
	var d := lad.far
	var b: Dictionary = meta.get("bounds", {})
	var lo: Array = b.get("min", [-2, 0, -2])
	var hi: Array = b.get("max", [2, 4, 2])
	var width := maxf(float(hi[0]) - float(lo[0]), float(hi[2]) - float(lo[2]))
	var height := float(b.get("height", 4.0))
	var gap := width * 1.5
	var rows: Array = []
	for i in 6:
		rows.append([(float(i) - 2.5) * gap, 0.0, -d, [0.0, 0.0, 120.0, 120.0, 240.0, 240.0][i], 1.0, "#ffffff"])
	var g := ScatterLod.make_group(lad, _stage, rows, false, true, 100000.0, path)
	cam.position = Vector3(0.0, 1.7, 0.0)
	cam.look_at(Vector3(0.0, height * 0.5, -d))
	_put(g, "solid1", [0, 2, 4])
	_put(g, "leaves1", [0, 2, 4])
	_put(g, "impostor", [1, 3, 5])
	var prior: Dictionary = ScatterLod.calibration_for(name)
	var gain_a: Array = prior.get("gain", [1.0, 1.0, 1.0])
	# One gain for all three channels: a brightness, never a hue. The mesh's far colour is partly
	# the sky seen through twigs thinner than a pixel, and a picture given a hue to match that
	# comes out wrong in itself: a blue gain turned a black ash's crown cream and a pollard's bark
	# lilac. The picture keeps the colours Cycles gave it, and matches the mesh in how much it
	# darkens the view.
	var bright := clampf(float(gain_a[1]), 0.5, 2.0)
	var scissor := float(prior.get("alpha_scissor", 0.45))
	# the best pass is kept, not the last: tonemapping can make a pass overshoot
	var best := {}
	var best_err := INF
	var best_img: Image = null
	for it in 4:
		var gain := Color(bright, bright, bright)
		lad.impostor_material.set_shader_parameter("tint", gain)
		lad.impostor_material.set_shader_parameter("alpha_scissor", scissor)
		# a fresh empty plate every pass, the trees hidden, so only the trees differ from it
		_stage.visible = false
		var plate := await _shot(6)
		_stage.visible = true
		var img := await _shot(6)
		var mesh_m := _mean_of(plate, img, [0, 2, 4], gap, width, height, d)
		var pic_m := _mean_of(plate, img, [1, 3, 5], gap, width, height, d)
		var mesh_c: Vector3 = mesh_m["colour"]
		var pic_c: Vector3 = pic_m["colour"]
		var mesh_ink: Vector3 = mesh_m["ink"]
		var pic_ink: Vector3 = pic_m["ink"]
		print("CALIB %s pass %d: mesh px %d ink (%.0f %.0f %.0f) | picture px %d ink (%.0f %.0f %.0f) | gain (%.2f %.2f %.2f) cut %.2f" % [
				name, it, int(mesh_m["count"]), mesh_ink.x, mesh_ink.y, mesh_ink.z, int(pic_m["count"]),
				pic_ink.x, pic_ink.y, pic_ink.z, gain.r, gain.g, gain.b, scissor])
		if int(pic_m["count"]) == 0 or int(mesh_m["count"]) == 0:
			break
		var cov := float(mesh_m["count"]) / float(pic_m["count"])
		# the colour the picture's own pixels would need for its ink to be the mesh's
		var want: Vector3 = (pic_m["behind"] as Vector3) + mesh_ink / float(pic_m["count"])
		want = want.clamp(Vector3(0.005, 0.005, 0.005), Vector3.ONE)
		var lum := Vector3(0.2126, 0.7152, 0.0722)
		var ink_err := absf(mesh_ink.dot(lum) - pic_ink.dot(lum)) / maxf(absf(mesh_ink.dot(lum)), 1.0)
		var err := ink_err + 0.2 * absf(cov - 1.0)
		if err < best_err:
			best_err = err
			best_img = img
			best = {"gain": [snappedf(gain.r, 0.001), snappedf(gain.g, 0.001), snappedf(gain.b, 0.001)],
					"alpha_scissor": snappedf(scissor, 0.001), "distance_m": snappedf(d, 0.1),
					"light": "%s %.1f h" % [region_short, float(REGION_HOURS.get(region_short, 10.0))],
					"mesh_rgb": [snappedf(mesh_c.x, 0.001), snappedf(mesh_c.y, 0.001), snappedf(mesh_c.z, 0.001)],
					"picture_rgb": [snappedf(pic_c.x, 0.001), snappedf(pic_c.y, 0.001), snappedf(pic_c.z, 0.001)],
					"coverage": [int(mesh_m["count"]), int(pic_m["count"])],
					"ink_error": snappedf(ink_err, 0.001)}
		# screen colour is tonemapped, so a ratio is only a direction: iterate towards it
		var l_want := want.x * 0.2126 + want.y * 0.7152 + want.z * 0.0722
		var l_pic := maxf(pic_c.x * 0.2126 + pic_c.y * 0.7152 + pic_c.z * 0.0722, 0.005)
		bright = clampf(bright * clampf(l_want / l_pic, 0.75, 1.33), 0.5, 2.0)
		# coverage: a lower cut keeps more of the picture's softened edge
		scissor = clampf(scissor - (cov - 1.0) * 0.35, 0.3, 0.6)
	if best_img != null:
		_save_crop(best_img, Vector3(-3.0 * gap, 0.0, -d), Vector3(3.0 * gap, height * 1.1, -d),
				"%s_calibrated" % name)
	return best


## The region a tree grows in, by its forge name.
func _region_of(tree_name: String) -> String:
	var r := tree_name.get_slice("_", 0)
	return r if REGION_HOURS.has(r) else "hearthvale"


## Several trees of the calibration row measured together, against the empty plate:
##   "count"  pixels the trees changed at all (the silhouette),
##   "ink"    the summed change, per channel (what the trees add to the view),
##   "colour" their mean colour, and "behind" the plate's mean under them.
## Ink is what a dissolve has to keep: while it runs, every pixel of the tree is one level or the
## other, so the view stays the same only if both levels change it by the same total. A far
## mesh is dark leaves and branches thinner than a pixel, blended with the sky between them; its
## picture is fewer, solider pixels. Matching their mean colours makes the picture pale; matching
## their ink makes the two look alike from where they are seen.
func _mean_of(plate: Image, img: Image, which: Array, gap: float, width: float, height: float,
		d: float) -> Dictionary:
	var ink := Vector3.ZERO
	var sum := Vector3.ZERO
	var under := Vector3.ZERO
	var count := 0
	var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	for i in which:
		var x := (float(i) - 2.5) * gap
		# from just above eye height (or the crown of a shrub shorter than that): below it the
		# ground shows behind the tree, and a neighbour's shadow on that ground is not its colour
		var a := cam.unproject_position(Vector3(x - width * 0.65, minf(1.8, height * 0.4), -d)) * k
		var b := cam.unproject_position(Vector3(x + width * 0.65, height * 1.08, -d)) * k
		var rect := Rect2i(Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs()))
		rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		for y in range(rect.position.y, rect.end.y):
			for px in range(rect.position.x, rect.end.x):
				var c := img.get_pixel(px, y)
				var q := plate.get_pixel(px, y)
				if absf(c.r - q.r) + absf(c.g - q.g) + absf(c.b - q.b) <= 0.06:
					continue
				var cv := Vector3(c.r, c.g, c.b)
				var qv := Vector3(q.r, q.g, q.b)
				ink += cv - qv
				sum += cv
				under += qv
				count += 1
	var n := float(maxi(count, 1))
	return {"count": count, "ink": ink, "colour": sum / n, "behind": under / n}


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


func _shot(frames := 12) -> Image:
	for i in frames:
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
