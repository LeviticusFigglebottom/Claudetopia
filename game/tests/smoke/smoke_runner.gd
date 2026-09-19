extends Node
## The smoke run: load every region and every interior, and fail on any error.
##
##   ./run.sh smoke
##   godot --headless --path game --audio-driver Dummy -- --smoke [--quick]
##
## Regions are visited by moving a probe to each region centre and each place, so the
## world streamer and the atmosphere both get exercised. Interiors are built for real,
## one at a time, and every one must produce geometry, collision, a light and a way out.
## Prints "SMOKE: PASS" or "SMOKE: FAIL" and exits 0 or 1.

const SETTLE_FRAMES := 4

var failures: Array[String] = []
var checked := {"regions": 0, "interiors": 0, "places": 0}
var quick := false
var _errors_at_start := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--quick":
			quick = true
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	_errors_at_start = Log.error_count
	print("SMOKE: starting (%d regions, %d interiors, %d places)" % [
		ContentDB.all("region").size(), ContentDB.all("interior").size(), ContentDB.all("place").size()])
	await _check_content()
	await _check_interiors()
	await _check_world()
	_report()


func _fail(what: String) -> void:
	failures.append(what)
	print("SMOKE: FAIL %s" % what)


## Content has to hold together before anything can load it.
func _check_content() -> void:
	for p in ContentDB.problems:
		_fail("content: %s" % p)
	for def in ContentDB.all("region"):
		checked.regions += 1
		var ident: Dictionary = def.get("identity", {})
		for key in ["palette", "light", "weather", "landmark"]:
			if not ident.has(key):
				_fail("region %s has no %s" % [def["id"], key])
		if not ContentDB.has(str(ident.get("landmark", ""))):
			_fail("region %s landmark is not a place: %s" % [def["id"], ident.get("landmark")])
	for def in ContentDB.all("place"):
		checked.places += 1
		if not ContentDB.has(str(def.get("region", ""))):
			_fail("place %s is in no region" % def["id"])
	await get_tree().process_frame


## Every interior is built for real. This is the check that catches a broken meta file,
## a missing mesh, or a dungeon with no way out.
func _check_interiors() -> void:
	var host := Node3D.new()
	host.name = "SmokeHost"
	add_child(host)
	for def in ContentDB.all("interior"):
		if def.get("test_only", false):
			continue
		var id := str(def["id"])
		var scene_path := str(def.get("scene", ""))
		if not ResourceLoader.exists(scene_path):
			_fail("interior %s: scene missing %s" % [id, scene_path])
			continue
		var meta_path := str(def.get("meta", ""))
		if meta_path.is_empty() or not FileAccess.file_exists(meta_path):
			_fail("interior %s: meta missing %s" % [id, meta_path])
			continue
		var before := Log.error_count
		var builder: Node3D = (CaveInterior.new() if def.has("formed_by") else HouseInterior.new())
		builder.build_on_ready = false
		if builder is CaveInterior:
			(builder as CaveInterior).spawn_encounters = false
		host.add_child(builder)
		var ok: bool = builder.build(meta_path)
		await get_tree().process_frame
		if not ok:
			_fail("interior %s: build refused" % id)
		else:
			_inspect_interior(id, builder)
		if Log.error_count > before:
			_fail("interior %s: %d errors while building" % [id, Log.error_count - before])
		builder.queue_free()
		await get_tree().process_frame
		checked.interiors += 1
	host.queue_free()


func _inspect_interior(id: String, builder: Node3D) -> void:
	var meshes := builder.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		_fail("interior %s: no geometry" % id)
	var shapes := builder.find_children("*", "CollisionShape3D", true, false)
	if shapes.is_empty():
		_fail("interior %s: no collision, the player would fall through" % id)
	var lights := builder.find_children("*", "Light3D", true, false)
	if lights.is_empty():
		_fail("interior %s: no light source" % id)
	var doors := 0
	for n in builder.find_children("*", "StaticBody3D", true, false):
		if n.is_in_group("door"):
			doors += 1
	if doors == 0:
		_fail("interior %s: no door out" % id)
	# Primitive meshes (a floor quad, a water plane) have geometry by construction and
	# do not answer surface_get_array_len, so only the built meshes are counted.
	var tris := 0
	var primitives := 0
	for m in meshes:
		var mesh: Mesh = (m as MeshInstance3D).mesh
		if mesh == null:
			continue
		if mesh is ArrayMesh:
			for s in mesh.get_surface_count():
				tris += (mesh as ArrayMesh).surface_get_array_len(s) / 3
		else:
			primitives += 1
	if tris < 200 and primitives == 0:
		_fail("interior %s: only %d triangles" % [id, tris])


## The world scene, if it exists yet: visit every region centre and settle.
func _check_world() -> void:
	if not ResourceLoader.exists("res://world/world.tscn"):
		print("SMOKE: world scene not built yet, skipping the overworld sweep")
		return
	var world: Node3D = (load("res://world/world.tscn") as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame
	var probe := Node3D.new()
	probe.add_to_group("streamer_target")
	world.add_child(probe)
	for def in ContentDB.all("region"):
		var map: Dictionary = def.get("map", {})
		var centre: Array = map.get("center", [0, 0])
		var before := Log.error_count
		probe.global_position = Vector3(float(centre[0]), 200.0, float(centre[1]))
		if world.has_method("force_stream_around"):
			world.force_stream_around(probe.global_position)
		for i in SETTLE_FRAMES:
			await get_tree().process_frame
		if Log.error_count > before:
			_fail("region %s: %d errors while streaming" % [def["id"], Log.error_count - before])
	if not quick:
		for def in ContentDB.all("place"):
			var pos: Array = def.get("position", [])
			if pos.size() < 2:
				continue
			var before2 := Log.error_count
			probe.global_position = Vector3(float(pos[0]), 200.0, float(pos[1]))
			if world.has_method("force_stream_around"):
				world.force_stream_around(probe.global_position)
			await get_tree().process_frame
			if Log.error_count > before2:
				_fail("place %s: %d errors while streaming" % [def["id"], Log.error_count - before2])
	world.queue_free()
	await get_tree().process_frame


func _report() -> void:
	var new_errors := Log.error_count - _errors_at_start
	print("SMOKE: %d regions, %d places, %d interiors checked; %d logged errors" % [
		checked.regions, checked.places, checked.interiors, new_errors])
	if failures.is_empty() and new_errors == 0:
		print("SMOKE: PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			print("SMOKE:   %s" % f)
		print("SMOKE: FAIL (%d problems, %d logged errors)" % [failures.size(), new_errors])
		get_tree().quit(1)
