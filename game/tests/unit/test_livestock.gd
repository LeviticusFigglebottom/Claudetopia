extends TestCase
## A settlement's beasts (world/exteriors/livestock.gd): hens in the yards, geese on the green,
## ewes in the paddocks, a pig in its sty -- each keeping to its own ground and wandering it, and
## none of them in a ruin.

const CENTRE := Vector3(900.0, 30.0, 2350.0)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _east_road() -> Array:
	var line: Array = []
	for i in range(-12, 13):
		line.append([CENTRE.x + float(i) * 9.0, CENTRE.z])
	return line


func test_the_forge_built_the_village_beasts() -> void:
	for kind in ["hen", "goose", "sheep", "pig"]:
		var paths := Livestock.paths_of(kind)
		assert_false(paths.is_empty(), "no %s in the forge's props" % kind)
		for p in paths:
			var meta := p.get_basename() + ".meta.json"
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta))
			assert_true(parsed is Dictionary, "%s has no meta" % p)
			var tris := int(((parsed as Dictionary).get("meshes", [{}]) as Array)[0].get("tris", 0))
			assert_true(tris > 0 and tris < 2500, "a %s of %d triangles, and a village keeps forty beasts" % [kind, tris])


func test_a_beast_keeps_to_its_own_ground_and_wanders_it() -> void:
	var stock := Livestock.new()
	stock.seed_with(5)
	var home := Vector3(10.0, 0.0, 10.0)
	stock.keep("hen", Livestock.paths_of("hen"), home, 2.0, 5)
	_tree().root.add_child(stock)
	var start: Array = []
	for b in stock.beasts:
		start.append(b["at"])
	for i in range(3000):
		stock.step(0.1)
	var moved := 0
	for i in range(stock.beasts.size()):
		var at: Vector3 = stock.beasts[i]["at"]
		assert_true(Vector2(at.x - home.x, at.z - home.z).length() <= 2.0 + 0.01, "a hen strayed %.1f m from its yard" % Vector2(at.x - home.x, at.z - home.z).length())
		if at.distance_to(start[i]) > 0.3:
			moved += 1
	assert_gt(moved, 2, "five hens in five minutes and %d of them moved" % moved)
	stock.free()


func test_a_village_keeps_hens_geese_and_sheep_and_a_ruin_keeps_none() -> void:
	var s := Settlement.raise_at("core:place/test_farmstead", "village", "core:region/hearthvale", CENTRE, 64.0,
			[_east_road()], [])
	_tree().root.add_child(s)
	var stock := s.get_node_or_null("Livestock") as Livestock
	assert_true(stock != null, "a Vale village with not a hen in it")
	var kinds := {}
	for b in stock.beasts:
		kinds[str(b["kind"])] = true
	for want in ["hen", "goose", "sheep"]:
		assert_true(kinds.has(want), "a Vale village keeps no %s: %s" % [want, kinds.keys()])
	s.queue_free()
	var ruin := Settlement.raise_at("core:place/test_empty", "ruin_village", "core:region/cinderlea", CENTRE, 64.0,
			[_east_road()], [])
	_tree().root.add_child(ruin)
	assert_true(ruin.get_node_or_null("Livestock") == null, "beasts kept in a ruin nobody lives in")
	ruin.queue_free()
