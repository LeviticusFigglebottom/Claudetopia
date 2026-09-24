extends TestCase
## The four faction lines, pressed the way a player presses them: every quest is started by
## finding the giver's choice in their real dialogue and choosing it, and every stage after that
## is closed by the event the world would actually raise — a kill, a book opened, a place
## discovered, a rest at a real Hearthstone, a delivery made in a conversation.
##
## Nothing here calls `quests.start()` to begin a quest, because a quest with no button is a
## quest no player can take, and that is the failure this file exists to catch.
##
## The side quests are here too, for the same reason and against the same rules: the checks at
## the foot of this file are about every authored quest a person hands over, of either layer.

const KILL_AT := preload("res://tests/fixtures/kill_at.gd")
const WARDENS := "core:faction/wardens"
const SAYERS := "core:faction/sayers"
const HANDS := "core:faction/quiet_hands"
const ORDER := "core:faction/tolling_order"

const WARDENS_Q1 := "core:quest/wardens_roll_of_names"
const LANE := "core:quest/the_lane_that_isnt"
const DEEP_LINES := "core:quest/the_deep_lines"
const READING := "core:quest/the_reading"

const LOUDER := "core:quest/louder"
const MEASUREMENT := "core:quest/the_long_measurement"
const COUNCIL := "core:quest/in_council"
const UNSAID := "core:quest/the_unsaid_woman"

const LEDGER := "core:quest/the_unsaid_ledger"
const REPORTED := "core:quest/a_thing_nobody_reported"
const BELL_WALL := "core:quest/against_the_bell"
const EVERY_PRICE := "core:quest/every_price"

const VIGIL := "core:quest/vigil"
const GREYFOLD := "core:quest/forty_one_places"
const CHAPTER_BOOK := "core:quest/the_names_in_the_chapter_book"
const AT_THE_GATE := "core:quest/at_the_gate"

const DAWN_LANTERN := "core:quest/the_lantern_still_lit"
const FAWNING := "core:quest/the_fawning_months"
const FOUR_TWELVE := "core:quest/four_hundred_and_twelve"
const COLD_FIRE := "core:quest/the_cold_fire"
const LAMP := "core:quest/the_lamp_is_dimmer"

var log_node: Node
var ctx: SocialContext
var inventory: SocialFakes.FakeInventory
var player: SocialFakes.FakePlayer
var sayings: SocialFakes.Sayings


func before_each() -> void:
	log_node = Social.quests
	ctx = Social.ctx
	GameState.reset_for_new_game(1)
	log_node.reset_for_new_game()
	Social.standing.reset_for_new_game()
	Social.factions.reset_for_new_game()
	Social.gossip.reset_for_new_game()
	inventory = SocialFakes.FakeInventory.new()
	player = SocialFakes.FakePlayer.new()
	sayings = SocialFakes.Sayings.new()
	Social.bind("inventory", inventory)
	Social.bind("player", player)
	Social.bind("sayings", sayings)


func after_each() -> void:
	if Social.dialogue.is_running():
		Social.dialogue.stop()
	# Opening a book opens the reader, and a full-screen menu pauses the tree, which would be
	# waiting for the next test that needs a physics frame.
	UI.close_all()
	log_node.reset_for_new_game()
	Social.standing.reset_for_new_game()
	Social.factions.reset_for_new_game()
	Social.bind("inventory", null)
	Social.bind("player", null)
	Social.bind("sayings", null)
	Social.refresh_providers()


# --- pressing buttons ----------------------------------------------------------------------------

## Opens a conversation and walks it to the first node that asks something.
func talk_to(npc_id: String) -> Node:
	var runner := Social.talk(npc_id)
	for i in 8:
		if not runner.is_running() or not runner.current_choices.is_empty():
			break
		runner.advance()
	return runner


## Takes the choice whose text begins with `prefix`, and says so if there is no such choice.
## Walks past any plain line first, because a player presses on through those.
func press(runner: Node, prefix: String) -> bool:
	for i in 8:
		if not runner.is_running() or not runner.current_choices.is_empty():
			break
		runner.advance()
	var offered: Array[String] = []
	for i in (runner.current_choices as Array).size():
		var text := str((runner.current_choices[i] as Dictionary).get("text", ""))
		offered.append(text)
		if text.begins_with(prefix):
			runner.choose(i)
			return true
	fail("no choice starting '%s' was offered; got %s" % [prefix, str(offered)])
	return false


## The whole way in: find the giver, press each choice in turn, and leave. A giver who talks a
## job over for three or four exchanges before handing it across is the normal case here, so
## this takes as many presses as the conversation asks for.
func walk_in(npc_id: String, presses: Array) -> void:
	var runner := talk_to(npc_id)
	for prefix in presses:
		if not runner.is_running():
			fail("the conversation closed before '%s' could be pressed" % str(prefix))
			return
		press(runner, str(prefix))
	if runner.is_running():
		runner.stop()


func rep(faction: String, value: int) -> void:
	Social.factions.set_reputation(faction, value)


## An earlier quest of the line, finished, so the gate on the next one is open. It has to be
## started before it can be completed: the log does not complete a quest it has never heard of.
func already_finished(quest_id: String) -> void:
	assert_true(log_node.start(quest_id), "%s would not start, so its gate cannot be opened" % quest_id)
	log_node.complete(quest_id)
	assert_true(log_node.is_completed(quest_id))


## Kills, each a body lying where the stage puts the fight: a kill objective counts only there
## (KillPlaces), so the line is walked the way a player has to walk it.
func killed(enemy_id: String, times: int = 1, where: String = "") -> void:
	KILL_AT.emit(enemy_id, where, times)


func arrived(place_id: String) -> void:
	EventBus.place_discovered.emit(place_id)


func read(book_id: String) -> void:
	EventBus.book_opened.emit(book_id)


func stage(quest_id: String) -> String:
	return log_node.stage_id_of(quest_id)


# --- the Wardens' line ----------------------------------------------------------------------------

## The line's first quest, driven to its end, so the quests after it have their gate open.
func finish_the_roll_of_names(outcome: String = "restore") -> void:
	var runner := talk_to("core:npc/wardens_hesk")
	press(runner, "They said you wanted anyone with legs.")
	press(runner, "I will bring them back.")
	if runner.is_running():
		runner.stop()
	assert_true(log_node.is_active(WARDENS_Q1), "the Roll of Names takes off the giver's button")
	log_node.set_stage(WARDENS_Q1, "the_pen")
	log_node.choose(WARDENS_Q1, outcome)
	assert_true(log_node.is_completed(WARDENS_Q1))


func test_the_lane_that_isnt_from_wrens_own_mouth() -> void:
	finish_the_roll_of_names()
	rep(WARDENS, 30)

	walk_in("core:npc/wren_tallow", ["Harewell.", "I'll walk it."])
	assert_true(log_node.is_active(LANE), "Wren's own choice took the quest")
	assert_eq(stage(LANE), "the_doorstep", "and moved it past the asking")

	# The doorstep is in a box on a shelf, and Hesk hands it over when asked for it.
	var hesk := talk_to("core:npc/wardens_hesk")
	press(hesk, "Wren wants the Harewell doorstep")
	hesk.stop()
	assert_eq(inventory.count("core:item/harewell_doorstep_stone"), 1, "the doorstep came out of the box")
	assert_eq(stage(LANE), "the_stretch", "carrying it closed the stage")

	arrived("core:poi/hedge_shrine_of_ansel")
	assert_eq(stage(LANE), "the_stretch", "the hedges are still being worked")
	killed("core:enemy/hedge_wight", 2, "core:poi/hedge_shrine_of_ansel")
	assert_eq(stage(LANE), "what_a_warden_writes")
	assert_true(ctx.has_flag("walked_the_harewell_down"))

	var wren := talk_to("core:npc/wren_tallow")
	press(wren, "I have been out to Harewell's lane.")
	press(wren, "Stand it in the lane.")
	assert_eq(log_node.outcome_of(LANE), "walked", "the option's own effects ran")
	assert_true(ctx.has_flag("harewell_doorstep_returned"))
	assert_eq(stage(LANE), "what_she_says_after")
	wren.advance()                    # she writes it down, then walks with you
	assert_true(ctx.has_flag("wren_named_the_wights"), "she says the thing she has not written down")
	wren.stop()
	assert_true(log_node.is_completed(LANE))
	assert_true(ctx.has_flag("lane_that_isnt_done"), "the flag the next quest gates on")
	assert_gt(Social.factions.reputation(WARDENS), 30, "the Wardens paid in standing as well as marks")
	assert_gt(inventory.marks(), 0)


func test_the_other_two_endings_of_the_harewell_line() -> void:
	for outcome in ["box", "tamwick"]:
		before_each()
		finish_the_roll_of_names()
		rep(WARDENS, 30)
		# Either answer reaches the same handing-over, which is the point of writing it twice.
		walk_in("core:npc/wren_tallow", ["Harewell.", "You want a witness, not a Warden.", "Then I'll go."])
		assert_true(log_node.is_active(LANE), "%s: the witness answer takes the quest too" % outcome)
		log_node.set_stage(LANE, "what_a_warden_writes")
		var wren := talk_to("core:npc/wren_tallow")
		press(wren, "I have been out to Harewell's lane.")
		press(wren, "Back in the box." if outcome == "box" else "Tamwick keeps it.")
		assert_eq(log_node.outcome_of(LANE), outcome)
		assert_eq(stage(LANE), "what_she_says_after", "every ending walks back to Wren")
		wren.advance()
		wren.stop()
		assert_true(log_node.is_completed(LANE), "%s: and every ending finishes it" % outcome)


## The leaf of the Roll out of the Reeve's bell goes back to the Rest, and the Rest is glad of it.
func test_the_leaf_of_the_roll_goes_back_to_the_rest() -> void:
	inventory.add("core:item/wardens_roll_fragment", 1)
	var before: int = Social.factions.reputation(WARDENS)
	var runner := talk_to("core:npc/wardens_hesk")
	press(runner, "There was a leaf of the Roll")
	assert_eq(inventory.count("core:item/wardens_roll_fragment"), 0, "Hesk keeps the leaf")
	assert_true(GameState.has_flag("gave_mullbourne_leaf"))
	assert_eq(Social.factions.reputation(WARDENS), before + 8, "the Wardens know who brought it")


func test_the_deep_lines_ends_the_barrow_reeves_reading() -> void:
	finish_the_roll_of_names()
	rep(WARDENS, 50)
	already_finished(LANE)
	rep(WARDENS, 50)

	walk_in("core:npc/wardens_hesk", ["Who kept the rolls before the Rest did?", "You want the roll.", "Then I'll go in first"])
	assert_true(log_node.is_active(DEEP_LINES))
	assert_eq(stage(DEEP_LINES), "read_the_orders", "the orders are read before the gate")
	assert_eq(inventory.count("core:item/tome_keepers_bond"), 1, "and the Rest issues the tome")

	read("core:book/saying_keepers_bond")
	assert_eq(stage(DEEP_LINES), "the_bell_cist")
	assert_true(ctx.has_flag("read_the_standing_orders"))

	arrived("core:place/hollin_barrow")
	killed("core:boss/barrow_reeve", 1, "core:interior/hollin_barrow")
	assert_eq(stage(DEEP_LINES), "the_roll_of_the_dead")
	assert_eq(inventory.count("core:item/barrow_roll"), 1, "the roll comes up off the Reeve")

	read("core:book/barrow_roll")
	assert_eq(stage(DEEP_LINES), "a_hundred_and_forty_names")

	var hesk := talk_to("core:npc/wardens_hesk")
	press(hesk, "I have the Barrow Reeve's roll.")
	press(hesk, "All hundred and forty.")
	if hesk.is_running():
		hesk.stop()
	assert_true(log_node.is_completed(DEEP_LINES), "the closing stage is auto and closes the quest")
	assert_eq(log_node.outcome_of(DEEP_LINES), "enter_them")
	assert_true(ctx.has_flag("barrow_names_entered"))
	assert_true(ctx.has_flag("deep_lines_done"), "the flag the last quest gates on")
	assert_gt(Social.standing.morality(), 0, "putting a hundred and forty names back is a Hearth deed")


func test_leaving_the_barrow_names_out_costs_the_hearth() -> void:
	finish_the_roll_of_names()
	rep(WARDENS, 50)
	already_finished(LANE)
	rep(WARDENS, 50)
	walk_in("core:npc/wardens_hesk", ["Who kept the rolls before the Rest did?", "You want me to go down and stop it.", "Then I'll go down and relieve him."])
	log_node.set_stage(DEEP_LINES, "a_hundred_and_forty_names")
	var hesk := talk_to("core:npc/wardens_hesk")
	press(hesk, "I have the Barrow Reeve's roll.")
	press(hesk, "Leave them out.")
	if hesk.is_running():
		hesk.stop()
	assert_eq(log_node.outcome_of(DEEP_LINES), "leave_them")
	assert_true(Social.standing.morality() < 0, "a struck name costs, and so does a name never entered")


func test_the_reading_makes_a_roll_warden_and_names_a_stone() -> void:
	finish_the_roll_of_names()
	rep(WARDENS, 75)
	already_finished(LANE)
	already_finished(DEEP_LINES)
	rep(WARDENS, 75)

	walk_in("core:npc/wardens_hesk", ["Who reads at the turn of the season?", "Give me the book."])
	assert_true(log_node.is_active(READING))
	assert_eq(stage(READING), "you_read")
	assert_eq(inventory.count("core:item/wardens_roll_excerpt"), 1, "the fair copy, so the real book stays in the room")

	read("core:book/wardens_roll_excerpt")
	assert_eq(stage(READING), "you_read", "reading it is half the stage; Dole is the other half")
	var dole := talk_to("core:npc/wardens_dole")
	press(dole, "You were at the back of the yard.")
	dole.stop()
	assert_true(ctx.has_flag("dole_heard_the_reading"))
	assert_eq(stage(READING), "the_privilege")
	assert_true(ctx.has_flag("read_the_roll_aloud"))

	arrived("core:poi/hedge_shrine_of_ansel")
	assert_eq(stage(READING), "the_privilege", "the stone itself has to be rested at")
	EventBus.hearthstone_rested.emit("core:poi/hedge_shrine_of_ansel")
	assert_eq(stage(READING), "the_name_on_the_stone")

	# Ryn's name is only offerable if Ryn was put back on the Roll, which this run did.
	var options: Array[Dictionary] = log_node.open_options(READING)
	var ids: Array[String] = []
	for o in options:
		ids.append(str(o["id"]))
	assert_true(ids.has("ryn"), "a restored name can be said to a stone, got %s" % str(ids))

	var hesk := talk_to("core:npc/wardens_hesk")
	press(hesk, "My hand is on the stone. Hear the name.")
	press(hesk, "Harewell.")
	if hesk.is_running():
		hesk.stop()

	assert_true(log_node.is_completed(READING))
	assert_eq(str(ctx.get_flag("stone_named", "")), "harewell")
	assert_true(ctx.has_flag("roll_warden"), "the title")
	assert_true(ctx.has_flag("wardens_line_done"))
	assert_true(ctx.has_flag("ranked_in_a_faction"), "which the main thread's last choice asks about")
	assert_eq(inventory.count("core:item/roll_wardens_seal"), 1)
	assert_true(sayings.knows_spell("core:spell/call_a_name"), "the last Calling, off the Roll")
	assert_eq(Social.factions.rank_name(WARDENS), "Roll-Warden", "the line ends at the top of the ladder")
	assert_true(Social.gossip.knows_deed("core:place/merrowby", "hearthstone_named")
		or Social.standing.renown() > 0, "naming a stone is a deed people hear about")


func test_a_stone_cannot_take_a_name_the_roll_has_struck() -> void:
	finish_the_roll_of_names("strike")
	rep(WARDENS, 75)
	already_finished(LANE)
	already_finished(DEEP_LINES)
	rep(WARDENS, 75)
	walk_in("core:npc/wardens_hesk", ["Who reads at the turn of the season?", "Give me the book."])
	log_node.set_stage(READING, "the_name_on_the_stone")
	var ids: Array[String] = []
	for o in log_node.open_options(READING):
		ids.append(str(o["id"]))
	assert_false(ids.has("ryn"), "Ryn was struck, so there is no name to say")
	var hesk := talk_to("core:npc/wardens_hesk")
	press(hesk, "My hand is on the stone. Hear the name.")
	var offered: Array[String] = []
	for c in hesk.current_choices:
		offered.append(str((c as Dictionary)["text"]))
	for text in offered:
		assert_false(text.begins_with("Ryn Larkbourne"), "a struck name is not on the button either")
	log_node.choose(READING, "ryn")
	assert_true(log_node.is_active(READING), "and saying it anyway does nothing")
	press(hesk, "Nothing.")
	if hesk.is_running():
		hesk.stop()
	assert_true(log_node.is_completed(READING))
	assert_eq(str(ctx.get_flag("stone_named", "")), "nobody")


# --- the Sayers' Circle ---------------------------------------------------------------------------

## Louder, taken and professed through Sulion's own hall, which is also the only way its last
## stage can be answered at all.
func finish_louder(profession: String = "The Bell.") -> void:
	var runner := talk_to("core:npc/aldith_sulion")
	press(runner, "Can I be taught?")
	if runner.is_running():
		runner.stop()
	assert_true(log_node.is_active(LOUDER), "the Circle takes Listeners off a button")
	log_node.set_stage(LOUDER, "profess")
	var hall := talk_to("core:npc/aldith_sulion")
	press(hall, "I am ready to profess.")
	press(hall, profession)
	if hall.is_running():
		hall.stop()
	assert_true(log_node.is_completed(LOUDER), "professing in the hall finishes Louder")


func test_louder_can_finally_be_professed() -> void:
	finish_louder()
	assert_true(ctx.has_flag("sayer_professed_bell"), "the option's own effects ran")
	assert_true(ctx.has_flag("louder_done"))
	assert_true(ctx.has_flag("ranked_in_a_faction"))
	assert_gt(Social.factions.reputation(SAYERS), 20, "a Speaker is past the first threshold")


func test_the_scraped_name_can_be_professed_only_once_it_is_found() -> void:
	var runner := talk_to("core:npc/aldith_sulion")
	press(runner, "Can I be taught?")
	runner.stop()
	log_node.set_stage(LOUDER, "profess")
	var ids: Array[String] = []
	for o in log_node.open_options(LOUDER):
		ids.append(str(o["id"]))
	assert_false(ids.has("tide"), "a scraped name you have not found is not on the list")
	ctx.set_flag("found_tessane")
	ids.clear()
	for o in log_node.open_options(LOUDER):
		ids.append(str(o["id"]))
	assert_true(ids.has("tide"), "and it is, once it has been found")
	var hall := talk_to("core:npc/aldith_sulion")
	press(hall, "I am ready to profess.")
	press(hall, "The Tide, in Tessane's name.")
	if hall.is_running():
		hall.stop()
	assert_true(ctx.has_flag("sayer_professed_tide"))
	assert_true(log_node.is_completed(LOUDER))


func test_the_long_measurement_is_taken_in_two_rooms() -> void:
	finish_louder()
	rep(SAYERS, 30)

	walk_in("core:npc/ismay_ondrael", ["Who is going to take that measurement for you?", "Why does the room matter?", "Then give me the glass"])
	assert_true(log_node.is_active(MEASUREMENT), "she has been asking for eleven years and now somebody said yes")
	assert_eq(stage(MEASUREMENT), "the_warm_room")
	assert_eq(inventory.count("core:item/ondraels_sand_glass"), 1, "and the glass came off her table")

	arrived("core:place/merrowby")
	EventBus.dialogue_ended.emit("core:npc/tobin_cresswell")
	assert_eq(stage(MEASUREMENT), "the_quiet_place")
	assert_true(ctx.has_flag("measured_in_the_warm"))

	arrived("core:poi/shingle_shrine")
	killed("core:enemy/cutpurse", 3, "core:poi/shingle_shrine")
	assert_eq(stage(MEASUREMENT), "the_quiet_place", "the figure is taken at the stone, not on the road")
	EventBus.hearthstone_rested.emit("core:poi/shingle_shrine")
	assert_eq(stage(MEASUREMENT), "the_figures")
	assert_true(ctx.has_flag("measured_in_the_deep"))
	assert_eq(inventory.count("core:item/ondraels_figures"), 1)

	read("core:book/ondraels_figures")
	EventBus.dialogue_ended.emit("core:npc/ismay_ondrael")
	assert_eq(stage(MEASUREMENT), "whose_name_on_it")

	var her := talk_to("core:npc/ismay_ondrael")
	press(her, "Two figures, in my own hand.")
	press(her, "Both. Yours first")
	if her.is_running():
		her.stop()
	assert_true(log_node.is_completed(MEASUREMENT))
	assert_eq(log_node.outcome_of(MEASUREMENT), "both")
	assert_true(ctx.has_flag("figures_published_as_both"))
	assert_true(ctx.has_flag("long_measurement_done"), "the flag the council gates on")
	assert_true(sayings.knows_spell("core:spell/winters_argument"), "the slow case, for a slow measurement")


func test_in_council_buys_the_hymn_with_the_price_it_was_asked() -> void:
	finish_louder()
	rep(SAYERS, 50)
	already_finished(MEASUREMENT)
	rep(SAYERS, 50)

	walk_in("core:npc/aldith_sulion", ["What would make the Circle sit in council?", "I'll go and ask them."])
	assert_true(log_node.is_active(COUNCIL))
	assert_eq(stage(COUNCIL), "the_round")

	arrived("core:place/isseva")
	var auti := talk_to("core:npc/auti_sa")
	press(auti, "The Circle wants the round. Written.")
	press(auti, "What is the fourth line?")
	auti.stop()
	assert_eq(inventory.count("core:item/the_reed_round"), 1, "she hands it over for the right reason")
	assert_true(ctx.has_flag("auti_gave_the_round"))
	assert_eq(stage(COUNCIL), "read_it")

	read("core:book/the_reed_round")
	assert_eq(stage(COUNCIL), "the_council")

	arrived("core:place/sayers_spire")
	for who in ["core:npc/aldith_sulion", "core:npc/bennick_cresswell", "core:npc/ismay_ondrael"]:
		EventBus.dialogue_ended.emit(who)
	assert_eq(stage(COUNCIL), "the_minutes", "all three have to stay in the room")

	ctx.set_flag("found_tessane")
	var sulion := talk_to("core:npc/aldith_sulion")
	press(sulion, "The minutes. Somebody has to write them.")
	press(sulion, "The flat fourth is Tessane's.")
	if sulion.is_running():
		sulion.stop()
	assert_true(log_node.is_completed(COUNCIL))
	assert_true(ctx.has_flag("minutes_name_tessane"))
	assert_true(ctx.has_flag("in_council_done"))


func test_the_circles_way_of_writing_minutes_costs_the_marsh() -> void:
	finish_louder()
	rep(SAYERS, 50)
	already_finished(MEASUREMENT)
	rep(SAYERS, 50)
	# She has been twice herself and says so, and the offer is still there afterwards.
	walk_in("core:npc/aldith_sulion", ["What would make the Circle sit in council?", "Ask them yourself.",
		"What would make the Circle sit in council?", "I'll go and ask them."])
	log_node.set_stage(COUNCIL, "the_minutes")
	var before: int = Social.factions.reputation("core:faction/reed_council")
	var sulion := talk_to("core:npc/aldith_sulion")
	press(sulion, "The minutes. Somebody has to write them.")
	press(sulion, "A marsh variant, unattributed.")
	if sulion.is_running():
		sulion.stop()
	assert_eq(log_node.outcome_of(COUNCIL), "the_circles_way")
	assert_true(Social.factions.reputation("core:faction/reed_council") < before, "Isseva hears about it")
	assert_true(Social.standing.morality() < 0)


func test_the_unsaid_woman_ends_the_line_on_which_account_is_taught() -> void:
	finish_louder()
	ctx.set_flag("found_tessane")
	rep(SAYERS, 75)
	already_finished(MEASUREMENT)
	already_finished(COUNCIL)
	rep(SAYERS, 75)

	walk_in("core:npc/ismay_ondrael", ["Tessane. Where did she actually go?", "What do you expect me to find?", "I'll go."])
	assert_true(log_node.is_active(UNSAID))
	assert_eq(stage(UNSAID), "the_eleven_days")

	arrived("core:place/isseva")
	var auti := talk_to("core:npc/auti_sa")
	press(auti, "Tell me what Tessane left at this bench.")
	auti.stop()
	assert_true(ctx.has_flag("isseva_told_tessanes_lantern"))
	EventBus.dialogue_ended.emit("core:npc/tallissa_oul")
	assert_eq(stage(UNSAID), "the_lantern")

	var loa := talk_to("core:npc/loa_oul")
	press(loa, "The lantern with the uncut reed.")
	press(loa, "Say it, then.")
	loa.stop()
	assert_true(ctx.has_flag("loa_said_the_name"), "twenty-two years of oil, and now the name out loud")
	assert_eq(inventory.count("core:item/tessanes_lantern"), 1)
	assert_eq(stage(UNSAID), "the_hall")

	arrived("core:place/sayers_spire")
	var sulion := talk_to("core:npc/aldith_sulion")
	press(sulion, "This is Tessane's lantern.")
	sulion.stop()
	assert_true(ctx.has_flag("sulion_took_the_lantern"))
	assert_eq(stage(UNSAID), "which_account", "the delivery was made in the conversation")

	var hall := talk_to("core:npc/aldith_sulion")
	press(hall, "You said the floor was mine.")
	press(hall, "Four accounts.")
	if hall.is_running():
		hall.stop()
	assert_true(log_node.is_completed(UNSAID))
	assert_true(ctx.has_flag("circle_teaches_four"), "the ending WORLD_BIBLE 4.1 sets")
	assert_true(ctx.has_flag("tessane_restored"))
	assert_true(ctx.has_flag("sayers_line_done"))
	assert_gt(Social.standing.morality(), 0, "putting a name back is a Hearth deed")
	assert_true(sayings.knows_spell("core:spell/call_the_hound"))
	assert_eq(Social.factions.rank_name(SAYERS), "Voice of the Circle", "the line ends at the top of the ladder")


func test_the_circle_can_unsay_her_a_second_time() -> void:
	finish_louder()
	ctx.set_flag("found_tessane")
	rep(SAYERS, 75)
	already_finished(MEASUREMENT)
	already_finished(COUNCIL)
	rep(SAYERS, 75)
	walk_in("core:npc/ismay_ondrael", ["Tessane. Where did she actually go?", "Then I'll go and find the rest of them."])
	log_node.set_stage(UNSAID, "which_account")
	var hall := talk_to("core:npc/aldith_sulion")
	press(hall, "You said the floor was mine.")
	press(hall, "Nothing. Blow the lantern out.")
	if hall.is_running():
		hall.stop()
	assert_true(log_node.is_completed(UNSAID))
	assert_true(ctx.has_flag("circle_unsaid_her_again"))
	assert_true(Social.standing.morality() < 0, "doing it twice is worse than doing it once")


# --- the Quiet Hands -------------------------------------------------------------------------------

## The Unsaid Ledger, taken and decided through Half-Ell, whose hall is the only place its last
## stage can be answered.
func finish_the_unsaid_ledger(ending: String = "It goes to the Hands.") -> void:
	var runner := talk_to("core:npc/half_ell")
	press(runner, "Teach me Hush.")
	if runner.is_running():
		runner.stop()
	assert_true(log_node.is_active(LEDGER), "learning the first Hush is taking the work")
	log_node.set_stage(LEDGER, "what_it_costs")
	var step := talk_to("core:npc/half_ell")
	press(step, "I have the day-book.")
	press(step, ending)
	if step.is_running():
		step.stop()
	assert_true(log_node.is_completed(LEDGER), "the day-book's ending finishes the quest")


func test_the_unsaid_ledger_can_finally_be_decided() -> void:
	finish_the_unsaid_ledger()
	assert_true(ctx.has_flag("daybook_to_hands"))
	assert_true(Social.factions.is_member(HANDS), "carrying it down is what makes somebody a Hand")
	assert_eq(inventory.count("core:item/half_ells_thimble"), 1)
	assert_true(ctx.has_flag("ranked_in_a_faction"))


func test_handing_the_day_book_to_quill_shuts_the_line() -> void:
	finish_the_unsaid_ledger("I am taking it to Quill")
	assert_true(ctx.has_flag("daybook_to_quill"))
	assert_false(Social.factions.is_member(HANDS), "the Hands do not keep somebody who sold them")
	assert_true(Social.factions.reputation(HANDS) < 20, "and the rest of the line is shut behind rank")
	assert_false(log_node.start(REPORTED), "which is the consequence, not a missing quest")


func test_a_thing_nobody_reported_goes_and_asks_the_man_on_the_page() -> void:
	finish_the_unsaid_ledger()
	rep(HANDS, 30)

	walk_in("core:npc/half_ell", ["Four marks and forty.", "Why has nobody asked him?", "Then I'll go."])
	assert_true(log_node.is_active(REPORTED))
	assert_eq(stage(REPORTED), "the_fisher")

	arrived("core:place/gullhithe")
	var jory := talk_to("core:npc/jory_wick")
	press(jory, "Forty marks was not for a barrow.")
	press(jory, "Where did the cart come from?")
	jory.stop()
	assert_true(ctx.has_flag("jory_told_what_he_saw"))
	assert_eq(stage(REPORTED), "the_wreck")

	arrived("core:poi/gullhithe_wreck")
	killed("core:enemy/smuggler_sayer", 2, "core:poi/gullhithe_wreck")
	assert_eq(stage(REPORTED), "the_wreck", "the chit is the point, not the sayers")
	inventory.add("core:item/forged_charter_chit", 1)
	assert_eq(stage(REPORTED), "whose_hand")

	var her := talk_to("core:npc/half_ell")
	press(her, "The chit is in Quill's own hand.")
	press(her, "Jory Wick can have it.")
	if her.is_running():
		her.stop()
	assert_true(log_node.is_completed(REPORTED))
	assert_eq(log_node.outcome_of(REPORTED), "to_the_fisher")
	assert_true(ctx.has_flag("chit_to_jory"))
	assert_true(ctx.has_flag("nobody_reported_done"))
	assert_gt(Social.standing.morality(), 0, "giving a man back forty marks is a Hearth deed")

	# And the fisher can be told, which is the only reason the chit was worth anything.
	var again := talk_to("core:npc/jory_wick")
	press(again, "The chit is yours.")
	again.stop()
	assert_true(ctx.has_flag("jory_has_the_chit"))


func test_against_the_bell_finds_what_the_guild_built_against() -> void:
	finish_the_unsaid_ledger()
	rep(HANDS, 50)
	already_finished(REPORTED)
	rep(HANDS, 50)

	walk_in("core:npc/half_ell", ["What is behind the back of the bell hall?", "I'll get the entry off the binder."])
	assert_eq(stage(BELL_WALL), "the_charter_entry")

	arrived("core:place/tollmere")
	var cassa := talk_to("core:npc/cassa_binder")
	press(cassa, "The Guild's entry for the Lantern Row strongroom.")
	press(cassa, "Eleven times and nobody has asked you the question?")
	cassa.stop()
	assert_eq(inventory.count("core:item/charter_strongroom_entry"), 1)
	assert_true(ctx.has_flag("cassa_said_it_is_a_bell"), "the binder says the thing at the foot of her own copy")
	read("core:book/charter_strongroom")
	assert_eq(stage(BELL_WALL), "behind_the_bell")

	arrived("core:place/undercroft")
	killed("core:enemy/gutter_drake", 4, "core:interior/undercroft")
	assert_eq(stage(BELL_WALL), "whose_name")

	var her := talk_to("core:npc/half_ell")
	press(her, "There is a second door in the bell's side.")
	press(her, "I'll say mine.")
	if her.is_running():
		her.stop()
	assert_true(log_node.is_completed(BELL_WALL))
	assert_true(ctx.has_flag("door_heard_your_name"))
	assert_true(ctx.has_flag("against_the_bell_done"))


func test_every_price_ends_the_line_on_who_reads_the_ledger() -> void:
	finish_the_unsaid_ledger()
	rep(HANDS, 75)
	already_finished(REPORTED)
	already_finished(BELL_WALL)
	rep(HANDS, 75)

	walk_in("core:npc/half_ell", ["Then let us go and get the Ledger.", "Why me?", "Then I'll carry it."])
	assert_eq(stage(EVERY_PRICE), "the_strongroom")

	arrived("core:place/undercroft")
	killed("core:enemy/bravo", 2, "core:interior/undercroft")
	inventory.add("core:item/ledger_of_prices", 1)
	assert_eq(stage(EVERY_PRICE), "read_it")
	read("core:book/ledger_of_prices")
	assert_eq(stage(EVERY_PRICE), "who_reads_it")

	var tally_before: int = Social.factions.reputation("core:faction/tallymen")
	var her := talk_to("core:npc/half_ell")
	press(her, "Thirty-one marks in the pound.")
	press(her, "It goes on the charter-board.")
	if her.is_running():
		her.stop()
	assert_true(log_node.is_completed(EVERY_PRICE))
	assert_true(ctx.has_flag("ledger_published"))
	assert_true(Social.factions.reputation("core:faction/tallymen") < tally_before, "the Guild reads it too")
	assert_eq(inventory.count("core:item/unsaid_glove"), 1, "one glove, and they keep the other")
	assert_true(ctx.has_flag("quiet_hands_line_done"))
	assert_eq(Social.factions.rank_name(HANDS), "The Unsaid", "the line ends at the top of the ladder")
	assert_gt(Social.standing.renown(), 40, "nailing that to a board is the loudest thing a thief can do")


func test_selling_the_ledger_back_is_paid_for_and_costs_the_hall() -> void:
	finish_the_unsaid_ledger()
	rep(HANDS, 75)
	already_finished(REPORTED)
	already_finished(BELL_WALL)
	rep(HANDS, 75)
	walk_in("core:npc/half_ell", ["Then let us go and get the Ledger.", "In through the bell's side, then."])
	log_node.set_stage(EVERY_PRICE, "who_reads_it")
	var her := talk_to("core:npc/half_ell")
	press(her, "Thirty-one marks in the pound.")
	press(her, "The Guild buys it back.")
	if her.is_running():
		her.stop()
	assert_eq(log_node.outcome_of(EVERY_PRICE), "sell_it_back")
	assert_gt(inventory.marks(), 600, "six hundred marks and the quest's own purse")
	assert_true(Social.factions.reputation(HANDS) < 75, "and the hall remembers it")
	assert_true(Social.standing.morality() < 0)


# --- the Tolling Order -----------------------------------------------------------------------------

## Vigil, driven through its own people: Cadwen's offer, Aud's walk to the line, and the bell at
## the chapter-house. The walk itself is `Escorts`' (test_escorts.gd walks her down with bodies);
## here it arrives the way Escorts says so, and the line she speaks there is spoken there.
func finish_vigil(bell: String = "Hang it silent.") -> void:
	var cadwen := talk_to("core:npc/cadwen_ash")
	press(cadwen, "I'd stand a night's vigil.")
	if cadwen.is_running():
		cadwen.stop()
	assert_true(log_node.is_active(VIGIL), "the Order takes anyone who will stand a night and count")
	log_node.set_stage(VIGIL, "the_pilgrim")
	ctx.set_flag("cadwen_asked_escort")

	var aud := talk_to("core:npc/aud_fennick")
	press(aud, "Will you let me walk you to the line?")
	aud.stop()
	assert_true(ctx.has_flag("aud_agreed_to_walk"), "she says she will walk")
	assert_eq(stage(VIGIL), "the_pilgrim", "and has not walked yet")
	EventBus.escort_arrived.emit("core:npc/aud_fennick", "core:place/hushline")
	assert_eq(stage(VIGIL), "what_she_left", "arriving at the line closed the escort")

	var at_the_line := talk_to("core:npc/aud_fennick")
	press(at_the_line, "This is the line. I'll stop here.")
	at_the_line.stop()
	assert_true(ctx.has_flag("aud_left_her_bell"), "she leaves the bell at the line")

	# carrying her bell to Cadwen and speaking to her hands it over
	EventBus.dialogue_ended.emit("core:npc/cadwen_ash")
	assert_eq(stage(VIGIL), "what_the_cantor_is", "the bell changed hands when Cadwen was spoken to")
	assert_eq(inventory.count("core:item/pilgrims_bell_aud"), 0, "and it is hers now")

	var chapter := talk_to("core:npc/cadwen_ash")
	press(chapter, "Aud left her bell.")
	press(chapter, bell)
	if chapter.is_running():
		chapter.stop()
	assert_true(log_node.is_completed(VIGIL), "the bell's ending finishes Vigil")


func test_vigil_can_finally_be_walked_and_decided() -> void:
	finish_vigil()
	assert_true(ctx.has_flag("aud_walked_south"), "the flag the rest of the line reads")
	assert_true(ctx.has_flag("aud_bell_hung"))
	assert_true(Social.factions.is_member(ORDER), "standing the watch is joining")
	assert_eq(inventory.count("core:item/vigil_cloak"), 1, "handed over once, not once a stage and once a reward")
	assert_true(sayings.knows_spell("core:spell/mend"), "the Order gives its Mending away")


func test_ringing_auds_bell_out_of_custom_costs_the_chapter_house() -> void:
	finish_vigil("Ring it tonight.")
	assert_true(ctx.has_flag("aud_bell_rung"))
	assert_gt(Social.standing.morality(), 0, "saying her name tonight is the kind thing")


func test_forty_one_places_carries_the_ninth_day_basket() -> void:
	finish_vigil()
	rep(ORDER, 30)

	walk_in("core:npc/cadwen_ash", ["Who carries the ninth-day basket to Greyfold?", "I'll take the basket."])
	assert_true(log_node.is_active(GREYFOLD))
	assert_eq(inventory.count("core:item/ash_cake"), 6, "six cakes, and she will count them")
	assert_eq(stage(GREYFOLD), "the_lane")

	arrived("core:place/greyfold")
	var nan := talk_to("core:npc/nan_greyfold")
	press(nan, "The Order's ninth-day basket.")
	nan.stop()
	assert_true(ctx.has_flag("nan_took_the_basket"))
	assert_eq(stage(GREYFOLD), "the_tables", "the delivery was made in the conversation")

	var tables := talk_to("core:npc/nan_greyfold")
	press(tables, "Say the forty-one for me.")
	tables.stop()
	assert_true(ctx.has_flag("nan_said_the_forty_one"))
	assert_eq(stage(GREYFOLD), "the_tables", "the tables are one half; what comes to them is the other")
	killed("core:enemy/ash_wight", 8, "core:place/greyfold")
	assert_eq(stage(GREYFOLD), "the_forty_second")

	var second := talk_to("core:npc/nan_greyfold")
	press(second, "Whose is the forty-second place?")
	press(second, "Aud Fennick's.")
	if second.is_running():
		second.stop()
	assert_true(log_node.is_completed(GREYFOLD))
	assert_true(ctx.has_flag("forty_second_for_aud"))
	assert_true(ctx.has_flag("forty_one_places_done"))
	assert_gt(Social.standing.morality(), 0)


func test_the_forty_second_place_is_only_auds_if_aud_walked() -> void:
	# Vigil is finished here without ever walking her south, which the log allows and the
	# choice does not: the option's condition reads the flag that walk sets.
	already_finished(VIGIL)
	rep(ORDER, 30)
	walk_in("core:npc/cadwen_ash", ["Who carries the ninth-day basket to Greyfold?", "I'll take the basket. Why never twice in a season?"])
	log_node.set_stage(GREYFOLD, "the_forty_second")
	var ids: Array[String] = []
	for o in log_node.open_options(GREYFOLD):
		ids.append(str(o["id"]))
	assert_false(ids.has("for_aud"), "a pilgrim you never walked is not yours to lay a place for")
	assert_true(ids.has("for_the_cantor"))


func test_the_names_in_the_chapter_book_goes_out_and_looks() -> void:
	finish_vigil()
	rep(ORDER, 50)
	already_finished(GREYFOLD)
	rep(ORDER, 50)

	walk_in("core:npc/toren_ash", ["Eleven names on the standing side.", "Has nobody ever gone?", "Then I'll go."])
	assert_true(log_node.is_active(CHAPTER_BOOK))
	assert_eq(inventory.count("core:item/the_chapter_roll"), 1)
	assert_eq(stage(CHAPTER_BOOK), "read_it")

	read("core:book/chapter_roll")
	assert_eq(stage(CHAPTER_BOOK), "the_walks")
	arrived("core:poi/headless_watch")
	killed("core:enemy/tolling_knight", 3, "core:poi/headless_watch")
	assert_eq(stage(CHAPTER_BOOK), "what_the_book_says")

	var toren := talk_to("core:npc/toren_ash")
	press(toren, "I have been out to the walks.")
	press(toren, "Send the eleven north to the Wardens' Roll.")
	if toren.is_running():
		toren.stop()
	assert_true(log_node.is_completed(CHAPTER_BOOK))
	assert_true(ctx.has_flag("chapter_roll_sent_north"))
	assert_gt(Social.factions.reputation(WARDENS), 0, "the Wardens keep names for a living")
	assert_true(ctx.has_flag("chapter_book_done"))
	assert_eq(inventory.count("core:item/ring_ash_knights_signet"), 1)


func test_at_the_gate_ends_the_line_without_opening_the_seat() -> void:
	finish_vigil()
	rep(ORDER, 75)
	already_finished(GREYFOLD)
	already_finished(CHAPTER_BOOK)
	rep(ORDER, 75)

	walk_in("core:npc/cadwen_ash", ["You have never taken anybody on the walk.", "Why go, if it never opens?", "Then I'll come."])
	assert_eq(stage(AT_THE_GATE), "the_ring")

	arrived("core:place/sunken_choir")
	killed("core:enemy/chorister", 2, "core:place/sunken_choir")
	assert_eq(stage(AT_THE_GATE), "the_walk_to_the_gate")
	assert_true(ctx.has_flag("stood_the_last_watch"))

	arrived("core:place/cantors_seat")
	EventBus.dialogue_ended.emit("core:npc/cadwen_ash")
	assert_eq(stage(AT_THE_GATE), "the_oath")
	assert_true(ctx.has_flag("stood_at_the_seats_gate"))
	assert_false(ctx.has_flag("seat_opened"), "the line ends at the gate; the door is the main thread's")

	var renown_before: int = Social.standing.renown()
	var cadwen := talk_to("core:npc/cadwen_ash")
	press(cadwen, "The door did not open.")
	press(cadwen, "I'll take the grey.")
	if cadwen.is_running():
		cadwen.stop()
	assert_true(log_node.is_completed(AT_THE_GATE))
	assert_true(ctx.has_flag("order_sworn_grey"))
	assert_true(ctx.has_flag("tolling_order_line_done"))
	assert_true(ctx.has_flag("ranked_in_a_faction"))
	assert_true(Social.standing.renown() < renown_before + 25,
		"going quiet costs what being known is worth, which is the whole of the Order's bargain")
	assert_eq(Social.factions.rank_name(ORDER), "Last Warden of the Seat", "the line ends at the top of the ladder")
	assert_true(sayings.knows_spell("core:spell/kind_word"))


func test_keeping_your_name_at_the_gate_is_the_other_answer() -> void:
	finish_vigil()
	rep(ORDER, 75)
	already_finished(GREYFOLD)
	already_finished(CHAPTER_BOOK)
	rep(ORDER, 75)
	walk_in("core:npc/cadwen_ash", ["You have never taken anybody on the walk.", "Then I'll stand the night and walk with you."])
	log_node.set_stage(AT_THE_GATE, "the_oath")
	var renown_before: int = Social.standing.renown()
	var cadwen := talk_to("core:npc/cadwen_ash")
	press(cadwen, "The door did not open.")
	press(cadwen, "I keep my name.")
	if cadwen.is_running():
		cadwen.stop()
	assert_eq(log_node.outcome_of(AT_THE_GATE), "keep_your_name")
	assert_gt(Social.standing.renown(), renown_before, "somebody standing at that door has to be known")


# --- the side quests in the regions that had none ---------------------------------------------------

func test_the_lantern_that_would_not_go_out() -> void:
	ctx.set_flag("isseva_told_still_lit")          # she says it at her own jetty first
	walk_in("core:npc/loa_oul", ["One lantern was still burning at noon", "Whose burial was it?", "Then I'll go and look at it."])
	assert_true(log_node.is_active(DAWN_LANTERN))
	assert_eq(stage(DAWN_LANTERN), "the_channel")

	arrived("core:poi/wisp_hollow")
	killed("core:enemy/wisp", 3, "core:poi/wisp_hollow")
	inventory.add("core:item/salissas_lantern", 1)
	assert_eq(stage(DAWN_LANTERN), "whose_frame")

	var auti := talk_to("core:npc/auti_sa")
	press(auti, "Read this frame for me.")
	auti.stop()
	assert_true(ctx.has_flag("knew_the_frame"), "her grandmother's pegging, left proud")
	assert_eq(stage(DAWN_LANTERN), "what_the_water_would_not_take")

	var loa := talk_to("core:npc/loa_oul")
	press(loa, "It was Sa'lissa's. She was nine.")
	press(loa, "Measure nine spoons.")
	if loa.is_running():
		loa.stop()
	assert_true(log_node.is_completed(DAWN_LANTERN))
	assert_true(ctx.has_flag("salissa_sent_out"))
	assert_gt(Social.standing.morality(), 0, "burying the unburied is a Hearth deed")
	assert_true(ctx.has_flag("lantern_still_lit_done"))


func test_the_fawning_months_and_what_custom_does_to_a_man() -> void:
	ctx.set_flag("hollow_told_the_heart")
	walk_in("core:npc/tansy_thornby", ["Something is snaring in the fawning months.", "Why not pull them and be done?", "Then I'll go up to the ninth."])
	assert_eq(stage(FAWNING), "the_line")

	arrived("core:poi/hunters_stand")
	killed("core:enemy/thornhound", 1, "core:poi/hunters_stand")
	assert_eq(stage(FAWNING), "whose_wire")

	arrived("core:poi/charcoal_camp")
	var fenwick := talk_to("core:npc/fenwick_collier")
	press(fenwick, "Who walks the ridge road at night?")
	fenwick.stop()
	assert_true(ctx.has_flag("knew_whose_wire"), "the burner is awake at two and is never asked")
	assert_eq(stage(FAWNING), "what_custom_does")

	# Saying it to his face is a Speech door, and it is shut on a character who has not got it.
	var ids: Array[String] = []
	for o in log_node.open_options(FAWNING):
		ids.append(str(o["id"]))
	assert_false(ids.has("tell_him"), "walking up the ladder is a Speech check, not a free option")

	var tansy := talk_to("core:npc/tansy_thornby")
	press(tansy, "It is Hob Larkin's line.")
	press(tansy, "Name him to the Hollow.")
	if tansy.is_running():
		tansy.stop()
	assert_true(log_node.is_completed(FAWNING))
	assert_true(ctx.has_flag("larkin_named_to_the_hollow"))
	assert_gt(Social.factions.reputation("core:faction/woodfolk"), 0)


func test_four_hundred_and_twelve_reads_a_mark_off_a_weld() -> void:
	ctx.set_flag("hold_told_the_count")
	walk_in("core:npc/skardd_ko_skarl", ["You found the link, didn't you.", "Where does a link go, if a man takes one?", "Then I'll go and take it off the cord."])
	assert_eq(stage(FOUR_TWELVE), "the_chimes")
	assert_eq(inventory.count("core:item/loosened_link"), 1, "he hands you the lie out of his own bridge")

	arrived("core:poi/clanless_camp")
	killed("core:enemy/clanless_raider", 2, "core:poi/clanless_camp")
	inventory.add("core:item/clan_forged_link", 1)
	assert_eq(stage(FOUR_TWELVE), "whose_mark")

	arrived("core:place/brindlecrag")
	var oskarth := talk_to("core:npc/oskarth_ko_brindle")
	press(oskarth, "Read this mark for me.")
	oskarth.stop()
	assert_true(ctx.has_flag("read_the_clan_mark"))
	assert_eq(stage(FOUR_TWELVE), "the_price")

	var skardd := talk_to("core:npc/skardd_ko_skarl")
	press(skardd, "The mark is a Ghast hand")
	press(skardd, "Report yourself.")
	if skardd.is_running():
		skardd.stop()
	assert_true(log_node.is_completed(FOUR_TWELVE))
	assert_true(ctx.has_flag("skardd_reported_himself"))
	assert_gt(Social.standing.morality(), 0)


func test_the_cold_fire_settles_a_split_tally() -> void:
	ctx.set_flag("ash_told_tallies")
	walk_in("core:npc/wat_thatcher", ["Both halves of a tally cannot be in one hand.", "What are the two piles?", "Then I'll go out to the Cold Fire."])
	assert_eq(stage(COLD_FIRE), "the_camp")
	assert_eq(inventory.count("core:item/wats_tally_stick"), 1)

	arrived("core:poi/cold_fire_camp")
	killed("core:enemy/ash_wight", 6, "core:poi/cold_fire_camp")
	assert_eq(stage(COLD_FIRE), "who_carried_it")

	var deseith := talk_to("core:npc/deseith")
	press(deseith, "You carried half a tally stick back in the dark.")
	deseith.stop()
	assert_true(ctx.has_flag("deseith_carried_the_tally"))
	assert_eq(stage(COLD_FIRE), "the_debt")

	var wat := talk_to("core:npc/wat_thatcher")
	press(wat, "Deseith carried it back.")
	press(wat, "Struck.")
	if wat.is_running():
		wat.stop()
	assert_true(log_node.is_completed(COLD_FIRE))
	assert_true(ctx.has_flag("wats_debt_struck"))
	assert_eq(inventory.count("core:item/ash_cake"), 4)


func test_the_lamp_is_dimmer_and_one_morning_it_was_not() -> void:
	walk_in("core:npc/tamsin_wick", ["The Lamp is dimmer, and you know it.", "Why not write it in the Guild's book?", "Then let me find out what is wrong with it."])
	assert_eq(stage(LAMP), "the_count_of_its_turning")

	arrived("core:place/gullhithe")
	EventBus.dialogue_ended.emit("core:npc/jory_wick")
	EventBus.dialogue_ended.emit("core:npc/elsie_wick")
	assert_eq(stage(LAMP), "the_chipped_face")

	arrived("core:poi/north_cliff_beacon")
	killed("core:enemy/smuggler_sayer", 2, "core:poi/north_cliff_beacon")
	inventory.add("core:item/sul_stone_sliver", 1)
	assert_eq(stage(LAMP), "what_the_keeper_does")

	var tamsin := talk_to("core:npc/tamsin_wick")
	press(tamsin, "Four flakes are gone off the north face.")
	press(tamsin, "Let Elsie back up at dusk.")
	if tamsin.is_running():
		tamsin.stop()
	assert_true(log_node.is_completed(LAMP))
	assert_true(ctx.has_flag("elsie_keeps_the_stair"))
	assert_gt(Social.standing.morality(), 0)
	assert_true(ctx.has_flag("lamp_is_dimmer_done"))


func test_the_six_side_quests_that_shipped_can_now_be_finished() -> void:
	# Each of them stopped dead on its deciding stage, because a `choice` is closed by a
	# dialogue effect and no dialogue had one. This presses each of those buttons.
	var decisions := [
		["core:quest/grist", "core:npc/osric_pennywort", "what_to_do", "I have been down in the wheel-pit.", "Leave him to it.", "leave"],
		["core:quest/seventeen_bells", "core:npc/aud_fennick", "what_now", "Hesta wants to know what to do with your bell.", "It stays up.", "keep"],
		["core:quest/bramble", "core:npc/robin_ashdown", "the_dog", "I have been up to the Hound. I found him.", "He's yours.", "home"],
		["core:quest/cask_and_press", "core:npc/corwen_mullard", "the_long_table_question", "I have tasted both.", "Cider.", "cider"],
		["core:quest/last_name", "core:npc/pellam_ashcombe", "what_to_do", "I have the third name.", "It is yours.", "tell"],
		["core:quest/a_verse_about_you", "core:npc/merrick_gosling", "what_it_hangs_on", "What kind of verse, then?", "Kind.", "kind"],
	]
	for row_v in decisions:
		var row: Array = row_v
		before_each()
		var quest := str(row[0])
		assert_true(log_node.start(quest), "%s will not start" % quest)
		log_node.set_stage(quest, str(row[2]))
		var runner := talk_to(str(row[1]))
		press(runner, str(row[3]))
		press(runner, str(row[4]))
		if runner.is_running():
			runner.stop()
		assert_eq(log_node.outcome_of(quest), str(row[5]), "%s: the decision was not taken" % quest)
		assert_ne(stage(quest), str(row[2]), "%s is still standing on the stage it was asked to decide" % quest)


# --- what every faction line owes a player ---------------------------------------------------------

## Quest ids that some dialogue offers through a `start_quest` effect, with the dialogue that
## offers each: the only way into a quest that does not involve the debug console.
func offered_quests() -> Dictionary:
	var out: Dictionary = {}
	for def in ContentDB.all("dialogue"):
		_collect_start_quests(def, str(def["id"]), out)
	return out


func _collect_start_quests(value: Variant, dialogue_id: String, out: Dictionary) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for key in (value as Dictionary):
				if str(key) == "start_quest":
					var quest := str((value as Dictionary)[key])
					if not out.has(quest):
						out[quest] = []
					if not (out[quest] as Array).has(dialogue_id):
						(out[quest] as Array).append(dialogue_id)
				else:
					_collect_start_quests((value as Dictionary)[key], dialogue_id, out)
		TYPE_ARRAY:
			for v in value:
				_collect_start_quests(v, dialogue_id, out)
		_:
			pass


func authored_quests(layer: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in ContentDB.all("quest"):
		if typeof(def.get("template")) == TYPE_DICTIONARY:
			continue
		if str(def.get("layer", "")) == layer:
			out.append(def)
	return out


func test_every_faction_and_side_quest_is_offered_by_its_own_giver() -> void:
	var offered := offered_quests()
	for layer in ["faction", "side"]:
		for def in authored_quests(layer):
			var quest := str(def["id"])
			var giver := str(def.get("giver", ""))
			assert_ne(giver, "", "%s has no giver, so nobody can hand it over" % quest)
			assert_true(ContentDB.has(giver), "%s is given by somebody who does not exist" % quest)
			assert_true(offered.has(quest), "%s is in no dialogue: there is no way to take it" % quest)
			var their_dialogue := str(ContentDB.get_or_empty(giver).get("dialogue", ""))
			assert_ne(their_dialogue, "", "%s's giver %s has no dialogue" % [quest, giver])
			var where: Array = offered[quest]
			var by_giver := false
			for dialogue_id in where:
				if str(dialogue_id) == their_dialogue:
					by_giver = true
			assert_true(by_giver, "%s is offered in %s, but its giver %s speaks %s" % [quest, str(where), giver, their_dialogue])


func test_every_faction_line_has_three_or_four_quests_and_chains() -> void:
	var by_faction: Dictionary = {}
	for def in authored_quests("faction"):
		var faction := str(def.get("faction", ""))
		assert_ne(faction, "", "%s is a faction quest for no faction" % def["id"])
		assert_true(ContentDB.has(faction), "%s names a faction that does not exist" % def["id"])
		if not by_faction.has(faction):
			by_faction[faction] = []
		(by_faction[faction] as Array).append(def)
	for faction in [WARDENS, SAYERS, HANDS, ORDER]:
		assert_true(by_faction.has(faction), "%s has no questline at all" % faction)
		var line: Array = by_faction[faction]
		assert_gt(line.size(), 2, "%s: DESIGN 5.10 promises three or four quests, found %d" % [faction, line.size()])
		assert_true(line.size() <= 4, "%s: %d quests is more than the line was scoped for" % [faction, line.size()])
		# Exactly one quest opens the line; every other one waits on a named quest being done.
		var openers := 0
		for def in line:
			var waits_for := ""
			for cond in def.get("requires", []):
				if typeof(cond) == TYPE_DICTIONARY and (cond as Dictionary).has("quest_done"):
					waits_for = str((cond as Dictionary)["quest_done"])
			if waits_for == "":
				openers += 1
				continue
			assert_true(ContentDB.has(waits_for), "%s waits on a quest that does not exist" % def["id"])
			assert_eq(str(ContentDB.get_or_empty(waits_for).get("faction", "")), faction,
				"%s waits on %s, which is not this line" % [def["id"], waits_for])
		assert_eq(openers, 1, "%s must have exactly one quest that opens it, found %d" % [faction, openers])


func test_a_faction_line_climbs_its_own_ladder() -> void:
	# A line that never asks for rank is a line you could finish as a stranger. Each of these
	# ends in the faction's top rank, so the reputation its quests pay must reach the threshold.
	for faction in [WARDENS, SAYERS, HANDS, ORDER]:
		var thresholds: Array = ContentDB.get_or_empty(faction).get("rank_thresholds", [])
		assert_gt(thresholds.size(), 4, "%s has no ladder to climb" % faction)
		var paid := 0
		var asked := 0
		for def in authored_quests("faction"):
			if str(def.get("faction", "")) != faction:
				continue
			paid += reputation_paid(def, faction)
			for cond in def.get("requires", []):
				if typeof(cond) == TYPE_DICTIONARY and (cond as Dictionary).has("rep_min"):
					var pair: Array = (cond as Dictionary)["rep_min"]
					if str(pair[0]) == faction:
						asked = maxi(asked, int(pair[1]))
		assert_gt(paid, asked, "%s asks for %d reputation and its own line pays %d" % [faction, asked, paid])


## Every mark of standing with a faction that a quest can pay: its rewards, its stages, and the
## options a player may take. A line pays for its own ladder mostly in the middle.
func reputation_paid(value: Variant, faction: String) -> int:
	var total := 0
	match typeof(value):
		TYPE_DICTIONARY:
			for key in (value as Dictionary):
				var child: Variant = (value as Dictionary)[key]
				if str(key) == "rep" and typeof(child) == TYPE_ARRAY and (child as Array).size() >= 2:
					if str(child[0]) == faction and int(child[1]) > 0:
						total += int(child[1])
				elif str(key) == "rep" and typeof(child) == TYPE_ARRAY:
					for entry in child:
						if typeof(entry) == TYPE_ARRAY and (entry as Array).size() >= 2 and str(entry[0]) == faction:
							total += maxi(0, int(entry[1]))
				else:
					total += reputation_paid(child, faction)
		TYPE_ARRAY:
			for v in value:
				total += reputation_paid(v, faction)
		_:
			pass
	return total


func test_no_quest_in_a_faction_line_prints_an_unfilled_token() -> void:
	for layer in ["faction", "side"]:
		for def in authored_quests(layer):
			var quest := str(def["id"])
			for stage_def in def.get("stages", []):
				var s: Dictionary = stage_def
				var journal := str(s.get("journal", ""))
				assert_gt(journal.length(), 40, "%s.%s journal is a stub" % [quest, s.get("id", "?")])
				assert_false(journal.contains("{"), "%s.%s journal has a token: %s" % [quest, s.get("id", "?"), journal])
				for o in s.get("objectives", []):
					var objective: Dictionary = o
					assert_false(str(objective.get("text", "")).contains("{"),
						"%s.%s objective text has a token" % [quest, s.get("id", "?")])
					var written: String = log_node.objective_text(objective, quest)
					assert_ne(written, "", "%s.%s: an objective with nothing to show" % [quest, s.get("id", "?")])
					assert_false(written.contains("{"), "%s.%s: '%s' still has a token" % [quest, s.get("id", "?"), written])
					assert_false(written.ends_with(" "), "%s.%s: '%s' names nothing" % [quest, s.get("id", "?"), written])
					for option in objective.get("options", []):
						if typeof(option) != TYPE_DICTIONARY:
							continue
						assert_ne(str((option as Dictionary).get("id", "")), "",
							"%s.%s has an option with no id, which cannot be chosen" % [quest, s.get("id", "?")])
						assert_gt(str((option as Dictionary).get("text", "")).length(), 10,
							"%s.%s has an option with nothing written on the button" % [quest, s.get("id", "?")])


func test_every_choice_a_quest_asks_for_has_a_button_in_a_dialogue() -> void:
	# A `choice` objective is closed by `choose()`, which only a dialogue effect calls in play.
	# A quest that asks a question no conversation asks is a quest that stops on that stage.
	var asked: Dictionary = {}
	for dialogue in ContentDB.all("dialogue"):
		_collect_quest_choices(dialogue, asked)
	# A choice put to you by a place rather than a person (`with` names a place: the bell at the
	# Turning Cairn) is asked by the ChoicePoint QuestItems stands there, whose conversation offers
	# every open option of the stage.
	var at_a_place: Dictionary = {}
	for row in QuestItems.placements():
		if str(row.get("kind", "")) == "choice":
			at_a_place["%s|%s" % [row["quest_id"], row["stage_id"]]] = true
	for layer in ["faction", "side"]:
		for def in authored_quests(layer):
			var quest := str(def["id"])
			for stage_def in def.get("stages", []):
				for o in (stage_def as Dictionary).get("objectives", []):
					if str((o as Dictionary).get("type", "")) != "choice":
						continue
					if at_a_place.has("%s|%s" % [quest, str((stage_def as Dictionary).get("id", ""))]):
						continue
					for option in (o as Dictionary).get("options", []):
						var id := str(option) if typeof(option) != TYPE_DICTIONARY else str((option as Dictionary).get("id", ""))
						assert_true(asked.has("%s|%s" % [quest, id]),
							"%s: nothing in any dialogue chooses '%s', so that stage cannot be answered" % [quest, id])


func _collect_quest_choices(value: Variant, out: Dictionary) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for key in (value as Dictionary):
				var child: Variant = (value as Dictionary)[key]
				if str(key) == "quest_choice" and typeof(child) == TYPE_ARRAY and (child as Array).size() >= 2:
					out["%s|%s" % [str(child[0]), str(child[1])]] = true
				else:
					_collect_quest_choices(child, out)
		TYPE_ARRAY:
			for v in value:
				_collect_quest_choices(v, out)
		_:
			pass
