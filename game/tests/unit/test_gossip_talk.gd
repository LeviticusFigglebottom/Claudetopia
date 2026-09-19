extends TestCase
## The talk: gossip the player can actually hear. Rumour pools existed and warmed and cooled
## and travelled between villages, and nothing in the game ever said one out loud — the only
## readers were the debug console and these tests.

const MERROWBY := "core:place/merrowby"
const WARM := "core:rumour/helped_villager"
const COLD := "core:rumour/seen_to_fall"

var gossip: Node


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	# The live gossip system, reset: it is an autoload's child and owns the signal wiring.
	gossip = Social.gossip
	gossip.reset_for_new_game()


func after_each() -> void:
	gossip.reset_for_new_game()


# --- tone ---------------------------------------------------------------------------------------

func test_a_rumour_carries_its_tone_into_the_pool() -> void:
	gossip.add_rumour(WARM, MERROWBY, 0.8)
	var pool: Array = gossip.pool_of(MERROWBY)
	assert_eq(pool.size(), 1)
	assert_eq(str(pool[0]["tone"]), "warm")


func test_who_likes_you_leads_with_the_kind_story() -> void:
	gossip.add_rumour(WARM, MERROWBY, 0.60)
	gossip.add_rumour(COLD, MERROWBY, 0.62)
	assert_eq(str(gossip.hottest(MERROWBY)["rumour"]), COLD, "with nobody's feelings in it, heat decides")
	assert_eq(str(gossip.hottest(MERROWBY, {}, 1.0)["rumour"]), WARM, "a friend would rather tell the good one")
	assert_eq(str(gossip.hottest(MERROWBY, {}, -1.0)["rumour"]), COLD, "somebody who has taken against you would not")


func test_heat_still_wins_when_the_news_is_big_enough() -> void:
	gossip.add_rumour(WARM, MERROWBY, 0.3)
	gossip.add_rumour(COLD, MERROWBY, 0.95)
	assert_eq(str(gossip.hottest(MERROWBY, {}, 1.0)["rumour"]), COLD, "a friend still tells you the big news")


# --- the conversation -----------------------------------------------------------------------------

func _runner() -> Node:
	var runner: Node = preload("res://systems/dialogue/dialogue_runner.gd").new()
	_tree().root.add_child(runner)
	runner.ctx.set_provider("gossip", gossip)
	runner.ctx.set_provider("flags", GameState)
	runner.ctx.place_id = MERROWBY
	return runner


func test_a_villager_offers_the_talk_and_says_it() -> void:
	gossip.add_rumour(WARM, MERROWBY, 0.9)
	var runner := _runner()
	var def := {"id": "core:dialogue/_test_talk", "speaker_name": "A villager", "start": "hub",
		"nodes": {"hub": {"speaker": "npc", "text": "Aye?", "choices": [{"text": "Nothing.", "next": "bye"}]},
			"bye": {"speaker": "npc", "text": "Mind the road."}}}
	var lines: Array = []
	runner.line_shown.connect(func(speaker: String, text: String, _c: Array) -> void: lines.append([speaker, text]))
	runner.start_def(def, "", MERROWBY)
	var offered := -1
	for i in runner.current_choices.size():
		if str(runner.current_choices[i]["text"]) == runner.TALK_CHOICE:
			offered = i
	assert_true(offered >= 0, "the talk is offered at a hub")
	runner.choose(offered)
	assert_gt(lines.size(), 1)
	var said := str(lines[lines.size() - 1][1])
	assert_true(said.length() > 20, "the villager actually says the rumour")
	assert_eq(str(lines[lines.size() - 1][0]), "A villager", "and the nameplate uses speaker_name")
	assert_true(GameState.has_flag("rumour:" + WARM), "hearing it writes it into the journal")
	runner.advance()
	assert_eq(runner.current_node_id, "hub", "and the conversation comes back to the hub")
	GameState.set_flag("rumour:" + WARM, false)
	runner.stop()
	_tree().root.remove_child(runner)
	runner.free()


func test_a_place_with_nothing_to_say_does_not_offer_the_talk() -> void:
	var runner := _runner()
	var def := {"id": "core:dialogue/_test_quiet", "start": "hub",
		"nodes": {"hub": {"speaker": "npc", "text": "Aye?", "choices": [{"text": "Nothing.", "next": "bye"}]},
			"bye": {"speaker": "npc", "text": "Mind the road."}}}
	runner.start_def(def, "", MERROWBY)
	for c in runner.current_choices:
		assert_true(str(c["text"]) != runner.TALK_CHOICE, "nothing to tell, so nothing offered")
	runner.stop()
	_tree().root.remove_child(runner)
	runner.free()


func test_a_node_may_turn_the_talk_down() -> void:
	gossip.add_rumour(WARM, MERROWBY, 0.9)
	var runner := _runner()
	var def := {"id": "core:dialogue/_test_no_talk", "start": "hub",
		"nodes": {"hub": {"speaker": "npc", "text": "Not now.", "no_talk": true,
			"choices": [{"text": "Right.", "next": "bye"}]},
			"bye": {"speaker": "npc", "text": "Go on."}}}
	runner.start_def(def, "", MERROWBY)
	for c in runner.current_choices:
		assert_true(str(c["text"]) != runner.TALK_CHOICE, "a tense scene is not the moment for village talk")
	runner.stop()
	_tree().root.remove_child(runner)
	runner.free()
