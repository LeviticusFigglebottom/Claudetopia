"""Rivers and water.

Rivers are traced as least-cost downhill routes on a coarse lattice, then carved at full
resolution: each river carries a monotonically falling water-surface profile, a width that
grows toward the mouth, and banks that blend back into the land. Afterwards the water mask,
the per-texel water level and the flow map are derived from the final heights.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy import ndimage

from .grid import Grid, lerp, smoothstep
from .heights import LAKE_LEVEL, SEA_LEVEL
from .noise import NoiseBank, downsample
from . import paths


@dataclass
class River:
    id: str
    points: np.ndarray       # [(x, z), ...] world metres
    width: np.ndarray        # per point, metres
    surface: np.ndarray      # per point, water surface elevation


@dataclass
class WaterResult:
    rivers: list
    mask: np.ndarray         # uint8, 1 = water surface
    level: np.ndarray        # float32, water surface elevation (only meaningful where mask)
    flow: np.ndarray         # uint8 [n, n, 2]
    river_dist: np.ndarray   # float32 metres to the nearest river centre line


def _coarse(h: np.ndarray, n_c: int) -> np.ndarray:
    return downsample(h, n_c)


def _monotone_profile(h_along: np.ndarray, start: float, end: float, min_drop: float = 0.05) -> np.ndarray:
    """A water surface that starts at `start`, ends at `end`, follows the land and never climbs."""
    k = h_along.size
    prof = np.minimum(h_along - 0.4, start)
    prof[0] = start
    for i in range(1, k):                      # enforce descent
        prof[i] = min(prof[i], prof[i - 1] - min_drop)
    # lift the tail smoothly so the mouth meets the receiving water level exactly
    t = np.linspace(0.0, 1.0, k) ** 2
    prof = lerp(prof, np.maximum(prof, end), t)
    prof[-1] = end
    for i in range(k - 2, -1, -1):
        prof[i] = max(prof[i], prof[i + 1] + min_drop)
    return prof.astype(np.float32)


def trace_rivers(grid: Grid, H: np.ndarray, bank: NoiseBank, lake, places: list, n_c: int = 512) -> list:
    """The Skerrow water into the Mere, the Mere's outflow west to the sea, and two feeders."""
    n_c = min(n_c, grid.n)             # a small test build has no room for a finer lattice
    gc = grid.with_n(n_c)
    hc = _coarse(H, n_c)
    Xc, Zc = gc.mesh()
    lake_sd_c = downsample(lake.sd, n_c)
    lake_water = lake_sd_c < -30.0
    sea = (hc < SEA_LEVEL + 0.5) & (Xc < -3500.0)
    # cost: follow low ground, hate climbing, like descending, avoid standing water
    area = 1.0 + 0.7 * smoothstep(40.0, 400.0, hc)
    graph_down = paths.build_graph(hc, gc.spacing, climb_penalty=260.0, descent_bonus=2.0, area_cost=area)

    def ij(x, z):
        j, i = gc.to_tex(x, z)
        j, i = gc.clamp_index(j, i)
        return int(i), int(j)

    def place_pos(short):
        for p in places:
            if p["id"].endswith("/" + short):
                return p["position"]
        return None

    out: list[River] = []

    def add(rid, start_xz, goal_mask, w0, w1, end_level, smooth=5):
        route = paths.shortest_path(graph_down, n_c, ij(*start_xz), goal_mask)
        if len(route) < 4:
            return None
        pts = np.array([gc.to_world(j, i) for i, j in route], dtype=np.float64)
        pts = np.stack(pts, axis=-1) if pts.ndim == 3 else pts
        pts = paths.smooth_polyline(pts, passes=smooth)
        pts = paths.resample_polyline(pts, 20.0)
        jj, ii = gc.to_tex(pts[:, 0], pts[:, 1])
        jj, ii = gc.clamp_index(jj, ii)
        h_along = hc[ii, jj].astype(np.float64)
        surf = _monotone_profile(h_along, float(h_along[0] - 0.5), float(end_level))
        t = np.linspace(0.0, 1.0, pts.shape[0])
        width = (w0 + (w1 - w0) * t ** 0.7).astype(np.float32)
        r = River(id=rid, points=pts, width=width, surface=surf)
        out.append(r)
        return r

    # 1. the Skerrow water: out of the northern karst, south into the Mere
    src = place_pos("oskeld_mine") or (-600, -3200)
    add("core:river/skerrow_water", (src[0] + 120, src[1] - 120), lake_water, 5.0, 13.0, LAKE_LEVEL)
    # 2. the Mere's outflow: west through Sedgemire to the Grey Sea
    mouth = (lake.center[0] - lake.radius * 0.92, lake.center[1] + 120.0)
    add("core:river/mere_outflow", mouth, sea, 11.0, 14.0, SEA_LEVEL - 0.6)
    # 3. the Larkbourne: the chalk stream of Hearthvale, north-west into the Mere
    lark = place_pos("pennywort_mill") or (600, 1900)
    add("core:river/larkbourne", (lark[0] + 250, lark[1] + 420), lake_water, 4.0, 7.5, LAKE_LEVEL)
    # 4. the Briarwold fall-water: out of the eastern ravines, west into the Mere
    fern = place_pos("fernhold") or (2300, 1100)
    add("core:river/fallwater", (fern[0] + 500, fern[1] - 250), lake_water, 4.0, 8.0, LAKE_LEVEL)
    return out


def carve_rivers(grid: Grid, H: np.ndarray, rivers: list, bank: NoiseBank):
    """Cut channels and banks. Returns (heights, distance to centre line, surface level, width)."""
    n = grid.n
    mask = np.zeros((n, n), dtype=bool)
    surf = np.zeros((n, n), dtype=np.float32)
    wide = np.zeros((n, n), dtype=np.float32)
    for r in rivers:
        paths.rasterise_polyline(r.points, grid, value=r.surface, out_mask=mask, out_value=surf)
        paths.rasterise_polyline(r.points, grid, value=r.width, out_mask=mask, out_value=wide)
    if not mask.any():
        return H, np.full((n, n), 1e6, dtype=np.float32), surf, wide
    dist_t, (ii, jj) = ndimage.distance_transform_edt(~mask, return_indices=True)
    d = (dist_t * grid.spacing).astype(np.float32)
    near_surf = surf[ii, jj]
    near_w = wide[ii, jj]
    del ii, jj, dist_t
    half = near_w * 0.5
    depth = 1.1 + 0.10 * near_w
    wob = 0.6 * bank.detail(220, n, wl_min=8.0, wl_max=40.0, beta=1.5)
    # channel: parabolic bed under the water surface
    t = np.clip(d / np.maximum(half, 0.5), 0.0, 1.0)
    bed = near_surf - depth * (1.0 - t * t) + 0.15 * wob
    # banks: rise to the local land over about two channel widths
    band = np.maximum(near_w * 1.6, 12.0)
    bank_h = near_surf + 0.8 + 0.5 * wob
    outer = smoothstep(half, half + band, d)
    target = lerp(np.minimum(bed, bank_h), np.maximum(H, bank_h), outer)
    influence = 1.0 - smoothstep(half + band, half + band * 2.2, d)
    Hn = lerp(H, np.where(d <= half, bed, np.minimum(H, target)), influence)
    return Hn.astype(np.float32), d, near_surf, near_w


def water_maps(grid: Grid, H: np.ndarray, lake, rivers: list, river_d: np.ndarray, river_surf: np.ndarray,
               river_w: np.ndarray, owner: np.ndarray, regions: list, bank: NoiseBank) -> WaterResult:
    n = grid.n
    X, Z = grid.mesh()
    level = np.full((n, n), -1000.0, dtype=np.float32)
    mask = np.zeros((n, n), dtype=bool)
    # the sea
    sea = H < SEA_LEVEL
    level[sea] = SEA_LEVEL
    mask |= sea
    # the Mere
    in_lake = (lake.sd < 0.0) & (H < LAKE_LEVEL) & (lake.island_sd > 0.0)
    level[in_lake] = LAKE_LEVEL
    mask |= in_lake
    # marsh pools: coherent sheets of standing water in Sedgemire's hollows, not speckle
    marsh_idx = next((r.index for r in regions if r.shape == "delta"), -1)
    if marsh_idx >= 0:
        smooth_h = ndimage.gaussian_filter(H, max(2.0, 8.0 / grid.spacing))
        table = marsh_table(grid, bank)
        pools = (owner == marsh_idx) & (smooth_h < table) & (H < table + 0.25) & ~mask
        k = max(3, int(round(12.0 / grid.spacing)) | 1)
        disc = np.hypot(*np.ogrid[-(k // 2):k // 2 + 1, -(k // 2):k // 2 + 1]) <= k / 2.0
        pools = ndimage.binary_opening(pools, disc)
        pools = ndimage.binary_closing(pools, disc)
        lab, nlab = ndimage.label(pools)
        if nlab:
            sizes = np.bincount(lab.ravel())
            small = np.flatnonzero(sizes < max(12, int(600.0 / (grid.spacing ** 2))))
            pools &= ~np.isin(lab, small)
        level = np.where(pools & (table > level), table, level)
        mask |= pools
    # rivers
    riv = (river_d <= river_w * 0.5 + 0.5) & (H < river_surf + 0.25)
    level = np.where(riv & (river_surf > level), river_surf, level)
    mask |= riv
    # drop specks: a single wet texel is noise, not a pool
    min_px = max(4, int(round(40.0 / (grid.spacing ** 2))))
    lab, nlab = ndimage.label(mask)
    if nlab:
        sizes = np.bincount(lab.ravel())
        tiny = np.flatnonzero(sizes < min_px)
        if tiny.size:
            drop = np.isin(lab, tiny)
            mask &= ~drop
            level[drop] = -1000.0
    # flow directions
    flow = np.full((n, n, 2), 128, dtype=np.uint8)
    for r in rivers:
        p = paths.resample_polyline(r.points, grid.spacing * 0.5)
        d = np.diff(p, axis=0, append=p[-1:][np.newaxis, 0].reshape(1, 2))
        nrm = np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-6)
        d = d / nrm
        j, i = grid.to_tex(p[:, 0], p[:, 1])
        j, i = grid.clamp_index(j, i)
        flow[i, j, 0] = np.clip(d[:, 0] * 127.0 + 128.0, 0, 255).astype(np.uint8)
        flow[i, j, 1] = np.clip(d[:, 1] * 127.0 + 128.0, 0, 255).astype(np.uint8)
    # spread river flow across the channel width
    wide_mask = river_d <= np.maximum(river_w * 0.5, grid.spacing)
    if wide_mask.any():
        idx = ndimage.distance_transform_edt(flow[..., 0] == 128, return_distances=False, return_indices=True)
        spread = flow[idx[0], idx[1]]
        flow = np.where(wide_mask[..., None], spread, flow)
    return WaterResult(rivers=rivers, mask=mask.astype(np.uint8), level=level, flow=flow,
                       river_dist=river_d)


def marsh_table(grid: Grid, bank: NoiseBank) -> np.ndarray:
    """The standing water level across the marsh: where the delta's pools sit."""
    return (1.25 + 0.25 * np.tanh(bank.field_at(232, grid.n, beta=2.0, wl_min=200, wl_max=900))).astype(np.float32)


def moisture(grid: Grid, H: np.ndarray, water: WaterResult, lake, bank: NoiseBank) -> np.ndarray:
    """0..1 wetness from distance to open water plus height above the local water surface."""
    n = grid.n
    d = ndimage.distance_transform_edt(water.mask == 0).astype(np.float32) * grid.spacing
    near = 1.0 - smoothstep(6.0, 140.0, d)
    low = 1.0 - smoothstep(2.0, 26.0, np.maximum(H - LAKE_LEVEL, 0.0))
    noise = 0.5 + 0.5 * np.tanh(bank.field_at(231, n, beta=1.8, wl_min=120, wl_max=600))
    m = np.clip(0.58 * near + 0.27 * low + 0.15 * noise, 0.0, 1.0)
    return m.astype(np.float32)
