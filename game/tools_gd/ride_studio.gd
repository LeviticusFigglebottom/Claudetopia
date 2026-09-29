extends Node
## The horse in the world, photographed and filmed (DECISIONS 2026-09-24, "A starter horse").
##
##   xvfb-run -a -s '-screen 0 1280x720x24' godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy --resolution 1280x720 --fixed-fps 30 res://tools_gd/ride_studio.tscn \
##       -- --out=<dir> [--films=stand,road,slope] [--every=0.2] [--seconds=14]
##
## Loads the real world with the player in it, gives the Wardens' cob as `give_mount` does (so she
## stands where the Stable puts her, in the yard of the Toll's Lip at Merrowby), and then:
##   stand  three stills of her standing, the body at her near shoulder: size, saddle height, paint;
##   road   the rider mounted on the nearest road out of Merrowby and ridden along it -- walk,
##          canter, gallop -- by holding the keys and looking down the road, as a player does;
##          frames through the player's own camera every `every` seconds, and some from the side;
##   slope  ridden up the steepest ground near Merrowby that a canter may take (12-22°).
## Every frame is <out>/<film>_<nnn>.png, and <out>/ride.txt has one line per frame: time, the
## horse's gait, speed, slope and the ground's height under her. Run with --fixed-fps so a
## second of the film is a second of the game.

const WORLD_SCENE := "res://world/world.tscn"
const HORSE := "core:mount/wardens_cob"
const PLACE := "core:place/merrowby"

var out_dir := "captures/ride"
var films: Array[String] = ["stand", "road", "slope"]
var every := 0.2
var seconds := 14.0
var failures: Array[String] = []
var _world: World = null
var _player: Player = null
var _horse: Mount = null
var _cam: Camera3D = null
var _lines: PackedStringArray = []
var _held: Dictionary = {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--films="):
			films.assign(a.substr(8).split(","))
		elif a.begins_with("--every="):
			every = float(a.substr(8))
		elif a.begins_with("--seconds="):
			seconds = float(a.substr(10))
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _run()
	var f := FileAccess.open(out_dir.path_join("ride.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
	for msg in failures:
		push_error("RideStudio: " + msg)
	print("RIDE: %d lines, %d failures -> %s" % [_lines.size(), failures.size(), out_dir])
	get_tree().quit(0 if failures.is_empty() else 1)


func _run() -> void:
	Settings.set_value("gameplay", "play_opening", false, false)
	GameState.reset_for_new_game(11)
	GameState.set_flag(SocialContext.MOUNT_FLAG_PREFIX + HORSE, true)
	_world = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	add_child(_world)
	if not _world.is_world_ready:
		await _world.world_ready
	var spawn: Node = _world.get_node_or_null("PlayerSpawn")
	for i in 900:
		_player = spawn.get("player") as Player if spawn != null else null
		if _player != null:
			break
		await get_tree().process_frame
	if _player == null:
		failures.append("no body stood up")
		return
	if UI.has_method("close_all"):
		UI.close_all()
	var stable := Stable.find()
	for i in 300:
		if stable != null and stable.horses.has(HORSE):
			break
		await get_tree().process_frame
		stable = Stable.find()
	if stable == null or not stable.horses.has(HORSE):
		failures.append("the Stable stood no horse")
		return
	_horse = stable.horses[HORSE]
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	for film in films:
		match film:
			"stand": await _stand()
			"road": await _road()
			"slope": await _slope()
			"flock": await _flock()
			"deer": await _deer()
			"deer_wild": await _deer_wild()
			"downhill": await _downhill()


# --- stills -------------------------------------------------------------------------------------

func _stand() -> void:
	var at := _horse.global_position
	_player.teleport(at + Basis(Vector3.UP, _horse.heading) * Vector3(-1.0, 0.0, -0.45) + Vector3(0.0, 0.3, 0.0), _horse.heading - PI * 0.5)
	await _settle(at)
	_lines.append("stand: the cob at %s, heading %.0f°, the Toll's Lip's door %s" % [str(at.round()), rad_to_deg(_horse.heading), str(_door_of("core:interior/tolls_lip"))])
	var f := Basis(Vector3.UP, _horse.heading)
	for v in [["near_side", Vector3(-6.5, 1.5, 0.0)], ["front_quarter", Vector3(-4.5, 1.7, -4.5)], ["back_quarter", Vector3(4.0, 1.9, 4.8)], ["wide", Vector3(-14.0, 4.0, -8.0)]]:
		var eye: Vector3 = at + f * (v[1] as Vector3)
		_cam.global_position = eye
		_cam.look_at(at + Vector3(0.0, 1.1, 0.0), Vector3.UP)
		_cam.make_current()
		await _frames(4)
		await _save("stand_%s" % str(v[0]))


# --- the road -----------------------------------------------------------------------------------

## The nearest road out of Merrowby: a run of it from near the town outward, as world points.
func _road_run(length := 400.0) -> PackedVector3Array:
	var centre := _world.place_position(PLACE)
	var best: Dictionary = {}
	var best_d := INF
	for r in RoadNetwork.roads():
		if RoadNetwork.is_street(str(r["id"])):
			continue
		var line: PackedVector2Array = r["points"]
		for i in line.size():
			var d := line[i].distance_to(Vector2(centre.x, centre.z))
			if d > 60.0 and d < best_d:
				best_d = d
				best = {"pts": line, "i": i}
	var out := PackedVector3Array()
	if best.is_empty():
		return out
	var pts: PackedVector2Array = best["pts"]
	var i0: int = best["i"]
	# walk away from the town: whichever way along the road gets farther from it
	var step := 1 if (i0 + 1 < pts.size() and pts[i0 + 1].distance_to(Vector2(centre.x, centre.z)) > best_d) else -1
	var walked := 0.0
	var i := i0
	while i >= 0 and i < pts.size() and walked < length:
		var p := pts[i]
		out.append(Vector3(p.x, _world.provider.get_height(p.x, p.y), p.y))
		if out.size() > 1:
			walked += out[-1].distance_to(out[-2])
		i += step
	return out


func _road() -> void:
	var run := _road_run()
	if run.size() < 3:
		failures.append("no road near Merrowby to ride")
		return
	await _ride_path("road", run, [[0.0, ["W", "Alt"]], [3.0, ["W"]], [7.0, ["W", "Shift"]]])


## The steepest ground within 500 m of Merrowby that a canter takes (12-22° over 30 m), ridden up.
func _slope() -> void:
	var c := _world.place_position(PLACE)
	var best_s := 0.0
	var best: Array = []
	for gx in range(-10, 11):
		for gz in range(-10, 11):
			var p := c + Vector3(gx * 50.0, 0.0, gz * 50.0)
			for a in range(0, 360, 30):
				var d := Vector3(sin(deg_to_rad(a)), 0.0, cos(deg_to_rad(a)))
				var h0 := _world.provider.get_height(p.x, p.z)
				var h1 := _world.provider.get_height(p.x + d.x * 30.0, p.z + d.z * 30.0)
				var s := rad_to_deg(atan2(h1 - h0, 30.0))
				if s > best_s and s < 22.0 and _world.provider.water_depth_at(p.x, p.z) <= 0.0:
					best_s = s
					best = [p, d]
	if best.is_empty() or best_s < 8.0:
		failures.append("no slope near Merrowby to ride up (steepest %.0f°)" % best_s)
		return
	var p0: Vector3 = best[0]
	var dir: Vector3 = best[1]
	var run := PackedVector3Array()
	for k in range(-2, 12):
		var q := p0 + dir * (float(k) * 6.0)
		run.append(Vector3(q.x, _world.provider.get_height(q.x, q.z), q.z))
	_lines.append("slope: %.0f° over 30 m at %s, bearing %.0f°" % [best_s, str(p0.round()), rad_to_deg(atan2(dir.x, -dir.z))])
	await _ride_path("slope", run, [[0.0, ["W"]]])


## Mounts at the path's start and rides it, the keys changing at the given times, the view held
## down the path as a player looks where they go. Frames through the player's camera.
func _ride_path(label: String, path: PackedVector3Array, keys: Array) -> void:
	var start := path[0]
	var ahead := path[1] - path[0]
	var yaw := atan2(-ahead.x, -ahead.z)
	var rider := _player.rider
	if rider.riding():
		rider.drop_for_teleport()
	_player.teleport(start + Vector3(2.0, 0.5, 0.0), yaw)
	_horse.wake()
	_horse.place(start, yaw)
	await _settle(start)
	if not rider.seat_now(_horse):
		failures.append("%s: could not get into the saddle" % label)
		return
	_player.camera_rig.yaw = yaw
	_player.camera_rig.pitch = -0.12
	_player.camera_rig.camera.make_current()
	await _frames(10)
	var t := 0.0
	var next_shot := 0.0
	var shot := 0
	var k := 0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var seg := 1
	while t < seconds:
		while k < keys.size() and t >= float(keys[k][0]):
			_hold(keys[k][1])
			k += 1
		# look down the road: the next point more than 14 m ahead
		var here := _horse.global_position
		while seg < path.size() - 1 and Vector2(path[seg].x - here.x, path[seg].z - here.z).length() < 14.0:
			seg += 1
		var to := path[seg] - here
		if Vector2(to.x, to.z).length() < 4.0 and seg >= path.size() - 1:
			break
		var want := atan2(-to.x, -to.z)
		_player.camera_rig.yaw = lerp_angle(_player.camera_rig.yaw, want, 0.12)
		await get_tree().physics_frame
		t += dt
		if t >= next_shot:
			next_shot += every
			await _save("%s_%03d" % [label, shot])
			_lines.append("%s %03d t=%.2f gait=%s speed=%.2f slope=%.1f held=%s ground=%.2f y=%.2f" % [label, shot, t, _horse.gait,
					_horse.speed, _horse.slope_ahead(), _horse.held_back, _world.provider.get_height(here.x, here.z), here.y])
			shot += 1
	_hold([])
	# and from the side, as it pulls up
	_cam.make_current()
	var f := Basis(Vector3.UP, _horse.heading)
	for i in 2:
		_cam.global_position = _horse.global_position + f * Vector3(-7.0, 1.8, -1.0)
		_cam.look_at(_horse.global_position + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		await _frames(15)
		await _save("%s_side_%d" % [label, i])


# --- down hill (triage 58) ------------------------------------------------------------------------

## Real slopes near Merrowby of about 5°, 10°, 20° and 30° (the fall over 24 m, within 2.5°, dry),
## each ridden down at a walk, a trot, a canter and a gallop for five seconds. Headless: no pictures,
## a DOWNHILL line per run -- the speeds each half second, the gaits, what held it back, the ticks
## off the floor, the worst gap over the ground and sink into it, and whether it refused.
## `--headless ... res://tools_gd/ride_studio.tscn -- --films=downhill`
func _downhill() -> void:
	var c := _world.place_position(PLACE)
	var found := {}
	for want in [5.0, 10.0, 20.0, 30.0]:
		var best_err := 2.5
		for gx in range(-16, 17):
			for gz in range(-16, 17):
				var p := c + Vector3(gx * 40.0, 0.0, gz * 40.0)
				if _world.provider.water_depth_at(p.x, p.z) > 0.0:
					continue
				for a in range(0, 360, 20):
					var d := Vector3(sin(deg_to_rad(a)), 0.0, cos(deg_to_rad(a)))
					# steady over the run: the fall over each third within 4° of the whole's
					var hs: Array[float] = []
					for k in 4:
						hs.append(_world.provider.get_height(p.x + d.x * 8.0 * k, p.z + d.z * 8.0 * k))
					var s := rad_to_deg(atan2(hs[0] - hs[3], 24.0))
					var steady := true
					for k in 3:
						steady = steady and absf(rad_to_deg(atan2(hs[k] - hs[k + 1], 8.0)) - s) < 4.0
					if steady and absf(s - want) < best_err:
						best_err = absf(s - want)
						found[want] = [p, d, s]
	for want in [5.0, 10.0, 20.0, 30.0]:
		if not found.has(want):
			_lines.append("DOWNHILL %.0f°: no such slope within 640 m of Merrowby" % want)
			print(_lines[-1])
			continue
		var p0: Vector3 = found[want][0]
		var dir: Vector3 = found[want][1]
		for gait in ["Walk", "Trot", "Canter", "Gallop"]:
			var rider := _player.rider
			if rider.riding():
				rider.drop_for_teleport()
			var yaw := atan2(-dir.x, -dir.z)
			# a length of run-up above the slope's top, as far as the gait needs to get going
			var start := p0 - dir * 4.0
			start.y = _world.provider.get_height(start.x, start.z)
			_player.teleport(start + Vector3(2.0, 0.5, 0.0), yaw)
			_horse.wake()
			_horse.place(start, yaw)
			_horse.stamina = _horse.max_stamina
			await _settle(start)
			if not rider.seat_now(_horse):
				failures.append("downhill: could not get into the saddle")
				return
			_player.camera_rig.yaw = yaw
			var keys := {"Walk": ["W", "Alt"], "Trot": ["W", "C"], "Canter": ["W"], "Gallop": ["W", "Shift"]}
			_hold(keys[gait])
			var speeds: Array[String] = []
			var gaits: Array[String] = []
			var held := {}
			var off := 0
			var gap := 0.0
			var sink := 0.0
			var refused := [0]
			var on_ref := func(_r: String) -> void: refused[0] += 1
			_horse.refused.connect(on_ref)
			var n := int(5.0 * Engine.physics_ticks_per_second)
			for i in n:
				_player.camera_rig.yaw = yaw
				await get_tree().physics_frame
				var h := _horse.global_position
				var g := _world.provider.get_height(h.x, h.z)
				gap = maxf(gap, h.y - g)
				sink = maxf(sink, g - h.y)
				if not _horse.is_on_floor():
					off += 1
				if _horse.gait != "" and (gaits.is_empty() or gaits[-1] != _horse.gait):
					gaits.append(_horse.gait)
				if _horse.held_back != "":
					held[_horse.held_back] = true
				if _horse.call("_refusal") != "":
					held["refusing"] = int(held.get("refusing", 0)) + 1
				if i % 30 == 0:
					speeds.append("%.1f/%.0f°" % [_horse.speed, _horse.slope_ahead()])
			_horse.refused.disconnect(on_ref)
			_hold([])
			_lines.append("DOWNHILL %.0f° (%.1f° at %s) %-6s speeds %s gaits %s held %s off-floor %d/%d gap %.2f sink %.2f refused %d" % [want,
					float(found[want][2]), str(p0.round()), gait, " ".join(PackedStringArray(speeds)), " > ".join(PackedStringArray(gaits)),
					str(held.keys()), off, n, gap, sink, refused[0]])
			print(_lines[-1])


# --- the flock ----------------------------------------------------------------------------------

## The nearest sheep to Merrowby that the world has put down (a paddock's, the Wardens' ewe's, a
## grazing flock's), photographed as a player comes on them: from 22 m and 12 m at eye height with
## the player's own body in the shot, and from 5 m down low, where the old prop sheep showed their
## gutted underside.
func _flock() -> void:
	var centre := _world.place_position(PLACE)
	var best: Livestock = null
	var best_d := INF
	var at := Vector3.ZERO
	# the paddocks stand up with their settlement's cells: stand the body in the town first
	_player.teleport(centre + Vector3(0.0, 1.0, 0.0), 0.0)
	await _settle(centre)
	for i in 120:
		for n in get_tree().get_nodes_in_group("livestock"):
			var l := n as Livestock
			if l == null:
				continue
			for b in l.beasts:
				if str(b["kind"]) != "sheep":
					continue
				var p := l.to_global(b["at"])
				var d := p.distance_to(centre)
				if d < best_d:
					best_d = d
					best = l
					at = p
		if best != null:
			break
		await _frames(5)
	if best == null:
		failures.append("flock: no sheep within the streamed ring of Merrowby")
		return
	_lines.append("flock: %d beasts at %s, %.0f m from Merrowby's middle, rigged %s" % [best.beasts.size(), str(at.round()),
			best_d, str(bool(best.beasts[0].get("rigged", false)))])
	for spec in [["play_18m", 18.0, 1.6], ["play_10m", 10.0, 1.6], ["low_4m", 4.0, 0.35]]:
		var dist: float = spec[1]
		# the side with a clear line to her: the first of sixteen bearings whose eye sees the sheep
		# over no fence post, bale or wall (the body stands behind the camera, out of the shot)
		var away := _clear_bearing(at, dist, float(spec[2]))
		var eye := at + away * dist
		eye.y = _world.provider.get_height(eye.x, eye.z) + float(spec[2])
		var body := at + away * (dist + 3.0)
		_player.teleport(Vector3(body.x, _world.provider.get_height(body.x, body.z) + 0.1, body.z), atan2(-away.x, -away.z), "ride_studio")
		await _settle(at)
		await _frames(30)
		_cam.global_position = eye
		_cam.look_at(at + Vector3(0.0, 0.45, 0.0), Vector3.UP)
		_cam.make_current()
		await _frames(45)
		await _save("flock_%s" % str(spec[0]))
		_lines.append("flock %s: %d drawn live, from %s" % [str(spec[0]), best.live_count(), str(away.snapped(Vector3.ONE * 0.01))])


## The red deer beside the cob, for scale: a stag, a hind and a yearling hind stood in the Toll's
## Lip's yard next to her, standing, walking and at the bound (played on the spot), from the side and
## the three-quarters.
func _deer() -> void:
	var at := _horse.global_position
	var f := Basis(Vector3.UP, _horse.heading)
	_player.teleport(at + f * Vector3(0.0, 0.0, -9.0) + Vector3(0.0, 0.3, 0.0), _horse.heading, "ride_studio")
	await _settle(at)
	var side := f * Vector3(1.0, 0.0, 0.0)
	var deer: Array[HorseModel] = []
	for spec in [[2.2, true, 1.08], [4.2, false, 1.0], [6.0, false, 0.82]]:
		var m := HorseModel.new()
		m.model_path = DeerHerds.MODEL
		m.antlers = bool(spec[1])
		_world.add_child(m)
		var p: Vector3 = at + side * float(spec[0])
		p.y = _world.provider.get_height(p.x, p.z)
		m.global_transform = Transform3D(Basis(Vector3.UP, _horse.heading).scaled(Vector3.ONE * float(spec[2])), p)
		deer.append(m)
	var mid := at + side * 3.0
	for pose in [["stand", 0.0, ""], ["walk", 1.1, "Walk"], ["run", 9.5, "Run"], ["alert", 0.0, "Alert"]]:
		for m in deer:
			m.standing_clip = "Alert" if str(pose[2]) == "Alert" else ""
			m.set_motion(float(pose[1]), 0.0, str(pose[2]))
		await _frames(20 if str(pose[0]) == "stand" else 11)
		for v in [["side", Vector3(-11.0, 1.3, 1.5)], ["quarter", Vector3(-7.5, 1.8, -8.0)]]:
			if str(pose[0]) == "alert" and str(v[0]) == "side":
				continue
			var eye: Vector3 = mid + f * (v[1] as Vector3)
			eye.y = maxf(eye.y, _world.provider.get_height(eye.x, eye.z) + 1.0)
			_cam.global_position = eye
			_cam.look_at(mid + Vector3(0.0, 1.0, 0.0), Vector3.UP)
			_cam.make_current()
			await _frames(2)
			await _save("deer_%s_%s" % [str(pose[0]), str(v[0])])
	_lines.append("deer: stag, hind and yearling beside the cob at %s" % str(at.round()))
	for m in deer:
		m.queue_free()


## The deer where they live: the herds at a Briarwold wood's edge as the country puts them there,
## near (the rigged deer), off on the next rise (the far herd's meshes), and put up and running.
func _deer_wild() -> void:
	var p := _world.provider
	var cell := Vector2i(27, 17)
	var c := Vector3(p.origin.x + (float(cell.x) + 0.5) * 256.0, 0.0, p.origin.y + (float(cell.y) + 0.5) * 256.0)
	c.y = p.get_height(c.x, c.z)
	_player.teleport(c + Vector3(0.0, 1.0, 0.0), 0.0, "ride_studio")
	await _settle(c)
	var herds: DeerHerds = _world.wildlife.deer if _world.wildlife != null else null
	if herds == null:
		failures.append("deer_wild: no deer herds under the wildlife")
		return
	Settings.set_value("graphics", "wildlife", 3.0, false)
	_world.wildlife.set_density(3.0)
	var best: Dictionary = {}
	for i in 200:
		var bd := INF
		for h in herds.herds:
			var d := DeerHerds._flat(h["home"], c)
			if d < bd:
				bd = d
				best = h
		if not best.is_empty():
			break
		await _frames(5)
	if best.is_empty():
		failures.append("deer_wild: no herd within reach of the Briarwold's edge at %s" % str(c.round()))
		return
	var home: Vector3 = best["home"]
	_lines.append("deer_wild: %d herds, %d deer (%d stags); the nearest %d at %s" % [herds.herds.size(), herds.count(),
			herds.count(true), (best["deer"] as Array).size(), str(home.round())])
	# the body well back out of their way, behind the camera
	for spec in [["far_140m", 140.0, 6.0], ["near_45m", 45.0, 1.7], ["near_28m", 28.0, 1.6]]:
		var dist: float = spec[1]
		var away := _clear_bearing(home, dist, float(spec[2]))
		var eye := home + away * dist
		eye.y = p.get_height(eye.x, eye.z) + float(spec[2])
		var body := home + away * (dist + 4.0)
		# nobody near: they graze on, the eye is only a camera
		_player.teleport(Vector3(body.x, p.get_height(body.x, body.z) + 0.1, body.z) + away * 110.0, 0.0, "ride_studio")
		_cam.global_position = eye
		_cam.look_at(home + Vector3(0.0, 0.9, 0.0), Vector3.UP)
		_cam.make_current()
		await _frames(60)
		await _save("deer_wild_%s" % str(spec[0]))
		_lines.append("deer_wild %s: %d rigged" % [str(spec[0]), herds.live_count()])
	# now the body walks up on them from behind the camera, and they go
	var away := _clear_bearing(home, 30.0, 1.6)
	var walk_from := home + away * 34.0
	_player.teleport(Vector3(walk_from.x, p.get_height(walk_from.x, walk_from.z) + 0.1, walk_from.z), atan2(-away.x, -away.z), "ride_studio")
	var eye2 := home + away * 40.0 + Vector3(-away.z, 0.0, away.x) * 12.0
	eye2.y = p.get_height(eye2.x, eye2.z) + 2.2
	_cam.global_position = eye2
	_cam.look_at(home + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	_cam.make_current()
	for k in 10:
		await _frames(6)
		await _save("deer_wild_flee_%02d" % k)
	_lines.append("deer_wild flee: herd %s" % str(DeerHerds.S.keys()[int(best["state"])]))


## A bearing from `at` along which an eye `dist` out and `h` up sees the sheep's back clear.
func _clear_bearing(at: Vector3, dist: float, h: float) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var target := at + Vector3(0.0, 0.45, 0.0)
	for i in 16:
		var a := TAU * float(i) / 16.0 + 0.3
		var dir := Vector3(sin(a), 0.0, cos(a))
		var eye := at + dir * dist
		eye.y = _world.provider.get_height(eye.x, eye.z) + h
		if eye.y < target.y - 1.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, target)
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["position"] as Vector3).distance_to(target) < 0.8:
			return dir
	return Vector3(1.0, 0.0, 0.3).normalized()


# --- helpers ----------------------------------------------------------------------------------------

func _hold(names: Array) -> void:
	for n in _held.keys():
		if not names.has(n):
			_key(str(n), false)
			_held.erase(n)
	for n in names:
		if not _held.has(n):
			_key(str(n), true)
			_held[n] = true


func _key(key_name: String, pressed: bool) -> void:
	var code := OS.find_keycode_from_string(key_name)
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	ev.shift_pressed = pressed and code == KEY_SHIFT
	ev.alt_pressed = pressed and code == KEY_ALT
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _settle(at: Vector3) -> void:
	_world.streamer.refresh()
	for i in 600:
		if _world.streamer.is_loaded_around(at):
			break
		await get_tree().process_frame
	await _frames(20)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(file_name + ".png"))


func _door_of(interior: String) -> Vector3:
	for wd in get_tree().get_nodes_in_group("world_doors"):
		for d in wd.get("placed"):
			if d != null and str(d.get("interior_id")) == interior:
				return (d as Node3D).global_position.round()
	return Vector3.INF
