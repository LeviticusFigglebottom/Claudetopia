class_name StyleDef
extends RefCounted
## A fighting style is data, `core:style/*` (content/packs/core/styles/): the way the character was
## taught to fight, chosen in the Naming beside the Calling (DESIGN §5.1). A Calling is where you
## were raised; a style is who taught you, where, and with what in your hands. It adds to the
## Calling and never replaces it.
##
##   {id, name, blurb, start: place id, teacher: npc id, opening: opening id,
##    tutorial: quest id, tie_in: quest id, mount: mount id, picture?: res:// image,
##    kit: {items: [{item, count?, equip?: main_hand|off_hand}], spells?: [spell id]},
##    skill_bonuses: {skill: n}}
##
## The style's `opening` (content/packs/core/opening.json, `role: "new_game"` with a `style` key)
## says where the new game begins, on what quest, after which short film, and who speaks first.
## This is the validator, and the few readers the Naming, the new-game flow and the tests share.

const TYPE := "style"
## What a style adds to a skill: a teacher's start, less than a Calling's lifetime (+10).
const MAX_BONUS := 5
const HANDS := ["main_hand", "off_hand"]
## The flag the Naming writes the chosen style under, and the one the save carries.
const FLAG := "player_style"


static func validate(def: Dictionary, source := "") -> Array[String]:
	var out: Array[String] = []
	var id := str(def.get("id", "?"))
	var where := "%s: %s" % [source, id] if not source.is_empty() else id
	for key in ["blurb", "start", "teacher", "opening", "tutorial", "tie_in", "mount"]:
		if str(def.get(key, "")).strip_edges().is_empty():
			out.append("%s has no %s" % [where, key])
	_check_type(def, "start", ["place", "poi"], where, out)
	_check_type(def, "teacher", ["npc"], where, out)
	_check_type(def, "opening", ["opening"], where, out)
	_check_type(def, "tutorial", ["quest"], where, out)
	_check_type(def, "tie_in", ["quest"], where, out)
	_check_type(def, "mount", ["mount"], where, out)
	var kit_v: Variant = def.get("kit", null)
	if not (kit_v is Dictionary):
		out.append("%s has no kit" % where)
	else:
		var kit: Dictionary = kit_v
		var items_v: Variant = kit.get("items", [])
		if not (items_v is Array) or (items_v as Array).is_empty():
			out.append("%s's kit has no items: a style starts with something in the hand" % where)
		else:
			var hands := {}
			for row_v in items_v as Array:
				if not (row_v is Dictionary) or str((row_v as Dictionary).get("item", "")).is_empty():
					out.append("%s's kit has a row with no item" % where)
					continue
				var row: Dictionary = row_v
				if Ids.type_of(str(row["item"])) != "item":
					out.append("%s's kit names %s, which is not an item" % [where, str(row["item"])])
				if int(row.get("count", 1)) < 1:
					out.append("%s's kit gives %s of %s" % [where, str(row.get("count")), str(row["item"])])
				var hand := str(row.get("equip", ""))
				if not hand.is_empty():
					if not HANDS.has(hand):
						out.append("%s's kit equips %s in '%s', which is not a hand" % [where, str(row["item"]), hand])
					elif hands.has(hand):
						out.append("%s's kit puts two things in the %s" % [where, hand])
					hands[hand] = true
				var quick := str(row.get("quick", ""))
				if not quick.is_empty() and not quick in ["quick_1", "quick_2", "quick_3", "quick_4"]:
					out.append("%s's kit keeps %s on '%s', which is not a quick key" % [where, str(row["item"]), quick])
		for spell in kit.get("spells", []):
			if Ids.type_of(str(spell)) != "spell":
				out.append("%s's kit teaches %s, which is not a spell" % [where, str(spell)])
	var bonuses_v: Variant = def.get("skill_bonuses", null)
	if not (bonuses_v is Dictionary) or (bonuses_v as Dictionary).is_empty():
		out.append("%s has no skill_bonuses" % where)
	else:
		for skill in bonuses_v as Dictionary:
			var n := int((bonuses_v as Dictionary)[skill])
			if n < 1 or n > MAX_BONUS:
				out.append("%s adds %d to %s: a style adds 1 to %d" % [where, n, str(skill), MAX_BONUS])
	var picture := str(def.get("picture", ""))
	if not picture.is_empty() and not picture.begins_with("res://"):
		out.append("%s's picture '%s' is not a res:// path" % [where, picture])
	return out


static func _check_type(def: Dictionary, key: String, types: Array, where: String, out: Array[String]) -> void:
	var v := str(def.get(key, ""))
	if v.is_empty():
		return
	if not Ids.is_valid(v) or not types.has(Ids.type_of(v)):
		out.append("%s's %s '%s' is not a %s id" % [where, key, v, " or ".join(PackedStringArray(types))])


## Every style in the loaded packs whose start can actually be begun (its opening is there), in id
## order so the cards always read the same way. A def with `offered: false` is in the pack (its
## quests and lines resolve) but is not a card yet: a start still being built.
static func all_styles() -> Array:
	var out: Array = []
	for def in ContentDB.all(TYPE):
		if ContentDB.has(str(def.get("opening", ""))) and bool(def.get("offered", true)):
			out.append(def)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("order", 99)) < int(b.get("order", 99)) if int(a.get("order", 99)) != int(b.get("order", 99)) \
					else str(a["id"]) < str(b["id"]))
	return out


## The style the character was named with, or "" (the fallback start, an old save, a test).
static func of_character() -> String:
	var id := str(GameState.get_flag(FLAG, ""))
	return id if ContentDB.has(id) else ""


## The opening a new game begins with for this style, or {} when there is none to begin.
static func opening_of(style_id: String) -> Dictionary:
	var def := ContentDB.get_or_empty(style_id)
	return ContentDB.get_or_empty(str(def.get("opening", "")))


## The kit in words, for a card: "an iron sword and an oak round shield".
static func kit_words(def: Dictionary) -> String:
	var names: Array[String] = []
	var kit: Dictionary = def.get("kit", {})
	for row in kit.get("items", []):
		var item := ContentDB.get_or_empty(str((row as Dictionary).get("item", "")))
		if item.is_empty() or bool((row as Dictionary).get("hidden", false)):
			continue
		var count := int((row as Dictionary).get("count", 1))
		var n := str(item.get("name", "")).to_lower()
		names.append(("%d %s" % [count, n if n.ends_with("s") else n + "s"]) if count > 1 else (("an " if n.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + n))
	for spell in kit.get("spells", []):
		var s := ContentDB.get_or_empty(str(spell))
		if not s.is_empty():
			names.append(str(s.get("name", "")))
	if names.size() <= 1:
		return "".join(PackedStringArray(names))
	return ", ".join(PackedStringArray(names.slice(0, names.size() - 1))) + " and " + names[names.size() - 1]
