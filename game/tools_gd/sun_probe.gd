extends Node
## Points a camera at the sun of a live Atmosphere and reads what colour the disc comes out, with
## the region's grade and glow on and off, so a disc that draws wrong can be taken apart stage by
## stage instead of guessed at. A scene rather than a `-s` script, because the Atmosphere names
## autoloads that a `-s` script is compiled before.
##
##   xvfb-run -a -s "-screen 0 800x450x24" godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy --resolution 800x450 res://tools_gd/sun_probe.tscn -- \
##       --region=cinderlea --hour=17.1 --out=<abs dir>

var out_dir := "user://sun_probe"
var region := "core:region/cinderlea"
var hour := 17.1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--region="):
			region = "core:region/" + a.substr(9)
		elif a.begins_with("--hour="):
			hour = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	WorldClock.running = false
	WorldClock.set_time(hour)
	var atmos := (load("res://systems/atmosphere/atmosphere.tscn") as PackedScene).instantiate() as Atmosphere
	add_child(atmos)
	atmos.set_region(region, true)
	atmos.settle()
	await _frames(3)
	var to_sun := atmos.sun.global_transform.basis.z
	cam.look_at_from_position(Vector3.ZERO, to_sun * 100.0, Vector3.UP)
	print("SUN elevation %.2f deg, energy %.3f, visible %s" % [float(atmos.state.get("elevation", 0.0)),
			atmos.sun.light_energy, str(atmos.sun.visible)])
	for case in ["as_shipped", "no_grade", "no_glow", "neither"]:
		Settings.set_value("graphics", "color_grade", case in ["as_shipped", "no_glow"], false)
		Settings.set_value("graphics", "glow", case in ["as_shipped", "no_grade"], false)
		atmos.settle()
		await _frames(4)
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/sun_%s.png" % [out_dir, case])
		var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		var ring := img.get_pixel(img.get_width() / 2, img.get_height() / 2 - 60)
		print("SUN %-10s disc centre %s   60 px above it %s" % [case, str(c), str(ring)])
	Settings.set_value("graphics", "color_grade", true, false)
	Settings.set_value("graphics", "glow", true, false)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
