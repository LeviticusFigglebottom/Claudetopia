extends TestCase
## Walking up to an anvil and making something.
##
## `station_screen.tscn` draws the forge, the alembic and the Name-table (DESIGN §5.8), and
## `UI.MENUS` has had "crafting" registered all along. **Nothing in the game ever called
## `UI.open("crafting")`.** Smithing, alchemy, enchanting and twenty-one recipes were behind a
## door with no handle: there was no forge, no still and no bench anywhere in the world that a
## player could use. Every one of those systems has its own passing tests.

const SMITHY := "core:interior/hallam_forge"
const STILLROOM := "core:interior/nell_stillroom"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Built the way the smoke run builds one: the builder node, handed the meta path.
func _build(interior_id: String) -> Node3D:
	var def := ContentDB.get_or_empty(interior_id)
	var meta_path := str(def.get("meta", ""))
	if meta_path.is_empty() or not FileAccess.file_exists(meta_path):
		return null
	var builder := HouseInterior.new()
	builder.build_on_ready = false
	_tree().root.add_child(builder)
	if not builder.build(meta_path):
		builder.queue_free()
		return null
	return builder


func _stations(root: Node) -> Array[String]:
	var out: Array[String] = []
	for node in root.find_children("*", "CraftingStation", true, false):
		out.append(str(node.get("station")))
	return out


func test_a_smithy_has_an_anvil_you_can_work_at() -> void:
	var room := _build(SMITHY)
	if room == null:
		return
	assert_true(_stations(room).has("forge"),
		"Hallam's forge has an anvil in it and no way to use it: %s" % [_stations(room)])
	room.queue_free()


func test_a_stillroom_has_an_alembic_you_can_work_at() -> void:
	var room := _build(STILLROOM)
	if room == null:
		return
	assert_true(_stations(room).has("alembic"),
		"Nell's stillroom has an alembic in it and no way to use it: %s" % [_stations(room)])
	room.queue_free()


func test_the_station_is_on_the_prop_and_can_be_pointed_at() -> void:
	var room := _build(SMITHY)
	if room == null:
		return
	var benches := room.find_children("*", "CraftingStation", true, false)
	assert_false(benches.is_empty(), "no station to point at, so this asserts nothing")
	for node in benches:
		var body := node as CollisionObject3D
		assert_true((body.collision_layer & (1 << 4)) != 0,
			"the anvil's station is off the interaction layer")
		assert_false(node.find_children("*", "CollisionShape3D", true, false).is_empty(),
			"the station has nothing for the ray to hit")
		assert_true(node.is_in_group("interactable"))
		assert_true(node.get_parent() is Node3D,
			"the station is not riding the prop it belongs to")
	room.queue_free()


## Walking up to it has to reach the screen, which is where every other version of this bug
## has been hiding: the node exists, the method runs, and nothing is drawn.
func test_working_at_it_opens_the_working_screen() -> void:
	var bench := CraftingStation.new()
	bench.station = "alembic"
	_tree().root.add_child(bench)
	var opened: Array[String] = []
	var note := func(station: String, _n: Node) -> void: opened.append(station)
	EventBus.crafting_station_used.connect(note)
	bench.interact(null)
	EventBus.crafting_station_used.disconnect(note)
	assert_eq(opened, ["alembic"] as Array[String], "working at it told the UI nothing")
	assert_true(UI.MENUS.has("crafting"), "no screen is registered for a working bench")
	bench.queue_free()


func test_it_says_what_it_is_when_you_look_at_it() -> void:
	for pair in [["forge", "anvil"], ["alembic", "alembic"], ["name_table", "Name-table"]]:
		var bench := CraftingStation.new()
		bench.station = str(pair[0])
		_tree().root.add_child(bench)
		assert_true(bench.prompt_text().contains(str(pair[1])),
			"a %s calls itself '%s'" % [pair[0], bench.prompt_text()])
		bench.queue_free()


## Enchanting was the third of the three and the only one with nowhere at all to happen:
## `station_screen` draws the Name-table, DESIGN §5.8 names it, the skill definition and two
## item descriptions refer to it — and no interior in the world contained one. The Tolling
## Order writes notes into iron, so the Bell Chapter-House at Pilgrim's Ash has one now.
func test_the_order_has_a_name_table() -> void:
	var room := _build("core:interior/cadwen_chapter_cell")
	if room == null:
		return
	assert_true(_stations(room).has("name_table"),
		"enchanting has nowhere in the world to happen: %s" % [_stations(room)])
	room.queue_free()


## Every station the working screen can draw should be somewhere a player can reach.
func test_all_three_working_screens_exist_somewhere_in_the_world() -> void:
	var found := {}
	for def in ContentDB.all("interior"):
		var meta_path := str(def.get("meta", ""))
		if meta_path.is_empty() or not FileAccess.file_exists(meta_path):
			continue
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		for p in m.get("placements", []):
			var kind := str(p.get("fixture", p.get("prop", "")))
			if HouseInterior.WORKABLE.has(kind):
				found[str(HouseInterior.WORKABLE[kind])] = true
	var missing: Array[String] = []
	for station in CraftingStation.KNOWN:
		if not found.has(station):
			missing.append(str(station))
	assert_true(missing.is_empty(),
		"the working screen draws these and nowhere in the world has one: %s" % [missing])


## The station opens the screen; the screen is no use unless a recipe actually runs against a
## real bag. Twenty-one forge recipes existed and none had ever been made in the game.
func test_a_forge_recipe_runs_against_a_real_bag() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	_tree().root.add_child(player)
	var bag := Inventory.new()
	bag.name = "Inventory"
	bag.add_to_group("inventory")
	player.add_child(bag)
	var crafting := Crafting.new()
	crafting.name = "Crafting"
	player.add_child(crafting)
	await _tree().process_frame

	var made := ""
	for entry in crafting.recipes_for("forge"):
		var row: Dictionary = entry
		var recipe_id := str(row.get("id", ""))
		if recipe_id.is_empty():
			continue
		for i in Smithing.inputs_for(recipe_id, null):
			bag.add(str(i["item"]), int(i["count"]))
		if crafting.craft(recipe_id):
			made = str(Smithing.def(recipe_id).get("output", {}).get("item", ""))
			break
	assert_ne(made, "", "not one of the forge's recipes could be made at it")
	assert_gt(bag.count(made), 0, "the thing that was made is not in the bag")
	player.queue_free()
