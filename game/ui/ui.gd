extends Node
## UI: the autoload that owns every CanvasLayer the game draws, and the menu stack.
##
## Layers (the debug console sits at 100 and must stay above everything here):
##   5  hud          bars, compass, prompts, toasts' resting place, region cards
##   12 dialogue     conversation and the gesture wheel
##   20 menus        full-screen screens; opening one pauses the tree
##   30 toasts       notifications, above menus so they are never swallowed
##   40 fade         screen fade for door transitions and scene changes
##
## Screens are data: MENUS maps a menu id to its scene and how it behaves. open()
## pauses the tree for full-screen menus, frees the mouse, emits EventBus.menu_opened,
## and remembers the stack so close() can walk back out of nested screens.
##
## The theme swaps to its cold-bronze "deep" variant in dangerous regions, in deep
## places and during boss fights, and back on the way out.

signal variant_changed(variant: String)
signal input_device_changed(gamepad: bool)
signal hud_visibility_changed(visible: bool)

const LAYER_HUD := 5
const LAYER_DIALOGUE := 12
const LAYER_MENUS := 20
const LAYER_TOASTS := 30
const LAYER_FADE := 40

const THEME_PATHS := {"warm": "res://ui/theme/wickmere_theme.tres", "deep": "res://ui/theme/wickmere_theme_deep.tres"}
const HUD_SCENE := "res://ui/hud/hud.tscn"
const DIALOGUE_SCENE := "res://ui/dialogue/dialogue_ui.tscn"

## menu id -> scene, and whether it takes over the screen (pause + free the mouse).
const MENUS := {
	"pause": {"scene": "res://ui/menus/pause_menu.tscn", "full": true},
	"settings": {"scene": "res://ui/menus/settings_menu.tscn", "full": true},
	"save_load": {"scene": "res://ui/menus/save_load.tscn", "full": true},
	"inventory": {"scene": "res://ui/inventory/inventory_screen.tscn", "full": true},
	"journal": {"scene": "res://ui/journal/journal.tscn", "full": true},
	"skills": {"scene": "res://ui/skills/skills_screen.tscn", "full": true},
	"map": {"scene": "res://ui/map/map_screen.tscn", "full": true},
	"book": {"scene": "res://ui/books/book_reader.tscn", "full": true},
	"crafting": {"scene": "res://ui/crafting/station_screen.tscn", "full": true},
	"trade": {"scene": "res://ui/trade/trade_screen.tscn", "full": true},
	"deed": {"scene": "res://ui/property/deed_confirm.tscn", "full": true},
}

## Actions that open their screen straight from the world.
const MENU_ACTIONS := {"inventory": "inventory", "journal": "journal", "map": "map", "skills": "skills"}

var hud_layer: CanvasLayer
var dialogue_layer: CanvasLayer
var menu_layer: CanvasLayer
var toast_layer: CanvasLayer
var fade_layer: CanvasLayer

var theme_variant := "warm"
var using_gamepad := false
var gameplay_override := false      ## set by tools so screens can be opened without a world

var _themes: Dictionary = {}
var _stack: Array[Dictionary] = []  # [{id, node, full}]
var _hud: Node = null
var _dialogue: Node = null
var _toast_box: VBoxContainer
var _fade: ColorRect
var _hud_visible := true
var _mouse_was_captured := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_layers()
	set_variant("warm", true)
	EventBus.notify.connect(_on_notify)
	EventBus.book_opened.connect(_on_book_opened)
	EventBus.region_entered.connect(func(id: String, _p: String) -> void: _refresh_variant())
	EventBus.interior_entered.connect(func(_id: String) -> void: _refresh_variant())
	EventBus.interior_exited.connect(func(_id: String) -> void: _refresh_variant())
	EventBus.boss_started.connect(func(_id: String) -> void: set_variant("deep"))
	EventBus.boss_defeated.connect(func(_id: String) -> void: _refresh_variant())
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.echo_recovered.connect(func(marks: int) -> void:
			EventBus.emit_notify("Your Echo goes quiet. %d marks recovered." % marks, "item"))
	EventBus.player_died.connect(func(_pos: Vector3) -> void:
			EventBus.emit_notify("You have gone quiet.", "warning"))
	if Engine.has_singleton("Interiors") or get_node_or_null("/root/Interiors") != null:
		var interiors: Node = get_node_or_null("/root/Interiors")
		if interiors and interiors.has_signal("transition"):
			interiors.transition.connect(_on_interior_transition)
	Log.info("UI", "layers ready")


func _build_layers() -> void:
	hud_layer = _make_layer("HudLayer", LAYER_HUD)
	dialogue_layer = _make_layer("DialogueLayer", LAYER_DIALOGUE)
	menu_layer = _make_layer("MenuLayer", LAYER_MENUS)
	toast_layer = _make_layer("ToastLayer", LAYER_TOASTS)
	fade_layer = _make_layer("FadeLayer", LAYER_FADE)

	_toast_box = VBoxContainer.new()
	_toast_box.name = "Toasts"
	_toast_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toast_box.offset_left = -430.0
	_toast_box.offset_top = 22.0
	_toast_box.offset_right = -22.0
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toast_box.add_theme_constant_override("separation", 8)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(_toast_box)

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.05, 0.04, 0.03, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	fade_layer.add_child(_fade)


func _make_layer(node_name: String, layer_index: int) -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.name = node_name
	cl.layer = layer_index
	add_child(cl)
	return cl


# --- theme --------------------------------------------------------------------------------

func theme_for(variant: String) -> Theme:
	if _themes.has(variant):
		return _themes[variant]
	var path: String = THEME_PATHS.get(variant, THEME_PATHS["warm"])
	var t: Theme = load(path) if ResourceLoader.exists(path) else null
	if t == null:
		Log.warn("UI", "theme %s missing; building at runtime" % path)
		t = ThemeBuilder.build(variant)
	_themes[variant] = t
	return t


func set_variant(variant: String, force := false) -> void:
	if variant == theme_variant and not force:
		return
	if not THEME_PATHS.has(variant):
		variant = "warm"
	theme_variant = variant
	var t := theme_for(variant)
	for layer: CanvasLayer in [hud_layer, dialogue_layer, menu_layer, toast_layer]:
		for child in layer.get_children():
			if child is Control:
				(child as Control).theme = t
	variant_changed.emit(variant)


## Deep places, dangerous regions and boss fights swap the frame to cold bronze and ash.
func _refresh_variant() -> void:
	set_variant("deep" if _is_deep_context() else "warm")


func _is_deep_context() -> bool:
	var interior: String = GameState.current_interior_id
	if not interior.is_empty():
		var place_id := interior.replace(":interior/", ":place/")
		var place := ContentDB.get_or_empty(place_id)
		if place.get("kind", "") in ["deep_place", "interior_dungeon"]:
			return true
		var idef := ContentDB.get_or_empty(interior)
		if idef.get("deep", false):
			return true
	var region := ContentDB.get_or_empty(GameState.current_region_id)
	return int(region.get("danger", 1)) >= 4


func apply_theme(control: Control) -> void:
	control.theme = theme_for(theme_variant)


# --- the menu stack -----------------------------------------------------------------------

func is_menu_open(menu_id := "") -> bool:
	if menu_id.is_empty():
		return not _stack.is_empty()
	for entry in _stack:
		if entry["id"] == menu_id:
			return true
	return false


func top_menu() -> String:
	return str(_stack[-1]["id"]) if not _stack.is_empty() else ""


func menu_node(menu_id := "") -> Node:
	for entry in _stack:
		if menu_id.is_empty() or entry["id"] == menu_id:
			return entry["node"]
	return null


## Opens a screen. `args` is handed to the screen's `setup(args)` if it has one.
func open(menu_id: String, args: Dictionary = {}) -> Node:
	if not MENUS.has(menu_id):
		Log.error("UI", "unknown menu '%s'" % menu_id)
		return null
	if is_menu_open(menu_id):
		return menu_node(menu_id)
	var path: String = MENUS[menu_id]["scene"]
	if not ResourceLoader.exists(path):
		Log.error("UI", "menu scene missing: %s" % path)
		return null
	var node: Node = (load(path) as PackedScene).instantiate()
	if node is Control:
		var c := node as Control
		c.theme = theme_for(theme_variant)
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(node)
	var full: bool = bool(MENUS[menu_id].get("full", true))
	_stack.append({"id": menu_id, "node": node, "full": full})
	if node.has_method("setup"):
		node.call("setup", args)
	if full:
		_set_paused(true)
		_free_mouse()
	if _hud:
		_hud.visible = _hud_visible and not full
	EventBus.menu_opened.emit(menu_id)
	return node


func close(menu_id := "") -> void:
	if _stack.is_empty():
		return
	var index := _stack.size() - 1
	if not menu_id.is_empty():
		index = -1
		for i in _stack.size():
			if _stack[i]["id"] == menu_id:
				index = i
		if index < 0:
			return
	var entry: Dictionary = _stack[index]
	_stack.remove_at(index)
	var node: Node = entry["node"]
	if node is Control and node.has_method("closing"):
		node.call("closing")
	if is_instance_valid(node):
		node.queue_free()
	EventBus.menu_closed.emit(str(entry["id"]))
	if _stack.is_empty():
		_set_paused(false)
		_restore_mouse()
		if _hud:
			_hud.visible = _hud_visible


func close_all() -> void:
	while not _stack.is_empty():
		close()


func toggle(menu_id: String, args: Dictionary = {}) -> void:
	if is_menu_open(menu_id):
		close(menu_id)
	else:
		open(menu_id, args)


func _set_paused(on: bool) -> void:
	if on:
		get_tree().paused = true
	elif not _stack.any(func(e: Dictionary) -> bool: return bool(e.get("full", false))):
		get_tree().paused = false


# --- mouse --------------------------------------------------------------------------------

func _free_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_was_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _restore_mouse() -> void:
	if _mouse_was_captured and _gameplay_active():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_was_captured = false


func _gameplay_active() -> bool:
	if gameplay_override:
		return true
	return get_tree().get_first_node_in_group("player") != null


# --- the HUD ------------------------------------------------------------------------------

var hud_visible: bool:
	get:
		return _hud_visible
	set(value):
		_hud_visible = value
		if _hud:
			_hud.visible = value and not is_menu_open()
		hud_visibility_changed.emit(value)


func hud() -> Node:
	return _hud


func show_hud() -> Node:
	if _hud and is_instance_valid(_hud):
		return _hud
	if not ResourceLoader.exists(HUD_SCENE):
		return null
	_hud = (load(HUD_SCENE) as PackedScene).instantiate()
	hud_layer.add_child(_hud)
	if _hud is Control:
		(_hud as Control).theme = theme_for(theme_variant)
	_hud.visible = _hud_visible and not is_menu_open()
	return _hud


func hide_hud() -> void:
	if _hud and is_instance_valid(_hud):
		_hud.queue_free()
	_hud = null


func show_dialogue() -> Node:
	if _dialogue and is_instance_valid(_dialogue):
		return _dialogue
	if not ResourceLoader.exists(DIALOGUE_SCENE):
		return null
	_dialogue = (load(DIALOGUE_SCENE) as PackedScene).instantiate()
	dialogue_layer.add_child(_dialogue)
	if _dialogue is Control:
		(_dialogue as Control).theme = theme_for(theme_variant)
	return _dialogue


func _on_player_spawned(_player: Node) -> void:
	show_hud()
	show_dialogue()


# --- toasts -------------------------------------------------------------------------------

const TOAST_ICONS := {"info": "bell", "quest": "quest", "item": "coin", "warning": "skull", "book": "book"}


func _on_notify(text: String, kind: String) -> void:
	toast(text, kind)


func toast(text: String, kind := "info") -> void:
	if _toast_box == null:
		return
	var panel := PanelContainer.new()
	panel.theme = theme_for(theme_variant)
	panel.theme_type_variation = &"FramedPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var tex := ThemeBuilder.icon(str(TOAST_ICONS.get(kind, "bell")))
	if tex:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = ThemeBuilder.colour("accent" if kind == "warning" else "ink", theme_variant)
		row.add_child(icon)
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Body"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300, 0)
	row.add_child(label)
	_toast_box.add_child(panel)
	while _toast_box.get_child_count() > 5:
		_toast_box.get_child(0).queue_free()
		_toast_box.remove_child(_toast_box.get_child(0))

	# fade in from ink: the panel arrives dark and settles into paper
	panel.modulate = Color(0.25, 0.20, 0.16, 0.0)
	panel.position.x += 30.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.45).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_interval(4.2)
	tw.chain().tween_property(panel, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(func() -> void:
			if is_instance_valid(panel):
				panel.queue_free())


# --- screen fade --------------------------------------------------------------------------

func fade_to_black(seconds := 0.35) -> void:
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, seconds)


func fade_from_black(seconds := 0.5) -> void:
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, seconds)
	tw.tween_callback(func() -> void: _fade.visible = false)


func _on_interior_transition(phase: String, _interior_id: String) -> void:
	if phase == "fade_out":
		fade_to_black(0.25)
	else:
		fade_from_black(0.45)


# --- books --------------------------------------------------------------------------------

func _on_book_opened(book_id: String) -> void:
	open("book", {"book_id": book_id})


# --- input --------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	var kbm := event is InputEventKey or event is InputEventMouseButton
	if pad and not using_gamepad:
		using_gamepad = true
		input_device_changed.emit(true)
	elif kbm and using_gamepad:
		using_gamepad = false
		input_device_changed.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if is_menu_open():
			close()
		elif _gameplay_active() and not _dialogue_running():
			open("pause")
		get_viewport().set_input_as_handled()
		return
	if is_menu_open() or _dialogue_running() or not _gameplay_active():
		return
	for action: String in MENU_ACTIONS:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			open(str(MENU_ACTIONS[action]))
			get_viewport().set_input_as_handled()
			return


func _dialogue_running() -> bool:
	var runner := get_tree().get_first_node_in_group("dialogue_runner")
	if runner and runner.has_method("is_running"):
		return bool(runner.call("is_running"))
	return _dialogue != null and is_instance_valid(_dialogue) and _dialogue is Control and (_dialogue as Control).visible


## The glyph to print in a prompt, e.g. "E" or "A", following the active device.
func prompt_for(action: String) -> String:
	return Settings.prompt_for(action, using_gamepad)


# --- small shared dialogs -------------------------------------------------------------------

## A themed yes/no over the current screen. Await it: `if await UI.confirm("Delete?"):`
func confirm(title: String, body: String, yes_text := "Yes", no_text := "No") -> bool:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.03, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.theme = theme_for(theme_variant)
	menu_layer.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(centre)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"FramedPanel"
	panel.custom_minimum_size = Vector2(460, 0)
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	var title_label := Label.new()
	title_label.text = title
	title_label.theme_type_variation = &"Heading"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title_label)
	var body_label := Label.new()
	body_label.text = body
	body_label.theme_type_variation = &"Body"
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(body_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	var yes := Button.new()
	yes.text = yes_text
	row.add_child(yes)
	var no := Button.new()
	no.text = no_text
	row.add_child(no)

	var answered := [false]
	yes.pressed.connect(func() -> void: answered[0] = true; dim.set_meta("done", true))
	no.pressed.connect(func() -> void: dim.set_meta("done", true))
	no.grab_focus()
	yes.focus_neighbor_left = no.get_path()
	no.focus_neighbor_right = yes.get_path()
	while not dim.has_meta("done"):
		await get_tree().process_frame
		if not is_instance_valid(dim):
			return false
	dim.queue_free()
	return answered[0]
