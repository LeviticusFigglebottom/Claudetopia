class_name NightWatch
extends Node
## Somebody a lesson is about not being seen by (docs/FIGHTING_STYLE_STARTS.md §3.4): the Reed
## Council's night-watch on Moreva's boards, whom the rogue gets past before dawn to the South
## Channel's traps. A stage's
##   "unseen": {npc, flag, said: [[npc_id, line], ...], back_to: <a PlaceRef spec>, back_m?,
##              again: [[npc_id, line], ...]}
## watches that person's detection meter (Npc.detection, DetectionMeter): when it reaches a
## witness's (WITNESS) they have seen you, `flag` goes up and `said` is said out loud. Seen, you go
## back to `back_to`; within `back_m` of it the flag comes down, the watcher's meter is let go, and
## `again` is said. The stage's own lines (the teacher's greeting, the choice that ends it) read the
## flag. Nothing is saved but the flag.

const GROUP := "night_watch"
const POLL_S := 0.2
const BACK_M := 8.0

## Who watches, when something other than the registry's person does (the tests stand one in).
var watcher: Node = null
var _look := PollTimer.new(POLL_S)


static func ensure() -> NightWatch:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is NightWatch:
		return found as NightWatch
	var made := NightWatch.new()
	made.name = "NightWatch"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


func _ready() -> void:
	add_to_group(GROUP)


func _process(delta: float) -> void:
	if _look.due(delta):
		refresh()


## The watch in force: the first active quest whose current stage has one.
func spec() -> Dictionary:
	var log_node := get_tree().get_first_node_in_group("quest_log") if is_inside_tree() else null
	if log_node == null:
		return {}
	for q in (log_node.get("quests") as Dictionary).keys():
		if not bool(log_node.call("is_active", q)):
			continue
		var stage: Dictionary = log_node.call("stage_def", q, int(log_node.call("stage_of", q)))
		var u: Variant = stage.get("unseen", null)
		if u is Dictionary:
			return u
	return {}


## One look: "seen" when the watcher has just seen you, "again" when you have just gone back, or "".
func refresh() -> String:
	var s := spec()
	if s.is_empty() or not is_inside_tree():
		return ""
	var flag := str(s.get("flag", ""))
	if flag.is_empty():
		return ""
	var who := _watcher(str(s.get("npc", "")))
	if not GameState.has_flag(flag):
		if who == null or float(who.get("detection")) < DetectionMeter.WITNESS:
			return ""
		GameState.set_flag(flag, true)
		_say(s.get("said", []))
		return "seen"
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var back: Variant = s.get("back_to", null)
	if player == null or not PlaceRef.is_spec(back):
		return ""
	var at := PlaceRef.point_xz(back)
	if at == Vector2.INF or Vector2(player.global_position.x, player.global_position.z).distance_to(at) > float(s.get("back_m", BACK_M)):
		return ""
	GameState.clear_flag(flag)
	if who != null:
		# she looks away again: the meter starts from nothing, not from having just seen you
		who.set("detection", 0.0)
		var meter: Variant = who.get("meter")
		if meter is DetectionMeter:
			(meter as DetectionMeter).reset()
	_say(s.get("again", []))
	return "again"


func _watcher(npc_id: String) -> Node:
	if watcher != null and is_instance_valid(watcher):
		return watcher
	if npc_id.is_empty() or NpcRegistry.instance == null:
		return null
	var n := NpcRegistry.instance.actor(npc_id)
	return n if n != null and is_instance_valid(n) and "detection" in n else null


static func _say(lines: Variant) -> void:
	if not (lines is Array):
		return
	var delay := 0.0
	for l in lines as Array:
		if l is Array and (l as Array).size() >= 2:
			Barks.say(str(l[0]), str(l[1]), delay)
			delay += 2.2
