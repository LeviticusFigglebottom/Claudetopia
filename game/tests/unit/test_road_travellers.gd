extends TestCase
## Somebody on the road. A schedule that took a person from one place to another had them set out
## twenty game-minutes before they were due and stand up at the far end: nobody was ever met on a
## road. A traveller now stands on the built road, at the share of the journey the clock says is
## done, and walks it. These read the built world's roads (`world/generated/roads.json`); with none
## they say so once and skip.

const FROM := "core:place/pilgrims_ash"
const TO := "core:place/ashwell"
const ON_ROAD_M := 14.0

var registry: NpcRegistry
var host: Node3D
var _roads: Array = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	RoadRoutes.reset()
	_roads = _read_roads()
	registry = NpcRegistry.ensure()
	registry.despawn_all()
	registry.states.clear()
	registry.abstract_only = false
	registry.spawning_enabled = true
	registry.rebuild()
	var streamer := _tree().get_first_node_in_group(NpcStreamer.GROUP)
	if streamer != null:
		streamer.set("enabled", false)
	host = Node3D.new()
	host.name = "RoadTestHost"
	host.add_to_group("world_dynamic")
	_tree().root.add_child(host)


func after_each() -> void:
	registry.despawn_all()
	registry.states.clear()
	registry.rebuild()
	if is_instance_valid(host):
		host.queue_free()
	WorldClock.set_time(8.0, 1)


func _read_roads() -> Array:
	if not FileAccess.file_exists(RoadRoutes.ROADS_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RoadRoutes.ROADS_PATH))
	return parsed if typeof(parsed) == TYPE_ARRAY else []


## How far a point is from the nearest built road.
func _off_road(p: Vector2) -> float:
	var best := INF
	for r_v in _roads:
		var pts: Array = (r_v as Dictionary).get("points", [])
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			var seg := a.distance_to(b)
			var t := 0.0 if seg == 0.0 else clampf((p - a).dot(b - a) / (seg * seg), 0.0, 1.0)
			best = minf(best, p.distance_to(a.lerp(b, t)))
	return best


func test_the_way_between_two_places_is_the_road() -> void:
	if _roads.is_empty():
		return
	var r := RoadRoutes.route(FROM, TO)
	assert_gt(r.size(), 3, "Pilgrim's Ash to Ashwell is a road, not a line")
	var a := WorldProbe.place_position(FROM)
	var b := WorldProbe.place_position(TO)
	assert_true(r[0].distance_to(Vector2(a.x, a.z)) < 1.0, "it starts at the place it leaves")
	assert_true(r[r.size() - 1].distance_to(Vector2(b.x, b.z)) < 1.0, "and ends at the place it goes to")
	var worst := 0.0
	for i in range(1, r.size() - 1):
		worst = maxf(worst, _off_road(r[i]))
	assert_true(worst <= ON_ROAD_M, "every point between is on a road (worst %.1f m off)" % worst)
	assert_gt(RoadRoutes.length_of(r), Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)), "and longer than the crow flies")
	var back := RoadRoutes.route(TO, FROM)
	assert_near(RoadRoutes.length_of(back), RoadRoutes.length_of(r), 1.0, "the way back is as long")


## A person of the pack whose day takes them along a road, caught half way there.
func _someone_on_the_road() -> Dictionary:
	for def in ContentDB.all("npc"):
		var id := str(def["id"])
		if registry.is_gone(id):
			continue
		for day in range(1, 8):
			for k in range(0, 24 * 12):
				var hour := float(k) / 12.0
				var e := Schedules.entry_for_def(def, day, hour)
				if not bool(e.get("travelling", false)):
					continue
				var lead := float(e.get("travel_hours", 0.0))
				var left := float(e.get("arrives_in_hours", 0.0))
				if lead < 0.5 or left > lead * 0.6 or left < lead * 0.4:
					continue
				var r := RoadRoutes.route(str(e["travel_from"]), str(e["place"]))
				if r.size() > 3 and RoadRoutes.length_of(r) > 300.0:
					return {"id": id, "day": day, "hour": hour}
	return {}


## The people whose day is a road (npcs/wayfarers.json) are on it for a good part of the day, and
## what they walk is roads, not the heath between two places nobody joined.
func test_a_wayfarers_day_is_mostly_road() -> void:
	if _roads.is_empty():
		return
	var n := 0
	for def in ContentDB.all("npc"):
		if not (def.get("tags", []) as Array).has("wayfarer"):
			continue
		n += 1
		var on_road := 0
		var samples := 0
		for day in range(1, 8):
			for k in range(0, 24 * 4):
				var e := Schedules.entry_for_def(def, day, float(k) / 4.0)
				samples += 1
				if bool(e.get("travelling", false)):
					on_road += 1
					var r := RoadRoutes.route(str(e["travel_from"]), str(e["place"]))
					assert_gt(r.size(), 2, "%s walks from %s to %s along a road" % [def["id"], e["travel_from"], e["place"]])
		var share := float(on_road) / float(samples)
		# a one-way journey a day at the three-hour cap is an eighth of the day
		assert_true(share >= 0.12, "%s is on the road only %.0f%% of the week" % [def["id"], share * 100.0])
	assert_true(n >= 8, "the wayfarers are written (%d)" % n)


func test_a_traveller_stands_on_the_road_half_way() -> void:
	if _roads.is_empty():
		return
	var who := _someone_on_the_road()
	assert_false(who.is_empty(), "somebody in the pack walks a road between two places of their day")
	if who.is_empty():
		return
	WorldClock.set_time(float(who["hour"]), int(who["day"]))
	registry.simulate(str(who["id"]), "clear")
	var id := str(who["id"])
	assert_true(registry.is_travelling(id), "%s is on the road" % id)
	var at := registry.road_position(id)
	assert_ne(at, Vector3.INF, "and somewhere on it")
	var r := registry.travel_route(id)
	var along := RoadRoutes.progress_of(r, Vector2(at.x, at.z))
	var total := RoadRoutes.length_of(r)
	assert_true(along > total * 0.25 and along < total * 0.75, "about half way (%.0f of %.0f m)" % [along, total])
	assert_true(_off_road(Vector2(at.x, at.z)) <= ON_ROAD_M, "on the road, not beside it")
	assert_eq(registry.cell_of(id), WorldProbe.cell_of(at), "and counted in the cell they are walking through")
	assert_false(registry.is_indoors(id), "out of doors")


func test_a_traveller_walks_along_the_road() -> void:
	if _roads.is_empty():
		return
	var who := _someone_on_the_road()
	if who.is_empty():
		return
	var id := str(who["id"])
	WorldClock.set_time(float(who["hour"]), int(who["day"]))
	WorldClock.running = false
	registry.simulate(id, "clear")
	var body := registry.spawn(id) as Node3D
	assert_true(body != null, "%s is stood up on the road" % id)
	if body == null:
		WorldClock.running = true
		return
	var r := registry.travel_route(id)
	var start := registry.road_position(id)
	assert_true(Vector2(body.global_position.x, body.global_position.z).distance_to(Vector2(start.x, start.z)) < 2.0,
			"where the clock says they have got to")
	var from := RoadRoutes.progress_of(r, Vector2(body.global_position.x, body.global_position.z))
	for i in 90:
		if i % 20 == 0:
			registry.steer_travellers()
		await _tree().physics_frame
	var here := Vector2(body.global_position.x, body.global_position.z)
	var to := RoadRoutes.progress_of(r, here)
	WorldClock.running = true
	assert_gt(to - from, 2.0, "and walks on along it (%.1f m in a second and a half)" % (to - from))
	assert_true(_off_road(here) <= ON_ROAD_M, "keeping to the road")
	assert_eq(str(body.get("activity")), "travel", "as a traveller")
