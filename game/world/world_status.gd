class_name WorldStatus
extends RefCounted
## What of the built world this copy of the game has, and what to tell a player about what it
## lacks.
##
## The world is built, not authored: `tools/world/build_world.py` writes `game/world/generated/`
## and `tools_gd/import_terrain.gd` turns that into Terrain3D regions under `game/terrain_data/`.
## A copy of the game can be missing either, and a machine can be missing the Terrain3D library
## itself (a platform the release has no binary for, or a Mac older than the one it was built for).
## Every one of those used to end the same way: the menu let you in, and you stood on nothing in
## a grey void with the HUD up. So every way into the world asks here first.
##
##   missing   no manifest, no runtime maps or no cells: there is no country to stand in. The title
##             screen says so, with the command that builds it, and nothing enters the world.
##   fallback  the country is there but Terrain3D cannot draw it (no library for this machine, a
##             graphics driver it crashes, or no regions in game/terrain_data), or
##             `-- --terrain=fallback` asked for it:
##             `FallbackTerrain` draws the ground from the runtime height map. Unless it was asked
##             for, the title says so across the sheet with the way to the full terrain, a card says
##             it again on arrival, and a plate in the corner says it for as long as the player is
##             on it (GroundNotice): a toast once said it, and a player who never saw it took the
##             coarse ground for the game's look.
##   ready     everything is there.

const GENERATED := "res://world/generated"
const TERRAIN_DATA := "res://terrain_data"
const BUILD_COMMAND := "./run.sh world"
const BUILD_NEEDS := "Python 3.11 or newer with the packages in tools/requirements.txt (pip install -r tools/requirements.txt), about 8 GB of free memory and a few minutes"
## Imports Terrain3D's regions from maps already built (`tools_gd/import_terrain.gd`, headless).
const TERRAIN_COMMAND := "./run.sh terrain"
const TERRAIN_NEEDS := "Godot 4.7, run headless for a minute or two: run.sh looks for it on the PATH and in the usual places, and the GODOT variable names it anywhere else"
## The full-resolution height map the import reads: there when the world was built on this machine.
const FULL_HEIGHTS := "heights.r32"
## `-- --terrain=fallback` draws the coarse ground even where Terrain3D is available: the way to
## see, test and capture what a machine without the plugin sees, and the way in for a machine whose
## graphics driver fails inside Terrain3D. Read from the user arguments and the engine's own, so it
## works after `--` and in the editor's Main Run Args alike.
const FORCE_FALLBACK_ARG := "--terrain=fallback"
## Other spellings that ask for the same thing (`--fallback-terrain` was the first one).
const FORCE_FALLBACK_ALIASES: Array[String] = ["--terrain=fallback", "--terrain=coarse", "--fallback-terrain"]
## `-- --terrain=terrain3d` tries Terrain3D even on a driver known to fail inside it (below), and so
## does asking for a number of clipmap rings (`--terrain-lods=N`): both are a tool taking the risk.
const FORCE_TERRAIN3D_ARG := "--terrain=terrain3d"
## Mesa's software Vulkan driver (lavapipe) names its device after llvmpipe, and Terrain3D 1.0.2
## crashes it: all four of the driver's rasterizer threads fault on the same out-of-range load in
## its compiled shader. When is a matter of the clipmap and the view, not the ring count alone.
## Alone in an empty project, at 2 m spacing, 7, 8 or 9 rings of 32 drew 60 frames and 9 of 48
## crashed; at 1 m spacing 7 of 48 crashed on the first frame. In the game, 9 rings crash as the
## world is built, and 7 drew the real terrain for 40 seconds of the New Game flow and then crashed
## the same way. So on Forward+ or Mobile there the ground is the coarse one unless a tool asks.
## The OpenGL llvmpipe of the Compatibility renderer draws Terrain3D without trouble (every flow run
## here uses it), and the one graphics card reported (a Radeon RX 9070 XT) draws nine rings. A
## graphics card is not guarded against.
const UNSAFE_RD_ADAPTER := "llvmpipe"
## The oldest macOS the Terrain3D 1.0.2 frameworks were built for (their LC_BUILD_VERSION).
const TERRAIN3D_MIN_MACOS := 15
## Terrain3D's clipmap rings. Nine reach the edge of the world from anywhere in it (world.gd).
const TERRAIN_LODS := 9
## `-- --terrain-lods=N` or the WICKMERE_TERRAIN_LODS environment variable sets the rings, 1 to 10,
## for tools; the argument wins. Seven reach about 6 km, and the land beyond stops in a line.
const TERRAIN_LODS_ARG := "--terrain-lods="
const TERRAIN_LODS_ENV := "WICKMERE_TERRAIN_LODS"

## Tests stand in for the disk with this; `facts()` returns a copy of it while it is set.
static var override: Dictionary = {}
## Tests (and anything else that wants the coarse ground) set this rather than the command line.
static var force_fallback := false


## What is on disk and what the engine loaded. Cheap enough to ask on every screen that needs it:
## one small JSON file, four file lengths and two directory listings.
static func facts() -> Dictionary:
	if not override.is_empty():
		return override.duplicate(true)
	var f := {
		"manifest": false, "runtime_maps": false, "cells": 0, "cells_expected": 0, "pois": false,
		"terrain_class": ClassDB.class_exists("Terrain3D"), "terrain_regions": 0,
		"forced_fallback": force_fallback or forced_by(OS.get_cmdline_user_args()) or forced_by(OS.get_cmdline_args()),
		"safe_mode": SafeMode.active,
		"forced_terrain3d": OS.get_cmdline_user_args().has(FORCE_TERRAIN3D_ARG) or OS.get_cmdline_args().has(FORCE_TERRAIN3D_ARG),
		"lods_asked": terrain_lods_asked(),
		"full_maps": FileAccess.file_exists("%s/%s" % [GENERATED, FULL_HEIGHTS]),
		# Forward+ and Mobile draw through a RenderingDevice; Compatibility and headless do not
		"rendering_device": RenderingServer.get_rendering_device() != null,
		"adapter": RenderingServer.get_video_adapter_name(),
		"os": OS.get_name(), "arch": Engine.get_architecture_name(), "os_version": OS.get_version(),
	}
	var manifest := read_manifest()
	f["manifest"] = not manifest.is_empty()
	if not manifest.is_empty():
		f["runtime_maps"] = _runtime_maps_present(manifest)
		var cells: Array = manifest.get("cells", [32, 32])
		f["cells_expected"] = int(cells[0]) * int(cells[1]) if cells.size() >= 2 else 0
		f["cells"] = _count_files("%s/cells" % GENERATED, "", ".json")
		f["pois"] = FileAccess.file_exists("%s/pois.json" % GENERATED)
	f["terrain_regions"] = _count_files(TERRAIN_DATA, "terrain3d", ".res")
	return f


## The verdict on a set of facts. Pure, so each branch can be tested without touching the disk.
static func evaluate(f: Dictionary) -> Dictionary:
	var out := {"state": "ready", "playable": true, "terrain": "terrain3d", "reason": "",
		"title": "", "detail": "", "notice": "", "badge": "", "announce": false,
		"command": BUILD_COMMAND, "needs": BUILD_NEEDS,
		"lods": int(f.get("lods_asked", 0)), "lods_why": "asked for"}
	var lacking := ""
	if not bool(f.get("manifest", false)):
		lacking = "game/world/generated/world_manifest.json"
	elif not bool(f.get("runtime_maps", false)):
		lacking = "the runtime maps in game/world/generated/runtime/"
	elif int(f.get("cells", 0)) == 0:
		lacking = "the cells in game/world/generated/cells/"
	if not lacking.is_empty():
		out["state"] = "missing"
		out["playable"] = false
		out["terrain"] = ""
		out["reason"] = "world_missing"
		out["title"] = "The world has not been built."
		out["detail"] = ("This copy of Wickmere has its code and its art but not its country: %s is not there. "
				+ "Build it from the repository's top folder with the command below. It needs %s. "
				+ "New Game and Continue wait until it is done.") % [lacking, BUILD_NEEDS]
		return out
	var why := ""
	if bool(f.get("safe_mode", false)):
		why = "safe_mode"
		out["title"] = "Started safely: the coarse ground."
		out["detail"] = ("The game is starting safely (after a launch that did not start properly, or because it was asked to), "
				+ "so the ground is drawn from the 8 m height map rather than by Terrain3D, and the title shows its drawn chart. "
				+ "The Graphics setting \"Full terrain and the title's country\" turns them back on.")
		out["command"] = ""
	elif bool(f.get("forced_fallback", false)):
		why = "forced"
		out["title"] = "The coarse ground, as asked for."
		out["detail"] = "The game was started with %s, so the ground is drawn from the 8 m height map rather than by Terrain3D." % FORCE_FALLBACK_ARG
		out["command"] = ""
	elif not bool(f.get("terrain_class", false)):
		why = "plugin_missing"
		out["title"] = "The full terrain cannot be drawn on this machine."
		out["detail"] = _plugin_missing_detail(f)
		out["command"] = ""
	elif driver_fails_terrain3d(f):
		why = "driver_unsafe"
		out["title"] = "The full terrain cannot be drawn with this graphics driver."
		out["detail"] = ("This is %s, Mesa's software Vulkan driver, and Terrain3D crashes it, "
				+ "so the ground is drawn from the coarse 8 m height map instead: the country is all there, with softer hills and plainer ground. "
				+ "The Compatibility renderer (--rendering-driver opengl3) draws the full terrain here, and a graphics card should. "
				+ "To try Terrain3D anyway, start the game with %s, or with fewer rings, %s7: it may still crash.") % [
					str(f.get("adapter", "")), FORCE_TERRAIN3D_ARG, TERRAIN_LODS_ARG]
		out["command"] = ""
	elif int(f.get("terrain_regions", 0)) == 0:
		why = "terrain_missing"
		out["title"] = "The full terrain is not built."
		if bool(f.get("full_maps", false)):
			# The world was built here and its import never ran. On Windows run.sh looked for
			# `godot` on the PATH, did not find it, and left the build's maps with no regions.
			out["command"] = TERRAIN_COMMAND
			out["needs"] = TERRAIN_NEEDS
			out["detail"] = ("The world's maps were built on this machine but never imported into Terrain3D: "
					+ "game/terrain_data holds no regions. So the ground is drawn from the coarse 8 m height map, "
					+ "which is why it looks plain and grey. The country is all there. Import the full terrain with the command below. It needs %s.") % TERRAIN_NEEDS
		else:
			out["detail"] = ("game/terrain_data holds no terrain regions, so the ground is drawn from the coarse 8 m height map, "
					+ "which is why it looks plain and grey. The country is all there. Build the full terrain with the command below. It needs %s.") % BUILD_NEEDS
	if why.is_empty():
		return out
	out["state"] = "fallback"
	out["terrain"] = "fallback"
	out["reason"] = why
	# Said on the title, on arrival and in the corner, unless the player asked for it themselves (or
	# safe mode says it in a line of its own on the title)
	out["announce"] = why not in ["forced", "safe_mode"]
	out["badge"] = badge_line(why, str(out["command"]))
	out["notice"] = "The full terrain is not drawn here: you are walking on the coarse ground. %s" % _notice_reason(why, f, str(out["command"]))
	return out


## What `evaluate(facts())` says about this machine, now.
static func current() -> Dictionary:
	return evaluate(facts())


## The clipmap rings asked for by these arguments or this environment value (TERRAIN_LODS_ARG,
## TERRAIN_LODS_ENV), clamped to Terrain3D's 1 to 10, or 0 when neither asks. Pure, for the tests.
static func lods_from(args: PackedStringArray, env: String) -> int:
	for a in args:
		if a.begins_with(TERRAIN_LODS_ARG):
			var n := a.trim_prefix(TERRAIN_LODS_ARG)
			if n.is_valid_int():
				return clampi(n.to_int(), 1, 10)
	if env.strip_edges().is_valid_int():
		return clampi(env.strip_edges().to_int(), 1, 10)
	return 0


## The rings this run was asked for, or 0: the user arguments, the engine's own, the environment.
static func terrain_lods_asked() -> int:
	var args := OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	return lods_from(args, OS.get_environment(TERRAIN_LODS_ENV))


## The clipmap rings Terrain3D draws with, for a verdict of `evaluate()`: what was asked for, else
## TERRAIN_LODS.
static func terrain_lods_for(s: Dictionary) -> int:
	var asked := int(s.get("lods", 0))
	return asked if asked > 0 else TERRAIN_LODS


## Whether these command-line arguments ask for the coarse ground (`--terrain=fallback`).
static func forced_by(args: PackedStringArray) -> bool:
	for a in args:
		if a in FORCE_FALLBACK_ALIASES:
			return true
	return false


## Whether Terrain3D would crash the graphics driver these facts describe (UNSAFE_RD_ADAPTER),
## unless `--terrain=terrain3d` or a number of rings asked to try it anyway.
static func driver_fails_terrain3d(f: Dictionary) -> bool:
	if bool(f.get("forced_terrain3d", false)) or int(f.get("lods_asked", 0)) > 0:
		return false
	if not bool(f.get("rendering_device", false)):
		return false
	return str(f.get("adapter", "")).to_lower().begins_with(UNSAFE_RD_ADAPTER)


## The one line under "Coarse ground" in the corner plate: why, and what mends it.
static func badge_line(why: String, command: String) -> String:
	match why:
		"forced":
			return "asked for with %s" % FORCE_FALLBACK_ARG
		"safe_mode":
			return "safe start: the Graphics settings turn the full terrain on"
		"plugin_missing":
			return "Terrain3D did not load on this machine"
		"driver_unsafe":
			return "Terrain3D crashes this graphics driver"
		"terrain_missing":
			return "the full terrain is not built: %s" % command
		"terrain_unreadable":
			return "the terrain regions did not load: %s" % command
	return ""


static func read_manifest() -> Dictionary:
	var path := "%s/world_manifest.json" % GENERATED
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func _runtime_maps_present(manifest: Dictionary) -> bool:
	var rt: Dictionary = manifest.get("runtime", {})
	var n := int(rt.get("grid", 0))
	if n <= 0:
		return false
	for key in ["heights", "regions", "water", "water_level"]:
		var path := "%s/%s" % [GENERATED, str(rt.get(key, ""))]
		var want := n * n * (4 if key in ["heights", "water_level"] else 1)
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null or f.get_length() < want:
			return false
	return true


static func _count_files(dir: String, prefix: String, suffix: String) -> int:
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	var n := 0
	for file in DirAccess.get_files_at(dir):
		if file.begins_with(prefix) and file.ends_with(suffix):
			n += 1
	return n


static func _plugin_missing_detail(f: Dictionary) -> String:
	var where := "%s on %s" % [str(f.get("os", "?")), str(f.get("arch", "?"))]
	var because := "Terrain3D, the plugin that draws the ground, has no library for %s in this copy (its 1.0.2 release ships Windows and Linux on x86_64 and macOS 15 or later)." % where
	if str(f.get("os", "")) == "macOS":
		var major := str(f.get("os_version", "")).get_slice(".", 0).to_int()
		if major > 0 and major < TERRAIN3D_MIN_MACOS:
			because = "Terrain3D, the plugin that draws the ground, is built for macOS %d or later and this Mac runs macOS %s." % [TERRAIN3D_MIN_MACOS, str(f.get("os_version", ""))]
		else:
			because = "Terrain3D, the plugin that draws the ground, did not load on this Mac (%s). If macOS refused it, the Console log says so." % where
	return because + " The ground is drawn from the coarse 8 m height map instead: the country is all there, with softer hills and plainer ground."


static func _notice_reason(why: String, f: Dictionary, command: String) -> String:
	match why:
		"forced":
			return "(%s)" % FORCE_FALLBACK_ARG
		"safe_mode":
			return "(A safe start: the Graphics settings turn the full terrain back on.)"
		"plugin_missing":
			return "(Terrain3D did not load on %s %s.)" % [str(f.get("os", "?")), str(f.get("arch", "?"))]
		"driver_unsafe":
			return "(Terrain3D crashes %s.)" % str(f.get("adapter", "this graphics driver"))
		"terrain_missing":
			return "(game/terrain_data is empty: %s makes it.)" % command
	return ""
