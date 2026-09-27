extends TestCase
## A prompt never outlives what it offered (playtest 09-27: "Sometimes prompts don't disappear,
## even after going in other menus, like press E to pick up ___").
##
## The thing picked up (freed), a menu opening, and the tree pausing each take the prompt and its
## toast down at once; the prompt comes back by itself when the world runs again and the thing is
## still there, without being announced a second time.

var _prompts: Array[String] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_prompts.clear()
	UI.dismiss_toasts("prompt")


## Something to pick up, on the interaction layer, a pace in front of the Interactor.
func _thing() -> StaticBody3D:
	var script := GDScript.new()
	script.source_code = "extends StaticBody3D\nfunc interact(_actor: Node) -> void:\n\tqueue_free()\nfunc prompt_text() -> String:\n\treturn \"Pick up the knife\"\n"
	script.reload()
	var body := StaticBody3D.new()
	body.set_script(script)
	body.collision_layer = Interactor.MASK_INTERACT
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.3, 0.4)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, 0.0, -1.2)
	return body


func _frames(n: int) -> void:
	for i in n:
		await _tree().physics_frame


func _stage() -> Array:
	var stage := Node3D.new()
	_tree().root.add_child(stage)
	var thing := _thing()
	stage.add_child(thing)
	var hand := Interactor.new()
	stage.add_child(hand)
	hand.prompt_changed.connect(func(text: String) -> void: _prompts.append(text))
	return [stage, thing, hand]


func _drop(stage: Node) -> void:
	_tree().root.remove_child(stage)
	stage.free()


func test_the_prompt_goes_with_the_thing_picked_up() -> void:
	var s := _stage()
	var hand: Interactor = s[2]
	await _frames(4)
	assert_true(hand.has_target(), "the knife is offered")
	assert_gt(UI.toasts_shown("prompt"), 0, "and announced in the corner")
	assert_true(hand.try_interact(s[0]), "and taken")
	await _tree().process_frame
	assert_false(hand.has_target(), "once it is gone nothing is offered")
	assert_eq(hand.prompt, "", "the prompt is down")
	assert_eq(_prompts.back(), "", "and the HUD was told")
	assert_eq(UI.toasts_shown("prompt"), 0, "and the toast that offered it went with it")
	_drop(s[0])


func test_a_menu_takes_the_prompt_down_and_it_comes_back_after() -> void:
	var s := _stage()
	var hand: Interactor = s[2]
	await _frames(4)
	assert_true(hand.has_target(), "the knife is offered")
	var announced := UI.toasts_shown("prompt")
	EventBus.menu_opened.emit("inventory")
	assert_eq(hand.prompt, "", "a menu opening takes the prompt down")
	assert_eq(UI.toasts_shown("prompt"), 0, "and its toast")
	await _frames(3)
	assert_true(hand.has_target(), "the world running again offers the knife again")
	assert_eq(UI.toasts_shown("prompt"), 0, "without announcing it a second time (had %d)" % announced)
	_drop(s[0])


func test_a_pause_takes_the_prompt_down() -> void:
	var s := _stage()
	var hand: Interactor = s[2]
	await _frames(4)
	assert_true(hand.has_target(), "the knife is offered")
	_tree().paused = true
	await _tree().process_frame
	var paused_prompt := hand.prompt
	_tree().paused = false
	assert_eq(paused_prompt, "", "under a pause nothing is offered")
	await _frames(3)
	assert_true(hand.has_target(), "and after it the knife is offered again")
	_drop(s[0])


func test_leaving_the_world_tells_the_hud() -> void:
	var s := _stage()
	var hand: Interactor = s[2]
	await _frames(4)
	assert_true(hand.has_target(), "the knife is offered")
	(s[0] as Node).remove_child(hand)
	assert_eq(_prompts.back(), "", "a body leaving the world takes its prompt with it")
	hand.free()
	_drop(s[0])
