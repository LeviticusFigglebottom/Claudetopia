#!/usr/bin/env python3
"""What a built world does to the places the content names: the checks to run after the map
is drawn again (docs/COORDINATES.md).

Reads a build directory (world_manifest.json and runtime/ maps; roads.json, pois.json and cells/
when present) and the core content pack, and reports, with coordinates:

* places and POIs standing in water (bridges, wrecks, falls, edges and "strange" POIs excepted);
* door-plan doors (a ring round their place) on water or ground steeper than 25 degrees;
* NPC schedule legs, walked along the built roads the way the game walks them (RoadRoutes), and
  quest escorts from the person's home to the place in a straight line, that cross more than 40 m
  of water off the roads (a road's own crossing is its bridge or its ford);
* quest markers, reach, escort and kill places with no dry ground within their radius;
* anything that fights standing within 50 m of the start's way (the road from the opening place
  to its path's end, test_the_start's CLEAR_OF_ENEMIES_M).

    tools/world/place_checks.py                       # game/world/generated
    tools/world/place_checks.py --world <build dir>

It exits 0 whatever it finds: several of these are the map's to answer (a lake commute may be
meant), and the reasons go to whoever drew it.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import sys

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACK = os.path.join(REPO, "game", "content", "packs", "core")
WET_KINDS = {"bridge", "wreck", "strange", "waterfall", "edge"}
STEEP_DEG = 25.0
WATER_LEG_M = 40.0
CLEAR_OF_ENEMIES_M = 50.0
DEFAULT_RADIUS = {"reach": 45.0, "escort": 45.0, "marker": 45.0, "kill": 140.0}


class World:
    def __init__(self, gen: str) -> None:
        self.gen = gen
        self.man = json.load(open(os.path.join(gen, "world_manifest.json")))
        rt = self.man["runtime"]
        self.n = int(rt["grid"])
        size = float(self.man.get("size_m", 8192))
        self.sp = size / self.n
        full = int(self.man.get("grid", 0))
        off = rt.get("height_offset_m")
        if off is None:
            off = (full // self.n - 1) * (size / full) * 0.5 if full > self.n and full % self.n == 0 else 0.0
        self.ox, self.oz = float(self.man["origin"][0]), float(self.man["origin"][1])
        self.hx, self.hz = self.ox + float(off), self.oz + float(off)
        self.H = np.fromfile(os.path.join(gen, rt["heights"]), dtype="<f4").reshape(self.n, self.n)
        self.W = np.fromfile(os.path.join(gen, rt["water"]), dtype=np.uint8).reshape(self.n, self.n)
        self.L = np.fromfile(os.path.join(gen, rt["water_level"]), dtype="<f4").reshape(self.n, self.n)

    def _ij(self, x: float, z: float) -> tuple[int, int]:
        # TerrainProvider._index: the texel under the point, no offset
        i = int(min(max((z - self.oz) / self.sp, 0), self.n - 1))
        j = int(min(max((x - self.ox) / self.sp, 0), self.n - 1))
        return i, j

    def wet(self, x: float, z: float) -> bool:
        return bool(self.W[self._ij(x, z)] != 0)

    def level(self, x: float, z: float) -> float:
        return float(self.L[self._ij(x, z)])

    def height(self, x: float, z: float) -> float:
        # TerrainProvider.sample_height: bilinear, first texel centred at the offset
        fx = min(max((x - self.hx) / self.sp, 0.0), self.n - 1.001)
        fz = min(max((z - self.hz) / self.sp, 0.0), self.n - 1.001)
        x0, z0 = int(fx), int(fz)
        tx, tz = fx - x0, fz - z0
        x1, z1 = min(x0 + 1, self.n - 1), min(z0 + 1, self.n - 1)
        top = self.H[z0, x0] + (self.H[z0, x1] - self.H[z0, x0]) * tx
        bot = self.H[z1, x0] + (self.H[z1, x1] - self.H[z1, x0]) * tx
        return float(top + (bot - top) * tz)

    def slope_deg(self, x: float, z: float, d: float = 2.0) -> float:
        gx = (self.height(x + d, z) - self.height(x - d, z)) / (2 * d)
        gz = (self.height(x, z + d) - self.height(x, z - d)) / (2 * d)
        return math.degrees(math.atan(math.hypot(gx, gz)))

    def wet_runs(self, a, b, step: float = 4.0) -> list:
        """Stretches of water on the straight line from a to b: (start, end, length, level)."""
        k = max(1, int(math.dist(a, b) / step))
        out, cur = [], None
        for i in range(k + 1):
            t = i / k
            x, z = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            if self.wet(x, z):
                cur = [(x, z), (x, z), self.level(x, z)] if cur is None else [cur[0], (x, z), cur[2]]
            elif cur is not None:
                out.append(cur)
                cur = None
        if cur is not None:
            out.append(cur)
        return [(s, e, math.dist(s, e), lv) for s, e, lv in out if math.dist(s, e) > 8.0]

    def nearest_dry(self, x: float, z: float, limit: float = 400.0):
        i0, j0 = self._ij(x, z)
        r = int(limit / self.sp)
        best = None
        for di in range(-r, r + 1):
            for dj in range(-r, r + 1):
                i, j = i0 + di, j0 + dj
                if 0 <= i < self.n and 0 <= j < self.n and self.W[i, j] == 0:
                    cx, cz = self.ox + (j + 0.5) * self.sp, self.oz + (i + 0.5) * self.sp
                    d = math.hypot(cx - x, cz - z)
                    if best is None or d < best[0]:
                        best = (d, cx, cz)
        return best


# --- the roads, the way the game walks them (game/systems/npc_life/road_routes.gd) -----------------

JOIN_M = 22.0      # road ends this close are one junction
REACH_M = 140.0    # a place is reached by every road end this near its pad
ACROSS_M = 900.0   # or by the nearest within this, walked to across country


class Roads:
    def __init__(self, gen: str) -> None:
        self.nodes: list = []
        self.edges: dict = {}
        path = os.path.join(gen, "roads.json")
        if not os.path.exists(path):
            return
        for r in json.load(open(path, encoding="utf-8")):
            pts = [tuple(map(float, p)) for p in r.get("points", [])]
            if len(pts) < 2:
                continue
            a, b = self._node(pts[0]), self._node(pts[-1])
            if a == b:
                continue
            length = sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
            self.edges.setdefault(a, []).append((b, length, pts))
            self.edges.setdefault(b, []).append((a, length, pts[::-1]))

    def _node(self, p) -> int:
        for i, q in enumerate(self.nodes):
            if math.dist(p, q) <= JOIN_M:
                return i
        self.nodes.append(p)
        return len(self.nodes) - 1

    def _near(self, p) -> list:
        out = [i for i, q in enumerate(self.nodes) if math.dist(p, q) <= REACH_M]
        if not out and self.nodes:
            i = min(range(len(self.nodes)), key=lambda k: math.dist(p, self.nodes[k]))
            if math.dist(p, self.nodes[i]) <= ACROSS_M:
                out = [i]
        return out

    def route(self, a, b) -> tuple:
        """(points, on_road) from a to b: the way along the roads, and for each stretch whether it
        is a road's own. The straight line, all off-road, when the roads do not join them."""
        starts, ends = self._near(a), self._near(b)
        if not starts or not ends:
            return [a, b], [False]
        import heapq
        dist = {n: math.dist(self.nodes[n], a) for n in starts}
        prev: dict = {}
        heap = [(d, n) for n, d in dist.items()]
        heapq.heapify(heap)
        best, best_end, done = math.inf, -1, set()
        while heap:
            d, n = heapq.heappop(heap)
            if n in done or d >= best:
                continue
            done.add(n)
            if n in ends and d + math.dist(self.nodes[n], b) < best:
                best, best_end = d + math.dist(self.nodes[n], b), n
            for to, length, pts in self.edges.get(n, []):
                if d + length < dist.get(to, math.inf):
                    dist[to] = d + length
                    prev[to] = (n, pts)
                    heapq.heappush(heap, (d + length, to))
        if best_end < 0:
            return [a, b], [False]
        legs, at = [], best_end
        while at in prev:
            n, pts = prev[at]
            legs.insert(0, pts)
            at = n
        if not legs:
            return [a, b], [False]
        points, on = [a], []
        for pts in legs:
            for i, q in enumerate(pts):
                if math.dist(points[-1], q) > 0.5:
                    points.append(q)
                    on.append(i > 0)
        points.append(b)
        on.append(False)
        return points, on


def content() -> dict:
    defs = {}
    for f in glob.glob(os.path.join(PACK, "**", "*.json"), recursive=True):
        try:
            data = json.load(open(f, encoding="utf-8"))
        except Exception:
            continue
        for d in data if isinstance(data, list) else []:
            if isinstance(d, dict) and "id" in d:
                defs[d["id"]] = d
    return defs


def xz(defs: dict, pid: str):
    p = defs.get(pid, {}).get("position")
    return (float(p[0]), float(p[1])) if isinstance(p, list) and len(p) >= 2 else None


def fmt(p) -> str:
    return "(%.0f, %.0f)" % (p[0], p[1])


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--world", default=os.path.join(REPO, "game", "world", "generated"))
    args = ap.parse_args(argv)
    w = World(args.world)
    defs = content()
    print("world %s: built %s, atlas %s" % (args.world, w.man.get("built_at"), w.man.get("atlas", {}).get("crc")))

    print("\n== places and POIs standing in water")
    for pid, d in sorted(defs.items()):
        p = xz(defs, pid)
        if p and pid.split("/")[0] in ("core:place", "core:poi") and d.get("kind") not in WET_KINDS and w.wet(*p):
            print("  %-40s %-14s at %s: water at %.1f m over ground at %.1f m" % (pid, d.get("kind", ""), fmt(p), w.level(*p), w.height(*p)))

    print("\n== door-plan doors on water or ground steeper than %.0f degrees" % STEEP_DEG)
    built = {}
    if os.path.exists(os.path.join(args.world, "pois.json")):
        built = {e["place_id"]: e for e in json.load(open(os.path.join(args.world, "pois.json")))}
    for pid, d in sorted(defs.items()):
        if d.get("role") != "door_plan":
            continue
        c = xz(defs, d.get("place", ""))
        if d.get("place") in built:
            c = (built[d["place"]]["pos"][0], built[d["place"]]["pos"][2])
        if c is None:
            print("  %s: its place %s says nowhere" % (pid, d.get("place")))
            continue
        for row in d.get("rows", []):
            b = math.radians(float(row.get("bearing_deg", 0.0)))
            r = float(row.get("ring_radius", 20.0))
            x, z = c[0] + math.sin(b) * r, c[1] + math.cos(b) * r     # WorldDoors._place_one
            s = w.slope_deg(x, z)
            if w.wet(x, z) or s > STEEP_DEG:
                print("  %-40s at %s: %sslope %.0f deg" % (row.get("interior", "?"), fmt((x, z)), "water, " if w.wet(x, z) else "", s))

    print("\n== legs across more than %.0f m of water off the roads (schedules by road, escorts straight)" % WATER_LEG_M)
    legs = set()
    for pid, d in sorted(defs.items()):
        if pid.startswith("core:npc/"):
            home = d.get("home_place", "")
            stops = [home] + [e.get("place", "") for e in d.get("schedule", [])]
            stops = [home if s == "home" else s for s in stops if s]
            legs.update((pid, a, b) for a, b in zip(stops, stops[1:]) if a != b and (pid, b, a) not in legs)
        if pid.startswith("core:quest/"):
            for st in d.get("stages", []):
                for o in st.get("objectives", []):
                    if o.get("type") == "escort" and o.get("target") in defs and o.get("place"):
                        legs.add((pid + " escort", defs[o["target"]].get("home_place", ""), o["place"]))
    roads = Roads(args.world)
    for who, a, b in sorted(legs):
        pa, pb = xz(defs, a), xz(defs, b)
        if pa and pb:
            # people walk their day along the roads (RoadRoutes); an escort follows the player
            if who.endswith(" escort"):
                runs = w.wet_runs(pa, pb)
            else:
                points, on = roads.route(pa, pb)
                runs = [r for i in range(len(points) - 1) if not on[i] for r in w.wet_runs(points[i], points[i + 1])]
            if sum(r[2] for r in runs) > WATER_LEG_M:
                print("  %-36s %s -> %s:" % (who, a, b))
                for s, e, length, lv in runs:
                    print("      %s to %s: %.0f m of water at %.1f m" % (fmt(s), fmt(e), length, lv))

    print("\n== quest places with no dry ground within their radius")
    seen = set()
    for qid, q in sorted(defs.items()):
        if not qid.startswith("core:quest/"):
            continue
        for st in q.get("stages", []):
            objs = list(st.get("objectives", []))
            if isinstance(st.get("marker"), dict):
                objs.append({"type": "marker", "place": st["marker"].get("place_id", ""), "radius": st["marker"].get("radius", 45)})
            for o in objs:
                typ = o.get("type", "")
                place = o.get("place") or o.get("where") or ""
                if typ not in DEFAULT_RADIUS or not isinstance(place, str) or xz(defs, place) is None or (qid, place) in seen:
                    continue
                seen.add((qid, place))
                radius = float(o.get("radius", DEFAULT_RADIUS[typ]))
                p = xz(defs, place)
                dry = w.nearest_dry(*p)
                if dry is None or dry[0] > radius:
                    print("  %-40s %-7s %s r %.0f: nearest dry ground %s" % (qid, typ, place, radius,
                          "none within 400 m" if dry is None else "%.0f m off at %s" % (dry[0], fmt(dry[1:]))))

    print("\n== anything that fights within %.0f m of the start's way" % CLEAR_OF_ENEMIES_M)
    opening = defs.get("core:opening/new_game", {})
    start = opening.get("place", "")
    to = (defs.get(start, {}).get("path") or {}).get("to", "")
    roads_path = os.path.join(args.world, "roads.json")
    if start and to and os.path.exists(roads_path):
        name = lambda i: i.split("/")[-1]
        ids = {"core:road/%s_%s" % (name(start), name(to)), "core:road/%s_%s" % (name(to), name(start))}
        road = next((r for r in json.load(open(roads_path)) if r.get("id") in ids), None)
        if road is None:
            print("  no built road from %s to %s: the waystones follow the path's drawn shape" % (start, to))
        else:
            pts = road["points"]
            length = sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))
            print("  %s: %.0f m (test_the_start wants 300-650 m)" % (road["id"], length))
            for f in sorted(glob.glob(os.path.join(args.world, "cells", "*.json"))):
                for s in json.load(open(f)).get("spawns", []):
                    if s.get("kind") != "enemy":
                        continue
                    p = (float(s["pos"][0]), float(s["pos"][2]))
                    d = min(_seg_dist(p, a, b) for a, b in zip(pts, pts[1:]))
                    if d < CLEAR_OF_ENEMIES_M:
                        print("  %-26s at %s: %.1f m from the way (group %s)" % (s.get("def"), fmt(p), d, s.get("group", "")))
    return 0


def _seg_dist(p, a, b) -> float:
    dx, dz = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / l2))
    return math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dz))


if __name__ == "__main__":
    sys.exit(main())
