extends Node
## Opens every Wickmere screen with believable data and screenshots it, so the UI can be
## looked at and fixed without a GPU or a world.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy --resolution 1280x720 res://tools_gd/ui_review.tscn -- --out=<dir>
##
## Arguments (after --): --out=<dir>  --only=<name[,name]>  --frames=<n>  --ui-scale=<0.8-1.4>
## (--ui-scale sets the "Size of the UI" for the run, not in the player's settings file)
##
## Where it can, the harness uses the real systems (Inventory, Equipment, Progression,
## Crafting, QuestLog) loaded with real content, so a screenshot is evidence the screen works
## and not just that it draws. Only the player, the dialogue runner and the merchant are
## stand-ins, because those streams are still being written.

const FAKES := "res://tools_gd/ui_review_fakes.gd"

var out_dir := "user://ui"
var only: PackedStringArray = []
var settle_seconds := 3.3
var _shots: Array[Dictionary] = []
var _index := 0
var _wait := 0.0
var _frames := 0
var _host: Control
var _current: Node = null
var _chest: Node = null
var _fakes: Node


func _ready() -> void:
	# full-screen screens pause the tree, so the harness has to keep running through it
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a.begins_with("--settle="):
			settle_seconds = float(a.substr(9))
		elif a.begins_with("--ui-scale="):
			Settings.persist = false
			Settings.set_value("accessibility", "ui_scale", float(a.substr(11)))
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not ContentDB.is_loaded:
		await ContentDB.loaded

	# A Control only picks up the viewport rect under a CanvasLayer, so screens get one.
	var host_layer := CanvasLayer.new()
	host_layer.layer = 0
	add_child(host_layer)
	# a plain sky-and-ground wash behind the HUD, so contrast can be judged against
	# something like the world rather than against the editor's clear colour
	var wash := ColorRect.new()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 0.46, 1.0])
	grad.colors = PackedColorArray([Color(0.52, 0.62, 0.74), Color(0.74, 0.76, 0.70),
			Color(0.44, 0.47, 0.32), Color(0.24, 0.26, 0.18)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	var sky := TextureRect.new()
	sky.texture = gtex
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	host_layer.add_child(wash)
	host_layer.add_child(sky)

	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host_layer.add_child(_host)

	_fakes = (load(FAKES) as GDScript).new()
	add_child(_fakes)
	_fakes.build()
	UI.gameplay_override = true

	_shots = _plan()
	print("[ui_review] %d shots -> %s" % [_shots.size(), out_dir])


func _plan() -> Array[Dictionary]:
	var all: Array[Dictionary] = [
		{"name": "main_menu", "scene": "res://ui/menus/main_menu.tscn"},
		{"name": "naming", "scene": "res://ui/character/naming.tscn"},
		{"name": "naming_styles", "scene": "res://ui/character/naming.tscn", "state": "styles"},
		{"name": "hud", "hud": true},
		{"name": "hud_combat", "hud": true, "state": "combat"},
		{"name": "dialogue", "dialogue": true},
		{"name": "gesture_wheel", "dialogue": true, "state": "gestures"},
		{"name": "pause", "menu": "pause"},
		{"name": "settings_video", "menu": "settings", "args": {"tab": "Video"}},
		{"name": "settings_graphics", "menu": "settings", "args": {"tab": "Graphics"}},
		{"name": "settings_graphics_light", "menu": "settings", "args": {"tab": "Graphics", "scroll": 700}},
		{"name": "settings_audio", "menu": "settings", "args": {"tab": "Audio"}},
		{"name": "settings_controls", "menu": "settings", "args": {"tab": "Controls"}},
		{"name": "settings_bindings", "menu": "settings", "args": {"tab": "Controls", "scroll": 330}},
		{"name": "settings_gameplay", "menu": "settings", "args": {"tab": "Gameplay"}},
		{"name": "settings_accessibility", "menu": "settings", "args": {"tab": "Accessibility"}},
		{"name": "save_load", "menu": "save_load", "args": {"mode": "save"}},
		{"name": "journal_quests", "menu": "journal", "args": {"tab": 0}},
		{"name": "journal_rumours", "menu": "journal", "args": {"tab": 1}},
		{"name": "journal_people", "menu": "journal", "args": {"tab": 2, "people": [
			"core:npc/wren_tallow", "core:npc/osric_pennywort", "core:npc/merrick_gosling",
			"core:npc/hesta_hollins", "core:npc/wardens_hesk"]}},
		{"name": "journal_bestiary", "menu": "journal", "args": {"tab": 3}},
		{"name": "journal_books", "menu": "journal", "args": {"tab": 4}},
		{"name": "book_reader", "menu": "book", "args": {"book_id": "core:book/the_falling_of_the_toll"}},
		{"name": "book_tome", "menu": "book", "args": {"book_id": "core:book/saying_ward"}},
		{"name": "inventory", "menu": "inventory"},
		{"name": "skills", "menu": "skills"},
		{"name": "sayings", "menu": "sayings"},
		{"name": "sayings_empty", "menu": "sayings", "state": "no_sayings"},
		{"name": "crafting_forge", "menu": "crafting", "args": {"station": "forge"}},
		{"name": "crafting_alchemy", "menu": "crafting", "args": {"station": "alembic"}},
		{"name": "crafting_enchanting", "menu": "crafting", "args": {"station": "name_table"}},
		{"name": "trade", "menu": "trade", "args": {"merchant_id": "core:npc/review_merchant"}},
		{"name": "deed", "menu": "deed", "args": {"property_id": "core:property/merrowby_cottage", "name": "The Cottage by the Toll", "place": "Merrowby", "price": 980}},
		{"name": "container", "menu": "container", "state": "chest"},
		{"name": "map", "menu": "map"},
	]
	if only.is_empty():
		return all
	var picked: Array[Dictionary] = []
	for s in all:
		if only.has(str(s["name"])):
			picked.append(s)
	return picked


func _process(delta: float) -> void:
	if _index >= _shots.size():
		# the two review saves go in the real save directory so the title menu has a Continue
		# to draw; left behind, they are what a player's Continue then loads
		_fakes.clear_slots()
		print("[ui_review] done")
		get_tree().quit(0)
		return
	if _wait > 0.0:
		# settle by wall clock and by frames: tweens run on delta, layout needs frames
		_wait -= delta
		_frames += 1
		if _wait <= 0.0 and _frames >= 4:
			_capture(str(_shots[_index]["name"]))
			_teardown()
			_index += 1
		return
	_frames = 0
	_setup(_shots[_index])
	_wait = settle_seconds


func _setup(shot: Dictionary) -> void:
	var state := str(shot.get("state", "default"))
	if shot.has("scene"):
		var path: String = shot["scene"]
		if not ResourceLoader.exists(path):
			push_warning("ui_review: missing %s" % path)
			return
		_current = (load(path) as PackedScene).instantiate()
		_host.add_child(_current)
		if _current.has_method("review_state"):
			_current.call("review_state", state)
	elif shot.get("hud", false):
		UI.show_hud()
		# the HUD has to exist before the world talks to it, or it misses the signals
		_fakes.set_state(state)
		if UI.hud() and UI.hud().has_method("review_state"):
			UI.hud().call("review_state", state)
		_fakes.fire_hud_events(state)
	elif shot.get("dialogue", false):
		UI.show_hud()
		var dlg := UI.show_dialogue()
		if dlg:
			_fakes.drive_dialogue(dlg, state)
	elif shot.has("menu"):
		if state != "default":
			_fakes.set_state(state)
		UI.show_hud()
		var args: Dictionary = shot.get("args", {}).duplicate()
		# The container screen is shown a real container, because a list of items with no
		# chest behind it would prove nothing about the screen that matters.
		if str(shot["menu"]) == "container":
			args["container"] = _review_chest()
		UI.open(str(shot["menu"]), args)


## A chest with a believable haul in it, standing in for the one you would have opened.
func _review_chest() -> Node:
	if _chest != null and is_instance_valid(_chest):
		_chest.queue_free()
	var chest := WorldContainer.new()
	chest.container_id = "review:container/kist"
	chest.owner_npc = "core:npc/ellard_wynstead"
	_host.add_child(chest)
	for pair in [["core:item/iron_sword", 1], ["core:item/bread", 3],
			["core:item/linen_bandage", 2], ["core:item/oak_round_shield", 1]]:
		if ContentDB.has(str(pair[0])):
			chest.inventory.add(str(pair[0]), int(pair[1]))
	chest.inventory.add_marks(64)
	_chest = chest
	return chest


func _teardown() -> void:
	if _chest != null and is_instance_valid(_chest):
		_chest.queue_free()
		_chest = null
	_fakes.set_state("default")
	EventBus.boss_defeated.emit("")
	UI.set_variant("warm")
	UI.close_all()
	if _current and is_instance_valid(_current):
		_current.queue_free()
	_current = null
	if UI.hud():
		UI.hide_hud()
	var dlg := UI.dialogue_layer
	for child in dlg.get_children():
		child.queue_free()
	UI._dialogue = null
	get_tree().paused = false


func _capture(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var size := img.get_size()
	var path := "%s/%s_%dx%d.png" % [out_dir, shot_name, size.x, size.y]
	img.save_png(path)
	print("[ui_review] %s" % path)
