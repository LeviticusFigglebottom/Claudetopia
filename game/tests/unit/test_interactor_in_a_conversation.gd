extends TestCase
## The interaction prompt while somebody is talking.
##
## The flow's picture of the first conversation had the HUD's "[E] Talk to Wren Tallow" under the
## Warden's words, with a toast saying it again: the key that goes on through a conversation, offered
## as the key that would start it. The ray offers nothing while a conversation runs. When it ends it
## finds the person again, and it does not announce them a second time until the player has turned
## away and come back.

const WREN := "core:npc/wren_tallow"

var _notes: Array[String] = []
var _prompts: Array[String] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	Social.reset_for_new_game()
	GameState.reset_for_new_game(17)
	_notes.clear()
	_prompts.clear()


func after_each() -> void:
	if bool(Social.dialogue.call("is_running")):
		Social.dialogue.call("stop")


func _on_notify(text: String, kind: String) -> void:
	if kind == "prompt":
		_notes.append(text)


## Something to talk to, on the interaction layer, a pace and a half in front of the ray.
func _post() -> StaticBody3D:
	var script := GDScript.new()
	script.source_code = "extends StaticBody3D\nvar used := 0\nfunc interact(_actor: Node) -> void:\n\tused += 1\nfunc prompt_text() -> String:\n\treturn \"Talk to the post\"\n"
	script.reload()
	var body := StaticBody3D.new()
	body.set_script(script)
	body.collision_layer = Interactor.MASK_INTERACT
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 2.0, 0.8)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, 0.0, -1.5)
	return body


func _frames(n: int) -> void:
	for i in n:
		await _tree().physics_frame


func test_nothing_is_offered_while_somebody_is_talking() -> void:
	var stage := Node3D.new()
	_tree().root.add_child(stage)
	var post := _post()
	stage.add_child(post)
	var ray := Interactor.new()
	stage.add_child(ray)
	ray.prompt_changed.connect(func(text: String) -> void: _prompts.append(text))
	EventBus.notify.connect(_on_notify)
	await _frames(4)
	assert_true(ray.has_target(), "facing the post, the ray finds it")
	assert_true(ray.prompt.contains("Talk to the post"), "and offers it: %s" % ray.prompt)
	assert_eq(_notes.size(), 1, "and announces it once")

	Social.talk(WREN, "core:dialogue/wren_tallow")
	assert_true(bool(Social.dialogue.call("is_running")), "a conversation is running")
	await _frames(4)
	assert_false(ray.has_target(), "while it runs, the ray offers nothing")
	assert_eq(_prompts.back() if not _prompts.is_empty() else "?", "", "and the prompt is taken down")
	assert_false(ray.try_interact(stage), "the interact key goes on through the conversation")
	assert_eq(int(post.get("used")), 0, "and does not reach past it to the post")

	Social.dialogue.call("stop")
	await _frames(4)
	assert_true(ray.has_target(), "once it ends, the ray finds the post again")
	assert_true(ray.prompt.contains("Talk to the post"), "and offers it again")
	assert_eq(_notes.size(), 1, "without announcing it a second time")

	# turning away and coming back is a new approach, and it is announced
	post.position = Vector3(0.0, 0.0, -9.0)
	await _frames(4)
	assert_false(ray.has_target(), "out of reach, nothing")
	post.position = Vector3(0.0, 0.0, -1.5)
	await _frames(4)
	assert_true(ray.has_target(), "back in reach")
	assert_eq(_notes.size(), 2, "and announced again")

	EventBus.notify.disconnect(_on_notify)
	_tree().root.remove_child(stage)
	stage.free()
