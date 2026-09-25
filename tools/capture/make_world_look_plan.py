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
    tools/capture/make_world_look_plan.py --only falls,rocks              # falls rocks roads ledges
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
        return bool(np.all(self.h(x, z) < y - SIGHT_SPARE_M))


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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--world", default=GEN)
    ap.add_argument("--out", default=os.path.join(REPO, "tools", "capture", "plans", "world_look.json"))
    ap.add_argument("--only", default="falls,rocks,roads,ledges")
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
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"_doc": "Generated by tools/capture/make_world_look_plan.py from %s." % os.path.relpath(args.world, REPO),
                   "shots": shots}, f, indent=1)
    print("%d shots -> %s: %s" % (len(shots), args.out, ", ".join(s["label"] for s in shots)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
