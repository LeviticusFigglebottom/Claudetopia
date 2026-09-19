extends Node
## Opens every Wickmere screen with believable data and screenshots it, so the UI can be
## looked at and fixed without a GPU or a world.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy --resolution 1280x720 res://tools_gd/ui_review.tscn -- --out=<dir>
##
## Arguments (after --): --out=<dir>  --only=<name[,name]>  --frames=<n>
##
## Where it can, the harness uses the real systems (Inventory, Equipment, Progression,
## Crafting) loaded with real content, so a screenshot is evidence the screen works and
## not just that it draws. Only the player, the quest log, the dialogue runner and the
## merchant are stand-ins, because those streams are still being written.

const FAKES := "res://tools_gd/ui_review_fakes.gd"

var out_dir := "user://ui"
var only: PackedStringArray = []
var settle_seconds := 2.4
var _shots: Array[Dictionary] = []
var _index := 0
var _wait := 0.0
var _frames := 0
var _host: Control
var _current: Node = null
var _fakes: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a.begins_with("--settle="):
			settle_seconds = float(a.substr(9))
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not ContentDB.is_loaded:
		await ContentDB.loaded

	# A Control only picks up the viewport rect under a CanvasLayer, so screens get one.
	var host_layer := CanvasLayer.new()
	host_layer.layer = 0
	add_child(host_layer)
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
		{"name": "hud", "hud": true},
		{"name": "hud_combat", "hud": true, "state": "combat"},
		{"name": "dialogue", "dialogue": true},
		{"name": "gesture_wheel", "dialogue": true, "state": "gestures"},
		{"name": "pause", "menu": "pause"},
		{"name": "settings_video", "menu": "settings", "args": {"tab": 0}},
		{"name": "settings_audio", "menu": "settings", "args": {"tab": 1}},
		{"name": "settings_controls", "menu": "settings", "args": {"tab": 2}},
		{"name": "settings_gameplay", "menu": "settings", "args": {"tab": 3}},
		{"name": "settings_accessibility", "menu": "settings", "args": {"tab": 4}},
		{"name": "save_load", "menu": "save_load", "args": {"mode": "save"}},
		{"name": "journal_quests", "menu": "journal", "args": {"tab": 0}},
		{"name": "journal_rumours", "menu": "journal", "args": {"tab": 1}},
		{"name": "journal_bestiary", "menu": "journal", "args": {"tab": 2}},
		{"name": "journal_books", "menu": "journal", "args": {"tab": 3}},
		{"name": "book_reader", "menu": "book", "args": {"book_id": "core:book/four_accounts"}},
		{"name": "inventory", "menu": "inventory"},
		{"name": "skills", "menu": "skills"},
		{"name": "crafting_forge", "menu": "crafting", "args": {"station": "forge"}},
		{"name": "crafting_alchemy", "menu": "crafting", "args": {"station": "alembic"}},
		{"name": "crafting_enchanting", "menu": "crafting", "args": {"station": "name_table"}},
		{"name": "trade", "menu": "trade", "args": {"merchant_id": "core:npc/review_merchant"}},
		{"name": "deed", "menu": "deed", "args": {"property_id": "core:property/merrowby_cottage", "name": "The Cottage by the Toll", "place": "Merrowby", "price": 2400}},
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
	_fakes.set_state(str(shot.get("state", "default")))
	if shot.has("scene"):
		var path: String = shot["scene"]
		if not ResourceLoader.exists(path):
			push_warning("ui_review: missing %s" % path)
			return
		_current = (load(path) as PackedScene).instantiate()
		_host.add_child(_current)
	elif shot.get("hud", false):
		UI.show_hud()
		if UI.hud() and UI.hud().has_method("review_state"):
			UI.hud().call("review_state", str(shot.get("state", "default")))
		_fakes.fire_hud_events(str(shot.get("state", "default")))
	elif shot.get("dialogue", false):
		UI.show_hud()
		var dlg := UI.show_dialogue()
		if dlg:
			_fakes.drive_dialogue(dlg, str(shot.get("state", "default")))
	elif shot.has("menu"):
		UI.show_hud()
		UI.open(str(shot["menu"]), shot.get("args", {}))


func _teardown() -> void:
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
