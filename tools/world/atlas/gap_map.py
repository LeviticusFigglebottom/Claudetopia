#!/usr/bin/env python3
"""The gap map: where a walker goes a long way between things worth stopping for.

    python3 tools/world/atlas/gap_map.py                        # the tracked world, game/world/generated
    python3 tools/world/atlas/gap_map.py --world /tmp/w1024     # any build (its roads.json, its heights)
    python3 tools/world/atlas/gap_map.py --out gaps.png --json gaps.json --list 40

The user's playtest-5 complaint was that "the world still feels empty between places". The
atlas was drawn to a coverage rule (preview.py: nothing on a road more than 250 m from a
location), and it keeps it, and the complaint stands: 250 m either side of a thing is a 500 m
walk between two of them. This measures what a walker feels instead: along every built road,
how far you go between passing one thing and passing the next.

**A thing** is every place and every point of interest in the content packs, and so every
wayside find, farmstead, mill and cave, which are points of interest (`"wayside": true` marks the
finds). Places of the edge and deep kinds are left out: they are not stood beside. A settlement
counts out to its pad radius (from the build's pois.json, or `worldgen.roads.pad_radius` for a
thing the build has not seen yet) plus its outskirts, OUTSKIRTS_M.

**Passing a thing** is coming within NEAR_M of it (of a settlement's outskirts): close enough to
see it for what it is and step off the road to it.

**A gap** is a run of road on which you pass nothing. It is **thin** when it is longer than
THIN_M: a minute of the player's jog (5 m/s), 300 m. The headline figure, "N of M km thin", is
the road inside thin gaps over all the built road, the settlements' own streets included (they
are never thin).

**Across the land**, walkable ground (not water, under 35 degrees, not the closing ranges or the
snowfield, as preview.py reads them) further than LAND_THIN_M from any thing is empty country.

The picture is the built land, hill-shaded, with the roads in grey, the thin gaps over them in
red (darker the longer), numbered from the longest, the empty country shaded, and the things as
dots: settlements black, points of interest dark grey, wayside finds orange. The JSON lists every
thin gap with its road, ends, length, province and the things at either end: the work list for
the next wave of finds.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

from worldgen import atlas as ATLAS  # noqa: E402
from worldgen import content as CONTENT  # noqa: E402
from worldgen.roads import pad_radius  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
GEN = os.path.join(REPO, "game", "world", "generated")
PACK = os.path.join(REPO, "game", "content", "packs", "core")

## the definitions the module docstring states
NEAR_M = 60.0
OUTSKIRTS_M = 40.0
THIN_M = 300.0
LAND_THIN_M = 300.0
STEP_M = 5.0
## place kinds that are not stood beside
NOT_THINGS = ("edge", "deep_place", "interior_dungeon")
## preview.py's reading of what is not country
WALKABLE_SLOPE = 0.70
SNOWLINE_M = 520.0
CLOSURES = {"skerrow_wall": "north", "thornmarch": "east"}
CREST_M = 120.0


# --- reading ---------------------------------------------------------------------------------


def pack_defs(pack: str) -> list:
    """Every place def (places/places.json) and every POI def (every pois/*.json)."""
    out = []
    path = os.path.join(pack, "places", "places.json")
    if os.path.exists(path):
        out += json.load(open(path, encoding="utf-8"))
    return out + CONTENT.poi_registry(pack)

def things(pack: str = PACK, world: str = GEN) -> list:
    """Every thing worth stopping for: dicts {id, name, kind, x, z, r, cls} where r is how far
    out from its position it counts as there (a settlement's pad and outskirts; 0 for a point
    of interest) and cls is 'place', 'poi' or 'wayside'."""
    built = {}
    path = os.path.join(world, "pois.json")
    if os.path.exists(path):
        for e in json.load(open(path, encoding="utf-8")):
            built[e["place_id"]] = float(e.get("radius_flat_m", 0.0))
    out = []
    for d in pack_defs(pack):
        pos = d.get("position")
        kind = str(d.get("kind", ""))
        if not pos or len(pos) < 2 or kind in NOT_THINGS:
            continue
        is_place = ":place/" in d["id"]
        r = 0.0
        if is_place and kind in ATLAS.SETTLEMENT_KINDS:
            r = built.get(d["id"], pad_radius(d)) + OUTSKIRTS_M
        cls = "place" if is_place else ("wayside" if d.get("wayside") else "poi")
        out.append({"id": d["id"], "name": d.get("name", d["id"]), "kind": kind,
                    "x": float(pos[0]), "z": float(pos[1]), "r": r, "cls": cls})
    return out


def roads(world: str = GEN, atlas: dict | None = None, pack: str = PACK) -> list:
    """The built roads [(id, [(x, z), ...])], or, with no build, the atlas's drawn ones."""
    path = os.path.join(world, "roads.json")
    if os.path.exists(path):
        return [(r["id"], [(float(p[0]), float(p[1])) for p in r["points"]])
                for r in json.load(open(path, encoding="utf-8"))]
    atlas = atlas or ATLAS.load()
    where = {t["id"]: (t["x"], t["z"]) for t in things(pack, world)}
    out = []
    for r in atlas.get("roads", []):
        a, b = where.get(r["from"]), where.get(r["to"])
        if a is None or b is None:
            continue
        rid = r.get("id") or "core:road/%s_%s" % (r["from"].split("/")[-1], r["to"].split("/")[-1])
        out.append((rid, [a] + [tuple(v) for v in r.get("via", [])] + [b]))
    return out


def resample(pts: list, step: float) -> tuple:
    """(points [n, 2], distance along [n]) every `step` metres along a polyline."""
    P = np.asarray(pts, np.float64)
    seg = np.hypot(*np.diff(P, axis=0).T)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    total = float(s[-1])
    if total <= 0.0:
        return P[:1], np.zeros(1)
    t = np.linspace(0.0, total, max(int(math.ceil(total / step)) + 1, 2))
    return np.stack([np.interp(t, s, P[:, 0]), np.interp(t, s, P[:, 1])], axis=1), t


# --- measuring -------------------------------------------------------------------------------

def road_gaps(road_list: list, thing_list: list, near: float = NEAR_M, thin: float = THIN_M,
              step: float = STEP_M) -> dict:
    """Every run of road passing nothing; the thin ones; the totals."""
    T = np.array([[t["x"], t["z"]] for t in thing_list], np.float64)
    R = np.array([t["r"] for t in thing_list], np.float64)
    gaps = []
    total = 0.0
    for rid, pts in road_list:
        if len(pts) < 2:
            continue
        P, s = resample(pts, step)
        length = float(s[-1])
        total += length
        d = np.hypot(P[:, None, 0] - T[None, :, 0], P[:, None, 1] - T[None, :, 1]) - R[None, :]
        nearest = np.argmin(d, axis=1)
        at = d[np.arange(len(P)), nearest] <= near
        k = 0
        n = len(P)
        while k < n:
            if at[k]:
                k += 1
                continue
            m = k
            while m < n and not at[m]:
                m += 1
            # the run is from the last point at something to the first one again
            a = s[k - 1] if k > 0 else s[k]
            b = s[m] if m < n else s[m - 1]
            run = float(b - a)
            before = thing_list[nearest[k - 1]]["id"] if k > 0 else ""
            after = thing_list[nearest[m]]["id"] if m < n else ""
            mid = P[(k + m - 1) // 2]
            gaps.append({"road": rid, "length_m": run, "from": [float(P[k][0]), float(P[k][1])],
                         "to": [float(P[m - 1][0]), float(P[m - 1][1])],
                         "mid": [float(mid[0]), float(mid[1])],
                         "points": [[float(x), float(z)] for x, z in P[k:m][::4]] +
                                   [[float(P[m - 1][0]), float(P[m - 1][1])]],
                         "after": before, "before": after})
            k = m
    thin_gaps = sorted((g for g in gaps if g["length_m"] > thin), key=lambda g: -g["length_m"])
    return {"road_km": total / 1000.0,
            "thin_km": sum(g["length_m"] for g in thin_gaps) / 1000.0,
            "gap_km": sum(g["length_m"] for g in gaps) / 1000.0,
            "thin": thin_gaps,
            "longest_m": thin_gaps[0]["length_m"] if thin_gaps else max([g["length_m"] for g in gaps] or [0.0])}


def load_land(world: str) -> tuple:
    """(heights, water) as n x n float/bool over the world, from the build's runtime arrays or
    its full-size heights."""
    man = json.load(open(os.path.join(world, "world_manifest.json"), encoding="utf-8"))
    rt = os.path.join(world, "runtime")
    for n in (1024, 512, 2048):
        h = os.path.join(rt, "heights_%d.r32" % n)
        w = os.path.join(rt, "water_%d.u8" % n)
        if os.path.exists(h) and os.path.exists(w):
            H = np.fromfile(h, dtype="<f4").reshape(n, n)
            W = np.fromfile(w, dtype=np.uint8).reshape(n, n) > 0
            return H, W, float(man.get("size_m", 8192.0))
    g = int(man["grid"])
    H = np.fromfile(os.path.join(world, "heights.r32"), dtype="<f4").reshape(g, g)
    W = np.fromfile(os.path.join(world, "water_mask.u8"), dtype=np.uint8).reshape(g, g) > 0
    f = max(g // 1024, 1)
    n = g // f
    H = H[:n * f, :n * f].reshape(n, f, n, f).mean(axis=(1, 3))
    W = W[:n * f, :n * f].reshape(n, f, n, f).max(axis=(1, 3))
    return H, W, float(man.get("size_m", 8192.0))


def walkable(H: np.ndarray, W: np.ndarray, size_m: float, atlas: dict) -> np.ndarray:
    n = H.shape[0]
    res = size_m / n
    c = (np.arange(n, dtype=np.float32) + 0.5) * res - size_m / 2.0
    xs, zs = c[None, :], c[:, None]
    gz, gx = np.gradient(H.astype(np.float64), res)
    edge = H > SNOWLINE_M
    for r in atlas.get("ranges", []):
        side = CLOSURES.get(r["id"])
        if side is None:
            continue
        crest = np.array([[p[0], p[1]] for p in r["ridge"]], np.float32)
        if side == "north":
            o = np.argsort(crest[:, 0])
            zc = np.interp(xs[0], crest[o, 0], crest[o, 1])
            edge |= zs < zc[None, :] + CREST_M
        else:
            o = np.argsort(crest[:, 1])
            xc = np.interp(zs[:, 0], crest[o, 1], crest[o, 0])
            edge |= xs > xc[:, None] - CREST_M
    return (H > 0.3) & ~W & (np.hypot(gx, gz) < WALKABLE_SLOPE) & ~edge


def land_gaps(walk: np.ndarray, size_m: float, thing_list: list, far: float = LAND_THIN_M) -> dict:
    n = walk.shape[0]
    res = size_m / n
    seeds = np.ones((n, n), bool)
    for t in thing_list:
        j = int(min(max((t["x"] + size_m / 2) / res, 0), n - 1))
        i = int(min(max((t["z"] + size_m / 2) / res, 0), n - 1))
        rr = int(t["r"] / res)
        if rr <= 0:
            seeds[i, j] = False
        else:
            i0, i1, j0, j1 = max(i - rr, 0), min(i + rr + 1, n), max(j - rr, 0), min(j + rr + 1, n)
            ii, jj = np.mgrid[i0:i1, j0:j1]
            seeds[i0:i1, j0:j1] &= (ii - i) ** 2 + (jj - j) ** 2 > rr * rr
    dist = ndimage.distance_transform_edt(seeds) * res
    empty = walk & (dist > far)
    cell = (res / 1000.0) ** 2
    labels, nlab = ndimage.label(empty)
    blobs = []
    if nlab:
        sizes = ndimage.sum(empty, labels, range(1, nlab + 1))
        for k in np.argsort(-sizes)[:40]:
            if sizes[k] * cell < 0.02:
                break
            ys, xs_ = np.nonzero(labels == k + 1)
            w = int(np.argmax(dist[ys, xs_]))
            blobs.append({"area_km2": float(sizes[k] * cell), "worst_m": float(dist[ys[w], xs_[w]]),
                          "at": [float((xs_[w] + 0.5) * res - size_m / 2), float((ys[w] + 0.5) * res - size_m / 2)]})
    return {"walkable_km2": float(walk.sum() * cell), "empty_km2": float(empty.sum() * cell),
            "blobs": blobs, "dist": dist, "empty": empty}


## A wayside find is small: a stone, a gibbet, a cairn, a shrine in a wall. It asks the builder
## for a pad of about this radius, not the 25 m every other point of interest gets, so it can sit
## on a dale side without a quarry's worth of cut and fill.
WAYSIDE_PAD_M = 14.0
## where a wayside find may stand: a pace off the road, on ground a pad can take, clear of water
## and of every other thing. The spacing answers "how many does a gap want": a find a pace off
## the road is passed along about 2 * sqrt(NEAR_M^2 - SITE_OFF_M^2) of it, about 110 m.
SITE_OFF_M = (16.0, 22.0, 28.0)
SITE_SLOPE = 0.36          # about 20 degrees across a wayside pad (WAYSIDE_PAD_M)
## on a dale side there may be no such ground near the spot: then steeper, further along
SITE_SLOPE_STEEP = 0.5     # about 27 degrees
SHIFTS_M = (0.0, -30.0, 30.0, -60.0, 60.0, -90.0, 90.0, -120.0, 120.0, -150.0, 150.0)
SHIFTS_STEEP_M = tuple(float(v) for v in range(-240, 241, 30))
SITE_CLEAR_M = 110.0       # from every other thing
SITE_ROAD_CLEAR_M = 12.0   # from every road's centre line
SITE_RIVER_CLEAR_M = 14.0  # past a river's half width


def sites(m: dict, only: list | None = None, provinces: list | None = None,
          offsets: tuple = SITE_OFF_M, need_sight: bool = False) -> list:
    """Proposed places for wayside finds along the thin gaps, the longest first: enough evenly
    along each gap that no run of it stays thin. Each is {gap, road, province, at, slope,
    height}. A gap with no good ground at a spot gets nothing there, and says so ("none")."""
    if "H" not in m:
        return []
    H, W, size_m = m["H"], m["W"], m["size_m"]
    n = H.shape[0]
    res = size_m / n
    gz, gx = np.gradient(H.astype(np.float64), res)
    slope = np.hypot(gx, gz)

    def cell(x, z):
        return (int(min(max((z + size_m / 2) / res, 0), n - 1)), int(min(max((x + size_m / 2) / res, 0), n - 1)))

    rivers = []
    rp = os.path.join(m.get("world", GEN), "rivers.json")
    if os.path.exists(rp):
        for r in json.load(open(rp, encoding="utf-8")):
            rivers.append((np.asarray(r["points"], np.float64)[:, :2], float(r.get("width_m", 8.0))))
    road_pts = np.concatenate([resample(p, 6.0)[0] for _rid, p in m["roads"] if len(p) > 1])
    # clear of everything the packs stand anywhere, the mine mouths and edges included
    taken = [(t["x"], t["z"]) for t in m["things"]]
    for dd in pack_defs(m.get("pack", PACK)):
        pos = dd.get("position")
        if pos and len(pos) >= 2 and str(dd.get("kind", "")) in NOT_THINGS:
            taken.append((float(pos[0]), float(pos[1])))
    out = []
    for gi, g in enumerate(m["road"]["thin"]):
        if only and gi + 1 not in only:
            continue
        if provinces and g.get("province") not in provinces:
            continue
        pts = [tuple(p) for p in g["points"]]
        P, s = resample(pts, 4.0)
        L = float(s[-1])
        k = max(int(math.ceil((g["length_m"] - THIN_M) / 410.0)), 1)
        for i in range(1, k + 1):
            at = L * i / (k + 1)
            best = None
            # the gentle tier first; on a dale side, steeper ground further along the gap
            for max_slope, shifts in ((SITE_SLOPE, SHIFTS_M), (SITE_SLOPE_STEEP, SHIFTS_STEEP_M)):
                if best is not None:
                    break
                for shift in shifts:
                    u = min(max(at + shift, 0.0), L)
                    c = int(np.searchsorted(s, u))
                    c = min(max(c, 1), len(P) - 1)
                    d = P[c] - P[c - 1]
                    d = d / max(np.hypot(*d), 1e-6)
                    side = np.array([-d[1], d[0]])
                    for off in offsets:
                        for sgn in (1.0, -1.0):
                            x, z = P[c] + side * off * sgn
                            i_, j_ = cell(x, z)
                            if W[max(i_ - 3, 0):i_ + 4, max(j_ - 3, 0):j_ + 4].any():
                                continue
                            sl = float(slope[max(i_ - 1, 0):i_ + 2, max(j_ - 1, 0):j_ + 2].max())
                            if sl > max_slope:
                                continue
                            if min(math.hypot(x - a, z - b) for a, b in taken) < SITE_CLEAR_M:
                                continue
                            if float(np.min(np.hypot(road_pts[:, 0] - x, road_pts[:, 1] - z))) < SITE_ROAD_CLEAR_M:
                                continue
                            wet = False
                            for rpts, w in rivers:
                                if float(np.min(np.hypot(rpts[:, 0] - x, rpts[:, 1] - z))) < w * 0.5 + SITE_RIVER_CLEAR_M:
                                    wet = True
                                    break
                            if wet:
                                continue
                            if need_sight and not _sees(H, size_m, (float(P[c][0]), float(P[c][1])), (float(x), float(z))):
                                continue
                            score = sl + abs(shift) / 400.0 + off / 200.0
                            if best is None or score < best[0]:
                                best = (score, float(x), float(z), sl)
            prov = g.get("province", "")
            if best is None:
                out.append({"gap": gi + 1, "road": g["road"], "province": prov, "at": None,
                            "near": [float(v) for v in P[min(int(np.searchsorted(s, at)), len(P) - 1)]]})
                continue
            _sc, x, z, sl = best
            taken.append((x, z))
            i_, j_ = cell(x, z)
            out.append({"gap": gi + 1, "road": g["road"], "province": province_name(m["atlas"], x, z),
                        "at": [round(x), round(z)], "slope": round(sl, 3), "height": round(float(H[i_, j_]), 1)})
    return out


## Off the road: a find there has to give a walker a reason to leave the track, and the first
## reason is seeing it. An off-road site stands where the eye (EYE_M over a road) sees the top of
## something about a cairn's height (OFFROAD_TOP_M) over the ground between, no further than
## OFFROAD_SEEN_M from the road.
EYE_M = 1.65
OFFROAD_TOP_M = 2.2
OFFROAD_SEEN_M = 320.0
OFFROAD_MIN_M = 30.0
## where the thin road is a dale's switchbacks and nothing will stand a pace off it: further up or
## down the slope, where the road can still see it
SWITCHBACK_OFF_M = (35.0, 50.0, 65.0, 80.0, 95.0)


def _sees(H, size_m, a, b, eye=EYE_M, top=OFFROAD_TOP_M, clearance=0.5) -> bool:
    """Whether an eye at a (x, z) sees the top of a thing at b over the heights between."""
    n = H.shape[0]
    res = size_m / n

    def h(x, z):
        fx = min(max((x + size_m / 2) / res - 0.5, 0.0), n - 1.001)
        fz = min(max((z + size_m / 2) / res - 0.5, 0.0), n - 1.001)
        j, i = int(fx), int(fz)
        tx, tz = fx - j, fz - i
        return float((H[i, j] * (1 - tx) + H[i, j + 1] * tx) * (1 - tz) + (H[i + 1, j] * (1 - tx) + H[i + 1, j + 1] * tx) * tz)
    y0 = h(*a) + eye
    y1 = h(*b) + top
    d = math.hypot(b[0] - a[0], b[1] - a[1])
    steps = max(int(d / 6.0), 2)
    for k in range(1, steps):
        t = k / steps
        g = h(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        if g > y0 + (y1 - y0) * t - clearance:
            return False
    return True


def offroad_sites(m: dict, provinces: list | None = None, max_slope: float = SITE_SLOPE) -> list:
    """Proposed places for finds off the road, one to each patch of empty country: the walkable
    point that is furthest from any thing, among those a walker on a road can see from within
    OFFROAD_SEEN_M. Each is {at, province, seen_from, road_m, empty_m, area_km2, slope, height}."""
    if "land" not in m:
        return []
    H, size_m, walk = m["H"], m["size_m"], m["walk"]
    L = m["land"]
    n = H.shape[0]
    res = size_m / n
    gz, gx = np.gradient(H.astype(np.float64), res)
    slope = np.hypot(gx, gz)
    road_pts = np.concatenate([resample(p, 12.0)[0] for _rid, p in m["roads"] if len(p) > 1])
    labels, nlab = ndimage.label(L["empty"])
    out = []
    taken = [(t["x"], t["z"]) for t in m["things"]]
    for k in range(1, nlab + 1):
        ys, xs = np.nonzero(labels == k)
        area = len(ys) * (res / 1000.0) ** 2
        if area < 0.02:
            continue
        cx = (xs + 0.5) * res - size_m / 2
        cz = (ys + 0.5) * res - size_m / 2
        order = np.argsort(-L["dist"][ys, xs])
        best = None
        for idx in order[::3][:400]:
            x, z = float(cx[idx]), float(cz[idx])
            i, j = ys[idx], xs[idx]
            if not walk[i, j] or float(slope[max(i - 1, 0):i + 2, max(j - 1, 0):j + 2].max()) > max_slope:
                continue
            if min(math.hypot(x - a, z - b) for a, b in taken) < SITE_CLEAR_M:
                continue
            dr = np.hypot(road_pts[:, 0] - x, road_pts[:, 1] - z)
            near = np.nonzero((dr <= OFFROAD_SEEN_M) & (dr >= OFFROAD_MIN_M))[0]
            seen = None
            for r in near[np.argsort(dr[near])][:24]:
                if _sees(H, size_m, (float(road_pts[r, 0]), float(road_pts[r, 1])), (x, z)):
                    seen = r
                    break
            if seen is None:
                continue
            best = (x, z, int(seen), float(dr[seen]), float(L["dist"][i, j]), float(slope[i, j]), float(H[i, j]))
            break
        if best is None:
            continue
        x, z, r, dist_r, empty_m, sl, hh = best
        taken.append((x, z))
        prov = province_name(m["atlas"], x, z)
        if provinces and prov not in provinces:
            continue
        out.append({"at": [round(x), round(z)], "province": prov, "area_km2": round(area, 3),
                    "empty_m": round(empty_m), "seen_from": [round(float(road_pts[r, 0])), round(float(road_pts[r, 1]))],
                    "road_m": round(dist_r), "slope": round(sl, 3), "height": round(hh, 1)})
    return out


# --- threats along the roads ------------------------------------------------------------------

## The user's sixth playtest: "no enemies other than the starter area's". The country's own
## spawns are kept off the verges (worldgen/encounters.py: 14 m from every road, 120-420 m round
## every settlement), so what a road-keeper meets is what the authored encounters stand up at the
## places along the road. A threat is a place or point of interest an encounter def stands foes up
## at; it is met from the road within THREAT_NEAR_M of it (its group stands on the pad's rim).
THREAT_NEAR_M = 80.0
## A run of road longer than this with no threat met is quiet; the aim is one threat every
## 600-900 m outside the start's safe way, fewer in the quiet provinces.
QUIET_M = 900.0
## The first minutes of a new game belong to the opening: the roads the Naming walks and rides,
## and anything within START_SAFE_M of the Stair Head, stand nothing up.
START_AT = (10.0, 3670.0)
START_SAFE_M = 1500.0
SAFE_ROADS = ("core:road/stair_head_sunken_choir", "core:road/stair_head_hushline_stair",
              "core:road/sunken_choir_pilgrims_ash", "core:road/pilgrims_ash_ashwell",
              "core:road/ashwell_wynstead", "core:road/wynstead_merrowby")


def threats(pack: str = PACK) -> list:
    """Every place a def in encounters/ stands foes up at: {id, x, z, spawns, file}."""
    pos = {}
    for d in pack_defs(pack):
        if d.get("position") and len(d["position"]) >= 2:
            pos[d["id"]] = (float(d["position"][0]), float(d["position"][1]))
    out = []
    folder = os.path.join(pack, "encounters")
    for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
        if not name.endswith(".json"):
            continue
        for e in json.load(open(os.path.join(folder, name), encoding="utf-8")):
            where = e.get("place", "")
            if e.get("spawns") and where in pos:
                out.append({"id": where, "x": pos[where][0], "z": pos[where][1], "spawns": e["spawns"], "file": name})
    return out


def _safe(rid: str, x: float, z: float) -> bool:
    return rid in SAFE_ROADS or math.hypot(x - START_AT[0], z - START_AT[1]) < START_SAFE_M


def road_threats(road_list: list, threat_list: list, near: float = THREAT_NEAR_M, quiet: float = QUIET_M,
                 step: float = STEP_M) -> dict:
    """Threats met per km of road outside the start's safe way, and the quiet runs between them.
    Street roads (inside settlements) and the safe way are left out of both."""
    T = np.array([[t["x"], t["z"]] for t in threat_list], np.float64) if threat_list else np.zeros((0, 2))
    total = 0.0
    met = set()
    runs = []
    for rid, pts in road_list:
        if len(pts) < 2 or rid.endswith("_street") or "_street_" in rid:
            continue
        P, s = resample(pts, step)
        safe = np.array([_safe(rid, x, z) for x, z in P])
        if T.shape[0]:
            d = np.hypot(P[:, None, 0] - T[None, :, 0], P[:, None, 1] - T[None, :, 1])
            hit = d.min(axis=1) <= near
            for k in np.nonzero(d.min(axis=0) <= near)[0]:
                if not safe[np.argmin(d[:, k])]:
                    met.add(threat_list[k]["id"])
        else:
            hit = np.zeros(len(P), bool)
        total += float(np.sum(~safe)) * step
        k = 0
        while k < len(P):
            if hit[k] or safe[k]:
                k += 1
                continue
            m_ = k
            while m_ < len(P) and not hit[m_] and not safe[m_]:
                m_ += 1
            run = float(s[min(m_, len(P) - 1)] - s[k])
            if run > quiet:
                mid = P[(k + m_ - 1) // 2]
                runs.append({"road": rid, "length_m": run, "from": [float(P[k][0]), float(P[k][1])],
                             "to": [float(P[m_ - 1][0]), float(P[m_ - 1][1])], "mid": [float(mid[0]), float(mid[1])],
                             "points": [[float(x), float(z)] for x, z in P[k:m_][::4]]})
            k = m_
    runs.sort(key=lambda r: -r["length_m"])
    return {"road_km": total / 1000.0, "met": len(met), "per_km": len(met) / max(total / 1000.0, 1e-6),
            "quiet": runs, "quiet_km": sum(r["length_m"] for r in runs) / 1000.0}


def province_name(atlas: dict, x: float, z: float) -> str:
    p, _ = ATLAS.province_at(atlas, x, z)
    return p.get("name", p["id"]) if p else ""


# --- the picture -----------------------------------------------------------------------------

def render(out: str, H, W, walk, land, size_m, road_list, road, thing_list, atlas, size=2048,
           title="") -> None:
    n = H.shape[0]
    res = size_m / n
    gz, gx = np.gradient(H.astype(np.float64), res)
    lx, lz, ly = -0.6, -0.6, 0.55
    shade = np.clip((-gx * lx - gz * lz + ly) / np.sqrt(gx * gx + gz * gz + 1.0)
                    / math.sqrt(lx * lx + lz * lz + ly * ly), 0.0, 1.0)
    base = np.interp(H, [-30, 0, 0.01, 40, 160, 400, 650], [70, 90, 200, 190, 175, 185, 235])
    rgb = np.stack([base * 1.0, base * 0.98, base * 0.88], -1) * (0.55 + 0.6 * shade[..., None])
    rgb[W] = rgb[W] * 0.3 + np.array([80, 120, 160]) * 0.7
    rgb[land["empty"]] = rgb[land["empty"]] * 0.55 + np.array([230, 150, 60]) * 0.45
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").resize((size, size), Image.BILINEAR)
    d = ImageDraw.Draw(img, "RGBA")
    k = size / size_m

    def P(x, z):
        return ((x + size_m / 2) * k, (z + size_m / 2) * k)

    for prov in atlas.get("provinces", []):
        q = [P(*p) for p in prov["polygon"]]
        d.line(q + [q[0]], fill=(255, 255, 255, 90), width=1)
    for _rid, pts in road_list:
        d.line([P(*p) for p in pts], fill=(90, 80, 70, 255), width=2)
    for g in road["thin"]:
        a = min(1.0, (g["length_m"] - THIN_M) / 700.0)
        col = (int(255 - 90 * a), int(60 - 50 * a), 30, 255)
        d.line([P(*p) for p in g["points"]], fill=col, width=5)
    for t in thing_list:
        x, y = P(t["x"], t["z"])
        if t["cls"] == "place":
            r = max(3.0, t["r"] * k * 0.6)
            d.ellipse([x - r, y - r, x + r, y + r], outline=(0, 0, 0, 255), width=2)
        else:
            r = 2.5
            col = (255, 150, 0, 255) if t["cls"] == "wayside" else (40, 40, 40, 255)
            d.ellipse([x - r, y - r, x + r, y + r], fill=col)
    for i, g in enumerate(road["thin"][:60]):
        x, y = P(*g["mid"])
        d.text((x + 4, y - 6), "%d" % (i + 1), fill=(120, 0, 0, 255), stroke_width=2, stroke_fill=(255, 255, 255, 255))
    d.rectangle([0, 0, size, 40], fill=(255, 255, 255, 200))
    d.text((10, 6), title, fill=(0, 0, 0, 255))
    d.text((10, 22), "red: road with nothing within %d m for over %d m (darker = longer); orange ground: walkable, "
                     "over %d m from anything; black rings: settlements; dots: POIs (orange: wayside finds)"
           % (NEAR_M, THIN_M, LAND_THIN_M), fill=(0, 0, 0, 255))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    img.save(out)


# --- the whole ---------------------------------------------------------------------------------

def measure(world: str = GEN, pack: str = PACK, atlas_path: str = ATLAS.ATLAS_PATH,
            near: float = NEAR_M, thin: float = THIN_M, land_far: float = LAND_THIN_M) -> dict:
    atlas = ATLAS.load(atlas_path)
    tl = things(pack, world)
    rl = roads(world, atlas, pack)
    road = road_gaps(rl, tl, near, thin)
    for g in road["thin"]:
        g["province"] = province_name(atlas, *g["mid"])
    out = {"things": tl, "roads": rl, "road": road, "atlas": atlas, "world": world, "pack": pack}
    if os.path.exists(os.path.join(world, "world_manifest.json")):
        H, W, size_m = load_land(world)
        walk = walkable(H, W, size_m, atlas)
        out.update({"H": H, "W": W, "walk": walk, "size_m": size_m,
                    "land": land_gaps(walk, size_m, tl, land_far)})
    return out


def summary(m: dict) -> str:
    r = m["road"]
    tl = m["things"]
    s = ("%.1f of %.1f km of road thin (%d gaps over %d m; longest %.0f m); %d things "
         "(%d places, %d POIs, %d wayside)" % (
             r["thin_km"], r["road_km"], len(r["thin"]), THIN_M, r["longest_m"], len(tl),
             sum(t["cls"] == "place" for t in tl), sum(t["cls"] == "poi" for t in tl),
             sum(t["cls"] == "wayside" for t in tl)))
    if "land" in m:
        L = m["land"]
        s += "; %.1f of %.1f km2 walkable ground over %d m from anything" % (
            L["empty_km2"], L["walkable_km2"], LAND_THIN_M)
    return s


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--world", default=GEN)
    ap.add_argument("--pack", default=PACK)
    ap.add_argument("--atlas", default=ATLAS.ATLAS_PATH)
    ap.add_argument("--out", default="", help="write the picture here")
    ap.add_argument("--json", default="", help="write every thin gap here")
    ap.add_argument("--size", type=int, default=2048)
    ap.add_argument("--list", type=int, default=20, help="print this many of the longest gaps")
    ap.add_argument("--near", type=float, default=NEAR_M)
    ap.add_argument("--thin", type=float, default=THIN_M)
    ap.add_argument("--sites", default="", help="write proposed wayside-find sites along the thin gaps here (JSON)")
    ap.add_argument("--province", action="append", default=[], help="with --sites: only gaps in this province (repeatable)")
    ap.add_argument("--switchbacks", default="", help="write proposed sites 30-90 m off the thin gaps, seen from the road, here (JSON)")
    ap.add_argument("--threats", action="store_true", help="also measure the threats met along the roads")
    ap.add_argument("--offroad", default="", help="write proposed off-road sites, one to each patch of empty country, here (JSON)")
    a = ap.parse_args(argv)
    m = measure(a.world, a.pack, a.atlas, a.near, a.thin)
    text = summary(m)
    print(text)
    for i, g in enumerate(m["road"]["thin"][:a.list]):
        print("%3d. %5.0f m  %-26s %s  (%.0f, %.0f)-(%.0f, %.0f)" % (
            i + 1, g["length_m"], g["province"][:26], g["road"].replace("core:road/", ""),
            g["from"][0], g["from"][1], g["to"][0], g["to"][1]))
    if "land" in m:
        for b in m["land"]["blobs"][:min(a.list, 10)]:
            print("   empty %.2f km2 about (%.0f, %.0f), %.0f m from anything at worst, in %s" % (
                b["area_km2"], b["at"][0], b["at"][1], b["worst_m"], province_name(m["atlas"], *b["at"])))
    if a.json:
        doc = {"summary": text, "near_m": a.near, "thin_m": a.thin, "land_thin_m": LAND_THIN_M,
               "road_km": m["road"]["road_km"], "thin_km": m["road"]["thin_km"],
               "thin": [{k: v for k, v in g.items() if k != "points"} for g in m["road"]["thin"]]}
        if "land" in m:
            doc.update({"walkable_km2": m["land"]["walkable_km2"], "empty_km2": m["land"]["empty_km2"],
                        "empty": m["land"]["blobs"]})
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(doc, f, indent=1)
    if a.sites:
        ss = sites(m, provinces=a.province or None)
        with open(a.sites, "w", encoding="utf-8") as f:
            json.dump(ss, f, indent=1)
        print("%d sites proposed (%d gaps with no good ground at a spot) -> %s" % (
            sum(1 for s in ss if s["at"]), sum(1 for s in ss if not s["at"]), a.sites))
    if a.threats:
        th = road_threats(m["roads"], threats(a.pack))
        print("threats: %d met along %.1f km of road outside the start's safe way, %.2f a km (one every %.0f m); "
              "%d quiet runs over %d m, %.1f km" % (th["met"], th["road_km"], th["per_km"], 1000.0 / max(th["per_km"], 1e-6),
                                                    len(th["quiet"]), QUIET_M, th["quiet_km"]))
        for r in th["quiet"][:a.list]:
            print("  quiet %5.0f m  %-24s %s" % (r["length_m"], province_name(m["atlas"], *r["mid"])[:24], r["road"].replace("core:road/", "")))
    if a.switchbacks:
        ss = sites(m, provinces=a.province or None, offsets=SWITCHBACK_OFF_M, need_sight=True)
        with open(a.switchbacks, "w", encoding="utf-8") as f:
            json.dump(ss, f, indent=1)
        print("%d sites off the thin gaps proposed (%d spots with none) -> %s" % (
            sum(1 for s in ss if s["at"]), sum(1 for s in ss if not s["at"]), a.switchbacks))
    if a.offroad:
        ss = offroad_sites(m, provinces=a.province or None)
        with open(a.offroad, "w", encoding="utf-8") as f:
            json.dump(ss, f, indent=1)
        print("%d off-road sites proposed, each seen from a road within %d m -> %s" % (len(ss), OFFROAD_SEEN_M, a.offroad))
    if a.out:
        if "land" not in m:
            print("no built land at %s: no picture" % a.world)
        else:
            render(a.out, m["H"], m["W"], m["walk"], m["land"], m["size_m"], m["roads"], m["road"],
                   m["things"], m["atlas"], a.size, "Wickmere gap map: " + text)
            print(a.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
