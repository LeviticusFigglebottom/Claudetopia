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
## with a caption and the music waits, and the shot plays when the country is there -- or after
## HOLD_CAP_SECONDS, with what has come. The pictures keep real time, as the music does, and
## OVERALL_CAP_SECONDS after the first shot it hands over as a skip would: however slow the machine,
## nobody is left inside it. While it holds the game, no slot is written (`SaveSystem.hold_saves`).
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
## However slowly the country comes, a shot is held no longer than this, in real seconds, and is
## then shown with what has arrived: the terrain, the water and the sky are always there, and
## whatever the missing cells carry comes in while it plays. A few seconds: on a machine that
## keeps up, a shot's country is in within a fraction of one.
const HOLD_CAP_SECONDS := 4.0
## A hold that has lasted this long says in the log what it is waiting for, once.
const HOLD_REPORT_SECONDS := 2.0
## Real seconds from the first shot after which the opening hands over as though a key had been
## held: nearly four times its pictures. It is the net under everything else, not a pace: on a
## machine drawing a frame every six seconds, and some frames in twenty, the whole opening, holds
## and all, took a little over four minutes.
const OVERALL_CAP_SECONDS := 360.0
## The pictures run on the wall clock, as the music does. One long frame among quick ones -- a
## hitch -- moves them on by no more than this, so it does not throw a shot away; on a machine whose
## every frame is long the pictures keep the wall clock regardless, or the opening would crawl.
const MAX_STEP_SECONDS := 1.0
## Frames drawn at a new place before its shot is shown, so the country just built and Terrain3D's
## clipmap, which re-centres on the camera over a frame, are what the shot opens on. Never for the
## black, and never past the hold's cap.
const SETTLE_FRAMES := 2
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
## The caps, as values a test can shorten.
var hold_cap_seconds := HOLD_CAP_SECONDS
var overall_cap_seconds := OVERALL_CAP_SECONDS
## Whether the overall cap handed over, and the shots shown before their country had all come.
var gave_up := false
var shown_early: Array[String] = []

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
## When the key being held went down, on the wall clock: the hold is timed from the press, not
## summed from frames, or a single five-second frame would make any tap a skip.
var _held_since_ms := 0
var _prompt_idle := 0.0
var _saved: Dictionary = {}
var _restored := false
var _handover_at := Vector3.ZERO
var _handover_yaw := 0.0
var _handover_rig_yaw := 0.0
var _handover_pitch := PLAYER_PITCH
var _player_name := ""
var _subtitles := true
var _began_ms := 0
var _hold_began_ms := 0
var _hold_reported := false
var _last_usec := 0
var _last_raw_s := 0.0
## Whether the curtain waits under the menus' fade and its loading caption until both have gone
## (`begin`), so the caption fades out over black rather than being covered by it.
var _under_the_fade := false
## What each shot cost to show, for the log (`_log_shot`): frames drawn, the engine's own delta
## summed beside the wall clock, and the slowest frame.
var _shot_frames := 0
var _shot_began_ms := 0
var _shot_engine_s := 0.0
var _shot_slowest_s := 0.0


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
	# the camera is moved once per drawn frame, so it is not smeared between physics ticks
	# (DECISIONS 2026-09-23: what moves per frame opts out)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


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
	_overlay = CinematicOverlay.new()
	_overlay.letterbox = float(def.get("letterbox", CinematicDef.DEFAULT_LETTERBOX))
	_overlay.text_scale = clampf(float(Settings.get_value("accessibility", "ui_scale", 1.0)), 0.8, 1.4)
	add_child(_overlay)
	# The menus' fade is held until the country round the body is in (UI's wait for the country),
	# with the streaming on the body and the body's hands held. Nothing is borrowed until that
	# hold is over, or the two would pull the streaming two ways and the hold would time out.
	# Meanwhile the curtain lies black just under the fade, with the loading caption above it, so
	# the fade lifts onto the opening's black rather than onto the world.
	# It stays there until the fade and the caption have gone: raised over them at once, it covered
	# the caption the moment the hold ended, and on a machine drawing a frame every few seconds the
	# player looked at a bare black screen until the Warden's first words.
	if how != Mode.SCRUB and (UI.is_holding_for_country() or UI.is_loading_shown()):
		_overlay.layer = UI.LAYER_FADE - 1
		_under_the_fade = true
		while UI.is_holding_for_country():
			await get_tree().process_frame
			if not is_inside_tree():
				return
	_save_state()
	_camera = Camera3D.new()
	_camera.name = "CinematicCamera"
	_camera.near = 0.25
	_camera.far = 12000.0
	add_child(_camera)
	_camera.make_current()
	_take_over()
	_decide_handover()
	_put_player_at_handover()
	# the rig follows and pulls its arm in out of the way once per drawn frame: the hand-over
	# shot's last key is the gameplay camera as it will actually stand, not as it would stand with
	# nothing in the way
	for i in 3:
		await get_tree().process_frame
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
	# The menus' fade may still be down: it lifts when the body stands, or later if it waits for
	# the streaming. It sits under this curtain, which is just as black, so it is lifted here
	# unseen and the opening owns the screen until the hand-over, holding on its own black while
	# the country loads. Left down, it would hide every picture behind the subtitles.
	if UI.is_faded_out():
		UI.fade_from_black(0.3)
	if def.has("music"):
		Music.play_cue(str(def["music"]))
	_began_ms = Time.get_ticks_msec()
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
	SaveSystem.hold_saves(_save_reason())
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
	var rig: Node = _player.get("camera_rig")
	if _player.has_method("teleport"):
		# CONTRACTS §8: position, facing, the view behind it, no speed and no interpolation smear
		_player.call("teleport", _handover_at, _handover_yaw, "opening")
	else:
		_player.global_position = _handover_at
		if "velocity" in _player:
			_player.set("velocity", Vector3.ZERO)
		_player.rotation.y = _handover_yaw
	if rig != null:
		rig.set("yaw", _handover_rig_yaw)
		rig.set("pitch", _handover_pitch)
		if rig.has_method("snap_to_target"):
			rig.call("snap_to_target")


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
	# The opening hands the world to the body it hands control to, the way the spawn does, whatever
	# was following what when it began: the streaming, Terrain3D's clipmap and collision, and the
	# fly camera let go (World.follow).
	if mode == Mode.OPENING and _player != null and is_instance_valid(_player):
		_world.follow(_player)
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
	if not _saved.is_empty():
		SaveSystem.release_saves(_save_reason())


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
	_begin_hold()
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

func _process(_delta: float) -> void:
	if _under_the_fade and not UI.is_loading_shown() and not UI.is_faded_out():
		_under_the_fade = false
		_overlay.layer = CinematicOverlay.LAYER
	if _phase == Phase.DONE or _phase == Phase.STARTING or mode == Mode.SCRUB:
		_last_usec = 0
		_last_raw_s = 0.0
		return
	var real := _real_delta()
	var dt := real * time_scale
	if _phase == Phase.PLAY:
		_shot_frames += 1
		_shot_engine_s += _delta
		_shot_slowest_s = maxf(_shot_slowest_s, real)
	_update_skip(real)
	if _phase in [Phase.HOLD, Phase.PLAY] and not gave_up and _began_ms > 0 \
			and Time.get_ticks_msec() - _began_ms > int(overall_cap_seconds * 1000.0):
		_give_up()
	match _phase:
		Phase.HOLD:
			_tick_hold(real)
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


## Wall-clock seconds since the last frame. The engine's own delta is not that on a machine that
## cannot keep up: below 7.5 frames a second it slows the whole game rather than step physics more
## than eight times a frame, so a five-second frame arrives as an eighth of a second, and the
## opening ran at a fortieth of its speed (PROGRESS). A long frame after a quick one is a hitch and
## counts for MAX_STEP_SECONDS at most; a long frame after a long one is the machine, and counts.
func _real_delta() -> float:
	var now := Time.get_ticks_usec()
	var d := 0.0 if _last_usec == 0 else float(now - _last_usec) / 1000000.0
	_last_usec = now
	var limit := maxf(MAX_STEP_SECONDS, _last_raw_s * 2.0)
	_last_raw_s = d
	return minf(d, limit)


func _begin_hold() -> void:
	_phase = Phase.HOLD
	_waited = 0.0
	_settle = SETTLE_FRAMES
	_hold_began_ms = Time.get_ticks_msec()
	_hold_reported = false


func _tick_hold(delta: float) -> void:
	_waited += delta
	var shot: Dictionary = _shots[_index]
	var black := bool(shot.get("black", false))
	var held_ms := Time.get_ticks_msec() - _hold_began_ms
	# after the overall cap nothing is waited for: the hand-over comes at once
	var cap_ms := 0 if gave_up else int(hold_cap_seconds * 1000.0)
	var shown := black or _cells_ready()
	if not shown:
		if held_ms >= int(HOLD_REPORT_SECONDS * 1000.0) and not _hold_reported:
			_hold_reported = true
			Log.info("Cinematic", "shot '%s' is waiting for the country: %s" % [shot.get("id", ""), waiting_for()])
		if held_ms >= cap_ms:
			Log.warn("Cinematic", "shot '%s' shown after %.1f s without all of its country: %s"
					% [shot.get("id", ""), held_ms / 1000.0, waiting_for()])
			shown_early.append(str(shot.get("id", "")))
			shown = true
	if shown:
		if _settle > 0 and not black and held_ms < cap_ms:
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
	var held := (Time.get_ticks_msec() - _hold_began_ms) / 1000.0
	if held > 1.0:
		Log.info("Cinematic", "shot '%s' held %.1f s for its country" % [_shots[_index].get("id", ""), held])
	if _index == _handover:
		_stand_people_up()
	_phase = Phase.PLAY
	_shot_frames = 0
	_shot_began_ms = Time.get_ticks_msec()
	_shot_engine_s = 0.0
	_shot_slowest_s = 0.0


## One line per shot shown: how long its pictures took on the wall and how many frames drew them.
## A machine that cannot keep up shows here first, as few frames and a slow slowest one.
func _log_shot() -> void:
	var shot: Dictionary = _shots[_index]
	Log.info("Cinematic", "shot '%s': %.1f s of pictures in %.1f s on the wall, %d frames (slowest %.2f s; the engine counted %.1f s)"
			% [shot.get("id", ""), minf(_t, float(shot.get("duration", 1.0))),
				(Time.get_ticks_msec() - _shot_began_ms) / 1000.0, _shot_frames, _shot_slowest_s, _shot_engine_s])


func _tick_play(dt: float) -> void:
	var shot: Dictionary = _shots[_index]
	var duration := float(shot.get("duration", 1.0))
	# however long the frames, every shot is drawn at least once past its middle
	_t += minf(dt, duration * 0.5)
	var u := clampf(_t / duration, 0.0, 1.0)
	var path := path_of(_index)
	if path != null:
		_pose(path, u, _index == _handover)
		_set_conditions(_index, maxf(u, 0.0001))
	_update_words(shot)
	if _t >= duration:
		_end_shot()


func _end_shot() -> void:
	_log_shot()
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
				if _held.is_empty():
					_held_since_ms = Time.get_ticks_msec()
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
		_skip_held = maxf(_skip_held, (Time.get_ticks_msec() - _held_since_ms) / 1000.0)
	_overlay.prompt_fill(_skip_held / SKIP_HOLD_SECONDS)
	if _skip_held >= SKIP_HOLD_SECONDS:
		skip()


## Goes to black, then to the last frame of the hand-over shot, and hands over from there: the
## same hand-over, and so the same end state, as watching it through.
func skip() -> void:
	if skipped or not (_phase in [Phase.HOLD, Phase.PLAY]) or mode == Mode.SCRUB:
		return
	skipped = true
	Log.info("Cinematic", "skipped in shot '%s' (%s, %.1f s in)" % [
			(_shots[_index] as Dictionary).get("id", "") if _index >= 0 and _index < _shots.size() else "",
			phase_name(), _t])
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
	_begin_hold()


# --- handing over --------------------------------------------------------------------------------------

func _hand_over() -> void:
	_stand_people_up()
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
	# only now: the new game's flag comes down and its story starts as `finished` is heard, and a
	# slot written in between would have played the opening again when it was loaded
	SaveSystem.release_saves(_save_reason())
	queue_free()


## The people of the place control comes back at are stood up now, not at the NPC streamer's next
## look round. A point of interest's people wait for its dressing (NpcStreamer._place_ready), and
## the dressing goes with its cell when the camera flies off, so the Warden was never stood up
## while the opening played; the streamer looks every three quarters of a second of game time,
## which on a machine drawing a frame every few seconds is half a minute, and the first frame of
## control had nobody at the fire. Called as the last shot is revealed, when the camp is loaded
## around the camera, and again at the hand-over.
func _stand_people_up() -> void:
	if mode != Mode.OPENING:
		return
	var people := get_tree().get_first_node_in_group("npc_streamer")
	if people != null and people.has_method("refresh"):
		people.call("refresh")


## The overall cap: hands over the way holding a key does, so the end is the same end.
func _give_up() -> void:
	gave_up = true
	var shot: Dictionary = _shots[_index] if _index >= 0 and _index < _shots.size() else {}
	Log.warn("Cinematic", "%s has run %.0f s, past its %.0f s cap, in shot '%s' (%s): handing over"
			% [def.get("id", "the cinematic"), (Time.get_ticks_msec() - _began_ms) / 1000.0,
				overall_cap_seconds, shot.get("id", ""), phase_name()])
	skip()


func _save_reason() -> String:
	match mode:
		Mode.REPLAY:
			return "the opening is replayed"
		Mode.SCRUB:
			return "a cinematic is photographed"
	return "the opening plays"


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


## What the current moment is waiting for, for the log: how many of the cells round its points are
## standing, and where each missing one has got to in the streamer.
func waiting_for() -> String:
	var streamer := _world.streamer if _world != null else null
	if streamer == null:
		return "no streamer"
	var cells := {}
	var missing := {}
	for p in _need:
		for c in streamer.cells_around(p):
			cells[c] = true
		for c in streamer.missing_around(p):
			missing[c] = true
	var words: Array[String] = []
	for c: Vector2i in missing:
		words.append("%d_%d %s" % [c.x, c.y, streamer.cell_state(c)])
	var queue := streamer.queue()
	return "%d of %d cells in%s; the streamer follows %s, %d loaded, %d asked for, %d parsed" % [
			cells.size() - missing.size(), cells.size(),
			(" (missing: %s)" % ", ".join(words)) if not words.is_empty() else "",
			str(streamer.target.name) if streamer.target != null else "nothing",
			int(queue["loaded"]), int(queue["pending"]), int(queue["parsed"])]


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
