extends TestCase
## Skerrow's large sites (docs/WORLD_LIFE_INTERIORS.md), walked the way test_sites.gd walks the
## showcases: Ghastow Undercroft under Old Ghastow's keep, Orrdun's bone-hall in the Wall, the caves
## under the Brakh's Drink, and (phase 2) Dunnow's halls in the Wall's foot, Ghaleld's workings and the
## Salt Cave under Oskel Gloup, and (the novel places) the Cellars of Corbie Stack and the Hag-Warren
## under the Unmade Giant. Each is entered through a door, stood in, every room reached on its
## navigation mesh from the way in, its foes and its boss's arena there, and left through the way out.
## Its quest's boss and its outside's door are the pack's own.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")
const SITES_TEST := preload("res://tests/unit/test_sites.gd")
## Each inside, its outside, and the boss its quest sends you down to.
const SITES := {
	"core:interior/ghastow_undercroft": ["core:poi/old_ghastow", "core:boss/gorrm_unroped", "core:quest/a_stone_before_the_death"],
	"core:interior/orrdun_bone_hall": ["core:poi/orrdun", "core:boss/keener_of_orrdun", "core:quest/the_verse_nobody_sang"],
	"core:interior/brakhs_drink_under": ["core:poi/brakhs_drink", "core:boss/kneeling_brakh", "core:quest/tokens_of_no_clan"],
	"core:interior/dunnow_halls": ["core:poi/dunnow", "core:boss/kadda_the_rasp", "core:quest/the_long_tally"],
	"core:interior/ghaleld_workings": ["core:poi/ghaleld", "core:boss/chained_brakh", "core:quest/iron_for_the_chain"],
	"core:interior/the_salt_cave": ["core:poi/oskel_gloup", "core:boss/haldo_the_lampman", "core:quest/the_second_light"],
	# the novel places (2026-10-04)
	"core:interior/corbie_cellars": ["core:poi/corbie_stack", "core:boss/annet_blackrent", "core:quest/the_black_rent"],
	"core:interior/hag_warren": ["core:poi/the_unmade_giant", "core:boss/mother_scree", "core:quest/the_unmade_giant"],
}
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


## The data: each inside names its outside and its boss, the outside leads to the inside (a keep or a
## delve's door), the boss drops what the quest asks you to take, and the quest kills it there.
func test_each_site_is_joined_up_in_the_pack() -> void:
	for id: String in SITES:
		var row: Array = SITES[id]
		var def := ContentDB.get_or_empty(id)
		assert_false(def.is_empty(), "%s is content" % id)
		var site: Dictionary = def.get("site", {})
		assert_eq(str(def.get("place", "")), str(row[0]), "%s is under %s" % [id, row[0]])
		assert_eq(str(site.get("boss", "")), str(row[1]), "%s's boss is %s" % [id, row[1]])
		var outside: Dictionary = ContentDB.get_or_empty(str(row[0])).get("site", {})
		assert_true(str(outside.get("interior", outside.get("keep", ""))) == id, "%s's door leads to %s" % [row[0], id])
		var boss := ContentDB.get_or_empty(str(row[1]))
		assert_false(boss.is_empty(), "%s is content" % row[1])
		assert_eq(str(boss.get("arena", "")), str(row[0]), "%s fights at %s" % [row[1], row[0]])
		var quest := ContentDB.get_or_empty(str(row[2]))
		var kills := false
		var takes := false
		for stage in quest.get("stages", []):
			for o in (stage as Dictionary).get("objectives", []):
				var ob: Dictionary = o
				kills = kills or (str(ob.get("type", "")) == "kill" and str(ob.get("target", "")) == str(row[1]) and str(ob.get("where", "")) == id)
				if str(ob.get("type", "")) == "collect":
					takes = takes or (boss.get("drops", []) as Array).has(str(ob.get("target", "")))
		assert_true(kills, "%s sends you down %s for %s" % [row[2], id, row[1]])
		assert_true(takes, "%s asks for what %s drops" % [row[2], row[1]])


## Built, stood on, every room on one navigation mesh with the way in, foes in it, the boss's arena,
## and a way out beside the door it was entered by.
func test_each_site_is_built_walkable_and_left() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var walker: Object = SITES_TEST.new()
	for id: String in SITES:
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
		var report: Dictionary = walker.call("_walk", site)
		print("SITE | %s | %d rooms, %d links, %d chunks, %d tris, %d lights, %d foes, %d containers | reached %s | main %.0f ms" % [
			id, site.plan.rooms.size(), site.plan.links.size(), site.chunks.size(), SITES_TEST._tris(site), site.dress.lights.size(),
			site.dress.spawner.living.size(), site.plan.containers.size(), report["reached"], site.main_us / 1000.0])
		assert_eq(report["unreached"], [], "%s: every room is walkable from the way in on the navigation mesh" % id)
		assert_gt(site.dress.spawner.living.size(), 4, "%s: foes stand in it" % id)
		assert_true(site.find_child("BossArena", true, false) != null, "%s: the boss has an arena" % id)
		var way_out := site.find_child("WayOut", true, false) as Door
		assert_true(way_out != null, "%s: a way out" % id)
		if way_out != null:
			way_out.interact(player)
			assert_false(Interiors.in_interior(), "%s: the way out leads out" % id)
			assert_near(player.global_position.x, 110.0, 0.01, "%s: beside the door it came in by" % id)
		Interiors.unload_all()
		door.queue_free()
		await tree.process_frame
	if walker is Node:
		(walker as Node).free()
