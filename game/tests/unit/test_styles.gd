extends TestCase
## The fighting styles (DESIGN §5.1, docs/FIGHTING_STYLE_STARTS.md): a style is data a validator
## checks, a kit and skills the body is handed on top of its Calling, the opening a new game begins
## with, a page of the Naming with a card each, and the save field that carries it. These press the
## Naming's cards and ask the flags, stand a body up and ask its bag and its hands, and ask the new
## game which opening it would begin with.

const PATCH := preload("res://tests/fixtures/content_patch.gd")
const PLAYER := preload("res://actors/player/player.tscn")
const SCREEN := preload("res://ui/character/naming.tscn")
const STYLE := "core:style/_test_fighter"
const OPENING := "core:opening/_test_fighter"
const REEDBORN := "core:calling/reedborn"
const SWORD := "core:item/iron_sword"
const SHIELD := "core:item/oak_round_shield"
const NAMING_QUEST := "core:quest/the_naming"

var _added: Array[String] = []
var _nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(11)
	SaveSystem.pending.clear()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	for id in _added:
		PATCH.remove(id)
	_added.clear()
	GameState.reset_for_new_game(11)
	Social.quests.call("reset_for_new_game")


## A style as the pack writes one, and its opening, laid over the pack for this test.
func _fixture_style(extra := {}) -> Dictionary:
	var opening := {"id": OPENING, "role": "new_game", "style": STYLE, "quest": "core:quest/the_toll_hums",
			"place": "core:place/wardens_rest", "region": "core:region/hearthvale", "greeter": "core:npc/wardens_dole"}
	var style := {"id": STYLE, "name": "Fighter", "blurb": "Wardens' Rest, on the West Downs: a test teaches the shield.",
			"start": "core:place/wardens_rest", "teacher": "core:npc/wardens_dole", "opening": OPENING,
			"tutorial": "core:quest/the_toll_hums", "tie_in": "core:quest/the_toll_hums", "mount": "core:mount/wardens_cob",
			"kit": {"items": [{"item": SWORD, "equip": "main_hand"}, {"item": SHIELD, "equip": "off_hand"}]},
			"skill_bonuses": {"one_handed": 5, "block": 5}, "icon": "shield"}
	style.merge(extra, true)
	for def in [opening, style]:
		PATCH.add(def)
		_added.append(str(def["id"]))
	return style


# --- the definition ------------------------------------------------------------------------------

func test_a_style_as_written_passes_its_validator() -> void:
	var def := _fixture_style()
	assert_empty(StyleDef.validate(def, "test"), "a whole style is valid")
	assert_empty(Schemas.validate_def(def, "test"), "and the pack's schema agrees")


func test_the_validator_says_what_a_style_is_missing() -> void:
	var def := _fixture_style()
	var bad := def.duplicate(true)
	bad.erase("teacher")
	bad["skill_bonuses"] = {"one_handed": 12}
	bad["kit"] = {"items": [{"item": SWORD, "equip": "main_hand"}, {"item": "core:item/iron_dagger", "equip": "main_hand"}]}
	bad["mount"] = "core:npc/wardens_dole"
	var said := " / ".join(PackedStringArray(StyleDef.validate(bad, "test")))
	assert_true(said.contains("no teacher"), said)
	assert_true(said.contains("adds 12"), said)
	assert_true(said.contains("two things in the main_hand"), said)
	assert_true(said.contains("not a mount id"), said)


func test_every_style_in_the_pack_is_whole() -> void:
	for def in ContentDB.all("style"):
		assert_empty(StyleDef.validate(def, "pack"), "%s is whole" % def["id"])
		var opening := StyleDef.opening_of(str(def["id"]))
		assert_false(opening.is_empty(), "%s has an opening" % def["id"])
		assert_eq(str(opening.get("style", "")), str(def["id"]), "%s's opening says whose it is" % def["id"])
		assert_eq(str(opening.get("role", "")), "new_game", "%s's opening begins a new game" % def["id"])
		for key in ["teacher", "tutorial", "tie_in", "mount", "start"]:
			assert_true(ContentDB.has(str(def.get(key, ""))), "%s's %s is in the pack" % [def["id"], key])
		var picture := str(def.get("picture", ""))
		assert_true(picture.is_empty() or ResourceLoader.exists(picture), "%s's picture %s is there" % [def["id"], picture])


func test_the_kit_reads_as_words() -> void:
	var def := _fixture_style()
	assert_eq(StyleDef.kit_words(def), "an iron sword, an oak round shield and a pitch torch")


# --- the opening a new game begins with ------------------------------------------------------------

func test_a_character_with_no_style_gets_the_fallback_and_one_with_a_style_its_own() -> void:
	_fixture_style()
	assert_eq(str(Openings.for_new_game().get("id", "")), Openings.FALLBACK, "no style: the old start")
	GameState.set_flag(StyleDef.FLAG, STYLE)
	assert_eq(str(Openings.for_new_game().get("id", "")), OPENING, "a style: its own opening")
	assert_true(Openings.is_style_start(Openings.for_new_game()))
	GameState.set_flag(StyleDef.FLAG, "core:style/no_such_style")
	assert_eq(str(Openings.for_new_game().get("id", "")), Openings.FALLBACK, "a style the pack has lost: the old start")
	assert_eq(str(Openings.wake().get("role", "")), Openings.WAKE_ROLE, "and there is a wake to come to")
	assert_eq(str(Openings.wake().get("stage", "")), "wake")


func test_the_fallback_opens_the_naming_on_its_wake() -> void:
	var fallback := ContentDB.get_def(Openings.FALLBACK)
	assert_eq(str(fallback.get("stage", "")), "wake", "a character who never went down has nothing to follow")
	var stages: Array = ContentDB.get_def(NAMING_QUEST).get("stages", [])
	assert_eq(str((stages[0] as Dictionary).get("id", "")), "down_the_stair", "the Naming begins with the descent")
	assert_true(bool((stages[0] as Dictionary).get("manual_advance", false)), "which the wake moves on, not its objective")


# --- the body --------------------------------------------------------------------------------------

func test_a_styled_character_stands_up_with_its_kit_in_its_hands_on_top_of_its_calling() -> void:
	_fixture_style()
	GameState.set_flag("player_name", "Tam of the Downs")
	GameState.set_flag("player_calling", REEDBORN)
	GameState.set_flag(StyleDef.FLAG, STYLE)
	GameState.set_flag(Openings.STYLE_START, true)
	GameState.set_flag(Openings.STYLE_DUE, true)
	var player := PLAYER.instantiate()
	_tree().root.add_child(player)
	_nodes.append(player)
	var prog := player.get_node("Progression") as Progression
	var calling: Dictionary = ContentDB.get_def(REEDBORN)
	var from_calling := int((calling.get("skill_bonuses", {}) as Dictionary).get("one_handed", 0))
	assert_eq(prog.skill_set.level("one_handed"), Skills.BASE_LEVEL + from_calling + 5, "the style adds five to one-handed")
	assert_eq(prog.skill_set.level("block"), Skills.BASE_LEVEL + int((calling.get("skill_bonuses", {}) as Dictionary).get("block", 0)) + 5)
	assert_eq(prog.calling_id, REEDBORN, "the Calling still stands")
	assert_eq(prog.style_id, STYLE, "and the style beside it")
	var worn := player.get_node("Equipment") as Equipment
	assert_eq(str(worn.get_slot("main_hand").id), SWORD, "the sword is in the hand")
	assert_eq(str(worn.get_slot("off_hand").id), SHIELD, "the shield on the arm")
	var saved := prog.to_save()
	assert_eq(str(saved.get("style", "")), STYLE, "the save carries the style")
	var again := Progression.new()
	again.listen_to_event_bus = false
	again.from_save(saved)
	assert_eq(again.style_id, STYLE, "and gives it back")
	again.free()
	prog.from_save({"calling": REEDBORN})
	assert_eq(prog.style_id, "", "a save from before styles has none")


# --- the Naming ------------------------------------------------------------------------------------

func _naming() -> Control:
	var n := SCREEN.instantiate() as Control
	n.set("world_scene", "")
	_tree().root.add_child(n)
	_nodes.append(n)
	return n


func _find(root: Node, pred: Callable) -> Node:
	for n in root.find_children("*", "", true, false):
		if bool(pred.call(n)):
			return n
	return null


func test_the_naming_has_a_page_of_styles_with_a_card_each() -> void:
	_fixture_style()
	var n := _naming()
	var card := _find(n, func(x: Node) -> bool: return x is Button and str(x.get_meta("style", "")) == STYLE) as Button
	assert_true(card != null, "a card for the style")
	var tab := _find(n, func(x: Node) -> bool: return x is Button and str(x.get_meta("page", "")) == "how") as Button
	assert_true(tab != null, "a tab for How you fight")
	if card == null or tab == null:
		return
	assert_false(card.is_visible_in_tree(), "the styles wait on their own page")
	tab.pressed.emit()
	assert_true(card.is_visible_in_tree(), "the tab shows them")
	card.pressed.emit()
	assert_eq(str(n.get("style_id")), STYLE)
	var said := ""
	for l in n.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			said += (l as Label).text + " | "
	assert_true(said.contains("Sergeant Dole"), "the card names the teacher: %s" % said)
	assert_true(said.contains("an iron sword and an oak round shield"), "and the detail the kit: %s" % said)
	assert_true(said.contains("One-Handed +5"), "and what it teaches: %s" % said)


func test_be_named_with_a_style_begins_its_start_and_not_the_wake() -> void:
	_fixture_style({"loading_line": "Wardens' Rest. Dole is counting."})
	var n := _naming()
	var card := _find(n, func(x: Node) -> bool: return x is Button and str(x.get_meta("style", "")) == STYLE) as Button
	card.pressed.emit()
	var be_named := _find(n, func(x: Node) -> bool: return x is Button and (x as Button).text == "Be named") as Button
	be_named.pressed.emit()
	await _tree().process_frame
	assert_eq(str(GameState.get_flag(StyleDef.FLAG, "")), STYLE, "the style is written down")
	assert_true(GameState.has_flag(Openings.STYLE_START), "its start is under way")
	assert_true(GameState.has_flag(Openings.STYLE_DUE), "and due to begin")
	assert_false(GameState.has_flag(Openings.NEW_GAME), "the wake's flag waits for the descent")
	assert_eq(str(n.call("loading_line")), "Wardens' Rest. Dole is counting.", "the loading caption is the style's")


# --- the vocabulary the starts are written in --------------------------------------------------------

func test_an_if_effect_does_one_thing_or_the_other() -> void:
	var ctx: SocialContext = Social.ctx
	Effects.apply({"if": [{"flag": "_t_yes"}], "then": [{"set_flag": "_t_then"}], "else": [{"set_flag": "_t_else"}]}, ctx)
	assert_false(GameState.has_flag("_t_then"))
	assert_true(GameState.has_flag("_t_else"), "the conditions do not hold: else")
	GameState.set_flag("_t_yes", true)
	Effects.apply({"if": [{"flag": "_t_yes"}], "then": [{"set_flag": "_t_then"}]}, ctx)
	assert_true(GameState.has_flag("_t_then"), "they hold: then")


func test_the_style_and_horse_conditions() -> void:
	var ctx: SocialContext = Social.ctx
	_fixture_style()
	assert_false(Conditions.check({"style": STYLE}, ctx))
	GameState.set_flag(StyleDef.FLAG, STYLE)
	assert_true(Conditions.check({"style": STYLE}, ctx))
	assert_true(Conditions.check({"has_mount": false}, ctx), "no horse yet")
	GameState.set_flag(SocialContext.MOUNT_FLAG_PREFIX + "core:mount/wardens_cob", true)
	assert_true(Conditions.check({"has_mount": true}, ctx), "a horse")
	assert_false(Conditions.check({"has_mount": false}, ctx))


func test_the_toll_hums_gives_the_cob_only_to_somebody_without_a_horse() -> void:
	var toll: Dictionary = ContentDB.get_def("core:quest/the_toll_hums")
	var arrive: Dictionary = (toll["stages"] as Array)[0]
	var gift: Dictionary = (arrive["on_complete"] as Array)[0]
	assert_true(gift.has("if"), "the cob is conditional")
	assert_eq(str(gift["if"]), str([{"has_mount": false}]))


func test_an_act_objective_counts_the_player_s_own_doing() -> void:
	var quests: Node = Social.quests
	var quest := {"id": "core:quest/_t_acts", "name": "Acts", "layer": "side", "stages": [
		{"id": "yard", "journal": "Drill.", "objectives": [
			{"type": "act", "target": "parry", "count": 2},
			{"type": "act", "target": "hit_heavy", "against": "core:enemy/roadside_bandit", "count": 1}]},
		{"id": "done", "journal": "Done.", "objectives": [{"type": "act", "target": "lock_on"}]}]}
	PATCH.add(quest)
	_added.append(str(quest["id"]))
	assert_true(bool(quests.call("start", quest["id"])))
	var me := Node3D.new()
	me.add_to_group("player")
	_tree().root.add_child(me)
	_nodes.append(me)
	var other := Node3D.new()
	_tree().root.add_child(other)
	_nodes.append(other)
	EventBus.act_done.emit("parry", other, me, "")
	assert_eq(int((quests.call("objectives_of", quest["id"]) as Array)[0]["count"]), 0, "somebody else's parry is not the player's")
	EventBus.act_done.emit("parry", me, other, "")
	EventBus.act_done.emit("parry", me, other, "")
	assert_true(bool((quests.call("objectives_of", quest["id"]) as Array)[0]["done"]), "two parries")
	EventBus.act_done.emit("hit_heavy", me, other, "")
	assert_eq(str(quests.call("stage_id_of", quest["id"])), "yard", "a heavy blow on the wrong thing does not count")
	assert_eq(str((quests.call("objectives_of", quest["id"]) as Array)[0]["text"]), "Parry a blow", "an act says what it is")
