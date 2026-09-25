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
	var away := Vector3(1.0, 0.0, 0.3).normalized()
	for spec in [["play_22m", 22.0, 1.6], ["play_12m", 12.0, 1.6], ["low_5m", 5.0, 0.35]]:
		var dist: float = spec[1]
		var eye := at + away * dist
		eye.y = _world.provider.get_height(eye.x, eye.z) + float(spec[2])
		var body := at + away * (dist - 2.5)
		_player.teleport(Vector3(body.x, _world.provider.get_height(body.x, body.z) + 0.1, body.z), atan2(away.x, away.z))
		await _settle(at)
		await _frames(30)
		_cam.global_position = eye
		_cam.look_at(at + Vector3(0.0, 0.45, 0.0), Vector3.UP)
		_cam.make_current()
		for k in 3:
			await _frames(45)
			await _save("flock_%s_%d" % [str(spec[0]), k])
		_lines.append("flock %s: %d drawn live" % [str(spec[0]), best.live_count()])


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
