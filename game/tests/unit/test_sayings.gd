extends TestCase
## Sayings end to end (DESIGN §5.3): what a character knows, the three ways to be taught,
## the gate that keeps an untaught saying uncastable, what the screen reads, and the save.
##
## Known sayings live on the Progression node (see DECISIONS.md), so these drive the real
## node, the real Inventory and the real content pack rather than doubles.

const KINDLE := "core:spell/kindle_bolt"
const HUSH_FROST := "core:spell/hush_frost"
const WARD := "core:spell/ward"
const QUIET_BLOOD := "core:spell/quiet_the_blood"
const TOME_KINDLE := "core:item/tome_kindle_bolt"
const TOME_WARD := "core:item/tome_ward"
const BOOK_WARD := "core:book/saying_ward"

var holder: Node
var prog: Progression


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	holder = Node.new()
	prog = Progression.new()
	# Listening is left on: a tome teaches through EventBus.book_opened, which is the same
	# switch that governs skill XP, and these tests are about what that path does.
	prog.listen_to_event_bus = true
	holder.add_child(prog)
	_tree().root.add_child(holder)


func after_each() -> void:
	holder.free()


# --- content -----------------------------------------------------------------------------

func test_every_saying_has_a_tome_and_every_tome_a_saying() -> void:
	var spells := ContentDB.ids_of("spell")
	assert_eq(spells.size(), 15, "the five schools, three sayings each")
	var taught: Dictionary = {}
	for book in ContentDB.all("book"):
		var spell := str(book.get("teaches_spell", ""))
		if spell == "":
			continue
		assert_true(ContentDB.has(spell), "%s teaches unknown %s" % [book["id"], spell])
		assert_gt(str(book.get("body", "")).length(), 400, "%s has no working written in it" % book["id"])
		assert_false(taught.has(spell), "two books teach %s" % spell)
		taught[spell] = book["id"]
	for id in spells:
		assert_true(taught.has(id), "no book teaches %s" % id)
	# and each of those books is carried by exactly one item somebody could own
	var carried: Dictionary = {}
	for item in ContentDB.all("item"):
		var reads := str(item.get("reads", ""))
		if not taught.values().has(reads):
			continue
		assert_eq(str(item.get("category", "")), "book", "a tome is a book you can carry")
		assert_gt(int(item.get("value", 0)), 0, "%s must be worth something" % item["id"])
		assert_false(carried.has(reads), "two items carry %s" % reads)
		carried[reads] = item["id"]
	assert_eq(carried.size(), 15, "every saying-book is a thing somebody can own")


func test_the_first_rung_of_each_school_is_within_a_starting_purse() -> void:
	# A new character carries 15 to 60 marks. The cheapest tome in each school has to be
	# reachable on the first day, or magic is something only the rich ever try.
	var cheapest: Dictionary = {}
	for item in ContentDB.all("item"):
		var spell := str(ContentDB.get_or_empty(str(item.get("reads", ""))).get("teaches_spell", ""))
		if spell == "":
			continue
		var school := str(ContentDB.get_or_empty(spell).get("school", ""))
		var value := int(item.get("value", 0))
		if not cheapest.has(school) or value < int(cheapest[school]):
			cheapest[school] = value
	for school: String in ["kindling", "hush", "binding", "mending"]:
		assert_true(int(cheapest.get(school, 9999)) <= 40,
				"the first %s tome costs %d, more than a new purse holds" % [school, int(cheapest.get(school, -1))])


func test_the_sayer_callings_start_with_a_saying_and_the_others_do_not() -> void:
	var with_sayings := 0
	for calling in ContentDB.all("calling"):
		var starting: Array = calling.get("starting_spells", [])
		for id in starting:
			assert_true(ContentDB.has(str(id)), "%s starts with unknown %s" % [calling["id"], id])
		if starting.is_empty():
			continue
		with_sayings += 1
		# a calling only starts with what its own bonuses point at
		var schools: Array = []
		for skill in calling.get("skill_bonuses", {}):
			if SpellRuntime.SCHOOLS.has(str(skill)):
				schools.append(str(skill))
		for id in starting:
			assert_true(schools.has(SpellRuntime.school_of(ContentDB.get_or_empty(str(id)))),
					"%s starts with %s but is not trained in its school" % [calling["id"], id])
	assert_eq(with_sayings, 3, "Reedborn, Ashwalker and Lantern-Clerk; nobody else")


# --- learning ----------------------------------------------------------------------------

func test_learning_a_saying_and_learning_it_twice() -> void:
	var heard: Array[String] = []
	var cb := func(id: String) -> void: heard.append(id)
	EventBus.spell_learned.connect(cb)
	assert_false(prog.knows_spell(KINDLE))
	assert_true(prog.learn_spell(KINDLE), "the first time takes")
	assert_true(prog.knows_spell(KINDLE))
	assert_false(prog.learn_spell(KINDLE), "the second time is not news")
	EventBus.spell_learned.disconnect(cb)
	assert_eq(heard, [KINDLE], "learning it twice announces it once")
	assert_eq(prog.known_spells.size(), 1)


func test_a_saying_nobody_wrote_is_refused() -> void:
	assert_false(prog.learn_spell("core:spell/ghost_word"))
	assert_false(prog.learn_spell("core:item/bread"), "an item is not a saying")
	assert_false(prog.learn_spell(""))
	assert_empty(prog.known_spells)


func test_the_calling_hands_over_its_starting_sayings() -> void:
	assert_true(prog.apply_calling("core:calling/ashwalker"))
	assert_true(prog.knows_spell(KINDLE), "the Ash-Pilgrim comes up Kindling")
	assert_true(prog.knows_spell(QUIET_BLOOD))
	assert_false(prog.knows_spell(WARD))

	var plain := Progression.new()
	plain.listen_to_event_bus = false
	holder.add_child(plain)
	assert_true(plain.apply_calling("core:calling/wayfarer"))
	assert_empty(plain.known_spells, "the Wayfarer was never taught a thing")


func test_reading_a_tome_teaches_the_saying_in_it() -> void:
	var bag := Inventory.new()
	holder.add_child(bag)
	bag.add(TOME_KINDLE, 1)
	assert_true(bag.use(TOME_KINDLE), "the inventory screen's Read button")
	assert_true(prog.knows_spell(KINDLE))
	assert_eq(bag.count(TOME_KINDLE), 1, "a book is read, not eaten")
	close_screen("book", "a tome read out of the bag is drawn in the reader")


func test_a_tome_read_off_a_shelf_teaches_the_same_thing() -> void:
	# Nothing is carried here: the book is simply opened, the way a Readable in a room opens it.
	EventBus.book_opened.emit(BOOK_WARD)
	assert_true(prog.knows_spell(WARD))
	var said: Array[String] = []
	var cb := func(text: String, _kind: String) -> void: said.append(text)
	EventBus.notify.connect(cb)
	EventBus.book_opened.emit(BOOK_WARD)
	EventBus.notify.disconnect(cb)
	assert_eq(said.size(), 1, "re-reading says something rather than nothing")
	assert_true(said[0].contains("already"), "and says it is already known: '%s'" % said[0])
	close_screen("book", "a tome opened off a shelf is drawn in the reader")


func test_a_book_with_no_working_in_it_teaches_no_saying() -> void:
	EventBus.book_opened.emit("core:book/naming_day_primer")
	assert_empty(prog.known_spells)
	close_screen("book", "an ordinary book is still read")


func test_a_tome_says_what_it_opens_in_its_summary() -> void:
	var bag := Inventory.new()
	holder.add_child(bag)
	var stack := bag.add(TOME_WARD, 1)
	var summary := stack.summary()
	assert_eq(str(summary["reads"]), BOOK_WARD)
	assert_true(bool(summary["readable"]), "the screen needs a Read button")
	assert_false(bool(summary["consumable"]), "a tome is not food")


func test_a_sayer_teaches_through_the_dialogue_effect() -> void:
	var ctx := SocialContext.new()
	var sayings := SocialFakes.Sayings.new()
	ctx.set_provider("sayings", sayings)
	Effects.apply({"teach_spell": HUSH_FROST}, ctx)
	assert_eq(sayings.known, [HUSH_FROST])
	assert_empty(ctx.problems)
	assert_true(Conditions.check({"knows_spell": HUSH_FROST}, ctx))
	assert_false(Conditions.check({"knows_spell": WARD}, ctx))


func test_teaching_with_nobody_listening_is_a_reported_problem_not_a_silent_loss() -> void:
	var ctx := SocialContext.new()
	Effects.apply({"teach_spell": HUSH_FROST}, ctx)
	assert_eq(ctx.problems.size(), 1, "a lost teaching must be loud")


func test_the_real_progression_node_serves_as_the_sayings_provider() -> void:
	var ctx := SocialContext.new()
	ctx.set_provider("sayings", prog)
	Effects.apply({"teach_spell": WARD}, ctx)
	assert_true(prog.knows_spell(WARD), "Social binds the progression group to 'sayings'")


func test_a_quest_reward_can_teach_one() -> void:
	# Quest rewards run their `effects` through the same vocabulary, so a faction line that
	# ends in a saying needs no code of its own — but it does need to be real.
	var found := 0
	for quest in ContentDB.all("quest"):
		for effect in (quest.get("rewards", {}) as Dictionary).get("effects", []):
			if typeof(effect) == TYPE_DICTIONARY and effect.has("teach_spell"):
				found += 1
				assert_true(ContentDB.has(str(effect["teach_spell"])),
						"%s rewards an unknown saying" % quest["id"])
	assert_gt(found, 0, "at least one questline should end in a saying")


# --- the gate ----------------------------------------------------------------------------

func test_the_rules_refuse_a_saying_nobody_taught() -> void:
	var def := ContentDB.get_or_empty(KINDLE)
	var untaught := SpellRuntime.can_cast(def, 100.0, false, 0.0, false, false)
	assert_false(bool(untaught["ok"]))
	assert_eq(str(untaught["reason"]), "not_known")
	assert_true(bool(SpellRuntime.can_cast(def, 100.0, false, 0.0, false, true)["ok"]))
	assert_true(bool(SpellRuntime.can_cast(def, 100.0, false)["ok"]), "known by default, for enemy casters")


func test_a_caster_asks_before_it_says_anything() -> void:
	var caster := SpellCaster.new()
	caster.auto_advance = false
	holder.add_child(caster)
	caster.setup(null, 20)
	var refused: Array[String] = []
	caster.cast_failed.connect(func(_id: String, reason: String) -> void: refused.append(reason))
	caster.known_lookup = func(id: String) -> bool: return prog.knows_spell(id)

	assert_false(caster.cast(KINDLE), "not taught, not cast")
	assert_eq(refused, ["not_known"])
	assert_near(caster.mana, caster.mana_max, 0.001, "a refused cast spends nothing")

	prog.learn_spell(KINDLE)
	assert_true(caster.cast(KINDLE))
	assert_true(caster.mana < caster.mana_max, "a real cast costs breath")


func test_the_reasons_a_cast_fails_are_all_distinguishable() -> void:
	var def := ContentDB.get_or_empty(KINDLE)
	assert_eq(str(SpellRuntime.can_cast({}, 99.0, false)["reason"]), "unknown")
	assert_eq(str(SpellRuntime.can_cast(def, 99.0, false, 0.0, false, false)["reason"]), "not_known")
	assert_eq(str(SpellRuntime.can_cast(def, 99.0, false, 0.0, true)["reason"]), "busy")
	assert_eq(str(SpellRuntime.can_cast(def, 99.0, true)["reason"]), "silenced")
	assert_eq(str(SpellRuntime.can_cast(def, 1.0, false)["reason"]), "mana")


# --- the screen reads ---------------------------------------------------------------------

func test_the_listing_is_grouped_by_school_and_priced_for_this_character() -> void:
	for id in [QUIET_BLOOD, KINDLE, WARD]:
		prog.learn_spell(id)
	var listed := prog.spells()
	assert_eq(listed.size(), 3)
	assert_eq(str(listed[0]["school"]), "kindling", "the five schools keep DESIGN's order")
	assert_eq(str(listed[1]["school"]), "binding")
	assert_eq(str(listed[2]["school"]), "mending")
	assert_eq(str(listed[0]["id"]), KINDLE)
	assert_near(float(listed[0]["cost"]), SpellRuntime.cost_of(ContentDB.get_or_empty(KINDLE),
			prog.effective_skill("kindling")), 0.001)
	assert_ne(str(listed[0]["school_name"]), "", "the school has a name to print")
	assert_ne(str(listed[0]["description"]), "")


func test_every_saying_can_be_put_into_plain_words() -> void:
	var screen: GDScript = load("res://ui/sayings/sayings_screen.gd")
	for id in ContentDB.ids_of("spell"):
		prog.learn_spell(id)
	for s in prog.spells():
		var lines: Array = screen.plain_words(s)
		assert_gt(lines.size(), 0, "%s says nothing about itself" % s["id"])
		for line in lines:
			assert_false(str(line).contains("core:"), "%s leaks an id into the page" % s["id"])
			assert_ne(str(line), "Nothing anybody has written down.", "%s has no plain words" % s["id"])


# --- save ---------------------------------------------------------------------------------

func test_known_sayings_survive_a_round_trip() -> void:
	prog.learn_spell(KINDLE)
	prog.learn_spell(WARD)
	var saved := prog.to_save()
	var other := Progression.new()
	other.listen_to_event_bus = false
	holder.add_child(other)
	other.from_save(saved)
	assert_true(other.knows_spell(KINDLE))
	assert_true(other.knows_spell(WARD))
	assert_eq(other.known_spells.size(), 2)


func test_an_old_save_with_no_sayings_key_loads_clean() -> void:
	prog.learn_spell(KINDLE)
	prog.from_save({"calling": "", "skills": {}, "leveling": {}, "perks": {}})
	assert_empty(prog.known_spells, "a missing key means nothing learned, not a crash")


func test_a_saying_whose_pack_is_gone_is_dropped_on_load() -> void:
	prog.from_save({"known_spells": [KINDLE, "core:spell/from_a_pack_that_left"]})
	assert_eq(prog.known_spells, [KINDLE] as Array[String])


func test_the_v2_migration_carries_a_readied_saying_into_what_is_known() -> void:
	var old := {"schema_version": 2, "sections": {
		"player": {"equipped_spell": KINDLE},
		"progression": {"calling": "core:calling/ashwalker", "skills": {}},
	}}
	var m := Migrations.migrate(old)
	assert_eq(int(m["schema_version"]), SaveSystem.SCHEMA_VERSION)
	assert_has(m["sections"]["progression"], "known_spells")
	assert_eq(m["sections"]["progression"]["known_spells"], [KINDLE],
			"the saying they had readied is one they plainly knew")
	assert_eq(str(m["sections"]["progression"]["calling"]), "core:calling/ashwalker",
			"the rest of the section is left alone")


func test_the_v2_migration_leaves_a_character_who_never_cast_with_nothing() -> void:
	var m := Migrations.migrate({"schema_version": 2, "sections": {"player": {"marks": 10}}})
	assert_empty(m["sections"]["progression"]["known_spells"])
	assert_empty(Migrations.migrate({"schema_version": 2, "sections": {}})["sections"]["progression"]["known_spells"])
