extends TestCase
## What the Interactor offers, from where (playtest 09-27: prompts "don't appear unless you're at a
## very particular angle or distance ... could use a rework").
##
## It was one ray down the camera's view from the chest. Now it looks all round within reach and
## prefers what is near and in front. Each case is one a player meets: a knife on the ground at
## their feet, somebody standing at their side, two things at once, a thing behind a wall, a thing
## behind their back, and two things side by side that must not flicker.

var _stage: Node3D = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_stage = Node3D.new()
	_tree().root.add_child(_stage)


func after_each() -> void:
	_tree().root.remove_child(_stage)
	_stage.free()
	_stage = null


## Something on the interaction layer at `at` (feet at the stage's floor, y = 0).
func _thing(label: String, at: Vector3, size := Vector3(0.5, 0.5, 0.5)) -> StaticBody3D:
	var script := GDScript.new()
	script.source_code = "extends StaticBody3D\nvar label := \"\"\nfunc interact(_actor: Node) -> void:\n\tpass\nfunc prompt_text() -> String:\n\treturn label\n"
	script.reload()
	var body := StaticBody3D.new()
	body.set_script(script)
	body.set("label", label)
	body.name = label
	body.collision_layer = Interactor.MASK_INTERACT
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_stage.add_child(body)
	return body


## The Interactor where the player's rides: at the chest of a body standing at the origin,
## facing -Z.
func _hand() -> Interactor:
	var hand := Interactor.new()
	hand.position = Vector3(0.0, 1.3, 0.0)
	_stage.add_child(hand)
	return hand


func _frames(n: int) -> void:
	for i in n:
		await _tree().physics_frame


func _offered(hand: Interactor) -> String:
	return str(hand.target.name) if hand.has_target() else "(nothing)"


func test_a_knife_on_the_ground_at_your_feet_is_offered() -> void:
	_thing("knife", Vector3(0.0, 0.1, -1.4), Vector3(0.4, 0.1, 0.2))
	var hand := _hand()
	await _frames(3)
	assert_eq(_offered(hand), "knife", "a thing lying a stride ahead, under the old chest-high ray")


func test_somebody_at_your_side_is_offered() -> void:
	_thing("person", Vector3(1.6, 0.9, 0.2), Vector3(0.6, 1.8, 0.6))
	var hand := _hand()
	await _frames(3)
	assert_eq(_offered(hand), "person", "a person standing at your elbow, square to your facing")


func test_in_front_is_preferred_to_beside() -> void:
	_thing("ahead", Vector3(0.0, 0.9, -2.0))
	_thing("beside", Vector3(1.4, 0.9, 0.0))
	var hand := _hand()
	await _frames(3)
	assert_eq(_offered(hand), "ahead", "the thing you face is offered before the one at your side")
	hand.update_aim(Vector3(1.0, 0.0, 0.0))
	await _frames(3)
	assert_eq(_offered(hand), "beside", "looking at the other one offers it instead")


func test_too_far_and_behind_are_not_offered() -> void:
	var far := _thing("far", Vector3(0.0, 0.9, -4.0))
	_thing("behind", Vector3(0.0, 0.9, 1.8))
	var hand := _hand()
	await _frames(3)
	assert_eq(_offered(hand), "(nothing)", "four metres off, or behind your back, nothing is offered")
	far.position = Vector3(0.0, 0.9, -2.4)
	await _frames(3)
	assert_eq(_offered(hand), "far", "walk up to it and it is")


func test_nothing_is_offered_through_a_wall() -> void:
	_thing("beyond", Vector3(0.0, 0.9, -2.0))
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 1.5, -1.0)
	_stage.add_child(wall)
	var hand := _hand()
	await _frames(3)
	assert_eq(_offered(hand), "(nothing)", "the chest on the far side of the wall is not offered")


func test_two_things_side_by_side_do_not_flicker() -> void:
	var a := _thing("a", Vector3(-0.3, 0.9, -1.6))
	_thing("b", Vector3(0.3, 0.9, -1.6))
	var hand := _hand()
	await _frames(3)
	var first := _offered(hand)
	assert_true(first == "a" or first == "b", "one of the two is offered")
	var changes := [0]
	hand.target_changed.connect(func(_t: Node) -> void: changes[0] += 1)
	# the camera sways a little across the pair, and the offer holds
	for i in 12:
		hand.update_aim(Vector3(0.12 * (1.0 if i % 2 == 0 else -1.0), 0.0, -1.0))
		await _frames(1)
	assert_eq(changes[0], 0, "a little sway of the view does not swap them")
	assert_true(is_instance_valid(a))
