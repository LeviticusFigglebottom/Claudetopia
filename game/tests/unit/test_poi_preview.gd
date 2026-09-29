extends TestCase
## A POI written since the last world build stands where its def says, on a pad laid at runtime
## (PoiPreview, docs/WORLD_LIFE.md): the pad is the build's shape, the entry replaces a built one
## only when asked for, and the cells' scatter is cleared off the pad and moved with its skirt.
##
## Headless, on the runtime height map alone (no Terrain3D): TerrainProvider.lay_pad changes that
## copy as it changes Terrain3D's.

const GENERATED := "res://world/generated"
const ID := "core:poi/larkbourne_ford"

var provider: TerrainProvider = null
var built: Array = []


func before_each() -> void:
	PoiPreview.clear()
	PoiPreview.auto = true
	if provider != null:
		return
	if not FileAccess.file_exists("%s/pois.json" % GENERATED):
		skip("world data missing: run ./run.sh world")
		return
	provider = TerrainProvider.new()
	provider.load_data()
	built = JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED))


func after_each() -> void:
	PoiPreview.clear()
	PoiPreview.auto = true


func test_a_pad_is_the_builds_size() -> void:
	assert_eq(PoiPreview.pad_radius({"kind": "ruins"}), 25.0)
	assert_eq(PoiPreview.pad_radius({"kind": "camp"}), 22.0)
	assert_eq(PoiPreview.pad_radius({"kind": "cairn", "wayside": true}), 14.0)
	assert_eq(PoiPreview.pad_radius({"kind": "ruins", "pad_radius_m": 48}), 48.0, "a larger place asks for its own")


func test_the_built_world_is_left_alone_unless_asked() -> void:
	if provider == null:
		return
	# the POIs written since the last build (the world-life regions' new places) are wanted; nothing the
	# build has is, until it is asked for
	var ids := {}
	for e: Dictionary in built:
		ids[str(e["place_id"])] = true
	var fresh := PoiPreview.wanted(built)
	for d: Dictionary in fresh:
		assert_false(ids.has(str(d["id"])), "%s is in the built world, and was not asked for" % str(d["id"]))
	PoiPreview.ask(["larkbourne_ford"])
	var w := PoiPreview.wanted(built)
	assert_eq(w.size(), fresh.size() + 1)
	assert_true(w.any(func(d: Dictionary) -> bool: return str(d["id"]) == ID), "asked for by its short name")


func test_one_the_build_has_not_seen_is_stood_up_on_a_pad() -> void:
	if provider == null:
		return
	var without: Array = built.filter(func(e: Dictionary) -> bool: return str(e["place_id"]) != ID)
	var def := ContentDB.get_or_empty(ID)
	var xz := WorldProbe.xz_of(def)
	var pad := PoiPreview.pad_for(def, provider)
	var fresh := PoiPreview.wanted(without).size()
	var out := PoiPreview.apply(without, provider)
	assert_eq(out.size(), without.size() + fresh, "its entry is put in")
	var got: Dictionary = {}
	for e: Dictionary in out:
		if str(e["place_id"]) == ID:
			got = e
	assert_eq(str(got.get("place_id", "")), ID)
	assert_true(bool(got.get("preview", false)), "marked as a preview")
	assert_near(float(got["pos"][1]), float(pad["level"]), 0.001, "stood at the pad's level")
	assert_eq(float(got["radius_flat_m"]), 25.0)
	# level on its core, as it was past its reach
	for a in 8:
		var ang := TAU * a / 8.0
		# (the runtime map is 8 m a texel: a point is read off texels up to 11 m from it)
		var core := xz + Vector2(cos(ang), sin(ang)) * (float(pad["level_radius"]) - 11.5)
		assert_near(provider.get_height(core.x, core.y), float(pad["level"]), 0.05, "level on its core")
	assert_eq(PoiPreview.pads.size(), fresh)


func test_asked_for_it_replaces_the_built_entry() -> void:
	if provider == null:
		return
	var fresh := PoiPreview.wanted(built).size()
	PoiPreview.ask([ID])
	var out := PoiPreview.apply(built, provider)
	assert_eq(out.size(), built.size() + fresh, "replaced, not added")
	var n := 0
	for e: Dictionary in out:
		if str(e["place_id"]) == ID:
			n += 1
			assert_true(bool(e.get("preview", false)))
	assert_eq(n, 1)


func test_the_scatter_is_cleared_off_the_pad_and_follows_its_skirt() -> void:
	PoiPreview.pads = [{"id": "x", "x": 0.0, "z": 0.0, "level": 10.0, "radius": 20.0, "level_radius": 14.0, "reach": 32.0}]
	var data := {"instances": {"tree": [[5.0, 12.0, 5.0, 0.0, 1.0, "#fff"], [0.0, 16.0, 25.0, 0.0, 1.0, "#fff"],
			[100.0, 30.0, 0.0, 0.0, 1.0, "#fff"]]}}
	PoiPreview.clear_cell(data)
	var rows: Array = data["instances"]["tree"]
	assert_eq(rows.size(), 2, "the one on the pad is gone")
	assert_true(float(rows[0][1]) < 16.0 and float(rows[0][1]) > 10.0, "the one on the skirt came down toward the pad")
	assert_eq(float(rows[1][1]), 30.0, "the one past the reach is left")


## A region's own builder (the def's `builder`, in world/pois/regions/<region>.gd) builds the place,
## and a name the region's script does not have builds it as its kind.
func test_a_regions_own_builder_builds_the_place() -> void:
	if provider == null:
		return
	var host := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var at := [-30.0, provider.get_height(-30.0, 1560.0), 1560.0]
	var own := PoiDressing.raise({"place_id": "core:poi/_test_mark", "pos": at, "radius_flat_m": 14.0},
			{"id": "core:poi/_test_mark", "kind": "cairn", "region": "core:region/_test", "builder": "marked_cairn"},
			false, provider, [])
	var plain := PoiDressing.raise({"place_id": "core:poi/_test_plain", "pos": at, "radius_flat_m": 14.0},
			{"id": "core:poi/_test_plain", "kind": "cairn", "region": "core:region/_test", "builder": "no_such"},
			false, provider, [])
	host.add_child(own)
	host.add_child(plain)
	for i in 120:
		if own.finished and plain.finished:
			break
		await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(own.finished and plain.finished, "both built")
	assert_true(own.find_child("RegionalMark", false, false) != null, "the region's builder ran")
	assert_gt(own.mesh_count(), 0, "and built on its kind's")
	assert_true(plain.find_child("RegionalMark", false, false) == null, "a missing builder is its kind's")
	assert_gt(plain.mesh_count(), 0)
	host.queue_free()
