#!/usr/bin/env python3
"""Wickmere world builder.

Reads the world, region, place and POI definitions from the core content pack and writes
every file listed in docs/CONTRACTS.md section 6 into game/world/generated/.

    tools/world/build_world.py                 # full 4096 build
    tools/world/build_world.py --size 1024     # fast test build
    tools/world/build_world.py --only heights  # heights/water/roads only
    tools/world/build_world.py --seed 99 --out /tmp/w

Stages: region membership -> per-shape heights -> the Mere and the world edges -> place pads
-> rivers -> roads -> water, moisture -> texture control maps and colour -> POIs -> cell
scatter. Everything is deterministic from the seed in world.json (or --seed).
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

from worldgen import cells as CELLS
from worldgen import encounters as ENC
from worldgen import fields as FL
from worldgen import heights as HM
from worldgen import hedges as HG
from worldgen import hydro as HY
from worldgen import output as OUT
from worldgen import pads as PD
from worldgen import roads as RD
from worldgen import roadside as RS
from worldgen import stones as ST
from worldgen import surface as SF
from worldgen.grid import Grid, sample_bilinear
from worldgen.noise import NoiseBank
from worldgen.regions import compute_regions, dithered_owner, load_places, load_regions

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACK = os.path.join(REPO, "game", "content", "packs", "core")
DEFAULT_OUT = os.path.join(REPO, "game", "world", "generated")
OPEN_WATER = 255


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
    regions = load_regions(os.path.join(PACK, "regions", "regions.json"))
    places = load_places(os.path.join(PACK, "places", "places.json"))
    pois = load_poi_registry(PACK)
    out_dir = args.out or DEFAULT_OUT
    os.makedirs(out_dir, exist_ok=True)
    print("[world] seed %d, %d m at %.2f m/texel (%d^2), %d regions, %d places, %d pois"
          % (seed, size_m, grid.spacing, n, len(regions), len(places), len(pois)), flush=True)

    lake_def = next(r for r in regions if r.shape == "lake_basin")
    lake_c = HM.lake_geometry(grid_c, bank, lake_def.center, lake_def.lake_radius)
    lake = lake_c if n == nc else HM.lake_geometry(grid, bank, lake_def.center, lake_def.lake_radius)
    rf = compute_regions(regions, grid_c, bank, lake_c.sd, places)
    t.mark("regions")

    # pad targets: every named place, plus every POI in the registry
    pad_targets = [dict(p) for p in places]
    known = {tuple(p["position"]) for p in places}
    for p in pois:
        if tuple(p.get("position", [])) in known:
            continue
        pad_targets.append({"id": p["id"], "kind": p.get("kind", "poi"), "position": p["position"],
                            "region": p.get("region", "")})

    # Minimum pad levels: settlements sit above standing water. The marsh's table and the
    # sea's edge are the two that bite (Isseva is a stilt-town, not an underwater one).
    marsh_idx = next((r.index for r in regions if r.shape == "delta"), -1)
    marsh_tab = HY.marsh_table(grid, bank)
    min_levels: dict = {}
    dry_kinds = ("city", "town", "village", "hamlet", "fort", "camp", "lodge", "ruin_village")
    for p in pad_targets:
        px, pz = float(p["position"][0]), float(p["position"][1])
        j, i = grid.to_tex(np.array([px]), np.array([pz]))
        j, i = grid.clamp_index(j, i)
        floor_m = 0.8 if p.get("kind") in dry_kinds else 0.2
        if marsh_idx >= 0 and rf.owner_at(n)[int(i[0]), int(j[0])] == marsh_idx:
            floor_m = max(floor_m, float(marsh_tab[int(i[0]), int(j[0])]) + 0.75)
        min_levels[p["id"]] = floor_m

    heights_path = os.path.join(out_dir, "heights.r32")
    reuse = args.only in ("textures", "cells") and os.path.exists(heights_path)
    if reuse:
        H = np.fromfile(heights_path, dtype="<f4").reshape(n, n).copy()
        print("[world] reusing %s" % heights_path, flush=True)
        rivers = []
        roads_list = []
        H, pad_mask, pad_levels = RD.apply_pads(grid, H.copy(), pad_targets, min_levels)
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
        t.mark("reload")
    else:
        H = HM.compose_heights(grid, grid_c, bank, regions, rf, lake_c, lake, places)
        t.mark("heights")
        H, pad_mask, pad_levels = RD.apply_pads(grid, H, pad_targets, min_levels)
        t.mark("pads")
        rivers = HY.trace_rivers(grid, H, bank, lake, places)
        H, river_d, river_surf, river_w = HY.carve_rivers(grid, H, rivers, bank)
        t.mark("rivers")
        # a first water mask so roads know what to avoid, then the roads themselves
        rough_water = ((H < HM.SEA_LEVEL) | ((lake.sd < 0) & (H < HM.LAKE_LEVEL))
                       | (river_d <= river_w * 0.5 + 1.0)).astype(np.uint8)
        roads_list = RD.plan_roads(grid, H, pad_targets, rough_water, pad_levels)
        # and through each settlement, so a town is somewhere a road passes rather than three
        # spokes meeting at a point
        roads_list = RD.add_streets(roads_list, pad_targets, pad_levels)
        H, road_d, road_w = RD.carve_roads(grid, H, roads_list)
        # pads again: roads must not tilt a settlement platform
        H, pad_mask, pad_levels = RD.apply_pads(grid, H, pad_targets, min_levels)
        t.mark("roads")

    owner = dithered_owner(rf, n, bank)
    water = HY.water_maps(grid, H, lake, rivers, river_d, river_surf, river_w, owner, regions, bank)
    moist = HY.moisture(grid, H, water, lake, bank)
    t.mark("water")

    region_mask = owner.copy()
    open_water = (water.mask > 0) & ((lake.sd < 0) | (H < HM.SEA_LEVEL))
    region_mask[open_water] = OPEN_WATER

    # the enclosed patchwork: one pattern read by the crops, the hedges and the colour map
    field_labels, field_d = FL.field_map(grid, bank, owner, regions)
    # how far to any water at all -- river, mere or sea -- for the trees that follow it
    water_d = (ndimage.distance_transform_edt(water.mask == 0) * grid.spacing).astype(np.float32)
    # how far across a settlement's platform, so the verge can be planted and the green left
    pad_t = PD.pad_distance(grid, pad_targets)
    t.mark("fields")

    ctx = SF.SurfaceContext(grid, bank, H, regions, owner, water.mask, water.level, moist,
                            river_d, road_d, road_w, pad_mask, lake, places, rf=rf,
                            field_labels=field_labels, field_d=field_d)
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
        rules = CELLS.load_rules(os.path.join(os.path.dirname(os.path.abspath(__file__)), "scatter_rules.json"))
        sw = CELLS.ScatterWorld(grid, H, owner, moist, water.mask, road_d, road_w, pad_mask,
                                ctx.slope, bank, regions, water_d=water_d, field_d=field_d,
                                pad_t=pad_t)
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
                          field_labels, field_d, regions, index, bank, seed, places=places)
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
        # and what stands beside the roads: milestones, a signpost where roads meet, and
        # post-and-rail where the carriageway runs past somebody's field
        beside = RS.place(grid, H, owner, ctx.slope, water.mask, pad_mask, field_d, regions,
                          roads_list, places, index, seed)
        roadside_rows = 0
        for key, by_asset in beside.items():
            for asset, rows in by_asset.items():
                buckets.setdefault(key, {}).setdefault(asset, []).extend(rows)
                roadside_rows += len(rows)
        print("[world] %d hedge pieces, %d orchard trees, %d roadside"
              % (rows_of_hedge, orchard_trees, roadside_rows), flush=True)
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
    }
    OUT.write_manifest(out_dir, grid, seed, regions, runtime, stats)
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
    args = ap.parse_args(argv)
    build(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
