extends TestCase

const SCHEDULE := [
	{"days": "all", "hour": 22, "place": "home", "activity": "sleep", "spot": "bed"},
	{"days": "all", "hour": 6, "place": "home", "activity": "eat", "spot": "table"},
	{"days": "workdays", "hour": 8, "place": "core:place/merrowby", "activity": "work", "spot": "market_stall"},
	{"days": "workdays", "hour": 13, "place": "core:place/merrowby", "activity": "eat", "spot": "inn_bench"},
	{"days": "workdays", "hour": 14, "place": "core:place/merrowby", "activity": "work", "spot": "market_stall"},
	{"days": "all", "hour": 18, "place": "core:place/merrowby", "activity": "idle", "spot": "green"},
	{"days": "tollday", "hour": 9, "place": "core:place/cracked_toll", "activity": "pray", "spot": "in:lip"},
]
const HOME := "core:place/tamwick"


func test_day_filters() -> void:
	assert_true(Schedules.applies_on("all", 3))
	assert_true(Schedules.applies_on(null, 0))
	assert_true(Schedules.applies_on("workdays", 5))
	assert_false(Schedules.applies_on("workdays", 6))
	assert_true(Schedules.applies_on("tollday", 6))
	assert_true(Schedules.applies_on("Kindleday", 0))
	assert_true(Schedules.applies_on([1, 3], 3))
	assert_false(Schedules.applies_on([1, 3], 2))
	assert_true(Schedules.applies_on("1-3", 2))
	assert_true(Schedules.applies_on("5-1", 0), "wrapping range")
	assert_false(Schedules.applies_on("5-1", 3))
	assert_true(Schedules.applies_on("0,2,4", 4))
	assert_true(Schedules.applies_on(2.0, 2), "JSON numbers arrive as floats")
	assert_eq(Schedules.weekday_of(1), 0)
	assert_eq(Schedules.weekday_of(8), 0)
	assert_eq(Schedules.weekday_of(7), 6)


func test_entry_selection_workday() -> void:
	var e := Schedules.entry_at(SCHEDULE, 2, 10.0, "clear", HOME)
	assert_eq(e["activity"], "work")
	assert_eq(e["place"], "core:place/merrowby")
	assert_eq(e["spot"], "market_stall")
	assert_false(e["travelling"])
	assert_near(float(e["hour"]), 8.0)
	assert_eq(e["next"]["activity"], "eat")
	assert_near(float(e["next"]["starts_in_hours"]), 3.0)
	var at_exact := Schedules.entry_at(SCHEDULE, 2, 8.0, "clear", HOME)
	assert_eq(at_exact["activity"], "work", "an entry starts at its own hour")


func test_entry_selection_wraps_to_previous_day() -> void:
	var e := Schedules.entry_at(SCHEDULE, 2, 3.0, "clear", HOME)
	assert_eq(e["activity"], "sleep")
	assert_eq(e["place"], HOME, "'home' resolves to the home place")
	assert_near(float(e["hour"]), -2.0, 0.001, "entry started at 22:00 yesterday")
	var e2 := Schedules.entry_at(SCHEDULE, 6, 10.0, "clear", HOME)
	assert_eq(e2["activity"], "pray", "tollday schedule differs")
	# no work on tollday: still at breakfast, until it is time to walk to the Toll for nine
	var e3 := Schedules.entry_at(SCHEDULE, 6, 6.4, "clear", HOME)
	assert_eq(e3["activity"], "eat", "no work on tollday: still at breakfast")
	var e4 := Schedules.entry_at(SCHEDULE, 6, 8.5, "clear", HOME)
	assert_eq(e4["place"], "core:place/cracked_toll", "and then on the road to the Toll, not to the market")


func test_travel_lead() -> void:
	# Tamwick to Merrowby is some 1.2 km of road, most of three game-hours at a walking pace, but
	# breakfast at six leaves two hours before work at eight, and a journey takes at most
	# three-quarters of the time the entry before it had
	var lead_h := Schedules.travel_hours(HOME, "core:place/merrowby", 2.0)
	assert_near(lead_h, 1.5, 0.001, "the walk is held to three-quarters of breakfast")
	var sets_out := 8.0 - lead_h
	var before := Schedules.entry_at(SCHEDULE, 1, sets_out - 1.0 / 60.0, "clear", HOME)
	assert_eq(before["activity"], "eat")
	assert_false(before["travelling"])
	var lead := Schedules.entry_at(SCHEDULE, 1, sets_out + 1.0 / 60.0, "clear", HOME)
	assert_true(lead["travelling"], "the NPC sets out as long before the entry as the walk takes")
	assert_eq(lead["activity"], "travel")
	assert_eq(lead["place"], "core:place/merrowby")
	assert_eq(lead["spot"], "market_stall")
	assert_eq(lead["after_travel"], "work")
	assert_eq(lead["travel_from"], HOME, "and says where from, for the road between")
	assert_false(lead["indoors"], "somebody on the road is out of doors")
	assert_near(float(lead["arrives_in_hours"]), lead_h - 1.0 / 60.0, 0.001)
	var same_place := Schedules.entry_at(SCHEDULE, 1, 12.0 + 50.0 / 60.0, "clear", HOME)
	assert_false(same_place["travelling"], "no travel when the next entry is at the same place")
	assert_eq(same_place["activity"], "work")
	var overnight := Schedules.entry_at(SCHEDULE, 1, 23.9, "clear", HOME)
	assert_false(overnight["travelling"], "next entry (06:00 tomorrow) is far away")
	assert_eq(overnight["activity"], "sleep")


func test_a_journey_takes_as_long_as_its_road() -> void:
	var near := Schedules.travel_hours("core:place/wynstead", "core:place/merrowby")
	var far := Schedules.travel_hours("core:place/pilgrims_ash", "core:place/merrowby")
	assert_gt(far, near, "a longer road is a longer walk")
	assert_true(far <= Schedules.MAX_TRAVEL_HOURS + 0.001, "and never longer than the cap")
	assert_true(near >= Schedules.TRAVEL_LEAD_HOURS, "and never shorter than the old twenty minutes")
	assert_near(Schedules.travel_hours("core:place/nowhere_at_all", "core:place/merrowby"), Schedules.TRAVEL_LEAD_HOURS, 0.001,
			"places the roads do not know are twenty minutes apart")
	assert_near(Schedules.travel_hours("core:place/merrowby", "core:place/merrowby"), Schedules.TRAVEL_LEAD_HOURS, 0.001)


func test_weather_override() -> void:
	var dry := Schedules.entry_at(SCHEDULE, 1, 19.0, "clear", HOME)
	assert_eq(dry["activity"], "idle")
	assert_eq(dry["place"], "core:place/merrowby")
	assert_false(dry["weather_override"])
	var wet := Schedules.entry_at(SCHEDULE, 1, 19.0, "rain", HOME)
	assert_eq(wet["activity"], "idle")
	assert_eq(wet["place"], HOME, "rain sends outdoor idling home")
	assert_eq(wet["spot"], "home")
	assert_true(wet["weather_override"])
	var storm_work := Schedules.entry_at(SCHEDULE, 1, 10.0, "storm", HOME)
	assert_eq(storm_work["place"], "core:place/merrowby", "work is not overridden by weather")
	var indoor_idle := [{"days": "all", "hour": 18, "place": "core:place/merrowby", "activity": "idle", "spot": "in:inn", "indoors": true}]
	var inn := Schedules.entry_at(indoor_idle, 1, 19.0, "rain", HOME)
	assert_false(inn["weather_override"], "indoor idle is unaffected")
	assert_true(Schedules.is_rainy("drizzle"))
	assert_false(Schedules.is_rainy("fog"))
	var travel_wet := Schedules.entry_at(SCHEDULE, 1, 18.0 - Schedules.travel_hours("core:place/merrowby", HOME, 4.0) + 1.0 / 60.0, "rain", HOME)
	assert_true(travel_wet["travelling"], "travel target follows the override (market -> home)")
	assert_eq(travel_wet["place"], HOME)


func test_empty_schedule_and_intents() -> void:
	var e := Schedules.entry_at([], 0, 12.0, "clear", HOME)
	assert_eq(e["activity"], "idle")
	assert_eq(e["place"], HOME)
	assert_eq(Schedules.intent_for("sleep"), "Sleep_Idle")
	assert_eq(Schedules.intent_for("work", {"clip": "Work_Stir"}), "Work_Stir")
	assert_eq(Schedules.intent_for("work", {}, {"work_clip": "Work_Chop"}), "Work_Chop")
	assert_eq(Schedules.intent_for("work"), "Work_Hammer")
	assert_eq(Schedules.intent_for("work", {"clip": ""}, {"work_clip": "Work_Chop"}), "Work_Chop", "an empty clip is no clip")
	assert_eq(Schedules.intent_for("work", {"clip": ""}, {"work_clip": ""}), "Work_Hammer")
	assert_eq(Schedules.intent_for("travel"), "Walk")
	assert_eq(Schedules.intent_for("socialise"), "Talk_1")
	var bad := Schedules.problems([{"hour": 25, "activity": "juggle"}], "x")
	assert_eq(bad.size(), 2)
	assert_empty(Schedules.problems(SCHEDULE, "ok"))


func test_entry_for_def_uses_clock_day() -> void:
	var def := {"home_place": HOME, "schedule": SCHEDULE}
	var e := Schedules.entry_for_def(def, 7, 10.0)
	assert_eq(e["activity"], "pray", "day 7 is Tollday")
	var e2 := Schedules.entry_for_def(def, 8, 10.0)
	assert_eq(e2["activity"], "work", "day 8 wraps to Kindleday")


func test_core_npc_schedules_are_valid() -> void:
	for npc in ContentDB.all("npc"):
		var probs := Schedules.problems(npc.get("schedule", []), npc["id"])
		assert_empty(probs, npc["id"])
		for e in npc.get("schedule", []):
			var place := str(e.get("place", "home"))
			if place != "home":
				assert_true(ContentDB.has(place), "%s schedule place %s missing" % [npc["id"], place])
