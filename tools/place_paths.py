#!/usr/bin/env python3
"""Rewrite a POI's way from coordinates into a shape between its two ends.

A POI's `path` names where its way goes (`to`) and the points it passes. Written as map
coordinates (`via`) the points stay put when the map is redrawn and the two ends move, and the
waystones walk off across whatever is there now. As a `shape` they are said in the frame that
runs from the POI (0, 0) to the place it leads to (1, 0), the second number to the right of
somebody walking it, and the way stretches and turns with its ends (`PlaceRef.along` in the game,
docs/COORDINATES.md).

    tools/place_paths.py                         # show every POI way and its shape
    tools/place_paths.py --write                 # rewrite pois.json: each `via` becomes a `shape`
    tools/place_paths.py --points core:poi/x     # a way's points on today's map (from its shape)

Draw a new way in coordinates (`via`), on today's map, and run --write.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK = os.path.join(REPO, "game", "content", "packs", "core")
POIS = os.path.join(PACK, "pois")          # one file a region (docs/WORLD_LIFE.md), every one read
DECIMALS = 5          # a 5 km way to within a few centimetres


def positions() -> dict:
    out = {}
    with open(os.path.join(PACK, "places", "places.json"), "r", encoding="utf-8") as f:
        defs = json.load(f)
    for path in _poi_files():
        with open(path, "r", encoding="utf-8") as f:
            defs += json.load(f)
    for d in defs:
        p = d.get("position")
        if isinstance(p, list) and len(p) >= 2:
            out[d["id"]] = (float(p[0]), float(p[1]))
    return out


def _poi_files() -> list:
    return [os.path.join(POIS, f) for f in sorted(os.listdir(POIS)) if f.endswith(".json")]


def shape_of(p, a, b) -> list:
    """Where map point p stands in the frame from a (0, 0) to b (1, 0)."""
    ux, uz = b[0] - a[0], b[1] - a[1]
    len2 = ux * ux + uz * uz
    rx, rz = -uz, ux                       # to the right of the way (walking north, east)
    dx, dz = p[0] - a[0], p[1] - a[1]
    return [round((dx * ux + dz * uz) / len2, DECIMALS), round((dx * rx + dz * rz) / len2, DECIMALS)]


def along(shape, a, b) -> list:
    ux, uz = b[0] - a[0], b[1] - a[1]
    rx, rz = -uz, ux
    return [[a[0] + ux * s + rx * c, a[1] + uz * s + rz * c] for s, c in shape]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--points", default="")
    args = ap.parse_args(argv)
    pos = positions()
    for path in _poi_files():
        _one_file(path, pos, args)
    return 0


def _one_file(path: str, pos: dict, args) -> None:
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    pois = json.loads(text)
    changed = 0
    for poi in pois:
        way = poi.get("path")
        if not isinstance(way, dict):
            continue
        pid, to = poi["id"], way.get("to", "")
        if pid not in pos or to not in pos:
            print("%s: a way to %s, and one of its ends says nowhere" % (pid, to))
            continue
        a, b = pos[pid], pos[to]
        if args.points and args.points == pid:
            pts = along(way.get("shape", []), a, b) if "shape" in way else way.get("via", [])
            print(json.dumps([[round(x, 1), round(z, 1)] for x, z in pts]))
            continue
        if "via" not in way:
            print("%s -> %s: %d points, already a shape" % (pid, to, len(way.get("shape", []))))
            continue
        shape = [shape_of(p, a, b) for p in way["via"]]
        back = along(shape, a, b)
        worst = max(((x - p[0]) ** 2 + (z - p[1]) ** 2) ** 0.5 for (x, z), p in zip(back, way["via"]))
        print("%s -> %s: %d points; back on the map to within %.3f m" % (pid, to, len(shape), worst))
        if args.write:
            # the POI's own text, so the rest of the file keeps the shape it was written in
            start = text.index('"id": "%s"' % pid)
            m = re.compile(r'"via":\s*\[\[.*?\]\]', re.S).search(text, start)
            if m is None:
                print("  could not find its via in the text; left alone")
                continue
            text = text[:m.start()] + '"shape": ' + json.dumps(shape) + text[m.end():]
            changed += 1
    if args.write and changed:
        json.loads(text)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print("rewrote %d way(s) in %s" % (changed, os.path.relpath(path, REPO)))


if __name__ == "__main__":
    sys.exit(main())
