extends TestCase
## The four faction lines, pressed the way a player presses them: every quest is started by
## finding the giver's choice in their real dialogue and choosing it, and every stage after that
## is closed by the event the world would actually raise — a kill, a book opened, a place
## discovered, a rest at a real Hearthstone, a delivery made in a conversation.
##
## Nothing here calls `quests.start()` to begin a quest, because a quest with no button is a
## quest no player can take, and that is the failure this file exists to catch.

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


func killed(enemy_id: String, times: int = 1) -> void:
	for i in times:
		EventBus.entity_killed.emit(null, null, enemy_id)


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
	killed("core:enemy/hedge_wight", 2)
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
	killed("core:boss/barrow_reeve")
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

	arrived("core:place/hollin_barrow")
	assert_eq(stage(READING), "the_privilege", "the stone itself has to be rested at")
	EventBus.hearthstone_rested.emit("hearth_hollin_barrow")
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

	arrived("core:place/undercroft")
	killed("core:enemy/gutter_drake", 3)
	assert_eq(stage(MEASUREMENT), "the_quiet_place", "the figure is taken at the stone, not on the stair")
	EventBus.hearthstone_rested.emit("hearth_undercroft")
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
			for entry in (def.get("rewards", {}) as Dictionary).get("rep", []):
				if typeof(entry) == TYPE_ARRAY and str(entry[0]) == faction:
					paid += int(entry[1])
			for cond in def.get("requires", []):
				if typeof(cond) == TYPE_DICTIONARY and (cond as Dictionary).has("rep_min"):
					var pair: Array = (cond as Dictionary)["rep_min"]
					if str(pair[0]) == faction:
						asked = maxi(asked, int(pair[1]))
		assert_gt(paid, asked, "%s asks for %d reputation and its own line pays %d" % [faction, asked, paid])


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
	for layer in ["faction", "side"]:
		for def in authored_quests(layer):
			var quest := str(def["id"])
			for stage_def in def.get("stages", []):
				for o in (stage_def as Dictionary).get("objectives", []):
					if str((o as Dictionary).get("type", "")) != "choice":
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
