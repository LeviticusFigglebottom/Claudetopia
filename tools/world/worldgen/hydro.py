"""Rivers and water.

Rivers run where the atlas draws them (`atlas_rivers`), in valleys they have cut
(`carve_river_valleys`), and are carved at full resolution: each carries a monotonically falling
water-surface profile, a width that grows toward the mouth, and banks that blend back into the
land. Afterwards the water mask, the per-texel water level and the flow map are derived from
the final heights: the sea, the atlas's lakes at their levels, a delta's pools and the rivers.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

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
    ## still water beside it: the loops it has cut off (`meander`), each a River of its own at
    ## one level, carved and wet like the river but not written to rivers.json and not flowing
    oxbows: list = field(default_factory=list)
    ## its falls (`find_falls`), as rivers.json writes them, and the plunge pools under the big
    ## ones, each a River of its own at the foot's level (carved and wet like an oxbow)
    falls: list = field(default_factory=list)
    pools: list = field(default_factory=list)


@dataclass
class WaterResult:
    rivers: list
    mask: np.ndarray         # uint8, 1 = water surface
    level: np.ndarray        # float32, water surface elevation (only meaningful where mask)
    flow: np.ndarray         # uint8 [n, n, 2]
    river_dist: np.ndarray   # float32 metres to the nearest river centre line
    # the marsh's creeks and small pools (shores.marsh) this added, bool, or None
    creeks: np.ndarray | None = None


def _monotone_profile(h_along: np.ndarray, start: float, end: float, min_drop=0.05) -> np.ndarray:
    """A water surface that starts at `start`, ends at `end`, follows the land and never climbs.

    `min_drop` is the least it falls from one point to the next: one figure, or one per step."""
    k = h_along.size
    drop = np.broadcast_to(np.asarray(min_drop, dtype=np.float64), (max(k - 1, 0),))
    prof = np.minimum(h_along - 0.4, start)
    prof[0] = start
    for i in range(1, k):                      # enforce descent
        prof[i] = min(prof[i], prof[i - 1] - drop[i - 1])
    # lift the tail smoothly so the mouth meets the receiving water level exactly
    t = np.linspace(0.0, 1.0, k) ** 2
    prof = lerp(prof, np.maximum(prof, end), t)
    prof[-1] = end
    for i in range(k - 2, -1, -1):
        prof[i] = max(prof[i], prof[i + 1] + drop[i])
    return prof.astype(np.float32)


## A drawn river is a line through a few points hundreds of metres apart, and built on that line
## it ran ruler-straight between them: on the chart and from the ground the rivers read as canals.
## Between its drawn points a river now wanders, and its bends are a sine-generated curve (the
## river's heading swings to and fro as it goes, Langbein and Leopold's meander), not a sine wave
## laid across the line. A sine wave's bends are all one shape, and on the chart the Outfall and
## the Larkbourne read as a drawn squiggle. Here the swing, the wavelength and the skew of the
## bends drift along the river with slow noise: some bends are lazy and some are goose-necks,
## the odd reach runs straight, and beside the tightest a loop the river has cut off lies as an
## oxbow of still water.
##
## * The wavelength is MEANDER_WAVE_WIDTHS widths (at least MEANDER_WAVE_MIN_M), times up to
##   MEANDER_WAVE_VARY either way.
## * The swing (the heading's largest angle off the line) is MEANDER_SWING radians, times 0.2 to
##   1.4 by the noise, and nothing where the noise runs low enough for a straight reach. Past a
##   right angle a bend loops back on itself, a goose-neck; no bend is tighter at its apex than
##   MEANDER_RADIUS_WIDTHS widths. MEANDER_SKEW leans the bends up or down the valley.
## * It fades out as the valley steepens over FLAT_GRADE (a gill steps down, it does not loop),
##   and a sway over a few hundred metres, WANDER_M and WANDER_M_PER_WIDTH a width, halves.
## * It passes through every drawn point and runs straight within ANCHOR_M of one, and it keeps
##   to its drawn line near anything the atlas or the content puts beside it (a bridge, a ford, a
##   town, a confluence), coming back to it from AVOID_FAR_M to AVOID_NEAR_M away.
## * An oxbow lies beside a bend swinging more than OXBOW_SWING, by about OXBOW_CHANCE of
##   them and none within OXBOW_APART_WAVES wavelengths of another: a crescent OXBOW_ARC_DEG
##   round, OXBOW_RADIUS_WAVES of a wavelength across, OXBOW_WIDTH of the river's width, its open
##   side to the river, and at the river's level there; only on the floodplain (`_oxbows`).
MEANDER_WAVE_WIDTHS = 13.0
MEANDER_WAVE_MIN_M = 110.0
MEANDER_WAVE_VARY = 1.6
MEANDER_SWING = 1.5
MEANDER_SKEW = 0.12
## the tightest a bend may turn, at its apex: MEANDER_RADIUS_WIDTHS widths, and never under
## MEANDER_RADIUS_MIN_M, so a bend holds its shape on a river kept a point every RIVER_STEP_M
MEANDER_RADIUS_WIDTHS = 1.6
MEANDER_RADIUS_MIN_M = 14.0
WANDER_M = 28.0
WANDER_M_PER_WIDTH = 1.4
ANCHOR_M = 50.0
ANCHOR_TAPER = 1.2
AVOID_NEAR_M = 45.0
AVOID_FAR_M = 170.0
## the grades over which the meanders fade out and the sway halves
FLAT_GRADE = (0.03, 0.15)
OXBOW_SWING = 1.15
OXBOW_CHANCE = 0.8
OXBOW_APART_WAVES = 4.0
OXBOW_ARC_DEG = 240.0
OXBOW_RADIUS_WAVES = 0.22
OXBOW_WIDTH = 0.8
OXBOW_MIN_WIDTH_M = 6.0
OXBOW_LEVEL_M = 2.0
OXBOW_OVER_M = 3.0


def _slow_noise(rng, s: np.ndarray, lo_m: float, hi_m: float, k: int = 3) -> np.ndarray:
    """Smooth noise along a river, about unit spread: `k` waves between `lo_m` and `hi_m` long."""
    out = np.zeros_like(s)
    for _ in range(k):
        out += np.sin(2.0 * np.pi * s / rng.uniform(lo_m, hi_m) + rng.uniform(0.0, 2.0 * np.pi))
    return out / math.sqrt(0.5 * k)


def meander(path, width, H: np.ndarray, grid: Grid, key: str, avoid: np.ndarray | None = None,
            step_m: float = 20.0, scale: float = 1.0, oxbows: list | None = None) -> np.ndarray:
    """A drawn river's line wandering between its drawn points, resampled every `step_m`.

    `width` is (width at the source, width at the mouth); `avoid` [(x, z), ...] the things the
    river keeps to its drawn line near; `key` seeds the wander, so a river always wanders the
    same way; `scale` is the atlas's `meander`, 0 for none. Where `oxbows` is a list, the loops
    the river has cut off are added to it as (points, width), each a crescent polyline."""
    import zlib

    p = np.asarray(path, dtype=np.float64)
    if p.shape[0] < 2:
        return p
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    s_v = np.concatenate([[0.0], np.cumsum(seg)])
    total = float(s_v[-1])
    if total < 2.0 * ANCHOR_M or scale <= 0.0:
        return paths.resample_polyline(p, step_m)
    ds = 5.0
    fine = paths.resample_polyline(p, ds)
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
    win = max(int(100.0 / ds), 1)
    kern = np.ones(2 * win + 1) / (2 * win + 1)
    hs = np.convolve(np.pad(h, win, mode="edge"), kern, mode="valid")
    grade = np.abs(np.gradient(hs, ds))
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
    # how the bends drift along the river: their length, their swing, their skew, the straights
    base_wave = np.maximum(MEANDER_WAVE_WIDTHS * w, MEANDER_WAVE_MIN_M)
    lw = float(base_wave.mean())
    n_wave = np.clip(_slow_noise(rng, s, 3.0 * lw, 8.0 * lw), -2.0, 2.0)
    n_swing = np.clip(_slow_noise(rng, s, 2.5 * lw, 6.0 * lw), -2.0, 2.0)
    n_straight = _slow_noise(rng, s, 5.0 * lw, 12.0 * lw)
    n_skew = np.clip(_slow_noise(rng, s, 2.0 * lw, 5.0 * lw), -2.0, 2.0)
    wave = base_wave * MEANDER_WAVE_VARY ** (0.6 * n_wave)
    swing = (MEANDER_SWING * np.clip(0.8 + 0.4 * n_swing, 0.2, 1.4)
             * smoothstep(-1.1, -0.55, n_straight) * flat * env * min(scale, 1.5))
    # no bend tighter than the river can turn: its apex radius is wave / (2 pi swing)
    swing = np.minimum(swing, wave / (2.0 * np.pi * np.maximum(MEANDER_RADIUS_WIDTHS * w, MEANDER_RADIUS_MIN_M)))
    skew = MEANDER_SKEW * n_skew
    # The curve, walked along its own length in the drawn line's frame: `u` is how far along the
    # drawn line it has come and `v` how far off it. Its heading swings by `swing`, its phase
    # turns once a wavelength, and a bend swinging past a right angle loops back on itself.
    step = 2.0
    us, vs = [0.0], [0.0]
    u = v = 0.0
    phase = float(ph[0])
    guard = int(8.0 * total / step) + 10
    while u < total and guard > 0:
        guard -= 1
        i = min(max(int(u / ds), 0), s.size - 1)
        om = float(swing[i])
        th = om * math.sin(phase) + float(skew[i]) * om * math.cos(3.0 * phase)
        u += step * math.cos(th)
        v += step * math.sin(th)
        phase += 2.0 * math.pi * step / float(wave[i])
        us.append(u)
        vs.append(v)
    uu = np.clip(np.asarray(us), 0.0, total)
    vv = np.asarray(vs)
    # take out the drift the swing leaves as it changes: only the bends are wanted
    sig = max(0.7 * float(np.median(wave)) / step, 1.0)
    vv = vv - ndimage.gaussian_filter1d(vv, sig, mode="nearest")
    env_u = np.interp(uu, s, env)
    w_u = np.interp(uu, s, w)
    flat_u = np.interp(uu, s, flat)
    sway_m = (WANDER_M + WANDER_M_PER_WIDTH * w_u) * (0.5 + 0.5 * flat_u)
    sway = sway_m * (0.65 * np.sin(2.0 * np.pi * uu / 430.0 + ph[2]) + 0.35 * np.sin(2.0 * np.pi * uu / 270.0 + ph[3]))
    # Into a drawn point the river eases back to its line over a taper as long as the bend beside
    # it is wide (ANCHOR_TAPER of it, and at least ANCHOR_M): squeezed to the point over a fixed
    # 50 m, a bend 60 m out made a V there, and on the chart the Outfall ran in sharp peaks.
    raw = vv + scale * sway
    taper = np.ones_like(uu)
    for sv in s_v[1:-1]:
        near = np.abs(uu - sv) < 0.5 * float(np.median(wave))
        reach = max(ANCHOR_M, ANCHOR_TAPER * float(np.max(np.abs(raw[near]))) if near.any() else 0.0)
        taper = np.minimum(taper, smoothstep(0.0, reach, np.abs(uu - sv)))
    off_u = raw * env_u * taper
    ku = np.clip(np.searchsorted(s_v, uu, side="right") - 1, 0, p.shape[0] - 2)
    base = p[ku] + (uu - s_v[ku])[:, None] * (p[ku + 1] - p[ku]) / np.maximum(seg[ku], 1e-9)[:, None]
    nrm = np.stack([-(p[ku + 1] - p[ku])[:, 1], (p[ku + 1] - p[ku])[:, 0]], axis=1) / np.maximum(seg[ku], 1e-9)[:, None]
    line = base + nrm * off_u[:, None]
    # every drawn point stays on the line: pin it where the curve first comes to it, and
    # resample the stretch between each pair
    at = np.array([int(np.argmax(uu >= sv - 1e-6)) for sv in s_v])
    at[0], at[-1] = 0, line.shape[0] - 1
    at = np.maximum.accumulate(at)
    line[at] = p
    cut = np.unique(at)
    out = [line[:1]]
    for a, b in zip(cut[:-1], cut[1:]):
        if b > a:
            out.append(paths.resample_polyline(line[a:b + 1], step_m)[1:])
    result = np.concatenate(out, axis=0)
    if oxbows is not None:
        # how far off the drawn line the river stands at each fine point, for the oxbows' side
        order = np.argsort(uu, kind="stable")
        off = np.interp(s, uu[order], off_u[order])
        oxbows.extend(_oxbows(rng, fine, normal, s, off, swing, wave, w, result, avoid,
                              flat, h, lambda q: sample_bilinear(H, grid, q[:, 0], q[:, 1])))
    return result


def _oxbows(rng, fine, normal, s, off, swing, wave, w, line, avoid, flat, h, ground) -> list:
    """The loops a river has cut off, beside its tightest bends (see `meander`): [(points, width)].

    Only on its floodplain: where the valley is flat, the river at least OXBOW_MIN_WIDTH_M wide,
    the land round the crescent level within OXBOW_LEVEL_M, and on the whole no more than
    OXBOW_OVER_M over the land by the river. Put anywhere, one was cut into a hillside beside the
    Larkbourne 20 m over the river."""
    out = []
    tight = (swing > OXBOW_SWING) & (flat > 0.95) & (w >= OXBOW_MIN_WIDTH_M)
    last = -1e9
    n = s.size
    dense = paths.resample_polyline(line, 4.0)
    i = 0
    while i < n:
        if not tight[i]:
            i += 1
            continue
        j = i
        while j < n and tight[j]:
            j += 1
        k = i + int(np.argmax(swing[i:j]))
        i = j
        draw = rng.uniform()
        if s[k] - last < OXBOW_APART_WAVES * wave[k] or draw > OXBOW_CHANCE:
            continue
        r = OXBOW_RADIUS_WAVES * float(wave[k])
        ow = OXBOW_WIDTH * float(w[k])
        # across the drawn line from where the river bulges, clear of its bank
        side = -1.0 if off[k] > 0 else 1.0
        c = fine[k] + normal[k] * (side * (r + float(w[k]) + OXBOW_WIDTH * float(w[k]) + 10.0))
        # a crescent round `c`, its open side toward the river
        toward = -side * normal[k]
        a0 = math.atan2(toward[1], toward[0])
        half_gap = math.radians(0.5 * (360.0 - OXBOW_ARC_DEG))
        ang = np.linspace(a0 + half_gap, a0 + 2.0 * math.pi - half_gap, max(int(OXBOW_ARC_DEG / 8.0), 8))
        # not a compass arc: its radius wanders by a sixth along it, as the old bend's did
        t_arc = np.linspace(0.0, 1.0, ang.size)
        rr = r * (1.0 + 0.1 * np.sin(2.0 * np.pi * (1.3 * t_arc + rng.uniform()))
                  + 0.06 * np.sin(2.0 * np.pi * (3.1 * t_arc + rng.uniform())))
        pts = np.stack([c[0] + rr * np.cos(ang), c[1] + rr * np.sin(ang)], axis=1)
        g = np.asarray(ground(pts), dtype=np.float64)
        if float(np.ptp(g)) > OXBOW_LEVEL_M or float(g.mean() - h[k]) > OXBOW_OVER_M:
            continue
        clear = float(np.min(np.hypot(pts[:, None, 0] - dense[None, :, 0], pts[:, None, 1] - dense[None, :, 1])))
        if clear < float(w[k]) + ow + 8.0:
            continue
        if avoid is not None and len(avoid):
            av = np.asarray(avoid, dtype=np.float64)
            if float(np.min(np.hypot(av[:, 0] - c[0], av[:, 1] - c[1]))) < r + ow + AVOID_NEAR_M:
                continue
        out.append((pts, ow))
        last = s[k]
    return out


## Down a steep stretch a river keeps a point every FALL_SAMPLE_M, not every 20 m, and its water
## follows the fall's own face. The channel is cut to the water (`carve_rivers`), and drawn
## straight between points 20 m apart down a cliff that stands between them it cut a trench of
## up to 20 m into the land above the cliff and built a levee of up to 8 m out over its foot,
## which the water's ribbon, wider than the channel, hung over. At 5 m the trench is the
## channel's own depth and the levee under 3 m (measured on 2 m and 4 m texels). A stretch is
## steep where the land falls faster than FALL_GRADE over 20 m. Steps of pools and sheets were
## tried and are worse: a drop narrower than a texel cannot be carved, and the water hung over
## every lip.
FALL_GRADE = 0.3
FALL_SAMPLE_M = 5.0
RIVER_STEP_M = 10.0
## the least a river's water falls, a metre along it
MIN_FALL_PER_M = 0.05 / 20.0


def fall_points(fine: np.ndarray, h_fine: np.ndarray) -> np.ndarray:
    """Which of a river's points, every FALL_SAMPLE_M along it, it keeps: one every RIVER_STEP_M,
    the last, and every one down a stretch falling faster than FALL_GRADE."""
    k = fine.shape[0]
    per = max(int(round(RIVER_STEP_M / FALL_SAMPLE_M)), 1)
    keep = np.zeros(k, dtype=bool)
    keep[::per] = True
    keep[-1] = True
    if k > per:
        drop = h_fine[:-per] - h_fine[per:]
        for i in np.nonzero(np.abs(drop) > FALL_GRADE * RIVER_STEP_M)[0]:
            keep[i:i + per + 1] = True
    return np.nonzero(keep)[0]


## A fall, for the game to draw as one (a sheet, foam at the lip, spray and a pool at the foot)
## rather than as the ribbon laid down its face: wherever the water falls faster than FALL_DROP_GRADE
## between two of its points, a run of such steps falling FALL_MIN_HEIGHT_M or more is a fall. One
## falling POOL_MIN_HEIGHT_M or more has a plunge pool at its foot, POOL_RADIUS_PER_M of its height
## across (between POOL_RADIUS_WIDTHS of the river's widths), cut into the land as a basin of its
## own at the foot's level.
FALL_DROP_GRADE = 1.0
FALL_MIN_HEIGHT_M = 2.0
POOL_MIN_HEIGHT_M = 6.0
POOL_RADIUS_PER_M = 0.3
POOL_RADIUS_WIDTHS = (1.2, 3.0)
## a fall at least FALL_SHEER high for each metre it runs is a `fall` (a sheet), and a shallower
## one a `cascade` (water down a stepped face); a pool reaches no further than where the river
## has fallen POOL_LIP_DROP_M below it, a lip it spills over and not a dam
FALL_SHEER = 2.0
POOL_LIP_DROP_M = 1.0


def find_falls(river_id: str, points: np.ndarray, surface: np.ndarray, width: np.ndarray) -> tuple:
    """A river's falls, as rivers.json writes them, and the pools under them (Rivers).

    Each fall is {"top": [x, y, z], "foot": [x, y, z], "height_m", "width_m", "run_m",
    "facing_deg"} and, under a big one, "pool": {"centre": [x, y, z], "radius_m", "depth_m"}.
    `top` and `foot` are on the water's surface at the lip and at the foot; `facing_deg` is the
    bearing the face looks out along, downstream (from +z toward +x, as the door plan measures)."""
    p = np.asarray(points, dtype=np.float64)
    s = np.asarray(surface, dtype=np.float64)
    if p.shape[0] < 2:
        return [], []
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    drop = s[:-1] - s[1:]
    steep = drop > FALL_DROP_GRADE * np.maximum(seg, 1e-6)
    falls, pools = [], []
    i = 0
    while i < steep.size:
        if not steep[i]:
            i += 1
            continue
        j = i
        while j < steep.size and steep[j]:
            j += 1
        a, b = i, j                                 # the fall runs from point a to point b
        i = j
        height = float(s[a] - s[b])
        if height < FALL_MIN_HEIGHT_M:
            continue
        d = p[b] - p[a]
        run = float(np.linalg.norm(d))
        if run < 1e-6:
            d = p[min(b + 1, p.shape[0] - 1)] - p[max(a - 1, 0)]
        u = d / max(float(np.linalg.norm(d)), 1e-6)
        fall = {"top": [round(float(p[a, 0]), 2), round(float(s[a]), 2), round(float(p[a, 1]), 2)],
                "foot": [round(float(p[b, 0]), 2), round(float(s[b]), 2), round(float(p[b, 1]), 2)],
                "height_m": round(height, 2), "width_m": round(float(width[a]), 2),
                "run_m": round(run, 2),
                "facing_deg": round(float(math.degrees(math.atan2(u[0], u[1])) % 360.0), 1),
                "kind": "fall" if height >= FALL_SHEER * run else "cascade"}
        # A pool is a basin at the foot's level, carved as its own channel: reaching over the lip
        # of the next drop down it would hold the river's bed up at its level there, a dam.
        run_on = np.concatenate([[0.0], np.cumsum(seg[b:])])
        below = np.nonzero(s[b:] < s[b] - POOL_LIP_DROP_M)[0]
        room = float(run_on[below[0]]) if below.size else float(run_on[-1])
        wb = float(width[b])
        r = float(np.clip(POOL_RADIUS_PER_M * height, POOL_RADIUS_WIDTHS[0] * wb, POOL_RADIUS_WIDTHS[1] * wb))
        r = min(r, room / 1.1)
        if height >= POOL_MIN_HEIGHT_M and r >= POOL_RADIUS_WIDTHS[0] * wb:
            c = p[b] + u * 0.6 * r
            # a stadium along the flow as wide as the pool: carved as a channel 2r wide
            ends = np.stack([p[b] + u * 0.1 * r, p[b] + u * 1.1 * r])
            pool = River(id="%s/pool_%d" % (river_id, len(pools) + 1), points=ends,
                         width=np.full(2, 2.0 * r, dtype=np.float32),
                         surface=np.full(2, float(s[b]), dtype=np.float32))
            pools.append(pool)
            fall["pool"] = {"centre": [round(float(c[0]), 2), round(float(s[b]), 2), round(float(c[1]), 2)],
                            "radius_m": round(r, 2), "depth_m": round(1.1 + 0.1 * 2.0 * r, 2)}
        falls.append(fall)
    return falls, pools


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
        cut_off: list = []
        pts = meander(rv["path"], rv["width_m"], H, grid, rv["id"], keep_arr,
                      step_m=FALL_SAMPLE_M, scale=float(rv.get("meander", 1.0)), oxbows=cut_off)
        if pts.shape[0] < 2:
            continue
        if into is not None and into in by_id:
            # a tributary ends on the river it joins, wherever that river now runs
            other = by_id[into]
            k = int(np.argmin(np.hypot(other.points[:, 0] - pts[-1, 0], other.points[:, 1] - pts[-1, 1])))
            pts[-1] = other.points[k]
        # the land along it every FALL_SAMPLE_M, and the points it keeps (`fall_points`)
        from .grid import sample_bilinear
        fine = paths.resample_polyline(pts, FALL_SAMPLE_M)
        h_fine = sample_bilinear(H, grid, fine[:, 0], fine[:, 1]).astype(np.float64)
        kept = fall_points(fine, h_fine)
        pts, h_along = fine[kept], h_fine[kept]
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
        seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
        run = np.concatenate([[0.0], np.cumsum(seg)])
        # at least 0.05 m of fall every 20 m, as when the points were all 20 m apart
        min_drop = MIN_FALL_PER_M * seg
        end = min(end, start - float(min_drop.sum()))
        surf = _monotone_profile(h_along, start, end, min_drop)
        t = run / max(float(run[-1]), 1e-6)
        w0, w1 = (float(v) for v in rv["width_m"])
        width = (w0 + (w1 - w0) * t ** 0.7).astype(np.float32)
        river = River(id=rv["id"], points=pts, width=width, surface=surf, valley_m=rv.get("valley_m"))
        river.falls, river.pools = find_falls(rv["id"], pts, surf, width)
        # an oxbow stands at the river's level beside it
        for n_ox, (opts, ow) in enumerate(cut_off):
            c = opts.mean(axis=0)
            k = int(np.argmin(np.hypot(pts[:, 0] - c[0], pts[:, 1] - c[1])))
            river.oxbows.append(River(id="%s/oxbow_%d" % (rv["id"], n_ox + 1), points=opts,
                                      width=np.full(opts.shape[0], ow, dtype=np.float32),
                                      surface=np.full(opts.shape[0], float(surf[k]), dtype=np.float32)))
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
        paths.rasterise_polyline(r.points, grid, value=r.surface, out_mask=mask, out_value=surf, at_centre=True)
        # how far down the river from its source each point of it is
        run = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(r.points, axis=0), axis=1))])
        paths.rasterise_polyline(r.points, grid, value=run, out_mask=mask, out_value=down, at_centre=True)
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


def with_oxbows(rivers: list) -> list:
    """The rivers, then every oxbow and plunge pool beside them."""
    return list(rivers) + [ox for r in rivers for ox in list(getattr(r, "oxbows", [])) + list(getattr(r, "pools", []))]


def carve_rivers(grid: Grid, H: np.ndarray, rivers: list, bank: NoiseBank):
    """Cut channels and banks. Returns (heights, distance to centre line, surface level, width)."""
    n = grid.n
    mask = np.zeros((n, n), dtype=bool)
    surf = np.zeros((n, n), dtype=np.float32)
    wide = np.zeros((n, n), dtype=np.float32)
    for r in with_oxbows(rivers):
        paths.rasterise_polyline(r.points, grid, value=r.surface, out_mask=mask, out_value=surf, at_centre=True)
        paths.rasterise_polyline(r.points, grid, value=r.width, out_mask=mask, out_value=wide, at_centre=True)
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
               table: np.ndarray | None, extra: np.ndarray | None = None) -> WaterResult:
    """`lake` is the atlas's lakes (geography.Waters) and `sea` the sea at this grid; `table` the
    marsh's water table (`marsh_table`), for the pools in a delta province; `extra` (bool) the
    marsh's creeks and small pools (shores.marsh), which stand at the table too."""
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
    add = None
    if extra is not None and table is not None:
        add = extra & ~mask
        level = np.where(add, table, level)
        mask |= add
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
    # an oxbow's water is still
    ox = [o for r in rivers for o in getattr(r, "oxbows", [])]
    if ox:
        still = np.zeros((n, n), dtype=bool)
        for o in ox:
            paths.rasterise_polyline(o.points, grid, out_mask=still)
        d_ox = ndimage.distance_transform_edt(~still) * grid.spacing
        reach = max(float(max(np.max(o.width) for o in ox)) * 0.5, grid.spacing) + grid.spacing
        flow[(d_ox <= reach) & (d_ox < river_d + 0.5 * grid.spacing)] = 128
    return WaterResult(rivers=rivers, mask=mask.astype(np.uint8), level=level, flow=flow,
                       river_dist=river_d, creeks=None if add is None else (add & mask))


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
