extends TestCase
## The screen fade is an autoload layer, so a fade to black started by the main menu or the
## Naming outlives the scene change into the world. Nothing lifted it: the world stood up and
## ran behind an opaque rectangle, which a player reads as the game never loading. The body
## arriving in the world (`EventBus.player_spawned`) is what lifts it now.


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _settle(frames: int) -> void:
	for i in frames:
		await _tree().process_frame


func test_a_body_arriving_in_the_world_lifts_the_black_the_naming_left() -> void:
	UI.fade_to_black(0.0)
	await _settle(2)
	assert_true(UI.is_faded_out(), "the Naming's fade to black is up")
	var body := Node3D.new()
	_tree().root.add_child(body)
	EventBus.player_spawned.emit(body)
	# the fade in is a tween of under a second; wait it out in frames rather than real time
	var lifted := false
	for i in 120:
		await _tree().process_frame
		if not UI.is_faded_out():
			lifted = true
			break
	assert_true(lifted, "the fade never lifted after the player spawned")
	body.queue_free()
	await _settle(1)


func test_fading_in_when_nothing_is_faded_is_harmless() -> void:
	UI.fade_from_black(0.0)
	await _settle(2)
	assert_false(UI.is_faded_out(), "no fade to lift")
	UI.fade_from_black(0.0)
	await _settle(2)
	assert_false(UI.is_faded_out())


## Between "Be named" and the first look at the world the screen was a dead black rectangle for
## as long as the terrain took. A menu that hands over to the world now says a line over it, and
## the caption stays until the body arrives.
func test_the_fade_from_a_menu_carries_a_caption_until_the_body_arrives() -> void:
	UI.fade_to_black(0.0, "The Warden walks you out of the Hush.")
	await _settle(2)
	assert_true(UI.is_loading_shown(), "no loading caption over the menu's fade")
	assert_true(UI.loading_text().contains("The Warden walks you out of the Hush."), "the caption does not say the line")
	assert_true(UI.loading_text().contains("Raising the ground"), "with no world yet, the caption should say the ground is being raised")
	var body := Node3D.new()
	_tree().root.add_child(body)
	EventBus.player_spawned.emit(body)
	var gone := false
	for i in 120:
		await _tree().process_frame
		if not UI.is_loading_shown():
			gone = true
			break
	assert_true(gone, "the caption stayed up after the player spawned")
	var lifted := false
	for i in 120:
		await _tree().process_frame
		if not UI.is_faded_out():
			lifted = true
			break
	assert_true(lifted, "and the fade should have lifted with it")
	body.queue_free()
	await _settle(1)


func test_a_door_fade_carries_no_caption() -> void:
	UI.fade_to_black(0.0)
	await _settle(2)
	assert_false(UI.is_loading_shown(), "a plain fade (a door) must not say the loading line")
	assert_eq(UI.loading_text(), "")
	UI.fade_from_black(0.0)
	await _settle(2)


func test_a_fade_in_replaces_a_fade_out_in_flight() -> void:
	UI.fade_to_black(5.0)
	await _settle(1)
	UI.fade_from_black(0.0)
	var lifted := false
	for i in 60:
		await _tree().process_frame
		if not UI.is_faded_out():
			lifted = true
			break
	assert_true(lifted, "the earlier fade-out tween kept driving the alpha up")
