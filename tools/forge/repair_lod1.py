"""Take out the LOD1 bark triangles that stand off a tree's full bark (lib/lod_repair.py).

    python3 tools/forge/repair_lod1.py [--root game/assets/models/trees] [tree ...]

`gen_impostors` does this to every tree it draws a picture of, so a tree rebuilt by the
forge gets it on the way; this is the same step for trees whose pictures are already
current. It is idempotent: a second run drops nothing and says so.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from lib import glb as G  # noqa: E402
from lib import lod_repair as LR  # noqa: E402

ROOT = HERE.parent.parent / "game" / "assets" / "models" / "trees"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", default=str(ROOT))
    ap.add_argument("trees", nargs="*")
    args = ap.parse_args()
    root = Path(args.root)
    names = args.trees or sorted(p.name for p in root.iterdir() if p.is_dir())
    total = 0
    for name in names:
        glb = root / name / ("%s.glb" % name)
        meta = root / name / ("%s.meta.json" % name)
        if not glb.exists() or not meta.exists():
            print("REPAIR_SKIP %s (no GLB or meta)" % name)
            continue
        before = G.summary(glb)
        rep = LR.repair_tree(glb, meta, name)
        after = G.summary(glb)
        lod1 = {m["name"]: m["tris"] for m in before["meshes"]}.get("%s_LOD1" % name, 0)
        lod1_after = {m["name"]: m["tris"] for m in after["meshes"]}.get("%s_LOD1" % name, 0)
        total += lod1 - lod1_after
        print("REPAIR_OK %-30s LOD1 bark %4d -> %4d tris (tolerance %.2f m; %d dropped, %.1f m2, all runs)"
              % (name, lod1, lod1_after, rep["tol_m"], rep["dropped"], rep["area_m2"]))
    print("REPAIR_DONE %d trees, %d triangles dropped this run" % (len(names), total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
