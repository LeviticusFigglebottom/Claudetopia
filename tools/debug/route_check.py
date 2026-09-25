"""Checks a marked way against the built world, as test_the_start does, and against every solid
scene the build stood near it (with the footprint of its model's bounds).

    python3 tools/debug/route_check.py game                      (the Stair Head's waystones)
    python3 tools/debug/route_check.py game '[[x, z], ...]'      (any other way)

It reads the built world under game/world/generated: the full-resolution maps where this machine
built them (`./run.sh world`), else the runtime copies the tracked world carries (8 m, so a slope
is judged over 8 m rather than 4). The Stair Head's way is found as the game finds it
(PoiDressing.way_points): the built road to the Choir, else the path's shape between the two, and
it stops where reaching the Choir counts, as the stones do. Each problem names its leg: slopes over
30 degrees, water, an enemy spawn within 50 m, and a solid scene whose footprint the way passes
within 1.5 m of.
"""
import json
import math
import os
import struct
import sys

GAME = sys.argv[1]
GEN = os.path.join(GAME, "world/generated")
man = json.load(open(os.path.join(GEN, "world_manifest.json")))
GRID = int(man["grid"])
SP = float(man["spacing_m"])
OX, OZ = man["origin"]
WX, WZ = OX, OZ
WGRID, WSP = GRID, SP
if os.path.exists(os.path.join(GEN, "heights.r32")):
    heights = open(os.path.join(GEN, "heights.r32"), "rb")
    water = open(os.path.join(GEN, "water_mask.u8"), "rb")
    STEP = 4.0
else:
    # the tracked world: the runtime copies, heights centred on their block (TerrainProvider)
    rt = man["runtime"]
    low = int(rt["grid"])
    full_sp = SP
    SP = WSP = float(man["size_m"]) / low
    OX += (GRID // low - 1) * full_sp * 0.5
    OZ += (GRID // low - 1) * full_sp * 0.5
    GRID = WGRID = low
    heights = open(os.path.join(GEN, rt["heights"]), "rb")
    water = open(os.path.join(GEN, rt["water"]), "rb")
    STEP = SP
    print("(no full-resolution maps: reading the runtime copies at %.0f m)" % SP)


def h(ix, iz):
    ix = min(max(ix, 0), GRID - 1)
    iz = min(max(iz, 0), GRID - 1)
    heights.seek((iz * GRID + ix) * 4)
    return struct.unpack("<f", heights.read(4))[0]


def ground(x, z):
    fx = min(max((x - OX) / SP, 0.0), GRID - 1.001)
    fz = min(max((z - OZ) / SP, 0.0), GRID - 1.001)
    x0, z0 = int(fx), int(fz)
    tx, tz = fx - x0, fz - z0
    a = h(x0, z0) + (h(x0 + 1, z0) - h(x0, z0)) * tx
    b = h(x0, z0 + 1) + (h(x0 + 1, z0 + 1) - h(x0, z0 + 1)) * tx
    return a + (b - a) * tz


def wet(x, z):
    ix = min(max(int(round((x - WX) / WSP)), 0), WGRID - 1)
    iz = min(max(int(round((z - WZ) / WSP)), 0), WGRID - 1)
    water.seek(iz * WGRID + ix)
    return water.read(1)[0] != 0


def seg_dist(p, a, b):
    ax, az = a
    bx, bz = b
    px, pz = p
    dx, dz = bx - ax, bz - az
    L = dx * dx + dz * dz
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L))
    cx, cz = ax + dx * t, az + dz * t
    return math.hypot(px - cx, pz - cz)


_foot = {}


def footprint(scene):
    if scene in _foot:
        return _foot[scene]
    r = 0.0
    meta = os.path.join(GAME, scene.replace("res://", "")).replace(".glb", ".meta.json")
    if os.path.exists(meta):
        b = json.load(open(meta)).get("bounds", {})
        mn, mx = b.get("min", [0, 0, 0]), b.get("max", [0, 0, 0])
        r = max(abs(mn[0]), abs(mx[0]), abs(mn[2]), abs(mx[2]))
    _foot[scene] = r
    return r


PACK = os.path.join(GAME, "content/packs/core")
defs = json.load(open(os.path.join(PACK, "pois/pois.json")))
places = {d["id"]: d for d in defs}
places.update({d["id"]: d for d in json.load(open(os.path.join(PACK, "places/places.json")))})
start = places["core:poi/stair_head"]
start_xz = tuple(float(v) for v in start["position"])
way = start["path"]
goal_xz = tuple(float(v) for v in places[way["to"]]["position"])
# how near a `reach` objective's place counts as there (QuestLog.REACH_RADIUS_M), less a margin:
# the stones stop inside it (test_the_start._via)
STOP_M = 40.0


def the_way():
    for r in json.load(open(os.path.join(GEN, "roads.json"))):
        if r["id"] != way.get("built_road"):
            continue
        pts = [(float(p[0]), float(p[-1])) for p in r["points"]]
        if math.dist(pts[0], start_xz) > math.dist(pts[-1], start_xz):
            pts.reverse()
        return pts, "the built road %s" % r["id"]
    ax, az = start_xz
    ux, uz = goal_xz[0] - ax, goal_xz[1] - az
    pts = [(ax + ux * a - uz * c, az + uz * a + ux * c) for a, c in [[0, 0]] + way["shape"] + [[1, 0]]]
    return pts, "the path's shape"


if len(sys.argv) > 2:
    route, source = json.loads(sys.argv[2]), "the way given"
else:
    whole, source = the_way()
    route = []
    for p in whole:
        route.append(p)
        if len(route) >= 2 and math.dist(p, goal_xz) <= STOP_M:
            break
print("the way: %s" % source)

spawns = []
solids = []
for f in os.listdir(os.path.join(GEN, "cells")):
    if not f.endswith(".json"):
        continue
    cell = json.load(open(os.path.join(GEN, "cells", f)))
    for s in cell.get("spawns", []):
        if s.get("kind") == "enemy":
            p = s["pos"]
            if math.hypot(p[0] - start_xz[0], p[2] - start_xz[1]) < 800:
                spawns.append((s.get("def"), (p[0], p[2])))
    for s in cell.get("scenes", []):
        if not s.get("collision"):
            continue
        p = s["pos"]
        if math.hypot(p[0] - start_xz[0], p[2] - start_xz[1]) < 800:
            solids.append((s["scene"].split("/")[-1], (p[0], p[2]), footprint(s["scene"]) * float(s.get("scale", 1.0))))

problems = []
length = 0.0
for i in range(len(route) - 1):
    a, b = route[i], route[i + 1]
    d = math.hypot(b[0] - a[0], b[1] - a[1])
    length += d
    n = max(1, math.ceil(d / STEP))
    for s in range(n):
        p = (a[0] + (b[0] - a[0]) * s / n, a[1] + (b[1] - a[1]) * s / n)
        q = (a[0] + (b[0] - a[0]) * (s + 1) / n, a[1] + (b[1] - a[1]) * (s + 1) / n)
        rise = abs(ground(*q) - ground(*p))
        slope = math.degrees(math.atan2(rise, math.hypot(q[0] - p[0], q[1] - p[1])))
        if slope > 30.0:
            problems.append("leg %d: %.0f deg at (%.0f, %.0f)" % (i, slope, p[0], p[1]))
        if wet(*p):
            problems.append("leg %d: water at (%.0f, %.0f)" % (i, p[0], p[1]))
    for name, at in spawns:
        dd = seg_dist(at, a, b)
        if dd < 50.0:
            problems.append("leg %d: %s %.0f m from it" % (i, name, dd))
    for name, at, r in solids:
        dd = seg_dist(at, a, b)
        if dd < r + 1.5:
            problems.append("leg %d (%s -> %s): %s at (%.0f, %.0f), %.1f m from its centre, its footprint %.1f m" % (i, a, b, name, at[0], at[1], dd, r))
print("route of %d points, %.0f m" % (len(route), length))
print("last point %.1f m from %s; the start test wants 300-650 m" % (math.dist(route[-1], goal_xz), way["to"]))
print("solid scenes within 800 m: %d; enemies: %d" % (len(solids), len(spawns)))
for p in problems:
    print("  " + p)
print("OK" if not problems else "%d problems" % len(problems))
