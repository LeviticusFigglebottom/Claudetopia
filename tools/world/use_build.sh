#!/usr/bin/env bash
# Run the game on a world build without committing it: copy a build directory (what
# tools/world/build_world.py --out writes) into this checkout's game/world/generated, and its
# Terrain3D regions into game/terrain_data, then test, journey or capture as usual. Both
# directories are tracked (main's world), so NEVER stage anything under them after this;
# `--restore` puts the committed world back. See docs/COORDINATES.md for what to check.
#
#   tools/world/use_build.sh <build dir> [<terrain dir>]   # no terrain dir: import it here
#   tools/world/use_build.sh --restore
#
# The import (when no terrain dir is given) runs Godot headless, about 20 s and 1-2 GB; it also
# rewrites game/world/terrain_assets.tres, which should come out unchanged. Wait for any
# WORLD_BUILD lock and for memory first: only one Godot at a time on a shared machine.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1
GEN=game/world/generated
TERR=game/terrain_data

if [ "${1:-}" = "--restore" ]; then
  rm -rf "$GEN" "$TERR"
  git checkout -- "$GEN" "$TERR"
  echo "[use_build] restored the committed world: $(git ls-files "$GEN" | wc -l) generated files, $(ls "$TERR" | wc -l) terrain regions"
  git status --short "$GEN" "$TERR" | head -3
  exit 0
fi

src="${1:-}"
terr="${2:-}"
[ -f "$src/world_manifest.json" ] || { echo "usage: $0 <build dir> [<terrain dir>] | --restore (no world_manifest.json in '$src')"; exit 2; }
if [ -n "$terr" ] && ! ls "$terr"/terrain3d*.res > /dev/null 2>&1; then
  echo "no terrain3d*.res in $terr"; exit 2
fi
rm -rf "$GEN.new" "$TERR.new"
mkdir -p "$GEN.new"
cp -r "$src"/. "$GEN.new"/ || exit 1
rm -rf "$GEN"
mv "$GEN.new" "$GEN"
if [ -n "$terr" ]; then
  mkdir -p "$TERR.new"
  cp -r "$terr"/. "$TERR.new"/ || exit 1
  rm -rf "$TERR"
  mv "$TERR.new" "$TERR"
else
  start=$(date +%s)
  godot --headless --path game --audio-driver Dummy res://tools_gd/import_terrain.tscn > /tmp/use_build_import.log 2>&1
  echo "[use_build] terrain import rc=$? in $(( $(date +%s) - start )) s"
  grep -E "ImportTerrain\]" /tmp/use_build_import.log | tail -2
fi
python3 - "$GEN/world_manifest.json" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1]))
print("[use_build] built %s, atlas %s, grid %s, %s POIs, start %s" % (
    m.get("built_at"), m.get("atlas", {}).get("crc"), m.get("grid"), m.get("pois"), m.get("start")))
EOF
echo "[use_build] $(ls "$TERR" | wc -l) terrain regions. Do not stage $GEN or $TERR; '$0 --restore' puts the committed world back."
