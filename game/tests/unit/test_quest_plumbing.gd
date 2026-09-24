extends TestCase
## The quest plumbing the quests that follow the map found missing (docs/ATLAS.md §15; PROGRESS,
## "The quests follow the map"):
##
## * a `talk` that waits for its own line (`topic`), where any conversation used to close it;
## * a book read where it lies (`in_place`), where only a copy you carried off could be read;
## * a decision that is a crime (the `bounty` effect), reported by the crime system's own rules;
## * a quest its giver offers counts as one somebody can start;
## * work from somebody who lives in a place, where the Jobs system knew only notice posts and
##   workbenches, and only towns, cities, villages and forts have a post.

## Somebody no pack knows, so no other line of theirs is offered at the hub but the test's own.
const TELLER := "core:npc/test_teller"
const GRAPH := {"id": "core:dialogue/test_teller", "start": "hub", "nodes": {
	"hub": {"speaker": "npc", "text": "Well?", "choices": [
		{"text": "How is the bread?", "next": "bread"},
		{"text": "About the bell.", "next": "the_news"},
		{"text": "Goodbye.", "next": "end"}]},
	"bread": {"speaker": "npc", "text": "Slow.", "next": "hub"},
	"the_news": {"speaker": "npc", "text": "So that is it.", "next": "hub"}}}

## The keeper-roll hangs inside Hound Watch's door: One to Dunn asks you to read it there, and it
## is the board itself that is laid down, not a copy you carry off.
const DUNN := "core:quest/one_to_dunn"
const ROSTER := "core:book/hound_watch_roster"
const HOUND_WATCH := "core:poi/hound_watch"

## Where a crime by decision happens in these tests, and who sees it: the Guild's clerk in Tollmere.
const TOLLMERE := "core:place/tollmere"
const CLERK := "core:npc/orrin_quill"
## Where there is no law: the Briarwold keeps ill-feeling, not a bounty.
const ELDERHOLD := "core:place/elderhold"

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
	var crime := Bounty.instance
	if crime != null and is_instance_valid(crime):
		crime.clear_all()
		crime.pending.clear()
		crime.history.clear()
		crime.known.clear()
	Social.standing.reset_for_new_game()
	var carried := _tree().root.get_node_or_null(JobBoard.CARRIED_HOLDER)
	if carried != null:
		_tree().root.remove_child(carried)
		carried.free()
	Social.bind("bounty", null)
	Social.refresh_providers()
	Social.ctx.npc_id = ""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


# --- a talk that waits for its own line --------------------------------------------------------------

## A quest whose first stage asks you to speak to the teller, about `topic` when it names one.
func _telling(topic: String) -> String:
	var id := "core:quest/test_tell_%s" % (topic if topic != "" else "anything")
	var talk := {"type": "talk", "target": TELLER, "text": "Tell her"}
	if topic != "":
		talk["topic"] = topic
	log_node.register_runtime({"id": id, "name": "Telling", "layer": "side", "stages": [
		{"id": "tell", "journal": "Tell her.", "objectives": [talk]},
		{"id": "told", "journal": "Told.", "objectives": [{"type": "reach", "target": "core:place/merrowby"}]}]})
	assert_true(log_node.start(id), "the test quest starts")
	return id


## Talks to the teller, takes the choice that goes to `next_node` (none: just says goodbye), and
## lets the conversation end.
func _say(next_node: String) -> void:
	var runner: Node = Social.dialogue
	runner.start_def(GRAPH, TELLER)
	if next_node != "":
		for i in runner.current_choices.size():
			if str((runner.current_choices[i] as Dictionary).get("next", "")) == next_node:
				runner.choose(i)
				break
	if runner.is_running():
		runner.stop()


func test_a_talk_with_a_topic_waits_for_its_own_line() -> void:
	var quest := _telling("the_news")
	_say("")
	assert_eq(log_node.stage_id_of(quest), "tell", "a goodbye closed a talk that waits for its line")
	_say("bread")
	assert_eq(log_node.stage_id_of(quest), "tell", "small talk closed a talk that waits for its line")
	_say("the_news")
	assert_eq(log_node.stage_id_of(quest), "told", "the line itself closes the talk")


func test_a_talk_without_a_topic_closes_on_any_conversation() -> void:
	var quest := _telling("")
	_say("")
	assert_eq(log_node.stage_id_of(quest), "told", "a talk with no topic closes when any conversation ends")


## The walk says a topic that names no line is no way to close a talk.
func test_the_walk_reads_a_topic_against_the_persons_dialogue() -> void:
	var npc := "core:npc/maud_brambling"
	var real := {"type": "talk", "target": npc, "topic": "the_hum"}
	var made_up := {"type": "talk", "target": npc, "topic": "no_such_line"}
	var quest := {"id": "core:quest/test_walk_topics", "stages": [{"id": "s", "objectives": [real, made_up]}]}
	var stage: Dictionary = (quest["stages"] as Array)[0]
	assert_true(bool(QuestWalk.verdict(quest, stage, 0)["ok"]), "Maud's line about the bell is somewhere to close it")
	assert_false(bool(QuestWalk.verdict(quest, stage, 1)["ok"]), "a line Maud does not have closes nothing")


## Every talk the map's quests send you on has a line of its own to close on, and it is there.
func test_every_talk_in_the_maps_quests_closes_on_its_own_line() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/core/quests/the_map.json"))
	var talks := 0
	for def_v in parsed:
		for stage_v in (def_v as Dictionary).get("stages", []):
			var objectives: Array = (stage_v as Dictionary).get("objectives", [])
			for i in objectives.size():
				var o: Dictionary = objectives[i]
				if str(o.get("type", "")) != "talk":
					continue
				talks += 1
				assert_ne(str(o.get("topic", "")), "", "%s / %s: the talk with %s closes on any conversation" % [
						(def_v as Dictionary)["id"], (stage_v as Dictionary)["id"], o.get("target", "")])
				var v := QuestWalk.verdict(def_v, stage_v, i)
				assert_true(bool(v["ok"]), "%s: %s" % [(def_v as Dictionary)["id"], v["how"]])
	assert_gt(talks, 10, "the map's talks were read")


# --- a book read where it lies ----------------------------------------------------------------------

func _laid(book: String) -> Dictionary:
	for row in QuestItems.placements():
		if str(row.get("kind", "")) == "book" and str(row.get("book", "")) == book:
			return row
	return {}


func test_a_book_read_in_place_is_laid_where_it_is_read() -> void:
	var row := _laid(ROSTER)
	assert_false(row.is_empty(), "the keeper-roll is laid down")
	assert_eq(str(row.get("where", "")), HOUND_WATCH, "at Hound Watch, where the stage reads it")
	assert_eq(str(row.get("quest_id", "")), DUNN)
	for other in QuestItems.placements():
		assert_ne(str(other.get("item", "")), "core:item/hound_watch_roster", "and no copy of it is put down to carry off")


func test_reading_it_where_it_lies_closes_the_objective() -> void:
	assert_true(log_node.start(DUNN), "One to Dunn starts")
	log_node.set_stage(DUNN, "the_watch")
	var placer := QuestItems.new()
	var board: Node = placer._make(_laid(ROSTER))
	placer.free()
	assert_true(board is Readable and (board as Readable).fixed, "it is a book read where it lies")
	_tree().root.add_child(board)
	var result: Dictionary = (board as Readable).interact(null)
	assert_true(bool(result.get("ok", false)), "it can be read")
	close_screen("book", "reading the keeper-roll opens the reader")
	var closed := false
	for entry in log_node.current_objectives("read_book"):
		if str(entry["quest_id"]) == DUNN:
			closed = bool(entry["done"])
	assert_true(closed, "reading the board where it hangs closes 'read the keeper-roll'")
	_tree().root.remove_child(board)
	board.free()


func test_the_walk_counts_a_book_read_where_it_lies() -> void:
	var def := ContentDB.get_or_empty(DUNN)
	var asked := 0
	for stage_v in def.get("stages", []):
		var objectives: Array = (stage_v as Dictionary).get("objectives", [])
		for i in objectives.size():
			if str((objectives[i] as Dictionary).get("type", "")) == "read_book":
				asked += 1
				var v := QuestWalk.verdict(def, stage_v, i)
				assert_true(bool(v["ok"]) and str(v["how"]).contains("where it lies"), "the walk: %s" % v["how"])
	assert_eq(asked, 1, "One to Dunn reads one book")


# --- a decision that is a crime ------------------------------------------------------------------------

func _crime_service() -> Bounty:
	var crime := Bounty.ensure()
	crime.clear_all()
	crime.pending.clear()
	crime.history.clear()
	Social.bind("bounty", crime)
	return crime


func _key_at(place: String) -> String:
	return Bounty.key_for_region(str(ContentDB.get_or_empty(place).get("region", "")))


## `bounty_min` and the wanted greetings ask the context, and the context asks the crime service by
## a name the service did not have: every one of them read nought.
func test_a_wanted_player_is_wanted_in_conversation_too() -> void:
	var crime := _crime_service()
	var key := _key_at(TOLLMERE)
	crime.add(key, 30)
	assert_eq(Social.ctx.bounty(key), 30, "the context reads the ledger")
	assert_true(Conditions.all_of([{"bounty_min": [key, 25]}], Social.ctx), "and a bounty_min over it holds")


func test_a_decision_can_put_a_price_on_your_head() -> void:
	var crime := _crime_service()
	var key := _key_at(TOLLMERE)
	Effects.apply({"bounty": {"crime": "assault", "at": TOLLMERE, "seen_by": CLERK}}, Social.ctx)
	assert_eq(crime.history.size(), 1, "the crime is on the record")
	assert_eq(str((crime.history[0] as Dictionary)["kind"]), "assault")
	assert_eq(crime.total(key), 0, "the clerk has not reported it yet")
	assert_eq(crime.pending_count(key), 1, "he will")
	crime.process_pending(Bounty.now_hours() + 24.0)
	assert_eq(crime.total(key), Crimes.severity("assault"), "the price the crime system puts on an assault, with the law of the place")
	assert_true(crime.is_known_at(key, TOLLMERE), "and it is known where it was done")


func test_the_person_spoken_to_is_the_witness_unless_the_effect_names_one() -> void:
	var crime := _crime_service()
	var key := _key_at(TOLLMERE)
	Social.ctx.npc_id = CLERK
	Social.ctx.place_id = TOLLMERE
	Effects.apply({"bounty": {"crime": "theft", "value": 80}}, Social.ctx)
	crime.process_pending(Bounty.now_hours() + 24.0)
	assert_eq(crime.total(key), Crimes.severity("theft", 80), "a theft of eighty marks, told to the clerk's face")


func test_nobody_saw_it_so_nobody_reports_it() -> void:
	var crime := _crime_service()
	var key := _key_at(TOLLMERE)
	Social.ctx.npc_id = ""
	Effects.apply({"bounty": {"crime": "theft", "value": 80, "at": TOLLMERE}}, Social.ctx)
	crime.process_pending(Bounty.now_hours() + 24.0)
	assert_eq(crime.history.size(), 1, "it happened")
	assert_eq(crime.total(key), 0, "and nobody saw it, so nobody puts a price on it")


## Where there is no law (the Briarwold), a crime is ill-feeling in the region's name, not a
## bounty any guard will collect, and it wears off.
func test_where_there_is_no_law_it_is_ill_feeling_that_wears_off() -> void:
	var crime := _crime_service()
	var key := _key_at(ELDERHOLD)
	assert_true(Bounty.is_lawless_key(key), "the Briarwold keeps no law")
	Effects.apply({"bounty": {"crime": "assault", "at": ELDERHOLD, "seen_by": "core:npc/wenna_holt"}}, Social.ctx)
	crime.process_pending(Bounty.now_hours() + 24.0)
	var felt := crime.total(key)
	assert_gt(felt, 0, "the Wold remembers it")
	crime.decay_lawless(3)
	assert_eq(crime.total(key), felt - 3 * Bounty.DECAY_PER_DAY, "and forgets it a day at a time")


## Every crime a line or a stage makes of the player names a crime the system knows, somebody who
## can see it, and somewhere it can happen.
func test_every_bounty_in_the_pack_names_a_real_crime() -> void:
	var found: Array = []
	for type in ["dialogue", "quest"]:
		for def in ContentDB.all(type):
			_bounties(def, found)
	for b in found:
		var kind := str(b.get("crime", "")) if typeof(b) == TYPE_DICTIONARY else str(b)
		assert_true(kind in Crimes.KINDS, "a bounty for '%s', which is no crime" % kind)
		if typeof(b) == TYPE_DICTIONARY:
			for key in ["at", "seen_by"]:
				if str((b as Dictionary).get(key, "")) != "":
					assert_true(ContentDB.has(str(b[key])), "a bounty's %s names %s, which is nowhere" % [key, b[key]])


func _bounties(v: Variant, out: Array) -> void:
	if typeof(v) == TYPE_DICTIONARY:
		for k in v:
			if str(k) == "bounty" and typeof(v[k]) in [TYPE_STRING, TYPE_DICTIONARY]:
				out.append(v[k])
			else:
				_bounties(v[k], out)
	elif typeof(v) == TYPE_ARRAY:
		for x in v:
			_bounties(x, out)


# --- a quest its giver offers ---------------------------------------------------------------------------

## A giver offers their quest at their hub when nothing else starts it (QuestLog.giver_offers), so
## a quest with a giver who has lines of their own is one somebody can start.
func test_a_quest_its_giver_offers_can_be_started() -> void:
	var begins: Dictionary = {}
	for b in QuestWalk.beginnings():
		begins[str(b["quest_id"])] = b
	assert_true(bool((begins.get(DUNN, {}) as Dictionary).get("ok", false)), "One to Dunn can be begun")


# --- work from somebody who lives there -----------------------------------------------------------------

## Hazelwick is a hamlet: no notice post, and until now no work but the chopping block.
const HAZELWICK := "core:place/hazelwick"
const AGGIE := "core:npc/aggie_coppice"


func test_a_place_with_no_post_has_its_work_carried_by_its_people() -> void:
	var board := JobBoard.for_place(HAZELWICK)
	assert_true(board != null and board.carried, "Hazelwick's work is carried, not posted")
	assert_eq(board.place_id, HAZELWICK)
	assert_true(JobBoard.for_place(HAZELWICK) == board, "and it is the same work whoever there you ask")
	assert_false(board.offers().is_empty(), "there is work going")
	assert_false(board.is_in_group("interactable"), "and nothing to walk up to in the world")


func test_a_place_with_a_post_offers_the_posts_work() -> void:
	var post := JobBoard.new()
	post.place_id = HAZELWICK
	_tree().root.add_child(post)
	assert_true(JobBoard.for_place(HAZELWICK) == post, "a resident reads you the post that stands there")
	_tree().root.remove_child(post)
	post.free()


func test_asking_a_resident_for_work_opens_their_places_work() -> void:
	var opened: Array = []
	var seen := func(board: Node, _actor: Node) -> void: opened.append(board)
	EventBus.job_board_opened.connect(seen)
	var runner: Node = Social.dialogue
	runner.start(str(ContentDB.get_or_empty(AGGIE).get("dialogue", "")), AGGIE)
	var asked := false
	for guard in 6:
		for i in runner.current_choices.size():
			if str((runner.current_choices[i] as Dictionary).get("next", "")) == "work_going":
				runner.choose(i)
				asked = true
				break
		if asked or not runner.is_running() or not runner.current_choices.is_empty():
			break
		runner.advance()
	EventBus.job_board_opened.disconnect(seen)
	assert_true(asked, "Aggie can be asked for work at her hub")
	assert_eq(opened.size(), 1, "asking opens a board")
	if opened.size() == 1:
		assert_eq(str((opened[0] as JobBoard).place_id), HAZELWICK, "Hazelwick's")
	close_screen("job_board", "the work going opens over the conversation")


## Every resident the map gave a place can be asked what work is going there.
func test_every_resident_of_the_map_offers_work() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/core/npcs/the_map.json"))
	for npc_v in parsed:
		var npc: Dictionary = npc_v
		var dialogue := ContentDB.get_or_empty(str(npc.get("dialogue", "")))
		var node: Dictionary = (dialogue.get("nodes", {}) as Dictionary).get("work_going", {})
		var offers := false
		for e in node.get("effects", []):
			offers = offers or (e as Dictionary).has("offer_work")
		assert_true(offers, "%s has no work to offer" % npc.get("id", ""))

