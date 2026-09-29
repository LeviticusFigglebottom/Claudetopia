#!/usr/bin/env python3
"""Rewrite a capture plan's coordinates as places, so its shots go where their places go.

The map is drawn by hand (tools/world/atlas) and gets drawn again. A shot written as
`"pos": [x, y, z]` stays at those numbers when the place it was of moves, and photographs
whatever is there now. This turns every camera and every target in a plan into the same place
spec the opening's cinematic uses (docs/COORDINATES.md, `PlaceRef` in the game):

    {"place": id, "bearing": deg, "distance": m, "height": m}

a compass bearing (0 north = -z, 90 east = +x) and a distance from the nearest place or POI,
`height` metres above the ground there. The capture runner resolves it against the world it
loads, so on the world the plan was written for the camera stands where it stood (to the
centimetre where the plan gave a height above the ground, and to the difference between the
runtime height map this reads and Terrain3D's where it gave a bare y), and on a redrawn world
it stands the same way off the same place.

    tools/capture/relative_plan.py tools/capture/plans/look.json            # print the result
    tools/capture/relative_plan.py --write tools/capture/plans/*.json       # rewrite in place
    tools/capture/relative_plan.py --check tools/capture/plans/look.json    # how far each
        resolved point lands from the coordinates it replaced (on this world)

Shots (`pos`, `height_above_ground`, `place`, `look_at`), a gait's `pos` and a sequence's `pos`,
`look_at` and `to` are rewritten; a flythrough path, and anything already a spec, is left alone.
Generated plans (default.json, pois.json) are better made again by their generators, which
read where the places are now.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(REPO, "game", "world", "generated")
PACK = os.path.join(REPO, "game", "content", "packs", "core")
## The places, and every POI file (one a region, docs/WORLD_LIFE.md).
ANCHOR_FILES = ("places/places.json", "pois/*.json")


class Ground:
    """The runtime height map, sampled the way TerrainProvider.sample_height does (bilinear, the
    first texel centred `runtime_height_offset` east and south of the origin)."""

    def __init__(self, gen: str = GEN) -> None:
        with open(os.path.join(gen, "world_manifest.json"), "r", encoding="utf-8") as f:
            man = json.load(f)
        rt = man["runtime"]
        self.n = int(rt["grid"])
        size = float(man.get("size_m", 8192))
        self.spacing = size / self.n
        full = int(man.get("grid", 0))
        if "height_offset_m" in rt:
            off = float(rt["height_offset_m"])
        elif full > self.n and full % self.n == 0:
            off = (full // self.n - 1) * (size / full) * 0.5
        else:
            off = 0.0
        self.ox = float(man["origin"][0]) + off
        self.oz = float(man["origin"][1]) + off
        self.h = np.fromfile(os.path.join(gen, rt["heights"]), dtype="<f4").reshape(self.n, self.n)

    def height(self, x: float, z: float) -> float:
        fx = min(max((x - self.ox) / self.spacing, 0.0), self.n - 1.001)
        fz = min(max((z - self.oz) / self.spacing, 0.0), self.n - 1.001)
        x0, z0 = int(fx), int(fz)
        tx, tz = fx - x0, fz - z0
        x1, z1 = min(x0 + 1, self.n - 1), min(z0 + 1, self.n - 1)
        h = self.h
        top = h[z0, x0] + (h[z0, x1] - h[z0, x0]) * tx
        bottom = h[z1, x0] + (h[z1, x1] - h[z1, x0]) * tx
        return float(top + (bottom - top) * tz)


def anchors(pack: str = PACK) -> dict:
    """Every place and POI that says where it stands: id -> (x, z)."""
    out = {}
    import glob
    paths = [p for rel in ANCHOR_FILES for p in sorted(glob.glob(os.path.join(pack, rel)))]
    for path in paths:
        with open(path, "r", encoding="utf-8") as f:
            for d in json.load(f):
                p = d.get("position")
                if isinstance(p, list) and len(p) >= 2:
                    out[d["id"]] = (float(p[0]), float(p[1]))
    return out


def nearest(places: dict, x: float, z: float) -> str:
    return min(places, key=lambda k: (places[k][0] - x) ** 2 + (places[k][1] - z) ** 2)


def spec_of(places: dict, ground: Ground, x: float, z: float, height: float) -> dict:
    """The place spec for a point `height` metres above the ground at (x, z)."""
    pid = nearest(places, x, z)
    px, pz = places[pid]
    dx, dz = x - px, z - pz
    distance = math.hypot(dx, dz)
    bearing = (math.degrees(math.atan2(dx, -dz)) + 360.0) % 360.0 if distance > 0.005 else 0.0
    spec = {"place": pid}
    if distance > 0.005:
        spec["bearing"] = round(bearing, 3)
        spec["distance"] = round(distance, 2)
    spec["height"] = round(height, 2)
    return spec


def resolve(places: dict, ground: Ground, spec: dict) -> tuple:
    px, pz = places[spec["place"]]
    b = math.radians(float(spec.get("bearing", 0.0)))
    d = float(spec.get("distance", 0.0))
    x, z = px + math.sin(b) * d, pz - math.cos(b) * d
    return x, ground.height(x, z) + float(spec.get("height", 0.0)), z


def _put(item: dict, replaced: tuple, key: str, value) -> None:
    """Sets `key` where the first of `replaced` stood and drops the rest, keeping the order the
    plan was written in."""
    items = list(item.items())
    item.clear()
    done = False
    for k, v in items:
        if k in replaced or k == key:
            if not done:
                item[key] = value
                done = True
            continue
        item[k] = v
    if not done:
        item[key] = value


def _is_spec(v) -> bool:
    return isinstance(v, dict) and bool(v.get("place"))


def _xyz(v) -> tuple | None:
    if isinstance(v, list) and len(v) >= 3 and all(isinstance(n, (int, float)) for n in v[:3]):
        return float(v[0]), float(v[1]), float(v[2])
    return None


def convert_camera(item: dict, places: dict, ground: Ground, report: list, label: str,
                   travels: bool = False) -> None:
    """`pos` (+ `height_above_ground`) or `place` -> `at`; `look_at` -> `look`; in place. A
    sequence that `travels` keeps its `height_above_ground`, which holds the camera over the
    ground all the way to `to`."""
    hag = item.get("height_above_ground")
    if not _is_spec(item.get("at")):
        pos = _xyz(item.get("pos"))
        if pos is None and item.get("place") in places:
            px, pz = places[item["place"]]
            pos = (px, ground.height(px, pz), pz)
        if pos is not None:
            x, y, z = pos
            h = float(hag) if hag is not None else y - ground.height(x, z)
            want = (x, ground.height(x, z) + h, z)
            dropped = ("pos", "place") if travels else ("pos", "place", "height_above_ground")
            _put(item, dropped, "at", spec_of(places, ground, x, z, h))
            report.append((label + " at", want, resolve(places, ground, item["at"])))
    look = _xyz(item.get("look_at"))
    if look is not None and not _is_spec(item.get("look")):
        x, y, z = look
        _put(item, ("look_at",), "look", spec_of(places, ground, x, z, y - ground.height(x, z)))
        report.append((label + " look", look, resolve(places, ground, item["look"])))
    to = _xyz(item.get("to"))
    if to is not None:
        x, y, z = to
        h = float(hag) if hag is not None else y - ground.height(x, z)
        _put(item, ("to",), "to", spec_of(places, ground, x, z, h))
        report.append((label + " to", to, resolve(places, ground, item["to"])))


def convert_plan(plan: dict, places: dict, ground: Ground) -> list:
    report: list = []
    for i, shot in enumerate(plan.get("shots", [])):
        if isinstance(shot, dict):
            convert_camera(shot, places, ground, report, str(shot.get("label", "shot_%d" % i)))
    for i, seq in enumerate(plan.get("sequences", [])):
        if isinstance(seq, dict) and ("pos" in seq or "look_at" in seq or "place" in seq):
            convert_camera(seq, places, ground, report, str(seq.get("label", "sequence_%d" % i)), True)
    gait = plan.get("gait")
    if isinstance(gait, dict) and not _is_spec(gait.get("at")):
        pos = _xyz(gait.get("pos"))
        if pos is not None:
            x, _, z = pos
            at = spec_of(places, ground, x, z, 0.0)
            at.pop("height", None)
            _put(gait, ("pos",), "at", at)
            report.append(("gait at", (x, ground.height(x, z), z), resolve(places, ground, gait["at"])))
    return report


def dumps(plan: dict) -> str:
    """Two-space JSON with each shot, sequence key or gait run on one line, the way the hand
    plans are written."""
    lines = ["{"]
    keys = list(plan.keys())
    for n, k in enumerate(keys):
        v = plan[k]
        comma = "," if n < len(keys) - 1 else ""
        if isinstance(v, list) and v and all(isinstance(e, dict) for e in v):
            lines.append("  %s: [" % json.dumps(k))
            for m, e in enumerate(v):
                lines.append("    %s%s" % (json.dumps(e, ensure_ascii=False), "," if m < len(v) - 1 else ""))
            lines.append("  ]" + comma)
        else:
            lines.append("  %s: %s%s" % (json.dumps(k), json.dumps(v, ensure_ascii=False), comma))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("plans", nargs="+")
    ap.add_argument("--write", action="store_true", help="rewrite each plan in place")
    ap.add_argument("--check", action="store_true", help="print how far each resolved point lands")
    ap.add_argument("--world", default=GEN, help="the generated world to measure the ground in")
    args = ap.parse_args(argv)
    places = anchors()
    ground = Ground(args.world)
    worst = 0.0
    for path in args.plans:
        with open(path, "r", encoding="utf-8") as f:
            plan = json.load(f)
        report = convert_plan(plan, places, ground)
        for label, want, got in report:
            off = math.dist(want, got)
            worst = max(worst, off)
            if args.check:
                print("%-48s %6.3f m  %s" % (label, off, json.dumps([round(c, 2) for c in got])))
        if args.write:
            with open(path, "w", encoding="utf-8") as f:
                f.write(dumps(plan))
            print("%s: %d points" % (path, len(report)))
        elif not args.check:
            sys.stdout.write(dumps(plan))
    if args.check or args.write:
        print("worst: %.3f m from the coordinates replaced" % worst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
