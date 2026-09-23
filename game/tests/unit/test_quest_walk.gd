extends TestCase
## Every objective of every quest can be closed by something in the built game.
##
## A green suite said the quest log listened for each objective's event; it did not say anything
## ever sent one. Walking the pack found deliveries with no line to hand them over on, decisions
## with no button, an escort nothing walked, eighteen things nothing put anywhere and a boss nothing
## stood up. `QuestWalk` asks it of every objective; this fails when one cannot be closed and is not
## in `KNOWN` with the reason, and when one in `KNOWN` has since been made closable (so the list
## cannot quietly go stale).
##
## `print_report` in the run's output is the per-quest list the progress notes quote.

## quest|stage|objective index -> why it cannot be closed yet.
const KNOWN := {}

## template|region|token|target -> why a job board could post it and it could not be done.
const KNOWN_RADIANT := {}


func _key(row: Dictionary) -> String:
	return "%s|%s|%d" % [row["quest_id"], row["stage_id"], int(row["index"])]


func test_every_objective_of_every_quest_can_be_closed() -> void:
	var rows := QuestWalk.objectives()
	assert_gt(rows.size(), 200, "the walk walked the pack")
	var cannot: Dictionary = {}
	for row in rows:
		if not bool(row["ok"]):
			cannot[_key(row)] = str(row["how"])
	for key in cannot:
		assert_true(KNOWN.has(key), "%s cannot be closed: %s" % [key, cannot[key]])
	for key in KNOWN:
		assert_true(cannot.has(key), "%s is listed as unclosable and can be closed now; take it off the list" % key)


func test_every_quest_has_something_that_starts_it() -> void:
	for b in QuestWalk.beginnings():
		assert_true(bool(b["ok"]), "%s never begins: %s" % [b["quest_id"], b["how"]])


func test_every_job_a_board_could_post_can_be_done() -> void:
	var rows := QuestWalk.radiant(Social.radiant)
	assert_gt(rows.size(), 20, "the walk asked the boards")
	var cannot: Dictionary = {}
	for row in rows:
		if not bool(row["ok"]):
			cannot["%s|%s|%s|%s" % [row["template"], row["region"], row["token"], row["target"]]] = str(row["how"])
	for key in cannot:
		assert_true(KNOWN_RADIANT.has(key), "a board could post %s and it cannot be done: %s" % [key, cannot[key]])
	for key in KNOWN_RADIANT:
		assert_true(cannot.has(key), "%s can be done now; take it off the list" % key)


## The walk's radiant half found two ways a board could post work that is not work: an escort
## naming a placeholder from the writers' first roster (one of them a dog) or an anonymous watch
## post, and a fetch for goods nothing in the game has. The generator's pools leave both out now.
func test_no_board_names_a_placeholder_a_watch_post_or_goods_nobody_has() -> void:
	var radiant: RadiantGenerator = Social.radiant
	var escort := radiant.template("core:quest/radiant_escort")
	var fetch := radiant.template("core:quest/radiant_fetch")
	assert_false(escort.is_empty() or fetch.is_empty(), "the escort and fetch templates are in the pack")
	for region in ContentDB.all("region"):
		var region_id := str(region["id"])
		var board := radiant.default_board(region_id)
		if board == "":
			continue
		for id in radiant.pool_for(escort["template"]["targets"]["traveller"], region_id, board):
			var def := ContentDB.get_or_empty(id)
			assert_false(bool(def.get("example", false)), "a board in %s could ask you to walk %s, a placeholder" % [region_id, id])
			assert_false((def.get("tags", []) as Array).has("guard"), "a board in %s could ask you to walk %s, a watch post" % [region_id, id])
		for id in radiant.pool_for(fetch["template"]["targets"]["goods"], region_id, board):
			assert_true(ItemSources.sold(id) or ItemSources.rolled(id) or ItemSources.story_gives(id),
					"a board in %s could ask for %s, which nothing gives, sells or drops" % [region_id, id])


## An escort that ends as it begins is not a job: nobody is posted to walk someone to where they live.
func test_no_board_posts_an_escort_to_the_travellers_own_home() -> void:
	var escorts := 0
	for region in ["core:region/hearthvale", "core:region/brightwater", "core:region/sedgemire"]:
		for seed_value in range(1, 120):
			for job in Social.radiant.generate(region, 6, "", seed_value):
				if str(job.get("kind", "")) != "escort":
					continue
				for stage in job["stages"]:
					for o in (stage as Dictionary).get("objectives", []):
						if str((o as Dictionary).get("type", "")) != "escort":
							continue
						escorts += 1
						var home := str(ContentDB.get_or_empty(str(o["target"])).get("home_place", ""))
						assert_ne(home, str(o["place"]), "%s walks %s home to %s" % [job["id"], o["target"], home])
	assert_gt(escorts, 0, "the boards post escorts at all")


func test_the_walk_says_how_as_well_as_whether() -> void:
	# the Hart, the note, the escort and a thing lying in the fallen stair, one of each kind of fix
	var want := {
		"core:quest/the_briars_purpose|the_hart|1": "Moot",
		"core:quest/the_held_note|the_held_note|0": "Cantor",
		"core:quest/vigil|the_pilgrim|1": "walks with you",
		"core:quest/wardens_roll_of_names|the_tumbled_watch|1": "Tumbled Watch",
	}
	var seen: Dictionary = {}
	for row in QuestWalk.objectives():
		var key := _key(row)
		if want.has(key):
			seen[key] = true
			assert_true(bool(row["ok"]), "%s: %s" % [key, row["how"]])
			assert_true(str(row["how"]).contains(str(want[key])), "%s says how: '%s'" % [key, row["how"]])
	assert_eq(seen.size(), want.size(), "every one of them was walked")


func test_print_report() -> void:
	print(QuestWalk.report(true))
	assert_true(true)
