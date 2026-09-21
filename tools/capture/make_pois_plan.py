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

# the hour and weather each region is written for (tools/capture/make_default_plan.py)
REGION_HOUR = {
    "core:region/hearthvale": (9.0, "core:weather/clear"),
    "core:region/brightwater": (12.0, "core:weather/clear"),
    "core:region/sedgemire": (7.5, "core:weather/overcast"),
    "core:region/briarwold": (10.5, "core:weather/still"),
    "core:region/skerrow": (14.0, "core:weather/clear_cold"),
    "core:region/cinderlea": (16.5, "core:weather/dry_wind"),
}
# kinds that carry a fire or a lantern are shot in the last of the light, when a lamp shows
# and the ground still does (by 19:00 the country is black)
DUSK_KINDS = {"camp": 18.0, "shrine": 18.0, "hearth": 18.0, "wreck": 17.8}
# how far off the camera stands, by how big the thing is
DISTANCE = {"giant_bones": 48.0, "tower": 44.0, "bridge": 40.0, "waterfall": 42.0, "strange_tree": 44.0,
            "hidden_valley": 38.0, "wreck": 36.0, "ruins": 38.0, "standing_stones": 34.0, "camp": 34.0,
            "shrine": 30.0, "strange": 30.0, "hearth": 26.0}
EYE = 1.65


class Ground:
    def __init__(self) -> None:
        with open(os.path.join(GEN, "world_manifest.json"), "r", encoding="utf-8") as f:
            man = json.load(f)
        rt = man["runtime"]
        self.n = int(rt["grid"])
        self.spacing = float(man["size_m"]) / self.n
        self.origin = man["origin"]
        self.h = np.fromfile(os.path.join(GEN, rt["heights"]), dtype="<f4").reshape(self.n, self.n)
        self.water = np.fromfile(os.path.join(GEN, rt["water"]), dtype=np.uint8).reshape(self.n, self.n)

    def _ij(self, x: float, z: float) -> tuple:
        j = int(np.clip((x - self.origin[0]) / self.spacing, 0, self.n - 1))
        i = int(np.clip((z - self.origin[1]) / self.spacing, 0, self.n - 1))
        return i, j

    def height(self, x: float, z: float) -> float:
        i, j = self._ij(x, z)
        return float(self.h[i, j])

    def is_water(self, x: float, z: float) -> bool:
        i, j = self._ij(x, z)
        return bool(self.water[i, j] > 0)


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


def shot_for(entry: dict, poi: dict, kind: str, roads, ground: Ground) -> dict:
    pos = entry["pos"]
    dist = DISTANCE.get(kind, 34.0)
    bearing = approach_bearing(pos, roads, ground)
    # a camera in the water or below the pad is no good: walk the bearing round until dry
    for turn in range(0, 360, 30):
        b = bearing + math.radians(turn)
        cx, cz = pos[0] + math.sin(b) * dist, pos[2] + math.cos(b) * dist
        if not ground.is_water(cx, cz):
            break
    cy = max(ground.height(cx, cz), pos[1] - 2.0) + EYE
    # looking down at a thing 40 m below reads as a map; look from at least a little above
    cy = max(cy, pos[1] + 1.0)
    region = poi.get("region", "")
    hour, weather = REGION_HOUR.get(region, (10.0, "core:weather/clear"))
    if kind in DUSK_KINDS:
        hour = DUSK_KINDS[kind]
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
    args = ap.parse_args()
    ground = Ground()
    pois = load_json(os.path.join(GEN, "pois.json"))
    roads = load_json(os.path.join(GEN, "roads.json"))
    defs = {p["id"]: p for p in load_json(os.path.join(PACK, "pois", "pois.json"))}
    places = {p["id"]: p for p in load_json(os.path.join(PACK, "places", "places.json"))}
    kinds = {k for k in args.kinds.split(",") if k}
    only = [s for s in args.only.split(",") if s]
    shots = []
    for entry in pois:
        pid = entry["place_id"]
        if pid in defs:
            poi, kind = defs[pid], defs[pid]["kind"]
        elif pid in places and "shrine" in places[pid].get("tags", []):
            poi, kind = places[pid], "hearth"
        else:
            continue
        if kinds and kind not in kinds:
            continue
        if only and not any(s in pid for s in only):
            continue
        shots.append(shot_for(entry, poi, kind, roads, ground))
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
