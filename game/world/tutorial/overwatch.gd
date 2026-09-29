class_name Overwatch
extends Node
## A teacher watching over the first real fight (docs/FIGHTING_STYLE_STARTS.md §3.2): Rosen Wyke on
## the lip over Wold Force does not shoot unless you are hurt, and says afterwards that she nearly
## did not. A stage's
##   "overwatch": {npc, enemy, below: the player's health share, damage, every: seconds, say, flag}
## has the teacher's shot land on the nearest living foe of that kind near the player whenever the
## player is under `below`, at most once every `every` seconds; the first time, they say `say` and
## `flag` is raised.

const GROUP := "overwatch"
const POLL_S := 0.25
const REACH_M := 60.0

var _look := PollTimer.new(POLL_S)
var _next_ms := 0


static func ensure() -> Overwatch:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is Overwatch:
		return found as Overwatch
	var made := Overwatch.new()
	made.name = "Overwatch"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


func _ready() -> void:
	add_to_group(GROUP)


func _process(delta: float) -> void:
	if _look.due(delta):
		refresh()


## The overwatch in force: the first active quest whose current stage has one.
func spec() -> Dictionary:
	var log_node := get_tree().get_first_node_in_group("quest_log") if is_inside_tree() else null
	if log_node == null:
		return {}
	for q in (log_node.get("quests") as Dictionary).keys():
		if not bool(log_node.call("is_active", q)):
			continue
		var stage: Dictionary = log_node.call("stage_def", q, int(log_node.call("stage_of", q)))
		var o: Variant = stage.get("overwatch", null)
		if o is Dictionary:
			return o
	return {}


## Takes the shot if one is wanted now. Returns the foe it struck, or null.
func refresh() -> Node:
	var s := spec()
	var player := get_tree().get_first_node_in_group("player") as Actor if is_inside_tree() else null
	if s.is_empty() or player == null or player.dead:
		return null
	if player.health > player.max_health * float(s.get("below", 0.4)) or Time.get_ticks_msec() < _next_ms:
		return null
	var want := str(s.get("enemy", ""))
	var best: Enemy = null
	var best_d := REACH_M
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e == null or e.dead or (want != "" and e.content_id() != want):
			continue
		var d := e.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return null
	_next_ms = Time.get_ticks_msec() + int(float(s.get("every", 4.0)) * 1000.0)
	best.apply_raw_damage(float(s.get("damage", 40.0)), "pierce", null)
	var flag := str(s.get("flag", ""))
	if flag != "" and not GameState.has_flag(flag):
		GameState.set_flag(flag, true)
		Barks.say(str(s.get("npc", "")), str(s.get("say", "")), 0.6)
	return best
