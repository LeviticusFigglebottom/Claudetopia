#!/usr/bin/env bash
# install_world.sh BUILD: put a world built outside the checkout (build_world.py --out BUILD, or
# build_when_free.sh) into this checkout, as `./run.sh world` leaves one it built in place:
#
#   1. BUILD replaces game/world/generated whole (nothing of the old world is left in it);
#   2. Godot imports the project once, so the class cache knows every script the game names (a
#      stale cache made later scene runs fail to compile);
#   3. the terrain import (tools_gd/import_terrain.tscn, what `./run.sh terrain` runs) writes
#      Terrain3D's regions into game/terrain_data from the full-resolution maps.
#
# Its log is BUILD.import.log. Keep a copy of game/terrain_data afterwards to install the same
# world elsewhere without importing it again. None of this is committed: put the tracked world
# back with `git checkout -- game/world/generated game/terrain_data` (the builder's untracked
# full-resolution maps stay behind; they are ignored, and `./run.sh world` writes them again).
set -u
repo="$(cd "$(dirname "$0")/../.." && pwd)"
src="${1:-}"
[ -n "$src" ] && [ -f "$src/world_manifest.json" ] || { echo "usage: $0 BUILD (no world_manifest.json in '$src')" >&2; exit 2; }
src="$(cd "$src" && pwd)"
dst="$repo/game/world/generated"
rm -rf "$dst.new"
mkdir -p "$dst.new"
cp -r "$src"/. "$dst.new"/
rm -rf "$dst.old"
mv "$dst" "$dst.old"
mv "$dst.new" "$dst"
rm -rf "$dst.old"
cd "$repo"
start=$(date +%s)
# run.sh's import: one file at a time, since the threaded one deadlocks on this machine (run.sh,
# import_project, says how and why)
IMPORT_LOG="$src.import.log" ./run.sh import
godot --headless --path game --audio-driver Dummy res://tools_gd/import_terrain.tscn >> "$src.import.log" 2>&1
rc=$?
echo "[install] terrain import rc=$rc wall=$(( $(date +%s) - start ))s, log $src.import.log"
grep -E "ImportTerrain\]" "$src.import.log" | tail -3
exit $rc
