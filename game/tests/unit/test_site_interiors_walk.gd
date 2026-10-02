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


func _walk(site: SiteInterior) -> Dictionary:
	var nm := SiteInterior.navmesh_settings()
	NavigationServer3D.bake_from_source_geometry_data(nm, site.source_geometry())
	var unreached: Array = []
	var links := SiteInterior.passage_links(site.plan)
	for r in site.plan.rooms:
		if not TestSites._joined(nm, site.plan.entrance, r["centre"], links):
			unreached.append(r["id"])
	return {"unreached": unreached}
