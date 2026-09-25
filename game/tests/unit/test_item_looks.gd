extends TestCase
## Every item lying in the world looks like the thing it is, and none is the stand-in box.
##
## 500 of the 504 item defs name no model, and each was drawn as WorldItem's generated "Placeholder"
## box: the seat audit found one on a ruin's grass, the thing a player takes for something dropped
## in to test. systems/inventory/item_look.gd draws each as the forge's own prop that fits it.

const LOOK := preload("res://systems/inventory/item_look.gd")


func test_every_item_def_has_a_look_the_forge_made() -> void:
	var none: Array[String] = []
	var fell_back: Array[String] = []
	var kinds := {}
	for d: Dictionary in ContentDB.all("item"):
		var id := str(d.get("id", ""))
		var path: String = LOOK.model_for(d)
		if path == "" or not ResourceLoader.exists(path):
			none.append(id)
			continue
		var k: String = LOOK.kind_for(d) if not path.contains("/weapons/") else "held"
		kinds[k] = int(kinds.get(k, 0)) + 1
		if k == LOOK.FALLBACK and not str(d.get("tags", [])).contains("parcel"):
			fell_back.append(id.get_slice("/", 1))
	print("    looks by kind: %s" % str(kinds))
	print("    drawn as the fallback sack (%d): %s" % [fell_back.size(), ", ".join(PackedStringArray(fell_back))])
	assert_empty(none, "items with no look at all: %s" % str(none))


func test_a_pickup_is_never_the_stand_in_box() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var errors_before := Log.error_count
	for id in ["core:item/letter_to_the_circle", "core:item/stewards_brass_key", "core:item/potion_restore_health",
			"core:item/iron_arrow", "core:item/wolf_pelt", "core:item/sword_iron", "core:item/cider"]:
		if not ContentDB.has(id):
			continue
		var wi := WorldItem.new()
		wi.setup(id, 1)
		tree.root.add_child(wi)
		var boxes := wi.find_children("Placeholder", "", true, false)
		assert_empty(boxes, "%s is drawn as the stand-in box" % id)
		assert_true(wi.get_node("Visual").get_child_count() > 0, "%s is drawn as something" % id)
		wi.queue_free()
	var purse := WorldItem.new()
	purse.setup("", 0, {}, 25)
	tree.root.add_child(purse)
	assert_empty(purse.find_children("Placeholder", "", true, false), "a purse is a sack, not a gold ball")
	purse.queue_free()
	assert_eq(Log.error_count, errors_before, "no item was logged as having no model")


func test_the_rules_pick_what_the_thing_is() -> void:
	assert_eq(LOOK.kind_for({"id": "core:item/letter_to_the_circle", "tags": ["quest", "letter"], "category": "misc"}), "scroll")
	assert_eq(LOOK.kind_for({"id": "core:item/potion_slow", "tags": ["potion"], "category": "consumable"}), "phial")
	assert_eq(LOOK.kind_for({"id": "core:item/stewards_brass_key", "tags": ["key"], "category": "key"}), "copper")
	assert_eq(LOOK.kind_for({"id": "core:item/wolf_pelt", "tags": ["hide"], "category": "material"}), "cloth")
	assert_eq(LOOK.kind_for({"id": "core:item/the_struck_bell", "tags": ["book"], "category": "book"}), "book")
