class_name NightWatch
extends Node
## Somebody a lesson is about not being seen by (docs/FIGHTING_STYLE_STARTS.md §3.4): the Reed
## Council's night-watch on Moreva's boards, whom the rogue gets past before dawn to the South
## Channel's traps. A stage's
##   "unseen": {npc, flag, said: [[npc_id, line], ...], fail_stage: <stage id>, noticed?: [...],
##              eased?: [...], lantern?: {range, energy}, weather?: <a weather id>}
## watches that person's detection meter (Npc.detection, DetectionMeter), in the HUD eye's own steps:
## - Noticed (SUSPICIOUS): `noticed` is said, once, and when the meter has fallen back to nothing
##   without her being sure, `eased` is: the build-up, and backing off from it, are heard;
## - Seen (WITNESS): the attempt has failed (triage 78). `flag` goes up, `said` is said out loud, and
##   the quest is sent to `fail_stage`, a `detour` stage whose objective is to speak to the teacher
##   again (the marker moves to them). That stage says `"keeps_watch": <the watched stage's id>`: the
##   watcher keeps her post, her lantern and her look while you go back. Speaking to the teacher
##   sends the quest back to the watched stage, and entering it begins a clean attempt: the flag
##   comes down and the watcher's meter starts from nothing.
## Being seen used to send you back to a shelter to wait until she looked away, and a body she kept
## seeing there never came round again: a softlock. An `unseen` with no `fail_stage` is a content
## problem (tools/quests/softlock_check.py).
## `lantern` hangs a light on the watcher while the stage lasts: a pool she sees you in, which you
## can see from the dark; `weather` is kept over the region while it lasts. The stage's own lines (the
## teacher's greeting, the choice that ends it) read the flag. Nothing is saved but the flag and the
## stage, and a game loaded on the watched stage with the flag still up (a save from before the
## fail) begins its attempt clean.

const GROUP := "night_watch"
const POLL_S := 0.2
## Below this, a build-up that never became seeing has gone: she has looked away.
const EASED := 0.12

## Who watches, when something other than the registry's person does (the tests stand one in).
var watcher: Node = null
var _look := PollTimer.new(POLL_S)
var _noticed := false
var _lantern: Node3D = null
## Whom this watch told to keep their look on their post.
var _kept: Node = null
## The attempt under way ("<quest>:<stage>"): a watched stage entered afresh begins a clean one.
var _attempt := ""
## A clean attempt begun before the watcher was stood up: her meter is let go when she is.
var _calm_pending := false


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


## The watch in force: the first active quest whose current stage has one, or whose current stage
## keeps another stage's (`keeps_watch`): {quest, stage, spec, passive}, or {}.
func watch() -> Dictionary:
	var log_node := get_tree().get_first_node_in_group("quest_log") if is_inside_tree() else null
	if log_node == null:
		return {}
	for q in (log_node.get("quests") as Dictionary).keys():
		if not bool(log_node.call("is_active", q)):
			continue
		var stage: Dictionary = log_node.call("stage_def", q, int(log_node.call("stage_of", q)))
		var u: Variant = stage.get("unseen", null)
		if u is Dictionary:
			return {"quest": str(q), "stage": str(stage.get("id", "")), "spec": u, "passive": false}
		var kept := str(stage.get("keeps_watch", ""))
		if kept != "":
			var at := int(log_node.call("stage_index", q, kept))
			var watched: Dictionary = log_node.call("stage_def", q, at) if at >= 0 else {}
			if watched.get("unseen", null) is Dictionary:
				return {"quest": str(q), "stage": str(stage.get("id", "")), "spec": watched["unseen"], "passive": true}
	return {}


## The `unseen` spec in force (a kept watch's too), or {}.
func spec() -> Dictionary:
	var w := watch()
	return w.get("spec", {}) if not w.is_empty() else {}


## One look: "seen" when the watcher has just seen you (the attempt failed), "again" when a fresh
## attempt has just begun after one, "noticed" / "eased" as her meter crosses Noticed up and falls
## back to nothing, or "".
func refresh() -> String:
	var w := watch()
	if w.is_empty() or not is_inside_tree():
		_put_out()
		_noticed = false
		_attempt = ""
		return ""
	var s: Dictionary = w["spec"]
	var flag := str(s.get("flag", ""))
	var who := _watcher(str(s.get("npc", "")))
	_light(who, s.get("lantern", null))
	_keep(who)
	_keep_weather(str(s.get("weather", "")))
	if bool(w["passive"]):
		# gone back to the teacher after being seen: she keeps her post and her look, and sees nothing new
		_attempt = ""
		return ""
	var said := ""
	var key := "%s:%s" % [str(w["quest"]), str(w["stage"])]
	if key != _attempt:
		_attempt = key
		_noticed = false
		_calm_pending = true
		if flag != "" and GameState.has_flag(flag):
			GameState.clear_flag(flag)
			said = "again"
	if _calm_pending and who != null:
		_calm_pending = false
		_calm(who)
	if flag.is_empty() or who == null:
		return said
	if GameState.has_flag(flag):
		return said
	var level := float(who.get("detection"))
	if level >= DetectionMeter.WITNESS:
		GameState.set_flag(flag, true)
		_noticed = false
		_say(s.get("said", []))
		_fail(str(w["quest"]), str(s.get("fail_stage", "")))
		return "seen"
	if level >= DetectionMeter.SUSPICIOUS and not _noticed:
		_noticed = true
		_say(s.get("noticed", []))
		return "noticed"
	if _noticed and level < EASED:
		_noticed = false
		_say(s.get("eased", []))
		return "eased"
	return said


## Seen: the attempt is over, and the quest goes to the stage that puts it right (its teacher).
func _fail(quest_id: String, fail_stage: String) -> void:
	if fail_stage.is_empty():
		Log.warn("NightWatch", "%s: an `unseen` with no fail_stage; seen, the stage has nowhere to go (content problem)" % quest_id)
		return
	var log_node := get_tree().get_first_node_in_group("quest_log")
	if log_node != null:
		log_node.call("set_stage", quest_id, fail_stage)


## The watcher starts from nothing: not from having just seen you.
static func _calm(who: Node) -> void:
	who.set("detection", 0.0)
	var meter: Variant = who.get("meter")
	if meter is DetectionMeter:
		(meter as DetectionMeter).reset()


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


func _keep(who: Node) -> void:
	if who == _kept:
		return
	_let_go()
	if who != null and "keep_look" in who:
		who.set("keep_look", true)
		_kept = who


func _let_go() -> void:
	if _kept != null and is_instance_valid(_kept) and "keep_look" in _kept:
		_kept.set("keep_look", false)
	_kept = null


func _put_out() -> void:
	_let_go()
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
