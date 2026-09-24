"""What stands beside a road, so that a road reads as a road.

The roads are carved, graded and paved, and the surface rules give them a worn crown, ruts
and a verge -- but until now nothing stood along them. A painted stripe across a hillside is
not a road; what makes one legible is the furniture beside it: posts and rails where it runs
past somebody's field, a milestone at the roadside, and a signpost where two of them meet
pointing at the places they go to. The world already knows all of it -- every road is named
for the two settlements it joins -- so none of this has to be invented.

Placed along the road polylines rather than scattered, because everything here is spaced by
distance travelled: a milestone every so many hundred metres, a signpost at a junction, a run
of rail between two points on one side of the carriageway.
"""
from __future__ import annotations

import math

import numpy as np

from .grid import Grid

## metres between milestones along a road, and how far off the centre line they stand
MILESTONE_EVERY_M = 420.0
MILESTONE_OFFSET_M = 3.4
## a run of post-and-rail along a frontage: how long, how often, and the gap between posts
RAIL_EVERY_M = 2.35
FRONTAGE_RUN_M = 34.0
FRONTAGE_CHANCE = 0.22
## What a road is fenced from the land with. By default, post and rail in every region
## (`RAIL_KIT`). With `place(by_region=True)`, which is the world build's `cover` recipe, by
## landform: the Vale and the lake shoulder put post and rail along a frontage; the clans wall
## theirs in drystone, in longer runs; nobody fences a road across a marsh, a wood or an ash
## heath, where the rail is the Vale's own fence carried into every region.
RAIL_KIT = {"asset": "props/fence_post_rail", "run_m": FRONTAGE_RUN_M, "chance": FRONTAGE_CHANCE}
FRONTAGE = {
    "downs": {"asset": "props/fence_post_rail", "run_m": FRONTAGE_RUN_M, "chance": FRONTAGE_CHANCE},
    "lake_basin": {"asset": "props/fence_post_rail", "run_m": FRONTAGE_RUN_M, "chance": FRONTAGE_CHANCE},
    "mountains": {"asset": "props/drystone_wall", "run_m": 70.0, "chance": 0.30},
}


def _resample(points: np.ndarray, step_m: float) -> tuple:
    """Walk a polyline at a fixed step; returns (positions, unit tangents, distance along)."""
    pts = np.asarray(points, dtype=np.float64)
    if pts.shape[0] < 2:
        return np.zeros((0, 2)), np.zeros((0, 2)), np.zeros(0)
    seg = np.diff(pts, axis=0)
    seg_len = np.hypot(seg[:, 0], seg[:, 1])
    total = float(seg_len.sum())
    if total < step_m:
        return np.zeros((0, 2)), np.zeros((0, 2)), np.zeros(0)
    cum = np.concatenate([[0.0], np.cumsum(seg_len)])
    want = np.arange(step_m * 0.5, total, step_m)
    out_p, out_t = [], []
    for d in want:
        k = int(np.searchsorted(cum, d) - 1)
        k = max(0, min(k, seg.shape[0] - 1))
        f = (d - cum[k]) / max(seg_len[k], 1e-6)
        out_p.append(pts[k] + seg[k] * f)
        out_t.append(seg[k] / max(seg_len[k], 1e-6))
    return np.array(out_p), np.array(out_t), want


def _yaw_along(tx: float, tz: float) -> float:
    """Degrees about +Y that lay an asset's own +X along (tx, tz)."""
    return math.degrees(math.atan2(-tz, tx))


def _yaw_facing(dx: float, dz: float) -> float:
    """Degrees about +Y that turn an asset's front (-Z) toward (dx, dz)."""
    return math.degrees(math.atan2(-dx, -dz))


def _put(out: dict, grid: Grid, H: np.ndarray, x: float, z: float, yaw: float, scale: float,
         asset: str, tint: str = "#ffffff") -> bool:
    j, i = grid.to_tex(np.array([x], dtype=np.float32), np.array([z], dtype=np.float32))
    j, i = grid.clamp_index(j, i)
    y = float(H[int(i[0]), int(j[0])])
    key = grid.written_cell(x, z)
    out.setdefault(key, {}).setdefault(asset, []).append(
        [round(x, 2), round(y, 2), round(z, 2), round(yaw, 1), round(scale, 3), tint])
    return True


def place(grid: Grid, H: np.ndarray, owner: np.ndarray, slope: np.ndarray, water: np.ndarray,
          pad_mask: np.ndarray, field_d: np.ndarray, regions: list, roads: list, places: list,
          index: dict, seed: int, by_region: bool = False) -> dict:
    """Returns {(cx, cz): {asset_path: [rows]}} for milestones, signposts and rails.

    `by_region` fences each road the way its landform does (`FRONTAGE`) instead of with post
    and rail everywhere.
    """
    from .cells import assets_for

    out: dict = {}
    if not roads:
        return out
    rng = np.random.default_rng(np.random.SeedSequence([seed, 6161]))
    by_index = {r.index: r for r in regions}
    n = grid.n

    def region_short_at(x: float, z: float) -> str:
        j, i = grid.to_tex(np.array([x], dtype=np.float32), np.array([z], dtype=np.float32))
        j, i = grid.clamp_index(j, i)
        r = by_index.get(int(owner[int(i[0]), int(j[0])]))
        # the province's biome's art: a lake shore in the Hearthvale takes Brightwater's rails
        return r.art_short if r else ""

    def clear_at(x: float, z: float, off_pad: bool = True) -> bool:
        j, i = grid.to_tex(np.array([x], dtype=np.float32), np.array([z], dtype=np.float32))
        j, i = grid.clamp_index(j, i)
        ii, jj = int(i[0]), int(j[0])
        if off_pad and pad_mask[ii, jj] != 0:
            return False
        return bool(water[ii, jj] == 0 and slope[ii, jj] < 0.42)

    # --- milestones ---------------------------------------------------------------------
    for road in roads:
        pts, tans, dist = _resample(np.asarray(road.points), MILESTONE_EVERY_M)
        for k in range(pts.shape[0]):
            px, pz = float(pts[k][0]), float(pts[k][1])
            tx, tz = float(tans[k][0]), float(tans[k][1])
            side = 1.0 if (k % 2 == 0) else -1.0
            nx, nz = -tz * side, tx * side
            x = px + nx * MILESTONE_OFFSET_M
            z = pz + nz * MILESTONE_OFFSET_M
            if not clear_at(x, z):
                continue
            short = region_short_at(x, z)
            stones = assets_for(index, "props/milestone", short)
            if not stones:
                continue
            # the dressed face looks back across the road at whoever is reading it
            yaw = _yaw_facing(-nx, -nz) + float(rng.normal(0.0, 5.0))
            _put(out, grid, H, x, z, yaw, float(rng.uniform(0.92, 1.12)),
                 stones[int(rng.integers(0, len(stones)))])

    # --- signposts where roads meet -------------------------------------------------------
    # Every road ends at a settlement, so the ends cluster; a place with three or more roads
    # arriving is a junction and gets a post, standing back from the carriageway.
    #
    # It has to be allowed to stand *on* the settlement's platform. Every junction in the
    # world is a town centre, and a town centre is pad by definition, so testing the pad the
    # way the milestones and rails do rejected all eleven of them and the first build raised
    # exactly zero signposts.
    ends: dict = {}
    for road in roads:
        pts = np.asarray(road.points)
        for end in (0, -1):
            key = (round(float(pts[end][0]) / 24.0), round(float(pts[end][1]) / 24.0))
            ends.setdefault(key, []).append((float(pts[end][0]), float(pts[end][1])))
    for key, arrivals in ends.items():
        if len(arrivals) < 3:
            continue
        x0 = float(np.mean([a[0] for a in arrivals]))
        z0 = float(np.mean([a[1] for a in arrivals]))
        short = region_short_at(x0, z0)
        posts = assets_for(index, "props/signpost", short)
        if not posts:
            continue
        for attempt in range(10):
            a = float(rng.uniform(0.0, 2.0 * math.pi))
            r = float(rng.uniform(9.0, 15.0))
            x, z = x0 + math.cos(a) * r, z0 + math.sin(a) * r
            if clear_at(x, z, off_pad=False):
                _put(out, grid, H, x, z, float(rng.uniform(0.0, 360.0)),
                     float(rng.uniform(0.95, 1.1)),
                     posts[int(rng.integers(0, len(posts)))])
                break

    # --- post and rail along a frontage ---------------------------------------------------
    # Where a road runs past enclosed ground, the field is fenced off from it. Runs rather
    # than a continuous fence: a frontage is one owner's boundary, not the whole road.
    shape_of = {r.art_short: r.shape for r in regions}
    for road in roads:
        pts, tans, dist = _resample(np.asarray(road.points), RAIL_EVERY_M)
        if pts.shape[0] == 0:
            continue
        run_left = 0
        side = 1.0
        off = 3.6
        kit = None
        for k in range(pts.shape[0]):
            px, pz = float(pts[k][0]), float(pts[k][1])
            if run_left <= 0:
                kit = FRONTAGE.get(shape_of.get(region_short_at(px, pz), "")) if by_region else RAIL_KIT
                if kit is None:
                    continue
                if float(rng.random()) > kit["chance"] * (RAIL_EVERY_M / kit["run_m"]) * 6.0:
                    continue
                run_left = int(kit["run_m"] / RAIL_EVERY_M)
                side = 1.0 if rng.random() < 0.5 else -1.0
                # one distance off the road for the whole run: each module drawn at its own
                # distance (and its own x and z of it) stood its rails clear of the next's posts
                off = float(rng.uniform(3.2, 4.0))
            run_left -= 1
            tx, tz = float(tans[k][0]), float(tans[k][1])
            nx, nz = -tz * side, tx * side
            x = px + nx * off
            z = pz + nz * off
            if not clear_at(x, z):
                run_left = 0
                continue
            short = region_short_at(x, z)
            rails = assets_for(index, kit["asset"], short)
            if not rails:
                continue
            # along the road exactly and at the module's own size, so each meets the next
            _put(out, grid, H, x, z, _yaw_along(tx, tz), 1.0,
                 rails[int(rng.integers(0, len(rails)))])
    return out


## Playtest 5: "the world still feels empty between places". A road across open country was a
## carriageway and its rails and milestones, with the scatter going on either side of it as if it
## were not there. A road that is travelled has its own planting: a verge of taller growth along
## its edges (cow parsley, rough grass, foxgloves, ferns under the trees), the hedge or the wall
## somebody laid along it, and the odd tree that has been left to grow at the roadside. By landform:
## `verge` [(asset, weight)] and `per_m` plants a metre each side, `band` metres out past the
## carriageway's edge; `line` a hedge or a wall in runs of `run_m` along `share` of the road, `back`
## metres past the edge; `trees` [(asset, weight)] one every `tree_every_m`, `tree_back` out.
VERGE = {
    "downs": {"verge": [("flora/cow_parsley", 0.34), ("flora/meadow_grass", 0.3), ("flora/grass_clump", 0.14),
                        ("flora/oxeye_daisy", 0.09), ("flora/foxglove", 0.05), ("flora/buttercup", 0.08)],
              "per_m": 1.2, "band": (0.6, 3.2),
              "line": "props/hedge_segment", "spacing_m": 2.1, "share": 0.5, "run_m": (50.0, 220.0), "back": (2.6, 3.4),
              "trees": [("trees/oak", 0.45), ("trees/hawthorn", 0.35), ("trees/hazel", 0.2)],
              "tree_every_m": (70.0, 190.0), "tree_back": (3.8, 6.5)},
    "lake_basin": {"verge": [("flora/meadow_grass", 0.4), ("flora/cow_parsley", 0.25), ("flora/grass_clump", 0.15),
                             ("flora/oxeye_daisy", 0.12), ("flora/buttercup", 0.08)],
                   "per_m": 1.1, "band": (0.6, 3.0),
                   "line": "props/hedge_segment", "spacing_m": 2.2, "share": 0.35, "run_m": (40.0, 160.0), "back": (2.6, 3.4),
                   "trees": [("trees/lime", 0.4), ("trees/willow", 0.2), ("trees/alder", 0.2), ("trees/birch", 0.2)],
                   "tree_every_m": (80.0, 200.0), "tree_back": (3.8, 6.5)},
    "forest_rise": {"verge": [("flora/fern", 0.3), ("flora/bracken", 0.28), ("flora/foxglove", 0.12),
                              ("flora/briar", 0.1), ("flora/grass_clump", 0.2)],
                    "per_m": 1.3, "band": (0.5, 3.6),
                    "trees": [("trees/oak_sapling", 0.2), ("trees/hazel", 0.3), ("trees/birch", 0.2),
                              ("trees/black_ash_sapling", 0.15), ("trees/black_ash", 0.15)],
                    "tree_every_m": (45.0, 130.0), "tree_back": (3.4, 6.0)},
    "mountains": {"verge": [("flora/grass_clump", 0.45), ("flora/heather", 0.3), ("flora/bracken", 0.25)],
                  "per_m": 0.8, "band": (0.5, 2.8),
                  "line": "props/drystone_wall", "spacing_m": 2.4, "share": 0.3, "run_m": (40.0, 150.0), "back": (2.4, 3.2),
                  "max_height_m": 430.0,
                  "trees": [("trees/rowan", 0.45), ("flora/juniper", 0.35), ("trees/hawthorn", 0.2)],
                  "tree_every_m": (140.0, 360.0), "tree_back": (3.6, 6.0)},
    "delta": {"verge": [("flora/sedge_tussock", 0.35), ("flora/meadow_grass", 0.3), ("flora/marsh_marigold", 0.15),
                        ("flora/grass_clump", 0.2)],
              "per_m": 1.0, "band": (0.5, 3.0),
              "trees": [("trees/willow_pollard", 0.6), ("trees/alder", 0.4)],
              "tree_every_m": (60.0, 170.0), "tree_back": (3.4, 5.5)},
    "ash_plateau": {"verge": [("flora/grey_grass", 1.0)], "per_m": 0.6, "band": (0.5, 2.6),
                    "trees": [("trees/dead_ash", 0.5), ("props/char_stump", 0.5)],
                    "tree_every_m": (150.0, 340.0), "tree_back": (3.4, 5.5)},
}
## the step a road is walked at for its verge, and how steep the ground may be for any of it
VERGE_STEP_M = 1.0
VERGE_SLOPE_MAX = 0.5
## how near a rail, a milestone or a signpost the planting keeps off
VERGE_CLEAR_M = 1.6


def _tints(rules: dict) -> dict:
    """{asset: (tint_index, tint_strength, scale)} off the scatter's own rules, so a verge's cow
    parsley is the colour and the size of the field's."""
    out: dict = {}
    for block in ("flora", "countryside"):
        items = rules.get(block, {})
        rows = items.values() if block == "flora" else [r for v in items.values() if isinstance(v, list) for r in v]
        for r in rows:
            if isinstance(r, dict) and "asset" in r and r["asset"] not in out:
                out[r["asset"]] = (r.get("tint_index", 1), r.get("tint_strength", 0.45), r.get("scale", [0.85, 1.2]))
    return out


def planting(grid: Grid, H: np.ndarray, owner: np.ndarray, slope: np.ndarray, water: np.ndarray,
             pad_mask: np.ndarray, road_d: np.ndarray, road_w: np.ndarray, regions: list, roads: list,
             index: dict, seed: int, rules: dict | None = None, beside: dict | None = None) -> dict:
    """Returns {(cx, cz): {asset_path: [rows]}}: the verge, the hedges and walls, and the odd tree
    along every road through open country (VERGE), none on a settlement's platform, in water, on
    another road's carriageway, down a slope, or within VERGE_CLEAR_M of what `beside` (the rails,
    milestones and signposts `place` stood) already has there."""
    from .cells import _hex, _palette_rgb, assets_for
    from .grid import sample_bilinear, sample_nearest

    out: dict = {}
    if not roads:
        return out
    rng = np.random.default_rng(np.random.SeedSequence([seed, 6262]))
    by_index = {r.index: r for r in regions}
    tint_of = _tints(rules or {})
    stood = None
    if beside:
        pts = [(r[0], r[2]) for by in beside.values() for rows in by.values() for r in rows]
        if pts:
            from scipy.spatial import cKDTree
            stood = cKDTree(np.asarray(pts, dtype=np.float64))
    variants: dict = {}

    def kinds(asset: str, short: str) -> list:
        key = (asset, short)
        if key not in variants:
            variants[key] = assets_for(index, asset, short)
        return variants[key]

    def ok(x: np.ndarray, z: np.ndarray, clear_m: float) -> np.ndarray:
        good = sample_nearest(water, grid, x, z) == 0
        good &= sample_nearest(pad_mask.view(np.uint8) if pad_mask.dtype == bool else pad_mask, grid, x, z) == 0
        good &= sample_bilinear(slope, grid, x, z) < VERGE_SLOPE_MAX
        # off every carriageway, this road's and any other's
        good &= sample_nearest(road_d, grid, x, z) > sample_nearest(road_w, grid, x, z) * 0.5 + 0.4
        if stood is not None and good.any():
            d, _ = stood.query(np.stack([x, z], axis=1))
            good &= d > clear_m
        return good

    def put(x: float, z: float, yaw: float, scale: float, asset: str, tint: str) -> None:
        y = float(sample_bilinear(H, grid, np.array([x]), np.array([z]))[0])
        key = grid.written_cell(x, z)
        out.setdefault(key, {}).setdefault(asset, []).append(
            [round(x, 2), round(y, 2), round(z, 2), round(yaw, 1), round(scale, 3), tint])

    def tint_for(asset: str, region) -> str:
        idx, strength, _ = tint_of.get(asset, (1, 0.45, None))
        if idx is None or strength is None or int(idx) < 0:
            return "#ffffff"
        pal = _palette_rgb(region)
        base = (1.0 - float(strength)) + float(strength) * pal[int(idx) % pal.shape[0]]
        c = np.clip(base * (1.0 + rng.normal(0.0, 0.07) + rng.normal(0.0, 0.02, 3)), 0.25, 1.0)
        return _hex(c)

    def scale_for(asset: str) -> float:
        lo, hi = tint_of.get(asset, (1, 0.45, [0.85, 1.2]))[2] or [0.85, 1.2]
        return float(rng.uniform(float(lo), float(hi)))

    def region_at(x: np.ndarray, z: np.ndarray) -> np.ndarray:
        return sample_nearest(owner, grid, x, z)

    for road in roads:
        pts = np.asarray(road.points, dtype=np.float64)[:, :2]
        half = float(road.width) * 0.5
        p, t, dist = _resample(pts, VERGE_STEP_M)
        if p.shape[0] == 0:
            continue
        nx, nz = -t[:, 1], t[:, 0]
        owners = region_at(p[:, 0], p[:, 1])
        # --- the verge ----------------------------------------------------------------------
        for side in (1.0, -1.0):
            kit_per = np.array([float(VERGE.get(getattr(by_index.get(int(o)), "shape", ""), {}).get("per_m", 0.0))
                                for o in owners])
            take = rng.random(p.shape[0]) < kit_per * VERGE_STEP_M
            if not take.any():
                continue
            k = np.nonzero(take)[0]
            lo = np.array([VERGE[by_index[int(owners[i])].shape]["band"][0] for i in k])
            hi = np.array([VERGE[by_index[int(owners[i])].shape]["band"][1] for i in k])
            off = half + lo + (hi - lo) * rng.random(k.size) ** 1.6       # thickest at the edge
            along = rng.uniform(-0.5, 0.5, k.size)
            x = p[k, 0] + side * nx[k] * off + t[k, 0] * along
            z = p[k, 1] + side * nz[k] * off + t[k, 1] * along
            good = ok(x, z, 0.8)
            for m in np.nonzero(good)[0]:
                region = by_index[int(owners[k[m]])]
                kit = VERGE[region.shape]
                names = [a for a, _ in kit["verge"]]
                w = np.array([wt for _, wt in kit["verge"]], dtype=np.float64)
                asset = names[int(rng.choice(len(names), p=w / w.sum()))]
                got = kinds(asset, region.art_short)
                if not got:
                    continue
                put(float(x[m]), float(z[m]), float(rng.uniform(0.0, 360.0)), scale_for(asset),
                    got[int(rng.integers(0, len(got)))], tint_for(asset, region))
        # --- the hedges and walls, in runs along one side -----------------------------------
        for side in (1.0, -1.0):
            left = 0.0
            back = 3.0
            asset_line = None
            spacing = 2.2
            s = 0.0
            while s < float(dist[-1]) if dist.size else False:
                i = min(int(s / VERGE_STEP_M), p.shape[0] - 1)
                region = by_index.get(int(owners[i]))
                kit = VERGE.get(getattr(region, "shape", ""), {})
                if left <= 0.0:
                    s += 10.0
                    if not kit.get("line") or rng.random() > kit["share"] * 10.0 / (0.5 * sum(kit["run_m"])):
                        continue
                    left = float(rng.uniform(*kit["run_m"]))
                    back = float(rng.uniform(*kit["back"]))
                    asset_line = kit["line"]
                    spacing = float(kit["spacing_m"])
                    continue
                x = p[i, 0] + side * nx[i] * (half + back)
                z = p[i, 1] + side * nz[i] * (half + back)
                good = bool(ok(np.array([x]), np.array([z]), VERGE_CLEAR_M)[0])
                if good and "max_height_m" in kit:
                    good = float(sample_bilinear(H, grid, np.array([x]), np.array([z]))[0]) < kit["max_height_m"]
                got = kinds(asset_line, region.art_short) if (good and region is not None) else []
                if got:
                    yaw = _yaw_along(float(t[i, 0]), float(t[i, 1])) + float(rng.normal(0.0, 3.0))
                    put(x, z, yaw, float(rng.uniform(0.9, 1.15)), got[int(rng.integers(0, len(got)))], "#ffffff")
                s += spacing
                left -= spacing
        # --- the odd tree ---------------------------------------------------------------------
        s = float(rng.uniform(10.0, 80.0))
        while dist.size and s < float(dist[-1]):
            i = min(int(s / VERGE_STEP_M), p.shape[0] - 1)
            region = by_index.get(int(owners[i]))
            kit = VERGE.get(getattr(region, "shape", ""), {})
            gap = kit.get("tree_every_m", (150.0, 300.0))
            if kit.get("trees"):
                side = 1.0 if rng.random() < 0.5 else -1.0
                off = half + float(rng.uniform(*kit["tree_back"]))
                x = p[i, 0] + side * nx[i] * off
                z = p[i, 1] + side * nz[i] * off
                if bool(ok(np.array([x]), np.array([z]), 3.0)[0]):
                    names = [a for a, _ in kit["trees"]]
                    w = np.array([wt for _, wt in kit["trees"]], dtype=np.float64)
                    asset = names[int(rng.choice(len(names), p=w / w.sum()))]
                    got = kinds(asset, region.art_short)
                    if got:
                        put(float(x), float(z), float(rng.uniform(0.0, 360.0)), float(rng.uniform(0.85, 1.25)),
                            got[int(rng.integers(0, len(got)))], "#ffffff")
            s += float(rng.uniform(*gap))
    return out
