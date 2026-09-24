extends TestCase
## Everything you can walk up to, built the way the world builds it.
##
## The player's interaction ray masks one physics layer. Five of the eight interactable
## classes set that layer only in their own `.tscn` — and three of those five are never
## instantiated from a scene anywhere in the game. A `JobBoard.new()` kept Godot's default
## layer 1, so the notice post stood in the village square, drew its signpost, sat in the
## "interactable" group, answered `interact()`, and the ray went straight through it.
##
## That is the whole failure in one sentence: **every test of the thing passed, and you could
## not walk up to it.** So this asserts the one property that only matters at the moment a
## player points at something.

const MASK := 1 << 4


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Every class that puts itself in the "interactable" group, built with `.new()`.
func _built() -> Array[Node]:
	var out: Array[Node] = []
	for script_path in [
			"res://systems/economy/job_board.gd",
			"res://systems/economy/job_station.gd",
			"res://systems/economy/property_sign.gd",
			"res://systems/hearth/hearthstone.gd",
			"res://systems/interiors/door.gd",
			"res://systems/inventory/container.gd",
			"res://systems/inventory/world_item.gd",
		]:
		var script: GDScript = load(script_path)
		var node: Node = script.new()
		node.name = script_path.get_file().get_basename()
		out.append(node)
	return out


func test_the_ray_can_reach_everything_you_can_interact_with() -> void:
	var wrong: Array[String] = []
	for node in _built():
		_tree().root.add_child(node)
		var body := node as CollisionObject3D
		if body != null and (body.collision_layer & MASK) == 0:
			wrong.append("%s (layer %d)" % [node.name, body.collision_layer])
		node.queue_free()
	assert_true(wrong.is_empty(),
		"built with new() these sit off the interaction layer and cannot be pointed at: %s"
			% ", ".join(wrong))


func test_everything_interactable_says_so_and_answers() -> void:
	for node in _built():
		_tree().root.add_child(node)
		assert_true(node.is_in_group("interactable"), "%s is not in the group" % node.name)
		assert_true(node.has_method("interact"), "%s has no interact()" % node.name)
		node.queue_free()


## The mask is written in the player's interactor and the layer in each of seven other files.
## Two numbers that must agree and live apart is a thing that drifts, so it is asserted.
func test_the_layer_and_the_mask_are_the_same_number() -> void:
	assert_eq(Interactor.MASK_INTERACT, MASK,
		"the interaction ray's mask moved and the interactable classes did not follow")
	for script_path in ["res://systems/inventory/container.gd",
			"res://systems/economy/job_board.gd", "res://systems/interiors/door.gd"]:
		var script: GDScript = load(script_path)
		assert_eq(int(script.get("INTERACT_LAYER")), MASK,
			"%s disagrees about which layer is interactable" % script_path)


## Every collider needs a shape, or the ray has nothing to hit whatever layer it is on.
func test_everything_has_something_to_hit() -> void:
	for node in _built():
		_tree().root.add_child(node)
		assert_false(node.find_children("*", "CollisionShape3D", true, false).is_empty(),
			"%s is a collision body with no collision shape" % node.name)
		node.queue_free()


## A door says what is behind it when it is deadly. The Cantor's Seat (danger 5) stands ten metres
## off the new game's first marked way, unlocked.
func test_a_deadly_door_says_so() -> void:
	var door := Door.new()
	door.display_name = "The Cantor's Seat"
	door.interior_id = "core:interior/cantors_seat"
	_tree().root.add_child(door)
	assert_eq(door.prompt_text(), "Enter The Cantor's Seat (deadly)")
	door.interior_id = ""
	assert_eq(door.prompt_text(), "Enter The Cantor's Seat", "a door to nowhere in particular says nothing more")
	door.queue_free()
