extends SceneTree
## Writes the installed terrain's heights (game/terrain_data's Terrain3D regions) as raw float32,
## one file per region named after it (terrain3d-01_00.r32: region x -1, z 0, 1024 x 1024 at 2 m),
## into $DUMP_OUT. The world build's full-resolution heights.r32 is not kept in the checkout, and
## the tools that sweep an installed world's cells against its ground (tools/world/seat_cliffs.py)
## read these instead:
##
##   DUMP_OUT=/tmp/h godot --headless --path game --audio-driver Dummy -s res://tools_gd/dump_heights.gd


func _init() -> void:
	var out := OS.get_environment("DUMP_OUT")
	if out == "":
		push_error("dump_heights: set DUMP_OUT to a directory")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var dir := DirAccess.open("res://terrain_data")
	var n := 0
	for f in dir.get_files():
		if not f.ends_with(".res"):
			continue
		var region: Resource = load("res://terrain_data/" + f)
		var img: Image = region.get("height_map")
		var fa := FileAccess.open("%s/%s.r32" % [out, f.get_basename()], FileAccess.WRITE)
		fa.store_buffer(img.get_data())
		fa.close()
		n += 1
	print("dump_heights: %d regions to %s" % [n, out])
	quit(0 if n > 0 else 1)
