extends TestCase
## Every place the pack names a quest stage, and whether it names the stage its writer meant.
##
## Content names a stage by its id or by its number, and the numbers are counted from one: every
## quest that writes them says so in its own notes. The code counted from nought, so each of the
## pack's forty-eight numbered references landed on the stage after the one written — Wren's
## "There you are. Eyes working?" waited for the fight instead of the waking, "I'm ready for the
## cart" asked for a fifth stage the Naming does not have, and every branch of the six branching
## side quests jumped into the branch beside the one chosen. An integer in range is not evidence
## of anything, so this pins each number the pack uses to the stage id its prose describes.

const QUEST_LOG := preload("res://systems/quests/quest_log.gd")
const NAMING := "core:quest/the_naming"
const WREN := "core:npc/wren_tallow"

## The stage each number in the pack was written to mean, read off the journal, the option and
## the line it gates. A new number in the pack fails `test_every_stage_number_...` until it is
## added here, which is the point: say which stage you mean.
const WRITER_MEANT := {
	"core:quest/the_naming|1": "wake",
	"core:quest/the_naming|2": "ash_wights",
	"core:quest/the_naming|3": "hearthstone",
	"core:quest/the_naming|4": "the_cart",
	"core:quest/the_toll_hums|2": "ask_around",
	"core:quest/the_toll_hums|3": "the_lip",
	"core:quest/the_toll_hums|5": "a_fourth_line",
	"core:quest/louder_than_books|2": "the_spire",
	"core:quest/grist|4": "rest_him",
	"core:quest/grist|5": "bring_the_water",
	"core:quest/grist|6": "tell_osric",
	"core:quest/seventeen_bells|4": "carry_the_bell",
	"core:quest/seventeen_bells|5": "tell_hesta",
	"core:quest/bramble|5": "the_hedge_witch",
	"core:quest/bramble|6": "tell_robin",
	"core:quest/cask_and_press|4": "the_screw",
	"core:quest/cask_and_press|5": "say_it",
	"core:quest/cask_and_press|6": "the_other_side",
	"core:quest/last_name|5": "say_it",
	"core:quest/last_name|6": "strike_it",
	"core:quest/last_name|7": "let_go",
	"core:quest/last_name|8": "the_morning",
	"core:quest/a_verse_about_you|3": "the_road",
	"core:quest/a_verse_about_you|4": "the_loaves",
	"core:quest/a_verse_about_you|5": "the_key",
	"core:quest/a_verse_about_you|6": "the_performance",
}

## Every option of every branching side quest, and the stages its journal says it walks through
## before the quest is done. Read off the option text and the branch stages' journals.
const BRANCHES := {
	"core:quest/grist": {"at": "what_to_do", "paths": {
		"rest": ["rest_him", "tell_osric"],
		"water": ["bring_the_water", "tell_osric"],
		"leave": ["tell_osric"]}},
	"core:quest/seventeen_bells": {"at": "what_now", "paths": {
		"keep": ["tell_hesta"],
		"give": ["carry_the_bell", "tell_hesta"],
		"bury": ["tell_hesta"]}},
	"core:quest/bramble": {"at": "the_dog", "paths": {
		"home": ["tell_robin"],
		"nell": ["the_hedge_witch", "tell_robin"],
		"end": ["tell_robin"]}},
	"core:quest/cask_and_press": {"at": "the_long_table_question", "paths": {
		"sabotage": ["the_screw", "the_other_side"],
		"ale": ["say_it", "the_other_side"],
		"cider": ["say_it", "the_other_side"]}},
	"core:quest/last_name": {"at": "what_to_do", "paths": {
		"tell": ["say_it", "the_morning"],
		"strike": ["strike_it", "the_morning"],
		"let_go": ["let_go", "the_morning"]}},
	"core:quest/a_verse_about_you": {"at": "what_it_hangs_on", "paths": {
		"brave": ["the_road", "the_performance"],
		"kind": ["the_loaves", "the_performance"],
		"terrible": ["the_key", "the_performance"]}},
}

const STAGE_KEYS := ["quest_at", "quest_stage", "quest_min_stage", "quest_min"]

var log_node: Node
var bag: SocialFakes.FakeInventory


func before_each() -> void:
	log_node = Social.quests
	log_node.reset_for_new_game()
	Social.standing.reset_for_new_game()
	Social.factions.reset_for_new_game()
	bag = SocialFakes.FakeInventory.new()
	Social.bind("inventory", bag)


func after_each() -> void:
	log_node.reset_for_new_game()
	Social.standing.reset_for_new_game()
	Social.factions.reset_for_new_game()
	Social.bind("inventory", null)
	Social.refresh_providers()


# --- the walk -------------------------------------------------------------------------------------

## [{source, key, quest, stage}] for every stage reference in every definition of every type.
func _every_reference() -> Array:
	var out: Array = []
	for type in Schemas.REQUIRED:
		for def in ContentDB.all(str(type)):
			_walk(def, str((def as Dictionary).get("id", "?")), out)
	return out


func _walk(v: Variant, source: String, out: Array) -> void:
	if typeof(v) == TYPE_DICTIONARY:
		for key in (v as Dictionary):
			var value: Variant = (v as Dictionary)[key]
			if STAGE_KEYS.has(str(key)) and typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
				out.append({"source": source, "key": str(key), "quest": str(value[0]), "stage": value[1]})
			_walk(value, source, out)
	elif typeof(v) == TYPE_ARRAY:
		for x in v:
			_walk(x, source, out)


func test_the_walk_finds_the_references_it_is_about() -> void:
	var refs := _every_reference()
	var numbered := refs.filter(func(r: Dictionary) -> bool: return typeof(r["stage"]) != TYPE_STRING)
	assert_gt(refs.size(), 120, "the pack names a stage over a hundred times; the walk found %d" % refs.size())
	assert_gt(numbered.size(), 40, "and numbers one some forty times; the walk found %d" % numbered.size())


func test_every_stage_reference_names_a_stage_of_its_quest() -> void:
	var bad: Array[String] = []
	for r in _every_reference():
		var quest := ContentDB.get_or_empty(str(r["quest"]))
		if quest.is_empty():
			bad.append("%s: %s names %s, which is no quest" % [r["source"], r["key"], r["quest"]])
			continue
		var stages: Array = quest.get("stages", [])
		var at: int = QUEST_LOG.stage_index_in(stages, r["stage"])
		if at < 0:
			bad.append("%s: %s [%s, %s] names no stage of it" % [r["source"], r["key"], r["quest"], str(r["stage"])])
			continue
		if typeof(r["stage"]) == TYPE_STRING:
			assert_eq(str((stages[at] as Dictionary).get("id", "")), str(r["stage"]),
					"%s: %s names a stage by a string that is not its id" % [r["source"], r["key"]])
	assert_empty(bad, "stage references that name nothing")


func test_every_stage_number_names_the_stage_its_writer_meant() -> void:
	var unexplained: Array[String] = []
	var used: Dictionary = {}
	for r in _every_reference():
		if typeof(r["stage"]) == TYPE_STRING:
			continue
		var key := "%s|%d" % [r["quest"], int(r["stage"])]
		used[key] = true
		if not WRITER_MEANT.has(key):
			unexplained.append("%s: %s [%s, %d]" % [r["source"], r["key"], r["quest"], int(r["stage"])])
			continue
		var stages: Array = ContentDB.get_or_empty(str(r["quest"])).get("stages", [])
		var at: int = QUEST_LOG.stage_index_in(stages, r["stage"])
		var lands := str((stages[at] as Dictionary).get("id", "")) if at >= 0 else "(no stage)"
		assert_eq(lands, str(WRITER_MEANT[key]), "%s: %s [%s, %d] lands on %s; its writer meant %s"
				% [r["source"], r["key"], r["quest"], int(r["stage"]), lands, WRITER_MEANT[key]])
		# a quest that names its stages by number says how it counts
		var notes := str(ContentDB.get_or_empty(str(r["quest"])).get("notes", ""))
		assert_true(notes.contains("1-based"), "%s writes stage numbers and its notes do not say how it counts" % r["quest"])
	assert_empty(unexplained, "stage numbers nobody has said the meaning of (add them to WRITER_MEANT)")
	for key in WRITER_MEANT:
		assert_true(used.has(key), "WRITER_MEANT names %s and nothing in the pack uses it any more" % key)


# --- the live log reads a number the way its writer did --------------------------------------------

func test_a_stage_number_counts_from_one_in_the_live_log() -> void:
	assert_true(log_node.start(NAMING))
	assert_eq(log_node.stage_id_of(NAMING), "wake")
	assert_true(Conditions.check({"quest_at": [NAMING, 1]}, Social.ctx), "the first stage is stage 1")
	assert_false(Conditions.check({"quest_at": [NAMING, 2]}, Social.ctx))
	assert_true(Conditions.check({"quest_at": [NAMING, "wake"]}, Social.ctx))
	log_node.set_stage(NAMING, 2)
	assert_eq(log_node.stage_id_of(NAMING), "ash_wights", "set_stage takes the same number content writes")
	assert_true(Conditions.check({"quest_min_stage": [NAMING, 2]}, Social.ctx))
	assert_true(Conditions.check({"quest_min_stage": [NAMING, "wake"]}, Social.ctx))
	assert_false(Conditions.check({"quest_min_stage": [NAMING, "hearthstone"]}, Social.ctx))
	assert_eq(log_node.stage_index(NAMING, 4), 3)
	assert_eq(log_node.stage_index(NAMING, 5), -1, "the Naming has four stages")
	assert_eq(log_node.stage_index(NAMING, 0), -1, "there is no stage nought")
	assert_eq(log_node.stage_index(NAMING, "the_cart"), 3)


## The line the off-by-one hid: Wren's greeting at the waking was keyed to the second stage.
func test_wren_greets_the_waking_with_the_line_written_for_it() -> void:
	assert_true(log_node.start(NAMING))
	var line := str(Social.greet(WREN))
	assert_true(line.contains("Eyes working"), "at the waking Wren says \"%s\"" % line)
	log_node.set_stage(NAMING, "ash_wights")
	line = str(Social.greet(WREN))
	assert_true(line.contains("Sword up"), "at the ash-wights Wren says \"%s\"" % line)


# --- branches ----------------------------------------------------------------------------------------

## Starts a quest at its choice, takes one option, and then closes whatever each stage asks until
## the quest ends, recording the stages it passes through.
func _walk_branch(quest_id: String, choice_at: String, option: String) -> Array:
	log_node.reset_for_new_game()
	assert_true(log_node.start(quest_id), "%s cannot be started" % quest_id)
	log_node.set_stage(quest_id, choice_at)
	log_node.choose(quest_id, option)
	var visited: Array = []
	var guard := 0
	while log_node.is_active(quest_id) and guard < 16:
		guard += 1
		var sid: String = log_node.stage_id_of(quest_id)
		visited.append(sid)
		var objectives: Array = log_node.stage_def(quest_id, log_node.stage_of(quest_id)).get("objectives", [])
		if objectives.is_empty():
			break
		for i in objectives.size():
			if log_node.stage_id_of(quest_id) != sid or not log_node.is_active(quest_id):
				break
			log_node.complete_objective(quest_id, i)
	return visited


func test_every_branch_lands_where_its_option_says_and_rejoins() -> void:
	for quest_id in BRANCHES:
		var spec: Dictionary = BRANCHES[quest_id]
		for option in (spec["paths"] as Dictionary):
			var visited := _walk_branch(str(quest_id), str(spec["at"]), str(option))
			assert_eq(visited, spec["paths"][option], "%s, choosing '%s', walked %s" % [quest_id, option, str(visited)])
			assert_true(log_node.is_completed(str(quest_id)), "%s, choosing '%s', never finished" % [quest_id, option])


## The fault in `advance()` on its own: a stage whose own on_complete sends the quest elsewhere
## goes there, and is not then walked into the stage after it anyway.
func test_a_stage_that_sends_the_quest_elsewhere_is_obeyed() -> void:
	log_node.register_runtime({
		"id": "core:quest/_test_rejoin", "name": "Rejoin", "layer": "side",
		"stages": [
			{"id": "branch", "journal": "A branch.", "objectives": [{"type": "talk", "target": "core:npc/wardens_hesk"}],
			 "on_complete": [{"quest_stage": ["core:quest/_test_rejoin", "rejoin"]}]},
			{"id": "other_branch", "journal": "The other branch.", "objectives": [{"type": "talk", "target": "core:npc/wardens_dole"}]},
			{"id": "rejoin", "journal": "Back on the road.", "objectives": [{"type": "talk", "target": "core:npc/wardens_ryn"}]},
		]})
	assert_true(log_node.start("core:quest/_test_rejoin"))
	EventBus.dialogue_ended.emit("core:npc/wardens_hesk")
	assert_eq(log_node.stage_id_of("core:quest/_test_rejoin"), "rejoin", "the branch rejoined rather than falling into its neighbour")
	EventBus.dialogue_ended.emit("core:npc/wardens_ryn")
	assert_true(log_node.is_completed("core:quest/_test_rejoin"))
