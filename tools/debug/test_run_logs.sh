#!/usr/bin/env bash
# A redirected run keeps every line: `./run.sh flow > f 2>&1` must hold all three ways in.
#
#   tools/debug/test_run_logs.sh      (seconds; no real Godot is started)
#
# run.sh once showed each Godot run's output with `| tee /dev/stderr`. tee opens /dev/stderr
# afresh, and when stderr is a file that open truncates it, so each run wiped the one before: a
# flow log held only the Continue, and the New Game's failures were gone. This runs run.sh's flow
# and smoke with a stand-in Godot that says a line per run, stderr and stdout redirected to one
# file, and fails unless every line is there once, in order.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
mkdir -p "$work/bin"
# the stand-in: named godot, so run.sh takes it for one; it says which way in it was asked for
cat > "$work/bin/godot" <<'EOF'
#!/usr/bin/env bash
way="new"
for a in "$@"; do
  case "$a" in
    --load=*) way="load" ;;
    --continue) way="continue" ;;
    --smoke) way="smoke" ;;
    --import) echo "stand-in import"; exit 0 ;;
  esac
done
echo "stand-in run: $way"
if [ "$way" = "smoke" ]; then echo "SMOKE: PASS"; else echo "FLOW: PASS ($way: 1 checks, 0 failed, 0 errors logged)"; fi
EOF
chmod +x "$work/bin/godot"
fail=0
check() {  # file, pattern, how many
  local n
  n="$(grep -c -- "$2" "$1" || true)"
  if [ "$n" != "$3" ]; then
    echo "FAIL: $(basename "$1") has $n line(s) of '$2', not $3"
    fail=1
  fi
}
GODOT="$work/bin/godot" FLOW_OUT="$work/flow" WICKMERE_USER_HOME="$work/user" \
  "$ROOT/run.sh" flow > "$work/flow.log" 2>&1
check "$work/flow.log" "stand-in run: new" 1
check "$work/flow.log" "stand-in run: load" 1
check "$work/flow.log" "stand-in run: continue" 1
check "$work/flow.log" "^\[flow\] PASS" 1
# in order: the New Game's line is still first
first="$(grep -m1 'stand-in run:' "$work/flow.log")"
[ "$first" = "stand-in run: new" ] || { echo "FAIL: the first run in the log is '$first'"; fail=1; }
GODOT="$work/bin/godot" WICKMERE_USER_HOME="$work/user" "$ROOT/run.sh" smoke > "$work/smoke.log" 2>&1
check "$work/smoke.log" "stand-in run: smoke" 1
check "$work/smoke.log" "^\[smoke\] PASS" 1
if [ "$fail" = "0" ]; then
  echo "PASS: a redirected flow keeps all three ways in, and smoke its run"
  rm -rf "$work"
else
  echo "logs kept in $work"
fi
exit $fail
