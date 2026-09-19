extends TestCase

var _nodes: Array[Node] = []


func before_each() -> void:
	Peers.overrides.clear()
	GameState.reset_for_new_game(1)
	WorldClock.set_time(12.0, 3)
	if Bounty.instance != null:
		Bounty.instance.clear_all()
	# The NPC registry outlives a single test file; start from fresh dispositions and
	# nobody hostile, or another file's hostility decides these reactions.
	var reg := NpcRegistry.instance
	if reg != null:
		reg.states.clear()
		reg.rebuild()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()
	if Reactions.instance != null:
		Reactions.instance.forget_all()
	if Bounty.instance != null:
		Bounty.instance.clear_all()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _profile(renown: int, morality: int, title := "") -> Dictionary:
	return {"renown_tier": renown, "morality_tier": morality, "title": title}


func _plain() -> Personality:
	return Personality.of([])


# --- the rule ------------------------------------------------------------------------------

func test_unknown_player_is_simply_greeted() -> void:
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), []), "greet")
	assert_eq(Reactions.choose(_profile(0, 0), Personality.of(["quiet"]), []), "ignore", "the quiet say nothing")


func test_renown_earns_cheers_and_crowds() -> void:
	assert_eq(Reactions.choose(_profile(1, 0), _plain(), []), "greet")
	assert_eq(Reactions.choose(_profile(1, 0), Personality.of(["proud"]), []), "bow")
	assert_eq(Reactions.choose(_profile(2, 0), _plain(), []), "cheer")
	assert_eq(Reactions.choose(_profile(3, 0), _plain(), [], {"nearby": 0}), "cheer", "alone, nobody can crowd")
	assert_eq(Reactions.choose(_profile(3, 0), _plain(), [], {"nearby": 3}), "crowd")
	assert_eq(Reactions.choose(_profile(4, 2), _plain(), [], {"nearby": 5}), "crowd")


func test_hollow_and_bounty_frighten() -> void:
	assert_eq(Reactions.choose(_profile(0, -2), _plain(), []), "flinch")
	assert_eq(Reactions.choose(_profile(0, -3), _plain(), []), "flee", "deep Hollow empties a street")
	assert_eq(Reactions.choose(_profile(0, -2), Personality.of(["timid"]), []), "flee")
	assert_eq(Reactions.choose(_profile(0, -2), Personality.of(["brave"]), []), "confront", "the brave stand their ground")
	assert_eq(Reactions.choose(_profile(4, -2), _plain(), [], {"nearby": 5}), "flinch", "fame does not undo the Hollow")
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), [], {"bounty": 20}), "flinch")
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), [], {"bounty": 20, "wanted": true}), "flinch")
	assert_eq(Reactions.choose(_profile(0, 0), Personality.of(["brave"]), [], {"wanted": true}), "flinch", "the brave do not flee a warrant, but they do not meet your eye either")
	assert_eq(Reactions.choose(_profile(0, -3), Personality.of(["brave"]), [], {"wanted": true}), "flee", "brave and Hollow and wanted is too much")
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), [], {"hostile": true}), "confront")


func test_children_follow_or_hide() -> void:
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), ["child"]), "greet")
	assert_eq(Reactions.choose(_profile(2, 1), _plain(), ["child"]), "follow", "children trail the famous")
	assert_eq(Reactions.choose(_profile(4, 2), _plain(), ["child"]), "follow")
	assert_eq(Reactions.choose(_profile(4, -2), _plain(), ["child"]), "hide")
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), ["child"], {"wanted": true}), "hide")


func test_dogs_growl_at_the_hollow() -> void:
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), ["dog"]), "ignore")
	assert_eq(Reactions.choose(_profile(0, -2), _plain(), ["dog"]), "growl")
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), ["dog"], {"wanted": true}), "growl")
	assert_eq(Reactions.choose(_profile(0, 2), _plain(), ["dog"]), "follow", "dogs know a kind one")
	assert_eq(Reactions.choose(_profile(3, 0), _plain(), ["dog"]), "follow")
	assert_eq(Reactions.choose(_profile(4, -3), _plain(), ["dog"], {"nearby": 4}), "growl", "renown does not fool a dog")


func test_guards_read_the_ledger_first() -> void:
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), ["guard"]), "greet")
	assert_eq(Reactions.choose(_profile(4, 3), _plain(), ["guard"], {"nearby": 9}), "greet", "no crowd around a guard")
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), ["guard"], {"bounty": 20}), "confront")
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), ["guard"], {"bounty": 5}), "greet", "a trespass is not worth the walk")
	assert_eq(Reactions.choose(_profile(0, 0), _plain(), ["guard"], {"wanted": true}), "confront")
	assert_eq(Reactions.choose(_profile(0, -2), _plain(), ["guard"]), "watch")


func test_barred_doors() -> void:
	assert_false(Reactions.door_barred(_profile(0, 0), "vale"))
	assert_true(Reactions.door_barred(_profile(0, -2), "vale"), "Hollow villages bar their doors")
	assert_true(Reactions.door_barred(_profile(0, -3), "clans"))
	assert_false(Reactions.door_barred(_profile(0, -2), "woodfolk"), "the Woodfolk have no doors to bar")
	assert_false(Reactions.door_barred(_profile(0, -2), "pilgrims"), "Cinderlea's people are kind and doomed")
	assert_true(Reactions.door_barred(_profile(0, 0), "vale", true), "a wanted stranger finds doors shut")
	assert_false(Reactions.door_barred(_profile(0, 0), "clans", true))


func test_lines_and_intents() -> void:
	assert_true(Reactions.line_for("greet", "Bram").contains("Bram"))
	assert_true(Reactions.line_for("bow", "Bram", "Hearth-Warden").contains("Hearth-Warden"))
	assert_true(Reactions.line_for("crowd", "Bram").length() > 0)
	assert_eq(Reactions.line_for("ignore", "Bram"), "", "silence has no line")
	assert_eq(Reactions.intent_for("greet"), "Wave")
	assert_eq(Reactions.intent_for("cheer"), "Cheer")
	assert_eq(Reactions.intent_for("hide"), "Cower")
	assert_eq(Reactions.intent_for("bow"), "Bow_Gesture")
	assert_eq(Reactions.intent_for("ignore"), "Idle")


# --- the service --------------------------------------------------------------------------------

func _standing(renown: int, morality: int, title := "") -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar rt := 0\nvar mt := 0\nvar t := \"\"\nfunc reaction_profile() -> Dictionary:\n\treturn {\"renown_tier\": rt, \"morality_tier\": mt, \"title\": t}\n"
	s.reload()
	var n := Node.new()
	n.set_script(s)
	n.set("rt", renown)
	n.set("mt", morality)
	n.set("t", title)
	_nodes.append(n)
	Peers.overrides["standing"] = n
	return n


func test_service_reacts_once_per_approach() -> void:
	var r := Reactions.ensure()
	assert_true(r.is_in_group("reactions"))
	_standing(2, 0)
	var fired: Array = []
	var cb := func(id: String, kind: String) -> void: fired.append([id, kind])
	r.reaction.connect(cb)
	var npc := "core:npc/example_thatcher_bram"
	assert_eq(r.on_player_near(npc, 30.0), "", "too far to notice")
	assert_eq(r.on_player_near(npc, 5.0), "cheer")
	assert_eq(fired.size(), 1)
	assert_eq(r.on_player_near(npc, 4.0), "", "he has already said hello")
	assert_eq(fired.size(), 1)
	r.on_player_near(npc, 20.0)
	assert_eq(r.on_player_near(npc, 5.0), "cheer", "you went away and came back")
	assert_eq(fired.size(), 2)
	r.reaction.disconnect(cb)


func test_service_reads_the_real_bounty_and_tags() -> void:
	var r := Reactions.ensure()
	var b := Bounty.ensure()
	_standing(0, 0)
	GameState.enter_region("core:region/hearthvale")
	assert_eq(r.choose_for("core:npc/example_child_tibb"), "greet")
	assert_eq(r.choose_for("core:npc/example_dog_gosling"), "ignore")
	b.add("core:faction/wardens", 50, "core:place/merrowby")
	assert_true(r.wanted_here("core:region/hearthvale"))
	assert_eq(r.bounty_here("core:region/hearthvale"), 50)
	assert_eq(r.choose_for("core:npc/example_child_tibb"), "hide", "children hide from the wanted")
	assert_eq(r.choose_for("core:npc/example_dog_gosling"), "growl")
	assert_eq(r.choose_for("core:npc/guard_wardens"), "confront")
	b.clear("core:faction/wardens")
	assert_eq(r.choose_for("core:npc/guard_wardens"), "greet")


func test_service_emits_a_line() -> void:
	var r := Reactions.ensure()
	_standing(3, 2, "the Bell-Named")
	var lines: Array = []
	var cb := func(text: String, kind: String) -> void:
		if kind == "reaction":
			lines.append(text)
	EventBus.notify.connect(cb)
	var kind := r.react("core:npc/example_thatcher_bram")
	assert_eq(kind, "cheer")
	assert_eq(lines.size(), 1)
	assert_true(lines[0].contains("Bram"))
	EventBus.notify.disconnect(cb)


func test_disabled_service_is_silent() -> void:
	var r := Reactions.ensure()
	_standing(4, 0)
	r.enabled = false
	assert_eq(r.react("core:npc/example_thatcher_bram"), "")
	r.enabled = true
