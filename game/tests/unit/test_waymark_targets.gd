extends TestCase
## Markers on the objective, not on the quest giver (triage 49). The user: "The objective icon
## keeps marking the quest giver, not the objective". Every `act` objective with no place had been
## sent to its teacher; a lesson now points at what it is made on (a prop of its kind, the foes, a
## named spot, where going unseen is going), and the teacher only when nothing says anything.
##
## The audit walks every objective of every quest in the pack and fails on any that ends up on the
## giver while the content says something better.

const LAMP := "core:place/the_lamp"
const MOREVA := "core:place/moreva"

var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _stage(quest_id: String, stage_id: String) -> Dictionary:
	for s in ContentDB.get_or_empty(quest_id).get("stages", []):
		if str((s as Dictionary).get("id", "")) == stage_id:
			return s
	return {}


# --- the audit ----------------------------------------------------------------------------------

## Whether the content says something about where an objective is that is not its giver: a named
## target, spot or place, or a kind of objective that is never about a person.
static func _says_better(quest: Dictionary, o: Dictionary) -> String:
	for key in ["against", "spot", "where", "place"]:
		var v := str(o.get(key, ""))
		if v != "" and v != str(quest.get("giver", "")):
			return "it names %s %s" % [key, v]
	var type := str(o.get("type", ""))
	# (a thing to read, gather or use may be the giver's to hand over: that is where it is got)
	if type in ["reach", "kill", "rest_at", "act", "escort"]:
		return "a %s is never about the one who gave it" % type
	return ""


func test_no_objective_is_marked_on_its_giver_while_a_better_target_exists() -> void:
	var bad: Array[String] = []
	var on_giver := 0
	var walked := 0
	var quests := ContentDB.all("quest")
	quests.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["id"]) < str(y["id"]))
	for def in quests:
		if str(def.get("layer", "")) == "radiant":
			continue
		var giver := str(def.get("giver", ""))
		for stage_v in def.get("stages", []):
			var stage: Dictionary = stage_v
			var objs: Array = stage.get("objectives", [])
			for i in objs.size():
				var o: Dictionary = objs[i]
				walked += 1
				var a := Waymarks.anchor(def, stage, o)
				if giver == "" or str(a.get("kind", "")) not in ["npc", "escort"] or str(a.get("npc", "")) != giver:
					continue
				if str(o.get("target", "")) == giver:
					continue      # to speak to them, or take them something: they are the objective
				on_giver += 1
				var why := _says_better(def, o)
				if why != "":
					bad.append("%s / %s #%d [%s %s]: on %s, but %s" % [Ids.name_of(str(def["id"])), stage.get("id", ""), i,
							o.get("type", ""), o.get("target", ""), Ids.name_of(giver), why])
	print("  waymark targets: %d objectives, %d on their giver by right of content, %d wrongly" % [walked, on_giver, bad.size()])
	for line in bad:
		print("    ON THE GIVER " + line)
	assert_gt(walked, 400, "the walk covers the pack")
	assert_empty(bad, "no objective is marked on its giver while its content says where it is")


func test_no_lesson_of_a_style_start_points_at_its_teacher() -> void:
	for style in StyleDef.all_styles():
		var quest := ContentDB.get_or_empty(str(style.get("tutorial", "")))
		var teacher := str(style.get("teacher", ""))
		for stage_v in quest.get("stages", []):
			var stage: Dictionary = stage_v
			var objs: Array = stage.get("objectives", [])
			for i in objs.size():
				var o: Dictionary = objs[i]
				if str(o.get("type", "")) != "act":
					continue
				var a := Waymarks.anchor(quest, stage, o)
				assert_false(str(a.get("npc", "")) == teacher and str(a.get("kind", "")) == "npc",
						"%s / %s #%d (%s) points at %s, not the teacher" % [Ids.name_of(str(quest["id"])), stage.get("id", ""), i,
						o.get("target", ""), a.get("kind", "")])
				assert_true(Waymarks.map_xz_of(a) != Vector2.INF, "%s / %s #%d is somewhere on the chart" % [
						Ids.name_of(str(quest["id"])), stage.get("id", ""), i])


# --- the convention, on fixtures ------------------------------------------------------------------

func _lesson_quest() -> Dictionary:
	return {"id": "core:quest/_lessons", "giver": "core:npc/tamsin_wick", "layer": "main",
		"props": [
			{"kind": "brazier", "name": "_b_near", "place": LAMP, "bearing": 90, "distance": 10},
			{"kind": "brazier", "name": "_b_far", "place": LAMP, "bearing": 90, "distance": 40},
			{"kind": "strongbox", "name": "_box", "place": LAMP, "bearing": 0, "distance": 20, "loot": "core:loot/tithe_strongbox"},
			{"kind": "cover", "look": "traps", "name": "_traps", "place": LAMP, "bearing": 180, "distance": 30}],
		"spots": [{"name": "_the_shingle", "place": LAMP, "bearing": 270, "distance": 25}]}


func test_a_prop_lesson_points_at_the_props_of_its_kind() -> void:
	var q := _lesson_quest()
	var a := Waymarks.anchor(q, {"marker": {"place_id": LAMP}}, {"type": "act", "target": "kindle", "against": "prop:brazier"})
	assert_eq(str(a["kind"]), "prop")
	assert_eq(str(a["prop"]), "brazier")
	assert_eq((a["names"] as Array).size(), 2, "both of the quest's braziers")
	assert_near(Waymarks.map_xz_of(a).distance_to(PlaceRef.point_xz(q["props"][0])), 0.0, 0.01, "on the chart, a brazier")
	var traps := Waymarks.anchor(q, {}, {"type": "act", "target": "sneak", "against": "prop:traps"})
	assert_eq(str(traps["kind"]), "prop", "a cover by its look")
	assert_eq((traps["names"] as Array), ["_traps"] as Array)


func test_a_lock_and_what_it_keeps_point_at_the_strongbox() -> void:
	var q := _lesson_quest()
	var pick := Waymarks.anchor(q, {}, {"type": "act", "target": "pick_lock"})
	assert_eq(str(pick["kind"]), "prop")
	assert_eq(str(pick["prop"]), "strongbox", "the lock is the quest's box")
	var book := Waymarks.anchor(ContentDB.get_or_empty("core:quest/first_rogue"), {}, {"type": "collect", "target": "core:item/tithe_book"})
	assert_eq(str(book["kind"]), "prop", "a thing in a quest's container marks the container")
	assert_eq(str(book["prop"]), "strongbox")


func test_a_spot_and_a_lesson_on_foes_point_there() -> void:
	var q := _lesson_quest()
	var spot := Waymarks.anchor(q, {}, {"type": "act", "target": "cast", "spot": "_the_shingle"})
	assert_eq(str(spot["kind"]), "spot")
	assert_near(Waymarks.map_xz_of(spot).distance_to(PlaceRef.point_xz(q["spots"][0])), 0.0, 0.01)
	var stage := {"objectives": [{"type": "kill", "target": "core:enemy/gutter_drake", "where": LAMP, "radius": 120},
			{"type": "act", "target": "ward", "against": "core:enemy/gutter_drake"},
			{"type": "act", "target": "cast", "detail": "core:spell/hush_frost"}]}
	var ward := Waymarks.anchor(q, stage, stage["objectives"][1])
	assert_eq(str(ward["kind"]), "foes", "a lesson against a foe is the foes")
	assert_eq(str(ward["where"]), LAMP, "where the stage fights them")
	var cast := Waymarks.anchor(q, stage, stage["objectives"][2])
	assert_eq(str(cast["kind"]), "foes", "a saying with no target named is cast in the stage's fight")


func test_going_unseen_points_where_it_is_going() -> void:
	# the Rogue's night in a thief's order (triage 51): crouching at the box goes where the crouch is for,
	# the strongbox, not the teacher; carrying the book down goes to Sauve, held at his traps
	var rogue := ContentDB.get_or_empty("core:quest/first_rogue")
	var stage := _stage("core:quest/first_rogue", "the_strongbox")
	var a := Waymarks.anchor(rogue, stage, (stage["objectives"] as Array)[0])
	assert_ne(str(a["kind"]), "npc", "the crouch at the box points at the box, not Sauve: %s" % str(a))
	var held := false
	for h in ContentDB.get_or_empty("core:npc/sauve_mor").get("holds", []):
		if str((h as Dictionary).get("spot", "")) == "sauve_traps" and str((h as Dictionary).get("when", [])).contains("the_traps"):
			held = true
	assert_true(held, "and while the book goes down, Sauve is held at his traps, down at the channel's edge")


func test_a_teacher_only_when_nothing_else_is_said() -> void:
	var q := {"id": "core:quest/_bare", "giver": "core:npc/tamsin_wick"}
	var a := Waymarks.anchor(q, {"marker": {"place_id": LAMP, "radius": 60}}, {"type": "act", "target": "swap"})
	assert_eq(str(a["kind"]), "place", "the stage's place first")
	var last := Waymarks.anchor(q, {}, {"type": "act", "target": "swap"})
	assert_eq(str(last["kind"]), "npc", "and the teacher when nothing at all says where")
	assert_true(bool(last.get("last_resort", false)))


# --- the live world ---------------------------------------------------------------------------------

func _brazier(at: Vector3) -> Pell:
	var p := Pell.new()
	p.kind = "brazier"
	_tree().root.add_child(p)
	p.global_position = at
	_nodes.append(p)
	return p


func test_the_compass_goes_to_the_nearest_unlit_brazier_and_the_chart_agrees() -> void:
	var q := _lesson_quest()
	var a := Waymarks.anchor(q, {}, {"type": "act", "target": "kindle", "against": "prop:brazier"})
	var near := _brazier(Vector3(100, 0, 100))
	var far := _brazier(Vector3(100, 0, 160))
	var from := Vector3(100, 0, 90)
	var got := Waymarks.locate(a, from)
	assert_true(bool(got["ok"]) and bool(got["live"]), "a brazier standing, not a place")
	assert_near(Waymarks._flat(got["at"], near.global_position), 0.0, 0.01, "the nearest")
	assert_eq(got["map_xz"], Vector2(near.global_position.x, near.global_position.z), "the chart's pin where the compass points")
	near.lit = true
	var next := Waymarks.locate(a, from)
	assert_near(Waymarks._flat(next["at"], far.global_position), 0.0, 0.01, "a lit one is done: the next")


func test_a_bout_not_begun_points_at_whoever_begins_it() -> void:
	var warrior := ContentDB.get_or_empty("core:quest/first_warrior")
	var stage := _stage("core:quest/first_warrior", "the_ring")
	if stage.is_empty() or not stage.has("spar"):
		return
	var block: Dictionary = {}
	for o in stage["objectives"]:
		if str((o as Dictionary).get("target", "")) == "block":
			block = o
	if block.is_empty():
		return
	var a := Waymarks.anchor(warrior, stage, block)
	assert_eq(str(a["kind"]), "foes", "the sparring foe")
	assert_eq(str(a.get("npc", "")), str((stage["spar"] as Dictionary).get("npc", "")), "and, before the bout, who begins it")
