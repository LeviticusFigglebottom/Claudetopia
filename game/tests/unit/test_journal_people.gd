extends TestCase
## The People page: the journal keeps who you have met, what they are to you, and the one
## thing each of them does that nobody else does. Every NPC in the pack carries a `bio` and a
## `unique_habit` and until now no screen had ever shown a line of either.

const WREN := "core:npc/wren_tallow"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	GameState.set_flag("met:" + WREN, false)


# --- content -----------------------------------------------------------------------------------

func test_every_npc_is_written_up() -> void:
	for def in ContentDB.all("npc"):
		if bool(def.get("example", false)) or def.get("tags", []).has("guard"):
			continue          # a guard def is a post the law fills, not somebody with a life
		var id := str(def["id"])
		assert_gt(str(def.get("bio", def.get("lore", ""))).length(), 20, "%s has no write-up" % id)
		assert_gt(str(def.get("unique_habit", "")).length(), 20, "%s has no habit of their own" % id)


func test_no_two_people_share_a_habit() -> void:
	var seen := {}
	for def in ContentDB.all("npc"):
		if bool(def.get("example", false)) or def.get("tags", []).has("guard"):
			continue
		var habit := str(def.get("unique_habit", ""))
		assert_false(seen.has(habit), "%s and %s do the same unique thing" % [def["id"], seen.get(habit, "?")])
		seen[habit] = str(def["id"])


# --- meeting them --------------------------------------------------------------------------------

func test_talking_to_somebody_writes_them_into_the_journal() -> void:
	var runner: Node = preload("res://systems/dialogue/dialogue_runner.gd").new()
	_tree().root.add_child(runner)
	runner.ctx.set_provider("flags", GameState)
	assert_false(GameState.has_flag("met:" + WREN))
	runner.start_def({"id": "core:dialogue/_test_met", "start": "hi",
		"nodes": {"hi": {"speaker": "npc", "text": "Aye."}}}, WREN, "")
	assert_true(GameState.has_flag("met:" + WREN), "one conversation is enough")
	runner.stop()
	_tree().root.remove_child(runner)
	runner.free()


func test_the_page_lists_who_you_have_met_and_says_how_they_feel() -> void:
	var journal: Control = preload("res://ui/journal/journal.tscn").instantiate()
	_tree().root.add_child(journal)
	var people_tab: int = journal.TABS.find("People")
	assert_true(people_tab >= 0, "the journal has a People page")
	journal.setup({"tab": people_tab})
	var listed := 0
	for e in journal._entries:
		listed += 1
	assert_eq(listed, 0, "nobody has been met yet")
	GameState.set_flag("met:" + WREN, true)
	journal.setup({"tab": people_tab})
	var found := {}
	for e in journal._entries:
		found[str(e["id"])] = e
	assert_true(found.has(WREN), "and Wren is on the page once you have spoken to her")
	assert_eq(str(found[WREN]["def"]["bio"]), str(ContentDB.get_or_empty(WREN)["bio"]))
	_tree().root.remove_child(journal)
	journal.free()


func test_feeling_is_put_in_words_not_numbers() -> void:
	var journal_script := preload("res://ui/journal/journal.gd")
	assert_eq(journal_script._feeling_word(80), "Would stand up for you")
	assert_eq(journal_script._feeling_word(0), "Civil")
	assert_eq(journal_script._feeling_word(-90), "Would shut the door")
