extends TestCase
## A world's services (GameServices: the law, the market, the people, the quests' foes and finds)
## are inside that world and go when it goes. Each system's `ensure()` put them under the current
## scene, which under the test runner is the runner, so every world a test stood up left them
## behind, enabled. A left-over QuestFoes stood the Naming's ash-wights at the Choir itself, and
## the next test's own QuestFoes counted them as already standing and stood nothing
## (test_kill_places, main's full suite, 2026-09-25). They go with the world now, and while it
## stands they are left where they were made.

const WORLD_SCENE := "res://world/world.tscn"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _outside(root: Node) -> Array[String]:
	var out: Array[String] = []
	for group in ["quest_foes", "npc_registry", "npc_streamer", "place_discovery", "escorts", "crime_reports", "stealth", "crime"]:
		for n in _tree().get_nodes_in_group(group):
			if root == null or not root.is_ancestor_of(n):
				out.append(str(n.get_path()))
	return out


func test_a_world_s_services_stay_whole_and_go_with_it() -> void:
	if not FileAccess.file_exists("res://world/generated/world_manifest.json"):
		return
	var before := _outside(null)
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	var services := _tree().get_first_node_in_group("game_services")
	for i in 5:
		await _tree().process_frame
	assert_true(services != null, "the world installs its services")
	# while the world stands they are whole: nothing was moved, so nothing let go of what its
	# _ready took (the quest walker lost four quests when a first fix moved them in)
	var items := _tree().get_first_node_in_group("quest_items")
	assert_true(items != null and SaveSystem.participants.get(QuestItems.SECTION) == items,
			"the quests' finds are still saved with the game")
	_tree().root.remove_child(w)
	w.free()
	await _tree().process_frame
	var left := _outside(null).filter(func(p: String) -> bool: return not before.has(p))
	assert_true(left.is_empty(), "and none is left behind when it goes: %s" % ", ".join(left))
