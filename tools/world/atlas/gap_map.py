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
    for sub in (("places", "places.json"), ("pois", "pois.json")):
        p = os.path.join(pack, *sub)
        if not os.path.exists(p):
            continue
        for d in json.load(open(p, encoding="utf-8")):
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
WAYSIDE_PAD_M = 12.0
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


def sites(m: dict, only: list | None = None, provinces: list | None = None) -> list:
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
    for sub in (("places", "places.json"), ("pois", "pois.json")):
        pp = os.path.join(m.get("pack", PACK), *sub)
        if os.path.exists(pp):
            for dd in json.load(open(pp, encoding="utf-8")):
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
                    for off in SITE_OFF_M:
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
