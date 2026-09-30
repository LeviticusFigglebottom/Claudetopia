#!/usr/bin/env bash
# The Mac smoke test (.github/workflows/game-build.yml, mac-smoke), on a real Mac: starts the
# exported Wickmere.app headless into a new game and waits for the world to say it is ready. The
# exported game has no smoke runner (tests/ is not exported) and a release build ignores --script,
# so the world's own log line is the proof:
#   "[World] ready: terrain=terrain3d, ..." in user://logs/wickmere.log
# means Terrain3D's framework loaded, its classes read their regions out of the pack, and the pack's
# world data and scenes loaded. terrain=fallback, no line within the time, an early exit, a script
# error or a library that did not open fails it.
#
#   tools/release/mac_smoke.sh <Wickmere.app> <label> [launcher ...]
#   e.g. tools/release/mac_smoke.sh "$APP" arm64
#        tools/release/mac_smoke.sh "$APP" x86_64 arch -x86_64      # under Rosetta
# Writes smoke-<label>.out (stdout and stderr), wickmere-<label>.log and godot-<label>.log here.
set -u
app="$1"; label="$2"; shift 2
logs="${SMOKE_LOGS:-$HOME/Library/Application Support/Godot/app_userdata/Wickmere/logs}"
rm -rf "$logs"
limit="${SMOKE_SECONDS:-420}"

"$@" "$app/Contents/MacOS/Wickmere" --headless -- --new-game > "smoke-$label.out" 2>&1 &
pid=$!
verdict="no world after ${limit} s"
start=$(date +%s)
while [ $(( $(date +%s) - start )) -lt "$limit" ]; do
  sleep 2
  if [ -f "$logs/wickmere.log" ] && grep -q "\[World\] ready: terrain=" "$logs/wickmere.log"; then
    verdict="ready"
    break
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid"; verdict="the game exited early (code $?)"
    break
  fi
done
took=$(( $(date +%s) - start ))
kill "$pid" 2>/dev/null; sleep 5; kill -9 "$pid" 2>/dev/null
cp "$logs/wickmere.log" "wickmere-$label.log" 2>/dev/null || true
cp "$logs/godot.log" "godot-$label.log" 2>/dev/null || true

fail=""
[ "$verdict" = "ready" ] || fail="$verdict"
line=$(grep -h "\[World\] ready: terrain=" "wickmere-$label.log" 2>/dev/null | head -1)
case "$line" in
  *terrain=terrain3d*) ;;
  "") ;;
  *) fail="${fail:+$fail; }the world drew the coarse ground, not Terrain3D: $(grep -h "\[World\]" "wickmere-$label.log" | grep -v ready | head -2)" ;;
esac
if grep -h -E "SCRIPT ERROR|Can't open dynamic library|Error loading extension" "godot-$label.log" "smoke-$label.out" 2>/dev/null | head -5 | grep .; then
  fail="${fail:+$fail; }errors above"
fi
echo "[$label] after ${took} s: ${line:-no ready line}"
if [ -n "$fail" ]; then
  echo "[$label] FAIL: $fail"
  grep -E "^(W|E) " "wickmere-$label.log" 2>/dev/null | tail -15
  exit 1
fi
echo "[$label] PASS"
