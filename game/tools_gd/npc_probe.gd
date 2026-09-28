extends Node
## The people probe: how the villagers of a town get about, measured.
##
##   ./run.sh npcs [--place=merrowby] [--interior=maud_bakehouse] [--seconds=30] [--no-interior]
##
## Boot attaches it at the root when it sees --npcs=<dir> and starts a new game with no opening. Once
## the body stands it is put in the middle of the place, the clock is stopped at an hour and the
## people are left to settle, then the clock is moved on to an hour that sends them about the town
## (07:00 -> 10:00 and 16:00 -> 17:30, the first pass's windows, and 12:00 -> 13:00, when half the
## town goes to the well) and they are watched for --seconds of the game's time at a fixed 60 ticks.
## Then the player goes through the door of --interior at an hour its resident is in, and they are
## watched there as the hour comes that sends them out.
##
## For each window it counts, over every person stood up:
## - **overlap**: seconds two bodies (or a body and the player) stood closer than OVERLAP_M, summed
##   over the pairs, and the pairs that ever did;
## - **stuck**: seconds a person who was walking made less than STUCK_M in a second;
## - **walks / arrivals / short**: the walks begun, the arrivals, and the arrivals more than SHORT_M
##   from where the walk was for (a leg given up) or walks still going at the end;
## - **walling**: people standing at the end with a wall or a house within WALL_M in front of their
##   face; **fallen**: people more than 2 m under where they stood at the start of the window;
## - **snaps**: jumps of more than a metre in a tick that nobody walked;
## - **cost**: the median physics tick with the people and with them switched off (ms), the
##   difference being what they cost.
## One row a window in <dir>/npcs.jsonl, and a table on stdout.

const OVERLAP_M := 0.5
const STUCK_M := 0.3
const SHORT_M := 3.0
const WALL_M := 0.8
const SNAP_M := 1.0

var out_dir := ""
var place := "core:place/merrowby"
var interior := "core:interior/maud_bakehouse"
var seconds := 30.0
var do_interior := true
var _body: Node3D = null
var _rows: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--npcs="):
			out_dir = a.substr(7)
		elif a.begins_with("--place="):
			var p := a.substr(8)
			place = p if p.contains(":") else "core:place/" + p
		elif a.begins_with("--interior="):
			var i := a.substr(11)
			interior = i if i.contains(":") else "core:interior/" + i
		elif a.begins_with("--seconds="):
			seconds = float(a.substr(10))
		elif a == "--no-interior":
			do_interior = false
	if not out_dir.is_absolute_path():
		out_dir = ProjectSettings.globalize_path("res://../%s" % out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	EventBus.player_spawned.connect(func(p: Node) -> void: _body = p as Node3D)
	_run()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while _body == null and Time.get_ticks_msec() - t0 < 600000:
		await get_tree().process_frame
	if _body == null:
		print("NPCS: FAIL (no body stood in the world)")
		get_tree().quit(1)
		return
	await _ticks(180)
	var lifted_until := Time.get_ticks_msec() + 180000
	while UI.is_faded_out() and Time.get_ticks_msec() < lifted_until:
		await get_tree().process_frame
	WorldClock.time_scale = 0.0
	var mid := WorldProbe.place_position(place)
	var at := Vector3(mid.x + 3.0, World.get_height(mid.x + 3.0, mid.z + 3.0) + 1.0, mid.z + 3.0)
	_put(at)
	await _wait_for_cells(120.0)
	for pair: Array in [[7.0, 10.0], [12.0, 13.0], [16.0, 17.5]]:
		WorldClock.set_time(float(pair[0]))
		# the people stood up, on their markers, at their work
		await _ticks(600)
		WorldClock.set_time(float(pair[1]))
		_rows.append(await _watch("%s %02d:%02d->%02d:%02d" % [Ids.name_of(place), int(pair[0]), int(fmod(float(pair[0]), 1.0) * 60.0),
				int(pair[1]), int(fmod(float(pair[1]), 1.0) * 60.0)], seconds))
	if do_interior:
		_rows.append(await _inside())
	var f := FileAccess.open("%s/npcs.jsonl" % out_dir, FileAccess.WRITE)
	for r in _rows:
		f.store_line(JSON.stringify(r))
	f.close()
	_table()
	print("NPCS: DONE (%d windows, %.0f s)" % [_rows.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(0)


## Through the door of the interior at an hour its resident is at home, and watched there.
func _inside() -> Dictionary:
	var def := ContentDB.get_or_empty(interior)
	var who := str(def.get("resident", def.get("resident_npc", "")))
	# an hour they are in: the first of the small hours or the evening the roster says is indoors
	var reg := NpcRegistry.instance
	var hour := 21.0
	for h: float in [21.0, 22.0, 6.0, 5.0, 12.0, 13.0, 19.0]:
		WorldClock.set_time(h)
		if reg != null and reg.is_indoors(who):
			hour = h
			break
	if not Interiors.enter(interior):
		return {"window": "inside %s" % Ids.name_of(interior), "error": "could not go in"}
	await _ticks(600)
	# and the hour moves on while the player is in, to the one that sends them out (from bed to the
	# oven): the first after this that the roster does not have them indoors
	var then := fmod(hour + 1.0, 24.0)
	for k in 23:
		var h := fmod(hour + 1.0 + float(k), 24.0)
		WorldClock.set_time(h)
		if reg == null or not reg.is_indoors(who):
			then = h
			break
	WorldClock.set_time(fmod(then - 0.1 + 24.0, 24.0))
	await _ticks(60)
	WorldClock.set_time(then)
	var row := await _watch("inside %s %02d->%02d (%s)" % [Ids.name_of(interior), int(hour), int(then), Ids.name_of(who)], seconds)
	var root: Node3D = null
	for n in get_tree().get_nodes_in_group("interior_root"):
		if str((n as Node).get_meta("interior_id", "")) == interior:
			root = n as Node3D
	row["floor_y"] = root.global_position.y if root != null else NAN
	var ys := []
	for n in _people():
		ys.append(snappedf(n.global_position.y, 0.01))
	row["people_y"] = ys
	Interiors.exit()
	return row


func _watch(label: String, secs: float) -> Dictionary:
	var people := {}
	var starts := {}
	var overlap := 0.0
	var pairs := {}
	var stuck := 0.0
	var stuck_who := {}
	var walks := 0
	var arrivals := 0
	var short := 0
	var snaps := 0
	var walking := {}
	var goal := {}
	var last := {}
	var window_from := {}
	var window_t := 0.0
	var arrived_by := {}
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var ticks := int(secs / dt)
	var cost_on: Array[float] = []
	for t in ticks:
		await get_tree().physics_frame
		cost_on.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		var list := _people()
		for n in list:
			var id := n.get_instance_id()
			if not people.has(id):
				people[id] = n
				starts[id] = n.global_position
				last[id] = n.global_position
				window_from[id] = n.global_position
				var cb := func(_p: String) -> void: arrived_by[id] = int(arrived_by.get(id, 0)) + 1
				n.connect("arrived", cb)
			var going := bool(n.get("has_target"))
			if going and not bool(walking.get(id, false)):
				walks += 1
				goal[id] = n.get("target_position")
			if int(arrived_by.get(id, 0)) > 0:
				arrivals += int(arrived_by[id])
				if goal.has(id) and _flat(n.global_position - (goal[id] as Vector3)) > SHORT_M:
					short += 1
				arrived_by[id] = 0
			walking[id] = going
			var moved := _flat(n.global_position - (last[id] as Vector3))
			if moved > SNAP_M:
				snaps += 1
			last[id] = n.global_position
		# pairs, the player among them
		var bodies: Array[Node3D] = []
		bodies.assign(list)
		if is_instance_valid(_body):
			bodies.append(_body)
		for i in bodies.size():
			for j in range(i + 1, bodies.size()):
				var a := bodies[i]
				var b := bodies[j]
				if absf(a.global_position.y - b.global_position.y) < 1.5 and _flat(a.global_position - b.global_position) < OVERLAP_M:
					overlap += dt
					pairs["%s|%s" % [a.name, b.name]] = true
		window_t += dt
		if window_t >= 1.0:
			window_t = 0.0
			for n in list:
				var id := n.get_instance_id()
				if bool(walking.get(id, false)) and window_from.has(id) and _flat(n.global_position - (window_from[id] as Vector3)) < STUCK_M:
					stuck += 1.0
					stuck_who[str(n.get("npc_id"))] = float(stuck_who.get(str(n.get("npc_id")), 0.0)) + 1.0
				window_from[id] = n.global_position
	var unfinished := 0
	var walling := 0
	var fallen := 0
	var walled_who := []
	for id in people:
		var n: Node3D = people[id]
		if not is_instance_valid(n):
			continue
		if bool(n.get("has_target")):
			unfinished += 1
		elif _faces_wall(n):
			walling += 1
			walled_who.append(Ids.name_of(str(n.get("npc_id"))))
		if n.global_position.y < (starts[id] as Vector3).y - 2.0:
			fallen += 1
	var cost_off := await _cost_without_people()
	var worst := stuck_who.keys()
	worst.sort_custom(func(a: String, b: String) -> bool: return float(stuck_who[a]) > float(stuck_who[b]))
	var row := {
		"window": label, "people": people.size(), "seconds": secs,
		"overlap_s": snappedf(overlap, 0.01), "overlap_pairs": pairs.size(),
		"stuck_s": stuck, "stuck_people": stuck_who.size(),
		"stuck_worst": worst.slice(0, 4).map(func(k: String) -> String: return "%s %.0fs" % [Ids.name_of(k), float(stuck_who[k])]),
		"walks": walks, "arrivals": arrivals, "short": short, "unfinished": unfinished,
		"walling": walling, "walling_who": walled_who, "fallen": fallen, "snaps": snaps,
		"tick_ms": snappedf(_median(cost_on) * 1000.0, 0.001),
		"tick_ms_without": snappedf(cost_off * 1000.0, 0.001),
	}
	print("[npcs] %s" % JSON.stringify(row))
	return row


## The physics tick with every person switched off, for as many ticks as it takes to read it.
func _cost_without_people() -> float:
	var list := _people()
	for n in list:
		n.process_mode = Node.PROCESS_MODE_DISABLED
	var got: Array[float] = []
	for t in 240:
		await get_tree().physics_frame
		got.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
	for n in list:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT
	return _median(got)


static func _median(v: Array[float]) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return s[s.size() >> 1]


func _faces_wall(n: Node3D) -> bool:
	var face: Vector3 = n.call("facing_flat") if n.has_method("facing_flat") else -n.global_transform.basis.z
	var from := n.global_position + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, from + face * WALL_M, 1)
	q.exclude = [(n as CollisionObject3D).get_rid()]
	return not n.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _people() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("npc"):
		if n is Npc and (n as Npc).alive and (n as Node3D).is_inside_tree():
			out.append(n as Node3D)
	return out


func _table() -> void:
	print("%-44s %6s %9s %6s %8s %6s %6s %5s %5s %5s %5s %8s %8s" % ["window", "people", "overlap_s", "pairs", "stuck_s",
			"walks", "arrive", "short", "unfin", "wall", "fall", "tick_ms", "no_npcs"])
	for r: Dictionary in _rows:
		if r.has("error"):
			print("%-44s %s" % [r["window"], r["error"]])
			continue
		print("%-44s %6d %9.2f %6d %8.0f %6d %6d %5d %5d %5d %5d %8.3f %8.3f" % [r["window"], r["people"], r["overlap_s"],
				r["overlap_pairs"], r["stuck_s"], r["walks"], r["arrivals"], r["short"], r["unfinished"], r["walling"],
				r["fallen"], r["tick_ms"], r["tick_ms_without"]])


func _put(at: Vector3) -> void:
	if _body.has_method("teleport"):
		_body.call("teleport", at, 0.0)
	else:
		_body.global_position = at


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait_for_cells(limit_s: float) -> void:
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	await get_tree().process_frame
	while Time.get_ticks_msec() - t0 < int(limit_s * 1000.0):
		var world := World.instance
		if world == null or world.streamer == null or not is_instance_valid(_body):
			return
		if world.streamer.is_loaded_around(_body.global_position):
			return
		await get_tree().process_frame


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
