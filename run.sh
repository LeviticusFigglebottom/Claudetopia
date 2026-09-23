#!/usr/bin/env bash
# Wickmere single entry point. See README.md.
#   ./run.sh            run the game (generates world/assets if missing)
#   ./run.sh test       import + unit tests
#   ./run.sh smoke      load every region and interior headlessly, fail on errors
#   ./run.sh journey    scripted playthrough of every promise in DESIGN's done list
#   ./run.sh flow       boot -> title -> the Naming -> the world, pressing the buttons a player
#                       would, with a screenshot at every step -> captures/flow/
#   ./run.sh shots      headless capture plan -> captures/
#   ./run.sh perf       measure draw calls and primitives against the budgets
#   ./run.sh world      rebuild terrain/world data from recipes
#   ./run.sh assets     rebuild generated assets (needs Blender)
#   ./run.sh interiors  rebuild every cave and house from its recipe
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
# A fresh clone has never been imported, and `godot --path game` outside the editor cannot load a
# texture, mesh or scene that has not been: the first run imports it (a minute or two).
ensure_imported() {
  if [ ! -d "$GAME/.godot/imported" ]; then
    echo "[run] first run: importing the project (a minute or two)..."; import_project
  fi
}
# The built world is tracked (README.md, "Run it"), so a clone has it and nothing is built. What
# the game needs is the manifest with its runtime maps and cells, and Terrain3D's regions. If the
# regions alone are missing and the full-resolution maps are here, importing them is enough;
# otherwise the whole world is built, which needs Python 3.11+ (tools/requirements.txt), about
# 8 GB of memory and a few minutes. The title screen says the same thing if this never ran.
ensure_world() {
  local manifest="$GAME/world/generated/world_manifest.json"
  local regions
  regions="$(find "$GAME/terrain_data/" -maxdepth 1 -name 'terrain3d*.res' 2>/dev/null | wc -l || true)"
  if [ -f "$manifest" ] && [ "$regions" -gt 0 ]; then return 0; fi
  if [ ! -f "$ROOT/tools/world/build_world.py" ]; then return 0; fi
  if [ -f "$manifest" ] && [ -f "$GAME/world/generated/heights.r32" ]; then
    echo "[run] terrain regions missing; importing them from the built maps..."; import_terrain
  else
    echo "[run] world data missing; building it (Python 3.11+, about 8 GB, a few minutes)..."
    "$PY" "$ROOT/tools/world/build_world.py" && import_terrain
  fi
}
ensure_interiors() {
  if [ ! -f "$GAME/assets/models/dungeon/hollin_barrow/hollin_barrow.meta.json" ]; then
    echo "[run] interiors missing; forging (this takes a while)..."
    "$PY" "$ROOT/tools/interiors/cave_forge.py" "$ROOT"/tools/interiors/recipes/*.json --out "$GAME/assets/models/dungeon"
    "$PY" "$ROOT/tools/interiors/house_forge.py" "$ROOT"/tools/interiors/recipes/houses/*.json --out "$GAME/assets/models/interior"
    import_project
  fi
}
import_terrain() {
  "$GODOT" --headless --path "$GAME" --audio-driver Dummy res://tools_gd/import_terrain.tscn
}

case "$cmd" in
  run)
    ensure_imported
    ensure_interiors
    ensure_world
    exec "$GODOT" --path "$GAME" "$@" ;;
  test)
    import_project
    # The engine's SCRIPT ERRORs cannot be counted from inside GDScript, and they are not
    # cosmetic: an invalid call abandons the rest of the function, so one inside a test means the
    # assertions after it never ran. stderr is the honest count, so it is read here and it fails
    # the run. The tests' own logged errors are counted and attributed by tests/test_runner.gd.
    out="$("$GODOT" --headless --path "$GAME" --audio-driver Dummy res://tests/run_tests.tscn -- "$@" 2>&1 | tee /dev/stderr)" || true
    code=0
    # Never `echo "$out" | grep -q` under pipefail: grep -q stops reading at its match, echo can
    # take a SIGPIPE writing the rest, and the pipeline fails with the verdict in it (3 runs in
    # 50 on a passing suite's 215 KB). A grep that reads to the end cannot race.
    echo "$out" | grep "^RESULT: PASS" >/dev/null || code=1
    n="$(echo "$out" | grep -c "^SCRIPT ERROR" || true)"
    if [ "$n" -gt 0 ]; then
      echo "[test] $n script error(s) logged by the engine, at:"
      echo "$out" | grep -A1 "^SCRIPT ERROR" | grep "at:" | sed 's/^ *at: /  /' | sort | uniq -c
      code=1
    fi
    echo "[test] script errors: $n"
    # A closure the engine calls after the object it captured has been freed says so on stderr
    # and nowhere else: it is not a SCRIPT ERROR, GDScript cannot count it, and the run stayed
    # green through 139 of them. The listener is still connected, so whatever the closure was
    # for silently does not happen. Read it here, for the same reason as the line above.
    l="$(echo "$out" | grep -c "Lambda capture at index" || true)"
    if [ "$l" -gt 0 ]; then
      echo "[test] $l lambda capture(s) fired after the object they captured was freed"
      code=1
    fi
    echo "[test] dead lambda captures: $l"
    exit $code ;;
  journey)
    import_project
    "$GODOT" --headless --path "$GAME" --audio-driver Dummy res://tests/journey/journey.tscn -- "$@" ;;
  flow)
    # Three starts, each from boot.tscn with the probe attached: the title menu's New Game
    # through the Naming into the world (which also saves the slot the next two need), then
    # --load=<slot> straight in, then the title menu's Continue. Any black world, missing HUD
    # or unpressable button fails the run; the PNGs are there to be looked at either way.
    import_project
    out="${FLOW_OUT:-$ROOT/captures/flow}"
    mkdir -p "$out"
    flow_run() {
      local log
      log="$(xvfb "$GODOT" --path "$GAME" --rendering-driver opengl3 --audio-driver Dummy \
        --resolution "${FLOW_RES:-1280x720}" -- "--flow=$out" "$@" 2>&1 | tee /dev/stderr)" || true
      local script_errors
      script_errors="$(echo "$log" | grep -c "SCRIPT ERROR" || true)"
      [ "$script_errors" = "0" ] || echo "[flow] $script_errors script errors in the log (see above)"
      if echo "$log" | grep "FLOW: FAIL" >/dev/null; then echo "[flow] FAIL ($*)"; return 1; fi
      if ! echo "$log" | grep "FLOW: PASS" >/dev/null; then echo "[flow] FAIL (no verdict: $*)"; return 1; fi
    }
    # An `&&` list that fails part-way does not trip `set -e`, so this said PASS and exited 0
    # whatever the runs found; the verdict has to be taken from the list itself.
    if flow_run "$@" && flow_run "--load=flow" && flow_run "--continue"; then
      echo "[flow] PASS: $out"
    else
      echo "[flow] FAIL: $out"; exit 1
    fi ;;
  smoke)
    import_project
    out="$("$GODOT" --headless --path "$GAME" --audio-driver Dummy -- --smoke "$@" 2>&1 | tee /dev/stderr)"
    if echo "$out" | grep -E "SCRIPT ERROR|SMOKE: FAIL" >/dev/null; then echo "[smoke] FAIL"; exit 1; fi
    if ! echo "$out" | grep "SMOKE: PASS" >/dev/null; then echo "[smoke] FAIL (no verdict)"; exit 1; fi
    echo "[smoke] PASS" ;;
  perf)
    import_project
    mkdir -p "$ROOT/captures"
    xvfb "$GODOT" --path "$GAME" --audio-driver Dummy --resolution 1600x900 \
      res://tools_gd/perf_probe.tscn -- "--out=$ROOT/captures" ;;
  shots)
    import_project
    mkdir -p "$ROOT/captures"
    plan="${1:-tools/capture/plans/default.json}"
    xvfb "$GODOT" --path "$GAME" --rendering-driver opengl3 --audio-driver Dummy --resolution 1600x900 -- "--capture=$plan" "--out=$ROOT/captures" ;;
  world)
    "$PY" "$ROOT/tools/world/build_world.py" "$@" && import_terrain ;;
  assets)
    "$PY" "$ROOT/tools/forge/build_assets.py" "$@" ;;
  interiors)
    "$PY" "$ROOT/tools/interiors/cave_forge.py" "$ROOT"/tools/interiors/recipes/*.json --out "$GAME/assets/models/dungeon"
    "$PY" "$ROOT/tools/interiors/house_forge.py" "$ROOT"/tools/interiors/recipes/houses/*.json --out "$GAME/assets/models/interior"
    import_project ;;
  import)
    import_project ;;
  *)
    echo "unknown command: $cmd"; exit 2 ;;
esac
