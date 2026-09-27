#!/usr/bin/env python3
"""Run the build's last line-work pass (worldgen.linework.prune) over an installed world's cells.

The world build prunes its hedges, walls, rails and gate posts as it writes them. This applies the
same rules to cells already written, so an installed world takes a change to them without a
17-minute build: it reads game/world/generated/cells/*.json, pois.json and roads.json, and the
pack's places, and writes back only the cells that changed, in the build's own JSON.

    python3 tools/world/prune_lines.py                 # prune the installed world
    python3 tools/world/prune_lines.py --dry-run       # say what would go
    python3 tools/world/prune_lines.py --dry-run --plot out.png --box -400 -400 600 1500

`--plot` draws the hedges, walls, rails and posts inside `--box` (x0 z0 x1 z1) before and after,
from above, with the roads and the places' pads: a look at a stretch of country far cheaper than a
render.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from worldgen import linework as LW  # noqa: E402
from worldgen import roads as RD  # noqa: E402

WORLD = os.path.join(REPO, "game", "world", "generated")
PLACES = os.path.join(REPO, "game", "content", "packs", "core", "places", "places.json")


def settlements_of(pois: list, places: list) -> list:
    """[(x, z, pad radius)] of the places a settlement is built at (roads.FABRIC_COUNT), as the
    build's `settled` mask takes them."""
    kind = {p["id"]: str(p.get("kind", "")) for p in places}
    out = []
    for e in pois:
        pid = str(e.get("place_id", ""))
        if ":place/" in pid and RD.FABRIC_COUNT.get(kind.get(pid, ""), 0) > 0:
            out.append((float(e["pos"][0]), float(e["pos"][2]), float(e["radius_flat_m"])))
    return out


def _plot(path: str, box: list, before: dict, after: dict, roads: list, settlements: list) -> None:
    import math

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    x0, z0, x1, z1 = box
    colour = {"hedge": "#2e7d32", "wall": "#6d4c41", "rail": "#c62828", "post": "#1565c0"}
    fig, axes = plt.subplots(1, 2, figsize=(16, 8.5), sharex=True, sharey=True)
    for ax, (title, buckets) in zip(axes, (("before", before), ("after", after))):
        for r in roads:
            ax.plot([p[0] for p in r], [p[1] for p in r], color="#9e9e9e", lw=2.0, zorder=1)
        for sx, sz, sr in settlements:
            ax.add_patch(plt.Circle((sx, sz), sr, color="#ffb300", alpha=0.35, zorder=1))
        counts = {f: 0 for f in colour}
        for by_asset in buckets.values():
            for asset, rows in by_asset.items():
                fam = LW.family_of(asset)
                if fam is None:
                    continue
                for r in rows:
                    if not (x0 <= r[0] <= x1 and z0 <= r[2] <= z1):
                        continue
                    counts[fam] += 1
                    if fam == "post":
                        ax.plot(r[0], r[2], "o", ms=2.5, color=colour[fam], zorder=3)
                        continue
                    a = math.radians(r[3])
                    h = 1.1 * (r[8][0] if len(r) > 8 else r[4])
                    ux, uz = math.cos(a) * h, -math.sin(a) * h
                    ax.plot([r[0] - ux, r[0] + ux], [r[2] - uz, r[2] + uz], color=colour[fam], lw=1.2, zorder=2)
        ax.set_title("%s: %s" % (title, ", ".join("%s %d" % kv for kv in counts.items())))
        ax.set_xlim(x0, x1)
        ax.set_ylim(z1, z0)                        # north (-z) up
        ax.set_aspect("equal")
    fig.tight_layout()
    fig.savefig(path, dpi=110)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--world", default=WORLD)
    ap.add_argument("--dry-run", action="store_true", help="write nothing")
    ap.add_argument("--plot", help="a before-and-after PNG of --box")
    ap.add_argument("--box", type=float, nargs=4, metavar=("X0", "Z0", "X1", "Z1"))
    args = ap.parse_args()

    with open(os.path.join(args.world, "pois.json"), "r", encoding="utf-8") as f:
        pois = json.load(f)
    with open(os.path.join(args.world, "roads.json"), "r", encoding="utf-8") as f:
        roads = [[p[:2] for p in r["points"]] for r in json.load(f)]
    with open(PLACES, "r", encoding="utf-8") as f:
        places = json.load(f)
    settlements = settlements_of(pois, places)

    cells: dict = {}
    buckets: dict = {}
    for path in sorted(glob.glob(os.path.join(args.world, "cells", "*.json"))):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        cells[path] = data
        buckets[path] = data["instances"]
    before = None
    if args.plot:
        before = {k: {a: list(rows) for a, rows in v.items()} for k, v in buckets.items()}
    got = LW.prune(buckets, settlements, roads)
    print(json.dumps(got, indent=1))
    if args.plot and args.box:
        _plot(args.plot, args.box, before, buckets, roads, settlements)
        print("[prune_lines] plotted %s" % args.plot)
    if args.dry_run:
        return 0
    written = 0
    for path, data in cells.items():
        with open(path, "r", encoding="utf-8") as f:
            was = f.read()
        now = json.dumps(data, separators=(",", ":"))
        if now != was:
            with open(path, "w", encoding="utf-8") as f:
                f.write(now)
            written += 1
    print("[prune_lines] %d cells written" % written)
    return 0


if __name__ == "__main__":
    sys.exit(main())
