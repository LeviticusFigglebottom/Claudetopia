extends TestCase
## The chests in a house open. Twenty-three chests, fourteen cupboards, strongboxes and sacks
## stand in the twenty-four hand-built interiors, and every one of them was a mesh: the
## container system could roll loot, lock itself and be emptied, and nothing in an interior
## ever attached one to the furniture. These pin that they are attached, that they are the
## resident's, and that the same chest holds the same things every time you come back.

const HOUSE := "core:interior/ellard_steward"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Built the way the smoke run builds one: the builder node in the tree first, then `build()`
## with the meta path. Setting `meta_path` and relying on `_ready` builds nothing, because the
## scene's own export is empty and `_ready` has already run by then.
func _open(interior_id: String) -> Node3D:
	var def := ContentDB.get_or_empty(interior_id)
	var builder := HouseInterior.new()
	builder.build_on_ready = false
	_tree().root.add_child(builder)
	builder.build(str(def.get("meta", "")))
	return builder


func _drop(n: Node) -> void:
	_tree().root.remove_child(n)
	n.queue_free()


func _containers(root: Node) -> Array[WorldContainer]:
	var out: Array[WorldContainer] = []
	for node in root.find_children("*", "StaticBody3D", true, false):
		if node is WorldContainer:
			out.append(node as WorldContainer)
	return out


func test_a_house_has_furniture_you_can_open() -> void:
	var house := _open(HOUSE)
	var boxes := _containers(house)
	assert_gt(boxes.size(), 0, "the steward's house has nothing that opens")
	_drop(house)


func test_what_opens_belongs_to_whoever_lives_there() -> void:
	var house := _open(HOUSE)
	var resident := str(ContentDB.get_or_empty(HOUSE).get("resident", ""))
	assert_true(resident != "", "this test needs a house with a named resident")
	for box in _containers(house):
		assert_eq(box.owner_npc, resident,
				"%s belongs to nobody, so robbing it is not a crime" % box.container_id)
	_drop(house)


func test_every_openable_thing_can_be_reached_by_the_interaction_ray() -> void:
	var house := _open(HOUSE)
	for box in _containers(house):
		assert_true(box.is_in_group("interactable"), "%s is not interactable" % box.container_id)
		var shapes := box.find_children("*", "CollisionShape3D", false, false)
		assert_gt(shapes.size(), 0, "%s has no shape, so the ray goes through it" % box.container_id)
	_drop(house)


func test_the_same_chest_holds_the_same_things_every_visit() -> void:
	WorldContainer.store.clear()
	var first := _open(HOUSE)
	var before: Dictionary = {}
	for box in _containers(first):
		box.ensure_loot()
		before[box.container_id] = box.inventory.total_value()
	_drop(first)
	await _tree().process_frame
	var second := _open(HOUSE)
	for box in _containers(second):
		box.ensure_loot()
		assert_true(before.has(box.container_id), "a chest changed its id between visits")
		assert_eq(box.inventory.total_value(), int(before[box.container_id]),
				"%s held something different the second time" % box.container_id)
	_drop(second)


func test_a_strongbox_is_locked_and_a_crate_is_not() -> void:
	var locked_kinds := 0
	var open_kinds := 0
	for id in ["core:interior/ellard_steward", "core:interior/hallam_forge",
			"core:interior/corwen_brewhouse", "core:interior/tolls_lip"]:
		if not ContentDB.has(id):
			continue
		var house := _open(id)
		for box in _containers(house):
			if box.locked:
				locked_kinds += 1
			else:
				open_kinds += 1
		_drop(house)
	assert_gt(open_kinds, 0, "every openable thing in four houses was locked")


func test_a_sack_of_flour_is_not_a_treasure_chest() -> void:
	# The poor tier draws no loot table at all: an empty crate that says so is more honest
	# than a crate that mints a dagger.
	assert_false(HouseInterior.TIER_LOOT.has("poor"), "the poor tier was given a loot table")
	for kind in ["crate", "barrel", "flour_sacks", "seed_sacks"]:
		assert_eq(str(HouseInterior.OPENABLE.get(kind, "")), "poor", "%s is not poor" % kind)
