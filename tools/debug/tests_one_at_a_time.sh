#!/bin/bash
# Runs test files one after another, one Godot at a time, each only when the machine has the
# memory for it, and writes a line per file to $OUT/summary.txt.
#
#   OUT=/some/dir tools/debug/tests_one_at_a_time.sh test_talk_to_the_warden test_dialogue_runner
#
# BUILD_LOCK names a file another job holds while it builds the world; while it exists and is under
# 45 minutes old, the next file waits. MIN_FREE_MB is the memory a run waits for (4500 by default).
cd "$(dirname "$0")/../.." || exit 1
OUT=${OUT:-/tmp/wickmere_tests}
MIN_FREE_MB=${MIN_FREE_MB:-4500}
mkdir -p "$OUT"
locked() {
	[ -n "$BUILD_LOCK" ] && [ -e "$BUILD_LOCK" ] || return 1
	[ $(( $(date +%s) - $(stat -c %Y "$BUILD_LOCK") )) -lt 2700 ]
}
: > "$OUT/summary.txt"
for f in "$@"; do
	while locked || [ "$(free -m | awk '/Mem:/{print $7}')" -lt "$MIN_FREE_MB" ]; do sleep 15; done
	timeout 1500 ./run.sh test "--filter=$f" > "$OUT/$f.log" 2>&1
	code=$?
	echo "$f exit $code: $(grep -E '^RESULT|tests,' "$OUT/$f.log" | tr '\n' ' ') $(grep -E '\[test\] script errors' "$OUT/$f.log")" >> "$OUT/summary.txt"
done
echo "done $(date +%H:%M:%S)" >> "$OUT/summary.txt"
