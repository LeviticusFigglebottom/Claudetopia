extends TestCase
## The quest notice (QuestNotice, QuestNoticeQueue). The owner: "make objective transitions appear on
## screen like Oblivion does it; almost every starter quest progresses from point-to-point with no
## clear reason why, or the bit that pops up is small and disappears". A quest taken, moved on or
## finished is said near the top of the screen: its name, a head, the objective large and the
## reason, held long enough to read, several in turn, and never spent under a conversation or a film.
## And every stage of the four style starts and their tie-ins has a reason line to show.

const SIDE := "core:quest/_notice_side"
const OTHER := "core:quest/_notice_other"
## The tracker's right edge on the canvas (the HUD sets it 22 px in, QuestTracker.WIDTH wide).
const TRACKER_EDGE := 22.0 + QuestTracker.WIDTH
const STARTERS := ["core:quest/first_warrior", "core:quest/the_relief", "core:quest/first_ranger",
		"core:quest/the_grey_hart", "core:quest/first_mage", "core:quest/the_note_under_the_water",
		"core:quest/first_rogue", "core:quest/the_unsaid_page"]

var log_node: Node
var _nodes: Array[Node] = []
var _setting_was: Variant = null


func before_each() -> void:
	log_node = Social.quests
	log_node.reset_for_new_game()
	QuestNotice.forget_recent()
	log_node.call("register_runtime", _fixture(SIDE, "Fixture Notice"))
	log_node.call("register_runtime", _fixture(OTHER, "Fixture Other"))
	_setting_was = Settings.get_value("gameplay", "quest_notice_time", 1.0)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Settings.set_value("gameplay", "quest_notice_time", _setting_was)
	log_node.reset_for_new_game()
	QuestNotice.forget_recent()


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _fixture(id: String, name_of: String) -> Dictionary:
	return {"id": id, "name": name_of, "layer": "side",
		"stages": [
			{"id": "first", "journal": "The pens are open, and the Sergeant wants the strays back before dark.",
				"objectives": [{"type": "reach", "target": "core:place/wardens_rest"}]},
			{"id": "last", "journal": "The strays are in. Back to the Sergeant with the count.",
				"objectives": [{"type": "reach", "target": "core:place/merrowby"}]}]}


static func _note(quest: String, kind := "updated", objective := "Go to the pens", why := "") -> Dictionary:
	return {"quest": quest, "kind": kind, "name": quest, "objective": objective, "why": why, "tier": "side"}


func _hud() -> Control:
	var hud: Control = (load(UI.HUD_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(hud)
	_nodes.append(hud)
	return hud


# --- the timing --------------------------------------------------------------------------------------

func test_a_notice_is_held_long_enough_to_read_by_its_words() -> void:
	var short := QuestNoticeQueue.hold_seconds("Go home", "")
	var long := QuestNoticeQueue.hold_seconds("Put down the two ash-wights on the bridge road",
			"Tam is waiting for you at the Glass Bridge on the pay's road south, and two grey things have come up from under its arch at him.")
	assert_near(short, QuestNoticeQueue.MIN_HOLD_S, 0.001, "never under six seconds at full ink")
	assert_gt(long, short, "more words, longer")
	assert_true(long <= QuestNoticeQueue.MAX_HOLD_S + 0.001, "never over ten: %.1f" % long)
	assert_gt(long, 8.0, "a long reason is given most of the ten: %.1f" % long)
	assert_near(QuestNoticeQueue.hold_seconds("Go home", "", 1.5), QuestNoticeQueue.MIN_HOLD_S * 1.5, 0.001,
			"the setting scales it")


func test_it_inks_in_holds_and_fades_on_the_clock() -> void:
	var q := QuestNoticeQueue.new()
	q.push(_note("a"))
	q.step(0.0, false)
	assert_eq(str(q.current().get("quest", "")), "a", "up at once on a clear screen")
	q.step(QuestNoticeQueue.FADE_IN_S * 0.5, false)
	assert_true(q.alpha() > 0.3 and q.alpha() < 0.7, "inking in: %.2f" % q.alpha())
	q.step(QuestNoticeQueue.FADE_IN_S, false)
	assert_near(q.alpha(), 1.0, 0.001, "full ink")
	# at full ink for the whole hold
	var held := 0.0
	while q.alpha() >= 0.999 and held < 30.0:
		q.step(0.1, false)
		held += 0.1
	assert_gt(held, QuestNoticeQueue.MIN_HOLD_S - 0.6, "held at full ink for %.1f s" % held)
	assert_false(q.current().is_empty(), "then fading, still up")
	q.step(QuestNoticeQueue.FADE_OUT_S + 0.1, false)
	assert_true(q.current().is_empty(), "and gone")


# --- the queue ---------------------------------------------------------------------------------------

func test_several_wait_their_turn_and_none_writes_over_another() -> void:
	var q := QuestNoticeQueue.new()
	q.push(_note("a", "complete", ""))
	q.push(_note("b", "started"))
	q.push(_note("c", "updated"))
	q.step(0.0, false)
	var seen: Array[String] = []
	var t := 0.0
	while t < 60.0:
		var cur := str(q.current().get("quest", ""))
		if cur != "" and (seen.is_empty() or seen[-1] != cur):
			seen.append(cur)
		q.step(0.1, false)
		t += 0.1
	assert_eq(seen, ["a", "b", "c"] as Array[String], "each in its turn, in order")
	assert_true(q.is_empty())


func test_a_quest_moved_on_at_once_shows_its_latest_objective_and_says_it_started() -> void:
	var q := QuestNoticeQueue.new()
	q.push(_note("a", "started", "Speak to the Warden"))
	q.push(_note("a", "updated", "Walk the waystones north"))
	q.step(0.0, false)
	assert_eq(q.pending().size(), 0, "the stale one is not kept to be read")
	assert_eq(str(q.current()["objective"]), "Walk the waystones north")
	assert_eq(str(q.current()["kind"]), "started", "a quest taken and moved on in a moment is still news")
	# one already up a moment gives way the same
	q.step(0.5, false)
	assert_true(q.push(_note("a", "updated", "Rest at the Ash")), "it takes the place of the one up now")
	assert_eq(str(q.current()["objective"]), "Rest at the Ash")
	# one up longer than that is read through; the next waits
	q.step(QuestNoticeQueue.SUPERSEDE_S + 0.5, false)
	assert_false(q.push(_note("a", "updated", "Go down the stair")))
	assert_eq(str(q.current()["objective"]), "Rest at the Ash", "not written over")
	assert_eq(q.pending().size(), 1, "waiting its turn")
	# a completion takes the place of its own quest's update still waiting
	q.push(_note("a", "complete", ""))
	assert_eq(q.pending().size(), 1)
	assert_eq(str(q.pending()[0]["kind"]), "complete")


func test_nothing_is_spent_under_a_conversation_or_a_film() -> void:
	var q := QuestNoticeQueue.new()
	q.push(_note("a"))
	for i in 200:
		q.step(0.1, true)
	assert_true(q.current().is_empty(), "twenty seconds of a conversation: not shown under it")
	assert_eq(q.pending().size(), 1, "still waiting")
	q.step(QuestNoticeQueue.SETTLE_S * 0.5, false)
	assert_true(q.current().is_empty(), "the screen settles a moment first")
	q.step(QuestNoticeQueue.SETTLE_S, false)
	assert_eq(str(q.current().get("quest", "")), "a", "then it comes up")
	# taken down half read by a film, shown again in full after
	q.step(QuestNoticeQueue.FADE_IN_S + 3.0, false)
	q.step(0.1, true)
	assert_true(q.current().is_empty(), "not under the film")
	q.step(QuestNoticeQueue.SETTLE_S + 0.05, false)
	assert_eq(str(q.current().get("quest", "")), "a")
	assert_true(q.age() < 0.2, "from the start again: %.2f" % q.age())


# --- on the HUD --------------------------------------------------------------------------------------

class FakeRunner:
	extends Node
	var running := true

	func _init() -> void:
		add_to_group("dialogue_runner")

	func is_running() -> bool:
		return running


class FakeFilm:
	extends Node
	var playing := true

	func _init() -> void:
		add_to_group(CinematicPlayer.GROUP)

	func is_playing() -> bool:
		return playing


func test_the_hud_holds_a_notice_back_while_a_conversation_or_a_film_is_up() -> void:
	var hud := _hud()
	var notice: QuestNotice = hud.call("quest_notice")
	var runner := FakeRunner.new()
	_tree().root.add_child(runner)
	_nodes.append(runner)
	assert_true(notice.screen_taken(), "a conversation has the screen")
	log_node.call("start", SIDE)
	for i in 5:
		await _tree().process_frame
	assert_true((hud.call("quest_notice_shown") as Dictionary).is_empty(), "nothing over the conversation")
	runner.running = false
	var film := FakeFilm.new()
	_tree().root.add_child(film)
	_nodes.append(film)
	assert_true(notice.screen_taken(), "nor over a film")
	notice.advance(2.0, notice.screen_taken())
	assert_true((hud.call("quest_notice_shown") as Dictionary).is_empty())
	film.playing = false
	assert_false(notice.screen_taken(), "the screen is the player's again")
	notice.advance(QuestNoticeQueue.SETTLE_S + 0.2, notice.screen_taken())
	var n: Dictionary = hud.call("quest_notice_shown")
	assert_eq(str(n.get("head", "")), "QUEST STARTED  ·  SIDE QUEST", str(n))
	assert_eq(str(n.get("name", "")), "Fixture Notice")
	assert_eq(str(n.get("objective", "")), str(hud.call("objective_text", SIDE)))
	assert_eq(str(n.get("why", "")), "The pens are open, and the Sergeant wants the strays back before dark.")


func test_the_plate_is_large_near_the_top_and_clear_of_the_crosshair() -> void:
	var hud := _hud()
	log_node.call("start", SIDE)
	var notice: QuestNotice = hud.call("quest_notice")
	notice.advance(1.0)
	for i in 3:
		await _tree().process_frame
	var n: Dictionary = hud.call("quest_notice_shown")
	assert_false(n.is_empty(), "up")
	assert_near(float(n["alpha"]), 1.0, 0.01, "at full ink")
	var view := hud.get_viewport_rect().size
	var r := notice.plate_rect()
	assert_gt(r.size.x, 400.0, "a plate, not a line: %s" % str(r))
	assert_true(r.position.y >= 70.0, "under the compass: %s" % str(r))
	assert_near(r.get_center().x, view.x * 0.5, 4.0, "in the middle of the screen: %s in %s" % [str(r), str(view)])
	assert_true(r.position.x >= TRACKER_EDGE or notice.over_tracker, "beside the tracker, not over it: %s" % str(r))
	assert_true(r.end.y < view.y * 0.5 - 40.0, "clear of the crosshair at the middle: %s in %s" % [str(r), str(view)])
	var objective := notice.find_child("Objective", true, false) as Label
	assert_true(objective.get_theme_font_size("font_size") >= 22, "the objective is large")
	assert_true(str(n.get("hint", "")).contains(Settings.prompt_for("journal")) and str(n["hint"]).contains("Journal"),
			"and says the journal's key: %s" % str(n.get("hint", "")))


func test_the_journal_key_opens_at_the_notices_quest() -> void:
	var hud := _hud()
	log_node.call("start", SIDE)
	log_node.call("start", OTHER)
	var notice: QuestNotice = hud.call("quest_notice")
	notice.advance(0.5)
	assert_eq(str((hud.call("quest_notice_shown") as Dictionary).get("quest", "")), SIDE, "the first taken first")
	assert_eq(QuestNotice.recent_quest(), SIDE)
	notice.advance(QuestNoticeQueue.FADE_IN_S + QuestNoticeQueue.MAX_HOLD_S + QuestNoticeQueue.FADE_OUT_S + QuestNoticeQueue.GAP_S + 0.5)
	assert_eq(str((hud.call("quest_notice_shown") as Dictionary).get("quest", "")), OTHER, "then the second, in turn")
	var journal: Control = (load("res://ui/journal/journal.tscn") as PackedScene).instantiate()
	journal.call("setup", {})
	_tree().root.add_child(journal)
	_nodes.append(journal)
	assert_eq(str(journal.call("selected_entry")), OTHER, "the journal opens at the quest the notice is about")
	journal.call("setup", {"tab": 0, "quest": SIDE})
	assert_eq(str(journal.call("selected_entry")), SIDE, "or at the quest it is asked for")


func test_the_followed_quests_rows_and_pins_glow_with_its_notice() -> void:
	var hud := _hud()
	log_node.call("start", SIDE)
	log_node.call("track", SIDE)
	var notice: QuestNotice = hud.call("quest_notice")
	notice.advance(0.2)
	var tracker: QuestTracker = hud.get("_tracker")
	var compass: Compass = hud.get("_compass")
	assert_gt(tracker.announced_ms(), -1, "the tracker's quest is announced as the notice comes up")
	assert_gt(compass.pin_glow(), 0.0, "and the strip's pins glow")
	for i in 3:
		await _tree().process_frame
	assert_true(tracker.rows_glowing(), "the new objective's row glows on the tracker")


func test_the_setting_lengthens_it() -> void:
	var hud := _hud()
	var notice: QuestNotice = hud.call("quest_notice")
	Settings.set_value("gameplay", "quest_notice_time", 1.5)
	assert_near(notice.queue.hold_scale, 1.5, 0.001)
	Settings.set_value("gameplay", "quest_notice_time", 1.0)
	assert_near(notice.queue.hold_scale, 1.0, 0.001)


# --- the content -------------------------------------------------------------------------------------

## Every stage of the four style starts and their tie-ins opens its journal on a reason line: why you
## are now going there, said whole on the notice (not cut), no tokens, and every stage that asks
## something has an objective to show under it.
func test_every_starter_stage_has_a_reason_line() -> void:
	var lines := {}
	for id: String in STARTERS:
		var def := ContentDB.get_or_empty(id)
		assert_false(def.is_empty(), "%s is in the pack" % id)
		for s in def.get("stages", []):
			var stage: Dictionary = s
			var where := "%s/%s" % [id, str(stage.get("id", ""))]
			var journal := str(stage.get("journal", "")).strip_edges()
			var first := journal.split("\n", false)[0] if journal != "" else ""
			assert_true(first.length() >= 40, "%s opens on a reason, not a fragment: '%s'" % [where, first])
			assert_eq(QuestCues.first_line(journal), first, "%s: its reason is shown whole (at most 170 letters, %d)" % [where, first.length()])
			assert_false(first.contains("{"), "%s: no token in the reason" % where)
			assert_false(lines.has(first), "%s: its reason is its own, not %s's" % [where, str(lines.get(first, ""))])
			lines[first] = where
			assert_false((stage.get("objectives", []) as Array).is_empty(), "%s has an objective to show" % where)


func test_a_new_games_first_quest_begun_before_the_hud_is_announced_as_it_comes_up() -> void:
	# the opening begins the first quest under its black, before the HUD stands: its "Quest started"
	# was heard by nobody, and the first objective was never shown (flow, 2026-10-03)
	var quests: Node = Social.quests
	quests.call("reset_for_new_game")
	var had := GameState.has_flag("new_game")
	GameState.set_flag("new_game", true)
	quests.call("start", "core:quest/the_naming", "wake")
	var hud: Node = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	_tree().root.add_child(hud)
	await _tree().process_frame
	await _tree().process_frame
	var notice: QuestNotice = hud.get_node("QuestNotice")
	assert_true(notice.has_quest("core:quest/the_naming"), "the quest begun before the HUD is told as it comes up")
	hud.queue_free()
	quests.call("reset_for_new_game")
	GameState.set_flag("new_game", had)


func test_a_slow_frame_does_not_stretch_the_wait_before_a_notice() -> void:
	# frames of 3 s (a slow machine) after a film: the 0.6 s settle is the frame's own time, not
	# 0.25 s capped steps that made it a dozen seconds; the read itself stays capped
	var q := QuestNoticeQueue.new()
	q.push({"quest": "q", "kind": "started", "objective": "Go", "why": ""})
	q.step(0.25, true, 3.0)
	assert_true(q.current().is_empty(), "nothing while the screen is taken")
	q.step(0.25, false, 3.0)
	assert_false(q.current().is_empty(), "up on the first clear frame of 3 s")
	var held := q.held_seconds()
	q.step(0.25, false, 3.0)
	assert_false(q.current().is_empty(), "and still up a capped step later (%.1f s held)" % held)
