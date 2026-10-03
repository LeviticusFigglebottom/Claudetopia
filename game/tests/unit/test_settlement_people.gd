extends TestCase
## The people of the settlements. DESIGN §6 promises six settlements with schedules, shops and
## property and sixty-odd people with a personality and a timetable; the pack had forty-three
## defs, eight of them placeholders, and Grandfather Hollow, Brindlecrag and Nauve's Landing had
## nobody whose home they were. These press what a player meets when they walk into a place:
## somebody living there, a shop in every town and village, a schedule that stands each person
## on the ground at their own place at noon, nobody left standing in the street at three in the
## morning, and a greeting and a first line from every one of them when you walk up.

## Kinds of place where people live (Gossip.SETTLED_KINDS, without the deep places).
const LIVED_IN := ["city", "town", "village", "hamlet", "camp", "fort", "lodge", "ruin_village"]
## Kinds that owe the player a shop.
const KEEP_SHOPS := ["city", "town", "village"]
## A body stands within the registry's spread around its place (NpcRegistry.spawn_position
## puts a village across sixty to a hundred metres); anything further is somebody else's place.
const NEAR_PLACE_M := 60.0


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	Peers.overrides.clear()


## Talking sets flags (met:<npc>, whatever a greet node writes); the tests that follow should
## not inherit a day's worth of conversations.
func after_each() -> void:
	if Social.dialogue.is_running():
		Social.dialogue.stop()
	Social.set_place("")
	GameState.reset_for_new_game(1)
	Social.reset_for_new_game()
	Peers.overrides.clear()


# --- who lives where --------------------------------------------------------------------------------

## The named people of the pack: placeholders and guard posts are not residents.
static func _people() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in ContentDB.all("npc"):
		if bool(def.get("example", false)):
			continue
		if (def.get("tags", []) as Array).has("guard"):
			continue
		out.append(def)
	return out


static func _residents_of(place_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in _people():
		if str(def.get("home_place", "")) == place_id:
			out.append(def)
	return out


static func _lived_in_places() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in ContentDB.all("place"):
		if str(p.get("kind", "")) in LIVED_IN:
			out.append(p)
	return out


func test_the_roster_is_the_size_the_design_asks_for() -> void:
	assert_true(_people().size() >= 60,
		"DESIGN §6 asks for sixty NPCs with personality and schedule; the pack has %d named people" % _people().size())
	for def in _people():
		var id := str(def["id"])
		assert_true((def.get("schedule", []) as Array).size() >= 1, "%s has no schedule" % id)
		assert_true((def.get("personality", {}).get("traits", []) as Array).size() >= 3, "%s has no personality" % id)
		assert_true(ContentDB.has(str(def.get("dialogue", ""))), "%s has nothing to say" % id)


func test_every_settled_place_has_people_and_every_town_a_shop() -> void:
	for place in _lived_in_places():
		var id := str(place["id"])
		var residents := _residents_of(id)
		assert_true(residents.size() >= 1, "%s is a %s with nobody living in it" % [id, place["kind"]])
		if not str(place["kind"]) in KEEP_SHOPS:
			continue
		assert_true(residents.size() >= 3, "%s is a %s with only %d people" % [id, place["kind"], residents.size()])
		var shops := 0
		for def in residents:
			if typeof(def.get("merchant")) == TYPE_DICTIONARY:
				shops += 1
		assert_true(shops >= 1, "%s is a %s where nothing is for sale" % [id, place["kind"]])


## DESIGN §6 names six; each has to have somebody living in it.
func test_the_six_promised_settlements_are_lived_in() -> void:
	for id in ["core:place/merrowby", "core:place/tollmere", "core:place/isseva",
			"core:place/grandfather_hollow", "core:place/kharrow_hold", "core:place/pilgrims_ash"]:
		assert_true(_residents_of(id).size() >= 3,
			"%s is promised by DESIGN §6 and has %d people" % [id, _residents_of(id).size()])


# --- the schedules are real -------------------------------------------------------------------

func test_every_schedule_entry_names_a_real_place_and_a_spot() -> void:
	for def in _people():
		var id := str(def["id"])
		var probs := Schedules.problems(def.get("schedule", []), id)
		assert_empty(probs, str(probs))
		for e in def.get("schedule", []):
			var entry: Dictionary = e
			var place := str(entry.get("place", "home"))
			if place != "home":
				assert_true(ContentDB.has(place), "%s is scheduled at %s, which is not a place" % [id, place])
				var pos: Array = ContentDB.get_or_empty(place).get("position", [])
				assert_eq(pos.size(), 2, "%s is scheduled at %s, which has no position on the map" % [id, place])
			assert_ne(str(entry.get("spot", "")), "", "%s has a schedule entry with no spot" % id)


## Bosses and foes with a face of their own are drawn from the same seeds as the people: a boss who
## rolls a villager's seed wears that villager's face (four did: 4521, 7311, 5577, 5520). A foe that
## extends another and keeps its parent's appearance shares its parent's face, and is counted so.
func test_no_two_people_share_a_face_seed() -> void:
	var seen: Dictionary = {}
	var faces: Array[Dictionary] = _people()
	for kind in ["boss", "enemy"]:
		for def in ContentDB.all(kind):
			if not bool(def.get("example", false)):
				faces.append(def)
	for def in faces:
		var face_seed: Variant = (def.get("appearance", {}) as Dictionary).get("seed")
		if face_seed == null:
			continue
		assert_false(seen.has(face_seed), "%s and %s roll the same face (seed %s)" % [def["id"], seen.get(face_seed, "?"), str(face_seed)])
		seen[face_seed] = str(def["id"])


func test_everyone_carries_one_side_of_each_axis() -> void:
	var opposites: Dictionary = Personality.OPPOSITES
	for def in _people():
		var traits: Array = def.get("personality", {}).get("traits", [])
		for t in traits:
			assert_true(Personality.TRAITS.has(str(t)), "%s has a trait no axis knows: %s" % [def["id"], str(t)])
			assert_false(traits.has(opposites.get(str(t), "")),
				"%s is both %s and %s" % [def["id"], str(t), str(opposites.get(str(t), ""))])


# --- in the built world ------------------------------------------------------------------------------

func _world() -> World:
	var w := (load("res://world/world.tscn") as PackedScene).instantiate() as World
	var spawn: Node = w.get_node_or_null("PlayerSpawn")
	if spawn != null:
		spawn.set("enabled", false)
	_tree().root.add_child(w)
	return w


func _drop(w: Node) -> void:
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame


func _anchor(w: World, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = "StandIn"
	node.add_to_group("player")
	w.add_child(node)
	node.global_position = at
	return node


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Noon on a workday (day 2 is Tallowday). Everybody whose schedule has them at home and out of
## doors is stood up there, on the ground, and every one of them, at home or away, asleep or
## awake, has a greeting and a first line when you walk up, the way the journey's step 4 does it.
##
## No place scene names spot markers today, so `Npc._spot_position()` falls through for every
## spot to `NpcRegistry.spawn_position`: the place's position, nudged deterministically per
## person, on the terrain. That fallback is what this pins: a spot never resolves to the origin
## and never to somewhere off its own place. A spot name is a promise about the fiction and not
## yet about the ground, and this is the test that will go red when somebody makes it one badly.
func test_at_noon_everyone_stands_at_home_on_the_ground_with_something_to_say() -> void:
	var w := _world()
	await w.world_ready
	var registry := NpcRegistry.ensure()
	# The world installs its own streamer, which follows the streaming target and would stand
	# the whole village up between two frames; the standing here is done by hand.
	var streamer := NpcStreamer.ensure()
	streamer.enabled = false
	registry.despawn_all()
	WorldClock.set_time(12.0, 2)
	registry.simulate_all("clear")
	var lines: Array = []
	var listen := func(_speaker: String, text: String, _choices: Array) -> void:
		lines.append(text)
	Social.dialogue.line_shown.connect(listen)
	for place in _lived_in_places():
		var place_id := str(place["id"])
		var residents := _residents_of(place_id)
		if residents.is_empty():
			continue
		var here := w.place_position(place_id)
		w.force_stream_around(here)
		await _tree().process_frame
		await _tree().process_frame
		registry.despawn_all()
		var anchor := _anchor(w, here)
		Social.set_place(place_id)
		var standing := 0
		for def in residents:
			var id := str(def["id"])
			# somebody the story keeps out of the world (their def's gone_when: the tithe courier,
			# only ever a lead's body; the collector, stood only asleep through the rogue's night
			# lessons) is nowhere to stand up and nobody to walk up to
			if registry.is_gone(id):
				continue
			var where := registry.place_of(id)
			assert_true(ContentDB.has(where), "%s is nowhere at noon" % id)
			# somebody on the road home at noon is met on the road, not stood up at home
			if where == place_id and not registry.is_indoors(id) and not registry.is_travelling(id):
				var body: Node = registry.spawn(id)
				assert_true(body is Node3D, "%s is out of doors at noon and no body was stood up" % id)
				if body is Node3D:
					standing += 1
					var pos: Vector3 = (body as Node3D).global_position
					assert_true(_flat(pos, here) < NEAR_PLACE_M, "%s stands %.0f m from %s" % [id, _flat(pos, here), where])
					assert_true(absf(pos.y - World.get_height(pos.x, pos.z)) < 2.5, "%s is not on the ground" % id)
					var spot: Vector3 = body.call("_spot_position")
					assert_true(_flat(spot, here) < NEAR_PLACE_M,
						"%s's spot '%s' resolves %.0f m from %s" % [id, str(body.get("spot")), _flat(spot, here), where])
					assert_true(absf(spot.y - World.get_height(spot.x, spot.z)) < 3.0, "%s's spot is off the ground" % id)
				registry.despawn(id)
			# At home or away, awake or asleep: walking up to them says something.
			var hello := str(Social.greet(id))
			assert_ne(hello, "", "%s has no greeting" % id)
			lines.clear()
			Social.talk(id)
			assert_true(not lines.is_empty() and str(lines[0]).strip_edges().length() > 0, "%s said nothing when spoken to" % id)
			Social.dialogue.stop()
		if str(place["kind"]) in KEEP_SHOPS:
			assert_true(standing >= 3, "%s had %d people out of doors at noon" % [place_id, standing])
		anchor.queue_free()
	Social.dialogue.line_shown.disconnect(listen)
	registry.despawn_all()
	WorldClock.set_time(9.0, 2)
	# the streamer can be a service that outlives this world: left off, the next test's world
	# stood nobody up (test_start_rogue's Sauve and the watch, when it ran after this)
	streamer.enabled = true
	await _drop(w)


## Three in the morning. A `sleep` entry is under a roof (Schedules.is_indoors), and the
## streamer stands nobody up who is under a roof: a sleeper whose spot no scene names is not put
## somewhere absurd and is not dropped. Their state is kept, alive, at a real place, and the
## street is empty of them until their day begins.
func test_at_three_in_the_morning_the_villages_are_asleep_not_dropped() -> void:
	var w := _world()
	await w.world_ready
	var registry := NpcRegistry.ensure()
	registry.despawn_all()
	var streamer := NpcStreamer.ensure()
	streamer.enabled = false
	WorldClock.set_time(3.0, 2)
	registry.simulate_all("clear")
	for place in _lived_in_places():
		var place_id := str(place["id"])
		var residents := _residents_of(place_id)
		if residents.is_empty():
			continue
		var anchor := _anchor(w, w.place_position(place_id))
		streamer.refresh()
		for def in residents:
			var id := str(def["id"])
			if registry.is_gone(id):
				continue   # out of the world by the story (see noon), not asleep and not dropped
			assert_true(registry.is_alive(id), "%s was dropped from the roster overnight" % id)
			var where := registry.place_of(id)
			assert_true(ContentDB.has(where), "%s is nowhere at three in the morning" % id)
			if registry.is_indoors(id):
				assert_false(registry.is_spawned(id), "%s is asleep and standing in the street" % id)
			# Even for a sleeper, the fallback position is real ground at a real place.
			var pos := registry.spawn_position(id)
			assert_true(_flat(pos, w.place_position(where)) < NEAR_PLACE_M,
				"%s would be stood up %.0f m from %s" % [id, _flat(pos, w.place_position(where)), where])
		registry.despawn_all()
		anchor.queue_free()
	WorldClock.set_time(9.0, 2)
	streamer.enabled = true
	await _drop(w)


# --- the talk of the place -----------------------------------------------------------------------

## Walking into a region seeds its settlements with their own rumours (Gossip.stock_region), so
## a village nobody has questioned is not silent. Sixty-five rumours shipped and the ones with
## no region tag can only ever arrive as news about the player, which is why the outlands needed
## local talk of their own.
func test_walking_into_a_region_gives_its_villages_something_to_say() -> void:
	var gossip: Node = Social.gossip
	gossip.reset_for_new_game()
	for region in ContentDB.all("region"):
		var region_id := str(region["id"])
		gossip.stock_region(region_id)
		for place_id in gossip.settlements_of(region_id):
			if _residents_of(str(place_id)).is_empty():
				continue
			var pool: Array = gossip.pool_of(str(place_id))
			assert_true(pool.size() > 0, "%s has people in it and nothing to say" % place_id)
			for entry in pool:
				var said := str((entry as Dictionary).get("text", ""))
				assert_true(said.length() > 20, "%s is saying nothing much: '%s'" % [place_id, said])
				assert_false(said.contains("{"), "%s left a token in the talk: %s" % [place_id, said])
	gossip.reset_for_new_game()


## Every local rumour is a rumour a place can actually be given: tagged with the short name of a
## region that exists, and not about the player, because `_is_local_colour` refuses both.
func test_every_local_rumour_belongs_to_a_region_that_exists() -> void:
	var shorts: Dictionary = {}
	for region in ContentDB.all("region"):
		shorts[str(region["id"]).get_slice("/", 1)] = true
	var local := 0
	for def in ContentDB.all("rumour"):
		var tags: Array = def.get("tags", [])
		var region_tags := 0
		for t in tags:
			if shorts.has(str(t)):
				region_tags += 1
		if region_tags == 0:
			continue
		local += 1
		assert_eq(region_tags, 1, "%s is tagged with more than one region" % def["id"])
		assert_false(str(def.get("text", "")).contains("{player}"),
			"%s is local colour and about the player, so it can never be seeded" % def["id"])
	assert_true(local >= 40, "only %d rumours are local colour; the rest can only arrive as news about you" % local)


## The talk is reachable in a conversation: at a place that is saying something, a resident's
## hub offers it and says it (DialogueRunner.TALK_CHOICE).
func test_a_villager_of_a_new_settlement_repeats_the_local_talk() -> void:
	var gossip: Node = Social.gossip
	gossip.reset_for_new_game()
	gossip.stock_region("core:region/briarwold")
	var who := "core:npc/dorrie_cooper"          # the Hollow's trader; a gossip, and keeps a shop
	var place := str(ContentDB.get_or_empty(who).get("home_place", ""))
	assert_true(gossip.pool_of(place).size() > 0, "%s is saying nothing" % place)
	var lines: Array = []
	var listen := func(_speaker: String, text: String, _choices: Array) -> void:
		lines.append(text)
	Social.dialogue.line_shown.connect(listen)
	Social.talk(who, "", place)
	# `start` is the greet line, which has no choices; the talk is offered at the hub, so this
	# presses on the way a player does.
	Social.dialogue.advance()
	var offered := -1
	for i in Social.dialogue.current_choices.size():
		if str(Social.dialogue.current_choices[i]["text"]) == Social.dialogue.TALK_CHOICE:
			offered = i
	assert_true(offered >= 0, "the talk of the place was not offered at %s's hub" % who)
	if offered >= 0:
		Social.dialogue.choose(offered)
		assert_true(lines.size() > 1 and str(lines[-1]).length() > 20, "%s was asked for the news and said nothing" % who)
	Social.dialogue.line_shown.disconnect(listen)
	Social.dialogue.stop()
	gossip.reset_for_new_game()


# --- the shops open ----------------------------------------------------------------------------------

## Every shopkeeper's counter can be pressed: the merchant loads their own table, opens with
## stock in it, and sells something to a customer with marks.
func test_every_shopkeepers_counter_opens_with_stock_and_sells() -> void:
	if EconomyService.instance != null:
		EconomyService.instance.saved_state.clear()
	var player := Node3D.new()
	player.add_to_group("player")
	_tree().root.add_child(player)
	var bag := Inventory.new()
	bag.add_to_group("inventory")
	player.add_child(bag)
	bag.add_marks(5000)
	var keepers := 0
	for def in _people():
		if typeof(def.get("merchant")) != TYPE_DICTIONARY:
			continue
		keepers += 1
		var id := str(def["id"])
		var m := Merchant.new()
		m.name = "Merchant"
		m.npc_id = id
		_tree().root.add_child(m)
		var shelf: Array[Dictionary] = m.items()
		assert_true(shelf.size() > 0, "%s opened with an empty counter" % id)
		if not shelf.is_empty():
			var item := str(shelf[0]["item_id"])
			var result: Dictionary = m.buy(player, item, 1)
			assert_true(bool(result.get("ok", false)), "%s would not sell %s: %s" % [id, item, str(result.get("reason", ""))])
			assert_eq(bag.count(item), 1, "%s took the marks and kept the goods" % id)
			bag.remove(item, 1)
		_tree().root.remove_child(m)
		m.free()
	assert_true(keepers >= 12, "only %d people in the whole world keep a shop" % keepers)
	_tree().root.remove_child(player)
	player.free()
