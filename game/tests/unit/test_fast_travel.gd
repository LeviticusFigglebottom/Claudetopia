extends TestCase
## The road between the Hearthstones (playtest 09-27: "fast travel between candles" did not exist).
##
## Resting at a lit stone only rests; then the stone offers the road, its second use, to every
## other lit one, and so does the chart from anywhere (triage 30). Taking it sets the body
## down at that place's arrival, facing the stone, and the clock goes on by the walk. A stone that
## is not lit is not offered, nor one in a cave, and nobody takes the road with a foe on them.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")

var player: Node3D
var _ids: Array[String] = []
var _lit_was: Array[String] = []
var _found_was: Array[String] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	player = FakePlayer.new()
	_tree().root.add_child(player)
	_lit_was = Hearth.lit.duplicate()
	Hearth.lit.clear()
	_found_was = GameState.discovered_places.duplicate()
	GameState.discovered_places.clear()
	_ids.clear()
	var keys := Hearth.stone_places().keys()
	keys.sort()
	for k in keys:
		if str(k).begins_with("core:poi/") and _ids.size() < 3:
			_ids.append(str(k))


func after_each() -> void:
	Hearth.lit.assign(_lit_was)
	GameState.discovered_places.assign(_found_was)
	_tree().root.remove_child(player)
	player.free()


func test_a_lit_stone_offers_the_others_that_are_lit() -> void:
	assert_eq(_ids.size(), 3, "the world has stones out in the country to test with")
	if _ids.size() < 3:
		return
	Hearth.lit.assign([_ids[0], _ids[1]])
	var road := Hearth.travel_targets(_ids[0])
	assert_eq(road.size(), 1, "one other stone is lit, and it is offered")
	assert_eq(str(road[0]["id"]), _ids[1])
	assert_gt(float(road[0]["km"]), 0.0, "with how far it is")
	Hearth.lit.append(_ids[2])
	assert_eq(Hearth.travel_targets(_ids[0]).size(), 2, "a third lit stone joins the road")
	var talk := Hearth.travel_conversation(_ids[0], "Hearthstone")
	var choices: Array = (talk["nodes"]["road"] as Dictionary)["choices"]
	assert_eq(choices.size(), 3, "the two stones and staying")
	assert_eq(str((choices[0]["effects"] as Array)[0]["travel"]), str(Hearth.travel_targets(_ids[0])[0]["id"]),
			"the nearest first, and choosing it takes the road")
	assert_true(Hearth.travel_targets("core:interior/some_cave_hearth").is_empty(), "a cave's stone is not on the road")


func test_the_road_sets_you_down_at_the_stone_and_the_day_goes_on() -> void:
	if _ids.size() < 2:
		fail("no stones to test with")
		return
	Hearth.lit.assign([_ids[0], _ids[1]])
	var there: Vector3 = Hearth.stone_places()[_ids[1]]
	var from: Vector3 = Hearth.stone_places()[_ids[0]]
	player.global_position = from
	var hours_before := WorldClock.day * 24.0 + WorldClock.time_hours
	assert_false(Hearth.travel_to(_ids[2]) if _ids.size() > 2 else false, "an unlit stone is not a way to go")
	assert_true(Hearth.travel_to(_ids[1]), "a lit one is")
	assert_false(Hearth.travel_to(_ids[1]), "and one journey at a time")
	await Hearth.travelled
	var off := Vector2(player.global_position.x - there.x, player.global_position.z - there.z).length()
	assert_true(off < 60.0, "set down at the place of the stone (%.1f m off)" % off)
	var km := Vector2(there.x - from.x, there.z - from.z).length() / 1000.0
	var hours := WorldClock.day * 24.0 + WorldClock.time_hours - hours_before
	assert_gt(hours, 0.0, "the clock has gone on (%.2f h for %.1f km)" % [hours, km])
	assert_true(hours < Hearth.TRAVEL_MAX_HOURS + 0.1, "by no more than a long walk")
	for i in 5:
		await _tree().process_frame
	assert_false(Hearth.is_travelling(), "and the journey is over")


func test_nobody_takes_the_road_with_a_foe_on_them() -> void:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar dead := false\nvar target: Node3D = null\n"
	script.reload()
	var foe := Node3D.new()
	foe.set_script(script)
	foe.add_to_group("enemy")
	_tree().root.add_child(foe)
	foe.set("target", player)
	foe.global_position = player.global_position + Vector3(6.0, 0.0, 0.0)
	assert_ne(Hearth.why_no_travel(), "", "a foe that has you is a reason to stay")
	foe.set("target", null)
	assert_eq(Hearth.why_no_travel(), "", "one that does not is not")
	_tree().root.remove_child(foe)
	foe.free()


# --- travel is its own choice (triage 30) ------------------------------------------------------

func _stone(id: String) -> Hearthstone:
	var stone := Hearthstone.new()
	stone.hearthstone_id = id
	stone.place_id = id
	_tree().root.add_child(stone)
	stone.global_position = player.global_position + Vector3(0.0, 0.0, -1.4)
	return stone


func _end_talk() -> void:
	if Social.dialogue.is_running():
		Social.dialogue.stop()


func test_resting_only_rests_and_then_the_stone_offers_the_road() -> void:
	if _ids.size() < 2:
		fail("no stones to test with")
		return
	Hearth.lit.assign([_ids[0], _ids[1]])
	var stone := _stone(_ids[0])
	var rested: Array[String] = []
	var on_rest := func(id: String) -> void: rested.append(id)
	EventBus.hearthstone_rested.connect(on_rest)
	assert_true(stone.prompt_text().begins_with("Rest"), "a stone you have not rested at offers a rest")
	stone.interact(player)
	assert_eq(rested.size(), 1, "resting rests (and a lesson that asks for a rest here is told so)")
	assert_false(Social.dialogue.is_running(), "and does not put the road to you")
	assert_true(stone.prompt_text().begins_with("Travel from"), "then the stone offers the road: '%s'" % stone.prompt_text())
	stone.interact(player)
	assert_true(Social.dialogue.is_running(), "and the second use is the road")
	_end_talk()
	assert_eq(rested.size(), 1, "which is not another rest")
	# walking off, the stone offers a rest again
	player.global_position += Vector3(8.0, 0.0, 0.0)
	await _tree().process_frame
	assert_true(stone.prompt_text().begins_with("Rest"), "walked off, it offers a rest again")
	EventBus.hearthstone_rested.disconnect(on_rest)
	stone.queue_free()


## The Warrior's lesson at the Wellspring (The Relief, "Put your hand on the Wellspring's
## Hearthstone") is a rest there, and resting still is one, with other stones lit or not.
func test_the_warriors_lesson_at_the_wellspring_still_completes() -> void:
	const RELIEF := "core:quest/the_relief"
	const WELLSPRING := "core:poi/the_wellspring"
	if not ContentDB.has(RELIEF):
		fail("no Relief in the pack")
		return
	var quests: Node = Social.quests
	quests.call("reset_for_new_game")
	quests.call("start", RELIEF)
	quests.call("set_stage", RELIEF, "the_ride")
	EventBus.place_discovered.emit(WELLSPRING)
	var others: Array[String] = []
	for id in _ids:
		if id != WELLSPRING:
			others.append(id)
	Hearth.lit.assign(others)
	var stone := _stone(WELLSPRING)
	stone.interact(player)
	assert_false(Social.dialogue.is_running(), "the hand on the stone is a rest, not the road")
	assert_ne(str(quests.call("stage_id_of", RELIEF)), "the_ride", "and the lesson is done: on to the Glass Bridge")
	_end_talk()
	stone.queue_free()
	quests.call("reset_for_new_game")


func test_with_no_other_stone_lit_the_stone_only_rests() -> void:
	if _ids.size() < 1:
		fail("no stones to test with")
		return
	Hearth.lit.assign([_ids[0]])
	var stone := _stone(_ids[0])
	stone.interact(player)
	assert_true(stone.prompt_text().begins_with("Rest"), "nowhere to go: no road offered")
	stone.interact(player)
	assert_false(Social.dialogue.is_running(), "and a second use rests again")
	stone.queue_free()


func test_the_road_is_refused_indoors_and_overloaded() -> void:
	if _ids.size() < 2:
		fail("no stones to test with")
		return
	Hearth.lit.assign([_ids[0], _ids[1]])
	var stone := _stone(_ids[0])
	stone.interact(player)
	Interiors.current_id = "core:interior/test_room"
	assert_ne(Hearth.why_no_travel(), "", "indoors the road is shut")
	stone.interact(player)
	assert_false(Social.dialogue.is_running(), "and the stone says so rather than offering it")
	assert_false(Hearth.travel_to(_ids[1]), "and travel_to refuses")
	Interiors.current_id = ""
	var bag := _overloaded_bag()
	assert_true(Hearth.why_no_travel().contains("carry"), "more than you can carry shuts it: '%s'" % Hearth.why_no_travel())
	assert_false(Hearth.travel_to(_ids[1]), "and travel_to refuses")
	player.remove_child(bag)
	bag.free()
	assert_eq(Hearth.why_no_travel(), "", "put down, the road is open")
	stone.queue_free()


## An Inventory under the body, loaded past what it can carry.
func _overloaded_bag() -> Inventory:
	var bag := Inventory.new()
	bag.name = "Inventory"
	bag.capacity_override = 1.0
	player.add_child(bag)
	bag.add("core:item/iron_sword", 3)
	assert_true(bag.is_overloaded(), "the test's bag is overloaded")
	return bag


func test_the_chart_lists_the_lit_stones_and_takes_the_road() -> void:
	if _ids.size() < 3:
		fail("no stones to test with")
		return
	Hearth.lit.assign([_ids[0], _ids[1]])
	player.global_position = Hearth.stone_places()[_ids[2]]
	var chart: Control = (load("res://ui/map/map_screen.tscn") as PackedScene).instantiate()
	_tree().root.add_child(chart)
	await _tree().process_frame
	var buttons := _road_buttons(chart)
	assert_eq(buttons.size(), 2, "both lit stones are on the chart's road, from wherever you stand")
	var nearest := str(Hearth.travel_targets_from(player.global_position)[0]["id"])
	assert_eq(str(buttons[0].get_meta("travel_to")), nearest, "nearest first")
	for b in buttons:
		assert_false(b.disabled, "and open")
	# a foe on you shuts it, and the page says why
	var foe := _foe()
	chart.call("refresh_road")
	await _tree().process_frame
	buttons = _road_buttons(chart)
	assert_true(buttons.all(func(b: Button) -> bool: return b.disabled), "with a foe on you the road is shut")
	assert_true(str((chart.get("_road_why") as Label).text).contains("foe"), "and the page says why")
	assert_false(bool(chart.call("take_road", nearest)), "a press does not take it")
	_tree().root.remove_child(foe)
	foe.free()
	chart.call("refresh_road")
	await _tree().process_frame
	buttons = _road_buttons(chart)
	var there: Vector3 = Hearth.stone_places()[nearest]
	buttons[0].pressed.emit()
	assert_true(Hearth.is_travelling(), "the press takes the road")
	await Hearth.travelled
	var off := Vector2(player.global_position.x - there.x, player.global_position.z - there.z).length()
	assert_true(off < 60.0, "set down at the stone chosen on the chart (%.1f m off)" % off)
	for i in 5:
		await _tree().process_frame
	chart.queue_free()


func test_the_chart_has_no_road_with_no_stone_lit() -> void:
	Hearth.lit.clear()
	var chart: Control = (load("res://ui/map/map_screen.tscn") as PackedScene).instantiate()
	_tree().root.add_child(chart)
	await _tree().process_frame
	assert_eq(_road_buttons(chart).size(), 0, "no lit stone, no road")
	assert_false((chart.get("_road") as Control).visible, "and no column for it")
	chart.queue_free()


func _road_buttons(chart: Node) -> Array[Button]:
	var out: Array[Button] = []
	for n in chart.find_children("*", "Button", true, false):
		if n.has_meta("travel_to") and not n.is_queued_for_deletion():
			out.append(n as Button)
	return out


func _foe() -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar dead := false\nvar target: Node3D = null\n"
	script.reload()
	var foe := Node3D.new()
	foe.set_script(script)
	foe.add_to_group("enemy")
	_tree().root.add_child(foe)
	foe.set("target", player)
	foe.global_position = player.global_position + Vector3(6.0, 0.0, 0.0)
	return foe


# --- the road to anywhere you have been (triage 43) --------------------------------------------

const TOWN := "core:place/merrowby"
const POI := "core:poi/larkbourne_ford"


## Where the body faces, flat.
func _facing() -> Vector3:
	return Vector3(-sin(player.rotation.y), 0.0, -cos(player.rotation.y))


func _journey_to(id: String) -> void:
	assert_true(Hearth.travel_to(id), "the road goes to %s" % id)
	await Hearth.travelled
	var centre := TravelPlaces.centre_of(id)
	var r := float(TravelPlaces.entries()[id].get("radius_flat_m", 25.0))
	var off := Vector2(player.global_position.x - centre.x, player.global_position.z - centre.z)
	assert_true(off.length() < r + TravelPlaces.ROAD_REACH_M + 5.0,
			"%s: set down at the place (%.1f m from its middle)" % [id, off.length()])
	if off.length() > 1.0:
		assert_gt(_facing().dot(Vector3(-off.x, 0.0, -off.y).normalized()), 0.9, "%s: facing into it" % id)
	for i in 5:
		await _tree().process_frame
	assert_false(Hearth.is_travelling(), "and the journey is over")


func test_the_road_goes_to_a_found_town_and_a_found_poi() -> void:
	if not TravelPlaces.has(TOWN) or not TravelPlaces.has(POI):
		fail("no Merrowby or Larkbourne Ford in the world")
		return
	player.global_position = TravelPlaces.centre_of(POI) + Vector3(900.0, 0.0, 0.0)
	assert_false(Hearth.can_travel_to(TOWN), "a place not found is not on the road")
	GameState.discover(TOWN)
	GameState.discover(POI)
	assert_true(Hearth.can_travel_to(TOWN), "found, it is")
	var hours_before := WorldClock.day * 24.0 + WorldClock.time_hours
	await _journey_to(TOWN)
	assert_gt(WorldClock.day * 24.0 + WorldClock.time_hours - hours_before, 0.0, "the day goes on")
	await _journey_to(POI)


func test_the_road_is_refused_to_a_place_not_found() -> void:
	if not TravelPlaces.has(TOWN):
		fail("no Merrowby in the world")
		return
	assert_false(Hearth.travel_to(TOWN), "not found: no road")
	assert_false(Hearth.is_travelling(), "and no journey begun")
	assert_false(Hearth.travel_to("core:place/nowhere_at_all"), "nor to a place the world has not got")
	var names := Hearth.destinations_from(player.global_position).map(func(t: Dictionary) -> String: return str(t["id"]))
	assert_false(names.has(TOWN), "and it is not listed")


func test_the_refusals_hold_for_a_found_place() -> void:
	GameState.discover(TOWN)
	Interiors.current_id = "core:interior/test_room"
	assert_false(Hearth.travel_to(TOWN), "indoors, no road to a found place either")
	Interiors.current_id = ""
	var foe := _foe()
	assert_false(Hearth.travel_to(TOWN), "nor with a foe on you")
	_tree().root.remove_child(foe)
	foe.free()
	var bag := _overloaded_bag()
	assert_false(Hearth.travel_to(TOWN), "nor carrying too much")
	player.remove_child(bag)
	bag.free()
	assert_false(Hearth.is_travelling())


func test_the_chart_lists_found_places_by_region_finds_them_and_a_marker_chooses() -> void:
	if not TravelPlaces.has(TOWN) or not TravelPlaces.has(POI) or _ids.is_empty():
		fail("nothing to test with")
		return
	Hearth.lit.assign([_ids[0]])
	GameState.discover(TOWN)
	GameState.discover(POI)
	player.global_position = TravelPlaces.centre_of(TOWN) + Vector3(0.0, 0.0, 300.0)
	var chart: Control = (load("res://ui/map/map_screen.tscn") as PackedScene).instantiate()
	_tree().root.add_child(chart)
	await _tree().process_frame
	var ids := _road_buttons(chart).map(func(b: Button) -> String: return str(b.get_meta("travel_to")))
	assert_eq(ids.size(), 3, "the stone and both found places: %s" % str(ids))
	assert_eq(str(ids[0]), _ids[0], "the lit stones first")
	assert_true(ids.has(TOWN) and ids.has(POI), "and the places found")
	var headings: Array = chart.find_children("*", "Label", true, false).filter(
			func(l: Label) -> bool: return l.has_meta("road_group"))
	var texts := headings.map(func(l: Label) -> String: return l.text)
	assert_true(texts.has("Hearthstones"), "under their heading")
	assert_true(texts.has(str(ContentDB.get_or_empty("core:region/hearthvale").get("name", ""))),
			"the places under their region's: %s" % str(texts))
	# finding by name
	var find := chart.get("_road_find") as LineEdit
	find.text = "merrow"
	find.text_changed.emit(find.text)
	var shown := _road_buttons(chart).filter(func(b: Button) -> bool: return b.visible)
	assert_eq(shown.size(), 1, "typing a name leaves that place")
	if shown.size() == 1:
		assert_eq(str(shown[0].get_meta("travel_to")), TOWN)
	find.text = ""
	find.text_changed.emit(find.text)
	# a click on a found place's marker chooses it; a place not found is not chosen
	var at: Vector2 = chart.call("marker_point", TOWN)
	assert_ne(at, Vector2.INF, "the town has a marker")
	assert_eq(str(chart.call("place_at", at)), TOWN, "the marker is the town's")
	assert_false(bool(chart.call("choose", "core:place/tollmere")), "a place not found is not chosen")
	assert_true(bool(chart.call("choose", TOWN)), "a found one is")
	assert_true((chart.get("_chosen_box") as Control).visible, "and named on the page with its way to go")
	var go := chart.get("_chosen_go") as Button
	assert_false(go.disabled, "open")
	go.pressed.emit()
	assert_true(Hearth.is_travelling(), "'Travel there' takes the road")
	await Hearth.travelled
	var c := TravelPlaces.centre_of(TOWN)
	var off := Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length()
	assert_true(off < 120.0, "to the town (%.1f m from its middle)" % off)
	for i in 5:
		await _tree().process_frame
	chart.queue_free()
