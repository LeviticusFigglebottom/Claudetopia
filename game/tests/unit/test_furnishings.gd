extends TestCase
## A furnishing you bought, standing in the house you walk into.
##
## `PropertyRegistry.add_furnishing()` and `furnishings()` were written, saved and tested, and
## `tools/unwired.py --verbs` showed nothing outside the tests calling either: DESIGN §5.14's
## "Furnishings bought" was a field in a save file. `test_deed_screen.gd` presses the buying
## button; this is the other half, the drawing.
##
## The six deeds on sale name interiors (`merrowby_crater_cottage` and the rest) that the forge
## has not built — `property.gd` says so: "a place id in pass one; real interiors land later".
## So these stand the mechanism up against a real house's real rooms and the real positions its
## dressing pass put the resident's things in, with the meta's id read as the one the deed
## names. When those houses are forged, nothing here has to change.

const DEED := "core:item/deed_merrowby_crater_cottage"
const RUG := "core:item/furnishing_hearth_rug"
const CHEST := "core:item/furnishing_oak_chest"
const HANGINGS := "core:item/furnishing_bed_hangings"
const PRESS := "core:item/furnishing_book_press"
## Hesta's bell house: Merrowby, a hearth room, a bed and a store, and no study — which is the
## interesting case for the book press.
const META := "res://assets/models/interior/hesta_bell_house/hesta_bell_house.meta.json"

var registry: PropertyRegistry
var house: HouseInterior


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	registry = PropertyRegistry.ensure()
	registry.owned.clear()


func after_each() -> void:
	if house != null and is_instance_valid(house):
		house.queue_free()
	house = null
	if is_instance_valid(registry):
		registry.owned.clear()


## A real house, dressed for its resident, that the deed's interior names.
func _own_and_build(furnishings: Array[String]) -> HouseInterior:
	registry.grant(DEED)
	for item in furnishings:
		assert_true(registry.add_furnishing(DEED, item), "%s was not recorded" % item)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META))
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "the house meta did not load: %s" % META)
	house = HouseInterior.new()
	house.build_on_ready = false
	house.meta = parsed
	house.meta["id"] = PropertyRegistry.interior_of(DEED)
	for r in house.meta.get("rooms", []):
		house.rooms[str((r as Dictionary)["id"])] = r
	_tree().root.add_child(house)
	house.dress_furnishings()
	return house


func _furnishing_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var holder := house.get_node_or_null("Furnishings")
	if holder == null:
		return out
	for child in holder.get_children():
		if child is Node3D and child.has_meta("furnishing"):
			out.append(child as Node3D)
	return out


func _node_for(item_id: String) -> Node3D:
	for n in _furnishing_nodes():
		if str(n.get_meta("furnishing")) == item_id:
			return n
	return null


func _room_of(item_id: String) -> String:
	var n := _node_for(item_id)
	return "" if n == null else str(n.get_meta("room", ""))


# --- the content ---------------------------------------------------------------------------

func test_every_furnishing_names_a_prop_the_library_can_draw() -> void:
	var all := PropertyRegistry.all_furnishings()
	assert_gt(all.size(), 0, "no furnishings ship in the core pack")
	var props := PropLibrary.new()
	for def in all:
		var id := str(def["id"])
		var block: Dictionary = def["furnishing"]
		assert_eq(str(def.get("category", "")), "misc", "%s is not a misc item" % id)
		assert_true((def.get("tags", []) as Array).has("furnishing"),
			"%s is not tagged furnishing, so nothing will find it" % id)
		assert_gt(int(def.get("value", 0)), 0, "%s has no price to sell it at" % id)
		var kind := str(block.get("prop", ""))
		assert_false(kind.is_empty(), "%s names no prop" % id)
		assert_false(props.resolve(kind, "vale").is_empty(),
			"%s asks for a prop the forge has not built and the library cannot stand in for: %s"
				% [id, kind])
		var spot := str(block.get("spot", "floor"))
		assert_true(spot in ["floor", "wall"], "%s wants an unknown spot '%s'" % [id, spot])


# --- in the house --------------------------------------------------------------------------

func test_a_bought_furnishing_stands_in_the_house_you_walk_into() -> void:
	_own_and_build([RUG] as Array[String])
	var node := _node_for(RUG)
	assert_true(node != null, "the rug was bought and the house was built without it")
	assert_eq(_room_of(RUG), "hearth_room", "a hearth rug went somewhere other than the hearth")
	var room: Dictionary = house.rooms["hearth_room"]
	assert_true(node.position.x > float(room["x"])
			and node.position.x < float(room["x"]) + float(room["w"]),
		"the rug is outside the room it belongs to, at %s" % str(node.position))
	assert_true(node.position.z > float(room["z"])
			and node.position.z < float(room["z"]) + float(room["d"]),
		"the rug is outside the room it belongs to, at %s" % str(node.position))
	assert_eq(node.position.y, float(room["floor_y"]), "the rug is not on the floor")


func test_nothing_of_yours_is_put_down_on_top_of_the_residents_things() -> void:
	_own_and_build([RUG, HANGINGS, CHEST] as Array[String])
	assert_eq(_furnishing_nodes().size(), 3, "not everything bought was drawn")
	for node in _furnishing_nodes():
		var room_id := str(node.get_meta("room"))
		var nearest := 99.0
		for p in house.meta.get("placements", []):
			if str((p as Dictionary).get("room", "")) != room_id:
				continue
			var at: Array = (p as Dictionary)["at"]
			nearest = minf(nearest, node.position.distance_to(
				Vector3(float(at[0]), float(at[1]), float(at[2]))))
		assert_gt(nearest, 0.35,
			"%s landed %.2f m from something the resident already put there"
				% [str(node.get_meta("furnishing")), nearest])


## The Crater Cottage is one room and most houses have no study, so a furnishing that asks for
## a room this house has not got goes to the hearth rather than refusing to exist.
func test_a_furnishing_whose_room_is_missing_goes_to_the_hearth() -> void:
	_own_and_build([PRESS] as Array[String])
	assert_false(house.rooms.has("study"), "this fixture was chosen for having no study")
	assert_eq(_room_of(PRESS), "hearth_room", "the book press had nowhere to go")


func test_a_chest_you_bought_is_storage_and_it_is_yours() -> void:
	_own_and_build([CHEST] as Array[String])
	var node := _node_for(CHEST)
	assert_true(node != null, "no chest")
	var box := node.get_node_or_null("Storage")
	assert_true(box != null, "the chest that is meant to be extra storage does not open")
	assert_true(str(box.get("container_id")).begins_with(
		PropertyRegistry.storage_id_of(DEED)), "got '%s'" % str(box.get("container_id")))
	assert_eq(str(box.get("loot_table")), "", "your own chest rolled loot into itself")
	assert_eq(str(box.get("owner_npc")), "", "your own chest belongs to somebody else")


func test_a_house_you_do_not_own_gets_none_of_your_furniture() -> void:
	registry.grant(DEED)
	registry.add_furnishing(DEED, RUG)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META))
	house = HouseInterior.new()
	house.build_on_ready = false
	house.meta = parsed                      # its own id: somebody else's house
	for r in house.meta.get("rooms", []):
		house.rooms[str((r as Dictionary)["id"])] = r
	_tree().root.add_child(house)
	house.dress_furnishings()
	assert_true(house.get_node_or_null("Furnishings") == null,
		"your rug turned up in a house belonging to %s" % str(house.meta.get("resident", "")))


# --- buying and the save -------------------------------------------------------------------

func test_buying_needs_a_house_of_your_own_and_marks_for_it() -> void:
	var bag := Inventory.new()
	bag.add_to_group("inventory")
	_tree().root.add_child(bag)
	var result: Dictionary = registry.buy_furnishing(bag, DEED, RUG)
	assert_eq(str(result["reason"]), "not_owned", "a furnishing was sold for a house nobody owns")
	registry.grant(DEED)
	assert_eq(str(registry.buy_furnishing(bag, DEED, RUG)["reason"]), "poor")
	bag.add_marks(PropertyRegistry.furnishing_price(RUG))
	assert_true(bool(registry.buy_furnishing(bag, DEED, RUG)["ok"]), "it could not be bought")
	assert_eq(bag.marks, 0, "the marks did not leave the bag")
	assert_eq(str(registry.buy_furnishing(bag, DEED, RUG)["reason"]), "already_there",
		"the same rug was sold twice")
	assert_eq(str(registry.buy_furnishing(bag, DEED, "core:item/bread")["reason"]), "unknown",
		"a loaf of bread was sold as a furnishing")
	bag.queue_free()


func test_furnishings_survive_a_save() -> void:
	registry.grant(DEED)
	registry.add_furnishing(DEED, RUG)
	registry.add_furnishing(DEED, CHEST)
	var saved := registry.to_save()
	registry.owned.clear()
	assert_empty(registry.furnishings(DEED))
	registry.from_save(saved)
	assert_eq(registry.furnishings(DEED), [RUG, CHEST] as Array,
		"the furnishings did not come back through the property section")
