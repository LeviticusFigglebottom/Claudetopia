extends TestCase

const BRAM := "core:npc/example_thatcher_bram"
const NELL := "core:npc/example_grocer_nell"
const WARDEN := "core:npc/guard_wardens"
const MERROWBY := "core:place/merrowby"

var _nodes: Array[Node] = []


func before_each() -> void:
	Peers.overrides.clear()
	GameState.reset_for_new_game(1)
	WorldClock.set_time(10.0, 2)
	var reg := NpcRegistry.ensure()
	if reg != null:
		reg.despawn_all()
		reg.states.clear()
		reg.loaded_cells.clear()
		reg.abstract_only = true
		reg.rebuild()


func after_each() -> void:
	var reg := NpcRegistry.instance
	if reg != null:
		reg.despawn_all()
		reg.loaded_cells.clear()
		reg.abstract_only = false
	for n in _nodes:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


# --- content ---------------------------------------------------------------------------------

func test_every_npc_def_has_a_state() -> void:
	var reg := NpcRegistry.instance
	assert_gt(ContentDB.all("npc").size(), 8)
	for def in ContentDB.all("npc"):
		assert_has(reg.states, def["id"])
		assert_true(reg.is_alive(def["id"]))


func test_a_guard_def_exists_for_every_law_faction() -> void:
	var law_factions := {}
	for r in ContentDB.all("region"):
		var f := str(r.get("law_faction", ""))
		if not f.is_empty():
			law_factions[f] = true
	assert_eq(law_factions.size(), 4, "Wardens, Tallymen, Clan-Moot, Reed Council")
	for f: String in law_factions:
		var found := ""
		for npc in ContentDB.all("npc"):
			if str(npc.get("faction", "")) == f and npc.get("tags", []).has("guard"):
				found = npc["id"]
		assert_ne(found, "", "no guard def for %s" % f)
		var def := ContentDB.get_or_empty(found)
		assert_gt(def["schedule"].size(), 3, "%s needs a real timetable" % found)
		assert_gt(def["personality"]["traits"].size(), 1)


func test_example_npcs_are_marked_for_deletion() -> void:
	for npc in ContentDB.all("npc"):
		var id: String = npc["id"]
		if Ids.name_of(id).begins_with("example_"):
			assert_true(bool(npc.get("example", false)), "%s must carry \"example\": true" % id)
			assert_true(str(npc.get("description", "")).contains("PLACEHOLDER"), "%s should say so" % id)


# --- abstract simulation -------------------------------------------------------------------------

func test_schedule_moves_npcs_off_screen() -> void:
	var reg := NpcRegistry.instance
	WorldClock.set_time(3.0, 2)
	reg.simulate_all("clear")
	assert_eq(reg.activity_of(BRAM), "sleep")
	assert_eq(reg.place_of(BRAM), MERROWBY, "'home' resolves to his home place")
	WorldClock.set_time(10.0, 2)
	reg.simulate_all("clear")
	assert_eq(reg.activity_of(BRAM), "work")
	assert_eq(reg.place_of(BRAM), MERROWBY)
	WorldClock.set_time(10.0, 6)
	reg.simulate_all("clear")
	assert_eq(reg.place_of(NELL), "core:place/tamwick", "Nell goes to the cider press on Hushday")


func test_hour_change_drives_the_whole_village() -> void:
	var reg := NpcRegistry.instance
	WorldClock.set_time(3.0, 2)
	assert_eq(reg.activity_of(BRAM), "sleep")
	WorldClock.set_time(10.0, 2)
	assert_eq(reg.activity_of(BRAM), "work", "hour_changed simulates everyone")


func test_weather_sends_idlers_home() -> void:
	var reg := NpcRegistry.instance
	WorldClock.set_time(20.5, 2)
	reg.simulate_all("clear")
	assert_eq(reg.activity_of("core:npc/example_smith_osric"), "idle")
	EventBus.weather_changed.emit("core:region/hearthvale", "rain")
	assert_eq(reg.activity_of("core:npc/example_smith_osric"), "idle")
	assert_eq(reg.place_of("core:npc/example_smith_osric"), MERROWBY, "his home is in Merrowby either way")
	assert_eq(reg.weather_now(), "rain", "the registry remembers the weather")


func test_npcs_at_a_place() -> void:
	var reg := NpcRegistry.instance
	WorldClock.set_time(10.0, 2)
	reg.simulate_all("clear")
	var here := reg.npcs_at(MERROWBY)
	assert_true(BRAM in here)
	assert_gt(here.size(), 3)
	reg.kill(BRAM)
	assert_false(BRAM in reg.npcs_at(MERROWBY), "the dead are not counted")
	assert_true(BRAM in reg.npcs_at(MERROWBY, true))
	assert_false(reg.is_alive(BRAM))
	assert_eq(GameState.count("npcs_dead"), 1)


func test_disposition_deeds_and_hostility() -> void:
	var reg := NpcRegistry.instance
	assert_eq(reg.disposition_of(BRAM), 0)
	assert_eq(reg.adjust_disposition(BRAM, 15), 15)
	assert_eq(reg.adjust_disposition(BRAM, -40), -25)
	assert_eq(reg.adjust_disposition(BRAM, -1000), -100, "clamped")
	reg.note_player_deed(BRAM, "murder")
	assert_eq(reg.last_seen_player_deed(BRAM), "murder")
	assert_false(reg.is_hostile(BRAM))
	reg.set_hostile(BRAM, true)
	assert_true(reg.is_hostile(BRAM))
	assert_empty(reg.state("core:npc/nobody"), "unknown npcs have no state")


func test_jail_freezes_the_schedule() -> void:
	var reg := NpcRegistry.instance
	WorldClock.set_time(10.0, 2)
	reg.simulate_all("clear")
	reg.jail(BRAM, 2)
	var s := reg.state(BRAM)
	s["place"] = "core:place/wardens_rest"
	WorldClock.set_time(20.0, 2)
	reg.simulate_all("clear")
	assert_eq(reg.place_of(BRAM), "core:place/wardens_rest", "he is not at the inn, he is in a cell")
	WorldClock.set_time(10.0, 5)
	reg.simulate_all("clear")
	assert_eq(reg.place_of(BRAM), MERROWBY, "let out, and back on the roofs")


# --- spawning ------------------------------------------------------------------------------------

func test_cells_spawn_and_despawn_actors() -> void:
	var reg := NpcRegistry.instance
	reg.abstract_only = false
	WorldClock.set_time(10.0, 2)
	reg.simulate_all("clear")
	var cell := WorldProbe.cell_of_place(MERROWBY)
	assert_eq(reg.cell_of(BRAM), cell)
	assert_false(reg.is_spawned(BRAM))
	var spawned_ids: Array = []
	var cb := func(id: String, _n: Node) -> void: spawned_ids.append(id)
	reg.npc_spawned.connect(cb)
	EventBus.cell_loaded.emit(cell)
	assert_true(reg.is_spawned(BRAM), "his cell loaded, so he is there to be met")
	assert_gt(spawned_ids.size(), 3)
	var actor := reg.actor(BRAM)
	assert_true(actor != null)
	assert_eq(str(actor.get("npc_id")), BRAM)
	assert_eq(str(actor.get("activity")), "work", "the actor picks up the abstract state")
	assert_true(actor.is_in_group("npc"))
	assert_true(actor.is_in_group("interactable"))
	assert_true(reg.is_spawned(WARDEN), "the Warden patrols Merrowby on a workday, so he is here too")
	assert_true(reg.actor("core:npc/guard_tallymen") == null, "Tollmere's watch is a long way off")
	EventBus.cell_unloaded.emit(cell)
	assert_false(reg.is_spawned(BRAM))
	assert_true(reg.actor(BRAM) == null)
	reg.npc_spawned.disconnect(cb)
	reg.abstract_only = true


func test_the_dead_stay_dead_and_leave_a_body() -> void:
	var reg := NpcRegistry.instance
	reg.abstract_only = false
	WorldClock.set_time(10.0, 2)
	reg.simulate_all("clear")
	var cell := WorldProbe.cell_of_place(MERROWBY)
	EventBus.cell_loaded.emit(cell)
	assert_true(reg.is_spawned(BRAM))
	reg.kill(BRAM)
	assert_false(reg.is_alive(BRAM))
	var body := reg.actor(BRAM)
	assert_true(body != null, "the body is left where it fell, for looting and for the sight of it")
	assert_false(bool(body.get("alive")))
	assert_false(body.is_in_group("interactable"), "you cannot chat with a corpse")
	EventBus.cell_unloaded.emit(cell)
	assert_false(reg.is_alive(BRAM), "unloading the cell must not write the body's state back over death")
	EventBus.cell_loaded.emit(cell)
	assert_false(reg.is_spawned(BRAM), "and the dead do not come back with the cell")
	assert_false(reg.is_alive(BRAM))
	reg.despawn_all()
	reg.abstract_only = true


func test_guards_spawn_with_the_guard_script() -> void:
	var reg := NpcRegistry.instance
	reg.abstract_only = false
	WorldClock.set_time(10.0, 2)
	reg.simulate_all("clear")
	EventBus.cell_loaded.emit(WorldProbe.cell_of_place(MERROWBY))
	var warden := reg.actor(WARDEN)
	assert_true(warden is Guard, "an npc tagged guard gets guard.gd")
	assert_eq((warden as Guard).law_faction, "core:faction/wardens")
	assert_true(warden.is_in_group("guard"))
	reg.despawn_all()
	reg.abstract_only = true


func test_spawn_positions_are_spread_and_stable() -> void:
	var reg := NpcRegistry.instance
	var a := reg.spawn_position(BRAM)
	var b := reg.spawn_position(NELL)
	assert_gt(a.distance_to(b), 0.5, "a village does not stand in one spot")
	assert_eq(reg.spawn_position(BRAM), a, "and everyone keeps their place")
	# A settlement is sixty to a hundred metres across and its people stand across it, not in
	# a ten-metre scrum on the green — but they stay inside their own village.
	assert_true(a.distance_to(WorldProbe.place_position(MERROWBY)) <= 42.0,
			"%s stands %.1f m from the middle of their own village"
			% [BRAM, a.distance_to(WorldProbe.place_position(MERROWBY))])


# --- save ------------------------------------------------------------------------------------------

func test_save_round_trip() -> void:
	var reg := NpcRegistry.instance
	WorldClock.set_time(10.0, 2)
	reg.simulate_all("clear")
	reg.adjust_disposition(BRAM, 30)
	reg.note_player_deed(BRAM, "theft")
	reg.kill(NELL)
	reg.set_hostile(WARDEN, true)
	var data := reg.to_save()
	var text := JSON.stringify(data)
	reg.states.clear()
	reg.rebuild()
	assert_eq(reg.disposition_of(BRAM), 0)
	assert_true(reg.is_alive(NELL))
	reg.from_save(JSON.parse_string(text))
	assert_eq(reg.disposition_of(BRAM), 30)
	assert_eq(reg.last_seen_player_deed(BRAM), "theft")
	assert_false(reg.is_alive(NELL), "she stays dead")
	assert_true(reg.is_hostile(WARDEN))
	assert_eq(reg.activity_of(BRAM), "work", "and the living are put back on their schedule")
