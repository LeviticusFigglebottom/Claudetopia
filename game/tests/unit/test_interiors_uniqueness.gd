extends TestCase
## DESIGN section 10: the uniqueness tests, enforced.
##
## Every interior must answer "who was here?" and "what happened?", and no two may answer
## with the same object. Every deep place must say what formed it and must loop back on
## itself somewhere.


func test_every_interior_declares_its_story() -> void:
	var interiors := ContentDB.all("interior")
	assert_gt(interiors.size(), 20, "expected a real set of interiors")
	for d in interiors:
		if d.get("test_only", false):
			continue
		for key in ["resident", "story", "unique_object"]:
			assert_true(not str(d.get(key, "")).is_empty(), "%s has no %s" % [d["id"], key])
		assert_gt(str(d["story"]).length(), 40, "%s story is too thin to answer what happened" % d["id"])


func test_no_two_interiors_share_a_unique_object() -> void:
	var seen := {}
	for d in ContentDB.all("interior"):
		if d.get("test_only", false):
			continue
		var u := str(d["unique_object"]).to_lower()
		assert_false(seen.has(u), "%s and %s share a unique object: %s" % [d["id"], seen.get(u, ""), u])
		seen[u] = d["id"]


func test_interiors_point_at_a_scene_and_a_meta_that_exist() -> void:
	for d in ContentDB.all("interior"):
		assert_true(ResourceLoader.exists(str(d["scene"])), "%s scene missing: %s" % [d["id"], d["scene"]])
		if d.has("meta"):
			assert_true(FileAccess.file_exists(str(d["meta"])), "%s meta missing: %s" % [d["id"], d["meta"]])


func test_every_deep_place_says_what_formed_it_and_loops_back() -> void:
	var deep := 0
	for d in ContentDB.all("interior"):
		if not d.has("formed_by"):
			continue
		deep += 1
		assert_true(not str(d["formed_by"]).is_empty(), "%s has an empty formed_by" % d["id"])
		var meta_path := str(d.get("meta", ""))
		if meta_path.is_empty() or not FileAccess.file_exists(meta_path):
			continue
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		assert_true(m.has("shortcut") and m["shortcut"] != null, "%s has no shortcut looping back" % d["id"])
		assert_gt(int(m.get("tris", 0)), 1000, "%s has no geometry" % d["id"])
		# Verticality: a deep place that is flat is a corridor, not a place.
		var lowest := INF
		var highest := -INF
		for id in m.get("chambers", {}):
			var y := float(m["chambers"][id]["floor_y"])
			lowest = minf(lowest, y)
			highest = maxf(highest, y)
		assert_gt(highest - lowest, 8.0, "%s has only %.1f m of vertical range" % [d["id"], highest - lowest])
	assert_gt(deep, 7, "expected at least eight deep places")


func test_houses_follow_from_their_residents() -> void:
	var houses := 0
	for d in ContentDB.all("interior"):
		if not d.has("trade"):
			continue
		houses += 1
		var resident := str(d.get("resident", ""))
		if resident.begins_with("core:npc/"):
			assert_true(ContentDB.has(resident), "%s names a resident who does not exist: %s" % [d["id"], resident])
		var meta_path := str(d.get("meta", ""))
		if meta_path.is_empty() or not FileAccess.file_exists(meta_path):
			continue
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		assert_gt(m.get("rooms", []).size(), 1, "%s has one room" % d["id"])
		assert_gt(m.get("placements", []).size(), 10, "%s is not dressed" % d["id"])
		assert_gt(m.get("lights", []).size(), 0, "%s has no light" % d["id"])
		# Every prop must sit in a room that exists.
		var room_ids := {}
		for r in m["rooms"]:
			room_ids[str(r["id"])] = true
		for p in m["placements"]:
			assert_true(room_ids.has(str(p["room"])), "%s places %s in unknown room %s" % [d["id"], p.get("asset", "?"), p["room"]])
	assert_gt(houses, 10, "expected at least eleven houses")
