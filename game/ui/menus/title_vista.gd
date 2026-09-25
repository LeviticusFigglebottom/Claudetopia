class_name TitleVista
extends Node
## The country behind the title's menu: held, slowly moving shots of the world, each at its own hour
## and weather, dipped to dark between them, round and round (`core:cinematic/title`).
##
## The menu is drawn and takes input before any of this starts. The world is stood up a few frames
## later, without a body, without the game's services and without telling the game it has entered a
## region (`World.vista`), so nothing the title shows reaches a new game, a load or a continue. Its
## own camera leads the streamer. While a shot plays, the next shot's cells are asked for beside it
## (`WorldStreamer.set_also_around`); a shot is never shown before its cells have arrived, and the
## one before holds its last frame, at most NEXT_WAIT_CAP_S, while they come. The first shot fades
## in over the drawn chart the menu has always had, so the menu is never waiting for the country.
##
## It borrows the clock (stopped, and set to each shot's hour) and gives it back in `_exit_tree`, which
## is also where the world goes: the scene the menu changes to never meets it. The shots are data:
## the camera paths are `CinematicPath`s, validated by `CinematicDef` like the opening's.

## A shot started showing (after its dip), and the vista came up or went.
signal shot_started(index: int, shot_id: String)
signal showing_changed(showing: bool)

const DEF_ID := "core:cinematic/title"
const WORLD_SCENE := "res://world/world.tscn"
## Frames the menu is drawn and live before the world is asked for.
const START_DELAY_FRAMES := 4
## However slowly the first shot's country comes, the chart stays up this long at most, then the
## vista is given up for this visit (a machine that slow is better served by the chart).
const FIRST_SHOT_CAP_S := 40.0
## A shot holds on its last frame at most this long for the next one's cells, then the next is shown.
const NEXT_WAIT_CAP_S := 8.0
## Frames drawn at a new place, under the dark, before the dip lifts: Terrain3D's clipmap re-centres.
const SETTLE_FRAMES := 3
const REVEAL_S := 2.2
const DIP_OUT_S := 1.0
const DIP_IN_S := 1.4
## One long frame moves the pictures on no more than this.
const MAX_STEP_S := 0.1
## The camera never goes nearer the ground than this, however the land is rebuilt.
const CLEARANCE := 2.0

enum Phase { IDLE, LOADING, FIRST, PLAY, DIP_OUT, WAIT_NEXT, DIP_IN, GONE }

## A headless run never stands a world up behind a menu unless a test asks for it here.
static var headless_allowed := false

## Tests run the pictures faster; the waits for the country stay in real seconds.
var time_scale := 1.0

## What the menu gives it to draw with: the dark it dips to (alpha 1 is dark), and the chart it fades
## out once the country is up.
var dip: CanvasItem = null
var chart: CanvasItem = null

var def: Dictionary = {}
var world: World = null
var camera: Camera3D = null
var phase := Phase.IDLE
var index := -1
## Shots shown, and for each whether its cells were all in when it was shown.
var shown: Array[Dictionary] = []

var _shots: Array = []
var _paths: Array = []
var _t := 0.0
var _phase_t := 0.0
var _settle := 0
var _last_us := 0
var _clock_saved: Dictionary = {}
var _frames := 0


## Whether the title should show the country here: a world to show, a display to draw it on, and the
## setting on.
static func wanted() -> bool:
	if DisplayServer.get_name() == "headless" and not headless_allowed:
		return false
	if not bool(Settings.get_value("graphics", "title_vista", true)):
		return false
	if not bool(WorldStatus.current().get("playable", false)):
		return false
	return ContentDB.has(DEF_ID)


func _ready() -> void:
	add_to_group("title_vista")
	def = ContentDB.get_or_empty(DEF_ID)
	_shots = def.get("shots", [])
	if _shots.is_empty():
		phase = Phase.GONE
		return
	phase = Phase.LOADING
	_last_us = Time.get_ticks_usec()


func is_showing() -> bool:
	return phase in [Phase.PLAY, Phase.DIP_OUT, Phase.WAIT_NEXT, Phase.DIP_IN]


func current_shot_id() -> String:
	return str((_shots[index] as Dictionary).get("id", "")) if index >= 0 and index < _shots.size() else ""


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	# the pictures move by `dt`; the dips and the waits for the country keep real time (`raw`)
	var raw := minf(float(now - _last_us) / 1000000.0, MAX_STEP_S)
	var dt := raw * time_scale
	_last_us = now
	if phase != Phase.GONE and not bool(Settings.get_value("graphics", "title_vista", true)):
		# switched off in the settings the title opened: the chart comes back at once
		stop()
		return
	match phase:
		Phase.LOADING:
			_frames += 1
			if _frames == START_DELAY_FRAMES:
				_stand_world_up()
		Phase.FIRST:
			_phase_t += raw
			if _cells_ready(index):
				_settle += 1
			if _settle >= SETTLE_FRAMES:
				_show(index, true)
				_fade(chart, 0.0, REVEAL_S)
				_fade(dip, 0.0, REVEAL_S)
				phase = Phase.PLAY
				showing_changed.emit(true)
			elif _phase_t > FIRST_SHOT_CAP_S:
				Log.warn("TitleVista", "the first shot's country did not come in %.0f s; the chart stays" % FIRST_SHOT_CAP_S)
				stop()
		Phase.PLAY:
			_t += dt
			_pose(index, _t)
			var duration := float((_shots[index] as Dictionary).get("duration", 10.0))
			if _t >= duration - DIP_OUT_S:
				phase = Phase.DIP_OUT
				_phase_t = 0.0
				_fade(dip, 1.0, DIP_OUT_S)
		Phase.DIP_OUT, Phase.WAIT_NEXT:
			_t += dt
			_phase_t += raw
			_pose(index, _t)
			if _phase_t < DIP_OUT_S:
				return
			var next := _next(index)
			phase = Phase.WAIT_NEXT
			if _cells_ready(next) or _phase_t > DIP_OUT_S + NEXT_WAIT_CAP_S:
				_enter(next)
				phase = Phase.DIP_IN
				_phase_t = 0.0
				_settle = 0
		Phase.DIP_IN:
			_t += dt
			_pose(index, _t)
			_settle += 1
			if _settle == SETTLE_FRAMES:
				_show(index, _cells_ready(index))
				_fade(dip, 0.0, DIP_IN_S)
				phase = Phase.PLAY


# --- the world --------------------------------------------------------------------------------------

func _stand_world_up() -> void:
	var packed := load(WORLD_SCENE) as PackedScene
	if packed == null:
		stop()
		return
	_clock_saved = {"time": WorldClock.time_hours, "day": WorldClock.day, "running": WorldClock.running}
	WorldClock.running = false
	var w := packed.instantiate() as World
	w.name = "TitleWorld"
	w.vista = true
	var spawn := w.get_node_or_null("PlayerSpawn")
	if spawn != null:
		spawn.set("enabled", false)
		spawn.set("services_without_a_body", false)
	# the camera is the world's eye from its first frame: in the group the world looks for its
	# target in, under the world, so no fly camera is made
	camera = Camera3D.new()
	camera.name = "TitleCamera"
	camera.near = 0.25
	camera.far = 6500.0
	camera.add_to_group("streamer_target")
	w.add_child(camera)
	var first_place := _first_place()
	if not first_place.is_empty():
		w.spawn_place = first_place
	world = w
	add_child(w)
	camera.make_current()
	if not w.is_world_ready:
		await w.world_ready
	if phase == Phase.GONE or not is_instance_valid(w):
		return
	camera.far = Graphics.camera_far(Settings.data.get("graphics", {}))
	_resolve()
	var first := _next(-1)
	if first < 0:
		stop()
		return
	_enter(first)
	phase = Phase.FIRST
	_phase_t = 0.0
	_settle = 0


func _first_place() -> String:
	for s in _shots:
		for k in (s as Dictionary).get("keys", []):
			var at: Variant = (k as Dictionary).get("at", null)
			if at is Dictionary:
				return str((at as Dictionary).get("place", ""))
	return ""


func _surface(x: float, z: float) -> float:
	var provider := world.provider if world != null else null
	if provider == null:
		return 0.0
	return maxf(provider.get_height(x, z), provider.water_level_at(x, z))


func _place(id: String) -> Vector3:
	if id.is_empty() or not ContentDB.has(id) or world == null:
		return Vector3.INF
	var at := world.place_position(id)
	return Vector3.INF if at == Vector3.ZERO else at


func _resolve() -> void:
	_paths.clear()
	var ground := Callable(self, "_surface")
	var place := Callable(self, "_place")
	for s in _shots:
		var path := CinematicPath.resolve(s, ground, place, Vector3.INF, Transform3D.IDENTITY, 55.0)
		if not path.unresolved.is_empty():
			Log.warn("TitleVista", "%s: cannot place %s" % [str((s as Dictionary).get("id", "?")), ", ".join(path.unresolved)])
		_paths.append(path if path.is_playable() else null)


func path_of(i: int) -> CinematicPath:
	return _paths[i] if i >= 0 and i < _paths.size() else null


## The shot after `i` that can be shown, round the list.
func _next(i: int) -> int:
	for step in range(1, _shots.size() + 1):
		var j := (i + step) % _shots.size()
		if path_of(j) != null:
			return j
	return -1


## Where a shot needs the country: where its camera starts and what it looks at.
func need_of(i: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var path := path_of(i)
	if path == null:
		return out
	out.append(path.position_at(0.0))
	out.append(path.position_at(1.0))
	for p in path.looks:
		out.append(p)
	return out


func _cells_ready(i: int) -> bool:
	var streamer := world.streamer if world != null else null
	if streamer == null:
		return true
	for p in need_of(i):
		if not streamer.is_loaded_around(p):
			return false
	return true


## Goes to shot `i` under the dark: its hour, its weather and its region's light, the camera at its
## first frame, and the streamer asked for this shot and the next.
func _enter(i: int) -> void:
	index = i
	_t = 0.0
	var shot: Dictionary = _shots[i]
	var path := path_of(i)
	if shot.has("time"):
		WorldClock.time_hours = float(shot["time"])
	var region := str(shot.get("region", ""))
	if region.is_empty() and path != null and world.provider != null:
		var at := path.position_at(0.0)
		region = world.provider.nearest_region_id_at(at.x, at.z)
	var atm := world.atmosphere
	if atm != null and not region.is_empty():
		atm.call("set_region", region, true)
		if shot.has("weather"):
			atm.call("force_weather", str(shot["weather"]), true)
	if world.water != null and not region.is_empty():
		world.water.set_region_look(region)
	_pose(i, 0.0)
	var ahead: Array = []
	for p in need_of(i):
		ahead.append(p)
	for p in need_of(_next(i)):
		ahead.append(p)
	if world.streamer != null:
		world.streamer.set_also_around(ahead)
		world.streamer.refresh()


func _pose(i: int, t: float) -> void:
	var path := path_of(i)
	if path == null or camera == null:
		return
	var shot: Dictionary = _shots[i]
	var duration := maxf(float(shot.get("duration", 10.0)), 0.1)
	var u := clampf(t / duration, 0.0, 1.0)
	if shot.has("time_to"):
		WorldClock.time_hours = lerpf(float(shot.get("time", WorldClock.time_hours)), float(shot["time_to"]), u)
	var tf := path.pose(u)
	var lowest := _surface(tf.origin.x, tf.origin.z) + CLEARANCE
	if tf.origin.y < lowest:
		tf.origin.y = lowest
	camera.global_transform = tf
	camera.fov = path.fov_at(u)


func _show(i: int, ready: bool) -> void:
	var id := str((_shots[i] as Dictionary).get("id", ""))
	shown.append({"index": i, "id": id, "cells_ready": ready, "at_ms": Time.get_ticks_msec()})
	if not ready:
		Log.warn("TitleVista", "%s shown before its country had all come" % id)
	shot_started.emit(i, id)


func _fade(item: CanvasItem, to: float, seconds: float) -> void:
	if item == null or not is_instance_valid(item):
		return
	var tw := item.create_tween()
	tw.tween_property(item, "modulate:a", to, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# --- going ------------------------------------------------------------------------------------------

## Ends the vista: the chart comes back, the world and everything it streamed go, and the clock is
## given back. Safe to call more than once, and it is what leaving the title does.
func stop() -> void:
	if phase == Phase.GONE:
		return
	var was_showing := is_showing()
	phase = Phase.GONE
	if chart != null and is_instance_valid(chart):
		chart.modulate.a = 1.0
	if dip != null and is_instance_valid(dip):
		dip.modulate.a = 1.0
	if world != null and is_instance_valid(world):
		world.queue_free()
	world = null
	camera = null
	_give_clock_back()
	if was_showing:
		showing_changed.emit(false)


func _give_clock_back() -> void:
	if _clock_saved.is_empty():
		return
	WorldClock.time_hours = float(_clock_saved["time"])
	WorldClock.day = int(_clock_saved["day"])
	WorldClock.running = bool(_clock_saved["running"])
	_clock_saved = {}


func _exit_tree() -> void:
	# the scene the menu changes to must not meet the title's world: it goes with the title
	phase = Phase.GONE
	_give_clock_back()
