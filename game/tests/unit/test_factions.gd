extends TestCase
## Factions: reputation, ranks from the content's thresholds, joining with rival penalties, the
## law lookup per region, and the save round trip. Runs against the live Social.Factions node.

const WARDENS := "core:faction/wardens"
const QUIET_HANDS := "core:faction/quiet_hands"
const SAYERS := "core:faction/sayers"
const TOLLING := "core:faction/tolling_order"
const TALLYMEN := "core:faction/tallymen"

var factions: Node
var rep_events: Array = []
var rank_events: Array = []


func before_each() -> void:
	factions = Social.factions
	factions.reset_for_new_game()
	rep_events = []
	rank_events = []
	EventBus.faction_reputation_changed.connect(_on_rep)
	EventBus.faction_rank_changed.connect(_on_rank)


func after_each() -> void:
	EventBus.faction_reputation_changed.disconnect(_on_rep)
	EventBus.faction_rank_changed.disconnect(_on_rank)
	factions.reset_for_new_game()


func _on_rep(faction_id: String, value: int, delta: int) -> void:
	rep_events.append({"id": faction_id, "value": value, "delta": delta})


func _on_rank(faction_id: String, rank: int) -> void:
	rank_events.append({"id": faction_id, "rank": rank})


# --- reputation -------------------------------------------------------------------------------

func test_reputation_moves_and_clamps() -> void:
	assert_eq(factions.reputation(WARDENS), 0)
	assert_eq(factions.add_reputation(WARDENS, 30, "helped"), 30)
	assert_eq(rep_events.size(), 1)
	assert_eq(rep_events[0]["delta"], 30)
	factions.add_reputation(WARDENS, 500)
	assert_eq(factions.reputation(WARDENS), 100, "reputation stops at 100")
	factions.add_reputation(WARDENS, -500)
	assert_eq(factions.reputation(WARDENS), -100, "and at -100")


func test_no_event_when_nothing_changes() -> void:
	factions.set_reputation(WARDENS, 100)
	rep_events = []
	factions.add_reputation(WARDENS, 10)
	assert_empty(rep_events, "already at the ceiling")


func test_unknown_faction_is_a_content_problem_not_a_crash() -> void:
	assert_eq(factions.add_reputation("core:faction/nobody", 10), 0)
	assert_empty(rep_events)
	assert_false(factions.join("core:faction/nobody"))


# --- ranks ------------------------------------------------------------------------------------

func test_rank_needs_membership_and_follows_thresholds() -> void:
	factions.set_reputation(WARDENS, 50)
	assert_eq(factions.rank(WARDENS), -1, "an outsider holds no rank")
	assert_eq(factions.rank_name(WARDENS), "")
	assert_true(factions.join(WARDENS))
	# thresholds are [0, 20, 45, 70, 95] -> 50 is the third rank (index 2)
	assert_eq(factions.rank(WARDENS), 2)
	assert_eq(factions.rank_name(WARDENS), "Roll-Keeper")
	assert_eq(factions.next_rank_at(WARDENS), 70)


func test_rank_change_is_announced() -> void:
	factions.join(WARDENS)
	rank_events = []
	factions.add_reputation(WARDENS, 20)
	assert_eq(rank_events.size(), 1)
	assert_eq(rank_events[0]["rank"], 1)
	rank_events = []
	factions.add_reputation(WARDENS, 5)
	assert_empty(rank_events, "still Watch, no announcement")


func test_top_rank_has_no_next() -> void:
	factions.join(WARDENS)
	factions.set_reputation(WARDENS, 100)
	assert_eq(factions.rank(WARDENS), 4)
	assert_eq(factions.rank_name(WARDENS), "Roll-Warden")
	assert_eq(factions.next_rank_at(WARDENS), -1)


# --- membership and rivals ---------------------------------------------------------------------

func test_joining_costs_standing_with_the_rival() -> void:
	factions.set_reputation(QUIET_HANDS, 40)
	assert_true(factions.join(WARDENS))
	assert_eq(factions.reputation(QUIET_HANDS), 40 - factions.RIVAL_JOIN_PENALTY)
	assert_true(factions.is_member(WARDENS))
	assert_false(factions.is_member(QUIET_HANDS))


func test_joining_a_rival_expels_you_from_the_first() -> void:
	factions.join(QUIET_HANDS)
	assert_true(factions.is_member(QUIET_HANDS))
	factions.join(WARDENS)
	assert_false(factions.is_member(QUIET_HANDS), "you cannot be both")
	assert_true(factions.was_expelled(QUIET_HANDS))
	assert_false(factions.join(QUIET_HANDS), "and they remember")
	factions.clear_expulsion(QUIET_HANDS)
	assert_true(factions.join(QUIET_HANDS))


func test_gains_bleed_away_from_the_rival_while_you_are_a_member() -> void:
	factions.join(SAYERS)                      # rival: the Tolling Order
	var before: int = factions.reputation(TOLLING)
	factions.add_reputation(SAYERS, 20, "a lecture attended")
	assert_eq(factions.reputation(TOLLING), before - int(20 * factions.RIVAL_BLEED))


func test_losses_do_not_help_the_rival() -> void:
	factions.join(SAYERS)
	var before: int = factions.reputation(TOLLING)
	factions.add_reputation(SAYERS, -20)
	assert_eq(factions.reputation(TOLLING), before, "falling out with one is not a favour to the other")


func test_unjoinable_factions_refuse() -> void:
	assert_false(factions.is_joinable(TALLYMEN))
	assert_false(factions.join(TALLYMEN))
	assert_eq(factions.rank(TALLYMEN), -1)


# --- law -----------------------------------------------------------------------------------------

func test_law_lookup_by_region() -> void:
	assert_eq(factions.law_faction_for_region("core:region/hearthvale"), WARDENS)
	assert_eq(factions.law_faction_for_region("core:region/brightwater"), TALLYMEN)
	assert_eq(factions.law_faction_for_region("core:region/skerrow"), "core:faction/clan_moot")
	assert_eq(factions.law_faction_for_region("core:region/sedgemire"), "core:faction/reed_council")


func test_lawless_regions() -> void:
	assert_true(factions.is_lawless("core:region/briarwold"), "the Wold has custom and bows, not law")
	assert_empty(factions.law_for_region("core:region/briarwold"))
	assert_true(factions.is_lawless("core:region/cinderlea"))


func test_law_block_carries_its_terms() -> void:
	var law: Dictionary = factions.law_for_region("core:region/hearthvale")
	assert_eq(str(law["faction"]), WARDENS)
	assert_eq(str(law["style"]), "fine_or_jail")
	assert_eq(int(law["arrest_threshold"]), 40)
	assert_eq(str(law["jail_place"]), "core:place/wardens_rest")
	var skerrow: Dictionary = factions.law_for_region("core:region/skerrow")
	assert_eq(str(skerrow["style"]), "blood_price", "the clans take a price, not a prisoner")


func test_every_law_block_points_at_a_real_region_and_faction() -> void:
	for def in ContentDB.all("faction"):
		var law: Variant = def.get("law")
		if typeof(law) != TYPE_DICTIONARY:
			continue
		var region := str((law as Dictionary).get("region", ""))
		assert_true(ContentDB.has(region), "%s polices unknown region %s" % [def["id"], region])
		assert_eq(factions.law_faction_for_region(region), str(def["id"]))


# --- summary and save --------------------------------------------------------------------------------

func test_summary_lists_every_faction() -> void:
	factions.join(WARDENS)
	factions.add_reputation(WARDENS, 46)
	var summary: Dictionary = factions.summary()
	assert_eq(summary.size(), ContentDB.all("faction").size())
	assert_true(bool(summary[WARDENS]["member"]))
	assert_eq(str(summary[WARDENS]["rank_name"]), "Roll-Keeper")
	assert_false(bool(summary[TALLYMEN]["member"]))


func test_save_round_trip() -> void:
	factions.join(WARDENS)
	factions.add_reputation(WARDENS, 72)
	factions.add_reputation(TALLYMEN, -15)
	var saved: Dictionary = factions.to_save()
	var text := JSON.stringify(saved)

	factions.reset_for_new_game()
	assert_eq(factions.reputation(WARDENS), 0)
	assert_false(factions.is_member(WARDENS))

	factions.from_save(JSON.parse_string(text))
	assert_eq(factions.reputation(WARDENS), 72)
	assert_eq(factions.rank_name(WARDENS), "Warden")
	assert_eq(factions.reputation(TALLYMEN), -15)
	assert_true(factions.is_member(WARDENS))


func test_save_keeps_expulsions() -> void:
	factions.join(QUIET_HANDS)
	factions.join(WARDENS)           # expels from the Quiet Hands
	var text := JSON.stringify(factions.to_save())
	factions.reset_for_new_game()
	factions.from_save(JSON.parse_string(text))
	assert_true(factions.was_expelled(QUIET_HANDS))
	assert_false(factions.join(QUIET_HANDS))
