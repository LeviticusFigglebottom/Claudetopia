#!/usr/bin/env python3
"""Write a capture plan that photographs the points of interest.

One shot per POI: the camera stands 30-50 m off at eye height on the side the road comes in
from (or downhill of the pad when no road does), looks at the POI's centre, and takes the
hour that shows the kind — dusk for anything with a fire or a lantern, the region's own hour
for the rest. Positions come from the built `pois.json`, so a moved POI moves its shot.

    tools/capture/make_pois_plan.py                       # every POI -> tools/capture/plans/pois.json
    tools/capture/make_pois_plan.py --kinds camp,shrine   # only these kinds
    tools/capture/make_pois_plan.py --only gosling,ansel  # only ids containing these
    tools/capture/make_pois_plan.py --out /tmp/plan.json
    tools/capture/make_pois_plan.py --world <build dir> --only horn_hole   # a build, not the tracked world

Every camera is checked against the land it looks over, as the world builder's look plan checks
its own (make_world_look_plan.py): it stands on dry land, out of every tree's crown, clear of
every trunk's bark by that trunk's own thickness and with trunks filling little of its frame, and the ground and the crowns between it and the POI stay
under its line of sight. Where the first spot fails it is raised, swung round and brought nearer
until one holds. The Oskel Drip's camera, on the approach side at eye height, stood inside the
dale side it was meant to look along, and the Rafters' Locker's in an alder's crown; the Moss
Bed's, eight metres from a giant oak whose trunk is nearly five metres round, saw bark.
"""
from __future__ import annotations

import argparse
import json
import math
import os

import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_default_plan as DP  # noqa: E402  (the scatter's crowns and trunks)
import frame_check as FC  # noqa: E402  (what the frame will hold)

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(REPO, "game", "world", "generated")
PACK = os.path.join(REPO, "game", "content", "packs", "core")

# the hour and weather each region is written for (tools/capture/make_default_plan.py)
REGION_HOUR = {
    "core:region/hearthvale": (9.0, "core:weather/clear"),
    "core:region/brightwater": (12.0, "core:weather/clear"),
    "core:region/sedgemire": (7.5, "core:weather/overcast"),
    "core:region/briarwold": (10.5, "core:weather/still"),
    "core:region/skerrow": (14.0, "core:weather/clear_cold"),
    "core:region/cinderlea": (16.5, "core:weather/dry_wind"),
}
# Kinds that carry a fire or a lantern are shot in the last of the light, when a lamp shows
# and the ground still does (by 19:00 the country is black).
# 18:00 still put the whole foreground in shadow; 17:10 is the last hour where a fire reads
# against the sky *and* the ground the camp stands on is still lit.
DUSK_KINDS = {"camp": 17.2, "shrine": 17.2, "hearth": 17.2, "wreck": 17.0}
DUSK_HOUR = 17.2
# ...and so is any POI of any kind whose own feature text is about a light. The Lantern
# Causeway is lit each dusk by a lamplighter who sings as she goes, and photographing it at
# half past seven in the morning shows poles.
LIT_WORDS = ("lantern", "lamp", "lit ", "light", "fire", "beacon", "foxfire", "wisp", "glow",
             "candle", "note-light")
# how far off the camera stands, by how big the thing is
DISTANCE = {"giant_bones": 48.0, "tower": 44.0, "bridge": 32.0, "waterfall": 42.0, "strange_tree": 44.0,
            "hidden_valley": 38.0, "wreck": 36.0, "ruins": 38.0, "standing_stones": 34.0, "camp": 34.0,
            "shrine": 30.0, "strange": 30.0, "hearth": 26.0}
EYE = 1.65


## how far under the line of sight the ground between must stay (a blade of grass)
SIGHT_SPARE_M = 0.4
## the POI's own dressing stands within this of its centre; the line of sight may end in it
OWN_M = 10.0
## a camera on the ground stands at least this far from anything standing (a trunk, a rock)
TRUNK_CLEAR_M = 4.0
## ...and this far from any tree's bark, however thick the trunk
BARK_CLEAR_M = 3.0
## the passes a camera is sought in: framed as strictly as the region shots are; then only clear
## of bark with trunks filling little of the frame's width; then, in a wood where there is always
## a trunk somewhere in front, with more of it filled
PASSES = ((True, 0.12), (False, 0.12), (False, 0.3))
## the frame check's limits are tightened by this for a camera chosen here, which is checked
## again on the tracked world's coarser heights
FRAME_SPARE = 0.1
## POI camera distances tried, as fractions of the kind's distance, after the usual ones (1, 0.8,
## 0.6, 1.25) give no clear frame: the Flood Stone's under the Greatwood's oaks
FARTHER_NEARER_K = (1.5, 0.45)


class Ground:
    """A built world's heights (bilinear, as the game samples them) and water: its full-size
    heights where the build kept them, else the runtime maps the tracked world carries."""

    def __init__(self, world: str = "", runtime: bool = False) -> None:
        world = world or GEN
        with open(os.path.join(world, "world_manifest.json"), "r", encoding="utf-8") as f:
            man = json.load(f)
        self.origin = man["origin"]
        full = os.path.join(world, "heights.r32")
        if not runtime and os.path.exists(full) and os.path.exists(os.path.join(world, "water_mask.u8")):
            self.n = int(man["grid"])
            self.spacing = float(man["spacing_m"])
            self.h = np.fromfile(full, dtype="<f4").reshape(self.n, self.n)
            self.water = np.fromfile(os.path.join(world, "water_mask.u8"), dtype=np.uint8).reshape(self.n, self.n)
            self.off = 0.0
        else:
            rt = man["runtime"]
            self.n = int(rt["grid"])
            self.spacing = float(man["size_m"]) / self.n
            self.h = np.fromfile(os.path.join(world, rt["heights"]), dtype="<f4").reshape(self.n, self.n)
            self.water = np.fromfile(os.path.join(world, rt["water"]), dtype=np.uint8).reshape(self.n, self.n)
            self.off = float(rt.get("height_offset_m", 0.5 * (self.spacing - float(man["spacing_m"]))))

    def _ij(self, x: float, z: float) -> tuple:
        j = int(np.clip((x - self.origin[0]) / self.spacing, 0, self.n - 1))
        i = int(np.clip((z - self.origin[1]) / self.spacing, 0, self.n - 1))
        return i, j

    def height(self, x: float, z: float) -> float:
        fj = min(max((x - self.origin[0] - self.off) / self.spacing, 0.0), self.n - 1.001)
        fi = min(max((z - self.origin[1] - self.off) / self.spacing, 0.0), self.n - 1.001)
        j, i = int(fj), int(fi)
        tj, ti = fj - j, fi - i
        H = self.h
        return float((H[i, j] * (1 - tj) + H[i, j + 1] * tj) * (1 - ti) + (H[i + 1, j] * (1 - tj) + H[i + 1, j + 1] * tj) * ti)

    def is_water(self, x: float, z: float) -> bool:
        i, j = self._ij(x, z)
        return bool(self.water[i, j] > 0)

    def clear(self, cam, look, own: float = OWN_M) -> bool:
        """The ground between the camera and `look` stays under the line of sight, up to the
        POI's own ground."""
        d = math.hypot(look[0] - cam[0], look[2] - cam[2])
        if d <= own:
            return True
        n = max(int(d / 2.0), 4)
        for k in range(1, n):
            t = k / n
            if t * d > d - own:
                break
            x, z = cam[0] + (look[0] - cam[0]) * t, cam[2] + (look[2] - cam[2]) * t
            if self.height(x, z) > cam[1] + (look[1] - cam[1]) * t - SIGHT_SPARE_M:
                return False
        return True


def load_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def approach_bearing(pos, roads, ground: Ground) -> float:
    """Bearing (radians, atan2(dx, dz)) from the POI toward where you come from."""
    px, pz = pos[0], pos[2]
    best = (1e9, None)
    for road in roads:
        for qx, qz in road["points"]:
            d = math.hypot(qx - px, qz - pz)
            if d < best[0]:
                best = (d, (qx, qz))
    if best[1] is not None and best[0] < 160.0 and best[0] > 8.0:
        return math.atan2(best[1][0] - px, best[1][1] - pz)
    # no road near: stand downhill, which is the way most things are approached
    h0 = ground.height(px, pz)
    drop, bearing = 0.0, 0.0
    for a in range(0, 360, 15):
        r = math.radians(a)
        d = h0 - ground.height(px + math.sin(r) * 30.0, pz + math.cos(r) * 30.0)
        if d > drop:
            drop, bearing = d, r
    return bearing if drop > 0.5 else math.radians(200.0)


class Trunks:
    """Every tree's trunk as a disc: where it stands and how thick it is (the forge's collision
    radius for the asset, times the instance's scale). A giant oak at twice its size is a trunk
    nearly five metres round, with its roots wider still, and a camera four metres from its
    centre is looking at bark; the crown model alone does not say so."""

    def __init__(self, scatter) -> None:
        self.scatter = scatter
        self._radius: dict = {}
        self.cells: dict = {}

    def radius_of(self, asset: str) -> float:
        if asset not in self._radius:
            r = 0.5
            meta = os.path.join(REPO, "game", asset.replace("res://", "", 1))
            meta = os.path.splitext(meta)[0] + ".meta.json"
            try:
                with open(meta, "r", encoding="utf-8") as f:
                    r = float(json.load(f).get("collision_params", {}).get("radius", r))
            except (OSError, ValueError, TypeError):
                pass
            self._radius[asset] = r
        return self._radius[asset]

    def _cell(self, cx: int, cz: int) -> list:
        key = (cx, cz)
        if key not in self.cells:
            out = []
            path = os.path.join(DP.GEN, "cells", "%d_%d.json" % (cx, cz))
            if os.path.exists(path):
                with open(path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                for asset, rows in data.get("instances", {}).items():
                    if "/trees/" not in asset:
                        continue
                    r0 = self.radius_of(asset)
                    for r in rows:
                        scale = float(r[4]) if len(r) > 4 else 1.0
                        out.append((float(r[0]), float(r[2]), r0 * scale))
            self.cells[key] = out
        return self.cells[key]

    def around(self, x: float, z: float, rings: int = 1):
        sc = self.scatter
        cx, cz = int((x + sc.half) // sc.cell_m), int((z + sc.half) // sc.cell_m)
        for dx in range(-rings, rings + 1):
            for dz in range(-rings, rings + 1):
                yield from self._cell(cx + dx, cz + dz)

    def clearance(self, x: float, z: float) -> float:
        """Metres from (x, z) to the nearest bark."""
        return min((math.hypot(px - x, pz - z) - r for px, pz, r in self.around(x, z)), default=1e9)

    def across(self, cam, look, to_m: float, spare: float = 0.5) -> bool:
        """Whether a trunk stands on the line of sight within `to_m` of the camera."""
        x0, z0 = cam[0], cam[2]
        dx, dz = look[0] - x0, look[2] - z0
        length = math.hypot(dx, dz)
        if length < 1.0:
            return False
        ux, uz = dx / length, dz / length
        seen = set()
        for k in range(0, int(to_m // 64.0) + 1):
            for t in self.around(x0 + ux * k * 64.0, z0 + uz * k * 64.0):
                if t in seen:
                    continue
                seen.add(t)
                px, pz, r = t
                along = (px - x0) * ux + (pz - z0) * uz
                if 0.0 < along < to_m + r and abs((px - x0) * uz - (pz - z0) * ux) < r + spare:
                    return True
        return False

    def in_frame(self, cam, look, fov_deg: float = 58.0, aspect: float = 16.0 / 9.0) -> float:
        """How much of the frame's width the trunks nearer than the POI fill (0 to 1, overlaps
        counted once)."""
        half = math.atan(math.tan(math.radians(fov_deg) * 0.5) * aspect)
        x0, z0 = cam[0], cam[2]
        ahead = math.atan2(look[2] - z0, look[0] - x0)
        far = math.hypot(look[0] - x0, look[2] - z0)
        spans = []
        for px, pz, r in self.around(x0, z0):
            d = math.hypot(px - x0, pz - z0)
            if d >= far or d <= 0.1:
                continue
            w = math.asin(min(1.0, r / d))
            off = (math.atan2(pz - z0, px - x0) - ahead + math.pi) % (2.0 * math.pi) - math.pi
            lo, hi = max(off - w, -half), min(off + w, half)
            if hi > lo:
                spans.append((lo, hi))
        spans.sort()
        covered, end = 0.0, -half
        for lo, hi in spans:
            if hi > end:
                covered += hi - max(lo, end)
                end = hi
        return covered / (2.0 * half)


def camera_for(pos, kind: str, bearing: float, ground: Ground, scatter) -> list:
    """Where to stand: the approach side and the flattest ground first, then raised, swung and
    brought nearer until the camera is on dry land, out of the trees and sees the POI."""
    dist = DISTANCE.get(kind, 34.0)
    FARTHER_NEARER = tuple(dist * k for k in FARTHER_NEARER_K)
    look = (pos[0], pos[1] + 1.5, pos[2])
    tried = []
    # a POI out on the water (the buoy bells) is shot from a boat's height over the water
    afloat = ground.is_water(pos[0], pos[2])
    for turn in range(0, 360, 20):
        b = bearing + math.radians(turn)
        for d in (dist, dist * 0.8, dist * 0.6, dist * 1.25) + FARTHER_NEARER:
            cx, cz = pos[0] + math.sin(b) * d, pos[2] + math.cos(b) * d
            if ground.is_water(cx, cz) and not afloat:
                continue
            g = ground.height(cx, cz)
            if afloat:
                g = max(g, pos[1])
            # a camera level with the POI or a little above it, not forty metres up a slope
            score = abs(g - pos[1]) + min(turn, 360 - turn) * 0.02 + abs(d - dist) * 0.05
            tried.append((score, cx, cz, g, d, d not in FARTHER_NEARER))
    tried.sort()
    trunks = props = None
    if scatter is not None:
        trunks = getattr(scatter, "trunks", None) or Trunks(scatter)
        scatter.trunks = trunks
        props = getattr(scatter, "props", None) or FC.Props(DP.GEN)
        scatter.props = props
    # First as strictly as the region shots are framed; then, in a wood where a trunk always stands
    # somewhere in front (the Greatwood's giant oaks), only clear of bark and over open ground.
    # Every pass is tried first with the frame check (tools/capture/frame_check.py: nothing
    # standing against the lens, the frame not a wall of trunks or leaves), and only then without.
    # the farther and nearer spots (FARTHER_NEARER) only when no other spot has a clear frame
    passes = ([(True, False) + p for p in PASSES] + [(True, True) + p for p in PASSES]
              + [(False, False) + p for p in PASSES])
    for framed, more, strict, frame_max in passes:
        if framed and props is None:
            continue
        for _score, cx, cz, g, d, usual in tried:
            if not usual and not more:
                continue
            look_deg = math.degrees(math.atan2(pos[2] - cz, pos[0] - cx))
            for up in (EYE, EYE + 3.0, EYE + 7.0, EYE + 14.0):
                cy = max(g + up, pos[1] + 1.0)
                cam = (cx, cy, cz)
                if scatter is not None:
                    if trunks.clearance(cx, cz) < BARK_CLEAR_M:
                        break
                    if cy - g <= EYE + 0.5:
                        # on the ground: under a canopy is fine, but not against a trunk
                        if scatter.nearest(cx, cz) < TRUNK_CLEAR_M:
                            continue
                        if strict and not scatter.view_clear(cx, cz, look_deg):
                            continue
                    elif scatter.in_crown(cx, cy, cz):
                        continue
                    if strict and scatter.crowns_across(cam, look, 2.0, max(d - OWN_M, 2.0)) > 0:
                        continue
                    if trunks.across(cam, look, max(d - OWN_M, 2.0)):
                        continue
                    if trunks.in_frame(cam, look) > frame_max:
                        continue
                if ground.clear(cam, look):
                    # checked on the heights it was chosen on, and on the runtime maps the
                    # committed plan's test reads, which are coarser
                    if framed and any(FC.faults({"pos": cam, "look_at": look, "fov": 58.0}, gr, props,
                                                spare=FRAME_SPARE, poi=True)
                                      for gr in (ground, getattr(scatter, "coarse", None)) if gr is not None):
                        continue
                    return [cx, cy, cz]
    # nothing holds: the old rule, the approach side at eye height, and say so
    cx, cz = pos[0] + math.sin(bearing) * dist, pos[2] + math.cos(bearing) * dist
    print("make_pois_plan: no camera for the POI at (%.0f, %.0f) passes; the approach side is used" % (pos[0], pos[2]))
    return [cx, max(ground.height(cx, cz) + EYE, pos[1] + 1.0), cz]


def shot_for(entry: dict, poi: dict, kind: str, roads, ground: Ground, scatter=None) -> dict:
    pos = entry["pos"]
    bearing = approach_bearing(pos, roads, ground)
    cx, cy, cz = camera_for(pos, kind, bearing, ground, scatter)
    region = poi.get("region", "")
    hour, weather = REGION_HOUR.get(region, (10.0, "core:weather/clear"))
    if kind in DUSK_KINDS:
        hour = DUSK_KINDS[kind]
    elif any(w in poi.get("unique_feature", "").lower() for w in LIT_WORDS):
        hour = DUSK_HOUR
    short = entry["place_id"].split("/")[-1]
    return {
        "label": "%s_%s" % (kind, short),
        "region": region,
        "pos": [round(cx, 1), round(cy, 1), round(cz, 1)],
        "look_at": [round(pos[0], 1), round(pos[1] + 1.5, 1), round(pos[2], 1)],
        "fov": 58.0,
        "time": hour,
        "weather": weather,
        "fog_scale": 0.6,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Write the POI capture plan")
    ap.add_argument("--out", default=os.path.join(REPO, "tools", "capture", "plans", "pois.json"))
    ap.add_argument("--kinds", default="", help="comma-separated kinds to include")
    ap.add_argument("--only", default="", help="comma-separated id substrings to include")
    ap.add_argument("--world", default="", help="a build directory rather than game/world/generated")
    args = ap.parse_args()
    world = args.world or GEN
    ground = Ground(world)
    DP.GEN = world                       # where the scatter's cells are read from
    scatter = DP.Scatter() if os.path.isdir(os.path.join(world, "cells")) else None
    if scatter is not None and os.path.exists(os.path.join(world, "heights.r32")):
        scatter.coarse = Ground(world, runtime=True)
    pois = load_json(os.path.join(world, "pois.json"))
    roads = load_json(os.path.join(world, "roads.json"))
    defs = {p["id"]: p for p in load_json(os.path.join(PACK, "pois", "pois.json"))}
    places = {p["id"]: p for p in load_json(os.path.join(PACK, "places", "places.json"))}
    kinds = {k for k in args.kinds.split(",") if k}
    only = [s for s in args.only.split(",") if s]
    shots = []
    for entry in pois:
        pid = entry["place_id"]
        if pid in defs:
            poi, kind = defs[pid], defs[pid]["kind"]
        elif pid in places and places[pid].get("dressing"):
            # a place the POI builders dress as one of their kinds (the Standing Moot's circle)
            poi, kind = places[pid], places[pid]["dressing"]
        elif pid in places and "shrine" in places[pid].get("tags", []):
            poi, kind = places[pid], "hearth"
        else:
            continue
        if kinds and kind not in kinds:
            continue
        if only and not any(s in pid for s in only):
            continue
        shots.append(shot_for(entry, poi, kind, roads, ground, scatter))
    shots.sort(key=lambda s: s["label"])
    plan = {"_doc": "Generated by tools/capture/make_pois_plan.py: one shot per point of interest, "
                    "30-50 m off at eye height from the approach side, at the hour that shows the kind.",
            "shots": shots}
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(plan, f, indent=1)
        f.write("\n")
    print("wrote %d shots to %s" % (len(shots), args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
