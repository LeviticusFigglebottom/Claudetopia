extends TestCase


func test_valid_ids() -> void:
	assert_true(Ids.is_valid("core:item/iron_sword"))
	assert_true(Ids.is_valid("mypack:quest/main_01.b"))
	assert_false(Ids.is_valid("core:item"))
	assert_false(Ids.is_valid("Core:item/Sword"))
	assert_false(Ids.is_valid("core/item/sword"))
	assert_false(Ids.is_valid(""))


func test_parts() -> void:
	assert_eq(Ids.pack_of("core:item/iron_sword"), "core")
	assert_eq(Ids.type_of("core:item/iron_sword"), "item")
	assert_eq(Ids.name_of("core:item/iron_sword"), "iron_sword")
	assert_eq(Ids.make("core", "npc", "wren_tallow"), "core:npc/wren_tallow")


func test_deep_merge() -> void:
	var base := {"a": 1, "stats": {"hp": 10, "poise": 5}, "tags": ["x"]}
	var over := {"stats": {"hp": 20}, "tags": ["y"], "b": 2}
	var m := ContentDB.deep_merge(base, over)
	assert_eq(m["a"], 1)
	assert_eq(m["b"], 2)
	assert_eq(m["stats"]["hp"], 20)
	assert_eq(m["stats"]["poise"], 5)
	assert_eq(m["tags"], ["y"])
	assert_eq(base["stats"]["hp"], 10, "base must not be mutated")
