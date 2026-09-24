extends TestCase
## The card a region's name arrives on (ui/hud/hud.gd). Every region's identity lists what it is
## known for (`unique_features`: the only apple trees in Wickmere, the Chalk Hound, the Wardens'
## Roll) and nothing read the list; the card says it under the tagline, the first time the
## player comes into the region and not at every crossing after.

const HUD := preload("res://ui/hud/hud.gd")
const VALE := "core:region/hearthvale"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	GameState.set_flag("region_card_seen/" + VALE, false)


func test_every_region_is_known_for_what_its_identity_says() -> void:
	for region in ContentDB.all("region"):
		var line := HUD.known_for(region)
		var listed: Array = (region.get("identity", {}) as Dictionary).get("unique_features", [])
		assert_false(listed.is_empty(), "%s is known for nothing" % region["id"])
		assert_true(line.begins_with("Known for "), line)
		for f in listed:
			assert_true(line.contains(str(f)), "%s's card leaves out %s" % [region["id"], f])
	assert_eq(HUD.known_for({"identity": {"unique_features": ["one thing"]}}), "Known for one thing.")
	assert_eq(HUD.known_for({}), "", "a region with no list shows nothing")


func test_the_card_says_it_the_first_time_and_not_after() -> void:
	GameState.set_flag("region_card_seen/" + VALE, false)
	var hud: Node = load("res://ui/hud/hud.tscn").instantiate()
	_tree().root.add_child(hud)
	var features: Label = hud.get("_region_features")
	hud.call("_on_region_entered", VALE, "")
	assert_true(features.visible and features.text.contains("apple"), "the first crossing said %s" % features.text)
	hud.call("_on_region_entered", VALE, "")
	assert_false(features.visible, "the Vale's claims were read out again at the second crossing")
	hud.free()
