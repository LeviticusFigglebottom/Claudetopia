class_name ControlHints
extends HBoxContainer
## The first minutes: a strip along the foot of the screen naming the handful of things a new
## player reaches for, with the keys (or the pad's buttons) they are bound to at this moment, and
## letting each go once it has been done. Someone who has moved, sprinted, rolled, jumped, used
## something, struck and blocked has nothing left on it, and it is gone. Someone who never blocks
## goes on being told how until they do, or until LIFETIME of play has passed.
##
## The playtest asked "no roll?": the roll existed, on a key nobody finds without reading. A
## player reads the foot of the screen before they read a menu.
##
## What has been learned is kept with the game (a GameState flag, so in the save): a new game is
## taught again, and nothing running outside a game -- a test, a capture -- writes the player's
## settings file. The Hints setting (gameplay/show_hints) turns the strip off altogether.

## [id, the word shown, the actions whose bindings are shown]
const ITEMS := [
	["move", "move", ["move_forward", "move_left", "move_back", "move_right"]],
	["sprint", "sprint", ["sprint"]],
	["roll", "roll", ["dodge"]],
	["jump", "jump", ["jump"]],
	["use", "use", ["interact"]],
	["strike", "strike", ["attack_light"]],
	["block", "block", ["block"]],
]
## Seconds of play (the world running, not paused) after which the strip goes anyway.
const LIFETIME := 900.0
## How long a thing has to be done before it counts as learned: a brush of a key is not a lesson.
const MOVE_S := 1.2
const SPRINT_S := 0.6
const BLOCK_S := 0.25
const FADE_S := 0.6

const LEARNED_FLAG := "hints_learned"

var learned: Array[String] = []
var _items: Dictionary = {}          # id -> the Control showing it
var _held_for: Dictionary = {}       # id -> seconds the thing has been done so far
var _played := 0.0
var _gone := false


func _ready() -> void:
	name = "ControlHints"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 12)
	for id in GameState.get_flag(LEARNED_FLAG, []):
		learned.append(str(id))
	UI.input_device_changed.connect(_on_input_device_changed)
	Settings.bindings_changed.connect(rebuild)
	Settings.changed.connect(_on_setting_changed)
	rebuild()


## Lays the strip out again from the live bindings and the device in use.
func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_items.clear()
	for item in ITEMS:
		var id := str(item[0])
		if learned.has(id):
			continue
		var node := _item(id, str(item[1]), item[2])
		_items[id] = node
		add_child(node)
	_refresh_visible()


func _on_input_device_changed(_pad: bool) -> void:
	rebuild()


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if (section == "gameplay" and key == "show_hints") or (section == "controls" and key in ["sprint_tap_rolls", "toggle_sprint"]):
		rebuild()


func _refresh_visible() -> void:
	visible = not _gone and bool(Settings.get_value("gameplay", "show_hints", true)) and not _items.is_empty()


## The keys an item is shown with, as the player would press them now. A roll is a tap of Sprint
## while that is how the roll is reached (Player.sprint_taps_roll()), on a pad (B) as on a keyboard.
func keys_for(id: String) -> Array[String]:
	var pad := UI.using_gamepad
	var out: Array[String] = []
	if id == "move":
		if pad:
			out.append("LS")
		else:
			var keys := ""
			for a in ["move_forward", "move_left", "move_back", "move_right"]:
				keys += Settings.prompt_for(a, false)
			out.append(keys if keys.length() == 4 else "WASD")
		return out
	if id == "roll" and Player.sprint_taps_roll_setting():
		out.append("tap " + Settings.prompt_for("sprint", pad))
		return out
	for item in ITEMS:
		if str(item[0]) == id:
			for a in item[2]:
				out.append(Settings.prompt_for(str(a), pad))
	return out


func _item(id: String, word: String, _actions: Array) -> Control:
	var row := HBoxContainer.new()
	row.name = id
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	for k in keys_for(id):
		var words := k.split(" ", false)
		var key := words[words.size() - 1]
		if words.size() > 1:
			row.add_child(_word(" ".join(words.slice(0, words.size() - 1))))
		row.add_child(_keycap(key))
	row.add_child(_word(word))
	return row


## A word on the strip, light with a dark rim so it reads on pale floor and dark earth alike:
## the theme's soft ink all but vanished against the world's dark ground.
func _word(text: String) -> Label:
	var l := UiKit.label(text, "Small")
	l.add_theme_color_override("font_color", ThemeBuilder.colour("paper", "warm"))
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l


## A key as a small plate: ink on paper inside a metal rim, a few pixels wider than its name.
## The theme's chrome plate is 24 px wider than its text, and seven of those did not fit between
## the bars and the quick slots at 1280 wide.
func _keycap(key: String) -> Control:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = ThemeBuilder.colour("paper", "warm", 0.92)
	box.border_color = ThemeBuilder.colour("metal", "warm")
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	box.content_margin_top = 1.0
	box.content_margin_bottom = 1.0
	cap.add_theme_stylebox_override("panel", box)
	var glyph := UiKit.label(key, "Small", HORIZONTAL_ALIGNMENT_CENTER)
	glyph.add_theme_color_override("font_color", ThemeBuilder.colour("ink", "warm"))
	cap.add_child(glyph)
	return cap


# --- learning -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _gone or get_tree().paused:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	_played += delta
	if _played >= LIFETIME:
		_fade_all()
		return
	var flat := Vector2(player.velocity.x, player.velocity.z).length()
	_accumulate("move", flat > 1.0 and player.state == Player.State.FREE, delta, MOVE_S)
	_accumulate("sprint", player.is_sprinting, delta, SPRINT_S)
	_accumulate("block", player.is_blocking, delta, BLOCK_S)
	if player.state == Player.State.DODGE:
		learn("roll")
	if player.velocity.y > 2.0 and not player.is_on_floor():
		learn("jump")
	if player.state == Player.State.ATTACK:
		learn("strike")
	if player.input_enabled and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		learn("use")


func _accumulate(id: String, doing: bool, delta: float, needed: float) -> void:
	if learned.has(id) or not doing:
		return
	_held_for[id] = float(_held_for.get(id, 0.0)) + delta
	if float(_held_for[id]) >= needed:
		learn(id)


## Marks a thing as learned: its item fades and goes, and once nothing is left the strip goes.
func learn(id: String) -> void:
	if learned.has(id):
		return
	learned.append(id)
	GameState.set_flag(LEARNED_FLAG, learned.duplicate())
	var node: Control = _items.get(id, null)
	_items.erase(id)
	if node != null and is_instance_valid(node):
		var tw := node.create_tween()
		tw.tween_property(node, "modulate:a", 0.0, FADE_S)
		tw.tween_callback(node.queue_free)
	if _items.is_empty():
		_fade_all()


func _fade_all() -> void:
	if _gone:
		return
	_gone = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_S)
	tw.tween_callback(_refresh_visible)


## What is still being taught, in order.
func showing() -> Array[String]:
	var out: Array[String] = []
	for item in ITEMS:
		if _items.has(str(item[0])):
			out.append(str(item[0]))
	return out
