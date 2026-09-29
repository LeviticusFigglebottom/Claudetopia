extends TestCase
## Waymarks and the tracker (DESIGN §5.16). The user: "Intro quest also doesn't give a waymarker to
## pilgrim's ash, and an active quest should have a small hud element showing current step with
## distance (x meters away) and completion (0/4 enemies, etc)".
##
## The audit walks every objective of every stage of every authored quest and asks where it points;
## a new objective that points nowhere fails it, unless it says `"hidden": true` and why.

const NAMING := "core:quest/the_naming"
const BRAMBLE := "core:quest/bramble"
const STAIR_HEAD := "core:poi/stair_head"
const CHOIR := "core:place/sunken_choir"
const PILGRIMS_ASH := "core:place/pilgrims_ash"
const WREN := "core:npc/wren_tallow"

var log_node: Node
var _cam: Camera3D = null


func before_each() -> void:
	log_node = Social.quests
	log_node.reset_for_new_game()


func after_each() -> void:
	log_node.reset_for_new_game()
	for flag in ["woke_at_hushline", "met_wren", "named", "walked_to_the_choir", "first_hearthstone"]:
		GameState.clear_flag(flag)
	if _cam != null and is_instance_valid(_cam):
		_cam.get_parent().remove_child(_cam)
		_cam.free()
	_cam = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _stage(quest_id: String, stage_id: String) -> Dictionary:
	for s in ContentDB.get_or_empty(quest_id).get("stages", []):
		if str((s as Dictionary).get("id", "")) == stage_id:
			return s
	return {}


func _anchor(quest_id: String, stage_id: String, index: int) -> Dictionary:
	var stage := _stage(quest_id, stage_id)
	return Waymarks.anchor(ContentDB.get_or_empty(quest_id), stage, (stage["objectives"] as Array)[index])


# --- the audit ---------------------------------------------------------------------------------

func test_every_objective_of_every_quest_points_somewhere() -> void:
	var rows := Waymarks.audit()
	assert_gt(rows.size(), 400, "the walk covers the pack (%d objectives)" % rows.size())
	var nowhere: Array[String] = []
	var hidden := 0
	for r in rows:
		if str(r["kind"]) == "hidden":
			hidden += 1
			if str(r["why"]).strip_edges() == "":
				nowhere.append("%s / %s #%d: hidden without saying why" % [Ids.name_of(str(r["quest_id"])), r["stage_id"], r["index"]])
			continue
		var xz: Vector2 = r["xz"]
		if xz == Vector2.INF:
			nowhere.append("%s / %s #%d [%s %s]: %s (%s)" % [Ids.name_of(str(r["quest_id"])), r["stage_id"], r["index"],
					r["type"], r["target"], r["kind"], r["why"]])
	print("  waymarks: %d objectives, %d point nowhere, %d hidden on purpose" % [rows.size(), nowhere.size(), hidden])
	for line in nowhere:
		print("    NOWHERE " + line)
	assert_empty(nowhere, "every objective points at something that stands in the world")


# --- what an objective points at -----------------------------------------------------------------

func test_a_reach_points_at_its_place() -> void:
	var a := _anchor(NAMING, "the_choir", 0)
	assert_eq(str(a["kind"]), "place")
	assert_eq(str(a["place"]), CHOIR)
	assert_eq(Waymarks.map_xz_of(a), PlaceRef.xz(CHOIR))


func test_a_marker_overrides_the_target() -> void:
	var a := _anchor(NAMING, "wake", 0)
	assert_eq(str(a["kind"]), "place", "the Warden's talk is marked at her fire")
	assert_eq(str(a["place"]), STAIR_HEAD)
	assert_near(float(a["radius"]), 30.0, 0.01)


func test_a_talk_points_at_the_person() -> void:
	var a := _anchor("core:quest/the_toll_hums", "arrive", 0)
	assert_eq(str(a["kind"]), "npc")
	assert_eq(str(a["npc"]), WREN)
	assert_ne(Waymarks.map_xz_of(a), Vector2.INF, "she lives somewhere on the map")


func test_a_kill_points_at_its_foes_where_the_story_puts_them() -> void:
	var a := _anchor(NAMING, "ash_wights", 0)
	assert_eq(str(a["kind"]), "foes")
	assert_eq(str(a["enemy"]), "core:enemy/ash_wight")
	assert_eq(str(a["where"]), CHOIR)
	assert_eq(str(a["about"]), "ash-wights", "named from the definition, several of them")
	assert_eq(Waymarks.map_xz_of(a), PlaceRef.xz(CHOIR))


func test_a_hidden_objective_says_why_and_points_nowhere() -> void:
	var a := Waymarks.anchor({"id": "core:quest/_t"}, {}, {"type": "reach", "target": CHOIR, "hidden": true,
			"hidden_why": "found by following the bells"})
	assert_eq(str(a["kind"]), "hidden")
	assert_eq(str(a["why"]), "found by following the bells")
	assert_false(bool(Waymarks.locate(a).get("ok", true)), "the world does not point at it")


func test_the_nearest_living_foe_of_the_kind_is_pointed_at() -> void:
	var a := {"kind": "foes", "enemy": "core:enemy/ash_wight", "where": CHOIR, "radius": 140.0, "about": "ash-wights"}
	var choir := WorldProbe.place_position(CHOIR)
	var none := Waymarks.locate(a, choir + Vector3(0, 0, 300))
	assert_true(bool(none["ok"]))
	assert_near(Waymarks._flat(none["at"], choir), 0.0, 0.5, "with nobody stood up yet, the place of the fight")
	var host := Node3D.new()
	_tree().root.add_child(host)
	var near := _fake_foe(host, "core:enemy/ash_wight", choir + Vector3(10, 0, 20))
	_fake_foe(host, "core:enemy/ash_wight", choir + Vector3(-10, 0, -30))
	_fake_foe(host, "core:enemy/down_wolf", choir + Vector3(0, 0, 25))
	var dead := _fake_foe(host, "core:enemy/ash_wight", choir + Vector3(0, 0, 60))
	dead.set("dead", true)
	var got := Waymarks.locate(a, choir + Vector3(0, 0, 100))
	assert_true(bool(got["live"]), "a body, not a place")
	assert_near(Waymarks._flat(got["at"], near.global_position), 0.0, 0.01, "the nearest living ash-wight, not the wolf or the dead")
	host.get_parent().remove_child(host)
	host.free()


## An Enemy with just the members Waymarks reads.
func _fake_foe(host: Node3D, id: String, at: Vector3) -> Node3D:
	var e := Node3D.new()
	e.set_script(load("res://tests/fakes/fake_foe.gd"))
	e.set("id", id)
	host.add_child(e)
	e.add_to_group("enemy")
	e.global_position = at
	return e


# --- words ---------------------------------------------------------------------------------------

func test_distance_is_said_sensibly() -> void:
	assert_eq(QuestTracker.distance_text(312.0), "310 m")
	assert_eq(QuestTracker.distance_text(47.0), "45 m")
	assert_eq(QuestTracker.distance_text(2.0), "5 m", "never nought metres")
	assert_eq(QuestTracker.distance_text(996.0), "1.0 km")
	assert_eq(QuestTracker.distance_text(1440.0), "1.4 km")
	assert_eq(QuestTracker.distance_text(12400.0), "12 km")
	assert_eq(QuestTracker.distance_text(40.0, 45.0), "", "within the objective's radius you are there")
	assert_eq(QuestTracker.distance_text(INF), "", "nobody can say")


func test_progress_counts_what_is_left() -> void:
	assert_eq(QuestTracker.progress_text(2, 4, "ash-wights"), "2/4 ash-wights")
	assert_eq(QuestTracker.progress_text(0, 3, "down wolves"), "0/3 down wolves")
	assert_eq(QuestTracker.progress_text(0, 1, "the Hart"), "", "one thing is not counted")
	assert_eq(QuestTracker.progress_text(5, 4, "x"), "4/4 x")
	assert_eq(QuestTracker.detail_text("2/4 ash-wights", "310 m"), "2/4 ash-wights  ·  310 m")
	assert_eq(QuestTracker.detail_text("", "310 m"), "310 m")


func test_names_are_put_in_the_plural() -> void:
	assert_eq(Waymarks.plural("ash-wight"), "ash-wights")
	assert_eq(Waymarks.plural("down wolf"), "down wolves")
	assert_eq(Waymarks.plural("hearth loaf"), "hearth loaves")
	assert_eq(Waymarks.plural("bog-drowned"), "bog-drowned")
	assert_eq(Waymarks.plural("gutter drake"), "gutter drakes")
	assert_eq(Waymarks.plural("wisp"), "wisps")
	assert_eq(Waymarks.plural("poacher"), "poachers")
	assert_eq(Waymarks.plural("bell-bearer"), "bell-bearers")
	assert_eq(Waymarks.plural("berry"), "berries")
	assert_eq(Waymarks.plural("marsh"), "marshes")


func test_a_pin_behind_you_waits_at_the_end_you_would_turn_to() -> void:
	var w := 520.0
	assert_near(Compass.pin_offset(0.0, 0.0, w), 260.0, 0.01, "ahead, in the middle")
	assert_near(Compass.pin_offset(170.0, 0.0, w), w - Compass.PIN_EDGE, 0.01, "behind and to the right: the right end")
	assert_near(Compass.pin_offset(190.0, 0.0, w), Compass.PIN_EDGE, 0.01, "behind and to the left: the left end")


# --- following one quest ----------------------------------------------------------------------------

func test_a_main_quest_takes_the_track_and_the_journal_can_give_it_to_another() -> void:
	assert_eq(str(log_node.call("tracked_quest")), "", "nothing to follow")
	assert_true(bool(log_node.call("start", BRAMBLE)))
	assert_eq(str(log_node.call("tracked_quest")), BRAMBLE, "the only quest is followed")
	assert_true(bool(log_node.call("start", NAMING)))
	assert_eq(str(log_node.call("tracked_quest")), NAMING, "a main quest takes the track")
	assert_true(bool(log_node.call("track", BRAMBLE)))
	assert_eq(str(log_node.call("tracked_quest")), BRAMBLE, "the journal's choice holds")
	log_node.call("set_stage", NAMING, "the_choir")
	assert_eq(str(log_node.call("tracked_quest")), NAMING, "until a new main-quest stage takes it")
	log_node.call("track", BRAMBLE)
	log_node.call("complete", BRAMBLE, "")
	assert_eq(str(log_node.call("tracked_quest")), NAMING, "a quest that ends hands the track on")
	assert_false(bool(log_node.call("track", BRAMBLE)), "an ended quest cannot be followed")


func test_the_choice_is_kept_in_the_save() -> void:
	log_node.call("start", NAMING)
	log_node.call("start", BRAMBLE)
	log_node.call("track", BRAMBLE)
	var saved: Dictionary = log_node.call("to_save")
	assert_eq(str(saved["tracked"]), BRAMBLE)
	log_node.call("reset_for_new_game")
	log_node.call("from_save", JSON.parse_string(JSON.stringify(saved)))
	assert_eq(str(log_node.call("tracked_quest")), BRAMBLE, "loaded as it was saved")
	saved.erase("tracked")
	log_node.call("from_save", saved)
	assert_eq(str(log_node.call("tracked_quest")), NAMING, "a save from before the tracker follows the main quest")


func test_a_v4_save_says_what_is_followed() -> void:
	var m := Migrations.migrate({"schema_version": 4, "sections": {"quests": {"quests": {}}}})
	assert_eq(int(m["schema_version"]), SaveSystem.SCHEMA_VERSION)
	assert_eq(str(m["sections"]["quests"]["tracked"]), "", "written down as nothing chosen")
	var bare := Migrations.migrate({"schema_version": 4, "sections": {}})
	assert_false(bare["sections"].has("quests"), "a save with no quest log grows none")


# --- the opening, on the tracked world -----------------------------------------------------------

## The user's report: after the Naming nothing pointed on to Pilgrim's Ash. Every stage of the
## Naming after the first talk points at a real position, and the one that sends you to Pilgrim's
## Ash points there, on the strip, on the chart and in the tracker.
func test_a_new_game_s_objectives_after_the_naming_point_at_real_places() -> void:
	log_node.call("start", NAMING, "wake")
	var hud := _hud_at(STAIR_HEAD)
	EventBus.dialogue_ended.emit(WREN)
	assert_eq(str(log_node.call("stage_id_of", NAMING)), "the_choir")
	var marks: Array[Dictionary] = hud.call("tracked_waymarks")
	assert_eq(marks.size(), 1)
	assert_true(bool(marks[0]["ok"]), "the walk north points somewhere")
	assert_near((marks[0]["xz"] as Vector2).distance_to(PlaceRef.xz(CHOIR)), 0.0, 1.0, "at the Choir")
	assert_true(str(marks[0]["detail"]).ends_with(" m"), "and says how far: '%s'" % marks[0]["detail"])
	var shown: Dictionary = hud.call("tracker_shown")
	assert_eq(str(shown["title"]), "The Naming", "the tracker names the quest")
	assert_eq(str((shown["rows"] as Array)[0]["text"]), "Walk the waystones north to the Sunken Choir")

	log_node.call("set_stage", NAMING, "ash_wights")
	marks = hud.call("tracked_waymarks")
	assert_true(bool(marks[0]["ok"]), "the ash-wights are pointed at")
	assert_true(PlaceRef.xz(CHOIR).distance_to(marks[0]["xz"]) <= 140.0, "at the Choir, where the story puts them")
	assert_true(str(marks[0]["detail"]).begins_with("0/3 ash-wights"), "counted: '%s'" % marks[0]["detail"])

	log_node.call("set_stage", NAMING, "hearthstone")
	marks = hud.call("tracked_waymarks")
	assert_eq(marks.size(), 2, "arrive, and rest at the stone")
	for m in marks:
		assert_true(bool(m["ok"]), "%s points somewhere" % m["text"])
		assert_near((m["xz"] as Vector2).distance_to(PlaceRef.xz(PILGRIMS_ASH)), 0.0, 1.0,
				"'%s' points at Pilgrim's Ash" % m["text"])
	var pilgrims := PlaceRef.xz(PILGRIMS_ASH)
	var said := str(marks[0]["detail"])
	assert_true(said.ends_with(" m") or said.ends_with(" km"), "the tracker says how far Pilgrim's Ash is: '%s'" % said)
	assert_eq(str(marks[1]["detail"]), "", "and says it once: the second step at the same place has no distance of its own")
	await _tree().process_frame
	# face it: the pin is on the strip
	_cam.look_at(Vector3(pilgrims.x, _cam.global_position.y, pilgrims.y))
	await _tree().process_frame
	await _tree().process_frame
	assert_true(bool(hud.call("quest_marker_on_strip")), "facing Pilgrim's Ash, its pin is on the compass")
	_drop(hud)


## A step done is ticked in the tracker, and the next inks in.
func test_the_tracker_ticks_a_step_and_counts_a_fight() -> void:
	log_node.call("start", BRAMBLE)
	var hud := _hud_at("core:place/chalk_hound")
	log_node.call("set_stage", BRAMBLE, "the_wolves")
	await _tree().process_frame
	var shown: Dictionary = hud.call("tracker_shown")
	assert_eq(str(shown["title"]), "Bramble")
	var rows: Array = shown["rows"]
	assert_eq(rows.size(), 1)
	assert_true(str(rows[0]["detail"]).begins_with("0/3 down wolves"), "'%s'" % rows[0]["detail"])
	log_node.call("complete_objective", BRAMBLE, 0)
	hud.call("tracked_waymarks")
	await _tree().process_frame
	rows = (hud.call("tracker_shown") as Dictionary)["rows"]
	var ticked := false
	for r in rows:
		if bool(r["done"]):
			ticked = true
	assert_true(ticked, "the wolves are ticked off before they go: %s" % str(rows))
	_drop(hud)


func _hud_at(place: String) -> Node:
	var at := WorldProbe.place_position(place)
	_cam = Camera3D.new()
	_tree().root.add_child(_cam)
	_cam.global_position = Vector3(at.x + 400.0, at.y + 2.0, at.z + 300.0)
	_cam.current = true
	var hud: Node = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	_tree().root.add_child(hud)
	return hud


func _drop(hud: Node) -> void:
	_tree().root.remove_child(hud)
	hud.free()


# --- the journal chooses, the chart shows ---------------------------------------------------------

func test_the_journal_s_follow_button_moves_the_track() -> void:
	log_node.call("start", NAMING)
	log_node.call("start", BRAMBLE)
	assert_eq(str(log_node.call("tracked_quest")), NAMING)
	var journal: Control = preload("res://ui/journal/journal.tscn").instantiate()
	_tree().root.add_child(journal)
	journal.setup({"tab": 0})
	journal.set("_selected", BRAMBLE)
	journal.call("_rebuild_detail")
	var follow := journal.find_child("Follow", true, false) as Button
	assert_true(follow != null, "an active quest that is not followed has a Follow button")
	follow.pressed.emit()
	assert_eq(str(log_node.call("tracked_quest")), BRAMBLE, "pressing it follows the quest")
	await _tree().process_frame
	var again := journal.find_child("Follow", true, false)
	assert_true(again == null or again.is_queued_for_deletion(), "and the page says it is followed instead")
	_tree().root.remove_child(journal)
	journal.free()


func test_the_chart_pins_the_tracked_objective_found_or_not() -> void:
	log_node.call("set_stage", NAMING, "hearthstone")
	var chart: Control = preload("res://ui/map/map_screen.tscn").instantiate()
	_tree().root.add_child(chart)
	var pins: Array = chart.call("tracked_pins")
	assert_eq(pins.size(), 2)
	for p in pins:
		assert_near((p["xz"] as Vector2).distance_to(PlaceRef.xz(PILGRIMS_ASH)), 0.0, 1.0, "pinned at Pilgrim's Ash")
	_tree().root.remove_child(chart)
	chart.free()
