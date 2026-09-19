extends Node3D
## Measures what a scene actually costs to draw, and fails if it is over budget.
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --audio-driver Dummy \
##     --resolution 1600x900 res://tools_gd/perf_probe.tscn -- --out=<abs dir> [--interiors]
##
## Budgets come from DESIGN section 11: at most 2 000 draw calls and 1.5 M primitives in
## view at 1080p. Interiors are measured from inside every chamber or room, because the
## worst case is standing in the largest space with the most lights, not the average.
##
## Writes <out>/perf.json and prints a table. Exit code 1 if anything is over budget.

const DRAW_CALL_BUDGET := 2000
const PRIMITIVE_BUDGET := 1_500_000
const WARMUP_FRAMES := 3
const MEASURE_FRAMES := 4

var out_dir := "user://perf"
var jobs: Array = []
var results: Array = []
var current: Dictionary = {}
var builder: Node3D
var cam: Camera3D
var frame := 0
var samples: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	_environment()
	cam = Camera3D.new()
	cam.fov = 75
	cam.far = 600.0
	add_child(cam)
	for def in ContentDB.all("interior"):
		if def.get("test_only", false):
			continue
		var meta_path := str(def.get("meta", ""))
		if meta_path.is_empty() or not FileAccess.file_exists(meta_path):
			continue
		jobs.append({"id": str(def["id"]), "name": str(def["name"]), "meta": meta_path,
					 "deep": def.has("formed_by")})
	print("PERF: %d interiors to measure" % jobs.size())
	_next()


func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.46, 0.58)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 2.0
	we.environment = env
	add_child(we)


func _next() -> void:
	if is_instance_valid(builder):
		builder.queue_free()
		builder = null
	if jobs.is_empty():
		_report()
		return
	current = jobs.pop_front()
	builder = (CaveInterior.new() if current["deep"] else HouseInterior.new())
	builder.build_on_ready = false
	if builder is CaveInterior:
		(builder as CaveInterior).spawn_encounters = false
	add_child(builder)
	builder.build(str(current["meta"]))
	samples.clear()
	frame = 0
	_aim(0)


## Stand in each space in turn and look across it: the worst case is inside the biggest
## room, not a flyover of the whole thing.
func _viewpoints() -> Array:
	var out: Array = []
	if builder is CaveInterior:
		for id in (builder as CaveInterior).chambers:
			var ch: Dictionary = (builder as CaveInterior).chambers[id]
			var c: Vector3 = CaveInterior._vec(ch["centre"])
			var r: Vector3 = CaveInterior._vec(ch["radii"])
			out.append([c + Vector3(r.x * 0.55, 1.65, r.z * 0.55), Vector3(c.x, c.y + 1.3, c.z)])
	else:
		for id in (builder as HouseInterior).rooms:
			var r2: Dictionary = (builder as HouseInterior).rooms[id]
			var c2 := Vector3(float(r2["x"]) + float(r2["w"]) * 0.5, float(r2["floor_y"]), float(r2["z"]) + float(r2["d"]) * 0.5)
			out.append([c2 + Vector3(-float(r2["w"]) * 0.35, 1.62, -float(r2["d"]) * 0.35), Vector3(c2.x, c2.y + 1.2, c2.z)])
	return out


var _views: Array = []
var _view_index := 0


func _aim(index: int) -> void:
	if index == 0:
		_views = _viewpoints()
	_view_index = index
	if index >= _views.size():
		return
	cam.global_position = _views[index][0]
	cam.look_at(_views[index][1])
	frame = 0


func _process(_d: float) -> void:
	if builder == null or _views.is_empty():
		return
	if _view_index >= _views.size():
		_finish_interior()
		return
	frame += 1
	if frame > WARMUP_FRAMES and frame <= WARMUP_FRAMES + MEASURE_FRAMES:
		samples.append({
			"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		})
	elif frame > WARMUP_FRAMES + MEASURE_FRAMES:
		_aim(_view_index + 1)


func _finish_interior() -> void:
	var worst := {"draw_calls": 0, "primitives": 0, "objects": 0}
	for s in samples:
		for k in worst:
			worst[k] = maxi(int(worst[k]), int(s[k]))
	var row := {
		"id": current["id"], "name": current["name"], "kind": "deep" if current["deep"] else "house",
		"viewpoints": _views.size(),
		"worst_draw_calls": worst["draw_calls"], "worst_primitives": worst["primitives"],
		"worst_objects": worst["objects"],
		"over_draw_calls": worst["draw_calls"] > DRAW_CALL_BUDGET,
		"over_primitives": worst["primitives"] > PRIMITIVE_BUDGET,
	}
	results.append(row)
	print("PERF: %-34s %5d draws  %9d prims  %4d objs  %s" % [
		Ids.name_of(str(current["id"])), row["worst_draw_calls"], row["worst_primitives"],
		row["worst_objects"], "OVER" if row["over_draw_calls"] or row["over_primitives"] else "ok"])
	_views.clear()
	_next()


func _report() -> void:
	var over := results.filter(func(r): return r["over_draw_calls"] or r["over_primitives"])
	var worst_draws := 0
	var worst_prims := 0
	for r in results:
		worst_draws = maxi(worst_draws, int(r["worst_draw_calls"]))
		worst_prims = maxi(worst_prims, int(r["worst_primitives"]))
	var doc := {
		"budgets": {"draw_calls": DRAW_CALL_BUDGET, "primitives": PRIMITIVE_BUDGET},
		"measured_at": Time.get_datetime_string_from_system(),
		"resolution": "%dx%d" % [get_viewport().size.x, get_viewport().size.y],
		"renderer": RenderingServer.get_current_rendering_method(),
		"worst_draw_calls": worst_draws, "worst_primitives": worst_prims,
		"over_budget": over.size(), "interiors": results,
	}
	var f := FileAccess.open(out_dir.path_join("perf.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	print("")
	print("PERF: worst case across %d interiors: %d draw calls (budget %d), %d primitives (budget %d)" % [
		results.size(), worst_draws, DRAW_CALL_BUDGET, worst_prims, PRIMITIVE_BUDGET])
	for r in over:
		print("PERF:   OVER BUDGET: %s (%d draws, %d prims)" % [r["id"], r["worst_draw_calls"], r["worst_primitives"]])
	print("PERF: %s" % ("PASS" if over.is_empty() else "FAIL"))
	get_tree().quit(0 if over.is_empty() else 1)
