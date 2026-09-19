#!/usr/bin/env python3
"""Render the material library as swatches, for judging the painterly look quickly.

    blender -b --python tools/forge/swatches.py -- --palette hearthvale --out captures/materials
    blender -b --python tools/forge/swatches.py -- --all-regions --only stone,wood

Each material is baked onto a rounded slab at a fixed size (so scale reads honestly) and
written as a PNG, then tiled into one sheet per palette. This is the loop for tuning
materials: a full asset takes a minute, a swatch takes a couple of seconds.
"""
from __future__ import annotations

import math
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

from lib import bake as B  # noqa: E402
from lib import cli  # noqa: E402
from lib import impostor as IMP  # noqa: E402
from lib import materials as M  # noqa: E402
from lib import palette as P  # noqa: E402
from lib import scene as S  # noqa: E402

# Materials that need alpha or a mesh of their own are not swatched here.
SKIP = {"canvas"}


def slab(name, mat, size=1.0):
    """A slightly domed, bevelled slab: shows flat surface, an edge and a curve at once."""
    ob = S.plane(name, size=(size, size), subdiv=48, mat=mat)
    for v in ob.data.vertices:
        u = v.co.x / (size * 0.5)
        w = v.co.y / (size * 0.5)
        r = min(1.0, math.hypot(u, w))
        v.co.z = math.cos(r * math.pi * 0.5) * size * 0.16
    S.solidify(ob, thickness=size * 0.12, offset=-1.0)
    S.bevel(ob, width=size * 0.02, segments=2, angle_deg=35)
    S.shade_smooth(ob, 40.0)
    return ob


def render_swatch(name: str, builder, pal, out_dir: Path, size_px: int, slab_m: float) -> Path | None:
    S.reset()
    try:
        mat = builder(pal, scale=slab_m * 0.45)
    except TypeError:
        mat = builder(pal)
    ob = slab("swatch_%s" % name, mat, size=slab_m)
    prefix = "%s_%s" % (pal.short, name)
    B.bake_atlas(ob, out_dir, prefix, size_px, unwrap_mode="smart")
    png = out_dir / ("_render_%s.png" % prefix)
    IMP.render_alpha([ob], png, size=size_px, samples=24, margin=1.02)
    return png


def main() -> None:
    parser = cli.build_parser("Wickmere material swatches")
    parser.add_argument("--only", default="", help="comma-separated material name substrings")
    parser.add_argument("--all-regions", action="store_true", help="one sheet per region")
    args = parser.parse_args(cli.forge_argv())
    only = [o for o in args.only.split(",") if o]
    all_regions = args.all_regions
    out_root = Path(args.out if args.out != str(cli.DEFAULT_OUT)
                    else cli.REPO_ROOT / "captures" / "materials")
    size_px = args.res or 256
    slab_m = 1.0

    pals = P.all_palettes() if all_regions else [P.get_palette(args.palette)]
    names = sorted(n for n in M.BUILDERS if n not in SKIP)
    if only:
        names = [n for n in names if any(o and o in n for o in only)]
    for pal in pals:
        d = out_root / pal.short
        d.mkdir(parents=True, exist_ok=True)
        t0 = time.time()
        made = []
        for n in names:
            try:
                p = render_swatch(n, M.BUILDERS[n], pal, d, size_px, slab_m)
                made.append(p)
                print("SWATCH %s/%s" % (pal.short, n), flush=True)
            except Exception as exc:  # keep going: one broken material must not stop the sheet
                print("SWATCH_FAIL %s/%s: %s" % (pal.short, n, exc), flush=True)
        print("SWATCHES %s: %d in %.0fs -> %s" % (pal.short, len(made), time.time() - t0, d))


if __name__ == "__main__":
    main()
