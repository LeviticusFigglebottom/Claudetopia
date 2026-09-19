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
