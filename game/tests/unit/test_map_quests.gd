extends TestCase
## The quests follow the map (docs/ATLAS.md §12). Every settlement offers local work, given by
## somebody who lives there and has a day and lines of their own; every place that is not a
## settlement is somewhere a quest sends you; every point of interest pays off in something the
## game puts there; and every objective of every quest resolves to a place, a person, a spawn or
## an item the game places.
##
## When the map was drawn, 41 quests reached 27 of its 60 places and 16 of its 240 points of
## interest, and most of the country's hamlets had one resident with nothing to ask of anybody.

## Where the quests that follow the map are written.
const MAP_QUESTS := "res://content/packs/core/quests/the_map.json"
const MAP_NOTES := "res://content/packs/core/encounters/the_map.json"
## What each point of interest's hook pays off in.
const MAP_HOOKS := "core:table/poi_hooks"


func _authored() -> Array:
	var out: Array = []
	for def in ContentDB.all("quest"):
		if str(def.get("layer", "")) != "radiant":
			out.append(def)
	return out


func _map_quests() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_QUESTS))
	return parsed if typeof(parsed) == TYPE_ARRAY else []


## Every place and point of interest one quest sends you to: an objective's target, where or
## place, a marker, and where its giver and the people it sends you to live.
func _sends_you(def: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var giver := str(def.get("giver", ""))
	if giver != "":
		out[str(ContentDB.get_or_empty(giver).get("home_place", ""))] = true
	for stage_v in def.get("stages", []):
		var stage: Dictionary = stage_v
		var marker: Variant = stage.get("marker")
		if typeof(marker) == TYPE_DICTIONARY:
			out[str((marker as Dictionary).get("place_id", ""))] = true
		for o_v in stage.get("objectives", []):
			var o: Dictionary = o_v
			for key in ["target", "where", "place"]:
				var v := str(o.get(key, ""))
				match Ids.type_of(v):
					"place", "poi":
						out[v] = true
					"npc":
						out[str(ContentDB.get_or_empty(v).get("home_place", ""))] = true
					"interior":
						out[str(ContentDB.get_or_empty(v).get("place", ""))] = true
	return out


## Every place and point of interest any authored quest sends you to.
func _reached() -> Dictionary:
	var out: Dictionary = {}
	for def in _authored():
		out.merge(_sends_you(def))
	return out


## Somebody who lives here, keeps a day of their own and has lines to say.
func _is_resident(npc: Dictionary, place_id: String) -> bool:
	if str(npc.get("home_place", "")) != place_id:
		return false
	if (npc.get("schedule", []) as Array).is_empty():
		return false
	return ContentDB.has(str(npc.get("dialogue", "")))


func test_every_settlement_offers_work_from_somebody_who_lives_there() -> void:
	var begins: Dictionary = {}
	for b in QuestWalk.beginnings():
		begins[str(b["quest_id"])] = bool(b["ok"])
	var settlements := 0
	for place in ContentDB.all("place"):
		var place_id := str(place["id"])
		if not Settlement.FABRIC.has(str(place.get("kind", ""))):
			continue
		settlements += 1
		var work: Array[String] = []
		for def in _authored():
			var giver := ContentDB.get_or_empty(str(def.get("giver", "")))
			if not giver.is_empty() and _is_resident(giver, place_id) and bool(begins.get(str(def["id"]), false)):
				work.append(str(def["id"]))
		assert_false(work.is_empty(), "%s offers no work: nobody who lives there gives a quest anybody can begin" % place_id)
	assert_gt(settlements, 35, "the map's settlements were asked")


func test_every_place_that_is_not_a_settlement_is_somewhere_a_quest_goes() -> void:
	var reached := _reached()
	for place in ContentDB.all("place"):
		var kind := str(place.get("kind", ""))
		if Settlement.FABRIC.has(kind) or kind == "edge":
			continue
		assert_true(reached.has(str(place["id"])), "no quest goes to %s (%s)" % [place["id"], kind])


## A point of interest's hook pays off in something the game puts there: a quest stage sends you,
## an encounter stands something up, something lies there to take or read, or it keeps a Hearthstone.
func test_every_point_of_interest_pays_off() -> void:
	var reached := _reached()
	var lying: Dictionary = {}
	for row in QuestItems.placements():
		lying[str(row["where"])] = true
	var bare: Array[String] = []
	for poi in ContentDB.all("poi"):
		var id := str(poi["id"])
		if reached.has(id) or lying.has(id) or not PoiEncounters.of(id).is_empty() or bool(poi.get("hearthstone", false)):
			continue
		bare.append(id)
	assert_empty(bare, "points of interest with nothing to go there for")


## Each point of interest's one-line hook, tied to the ids that pay it off (core:table/poi_hooks,
## docs/ATLAS.md §16). Every row is held to what the pack does: the quests it names send you there,
## the finds lie there, the encounters stand somebody up there, and the Hearthstone is the place's own.
func test_every_hook_is_tied_to_the_ids_that_pay_it_off() -> void:
	var rows: Array = ContentDB.get_or_empty(MAP_HOOKS).get("rows", [])
	assert_eq(rows.size(), ContentDB.all("poi").size(), "the hook table has a row for every point of interest")
	var lying: Dictionary = {}
	for row in QuestItems.placements():
		lying["%s|%s" % [row["where"], row.get("item", "")]] = true
		lying["%s|%s" % [row["where"], row.get("book", "")]] = true
	var seen: Dictionary = {}
	for r_v in rows:
		var r: Dictionary = r_v
		var poi_id := str(r.get("poi", ""))
		var poi := ContentDB.get_or_empty(poi_id)
		assert_false(poi.is_empty(), "the hook table has a row for %s, which is nowhere" % poi_id)
		seen[poi_id] = true
		var pays := 0
		for qid in r.get("quests", []):
			var def := ContentDB.get_or_empty(str(qid))
			assert_true(_sends_you(def).has(poi_id), "%s: %s does not send you there" % [poi_id, qid])
			pays += 1
		for what in r.get("finds", []):
			assert_true(lying.has("%s|%s" % [poi_id, what]), "%s: nothing puts %s down there" % [poi_id, what])
			pays += 1
		for enc_id in r.get("encounters", []):
			var enc := ContentDB.get_or_empty(str(enc_id))
			assert_true(str(enc.get("place", "")) == poi_id and not (enc.get("spawns", []) as Array).is_empty(),
					"%s: %s stands nobody up there" % [poi_id, enc_id])
			pays += 1
		var hearth := bool(poi.get("hearthstone", false))
		assert_eq(bool(r.get("hearthstone", false)), hearth, "%s: the table and the place disagree about its Hearthstone" % poi_id)
		pays += 1 if hearth else 0
		assert_gt(pays, 0, "%s: its hook pays off in nothing" % poi_id)
	for poi in ContentDB.all("poi"):
		assert_true(seen.has(str(poi["id"])), "the hook table has no row for %s" % poi["id"])


func test_every_note_at_a_point_of_interest_can_be_picked_up_and_read() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_NOTES))
	assert_true(typeof(parsed) == TYPE_ARRAY and not (parsed as Array).is_empty(), "the notes are written")
	if typeof(parsed) != TYPE_ARRAY:
		return
	for enc in parsed:
		var place := str((enc as Dictionary).get("place", ""))
		assert_true(ContentDB.has(place), "a note lies at %s, which is nowhere" % place)
		assert_true(((enc as Dictionary).get("spawns", []) as Array).is_empty(), "%s: a note stands nobody up" % place)
		for l in (enc as Dictionary).get("lies", []):
			var item := ContentDB.get_or_empty(str((l as Dictionary).get("item", "")))
			assert_false(item.is_empty(), "%s: the note lying there is no item" % place)
			assert_true(ContentDB.has(str(item.get("reads", ""))), "%s: %s reads nothing" % [place, item.get("id", "")])
			var row_found := false
			for row in QuestItems.placements():
				row_found = row_found or (str(row["where"]) == place and str(row.get("item", "")) == str(item.get("id", "")))
			assert_true(row_found, "%s: nothing puts %s down" % [place, item.get("id", "")])


## Every objective of every authored quest names something the built game has: a place with a
## position to reach, a person who lives somewhere, a foe something stands up where the fight is,
## an item the game places, gives or sells. `QuestWalk` says how; this says it resolves.
func test_every_objective_resolves_to_a_place_a_person_a_spawn_or_an_item() -> void:
	var rows := QuestWalk.objectives()
	assert_gt(rows.size(), 300, "the walk walked the pack")
	for r in rows:
		assert_true(bool(r["ok"]), "%s / %s: %s %s does not resolve: %s" % [r["quest_id"], r["stage_id"], r["type"],
				r["target"], r["how"]])


## The quests written with the map: 3 to 7 stages, a decision somebody has to make, two to four
## locations, and every where, marker and escort written as a place id, never as a coordinate.
func test_the_maps_quests_link_places_and_ask_for_a_decision() -> void:
	var quests := _map_quests()
	assert_gt(quests.size(), 35, "the map's quests are written")
	for def_v in quests:
		var def: Dictionary = def_v
		var qid := str(def["id"])
		var stages: Array = def.get("stages", [])
		assert_true(stages.size() >= 3 and stages.size() <= 7, "%s has %d stages" % [qid, stages.size()])
		var decides := false
		var places: Dictionary = {}
		places[str(ContentDB.get_or_empty(str(def.get("giver", ""))).get("home_place", ""))] = true
		for stage_v in stages:
			var stage: Dictionary = stage_v
			var marker: Variant = stage.get("marker")
			if typeof(marker) == TYPE_DICTIONARY:
				var at: Variant = (marker as Dictionary).get("place_id", "")
				assert_true(typeof(at) == TYPE_STRING and Ids.looks_like_id(str(at)), "%s marks a coordinate" % qid)
			for o_v in stage.get("objectives", []):
				var o: Dictionary = o_v
				decides = decides or str(o.get("type", "")) == "choice"
				for key in ["where", "place"]:
					if o.has(key):
						assert_true(typeof(o[key]) == TYPE_STRING and Ids.looks_like_id(str(o[key])),
								"%s: %s is not a place id" % [qid, key])
				for key in ["target", "where", "place"]:
					var v := str(o.get(key, ""))
					if Ids.type_of(v) == "place" or Ids.type_of(v) == "poi":
						places[v] = true
		assert_true(decides, "%s asks nobody to decide anything" % qid)
		assert_true(places.size() >= 2, "%s links %d locations" % [qid, places.size()])
