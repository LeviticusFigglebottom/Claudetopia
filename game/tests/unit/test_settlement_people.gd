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


func test_no_two_people_share_a_face_seed() -> void:
	var seen: Dictionary = {}
	for def in _people():
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
			var where := registry.place_of(id)
			assert_true(ContentDB.has(where), "%s is nowhere at noon" % id)
			if where == place_id and not registry.is_indoors(id):
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
	await _drop(w)


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
