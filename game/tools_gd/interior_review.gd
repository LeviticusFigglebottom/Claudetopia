extends Node3D
## Renders a built interior from several viewpoints so it can be judged as a place.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --audio-driver Dummy res://tools_gd/interior_review.tscn -- \
##     --meta=<abs meta.json> --out=<abs dir> [--label=name]

var cave: CaveInterior
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
	cave = CaveInterior.new()
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
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.014, 0.018)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.44, 0.60)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.14, 0.16, 0.22)
	env.fog_density = 0.008
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.25
	we.environment = env
	add_child(we)


func _plan_shots() -> void:
	# A lantern at the camera: a player always carries light in a deep place.
	var lantern := OmniLight3D.new()
	lantern.light_color = Color(1.0, 0.78, 0.5)
	lantern.light_energy = 2.0
	lantern.omni_range = 16.0
	lantern.shadow_enabled = true
	cam.add_child(lantern)
	lantern.position = Vector3(0.3, 0.1, -0.2)

	var ids: Array = cave.chambers.keys()
	ids.sort()
	for id in ids:
		var ch: Dictionary = cave.chambers[id]
		var centre: Vector3 = CaveInterior._vec(ch["centre"])
		var radii: Vector3 = CaveInterior._vec(ch["radii"])
		# Stand on real floor at the chamber's edge and look across it, so the shot
		# shows the room rather than the inside of a wall.
		var pts: Array = ch.get("floor_points", [])
		var stand := centre
		var best := -1.0
		for p in pts:
			var v: Vector3 = CaveInterior._vec(p)
			var d := Vector2(v.x - centre.x, v.z - centre.z).length()
			if d > best and d < maxf(radii.x, radii.z) * 0.55:
				best = d
				stand = v
		if best < 0.5:
			stand = centre + Vector3(radii.x * 0.6, 0, 0)
		shots.append({
			"label": "%s_%s" % [label, id],
			"pos": stand + Vector3(0, 1.65, 0),
			"look": Vector3(centre.x, stand.y + 1.3, centre.z),
			"fov": 75,
		})
	# A cutaway from above, to read the layout as a whole.
	var bounds: Array = cave.meta.get("bounds", [[-30, -30, -30], [30, 30, 30]])
	var lo := CaveInterior._vec(bounds[0])
	var hi := CaveInterior._vec(bounds[1])
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
