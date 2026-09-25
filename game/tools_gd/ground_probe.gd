extends Node
## The ground probe: is the built world sound where a body stands in it?
##
##   ./run.sh tour  [--region=skerrow,cinderlea] [--only=places|pois|<id>,<id>] [--minutes=25]
##                  [--limit=N] [--fresh]
##   ./run.sh roads [--only=<road id>,...] [--limit=N] [--max-m=M]
##   ./run.sh foes
##
## Boot attaches it at the root when it sees --tour=<dir> or --roads=<dir>, and then starts a new
## game with no opening (`--new-game --no-opening`). Once the body stands, the probe does one of two
## things, and writes a row per place or road to <dir> as it goes, so a run that is killed keeps
## what it saw:
##
## **The tour** (--tour) stands the body at every place and point of interest the built world lists
## (game/world/generated/pois.json, in the order that makes the shortest hops), lets the country
## stream in round it, and records at each: the engine errors and script errors said since the jump,
## the frame's cost (wall time, draw calls, primitives), what the body is standing on (the ground,
## a roof, a rock, water, nothing), whether it is under the ground, in water or inside something
## solid, and a picture of what the player sees. tour.jsonl, one row a place; tour_*.png.
##
## The tour is made to be taken in pieces between other people's heavy runs: every place has one
## index in one order over the whole map (nearest hop first from the north-west corner), a run takes
## the places --region and --only pick, skips every place tour.jsonl already has a row for, and
## stops at --minutes of wall clock or --limit places; the next run carries on and appends. --fresh
## starts tour.jsonl again.
##
## **The road walk** (--roads) puts the body at the start of each road (roads.json) and walks it to
## the end on the keys a player holds -- W held, Shift for the pace, the camera turned toward the
## road ahead as a mouse turns it -- so snags, walls and slopes are felt, not jumped over. A body
## that makes no way for a second is snagged: the probe says where and what is in front of it, then
## tries what a player tries (jump, step aside). One that still cannot go on in six seconds of the
## game's time is trapped, and is put down further along the road. roads.jsonl, one row a road.
##
## **The foes census** (--foes) asks where the enemies are: at five points in each region, three on
## its roads and two 300 m off them, it counts the living foes within 400 m against what the cells'
## spawns and the points of interest's encounters say the near ring should raise there; it jumps
## away and back to see the ring raise them again; it walks a kilometre of road in each region on
## the keys counting the foes met within 60 m and 200 m; and it kills ten poachers and ten bravos
## and counts the weapons they drop against two thousand rolls of their tables. foes.jsonl.
##
## tools/debug/ground_report.py turns either into a report a person can read in two minutes: the
## worst places, and a contact sheet of the pictures.

const LAYER_WORLD := 1 << 0
const LAYER_TERRAIN := 1 << 10
## The longest a jump is given, on the wall clock, for the cells round the body to stand.
const STREAM_LIMIT_S := 120.0
## Physics ticks the body is given to land after the jump (it is put down a metre up).
const SETTLE_TICKS := 45
## Frames whose cost is measured at each place.
const SAMPLE_FRAMES := 3
## A body this far under the ground's own height is under the ground; this deep in water, in it.
const UNDER_M := 0.5
const WET_M := 0.3
const DEEP_M := 1.2

## Road walk: a second of the game's time making less than this way is a snag.
const SNAG_M := 0.8
## A snag that lasts this many seconds of the game's time is a trap.
const TRAP_S := 6.0
## How far ahead along the road the body steers for.
const LOOKAHEAD_M := 6.0
## Reached the end when within this of the last point.
const ARRIVE_M := 4.0
## Roads a body was once held on, walked by `--only=regressions`: a trap on one, or not reaching
## its end, fails the run. greyfold_builders_harbour: Bell Street's ruined hall stood across it
## (batch 4, w4096b: 734 of 2556 m, 245 snags at the masonry).
const REGRESSION_ROADS: Array[String] = ["core:road/greyfold_builders_harbour"]

var out_dir := ""
var mode := "tour"
var only := ""
var from_index := 0
var limit := -1
## --region=a,b: only the places in these regions (a short name or a full id).
var regions: Array[String] = []
## --minutes=M: stop after this much wall clock (the place under way is finished).
var minutes := 0.0
## --fresh: start tour.jsonl again rather than carrying on from it.
var fresh := false
var max_road_m := 0.0
var capture := true

var _body: Node3D = null
var _rows: FileAccess = null
var _t0 := 0
var _deaths := 0
## Places whose country never stood, or stood empty: the run fails on any.
var _unstreamed: Array[String] = []
## Places tour.jsonl already has a row for, which this run skips.
var _done_ids := {}
## Regression roads the body could not walk to the end of: the run fails on any.
var _failed: Array[String] = []
## Called once a second of the game's time while a road is walked (the foes census looks round).
var _watch := Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour="):
			mode = "tour"
			out_dir = a.substr(7)
		elif a.begins_with("--roads="):
			mode = "roads"
			out_dir = a.substr(8)
		elif a.begins_with("--foes="):
			mode = "foes"
			out_dir = a.substr(7)
		elif a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--from="):
			from_index = maxi(int(a.substr(7)), 0)
		elif a.begins_with("--limit="):
			limit = int(a.substr(8))
		elif a.begins_with("--region="):
			for r in a.substr(9).split(",", false):
				regions.append(r.strip_edges() if r.contains(":") else "core:region/%s" % r.strip_edges())
		elif a.begins_with("--minutes="):
			minutes = float(a.substr(10))
		elif a == "--fresh":
			fresh = true
		elif a.begins_with("--max-m="):
			max_road_m = float(a.substr(8))
		elif a == "--no-capture":
			capture = false
	if DisplayServer.get_name() == "headless":
		capture = false
	if not out_dir.is_absolute_path():
		out_dir = ProjectSettings.globalize_path("res://../%s" % out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	EventBus.player_spawned.connect(func(p: Node) -> void: _body = p as Node3D)
	EventBus.player_died.connect(func(_at: Vector3) -> void: _deaths += 1)
	_run()


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	print("[ground] %s -> %s" % [mode, out_dir])
	while _body == null and Time.get_ticks_msec() - _t0 < 600000:
		await get_tree().process_frame
	if _body == null:
		print("GROUND: FAIL (no body stood in the world in 600 s)")
		get_tree().quit(1)
		return
	# the fade and the country round the spawn, then a fixed hour and a still clock, so every
	# picture is taken in the same light
	await _wall(3.0)
	var lifted_until := Time.get_ticks_msec() + 180000
	while UI.is_faded_out() and Time.get_ticks_msec() < lifted_until:
		await get_tree().process_frame
	WorldClock.set_time(13.0)
	WorldClock.time_scale = 0.0
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var path := "%s/%s.jsonl" % [out_dir, mode]
	# the tour carries on from the rows already there (unless --fresh); the road walk from --from
	var carry := (not fresh if mode == "tour" else from_index > 0) and FileAccess.file_exists(path)
	if carry:
		for line in FileAccess.get_file_as_string(path).split("\n", false):
			var row: Variant = JSON.parse_string(line)
			if row is Dictionary:
				_done_ids[str((row as Dictionary).get("id", ""))] = true
	_rows = FileAccess.open(path, FileAccess.READ_WRITE if carry else FileAccess.WRITE)
	if _rows == null:
		print("GROUND: FAIL (cannot write %s)" % path)
		get_tree().quit(1)
		return
	_rows.seek_end()
	var n := 0
	if mode == "tour":
		n = await _tour()
	elif mode == "foes":
		n = await _foes()
	else:
		n = await _roads()
	_rows.close()
	var took := (Time.get_ticks_msec() - _t0) / 1000.0
	if not _failed.is_empty():
		print("GROUND: FAIL (%s: a road a body was once held on holds it again: %s)" % [mode, "; ".join(PackedStringArray(_failed))])
		get_tree().quit(1)
		return
	if not _unstreamed.is_empty():
		# the frames and footings at these places were taken of an empty county: said, and failed
		print("GROUND: FAIL (%s: %d rows in %s, %.0f s; %d stops where the world did not stream: %s)" % [mode, n,
				path, took, _unstreamed.size(), ", ".join(PackedStringArray(_unstreamed.slice(0, 20)))])
		get_tree().quit(1)
		return
	print("GROUND: DONE (%s: %d rows in %s, %.0f s)" % [mode, n, path, took])
	get_tree().quit(0)


# --- the teleport tour ----------------------------------------------------------------------------

## Every place the built world lists, each with its index in one order over the whole map: nearest
## hop first from the north-west corner, since a tour that zig-zags the map streams every cell
## afresh. The order does not depend on what a run picks, so a place keeps its number across the
## pieces of a tour and across two tours of two builds.
func _tour_list() -> Array:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/pois.json"))
	var picked: Array = (raw as Array).duplicate() if raw is Array else []
	var ordered: Array = []
	var at := Vector2(-1e6, -1e6)
	while not picked.is_empty():
		var best := 0
		var best_d := INF
		for i in picked.size():
			var p: Array = picked[i]["pos"]
			var d := at.distance_squared_to(Vector2(float(p[0]), float(p[2])))
			if d < best_d:
				best_d = d
				best = i
		var e: Dictionary = (picked.pop_at(best) as Dictionary).duplicate()
		at = Vector2(float(e["pos"][0]), float(e["pos"][2]))
		e["i"] = ordered.size()
		ordered.append(e)
	var ids := {}
	if only != "" and only not in ["places", "pois"]:
		for s in only.split(",", false):
			ids[s.strip_edges()] = true
	var out: Array = []
	for e: Dictionary in ordered:
		var id := str(e.get("place_id", ""))
		var kind := id.get_slice("/", 0)
		if only == "places" and kind != "core:place":
			continue
		if only == "pois" and kind != "core:poi":
			continue
		if not ids.is_empty() and not ids.has(id) and not ids.has(id.get_slice("/", 1)):
			continue
		e["region"] = _region_of(id, e)
		if not regions.is_empty() and str(e["region"]) not in regions:
			continue
		out.append(e)
	return out


## The region a place belongs to: its own word for it, or the map's under it.
func _region_of(id: String, e: Dictionary) -> String:
	var r := str(ContentDB.get_or_empty(id).get("region", ""))
	if r != "":
		return r
	var p: Array = e["pos"]
	return World.region_id_at(Vector3(float(p[0]), 0.0, float(p[2])))


func _tour() -> int:
	var list := _tour_list()
	var todo: Array = list.filter(func(e: Dictionary) -> bool: return not _done_ids.has(str(e["place_id"])))
	var total := list.size()
	print("[ground] tour: %d places picked, %d already stood at, %d to go%s%s" % [total, total - todo.size(),
			todo.size(), " (at most %d this run)" % limit if limit >= 0 else "",
			" (for %.0f min)" % minutes if minutes > 0.0 else ""])
	var done := 0
	var until := Time.get_ticks_msec() + int(minutes * 60000.0) if minutes > 0.0 else 0
	for e: Dictionary in todo:
		if not is_instance_valid(_body) or (limit >= 0 and done >= limit) or (until > 0 and Time.get_ticks_msec() > until):
			break
		var i := int(e["i"])
		var row := await _stand_at(i, e)
		_rows.store_line(JSON.stringify(row))
		_rows.flush()
		done += 1
		if bool(row["unstreamed"]):
			_unstreamed.append(str(row["id"]))
		var ring: Dictionary = row["ring"]
		print("TOUR %d (%d of %d) %s  errors %d  script %d  %s  %.0f ms  %d draws  %s%s" % [i, done, todo.size(),
				row["id"], row["errors"], row["script_errors"], row["stand"]["on"], row["frame_ms"], row["draws"],
				", ".join(row["stand"]["flags"]) if not (row["stand"]["flags"] as Array).is_empty() else "sound",
				("  UNSTREAMED (%d of %d cells in, %d things%s)" % [int(ring["cells"]), int(ring["wanted"]),
					int(ring["things"]), "" if bool(ring["ground_drawn"]) else ", no ground drawn"])
					if bool(row["unstreamed"]) else ""])
	return done


## A stop the world did not stream at: its ring still coming in when the wait gave up (`stream_s`
## -1), or built and holding nothing at all. A ring with some bare cells (the sea, a fell top) is
## the country; a ring with not one thing in any cell is not.
##
## And a stop with no ground drawn under the body (`ground_drawn` false: Terrain3D has no region
## there) is the same fault under another name: a 1024 build drawn at the 4096 build's spacing was
## one region in a corner, and every other place stood over brown fog with its cells all built.
static func is_unstreamed(stream_s: float, ring: Dictionary) -> bool:
	if stream_s < 0.0:
		return true
	if not bool(ring.get("ground_drawn", true)):
		return true
	return int(ring.get("cells", 0)) > 0 and int(ring.get("things", 0)) == 0


## Whether the ground is drawn here: Terrain3D has a region under the point. The coarse ground
## (terrain_mode "fallback") is drawn everywhere it has a height map, so it answers true.
func _ground_drawn(at: Vector3) -> bool:
	var world := World.instance
	if world == null or world.terrain_node == null or not is_instance_valid(world.terrain_node):
		return world != null and world.terrain_mode == "fallback"
	if not world.terrain_node.is_class("Terrain3D"):
		return true
	var data: Object = world.terrain_node.get("data")
	return data != null and bool(data.call("has_regionp", at))


## What stands in the full-detail ring round the body: the cells in the world there, how many are
## built, how many of those hold anything, and how many things (a MultiMesh's instances each count).
func _ring_contents() -> Dictionary:
	var out := {"wanted": 0, "cells": 0, "with_things": 0, "things": 0}
	var world := World.instance
	if world == null or world.streamer == null or not is_instance_valid(_body):
		return out
	for c: Vector2i in world.streamer.cells_around(_body.global_position):
		out["wanted"] = int(out["wanted"]) + 1
		var node := world.streamer.get_node_or_null("Cell_%d_%d" % [c.x, c.y])
		if node == null:
			continue
		out["cells"] = int(out["cells"]) + 1
		var n := 0
		for g in node.find_children("*", "GeometryInstance3D", true, false):
			if g is MultiMeshInstance3D:
				var mm := (g as MultiMeshInstance3D).multimesh
				n += mm.instance_count if mm != null else 0
			else:
				n += 1
		if n > 0:
			out["with_things"] = int(out["with_things"]) + 1
		out["things"] = int(out["things"]) + n
	return out


func _stand_at(i: int, e: Dictionary) -> Dictionary:
	var id := str(e["place_id"])
	var p: Array = e["pos"]
	var x := float(p[0])
	var z := float(p[2])
	var ground := World.get_height(x, z)
	var before := _error_snapshot()
	var log_before: int = Log.error_count
	var deaths_before := _deaths
	var t := Time.get_ticks_msec()
	_put(Vector3(x, ground + 1.0, z), deg_to_rad(float(e.get("yaw", 0.0))))
	var streamed := await _wait_for_cells(STREAM_LIMIT_S)
	# the landing, in the game's ticks: a software frame here is seconds long and the engine runs at
	# most eight ticks a frame, so the cap is lifted for the landing and put back
	var lowest := INF
	var ticks := 0
	var cap := Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = SETTLE_TICKS
	while ticks < SETTLE_TICKS and is_instance_valid(_body):
		await get_tree().physics_frame
		lowest = minf(lowest, _body.global_position.y)
		ticks += 1
	Engine.max_physics_steps_per_frame = cap
	var ring := _ring_contents()
	ring["ground_drawn"] = _ground_drawn(_body.global_position if is_instance_valid(_body) else Vector3(x, 0.0, z))
	# the capture runner's lesson (DECISIONS.md, "A capture that photographs nothing fails the
	# run"): a ring that is built and holds nothing, or one still coming in at the limit, is a
	# picture of an empty county, and its frame costs nothing because nothing is drawn
	var unstreamed := is_unstreamed(streamed, ring)
	var cost := await _frame_cost()
	var pic := ""
	if capture:
		pic = "tour_%03d_%s.png" % [i, id.get_slice("/", 1)]
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("%s/%s" % [out_dir, pic])
	var errs := _error_delta(before)
	var row := {
		"i": i, "id": id, "name": str(ContentDB.get_or_empty(id).get("name", Ids.name_of(id))),
		"kind": str(ContentDB.get_or_empty(id).get("kind", "place" if id.begins_with("core:place") else "poi")),
		"region": str(e.get("region", World.region_id_at(Vector3(x, 0.0, z)))),
		"x": x, "z": z, "ground": ground, "level": float(p[1]),
		"stream_s": streamed, "wall_s": (Time.get_ticks_msec() - t) / 1000.0,
		"errors": int(errs["errors"]), "script_errors": int(errs["script_errors"]), "warnings": int(errs["warnings"]),
		"game_errors": Log.error_count - log_before, "said": errs["said"],
		"stand": _standing(lowest), "died": _deaths - deaths_before, "picture": pic,
		"ring": ring, "unstreamed": unstreamed, "load": _machine_load(),
	}
	row.merge(cost)
	_mend()
	return row


## Waits, up to `limit` seconds of wall clock, for the streamer's full ring round the body: the
## seconds it took, or -1 when it was still coming in.
func _wait_for_cells(limit_s: float) -> float:
	var t0 := Time.get_ticks_msec()
	# a frame for the streamer to see the body has moved
	await get_tree().process_frame
	await get_tree().process_frame
	while Time.get_ticks_msec() - t0 < int(limit_s * 1000.0):
		var world := World.instance
		if world == null or world.streamer == null or not is_instance_valid(_body):
			return -1.0
		if world.streamer.is_loaded_around(_body.global_position):
			return (Time.get_ticks_msec() - t0) / 1000.0
		await get_tree().process_frame
	return -1.0


## The cost of a frame here: the wall time between frames, the renderer's own CPU time, and what the
## frame drew. On the software renderers here the milliseconds are only good for comparing one place
## with another; the draw calls and primitives are what a GPU is given.
func _frame_cost() -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	var ms := 0.0
	var cpu := 0.0
	var draws := 0
	var prims := 0
	var objects := 0
	await get_tree().process_frame
	for k in SAMPLE_FRAMES:
		var t := Time.get_ticks_usec()
		await get_tree().process_frame
		ms += (Time.get_ticks_usec() - t) / 1000.0
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		objects = maxi(objects, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	return {"frame_ms": ms / SAMPLE_FRAMES, "render_cpu_ms": cpu / SAMPLE_FRAMES, "draws": draws,
		"primitives": prims, "objects": objects,
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))}


## What the body stands on, and what is wrong with where it stands. `lowest` is the lowest it went
## while it landed.
func _standing(lowest: float) -> Dictionary:
	if not is_instance_valid(_body):
		return {"on": "no body", "flags": ["no body"]}
	var at := _body.global_position
	var ground := World.get_height(at.x, at.z)
	var flags: Array[String] = []
	var floor_hit := _ray(at + Vector3.UP * 0.5, at + Vector3.DOWN * 4.0, LAYER_WORLD | LAYER_TERRAIN)
	var on := "nothing within 4 m"
	var on_is := "air"
	if not floor_hit.is_empty():
		var c := floor_hit.get("collider") as Node
		on_is = "ground" if _is_ground(c) else "thing"
		on = "the ground" if on_is == "ground" else _describe(c)
	var depth := _water_depth(at)
	var dy := at.y - ground
	if dy < -UNDER_M:
		flags.append("under the ground by %.1f m" % -dy)
	if lowest < ground - 2.0 and dy >= -UNDER_M:
		flags.append("fell %.1f m under the ground while landing" % (ground - lowest))
	if depth > DEEP_M:
		flags.append("in deep water (%.1f m)" % depth)
	elif depth > WET_M:
		flags.append("in water (%.1f m)" % depth)
	var shut := _shut_in(at)
	if shut != "":
		flags.append("inside %s" % shut)
	var on_floor := bool(_body.call("is_on_floor")) if _body.has_method("is_on_floor") else true
	if floor_hit.is_empty() or (not on_floor and dy > 2.0):
		flags.append("in the air %.1f m over the ground" % dy)
	var roof := _ray(at + Vector3.UP * 1.9, at + Vector3.UP * 30.0, LAYER_WORLD)
	return {"on": on, "on_is": on_is, "flags": flags, "dy": dy, "water_depth": depth, "on_floor": on_floor,
		"roof": _what(roof),
		"slope_deg": _slope_at(at), "y": at.y}


func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	if _body is CollisionObject3D:
		q.exclude = [(_body as CollisionObject3D).get_rid()]
	return _body.get_world_3d().direct_space_state.intersect_ray(q)


## What is solid in a body's room here (the quest walker's test): "" when the room is clear.
func _shut_in(at: Vector3) -> String:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.2
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = LAYER_WORLD
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.85, 0.0))
	if _body is CollisionObject3D:
		q.exclude = [(_body as CollisionObject3D).get_rid()]
	# the ground's own collision shares the world's layer, and a steep bank fills the room's foot
	for hit in _body.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var c := hit.get("collider") as Node
		if not _is_ground(c):
			return _describe(c)
	return ""


func _what(hit: Dictionary) -> String:
	if hit.is_empty():
		return ""
	var c := hit.get("collider") as Node
	return "the ground" if _is_ground(c) else _describe(c)


## A collider named by its nearest named owners below the cell: "Buildings/house_3/Body".
func _describe(node: Node) -> String:
	var names: Array[String] = []
	while node != null and names.size() < 3 and not str(node.name).begins_with("Cell_") and node != World.instance:
		names.push_front(str(node.name))
		node = node.get_parent()
	return "/".join(names) if not names.is_empty() else "the cell"


## The ground itself (Terrain3D's collision, or the coarse ground's), not a thing standing on it.
func _is_ground(node: Node) -> bool:
	if node == null:
		return true       # a collider with no node behind it is Terrain3D's own
	if node is CollisionObject3D and ((node as CollisionObject3D).collision_layer & LAYER_TERRAIN) != 0:
		return true
	while node != null:
		if node.is_class("Terrain3D") or str(node.name) == "Terrain3D":
			return true
		node = node.get_parent()
	return false


func _slope_at(at: Vector3) -> float:
	var dx := World.get_height(at.x + 1.0, at.z) - World.get_height(at.x - 1.0, at.z)
	var dz := World.get_height(at.x, at.z + 1.0) - World.get_height(at.x, at.z - 1.0)
	return rad_to_deg(atan(Vector2(dx, dz).length() / 2.0))


# --- the road walk ------------------------------------------------------------------------------

func _roads() -> int:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/roads.json"))
	var roads: Array = raw if raw is Array else []
	var ids := {}
	for s in (",".join(REGRESSION_ROADS) if only == "regressions" else only).split(",", false):
		ids[s.strip_edges()] = true
	var picked: Array = []
	for r: Dictionary in roads:
		var id := str(r.get("id", ""))
		if ids.is_empty() or ids.has(id) or ids.has(id.get_slice("/", 1)):
			picked.append(r)
	var end := picked.size() if limit < 0 else mini(picked.size(), from_index + limit)
	print("[ground] roads: %d listed, %d to %d this run" % [picked.size(), from_index, end - 1])
	var done := 0
	for i in range(from_index, end):
		if not is_instance_valid(_body):
			break
		var row := await _walk_road(i, picked[i] as Dictionary)
		_rows.store_line(JSON.stringify(row))
		_rows.flush()
		done += 1
		if str(row["id"]) in REGRESSION_ROADS and ((row["traps"] as Array).size() > 0 or not bool(row["reached"])):
			_failed.append("%s: %d traps, %.0f of %.0f m" % [row["id"], (row["traps"] as Array).size(),
					row["walked_m"], row["goal_m"]])
		print("ROAD %d/%d %s  %.0f of %.0f m in %.0f s  snags %d  traps %d  errors %d  script %d" % [i + 1, picked.size(),
				row["id"], row["walked_m"], row["length_m"], row["game_s"], (row["snags"] as Array).size(),
				(row["traps"] as Array).size(), row["errors"], row["script_errors"]])
	return done


func _walk_road(i: int, road: Dictionary) -> Dictionary:
	var pts: Array[Vector2] = []
	for q: Array in road.get("points", []):
		pts.append(Vector2(float(q[0]), float(q[1])))
	var length := 0.0
	for k in range(1, pts.size()):
		length += pts[k - 1].distance_to(pts[k])
	var goal_m := length if max_road_m <= 0.0 else minf(length, max_road_m)
	var before := _error_snapshot()
	var t := Time.get_ticks_msec()
	var row := {"i": i, "id": str(road.get("id", "")), "length_m": length, "goal_m": goal_m, "walked_m": 0.0,
		"game_s": 0.0, "wall_s": 0.0, "snags": [], "traps": [], "wet": [], "reached": false, "stream_waits": 0}
	if pts.size() < 2:
		return row
	_put(Vector3(pts[0].x, World.get_height(pts[0].x, pts[0].y) + 1.0, pts[0].y), _yaw_to(pts[0], pts[1]))
	if await _wait_for_cells(STREAM_LIMIT_S) < 0.0:
		_unstreamed.append("%s at its start" % row["id"])
	var forward := _key_for("move_forward")
	var sprint := _key_for("sprint")
	var tps := Engine.physics_ticks_per_second
	# the most game time a road gets: a slow walk's pace over its length, and a minute more
	var budget_ticks := int((goal_m / 2.5 + 60.0) * tps)
	var ticks := 0
	var along := 0.0            # how far along the road the body has come (its nearest point)
	var seg := 0
	var last_pos := _body.global_position
	var last_along := 0.0
	var stuck_ticks := 0
	var snag_open := false
	var tried := 0
	var wet_open := false
	_key(forward, true)
	_key(sprint, true)
	while ticks < budget_ticks and is_instance_valid(_body):
		# the country ahead has to be there before the body walks into it, as it would be for a
		# player on a machine that keeps up: a frame that stops the walk is not the road's fault
		if ticks % tps == 0 and not World.instance.streamer.is_loaded_around(_body.global_position, 1):
			_key(forward, false)
			row["stream_waits"] = int(row["stream_waits"]) + 1
			if await _wait_for_cells(STREAM_LIMIT_S) < 0.0:
				_unstreamed.append("%s at (%.0f, %.0f)" % [row["id"], _body.global_position.x, _body.global_position.z])
			_key(forward, true)
		var at := _body.global_position
		var at2 := Vector2(at.x, at.z)
		var near := _nearest_on(pts, at2, seg)
		seg = int(near["seg"])
		along = maxf(along, float(near["along"]))
		if along >= goal_m - ARRIVE_M or (seg >= pts.size() - 2 and at2.distance_to(pts[-1]) < ARRIVE_M):
			row["reached"] = true
			break
		_steer_to(_point_along(pts, float(near["along"]) + LOOKAHEAD_M))
		await get_tree().physics_frame
		ticks += 1
		# a wet foot is noted once per wading, with its deepest point
		var depth := _water_depth(_body.global_position)
		if depth > 0.5 and not wet_open:
			(row["wet"] as Array).append({"x": at.x, "z": at.z, "depth": depth})
			wet_open = true
		elif depth > 0.5:
			var w: Dictionary = (row["wet"] as Array)[-1]
			w["depth"] = maxf(float(w["depth"]), depth)
		elif depth < 0.2:
			wet_open = false
		if ticks % tps != 0:
			continue
		# once a second of the game's time: how much way was made
		_mend()
		if _watch.is_valid():
			_watch.call()
		# way made is way along the road, not movement: a step aside and back moves the body a
		# metre and gets it nowhere, and counted as movement it reset the snag every other second,
		# so a body held for eighteen minutes at Bell Street was never called trapped
		var moved := along - last_along
		last_along = along
		last_pos = _body.global_position
		if moved >= SNAG_M:
			stuck_ticks = 0
			snag_open = false
			tried = 0
			continue
		stuck_ticks += tps
		if not snag_open:
			snag_open = true
			(row["snags"] as Array).append(_snag_here())
		# what a player tries: a jump, then a step to either side
		tried += 1
		if tried == 1:
			await _tap(_key_for("jump"), 3)
		elif tried == 2:
			await _tap(_key_for("move_left"), tps >> 1)
		elif tried == 3:
			await _tap(_key_for("move_right"), tps)
		if float(stuck_ticks) / tps >= TRAP_S:
			var trap := _snag_here()
			trap["seconds"] = float(stuck_ticks) / tps
			(row["traps"] as Array).append(trap)
			var ahead := _point_along(pts, along + 15.0)
			_put(Vector3(ahead.x, World.get_height(ahead.x, ahead.y) + 1.0, ahead.y), _body.rotation.y)
			along += 15.0
			last_along = along
			last_pos = _body.global_position
			stuck_ticks = 0
			snag_open = false
			tried = 0
	_key(sprint, false)
	_key(forward, false)
	var errs := _error_delta(before)
	row["walked_m"] = minf(along, length)
	row["game_s"] = float(ticks) / tps
	row["wall_s"] = (Time.get_ticks_msec() - t) / 1000.0
	row["errors"] = errs["errors"]
	row["script_errors"] = errs["script_errors"]
	row["warnings"] = errs["warnings"]
	row["said"] = errs["said"]
	row["load"] = _machine_load()
	return row


## Where the body is snagged and what holds it: the thing in front at the knee and at the chest,
## the slope under it, and whether it is wet.
func _snag_here() -> Dictionary:
	var at := _body.global_position
	var ahead := -_body.global_transform.basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var knee := _ray(at + Vector3.UP * 0.4, at + Vector3.UP * 0.4 + ahead * 1.2, LAYER_WORLD | LAYER_TERRAIN)
	var chest := _ray(at + Vector3.UP * 1.3, at + Vector3.UP * 1.3 + ahead * 1.2, LAYER_WORLD | LAYER_TERRAIN)
	var rise := World.get_height(at.x + ahead.x * 2.0, at.z + ahead.z * 2.0) - World.get_height(at.x, at.z)
	return {"x": at.x, "z": at.z, "y": at.y, "region": World.region_id_at(at),
		"knee": _what(knee), "chest": _what(chest),
		"rise_deg": rad_to_deg(atan(rise / 2.0)), "water_depth": _water_depth(at),
		"inside": _shut_in(at)}


func _water_depth(at: Vector3) -> float:
	var t := World.terrain()
	if t == null:
		return 0.0
	var level := t.water_level_at(at.x, at.z)
	return 0.0 if level <= TerrainProvider.NO_WATER * 0.5 else maxf(level - at.y, 0.0)


## The nearest point of the road to `p`, searched a few segments either side of the last one.
func _nearest_on(pts: Array[Vector2], p: Vector2, seg: int) -> Dictionary:
	var best := {"seg": seg, "along": 0.0, "d": INF}
	var start_along := 0.0
	for k in range(0, maxi(seg - 3, 0)):
		start_along += pts[k].distance_to(pts[k + 1])
	var acc := start_along
	for k in range(maxi(seg - 3, 0), mini(seg + 6, pts.size() - 1)):
		var a := pts[k]
		var b := pts[k + 1]
		var ab := b - a
		var l := ab.length()
		var u := clampf((p - a).dot(ab) / maxf(l * l, 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * u)
		if d < float(best["d"]):
			best = {"seg": k, "along": acc + l * u, "d": d}
		acc += l
	return best


func _point_along(pts: Array[Vector2], m: float) -> Vector2:
	var acc := 0.0
	for k in range(pts.size() - 1):
		var l := pts[k].distance_to(pts[k + 1])
		if acc + l >= m:
			return pts[k].lerp(pts[k + 1], (m - acc) / maxf(l, 0.0001))
		acc += l
	return pts[-1]


## Turns the view toward `to`, the way the mouse turns it; the body's keys are camera-relative.
func _steer_to(to: Vector2) -> void:
	var rig: Node = _body.get("camera_rig")
	var yaw := _yaw_to(Vector2(_body.global_position.x, _body.global_position.z), to)
	if rig != null:
		rig.set("yaw", yaw)


static func _yaw_to(a: Vector2, b: Vector2) -> float:
	var d := b - a
	return atan2(-d.x, -d.y)


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


# --- the body, the keys, the errors ---------------------------------------------------------------

func _put(at: Vector3, yaw: float) -> void:
	if _body.has_method("teleport"):
		_body.call("teleport", at, yaw)
	else:
		_body.global_position = at


## Keeps the body alive and whole between places: a foe at a camp is the place's, not the probe's.
func _mend() -> void:
	if not is_instance_valid(_body):
		return
	if bool(_body.get("dead")) if "dead" in _body else false:
		if _body.has_method("respawn"):
			_body.call("respawn", _body.global_position + Vector3.UP, _body.rotation.y)
	if "health" in _body and "max_health" in _body:
		_body.set("health", _body.get("max_health"))


func _key_for(action: String) -> InputEventKey:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return ev as InputEventKey
	return null


func _key(key: InputEventKey, down: bool) -> void:
	if key == null:
		return
	var ev := key.duplicate() as InputEventKey
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _tap(key: InputEventKey, ticks: int) -> void:
	_key(key, true)
	for k in ticks:
		await get_tree().physics_frame
	_key(key, false)


## Every report ErrorLog holds, by what it said, with its count now.
func _error_snapshot() -> Dictionary:
	var out := {}
	var elog := get_node_or_null("/root/ErrorLog")
	if elog == null:
		return out
	for r: Dictionary in elog.call("sorted_reports"):
		out["%s|%s|%s" % [r["kind"], r["message"], r["source"]]] = int(r["count"])
	return out


## What was said since `before`: counts by kind, and the five most said lines.
func _error_delta(before: Dictionary) -> Dictionary:
	var errors := 0
	var script_errors := 0
	var warnings := 0
	var said: Array = []
	var elog := get_node_or_null("/root/ErrorLog")
	if elog != null:
		for r: Dictionary in elog.call("sorted_reports"):
			var key := "%s|%s|%s" % [r["kind"], r["message"], r["source"]]
			var n := int(r["count"]) - int(before.get(key, 0))
			if n <= 0:
				continue
			match str(r["kind"]):
				"script_error":
					script_errors += n
				"error", "shader_error":
					errors += n
				"warning":
					warnings += n
			if said.size() < 5:
				said.append({"kind": r["kind"], "n": n, "message": str(r["message"]).left(200), "source": r["source"]})
	return {"errors": errors, "script_errors": script_errors, "warnings": warnings, "said": said}


## The machine's one-minute load average, beside every measurement taken on it: a frame measured
## with eleven heavy runs on four cores costs several times what it costs alone. -1 off Linux.
static func _machine_load() -> float:
	var f := FileAccess.open("/proc/loadavg", FileAccess.READ)
	if f == null:
		return -1.0
	# a /proc file says it is empty, so get_as_text() reads nothing: read it a line at a time
	return float(f.get_line().get_slice(" ", 0))


func _wall(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


# --- the foes census ------------------------------------------------------------------------------

## How far round a point foes are counted, and how many points a region gets on its roads and off.
const FOES_RADIUS := 400.0
const FOES_ON_ROAD := 3
const FOES_OFF_ROAD := 2
const FOES_OFF_M := 300.0
## How far a road walk goes in each region, and how near a foe counts as met.
const FOES_WALK_M := 1000.0
const FOES_SEEN_NEAR := 60.0
const FOES_SEEN_FAR := 200.0
## Kills per foe kind for the drop count, and rolls of its table for the expected rate.
const FOES_KILLS := 10
const FOES_ROLLS := 2000
const FOES_LOOT_KINDS: Array[String] = ["core:enemy/poacher", "core:enemy/bravo"]


## Where the foes are, measured rather than read: at points on and off the roads of every region,
## the living foes within FOES_RADIUS against what the cells and the points of interest there say
## should stand; then a kilometre of road walked in each region on the keys, counting the foes met;
## a jump away and back to see the ring raise its foes again; and ten kills of each loot kind.
func _foes() -> int:
	WorldClock.set_time(13.0)
	var rows := 0
	var points := _foes_points()
	print("[ground] foes: %d points over %d regions" % [points.size(), _foes_regions().size()])
	var first := {}
	for p: Dictionary in points:
		var row := await _foes_at(p)
		if first.is_empty():
			first = row
		_emit(row)
		rows += 1
	# the ring raises its foes again when it comes back: the first point, after a jump away
	if not first.is_empty():
		var far := Vector2(float(first["x"]), float(first["z"])) + Vector2(2000.0, 0.0)
		_put(Vector3(far.x, World.get_height(far.x, far.y) + 1.0, far.y), 0.0)
		await _wait_for_cells(STREAM_LIMIT_S)
		var again := await _foes_at({"id": "%s again" % first["id"], "region": first["region"],
				"x": first["x"], "z": first["z"], "on_road": first["on_road"]})
		again["kind"] = "return"
		again["before"] = {"live": first["live"], "live_cells": first["live_cells"], "live_pois": first["live_pois"]}
		_emit(again)
		rows += 1
	for region: String in _foes_regions():
		var walk := await _foes_walk(region)
		_emit(walk)
		rows += 1
	for kind: String in FOES_LOOT_KINDS:
		_emit(await _foes_loot(kind))
		rows += 1
	return rows


func _emit(row: Dictionary) -> void:
	_rows.store_line(JSON.stringify(row))
	_rows.flush()
	print("FOES %s" % JSON.stringify(row).left(400))


func _foes_regions() -> Array[String]:
	var out: Array[String] = []
	for def: Dictionary in ContentDB.all("region"):
		out.append(str(def.get("id", "")))
	out.sort()
	return out


## Points on the roads of every region, spread along them, and as many again FOES_OFF_M off to
## the side of a road on dry ground.
func _foes_points() -> Array:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/roads.json"))
	var roads: Array = raw if raw is Array else []
	var by_region := {}
	for r: Dictionary in roads:
		var pts: Array = r.get("points", [])
		for k in range(0, pts.size() - 1, 8):
			var a := Vector2(float(pts[k][0]), float(pts[k][1]))
			var b := Vector2(float(pts[k + 1][0]), float(pts[k + 1][1]))
			var region := World.region_id_at(Vector3(a.x, 0.0, a.y))
			if not by_region.has(region):
				by_region[region] = []
			(by_region[region] as Array).append({"at": a, "side": (b - a).normalized().orthogonal(), "road": str(r.get("id", ""))})
	var out: Array = []
	for region: String in _foes_regions():
		var cands: Array = by_region.get(region, [])
		if cands.is_empty():
			continue
		var want := FOES_ON_ROAD + FOES_OFF_ROAD
		for n in want:
			var c: Dictionary = cands[int(float(n) * float(cands.size()) / float(want))]
			var at: Vector2 = c["at"]
			var on_road := n < FOES_ON_ROAD
			if not on_road:
				var side: Vector2 = c["side"]
				var off := at + side * FOES_OFF_M
				if World.is_water(off.x, off.y):
					off = at - side * FOES_OFF_M
				at = off
			out.append({"id": "%s %s %d" % [Ids.name_of(region), "road" if on_road else "off", n],
					"region": region, "x": at.x, "z": at.y, "on_road": on_road, "road": c["road"]})
	return out


## Stands the body at a point, lets the ring settle, and counts the foes there against the data.
func _foes_at(p: Dictionary) -> Dictionary:
	var x := float(p["x"])
	var z := float(p["z"])
	_put(Vector3(x, World.get_height(x, z) + 1.0, z), 0.0)
	var streamed := await _wait_for_cells(STREAM_LIMIT_S)
	var cap := Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 60
	for k in 60:
		await get_tree().physics_frame
	Engine.max_physics_steps_per_frame = cap
	_mend()
	var at := Vector3(x, 0.0, z)
	var live := _foes_live(at, FOES_RADIUS)
	var expect := _foes_expected(at, FOES_RADIUS)
	var row := {"kind": "point", "id": p["id"], "region": p["region"], "x": x, "z": z, "on_road": p["on_road"],
		"stream_s": streamed, "hour": WorldClock.time_hours, "load": _machine_load()}
	row.merge(live)
	row.merge(expect)
	return row


## The living foes within `radius` of `at`: all, those a cell's spawns raised, those a point of
## interest's encounter raised, and the rest (quests, summons), with their kinds.
func _foes_live(at: Vector3, radius: float) -> Dictionary:
	var all := 0
	var from_cells := 0
	var from_pois := 0
	var dead := 0
	var kinds := {}
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Node3D
		if e == null or not e.is_inside_tree():
			continue
		if _flat(e.global_position - at) > radius:
			continue
		if bool(e.get("dead")):
			dead += 1
			continue
		all += 1
		var holder := e.get_parent()
		if holder is PoiEncounters:
			from_pois += 1
		elif holder != null and str(holder.name) == "Encounters":
			from_cells += 1
		var id := str(e.get("enemy_id")).get_slice("/", 1)
		kinds[id] = int(kinds.get(id, 0)) + 1
	return {"live": all, "live_cells": from_cells, "live_pois": from_pois, "live_other": all - from_cells - from_pois,
		"dead_near": dead, "kinds": kinds, "enemies_in_tree": get_tree().get_nodes_in_group("enemy").size()}


## What the data says should stand within `radius` of `at`, counting only what the near ring
## raises (full_ring round the body): the cells' enemy spawns, and the encounter entries of the
## points of interest there that are open at this hour.
func _foes_expected(at: Vector3, radius: float) -> Dictionary:
	var streamer := World.instance.streamer if World.instance != null else null
	if streamer == null:
		return {}
	var near := {}
	for c: Vector2i in streamer.cells_around(_body.global_position):
		near[c] = true
	var cells_in_radius := 0
	var cells_near := 0
	for c: Vector2i in near:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/cells/%d_%d.json" % [c.x, c.y]))
		if not raw is Dictionary:
			continue
		for s: Variant in (raw as Dictionary).get("spawns", []):
			if not s is Dictionary or str((s as Dictionary).get("kind", "enemy")) != "enemy":
				continue
			cells_near += 1
			var sp: Array = (s as Dictionary).get("pos", [0, 0, 0])
			if _flat(Vector3(float(sp[0]), 0.0, float(sp[2])) - at) <= radius:
				cells_in_radius += 1
	var poi_expected := 0
	var poi_places: Array[String] = []
	var raw_pois: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/pois.json"))
	for e: Dictionary in (raw_pois if raw_pois is Array else []):
		var pp: Array = e["pos"]
		var pv := Vector3(float(pp[0]), 0.0, float(pp[2]))
		if _flat(pv - at) > radius or not near.has(streamer.cell_of(pv)):
			continue
		var n := 0
		for entry: Variant in PoiEncounters.of(str(e["place_id"])):
			if entry is Dictionary and PoiEncounters.is_open(str((entry as Dictionary).get("when", "always")), WorldClock.time_hours):
				n += int((entry as Dictionary).get("count", 1))
		if n > 0:
			poi_expected += n
			poi_places.append("%s x%d" % [str(e["place_id"]).get_slice("/", 1), n])
	return {"expect_cells_in_radius": cells_in_radius, "expect_cells_in_ring": cells_near,
		"expect_pois": poi_expected, "poi_places": poi_places}


## A kilometre of road in `region`, walked on the keys, counting the foes that came within
## FOES_SEEN_NEAR and FOES_SEEN_FAR, and how many stood in the whole tree as it went.
func _foes_walk(region: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/roads.json"))
	var best: Dictionary = {}
	var best_len := 0.0
	var best_from := 0
	for r: Dictionary in (raw if raw is Array else []):
		var pts: Array = r.get("points", [])
		# the longest run of this road inside the region
		var run := 0.0
		var from := 0
		for k in range(1, pts.size()):
			var a := Vector2(float(pts[k - 1][0]), float(pts[k - 1][1]))
			var b := Vector2(float(pts[k][0]), float(pts[k][1]))
			if World.region_id_at(Vector3(a.x, 0.0, a.y)) != region:
				run = 0.0
				from = k
				continue
			run += a.distance_to(b)
			if run > best_len:
				best_len = run
				best = r
				best_from = from
	if best.is_empty():
		return {"kind": "walk", "region": region, "why": "no road in the region"}
	var pts: Array = (best["points"] as Array).slice(best_from)
	var seen_near := {}
	var seen_far := {}
	var most := {"in_tree": 0}      # a lambda's own copy of an int would not come back out
	var t := Time.get_ticks_msec()
	# the road walk's own legs, with a look round every second of the game's time
	var watcher := func() -> void:
		for n in get_tree().get_nodes_in_group("enemy"):
			var e := n as Node3D
			if e == null or not e.is_inside_tree() or bool(e.get("dead")):
				continue
			var d := _flat(e.global_position - _body.global_position)
			if d <= FOES_SEEN_FAR:
				seen_far[e.get_instance_id()] = str(e.get("enemy_id")).get_slice("/", 1)
			if d <= FOES_SEEN_NEAR:
				seen_near[e.get_instance_id()] = str(e.get("enemy_id")).get_slice("/", 1)
		most["in_tree"] = maxi(int(most["in_tree"]), get_tree().get_nodes_in_group("enemy").size())
	_watch = watcher
	max_road_m = FOES_WALK_M
	var walk := await _walk_road(0, {"id": str(best["id"]), "points": pts})
	_watch = Callable()
	var near_kinds := {}
	for k: String in seen_near.values():
		near_kinds[k] = int(near_kinds.get(k, 0)) + 1
	return {"kind": "walk", "region": region, "road": best["id"], "walked_m": walk["walked_m"],
		"game_s": walk["game_s"], "seen_within_60": seen_near.size(), "seen_within_200": seen_far.size(),
		"near_kinds": near_kinds, "most_in_tree": most["in_tree"], "snags": (walk["snags"] as Array).size(),
		"traps": (walk["traps"] as Array).size(), "wall_s": (Time.get_ticks_msec() - t) / 1000.0, "load": _machine_load()}


## Ten of a kind stood up beside the body and killed by it, and what they dropped, against what
## FOES_ROLLS rolls of the same table give.
func _foes_loot(kind: String) -> Dictionary:
	var drops: Node = get_tree().get_first_node_in_group("loot_drops")
	var spawner := EnemySpawner.for_node(_body)
	var got: Array = []
	var on_drop := func(results: Array, _pos: Vector3, enemy_id: String) -> void:
		if enemy_id == kind:
			got.append(results)
	if drops != null:
		drops.connect("dropped", on_drop)
	for k in FOES_KILLS:
		var at := _body.global_position + Vector3(3.0 + float(k), 0.0, 3.0)
		var foe := spawner.spawn_one(kind, at, 0.0) if spawner != null else null
		if foe == null:
			continue
		await get_tree().physics_frame
		foe.die(_body)
		for w in 3:
			await get_tree().physics_frame
	if drops != null:
		drops.disconnect("dropped", on_drop)
	var weapons := 0
	var kills_with_weapon := 0
	for results: Array in got:
		var had := false
		for r: Dictionary in results:
			if _is_weapon(str(r.get("item", ""))):
				weapons += 1
				had = true
		if had:
			kills_with_weapon += 1
	# the expected rate: the same table rolled FOES_ROLLS times in the same context
	var expected := 0
	if drops != null:
		var def := ContentDB.get_or_empty(kind)
		var ctx: Dictionary = drops.call("context")
		ctx["level"] = int(_body.call("get_level")) if _body.has_method("get_level") else 1
		for k in FOES_ROLLS:
			for r: Dictionary in drops.call("drops_for", def, ctx):
				if _is_weapon(str(r.get("item", ""))):
					expected += 1
					break
	return {"kind": "loot", "enemy": kind, "kills": got.size(), "kills_with_a_weapon": kills_with_weapon,
		"weapons": weapons, "drops": got, "expected_share_with_a_weapon": float(expected) / FOES_ROLLS,
		"loot_drops_present": drops != null}


func _is_weapon(item_id: String) -> bool:
	return item_id != "" and str(ContentDB.get_or_empty(item_id).get("category", "")) == "weapon"
