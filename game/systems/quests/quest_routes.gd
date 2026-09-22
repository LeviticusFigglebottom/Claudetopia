class_name QuestRoutes
extends RefCounted
## Which quest objectives the pack's dialogue already closes by hand, and who hosts the rest.
##
## Two objective types close only when something else says so. A `deliver` closes on a dialogue
## effect (`complete_objective`) and a `choice` on another (`quest_choice`); the authors wrote
## those for some quests and not for others. The walk of every quest in the pack found nine that
## nobody could ever close: five deliveries with no line to hand the thing over on, and the main
## thread's five decisions — the Circle's price, whose bell, the eighth verse, who keeps the Moot,
## and the note itself — with no button anywhere to decide them on.
##
## So the quest log hands a delivery over when you finish speaking to the person carrying what
## they are owed, and the dialogue runner offers a stage's open options at its host's hub. Both
## stand aside wherever an author did write the line, which is what this index is for: an
## authored hand-over is a scene, and a generic one arriving first would skip it.
##
## A choice's host is, in order: the objective's own `with` (an npc id; or a place, POI or
## interior, where a `ChoicePoint` is put down instead — the note at the Cantor's Seat has nobody
## left to ask); the person the same stage asks you to speak to; the quest's giver.

static var _closes: Dictionary = {}     # "quest|key" -> true, from complete_objective effects
static var _chosen: Dictionary = {}     # "quest|option" -> true, from quest_choice effects
static var _built := false


static func reset() -> void:
	_closes.clear()
	_chosen.clear()
	_built = false


static func _build() -> void:
	if _built:
		return
	_built = true
	for def in ContentDB.all("dialogue"):
		_walk(def)


static func _walk(v: Variant) -> void:
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		for key in d:
			var value: Variant = d[key]
			if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
				if str(key) == "complete_objective":
					_closes["%s|%s" % [str(value[0]), str(value[1])]] = true
				elif str(key) == "quest_choice":
					_chosen["%s|%s" % [str(value[0]), str(value[1])]] = true
			_walk(value)
	elif typeof(v) == TYPE_ARRAY:
		for x in v:
			_walk(x)


## Does some dialogue in the pack close this objective itself? Matches the way
## `QuestLog.complete_objective` resolves a key: the objective's index, its `key`, its target,
## or "type:target" — and only when that key would land on *this* objective of the stage rather
## than an earlier one with the same target.
static func dialogue_closes(quest_id: String, stage: Dictionary, index: int) -> bool:
	_build()
	var objectives: Array = stage.get("objectives", [])
	if index < 0 or index >= objectives.size():
		return false
	if _closes.has("%s|%d" % [quest_id, index]):
		return true
	var mine: Dictionary = objectives[index]
	for wanted in [str(mine.get("key", "")), str(mine.get("target", "")),
			"%s:%s" % [str(mine.get("type", "")), str(mine.get("target", ""))]]:
		if wanted == "" or wanted == ":" or not _closes.has("%s|%s" % [quest_id, wanted]):
			continue
		if _first_match(objectives, wanted) == index:
			return true
	return false


static func _first_match(objectives: Array, wanted: String) -> int:
	for i in objectives.size():
		var o: Dictionary = objectives[i]
		if str(o.get("key", "")) == wanted or str(o.get("target", "")) == wanted \
				or "%s:%s" % [str(o.get("type", "")), str(o.get("target", ""))] == wanted:
			return i
	return -1


## Has an author written a button for any option of this choice objective?
static func dialogue_offers(quest_id: String, objective: Dictionary) -> bool:
	_build()
	for entry in objective.get("options", []):
		var option := str((entry as Dictionary).get("id", "")) if typeof(entry) == TYPE_DICTIONARY else str(entry)
		if _chosen.has("%s|%s" % [quest_id, option]):
			return true
	return _chosen.has("%s|%s" % [quest_id, str(objective.get("target", ""))])


## Who is asked to decide a choice nobody wrote a button for (see the class note).
static func host_of(quest_def: Dictionary, stage: Dictionary, objective: Dictionary) -> String:
	var named := str(objective.get("with", ""))
	if named != "":
		return named
	for o in stage.get("objectives", []):
		var other: Dictionary = o
		if str(other.get("type", "")) == "talk" and Ids.type_of(str(other.get("target", ""))) == "npc":
			return str(other["target"])
	return str(quest_def.get("giver", ""))
