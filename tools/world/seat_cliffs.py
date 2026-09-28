#!/usr/bin/env python3
"""Seat the cliff face pieces of an installed world's cells in their slopes (worldgen.cliff_seat).

The world build seats each cliff piece as it lays it (crags.cliff_faces). This applies the same
rules to cells already written, so an installed world takes them without a build: every
`*_cliff_face_*` row in game/world/generated/cells/*.json is turned and leaned to lie in the plane
of the ground under it, sized to the face it dresses, and moved along the slope's normal until the
lowest fifth of its front stands SEAT_SHOW_M out of the ground; one that cannot be, or that stands
alone, goes. Only the cells that changed are written, in the build's own JSON. It is idempotent.

It needs the installed ground at full resolution. A build leaves it as heights.r32 (4096 x 4096,
not committed); otherwise dump the Terrain3D regions the game loads:

    DUMP_OUT=/tmp/h godot --headless --path game --audio-driver Dummy -s res://tools_gd/dump_heights.gd
    python3 tools/world/seat_cliffs.py --heights /tmp/h [--dry-run] [--stats before.json]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from worldgen import cliff_seat as CS  # noqa: E402
from worldgen.grid import Grid  # noqa: E402

WORLD = os.path.join(REPO, "game", "world", "generated")


def load_heights(path: str, manifest: dict) -> np.ndarray:
    """The installed ground, [z, x] at the manifest's grid: a build's heights.r32, or a directory
    of dump_heights.gd's region files (Terrain3D's regions of 1024 samples, named by location)."""
    n = int(manifest["grid"])
    if os.path.isfile(path):
        return np.fromfile(path, dtype=np.float32).reshape(n, n)
    spacing = float(manifest.get("spacing_m", 2.0))
    ox, oz = (float(v) for v in manifest["origin"])
    H = np.full((n, n), np.nan, dtype=np.float32)
    for f in glob.glob(os.path.join(path, "terrain3d*.r32")):
        m = re.match(r"terrain3d([-_])(\d+)([-_])(\d+)\.r32$", os.path.basename(f))
        if not m:
            continue
        rx = int(m.group(2)) * (-1 if m.group(1) == "-" else 1)
        rz = int(m.group(4)) * (-1 if m.group(3) == "-" else 1)
        a = np.fromfile(f, dtype=np.float32)
        k = int(round(len(a) ** 0.5))
        a = a.reshape(k, k)
        j0 = int(round((rx * k * spacing - ox) / spacing))
        i0 = int(round((rz * k * spacing - oz) / spacing))
        ii0, jj0 = max(i0, 0), max(j0, 0)
        ii1, jj1 = min(i0 + k, n), min(j0 + k, n)
        if ii1 > ii0 and jj1 > jj0:
            H[ii0:ii1, jj0:jj1] = a[ii0 - i0:ii1 - i0, jj0 - j0:jj1 - j0]
    if np.isnan(H).any():
        raise SystemExit("seat_cliffs: %d texels of the ground missing from %s" % (int(np.isnan(H).sum()), path))
    return H


def summary(m: dict) -> dict:
    r = m["rows"]
    if not len(r):
        return {"pieces": 0}
    q = lambda a, p: round(float(np.percentile(a, p)), 2)  # noqa: E731
    return {
        "pieces": int(len(r)),
        "front_out_median_m": q(r[:, 0], 50), "front_out_mean_m": round(float(r[:, 0].mean()), 2),
        "front_out_p90_m": q(r[:, 0], 90),
        "worst_tenth_out_median_m": q(r[:, 1], 50), "worst_tenth_out_p90_m": q(r[:, 1], 90),
        "size_over_fit_median": q(r[:, 2], 50), "size_over_fit_p90": q(r[:, 2], 90),
        "too_big_share": round(float((r[:, 2] > 1.0 + 1e-3).mean()), 3),
        "slope_deg_p10": q(r[:, 3], 10), "slope_deg_median": q(r[:, 3], 50), "under_min_slope_share": round(float((r[:, 3] < CS.SEAT_MIN_SLOPE_DEG).mean()), 3),
        "back_shows_m_p90": q(r[:, 4], 90),
        "scale_median": q(r[:, 5], 50), "lean_deg_median": q(r[:, 6], 50),
        "front_shown_share_median": q(r[:, 7], 50), "front_shown_share_p10": q(r[:, 7], 10),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--world", default=WORLD)
    ap.add_argument("--heights", default=None, help="heights.r32, or a directory of dump_heights.gd's region files")
    ap.add_argument("--dry-run", action="store_true", help="write nothing")
    ap.add_argument("--measure", action="store_true", help="only measure the pieces as they stand")
    ap.add_argument("--stats", help="write the before and after measures here (JSON)")
    args = ap.parse_args()

    with open(os.path.join(args.world, "world_manifest.json"), "r", encoding="utf-8") as f:
        manifest = json.load(f)
    heights = args.heights or os.path.join(args.world, "heights.r32")
    if not os.path.exists(heights):
        raise SystemExit("seat_cliffs: no %s; dump the installed ground with tools_gd/dump_heights.gd (see --help)" % heights)
    H = load_heights(heights, manifest)
    g = Grid(float(manifest["size_m"]), int(manifest["grid"]), float(manifest.get("cell_size_m", 256.0)))

    cells: dict = {}
    buckets: dict = {}
    for path in sorted(glob.glob(os.path.join(args.world, "cells", "*.json"))):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        key = tuple(int(v) for v in data["cell"])
        cells[key] = (path, data)
        buckets[key] = data["instances"]
    before = summary(CS.measure(buckets, H, g, REPO))
    print("[seat_cliffs] before: %s" % json.dumps(before))
    if args.measure:
        return 0
    got = CS.settle(buckets, H, g, REPO)
    got.pop("feet", None)
    print("[seat_cliffs] %s" % json.dumps(got))
    after = summary(CS.measure(buckets, H, g, REPO))
    print("[seat_cliffs] after: %s" % json.dumps(after))
    if args.stats:
        with open(args.stats, "w", encoding="utf-8") as f:
            json.dump({"before": before, "after": after, "settle": got}, f, indent=1)
    stray = [k for k in buckets if k not in cells]
    if stray:
        raise SystemExit("seat_cliffs: pieces moved into cells the world does not have: %s" % stray)
    if args.dry_run:
        return 0
    written = 0
    for key, (path, data) in cells.items():
        with open(path, "r", encoding="utf-8") as f:
            was = f.read()
        data["instances"] = {a: rows for a, rows in data["instances"].items() if rows}
        now = json.dumps(data, separators=(",", ":"))
        if now != was:
            with open(path, "w", encoding="utf-8") as f:
                f.write(now)
            written += 1
    print("[seat_cliffs] %d cells written" % written)
    return 0


if __name__ == "__main__":
    sys.exit(main())
