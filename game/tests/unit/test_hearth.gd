extends TestCase

const FakeInventory := preload("res://tests/fakes/fake_inventory.gd")
const FakePlayer := preload("res://tests/fakes/fake_player.gd")

var inv: Node
var player: Node3D


func before_each() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	inv = FakeInventory.new()
	tree.root.add_child(inv)
	player = FakePlayer.new()
	tree.root.add_child(player)
	Hearth.echo = {}
	Hearth.lit.clear()
	Hearth.last_hearthstone_id = ""
	Hearth._respawning = false


func after_each() -> void:
	Hearth._clear_echo_node()
	for n in [inv, player]:
		n.get_parent().remove_child(n)
		n.free()


func test_rest_sets_respawn_and_lights() -> void:
	Hearth.rest_at("stone_a", Vector3(10, 2, 3), 1.5, false)
	assert_eq(Hearth.last_hearthstone_id, "stone_a")
	assert_eq(Hearth.respawn_position, Vector3(10, 2, 3))
	assert_true(Hearth.is_lit("stone_a"))
	assert_eq(player.restores, 1)


func test_death_drops_marks_into_echo() -> void:
	inv.marks = 120
	Hearth.rest_at("stone_a", Vector3(10, 2, 3), 0.0, false)
	Hearth._on_player_died(Vector3(50, 0, 50))
	assert_true(Hearth.has_echo())
	assert_eq(int(Hearth.echo["marks"]), 120)
	assert_eq(inv.marks, 0)
	Hearth._respawn()
	assert_eq(player.global_position, Vector3(10, 2, 3))
	assert_eq(player.respawns, 1)


func test_second_death_loses_old_echo() -> void:
	inv.marks = 100
	Hearth._on_player_died(Vector3(1, 0, 1))
	Hearth._respawn()
	inv.marks = 30
	Hearth._on_player_died(Vector3(5, 0, 5))
	assert_eq(int(Hearth.echo["marks"]), 30)
	assert_eq(Hearth.echo["position"], Vector3(5, 0, 5))
	Hearth._respawn()


func test_recover_echo_restores_marks() -> void:
	inv.marks = 77
	Hearth._on_player_died(Vector3(1, 0, 1))
	Hearth._respawn()
	Hearth.recover_echo()
	assert_eq(inv.marks, 77)
	assert_false(Hearth.has_echo())


func test_save_round_trip_with_echo() -> void:
	inv.marks = 40
	Hearth.rest_at("stone_b", Vector3(1, 2, 3), 0.7, false)
	Hearth._on_player_died(Vector3(9, 8, 7))
	Hearth._respawn()
	var data: Dictionary = JSON.parse_string(JSON.stringify(Hearth.to_save()))
	Hearth.echo = {}
	Hearth.lit.clear()
	Hearth.from_save(data)
	assert_true(Hearth.has_echo())
	assert_eq(int(Hearth.echo["marks"]), 40)
	assert_near((Hearth.echo["position"] as Vector3).x, 9.0)
	assert_true(Hearth.is_lit("stone_b"))
	assert_eq(Hearth.last_hearthstone_id, "stone_b")
