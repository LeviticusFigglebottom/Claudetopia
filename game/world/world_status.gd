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
##   missing     no manifest, no runtime maps or no cells: there is no country to stand in. The
##               title screen says so, with the command that builds it, and nothing enters the world.
##   no_terrain  the country is there but Terrain3D cannot draw its ground (no library for this
##               machine, or no regions in game/terrain_data): refused the same way, with the reason.
##   fallback    only when asked for with `-- --fallback-terrain`: `FallbackTerrain` draws the ground
##               from the runtime height map. It is written and not yet verified in a render, so it
##               never switches itself on.
##   ready       everything is there.

const GENERATED := "res://world/generated"
const TERRAIN_DATA := "res://terrain_data"
const BUILD_COMMAND := "./run.sh world"
const BUILD_NEEDS := "Python 3.11 or newer with the packages in tools/requirements.txt (pip install -r tools/requirements.txt), about 8 GB of free memory and a few minutes"
## `-- --fallback-terrain` draws the coarse ground even where Terrain3D is available: the way to
## see, test and capture what a machine without the plugin sees.
const FORCE_FALLBACK_ARG := "--fallback-terrain"
## The oldest macOS the Terrain3D 1.0.2 frameworks were built for (their LC_BUILD_VERSION).
const TERRAIN3D_MIN_MACOS := 15

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
		"forced_fallback": force_fallback or OS.get_cmdline_user_args().has(FORCE_FALLBACK_ARG),
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
		"title": "", "detail": "", "notice": "", "command": BUILD_COMMAND, "needs": BUILD_NEEDS}
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
	if not bool(f.get("terrain_class", false)):
		why = "plugin_missing"
	elif int(f.get("terrain_regions", 0)) == 0:
		why = "terrain_missing"
	if bool(f.get("forced_fallback", false)):
		# The coarse ground (FallbackTerrain) is drawn only when asked for. It is written and it
		# has not yet been looked at in a render, so it does not switch itself on: see PROGRESS.md.
		out["state"] = "fallback"
		out["terrain"] = "fallback"
		out["reason"] = why if not why.is_empty() else "forced"
		out["title"] = "The coarse ground, as asked for."
		out["detail"] = "The game was started with %s, so the ground is drawn from the 8 m height map rather than by Terrain3D." % FORCE_FALLBACK_ARG
		out["notice"] = "You are walking on the coarse ground (%s), not the full terrain." % FORCE_FALLBACK_ARG
		return out
	if why.is_empty():
		return out
	# Terrain3D cannot draw the ground here, and without a ground there is nothing to stand on:
	# the world is refused with the reason rather than entered as a void.
	out["state"] = "no_terrain"
	out["playable"] = false
	out["terrain"] = ""
	out["reason"] = why
	if why == "plugin_missing":
		out["title"] = "The ground cannot be drawn on this machine."
		out["detail"] = _plugin_missing_detail(f)
		out["command"] = "godot --path game -- %s" % FORCE_FALLBACK_ARG
	else:
		out["title"] = "The terrain has not been built."
		out["detail"] = ("The country's maps are here but game/terrain_data holds no terrain regions, so there is no ground to stand on. "
				+ "Build it from the repository's top folder with the command below. It needs %s.") % BUILD_NEEDS
	return out


## What `evaluate(facts())` says about this machine, now.
static func current() -> Dictionary:
	return evaluate(facts())


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
	return because + " Without it there is no ground to stand on. An experimental coarse ground, drawn from the 8 m height map, can be tried with the command below."
