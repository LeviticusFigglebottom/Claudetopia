extends TestCase
## Hearthvale's own large site (world life, phase 1): the Hound's Swallet, a cave under Hound Down with
## the Old Hound at the bottom, built, stood on, walked on its navigation mesh from the way in to every
## room, its boss in an arena, and left by its way out. The walk is test_sites.gd's, copied so the
## region's test is the region's own file.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")
const SWALLET := "core:interior/hounds_swallet"
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


func test_the_hounds_swallet_is_built_walkable_and_left() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(ContentDB.has(SWALLET), "the swallet's inside is content")
	var door := Door.new()
	tree.root.add_child(door)
	door.global_position = Vector3(110, 5, 100)
	door.interior_id = SWALLET
	assert_true(Interiors.enter(SWALLET, door), "it can be entered")
	await tree.process_frame
	await tree.physics_frame
	var site := Interiors._loaded.get(SWALLET) as SiteInterior
	assert_true(site != null and site.is_built, "it is built")
	if site == null:
		door.queue_free()
		return
	var space := player.get_world_3d().direct_space_state
	var at := player.global_position
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0, 1))
	assert_false(hit.is_empty(), "a floor under the way in")
	var ids: Array = []
	for r in site.plan.rooms:
		ids.append(str(r["id"]))
		var c := site.to_global(r["centre"])
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.5, c + Vector3.DOWN * 2.0, 1))
		var head := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.3, c + Vector3.UP * 2.1, 1))
		assert_false(down.is_empty(), "room %s has a floor" % r["id"])
		assert_true(head.is_empty(), "room %s has headroom at its middle" % r["id"])
	for want in ["throat", "pelters_camp", "bourne_lake", "the_den"]:
		assert_true(ids.has(want), "the swallet has its %s" % want)
	var report := _walk(site)
	print("SITE | %s | %d rooms, %d links, %d chunks, %d lights, %d foes, %d containers | reached %s" % [
		SWALLET, site.plan.rooms.size(), site.plan.links.size(), site.chunks.size(), site.dress.lights.size(),
		site.dress.spawner.living.size(), site.plan.containers.size(), report["reached"]])
	assert_eq(report["unreached"], [], "every room is walkable from the way in on the navigation mesh")
	assert_gt(site.dress.spawner.living.size(), 4, "foes stand in it")
	var boss_there := false
	for e in site.dress.spawner.living:
		boss_there = boss_there or (is_instance_valid(e) and str(e.get("enemy_id")) == "core:boss/old_hound")
	assert_true(boss_there, "the Old Hound lies in its den")
	assert_true(site.find_child("BossArena", true, false) != null, "the boss has an arena")
	var way_out := site.find_child("WayOut", true, false) as Door
	assert_true(way_out != null, "a way out")
	if way_out != null:
		way_out.interact(player)
		assert_false(Interiors.in_interior(), "the way out leads out")
	Interiors.unload_all()
	door.queue_free()
	await tree.process_frame


func _walk(site: SiteInterior) -> Dictionary:
	var nm := SiteInterior.navmesh_settings()
	NavigationServer3D.bake_from_source_geometry_data(nm, site.source_geometry())
	var reached: Array = []
	var unreached: Array = []
	for r in site.plan.rooms:
		var goal: Vector3 = r["centre"]
		if _joined(nm, site.plan.entrance, goal):
			reached.append(r["id"])
		else:
			unreached.append(r["id"])
	return {"reached": reached.size(), "unreached": unreached}


## Whether two points (local to the navigation mesh) stand on polygons joined by shared edges.
static func _joined(nm: NavigationMesh, a: Vector3, b: Vector3) -> bool:
	var verts := nm.get_vertices()
	var n := nm.get_polygon_count()
	if n == 0:
		return false
	var by_vert := {}
	var key := func(v: Vector3) -> Vector3i: return Vector3i((v * 10.0).round())
	for i in n:
		for vi in nm.get_polygon(i):
			by_vert.get_or_add(key.call(verts[vi]), []).append(i)
	var nearest := func(p: Vector3) -> int:
		var best := -1
		var best_d := INF
		for i in n:
			var c := Vector3.ZERO
			var poly := nm.get_polygon(i)
			for vi in poly:
				c += verts[vi]
			c /= float(poly.size())
			var d := Vector2(c.x - p.x, c.z - p.z).length() + absf(c.y - p.y) * 2.0
			if d < best_d:
				best_d = d
				best = i
		return best if best_d < 4.0 else -1
	var start: int = nearest.call(a)
	var goal: int = nearest.call(b)
	if start < 0 or goal < 0:
		return false
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var i: int = todo.pop_back()
		if i == goal:
			return true
		for vi in nm.get_polygon(i):
			for j in by_vert[key.call(verts[vi])]:
				if not seen.has(j):
					seen[j] = true
					todo.append(j)
	return false
