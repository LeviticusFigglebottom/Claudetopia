extends TestCase
## What stands at the points of interest. Seventy-three of the eighty-two entries in
## `pois.json` were a flattened pad and a name; every one of them is raised at runtime now,
## deterministically from its id, with something to look at, something to bump into, and a
## Hearthstone wherever the data promises one — including the three settlements the main quest
## rests at, where no stone had ever stood.
##
## These read the built world (`./run.sh world`); when it is missing they say so once and skip.

const GENERATED := "res://world/generated"

var provider: TerrainProvider = null
var pois: Array = []
var roads: Array = []
var _scratch: Node = null


func before_each() -> void:
	if provider != null:
		return
	if not FileAccess.file_exists("%s/pois.json" % GENERATED):
		skip("world data missing: run ./run.sh world")
		return
	provider = TerrainProvider.new()
	provider.load_data()
	pois = JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED))
	roads = WorldPois.roads_from_disk()


func _skip() -> bool:
	return provider == null


func _host() -> Node:
	if _scratch == null or not is_instance_valid(_scratch):
		_scratch = Node3D.new()
		_scratch.name = "PoiTestScratch"
		(Engine.get_main_loop() as SceneTree).root.add_child(_scratch)
	return _scratch


func _entry(id: String) -> Dictionary:
	for e in pois:
		if str((e as Dictionary).get("place_id", "")) == id:
			return e
	return {}


func _raise(id: String, far := false) -> PoiDressing:
	var entry := _entry(id)
	assert_false(entry.is_empty(), "%s is not in pois.json" % id)
	var d := PoiDressing.raise(entry, ContentDB.get_or_empty(id), far, provider, roads)
	_host().add_child(d)
	return d


func _drop(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.free()


# --- every kind, every POI --------------------------------------------------------------------------

func test_every_poi_kind_in_the_pack_has_a_builder() -> void:
	var unbuilt: Array[String] = []
	for def in ContentDB.all("poi"):
		var kind := str(def.get("kind", ""))
		if not PoiDressing.KINDS.has(kind):
			unbuilt.append("%s (%s)" % [def.get("id", "?"), kind])
	assert_true(unbuilt.is_empty(), "POI kinds nobody knows how to dress: %s" % ", ".join(unbuilt))


## The kinds no builder exists for yet, named in the run rather than hidden by it.
static func _pending_kinds() -> Array[String]:
	var out: Array[String] = []
	for kind in PoiDressing.KINDS:
		if not PoiDressing.KINDS_BUILT.has(kind):
			out.append(kind)
	return out


func _built(item: Dictionary) -> bool:
	var entry: Dictionary = item["entry"]
	return PoiDressing.KINDS_BUILT.has(PoiDressing.kind_of(str(entry["place_id"]), item["def"]))


func test_every_poi_in_the_world_raises_a_dressing() -> void:
	if _skip():
		return
	var pending := _pending_kinds()
	if not pending.is_empty():
		print("  (POI kinds still to be dressed: %s)" % ", ".join(pending))
	var checked := 0
	var bare: Array[String] = []
	var walk_through: Array[String] = []
	var wrong_stone: Array[String] = []
	for item_v in WorldPois.candidates(pois):
		var item: Dictionary = item_v
		if not _built(item):
			continue
		var entry: Dictionary = item["entry"]
		var def: Dictionary = item["def"]
		var id := str(entry["place_id"])
		var errors_before := Log.error_count
		var warnings_before := Log.warning_count
		var d := PoiDressing.raise(entry, def, false, provider, roads)
		_host().add_child(d)
		checked += 1
		if d.mesh_count() == 0:
			bare.append(id)
		if bool(PoiDressing.KINDS.get(d.kind, false)) and d.body_count() == 0:
			walk_through.append(id)
		var wants := bool(def.get("hearthstone", false)) or d.kind == "hearth"
		if (d.hearthstones().size() == 1) != wants:
			wrong_stone.append("%s (%d stones, wanted %s)" % [id, d.hearthstones().size(), str(wants)])
		assert_eq(Log.error_count, errors_before, "%s logged an error while being dressed" % id)
		assert_eq(Log.warning_count, warnings_before, "%s logged a warning while being dressed" % id)
		_drop(d)
	assert_gt(checked, 0, "no POI of a built kind stands in the world")
	if pending.is_empty():
		assert_gt(checked, 50, "expected the 48 POIs and the shrine-tagged places, got %d" % checked)
	assert_true(bare.is_empty(), "POIs with nothing to look at: %s" % ", ".join(bare))
	assert_true(walk_through.is_empty(), "POIs with nothing to bump into: %s" % ", ".join(walk_through))
	assert_true(wrong_stone.is_empty(), "Hearthstones not as the data says: %s" % ", ".join(wrong_stone))


## Every collider a POI's own builder puts up says what a foot lands on (stone, wood, dirt ...),
## so a bridge deck, a wall top, a stair or a pier is heard as what it is and not as the ground
## under it. The forged props' bodies take theirs from the asset's name, and a bush or a banner
## leaves it to the ground; those are counted, not required.
func test_every_poi_collider_says_what_it_is_underfoot() -> void:
	if _skip():
		return
	var built := 0
	var silent := {}
	var by_surface := {}
	var props_left_to_ground := 0
	for item_v in WorldPois.candidates(pois):
		var item: Dictionary = item_v
		if not _built(item):
			continue
		var entry: Dictionary = item["entry"]
		var id := str(entry["place_id"])
		var d := PoiDressing.raise(entry, item["def"], false, provider, roads)
		_host().add_child(d)
		for body_v in d.find_children("*", "StaticBody3D", true, false):
			var body := body_v as StaticBody3D
			for cs_v in body.find_children("*", "CollisionShape3D", false, false):
				var cs := cs_v as CollisionShape3D
				var surface := str(cs.get_meta(PoiKit.SURFACE_META, body.get_meta(PoiKit.SURFACE_META, "")))
				if body.name == "Masonry":
					built += 1
					if surface.is_empty():
						silent[id] = int(silent.get(id, 0)) + 1
				elif surface.is_empty():
					props_left_to_ground += 1
				if not surface.is_empty():
					by_surface[surface] = int(by_surface.get(surface, 0)) + 1
		_drop(d)
	print("MEASURE | POI collision shapes by what they are underfoot | %s | built shapes %d | props left to the ground %d"
			% [str(by_surface), built, props_left_to_ground])
	assert_gt(built, 100, "the builders put up their own colliders")
	assert_true(silent.is_empty(), "built colliders that name no surface, by POI: %s" % str(silent))


## What a forged asset is made of underfoot, from its name.
func test_a_forged_asset_says_what_it_is_made_of() -> void:
	var cases := {
		"res://assets/models/props/sedgemire/sedgemire_boardwalk_plank_a.glb": "wood",
		"res://assets/models/props/sedgemire/sedgemire_dock_post_b.glb": "wood",
		"res://assets/models/props/hearthvale/hearthvale_cart_a.glb": "wood",
		"res://assets/models/props/briarwold/briarwold_stool_a.glb": "wood",
		"res://assets/models/props/hearthvale/hearthvale_signpost_a.glb": "wood",
		"res://assets/models/props/skerrow/skerrow_drystone_wall_a.glb": "stone",
		"res://assets/models/props/hearthvale/hearthvale_cliff_slab_b.glb": "stone",
		"res://assets/models/props/hearthvale/hearthvale_gravestone_a.glb": "stone",
		"res://assets/models/props/cinderlea/cinderlea_bone_finger_a.glb": "stone",
		"res://assets/models/props/skerrow/skerrow_scree_c.glb": "gravel",
		"res://assets/models/props/brightwater/brightwater_banner_a.glb": "",
		"res://assets/models/props/briarwold/briarwold_fern_b.glb": "",
	}
	for path in cases:
		assert_eq(PoiKit.surface_of_asset(str(path)), str(cases[path]), str(path).get_file())

func test_a_hearthstone_carries_the_id_of_the_place_it_stands_at() -> void:
	if _skip():
		return
	var seen: Dictionary = {}
	for item_v in WorldPois.candidates(pois):
		var item: Dictionary = item_v
		var entry: Dictionary = item["entry"]
		var id := str(entry["place_id"])
		var d := PoiDressing.raise(entry, item["def"], false, provider, roads)
		_host().add_child(d)
		for stone_v in d.hearthstones():
			var stone: Hearthstone = stone_v
			assert_eq(stone.hearthstone_id, id, "%s's stone is called %s" % [id, stone.hearthstone_id])
			assert_eq(stone.place_id, id)
			assert_false(seen.has(stone.hearthstone_id), "two Hearthstones share the id %s" % stone.hearthstone_id)
			seen[stone.hearthstone_id] = true
		_drop(d)
	assert_gt(seen.size(), 8, "only %d Hearthstones in the whole overworld" % seen.size())


## The main quest says "rest at Pilgrim's Ash" and no stone stood there, or at Isseva, or in
## the Fallen Hand's palm. A place tagged `shrine` keeps one now, under the place's own id,
## which is exactly what the quest's `rest_at` objective names.
func test_the_main_quests_resting_places_have_hearthstones() -> void:
	if _skip():
		return
	var stones := _every_hearthstone_in_the_game()
	var wanted := 0
	for quest in ContentDB.all("quest"):
		for stage in quest.get("stages", []):
			for o in (stage as Dictionary).get("objectives", []):
				var obj: Dictionary = o
				if str(obj.get("type", "")) != "rest_at":
					continue
				var target := str(obj.get("target", ""))
				if target == "" or target == "any" or target.begins_with("tag:"):
					continue
				wanted += 1
				assert_true(stones.has(target),
						"%s rests at %s and no Hearthstone of that id stands anywhere, in the open or in a deep place"
						% [quest.get("id", "?"), target])
	assert_gt(wanted, 0, "no quest rests anywhere; the objective type went unused")


## Every Hearthstone the built game can stand up, by id, from both places they come from: the
## ones this node raises in the open, and the ones the deep places declare as a `hearthstone`
## feature in their own meta, which `cave_interior.gd` builds when you go inside.
##
## Counting only the overworld ones made this test wrong rather than strict: a quest that
## rests at `hearth_undercroft` names a stone that genuinely exists, down in the Undercroft,
## and the test called it missing.
func _every_hearthstone_in_the_game() -> Dictionary:
	var out: Dictionary = {}
	for item_v in WorldPois.candidates(pois):
		var item: Dictionary = item_v
		var d := PoiDressing.raise(item["entry"], item["def"], false, provider, roads)
		_host().add_child(d)
		for stone_v in d.hearthstones():
			out[(stone_v as Hearthstone).hearthstone_id] = true
		_drop(d)
	for def in ContentDB.all("interior"):
		var meta_path := str(def.get("meta", ""))
		if meta_path == "" or not FileAccess.file_exists(meta_path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		for feature_v in (parsed as Dictionary).get("features", []):
			if typeof(feature_v) != TYPE_DICTIONARY:
				continue
			var feature: Dictionary = feature_v
			if str(feature.get("kind", "")) == "hearthstone":
				out[str(feature.get("id", ""))] = true
	return out


# --- the same place every time ------------------------------------------------------------------------

func test_the_same_poi_is_dressed_the_same_way_twice() -> void:
	if _skip():
		return
	for id in ["core:poi/gosling_pit", "core:poi/hedge_shrine_of_ansel", "core:poi/sinkhole_shrine"]:
		var a := _raise(id)
		var b := _raise(id)
		var sa := a.signature()
		var sb := b.signature()
		assert_eq(sa.size(), sb.size(), "%s was built two different sizes" % id)
		for i in range(mini(sa.size(), sb.size())):
			assert_eq(sa[i], sb[i], "%s: %s moved between raisings" % [id, sa[i]])
		_drop(a)
		_drop(b)


func test_two_pois_of_one_kind_are_not_the_same_place_twice() -> void:
	if _skip():
		return
	var a := _raise("core:poi/gosling_pit")
	var b := _raise("core:poi/clanless_camp")
	var sa := a.signature()
	var sb := b.signature()
	var same := 0
	for s in sa:
		if sb.has(s):
			same += 1
	assert_true(same < sa.size() / 2, "two camps share %d of %d placements" % [same, sa.size()])
	_drop(a)
	_drop(b)


# --- the far ring ---------------------------------------------------------------------------------------

func test_the_far_ring_gets_a_silhouette_and_no_lights() -> void:
	if _skip():
		return
	var near := _raise("core:poi/gosling_pit")
	var far := _raise("core:poi/gosling_pit", true)
	assert_true(far.lights().is_empty(), "a far camp carries %d lights" % far.lights().size())
	assert_true(far.hearthstones().is_empty(), "a far dressing should not stand a Hearthstone")
	assert_true(far.mesh_count() < near.mesh_count(),
			"the far ring built %d meshes against %d near" % [far.mesh_count(), near.mesh_count()])
	assert_eq(far.body_count(), 0, "nothing in the far ring needs collision")
	_drop(near)
	_drop(far)


# --- indexing and streaming ------------------------------------------------------------------------------

func test_world_pois_indexes_every_dressable_entry_by_its_cell() -> void:
	if _skip():
		return
	var wp := WorldPois.new()
	_host().add_child(wp)
	var n := wp.index(pois, provider, roads)
	# every built entry, and every POI the content has that the land does not have a pad for yet
	var unbuilt := WorldPois.unbuilt_entries(pois, provider)
	assert_eq(n, WorldPois.candidates(pois + unbuilt).size())
	for e in unbuilt:
		var id := str((e as Dictionary)["place_id"])
		assert_true(_entry(id).is_empty(), "%s is marked unbuilt but has a pad" % id)
	assert_gt(n, 50, "only %d entries indexed" % n)
	for item_v in wp.entries():
		var pos: Array = (item_v["entry"] as Dictionary)["pos"]
		var cell := wp.cell_of(Vector3(float(pos[0]), float(pos[1]), float(pos[2])))
		# CONTRACTS §6: cx = floor((x + 4096) / 256)
		assert_eq(cell, Vector2i(int(floor((float(pos[0]) + 4096.0) / 256.0)),
				int(floor((float(pos[2]) + 4096.0) / 256.0))))
	_drop(wp)


func test_the_streamer_raises_the_dressings_of_a_cell_it_builds() -> void:
	if _skip():
		return
	var wp := WorldPois.new()
	_host().add_child(wp)
	wp.index(pois, provider, roads)
	var streamer := WorldStreamer.new()
	_host().add_child(streamer)
	streamer.setup(provider, null)
	var entry := _entry("core:poi/gosling_pit")
	var pos: Array = entry["pos"]
	var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var cell := streamer.cell_of(at)
	var data := {"cell": [cell.x, cell.y], "region": "", "instances": {}, "scenes": [], "spawns": [], "lights": []}
	streamer._build_cell(cell, 0, data)
	var node: Node3D = streamer.get_node_or_null("Cell_%d_%d" % [cell.x, cell.y])
	assert_true(node != null, "the cell node was not built")
	var dressing: Node = node.get_node_or_null("Poi_gosling_pit")
	assert_true(dressing is PoiDressing, "the camp was not raised with its cell")
	if dressing is PoiDressing:
		var d := dressing as PoiDressing
		assert_false(d.far, "the near ring should get the full camp")
		assert_true(d.global_position.distance_to(at) < 0.01, "the camp stands %s, its data says %s" % [str(d.global_position), str(at)])
		assert_gt(d.mesh_count(), 0)
	# and the far ring gets the silhouette (a second streamer: unloading only queues the first
	# one's cell node for freeing, and a new node of the same name would be renamed around it)
	var far_streamer := WorldStreamer.new()
	_host().add_child(far_streamer)
	far_streamer.setup(provider, null)
	far_streamer._build_cell(cell, 2, data)
	var far_node: Node3D = far_streamer.get_node_or_null("Cell_%d_%d" % [cell.x, cell.y])
	var far_dressing: Node = far_node.get_node_or_null("Poi_gosling_pit") if far_node != null else null
	assert_true(far_dressing is PoiDressing and (far_dressing as PoiDressing).far, "the far ring should raise a silhouette")
	if far_dressing is PoiDressing:
		assert_true((far_dressing as PoiDressing).lights().is_empty(), "a far cell should carry no lights")
	streamer.unload_all()
	far_streamer.unload_all()
	_drop(streamer)
	_drop(far_streamer)
	_drop(wp)
