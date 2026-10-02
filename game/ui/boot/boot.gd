extends Node
## Boot: first scene. Waits for content, handles command-line modes, then hands off.
##   --smoke            run the smoke test (load every region and interior) and quit
##   --arena            load the flat combat test arena (tests/arena/arena.tscn)
##   --capture=<plan>   run a capture plan (screenshots / fly-through) and quit
##   --new-game         skip the main menu and start a new game with defaults
##   --load=<slot>      load a slot straight away
##   --flow=<dir>       attach the flow probe (tools_gd/flow_probe.gd) and then boot exactly as
##                      without it: the probe presses the buttons a player would and writes
##                      what it saw to <dir>. `./run.sh flow` runs it.
##   --tour=<dir>       attach the ground probe (tools_gd/ground_probe.gd): once a body stands, it is
##   --roads=<dir>      stood at every place (`./run.sh tour`) or walked down every road on the keys
##                      (`./run.sh roads`), and what the world did to it is written to <dir>
##   --npcs=<dir>       attach the people probe (tools_gd/npc_probe.gd): a town's people watched
##                      getting about it, and one house's (`./run.sh npcs`)
##   --click=<s>[:<b>]  attach the click probe (tools_gd/click_probe.gd): press the title's button <b>
##                      (New Game) <s> seconds after the menu is up, and say whether the game went on
##   --cpu=<dir>        attach the CPU probe (tools_gd/cpu_probe.gd): the main thread's time per frame
##                      on the title and, with --cpu-new=<style>, through a new game's opening
##   --benchmark        run the built-in benchmark (tools_gd/benchmark.gd, docs/BENCHMARK.md): the
##                      title, the Naming and a fixed flight through the world, timed, then quit

@onready var label: Label = $Label


func _ready() -> void:
	StartupTrace.step("boot scene: waiting for the content")
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	StartupTrace.step("content loaded")
	# never change scene from inside _ready: the tree is still building
	await get_tree().process_frame
	label.text = "Wickmere\n%d definitions in %d packs" % [ContentDB.all("region").size() + ContentDB.all("place").size(), ContentDB.packs.size()]
	var args := _user_args()
	if args.has("flow"):
		_attach_flow_probe(str(args["flow"]))
	if args.has("tour") or args.has("roads") or args.has("foes") or args.has("seats"):
		_attach_probe("res://tools_gd/ground_probe.gd", "GroundProbe")
	if args.has("npcs"):
		_attach_probe("res://tools_gd/npc_probe.gd", "NpcProbe")
	if args.has("cpu"):
		var cpu := _attach_probe("res://tools_gd/cpu_probe.gd", "CpuProbe")
		if cpu != null:
			cpu.set("out_dir", str(args["cpu"]))
	if args.has("click"):
		_attach_probe("res://tools_gd/click_probe.gd", "ClickProbe")
	if args.has("benchmark"):
		_attach_probe("res://tools_gd/benchmark.gd", "Benchmark")
	if args.has("smoke"):
		_run_smoke()
		return
	if args.has("arena"):
		_run_arena()
		return
	if args.has("capture"):
		_run_capture(args["capture"])
		return
	if args.has("new-game") or args.has("load"):
		_start_world(args)
		return
	if ResourceLoader.exists("res://ui/menus/main_menu.tscn"):
		get_tree().change_scene_to_file.call_deferred("res://ui/menus/main_menu.tscn")
	else:
		_start_world(args)


func _user_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			@warning_ignore("incompatible_ternary")
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _start_world(args: Dictionary) -> void:
	var world_status := WorldStatus.current()
	if not bool(world_status.get("playable", false)):
		# `--new-game` and `--load` on a copy with no world: say why on stdout for whoever typed
		# it, and go to the title, which says it on the screen with the command that builds it.
		print("[boot] %s %s Build it with: %s" % [str(world_status.get("title", "")),
				str(world_status.get("detail", "")), WorldStatus.BUILD_COMMAND])
		label.text += "\n" + str(world_status.get("title", ""))
		if ResourceLoader.exists("res://ui/menus/main_menu.tscn"):
			get_tree().change_scene_to_file.call_deferred("res://ui/menus/main_menu.tscn")
		return
	if ResourceLoader.exists("res://world/world.tscn"):
		if args.has("load"):
			GameState.set_flag("_pending_load_slot", str(args["load"]))
		elif args.has("new-game"):
			# a new game with defaults is still a new game: a name, a Calling, and the flag
			# GameServices starts the opening quest from
			if not GameState.has_flag("player_name"):
				GameState.set_flag("player_name", "Foundling")
			if not GameState.has_flag("player_calling"):
				var callings := ContentDB.all("calling")
				if not callings.is_empty():
					GameState.set_flag("player_calling", str(callings[0].get("id", "")))
			GameState.set_flag("new_game", true)
		# the same caption the menus put up: the world takes a while, and a dead screen while it
		# does reads as a hang
		UI.fade_to_black(0.0, "The Roll is read again, and your name is in it." if args.has("load")
				else "The Warden walks you out of the Hush. Keep up; she does not look back.")
		# deferred: _ready() is inside the tree's add/remove pass, where a scene swap is refused
		get_tree().change_scene_to_file.call_deferred("res://world/world.tscn")
	else:
		label.text += "\n(no world scene yet)"


## The probe lives at the root, outside every scene, so it survives the scene changes it is
## there to watch. Boot then carries on down the same road it takes with no arguments.
func _attach_flow_probe(out_dir: String) -> void:
	var probe := _attach_probe("res://tools_gd/flow_probe.gd", "FlowProbe")
	if probe != null:
		probe.set("out_dir", out_dir)


func _attach_probe(path: String, probe_name: String) -> Node:
	if not ResourceLoader.exists(path):
		Log.error("Boot", "probe missing: %s" % path)
		get_tree().quit(2)
		return null
	var probe: Node = (load(path) as GDScript).new()
	probe.name = probe_name
	get_tree().root.add_child.call_deferred(probe)
	return probe


func _run_smoke() -> void:
	if ResourceLoader.exists("res://tests/smoke/smoke_runner.tscn"):
		get_tree().change_scene_to_file.call_deferred("res://tests/smoke/smoke_runner.tscn")
	else:
		Log.error("Boot", "smoke runner missing")
		get_tree().quit(2)


func _run_arena() -> void:
	if ResourceLoader.exists("res://tests/arena/arena.tscn"):
		get_tree().call_deferred("change_scene_to_file", "res://tests/arena/arena.tscn")
	else:
		Log.error("Boot", "test arena missing")
		get_tree().quit(2)


func _run_capture(plan: String) -> void:
	if ResourceLoader.exists("res://tools_gd/capture_runner.tscn"):
		GameState.set_flag("_capture_plan", plan)
		get_tree().change_scene_to_file.call_deferred("res://tools_gd/capture_runner.tscn")
	else:
		Log.error("Boot", "capture runner missing")
		get_tree().quit(2)
