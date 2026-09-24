class_name NpcRegistry
extends Node
## Every NPC in the world, simulated abstractly when off screen (DESIGN §5.12).
##
## For each npc def the registry keeps {place, activity, spot, alive, disposition,
## last_seen_player_deed, hostile, in_jail_until_day}. Those follow the schedule on every
## hour change whether or not the NPC is loaded. When a cell is loaded (EventBus.cell_loaded)
## every NPC whose current place falls in that cell is spawned as an actor; when the cell
## unloads, the actor's state is written back and the node freed.
## Save section "npcs". Group "npc_registry".

static var instance: NpcRegistry

signal state_changed(npc_id: String)
signal npc_spawned(npc_id: String, node: Node)
signal npc_despawned(npc_id: String)

const SECTION := "npcs"
const NPC_SCENE := "res://actors/npc/npc.tscn"
const GUARD_SCRIPT := "res://actors/npc/guard.gd"
## Markers a dressing puts where somebody works, named for the `spot` in their schedule.
const SPOT_GROUP := "npc_spot"

var states: Dictionary = {}       # npc_id -> Dictionary
var spawned: Dictionary = {}      # npc_id -> Node
var loaded_cells: Dictionary = {} # Vector2i -> true
var spawning_enabled := true
## Set by tests and the smoke run: spawn no actors, only simulate.
var abstract_only := false


static func ensure() -> NpcRegistry:
	if instance != null and is_instance_valid(instance):
		return instance
	var found := Service.ensure(load("res://systems/npc_life/npc_registry.gd"), "NpcRegistry") as NpcRegistry
	# A copy of this service inside a world set `instance` as it entered the tree and cleared it as it
	# left; a copy under the root that entered earlier is then found here with `instance` still empty,
	# and everything that reads `instance` directly finds nothing. Point it at what was found.
	if found != null and (instance == null or not is_instance_valid(instance)):
		instance = found
	return found


func _enter_tree() -> void:
	instance = self
	add_to_group("npc_registry")


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if SaveSystem.participants.get(SECTION) == self:
		SaveSystem.unregister(SECTION)


func _ready() -> void:
	SaveSystem.register(SECTION, self)
	var pending := SaveSystem.take_pending(SECTION)
	rebuild()
	if not pending.is_empty():
		from_save(pending)
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.new_day.connect(_on_new_day)
	EventBus.cell_loaded.connect(_on_cell_loaded)
	EventBus.cell_unloaded.connect(_on_cell_unloaded)
	EventBus.weather_changed.connect(_on_weather_changed)
	# a def's `holds` follow the story (Schedules.held_entry), so the story moving on is a reason
	# to look again, as the clock is
	EventBus.quest_started.connect(_on_story_moved)
	EventBus.quest_stage_changed.connect(_on_story_moved)
	EventBus.quest_completed.connect(_on_story_moved)
	# somebody whose day moved on while the player talked to them is told where to go afterwards
	EventBus.dialogue_ended.connect(_on_dialogue_ended)


# --- state ---------------------------------------------------------------------------------

## Builds a state for every npc def that has none yet, and advances all of them to now.
func rebuild() -> void:
	for def in ContentDB.all("npc"):
		var id: String = def["id"]
		if not states.has(id):
			states[id] = _fresh_state(def)
	simulate_all()


func _fresh_state(def: Dictionary) -> Dictionary:
	return {
		"place": str(def.get("home_place", "")),
		"activity": "idle",
		"spot": "",
		"indoors": false,
		"alive": true,
		"disposition": int(def.get("disposition", 0)),
		"last_seen_player_deed": "",
		"hostile": false,
		"in_jail_until_day": 0,
		"travelling": false,
		# on the road between two places of their own day: where from, and when they set out and
		# are due, in game hours since the first day began (day * 24 + hour)
		"travel_from": "",
		"travel_depart": 0.0,
		"travel_arrive": 0.0,
		# walking with the player (Escorts): the quest it is for, where they last stood, and
		# whether they have been left behind; and, once there, the place they were brought to
		"escort": "",
		"escort_pos": [],
		"escort_left": false,
		"waiting_at": "",
	}


func state(npc_id: String) -> Dictionary:
	if not states.has(npc_id):
		if ContentDB.has(npc_id):
			states[npc_id] = _fresh_state(ContentDB.get_or_empty(npc_id))
		else:
			return {}
	return states[npc_id]


func known_ids() -> Array[String]:
	var out: Array[String] = []
	for id in states:
		out.append(id)
	out.sort()
	return out


func is_alive(npc_id: String) -> bool:
	return bool(state(npc_id).get("alive", false))


## Somebody the story has taken out of the world: their def's `gone_when` conditions hold. Aud
## Fennick walks into the grey at the end of the vigil, and the roster put her back in her tent at
## Pilgrim's Ash the next hour, mending other people's grey. Nobody killed her and she is not dead;
## she is not anywhere any more: stood up nowhere, off the clock, at no place.
func is_gone(npc_id: String) -> bool:
	var conds: Variant = ContentDB.get_or_empty(npc_id).get("gone_when", [])
	if typeof(conds) != TYPE_ARRAY or (conds as Array).is_empty() or Social.ctx == null:
		return false
	return Conditions.all_of(conds, Social.ctx)


func place_of(npc_id: String) -> String:
	if is_gone(npc_id):
		return ""
	return str(state(npc_id).get("place", ""))


func activity_of(npc_id: String) -> String:
	return str(state(npc_id).get("activity", "idle"))


## Is this person under a roof right now? Their schedule decides it (Schedules.is_indoors),
## and it is what keeps a sleeping villager out of the village square at three in the morning.
## Somebody walking the road with you is not in bed, whatever their timetable last said.
func is_indoors(npc_id: String) -> bool:
	if is_escorted(npc_id):
		return false
	return bool(state(npc_id).get("indoors", false))


# --- escorts ---------------------------------------------------------------------------------------

## Somebody walking with the player keeps no timetable: `simulate` leaves them alone, they stand
## up where they were last seen rather than at their home place, and they are counted as being in
## whichever cell they are actually in. `Escorts` decides when all that starts and stops.
func is_escorted(npc_id: String) -> bool:
	return str(state(npc_id).get("escort", "")) != ""


func escorted_ids() -> Array[String]:
	var out: Array[String] = []
	for id in states:
		if str((states[id] as Dictionary).get("escort", "")) != "":
			out.append(str(id))
	out.sort()
	return out


func begin_escort(npc_id: String, quest_id: String, at: Vector3) -> void:
	var s := state(npc_id)
	if s.is_empty():
		return
	s["escort"] = quest_id
	s["escort_left"] = false
	s["waiting_at"] = ""
	s["indoors"] = false
	set_escort_position(npc_id, at)
	state_changed.emit(npc_id)


func set_escort_position(npc_id: String, at: Vector3) -> void:
	var s := state(npc_id)
	if not s.is_empty() and at != Vector3.INF:
		s["escort_pos"] = [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]


## Where an escorted person last stood, or `Vector3.INF` for anybody who is not walking with you.
func escort_position(npc_id: String) -> Vector3:
	var p: Variant = state(npc_id).get("escort_pos", [])
	if not is_escorted(npc_id) or typeof(p) != TYPE_ARRAY or (p as Array).size() < 3:
		return Vector3.INF
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func escort_left(npc_id: String) -> bool:
	return bool(state(npc_id).get("escort_left", false))


func set_escort_left(npc_id: String, left: bool) -> void:
	var s := state(npc_id)
	if not s.is_empty():
		s["escort_left"] = left
		state_changed.emit(npc_id)


## Stops an escort. With `stay_at` they have arrived: they stand at that place for as long as the
## player is there to see it, and go back to their own life once the player has gone (see
## `despawn`). Without it they simply go back to their timetable.
func end_escort(npc_id: String, stay_at := "") -> void:
	var s := state(npc_id)
	if s.is_empty():
		return
	s["escort"] = ""
	s["escort_pos"] = []
	s["escort_left"] = false
	if stay_at != "":
		s["place"] = stay_at
		s["waiting_at"] = stay_at
		s["activity"] = "idle"
		s["spot"] = ""
		state_changed.emit(npc_id)
	else:
		s["waiting_at"] = ""
		state_changed.emit(npc_id)
		simulate(npc_id)


func waiting_at(npc_id: String) -> String:
	return str(state(npc_id).get("waiting_at", ""))


func disposition_of(npc_id: String) -> int:
	return int(state(npc_id).get("disposition", 0))


func adjust_disposition(npc_id: String, delta: int) -> int:
	var s := state(npc_id)
	if s.is_empty():
		return 0
	s["disposition"] = clampi(int(s.get("disposition", 0)) + delta, -100, 100)
	state_changed.emit(npc_id)
	return s["disposition"]


## Remembers the worst thing this NPC has seen the player do (crime kind or deed key).
func note_player_deed(npc_id: String, deed: String) -> void:
	var s := state(npc_id)
	if s.is_empty():
		return
	s["last_seen_player_deed"] = deed
	state_changed.emit(npc_id)


func last_seen_player_deed(npc_id: String) -> String:
	return str(state(npc_id).get("last_seen_player_deed", ""))


func set_hostile(npc_id: String, hostile: bool) -> void:
	var s := state(npc_id)
	if s.is_empty():
		return
	s["hostile"] = hostile
	if spawned.has(npc_id) and is_instance_valid(spawned[npc_id]):
		spawned[npc_id].set("hostile", hostile)
	state_changed.emit(npc_id)


func is_hostile(npc_id: String) -> bool:
	return bool(state(npc_id).get("hostile", false))


## Marks an NPC dead. The body is left where it fell — a corpse other streams can loot and
## the player can see — and is freed with its cell; `spawn` refuses the dead, so it never
## comes back. The actor is told first so its own `alive` cannot be written back over this.
func kill(npc_id: String) -> void:
	var s := state(npc_id)
	if s.is_empty() or not s["alive"]:
		return
	s["alive"] = false
	s["hostile"] = false
	var node := actor(npc_id)
	if node != null and node.has_method("die"):
		node.call("die")
	elif node != null and "alive" in node:
		node.set("alive", false)
	GameState.inc("npcs_dead")
	state_changed.emit(npc_id)


## People in a place right now (the living only, unless `include_dead`).
func npcs_at(place_id: String, include_dead := false) -> Array[String]:
	var out: Array[String] = []
	for id in states:
		var s: Dictionary = states[id]
		if str(s.get("place", "")) != place_id:
			continue
		if not include_dead and not bool(s.get("alive", true)):
			continue
		if is_gone(str(id)):
			continue
		out.append(id)
	out.sort()
	return out


# --- abstract simulation ---------------------------------------------------------------------

func weather_now() -> String:
	var atmosphere := Service.in_group("atmosphere")
	if atmosphere != null:
		for m in ["current_weather", "weather_id", "weather"]:
			if atmosphere.has_method(m):
				return str(atmosphere.call(m))
			if m in atmosphere:
				return str(atmosphere.get(m))
	return str(GameState.get_flag("_weather", "clear"))


## Moves every living, free NPC to where its schedule says it should be.
func simulate_all(weather := "") -> void:
	if weather.is_empty():
		weather = weather_now()
	for id in states:
		simulate(id, weather)


func simulate(npc_id: String, weather := "") -> Dictionary:
	var s := state(npc_id)
	if s.is_empty() or not bool(s.get("alive", true)):
		return s
	if is_gone(npc_id):
		if str(s.get("place", "")) != "":
			s["place"] = ""
			s["spot"] = ""
			state_changed.emit(npc_id)
		if is_spawned(npc_id):
			despawn(npc_id)
		return s
	if int(s.get("in_jail_until_day", 0)) > WorldClock.day:
		return s
	# on the road with the player, or standing where the player brought them: not on the clock
	if str(s.get("escort", "")) != "" or str(s.get("waiting_at", "")) != "":
		return s
	if weather.is_empty():
		weather = weather_now()
	var def := ContentDB.get_or_empty(npc_id)
	var entry := Schedules.entry_for_def(def, WorldClock.day, WorldClock.time_hours, weather)
	var moved: bool = str(s.get("place", "")) != str(entry["place"])
	var changed: bool = moved or str(s.get("spot", "")) != str(entry["spot"]) \
			or str(s.get("activity", "")) != str(entry["activity"])
	s["place"] = entry["place"]
	s["activity"] = entry["activity"]
	s["spot"] = entry["spot"]
	s["indoors"] = bool(entry.get("indoors", false))
	var was_travelling := bool(s.get("travelling", false))
	s["travelling"] = entry["travelling"]
	if bool(entry["travelling"]):
		var now := _now_hours()
		var arrive := now + float(entry.get("arrives_in_hours", 0.0))
		# a journey already under way keeps the hour it set out at
		if not was_travelling or moved or str(s.get("travel_from", "")) != str(entry.get("travel_from", "")):
			s["travel_depart"] = arrive - float(entry.get("travel_hours", Schedules.TRAVEL_LEAD_HOURS))
		s["travel_arrive"] = arrive
		s["travel_from"] = str(entry.get("travel_from", ""))
	else:
		s["travel_from"] = ""
	var node: Node = spawned.get(npc_id) if spawned.has(npc_id) and is_instance_valid(spawned[npc_id]) else null
	if moved:
		state_changed.emit(npc_id)
		_resync_spawn(npc_id)
		node = spawned.get(npc_id) if spawned.has(npc_id) and is_instance_valid(spawned[npc_id]) else null
	if node != null and is_talking(npc_id):
		# mid-conversation: the day moves on in the roster and the body finishes what it is saying,
		# and is sent on its way when the player lets it go (_on_dialogue_ended)
		if changed:
			_after_talk[npc_id] = true
		return s
	var after_talk := _after_talk.has(npc_id)
	_after_talk.erase(npc_id)
	# somebody who stays stood up, across a move or not, is told where they are going now. Not
	# when nothing has changed and the marker they stand at is not there to be walked to: its
	# dressing is being raised again with its cell, and the walk the body would be given is to
	# the ring round the place's middle. The Warden walked off from the Foundling that way after
	# their talk ended, when a loaded run had unloaded her cell during it.
	var told := changed or after_talk or bool(entry["travelling"]) or spot_marker(npc_id) != null
	if node != null and told and node.has_method("apply_schedule_state"):
		node.call("apply_schedule_state", entry)
	if node != null:
		steer_traveller(npc_id)
	return s


func _on_hour_changed(_hour: int) -> void:
	simulate_all()


## Journeys set out and arrive between the hours, so the roster is looked at every TICK_HOURS of
## game time as well as on the hour. The look is the same as the hourly one and costs a schedule
## lookup a person.
const TICK_HOURS := 10.0 / 60.0
var _last_tick := -1


func _process(_delta: float) -> void:
	var tick := int(floor(_now_hours() / TICK_HOURS))
	if _last_tick < 0:
		_last_tick = tick
	elif tick != _last_tick:
		_last_tick = tick
		simulate_all()


static func _now_hours() -> float:
	return float(WorldClock.day) * 24.0 + WorldClock.time_hours


func _on_story_moved(_quest_id: String = "", _detail: Variant = null) -> void:
	simulate_all()


func _on_new_day(day: int) -> void:
	for id in states:
		var s: Dictionary = states[id]
		if int(s.get("in_jail_until_day", 0)) > 0 and int(s["in_jail_until_day"]) <= day:
			s["in_jail_until_day"] = 0
	simulate_all()


func _on_weather_changed(_region_id: String, weather_id: String) -> void:
	GameState.set_flag("_weather", weather_id)
	simulate_all(weather_id)


## A conversation is over: whoever it was with goes back to their day, walking from wherever they
## stood to talk, which is how somebody whose hour turned while they talked walks away afterwards
## and a traveller the player stopped on the road walks on.
func _on_dialogue_ended(npc_id: String) -> void:
	if is_spawned(npc_id):
		simulate(npc_id)


# --- in the player's company ---------------------------------------------------------------------
#
# The roster looks at everybody's day every TICK_HOURS of game time and on every hour, and moves
# whoever it has somewhere else: a body whose place's cell is not loaded is taken away, and one
# whose marker comes up is put down on it. Under a loaded run a single step of the clock is long
# enough to cross an hour, and the Warden went from beside her fire while the Foundling was
# talking to her. Nobody the player is with is taken away or put down elsewhere by that: somebody
# they are talking to, have in the interact prompt, a quest is waiting on them to speak to, or who
# stands within KEEP_NEAR_M of them. The roster still moves them on; they walk.

## Within this of the player, a body is left where it is by the roster.
const KEEP_NEAR_M := 20.0
## People whose day moved on while they talked to the player: they are told where to go when the
## talk ends, whether or not anything changes after it.
var _after_talk: Dictionary = {}
## The objectives that wait on a particular person being spoken to.
const PINNING_OBJECTIVES: Array[String] = ["talk", "deliver"]


## Whether the roster must leave this person's body alone (see above). False for anybody who is
## not stood up.
func is_kept(npc_id: String) -> bool:
	return kept_because(npc_id) != ""


## Why the roster must leave this person's body alone, or "" when it need not: "talking",
## "targeted", "near" or "pinned".
func kept_because(npc_id: String) -> String:
	var body := actor(npc_id) as Node3D
	if body == null:
		return ""
	if is_talking(npc_id):
		return "talking"
	if _is_targeted(body):
		return "targeted"
	if _near_player(body):
		return "near"
	if is_pinned(npc_id):
		return "pinned"
	return ""


## Whether the player is with this person: talking to them, has them in the prompt, or stands
## within KEEP_NEAR_M of them. Any body in the player group counts, not only the one the streamer
## follows. A quest waiting on somebody is not the player being with them.
func is_with_player(npc_id: String) -> bool:
	var why := kept_because(npc_id)
	return why != "" and why != "pinned"


## Whether somebody whose day has them under a roof can be taken in now. At once when the player is
## not with them. When the player is only near them, or a quest is waiting on them, once they have
## walked to where their day sends them: they go in rather than vanish at the player's elbow, and
## a stand-still player does not keep a village standing in the street all night. Not while the
## player is talking to them or has them in the prompt.
func can_go_in(npc_id: String) -> bool:
	match kept_because(npc_id):
		"":
			return true
		"near", "pinned":
			var body := actor(npc_id)
			return body == null or not bool(body.get("has_target"))
	return false


## True while the player's conversation is with this person.
static func is_talking(npc_id: String) -> bool:
	var runner: Node = Social.dialogue
	return runner != null and is_instance_valid(runner) and bool(runner.call("is_running")) \
			and str(runner.get("npc_id")) == npc_id


## True while a quest's current stage waits on this person being spoken to (the Warden, for the
## Naming's first objective).
func is_pinned(npc_id: String) -> bool:
	var quests: Node = Social.quests
	if quests == null or not is_instance_valid(quests) or not quests.has_method("current_objectives"):
		return false
	for e_v in quests.call("current_objectives"):
		var e: Dictionary = e_v
		if bool(e.get("done", false)):
			continue
		var o: Dictionary = e.get("objective", {})
		if PINNING_OBJECTIVES.has(str(o.get("type", ""))) and str(o.get("target", "")) == npc_id:
			return true
	return false


func _is_targeted(body: Node) -> bool:
	for p in _players():
		var hand: Variant = p.get("interactor")
		if hand is Node and is_instance_valid(hand) and (hand as Node).get("target") == body:
			return true
	return false


func _near_player(body: Node3D) -> bool:
	if not body.is_inside_tree():
		return false
	for p in _players():
		if p.global_position.distance_to(body.global_position) <= KEEP_NEAR_M:
			return true
	return false


## Every body in the player group that is standing in the world. All of them, not the first: a
## stand-in another system left behind is no reason to take away the person beside the real one.
func _players() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node3D and (n as Node3D).is_inside_tree() and not n.is_queued_for_deletion():
			out.append(n as Node3D)
	return out


# --- spawning --------------------------------------------------------------------------------

## The cell an NPC is currently in: its place's, or for somebody on the road with the player,
## the one they are actually standing in — otherwise their home cell unloading behind you would
## take them away from your side.
func cell_of(npc_id: String) -> Vector2i:
	var on_road := escort_position(npc_id)
	if on_road != Vector3.INF:
		return WorldProbe.cell_of(on_road)
	var walking := road_position(npc_id)
	if walking != Vector3.INF:
		return WorldProbe.cell_of(walking)
	return WorldProbe.cell_of_place(place_of(npc_id))


# --- on the road ------------------------------------------------------------------------------------

## How far ahead along the road a traveller is sent each time they are steered: far enough that they
## never arrive at it between looks (the streamer looks every 0.75 s; they walk 3.4 m/s).
const ROAD_LOOKAHEAD_M := 18.0


func is_travelling(npc_id: String) -> bool:
	var s := state(npc_id)
	return bool(s.get("travelling", false)) and str(s.get("travel_from", "")) != "" and not is_escorted(npc_id)


## The road a traveller is walking, from where they set out to where they are going.
func travel_route(npc_id: String) -> PackedVector2Array:
	if not is_travelling(npc_id):
		return PackedVector2Array()
	var s := state(npc_id)
	return RoadRoutes.route(str(s["travel_from"]), str(s["place"]))


## Where on the road a traveller is now, by the share of the journey's time gone; `Vector3.INF` for
## anybody who is not on the road between two places of their own day.
func road_position(npc_id: String) -> Vector3:
	var r := travel_route(npc_id)
	if r.size() < 2:
		return Vector3.INF
	var s := state(npc_id)
	var depart := float(s.get("travel_depart", 0.0))
	var arrive := float(s.get("travel_arrive", 0.0))
	var share := 1.0 if arrive <= depart else clampf((_now_hours() - depart) / (arrive - depart), 0.0, 1.0)
	var at: Vector2 = RoadRoutes.point_along(r, share * RoadRoutes.length_of(r))["at"]
	return Vector3(at.x, WorldProbe.get_height(at.x, at.y, 0.0), at.y)


## Everybody on the road right now, living and in the world.
func travelling_ids() -> Array[String]:
	var out: Array[String] = []
	for id in states:
		if is_alive(str(id)) and not is_gone(str(id)) and is_travelling(str(id)):
			out.append(str(id))
	out.sort()
	return out


## Sends a stood-up traveller on along the road, a few paces ahead of wherever they have got to, so
## they walk it rather than cutting across country to their destination's spot. Near the end they
## are let go to walk to the spot itself.
func steer_traveller(npc_id: String) -> void:
	var body := actor(npc_id) as Node3D
	if body == null or not body.has_method("set_move_target"):
		return
	# stopped on the road to talk: they stay stopped until the player lets them go
	if is_talking(npc_id):
		return
	var r := travel_route(npc_id)
	if r.size() < 2:
		return
	var here := Vector2(body.global_position.x, body.global_position.z)
	var along := RoadRoutes.progress_of(r, here)
	var total := RoadRoutes.length_of(r)
	if total - along <= ROAD_LOOKAHEAD_M:
		return
	var ahead: Vector2 = RoadRoutes.point_along(r, along + ROAD_LOOKAHEAD_M)["at"]
	body.call("set_move_target", Vector3(ahead.x, WorldProbe.get_height(ahead.x, ahead.y, body.global_position.y), ahead.y))


func steer_travellers() -> void:
	for id in spawned.keys():
		if is_travelling(str(id)):
			steer_traveller(str(id))


func _on_cell_loaded(cell: Vector2i) -> void:
	loaded_cells[cell] = true
	if not spawning_enabled or abstract_only:
		return
	for id in states:
		if is_alive(id) and cell_of(id) == cell and not is_gone(id):
			if is_spawned(id):
				_settle_on_marker(id)
			else:
				spawn(id)


## Somebody stood up before the place they work was built — a far cell coming into the near
## ring raises the full dressing, markers and all — is moved onto their marker once it exists.
## Not somebody on the road: their spot is the one at the far end, and a cell coming up along the
## way put a traveller down there. Nor anybody the player is with (is_kept): they walk to it.
func _settle_on_marker(npc_id: String) -> void:
	if is_escorted(npc_id) or is_travelling(npc_id) or is_kept(npc_id):
		return
	var marker := spot_marker(npc_id)
	var body := actor(npc_id)
	if marker != null and body is Node3D and (body as Node3D).global_position.distance_to(marker.global_position) > 2.0:
		(body as Node3D).global_position = marker.global_position


func _on_cell_unloaded(cell: Vector2i) -> void:
	loaded_cells.erase(cell)
	for id in spawned.keys():
		if cell_of(id) == cell and not _keeps(str(id), "its cell was unloaded"):
			despawn(id)


## Spawns or despawns one NPC to match whether its cell is loaded. Somebody the player is with is
## not taken away (is_kept): their day has moved on, and they walk.
func _resync_spawn(npc_id: String) -> void:
	if not spawning_enabled or abstract_only:
		return
	var here := loaded_cells.has(cell_of(npc_id))
	if here and not spawned.has(npc_id):
		spawn(npc_id)
	elif not here and spawned.has(npc_id) and not _keeps(npc_id, "their day moved them out of the loaded cells"):
		despawn(npc_id)


## is_kept, saying so in the log when it keeps somebody the roster was about to take away: the
## Warden's going in loaded runs was only ever seen as her absence.
func _keeps(npc_id: String, what: String) -> bool:
	var why := kept_because(npc_id)
	if why == "":
		return false
	Log.info("NpcRegistry", "%s stays (%s) although %s" % [npc_id, why, what])
	return true


func is_spawned(npc_id: String) -> bool:
	return spawned.has(npc_id) and is_instance_valid(spawned[npc_id])


func actor(npc_id: String) -> Node:
	return spawned.get(npc_id) if is_spawned(npc_id) else null


func spawn(npc_id: String) -> Node:
	if is_spawned(npc_id) or not is_alive(npc_id) or is_gone(npc_id):
		return null
	if not ResourceLoader.exists(NPC_SCENE):
		return null
	var scene: PackedScene = load(NPC_SCENE)
	var node: Node = scene.instantiate()
	var def := ContentDB.get_or_empty(npc_id)
	if _is_guard(def) and ResourceLoader.exists(GUARD_SCRIPT):
		node.set_script(load(GUARD_SCRIPT))
	node.set("npc_id", npc_id)
	var parent := _spawn_parent()
	if parent == null:
		node.free()
		return null
	parent.add_child(node)
	if node is Node3D:
		(node as Node3D).global_position = spawn_position(npc_id)
	if node.has_method("apply_state"):
		node.call("apply_state", state(npc_id))
	spawned[npc_id] = node
	npc_spawned.emit(npc_id, node)
	if is_travelling(npc_id):
		steer_traveller(npc_id)
	return node


func _is_guard(def: Dictionary) -> bool:
	var tags: Variant = def.get("tags", [])
	return typeof(tags) == TYPE_ARRAY and tags.has("guard")


func _spawn_parent() -> Node:
	var world := Service.in_group("world_dynamic")
	if world != null:
		return world
	return get_tree().current_scene if get_tree() != null and get_tree().current_scene != null else self


## Where an NPC stands: its place's position, nudged deterministically per npc so a whole
## village does not stand in one spot. The spot marker (if the place scene has one) wins,
## and the actor resolves that itself once spawned.
func spawn_position(npc_id: String) -> Vector3:
	var on_road := escort_position(npc_id)
	if on_road != Vector3.INF:
		return on_road
	var walking := road_position(npc_id)
	if walking != Vector3.INF:
		return walking
	var marked := spot_marker(npc_id)
	if marked != null:
		return marked.global_position + gather_offset(npc_id, marked)
	var base := WorldProbe.place_position(place_of(npc_id))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(npc_id)
	# Two to ten metres put a village of twenty-three people in one scrum on the green. A
	# settlement is sixty to a hundred metres across, so they stand across it — still
	# deterministic, so everyone is where they were when you last looked.
	var angle := rng.randf() * TAU
	var radius := 6.0 + sqrt(rng.randf()) * 34.0
	var pos := base + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	pos.y = WorldProbe.get_height(pos.x, pos.z, base.y)
	return pos


## A marker in the world named for where this person stands right now. A point of interest's
## dressing puts one where its resident works — the toll-keeper's stool, the hermit's fire — so
## they stand up there rather than on a ring round the place's middle, which on a causeway or an
## island is the water.
func spot_marker(npc_id: String) -> Node3D:
	var spot := str(state(npc_id).get("spot", ""))
	if spot == "" or not is_inside_tree():
		return null
	var place := place_of(npc_id)
	for node in get_tree().get_nodes_in_group(SPOT_GROUP):
		if not (node is Node3D) or not (node as Node3D).is_inside_tree() or str(node.name) != spot:
			continue
		# a marker says whose place it is in; two camps' fires are not the same fire
		var owner_place := str(node.get_meta("place", ""))
		if owner_place != "" and owner_place != place:
			continue
		return node as Node3D
	return null


## Where in a shared spot one person stands. A settlement's well, green and inn door are marked
## `gather`, because half a village is sent to each of them at some hour: they stand round it,
## each in a place of their own that is the same every time, rather than all in one point. A
## spot a dressing made for one person (the toll-keeper's stool) holds them exactly on it.
static func gather_offset(npc_id: String, marker: Node3D) -> Vector3:
	if marker == null or not bool(marker.get_meta("gather", false)):
		return Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("gather:" + npc_id)
	var a := rng.randf() * TAU
	var r := rng.randf_range(0.9, 2.6)
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


func despawn(npc_id: String) -> void:
	if not spawned.has(npc_id):
		return
	var node: Node = spawned[npc_id]
	spawned.erase(npc_id)
	# Somebody who was brought somewhere stays there only while there is somebody to see it.
	# Once the player has gone they go back to their own life, off the page like everyone else.
	var kept := state(npc_id)
	if str(kept.get("waiting_at", "")) != "":
		kept["waiting_at"] = ""
	if is_instance_valid(node):
		if node.has_method("collect_state"):
			var s: Variant = node.call("collect_state")
			if typeof(s) == TYPE_DICTIONARY:
				var target := state(npc_id)
				# A dead NPC stays dead whatever the body says.
				if not bool(target.get("alive", true)):
					s.erase("alive")
					s.erase("hostile")
				target.merge(s, true)
		node.queue_free()
	npc_despawned.emit(npc_id)


func despawn_all() -> void:
	for id in spawned.keys():
		despawn(id)


# --- jail --------------------------------------------------------------------------------------

func jail(npc_id: String, days: int) -> void:
	var s := state(npc_id)
	if s.is_empty():
		return
	s["in_jail_until_day"] = WorldClock.day + maxi(1, days)
	state_changed.emit(npc_id)


# --- save ----------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	for id in spawned.keys():
		var node: Node = spawned[id]
		if is_instance_valid(node) and node.has_method("collect_state"):
			var s: Variant = node.call("collect_state")
			if typeof(s) == TYPE_DICTIONARY:
				state(id).merge(s, true)
	var out := states.duplicate(true)
	# somebody walking with the player is saved with the place they were beside, so a load into a
	# redrawn map has them on the road beside it rather than at the old coordinates (PlaceRef)
	for id in out:
		var p: Variant = (out[id] as Dictionary).get("escort_pos", [])
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 3:
			out[id]["escort_near"] = PlaceRef.pin(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return {"states": out}


func from_save(d: Dictionary) -> void:
	despawn_all()
	var saved: Dictionary = d.get("states", {})
	for id in saved:
		if typeof(saved[id]) == TYPE_DICTIONARY:
			var base: Dictionary = states.get(id, _fresh_state(ContentDB.get_or_empty(id)))
			base.merge(saved[id], true)
			var p: Variant = base.get("escort_pos", [])
			if base.has("escort_near") and typeof(p) == TYPE_ARRAY and (p as Array).size() >= 3:
				var at := PlaceRef.follow(Vector3(float(p[0]), float(p[1]), float(p[2])), base["escort_near"])
				base["escort_pos"] = [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
			base.erase("escort_near")
			states[id] = base
	simulate_all()
	for id in states:
		_resync_spawn(id)
