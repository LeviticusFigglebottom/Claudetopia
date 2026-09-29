#!/usr/bin/env python3
"""A contact sheet of one point of interest (or a few) from four sides, in the real country, before
the world is built again (docs/WORLD_LIFE.md).

    GODOT=... ~/bin/heavy python3 tools/world/poi_sheet.py core:poi/foxglove_dell
    GODOT=... ~/bin/heavy python3 tools/world/poi_sheet.py foxglove_dell gosling_pit --time 20.5
    python3 tools/world/poi_sheet.py foxglove_dell --plan-only        # write the plan, shoot nothing

Each POI is stood up where its def says, on a pad laid at runtime (the plan's "preview_pois",
PoiPreview), whether or not the built world has it, so a place written or moved since the last
world build is seen as it will stand. Three views from eye-level-ish obliques (the first from the
nearest road's side, the way a player comes) and one from above; Compatibility renderer under
xvfb (`./run.sh shots`), 1600x900. Writes captures/poi_sheet/<name>.jpg, each tile labelled with
its draw calls and primitives, prints each view's cost against the per-view budgets
(docs/WORLD_LIFE.md), and deletes the PNGs. `--built` shoots the built world's own instead (no
preview), for a before and after. The world build is still the source of truth.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools", "capture"))

from worldgen import content as CONTENT  # noqa: E402
from worldgen import roads as RD  # noqa: E402

PACK = os.path.join(REPO, "game", "content", "packs", "core")
GEN = os.path.join(REPO, "game", "world", "generated")
OUT = os.path.join(REPO, "captures", "poi_sheet")
## docs/WORLD_LIFE.md: what one view of a place may cost (Compatibility, 1600x900). The worst view
## anywhere may not pass the budget (DESIGN.md section 11); a view at a place aims under the aim,
## to leave room for the people, the foes and the weather a sheet does not show.
BUDGET_DRAWS, BUDGET_PRIMS = 2000, 1_500_000
AIM_DRAWS, AIM_PRIMS = 1400, 1_100_000


def _def(pid: str, defs: dict) -> dict:
    full = pid if pid.startswith("core:") else "core:poi/%s" % pid
    if full not in defs:
        raise SystemExit("no POI %s in game/content/packs/core/pois/" % full)
    return defs[full]


def _approach(x: float, z: float, roads: list) -> float:
    """Compass bearing (0 north = -z, 90 east = +x) from the place toward its nearest road."""
    best = (1e18, 180.0)
    for r in roads:
        for px, pz in r["points"]:
            d = (px - x) ** 2 + (pz - z) ** 2
            if d < best[0] and d > 25.0:
                best = (d, math.degrees(math.atan2(px - x, -(pz - z))) % 360.0)
    return best[1]


def plan_for(ids: list, time_h: float, built: bool) -> dict:
    defs = {d["id"]: d for d in CONTENT.poi_registry(PACK)}
    pois = {e["place_id"]: e for e in json.load(open(os.path.join(GEN, "pois.json"), encoding="utf-8"))}
    roads = json.load(open(os.path.join(GEN, "roads.json"), encoding="utf-8"))
    shots = []
    full_ids = []
    for pid in ids:
        d = _def(pid, defs)
        full_ids.append(d["id"])
        e = pois.get(d["id"])
        r = float(e["radius_flat_m"]) if (e and built) else RD.pad_radius(dict(d))
        x, z = float(d["position"][0]), float(d["position"][1])
        b0 = _approach(x, z, roads)
        name = d["id"].split("/")[-1]
        dist = max(26.0, 1.5 * r)
        look = {"place": d["id"], "height": 2.0}
        for k, db in enumerate((0.0, 120.0, 240.0)):
            shots.append({"label": "%s_%d" % (name, k + 1), "region": d.get("region", ""),
                          "at": {"place": d["id"], "bearing": (b0 + db) % 360.0, "distance": dist,
                                 "height": 3.0 + 0.18 * dist},
                          "look": look, "fov": 60.0, "time": time_h})
        shots.append({"label": "%s_4_above" % name, "region": d.get("region", ""),
                      "at": {"place": d["id"], "bearing": (b0 + 60.0) % 360.0, "distance": 0.9 * r + 14.0,
                             "height": 1.5 * r + 22.0},
                      "look": look, "fov": 60.0, "time": time_h})
    plan = {"_doc": "Written by tools/world/poi_sheet.py: each POI from four sides, on a pad laid at runtime.",
            "shots": shots}
    if not built:
        plan["preview_pois"] = full_ids
    return plan


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("ids", nargs="+", help="POI ids or short names")
    ap.add_argument("--time", type=float, default=11.0, help="the hour to shoot at")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--built", action="store_true", help="the built world's entry, not a preview")
    ap.add_argument("--plan-only", action="store_true")
    ap.add_argument("--keep", action="store_true", help="keep the PNGs")
    args = ap.parse_args(argv)
    plan = plan_for(args.ids, args.time, args.built)
    name = "_".join(i.split("/")[-1] for i in args.ids)[:80] + ("_built" if args.built else "")
    work = os.path.join(args.out, name)
    os.makedirs(work, exist_ok=True)
    plan_path = os.path.join(work, "plan.json")
    with open(plan_path, "w", encoding="utf-8") as f:
        json.dump(plan, f, indent=1)
    if args.plan_only:
        print("[sheet] plan: %s" % plan_path)
        return 0
    shots = os.path.join(work, "shots")
    os.makedirs(shots, exist_ok=True)
    code = subprocess.run([os.path.join(REPO, "run.sh"), "shots", plan_path, "--out=%s" % shots]).returncode
    import contact_sheet  # noqa: E402
    sheet = os.path.join(args.out, name + ".jpg")
    over = []
    pngs = [f for f in os.listdir(shots) if f.endswith(".png")] if os.path.isdir(shots) else []
    if pngs:
        contact_sheet.build(shots, sheet, 2, 1600)
        perf_path = os.path.join(shots, "perf.json")
        if os.path.exists(perf_path):
            for s in json.load(open(perf_path, encoding="utf-8")).get("shots", []):
                dc, pr = int(s.get("draw_calls", 0)), int(s.get("primitives", 0))
                ok = dc <= BUDGET_DRAWS and pr <= BUDGET_PRIMS
                aim = dc <= AIM_DRAWS and pr <= AIM_PRIMS
                print("[sheet] %-40s %5d draws  %5.2f M prims  %s" % (
                    s.get("label", s.get("file", "")), dc, pr / 1e6,
                    "ok" if aim else ("over the aim (%d / %.1f M)" % (AIM_DRAWS, AIM_PRIMS / 1e6) if ok
                                      else "OVER the budget (%d / %.1f M)" % (BUDGET_DRAWS, BUDGET_PRIMS / 1e6))))
                if not ok:
                    over.append(s.get("label", ""))
        print("[sheet] %s" % os.path.relpath(sheet, REPO))
    if not args.keep:
        shutil.rmtree(shots, ignore_errors=True)
    if code != 0 or not pngs:
        print("[sheet] the capture failed (exit %d)" % code)
        return 1
    return 2 if over else 0


if __name__ == "__main__":
    sys.exit(main())
