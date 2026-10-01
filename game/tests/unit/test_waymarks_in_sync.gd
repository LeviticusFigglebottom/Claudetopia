extends TestCase
## Triage 79: every quest's marker in step with its objective now. The HUD's tracker and compass
## (tracked_waymarks), and the chart's areas (active_markers), are read through a quest's life:
## a stage moving on, a step done, a try that fails and is tried again (the Rogue's watch), a save
## and a load, and a quest that fails. Nothing they show may be a step that is done, not yet
## reached, or of a quest that has ended.

const ROGUE := "core:quest/first_rogue"
const SAUVE := "core:npc/sauve_mor"
const STEPS := "test:quest/two_steps_for_the_waymark_test"

var _cam: Camera3D = null
var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(80)
	Social.quests.call("reset_for_new_game")


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	if _cam != null and is_instance_valid(_cam):
		_cam.get_parent().remove_child(_cam)
		_cam.free()
	_cam = null
	Social.quests.call("reset_for_new_game")
	GameState.reset_for_new_game(80)


class _Watcher extends Node3D:
	var detection := 0.0


func _hud_at(place: String) -> Node:
	var at := WorldProbe.place_position(place)
	_cam = Camera3D.new()
	_tree().root.add_child(_cam)
	_cam.global_position = Vector3(at.x + 30.0, at.y + 2.0, at.z + 30.0)
	_cam.current = true
	var hud: Node = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	_tree().root.add_child(hud)
	_nodes.append(hud)
	return hud


func _texts(hud: Node) -> Array[String]:
	var out: Array[String] = []
	for w in hud.call("tracked_waymarks"):
		out.append(str((w as Dictionary)["text"]))
	return out


## The tracked rows are the current stage's open, reached objectives, each pointing somewhere.
func _in_step(quest_id: String, why: String) -> void:
	var rows: Array = Social.quests.call("tracked_objectives")
	var open: Array = (Social.quests.call("objectives_of", quest_id) as Array).filter(
			func(o: Dictionary) -> bool: return not bool(o["done"]) and not bool(o["veiled"]))
	var shown: Array = rows.filter(func(o: Dictionary) -> bool: return not bool(o["done"]))
	assert_eq(shown.size(), open.size(), "%s: the tracker lists the open steps (%s)" % [why, str(shown.map(func(o: Dictionary) -> String: return str(o["text"])))])
	for r in shown:
		var a: Dictionary = (r as Dictionary)["anchor"]
		assert_true(str(a.get("kind", "")) not in ["none", ""], "%s: '%s' points somewhere (%s)" % [why, str(r["text"]), str(a)])
		assert_eq(str(r["quest_id"]), quest_id)


func test_the_rogue_s_marker_follows_the_watch_s_fail_and_the_try_again() -> void:
	var hud := _hud_at("core:place/moreva")
	Social.quests.call("start", ROGUE)
	Social.quests.call("set_stage", ROGUE, "the_traps")
	_in_step(ROGUE, "the traps")
	var before := _texts(hud)
	assert_eq(before.size(), 1)
	assert_true(before[0].begins_with("Take the book down to Sauve"), str(before))
	var watch := NightWatch.new()
	_tree().root.add_child(watch)
	_nodes.append(watch)
	var tella := _Watcher.new()
	_tree().root.add_child(tella)
	_nodes.append(tella)
	watch.watcher = tella
	watch.refresh()
	tella.detection = 0.8
	assert_eq(watch.refresh(), "seen")
	_in_step(ROGUE, "seen")
	var seen := _texts(hud)
	assert_eq(seen.size(), 1, "one step, and not the traps' any more: %s" % str(seen))
	assert_true(seen[0].begins_with("Seen: go back to Sauve"), str(seen))
	var rows: Array = Social.quests.call("tracked_objectives")
	assert_eq(str((rows[0]["anchor"] as Dictionary).get("npc", "")), SAUVE, "the marker is on Sauve")
	for r in (hud.call("tracker_shown") as Dictionary)["rows"]:
		assert_false(str((r as Dictionary)["text"]).begins_with("Take the book down") and bool(r["done"]),
				"the spoilt try is not ticked off as done: %s" % str(r))
	# saved and loaded on the fail: the same step, the same mark
	var saved: Dictionary = Social.quests.call("to_save")
	Social.quests.call("reset_for_new_game")
	assert_eq(_texts(hud).size(), 0, "a new game shows nothing of it")
	Social.quests.call("from_save", saved)
	assert_eq(_texts(hud), seen, "loaded, the marker is where it was")
	_in_step(ROGUE, "seen, loaded")
	# tried again: back to the traps' step
	EventBus.dialogue_node_entered.emit(SAUVE, "traps_again")
	_in_step(ROGUE, "tried again")
	assert_eq(_texts(hud), before, "the try again marks the traps again")
	# a quest that ends shows nothing more, here or on the chart
	Social.quests.call("fail", ROGUE, "a test")
	assert_eq(_texts(hud).size(), 0, "a failed quest has no marker left")
	for m in Social.quests.call("active_markers"):
		assert_true(str((m as Dictionary).get("quest_id", "")) != ROGUE, "nor an area on the chart")


func test_a_step_done_leaves_the_markers_and_one_not_reached_is_kept_back() -> void:
	var def := {"id": STEPS, "name": "Two Steps", "layer": "side", "stages": [
			{"id": "both", "journal": "x", "objectives": [
				{"type": "reach", "target": "core:place/moreva", "radius": 20, "text": "Go to Moreva"},
				{"type": "talk", "target": SAUVE, "after": 0, "text": "Then speak to Sauve"}]},
			{"id": "last", "journal": "y", "objectives": [
				{"type": "reach", "target": "core:place/merrowby", "text": "Go on to Merrowby"}]}]}
	assert_true(bool(Social.quests.call("register_runtime", def)))
	var hud := _hud_at("core:place/moreva")
	Social.quests.call("start", STEPS)
	Social.quests.call("track", STEPS)
	_in_step(STEPS, "the first step")
	assert_eq(_texts(hud), ["Go to Moreva"] as Array[String], "the step after is kept back")
	var areas: Array = (Social.quests.call("active_markers") as Array).filter(func(m: Dictionary) -> bool: return str(m["quest_id"]) == STEPS)
	assert_eq(areas.size(), 1, "the chart keeps it back too: %s" % str(areas))
	Social.quests.call("complete_objective", STEPS, 0)
	_in_step(STEPS, "the first step done")
	assert_eq(_texts(hud), ["Then speak to Sauve"] as Array[String], "done, the next takes its place")
	areas = (Social.quests.call("active_markers") as Array).filter(func(m: Dictionary) -> bool: return str(m["quest_id"]) == STEPS)
	assert_eq(areas.size(), 1)
	assert_eq(str(areas[0].get("place_id", "")), str(ContentDB.get_or_empty(SAUVE).get("home_place", "")), "the area is Sauve's, not Moreva's reach")
	Social.quests.call("complete_objective", STEPS, 1)
	_in_step(STEPS, "the stage moved on")
	assert_eq(_texts(hud), ["Go on to Merrowby"] as Array[String], "the next stage's step, at once")
	Social.quests.call("complete_objective", STEPS, 0)
	assert_true(bool(Social.quests.call("is_completed", STEPS)))
	assert_eq(_texts(hud).size(), 0, "a finished quest's marker is cleared")
