extends TestCase
## The roll, from the keys a player presses. Every event here is a real key or button event fed
## through the input map the game builds from core/default_bindings.json -- not Input.action_press,
## which would prove the roll works and nothing about whether a player can reach it.
##
## The playtest said "no roll?". The roll was on Ctrl alone, a key the genre does not use for it
## and a player does not find without reading. Now a tap of Sprint rolls, as the Souls games have
## taught most of the people who will play this; a hold sprints; Space stays jump; Ctrl still
## rolls. On a pad Sprint is B, and B does the same: a tap rolls, a hold runs.

const PLAYER := preload("res://actors/player/player.tscn")
const KEYS: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_CTRL, KEY_SPACE, KEY_ALT]

var player: Player = null
var floor_body: StaticBody3D = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(7)
	SaveSystem.pending.clear()
	# The defaults as shipped, whatever this machine's own settings file says. Nothing is saved.
	Settings.load_settings()
	Settings._load_binding_defs()
	Settings.apply_bindings()
	Settings.data["controls"]["sprint_tap_rolls"] = true
	Settings.data["controls"]["toggle_sprint"] = false


func after_each() -> void:
	for k in KEYS:
		_key(k, false)
	_pad_button(JOY_BUTTON_B, false)
	_pad_button(JOY_BUTTON_LEFT_STICK, false)
	_key(KEY_W, false)          # a key event last, so the UI is back on the keyboard
	for n in [player, floor_body]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	player = null
	floor_body = null
	Settings.load_settings()
	Settings.apply_bindings()
	GameState.reset_for_new_game(7)


## A key as a keyboard sends it: a modifier key reports itself held while it is down.
func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.key_label = code
	ev.pressed = pressed
	ev.ctrl_pressed = pressed and code == KEY_CTRL
	ev.shift_pressed = pressed and code == KEY_SHIFT
	ev.alt_pressed = pressed and code == KEY_ALT
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _pad_button(button: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = pressed
	ev.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _ticks(n: int) -> void:
	for i in n:
		await _tree().physics_frame


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


## Runs until the body leaves the roll (or `limit` ticks pass) and reports what the roll did:
## {started, ticks from the key to the roll, metres covered in it, seconds untouchable, clip}.
func _watch_roll(limit := 90) -> Dictionary:
	var out := {"started": false, "after": -1, "metres": 0.0, "iframes": 0.0, "clip": ""}
	var from := Vector3.ZERO
	for i in limit:
		await _tree().physics_frame
		var rolling := player.state == Player.State.DODGE
		if rolling and not bool(out["started"]):
			out["started"] = true
			out["after"] = i
			from = player.global_position
			out["clip"] = player.anim.current_clip
		if bool(out["started"]):
			if player.is_in_iframes():
				out["iframes"] = float(out["iframes"]) + 1.0 / Engine.physics_ticks_per_second
			if not rolling:
				out["metres"] = Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length()
				return out
	if bool(out["started"]):
		out["metres"] = Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length()
	return out


func _assert_a_roll(r: Dictionary, what: String) -> void:
	assert_true(bool(r["started"]), "%s did not roll" % what)
	if not bool(r["started"]):
		return
	assert_true(int(r["after"]) <= 2, "%s rolled %d ticks late" % [what, int(r["after"])])
	var params := DamageModel.dodge_params(0.0)
	assert_near(float(r["metres"]), float(params["distance"]), 0.5, "%s carried the body %.2f m" % [what, float(r["metres"])])
	var window := float(params["iframe_end"]) - float(params["iframe_start"])
	assert_near(float(r["iframes"]), window, 2.5 / Engine.physics_ticks_per_second,
			"%s was untouchable for %.2f s" % [what, float(r["iframes"])])
	assert_true(str(r["clip"]).begins_with("Dodge_"), "%s played %s, not a roll" % [what, str(r["clip"])])


func _report(what: String, r: Dictionary) -> void:
	print("    %s: rolled %d ticks after the key, %.2f m, untouchable for %.2f s, %s" % [
		what, int(r["after"]), float(r["metres"]), float(r["iframes"]), str(r["clip"])])


## Ctrl, the Dodge key as shipped, rolls a jogging body forward: it moves the body the roll's
## distance, it is untouchable for the roll's window, and the model plays a roll.
func test_ctrl_rolls_the_body_with_its_i_frames() -> void:
	await _stand()
	_key(KEY_W, true)
	await _ticks(40)
	_key(KEY_CTRL, true)
	var r := await _watch_roll()
	_key(KEY_CTRL, false)
	_key(KEY_W, false)
	_report("Ctrl", r)
	_assert_a_roll(r, "Ctrl")


## A tap of Shift rolls, and does not lurch into a sprint first. A hold of Shift sprints, and
## letting it go after a sprint is not a roll.
func test_a_tap_of_shift_rolls_and_a_hold_sprints() -> void:
	await _stand()
	_key(KEY_W, true)
	await _ticks(40)
	_key(KEY_SHIFT, true)
	var lurched := false
	for i in 6:
		await _tree().physics_frame
		lurched = lurched or player.is_sprinting
	_key(KEY_SHIFT, false)
	var r := await _watch_roll()
	_report("a tap of Shift", r)
	_assert_a_roll(r, "a tap of Shift")
	assert_false(lurched, "the tap sprinted before it rolled")
	await _ticks(30)
	var rolled := false
	_key(KEY_SHIFT, true)
	for i in 90:
		await _tree().physics_frame
		rolled = rolled or player.state == Player.State.DODGE
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	assert_true(player.is_sprinting, "holding Shift does not sprint")
	assert_gt(speed, Player.JOG_SPEED + 1.0, "held a second and a half, Shift ran at %.2f m/s" % speed)
	_key(KEY_SHIFT, false)
	for i in 30:
		await _tree().physics_frame
		rolled = rolled or player.state == Player.State.DODGE
	_key(KEY_W, false)
	assert_false(rolled, "a held Shift rolled")


## Space jumps, as it does everywhere, and does not roll.
func test_space_jumps_and_does_not_roll() -> void:
	await _stand()
	_key(KEY_SPACE, true)
	var rose := false
	var rolled := false
	for i in 30:
		await _tree().physics_frame
		rose = rose or player.velocity.y > 2.0
		rolled = rolled or player.state == Player.State.DODGE
	_key(KEY_SPACE, false)
	assert_true(rose, "Space did not jump")
	assert_false(rolled, "Space rolled")


## On a pad, a tap of B rolls and a hold of B runs, as the Souls games have it; the left stick's
## click sneaks and neither rolls nor runs.
func test_b_on_a_pad_rolls_on_a_tap_and_runs_held() -> void:
	await _stand()
	_key(KEY_W, true)
	await _ticks(40)
	_pad_button(JOY_BUTTON_B, true)
	await _ticks(5)
	_pad_button(JOY_BUTTON_B, false)
	var r := await _watch_roll()
	_report("a tap of B on a pad", r)
	_assert_a_roll(r, "a tap of B on a pad")
	await _ticks(30)
	var rolled := false
	_pad_button(JOY_BUTTON_B, true)
	for i in 90:
		await _tree().physics_frame
		rolled = rolled or player.state == Player.State.DODGE
	assert_true(player.is_sprinting, "holding B does not run")
	_pad_button(JOY_BUTTON_B, false)
	for i in 30:
		await _tree().physics_frame
		rolled = rolled or player.state == Player.State.DODGE
	assert_false(rolled, "a held B rolled")
	var sneaking := player.is_sneaking
	_pad_button(JOY_BUTTON_LEFT_STICK, true)
	await _ticks(3)
	_pad_button(JOY_BUTTON_LEFT_STICK, false)
	var r2 := await _watch_roll(30)
	_key(KEY_W, false)
	assert_false(bool(r2["started"]), "a click of the left stick rolled")
	assert_ne(player.is_sneaking, sneaking, "a click of the left stick did not sneak")


## The tap is a roll only while it is asked to be: not with its setting off, and not when Sprint is
## a toggle (the tap is the toggle).
func test_a_tap_rolls_only_when_it_is_asked_to() -> void:
	await _stand()
	Settings.data["controls"]["sprint_tap_rolls"] = false
	_key(KEY_SHIFT, true)
	await _ticks(5)
	_key(KEY_SHIFT, false)
	var r := await _watch_roll(30)
	assert_false(bool(r["started"]), "with the setting off, a tap of Shift rolled")
	Settings.data["controls"]["sprint_tap_rolls"] = true
	Settings.data["controls"]["toggle_sprint"] = true
	_key(KEY_SHIFT, true)
	await _ticks(5)
	_key(KEY_SHIFT, false)
	r = await _watch_roll(30)
	assert_false(bool(r["started"]), "with Sprint a toggle, a tap of Shift rolled")
	Settings.data["controls"]["toggle_sprint"] = false
	# and with all of that put back, the tap rolls again
	_key(KEY_SHIFT, true)
	await _ticks(5)
	_key(KEY_SHIFT, false)
	r = await _watch_roll()
	assert_true(bool(r["started"]), "the tap stopped rolling once its settings were back")
