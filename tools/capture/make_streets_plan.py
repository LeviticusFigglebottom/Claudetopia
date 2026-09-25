#!/usr/bin/env python3
"""The six street shots (tools/capture/plans/streets.json): one settlement a region, looked at from
its own street, as somebody walking in on the road sees it.

    python3 tools/capture/make_streets_plan.py

The shots were a bearing and a distance from each place's centre, chosen once on a world long
since redrawn, and most of them now stood in a back garden looking at the backs of houses. A
settlement's streets are its roads (Settlement lays them from roads.json), so each camera now
stands on the road that comes in nearest the centre, STAND_M out from it, at eye height, and looks
down the road to a point LOOK_M from the centre. Both are written as place specs (a bearing and a
distance off the place, docs/COORDINATES.md), so the plan still resolves on the world it was made
on; run it again after a world build.
"""
from __future__ import annotations

import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
GEN = os.path.join(REPO, "game", "world", "generated")
OUT = os.path.join(HERE, "plans", "streets.json")

STAND_M = 42.0
LOOK_M = 8.0
# (label, place, region, hour, weather), as the street shots of default.json have them
STREETS = [
    ("hearthvale_street", "core:place/merrowby", "core:region/hearthvale", 9.0, "core:weather/clear"),
    ("brightwater_street", "core:place/gullhithe", "core:region/brightwater", 11.0, "core:weather/clear"),
    ("sedgemire_street", "core:place/isseva", "core:region/sedgemire", 17.0, "core:weather/mist"),
    ("briarwold_street", "core:place/fernhold", "core:region/briarwold", 12.0, "core:weather/still"),
    ("skerrow_street", "core:place/kharrow_hold", "core:region/skerrow", 11.0, "core:weather/clear_cold"),
    ("cinderlea_street", "core:place/pilgrims_ash", "core:region/cinderlea", 16.0, "core:weather/still_grey"),
]


def spec(place: str, cx: float, cz: float, x: float, z: float, height: float) -> dict:
    """A place spec for (x, z): its compass bearing (0 north = -z, 90 east = +x) and distance."""
    dx, dz = x - cx, z - cz
    return {"place": place, "bearing": round(math.degrees(math.atan2(dx, -dz)) % 360.0, 3),
            "distance": round(math.hypot(dx, dz), 2), "height": height}


def along(pts: list, start: tuple, toward_out: bool, cx: float, cz: float, want: float):
    """Walks the polyline from its point nearest the centre (index `start`, the point `start`)
    outward, and returns the first point `want` metres from the centre, or None."""
    i0, p0 = start
    rng = range(i0 + 1, len(pts)) if toward_out else range(i0, -1, -1)
    prev = p0
    for k in rng:
        q = (float(pts[k][0]), float(pts[k][1]))
        d0 = math.hypot(prev[0] - cx, prev[1] - cz)
        d1 = math.hypot(q[0] - cx, q[1] - cz)
        if d0 <= want <= d1 and d1 > d0:
            t = (want - d0) / (d1 - d0)
            return (prev[0] + (q[0] - prev[0]) * t, prev[1] + (q[1] - prev[1]) * t)
        prev = q
    return None


def main():
    pads = {e["place_id"]: e for e in json.load(open(os.path.join(GEN, "pois.json")))}
    roads = [r["points"] for r in json.load(open(os.path.join(GEN, "roads.json")))]
    shots = []
    for label, place, region, hour, weather in STREETS:
        pad = pads.get(place)
        if pad is None:
            print("no pad for", place)
            continue
        cx, cz = float(pad["pos"][0]), float(pad["pos"][2])
        # every road that passes within 20 m of the centre, and the way out along it that goes
        # furthest before leaving STAND_M: the longest straight look down a street
        best = None
        for pts in roads:
            near, ni = 1e9, 0
            for k, p in enumerate(pts):
                d = math.hypot(float(p[0]) - cx, float(p[1]) - cz)
                if d < near:
                    near, ni = d, k
            if near > 20.0:
                continue
            start = (ni, (float(pts[ni][0]), float(pts[ni][1])))
            for out in (True, False):
                stand = along(pts, start, out, cx, cz, STAND_M)
                look = along(pts, start, out, cx, cz, LOOK_M)
                if stand is None:
                    continue
                if look is None:
                    look = start[1]
                # prefer the road that comes in straightest: the stand, the look and the centre in a line
                bend = abs(math.atan2(look[0] - stand[0], look[1] - stand[1]) - math.atan2(cx - stand[0], cz - stand[1]))
                bend = min(bend, 2 * math.pi - bend)
                score = near + bend * 20.0
                if best is None or score < best[0]:
                    best = (score, stand, look, near, bend)
        if best is None:
            print("no road into", place)
            continue
        _, stand, look, near, bend = best
        shots.append({"label": label, "region": region, "at": spec(place, cx, cz, stand[0], stand[1], 1.7),
                      "look": spec(place, cx, cz, look[0], look[1], 2.5), "fov": 58.0, "time": hour,
                      "weather": weather, "fog_scale": 1.0})
        print("%-20s on a road %.1f m from the centre, standing %.0f m out, looking to %.0f m (bend %.0f deg)" % (
            label, near, STAND_M, math.hypot(look[0] - cx, look[1] - cz), math.degrees(bend)))
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"_doc": "tools/capture/make_streets_plan.py: the six street shots, each from its own street, "
                   "for looking at the settlement fabric (and, with `-- --attribute`, its draw calls per owner)",
                   "shots": shots}, f, indent=1)
        f.write("\n")
    print(len(shots), "shots ->", os.path.relpath(OUT, REPO))


if __name__ == "__main__":
    main()
