class_name Leveling
extends RefCounted
## Character level, attributes and the derived pools (DESIGN §5.3, §5.6).
##
## Character level L requires `sum_skill_gains >= 10*L + 5*L^2` skill levels earned; level 1 is
## free (the threshold for L is the cost of *reaching* L+1... no: THRESHOLDS are cumulative and
## level(gains) returns the highest L whose threshold the gains have met, starting from 1).
## Each level grants one attribute point and one perk point.
##
## Attributes: Vigour (health), Endurance (stamina = 100 + 8*E, carrying = 60 + 4*E), Will
## (mana = 60 + 6*W). All three start at 10. Health, stamina and mana are DamageModel's formulas,
## the ones combat has always used: this file kept a second set (health 100 + 10*V, attributes
## starting at 5) that the body never read, so the character sheet and the health bar disagreed
## from the first frame, and a level's point in Endurance changed only the sheet.
## Pure logic: no nodes, no signals.

const ATTRIBUTES: Array[String] = ["vigour", "endurance", "will"]
const ATTRIBUTE_NAMES := {"vigour": "Vigour", "endurance": "Endurance", "will": "Will"}
const BASE_ATTRIBUTE := 10
const MAX_ATTRIBUTE := 100

const LOAD_BASE := 60.0
const LOAD_PER_ENDURANCE := 4.0

const MAX_LEVEL := 60

var level: int = 1
var attributes: Dictionary = {}
var attribute_points: int = 0
var perk_points: int = 0
var spent_attribute_points: int = 0


func _init() -> void:
	reset()


func reset() -> void:
	level = 1
	attributes = {}
	for a in ATTRIBUTES:
		attributes[a] = BASE_ATTRIBUTE
	attribute_points = 0
	perk_points = 0
	spent_attribute_points = 0


# --- the curve ---------------------------------------------------------------------------

## Skill gains needed to have reached character level L (DESIGN §5.6: 10L + 5L²).
static func threshold_for(character_level: int) -> int:
	if character_level <= 1:
		return 0
	var l := character_level - 1
	return 10 * l + 5 * l * l


## The character level a total of skill gains buys.
static func level_for(total_gains: int) -> int:
	var l := 1
	while l < MAX_LEVEL and total_gains >= threshold_for(l + 1):
		l += 1
	return l


## 0..1 toward the next character level.
static func fraction_for(total_gains: int) -> float:
	var l := level_for(total_gains)
	if l >= MAX_LEVEL:
		return 1.0
	var lo := threshold_for(l)
	var hi := threshold_for(l + 1)
	if hi <= lo:
		return 1.0
	return clampf(float(total_gains - lo) / float(hi - lo), 0.0, 1.0)


static func gains_to_next(total_gains: int) -> int:
	var l := level_for(total_gains)
	if l >= MAX_LEVEL:
		return 0
	return maxi(0, threshold_for(l + 1) - total_gains)


## Recomputes the level from skill gains, granting a point of each kind per new level.
## Returns the levels gained.
func update_from_gains(total_gains: int) -> int:
	var target := level_for(total_gains)
	var gained := maxi(0, target - level)
	if gained > 0:
		level = target
		attribute_points += gained
		perk_points += gained
	return gained


# --- attributes --------------------------------------------------------------------------

func attribute(name: String) -> int:
	return int(attributes.get(name, 0))


## Spends one attribute point. Returns false when there is none or the name is unknown.
func spend_attribute(name: String) -> bool:
	if attribute_points <= 0 or not attributes.has(name):
		return false
	if attribute(name) >= MAX_ATTRIBUTE:
		return false
	attributes[name] = attribute(name) + 1
	attribute_points -= 1
	spent_attribute_points += 1
	return true


func spend_perk_point() -> bool:
	if perk_points <= 0:
		return false
	perk_points -= 1
	return true


func refund_perk_point() -> void:
	perk_points += 1


# --- derived pools -----------------------------------------------------------------------

static func max_health_for(vigour: int) -> float:
	return DamageModel.hp_max(vigour)


static func max_stamina_for(endurance: int) -> float:
	return DamageModel.stamina_max(endurance)


static func max_mana_for(will: int) -> float:
	return DamageModel.mana_max(will)


static func load_capacity_for(endurance: int) -> float:
	return LOAD_BASE + LOAD_PER_ENDURANCE * endurance


func max_health() -> float:
	return max_health_for(attribute("vigour"))


func max_stamina() -> float:
	return max_stamina_for(attribute("endurance"))


func max_mana() -> float:
	return max_mana_for(attribute("will"))


func load_capacity() -> float:
	return load_capacity_for(attribute("endurance"))


func summary(total_gains: int = -1) -> Dictionary:
	var d := {
		"level": level, "attribute_points": attribute_points, "perk_points": perk_points,
		"attributes": attributes.duplicate(), "max_health": max_health(), "max_stamina": max_stamina(),
		"max_mana": max_mana(), "load_capacity": load_capacity(),
	}
	if total_gains >= 0:
		d["progress"] = fraction_for(total_gains)
		d["gains_to_next"] = gains_to_next(total_gains)
	return d


func to_save() -> Dictionary:
	return {
		"level": level, "attributes": attributes.duplicate(), "attribute_points": attribute_points,
		"perk_points": perk_points, "spent_attribute_points": spent_attribute_points,
	}


func from_save(d: Dictionary) -> void:
	reset()
	level = maxi(1, int(d.get("level", 1)))
	var saved: Dictionary = d.get("attributes", {})
	for a in ATTRIBUTES:
		if saved.has(a):
			attributes[a] = clampi(int(saved[a]), 1, MAX_ATTRIBUTE)
	attribute_points = int(d.get("attribute_points", 0))
	perk_points = int(d.get("perk_points", 0))
	spent_attribute_points = int(d.get("spent_attribute_points", 0))
