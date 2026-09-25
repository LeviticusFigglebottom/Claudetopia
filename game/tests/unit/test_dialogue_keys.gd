extends TestCase
## The keys a player's hand is already on choose a conversation's answers (playtest 6: "W and S
## can't be used for selection"). The dialogue screen is given a stand-in runner and its answers,
## and the keys are pressed as a hand presses them: through Input and the viewport, not by calling
## the function under them.

const SCENE := "res://ui/dialogue/dialogue_ui.tscn"


class FakeRunner:
	extends Node
	signal line_shown(speaker: String, text: String, choices: Array)
	signal choice_needed(choices: Array)
	signal ended
	var chosen := -1
	var advanced := 0

	func choose(i: int) -> void:
		chosen = i

	func advance() -> void:
		advanced += 1

	func is_running() -> bool:
		return true


var _ui: Control = null
var _runner: FakeRunner = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_ui = (load(SCENE) as PackedScene).instantiate() as Control
	_tree().root.add_child(_ui)
	_runner = FakeRunner.new()
	_tree().root.add_child(_runner)
	_ui.call("bind_runner", _runner)


func after_each() -> void:
	for n in [_ui, _runner]:
		if n != null and is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_ui = null
	_runner = null


## Three answers up, the line typed out.
func _answers_up() -> void:
	var choices := [{"text": "Who are you?"}, {"text": "What is this place?"}, {"text": "Goodbye."}]
	_runner.line_shown.emit("Wren Tallow", "Well? Ask.", choices)
	_ui.call("_finish_typing")
	for i in 3:
		await _tree().process_frame


func _key_of(action: String) -> InputEventKey:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return ev as InputEventKey
	return null


func _press(action: String) -> void:
	var key := _key_of(action)
	assert_true(key != null, "'%s' has a key" % action)
	if key == null:
		return
	for pressed in [true, false]:
		var ev := key.duplicate() as InputEventKey
		ev.pressed = pressed
		# once, as a keyboard sends it: Input passes it on to the viewport as well
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		for i in 2:
			await _tree().process_frame


func test_s_twice_then_e_takes_the_third_answer() -> void:
	await _answers_up()
	assert_eq(int(_ui.call("focused_choice")), 0, "the first answer has the focus when they come up")
	await _press("move_back")
	await _press("move_back")
	assert_eq(int(_ui.call("focused_choice")), 2, "S twice moves the focus to the third")
	await _press("interact")
	assert_eq(_runner.chosen, 2, "and E takes the third answer")


func test_w_moves_back_up_and_stops_at_the_top() -> void:
	await _answers_up()
	await _press("move_back")
	await _press("move_forward")
	await _press("move_forward")
	assert_eq(int(_ui.call("focused_choice")), 0, "W goes back up, and not past the first")
	await _press("interact")
	assert_eq(_runner.chosen, 0, "E takes the answer the focus is on")


func test_e_on_a_line_without_answers_goes_on() -> void:
	_runner.line_shown.emit("Wren Tallow", "There you are.", [])
	_ui.call("_finish_typing")
	await _tree().process_frame
	await _press("interact")
	assert_eq(_runner.advanced, 1, "E on a line with no answers goes on to the next")
	assert_eq(_runner.chosen, -1, "and chooses nothing")
