extends TestCase
## The dialogue runner walking a scripted graph: node chains, node reuse, choice filtering,
## effects, the greeting matrix and gestures.

const QUEST := "core:quest/wardens_roll_of_names"
const WARDENS := "core:faction/wardens"

var runner: Node
var ctx: SocialContext
var shown: Array[Dictionary] = []
var choice_calls: Array = []
var ended_count := 0
var ended_npc := ""


func before_each() -> void:
	ctx = SocialFakes.context()
	ctx.npc_id = "core:npc/wardens_hesk"
	ctx.npc = {"name": "Roll-Keeper Hesk", "personality": {"traits": ["pious", "quiet"]}}
	runner = preload("res://systems/dialogue/dialogue_runner.gd").new()
	runner.ctx = ctx
	Engine.get_main_loop().root.add_child(runner)
	shown = []
	choice_calls = []
	ended_count = 0
	ended_npc = ""
	runner.line_shown.connect(func(speaker: String, text: String, choices: Array) -> void:
		shown.append({"speaker": speaker, "text": text, "choices": choices}))
	runner.choice_needed.connect(func(choices: Array) -> void: choice_calls.append(choices))
	runner.ended.connect(func() -> void: ended_count += 1)


func after_each() -> void:
	if is_instance_valid(runner):
		runner.queue_free()
	Greetings.forget()
	Gestures.clear_memory()


func graph() -> Dictionary:
	return {
		"id": "core:dialogue/_test_graph",
		"start": "open",
		"nodes": {
			"open": {"speaker": "npc", "text": "You are {player}, then.", "next": "hub"},
			"hub": {
				"speaker": "npc",
				"text": "Well?",
				"choices": [
					{"text": "Take the job.", "effects": [{"start_quest": QUEST}, {"set_flag": "took_job"}], "next": "taken"},
					{"text": "Ask about the pay.", "next": "pay", "once": true},
					{"text": "You are a Warden, aren't you?", "conditions": [{"flag": "knows_warden"}], "next": "warden"},
					{"text": "Nothing.", "effects": [{"end": true}]}
				]
			},
			"pay": {"speaker": "npc", "text": "A hundred and forty marks.", "effects": [{"set_flag": "asked_pay"}], "next": "hub"},
			"taken": {"speaker": "npc", "text": "Then go.", "effects": [{"rep": [WARDENS, 5]}, {"end": true}]},
			"warden": {"speaker": "npc", "text": "I keep the Roll.", "next": "hub"},
			"gated": {"speaker": "npc", "text": "unreachable", "conditions": [{"flag": "never"}], "else": "fallback"},
			"fallback": {"speaker": "npc", "text": "Something else, then."}
		}
	}


# --- walking ---------------------------------------------------------------------------------

func test_walks_a_chain_and_substitutes_text() -> void:
	runner.start_def(graph(), "core:npc/wardens_hesk")
	assert_eq(shown.size(), 1)
	assert_eq(shown[0]["speaker"], "Roll-Keeper Hesk")
	assert_eq(shown[0]["text"], "You are Wren, then.", "{player} is filled in")
	assert_empty(shown[0]["choices"], "a plain line offers no choices")
	runner.advance()
	assert_eq(shown.size(), 2)
	assert_eq(shown[1]["text"], "Well?")
	assert_eq(choice_calls.size(), 1, "the hub asks for a choice")


func test_choices_are_filtered_by_conditions() -> void:
	runner.start_def(graph(), "core:npc/wardens_hesk")
	runner.advance()
	var choices: Array = choice_calls[0]
	assert_eq(choices.size(), 3, "the Warden line is hidden without the flag")
	assert_eq(choices[0]["text"], "Take the job.")
	assert_eq(choices[0]["index"], 0)

	ctx.provider("flags").set_flag("knows_warden")
	runner.choose(1)          # ask about the pay
	runner.advance()          # the pay line has a next: back to the hub
	assert_eq(choice_calls.size(), 2)
	var second: Array = choice_calls[1]
	assert_eq(second.size(), 3, "the pay line is spent, the Warden line has opened")
	var texts: Array[String] = []
	for c in second:
		texts.append(str(c["text"]))
	assert_true(texts.has("You are a Warden, aren't you?"))
	assert_false(texts.has("Ask about the pay."), "a once-only choice does not come back")


func test_effects_are_applied_and_the_conversation_ends() -> void:
	runner.start_def(graph(), "core:npc/wardens_hesk")
	runner.advance()
	runner.choose(0)
	var quests: SocialFakes.Quests = ctx.provider("quests")
	var factions: SocialFakes.Factions = ctx.provider("factions")
	assert_true(quests.started.has(QUEST), "the choice's effect started the quest")
	assert_true(ctx.provider("flags").has_flag("took_job"))
	assert_eq(factions.reputation(WARDENS), 5, "the node's effect ran too")
	assert_eq(ended_count, 1, "{end: true} closed the conversation")
	assert_false(runner.is_running())


func test_node_reuse_keeps_history() -> void:
	runner.start_def(graph(), "core:npc/wardens_hesk")
	runner.advance()
	runner.choose(1)          # pay
	runner.advance()          # -> hub
	assert_eq(runner.history, ["open", "hub", "pay", "hub"], "the hub is entered twice")
	assert_true(ctx.provider("flags").has_flag("asked_pay"))


func test_failed_node_conditions_fall_through_to_else() -> void:
	var g := graph()
	g["start"] = "gated"
	runner.start_def(g, "core:npc/wardens_hesk")
	assert_eq(shown.size(), 1)
	assert_eq(shown[0]["text"], "Something else, then.")
	runner.advance()
	assert_eq(ended_count, 1, "a node with no next ends the conversation")


func test_choosing_out_of_range_is_ignored() -> void:
	runner.start_def(graph(), "core:npc/wardens_hesk")
	runner.advance()
	runner.choose(99)
	assert_true(runner.is_running())
	assert_eq(ended_count, 0)


func test_dialogue_ended_signal_fires_for_the_quest_log() -> void:
	var cb := func(npc_id: String) -> void: ended_npc = npc_id
	EventBus.dialogue_ended.connect(cb)
	runner.start_def(graph(), "core:npc/wardens_hesk")
	runner.advance()
	runner.choose(choice_calls[0].size() - 1)   # "Nothing.", the last line offered
	EventBus.dialogue_ended.disconnect(cb)
	assert_eq(ended_npc, "core:npc/wardens_hesk")


func test_unknown_dialogue_falls_back_to_a_greeting() -> void:
	runner.start("core:dialogue/does_not_exist", "core:npc/wardens_hesk")
	assert_eq(shown.size(), 1, "the villager still says something")
	assert_ne(shown[0]["text"], "")


# --- the authored Wardens graph -----------------------------------------------------------------

func test_the_wardens_quest_dialogue_offers_the_job() -> void:
	runner.start("core:dialogue/wardens_q1_hesk", "core:npc/wardens_hesk")
	runner.advance()                       # greeting -> hub
	var choices: Array = choice_calls[0]
	assert_gt(choices.size(), 0)
	assert_eq(str(choices[0]["text"]), "They said you wanted anyone with legs.")
	runner.choose(0)                       # -> offer
	assert_true(ctx.has_flag("topic/wardens_roll"), "the offer unlocks the Roll topic")
	var offer_choices: Array = choice_calls[1]
	var accept := -1
	for c in offer_choices:
		if str(c["text"]).begins_with("I will bring"):
			accept = int(c["index"])
	assert_gt(accept, -1)
	runner.choose(accept)
	var quests: SocialFakes.Quests = ctx.provider("quests")
	assert_true(quests.started.has(QUEST))
	assert_eq(quests.stage_id_of(QUEST), "the_tumbled_watch")


# --- greetings ---------------------------------------------------------------------------------

func test_greeting_matrix_answers_to_standing() -> void:
	var standing: SocialFakes.Standing = ctx.provider("standing")
	var plain := Greetings.select_row("core:npc/wardens_hesk", ctx)
	assert_false(plain.is_empty())
	standing.add_renown(700)
	var famous := Greetings.select_row("core:npc/wardens_hesk", ctx)
	assert_true(str(famous["id"]).begins_with("renown_named"), "at renown tier 4 the Named lines are used, got %s" % famous["id"])
	standing.renown_value = 0
	standing.add_morality(-90)
	var hollow := Greetings.select_row("core:npc/wardens_hesk", ctx)
	assert_true(str(hollow["id"]).begins_with("hollow"), "a Hollow player is greeted as one, got %s" % hollow["id"])


func test_greeting_uses_personality_and_time() -> void:
	ctx.npc_id = "core:npc/test_gossip"
	ctx.npc = {"name": "A gossip", "personality": {"traits": ["gossip"]}}
	var row := Greetings.select_row("core:npc/test_gossip", ctx)
	assert_eq(str(row["id"]), "trait_gossip")
	var clock: SocialFakes.Clock = ctx.provider("clock")
	clock.hour_value = 23
	var night := Greetings.select_row("core:npc/test_gossip", ctx)
	assert_true(str(night["id"]).begins_with("night"), "late at night the hour wins, got %s" % night["id"])


func test_greeting_reacts_to_a_witness_and_to_gossip() -> void:
	var standing: SocialFakes.Standing = ctx.provider("standing")
	standing.witnessed["core:npc/wardens_hesk"] = "steal"
	var row := Greetings.select_row("core:npc/wardens_hesk", ctx)
	assert_eq(str(row["id"]), "witnessed_crime", "what this one saw outweighs everything else")
	standing.witnessed.clear()
	var gossip: SocialFakes.Gossip = ctx.provider("gossip")
	gossip.add_rumour("core:rumour/boss_slain", ctx.place_id, 1.0, "boss_kill")
	var heard := Greetings.select_row("core:npc/wardens_hesk", ctx)
	assert_eq(str(heard["id"]), "gossip_knows_boss")


func test_greeting_lines_vary() -> void:
	var seen: Dictionary = {}
	for i in 12:
		seen[Greetings.greet("core:npc/wardens_hesk", ctx)] = true
	assert_gt(seen.size(), 1, "the same NPC does not say the same line every time")


func test_every_greeting_row_has_lines_and_known_keys() -> void:
	var known := ["id", "lines", "weight", "traits", "renown_tier", "morality_tier", "faction",
		"faction_rank_min", "rep_min", "rep_max", "bounty_min", "witnessed", "knows_deed", "time",
		"wearing_tag", "disposition_min", "disposition_max", "place", "region", "npc", "flag", "conditions"]
	var rows := Greetings.table_rows()
	assert_gt(rows.size(), 20)
	var lines := 0
	for row in rows:
		assert_gt((row as Dictionary).get("lines", []).size(), 0, "%s has no lines" % row.get("id", "?"))
		lines += (row as Dictionary)["lines"].size()
		for key in (row as Dictionary).keys():
			assert_true(known.has(str(key)), "greeting row %s has unknown key '%s'" % [row.get("id", "?"), key])
	assert_gt(lines, 59, "the matrix ships at least 60 lines")


# --- gestures ------------------------------------------------------------------------------------

func test_gesture_reaction_depends_on_personality() -> void:
	var proud := {"personality": {"traits": ["proud"]}}
	var cynical := {"personality": {"traits": ["cynical"]}}
	var bow := ContentDB.get_or_empty("core:gesture/bow")
	assert_gt(Gestures.reaction_for(bow, proud["personality"]["traits"]), Gestures.reaction_for(bow, cynical["personality"]["traits"]))


func test_gesture_moves_disposition_and_answers() -> void:
	ctx.npc_id = "core:npc/wardens_hesk"
	ctx.npc = {"name": "Hesk", "personality": {"traits": ["pious"]}}
	var result := Gestures.perform("core:gesture/bow", "core:npc/wardens_hesk", ctx)
	assert_gt(int(result["delta"]), 0)
	assert_ne(str(result["line"]), "", "the NPC answers")
	assert_eq(ctx.disposition("core:npc/wardens_hesk"), int(result["delta"]))


func test_rude_gesture_in_company_becomes_a_deed() -> void:
	var standing: SocialFakes.Standing = ctx.provider("standing")
	var result := Gestures.perform("core:gesture/rude", "core:npc/wardens_hesk", ctx, ["core:npc/wardens_dole"])
	assert_true(int(result["delta"]) < 0)
	assert_eq(standing.deeds.size(), 1)
	assert_eq(str(standing.deeds[0]["deed"]), "gesture_offence")
	assert_eq((standing.deeds[0]["witnesses"] as Array).size(), 2, "both the target and the bystander saw it")


func test_repeating_a_gesture_stops_meaning_anything() -> void:
	var first := Gestures.perform("core:gesture/wave", "core:npc/wardens_dole", ctx)
	var second := Gestures.perform("core:gesture/wave", "core:npc/wardens_dole", ctx)
	assert_true(int(second["delta"]) < int(first["delta"]), "the second wave is worth less")


func test_apology_clears_what_this_one_saw() -> void:
	var standing: SocialFakes.Standing = ctx.provider("standing")
	standing.witnessed["core:npc/wardens_hesk"] = "steal"
	ctx.npc = {"personality": {"traits": ["generous"]}}
	Gestures.perform("core:gesture/apologise", "core:npc/wardens_hesk", ctx)
	assert_eq(standing.npc_witnessed("core:npc/wardens_hesk"), "", "a well-taken apology is forgetting")


func test_all_ten_gestures_are_content_complete() -> void:
	var ids := Gestures.all_ids()
	assert_eq(ids.size(), 10)
	for id in ids:
		var def := ContentDB.get_or_empty(id)
		assert_has(def, "animation")
		assert_has(def, "reactions")
		assert_gt((def.get("replies", {}) as Dictionary).get("default", []).size(), 0, "%s has no default reply" % id)
		for reply_gesture in (def.get("reply_gestures", {}) as Dictionary).values():
			if str(reply_gesture) != "":
				assert_true(ContentDB.has(str(reply_gesture)), "%s replies with unknown gesture %s" % [id, reply_gesture])


func test_gesture_during_a_conversation_is_shown_as_a_line() -> void:
	runner.start_def(graph(), "core:npc/wardens_hesk")
	var before := shown.size()
	runner.gesture("core:gesture/wave")
	assert_eq(shown.size(), before + 1, "the answer appears as a spoken line")
