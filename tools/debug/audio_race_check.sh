#!/bin/bash
# Regression check for the engine's audio race (game/systems/audio/audio_guard.gd).
#
# Holds only Godot's mixing thread, under gdb, between loading a sound's bus details and copying
# them (tools/debug/stall_mixer.py), while game/tools_gd/audio_race.gd keeps sounds playing:
#   1. without the guard (-- --no-audio-guard) the program must crash, with the mixer's backtrace;
#   2. with the guard it must run its full time and exit.
# Frames are paced at 60 a second (--realtime), as a game's are. Needs gdb and the official 4.7.2
# Linux build (the stall address is that build's; see stall_mixer.py). Exits non-zero on failure.
#
#   tools/debug/audio_race_check.sh [seconds] [stall_us]
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tools/godot_env.sh"   # this checkout's own user://
GODOT="${GODOT:-godot}"
SECS="${1:-40}"
STALL="${2:-20000}"
OUT="$(mktemp -d)"
run() {
  local tag="$1"; shift
  ( sleep $((SECS + 30)) | STALL_US="$STALL" timeout $((SECS + 60)) gdb -q -x "$ROOT/tools/debug/stall_mixer.py" --args \
      "$GODOT" --headless --path "$ROOT/game" --audio-driver Dummy --script res://tools_gd/audio_race.gd -- \
      --seconds="$SECS" --churn --players=4 --realtime "$@" ) > "$OUT/$tag.log" 2>&1
  grep -E "^STALL|AUDIO_RACE \| survived" "$OUT/$tag.log" | head -3
}
echo "== without the guard"
run unguarded --no-audio-guard
echo "== with the guard"
run guarded
fail=0
if ! grep -q "then SIGSEGV" "$OUT/unguarded.log"; then
  echo "FAIL: without the guard the stalled mixer did not crash (the reproduction no longer reproduces)"
  fail=1
elif ! grep -q "0x00000000048f7c1\|0x00000000048f7c2" "$OUT/unguarded.log"; then
  echo "FAIL: it crashed, but not in the StringName copy the engine race crashes in"
  fail=1
fi
if grep -q "then SIG" "$OUT/guarded.log" || ! grep -q "AUDIO_RACE | survived" "$OUT/guarded.log"; then
  echo "FAIL: with the guard the stalled mixer still crashed or did not finish"
  fail=1
fi
[ $fail -eq 0 ] && echo "PASS: crashes without the guard, runs its time with it (logs in $OUT)"
exit $fail
