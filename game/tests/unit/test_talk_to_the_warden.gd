extends TestCase
## Talking to the Warden the way a player does: walk up to her, face her, press the interact key.
##
## The playtest's first report on the new start was "talking to Wren doesn't do anything", and it
## didn't. The interact key reached her, and her `interact` announced a conversation that nothing
## started. Every test had reached past it to `Social.talk`, and the flow probe only looked at where
## she stood. Behind that was a second fault: her conversation's goodbye went back to its hub, so
## once it had started it could not be left.
##
## This goes through the world's own body, its interaction ray, the key bound to `interact`, the
## HUD's prompt and the conversation on the screen, and says goodbye the way a player picks an
## answer. The opening is off here; its own hand-over is held by test_cinematic_player and the flow.

const WORLD_SCENE := "res://world/world.tscn"
const WREN := "core:npc/wren_tallow"
const NAMING := "core:quest/the_naming"
## Seconds for the world to stand up round the start with the Warden at her fire.
const STAND_TIMEOUT := 180.0

var _setting_was: Variant = true


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _built() -> bool:
	return FileAccess.file_exists("res://world/generated/world_manifest.json")


func before_each() -> void:
	_setting_was = Settings.get_value("gameplay", "play_opening", true)
	Settings.set_value("gameplay", "play_opening", false, false)
	Social.reset_for_new_game()
	GameState.reset_for_new_game(41)
	GameState.set_flag("player_name", "Tam Cresswell")
	GameState.set_flag("new_game", true)


func after_each() -> void:
	Settings.set_value("gameplay", "play_opening", _setting_was, false)
	if bool(Social.dialogue.call("is_running")):
		Social.dialogue.call("stop")
	Input.action_release("interact")


func test_walking_up_to_the_warden_and_pressing_interact_talks_to_her() -> void:
	if not _built():
		return
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	var player := w.get_node("PlayerSpawn").get("player") as Node3D
	var wren := await _warden_at_her_fire(w, player)
	assert_true(wren != null, "the Warden is at her fire and the player's hands are free")
	if wren == null:
		await _drop(w)
		return
	var log_node := _tree().get_first_node_in_group("quest_log")
	assert_eq(str(log_node.call("stage_id_of", NAMING)), "wake", "the Naming asks the player to speak to her")
	var interactor: Node = player.get("interactor")
	var reach := float(interactor.get("reach"))

	# four metres out is further than the interact ray reaches: no prompt, and a press does nothing
	await _stand_facing(w, player, wren, 4.0)
	wren = await _find_her(w)
	if wren == null:
		fail("the Warden went while the player stood four metres off")
		await _drop(w)
		return
	assert_false(_finds(player, wren), "four metres out, the interact ray (%.1f m) does not reach her" % reach)
	await _press("interact")
	assert_false(bool(Social.dialogue.call("is_running")), "and pressing interact there starts nothing")

	for d: float in [2.5, 1.5]:
		wren = await _find_her(w)
		if wren == null:
			fail("the Warden went before the player stood %.1f m off" % d)
			break
		await _stand_facing(w, player, wren, d)
		wren = await _find_her(w)
		if wren == null:
			fail("the Warden went while the player stood %.1f m off" % d)
			break
		assert_true(_finds(player, wren), "at %.1f m, facing her, the interact ray finds her" % d)
		var prompt := str(UI.hud().call("prompt_text")) if UI.hud() != null else ""
		assert_true(prompt.contains("Wren Tallow"), "at %.1f m the prompt says who: %s" % [d, prompt])
		await _press("interact")
		var talking := await _until(func() -> bool: return bool(Social.dialogue.call("is_running")), 5.0)
		assert_true(talking, "at %.1f m, pressing interact starts a conversation with her" % d)
		assert_eq(str(Social.dialogue.get("npc_id")), WREN, "with her")
		var shown := await _until(func() -> bool: return bool(UI.show_dialogue().call("on_screen")), 5.0)
		assert_true(shown, "and the conversation is on the screen")
		# she turns and the camera eases round on the game's own clock, which crawls when the
		# machine is loaded (a full suite beside other runs): wait on the wall for what is checked
		# below, not a count of frames
		var rig: CameraRig = player.get("camera_rig")
		await _until(func() -> bool: return _turned_and_framed(w, player, rig), 10.0)
		wren = await _find_her(w)
		if wren == null:
			fail("the Warden went while she talked at %.1f m" % d)
			break
		var to_player := player.global_position - wren.global_position
		to_player.y = 0.0
		var facing := _facing(wren)
		assert_gt(facing.dot(to_player.normalized()), 0.7,
				"at %.1f m she has turned to face the player while they talk (facing %s, the player %s)" % [d, facing, to_player.normalized()])
		assert_true(rig.is_framing_speaker(), "at %.1f m the camera frames her" % d)
		var to_cam := rig.camera.global_position - wren.global_position
		to_cam.y = 0.0
		assert_gt(facing.dot(to_cam.normalized()), 0.3,
				"at %.1f m her face is towards the camera (facing %s, the camera %s from her)" % [d, facing, to_cam])
		var left := await _talk_it_through(30.0)
		assert_true(left, "at %.1f m the conversation is talked through to its goodbye, and the press that ends it does not start it again" % d)
		if d == 2.5:
			var moved := await _until(func() -> bool: return str(log_node.call("stage_id_of", NAMING)) != "wake", 3.0)
			assert_true(moved, "speaking to her is the Naming's first objective done (now at '%s')" % str(log_node.call("stage_id_of", NAMING)))
	await _drop(w)


## Waits for the story to have started, the Warden to be standing (in the tree) and the country to
## have let go of the player's hands.
func _warden_at_her_fire(w: World, player: Node3D) -> Node3D:
	var until := Time.get_ticks_msec() + int(STAND_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < until:
		var log_node := _tree().get_first_node_in_group("quest_log")
		var begun := log_node != null and bool(log_node.call("is_active", NAMING))
		var wren := _her(w)
		if begun and wren != null and player != null and bool(player.get("input_enabled")) and not UI.is_holding_for_country():
			return wren
		await _tree().process_frame
	return null


## The Warden as she stands now, found again every time she is needed. Held across awaits, she
## was sometimes a freed object by the next step of the full suite: the registry's actor can be one
## an earlier test left queued for deletion, or the one the world had while it settled, and a
## person the world stands up again is a new node. (She is not under the World: the registry puts
## people under the "world_dynamic" group's node, or the running scene.)
func _her(w: World) -> Node3D:
	if NpcRegistry.instance == null or not is_instance_valid(w):
		return null
	var a: Node = NpcRegistry.instance.actor(WREN)
	if a == null or not is_instance_valid(a) or a.is_queued_for_deletion() or not a.is_inside_tree():
		return null
	return a as Node3D


## Her again, given a few seconds to be stood up again if the world has just put her back.
func _find_her(w: World) -> Node3D:
	await _until(func() -> bool: return _her(w) != null, 5.0)
	return _her(w)


## Stands the player `d` metres from her, on the side the start is on, facing her with the camera
## at its resting pitch, and lets the interaction ray look.
func _stand_facing(w: World, player: Node3D, wren: Node3D, d: float) -> void:
	var at := wren.global_position
	var away := Vector3(player.global_position.x - at.x, 0.0, player.global_position.z - at.z)
	if away.length() < 0.1:
		away = Vector3(0.0, 0.0, 1.0)
	away = away.normalized()
	var spot := at + away * d
	spot.y = w.provider.get_height(spot.x, spot.z) + 0.05
	player.set("velocity", Vector3.ZERO)
	player.global_position = spot
	var to := at - spot
	var yaw := atan2(-to.x, -to.z)
	player.rotation.y = yaw
	var rig: Node = player.get("camera_rig")
	rig.set("yaw", yaw)
	rig.set("pitch", -0.18)
	player.reset_physics_interpolation()
	for i in 10:
		await _tree().physics_frame


## Whether the Warden faces the player and the camera has come round to her face: what the talk's
## checks ask, read afresh each time since she can be a new node after a cell reload.
func _turned_and_framed(w: World, player: Node3D, rig: CameraRig) -> bool:
	var her := _her(w)
	if her == null or not rig.is_framing_speaker():
		return false
	var facing := _facing(her)
	var to_player := player.global_position - her.global_position
	to_player.y = 0.0
	var to_cam := rig.camera.global_position - her.global_position
	to_cam.y = 0.0
	return facing.dot(to_player.normalized()) > 0.7 and facing.dot(to_cam.normalized()) > 0.3


## Which way a person faces, as the Npc reckons it (its model is turned, not its body).
func _facing(wren: Node3D) -> Vector3:
	return wren.call("facing_flat")


func _finds(player: Node3D, wren: Node3D) -> bool:
	var interactor: Node = player.get("interactor")
	return interactor != null and bool(interactor.call("has_target")) and interactor.get("target") == wren


## Goes through the conversation as a player does: the interact key on a line, the last answer
## offered when there are answers (the goodbye, the way these conversations are written). A line
## still typing out is finished by the interact key first, which does nothing else while answers
## are up. True when it has ended and stays ended.
func _talk_it_through(timeout: float) -> bool:
	var until := Time.get_ticks_msec() + int(timeout * 1000.0)
	var presses := 0
	while bool(Social.dialogue.call("is_running")) and Time.get_ticks_msec() < until and presses < 60:
		var choices: Array = Social.dialogue.get("current_choices")
		if choices.is_empty():
			await _press("interact")
		elif choices.size() <= 9:
			await _press("interact")
			await _press_key(KEY_1 + choices.size() - 1)
		else:
			await _press_last_button()
		presses += 1
	for i in 8:
		await _tree().physics_frame
	return not bool(Social.dialogue.call("is_running"))


## The key bound to an action, pressed and let go as a hand does: the Input singleton's state (what
## the body reads each physics frame) and the viewport's input (what the dialogue on the screen reads).
func _press(action: String) -> void:
	var key: InputEventKey = null
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			key = ev as InputEventKey
			break
	assert_true(key != null, "'%s' has a key bound to it" % action)
	if key == null:
		return
	await _send(key)


func _press_key(code: int) -> void:
	var key := InputEventKey.new()
	key.keycode = code as Key
	key.physical_keycode = code as Key
	await _send(key)


func _send(key: InputEventKey) -> void:
	var down := key.duplicate() as InputEventKey
	down.pressed = true
	Input.parse_input_event(down)
	_tree().root.push_input(down)
	Input.flush_buffered_events()
	for i in 3:
		await _tree().physics_frame
	var up := key.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	_tree().root.push_input(up)
	Input.flush_buffered_events()
	for i in 3:
		await _tree().physics_frame


## More answers than there are number keys: the last one clicked, as a mouse would.
func _press_last_button() -> void:
	var ui: Node = UI.show_dialogue()
	var box: Node = ui.get("_choice_box") if ui != null else null
	if box == null or box.get_child_count() == 0:
		await _press("interact")
		return
	(box.get_child(box.get_child_count() - 1) as BaseButton).pressed.emit()
	for i in 3:
		await _tree().physics_frame


func _until(pred: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if bool(pred.call()):
			return true
		await _tree().process_frame
	return bool(pred.call())


func _drop(w: Node) -> void:
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame
