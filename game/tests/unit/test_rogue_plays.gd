extends TestCase
## The Rogue's night at Moreva played as a player plays it (triage 44: "the first quest didn't make
## sense, and is it possible? The stealth."): the real body on the built world, moved only by its
## keys (crouch, the move keys under a turned view, interact, the light blow) along a simple
## scripted way, with the night-watch's own eyes, the HUD's own read and the quest's own acts. The
## other rogue tests emit the acts or stand the body where it needs to be; this one has to get
## there.
##
## What it plays, and what each part proves:
## - the straight way down to the traps, crouched: Tella Oul notices, then sees; the read says
##   Noticed before it says Seen; back in the lane's shelter the watch comes round again;
## - the lane down the way's east side, behind the stacks and the boat: never Seen, to Sauve, who
##   is talked to (crouched at his back, the key talks, it does not pick his pocket);
## - the strongbox picked on the lockpick screen by the interact key as the needle crosses, the
##   tithe-book taken; the sleeping collector's pocket offered crouched;
## - round to the sack's back and one light blow: a sneak attack;
## - the bravo on his round in the fog, stalked crouched and struck once from behind;
## - the book to Sauve: Tally, the page, and the courier.

const FIRST := "core:quest/first_rogue"
const PAGE := "core:quest/the_unsaid_page"
const SAUVE := "core:npc/sauve_mor"
const TELLA := "core:npc/tella_oul"
const TOLE := "core:npc/tithe_collector"
const BRAVO := "core:enemy/tithe_bravo"
const HUD := preload("res://ui/hud/hud.gd")
const KEYS: Array[String] = ["move_forward", "move_back", "move_left", "move_right", "sprint", "walk", "sneak", "interact", "attack_light"]
const TICK := 1.0 / 60.0

var player: Player = null
var world: World = null
## What the watch and the read did on the last walk: the highest level, whether the read said
## Noticed, and when (seconds into the walk) it first said Noticed and Seen.
var walk_most := 0.0
var walk_noticed_at := -1.0
var walk_seen_at := -1.0


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	for a in KEYS:
		if InputMap.has_action(a):
			Input.action_release(a)
	UI.close_all()
	WorldContainer.store.clear()
	Pickpocketing.store.clear()
	if world != null and is_instance_valid(world):
		_tree().root.remove_child(world)
		world.queue_free()
	world = null
	player = null
	Social.quests.call("reset_for_new_game")
	GameState.reset_for_new_game(53)


func _ticks(n: int) -> void:
	for i in n:
		await _tree().physics_frame


func _until(pred: Callable, seconds: float) -> bool:
	for i in int(seconds / TICK):
		if bool(pred.call()):
			return true
		await _tree().physics_frame
	return bool(pred.call())


func _tap(action: String) -> void:
	Input.action_press(action)
	await _ticks(3)
	Input.action_release(action)
	await _ticks(2)


## A key pressed as a screen hears it (the lockpick screen reads _unhandled_input).
func _tap_event(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _ticks(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _ticks(2)


static func _bearing(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _look_at(p: Vector3) -> void:
	player.camera_rig.yaw = -deg_to_rad(_bearing(player.global_position, p))


func _tella() -> Npc:
	return NpcRegistry.instance.actor(TELLA) as Npc


func _stage() -> String:
	return str(Social.quests.call("stage_id_of", FIRST))


func _crouched() -> void:
	if not player.is_sneaking:
		await _tap("sneak")
	assert_true(player.is_sneaking, "crouched on the key")


## Walks the body along `way` (world points) with the move key held under a view turned to each
## point in turn, crouched as it is. Stops early when `stop` says so. Records the watch and the
## HUD's read on the way (walk_most, walk_noticed_at, walk_seen_at). True when it got to the end.
func _walk(way: Array, seconds: float, stop: Callable = Callable(), reach := 0.8) -> bool:
	walk_most = 0.0
	walk_noticed_at = -1.0
	walk_seen_at = -1.0
	var i := 0
	var t := 0.0
	var stuck_at := player.global_position
	var stuck_t := 0.0
	var rounds: Array = []
	var detours := 0
	way = way.duplicate()
	while t < seconds:
		if stop.is_valid() and bool(stop.call()):
			Input.action_release("move_forward")
			return false
		if i >= way.size():
			break
		var to: Vector3 = way[i]
		if _flat(player.global_position, to) < reach:
			i += 1
			continue
		# round whatever stands in the way, as a player would
		if detours < 12 and not (to in rounds):
			var round_it := _detour(player.global_position, to)
			if round_it != Vector3.INF and _flat(player.global_position, round_it) > reach:
				way.insert(i, round_it)
				rounds.append(round_it)
				detours += 1
				continue
		_look_at(to)
		Input.action_press("move_forward")
		await _tree().physics_frame
		t += TICK
		var tella := _tella()
		if tella != null:
			walk_most = maxf(walk_most, tella.detection)
		var read := HUD.eye_state(HUD.watched_level(_tree(), player.global_position))
		if read == "suspicious" and walk_noticed_at < 0.0:
			walk_noticed_at = t
		if read in ["alert", "detected"] and walk_seen_at < 0.0:
			walk_seen_at = t
		stuck_t += TICK
		if stuck_t > 4.0:
			if _flat(player.global_position, stuck_at) < 0.5:
				print("PLAY stuck at %s on the way to %s (talking %s, menu %s, input %s)" % [player.global_position.snapped(Vector3.ONE * 0.1), to.snapped(Vector3.ONE * 0.1), str(Social.dialogue.call("is_running")), UI.top_menu(), str(player.input_enabled)])
				break
			stuck_at = player.global_position
			stuck_t = 0.0
	Input.action_release("move_forward")
	await _ticks(6)
	return i >= way.size()


## A point round the first solid thing between `from` and `to` at knee height, or Vector3.INF when
## the way is clear: past the nearer end of a stack or a boat, or a step to the side of anything else.
func _detour(from: Vector3, to: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var a := from + Vector3.UP * 0.5
	var b := Vector3(to.x, from.y, to.z) + Vector3.UP * 0.5
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, player.collision_mask, [player.get_rid()]))
	if hit.is_empty() or (hit["position"] as Vector3).distance_to(a) > a.distance_to(b) - 0.3:
		return Vector3.INF
	var c: Object = hit["collider"]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var picks: Array[Vector3] = []
	if c is QuestCover:
		var q := c as QuestCover
		var axis := q.global_transform.basis.x.normalized()
		var half := q.size().x * 0.5 + 1.0
		var across := q.global_transform.basis.z.normalized() * (q.size().z * 0.5 + 0.6)
		for e in [q.global_position + axis * half, q.global_position - axis * half]:
			# the end, on the near side of it
			var side := across if across.dot(from - q.global_position) > 0.0 else -across
			picks.append((e as Vector3) + side)
	else:
		var n := Vector3(-dir.z, 0.0, dir.x)
		var at := hit["position"] as Vector3
		picks.append(at + n * 1.8 - dir * 0.6)
		picks.append(at - n * 1.8 - dir * 0.6)
	var best := Vector3.INF
	for p in picks:
		if best == Vector3.INF or _flat(from, p) + _flat(p, to) < _flat(from, best) + _flat(best, to):
			best = p
	return _at_xz(best.x, best.z)


func _at_xz(x: float, z: float) -> Vector3:
	return Vector3(x, WorldProbe.get_height(x, z, player.global_position.y), z)


## Stands `d` metres from `thing` on its compass bearing `side`, turned to it.
func _beside(thing: Vector3, side: float, d: float) -> Vector3:
	var b := deg_to_rad(side)
	return _at_xz(thing.x + sin(b) * d, thing.z - cos(b) * d)


func _talk_and_choose(npc_id: String, choice_starts: String) -> bool:
	var who := NpcRegistry.instance.actor(npc_id) as Node3D
	_look_at(who.global_position)
	await _ticks(8)
	var prompt := player.interactor._prompt_for(player.interactor.target) if player.interactor.target != null else ""
	print("PLAY prompt at %s: %s" % [npc_id, prompt])
	assert_true(prompt.contains("Talk to"), "at %s the key talks: '%s'" % [npc_id, prompt])
	await _tap("interact")
	var running := await _until(func() -> bool: return bool(Social.dialogue.call("is_running")), 3.0)
	assert_true(running, "the conversation begins")
	for step in 12:
		if not bool(Social.dialogue.call("is_running")):
			break
		var choices: Array = Social.dialogue.get("current_choices")
		var picked := -1
		for k in choices.size():
			if str((choices[k] as Dictionary).get("text", "")).begins_with(choice_starts):
				picked = k
		if picked >= 0:
			Social.dialogue.call("choose", picked)
			await _ticks(2)
			Social.dialogue.call("stop")
			await _ticks(4)
			return true
		if choices.is_empty():
			Social.dialogue.call("advance")
		else:
			print("PLAY choices: %s" % str(choices.map(func(c: Dictionary) -> String: return str(c.get("text", "")))))
			break
		await _ticks(2)
	Social.dialogue.call("stop")
	await _ticks(4)
	return false


func test_the_rogue_s_night_is_played_through_with_the_keys() -> void:
	if not FileAccess.file_exists("res://world/generated/world_manifest.json"):
		skip("no built world")
		return
	# a new game: nothing another test left open or kept (a page, a menu, a box's state, a pocket)
	UI.close_all()
	if bool(Social.dialogue.call("is_running")):
		Social.dialogue.call("stop")
	WorldContainer.store.clear()
	Pickpocketing.store.clear()
	GameState.reset_for_new_game(53)
	Social.quests.call("reset_for_new_game")
	GameState.set_flag(StyleDef.FLAG, "core:style/rogue")
	GameState.set_flag(Openings.STYLE_START, true)
	GameState.set_flag(Openings.STYLE_DUE, true)
	GameState.set_flag("player_name", "Hesk of the Delta")
	GameState.set_flag("player_calling", "core:calling/lantern_clerk")
	# the film hands over at 05:24 in mist
	WorldClock.set_time(5.4)
	world = (load("res://world/world.tscn") as PackedScene).instantiate() as World
	_tree().root.add_child(world)
	await world.world_ready
	assert_true(await _until(func() -> bool: return bool(Social.quests.call("is_active", FIRST)), 15.0), "the night begins")
	player = world.get_node("PlayerSpawn").get("player") as Player
	var spots := QuestSpots.ensure()
	var post := spots.position_of("tella_boards")
	var at_post := await _until(func() -> bool:
			var t := _tella()
			return t != null and _flat(t.global_position, post) < 3.0, 30.0)
	assert_true(at_post, "the watch at her post")
	await _ticks(90)
	var tella := _tella()
	var ff := tella.facing_flat()
	var look := fposmod(rad_to_deg(atan2(ff.x, -ff.z)), 360.0)
	print("PLAY %02d:%02d, sun %.0f deg, light %.3f, sight x%.2f; Tella looks %.0f (sees %.1f m, keen %.1f), lantern %s" % [
			int(WorldClock.time_hours), int(fposmod(WorldClock.time_hours, 1.0) * 60.0), WorldClock.sun_elevation_deg(),
			Stealth.instance.player_light(), Stealth.weather_sight(), look, tella.seeing_range(), tella.keen,
			str(tella.get_node_or_null("WatchLantern") != null)])
	assert_true(absf(angle_difference(deg_to_rad(look), deg_to_rad(150.0))) < deg_to_rad(25.0), "she looks down the way (%.0f)" % look)
	assert_true(tella.get_node_or_null("WatchLantern") != null, "with her lantern")
	# the start is behind her, and the HUD's eye reads her, not the teacher at your shoulder
	await _crouched()
	assert_true(bool(Social.quests.call("objective_done", FIRST, 0)), "crouched: the first lesson")
	await _ticks(30)
	var read := HUD.eye_state(HUD.watched_level(_tree(), player.global_position))
	assert_eq(read, "unaware", "crouched at the start, with Sauve a few paces off: Unseen")
	var sauve := NpcRegistry.instance.actor(SAUVE) as Npc
	assert_true(sauve.is_with_you(), "Sauve is with you")

	# 1. the straight way down, crouched, past her lantern: noticed, then seen, and back
	var traps := spots.position_of("sauve_traps")
	var start := player.global_position
	var seen_flag := func() -> bool: return GameState.has_flag("seen_on_the_boards")
	await _walk([traps], 40.0, seen_flag)
	print("PLAY straight down: noticed %.1f s, seen %.1f s, at %.1f m from her, flag %s" % [walk_noticed_at, walk_seen_at, _flat(player.global_position, tella.global_position), str(GameState.has_flag("seen_on_the_boards"))])
	assert_true(GameState.has_flag("seen_on_the_boards"), "the straight way down in front of her lantern is seen")
	assert_true(walk_noticed_at >= 0.0 and walk_seen_at > walk_noticed_at + 1.0, "and the read said Noticed a while before Seen (%.1f, %.1f)" % [walk_noticed_at, walk_seen_at])
	var back := NightWatch.nearest_back(NightWatch.ensure().spec(), Vector2(player.global_position.x, player.global_position.z))
	var back_at := _at_xz(back.x, back.y)
	print("PLAY seen: back %.1f m to the shelter (the start is %.1f m)" % [_flat(player.global_position, back_at), _flat(player.global_position, start)])
	assert_true(_flat(player.global_position, back_at) < _flat(player.global_position, start), "the shelter is nearer than the start")
	await _walk([_at_xz(back.x + 1.0, back.y + 0.5), back_at], 30.0)
	for k in 12:
		if not GameState.has_flag("seen_on_the_boards"):
			break
		var eye_ray := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(tella.eye_position(), Stealth.sight_point(player), 1 | (1 << 10), [tella.get_rid()]))
		print("PLAY waiting in the shelter at %s: %.1f m from it, her level %.2f, she sees me %s, %.1f m from her at %s, the ray stops on %s" % [player.global_position.snapped(Vector3.ONE * 0.1), _flat(player.global_position, back_at), tella.detection, str(tella.can_see(player)), _flat(player.global_position, tella.global_position), tella.global_position.snapped(Vector3.ONE * 0.1), str(eye_ray.get("collider", "nothing"))])
		await _ticks(60)
	var again := not GameState.has_flag("seen_on_the_boards")
	assert_true(again, "back in the shelter, and she looks at the water again")

	# 2. the lane: behind the stacks and the boat, down the way's east side
	# down the east side of the stacks, a pace off them (the way a player keeps them between)
	var way: Array = []
	for xz in [Vector2(-2786.2, -955.0), Vector2(-2786.4, -950.0), Vector2(-2786.4, -946.0), Vector2(-2786.4, -942.0),
			Vector2(-2786.6, -938.0), Vector2(-2787.5, -934.0), Vector2(-2789.0, -930.5)]:
		way.append(_at_xz(xz.x, xz.y))
	way.append(_at_xz(traps.x + 1.5, traps.z - 1.2))
	var got_down := await _walk(way, 60.0, seen_flag)
	print("PLAY the lane: got down %s, Tella's most %.2f, read noticed at %.1f, seen at %.1f, flag %s" % [str(got_down), walk_most, walk_noticed_at, walk_seen_at, str(GameState.has_flag("seen_on_the_boards"))])
	assert_true(got_down, "down the lane to the traps")
	assert_false(GameState.has_flag("seen_on_the_boards"), "unseen")
	assert_true(walk_most < DetectionMeter.WITNESS, "the watch never sure (%.2f)" % walk_most)
	var sauve_there := await _until(func() -> bool: return _flat(sauve.global_position, traps) < 2.5, 30.0)
	assert_true(sauve_there, "Sauve at his traps")
	await _walk([_beside(sauve.global_position, _bearing(sauve.global_position, player.global_position), 1.6)], 10.0)
	assert_true(player.is_sneaking, "still crouched")
	assert_true(await _talk_and_choose(SAUVE, "Down, and she never saw me"), "told Sauve")
	assert_false(bool(Social.dialogue.call("is_running")), "and the talk is over")
	assert_eq(UI.top_menu(), "", "with nothing left up")
	assert_eq(_stage(), "the_strongbox", "the traps are done")

	# 3. back up to the strongbox: the lock on the screen, the book out, the collector's pocket
	var box := spots.props["tithe_strongbox"] as WorldContainer
	var face := -box.global_transform.basis.z
	var box_side := fposmod(rad_to_deg(atan2(face.x, -face.z)), 360.0)
	var stand := _beside(box.global_position, box_side, 1.25)
	var up_way: Array = [way[5], way[4], way[3], way[2], way[1], way[0], _at_xz(stand.x + 2.5, stand.z - 2.0), stand]
	await _walk(up_way, 90.0)
	_look_at(box.global_position)
	await _ticks(10)
	print("PLAY at the box: %.1f m, the key offers '%s'" % [_flat(player.global_position, box.global_position), player.interactor._prompt_for(player.interactor.target) if player.interactor.target != null else ""])
	await _tap("interact")
	var screen_up := await _until(func() -> bool: return UI.is_menu_open("lockpick"), 3.0)
	if not screen_up:
		print("PLAY no lockpick screen: menu '%s', talking %s, input %s, target %s, %.1f m from the box, locked %s" % [UI.top_menu(), str(Social.dialogue.call("is_running")), str(player.input_enabled), str(player.interactor.target), _flat(player.global_position, box.global_position), str(box.locked)])
	assert_true(screen_up, "the lockpick screen")
	var tries := 0
	while box.locked and tries < 8 and UI.is_menu_open("lockpick"):
		var screen := UI.menu_node("lockpick")
		await _until(func() -> bool: return float(screen.call("miss")) < 0.05, 5.0)
		await _tap_event("interact")
		tries += 1
		await _ticks(10)
	print("PLAY the lock: %d tries, locked %s" % [tries, str(box.locked)])
	assert_false(box.locked, "picked with the key as the needle crossed")
	assert_true(await _until(func() -> bool: return UI.is_menu_open("container"), 3.0), "and it opens")
	box.take_all(player)
	UI.close_all()
	await _ticks(10)
	assert_true((player.get_node("Inventory") as Inventory).count("core:item/tithe_book") == 1, "the tithe-book in the bag")
	var tole := NpcRegistry.instance.actor(TOLE) as Npc
	assert_true(tole != null, "the collector asleep by his box")
	if tole != null:
		var tf := tole.facing_flat()
		var his_back := fposmod(rad_to_deg(atan2(tf.x, -tf.z)) + 180.0, 360.0)
		await _walk([_beside(tole.global_position, his_back, 1.0)], 15.0)
		_look_at(tole.global_position)
		await _ticks(10)
		var offer := player.interactor._prompt_for(player.interactor.target) if player.interactor.target != null else ""
		print("PLAY at the collector's back: '%s'" % offer)
		assert_true(offer.contains("Pick"), "crouched at a sleeper's back, the key picks his pocket: '%s'" % offer)
	# the strongbox lesson closes on the lock and the book; the pocket is the lesson's own choice
	var dagger := await _until(func() -> bool: return _stage() == "the_dagger", 5.0)
	assert_true(dagger, "the strongbox done: %s" % _stage())

	# 4. the sack, from behind
	var sack := spots.props["eel_sack"] as Node3D
	var sf := -sack.global_transform.basis.z
	var sack_back := fposmod(rad_to_deg(atan2(sf.x, -sf.z)) + 180.0, 360.0)
	await _walk([_beside(sack.global_position, sack_back + 40.0, 3.0), _beside(sack.global_position, sack_back, 1.2)], 60.0)
	_look_at(sack.global_position)
	await _ticks(10)
	await _tap("attack_light")
	await _ticks(60)
	print("PLAY the sack: stage %s" % _stage())
	assert_eq(_stage(), "the_bravo", "one blow from behind")

	# 5. the bravo, in the fog, on his round: followed crouched, struck once from behind
	var find_bravo := func() -> Enemy:
		for e in _tree().get_nodes_in_group("enemy"):
			if (e as Enemy).content_id() == BRAVO and not (e as Enemy).dead:
				return e as Enemy
		return null
	var stood := await _until(func() -> bool: return find_bravo.call() != null, 30.0)
	var bravo: Enemy = find_bravo.call()
	assert_true(stood, "the bravo on his round")
	var most := 0.0
	var struck := false
	var after_first := -1.0
	var lowest := player.health
	var t := 0.0
	while bravo != null and is_instance_valid(bravo) and not bravo.dead and t < 120.0:
		var bf := -bravo.global_transform.basis.z
		var behind := bravo.global_position - Vector3(bf.x, 0.0, bf.z).normalized() * 1.3
		var d := _flat(player.global_position, bravo.global_position)
		if player._backstab_candidate() == bravo and d < 2.0 and player.state == Player.State.FREE:
			Input.action_release("move_forward")
			_look_at(bravo.global_position)
			print("PLAY strike at %.1f m, his detection %.2f, his health %.0f" % [d, bravo.perception.detection if bravo.perception != null else -1.0, bravo.health])
			Input.action_press("attack_light")
			await _ticks(3)
			Input.action_release("attack_light")
			var kinds := []
			for k in 36:
				await _tree().physics_frame
				if k % 6 == 0:
					kinds.append("%s/%s %.1fm %.0fhp" % [str(player._attack_kind), str(player._attack_phase), _flat(player.global_position, bravo.global_position) if is_instance_valid(bravo) else -1.0, bravo.health if is_instance_valid(bravo) else -1.0])
			print("PLAY after the blow: %s" % str(kinds))
			if not struck:
				after_first = bravo.health if is_instance_valid(bravo) and not bravo.dead else 0.0
			struck = true
			t += 45.0 * TICK
			continue
		_look_at(behind if d > 2.2 else bravo.global_position)
		Input.action_press("move_forward")
		await _tree().physics_frame
		t += TICK
		if bravo.perception != null:
			most = maxf(most, bravo.perception.detection)
		lowest = minf(lowest, player.health)
	Input.action_release("move_forward")
	print("PLAY the bravo: struck %s, dead %s, his most %.2f, %.0f s, stage %s" % [str(struck), str(bravo == null or bravo.dead), most, t, _stage()])
	print("PLAY the first blow left him %.0f of 62; my lowest health %.0f" % [after_first, lowest])
	assert_true(bravo == null or bravo.dead, "the bravo put down")
	assert_true(after_first >= 0.0 and after_first <= 62.0 * 0.2, "the first blow, from behind, ended him or nearly (%.0f left)" % after_first)
	assert_true(lowest > 0.0, "and he never got to fight back to the death")
	assert_eq(_stage(), "report", "and the report")

	# 6. the book to Sauve
	sauve = NpcRegistry.instance.actor(SAUVE) as Npc
	await _walk([_beside(sauve.global_position, _bearing(sauve.global_position, player.global_position), 1.6)], 60.0)
	assert_true(await _talk_and_choose(SAUVE, "The collector's tithe-book"), "the book to Sauve")
	assert_true(bool(Social.quests.call("is_completed", FIRST)), "the night is done")
	var bag := player.get_node("Inventory") as Inventory
	assert_eq(bag.count("core:item/unsaid_page"), 1, "the page folded in the book's back")
	assert_eq(bag.count("core:item/tithe_book"), 0, "and Sauve keeps the book")
	assert_eq(str(Social.quests.call("stage_id_of", PAGE)), "the_courier", "and the courier")
