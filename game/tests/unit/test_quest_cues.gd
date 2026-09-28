extends TestCase
## Quest-marked dialogue and quest business over heads (triage 50). The user: "it's not obvious what
## dialog options relate to/progress quests (with distinction between turning in main/side quest,
## accepting a quest, etc)". An answer is marked by what it does, read from its effects and the lines
## it leads to (QuestCues.for_choice); a person by what they are to your quests (QuestCues.state_now).
## And (fourth playtest) the journal says only what has been reached, and a stage moving on says why.

const OTHER := "core:npc/tam_hobb"
const SIDE := "core:quest/_cue_side"
const MAIN := "core:quest/_cue_main"

var log_node: Node
## The fixtures' giver: somebody with no quest business of their own in the pack on a fresh log.
var giver_id := ""
var _nodes: Array[Node] = []


func before_each() -> void:
	log_node = Social.quests
	log_node.reset_for_new_game()
	QuestCues.touch()
	if giver_id == "":
		var ids: Array[String] = []
		for def in ContentDB.all("npc"):
			ids.append(str(def["id"]))
		ids.sort()
		for id in ids:
			if id != OTHER and QuestCues.state_now(id, log_node, Social.ctx).is_empty():
				giver_id = id
				break
	log_node.call("register_runtime", _fixture(SIDE, "side", giver_id))
	log_node.call("register_runtime", _fixture(MAIN, "main", giver_id))


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	if Social.dialogue != null and bool(Social.dialogue.call("is_running")):
		Social.dialogue.call("stop")
	log_node.reset_for_new_game()
	QuestCues.touch()


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Two stages: speak to Tam (his line `tam_line`) and go somewhere, then speak to the giver on
## `report` to hand it in.
static func _fixture(id: String, layer: String, giver: String) -> Dictionary:
	return {"id": id, "name": "Fixture " + layer.capitalize(), "layer": layer, "giver": giver,
		"stages": [
			{"id": "first", "journal": "Tam knows where the pens are. Ask him first.\nA second line.",
				"objectives": [{"type": "talk", "target": OTHER, "topic": "tam_line"},
					{"type": "reach", "target": "core:place/wardens_rest", "after": 0}]},
			{"id": "last", "journal": "Back to the Sergeant with it.",
				"objectives": [{"type": "talk", "target": giver, "topic": "report"}]}]}


func _nodes_of(def: Dictionary) -> Callable:
	return func(id: String) -> Dictionary: return (def["nodes"] as Dictionary).get(id, {})


func _cue(choice: Dictionary, npc: String, nodes: Dictionary = {}) -> Dictionary:
	return QuestCues.for_choice(choice, npc, _nodes_of({"nodes": nodes}),
			func(c: Variant) -> bool: return Conditions.all_of(c, Social.ctx), log_node)


# --- answers ----------------------------------------------------------------------------------------

func test_an_answer_that_takes_a_quest_is_a_new_quest_of_its_tier() -> void:
	var side := _cue({"text": "I'll do it.", "effects": [{"start_quest": SIDE}]}, giver_id)
	assert_eq(str(side["kind"]), "start")
	assert_eq(str(side["tag"]), "New quest")
	assert_eq(str(side["tier"]), "side")
	assert_eq(str(side["name"]), "Fixture Side")
	# the effect on the line after the answer counts as the answer's
	var main := _cue({"text": "Tell me.", "next": "offer"}, giver_id, {"offer": {"text": "Then go.", "effects": [{"start_quest": MAIN}]}})
	assert_eq(str(main["kind"]), "start")
	assert_eq(str(main["tier"]), "main", "main and side told apart")
	log_node.call("start", SIDE)
	assert_true(_cue({"effects": [{"start_quest": SIDE}]}, giver_id).is_empty(), "a quest already taken is not new")


func test_the_first_lessons_are_their_own_tier() -> void:
	var first := ""
	for style in StyleDef.all_styles():
		first = str(style.get("tutorial", ""))
		break
	if first == "":
		return
	assert_eq(QuestCues.tier_of(first), "intro", "a style's tutorial")
	assert_eq(QuestCues.tier_of("core:quest/the_naming"), "main")


func test_a_line_a_talk_waits_for_advances_and_the_last_one_turns_in() -> void:
	log_node.call("start", SIDE)
	var ask := {"text": "Where are the pens?", "next": "tam_line"}
	var nodes := {"tam_line": {"text": "Over the hill.", "next": "hub"}, "hub": {"choices": [{"text": "Bye"}]},
			"report": {"text": "Good."}}
	var a := _cue(ask, OTHER, nodes)
	assert_eq(str(a["kind"]), "advance", "Tam's line closes a step, and more is asked after it")
	assert_eq(str(a["tag"]), "Quest")
	assert_true(_cue(ask, giver_id, nodes).is_empty(), "the same line said by somebody else closes nothing")
	log_node.call("set_stage", SIDE, "last")
	var t := _cue({"text": "It's done.", "next": "report"}, giver_id, nodes)
	assert_eq(str(t["kind"]), "turn_in", "the last thing the quest asks")
	assert_eq(str(t["tag"]), "Turn in")
	var c := _cue({"text": "Take it.", "effects": [{"complete_quest": SIDE}]}, giver_id)
	assert_eq(str(c["kind"]), "turn_in", "complete_quest is a hand-in")


func test_a_stage_moved_on_is_an_advance_and_a_question_about_a_quest_is_about_it() -> void:
	log_node.call("start", MAIN)
	var s := _cue({"text": "Go on.", "effects": [{"quest_stage": [MAIN, "last"]}]}, giver_id)
	assert_eq(str(s["kind"]), "advance")
	assert_eq(str(s["tier"]), "main")
	var about := _cue({"text": "What was I doing?", "conditions": [{"quest_at": [MAIN, "first"]}]}, giver_id)
	assert_eq(str(about["kind"]), "about")
	assert_eq(str(about["tag"]), "", "no tag: a dim mark only")
	assert_true(_cue({"text": "Nice weather."}, giver_id).is_empty(), "small talk is left alone")


func test_the_runner_hands_the_page_its_marks_and_the_page_shows_them() -> void:
	log_node.call("start", SIDE)
	log_node.call("set_stage", SIDE, "last")
	var def := {"id": "core:dialogue/_cues", "start": "hub", "nodes": {
		"hub": {"speaker": "npc", "text": "Well?", "no_talk": true, "no_trade": true, "choices": [
			{"text": "It's done.", "next": "report"},
			{"text": "Anything else?", "effects": [{"start_quest": MAIN}], "next": "hub"},
			{"text": "Goodbye.", "next": "end"}]},
		"report": {"speaker": "npc", "text": "Good."}}}
	var page: Control = (load(UI.DIALOGUE_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(page)
	_nodes.append(page)
	page.call("bind_runner", Social.dialogue)
	var got: Array = []
	var grab := func(_s: String, _t: String, choices: Array) -> void: got.assign(choices)
	Social.dialogue.line_shown.connect(grab)
	Social.dialogue.call("start_def", def, giver_id)
	Social.dialogue.line_shown.disconnect(grab)
	var by_text := {}
	for c in got:
		by_text[str((c as Dictionary)["text"])] = c
	assert_eq(str((by_text["It's done."] as Dictionary).get("quest", {}).get("kind", "")), "turn_in")
	assert_eq(str((by_text["Anything else?"] as Dictionary).get("quest", {}).get("kind", "")), "start")
	assert_false((by_text["Goodbye."] as Dictionary).has("quest"), "goodbye is not a quest")
	page.call("_finish_typing")
	var marks: Dictionary = page.call("quest_marks")
	var done_row: Dictionary = (marks["answers"] as Array).filter(func(a: Dictionary) -> bool: return str(a["text"]).ends_with("It's done."))[0]
	var more_row: Dictionary = (marks["answers"] as Array).filter(func(a: Dictionary) -> bool: return str(a["text"]).ends_with("Anything else?"))[0]
	var bye_row: Dictionary = (marks["answers"] as Array).filter(func(a: Dictionary) -> bool: return str(a["text"]).ends_with("Goodbye."))[0]
	assert_true(str(done_row["text"]).contains("[Turn in]"), str(done_row["text"]))
	assert_eq(str(done_row["tier"]), "side")
	assert_true(str(more_row["text"]).contains("[New quest]"), str(more_row["text"]))
	assert_eq(str(more_row["tier"]), "main")
	assert_false(str(bye_row["text"]).contains("["), "goodbye unmarked")
	assert_true(str(marks["plate"]).contains("Turn in"), "the nameplate says they have a quest to hand in: %s" % marks["plate"])


# --- people ------------------------------------------------------------------------------------------

func test_a_person_s_mark_follows_their_quest_business() -> void:
	# somebody with work to give: whoever the pack's givers are, on a fresh log
	var giver := ""
	var offered := ""
	for def in ContentDB.all("npc"):
		var offers: Array = log_node.call("giver_offers", str(def["id"]))
		if not offers.is_empty():
			giver = str(def["id"])
			offered = str((offers[0] as Dictionary)["quest_id"])
			break
	if giver != "":
		var avail := QuestCues.state_now(giver, log_node, Social.ctx)
		assert_eq(str(avail.get("state", "")), "available", "%s has %s to give" % [giver, offered])
		assert_eq(QuestCues.state_glyph("available"), "!")
	log_node.call("start", SIDE)
	assert_eq(str(QuestCues.state_now(OTHER, log_node, Social.ctx).get("state", "")), "advance", "Tam has a step of it")
	assert_eq(str(QuestCues.state_now(giver_id, log_node, Social.ctx).get("state", "")), "in_progress", "the giver, while it is under way")
	log_node.call("set_stage", SIDE, "last")
	var ready := QuestCues.state_now(giver_id, log_node, Social.ctx)
	assert_eq(str(ready.get("state", "")), "turn_in", "and ready to hand in")
	assert_eq(str(ready.get("tier", "")), "side")
	assert_true(QuestCues.state_now(OTHER, log_node, Social.ctx).is_empty(), "Tam has nothing more to do with it")


class _Person extends Node3D:
	var npc_id := ""
	var alive := true
	var hostile := false


func test_the_mark_over_a_head_shows_the_state_in_the_quest_s_colour() -> void:
	var body := _Person.new()
	body.npc_id = giver_id
	_tree().root.add_child(body)
	_nodes.append(body)
	var mark := QuestMark.new()
	body.add_child(mark)
	log_node.call("start", SIDE)
	log_node.call("set_stage", SIDE, "last")
	QuestCues.touch()
	mark.refresh()
	assert_true(mark.visible, "shown")
	assert_eq(mark.text, "?")
	assert_eq(str(mark.shown.get("state", "")), "turn_in")
	assert_true(mark.modulate.is_equal_approx(QuestCues.tier_colour("side")), "in the side quests' colour")
	body.hostile = true
	mark.refresh()
	assert_false(mark.visible, "never over somebody hostile")


# --- the journal and the notice ------------------------------------------------------------------------

func test_the_journal_says_only_what_has_been_reached() -> void:
	log_node.call("start", SIDE)
	var page := preload("res://ui/journal/journal.gd").quest_page(log_node.call("entry", SIDE))
	var words := JSON.stringify(page)
	assert_true(words.contains("Tam knows where the pens are"), "the stage you are at")
	assert_false(words.contains("Back to the Sergeant"), "never a stage not reached")
	var steps := page.filter(func(p: Dictionary) -> bool: return str(p["kind"]) == "step")
	assert_eq(steps.size(), 1, "the step that follows another is kept back until that one is done")
	assert_false(words.contains("Earlier"), "no log before a second stage")
	log_node.call("set_stage", SIDE, "last")
	page = preload("res://ui/journal/journal.gd").quest_page(log_node.call("entry", SIDE))
	assert_eq(str(page[0]["kind"]), "now")
	assert_true(str(page[0]["text"]).contains("Back to the Sergeant"))
	var log_rows := page.filter(func(p: Dictionary) -> bool: return str(p["kind"]) == "log")
	assert_eq(log_rows.size(), 1, "the stage before, as a line of the log")
	assert_eq(str(log_rows[0]["text"]), "Tam knows where the pens are. Ask him first.", "its first line only")
	var tracked: Array = log_node.call("tracked_objectives")
	for row in tracked:
		assert_false(bool((row as Dictionary).get("veiled", false)))


func test_a_stage_moving_on_says_so_and_why() -> void:
	var hud: Control = (load(UI.HUD_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(hud)
	_nodes.append(hud)
	log_node.call("start", SIDE)
	var n: Dictionary = hud.call("quest_notice_shown")
	await _tree().process_frame
	n = hud.call("quest_notice_shown")
	assert_true(str(n.get("head", "")).begins_with("NEW QUEST"), "a quest taken: %s" % str(n))
	log_node.call("set_stage", SIDE, "last")
	await _tree().process_frame
	await _tree().process_frame
	n = hud.call("quest_notice_shown")
	assert_eq(str(n.get("head", "")), "NEW OBJECTIVE  ·  SIDE QUEST")
	assert_eq(str(n.get("why", "")), "Back to the Sergeant with it.", "the stage's first journal line says why")
	assert_true(str(n.get("line", "")).begins_with("Fixture Side: "), str(n.get("line", "")))
	assert_eq(QuestCues.first_line("One.\nTwo."), "One.")
