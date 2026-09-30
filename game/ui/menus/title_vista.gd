class_name TitleVista
extends Node
## The country behind the title's menu: held, slowly moving shots of the world, each at its own hour
## and weather, dipped to dark between them, round and round (`core:cinematic/title`).
##
## The menu is drawn and takes input before any of this starts. The world's scene is read on a worker
## thread, and the world is stood up a step a frame (`World.stand_up_in_steps`, its terrain read on
## worker threads too), without a body, without the game's services and without telling the game it
## has entered a region (`World.vista`), so nothing the title shows reaches a new game, a load or a
## continue. Until the first shot's country is in, nothing 3D is drawn at all (`Viewport.disable_3d`):
## the chart drifts and the menu answers at the speed it always did, instead of standing still on
## the chart while the world stood up behind it in one go (TRIAGE item 24).
##
## Its own camera leads the streamer, and each shot asks for what its camera will see along its
## whole path (ShotSight), with the next shot's opening beside it; a shot is never shown before the
## cells its opening sees have arrived, and the one before holds its last frame under the dip, at
## most NEXT_WAIT_CAP_S, while they come. While the chart or the dip covers the screen the streamer
## hurries; while a shot is watched it builds a few milliseconds a frame. The first shot fades in over
## the drawn chart, so the menu is never waiting for the country.
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
## From asking for the world to the first shot shown, however the time goes (the world standing up,
## its cells, the first frames that draw it), at most this long; then the vista is given up for
## this visit and the chart stays (`first_show_cap_s`).
const FIRST_SHOW_CAP_S := 90.0
## One frame this long while the first shot's country is first drawn under the chart (Phase.FIRST,
## `World.warm_layers`) -- a machine compiling every shader from source on its first launch, or one
## that cannot draw the world at all -- gives the vista up at once: the next frames would cost the
## same, and the menu is worth more than the picture (`long_frame_s`). The world standing up before
## it is paced and read on threads, and has its one known long frame (the provider's maps, 2.4 s of
## CPU on the software renderer here): the whole wait's cap covers that.
const LONG_FRAME_S := 4.0
## A shot holds on its last frame at most this long for the next one's cells, then the next is shown.
const NEXT_WAIT_CAP_S := 8.0
## Frames drawn at a new place, under the dark, before the dip lifts: Terrain3D's clipmap re-centres.
const SETTLE_FRAMES := 3
## What the first frames of 3D draw: one more of the world's layers a frame (World.warm_layers).
## Frames drawn with every layer up before the first shot fades in over the chart.
const FIRST_SETTLE_FRAMES := 2
const REVEAL_S := 2.2
const DIP_OUT_S := 1.0
const DIP_IN_S := 1.4
## The pictures keep the wall clock, as the opening's do (CinematicPlayer._real_delta): one long
## frame after quick ones is a hitch and moves them on no more than this; a long frame after a long
## one is the machine, and counts.
const MAX_STEP_S := 0.25
## A shot is shown once the cells its first OPENING_U of playing sees are in; the rest of what it
## will see comes while it plays, asked for when it begins.
const OPENING_U := 0.3
## The camera never goes nearer the ground than this, however the land is rebuilt.
const CLEARANCE := 2.0

enum Phase { IDLE, LOADING, FIRST, PLAY, DIP_OUT, WAIT_NEXT, DIP_IN, GONE }

## A headless run never stands a world up behind a menu unless a test asks for it here.
static var headless_allowed := false
## A software rasterizer (lavapipe, WARP: a machine with no graphics driver yet) keeps the chart: its
## first frames of the world are each a minute of compiling pipelines, with the menu frozen under
## them (2026-09-30: 44, 18, 79 and 30 s on lavapipe). A tool measuring it turns this on.
static var software_allowed := false
## Off, a shot asks only for the rings round its camera, as it did before ShotSight: for the title's
## film (`--no-sight`) to show the difference on one build.
static var sight_streaming := true

## Tests run the pictures faster; the waits for the country stay in real seconds.
var time_scale := 1.0
## The caps before the first shot (FIRST_SHOW_CAP_S, LONG_FRAME_S); a test or a tool may widen them.
var first_show_cap_s := FIRST_SHOW_CAP_S
var long_frame_s := LONG_FRAME_S
## Why the vista was given up before its first shot ("" while it was not): "cap", "long_frame".
var gave_up := ""

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
var _last_raw := 0.0
## When the world was asked for (µs), and the longest frame since, until the first shot is shown.
var _asked_us := 0
var _longest_s := 0.0
## Whether the caps before the first shot apply (from `_ready`; `scrub` turns them off).
var _capping := false
## What each shot's camera sees along its path (ShotSight.seen), worked out when it is first wanted.
var _sights: Dictionary = {}
## Whether the root viewport drew 3D before the vista stopped it, to give it back.
var _had_3d := true
var _holding_3d := false
## The fade running on each item, so a stop or a new fade takes over from it rather than fighting it.
var _tweens: Dictionary = {}


## Whether the Graphics tab has it on ("The country behind the title"; off on Low).
static func switched_on() -> bool:
	return bool(Settings.get_value("graphics", "title_vista", true))


## Whether the title should show the country here: a world to show, a display to draw it on, and the
## setting on.
static func wanted() -> bool:
	if DisplayServer.get_name() == "headless" and not headless_allowed:
		return false
	if not switched_on():
		return false
	if software_renderer() and not software_allowed:
		return false
	if not bool(WorldStatus.current().get("playable", false)):
		return false
	return ContentDB.has(DEF_ID)


## Whether the screen is drawn by the CPU (Forward+ or Mobile on a software rasterizer).
static func software_renderer() -> bool:
	return RenderingServer.get_rendering_device() != null \
			and RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_CPU


func _ready() -> void:
	add_to_group("title_vista")
	def = ContentDB.get_or_empty(DEF_ID)
	_shots = def.get("shots", [])
	if _shots.is_empty():
		phase = Phase.GONE
		return
	phase = Phase.LOADING
	_last_us = Time.get_ticks_usec()
	_asked_us = _last_us
	_capping = true
	# the world's scene is read while the menu's first frames are drawn
	ThreadedLoads.request(WORLD_SCENE)


func is_showing() -> bool:
	return phase in [Phase.PLAY, Phase.DIP_OUT, Phase.WAIT_NEXT, Phase.DIP_IN]


func current_shot_id() -> String:
	return str((_shots[index] as Dictionary).get("id", "")) if index >= 0 and index < _shots.size() else ""


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	# the pictures move by `dt`; the dips and the waits for the country keep real time (`raw`)
	var d := float(now - _last_us) / 1000000.0
	var raw := minf(d, maxf(MAX_STEP_S, _last_raw * 2.0))
	_last_raw = d
	var dt := raw * time_scale
	_last_us = now
	if phase != Phase.GONE and not switched_on():
		# switched off in the settings the title opened: the chart comes back at once
		stop()
		return
	if _before_first_shot() and _over_budget(now, d):
		return
	match phase:
		Phase.LOADING:
			_frames += 1
			if _frames >= START_DELAY_FRAMES and world == null \
					and ThreadedLoads.status(WORLD_SCENE) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				phase = Phase.IDLE
				_stand_world_up()
		Phase.FIRST:
			_phase_t += raw
			if _settle > 0:
				# what each warming frame cost (the frame before this one drew step _settle - 1)
				Log.info("TitleVista", "warm step %d drew in %.0f ms" % [_settle - 1, d * 1000.0])
			if _settle > 0 or _cells_ready(index):
				# the country is in: drawn from here, under the chart, so what the first frames cost
				# (every shader's first use, the cells' first draw) is paid before it shows, and a
				# layer a frame (`_warm`), so it is paid in several short frames and not one long one
				_warm(_settle)
				_settle += 1
			if _settle >= World.WARM_LAYERS.size() + FIRST_SETTLE_FRAMES:
				_show(index, true)
				_fade(chart, 0.0, REVEAL_S)
				_fade(dip, 0.0, REVEAL_S)
				phase = Phase.PLAY
				_hurry(false)
				showing_changed.emit(true)
			elif _settle == 0 and _phase_t > FIRST_SHOT_CAP_S:
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
				_hurry(true)
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
				_hurry(false)


## Until the first shot is shown: the world asked for, standing up, its cells coming, the first
## frames drawn under the chart.
## (Not a vista held still by `scrub`.)
func _before_first_shot() -> bool:
	return _capping and shown.is_empty() and phase in [Phase.LOADING, Phase.IDLE, Phase.FIRST]


## The safety net before the first shot (docs/FIRST_LAUNCH.md: a first launch froze behind the
## title). One frame of `frame_s` longer than `long_frame_s` while it warms (Phase.FIRST), or more
## than `first_show_cap_s` since the world was asked for, and the vista is given up with a warning: the world goes, the chart stays drawn and the menu
## goes on answering. True when it gave up.
func _over_budget(now_us: int, frame_s: float) -> bool:
	_longest_s = maxf(_longest_s, frame_s)
	var why := ""
	if frame_s > long_frame_s and phase == Phase.FIRST:
		why = "long_frame"
		Log.warn("TitleVista", "one frame took %.1f s while the country stood up behind the title (%s); the chart stays" % [frame_s, _phase_name()])
	elif float(now_us - _asked_us) / 1000000.0 > first_show_cap_s:
		why = "cap"
		Log.warn("TitleVista", "the first shot was not up %.0f s after the world was asked for (%s, longest frame %.1f s); the chart stays" % [first_show_cap_s, _phase_name(), _longest_s])
	if why.is_empty():
		return false
	stop()
	gave_up = why
	return true


func _phase_name() -> String:
	return str(Phase.keys()[phase]).to_lower()


# --- the world --------------------------------------------------------------------------------------

func _stand_world_up() -> void:
	var packed := ThreadedLoads.take(WORLD_SCENE) as PackedScene
	if packed == null:
		packed = load(WORLD_SCENE) as PackedScene
	if packed == null or phase == Phase.GONE:
		stop()
		return
	_clock_saved = {"time": WorldClock.time_hours, "day": WorldClock.day, "running": WorldClock.running}
	WorldClock.running = false
	var w := packed.instantiate() as World
	w.name = "TitleWorld"
	w.vista = true
	# a step a frame, so the chart and the menu go on being drawn while it stands up
	w.stand_up_in_steps = true
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
	# moved once per drawn frame, so it is not smeared between physics ticks (DECISIONS 2026-09-23)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	w.add_child(camera)
	var first_place := _first_place()
	if not first_place.is_empty():
		w.spawn_place = first_place
		# where it will first look from, so what the world stands up first (the cells round its eye,
		# the towns there) is what the first shot shows, not the middle of the map
		var xz := PlaceRef.xz(first_place)
		if xz != Vector2.INF:
			camera.position = Vector3(xz.x, 120.0, xz.y)
	world = w
	# nothing 3D is drawn until the first shot's country is in: under the opaque chart it was all
	# cost and no picture, and it held every frame of the menu to the world's
	_draw_3d(false)
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
	_hurry(true)
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


## Where a shot needs the full-detail ring: where its camera starts and ends. What it looks at is
## in its sight (`sight_of`), at the detail its distance deserves.
func need_of(i: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var path := path_of(i)
	if path == null:
		return out
	out.append(path.position_at(0.0))
	out.append(path.position_at(1.0))
	return out


## The cells shot `i`'s camera sees along its path (ShotSight.seen), worked out once.
func sight_of(i: int) -> Dictionary:
	if _sights.has(i):
		return _sights[i]
	var path := path_of(i)
	var streamer := world.streamer if world != null else null
	var seen := {}
	if path != null and streamer != null:
		var t0 := Time.get_ticks_usec()
		seen = ShotSight.seen(path, streamer, Callable(self, "_surface"), 0.0, 1.0, _aspect(), _reach(streamer))
		Log.info("TitleVista", "%s sees %d cells (%.0f ms)" % [path.shot_id, seen.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	_sights[i] = seen
	return seen


func _aspect() -> float:
	var r := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16.0, 9.0)
	return r.x / maxf(r.y, 1.0)


## How far a shot's cells are wanted: as far as the far ring's trees are drawn at this view range.
func _reach(streamer: WorldStreamer) -> float:
	return ShotSight.REACH_M * maxf(streamer.view_range, 0.5)


## Whether shot `i` may be shown: the ring round where its camera starts and ends, and every cell its
## opening sees.
func _cells_ready(i: int) -> bool:
	var streamer := world.streamer if world != null else null
	if streamer == null:
		return true
	for p in need_of(i):
		if not streamer.is_loaded_around(p):
			return false
	# the towns where it opens, raised a piece at a time behind the menu (WorldDoors)
	var need := need_of(i)
	if not need.is_empty():
		var towns := WorldDoors.towns_near(get_tree(), need[0], ShotSight.TOWNS_M)
		if towns.x < towns.y:
			return false
	if not sight_streaming:
		return true
	# the near ground its opening sees; the far ring's cells come while it plays
	var opening := streamer.standing_of(ShotSight.near_only(ShotSight.rings(sight_of(i), OPENING_U)))
	return opening.x >= opening.y


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
	var next := _next(i)
	for p in need_of(next):
		ahead.append(p)
	if world.streamer != null:
		# all this shot will see, and what the next one opens on, so it is in by the dip
		world.streamer.also_cells = ShotSight.merged(ShotSight.rings(sight_of(i)),
				ShotSight.rings(sight_of(next), OPENING_U)) if sight_streaming else {}
		world.streamer.set_also_around(ahead)


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


func _show(i: int, came: bool) -> void:
	var id := str((_shots[i] as Dictionary).get("id", ""))
	shown.append({"index": i, "id": id, "cells_ready": came, "at_ms": Time.get_ticks_msec()})
	if not came:
		Log.warn("TitleVista", "%s shown before its country had all come" % id)
	shot_started.emit(i, id)


## The `step`th frame of 3D: on it, the ground and the sky with the layers after it hidden; each
## frame after, one more layer.
func _warm(step: int) -> void:
	if world == null or not is_instance_valid(world):
		return
	if step == 0:
		_draw_3d(true)
	world.warm_layers(step)


## The streamer hurries while nothing it builds is watched (the chart or the dip covers the screen).
func _hurry(on: bool) -> void:
	if world != null and is_instance_valid(world) and world.streamer != null:
		world.streamer.hurry = on


## Whether the screen draws the 3D world; given back as it was when the vista stops.
func _draw_3d(on: bool) -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if not on and not _holding_3d:
		_had_3d = not vp.disable_3d
		_holding_3d = true
		vp.disable_3d = true
	elif on and _holding_3d:
		_holding_3d = false
		vp.disable_3d = not _had_3d


func _fade(item: CanvasItem, to: float, seconds: float) -> void:
	if item == null or not is_instance_valid(item):
		return
	_stop_fade(item)
	var tw := item.create_tween()
	tw.tween_property(item, "modulate:a", to, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens[item.get_instance_id()] = tw


func _stop_fade(item: CanvasItem) -> void:
	var old: Variant = _tweens.get(item.get_instance_id(), null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	_tweens.erase(item.get_instance_id())


## Poses the vista at shot `i`, `u` of the way through it, for a still: its hour, weather and camera,
## the streamer asked for it, the chart and the dip out of the way, and the shots no longer running
## on their own. The film (tools_gd/title_film.gd) waits for `cells_in()` and a few frames, then
## takes the picture, however slowly the machine draws.
func scrub(i: int, u: float) -> void:
	if world == null or path_of(i) == null:
		return
	if phase != Phase.GONE:
		phase = Phase.IDLE
	# a film's stills take as long as the machine needs: the caps before the first shot are off
	_capping = false
	_draw_3d(true)
	for item: CanvasItem in [dip, chart]:
		if item != null and is_instance_valid(item):
			_stop_fade(item)
			item.modulate.a = 0.0
	_enter(i)
	_t = u * float((_shots[i] as Dictionary).get("duration", 10.0))
	_pose(i, _t)


## Whether the current shot's country has all come.
func cells_in() -> bool:
	return index >= 0 and _cells_ready(index)


## What the current shot is waiting for, in words, for a log or a film's report.
func waiting_for() -> String:
	var streamer := world.streamer if world != null else null
	if streamer == null or index < 0:
		return "nothing"
	var missing: Array[String] = []
	var opening := ShotSight.rings(sight_of(index), OPENING_U)
	for c: Vector2i in opening:
		if not streamer.is_loaded(c):
			missing.append("%d_%d %s" % [c.x, c.y, streamer.cell_state(c)])
	for p in need_of(index):
		for c in streamer.missing_around(p):
			missing.append("%d_%d %s (round the camera)" % [c.x, c.y, streamer.cell_state(c)])
	var q := streamer.queue()
	return "%d of the %d cells its opening sees are in%s; %d loaded, %d asked for" % [
			opening.size() - missing.size(), opening.size(),
			" (missing: %s)" % ", ".join(missing.slice(0, 8)) if not missing.is_empty() else "",
			int(q["loaded"]), int(q["pending"])]


# --- going ------------------------------------------------------------------------------------------

## Ends the vista: the chart comes back, the world and everything it streamed go, and the clock is
## given back. Safe to call more than once, and it is what leaving the title does.
func stop() -> void:
	if phase == Phase.GONE:
		return
	var was_showing := is_showing()
	phase = Phase.GONE
	_draw_3d(true)
	for item: CanvasItem in [chart, dip]:
		if item != null and is_instance_valid(item):
			_stop_fade(item)
			item.modulate.a = 1.0
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
	_draw_3d(true)
	_give_clock_back()
	# a scene read on a thread and never taken is taken here, so it is not left in the loader
	if world == null:
		ThreadedLoads.forget(WORLD_SCENE)
