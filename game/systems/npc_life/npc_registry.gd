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
	return Service.ensure(load("res://systems/npc_life/npc_registry.gd"), "NpcRegistry") as NpcRegistry


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


func place_of(npc_id: String) -> String:
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
	s["place"] = entry["place"]
	s["activity"] = entry["activity"]
	s["spot"] = entry["spot"]
	s["indoors"] = bool(entry.get("indoors", false))
	s["travelling"] = entry["travelling"]
	if moved:
		state_changed.emit(npc_id)
		_resync_spawn(npc_id)
	elif spawned.has(npc_id) and is_instance_valid(spawned[npc_id]):
		var node: Node = spawned[npc_id]
		if node.has_method("apply_schedule_state"):
			node.call("apply_schedule_state", entry)
	return s


func _on_hour_changed(_hour: int) -> void:
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


# --- spawning --------------------------------------------------------------------------------

## The cell an NPC is currently in: its place's, or for somebody on the road with the player,
## the one they are actually standing in — otherwise their home cell unloading behind you would
## take them away from your side.
func cell_of(npc_id: String) -> Vector2i:
	var on_road := escort_position(npc_id)
	if on_road != Vector3.INF:
		return WorldProbe.cell_of(on_road)
	return WorldProbe.cell_of_place(place_of(npc_id))


func _on_cell_loaded(cell: Vector2i) -> void:
	loaded_cells[cell] = true
	if not spawning_enabled or abstract_only:
		return
	for id in states:
		if is_alive(id) and cell_of(id) == cell:
			if is_spawned(id):
				_settle_on_marker(id)
			else:
				spawn(id)


## Somebody stood up before the place they work was built — a far cell coming into the near
## ring raises the full dressing, markers and all — is moved onto their marker once it exists.
func _settle_on_marker(npc_id: String) -> void:
	if is_escorted(npc_id):
		return
	var marker := spot_marker(npc_id)
	var body := actor(npc_id)
	if marker != null and body is Node3D and (body as Node3D).global_position.distance_to(marker.global_position) > 2.0:
		(body as Node3D).global_position = marker.global_position


func _on_cell_unloaded(cell: Vector2i) -> void:
	loaded_cells.erase(cell)
	for id in spawned.keys():
		if cell_of(id) == cell:
			despawn(id)


## Spawns or despawns one NPC to match whether its cell is loaded.
func _resync_spawn(npc_id: String) -> void:
	if not spawning_enabled or abstract_only:
		return
	var here := loaded_cells.has(cell_of(npc_id))
	if here and not spawned.has(npc_id):
		spawn(npc_id)
	elif not here and spawned.has(npc_id):
		despawn(npc_id)


func is_spawned(npc_id: String) -> bool:
	return spawned.has(npc_id) and is_instance_valid(spawned[npc_id])


func actor(npc_id: String) -> Node:
	return spawned.get(npc_id) if is_spawned(npc_id) else null


func spawn(npc_id: String) -> Node:
	if is_spawned(npc_id) or not is_alive(npc_id):
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
	var marked := spot_marker(npc_id)
	if marked != null:
		return marked.global_position
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
	return {"states": states.duplicate(true)}


func from_save(d: Dictionary) -> void:
	despawn_all()
	var saved: Dictionary = d.get("states", {})
	for id in saved:
		if typeof(saved[id]) == TYPE_DICTIONARY:
			var base: Dictionary = states.get(id, _fresh_state(ContentDB.get_or_empty(id)))
			base.merge(saved[id], true)
			states[id] = base
	simulate_all()
	for id in states:
		_resync_spawn(id)
