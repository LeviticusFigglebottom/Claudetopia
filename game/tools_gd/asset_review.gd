extends Node3D
## Asset lineup renderer. Loads a category (or an explicit list of GLBs), lines the models
## up on a neutral stage, and writes PNGs from three camera angles (plus an optional
## turntable) into captures/assets/<category>/.
##
## Run:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --audio-driver Dummy res://tools_gd/asset_review.tscn -- \
##     --category=trees --out=<abs dir> [--turntable=8] [--only=oak] [--per-shot=4] [--lod=1]
##
## Exposure note (see PROGRESS.md): with the Compatibility renderer, tonemap_white must be
## around 6 and the sun near 1.0 or mid-greys clip to white and every painted surface reads
## as a flat highlight.

const MODELS_ROOT := "res://assets/models"
const SHOT_NAMES: Array[String] = ["three_quarter", "front", "high"]

var out_dir := "user://assets"
var category := "props"
var only := ""
var per_shot := 4
var turntable := 0
var lod_level := 0
var single_mode := false

var cam: Camera3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var stage_radius := 6.0
var stage_centre := Vector3.ZERO
var stage_height := 2.0
var entries: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var shot_index := -1
var frames := 0


func _ready() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_build_environment()
	_build_ground()
	var paths := _collect_paths()
	if paths.is_empty():
		push_error("asset_review: no GLBs found for category '%s'" % category)
		get_tree().quit(2)
		return
	_place_lineup(paths)
	_build_camera()
	_build_shots()
	print("asset_review: %d assets, %d shots -> %s" % [entries.size(), shots.size(), out_dir])
	for e in entries:
		var b: AABB = e["aabb"]
		print("  %s x=%.1f size=%v" % [String(e["path"]).get_file(), float(e["x"]), b.size])
	for s in shots:
		print("  shot %s centre=%v dist=%.1f angle=%d" % [s["name"], s["centre"], float(s["dist"]), int(s["angle"])])


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--category="):
			category = a.substr(11)
		elif a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--per-shot="):
			per_shot = maxi(1, int(a.substr(11)))
		elif a.begins_with("--turntable="):
			turntable = maxi(0, int(a.substr(12)))
		elif a.begins_with("--lod="):
			lod_level = maxi(0, int(a.substr(6)))
		elif a.begins_with("--single="):
			single_mode = true
			category = a.substr(9)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.34, 0.50, 0.76)
	sky_mat.sky_horizon_color = Color(0.80, 0.80, 0.76)
	sky_mat.ground_horizon_color = Color(0.62, 0.60, 0.54)
	sky_mat.ground_bottom_color = Color(0.26, 0.24, 0.20)
	sky_mat.sun_angle_max = 12.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Without this the mid-greys of a painted surface clip to white on Compatibility.
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.95, 0.87)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)

	fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, -135.0, 0.0)
	fill.light_energy = 0.25
	fill.light_color = Color(0.78, 0.84, 1.0)
	fill.shadow_enabled = false
	add_child(fill)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400.0, 400.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.44, 0.36)
	gm.roughness = 0.95
	gm.specular = 0.1
	ground.material_override = gm
	add_child(ground)


func _collect_paths() -> Array[String]:
	var paths: Array[String] = []
	if single_mode:
		paths.append(category)
		return paths
	var root := "%s/%s" % [MODELS_ROOT, category]
	_scan_dir(root, paths)
	paths.sort()
	return paths


func _scan_dir(dir_path: String, into: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan_dir("%s/%s" % [dir_path, sub], into)
	for f in dir.get_files():
		if not f.ends_with(".glb") or f.ends_with("_col.glb"):
			continue
		if only != "" and not f.contains(only):
			continue
		into.append("%s/%s" % [dir_path, f])


func _place_lineup(paths: Array[String]) -> void:
	# First instantiate everything so the spacing can follow the real footprints.
	var loaded: Array[Dictionary] = []
	for p in paths:
		var ps: Resource = ResourceLoader.load(p)
		if ps == null or not (ps is PackedScene):
			push_error("asset_review: cannot load %s" % p)
			continue
		var inst: Node3D = (ps as PackedScene).instantiate() as Node3D
		if inst == null:
			continue
		add_child(inst)
		_apply_lod(inst)
		var box := _aabb(inst)
		loaded.append({"path": p, "node": inst, "aabb": box})
	if loaded.is_empty():
		return
	# Space neighbours by their own footprints, not by the largest in the set: one 13 m
	# giant bone must not push a 0.4 m mug half a screen away from its neighbour.
	var cursor := 0.0
	var max_h := 0.0
	var prev_half := 0.0
	for i in loaded.size():
		var e: Dictionary = loaded[i]
		var box: AABB = e["aabb"]
		var half := maxf(box.size.x, box.size.z) * 0.5
		if i > 0:
			cursor += prev_half + half + maxf(0.35, maxf(prev_half, half) * 0.35)
		var node: Node3D = e["node"]
		# Centre each asset on its own footprint and sit it on the ground.
		node.position = Vector3(cursor - box.position.x - box.size.x * 0.5, -box.position.y, 0.0)
		max_h = maxf(max_h, box.size.y)
		e["x"] = cursor
		entries.append(e)
		prev_half = half
	stage_radius = maxf(cursor * 0.5 + prev_half, 2.0)
	stage_centre = Vector3(cursor * 0.5, 0.0, 0.0)
	stage_height = max_h


func _apply_lod(root: Node3D) -> void:
	## Show only the requested LOD: meshes named *_LOD1/_LOD2 are hidden unless asked for.
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := m.name
		var level := 0
		if n.contains("_LOD1"):
			level = 1
		elif n.contains("_LOD2"):
			level = 2
		elif n.contains("_LOD3"):
			level = 3
		m.visible = level == lod_level
		if m.visible:
			# The importer gives each level a distance band; a lineup is shot from far
			# enough away that LOD0 would be culled, so the forced level ignores the band.
			m.visibility_range_begin = 0.0
			m.visibility_range_end = 0.0
			m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			_fix_materials(m)


func _fix_materials(mi: MeshInstance3D) -> void:
	## The review scene renders what the importer produced; it only ensures foliage is
	## double-sided and scissored so cards are not invisible from behind.
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var mat := mi.get_active_material(i)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.albedo_texture != null and sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue


func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible or m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.05
	cam.far = 900.0
	add_child(cam)


func _build_shots() -> void:
	## Assets are photographed in groups of `per_shot` so nothing is a dot in a long row.
	var groups: Array[Array] = []
	var current: Array = []
	for e in entries:
		current.append(e)
		if current.size() >= per_shot:
			groups.append(current)
			current = []
	if not current.is_empty():
		groups.append(current)
	for gi in groups.size():
		var g: Array = groups[gi]
		var lo := INF
		var hi := -INF
		var h := 0.0
		for e in g:
			var box: AABB = e["aabb"]
			var x: float = e["x"]
			lo = minf(lo, x - box.size.x * 0.5)
			hi = maxf(hi, x + box.size.x * 0.5)
			h = maxf(h, box.size.y)
		var centre := Vector3((lo + hi) * 0.5, h * 0.45, 0.0)
		var span := maxf(hi - lo, h * 1.2) + h * 0.3
		var dist := maxf(span * 1.25, 1.6)
		for si in SHOT_NAMES.size():
			var name := "%s_%02d_%s" % [category.get_file().get_basename(), gi, SHOT_NAMES[si]]
			shots.append({"name": name, "centre": centre, "dist": dist, "angle": si, "height": h})
		for t in turntable:
			shots.append({"name": "%s_%02d_turn%02d" % [category.get_file().get_basename(), gi, t],
					"centre": centre, "dist": dist, "angle": 100 + t, "turns": turntable, "height": h})


func _aim(shot: Dictionary) -> void:
	var centre: Vector3 = shot["centre"]
	var dist: float = shot["dist"]
	var angle: int = shot["angle"]
	var h: float = shot["height"]
	var pos: Vector3
	match angle:
		0:  # three-quarter, eye level-ish
			pos = centre + Vector3(dist * 0.55, h * 0.55 + 0.6, dist * 1.05)
		1:  # straight on, low, to read silhouettes
			pos = centre + Vector3(0.0, h * 0.35 + 0.35, dist * 1.25)
		2:  # high, to read footprint and top surfaces
			pos = centre + Vector3(-dist * 0.45, h * 1.25 + dist * 0.55, dist * 0.85)
		_:
			var turns: int = shot.get("turns", 8)
			var t := float(angle - 100) / float(maxi(turns, 1))
			var a := TAU * t
			pos = centre + Vector3(sin(a) * dist * 1.05, h * 0.5 + 0.5, cos(a) * dist * 1.05)
	cam.position = pos
	cam.look_at(centre)


func _process(_delta: float) -> void:
	frames += 1
	# Three frames per shot: aim, let the frame render with the new camera, then capture.
	var phase := frames % 3
	if phase == 1:
		shot_index += 1
		if shot_index >= shots.size():
			print("asset_review: done")
			get_tree().quit(0)
			return
		_aim(shots[shot_index])
	elif phase == 0 and shot_index >= 0 and shot_index < shots.size():
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, shots[shot_index]["name"]]
		var err := img.save_png(path)
		if err != OK:
			push_error("asset_review: cannot write %s (%d)" % [path, err])
		else:
			print("SHOT %s" % path)
