#!/usr/bin/env python3
"""Write tools/capture/plans/default.json: three shots per region plus a flythrough.

Shot positions are derived from the built heightmap so the camera always stands on real
ground and looks at something: each region gets its landmark, a vista from the highest point
within a few hundred metres of a viewpoint place, and the approach to its main settlement.

    tools/capture/make_default_plan.py [--out tools/capture/plans/default.json]
"""
from __future__ import annotations

import argparse
import json
import math
import os
import zlib

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(REPO, "game", "world", "generated")
PACK = os.path.join(REPO, "game", "content", "packs", "core")

# region -> (landmark place, vista place, settlement place, hour, weather, approach bearing)
# The weather is forced so the sheet is repeatable and each region shows its own light rather
# than whatever the weather table rolled; the hours are the ones each region is written for.
REGION_SHOTS = {
    "core:region/hearthvale": ("core:place/cracked_toll", "core:place/chalk_hound", "core:place/merrowby",
                               9.0, "core:weather/clear", 200.0),
    "core:region/brightwater": ("core:place/sayers_spire", "core:place/the_lamp", "core:place/gullhithe",
                                12.0, "core:weather/clear", 150.0),
    "core:region/sedgemire": ("core:place/drowned_nave", "core:place/eelfathom", "core:place/isseva",
                              7.5, "core:weather/overcast", 60.0),
    "core:region/briarwold": ("core:place/grandfather", "core:place/standing_moot", "core:place/fernhold",
                              10.5, "core:weather/still", 250.0),
    "core:region/skerrow": ("core:place/fallen_hand", "core:place/windgate", "core:place/kharrow_hold",
                            14.0, "core:weather/clear_cold", 110.0),
    "core:region/cinderlea": ("core:place/sunken_choir", "core:place/greyfold", "core:place/pilgrims_ash",
                              16.5, "core:weather/dry_wind", 20.0),
}


class Heights:
    def __init__(self):
        with open(os.path.join(GEN, "world_manifest.json"), "r", encoding="utf-8") as f:
            self.man = json.load(f)
        self.n = int(self.man["grid"])
        self.spacing = float(self.man["spacing_m"])
        self.origin = self.man["origin"]
        self.h = np.fromfile(os.path.join(GEN, "heights.r32"), dtype="<f4").reshape(self.n, self.n)
        self.mask = np.fromfile(os.path.join(GEN, "region_mask.u8"),
                                dtype=np.uint8).reshape(self.n, self.n)
        self.water = np.fromfile(os.path.join(GEN, "water_mask.u8"),
                                 dtype=np.uint8).reshape(self.n, self.n)
        self.region_index = {rid: i for i, rid in enumerate(self.man.get("regions", []))}

    def xz_of(self, i: int, j: int):
        return (self.origin[0] + j * self.spacing, self.origin[1] + i * self.spacing)

    def sample_region(self, region: int, count: int, seed: int, want_water=None):
        """`count` places drawn from a region's own ground, spread out rather than clustered.

        The drop test turns on having several shots of a region that are not three views of
        the same hill, so these are drawn from the whole of it and thinned by distance.
        """
        if region < 0:
            return []
        sel = self.mask == region
        if want_water is not None:
            sel = sel & ((self.water > 0) if want_water else (self.water == 0))
        rows, cols = np.nonzero(sel)
        if rows.size == 0:
            return []
        rng = np.random.default_rng(seed)
        pick = rng.choice(rows.size, size=min(700, rows.size), replace=False)
        out = []
        for k in pick:
            x, z = self.xz_of(int(rows[k]), int(cols[k]))
            if any(math.hypot(x - ox, z - oz) < 1100.0 for ox, oz in out):
                continue
            out.append((x, z))
            if len(out) >= count:
                break
        return out

    def at(self, x: float, z: float) -> float:
        j = int(round((x - self.origin[0]) / self.spacing))
        i = int(round((z - self.origin[1]) / self.spacing))
        j = min(max(j, 0), self.n - 1)
        i = min(max(i, 0), self.n - 1)
        return float(self.h[i, j])

    def high_point(self, x: float, z: float, radius: float, samples: int = 96):
        """The highest ground within `radius`, for putting a camera on a vantage."""
        rng = np.random.default_rng(7)
        best = (x, z, self.at(x, z))
        for _ in range(samples):
            a = rng.uniform(0, 2 * math.pi)
            r = radius * math.sqrt(rng.uniform(0.05, 1.0))
            px, pz = x + math.cos(a) * r, z + math.sin(a) * r
            h = self.at(px, pz)
            if h > best[2]:
                best = (px, pz, h)
        return best

    def high_points(self, x: float, z: float, radius: float, count: int = 12,
                    samples: int = 220, apart_m: float = 30.0):
        """The `count` highest distinct spots within `radius`, highest first.

        `high_point` returns one, and one is not enough: the highest ground in a wood is
        under a tree as often as not, so a vantage is chosen from several, taking the first
        whose lens is clear and whose line to the target the land and the trees allow.
        """
        rng = np.random.default_rng(7)
        cands = [(x, z, self.at(x, z))]
        for _ in range(samples):
            a = rng.uniform(0, 2 * math.pi)
            r = radius * math.sqrt(rng.uniform(0.05, 1.0))
            px, pz = x + math.cos(a) * r, z + math.sin(a) * r
            cands.append((px, pz, self.at(px, pz)))
        cands.sort(key=lambda c: -c[2])
        out = []
        for c in cands:
            if any(math.hypot(c[0] - o[0], c[1] - o[1]) < apart_m for o in out):
                continue
            out.append(c)
            if len(out) >= count:
                break
        return out

    def low_point(self, x: float, z: float, radius: float, samples: int = 140):
        """The lowest ground within `radius`, for pointing a camera off a vantage.

        A view from high ground is only a view if it looks at the drop. Aiming at the lowest
        ground in range is what puts an escarpment face, a valley floor or a shoreline in the
        frame instead of the back of the hill the camera is standing on.
        """
        rng = np.random.default_rng(11)
        best = (x, z, self.at(x, z))
        for _ in range(samples):
            a = rng.uniform(0, 2 * math.pi)
            r = radius * math.sqrt(rng.uniform(0.25, 1.0))
            px, pz = x + math.cos(a) * r, z + math.sin(a) * r
            h = self.at(px, pz)
            if h < best[2]:
                best = (px, pz, h)
        return best


## How far outside the nearest crown's footprint a raised camera has to stand.
CROWN_MARGIN_M = 2.0
## How far along its line of sight a camera may not have a crown crossing the centre. Seventy
## metres: a tree in the middle ground is part of a wood's view, a tree in the foreground is
## the whole frame.
LINE_TREE_REACH_M = 70.0


class Scatter:
    """Where everything the world planted is standing, for keeping a camera out of it.

    A camera at eye height inside a region at thirty stems a hectare will sometimes be inside
    a tree, and a frame of leaves is not a photograph of a place. Loading the cells is cheap
    (the plan is generated once) and lets a shot step along its own bearing until it is in the
    open.

    Trees are kept apart from the rest and carry their canopy: a raised camera -- a vista at
    twelve metres, an approach at twenty-eight -- is clear of a trunk and still inside the
    crown of the giant oak fourteen metres off, which is exactly where the Briarwold vista
    stood. The canopy radius is read from the forge's own meta file (the horizontal half-extent
    of the asset's bounds, times the instance scale), so a hawthorn and a giant oak are not
    given the same reach.
    """

    def __init__(self, cell_m: float = 256.0, world_m: float = 8192.0):
        self.cell_m = cell_m
        self.half = world_m / 2.0
        self.cells: dict = {}
        self._reach: dict = {}

    def canopy_radius(self, asset: str) -> float:
        """Horizontal half-extent of a tree asset at scale 1, from its meta file."""
        if asset in self._reach:
            return self._reach[asset]
        r = 6.0
        meta = os.path.join(REPO, "game", asset.replace("res://", "", 1))
        meta = os.path.splitext(meta)[0] + ".meta.json"
        if os.path.exists(meta):
            try:
                with open(meta, "r", encoding="utf-8") as f:
                    b = json.load(f).get("bounds", {})
                lo, hi = b.get("min", [0, 0, 0]), b.get("max", [0, 0, 0])
                r = max(abs(float(lo[0])), abs(float(hi[0])), abs(float(lo[2])), abs(float(hi[2])), 1.0)
            except (OSError, ValueError, KeyError, IndexError):
                pass
        self._reach[asset] = r
        return r

    def _cell(self, cx: int, cz: int) -> tuple:
        key = (cx, cz)
        if key in self.cells:
            return self.cells[key]
        path = os.path.join(GEN, "cells", "%d_%d.json" % (cx, cz))
        pts: list = []
        trees: list = []
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            for asset, rows in data.get("instances", {}).items():
                # only the things big enough to stand in front of a lens
                if "/flora/" in asset and "reed" not in asset:
                    continue
                is_tree = "/trees/" in asset
                reach = self.canopy_radius(asset) if is_tree else 0.0
                for r in rows:
                    pts.append((float(r[0]), float(r[2])))
                    if is_tree:
                        scale = float(r[4]) if len(r) > 4 else 1.0
                        trees.append((float(r[0]), float(r[2]), reach * scale))
        self.cells[key] = (pts, trees)
        return self.cells[key]

    def _around(self, x: float, z: float, rings: int = 1):
        cx = int((x + self.half) // self.cell_m)
        cz = int((z + self.half) // self.cell_m)
        for dx in range(-rings, rings + 1):
            for dz in range(-rings, rings + 1):
                yield self._cell(cx + dx, cz + dz)

    def nearest(self, x: float, z: float) -> float:
        """Distance to the nearest stem, trunk or prop (not its crown)."""
        best = 1e9
        for pts, _trees in self._around(x, z):
            for px, pz in pts:
                d = math.hypot(px - x, pz - z)
                if d < best:
                    best = d
        return best

    def canopy_clearance(self, x: float, z: float) -> float:
        """Metres from the point to the edge of the nearest tree's crown; negative inside one."""
        best = 1e9
        for _pts, trees in self._around(x, z):
            for px, pz, reach in trees:
                d = math.hypot(px - x, pz - z) - reach
                if d < best:
                    best = d
        return best

    def lens_clear(self, x: float, z: float, want: float, raised: bool) -> bool:
        """Nothing within `want` metres of the lens; for a raised camera, no crown over it.

        The crown margin is two metres, not `want`: a vantage in a wood is a spot between the
        trees, and asking for nine clear metres past every crown's edge finds nothing in the
        Briarwold at all. Standing two metres outside the widest crown's footprint, twelve
        metres up, is beside the tree and not in it.
        """
        if self.nearest(x, z) < want:
            return False
        return (not raised) or self.canopy_clearance(x, z) >= CROWN_MARGIN_M

    def clear_spot(self, x: float, z: float, bearing_deg: float, want: float = 5.0,
                   step: float = 9.0, tries: int = 14, raised: bool = False):
        """Step along the bearing until nothing is standing within `want` metres."""
        a = math.radians(bearing_deg)
        for k in range(tries):
            px, pz = x + math.cos(a) * step * k, z + math.sin(a) * step * k
            if abs(px) > self.half - 40.0 or abs(pz) > self.half - 40.0:
                break
            if self.lens_clear(px, pz, want, raised):
                return px, pz
        return x, z

    def trees_across(self, x0: float, z0: float, x1: float, z1: float, within_m: float) -> int:
        """Trees whose crown crosses the first `within_m` metres of the line from (x0, z0)."""
        dx, dz = x1 - x0, z1 - z0
        length = math.hypot(dx, dz)
        if length < 1.0:
            return 0
        ux, uz = dx / length, dz / length
        reach = min(within_m, length)
        hits = 0
        # the cells the line passes through, sampled every cell length along it
        seen = set()
        steps = int(reach // (self.cell_m * 0.5)) + 2
        for i in range(steps + 1):
            t = min(reach, i * self.cell_m * 0.5)
            cx = int((x0 + ux * t + self.half) // self.cell_m)
            cz = int((z0 + uz * t + self.half) // self.cell_m)
            for ddx in (-1, 0, 1):
                for ddz in (-1, 0, 1):
                    key = (cx + ddx, cz + ddz)
                    if key in seen:
                        continue
                    seen.add(key)
                    _pts, trees = self._cell(*key)
                    for px, pz, r in trees:
                        along = (px - x0) * ux + (pz - z0) * uz
                        if along < 0.0 or along > reach:
                            continue
                        side = abs((px - x0) * uz - (pz - z0) * ux)
                        if side < r:
                            hits += 1
        return hits


def line_clear(hh: "Heights", scatter: Scatter, cam, target, tree_reach_m: float = LINE_TREE_REACH_M) -> bool:
    """Whether the ground stays under the line of sight and no crown crosses its near end.

    Sampled every eight metres. The ground may not rise to within a metre of the line beyond
    the first fifteen metres (the near ground is under a raised camera by construction), and
    no tree's crown may cross the line within `tree_reach_m`: a trunk in the middle of the
    frame at fifty metres is a photograph of that tree, not of the country behind it.
    """
    (cx, cy, cz), (tx, ty, tz) = cam, target
    dist = math.hypot(tx - cx, tz - cz)
    n = max(int(dist / 8.0), 2)
    for i in range(1, n):
        t = i / n
        px, pz = cx + (tx - cx) * t, cz + (tz - cz) * t
        if t * dist >= 15.0 and hh.at(px, pz) > cy + (ty - cy) * t - 1.0:
            return False
    return scatter.trees_across(cx, cz, tx, tz, tree_reach_m) == 0


def load_places() -> dict:
    with open(os.path.join(PACK, "places", "places.json"), "r", encoding="utf-8") as f:
        return {p["id"]: p for p in json.load(f)}


def shot(label: str, pos, look, fov: float, hour: float, weather: str, fog_scale: float = 1.0,
         region: str = "") -> dict:
    return {
        "label": label,
        # the region the shot is *about*: a vista is often taken from the high ground of a
        # neighbour, and the drop test should file the picture under its subject
        "region": region,
        "pos": [round(pos[0], 1), round(pos[1], 1), round(pos[2], 1)],
        "look_at": [round(look[0], 1), round(look[1], 1), round(look[2], 1)],
        "fov": fov,
        "time": hour,
        "weather": weather,
        # The region fog densities are now written for a country you can see across, so the
        # sheet is shot at the light each region actually has. This override is kept for a
        # plan that wants to look further than the weather allows.
        "fog_scale": fog_scale,
    }


def build_plan() -> dict:
    hh = Heights()
    places = load_places()
    scatter = Scatter()
    shots = []
    for region_id, (landmark, vista, settlement, hour, weather, bearing) in REGION_SHOTS.items():
        short = region_id.split("/")[-1]
        lm = places[landmark]
        lx, lz = float(lm["position"][0]), float(lm["position"][1])
        lh = hh.at(lx, lz)
        # 1. the landmark from 360 m off and 55 m up: far enough that the land around it reads
        ang = math.radians(bearing)
        dist = 360.0
        cx, cz = lx + math.cos(ang) * dist, lz + math.sin(ang) * dist
        cam_h = max(hh.at(cx, cz), lh) + 55.0
        shots.append(shot("%s_landmark" % short, (cx, cam_h, cz), (lx, lh + 8.0, lz), 58.0, hour, weather, 1.0, region_id))
        # 2. a vista from the highest ground near the region's viewpoint, over the settlement.
        # Eye height on the hill, not forty-eight metres above it: from a drone every region
        # is a hazy panorama with the same composition, and the thing that tells a marsh from a
        # downland is its own near ground filling the bottom of the frame and its own skyline
        # cutting the top. That is the shot a person standing there actually gets.
        vp = places[vista]
        vx, vz = float(vp["position"][0]), float(vp["position"][1])
        tx, tz = float(places[settlement]["position"][0]), float(places[settlement]["position"][1])
        # The highest ground in a wood is under a tree as often as not, and this camera used
        # to stand on it regardless: twelve metres up in a forest of thirty-metre oaks is
        # inside the canopy, and one of the Briarwold's seven frames in the last sheet was a
        # photograph of leaves that the drop test then scored. So the vantage is the highest
        # of several candidates whose lens is clear -- no trunk or prop within nine metres and
        # no crown over the camera -- and whose line to the target the land and the trees
        # allow. If no spot within reach passes, the highest one is used and the camera is
        # raised out of the crowns, and the generator says so.
        hx, hz, hy = hh.high_point(vx, vz, 600.0)
        cam_y = hy + 12.0
        mx, mz = tx, tz
        found = False
        for px, pz, py in hh.high_points(vx, vz, 600.0):
            cy = py + 12.0
            if not scatter.lens_clear(px, pz, 9.0, True):
                continue
            # Look off the vantage at the lowest ground within a kilometre and a half, biased
            # toward the settlement so the shot is still about somewhere. Standing on a crest
            # and facing the back of your own hill is how six regions end up looking like one
            # field.
            lx, lz, lh = hh.low_point(px, pz, 1500.0)
            ax, az = lx * 0.4 + tx * 0.6, lz * 0.4 + tz * 0.6
            cmx, cmz = px + (ax - px) * 0.92, pz + (az - pz) * 0.92
            # Look out, not down. Aiming at ground four hundred metres away from twelve metres
            # up puts the horizon in the top fifth of the frame and fills the other four fifths
            # with the grass at your feet; aiming a little under your own eye height puts it at
            # about two fifths, which is where a person standing on a hill actually sees it.
            if not line_clear(hh, scatter, (px, cy, pz), (cmx, cy - 9.0, cmz)):
                continue
            hx, hz, hy, cam_y, mx, mz, found = px, pz, py, cy, cmx, cmz, True
            break
        if not found:
            lx, lz, lh = hh.low_point(hx, hz, 1500.0)
            ax, az = lx * 0.4 + tx * 0.6, lz * 0.4 + tz * 0.6
            mx, mz = hx + (ax - hx) * 0.92, hz + (az - hz) * 0.92
            cam_y = hy + 12.0 + 24.0
            print("[plan] %s_vista: no clear vantage within 600 m of %s; camera raised above the trees"
                  % (short, vista))
        shots.append(shot("%s_vista" % short, (hx, cam_y, hz), (mx, cam_y - 9.0, mz),
                          62.0, hour, weather, 1.0, region_id))
        # 3. the approach to the settlement, 420 m out and 28 m up, looking down on it
        sx, sz = tx, tz
        a2 = math.atan2(hz - sz, hx - sx)
        ax, az = sx + math.cos(a2) * 420.0, sz + math.sin(a2) * 420.0
        ax, az = scatter.clear_spot(ax, az, math.degrees(a2) + 180.0, want=9.0, raised=True)
        shots.append(shot("%s_approach" % short, (ax, hh.at(ax, az) + 28.0, az),
                          (sx, hh.at(sx, sz) + 4.0, sz), 55.0, hour, weather, 1.0, region_id))
    # One shot standing in the middle of each region's settlement, which is the only frame in
    # the sheet close enough for the villagers to be in it (they are kept up within 240 m) and
    # the only one that shows what a town actually looks like from the street.
    for region_id, (landmark, vista, settlement, hour, weather, bearing) in REGION_SHOTS.items():
        short = region_id.split("/")[-1]
        sp = places[settlement]
        sx, sz = float(sp["position"][0]), float(sp["position"][1])
        ang = math.radians(bearing + 35.0)
        ex, ez = sx - math.cos(ang) * 46.0, sz - math.sin(ang) * 46.0
        shots.append(shot("%s_street" % short, (ex, hh.at(ex, ez) + 1.7, ez),
                          (sx, hh.at(sx, sz) + 2.5, sz), 58.0, hour, weather, 1.0, region_id))

    # Three more per region, taken from the region's own ground rather than from its places,
    # so the drop test has six images of six different parts of a region instead of three
    # views of one hill. Below six a region, the landform axis is noise (DESIGN 10.1).
    for region_id, (landmark, vista, settlement, hour, weather, bearing) in REGION_SHOTS.items():
        short = region_id.split("/")[-1]
        idx = hh.region_index.get(region_id, -1)
        # crc32 rather than hash(): a salted hash would draw different ground shots on
        # every run and the sheet would not be comparable with the last one
        spots = hh.sample_region(idx, 3, seed=zlib.crc32(short.encode("utf-8")))
        for n, (sx, sz) in enumerate(spots):
            # stand on the ground and look out along it, each one on its own bearing
            ang = math.radians(bearing + 90.0 + n * 117.0)
            sx, sz = scatter.clear_spot(sx, sz, bearing + 90.0 + n * 117.0 + 180.0, want=5.5)
            tx, tz = sx + math.cos(ang) * 520.0, sz + math.sin(ang) * 520.0
            eye = hh.at(sx, sz) + 2.2
            shots.append(shot("%s_ground%d" % (short, n + 1), (sx, eye, sz),
                              (tx, hh.at(tx, tz) + 2.0, tz), 60.0, hour, weather, 1.0, region_id))

    # a flythrough that crosses every region, high enough to read the landforms
    waypoints = []
    for region_id in REGION_SHOTS:
        p = places[REGION_SHOTS[region_id][2]]
        x, z = float(p["position"][0]), float(p["position"][1])
        waypoints.append([round(x, 1), round(hh.at(x, z) + 140.0, 1), round(z, 1)])
    waypoints.append(waypoints[0])
    return {
        "_doc": "Generated by tools/capture/make_default_plan.py; edit freely, it is committed.",
        "shots": shots,
        "flythrough": {"path": waypoints, "frames": 12, "look_ahead": True, "time": 9.5,
                       "weather": "core:weather/clear", "fog_scale": 1.0},
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(REPO, "tools", "capture", "plans", "default.json"))
    args = ap.parse_args()
    plan = build_plan()
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(plan, f, indent=1)
    print("[plan] %d shots + %d flythrough frames -> %s"
          % (len(plan["shots"]), plan["flythrough"]["frames"], args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
