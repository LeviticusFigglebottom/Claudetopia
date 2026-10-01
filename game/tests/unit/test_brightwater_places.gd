extends TestCase
## Brightwater's world-life places (docs/WORLD_LIFE.md, phase 1): the people at its places stand at
## spots their places put down and not inside anything; Gull Holm's own builder stands the hinge-less
## door into its cellars; the new places raise what their defs promise (the Pennyfold charter-board
## and keep door, the Hush Hole's net and door, the Bleaching Green's frames, notice post and bleachers'
## spots, the Cadbrae Slate Cut's bench and the humming slate); and the three insides are built,
## walkable on their navigation meshes from the way in to every room, with a boss and a way out
## (the walk test_sites gives its showcases).

const FakePlayer := preload("res://tests/fakes/fake_player.gd")
const GENERATED := "res://world/generated"
const PEOPLE := {
	"core:npc/linnet_whitlow": "core:poi/bleaching_green",
	"core:npc/perrin_mull": "core:poi/bleaching_green",
	"core:npc/netta_knotley": "core:poi/net_field",
	"core:npc/cobb_knotley": "core:poi/net_field",
	"core:npc/kester_wick": "core:poi/eggers_camp",
	"core:npc/ottilie_gannet": "core:poi/standing_arches",
	"core:npc/barnet_slade": "core:poi/cadbrae_slate_cut",
	"core:npc/jessamy_slade": "core:poi/cadbrae_slate_cut",
	"core:npc/emmet_quarle": "core:poi/the_listening_post",
	"core:npc/crispin_tolley": "core:poi/counting_tower",
	"core:npc/ghedda_clanless": "core:poi/brindle_mill",
	"core:npc/abel_rowse": "core:poi/the_crown_drift",
	"core:npc/dorcas_pell": "core:poi/wash_stones",
	"core:npc/bryony_kettle": "core:poi/ness_market",
	"core:npc/silas_pask": "core:poi/ness_market",
}
const INSIDES := ["core:interior/pennyfold_undercroft", "core:interior/the_hush_hole", "core:interior/gull_holm_cellars",
		"core:interior/the_crown_drift", "core:interior/the_struck_barrow"]

var host: Node3D
var provider: TerrainProvider = null
var roads: Array = []
var built: Dictionary = {}
static var _warned := false


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	host = Node3D.new()
	host.name = "BrightwaterPlacesHost"
	_tree().root.add_child(host)
	if provider == null and FileAccess.file_exists("%s/pois.json" % GENERATED):
		provider = TerrainProvider.new()
		provider.load_data()
		roads = WorldPois.roads_from_disk()
		for e in JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED)):
			built[str((e as Dictionary).get("place_id", ""))] = e
	elif provider == null and not _warned:
		_warned = true
		print("  (world data missing: run ./run.sh world; the standing cases skip)")
	Interiors.current_id = ""
	GameState.current_interior_id = ""


func after_each() -> void:
	if Interiors.in_interior():
		Interiors.exit()
	Interiors.unload_all()
	_tree().root.remove_child(host)
	host.free()


## A place raised headless on its own, as the probe raises it: at its built entry, or where its def
## stands on the ground as it is (a place the world was not built with) with the pad its def asks for.
func _dress(place_id: String) -> PoiDressing:
	var def := ContentDB.get_or_empty(place_id)
	var entry: Dictionary = built.get(place_id, {})
	if entry.is_empty():
		var p: Array = def.get("position", [0, 0])
		var x := float(p[0])
		var z := float(p[1])
		entry = {"place_id": place_id, "pos": [x, provider.get_height(x, z), z],
				"radius_flat_m": PoiPreview.pad_radius(def)}
	var d := PoiDressing.raise(entry, def, false, provider, roads)
	host.add_child(d)
	var until := Time.get_ticks_msec() + 30000
	while not d.finished and Time.get_ticks_msec() < until:
		await _tree().process_frame
	return d


func test_every_person_has_words_and_works_at_their_place() -> void:
	for id in PEOPLE:
		var def := ContentDB.get_or_empty(str(id))
		assert_false(def.is_empty(), "%s is somebody" % id)
		assert_true(ContentDB.has(str(def.get("dialogue", ""))), "%s has something to say" % id)
		assert_eq(str(def.get("home_place", "")), str(PEOPLE[id]), "%s lives at %s" % [id, PEOPLE[id]])
		var there := false
		for e in def.get("schedule", []):
			there = there or str((e as Dictionary).get("place", "")) == str(PEOPLE[id])
		assert_true(there, "%s is at %s some of the day" % [id, PEOPLE[id]])
	# two people never work one spot at one hour
	for day in 7:
		for half in 48:
			var hour := float(half) * 0.5 + 0.25
			var taken: Dictionary = {}
			for id in PEOPLE:
				var entry := Schedules.entry_for_def(ContentDB.get_or_empty(str(id)), day, hour)
				if str(entry.get("spot", "")) == "":
					continue
				var key := "%s|%s" % [entry.get("place", ""), entry.get("spot", "")]
				assert_false(taken.has(key), "%s and %s both stand at '%s' at %.2f" % [taken.get(key, ""), id, entry.get("spot", ""), hour])
				taken[key] = id


func test_every_spot_they_work_is_put_down_and_nobody_stands_inside_anything() -> void:
	if provider == null:
		return
	var person := CapsuleShape3D.new()
	person.radius = 0.3
	person.height = 1.6
	var places: Dictionary = {}
	for id in PEOPLE:
		places[str(PEOPLE[id])] = true
	var looked := 0
	for place in places:
		var d: PoiDressing = await _dress(str(place))
		for i in 2:
			await _tree().physics_frame
		for id in PEOPLE:
			if str(PEOPLE[id]) != str(place):
				continue
			for e in ContentDB.get_or_empty(str(id)).get("schedule", []):
				var spot := str((e as Dictionary).get("spot", ""))
				var marker := d.find_child(spot, true, false)
				assert_true(marker is Node3D, "%s works at '%s' and %s puts no such marker down" % [id, spot, place])
				if marker != null:
					assert_true(marker.is_in_group(NpcRegistry.SPOT_GROUP), "'%s' at %s is somewhere a person stands" % [spot, place])
		var space := d.get_world_3d().direct_space_state
		for n in d.find_children("*", "Marker3D", true, false):
			if not n.is_in_group(NpcRegistry.SPOT_GROUP):
				continue
			looked += 1
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = person
			q.collision_mask = 1 << 0
			q.transform = Transform3D(Basis.IDENTITY, (n as Node3D).global_position + Vector3(0.0, 0.95, 0.0))
			var what: Array[String] = []
			for hit in space.intersect_shape(q, 4):
				var thing: Variant = (hit as Dictionary).get("collider")
				what.append(str((thing as Node).get_path()) if thing is Node else "something")
			assert_true(what.is_empty(), "%s: whoever works at '%s' stands inside %s" % [place, n.name, ", ".join(what)])
			assert_false(provider.is_water((n as Node3D).global_position.x, (n as Node3D).global_position.z),
					"%s: '%s' is on dry ground" % [place, n.name])
		d.queue_free()
	assert_gt(looked, 12, "the people's places put their spots down")


func test_the_places_stand_what_their_defs_promise() -> void:
	if provider == null:
		return
	# Gull Holm's door with no hinges, into its cellars, on the holm and not in the Mere
	var holm: PoiDressing = await _dress("core:poi/gull_holm")
	var doors := holm.find_children("*", "Door", true, false)
	assert_eq(doors.size(), 1, "Gull Holm has its door")
	if not doors.is_empty():
		var door := doors[0] as Door
		assert_eq(door.interior_id, "core:interior/gull_holm_cellars", "into the cellars")
		assert_false(provider.is_water(door.global_position.x, door.global_position.z), "standing on the holm")
	assert_true(holm.find_child("the_hinge_less_door", true, false) != null, "and the egg-collectors' chalk has a step to lie on")
	# the sites: a hook to start the quest, a door into the inside
	for pid in ["core:poi/pennyfold_keep", "core:poi/the_hush_hole", "core:poi/the_crown_drift", "core:poi/the_struck_barrow"]:
		var d: PoiDressing = await _dress(pid)
		var hook := d.find_child("Hook", true, false) as PoiTouch
		assert_true(hook != null and ContentDB.has(hook.dialogue_id), "%s has its hook" % pid)
		var in_door := d.find_children("*", "Door", true, false)
		assert_eq(in_door.size(), 1, "%s has its way in" % pid)
		d.queue_free()
	# the green: frames of linen, a notice post, the two bleachers' spots
	var green: PoiDressing = await _dress("core:poi/bleaching_green")
	assert_true(green.find_child("Linen", true, false) != null, "the Bleaching Green has cloth on its frames")
	assert_eq(green.find_children("*", "JobBoard", true, false).size(), 1, "and a notice post with day-work")
	for spot in ["the_frames", "the_lye_tubs"]:
		assert_true(green.find_child(spot, true, false) != null, "and '%s'" % spot)
	# phase 2's large sites: the drift's headframe, engine-house and chimney, spoil and shift-board; the
	# barrow's Needle with its names and brass cap, its portal and the night's people's marks
	var drift: PoiDressing = await _dress("core:poi/the_crown_drift")
	for what in ["Headframe", "EngineHouse", "Chimney", "Spoil", "sign_ShiftBoardPaint", "the_shaft_head", "the_count_house"]:
		assert_true(drift.find_child(what, true, false) != null, "the Crown Drift has %s" % what)
	drift.queue_free()
	var barrow: PoiDressing = await _dress("core:poi/the_struck_barrow")
	for what in ["TallyNeedle", "NeedlePlinth", "NeedleCap", "StruckNames", "Chalk", "Portal", "the_portal_step", "the_needle_foot"]:
		assert_true(barrow.find_child(what, true, false) != null, "the Struck Barrow has %s" % what)
	var needle := barrow.find_child("TallyNeedle", true, false) as MeshInstance3D
	var plinth := barrow.find_child("NeedlePlinth", true, false) as MeshInstance3D
	if needle != null and plinth != null:
		assert_gt(needle.get_aabb().end.y - plinth.get_aabb().position.y, 12.0, "the Needle stands tall enough to be seen across the Mere")
	barrow.queue_free()
	# the Wash-Stones: the spring's pool, the three dished stones, the linen, where Dorcas beats
	var wash: PoiDressing = await _dress("core:poi/wash_stones")
	for what in ["WashPool", "WashStones", "Dishes", "LinenBunting", "the_beating_stone"]:
		assert_true(wash.find_child(what, true, false) != null, "the Wash-Stones have %s" % what)
	wash.queue_free()
	# the slate cut: the black course, the bench, the humming slate where the thousand-book lies
	var cut: PoiDressing = await _dress("core:poi/cadbrae_slate_cut")
	for what in ["BlackCourse", "SlateStacks", "the_splitting_bench", "the_humming_slate", "the_face"]:
		assert_true(cut.find_child(what, true, false) != null, "the Cadbrae Slate Cut has %s" % what)


func test_the_insides_are_built_walkable_and_left() -> void:
	var tree := _tree()
	var player := FakePlayer.new()
	tree.root.add_child(player)
	player.global_position = Vector3(100, 5, 100)
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
		var until := Time.get_ticks_msec() + 90000
		while site != null and not site.is_built and Time.get_ticks_msec() < until:
			await tree.process_frame
		assert_true(site != null and site.is_built, "%s is built" % id)
		if site == null or not site.is_built or site.dress == null:
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
		var nm := SiteInterior.navmesh_settings()
		NavigationServer3D.bake_from_source_geometry_data(nm, site.source_geometry())
		var unreached: Array = []
		for r in site.plan.rooms:
			if not _joined(nm, site.plan.entrance, r["centre"]):
				unreached.append(r["id"])
		print("SITE | %s | %d rooms, %d links, %d chunks, %d lights, %d foes, %d containers | unreached %s" % [
			id, site.plan.rooms.size(), site.plan.links.size(), site.chunks.size(), site.dress.lights.size(),
			site.dress.spawner.living.size(), site.plan.containers.size(), unreached])
		assert_eq(unreached, [], "%s: every room is walkable from the way in" % id)
		assert_gt(site.dress.spawner.living.size(), 4, "%s: foes stand in it" % id)
		assert_true(site.find_child("BossArena", true, false) != null, "%s: the boss has an arena" % id)
		var way_out := site.find_child("WayOut", true, false) as Door
		assert_true(way_out != null, "%s: a way out" % id)
		if way_out != null:
			way_out.interact(player)
			assert_false(Interiors.in_interior(), "%s: the way out leads out" % id)
		Interiors.unload_all()
		door.queue_free()
		await tree.process_frame
	player.get_parent().remove_child(player)
	player.free()


## Whether two points (local to the navigation mesh) stand on polygons joined by shared edges
## (test_sites' own reading).
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
