#!/usr/bin/env python3
"""Paint an installed world's ground round its cliff pieces (worldgen.rock_paint).

The world build paints the crag and talus round the cliff pieces once they are all laid. This
applies the same pass to an installed world: it reads the Terrain3D regions' heights, control and
colour maps as dump_heights.gd writes them (DUMP_MAPS=1), paints them round the cliff pieces in
game/world/generated/cells, and writes the changed regions' control (.ctl) and colour (.rgba) maps
to --out, which tools_gd/load_terrain_maps.gd puts back into game/terrain_data:

    DUMP_MAPS=1 DUMP_OUT=/tmp/h godot --headless --path game --audio-driver Dummy -s res://tools_gd/dump_heights.gd
    python3 tools/world/paint_rock.py --maps /tmp/h --out /tmp/h/painted
    LOAD_FROM=/tmp/h/painted godot --headless --path game --audio-driver Dummy -s res://tools_gd/load_terrain_maps.gd

It refuses maps already painted (crag or talus in them) unless --force: painting twice would
tint the colour map twice. The manifest's texture_slots (which TerrainProvider.texture_at names
the ground by) gain the two slots.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import seat_cliffs as SC  # noqa: E402
from worldgen import cliff_seat as CS  # noqa: E402
from worldgen import rock_paint as RP  # noqa: E402
from worldgen.grid import Grid  # noqa: E402
from worldgen.surface import SLOT_NAMES  # noqa: E402

WORLD = SC.WORLD


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--world", default=WORLD)
    ap.add_argument("--maps", required=True, help="a directory of dump_heights.gd's region files (DUMP_MAPS=1)")
    ap.add_argument("--out", default=None, help="where the repainted region maps go (default: MAPS/painted)")
    ap.add_argument("--force", action="store_true", help="paint maps that are painted already")
    ap.add_argument("--dry-run", action="store_true", help="measure only")
    args = ap.parse_args()
    out_dir = args.out or os.path.join(args.maps, "painted")

    with open(os.path.join(args.world, "world_manifest.json"), "r", encoding="utf-8") as f:
        manifest = json.load(f)
    g = Grid(float(manifest["size_m"]), int(manifest["grid"]), float(manifest.get("cell_size_m", 256.0)))
    H = SC.load_heights(args.maps, manifest)
    ctrl = SC.load_regions(args.maps, manifest, ".ctl", np.uint32)
    colour = SC.load_regions(args.maps, manifest, ".rgba", np.uint8, 4)
    base, overlay, blend = RP.unpack_control(ctrl)
    if not args.force and bool(np.isin(base, (RP.CRAG, RP.TALUS)).any() | np.isin(overlay, (RP.CRAG, RP.TALUS)).any()):
        raise SystemExit("paint_rock: these maps are painted already (--force to paint them again)")

    buckets: dict = {}
    for path in sorted(glob.glob(os.path.join(args.world, "cells", "*.json"))):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        buckets[tuple(int(v) for v in data["cell"])] = {a: r for a, r in data["instances"].items() if "rocks/" in a}
    w = RP.weights(buckets, H, g, REPO, int(manifest.get("seed", 0)))
    del buckets
    steep = CS.face_mask(H, g)

    def rocky(b, o, bl):
        top = np.where(bl >= 128, o, b)
        return np.isin(top, (RP.CRAG, RP.TALUS, 7, 8, 9, 14))     # + granite, limestone, scree, fused stone

    before = float(rocky(base, overlay, blend)[steep].mean())
    colour0 = colour.copy()
    n = RP.paint_control(base, overlay, blend, w)
    RP.paint_colour(colour, w)
    after = float(rocky(base, overlay, blend)[steep].mean())
    top = np.where(blend >= 128, overlay, base)
    stats = {"texels": n, "painted_ha": round(n * g.spacing ** 2 / 1e4, 1),
             "crag_top_ha": round(float((top == RP.CRAG).sum()) * g.spacing ** 2 / 1e4, 1),
             "talus_top_ha": round(float((top == RP.TALUS).sum()) * g.spacing ** 2 / 1e4, 1),
             "steep_faces_rock_textured_before": round(before, 3), "steep_faces_rock_textured_after": round(after, 3),
             "steep_faces_crag_top": round(float((top == RP.CRAG)[steep].mean()), 3)}
    print("[paint_rock] %s" % json.dumps(stats))
    if args.dry_run:
        return 0
    new_ctrl = RP.repack_control(ctrl, base, overlay, blend)
    os.makedirs(out_dir, exist_ok=True)
    written = 0
    k = SC.REGION_SAMPLES
    for f, i0, j0 in SC.region_files(args.maps, manifest, ".ctl"):
        name = os.path.basename(f)[:-4]
        ii0, jj0 = max(i0, 0), max(j0, 0)
        ii1, jj1 = min(i0 + k, g.n), min(j0 + k, g.n)
        if ii1 <= ii0 or jj1 <= jj0:
            continue
        sl = np.s_[ii0:ii1, jj0:jj1]
        if np.array_equal(new_ctrl[sl], ctrl[sl]) and np.array_equal(colour[sl], colour0[sl]):
            continue
        c = np.fromfile(f, dtype="<u4").reshape(k, k)
        c[ii0 - i0:ii1 - i0, jj0 - j0:jj1 - j0] = new_ctrl[sl]
        c.tofile(os.path.join(out_dir, name + ".ctl"))
        rgba = np.fromfile(os.path.join(args.maps, name + ".rgba"), dtype=np.uint8).reshape(k, k, 4)
        rgba[ii0 - i0:ii1 - i0, jj0 - j0:jj1 - j0] = colour[sl]
        rgba.tofile(os.path.join(out_dir, name + ".rgba"))
        written += 1
    print("[paint_rock] %d regions -> %s" % (written, out_dir))
    slots = list(manifest.get("texture_slots", []))
    if len(slots) < len(SLOT_NAMES) and slots == SLOT_NAMES[:len(slots)]:
        # (in the file's own text, so nothing else in it is rewritten)
        path = os.path.join(args.world, "world_manifest.json")
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
        last = '  "%s"\n ]' % slots[-1]
        if last in text:
            more = "".join(',\n  "%s"' % s for s in SLOT_NAMES[len(slots):])
            text = text.replace(last, '  "%s"%s\n ]' % (slots[-1], more), 1)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            print("[paint_rock] the manifest's texture_slots: %d" % len(SLOT_NAMES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
