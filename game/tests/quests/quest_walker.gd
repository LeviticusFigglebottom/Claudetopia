extends Node
## The quest walker: every authored quest played through on the built world, the way a player
## plays it, and every decision taken each way.
##
##   ./run.sh quests                    all 75, every branch; exits 0 only when every one ends
##   ./run.sh quests --only=grist,vigil  just these (ids, or the part after the slash)
##   ./run.sh quests --no-branches      the first option of every decision only
##   ./run.sh quests --out=<file>       also write the report there
##
## `test_quest_walk` asks whether something in the game could close each objective. This closes
## them. It stands a new game up in the world the builder made, starts each quest the way the game
## starts it (the opening, a line that starts it, the work its giver offers, the quest before it),
## and drives each objective through the services a player's input reaches: it goes to the place
## (teleporting there, and letting the country stream in round it); it finds the person where
## their day has them and talks to them through their own dialogue, choosing lines until it
## reaches the one the objective waits for; it kills with hits through the damage model whatever
## stands where the fight is; it picks things up and reads them where they lie, and takes from a
## shop or a boss what only they have. At every stage it checks that the stage's effects took,
## and when a quest ends it checks that the people who should remember it greet you with it.
##
## A decision is walked every way. Before a choice the game is saved (in memory, through the same
## SaveSystem a slot uses); each option is then chosen from that save and the quest walked to its
## end, and the first option is the one the main walk goes on with. A choice first met inside a
## branch is walked every way there, so every option of every decision is taken once, and the
## number of walks stays one more than the number of options past the first.
##
## What it reports, one line each, prefixed QW: a quest (and branch) that ended, or where it
## stuck and why; and apart from those, WORLD lines for what the built world does to a place the
## content names (a person standing in water, a find inside a rock, a target with no dry ground
## round it), with coordinates, which are the land's to answer rather than the content's.

const WORLD_SCENE := "res://world/world.tscn"
const WORLD_MANIFEST := "res://world/generated/world_manifest.json"
const SEED := 1043
## The hours a person is looked for at, in order: most people are about at midday.
const HOURS := [12.0, 15.0, 10.0, 17.0, 9.0, 19.0, 7.0, 21.0, 13.0, 23.0, 5.0, 2.0]
## How close the walker stands to what it talks to, picks up or hits.
const NEAR_M := 1.6
## A step on a walk somebody walks with you.
const STEP_M := 20.0
## How long the country is given to stand up round a body that has just arrived: the dressing,
## the place's people, and the fights a stage stands (QuestFoes waits 1.5 s after its cell).
const SETTLE_S := 1.2
const STREAM_TIMEOUT_MS := 40000
const HIT_FRACTION := 0.34
## How far from a place's own position what it holds is looked for.
## How far off a tucked-in find the body can stand and still take it: the interact ray's 2.6 m,
## less the eye's height over the find.
const TAKE_REACH_M := 2.2
const FIND_M := 70.0
const QUEST_LOG := preload("res://systems/quests/quest_log.gd")

var world: World = null
var player: Node3D = null
var bag: Inventory = null
var log_node: Node = null
var registry: NpcRegistry = null
var people: NpcStreamer = null
var terrain: TerrainProvider = null

var only: Array[String] = []
var branches := true
var out_path := ""
var log_path := ""
var verbose := false
var _log: FileAccess = null

var results: Array[Dictionary] = []        # {quest, branch, ok, problems[], notes[], stages, secs}
var world_notes: Dictionary = {}            # text -> true
var explored: Dictionary = {}               # "quest|stage|index" -> true
var tried_begin: Dictionary = {}            # quest -> {why, after (walks done then), times}
var _cur: Dictionary = {}                   # the walk being written
var _needed: Dictionary = {}                # quests the wanted ones need walked first
var _t0 := 0
var _errors_at_start := 0
var _fresh: Dictionary = {}                 # the new game as the world stood it up (_snapshot)


# --- the run --------------------------------------------------------------------------------------

func _ready() -> void:
	_args()
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	_t0 = Time.get_ticks_msec()
	_errors_at_start = Log.error_count
	SaveSystem.hold_saves("quest_walker")
	# a new game, as the Naming screen hands one over: a name, a Calling, and the flag that has the
	# world's services start the opening quest
	var calling := str((ContentDB.all("calling")[0] as Dictionary).get("id", ""))
	GameState.reset_for_new_game(SEED)
	GameState.set_flag("player_name", "Wayfarer")
	GameState.set_flag("player_calling", calling)
	GameState.set_flag("player_appearance", {"skin": 3, "hair": 2, "build": 0.5})
	GameState.set_flag("new_game", true)
	if not ResourceLoader.exists(WORLD_SCENE) or not FileAccess.file_exists(WORLD_MANIFEST):
		_say("QW: no built world (./run.sh world); nothing to walk")
		get_tree().quit(1)
		return
	world = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	add_child(world)
	if not world.is_world_ready:
		await world.world_ready
	for i in 20:
		await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player") as Node3D
	bag = Inventory.player_bag(get_tree())
	log_node = Social.quests
	registry = NpcRegistry.ensure()
	people = NpcStreamer.ensure()
	terrain = World.terrain()
	if player == null or bag == null or log_node == null or registry == null or terrain == null:
		_say("QW: the world stood up without a player, a bag, a quest log, the roster or the land")
		get_tree().quit(1)
		return
	var progression := get_tree().get_first_node_in_group("progression")
	if progression != null and progression.has_method("apply_calling"):
		progression.apply_calling(calling, bag)
	bag.add_marks(5000)
	_say("QW: world up in %.0f s; saving through %s" % [(Time.get_ticks_msec() - _t0) / 1000.0,
			", ".join(PackedStringArray(SaveSystem.participants.keys()))])
	# the new game as it stood up, before anything was walked: each fighting style's start is
	# walked from it (_walk_the_style_starts)
	_fresh = _snapshot()
	await _play()
	_report()


func _args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			for part in a.substr(7).split(",", false):
				only.append(part.strip_edges())
		elif a == "--no-branches":
			branches = false
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a == "--verbose":
			verbose = true
		elif a.begins_with("--log="):
			log_path = a.substr(6)


## A line of the report: printed, and written to the --log file at once, so a long walk can be
## read while it runs (the engine's own output is buffered when it goes down a pipe).
func _say(line: String) -> void:
	print(line)
	if log_path == "":
		return
	if _log == null:
		_log = FileAccess.open(log_path, FileAccess.WRITE)
		if _log == null:
			log_path = ""
			return
	_log.store_line(line)
	_log.flush()


func _wanted(quest_id: String) -> bool:
	if only.is_empty():
		return true
	for o in only:
		if quest_id == o or quest_id.ends_with("/" + o):
			return true
	return false


## The authored quests, in the order they are begun: a quest after those whose completion it
## requires, otherwise as the pack lists them.
func _order() -> Array[String]:
	var all: Array[String] = []
	for def in ContentDB.all("quest"):
		if str((def as Dictionary).get("layer", "")) != "radiant":
			all.append(str(def["id"]))
	all.sort()
	var out: Array[String] = []
	var placed: Dictionary = {}
	for _pass in 12:
		for q in all:
			if placed.has(q):
				continue
			var ready := true
			for r in ContentDB.get_def(q).get("requires", []):
				if typeof(r) == TYPE_DICTIONARY and (r as Dictionary).has("quest_done") and not placed.has(str(r["quest_done"])):
					ready = false
			if ready:
				placed[q] = true
				out.append(q)
	for q in all:
		if not placed.has(q):
			out.append(q)
	return out


func _play() -> void:
	var order := _order()
	var guard := 0
	while guard < 500:
		guard += 1
		# a quest under way is walked to its end first (a chain's next one, one a line started on
		# the way), except the main thread past its opening, which waits until nothing else is left
		# to do: the ending's third way asks for more renown than the main thread alone gives
		var active := _pick_active(order, false)
		if active != "":
			await _walk_quest(active)
			continue
		var next := _pick_to_begin(order)
		if next != "":
			var began := await _begin(next)
			if not bool(began["ok"]):
				var times := int((tried_begin.get(next, {"times": 0}) as Dictionary)["times"]) + 1
				tried_begin[next] = {"why": str(began["why"]), "after": results.size(), "times": times}
			continue
		active = _pick_active(order, true)
		if active != "":
			await _walk_quest(active)
			continue
		break
	await _walk_the_style_starts(order)
	for q in order:
		if _wanted(q) and not _walked(q):
			var why := str((tried_begin.get(q, {"why": "nothing began it"}) as Dictionary)["why"])
			if log_node.is_completed(q):
				why = "it ended before the walker came to it (%s)" % log_node.outcome_of(q)
			results.append({"quest": q, "branch": "", "ok": false, "problems": ["never walked: %s" % why],
					"notes": [], "stages": 0, "secs": 0.0})
			_say("QW FAIL %s: never walked: %s" % [_short(q), why])


## The fighting styles' starts (docs/FIGHTING_STYLE_STARTS.md): each style's tutorial is begun by a
## new game of that style, by its opening (Openings, `core:opening/<style>`), never by a line or its
## giver, and its tie-in by a `start_quest` on the tutorial's report. They were "never walked:
## nothing began it" (triage 38). One game has one style, and a style's start comes before the wake
## (the walker's own new game, with no style, opens on it, and Tam Hobb is gone once a warrior has
## woken), so each is walked last, from the new game as it stood up (_fresh), made a new game of
## that style: the Naming's wake undone; the style's flag, `style_start`, its kit and its sayings;
## and the opening's quest started as GameServices._begin_style_start starts it. It, and what it
## starts (the tie-in), are walked to their ends before the next style's.
func _walk_the_style_starts(order: Array[String]) -> void:
	var fallback := str(ContentDB.get_or_empty(Openings.FALLBACK).get("quest", ""))
	for opening_v in ContentDB.all("opening"):
		var opening: Dictionary = opening_v
		if not Openings.is_style_start(opening):
			continue
		var q := str(opening.get("quest", ""))
		if q == "" or not ContentDB.has(q) or _walked(q) or not _wanted_or_needed(q):
			continue
		var style := str(opening["style"])
		await _restore(_fresh)
		if fallback != "":
			log_node.forget(fallback)
		GameState.clear_flag(Openings.NEW_GAME)
		GameState.clear_flag("woke_at_hushline")
		GameState.set_flag(StyleDef.FLAG, style)
		GameState.set_flag(Openings.STYLE_START, true)
		var progression := get_tree().get_first_node_in_group("progression")
		if progression != null and progression.has_method("apply_style"):
			progression.call("apply_style", style, bag, player.get_node_or_null("Equipment"))
		if player.has_method("_ready_style_sayings"):
			player.call("_ready_style_sayings", style)
		registry.simulate_all()
		people.refresh()
		if not bool(log_node.start(q)):
			tried_begin[q] = {"why": "its opening, %s, did not start it" % str(opening.get("id", "?")),
					"after": results.size(), "times": 3}
			continue
		_say("QW: began %s by the %s start" % [_short(q), Ids.name_of(style)])
		# the start and what it starts in turn (its tie-in), not the Naming it hands on to
		var chain: Dictionary = {q: true}
		for _guard in 20:
			var next := ""
			for c in order:
				if next == "" and c != fallback and log_node.is_active(c) and not _walked(c) \
						and (chain.has(c) or _started_by(chain, c)):
					next = c
			if next == "":
				break
			chain[next] = true
			await _walk_quest(next)


func _started_by(chain: Dictionary, q: String) -> bool:
	for c in chain:
		if _starts(ContentDB.get_def(str(c)), q):
			return true
	return false


func _is_late(q: String) -> bool:
	var opening := str(ContentDB.get_or_empty(GameServices.OPENING).get("quest", ""))
	return str(ContentDB.get_def(q).get("layer", "")) == "main" and q != opening


func _pick_active(order: Array[String], late: bool) -> String:
	for q in order:
		if log_node.is_active(q) and not _walked(q) and _is_late(q) == late and _wanted_or_needed(q):
			return q
	return ""


## The next quest to begin: one not tried yet, or tried before another quest ended that may have
## opened its way (a flag, a requirement), three times at most.
func _pick_to_begin(order: Array[String]) -> String:
	for q in order:
		if log_node.is_known(q) or _is_late(q) or not _wanted_or_needed(q):
			continue
		var t: Dictionary = tried_begin.get(q, {})
		if t.is_empty() or (int(t["after"]) < results.size() and int(t["times"]) < 3):
			return q
	return ""


## Wanted, or on the way to one that is: a quest another wanted quest requires is walked too.
func _wanted_or_needed(q: String) -> bool:
	if _wanted(q):
		return true
	if _needed.is_empty():
		_needed["-"] = true
		for other in only:
			for def in ContentDB.all("quest"):
				var id := str(def["id"])
				if id == other or id.ends_with("/" + other):
					_needed.merge(_requires_chain(id), true)
	return _needed.has(q)


func _requires_chain(q: String) -> Dictionary:
	var out: Dictionary = {}
	var todo: Array = [q]
	while not todo.is_empty():
		var id := str(todo.pop_back())
		for r in ContentDB.get_def(id).get("requires", []):
			if typeof(r) == TYPE_DICTIONARY and (r as Dictionary).has("quest_done"):
				var before := str(r["quest_done"])
				if not out.has(before):
					out[before] = true
					todo.append(before)
		# and the quest that starts it
		for def in ContentDB.all("quest"):
			if _starts(def, id) and not out.has(str(def["id"])):
				out[str(def["id"])] = true
				todo.append(str(def["id"]))
	return out


func _starts(def: Dictionary, q: String) -> bool:
	return JSON.stringify(def.get("stages", [])).contains("\"start_quest\":\"%s\"" % q) \
			or JSON.stringify(def.get("rewards", {})).contains("\"start_quest\":\"%s\"" % q)


func _walked(q: String) -> bool:
	for r in results:
		if str(r["quest"]) == q and str(r["branch"]) == "":
			return true
	return false


# --- beginning a quest --------------------------------------------------------------------------------

## Starts a quest the way the game does: a line somebody says, or the work its giver offers. Its
## `requires` are met by the quests before it; reputation short of a line's floor is made up and
## said, since standing is earned in many ways the walker does not play.
func _begin(q: String) -> Dictionary:
	var def := ContentDB.get_def(q)
	var topped: Array[String] = []
	for r_v in def.get("requires", []):
		if typeof(r_v) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = r_v
		if Conditions.all_of([r], Social.ctx):
			continue
		if r.has("rep_min"):
			var faction := str(r["rep_min"][0])
			var need := int(r["rep_min"][1])
			var have: int = Social.factions.reputation(faction)
			Social.factions.add_reputation(faction, need - have, "quest walker")
			topped.append("%s %d short of %d" % [Ids.name_of(faction), need - have, need])
			continue
		return {"ok": false, "why": "requires %s" % JSON.stringify(r)}
	var ways: Array[String] = []
	var want := {"start_quest": q}
	var lines := DialogueSteer.speakers_of(want)
	var giver := str(def.get("giver", ""))
	var who: Array[String] = []
	for l in lines:
		if not who.has(str(l["npc"])):
			who.append(str(l["npc"]))
	if giver != "" and not who.has(giver):
		who.append(giver)
	for npc in who:
		var met := await _meet(npc)
		if not bool(met["ok"]):
			ways.append(str(met["why"]))
			continue
		var r := DialogueSteer.drive(npc, {"effect": want})
		if log_node.is_known(q):
			_say("QW: began %s with %s%s" % [_short(q), Ids.name_of(npc),
					"" if topped.is_empty() else " (reputation made up: %s)" % ", ".join(topped)])
			return {"ok": true, "why": ""}
		ways.append("%s: %s" % [Ids.name_of(npc), str(r["why"])])
	if who.is_empty():
		ways.append("no line starts it and it has no giver")
	return {"ok": false, "why": "; ".join(ways)}


# --- walking a quest ------------------------------------------------------------------------------------

func _walk_quest(q: String) -> void:
	_cur = _new_walk(q, "")
	var t := Time.get_ticks_msec()
	await _walk(q)
	_close_walk(q, t)


func _new_walk(q: String, branch: String) -> Dictionary:
	return {"quest": q, "branch": branch, "ok": false, "problems": [], "notes": [], "stages": 0, "secs": 0.0,
			"flags": {}}


func _close_walk(q: String, started_ms: int) -> void:
	_cur["secs"] = (Time.get_ticks_msec() - started_ms) / 1000.0
	if log_node.is_completed(q) or log_node.is_failed(q):
		_after_the_end(q)
	_cur["ok"] = (_cur["problems"] as Array).is_empty() and (log_node.is_completed(q) or _ends_in_failure_by_choice(q))
	_cur.erase("flags")
	results.append(_cur)
	var label := _short(q) + ("" if str(_cur["branch"]) == "" else " [%s]" % _cur["branch"])
	_say("QW %s %s: %d stages, %s, %.0f s" % ["PASS" if bool(_cur["ok"]) else "FAIL", label, int(_cur["stages"]),
			log_node.outcome_of(q) if log_node.is_completed(q) else ("failed" if log_node.is_failed(q) else "still at %s" % log_node.stage_id_of(q)),
			float(_cur["secs"])])
	for p in _cur["problems"]:
		_say("QW   - %s" % p)
	for n in _cur["notes"]:
		_say("QW   ~ %s" % n)
	_cur = {}


## A quest that fails because the decision taken says it does (the pilgrim who turns back) has
## ended as written.
func _ends_in_failure_by_choice(q: String) -> bool:
	return log_node.is_failed(q) and str(_cur.get("branch", "")) != ""


func _problem(text: String) -> void:
	if _cur.is_empty():
		return
	(_cur["problems"] as Array).append(text)


func _note(text: String) -> void:
	if not _cur.is_empty():
		(_cur["notes"] as Array).append(text)


## What the built world does to something the content names, said once with where it is.
func _world(text: String) -> void:
	if world_notes.has(text):
		return
	world_notes[text] = true
	_say("QW WORLD %s" % text)


## Walks the quest from wherever it stands to its end, or until something cannot be done.
func _walk(q: String) -> void:
	var guard := 0
	while log_node.is_active(q) and guard < 60:
		guard += 1
		var at: int = log_node.stage_of(q)
		var stage: Dictionary = log_node.stage_def(q, at)
		var before := _progress_sign(q)
		var objs: Array = stage.get("objectives", [])
		var i := _next_objective(q, at, stage)
		var did: Dictionary = {}
		var blocked := _blocked_objective(q, stage)
		if i < 0 and blocked != "":
			var earned := await _unblock(q, stage)
			if earned == "":
				continue
			_problem("stage '%s': %s%s" % [str(stage.get("id", at)), blocked, earned])
			return
		if i < 0:
			did = await _move_on(q, stage)
		else:
			var o: Dictionary = objs[i]
			if str(o.get("type", "")) == "choice":
				did = await _choice(q, stage, i)
			else:
				did = await _drive(q, stage, i)
		if verbose:
			_say("QW . %s %s %s -> %s %s | at %s" % [_short(q), str(stage.get("id", at)),
					_objective_text(q, objs[i] as Dictionary) if i >= 0 else "(moves on)",
					"ok" if bool(did.get("ok", false)) else "no", str(did.get("why", "")),
					"(%.0f, %.0f)" % [player.global_position.x, player.global_position.z]])
		if not log_node.is_active(q) and not log_node.is_completed(q) and not log_node.is_failed(q):
			break
		_after_step(q, at, stage)
		if _progress_sign(q) == before and log_node.is_active(q):
			var what := "stage '%s'" % str(stage.get("id", at))
			if i >= 0:
				what += ", %s" % _objective_text(q, objs[i] as Dictionary)
			_problem("%s: %s" % [what, str(did.get("why", "")) if str(did.get("why", "")) != "" else "done, and it did not close"])
			return


## Something that changes when anything is done: the stage and every count.
func _progress_sign(q: String) -> String:
	var rec: Dictionary = (log_node.get("quests") as Dictionary).get(q, {})
	return "%s|%s|%s" % [str(rec.get("stage", "")), JSON.stringify(rec.get("counts", {})), str(rec.get("state", ""))]


## Whether objective `i` of the stage the quest was at is still to do: the quest is at that stage
## and the objective is not done. A stage that has moved on has closed it.
func _still_open(q: String, at_stage: int, i: int) -> bool:
	return log_node.is_active(q) and log_node.stage_of(q) == at_stage and not log_node.objective_done(q, i)


## An objective that waits on a flag somebody's line sets (Aud Fennick agrees to be walked only
## once Cadwen has asked you to walk her): the flag is earned the way a player earns it, by
## saying that line, and a line that is itself gated on another flag has that one earned first.
## "" when every objective's `requires` holds after; otherwise why not, for the report.
func _unblock(q: String, stage: Dictionary) -> String:
	var tried: Array[String] = []
	for o in stage.get("objectives", []):
		for c in (o as Dictionary).get("requires", []):
			if typeof(c) == TYPE_DICTIONARY and (c as Dictionary).size() == 1 and (c as Dictionary).has("flag") and not Conditions.all_of([c], Social.ctx):
				var why := await _earn_flag(str(c["flag"]), 0)
				if why != "":
					tried.append(why)
	if _blocked_objective(q, stage) == "":
		return ""
	return " (%s)" % ("; ".join(tried) if not tried.is_empty() else "no flag to earn")


func _earn_flag(flag: String, depth: int) -> String:
	var want := {"set_flag": flag}
	var lines := DialogueSteer.speakers_of(want)
	if lines.is_empty():
		return "no line sets %s" % flag
	var tried: Array[String] = []
	for l in lines:
		# the flags the line waits on: its own conditions and those of every choice that leads to it
		var gates: Array = (l["conditions"] as Array).duplicate()
		if int(l["choice"]) < 0:
			var nodes: Dictionary = ContentDB.get_or_empty(str(l["dialogue"])).get("nodes", {})
			for n in nodes.values():
				for ch in (n as Dictionary).get("choices", []):
					if typeof(ch) == TYPE_DICTIONARY and str((ch as Dictionary).get("next", "")) == str(l["node"]):
						gates.append_array((ch as Dictionary).get("conditions", []))
		if depth < 3:
			# only a flag that must be set; one inside a `not` or an `any` is not earned
			for g in gates:
				if typeof(g) == TYPE_DICTIONARY and (g as Dictionary).size() == 1 and (g as Dictionary).has("flag") \
						and str(g["flag"]) != flag and not Conditions.all_of([g], Social.ctx):
					await _earn_flag(str(g["flag"]), depth + 1)
		var met := await _meet(str(l["npc"]))
		if not bool(met["ok"]):
			tried.append(str(met["why"]))
			continue
		var r := DialogueSteer.drive(str(l["npc"]), {"effect": want})
		if Conditions.all_of([{"flag": flag}], Social.ctx):
			if verbose:
				_say("QW . earned %s from %s" % [flag, Ids.name_of(str(l["npc"]))])
			return ""
		tried.append("%s: %s" % [Ids.name_of(str(l["npc"])), str(r["why"])])
	return "%s not earned: %s" % [flag, "; ".join(tried)]


## An objective left to do that waits on a `requires` nothing done so far has met, said; "" when none.
func _blocked_objective(q: String, stage: Dictionary) -> String:
	var objs: Array = stage.get("objectives", [])
	for i in objs.size():
		var o: Dictionary = objs[i]
		if bool(o.get("optional", false)) or log_node.objective_done(q, i):
			continue
		if not Conditions.all_of(o.get("requires", []), Social.ctx):
			return "%s waits on %s, and nothing in the stage made it hold" % [_objective_text(q, o), JSON.stringify(o.get("requires", []))]
	return ""


## The next objective to drive: the first not done, not optional, whose `requires` hold.
func _next_objective(q: String, at: int, stage: Dictionary) -> int:
	var objs: Array = stage.get("objectives", [])
	for i in objs.size():
		var o: Dictionary = objs[i]
		if bool(o.get("optional", false)) or log_node.objective_done(q, i):
			continue
		if not Conditions.all_of(o.get("requires", []), Social.ctx):
			continue
		return i
	return -1


func _objective_text(q: String, o: Dictionary) -> String:
	return "%s %s \"%s\"" % [str(o.get("type", "")), Ids.name_of(str(o.get("target", ""))), log_node.objective_text(o, q)]


## After each step: a stage passed has its effects checked.
func _after_step(q: String, was_at: int, was_stage: Dictionary) -> void:
	var now_at: int = log_node.stage_of(q) if log_node.is_active(q) else -1
	if now_at == was_at and log_node.is_active(q):
		return
	_cur["stages"] = int(_cur["stages"]) + 1
	_check_effects(q, was_stage.get("on_complete", []), "stage '%s'" % str(was_stage.get("id", was_at)))


func _drive(q: String, stage: Dictionary, i: int) -> Dictionary:
	var o: Dictionary = (stage.get("objectives", []) as Array)[i]
	match str(o.get("type", "")):
		"talk":
			return await _talk(q, stage, i, o)
		"reach":
			return await _reach(o)
		"kill":
			return await _kill(q, i, o)
		"collect":
			return await _collect(q, o)
		"read_book":
			return await _read(q, stage, i, o)
		"deliver":
			return await _deliver(q, stage, i, o)
		"escort":
			return await _escort(q, i, o)
		"use_item":
			return await _use(q, o)
		"rest_at":
			return await _rest(o)
		"act":
			return await _act(o)
	return {"ok": false, "why": "the walker drives no '%s'" % str(o.get("type", ""))}


# --- talk -------------------------------------------------------------------------------------------------

func _talk(q: String, stage: Dictionary, i: int, o: Dictionary) -> Dictionary:
	var npc := str(o.get("target", ""))
	var met := await _meet(npc)
	if not bool(met["ok"]):
		return met
	var topic := str(o.get("topic", ""))
	var goal: Dictionary = {"node": topic} if topic != "" else {"quest": q, "flags": _flags_of(q)}
	if topic == "" and QuestRoutes.dialogue_closes(q, stage, i):
		goal = {"effect": {"complete_objective": [q, null]}}
	var r := DialogueSteer.drive(npc, goal)
	if not bool(r["ok"]):
		return {"ok": false, "why": str(r["why"])}
	return {"ok": true, "why": ""}


## Every flag the quest's own text tests or sets: what makes a line in a conversation about it.
func _flags_of(q: String) -> Array:
	var out: Array = []
	var text := JSON.stringify(ContentDB.get_def(q))
	var rx := RegEx.new()
	rx.compile("\"(?:flag|set_flag|flag_not|clear_flag)\":\\s*\\[?\"([^\"]+)\"")
	for m in rx.search_all(text):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


# --- going places -------------------------------------------------------------------------------------------

## Stands the player at a point on the ground and lets the country stand up round them.
func _go(pos: Vector3) -> void:
	_close_menus()
	if Interiors.in_interior():
		Interiors.exit()
		await get_tree().process_frame
	var p := Vector3(pos.x, terrain.get_height(pos.x, pos.z) + 0.4, pos.z)
	world.move_target(p)
	var t := Time.get_ticks_msec()
	while not world.streamer.is_loaded_around(p, 1) and Time.get_ticks_msec() - t < STREAM_TIMEOUT_MS:
		await get_tree().process_frame
	if not world.streamer.is_loaded_around(p, 1):
		_stream_stalled(p)
	await _settle(SETTLE_S)
	_stand(p)
	log_node.check_reach(player.global_position)


## Shuts what a thing done left open, the way a player shuts a book they have read before walking
## on: a book, a shop or a letter is a full-screen menu and pauses the game, and a paused game
## streams nothing and stands nobody up.
func _close_menus() -> void:
	var stack: Array = UI.get("_stack") if UI.get("_stack") != null else []
	if not stack.is_empty():
		if verbose:
			var ids: Array[String] = []
			for e in stack:
				ids.append(str((e as Dictionary).get("id", "?")))
			_say("QW . shut %s" % ", ".join(ids))
		UI.close_all()
	if get_tree().paused:
		_say("QW ! the game was paused with no menu open; unpaused")
		get_tree().paused = false


## Why the country did not stream in round a point: said once per stall, for the log.
func _stream_stalled(p: Vector3) -> void:
	var st := world.streamer
	var tgt: Node3D = st.target
	var states: Array[String] = []
	for c in st.missing_around(p, 1):
		states.append("%s %s" % [str(c), st.cell_state(c)])
	_say("QW ! the country did not stream in round (%.0f, %.0f) in %d s%s: streamer %s, following %s at %s, the player at %s; %s; queue %s" % [
			p.x, p.z, STREAM_TIMEOUT_MS / 1000, " (the game is paused)" if get_tree().paused else "", "on" if st.enabled else "OFF",
			"nothing" if tgt == null else ("%s%s" % [tgt.name, "" if is_instance_valid(tgt) and tgt.is_inside_tree() else " (gone)"]),
			"-" if tgt == null or not tgt.is_inside_tree() else str(Vector2(tgt.global_position.x, tgt.global_position.z).round()),
			str(Vector2(player.global_position.x, player.global_position.z).round()), ", ".join(states), str(st.queue())])


## A step along the way: the ring is mostly standing already.
func _step_to(pos: Vector3) -> void:
	_close_menus()
	var p := Vector3(pos.x, terrain.get_height(pos.x, pos.z) + 0.4, pos.z)
	world.move_target(p)
	var t := Time.get_ticks_msec()
	while not world.streamer.is_loaded_around(p, 1) and Time.get_ticks_msec() - t < STREAM_TIMEOUT_MS:
		await get_tree().process_frame
	await get_tree().process_frame
	_stand(p)


func _stand(p: Vector3) -> void:
	player.global_position = Vector3(p.x, terrain.get_height(p.x, p.z) + 0.2, p.z)
	if player.has_method("reset_physics_interpolation"):
		player.reset_physics_interpolation()
	if (player as Object).get("velocity") != null:
		player.set("velocity", Vector3.ZERO)
	_heal()


func _heal() -> void:
	if player.has_method("full_restore"):
		player.call("full_restore")


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Where a place or point of interest stands: its built pad, else its data.
func _pad(id: String) -> Vector3:
	var p := world.place_position(id)
	if p == Vector3.ZERO:
		var xz := WorldProbe.xz_of(ContentDB.get_or_empty(id))
		p = Vector3(xz.x, terrain.get_height(xz.x, xz.y), xz.y)
	return p


func _xz(id: String) -> Vector2:
	return WorldProbe.xz_of(ContentDB.get_or_empty(id))


## Goes into an interior from outside its place, the way its door would take you.
func _enter(interior: String) -> bool:
	var def := ContentDB.get_or_empty(interior)
	if def.is_empty():
		return false
	var place := str(def.get("place", ""))
	if place != "" and ContentDB.has(place):
		await _go(_pad(place))
	var ok: bool = Interiors.enter(interior)
	for k in 30:
		await get_tree().process_frame
	await _settle(1.0)
	people.refresh()
	_heal()
	return ok


## Dry ground within `radius` of a point, nearest first; the point itself when it is dry.
func _dry_near(xz: Vector2, radius: float) -> Variant:
	if not _wet(xz.x, xz.y):
		return xz
	for r_i in range(1, int(radius / 4.0) + 1):
		var r := float(r_i) * 4.0
		for k in 16:
			var a := float(k) * TAU / 16.0
			var p := xz + Vector2(cos(a), sin(a)) * r
			if not _wet(p.x, p.y):
				return p
	return null


func _wet(x: float, z: float) -> bool:
	return terrain.is_water(x, z)


# --- people ---------------------------------------------------------------------------------------------------

## Finds a person where their day has them, and stands beside them. The hours are tried in turn
## until they are out of doors; somebody who never is is looked for in their own house.
func _meet(npc: String) -> Dictionary:
	if not ContentDB.has(npc):
		return {"ok": false, "why": "%s is nobody in the pack" % npc}
	if registry.is_gone(npc):
		return {"ok": false, "why": "%s has gone (their gone_when holds)" % Ids.name_of(npc)}
	if not registry.is_alive(npc):
		return {"ok": false, "why": "%s is dead" % Ids.name_of(npc)}
	# already standing near
	var here: Node = registry.actor(npc)
	if here is Node3D and _flat(player.global_position, (here as Node3D).global_position) < 30.0 and not Interiors.in_interior():
		_stand_beside(here as Node3D)
		return {"ok": true, "why": ""}
	var hour_was: float = WorldClock.time_hours
	for h in HOURS:
		WorldClock.set_time(float(h))
		registry.simulate(npc, "clear")
		var place := registry.place_of(npc)
		if place == "" or registry.is_indoors(npc):
			continue
		var at := registry.spawn_position(npc)
		if at == Vector3.ZERO or at == Vector3.INF:
			continue
		await _go(at + Vector3(2.0, 0.0, 0.0))
		registry.simulate(npc, "clear")
		people.refresh()
		for k in 6:
			await get_tree().process_frame
		var body: Node = registry.actor(npc)
		if body == null:
			body = registry.spawn(npc)
		if body is Node3D:
			await get_tree().process_frame
			_check_person(npc, body as Node3D)
			_stand_beside(body as Node3D)
			return {"ok": true, "why": ""}
	# only ever under a roof: their house
	var home := _home_of(npc)
	if home != "":
		WorldClock.set_time(hour_was)
		registry.simulate(npc, "clear")
		if await _enter(home):
			var body: Node = registry.actor(npc)
			if body is Node3D:
				_stand_beside(body as Node3D)
			_note("%s found at home in %s" % [Ids.name_of(npc), Ids.name_of(home)])
			return {"ok": true, "why": ""}
	WorldClock.set_time(hour_was)
	var place_now := registry.place_of(npc)
	_world("%s: never stood up anywhere a player could walk to them (place %s)" % [Ids.name_of(npc), place_now])
	return {"ok": false, "why": "%s could not be found in the world (their place %s)" % [Ids.name_of(npc), place_now]}


func _home_of(npc: String) -> String:
	for def in ContentDB.all("interior"):
		if str((def as Dictionary).get("resident", (def as Dictionary).get("resident_npc", ""))) == npc:
			return str(def["id"])
	return ""


func _stand_beside(body: Node3D) -> void:
	var p := body.global_position + Vector3(NEAR_M, 0.0, 0.0)
	if Interiors.in_interior():
		player.global_position = p + Vector3(0.0, 0.2, 0.0)
	else:
		_stand(p)


## What the built world does to where a person stands: under water, in the air or the ground,
## or inside something solid.
func _check_person(npc: String, body: Node3D) -> void:
	var p := body.global_position
	var ground := terrain.get_height(p.x, p.z)
	var where := "(%.0f, %.0f)" % [p.x, p.z]
	if _wet(p.x, p.z):
		_world("%s stands in water at %s (%s)" % [Ids.name_of(npc), where, Ids.name_of(registry.place_of(npc))])
	elif absf(p.y - ground) > 3.0:
		_world("%s stands %.1f m %s the ground at %s" % [Ids.name_of(npc), absf(p.y - ground), "above" if p.y > ground else "under", where])
	elif _shut_in(p):
		_world("%s stands inside something solid at %s (%s; %s)" % [Ids.name_of(npc), where, Ids.name_of(registry.place_of(npc)), _what_shuts(p)])


## Is a body's room at this point taken by something solid (or roofed over by a hull)?
func _shut_in(p: Vector3) -> bool:
	return _what_shuts(p) != ""


## What is solid in a body's room at this point: the nearest named thing that owns the collider
## (the dressing, the landmark, the cell), "" when the room is clear.
func _what_shuts(p: Vector3) -> String:
	var space := player.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.2
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1 << 0
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0.0, 0.75, 0.0))
	var hits := space.intersect_shape(q, 1)
	if hits.is_empty():
		return ""
	var node: Node = hits[0].get("collider") as Node
	var shape_says := ""
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		var idx := int(hits[0].get("shape", 0))
		var owner_id := body.shape_find_owner(idx)
		var owner := body.shape_owner_get_owner(owner_id) as Node3D
		if owner != null:
			var sh: Shape3D = body.shape_owner_get_shape(owner_id, 0)
			var o := owner.global_position
			shape_says = " %s %s at (%.1f, %.1f, %.1f)%s" % [sh.get_class() if sh != null else "?",
					str((sh as BoxShape3D).size) if sh is BoxShape3D else "", o.x, o.y, o.z,
					" [%s]" % str(owner.get_meta("surface", "")) if owner.has_meta("surface") else ""]
	var names: Array[String] = []
	while node != null and names.size() < 3 and not str(node.name).begins_with("Cell_"):
		names.push_front(str(node.name))
		node = node.get_parent()
	return ("/".join(names) if not names.is_empty() else "the ground's own collision") + shape_says


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- reach ------------------------------------------------------------------------------------------------------

func _reach(o: Dictionary) -> Dictionary:
	var id := str(o.get("target", ""))
	var xz := _xz(id)
	if xz == Vector2.ZERO and not ContentDB.get_or_empty(id).has("position"):
		return {"ok": false, "why": "%s says nowhere" % id}
	var radius := float(o.get("radius", QUEST_LOG.REACH_RADIUS_M))
	var spot: Variant = _dry_near(xz, radius)
	if spot == null:
		_world("%s at (%.0f, %.0f): no dry ground within its %.0f m" % [Ids.name_of(id), xz.x, xz.y, radius])
		spot = xz
	var s: Vector2 = spot
	await _go(Vector3(s.x, 0.0, s.y))
	log_node.check_reach(player.global_position)
	return {"ok": true, "why": "stood at (%.0f, %.0f), %.0f m from its middle" % [player.global_position.x, player.global_position.z,
			Vector2(player.global_position.x, player.global_position.z).distance_to(xz)]}


# --- kill ---------------------------------------------------------------------------------------------------------

func _kill(q: String, i: int, o: Dictionary) -> Dictionary:
	var target := str(o.get("target", ""))
	var where := str(o.get("where", ""))
	var when := str(o.get("when", "always"))
	_set_hour_for(when)
	var inside := Ids.type_of(where) == "interior"
	var at := Vector3.INF
	if inside:
		if not await _enter(where):
			return {"ok": false, "why": "could not go into %s" % Ids.name_of(where)}
	elif where != "" and where != KillPlaces.ANYWHERE:
		at = _pad(where)
		await _go(at + Vector3(4.0, 0.0, 4.0))
	else:
		var near := _foes_anywhere(target)
		if near == Vector3.INF:
			return {"ok": false, "why": "no %s stands anywhere in the built world" % Ids.name_of(target)}
		at = near
		await _go(at + Vector3(4.0, 0.0, 0.0))
	var radius := float(o.get("radius", KillPlaces.RADIUS_M))
	var foes := QuestFoes.ensure()
	var felled := 0
	var waits := 0
	var at_stage: int = log_node.stage_of(q)
	while _still_open(q, at_stage, i) and waits < 12:
		if foes != null:
			foes.refresh()
		var foe := _nearest_foe(target, where if inside else "", at, radius)
		if foe == null:
			waits += 1
			await _settle(1.0)
			continue
		if await _fell(foe):
			felled += 1
		await get_tree().process_frame
	if not _still_open(q, at_stage, i):
		return {"ok": true, "why": ""}
	var need := maxi(1, int(o.get("count", 1)))
	return {"ok": false, "why": "%d of %d %s put down at %s: no more stood there%s [%s]" % [felled, need, Ids.name_of(target),
			Ids.name_of(where) if where != "" else "anywhere", "" if when == "always" else " (" + when + ")",
			_foes_seen(target, at, radius, q)]}


## What stood of a kind, for a fight that could not be finished: every one in the tree, how far
## from the place and in what state, and what the stage's own foes (QuestFoes) made of it.
func _foes_seen(target: String, at: Vector3, radius: float, q: String) -> String:
	var parts: Array[String] = []
	var n := 0
	for node in get_tree().get_nodes_in_group("enemy"):
		var e := node as Enemy
		if e == null or e.content_id() != target:
			continue
		n += 1
		if parts.size() < 6:
			var d := _flat(e.global_position, at) if at != Vector3.INF else -1.0
			parts.append("%s%s at (%.0f, %.0f) %.0f m, %.0f hp%s" % ["dead " if e.dead else "", "inside " + KillPlaces.interior_of(e) if KillPlaces.interior_of(e) != "" else "",
					e.global_position.x, e.global_position.z, d, e.health, " (radius %.0f)" % radius if d > radius else ""])
	var foes := QuestFoes.ensure()
	var want := ""
	if foes != null:
		for key in foes.wanted().keys():
			if str(key).begins_with(q + "|"):
				var g: Variant = (foes.get("_groups") as Dictionary).get(key, "none")
				var w_at: Vector3 = (foes.wanted()[key] as Dictionary)["at"]
				var fc := WorldProbe.cell_of(w_at)
				var cells: Dictionary = foes.get("_cells")
				want = "QuestFoes wants %s at (%.0f, %.0f), %.0f m from the player, group %s; its cell %s %s" % [key, w_at.x, w_at.z,
						_flat(player.global_position, w_at), "null (enough stood)" if g == null else str(g), str(fc),
						"loaded %d ms ago" % (Time.get_ticks_msec() - int(cells[fc])) if cells.has(fc) else "never said loaded"]
	return "%d of them in the world: %s; %s; hour %.1f" % [n, "; ".join(parts), want if want != "" else "QuestFoes wants nothing here", WorldClock.time_hours]


func _set_hour_for(when: String) -> void:
	match when:
		"night":
			WorldClock.set_time(23.0)
		"dawn":
			WorldClock.set_time(6.0)
		"dusk":
			WorldClock.set_time(19.5)
		"midnight":
			WorldClock.set_time(23.5)
		"day":
			WorldClock.set_time(12.0)
		_:
			pass


## A living foe of that kind in the interior, or in the open within `radius` of `at`.
func _nearest_foe(target: String, interior: String, at: Vector3, radius: float) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	var def := ContentDB.get_or_empty(target)
	for node in get_tree().get_nodes_in_group("enemy"):
		var e := node as Enemy
		if e == null or e.dead or e.is_queued_for_deletion():
			continue
		if not QUEST_LOG._matches(target, e.content_id(), def):
			continue
		var e_in := KillPlaces.interior_of(e)
		if interior != "":
			if e_in != interior:
				continue
		elif e_in != "":
			continue
		elif at != Vector3.INF and _flat(e.global_position, at) > radius:
			continue
		var d := _flat(e.global_position, player.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## Where the built cells stand one of these, nearest the player.
func _foes_anywhere(target: String) -> Vector3:
	var best := Vector3.INF
	var dir := DirAccess.open("res://world/generated/cells")
	if dir == null:
		return best
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string("res://world/generated/cells/" + file)
		if not text.contains(target):
			continue
		var cell: Variant = JSON.parse_string(text)
		if typeof(cell) != TYPE_DICTIONARY:
			continue
		for s in (cell as Dictionary).get("spawns", []):
			if str((s as Dictionary).get("def", "")) == target:
				var pos: Array = (s as Dictionary).get("pos", [0, 0, 0])
				var p := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
				if best == Vector3.INF or _flat(p, player.global_position) < _flat(best, player.global_position):
					best = p
	return best


## Puts a foe down with hits through the damage model, standing where it can be struck.
func _fell(e: Enemy) -> bool:
	var p := e.global_position + Vector3(NEAR_M, 0.0, 0.0)
	player.global_position = p + Vector3(0.0, 0.3, 0.0)
	if e.is_boss:
		e.start_boss()
	for k in 90:
		if not is_instance_valid(e) or e.dead:
			break
		var hit := HitData.new()
		hit.amount = maxf(e.max_health * HIT_FRACTION, 10.0)
		hit.kind = "slash"
		hit.poise_damage = 60.0
		hit.attacker = player
		hit.source = player
		hit.swing_id = randi()
		hit.origin = player.global_position
		e.take_hit(hit)
		_heal()
		await get_tree().process_frame
	return not is_instance_valid(e) or e.dead


# --- things ---------------------------------------------------------------------------------------------------------

func _collect(q: String, o: Dictionary) -> Dictionary:
	var item := str(o.get("target", ""))
	var need := maxi(1, int(o.get("count", 1)))
	var r := await _obtain(item, need, q)
	log_node.call("_sync_stage", q)
	return r


## Gets `need` of an item into the bag the ways the game offers, surest first: where a quest puts
## it, a line that hands it over, a boss that drops it, a shop that sells it, a house or a cave
## that holds it.
func _obtain(item: String, need: int, q: String) -> Dictionary:
	if bag.count(item) >= need:
		return {"ok": true, "why": ""}
	var tried: Array[String] = []
	# what a fight just left lying, or anything of it standing in reach already
	for k in need:
		var near := await _pick_up_near(item, Vector3.INF)
		if not bool(near["ok"]):
			break
	if bag.count(item) >= need:
		return {"ok": true, "why": ""}
	# where a quest puts it
	for row in _rows_for(item, q):
		var r := await _pick_up_row(row)
		if bag.count(item) >= need:
			return {"ok": true, "why": ""}
		tried.append(str(r["why"]))
	# a quest's own box whose loot promises it (the collector's strongbox holds the tithe-book):
	# gone to, its lock picked as the lesson does, and emptied
	for how in ItemSources.how_given(item):
		if not str(how).begins_with("loot:"):
			continue
		var table := str(how).trim_prefix("loot:")
		var spots := QuestSpots.ensure()
		for p in (spots.props.values() if spots != null else []):
			if not (p is WorldContainer) or str((p as WorldContainer).loot_table) != table:
				continue
			var box := p as WorldContainer
			await _go(box.global_position + Vector3(1.5, 0.0, 0.0))
			if box.locked:
				box.unlock()
			box.ensure_loot()
			box.take_all(player)
			await get_tree().process_frame
			if bag.count(item) >= need:
				return {"ok": true, "why": ""}
			tried.append("%s held no %s" % [box.display_name, Ids.name_of(item)])
	# a line that hands it over
	for l in DialogueSteer.speakers_of({"give_item": [item, null]}):
		if not Conditions.all_of(l["conditions"], Social.ctx) and not _mentions_quest(l["conditions"], q):
			continue
		var met := await _meet(str(l["npc"]))
		if not bool(met["ok"]):
			tried.append(str(met["why"]))
			continue
		var r2 := DialogueSteer.drive(str(l["npc"]), {"effect": {"give_item": [item, null]}})
		if bag.count(item) >= need:
			return {"ok": true, "why": ""}
		tried.append("%s: %s" % [Ids.name_of(str(l["npc"])), str(r2["why"])])
	# a boss that drops it
	for how in ItemSources.how_given(item):
		var parts := str(how).split(" ", false, 1)
		if parts.size() == 2 and parts[0] == "drop" and Ids.type_of(parts[1]) == "boss":
			var r3 := await _put_down_boss(parts[1])
			if bag.count(item) >= need:
				return {"ok": true, "why": ""}
			await _gather_drops(item)
			if bag.count(item) >= need:
				return {"ok": true, "why": ""}
			tried.append(str(r3["why"]) if str(r3["why"]) != "" else "%s fell and dropped none" % Ids.name_of(parts[1]))
	# a shop
	for table in ItemSources.sold_by(item):
		var r4 := await _buy(item, need, str(table))
		if bag.count(item) >= need:
			return {"ok": true, "why": ""}
		tried.append(str(r4["why"]))
	# a house or a cave
	for interior in _interiors_holding(item):
		if await _enter(interior):
			await _pick_up_near(item, Vector3.INF)
		if bag.count(item) >= need:
			return {"ok": true, "why": ""}
		tried.append("nothing of it lay in %s" % Ids.name_of(interior))
	if tried.is_empty():
		tried.append("nothing gives, sells or puts down %s" % Ids.name_of(item))
	return {"ok": false, "why": "%s: %s" % [Ids.name_of(item), "; ".join(tried)]}


func _mentions_quest(conds: Variant, q: String) -> bool:
	return JSON.stringify(conds).contains(q)


## QuestItems' rows for an item, this quest's first.
func _rows_for(item: String, q: String) -> Array[Dictionary]:
	var mine: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	for row in QuestItems.placements():
		if str(row.get("item", "")) != item or str(row.get("kind", "")) != "item":
			continue
		if str(row.get("quest_id", "")) == q:
			mine.append(row)
		else:
			others.append(row)
	return mine + others


func _pick_up_row(row: Dictionary) -> Dictionary:
	var items := QuestItems.ensure()
	var key := str(row["key"])
	if items != null and items.is_taken(key):
		return {"ok": false, "why": "already taken from %s" % Ids.name_of(str(row["where"]))}
	var where := str(row["where"])
	var at := Vector3.INF
	if Ids.type_of(where) == "interior":
		if not await _enter(where):
			return {"ok": false, "why": "could not go into %s" % Ids.name_of(where)}
	else:
		at = _pad(where)
		await _go(at + Vector3(3.0, 0.0, 0.0))
		if items != null:
			items.raise_in_loaded_cells()
			await get_tree().process_frame
	var got := await _pick_up_near(str(row["item"]), at)
	if not bool(got["ok"]):
		return {"ok": false, "why": "%s did not lie at %s [%s]" % [Ids.name_of(str(row["item"])), Ids.name_of(where),
				_lying_seen(str(row["item"]), key, at)]}
	return got


## Where the things of an id lie in the tree, and what QuestItems holds for the row: for a find
## that was not where its quest says.
func _lying_seen(id: String, key: String, at: Vector3) -> String:
	var parts: Array[String] = []
	for node in get_tree().get_nodes_in_group("interactable"):
		var here := ""
		if node is WorldItem and (node as WorldItem).item_id == id:
			here = "item"
		elif node is Readable and (node as Readable).book_id == id:
			here = "book"
		if here == "" or parts.size() >= 6:
			continue
		var p := (node as Node3D).global_position
		parts.append("%s at (%.1f, %.1f, %.1f) %.0f m off" % [here, p.x, p.y, p.z, _flat(p, at) if at != Vector3.INF else -1.0])
	var items := QuestItems.ensure()
	var placed := "no QuestItems"
	if items != null:
		var node: Variant = (items.get("_placed") as Dictionary).get(key)
		placed = "taken" if items.is_taken(key) else ("standing" if node != null and is_instance_valid(node) else "not standing")
	var cell_says := ""
	if at != Vector3.INF and world != null and world.streamer != null:
		var c := WorldProbe.cell_of(at)
		var cell_node := world.streamer.get_node_or_null("Cell_%d_%d" % [c.x, c.y])
		cell_says = "; its cell %s is %s" % [str(c), "not in the tree" if cell_node == null else
				"ring %d%s" % [int(cell_node.get_meta("ring", 99)), " (going)" if cell_node.is_queued_for_deletion() else ""]]
	return "%d in the tree: %s; the row %s is %s%s; the player at (%.0f, %.0f)" % [parts.size(), "; ".join(parts), key, placed,
			cell_says, player.global_position.x, player.global_position.z]


## Takes the nearest lying pickup of the item within reach: FIND_M of `at` (or of the player, when
## `at` is INF) in the open, anywhere in the interior the player is in. What the built world does
## to where it lies is said.
func _pick_up_near(item: String, at: Vector3) -> Dictionary:
	var best: Node3D = null
	var best_d := INF
	var from := player.global_position if at == Vector3.INF else at
	var reach := 600.0 if Interiors.in_interior() else FIND_M
	for node in get_tree().get_nodes_in_group("interactable"):
		if not (node is WorldItem) or (node as Node).is_queued_for_deletion():
			continue
		var w := node as WorldItem
		if w.item_id != item:
			continue
		var d := _flat(w.global_position, from)
		if d > reach:
			continue
		if d < best_d:
			best_d = d
			best = w
	if best == null:
		return {"ok": false, "why": "no %s lies here" % Ids.name_of(item)}
	_check_find(item, best)
	player.global_position = best.global_position + Vector3(NEAR_M * 0.5, 0.2, 0.0)
	var ok: bool = (best as WorldItem).interact(player)
	await get_tree().process_frame
	return {"ok": ok, "why": "" if ok else "%s would not come up" % Ids.name_of(item)}


func _check_find(item: String, node: Node3D) -> void:
	if Interiors.in_interior():
		return
	var p := node.global_position
	var ground := terrain.get_height(p.x, p.z)
	var where := "(%.1f, %.1f)" % [p.x, p.z]
	if _wet(p.x, p.z):
		_world("%s lies in water at %s" % [Ids.name_of(item), where])
	elif p.y < ground - 0.5:
		_world("%s lies %.1f m under the ground at %s" % [Ids.name_of(item), ground - p.y, where])
	elif _shut_in(p) and _stand_in_reach(p) == Vector3.INF:
		_world("%s lies inside something solid at %s, with nowhere to stand within %.1f m (%s)" % [Ids.name_of(item), where,
				TAKE_REACH_M, _what_shuts(p)])


## A thing tucked in somewhere (the chit under the keel, the day-book under the cart's seat) is
## taken the way the player takes anything: the interact ray reaches 2.6 m and sees only the
## interactable layer, through whatever else is there. So what matters is open ground to stand on
## within that reach: the nearest such point, or INF when there is none.
func _stand_in_reach(p: Vector3) -> Vector3:
	for r in [0.8, 1.3, 1.8, TAKE_REACH_M]:
		for k in 12:
			var a := float(k) * TAU / 12.0
			var at := Vector3(p.x + cos(a) * r, 0.0, p.z + sin(a) * r)
			at.y = terrain.get_height(at.x, at.z)
			if absf(at.y - p.y) > 1.6 or _wet(at.x, at.z):
				continue
			if not _shut_in(at):
				return at
	return Vector3.INF


## Picks up what a fall left lying round the player.
func _gather_drops(item: String) -> void:
	for k in 10:
		await get_tree().process_frame
	await _pick_up_near(item, player.global_position)


func _interiors_holding(item: String) -> Array[String]:
	var out: Array[String] = []
	for def in ContentDB.all("interior"):
		var path := str((def as Dictionary).get("meta", ""))
		if path == "" or not FileAccess.file_exists(path):
			continue
		if FileAccess.get_file_as_string(path).contains("\"%s\"" % item):
			out.append(str(def["id"]))
	return out


func _put_down_boss(boss: String) -> Dictionary:
	var def := ContentDB.get_or_empty(boss)
	var arena := str(def.get("arena", ""))
	if arena == "":
		return {"ok": false, "why": "%s has no arena" % Ids.name_of(boss)}
	if Ids.type_of(arena) == "interior":
		await _enter(arena)
	else:
		await _go(_pad(arena) + Vector3(4.0, 0.0, 0.0))
		# a boss in a deep place under the place stands inside it
		for idef in ContentDB.all("interior"):
			if str((idef as Dictionary).get("place", "")) == arena and _nearest_foe(boss, "", Vector3.INF, INF) == null:
				await _enter(str(idef["id"]))
				break
	var e := _nearest_foe(boss, KillPlaces.interior_of(player) if Interiors.in_interior() else "", Vector3.INF, INF)
	if e == null:
		for node in get_tree().get_nodes_in_group("enemy"):
			if node is Enemy and (node as Enemy).content_id() == boss and not (node as Enemy).dead:
				e = node as Enemy
	if e == null:
		return {"ok": false, "why": "%s did not stand at %s" % [Ids.name_of(boss), Ids.name_of(arena)]}
	var fell := await _fell(e)
	return {"ok": fell, "why": "" if fell else "%s would not fall" % Ids.name_of(boss)}


func _buy(item: String, need: int, table: String) -> Dictionary:
	for npc_def in ContentDB.all("npc"):
		var m: Variant = (npc_def as Dictionary).get("merchant", {})
		if typeof(m) != TYPE_DICTIONARY or str((m as Dictionary).get("stock", "")) != table:
			continue
		var npc := str(npc_def["id"])
		var met := await _meet(npc)
		if not bool(met["ok"]):
			continue
		var merchant: Merchant = EconomyService.merchant_for(npc)
		if merchant == null:
			return {"ok": false, "why": "%s keeps no shop in the world" % Ids.name_of(npc)}
		var r: Dictionary = merchant.buy(player, item, need)
		if bag.count(item) >= need:
			return {"ok": true, "why": ""}
		return {"ok": false, "why": "%s would not sell it: %s" % [Ids.name_of(npc), JSON.stringify(r)]}
	return {"ok": false, "why": "nobody keeps %s" % table}


# --- books -------------------------------------------------------------------------------------------------------------

func _read(q: String, stage: Dictionary, i: int, o: Dictionary) -> Dictionary:
	var book := str(o.get("target", ""))
	var tried: Array[String] = []
	# read where it lies: an objective that says so, or a place's own
	for row in QuestItems.placements():
		if str(row.get("kind", "")) != "book" or str(row.get("book", "")) != book:
			continue
		var where := str(row["where"])
		if Ids.type_of(where) == "interior":
			await _enter(where)
		else:
			await _go(_pad(where) + Vector3(3.0, 0.0, 0.0))
			QuestItems.ensure().raise_in_loaded_cells()
			await get_tree().process_frame
		if _read_lying(book):
			return {"ok": true, "why": ""}
		tried.append("nothing to read lay at %s [%s]" % [Ids.name_of(where), _lying_seen(book, str(row["key"]),
				_pad(where) if Ids.type_of(where) != "interior" else Vector3.INF)])
	# a shelf in a house
	for interior in _interiors_holding(book):
		if await _enter(interior) and _read_lying(book):
			return {"ok": true, "why": ""}
	# the item that reads it, out of the bag
	var reader := ItemSources.reader_of(book)
	if reader != "":
		var got := await _obtain(reader, 1, q)
		if bag.count(reader) > 0:
			bag.read(reader)
			await get_tree().process_frame
			return {"ok": true, "why": ""}
		tried.append(str(got["why"]))
	return {"ok": false, "why": "%s: %s" % [Ids.name_of(book), "; ".join(tried) if not tried.is_empty() else "nothing reads it"]}


func _read_lying(book: String) -> bool:
	for node in get_tree().get_nodes_in_group("readable"):
		var r := node as Readable
		if r == null or r.book_id != book or r.is_queued_for_deletion():
			continue
		if not Interiors.in_interior():
			_check_find(book, r)
		player.global_position = r.global_position + Vector3(NEAR_M * 0.5, 0.2, 0.0)
		var res: Dictionary = r.interact(player)
		return bool(res.get("ok", false))
	return false


# --- deliver, escort, use, rest ---------------------------------------------------------------------------------------------

func _deliver(q: String, stage: Dictionary, i: int, o: Dictionary) -> Dictionary:
	var item := str(o.get("item", ""))
	var need := maxi(1, int(o.get("count", 1)))
	if item != "" and bag.count(item) < need:
		var got := await _obtain(item, need, q)
		if not bool(got["ok"]):
			return got
	var npc := str(o.get("target", ""))
	var met := await _meet(npc)
	if not bool(met["ok"]):
		return met
	var goal: Dictionary = {"quest": q, "flags": _flags_of(q)}
	if QuestRoutes.dialogue_closes(q, stage, i):
		goal = {"effect": {"complete_objective": [q, null]}}
	var r := DialogueSteer.drive(npc, goal)
	return {"ok": bool(r["ok"]), "why": str(r["why"])}


func _escort(q: String, i: int, o: Dictionary) -> Dictionary:
	var npc := str(o.get("target", ""))
	var place := str(o.get("place", ""))
	var met := await _meet(npc)
	if not bool(met["ok"]):
		return met
	var escorts := Escorts.ensure()
	escorts.tick()
	await get_tree().process_frame
	if not registry.is_escorted(npc):
		return {"ok": false, "why": "%s did not set out (the stage's talk and requires: %s)" % [Ids.name_of(npc), JSON.stringify(o.get("requires", []))]}
	# where the escort is judged to have arrived: the place's own position (Escorts)
	var dest := WorldProbe.place_position(place)
	var steps := 0
	var at_stage: int = log_node.stage_of(q)
	while _still_open(q, at_stage, i) and steps < 400:
		steps += 1
		var here := player.global_position
		var dir := Vector3(dest.x - here.x, 0.0, dest.z - here.z)
		if dir.length() < 1.0:
			break
		var step := minf(STEP_M, dir.length())
		var to := here + dir.normalized() * step
		await _step_to(to)
		var body := registry.actor(npc) as Node3D
		if body != null:
			var behind := player.global_position - dir.normalized() * 2.0
			body.global_position = Vector3(behind.x, terrain.get_height(behind.x, behind.z) + 0.1, behind.z)
		escorts.tick()
		await get_tree().process_frame
	if not _still_open(q, at_stage, i):
		return {"ok": true, "why": ""}
	return {"ok": false, "why": "walked %d steps with %s and never arrived at %s (%.0f m off)" % [steps, Ids.name_of(npc),
			Ids.name_of(place), _flat(player.global_position, dest)]}


func _use(q: String, o: Dictionary) -> Dictionary:
	var item := str(o.get("target", ""))
	var got := await _obtain(item, 1, q)
	if not bool(got["ok"]):
		return got
	var ok := bag.use(item)
	await get_tree().process_frame
	return {"ok": ok, "why": "" if ok else "%s could not be used" % Ids.name_of(item)}


## A lesson's act (QuestLog `act`): the walker goes where the stage marks it and says the act is done,
## to something of the kind it asks for, as the body's own blow or guard would. The descent plays
## the wake, as the fortieth step does.
func _act(o: Dictionary) -> Dictionary:
	var marker: Variant = o.get("marker", null)
	if marker is Dictionary and ContentDB.has(str((marker as Dictionary).get("place_id", ""))):
		await _go(_pad(str((marker as Dictionary)["place_id"])) + Vector3(3.0, 0.0, 0.0))
	var act := str(o.get("target", ""))
	var against := str(o.get("against", ""))
	var on := _ActTarget.new()
	# a prop names itself `prop:<kind>` (Pell.content_id: the ranger's butts, the rogue's sack)
	on.id = against if Ids.is_valid(against) or against.begins_with("prop:") else ""
	add_child(on)
	# as far off as the objective asks (the far butt at fifty paces)
	on.global_position = player.global_position + Vector3(float(o.get("min_range", 0.0)) + 1.0, 0.0, 0.0)
	for n in maxi(1, int(o.get("count", 1))):
		EventBus.act_done.emit(act, player, on, str(o.get("detail", "")))
	on.queue_free()
	if act == "descend":
		var services := get_tree().get_first_node_in_group("game_services")
		if services != null and services.has_method("begin_wake"):
			await services.call("begin_wake")
	await get_tree().process_frame
	return {"ok": true, "why": ""}


class _ActTarget extends Node3D:
	var id := ""

	func content_id() -> String:
		return id


func _rest(o: Dictionary) -> Dictionary:
	var target := str(o.get("target", ""))
	if ContentDB.has(target) and ContentDB.get_or_empty(target).has("position"):
		await _go(_pad(target) + Vector3(3.0, 0.0, 0.0))
	else:
		for def in ContentDB.all("interior"):
			var path := str((def as Dictionary).get("meta", ""))
			if path != "" and FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).contains("\"%s\"" % target):
				await _enter(str(def["id"]))
				break
	var best: Node3D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("hearthstone"):
		var hs := node as Node3D
		if hs == null or str(hs.get("hearthstone_id")) != target:
			continue
		var d := _flat(hs.global_position, player.global_position)
		if d < best_d:
			best_d = d
			best = hs
	if best == null:
		return {"ok": false, "why": "no Hearthstone %s stood there" % Ids.name_of(target)}
	player.global_position = best.global_position + Vector3(1.2, 0.2, 0.0)
	best.call("interact", player)
	await get_tree().process_frame
	return {"ok": true, "why": ""}


# --- a stage that waits for a word -----------------------------------------------------------------------------------------

## A stage with nothing left to do that has not moved on waits for a line that moves it: a stage
## change, an ending or an objective closed in somebody's conversation.
func _move_on(q: String, stage: Dictionary) -> Dictionary:
	var wants: Array[Dictionary] = [{"quest_stage": [q, null]}, {"complete_quest": q}, {"complete_objective": [q, null]}, {"fail_quest": q}]
	var tried: Array[String] = []
	for want in wants:
		for l in DialogueSteer.speakers_of(want):
			if not Conditions.all_of(l["conditions"], Social.ctx):
				continue
			var met := await _meet(str(l["npc"]))
			if not bool(met["ok"]):
				tried.append(str(met["why"]))
				continue
			var before := _progress_sign(q)
			var r := DialogueSteer.drive(str(l["npc"]), {"effect": want})
			if _progress_sign(q) != before:
				return {"ok": true, "why": ""}
			tried.append("%s: %s" % [Ids.name_of(str(l["npc"])), str(r["why"])])
	return {"ok": false, "why": "nothing moves it on%s" % ("" if tried.is_empty() else ": " + "; ".join(tried))}


# --- decisions -----------------------------------------------------------------------------------------------------------------

## A decision, walked every way: the first option goes on in this walk; each other one is chosen
## from a save made here and walked to the quest's end, once per decision.
func _choice(q: String, stage: Dictionary, i: int) -> Dictionary:
	var options: Array[String] = []
	for opt in log_node.open_options(q):
		options.append(str(opt["id"]))
	var o: Dictionary = (stage.get("objectives", []) as Array)[i]
	var written: Array[String] = []
	for entry in o.get("options", []):
		written.append(str((entry as Dictionary).get("id", "")) if typeof(entry) == TYPE_DICTIONARY else str(entry))
	if options.is_empty():
		return {"ok": false, "why": "no option of '%s' is open" % str(o.get("target", ""))}
	var key := "%s|%s|%d" % [q, str(stage.get("id", "")), i]
	if branches and written.size() > 1 and not explored.has(key):
		explored[key] = true
		var snap := _snapshot()
		var outer := _cur
		for opt in written:
			if opt == options[0]:
				continue
			await _restore(snap)
			_cur = _new_walk(q, _branch_label(outer, stage, opt))
			var t := Time.get_ticks_msec()
			# an option this walk has not earned (a Sayer's skill, the renown the third ending asks
			# for, a flag another quest's other branch sets) has its way made up, and says so
			if not _open_now(q, opt):
				var made := _make_hold(QUEST_LOG.option_def(o, opt).get("conditions", []))
				_note("its way made up: %s" % ", ".join(made))
			var at_before: int = log_node.stage_of(q)
			var r := await _decide(q, stage, i, opt)
			if not bool(r["ok"]):
				_problem("choosing '%s': %s" % [opt, str(r["why"])])
			else:
				_check_option(q, o, opt)
				_after_step(q, at_before, stage)
				await _walk(q)
			_close_walk(q, t)
		await _restore(snap)
		_cur = outer
	var main := await _decide(q, stage, i, options[0])
	if bool(main["ok"]):
		_check_option(q, o, options[0])
	return main


func _open_now(q: String, option: String) -> bool:
	for opt in log_node.open_options(q):
		if str(opt["id"]) == option:
			return true
	return false


## Makes a gate's conditions hold the ways a player comes by them: standing and renown given,
## a skill used until it is good enough, a flag another branch would have set. Says what it made.
func _make_hold(conds: Variant) -> Array[String]:
	var made: Array[String] = []
	if typeof(conds) != TYPE_ARRAY:
		return made
	for c_v in conds as Array:
		if typeof(c_v) != TYPE_DICTIONARY or Conditions.all_of([c_v], Social.ctx):
			continue
		var c: Dictionary = c_v
		if c.has("flag"):
			GameState.set_flag(str(c["flag"]))
			made.append("flag %s" % str(c["flag"]))
		elif c.has("flag_equals"):
			GameState.set_flag(str(c["flag_equals"][0]), c["flag_equals"][1])
			made.append("flag %s = %s" % [str(c["flag_equals"][0]), str(c["flag_equals"][1])])
		elif c.has("renown_min"):
			var short := int(c["renown_min"]) - int(Social.standing.renown())
			Social.standing.add_renown(short, "quest walker")
			made.append("renown +%d to %d" % [short, int(c["renown_min"])])
		elif c.has("rep_min"):
			var faction := str(c["rep_min"][0])
			var short := int(c["rep_min"][1]) - int(Social.factions.reputation(faction))
			Social.factions.add_reputation(faction, short, "quest walker")
			made.append("%s +%d" % [Ids.name_of(faction), short])
		elif c.has("skill_min"):
			var skill := str(c["skill_min"][0])
			var id := skill if skill.contains(":") else "core:skill/" + skill
			var uses := 0
			while Social.ctx.skill_level(skill) < int(c["skill_min"][1]) and uses < 4000:
				EventBus.skill_used.emit(id, 8.0)
				uses += 1
			made.append("%s used %d times to %d" % [skill, uses, Social.ctx.skill_level(skill)])
		else:
			made.append("could not make %s hold" % JSON.stringify(c))
	return made


func _branch_label(outer: Dictionary, stage: Dictionary, option: String) -> String:
	var here := "%s:%s" % [str(stage.get("id", "")), option]
	var before := str(outer.get("branch", ""))
	return here if before == "" else before + " > " + here


## Makes the decision where the game puts it: an authored line, a cold light where nobody is left
## to ask, or the host's own conversation (the runner offers decisions nobody wrote a button for).
func _decide(q: String, stage: Dictionary, i: int, option: String) -> Dictionary:
	var want := {"quest_choice": [q, option]}
	var o: Dictionary = (stage.get("objectives", []) as Array)[i]
	var before := _progress_sign(q)
	# a decision with nobody left to put it
	for row in QuestItems.placements():
		if str(row["kind"]) != "choice" or str(row["quest_id"]) != q or str(row["stage_id"]) != str(stage.get("id", "")):
			continue
		var where := str(row["where"])
		if Ids.type_of(where) == "interior":
			await _enter(where)
		else:
			await _go(_pad(where) + Vector3(3.0, 0.0, 0.0))
			QuestItems.ensure().raise_in_loaded_cells()
			await get_tree().process_frame
		for node in get_tree().get_nodes_in_group("choice_point"):
			var point := node as ChoicePoint
			if point == null or point.quest_id != q or not point.is_open():
				continue
			player.global_position = point.global_position + Vector3(1.2, 0.2, 0.0)
			point.interact(player)
			var r := DialogueSteer.steer(Social.dialogue, {"effect": want})
			if _progress_sign(q) != before:
				return {"ok": true, "why": ""}
			return {"ok": false, "why": "the light at %s: %s" % [Ids.name_of(where), str(r["why"])]}
		return {"ok": false, "why": "no light to decide at stood at %s" % Ids.name_of(where)}
	# an authored line, then the host's hub
	var who: Array[String] = []
	for l in DialogueSteer.speakers_of(want):
		if not who.has(str(l["npc"])):
			who.append(str(l["npc"]))
	var host := QuestRoutes.host_of(log_node.definition(q), stage, o)
	if host != "" and Ids.type_of(host) == "npc" and not who.has(host):
		who.append(host)
	var tried: Array[String] = []
	for npc in who:
		var met := await _meet(npc)
		if not bool(met["ok"]):
			tried.append(str(met["why"]))
			continue
		var r := DialogueSteer.drive(npc, {"effect": want})
		if _progress_sign(q) != before or log_node.choice_of(q) == option:
			return {"ok": true, "why": ""}
		tried.append("%s: %s" % [Ids.name_of(npc), str(r["why"])])
	return {"ok": false, "why": "nobody put it: %s" % "; ".join(tried)}


func _check_option(q: String, o: Dictionary, option: String) -> void:
	var def := QUEST_LOG.option_def(o, option)
	_check_effects(q, def.get("effects", []), "option '%s'" % option)
	var per: Variant = o.get("effects_by_option", {})
	if typeof(per) == TYPE_DICTIONARY and (per as Dictionary).has(option):
		_check_effects(q, per[option], "option '%s'" % option)


# --- saves --------------------------------------------------------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	if Social.dialogue.is_running():
		Social.dialogue.stop()
	if Interiors.in_interior():
		Interiors.exit()
	return {"save": SaveSystem.serialize(), "hour": WorldClock.time_hours, "day": WorldClock.day,
			"pos": player.global_position}


## Loads the save the way a slot loads, and stands the world back up as a reload would: the
## stage's fights and the quest's finds are stood again.
func _restore(s: Dictionary) -> void:
	if Social.dialogue.is_running():
		Social.dialogue.stop()
	if Interiors.in_interior():
		Interiors.exit()
		await get_tree().process_frame
	# A load from a slot changes scene, and the houses built so far go with the old one; here the
	# scene stays, so they are let go by hand, or a house would be walked back into as a branch
	# left it (the book on Tallissa's shelf already taken).
	Interiors.unload_all()
	await get_tree().process_frame
	SaveSystem.deserialize((s["save"] as Dictionary).duplicate(true))
	WorldClock.set_time(float(s["hour"]), int(s["day"]))
	var foes := QuestFoes.ensure()
	if foes != null:
		var groups: Dictionary = foes.get("_groups")
		for k in groups.keys():
			var g: Variant = groups[k]
			if g != null and is_instance_valid(g):
				(g as Node).queue_free()
		groups.clear()
	registry.simulate_all()
	await _go(s["pos"])
	var items := QuestItems.ensure()
	if items != null:
		items.raise_in_loaded_cells()
	people.refresh()


# --- checks -------------------------------------------------------------------------------------------------------------------------------

## What an effects list promises, checked after it ran: flags set and cleared, quests started and
## ended, factions joined and left, things given, sayings taught.
func _check_effects(q: String, effects: Variant, where: String) -> void:
	if typeof(effects) != TYPE_ARRAY:
		return
	for e_v in effects as Array:
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_v
		for key in e.keys():
			var arg: Variant = e[key]
			var ok := true
			match str(key):
				"set_flag":
					var f := str(arg[0]) if typeof(arg) == TYPE_ARRAY else str(arg)
					ok = GameState.has_flag(f)
					if not _cur.is_empty():
						(_cur["flags"] as Dictionary)[f] = true
				"clear_flag":
					ok = not GameState.has_flag(str(arg))
				"start_quest":
					ok = log_node.is_known(str(arg))
				"complete_quest":
					ok = log_node.is_completed(str(arg))
				"fail_quest":
					ok = log_node.is_failed(str(arg))
				"join_faction":
					ok = Social.factions.is_member(str(arg))
				"leave_faction":
					ok = not Social.factions.is_member(str(arg))
				"give_item":
					var item := str(arg[0]) if typeof(arg) == TYPE_ARRAY else str(arg)
					ok = bag.count(item) > 0 or _handed_on(q, item)
				"arm":
					# given like give_item; whether it is also in the hand depends on what the hand held
					var weapon := str(arg[0]) if typeof(arg) == TYPE_ARRAY else str(arg)
					ok = bag.count(weapon) > 0 or _handed_on(q, weapon)
				"teach_spell":
					var prog := get_tree().get_first_node_in_group("progression")
					ok = prog == null or not prog.has_method("knows_spell") or bool(prog.call("knows_spell", str(arg)))
				_:
					pass
			if not ok:
				_problem("%s: %s did not take" % [where, JSON.stringify(e)])


## Whether an item given has already gone on, to a delivery of this quest.
func _handed_on(q: String, item: String) -> bool:
	return JSON.stringify(ContentDB.get_def(q)).contains("\"item\":\"%s\"" % item)


## The end of a quest: its rewards, and the people who remember it greeting you with it.
func _after_the_end(q: String) -> void:
	var def := ContentDB.get_def(q)
	if log_node.is_completed(q):
		var rewards: Dictionary = def.get("rewards", {})
		_check_effects(q, rewards.get("effects", []), "the reward")
		for entry in rewards.get("items", []):
			var item := str(entry[0]) if typeof(entry) == TYPE_ARRAY else str(entry)
			if bag.count(item) <= 0:
				_problem("the reward: %s is not in the bag" % Ids.name_of(item))
	_check_greetings(q)


## Greetings that remember this quest: a greeting whose conditions ask that it was done, how it
## ended, or a flag it sets. If any line remembers it at all, one must hold at the end of every way
## it goes. Each person with one that holds greets you with it, or with a line as specific (a tie
## is broken at random, and theirs is in the draw).
func _check_greetings(q: String) -> void:
	var own_flags := _flags_set_in(ContentDB.get_def(q))
	var rows_by_npc: Dictionary = {}
	var remembering := 0
	for row_v in Greetings.dialogue_rows():
		var row: Dictionary = row_v
		if not _remembers(row.get("conditions", []), q, own_flags):
			continue
		remembering += 1
		if not Conditions.all_of(row.get("conditions", []), Social.ctx):
			continue
		var npc := str(row.get("npc", ""))
		if not rows_by_npc.has(npc):
			rows_by_npc[npc] = []
		(rows_by_npc[npc] as Array).append(row)
	if remembering > 0 and rows_by_npc.is_empty():
		_problem("nobody greets you remembering it: the %d lines that remember it are for other ways it went" % remembering)
	var remembered := 0
	for npc in rows_by_npc:
		var ctx: SocialContext = Social.ctx
		var was_id := ctx.npc_id
		var was_def := ctx.npc
		ctx.npc_id = str(npc)
		ctx.npc = ContentDB.get_or_empty(str(npc))
		var best := -1.0
		var best_rows: Array = []
		for row_v in Greetings.table_rows():
			var row: Dictionary = row_v
			var s := Greetings._score(row, str(npc), ctx)
			if s < 0.0:
				continue
			if s > best + 0.0001:
				best = s
				best_rows = [row]
			elif absf(s - best) <= 0.0001:
				best_rows.append(row)
		ctx.npc_id = was_id
		ctx.npc = was_def
		var mine: Array = rows_by_npc[npc]
		var met := false
		for row in mine:
			if best_rows.has(row):
				met = true
		if met:
			remembered += 1
		elif _on_what_came_next(best_rows, q):
			# the quest this one started at its end is what they are talking about now (Alder Wyke
			# on the Grey Hart the moment the ranger's start hands on to it); the memory comes after
			_note("%s greets you with the quest it started, not yet with what they remember of it" % Ids.name_of(str(npc)))
		else:
			var said: Array = []
			for row in best_rows:
				said.append(_short_text(str(((row as Dictionary).get("lines", [""]) as Array)[0])))
			_problem("%s does not greet you with what they remember of it: \"%s\" wins over \"%s\"" % [Ids.name_of(str(npc)),
					" / ".join(PackedStringArray(said)), _short_text(str(((mine[0] as Dictionary).get("lines", [""]) as Array)[0]))])
	if remembered > 0:
		_note("remembered by %d" % remembered)


## Whether one of these greetings is about a quest `q` started and that is under way now.
func _on_what_came_next(rows: Array, q: String) -> bool:
	var def := ContentDB.get_def(q)
	for row_v in rows:
		var conds := JSON.stringify((row_v as Dictionary).get("conditions", []))
		for other in log_node.active_quests():
			var id := str((other as Dictionary).get("id", ""))
			if id != "" and id != q and conds.contains("\"%s\"" % id) and _starts(def, id):
				return true
	return false


## Every flag a definition's effects set, anywhere in it.
func _flags_set_in(def: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var rx := RegEx.new()
	rx.compile("\"set_flag\":\\s*\\[?\"([^\"]+)\"")
	for m in rx.search_all(JSON.stringify(def)):
		out[m.get_string(1)] = true
	return out


## Whether conditions ask, other than under a `not`, that the quest was done, how it ended, or for
## one of its flags.
func _remembers(conds: Variant, q: String, own_flags: Dictionary) -> bool:
	if typeof(conds) == TYPE_DICTIONARY:
		conds = [conds]
	if typeof(conds) != TYPE_ARRAY:
		return false
	for c_v in conds as Array:
		if typeof(c_v) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_v
		if c.has("quest_done") and str(c["quest_done"]) == q:
			return true
		if c.has("quest_outcome") and typeof(c["quest_outcome"]) == TYPE_ARRAY and str((c["quest_outcome"] as Array)[0]) == q:
			return true
		if c.has("flag") and own_flags.has(str(c["flag"])):
			return true
		if c.has("flag_equals") and typeof(c["flag_equals"]) == TYPE_ARRAY and own_flags.has(str((c["flag_equals"] as Array)[0])):
			return true
		for key in ["all", "any"]:
			if c.has(key) and _remembers(c[key], q, own_flags):
				return true
	return false


func _short_text(t: String) -> String:
	return t if t.length() <= 48 else t.substr(0, 45) + "..."


func _short(q: String) -> String:
	return q.get_slice("/", 1) if q.contains("/") else q


# --- the report ---------------------------------------------------------------------------------------------------------------------------

func _report() -> void:
	var walks := results.size()
	var passed := 0
	var quests: Dictionary = {}
	var quests_ok: Dictionary = {}
	for r in results:
		quests[str(r["quest"])] = true
		if bool(r["ok"]):
			passed += 1
	for q in quests:
		var all_ok := true
		for r in results:
			if str(r["quest"]) == q and not bool(r["ok"]):
				all_ok = false
		if all_ok:
			quests_ok[q] = true
	var errors: int = Log.error_count - _errors_at_start
	var lines: Array[String] = []
	lines.append("QW RESULT: %d of %d quests end every way they can; %d of %d walks (branches %s); %d world notes; %d logged errors; %.0f min" % [
			quests_ok.size(), quests.size(), passed, walks, "on" if branches else "off", world_notes.size(), errors,
			(Time.get_ticks_msec() - _t0) / 60000.0])
	for r in results:
		if bool(r["ok"]):
			continue
		lines.append("QW FAILED %s%s: %s" % [_short(str(r["quest"])), "" if str(r["branch"]) == "" else " [%s]" % r["branch"],
				"; ".join(PackedStringArray(r["problems"]))])
	for w in world_notes:
		lines.append("QW WORLD %s" % w)
	for l in lines:
		_say(l)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			for r in results:
				f.store_line("%s %s%s %s" % ["PASS" if bool(r["ok"]) else "FAIL", _short(str(r["quest"])),
						"" if str(r["branch"]) == "" else " [%s]" % r["branch"],
						"; ".join(PackedStringArray(r["problems"]))])
			for l in lines:
				f.store_line(l)
			f.close()
	var ok := quests_ok.size() == quests.size() and not quests.is_empty() and world_notes.is_empty()
	get_tree().quit(0 if ok else 1)
