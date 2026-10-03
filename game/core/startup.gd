extends Node
## Startup: the trace of the game starting (StartupTrace), the watchdog on the main thread, and
## safe mode (SafeMode). docs/FIRST_LAUNCH.md says what a tester should send.
##
## A tester's game froze behind the title on a fresh PC, and its console stopped at the terrain.
## So from boot every step of the game standing up writes a line to user://logs/startup_*.txt,
## flushed at once, and a thread of its own watches the main thread: when it has not moved for
## STALL_S, the watchdog writes where it stopped and the memory then, every STALL_S while it stays
## stopped. The launch's state is written to user://launch_state.json as it goes, and a launch that
## finds the last one never got its menu going starts safely (SafeMode).
##
## A headless run (the tests, the tools) writes nothing, watches nothing and decides nothing.
##
## Why the window's X cannot be made to work while the main thread is stuck: on Windows the close
## request is a message to the window, and the window's messages are read by the main thread
## (DisplayServerWindows::process_events). A main thread that does not come back never reads it, so
## no other thread can know the X was pressed, and a watchdog killing the game on a stall alone
## would kill games that were only slow. Windows itself offers "Close the program" on a window that
## has not read its messages for a few seconds.

## The main thread not moving for this long is a stall, and each this long again another line.
const STALL_S := 5
## How often the watchdog looks.
const WATCH_MS := 1000
## `-- --debug-stall-terrain=N` holds the main thread N seconds in the terrain step (a debug build's
## test of the watchdog and of safe mode; a release build ignores it).
const STALL_ARG := "--debug-stall-terrain="

## Frames the main thread has gone round (the watchdog reads it).
var ticks := 0
## Whether this launch writes the sentinel (a player's launch: SafeMode.skips_check).
var checking := false
## The state this launch last wrote ("starting", "menu_ok"), as the main thread knows it.
var state := ""
## The seconds a debug build holds the main thread in the terrain step (STALL_ARG), or 0.
var debug_stall_s := 0

var _thread: Thread = null
var _stop := false
var _mutex := Mutex.new()
## Set by the watchdog while it has written "stalled"; the main thread writes the state back.
var _stalled_s := 0
var _stalled_at := ""
var _stalled_written := false
## When the title said it was up (ms), or -1.
var _menu_since_ms := -1
var _ended := false
var _base: Dictionary = {}


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		return
	StartupTrace.begin()
	StartupTrace.step("boot")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var user_args := OS.get_cmdline_user_args()
	for a in user_args:
		if a.begins_with(STALL_ARG) and OS.is_debug_build():
			debug_stall_s = maxi(a.trim_prefix(STALL_ARG).to_int(), 0)
	var headless := DisplayServer.get_name() == "headless"
	checking = not SafeMode.skips_check(user_args, OS.get_cmdline_args(), headless, EngineDebugger.is_active())
	SafeMode.previous = SafeMode.read_state() if checking else {}
	var full := bool(Settings.get_value("graphics", "full_terrain", true))
	var verdict := SafeMode.decide(SafeMode.previous, user_args, full, checking)
	SafeMode.pinned = bool(verdict["pinned"])
	SafeMode.set_active(bool(verdict["safe"]), str(verdict["why"]))
	if bool(verdict["safe"]):
		if str(verdict["why"]) == "last_launch" and full:
			# the player's own setting from here on: never switched back behind their back
			Settings.set_value("graphics", "full_terrain", false, false)
			Settings.save_settings()
	if headless:
		set_process(false)
		return
	_machine()
	StartupTrace.step("safe mode: %s; the last launch %s; the sentinel is %s" % [
		("on (%s)" % SafeMode.why) if SafeMode.active else "off",
		str(SafeMode.previous.get("state", "left nothing")) + (" at \"%s\"" % str(SafeMode.previous.get("step", ""))
			if SafeMode.previous.has("step") else ""),
		"written" if checking else "not written (not a player's launch)"])
	if SafeMode.active:
		Log.warn("Startup", "safe mode (%s): the coarse ground, no country behind the title, one threaded read at a time" % SafeMode.why)
	var info := Engine.get_version_info()
	_base = {"build": ErrorLog.game_commit(), "godot": "%s %s" % [str(info.get("string", "")), str(info.get("hash", "")).left(10)],
		"version": str(ProjectSettings.get_setting("application/config/version", "")), "safe_mode": SafeMode.active,
		"trace": ProjectSettings.globalize_path(StartupTrace.path) if not StartupTrace.path.is_empty() else ""}
	_write("starting")
	_thread = Thread.new()
	# above the game's own threads: a machine that is stuck may be busy, and this must still get to write
	_thread.start(_watch, Thread.PRIORITY_HIGH)
	get_tree().node_added.connect(_on_node_added)
	EventBus.menu_opened.connect(_on_menu_opened)


## The machine, once, at the top of the trace.
func _machine() -> void:
	var driver := OS.get_video_adapter_driver_info()
	var types := ["other", "integrated", "discrete", "virtual", "cpu"]
	var t := RenderingServer.get_video_adapter_type()
	var mem := OS.get_memory_info()
	StartupTrace.step("Wickmere %s, commit %s, Godot %s (%s)" % [ProjectSettings.get_setting("application/config/version", ""),
		ErrorLog.game_commit(), Engine.get_version_info().get("string", "?"), "debug" if OS.is_debug_build() else "release"])
	StartupTrace.step("OS %s %s; CPU %s, %d threads; RAM %.1f GB, %.1f GB free" % [OS.get_name(), OS.get_version(),
		OS.get_processor_name(), OS.get_processor_count(), int(mem.get("physical", 0)) / 1073741824.0, int(mem.get("available", 0)) / 1073741824.0])
	var vram := Graphics.video_memory_gb()
	StartupTrace.step("GPU %s (%s, %s); driver %s; %s via %s, API %s; VRAM %s" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		types[t] if t >= 0 and t < types.size() else str(t), " ".join(driver) if not driver.is_empty() else "?",
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_api_version(), ("%.1f GB" % vram) if vram > 0.0 else "not read on this renderer"])
	# the preset a first launch was given for this adapter (HardwareTier), or the player's own
	var d := HardwareTier.decision
	StartupTrace.step(("graphics: first launch, %s" % HardwareTier.describe(d["adapter"], d)) if bool(d.get("first_launch", false))
			else "graphics: preset %s, the player's (settings.cfg)" % str(Settings.get_value("graphics", "preset", "")))
	StartupTrace.step("worker pool %d threads; threaded reads at once %d; window %s; args %s" % [ThreadedLoads.pool_size(),
		ThreadedLoads.limit(), str(DisplayServer.window_get_size()), " ".join(OS.get_cmdline_user_args())])


func _process(_delta: float) -> void:
	_mutex.lock()
	ticks += 1
	var stalled := _stalled_written
	var for_s := _stalled_s
	var at := _stalled_at
	_stalled_written = false
	_mutex.unlock()
	if stalled:
		StartupTrace.note("main thread went on after %d s or more at \"%s\"" % [for_s, at], StartupTrace.memory(true))
		_write(state)
	if _menu_since_ms >= 0 and Time.get_ticks_msec() - _menu_since_ms >= int(SafeMode.MENU_OK_S * 1000.0):
		var menu := get_tree().current_scene
		if menu == null or not menu.scene_file_path.ends_with("main_menu.tscn"):
			_menu_since_ms = -1
		elif _vista_settled(menu):
			_menu_since_ms = -1
			StartupTrace.step("the title has answered for %.0f s" % SafeMode.MENU_OK_S)
			if state == "starting":
				_write("menu_ok")


## The title's country is shown, or was given up, or there is none.
func _vista_settled(menu: Node) -> bool:
	var v := menu.get_node_or_null("TitleVista") as TitleVista
	return v == null or v.is_showing() or v.phase == TitleVista.Phase.GONE or not v.shown.is_empty()


func _on_menu_opened(screen: String) -> void:
	if screen == "main_menu" and state == "starting":
		_menu_since_ms = Time.get_ticks_msec()


## A game's world (not the title's) that stands up ends the trace and counts as started.
func _on_node_added(node: Node) -> void:
	if StartupTrace.active and node.get_parent() == get_tree().root:
		StartupTrace.step("scene: %s comes in (%s)" % [node.name, node.scene_file_path.get_file()])
	if node is World and not (node as World).vista:
		(node as World).world_ready.connect(_on_game_world_ready, CONNECT_ONE_SHOT)


func _on_game_world_ready() -> void:
	StartupTrace.finish("a game's world is ready")
	if state == "starting":
		_write("menu_ok")


## The main thread going into the terrain step: a debug build asked to hold it there does.
func debug_stall(where: String) -> void:
	if debug_stall_s <= 0:
		return
	StartupTrace.step("debug: holding the main thread %d s in %s" % [debug_stall_s, where])
	OS.delay_msec(debug_stall_s * 1000)
	debug_stall_s = 0


func _write(new_state: String) -> void:
	if not checking or new_state.is_empty():
		return
	_mutex.lock()
	state = new_state
	_mutex.unlock()
	var s := _base.duplicate()
	s["state"] = new_state
	s["step"] = StartupTrace.last()
	s["at"] = Time.get_datetime_string_from_system(true, true) + " UTC"
	SafeMode.write_state(s)


# --- the watchdog (its own thread: never the tree, never the rendering server) ------------------

func _watch() -> void:
	var seen := -1
	var since_ms := Time.get_ticks_msec()
	var next_line_s := STALL_S
	while true:
		# a tenth of WATCH_MS at a time, so quitting never waits long for it; the stall is measured on
		# the clock, not by counting these, which a busy machine may wake late
		for i in 10:
			OS.delay_msec(roundi(WATCH_MS / 10.0))
			if _stop_asked():
				return
		_mutex.lock()
		var now := ticks
		var was := state
		_mutex.unlock()
		var t := Time.get_ticks_msec()
		if now != seen:
			seen = now
			since_ms = t
			next_line_s = STALL_S
			continue
		var still_s := floori((t - since_ms) / 1000.0)
		if still_s < next_line_s:
			continue
		while next_line_s <= still_s:
			next_line_s += STALL_S
		var at := StartupTrace.last()
		StartupTrace.note("WATCHDOG: main thread stalled %d s at step \"%s\"" % [still_s, at])
		if checking:
			var s := _base.duplicate()
			s["state"] = "stalled"
			s["step"] = at
			s["stalled_s"] = still_s
			s["was"] = was
			s["at"] = Time.get_datetime_string_from_system(true, true) + " UTC"
			SafeMode.write_state(s)
		_mutex.lock()
		_stalled_written = true
		_stalled_s = still_s
		_stalled_at = at
		_mutex.unlock()


func _stop_asked() -> bool:
	_mutex.lock()
	var s := _stop
	_mutex.unlock()
	return s


func _stop_watching() -> void:
	if _thread == null:
		return
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	if _thread.is_started():
		_thread.wait_to_finish()
	_thread = null


# --- quitting -------------------------------------------------------------------------------------

func _end(why: String) -> void:
	if _ended:
		return
	_ended = true
	_stop_watching()
	StartupTrace.note("quit (%s)" % why, "")
	_write("clean_exit")
	StartupTrace.close()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if get_tree().auto_accept_quit:
				_end("the window was closed")
		NOTIFICATION_EXIT_TREE, NOTIFICATION_PREDELETE:
			_end("the game ended")
