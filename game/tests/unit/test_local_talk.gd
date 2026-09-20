extends TestCase
## The talk of a place. A rumour only ever entered a pool because the player spoke to whoever
## seeds it, so a village nobody had questioned was silent — sixty-five written rumours and no
## way to hear all but a handful of them. Walking into a region stocks its settlements with
## their own talk now, and these pin what is and is not allowed into that.

## `Gossip` has no class_name and no `ensure()`: `Social` owns the one instance, which is
## also the instance the region-entry hook lives on.
var gossip: Node


func before_each() -> void:
	gossip = Social.gossip
	gossip.pools.clear()


func after_each() -> void:
	if is_instance_valid(gossip):
		gossip.pools.clear()


func _tagged(region_short: String) -> Array[String]:
	var out: Array[String] = []
	for def in ContentDB.all("rumour"):
		var tags: Variant = (def as Dictionary).get("tags", [])
		if typeof(tags) == TYPE_ARRAY and (tags as Array).has(region_short):
			out.append(str((def as Dictionary).get("id", "")))
	return out


func test_walking_into_a_region_gives_its_villages_something_to_say() -> void:
	assert_eq(gossip.places_talking().size(), 0, "somebody was talking before we arrived")
	var seeded: int = gossip.stock_region("core:region/hearthvale")
	assert_gt(seeded, 0, "Hearthvale had nothing of its own to say")
	assert_gt(gossip.places_talking().size(), 0, "nowhere in Hearthvale is talking")


func test_every_region_has_talk_of_its_own() -> void:
	for region in ContentDB.all("region"):
		var id := str((region as Dictionary).get("id", ""))
		gossip.pools.clear()
		var n: int = gossip.stock_region(id)
		assert_gt(n, 0, "%s has no rumours tagged for it" % id)


func test_only_that_regions_own_talk_is_seeded() -> void:
	gossip.stock_region("core:region/sedgemire")
	var theirs := _tagged("sedgemire")
	for place in gossip.places_talking():
		for entry in gossip.pool_of(place):
			var id := str((entry as Dictionary).get("rumour", ""))
			assert_true(theirs.has(id), "%s is being said in the fens and is not of the fens" % id)


func test_news_about_you_is_never_just_lying_around() -> void:
	# A deed rumour is earned. If walking into a valley seeded one, the world would be
	# congratulating you for things you have not done.
	for region in ContentDB.all("region"):
		gossip.pools.clear()
		gossip.stock_region(str((region as Dictionary).get("id", "")))
		for place in gossip.places_talking():
			for entry in gossip.pool_of(place):
				var id := str((entry as Dictionary).get("rumour", ""))
				var text := str(ContentDB.get_or_empty(id).get("text", ""))
				assert_false(text.contains("{player}"), "%s is about the player" % id)


func test_a_gated_rumour_is_not_said_before_it_is_true() -> void:
	var gated := ""
	for def in ContentDB.all("rumour"):
		var c: Variant = (def as Dictionary).get("conditions", [])
		if typeof(c) == TYPE_ARRAY and not (c as Array).is_empty():
			gated = str((def as Dictionary).get("id", ""))
			break
	if gated == "":
		return      # nothing in the pack is gated yet; nothing to prove
	for region in ContentDB.all("region"):
		gossip.pools.clear()
		gossip.stock_region(str((region as Dictionary).get("id", "")))
		for place in gossip.places_talking():
			assert_false(gossip.knows_rumour(place, gated),
					"%s is being said and its condition has not been met" % gated)


func test_the_talk_stays_local() -> void:
	# Local colour is under the spreading threshold: what Merrowby says about Merrowby is not
	# news that walks to the fens.
	assert_true(float(gossip.LOCAL_HEAT) < float(gossip.SPREAD_THRESHOLD),
			"the talk of a place would travel like news")
	assert_true(float(gossip.LOCAL_HEAT) > float(gossip.MIN_HEAT),
			"the talk of a place would evaporate at once")


func test_coming_back_finds_them_still_talking() -> void:
	gossip.stock_region("core:region/hearthvale")
	var first: int = gossip.places_talking().size()
	gossip.advance_hours(72.0)              # three days away: local colour has faded out
	gossip.stock_region("core:region/hearthvale")
	assert_eq(gossip.places_talking().size(), first, "the village had nothing to say on your return")


func test_the_same_village_says_the_same_things() -> void:
	gossip.stock_region("core:region/briarwold")
	var before: Dictionary = {}
	for place in gossip.places_talking():
		var ids: Array[String] = []
		for entry in gossip.pool_of(place):
			ids.append(str((entry as Dictionary).get("rumour", "")))
		ids.sort()
		before[place] = ids
	gossip.pools.clear()
	gossip.stock_region("core:region/briarwold")
	for place in gossip.places_talking():
		var ids: Array[String] = []
		for entry in gossip.pool_of(place):
			ids.append(str((entry as Dictionary).get("rumour", "")))
		ids.sort()
		assert_eq(ids, before.get(place, []), "%s changed its mind about what it talks about" % place)
