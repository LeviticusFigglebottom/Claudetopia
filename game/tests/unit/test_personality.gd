extends TestCase


func before_each() -> void:
	Personality.reset_rows()


func test_traits_and_opposites() -> void:
	var p := Personality.of(["brave", "greedy", "gossip"])
	assert_true(p.has("brave"))
	assert_true(p.is_opposed("timid"))
	assert_false(p.has("timid"))
	p.add("timid")
	assert_true(p.has("timid"), "adding the opposite replaces the trait")
	assert_false(p.has("brave"))
	assert_eq(p.traits.size(), 3)
	var from_def := Personality.from_def({"personality": {"traits": ["kind", "pious"]}})
	assert_true(from_def.has("kind"))
	assert_eq(from_def.describe(), "kind, pious")


func test_gesture_disposition() -> void:
	var proud := Personality.of(["proud"])
	var humble := Personality.of(["humble"])
	assert_gt(proud.disposition_delta("bow"), humble.disposition_delta("bow"), "the proud love a bow")
	assert_gt(0, proud.disposition_delta("rude"))
	assert_gt(humble.disposition_delta("rude"), proud.disposition_delta("rude"), "the proud take rudeness worse")
	var plain := Personality.of([])
	assert_eq(plain.disposition_delta("wave"), 1)
	assert_eq(plain.disposition_delta("rude"), -4)
	var gossip := Personality.of(["gossip"])
	assert_gt(gossip.disposition_delta("dance"), plain.disposition_delta("dance"))


func test_price_bias_and_crime_reaction() -> void:
	assert_near(Personality.of(["greedy"]).price_bias(), 0.10)
	assert_near(Personality.of(["generous"]).price_bias(), -0.10)
	assert_near(Personality.of([]).price_bias(), 0.0)
	assert_eq(Personality.of(["timid", "gossip"]).crime_reaction(), "flee", "fear wins over nosiness")
	assert_eq(Personality.of(["brave", "cynical"]).crime_reaction(), "confront")
	assert_eq(Personality.of(["cynical", "quiet"]).crime_reaction(), "ignore")
	assert_eq(Personality.of(["gossip"]).crime_reaction(), "report")
	assert_eq(Personality.of([]).crime_reaction(), "report")
	assert_eq(Personality.of(["timid"]).greeting_bias(), "wary")
	assert_gt(Personality.of(["timid"]).fear(), Personality.of(["brave"]).fear())


func test_table_rows_loaded_from_content() -> void:
	var rows := Personality.rows()
	for t in Personality.TRAITS:
		assert_has(rows, t, "trait row %s" % t)
		assert_has(rows[t], "gestures")
	var tables := ContentDB.where("table", "role", "personality_traits")
	assert_eq(tables.size(), 1, "exactly one personality table in core")


func test_custom_rows_override() -> void:
	Personality.set_rows({"brave": {"gestures": {"bow": 10}, "price_bias": 0.2, "crime_reaction": "flee"}})
	var p := Personality.of(["brave"])
	assert_eq(p.disposition_delta("bow"), 12)
	assert_near(p.price_bias(), 0.2)
	assert_eq(p.crime_reaction(), "flee")
