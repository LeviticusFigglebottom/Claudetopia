extends TestCase
## The generated world as data: the manifest, the maps, cell indexing, and the places.
##
## These tests read res://world/generated, which `./run.sh world` builds. When the data is
## missing they report that once and skip, so a fresh clone can still run the suite; CI builds
## the world first (run.sh does it automatically when the manifest is absent).

const GENERATED := "res://world/generated"
const MERROWBY := "core:place/merrowby"
const HUSHLINE := "core:place/hushline"
const WINDGATE := "core:place/windgate"

var manifest: Dictionary = {}
var provider: TerrainProvider = null
var _scratch: Node = null


## Nodes under test need a tree (the streamer uses WorkerThreadPool and signals).
func add_child_for_test(node: Node) -> void:
	if _scratch == null:
		_scratch = Node.new()
		_scratch.name = "WorldDataTestScratch"
		Engine.get_main_loop().root.add_child(_scratch)
	_scratch.add_child(node)


static var _warned_missing := false


func before_each() -> void:
	if provider != null:
		return
	if not FileAccess.file_exists("%s/world_manifest.json" % GENERATED):
		if not _warned_missing:
			_warned_missing = true
			print("  (world data missing: run ./run.sh world; world tests skipped)")
		return
	provider = TerrainProvider.new()
	provider.load_data()
	manifest = provider.manifest


func _skip() -> bool:
	return provider == null


func test_manifest_matches_the_contract() -> void:
	if _skip():
		return
	for key in ["seed", "size_m", "spacing_m", "origin", "grid", "sea_level", "lake_level",
			"regions", "cell_size_m", "cells"]:
		assert_has(manifest, key, "world_manifest.json is missing %s" % key)
	assert_eq(int(manifest["size_m"]), 8192)
	assert_eq(int(manifest["cell_size_m"]), 256)
	assert_eq(int(manifest["lake_level"]), 8)
	var cells: Array = manifest["cells"]
	assert_eq(int(cells[0]), 32)
	assert_eq(int(cells[1]), 32)
	var grid := int(manifest["grid"])
	assert_eq(float(manifest["size_m"]) / float(grid), float(manifest["spacing_m"]))
	var origin: Array = manifest["origin"]
	assert_eq(float(origin[0]), -float(manifest["size_m"]) / 2.0)


func test_region_list_matches_the_content_pack() -> void:
	if _skip():
		return
	var ids: Array = manifest["regions"]
	assert_eq(ids.size(), ContentDB.all("region").size())
	for id in ids:
		assert_true(ContentDB.has(id), "manifest names unknown region %s" % id)


## Each region is the kind of country its map block says: its ground, taken over every texel the
## built region mask gives it, stands on average in its band. It used to be read at the region
## def's `map.center`, a point that stays where it was written when the map is redrawn and the
## region goes somewhere else (docs/COORDINATES.md).
func test_each_region_stands_at_its_height() -> void:
	if _skip():
		return
	var expected := {
		"core:region/hearthvale": [15.0, 140.0],
		"core:region/brightwater": [-15.0, 90.0],
		"core:region/sedgemire": [-5.0, 40.0],
		"core:region/briarwold": [20.0, 400.0],
		"core:region/skerrow": [120.0, 700.0],
		"core:region/cinderlea": [30.0, 170.0],
	}
	var ids: Array = manifest.get("regions", [])
	var sums := PackedFloat64Array()
	var counts := PackedInt64Array()
	sums.resize(ids.size())
	counts.resize(ids.size())
	var heights := provider.runtime_heights()
	var regions := provider.runtime_regions()
	for i in mini(heights.size(), regions.size()):
		var r := regions[i]
		if r < ids.size():
			sums[r] += heights[i]
			counts[r] += 1
	for r in ids.size():
		var id := str(ids[r])
		assert_gt(counts[r], 0, "%s has no ground in the region mask" % id)
		if counts[r] == 0:
			continue
		var mean := sums[r] / float(counts[r])
		var range_v: Array = expected.get(id, [-50.0, 800.0])
		assert_true(mean >= float(range_v[0]) and mean <= float(range_v[1]),
			"%s stands at %.1f m on average, expected %s" % [id, mean, str(range_v)])


## The Mere, wherever the map puts it: the deepest water standing at the manifest's lake level
## (the biggest lake's; DESIGN §4 has the Mere at 8 m), with how much of the map lies at that
## level. {"at": Vector2, "depth": m, "km2": area}; depth 0 when there is no such water.
func _the_mere() -> Dictionary:
	var level := float(manifest.get("lake_level", 8.0))
	var step := 32.0
	var best := Vector2.ZERO
	var deepest := 0.0
	var texels := 0
	var z := -4096.0 + step * 0.5
	while z < 4096.0:
		var x := -4096.0 + step * 0.5
		while x < 4096.0:
			if provider.is_water(x, z) and absf(provider.water_level_at(x, z) - level) < 0.6:
				texels += 1
				var d := provider.water_depth_at(x, z)
				if d > deepest:
					deepest = d
					best = Vector2(x, z)
			x += step
		z += step
	return {"at": best, "depth": deepest, "km2": float(texels) * step * step / 1e6}


func test_world_height_extremes() -> void:
	if _skip():
		return
	# the Mere sits at 8 m and the northern peaks reach 600-700 m (DESIGN.md §4); each is found
	# by what it is -- the lake's water, the wall behind Windgate, the Hushline's own place --
	# rather than at the coordinates it had before the map was redrawn
	var mere: Vector2 = _the_mere()["at"]
	var lake := provider.get_height(mere.x, mere.y)
	assert_true(lake < 20.0, "the middle of the Mere is %.1f m" % lake)
	var gate := PlaceRef.xz(WINDGATE)
	var peak := provider.max_height_around(gate.x, gate.y, 600.0, 24)
	assert_gt(peak, 450.0, "the northern wall only reaches %.1f m" % peak)
	var hushline := PlaceRef.xz(HUSHLINE)
	var hush := provider.get_height(hushline.x, hushline.y)
	assert_true(hush < 10.0, "the Hushline should fall away, it is %.1f m" % hush)


func test_region_mask_agrees_with_place_data() -> void:
	if _skip():
		return
	var checked := 0
	for place in ContentDB.all("place"):
		var pos: Array = place.get("position", [])
		if pos.size() < 2:
			continue
		var x := float(pos[0])
		var z := float(pos[1])
		var id := provider.nearest_region_id_at(x, z)
		assert_eq(id, str(place["region"]), "%s sits in %s" % [place["id"], id])
		checked += 1
	assert_gt(checked, 20)


func test_settlements_are_out_of_the_water() -> void:
	if _skip():
		return
	for place in ContentDB.all("place"):
		if not str(place.get("kind", "")) in ["city", "town", "village", "hamlet", "fort", "camp"]:
			continue
		var pos: Array = place["position"]
		var x := float(pos[0])
		var z := float(pos[1])
		assert_false(provider.is_water(x, z), "%s stands in water" % place["id"])


func test_water_levels() -> void:
	if _skip():
		return
	var mere := _the_mere()
	var at: Vector2 = mere["at"]
	assert_gt(float(mere["km2"]), 1.0, "the Mere is a lake, not a pond: %.2f km² at its level" % float(mere["km2"]))
	assert_true(provider.is_water(at.x, at.y), "the middle of the Mere should be water")
	assert_near(provider.water_level_at(at.x, at.y), 8.0, 0.6)
	var town := PlaceRef.xz(MERROWBY)
	assert_false(provider.is_water(town.x, town.y), "Merrowby should be dry")
	assert_eq(provider.water_level_at(town.x, town.y), TerrainProvider.NO_WATER)
	assert_gt(provider.water_depth_at(at.x, at.y), 2.0)


func test_cell_index_maths() -> void:
	if _skip():
		return
	# cx = floor((x + 4096) / 256), cz likewise (docs/CONTRACTS.md §6)
	var streamer := WorldStreamer.new()
	streamer.provider = provider
	streamer.setup(provider, null)
	assert_eq(streamer.cell_of(Vector3(-4096.0, 0.0, -4096.0)), Vector2i(0, 0))
	assert_eq(streamer.cell_of(Vector3(-3841.0, 0.0, -4096.0)), Vector2i(0, 0))
	assert_eq(streamer.cell_of(Vector3(-3840.0, 0.0, -4096.0)), Vector2i(1, 0))
	assert_eq(streamer.cell_of(Vector3(0.0, 0.0, 0.0)), Vector2i(16, 16))
	assert_eq(streamer.cell_of(Vector3(4095.0, 0.0, 4095.0)), Vector2i(31, 31))
	var centre := streamer.cell_centre(Vector2i(16, 16))
	assert_near(centre.x, 128.0)
	assert_near(centre.y, 128.0)
	streamer.free()


func test_every_cell_file_exists_and_parses() -> void:
	if _skip():
		return
	var cells: Array = manifest["cells"]
	var wide := int(cells[0])
	var missing := 0
	var with_instances := 0
	var region_ids: Array = manifest["regions"]
	for cz in [0, 7, 16, 23, 31]:
		for cx in [0, 7, 16, 23, 31]:
			if cx >= wide or cz >= wide:
				continue
			var path := "%s/cells/%d_%d.json" % [GENERATED, cx, cz]
			if not FileAccess.file_exists(path):
				missing += 1
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			assert_true(typeof(parsed) == TYPE_DICTIONARY, "%s is not an object" % path)
			var cell: Dictionary = parsed
			assert_has(cell, "cell")
			assert_has(cell, "region")
			assert_has(cell, "instances")
			assert_has(cell, "scenes")
			assert_eq(int(cell["cell"][0]), cx)
			assert_eq(int(cell["cell"][1]), cz)
			if not str(cell["region"]).is_empty():
				assert_true(region_ids.has(str(cell["region"])), "%s has region %s" % [path, cell["region"]])
			if not (cell["instances"] as Dictionary).is_empty():
				with_instances += 1
	assert_eq(missing, 0, "%d sampled cell files are missing" % missing)
	assert_gt(with_instances, 0, "no sampled cell has any scatter")


func test_scatter_rows_have_the_contract_shape() -> void:
	if _skip():
		return
	var found := false
	for cz in [12, 16, 20]:
		for cx in [12, 16, 20]:
			var path := "%s/cells/%d_%d.json" % [GENERATED, cx, cz]
			if not FileAccess.file_exists(path):
				continue
			var cell: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			for asset_path in cell["instances"]:
				assert_true(str(asset_path).begins_with("res://assets/models/"),
					"scatter asset path %s" % asset_path)
				var rows: Array = cell["instances"][asset_path]
				for row in rows:
					assert_eq((row as Array).size(), 6, "a scatter row is [x, y, z, yaw, scale, tint]")
					var x := float(row[0])
					var z := float(row[2])
					var expect := Vector2i(cx, cz)
					var got := Vector2i(int(floor((x + 4096.0) / 256.0)), int(floor((z + 4096.0) / 256.0)))
					assert_eq(got, expect, "an instance at (%.1f, %.1f) is filed in cell %s" % [x, z, str(expect)])
					found = true
					break
				break
	assert_true(found, "no scatter rows were found to check")


func test_pois_sit_on_the_ground() -> void:
	if _skip():
		return
	var path := "%s/pois.json" % GENERATED
	assert_true(FileAccess.file_exists(path), "pois.json is missing")
	var pois: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_gt(pois.size(), 20)
	for poi in pois:
		var entry: Dictionary = poi
		assert_has(entry, "place_id")
		assert_has(entry, "pos")
		assert_has(entry, "radius_flat_m")
		var pos: Array = entry["pos"]
		var ground := provider.get_height(float(pos[0]), float(pos[2]))
		assert_near(float(pos[1]), ground, 2.0, "%s is %.1f m off the ground" % [entry["place_id"], float(pos[1]) - ground])
		if entry.has("scene"):
			assert_true(ResourceLoader.exists(str(entry["scene"])),
				"%s points at a scene that does not exist: %s" % [entry["place_id"], entry["scene"]])


func test_rivers_and_roads_are_sane() -> void:
	if _skip():
		return
	var rivers: Array = JSON.parse_string(FileAccess.get_file_as_string("%s/rivers.json" % GENERATED))
	assert_gt(rivers.size(), 2, "expected the Skerrow water, the outflow and its feeders")
	for river in rivers:
		var r: Dictionary = river
		assert_gt((r["points"] as Array).size(), 8)
		assert_true(float(r["width_m"]) >= 4.0 and float(r["width_m"]) <= 14.0,
			"%s is %.1f m wide" % [r["id"], float(r["width_m"])])
		# water runs downhill: the surface at the mouth is below the source
		assert_true(float(r["surface_to_m"]) <= float(r["surface_from_m"]),
			"%s runs uphill" % r["id"])
	var roads: Array = JSON.parse_string(FileAccess.get_file_as_string("%s/roads.json" % GENERATED))
	assert_gt(roads.size(), 5)
	var linked := {}
	for road in roads:
		var r: Dictionary = road
		assert_true(float(r["width_m"]) >= 4.0 and float(r["width_m"]) <= 6.0)
		var points: Array = r["points"]
		assert_gt(points.size(), 4)
		for name in str(r["id"]).trim_prefix("core:road/").split("_", false):
			linked[name] = true
	assert_gt(linked.size(), 4, "the road network barely connects anything")


func test_streamer_builds_multimeshes_from_a_cell() -> void:
	if _skip():
		return
	# The scatter assets themselves are still to come from the forge, so this drives the
	# streamer's instancing path with a fixture mesh: one MultiMesh per asset per cell,
	# instance transforms in cell-local space, tint carried as instance colour, and exactly
	# one warning for an asset that does not exist yet.
	var streamer := WorldStreamer.new()
	add_child_for_test(streamer)
	streamer.setup(provider, null)
	var cell := Vector2i(16, 16)
	var centre := streamer.cell_centre(cell)
	var data := {
		"cell": [cell.x, cell.y],
		"region": "core:region/brightwater",
		"instances": {
			"res://tests/fixtures/test_scatter_mesh.tres": [
				[centre.x, 12.0, centre.y, 90.0, 1.5, "#ff8844"],
				[centre.x + 4.0, 13.0, centre.y + 4.0, 0.0, 0.8, "#224466"],
			],
			"res://assets/models/trees/does_not_exist/does_not_exist.glb": [
				[centre.x, 12.0, centre.y, 0.0, 1.0, "#ffffff"],
			],
		},
		"scenes": [], "spawns": [], "lights": [],
	}
	var warnings_before := Log.warning_count
	streamer._build_cell(cell, 0, data)
	var node: Node3D = streamer.get_node_or_null("Cell_16_16")
	assert_true(node != null, "the cell node was not built")
	var mmis: Array[Node] = []
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			mmis.append(child)
	assert_eq(mmis.size(), 1, "only the asset that exists should become a MultiMesh")
	var mmi: MultiMeshInstance3D = mmis[0]
	assert_eq(mmi.multimesh.instance_count, 2)
	assert_true(mmi.multimesh.use_colors)
	assert_true(mmi.multimesh.mesh != null)
	assert_true(mmi.visibility_range_end > 0.0, "scatter needs a LOD cut-off")
	# The per-instance data lives in the rendering server, which is a stub in a headless run,
	# so the placement maths is checked through the (pure) helpers the streamer uses.
	var row: Array = [centre.x, 12.0, centre.y, 90.0, 1.5, "#ff8844"]
	var xform := WorldStreamer.instance_transform(row, Vector3(centre.x, 0.0, centre.y))
	assert_near(xform.origin.x, 0.0, 0.01, "instances are stored relative to the cell")
	assert_near(xform.origin.y, 12.0, 0.01)
	assert_near(xform.origin.z, 0.0, 0.01)
	assert_near(xform.basis.get_scale().x, 1.5, 0.01)
	assert_near(rad_to_deg(xform.basis.get_euler().y), 90.0, 0.1)
	assert_near(WorldStreamer.instance_tint(row).r, Color("#ff8844").r, 0.01)
	assert_near(WorldStreamer.instance_tint([0, 0, 0, 0, 1]).g, 1.0, 0.01)
	assert_eq(Log.warning_count, warnings_before + 1, "a missing asset should warn exactly once")
	streamer._build_cell(Vector2i(17, 16), 0, data)
	assert_eq(Log.warning_count, warnings_before + 1, "the same missing asset warned twice")
	assert_eq(streamer.instance_count(), 4)
	streamer.unload_all()
	streamer.queue_free()


func test_provider_normals_and_slopes() -> void:
	if _skip():
		return
	var town := PlaceRef.xz(MERROWBY)
	var flat := provider.get_normal(town.x, town.y)     # a settlement pad is flat by construction
	assert_gt(flat.y, 0.9, "a flattened pad should have an upward normal, got %s" % str(flat))
	assert_near(flat.length(), 1.0, 0.01)
	var slope := provider.get_slope(town.x, town.y)
	assert_true(slope < 0.4, "the pad slope is %.2f rad" % slope)
