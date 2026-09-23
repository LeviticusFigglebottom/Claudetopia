class_name GroundNotice
extends CanvasLayer
## What a player on the coarse ground sees for as long as they are on it: a plate in the top left
## corner that says "Coarse ground" and why, and on arrival a card across the top of the view with
## the whole account and the command that mends it.
##
## This used to be one toast, among the other toasts, for a few seconds. A player on Windows played
## on the coarse ground run after run without seeing it, and took its plain grey hills for the
## game's look: the build had written the maps and the Terrain3D import had never run. So the plate
## does not go away. It shows whenever the HUD does, above the HUD's idle fade, and the card waits
## for the fade to lift and counts its seconds only while it can be seen.
##
## Asked for with `--terrain=fallback` the ground is what the player wanted, so there is no card,
## and the plate says it was asked for.

const CARD_SECONDS := 16.0
const PLATE_WIDTH := 330.0
const CARD_WIDTH := 640.0

## `WorldStatus` as the world found it (with "badge", "announce", "title", "detail", "command").
var status: Dictionary = {}
var plate: PanelContainer
var plate_line: Label
var card: PanelContainer
## Whether the card has been up, for the flow probe and the tests: it is gone after CARD_SECONDS.
var card_shown := false
var _card_left := 0.0
var _root: Control


static func make(s: Dictionary) -> GroundNotice:
	var g := GroundNotice.new()
	g.name = "GroundNotice"
	g.status = s
	g.layer = UI.LAYER_HUD
	return g


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	UI.apply_theme(_root)
	_build_plate()
	_build_card()
	visible = false


func _build_plate() -> void:
	plate = UiKit.panel("ChromePanel")
	plate.name = "Plate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_anchors_preset(Control.PRESET_TOP_LEFT)
	plate.offset_left = 22.0
	plate.offset_top = 18.0
	plate.custom_minimum_size = Vector2(PLATE_WIDTH, 0)
	_root.add_child(plate)
	var row := UiKit.row(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	var tex := ThemeBuilder.icon("map")
	if tex:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = ThemeBuilder.colour("accent", UI.theme_variant)
		row.add_child(icon)
	var col := UiKit.column(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var head := UiKit.label("Coarse ground", "Emphasis")
	head.name = "Head"
	col.add_child(head)
	plate_line = UiKit.wrapped(str(status.get("badge", "")), "Small", PLATE_WIDTH - 60.0)
	plate_line.name = "Line"
	col.add_child(plate_line)


func _build_card() -> void:
	card = UiKit.panel("SheetPanel")
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.offset_left = -CARD_WIDTH * 0.5
	card.offset_right = CARD_WIDTH * 0.5
	card.offset_top = 86.0             # under the compass
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.visible = false
	_root.add_child(card)
	var col := UiKit.column(8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var title := UiKit.label(str(status.get("title", "")), "Heading", HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	col.add_child(title)
	var detail := UiKit.wrapped(str(status.get("detail", "")), "Body", CARD_WIDTH - 48.0)
	detail.name = "Detail"
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(detail)
	var command := str(status.get("command", ""))
	if not command.is_empty():
		var cmd := UiKit.label(command, "Emphasis", HORIZONTAL_ALIGNMENT_CENTER)
		cmd.name = "Command"
		col.add_child(cmd)
	var foot := UiKit.label("This stays in the corner for as long as the ground is the coarse one.", "Small",
			HORIZONTAL_ALIGNMENT_CENTER)
	foot.name = "Foot"
	col.add_child(foot)


## The card, once the player can see: called by the world when the fade has lifted.
func announce() -> void:
	if not bool(status.get("announce", false)) or card == null:
		return
	card.visible = true
	card_shown = true
	_card_left = CARD_SECONDS
	UiKit.ink_in(card, 0.0, 0.6)


func _process(delta: float) -> void:
	var hud := UI.hud() as CanvasItem
	var seen := hud != null and is_instance_valid(hud) and hud.is_visible_in_tree() and not UI.is_faded_out()
	visible = seen
	if not seen or card == null or not card.visible:
		return
	_card_left -= delta
	if _card_left <= 0.0:
		card.visible = false


## Whether the plate is up where the player can see it now.
func plate_showing() -> bool:
	return visible and plate != null and plate.is_visible_in_tree()


## The words on the plate and the card, for a test or a probe.
func text() -> String:
	var words: PackedStringArray = []
	for n in [plate, card]:
		if n == null:
			continue
		for l in (n as Node).find_children("*", "Label", true, false):
			words.append((l as Label).text)
	return " / ".join(words)
