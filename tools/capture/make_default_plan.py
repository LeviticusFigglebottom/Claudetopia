#!/usr/bin/env python3
"""Write tools/capture/plans/default.json: three shots per region plus a flythrough.

Shot positions are derived from the built heightmap so the camera always stands on real
ground and looks at something: each region gets its landmark, a vista from the highest point
within a few hundred metres of a viewpoint place, and the approach to its main settlement.

    tools/capture/make_default_plan.py [--out tools/capture/plans/default.json]
    tools/capture/make_default_plan.py --horizon     # the three-shot horizon diagnostic
    tools/capture/make_default_plan.py --look        # dusk, dawn, night, lamps, water, falls
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


## How far outside a crown's footprint a raised camera has to stand, and how far above its top.
CROWN_MARGIN_M = 2.0
## How far along its line of sight a camera may not have a crown in the way. Seventy metres: a
## tree in the middle ground is part of a wood's view, a tree in the foreground is the frame.
LINE_TREE_REACH_M = 70.0
## A landmark shot has to see the landmark, so its whole line is checked -- except the last
## stretch, where the landmark's own wood stands round its feet and hides only its base.
LANDMARK_TREE_SLACK_M = 60.0
## The bearings a landmark shot will try, in order, when the one it was written for is blocked.
LANDMARK_BEARING_STEPS = (0.0, 15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0, 90.0, -90.0)


class Scatter:
    """Where everything the world planted is standing, for keeping a camera out of it.

    A camera at eye height inside a region at thirty stems a hectare will sometimes be inside
    a tree, and a frame of leaves is not a photograph of a place. Loading the cells is cheap
    (the plan is generated once) and lets a shot step along its own bearing until it is in the
    open.

    Trees are kept apart from the rest and carry their crown as a cylinder: its reach (the
    horizontal half-extent of the forge's bounds, times the instance scale) and its top (the
    ground the instance stands on plus the asset's height, times the scale), both read from the
    asset's own meta file, so a hawthorn and a giant oak are not given the same size. A raised
    camera -- a vista at twelve metres, an approach at twenty-eight, a landmark at fifty-five --
    is clear of every trunk and can still be inside the crown of the giant oak fourteen metres
    off, which is exactly where the Briarwold vista stood; and the same camera fifty-five metres
    up is above that oak altogether. Height is what tells the two apart.
    """

    def __init__(self, cell_m: float = 256.0, world_m: float = 8192.0):
        self.cell_m = cell_m
        self.half = world_m / 2.0
        self.cells: dict = {}
        self._crowns: dict = {}

    def crown_of(self, asset: str) -> tuple:
        """(reach, height) of a tree asset at scale 1, from its meta file."""
        if asset in self._crowns:
            return self._crowns[asset]
        reach, height = 6.0, 12.0
        meta = os.path.join(REPO, "game", asset.replace("res://", "", 1))
        meta = os.path.splitext(meta)[0] + ".meta.json"
        if os.path.exists(meta):
            try:
                with open(meta, "r", encoding="utf-8") as f:
                    b = json.load(f).get("bounds", {})
                lo, hi = b.get("min", [0, 0, 0]), b.get("max", [0, 0, 0])
                reach = max(abs(float(lo[0])), abs(float(hi[0])), abs(float(lo[2])), abs(float(hi[2])), 1.0)
                height = max(float(hi[1]), 1.0)
            except (OSError, ValueError, KeyError, IndexError):
                pass
        self._crowns[asset] = (reach, height)
        return self._crowns[asset]

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
                reach, height = self.crown_of(asset) if is_tree else (0.0, 0.0)
                for r in rows:
                    pts.append((float(r[0]), float(r[2])))
                    if is_tree:
                        scale = float(r[4]) if len(r) > 4 else 1.0
                        ground = float(r[1])
                        trees.append((float(r[0]), float(r[2]), ground, reach * scale, ground + height * scale))
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

    def in_crown(self, x: float, y: float, z: float) -> bool:
        """Whether a lens at (x, y, z) is inside, or under, any tree's crown."""
        for _pts, trees in self._around(x, z):
            for px, pz, _ground, reach, top in trees:
                if y < top + CROWN_MARGIN_M and math.hypot(px - x, pz - z) < reach + CROWN_MARGIN_M:
                    return True
        return False

    def lens_clear(self, x: float, z: float, want: float, cam_y=None) -> bool:
        """Nothing standing within `want` metres; for a raised camera, no crown round the lens.

        A vantage in a wood is a spot between the trees, or above them: asking for nine clear
        metres past every crown finds nothing in the Briarwold at all, and the camera does not
        need it -- two metres outside the widest crown's footprint, or two metres over its top,
        is beside the tree or above it and not in it.
        """
        if self.nearest(x, z) < want:
            return False
        return cam_y is None or not self.in_crown(x, cam_y, z)

    def clear_spot(self, x: float, z: float, bearing_deg: float, want: float = 5.0,
                   step: float = 9.0, tries: int = 14, eye=None):
        """Step along the bearing until nothing is standing within `want` metres.

        `eye(x, z)`, when given, is the lens height at a spot; the crowns are then checked
        at that height as well, which is what a raised camera needs.
        """
        a = math.radians(bearing_deg)
        for k in range(tries):
            px, pz = x + math.cos(a) * step * k, z + math.sin(a) * step * k
            if abs(px) > self.half - 40.0 or abs(pz) > self.half - 40.0:
                break
            if self.lens_clear(px, pz, want, eye(px, pz) if eye else None):
                return px, pz
        return x, z

    def crowns_across(self, cam, target, from_m: float, to_m: float) -> int:
        """Crowns the line of sight passes through between `from_m` and `to_m` along it.

        A crown is a cylinder from a third of the tree's height to its top; the trunk under it
        is a metre and a bit wide. A line that passes over a tree, or between two, is clear.
        """
        (x0, y0, z0), (x1, y1, z1) = cam, target
        dx, dz = x1 - x0, z1 - z0
        length = math.hypot(dx, dz)
        if length < 1.0:
            return 0
        ux, uz = dx / length, dz / length
        to_m = min(to_m, length)
        hits = 0
        seen = set()
        t = from_m
        while t <= to_m + self.cell_m * 0.5:
            tt = min(t, to_m)
            cx = int((x0 + ux * tt + self.half) // self.cell_m)
            cz = int((z0 + uz * tt + self.half) // self.cell_m)
            for ddx in (-1, 0, 1):
                for ddz in (-1, 0, 1):
                    key = (cx + ddx, cz + ddz)
                    if key in seen:
                        continue
                    seen.add(key)
                    _pts, trees = self._cell(*key)
                    for px, pz, ground, reach, top in trees:
                        along = (px - x0) * ux + (pz - z0) * uz
                        if along < from_m or along > to_m:
                            continue
                        side = abs((px - x0) * uz - (pz - z0) * ux)
                        line_y = y0 + (y1 - y0) * along / length
                        if line_y >= top:
                            continue
                        crown_foot = ground + (top - ground) * 0.33
                        if (side < reach * 0.85 and line_y > crown_foot) or side < 1.2:
                            hits += 1
            t += self.cell_m * 0.5
        return hits


def line_clear(hh: "Heights", scatter: Scatter, cam, target, tree_from_m: float = 0.0,
               tree_to_m: float = LINE_TREE_REACH_M) -> bool:
    """Whether the ground stays under the line of sight and no crown stands in it.

    Sampled every eight metres. The ground may not rise to within a metre of the line beyond
    the first fifteen metres (the near ground is under a raised camera by construction), and
    no crown may cross the line between `tree_from_m` and `tree_to_m`: a trunk in the middle of
    the frame at fifty metres is a photograph of that tree, not of the country behind it.
    """
    (cx, cy, cz), (tx, ty, tz) = cam, target
    dist = math.hypot(tx - cx, tz - cz)
    n = max(int(dist / 8.0), 2)
    for i in range(1, n):
        t = i / n
        px, pz = cx + (tx - cx) * t, cz + (tz - cz) * t
        if t * dist >= 15.0 and hh.at(px, pz) > cy + (ty - cy) * t - 1.0:
            return False
    return scatter.crowns_across(cam, target, tree_from_m, tree_to_m) == 0


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


def landmark_camera(hh: Heights, scatter: Scatter, lx: float, lz: float, bearing: float,
                    label: str, dist: float = 360.0, rise: float = 55.0):
    """A camera `dist` off the landmark and `rise` up, on the first bearing it can see from.

    The written bearing is tried first; if the lens is in a crown or the line to the landmark
    goes through the land or through a wood before the landmark's own, the bearing swings
    fifteen degrees at a time either way. The Briarwold's landmark shot looked at the
    Grandfather through the crowns on the rise in front of it, and the frame was leaves.
    """
    lh = hh.at(lx, lz)
    target = (lx, lh + 8.0, lz)
    first = None
    for step in LANDMARK_BEARING_STEPS:
        ang = math.radians(bearing + step)
        cx, cz = lx + math.cos(ang) * dist, lz + math.sin(ang) * dist
        cy = max(hh.at(cx, cz), lh) + rise
        if first is None:
            first = (cx, cy, cz)
        if scatter.in_crown(cx, cy, cz):
            continue
        if not line_clear(hh, scatter, (cx, cy, cz), target, 0.0, dist - LANDMARK_TREE_SLACK_M):
            continue
        if step != 0.0:
            print("[plan] %s: written bearing is blocked; turned %+.0f degrees" % (label, step))
        return (cx, cy, cz), target
    print("[plan] %s: no clear bearing; the written one is kept" % label)
    return first, target


def vista_camera(hh: Heights, scatter: Scatter, vx: float, vz: float, tx: float, tz: float,
                 label: str, radius: float = 600.0, rise: float = 12.0):
    """A vantage on the high ground near a viewpoint, with a clear lens and a clear line.

    Returns (camera, look_at, found). The highest ground in a wood is under a tree as often as
    not, and this camera used to stand on it regardless: twelve metres up in a forest of
    thirty-metre oaks is inside the canopy, and one of the Briarwold's seven frames in the last
    sheet was a photograph of leaves that the drop test then scored. So the vantage is the
    highest of several candidates whose lens is clear -- no trunk or prop within nine metres
    and no crown round the camera -- and whose line to the target the land and the trees allow.
    If none passes, the highest is used with the camera raised out of the crowns, and the
    generator says so.
    """
    def aim(px: float, pz: float):
        # Look off the vantage at the lowest ground within a kilometre and a half, biased toward
        # the settlement so the shot is still about somewhere. Standing on a crest and facing the
        # back of your own hill is how six regions end up looking like one field.
        lx, lz, _lh = hh.low_point(px, pz, 1500.0)
        ax, az = lx * 0.4 + tx * 0.6, lz * 0.4 + tz * 0.6
        return px + (ax - px) * 0.92, pz + (az - pz) * 0.92

    for px, pz, py in hh.high_points(vx, vz, radius):
        cy = py + rise
        if not scatter.lens_clear(px, pz, 9.0, cy):
            continue
        mx, mz = aim(px, pz)
        # Look out, not down. Aiming at ground four hundred metres away from twelve metres up
        # puts the horizon in the top fifth of the frame and fills the other four fifths with
        # the grass at your feet; aiming a little under your own eye height puts it at about two
        # fifths, which is where a person standing on a hill actually sees it.
        if not line_clear(hh, scatter, (px, cy, pz), (mx, cy - 9.0, mz)):
            continue
        return (px, cy, pz), (mx, cy - 9.0, mz), True
    hx, hz, hy = hh.high_point(vx, vz, radius)
    mx, mz = aim(hx, hz)
    cy = hy + rise + 24.0
    print("[plan] %s: no clear vantage within %.0f m; camera raised above the trees" % (label, radius))
    return (hx, cy, hz), (mx, cy - 9.0, mz), False


def build_plan() -> dict:
    hh = Heights()
    places = load_places()
    scatter = Scatter()
    shots = []
    for region_id, (landmark, vista, settlement, hour, weather, bearing) in REGION_SHOTS.items():
        short = region_id.split("/")[-1]
        lm = places[landmark]
        lx, lz = float(lm["position"][0]), float(lm["position"][1])
        # 1. the landmark from 360 m off and 55 m up: far enough that the land around it reads
        cam, look = landmark_camera(hh, scatter, lx, lz, bearing, "%s_landmark" % short)
        shots.append(shot("%s_landmark" % short, cam, look, 58.0, hour, weather, 1.0, region_id))
        # 2. a vista from the highest ground near the region's viewpoint, over the settlement.
        # Eye height on the hill, not forty-eight metres above it: from a drone every region
        # is a hazy panorama with the same composition, and the thing that tells a marsh from a
        # downland is its own near ground filling the bottom of the frame and its own skyline
        # cutting the top. That is the shot a person standing there actually gets.
        vp = places[vista]
        vx, vz = float(vp["position"][0]), float(vp["position"][1])
        tx, tz = float(places[settlement]["position"][0]), float(places[settlement]["position"][1])
        cam, look, _found = vista_camera(hh, scatter, vx, vz, tx, tz, "%s_vista" % short)
        shots.append(shot("%s_vista" % short, cam, look, 62.0, hour, weather, 1.0, region_id))
        hx, hz = cam[0], cam[2]
        # 3. the approach to the settlement, 420 m out and 28 m up, looking down on it
        sx, sz = tx, tz
        a2 = math.atan2(hz - sz, hx - sx)
        ax, az = sx + math.cos(a2) * 420.0, sz + math.sin(a2) * 420.0
        ax, az = scatter.clear_spot(ax, az, math.degrees(a2) + 180.0, want=9.0,
                                    eye=lambda x, z: hh.at(x, z) + 28.0)
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


## The horizon diagnostic: three regions' vistas turned to face the far distance, which is
## where the world used to end in a straight line and where the fog and the sky meet.
HORIZON_REGIONS = ("core:region/hearthvale", "core:region/briarwold", "core:region/skerrow")


def build_horizon_plan() -> dict:
    """Three vistas that look at the far horizon, from the same clear vantages as the sheet.

    The hand-written plan this replaces had drifted off its own purpose as the world was
    rebuilt under it: its Hearthvale camera stood in the grass looking at the slope in front
    of it and its Briarwold camera was in the crowns. These stand where the default plan's
    vistas stand and look two kilometres out along the same bearing, a little under eye level.
    """
    hh = Heights()
    places = load_places()
    scatter = Scatter()
    shots = []
    for region_id in HORIZON_REGIONS:
        landmark, vista, settlement, hour, weather, _bearing = REGION_SHOTS[region_id]
        short = region_id.split("/")[-1]
        vp = places[vista]
        vx, vz = float(vp["position"][0]), float(vp["position"][1])
        tx, tz = float(places[settlement]["position"][0]), float(places[settlement]["position"][1])
        cam, look, _found = vista_camera(hh, scatter, vx, vz, tx, tz, "%s_vista (horizon)" % short)
        dx, dz = look[0] - cam[0], look[2] - cam[2]
        d = max(math.hypot(dx, dz), 1.0)
        far = (cam[0] + dx / d * 2000.0, cam[1] - 60.0, cam[2] + dz / d * 2000.0)
        shots.append(shot("%s_vista" % short, cam, far, 68.0, hour, weather, 1.0, region_id))
    return {
        "_doc": "Generated by tools/capture/make_default_plan.py --horizon. Diagnostic: three vistas that "
                "look at the far horizon, for checking that the world does not end in a straight line "
                "and that the fog meets the sky. Runs in about three minutes.",
        "shots": shots,
    }


## The look review: what the drop-test sheet never shows. The sheet is shot at one hour a region
## by design, so dusk, dawn, night, the lamps, the water and the falls need their own frames.
## Each row is (label, source plan, source shot, hour, weather[, frame]); the camera is the
## source's, and a `frame` has the capture runner re-aim it at a mesh the world raised there.
## A dusk or dawn hour is the one at which that region's own sun stands a degree or three off
## the horizon (its sun_elevation_scale and _bias are its latitude): Hearthvale's sun sets at
## 17:41, Brightwater's at 18:20 and Cinderlea's at 17:19. The sky follows the sun's height, so
## a "dusk" written as an hour of the clock -- 19:24 over the Mere -- is a night.
LOOK_SHOTS = (
    ("hearthvale_approach_dusk", "default", "hearthvale_approach", 17.55, "core:weather/clear"),
    ("hearthvale_street_night", "default", "hearthvale_street", 22.0, "core:weather/clear"),
    ("hearthvale_vista_moon", "default", "hearthvale_vista", 23.5, "core:weather/clear"),
    ("hearthvale_whitecut_falls", "pois", "waterfall_whitecut_falls", 9.0, "core:weather/clear",
     {"node": "Poi_whitecut_falls", "child_prefix": "Fall", "distance": 20.0, "height": 2.0}),
    ("brightwater_landmark_dusk", "default", "brightwater_landmark", 18.25, "core:weather/clear"),
    ("brightwater_mere_noon", "pois", "strange_tree_willow_isle", 12.0, "core:weather/clear"),
    ("brightwater_long_stride_night", "pois", "bridge_long_stride", 21.8, "core:weather/clear"),
    ("brightwater_street_night", "default", "brightwater_street", 21.5, "core:weather/clear"),
    ("sedgemire_landmark_dawn", "default", "sedgemire_landmark", 6.3, "core:weather/fog"),
    ("sedgemire_causeway_night", "pois", "bridge_lantern_causeway", 21.0, "core:weather/overcast"),
    ("briarwold_vista_late", "default", "briarwold_vista", 17.6, "core:weather/still"),
    ("briarwold_foxfire_falls", "pois", "waterfall_foxfire_falls", 11.0, "core:weather/still",
     {"node": "Poi_foxfire_falls", "child_prefix": "Fall", "distance": 20.0, "height": 2.0}),
    ("skerrow_vista_dawn", "default", "skerrow_vista", 6.2, "core:weather/clear_cold"),
    ("skerrow_three_sisters_falls", "pois", "waterfall_three_sisters_falls", 14.0, "core:weather/clear_cold",
     {"node": "Poi_three_sisters_falls", "child_prefix": "Fall", "distance": 26.0, "height": 3.0}),
    ("cinderlea_glass_falls", "pois", "waterfall_glass_falls", 16.5, "core:weather/dry_wind",
     {"node": "Poi_glass_falls", "child_prefix": "Glass", "distance": 20.0, "height": 2.0}),
    ("cinderlea_landmark_dusk", "default", "cinderlea_landmark", 17.1, "core:weather/thin_sun"),
    ("cinderlea_street_night", "default", "cinderlea_street", 20.8, "core:weather/still_grey"),
)


def build_look_plan() -> dict:
    """Dusk, dawn, night, lamps, water and falls, from cameras the other plans already trust."""
    plans = {}
    for name in ("default", "pois"):
        with open(os.path.join(REPO, "tools", "capture", "plans", name + ".json"), "r", encoding="utf-8") as f:
            plans[name] = {sh["label"]: sh for sh in json.load(f)["shots"]}
    shots = []
    for row in LOOK_SHOTS:
        label, plan, source, hour, weather = row[:5]
        src = plans[plan][source]
        region = src.get("region") or "core:region/" + label.split("_")[0]
        entry = shot(label, src["pos"], src["look_at"], float(src.get("fov", 60.0)), hour, weather,
                     1.0, region)
        if len(row) > 5:
            # re-aimed by the capture runner at what the world raised there: a waterfall's
            # sheet faces the terrain's own grain, which no plan written beforehand knows
            entry["frame"] = row[5]
        shots.append(entry)
    return {
        "_doc": "Generated by tools/capture/make_default_plan.py --look from default.json and pois.json. "
                "The painted-look review: dusk, dawn, night, lamps, water and falls. Not a drop-test "
                "sheet; its region copies are filed under regions/ like any other plan's.",
        "shots": shots,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    ap.add_argument("--horizon", action="store_true",
                    help="write the three-shot horizon diagnostic instead of the default sheet")
    ap.add_argument("--look", action="store_true",
                    help="write the dusk/dawn/night/water review plan (reads default.json and pois.json)")
    args = ap.parse_args()
    name = "horizon.json" if args.horizon else ("look.json" if args.look else "default.json")
    out = args.out or os.path.join(REPO, "tools", "capture", "plans", name)
    if args.horizon:
        plan = build_horizon_plan()
    elif args.look:
        plan = build_look_plan()
    else:
        plan = build_plan()
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(plan, f, indent=1)
    fly = plan.get("flythrough", {}).get("frames", 0)
    print("[plan] %d shots + %d flythrough frames -> %s" % (len(plan["shots"]), fly, out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
