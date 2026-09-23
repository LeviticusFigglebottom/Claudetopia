extends TestCase

const FakePlayer := preload("res://tests/fakes/fake_player.gd")
var player: Node3D


func before_each() -> void:
	player = FakePlayer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	player.global_position = Vector3(100, 5, 100)
	Interiors.current_id = ""
	GameState.current_interior_id = ""


func after_each() -> void:
	if Interiors.in_interior():
		Interiors.exit()
	Interiors.unload_all()
	player.get_parent().remove_child(player)
	player.free()


## Coming in from the overworld (no interior current yet), a house and a deep place are built from
## their own meta files: the wrapper used to look for the current interior, which is only set
## once the player is through, and built nothing.
func test_a_real_house_and_a_real_deep_place_are_built_when_walked_into() -> void:
	for id in ["core:interior/tolls_lip", "core:interior/weaverdeep"]:
		assert_eq(GameState.current_interior_id, "", "coming in from outside")
		assert_true(Interiors.enter(id), "%s can be entered" % id)
		var root: Node = Interiors._loaded.get(id)
		assert_true(root != null, "%s is loaded" % id)
		if root != null:
			var floors := 0
			for body in root.find_children("*", "StaticBody3D", true, false):
				if (body as Node).has_meta("surface"):
					floors += 1
			assert_gt(floors, 0, "%s was built: it has a floor to stand on" % id)
			var space := (player as Node3D).get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.5, player.global_position + Vector3.DOWN * 4.0, 1)
			await (Engine.get_main_loop() as SceneTree).physics_frame
			assert_false(space.intersect_ray(q).is_empty(), "%s: the player stands over its floor" % id)
		Interiors.exit()
		GameState.current_interior_id = ""


## Going into any deep place stands the body on the floor of its mouth (the forge's entrance
## point), not a metre over the pocket's origin with a 3.0-4.5 m drop under it, and the floor it
## stands on is rock underfoot.
func test_every_deep_place_stands_a_body_on_the_floor_of_its_mouth() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var caves := 0
	for id in ContentDB.ids_of("interior"):
		if not str(ContentDB.get_def(id).get("scene", "")).ends_with("deep_place.tscn"):
			continue
		caves += 1
		assert_true(Interiors.enter(id), "%s can be entered" % id)
		await tree.physics_frame
		var at := player.global_position
		var space := player.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 6.0, 1)
		var hit := space.intersect_ray(q)
		assert_false(hit.is_empty(), "%s: there is a floor under the arrival" % id)
		if not hit.is_empty():
			var above := at.y - (hit["position"] as Vector3).y
			print("ARRIVAL | %s | %.2f m above the floor | %s underfoot" % [id, above, Foley.surface_at(at)])
			assert_true(above > -0.01 and above < 0.2, "%s: the body arrives standing on the mouth's floor (%.2f m above it)" % [id, above])
			assert_eq(Foley.surface_at(at), "stone", "%s: its floor is rock underfoot" % id)
		Interiors.exit()
		GameState.current_interior_id = ""
		Interiors.unload_all()
		await tree.process_frame
	assert_gt(caves, 5, "the deep places were all walked into")


## What a quest says lies inside is there when the player walks in through the door, not only
## when a test hands the builder its interior: the builders ask themselves which interior they
## are, and Interiors names the wrapper above them.
func test_what_a_quest_left_inside_is_there_when_walked_into() -> void:
	var items := QuestItems.ensure()
	items.clear()
	for pair in [["core:interior/ellard_steward", "core:item/stewards_brass_key"],
			["core:interior/undercroft", "core:item/ledger_of_prices"]]:
		assert_true(Interiors.enter(str(pair[0])), "%s can be entered" % pair[0])
		var root: Node = Interiors._loaded.get(str(pair[0]))
		var found := false
		if root != null:
			for n in root.find_children("*", "", true, false):
				if n is WorldItem and (n as WorldItem).item_id == str(pair[1]):
					found = true
		assert_true(found, "%s lies in %s when it is walked into" % [pair[1], pair[0]])
		Interiors.exit()
		GameState.current_interior_id = ""
		Interiors.unload_all()
		await (Engine.get_main_loop() as SceneTree).process_frame
	items.clear()


func test_enter_and_exit() -> void:
	var door := preload("res://systems/interiors/door.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(door)
	door.global_position = Vector3(110, 5, 100)
	door.interior_id = "core:interior/test_cell"
	assert_true(Interiors.enter("core:interior/test_cell", door))
	assert_true(Interiors.in_interior())
	assert_eq(GameState.current_interior_id, "core:interior/test_cell")
	assert_gt(player.global_position.x, 40000.0, "player teleported into the pocket")
	assert_near(player.global_position.x, Interiors.pocket_for("core:interior/test_cell").x + 2.0, 0.01)
	assert_true(Interiors.exit())
	assert_false(Interiors.in_interior())
	assert_near(player.global_position.x, 110.0, 0.01, "returned beside the door")
	assert_near(player.global_position.z, 100.0 + 1.5, 0.01, "one and a half metres in front of the door")
	door.get_parent().remove_child(door)
	door.free()


func test_pocket_slots_are_distinct() -> void:
	var a := Interiors.pocket_for("core:interior/test_cell")
	var b := Interiors.pocket_for("core:interior/other")
	assert_ne(a, b)
	assert_eq(Interiors.pocket_for("core:interior/test_cell"), a)


func test_save_round_trip() -> void:
	assert_true(Interiors.enter("core:interior/test_cell"))
	var data: Dictionary = JSON.parse_string(JSON.stringify(Interiors.to_save()))
	Interiors.exit()
	Interiors.from_save(data)
	assert_true(Interiors.in_interior())
	assert_eq(Interiors.current_id, "core:interior/test_cell")


func test_unknown_interior_refused() -> void:
	var before := Log.error_count
	assert_false(Interiors.enter("core:interior/does_not_exist"))
	assert_gt(Log.error_count, before)
