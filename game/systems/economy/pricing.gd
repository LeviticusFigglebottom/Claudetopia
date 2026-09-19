class_name Pricing
## Pure price maths (DESIGN §5.14):
##   price = base · region_mod · supply_mod · disposition_mod · (1.3 − Speech/300)
## Buying pays that; selling receives `price · SELL_FRACTION` with the disposition and
## speech terms inverted, so a liked, silver-tongued player buys cheap and sells dear.
## Every factor is clamped so no combination can make an item free or ruinous.

const SELL_FRACTION := 0.45
const SPEECH_BASE := 1.3
const SPEECH_DIVISOR := 300.0
const SUPPLY_TARGET := 8.0
const SUPPLY_MIN := 0.75
const SUPPLY_MAX := 1.4
const DISPOSITION_SWING := 0.25      # ±25% from standing (DESIGN §5.11)
const MIN_PRICE := 1


## Region price modifier from the region def's `price_mod` (default 1.0).
static func region_mod(region_id: String) -> float:
	var r := ContentDB.get_or_empty(region_id)
	return clampf(float(r.get("price_mod", 1.0)), 0.5, 2.0)


## Scarcity: a merchant with none of an item charges more, a glut charges less.
static func supply_mod(stock_count: int) -> float:
	if stock_count <= 0:
		return SUPPLY_MAX
	return clampf(SUPPLY_MAX - (SUPPLY_MAX - SUPPLY_MIN) * minf(1.0, float(stock_count) / SUPPLY_TARGET), SUPPLY_MIN, SUPPLY_MAX)


## Speech term: 1.3 at Speech 0 down to 1.0 at Speech 90, floored at 0.95.
static func speech_mod(speech_skill: int) -> float:
	return maxf(0.95, SPEECH_BASE - clampf(float(speech_skill), 0.0, 100.0) / SPEECH_DIVISOR)


## How the merchant feels about the buyer, as a multiplier around 1.0.
## `disposition` −100..100 (standing, faction rank and past trade), `personality_bias` from
## Personality.price_bias(), `hollow_penalty` when the Hollow are served grudgingly.
static func disposition_mod(disposition: int, personality_bias: float = 0.0, hollow_penalty: float = 0.0) -> float:
	var d := clampf(float(disposition), -100.0, 100.0) / 100.0
	return clampf(1.0 - d * DISPOSITION_SWING + personality_bias + hollow_penalty, 0.5, 2.0)


## Disposition of a merchant toward the player, −100..100, from renown and morality tiers,
## faction rank with the merchant's faction, and any per-merchant stored disposition.
static func disposition_for(profile: Dictionary, faction_rank: int = 0, stored: int = 0) -> int:
	var renown_tier := int(profile.get("renown_tier", 0))
	var morality_tier := int(profile.get("morality_tier", 0))
	var d := stored + renown_tier * 8 + morality_tier * 6 + faction_rank * 5
	return clampi(d, -100, 100)


## The price of one unit. `base` is the item's `value`.
static func price(base: int, region_mod_: float, supply_mod_: float, disposition_mod_: float, speech_skill: int) -> int:
	var p := float(base) * region_mod_ * supply_mod_ * disposition_mod_ * speech_mod(speech_skill)
	return maxi(MIN_PRICE, roundi(p))


## What the player pays the merchant for one unit.
static func buy_price(base: int, region_id: String, stock_count: int, disposition: int, speech_skill: int, personality_bias: float = 0.0, hollow_penalty: float = 0.0) -> int:
	return price(base, region_mod(region_id), supply_mod(stock_count), disposition_mod(disposition, personality_bias, hollow_penalty), speech_skill)


## What the merchant pays the player for one unit. The disposition and speech terms invert:
## a merchant who likes you pays more, not less.
static func sell_price(base: int, region_id: String, stock_count: int, disposition: int, speech_skill: int, personality_bias: float = 0.0, hollow_penalty: float = 0.0) -> int:
	var disp := disposition_mod(disposition, personality_bias, hollow_penalty)
	var speech := speech_mod(speech_skill)
	var p := float(base) * SELL_FRACTION * region_mod(region_id) * supply_mod(stock_count) / maxf(0.25, disp * speech)
	return maxi(MIN_PRICE, roundi(p))


## Total for `count` units, priced one at a time so scarcity rises as a merchant sells out.
## `direction` is "buy" or "sell"; returns {total, unit_prices[]}.
static func bulk(base: int, region_id: String, stock_count: int, count: int, disposition: int, speech_skill: int, direction: String = "buy", personality_bias: float = 0.0, hollow_penalty: float = 0.0) -> Dictionary:
	var total := 0
	var units: Array[int] = []
	for i in maxi(0, count):
		var stock := stock_count - i if direction == "buy" else stock_count + i
		var p := buy_price(base, region_id, stock, disposition, speech_skill, personality_bias, hollow_penalty) if direction == "buy" else sell_price(base, region_id, stock, disposition, speech_skill, personality_bias, hollow_penalty)
		units.append(p)
		total += p
	return {"total": total, "unit_prices": units}
