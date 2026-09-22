extends TestCase
## The named character is the body that stands in the world.
##
## The Naming wrote `player_name`, `player_calling` and `player_appearance` into GameState and
## nothing read them: the body that stood at the Hushline Stair was the bare rig with the
## default head whatever had been chosen, the Calling's skills never landed and its lantern
## never reached the bag. `Player._take_the_naming` reads them now; this asks the body.

const PLAYER := preload("res://actors/player/player.tscn")
const REEDBORN := "core:calling/reedborn"
const SLOT := "test_player_body"

var player: Node


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(7)
	SaveSystem.pending.clear()
	player = null


func after_each() -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	player = null
	SaveSystem.delete_slot(SLOT)
	GameState.reset_for_new_game(7)


func _stand_up() -> Node:
	player = PLAYER.instantiate()
	_tree().root.add_child(player)
	return player


## What the Naming would write for a Reedborn with a few things chosen.
func _record() -> Dictionary:
	var a := CharacterAppearance.new()
	a.skin = "amber"
	a.hair_colour = "auburn"
	a.eye_colour = "green"
	a.set_part("head", "narrow")
	a.set_part("hair", "braid")
	a.height = 1.71
	a.build = 0.65
	a.dress_for_culture(CharacterAppearance.culture_of_calling(REEDBORN), 1)
	return a.to_dict()


func _name_them() -> void:
	GameState.set_flag("player_name", "Wren of the Hushline")
	GameState.set_flag("player_calling", REEDBORN)
	GameState.set_flag("player_appearance", _record())
	GameState.set_flag("new_game", true)


func _model() -> HumanoidModel:
	return player.call("body_model") as HumanoidModel


func test_the_body_in_the_world_is_the_one_the_naming_made() -> void:
	_name_them()
	_stand_up()
	assert_eq(str(player.get("display_name")), "Wren of the Hushline")
	var model := _model()
	assert_true(model != null, "the player stood up without a forge body")
	if model == null or model.skeleton == null:
		return
	var look := model.appearance
	assert_eq(look.skin, "amber")
	assert_eq(look.hair_colour, "auburn")
	assert_eq(look.eye_colour, "green")
	assert_eq(look.part("hair"), "braid")
	assert_eq(look.part("head"), "narrow")
	assert_eq(look.culture, "reedfolk")
	assert_eq(look.part("torso"), "wrap_torso", "the Reedborn is dressed as Reedfolk")
	for slot in ["hair", "head", "torso"]:
		assert_true(model._part_meshes.has(slot), "no %s on the body" % slot)
	assert_near(model._rig_root.scale.y, 1.71 / 1.78, 0.001)
	assert_true(model._rig_root.scale.x > model._rig_root.scale.y, "a solid build should widen the rig")


func test_the_calling_lands_in_the_bag_and_the_skills_once() -> void:
	_name_them()
	var untrained := Progression.new()
	var base := untrained.skill_level("alchemy")
	untrained.free()
	_stand_up()
	var bag: Inventory = player.get_node("Inventory")
	assert_true(bag.has("core:item/lantern"), "the Reedborn's jetty-lantern is not in the bag")
	assert_true(bag.has("core:item/eel_pie"), "the starting eel pie is not in the bag")
	assert_eq(bag.marks, 20, "the starting marks did not arrive")
	var prog: Progression = player.get_node("Progression")
	assert_eq(prog.calling_id, REEDBORN)
	assert_eq(prog.skill_level("alchemy"), base + 10, "the Calling's +10 alchemy did not land")
	assert_true(prog.knows_spell("core:spell/hush_frost"), "the Reedborn starts with Hush Frost in the mouth")
	# a second pass over the same flags (a load, a respawn) must not hand it all out again
	player.call("_take_the_naming")
	assert_eq(bag.marks, 20, "the Calling was applied twice")
	assert_eq(bag.count("core:item/lantern"), 1, "the Calling was applied twice")


func test_a_loaded_game_does_not_reapply_the_calling() -> void:
	_name_them()
	GameState.set_flag("new_game", false)
	_stand_up()
	var bag: Inventory = player.get_node("Inventory")
	assert_false(bag.has("core:item/lantern"), "a game that is not new handed out the Calling's items again")
	assert_eq(str(player.get("display_name")), "Wren of the Hushline", "but the name still comes from the flags")
	if _model() != null and _model().skeleton != null:
		assert_eq(_model().appearance.skin, "amber", "and so does the look")


func test_without_a_naming_the_foundling_is_still_dressed() -> void:
	_stand_up()
	assert_eq(str(player.get("display_name")), "Foundling")
	var model := _model()
	if model == null or model.skeleton == null:
		return
	assert_true(not model.appearance.part("torso").is_empty(), "a Foundling with no Naming stood up naked")
	assert_true(model._part_meshes.has("torso"))


func test_a_loaded_game_reads_the_slot_it_was_asked_for() -> void:
	GameState.set_flag("player_name", "Hesk Rooke")
	GameState.set_flag("player_calling", REEDBORN)
	GameState.set_flag("player_appearance", _record())
	assert_eq(SaveSystem.save_to_slot(SLOT), OK)
	GameState.reset_for_new_game(9)
	assert_false(GameState.has_flag("player_name"))
	# Continue, Load and --load=<slot> all write this flag and, until now, nothing read it
	GameState.set_flag("_pending_load_slot", SLOT)
	assert_eq(PlayerSpawn.load_pending_slot(), SLOT)
	assert_false(GameState.has_flag("_pending_load_slot"), "the flag must be consumed")
	assert_eq(str(GameState.get_flag("player_name", "")), "Hesk Rooke", "the save was not read back")
	assert_eq(PlayerSpawn.load_pending_slot(), "", "a second call has nothing to load")
	# and the body that then stands is that character
	_stand_up()
	assert_eq(str(player.get("display_name")), "Hesk Rooke")
	if _model() != null and _model().skeleton != null:
		assert_eq(_model().appearance.part("hair"), "braid")


## A save written before the Naming spoke the record's vocabulary carries swatch indices
## (`{"skin": 3, "hair": 2}`), and so does the journey's shorthand. Read as strings those made
## the skin "3.0": no tone, and a tint computed from nothing. An index means what it meant.
func test_an_old_record_of_swatch_indices_still_makes_a_body() -> void:
	GameState.set_flag("player_name", "An Older Foundling")
	GameState.set_flag("player_calling", REEDBORN)
	GameState.set_flag("player_appearance", {"skin": 3, "hair": 2, "build": 0.5})
	_stand_up()
	var look := CharacterAppearance.new({"skin": 3, "hair": 2, "build": 0.5})
	assert_eq(look.skin, CharacterAppearance.SKIN_TONES[3], "an index must name the tone it indexed")
	assert_eq(look.hair_colour, CharacterAppearance.HAIR_COLOURS[2])
	assert_true(look.skin in CharacterAppearance.SKIN_TONES)
	if _model() != null and _model().skeleton != null:
		assert_true(_model().appearance.skin in CharacterAppearance.SKIN_TONES,
				"the body's skin must be a tone, not a number read as a word")
		assert_true(not _model().appearance.part("torso").is_empty(), "and it must still be dressed")


func test_a_record_naming_a_tone_that_does_not_exist_falls_back() -> void:
	var look := CharacterAppearance.new({"skin": "puce", "hair_colour": "chartreuse", "eye_colour": "mauve"})
	assert_eq(look.skin, "wheat", "an unknown tone must leave the default rather than be invented")
	assert_eq(look.hair_colour, "dark_brown")
	assert_eq(look.eye_colour, "brown")


func test_a_missing_slot_is_reported_not_crashed() -> void:
	GameState.set_flag("_pending_load_slot", "no_such_slot_ever")
	var errors := Log.error_count
	assert_eq(PlayerSpawn.load_pending_slot(), "")
	assert_false(GameState.has_flag("_pending_load_slot"))
	assert_eq(Log.error_count, errors + 1, "a slot that is not there is an error, said once")
