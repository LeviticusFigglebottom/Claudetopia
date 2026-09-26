class_name Migrations
## Save-file migrations. Each step upgrades a save dictionary from version N to N+1.
## Add a new static function and append it to STEPS whenever SaveSystem.SCHEMA_VERSION bumps.
## Steps must be pure (no engine state) so they can be unit-tested with fixtures.

static var STEPS: Array[Callable] = [
	_v1_to_v2,
	_v2_to_v3,
	_v3_to_v4,
	_v4_to_v5,
]


static func migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("schema_version", 1))
	while v - 1 < STEPS.size():
		var step: Callable = STEPS[v - 1]
		data = step.call(data)
		v += 1
		data["schema_version"] = v
	return data


## v1 -> v2: currency renamed "gold" -> "marks" in the player section; world section gained a
## weather block; clock gained explicit day numbering (v1 stored total hours).
static func _v1_to_v2(data: Dictionary) -> Dictionary:
	var sections: Dictionary = data.get("sections", {})
	if sections.has("player") and sections.player.has("gold"):
		sections.player["marks"] = sections.player["gold"]
		sections.player.erase("gold")
	if sections.has("clock") and sections.clock.has("total_hours"):
		var total: float = float(sections.clock["total_hours"])
		sections.clock = {"time_hours": fmod(total, 24.0), "day": int(total / 24.0) + 1}
	if not sections.has("world"):
		sections["world"] = {}
	if not sections.world.has("weather"):
		sections.world["weather"] = {}
	data["sections"] = sections
	return data


## v2 -> v3: the progression section gained `known_spells` — the sayings the character has been
## taught (DESIGN §5.3). Before this, nothing tracked them and a readied saying was the only
## evidence that a character could Say anything at all, so that one is carried over; otherwise
## the character simply knows nothing yet and has to be taught, like a new one.
static func _v2_to_v3(data: Dictionary) -> Dictionary:
	var sections: Dictionary = data.get("sections", {})
	if not sections.has("progression"):
		sections["progression"] = {}
	var progression: Dictionary = sections["progression"]
	if not progression.has("known_spells"):
		var carried: Array = []
		var readied := str((sections.get("player", {}) as Dictionary).get("equipped_spell", ""))
		if readied != "":
			carried.append(readied)
		progression["known_spells"] = carried
	sections["progression"] = progression
	data["sections"] = sections
	return data


## v3 -> v4: attributes start at 10 instead of 5. The character's Vigour, Endurance and Will
## always lived on Progression, starting at 5, while the body kept three of its own at 10 and
## built its health, stamina and mana from those; the body now reads Progression's, so
## Progression starts where the body always stood. A saved character keeps what it was: every
## attribute it saved moves up by the same 5, points already spent included.
const V4_ATTRIBUTE_SHIFT := 5

static func _v3_to_v4(data: Dictionary) -> Dictionary:
	var sections: Dictionary = data.get("sections", {})
	var progression: Dictionary = sections.get("progression", {})
	var leveling: Dictionary = progression.get("leveling", {})
	var attributes: Dictionary = leveling.get("attributes", {})
	for a in attributes.keys():
		attributes[a] = int(attributes[a]) + V4_ATTRIBUTE_SHIFT
	if not attributes.is_empty():
		leveling["attributes"] = attributes
		progression["leveling"] = leveling
		sections["progression"] = progression
	data["sections"] = sections
	return data


## v4 -> v5: the quest log keeps which quest is followed on the compass, the chart and the HUD's
## tracker (`tracked`, DESIGN §5.16). A save from before says nothing, which the log reads as "follow
## the main quest", the same as a new game; this writes that down so every v5 save carries the key.
static func _v4_to_v5(data: Dictionary) -> Dictionary:
	var sections: Dictionary = data.get("sections", {})
	if sections.has("quests") and typeof(sections["quests"]) == TYPE_DICTIONARY:
		var quests: Dictionary = sections["quests"]
		if not quests.has("tracked"):
			quests["tracked"] = ""
	data["sections"] = sections
	return data
