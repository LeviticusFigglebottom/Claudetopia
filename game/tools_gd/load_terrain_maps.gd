extends SceneTree
## Puts repainted control and colour maps back into the installed terrain (game/terrain_data's
## Terrain3D regions): for each region with a file in $LOAD_FROM (terrain3d-01_00.ctl, the packed
## uint32 control words; terrain3d-01_00.rgba, RGBA8 colour without mipmaps; as dump_heights.gd
## writes them with DUMP_MAPS=1 and tools/world/paint_rock.py repaints them), the region's map is
## replaced and the region saved where it was. The heights are not touched.
##
##   LOAD_FROM=/tmp/h/painted godot --headless --path game --audio-driver Dummy -s res://tools_gd/load_terrain_maps.gd

const SIZE := 1024


func _init() -> void:
	var src := OS.get_environment("LOAD_FROM")
	if src == "":
		push_error("load_terrain_maps: set LOAD_FROM to a directory")
		quit(2)
		return
	var dir := DirAccess.open("res://terrain_data")
	var n := 0
	for f in dir.get_files():
		if not f.ends_with(".res"):
			continue
		var stem := f.get_basename()
		var ctl_path := "%s/%s.ctl" % [src, stem]
		var col_path := "%s/%s.rgba" % [src, stem]
		if not FileAccess.file_exists(ctl_path) and not FileAccess.file_exists(col_path):
			continue
		var path := "res://terrain_data/" + f
		var region: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if FileAccess.file_exists(ctl_path):
			var bytes := FileAccess.get_file_as_bytes(ctl_path)
			if bytes.size() != SIZE * SIZE * 4:
				push_error("load_terrain_maps: %s is %d bytes" % [ctl_path, bytes.size()])
				quit(1)
				return
			region.set("control_map", Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, bytes))
		if FileAccess.file_exists(col_path):
			var bytes := FileAccess.get_file_as_bytes(col_path)
			if bytes.size() != SIZE * SIZE * 4:
				push_error("load_terrain_maps: %s is %d bytes" % [col_path, bytes.size()])
				quit(1)
				return
			var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, bytes)
			img.generate_mipmaps()
			region.set("color_map", img)
		if region.has_method("set_modified"):
			region.call("set_modified", true)
		var err := ResourceSaver.save(region, path, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("load_terrain_maps: cannot save %s: %s" % [path, error_string(err)])
			quit(1)
			return
		n += 1
	print("load_terrain_maps: %d regions from %s" % [n, src])
	quit(0 if n > 0 else 1)
