extends TestCase
## Six recipes ship with known_by_default false — the Tollmere crossbow, the Ashen and
## Bell-Bronze swords, clan plate, the clan bow and the Kingbone greatsword. Nothing in the
## packs could teach any of them, so seven items existed that no player could ever make. These
## tests pin the way back: that somebody in the world teaches each one, that you have to walk
## to them through a gate, that the gate refuses a character who has not met it, and that a
## character who has met it comes away with the recipe in Crafting.

const LOCKED := [
	"core:recipe/crossbow",
	"core:recipe/ashen_sword",
	"core:recipe/bell_bronze_sword",
	"core:recipe/clan_plate",
	"core:recipe/kingbone_greatsword",
	"core:recipe/clan_bow",
]

const HALLAM := "core:npc/hallam_ashdown"
const CADWEN := "core:npc/cadwen_ash"
const SORREL := "core:npc/sorrel_lathe"
const ORDDA := "core:npc/ordda_ko_brindle"
const DUNNA := "core:npc/dunna_ko_kharrow"

const ORDER := "core:faction/tolling_order"
const TALLYMEN := "core:faction/tallymen"
const MOOT := "core:faction/clan_moot"

const SCRAP := "core:item/bell_bronze_scrap"
const KINGBONE := "core:item/kingbone"
const BELL_MOULD := "core:item/bell_mould"

var runner: Node
var ctx: SocialContext
var crafting: Crafting
var holder: Node
var shown: Array[String] = []


func before_each() -> void:
	ctx = SocialFakes.context()
	holder = Node.new()
	var bag := Inventory.new()
	crafting = Crafting.new()
	holder.add_child(bag)
	holder.add_child(crafting)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	# The real Crafting node is the "recipes" provider, so teach_recipe and knows_recipe go
	# through the same learn_recipe/knows_recipe the game uses.
	ctx.set_provider("recipes", crafting)
	runner = preload("res://systems/dialogue/dialogue_runner.gd").new()
	runner.ctx = ctx
	(Engine.get_main_loop() as SceneTree).root.add_child(runner)
	shown = []
	runner.line_shown.connect(func(_speaker: String, text: String, _choices: Array) -> void:
		shown.append(text))


func after_each() -> void:
	if is_instance_valid(runner):
		runner.queue_free()
	if is_instance_valid(holder):
		holder.queue_free()
	Greetings.forget()


# --- providers the gates read ------------------------------------------------------------------

func flags() -> SocialFakes.Flags:
	return ctx.provider("flags")


func player() -> SocialFakes.FakePlayer:
	return ctx.provider("player")


func inventory() -> SocialFakes.FakeInventory:
	return ctx.provider("inventory")


func factions() -> SocialFakes.Factions:
	return ctx.provider("factions")


func standing() -> SocialFakes.Standing:
	return ctx.provider("standing")


func bounty() -> SocialFakes.FakeBounty:
	return ctx.provider("bounty")


# --- walking a conversation ----------------------------------------------------------------------

## Steps past every line that offers no choice, stopping at a hub or at the end.
func drain() -> void:
	var guard := 0
	while runner.is_running() and runner.current_choices.is_empty() and guard < 40:
		var before := shown.size()
		runner.advance()
		guard += 1
		if shown.size() == before and runner.current_choices.is_empty():
			break


func talk(npc_id: String) -> void:
	shown.clear()
	runner.start("", npc_id)
	drain()


func choice_at(fragment: String) -> int:
	for i in runner.current_choices.size():
		if str(runner.current_choices[i].get("text", "")).contains(fragment):
			return i
	return -1


## Takes the choice whose text contains `fragment` and walks on to the next hub or ending.
func pick(fragment: String) -> void:
	var i := choice_at(fragment)
	assert_true(i >= 0, "no choice matching '%s' was offered (offered: %s)" % [fragment, str(runner.current_choices.map(func(c: Dictionary) -> String: return str(c.get("text", ""))))])
	if i < 0:
		return
	runner.choose(i)
	drain()


func said(fragment: String) -> bool:
	for line in shown:
		if line.contains(fragment):
			return true
	return false


func transcript() -> String:
	return "\n".join(shown)


func assert_clean() -> void:
	assert_empty(ctx.problems, "the conversation raised content problems: %s" % str(ctx.problems))


# --- the content itself ---------------------------------------------------------------------------

func teaching_nodes() -> Dictionary:
	# recipe id -> [{dialogue, node}]
	var out: Dictionary = {}
	for def in ContentDB.all("dialogue"):
		var nodes: Dictionary = def.get("nodes", {})
		for node_id in nodes:
			var node: Dictionary = nodes[node_id]
			for e in node.get("effects", []):
				if typeof(e) == TYPE_DICTIONARY and (e as Dictionary).has("teach_recipe"):
					var recipe := str((e as Dictionary)["teach_recipe"])
					if not out.has(recipe):
						out[recipe] = []
					out[recipe].append({"dialogue": str(def["id"]), "node": node_id})
	return out


func test_every_recipe_nobody_starts_with_can_be_taught_by_somebody() -> void:
	var taught := teaching_nodes()
	for recipe in LOCKED:
		assert_true(ContentDB.has(recipe), "%s is not in the pack" % recipe)
		assert_false(bool(ContentDB.get_or_empty(recipe).get("known_by_default", false)),
				"%s is known by default, so this test is watching the wrong recipe" % recipe)
		assert_true(taught.has(recipe), "nothing in the packs teaches %s" % recipe)
	for recipe in taught:
		assert_true(ContentDB.has(recipe), "a dialogue teaches %s, which does not exist" % recipe)


func test_every_teaching_node_can_be_reached_from_its_dialogue_start() -> void:
	for recipe in teaching_nodes():
		for where in teaching_nodes()[recipe]:
			var def: Dictionary = ContentDB.get_or_empty(str(where["dialogue"]))
			var reach := _reachable(def, false)
			assert_true(reach.has(str(where["node"])),
					"%s.%s teaches %s and cannot be reached from the start node" % [where["dialogue"], where["node"], recipe])


func test_no_recipe_is_handed_over_on_a_path_with_no_gate_on_it() -> void:
	# The same walk, but only through choices and nodes that state no conditions. If a teaching
	# node turns up here, it is free: somebody could wander into it with nothing to their name.
	for recipe in teaching_nodes():
		for where in teaching_nodes()[recipe]:
			var def: Dictionary = ContentDB.get_or_empty(str(where["dialogue"]))
			var free := _reachable(def, true)
			assert_false(free.has(str(where["node"])),
					"%s.%s hands over %s with no condition anywhere on the way in" % [where["dialogue"], where["node"], recipe])


func test_every_teacher_is_somebody_standing_in_the_world() -> void:
	var by_dialogue: Dictionary = {}
	for npc in ContentDB.all("npc"):
		var d := str(npc.get("dialogue", ""))
		if d != "":
			by_dialogue[d] = str(npc["id"])
	for recipe in teaching_nodes():
		for where in teaching_nodes()[recipe]:
			var dialogue := str(where["dialogue"])
			assert_true(by_dialogue.has(dialogue), "%s teaches %s but no NPC uses that dialogue" % [dialogue, recipe])
			var npc: Dictionary = ContentDB.get_or_empty(str(by_dialogue[dialogue]))
			assert_true(ContentDB.has(str(npc.get("home_place", ""))), "%s has no real home_place" % npc.get("id", "?"))


## Node ids reachable from the start. With `only_free`, an edge is taken only when neither the
## choice nor the node it leads to states any condition.
func _reachable(def: Dictionary, only_free: bool) -> Dictionary:
	var nodes: Dictionary = def.get("nodes", {})
	var start := str(def.get("start", "start"))
	var seen: Dictionary = {}
	if not nodes.has(start):
		return seen
	if only_free and not (nodes[start] as Dictionary).get("conditions", []).is_empty():
		return seen
	seen[start] = true
	var stack: Array[String] = [start]
	while not stack.is_empty():
		var current: String = stack.pop_back()
		var node: Dictionary = nodes.get(current, {})
		var edges: Array[String] = []
		for key in ["next", "else"]:
			if node.has(key):
				edges.append(str(node[key]))
		for c in node.get("choices", []):
			if typeof(c) != TYPE_DICTIONARY or not (c as Dictionary).has("next"):
				continue
			if only_free and not ((c as Dictionary).get("conditions", []) as Array).is_empty():
				continue
			edges.append(str((c as Dictionary)["next"]))
		for to in edges:
			if not nodes.has(to) or seen.has(to):
				continue
			if only_free and not ((nodes[to] as Dictionary).get("conditions", []) as Array).is_empty():
				continue
			seen[to] = true
			stack.append(to)
	return seen


# --- Hallam Ashdown: the bell-bronze sword ---------------------------------------------------------

func test_hallam_will_not_teach_bell_bronze_to_a_hand_that_cannot_hold_it() -> void:
	flags().set_flag("hallam_anvil_flat")
	talk(HALLAM)
	pick("Teach me to work bell-bronze")
	assert_false(crafting.knows_recipe("core:recipe/bell_bronze_sword"))
	assert_true(said("draw a full-length blade out of plain iron"), "the refusal names the way back: %s" % transcript())
	assert_clean()


func test_hallam_will_not_teach_bell_bronze_over_an_empty_anvil() -> void:
	flags().set_flag("hallam_anvil_flat")
	player().skills["smithing"] = 60
	talk(HALLAM)
	pick("Teach me to work bell-bronze")
	assert_false(crafting.knows_recipe("core:recipe/bell_bronze_sword"), "hands are not enough without the metal")
	assert_true(said("bring me a piece of it"), transcript())
	assert_clean()


func test_hallam_teaches_bell_bronze_and_the_sword_comes_out_from_under_the_bed() -> void:
	flags().set_flag("hallam_anvil_flat")
	player().skills["smithing"] = 60
	inventory().add(SCRAP, 2)
	talk(HALLAM)
	pick("Teach me to work bell-bronze")
	assert_true(crafting.knows_recipe("core:recipe/bell_bronze_sword"))
	assert_eq(inventory().count(SCRAP), 1, "he keeps one piece to spoil with you")
	assert_true(flags().has_flag("hallam_sword_out"), "the one sword he ever made is on the wall now")
	assert_clean()


func test_the_bell_bronze_topic_opens_for_anybody_carrying_a_piece_of_the_toll() -> void:
	inventory().add(SCRAP, 1)
	talk(HALLAM)
	assert_true(choice_at("Teach me to work bell-bronze") >= 0,
			"the metal in your bag is its own way into the conversation")


# --- Cadwen Ash: the ashen sword -------------------------------------------------------------------

func test_cadwen_asks_for_a_night_before_she_gives_away_the_orders_fire() -> void:
	talk(CADWEN)
	pick("blades are black to the hilt")
	assert_false(crafting.knows_recipe("core:recipe/ashen_sword"))
	assert_true(said("Stand the night first"), transcript())
	assert_true(said("One night at the ring"), "the refusal says exactly what would change it")
	assert_clean()


func test_cadwen_teaches_the_ashen_sword_to_anyone_who_stood_the_watch() -> void:
	flags().set_flag("stood_vigil")
	talk(CADWEN)
	pick("blades are black to the hilt")
	assert_true(crafting.knows_recipe("core:recipe/ashen_sword"))
	assert_eq(inventory().count(BELL_MOULD), 3, "she sends you off with the mould as well")
	assert_clean()


func test_a_ranked_toll_knight_does_not_have_to_stand_it_twice() -> void:
	factions().join(ORDER)
	factions().ranks[ORDER] = 3
	talk(CADWEN)
	pick("blades are black to the hilt")
	assert_true(crafting.knows_recipe("core:recipe/ashen_sword"), "rank in the Order is the same answer by another road")
	assert_clean()


# --- Sorrel Lathe: the Tollmere crossbow -----------------------------------------------------------

func setup_sorrel(rep: int, marks: int, owed: int) -> void:
	if rep != 0:
		factions().add_reputation(TALLYMEN, rep)
	inventory().add_marks(marks)
	if owed > 0:
		bounty().bounties[TALLYMEN] = owed


func test_the_guild_pattern_is_refused_to_anybody_the_watch_wants() -> void:
	setup_sorrel(40, 400, 60)
	talk(SORREL)
	pick("Teach me the pattern")
	assert_false(crafting.knows_recipe("core:recipe/crossbow"))
	assert_true(said("Settle it"), transcript())
	assert_clean()


func test_the_guild_pattern_is_refused_to_a_stranger_the_guild_has_never_written_down() -> void:
	setup_sorrel(0, 400, 0)
	talk(SORREL)
	pick("Teach me the pattern")
	assert_false(crafting.knows_recipe("core:recipe/crossbow"))
	assert_true(said("Come back when there is a line"), transcript())
	assert_clean()


func test_the_register_line_cannot_be_left_blank() -> void:
	setup_sorrel(40, 400, 0)
	talk(SORREL)
	pick("Teach me the pattern")
	pick("That is my business")
	assert_false(crafting.knows_recipe("core:recipe/crossbow"), "no declared use, no pattern")
	assert_false(flags().has_flag("lathe_declared_use"))
	assert_true(said("I cannot do is leave the line blank"), transcript())
	assert_clean()


func test_the_posted_price_is_not_shaved_for_a_good_story() -> void:
	setup_sorrel(40, 100, 0)
	talk(SORREL)
	pick("Teach me the pattern")
	pick("Whatever I meet")
	assert_true(flags().has_flag("lathe_declared_use"), "the use went into the register either way")
	assert_false(crafting.knows_recipe("core:recipe/crossbow"))
	assert_true(said("It will be a hundred and forty then as well"), transcript())
	assert_eq(inventory().marks(), 100, "a refusal costs nothing")
	assert_clean()


func test_sorrel_teaches_the_crossbow_pattern_and_keeps_the_number() -> void:
	setup_sorrel(40, 400, 0)
	talk(SORREL)
	pick("Teach me the pattern")
	pick("The road")
	assert_true(crafting.knows_recipe("core:recipe/crossbow"))
	assert_eq(inventory().marks(), 260, "the posted hundred and forty")
	assert_eq(str(flags().get_flag("lathe_declared_use", "")), "the road", "what you said is what is written")
	assert_clean()


# --- Ordda ko-Brindle: clan plate and the clan bow ---------------------------------------------------

func test_clan_plate_is_refused_until_the_mountain_has_held_you() -> void:
	standing().add_renown(400)
	talk(ORDDA)
	pick("Teach me to face a clan plate")
	assert_false(crafting.knows_recipe("core:recipe/clan_plate"))
	assert_true(said("lie the night in the palm"), transcript())
	assert_clean()


func test_clan_plate_is_refused_to_somebody_the_hold_has_not_heard_of() -> void:
	flags().set_flag("held_by_the_hand")
	talk(ORDDA)
	pick("Teach me to face a clan plate")
	assert_false(crafting.knows_recipe("core:recipe/clan_plate"))
	assert_true(said("It has to be told"), transcript())
	assert_clean()


func test_ordda_teaches_clan_plate_to_somebody_the_hand_held_and_the_roads_talk_about() -> void:
	flags().set_flag("held_by_the_hand")
	standing().add_renown(150)
	talk(ORDDA)
	pick("Teach me to face a clan plate")
	assert_true(crafting.knows_recipe("core:recipe/clan_plate"))
	assert_true(factions().reputation(MOOT) > 0, "the Moot hears about it")
	assert_clean()


func test_the_clan_bow_is_refused_to_somebody_who_cannot_shoot() -> void:
	factions().add_reputation(MOOT, 40)
	talk(ORDDA)
	pick("Teach me the bridge bow")
	assert_false(crafting.knows_recipe("core:recipe/clan_bow"))
	assert_true(said("Put a winter into a plain stave"), transcript())
	assert_clean()


func test_the_clan_bow_is_refused_to_a_stranger_however_well_they_shoot() -> void:
	player().skills["archery"] = 90
	talk(ORDDA)
	pick("Teach me the bridge bow")
	assert_false(crafting.knows_recipe("core:recipe/clan_bow"))
	assert_true(said("Be of some use to the Moot"), transcript())
	assert_clean()


func test_ordda_teaches_the_clan_bow_to_a_shot_the_moot_owes_something() -> void:
	player().skills["archery"] = 35
	factions().add_reputation(MOOT, 15)
	talk(ORDDA)
	pick("Teach me the bridge bow")
	assert_true(crafting.knows_recipe("core:recipe/clan_bow"))
	assert_clean()


# --- Dunna ko-Kharrow: the kingbone greatsword --------------------------------------------------------

func setup_dunna(skill: int, carry_bone: bool) -> void:
	flags().set_flag("stone_thrall_king_fallen")
	player().skills["smithing"] = skill
	if carry_bone:
		inventory().add(KINGBONE, 1)


func test_dunna_has_nothing_to_say_about_kingbone_before_the_king_is_down() -> void:
	player().skills["smithing"] = 100
	inventory().add(KINGBONE, 1)
	talk(DUNNA)
	assert_eq(choice_at("Teach me the saying"), -1, "there is no kingbone in the world yet")
	assert_clean()


func test_dunna_will_not_spend_the_only_kingbone_on_hands_that_are_not_ready() -> void:
	setup_dunna(40, true)
	flags().set_flag("ghorr_remembered")
	talk(DUNNA)
	pick("Teach me the saying")
	assert_false(crafting.knows_recipe("core:recipe/kingbone_greatsword"))
	assert_true(said("Ordda will leave you at her bench unwatched"), transcript())
	assert_clean()


func test_dunna_will_not_say_a_saying_over_an_empty_bench() -> void:
	setup_dunna(75, false)
	flags().set_flag("ghorr_remembered")
	talk(DUNNA)
	pick("Teach me the saying")
	assert_false(crafting.knows_recipe("core:recipe/kingbone_greatsword"))
	assert_true(said("Then bring it"), transcript())
	assert_clean()


func test_dunna_teaches_the_kingbone_working_when_the_moot_has_its_eighth_verse() -> void:
	setup_dunna(75, true)
	flags().set_flag("ghorr_remembered")
	talk(DUNNA)
	pick("Teach me the saying")
	assert_true(crafting.knows_recipe("core:recipe/kingbone_greatsword"))
	assert_true(said("Ghorr"), "she says the name herself: %s" % transcript())
	assert_clean()


func test_dunna_still_teaches_it_when_you_kept_the_name_and_makes_you_say_it_alone() -> void:
	setup_dunna(75, true)
	flags().set_flag("ghorr_unsaid")
	talk(DUNNA)
	pick("Teach me the saying")
	assert_true(crafting.knows_recipe("core:recipe/kingbone_greatsword"),
			"keeping the eighth verse must not lock the blade away for good")
	assert_true(said("alone, in a shop, with the door shut"), transcript())
	assert_false(said("Ghorr"), "she does not say a name she was not given")
	assert_clean()


# --- and then you can actually make the thing ------------------------------------------------------

func test_a_taught_recipe_is_one_the_forge_will_now_accept() -> void:
	flags().set_flag("stood_vigil")
	talk(CADWEN)
	pick("blades are black to the hilt")
	assert_true(crafting.knows_recipe("core:recipe/ashen_sword"))
	assert_eq(Smithing.blocker("core:recipe/ashen_sword", crafting.bag(), 30, "forge", false), "not_known",
			"unknown, the forge turns it away")
	assert_eq(Smithing.blocker("core:recipe/ashen_sword", crafting.bag(), 30, "forge", true), "missing_materials",
			"known, the only thing left in the way is the iron")
