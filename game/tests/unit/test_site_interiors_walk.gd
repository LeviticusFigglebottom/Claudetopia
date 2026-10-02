extends TestCase
## Every large site's inside, in every region, walked end to end on the seed a player gets.
##
## The seed is the def's own: SitePlan.make takes `site.seed` (or, without one, a hash of the
## interior's id), and nothing else feeds the plan, the rock, the dressing or the foes, so a
## site is the same place on every machine, every world and every visit (site_plan.gd). A seed
## that does not walk end to end is therefore not a chance a player might draw: it is a softlock
## every player of that site has. test_sites walks the generator's kinds at three seeds; this
## walks what ships: every interior def with a `site` block in every pack file, built as the game
## builds it, its navigation mesh baked from the rock and its passages' links, from the way in to
## every room. A def written with its own rooms (a hand-laid mine, a barrow) is walked as written.
## The secret room is walked as the player walks it, with its loose stones pulled away: its passage
## has no navigation link while it is sealed (SiteInterior.passage_links), so it is given its own.
##
## The seed cannot vary at runtime, but an author moving a def's seed, or a change to the shared
## generator, can make a written layout one that does not walk: the second test walks every def
## that writes its own rooms on a spread of other seeds too (the Charter Delf's written mine once
## walked on one seed in ten, before a secret's passage was cut on into its host room).

const TestSites := preload("res://tests/unit/test_sites.gd")


func test_every_shipped_site_inside_walks_from_its_way_in_to_every_room() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var ids: Array[String] = []
	for id in ContentDB.ids_of("interior"):
		var def := ContentDB.get_def(id)
		if def.get("site", null) is Dictionary:
			ids.append(id)
	ids.sort()
	assert_gt(ids.size(), 10, "the packs' large sites are found (%d)" % ids.size())
	var bad: Array = []
	for id in ids:
		var site := SiteInterior.new()
		site.def_override = ContentDB.get_def(id)
		site.paced_override = 0
		tree.root.add_child(site)
		await tree.process_frame
		var walk: Dictionary = await _walk(site)
		var seed_i := site.plan.site_seed
		print("SITE INSIDE | %s | seed %d | %d rooms | unreached %s" % [id, seed_i, site.plan.rooms.size(), walk["unreached"]])
		if not (walk["unreached"] as Array).is_empty():
			bad.append("%s (seed %d): %s" % [id, seed_i, walk["unreached"]])
		site.queue_free()
		await tree.process_frame
	assert_eq(bad, [], "every shipped site's inside walks from its way in to every room")


## Every def that writes its own rooms, on seeds it does not ship with: what the generator makes of
## a written layout is the same whatever the seed.
func test_every_written_site_layout_walks_on_a_spread_of_seeds() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var bad: Array = []
	var built := 0
	for id in ContentDB.ids_of("interior"):
		var def := ContentDB.get_def(id)
		var site_def: Variant = def.get("site", null)
		if not (site_def is Dictionary) or (site_def as Dictionary).get("rooms", []).is_empty():
			continue
		for seed_i in [1019, 2024, 7400]:
			var d: Dictionary = def.duplicate(true)
			d["site"]["seed"] = seed_i
			var site := SiteInterior.new()
			site.def_override = d
			site.paced_override = 0
			tree.root.add_child(site)
			await tree.process_frame
			built += 1
			var walk: Dictionary = await _walk(site)
			if not (walk["unreached"] as Array).is_empty():
				bad.append("%s (seed %d): %s" % [id, seed_i, walk["unreached"]])
			site.queue_free()
			await tree.process_frame
	print("SITE INSIDE | %d written layouts walked on other seeds, %d cut a room off" % [built, bad.size()])
	assert_gt(built, 20, "the written layouts are found")
	assert_eq(bad, [], "every written layout walks on any seed")


func _walk(site: SiteInterior) -> Dictionary:
	var nm := SiteInterior.navmesh_settings()
	NavigationServer3D.bake_from_source_geometry_data(nm, site.source_geometry())
	var unreached: Array = []
	var links := SiteInterior.passage_links(site.plan)
	# the secret's passage, its stones pulled away, as the player walks it
	for l in site.plan.links:
		if str(l["kind"]) == "secret":
			var chain: Array = [(site.plan.room(str(l["a"]))["centre"] as Vector3) + Vector3.UP * 0.05]
			var inner: Array = l["points"]
			for i in range(1, inner.size() - 1):
				chain.append(inner[i])
			chain.append((site.plan.room(str(l["b"]))["centre"] as Vector3) + Vector3.UP * 0.05)
			for i in range(1, chain.size()):
				links.append([chain[i - 1], chain[i], true])
	for r in site.plan.rooms:
		if not TestSites._joined(nm, site.plan.entrance, r["centre"], links):
			unreached.append(r["id"])
	return {"unreached": unreached}
