extends Node
## Smoke test: load the world and walk the camera over every region centre and every place,
## waiting for streaming at each stop. Fails on any logged error, any missing world data, any
## implausible ground height and any place that does not report the region it belongs to.
##
##   ./run.sh smoke          (boot.gd routes `-- --smoke` here)
##
## Prints "SMOKE: PASS" or "SMOKE: FAIL" with details, and exits 0/1.

const WORLD_SCENE := "res://world/world.tscn"
const SETTLE_FRAMES := 3
const MAX_WAIT_FRAMES := 120
const VIEW_HEIGHT := 40.0

## Plausible ground height per region shape, from the region map blocks (metres).
const HEIGHT_RANGE := {
	"core:region/hearthvale": [5.0, 160.0],
	"core:region/brightwater": [-20.0, 120.0],
	"core:region/sedgemire": [-10.0, 60.0],
	"core:region/briarwold": [5.0, 420.0],
	"core:region/skerrow": [20.0, 760.0],
	"core:region/cinderlea": [-30.0, 190.0],
}

var _world: World = null
var _problems: Array[String] = []
var _stops := 0
var _errors_at_start := 0


func _ready() -> void:
	var code: int = await run()
	get_tree().quit(code)


func run() -> int:
	_errors_at_start = Log.error_count
	var t0 := Time.get_ticks_msec()
	if not ResourceLoader.exists(WORLD_SCENE):
		_fail("world scene missing: %s" % WORLD_SCENE)
		return _finish(t0)
	var packed: PackedScene = load(WORLD_SCENE)
	_world = packed.instantiate() as World
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	if _world.streamer:
		_world.streamer.cells_per_frame = 12      # the smoke run teleports; build at full speed
	if _world.provider == null or _world.provider.manifest.is_empty():
		_fail("world data missing; run ./run.sh world")
		return _finish(t0)
	_check_manifest()
	await _visit_regions()
	await _visit_places()
	_check_streamer()
	return _finish(t0)


func _check_manifest() -> void:
	var p := _world.provider
	var m := p.manifest
	for key in ["seed", "size_m", "spacing_m", "grid", "regions", "cells", "runtime"]:
		if not m.has(key):
			_fail("world_manifest.json missing '%s'" % key)
	if p.region_ids.size() != ContentDB.all("region").size():
		_fail("manifest lists %d regions, the content pack has %d"
			% [p.region_ids.size(), ContentDB.all("region").size()])
	if not p.has_terrain():
		Log.warn("Smoke", "Terrain3D data is not loaded; heights come from the runtime map")


func _visit_regions() -> void:
	for region in ContentDB.all("region"):
		var map: Dictionary = region.get("map", {})
		var centre: Array = map.get("center", [0, 0])
		var x := float(centre[0])
		var z := float(centre[1])
		await _go(x, z, "region %s" % region["id"])
		var h := _world.provider.get_height(x, z)
		var range_v: Array = HEIGHT_RANGE.get(region["id"], [-50.0, 800.0])
		if h < float(range_v[0]) or h > float(range_v[1]):
			_fail("%s centre height %.1f m outside %s" % [region["id"], h, str(range_v)])
		var here := _world.provider.nearest_region_id_at(x, z)
		if here != region["id"]:
			_fail("%s centre reports region %s" % [region["id"], here])


func _visit_places() -> void:
	for place in ContentDB.all("place"):
		var pos: Array = place.get("position", [])
		if pos.size() < 2:
			continue
		var x := float(pos[0])
		var z := float(pos[1])
		await _go(x, z, str(place["id"]))
		var h := _world.provider.get_height(x, z)
		if is_nan(h):
			_fail("%s: height is NaN" % place["id"])
			continue
		if h < -60.0 or h > 800.0:
			_fail("%s: implausible height %.1f m" % [place["id"], h])
		var kind := str(place.get("kind", ""))
		if kind in ["town", "city", "village", "hamlet", "fort", "camp"] and _world.provider.is_water(x, z):
			_fail("%s (%s) stands in water" % [place["id"], kind])
		var region := _world.provider.nearest_region_id_at(x, z)
		if region != str(place.get("region", "")):
			_fail("%s is in %s but its data says %s" % [place["id"], region, place.get("region", "")])


func _go(x: float, z: float, what: String) -> void:
	var ground := _world.provider.get_height(x, z)
	var pos := Vector3(x, ground + VIEW_HEIGHT, z)
	_world.move_target(pos, Vector3(x, ground, z + 60.0))
	var frames := 0
	while frames < MAX_WAIT_FRAMES:
		await get_tree().process_frame
		frames += 1
		if _world.streamer == null or _world.streamer.is_ring_loaded():
			break
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	_stops += 1
	if frames >= MAX_WAIT_FRAMES:
		_fail("streaming never settled at %s" % what)


func _check_streamer() -> void:
	if _world.streamer == null:
		_fail("no WorldStreamer")
		return
	var cells := _world.streamer.loaded_count()
	if cells <= 0:
		_fail("no cells loaded after visiting %d places" % _stops)
	if GameState.current_region_id.is_empty():
		_fail("GameState never entered a region")


func _fail(msg: String) -> void:
	_problems.append(msg)


func _finish(t0: int) -> int:
	var logged := Log.error_count - _errors_at_start
	if logged > 0:
		_problems.append("%d errors were logged during the run" % logged)
	var ms := Time.get_ticks_msec() - t0
	print("SMOKE: %d stops, %d cells loaded, %d problems, %d ms"
		% [_stops, _world.streamer.loaded_count() if _world and _world.streamer else 0, _problems.size(), ms])
	for p in _problems:
		print("  - %s" % p)
	if _problems.is_empty():
		print("SMOKE: PASS")
		return 0
	print("SMOKE: FAIL")
	return 1
