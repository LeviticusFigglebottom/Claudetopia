class_name CinematicPlayer
extends Node
## Plays a `core:cinematic/*` definition in the world it stands in (DESIGN §5.1a).
##
## It borrows what it needs and gives every piece of it back: the current camera, the streamer's
## target (and its habit of telling the game which region the player is in, which a camera flying
## over five of them must not do), the clock, the sky, two audio buses, the HUD, the toasts and
## the player's input. `_save_state` writes down how each was; `_restore` puts it back, and it is
## the same code whether the cinematic was watched to the end or skipped, so the two cannot come
## apart. The world is never paused: the villages it flies over go on with their day.
##
## Each shot is resolved against the live ground when the cinematic starts (`CinematicPath`), the
## streamer follows the camera, and the next shot's places are loaded while this one plays. A shot
## whose cells have not arrived is not shown: the last frame holds, then the picture goes to black
## with a caption and the music waits, and the shot plays when the country is there.
##
## Three ways to use it:
##   OPENING  after the Naming, from `GameServices.begin_new_game` via `play_opening`; control is
##            handed back at the place the story opens, facing where the definition says.
##   REPLAY   from the pause menu via `replay`; everything, the player included, goes back to
##            exactly where it was.
##   SCRUB    for the capture runner: `scrub(shot, u)` poses the camera, the sky, the letterbox, the
##            subtitle and the title for one moment, so the frames on disk are this code's frames.

signal shot_started(index: int, shot_id: String)
## Control is back and everything the cinematic borrowed has been returned.
signal finished(skipped: bool)

enum Mode { OPENING, REPLAY, SCRUB }
enum Phase { STARTING, HOLD, PLAY, SKIPPING, HANDOVER, DONE }

const GROUP := "cinematic"
const SKIP_HOLD_SECONDS := 1.0
const PROMPT_LINGER_SECONDS := 2.5
## A wait for the country shorter than this shows nothing and stops nothing: the last frame
## simply holds a moment longer.
const HOLD_GRACE_SECONDS := 0.5
const SETTLE_FRAMES := 4
const FADE_IN_SECONDS := 1.6
const SKIP_FADE_SECONDS := 0.45
const BARS_SECONDS := 1.4
const HANDOVER_SECONDS := 1.3
## However the land is rebuilt, the camera is never nearer the ground than this.
const CLEARANCE := 1.5
## The world under the music: the ambience stays, lower; the foley of whatever the camera passes
## is kept well back, because a stranger's footsteps are not part of the story being told.
const DUCK_DB := {"Ambience": -10.0, "SFX": -24.0}
## Where the camera rig rests when nobody has moved it (CameraRig's own default).
const PLAYER_PITCH := -0.18
const DEFAULT_HOLD_LINE := "The Warden waits for you to catch her up."

## A headless run (the unit suite, the journey, the smoke run) never plays one unless a test
## asks for it here: a cutscene taking the camera for ninety seconds is not something a
## scripted run expects.
static var headless_allowed := false

var def: Dictionary = {}
var mode := Mode.OPENING
## Tests run the pictures faster; the waits for the country and a held key stay in real seconds.
var time_scale := 1.0
var skipped := false

var _world: World = null
var _player: Node3D = null
var _camera: Camera3D = null
var _overlay: CinematicOverlay = null
var _shots: Array = []
var _paths: Array = []
var _handover := -1
var _index := -1
var _t := 0.0
var _phase := Phase.STARTING
var _waited := 0.0
var _settle := 0
var _need: Array[Vector3] = []
var _held_music := false
var _curtain_target := 1.0
var _curtain_rate := 1.0
var _bars_target := 0.0
var _dissolve_total := 0.0
var _dissolve_left := 0.0
var _line_key := ""
var _title_up := false
var _held: Dictionary = {}
var _skip_held := 0.0
var _prompt_idle := 0.0
var _saved: Dictionary = {}
var _restored := false
var _handover_at := Vector3.ZERO
var _handover_yaw := 0.0
var _handover_rig_yaw := 0.0
var _handover_pitch := PLAYER_PITCH
var _player_name := ""
var _subtitles := true


# --- the ways in -----------------------------------------------------------------------------------

## Whether the cinematic `id` would play now: it exists, the player has not asked never to see it
## (Settings gameplay/play_opening, or `-- --no-opening`), there is a world with a body in it, and
## nothing else is playing one.
static func should_play(id: String) -> bool:
	if id.is_empty() or not ContentDB.has(id):
		return false
	if not bool(Settings.get_value("gameplay", "play_opening", true)):
		return false
	if OS.get_cmdline_user_args().has("--no-opening"):
		return false
	if DisplayServer.get_name() == "headless" and not headless_allowed:
		return false
	var world := World.instance
	if world == null or not world.is_world_ready or _player_of(world) == null:
		return false
	return world.get_tree().get_first_node_in_group(GROUP) == null


## The one call the new-game flow makes. Plays the cinematic `opening` (a `core:opening/*`
## definition) names, and returns once control is back; false when nothing was played.
static func play_opening(opening: Dictionary) -> bool:
	var id := str(opening.get("cinematic", ""))
	if not should_play(id):
		return false
	var world := World.instance
	var cin := CinematicPlayer.new()
	cin.name = "Opening"
	world.add_child(cin)
	cin.begin(world, _player_of(world), ContentDB.get_def(id), Mode.OPENING)
	await cin.finished
	return true


## The pause menu's "watch the opening again". Everything goes back as it was afterwards.
static func replay(id := "") -> CinematicPlayer:
	var cid := id if not id.is_empty() else opening_cinematic_id()
	var world := World.instance
	if cid.is_empty() or not ContentDB.has(cid) or world == null or not world.is_world_ready:
		return null
	if world.get_tree().get_first_node_in_group(GROUP) != null or _player_of(world) == null:
		return null
	var cin := CinematicPlayer.new()
	cin.name = "Replay"
	world.add_child(cin)
	cin.begin(world, _player_of(world), ContentDB.get_def(cid), Mode.REPLAY)
	return cin


static func opening_cinematic_id() -> String:
	return str(ContentDB.get_or_empty(GameServices.OPENING).get("cinematic", ""))


static func can_replay() -> bool:
	var id := opening_cinematic_id()
	var world := World.instance
	return not id.is_empty() and ContentDB.has(id) and world != null and world.is_world_ready \
			and _player_of(world) != null and world.get_tree().get_first_node_in_group(GROUP) == null


static func _player_of(world: World) -> Node3D:
	if world == null:
		return null
	for p in world.get_tree().get_nodes_in_group("player"):
		if p is Node3D and world.is_ancestor_of(p):
			return p as Node3D
	return null


## The gameplay camera's resting pose behind a body at `feet` facing `yaw`, from CameraRig's own
## numbers and with nothing in the way: what the tests and the capture runner compose the last
## key against when there is no rig to ask.
static func resting_camera(feet: Vector3, yaw: float, pitch := PLAYER_PITCH) -> Transform3D:
	var side := 1.0 if int(Settings.get_value("controls", "camera_side", 1)) >= 0 else -1.0
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var pivot := feet + Vector3(0.0, CameraRig.TP_HEIGHT, 0.0)
	var arm := Vector3(CameraRig.TP_SHOULDER * side, 0.12, CameraRig.TP_ARM_LENGTH)
	return Transform3D(basis, pivot + basis * arm)


# --- starting ----------------------------------------------------------------------------------------

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func begin(world: World, player: Node3D, definition: Dictionary, how: Mode) -> void:
	_world = world
	_player = player
	def = definition
	mode = how
	add_to_group(GROUP)
	_shots = CinematicDef.shots_of(def)
	_handover = CinematicDef.handover_index(def)
	_player_name = str(GameState.get_flag("player_name", ""))
	_subtitles = bool(Settings.get_value("gameplay", "subtitles", true))
	_save_state()
	_overlay = CinematicOverlay.new()
	_overlay.letterbox = float(def.get("letterbox", CinematicDef.DEFAULT_LETTERBOX))
	_overlay.text_scale = clampf(float(Settings.get_value("accessibility", "ui_scale", 1.0)), 0.8, 1.4)
	add_child(_overlay)
	_camera = Camera3D.new()
	_camera.name = "CinematicCamera"
	_camera.near = 0.25
	_camera.far = 12000.0
	add_child(_camera)
	_camera.make_current()
	_take_over()
	_decide_handover()
	_put_player_at_handover()
	# the rig's spring arm settles on the physics step: the hand-over shot's last key is the
	# gameplay camera as it will actually stand, not as it would stand with nothing in the way
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_resolve_all()
	if mode == Mode.SCRUB:
		_overlay.set_curtain(0.0)
		_overlay.set_bars(1.0)
		_phase = Phase.PLAY
		return
	_overlay.set_curtain(1.0)
	_curtain_target = 1.0
	_bars_target = 1.0
	if def.has("music"):
		Music.play_cue(str(def["music"]))
	_enter_shot(0)


func is_playing() -> bool:
	return _phase in [Phase.HOLD, Phase.PLAY, Phase.SKIPPING]


func current_shot() -> int:
	return _index


## Seconds into the current shot.
func shot_time() -> float:
	return _t


func phase_name() -> String:
	return Phase.keys()[_phase]


# --- what is borrowed, and giving it back ---------------------------------------------------------------

func _save_state() -> void:
	var streamer := _world.streamer if _world != null else null
	var atm := _atmosphere()
	var rig: Node = _player.get("camera_rig") if _player != null else null
	var buses := {}
	for bus: String in DUCK_DB:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			buses[bus] = [AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)]
	_saved = {
		"target": streamer.target if streamer != null else null,
		"report_regions": streamer.report_regions if streamer != null else true,
		"also_around": streamer.also_around.duplicate() if streamer != null else [],
		"time": WorldClock.time_hours, "day": WorldClock.day, "running": WorldClock.running,
		"sky": atm.call("to_save") if atm != null else {},
		"sky_region": str(atm.get("region_id")) if atm != null else "",
		"hud": UI.hud_visible, "toasts": UI.toast_layer.visible,
		"buses": buses,
		"camera": get_viewport().get_camera_3d(),
		"mouse": Input.mouse_mode,
		"input": bool(_player.get("input_enabled")) if _player != null and _player.get("input_enabled") != null else true,
		"position": _player.global_position if _player != null else Vector3.ZERO,
		"rotation": _player.rotation.y if _player != null else 0.0,
		"yaw": float(rig.get("yaw")) if rig != null else 0.0,
		"pitch": float(rig.get("pitch")) if rig != null else PLAYER_PITCH,
		"ambience": str(Ambience.get("region_id")),
		"terrain_camera": _world.terrain_node.call("get_camera") if _world != null and _world.terrain_node != null else null,
		"body_physics": _player.is_physics_processing() if _player != null else true,
	}


func _take_over() -> void:
	UI.close_all()
	if _player != null and _player.has_method("set_input_enabled"):
		_player.call("set_input_enabled", false)
	UI.hud_visible = false
	UI.toast_layer.visible = false
	if mode != Mode.SCRUB:
		var buses: Dictionary = _saved.get("buses", {})
		for bus: String in buses:
			var i := AudioServer.get_bus_index(bus)
			AudioServer.set_bus_volume_db(i, float(buses[bus][0]) + float(DUCK_DB[bus]))
	var streamer := _world.streamer
	if streamer != null:
		streamer.report_regions = false
		streamer.target = _camera
	# Terrain3D centres its clipmap -- its detail, its distance blending and its collision -- on
	# one camera it was given, and the world gave it the fly camera. A shot four kilometres away
	# would be drawn from the coarse outer rings, so the terrain follows this camera while it plays;
	# and the body, whose ground may go with it, is held still until it is handed back.
	if _world.terrain_node != null:
		_world.terrain_node.call("set_camera", _camera)
	if _player != null:
		_player.set_physics_process(false)
	WorldClock.running = false


## Where control comes back. The opening decides it, and a scrub shows the opening's; a replay
## leaves the body where it was standing.
func _decide_handover() -> void:
	if mode == Mode.REPLAY or _player == null:
		_handover_at = _saved.get("position", Vector3.ZERO)
		_handover_yaw = float(_saved.get("rotation", 0.0))
		_handover_rig_yaw = float(_saved.get("yaw", _handover_yaw))
		_handover_pitch = float(_saved.get("pitch", PLAYER_PITCH))
		return
	var feet := _player.global_position
	var provider := _world.provider
	if provider != null:
		feet.y = provider.get_height(feet.x, feet.z)
	_handover_at = feet
	_handover_pitch = PLAYER_PITCH
	var facing: Variant = (def.get("handover", {}) as Dictionary).get("facing", null)
	_handover_yaw = float(_saved.get("rotation", 0.0))
	if facing is Dictionary:
		var f: Dictionary = facing
		if f.has("place"):
			var at := _place(str(f["place"]))
			if at != Vector3.INF:
				var d := at - feet
				if Vector2(d.x, d.z).length() > 0.5:
					_handover_yaw = atan2(-d.x, -d.z)
		elif f.has("bearing"):
			_handover_yaw = -deg_to_rad(float(f["bearing"]))
	# the body and its camera face the same way, as Player.respawn sets them
	_handover_rig_yaw = _handover_yaw


## The body stands where it will be handed back, facing that way, from the first frame: it is
## never seen until the last shot, and the last shot has to know where the gameplay camera is.
func _put_player_at_handover() -> void:
	if _player == null:
		return
	_player.global_position = _handover_at
	if "velocity" in _player:
		_player.set("velocity", Vector3.ZERO)
	_player.rotation.y = _handover_yaw
	var rig: Node = _player.get("camera_rig")
	if rig != null:
		rig.set("yaw", _handover_rig_yaw)
		rig.set("pitch", _handover_pitch)


func _restore() -> void:
	if _restored:
		return
	_restored = true
	_restore_world()
	_restore_globals()


## What belongs to the world: the streamer, the sky, the body and its camera.
func _restore_world() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var streamer := _world.streamer
	if streamer != null:
		var target: Variant = _saved.get("target", null)
		streamer.target = target if target is Node3D and is_instance_valid(target) else _player
		streamer.report_regions = bool(_saved.get("report_regions", true))
		streamer.set_also_around(_saved.get("also_around", []))
	var terrain_camera: Variant = _saved.get("terrain_camera", null)
	if _world.terrain_node != null and terrain_camera is Camera3D and is_instance_valid(terrain_camera):
		_world.terrain_node.call("set_camera", terrain_camera)
	var atm := _atmosphere()
	if atm != null:
		atm.call("from_save", _saved.get("sky", {}))
		var home := str(_saved.get("sky_region", ""))
		if home.is_empty():
			home = GameState.current_region_id
		atm.call("set_region", home, true)
		var weather := str((def.get("handover", {}) as Dictionary).get("weather", ""))
		if mode == Mode.OPENING and not weather.is_empty():
			atm.call("force_weather", weather, true)
	if _player != null and is_instance_valid(_player):
		_put_player_at_handover()
		_player.set_physics_process(bool(_saved.get("body_physics", true)))
		if _player.has_method("set_input_enabled"):
			_player.call("set_input_enabled", bool(_saved.get("input", true)))
		var rig: Node = _player.get("camera_rig")
		var cam: Camera3D = rig.get("camera") if rig != null else null
		if cam != null:
			cam.make_current()
	var before: Variant = _saved.get("camera", null)
	if (_player == null or not is_instance_valid(_player)) and before is Camera3D and is_instance_valid(before):
		(before as Camera3D).make_current()


## What belongs to the autoloads, which outlive the world: put back even if the world is torn down
## halfway through, or the next scene inherits a stopped clock and a quiet mix.
func _restore_globals() -> void:
	var handover_hour: float = float((def.get("handover", {}) as Dictionary).get("time", _saved.get("time", WorldClock.time_hours)))
	if mode == Mode.OPENING:
		WorldClock.set_time(handover_hour)
	else:
		WorldClock.set_time(float(_saved.get("time", WorldClock.time_hours)), int(_saved.get("day", WorldClock.day)))
	WorldClock.running = bool(_saved.get("running", true))
	var buses: Dictionary = _saved.get("buses", {})
	for bus: String in buses:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, float(buses[bus][0]))
			AudioServer.set_bus_mute(i, bool(buses[bus][1]))
	Music.end_cue()
	Ambience.call("set_region", str(_saved.get("ambience", GameState.current_region_id)))
	UI.toast_layer.visible = bool(_saved.get("toasts", true))
	UI.hud_visible = bool(_saved.get("hud", true))
	var hud := UI.hud()
	if hud != null and hud.has_method("come_up"):
		hud.call("come_up")
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = int(_saved.get("mouse", Input.MOUSE_MODE_CAPTURED)) as Input.MouseMode
	# the screen fade belongs to the menus, and a world handed over under it would be invisible
	if UI.is_faded_out():
		UI.fade_from_black(0.5)


func _exit_tree() -> void:
	# torn down mid-play (a test dropping its world, the game quitting): the autoloads must not
	# keep what was lent to them
	if not _restored and not _saved.is_empty():
		_restored = true
		_restore_globals()


## Gives back everything a scrub borrowed; the capture runner calls it when it is done.
func release() -> void:
	_restore()
	_phase = Phase.DONE
	queue_free()


# --- resolving the shots --------------------------------------------------------------------------------

func _surface(x: float, z: float) -> float:
	var provider := _world.provider
	if provider == null:
		return 0.0
	return maxf(provider.get_height(x, z), provider.water_level_at(x, z))


func _place(id: String) -> Vector3:
	if id.is_empty() or not ContentDB.has(id):
		return Vector3.INF
	var at := _world.place_position(id)
	return Vector3.INF if at == Vector3.ZERO else at


func _player_camera() -> Transform3D:
	var rig: Node = _player.get("camera_rig") if _player != null else null
	var cam: Camera3D = rig.get("camera") if rig != null else null
	if cam != null and cam.is_inside_tree():
		return cam.global_transform
	return resting_camera(_handover_at, _handover_yaw, _handover_pitch)


func _player_fov() -> float:
	var rig: Node = _player.get("camera_rig") if _player != null else null
	var cam: Camera3D = rig.get("camera") if rig != null else null
	return cam.fov if cam != null else float(Settings.get_value("video", "fov", 75.0))


func _resolve_all() -> void:
	_paths.clear()
	var ground := Callable(self, "_surface")
	var place := Callable(self, "_place")
	var pc := _player_camera()
	var fov := _player_fov()
	for shot in _shots:
		var s: Dictionary = shot
		if bool(s.get("black", false)):
			_paths.append(null)
			continue
		var path := CinematicPath.resolve(s, ground, place, _handover_at, pc, fov)
		if not path.unresolved.is_empty():
			Log.warn("Cinematic", "%s: cannot place %s" % [def.get("id", "?"), ", ".join(path.unresolved)])
		_paths.append(path if path.is_playable() else null)


func path_of(index: int) -> CinematicPath:
	return _paths[index] if index >= 0 and index < _paths.size() else null


## The picture a shot opens on: its own first frame, or for a black shot the next picture's, so the
## country for it loads in the dark.
func _picture_for(index: int) -> int:
	for i in range(index, _shots.size()):
		if path_of(i) != null:
			return i
	return -1


# --- shots --------------------------------------------------------------------------------------------

func _enter_shot(index: int) -> void:
	_index = index
	_t = 0.0
	_line_key = ""
	_dissolve_left = 0.0
	var shot: Dictionary = _shots[index]
	var picture := _picture_for(index)
	_need.clear()
	if picture >= 0:
		var path := path_of(picture)
		_set_conditions(picture, 0.0)
		_pose(path, 0.0, picture == _handover)
		_need.append(path.position_at(0.0))
		for p in path.looks:
			_need.append(p)
	_stream_ahead(picture)
	_phase = Phase.HOLD
	_waited = 0.0
	_settle = SETTLE_FRAMES
	shot_started.emit(index, str(shot.get("id", "")))


## Loads what the current picture looks at and where the next one starts while this one plays.
func _stream_ahead(picture: int) -> void:
	var streamer := _world.streamer
	if streamer == null:
		return
	var points: Array = []
	var path := path_of(picture)
	if path != null:
		for p in path.looks:
			points.append(p)
	var next := _picture_for(picture + 1) if picture >= 0 else -1
	var ahead := path_of(next)
	if ahead != null:
		points.append(ahead.position_at(0.0))
		for p in ahead.looks:
			points.append(p)
	streamer.set_also_around(points)


func _cells_ready() -> bool:
	var streamer := _world.streamer
	if streamer == null:
		return true
	for p in _need:
		if not streamer.is_loaded_around(p):
			return false
	return true


## The time, the weather and the light of the place a shot is in.
func _set_conditions(index: int, u: float) -> void:
	var shot: Dictionary = _shots[index]
	if shot.has("time"):
		var from := float(shot["time"])
		WorldClock.time_hours = lerpf(from, float(shot.get("time_to", from)), clampf(u, 0.0, 1.0))
	if u > 0.0:
		return
	var atm := _atmosphere()
	var region := str(shot.get("region", ""))
	var path := path_of(index)
	if region.is_empty() and path != null and _world.provider != null:
		var at := path.position_at(0.0)
		region = _world.provider.nearest_region_id_at(at.x, at.z)
	if atm != null and not region.is_empty():
		atm.call("set_region", region, true)
		if shot.has("weather"):
			atm.call("force_weather", str(shot["weather"]), true)
	if not region.is_empty():
		Ambience.call("set_region", region)


func _pose(path: CinematicPath, u: float, handover := false) -> void:
	if path == null:
		return
	var tf := path.pose(u)
	# the path is tested clear of the ground, but the ground is rebuilt; the last stretch of the
	# hand-over is the gameplay camera arriving, which answers to its own spring arm
	if not (handover and path.arriving(u)):
		var lowest := _highest_ground(tf.origin) + CLEARANCE
		if tf.origin.y < lowest:
			tf.origin.y = lowest
	_camera.global_transform = tf
	_camera.fov = path.fov_at(u)


func _highest_ground(p: Vector3) -> float:
	var best := _surface(p.x, p.z)
	for i in 6:
		var a := TAU * float(i) / 6.0
		best = maxf(best, _surface(p.x + cos(a) * 2.5, p.z + sin(a) * 2.5))
	return best


# --- the frame loop ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _phase == Phase.DONE or _phase == Phase.STARTING or mode == Mode.SCRUB:
		return
	var dt := delta * time_scale
	_update_skip(delta)
	match _phase:
		Phase.HOLD:
			_tick_hold(delta)
		Phase.PLAY:
			_tick_play(dt)
		Phase.SKIPPING:
			if _overlay.curtain() >= 0.999:
				_arrive_at_the_end()
		Phase.HANDOVER:
			if _overlay.curtain() <= 0.001 and _overlay.bars() <= 0.001:
				_finish()
	_animate(dt)


func _animate(dt: float) -> void:
	var c := move_toward(_overlay.curtain(), _curtain_target, dt * _curtain_rate)
	_overlay.set_curtain(c)
	var b := move_toward(_overlay.bars(), _bars_target, dt / (BARS_SECONDS if _bars_target > 0.5 else HANDOVER_SECONDS))
	if not is_equal_approx(b, _overlay.bars()):
		_overlay.set_bars(b)
	if _dissolve_left > 0.0 and _phase == Phase.PLAY:
		_dissolve_left = maxf(0.0, _dissolve_left - dt)
		var a := _dissolve_left / maxf(_dissolve_total, 0.001)
		# eased, so the new shot arrives the way a painted wash dries rather than at a constant rate
		_overlay.set_freeze_alpha(a * a * (3.0 - 2.0 * a))
	if _overlay.caption_shown():
		_overlay.set_caption_progress(_progress_text())


func _fade_curtain(to: float, seconds: float) -> void:
	_curtain_target = to
	_curtain_rate = 1.0 / maxf(seconds, 0.01)


func _tick_hold(delta: float) -> void:
	_waited += delta
	var shot: Dictionary = _shots[_index]
	var black := bool(shot.get("black", false))
	if black or _cells_ready():
		if _settle > 0:
			_settle -= 1
			return
		_reveal(black)
		return
	if _waited > HOLD_GRACE_SECONDS and not _overlay.caption_shown():
		# the country is late: hold on black with a caption, and the music waits with the pictures
		_fade_curtain(1.0, 0.35)
		_overlay.caption_in(str(def.get("hold_line", DEFAULT_HOLD_LINE)))
		Music.pause_cue(true)
		_held_music = true


func _reveal(black: bool) -> void:
	_overlay.caption_out()
	if _held_music:
		Music.pause_cue(false)
		_held_music = false
	var dissolve := CinematicDef.dissolve_into(def, _index)
	if black:
		_fade_curtain(1.0, 0.5)
	elif _overlay.is_frozen() and _overlay.curtain() <= 0.01 and dissolve > 0.0:
		_dissolve_total = dissolve
		_dissolve_left = dissolve
	else:
		_overlay.clear_freeze()
		_fade_curtain(0.0, FADE_IN_SECONDS)
	_phase = Phase.PLAY


func _tick_play(dt: float) -> void:
	_t += dt
	var shot: Dictionary = _shots[_index]
	var duration := float(shot.get("duration", 1.0))
	var u := clampf(_t / duration, 0.0, 1.0)
	var path := path_of(_index)
	if path != null:
		_pose(path, u, _index == _handover)
		_set_conditions(_index, maxf(u, 0.0001))
	_update_words(shot)
	if _t >= duration:
		_end_shot()


func _end_shot() -> void:
	if _index == _handover:
		_hand_over()
		return
	var next := _index + 1
	if CinematicDef.dissolve_into(def, next) > 0.0:
		var still := _grab_frame()
		if still != null:
			_overlay.freeze(still)
	_enter_shot(next)


func _update_words(shot: Dictionary) -> void:
	var line := CinematicDef.line_at(shot, _t) if _subtitles else {}
	var key := "" if line.is_empty() else "%s@%s" % [shot.get("id", ""), str(line.get("at", 0.0))]
	if key != _line_key:
		_line_key = key
		if line.is_empty():
			_overlay.unsay()
		else:
			_overlay.say(str(line.get("speaker", def.get("speaker", ""))), CinematicDef.words(line, _player_name))
	var card: Dictionary = def.get("title_card", {})
	var inside := false
	if str(card.get("shot", "")) == str(shot.get("id", "")):
		var at := float(card.get("at", 0.0))
		inside = _t >= at and _t < at + float(card.get("for", 0.0))
	if inside and not _title_up:
		_title_up = true
		_overlay.title_in(str(card.get("title", "")), str(card.get("line", "")))
	elif not inside and _title_up:
		_title_up = false
		_overlay.title_out()


# --- skipping ------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if mode == Mode.SCRUB or _phase == Phase.DONE or _phase == Phase.HANDOVER:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		var id := _event_id(event)
		var wheel := event is InputEventMouseButton and (event as InputEventMouseButton).button_index in [
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
		if event.is_pressed() and not event.is_echo():
			_prompt_idle = 0.0
			if _phase in [Phase.HOLD, Phase.PLAY]:
				_overlay.prompt(true)
			if not wheel:
				_held[id] = true
		elif not event.is_pressed():
			_held.erase(id)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion or event is InputEventJoypadMotion:
		# the camera is not the player's yet
		get_viewport().set_input_as_handled()


static func _event_id(event: InputEvent) -> String:
	if event is InputEventKey:
		var k := event as InputEventKey
		return "k%d" % int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	if event is InputEventMouseButton:
		return "m%d" % int((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return "j%d_%d" % [event.device, int((event as InputEventJoypadButton).button_index)]
	return event.as_text()


func _update_skip(delta: float) -> void:
	if not (_phase in [Phase.HOLD, Phase.PLAY]):
		return
	if _held.is_empty():
		_skip_held = maxf(0.0, _skip_held - delta * 2.0)
		_prompt_idle += delta
		if _prompt_idle > PROMPT_LINGER_SECONDS and _overlay.prompt_shown():
			_overlay.prompt(false)
	else:
		_skip_held += delta
	_overlay.prompt_fill(_skip_held / SKIP_HOLD_SECONDS)
	if _skip_held >= SKIP_HOLD_SECONDS:
		skip()


## Goes to black, then to the last frame of the hand-over shot, and hands over from there: the
## same hand-over, and so the same end state, as watching it through.
func skip() -> void:
	if skipped or not (_phase in [Phase.HOLD, Phase.PLAY]) or mode == Mode.SCRUB:
		return
	skipped = true
	_phase = Phase.SKIPPING
	_held.clear()
	_skip_held = 0.0
	_overlay.prompt(false)
	_overlay.unsay()
	if _title_up:
		_title_up = false
		_overlay.title_out(0.3)
	if _held_music:
		_held_music = false
	Music.end_cue()
	_fade_curtain(1.0, SKIP_FADE_SECONDS)


func _arrive_at_the_end() -> void:
	_overlay.clear_freeze()
	_overlay.caption_out()
	_index = _handover
	var shot: Dictionary = _shots[_handover]
	_t = float(shot.get("duration", 1.0))
	var path := path_of(_handover)
	if path != null:
		_set_conditions(_handover, 0.0)
		_set_conditions(_handover, 1.0)
		_pose(path, 1.0, true)
		_need = [path.position_at(1.0)]
	_stream_ahead(-1)
	_phase = Phase.HOLD
	_waited = 0.0
	_settle = SETTLE_FRAMES


# --- handing over --------------------------------------------------------------------------------------

func _hand_over() -> void:
	_phase = Phase.HANDOVER
	_overlay.unsay()
	_overlay.prompt(false)
	_overlay.caption_out()
	if _title_up:
		_title_up = false
		_overlay.title_out(0.4)
	_bars_target = 0.0
	if _overlay.curtain() > 0.0:
		_fade_curtain(0.0, FADE_IN_SECONDS * 0.5)
	# control is back from this frame: the camera is already where play begins
	_restore()


func _finish() -> void:
	_phase = Phase.DONE
	set_process(false)
	set_process_input(false)
	finished.emit(skipped)
	queue_free()


# --- scrubbing, for the capture runner ------------------------------------------------------------------

## Poses everything for `u` (0..1) of shot `index`, as a player watching it would see that moment.
func scrub(index: int, u: float) -> void:
	_index = index
	var shot: Dictionary = _shots[index]
	var duration := float(shot.get("duration", 1.0))
	_t = u * duration
	# a black shot stands its camera where playback does: on the next picture's first frame
	var black := path_of(index) == null
	var shown := _picture_for(index) if black else index
	var at := 0.0 if black else u
	var path := path_of(shown)
	_need.clear()
	if path != null:
		_set_conditions(shown, 0.0)
		_set_conditions(shown, maxf(at, 0.0001))
		_pose(path, at, shown == _handover)
		_need.append(_camera.global_position)
		for p in path.looks:
			_need.append(p)
	_stream_ahead(shown)
	_overlay.set_curtain(1.0 if black else 0.0)
	# a scrub jumps; whatever was said at the last moment it showed is not said at this one
	_line_key = "?"
	_update_words(shot)


## Whether everything the current moment looks at is standing (the capture runner waits on it).
func ready_to_show() -> bool:
	return _cells_ready()


func camera() -> Camera3D:
	return _camera


func overlay() -> CinematicOverlay:
	return _overlay


# --- small things -----------------------------------------------------------------------------------------

func _atmosphere() -> Node:
	if _world == null or not is_instance_valid(_world):
		return null
	return _world.atmosphere


func _grab_frame() -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var tex := get_viewport().get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _progress_text() -> String:
	var streamer := _world.streamer if _world != null else null
	var cells := streamer.loaded_count() if streamer != null else 0
	return "Laying the country: %d cells…" % cells
