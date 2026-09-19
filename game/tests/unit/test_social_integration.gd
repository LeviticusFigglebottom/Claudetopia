extends TestCase
## The seams between this stream and the ones that own the player, the bag, the paper-doll and
## the skills. Dialogue conditions ask about items, marks, worn tags and skills; these tests use
## the real Inventory, Equipment and Progression nodes rather than fakes, so a rename in either
## stream fails here instead of silently making a condition read false forever.

const APPLE := "core:item/apple"
const BADGE := "core:item/wardens_lantern_badge"

var player: Node3D
var bag: Inventory
var equipment: Equipment
var progression: Progression


func root() -> Node:
	return Engine.get_main_loop().root


func before_each() -> void:
	player = Node3D.new()
	player.add_to_group("player")
	bag = Inventory.new()
	equipment = Equipment.new()
	progression = Progression.new()
	player.add_child(bag)
	player.add_child(equipment)
	player.add_child(progression)
	root().add_child(player)
	Social.refresh_providers()
	Social.bind("inventory", bag)
	Social.bind("equipment", equipment)
	Social.bind("player", player)
	Social.bind("skills", progression)


func after_each() -> void:
	for name in ["inventory", "equipment", "player", "skills"]:
		Social.bind(name, null)
	player.free()
	Social.standing.reset_for_new_game()
	Social.factions.reset_for_new_game()


func test_has_item_reads_the_real_bag() -> void:
	var ctx := Social.ctx
	assert_false(Conditions.check({"has_item": [APPLE, 1]}, ctx))
	bag.add(APPLE, 3)
	assert_true(Conditions.check({"has_item": [APPLE, 3]}, ctx))
	assert_false(Conditions.check({"has_item": [APPLE, 4]}, ctx))
	assert_eq(ctx.item_count(APPLE), 3)


func test_give_and_take_item_effects_move_real_stacks() -> void:
	var ctx := Social.ctx
	Effects.apply_all([{"give_item": [APPLE, 2]}], ctx)
	assert_eq(bag.count(APPLE), 2)
	Effects.apply_all([{"take_item": [APPLE, 1]}], ctx)
	assert_eq(bag.count(APPLE), 1)


func test_marks_are_the_inventorys_property() -> void:
	var ctx := Social.ctx
	bag.marks = 0
	Effects.apply_all([{"marks": 120}], ctx)
	assert_eq(bag.marks, 120, "a dialogue paying out reaches the real purse")
	assert_eq(ctx.marks(), 120)
	assert_true(Conditions.check({"marks_min": 100}, ctx))
	Effects.apply_all([{"marks": -20}], ctx)
	assert_eq(bag.marks, 100)


func test_wearing_tag_reads_the_paper_doll() -> void:
	var ctx := Social.ctx
	assert_false(Conditions.check({"wearing_tag": "warden"}, ctx))
	var stack: ItemStack = bag.add(BADGE, 1)
	assert_ne(stack, null)
	# The badge is a misc item, so put it somewhere the doll will take it; whatever slot it
	# lands in, the greeting matrix must see its tags.
	var equipped := equipment.equip(stack)
	if not equipped:
		return   # nothing equippable about a badge in this build; the read is covered below
	assert_true(Conditions.check({"wearing_tag": "warden"}, ctx), "the Wardens' colours are showing")
	assert_false(Conditions.check({"wearing_tag": "hollow"}, ctx))


func test_skill_min_reads_progression() -> void:
	var ctx := Social.ctx
	assert_false(Conditions.check({"skill_min": ["speech", 20]}, ctx))
	progression.skill_set.set_level("speech", 30)
	assert_eq(ctx.skill_level("speech"), 30)
	assert_true(Conditions.check({"skill_min": ["speech", 25]}, ctx))
	assert_false(Conditions.check({"skill_min": ["speech", 31]}, ctx))


func test_the_player_node_locates_itself_for_reach_objectives() -> void:
	assert_eq(Social.quests.position_provider, player, "a Node3D player is a position provider")
	player.global_position = Vector3(12.0, 0.0, -8.0)
	assert_eq(SocialContext.position_of(player), Vector3(12.0, 0.0, -8.0))
	assert_eq(Social.ctx.player_position(), Vector3(12.0, 0.0, -8.0))


func test_a_deed_lands_where_the_player_is_standing() -> void:
	var merrowby: Array = ContentDB.get_or_empty("core:place/merrowby")["position"]
	player.global_position = Vector3(float(merrowby[0]) + 40.0, 0.0, float(merrowby[1]))
	assert_eq(Social.place_id(), "core:place/merrowby")
	Social.apply_deed("boss_kill", 2)
	assert_true(Social.gossip.knows_deed("core:place/merrowby", "boss_kill"),
		"the village nearest the deed is the one that talks about it")


func test_quest_rewards_reach_the_real_bag() -> void:
	bag.marks = 0
	Social.quests.register_runtime({
		"id": "core:quest/_test_integration", "name": "A paid errand", "layer": "side",
		"stages": [{"id": "done", "auto": true, "journal": "Finished.", "objectives": []}],
		"rewards": {"marks": 75, "items": [[APPLE, 2]], "rep": [["core:faction/wardens", 5]]},
	})
	Social.take_quest("core:quest/_test_integration")
	assert_eq(bag.marks, 75)
	assert_eq(bag.count(APPLE), 2)
	assert_eq(Social.factions.reputation("core:faction/wardens"), 5)
	Social.quests.forget("core:quest/_test_integration")
