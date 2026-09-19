extends TestCase
## Every condition in the docs/CONTRACTS.md §7 vocabulary and this stream's extensions, both
## true and false, against fakes.

const QUEST := "core:quest/wardens_roll_of_names"
const WARDENS := "core:faction/wardens"

var ctx: SocialContext
var flags: SocialFakes.Flags
var quests: SocialFakes.Quests
var factions: SocialFakes.Factions
var standing: SocialFakes.Standing
var gossip: SocialFakes.Gossip
var inventory: SocialFakes.FakeInventory
var player: SocialFakes.FakePlayer
var bounty: SocialFakes.Bounty
var clock: SocialFakes.Clock


func before_each() -> void:
	ctx = SocialFakes.context()
	flags = ctx.provider("flags")
	quests = ctx.provider("quests")
	factions = ctx.provider("factions")
	standing = ctx.provider("standing")
	gossip = ctx.provider("gossip")
	inventory = ctx.provider("inventory")
	player = ctx.provider("player")
	bounty = ctx.provider("bounty")
	clock = ctx.provider("clock")


func check(cond: Dictionary) -> bool:
	return Conditions.check(cond, ctx)


# --- flags and counters -------------------------------------------------------------------

func test_flag() -> void:
	assert_false(check({"flag": "met_wren"}))
	flags.set_flag("met_wren")
	assert_true(check({"flag": "met_wren"}))
	flags.set_flag("empty_string", "")
	assert_false(check({"flag": "empty_string"}), "an empty string is not a set flag")


func test_flag_not_and_equals() -> void:
	assert_true(check({"flag_not": "met_wren"}))
	flags.set_flag("met_wren")
	assert_false(check({"flag_not": "met_wren"}))
	flags.set_flag("wardens_roll_ryn", "restored")
	assert_true(check({"flag_equals": ["wardens_roll_ryn", "restored"]}))
	assert_false(check({"flag_equals": ["wardens_roll_ryn", "struck"]}))


func test_counter_min() -> void:
	assert_false(check({"counter_min": ["wolves_killed", 3]}))
	flags.inc("wolves_killed", 3)
	assert_true(check({"counter_min": ["wolves_killed", 3]}))
	assert_false(check({"counter_min": ["wolves_killed", 4]}))


# --- quests ---------------------------------------------------------------------------------

func test_quest_at_by_index_and_by_stage_id() -> void:
	assert_false(check({"quest_at": [QUEST, 2]}), "an unstarted quest is at no stage")
	quests.start(QUEST)
	quests.set_stage(QUEST, 2)
	assert_true(check({"quest_at": [QUEST, 2]}))
	assert_false(check({"quest_at": [QUEST, 1]}))
	quests.set_stage(QUEST, "the_pen")
	assert_true(check({"quest_at": [QUEST, "the_pen"]}))
	assert_false(check({"quest_at": [QUEST, "summons"]}))


func test_quest_state_conditions() -> void:
	assert_false(check({"quest_active": QUEST}))
	assert_true(check({"quest_not_done": QUEST}))
	quests.start(QUEST)
	assert_true(check({"quest_active": QUEST}))
	assert_false(check({"quest_done": QUEST}))
	quests.set_stage(QUEST, 3)
	assert_true(check({"quest_min_stage": [QUEST, 2]}))
	assert_false(check({"quest_min_stage": [QUEST, 4]}))
	quests.complete(QUEST, "restore")
	assert_true(check({"quest_done": QUEST}))
	assert_false(check({"quest_not_done": QUEST}))
	assert_false(check({"quest_active": QUEST}))
	assert_true(check({"quest_outcome": [QUEST, "restore"]}))
	assert_false(check({"quest_outcome": [QUEST, "strike"]}))


# --- factions -------------------------------------------------------------------------------

func test_rep_min_and_max() -> void:
	assert_false(check({"rep_min": [WARDENS, 20]}))
	assert_true(check({"rep_max": [WARDENS, 0]}))
	factions.add_reputation(WARDENS, 25)
	assert_true(check({"rep_min": [WARDENS, 20]}))
	assert_false(check({"rep_max": [WARDENS, 0]}))


func test_faction_rank_min_needs_membership() -> void:
	factions.ranks[WARDENS] = 3
	assert_false(check({"faction_rank_min": [WARDENS, 2]}), "rank without membership does not count")
	factions.join(WARDENS)
	assert_true(check({"faction_rank_min": [WARDENS, 2]}))
	assert_false(check({"faction_rank_min": [WARDENS, 4]}))


func test_member_of() -> void:
	assert_false(check({"member_of": WARDENS}))
	assert_true(check({"not_member_of": WARDENS}))
	factions.join(WARDENS)
	assert_true(check({"member_of": WARDENS}))
	assert_false(check({"not_member_of": WARDENS}))


func test_bounty_min() -> void:
	assert_false(check({"bounty_min": [WARDENS, 50]}))
	bounty.bounties[WARDENS] = 60
	assert_true(check({"bounty_min": [WARDENS, 50]}))
	assert_false(check({"bounty_min": [WARDENS, 61]}))


# --- standing -------------------------------------------------------------------------------

func test_renown_and_morality() -> void:
	assert_false(check({"renown_min": 50}))
	assert_true(check({"renown_max": 0}))
	standing.add_renown(120)
	assert_true(check({"renown_min": 50}))
	assert_false(check({"renown_max": 100}))
	assert_true(check({"morality_min": 0}))
	standing.add_morality(-30)
	assert_false(check({"morality_min": 10}))
	assert_true(check({"morality_min": -30}), "a negative bound tests the Hollow side")
	assert_true(check({"morality_max": -10}))


func test_knows_deed_and_witnessed_and_disposition() -> void:
	assert_false(check({"knows_deed": [ctx.place_id, "murder"]}))
	gossip.add_rumour("core:rumour/murder", ctx.place_id, 1.0, "murder")
	assert_true(check({"knows_deed": [ctx.place_id, "murder"]}))
	assert_true(check({"knows_deed": "murder"}), "the bare form asks about the current place")

	ctx.npc_id = "core:npc/wardens_hesk"
	assert_false(check({"witnessed_crime": true}))
	standing.witnessed[ctx.npc_id] = "steal"
	assert_true(check({"witnessed_crime": true}))

	assert_false(check({"disposition_min": 10}))
	standing.add_disposition(ctx.npc_id, 20)
	assert_true(check({"disposition_min": 10}))
	assert_true(check({"disposition_min": [ctx.npc_id, 20]}))
	assert_false(check({"disposition_min": [ctx.npc_id, 21]}))


# --- player, items, skills ---------------------------------------------------------------------

func test_skill_min() -> void:
	assert_false(check({"skill_min": ["speech", 25]}))
	player.skills["speech"] = 30
	assert_true(check({"skill_min": ["speech", 25]}))
	assert_false(check({"skill_min": ["speech", 31]}))


func test_has_item_and_has_no_item() -> void:
	var bell := "core:item/wardens_hand_bell"
	assert_false(check({"has_item": [bell, 1]}))
	assert_true(check({"has_no_item": [bell, 1]}))
	inventory.add(bell, 1)
	assert_true(check({"has_item": [bell, 1]}))
	assert_true(check({"has_item": bell}), "the bare form means one")
	assert_false(check({"has_item": [bell, 2]}))
	assert_false(check({"has_no_item": [bell, 1]}))


func test_wearing_tag_and_marks() -> void:
	assert_false(check({"wearing_tag": "warden"}))
	inventory.equipped_tags.append("warden")
	assert_true(check({"wearing_tag": "warden"}))
	assert_false(check({"marks_min": 100}))
	inventory.add_marks(140)
	assert_true(check({"marks_min": 100}))


# --- world ----------------------------------------------------------------------------------

func test_discovered_and_books_and_place() -> void:
	assert_false(check({"discovered": "core:place/hollin_barrow"}))
	flags.discover("core:place/hollin_barrow")
	assert_true(check({"discovered": "core:place/hollin_barrow"}))

	assert_false(check({"book_read": "core:book/anything"}))
	flags.mark_book_read("core:book/anything")
	assert_true(check({"book_read": "core:book/anything"}))

	assert_true(check({"in_region": "core:region/hearthvale"}))
	assert_false(check({"in_region": "core:region/cinderlea"}))
	assert_true(check({"at_place": "core:place/merrowby"}))
	assert_false(check({"at_place": "core:place/tollmere"}))

	ctx.npc_id = "core:npc/wardens_dole"
	assert_true(check({"npc_is": "core:npc/wardens_dole"}))
	assert_false(check({"npc_is": "core:npc/wardens_hesk"}))


func test_personality() -> void:
	ctx.npc = {"personality": {"traits": ["gossip", "generous"]}}
	assert_true(check({"personality": "gossip"}))
	assert_false(check({"personality": "cynical"}))
	ctx.npc = {"personality": ["cynical"]}
	assert_true(check({"personality": "cynical"}), "a bare trait list is accepted too")


func test_time_between_wraps_past_midnight() -> void:
	clock.hour_value = 22
	assert_true(check({"time_between": [20, 6]}))
	assert_false(check({"time_between": [6, 20]}))
	clock.hour_value = 3
	assert_true(check({"time_between": [20, 6]}), "the window wraps past midnight")
	clock.hour_value = 12
	assert_false(check({"time_between": [20, 6]}))
	assert_true(check({"time_between": [6, 20]}))
	assert_true(check({"is_night": false}))
	clock.hour_value = 2
	assert_true(check({"is_night": true}))


func test_random_uses_the_context_rng() -> void:
	assert_true(check({"random": 1.0}))
	assert_false(check({"random": 0.0}))
	ctx.rng.seed = 99
	var first: Array[bool] = []
	for i in 12:
		first.append(check({"random": 0.5}))
	ctx.rng.seed = 99
	for i in 12:
		assert_eq(check({"random": 0.5}), first[i], "the same seed gives the same rolls")


# --- logic and lists -----------------------------------------------------------------------------

func test_not_any_all() -> void:
	flags.set_flag("a")
	assert_true(check({"not": {"flag": "b"}}))
	assert_false(check({"not": {"flag": "a"}}))
	assert_true(check({"any": [{"flag": "b"}, {"flag": "a"}]}))
	assert_false(check({"any": [{"flag": "b"}, {"flag": "c"}]}))
	assert_true(check({"all": [{"flag": "a"}, {"renown_max": 0}]}))
	assert_false(check({"all": [{"flag": "a"}, {"flag": "b"}]}))
	assert_true(check({"not": [{"flag": "b"}, {"flag": "c"}]}), "not also accepts a list")


func test_all_of_list_and_empties() -> void:
	assert_true(Conditions.all_of([], ctx), "no conditions means yes")
	assert_true(Conditions.all_of(null, ctx))
	assert_true(Conditions.check({}, ctx))
	flags.set_flag("a")
	assert_true(Conditions.all_of([{"flag": "a"}, {"true": true}], ctx))
	assert_false(Conditions.all_of([{"flag": "a"}, {"false": true}], ctx))


func test_multiple_keys_in_one_object_are_anded() -> void:
	flags.set_flag("a")
	assert_true(check({"flag": "a", "renown_max": 10}))
	assert_false(check({"flag": "a", "renown_min": 10}))


# --- content problems ------------------------------------------------------------------------------

func test_unknown_condition_is_a_content_problem_not_a_crash() -> void:
	assert_false(check({"wibble": 3}))
	assert_eq(ctx.problems.size(), 1)
	assert_true(ctx.problems[0].contains("wibble"))


func test_malformed_arguments_are_reported() -> void:
	assert_false(check({"rep_min": "not-a-pair"}))
	assert_false(Conditions.all_of({"flag": "a"}, ctx) and false)
	assert_gt(ctx.problems.size(), 0)
	assert_false(Conditions.check("a string", ctx))


func test_missing_providers_give_safe_defaults() -> void:
	var bare := SocialContext.new()
	assert_false(Conditions.check({"flag": "anything"}, bare))
	assert_false(Conditions.check({"renown_min": 1}, bare))
	assert_true(Conditions.check({"renown_max": 0}, bare))
	assert_false(Conditions.check({"has_item": ["core:item/wardens_hand_bell", 1]}, bare))
