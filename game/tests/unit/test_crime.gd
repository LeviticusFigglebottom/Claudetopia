extends TestCase

const MERROWBY := "core:place/merrowby"
const WARDENS := "core:faction/wardens"
const HEARTHVALE := "core:region/hearthvale"
const BRIARWOLD := "core:region/briarwold"
const MERROWBY_POS := Vector3(900.0, 40.0, 2350.0)
const HOLLOW_POS := Vector3(3000.0, 60.0, 250.0)

var _nodes: Array[Node] = []
var _events: Array = []


func before_each() -> void:
	Peers.overrides.clear()
	_events.clear()
	GameState.reset_for_new_game(1)
	WorldClock.set_time(10.0, 5)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	Peers.overrides.clear()


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _bounty() -> Bounty:
	var b := Bounty.new()
	_root().add_child(b)
	_nodes.append(b)
	return b


func _ownership() -> Ownership:
	var o := Ownership.new()
	_root().add_child(o)
	_nodes.append(o)
	return o


func _witness(npc_id: String, detection: float, los := true, reaction := "report", is_guard := false, place := MERROWBY) -> Dictionary:
	return {"npc_id": npc_id, "detection": detection, "line_of_sight": los, "reaction": reaction, "is_guard": is_guard, "place_id": place}


# --- pure rules ---------------------------------------------------------------------------

func test_severity_table() -> void:
	assert_eq(Crimes.severity("trespass"), 5)
	assert_eq(Crimes.severity("pickpocket"), 25)
	assert_eq(Crimes.severity("assault"), 40)
	assert_eq(Crimes.severity("murder"), 100)
	assert_eq(Crimes.severity("lockpicking"), 15)
	assert_eq(Crimes.severity("theft", 100), 50, "theft is value based")
	assert_eq(Crimes.severity("theft", 3), 10, "theft has a floor")
	assert_eq(Crimes.severity("theft", 0), 10)
	assert_eq(Crimes.severity("juggling"), 0)
	assert_eq(Crimes.morality_delta("murder"), -20)
	assert_true(Crimes.is_hollow_deed("murder"))
	assert_false(Crimes.is_hollow_deed("theft"))
	assert_eq(Crimes.morality_delta("trespass"), 0)


func test_witness_rule_and_delays() -> void:
	assert_true(Crimes.is_witness(0.6, true))
	assert_false(Crimes.is_witness(0.59, true), "below the 0.6 threshold")
	assert_false(Crimes.is_witness(1.0, false), "no line of sight")
	assert_near(Crimes.report_delay_hours("report"), 0.5)
	assert_near(Crimes.report_delay_hours("flee"), 1.0)
	assert_near(Crimes.report_delay_hours("confront"), 0.25)
	assert_near(Crimes.report_delay_hours("anything", true), 0.0, 0.0001, "guards report at once")
	assert_true(Crimes.report_delay_hours("ignore") < 0.0)


func test_fines_and_jail() -> void:
	assert_eq(Crimes.fine(40, 1.5), 60)
	assert_eq(Crimes.fine(0, 2.0), 0)
	assert_eq(Crimes.jail_days(100, 2), 2)
	assert_eq(Crimes.jail_days(50, 2), 1)
	assert_eq(Crimes.jail_days(10, 1), 1, "at least a day when jail applies")
	assert_eq(Crimes.jail_days(100, 0), 0, "no jail in blood-price lands")


func test_law_styles_options() -> void:
	var wardens: Dictionary = ContentDB.get_def(WARDENS)["law"]
	var opts := Crimes.confront_options("fine_or_jail", 50, wardens)
	assert_eq(opts.size(), 3)
	assert_eq(opts[0]["id"], "pay")
	assert_eq(int(opts[0]["cost"]), 50)
	assert_eq(opts[1]["id"], "jail")
	assert_eq(int(opts[1]["days"]), 1)
	assert_eq(opts[2]["id"], "resist")
	var tally: Dictionary = ContentDB.get_def("core:faction/tallymen")["law"]
	var t := Crimes.confront_options("fine_or_jail", 50, tally)
	assert_eq(int(t[0]["cost"]), 75, "Tollmere law is paid law: 1.5x")
	var clans: Dictionary = ContentDB.get_def("core:faction/clan_moot")["law"]
	var blood := Crimes.confront_options("blood_price", 30, clans)
	assert_eq(blood.size(), 2)
	assert_eq(blood[0]["id"], "pay")
	assert_eq(int(blood[0]["cost"]), 60, "blood-price doubles")
	assert_eq(blood[1]["id"], "resist")
	var reeds: Dictionary = ContentDB.get_def("core:faction/reed_council")["law"]
	var exile := Crimes.confront_options("exile", 40, reeds)
	assert_eq(exile.size(), 2)
	assert_eq(exile[0]["id"], "exile")
	assert_empty(Crimes.confront_options("none", 100, {}))
	assert_eq(WorldProbe.law_of_region(HEARTHVALE)["law"]["style"], "fine_or_jail")
	assert_eq(WorldProbe.law_of_region("core:region/skerrow")["law"]["style"], "blood_price")
	assert_eq(WorldProbe.law_of_region("core:region/sedgemire")["law"]["style"], "exile")
	assert_eq(WorldProbe.law_of_region(BRIARWOLD)["law"]["style"], "none")
	assert_eq(WorldProbe.law_of_region(BRIARWOLD)["faction_id"], "")


func test_gossip_targets_same_region_settlements() -> void:
	var targets := Crimes.gossip_targets(MERROWBY, ContentDB.all("place"), {})
	assert_true("core:place/tamwick" in targets)
	assert_true("core:place/wardens_rest" in targets)
	assert_false("core:place/tollmere" in targets, "other region")
	assert_false("core:place/hollin_barrow" in targets, "not a settlement")
	assert_false(MERROWBY in targets)
	var none := Crimes.gossip_targets(MERROWBY, ContentDB.all("place"), {"core:place/tamwick": true, "core:place/wardens_rest": true})
	assert_empty(none)


# --- bounty service -------------------------------------------------------------------------

func test_keys_per_region() -> void:
	assert_eq(Bounty.key_for_region(HEARTHVALE), WARDENS)
	assert_eq(Bounty.key_for_region("core:region/skerrow"), "core:faction/clan_moot")
	assert_eq(Bounty.key_for_region(BRIARWOLD), BRIARWOLD, "lawless regions key by region")
	assert_true(Bounty.is_lawless_key(BRIARWOLD))
	assert_false(Bounty.is_lawless_key(WARDENS))
	assert_eq(Bounty.law_for_key("core:faction/clan_moot")["law"]["style"], "blood_price")
	assert_eq(Bounty.law_for_key(BRIARWOLD)["law"]["style"], "none")


func test_witnessed_theft_reports_after_delay() -> void:
	var b := _bounty()
	assert_true(b.is_in_group("crime"))
	assert_eq(Bounty.instance, b)
	var seen: Array = []
	var cb := func(k: String, t: int) -> void: seen.append([k, t])
	EventBus.bounty_changed.connect(cb)
	var crime := b.commit("theft", MERROWBY_POS, {"value": 40, "witnesses": [_witness("core:npc/a", 0.7)]})
	assert_true(crime["witnessed"])
	assert_eq(crime["key"], WARDENS)
	assert_eq(crime["place"], MERROWBY)
	assert_eq(int(crime["severity"]), 20)
	assert_eq(crime["region"], HEARTHVALE)
	assert_eq(b.total(WARDENS), 0, "not reported yet")
	assert_eq(b.pending_count(WARDENS), 1)
	assert_eq(GameState.count("crimes_theft"), 1)
	assert_eq(b.process_pending(Bounty.now_hours() + 0.4), 0, "still on the way")
	assert_eq(b.process_pending(Bounty.now_hours() + 0.5), 1)
	assert_eq(b.total(WARDENS), 20)
	assert_eq(b.bounty(WARDENS), 20)
	assert_true(b.is_known_at(WARDENS, MERROWBY))
	assert_false(b.is_known_at(WARDENS, "core:place/tamwick"))
	assert_eq(seen.size(), 1)
	assert_eq(seen[0], [WARDENS, 20])
	EventBus.bounty_changed.disconnect(cb)


func test_unwitnessed_and_ignored_crimes_do_not_report() -> void:
	var b := _bounty()
	var c1 := b.commit("pickpocket", MERROWBY_POS, {"witnesses": [_witness("core:npc/a", 0.5), _witness("core:npc/b", 0.9, false)]})
	assert_false(c1["witnessed"])
	assert_eq(b.pending_count(), 0)
	var c2 := b.commit("pickpocket", MERROWBY_POS, {"witnesses": [_witness("core:npc/c", 0.9, true, "ignore")]})
	assert_true(c2["witnessed"], "the cynic saw it")
	assert_eq(b.pending_count(), 0, "but does not care")
	var c3 := b.commit("murder", MERROWBY_POS, {"victim": "core:npc/v", "witnesses": [_witness("core:npc/v", 1.0)]})
	assert_false(c3["witnessed"], "the dead do not report")
	assert_eq(GameState.count("hollow_deeds"), 1)


func test_guard_reports_instantly_and_witness_can_be_silenced() -> void:
	var b := _bounty()
	b.commit("assault", MERROWBY_POS, {"witnesses": [_witness("core:npc/guard", 0.8, true, "confront", true)]})
	assert_eq(b.total(WARDENS), 40, "guards do not need to walk to the watch-house")
	b.commit("trespass", MERROWBY_POS, {"witnesses": [_witness("core:npc/timid", 0.65, true, "flee")]})
	assert_eq(b.pending_count(), 1)
	assert_eq(b.silence_witness("core:npc/timid"), 1)
	assert_eq(b.pending_count(), 0)
	b.process_pending(Bounty.now_hours() + 5.0)
	assert_eq(b.total(WARDENS), 40)
	b.commit("trespass", MERROWBY_POS, {"witnesses": [_witness("core:npc/w", 0.65)]})
	var victim := Node.new()
	victim.set_script(_npc_stub_script())
	victim.set("npc_id", "core:npc/w")
	EventBus.entity_killed.emit(victim, null, "")
	assert_eq(b.pending_count(), 0, "a dead witness tells nothing")
	victim.free()


func _npc_stub_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar npc_id := \"\"\n"
	s.reload()
	return s


func test_node_witnesses_via_perception_interface() -> void:
	var b := _bounty()
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar npc_id := \"core:npc/seer\"\nvar detection := 0.9\nvar alive := true\nvar place_id := \"core:place/merrowby\"\nvar personality = null\nfunc can_see_point(p: Vector3) -> bool:\n\treturn global_position.distance_to(p) < 20.0\n"
	s.reload()
	var npc := Node3D.new()
	npc.set_script(s)
	npc.add_to_group("npc")
	_root().add_child(npc)
	_nodes.append(npc)
	npc.global_position = MERROWBY_POS + Vector3(5, 0, 0)
	var far := b.commit("theft", MERROWBY_POS + Vector3(100, 0, 0), {"value": 10})
	assert_false(far["witnessed"], "out of sight")
	var near := b.commit("theft", MERROWBY_POS, {"value": 10})
	assert_true(near["witnessed"])
	assert_eq(near["witnesses"], ["core:npc/seer"])
	assert_eq(b.pending_count(), 1)


func test_lawless_regions_decay_and_gossip_spreads() -> void:
	var b := _bounty()
	var c := b.commit("theft", HOLLOW_POS, {"value": 30, "witnesses": [_witness("core:npc/w", 0.9, true, "report", true, "core:place/grandfather_hollow")]})
	assert_eq(c["key"], BRIARWOLD)
	assert_eq(c["law_faction"], "")
	assert_eq(b.total(BRIARWOLD), 15)
	b.add(WARDENS, 10, MERROWBY)
	b.decay_lawless()
	assert_eq(b.total(BRIARWOLD), 14, "one point a day in lawless country")
	assert_eq(b.total(WARDENS), 10, "faction bounties never decay")
	b.decay_lawless(14)
	assert_eq(b.total(BRIARWOLD), 0)
	assert_false(b.totals.has(BRIARWOLD))
	var rumours: Array = []
	var cb := func(r: String, p: String) -> void: rumours.append([r, p])
	EventBus.rumour_spread.connect(cb)
	var learned := b.spread_gossip()
	assert_eq(learned, 2, "Tamwick and Wardens' Rest hear of it")
	assert_true(b.is_known_at(WARDENS, "core:place/tamwick"))
	assert_true(b.is_known_at(WARDENS, "core:place/wardens_rest"))
	assert_eq(rumours.size(), 2)
	assert_eq(rumours[0][0], "bounty:" + WARDENS)
	assert_eq(b.spread_gossip(), 0, "nowhere left to spread within range")
	EventBus.rumour_spread.disconnect(cb)


func test_wanted_threshold_and_pay_bounty() -> void:
	var b := _bounty()
	b.add(WARDENS, 39, MERROWBY)
	assert_false(b.is_wanted(WARDENS))
	b.add(WARDENS, 1)
	assert_true(b.is_wanted(WARDENS), "arrest threshold 40 for the Wardens")
	b.add(BRIARWOLD, 500)
	assert_false(b.is_wanted(BRIARWOLD), "nobody arrests you in the Briarwold")
	GameState.inc("marks", 30)
	assert_false(b.pay_bounty(WARDENS), "cannot afford 40 marks")
	assert_eq(b.total(WARDENS), 40)
	GameState.inc("marks", 20)
	assert_true(b.pay_bounty(WARDENS))
	assert_eq(b.total(WARDENS), 0)
	assert_eq(GameState.count("marks"), 10)
	assert_eq(GameState.count("fines_paid"), 40)
	assert_false(b.is_known_at(WARDENS, MERROWBY), "paid bounties are forgotten")


func test_report_crime_contract_and_save_round_trip() -> void:
	var b := _bounty()
	var c := b.report_crime({"kind": "theft", "position": [900.0, 40.0, 2350.0], "value": 60, "witnesses": [_witness("core:npc/a", 0.9)]})
	assert_eq(c["kind"], "theft")
	assert_eq(int(c["severity"]), 30)
	assert_eq(b.pending_count(), 1)
	assert_true(b.report_crime({"kind": "bad_hair"}).is_empty())
	b.add(WARDENS, 12, MERROWBY)
	var data := b.to_save()
	assert_eq(int(data["totals"][WARDENS]), 12)
	assert_eq(data["pending"].size(), 1)
	var text := JSON.stringify(data)
	var b2 := Bounty.new()
	_root().add_child(b2)
	_nodes.append(b2)
	b2.from_save(JSON.parse_string(text))
	assert_eq(b2.total(WARDENS), 12)
	assert_eq(b2.pending_count(WARDENS), 1)
	assert_true(b2.is_known_at(WARDENS, MERROWBY))
	assert_eq(b2.process_pending(Bounty.now_hours() + 1.0), 1)
	assert_eq(b2.total(WARDENS), 42)


func test_hour_change_processes_reports() -> void:
	var b := _bounty()
	b.commit("theft", MERROWBY_POS, {"value": 20, "witnesses": [_witness("core:npc/a", 0.9)]})
	WorldClock.set_time(11.0, 5)
	assert_eq(b.total(WARDENS), 10, "hour_changed drives pending reports")


# --- ownership --------------------------------------------------------------------------------

func test_ownership_metadata_and_registry() -> void:
	var o := _ownership()
	var chest := Node.new()
	var inner := Node.new()
	chest.add_child(inner)
	_root().add_child(chest)
	_nodes.append(chest)
	assert_false(Ownership.is_owned(chest))
	Ownership.tag(chest, "", "core:npc/wren")
	assert_eq(Ownership.owner_of(chest)["npc"], "core:npc/wren")
	assert_eq(Ownership.owner_of(inner)["npc"], "core:npc/wren", "children inherit the owner")
	assert_true(Ownership.is_owned_by_other(chest))
	assert_false(Ownership.is_owned_by_other(chest, "core:npc/wren"), "the owner may take their own")
	Ownership.tag(chest, WARDENS, "")
	assert_true(Ownership.is_owned_by_other(chest))
	assert_false(Ownership.is_owned_by_other(chest, "core:npc/x", [WARDENS]), "members share faction goods")
	var fake_factions := Node.new()
	var s := GDScript.new()
	s.source_code = "extends Node\nfunc is_member(id: String) -> bool:\n\treturn id == \"%s\"\n" % WARDENS
	s.reload()
	fake_factions.set_script(s)
	Peers.overrides["factions"] = fake_factions
	assert_false(Ownership.is_owned_by_other(chest), "the player is a Warden")
	Peers.overrides.erase("factions")
	fake_factions.free()
	Ownership.tag(chest, "", "player")
	assert_false(Ownership.is_owned_by_other(chest))
	Ownership.tag(chest)
	assert_false(Ownership.is_owned(chest))
	o.assign_owner("core:place/merrowby#bed_3", "", "core:npc/wren")
	assert_true(Ownership.is_owned_by_other("core:place/merrowby#bed_3"))
	o.claim_for_player("core:place/merrowby#bed_3")
	assert_true(o.is_player_owned("core:place/merrowby#bed_3"))
	assert_false(Ownership.is_owned_by_other("core:place/merrowby#bed_3"))
	o.assign_owner("x", "", "core:npc/a")
	o.assign_owner("y", "", "core:npc/a")
	assert_eq(o.owned_by("core:npc/a"), ["x", "y"])
	var d := o.to_dict()
	var o2 := Ownership.new()
	o2.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(o2.registry.size(), 3)
	o2.free()
	var props: Array = []
	for n in chest.get_meta_list():
		props.append(n)
	assert_empty(props, "tag() with no owner removes metadata")
