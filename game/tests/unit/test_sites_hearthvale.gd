extends TestCase
## Hearthvale's large sites (world life, phases 1 and 2): the Hound's Swallet (a cave under Hound
## Down, the Old Hound at the bottom), Knappers' Deep (a flint mine, the Gaffer at the far face), the
## throat under the Hum Stone (the Builders' vaults, the Digger-King at the bottom) and the crypt under
## Wake Barrow (the barrow-wives' halls, Ebba Crowle at the bottom) and the cellars under Wassail Knap
## (the press-masters' vaults, the Wassail King at the Mother Vat) and the undercroft of the Great Barn (the Kern Mother; both the novel round). Each is built,
## stood on, walked on its navigation mesh from the way in to every room, its boss in an arena, and
## left by its way out. The walk is test_sites.gd's.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")
const TS := preload("res://tests/unit/test_sites.gd")
const SWALLET := "core:interior/hounds_swallet"
const DEEP := "core:interior/knappers_deep"
const THROAT := "core:interior/hum_stone_throat"
const WAKE := "core:interior/wake_barrow_crypt"
const CELLARS := "core:interior/wassail_cellars"
const UNDERCROFT := "core:interior/great_barn_undercroft"
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
	await _built_walked_and_left(SWALLET, "core:boss/old_hound", ["throat", "pelters_camp", "bourne_lake", "the_den"])


func test_knappers_deep_is_built_walkable_and_left() -> void:
	await _built_walked_and_left(DEEP, "core:boss/the_gaffer", ["shaft_foot", "boys_camp", "the_fall", "night_gallery", "far_face"])


func test_the_hum_stones_throat_is_built_walkable_and_left() -> void:
	await _built_walked_and_left(THROAT, "core:boss/digger_king", ["the_cut", "diggers_camp", "the_niches", "grey_hall", "the_throat"])


func test_the_crypt_under_wake_barrow_is_built_walkable_and_left() -> void:
	await _built_walked_and_left(WAKE, "core:boss/barrow_wife", ["the_passage", "the_wake_hall", "the_washing_pool", "the_root", "the_ossuary", "the_hearth", "the_long_wake"])


func test_the_cellars_under_wassail_knap_are_built_walkable_and_left() -> void:
	await _built_walked_and_left(CELLARS, "core:boss/wassail_king", ["the_stair_foot", "the_pomace_cellar", "the_wassail_hall", "the_vat_hall", "the_press_spring", "the_kings_table", "the_mother_vat"])


func test_the_undercroft_of_the_great_barn_is_built_walkable_and_left() -> void:
	await _built_walked_and_left(UNDERCROFT, "core:boss/kern_mother", ["the_stair_foot", "the_granary", "the_reapers_loft", "the_drying_kiln", "the_tithe_vault", "the_sheaf_hall", "the_last_sheaf"])


func _built_walked_and_left(interior: String, boss: String, rooms: Array) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(ContentDB.has(interior), "%s is content" % interior)
	var door := Door.new()
	tree.root.add_child(door)
	door.global_position = Vector3(110, 5, 100)
	door.interior_id = interior
	assert_true(Interiors.enter(interior, door), "it can be entered")
	await tree.process_frame
	await tree.physics_frame
	var site := Interiors._loaded.get(interior) as SiteInterior
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
		# a collapsed shaft's middle is the mound of the roof that fell (the Fall, the stone's root):
		# that room is walked round, and its way through is the navigation walk's to prove
		if str(r.get("set_piece", "")) != "collapsed_shaft":
			assert_true(head.is_empty(), "room %s has headroom at its middle" % r["id"])
	for want in rooms:
		assert_true(ids.has(want), "%s has its %s" % [interior, want])
	var report := _walk(site)
	print("SITE | %s | %d rooms, %d links, %d chunks, %d lights, %d foes, %d containers | reached %s" % [
		interior, site.plan.rooms.size(), site.plan.links.size(), site.chunks.size(), site.dress.lights.size(),
		site.dress.spawner.living.size(), site.plan.containers.size(), report["reached"]])
	assert_eq(report["unreached"], [], "every room is walkable from the way in on the navigation mesh")
	assert_gt(site.dress.spawner.living.size(), 4, "foes stand in it")
	var boss_there := false
	for e in site.dress.spawner.living:
		boss_there = boss_there or (is_instance_valid(e) and str(e.get("enemy_id")) == boss)
	assert_true(boss_there, "%s waits in %s" % [boss, interior])
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
		if TS._joined(nm, site.plan.entrance, r["centre"], SiteInterior.passage_links(site.plan)):
			reached.append(r["id"])
		else:
			unreached.append(r["id"])
	return {"reached": reached.size(), "unreached": unreached}
