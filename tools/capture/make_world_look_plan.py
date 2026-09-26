#!/usr/bin/env python3
"""Write a capture plan for the world builder's looks: the waterfalls' steps, scattered rock where a
player meets it, roads through open country, and the crags' ledges near and far.

Every camera is checked against the ground it looks over: it stands on land, over no water, at
least EYE_M above the ground under it, and the ground between it and what it looks at stays under
the line of sight (it is raised, then brought nearer, until it does). A camera 14 m downhill of a
boulder stood inside the slab beside it, one looking at the Glass Falls looked into its own slope,
and the far ledge shot stood under the sea: those were the first batch 4 plan's.

    tools/capture/make_world_look_plan.py                                 # game/world/generated
    tools/capture/make_world_look_plan.py --world <build dir> --out /tmp/plan.json
    tools/capture/make_world_look_plan.py --only falls,rocks      # falls rocks roads ledges trees fences caves slopes
    tools/capture/make_world_look_plan.py --falls whitecut,kharrow        # only these falls
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(REPO, "game", "world", "generated")
HOUR = {"core:region/hearthvale": (9.0, "core:weather/clear"), "core:region/brightwater": (12.0, "core:weather/clear"),
        "core:region/sedgemire": (10.0, "core:weather/overcast"), "core:region/briarwold": (10.5, "core:weather/still"),
        "core:region/skerrow": (14.0, "core:weather/clear_cold"), "core:region/cinderlea": (16.5, "core:weather/dry_wind")}
EYE_M = 1.7
## how far over the line of sight's own height the ground between may come (a blade of grass)
SIGHT_SPARE_M = 0.4


## what a camera may not stand in, and how near (metres, times the plant's scale): a tree's crown,
## a bush, a hedge; and how far along its sight line it must be clear of them
PLANT_REACH = (("/trees/", 3.5), ("hedge", 2.5), ("bracken", 1.2), ("fern", 1.2), ("briar", 1.5),
               ("foxglove", 1.0), ("reeds", 1.2), ("bulrush", 1.0), ("heather", 0.9), ("gorse", 1.5))
PLANT_SIGHT_M = 8.0


def _plants(path: str):
    """Every tree and bush of a built world's cells: their (x, z) and how near a camera may come."""
    pts, reach = [], []
    for fn in sorted(glob.glob(os.path.join(path, "cells", "*.json"))):
        d = json.load(open(fn))
        for a, rows in d["instances"].items():
            r = next((m for k, m in PLANT_REACH if k in a and "_impostor" not in a), None)
            if r is None:
                continue
            for row in rows:
                pts.append((row[0], row[2]))
                reach.append(r * max(float(row[4]), 0.5))
    return np.asarray(pts, dtype=np.float64).reshape(-1, 2), np.asarray(reach, dtype=np.float64)


class World:
    """The runtime maps of a built world (what the game reads): heights, water and regions."""

    def __init__(self, path: str):
        self.path = path
        m = json.load(open(os.path.join(path, "world_manifest.json")))
        rt = m["runtime"]
        self.n = int(rt["grid"])
        self.size = float(m["size_m"])
        self.x0, self.z0 = (float(v) for v in m["origin"])
        self.sp = self.size / self.n
        self.off = float(rt.get("height_offset_m", 0.0 if self.n == int(m["grid"]) else 0.5 * (self.sp - m["spacing_m"])))
        self.H = np.fromfile(os.path.join(path, rt["heights"]), dtype="<f4").reshape(self.n, self.n)
        self.W = np.fromfile(os.path.join(path, rt["water"]), dtype=np.uint8).reshape(self.n, self.n)
        self.R = np.fromfile(os.path.join(path, rt["regions"]), dtype=np.uint8).reshape(self.n, self.n)
        self.regions = m["regions"]
        self._plants = None
        self._plant_tree = None

    def _ij(self, x, z, off=0.0):
        j = np.clip((np.asarray(x, dtype=np.float64) - self.x0 - off) / self.sp, 0, self.n - 1.001)
        i = np.clip((np.asarray(z, dtype=np.float64) - self.z0 - off) / self.sp, 0, self.n - 1.001)
        return j, i

    def h(self, x, z):
        j, i = self._ij(x, z, self.off)
        j0, i0 = np.floor(j).astype(int), np.floor(i).astype(int)
        tj, ti = j - j0, i - i0
        H = self.H
        return (H[i0, j0] * (1 - tj) * (1 - ti) + H[i0, j0 + 1] * tj * (1 - ti)
                + H[i0 + 1, j0] * (1 - tj) * ti + H[i0 + 1, j0 + 1] * tj * ti)

    def wet(self, x, z) -> bool:
        j, i = self._ij(x, z)
        return bool(self.W[int(round(float(i))), int(round(float(j)))] > 0)

    def region(self, x, z) -> str:
        j, i = self._ij(x, z)
        r = int(self.R[int(round(float(i))), int(round(float(j)))])
        return self.regions[r] if r < len(self.regions) else "core:region/brightwater"

    def clear(self, cam, look) -> bool:
        """The ground between `cam` and `look` stays under the line of sight."""
        t = np.linspace(0.04, 0.9, 48)
        x = cam[0] + (look[0] - cam[0]) * t
        z = cam[2] + (look[2] - cam[2]) * t
        y = cam[1] + (look[1] - cam[1]) * t
        return bool(np.all(self.h(x, z) < y - SIGHT_SPARE_M) and not self.leafy(cam, look))

    def trees_near(self, x: float, z: float, r: float) -> int:
        """How many trees and bushes stand within `r` metres of (x, z)."""
        if self._plants is None:
            self._plants = _plants(self.path)
        if len(self._plants[0]) == 0:
            return 0
        from scipy.spatial import cKDTree
        if self._plant_tree is None:
            self._plant_tree = cKDTree(self._plants[0])
        return len(self._plant_tree.query_ball_point((x, z), r))

    def leafy(self, cam, look) -> bool:
        """A tree or a bush stands at the camera, or across the first metres of its sight line.

        The w4096d ground review's frames 01, 05, 11 and 21 were shot from inside a hawthorn, a
        wood's understorey and a bush: the ground under them was clear, the plants on it were not.
        """
        if self._plants is None:
            self._plants = _plants(self.path)
        pts, reach = self._plants
        if len(pts) == 0:
            return False
        from scipy.spatial import cKDTree
        if self._plant_tree is None:
            self._plant_tree = cKDTree(pts)
        d = math.hypot(look[0] - cam[0], look[2] - cam[2])
        t = np.linspace(0.0, min(1.0, PLANT_SIGHT_M / max(d, 1e-3)), 9)
        probe = np.stack([cam[0] + (look[0] - cam[0]) * t, cam[2] + (look[2] - cam[2]) * t], axis=1)
        for q, near in zip(probe, self._plant_tree.query_ball_point(probe, float(reach.max()))):
            for k in near:
                if math.hypot(pts[k, 0] - q[0], pts[k, 1] - q[1]) < reach[k]:
                    return True
        return False


def frame(w: World, label: str, look, bearing: float, dist: float, above: float, fov: float = 60.0):
    """A shot of `look` from `dist` metres off on compass-free bearing (radians, x = sin, z = cos),
    `above` over the ground there; raised, swung and brought nearer until it is on dry land and
    sees its target. None where nothing will do."""
    for d in (dist, dist * 0.8, dist * 0.6, dist * 1.25):
        for swing in (0.0, 0.35, -0.35, 0.7, -0.7):
            a = bearing + swing
            cx, cz = look[0] + math.sin(a) * d, look[2] + math.cos(a) * d
            if w.wet(cx, cz):
                continue
            g = float(w.h(cx, cz))
            for up in (above, above + 3.0, above + 7.0, above + 14.0):
                cam = [cx, g + up, cz]
                if w.clear(cam, look):
                    r = w.region(cx, cz)
                    hour, weather = HOUR.get(r, (10.0, "core:weather/clear"))
                    return {"label": label, "region": r, "pos": [round(v, 2) for v in cam],
                            "height_above_ground": round(up, 2), "look_at": [round(float(v), 2) for v in look],
                            "fov": fov, "time": hour, "weather": weather, "fog_scale": 0.6}
    return None


def falls(w: World, only: list | None) -> list:
    out = []
    for e in json.load(open(os.path.join(w.path, "pois.json"))):
        f = e.get("fall")
        if not f or (only and not any(o in e["place_id"] for o in only)):
            continue
        a = math.radians(f["facing_deg"])
        fx, fz = math.sin(a), math.cos(a)
        x, _, z = e["pos"]
        back = f["faces"][-1]["behind_m"]
        drop = f["top_m"] - f["foot_m"]
        look = [x - fx * back * 0.5, f["foot_m"] + drop * 0.5, z - fz * back * 0.5]
        name = e["place_id"].split("/")[-1]
        for tag, swing, dist, up in (("front", 0.25, 32.0, 3.0), ("side", 1.05, 30.0, 6.0)):
            s = frame(w, "fall_%s_%s" % (name, tag), look, a + swing, dist, up, 62.0)
            if s:
                out.append(s)
    return out


def _rows(w: World, part: str):
    for fn in sorted(glob.glob(os.path.join(w.path, "cells", "*.json"))):
        d = json.load(open(fn))
        for a, rows in d["instances"].items():
            if part in a:
                for r in rows:
                    yield a, r


def rocks(w: World) -> list:
    """The biggest leaning boulder in each of four regions, at 22 m across the slope and 16 m
    below it: where a player walking the hillside sees it."""
    picked: dict = {}
    for a, r in _rows(w, "/rocks/"):
        if "_boulder_" not in a or len(r) < 8 or r[6] < 6.0:
            continue
        rg = w.region(r[0], r[2]).split("/")[-1]
        if rg not in ("briarwold", "skerrow", "hearthvale", "cinderlea"):
            continue
        # on a hillside a player walks, not a cliff's top: the ground 18 m below it within 8 m of
        # its height (the first pick stood the camera at a sea cliff's foot, 111 m under its boulder)
        t = math.radians(r[7])
        bx, bz = r[0] + math.cos(t) * 18.0, r[2] + math.sin(t) * 18.0
        if abs(float(w.h(bx, bz)) - r[1]) > 8.0 or w.wet(bx, bz):
            continue
        if rg not in picked or r[4] > picked[rg][4]:
            picked[rg] = r
    out = []
    for rg, r in sorted(picked.items()):
        t = math.radians(r[7])
        down = math.atan2(math.cos(t), math.sin(t))          # the bearing (x = sin) of the fall line
        look = [r[0], r[1] + 0.6, r[2]]
        for tag, bearing, dist, up in (("below", down, 18.0, EYE_M), ("across", down + math.pi / 2, 24.0, EYE_M)):
            s = frame(w, "rock_%s_%s" % (rg, tag), look, bearing, dist, up)
            if s:
                out.append(s)
    return out


def roads(w: World) -> list:
    rds = json.load(open(os.path.join(w.path, "roads.json")))
    P = np.array([(e["pos"][0], e["pos"][2]) for e in json.load(open(os.path.join(w.path, "pois.json")))])
    want = {"hearthvale": 1, "briarwold": 1, "skerrow": 1, "brightwater": 1, "sedgemire": 1}
    got: dict = {}
    out = []
    for rd in rds:
        pts = np.array([(p[0], p[-1]) for p in rd["points"]], dtype=np.float64)
        for k in range(5, len(pts) - 5, 7):
            x, z = pts[k]
            if np.min(np.hypot(P[:, 0] - x, P[:, 1] - z)) < 170.0:
                continue
            rg = w.region(x, z).split("/")[-1]
            if got.get(rg, 0) >= want.get(rg, 0):
                continue
            tx, tz = pts[k + 3] - pts[k - 1]
            L = math.hypot(tx, tz)
            tx, tz = tx / L, tz / L
            lx, lz = x + tx * 60, z + tz * 60
            s = frame(w, "road_%s" % rg, [lx, float(w.h(lx, lz)) + 1.2, lz], math.atan2(-tx, -tz), 62.0, EYE_M, 62.0)
            if s:
                got[rg] = got.get(rg, 0) + 1
                out.append(s)
                break
    return out


def ledges(w: World) -> list:
    """An inland Skerrow crag at 25 m and at 90 m, looking at the middle of its rows."""
    best = None
    for a, r in _rows(w, "cliff_ledge"):
        if "skerrow" not in a or r[1] < 60.0:
            continue
        if best is None or r[1] > best[1]:
            best = r
    if best is None:
        return []
    t = math.radians(best[3])
    out = []
    look = [best[0], best[1] + 2.5, best[2]]
    for tag, dist, up in (("near", 25.0, EYE_M), ("far", 90.0, 4.0)):
        s = frame(w, "ledge_%s" % tag, look, t, dist, up)
        if s:
            out.append(s)
    return out


def trees(w: World) -> list:
    """The trunk's foot of the biggest tree on the steepest ground in each of four regions, and of a
    giant oak: from 14 m below it, low, looking at its foot (playtest 6: a tree standing on its roots)."""
    # a tree standing on its own, so the frame sees its foot and not a wood's dark (the w4096c tree
    # frames were all under the canopy of the wood round the biggest tree)
    from scipy.spatial import cKDTree
    everyone = [(a, r) for a, r in _rows(w, "/trees/")]
    tree = cKDTree(np.array([(r[0], r[2]) for a, r in everyone])) if everyone else None
    picked: dict = {}
    for a, r in everyone:
        if len(tree.query_ball_point((r[0], r[2]), 18.0)) > 1:
            continue
        rg = w.region(r[0], r[2]).split("/")[-1]
        key = "giant_oak" if "giant_oak" in a else rg
        if key not in ("giant_oak", "briarwold", "hearthvale", "skerrow", "brightwater"):
            continue
        d = 3.0
        s = math.hypot(float(w.h(r[0] + d, r[2]) - w.h(r[0] - d, r[2])), float(w.h(r[0], r[2] + d) - w.h(r[0], r[2] - d))) / (2 * d)
        if s > 0.6:
            continue                # a slope a player stands on, not a crag's face
        score = s * r[4]
        if key not in picked or score > picked[key][0]:
            gx = float(w.h(r[0] + d, r[2]) - w.h(r[0] - d, r[2]))
            gz = float(w.h(r[0], r[2] + d) - w.h(r[0], r[2] - d))
            picked[key] = (score, r, math.atan2(-gx, -gz))
    out = []
    for key, (_, r, down) in sorted(picked.items()):
        look = [r[0], float(w.h(r[0], r[2])) + 1.0, r[2]]
        s = frame(w, "tree_%s" % key, look, down, 14.0, 1.4, 62.0)
        if s:
            out.append(s)
    return out


def caves(w: World) -> list:
    """Each cave's mouth in its face, from 16 m out in front and from the side (pois.json `cave`)."""
    out = []
    for e in json.load(open(os.path.join(w.path, "pois.json"))):
        c = e.get("cave")
        if not c:
            continue
        a = math.radians(c["facing_deg"])
        fx, fz = math.sin(a), math.cos(a)
        x, _, z = e["pos"]
        b = c["mouth_behind_m"]
        look = [x - fx * b, c["mouth_m"] + 2.0, z - fz * b]
        name = e["place_id"].split("/")[-1]
        for tag, swing, dist in (("front", 0.2, 16.0), ("side", 0.9, 18.0)):
            s = frame(w, "cave_%s_%s" % (name, tag), look, a + swing, dist, EYE_M, 62.0)
            if s:
                out.append(s)
    return out


def fences(w: World) -> list:
    """A run of rail or of wall beside a road in each region that has one, from a few metres off the
    road, looking along the run."""
    out = []
    seen: set = set()
    for part in ("fence_post_rail", "drystone_wall", "hedge_segment"):
        for a, r in _rows(w, part):
            rg = w.region(r[0], r[2]).split("/")[-1]
            if (rg, part) in seen:
                continue
            yaw = math.radians(r[3])
            ax, az = math.cos(yaw), -math.sin(yaw)          # the run lies along the piece's own +X
            look = [r[0] + ax * 12.0, float(w.h(r[0] + ax * 12.0, r[2] + az * 12.0)) + 0.6, r[2] + az * 12.0]
            s = frame(w, "run_%s_%s" % (part.split("_")[0], rg), look, math.atan2(-ax, -az) + 0.25, 16.0, EYE_M, 62.0)
            if s:
                seen.add((rg, part))
                out.append(s)
    return out


## the steep hillsides: which regions, how steep the ground round the target is on average
## (degrees), how wide that ground must be, and how far apart two shots of one region stand
SLOPE_REGIONS = ("hearthvale", "skerrow", "briarwold", "brightwater", "cinderlea")
SLOPE_DEG = ((34.0, 42.0), (42.0, 58.0))
SLOPE_WINDOW_M = 40.0
SLOPE_APART_M = 700.0


def slopes(w: World) -> list:
    """A steep hillside (a bank of 34-42 degrees, and a face of 42-58) in each of SLOPE_REGIONS, seen
    from 45 m off across and below it, at eye height: where the ground turns from turf to earth,
    scree and rock (surface.STEEP)."""
    from scipy import ndimage

    gz, gx = np.gradient(w.H.astype(np.float64), w.sp)
    deg = np.degrees(np.arctan(np.hypot(gx, gz)))
    k = max(3, int(SLOPE_WINDOW_M / w.sp))
    mean = ndimage.uniform_filter(deg, k)
    # smoothed downhill, over the window
    sgx, sgz = ndimage.uniform_filter(gx, k), ndimage.uniform_filter(gz, k)
    out = []
    for short in SLOPE_REGIONS:
        rid = "core:region/" + short
        if rid not in w.regions:
            continue
        mine = (w.R == w.regions.index(rid)) & (w.W == 0)
        mine = ndimage.binary_erosion(mine, iterations=k)
        for tag, (lo, hi) in zip(("bank", "face"), SLOPE_DEG):
            ok = mine & (mean >= lo) & (mean < hi)
            if not ok.any():
                continue
            ii, jj = np.nonzero(ok)
            # the middle of the band, deterministically: nearest to its mean slope, then its index
            order = np.lexsort((ii * w.n + jj, np.abs(mean[ii, jj] - 0.5 * (lo + hi))))
            taken = [s["look_at"] for s in out if s["label"].startswith("slope_%s" % short)]
            for o in order[:4000]:
                i, j = int(ii[o]), int(jj[o])
                x, z = w.x0 + (j + 0.5) * w.sp, w.z0 + (i + 0.5) * w.sp
                if any(math.hypot(x - t[0], z - t[2]) < SLOPE_APART_M for t in taken):
                    continue
                look = [x, float(w.h(x, z)) + 1.0, z]
                down = math.atan2(-sgx[i, j], -sgz[i, j])        # the bearing downhill (x = sin, z = cos)
                shot = frame(w, "slope_%s_%s" % (short, tag), look, down + 0.7, 45.0, EYE_M, 62.0)
                if shot:
                    out.append(shot)
                    break
    return out


REVIEW_REGIONS = ("hearthvale", "brightwater", "sedgemire", "briarwold", "skerrow", "cinderlea")


def review(w: World) -> list:
    """The ground, region by region, at eye height: a steep bank and face (`slopes`), the rock on a
    crag or a cliff (a ledge, a face piece or a crest boulder), a point of interest's pad from 18 m,
    and the roughest hillside, for terraces and odd ridges."""
    out = [dict(s, label=s["label"].replace("slope_", "rv_")) for s in slopes(w)]
    by_region: dict = {}
    # the rock: one piece of each kind a region has, its biggest, looked at from across its slope
    for a, r in _rows(w, "/rocks/"):
        kind = next((k for k in ("_cliff_ledge_", "_cliff_slab_", "_basalt_columns_", "_boulder_") if k in a), None)
        if kind is None:
            continue
        region = w.region(r[0], r[2]).split("/")[-1]
        if region not in REVIEW_REGIONS:
            continue
        key = (region, kind)
        if key not in by_region or r[4] > by_region[key][4]:
            by_region[key] = r
    for (region, kind), r in sorted(by_region.items()):
        if kind == "_boulder_":
            continue
        look = [r[0], r[1] + 1.5, r[2]]
        yaw = math.radians(r[3])
        shot = frame(w, "rv_%s_rock%s" % (region, kind.rstrip("_")), look, yaw + 0.5, 22.0, EYE_M)
        if shot:
            out.append(shot)
    # a point of interest's pad, from 18 m off on the downhill side: in each region the most open
    # one (the fewest trees within 25 m), since a pad deep in a wood photographs as the wood's
    # shade (the w4096d review's frame 21, Mossbridge in the Greatwood, was black)
    pads: dict = {}
    for e in json.load(open(os.path.join(w.path, "pois.json"))):
        if "fall" in e or "cave" in e or ":place/" in e["place_id"]:
            continue
        x, _y, z = e["pos"]
        region = w.region(x, z).split("/")[-1]
        if region in REVIEW_REGIONS and not w.wet(x, z):
            cover = w.trees_near(x, z, 25.0)
            if region not in pads or cover < pads[region][0]:
                pads[region] = (cover, e)
    pads = {k: v[1] for k, v in pads.items()}
    for region, e in sorted(pads.items()):
        x, y, z = e["pos"]
        gx = float(w.h(x + 10.0, z) - w.h(x - 10.0, z))
        gz = float(w.h(x, z + 10.0) - w.h(x, z - 10.0))
        down = math.atan2(-gx, -gz) if abs(gx) + abs(gz) > 0.05 else 0.0
        shot = frame(w, "rv_%s_pad_%s" % (region, e["place_id"].split("/")[-1]), [x, y + 1.0, z], down, 18.0, EYE_M)
        if shot:
            out.append(shot)
    # the roughest hillside: where the ground's curvature is greatest, over 60 m, in each region
    from scipy import ndimage
    lap = np.abs(ndimage.laplace(ndimage.gaussian_filter(w.H.astype(np.float64), 1.0)))
    rough = ndimage.uniform_filter(lap, max(3, int(60.0 / w.sp)))
    for short in REVIEW_REGIONS:
        rid = "core:region/" + short
        if rid not in w.regions:
            continue
        mine = ndimage.binary_erosion((w.R == w.regions.index(rid)) & (w.W == 0), iterations=6)
        if not mine.any():
            continue
        v = np.where(mine, rough, -1.0)
        i, j = np.unravel_index(int(np.argmax(v)), v.shape)
        x, z = w.x0 + (j + 0.5) * w.sp, w.z0 + (i + 0.5) * w.sp
        shot = frame(w, "rv_%s_rough" % short, [x, float(w.h(x, z)) + 1.0, z], 0.9, 60.0, EYE_M)
        if shot:
            out.append(shot)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--world", default=GEN)
    ap.add_argument("--out", default=os.path.join(REPO, "tools", "capture", "plans", "world_look.json"))
    ap.add_argument("--only", default="falls,rocks,roads,ledges,trees,fences,caves,slopes")
    ap.add_argument("--falls", default="")
    args = ap.parse_args()
    w = World(args.world)
    parts = args.only.split(",")
    shots = []
    if "falls" in parts:
        shots += falls(w, [s for s in args.falls.split(",") if s] or None)
    if "rocks" in parts:
        shots += rocks(w)
    if "roads" in parts:
        shots += roads(w)
    if "ledges" in parts:
        shots += ledges(w)
    if "trees" in parts:
        shots += trees(w)
    if "fences" in parts:
        shots += fences(w)
    if "caves" in parts:
        shots += caves(w)
    if "slopes" in parts:
        shots += slopes(w)
    if "review" in parts:
        shots += review(w)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"_doc": "Generated by tools/capture/make_world_look_plan.py from %s." % os.path.relpath(args.world, REPO),
                   "shots": shots}, f, indent=1)
    print("%d shots -> %s: %s" % (len(shots), args.out, ", ".join(s["label"] for s in shots)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
