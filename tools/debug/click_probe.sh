#!/usr/bin/env bash
# Presses a title button at several moments while the country behind the title stands up, one fresh
# launch each, and says whether the game went on (game/tools_gd/click_probe.gd). A player's first
# click on a fresh PC froze the game for good; docs/FIRST_LAUNCH.md.
#
#   tools/debug/click_probe.sh [--terrain=terrain3d|fallback] [--button="New Game"] [--times="0.5 1 2 4 8"] [--repeat=1]
#
# Drawn with the Compatibility renderer under xvfb (it draws Terrain3D here). GODOT names Godot, as
# for run.sh. Every launch gets an empty user:// of its own, as a player's first launch has.
# Exits 1 if any launch failed its verdict.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
terrain="--terrain=terrain3d"; button="New Game"; times="0.5 1 2 4 8"; repeat=1
for a in "$@"; do
  case "$a" in
    --terrain=*) terrain="$a" ;;
    --button=*) button="${a#--button=}" ;;
    --times=*) times="${a#--times=}" ;;
    --repeat=*) repeat="${a#--repeat=}" ;;
  esac
done
out="${CLICK_OUT:-$ROOT/captures/click_probe}"
mkdir -p "$out"
results="$out/results.txt"
: > "$results"
code=0
for r in $(seq 1 "$repeat"); do
  for t in $times; do
    home="$(mktemp -d)"
    log="$out/click_${t}_${r}.log"
    XDG_DATA_HOME="$home" xvfb-run -a -s "-screen 0 1280x720x24" timeout -s KILL 150 \
      "$GODOT" --path "$ROOT/game" --rendering-driver opengl3 --audio-driver Dummy -- \
      "$terrain" "--click=$t:$button" "--click-out=$results" > "$log" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then code=1; fi
    if ! grep -q "^CLICK at=" "$log"; then
      echo "CLICK at=$t button=$button went_on=NO (no verdict: exit $rc, a hang or a crash; $log)" | tee -a "$results"
      code=1
    else
      grep "^CLICK at=" "$log"
    fi
    rm -rf "$home"
  done
done
echo "[click_probe] $(grep -c 'verdict=PASS' "$results") passed of $(grep -c '^CLICK' "$results"); $results"
exit $code
