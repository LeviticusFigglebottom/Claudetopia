#!/usr/bin/env bash
# Wickmere single entry point. See README.md.
#   ./run.sh            run the game (generates world/assets if missing)
#   ./run.sh test       import + unit tests
#   ./run.sh smoke      load every region and interior headlessly, fail on errors
#   ./run.sh journey    scripted playthrough of every promise in DESIGN's done list
#   ./run.sh quests     every authored quest played on the built world, every decision each way
#   ./run.sh fights     a scripted player against one foe of every archetype, headless
#   ./run.sh flow       boot -> title -> the Naming -> the world, pressing the buttons a player
#                       would, with a screenshot at every step -> captures/flow/
#   ./run.sh shots      headless capture plan -> captures/
#                       (./run.sh shots <plan> --preset=high --attribute  shoots at a graphics preset)
#   ./run.sh perf       measure draw calls and primitives against the budgets
#                       (./run.sh perf --preset=low  measures at a graphics preset)
#   ./run.sh world      rebuild terrain/world data from recipes, then import the terrain
#   ./run.sh terrain    import Terrain3D's regions from the maps a world build left here
#   ./run.sh godot      say which Godot this script found (GODOT names one anywhere)
#   ./run.sh assets     rebuild generated assets (needs Blender)
#   ./run.sh interiors  rebuild every cave and house from its recipe
#   ./run.sh import     (re)import the Godot project headlessly
#   ./run.sh seed-import CHECKOUT   link CHECKOUT's imported files in, then import what differs
#   ./run.sh warnings   count the GDScript warnings, and fail if the game's grew past the baseline
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME="$ROOT/game"
cmd="${1:-run}"; shift || true

# A census of the GDScript warnings (tools/debug/warning_census.py) writes game/override.cfg for
# one run of Godot and removes it after; one killed in the middle leaves it behind, and with it
# every warning is an error and the game does not start. The headless import below writes one
# too (import_project). Their first line says whose each is; anyone else's is left alone.
IMPORT_OVERRIDE_MARK="; written by run.sh for one headless import; delete it if you find it"
if [ -f "$GAME/override.cfg" ]; then
  first_line=""
  read -r first_line < "$GAME/override.cfg" || true
  case "$first_line" in
    *warning_census.py*) rm -f "$GAME/override.cfg"; echo "[run] removed a warning census's override.cfg left behind" >&2 ;;
    "$IMPORT_OVERRIDE_MARK") rm -f "$GAME/override.cfg"; echo "[run] removed an import's override.cfg left behind" >&2 ;;
  esac
fi

# What a player has to act on is said where it is seen: a banner on stderr, not one more line.
loud() {
  {
    echo ""
    echo "[run] ========================================================================"
    local line
    for line in "$@"; do echo "[run] $line"; done
    echo "[run] ========================================================================"
    echo ""
  } >&2
}

# --- Godot and Python -------------------------------------------------------------------------
# Godot is `godot` on the PATH on most Linux machines and almost nowhere else. On Windows (Git Bash
# runs this script there) it is an .exe named for its version, wherever its zip was unpacked; on a
# Mac it is inside Godot.app. A build on Windows once found no `godot`, wrote the world's maps and
# never imported the terrain, and the game ran on the coarse ground for days without anyone
# knowing why. So: GODOT if it is set, then the usual names on the PATH, then the usual places,
# a 4.7 before any other; and a command that needs Godot and has none stops and says so first.
GODOT_ASKED="${GODOT:-}"
godot_candidates() {
  local home="${HOME:-}" d f
  local dirs=("$home/Downloads" "$home/Desktop" "$home/Documents" "$home/Godot" "$home/Documents/Godot"
    "$home/bin" "$home/.local/bin" "$home/Applications" "/c/Godot" "/c/Tools" "/c/Program Files/Godot"
    "/c/Program Files (x86)/Godot" "/c/Program Files (x86)/Steam/steamapps/common/Godot Engine"
    "/c/Program Files/Steam/steamapps/common/Godot Engine" "/opt/godot")
  if [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
    local lad
    lad="$(cygpath -u "$LOCALAPPDATA")"
    dirs+=("$lad/Programs/Godot" "$lad/Godot" "$lad/Microsoft/WinGet/Links")
    for d in "$lad"/Microsoft/WinGet/Packages/GodotEngine.GodotEngine*; do dirs+=("$d"); done
  fi
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    # the console build before the other, which prints nothing to this terminal
    for f in "$d"/Godot_v4*_console.exe "$d"/*/Godot_v4*_console.exe "$d"/Godot_v4*.exe "$d"/*/Godot_v4*.exe \
        "$d"/godot.windows.*.exe "$d"/Godot_v4*_linux.x86_64 "$d"/*/Godot_v4*_linux.x86_64 \
        "$d"/Godot_v4*_linux.arm64 "$d"/*/Godot_v4*_linux.arm64; do
      if [ -f "$f" ]; then echo "$f"; fi
    done
  done
  for f in "/Applications/Godot.app/Contents/MacOS/Godot" "$home/Applications/Godot.app/Contents/MacOS/Godot"; do
    if [ -x "$f" ]; then echo "$f"; fi
  done
  return 0
}
find_godot() {
  if [ -n "$GODOT_ASKED" ]; then
    command -v "$GODOT_ASKED" 2>/dev/null || return 1
    return 0
  fi
  local name all best="" f
  for name in godot godot4 godot-4 godot.exe godot4.exe; do
    if command -v "$name" >/dev/null 2>&1; then command -v "$name"; return 0; fi
  done
  all="$(godot_candidates)"
  [ -n "$all" ] || return 1
  while IFS= read -r f; do
    case "$(basename "$f")" in Godot_v4.7*) best="$f"; break ;; esac
  done <<< "$all"
  [ -n "$best" ] || best="$(printf '%s\n' "$all" | sed -n 1p)"
  echo "$best"
}
GODOT="$(find_godot || true)"
GODOT_WARNED=""
need_godot() {
  if [ -n "$GODOT" ]; then
    # a download names its version; one that is not 4.7 may not open this project at all
    case "$(basename "$GODOT")" in
      Godot_v4.7*|godot|godot4|godot-4|godot.exe|godot4.exe|Godot) ;;
      *) if [ -z "$GODOT_WARNED" ]; then
           echo "[run] warning: $GODOT is not Godot 4.7, which this project is made in; set GODOT to a 4.7 if it will not open" >&2
           GODOT_WARNED=1
         fi ;;
    esac
    return 0
  fi
  local why="Godot 4.7 was not found: there is no godot on the PATH, and none in the usual places."
  [ -z "$GODOT_ASKED" ] || why="GODOT is set to '$GODOT_ASKED', and that is not a program this shell can run."
  loud "$why" \
    "Tell run.sh where it is with the GODOT variable (forward slashes on Windows), for example:" \
    "  Windows, Git Bash:  GODOT=\"/c/Godot/Godot_v4.7.2-stable_win64_console.exe\" ./run.sh $cmd" \
    "  macOS:              GODOT=/Applications/Godot.app/Contents/MacOS/Godot ./run.sh $cmd" \
    "  Linux:              GODOT=\$HOME/Downloads/Godot_v4.7.2-stable_linux.x86_64 ./run.sh $cmd" \
    "Nothing has been built or changed."
  exit 1
}
# Python 3.11+: PYTHON if it is set, else python3, else python. On Windows `python3` can be the
# Microsoft Store's stand-in, which runs nothing, so each is asked to run before it is trusted.
PY=""
# A tracked script without its tracked .uid, or an .import sidecar without the path and
# dest_files lines Godot writes into it: each is a change in every checkout that imports.
import_check() {
  need_python || return 0
  local out rc
  out="$("$PY" "$ROOT/tools/debug/import_check.py" 2>&1)" && rc=0 || rc=$?
  echo "$out" | tail -25
  return $rc
}

need_python() {
  [ -n "$PY" ] && return 0
  local p
  for p in ${PYTHON:+"$PYTHON"} python3 python; do
    if "$p" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then PY="$p"; return 0; fi
  done
  loud "Python 3.11 or newer was not found (tried ${PYTHON:+\$PYTHON, }python3 and python)." \
    "Building needs it, with its packages: pip install -r tools/requirements.txt" \
    "Set PYTHON to name it if it is installed under another name."
  return 1
}

# Windows (Git Bash) and macOS always have a screen and never have xvfb-run; Linux says so.
have_display() {
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*|Darwin*) return 0 ;; esac
  [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
}
xvfb() { if have_display; then "$@"; else xvfb-run -a -s "-screen 0 1600x900x24" "$@"; fi; }
# The headless import, one file at a time. Godot's threaded import deadlocks on this machine: the
# main thread spins, the workers sit idle, and 0-byte .ctex-XXXXXX temp files are all it leaves
# (twice on 2026-09-24), where one thread imports ten textures in 8 s. The switch is the project's
# editor/import/use_multiple_threads, set in a game/override.cfg written for this import alone and
# marked as run.sh's (IMPORT_OVERRIDE_MARK), so a killed import's leftover is removed by the next
# run.sh or by the warning census; an override.cfg that is somebody's own is left alone, and the
# import then runs as it is. IMPORT_LOG names a file for its output (install_world.sh keeps one).
import_project() {
  need_godot
  # Godot redoes an import only when its source's modified time has changed, so an import cache
  # linked from another checkout (seed-import) or a file whose time was kept stays stale: its
  # sources are touched first (tools/debug/import_check.py compares each import's recorded md5).
  if need_python >/dev/null 2>&1; then
    "$PY" "$ROOT/tools/debug/import_check.py" --touch-stale >&2 || true
  fi
  local ours=0
  if [ ! -e "$GAME/override.cfg" ]; then
    printf '%s\n[editor]\n\nimport/use_multiple_threads=false\n' "$IMPORT_OVERRIDE_MARK" > "$GAME/override.cfg" && ours=1
  fi
  "$GODOT" --headless --path "$GAME" --import --audio-driver Dummy >"${IMPORT_LOG:-/dev/null}" 2>&1 || true
  if [ "$ours" = "1" ] && [ -f "$GAME/override.cfg" ]; then
    local first_line=""
    read -r first_line < "$GAME/override.cfg" || true
    [ "$first_line" != "$IMPORT_OVERRIDE_MARK" ] || rm -f "$GAME/override.cfg"
  fi
}
# A fresh clone has never been imported, and `godot --path game` outside the editor cannot load a
# texture, mesh or scene that has not been: the first run imports it (a minute or two).
ensure_imported() {
  if [ ! -d "$GAME/.godot/imported" ]; then
    echo "[run] first run: importing the project (a minute or two)..."; import_project
  elif class_cache_stale; then
    echo "[run] a script names a class this checkout has not registered yet; importing to register it..."
    import_project
  fi
}
# A `class_name` is known to the game only once the import (or the editor) has written it into
# .godot/global_script_class_cache.cfg. A pull that adds one leaves an old cache behind, and every
# script that names the new class then fails to parse: after a pull added ArmRoom, HumanoidModel
# did not load and the Naming's preview stood empty. True when a script declares a class the cache
# does not list.
class_cache_stale() {
  local cache="$GAME/.godot/global_script_class_cache.cfg" name
  [ -f "$cache" ] || return 0
  for name in $(grep -rhoE '^class_name[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' --include='*.gd' \
      --exclude-dir=.godot "$GAME" 2>/dev/null | awk '{print $2}' | sort -u); do
    grep -F "&\"$name\"" "$cache" >/dev/null || return 0
  done
  return 1
}
# The built world is tracked (README.md, "Run it"), so a clone has it and nothing is built. What
# the game needs is the manifest with its runtime maps and cells, and Terrain3D's regions. If the
# regions alone are missing and the full-resolution maps are here, importing them is enough;
# otherwise the whole world is built, which needs Python 3.11+ (tools/requirements.txt), about
# 8 GB of memory and a few minutes. The title screen says the same thing if this never ran.
count_regions() {
  local n
  n="$(find "$GAME/terrain_data/" -maxdepth 1 -name 'terrain3d*.res' 2>/dev/null | wc -l || true)"
  echo "${n//[[:space:]]/}"
}
ensure_world() {
  local manifest="$GAME/world/generated/world_manifest.json"
  if [ -f "$manifest" ] && [ "$(count_regions)" != "0" ]; then return 0; fi
  if [ ! -f "$ROOT/tools/world/build_world.py" ]; then return 0; fi
  if [ -f "$manifest" ] && [ -f "$GAME/world/generated/heights.r32" ]; then
    echo "[run] the terrain regions are missing; importing them from the built maps..."
    import_terrain || true
    return 0
  fi
  echo "[run] world data missing; building it (Python 3.11+, about 8 GB, a few minutes)..."
  need_python || return 0
  if ! "$PY" "$ROOT/tools/world/build_world.py"; then
    loud "THE WORLD WAS NOT BUILT: tools/world/build_world.py failed, and its messages are above." \
      "It needs Python 3.11+ with pip install -r tools/requirements.txt, about 8 GB of free memory and a few minutes." \
      "The game still starts, and its title screen says what is missing."
    return 0
  fi
  import_terrain || true
}
ensure_interiors() {
  if [ ! -f "$GAME/assets/models/dungeon/hollin_barrow/hollin_barrow.meta.json" ]; then
    echo "[run] interiors missing; forging (this takes a while)..."
    need_python || return 0
    "$PY" "$ROOT/tools/interiors/cave_forge.py" "$ROOT"/tools/interiors/recipes/*.json --out "$GAME/assets/models/dungeon"
    "$PY" "$ROOT/tools/interiors/house_forge.py" "$ROOT"/tools/interiors/recipes/houses/*.json --out "$GAME/assets/models/interior"
    import_project
  fi
}
# Terrain3D's regions from the full-resolution maps a world build leaves in game/world/generated.
# Without them the game draws the coarse ground, so a failed import is said as loudly as a failed
# build: once it was one line at the end of minutes of output, and nobody saw it.
import_terrain() {
  need_godot
  ensure_imported
  echo "[run] importing the terrain into Terrain3D with $GODOT (a minute or two)..."
  local code=0 regions
  "$GODOT" --headless --path "$GAME" --audio-driver Dummy res://tools_gd/import_terrain.tscn || code=$?
  regions="$(count_regions)"
  if [ "$code" != "0" ] || [ "$regions" = "0" ]; then
    local left="game/terrain_data holds no regions"
    [ "$regions" = "0" ] || left="the $regions region files in game/terrain_data may be old or cut short"
    loud "THE FULL TERRAIN WAS NOT IMPORTED." \
      "The import (tools_gd/import_terrain.gd, run by $GODOT) exited $code; its messages are above." \
      "The world's maps are built, but $left." \
      "With no regions the game still runs, on the coarse 8 m ground, and says so on the title screen and in the corner." \
      "To try again:  ./run.sh terrain"
    return 1
  fi
  echo "[run] terrain imported: $regions regions in game/terrain_data"
}

case "$cmd" in
  run)
    need_godot
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
    # The GDScript warnings in the game's own scripts may not grow past their committed baseline:
    # each is an entry in a user's debugger, and there were 239 (tools/debug/warning_census.py).
    # The census takes a minute; WARNINGS=0 leaves it out of a run.
    if [ "${WARNINGS:-1}" != "0" ] && need_python; then
      census="$("$PY" "$ROOT/tools/debug/warning_census.py" --check 2>&1)" && wcode=0 || wcode=$?
      echo "$census" | sed -n '1p;/^PASS/,$p;/^FAIL/,$p'
      if [ "$wcode" -eq 2 ]; then
        # it could not be taken, which says nothing about the warnings: say why, not that they grew
        echo "[test] the warning census could not run: $(echo "$census" | grep '^warning_census:' | tail -1)"
        code=1
      elif [ "$wcode" -ne 0 ]; then
        echo "[test] the GDScript warnings in the game's scripts grew (python3 tools/debug/warning_census.py --list)"
        code=1
      fi
    fi
    # What every checkout's import would otherwise make anew or rewrite: a tracked script without
    # its tracked .uid, a sidecar without its path and dest_files (tools/debug/import_check.py).
    import_check || code=1
    exit $code ;;
  warnings)
    # Every GDScript warning, counted by kind and by file, and checked against the baseline.
    need_godot
    need_python || exit 1
    "$PY" "$ROOT/tools/debug/warning_census.py" --check "$@" ;;
  journey)
    import_project
    "$GODOT" --headless --path "$GAME" --audio-driver Dummy res://tests/journey/journey.tscn -- "$@" ;;
  quests)
    # Every authored quest played through on the built world, through the game's own services, and
    # every decision taken each way (tests/quests/quest_walker.gd). One QW line per walk and a
    # QW RESULT line; exits 1 unless every quest ends every way it can and the world put nothing
    # the quests name in water or rock.
    #   ./run.sh quests [--only=grist,vigil] [--no-branches] [--out=<file>]
    import_project
    "$GODOT" --headless --path "$GAME" --audio-driver Dummy res://tests/quests/quest_walker.tscn -- "$@" ;;
  fights)
    # A scripted player of a starting Calling against one foe of every archetype, headless and at a
    # fixed 60 fps (so it is the same run every time and costs what the machine needs, not real
    # time). Prints a FIGHT row per fight and a CHECK row per promise; exits 1 on a failed check.
    #   ./run.sh fights [--calling=hearthkeeper] [--only=pack,boss] [--trace=boss]
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
      script_errors="$(echo "$log" | grep -c "SCRIPT ERROR" || true)"
      [ "$script_errors" = "0" ] || echo "[flow] $script_errors script errors in the log (see above)"
      if echo "$log" | grep "FLOW: FAIL" >/dev/null; then echo "[flow] FAIL ($*)"; return 1; fi
      if ! echo "$log" | grep "FLOW: PASS" >/dev/null; then echo "[flow] FAIL (no verdict: $*)"; return 1; fi
    }
    # a checkout the import would change is not the one under test
    import_check || { echo "[flow] FAIL: files the import would make or rewrite (above)"; exit 1; }
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
      res://tools_gd/perf_probe.tscn -- "--out=$ROOT/captures" "$@" ;;
  shots)
    import_project
    mkdir -p "$ROOT/captures"
    plan="${1:-tools/capture/plans/default.json}"; shift || true
    xvfb "$GODOT" --path "$GAME" --rendering-driver opengl3 --audio-driver Dummy --resolution 1600x900 -- "--capture=$plan" "--out=$ROOT/captures" "$@" ;;
  world)
    # The import at the end needs Godot, so it is looked for before the build, not after it: a
    # machine without it is told at once instead of being left with maps and no terrain.
    need_godot
    need_python || exit 1
    "$PY" "$ROOT/tools/world/build_world.py" "$@"
    import_terrain ;;
  terrain)
    if [ ! -f "$GAME/world/generated/heights.r32" ]; then
      loud "game/world/generated/heights.r32 is not here: only a machine that built the world has the full-resolution maps." \
        "Build them with ./run.sh world (Python 3.11+, about 8 GB, a few minutes), which imports the terrain at the end."
      exit 1
    fi
    import_terrain ;;
  godot)
    need_godot
    echo "$GODOT"
    "$GODOT" --headless --version 2>/dev/null || true ;;
  assets)
    need_python || exit 1
    "$PY" "$ROOT/tools/forge/build_assets.py" "$@" ;;
  interiors)
    need_python || exit 1
    "$PY" "$ROOT/tools/interiors/cave_forge.py" "$ROOT"/tools/interiors/recipes/*.json --out "$GAME/assets/models/dungeon"
    "$PY" "$ROOT/tools/interiors/house_forge.py" "$ROOT"/tools/interiors/recipes/houses/*.json --out "$GAME/assets/models/interior"
    import_project ;;
  import)
    import_project ;;
  seed-import)
    # Link another checkout's imported files into this one, so a checkout on a shared disk does not
    # import every asset again, then import: whatever differs here is found stale and redone.
    src="${1:-}"
    [ -n "$src" ] && [ -d "$src/game/.godot/imported" ] \
      || { echo "usage: ./run.sh seed-import <another checkout with game/.godot/imported>" >&2; exit 2; }
    mkdir -p "$GAME/.godot/imported"
    cp -al --remove-destination "$src/game/.godot/imported/." "$GAME/.godot/imported/"
    import_project ;;
  *)
    echo "unknown command: $cmd"; exit 2 ;;
esac
