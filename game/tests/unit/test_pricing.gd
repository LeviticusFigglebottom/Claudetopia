extends TestCase

const HEARTHVALE := "core:region/hearthvale"


func test_speech_term() -> void:
	assert_near(Pricing.speech_mod(0), 1.3)
	assert_near(Pricing.speech_mod(30), 1.2)
	assert_near(Pricing.speech_mod(90), 1.0)
	assert_near(Pricing.speech_mod(100), 0.9667, 0.001)
	assert_near(Pricing.speech_mod(500), 0.9667, 0.001, "clamped to skill 100")


func test_supply_term() -> void:
	assert_near(Pricing.supply_mod(0), 1.4, 0.0001, "out of stock is dear")
	assert_near(Pricing.supply_mod(8), 0.75)
	assert_near(Pricing.supply_mod(80), 0.75, 0.0001, "a glut bottoms out")
	assert_near(Pricing.supply_mod(4), 1.075)
	assert_gt(Pricing.supply_mod(2), Pricing.supply_mod(6), "scarcity costs")


func test_region_modifier_from_data() -> void:
	assert_near(Pricing.region_mod(HEARTHVALE), 1.0, 0.0001, "default when a region defines none")
	assert_near(Pricing.region_mod("core:region/nowhere"), 1.0)
	var brightwater := Pricing.region_mod("core:region/brightwater")
	assert_true(brightwater >= 0.5 and brightwater <= 2.0)


func test_disposition_term() -> void:
	assert_near(Pricing.disposition_mod(0), 1.0)
	assert_near(Pricing.disposition_mod(100), 0.75, 0.0001, "a friend knocks a quarter off")
	assert_near(Pricing.disposition_mod(-100), 1.25)
	assert_near(Pricing.disposition_mod(0, 0.10), 1.10, 0.0001, "a greedy shopkeeper")
	assert_near(Pricing.disposition_mod(0, -0.10), 0.90, 0.0001, "a generous one")
	assert_near(Pricing.disposition_mod(0, 0.0, 0.25), 1.25, 0.0001, "the Hollow pay more")
	assert_near(Pricing.disposition_mod(1000), 0.75, 0.0001, "clamped")


func test_disposition_from_profile() -> void:
	assert_eq(Pricing.disposition_for({"renown_tier": 0, "morality_tier": 0}), 0)
	assert_eq(Pricing.disposition_for({"renown_tier": 4, "morality_tier": 3}), 50)
	assert_eq(Pricing.disposition_for({"renown_tier": 0, "morality_tier": -3}), -18, "the Hollow are liked less")
	assert_eq(Pricing.disposition_for({"renown_tier": 2}, 3), 31, "faction rank counts")
	assert_eq(Pricing.disposition_for({"renown_tier": 2}, 0, 10), 26, "past trade counts")
	assert_eq(Pricing.disposition_for({"renown_tier": 4, "morality_tier": 3}, 5, 100), 100, "clamped")


func test_buy_and_sell_prices() -> void:
	var plain := Pricing.buy_price(100, HEARTHVALE, 8, 0, 0)
	assert_eq(plain, 98, "100 x 1.0 x 0.75 x 1.0 x 1.3")
	assert_eq(Pricing.buy_price(100, HEARTHVALE, 8, 0, 90), 75, "Speech 90 removes the mark-up")
	assert_gt(plain, Pricing.buy_price(100, HEARTHVALE, 8, 100, 0), "a friend charges less")
	assert_gt(Pricing.buy_price(100, HEARTHVALE, 8, -100, 0), plain, "an enemy charges more")
	assert_gt(Pricing.buy_price(100, HEARTHVALE, 0, 0, 0), plain, "scarcity costs")
	assert_eq(Pricing.buy_price(1, HEARTHVALE, 40, 100, 100), Pricing.MIN_PRICE, "nothing is free")
	var sell := Pricing.sell_price(100, HEARTHVALE, 8, 0, 0)
	assert_eq(sell, 26, "100 x 0.45 x 0.75 / 1.3")
	assert_true(sell < plain, "merchants buy low and sell high")
	assert_gt(Pricing.sell_price(100, HEARTHVALE, 8, 0, 90), sell, "Speech helps when selling too")
	assert_gt(Pricing.sell_price(100, HEARTHVALE, 8, 100, 0), sell, "a friend pays more")
	assert_gt(sell, Pricing.sell_price(100, HEARTHVALE, 8, -100, 0), "an enemy pays less")


func test_personality_and_hollow_effects() -> void:
	var base := Pricing.buy_price(100, HEARTHVALE, 8, 0, 0)
	var greedy := Pricing.buy_price(100, HEARTHVALE, 8, 0, 0, Personality.of(["greedy"]).price_bias())
	var generous := Pricing.buy_price(100, HEARTHVALE, 8, 0, 0, Personality.of(["generous"]).price_bias())
	assert_gt(greedy, base)
	assert_gt(base, generous)
	assert_gt(Pricing.buy_price(100, HEARTHVALE, 8, 0, 0, 0.0, 0.25), base, "Hollow players pay a penalty")


func test_bulk_prices_move_with_stock() -> void:
	var buy := Pricing.bulk(100, HEARTHVALE, 3, 3, 0, 0, "buy")
	assert_eq(buy["unit_prices"].size(), 3)
	assert_gt(buy["unit_prices"][2], buy["unit_prices"][0], "the last one off the shelf costs most")
	assert_eq(int(buy["total"]), int(buy["unit_prices"][0]) + int(buy["unit_prices"][1]) + int(buy["unit_prices"][2]))
	var sell := Pricing.bulk(100, HEARTHVALE, 1, 3, 0, 0, "sell")
	assert_gt(int(sell["unit_prices"][0]), int(sell["unit_prices"][2]), "flooding the shop lowers what he pays")
	assert_eq(int(Pricing.bulk(100, HEARTHVALE, 5, 0, 0, 0)["total"]), 0)
