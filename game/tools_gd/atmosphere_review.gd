extends Node3D
## Renders every region at several times of day (and its most likely weather) into
## captures/atmosphere/. Run:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --audio-driver Dummy res://tools_gd/atmosphere_review.tscn -- --out=<abs dir>

const TIMES := [6.3, 9.0, 13.0, 17.5, 19.6, 23.0]
var atmosphere: Atmosphere
var cam: Camera3D
var jobs: Array = []
var frames := 0
var out_dir := "user://atmosphere"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_build_stage()
	atmosphere = preload("res://systems/atmosphere/atmosphere.tscn").instantiate()
	add_child(atmosphere)
	cam = Camera3D.new()
	add_child(cam)
	cam.fov = 60
	cam.position = Vector3(0, 3.0, 14.0)
	cam.look_at(Vector3(0, 2.5, 0))
	var regions := ContentDB.ids_of("region")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--region="):
			only = a.substr(9)
	for r in regions:
		if only != "" and not r.ends_with(only):
			continue
		for t in TIMES:
			jobs.append([r, t])
	print("atmosphere review: %d shots" % jobs.size())


func _build_stage() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	pm.subdivide_depth = 60
	pm.subdivide_width = 60
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.40, 0.44, 0.30)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = rng.randf_range(1.5, 3.0)
		cm.height = rng.randf_range(6.0, 14.0)
		cone.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.18, 0.28, 0.14).lerp(Color(0.3, 0.3, 0.2), rng.randf())
		cone.material_override = m
		var d := rng.randf_range(20.0, 220.0)
		var ang := rng.randf_range(-PI * 0.75, PI * 0.75)
		cone.position = Vector3(sin(ang) * d, cm.height * 0.5, -cos(ang) * d)
		add_child(cone)
	for i in 6:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4, 3.5, 4)
		b.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.66, 0.58)
		b.material_override = m
		b.position = Vector3(-12 + i * 5.0, 1.75, -18 - (i % 2) * 6)
		add_child(b)
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	s.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.5, 0.5, 0.5)
	s.material_override = mm
	s.position = Vector3(2, 1, 2)
	add_child(s)
	var far := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(300, 90, 60)
	far.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.45, 0.45, 0.42)
	far.material_override = fmat
	far.position = Vector3(60, 45, -420)
	add_child(far)


func _process(_d: float) -> void:
	frames += 1
	if jobs.is_empty():
		if frames % 12 == 0:
			get_tree().quit()
		return
	if frames % 12 == 1:
		var job: Array = jobs[0]
		WorldClock.running = false
		WorldClock.set_time(float(job[1]))
		atmosphere.set_region(job[0], true)
		var def := ContentDB.get_def(job[0])
		var weights: Dictionary = def["identity"]["weather"]
		var best := ""
		var bw := -1.0
		for k in weights:
			if float(weights[k]) > bw:
				bw = float(weights[k])
				best = k
		atmosphere.force_weather("core:weather/%s" % best, true)
	elif frames % 12 == 0:
		var job: Array = jobs.pop_front()
		var img := get_viewport().get_texture().get_image()
		var name := "%s_%04.1f.png" % [Ids.name_of(job[0]), float(job[1])]
		img.save_png(out_dir.path_join(name))
		print("SAVED ", name)
