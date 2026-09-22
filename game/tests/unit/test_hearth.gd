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


## A body the physics server can see, standing in the player's own layer. The Echo is an Area3D
## and an Area3D never notices a bare Node3D, so `FakePlayer` cannot show what follows.
func _standing_body() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 1 << 1          # "player": the layer the Echo watches
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	body.add_child(shape)
	body.add_to_group("player")
	return body


## Dying does not hand you your own marks straight back.
##
## The Echo stands at the spot you fell, and for the three seconds of RESPAWN_DELAY your body is
## still lying on that spot. So the Area3D woke up around its own player, `body_entered` fired
## at once, and `recover_echo()` returned everything before the player had stood up: death cost
## nothing, and the Echo you are meant to walk back to went quiet before you could see it. In
## the journey this read as `marks_gone=false` or `dropped=false` depending on which frame the
## physics tick happened to land in, which is what made it look like a flake in one run of five.
func test_dying_on_the_spot_does_not_hand_the_marks_straight_back() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	# An Area3D flushes its overlaps on the physics step, so a paused tree makes every assertion
	# below vacuously true. Say so here rather than report a pass nobody asked for.
	assert_false(tree.paused, "the world is paused, so nothing in this test is being measured")
	var body := _standing_body()
	tree.root.add_child(body)
	var fell := Vector3(120.0, 0.0, -40.0)
	body.global_position = fell
	inv.marks = 240
	Hearth.rest_at("stone_a", Vector3(10, 2, 3), 0.0, false)
	Hearth._on_player_died(fell)
	assert_true(Hearth.has_echo(), "the Echo stands where you fell")
	assert_eq(inv.marks, 0, "and the marks went into it")
	for i in 3:
		await tree.physics_frame
	assert_true(Hearth.has_echo(), "the Echo went quiet before the player ever stood up")
	assert_eq(inv.marks, 0, "death cost nothing: the marks came straight back")

	# Coming back for it is what recovers it: away from the spot, back at the stone, and in again.
	body.global_position = fell + Vector3(60.0, 0.0, 0.0)
	await tree.physics_frame
	Hearth._respawn()
	await tree.physics_frame
	body.global_position = fell
	for i in 3:
		await tree.physics_frame
	assert_false(Hearth.has_echo(), "walking back into the Echo does not recover it")
	assert_eq(inv.marks, 240, "the marks did not come back with it")
	body.get_parent().remove_child(body)
	body.free()


## One death, one coming back. The death delay's timer fires three seconds after the fall and
## nothing cancels it, so anything that brought the player back sooner -- a load, a scripted
## respawn, the journey's own -- was undone by it seconds into whatever they were doing next.
func test_coming_back_twice_from_one_death_only_moves_you_once() -> void:
	inv.marks = 50
	Hearth.rest_at("stone_a", Vector3(10, 2, 3), 0.0, false)
	Hearth._on_player_died(Vector3(80, 0, 80))
	Hearth._respawn()
	assert_eq(player.respawns, 1)
	player.global_position = Vector3(300, 5, 300)      # off doing something else by now
	Hearth._respawn()                                   # the delay timer, arriving late
	assert_eq(player.respawns, 1, "a second coming back from one death moved the body twice")
	assert_eq(player.global_position, Vector3(300, 5, 300), "and put it back at the stone")
