extends Node
## Measures what the streamer costs when the scatter assets exist.
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy --resolution 1600x900 res://tools_gd/scatter_probe.tscn
##
## The forge has not made the trees and rocks yet, so the streamer skips them and a capture
## measures terrain and water only. This probe stands proxy meshes in for every scatter asset
## the cells ask for (a low-poly billboard-ish cross for foliage, a small rock-sized box for
## the rest), then reports draw calls and primitives at several viewpoints -- the numbers that
## matter for DESIGN.md §11 (<= 2000 draw calls, <= 1.5 M primitives at 1600x900).
##
## Writes captures/scatter_perf.json and a PNG per viewpoint.

const OUT_DIR := "captures/scatter_probe"
const VIEWS := [
	{"label": "merrowby", "place": "core:place/merrowby", "height": 22.0, "time": 9.0},
	{"label": "briarwold_forest", "place": "core:place/fernhold", "height": 20.0, "time": 10.5},
	{"label": "sedgemire_reeds", "place": "core:place/nauves_landing", "height": 14.0, "time": 8.0},
	{"label": "skerrow_moor", "place": "core:place/brindlecrag", "height": 24.0, "time": 14.0},
	{"label": "cinderlea_heath", "place": "core:place/pilgrims_ash", "height": 20.0, "time": 16.0},
]

var _world: World = null
var _results: Array = []


func _ready() -> void:
	var code: int = await run()
	get_tree().quit(code)


func run() -> int:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://world/world.tscn")
	_world = packed.instantiate() as World
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	_install_proxy_meshes()
	for view in VIEWS:
		await _measure(view)
	var worst_draw := 0
	var worst_prims := 0
	for r in _results:
		worst_draw = maxi(worst_draw, int(r["draw_calls"]))
		worst_prims = maxi(worst_prims, int(r["primitives"]))
	var doc := {
		"generated_at": Time.get_datetime_string_from_system(),
		"note": "proxy meshes stand in for the forge's assets: ~%d triangles per foliage instance" % 8,
		"budget": {"draw_calls": 2000, "primitives": 1500000},
		"worst": {"draw_calls": worst_draw, "primitives": worst_prims},
		"within_budget": worst_draw <= 2000 and worst_prims <= 1500000,
		"views": _results,
	}
	var f := FileAccess.open("%s/scatter_perf.json" % OUT_DIR, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(doc, "  "))
		f.close()
	Log.info("ScatterProbe", "worst: %d draw calls, %.2f M primitives (budget 2000 / 1.5 M)"
		% [worst_draw, float(worst_prims) / 1e6])
	return 0


## Every asset path the cells reference gets a stand-in mesh of about the right size.
func _install_proxy_meshes() -> void:
	var streamer := _world.streamer
	var foliage := _cross_mesh(0.9, 1.4)
	var bush := _cross_mesh(1.4, 1.8)
	var tree := _tree_mesh()
	var rock := BoxMesh.new()
	rock.size = Vector3(1.4, 0.9, 1.2)
	var cells_dir := "res://world/generated/cells"
	var seen: Dictionary = {}
	for cz in range(0, 32, 2):
		for cx in range(0, 32, 2):
			var path := "%s/%d_%d.json" % [cells_dir, cx, cz]
			if not FileAccess.file_exists(path):
				continue
			var cell: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(cell) != TYPE_DICTIONARY:
				continue
			for asset in (cell as Dictionary).get("instances", {}):
				seen[str(asset)] = true
	for asset in seen:
		var mesh: Mesh = foliage
		if str(asset).contains("/trees/"):
			mesh = tree
		elif str(asset).contains("/rocks/") or str(asset).contains("/props/"):
			mesh = rock
		elif str(asset).contains("briar") or str(asset).contains("juniper") or str(asset).contains("hawthorn"):
			mesh = bush
		streamer._mesh_cache[str(asset)] = mesh
	Log.info("ScatterProbe", "%d scatter assets proxied" % seen.size())
	streamer.unload_all()
	streamer.refresh()


## Two crossed quads: the cheapest thing that still looks like foliage (8 triangles).
func _cross_mesh(width: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for angle in [0.0, PI * 0.5]:
		var dir := Vector3(cos(angle), 0.0, sin(angle)) * width * 0.5
		var quad := [Vector3(-dir.x, 0.0, -dir.z), Vector3(dir.x, 0.0, dir.z),
			Vector3(dir.x, height, dir.z), Vector3(-dir.x, height, -dir.z)]
		for tri in [[0, 1, 2], [0, 2, 3], [2, 1, 0], [3, 2, 0]]:
			for i in tri:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(0.5, 0.5))
				st.add_vertex(quad[i])
	st.generate_tangents()
	return st.commit()


## A trunk and a canopy: about 100 triangles, the low end of what the forge will make.
func _tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.35
	trunk.height = 4.0
	trunk.radial_segments = 6
	trunk.rings = 1
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 2.0, 0)))
	var canopy := SphereMesh.new()
	canopy.radius = 2.6
	canopy.height = 4.6
	canopy.radial_segments = 8
	canopy.rings = 4
	st.append_from(canopy, 0, Transform3D(Basis(), Vector3(0, 5.4, 0)))
	return st.commit()


func _measure(view: Dictionary) -> void:
	WorldClock.set_time(float(view.get("time", 10.0)))
	var pos := _world.place_position(str(view["place"]))
	pos.y = _world.provider.get_height(pos.x, pos.z) + float(view.get("height", 20.0))
	var look := Vector3(pos.x + 120.0, pos.y - 26.0, pos.z + 120.0)
	_world.fly_camera.fov = 65.0
	_world.fly_camera.move_to(pos, look)
	_world.move_target(pos)
	var frames := 0
	while frames < 240:
		await get_tree().process_frame
		frames += 1
		if _world.streamer.is_ring_loaded():
			break
	for _i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, view["label"]])
	var entry := {
		"label": view["label"],
		"region": _world.provider.nearest_region_id_at(pos.x, pos.z),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"cells_loaded": _world.streamer.loaded_count(),
		"scatter_instances": _world.streamer.instance_count(),
		"fps_estimate": snappedf(Performance.get_monitor(Performance.TIME_FPS), 0.1),
	}
	_results.append(entry)
	Log.info("ScatterProbe", "%s: %d draws, %.2f M prims, %d instances in %d cells"
		% [entry["label"], entry["draw_calls"], float(entry["primitives"]) / 1e6,
		entry["scatter_instances"], entry["cells_loaded"]])
