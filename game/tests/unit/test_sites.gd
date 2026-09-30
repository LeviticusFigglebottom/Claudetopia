extends TestCase
## The large sites (world/sites, docs/WORLD_LIFE_INTERIORS.md): every kind's layouts connected, with a
## loop, a secret and a way back out; the showcase insides built, walkable on their navigation meshes
## from the way in to every room, entered and left and saved inside; the build the same every time and
## in pieces within the frame's budget; the fort's walls, gate and walkways standing and climbable.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")
const SHOWCASE := ["core:interior/the_kilnway", "core:interior/scathe_undercroft"]
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


static func _def(kind: String, seed_i: int, size := "medium") -> Dictionary:
	return {"id": "core:interior/test_site_%s_%d" % [kind, seed_i], "name": "Test %s" % kind, "danger": 2,
			"site": {"kind": kind, "seed": seed_i, "size": size, "region": "hearthvale", "boss": "core:boss/barrow_reeve"}}


## Every kind, several seeds and sizes: every room is reached from the way in and has a way back to
## it, the rooms make a loop, and the plan has its secret room and its way from the boss back out.
func test_every_kind_lays_connected_plans_with_a_loop_a_secret_and_a_way_out() -> void:
	var plans := 0
	var secrets := 0
	var shortcuts := 0
	var drops := 0
	var pieces := {}
	for kind in SiteKinds.KINDS:
		for seed_i in [1, 2, 3, 4, 5, 6]:
			for size in ["medium", "large"]:
				var p := SitePlan.make(_def(kind, seed_i, size))
				plans += 1
				var reach := p.reach()
				assert_eq((reach["from"] as Array).size(), p.rooms.size(), "%s/%d/%s: every room is reached from the way in %s" % [kind, seed_i, size, p.problems])
				assert_eq((reach["back"] as Array).size(), p.rooms.size(), "%s/%d/%s: every room has a way back" % [kind, seed_i, size])
				assert_true(p.has_loop(), "%s/%d/%s: the rooms make a loop" % [kind, seed_i, size])
				var boss := 0
				for r in p.rooms:
					boss += 1 if r["role"] == "boss" else 0
					if str(r["set_piece"]) != "":
						pieces[r["set_piece"]] = int(pieces.get(r["set_piece"], 0)) + 1
				assert_eq(boss, 1, "%s/%d: one boss room" % [kind, seed_i])
				for l in p.links:
					secrets += 1 if l["kind"] == "secret" else 0
					shortcuts += 1 if l["kind"] == "shortcut" else 0
					drops += 1 if l["kind"] == "drop" else 0
					# no passage climbs steeper than a body can walk (a drop is level, then a fall)
					var pts: Array = l["points"]
					for i in range(1, pts.size()):
						var a: Vector3 = pts[i - 1]
						var b: Vector3 = pts[i]
						var run := Vector2(b.x - a.x, b.z - a.z).length()
						assert_true(absf(b.y - a.y) <= run * SitePlan.MAX_SLOPE + 0.6, "%s/%d: a passage %s climbs %.1f m in %.1f m" % [kind, seed_i, l["kind"], b.y - a.y, run])
				assert_gt(p.encounters.size(), 2, "%s/%d: people are in it" % [kind, seed_i])
				assert_gt(p.containers.size(), 1, "%s/%d: things to loot" % [kind, seed_i])
	print("SITES | %d plans: %d with a secret, %d with a shortcut, %d drops; set-pieces %s" % [plans, secrets, shortcuts, drops, pieces])
	assert_gt(secrets, floori(plans * 0.8), "nearly every plan has a secret room")
	assert_gt(shortcuts, floori(plans * 0.8), "nearly every plan has a way from the boss back out")
	# a ledge over a lower room in a fair share of plans (5 of 96 before the drop was looked for on
	# its own)
	assert_gt(drops, floori(plans * 0.3), "a drop in a fair share of plans (%d of %d)" % [drops, plans])


func test_a_plan_is_the_same_every_time_and_a_seed_changes_it() -> void:
	var a := SitePlan.make(_def("cave", 7, "large"))
	var b := SitePlan.make(_def("cave", 7, "large"))
	var c := SitePlan.make(_def("cave", 8, "large"))
	assert_eq(a.fingerprint(), b.fingerprint(), "the same def is the same place")
	assert_ne(a.fingerprint(), c.fingerprint(), "another seed is another place")


func test_the_rock_is_the_same_every_time() -> void:
	var p := SitePlan.make(_def("crypt", 3, "medium"))
	var one: Array = SiteField.build(p.ops, p.bounds, 0.6, p.site_seed, 0.12, [])
	var two: Array = SiteField.build(p.ops, p.bounds, 0.6, p.site_seed, 0.12, [])
	assert_gt(one.size(), 0, "the rock has chunks")
	assert_eq(var_to_bytes(one).size(), var_to_bytes(two).size())
	assert_eq(str(one.map(func(ch: Dictionary) -> String: return var_to_bytes(ch["verts"]).hex_encode().md5_text())),
			str(two.map(func(ch: Dictionary) -> String: return var_to_bytes(ch["verts"]).hex_encode().md5_text())), "identical vertices")


## The showcases, walked into through Interiors: built, stood on, every room on one navigation mesh
## with the way in, and left through the way out.
func test_the_showcase_insides_are_built_walkable_and_left() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for id in SHOWCASE:
		assert_true(ContentDB.has(id), "%s is content" % id)
		var door := Door.new()
		tree.root.add_child(door)
		door.global_position = Vector3(110, 5, 100)
		door.interior_id = id
		assert_true(Interiors.enter(id, door), "%s can be entered" % id)
		await tree.process_frame
		await tree.physics_frame
		var root: Node = Interiors._loaded.get(id)
		var site := root as SiteInterior
		assert_true(site != null and site.is_built, "%s is built" % id)
		if site == null:
			continue
		# standing on the rock at the way in
		var space := player.get_world_3d().direct_space_state
		var at := player.global_position
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0, 1))
		assert_false(hit.is_empty(), "%s: a floor under the way in" % id)
		if not hit.is_empty():
			assert_true(absf(at.y - (hit["position"] as Vector3).y) < 0.3, "%s: standing on it (%.2f m)" % [id, at.y - (hit["position"] as Vector3).y])
		# the way in looks into its room: from eye height, the first room's far side is metres away
		var ent := site.get_node("Entrance") as Node3D
		var eye := ent.global_position + Vector3.UP * 1.65
		var look := eye - ent.global_transform.basis.z * 30.0
		var seen := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, look, 1))
		var clear := 30.0 if seen.is_empty() else eye.distance_to(seen["position"])
		var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + Vector3.UP * 20.0, 1))
		print("SITE WAY IN | %s | at %s facing %s: %.1f m clear ahead, roof %s" % [id, site.to_local(ent.global_position),
				-ent.global_transform.basis.z, clear, "over" if not up.is_empty() else "none"])
		assert_gt(clear, 3.0, "%s: the way in looks into its room" % id)
		assert_false(up.is_empty(), "%s: the way in is under the roof, inside" % id)
		# every room's floor is rock under its middle, with room to stand over it
		for r in site.plan.rooms:
			var c := site.to_global(r["centre"])
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.5, c + Vector3.DOWN * 2.0, 1))
			var head := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.3, c + Vector3.UP * 2.1, 1))
			assert_false(down.is_empty(), "%s: room %s has a floor" % [id, r["id"]])
			assert_true(head.is_empty(), "%s: room %s has headroom at its middle" % [id, r["id"]])
		var report := _walk(site)
		print("SITE | %s | %d rooms, %d links, %d chunks, %d tris, %d lights, %d foes, %d containers | reached %s | main %.0f ms" % [
			id, site.plan.rooms.size(), site.plan.links.size(), site.chunks.size(), _tris(site), site.dress.lights.size(),
			site.dress.spawner.living.size(), site.plan.containers.size(), report["reached"], site.main_us / 1000.0])
		# no chunk of rock is reached by more lights than Compatibility draws on one object (12)
		var worst := 0
		for ch in site.chunks:
			var box := AABB((ch["verts"] as PackedVector3Array)[0], Vector3.ZERO)
			for v in ch["verts"]:
				box = box.expand(v)
			var n := 0
			for l in site.dress.lights:
				var o := l as OmniLight3D
				if o != null and o.visible and box.grow(o.omni_range).has_point(o.position):
					n += 1
			worst = maxi(worst, n)
		print("SITE LIGHTS | %s | at most %d lights on one chunk" % [id, worst])
		assert_true(worst <= 12, "%s: at most 12 lights reach one chunk (%d)" % [id, worst])
		assert_eq(report["unreached"], [], "%s: every room is walkable from the way in on the navigation mesh" % id)
		assert_gt(site.dress.spawner.living.size(), 4, "%s: foes stand in it" % id)
		assert_true(site.find_child("BossArena", true, false) != null, "%s: the boss has an arena" % id)
		# out through the way out
		var way_out := site.find_child("WayOut", true, false) as Door
		assert_true(way_out != null, "%s: a way out" % id)
		if way_out != null:
			way_out.interact(player)
			assert_false(Interiors.in_interior(), "%s: the way out leads out" % id)
			assert_near(player.global_position.x, 110.0, 0.01, "%s: beside the door it came in by" % id)
		Interiors.unload_all()
		door.queue_free()
		await tree.process_frame


## Saved inside and loaded: back inside, standing at the way in, and able to leave.
func test_a_game_saved_inside_a_site_comes_back_inside() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var id: String = SHOWCASE[0]
	assert_true(Interiors.enter(id))
	await tree.process_frame
	var data: Dictionary = JSON.parse_string(JSON.stringify(Interiors.to_save()))
	var inside := player.global_position
	Interiors.exit()
	Interiors.unload_all()
	await tree.process_frame
	player.global_position = inside
	Interiors.from_save(data)
	await tree.process_frame
	await tree.physics_frame
	assert_true(Interiors.in_interior(), "back inside")
	var site := Interiors._loaded.get(id) as SiteInterior
	assert_true(site != null and site.is_built, "built again")
	var space := player.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.5, player.global_position + Vector3.DOWN * 3.0, 1))
	assert_false(hit.is_empty(), "standing on the floor after the load")
	assert_true(Interiors.exit(), "and can leave")


## Built paced, every piece of the build on the main thread is within a frame's budget (the rock is
## worked out on a worker thread), and the result is the build made at once.
func test_a_paced_build_keeps_every_piece_short_and_builds_the_same() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var def := ContentDB.get_def(SHOWCASE[1]).duplicate(true)
	var at_once := SiteInterior.new()
	at_once.def_override = def
	at_once.paced_override = 0
	tree.root.add_child(at_once)
	await tree.process_frame
	var paced := SiteInterior.new()
	paced.def_override = def
	paced.paced_override = 1
	# a fresh shell, worked out on the worker thread rather than read from the cache
	SiteInterior._ready_shells.clear()
	DirAccess.remove_absolute("%s/%s.bin" % [SiteInterior.CACHE_DIR, SiteInterior.cache_key(SitePlan.make(def))])
	tree.root.add_child(paced)
	var frames := 0
	while not paced.is_built and frames < 3000:
		await tree.process_frame
		frames += 1
	assert_true(paced.is_built, "the paced build finished (%d frames)" % frames)
	print("SITE PACED | %d frames, main thread %.1f ms, longest piece %.1f ms at %s, longest foe stood up %.1f ms (at once: %.1f ms)" %
			[frames, paced.main_us / 1000.0, paced.longest_piece_us / 1000.0, paced.longest_piece_at, paced.longest_foe_us / 1000.0, at_once.main_us / 1000.0])
	assert_true(paced.longest_piece_us < 40000, "no piece of the build is a long frame (%.1f ms)" % (paced.longest_piece_us / 1000.0))
	assert_eq(_shape(paced), _shape(at_once), "the same place either way")
	at_once.queue_free()
	paced.queue_free()
	await tree.process_frame


## Scathe Fort's outside, raised on flat ground: walls that stop you, a gate you walk through, stairs
## up to a walkway you can stand on, towers with room on top, the keep's door, and its garrison.
func test_the_fort_stands_with_a_gate_a_walkway_and_a_garrison() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var def := ContentDB.get_def("core:poi/scathe_fort")
	var entry := {"place_id": "core:poi/scathe_fort", "pos": [0.0, 0.0, 0.0], "radius_flat_m": 30.0, "radius_level_m": 30.0}
	var d := PoiDressing.raise(entry, def)
	tree.root.add_child(d)
	await tree.process_frame
	await tree.physics_frame
	assert_true(d.finished, "the fort is built")
	var space := d.get_world_3d().direct_space_state
	# the gate: nothing across it at chest height, walls either side of it
	var door := d.find_child("Door_scathe_undercroft", true, false) as Door
	assert_true(door != null, "the keep has its door to the undercroft")
	var walls := 0
	var through := 0
	for i in 36:
		var a := TAU * float(i) / 36.0
		var dir := Vector3(sin(a), 0.0, cos(a))
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3.UP * 1.2 + dir * 12.0, Vector3.UP * 1.2 + dir * 30.0, 1))
		if h.is_empty():
			through += 1
		else:
			walls += 1
	print("FORT | %d of 36 bearings walled, %d open (the gate)" % [walls, through])
	assert_gt(walls, 28, "walled round")
	assert_gt(through, 0, "and a gate to walk through")
	# the walkway: the garrison walks it, so it is there under their feet
	var garrison := d.find_child("Garrison", true, false) as EnemySpawner
	assert_true(garrison != null and garrison.living.size() >= 8, "a garrison of %d" % (garrison.living.size() if garrison else 0))
	var high := 0
	if garrison != null:
		for e in garrison.living:
			# the test has no ground: only those up on the walls and towers stand on the fort itself
			if e.global_position.y > 3.0:
				var under := space.intersect_ray(PhysicsRayQueryParameters3D.create(e.global_position + Vector3.UP * 0.5, e.global_position + Vector3.DOWN * 2.0, 1))
				assert_false(under.is_empty(), "%s stands on the wall" % e.enemy_id)
				high += 1
	assert_gt(high, 3, "archers and the walls' walkers stand up on the walls and towers")
	# the walkway joined to the yard: a navigation mesh over the fort's own collision and the ground
	var nm := SiteInterior.navmesh_settings()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.filter_baking_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 30, 80))
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, d)
	var ground := PlaneMesh.new()
	ground.size = Vector2(80, 80)
	src.add_faces(ground.get_faces(), Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var yard := Vector3(0.0, 0.0, 0.0)
	var on_wall := Vector3.INF
	if garrison != null:
		for e in garrison.living:
			if e.patrol_points.size() > 0:
				on_wall = d.to_local(e.patrol_points[0])
				break
	assert_true(on_wall != Vector3.INF, "someone walks the walls")
	if on_wall != Vector3.INF:
		var ok := _joined(nm, yard, on_wall)
		if not ok:
			# what the mesh has, by height, to see where the way up breaks
			var bands := {}
			var verts := nm.get_vertices()
			for i in nm.get_polygon_count():
				var cy := 0.0
				for vi in nm.get_polygon(i):
					cy += verts[vi].y
				cy /= float(nm.get_polygon(i).size())
				bands[int(round(cy))] = int(bands.get(int(round(cy)), 0)) + 1
			print("FORT NAV | walker at %s, polygons by height %s" % [on_wall, bands])
		assert_true(ok, "the walkway is reached from the yard up the stairs")
	# the stone weathered: the walls in site_stone's shader, every vertex carrying the ground under it
	var walls_mi := d.find_child("Walls", true, false) as MeshInstance3D
	assert_true(walls_mi != null, "the walls are drawn")
	if walls_mi != null:
		var sm := walls_mi.material_override as ShaderMaterial
		assert_true(sm != null and sm.shader.resource_path.ends_with("site_stone.gdshader"), "the walls are weathered stone")
		var arrays := walls_mi.mesh.surface_get_arrays(0)
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		assert_eq(uv2.size(), (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "every vertex carries the ground's height")
		assert_true(not uv2.is_empty() and uv2[0].y == 1.0, "and says so")
	for part in ["Portcullis", "Keep", "TroddenEarth", "Fallen", "Pentice"]:
		assert_true(d.find_child(part, true, false) != null, "the fort has its %s" % part)
	d.queue_free()
	await tree.process_frame


## Every kind, several seeds, built and walked on its navigation mesh from the way in to every room:
## an author never hunts for a seed that can be walked (only the showcases were walked, and 13 of 14
## mines tried left rooms off the mesh).
func test_every_kind_is_walked_end_to_end() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var bad: Array = []
	var built := 0
	for kind in SiteKinds.KINDS:
		for seed_i in [811, 1031, 1044]:
			var def := _def(kind, seed_i)
			var site := SiteInterior.new()
			site.def_override = def
			site.paced_override = 0
			tree.root.add_child(site)
			await tree.process_frame
			built += 1
			var report := _walk(site)
			if not (report["unreached"] as Array).is_empty():
				var nm := SiteInterior.navmesh_settings()
				NavigationServer3D.bake_from_source_geometry_data(nm, site.source_geometry())
				var why: Array = []
				for rid in report["unreached"]:
					var r := site.plan.room(str(rid))
					var ways: Array = []
					for li in r["links"]:
						var l: Dictionary = site.plan.links[li]
						var pts: Array = l["points"]
						var a: Vector3 = pts[0]
						var b: Vector3 = pts[-1]
						var run := Vector2(b.x - a.x, b.z - a.z).length()
						var mid: Vector3 = (a + b) * 0.5
						ways.append("%s %s-%s rise %.1f/%.1f mid %s" % [l["kind"], l["a"], l["b"], b.y - a.y, run,
								"on" if _near_poly(nm, mid) < 1.5 else "OFF(%.1f)" % _near_poly(nm, mid)])
					why.append("%s[%s %s, centre %s] via %s" % [rid, r["role"], r["set_piece"],
							"on" if _near_poly(nm, r["centre"]) < 1.5 else "OFF", ways])
				bad.append("%s/%d: %s" % [kind, seed_i, why])
			site.queue_free()
			await tree.process_frame
	for b in bad:
		print("SITE WALK | " + str(b))
	print("SITE WALK | %d of %d built sites walked to every room" % [built - bad.size(), built])
	assert_eq(bad.size(), 0, "every kind walked end to end")


static func _near_poly(nm: NavigationMesh, p: Vector3) -> float:
	var verts := nm.get_vertices()
	var best := INF
	for i in nm.get_polygon_count():
		best = minf(best, _poly_distance(verts, nm.get_polygon(i), p))
	return best


## How far `p` is from a navigation polygon: across (0 inside it, else to its nearest edge) and
## twice how far above or below it. A flat vaulted floor bakes into a few big polygons whose middles
## are far from any point on them, so matching by the polygons' middles lost whole rooms.
static func _poly_distance(verts: PackedVector3Array, poly: PackedInt32Array, p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	var inside := true
	var sign_seen := 0.0
	var edge := INF
	var y := 0.0
	for k in poly.size():
		var a3 := verts[poly[k]]
		var b3 := verts[poly[(k + 1) % poly.size()]]
		y += a3.y
		var a := Vector2(a3.x, a3.z)
		var b := Vector2(b3.x, b3.z)
		var c := (b - a).cross(q - a)
		if absf(c) > 0.0001:
			if sign_seen == 0.0:
				sign_seen = signf(c)
			elif signf(c) != sign_seen:
				inside = false
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		edge = minf(edge, (a + ab * t).distance_to(q))
	y /= float(poly.size())
	return (0.0 if inside else edge) + absf(y - p.y) * 0.5


## A site whose rooms are written out, with a ledge asked for and a secret: built (the ledge's
## dressing read a key the plan never wrote), and every room reached from the way in.
func test_a_written_site_with_a_ledge_is_built_and_reached() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for seed_i in [1043, 1044, 1045, 1046, 1047]:
		var def := {"id": "core:interior/test_written_%d" % seed_i, "name": "Written", "danger": 2,
				"site": {"kind": "cave", "seed": seed_i, "region": "hearthvale", "boss": "core:boss/barrow_reeve",
				"rooms": [{"id": "porch", "role": "entrance", "size": "medium"},
						{"id": "stair", "role": "passage", "size": "small", "drop": -3.0},
						{"id": "hall", "role": "hall", "size": "large", "set_piece": "ledge"},
						{"id": "den", "role": "camp", "size": "large"},
						{"id": "throne", "role": "boss", "size": "huge", "set_piece": "boss_arena"}]}}
		var p := SitePlan.make(def)
		var reach := p.reach()
		assert_eq((reach["from"] as Array).size(), p.rooms.size(), "%d: every written room reached %s" % [seed_i, p.problems])
		if seed_i == 1043:
			var site := SiteInterior.new()
			site.def_override = def
			site.paced_override = 0
			tree.root.add_child(site)
			await tree.process_frame
			assert_true(site.is_built, "a written site with a ledge is built")
			var report := _walk(site)
			assert_eq(report["unreached"], [], "and walked to every room")
			site.queue_free()
			await tree.process_frame


## The fort's garrison and a site's foes stay dead when the place is raised again, until a rest.
func test_the_fallen_stay_dead_until_a_rest() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var def := ContentDB.get_def("core:poi/scathe_fort")
	var entry := {"place_id": "core:poi/scathe_fort", "pos": [0.0, 0.0, 0.0], "radius_flat_m": 30.0, "radius_level_m": 30.0}
	var d := PoiDressing.raise(entry, def)
	tree.root.add_child(d)
	await tree.process_frame
	var g := d.find_child("Garrison", true, false) as EnemySpawner
	assert_true(g != null and g.living.size() > 2, "a garrison stands")
	if g == null or g.living.size() < 3:
		d.queue_free()
		return
	var whole := g.living.size()
	var victims: Array[String] = []
	for e in [g.living[0], g.living[2]]:
		var key := str((e as Enemy).get_meta("site_key", ""))
		assert_ne(key, "", "each has a place in the garrison")
		(e as Enemy).died.emit(null)
		victims.append(key)
		assert_true(SiteFallen.is_fallen(key), "%s is remembered dead" % key)
	d.queue_free()
	await tree.process_frame
	# raised again: the two are not there
	var d2 := PoiDressing.raise(entry, def)
	tree.root.add_child(d2)
	await tree.process_frame
	var g2 := d2.find_child("Garrison", true, false) as EnemySpawner
	assert_eq(g2.living.size(), whole - 2, "the dead stay dead when the fort is raised again")
	for e in g2.living:
		assert_false(victims.has(str(e.get_meta("site_key", ""))), "and nobody stands in a dead man's place")
	d2.queue_free()
	await tree.process_frame
	# a rest brings them back
	SiteFallen._on_rested("test")
	for key in victims:
		assert_false(SiteFallen.is_fallen(key), "%s stands again after a rest" % key)
	var d3 := PoiDressing.raise(entry, def)
	tree.root.add_child(d3)
	await tree.process_frame
	assert_eq((d3.find_child("Garrison", true, false) as EnemySpawner).living.size(), whole, "the whole garrison after a rest")
	d3.queue_free()
	await tree.process_frame
	# inside: a foe of the undercroft killed is not there when it is built again
	var site_def := ContentDB.get_def(SHOWCASE[1])
	var s1 := SiteInterior.new()
	s1.def_override = site_def
	s1.paced_override = 0
	tree.root.add_child(s1)
	await tree.process_frame
	var inside := s1.dress.spawner.living.size()
	var one: Enemy = null
	for e in s1.dress.spawner.living:
		if e.has_meta("site_key"):
			one = e
			break
	assert_true(one != null, "the undercroft's foes have their places")
	if one != null:
		one.died.emit(null)
	s1.queue_free()
	await tree.process_frame
	var s2 := SiteInterior.new()
	s2.def_override = site_def
	s2.paced_override = 0
	tree.root.add_child(s2)
	await tree.process_frame
	assert_eq(s2.dress.spawner.living.size(), inside - 1, "the one killed inside stays dead")
	s2.queue_free()
	SiteFallen._on_rested("test")
	await tree.process_frame


## The Kilnway's outside, raised on flat ground: a lava tube's mouth open to walk into from its
## trench, the throat bending away to the door, a floor under the door and a roof over it.
func test_the_lava_mouth_is_open_to_walk_into() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var def := ContentDB.get_def("core:poi/the_kilnway")
	var entry := {"place_id": "core:poi/the_kilnway", "pos": [0.0, 0.0, 0.0], "radius_flat_m": 34.0, "radius_level_m": 34.0}
	var d := PoiDressing.raise(entry, def)
	tree.root.add_child(d)
	await tree.process_frame
	await tree.physics_frame
	var door := d.find_child("Door_the_kilnway", true, false) as Door
	assert_true(door != null, "the mouth has its door")
	for part in ["TubeGround", "GlassLip", "Throat", "Headwall", "Embers", "Hook", "Shards", "Cinders", "RoofFall"]:
		assert_true(d.find_child(part, true, false) != null, "the mouth has its %s" % part)
	var den := d.find_child("the_mouth", true, false) as Node3D
	assert_true(den != null, "the mouth is marked")
	if door != null and den != null:
		var space := d.get_world_3d().direct_space_state
		var into := Vector3(den.position.x, 0.0, den.position.z).normalized()
		# from the trench's floor up to the mouth and into the throat, chest high, nothing in the way
		var from := d.to_global(den.position - into * 9.0 + Vector3.UP * 1.2)
		var to := d.to_global(den.position + Vector3.UP * 1.2)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
		assert_true(hit.is_empty(), "the way in is open from the trench into the throat (hit at %s)" % [hit.get("position", "")])
		# the door round the bend: a floor under it, a roof over it, and the throat open back from it
		var at := door.global_position
		assert_false(space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 1.0, 1)).is_empty(), "a floor at the door")
		assert_false(space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.UP * 8.0, 1)).is_empty(), "a roof over the door")
		var view: Vector3 = d.to_global(door.get_meta("view_from", door.position))
		var back := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.4, view + Vector3.UP * 1.4, 1))
		assert_true(back.is_empty(), "the door is seen from up the throat")
	d.queue_free()
	await tree.process_frame


# --- helpers ------------------------------------------------------------------------------------------

static func _tris(site: SiteInterior) -> int:
	var n := 0
	for ch in site.chunks:
		n += floori((ch["indices"] as PackedInt32Array).size() / 3.0)
	return n


static func _shape(site: SiteInterior) -> String:
	var parts: Array = []
	for n in site.find_children("*", "", true, false):
		if n is Enemy:
			# foes walk once stood up: where they were stood is the build's
			parts.append("Enemy@%s" % (site.to_local((n as Enemy).spawn_position) * 10.0).round())
		elif n is MeshInstance3D or n is CollisionShape3D or n is Light3D:
			parts.append("%s@%s" % [n.get_class(), ((n as Node3D).position * 10.0).round()])
	parts.sort()
	return str(parts.size()) + ":" + str(parts).md5_text()


## Bakes the site's navigation mesh and walks its polygons from the way in: which rooms have a
## polygon near their middle's clear floor that is joined to the way in's.
func _walk(site: SiteInterior) -> Dictionary:
	var nm := SiteInterior.navmesh_settings()
	NavigationServer3D.bake_from_source_geometry_data(nm, site.source_geometry())
	var reached: Array = []
	var unreached: Array = []
	for r in site.plan.rooms:
		var goal: Vector3 = r["centre"]
		if _joined(nm, site.plan.entrance, goal, SiteInterior.passage_links(site.plan)):
			reached.append(r["id"])
		else:
			unreached.append(r["id"])
	return {"reached": reached.size(), "unreached": unreached}


## Whether two points (local to the navigation mesh) stand on polygons joined by shared edges.
static func _joined(nm: NavigationMesh, a: Vector3, b: Vector3, links: Array = []) -> bool:
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
			var d := _poly_distance(verts, nm.get_polygon(i), p)
			if d < best_d:
				best_d = d
				best = i
		return best if best_d < 1.5 else -1
	var start: int = nearest.call(a)
	var goal: int = nearest.call(b)
	if start < 0 or goal < 0:
		return false
	# the navigation's links (SiteInterior.passage_links): a way from one polygon to another
	var jumps := {}
	for w in links:
		var pa: int = nearest.call(w[0])
		var pb: int = nearest.call(w[1])
		if pa < 0 or pb < 0:
			continue
		jumps.get_or_add(pa, []).append(pb)
		if bool(w[2]):
			jumps.get_or_add(pb, []).append(pa)
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
		for j in jumps.get(i, []):
			if not seen.has(j):
				seen[j] = true
				todo.append(j)
	return false
