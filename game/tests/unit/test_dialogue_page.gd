extends TestCase
## The dialogue page is never left on the screen with nothing on it (triage 41: after the wake, on
## the Naming's waystones, the page stood open across the bottom of the screen in the rain with no
## name, no line and no answers, and no key took it down). The gesture wheel's close put the page
## back whenever it had only been hidden by its parent, which was always: a G pressed and let go in
## the open country raised an empty page. And a node whose every answer its conditions closed off
## left nothing to press.

const SCENE := "res://ui/dialogue/dialogue_ui.tscn"


class FakeRunner:
	extends Node
	signal line_shown(speaker: String, text: String, choices: Array)
	signal choice_needed(choices: Array)
	signal ended
	var running := false
	var advanced := 0
	var stopped := 0

	func choose(_i: int) -> void:
		pass

	func advance() -> void:
		advanced += 1

	func stop() -> void:
		if running:
			running = false
			stopped += 1
			ended.emit()

	func is_running() -> bool:
		return running


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


func _on_screen() -> bool:
	return bool(_ui.call("on_screen"))


func _frames(seconds: float) -> void:
	for i in int(seconds * 60.0):
		_ui.call("_process", 1.0 / 60.0)


func test_nothing_is_on_screen_before_anybody_speaks() -> void:
	assert_false(_on_screen(), "a fresh page is not up")


func test_the_gesture_wheel_in_the_open_brings_no_empty_page_back() -> void:
	# the screenshot: G pressed and let go with nobody being spoken to
	_ui.call("open_gesture_wheel", "")
	assert_true(bool(_ui.call("wheel_open")), "the wheel opens")
	_ui.call("close_gesture_wheel")
	assert_false(_on_screen(), "closing it raises no page")
	assert_false(_ui.visible, "and nothing of the dialogue layer is left up")
	# and after a conversation that has ended
	_runner.running = true
	_runner.line_shown.emit("Wren Tallow", "Go on, then.", [])
	_runner.stop()
	await _tree().create_timer(0.45).timeout
	assert_false(_on_screen(), "the goodbye takes the page down")
	_ui.call("open_gesture_wheel", "")
	_ui.call("close_gesture_wheel")
	assert_false(_on_screen(), "and the wheel does not put that page back either")


func test_the_wheel_during_a_talk_gives_the_page_back() -> void:
	_runner.running = true
	_runner.line_shown.emit("Wren Tallow", "Well?", [{"index": 0, "text": "Goodbye."}])
	_ui.call("open_gesture_wheel", "core:npc/wren_tallow")
	assert_false(_on_screen(), "the page steps aside for the wheel")
	_ui.call("close_gesture_wheel")
	assert_true(_on_screen(), "and comes back while the talk runs")


func test_a_line_with_nothing_in_it_is_not_put_up() -> void:
	_runner.running = true
	_runner.line_shown.emit("", "", [])
	assert_false(_on_screen(), "no name, no line, no answers: no page")
	await _tree().process_frame
	assert_eq(_runner.advanced, 1, "and the conversation is moved on past it")


func test_a_page_with_no_conversation_behind_it_goes_by_itself() -> void:
	_runner.running = true
	_runner.line_shown.emit("Wren Tallow", "There you are.", [])
	_ui.call("_finish_typing")
	_frames(1.0)
	assert_true(_on_screen(), "a live conversation's page stays while it is read")
	_runner.running = false          # ended without a word to the page
	_frames(1.0)
	assert_false(_on_screen(), "a page nobody is talking behind is taken down")


func test_escape_leaves_the_conversation() -> void:
	_runner.running = true
	_runner.line_shown.emit("Wren Tallow", "Well? Ask.", [{"index": 0, "text": "Who are you?"}])
	_ui.call("_finish_typing")
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	_ui.call("_unhandled_input", ev)
	assert_eq(_runner.stopped, 1, "Escape ends the talk")
	await _tree().create_timer(0.45).timeout
	assert_false(_on_screen(), "and the page goes with it")


# --- the runner's side: a node that would have nothing to press ------------------------------

func test_a_node_whose_answers_are_all_closed_off_offers_a_way_out() -> void:
	var runner: Node = preload("res://systems/dialogue/dialogue_runner.gd").new()
	runner.set("ctx", SocialFakes.context())
	_tree().root.add_child(runner)
	var shown: Array = []
	runner.connect("line_shown", func(_s: String, text: String, choices: Array) -> void: shown.append([text, choices]))
	runner.call("start_def", {"id": "test:dialogue/closed", "start": "a", "nodes": {"a": {"speaker": "Someone", "text": "Hm.",
			"choices": [{"text": "Only if.", "next": "b", "conditions": [{"false": true}]}]},
			"b": {"speaker": "Someone", "text": "So."}}}, "")
	assert_true(bool(runner.call("is_running")), "the conversation is not closed in the player's face")
	var choices: Array = shown.back()[1]
	assert_eq(choices.size(), 1, "one answer is offered: %s" % str(choices))
	assert_eq(str(choices[0].get("text", "")) if not choices.is_empty() else "", runner.get("LEAVE_CHOICE"), "and it is the way out")
	runner.call("choose", 0)
	assert_false(bool(runner.call("is_running")), "which leaves")
	runner.get_parent().remove_child(runner)
	runner.free()


func test_a_node_with_no_line_and_nothing_to_ask_still_says_something() -> void:
	var runner: Node = preload("res://systems/dialogue/dialogue_runner.gd").new()
	runner.set("ctx", SocialFakes.context())
	_tree().root.add_child(runner)
	var shown: Array = []
	runner.connect("line_shown", func(_s: String, text: String, _c: Array) -> void: shown.append(text))
	runner.call("start_def", {"id": "test:dialogue/blank", "start": "a", "nodes": {"a": {"speaker": "Someone", "text": "", "next": "b"},
			"b": {"speaker": "Someone", "text": "There."}}}, "")
	assert_false(str(shown[0]).strip_edges().is_empty(), "a blank node puts up a line, not nothing")
	runner.call("stop")
	runner.get_parent().remove_child(runner)
	runner.free()
