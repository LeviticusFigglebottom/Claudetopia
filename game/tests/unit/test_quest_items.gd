extends TestCase
## The things the quests send you to pick up, lying where the quests say.
##
## Fourteen quests sent you for something nothing in the game gave, sold or put anywhere, so
## eighteen objectives waited for an item that did not exist. `QuestItems` puts them down as the
## world streams in, and inside the houses and deep places as they are built, and remembers what
## has been taken.
##
## The streaming half reads the built world (`./run.sh world`); when it is missing it says so once
## and those cases skip.

const GENERATED := "res://world/generated"

## What lies where, read off each quest's own stage: the objective's `where`, or the place the
## same stage sends you to.
const EXPECTED := {
	"item:core:item/tuning_tine": "core:place/cracked_toll",
	"item:core:item/lip_inscription": "core:place/cracked_toll",
	"item:core:item/wardens_hand_bell": "core:poi/tumbled_watchtower",
	"item:core:item/ledger_of_prices": "core:interior/undercroft",
	"item:core:item/stewards_brass_key": "core:interior/ellard_steward",
	"item:core:item/quills_daybook": "core:place/tollmere",
	"item:core:item/press_screw": "core:place/tamwick",
	"item:core:item/sluice_pin": "core:place/chalk_hound",
	"item:core:item/clan_forged_link": "core:poi/clanless_camp",
	"item:core:item/salissas_lantern": "core:poi/wisp_hollow",
	"item:core:item/sul_stone_sliver": "core:poi/north_cliff_beacon",
	"item:core:item/forged_charter_chit": "core:poi/gullhithe_wreck",
	"item:core:item/scraped_roll_page": "core:place/sayers_spire",
	"item:core:item/kharrow_memory_song": "core:interior/dunna_cliff_hold",
	"item:core:item/the_going_out": "core:interior/tallissa_stilt",
	"choice:core:quest/the_held_note|the_held_note": "core:interior/cantors_seat",
}

## What the story hands over, a shopkeeper sells, or a boss drops: none of it also lies about.
const NOT_LYING_ABOUT := ["core:item/nave_bell", "core:item/pilgrims_bell_aud", "core:item/fennick_bell",
		"core:item/hearth_loaf", "core:item/lecture_on_saying", "core:item/the_reed_round",
		"core:item/tessanes_lantern", "core:item/harewell_doorstep_stone", "core:item/speaking_stone"]

var items: QuestItems
var host: Node3D
var provider: TerrainProvider = null
var pois: Array = []
static var _warned := false


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	host = Node3D.new()
	host.name = "QuestItemsTestHost"
	_tree().root.add_child(host)
	# The one the world's builders find by group: a suite that has stood up the world services
	# already has one, and a second would never be asked.
	items = QuestItems.ensure()
	items.clear()
	if provider == null and FileAccess.file_exists("%s/pois.json" % GENERATED):
		provider = TerrainProvider.new()
		provider.load_data()
		pois = JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED))
	elif provider == null and not _warned:
		_warned = true
		print("  (world data missing: run ./run.sh world; the streaming cases skip)")


func after_each() -> void:
	_tree().root.remove_child(host)
	host.free()
	items.clear()
	Social.quests.reset_for_new_game()


func _row(key: String) -> Dictionary:
	for row in QuestItems.placements():
		if str(row["key"]) == key:
			return row
	return {}


func _meta_of(interior_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(ContentDB.get_or_empty(interior_id).get("meta", ""))))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


# --- what the pack asks for -----------------------------------------------------------------------

func test_the_quests_things_lie_where_their_quests_say() -> void:
	for key in EXPECTED:
		var row := _row(str(key))
		assert_false(row.is_empty(), "nothing puts down %s" % key)
		if not row.is_empty():
			assert_eq(str(row["where"]), str(EXPECTED[key]), "%s lies at %s" % [key, row["where"]])
	assert_eq(str(_row("item:core:item/quills_daybook").get("owner", "")), "core:npc/orrin_quill", "the day-book is Quill's to lose")
	assert_eq(str(_row("item:core:item/press_screw").get("owner", "")), "core:npc/bessa_tamwick", "and the press screw Bessa's")


func test_nothing_a_quest_asks_for_is_left_with_nowhere_to_lie() -> void:
	assert_empty(QuestItems.unplaced(), "things a quest asks for with no source and no place")


func test_what_the_story_hands_over_is_not_also_left_lying_about() -> void:
	for item in NOT_LYING_ABOUT:
		assert_true(_row("item:" + str(item)).is_empty(), "%s is handed over, sold or dropped, and also lies about" % item)


func test_every_placement_names_a_real_place_and_spot() -> void:
	for row in QuestItems.placements():
		var where := str(row["where"])
		assert_true(ContentDB.has(where), "%s lies at %s, which is nowhere" % [row["key"], where])
		if str(row["kind"]) == "item":
			assert_true(ContentDB.has(str(row["item"])), "%s is no item" % row["item"])
		var spot := str(row.get("spot", ""))
		if spot == "" or Ids.type_of(where) != "interior":
			continue
		var meta := _meta_of(where)
		var found: bool = (meta.get("chambers", {}) as Dictionary).has(spot)
		for r in meta.get("rooms", []):
			found = found or str((r as Dictionary).get("id", "")) == spot
		assert_true(found, "%s names %s in %s, which has no such chamber or room" % [row["key"], spot, where])


# --- the open country --------------------------------------------------------------------------------

func _raise_cell_of(poi_id: String) -> Node3D:
	var wp := WorldPois.new()
	host.add_child(wp)
	wp.index(pois, provider, WorldPois.roads_from_disk())
	var entry: Dictionary = {}
	for e in pois:
		if str((e as Dictionary).get("place_id", "")) == poi_id:
			entry = e
	var at := Vector3(float(entry["pos"][0]), float(entry["pos"][1]), float(entry["pos"][2]))
	var cell := wp.cell_of(at)
	var parent := Node3D.new()
	parent.name = "Cell_%d_%d" % [cell.x, cell.y]
	host.add_child(parent)
	wp.raise_in_cell(parent, cell, false)
	return parent


func _found(parent: Node, name_prefix: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in parent.find_children(name_prefix + "*", "", true, false):
		if not n.is_queued_for_deletion():
			out.append(n)
	return out


func test_the_hand_bell_lies_in_the_fallen_stair_until_somebody_takes_it() -> void:
	if provider == null:
		return
	var parent := _raise_cell_of("core:poi/tumbled_watchtower")
	var bells := _found(parent, "QuestItem_wardens_hand_bell")
	assert_eq(bells.size(), 1, "one hand-bell in the Tumbled Watch")
	if bells.is_empty():
		return
	var bell := bells[0] as WorldItem
	var stair := parent.find_child("fallen_stair", true, false) as Node3D
	assert_true(stair != null, "the watch's dressing marks its fallen stair")
	if stair != null:
		assert_true(bell.global_position.distance_to(stair.global_position) < 0.1, "and the bell lies on it")
	# somebody takes it
	var actor := Node3D.new()
	actor.add_to_group("player")
	var bag := Inventory.new()
	bag.is_player = true
	actor.add_child(bag)
	host.add_child(actor)
	assert_true(bell.interact(actor), "it can be picked up")
	assert_eq(bag.count("core:item/wardens_hand_bell"), 1)
	assert_true(items.is_taken("item:core:item/wardens_hand_bell"), "and the placer knows it has gone")
	# the cell comes round again, and a save is made and loaded in between
	var saved := JSON.stringify(items.to_save())
	items.taken.clear()
	items.from_save(JSON.parse_string(saved))
	var again := _raise_cell_of("core:poi/tumbled_watchtower")
	assert_empty(_found(again, "QuestItem_wardens_hand_bell"), "a thing taken stays taken")


func test_a_thing_lies_in_the_same_place_every_time() -> void:
	if provider == null:
		return
	var a := _raise_cell_of("core:place/cracked_toll")
	var tines_a := _found(a, "QuestItem_tuning_tine")
	var at_a := (tines_a[0] as Node3D).global_position if not tines_a.is_empty() else Vector3.INF
	a.get_parent().remove_child(a)
	a.free()
	var b := _raise_cell_of("core:place/cracked_toll")
	var tines_b := _found(b, "QuestItem_tuning_tine")
	assert_eq(tines_a.size(), 1, "the tine lies at the Toll")
	assert_eq(tines_b.size(), 1)
	if not tines_b.is_empty():
		assert_true((tines_b[0] as Node3D).global_position.distance_to(at_a) < 0.01, "in the same place both times")


func test_every_spot_a_quest_names_in_the_open_is_put_down_by_its_dressing() -> void:
	if provider == null:
		return
	for row in QuestItems.placements():
		var spot := str(row.get("spot", ""))
		if spot == "" or Ids.type_of(str(row["where"])) != "poi":
			continue
		var parent := _raise_cell_of(str(row["where"]))
		assert_true(parent.find_child(spot, true, false) != null, "%s's dressing puts down no '%s'" % [row["where"], spot])
		var named := ("Book_" + Ids.name_of(str(row["book"]))) if str(row["kind"]) == "book" \
				else ("QuestItem_" + Ids.name_of(str(row["item"])))
		var placed := _found(parent, named)
		assert_eq(placed.size(), 1, "%s lies at %s" % [named, row["where"]])


## A place's own sentence can say something lies there too: the chart in the Reed Wreck to take,
## the hermit's exercise book on Willow Isle to read where it is.
func test_what_a_places_sentence_says_lies_there_lies_there() -> void:
	var chart := _row("lies:core:poi/reed_wreck|core:item/salt_isles_guide")
	assert_false(chart.is_empty(), "the Salt Isles chart lies in the Reed Wreck")
	assert_eq(str(chart.get("kind", "")), "item")
	var book := _row("lies:core:poi/willow_isle|core:book/saying_ward")
	assert_false(book.is_empty(), "the hermit's book lies on Willow Isle")
	assert_eq(str(book.get("kind", "")), "book")
	if provider == null:
		return
	var isle := _raise_cell_of("core:poi/willow_isle")
	var readables := _found(isle, "Book_saying_ward")
	assert_eq(readables.size(), 1, "on his crate")
	if not readables.is_empty():
		var r := readables[0] as Readable
		assert_true(r.fixed, "read where it lies, not carried off")
		assert_eq(r.collision_layer, Readable.INTERACT_LAYER, "and something the interaction ray can find")
		assert_eq(r.book_id, "core:book/saying_ward", "and what it opens is his book")


# --- inside -------------------------------------------------------------------------------------------

func test_the_stewards_key_lies_in_his_study_and_is_his() -> void:
	var root := Node3D.new()
	host.add_child(root)
	var meta := _meta_of("core:interior/ellard_steward")
	var placed := items.raise_in_interior(root, "core:interior/ellard_steward", meta)
	var key: WorldItem = null
	for n in placed:
		if n is WorldItem and (n as WorldItem).item_id == "core:item/stewards_brass_key":
			key = n
	assert_true(key != null, "the brass key is in Ellard's house")
	if key == null:
		return
	assert_eq(key.owner_npc, "core:npc/ellard_wynstead", "and taking it is taking it from him")
	var study: Dictionary = {}
	for r in meta.get("rooms", []):
		if str((r as Dictionary).get("id", "")) == "study":
			study = r
	var c: Array = study.get("centre", [0, 0, 0])
	assert_true(key.position.distance_to(Vector3(float(c[0]), float(c[1]), float(c[2]))) < 1.5, "in the study, upstairs")


func test_the_ledger_lies_in_the_room_behind_the_bell() -> void:
	var root := Node3D.new()
	host.add_child(root)
	var meta := _meta_of("core:interior/undercroft")
	var placed := items.raise_in_interior(root, "core:interior/undercroft", meta)
	var ledger: WorldItem = null
	for n in placed:
		if n is WorldItem and (n as WorldItem).item_id == "core:item/ledger_of_prices":
			ledger = n
	assert_true(ledger != null, "the Ledger of Prices is in the Undercroft")
	if ledger != null:
		var points: Array = (meta["chambers"]["ledger_fall"] as Dictionary).get("floor_points", [])
		var on_the_floor := false
		for p in points:
			on_the_floor = on_the_floor or ledger.position.distance_to(Vector3(float(p[0]), float(p[1]), float(p[2]))) < 0.01
		assert_true(on_the_floor, "on the floor of the ledger fall")


func test_what_the_forge_put_in_a_cave_can_be_picked_up_but_a_boss_keeps_his_own() -> void:
	var at_the_feature := func(_f: Dictionary) -> Vector3: return Vector3(1.0, 2.0, 3.0)
	var mill := Node3D.new()
	host.add_child(mill)
	var got := items.raise_in_interior(mill, "core:interior/pennywort_mill", _meta_of("core:interior/pennywort_mill"), at_the_feature)
	var flour: WorldItem = null
	for n in got:
		if n is WorldItem and (n as WorldItem).item_id == "core:item/cold_flour":
			flour = n
	assert_true(flour != null, "the cold flour in the mill cellar is something you can take")
	if flour != null:
		assert_eq(flour.position, Vector3(1.0, 2.0, 3.0), "where the cave builder says the feature is")
		assert_false(flour.bob, "a sack on a cellar floor does not spin like a pickup")
		assert_true(flour.visual_path.ends_with(".glb"), "and wears the prop the forge set down")
	var nave := Node3D.new()
	host.add_child(nave)
	got = items.raise_in_interior(nave, "core:interior/drowned_nave", _meta_of("core:interior/drowned_nave"), at_the_feature)
	for n in got:
		assert_false(n is WorldItem and (n as WorldItem).item_id == "core:item/nave_bell", "She Who Waits drops her bell; it is not also on the floor")


# --- the note at the Seat -------------------------------------------------------------------------------

func test_the_note_is_taken_up_at_the_seat_and_nowhere_else() -> void:
	var seat := Node3D.new()
	host.add_child(seat)
	var got := items.raise_in_interior(seat, "core:interior/cantors_seat", _meta_of("core:interior/cantors_seat"))
	var point: ChoicePoint = null
	for n in got:
		if n is ChoicePoint:
			point = n
	assert_true(point != null, "the Seat keeps a place to decide the note")
	if point == null:
		return
	assert_false(point.is_open(), "before the Cantor has fallen there is nothing to decide")
	assert_eq(point.collision_layer, 0, "and nothing to walk up to")
	assert_true(Social.quests.start("core:quest/the_held_note"))
	Social.quests.set_stage("core:quest/the_held_note", "the_held_note")
	assert_true(point.is_open())
	assert_ne(point.collision_layer, 0, "now it can be walked up to")
	point.interact(null)
	var runner: Node = Social.dialogue
	assert_true(runner.is_running(), "walking up to it puts the choice")
	var picked := false
	for i in (runner.current_choices as Array).size():
		if str((runner.current_choices[i] as Dictionary).get("text", "")) == "Let the note end.":
			runner.choose(i)
			picked = true
			break
	assert_true(picked, "letting the note end is one of the choices")
	assert_true(Social.quests.is_completed("core:quest/the_held_note"), "and deciding it ends the main thread")
	assert_eq(Social.quests.outcome_of("core:quest/the_held_note"), "let_end")
	assert_false(point.is_open())
	assert_eq(point.collision_layer, 0, "and there is nothing left to walk up to")
	if runner.is_running():
		runner.stop()
