extends Node3D
## A picture of the road's trains (systems/roads/road_train.gd): a horse and cart and a packhorse
## on flat ground, from the side and three-quarters, to see they are the forge's things put
## together the right way round (the horse between the shafts, the load on the bed and the pack).
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy res://tools_gd/road_train_review.tscn -- --out=captures/roadlife

var out_dir := "captures/roadlife"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	_run.call_deferred()


func _run() -> void:
	var dir := ProjectSettings.globalize_path("res://../%s" % out_dir) if not out_dir.is_absolute_path() else out_dir
	DirAccess.make_dir_recursive_absolute(dir)
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.72, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.38, 0.28)
	ground.material_override = mat
	world.add_child(ground)
	var wagon := RoadTrain.new()
	world.add_child(wagon)
	wagon.build("wagon", "hearthvale", "review:wagon", "", "")
	wagon.move(Vector3(-2.0, 0.0, 0.0), Vector2(0, -1), 1.3)
	var pack := RoadTrain.new()
	world.add_child(pack)
	pack.build("packhorse", "hearthvale", "review:pack", "", "")
	pack.move(Vector3(3.0, 0.0, -1.0), Vector2(0, -1), 1.3)
	var cam := Camera3D.new()
	world.add_child(cam)
	for view in [["side", Vector3(12.0, 2.5, 1.5)], ["three_quarter", Vector3(8.0, 4.0, -8.0)], ["back", Vector3(-4.0, 3.5, 10.0)]]:
		cam.global_position = view[1]
		cam.look_at(Vector3(0.0, 1.0, 1.0))
		cam.current = true
		for i in 20:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/train_%s.png" % [dir, view[0]])
		print("REVIEW wrote %s/train_%s.png" % [dir, view[0]])
	get_tree().quit(0)
