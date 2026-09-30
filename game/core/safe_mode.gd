class_name SafeMode
extends RefCounted
## Starting safely after a launch that did not start properly: the coarse ground, no country behind
## the title, and one threaded read at a time.
##
## Each launch writes `user://launch_state.json` (the sentinel) as it goes:
##
##   starting     written at boot, with the step it had reached and the build
##   stalled      written by the watchdog while the main thread has not moved for 5 s or more;
##                written back to what it was when the main thread goes on
##   menu_ok      the title has been up and answering for MENU_OK_S, with its country shown or
##                given up (or a game's world stood up)
##   clean_exit   the game was quit
##
## A launch that finds "starting" or "stalled" there -- the last one was killed, or crashed, before
## its menu was ever usable -- starts in safe mode and says so on the title. It also turns the
## Graphics setting "Full terrain and the title's country" off, so it stays the player's choice: it
## is never turned back on behind their back, however many safe launches go well; that setting
## turns it back on.
##
## `-- --safe-mode` asks for it, `-- --no-safe-mode` switches the check off for a launch. Headless
## runs, tools and tests are never touched: the check is skipped when anything but a player's
## argument is on the command line (`skips_check`), and so is a run from the editor's debugger
## (stopping one there is a kill).

const STATE_PATH := "user://launch_state.json"
## How long the title must be up and answering before the launch counts as having started.
const MENU_OK_S := 20.0
const ARG_ON := "--safe-mode"
const ARG_OFF := "--no-safe-mode"
## What a player (or a tester told what to type) may put on the command line without it counting
## as a tool's run. Prefixes.
const PLAYER_ARGS: Array[String] = ["--safe-mode", "--no-safe-mode", "--terrain=", "--terrain-lods=",
	"--fallback-terrain", "--debug-stall-terrain", "--errorlog"]
## The states a launch that never finished starting leaves behind.
const UNCLEAN: Array[String] = ["starting", "stalled"]

## Whether this launch is in safe mode.
static var active := false
## Why: "asked" (--safe-mode), "last_launch" (the sentinel), "setting" (the Graphics setting is off).
static var why := ""
## What the sentinel said when the game started.
static var previous: Dictionary = {}
## Whether the command line decided (--safe-mode, --terrain=terrain3d), so the setting does not.
static var pinned := false

static var _mutex := Mutex.new()


## Whether the launch before this one never finished starting.
static func unclean(prev: Dictionary) -> bool:
	return str(prev.get("state", "")) in UNCLEAN


## Whether this run is not a player's launch: headless, a tool's arguments, a script or a scene of
## its own named on the command line, or the editor's debugger attached. Pure, for the tests.
static func skips_check(user_args: PackedStringArray, engine_args: PackedStringArray, headless: bool, debugger: bool) -> bool:
	if headless or debugger:
		return true
	for a in user_args:
		var players := false
		for p in PLAYER_ARGS:
			if a.begins_with(p):
				players = true
				break
		if not players:
			return true
	for a in engine_args:
		if a in ["-s", "--script", "--doctool", "--export-release", "--export-debug", "--export-pack", "--import", "--editor", "-e"] \
				or a.ends_with(".tscn") or a.ends_with(".gd"):
			return true
	return false


## The verdict for this launch: {"safe": bool, "why": String, "pinned": bool}. Pure, for the tests.
##   --safe-mode          always ("asked"), whatever the setting says (pinned)
##   --terrain=terrain3d  never: whoever typed it is taking the risk (pinned)
##   an unclean sentinel  "last_launch", unless the check is skipped or --no-safe-mode
##   the setting off      "setting"
## Pinned, the Graphics setting does not change it for the rest of the launch.
static func decide(prev: Dictionary, user_args: PackedStringArray, full_terrain: bool, checking: bool) -> Dictionary:
	if user_args.has(ARG_ON):
		return {"safe": true, "why": "asked", "pinned": true}
	if user_args.has(WorldStatus.FORCE_TERRAIN3D_ARG):
		return {"safe": false, "why": "", "pinned": true}
	if checking and not user_args.has(ARG_OFF) and unclean(prev):
		return {"safe": true, "why": "last_launch", "pinned": false}
	if not full_terrain:
		return {"safe": true, "why": "setting", "pinned": false}
	return {"safe": false, "why": "", "pinned": false}


## The Graphics setting "Full terrain and the title's country" moved (or was applied): off is safe
## mode, on leaves it, unless the command line decided (`pinned`). Graphics.apply calls it.
static func follow_setting(full_terrain: bool) -> void:
	if pinned:
		return
	if not full_terrain and not active:
		set_active(true, "setting")
	elif full_terrain and active:
		set_active(false)


## Puts the game in (or out of) safe mode now: the coarse ground, and one threaded read at a time.
## The title reads `active` for its country.
static func set_active(on: bool, reason := "") -> void:
	active = on
	why = reason if on else ""
	WorldStatus.force_fallback = on
	ThreadedLoads.safe_limit = 1 if on else 0


## The one line the title shows in safe mode.
static func menu_line(reason: String) -> String:
	match reason:
		"last_launch":
			return ("Wickmere did not start properly last time, so it has started safely: the coarse ground, "
					+ "and no country behind the menu. The Graphics settings turn the full terrain back on.")
		"asked":
			return "Started safely, as asked (%s): the coarse ground, and no country behind this menu." % ARG_ON
	return ("Started safely: the coarse ground, and no country behind this menu. "
			+ "The Graphics settings turn the full terrain back on.")


# --- the sentinel -------------------------------------------------------------------------------

## What the sentinel at `at` says, or {} when there is none or it cannot be read.
static func read_state(at := STATE_PATH) -> Dictionary:
	_mutex.lock()
	var out := {}
	if FileAccess.file_exists(at):
		# quietly: a torn file (the game killed while writing it) is no verdict, and no error either
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(at)) == OK and json.data is Dictionary:
			out = json.data
	_mutex.unlock()
	return out


## Writes the sentinel whole: to a file beside it, then over it, so a game killed in the middle of
## writing it leaves the old one rather than half of the new. Safe from any thread.
static func write_state(state: Dictionary, at := STATE_PATH) -> bool:
	_mutex.lock()
	var tmp := at + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	var ok := f != null
	if ok:
		f.store_string(JSON.stringify(state, "  "))
		f.close()
		ok = DirAccess.rename_absolute(tmp, at) == OK
		if not ok:
			# a rename that will not replace: write it in place
			var g := FileAccess.open(at, FileAccess.WRITE)
			ok = g != null
			if ok:
				g.store_string(JSON.stringify(state, "  "))
				g.close()
			DirAccess.remove_absolute(tmp)
	_mutex.unlock()
	return ok
