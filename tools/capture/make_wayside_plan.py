#!/usr/bin/env python3
"""The capture plan that photographs each wayside kind (the finds the cartographer puts where a
road runs a minute and more past nothing) in the real country: tools/capture/plans/wayside.json.

    python3 tools/capture/make_wayside_plan.py

Each shot stands one up for itself (the capture runner's `dress`) with a 7 m pad, the wayside pad's
half-width, in the region it belongs to, 5 to 14 m off a built road on a dale side where one can be
found (the world puts these on 25 to 45 degree slopes), clear of the places and the water. Two
frames each: one from the road at 12 m, where a walker sees it, and one at 30 m, which is where a
Skerrow grave and a Cinderlea grave must already be told apart. Run it again after a world build.
"""
from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import make_default_plan as plan  # noqa: E402
from make_poi_kinds_plan import Land, aim  # noqa: E402

OUT = os.path.join(HERE, "plans", "wayside.json")

# (label, kind, region, brief, time, weather)
FINDS = [
    ("cairn_skerrow", "cairn", "skerrow", "a cairn where the drove road tops the fell", 11.0, "core:weather/clear_cold"),
    ("cairn_cinderlea", "cairn", "cinderlea", "a cairn on the pilgrims' way", 16.0, "core:weather/still_grey"),
    ("cairn_hearthvale", "cairn", "hearthvale", "a cairn over a drover who lies here", 10.0, "core:weather/clear"),
    ("tally_post", "tally_post", "skerrow", "a blood-price of the Oskel clan, half paid", 12.0, "core:weather/clear_cold"),
    ("grave_hearthvale", "grave", "hearthvale", "a roadside grave with flowers still brought", 10.0, "core:weather/clear"),
    ("grave_brightwater", "grave", "brightwater", "a watchman's grave by the Long Stride road", 12.0, "core:weather/clear"),
    ("grave_skerrow", "grave", "skerrow", "a clansman's grave under bone lintels", 11.0, "core:weather/clear_cold"),
    ("grave_sedgemire", "grave", "sedgemire", "a reedwoman's grave with her lantern", 17.5, "core:weather/fog"),
    ("grave_cinderlea", "grave", "cinderlea", "a pilgrim's grave under a bell on a stake", 16.0, "core:weather/still_grey"),
    ("grave_briarwold", "grave", "briarwold", "a forester's grave under a mossed stone", 12.0, "core:weather/still"),
    ("gibbet_hearthvale", "gibbet", "hearthvale", "the Wardens' gibbet at the crossways", 15.0, "core:weather/overcast"),
    ("gibbet_brightwater", "gibbet", "brightwater", "the Tollmere watch's gibbet on the lake road", 12.0, "core:weather/clear"),
    ("fold_skerrow", "fold", "skerrow", "a drystone fold, ewes in it, a lean-to for lambing", 11.0, "core:weather/clear_cold"),
    ("fold_hearthvale", "fold", "hearthvale", "a hurdle fold on the down, sheep in it", 10.0, "core:weather/clear"),
    ("well_hearthvale", "well", "hearthvale", "a wellhead by the road with a cup on a chain", 11.0, "core:weather/clear"),
    ("well_brightwater", "well", "brightwater", "a spring-trough the Guild keeps, a brass cup on a chain", 12.0, "core:weather/clear"),
    ("lantern_post", "lantern_post", "sedgemire", "the safe way over the fen", 18.5, "core:weather/fog"),
    ("lantern_drowned", "lantern_post", "sedgemire", "the lantern of a boy who drowned here", 18.5, "core:weather/fog"),
    ("cart_wreck", "wreck", "hearthvale", "a carter's cart gone over in the verge, its load spilled", 11.0, "core:weather/clear"),
    ("hut_burner", "hut", "briarwold", "a charcoal-burner's hut in the ride", 12.0, "core:weather/still"),
    ("hut_hermit", "hut", "briarwold", "a hermit's lean-to under the rock", 12.0, "core:weather/still"),
    ("hut_bothy", "hut", "skerrow", "a shepherd's bothy", 11.0, "core:weather/clear_cold"),
    ("crossroads", "crossroads", "hearthvale", "where the drove road crosses the Brow road", 11.0, "core:weather/clear"),
    ("peat_cut", "peat_cut", "skerrow", "the Oskel clan's peat bank", 11.0, "core:weather/clear_cold"),
    ("beacon", "beacon", "hearthvale", "the Wardens' beacon on the down", 11.0, "core:weather/clear"),
]


def clear_line(land, pos, look, over=0.6):
    """`pos` raised a metre at a time (up to 25) until the ground between it and `look` stays
    `over` metres under the line of sight."""
    cx, cy, cz = pos
    for _ in range(25):
        if all(land.h(cx + (look[0] - cx) * t, cz + (look[2] - cz) * t) + over <= cy + (look[1] - cy) * t
               for t in [i / 24.0 for i in range(1, 22)]):
            break
        cy += 1.0
    return [cx, round(cy, 1), cz]


def main():
    land = Land()
    scatter = plan.Scatter()
    shots = []
    used = []

    # the candidates: points 5 to 14 m either side of every built road, every 12 m along it
    cands = []
    for pts in land.roads:
        for a, b in zip(pts[:-1], pts[1:]):
            dx, dz = b[0] - a[0], b[1] - a[1]
            n = math.hypot(dx, dz)
            if n < 1.0:
                continue
            ux, uz = dx / n, dz / n
            t = 0.0
            while t < n:
                for off in (-11.0, -7.0, 7.0, 11.0):
                    cands.append((a[0] + ux * t - uz * off, a[1] + uz * t + ux * off, (a[0] + ux * t, a[1] + uz * t)))
                t += 12.0
    by_region = {}
    for x, z, q in cands:
        by_region.setdefault(land.region(x, z), []).append((x, z, q))

    def pick(region, lo_slope, hi_slope):
        best = None
        for x, z, q in by_region.get(region, []):
            if land.is_wet(x, z) or any(math.hypot(x - u[0], z - u[1]) < 200.0 for u in used):
                continue
            s_ = land.slope(x, z, 7.0)
            if s_ < lo_slope or s_ > hi_slope:
                continue
            if land.pad_dist((x, z)) < 60.0 or land.water_near(x, z, 10.0) or scatter.nearest(x, z) < 5.0:
                continue
            score = -abs(s_ - (lo_slope + hi_slope) * 0.5) + min(scatter.nearest(x, z), 15.0) * 0.01
            if best is None or score > best[0]:
                best = (score, x, z, q)
        return best

    for label, kind, region, brief, time, weather in FINDS:
        rid = "core:region/" + region
        # a dale side first (the world's wayside ground), then anything gentler that is by a road
        spot = pick(rid, 0.45, 0.9) or pick(rid, 0.0, 0.45)
        if spot is None:
            print("no spot for", label)
            continue
        _, x, z, q = spot
        used.append((x, z))
        to_road = ((q[0] - x), (q[1] - z))
        n = math.hypot(*to_road) or 1.0
        to_road = (to_road[0] / n, to_road[1] / n)
        dress = {"kind": kind, "region": rid, "at": [x, z], "brief": brief, "encounter": "", "radius": 7.0}
        for suffix, dist, height, look_up in (("", 12.0, 1.8, 1.0), ("_30m", 30.0, 2.5, 1.2)):
            pos, look, hits = aim(land, scatter, x, z, to_road, dist, height, spread=60.0, look_up=look_up)
            # on a dale side the slope between can hide it: raise the camera until nothing of the
            # ground stands in the line to what it looks at
            pos = clear_line(land, pos, look)
            shots.append({"label": label + suffix, "region": rid, "pos": pos, "look_at": look, "fov": 55.0,
                          "time": time, "weather": weather, "fog_scale": 1.0, "dress": dress})
        print("%-20s %-12s (%.0f, %.0f) slope %.2f, %d crowns across" % (label, region, x, z, land.slope(x, z, 7.0), hits))

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"_doc": "tools/capture/make_wayside_plan.py: each wayside kind staged by a road, at 12 m and 30 m",
                   "shots": shots}, f, indent=1)
        f.write("\n")
    print(len(shots), "shots ->", os.path.relpath(OUT, REPO))


if __name__ == "__main__":
    main()
