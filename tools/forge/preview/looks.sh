#!/bin/bash
# A lineup of looks in the engine, each from four sides, through game/tools_gd/character_review.
#
#   tools/forge/preview/looks.sh <outdir> <looks.json> [--pose=Walk@0.51] [--frame=hands] [--no-child-rig]
#
# <looks.json> is a list of appearances (height, build, skin, hair_colour, culture, parts by slot);
# tools/forge/preview/looks/ has the lineups the characters were judged on. Renders with the
# Compatibility renderer under Xvfb at 1280x720; the pictures and review.log land in <outdir>.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tools/godot_env.sh"   # this checkout's own user://, from the shipped settings
wickmere_default_settings
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
LOOKS="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
shift 2
cd "$ROOT" || exit 2
timeout 600 xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 --audio-driver Dummy \
  --resolution 1280x720 res://tools_gd/character_review.tscn -- "--out=$OUT" "--looks=$LOOKS" "$@" > "$OUT/review.log" 2>&1
echo "exit $?"
grep -E "REVIEW|SCRIPT ERROR|ERROR" "$OUT/review.log" | head -20
