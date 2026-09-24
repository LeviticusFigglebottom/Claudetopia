extends TestCase
## The falls: every one rivers.json records drawn from its lip to its foot with its pool, white
## water and mist; a waterfall place's own plain sheet and pool replaced by the same, or left out
## where the river draws the water; and the rivers' ribbons in their carved channels, cut where a
## fall is drawn instead. A river ribbon alone ran down a fall as a slide, a near-vertical sheet
## lit as if it lay flat.

const RIVERS := [
	{"id": "a", "points": [], "falls": [
		{"top": [0.0, 100.0, 0.0], "foot": [0.0, 88.0, 3.0], "height_m": 12.0, "width_m": 4.0,
			"run_m": 3.0, "facing_deg": 0.0, "kind": "fall",
			"pool": {"centre": [0.0, 88.0, 6.0], "radius_m": 5.0, "depth_m": 2.0}},
		{"top": [200.0, 60.0, 0.0], "foot": [205.0, 56.0, 0.0], "height_m": 4.0, "width_m": 6.0,
			"run_m": 5.0, "facing_deg": 90.0, "kind": "cascade"}]},
	{"id": "b", "points": []},
	"not a river",
]

var host: Node3D


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	host = Node3D.new()
	host.name = "RiverFallsHost"
	_tree().root.add_child(host)


func after_each() -> void:
	RiverFalls.all.clear()
	_tree().root.remove_child(host)
	host.free()


func _rivers_on_disk() -> Array:
	var path := "%s/rivers.json" % WaterSurface.GENERATED
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Array else []


func test_every_fall_is_read_and_nothing_else() -> void:
	assert_eq(RiverFalls.read_falls(RIVERS).size(), 2)


func test_each_fall_draws_a_sheet_from_lip_to_foot() -> void:
	var falls := RiverFalls.new()
	assert_eq(falls.build(RIVERS), 2)
	for i in 2:
		var f: Dictionary = RIVERS[0]["falls"][i]
		var node: Node3D = falls.get_node("Fall%d" % i)
		var sheet: MeshInstance3D = node.get_node("Sheet")
		var aabb := sheet.mesh.get_aabb()
		var drop := float(f["top"][1]) - float(f["foot"][1])
		assert_near(aabb.position.y, -drop, 0.3, "fall %d's sheet reaches its foot" % i)
		assert_near(aabb.end.y, 0.0, 0.3, "fall %d's sheet starts at its lip" % i)
		assert_gt(aabb.size.x + aabb.size.z, float(f["width_m"]), "fall %d's sheet is as wide as the river" % i)
		assert_true((sheet.material_override as ShaderMaterial).shader == RiverFalls.WATERFALL_SHADER,
			"fall %d is drawn as falling water" % i)
		assert_true(node.get_node_or_null("Pool") != null, "fall %d lands in churning water" % i)
		assert_true(node.get_node_or_null("Spray") != null, "fall %d throws up white water" % i)
	# the tall one has mist as well; the low cascade only the white water
	assert_true(falls.get_node("Fall0").get_node_or_null("Mist") != null, "a 12 m fall raises mist")
	assert_true(falls.get_node("Fall1").get_node_or_null("Mist") == null, "a 4 m cascade does not")
	# the pool is the one the file gives, where it gives one
	var pool: MeshInstance3D = falls.get_node("Fall0/Pool")
	assert_near(pool.position.z, 6.0, 0.01, "the pool stands at its centre")
	assert_near(float((pool.material_override as ShaderMaterial).get_shader_parameter("radius_m")), 5.0, 0.01)
	assert_near(float((falls.get_node("Fall1/Sheet") as MeshInstance3D).material_override.get_shader_parameter("cascade")), 1.0, 0.001,
		"a cascade is drawn stepped")
	falls.free()


## The sheet's normal faces out along the fall, not up: a ribbon run down a fall was lit as a
## floor stood on end.
func test_a_fall_faces_out_not_up() -> void:
	var mesh := RiverFalls.sheet_mesh(Vector3.ZERO, Vector3(0.0, -20.0, 4.0), 5.0, Vector3.BACK, false)
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for n in normals:
		assert_true(absf(n.y) < 0.5, "a falling sheet's normal is not up (%s)" % n)
		if absf(n.y) >= 0.5:
			break


func test_every_fall_in_the_world_is_drawn() -> void:
	var rivers := _rivers_on_disk()
	if rivers.is_empty():
		print("  (world data missing: falls test skipped)")
		return
	var want := RiverFalls.read_falls(rivers)
	assert_gt(want.size(), 0, "the world has falls")
	var falls := RiverFalls.new()
	host.add_child(falls)
	assert_eq(falls.build(rivers), want.size(), "one drawn fall for every fall in rivers.json")
	for i in want.size():
		var f: Dictionary = want[i]
		var node := falls.get_node_or_null("Fall%d" % i) as Node3D
		assert_true(node != null, "fall %d is drawn" % i)
		if node == null:
			continue
		var sheet := node.get_node_or_null("Sheet") as MeshInstance3D
		assert_true(sheet != null and sheet.mesh != null, "fall %d has its sheet" % i)
		if sheet == null:
			continue
		var box := sheet.mesh.get_aabb()
		var top: Array = f["top"]
		var foot: Array = f["foot"]
		assert_near(node.position.y + box.end.y, float(top[1]), 0.6, "fall %d starts at its lip" % i)
		assert_near(node.position.y + box.position.y, float(foot[1]), 0.8, "fall %d reaches its foot" % i)
		assert_true(RiverFalls.near(Vector3(float(foot[0]), 0.0, float(foot[2])), 1.0), "fall %d can be asked for" % i)
		if f.has("pool"):
			assert_true(node.get_node_or_null("Pool") != null, "fall %d's pool is drawn" % i)
	falls.queue_free()


## Where a waterfall place stands at a fall a river draws, the place keeps its rock and its lip
## and draws no water of its own: no Fall sheet, no Pool.
func test_a_place_at_a_drawn_fall_leaves_the_water_to_it() -> void:
	var falls := RiverFalls.new()
	falls.build([{"id": "t", "points": [], "falls": [
		{"top": [0.0, 62.0, -6.0], "foot": [0.0, 50.0, 0.0], "height_m": 12.0, "width_m": 5.0,
			"run_m": 6.0, "facing_deg": 180.0, "kind": "fall"}]}])
	var d := _dress_waterfall()
	assert_true(d.find_children("lip*", "Marker3D", true, false).size() > 0, "the lip is still marked")
	for n in d.find_children("*", "GeometryInstance3D", true, false):
		var name := str(n.name)
		if name.begins_with("Fall") or name.begins_with("Pool"):
			assert_false((n as GeometryInstance3D).visible, "%s is not drawn by the place" % name)
	falls.free()


## Where no river's fall is drawn, the place's plain sheet and pool are replaced by the fall as
## the rivers' falls are drawn: the same falling water, a churning pool, white water and mist.
func test_a_place_of_its_own_draws_a_proper_fall() -> void:
	RiverFalls.all.clear()
	var d := _dress_waterfall()
	var fall := d.find_child("Fall", true, false) as MeshInstance3D
	assert_true(fall != null, "the fall is still there to be framed")
	if fall == null:
		return
	assert_true((fall.material_override as ShaderMaterial).shader == RiverFalls.WATERFALL_SHADER,
		"drawn as falling water, not the plain sheet")
	assert_gt(fall.mesh.get_aabb().size.y, 7.0, "from the lip to the pool")
	var pools := 0
	for n in d.find_children("Pool*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.is_queued_for_deletion():
			continue
		pools += 1
		assert_true((mi.material_override as ShaderMaterial).shader == RiverFalls.POOL_SHADER, "%s churns" % mi.name)
	assert_eq(pools, 1, "one pool drawn")
	assert_true(d.find_child("Spray", true, false) != null, "white water where it lands")
	assert_true(d.find_child("Mist", true, false) != null, "and mist over it")


func _dress_waterfall() -> PoiDressing:
	var id := "core:poi/test_waterfall"
	var entry := {"place_id": id, "pos": [0.0, 50.0, 0.0], "radius_flat_m": 30.0}
	var def := {"id": id, "name": "Waterfall", "kind": "waterfall", "region": "core:region/hearthvale",
			"unique_feature": "a single white sheet off the scarp", "encounter": ""}
	var d := PoiDressing.raise(entry, def, false, null, [])
	host.add_child(d)
	return d


func test_a_place_can_ask_whether_a_fall_is_its_own() -> void:
	var falls := RiverFalls.new()
	falls.build(RIVERS)
	assert_true(RiverFalls.near(Vector3(2.0, 90.0, 4.0)), "beside the tall fall")
	assert_true(RiverFalls.near(Vector3(204.0, 0.0, 10.0)), "beside the cascade")
	assert_false(RiverFalls.near(Vector3(100.0, 0.0, 0.0)), "between them")
	falls.free()


## The ribbon stops at a fall's lip and starts again at its foot: no quad of it spans the fall.
func test_the_ribbon_is_cut_over_a_fall() -> void:
	var ws := WaterSurface.new()
	var entry := {"id": "test:river/falls", "width_m": 4.0,
		"points": [[0.0, 0.0], [0.0, 10.0], [0.0, 15.0], [0.0, 25.0], [0.0, 35.0]],
		"surface_m": [30.0, 29.8, 20.0, 19.9, 19.8],
		"falls": [{"top": [0.0, 29.8, 10.0], "foot": [0.0, 20.0, 15.0], "height_m": 9.8, "width_m": 4.0,
			"run_m": 5.0, "facing_deg": 0.0, "kind": "fall"}]}
	var mesh := ws._river_mesh(entry)
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in range(0, idx.size(), 3):
		var ys := [verts[idx[i]].y, verts[idx[i + 1]].y, verts[idx[i + 2]].y]
		assert_true(ys.max() - ys.min() < 1.0, "no triangle of the ribbon runs down the fall (%s)" % str(ys))
	assert_eq(idx.size(), 3 * 6, "three of the four stretches drawn")
	ws.free()


## Water never stands above its bed by more than the carve allows: every ribbon vertex drawn is
## at the river's own surface, and that surface is no higher over the ground on its centre line
## than the channel the builder carved there (worldgen/hydro.py carve_rivers: 1.1 m and a tenth
## of the width), with the runtime height map's own tolerance -- 0.75 m, and the drop across one
## of its eight-metre texels where the ground slopes, since its heights are block means.
func test_the_water_sits_in_its_channel() -> void:
	var rivers := _rivers_on_disk()
	var provider := TerrainProvider.new()
	if rivers.is_empty() or not provider.load_data() or not provider.has_runtime_maps():
		print("  (world data missing: channel test skipped)")
		provider.free()
		return
	var ws := WaterSurface.new()
	ws.provider = provider
	var checked := 0
	var over: Array[String] = []
	for entry in rivers:
		var pts: Array = entry.get("points", [])
		var surf: Array = entry.get("surface_m", [])
		var mesh := ws._river_mesh(entry)
		if mesh == null or surf.size() != pts.size():
			continue
		var arr := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var colours: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var drawn := {}
		for k in idx:
			drawn[int(k) >> 1] = true
		var w_from := float(entry.get("width_from_m", entry.get("width_m", 6.0)))
		var w_to := float(entry.get("width_to_m", entry.get("width_m", 6.0)))
		for i: int in drawn:
			if colours[i * 2].a <= 0.0:
				continue
			var y := verts[i * 2].y
			var s := float(surf[i])
			assert_true(y <= s + 0.01, "%s %d: the ribbon is not lifted off its surface (%.2f over)" % [entry["id"], i, y - s])
			var p: Array = pts[i]
			var x := float(p[0])
			var z := float(p[1])
			var t := float(i) / float(pts.size() - 1)
			var depth := 1.1 + 0.1 * lerpf(w_from, w_to, pow(t, 0.7))
			var slope := maxf(absf(provider.sample_height(x + 8.0, z) - provider.sample_height(x - 8.0, z)),
					absf(provider.sample_height(x, z + 8.0) - provider.sample_height(x, z - 8.0))) / 16.0
			var tolerance := 0.75 + 8.0 * slope
			var excess := y - provider.sample_height(x, z) - depth
			checked += 1
			if excess > tolerance:
				over.append("%s %d at (%.0f, %.0f): %.2f m over its carve" % [entry["id"], i, x, z, excess])
	assert_gt(checked, 1000, "the rivers were checked (%d points)" % checked)
	assert_eq(over.size(), 0, "water above its bed: %s" % ", ".join(over.slice(0, 8)))
	ws.free()
	provider.free()
