#!/usr/bin/env python3
"""The capture plan that photographs each kind of point of interest the drawn map asked for next
(docs/ATLAS.md, section 10) in the real country: tools/capture/plans/poi_kinds.json.

    python3 tools/capture/make_poi_kinds_plan.py

The world may have none of these kinds yet, so each shot stands one up for itself (the capture
runner's `dress`) on a spot of the built world that suits it: a cave in a slope, a quarry in a
steeper one, a farmstead and a market field on level ground off a road, a waystone at a road's
side, a mill by a river and a windmill on a rise, a shieling on the high fell, a vista on an edge
the ground falls away from. Each spot keeps clear of the places, the roads' own line and the
water. The camera stands on the side the thing is meant to be seen from and, of the bearings
round that side, on the one whose line of sight no tree's crown crosses (make_default_plan's
Scatter). Run it again after a world build: the spots are read from the built world.
"""
from __future__ import annotations

import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
GEN = os.path.join(REPO, "game", "world", "generated")
sys.path.insert(0, HERE)

import make_default_plan as plan  # noqa: E402

OUT = os.path.join(HERE, "plans", "poi_kinds.json")
# the direction the wind blows toward (Atmosphere's wm_wind_dir): a windmill's sails face into it
WIND = (0.8, 0.6)


class Land:
    def __init__(self):
        man = json.load(open(os.path.join(GEN, "world_manifest.json")))
        self.n = int(man["runtime"]["grid"])
        self.size = float(man["size_m"])
        self.ox, self.oz = float(man["origin"][0]), float(man["origin"][1])
        self.regions = man["regions"]
        rt = man["runtime"]
        self.hts = open(os.path.join(GEN, rt["heights"]), "rb").read()
        self.reg = open(os.path.join(GEN, rt["regions"]), "rb").read()
        self.wet = open(os.path.join(GEN, rt["water"]), "rb").read()
        self.roads = [r["points"] for r in json.load(open(os.path.join(GEN, "roads.json")))]
        self.rivers = [r["points"] for r in json.load(open(os.path.join(GEN, "rivers.json")))]
        self.pads = json.load(open(os.path.join(GEN, "pois.json")))

    def _ij(self, x, z):
        i = int((x - self.ox) / self.size * self.n)
        j = int((z - self.oz) / self.size * self.n)
        return max(0, min(self.n - 1, i)), max(0, min(self.n - 1, j))

    def h(self, x, z):
        fx = (x - self.ox) / self.size * self.n - 0.5
        fz = (z - self.oz) / self.size * self.n - 0.5
        i0, j0 = int(math.floor(fx)), int(math.floor(fz))
        tx, tz = fx - i0, fz - j0

        def at(i, j):
            i = max(0, min(self.n - 1, i))
            j = max(0, min(self.n - 1, j))
            return struct.unpack_from("<f", self.hts, 4 * (j * self.n + i))[0]
        a = at(i0, j0) * (1 - tx) + at(i0 + 1, j0) * tx
        b = at(i0, j0 + 1) * (1 - tx) + at(i0 + 1, j0 + 1) * tx
        return a * (1 - tz) + b * tz

    def region(self, x, z):
        i, j = self._ij(x, z)
        r = self.reg[j * self.n + i]
        return self.regions[r] if r < len(self.regions) else ""

    def is_wet(self, x, z):
        i, j = self._ij(x, z)
        return self.wet[j * self.n + i] > 0

    @staticmethod
    def seg_dist(p, a, b):
        dx, dz = b[0] - a[0], b[1] - a[1]
        l2 = dx * dx + dz * dz
        t = 0.0 if l2 < 1e-6 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / l2))
        return math.hypot(p[0] - (a[0] + dx * t), p[1] - (a[1] + dz * t)), (a[0] + dx * t, a[1] + dz * t)

    def line_dist(self, p, lines):
        best, near = 1e9, p
        for pts in lines:
            for k in range(len(pts) - 1):
                d, q = self.seg_dist(p, pts[k], pts[k + 1])
                if d < best:
                    best, near = d, q
        return best, near

    def pad_dist(self, p):
        return min(math.hypot(p[0] - e["pos"][0], p[1] - e["pos"][2]) - float(e.get("radius_flat_m", 25)) for e in self.pads)

    def downhill(self, x, z):
        h0 = self.h(x, z)
        best, d = 0.0, (0.0, 0.0)
        for a in range(0, 360, 15):
            u = (math.sin(math.radians(a)), math.cos(math.radians(a)))
            drop = h0 - self.h(x + u[0] * 24.0, z + u[1] * 24.0)
            if drop > best:
                best, d = drop, u
        return d, best

    def slope(self, x, z, r=10.0):
        return max(abs(self.h(x + dx, z + dz) - self.h(x, z)) for dx, dz in ((r, 0), (-r, 0), (0, r), (0, -r))) / r

    def water_near(self, x, z, r):
        return any(self.is_wet(x + math.sin(math.radians(a)) * d, z + math.cos(math.radians(a)) * d)
                   for a in range(0, 360, 20) for d in range(4, int(r), 4))

    def water_dir(self, x, z, r=80.0):
        for d in range(3, int(r), 3):
            for a in range(0, 360, 10):
                u = (math.sin(math.radians(a)), math.cos(math.radians(a)))
                if self.is_wet(x + u[0] * d, z + u[1] * d):
                    return u
        return None

    def clear(self, x, z, road_min=12.0, pad_min=40.0):
        return (self.line_dist((x, z), self.roads)[0] > road_min and self.pad_dist((x, z)) > pad_min
                and self.line_dist((x, z), self.rivers)[0] > 12.0 and not self.is_wet(x, z))

    def search(self, pred, want_region, step=24.0):
        best = None
        x = self.ox + 200
        while x < self.ox + self.size - 200:
            z = self.oz + 200
            while z < self.oz + self.size - 200:
                if self.region(x, z) == want_region and not self.is_wet(x, z):
                    s = pred(x, z)
                    if s is not None and (best is None or s > best[0]):
                        best = (s, x, z)
                z += step
            x += step
        return best


def aim(land, scatter, x, z, prefer, dist, height, spread=70.0, look_up=2.0):
    """A camera `dist` out from the spot, `height` over the ground, on the bearing nearest `prefer`
    (within `spread` degrees either side) whose lens is clear and whose line of sight no crown
    crosses; the preferred bearing itself when none is."""
    base = math.degrees(math.atan2(prefer[1], prefer[0]))
    best = None
    for off in [0, 15, -15, 30, -30, 45, -45, 60, -60, 75, -75]:
        if abs(off) > spread:
            continue
        a = math.radians(base + off)
        cx, cz = x + math.cos(a) * dist, z + math.sin(a) * dist
        cy = max(land.h(cx, cz), land.h(x, z)) + height
        target = (x, land.h(x, z) + look_up, z)
        hits = scatter.crowns_across((cx, cy, cz), target, 0.0, dist)
        blocked = scatter.in_crown(cx, cy, cz)
        score = hits * 10 + (100 if blocked else 0) + abs(off) / 15.0
        if best is None or score < best[0]:
            best = (score, cx, cy, cz, hits)
    _, cx, cy, cz, hits = best
    return [round(cx, 1), round(cy, 1), round(cz, 1)], [x, round(land.h(x, z) + look_up, 1), z], hits


def main():
    land = Land()
    scatter = plan.Scatter()
    shots = []

    def add(label, kind, region, spot, brief, prefer, dist, height, time=11.0, encounter="", day=None, look_up=2.0,
            weather="core:weather/clear", target=None):
        if spot is None:
            print("no spot for", label)
            return
        _, x, z = spot
        tx, tz = target if target is not None else (x, z)
        pos, look, hits = aim(land, scatter, tx, tz, prefer, dist, height, look_up=look_up)
        s = {"label": label, "region": region, "pos": pos, "look_at": look, "fov": 60.0, "time": time,
             "weather": weather, "fog_scale": 1.0,
             "dress": {"kind": kind, "region": region, "at": [x, z], "brief": brief, "encounter": encounter, "radius": 30}}
        if day is not None:
            s["day"] = day
        shots.append(s)
        print("%-14s %-24s (%.0f, %.0f)  camera %s, %d crowns across" % (label, region, x, z, pos, hits))

    def slope_pred(lo, hi, road_min=12.0):
        def pred(x, z):
            _d, drop = land.downhill(x, z)
            if not land.clear(x, z, road_min) or drop < lo or drop > hi or scatter.nearest(x, z) < 6.0:
                return None
            return -abs(drop - (lo + hi) * 0.5)
        return pred

    def near_road(lo, hi, flat=0.08):
        def pred(x, z):
            rd, _q = land.line_dist((x, z), land.roads)
            if rd < lo or rd > hi or land.pad_dist((x, z)) < 60.0 or land.slope(x, z) > flat or land.is_wet(x, z):
                return None
            return -rd + min(scatter.nearest(x, z), 20.0)
        return pred

    def toward_road(x, z):
        _d, q = land.line_dist((x, z), land.roads)
        dx, dz = q[0] - x, q[1] - z
        n = math.hypot(dx, dz) or 1.0
        return (dx / n, dz / n)

    # caves: in a slope, looked at from below its mouth
    for rid, brief in (("core:region/skerrow", "a limestone mouth in the scar above the dale"),
                       ("core:region/briarwold", "a root-cave under an old oak on the bank")):
        spot = land.search(slope_pred(9.0, 18.0), rid)
        if spot:
            d, _ = land.downhill(spot[1], spot[2])
            add("cave_" + rid.split("/")[-1], "cave", rid, spot, brief, d, 24.0, 4.0)

    def sea_pred(x, z):
        if land.h(x, z) > 7.0 or land.h(x, z) < 1.0 or not land.clear(x, z, 8.0, 30.0):
            return None
        _d, drop = land.downhill(x, z)
        if drop < 3.0 or not land.water_near(x, z, 36.0):
            return None
        return drop

    spot = land.search(sea_pred, "core:region/cinderlea")
    if spot:
        d, _ = land.downhill(spot[1], spot[2])
        add("cave_sea", "cave", "core:region/cinderlea", spot, "a sea-cave under the Hushline where the tide comes in", d, 20.0, 3.0, 14.0)

    # a quarry: a Vale slope, for its chalk face, gentle enough for the floor it is cut down to
    spot = land.search(slope_pred(4.0, 9.0), "core:region/hearthvale")
    if spot:
        d, _ = land.downhill(spot[1], spot[2])
        add("quarry", "quarry", "core:region/hearthvale", spot, "the chalk pit where the Vale's lime was cut", d, 32.0, 7.0)

    # level ground off a road
    for label, kind, rid, brief, lo, hi, dist, height, enc, day in (
            ("farmstead", "farmstead", "core:region/hearthvale", "a cob farm with a dog that barks at nothing", 20.0, 45.0, 36.0, 9.0, "none; jobs", None),
            ("market_field", "market_field", "core:region/skerrow", "Kharrow Foot, where the drovers meet", 24.0, 50.0, 40.0, 10.0, "", 3),
            ("waystone", "waystone", "core:region/cinderlea", "the ninth waystone the pilgrims count", 3.0, 10.0, 7.0, 1.7, "", None)):
        spot = land.search(near_road(lo, hi), rid)
        if spot:
            add(label, kind, rid, spot, brief, toward_road(spot[1], spot[2]), dist, height, 11.0, enc, day,
                look_up=0.9 if kind == "waystone" else 2.0)

    # a mill: level ground by a river, seen from the water side, where its wheel is
    def mill_pred(x, z):
        rd, _q = land.line_dist((x, z), land.rivers)
        if rd < 14.0 or rd > 40.0 or land.pad_dist((x, z)) < 60.0 or land.slope(x, z) > 0.1 \
                or land.line_dist((x, z), land.roads)[0] < 10.0 or land.is_wet(x, z):
            return None
        return -rd + min(scatter.nearest(x, z), 20.0)

    spot = land.search(mill_pred, "core:region/hearthvale")
    if spot:
        w = land.water_dir(spot[1], spot[2]) or (0.6, 0.8)
        add("mill", "mill", "core:region/hearthvale", spot, "the mill on the Larkbourne", w, 28.0, 6.0)

    # a windmill: a Brightwater rise, seen from upwind, where its sails face
    def rise_pred(x, z):
        if not land.clear(x, z) or land.slope(x, z) > 0.12:
            return None
        around = min(land.h(x + math.sin(a) * 120.0, z + math.cos(a) * 120.0) for a in [k * 0.785 for k in range(8)])
        return land.h(x, z) - around

    spot = land.search(rise_pred, "core:region/brightwater")
    if spot:
        add("windmill", "mill", "core:region/brightwater", spot, "a windmill with four sails on the ridge", (-WIND[0], -WIND[1]), 32.0, 4.0)

    # a shieling: the high fell, from a little above it
    def fell_pred(x, z):
        if not land.clear(x, z, 30.0, 150.0) or land.slope(x, z) > 0.12:
            return None
        return land.h(x, z)

    spot = land.search(fell_pred, "core:region/skerrow", step=40.0)
    if spot:
        d, _ = land.downhill(spot[1], spot[2])
        add("shieling", "shieling", "core:region/skerrow", spot, "a summer hut on the high fell", d if d != (0.0, 0.0) else (0.6, 0.8), 18.0, 7.0, 14.0)

    # a vista: an edge the ground falls away from, seen from behind its bench, looking out
    def edge_pred(x, z):
        if not land.clear(x, z, 10.0, 60.0) or land.slope(x, z, 6.0) > 0.15:
            return None
        d, drop = land.downhill(x, z)
        far = sum(land.h(x, z) - land.h(x + d[0] * r, z + d[1] * r) for r in (80.0, 160.0, 300.0))
        return far if drop > 2.0 else None

    def view_of(x, z):
        """The vista builder's own `_view`: the bearing the ground falls furthest along over the
        next few hundred metres, so the camera finds the bench where the builder puts it."""
        h0 = land.h(x, z)
        best = None
        for a in range(0, 360, 10):
            u = (math.sin(math.radians(a)), math.cos(math.radians(a)))
            drop = sum(h0 - land.h(x + u[0] * r, z + u[1] * r) for r in (40.0, 90.0, 160.0, 260.0, 400.0))
            if best is None or drop > best[0]:
                best = (drop, u)
        return best[1] if best[0] > 4.0 else None

    spot = land.search(edge_pred, "core:region/hearthvale")
    if spot:
        _, x, z = spot
        d, _ = land.downhill(x, z)
        v = view_of(x, z) or d
        # the seat, seen from behind and to one side at ten metres, the country it looks at beyond
        bx, bz = x + v[0] * 7.0, z + v[1] * 7.0
        a = math.atan2(-v[1], -v[0]) + math.radians(40.0)
        add("vista", "vista", "core:region/hearthvale", spot, "the bench at the Larkmouth where the Vale opens",
            (math.cos(a), math.sin(a)), 10.0, 2.4, 12.0, look_up=0.6, target=(bx, bz))
        shots[-1]["look_at"] = [round(bx + v[0] * 6.0, 1), round(land.h(bx, bz) + 0.2, 1), round(bz + v[1] * 6.0, 1)]

    # a beacon and a plain watch, raised to eleven or twelve metres with their crowns: on a
    # hilltop, from far enough out to see the crown against the sky
    def top_pred(x, z):
        if not land.clear(x, z, 12.0, 60.0) or land.slope(x, z, 6.0) > 0.1 or scatter.nearest(x, z) < 8.0:
            return None
        return land.h(x, z)

    spot = land.search(top_pred, "core:region/hearthvale", step=40.0)
    add("beacon", "tower", "core:region/hearthvale", spot, "a beacon on the hill, its fire-bowl ready", (0.7, 0.7), 45.0, 3.0, 15.0,
        look_up=6.0)
    spot = land.search(top_pred, "core:region/skerrow", step=40.0)
    add("watch", "tower", "core:region/skerrow", spot, "a watch over the dale", (0.6, -0.8), 45.0, 3.0, 11.0, look_up=6.0)

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"shots": shots}, f, indent=1)
        f.write("\n")
    print(len(shots), "shots ->", os.path.relpath(OUT, REPO))


if __name__ == "__main__":
    main()
