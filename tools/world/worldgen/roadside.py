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
    cx, cz = grid.cell_of(np.array([x], dtype=np.float32), np.array([z], dtype=np.float32))
    key = (int(np.clip(cx[0], 0, grid.cells - 1)), int(np.clip(cz[0], 0, grid.cells - 1)))
    out.setdefault(key, {}).setdefault(asset, []).append(
        [round(x, 2), round(y, 2), round(z, 2), round(yaw, 1), round(scale, 3), tint])
    return True


def place(grid: Grid, H: np.ndarray, owner: np.ndarray, slope: np.ndarray, water: np.ndarray,
          pad_mask: np.ndarray, field_d: np.ndarray, regions: list, roads: list, places: list,
          index: dict, seed: int) -> dict:
    """Returns {(cx, cz): {asset_path: [rows]}} for milestones, signposts and rails."""
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
        return r.short if r else ""

    def clear_at(x: float, z: float) -> bool:
        j, i = grid.to_tex(np.array([x], dtype=np.float32), np.array([z], dtype=np.float32))
        j, i = grid.clamp_index(j, i)
        ii, jj = int(i[0]), int(j[0])
        return bool(water[ii, jj] == 0 and pad_mask[ii, jj] == 0 and slope[ii, jj] < 0.42)

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
    # arriving is a junction and gets a post. It stands off the carriageway, at the edge of
    # the settlement's flattened ground rather than in the middle of the street.
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
            if clear_at(x, z):
                _put(out, grid, H, x, z, float(rng.uniform(0.0, 360.0)),
                     float(rng.uniform(0.95, 1.1)),
                     posts[int(rng.integers(0, len(posts)))])
                break

    # --- post and rail along a frontage ---------------------------------------------------
    # Where a road runs past enclosed ground, the field is fenced off from it. Runs rather
    # than a continuous fence: a frontage is one owner's boundary, not the whole road.
    for road in roads:
        pts, tans, dist = _resample(np.asarray(road.points), RAIL_EVERY_M)
        if pts.shape[0] == 0:
            continue
        run_left = 0
        side = 1.0
        for k in range(pts.shape[0]):
            if run_left <= 0:
                if float(rng.random()) > FRONTAGE_CHANCE * (RAIL_EVERY_M / FRONTAGE_RUN_M) * 6.0:
                    continue
                run_left = int(FRONTAGE_RUN_M / RAIL_EVERY_M)
                side = 1.0 if rng.random() < 0.5 else -1.0
            run_left -= 1
            px, pz = float(pts[k][0]), float(pts[k][1])
            tx, tz = float(tans[k][0]), float(tans[k][1])
            nx, nz = -tz * side, tx * side
            x = px + nx * float(rng.uniform(3.2, 4.0))
            z = pz + nz * float(rng.uniform(3.2, 4.0))
            if not clear_at(x, z):
                run_left = 0
                continue
            short = region_short_at(x, z)
            rails = assets_for(index, "props/fence_post_rail", short)
            if not rails:
                continue
            _put(out, grid, H, x, z, _yaw_along(tx, tz) + float(rng.normal(0.0, 2.5)),
                 float(rng.uniform(0.95, 1.08)),
                 rails[int(rng.integers(0, len(rails)))])
    return out
