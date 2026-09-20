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
        hx, hz, hy = hh.high_point(vx, vz, 600.0)
        tx, tz = float(places[settlement]["position"][0]), float(places[settlement]["position"][1])
        # look at a point part-way to the settlement so the near ground is in frame too
        mx, mz = hx + (tx - hx) * 0.35, hz + (tz - hz) * 0.35
        shots.append(shot("%s_vista" % short, (hx, hy + 12.0, hz), (mx, hh.at(mx, mz) + 6.0, mz),
                          62.0, hour, weather, 1.0, region_id))
        # 3. the approach to the settlement, 420 m out and 28 m up, looking down on it
        sx, sz = tx, tz
        a2 = math.atan2(hz - sz, hx - sx)
        ax, az = sx + math.cos(a2) * 420.0, sz + math.sin(a2) * 420.0
        shots.append(shot("%s_approach" % short, (ax, hh.at(ax, az) + 28.0, az),
                          (sx, hh.at(sx, sz) + 4.0, sz), 55.0, hour, weather, 1.0, region_id))
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
