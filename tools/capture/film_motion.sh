#!/usr/bin/env bash
# Films a motion-studio plan (game/tools_gd/motion_studio.gd) on Forward+ under xvfb, at a fixed
# 60 fps, so every frame is one physics tick and the load on the machine does not change what is
# filmed. Then tiles each sequence's frames into one sheet with tools/capture/motion_sheets.py.
#
#   tools/capture/film_motion.sh tools/capture/plans/turns_and_ways.json captures/turns [opengl3]
#
# The frames and <out>/motion.txt (where each foot and the body were at every shot) land in <out>,
# the sheets in <out>/sheets. Needs xvfb-run, and Mesa's Vulkan (lavapipe) for Forward+.
set -u
plan="${1:?plan, relative to the repo root}"
out="${2:?output directory}"
renderer="${3:-forward_plus}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
source "$root/tools/godot_env.sh"   # this checkout's own user://, from the shipped settings
wickmere_default_settings
case "$out" in /*) ;; *) out="$root/$out" ;; esac
mkdir -p "$out"
if [ "$renderer" = "opengl3" ]; then
  flags=(--rendering-driver opengl3)
else
  flags=(--rendering-driver vulkan --rendering-method forward_plus)
fi
cd "$root" || exit 1
timeout 1500 xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path game "${flags[@]}" \
  --audio-driver Dummy --resolution 1280x720 --fixed-fps 60 res://tools_gd/motion_studio.tscn -- \
  "--plan=$plan" "--out=$out" > "$out/run.log" 2>&1
code=$?
grep -E "MOTION|SCRIPT ERROR" "$out/run.log" | head -10
python3 "$root/tools/capture/motion_sheets.py" "$out" "$out/sheets" 6
exit $code
