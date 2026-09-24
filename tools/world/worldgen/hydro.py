"""Rivers and water.

Rivers run where the atlas draws them (`atlas_rivers`), in valleys they have cut
(`carve_river_valleys`), and are carved at full resolution: each carries a monotonically falling
water-surface profile, a width that grows toward the mouth, and banks that blend back into the
land. Afterwards the water mask, the per-texel water level and the flow map are derived from
the final heights: the sea, the atlas's lakes at their levels, a delta's pools and the rivers.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy import ndimage

from .grid import Grid, lerp, smoothstep
from .geography import SEA_LEVEL
from .noise import NoiseBank, downsample
from . import paths


@dataclass
class River:
    id: str
    points: np.ndarray       # [(x, z), ...] world metres
    width: np.ndarray        # per point, metres
    surface: np.ndarray      # per point, water surface elevation
    valley_m: float | None = None   # the atlas's valley width, when it gives one


@dataclass
class WaterResult:
    rivers: list
    mask: np.ndarray         # uint8, 1 = water surface
    level: np.ndarray        # float32, water surface elevation (only meaningful where mask)
    flow: np.ndarray         # uint8 [n, n, 2]
    river_dist: np.ndarray   # float32 metres to the nearest river centre line


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


## A drawn river is a line through a few points hundreds of metres apart, and built on that line
## it ran ruler-straight between them: on the chart and from the ground the rivers read as canals.
## Between its drawn points a river now wanders. It swings in meanders MEANDER_WAVE_WIDTHS widths
## long (at least MEANDER_WAVE_MIN_M) and MEANDER_AMP_WIDTHS widths out, on flat ground only, and
## sways over a few hundred metres by WANDER_M and WANDER_M_PER_WIDTH a width, less in steep
## country. It passes through every drawn point and runs straight within ANCHOR_M of one, and it
## keeps to its drawn line near anything the atlas or the content puts beside it (a bridge, a
## ford, a town, a confluence), coming back to it from AVOID_FAR_M to AVOID_NEAR_M away.
MEANDER_WAVE_WIDTHS = 13.0
MEANDER_WAVE_MIN_M = 110.0
MEANDER_AMP_WIDTHS = 3.5
WANDER_M = 28.0
WANDER_M_PER_WIDTH = 1.4
ANCHOR_M = 50.0
AVOID_NEAR_M = 45.0
AVOID_FAR_M = 170.0
## the grades over which the meanders fade out and the sway halves
FLAT_GRADE = (0.03, 0.15)


def meander(path, width, H: np.ndarray, grid: Grid, key: str, avoid: np.ndarray | None = None,
            step_m: float = 20.0, scale: float = 1.0) -> np.ndarray:
    """A drawn river's line wandering between its drawn points, resampled every `step_m`.

    `width` is (width at the source, width at the mouth); `avoid` [(x, z), ...] the things the
    river keeps to its drawn line near; `key` seeds the wander, so a river always wanders the
    same way; `scale` is the atlas's `meander`, 0 for none."""
    import zlib

    p = np.asarray(path, dtype=np.float64)
    if p.shape[0] < 2:
        return p
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    s_v = np.concatenate([[0.0], np.cumsum(seg)])
    total = float(s_v[-1])
    if total < 2.0 * ANCHOR_M or scale <= 0.0:
        return paths.resample_polyline(p, step_m)
    fine = paths.resample_polyline(p, 5.0)
    s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(fine, axis=0), axis=1))])
    # the drawn line's normal, segment by segment
    k = np.clip(np.searchsorted(s_v, s, side="right") - 1, 0, p.shape[0] - 2)
    d = (p[k + 1] - p[k]) / np.maximum(seg[k], 1e-9)[:, None]
    normal = np.stack([-d[:, 1], d[:, 0]], axis=1)
    w0, w1 = (float(v) for v in width)
    w = w0 + (w1 - w0) * (s / total) ** 0.7
    # how steep the land is along the drawn line, over a couple of hundred metres
    from .grid import sample_bilinear
    h = sample_bilinear(H, grid, fine[:, 0], fine[:, 1]).astype(np.float64)
    win = max(int(100.0 / 5.0), 1)
    kern = np.ones(2 * win + 1) / (2 * win + 1)
    hs = np.convolve(np.pad(h, win, mode="edge"), kern, mode="valid")
    grade = np.abs(np.gradient(hs, 5.0))
    flat = 1.0 - smoothstep(FLAT_GRADE[0], FLAT_GRADE[1], grade)
    # straight through every drawn point, and near anything beside the river
    to_anchor = np.min(np.abs(s[:, None] - s_v[None, :]), axis=1)
    env = smoothstep(0.0, ANCHOR_M, to_anchor)
    if avoid is not None and len(avoid):
        a = np.asarray(avoid, dtype=np.float64)
        near = np.full(fine.shape[0], 1e9)
        for c in range(0, a.shape[0], 256):
            dd = np.hypot(fine[:, None, 0] - a[None, c:c + 256, 0], fine[:, None, 1] - a[None, c:c + 256, 1])
            near = np.minimum(near, dd.min(axis=1))
        env = env * smoothstep(AVOID_NEAR_M, AVOID_FAR_M, near)
    rng = np.random.default_rng(zlib.crc32(key.encode("utf-8")))
    ph = rng.uniform(0.0, 2.0 * np.pi, 4)
    # the meanders: their wavelength grows with the river, so the phase is integrated along it
    wave = np.maximum(MEANDER_WAVE_WIDTHS * w, MEANDER_WAVE_MIN_M)
    phase = np.concatenate([[0.0], np.cumsum(2.0 * np.pi * np.diff(s) / wave[1:])])
    bends = MEANDER_AMP_WIDTHS * w * flat * (np.sin(phase + ph[0]) + 0.3 * np.sin(2.1 * phase + ph[1]))
    sway_m = (WANDER_M + WANDER_M_PER_WIDTH * w) * (0.5 + 0.5 * flat)
    sway = sway_m * (0.65 * np.sin(2.0 * np.pi * s / 430.0 + ph[2]) + 0.35 * np.sin(2.0 * np.pi * s / 270.0 + ph[3]))
    off = scale * env * (bends + sway)
    line = fine + normal * off[:, None]
    # every drawn point stays on the line: pin it there and resample the stretch between each pair
    at = np.clip(np.searchsorted(s, s_v), 0, fine.shape[0] - 1)
    at[0], at[-1] = 0, fine.shape[0] - 1
    line[at] = p
    cut = np.unique(at)
    out = [line[:1]]
    for a, b in zip(cut[:-1], cut[1:]):
        if b > a:
            out.append(paths.resample_polyline(line[a:b + 1], step_m)[1:])
    return np.concatenate(out, axis=0)


def atlas_rivers(grid: Grid, H: np.ndarray, atlas: dict, wt, avoid: list | None = None) -> list:
    """The rivers the atlas draws, each with a surface falling from its source to its mouth.

    A river's path is the atlas's, wandering between its drawn points (`meander`) and resampled
    every 20 m; `avoid` is every place and point of interest, which a river keeps to its drawn
    line near, and every river's ends are added to it. Its water starts half a metre under the
    land at the source (at the lake's level, when it rises in a lake) and ends at the level of the
    water it runs into: the sea's, a lake's, or the other river's at the confluence, which is why
    `geography.river_order` lays a tributary after the river it joins. In between it follows the
    land where the land falls and holds its level where the land rises, so a river that crosses a
    ridge cuts through it. The width runs from the source's to the mouth's.
    """
    from .atlas import lake_at, on_land
    from .geography import river_order

    out: list[River] = []
    by_id: dict = {}
    keep = [tuple(v) for v in (avoid or [])]
    for rv in atlas.get("rivers", []):
        keep.append(tuple(rv["path"][0]))
        keep.append(tuple(rv["path"][-1]))
    keep_arr = np.asarray(keep, dtype=np.float64) if keep else None
    for rv, into in river_order(atlas):
        pts = meander(rv["path"], rv["width_m"], H, grid, rv["id"], keep_arr,
                      scale=float(rv.get("meander", 1.0)))
        if pts.shape[0] < 2:
            continue
        if into is not None and into in by_id:
            # a tributary ends on the river it joins, wherever that river now runs
            other = by_id[into]
            k = int(np.argmin(np.hypot(other.points[:, 0] - pts[-1, 0], other.points[:, 1] - pts[-1, 1])))
            pts[-1] = other.points[k]
        jj, ii = grid.to_tex(pts[:, 0], pts[:, 1])
        jj, ii = grid.clamp_index(jj, ii)
        h_along = H[ii, jj].astype(np.float64)
        sx, sz = rv["path"][0]
        mx, mz = rv["path"][-1]
        src_lake = lake_at(atlas, sx, sz)
        start = float(src_lake["level_m"]) if src_lake is not None else float(h_along[0] - 0.5)
        mouth_lake = lake_at(atlas, mx, mz)
        if into is not None and into in by_id:
            other = by_id[into]
            k = int(np.argmin(np.hypot(other.points[:, 0] - mx, other.points[:, 1] - mz)))
            end = float(other.surface[k])
        elif mouth_lake is not None:
            end = float(mouth_lake["level_m"])
        elif not on_land(atlas, mx, mz):
            end = SEA_LEVEL - 0.6
        else:
            end = float(h_along[-1] - 1.0)
        end = min(end, start - 0.05 * (pts.shape[0] - 1))
        surf = _monotone_profile(h_along, start, end)
        t = np.linspace(0.0, 1.0, pts.shape[0])
        w0, w1 = (float(v) for v in rv["width_m"])
        width = (w0 + (w1 - w0) * t ** 0.7).astype(np.float32)
        river = River(id=rv["id"], points=pts, width=width, surface=surf, valley_m=rv.get("valley_m"))
        out.append(river)
        by_id[rv["id"]] = river
    return out


## the grade a river's valley sides climb at from its banks until they meet the land, and the
## valley's width when the atlas does not give one, in river widths
VALLEY_GRADE = 0.22
VALLEY_WIDTHS = 12.0
## Past half the valley's width, land still standing over the valley side is a gorge the river
## has cut, and its wall climbs on at this grade (50 degrees) until it meets the land. Faded back
## to the land over the valley's last fifth instead, a river held level through high ground ran
## in a slot: the Brindle Beck through the Skerrow dales' southern ridge, 95 m wide, its walls
## falling 55 m in one 9.4 m step.
GORGE_GRADE = 1.2
## how far past the valley a gorge wall is followed: 480 m of climb, more than any land in the
## atlas stands over a river's valley side
GORGE_REACH_M = 400.0
## A gorge wall is not a plane. Its line wanders in and out by GORGE_WANDER_M (one standard
## deviation) over a few hundred metres, as spurs and gullies, and its face has GORGE_GRAIN_M of
## grain at the detail band's scale. Both come in over the wall's first GORGE_INTO_M, so the
## valley floor is untouched and the wall never leans back on itself. Cut as a plane, the gorges
## of a 1024 build of the drawn atlas were smooth ramps a hundred metres across in rough fell.
GORGE_WANDER_M = 10.0
GORGE_GRAIN_M = 1.2
GORGE_INTO_M = 40.0
## Nor is a valley's floor. Carved as the water plus a metre and a steady climb from the bank, it
## was a smooth ramp a hundred metres wide in rough fell, and read from above as a made thing. It
## rolls by FLOOR_ROLL_M over 30 to 160 m and has FLOOR_GRAIN_M of grain, both coming in over the
## first FLOOR_INTO_M from the bank, and it never falls within FLOOR_OVER_M of the water.
FLOOR_ROLL_M = 1.8
FLOOR_GRAIN_M = 0.9
FLOOR_INTO_M = 16.0
FLOOR_OVER_M = 0.6
## A valley comes in down its river from the source, full depth by half the valley's width plus
## GORGE_INTO_M down it. A river does not cut the hill behind its own source: carved from the
## source point outwards, the Rudd Beck's head cut a bowl into the fell behind it, and lowered the
## Fallen Hand's knoll, 80 m up the fell, by 5 m after the saddle under its line had been cut.


def carve_river_valleys(grid: Grid, H: np.ndarray, rivers: list, bank: NoiseBank | None = None) -> np.ndarray:
    """Open a valley along every river so its channel is not a slot in the hills.

    From each bank the ground may stand no higher than the water plus a metre and a climb of
    VALLEY_GRADE, out to half the valley's width. Past that, land under the valley side is left
    as it was, and land over it is a gorge the river has cut through high ground: the wall
    climbs on from the valley's edge at GORGE_GRADE until it meets the land. With a `bank`, the
    wall's line wanders and its face has a grain (GORGE_WANDER_M, GORGE_GRAIN_M); without one it
    is a plane. The valley comes in down the river from its source, and the land behind the
    source is left as it was. `valley_m` 0 leaves the land to the channel's own banks.
    """
    n = grid.n
    wander = grain = roll = None
    if bank is not None:
        wander = np.clip(bank.detail(236, n, wl_min=60.0, wl_max=300.0, beta=1.8), -2.0, 2.0)
        grain = bank.detail(237, n, wl_min=max(3.0 * grid.spacing, 6.0), wl_max=48.0, beta=1.5)
        roll = np.clip(bank.detail(238, n, wl_min=30.0, wl_max=160.0, beta=2.0), -2.5, 2.5)
    for r in rivers:
        vm = getattr(r, "valley_m", None)
        if vm is not None and float(vm) <= 0.0:
            continue
        half_w = float(np.max(r.width)) * 0.5
        reach = (0.5 * float(vm)) if vm is not None else VALLEY_WIDTHS * float(np.max(r.width)) * 0.5
        reach = max(reach, half_w + 20.0)
        mask = np.zeros((n, n), dtype=bool)
        surf = np.zeros((n, n), dtype=np.float32)
        down = np.zeros((n, n), dtype=np.float32)
        paths.rasterise_polyline(r.points, grid, value=r.surface, out_mask=mask, out_value=surf)
        # how far down the river from its source each point of it is
        run = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(r.points, axis=0), axis=1))])
        paths.rasterise_polyline(r.points, grid, value=run, out_mask=mask, out_value=down)
        if not mask.any():
            continue
        # only a window round the river is worth the distance transform
        ii, jj = np.nonzero(mask)
        pad = int((reach + GORGE_REACH_M) / grid.spacing) + 4
        i0, i1 = max(int(ii.min()) - pad, 0), min(int(ii.max()) + pad + 1, n)
        j0, j1 = max(int(jj.min()) - pad, 0), min(int(jj.max()) + pad + 1, n)
        sub = mask[i0:i1, j0:j1]
        dist, (ni, nj) = ndimage.distance_transform_edt(~sub, return_indices=True)
        d = (dist * grid.spacing).astype(np.float32)
        del dist
        s = surf[i0:i1, j0:j1][ni, nj]
        # (from two texels down: the source's own texel is written a metre or so down the river)
        head = smoothstep(2.0 * grid.spacing, reach + GORGE_INTO_M, down[i0:i1, j0:j1][ni, nj])
        del ni, nj, down
        rim = VALLEY_GRADE * max(reach - half_w, 0.0)
        over = np.maximum(d - reach, 0.0)
        wall = GORGE_GRADE * over
        if wander is not None:
            into = smoothstep(0.0, GORGE_INTO_M, over)
            wall = GORGE_GRADE * np.maximum(over + GORGE_WANDER_M * wander[i0:i1, j0:j1] * into, 0.0)
            wall += GORGE_GRAIN_M * grain[i0:i1, j0:j1] * into
            del into
        climb = np.where(d <= reach, VALLEY_GRADE * np.maximum(d - half_w, 0.0), rim + wall)
        if roll is not None:
            floor_in = smoothstep(half_w + 2.0, half_w + 2.0 + FLOOR_INTO_M, d)
            climb += floor_in * (FLOOR_ROLL_M * roll[i0:i1, j0:j1] + FLOOR_GRAIN_M * grain[i0:i1, j0:j1])
            climb = np.where(d > half_w, np.maximum(climb, FLOOR_OVER_M - 1.0), climb)
            del floor_in
        side = s + 1.0 + climb
        del climb, s, over, wall
        Hs = H[i0:i1, j0:j1]
        carved = lerp(Hs, np.minimum(Hs, side), head)
        H[i0:i1, j0:j1] = np.where(d <= reach + GORGE_REACH_M, carved, Hs)
    return H


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


## How far under the water a road's ford lies. Shallow enough to wade, deep enough to read as
## water across the road and not as a wet stripe on it.
FORD_DEPTH_M = 0.45


def keep_channels(grid: Grid, H: np.ndarray, carved: np.ndarray, river_d: np.ndarray,
                  river_w: np.ndarray, river_surf: np.ndarray, road_d: np.ndarray | None = None,
                  road_w: np.ndarray | None = None) -> np.ndarray:
    """Cut every river back through whatever was laid over it after it was carved.

    Pads and roads are laid after the rivers, and both flatten or grade whatever lies under
    them, a river bed included. Measured on the build before this existed: the Larkbourne Ford,
    moved onto the river it is named for, filled 54 m of the Larkbourne with its own pad; the
    Three Sisters' pad left the Skerrow Water dry for 46 m at the foot of the falls; and every
    road crossing dammed its river for 8 to 30 m with a crown of road. A bridge dressed over a
    dry bed has nothing to span.

    `carved` is the land as the river carve left it. Inside the channel and along its banks,
    nothing laid later may stand higher than that; where a road crosses, the bed is held up to
    a wading depth (`FORD_DEPTH_M`) so the road runs through the water rather than under it.
    """
    half = river_w * 0.5
    band = np.maximum(river_w * 1.6, 12.0)
    zone = river_d <= half + band
    if not zone.any():
        return H
    ceiling = carved.astype(np.float32, copy=True)
    if road_d is not None and road_w is not None:
        ford = zone & (river_d <= half) & (road_d <= road_w * 0.5 + 2.0)
        ceiling = np.where(ford, np.maximum(ceiling, river_surf - FORD_DEPTH_M), ceiling)
    return np.where(zone, np.minimum(H, ceiling), H).astype(np.float32)


def water_maps(grid: Grid, H: np.ndarray, lake, sea: np.ndarray, rivers: list, river_d: np.ndarray,
               river_surf: np.ndarray, river_w: np.ndarray, owner: np.ndarray, regions: list,
               table: np.ndarray | None) -> WaterResult:
    """`lake` is the atlas's lakes (geography.Waters) and `sea` the sea at this grid; `table` the
    marsh's water table (`marsh_table`), for the pools in a delta province."""
    n = grid.n
    level = np.full((n, n), -1000.0, dtype=np.float32)
    mask = np.zeros((n, n), dtype=bool)
    # the sea
    level[sea] = SEA_LEVEL
    mask |= sea
    # the lakes, each at its own level
    in_lake = lake.in_lake(H)
    level = np.where(in_lake, lake.level, level)
    mask |= in_lake
    # marsh pools: coherent sheets of standing water in a delta's hollows, not speckle
    marsh = [r.index for r in regions if r.shape == "delta"]
    if marsh and table is not None:
        smooth_h = ndimage.gaussian_filter(H, max(2.0, 8.0 / grid.spacing))
        pools = np.isin(owner, marsh) & (smooth_h < table) & (H < table + 0.25) & ~mask
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
    # drop specks: a single wet texel is noise, not a pool. Counted with the corners joined: a
    # beck two metres wide at its head runs across 2 m texels as a line one texel wide, and
    # where it runs on the diagonal its texels meet only at their corners. Counted side by side,
    # the Cressbourne's head fell into eighteen pieces and the Blackgill's into fifty, most under
    # the limit, and the water mask was dry along 60 of their first 130 texels.
    min_px = max(4, int(round(40.0 / (grid.spacing ** 2))))
    lab, nlab = ndimage.label(mask, structure=np.ones((3, 3), dtype=bool))
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


## how far over a delta province's low ground its water table stands
MARSH_TABLE_OVER_M = 0.75


def marsh_table(grid: Grid, bank: NoiseBank, regions: list | None = None, rf=None) -> np.ndarray:
    """The standing water level across a marsh: where a delta's pools sit. Three quarters of a
    metre over the delta province's low ground (its `base_height_m`, blended where two meet),
    give or take a quarter, so the pools fill its lowest hollows and channels; 1.25 m where
    there is no province to say (a delta whose low ground is at half a metre, as Sedgemire's)."""
    wobble = 0.25 * np.tanh(bank.field_at(232, grid.n, beta=2.0, wl_min=200, wl_max=900))
    base = np.full((grid.n, grid.n), 0.5, dtype=np.float32)
    if regions is not None and rf is not None:
        marsh = [r for r in regions if r.shape == "delta"]
        if marsh:
            wsum = np.zeros((grid.n, grid.n), dtype=np.float32)
            acc = np.zeros((grid.n, grid.n), dtype=np.float32)
            for r in marsh:
                w = rf.weight_at(r.index, grid.n)
                wsum += w
                acc += w * float(r.base_height)
            base = np.where(wsum > 1e-4, acc / np.maximum(wsum, 1e-4), base)
    return (base + MARSH_TABLE_OVER_M + wobble).astype(np.float32)


def moisture(grid: Grid, H: np.ndarray, water: WaterResult, lake, bank: NoiseBank) -> np.ndarray:
    """0..1 wetness from distance to open water plus height above the local water surface."""
    n = grid.n
    d = ndimage.distance_transform_edt(water.mask == 0).astype(np.float32) * grid.spacing
    near = 1.0 - smoothstep(6.0, 140.0, d)
    # the water a texel stands over: its lake's, within a kilometre and a half of one, else the sea's
    ref = np.where((lake.lake_id >= 0) & (lake.sd < 1500.0), lake.level, SEA_LEVEL)
    low = 1.0 - smoothstep(2.0, 26.0, np.maximum(H - ref, 0.0))
    noise = 0.5 + 0.5 * np.tanh(bank.field_at(231, n, beta=1.8, wl_min=120, wl_max=600))
    m = np.clip(0.58 * near + 0.27 * low + 0.15 * noise, 0.0, 1.0)
    return m.astype(np.float32)
