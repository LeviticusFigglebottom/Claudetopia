class_name NightWatch
extends Node
## Somebody a lesson is about not being seen by (docs/FIGHTING_STYLE_STARTS.md §3.4): the Reed
## Council's night-watch on Moreva's boards, whom the rogue gets past before dawn to the South
## Channel's traps. A stage's
##   "unseen": {npc, flag, said: [[npc_id, line], ...], back_to: <a PlaceRef spec, or a list of them>,
##              back_m?, again: [[npc_id, line], ...], noticed?: [...], eased?: [...],
##              lantern?: {range, energy}, weather?: <a weather id>}
## watches that person's detection meter (Npc.detection, DetectionMeter), in the HUD eye's own steps:
## - Noticed (SUSPICIOUS): `noticed` is said, once, and when the meter has fallen back to nothing
##   without her being sure, `eased` is: the build-up, and backing off from it, are heard;
## - Seen (WITNESS): `flag` goes up and `said` is said out loud. Seen, you go back to the nearest of
##   `back_to` (the lane's shelter, a short way, not the start); within `back_m` of it, with her
##   looking elsewhere, the flag comes down, the watcher's meter is let go, and `again` is said.
## `lantern` hangs a light on the watcher while the stage lasts: a pool she sees you in, which you
## can see from the dark; `weather` is kept over the region while it lasts. The stage's own lines (the teacher's greeting, the choice that ends it)
## read the flag. Nothing is saved but the flag.

const GROUP := "night_watch"
const POLL_S := 0.2
const BACK_M := 5.0
## Below this, a build-up that never became seeing has gone: she has looked away.
const EASED := 0.12

## Who watches, when something other than the registry's person does (the tests stand one in).
var watcher: Node = null
var _look := PollTimer.new(POLL_S)
var _noticed := false
var _lantern: Node3D = null


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


func _exit_tree() -> void:
	_put_out()


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


## One look: "seen" when the watcher has just seen you, "again" when you have just gone back,
## "noticed" / "eased" as her meter crosses Noticed up and falls back to nothing, or "".
func refresh() -> String:
	var s := spec()
	if s.is_empty() or not is_inside_tree():
		_put_out()
		_noticed = false
		return ""
	var flag := str(s.get("flag", ""))
	if flag.is_empty():
		return ""
	var who := _watcher(str(s.get("npc", "")))
	_light(who, s.get("lantern", null))
	_keep_weather(str(s.get("weather", "")))
	if not GameState.has_flag(flag):
		if who == null:
			return ""
		var level := float(who.get("detection"))
		if level >= DetectionMeter.WITNESS:
			GameState.set_flag(flag, true)
			_noticed = false
			_say(s.get("said", []))
			return "seen"
		if level >= DetectionMeter.SUSPICIOUS and not _noticed:
			_noticed = true
			_say(s.get("noticed", []))
			return "noticed"
		if _noticed and level < EASED:
			_noticed = false
			_say(s.get("eased", []))
			return "eased"
		return ""
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return ""
	var at := nearest_back(s, Vector2(player.global_position.x, player.global_position.z))
	if at == Vector2.INF or Vector2(player.global_position.x, player.global_position.z).distance_to(at) > float(s.get("back_m", BACK_M)):
		return ""
	# back in the shelter, and she has stopped looking at where you were
	if who != null and float(who.get("detection")) >= DetectionMeter.SUSPICIOUS:
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


## The nearest of a watch's places to go back to (its `back_to`: one PlaceRef spec, or a list), or
## Vector2.INF.
static func nearest_back(s: Dictionary, from: Vector2) -> Vector2:
	var back: Variant = s.get("back_to", null)
	var list: Array = back if back is Array else [back]
	var best := Vector2.INF
	for b in list:
		if not PlaceRef.is_spec(b):
			continue
		var at := PlaceRef.point_xz(b)
		if at != Vector2.INF and (best == Vector2.INF or from.distance_to(at) < from.distance_to(best)):
			best = at
	return best


func _watcher(npc_id: String) -> Node:
	if watcher != null and is_instance_valid(watcher):
		return watcher
	if npc_id.is_empty() or NpcRegistry.instance == null:
		return null
	var n := NpcRegistry.instance.actor(npc_id)
	return n if n != null and is_instance_valid(n) and "detection" in n else null


## The watcher's lantern, hung on her while the watch lasts (and moved to her if she was stood up
## again), or put out.
func _light(who: Node, spec_v: Variant) -> void:
	if not (spec_v is Dictionary) or not (who is Node3D):
		_put_out()
		return
	if _lantern != null and is_instance_valid(_lantern) and _lantern.get_parent() == who:
		return
	_put_out()
	var l: Dictionary = spec_v
	var pole := Node3D.new()
	pole.name = "WatchLantern"
	# held out on a pole to her right and a little ahead, hooded on the landward side
	pole.position = Vector3(0.45, 2.1, 0.35)
	var glow := MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.09
	bulb.height = 0.18
	glow.mesh = bulb
	var hot := StandardMaterial3D.new()
	hot.albedo_color = Color(1.0, 0.78, 0.45)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.7, 0.35)
	hot.emission_energy_multiplier = 3.0
	glow.material_override = hot
	pole.add_child(glow)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color(1.0, 0.76, 0.45)
	lamp.omni_range = float(l.get("range", 7.0))
	lamp.light_energy = float(l.get("energy", 0.8))
	lamp.shadow_enabled = false
	pole.add_child(lamp)
	var seen_by := StealthLight.new()
	seen_by.name = "StealthLight"
	lamp.add_child(seen_by)
	(who as Node3D).add_child(pole)
	_lantern = pole


## The watch's own weather, kept while it lasts: a stage's on_enter weather is brought on as the
## quest begins, which for a new game is before the region's own weather is picked, and the pick
## put a clear night over the lesson about the mist.
func _keep_weather(weather_id: String) -> void:
	if weather_id.is_empty() or not ContentDB.has(weather_id):
		return
	var atm := get_tree().get_first_node_in_group("atmosphere")
	if atm == null or not atm.has_method("force_weather"):
		return
	var region := str(atm.get("region_id"))
	if region.is_empty():
		return
	var now: Dictionary = atm.get("weather_by_region")
	if str(now.get(region, "")) != weather_id:
		atm.call("force_weather", weather_id, false)


func _put_out() -> void:
	if _lantern != null and is_instance_valid(_lantern):
		_lantern.queue_free()
	_lantern = null


static func _say(lines: Variant) -> void:
	if not (lines is Array):
		return
	var delay := 0.0
	for l in lines as Array:
		if l is Array and (l as Array).size() >= 2:
			Barks.say(str(l[0]), str(l[1]), delay)
			delay += 2.2
