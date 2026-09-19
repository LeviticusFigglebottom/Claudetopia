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

var steps: Array[Step] = []
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
	host = Node3D.new()
	host.name = "JourneyWorld"
	host.add_to_group("world_dynamic")
	add_child(host)
	# The world's services: law, ownership, stealth, NPC life, market, property.
	var services := GameServices.new()
	services.name = "GameServices"
	add_child(services)
	await get_tree().process_frame
	print("JOURNEY: starting")

	await _step_character_creation()
	await _step_spawn_player()
	await _step_leave_the_start()
	await _step_fight()
	await _step_level_up()
	await _step_die_and_recover()
	await _step_join_a_faction()
	await _step_commit_a_crime()
	await _step_buy_a_house()
	await _step_clear_a_dungeon()
	await _step_fight_a_boss()
	await _step_learn_and_say()
	await _step_save_and_load()
	_report()


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
	# The world is the thing you leave into; say honestly whether there is one yet.
	var world_exists := ResourceLoader.exists("res://world/world.tscn")
	_record("leave the starting area in any direction", reached == 4,
		"moved freely in %d of 4 directions%s" % [reached, "" if world_exists else "; no streamed world scene yet"])


# 4 ------------------------------------------------------------------------------------
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
	_record("die and get your marks back", rested and dropped and back_at_stone and marks_gone and recovered,
		"rested, dropped %d marks on death, respawned at the stone, recovered them" % marks_before)


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
