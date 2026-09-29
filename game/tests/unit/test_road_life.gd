extends TestCase
## The road's life (systems/roads, docs/WORLD_LIFE_ROADS.md): the director's budget and cooldowns,
## the ground it keeps off, never standing anything where the camera looks, taking things down as
## the player leaves them and as cells go, caravans kept across a save without a second of any,
## a caravan walking its road, an ambush springing, a caravan's trade, and the road's armed people
## leaving the player be until struck.
##
## A road of its own (RoadNetwork.use) on flat ground at y 0 with a floor under it, in Hearthvale by
## the regions' centres, and tables of the test's own where a row must be certain.

const ROAD_PTS := [[900.0, 2400.0], [1000.0, 2400.0], [1100.0, 2400.0], [1200.0, 2400.0], [1300.0, 2400.0],
		[1380.0, 2460.0], [1420.0, 2560.0], [1420.0, 2800.0]]
const REGION := "core:region/hearthvale"

var host: Node3D
var life: RoadLife
var player: Node3D


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	var pts := PackedVector2Array()
	for p in ROAD_PTS:
		pts.append(Vector2(p[0], p[1]))
	RoadNetwork.use([{"id": "core:road/test_way", "points": pts, "width": 4.0}])
	RoadSites.reset()
	RoadSites.use_rivers([])
	RoadTables.reset()
	GameState.reset_for_new_game(1)
	WorldClock.set_time(12.0, 2)
	host = Node3D.new()
	host.name = "RoadLifeTestHost"
	_tree().root.add_child(host)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1 | (1 << 10)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6000.0, 1.0, 6000.0)
	shape.shape = box
	shape.position = Vector3(1000.0, -0.5, 2400.0)
	floor.add_child(shape)
	host.add_child(floor)
	player = (load("res://tests/fakes/fake_player.gd") as GDScript).new() as Node3D
	player.name = "RoadPlayer"
	host.add_child(player)
	player.global_position = Vector3(1000.0, 0.0, 2400.0)
	Peers.overrides["player"] = player
	RoadLife.forced = 1
	life = RoadLife.new()
	life.world_checks = false
	life.ground = func(_x: float, _z: float) -> float: return 0.0
	host.add_child(life)
	life.journeys.clear()
	life.use_pads([{"at": Vector2(INF, INF), "radius": 0.0, "town": false}])


func after_each() -> void:
	RoadLife.forced = -1
	Peers.overrides.clear()
	if is_instance_valid(host):
		host.get_parent().remove_child(host)
		host.queue_free()
	RoadNetwork.forget()
	RoadSites.reset()
	RoadTables.reset()


## A table of the test's own for Hearthvale.
func _table(rows: Array, budget: Dictionary = {}) -> void:
	RoadTables._by_region = {REGION: {"rows": rows, "caravans": [], "sites": [], "budget": budget}}
	RoadTables._built = true


func _camera_along_road() -> Camera3D:
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.global_position = player.global_position + Vector3(0.0, 1.7, 0.0)
	cam.look_at(Vector3(1200.0, 1.7, 2400.0))
	life.camera_override = cam
	return cam


func _physics(frames: int) -> void:
	for i in frames:
		await _tree().physics_frame


# --- content ------------------------------------------------------------------------------------

func test_the_tables_and_events_are_sound() -> void:
	var problems := RoadTables.problems()
	assert_true(problems.is_empty(), "road-life content problems: %s" % str(problems))
	for r in ContentDB.all("region"):
		assert_false((RoadTables.table(str(r["id"]))["rows"] as Array).is_empty(), "%s has no roadtable rows" % r["id"])
	assert_false(RoadTables.caravans().is_empty(), "no caravans anywhere")


# --- the budget, the gap, the cooldowns ------------------------------------------------------------

func test_the_director_keeps_to_its_budget_and_gap() -> void:
	_table([{"event": "core:roadevent/pilgrims", "weight": 1, "cooldown_h": 0}], {"max_active": 2, "gap_s": 0})
	for i in 6:
		life.travel_m = 1.0e6
		life.since_start_s = 999.0
		life.look()
	assert_eq(life._active(), 2, "as many as the budget allows, and no more")
	# the gap: a new stretch travelled, but too soon after the last
	_table([{"event": "core:roadevent/pilgrims", "weight": 1, "cooldown_h": 0}], {"max_active": 5, "gap_s": 60})
	life.travel_m = 1.0e6
	life.since_start_s = 10.0
	life.look()
	assert_eq(life._active(), 2, "nothing new within the gap")
	# and the stretch: time enough, road not
	life.since_start_s = 999.0
	life.travel_m = 0.0
	life.next_due_m = 300.0
	life.look()
	assert_eq(life._active(), 2, "nothing new before the next stretch of road is travelled")


func test_an_event_waits_out_its_cooldown() -> void:
	_table([{"event": "core:roadevent/pilgrims", "weight": 1, "cooldown_h": 5}], {"max_active": 5, "gap_s": 0})
	var first := life.roll(player.global_position, Vector2(1, 0))
	assert_true(first != null, "the pilgrims came")
	var again := life.roll(player.global_position, Vector2(1, 0))
	assert_true(again == null, "not again within five hours")
	WorldClock.set_time(18.0, 2)
	var later := life.roll(player.global_position, Vector2(1, 0))
	assert_true(later != null, "again after the cooldown")


# --- where nothing happens -------------------------------------------------------------------------

func test_nothing_happens_in_a_town_or_on_a_pad() -> void:
	_table([{"event": "core:roadevent/pilgrims", "weight": 1, "cooldown_h": 0}])
	life.use_pads([{"at": Vector2(1000.0, 2400.0), "radius": 60.0, "town": true}])
	assert_true(life.is_safe(player.global_position), "the player is in the town")
	assert_true(life.roll(player.global_position, Vector2(1, 0)) == null, "nothing rolled in a town")
	assert_eq(life.fit(Vector3(1120.0, 0.0, 2400.0), Vector3(900.0, 0.0, 2400.0)), "safe ground", "the town's margin is kept")
	life.use_pads([{"at": Vector2(1300.0, 2400.0), "radius": 20.0, "town": false}])
	assert_eq(life.fit(Vector3(1310.0, 0.0, 2400.0), player.global_position), "safe ground", "a place's pad is kept")
	life.hush("test")
	assert_eq(life.hushed(), "test")
	life.unhush("test")
	GameState.set_flag("road_life/hush", true)
	assert_eq(life.hushed(), "story", "a quest may hush the road")


func test_nothing_is_stood_up_where_the_camera_looks_or_on_top_of_the_player() -> void:
	_table([{"event": "core:roadevent/pilgrims", "weight": 1, "cooldown_h": 0}], {"max_active": 5, "gap_s": 0})
	var cam := _camera_along_road()
	assert_true(life.in_view(Vector3(1150.0, 1.0, 2400.0)), "the road ahead is in view")
	assert_false(life.in_view(Vector3(850.0, 1.0, 2400.0)), "the road behind is not")
	assert_eq(life.fit(Vector3(1150.0, 0.0, 2400.0), player.global_position), "in view")
	assert_eq(life.fit(Vector3(1030.0, 0.0, 2400.0), player.global_position), "too near")
	# a crest between hides what is past it
	life.ground = func(x: float, _z: float) -> float: return 6.0 if x > 1060.0 and x < 1080.0 else 0.0
	assert_false(life.in_view(Vector3(1150.0, 1.0, 2400.0)), "behind the crest")
	life.ground = func(_x: float, _z: float) -> float: return 0.0
	for i in 4:
		var ev := life.roll(player.global_position, Vector2(1, 0))
		if ev == null:
			continue
		await _physics(2)
		assert_false(life.any_in_view(ev.points()), "stood up in view: %s" % str(ev.points()))
		for p in ev.points():
			assert_gt(Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length(), RoadLife.MIN_SPAWN_M - 20.0, "on top of the player")
	assert_true(int((life.stats["skipped"] as Dictionary).get("in view", 0)) > 0, "the road ahead was refused for being seen")
	cam.queue_free()


# --- streaming -------------------------------------------------------------------------------------

func test_what_is_left_behind_is_taken_down() -> void:
	_table([{"event": "core:roadevent/pilgrims", "weight": 1, "cooldown_h": 0}], {"max_active": 5, "gap_s": 0})
	var a := life.roll(player.global_position, Vector2(1, 0))
	var b := life.roll(player.global_position, Vector2(1, 0))
	assert_true(a != null and b != null)
	# its cell goes
	EventBus.cell_unloaded.emit(WorldProbe.cell_of(a.focus()))
	assert_false(life.events.has(a), "gone with its cell")
	# the player rides on
	player.global_position = Vector3(1420.0, 0.0, 2900.0) + Vector3(0.0, 0.0, 400.0)
	life.look()
	assert_true(life.events.is_empty(), "left behind, and taken down")


# --- caravans: kept, saved, walked, traded with -------------------------------------------------------

func test_caravans_are_kept_across_a_save_without_a_second_of_any() -> void:
	RoadTables.reset()
	life.seed_journeys()
	assert_false(life.journeys.is_empty(), "the tables' caravans set out")
	var id := ""
	for k in life.journeys:
		if str(k).contains("merrowby") and str(life.journeys[k]["state"]) == "road":
			id = str(k)
	if id == "":
		skip("no Merrowby caravan on the road (no built roads here)")
		return
	var pt := life.journey_point(life.journeys[id])
	if pt.is_empty():
		skip("the Merrowby caravan has no road")
		return
	var at: Vector2 = pt["at"]
	player.global_position = Vector3(at.x + 120.0, 0.0, at.y)
	life._stand_caravans(player.global_position)
	assert_true(life.live_caravans.has(id), "stood up near the player")
	await _physics(2)
	var metres := float(life.journeys[id]["metres"])
	var saved := life.to_save()
	life.from_save(saved)
	await _physics(1)
	assert_true(life.live_caravans.is_empty(), "a load begins with nothing stood")
	assert_near(float(life.journeys[id]["metres"]), metres, 5.0, "the journey is where it was")
	life._stand_caravans(player.global_position)
	life._stand_caravans(player.global_position)
	await _physics(2)
	var standing := 0
	for n in _tree().get_nodes_in_group("road_events"):
		if (n as RoadEvent).uid == id and not n.is_queued_for_deletion():
			standing += 1
	assert_eq(standing, 1, "one caravan, not two, after a load")
	# the clock moves an unseen caravan on
	life.clear_live()
	var before := float(life.journeys[id]["metres"])
	life.advance(life.journeys[id], 0.5, RoadLife.now_h())
	assert_gt(float(life.journeys[id]["metres"]), before, "half an hour unseen is road walked")


func _start_caravan() -> RoadEvent:
	var def := ContentDB.get_or_empty("core:roadevent/carters_wagon")
	var pts := PackedVector2Array()
	for p in ROAD_PTS:
		pts.append(Vector2(p[0], p[1]))
	player.global_position = Vector3(1000.0, 0.0, 2460.0)
	var ev := life.start(def, {"at": Vector2(1100.0, 2400.0), "dir": Vector2(1, 0), "kind": "road"}, pts, 200.0, 1, REGION,
			{"id": "test|caravan", "speed": 1.3, "from": "core:place/merrowby"})
	life.live_caravans["test|caravan"] = ev
	return ev


func test_a_caravan_walks_its_road() -> void:
	var ev := _start_caravan()
	await _physics(3)
	assert_true(ev.built, "stood up")
	assert_true(ev.train != null and ev.train.goods != null, "a wagon with a load")
	assert_eq(ev.train.goods.owner_faction, "core:faction/tallymen", "the load is the carters'")
	var start := ev.path_m
	await _physics(300)
	assert_gt(ev.path_m, start + 3.0, "the file went on down the road")
	var lead := ev._leader()
	assert_true(lead != null, "a trader leads")
	var near := RoadSites.nearest(Vector2(lead.global_position.x, lead.global_position.z), 50.0)
	assert_false(near.is_empty(), "the trader is by the road")
	assert_true(float(near.get("dist", 99.0)) < 4.0, "the trader walks the road, %.1f m off it" % float(near.get("dist", 99.0)))
	assert_true(ev.train.global_position.distance_to(lead.global_position) < 12.0, "the wagon keeps behind the trader")


func test_a_caravan_trades_through_the_shop_screen() -> void:
	var ev := _start_caravan()
	await _physics(2)
	var trader: Node3D = null
	for m in ev.members:
		if str(m["role"]) == "trader":
			trader = m["node"]
	assert_true(trader != null, "a trader")
	var shop := trader.get_node_or_null("Merchant") as Merchant
	assert_true(shop != null, "the trader keeps a shop")
	assert_false(shop.items().is_empty(), "with the carter's load on its shelves")
	var asked: Array = []
	var catch := func(id: String) -> void: asked.append(id)
	EventBus.trade_requested.connect(catch)
	ev.talk(trader, player)
	EventBus.trade_requested.disconnect(catch)
	assert_eq(asked, [shop.merchant_id()], "the shop screen was asked for")
	assert_true(EconomyService.merchant_for(shop.merchant_id()) == shop, "and finds this shop")
	UI.close("trade")


func test_the_roads_people_leave_the_player_be_until_struck() -> void:
	var ev := _start_caravan()
	await _physics(2)
	var guard: Enemy = null
	for m in ev.members:
		if str(m["role"]) == "guard":
			guard = m["node"]
	assert_true(guard != null, "a guard")
	assert_true(guard.is_in_group(Perception.ROAD_GROUP))
	assert_false(guard.perception._is_live_quarry(player, "player"), "a guard does not hunt the player")
	var hit := HitData.new()
	hit.attacker = player
	hit.amount = 1.0
	guard.hit_taken.emit(hit, "hit")
	assert_true(ev.provoked, "struck")
	assert_true(guard.perception._is_live_quarry(player, "player"), "and now it does")


# --- the ambush ----------------------------------------------------------------------------------------

func test_an_ambush_springs_on_a_player_and_is_fair() -> void:
	var def := ContentDB.get_or_empty("core:roadevent/hearthvale_larkbourne_ambush")
	var ev := life.start(def, {"at": Vector2(1200.0, 2400.0), "dir": Vector2(1, 0), "kind": "bend", "tell": "crows"},
			PackedVector2Array(), 0.0, 1, REGION)
	await _physics(2)
	assert_true(ev.built)
	var foes: Array[Enemy] = []
	for m in ev.members:
		if m["node"] is Enemy:
			foes.append(m["node"])
	assert_true(foes.size() >= 1 and foes.size() <= int(RoadEvent.FOE_CAP[1]), "a first-tier ambush is %d foes" % foes.size())
	for e in foes:
		assert_false(e.visible, "hidden until sprung")
	assert_true(ev.get_node_or_null("Crows") != null, "the crows over the site are the warning")
	player.global_position = Vector3(1195.0, 0.0, 2400.0)
	await _physics(30)
	assert_eq(ev.state, "sprung", "sprung as the player came to it")
	var out := 0
	for e in foes:
		if e.visible and e.brain.is_fighting():
			out += 1
	assert_true(out >= mini(2, foes.size()), "the first two come out at once")


func test_bandits_set_on_a_caravan_rise_against_its_guards() -> void:
	var caravan := _start_caravan()
	await _physics(2)
	var def := ContentDB.get_or_empty("core:roadevent/hearthvale_raid_on_a_carter")
	var lead := caravan._leader()
	var at := Vector2(lead.global_position.x + 6.0, lead.global_position.z)
	var raid := life.start(def, {"at": at, "dir": Vector2(1, 0), "kind": "raid", "tell": "crows"}, PackedVector2Array(), 0.0, 1, REGION)
	raid.prey = caravan
	await _physics(30)
	assert_eq(raid.state, "sprung", "the raid sprang on the caravan, not the player")
	var bandit: Enemy = null
	for m in raid.members:
		if m["node"] is Enemy:
			bandit = m["node"]
	var guard: Enemy = null
	for m in caravan.members:
		if str(m["role"]) == "guard":
			guard = m["node"]
	assert_true(bandit.perception._is_live_quarry(guard, Perception.ROAD_GROUP), "a bandit hunts a guard")
	assert_true(guard.perception._is_live_quarry(bandit, "enemy"), "and a guard a bandit")
	assert_false(guard.perception._is_live_quarry(player, "player"), "and neither turns the guard on the player")
