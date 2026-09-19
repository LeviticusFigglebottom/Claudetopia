extends Node
## Boot: first scene. Waits for content, handles command-line modes, then hands off.
##   --smoke            run the smoke test (load every region and interior) and quit
##   --capture=<plan>   run a capture plan (screenshots / fly-through) and quit
##   --new-game         skip the main menu and start a new game with defaults
##   --load=<slot>      load a slot straight away

@onready var label: Label = $Label


func _ready() -> void:
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	# never change scene from inside _ready: the tree is still building
	await get_tree().process_frame
	label.text = "Wickmere\n%d definitions in %d packs" % [ContentDB.all("region").size() + ContentDB.all("place").size(), ContentDB.packs.size()]
	var args := _user_args()
	if args.has("smoke"):
		_run_smoke()
		return
	if args.has("capture"):
		_run_capture(args["capture"])
		return
	if args.has("new-game") or args.has("load"):
		_start_world(args)
		return
	if ResourceLoader.exists("res://ui/menus/main_menu.tscn"):
		get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")
	else:
		_start_world(args)


func _user_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _start_world(args: Dictionary) -> void:
	if ResourceLoader.exists("res://world/world.tscn"):
		if args.has("load"):
			GameState.set_flag("_pending_load_slot", str(args["load"]))
		get_tree().change_scene_to_file("res://world/world.tscn")
	else:
		label.text += "\n(no world scene yet)"


func _run_smoke() -> void:
	if ResourceLoader.exists("res://tests/smoke/smoke_runner.tscn"):
		get_tree().change_scene_to_file("res://tests/smoke/smoke_runner.tscn")
	else:
		Log.error("Boot", "smoke runner missing")
		get_tree().quit(2)


func _run_capture(plan: String) -> void:
	if ResourceLoader.exists("res://tools_gd/capture_runner.tscn"):
		GameState.set_flag("_capture_plan", plan)
		get_tree().change_scene_to_file("res://tools_gd/capture_runner.tscn")
	else:
		Log.error("Boot", "capture runner missing")
		get_tree().quit(2)
