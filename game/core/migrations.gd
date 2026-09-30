class_name Migrations
## Save-file migrations. Each step upgrades a save dictionary from version N to N+1.
## Add a new static function and append it to STEPS whenever SaveSystem.SCHEMA_VERSION bumps.
## Steps must be pure (no engine state) so they can be unit-tested with fixtures.

static var STEPS: Array[Callable] = [
	_v1_to_v2,
	_v2_to_v3,
	_v3_to_v4,
	_v4_to_v5,
	_v5_to_v6,
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


## v5 -> v6: the belt holds things used and has eight slots; weapons are in the weapon set, which
## the cycle key goes round (Equipment.weapon_set, playtest 09-30). A weapon a save kept on a quick
## key (the ranger's knife on 4) moves into the equipment section's `weapon_set`, after the weapon in
## the hand when the bag says which that is; draughts and the rest stay where they were. The
## player section's own copy of the belt (for sayings) loses its weapons and grows to eight.
## A weapon is known by its id's record in the content (ContentDB), which is data, not engine state.
const V6_QUICK_SLOTS := ["quick_1", "quick_2", "quick_3", "quick_4", "quick_5", "quick_6", "quick_7", "quick_8"]
const V6_WEAPON_SET_SIZE := 4

static func _v5_to_v6(data: Dictionary) -> Dictionary:
	var sections: Dictionary = data.get("sections", {})
	var eq: Dictionary = sections.get("equipment", {}) if typeof(sections.get("equipment")) == TYPE_DICTIONARY else {}
	if not eq.is_empty():
		var quick: Dictionary = eq.get("quick", {})
		var wset: Array = eq.get("weapon_set", []).duplicate()
		var held := _v6_held_weapon(sections, eq)
		if held != "" and not wset.has(held):
			wset.push_front(held)
		for q in V6_QUICK_SLOTS:
			var id := str(quick.get(q, ""))
			if _v6_is_weapon(id):
				if not wset.has(id) and wset.size() < V6_WEAPON_SET_SIZE:
					wset.append(id)
				id = ""
			quick[q] = id
		eq["quick"] = quick
		eq["weapon_set"] = wset
		if not eq.has("set_offhand"):
			eq["set_offhand"] = {}
		sections["equipment"] = eq
	var player: Dictionary = sections.get("player", {}) if typeof(sections.get("player")) == TYPE_DICTIONARY else {}
	if player.has("quick_slots"):
		var belt: Array = []
		for id in player["quick_slots"]:
			belt.append("" if _v6_is_weapon(str(id)) else str(id))
		while belt.size() < V6_QUICK_SLOTS.size():
			belt.append("")
		player["quick_slots"] = belt
		sections["player"] = player
	data["sections"] = sections
	return data


static func _v6_is_weapon(id: String) -> bool:
	if id.is_empty():
		return false
	var def := ContentDB.get_or_empty(id)
	return str(def.get("category", "")) == "weapon" and not (def.get("tags", []) as Array).has("shield")


## The id of the weapon in the saved main hand: the doll keeps a stack's uid, the bag the stack.
static func _v6_held_weapon(sections: Dictionary, eq: Dictionary) -> String:
	var uid := int((eq.get("slots", {}) as Dictionary).get("main_hand", 0))
	if uid <= 0:
		return ""
	var bag: Variant = sections.get("inventory", {})
	if typeof(bag) != TYPE_DICTIONARY:
		return ""
	for key in ["stacks", "items"]:
		for st in (bag as Dictionary).get(key, []):
			if typeof(st) == TYPE_DICTIONARY and int((st as Dictionary).get("uid", -1)) == uid:
				var id := str((st as Dictionary).get("id", ""))
				return id if _v6_is_weapon(id) else ""
	return ""
