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
var _started: Array[String] = []


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
	# The parcel tests below are about carrying a parcel, so the radiant generator is kept
	# out of the way for them; the last test takes the override off and presses Take on the
	# real thing a board lists.
	Peers.overrides["social"] = null


func after_each() -> void:
	Peers.overrides.clear()
	for id in _started:
		Social.quests.forget(id)
	_started.clear()
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


## Taking a bounty off the board, by pressing the button on the screen.
##
## `Social.take_quest()` is the front door the social stream put there for accepting board
## work, documented in two READMEs, and nothing outside a unit test had ever opened it: the
## board reached past it to the quest log's `start()` and emitted `quest_started` itself on
## top of the one `start()` already emits. It was unreachable in play anyway, because no board
## ever listed a quest — `Jobs.board_offers` asked the quest log for a `generate()` it does
## not have, and fell through to deliveries every time. Both halves are wired now, and this
## is the button.
func test_taking_a_bounty_off_the_board_starts_the_quest() -> void:
	Peers.overrides.erase("social")
	_open()
	await _tree().process_frame
	var offers := board.offers()
	assert_gt(offers.size(), 0, "the board had no radiant work on it")
	for job in offers:
		_started.append(str(job["id"]))
		assert_false(Social.quests.is_active(str(job["id"])), "that quest was already running")
	var take := _button("Take it")
	assert_true(take != null, "the board listed work and offered no way to take it")
	take.pressed.emit()
	await _tree().process_frame
	var accepted := board.accepted
	assert_eq(accepted.size(), 1, "pressing Take it took %d jobs" % accepted.size())
	var job_id: String = accepted[0]
	assert_true(Social.quests.is_active(job_id),
		"pressing Take it on %s put nothing in the journal" % job_id)
	assert_true(board.has_taken(job_id), "the notice stayed on the board after it was taken")
	assert_empty(board.taken, "a bounty is not a parcel and should not be carried")


## `QuestLog.start()` emits `quest_started` itself. The board used to emit it a second time,
## and emitted it even when the quest refused to start.
func test_the_quest_started_once_and_only_when_it_started() -> void:
	Peers.overrides.erase("social")
	var seen: Array[String] = []
	var note := func(id: String) -> void: seen.append(id)
	EventBus.quest_started.connect(note)
	var job := board.take(0, player)
	var job_id := str(job.get("id", ""))
	assert_false(job_id.is_empty(), "the board took nothing")
	_started.append(job_id)
	assert_eq(seen, [job_id] as Array[String],
		"one job taken, %d announcements of it" % seen.size())
	seen.clear()
	assert_true(board.take(0, player).is_empty(), "the same notice was taken twice")
	EventBus.quest_started.disconnect(note)
	assert_empty(seen, "a job that was not taken announced itself anyway")


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
