extends TestCase
## Cinderlea's large sites and its own builders (docs/WORLD_LIFE.md, WORLD_LIFE_INTERIORS.md): the
## Undercroft of Turnback and Anthe-Ondr entered, built, walked from the way in to every room on
## their navigation meshes, peopled, with a boss's arena and a way out; and the places the region's
## builders raise (game/world/pois/regions/cinderlea.gd) standing with the doors, the spots their
## people keep and the things to touch that their content names.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")
const INSIDES := ["core:interior/turnback_undercroft", "core:interior/anthe_ondr", "core:interior/cistern_of_isse"]
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
		assert_gt(site.dress.spawner.living.size(), 3, "%s: foes stand in it" % id)
		var boss_id := str(ContentDB.get_or_empty(id).get("site", {}).get("boss", ""))
		if boss_id != "":
			assert_true(site.find_child("BossArena", true, false) != null, "%s: the boss has an arena" % id)
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
		"core:poi/greyfleece_shieling": {"spots": ["the_fold"]},
		"core:poi/bell_counters_hut": {"spots": ["the_stone"]},
		"core:poi/scavengers_ring": {"spots": ["ring_hearth", "the_gate"]},
		"core:poi/sayers_gauge": {"spots": ["the_gauge_foot"]},
		# the second pass (world life phase 2): every ruin from its own sentence, with the spots its
		# encounters and quests name and the thing to touch that tells its story
		"core:poi/bell_street": {"spots": ["in_the_bell", "the_street"], "touch": ["the_solid_bell"], "boxes": 1},
		"core:poi/sunk_plaza": {"spots": ["the_fountain"], "touch": ["the_count"]},
		"core:poi/anthem_hall": {"spots": ["the_benches", "the_stone"], "touch": ["the_singers_stone"], "boxes": 1},
		"core:poi/cistern_of_isse": {"spots": ["the_stair_head", "the_well_foot"], "doors": ["Door_cistern_of_isse"], "touch": ["the_well"]},
		"core:poi/weighhouse": {"spots": ["the_yard", "the_tally_desk"], "touch": ["the_pans"], "boxes": 1},
		"core:poi/silent_market": {"spots": ["the_fresh_stall", "the_square"], "touch": ["the_fresh_goods"], "boxes": 1},
		"core:poi/north_gate": {"spots": ["the_gateway", "beyond_the_gate"], "touch": ["the_track"]},
		"core:poi/bell_pit": {"spots": ["the_pit", "the_diggers"], "boxes": 1},
		"core:poi/hermits_gate": {"spots": ["home", "the_arch"], "touch": ["the_door"]},
		"core:poi/hesk_morn": {"spots": ["the_door", "the_threshold"], "touch": ["the_slab"]},
		"core:poi/ashcombe": {"spots": ["hearth_0", "the_green"], "touch": ["the_chimney"], "boxes": 1},
		"core:poi/ashwinter_carts": {"spots": ["the_day_book", "the_cart_beds"], "touch": ["the_book_peg"], "boxes": 1},
		"core:poi/bell_garden": {"spots": ["the_rows", "the_striking_post"], "touch": ["the_garden"]},
		"core:poi/row_of_mouths": {"spots": ["the_singing_mouth", "the_colonnade"], "touch": ["the_mouth"]},
		"core:poi/hesk_pool": {"spots": ["the_steps"], "touch": ["the_black_water"]},
		"core:poi/builders_harbour": {"spots": ["the_quay"], "touch": ["the_bell_post"], "boxes": 1},
		"core:poi/greywatch": {"spots": ["the_reading"], "touch": ["the_names"]},
		"core:poi/ninth_waystone": {"spots": ["the_count"], "touch": ["the_tallies"]},
		"core:poi/greyline_stones": {"spots": ["the_newest"], "touch": ["the_line"]},
		"core:poi/last_milestone": {"spots": ["the_names", "the_road_west"]},
		"core:poi/novices_seats": {"spots": ["the_seats", "home"], "touch": ["the_turned_seat"]},
		"core:poi/tower_of_vaelost": {"spots": ["the_fallen_course", "the_foot"], "touch": ["the_course"]},
		"core:poi/sulion": {"spots": ["the_socket", "the_foot"]},
		"core:poi/hush_bell": {"spots": ["the_bell_arm", "the_tower_door"], "touch": ["the_bell"]},
		"core:poi/strand_beacon": {"spots": ["the_stair_foot"], "touch": ["the_ashes"], "boxes": 1},
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
			var t := d.find_child(str(n), true, false) as PoiTouch
			assert_true(t != null, "%s: %s can be touched" % [id, n])
			if t != null and t.dialogue_id != "":
				assert_true(ContentDB.has(t.dialogue_id), "%s: %s's words (%s) are content" % [id, n, t.dialogue_id])
		var boxes := 0
		for c in d.find_children("*", "WorldContainer", true, false):
			boxes += 1
			assert_true(ContentDB.has((c as WorldContainer).loot_table), "%s: %s's loot is content" % [id, (c as WorldContainer).loot_table])
		assert_true(boxes >= int(want.get("boxes", 0)), "%s: %d things to open" % [id, int(want.get("boxes", 0))])
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
