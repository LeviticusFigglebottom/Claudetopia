extends TestCase
## Cinderlea's large sites and its own builders (docs/WORLD_LIFE.md, WORLD_LIFE_INTERIORS.md): the
## Undercroft of Turnback and Anthe-Ondr entered, built, walked from the way in to every room on
## their navigation meshes, peopled, with a boss's arena and a way out; and the places the region's
## builders raise (game/world/pois/regions/cinderlea.gd) standing with the doors, the spots their
## people keep and the things to touch that their content names.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")
const INSIDES := ["core:interior/turnback_undercroft", "core:interior/anthe_ondr"]
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


func test_the_insides_are_built_walkable_peopled_and_left() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for id in INSIDES:
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
		var report := _walk(site)
		print("CINDERLEA SITE | %s | %d rooms, %d links, %d chunks, %d lights, %d foes, %d containers | reached %s | main %.0f ms" % [
			id, site.plan.rooms.size(), site.plan.links.size(), site.chunks.size(), site.dress.lights.size(),
			site.dress.spawner.living.size(), site.plan.containers.size(), report["reached"], site.main_us / 1000.0])
		assert_eq(report["unreached"], [], "%s: every room is walkable from the way in" % id)
		assert_gt(site.dress.spawner.living.size(), 4, "%s: foes stand in it" % id)
		assert_true(site.find_child("BossArena", true, false) != null, "%s: the boss has an arena" % id)
		var boss_id := str(ContentDB.get_or_empty(id).get("site", {}).get("boss", ""))
		var stood := false
		for e in site.dress.spawner.living:
			stood = stood or (e as Enemy).enemy_id == boss_id
		assert_true(stood, "%s: %s stands in it" % [id, boss_id])
		var way_out := site.find_child("WayOut", true, false) as Door
		assert_true(way_out != null, "%s: a way out" % id)
		if way_out != null:
			way_out.interact(player)
			assert_false(Interiors.in_interior(), "%s: the way out leads out" % id)
		Interiors.unload_all()
		door.queue_free()
		await tree.process_frame


## The region's own builders, raised on flat ground: each place finished, with what its people,
## quests and hooks name standing in it.
func test_the_regions_builders_stand_what_their_content_names() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var wants := {
		"core:poi/turnback_keep": {"spots": ["elsbet_fire"], "doors": ["Door_turnback_undercroft"], "touch": ["Hook"]},
		"core:poi/salt_landing": {"spots": ["landing_fire", "thalisse_awning", "the_oar_lantern", "ossul_boat"], "touch": ["the_lantern"]},
		"core:poi/bellrope_walk": {"spots": ["home", "the_wheel", "the_sledge"], "touch": ["the_strand"]},
		"core:poi/rooftop_shaft": {"doors": ["Door_anthe_ondr"], "touch": ["Hook"]},
		"core:poi/ashcombe_mill": {"spots": ["the_door"], "touch": ["the_tally"]},
	}
	for id in wants:
		var def := ContentDB.get_def(id)
		assert_false(def.is_empty(), "%s is content" % id)
		var pad := float(def.get("pad_radius_m", 25.0))
		var entry := {"place_id": id, "pos": [0.0, 0.0, 0.0], "radius_flat_m": pad, "radius_level_m": pad * 0.7}
		var d := PoiDressing.raise(entry, def)
		tree.root.add_child(d)
		var frames := 0
		while not d.finished and frames < 600:
			await tree.process_frame
			frames += 1
		assert_true(d.finished, "%s is built" % id)
		assert_true(d.regional_builder() != null, "%s is built by the region's own builder" % id)
		var want: Dictionary = wants[id]
		for s in want.get("spots", []):
			assert_true(d.find_child(str(s), true, false) != null, "%s: the spot %s stands" % [id, s])
		for n in want.get("doors", []):
			var door := d.find_child(str(n), true, false) as Door
			assert_true(door != null, "%s: the door %s stands" % [id, n])
		for n in want.get("touch", []):
			var t := d.find_child(str(n), true, false)
			assert_true(t != null, "%s: %s can be touched" % [id, n])
		var reach := 0.0
		for c in d.find_children("*", "Node3D", true, false):
			var p := d.to_local((c as Node3D).global_position)
			reach = maxf(reach, Vector2(p.x, p.z).length())
		print("CINDERLEA BUILDER | %s | reach %.1f m on a %.0f m pad" % [id, reach, pad])
		assert_true(reach <= pad + 4.0, "%s: its pieces stand on its pad (%.1f m of %.0f)" % [id, reach, pad])
		d.queue_free()
		await tree.process_frame


# --- helpers (as test_sites.gd's) ---------------------------------------------------------------------

func _walk(site: SiteInterior) -> Dictionary:
	var nm := SiteInterior.navmesh_settings()
	NavigationServer3D.bake_from_source_geometry_data(nm, site.source_geometry())
	var reached: Array = []
	var unreached: Array = []
	for r in site.plan.rooms:
		if _joined(nm, site.plan.entrance, r["centre"]):
			reached.append(r["id"])
		else:
			unreached.append(r["id"])
	return {"reached": reached.size(), "unreached": unreached}


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
			var dd := Vector2(c.x - p.x, c.z - p.z).length() + absf(c.y - p.y) * 2.0
			if dd < best_d:
				best_d = dd
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
