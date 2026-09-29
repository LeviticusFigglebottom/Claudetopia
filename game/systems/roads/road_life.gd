class_name RoadLife
extends Node
## The road's own life: what happens in the country round the player while they travel, on foot
## or on a horse (docs/WORLD_LIFE_ROADS.md). The playtest said the land between places was empty.
##
## Two things are kept here.
##
## **Caravans** are the road's standing traffic. Every caravan a region's roadtable names is a
## journey between two places along the built roads (RoadRoutes), kept whether anybody is near or
## not: its trader walks it at their pace on the game's clock, rests at each end, and turns round.
## Near the player (CARAVAN_NEAR_M) the journey is stood up as a RoadEvent where the clock has it,
## and taken down again past CARAVAN_FAR_M; the journeys are saved, so a load stands up the same
## caravans where they were and never a second of any.
##
## **Events** are rolled as the player travels: after EVERY_M of road (a random stretch in the
## range), no sooner than GAP_S after the last began and with fewer than MAX_ACTIVE about, the
## region's table is asked what fits the hour, the ground, the player's tier and the road ahead
## (RoadTables), and one is picked by weight and stood up out of sight: ahead on the road where a
## bend, a crest or woods hide it, else behind; an ambush at a site the road has (RoadSites). A row's
## own cooldown keeps one thing from coming twice in an afternoon. Events are not saved: a load
## begins with none, and the caravans.
##
## Never where it should not be: nothing is rolled while the player is indoors, in a film, talking,
## fighting, travelling by Hearthstone, under the loading curtain, escorting somebody, in a style's
## first lesson, or while anything has hushed the road (`hush`, or the flag `road_life/hush` a
## quest may set); nothing is stood up within a settlement's bounds or a Hearthstone's, on a place's
## pad, nearer than MIN_SPAWN_M, in a cell not standing, or where the camera sees it
## (`in_view`: in the frustum, within VIEW_M, and not behind the ground). Everything it stands up is
## taken down out of sight once the player is DESPAWN_M away or its cell goes.
##
## Every body is stood up within WorldPace's budget, one event building at a time (RoadEvent.build).

const GROUP := "road_life"
const SECTION := "road_life"
const MAX_ACTIVE := 3
const GAP_S := 55.0
const EVERY_M := Vector2(260.0, 520.0)
const LOOK_S := 1.0
const NEAR_ROAD_M := 70.0
const AHEAD_M := Vector2(120.0, 200.0)
const BEHIND_M := Vector2(95.0, 150.0)
const SITE_AHEAD_M := Vector2(110.0, 280.0)
const MIN_SPAWN_M := 70.0
const VIEW_M := 320.0
const VIEW_MARGIN := 1.25
const DESPAWN_M := 300.0
const RESOLVED_GONE_M := 90.0
const CARAVAN_NEAR_M := 230.0
const CARAVAN_FAR_M := 330.0
## A move further than this between two looks is a jump (a Hearthstone, a load), not travel.
const JUMP_M := 80.0
## Game hours a caravan rests at each end of its road, and days before a broken one sets out again.
const CARAVAN_REST_H := 3.0
const CARAVAN_LOST_H := 72.0
## What a metre of the road is on the game's clock: real seconds a game hour takes by day (a 48
## minute day at WorldClock.DAY_RATE), so a caravan walks as far unseen as seen.
const SECONDS_PER_GAME_HOUR := 144.0
## Round a settlement (beyond its pad) and a Hearthstone, and on any place's pad.
const TOWN_MARGIN_M := 90.0
const STONE_M := 60.0
const PAD_MARGIN_M := 15.0
const POIS_PATH := "res://world/generated/pois.json"

static var instance: RoadLife = null
## Whether it runs: -1 as the game does (only where something is drawn, and a world stands), 1
## always (a test, the road-life probe), 0 never.
static var forced := -1

var enabled := true
var rng := RandomNumberGenerator.new()
## id -> {id, event, region, from, to, metres, state: road|resting|lost, until_h, speed}
var journeys: Dictionary = {}
## event id -> absolute game hour it may come again
var cooldowns: Dictionary = {}
var travel_m := 0.0
var next_due_m := 400.0
var since_start_s := 999.0
var events: Array[RoadEvent] = []
var live_caravans: Dictionary = {}     # journey id -> RoadEvent
var hush_reasons: Dictionary = {}
var stats := {"rolls": 0, "started": {}, "skipped": {}, "despawned": 0, "caravans_stood": 0, "outcomes": {}}
## A test's or tool's own camera for `in_view` (else the viewport's).
var camera_override: Camera3D = null
## A test's own ground (x, z) -> height.
var ground := Callable()
## Off only for a test: the world's own reasons for quiet (a film, the curtain, a conversation, a
## fight, an escort, a lesson) are not asked, only `hush` and the flag.
var world_checks := true

var _look := PollTimer.new(LOOK_S)
var _last_pos := Vector3.INF
var _last_h := -1.0
var _building := false
var _engaged: Dictionary = {}
var _pads: Array = []
var _uid := 0


static func ensure() -> RoadLife:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is RoadLife:
		return found as RoadLife
	var made := RoadLife.new()
	made.name = "RoadLife"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


func _enter_tree() -> void:
	instance = self
	add_to_group(GROUP)


func _exit_tree() -> void:
	if instance == self:
		instance = null
	SaveSystem.unregister(SECTION)


func _ready() -> void:
	rng.randomize()
	next_due_m = rng.randf_range(EVERY_M.x, EVERY_M.y)
	SaveSystem.register(SECTION, self)
	EventBus.cell_unloaded.connect(_on_cell_unloaded)
	EventBus.enemy_engaged.connect(_on_enemy_engaged)
	if journeys.is_empty():
		seed_journeys()


## Whether the director runs at all here.
func running() -> bool:
	if not enabled or forced == 0:
		return false
	if forced == 1:
		return true
	return World.instance != null and DisplayServer.get_name() != "headless"


func _process(delta: float) -> void:
	since_start_s += delta
	if not running() or not _look.due(delta):
		return
	look()


## One look round: the caravans' clocks, what is too far, and whether something new is due.
func look() -> void:
	var player := Peers.player() as Node3D
	_advance_journeys()
	if player == null or not player.is_inside_tree():
		return
	var here := player.global_position
	var moved := 0.0 if _last_pos == Vector3.INF else Vector2(here.x - _last_pos.x, here.z - _last_pos.z).length()
	var heading := Vector2.ZERO if _last_pos == Vector3.INF else Vector2(here.x - _last_pos.x, here.z - _last_pos.z)
	_last_pos = here
	if moved < JUMP_M and GameState.current_interior_id == "":
		travel_m += moved
	_take_down(here)
	_stand_caravans(here)
	var why := hushed()
	if why != "":
		_skip(why)
		return
	if travel_m < next_due_m or since_start_s < gap_s() or _active() >= max_active() or _building:
		return
	roll(here, heading)


# --- the budget --------------------------------------------------------------------------------------

func _budget(key: String, fallback: float) -> float:
	var region := WorldProbe.region_id_at(_last_pos) if _last_pos != Vector3.INF else ""
	return float((RoadTables.table(region)["budget"] as Dictionary).get(key, fallback))


func gap_s() -> float:
	return _budget("gap_s", GAP_S)


func max_active() -> int:
	return int(_budget("max_active", MAX_ACTIVE))


func _active() -> int:
	var n := 0
	for e in events:
		if is_instance_valid(e) and e.state != "resolved":
			n += 1
	return n


func _skip(why: String) -> void:
	var s: Dictionary = stats["skipped"]
	s[why] = int(s.get(why, 0)) + 1


## Why nothing new may happen now, or "".
func hushed() -> String:
	if not hush_reasons.is_empty():
		return str(hush_reasons.keys()[0])
	if GameState.has_flag("road_life/hush"):
		return "story"
	if GameState.current_interior_id != "":
		return "indoors"
	if not world_checks:
		return ""
	var tree := get_tree()
	if tree.get_first_node_in_group("cinematic") != null:
		return "film"
	if UI != null and UI.is_faded_out():
		return "curtain"
	if Social.dialogue != null and bool(Social.dialogue.call("is_running")):
		return "talk"
	if Hearth != null and Hearth.has_method("is_travelling") and bool(Hearth.call("is_travelling")):
		return "stone"
	if not _engaged.is_empty():
		_prune_engaged()
		if not _engaged.is_empty():
			return "fighting"
	var reg := NpcRegistry.instance
	if reg != null and is_instance_valid(reg) and not reg.escorted_ids().is_empty():
		return "escort"
	if _in_lesson():
		return "lesson"
	return ""


## Stops anything new happening while `reason` holds (a quest's scene, a tool), until `unhush`.
func hush(reason: String) -> void:
	hush_reasons[reason] = true


func unhush(reason: String) -> void:
	hush_reasons.erase(reason)


## A style's first lesson is taught on quiet roads: the tutorial quests of the styles.
func _in_lesson() -> bool:
	var quest_log := Peers.quests()
	if quest_log == null or not quest_log.has_method("is_active"):
		return false
	for s in ContentDB.all("style"):
		var q := str(s.get("tutorial", ""))
		if q != "" and bool(quest_log.call("is_active", q)):
			return true
	return false


func _on_enemy_engaged(enemy: Node, engaged: bool) -> void:
	if enemy == null:
		return
	if engaged:
		_engaged[enemy.get_instance_id()] = enemy
	else:
		_engaged.erase(enemy.get_instance_id())


func _prune_engaged() -> void:
	for k in _engaged.keys():
		var e: Variant = _engaged[k]
		if not is_instance_valid(e) or (e as Node).is_queued_for_deletion() or bool((e as Node).get("dead")):
			_engaged.erase(k)


# --- where nothing happens ---------------------------------------------------------------------------

## Whether `p` is inside a settlement's bounds, a lit Hearthstone's round, or on any place's pad.
func is_safe(p: Vector3) -> bool:
	var flat := Vector2(p.x, p.z)
	for pad in _pad_list():
		var d := flat.distance_to(pad["at"])
		if d < float(pad["radius"]) + (TOWN_MARGIN_M if bool(pad["town"]) else PAD_MARGIN_M):
			return true
	for s in get_tree().get_nodes_in_group("hearthstone"):
		if s is Node3D and flat.distance_to(Vector2((s as Node3D).global_position.x, (s as Node3D).global_position.z)) < STONE_M:
			return true
	return false


func _pad_list() -> Array:
	if not _pads.is_empty():
		return _pads
	if FileAccess.file_exists(POIS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POIS_PATH))
		if parsed is Array:
			for p in parsed:
				var pos: Array = (p as Dictionary).get("pos", [])
				if pos.size() < 3:
					continue
				var kind := str(ContentDB.get_or_empty(str(p.get("place_id", ""))).get("kind", ""))
				_pads.append({"at": Vector2(float(pos[0]), float(pos[2])), "radius": float(p.get("radius_flat_m", 30.0)),
						"town": kind in Crimes.SETTLEMENT_KINDS})
	if _pads.is_empty():
		# no built world: the places' own positions and a town's size
		for d in ContentDB.all("place"):
			var xz := WorldProbe.xz_of(d)
			if xz != Vector2.ZERO:
				_pads.append({"at": xz, "radius": 60.0, "town": str(d.get("kind", "")) in Crimes.SETTLEMENT_KINDS})
		if _pads.is_empty():
			_pads.append({"at": Vector2(INF, INF), "radius": 0.0, "town": false})
	return _pads


## For a test: the pads and towns to use.
func use_pads(pads: Array) -> void:
	_pads = pads


## Whether the camera sees `p`: in its frustum, within VIEW_M, and not behind the ground.
func in_view(p: Vector3) -> bool:
	var cam := camera_override
	if cam == null and is_inside_tree():
		cam = get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return false
	var from := cam.global_position
	if from.distance_to(p) > VIEW_M:
		return false
	if not in_frustum(cam, p):
		return false
	return not _behind_ground(from, p)


## Whether `p` is inside the camera's view, widened by VIEW_MARGIN so that a thing just past the
## frame's edge is not stood up for a small turn of the head to find. Worked out from the camera's
## own angle and the viewport's shape (not the engine's frustum, which a headless run has none of).
func in_frustum(cam: Camera3D, p: Vector3) -> bool:
	var local := cam.global_transform.affine_inverse() * p
	if local.z >= -0.1:
		return false
	var size := cam.get_viewport().get_visible_rect().size if cam.get_viewport() != null else Vector2(16, 9)
	var aspect := size.x / size.y if size.y > 0.0 else 16.0 / 9.0
	var tan_v := tan(deg_to_rad(cam.fov * 0.5)) * VIEW_MARGIN
	var depth := -local.z
	return absf(local.y) <= tan_v * depth and absf(local.x) <= tan_v * aspect * depth


func any_in_view(pts: Array) -> bool:
	for p in pts:
		if in_view(p):
			return true
	return false


func _behind_ground(from: Vector3, to: Vector3) -> bool:
	for i in range(1, 12):
		var t := float(i) / 12.0
		var q := from.lerp(to, t)
		if _height(q.x, q.z, -INF) > q.y + 0.6:
			return true
	return false


func _height(x: float, z: float, fallback := 0.0) -> float:
	if ground.is_valid():
		return float(ground.call(x, z))
	if World.instance != null:
		return World.get_height(x, z)
	return fallback


func _standing(p: Vector3) -> bool:
	if World.instance == null or World.instance.streamer == null:
		return true
	return World.instance.streamer.is_loaded_around(p, 0)


## Whether a spot is fit to stand something up at: not safe ground, not in sight, not on top of
## the player, and in a standing cell.
func fit(p: Vector3, player_at: Vector3) -> String:
	if Vector2(p.x - player_at.x, p.z - player_at.z).length() < MIN_SPAWN_M:
		return "too near"
	if is_safe(p):
		return "safe ground"
	if in_view(p + Vector3.UP):
		return "in view"
	if not _standing(p):
		return "not standing"
	return ""


# --- rolling -------------------------------------------------------------------------------------------

## Asks the region's table for something that fits, and stands it up. Returns the event or null.
func roll(here: Vector3, heading := Vector2.ZERO) -> RoadEvent:
	stats["rolls"] = int(stats["rolls"]) + 1
	if is_safe(here):
		_skip("player on safe ground")
		return null
	var region := WorldProbe.region_id_at(here)
	var flat := Vector2(here.x, here.z)
	var near := RoadSites.nearest(flat, NEAR_ROAD_M)
	var way := 1
	if not near.is_empty():
		var dir: Vector2 = near["dir"]
		var facing := heading
		if facing.length() < 0.5:
			var p := Peers.player() as Node3D
			if p != null:
				var f := -p.global_transform.basis.z
				facing = Vector2(f.x, f.z)
		way = 1 if facing.dot(dir) >= 0.0 else -1
	var ahead_kinds: Array = []
	if not near.is_empty():
		for f in RoadSites.features(int(near["road"])):
			var d := (float(f["along"]) - float(near["along"])) * way
			if d >= SITE_AHEAD_M.x and d <= SITE_AHEAD_M.y and not ahead_kinds.has(f["kind"]):
				ahead_kinds.append(f["kind"])
	var level := 1
	var prog := Peers.progression()
	if prog != null and prog.get("level") != null:
		level = int(prog.get("level"))
	var ctx := {"hour": WorldClock.time_hours, "biome": RoadSites.biome_at(near.get("at", flat)),
			"tier": RoadTables.tier_of_level(level), "sites": ahead_kinds, "now_h": now_h(),
			"cooldowns": cooldowns, "on_road": not near.is_empty()}
	var rows := RoadTables.rows_for(region, ctx)
	if rows.is_empty():
		_skip("nothing fits")
		_next_stretch()
		return null
	var row := RoadTables.pick(rows, rng)
	var def := ContentDB.get_or_empty(str(row["event"]))
	var ev := _place(def, row, here, near, way, int(ctx["tier"]), region)
	if ev == null:
		_next_stretch(0.35)
		return null
	cooldowns[str(def["id"])] = now_h() + float(row.get("cooldown_h", def.get("cooldown_h", 4.0)))
	_next_stretch()
	since_start_s = 0.0
	return ev


func _next_stretch(share := 1.0) -> void:
	travel_m = 0.0
	next_due_m = rng.randf_range(EVERY_M.x, EVERY_M.y) * share
	var every: Variant = RoadTables.table(WorldProbe.region_id_at(_last_pos) if _last_pos != Vector3.INF else "")["budget"].get("every_m", null)
	if every is Array and (every as Array).size() >= 2:
		next_due_m = rng.randf_range(float(every[0]), float(every[1])) * share


## Finds where `def` can happen near the player and stands it up there; null when nowhere fits.
func _place(def: Dictionary, row: Dictionary, here: Vector3, near: Dictionary, way: int, tier: int, region: String) -> RoadEvent:
	var kind := str(def.get("kind", ""))
	if str(def.get("prey", "")) == "caravan":
		return _place_raid(def, here, tier, region)
	if near.is_empty():
		if kind not in ["beasts", "wanderer"]:
			_skip("off the road")
			return null
		# off the road: across the player's way, well ahead
		var p := Peers.player() as Node3D
		var f := -p.global_transform.basis.z if p != null else Vector3.FORWARD
		var at := Vector2(here.x, here.z) + Vector2(f.x, f.z).normalized() * rng.randf_range(AHEAD_M.x, AHEAD_M.y)
		var why := fit(_v3(at), here)
		if why != "":
			_skip(why)
			return null
		return start(def, {"at": at, "dir": Vector2(f.z, -f.x).normalized(), "kind": "open"}, PackedVector2Array(), 0.0, tier, region)
	var road := int(near["road"])
	var along := float(near["along"])
	var candidates: Array = []
	var needs: Array = row.get("sites", [])
	if kind == "ambush" or not needs.is_empty():
		var f := RoadSites.feature_ahead(road, along, way, SITE_AHEAD_M.x, SITE_AHEAD_M.y, needs)
		if not f.is_empty():
			candidates.append({"along": float(f["along"]), "kind": str(f["kind"]), "tell": str(f.get("tell", ""))})
		elif kind == "ambush":
			_skip("no site ahead")
			return null
	else:
		for i in 3:
			candidates.append({"along": along + way * rng.randf_range(AHEAD_M.x, AHEAD_M.y), "kind": "road"})
		for i in 2:
			candidates.append({"along": along - way * rng.randf_range(BEHIND_M.x, BEHIND_M.y), "kind": "road"})
	for c in candidates:
		var s := clampf(float(c["along"]), 5.0, RoadSites.length_of(road) - 5.0)
		var pt := RoadSites.point_at(road, s)
		var why := fit(_v3(pt["at"]), here)
		if why != "":
			_skip(why)
			continue
		var site := {"at": pt["at"], "dir": pt["dir"], "kind": str(c["kind"]), "tell": str(c.get("tell", ""))}
		# the walkers come towards the player from ahead, and catch up from behind
		var path := _road_points(road)
		var path_m := s
		var toward_player := (s - along) * way > 0.0
		var go := -way if toward_player else way
		if go < 0:
			path.reverse()
			path_m = RoadSites.length_of(road) - s
		return start(def, site, path, path_m, tier, region)
	return null


func _road_points(road: int) -> PackedVector2Array:
	var r: Dictionary = RoadSites.roads()[road]
	return (r["points"] as PackedVector2Array).duplicate()


## An ambush laid for a caravan the player can see coming: ahead of it on its own road, out of the
## player's sight.
func _place_raid(def: Dictionary, here: Vector3, tier: int, region: String) -> RoadEvent:
	for id in live_caravans:
		var c: RoadEvent = live_caravans[id]
		if not is_instance_valid(c) or not c.built or c.state != "live" or c.focus().distance_to(here) > 300.0:
			continue
		var ahead := c.path_m + rng.randf_range(60.0, 110.0)
		if ahead > RoadRoutes.length_of(c.path) - 20.0:
			continue
		var pt := RoadRoutes.point_along(c.path, ahead)
		var why := fit(_v3(pt["at"]), here)
		if why != "":
			_skip(why)
			continue
		var ev := start(def, {"at": pt["at"], "dir": pt["dir"], "kind": "raid"}, PackedVector2Array(), 0.0, tier, region)
		ev.prey = c
		return ev
	_skip("no caravan to raid")
	return null


func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, _height(p.x, p.y), p.y)


## Stands up `def` at `site` (and along `path` from `path_m` for walkers). The build is paced.
func start(def: Dictionary, site: Dictionary, path: PackedVector2Array, path_m: float, tier: int, region: String, journey: Dictionary = {}) -> RoadEvent:
	var ev := RoadEvent.new()
	_uid += 1
	ev.uid = str(journey.get("id", "road_%d_%d" % [Time.get_ticks_msec(), _uid]))
	ev.name = "RoadEvent_%s" % Ids.name_of(str(def.get("id", "x"))).left(24)
	ev.def = def
	ev.kind = str(def.get("kind", ""))
	ev.region = region
	ev.tier = tier
	ev.rng.seed = hash(ev.uid)
	ev.site = site
	ev.tell = str(site.get("tell", ""))
	ev.path = path
	ev.path_m = path_m
	ev.speed = float(journey.get("speed", def.get("speed", 1.3)))
	ev.journey = journey
	ev.terrain_height = ground
	add_child(ev)
	ev.global_position = _v3(site.get("at", path[0] if path.size() > 0 else Vector2.ZERO))
	if journey.is_empty():
		events.append(ev)
	var st: Dictionary = stats["started"]
	st[ev.kind] = int(st.get(ev.kind, 0)) + 1
	_building = true
	_build(ev)
	return ev


func _build(ev: RoadEvent) -> void:
	# wait for the frame's budget before the first body: an event never begins in a spent frame
	while WorldPace.paced() and WorldPace.left_usec() <= 0 and is_instance_valid(ev):
		await WorldPace.next_frame()
	if is_instance_valid(ev):
		await ev.build()
	_building = false


## What an event came to (RoadEvent.finish, and a caravan broken or set upon).
func note_outcome(ev: RoadEvent, how: String) -> void:
	var o: Dictionary = stats["outcomes"]
	o[how] = int(o.get(how, 0)) + 1
	if not ev.journey.is_empty() and how == "broken":
		var j: Dictionary = ev.journey
		j["state"] = "lost"
		j["until_h"] = now_h() + CARAVAN_LOST_H


# --- taking down ---------------------------------------------------------------------------------------

func _take_down(here: Vector3) -> void:
	for v in events.duplicate():
		if not is_instance_valid(v):
			events.erase(v)
			continue
		var ev := v as RoadEvent
		var d := ev.focus().distance_to(here)
		var far := d > DESPAWN_M or (ev.state == "resolved" and d > RESOLVED_GONE_M)
		if far and not ev.fighting() and not any_in_view(ev.points()):
			_drop(ev)
	for id in live_caravans.keys():
		var c: RoadEvent = live_caravans[id]
		if not is_instance_valid(c):
			live_caravans.erase(id)
			continue
		var d := c.focus().distance_to(here)
		var done := c.arrived() or c.state == "broken"
		if (d > CARAVAN_FAR_M or done) and not c.fighting() and not any_in_view(c.points()):
			_drop_caravan(str(id))


func _drop(ev: RoadEvent) -> void:
	events.erase(ev)
	stats["despawned"] = int(stats["despawned"]) + 1
	ev.queue_free()


func _drop_caravan(id: String) -> void:
	var c: RoadEvent = live_caravans.get(id, null)
	live_caravans.erase(id)
	if c != null and is_instance_valid(c):
		var j: Dictionary = journeys.get(id, {})
		if not j.is_empty() and j.get("state", "") == "road":
			j["metres"] = c.path_m
		stats["despawned"] = int(stats["despawned"]) + 1
		c.queue_free()


func _on_cell_unloaded(cell: Vector2i) -> void:
	for v in events.duplicate():
		if is_instance_valid(v) and WorldProbe.cell_of((v as RoadEvent).focus()) == cell and not (v as RoadEvent).fighting():
			_drop(v as RoadEvent)
	for id in live_caravans.keys():
		var c: RoadEvent = live_caravans[id]
		if is_instance_valid(c) and WorldProbe.cell_of(c.focus()) == cell and not c.fighting():
			_drop_caravan(str(id))


## Takes everything stood up down at once (a load, a test).
func clear_live() -> void:
	for ev in events:
		if is_instance_valid(ev):
			ev.queue_free()
	events.clear()
	for id in live_caravans:
		if is_instance_valid(live_caravans[id]):
			(live_caravans[id] as Node).queue_free()
	live_caravans.clear()
	_building = false


# --- caravans ------------------------------------------------------------------------------------------

static func now_h() -> float:
	return float(WorldClock.day) * 24.0 + WorldClock.time_hours


## Every caravan the tables name, set out on its road at its `start` share of the way (or one of its
## own), if it has no journey yet.
func seed_journeys() -> void:
	for c in RoadTables.caravans():
		var route: Array = c.get("route", [])
		if route.size() < 2:
			continue
		var id := "%s|%s|%s" % [c["event"], route[0], route[1]]
		if journeys.has(id):
			continue
		var r := RoadRoutes.route(str(route[0]), str(route[1]))
		var length := RoadRoutes.length_of(r) if r.size() >= 2 else 0.0
		var start_share := float(c.get("start", float(abs(id.hash()) % 1000) / 1000.0))
		journeys[id] = {"id": id, "event": str(c["event"]), "region": str(c.get("region", "")), "from": str(route[0]),
				"to": str(route[1]), "metres": length * clampf(start_share, 0.0, 1.0), "state": "road", "until_h": 0.0,
				"speed": float(c.get("speed", ContentDB.get_or_empty(str(c["event"])).get("speed", 1.3)))}


## The caravans' clocks: how far each has gone since the last look, off the game's hours.
func _advance_journeys() -> void:
	var now := now_h()
	var dt := 0.0 if _last_h < 0.0 else clampf(now - _last_h, 0.0, 24.0 * 7.0)
	_last_h = now
	for id in journeys:
		if live_caravans.has(id):
			continue
		advance(journeys[id], dt, now)


## Moves one journey on by `dt_h` game hours: along its road, resting at the end, turning round.
func advance(j: Dictionary, dt_h: float, now: float) -> void:
	match str(j.get("state", "road")):
		"resting", "lost":
			if now >= float(j.get("until_h", 0.0)):
				j["state"] = "road"
				j["metres"] = 0.0
		"road":
			var length := RoadRoutes.length_of(RoadRoutes.route(str(j["from"]), str(j["to"])))
			j["metres"] = float(j["metres"]) + float(j.get("speed", 1.3)) * SECONDS_PER_GAME_HOUR * dt_h
			if length <= 0.0 or float(j["metres"]) >= length:
				var f := str(j["from"])
				j["from"] = str(j["to"])
				j["to"] = f
				j["metres"] = 0.0
				j["state"] = "resting"
				j["until_h"] = now + CARAVAN_REST_H


## Where a journey's head is now, on the ground ({at: Vector2, dir}), or {} when it is not on a road.
func journey_point(j: Dictionary) -> Dictionary:
	if str(j.get("state", "")) != "road":
		return {}
	var r := RoadRoutes.route(str(j["from"]), str(j["to"]))
	if r.size() < 2:
		return {}
	return RoadRoutes.point_along(r, float(j["metres"]))


## Stands up the journeys near the player that are not yet stood, where the clock has them.
func _stand_caravans(here: Vector3) -> void:
	if _building:
		return
	for id in journeys:
		if live_caravans.has(id):
			continue
		var j: Dictionary = journeys[id]
		var pt := journey_point(j)
		if pt.is_empty():
			continue
		var at := _v3(pt["at"])
		if Vector2(at.x - here.x, at.z - here.z).length() > CARAVAN_NEAR_M:
			continue
		# a caravan is somewhere already: under the curtain it may be stood anywhere, but not on
		# top of the player or where the camera is looking
		var faded := UI != null and UI.is_faded_out()
		if not faded and (in_view(at + Vector3.UP) or Vector2(at.x - here.x, at.z - here.z).length() < MIN_SPAWN_M):
			continue
		if not _standing(at):
			continue
		var def := ContentDB.get_or_empty(str(j["event"]))
		if def.is_empty():
			continue
		var route := RoadRoutes.route(str(j["from"]), str(j["to"]))
		var ev := start(def, {"at": pt["at"], "dir": pt["dir"], "kind": "road"}, route, float(j["metres"]), 1, str(j["region"]), j)
		ev.uid = str(id)
		live_caravans[id] = ev
		stats["caravans_stood"] = int(stats["caravans_stood"]) + 1
		return


# --- save --------------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	for id in live_caravans:
		var c: RoadEvent = live_caravans[id]
		if is_instance_valid(c) and journeys.has(id) and str(journeys[id].get("state", "")) == "road":
			journeys[id]["metres"] = c.path_m
	return {"journeys": journeys.duplicate(true), "cooldowns": cooldowns.duplicate(), "travel_m": travel_m,
			"next_due_m": next_due_m, "last_h": _last_h}


func from_save(d: Dictionary) -> void:
	clear_live()
	journeys = (d.get("journeys", {}) as Dictionary).duplicate(true)
	cooldowns = (d.get("cooldowns", {}) as Dictionary).duplicate()
	travel_m = float(d.get("travel_m", 0.0))
	next_due_m = float(d.get("next_due_m", next_due_m))
	_last_h = float(d.get("last_h", -1.0))
	_last_pos = Vector3.INF
	# a table added since the save was written sets its caravans out too
	seed_journeys()
