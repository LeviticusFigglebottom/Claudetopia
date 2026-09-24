extends TestCase
## How the quest walker (tests/quests/quest_walker.gd) picks lines in a conversation
## (tests/quests/dialogue_steer.gd). The walker finds and plays each quest through the real
## dialogue runner, choosing the choices a player would. These pin that, on a graph of their own:
## it reaches a line more than one choice deep; it takes a choice for its effect; it looks past
## a choice whose condition a line on the way satisfies; while going through a quest's lines it
## makes no decision and ends nothing; and it gives up rather than wander when the line is not
## there.

const WHO := "core:npc/test_steered"
const QUEST := "core:quest/test_steering"
const GRAPH := {"id": "core:dialogue/test_steered", "start": "hub", "nodes": {
	"hub": {"speaker": "npc", "text": "Well?", "choices": [
		{"text": "How is the bread?", "next": "bread"},
		{"text": "About the mill.", "next": "mill"},
		{"text": "Tell me the secret.", "next": "secret", "conditions": [{"flag": "steer_asked_nicely"}]},
		{"text": "Please.", "next": "hub", "effects": [{"set_flag": "steer_asked_nicely"}]},
		{"text": "Goodbye.", "next": "end"}]},
	"bread": {"speaker": "npc", "text": "Slow.", "next": "hub"},
	"mill": {"speaker": "npc", "text": "The wheel stopped.", "choices": [
		{"text": "Why did it stop?", "next": "the_wheel"},
		{"text": "Never mind.", "next": "hub"}]},
	"the_wheel": {"speaker": "npc", "text": "Something in the race.", "next": "hub"},
	"secret": {"speaker": "npc", "text": "It was the miller.", "next": "hub"}}}
const QUEST_GRAPH := {"id": "core:dialogue/test_steered_quest", "start": "hub", "nodes": {
	"hub": {"speaker": "npc", "text": "You came back.", "choices": [
		{"text": "I will help.", "next": "hub", "conditions": [{"quest_active": "core:quest/test_steering"}],
				"effects": [{"set_flag": "steer_will_help"}]},
		{"text": "Burn it down.", "next": "end", "effects": [{"quest_choice": ["core:quest/test_steering", "burn"]}]},
		{"text": "I give up.", "next": "end", "effects": [{"fail_quest": "core:quest/test_steering"}]},
		{"text": "The weather?", "next": "hub"},
		{"text": "Goodbye.", "next": "end"}]}}}

var log_node: Node


func before_each() -> void:
	log_node = Social.quests
	GameState.reset_for_new_game(1)
	log_node.reset_for_new_game()


func after_each() -> void:
	if Social.dialogue.is_running():
		Social.dialogue.stop()
	UI.close_all()
	log_node.reset_for_new_game()
	Social.ctx.npc_id = ""


func _start(graph: Dictionary) -> Node:
	var runner: Node = Social.dialogue
	runner.start_def(graph, WHO)
	return runner


func test_it_reaches_a_line_two_choices_deep() -> void:
	var runner := _start(GRAPH)
	var r := DialogueSteer.steer(runner, {"node": "the_wheel"}, WHO)
	assert_true(bool(r["ok"]), "the line about the wheel was reached: %s" % str(r))
	assert_true((runner.history as Array).has("the_wheel"), "and the runner went there: %s" % str(runner.history))
	assert_false(runner.is_running(), "then it walked away")


func test_it_takes_a_choice_for_what_it_does() -> void:
	var runner := _start(GRAPH)
	var r := DialogueSteer.steer(runner, {"effect": {"set_flag": "steer_asked_nicely"}}, WHO)
	assert_true(bool(r["ok"]), str(r))
	assert_true(GameState.has_flag("steer_asked_nicely"), "the choice was taken and its effect ran")


func test_it_looks_past_a_condition_a_line_on_the_way_meets() -> void:
	var runner := _start(GRAPH)
	var r := DialogueSteer.steer(runner, {"node": "secret"}, WHO)
	assert_true(bool(r["ok"]), "asking nicely first opens the secret: %s" % str(r))
	assert_true((runner.history as Array).has("secret"))


func test_through_a_quests_lines_it_decides_nothing_and_ends_nothing() -> void:
	log_node.register_runtime({"id": QUEST, "name": "Steering", "layer": "side", "stages": [
		{"id": "ask", "journal": "Ask.", "objectives": [{"type": "talk", "target": WHO},
			{"type": "choice", "target": "the_mill", "options": [{"id": "burn", "text": "Burn it"}, {"id": "mend", "text": "Mend it"}]}]}]})
	assert_true(log_node.start(QUEST))
	var runner := _start(QUEST_GRAPH)
	var r := DialogueSteer.steer(runner, {"quest": QUEST, "flags": []}, WHO)
	assert_true(bool(r["ok"]), str(r))
	assert_true(GameState.has_flag("steer_will_help"), "the line about the quest was taken: %s" % str(r["lines"]))
	assert_true(log_node.is_active(QUEST), "nothing ended it")
	assert_eq(log_node.choice_of(QUEST), "", "and nothing decided it")
	assert_false(runner.is_running(), "and it walked away when the quest's lines were done")


func test_it_says_so_when_the_line_is_not_there() -> void:
	var runner := _start(GRAPH)
	var r := DialogueSteer.steer(runner, {"node": "no_such_line"}, WHO)
	assert_false(bool(r["ok"]))
	assert_true(str(r["why"]).contains("no_such_line"), str(r["why"]))
	assert_false(runner.is_running(), "and it walked away")


func test_it_finds_who_can_say_a_thing() -> void:
	# a line in the pack that starts the Naming's successor: the walker begins quests through these
	var lines := DialogueSteer.speakers_of({"quest_choice": [null, null]})
	assert_gt(lines.size(), 10, "the pack's decisions have lines that put them")
	for l in lines:
		assert_true(ContentDB.has(str(l["npc"])), "each belongs to somebody in the pack: %s" % str(l))
