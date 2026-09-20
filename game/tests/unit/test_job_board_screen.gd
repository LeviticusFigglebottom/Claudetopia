extends TestCase
## Reading the notices, by pressing what is on the screen.
##
## `JobBoard.offers()`, `take()` and `deliver()` were complete and tested. No screen drew them
## and nothing in the world placed a board, so the whole of DESIGN §5.15's radiant work was a
## unit test. These press the buttons, because the two previous dead systems in this project
## both had a passing test of the function under the button.

const SCREEN := preload("res://ui/jobs/job_board_screen.tscn")
const MERROWBY := "core:place/merrowby"

var board: JobBoard
var player: Node3D
var bag: Inventory
var screen: Control


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	player = Node3D.new()
	player.add_to_group("player")
	_tree().root.add_child(player)
	bag = Inventory.new()
	bag.add_to_group("inventory")
	player.add_child(bag)
	board = JobBoard.new()
	board.place_id = MERROWBY
	board.display_name = "the notice post"
	_tree().root.add_child(board)


func after_each() -> void:
	for n in [screen, board, player]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	screen = null


func _open() -> void:
	screen = SCREEN.instantiate()
	screen.call("setup", {"board": board, "actor": player})
	_tree().root.add_child(screen)


func _button(text: String) -> Button:
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var b := n as Button
		if b != null and b.text == text:
			return b
		stack.append_array(n.get_children())
	return null


func _labels() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var l := n as Label
		if l != null:
			out.append(l.text)
		stack.append_array(n.get_children())
	return out


func test_the_board_shows_the_days_work() -> void:
	_open()
	await _tree().process_frame
	assert_false(board.offers().is_empty(), "a village board had no work on it at all")
	assert_true(_button("Take it") != null,
		"the board listed work and offered no way to take any of it")
	assert_true(_labels().has("the notice post"), "the board did not say which board it is")


func test_taking_one_puts_it_in_your_hands() -> void:
	_open()
	await _tree().process_frame
	_button("Take it").pressed.emit()
	await _tree().process_frame
	assert_eq(board.taken.size(), 1, "pressing Take it took nothing")
	assert_true(_button("Hand it over") != null,
		"a parcel in hand offered no way to hand it over")


func test_a_job_already_taken_is_not_offered_twice() -> void:
	_open()
	await _tree().process_frame
	var before := board.offers().size()
	_button("Take it").pressed.emit()
	await _tree().process_frame
	var takes := 0
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var b := n as Button
		if b != null and b.text == "Take it":
			takes += 1
		stack.append_array(n.get_children())
	assert_eq(takes, before - 1, "the board went on offering work already in hand")


## Walking up to a board must reach the screen. `interact()` emitted a node signal that
## nothing outside a test was connected to; the event bus is what the UI listens on.
func test_walking_up_to_it_opens_the_screen() -> void:
	var opened: Array[Node] = []
	var note := func(b: Node, _a: Node) -> void: opened.append(b)
	EventBus.job_board_opened.connect(note)
	board.interact(player)
	EventBus.job_board_opened.disconnect(note)
	assert_eq(opened, [board] as Array[Node],
		"reading the board told the UI nothing, so nothing was drawn")
	assert_true(UI.MENUS.has("job_board"), "the UI has no screen registered for a board")
