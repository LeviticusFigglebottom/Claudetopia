#!/usr/bin/env bash
# The cartographer's sweep for right after a world build lands in the tracked world: are the roads
# still signed, how thin are they and how armed, do the cameras still see what they look at, and
# what the new things look like.
#
#   tools/world/atlas/after_build.sh                 # the checks, and the capture command to run
#   GATE="$SCRATCH/gate.sh 4" tools/world/atlas/after_build.sh --shoot   # and take the captures
#   WORLD=/path/to/build tools/world/atlas/after_build.sh   # cameras on the build's full heights
#
# 1. signposts.json against the built roads. The build meanders the roads again from the atlas, so
#    a junction can move. If the file differs, it is rewritten, and it wants committing before the
#    next build stands the posts.
# 2. The gap map and the road threats: thin road, empty country, threats met and quiet runs.
# 3. check_atlas and the hook table.
# 4. The POI plan remade on the new pads. Waves 5 and 6 were shot from their defs' positions until
#    now. It is frame-checked with the ground shots, and with the capture, signpost and gap-map
#    tests.
# 5. The captures of tools/capture/plans/after_signposts.json: three junctions' fingerposts, a town
#    stone, six of the new finds on their pads, and two of wave 6's threats with a body standing
#    by. Only with --shoot, and through the gate.
set -u
cd "$(dirname "$0")/../../.."
OUT="${OUT:-captures/after_build}"
# the build's own directory, with its full-size heights, for the cameras: the tracked world has only
# the runtime maps, and the committed POI plan is made on the full heights
WORLD="${WORLD:-game/world/generated}"
step() { printf '\n== %s\n' "$*"; }

step "1. the signposts against the built roads"
if ! python3 tools/world/atlas/signposts.py --check; then
  python3 tools/world/atlas/signposts.py
  echo "signposts.json rewritten: commit it before the next build"
fi

step "2. the gap map and the road threats"
python3 tools/world/atlas/gap_map.py --list 12 | awk 'NR <= 13'
python3 tools/world/atlas/gap_map.py --threats | grep -E 'threats:|quiet '

step "3. the atlas and the hook table"
python3 tools/world/atlas/check_atlas.py | tail -1
python3 tools/poi_hooks.py --check | tail -1

step "4. the POI plan on the new pads, and the frames"
python3 tools/capture/make_pois_plan.py --world "$WORLD" | tail -3
python3 tools/capture/frame_check.py --poi tools/capture/plans/pois.json | grep -v ' clear$' || true
python3 tools/capture/frame_check.py | grep -v ' clear$' || true
python3 -m pytest -q -p no:cacheprovider tools/tests/test_capture_plan.py tools/tests/test_relative_plan.py \
  tools/world/tests/test_signposts.py tools/world/tests/test_gap_map.py 2>&1 | tail -2

step "5. the captures"
if [ "${1:-}" = "--shoot" ]; then
  ${GATE:?set GATE to the gate command, e.g. GATE=\"\$SCRATCH/gate.sh 4\"} && \
    ./run.sh shots tools/capture/plans/after_signposts.json "--out=$OUT"
  ls "$OUT"
else
  echo "to take them: GATE=\"\$SCRATCH/gate.sh 4\" $0 --shoot   (into $OUT)"
fi
