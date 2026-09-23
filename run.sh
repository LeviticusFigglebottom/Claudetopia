#!/usr/bin/env bash
# Wickmere single entry point. See README.md.
#   ./run.sh            run the game (generates world/assets if missing)
#   ./run.sh test       import + unit tests
#   ./run.sh smoke      load every region and interior headlessly, fail on errors
#   ./run.sh journey    scripted playthrough of every promise in DESIGN's done list
#   ./run.sh fights     a scripted player against one foe of every archetype, headless
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
ensure_world() {
  if [ ! -f "$GAME/world/generated/world_manifest.json" ] && [ -f "$ROOT/tools/world/build_world.py" ]; then
    echo "[run] world data missing; building..."; "$PY" "$ROOT/tools/world/build_world.py" && import_terrain
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
    # Every check on the output reads it from a here-string, never `echo | grep -q`: under
    # pipefail, grep -q leaving at the first match can kill the echo still writing a 200 KB log,
    # and the pipeline then fails -- this line reported four green runs in five as failures.
    grep -q "^RESULT: PASS" <<<"$out" || code=1
    n="$(grep -c "^SCRIPT ERROR" <<<"$out" || true)"
    if [ "$n" -gt 0 ]; then
      echo "[test] $n script error(s) logged by the engine, at:"
      grep -A1 "^SCRIPT ERROR" <<<"$out" | grep "at:" | sed 's/^ *at: /  /' | sort | uniq -c
      code=1
    fi
    echo "[test] script errors: $n"
    # A closure the engine calls after the object it captured has been freed says so on stderr
    # and nowhere else: it is not a SCRIPT ERROR, GDScript cannot count it, and the run stayed
    # green through 139 of them. The listener is still connected, so whatever the closure was
    # for silently does not happen. Read it here, for the same reason as the line above.
    l="$(grep -c "Lambda capture at index" <<<"$out" || true)"
    if [ "$l" -gt 0 ]; then
      echo "[test] $l lambda capture(s) fired after the object they captured was freed"
      code=1
    fi
    echo "[test] dead lambda captures: $l"
    exit $code ;;
  journey)
    import_project
    "$GODOT" --headless --path "$GAME" --audio-driver Dummy res://tests/journey/journey.tscn -- "$@" ;;
  fights)
    # A scripted player of a starting Calling against one foe of every archetype, headless and at a
    # fixed 60 fps (so it is the same run every time and costs what the machine needs, not real
    # time). Prints a FIGHT row per fight and a CHECK row per promise; exits 1 on a failed check.
    #   ./run.sh fights [--calling=hearthkeeper]
    import_project
    "$GODOT" --headless --path "$GAME" --audio-driver Dummy --fixed-fps 60 res://tests/arena/fights.tscn -- "$@" ;;
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
      script_errors="$(grep -c "SCRIPT ERROR" <<<"$log" || true)"
      [ "$script_errors" = "0" ] || echo "[flow] $script_errors script errors in the log (see above)"
      if grep -q "FLOW: FAIL" <<<"$log"; then echo "[flow] FAIL ($*)"; return 1; fi
      if ! grep -q "FLOW: PASS" <<<"$log"; then echo "[flow] FAIL (no verdict: $*)"; return 1; fi
    }
    flow_run "$@" && flow_run "--load=flow" && flow_run "--continue"
    echo "[flow] PASS: $out" ;;
  smoke)
    import_project
    out="$("$GODOT" --headless --path "$GAME" --audio-driver Dummy -- --smoke "$@" 2>&1 | tee /dev/stderr)"
    if grep -qE "SCRIPT ERROR|SMOKE: FAIL" <<<"$out"; then echo "[smoke] FAIL"; exit 1; fi
    if ! grep -q "SMOKE: PASS" <<<"$out"; then echo "[smoke] FAIL (no verdict)"; exit 1; fi
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
