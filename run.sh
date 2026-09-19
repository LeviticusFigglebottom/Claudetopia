#!/usr/bin/env bash
# Wickmere single entry point. See README.md.
#   ./run.sh            run the game (generates world/assets if missing)
#   ./run.sh test       import + unit tests
#   ./run.sh smoke      load every region and interior headlessly, fail on errors
#   ./run.sh shots      headless capture plan -> captures/
#   ./run.sh world      rebuild terrain/world data from recipes
#   ./run.sh assets     rebuild generated assets (needs Blender)
#   ./run.sh import     (re)import the Godot project headlessly
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="${GODOT:-godot}"
PY="${PYTHON:-python3}"
GAME="$ROOT/game"
cmd="${1:-run}"; shift || true

have_display() { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }
xvfb() { if have_display; then "$@"; else xvfb-run -a -s "-screen 0 1600x900x24" "$@"; fi; }
import_project() { "$GODOT" --headless --path "$GAME" --import --audio-driver Dummy >/dev/null 2>&1 || true; }
ensure_world() {
  if [ ! -f "$GAME/world/generated/world_manifest.json" ]; then
    echo "[run] world data missing; building..."; "$PY" "$ROOT/tools/world/build_world.py" && import_terrain
  fi
}
import_terrain() {
  "$GODOT" --headless --path "$GAME" --audio-driver Dummy res://tools_gd/import_terrain.tscn
}

case "$cmd" in
  run)
    ensure_world
    exec "$GODOT" --path "$GAME" "$@" ;;
  test)
    import_project
    "$GODOT" --headless --path "$GAME" --audio-driver Dummy res://tests/run_tests.tscn -- "$@" ;;
  smoke)
    import_project
    out="$("$GODOT" --headless --path "$GAME" --audio-driver Dummy -- --smoke "$@" 2>&1 | tee /dev/stderr)"
    if echo "$out" | grep -qE "^ERROR:|SCRIPT ERROR|SMOKE: FAIL"; then echo "[smoke] FAIL"; exit 1; fi
    echo "[smoke] PASS" ;;
  shots)
    import_project
    mkdir -p "$ROOT/captures"
    plan="${1:-tools/capture/plans/default.json}"
    xvfb "$GODOT" --path "$GAME" --rendering-driver opengl3 --audio-driver Dummy --resolution 1600x900 -- "--capture=$plan" "--out=$ROOT/captures" ;;
  world)
    "$PY" "$ROOT/tools/world/build_world.py" "$@" && import_terrain ;;
  assets)
    "$PY" "$ROOT/tools/forge/build_assets.py" "$@" ;;
  import)
    import_project ;;
  *)
    echo "unknown command: $cmd"; exit 2 ;;
esac
