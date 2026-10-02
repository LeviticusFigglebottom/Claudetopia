#!/usr/bin/env python3
"""A region's audit for the world-life work (docs/WORLD_LIFE.md): where its land is empty, how much
each of its points of interest does, and where they do not stand right.

    python3 tools/world/region_audit.py hearthvale                # report from the committed probe
    python3 tools/world/region_audit.py hearthvale --probe        # raise every POI in Godot first
    python3 tools/world/region_audit.py all --out docs/review/world_life

Writes <out>/audit_<region>.md and audit_<region>.png (out: docs/review/world_life). `--probe`
runs `./run.sh poi-probe` for the region (Godot, headless, a few minutes: run it under
~/bin/heavy) and keeps what it measured in <out>/probe_<region>.json, which a later run without
`--probe` reads again.

It reads the installed world (game/world/generated: the 8 m runtime maps, roads.json, pois.json,
the cells' signposts and milestones) and the content pack. A POI the world was not built with is
counted where its def stands, with the pad the build would give it (PoiPreview), so a region's
new places close their gaps here before the next world build.

(a) Empty land: the land of the region further than --gap metres from every place, POI and
    roadside feature (a signpost, a milestone), measured from the edge of each one's pad. Each
    stretch of it, largest first: its middle (the point furthest from anything), its area and
    extent, its slope, the province and biome it is in (the atlas), whether a road runs through it
    or how far the nearest is, and up to three sites in it for a new place (gentle ground, as far
    from everything as the stretch allows, near a road where one is near).
(b) Every POI: kind, footprint, pieces, draw cost, interactables, enemies, loot, NPCs, and whether
    it has a quest, an encounter, an interior, a Hearthstone, a landmark model. An impact score
    (IMPACT below) and a flag for the weak ones.
(c) Placement problems: the probe's seat audit (floating, buried, sunk, standing in a road,
    overlapping, a lamp hung from nothing), pads that overlap, a road through a place's level
    core, a place in water, pieces standing past the pad, and the cut or fill a pad makes.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from worldgen import atlas as ATLAS  # noqa: E402
from worldgen import content as CONTENT  # noqa: E402
from worldgen import roads as RD  # noqa: E402

GEN = os.path.join(REPO, "game", "world", "generated")
PACK = os.path.join(REPO, "game", "content", "packs", "core")
OUT = os.path.join(REPO, "docs", "review", "world_life")
REGIONS = CONTENT.REGIONS

## Land further than this from everything is a gap (m, from the edge of a pad).
GAP_M = 200.0
## A stretch smaller than this is not listed (km2).
MIN_STRETCH_KM2 = 0.04
## Roadside features: what the cells stand by the roads that marks a spot (m of radius).
ROADSIDE_RE = re.compile(r"(signpost|milestone)")
ROADSIDE_R = 4.0
## A site suggested for a new place: ground no steeper than this (degrees), this far apart (m).
SITE_SLOPE_DEG = 14.0
SITE_APART_M = 280.0
## Road furniture: a road through the middle of one of these is what it is for (the road planner's own
## list, roads.ROAD_FURNITURE_KINDS).
ROAD_KINDS = set(RD.ROAD_FURNITURE_KINDS)


def roads_meant_through(atlas: dict) -> set:
    """The POIs a road is meant to run through the middle of, as the road planner reads the atlas
    (roads.poi_cores, roads.poi_road_ends): a road's `through`, and a place several roads end at,
    where they meet."""
    count: dict = {}
    out = {str(t) for s in atlas.get("roads", []) for t in s.get("through", [])}
    for s in atlas.get("roads", []):
        for e in (s.get("from"), s.get("to")):
            count[e] = count.get(e, 0) + 1
    return out | {e for e, n in count.items() if n > 1 and ":poi/" in str(e)}
WET_KINDS = {"bridge", "wreck", "strange", "waterfall", "edge"}
## A pad's skirt steeper than this (degrees, mean along a line out from the level core to its reach)
## reads as a cut or an embankment.
SKIRT_DEG = 33.0
## Ground under a new place's pad steeper than this (mean, degrees) will be cut and filled hard.
SITE_STEEP_DEG = 18.0
## The last of the map toward its edge is not counted as land to fill (m), nor ground steeper than
## WILD_DEG (a crag, a cliff, a mountain wall: nobody walks it, and nothing is built on it).
EDGE_M = 250.0
WILD_DEG = 32.0


def skirt_deg(world: "World", x: float, z: float, r: float) -> float:
    """The steepest of 16 lines out across a pad's skirt, as its mean slope in degrees."""
    level_r, reach = RD.PAD_LEVEL * r, RD.PAD_LEVEL * r + RD.PAD_SKIRT * r
    worst = 0.0
    for k in range(16):
        a = 2 * math.pi * k / 16
        h0 = world.height(x + math.cos(a) * level_r, z + math.sin(a) * level_r)
        h1 = world.height(x + math.cos(a) * reach, z + math.sin(a) * reach)
        worst = max(worst, math.degrees(math.atan(abs(h1 - h0) / max(reach - level_r, 1.0))))
    return worst


def site_deg(world: "World", x: float, z: float, r: float) -> float:
    """The mean slope of the ground under a pad (degrees), as it stands."""
    i, j = world.ij(x, z)
    rt = max(int(r / world.sp), 1)
    return float(world.slope[max(i - rt, 0):i + rt + 1, max(j - rt, 0):j + rt + 1].mean())

## The impact score (b): how much a place gives a player who finds it. Each line is points.
IMPACT = [
    ("size", "footprint reach (m from the middle to its furthest piece): <8 = 0, <14 = 1, <22 = 2, "
             "<32 = 3, else 4"),
    ("things", "interactables in the dressing (Hearthstone, touch, container, readable ...): 1 each, "
               "up to 3"),
    ("foes", "an encounter that stands foes up: 1, and 1 more for 4 or more"),
    ("loot", "something to take (an encounter's `lies`, a quest's item, a find): 1"),
    ("people", "an NPC who lives or stands there: 1, 2 for two or more"),
    ("quest", "a quest sends you there: 2"),
    ("interior", "a door into an interior: 2"),
    ("landmark", "a landmark model (a `scene` in pois.json): 2"),
    ("hearth", "a Hearthstone: 1"),
]
WEAK_SCORE = 3          # at or under this: small / no impact
SMALL_REACH_M = 10.0


def size_points(reach: float) -> int:
    for i, lim in enumerate((8.0, 14.0, 22.0, 32.0)):
        if reach < lim:
            return i
    return 4


# --- the world ------------------------------------------------------------------------------------

class World:
    """The installed world's runtime maps (8 m a texel) and what stands on them."""

    def __init__(self, gen: str = GEN) -> None:
        self.gen = gen
        self.man = json.load(open(os.path.join(gen, "world_manifest.json"), encoding="utf-8"))
        rt = self.man["runtime"]
        self.n = int(rt["grid"])
        self.size = float(self.man.get("size_m", 8192))
        self.sp = self.size / self.n
        self.ox, self.oz = map(float, self.man["origin"])
        full = int(self.man.get("grid", 0))
        off = (full // self.n - 1) * (self.size / full) * 0.5 if full > self.n and full % self.n == 0 else 0.0
        self.hx, self.hz = self.ox + off, self.oz + off
        n = self.n
        self.H = np.fromfile(os.path.join(gen, rt["heights"]), dtype="<f4").reshape(n, n)
        self.R = np.fromfile(os.path.join(gen, rt["regions"]), dtype=np.uint8).reshape(n, n)
        self.W = np.fromfile(os.path.join(gen, rt["water"]), dtype=np.uint8).reshape(n, n)
        self.L = np.fromfile(os.path.join(gen, rt["water_level"]), dtype="<f4").reshape(n, n)
        gy, gx = np.gradient(self.H.astype(np.float64), self.sp)
        self.slope = np.degrees(np.arctan(np.hypot(gx, gy)))
        self.region_index = {r.split("/")[-1]: i for i, r in enumerate(self.man["regions"])}
        self.roads = json.load(open(os.path.join(gen, "roads.json"), encoding="utf-8"))
        self.built = {e["place_id"]: e for e in json.load(open(os.path.join(gen, "pois.json"), encoding="utf-8"))}

    def ij(self, x, z):
        j = np.clip(((np.asarray(x) - self.ox) / self.sp).astype(int), 0, self.n - 1)
        i = np.clip(((np.asarray(z) - self.oz) / self.sp).astype(int), 0, self.n - 1)
        return i, j

    def xz(self, i, j):
        return self.ox + (j + 0.5) * self.sp, self.oz + (i + 0.5) * self.sp

    def height(self, x: float, z: float) -> float:
        fx = min(max((x - self.hx) / self.sp, 0.0), self.n - 1.001)
        fz = min(max((z - self.hz) / self.sp, 0.0), self.n - 1.001)
        x0, z0 = int(fx), int(fz)
        tx, tz = fx - x0, fz - z0
        H = self.H
        top = H[z0, x0] + (H[z0, x0 + 1] - H[z0, x0]) * tx
        bot = H[z0 + 1, x0] + (H[z0 + 1, x0 + 1] - H[z0 + 1, x0]) * tx
        return float(top + (bot - top) * tz)

    def roadside(self) -> list:
        """[(x, z)] of every signpost and milestone the cells stand."""
        out = []
        for f in glob.glob(os.path.join(self.gen, "cells", "*.json")):
            for path, rows in json.load(open(f, encoding="utf-8")).get("instances", {}).items():
                if ROADSIDE_RE.search(path.rsplit("/", 1)[-1]):
                    out.extend((float(r[0]), float(r[2])) for r in rows)
        return out

    def road_mask(self) -> np.ndarray:
        m = np.zeros((self.n, self.n), dtype=bool)
        for r in self.roads:
            pts = np.asarray(r["points"], dtype=np.float64)
            if len(pts) < 2:
                continue
            seg = np.diff(pts, axis=0)
            L = np.hypot(seg[:, 0], seg[:, 1])
            for (a, s, l) in zip(pts[:-1], seg, L):
                k = max(int(l / (self.sp * 0.5)), 1)
                t = np.linspace(0.0, 1.0, k + 1)
                i, j = self.ij(a[0] + s[0] * t, a[1] + s[1] * t)
                m[i, j] = True
        return m


# --- the content ----------------------------------------------------------------------------------

def load_content(pack: str = PACK) -> dict:
    pois = CONTENT.poi_registry(pack)
    places = json.load(open(os.path.join(pack, "places", "places.json"), encoding="utf-8"))
    enc = defaultdict(list)
    for e in CONTENT.rows(pack, "encounters"):
        if isinstance(e, dict) and e.get("place"):
            enc[e["place"]].append(e)
    npcs = defaultdict(list)
    for n in CONTENT.rows(pack, "npcs"):
        if isinstance(n, dict) and n.get("home_place"):
            npcs[n["home_place"]].append(n["id"])
    interiors = defaultdict(list)
    for d in CONTENT.rows(pack, "interiors"):
        if isinstance(d, dict) and d.get("place") and str(d.get("id", "")).startswith("core:interior/"):
            interiors[d["place"]].append(d["id"])
    # what each POI's hook pays off in, worked out as tools/poi_hooks.py works out its table
    sys.path.insert(0, os.path.join(REPO, "tools"))
    import poi_hooks as HOOKS
    hooks = {r["poi"]: r for r in HOOKS.rows(HOOKS.defs())}
    return {"pois": pois, "places": places, "enc": enc, "npcs": npcs, "interiors": interiors, "hooks": hooks}


def things(world: World, content: dict) -> list:
    """Everything that marks a spot: {id, kind, x, z, r, cls, built}, pads at their built radius
    (or the pad a def not yet built would get)."""
    out = []
    for d in list(content["places"]) + list(content["pois"]):
        pos = d.get("position")
        if not pos or len(pos) < 2 or str(d.get("kind", "")) in ("edge", "deep_place", "interior_dungeon"):
            continue
        e = world.built.get(d["id"])
        if e is not None:
            x, z, r = float(e["pos"][0]), float(e["pos"][2]), float(e.get("radius_flat_m", 25.0))
        else:
            x, z = float(pos[0]), float(pos[1])
            r = RD.pad_radius({"id": d["id"], "kind": d.get("kind", ""), "wayside": d.get("wayside"),
                               "pad_radius_m": d.get("pad_radius_m")})
        out.append({"id": d["id"], "kind": str(d.get("kind", "")), "x": x, "z": z, "r": r,
                    "cls": "place" if ":place/" in d["id"] else "poi", "built": e is not None,
                    "region": CONTENT.region_of(d), "def": d})
    for x, z in world.roadside():
        out.append({"id": "roadside", "kind": "roadside", "x": x, "z": z, "r": ROADSIDE_R, "cls": "roadside",
                    "built": True, "region": ""})
    return out


# --- (a) empty land -------------------------------------------------------------------------------

def distance_field(world: World, marks: list) -> np.ndarray:
    """Metres from each texel to the edge of the nearest mark's pad (0 inside one)."""
    n = world.n
    occ = np.zeros((n, n), dtype=bool)
    for t in marks:
        rt = int(math.ceil(t["r"] / world.sp)) + 1
        i0, j0 = world.ij(t["x"], t["z"])
        i0, j0 = int(i0), int(j0)
        ii, jj = np.mgrid[max(i0 - rt, 0):min(i0 + rt + 1, n), max(j0 - rt, 0):min(j0 + rt + 1, n)]
        cx, cz = world.xz(ii, jj)
        occ[ii, jj] |= np.hypot(cx - t["x"], cz - t["z"]) <= t["r"]
    return ndimage.distance_transform_edt(~occ) * world.sp


def stretches(world: World, region: str, dist: np.ndarray, road_d: np.ndarray, atlas: dict,
              gap: float = GAP_M) -> tuple:
    """(the stretches of empty land, largest first; the region's land numbers)."""
    idx = world.region_index[region]
    # land a body walks: not water, not ground steeper than WILD_DEG, not the map's last metres
    land = (world.R == idx) & (world.W == 0) & (world.slope <= WILD_DEG)
    edge = int(EDGE_M / world.sp)
    land[:edge, :] = land[-edge:, :] = land[:, :edge] = land[:, -edge:] = False
    far = land & (dist > gap)
    lab, k = ndimage.label(far, structure=np.ones((3, 3)))
    px = world.sp * world.sp / 1e6
    out = []
    if k:
        sizes = ndimage.sum(far, lab, index=np.arange(1, k + 1))
        for c in np.argsort(-sizes):
            area = float(sizes[c]) * px
            if area < MIN_STRETCH_KM2:
                break
            m = lab == (c + 1)
            ii, jj = np.nonzero(m)
            best = int(np.argmax(dist[ii, jj]))
            x, z = world.xz(ii[best], jj[best])
            xs, zs = world.xz(ii, jj)
            rd = road_d[ii, jj]
            prov, _depth = ATLAS.province_at(atlas, float(x), float(z))
            forest = next((f.get("name", f["id"]) for f in atlas.get("forests", [])
                           if ATLAS.point_in_polygon(float(x), float(z), f["polygon"])), "")
            out.append({
                "rank": len(out) + 1, "x": round(float(x)), "z": round(float(z)), "area_km2": round(area, 3),
                "extent_m": [round(float(xs.max() - xs.min()) + world.sp), round(float(zs.max() - zs.min()) + world.sp)],
                "furthest_m": round(float(dist[ii[best], jj[best]])),
                "slope_mean": round(float(world.slope[ii, jj].mean()), 1),
                "slope_p75": round(float(np.percentile(world.slope[ii, jj], 75)), 1),
                "height_m": round(float(world.H[ii[best], jj[best]])),
                "province": prov["name"] if prov else "", "biome": prov.get("biome", "") if prov else "",
                "forest": forest,
                "road_inside_m": round(float((rd <= world.sp * 0.75).sum() * world.sp)),
                "road_nearest_m": round(float(rd.min())),
                "sites": sites(world, ii, jj, dist, rd),
            })
    total = float(land.sum()) * px
    stats = {"land_km2": round(total, 2), "far_km2": round(float(far.sum()) * px, 2),
             "far_share": round(float(far.sum()) / max(float(land.sum()), 1.0), 3),
             "far2_share": round(float((land & (dist > 2 * gap)).sum()) / max(float(land.sum()), 1.0), 3),
             "gap_m": gap,
             "share_by_m": {str(m): round(float((land & (dist > m)).sum()) / max(float(land.sum()), 1.0), 3)
                            for m in (100, 150, 200, 300, 400)}}
    return out, stats


def sites(world: World, ii, jj, dist, rd) -> list:
    """Up to three spots for a new place in a stretch: gentle, far from everything, near a road."""
    s = world.slope[ii, jj]
    ok = s <= SITE_SLOPE_DEG
    if not ok.any():
        return []
    score = np.minimum(dist[ii, jj], 600.0) - 0.4 * np.maximum(rd[ii, jj] if np.ndim(rd) == 2 else rd, 60.0) - 6.0 * s
    order = np.argsort(-np.where(ok, score, -1e9))
    out = []
    for o in order[:4000]:
        if not ok[o]:
            break
        x, z = world.xz(ii[o], jj[o])
        if all(math.hypot(x - a, z - b) >= SITE_APART_M for a, b, _s, _r in out):
            rr = rd[ii[o], jj[o]] if np.ndim(rd) == 2 else rd[o]
            out.append((round(float(x)), round(float(z)), round(float(s[o]), 1), round(float(rr))))
        if len(out) == 3:
            break
    return [{"x": a, "z": b, "slope": c, "road_m": d} for a, b, c, d in out]


# --- (b) the POIs ---------------------------------------------------------------------------------

def poi_rows(world: World, region: str, content: dict, probe: dict) -> list:
    out = []
    for d in content["pois"]:
        if CONTENT.region_of(d) != region:
            continue
        pid = d["id"]
        p = probe.get(pid, {})
        e = world.built.get(pid, {})
        encs = content["enc"].get(pid, [])
        foes = sum(int(s.get("count", 1)) for x in encs for s in x.get("spawns", []))
        hook = content["hooks"].get(pid, {})
        loot = sum(len(x.get("lies", [])) for x in encs) + len(hook.get("finds", []))
        things_ = dict(p.get("interactables", {}))
        loot += int(things_.get("WorldContainer", 0)) + int(things_.get("WorldItem", 0))
        npcs = len(content["npcs"].get(pid, [])) + int(things_.get("Npc", 0))
        n_things = sum(v for k, v in things_.items() if k not in ("Npc",))
        reach = float(p.get("footprint", {}).get("reach", 0.0)) if p else 0.0
        row = {
            "id": pid, "name": d.get("name", pid), "kind": d.get("kind", ""), "wayside": bool(d.get("wayside")),
            "built": bool(e), "probed": bool(p), "pos": d.get("position"),
            "pad_m": float(e.get("radius_flat_m", 0.0)) or RD.pad_radius(dict(d, id=pid)),
            "reach": reach, "footprint": p.get("footprint", {}), "pieces": p.get("pieces", 0),
            "draws": p.get("draws", 0), "primitives": p.get("primitives", 0),
            "things": n_things, "things_by": things_, "foes": foes, "loot": loot, "npcs": npcs,
            "quest": bool(hook.get("quests")), "encounter": bool(encs), "interior": bool(content["interiors"].get(pid)),
            "hearth": bool(d.get("hearthstone")) or int(p.get("hearthstones", 0)) > 0,
            "landmark": bool(e.get("scene")),
            "seat": p.get("seat", {}), "findings": p.get("findings", []), "embankment_m": p.get("embankment_m"),
        }
        pts = {
            "size": size_points(reach) if p else 0,
            "things": min(n_things, 3),
            "foes": (1 if foes > 0 else 0) + (1 if foes >= 4 else 0),
            "loot": 1 if loot > 0 else 0,
            "people": min(npcs, 2),
            "quest": 2 if row["quest"] else 0,
            "interior": 2 if row["interior"] else 0,
            "landmark": 2 if row["landmark"] else 0,
            "hearth": 1 if row["hearth"] else 0,
        }
        row["points"] = pts
        row["score"] = sum(pts.values())
        row["weak"] = row["score"] <= WEAK_SCORE
        row["small"] = bool(p) and reach < SMALL_REACH_M
        out.append(row)
    return out


# --- (c) placement --------------------------------------------------------------------------------

def placement(world: World, region: str, rows: list, marks: list, road_d_at, through: set | None = None) -> list:
    """[{id, what, detail}] for the region's POIs. `through`: the POIs a road is meant to run through
    (`roads_meant_through`)."""
    out = []
    mine = {r["id"]: r for r in rows}
    pads = [t for t in marks if t["cls"] != "roadside"]
    for r in rows:
        for check, n in sorted(r["seat"].items()):
            ex = next((f for f in r["findings"] if f.get("check") == check), {})
            out.append({"id": r["id"], "what": "seat:" + check, "n": n,
                        "detail": "%s %s at (%.0f, %.0f): %s" % (ex.get("family", ""), ex.get("asset", ""),
                                                                 ex.get("x", 0), ex.get("z", 0), ex.get("detail", ""))})
        if r["probed"] and r["reach"] > r["pad_m"] + 2.0:
            out.append({"id": r["id"], "what": "past_pad", "n": 1,
                        "detail": "pieces reach %.0f m from its middle; its pad is %.0f m" % (r["reach"], r["pad_m"])})
        pos = r["pos"] or [0, 0]
        if r["built"]:
            e = world.built[r["id"]]
            sk = skirt_deg(world, float(e["pos"][0]), float(e["pos"][2]), float(e.get("radius_flat_m", 25.0)))
            if sk > SKIRT_DEG:
                out.append({"id": r["id"], "what": "steep_skirt", "n": 1,
                            "detail": "its pad's skirt falls at %.0f deg: a cut or an embankment" % sk})
        else:
            sd = site_deg(world, float(pos[0]), float(pos[1]), r["pad_m"])
            if sd > SITE_STEEP_DEG:
                out.append({"id": r["id"], "what": "steep_site", "n": 1,
                            "detail": "the ground under its pad slopes %.0f deg on average" % sd})
    for t in pads:
        if t["id"] not in mine:
            continue
        r = mine[t["id"]]
        for u in pads:
            if u["id"] == t["id"] or (u["id"] in mine and u["id"] < t["id"]):
                continue
            d = math.hypot(t["x"] - u["x"], t["z"] - u["z"])
            if d < t["r"] + u["r"]:
                sev = "on top of" if d < max(t["r"], u["r"]) else "pads overlap with"
                out.append({"id": t["id"], "what": "overlap_pad", "n": 1,
                            "detail": "%s %s (%.0f m apart, pads %.0f + %.0f m)" % (sev, u["id"], d, t["r"], u["r"])})
        i, j = world.ij(t["x"], t["z"])
        if world.W[i, j] and r["kind"] not in WET_KINDS:
            out.append({"id": t["id"], "what": "in_water", "n": 1, "detail": "its middle is in water"})
        rd = road_d_at(t["x"], t["z"])
        core = 0.7 * t["r"]
        if rd < core - 3.0 and r["kind"] not in ROAD_KINDS and not r["wayside"] and t["id"] not in (through or ()):
            out.append({"id": t["id"], "what": "road_through", "n": 1,
                        "detail": "a road passes %.0f m from its middle, inside its %.0f m level core" % (rd, core)})
    return out


# --- the report -----------------------------------------------------------------------------------

def audit(region: str, world: World, content: dict, atlas: dict, probe: dict, gap: float = GAP_M,
          marks: list | None = None) -> dict:
    marks = marks if marks is not None else things(world, content)
    dist = distance_field(world, marks)
    roads = world.road_mask()
    road_d = ndimage.distance_transform_edt(~roads) * world.sp
    gaps, stats = stretches(world, region, dist, road_d, atlas, gap)
    rows = poi_rows(world, region, content, probe)

    def road_d_at(x, z):
        best = 1e9
        for rr in world.roads:
            pts = np.asarray(rr["points"], dtype=np.float64)
            if len(pts) < 2:
                continue
            if (pts[:, 0].min() - 200 > x or pts[:, 0].max() + 200 < x or pts[:, 1].min() - 200 > z
                    or pts[:, 1].max() + 200 < z):
                continue
            a, b = pts[:-1], pts[1:]
            ab = b - a
            t = np.clip(((x - a[:, 0]) * ab[:, 0] + (z - a[:, 1]) * ab[:, 1]) / np.maximum((ab ** 2).sum(1), 1e-9), 0, 1)
            px, pz = a[:, 0] + ab[:, 0] * t, a[:, 1] + ab[:, 1] * t
            best = min(best, float(np.hypot(px - x, pz - z).min()))
        return best

    problems = placement(world, region, rows, marks, road_d_at, roads_meant_through(atlas))
    mine = [t for t in marks if t["cls"] == "poi" and t["region"] == region]
    stats["pois"] = len(rows)
    stats["pois_per_km2"] = round(len(rows) / max(stats["land_km2"], 0.01), 2)
    stats["weak"] = sum(1 for r in rows if r["weak"] and not r["wayside"])
    stats["weak_wayside"] = sum(1 for r in rows if r["weak"] and r["wayside"])
    stats["strong"] = sum(1 for r in rows if r["score"] >= 8)
    stats["probed"] = sum(1 for r in rows if r["probed"])
    stats["unbuilt"] = sum(1 for t in mine if not t["built"])
    stats["largest_gap_km2"] = gaps[0]["area_km2"] if gaps else 0.0
    stats["problems"] = len(problems)
    stats["problem_pois"] = len({p["id"] for p in problems})
    return {"region": region, "gaps": gaps, "stats": stats, "rows": rows, "problems": problems,
            "dist": dist, "roads": roads, "marks": marks}


def write_png(a: dict, world: World, path: str) -> None:
    from PIL import Image, ImageDraw
    idx = world.region_index[a["region"]]
    # the region's own dry ground: its pieces of 1% of it or more, not the odd texel the map keeps elsewhere
    dry = (world.R == idx) & (world.W == 0)
    lab, k = ndimage.label(dry)
    sizes = ndimage.sum(dry, lab, index=np.arange(1, k + 1))
    keep = np.isin(lab, 1 + np.nonzero(sizes >= 0.01 * dry.sum())[0])
    ii, jj = np.nonzero(keep)
    pad = 16
    lo_i, hi_i, lo_j, hi_j = ii.min(), ii.max(), jj.min(), jj.max()
    i0, i1 = max(lo_i - pad, 0), min(hi_i + pad, world.n - 1)
    j0, j1 = max(lo_j - pad, 0), min(hi_j + pad, world.n - 1)
    H = world.H[i0:i1 + 1, j0:j1 + 1].astype(np.float64)
    gy, gx = np.gradient(H, world.sp)
    shade = np.clip(0.55 + 0.45 * (-gx * 0.7 - gy * 0.7) / np.sqrt(1 + gx * gx + gy * gy), 0, 1)
    rgb = np.stack([shade * 150 + 60, shade * 150 + 70, shade * 120 + 50], -1)
    other = world.R[i0:i1 + 1, j0:j1 + 1] != idx
    rgb[other] = rgb[other] * 0.45 + 30
    wet = world.W[i0:i1 + 1, j0:j1 + 1] != 0
    rgb[wet] = (70, 110, 160)
    far = (a["dist"][i0:i1 + 1, j0:j1 + 1] > a["stats"]["gap_m"]) & ~other & ~wet
    rgb[far] = rgb[far] * 0.5 + np.array([200, 60, 170]) * 0.5
    rgb[a["roads"][i0:i1 + 1, j0:j1 + 1]] = (235, 215, 160)
    scale = 1100.0 / max(i1 - i0 + 1, j1 - j0 + 1)
    img = Image.fromarray(rgb.astype(np.uint8)).resize((round((j1 - j0 + 1) * scale), round((i1 - i0 + 1) * scale)),
                                                       Image.BILINEAR)
    d = ImageDraw.Draw(img)

    def P(x, z):
        return ((x - world.ox) / world.sp - j0) * scale, ((z - world.oz) / world.sp - i0) * scale

    rows = {r["id"]: r for r in a["rows"]}
    bad = {p["id"] for p in a["problems"]}
    for t in a["marks"]:
        x, y = P(t["x"], t["z"])
        rr = max(t["r"] / world.sp * scale, 2)
        if t["cls"] == "place":
            d.ellipse([x - rr, y - rr, x + rr, y + rr], outline=(255, 255, 255), width=2)
        elif t["cls"] == "roadside":
            d.rectangle([x - 1, y - 1, x + 1, y + 1], fill=(255, 240, 120))
        else:
            r = rows.get(t["id"])
            col = (160, 160, 160) if r is None else ((220, 50, 40) if r["weak"] else
                                                     (240, 190, 40) if r["score"] < 8 else (60, 200, 80))
            d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=col, outline=(0, 0, 0))
            if t["id"] in bad:
                d.ellipse([x - rr - 3, y - rr - 3, x + rr + 3, y + rr + 3], outline=(255, 0, 255), width=2)
    for g in a["gaps"][:12]:
        x, y = P(g["x"], g["z"])
        d.text((x - 4, y - 6), str(g["rank"]), fill=(255, 255, 255))
        for s in g["sites"]:
            sx, sy = P(s["x"], s["z"])
            d.line([sx - 5, sy, sx + 5, sy], fill=(255, 255, 255), width=2)
            d.line([sx, sy - 5, sx, sy + 5], fill=(255, 255, 255), width=2)
    legend = Image.new("RGB", (max(img.width, 640), img.height + 64), (20, 20, 24))
    legend.paste(img, (0, 64))
    img = legend
    d = ImageDraw.Draw(img)
    d.text((6, 4), "%s: magenta = land > %d m from any place/POI/roadside mark; numbers = gaps by size; "
                   "+ = suggested sites" % (a["region"], a["stats"]["gap_m"]), fill=(240, 235, 220))
    d.text((6, 22), "POIs: red = weak (score <= %d), amber = some, green = strong (>= 8); ring = placement "
                    "problem" % WEAK_SCORE, fill=(240, 235, 220))
    d.text((6, 40), "white ring = settlement pad; yellow dot = signpost/milestone; tan = road", fill=(240, 235, 220))
    img.quantize(colors=96).save(path, optimize=True)


def _fmt_bool(b) -> str:
    return "yes" if b else ""


def write_md(a: dict, path: str, png: str, probe_file: str) -> None:
    s = a["stats"]
    L = []
    title = a["region"].capitalize()
    L.append("# World life audit: %s\n" % title)
    L.append("Made by `python3 tools/world/region_audit.py %s` from the installed world (%s) and the "
             "content pack; the POI measurements are `%s` (tools_gd/poi_probe.gd, headless). "
             "docs/WORLD_LIFE.md says how to read and use it.\n" % (a["region"], a.get("built_at", ""), probe_file))
    L.append("![map](%s)\n" % os.path.basename(png))
    L.append("## Summary\n")
    L.append("| | |\n|---|---|")
    L.append("| land a body walks (dry, no steeper than %.0f deg, %.0f m in from the map's edge) | %.1f km2 |"
             % (WILD_DEG, EDGE_M, s["land_km2"]))
    L.append("| points of interest | %d (%.1f per km2; %d not yet in the built world) |" % (s["pois"], s["pois_per_km2"], s["unbuilt"]))
    L.append("| land more than %d m from any place, POI or roadside mark | %.2f km2 (%.0f%%); more than %d m: %.0f%% |"
             % (s["gap_m"], s["far_km2"], 100 * s["far_share"], 2 * s["gap_m"], 100 * s["far2_share"]))
    L.append("| share of land further than 100 / 150 / 200 / 300 / 400 m from anything | %s |"
             % " / ".join("%.0f%%" % (100 * s["share_by_m"][k]) for k in ("100", "150", "200", "300", "400")))
    L.append("| largest empty stretch | %.2f km2 |" % s["largest_gap_km2"])
    L.append("| weak POIs (score <= %d) | %d, and %d wayside finds (small by design) |" % (WEAK_SCORE, s["weak"], s["weak_wayside"]))
    L.append("| strong POIs (score >= 8) | %d |" % s["strong"])
    L.append("| placement problems | %d, at %d POIs |" % (s["problems"], s["problem_pois"]))
    L.append("")
    L.append("## (a) Empty land, largest first\n")
    L.append("A stretch is land of the region more than %d m from the edge of every place's, POI's and "
             "roadside mark's pad. `furthest` is how far its middle is from anything. Sites are gentle "
             "ground (<= %d deg) in it, as far from everything as it allows, nearer a road where one is "
             "near.\n" % (s["gap_m"], SITE_SLOPE_DEG))
    L.append("| # | middle (x, z) | km2 | extent m | furthest m | slope mean/p75 | height | province (biome) | road | sites (x, z, slope, road m) |")
    L.append("|---|---|---|---|---|---|---|---|---|---|")
    for g in a["gaps"][:25]:
        road = ("through it, %d m" % g["road_inside_m"]) if g["road_inside_m"] else ("nearest %d m" % g["road_nearest_m"])
        where = "%s (%s)" % (g["province"], g["biome"]) + (", %s" % g["forest"] if g["forest"] else "")
        st = "; ".join("(%d, %d) %.0f deg %d m" % (x["x"], x["z"], x["slope"], x["road_m"]) for x in g["sites"])
        L.append("| %d | (%d, %d) | %.2f | %d x %d | %d | %.0f / %.0f | %d | %s | %s | %s |"
                 % (g["rank"], g["x"], g["z"], g["area_km2"], g["extent_m"][0], g["extent_m"][1], g["furthest_m"],
                    g["slope_mean"], g["slope_p75"], g["height_m"], where, road, st))
    if len(a["gaps"]) > 25:
        L.append("\n%d smaller stretches not listed.\n" % (len(a["gaps"]) - 25))
    L.append("\n## (b) Points of interest, weakest first\n")
    L.append("Impact score, points for each: " + "; ".join("**%s** %s" % (k, v) for k, v in IMPACT)
             + ". **Weak** is %d or under; **small** is a reach under %d m. `reach` is metres from the middle to "
               "the furthest piece; `things` are interactables in the dressing (hearthstones, touches, containers); "
               "foes are the encounter's standing count; loot counts an encounter's `lies`, a find and a container.\n"
             % (WEAK_SCORE, SMALL_REACH_M))
    L.append("| score | POI | kind | reach / pad m | pieces | draws | tris k | things | foes | loot | NPCs | quest | enc | interior | hearth | landmark | flags |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in sorted(a["rows"], key=lambda r: (r["score"], r["reach"])):
        flags = []
        if r["weak"]:
            flags.append("WEAK")
        if r["small"]:
            flags.append("small")
        if r["wayside"]:
            flags.append("wayside")
        if not r["built"]:
            flags.append("unbuilt")
        if not r["probed"]:
            flags.append("not probed")
        L.append("| %d | %s `%s` | %s | %.0f / %.0f | %d | %d | %.0f | %d | %d | %d | %d | %s | %s | %s | %s | %s | %s |"
                 % (r["score"], r["name"], r["id"].split("/")[-1], r["kind"], r["reach"], r["pad_m"], r["pieces"],
                    r["draws"], r["primitives"] / 1000.0, r["things"], r["foes"], r["loot"], r["npcs"],
                    _fmt_bool(r["quest"]), _fmt_bool(r["encounter"]), _fmt_bool(r["interior"]), _fmt_bool(r["hearth"]),
                    _fmt_bool(r["landmark"]), " ".join(flags)))
    kinds = Counter(r["kind"] for r in a["rows"] if r["weak"] and not r["wayside"])
    if kinds:
        L.append("\nWeak POIs by kind (not wayside): " + ", ".join("%s %d" % kv for kv in kinds.most_common()) + ".\n")
    L.append("\n## (c) Placement problems\n")
    L.append("`seat:*` are the seat audit's findings over the POI's own pieces (tools_gd/seat_audit.gd: floating "
             "over the ground, buried, sunk, standing in a road's carriageway, overlapping another piece, a lamp "
             "or light hung from nothing; headless, so multimesh rows are not looked at). `past_pad`: pieces stand "
             "beyond the flattened pad, on the skirt or raw ground. `steep_skirt`: the pad's skirt (from its level "
             "core to its reach) falls at more than %.0f deg along some line: a cut or an embankment. `steep_site`: "
             "a POI not yet built stands on ground sloping more than %.0f deg on average under its pad. "
             "`overlap_pad`: two pads overlap. `road_through`: a road crosses the level core of a place that is "
             "not road furniture. `in_water`: its middle is in water.\n" % (SKIRT_DEG, SITE_STEEP_DEG))
    by = Counter(p["what"] for p in a["problems"])
    L.append("Counts: " + (", ".join("%s %d" % kv for kv in by.most_common()) or "none") + ".\n")
    L.append("| POI | problem | n | detail |")
    L.append("|---|---|---|---|")
    for p in sorted(a["problems"], key=lambda p: (p["what"], p["id"])):
        L.append("| `%s` | %s | %d | %s |" % (p["id"].split("/")[-1], p["what"], p["n"], p["detail"].replace("|", "/")))
    open(path, "w", encoding="utf-8").write("\n".join(L) + "\n")


def run_probe(region: str, out_json: str, extra: list | None = None) -> None:
    """./run.sh poi-probe for a region (Godot, headless). Run under ~/bin/heavy."""
    cmd = [os.path.join(REPO, "run.sh"), "poi-probe", "--out=%s" % os.path.abspath(out_json)]
    cmd += (["--region=%s" % region] if region else []) + list(extra or [])
    print("[audit] " + " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)


def load_probe(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    return {p["id"]: p for p in json.load(open(path, encoding="utf-8")).get("pois", [])}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("region", help="a region's short name, or 'all'")
    ap.add_argument("--probe", action="store_true", help="raise every POI in Godot first (./run.sh poi-probe)")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--gap", type=float, default=GAP_M)
    args = ap.parse_args(argv)
    regions = list(REGIONS) if args.region == "all" else [args.region]
    os.makedirs(args.out, exist_ok=True)
    world = World()
    content = load_content()
    atlas = ATLAS.load()
    marks = things(world, content)
    if args.probe and len(regions) > 1:
        # one world stood up for every region's places, then kept a file a region
        whole = os.path.join(args.out, "probe_all.json")
        run_probe("", whole)
        data = json.load(open(whole, encoding="utf-8"))
        region_of = {d["id"]: CONTENT.region_of(d) for d in content["pois"]}
        for region in regions:
            mine = dict(data, region="core:region/%s" % region,
                        pois=[p for p in data["pois"] if region_of.get(p["id"]) == region])
            with open(os.path.join(args.out, "probe_%s.json" % region), "w", encoding="utf-8") as f:
                json.dump(mine, f, indent=1)
        os.remove(whole)
    for region in regions:
        probe_path = os.path.join(args.out, "probe_%s.json" % region)
        if args.probe and len(regions) == 1:
            run_probe(region, probe_path)
        probe = load_probe(probe_path)
        a = audit(region, world, content, atlas, probe, args.gap, marks)
        a["built_at"] = world.man.get("built_at", "")
        md = os.path.join(args.out, "audit_%s.md" % region)
        png = os.path.join(args.out, "audit_%s.png" % region)
        write_png(a, world, png)
        write_md(a, md, png, os.path.relpath(probe_path, REPO))
        s = a["stats"]
        print("%-12s land %.1f km2, %d POIs, far %.0f%%, largest gap %.2f km2, weak %d (+%d wayside), "
              "strong %d, problems %d at %d POIs -> %s"
              % (region, s["land_km2"], s["pois"], 100 * s["far_share"], s["largest_gap_km2"], s["weak"],
                 s["weak_wayside"], s["strong"], s["problems"], s["problem_pois"], os.path.relpath(md, REPO)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
