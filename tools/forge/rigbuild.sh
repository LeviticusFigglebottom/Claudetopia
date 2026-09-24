#!/bin/bash
# Rebuild the rig's body and head without re-baking a single clip.
#
#   tools/forge/rigbuild.sh [workdir]
#
# `character_forge.py rig` bakes every clip, and a re-bake is wanted only when a clip changes.
# When the body, the head or the paint changed, this builds the rig with the Idle alone, puts
# every clip of the rig on disk back onto it with transplant_clips.py, restores the clips.json
# sidecar and the meta's clip list, and compares every clip with the one it replaced
# (preview/clipdiff.py: all should be "identical (<1e-5)"). The rig on disk must be the one whose
# clips you want kept: the committed one, normally. Blender 4.2 on PATH; about half an hour.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${1:-$(mktemp -d)}"
R=game/assets/models/characters/humanoid_rig
cd "$ROOT"
mkdir -p "$WORK"
cp $R/humanoid_rig.glb "$WORK/committed.glb"
cp $R/humanoid_rig.clips.json "$WORK/committed.clips.json"
cp $R/humanoid_rig.meta.json "$WORK/committed.meta.json"
blender -b --python tools/forge/character_forge.py -- rig --clips Idle > "$WORK/rig.log" 2>&1 || {
  echo "rig build failed: $WORK/rig.log"; exit 1; }
grep -E "\[forge\]|Error|Traceback" "$WORK/rig.log" | head -20
cp $R/humanoid_rig.glb "$WORK/new_base.glb"
python3 tools/forge/transplant_clips.py "$WORK/new_base.glb" "$WORK/committed.glb" $R/humanoid_rig.glb
cp "$WORK/committed.clips.json" $R/humanoid_rig.clips.json
python3 - "$R/humanoid_rig.meta.json" "$WORK/committed.meta.json" <<'EOF'
import json, sys
new = json.load(open(sys.argv[1]))
old = json.load(open(sys.argv[2]))
new["clips"] = old["clips"]
json.dump(new, open(sys.argv[1], "w"), indent=1, sort_keys=True)
print("meta clips", len(new["clips"]), "tris", new.get("tris"))
EOF
python3 tools/forge/preview/clipdiff.py "$WORK/committed.glb" $R/humanoid_rig.glb
