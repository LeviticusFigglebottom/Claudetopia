extends Node3D
## Renders a built interior from several viewpoints so it can be judged as a place.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --audio-driver Dummy res://tools_gd/interior_review.tscn -- \
##     --meta=<abs meta.json> --out=<abs dir> [--label=name]

var cave: Node3D          # CaveInterior or HouseInterior
var is_house := false
var cam: Camera3D
var shots: Array = []
var frames := 0
var out_dir := "user://interiors"
var label := "interior"


func _ready() -> void:
	var meta_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--meta="):
			meta_path = a.substr(7)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--label="):
			label = a.substr(8)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_environment()
	var probe: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	is_house = typeof(probe) == TYPE_DICTIONARY and str(probe.get("generator", "")) == "house_forge"
	cave = HouseInterior.new() if is_house else CaveInterior.new()
	cave.build_on_ready = false
	add_child(cave)
	if not cave.build(meta_path):
		get_tree().quit(2)
		return
	if label == "interior":
		label = meta_path.get_file().trim_suffix(".meta.json")
	cam = Camera3D.new()
	cam.fov = 70
	cam.near = 0.05
	cam.far = 500.0
	add_child(cam)
	_plan_shots()
	print("interior review: %s, %d shots" % [label, shots.size()])


func _environment() -> void:
	var interior_is_house := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--meta="):
			var probe: Variant = JSON.parse_string(FileAccess.get_file_as_string(a.substr(7)))
			interior_is_house = typeof(probe) == TYPE_DICTIONARY and str(probe.get("generator", "")) == "house_forge"
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.014, 0.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.56, 0.64) if interior_is_house else Color(0.36, 0.44, 0.60)
	env.ambient_light_energy = 0.75 if interior_is_house else 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.14, 0.16, 0.22)
	env.fog_density = 0.0 if interior_is_house else 0.008
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.25
	we.environment = env
	add_child(we)


func _plan_shots() -> void:
	# A lantern at the camera: a player always carries light in a deep place.
	if is_house:
		# A house is lit by its own fires and windows; the reviewer carries no lantern.
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-38, 35, 0)
		sun.light_energy = 0.35
		sun.light_color = Color(0.95, 0.96, 1.0)
		sun.shadow_enabled = false
		add_child(sun)
	else:
		var lantern := OmniLight3D.new()
		lantern.light_color = Color(1.0, 0.78, 0.5)
		lantern.light_energy = 2.0
		lantern.omni_range = 16.0
		lantern.shadow_enabled = true
		cam.add_child(lantern)
		lantern.position = Vector3(0.3, 0.1, -0.2)

	var spaces: Dictionary = cave.rooms if is_house else cave.chambers
	var ids: Array = spaces.keys()
	ids.sort()
	for id in ids:
		var ch: Dictionary = spaces[id]
		var centre: Vector3
		var radii: Vector3
		if is_house:
			centre = Vector3(float(ch["x"]) + float(ch["w"]) * 0.5, float(ch["floor_y"]), float(ch["z"]) + float(ch["d"]) * 0.5)
			radii = Vector3(float(ch["w"]) * 0.5, 1.4, float(ch["d"]) * 0.5)
		else:
			centre = CaveInterior._vec(ch["centre"])
			radii = CaveInterior._vec(ch["radii"])
		# Stand in a corner and look across the space, the way someone walking in sees it.
		var stand := centre
		if is_house:
			stand = centre + Vector3(-radii.x * 0.72, 0, -radii.z * 0.72)
		else:
			var pts: Array = ch.get("floor_points", [])
			var best := -1.0
			for p in pts:
				var v: Vector3 = CaveInterior._vec(p)
				var dd := Vector2(v.x - centre.x, v.z - centre.z).length()
				if dd > best and dd < maxf(radii.x, radii.z) * 0.55:
					best = dd
					stand = v
			if best < 0.5:
				stand = centre + Vector3(radii.x * 0.6, 0, 0)
		shots.append({
			"label": "%s_%s" % [label, id],
			"pos": stand + Vector3(0, 1.62, 0),
			"look": Vector3(centre.x, stand.y + 1.15, centre.z),
			"fov": 78 if is_house else 75,
		})
	# A cutaway from above, to read the layout as a whole.
	var bounds: Array = cave.meta.get("bounds", [])
	var lo := Vector3(-30, -30, -30)
	var hi := Vector3(30, 30, 30)
	if bounds.size() == 2:
		lo = CaveInterior._vec(bounds[0])
		hi = CaveInterior._vec(bounds[1])
	elif is_house:
		lo = Vector3(1e9, 0, 1e9)
		hi = Vector3(-1e9, 0, -1e9)
		for id2 in cave.rooms:
			var r: Dictionary = cave.rooms[id2]
			lo.x = minf(lo.x, float(r["x"]))
			lo.z = minf(lo.z, float(r["z"]))
			hi.x = maxf(hi.x, float(r["x"]) + float(r["w"]))
			hi.z = maxf(hi.z, float(r["z"]) + float(r["d"]))
			hi.y = maxf(hi.y, float(r["floor_y"]) + 2.75)
	var mid := (lo + hi) * 0.5
	shots.append({"label": "%s_zz_overview" % label, "pos": Vector3(mid.x, hi.y + 12.0, hi.z + (hi.z - lo.z) * 0.55), "look": mid, "fov": 55, "hide_shell_top": true})


func _process(_d: float) -> void:
	frames += 1
	var i := frames / 10 - 1
	if frames % 10 == 1 and i + 1 < shots.size():
		var s: Dictionary = shots[i + 1]
		cam.fov = float(s.get("fov", 70))
		cam.position = s["pos"]
		cam.look_at(s["look"])
	elif frames % 10 == 0:
		if i >= 0 and i < shots.size():
			var img := get_viewport().get_texture().get_image()
			img.save_png(out_dir.path_join("%s.png" % shots[i]["label"]))
			print("SAVED %s" % shots[i]["label"])
		if i + 1 >= shots.size():
			print("errors=%d warnings=%d" % [Log.error_count, Log.warning_count])
			get_tree().quit(0)
