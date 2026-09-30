extends TestCase
## What going in and out leaves behind. The full quest walk (127 quests, every branch, one process)
## grew to 14 GB and was killed: a person's parts read for their jewellery and tattoos were kept for
## good, one reading (a megabyte a body) for every time the parts were loaded again, and a site's rock
## worked out ahead of anyone walking in was kept with the job that made it. A site walked into and
## out of again and again, the readings of meshes let go, and the shells worked out ahead, each come
## back to what they were.

const FakePlayer := preload("res://tests/fakes/fake_player.gd")
const SITE := "core:interior/the_kilnway"
const RIG_GLB := "res://assets/models/characters/humanoid_rig/humanoid_rig.glb"
const ROUNDS := 4
## What a round may leave above the first round's (allocator slack, a log line, a stat row).
const OBJECTS_SLACK := 150
const NODES_SLACK := 10
const STATIC_SLACK_MB := 24.0

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


func _counts() -> Dictionary:
	return {"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			"static_mb": OS.get_static_memory_usage() / 1048576.0}


func _round(tree: SceneTree) -> void:
	assert_true(Interiors.enter(SITE), "%s can be entered" % SITE)
	await tree.process_frame
	await tree.physics_frame
	var site := Interiors._loaded.get(SITE) as SiteInterior
	assert_true(site != null and site.is_built, "%s is built" % SITE)
	Interiors.exit()
	Interiors.unload_all()
	# the freed interior, its foes and the queued frees behind them
	for i in 4:
		await tree.process_frame
	await tree.physics_frame


## A site built, walked into, left and let go, over and over: the objects, the nodes and the memory
## come back to the first round's, and nothing is left orphaned.
func test_a_site_entered_and_left_again_and_again_comes_back_to_where_it_was() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	# the first round warms what is kept on purpose: its rock's shell, the shaders, the foes' parts
	await _round(tree)
	var base := _counts()
	for r in ROUNDS:
		await _round(tree)
	var now := _counts()
	print("SITE MEMORY | %d rounds | objects %d -> %d, nodes %d -> %d, orphans %d -> %d, static %.1f -> %.1f MB" % [ROUNDS,
			base["objects"], now["objects"], base["nodes"], now["nodes"], base["orphans"], now["orphans"], base["static_mb"], now["static_mb"]])
	assert_true(int(now["objects"]) <= int(base["objects"]) + OBJECTS_SLACK, "objects left behind: %d -> %d" % [base["objects"], now["objects"]])
	assert_true(int(now["nodes"]) <= int(base["nodes"]) + NODES_SLACK, "nodes left behind: %d -> %d" % [base["nodes"], now["nodes"]])
	assert_true(int(now["orphans"]) <= int(base["orphans"]), "nodes orphaned: %d -> %d" % [base["orphans"], now["orphans"]])
	assert_true(float(now["static_mb"]) <= float(base["static_mb"]) + STATIC_SLACK_MB,
			"memory left behind: %.1f -> %.1f MB" % [base["static_mb"], now["static_mb"]])
	assert_true(SiteInterior.held_shells() <= 2, "shells held: %d" % SiteInterior.held_shells())


## A body's reading for its jewellery and tattoos goes with its mesh: parts loaded again (a new mesh
## each time, as after everyone wearing them has gone with their cells) do not pile readings up.
func test_a_mesh_let_go_takes_its_reading_with_it() -> void:
	if not ResourceLoader.exists(RIG_GLB):
		return
	var inst := (load(RIG_GLB) as PackedScene).instantiate()
	var skel := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var src: MeshInstance3D = null
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).skin != null and (n as MeshInstance3D).mesh is ArrayMesh:
			src = n
			break
	assert_true(src != null, "the rig has a skinned body")
	if src == null:
		inst.free()
		return
	var mi := MeshInstance3D.new()
	mi.skin = src.skin
	var before := Adornment.carriers_held()
	for i in 6:
		mi.mesh = src.mesh.duplicate()
		assert_false(Adornment.carrier(mi, skel).is_empty(), "the body is read")
		assert_true(Adornment.carrier(mi, skel).get("id") != null, "and read once")
		mi.mesh = null
	# one more reading lets go of the ones whose meshes have gone
	mi.mesh = src.mesh.duplicate()
	Adornment.carrier(mi, skel)
	assert_true(Adornment.carriers_held() <= before + 1, "readings held: %d before, %d after seven meshes" % [before, Adornment.carriers_held()])
	mi.free()
	inst.free()


## Shells worked out ahead of anyone walking in (a site's entrance raised) are not kept with their
## jobs: once done they join the two kept in memory, and the rest are only on disk.
func test_shells_worked_out_ahead_are_not_kept_past_two() -> void:
	var keys: Array[String] = []
	for i in 3:
		var p := SitePlan.make({"id": "core:interior/test_leak_%d" % i, "name": "Test", "danger": 1,
				"site": {"kind": "cave", "seed": 900 + i, "size": "small", "region": "hearthvale"}})
		var key := "test_leak_%d" % i
		keys.append(key)
		SiteInterior._start_job(key, p)
	var tree := Engine.get_main_loop() as SceneTree
	for key in keys:
		for f in 3000:
			if WorkerThreadPool.is_task_completed(int((SiteInterior._jobs[key] as Dictionary)["task"])):
				break
			await tree.process_frame
	SiteInterior._collect()
	assert_true(SiteInterior._jobs.is_empty(), "the finished jobs are let go")
	assert_true(SiteInterior.held_shells() <= 2, "shells held: %d" % SiteInterior.held_shells())
	for key in keys:
		SiteInterior._ready_shells.erase(key)
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s.bin" % [SiteInterior.CACHE_DIR, key]))
