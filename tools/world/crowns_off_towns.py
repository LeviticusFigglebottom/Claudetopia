#!/usr/bin/env python3
"""Run the build's crowns-off-the-towns pass (worldgen.trees.clear_off_towns) over an installed world.

The world build takes out every tree whose crown reaches over a town (its pad and the gardens past
it) as it writes the cells. This applies the same pass to cells already written, so an installed
world takes it without a build: it reads game/world/generated/cells/*.json and pois.json and the
pack's places, and writes back only the cells that changed, in the build's own JSON.

    python3 tools/world/crowns_off_towns.py              # clear the installed world's towns
    python3 tools/world/crowns_off_towns.py --dry-run    # say what would go
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

from prune_lines import PLACES, WORLD, settlements_of  # noqa: E402
from worldgen import trees as TR  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--world", default=WORLD)
    ap.add_argument("--dry-run", action="store_true", help="write nothing")
    args = ap.parse_args()

    with open(os.path.join(args.world, "pois.json"), "r", encoding="utf-8") as f:
        pois = json.load(f)
    with open(PLACES, "r", encoding="utf-8") as f:
        places = json.load(f)
    towns = settlements_of(pois, places)

    cells: dict = {}
    buckets: dict = {}
    for path in sorted(glob.glob(os.path.join(args.world, "cells", "*.json"))):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        cells[path] = data
        buckets[path] = data["instances"]
    got = TR.clear_off_towns(buckets, towns, REPO)
    most = sorted(((n, t) for n, t in zip(got["by_town"], towns) if n), reverse=True)
    print("[crowns_off_towns] %d trees from %d of %d towns" % (got["trees"], len(most), len(towns)))
    by_pos = {(float(e["pos"][0]), float(e["pos"][2])): str(e.get("place_id", "")) for e in pois}
    for n, t in most[:12]:
        print("  %s %d" % (by_pos.get((t[0], t[1]), "?").split("/")[-1], n))
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
    print("[crowns_off_towns] %d cells written" % written)
    return 0


if __name__ == "__main__":
    sys.exit(main())
