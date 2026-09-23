#!/usr/bin/env python3
"""Bake the humanoid's clips alone, onto the bare armature, for tools/forge/transplant_clips.py.

    blender -b --python tools/forge/bake_clips.py -- --out <dir>

The rig bake (`character_forge.py rig`) rebuilds and repaints the body along with the clips. That
takes twenty minutes, and under another Blender it does not give back the same body. This builds
the armature and bakes every clip onto it exactly as the rig bake does -- it calls the same
functions -- and exports the armature and its animations alone:

    <dir>/humanoid_rig_clips.glb      the bones and the clips, no body
    <dir>/humanoid_rig.clips.json     the sidecar, as the rig bake writes it

Then move the clips onto the committed rig, and the sidecar beside it:

    python3 tools/forge/transplant_clips.py \\
        game/assets/models/characters/humanoid_rig/humanoid_rig.glb <dir>/humanoid_rig_clips.glb \\
        game/assets/models/characters/humanoid_rig/humanoid_rig.glb
    cp <dir>/humanoid_rig.clips.json game/assets/models/characters/humanoid_rig/
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
for p in (HERE, os.path.dirname(HERE)):
    if p not in sys.path:
        sys.path.insert(0, p)

import character_forge as cf  # noqa: E402  (its functions, not its command line)
from forge.lib import rig  # noqa: E402
from forge.lib.rig import Skeleton  # noqa: E402


def main(argv=None) -> int:
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser(prog="bake_clips", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="directory for the clips GLB and the sidecar")
    args = ap.parse_args(list(argv))
    if not cf.HAVE_BPY:
        raise SystemExit("bake_clips must run inside Blender: "
                         "blender -b --python tools/forge/bake_clips.py -- --out <dir>")
    t0 = time.time()
    cf.reset_scene()
    skel = Skeleton(rig.Proportions())
    arm = rig.build_armature(skel, name="Armature")
    sidecar = cf.bake_all_clips(arm, skel)
    os.makedirs(args.out, exist_ok=True)
    glb = cf.export_glb(os.path.join(args.out, "humanoid_rig_clips.glb"), [arm], with_animation=True)
    with open(os.path.join(args.out, "humanoid_rig.clips.json"), "w") as f:
        json.dump(sidecar, f, indent=1, sort_keys=True)
    cf.log("baked %d clips onto the bare armature in %.1fs: %s" % (len(sidecar), time.time() - t0, glb))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
