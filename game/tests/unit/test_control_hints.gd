extends TestCase
## The first minutes teach the controls. A strip at the foot of the HUD names what a new player
## reaches for, with the keys bound at this moment (the pad's buttons when a pad is in use), and
## lets each go once it has been done; the pause page reaches a page of every control. The
## playtest asked "no roll?" of a roll that worked, on a key nothing on the screen named.

const PLAYER := preload("res://actors/player/player.tscn")
const HUD_SCENE := "res://ui/hud/hud.tscn"
const KEYS: Array[Key] = [KEY_W, KEY_SHIFT, KEY_SPACE, KEY_E, KEY_CTRL]

var player: Player = null
var floor_body: StaticBody3D = null
var hints: ControlHints = null
var hud: Node = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(7)
	SaveSystem.pending.clear()
	Settings.load_settings()
	Settings._load_binding_defs()
	Settings.apply_bindings()
	Settings.data["gameplay"]["show_hints"] = true
	Settings.data["controls"]["sprint_tap_rolls"] = true
	Settings.data["controls"]["toggle_sprint"] = false
	UI.using_gamepad = false


func after_each() -> void:
	for k in KEYS:
		_key(k, false)
	_mouse(MOUSE_BUTTON_LEFT, false)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	UI.close_all()
	for n in [hints, hud, player, floor_body]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	hints = null
	hud = null
	player = null
	floor_body = null
	Settings.load_settings()
	Settings.apply_bindings()
	UI.using_gamepad = false
	GameState.reset_for_new_game(7)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.key_label = code
	ev.pressed = pressed
	ev.ctrl_pressed = pressed and code == KEY_CTRL
	ev.shift_pressed = pressed and code == KEY_SHIFT
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _mouse(button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _ticks(n: int) -> void:
	for i in n:
		await _tree().physics_frame


func _make_hints() -> ControlHints:
	hints = ControlHints.new()
	_tree().root.add_child(hints)
	return hints


func _stand() -> void:
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	_tree().root.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	player.teleport(Vector3(0.0, 0.02, 0.0), 0.0)
	await _ticks(8)


func test_the_strip_names_the_keys_bound_now() -> void:
	_make_hints()
	assert_eq(hints.showing(), ["move", "sprint", "roll", "jump", "use", "strike", "block"])
	assert_true(hints.visible, "a new player sees the strip")
	assert_eq(hints.keys_for("move"), ["WASD"])
	assert_eq(hints.keys_for("sprint"), ["Shift"])
	assert_eq(hints.keys_for("roll"), ["tap Shift"], "the roll is named as a tap of Sprint")
	assert_eq(hints.keys_for("jump"), ["Space"])
	assert_eq(hints.keys_for("use"), ["E"])
	assert_eq(hints.keys_for("strike"), ["LMB"])
	assert_eq(hints.keys_for("block"), ["RMB"])
	# rebound, the strip follows at once
	Settings.bindings["jump"] = ["key:J", "joy_button:3"]
	Settings.apply_bindings()
	assert_eq(hints.keys_for("jump"), ["J"], "the strip still names the old jump key")
	# with the tap turned off, the roll is the Dodge key
	Settings.set_value("controls", "sprint_tap_rolls", false, false)
	assert_eq(hints.keys_for("roll"), ["Ctrl"])
	var words := []
	for c in hints.find_children("*", "Label", true, false):
		words.append((c as Label).text)
	assert_true(words.has("Ctrl") and words.has("J"), "the strip on screen was not rebuilt: %s" % str(words))


func test_a_pad_shows_the_pads_buttons() -> void:
	_make_hints()
	UI.using_gamepad = true
	UI.input_device_changed.emit(true)
	assert_eq(hints.keys_for("move"), ["LS"])
	assert_eq(hints.keys_for("roll"), ["B"], "on a pad the roll is B, not a tap of anything")
	assert_eq(hints.keys_for("jump"), ["Y"])
	assert_eq(hints.keys_for("use"), ["A"])
	assert_eq(hints.keys_for("strike"), ["RB"])
	var words := []
	for c in hints.find_children("*", "Label", true, false):
		words.append((c as Label).text)
	assert_true(words.has("B") and words.has("LS"), "the strip on screen still shows the keyboard: %s" % str(words))


## Each thing goes once it has been done with the keys, and when nothing is left the strip goes.
func test_each_item_goes_once_it_is_done() -> void:
	await _stand()
	_make_hints()
	_key(KEY_W, true)
	await _ticks(100)
	assert_true(hints.learned.has("move"), "walking about did not count as moving")
	_key(KEY_SHIFT, true)
	await _ticks(70)
	assert_true(hints.learned.has("sprint"), "a second of Shift did not count as a sprint")
	_key(KEY_SHIFT, false)
	await _ticks(20)
	_key(KEY_SHIFT, true)
	await _ticks(5)
	_key(KEY_SHIFT, false)
	await _ticks(10)
	assert_true(hints.learned.has("roll"), "a tap of Shift rolled and the strip did not notice")
	_key(KEY_W, false)
	await _ticks(50)
	_key(KEY_SPACE, true)
	await _ticks(10)
	_key(KEY_SPACE, false)
	assert_true(hints.learned.has("jump"), "a jump did not count")
	await _ticks(90)
	_key(KEY_E, true)
	await _ticks(3)
	_key(KEY_E, false)
	assert_true(hints.learned.has("use"), "E did not count as using")
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _ticks(4)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _ticks(60)
	assert_true(hints.learned.has("strike"), "a swing did not count")
	_mouse(MOUSE_BUTTON_RIGHT, true)
	await _ticks(40)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	assert_true(hints.learned.has("block"), "raising the guard did not count")
	assert_eq(hints.showing(), [], "everything was done and the strip still shows %s" % str(hints.showing()))
	await _ticks(60)
	assert_false(hints.visible, "with nothing left to teach, the strip stays up")
	# kept with the game: a strip made again in the same game has nothing to teach
	assert_eq(Array(GameState.get_flag(ControlHints.LEARNED_FLAG, [])).size(), 7, "what was learned was not kept")
	var again := ControlHints.new()
	_tree().root.add_child(again)
	assert_eq(again.showing(), [], "the same game taught the controls twice")
	assert_false(again.visible)
	again.queue_free()


func test_the_hints_setting_turns_it_off() -> void:
	_make_hints()
	Settings.set_value("gameplay", "show_hints", false, false)
	assert_false(hints.visible)
	Settings.set_value("gameplay", "show_hints", true, false)
	assert_true(hints.visible)


func test_the_hud_carries_the_strip() -> void:
	hud = (load(HUD_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(hud)
	await _tree().process_frame
	var found := hud.find_children("*", "ControlHints", true, false)
	assert_eq(found.size(), 1, "the HUD has no hint strip")


func test_the_pause_page_reaches_every_control() -> void:
	var pause := UI.open("pause")
	assert_true(pause != null, "the pause page did not open")
	var entries := []
	for b in pause.find_children("*", "Button", true, false):
		entries.append((b as Button).text)
	assert_true(entries.has("How to move and fight"), "the pause page has no way to the controls: %s" % str(entries))
	var page := UI.open("controls")
	assert_true(page != null, "the controls page did not open")
	await _tree().process_frame
	var lines := []
	for l in page.find_children("*", "Label", true, false):
		lines.append((l as Label).text)
	for want in ["Roll", "tap Shift", "Jump", "Space", "Light attack", "LMB", "Look about", "mouse"]:
		assert_true(lines.has(want), "the controls page does not say '%s'" % want)
	for pad_only in ["RX", "RY", "LS"]:
		assert_false(lines.has(pad_only), "the keyboard's page shows the pad's %s" % pad_only)
