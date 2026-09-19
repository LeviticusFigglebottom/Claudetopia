extends TestCase
## Reachability: a quest nothing can start is a quest nobody will ever play. The main thread
## was in exactly that state — six main quests and a faction line with no way in — so this
## pins the property rather than the instance.

const RADIANT := "radiant"


func _starters() -> Dictionary:
	## quest id -> where it is started from, gathered across the whole pack.
	var out: Dictionary = {}
	var opening := ContentDB.get_or_empty("core:opening/new_game")
	if opening.has("quest"):
		out[str(opening["quest"])] = "the opening"
	for d in ContentDB.all("dialogue"):
		_collect(d, str(d.get("id", "dialogue")), out)
	for q in ContentDB.all("quest"):
		_collect(q, str(q.get("id", "quest")), out)
	return out


func _collect(value: Variant, source: String, out: Dictionary) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = value
			if d.has("start_quest"):
				out[str(d["start_quest"])] = source
			for k in d:
				_collect(d[k], source, out)
		TYPE_ARRAY:
			for v in value:
				_collect(v, source, out)


func test_every_quest_can_be_started() -> void:
	var starters := _starters()
	var unreachable: Array[String] = []
	for q in ContentDB.all("quest"):
		if str(q.get("layer", "")) == RADIANT:
			continue          # radiant work is generated, not authored into a dialogue
		if not starters.has(str(q["id"])):
			unreachable.append(str(q["id"]))
	assert_eq(unreachable, [] as Array[String], "nothing starts these quests")


func test_the_game_opens_on_a_real_quest() -> void:
	var opening := ContentDB.get_or_empty("core:opening/new_game")
	assert_false(opening.is_empty(), "a new game needs to know what it opens with")
	assert_true(ContentDB.has(str(opening.get("quest", ""))))
	assert_eq(str(ContentDB.get_or_empty(str(opening["quest"])).get("layer", "")), "main")


func test_every_quest_giver_exists_and_can_be_talked_to() -> void:
	for q in ContentDB.all("quest"):
		var giver := str(q.get("giver", q.get("start", "")))
		if giver.is_empty():
			continue
		assert_true(ContentDB.has(giver), "%s is given by %s, who does not exist" % [q["id"], giver])
		var npc := ContentDB.get_or_empty(giver)
		assert_true(ContentDB.has(str(npc.get("dialogue", ""))), "%s has no dialogue to give %s in" % [giver, q["id"]])
