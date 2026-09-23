#!/usr/bin/env bash
# Runs one capture plan at 1280x720 and writes its frames, and a log beside them, where you say.
#
#   tools/capture/run_plan.sh <plan.json> <out_dir> [compat|forward] [more args for the capture]
#
#   compat   Compatibility (OpenGL), on the built terrain. The default.
#   forward  Forward+ (Vulkan). On a machine with only software Vulkan the terrain is the
#            fallback mesh, because Terrain3D is kept off it (DECISIONS).
#
# Pass --attribute after the renderer to have the capture count draw calls and primitives by
# owner (DrawAttribution) on each shot. For DESIGN section 11's budget, that is the streets plan's
# Merrowby shot alone:
#
#   tools/capture/run_plan.sh tools/capture/plans/budget_merrowby.json captures/budget compat --attribute
#
# A capture holds 3-4 GB. On a machine shared with other runs, whatever runs out first is killed,
# so this waits for MIN_FREE_GB (4 by default) to be available before it starts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
plan="$1"; out="$2"; shift 2
renderer="compat"
if [ "${1:-}" = "compat" ] || [ "${1:-}" = "forward" ]; then renderer="$1"; shift; fi
GODOT="${GODOT:-godot}"
case "$plan" in /*) ;; *) plan="$ROOT/$plan" ;; esac
case "$out" in /*) ;; *) out="$ROOT/$out" ;; esac
mkdir -p "$out"
need="${MIN_FREE_GB:-4}"
while [ "$(free -g | awk '/^Mem:/{print $7}')" -lt "$need" ]; do
  echo "[capture] waiting for ${need} GB of memory"; sleep 60
done
args=(--path "$ROOT/game" --audio-driver Dummy --resolution 1280x720)
extra=()
if [ "$renderer" = "forward" ]; then
  args+=(--rendering-driver vulkan --rendering-method forward_plus)
  extra+=(--terrain=fallback)
else
  args+=(--rendering-driver opengl3)
fi
run() { if [ -n "${DISPLAY:-}" ]; then "$@"; else xvfb-run -a -s "-screen 0 1280x720x24" "$@"; fi; }
code=0
run "$GODOT" "${args[@]}" -- "--capture=$plan" "--out=$out" ${extra[@]+"${extra[@]}"} "$@" > "$out.log" 2>&1 || code=$?
grep -E "\[Capture\] [a-z0-9_]+: |worst frame" "$out.log" || true
errors="$(grep -c "SCRIPT ERROR" "$out.log" || true)"
echo "[capture] exit $code, $errors script errors; frames in $out, log in $out.log"
exit "$code"
