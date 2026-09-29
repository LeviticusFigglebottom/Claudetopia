extends TestCase
## The Briarwold's large sites (world life, docs/WORLD_LIFE_INTERIORS.md): the Skarl Delving's inside
## built, stood on, walkable on its navigation mesh from the way in to every room, with its foes, its
## boss's arena and a way out; the Horn Pale's stockade walled round with a gate and its garrison up
## on the fighting step; the delve's mouth with its door and the tally-board that starts its story.
## The same checks test_sites.gd makes of the showcases, kept here so the Briarwold's author edits
## nothing another author does.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")
const TestSites := preload("res://tests/unit/test_sites.gd")
const INSIDE := ["core:interior/skarl_delving"]
var player: Node3D


func before_each() -> void:
	player = FakePlayer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	player.global_position = Vector3(100, 5, 100)
	Interiors.current_id = ""
	GameState.current_interior_id = ""


func after_each() -> void:
	if Interiors.in_interior():
		Interiors.exit()
	Interiors.unload_all()
	player.get_parent().remove_child(player)
	player.free()


func test_the_skarl_delving_is_built_walkable_and_left() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for id in INSIDE:
		assert_true(ContentDB.has(id), "%s is content" % id)
		var door := Door.new()
		tree.root.add_child(door)
		door.global_position = Vector3(110, 5, 100)
		door.interior_id = id
		assert_true(Interiors.enter(id, door), "%s can be entered" % id)
		await tree.process_frame
		await tree.physics_frame
		var site := Interiors._loaded.get(id) as SiteInterior
		assert_true(site != null and site.is_built, "%s is built" % id)
		if site == null:
			door.queue_free()
			continue
		var space := player.get_world_3d().direct_space_state
		var at := player.global_position
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0, 1))
		assert_false(hit.is_empty(), "%s: a floor under the way in" % id)
		for r in site.plan.rooms:
			var c := site.to_global(r["centre"])
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.5, c + Vector3.DOWN * 2.0, 1))
			var head := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.3, c + Vector3.UP * 2.1, 1))
			assert_false(down.is_empty(), "%s: room %s has a floor" % [id, r["id"]])
			assert_true(head.is_empty(), "%s: room %s has headroom at its middle" % [id, r["id"]])
		var walk := _walk(site)
		print("SITE | %s | %d rooms, %d links, %d chunks, %d lights, %d foes, %d containers | reached %d | main %.0f ms" % [
			id, site.plan.rooms.size(), site.plan.links.size(), site.chunks.size(), site.dress.lights.size(),
			site.dress.spawner.living.size(), site.plan.containers.size(), walk["reached"], site.main_us / 1000.0])
		assert_eq(walk["unreached"], [], "%s: every room is walkable from the way in on the navigation mesh" % id)
		assert_gt(site.dress.spawner.living.size(), 4, "%s: foes stand in it" % id)
		assert_true(site.find_child("BossArena", true, false) != null, "%s: the boss has an arena" % id)
		var boss_there := false
		for e in site.dress.spawner.living:
			if (e as Enemy).enemy_id == "core:boss/reel_mother":
				boss_there = true
		assert_true(boss_there, "%s: the Reel-Mother waits in it" % id)
		var way_out := site.find_child("WayOut", true, false) as Door
		assert_true(way_out != null, "%s: a way out" % id)
		if way_out != null:
			way_out.interact(player)
			assert_false(Interiors.in_interior(), "%s: the way out leads out" % id)
		Interiors.unload_all()
		door.queue_free()
		await tree.process_frame


func test_the_delvings_mouth_has_its_door_and_its_tally_board() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var def := ContentDB.get_def("core:poi/skarl_delving")
	var entry := {"place_id": "core:poi/skarl_delving", "pos": [0.0, 0.0, 0.0], "radius_flat_m": 24.0, "radius_level_m": 24.0}
	var d := PoiDressing.raise(entry, def)
	tree.root.add_child(d)
	await tree.process_frame
	await tree.physics_frame
	assert_true(d.finished, "the delving's mouth is built")
	var door := d.find_child("Door_skarl_delving", true, false) as Door
	assert_true(door != null, "a door at the back of the throat into the delving")
	var hook := d.find_child("Hook", true, false) as PoiTouch
	assert_true(hook != null and hook.dialogue_id == "core:dialogue/skarl_delving_board", "the tally-board by the adit")
	d.queue_free()
	await tree.process_frame


func test_the_horn_pale_is_walled_with_a_gate_and_a_garrison_on_the_step() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var def := ContentDB.get_def("core:poi/horn_pale")
	var entry := {"place_id": "core:poi/horn_pale", "pos": [0.0, 0.0, 0.0], "radius_flat_m": 30.0, "radius_level_m": 30.0}
	var d := PoiDressing.raise(entry, def)
	tree.root.add_child(d)
	await tree.process_frame
	await tree.physics_frame
	assert_true(d.finished, "the pale is built")
	var space := d.get_world_3d().direct_space_state
	var walls := 0
	var through := 0
	for i in 36:
		var a := TAU * float(i) / 36.0
		var dir := Vector3(sin(a), 0.0, cos(a))
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3.UP * 1.2 + dir * 8.0, Vector3.UP * 1.2 + dir * 28.0, 1))
		if h.is_empty():
			through += 1
		else:
			walls += 1
	print("HORN PALE | %d of 36 bearings staked, %d open (the gate)" % [walls, through])
	assert_gt(walls, 28, "staked round")
	assert_gt(through, 0, "and a gate to walk through")
	var garrison := d.find_child("Garrison", true, false) as EnemySpawner
	assert_true(garrison != null and garrison.living.size() >= 6, "a garrison of %d" % (garrison.living.size() if garrison else 0))
	var bravo := false
	if garrison != null:
		for e in garrison.living:
			if (e as Enemy).enemy_id == "core:enemy/bravo":
				bravo = true
	assert_true(bravo, "the factor's bravo is among them (the quest's kill)")
	var hook := d.find_child("Hook", true, false) as PoiTouch
	assert_true(hook != null and hook.dialogue_id == "core:dialogue/horn_pale_board", "the price board at the gate")
	d.queue_free()
	await tree.process_frame


func _walk(site: SiteInterior) -> Dictionary:
	var nm := SiteInterior.navmesh_settings()
	NavigationServer3D.bake_from_source_geometry_data(nm, site.source_geometry())
	var reached := 0
	var unreached: Array = []
	for r in site.plan.rooms:
		if TestSites._joined(nm, site.plan.entrance, r["centre"]):
			reached += 1
		else:
			unreached.append(r["id"])
	return {"reached": reached, "unreached": unreached}
