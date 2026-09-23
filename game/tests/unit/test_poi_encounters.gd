extends TestCase
## What the points of interest's own sentences say stands at them, standing there.
##
## Every POI carries an `encounter` sentence and nothing stood up what any of them described: the
## world builder keeps the country's encounters off every pad, so the places a player is drawn to
## were the one kind of ground sure to be empty, and the Hart of Thorns was stood up nowhere. An
## `encounter` def says each sentence in terms `PoiEncounters` can raise with the dressing.
##
## These read the built world (`./run.sh world`); when it is missing they say so once and skip.

const GENERATED := "res://world/generated"

## Every POI and what its sentence comes to: enemy groups (by def), people (npcs/poi_people.json and
## Ryn at Gosling Pit), or why nothing stands there. Pinned so a sentence cannot quietly lose what
## it describes, and so the report reads off one table.
const WHAT_STANDS := {
	"core:poi/larkbourne_ford": "two bandits after dark",
	"core:poi/hedge_shrine_of_ansel": "person: core:npc/marigold_orchard",
	"core:poi/tumbled_watchtower": "five bandits in the stair-hall, a smuggler-Sayer on the parapet",
	"core:poi/gosling_pit": "four bandits and the Larkbourne Bruiser at the fire, and person: core:npc/wardens_ryn",
	"core:poi/singing_yew": "nobody: safe ground, and the dead turn away at its ward (Wards)",
	"core:poi/whitecut_falls": "a down-wolf pack in the mouth behind the falls",
	"core:poi/bell_meadow_stones": "nobody: none",
	"core:poi/foxglove_dell": "two bristlebacks at dawn, and person: core:npc/tansy_cresswell",
	"core:poi/long_stride": "two cutpurses in the toll queue and a bravo keeping the toll, by day",
	"core:poi/shingle_shrine": "nobody: none",
	"core:poi/north_cliff_beacon": "a smuggler-Sayer and two cutpurses",
	"core:poi/gullhithe_wreck": "gutter drakes",
	"core:poi/eelweir": "leech-hounds at night",
	"core:poi/pilgrim_stair": "nobody: none above water",
	"core:poi/willow_isle": "person: core:npc/ivo_goslin",
	"core:poi/buoy_bell_field": "nobody: none",
	"core:poi/lantern_causeway": "bog-drowned at night unless the lamplighter is out, and person: core:npc/lissane_sa",
	"core:poi/drowned_bell_shrine": "wisps at midnight",
	"core:poi/sallow_king": "two sallowjaws in the pool, whose deaths cost the Reed Council's regard",
	"core:poi/reed_wreck": "leech-hounds",
	"core:poi/stair_of_isse": "bog-drowned",
	"core:poi/wisp_hollow": "wisps",
	"core:poi/tideflat_stones": "nobody: crabs on the old strand, which are not a fight",
	"core:poi/heron_watch": "nobody: none",
	"core:poi/mossbridge": "a Warden at each end, sitting unless you carry the forest's goods past it",
	"core:poi/oiled_stone_shrine": "nobody: none",
	"core:poi/hunters_stand": "three poachers on the platform",
	"core:poi/foxfire_falls": "weavers at night on the lip above the fall",
	"core:poi/hart_bones": "a Hart-Knight",
	"core:poi/briar_breach": "ash-wights",
	"core:poi/charcoal_camp": "person: core:npc/sorrel_rooke, person: core:npc/barnaby_rooke, and a job board",
	"core:poi/fern_gully": "weavers",
	"core:poi/chain_bridge": "crag-wolves at night on the far approach, and person: core:npc/khath_ko_rudd",
	"core:poi/rib_cathedral": "a crag-wolf pack",
	"core:poi/three_sisters_falls": "scree-hags on the top ledge",
	"core:poi/clanless_camp": "a clanless hewer and two outriders",
	"core:poi/sinkhole_shrine": "nobody: none",
	"core:poi/watch_of_the_gate": "person: core:npc/ruska_ko_dreugh (the gate-warden of the story; the sentence says none)",
	"core:poi/lichen_stones": "nobody: none",
	"core:poi/hidden_tarn": "scree-hags",
	"core:poi/glass_bridge": "ash-wights",
	"core:poi/bell_of_the_pilgrims": "nobody: none",
	"core:poi/headless_watch": "a fallen Tolling knight on the stair while the watch has turned, and person: core:npc/calen_ash",
	"core:poi/the_one_poppy": "nobody: the poppy itself, to pick or water",
	"core:poi/thirteenth_colossus": "choristers after dark, and by day the Sayers' dig, person: core:npc/gisel_morneth, person: core:npc/wennick_anthar",
	"core:poi/cold_fire_camp": "six ash-wights, seated until the cup is touched",
	"core:poi/glass_falls": "a bell-bearer on the lip at the top",
	"core:poi/hushline_stair": "ash-wights",
	"core:poi/stair_head": "nobody: the Wardens' camp where a new game starts; the Warden stands there by her npc def's holds, not by a schedule",
}

var host: Node3D
var provider: TerrainProvider = null
var pois: Array = []
static var _warned := false


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	host = Node3D.new()
	host.name = "PoiEncountersTestHost"
	_tree().root.add_child(host)
	if provider == null and FileAccess.file_exists("%s/pois.json" % GENERATED):
		provider = TerrainProvider.new()
		provider.load_data()
		pois = JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED))
	elif provider == null and not _warned:
		_warned = true
		print("  (world data missing: run ./run.sh world; the raising cases skip)")
	Social.quests.reset_for_new_game()
	WorldClock.set_time(12.0, 2)


func after_each() -> void:
	_tree().root.remove_child(host)
	host.free()
	GameState.clear_flag("boss_deed/core:boss/hart_of_thorns")
	Social.quests.reset_for_new_game()
	WorldClock.set_time(9.0, 2)


## Raises the cell a place stands in, as the streamer would, and returns the place's dressing.
func _dress(place_id: String) -> PoiDressing:
	var wp := WorldPois.new()
	host.add_child(wp)
	wp.index(pois, provider, WorldPois.roads_from_disk())
	var entry: Dictionary = {}
	for e in pois:
		if str((e as Dictionary).get("place_id", "")) == place_id:
			entry = e
	if entry.is_empty():
		return null
	var at := Vector3(float(entry["pos"][0]), float(entry["pos"][1]), float(entry["pos"][2]))
	var cell := wp.cell_of(at)
	var parent := Node3D.new()
	parent.name = "Cell_%d_%d" % [cell.x, cell.y]
	host.add_child(parent)
	var mine: PoiDressing = null
	for d in wp.raise_in_cell(parent, cell, false):
		if d.poi_id == place_id:
			mine = d
	return mine


func _encounters_of(d: PoiDressing) -> PoiEncounters:
	if d == null:
		return null
	for c in d.get_children():
		if c is PoiEncounters:
			return c as PoiEncounters
	return null


func _living(enc: PoiEncounters, enemy_id: String) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if enc == null:
		return out
	for e in enc.everyone():
		if e.enemy_id == enemy_id:
			out.append(e)
	return out


# --- the data ------------------------------------------------------------------------------------------

func test_every_point_of_interest_is_accounted_for() -> void:
	for def in ContentDB.all("poi"):
		assert_true(WHAT_STANDS.has(str(def["id"])), "%s's sentence ('%s') is in no row of this table"
				% [def["id"], def.get("encounter", "")])
	var peopled: Dictionary = {}
	for def in ContentDB.all("npc"):
		for e in def.get("schedule", []):
			var place := str((e as Dictionary).get("place", ""))
			if Ids.type_of(place) == "poi":
				peopled[place] = true
				# and the other way: whoever a schedule puts at a point of interest is in its row
				assert_true(str(WHAT_STANDS.get(place, "")).contains("person: %s" % def["id"]),
						"%s's schedule puts them at %s and its row does not name them" % [def["id"], place])
	for poi_id in WHAT_STANDS:
		var said := str(WHAT_STANDS[poi_id])
		var has_def := not PoiEncounters.of(str(poi_id)).is_empty()
		var nobody := said.begins_with("nobody")
		var only_people := said.begins_with("person")
		if nobody or only_people:
			assert_false(has_def, "%s stands enemies up and the table says %s" % [poi_id, said])
		else:
			assert_true(has_def, "%s: '%s' and no encounter def stands it up" % [poi_id, said])
		if said.contains("person: "):
			assert_true(peopled.has(poi_id), "%s: '%s' and nobody's schedule puts them there" % [poi_id, said])


func test_every_encounter_names_a_real_place_real_foes_and_a_real_hour() -> void:
	var defs := ContentDB.all("encounter")
	assert_gt(defs.size(), 30, "the sentences want saying")
	for def in defs:
		var place := str(def.get("place", ""))
		assert_true(ContentDB.has(place), "%s stands at %s, which is nowhere" % [def["id"], place])
		assert_true(PoiDressing.dressable(place, ContentDB.get_or_empty(place)), "%s: nothing dresses %s, so nothing stands anyone up there" % [def["id"], place])
		for s in def.get("spawns", []):
			var e: Dictionary = s
			assert_true(ContentDB.has(str(e.get("enemy", ""))), "%s: no such foe %s" % [def["id"], e.get("enemy", "")])
			assert_true(PoiEncounters.WHEN.has(str(e.get("when", "always"))), "%s: '%s' is no hour" % [def["id"], e.get("when", "")])
			var keeper := str(e.get("unless_present", ""))
			if keeper != "":
				var lives := false
				for sch in ContentDB.get_or_empty(keeper).get("schedule", []):
					lives = lives or str((sch as Dictionary).get("place", "")) == place
				assert_true(lives, "%s waits on %s, who is never at %s" % [def["id"], keeper, place])


func test_every_marker_an_encounter_names_is_put_down_by_its_dressing() -> void:
	if provider == null:
		return
	for def in ContentDB.all("encounter"):
		var place := str(def.get("place", ""))
		var names: Array[String] = []
		for s in def.get("spawns", []):
			for key in ["at", "rises_when"]:
				if str((s as Dictionary).get(key, "")) != "":
					names.append(str(s[key]))
		for l in def.get("lies", []):
			if str((l as Dictionary).get("at", "")) != "":
				names.append(str(l["at"]))
		if names.is_empty():
			continue
		var d := _dress(place)
		assert_true(d != null, "%s has no pad in the built world" % place)
		if d == null:
			continue
		for n in names:
			assert_true(d.find_child(n, true, false) != null, "%s's dressing puts down no '%s'" % [place, n])


# --- standing there ----------------------------------------------------------------------------------------

func test_the_hart_keeps_the_moot_until_it_is_put_down() -> void:
	if provider == null:
		return
	var d := _dress("core:place/standing_moot")
	assert_true(d != null, "the Standing Moot is dressed")
	var enc := _encounters_of(d)
	assert_true(enc != null, "and something stands in it")
	if enc == null:
		return
	enc.refresh()
	var harts := _living(enc, "core:boss/hart_of_thorns")
	assert_eq(harts.size(), 1, "the Hart of Thorns keeps the circle")
	if not harts.is_empty():
		var circle := d.find_child("the_circle", true, false) as Node3D
		var off := Vector2(harts[0].global_position.x - circle.global_position.x, harts[0].global_position.z - circle.global_position.z)
		assert_true(off.length() < 0.5, "in the middle, where the question is asked")
		assert_true(harts[0].is_boss, "as a boss")
	# once he is down he stays down, however often the Moot is streamed in again
	GameState.set_flag("boss_deed/core:boss/hart_of_thorns")
	var again := _encounters_of(_dress("core:place/standing_moot"))
	again.refresh()
	assert_empty(_living(again, "core:boss/hart_of_thorns"), "a keeper put down is not stood up again")


func test_the_fords_bandits_come_out_after_dark_and_go_by_morning() -> void:
	if provider == null:
		return
	var enc := _encounters_of(_dress("core:poi/larkbourne_ford"))
	assert_true(enc != null)
	if enc == null:
		return
	WorldClock.set_time(12.0, 2)
	enc.refresh()
	assert_empty(_living(enc, "core:enemy/roadside_bandit"), "none by day")
	WorldClock.set_time(22.0, 2)
	enc.refresh()
	assert_eq(_living(enc, "core:enemy/roadside_bandit").size(), 2, "two bandits after dark")
	WorldClock.set_time(9.0, 3)
	enc.refresh()
	await _tree().process_frame
	assert_empty(_living(enc, "core:enemy/roadside_bandit"), "and gone by morning")


func test_a_group_put_down_is_not_raised_again_on_the_hour() -> void:
	if provider == null:
		return
	var enc := _encounters_of(_dress("core:poi/hart_bones"))
	enc.refresh()
	var knights := _living(enc, "core:enemy/hart_knight")
	assert_eq(knights.size(), 1, "a Hart-Knight keeps vigil at the skull")
	if knights.is_empty():
		return
	knights[0].die(null)
	enc.refresh()
	WorldClock.set_time(13.0, 2)
	enc.refresh()
	assert_empty(_living(enc, "core:enemy/hart_knight"), "the knight stays dead until a rest brings him back")


func test_the_drowned_climb_the_poles_only_when_the_lamplighter_is_not_on_them() -> void:
	if provider == null:
		return
	var registry := NpcRegistry.ensure()
	registry.despawn_all()
	registry.states.clear()
	registry.rebuild()
	var enc := _encounters_of(_dress("core:poi/lantern_causeway"))
	assert_true(enc != null)
	if enc == null:
		return
	# a workday at ten at night: Lissane is on her round, and every pole is lit
	WorldClock.set_time(22.0, 2)
	registry.simulate_all("clear")
	assert_true(PoiEncounters.is_present("core:npc/lissane_sa", "core:poi/lantern_causeway"), "she walks the boardwalk at ten")
	enc.refresh()
	assert_empty(_living(enc, "core:enemy/bog_drowned"), "the drowned stay under the boards while she is on them")
	# gone home at eleven, and the lanterns burn down
	WorldClock.set_time(23.5, 2)
	registry.simulate_all("clear")
	enc.refresh()
	assert_eq(_living(enc, "core:enemy/bog_drowned").size(), 2, "and after she has gone home they climb")
	registry.states.clear()
	registry.rebuild()


func test_the_larkbourne_boys_keep_their_knives_away_while_ryn_is_waiting_to_be_heard() -> void:
	if provider == null:
		return
	var enc := _encounters_of(_dress("core:poi/gosling_pit"))
	assert_true(enc != null)
	if enc == null:
		return
	enc.refresh()
	assert_eq(_living(enc, "core:enemy/roadside_bandit").size(), 4, "a pack of bandits at the fire")
	assert_true(Social.quests.start("core:quest/wardens_roll_of_names"))
	Social.quests.set_stage("core:quest/wardens_roll_of_names", "find_the_name")
	enc.refresh()
	await _tree().process_frame
	assert_empty(_living(enc, "core:enemy/roadside_bandit"), "they stand aside while the Roll sends you to hear Ryn out")
	Social.quests.set_stage("core:quest/wardens_roll_of_names", "the_pen")
	enc.refresh()
	assert_eq(_living(enc, "core:enemy/roadside_bandit").size(), 4, "and they are back when that is done")


## The One Poppy's sentence is a deed: a Hollow one if picked, a Hearth one if watered. Kneeling by
## it puts the choice, and a poppy picked is not there when the heath is next built.
func test_the_one_poppy_is_watered_or_picked_and_once_picked_is_gone() -> void:
	if provider == null:
		return
	GameState.clear_flag("poppy_picked")
	GameState.clear_flag("poppy_watered")
	var d := _dress("core:poi/the_one_poppy")
	var touch := d.find_child("the_poppy", true, false) as PoiTouch
	assert_true(touch != null, "the poppy is something to kneel by")
	if touch == null:
		return
	assert_eq(touch.dialogue_id, "core:dialogue/the_one_poppy")
	assert_true(touch.find_child("Bloom", true, false) != null, "and it holds the flower")
	var bag := SocialFakes.FakeInventory.new()
	Social.bind("inventory", bag)
	var morality_before := int(Social.reaction_profile().get("morality", 0))
	touch.interact(null)
	var runner: Node = Social.dialogue
	assert_true(runner.is_running(), "kneeling puts the choice")
	var texts: Array = []
	for c in runner.current_choices:
		texts.append(str((c as Dictionary).get("text", "")))
	assert_eq(texts, ["Water it from the cup.", "Pick it.", "Leave it where it is."], "water, pick or leave: nobody here passes on the news")
	runner.choose(1)
	if runner.is_running():
		runner.stop()
	assert_true(GameState.has_flag("poppy_picked"), "picked")
	assert_eq(bag.count("core:item/ash_poppy_petal"), 4, "four petals in your hand")
	assert_true(int(Social.reaction_profile().get("morality", 0)) < morality_before, "and it was a Hollow deed")
	assert_false(touch.visible, "and it is gone from the heath at once")
	var again := _dress("core:poi/the_one_poppy")
	assert_true(again.find_child("the_poppy", true, false) == null, "and when the heath is next built, a ring round nothing")
	assert_true(again.find_child("Bloom", true, false) == null)
	GameState.clear_flag("poppy_picked")
	Social.bind("inventory", null)
	Social.refresh_providers()


func test_the_cold_fire_sits_until_somebody_takes_up_the_cup() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/cold_fire_camp")
	var enc := _encounters_of(d)
	assert_true(enc != null)
	if enc == null:
		return
	enc.refresh()
	var seated := _living(enc, "core:enemy/ash_wight")
	assert_eq(seated.size(), 6, "Greyfold's six, round the fire")
	for w in seated:
		assert_false(w.perception.enabled, "seated, and not seeing you")
	var cup := d.find_child("the_cup", true, false)
	assert_true(cup is PoiTouch, "and the cup going round is there to be taken up")
	if not (cup is PoiTouch):
		return
	var actor := Node3D.new()
	actor.add_to_group("player")
	host.add_child(actor)
	(cup as PoiTouch).interact(actor)
	for w in seated:
		assert_true(w.perception.enabled, "they rise")
		assert_eq(w.perception.target, actor, "and they rise for whoever took it")
	assert_eq((cup as PoiTouch).collision_layer, 0, "the cup is not taken up twice")


# --- the sentences honoured at last -------------------------------------------------------------------------

## A body walked past a group, carrying a bag of its own; `as_player` puts it in the player group,
## so that what it does costs what the player's deeds cost.
func _walker(at: Vector3, as_player := false) -> Node3D:
	var who := Node3D.new()
	who.name = "Walker"
	if as_player:
		who.add_to_group("player")
	var bag := Inventory.new()
	bag.name = "Bag"
	who.add_child(bag)
	host.add_child(who)
	who.global_position = at
	return who


func _marker(d: PoiDressing, marker_name: String) -> Node3D:
	return d.find_child(marker_name, true, false) as Node3D if d != null else null


func test_the_clanless_camp_is_a_brute_and_two_skirmishers() -> void:
	if provider == null:
		return
	var enc := _encounters_of(_dress("core:poi/clanless_camp"))
	assert_true(enc != null)
	if enc == null:
		return
	enc.refresh()
	var hewers := _living(enc, "core:enemy/clanless_hewer")
	var outriders := _living(enc, "core:enemy/clanless_outrider")
	assert_eq(hewers.size(), 1, "a brute")
	assert_eq(outriders.size(), 2, "and two skirmishers")
	if hewers.size() == 1 and outriders.size() == 2:
		assert_eq(hewers[0].archetype, "brute")
		assert_eq(outriders[0].archetype, "skirmisher")
		assert_true(hewers[0].max_health > outriders[0].max_health, "the hewer is the one who goes in first")


func test_the_larkbourne_band_has_its_brute() -> void:
	if provider == null:
		return
	var enc := _encounters_of(_dress("core:poi/gosling_pit"))
	enc.refresh()
	var brutes := _living(enc, "core:enemy/larkbourne_bruiser")
	assert_eq(brutes.size(), 1, "the pack's brute leader stands at the fire with it")
	if not brutes.is_empty():
		assert_eq(brutes[0].archetype, "brute")


func test_the_watch_turns_only_while_its_condition_holds() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/headless_watch")
	var enc := _encounters_of(d)
	assert_true(enc != null, "the Headless Watch has a group to raise")
	if enc == null:
		return
	enc.refresh()
	assert_empty(_living(enc, "core:enemy/tolling_knight"), "a friendly vigil while the watch has not turned")
	var entry: Dictionary = enc.entries[0]
	assert_eq(str(entry.get("at", "")), "the_stair")
	var said: Array = entry.get("if", [])
	assert_eq(said, [{"quest_at": ["core:quest/the_names_in_the_chapter_book", "the_walks"]}],
			"it turns while the Order's fallen stand the north walk")
	# the same group on a condition a test can hold: up while it holds, down when it does not
	var turned := entry.duplicate(true)
	turned["if"] = [{"flag": "test_the_watch_has_turned"}]
	enc.entries = [turned]
	GameState.set_flag("test_the_watch_has_turned")
	enc.refresh()
	var knights := _living(enc, "core:enemy/tolling_knight")
	assert_eq(knights.size(), 1, "a fallen knight once the watch has turned")
	var stair := _marker(d, "the_stair")
	if knights.size() == 1 and stair != null:
		assert_true(knights[0].global_position.distance_to(stair.global_position) < 0.6, "on the stair")
		assert_true(knights[0].global_position.y > d.world_position.y + 1.5, "up the stair, not at its foot")
	GameState.clear_flag("test_the_watch_has_turned")
	enc.refresh()
	await _tree().process_frame
	assert_empty(_living(enc, "core:enemy/tolling_knight"), "and gone when it has not")


func test_the_sallow_kings_sallowjaws_rise_from_the_pool_and_cost_the_reedfolk() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/sallow_king")
	var enc := _encounters_of(d)
	enc.refresh()
	var jaws := _living(enc, "core:enemy/sallowjaw")
	assert_eq(jaws.size(), 2)
	var pool := _marker(d, "the_pool")
	assert_true(pool != null, "the water inside the ring is where they lie")
	if jaws.size() != 2 or pool == null:
		return
	for j in jaws:
		assert_true(Vector2(j.global_position.x - pool.global_position.x, j.global_position.z - pool.global_position.z).length() < 2.5,
				"in the pool, not on the pad's rim")
	var council := "core:faction/reed_council"
	Social.factions.set_reputation(council, 20)
	# somebody else's kill costs the player nothing; the player's costs the council's regard
	jaws[0].die(null)
	assert_eq(Social.factions.reputation(council), 20, "a death that was not the player's is not held against them")
	var who := _walker(pool.global_position + Vector3(6.0, 0.0, 0.0), true)
	jaws[1].die(who)
	assert_eq(Social.factions.reputation(council), 12, "the Reed Council hears who killed one")
	Social.factions.set_reputation(council, 0)


func test_the_mossbridge_wardens_let_the_empty_handed_cross() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/mossbridge")
	var enc := _encounters_of(d)
	enc.refresh()
	var wardens := _living(enc, "core:enemy/warden")
	assert_eq(wardens.size(), 2)
	if wardens.is_empty():
		return
	for w in wardens:
		assert_true(w.inactive, "a Warden is a dead tree to whoever carries nothing")
	var who := _walker(wardens[0].global_position + Vector3(3.0, 0.0, 0.0))
	# it sees you cross, and seeing you is not a reason
	wardens[0].call("_on_detected", who)
	assert_true(wardens[0].inactive and wardens[0].minding, "a Warden that has seen you still lets you by")
	enc.mind(who)
	assert_true(wardens[0].inactive, "empty-handed, you cross")
	(who.get_node("Bag") as Inventory).add("core:item/wolf_pelt")
	enc.mind(who)
	assert_true(wardens[0].inactive, "a pelt Fernhold pays for is not the forest's to miss")
	(who.get_node("Bag") as Inventory).add("core:item/heartwood_knot")
	enc.mind(who)
	assert_false(wardens[0].inactive or wardens[0].minding, "a knot out of a Warden's own trunk wakes it")
	assert_eq(wardens[0].brain.state, Brain.COMBAT, "and it comes for you")
	wardens[0].reset_to_spawn()
	assert_true(wardens[0].inactive and wardens[0].minding, "and after a rest it is minding its end of the arch again")


func test_the_long_stride_bravo_keeps_the_toll_and_duels_who_walks_past_it() -> void:
	if provider == null:
		return
	WorldClock.set_time(12.0, 2)
	var d := _dress("core:poi/long_stride")
	var enc := _encounters_of(d)
	enc.refresh()
	var bravos := _living(enc, "core:enemy/bravo")
	assert_eq(bravos.size(), 1, "the toll is kept by day")
	var table := _marker(d, "the_toll_table")
	var line := _marker(d, "the_toll_line")
	assert_true(table != null and line != null and d.find_child("the_toll", true, false) is PoiTouch,
			"a table, a line past it and the toll to pay at it")
	if bravos.is_empty() or line == null:
		return
	assert_true(bravos[0].inactive, "he keeps his table and asks, he does not start it")
	bravos[0].call("_on_detected", null)
	assert_true(bravos[0].inactive, "and seeing you come is not starting it")
	GameState.clear_flag(enc.toll_flag())
	var who := _walker(line.global_position + Vector3(0.0, 0.0, 30.0))
	enc.mind(who)
	assert_true(bravos[0].inactive, "waiting in the queue is not refusing")
	# the toll is paid by touching the table, as a player does
	await _tree().process_frame
	var toll := d.find_child("the_toll", true, false) as PoiTouch
	assert_true(toll.prompt.contains("5 marks"), "the table says what the toll is: %s" % toll.prompt)
	Purse.give(who, 12)
	var before := Purse.balance(who)
	toll.interact(who)
	assert_eq(Purse.balance(who), before - 5, "five marks at the table")
	assert_true(enc.toll_paid())
	toll.interact(who)
	assert_eq(Purse.balance(who), before - 5, "and once a day")
	who.global_position = line.global_position
	enc.mind(who)
	assert_true(bravos[0].inactive, "paid, you walk on past him")
	GameState.clear_flag(enc.toll_flag())
	enc.mind(who)
	assert_false(bravos[0].inactive, "past the table without paying, and he has it out with you")
	GameState.clear_flag(enc.toll_flag())


func test_the_groups_the_sentences_put_up_high_stand_up_high() -> void:
	if provider == null:
		return
	WorldClock.set_time(23.0, 2)
	for row in [["core:poi/foxfire_falls", "core:enemy/weaver", "above_the_falls"],
			["core:poi/three_sisters_falls", "core:enemy/scree_hag", "the_cliffs"],
			["core:poi/glass_falls", "core:enemy/bell_bearer", "the_top"]]:
		var d := _dress(str(row[0]))
		var enc := _encounters_of(d)
		enc.refresh()
		var up := _marker(d, str(row[2]))
		var foes := _living(enc, str(row[1]))
		assert_false(foes.is_empty(), "%s stands %s up" % [row[0], row[1]])
		assert_true(up != null and bool(up.get_meta("raised", false)), "%s's %s is a place to stand, up off the ground" % [row[0], row[2]])
		if up == null or foes.is_empty():
			continue
		var ground := provider.get_height(up.global_position.x, up.global_position.z)
		assert_true(up.global_position.y > ground + 3.5, "%s: %s is up high (%.1f m over the ground)" % [row[0], row[2], up.global_position.y - ground])
		for f in foes:
			assert_true(absf(f.global_position.y - up.global_position.y) < 0.5, "%s: %s stands on it" % [row[0], row[1]])
	# and the down-wolves in the mouth behind the water, at the foot of the face
	var falls := _dress("core:poi/whitecut_falls")
	var mouth := _marker(falls, "behind_the_falls")
	var enc2 := _encounters_of(falls)
	enc2.refresh()
	var wolves := _living(enc2, "core:enemy/down_wolf")
	assert_eq(wolves.size(), 4)
	assert_true(mouth != null and falls.find_child("MouthDark", true, false) != null, "a dark mouth behind the fall")
	if mouth != null:
		for w in wolves:
			assert_true(Vector2(w.global_position.x - mouth.global_position.x, w.global_position.z - mouth.global_position.z).length() < 2.5,
					"the pack is in it")
	WorldClock.set_time(9.0, 2)


func test_the_tideflat_has_its_crabs_and_nothing_to_fight() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/tideflat_stones")
	assert_true(_encounters_of(d) == null, "none")
	var shore := d.find_child("Crabs", true, false) as Livestock
	assert_true(shore != null, "crabs")
	if shore == null:
		return
	assert_true(shore.beasts.size() >= 9, "a few on the strand at each stone (%d)" % shore.beasts.size())
	for b in shore.beasts:
		assert_eq(str((b as Dictionary)["kind"]), "crab")


func test_the_singing_yew_is_ground_the_dead_will_not_cross() -> void:
	if provider == null:
		return
	Wards.clear()
	var d := _dress("core:poi/singing_yew")
	assert_eq(Wards.count(), 1, "the yew puts its ward down with it")
	var yew := d.world_position
	assert_false(Wards.keeping(["humanoid", "revenant", "undead"], yew + Vector3(3.0, 0.0, 0.0)).is_empty(), "a hedge-wight will not pass it")
	assert_true(Wards.keeping(["bandit", "humanoid", "person"], yew + Vector3(3.0, 0.0, 0.0)).is_empty(), "a bandit does not care")
	assert_true(Wards.keeping(["undead"], yew + Vector3(20.0, 0.0, 0.0)).is_empty(), "and the ward ends where the yew's ground does")
	d.get_parent().free()
	assert_eq(Wards.count(), 0, "and it goes with the dressing")
