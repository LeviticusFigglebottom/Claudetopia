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
## streamer follows the camera, and every cell a shot's camera will see along its path is asked for
## when it begins (ShotSight), with what the next one opens on, so the far ground is not bare while
## it is watched. The whole film's country is asked for as it begins (`_plan_film`): every cell any
## shot sees or flies through, every place its towns stand and everyone who lives there, dressed; and
## the first picture waits under the opening's black until the near part of all of it stands
## (PREROLL_*), because the places, the towns and the people are pieces of tens of milliseconds that
## are never built while the pictures are watched. Once the first picture is up nothing waits on the
## country again: a cut holds its still a few frames, never goes to black and never says it is
## loading, and a shot whose country is somehow not all in is shown after MID_HOLD_CAP_SECONDS with
## what there is. Before the first picture the black shows the hold line after HOLD_GRACE_SECONDS,
## and the music waits. The pictures keep real time, as the music does, and
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
## Before the first picture, the whole film's country (`_plan_film`) is waited for until it stands,
## until nothing of it has come for PREROLL_STALL_FRAMES frames and PREROLL_STALL_S seconds together,
## or for PREROLL_CAP_SECONDS in all; then the film plays with what has come.
const PREROLL_CAP_SECONDS := 90.0
const PREROLL_STALL_S := 6.0
const PREROLL_STALL_FRAMES := 90
## Once the near country stands, the far ring's is waited for this much longer at most.
const PREROLL_FAR_GRACE_S := 3.0
## After the first picture a cut never waits on the country more than this, on its still, without a
## caption: then it is shown with what has come (the near country is all in by then unless the
## opening gave up on it).
const MID_HOLD_CAP_SECONDS := 1.0
## Where a shot's camera is sampled along its path for the near ground under it (`_plan_film`).
const PATH_SAMPLES := 9
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
## A shot is shown once the cells its first OPENING_U of playing sees are in (ShotSight); the rest
## come while it plays.
const OPENING_U := 0.3

## A headless run (the unit suite, the journey, the smoke run) never plays one unless a test
## asks for it here: a cutscene taking the camera for ninety seconds is not something a
## scripted run expects.
static var headless_allowed := false
## Off, a shot asks only for the rings round its camera and what it looks at, as it did before
## ShotSight: for a capture (`--no-sight`) to show the difference on one build.
static var sight_streaming := true

var def: Dictionary = {}
var mode := Mode.OPENING
## Tests run the pictures faster; the waits for the country and a held key stay in real seconds.
var time_scale := 1.0
var skipped := false
## The caps, as values a test can shorten.
var hold_cap_seconds := HOLD_CAP_SECONDS
var overall_cap_seconds := OVERALL_CAP_SECONDS
var preroll_cap_seconds := PREROLL_CAP_SECONDS
var mid_hold_cap_seconds := MID_HOLD_CAP_SECONDS
## The whole film's country (`_plan_film`): every cell any shot will see or fly over, at its ring;
## of them the near ones, which the first picture waits for; and every point a shot opens on or looks
## at, round which the near ring and the towns must stand. Empty when not planned (a scrub, or
## `sight_streaming` off).
var film_cells: Dictionary = {}
var film_near: Dictionary = {}
var film_points: Array[Vector3] = []
## How the opening's wait for the whole film went: {ms, cells, near, people, why} (why: "" when all of
## it came, "stalled" or "cap"), and when each picture's own country was all in, ms from the hold's
## start (for the log and the probe).
var preroll: Dictionary = {}
var _preroll_key := ""
var _preroll_moved_ms := 0
var _preroll_quiet := 0
var _preroll_done := false
var _near_ready_ms := -1
var _preroll_each: Dictionary = {}
## Whether the overall cap handed over, and the shots shown before their country had all come.
var gave_up := false
var shown_early: Array[String] = []
## Every hold the film made, in order, for a probe or a test: {shot, mid (after its first picture),
## ready (its country was in when first asked), caption (the hold line went up), early (shown on the
## cap without all of it), ms (from the cut to the picture)}. A hold mid-film that was not `ready`
## is a wait the player sat through.
var holds: Array[Dictionary] = []
var _hold_rec: Dictionary = {}
var _revealed_once := false

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
## The cells the current picture's opening sees (ShotSight.rings), which must be standing to show it.
var _need_cells: Dictionary = {}
## What each shot's camera sees along its path, worked out when it is first wanted.
var _sights: Dictionary = {}
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
## Whether this player has stopped the viewport drawing 3D while a hold covers the screen.
var _holding_3d := false
## The frames since the film's first picture began to be drawn (World.warm_layers), or -1: its first
## use of the ground's, the water's and the trees' shaders is paid a layer a frame under the curtain,
## as the title's is. Once a film: warming every shot cost each hold three frames, seconds apiece on
## the software renderer, for shaders already compiled.
var _warm_step := -1
var _warmed := false


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
	if mode != Mode.SCRUB:
		# The opening's black goes down now, and the menus' fade -- which may still be down: it lifts
		# when the body stands, or later if it waits for the streaming -- is lifted onto it unseen.
		# It sits under this curtain, which is just as black, so the opening owns the screen until
		# the hand-over, holding on its own black while the country loads. Left down, it would hide
		# every picture behind the subtitles. Not after the frames below: each of them stands up the
		# country round the hand-over and the first shots, and on a slow machine (or headless, where
		# nothing is paced) they are seconds each, the fade and its caption still down over them.
		_overlay.set_curtain(1.0)
		_curtain_target = 1.0
		_bars_target = 1.0
		if UI.is_faded_out():
			UI.fade_from_black(0.3)
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
	_see_ahead()
	if mode == Mode.SCRUB:
		_overlay.set_curtain(0.0)
		_overlay.set_bars(1.0)
		_phase = Phase.PLAY
		return
	# (the curtain went down and the menus' fade was lifted onto it with the take-over, above)
	if def.has("music"):
		Music.play_cue(str(def["music"]))
	_began_ms = Time.get_ticks_msec()
	_enter_shot(0)


func is_playing() -> bool:
	return _phase in [Phase.HOLD, Phase.PLAY, Phase.SKIPPING]


## Between taking the screen over (the curtain down, the menus' fade lifted onto it) and its first
## shot: the frames that stand up the country round the hand-over, seconds each on a slow machine.
func is_starting() -> bool:
	return _phase == Phase.STARTING


## The camera gliding back to the player after the last shot: still the film's, not yet the player's.
func is_handing_over() -> bool:
	return _phase == Phase.HANDOVER


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
		"also_cells": streamer.also_cells.duplicate() if streamer != null else {},
		"hurry": streamer.hurry if streamer != null else false,
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
	var atm := _atmosphere()
	if atm != null and "quiet" in atm:
		# the game's own weather at the hand-over is told now, under the black, once; the shots'
		# weather is the pictures' and is told to nobody (Atmosphere.quiet)
		var weather := str((def.get("handover", {}) as Dictionary).get("weather", ""))
		if mode == Mode.OPENING and not weather.is_empty():
			atm.call("force_weather", weather, true)
		atm.set("quiet", true)


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
	var t0 := Time.get_ticks_usec()
	_restore_world()
	t0 = _counted("film_restore_world", t0)
	_restore_globals()
	_counted("film_restore_globals", t0)


## What belongs to the world: the streamer, the sky, the body and its camera.
func _restore_world() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var t0 := Time.get_ticks_usec()
	var streamer := _world.streamer
	if streamer != null:
		var target: Variant = _saved.get("target", null)
		streamer.target = target if target is Node3D and is_instance_valid(target) else _player
		streamer.report_regions = bool(_saved.get("report_regions", true))
		streamer.hurry = bool(_saved.get("hurry", false))
		if _planned and _phase == Phase.HANDOVER:
			# the film's country is let go once the hand-over is over (`_finish`): a cell let go is a
			# frame of a tenth of a second here, and the gameplay camera arriving is watched
			streamer.refresh()
		else:
			_let_the_film_go()
	var terrain_camera: Variant = _saved.get("terrain_camera", null)
	if _world.terrain_node != null and terrain_camera is Camera3D and is_instance_valid(terrain_camera):
		_world.terrain_node.call("set_camera", terrain_camera)
	# The opening hands the world to the body it hands control to, the way the spawn does, whatever
	# was following what when it began: the streaming, Terrain3D's clipmap and collision, and the
	# fly camera let go (World.follow).
	if mode == Mode.OPENING and _player != null and is_instance_valid(_player):
		_world.follow(_player)
	t0 = _counted("film_restore_streaming", t0)
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
		if "quiet" in atm:
			atm.set("quiet", false)
			atm.call("tell_if_changed")
	t0 = _counted("film_restore_sky", t0)
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
## What the streamer was asked for besides its target before the film, given back.
func _let_the_film_go() -> void:
	var streamer := _world.streamer if _world != null and is_instance_valid(_world) else null
	if streamer == null or not streamer.is_inside_tree() or _world.torn_down:
		return
	streamer.also_cells = (_saved.get("also_cells", {}) as Dictionary).duplicate()
	streamer.set_also_around(_saved.get("also_around", []))


func _restore_globals() -> void:
	_draw_3d(true)
	if _warm_step >= 0 and _world != null and is_instance_valid(_world):
		_world.warm_layers(99)
	_warm_step = -1
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
	var atm := _atmosphere()
	if atm != null and "quiet" in atm and bool(atm.get("quiet")):
		atm.set("quiet", false)
	if _planned and _restored and _phase != Phase.DONE:
		_let_the_film_go()
	for i in _sight_tasks:
		WorkerThreadPool.wait_for_task_completion(int(_sight_tasks[i]))
	_sight_tasks.clear()
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
	_need_cells = {}
	_entering = [func() -> void: _enter_conditions(picture), func() -> void: _enter_sight(picture),
			func() -> void: _stream_ahead(picture)]
	if index == 0 or mode == Mode.SCRUB or not WorldPace.paced():
		# at once: the first shot (under the opening's curtain), a scrub, or where nothing is paced
		while not _entering.is_empty():
			_enter_step()
	_begin_hold()
	shot_started.emit(index, str(shot.get("id", "")))


## What entering a shot does, a piece a frame at the start of its hold (the still or the black covers
## the screen): its time, weather and place's light; where it sees; what to stream. Done in the frame
## the last shot ended it was up to 80 ms of one watched frame here (TRIAGE item 36's second pass).
var _entering: Array = []


func _enter_step() -> void:
	var step: Callable = _entering.pop_front()
	var t0 := Time.get_ticks_usec()
	step.call()
	_counted("film_enter", t0)


func _enter_conditions(picture: int) -> void:
	if picture < 0:
		return
	var path := path_of(picture)
	var t0 := Time.get_ticks_usec()
	_set_conditions(picture, 0.0)
	t0 = _counted("film_enter_sky", t0)
	_pose(path, 0.0, picture == _handover)
	_counted("film_enter_pose", t0)
	_need.append(path.position_at(0.0))
	for p in path.looks:
		_need.append(p)


func _enter_sight(picture: int) -> void:
	if picture < 0:
		return
	# the near ground its opening sees; the far comes while it plays
	_need_cells = ShotSight.near_only(ShotSight.rings(sight_of(picture), OPENING_U))


## Loads what the current picture looks at and where the next one starts while this one plays.
func _stream_ahead(picture: int) -> void:
	var streamer := _world.streamer
	if streamer == null:
		return
	if _planned:
		# the whole film's country is wanted from the opening's hold to the hand-over (`_plan_film`):
		# nothing a later shot needs is let go meanwhile, nor asked for again at a cut
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
	# everything this shot will see, and what the next opens on, so it is in before the cut
	streamer.also_cells = ShotSight.merged(ShotSight.rings(sight_of(picture)),
			ShotSight.rings(sight_of(next), OPENING_U)) if sight_streaming else {}
	streamer.set_also_around(points)


## The whole film's country, asked for at once (`film_cells`, `film_points`): what every shot's camera
## sees along its path (ShotSight), the near ground under its path, and the rings and the towns round
## where it opens and what it looks at. False until every shot's sight has been worked out (on worker
## threads since the film began: `_see_ahead`), so the frame never waits on one; true at once, and
## nothing planned, where there is nothing to plan (a scrub, `sight_streaming` off, no streamer).
var _planned := false


func _plan_film() -> bool:
	if _planned:
		return true
	if mode == Mode.SCRUB or not sight_streaming or _world == null or _world.streamer == null:
		return true                        # nothing to plan: each shot asks for its own (`_stream_ahead`)
	for i in _sight_tasks:
		if not WorkerThreadPool.is_task_completed(int(_sight_tasks[i])):
			return false
	var streamer := _world.streamer
	var cells: Dictionary = {}
	var points: Array[Vector3] = []
	for i in _shots.size():
		var path := path_of(i)
		if path == null:
			continue
		cells = ShotSight.merged(cells, ShotSight.rings(sight_of(i)))
		points.append(path.position_at(0.0))
		for p in path.looks:
			points.append(p)
		# what the streamer wants round its target (the camera) anyway as it flies: the near ring at
		# full detail and the far ring round it, so nothing new is asked for, and nothing let go, at a
		# cut or while a shot plays
		for k in PATH_SAMPLES:
			var under := streamer.cell_of(path.position_at(float(k) / float(PATH_SAMPLES - 1)))
			for dz in range(-streamer.far_ring, streamer.far_ring + 1):
				for dx in range(-streamer.far_ring, streamer.far_ring + 1):
					var c := Vector2i(under.x + dx, under.y + dz)
					var ring := 1 if maxi(absi(dx), absi(dz)) <= streamer.full_ring else 2
					cells[c] = mini(ring, int(cells.get(c, 99)))
	for p in points:
		for c in streamer.cells_around(p):
			cells[c] = 1
	film_cells = cells
	film_near = ShotSight.near_only(cells)
	film_points = points
	_planned = true
	streamer.also_cells = film_cells
	streamer.set_also_around(film_points)
	Log.info("Cinematic", "%s asks for its whole country: %d cells, %d of them near, round %d points"
			% [def.get("id", "?"), film_cells.size(), film_near.size(), film_points.size()])
	return true


## Whether the whole film's near country stands: the cells, the rings and the towns round every point
## a shot opens on or looks at, and everybody living there stood up and dressed.
func _film_ready() -> bool:
	if not _planned:
		return true
	var streamer := _world.streamer
	var near := streamer.standing_of(film_near)
	if near.x < near.y:
		return false
	for p in film_points:
		if not streamer.is_loaded_around(p):
			return false
		var towns := WorldDoors.towns_near(get_tree(), p, ShotSight.TOWNS_M)
		if towns.x < towns.y:
			return false
	return _people_settled()


## Nobody queued to be stood up, and nobody still being dressed.
func _people_settled() -> bool:
	var reg := NpcRegistry.instance
	if reg != null and is_instance_valid(reg) and not reg.settled():
		return false
	return Npc.dressing_count() == 0


## The opening's wait for the whole film: true once it stands, or once it is given up on (stalled,
## or the cap). Writes `preroll`.
func _preroll_ready(held_ms: int) -> bool:
	if _preroll_done or not _planned:
		return true
	var streamer := _world.streamer
	var all := streamer.standing_of(film_cells)
	var near := streamer.standing_of(film_near)
	var reg := NpcRegistry.instance
	var people := reg.spawned.size() if reg != null and is_instance_valid(reg) else 0
	for i in _shots.size():
		if not _preroll_each.has(i) and path_of(i) != null and _shot_ready(i):
			_preroll_each[i] = held_ms
	var why := ""
	if not _film_ready():
		# not WorldPace.built: the film counts its own frames there, and a starved streamer looked busy
		var towns := Vector2i.ZERO
		for p in film_points:
			towns += WorldDoors.towns_near(get_tree(), p, ShotSight.TOWNS_M)
		var key := "%d|%d|%d|%d|%d|%d" % [all.x, near.x, people, Npc.dressing_count(), streamer.progress(), towns.x]
		if key != _preroll_key:
			_preroll_key = key
			_preroll_moved_ms = held_ms
			_preroll_quiet = 0
		else:
			_preroll_quiet += 1
		if held_ms >= int(preroll_cap_seconds * 1000.0):
			why = "cap"
		elif _preroll_quiet >= PREROLL_STALL_FRAMES and held_ms - _preroll_moved_ms >= int(PREROLL_STALL_S * 1000.0):
			why = "stalled"
		if why.is_empty():
			return false
	elif all.x < all.y:
		# the near country stands; the far ring's (its places' silhouettes wait for the film's end
		# once it plays) is given a moment more while it keeps coming
		if _near_ready_ms < 0:
			_near_ready_ms = held_ms
		if held_ms - _near_ready_ms < int(PREROLL_FAR_GRACE_S * 1000.0) and held_ms < int(preroll_cap_seconds * 1000.0):
			return false
	_preroll_done = true
	preroll = {"ms": held_ms, "cells": all, "near": near, "people": people, "why": why, "each": _preroll_each.duplicate()}
	var line := "%s: the whole film's country in %.1f s before the first picture (near %d of %d, all %d of %d, %d people; each shot's own in %s ms)%s" % [
			def.get("id", "?"), held_ms / 1000.0, near.x, near.y, all.x, all.y, people, str(_preroll_each),
			"" if why.is_empty() else ", given up (%s): %s" % [why, waiting_for()]]
	if why.is_empty():
		Log.info("Cinematic", line)
	else:
		Log.warn("Cinematic", line)
	return true


## Whether picture `index`'s own opening stands (its point rings, its towns, the near cells it sees
## first): what `_cells_ready` asks of the current one.
func _shot_ready(index: int) -> bool:
	var path := path_of(index)
	var streamer := _world.streamer
	if path == null or streamer == null:
		return true
	var points: Array = [path.position_at(0.0)]
	points.append_array(path.looks)
	for p in points:
		if not streamer.is_loaded_around(p):
			return false
	var towns := WorldDoors.towns_near(get_tree(), points[0], ShotSight.TOWNS_M)
	if towns.x < towns.y:
		return false
	var seen := streamer.standing_of(ShotSight.near_only(ShotSight.rings(sight_of(index), OPENING_U)))
	return seen.x >= seen.y


## Whether the film's pictures are being watched, from its first picture to the end of the hand-over
## (cuts included): what builds the world in pieces too big for a watched frame (a place, a town, a
## person) waits until the film is over, since everything the film needs came before its first
## picture, and the gameplay camera arriving is watched too.
func watched() -> bool:
	return _revealed_once and _phase in [Phase.PLAY, Phase.HOLD, Phase.HANDOVER]


## The cells shot `index`'s camera sees along its path (ShotSight.seen); {} for a black one.
func sight_of(index: int) -> Dictionary:
	if index < 0:
		return {}
	if _sights.has(index):
		return _sights[index]
	if _sight_tasks.has(index):
		# worked out on a worker thread since the film began (`_see_ahead`): waited for, if not done
		WorkerThreadPool.wait_for_task_completion(int(_sight_tasks[index]))
		_sight_tasks.erase(index)
		_sights[index] = _sight_out[index]
		return _sights[index]
	var path := path_of(index)
	var streamer := _world.streamer if _world != null else null
	var seen := {}
	if path != null and streamer != null:
		var r := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16.0, 9.0)
		seen = ShotSight.seen(path, streamer, Callable(self, "_surface"), 0.0, 1.0,
				r.x / maxf(r.y, 1.0), ShotSight.REACH_M * maxf(streamer.view_range, 0.5))
	_sights[index] = seen
	return seen


## What every shot after the first will see, worked out on worker threads, one task a shot, as the
## film begins (ShotSight reads only the path and the ground's maps): tens of milliseconds a shot,
## which a cut paid in the frame it was wanted (TRIAGE item 36).
var _sight_tasks: Dictionary = {}
var _sight_out: Array = []


func _see_ahead() -> void:
	if mode == Mode.SCRUB or _world == null or _world.streamer == null or not WorldPace.paced():
		return
	var streamer := _world.streamer
	var r := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16.0, 9.0)
	var aspect := r.x / maxf(r.y, 1.0)
	var reach := ShotSight.REACH_M * maxf(streamer.view_range, 0.5)
	var ground := Callable(self, "_surface")
	_sight_out.resize(_shots.size())
	var out := _sight_out
	for i in range(1, _shots.size()):
		var path := path_of(i)
		if path == null or _sights.has(i):
			continue
		_sight_tasks[i] = WorkerThreadPool.add_task(func() -> void:
			out[i] = ShotSight.seen(path, streamer, ground, 0.0, 1.0, aspect, reach), true, "wm_shot_sight")


func _cells_ready() -> bool:
	var streamer := _world.streamer
	if streamer == null:
		return true
	for p in _need:
		if not streamer.is_loaded_around(p):
			return false
	# the towns where it opens, which a world standing up while it is drawn raises a piece at a time
	if not _need.is_empty():
		var towns := WorldDoors.towns_near(get_tree(), _need[0], ShotSight.TOWNS_M)
		if towns.x < towns.y:
			return false
	if not sight_streaming:
		return true
	var seen := streamer.standing_of(_need_cells)
	return seen.x >= seen.y


## Of the cells the current moment sees (ShotSight), how many are standing: Vector2i(standing, of).
## What a still shows bare is the difference.
func sight_standing() -> Vector2i:
	var streamer := _world.streamer if _world != null else null
	return streamer.standing_of(_need_cells) if streamer != null else Vector2i.ZERO


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
	var t0 := Time.get_ticks_usec()
	if atm != null and not region.is_empty():
		atm.call("set_region", region, true)
		if shot.has("weather"):
			atm.call("force_weather", str(shot["weather"]), true)
	t0 = _counted("film_sky_atmosphere", t0)
	if not region.is_empty():
		Ambience.call("set_region", region)
	_counted("film_sky_ambience", t0)


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

## Counts what a piece of the film's frame took (the CPU probe's accounts) and returns the time now.
func _counted(what: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	WorldPace.count(what, now - t0)
	return now


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_film(_delta)
	WorldPace.count("film_process", Time.get_ticks_usec() - t0)


func _process_film(_delta: float) -> void:
	if _phase == Phase.HOLD and mode != Mode.SCRUB:
		# while a hold covers the screen, what the shots ahead will see is worked out, one a frame
		# (ShotSight: tens of milliseconds each), so a cut does not pay for it in a watched frame
		for i in range(maxi(_index, 0), _shots.size()):
			if path_of(i) != null and not _sights.has(i):
				if _sight_tasks.has(i) and not WorkerThreadPool.is_task_completed(int(_sight_tasks[i])):
					break                  # still being worked out on its thread: never waited for here
				var ts := Time.get_ticks_usec()
				sight_of(i)
				WorldPace.count("film_sight", Time.get_ticks_usec() - ts)
				break
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
	if _holding_3d and _phase != Phase.HOLD:
		_draw_3d(true)
	match _phase:
		Phase.HOLD:
			var th := Time.get_ticks_usec()
			_tick_hold(real)
			_counted("film_tick_hold", th)
		Phase.PLAY:
			var tp := Time.get_ticks_usec()
			_tick_play(dt)
			_counted("film_tick_play", tp)
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


func _draw_3d(on: bool) -> void:
	if mode == Mode.SCRUB or not is_inside_tree():
		return
	var vp := get_viewport()
	if not on and not _holding_3d and not vp.disable_3d:
		vp.disable_3d = true
		_holding_3d = true
	elif on and _holding_3d:
		vp.disable_3d = false
		_holding_3d = false


func _hurry(on: bool) -> void:
	if mode != Mode.SCRUB and _world != null and is_instance_valid(_world) and _world.streamer != null:
		_world.streamer.hurry = on


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
	# Before the first picture (and after a skip) nothing is watched but the black: the country
	# hurries. At a cut mid-film it does not: the still is on the screen for a few frames, the
	# country is in already (`_plan_film`), and the curtain's budget there stood people and places up
	# in frames of a tenth of a second at every cut.
	_hurry(not _mid_film() or bool((_shots[_index] as Dictionary).get("black", false)))
	_waited = 0.0
	_settle = SETTLE_FRAMES
	_hold_began_ms = Time.get_ticks_msec()
	_hold_reported = false
	_hold_rec = {"shot": _index, "mid": _revealed_once, "ready": null, "caption": false, "early": false, "ms": 0}


func _tick_hold(delta: float) -> void:
	_waited += delta
	if not _entering.is_empty():
		# the shot is still being entered, a piece a frame (`_enter_shot`)
		_enter_step()
		return
	# while the black or the last frame covers the screen nothing 3D is seen, and on a slow machine a
	# frame of it is seconds the country could have been built in: none is drawn until it is in
	_draw_3d(not (_overlay.curtain() >= 0.999 or _overlay.is_frozen()))
	var shot: Dictionary = _shots[_index]
	var black := bool(shot.get("black", false))
	var held_ms := Time.get_ticks_msec() - _hold_began_ms
	var mid := _mid_film()
	# after the overall cap nothing is waited for: the hand-over comes at once; mid-film a cut waits
	# a moment at most, on its still
	var cap_ms := 0 if gave_up else int((minf(hold_cap_seconds, mid_hold_cap_seconds) if mid else hold_cap_seconds) * 1000.0)
	if not _revealed_once and not skipped and not gave_up:
		# before the first picture: the whole film's country, so that no cut waits on it again
		if not _plan_film():
			return
		var was_done := _preroll_done
		if not _preroll_ready(held_ms):
			_hold_line_if_late(shot)
			return
		if not was_done and _planned:
			# the first shot's own wait (its cap, its settling frames) counts from here
			_hold_rec["preroll_ms"] = held_ms
			_hold_began_ms = Time.get_ticks_msec()
			held_ms = 0
	var shown := black or _cells_ready()
	if _hold_rec.get("ready") == null:
		_hold_rec["ready"] = shown
	if not shown:
		if held_ms >= int(HOLD_REPORT_SECONDS * 1000.0) and not _hold_reported:
			_hold_reported = true
			Log.info("Cinematic", "shot '%s' is waiting for the country: %s" % [shot.get("id", ""), waiting_for()])
		if held_ms >= cap_ms:
			Log.warn("Cinematic", "shot '%s' shown after %.1f s without all of its country: %s"
					% [shot.get("id", ""), held_ms / 1000.0, waiting_for()])
			shown_early.append(str(shot.get("id", "")))
			_hold_rec["early"] = true
			shown = true
	if shown:
		# the settling frames draw the new place, under the curtain or the still; a place that was
		# not being drawn is drawn a layer a frame first
		if _holding_3d and not black and not _warmed:
			_warm_step = 0
			_warmed = true
		_draw_3d(true)
		if _warm_step >= 0 and _world != null and is_instance_valid(_world):
			var tw := Time.get_ticks_usec()
			var done := _world.warm_layers(_warm_step)
			_counted("film_warm_layers", tw)
			_warm_step = -1 if done else _warm_step + 1
			if not done:
				return
		if _settle > 0 and not black and held_ms < cap_ms:
			_settle -= 1
			return
		_reveal(black)
		return
	if not mid:
		_hold_line_if_late(shot)


## Before the first picture (or after a skip), a country late past HOLD_GRACE_SECONDS: the black
## with the hold line, and the music waits with the pictures. Never once the film has begun: a cut
## holds its still and nothing else (MID_HOLD_CAP_SECONDS).
func _hold_line_if_late(_shot: Dictionary) -> void:
	if _mid_film() or _waited <= HOLD_GRACE_SECONDS or _overlay.caption_shown():
		return
	_fade_curtain(1.0, 0.35)
	_overlay.caption_in(str(def.get("hold_line", DEFAULT_HOLD_LINE)))
	_hold_rec["caption"] = true
	Music.pause_cue(true)
	_held_music = true


## Whether the film's pictures have begun and it was not skipped: from then on nothing waits on black
## or says it is loading.
func _mid_film() -> bool:
	return _revealed_once and not skipped and not gave_up


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
	if not _hold_rec.is_empty():
		_hold_rec["ms"] = Time.get_ticks_msec() - _hold_began_ms
		holds.append(_hold_rec)
		_hold_rec = {}
	_revealed_once = true
	if held > 1.0:
		Log.info("Cinematic", "shot '%s' held %.1f s for its country" % [_shots[_index].get("id", ""), held])
	if _index == _handover:
		_stand_people_up()
	_phase = Phase.PLAY
	_hurry(false)
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
	var t0 := Time.get_ticks_usec()
	if path != null:
		_pose(path, u, _index == _handover)
		t0 = _counted("film_play_pose", t0)
		_set_conditions(_index, maxf(u, 0.0001))
		t0 = _counted("film_play_conditions", t0)
	_update_words(shot)
	t0 = _counted("film_play_words", t0)
	if _t >= duration:
		_end_shot()
		_counted("film_end_shot", t0)


func _end_shot() -> void:
	_log_shot()
	if _index == _handover:
		_hand_over()
		return
	var next := _index + 1
	if CinematicDef.dissolve_into(def, next) > 0.0:
		var tg := Time.get_ticks_usec()
		var still := _grab_frame()
		WorldPace.count("film_grab", Time.get_ticks_usec() - tg)
		if still != null:
			_overlay.freeze(still)
		_counted("film_freeze", tg)
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
	var t0 := Time.get_ticks_usec()
	_stand_people_up()
	_counted("film_handover_people", t0)
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
	_let_the_film_go()
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
	_need_cells = {}
	if path != null:
		_set_conditions(shown, 0.0)
		_set_conditions(shown, maxf(at, 0.0001))
		_pose(path, at, shown == _handover)
		_need.append(_camera.global_position)
		for p in path.looks:
			_need.append(p)
		# what this moment of the shot sees (a still is taken of it)
		var r := get_viewport().get_visible_rect().size
		_need_cells = ShotSight.rings(ShotSight.seen(path, _world.streamer, Callable(self, "_surface"),
				at, at, r.x / maxf(r.y, 1.0)))
	_stream_ahead(shown)
	if sight_streaming and _world.streamer != null and not _need_cells.is_empty():
		_world.streamer.set_also_cells(ShotSight.merged(_world.streamer.also_cells, _need_cells))
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
	var seen := streamer.standing_of(_need_cells)
	return "%d of %d cells in%s, %d of the %d its opening sees; the streamer follows %s, %d loaded, %d asked for, %d parsed" % [
			cells.size() - missing.size(), cells.size(),
			(" (missing: %s)" % ", ".join(words)) if not words.is_empty() else "",
			seen.x, seen.y,
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
