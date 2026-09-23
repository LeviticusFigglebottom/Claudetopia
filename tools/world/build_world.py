#!/usr/bin/env python3
"""Wickmere world builder.

Reads the atlas (tools/world/atlas/atlas.json, the geography as somebody drew it: see
tools/world/atlas/SCHEMA.md) and the world, region, place and POI definitions from the core
content pack, and writes every file listed in docs/CONTRACTS.md section 6 into
game/world/generated/.

    tools/world/build_world.py                 # full 4096 build
    tools/world/build_world.py --size 1024     # fast test build
    tools/world/build_world.py --only heights  # heights/water/roads only
    tools/world/build_world.py --seed 99 --out /tmp/w
    tools/world/build_world.py --atlas other.json
    tools/world/build_world.py --recipe cover  # see RECIPES

Stages: the atlas checked -> province membership -> the provinces' land, ranges, peaks,
valleys, the coast and the lakes, drainage -> place pads -> the atlas's rivers -> its roads ->
landforms -> water, moisture -> texture control maps and colour -> POIs -> cell scatter.
Where things are is the atlas's; the seed in world.json (or --seed) only breaks up the detail.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
import zlib

import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from worldgen import atlas as ATLAS
from worldgen import cells as CELLS
from worldgen import encounters as ENC
from worldgen import fields as FL
from worldgen import geography as GEO
from worldgen import heights as HM
from worldgen import hedges as HG
from worldgen import hydro as HY
from worldgen import landforms as LF
from worldgen import output as OUT
from worldgen import pads as PD
from worldgen import roads as RD
from worldgen import roadside as RS
from worldgen import stones as ST
from worldgen import surface as SF
from worldgen.grid import Grid, sample_bilinear
from worldgen.noise import NoiseBank
from worldgen.regions import dithered_owner, load_places, load_regions

import sightlines as SIGHT  # noqa: E402  tools/sightlines.py: the game's own sight model

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACK = os.path.join(REPO, "game", "content", "packs", "core")
DEFAULT_OUT = os.path.join(REPO, "game", "world", "generated")
OPEN_WATER = 255

## Parts of the world that are built and measured but not yet looked at in the game, so no
## default build makes them: each is turned on with `--recipe <name>` (`./run.sh world
## --recipe cover`) and recorded in the manifest. PROGRESS.md, "The shape of the land", has what
## each measured. (The landforms were one; they are the atlas's now, province by province.)
RECIPES = {
    # cover that differs between regions in structure: scatter_rules.json's `cover` block,
    # the per-landform field patterns, the fell wall, the waterside and ruin lines, roadside
    # frontage by region, and the Briarwold's holloways (roads.ROAD_SINK_M)
    "cover": "reeds at the water, willow lines, marram on the dune crests, boulder fields, ash "
             "in the sunken streets and wall stubs on their lips, intakes and fell walls",
}
## The recipes a build makes when it is not told otherwise; `--recipe` adds one, `--without`
## takes one away.
DEFAULT_RECIPES: tuple = ()


class Timer:
    def __init__(self, verbose=True):
        self.t0 = time.time()
        self.last = self.t0
        self.stages: list = []
        self.verbose = verbose

    def mark(self, label: str) -> None:
        now = time.time()
        self.stages.append((label, now - self.last))
        if self.verbose:
            print("  %-22s %6.1fs" % (label, now - self.last), flush=True)
        self.last = now

    def total(self) -> float:
        return time.time() - self.t0


def load_world_def(pack_dir: str) -> dict:
    path = os.path.join(pack_dir, "world", "world.json")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data[0] if isinstance(data, list) else data


def load_poi_registry(pack_dir: str) -> list:
    """The optional POI registry (core:poi/*). Absent in early passes; places still work."""
    path = os.path.join(pack_dir, "pois", "pois.json")
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, list) else [data]


def pad_targets_for(places: list, pois: list) -> list:
    """Every named place, plus every POI in the registry: everything that gets a pad."""
    out = [dict(p) for p in places]
    known = {tuple(p["position"]) for p in places}
    for p in pois:
        if tuple(p.get("position", [])) in known:
            continue
        out.append({"id": p["id"], "kind": p.get("kind", "poi"), "position": p["position"],
                    "region": p.get("region", "")})
    return out


def sightline_segments(pois: list, pad_targets: list) -> list:
    """[(x0, z0, x1, z1)] for every authored `visible_from` line whose two ends both have pads."""
    where = {str(p["id"]): (float(p["position"][0]), float(p["position"][1])) for p in pad_targets}
    out = []
    for p in pois:
        target = where.get(str(p.get("id", "")))
        for vantage in p.get("visible_from", []):
            v = where.get(str(vantage))
            if target is not None and v is not None:
                out.append((v[0], v[1], target[0], target[1]))
    return out


def sightline_claims(pois: list, pad_targets: list) -> list:
    """[(vantage_xz, target_xz, target_kind, vantage_pad_m, target_pad_m)] for every authored
    `visible_from` line whose two ends both have pads (geography.honour_sightlines)."""
    by_id = {str(p["id"]): p for p in pad_targets}
    out = []
    for p in pois:
        target = by_id.get(str(p.get("id", "")))
        if target is None:
            continue
        for vantage in p.get("visible_from", []):
            v = by_id.get(str(vantage))
            if v is None:
                continue
            out.append(((float(v["position"][0]), float(v["position"][1])),
                        (float(target["position"][0]), float(target["position"][1])),
                        str(p.get("kind", "")), RD.pad_radius(v), RD.pad_radius(target)))
    return out


def pad_fingerprint(pad_targets: list, fixed_levels: dict | None = None) -> str:
    """A checksum of where every pad is, how big, at what level if the atlas says, and what for."""
    fixed = fixed_levels or {}
    rows = sorted((str(p["id"]), str(p.get("kind", "")), round(float(p["position"][0]), 2),
                   round(float(p["position"][1]), 2), round(RD.pad_radius(p), 2))
                  + ((round(float(fixed[p["id"]]), 2),) if p["id"] in fixed else ())
                  for p in pad_targets)
    return "%08x" % zlib.crc32(json.dumps(rows).encode("utf-8"))


def refuse_stale_pads(out_dir: str, fingerprint: str) -> None:
    """A staged build may only reuse heights.r32 if the pads in it are the pads it would lay.

    `--only textures` and `--only cells` reuse the heightmap and never write it back, so when a
    place or a POI has moved since the heights were built, the terrain on disk keeps a pad at
    the old position and has none at the new one, while the scatter, the POI heights and the
    texture rules are computed against a pad re-flattened in memory where the thing now stands.
    That is a pad under a POI's original position, with the POI standing on unflattened ground
    and a clearing in the scatter where there is no platform. The answer is a heights build.
    """
    path = os.path.join(out_dir, "world_manifest.json")
    had = ""
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            had = str(json.load(f).get("pad_fingerprint", ""))
    if had != fingerprint:
        raise SystemExit("[world] heights.r32 was flattened for other pads (%s, now %s): a place "
                         "or POI has moved since. Rebuild the heights (build_world.py, or "
                         "--only heights) before a staged build." % (had or "unrecorded", fingerprint))


def scene_for(name: str, repo: str) -> str:
    """res:// path of a POI scene, but only if the scene actually exists."""
    rel = "world/pois/%s.tscn" % name
    return "res://" + rel if os.path.exists(os.path.join(repo, "game", rel)) else ""


def landmark_index(repo: str) -> dict:
    """place id -> what the forge built to stand there.

    A landmark model names its own place in its meta file, so nothing here has to guess from
    the directory name. An imported .glb loads as a PackedScene, which is all the streamer
    needs; the sibling *_col.glb is the collision the forge authored for it, and a landmark
    you can walk through is worse than a landmark that is not there.
    """
    out: dict = {}
    base = os.path.join(repo, "game", "assets", "models", "landmarks")
    if not os.path.isdir(base):
        return out
    for name in sorted(os.listdir(base)):
        meta_path = os.path.join(base, name, name + ".meta.json")
        if not os.path.exists(meta_path):
            continue
        with open(meta_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
        place = str(meta.get("place", ""))
        if not place:
            continue
        entry = {
            "scene": "res://assets/models/landmarks/%s/%s.glb" % (name, name),
            "height_m": float(meta.get("bounds", {}).get("height", 0.0)),
            "radius_m": float(meta.get("bounds", {}).get("radius", 0.0)),
        }
        col = str(meta.get("collision", ""))
        if col and os.path.exists(os.path.join(base, name, col)):
            entry["collision"] = "res://assets/models/landmarks/%s/%s" % (name, col)
        out.setdefault(place, []).append(entry)
    return out


## Which way a landmark looks. A forty-metre bell facing due north because that is the default
## is a tell, so every one of these is a bearing something in the world gives it:
##   "water"        out over the nearest open water (a lighthouse faces the sea)
##   ("place", id)  at another place (the colossi face the Cantor's Seat they sang to)
##   "downhill"     the way the ground falls, which for a fallen thing is the way it fell
## A `yaw` in places.json overrides all of it.
## Some landmarks are not one thing. The Sunken Choir is twelve headless colossi, so it is an
## avenue of them flanking the way to the Cantor's Seat rather than a single figure standing on
## the spot. `count` figures, `rows` of them either side of the facing line, `spacing_m` apart
## along it and `width_m` across it.
LANDMARK_SETS = {
    "core:place/sunken_choir": {"count": 11, "rows": 2, "spacing_m": 52.0, "width_m": 78.0},
}

LANDMARK_FACING = {
    "core:place/the_lamp": "water",
    "core:place/sayers_spire": ("place", "core:place/tollmere"),
    "core:place/sunken_choir": ("place", "core:place/cantors_seat"),
    "core:place/fallen_hand": "downhill",
    "core:place/cracked_toll": "downhill",
}


def landmark_set(place: dict, primary: dict, models: list, H, grid) -> list:
    """The rest of a landmark that is a set, as extra scene entries.

    The primary entry already stands on the place's own position; these are the others,
    ranked away from it along the bearing it faces, alternating between the variants the
    forge built so an avenue of twelve is not one figure printed twelve times.
    """
    spec = LANDMARK_SETS.get(place["id"])
    if not spec:
        return []
    count = int(spec.get("count", 1))
    if count <= 1:
        return []
    rows = max(int(spec.get("rows", 1)), 1)
    spacing = float(spec.get("spacing_m", 40.0))
    width = float(spec.get("width_m", 0.0))
    yaw = float(primary.get("yaw", 0.0))
    fx, fz = math.sin(math.radians(yaw)), math.cos(math.radians(yaw))
    px, pz = -fz, fx
    x0, z0 = float(place["position"][0]), float(place["position"][1])
    per_row = max(count // rows, 1)
    out = []
    for k in range(count):
        row = k % rows
        # the avenue runs away from the place toward what it faces, so the figure standing on
        # the place's own position is the head of it and not one in the middle of the road
        along = (k // rows) + 1.0
        across = (row - (rows - 1) * 0.5) * width
        x = x0 + fx * along * spacing + px * across
        z = z0 + fz * along * spacing + pz * across
        if abs(x - x0) < 1e-6 and abs(z - z0) < 1e-6:
            continue                                    # the primary already stands here
        y = float(sample_bilinear(H, grid, np.array([x]), np.array([z]))[0])
        model = models[k % len(models)]
        item = {"scene": model["scene"], "pos": [round(x, 2), round(y, 2), round(z, 2)],
                # each figure turns a little to face the line it flanks
                "yaw": round(yaw + (12.0 if across > 0 else -12.0), 1),
                "props": {"place_id": place["id"]}}
        if "collision" in model:
            item["collision"] = model["collision"]
        out.append(item)
    return out


def landmark_yaw(place: dict, facing, H, water_d, grid, places_by_id: dict) -> float:
    """Degrees about +Y, measured the way the streamer applies it (rotation.y)."""
    if "yaw" in place:
        return float(place["yaw"])
    x, z = float(place["position"][0]), float(place["position"][1])
    vx = vz = 0.0
    if isinstance(facing, tuple) and facing[0] == "place":
        other = places_by_id.get(facing[1])
        if other is not None:
            vx = float(other["position"][0]) - x
            vz = float(other["position"][1]) - z
    elif facing == "water":
        j, i = grid.to_tex(np.array([x]), np.array([z]))
        j = int(min(max(int(j[0]), 1), grid.n - 2))
        i = int(min(max(int(i[0]), 1), grid.n - 2))
        vx = -float(water_d[i, j + 1] - water_d[i, j - 1])
        vz = -float(water_d[i + 1, j] - water_d[i - 1, j])
    if abs(vx) < 1e-6 and abs(vz) < 1e-6:
        j, i = grid.to_tex(np.array([x]), np.array([z]))
        j = int(min(max(int(j[0]), 1), grid.n - 2))
        i = int(min(max(int(i[0]), 1), grid.n - 2))
        vx = -float(H[i, j + 1] - H[i, j - 1])
        vz = -float(H[i + 1, j] - H[i - 1, j])
    if abs(vx) < 1e-9 and abs(vz) < 1e-9:
        # zlib.crc32, not hash(): Python salts string hashing per process, and a world
        # that faces its landmarks differently on every build is not deterministic.
        return float(zlib.crc32(str(place.get("id", "")).encode("utf-8")) % 360)
    return float(round(math.degrees(math.atan2(vx, vz)), 1))


def build(args) -> dict:
    t = Timer()
    # `--pack` builds against another copy of the core pack (a cartographer's places and POIs
    # before they are merged); everything else about the build is the same
    PACK = getattr(args, "pack", None) or globals()["PACK"]
    wdef = load_world_def(PACK)
    seed = int(args.seed if args.seed is not None else wdef.get("seed", 1))
    size_m = float(wdef.get("size_m", 8192))
    spacing_default = float(wdef.get("spacing_m", 2))
    n = int(args.size) if args.size else int(round(size_m / spacing_default))
    cell_m = float(wdef.get("cell_size_m", 256))
    grid = Grid(size_m, n, cell_m)
    nc = min(n, 2048)
    grid_c = grid.with_n(nc)
    bank = NoiseBank(seed, grid)
    content_regions = load_regions(os.path.join(PACK, "regions", "regions.json"))
    places = load_places(os.path.join(PACK, "places", "places.json"))
    pois = load_poi_registry(PACK)
    atlas_path = getattr(args, "atlas", None) or ATLAS.ATLAS_PATH
    atlas = ATLAS.load(atlas_path)
    errors, warnings = ATLAS.check(atlas, PACK)
    for w in warnings:
        print("[world] atlas: " + w, flush=True)
    if errors:
        raise SystemExit("[world] the atlas %s has errors (python3 tools/world/atlas/check_atlas.py):\n  %s"
                         % (atlas_path, "\n  ".join(errors)))
    # one RegionDef per province: `regions` from here on is the provinces
    regions = GEO.provinces_from_atlas(atlas, content_regions)
    out_dir = args.out or DEFAULT_OUT
    os.makedirs(out_dir, exist_ok=True)
    asked = set(getattr(args, "recipe", None) or []) | set(getattr(args, "without", None) or [])
    recipes = sorted((set(DEFAULT_RECIPES) | set(getattr(args, "recipe", None) or []))
                     - set(getattr(args, "without", None) or []))
    unknown = [r for r in sorted(asked) if r not in RECIPES]
    if unknown:
        raise SystemExit("[world] no such recipe: %s (there are: %s)" % (", ".join(unknown), ", ".join(sorted(RECIPES))))
    cover = "cover" in recipes
    print("[world] seed %d, %d m at %.2f m/texel (%d^2), atlas %s: %d provinces in %d regions, "
          "%d places, %d pois%s"
          % (seed, size_m, grid.spacing, n, atlas.get("name", os.path.basename(atlas_path)), len(regions),
             len({r.id for r in regions}), len(places), len(pois),
             ", recipes: " + ", ".join(recipes) if recipes else ""), flush=True)

    # every place and POI by id: the ends of the roads and the causeways
    things = {p["id"]: p for p in list(places) + list(pois)}
    rf = GEO.province_field(grid_c, bank, atlas, regions)
    waters_c = GEO.waters(grid_c, atlas, things)
    waters = waters_c if n == nc else GEO.waters(grid, atlas, things)
    t.mark("regions")

    pad_targets = pad_targets_for(places, pois)
    # the atlas's own pads: a level, and a size where it gives one
    fixed_levels = {pad["place"]: float(pad["level_m"]) for pad in atlas.get("pads", [])}
    for pad in atlas.get("pads", []):
        for p in pad_targets:
            if p["id"] == pad["place"] and pad.get("radius_m"):
                p["pad_radius_m"] = float(pad["radius_m"])
    pads_crc = pad_fingerprint(pad_targets, fixed_levels)

    # Minimum pad levels: settlements sit above standing water. A delta's table and the sea's
    # edge are the two that bite (Isseva is a stilt-town, not an underwater one).
    marsh_ids = {r.index for r in regions if r.shape == "delta"}
    marsh_tab = HY.marsh_table(grid, bank, regions, rf)
    owner_full = rf.owner_at(n)
    min_levels: dict = {}
    dry_kinds = ("city", "town", "village", "hamlet", "fort", "camp", "lodge", "ruin_village")
    for p in pad_targets:
        px, pz = float(p["position"][0]), float(p["position"][1])
        j, i = grid.to_tex(np.array([px]), np.array([pz]))
        j, i = grid.clamp_index(j, i)
        floor_m = 0.8 if p.get("kind") in dry_kinds else 0.2
        if int(owner_full[int(i[0]), int(j[0])]) in marsh_ids:
            floor_m = max(floor_m, float(marsh_tab[int(i[0]), int(j[0])]) + 0.75)
        min_levels[p["id"]] = floor_m
    del owner_full

    heights_path = os.path.join(out_dir, "heights.r32")
    reuse = args.only in ("textures", "cells") and os.path.exists(heights_path)
    if reuse:
        refuse_stale_pads(out_dir, pads_crc)
        H = np.fromfile(heights_path, dtype="<f4").reshape(n, n).copy()
        print("[world] reusing %s" % heights_path, flush=True)
        rivers = []
        roads_list = []
        H, pad_mask, pad_levels = RD.apply_pads(grid, H.copy(), pad_targets, min_levels, fixed_levels)
        river_d = np.full((n, n), 1e6, dtype=np.float32)
        river_surf = np.zeros((n, n), dtype=np.float32)
        river_w = np.zeros((n, n), dtype=np.float32)
        road_d = np.full((n, n), 1e6, dtype=np.float32)
        road_w = np.zeros((n, n), dtype=np.float32)
        # rivers and roads are reloaded from their splines only to rebuild the distance
        # fields the texture rules read; their widths and surfaces are interpolated, which is
        # accurate enough for that and never written back.
        for path, target in (("rivers.json", "rivers"), ("roads.json", "roads")):
            fp = os.path.join(out_dir, path)
            if os.path.exists(fp):
                with open(fp, "r", encoding="utf-8") as f:
                    raw = json.load(f)
                if target == "rivers":
                    rivers = [HY.River(id=r["id"], points=np.array(r["points"], dtype=np.float64),
                                       width=np.linspace(r.get("width_from_m", r["width_m"]),
                                                         r.get("width_to_m", r["width_m"]), len(r["points"])).astype(np.float32),
                                       surface=np.linspace(r.get("surface_from_m", 0.0), r.get("surface_to_m", 0.0),
                                                           len(r["points"])).astype(np.float32)) for r in raw]
                else:
                    roads_list = [RD.Road(id=r["id"], points=np.array(r["points"], dtype=np.float64),
                                          width=float(r["width_m"]),
                                          elevation=np.zeros(len(r["points"]), dtype=np.float32)) for r in raw]
        if rivers:
            _, river_d, river_surf, river_w = HY.carve_rivers(grid, H.copy(), rivers, bank)
        if roads_list:
            _, road_d, road_w = RD.carve_roads(grid, H.copy(), roads_list)
        sea = ~GEO.land_mask(grid, atlas)
        t.mark("reload")
    else:
        # the landforms come back apart from the land: the rivers and the roads are laid and
        # carved on the land without them, and they are laid on after
        H, lf_delta, extras = HM.compose_heights(
            grid, grid_c, bank, atlas, regions, rf, waters_c, waters, places, things,
            keep_discs=[(float(p["position"][0]), float(p["position"][1]), RD.pad_radius(p)) for p in pad_targets],
            keep_lines=sightline_segments(pois, pad_targets), apart=True)
        sea = extras["sea"]
        del extras
        t.mark("heights")
        H, pad_mask, pad_levels = RD.apply_pads(grid, H, pad_targets, min_levels, fixed_levels)
        t.mark("pads")
        # The authored sightlines: where the land stands into one by no more than a saddle's
        # depth, it is cut down under it, as a pad is flattened under a place. A line with a
        # mountain in the way is left refused, and said so: it is the atlas's or the content's.
        notched = GEO.honour_sightlines(grid, H, sightline_claims(pois, pad_targets), SIGHT.constants())
        cut = [row for row in notched if row[3]]
        left = [row for row in notched if not row[3]]
        print("[world] sightlines: %d cut under their lines (deepest %.1f m), %d stood into by more than "
              "%.0f m and left" % (len(cut), max([row[2] for row in cut], default=0.0), len(left),
                                   GEO.NOTCH_MAX_M), flush=True)
        t.mark("sightlines")
        # the atlas's rivers, in the valleys they have cut
        rivers = HY.atlas_rivers(grid, H, atlas, waters)
        still = sea | waters.in_lake(H)
        H_still = H
        H = HY.carve_river_valleys(grid, H.copy(), rivers)
        H, river_d, river_surf, river_w = HY.carve_rivers(grid, H, rivers, bank)
        # a river's banks are raised to its water on land; where its mouth runs on into a lake or
        # the sea they would stand up out of the water, so there the bed is only ever deepened
        H = np.where(still, np.minimum(H, H_still), H).astype(np.float32)
        del still, H_still
        # the land as the rivers left it, which nothing laid afterwards may dam
        H_river = H.copy()
        t.mark("rivers")
        # a first water mask so roads know what to avoid, then the roads themselves
        in_lake = waters.in_lake(H)
        rough_water = (sea | in_lake | (river_d <= river_w * 0.5 + 1.0)).astype(np.uint8)
        # A road's profile is laid over water's surface, not along its bed: where it crosses a
        # river it is graded across the top, and `keep_channels` then cuts the ford. (A lake's
        # bed may be below the sea in the middle, so the lakes are tested last.)
        road_floor = np.where(river_d <= river_w * 0.5 + 2.0, river_surf + 0.6, -1.0e4)
        road_floor = np.where(sea, HM.SEA_LEVEL + 0.6, road_floor)
        road_floor = np.where(in_lake, waters.level + 0.6, road_floor).astype(np.float32)
        del in_lake
        # and how far below the land a road would rather run, where that is the country's way
        # (the Briarwold's holloways, which are part of its cover)
        road_sink = None
        for r in (regions if cover else []):
            depth = float(RD.ROAD_SINK_M.get(r.shape, 0.0))
            if depth > 0.0:
                w = depth * rf.weight_at(r.index, n)
                road_sink = w if road_sink is None else road_sink + w
        # and where it may cut but not build up: nothing rises into an authored sightline
        no_fill = LF.line_mask(grid, sightline_segments(pois, pad_targets), LF.LINE_CORRIDOR_M)
        roads_list = RD.plan_roads(grid, H, atlas.get("roads", []), things, rough_water, pad_levels,
                                   floor=road_floor, sink=road_sink, no_fill=no_fill, lake=waters)
        del road_floor, road_sink
        # and through each settlement, so a town is somewhere a road passes rather than three
        # spokes meeting at a point
        roads_list = RD.add_streets(roads_list, pad_targets, pad_levels)
        H, road_d, road_w = RD.carve_roads(grid, H, roads_list, no_fill=no_fill)
        del no_fill
        # pads again: roads must not tilt a settlement platform
        H, pad_mask, pad_levels = RD.apply_pads(grid, H, pad_targets, min_levels, fixed_levels)
        # and the rivers win over both: a pad or a road laid across a channel is cut through
        H = HY.keep_channels(grid, H, H_river, river_d, river_w, river_surf, road_d, road_w)
        t.mark("roads")
        if lf_delta is not None:
            # Each province's landforms go on last, and not across a road: a road is graded and
            # carved against the land it was routed over, and the landform only comes back
            # past its carve (landforms.road_clear), so a road climbs a scar through a break in
            # it. Then the pads and the channels once more, as after the roads.
            H = (H + lf_delta * LF.road_clear(road_d, road_w)).astype(np.float32)
            del lf_delta
            H, pad_mask, pad_levels = RD.apply_pads(grid, H, pad_targets, min_levels, fixed_levels)
            H = HY.keep_channels(grid, H, H_river, river_d, river_w, river_surf, road_d, road_w)
            t.mark("landforms")
        del H_river

    owner = dithered_owner(rf, n, bank)
    # The sea is the ground under its level outside the coast, and within 150 m of the shore
    # inside it: a low texel on the strand is wet sand, not a dry pit beside the water. Further
    # inland, ground under the sea's level is a dry hollow unless a lake says otherwise; and a
    # pad a place has raised out of the sea (the Hushline's, 0.2 m) stands dry.
    near_shore = GEO.coarse_distance(grid, sea) < 150.0
    sea_water = (H < HM.SEA_LEVEL) & (sea | near_shore)
    del near_shore
    water = HY.water_maps(grid, H, waters, sea_water, rivers, river_d, river_surf, river_w, owner, regions,
                          marsh_tab)
    moist = HY.moisture(grid, H, water, waters, bank)
    t.mark("water")

    # what the game reads: the content region under each province, and open water
    province_region = np.array([r.region_index for r in regions], dtype=np.uint8)
    region_mask = province_region[owner]
    open_water = (water.mask > 0) & ((waters.sd < 0) | sea_water)
    region_mask[open_water] = OPEN_WATER

    # the enclosed patchwork: one pattern read by the crops, the hedges and the colour map
    field_labels, field_d = FL.field_map(grid, bank, owner, regions,
                                         patterns=FL.PATTERNS if cover else FL.ONE_PATTERN)
    # how far to any water at all -- river, mere or sea -- for the trees that follow it
    water_d = (ndimage.distance_transform_edt(water.mask == 0) * grid.spacing).astype(np.float32)
    # how far across a settlement's platform, so the verge can be planted and the green left
    pad_t = PD.pad_distance(grid, pad_targets)
    t.mark("fields")

    ctx = SF.SurfaceContext(grid, bank, H, regions, owner, water.mask, water.level, moist,
                            river_d, road_d, road_w, pad_mask, waters, places, rf=rf,
                            field_labels=field_labels, field_d=field_d, sea=sea_water)
    base = overlay = blend = None
    colour = None
    if args.only in (None, "all", "heights", "textures", "cells"):
        pass
    if args.only in (None, "all", "textures") or args.only == "cells":
        base, overlay, blend = SF.control_maps(ctx)
        t.mark("textures")
        colour = SF.colour_map(ctx, rf)
        t.mark("colour")

    # --- POIs -------------------------------------------------------------------------
    # A place with nothing standing on it is a flattened pad and a name. Where a hand-built
    # scene exists it wins; otherwise the forge's landmark model for that place stands there,
    # with the collision it was built with and a bearing the world gives it.
    landmarks = landmark_index(REPO)
    places_by_id = {pl["id"]: pl for pl in pad_targets}
    poi_out = []
    extra_scenes: list = []
    for p in pad_targets:
        x, z = float(p["position"][0]), float(p["position"][1])
        y = float(sample_bilinear(H, grid, np.array([x]), np.array([z]))[0])
        short = p["id"].split("/")[-1]
        entry = {"place_id": p["id"], "pos": [round(x, 2), round(y, 2), round(z, 2)],
                 "yaw": 0.0, "radius_flat_m": RD.pad_radius(p)}
        scene = scene_for(short, REPO)
        models = landmarks.get(p["id"], [])
        if scene:
            entry["scene"] = scene
        elif models:
            entry["scene"] = models[0]["scene"]
            if "collision" in models[0]:
                entry["collision"] = models[0]["collision"]
            entry["yaw"] = landmark_yaw(p, LANDMARK_FACING.get(p["id"], "downhill"),
                                        H, water_d, grid, places_by_id)
            extra_scenes.extend(landmark_set(p, entry, models, H, grid))
        poi_out.append(entry)

    # --- cells ------------------------------------------------------------------------
    buckets: dict = {}
    if args.only in (None, "all", "cells"):
        rules = CELLS.load_rules(os.path.join(os.path.dirname(os.path.abspath(__file__)), "scatter_rules.json"),
                                 recipes)
        # where each point stands in the shape of the land, for the rules that grow on crests
        # or lie in hollows (only the `cover` rules ask)
        tpi = CELLS.topographic_position(H, grid.spacing) if cover else None
        sw = CELLS.ScatterWorld(grid, H, owner, moist, water.mask, road_d, road_w, pad_mask,
                                ctx.slope, bank, regions, water_d=water_d, field_d=field_d,
                                pad_t=pad_t, tpi=tpi, forests=GEO.forests(grid, atlas))
        buckets = CELLS.scatter(sw, rules, regions, seed, repo_root=REPO)
        # Standing stones are set, not scattered: a ring at the Moot, pairs flanking a road
        # where it crosses the high ground, and a few alone on skylines. They go into the same
        # buckets, so the streamer draws them in the same MultiMesh as everything else.
        placed = ST.place(grid, H, owner, ctx.slope, water.mask, road_d, pad_mask, regions,
                          pad_targets, roads_list, CELLS.asset_index(REPO), seed)
        stone_count = 0
        for key, by_asset in placed.items():
            for asset, rows in by_asset.items():
                buckets.setdefault(key, {}).setdefault(asset, []).extend(rows)
                stone_count += len(rows)
        t.mark("scatter")
        # The hedgerows, walls and orchard rows. Placed rather than scattered, for the same
        # reason the standing stones are: a hedge is a line somebody planted along a field
        # boundary, and no density per hectare produces a line.
        index = CELLS.asset_index(REPO)
        hedged = HG.place(grid, H, owner, ctx.slope, water.mask, road_d, road_w, pad_mask,
                          field_labels, field_d, regions, index, bank, seed, places=places,
                          fell_wall=cover)
        rows_of_hedge = 0
        for key, by_asset in hedged.items():
            for asset, rows in by_asset.items():
                buckets.setdefault(key, {}).setdefault(asset, []).extend(rows)
                rows_of_hedge += len(rows)
        grown = HG.orchards(grid, H, owner, ctx.slope, water.mask, pad_mask, field_labels,
                            field_d, regions, places, index, seed)
        orchard_trees = 0
        for key, by_asset in grown.items():
            for asset, rows in by_asset.items():
                buckets.setdefault(key, {}).setdefault(asset, []).extend(rows)
                orchard_trees += len(rows)
        # the lines that are the water's and the Builders', not a farmer's: willows along the
        # marsh channels, and the stubs of walls along the lips of Cinderlea's buried streets
        lined = 0
        lines_of = []
        if cover:
            lines_of = [HG.waterside(grid, H, owner, ctx.slope, water.mask, water_d, pad_mask,
                                     road_d, road_w, regions, index, bank, seed),
                        HG.ruin_lines(grid, H, owner, ctx.slope, water.mask, pad_mask, road_d,
                                      road_w, regions, index, bank, seed)]
        for placed_lines in lines_of:
            for key, by_asset in placed_lines.items():
                for asset, rows in by_asset.items():
                    buckets.setdefault(key, {}).setdefault(asset, []).extend(rows)
                    lined += len(rows)
        # and what stands beside the roads: milestones, a signpost where roads meet, and
        # post-and-rail where the carriageway runs past somebody's field
        beside = RS.place(grid, H, owner, ctx.slope, water.mask, pad_mask, field_d, regions,
                          roads_list, places, index, seed, by_region=cover)
        roadside_rows = 0
        for key, by_asset in beside.items():
            for asset, rows in by_asset.items():
                buckets.setdefault(key, {}).setdefault(asset, []).extend(rows)
                roadside_rows += len(rows)
        print("[world] %d hedge pieces, %d orchard trees, %d waterside and ruin, %d roadside"
              % (rows_of_hedge, orchard_trees, lined, roadside_rows), flush=True)
        t.mark("hedges")
    sw2 = CELLS.ScatterWorld(grid, H, owner, moist, water.mask, road_d, road_w, pad_mask, ctx.slope,
                             bank, regions, water_d=water_d, field_d=field_d, pad_t=pad_t)
    cell_regions = CELLS.cell_region_ids(sw2, regions)
    # Who is standing out there: the region's own creatures, off the roads and away from the
    # hearths, in the groups their kind keeps.
    spawns_by_cell = ENC.place(sw2, regions, places, PACK, seed)
    t.mark("encounters")
    scenes_by_cell: dict = {}
    for entry in poi_out:
        if "scene" not in entry:
            continue
        cx, cz = grid.cell_of(np.array([entry["pos"][0]]), np.array([entry["pos"][2]]))
        key = (int(cx[0]), int(cz[0]))
        scene_entry = {"scene": entry["scene"], "pos": entry["pos"], "yaw": entry["yaw"],
                       "props": {"place_id": entry["place_id"]}}
        if "collision" in entry:
            scene_entry["collision"] = entry["collision"]
        scenes_by_cell.setdefault(key, []).append(scene_entry)
    for scene_entry in extra_scenes:
        cx, cz = grid.cell_of(np.array([scene_entry["pos"][0]]), np.array([scene_entry["pos"][2]]))
        scenes_by_cell.setdefault((int(cx[0]), int(cz[0])), []).append(scene_entry)

    # --- write ------------------------------------------------------------------------
    # A staged build only rewrites its own outputs, so `--only textures` never blanks the
    # cells a previous full build wrote.
    stage = args.only or "all"
    want_terrain = stage in ("all", "heights")
    want_textures = stage in ("all", "textures")
    want_cells = stage in ("all", "cells")
    if base is None:
        base = np.zeros((n, n), dtype=np.uint8)
        overlay = np.zeros((n, n), dtype=np.uint8)
        blend = np.zeros((n, n), dtype=np.uint8)
        colour = np.full((n, n, 4), 128, dtype=np.uint8)
        colour[..., :3] = 255
    # navigation bit: walkable ground (gentle, dry, not a cliff) for future nav baking
    nav = ((ctx.slope < 0.55) & (water.mask == 0)).astype(np.uint8)
    OUT.write_maps(out_dir, grid, H, region_mask, base, overlay, blend, colour, water.mask, water.flow, nav,
                   terrain=want_terrain, textures=want_textures)
    runtime = OUT.write_runtime(out_dir, grid, H, region_mask, water.mask, water.level)
    if want_terrain:
        OUT.write_splines(out_dir, rivers, roads_list)
    n_cells = 0
    if want_cells:
        OUT.write_pois(out_dir, poi_out)
        n_cells = OUT.write_cells(out_dir, grid, buckets, cell_regions, scenes_by_cell, spawns_by_cell)
    instances = int(sum(len(v) for b in buckets.values() for v in b.values()))
    stats = {
        "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "build_seconds": round(t.total(), 1),
        "height_range": [round(float(H.min()), 2), round(float(H.max()), 2)],
        "water_fraction": round(float(water.mask.mean()), 4),
        "rivers": len(rivers), "roads": len(roads_list), "pois": len(poi_out),
        "scatter_instances": instances,
        "encounters": int(sum(len(v) for v in spawns_by_cell.values())),
        "texture_slots": SF.SLOT_NAMES,
        "only": args.only or "all",
        # what the pads in heights.r32 were flattened under; a staged build checks it
        "pad_fingerprint": pads_crc,
        # which of the parts that are off by default this build made (RECIPES)
        "recipes": recipes,
    }
    start = atlas.get("start")
    if start:
        sx, sz = float(start["at"][0]), float(start["at"][1])
        sy = float(sample_bilinear(H, grid, np.array([sx]), np.array([sz]))[0])
        stats["start"] = {"pos": [round(sx, 2), round(sy, 2), round(sz, 2)],
                          "facing_deg": float(start["facing_deg"])}
        if start.get("place"):
            stats["start"]["place"] = start["place"]
    # the manifest's one lake level is the biggest lake's (the game reads each texel's own level
    # from the runtime water-level map; this is for anything that wants "the lake")
    lakes = atlas.get("lakes", [])
    if lakes:
        biggest = max(lakes, key=lambda lk: ATLAS.polygon_area(lk["polygon"]))
        stats["lake_level"] = biggest["level_m"]
        stats["lakes"] = [{"id": lk["id"], "level_m": lk["level_m"]} for lk in lakes]
    stats["atlas"] = {"name": atlas.get("name", ""), "provinces": [r.province for r in regions],
                      "crc": "%08x" % zlib.crc32(json.dumps(atlas, sort_keys=True).encode("utf-8"))}
    OUT.write_manifest(out_dir, grid, seed, content_regions, runtime, stats)
    t.mark("write")
    print("[world] %d cells, %d scatter instances, heights %.1f..%.1f m, water %.1f%%"
          % (n_cells, instances, H.min(), H.max(), 100.0 * water.mask.mean()), flush=True)
    print("[world] done in %.1fs -> %s" % (t.total(), out_dir), flush=True)
    return stats


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Build Wickmere world data")
    ap.add_argument("--size", type=int, default=0, help="grid resolution (default: size_m / spacing_m)")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--out", type=str, default=None)
    ap.add_argument("--only", type=str, choices=["heights", "textures", "cells"], default=None)
    ap.add_argument("--atlas", type=str, default=None,
                    help="the atlas to build (default tools/world/atlas/atlas.json)")
    ap.add_argument("--pack", type=str, default=None,
                    help="the core content pack to read places, POIs and regions from "
                         "(default game/content/packs/core)")
    ap.add_argument("--recipe", action="append", choices=sorted(RECIPES), default=None,
                    help="build a part of the world that is off by default (repeatable): "
                         + "; ".join("%s -- %s" % kv for kv in sorted(RECIPES.items())))
    ap.add_argument("--without", action="append", choices=sorted(RECIPES), default=None,
                    help="leave out a recipe the build would otherwise make (repeatable)")
    args = ap.parse_args(argv)
    build(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
