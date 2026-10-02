extends TestCase
## Everything the world stands up at its places stands on something: no lamp in the air, no
## fence length alone in a field, no prop over the grass or through a road. One test a region, so
## `./run.sh test --filter=objects_seated_skerrow` looks at one. SEAT_BASELINE_WRITE=1 writes the
## counts as they stand as the baseline, after a fix has brought them down:
##
##   ./run.sh test --filter=test_objects_seated              (all six)
##   ./run.sh test --filter=objects_seated_hearthvale        (one)
##
## Each streams the region's places a few at a time (the three by three cells round each, up to
## PLACES_PER_REGION of them) and runs tools_gd/seat_audit.gd over them, then holds the counts by
## check against tools/debug/seat_baseline.json: a count may fall, and may not grow. `./run.sh
## seats` (drawn, the whole map) is where the numbers come from and where the baseline is written.
##
## Headless, a MultiMesh keeps no instances, so the cells' plain scatter (grass, herbs, hedges and
## walls) is not seen here; the scatter drawn by level of detail (trees, rocks, big props) is read
## from the cells' data, and everything the runtime places -- the points of interest, the
## settlements, the wayside's posts and gates, the lights -- is looked at whole.

const WORLD_SCENE := "res://world/world.tscn"
const AUDIT := preload("res://tools_gd/seat_audit.gd")
const BASELINE := "res://../tools/debug/seat_baseline.json"
## Places looked at per region: enough to meet every kind of builder, few enough to be quick.
const PLACES_PER_REGION := 8

var _w: World = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if _w != null and is_instance_valid(_w):
		_tree().root.remove_child(_w)
		_w.queue_free()
	_w = null


func test_objects_seated_hearthvale() -> void:
	await _region("hearthvale")


func test_objects_seated_briarwold() -> void:
	await _region("briarwold")


func test_objects_seated_brightwater() -> void:
	await _region("brightwater")


func test_objects_seated_sedgemire() -> void:
	await _region("sedgemire")


func test_objects_seated_skerrow() -> void:
	await _region("skerrow")


func test_objects_seated_cinderlea() -> void:
	await _region("cinderlea")


## The places of a region the built world lists, spread along it: every nth of them.
static func places_in(region: String, pois: Array, most: int) -> Array[Vector2]:
	var mine: Array[Vector2] = []
	for e: Dictionary in pois:
		var id := str(e.get("place_id", ""))
		var def := ContentDB.get_or_empty(id)
		if str(def.get("region", "")) != "core:region/%s" % region:
			continue
		var p: Array = e["pos"]
		mine.append(Vector2(float(p[0]), float(p[2])))
	if mine.size() <= most:
		return mine
	var out: Array[Vector2] = []
	for i in most:
		out.append(mine[int(float(i) * float(mine.size()) / float(most))])
	return out


## The counts a run found, by check, against the baseline's: the checks whose count grew.
static func grown(found: Dictionary, baseline: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for check: String in found:
		var was := int(baseline.get(check, 0))
		if int(found[check]) > was:
			out.append("%s %d (baseline %d)" % [check, int(found[check]), was])
	return out


func _region(region: String) -> void:
	if not FileAccess.file_exists("res://world/generated/pois.json"):
		print("    (no built world: run ./run.sh world; skipped)")
		return
	# SEAT_PLACES_FROM=<a pois.json>: the places another build's list picks, so two builds are
	# measured at the same places (a build that adds places to a region picks others from its own)
	var from := OS.get_environment("SEAT_PLACES_FROM")
	var list := from if from != "" and FileAccess.file_exists(from) else "res://world/generated/pois.json"
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(list))
	var places := places_in(region, raw if raw is Array else [], PLACES_PER_REGION)
	assert_true(places.size() > 0, "the built world lists places in %s" % region)
	if places.is_empty():
		return
	_w = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(_w)
	await _w.world_ready
	if _w.streamer == null:
		print("    (no streamer; skipped)")
		return
	var audit = AUDIT.new(_w)
	var seen := {}
	for at in places:
		_w.move_target(Vector3(at.x, World.get_height(at.x, at.y) + 2.0, at.y))
		var until := Time.get_ticks_msec() + 120000
		await _tree().process_frame
		await _tree().process_frame
		while Time.get_ticks_msec() < until and not _w.streamer.is_loaded_around(Vector3(at.x, 0.0, at.y)):
			await _tree().process_frame
		for k in 3:
			await _tree().process_frame
		var cells: Array = []
		for c: Vector2i in _w.streamer.cells_around(Vector3(at.x, 0.0, at.y)):
			if not seen.has(c):
				seen[c] = true
				cells.append(c)
		audit.audit_cells(cells)
	var found := {}
	for f: Dictionary in audit.findings:
		found[str(f["check"])] = int(found.get(str(f["check"]), 0)) + 1
	var examples := {}
	for f: Dictionary in audit.findings:
		var k := str(f["check"])
		if not examples.has(k):
			examples[k] = "%s %s at (%.0f, %.0f): %s" % [f["src"], f["family"], f["x"], f["z"], f["detail"]]
	print("    %s: %d cells, %d things, findings %s" % [region, seen.size(), audit.looked_at, str(found)])
	# SEAT_FINDINGS_OUT=<dir>: every finding, for reading which things a count is made of
	var dump := OS.get_environment("SEAT_FINDINGS_OUT")
	if not dump.is_empty():
		DirAccess.make_dir_recursive_absolute(dump)
		var out := FileAccess.open(dump.path_join("%s.json" % region), FileAccess.WRITE)
		out.store_string(JSON.stringify(audit.findings, " "))
		out.close()
	var base := {}
	var path := ProjectSettings.globalize_path(BASELINE)
	if FileAccess.file_exists(path):
		var b: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if b is Dictionary:
			base = (b as Dictionary).get(region, {})
	if OS.get_environment("SEAT_BASELINE_WRITE") == "1":
		# the counts as they stand become the baseline for this region (the others are kept)
		var all := {}
		if FileAccess.file_exists(path):
			var b2: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if b2 is Dictionary:
				all = b2
		all[region] = found
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(all, " ", true) + "\n")
		f.close()
		print("    %s: baseline written" % region)
		return
	var worse := grown(found, base)
	assert_true(worse.is_empty(), "%s: more unseated things than the baseline: %s (e.g. %s)" % [region,
		", ".join(PackedStringArray(worse)), str(examples)])
	assert_true(audit.looked_at > 0, "it looked at something")


func test_a_family_is_an_asset_without_its_region_and_variant() -> void:
	assert_eq(AUDIT.family("res://assets/models/props/hearthvale_hedge_segment_b/hearthvale_hedge_segment_b.glb"), "hedge_segment")
	assert_eq(AUDIT.family("cinderlea_cliff_slab_a_x16_body"), "cliff_slab")
	assert_eq(AUDIT.family("res://assets/models/props/cinderlea_tent_b/cinderlea_tent_b.glb"), "tent")
	assert_eq(AUDIT.family("grass_clump"), "grass_clump")


func test_a_count_may_fall_and_may_not_grow() -> void:
	assert_empty(grown({"floating": 3}, {"floating": 5}))
	assert_eq(grown({"floating": 6, "fence_lone": 1}, {"floating": 5}).size(), 2, "one grew, one is new")
