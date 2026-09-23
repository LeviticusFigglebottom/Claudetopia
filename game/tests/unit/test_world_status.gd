extends TestCase
## Whether there is a world to enter, and what the way in does when there is not.
##
## A copy of the game with no built world let New Game through to a grey void with the HUD up, and
## `./run.sh flow` passed it: every check it made was about the screen and the body, and none was
## about the ground. These hold each state the disk can be in against the verdict and against the
## title screen and the world themselves: the world missing, the Terrain3D library missing, the
## terrain regions missing, the coarse ground asked for, and everything there.

const MENU := preload("res://ui/menus/main_menu.tscn")
const WORLD_SCENE := "res://world/world.tscn"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	WorldStatus.override = {}
	WorldStatus.force_fallback = false


## A machine with everything, with `changes` taken away.
static func _facts(changes := {}) -> Dictionary:
	var f := {"manifest": true, "runtime_maps": true, "cells": 1024, "cells_expected": 1024, "pois": true,
		"terrain_class": true, "terrain_regions": 16, "forced_fallback": false,
		"os": "Linux", "arch": "x86_64", "os_version": "6.8"}
	f.merge(changes, true)
	return f


func _button(root: Node, text: String) -> Button:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == text:
			return n as Button
		stack.append_array(n.get_children())
	return null


# --- the verdict, branch by branch ---------------------------------------------------------------

func test_everything_there_is_ready() -> void:
	var s := WorldStatus.evaluate(_facts())
	assert_eq(s["state"], "ready")
	assert_true(bool(s["playable"]))
	assert_eq(s["terrain"], "terrain3d")


func test_no_world_data_refuses_and_says_how_to_build_it() -> void:
	for missing in [{"manifest": false}, {"runtime_maps": false}, {"cells": 0}]:
		var s := WorldStatus.evaluate(_facts(missing))
		assert_eq(s["state"], "missing", str(missing))
		assert_false(bool(s["playable"]), "%s: no world is entered" % str(missing))
		assert_eq(s["command"], WorldStatus.BUILD_COMMAND, "with the command that builds it")
		var detail := str(s["detail"])
		assert_true(detail.contains("Python 3.11") and detail.contains("8 GB"), "and what it needs: %s" % detail)


func test_no_terrain3d_library_draws_the_coarse_ground_and_says_why() -> void:
	var arm := WorldStatus.evaluate(_facts({"terrain_class": false, "arch": "arm64"}))
	assert_eq(arm["state"], "fallback")
	assert_true(bool(arm["playable"]), "the country is there; only its full terrain is not")
	assert_eq(arm["terrain"], "fallback")
	assert_eq(arm["reason"], "plugin_missing")
	assert_true(str(arm["detail"]).contains("Linux on arm64"), "names the machine: %s" % arm["detail"])
	assert_true(str(arm["notice"]).contains("coarse ground"), "and has a word for the player once they can see")
	var old_mac := WorldStatus.evaluate(_facts({"terrain_class": false, "os": "macOS", "arch": "arm64", "os_version": "14.6.1"}))
	assert_true(str(old_mac["detail"]).contains("macOS 15 or later") and str(old_mac["detail"]).contains("14.6.1"),
			"a Mac too old for the frameworks is told so: %s" % old_mac["detail"])


func test_no_terrain_regions_draws_the_coarse_ground_and_says_how_to_build_them() -> void:
	var s := WorldStatus.evaluate(_facts({"terrain_regions": 0}))
	assert_eq(s["state"], "fallback")
	assert_true(bool(s["playable"]))
	assert_eq(s["reason"], "terrain_missing")
	assert_eq(s["command"], WorldStatus.BUILD_COMMAND)
	assert_true(str(s["notice"]).contains(WorldStatus.BUILD_COMMAND), "the notice names the command")


func test_the_coarse_ground_can_be_asked_for() -> void:
	var s := WorldStatus.evaluate(_facts({"forced_fallback": true}))
	assert_eq(s["state"], "fallback")
	assert_true(bool(s["playable"]))
	assert_eq(s["terrain"], "fallback")
	assert_eq(s["reason"], "forced")


func test_this_machine_is_ready_when_its_world_is_built() -> void:
	if not FileAccess.file_exists("res://world/generated/world_manifest.json"):
		return
	var s := WorldStatus.current()
	assert_eq(s["state"], "ready", str(s.get("detail", "")))


func test_the_runtime_heights_are_centred_where_the_block_mean_puts_them() -> void:
	# a 4096 grid at 2 m averaged 4 x 4 into 1024: each texel's centre is 1.5 full texels in
	assert_near(TerrainProvider.runtime_height_offset({"grid": 4096, "size_m": 8192, "runtime": {"grid": 1024}}), 3.0)
	assert_near(TerrainProvider.runtime_height_offset({"grid": 1024, "size_m": 8192, "runtime": {"grid": 1024}}), 0.0)
	assert_near(TerrainProvider.runtime_height_offset({"grid": 4096, "size_m": 8192,
			"runtime": {"grid": 1024, "height_offset_m": 1.25}}), 1.25, 0.001, "a manifest that says so wins")


# --- the title screen and the world, against a disk with nothing on it --------------------------

func test_the_title_refuses_a_world_that_is_not_there_and_says_why() -> void:
	WorldStatus.override = _facts({"manifest": false})
	var menu: Control = MENU.instantiate()
	_tree().root.add_child(menu)
	await _tree().process_frame
	for text in ["New Game", "Continue", "Load"]:
		var b := _button(menu, text)
		assert_true(b != null and b.disabled, "%s is shut" % text)
	assert_false(_button(menu, "Quit").disabled, "Quit is not")
	var notice: WorldNotice = menu.get("notice")
	assert_true(notice != null and notice.is_visible_in_tree(), "the sheet says why")
	if notice != null:
		assert_true(notice.text().contains(WorldStatus.BUILD_COMMAND), "with the command: %s" % notice.text())
		assert_true(notice.text().contains("Python 3.11"), "and what it needs")
	# pressed anyway -- by a pad, or by the load screen calling load_slot -- it still refuses
	assert_false(bool(menu.call("_world_is_there")), "the way in asks again at the door")
	menu.queue_free()
	await _tree().process_frame


func test_the_title_lets_a_built_world_in() -> void:
	WorldStatus.override = _facts()
	var menu: Control = MENU.instantiate()
	_tree().root.add_child(menu)
	await _tree().process_frame
	var new_game := _button(menu, "New Game")
	assert_true(new_game != null and not new_game.disabled, "New Game is open")
	assert_eq(menu.get("notice"), null, "and there is nothing to apologise for")
	assert_eq(menu.get("ground_line"), null, "not even in small print")
	assert_true(bool(menu.call("_world_is_there")))
	menu.queue_free()
	await _tree().process_frame


func test_the_title_lets_a_world_without_terrain3d_in_and_says_so_in_small_print() -> void:
	WorldStatus.override = _facts({"terrain_class": false})
	var menu: Control = MENU.instantiate()
	_tree().root.add_child(menu)
	await _tree().process_frame
	var new_game := _button(menu, "New Game")
	assert_true(new_game != null and not new_game.disabled, "New Game is open: there is a country to walk")
	assert_eq(menu.get("notice"), null, "no apology across the sheet")
	var line: Label = menu.get("ground_line")
	assert_true(line != null and line.text.contains("coarse"), "one small line says the ground will be coarse")
	menu.queue_free()
	await _tree().process_frame


func test_a_world_with_no_data_stands_down_instead_of_showing_a_void() -> void:
	WorldStatus.override = _facts({"manifest": false})
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	for i in 4:
		await _tree().process_frame
	assert_false(w.is_world_ready, "the world never says it is ready")
	var notice := w.find_child("WorldNotice", true, false) as WorldNotice
	assert_true(notice != null, "the screen says why")
	assert_true(notice != null and notice.back_button != null, "and offers the way back to the title")
	assert_eq(w.get_node("PlayerSpawn").get("player"), null, "nobody is stood in it")
	assert_eq(w.terrain_node, null, "and no terrain was loaded")
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame


func test_a_world_without_terrain3d_draws_the_coarse_ground_under_the_body() -> void:
	if not FileAccess.file_exists("res://world/generated/world_manifest.json"):
		return
	# what a Mac older than macOS 15, or Linux on arm64, finds: the class is not there
	WorldStatus.override = _facts({"terrain_class": false})
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	assert_eq(w.terrain_mode, "fallback", "the ground is drawn anyway")
	assert_eq(w.terrain_node, null, "without touching Terrain3D")
	var body: Node3D = w.get_node("PlayerSpawn").get("player")
	assert_true(body != null, "somebody stands in it")
	await _tree().physics_frame
	await _tree().physics_frame
	if body != null:
		var q := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 2.0,
				body.global_position + Vector3.DOWN * 40.0, 1 << 10)
		var hit := w.get_world_3d().direct_space_state.intersect_ray(q)
		assert_true(not hit.is_empty() and absf((hit["position"] as Vector3).y - body.global_position.y) < 1.0,
				"on ground that is really there")
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame


func test_a_built_world_draws_terrain3d_and_no_fallback() -> void:
	if WorldStatus.current().get("state", "") != "ready":
		return
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	assert_eq(w.terrain_mode, "terrain3d")
	assert_true(w.terrain_node != null and w.fallback == null, "Terrain3D, and nothing drawn beside it")
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame
