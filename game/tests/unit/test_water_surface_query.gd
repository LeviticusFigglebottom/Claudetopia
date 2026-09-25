extends TestCase
## WaterSurface.surface_at, which swimming stands on: the water where the player is, its surface,
## how deep, which way a river runs. Checked against the built world's own files, at points found
## from them, so it holds for whatever world is installed.

var _water: WaterSurface = null
var _rivers: Array = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _built() -> WaterSurface:
	if _water == null:
		var p := TerrainProvider.new()
		p.load_data()
		_water = WaterSurface.new()
		_tree().root.add_child(_water)
		_water.add_child(p)
		_water.build(p)
		_rivers = JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/rivers.json"))
	return _water


func after_each() -> void:
	if _water != null:
		_tree().root.remove_child(_water)
		_water.free()
		_water = null


## A point mid-channel on a river, away from its falls and its mouth: the river index, the point.
func _mid_river() -> Array:
	for i in _rivers.size():
		var r: Dictionary = _rivers[i]
		var pts: Array = r.get("points", [])
		var surf: Array = r.get("surface_m", [])
		if pts.size() < 40 or surf.size() != pts.size():
			continue
		for k in range(int(pts.size() / 3.0), int(pts.size() * 2 / 3.0)):
			var ok := true
			for span in RiverFalls.spans(r):
				if k >= int(span[0]) - 2 and k <= int(span[1]) + 2:
					ok = false
			if ok and float(surf[k]) > 12.0:
				return [i, k]
	return []


func test_a_river_is_its_ribbon_running_downstream() -> void:
	var w := _built()
	var found := _mid_river()
	assert_false(found.is_empty(), "a river reach to stand in")
	if found.is_empty():
		return
	var r: Dictionary = _rivers[found[0]]
	var k: int = found[1]
	var a: Array = r["points"][k]
	var b: Array = r["points"][k + 1]
	var mid := Vector2((float(a[0]) + float(b[0])) * 0.5, (float(a[1]) + float(b[1])) * 0.5)
	var s := w.surface_at(mid.x, mid.y)
	assert_true(bool(s["has"]), "there is water mid-channel (%s)" % str(s))
	assert_eq(str(s["kind"]), "river", "and it is the river")
	var want := (float(r["surface_m"][k]) + float(r["surface_m"][k + 1])) * 0.5
	assert_true(float(s["y"]) <= want + 0.05 and float(s["y"]) >= want - 1.5,
			"at the river's surface there (%.2f, the file %.2f; lowered to a bank by at most most of the channel)" % [float(s["y"]), want])
	var down := Vector3(float(b[0]) - float(a[0]), 0.0, float(b[1]) - float(a[1])).normalized()
	var flow: Vector3 = s["flow"]
	assert_gt(flow.length(), WaterSurface.RIVER_SPEED.x - 0.01, "running")
	assert_gt(flow.normalized().dot(down), 0.9, "downstream")
	# thirty metres off to the side, out of the channel, there is none
	var side := Vector2(-down.z, down.x) * 30.0
	var dry := w.surface_at(mid.x + side.x, mid.y + side.y)
	assert_true(not bool(dry["has"]) or str(dry["kind"]) != "river", "and none thirty metres to the side")


func test_a_lake_and_the_sea_are_their_levels_and_still() -> void:
	var w := _built()
	var p := w.provider
	var lakes := {}
	for lake in p.manifest.get("lakes", []):
		lakes[str(lake["id"])] = float(lake["level_m"])
	# the deepest texel of the map at the Mere's level, and at the sea's
	var best_lake := Vector3(0.0, 0.0, -1.0)
	var best_sea := Vector3(0.0, 0.0, -1.0)
	var g := p.runtime_grid()
	var sp := p.runtime_spacing()
	for iz in range(0, g, 7):
		for ix in range(0, g, 7):
			var x := p.origin.x + float(ix) * sp
			var z := p.origin.y + float(iz) * sp
			if not p.is_water(x, z):
				continue
			var l := p.nearest_water_level(x, z)
			var d := l - p.sample_height(x, z)
			if absf(l - float(lakes.get("the_mere", 8.0))) < 0.1 and d > best_lake.z:
				best_lake = Vector3(x, z, d)
			if absf(l - p.sea_level) < 0.1 and d > best_sea.z:
				best_sea = Vector3(x, z, d)
	var mere := w.surface_at(best_lake.x, best_lake.y)
	assert_true(bool(mere["has"]), "the Mere has water")
	assert_eq(str(mere["kind"]), "lake", "and it is a lake")
	assert_near(float(mere["y"]), float(lakes.get("the_mere", 8.0)), 0.05, "at the Mere's level")
	assert_gt(float(mere["depth"]), 1.8, "deep enough to swim in (%.1f m)" % float(mere["depth"]))
	assert_eq((mere["flow"] as Vector3), Vector3.ZERO, "and still")
	var sea := w.surface_at(best_sea.x, best_sea.y)
	assert_eq(str(sea["kind"]), "sea", "the sea is the sea")
	assert_near(float(sea["y"]), p.sea_level, 0.05, "at sea level")


func test_dry_ground_has_no_water() -> void:
	var w := _built()
	var start: Array = w.provider.manifest.get("start", {}).get("pos", [10.0, 107.0, 3670.0])
	var s := w.surface_at(float(start[0]), float(start[2]))
	assert_false(bool(s["has"]), "none where the game starts, on dry ground")
	assert_eq(float(s["depth"]), 0.0, "and no depth")
	assert_eq(WaterSurface.under(Vector3(float(start[0]), float(start[1]) + 1.7, float(start[2]))), 0.0,
			"and a camera there is not under water")


func test_a_pool_is_its_level_and_a_camera_under_it_is_under() -> void:
	var w := _built()
	var pool: Dictionary = {}
	for f in RiverFalls.read_falls(_rivers):
		if typeof(f.get("pool", null)) == TYPE_DICTIONARY:
			pool = f["pool"]
			break
	assert_false(pool.is_empty(), "a fall with a pool")
	if pool.is_empty():
		return
	var c: Array = pool["centre"]
	var s := w.surface_at(float(c[0]), float(c[2]))
	assert_true(bool(s["has"]), "water in the pool (%s)" % str(s))
	assert_true(str(s["kind"]) == "pool" or str(s["kind"]) == "river", "the pool's, or the river running out of it")
	assert_near(float(s["y"]), float(c[1]), 0.6, "at the pool's level")
	var eye := Vector3(float(c[0]), float(s["y"]) - 0.5, float(c[2]))
	assert_near(WaterSurface.under(eye), 0.5, 0.01, "a camera half a metre down is half a metre under")


func test_it_is_cheap_enough_for_every_tick() -> void:
	var w := _built()
	var found := _mid_river()
	var r: Dictionary = _rivers[found[0]] if not found.is_empty() else {}
	var at: Array = r["points"][found[1]] if not found.is_empty() else [0.0, 0.0]
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		w.surface_at(float(at[0]) + float(i % 20) * 0.3, float(at[1]))
	var each := float(Time.get_ticks_usec() - t0) / 2000.0
	assert_true(each < 200.0, "a query costs %.1f µs" % each)
