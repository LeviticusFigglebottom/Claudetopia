class_name WorldNotice
extends PanelContainer
## What the title screen says when there is no world to enter, and what the world itself shows if
## anything gets into it anyway (the editor's Play Scene, `--new-game`, a tool): the headline, why,
## the command that builds it and what it needs, and a button that copies the command. The title
## says the same across its sheet when the ground will be the coarse one, with "foot" under it.
##
## `WorldStatus` decides what is true; this only says it.

signal back_pressed

const COPY_LABEL := "Copy the command"
const BACK_LABEL := "Back to the title"

var status: Dictionary = {}
var command_label: Label
var copy_button: Button
var back_button: Button = null


## The panel alone, for the title screen's column.
static func panel(s: Dictionary, width := 580.0) -> WorldNotice:
	var n := WorldNotice.new()
	n.status = s
	n.name = "WorldNotice"
	n.theme_type_variation = &"PlainPanel"
	n.custom_minimum_size = Vector2(width, 0)
	n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	n._build(width, false)
	return n


## A whole screen: the paper, the panel and the way back to the title.
static func screen(s: Dictionary) -> Control:
	var root := ColorRect.new()
	root.name = "WorldUnbuilt"
	root.color = ThemeBuilder.colour("paper_lo", "warm").darkened(0.45)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.apply_theme(root)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)
	var n := WorldNotice.new()
	n.status = s
	n.name = "WorldNotice"
	n.theme_type_variation = &"SheetPanel"
	n.custom_minimum_size = Vector2(640, 0)
	n._build(600.0, true)
	centre.add_child(n)
	n.back_pressed.connect(func() -> void: n.get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn"))
	(n.copy_button if n.copy_button != null else n.back_button).call_deferred("grab_focus")
	return root


func _build(width: float, with_back: bool) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var title := UiKit.label(str(status.get("title", "")), "Heading", HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	col.add_child(title)
	var detail := UiKit.wrapped(str(status.get("detail", "")), "Body", width - 24.0)
	detail.name = "Detail"
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(detail)
	# no command when nothing the player can run mends it (a machine Terrain3D has no library for)
	var command := str(status.get("command", WorldStatus.BUILD_COMMAND))
	if not command.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		col.add_child(row)
		command_label = UiKit.label(command, "Emphasis")
		command_label.name = "Command"
		row.add_child(command_label)
		copy_button = UiKit.button(COPY_LABEL, "FlatButton")
		copy_button.name = "Copy"
		copy_button.pressed.connect(_copy)
		row.add_child(copy_button)
	var foot := str(status.get("foot", ""))
	if not foot.is_empty():
		var foot_label := UiKit.label(foot, "Small", HORIZONTAL_ALIGNMENT_CENTER)
		foot_label.name = "Foot"
		col.add_child(foot_label)
	if with_back:
		back_button = UiKit.button(BACK_LABEL, "FlatButton")
		back_button.name = "Back"
		back_button.pressed.connect(func() -> void: back_pressed.emit())
		col.add_child(back_button)
		var chain: Array = [back_button] if copy_button == null else [copy_button, back_button]
		UiKit.focus_chain(chain)


func _copy() -> void:
	DisplayServer.clipboard_set(command_label.text)
	copy_button.text = "Copied"


## The words on it, for a test or a probe.
func text() -> String:
	return "%s\n%s\n%s\n%s" % [str(status.get("title", "")), str(status.get("detail", "")),
			command_label.text if command_label else "", str(status.get("foot", ""))]
