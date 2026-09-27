extends TestCase
## The road between the Hearthstones (playtest 09-27: "fast travel between candles" did not exist).
##
## Resting at a lit stone out in the country offers every other lit one; taking it sets the body
## down at that place's arrival, facing the stone, and the clock goes on by the walk. A stone that
## is not lit is not offered, nor one in a cave, and nobody takes the road with a foe on them.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")

var player: Node3D
var _ids: Array[String] = []
var _lit_was: Array[String] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	player = FakePlayer.new()
	_tree().root.add_child(player)
	_lit_was = Hearth.lit.duplicate()
	Hearth.lit.clear()
	_ids.clear()
	var keys := Hearth.stone_places().keys()
	keys.sort()
	for k in keys:
		if str(k).begins_with("core:poi/") and _ids.size() < 3:
			_ids.append(str(k))


func after_each() -> void:
	Hearth.lit.assign(_lit_was)
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
