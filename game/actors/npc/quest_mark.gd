class_name QuestMark
extends Label3D
## A person's quest business, over their head (triage 50): "!" when they have a quest to give,
## "?" when a step of one is theirs, a larger "?" when speaking to them hands one in, and a faint
## "?" while a quest they gave is under way. In the quest's tier colour (QuestCues). Small, seen
## only near, hidden while you are speaking with them, and never for somebody hostile or dead.
##
## It asks QuestCues.npc_state, which keeps each person's answer a moment, a couple of times a
## second, and only while the player is within SEEN_M.

const HEIGHT_M := 2.3
const SEEN_M := 32.0
const POLL_S := 0.5

var _look := PollTimer.new(POLL_S)
## What it shows now: {state, quest_id, tier, ...} or {} (the tests read it).
var shown: Dictionary = {}


func _ready() -> void:
	name = "QuestMark"
	position = Vector3(0.0, HEIGHT_M, 0.0)
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = false
	pixel_size = 0.0045
	font_size = 72
	outline_size = 14
	outline_modulate = Color(0.06, 0.05, 0.04, 0.85)
	no_depth_test = false
	shaded = false
	double_sided = true
	alpha_cut = Label3D.ALPHA_CUT_DISABLED
	visibility_range_end = SEEN_M
	var display := load(ThemeBuilder.FONT_DISPLAY) as Font
	if display != null:
		font = display
	visible = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if _look.due(delta):
		refresh()


## Looks again: what the person is to the player's quests now, and whether to show it.
func refresh() -> void:
	var npc := get_parent()
	var id := str(npc.get("npc_id")) if npc != null else ""
	if id == "" or npc.get("alive") == false or npc.get("hostile") == true or _in_talk(id) or not _near(npc as Node3D):
		_show({})
		return
	_show(QuestCues.npc_state(id))


func _show(state: Dictionary) -> void:
	shown = state
	var glyph := QuestCues.state_glyph(str(state.get("state", "")))
	visible = glyph != ""
	if not visible:
		return
	text = glyph
	var colour := QuestCues.tier_colour(str(state.get("tier", "")))
	match str(state["state"]):
		"turn_in":
			font_size = 96
		"in_progress":
			font_size = 60
			colour = Color(colour.lerp(Color(0.75, 0.75, 0.75), 0.55), 0.55)
		_:
			font_size = 72
	modulate = colour


func _in_talk(id: String) -> bool:
	var runner: Node = Social.dialogue if Social != null else null
	return runner != null and bool(runner.call("is_running")) and str(runner.get("npc_id")) == id


func _near(body: Node3D) -> bool:
	if body == null or not body.is_inside_tree():
		return false
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var from: Node3D = player if player != null else cam
	return from == null or from.global_position.distance_to(body.global_position) <= SEEN_M
