extends TestCase
## Every large site's inside, in every region, walked end to end on the seed a player gets, and back.
##
## The seed is the def's own: SitePlan.make takes `site.seed` (or, without one, a hash of the
## interior's id), and nothing else feeds the plan, the rock, the dressing or the foes, so a
## site is the same place on every machine, every world and every visit (site_plan.gd). A seed
## that does not walk end to end is therefore not a chance a player might draw: it is a softlock
## every player of that site has. test_sites walks the generator's kinds at three seeds; this
## walks what ships: every interior def with a `site` block in every pack file, built as the game
## builds it, its navigation mesh baked from the rock and its passages' links:
##
## * in, from the way in to every room, after the way back from the boss is laid and with it still
##   barred (the secret with its loose stones pulled away: its passage has no navigation link while
##   it is sealed, so it is given its own), the way in standing on the mesh; test_brightwater_places
##   reads its insides the same way (test_sites' reading of the mesh);
## * back, from the boss's room to the way in, a drop taken only downward (a one-way drop on the
##   way to the boss and no way back up is the softlock), with the barred way back from the boss
##   lifted from the boss's side as the player lifts it;
## * the way back from the boss laid at all (SitePlan's "no way back from the boss" problem).
##
## The seed cannot vary at runtime, but an author moving a def's seed, or a change to the shared
## generator, can make a written layout one that does not walk: the second test walks every def
## that writes its own rooms on a spread of other seeds too.

const TestSites := preload("res://tests/unit/test_sites.gd")
const SPREAD := [1019, 2024, 7400]


func test_every_shipped_site_inside_walks_in_to_every_room_and_back_from_the_boss() -> void:
	var bad: Array = []
	var ids := _site_ids(false)
	assert_gt(ids.size(), 10, "the packs' large sites are found (%d)" % ids.size())
	for id in ids:
		bad.append_array(await _check(ContentDB.get_def(id)))
	assert_eq(bad, [], "every shipped site's inside walks in to every room and back out from the boss")


## Every def that writes its own rooms, on seeds it does not ship with: what the generator makes of
## a written layout is the same whatever the seed.
func test_every_written_site_layout_walks_on_a_spread_of_seeds() -> void:
	var bad: Array = []
	var built := 0
	for id in _site_ids(true):
		for seed_i in SPREAD:
			var d: Dictionary = ContentDB.get_def(id).duplicate(true)
			d["site"]["seed"] = seed_i
			bad.append_array(await _check(d))
			built += 1
	print("SITE INSIDE | %d written layouts walked on other seeds, %d findings" % [built, bad.size()])
	assert_gt(built, 20, "the written layouts are found")
	assert_eq(bad, [], "every written layout walks in and back on any seed")


static func _site_ids(written_only: bool) -> Array[String]:
	var ids: Array[String] = []
	for id in ContentDB.ids_of("interior"):
		var site_def: Variant = ContentDB.get_def(id).get("site", null)
		if not (site_def is Dictionary):
			continue
		if written_only and (site_def as Dictionary).get("rooms", []).is_empty():
			continue
		ids.append(id)
	ids.sort()
	return ids


## What is wrong with one site built from `def`: rooms not reached from the way in, no way back
## from the boss to the way in, no way back laid. Empty when it walks.
func _check(def: Dictionary) -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	var site := SiteInterior.new()
	site.def_override = def
	site.paced_override = 0
	tree.root.add_child(site)
	await tree.process_frame
	var plan := site.plan
	var id := "%s (seed %d)" % [def.get("id", "?"), plan.site_seed]
	var out: Array = []
	var nm := SiteInterior.navmesh_settings()
	NavigationServer3D.bake_from_source_geometry_data(nm, site.source_geometry())
	# in: the passages and the secret's stones pulled away; the way back is still barred (it
	# opens from the boss's side only), so a room reached only through it is cut off
	var links := SiteInterior.passage_links(plan)
	for l in plan.links:
		if str(l["kind"]) == "secret":
			links.append_array(_chain(plan, l))
	if not TestSites._joined(nm, plan.entrance, plan.entrance, links):
		out.append("%s: the way in stands on no walkable ground" % id)
	var unreached: Array = []
	for r in plan.rooms:
		if not TestSites._joined(nm, plan.entrance, r["centre"], links):
			unreached.append(r["id"])
	if not unreached.is_empty():
		out.append("%s: not reached from the way in: %s" % [id, unreached])
	# back: the bar on the way back lifted from the boss's side
	for l in plan.links:
		if str(l["kind"]) == "shortcut":
			links.append_array(_chain(plan, l))
	var boss := {}
	for r in plan.rooms:
		if r["role"] == "boss":
			boss = r
	var back := true
	if not boss.is_empty():
		back = TestSites._joined(nm, boss["centre"], plan.entrance, links)
		if not back:
			out.append("%s: no way back from the boss's room to the way in" % id)
	var laid := true
	for p in plan.problems:
		if str(p).contains("no way back from the boss"):
			laid = false
			out.append("%s: %s" % [id, p])
	print("SITE INSIDE | %s | %d rooms | unreached %s | back %s | way back laid %s" % [id, plan.rooms.size(), unreached, back, laid])
	site.queue_free()
	await tree.process_frame
	return out


## A passage as navigation links walked both ways: room middle, its bends, room middle.
static func _chain(plan: SitePlan, l: Dictionary) -> Array:
	var pts: Array = [(plan.room(str(l["a"]))["centre"] as Vector3) + Vector3.UP * 0.05]
	var inner: Array = l["points"]
	for i in range(1, inner.size() - 1):
		pts.append(inner[i])
	pts.append((plan.room(str(l["b"]))["centre"] as Vector3) + Vector3.UP * 0.05)
	var out: Array = []
	for i in range(1, pts.size()):
		out.append([pts[i - 1], pts[i], true])
	return out
