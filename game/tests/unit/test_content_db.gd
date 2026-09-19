extends TestCase


func test_core_pack_loaded() -> void:
	assert_true(ContentDB.is_loaded)
	assert_gt(ContentDB.packs.size(), 0)
	assert_eq(ContentDB.packs[0]["id"], "core")


func test_regions_exist_and_are_distinct() -> void:
	var regions := ContentDB.all("region")
	assert_gt(regions.size(), 4, "expected at least 5 regions")
	var landmarks := {}
	var palettes := {}
	for r in regions:
		assert_has(r, "identity")
		var ident: Dictionary = r["identity"]
		for key in ["palette", "light", "weather", "flora", "architecture", "soundscape", "landmark", "geology"]:
			assert_has(ident, key, "%s identity missing %s" % [r["id"], key])
		assert_false(landmarks.has(ident["landmark"]), "duplicate landmark %s" % ident["landmark"])
		landmarks[ident["landmark"]] = true
		var pal := str(ident["palette"])
		assert_false(palettes.has(pal), "duplicate palette in %s" % r["id"])
		palettes[pal] = true


func test_places_have_unique_features() -> void:
	var seen := {}
	for p in ContentDB.all("place"):
		var f: String = p["unique_feature"]
		assert_false(seen.has(f), "unique_feature repeated: %s (%s and %s)" % [f, p["id"], seen.get(f, "")])
		seen[f] = p["id"]
		assert_true(ContentDB.has(p["region"]), "%s has unknown region %s" % [p["id"], p["region"]])


func test_no_problems() -> void:
	assert_empty(ContentDB.problems)


func test_where_and_ids_of() -> void:
	var ids := ContentDB.ids_of("faction")
	assert_gt(ids.size(), 3)
	var joinable := ContentDB.where("faction", "joinable", true)
	assert_gt(joinable.size(), 2)
