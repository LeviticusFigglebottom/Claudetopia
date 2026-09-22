extends Node
## The journey: one scripted run through everything a new player is promised.
##
##   ./run.sh journey            (headless, prints a step-by-step report, exits 0 or 1)
##
## DESIGN's "done" list says a new player can create a character, leave the starting area,
## fight, die and recover, level up, join a faction, commit a crime and face the
## consequences, buy a house, clear a dungeon, fight a boss, and save and load. This
## drives the real systems in order and reports which of those are actually true today.
##
## It is deliberately not a unit test: it crosses every system boundary at once, so it is
## the check that catches two streams that each pass their own tests and still do not fit.

class Step:
	var name: String
	var ok: bool
	var detail: String
	var skipped: bool

	func _init(n: String, o: bool, d: String, s := false) -> void:
		name = n
		ok = o
		detail = d
		skipped = s

const WORLD_SCENE := "res://world/world.tscn"
const WORLD_MANIFEST := "res://world/generated/world_manifest.json"

var steps: Array[Step] = []
var world: World = null
var in_the_world := false
var host: Node3D
var player: Node3D
var inventory: Node
var equipment: Node
var progression: Node
var _errors_at_start := 0


func _ready() -> void:
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	await get_tree().process_frame
	_errors_at_start = Log.error_count
	await _make_host()
	await get_tree().process_frame
	print("JOURNEY: starting")

	await _step_character_creation()
	await _step_spawn_player()
	await _step_leave_the_start()
	await _step_find_the_country()
	await _step_meet_somebody()
	await _step_fight()
	await _step_level_up()
	await _step_die_and_recover()
	await _step_join_a_faction()
	await _step_commit_a_crime()
	await _step_buy_a_house()
	await _step_clear_a_dungeon()
	await _step_fight_a_boss()
	await _step_make_something()
	await _step_learn_and_say()
	await _step_save_and_load()
	_report()


## The ground this run happens on. The real world when it has been built — which is the whole
## point of the run: the promises are about the game, not about a slab of test floor — and a
## bare host with a floor under it when it has not, so the journey still reports honestly on a
## checkout where nobody has run `./run.sh world` yet.
func _make_host() -> void:
	if ResourceLoader.exists(WORLD_SCENE) and FileAccess.file_exists(WORLD_MANIFEST):
		var w: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
		add_child(w)
		world = w as World
		if not world.is_world_ready:
			await world.world_ready
		host = world
		in_the_world = true
		return
	host = Node3D.new()
	host.name = "JourneyWorld"
	host.add_to_group("world_dynamic")
	add_child(host)
	var services := GameServices.new()
	services.name = "GameServices"
	add_child(services)


## A real hit, built the way a weapon builds one.
func _hit(amount: float, poise: float) -> HitData:
	var hit := HitData.new()
	hit.amount = amount
	hit.kind = "slash"
	hit.poise_damage = poise
	hit.attacker = player
	hit.source = player
	hit.swing_id = randi()
	hit.origin = player.global_position if player else Vector3.ZERO
	return hit


func _record(name: String, ok: bool, detail := "") -> void:
	steps.append(Step.new(name, ok, detail))
	print("JOURNEY: %s  %s%s" % ["PASS" if ok else "FAIL", name, "  (%s)" % detail if detail != "" else ""])


func _skip(name: String, why: String) -> void:
	steps.append(Step.new(name, true, why, true))
	print("JOURNEY: SKIP  %s  (%s)" % [name, why])


# 1 ------------------------------------------------------------------------------------
func _step_character_creation() -> void:
	var callings := ContentDB.all("calling")
	if callings.is_empty():
		_record("create a character", false, "no callings in the pack")
		return
	var calling: Dictionary = callings[0]
	GameState.reset_for_new_game(1043)
	GameState.set_flag("player_name", "Foundling")
	GameState.set_flag("player_calling", calling["id"])
	GameState.set_flag("player_appearance", {"skin": 3, "hair": 2, "build": 0.5})
	var named: bool = str(GameState.get_flag("player_name", "")) == "Foundling"
	var has_bonuses: bool = calling.has("skill_bonuses") and (calling["skill_bonuses"] as Dictionary).size() > 0
	_record("create a character", named and has_bonuses,
		"%s, calling %s with %d skill bonuses" % ["Foundling", calling["name"], (calling.get("skill_bonuses", {}) as Dictionary).size()])


# 2 ------------------------------------------------------------------------------------
func _step_spawn_player() -> void:
	if not ResourceLoader.exists("res://actors/player/player.tscn"):
		_record("spawn the player", false, "player scene missing")
		return
	if in_the_world:
		# The world stands its own body up at the place the story opens.
		player = get_tree().get_first_node_in_group("player") as Node3D
	else:
		var ground := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(400, 2, 400)
		cs.shape = box
		cs.position.y = -1.0
		ground.add_child(cs)
		ground.collision_layer = 1
		host.add_child(ground)
		player = (load("res://actors/player/player.tscn") as PackedScene).instantiate()
		host.add_child(player)
		player.global_position = Vector3(0, 1.0, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	inventory = get_tree().get_first_node_in_group("inventory")
	equipment = get_tree().get_first_node_in_group("equipment")
	progression = get_tree().get_first_node_in_group("progression")
	if progression and progression.has_method("apply_calling"):
		progression.apply_calling(str(GameState.get_flag("player_calling", "")), inventory)
	var parts: Array[String] = []
	if inventory:
		parts.append("bag")
	if equipment:
		parts.append("equipment")
	if progression:
		parts.append("progression")
	_record("spawn the player with their systems", player != null and inventory != null and progression != null,
		"player up with " + ", ".join(parts))


# 3 ------------------------------------------------------------------------------------
func _step_leave_the_start() -> void:
	if player == null:
		_record("leave the starting area", false, "no player")
		return
	var start := player.global_position
	var reached := 0
	for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		player.global_position = start + dir * 60.0
		await get_tree().process_frame
		if player.global_position.distance_to(start) > 50.0:
			reached += 1
	player.global_position = start
	if not in_the_world:
		_record("leave the starting area in any direction", reached == 4,
			"moved freely in %d of 4 directions; no world built, so this was flat ground" % reached)
		return
	# In the built world, leaving means the country changes around you: new ground under your
	# feet, cells loading, and eventually another region's name on the compass.
	var walk := await _walk_out_of_the_region()
	# Let the ring finish arriving before counting it, so the number is the country that is
	# actually standing around the body rather than whatever was mid-parse.
	for i in 30:
		await get_tree().process_frame
	var cells: int = world.streamer.loaded_count() if world.streamer else 0
	_record("leave the starting area in any direction",
		reached == 4 and float(walk["walked"]) > 100.0 and cells > 0,
		"walked %.0f m over real ground, %d cells streamed, %s -> %s"
			% [float(walk["walked"]), cells, Ids.name_of(str(walk["from"])), Ids.name_of(str(walk["to"]))])


## Walks the body out of the region it woke in, a step at a time, letting the world stream and
## the ground hold it up. Returns the distance covered.
func _walk_out_of_the_region() -> Dictionary:
	var from := player.global_position
	var provider := World.terrain()
	# Character creation resets the world state, so say plainly where the body is standing
	# before asking whether it has gone anywhere.
	if provider != null:
		GameState.enter_region(provider.nearest_region_id_at(from.x, from.z))
	var began := GameState.current_region_id
	var step := 120.0
	var heading := Vector3.FORWARD
	# Head towards the middle of the map, so a body that wakes at the edge walks inland.
	if provider != null:
		heading = (Vector3.ZERO - from)
		heading.y = 0.0
		heading = heading.normalized() if heading.length() > 1.0 else Vector3.FORWARD
	for i in 40:
		var to := player.global_position + heading * step
		if provider != null:
			to.y = provider.get_height(to.x, to.z)
		player.global_position = to
		world.force_stream_around(to)
		await get_tree().process_frame
		if provider != null:
			GameState.enter_region(provider.nearest_region_id_at(to.x, to.z))
		if GameState.current_region_id != began:
			break
	return {"walked": from.distance_to(player.global_position), "from": began,
			"to": GameState.current_region_id}


# 3b -----------------------------------------------------------------------------------
## Finding the country by walking in it, and reading it off high ground. Nothing in the game
## discovered a place by going to one — the chart filled up by being told about places — and
## the survey flag the map reads for its wider reveal was set by nothing outside a fake save.
## Both are only true if they happen to a body standing on the real ground, which is here.
func _step_find_the_country() -> void:
	if player == null or not in_the_world:
		_skip("find the country by walking in it", "no player in a built world")
		return
	var disco := PlaceDiscovery.ensure()
	if disco == null:
		_record("find the country by walking in it", false, "nothing installs PlaceDiscovery")
		return
	disco.enabled = false          # driven a step at a time here rather than per frame

	# A village you have not been told about, walked into.
	var target := ""
	for def in ContentDB.all("place"):
		var id := str(def.get("id", ""))
		if disco.position_of(id) != Vector3.ZERO and not GameState.is_discovered(id):
			target = id
			break
	var arrived := false
	if target != "":
		var at := disco.position_of(target)
		player.global_position = at
		world.force_stream_around(at)
		await get_tree().process_frame
		disco.look_around(at)
		arrived = GameState.is_discovered(target)

	# High ground, and what it shows you. The vista is whichever one the land actually agrees
	# with, because 36 of the 90 authored sightlines are blocked by it (tools/sightlines.py).
	var vantage := ""
	var revealed: Array[String] = []
	for v in disco.vistas():
		var from := disco.position_of(v)
		if from == Vector3.ZERO:
			continue
		GameState.discover(v)
		player.global_position = from
		world.force_stream_around(from)
		await get_tree().process_frame
		revealed = disco.survey(v)
		if not revealed.is_empty():
			vantage = v
			break
	var surveyed := vantage != "" and GameState.has_flag("surveyed:" + vantage)
	_record("find the country by walking in it and looking out from it",
		arrived and surveyed and not revealed.is_empty(),
		"walked into %s; surveyed %s and made out %d more: %s"
			% [Ids.name_of(target), Ids.name_of(vantage), revealed.size(),
				", ".join(revealed.map(func(i: String) -> String: return Ids.name_of(i)))])


# 4 ------------------------------------------------------------------------------------
## Walk into a village and meet somebody who lives there. Every part of this was already
## tested on its own -- the roster, the greetings, the dialogue graph -- and none of it had
## ever been run against a body standing on real ground in a real village, which is the only
## arrangement a player will ever see it in.
func _step_meet_somebody() -> void:
	var name := "meet somebody who lives here"
	if player == null:
		_record(name, false, "no player")
		return
	# Social is an autoload, not a group member: it is always there, and reaching for it by
	# group is how this step spent its first run reporting that talking was not installed.
	var social: Node = Social
	if social == null:
		_record(name, false, "no social autoload")
		return
	var registry := NpcRegistry.ensure()
	var streamer := NpcStreamer.ensure()
	if registry == null or streamer == null:
		_record(name, false, "the roster or the streamer is not installed")
		return

	var village := "core:place/merrowby"
	if in_the_world:
		var world := World.instance
		if world != null:
			var at := world.place_position(village)
			player.global_position = at + Vector3(0.0, 1.0, 0.0)
			world.move_target(player.global_position)
			await get_tree().process_frame
	# midday, so the village is out of doors rather than asleep
	WorldClock.set_time(12.0)
	registry.simulate_all("clear")
	streamer.refresh()
	await get_tree().process_frame

	var standing: Array[String] = []
	for id in registry.spawned.keys():
		if registry.place_of(str(id)) == village:
			standing.append(str(id))
	if standing.is_empty():
		_record(name, false, "nobody was standing in %s at noon" % village)
		return
	standing.sort()

	# Walk up to them in turn until somebody has something to say. A villager whose only
	# dialogue is gated behind a quest you have not taken closes the conversation at once,
	# which is correct of them and useless as evidence that talking works at all.
	social.set_place(village)
	var met := ""
	var who := ""
	var hello := ""
	# A GDScript lambda captures locals by value, so a captured String is written to a copy and
	# the caller never sees it. An Array's reference is copied instead, and appending to it is
	# visible here — which is how this step spent two runs reporting that a village of
	# twenty-three people had nothing to say.
	var sink: Array = []
	var listen := func(_speaker: String, text: String, _choices: Array) -> void:
		sink.append(text)
	social.dialogue.line_shown.connect(listen)
	for candidate in standing:
		sink.clear()
		hello = str(social.greet(candidate))
		social.talk(candidate)
		await get_tree().process_frame
		if not sink.is_empty() and not hello.is_empty():
			met = candidate
			who = str(ContentDB.get_or_empty(candidate).get("name", candidate))
			break
	social.dialogue.line_shown.disconnect(listen)
	var spoken: String = str(sink[0]) if not sink.is_empty() else ""
	if met == "":
		_record(name, false, "%d villagers were standing there and none of them said anything"
				% standing.size())
		return

	var body := registry.actor(met)
	var on_the_ground := true
	if in_the_world and body is Node3D:
		var at2: Vector3 = (body as Node3D).global_position
		on_the_ground = absf(at2.y - World.get_height(at2.x, at2.z)) < 2.5
	_record(name, on_the_ground,
		"%d in the street; %s said \"%s\"" % [standing.size(), who, spoken.substr(0, 52).strip_edges()])


# 5 ------------------------------------------------------------------------------------
func _step_fight() -> void:
	if player == null or not ResourceLoader.exists("res://actors/enemy/enemy.tscn"):
		_record("fight something", false, "no player or no enemy scene")
		return
	var enemies := ContentDB.all("enemy")
	if enemies.is_empty():
		_record("fight something", false, "no enemies in the pack")
		return
	var enemy := (load("res://actors/enemy/enemy.tscn") as PackedScene).instantiate()
	enemy.configure(str(enemies[0]["id"]))
	host.add_child(enemy)
	(enemy as Node3D).global_position = player.global_position + Vector3(0, 0, -2.0)
	await get_tree().process_frame
	var before: float = enemy.get("health")
	# Hit it the way the game does: through the damage model, not by writing the number.
	enemy.take_hit(_hit(14.0, 12.0))
	await get_tree().process_frame
	var after: float = enemy.get("health")
	_record("fight something", after < before, "%s took %.1f damage (%.1f -> %.1f)" % [enemies[0]["name"], before - after, before, after])
	enemy.queue_free()
	await get_tree().process_frame


# 5 ------------------------------------------------------------------------------------
func _step_level_up() -> void:
	if progression == null:
		_record("level up by doing", false, "no progression node")
		return
	var start_level: int = progression.get("level")
	var skill := "one_handed"
	if progression.has_method("skills"):
		var list: Array = progression.skills()
		if list.size() > 0:
			skill = str((list[0] as Dictionary).get("id", skill)).trim_prefix("core:skill/")
	# Use the skill many times, the way the game grants it: through the event.
	for i in 400:
		EventBus.skill_used.emit("core:skill/%s" % skill, 8.0)
	await get_tree().process_frame
	var end_level: int = progression.get("level")
	var skill_level: int = progression.skill_level("core:skill/%s" % skill) if progression.has_method("skill_level") else 0
	_record("level up by doing", end_level > start_level or skill_level > 5,
		"%s reached %d, character level %d -> %d" % [skill, skill_level, start_level, end_level])


# 6 ------------------------------------------------------------------------------------
func _step_die_and_recover() -> void:
	if player == null:
		_record("die and get your marks back", false, "no player")
		return
	if inventory and inventory.has_method("add_marks"):
		inventory.add_marks(200)
	var stone := (load("res://systems/hearth/hearthstone.tscn") as PackedScene).instantiate()
	host.add_child(stone)
	(stone as Node3D).global_position = player.global_position + Vector3(3, 0, 0)
	stone.hearthstone_id = "journey_stone"
	# One frame at each settling point. This step waited two, on the theory that a single frame
	# was "marginal" -- it was not: the Echo was an Area3D standing on the body that had just
	# fallen, so it recovered itself on the first physics tick after the death and which of the
	# five conditions came back false depended on where that tick landed. The cause is fixed in
	# `Hearth` (an Echo answers nobody until the player has come back for it) and pinned in
	# `test_hearth.gd`, so the extra frames are gone: a step that needs padding to pass is not
	# measuring the hearth, it is measuring the frame scheduler.
	await get_tree().process_frame
	stone.interact(player)
	var rested: bool = Hearth.last_hearthstone_id == "journey_stone"

	var marks_before: int = int(inventory.get("marks")) if inventory else 0
	var death_spot := player.global_position + Vector3(0, 0, -30.0)
	player.global_position = death_spot
	EventBus.player_died.emit(death_spot)
	await get_tree().process_frame
	var dropped: bool = Hearth.has_echo() and int(Hearth.echo.get("marks", 0)) == marks_before
	Hearth._respawn()
	await get_tree().process_frame
	var back_at_stone: bool = player.global_position.distance_to(Hearth.respawn_position) < 1.0
	var marks_gone: bool = int(inventory.get("marks")) == 0 if inventory else true
	Hearth.recover_echo()
	await get_tree().process_frame
	var recovered: bool = int(inventory.get("marks")) == marks_before if inventory else true
	var whole: bool = rested and dropped and back_at_stone and marks_gone and recovered
	var how := "rested, dropped %d marks on death, respawned at the stone, recovered them" % marks_before
	if not whole:
		# Which half of it broke, so a failure here names itself instead of reading like a mood.
		how = "rested=%s dropped=%s back_at_stone=%s marks_gone=%s recovered=%s (marks before %d, now %d)" % [
			rested, dropped, back_at_stone, marks_gone, recovered, marks_before,
			int(inventory.get("marks")) if inventory else -1]
	_record("die and get your marks back", whole, how)


# 7 ------------------------------------------------------------------------------------
func _step_join_a_faction() -> void:
	var factions := get_tree().get_first_node_in_group("factions")
	if factions == null:
		_record("join a faction", false, "no factions node")
		return
	var joinable := ContentDB.where("faction", "joinable", true)
	if joinable.is_empty():
		_record("join a faction", false, "no joinable factions")
		return
	var id := str(joinable[0]["id"])
	if factions.has_method("join"):
		factions.join(id)
	if factions.has_method("adjust"):
		factions.adjust(id, 50)
	elif factions.has_method("add_reputation"):
		factions.add_reputation(id, 50)
	await get_tree().process_frame
	var member: bool = factions.is_member(id) if factions.has_method("is_member") else false
	var rank: int = factions.rank(id) if factions.has_method("rank") else 0
	var rank_name: String = factions.rank_name(id) if factions.has_method("rank_name") else ""
	_record("join a faction and rise in it", member and rank > 0,
		"%s: rank %d (%s)" % [joinable[0]["name"], rank, rank_name])


# 8 ------------------------------------------------------------------------------------
func _step_commit_a_crime() -> void:
	var crime := get_tree().get_first_node_in_group("crime")
	if crime == null:
		_record("commit a crime and face the consequences", false, "no crime node")
		return
	var law := "core:faction/wardens"
	var before: int = crime.bounty(law) if crime.has_method("bounty") else 0
	if crime.has_method("report_crime"):
		crime.report_crime({"kind": "theft", "value": 40,
							"position": player.global_position if player else Vector3.ZERO,
							"region_id": "core:region/hearthvale", "place_id": "core:place/merrowby",
							"extra_witnesses": [
								{"npc_id": "core:npc/maud_brambling", "detection": 1.0, "line_of_sight": true,
								 "place_id": "core:place/merrowby", "reaction": "report", "is_guard": false},
								{"npc_id": "core:npc/hallam_ashdown", "detection": 1.0, "line_of_sight": true,
								 "place_id": "core:place/merrowby", "reaction": "report", "is_guard": false}]})
	# Witnesses take a while to find a Warden; the bounty lands when they do.
	WorldClock.advance_hours(3.0)
	if crime.has_method("process_pending"):
		crime.process_pending()
	await get_tree().process_frame
	await get_tree().process_frame
	var after: int = crime.bounty(law) if crime.has_method("bounty") else 0
	var wanted: bool = after > before
	# The consequence: you can pay it off, and then you are not wanted.
	var paid := false
	if wanted and inventory and inventory.has_method("add_marks"):
		inventory.add_marks(after * 3)
		if crime.has_method("pay_bounty"):
			paid = bool(crime.pay_bounty(law, player))
	await get_tree().process_frame
	var cleared: bool = (crime.bounty(law) if crime.has_method("bounty") else 0) == 0
	var why: Array[String] = []
	if not wanted:
		why.append("the theft raised no bounty (law %s)" % law)
	if wanted and not paid:
		why.append("could not pay the %d fine" % after)
	if wanted and paid and not cleared:
		why.append("paying did not clear it")
	_record("commit a crime and face the consequences", wanted and paid and cleared,
		"theft raised the bounty to %d, paying it cleared it" % after if why.is_empty() else ", ".join(why))


# 9 ------------------------------------------------------------------------------------
func _step_buy_a_house() -> void:
	var property := get_tree().get_first_node_in_group("property")
	if property == null:
		_record("buy a house", false, "no property node")
		return
	var deeds := ContentDB.where("item", "category", "deed")
	if deeds.is_empty():
		for d in ContentDB.all("item"):
			if d.has("property"):
				deeds.append(d)
	if deeds.is_empty():
		_record("buy a house", false, "no deeds in the pack")
		return
	var deed: Dictionary = deeds[0]
	var price: int = int((deed.get("property", {}) as Dictionary).get("price", deed.get("value", 500)))
	if inventory and inventory.has_method("add_marks"):
		inventory.add_marks(price + 100)
	var bought := false
	var why := ""
	if property.has_method("buy"):
		var result: Dictionary = property.buy(player, str(deed["id"]))
		bought = bool(result.get("ok", false))
		why = str(result.get("reason", ""))
	await get_tree().process_frame
	var owns: bool = property.owns(str(deed["id"])) if property.has_method("owns") else bought
	if not bought and why != "":
		_record("buy a house", false, "%s refused: %s" % [deed["name"], why])
		return
	_record("buy a house", bought and owns, "%s for %d marks" % [deed["name"], price])


# 10 -----------------------------------------------------------------------------------
func _step_clear_a_dungeon() -> void:
	var deep: Array = []
	for d in ContentDB.all("interior"):
		if d.has("formed_by"):
			deep.append(d)
	if deep.is_empty():
		_record("clear a dungeon", false, "no deep places")
		return
	var def: Dictionary = deep[0]
	var meta_path := str(def.get("meta", ""))
	if not FileAccess.file_exists(meta_path):
		_record("clear a dungeon", false, "meta missing for %s" % def["id"])
		return
	var cave := CaveInterior.new()
	cave.build_on_ready = false
	cave.spawn_encounters = true
	host.add_child(cave)
	var built: bool = cave.build(meta_path)
	await get_tree().process_frame
	var spawns := 0
	for m in get_tree().get_nodes_in_group("enemy_spawn"):
		if cave.is_ancestor_of(m):
			spawns += 1
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	var has_shortcut: bool = meta.get("shortcut") != null
	var hearths := 0
	for n in cave.find_children("*", "StaticBody3D", true, false):
		if n.is_in_group("hearthstone"):
			hearths += 1
	_record("clear a dungeon", built and spawns > 0 and has_shortcut and hearths > 0,
		"%s: %d chambers, %d encounter spawns, %d Hearthstone, a shortcut back" % [
			def["name"], cave.chambers.size(), spawns, hearths])
	cave.queue_free()
	await get_tree().process_frame


# 11 -----------------------------------------------------------------------------------
func _step_fight_a_boss() -> void:
	var bosses := ContentDB.all("boss")
	if bosses.is_empty():
		_record("fight a boss", false, "no bosses in the pack")
		return
	var def: Dictionary = bosses[0]
	var phases: Array = def.get("phases", [])
	if phases.is_empty():
		_record("fight a boss", false, "%s has no phases" % def["id"])
		return
	if not ResourceLoader.exists("res://actors/enemy/enemy.tscn"):
		_record("fight a boss", false, "no enemy scene")
		return
	var heard := {"started": false, "defeated": false}
	EventBus.boss_started.connect(func(_id: String) -> void: heard["started"] = true, CONNECT_ONE_SHOT)
	EventBus.boss_defeated.connect(func(_id: String) -> void: heard["defeated"] = true, CONNECT_ONE_SHOT)
	var boss := (load("res://actors/enemy/enemy.tscn") as PackedScene).instantiate()
	# Configure before it enters the tree, as the spawner hook documents: a def read after
	# _ready leaves the actor on default health.
	boss.configure(str(def["id"]))
	host.add_child(boss)
	(boss as Node3D).global_position = Vector3(0, 1, -6)
	await get_tree().process_frame
	boss.start_boss()
	await get_tree().process_frame
	# Take it through every phase threshold to the end.
	var hp: float = boss.get("max_health")
	for i in 60:
		boss.take_hit(_hit(maxf(hp * 0.06, 8.0), 0.0))
		await get_tree().process_frame
		if float(boss.get("health")) <= 0.0:
			break
	await get_tree().process_frame
	await get_tree().process_frame
	var dead: bool = float(boss.get("health")) <= 0.0
	var trouble: Array[String] = []
	if not dead:
		trouble.append("health stuck at %.1f of %.1f" % [float(boss.get("health")), hp])
	if not bool(heard["started"]):
		trouble.append("no boss_started signal")
	if not bool(heard["defeated"]):
		trouble.append("no boss_defeated signal")
	_record("fight a boss", dead and bool(heard["started"]) and bool(heard["defeated"]),
		"%s: %d phases, started and defeated" % [def["name"], phases.size()] if trouble.is_empty() else ", ".join(trouble))
	if is_instance_valid(boss):
		boss.queue_free()
	await get_tree().process_frame


# 11b ----------------------------------------------------------------------------------
## Making something, at the thing you walked up to. `station_screen.tscn` drew all three
## working screens, `UI.MENUS` had "crafting" registered from the start, and nothing in the
## game ever opened it, because there was no forge, no still and no bench in eight kilometres
## of country that a player could reach. So this step refuses to call `craft()` directly: it
## builds Hallam's forge the way the game builds it, finds the anvil in the room, works at it
## the way a player's interaction ray does, and only then makes a sword out of what is in the
## bag — and checks the iron left the bag and the sword arrived in it.
func _step_make_something() -> void:
	const SMITHY := "core:interior/hallam_forge"
	const RECIPE := "core:recipe/iron_sword"
	var name := "make something at a forge you walked up to"
	var crafting: Node = get_tree().get_first_node_in_group("crafting")
	if crafting == null or inventory == null:
		_record(name, false, "no crafting node or no bag")
		return
	var def := ContentDB.get_or_empty(SMITHY)
	var meta_path := str(def.get("meta", ""))
	if meta_path.is_empty() or not FileAccess.file_exists(meta_path):
		_record(name, false, "%s has no built interior (run ./run.sh interiors)" % SMITHY)
		return

	# The smithy, built from its own meta, the way the smoke run and the door both build it.
	var room := HouseInterior.new()
	room.build_on_ready = false
	host.add_child(room)
	var built: bool = room.build(meta_path)
	await get_tree().process_frame
	var anvil: Node = null
	for node in room.find_children("*", "CraftingStation", true, false):
		if str(node.get("station")) == "forge":
			anvil = node
			break

	# Working at it: the event the prop emits, and the screen the UI opens off it.
	var heard: Array[String] = []
	var listen := func(station: String, _node: Node) -> void: heard.append(station)
	EventBus.crafting_station_used.connect(listen)
	if anvil != null:
		anvil.call("interact", player)
	await get_tree().process_frame
	EventBus.crafting_station_used.disconnect(listen)
	var screen_open: bool = UI.is_menu_open("crafting")
	UI.close_all()
	await get_tree().process_frame

	# A recipe against the real bag: the iron goes in, the sword comes out.
	var recipe := ContentDB.get_or_empty(RECIPE)
	var made := false
	var consumed := false
	var output_id := str((recipe.get("output", {}) as Dictionary).get("item", ""))
	var had: int = int(inventory.count(output_id)) if output_id != "" else 0
	var iron_before := 0
	var iron_id := ""
	for entry in recipe.get("inputs", []):
		var row: Dictionary = entry
		var item := str(row.get("item", ""))
		var need := int(row.get("count", 1))
		inventory.add(item, need)
		if iron_id == "":
			iron_id = item
			iron_before = int(inventory.count(item))
	if crafting.has_method("craft"):
		made = bool(crafting.call("craft", RECIPE))
	await get_tree().process_frame
	if iron_id != "":
		consumed = int(inventory.count(iron_id)) < iron_before
	var arrived: bool = output_id != "" and int(inventory.count(output_id)) > had

	var trouble: Array[String] = []
	if not built:
		trouble.append("the smithy would not build")
	if anvil == null:
		trouble.append("no anvil in Hallam's forge to walk up to")
	if heard.is_empty():
		trouble.append("working at the anvil told the UI nothing")
	if not screen_open:
		trouble.append("the working screen never opened")
	if not made:
		trouble.append("the forge refused %s" % RECIPE)
	if not consumed:
		trouble.append("the iron never left the bag")
	if not arrived:
		trouble.append("nothing arrived in the bag")
	_record(name, trouble.is_empty(),
		"%s at the anvil in Hallam's forge, out of %d rooms" % [
			str(recipe.get("name", RECIPE)), room.rooms.size()] if trouble.is_empty() else ", ".join(trouble))
	room.queue_free()
	await get_tree().process_frame


# 12 -----------------------------------------------------------------------------------
## The whole of magic in one pass: a saying you have not been taught is not castable, a tome
## teaches it, the screen's Ready it puts it in the slot, and the cast key lands it on something.
func _step_learn_and_say() -> void:
	const SAYING := "core:spell/kindle_bolt"
	const TOME := "core:item/tome_kindle_bolt"
	if player == null or progression == null or inventory == null:
		_record("learn a saying and Say it", false, "no player, bag or progression")
		return
	if not ResourceLoader.exists("res://actors/enemy/enemy.tscn") or not ContentDB.has(TOME):
		_record("learn a saying and Say it", false, "no enemy scene or no tome in the pack")
		return

	# 1. untaught is uncastable, however the id gets into the slot
	var refused_before: bool = not bool(player.equip_spell(SAYING))
	var knew_nothing: bool = not bool(progression.knows_spell(SAYING))

	# 2. taught by a tome, read out of the bag the way the inventory screen reads one
	inventory.add(TOME, 1)
	inventory.use(TOME)
	await get_tree().process_frame
	var learned: bool = progression.knows_spell(SAYING)
	var kept_the_book: bool = inventory.count(TOME) == 1
	# a tome is a book: reading one opens the reader over the world, and the player shuts it
	var opened_the_book: bool = UI.is_menu_open("book")
	UI.close_all()
	await get_tree().process_frame

	# 3. readied: this is what the sayings screen's Ready it does
	var readied: bool = bool(player.equip_spell(SAYING)) and str(player.equipped_spell) == SAYING

	# 4. Said at something, through the cast key, and landing like any other hit
	player.global_position = Vector3(0, 1.0, 0)
	player.rotation.y = 0.0
	player.camera_rig.yaw = 0.0
	var mark := (load("res://actors/enemy/enemy.tscn") as PackedScene).instantiate()
	mark.configure("core:enemy/ash_wight")
	host.add_child(mark)
	(mark as Node3D).global_position = player.global_position + Vector3(0, 0, -4.0)
	await get_tree().physics_frame
	player.lock.acquire(player.global_position, -player.global_transform.basis.z)
	var locked: bool = player.lock.is_locked()
	var before: float = float(mark.get("health"))
	var mana_before: float = float(player.get("mana"))
	var mana_low := mana_before

	Input.action_press("cast")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("cast")
	var landed := false
	for i in 300:
		await get_tree().physics_frame
		mana_low = minf(mana_low, float(player.get("mana")))
		if float(mark.get("health")) < before:
			landed = true
			break
	# breath comes back as you stand there, so what matters is that it was spent at all
	var spent: bool = mana_low < mana_before
	var damage: float = before - float(mark.get("health"))
	if is_instance_valid(mark):
		mark.queue_free()
	player.lock.clear()
	await get_tree().process_frame

	var trouble: Array[String] = []
	if not (refused_before and knew_nothing):
		trouble.append("a saying nobody taught was readied anyway")
	if not learned:
		trouble.append("the tome taught nothing")
	if not kept_the_book:
		trouble.append("reading the tome consumed it")
	if not opened_the_book:
		trouble.append("the tome did not open the reader")
	if not readied:
		trouble.append("could not ready it")
	if not locked:
		trouble.append("could not lock on")
	if not spent:
		trouble.append("the cast cost no breath")
	if not landed:
		trouble.append("the bolt never landed")
	_record("learn a saying, ready it and Say it", trouble.is_empty(),
		"read a tome, readied %s, cast it for %.1f damage" % [
			str(ContentDB.get_or_empty(SAYING).get("name", SAYING)), damage] if trouble.is_empty() else ", ".join(trouble))


# 13 -----------------------------------------------------------------------------------
func _step_save_and_load() -> void:
	GameState.set_flag("journey_marker", "kept")
	WorldClock.set_time(17.25, 9)
	if inventory and inventory.has_method("add_marks"):
		inventory.add_marks(333)
	var marks_before: int = int(inventory.get("marks")) if inventory else 0
	var saying_before: String = str(player.equipped_spell) if player else ""
	var saved := SaveSystem.save_to_slot("journey") == OK
	GameState.set_flag("journey_marker", "lost")
	WorldClock.set_time(3.0, 1)
	if inventory and inventory.has_method("remove_marks"):
		inventory.remove_marks(marks_before)
	if player:
		player.equip_spell("")
	if progression:
		progression.forget_spell(saying_before)
	var loaded := SaveSystem.load_from_slot("journey") == OK
	await get_tree().process_frame
	await get_tree().process_frame
	var flag_back: bool = str(GameState.get_flag("journey_marker", "")) == "kept"
	var clock_back: bool = WorldClock.day == 9 and absf(WorldClock.time_hours - 17.25) < 0.01
	var marks_back: bool = int(inventory.get("marks")) == marks_before if inventory else true
	var saying_back: bool = saying_before == "" or (
		progression.knows_spell(saying_before) and str(player.equipped_spell) == saying_before)
	SaveSystem.delete_slot("journey")
	var parts: Array[String] = []
	if not saved:
		parts.append("save refused")
	if not loaded:
		parts.append("load refused")
	if not flag_back:
		parts.append("flag lost")
	if not clock_back:
		parts.append("clock lost (day %d, %.2f)" % [WorldClock.day, WorldClock.time_hours])
	if not marks_back:
		parts.append("marks lost (%d of %d)" % [int(inventory.get("marks")) if inventory else 0, marks_before])
	if not saying_back:
		parts.append("the readied saying did not come back (%s)" % saying_before)
	_record("save and load", saved and loaded and flag_back and clock_back and marks_back and saying_back,
		"flags, clock, %d marks and the readied saying survived" % marks_before if parts.is_empty() else ", ".join(parts))


func _report() -> void:
	var passed := 0
	var skipped := 0
	for s in steps:
		if s.skipped:
			skipped += 1
		elif s.ok:
			passed += 1
	var total := steps.size() - skipped
	var errors := Log.error_count - _errors_at_start
	print("")
	print("JOURNEY: === %d of %d steps pass, %d skipped, %d logged errors ===" % [passed, total, skipped, errors])
	for s in steps:
		if not s.ok and not s.skipped:
			print("JOURNEY:   still broken: %s (%s)" % [s.name, s.detail])
	var ok := passed == total
	print("JOURNEY: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
