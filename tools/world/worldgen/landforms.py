"""Landforms: the features a person walking notices, laid on a province because the atlas says so.

The drop test (DESIGN 10.1) reads a region's landform with the colour taken out -- its
skyline, how rugged it is, where the detail sits down the frame -- and on the 42-shot sheet the
old procedural world read 0.12 to 0.31 against 0.17 for chance and a bar of 0.55: the regions
differed by the colour of the ground, not by its shape. These are the terms that give a country
its own shape at the scale a person walking sees (fifty to three hundred metres off, a few metres
to a few tens of metres of relief). Each is named in SCHEMA.md; a province lists the ones it has
(`landform` in tools/world/atlas/atlas.json) and gets them in proportion to its weight.

* `raised_beaches` -- a lake that falls leaves its old shorelines: level benches at the heights
  it stood at, each backed by the cliff it cut. `dune_ridges` -- on the open shores, a strandplain
  of wind-built ridges parallel to the water, a steep face to it and a long back.
* `levees` -- rivers bank themselves with silt, three metres and more over a marsh, the only
  dry lines in the country. `oxbows` -- the loops a river has abandoned, crescent pools with
  low rims.
* `granite_stair` -- old granite does not ramp, it goes up in benches. `tors` -- rock piles
  on the lips of the benches.
* `limestone_scars` -- the edges of level beds, cliff bands at the same heights across every
  hillside. `shakeholes` -- the sinks the water went down, pocking the moor.
* `buried_streets` -- the Builders' city under the ash: straight sunken streets on one grid
  and the blocks mounded between them, flat-topped and straight-sided as no natural ground is.
* `lynchets` -- a slope ploughed along the contour, stepped into a flight of banks.
  `barrows` -- round mounds in lines behind a crest.

Each is made from the province's own ground with no reference to where anything stands, and
then three masks keep what the build has already composed. The ground under a place and around
it is left as it was: a pad flattens to the median of whatever is under it, so a terrace tread
through a POI would move the height its sightlines are aimed from. Nothing may rise along an
authored sightline (nine of the 87 lines clear the ground by under half a metre); lowering is
free everywhere. And the roads keep the ground they were laid on: the world build adds the
landforms last, held off every road out past its carve and brought back over thirty metres
(`road_clear`). Laid first, they sent the router straight over a limestone scar from Gullhithe
to Kharrow Hold and put the Grandfather Hollow road along the lip of a granite step, nine metres
above the ground either side. A road through a scar goes through a break in it.
"""
from __future__ import annotations

import math
import zlib

import numpy as np

from .grid import smoothstep
from .noise import terrace


def _stamp(out: np.ndarray, ctx, cx: float, cz: float, radius: float, fn) -> None:
    """Add fn(distance) into `out` in a window around (cx, cz); fn is zero past `radius`."""
    g = ctx.grid
    n = g.n
    j = int(round((cx - g.x0) / g.spacing))
    i = int(round((cz - g.z0) / g.spacing))
    k = int(radius / g.spacing) + 2
    i0, i1 = max(0, i - k), min(n, i + k + 1)
    j0, j1 = max(0, j - k), min(n, j + k + 1)
    if i0 >= i1 or j0 >= j1:
        return
    dx = ctx.X[:, j0:j1] - cx
    dz = ctx.Z[i0:i1, :] - cz
    out[i0:i1, j0:j1] += fn(np.sqrt(dx * dx + dz * dz), dx, dz).astype(np.float32)


def _rng(ctx, r, name: str) -> np.random.Generator:
    """Seeded by the province and the landform, never by where either is listed."""
    salt = zlib.crc32(("%s/%s" % (r.province or r.id, name)).encode("utf-8"))
    return np.random.default_rng(np.random.SeedSequence([ctx.bank.seed, salt]))


def _spots(ctx, r, rng, count: int, tries: int = 12):
    """Up to `count` random points well inside province `r` (weight over a half)."""
    g = ctx.grid
    w = ctx.rf.weights[r.index]
    idx = np.argwhere(w > 0.5)
    if idx.size == 0:
        return []
    out = []
    for k in rng.integers(0, idx.shape[0], count * tries)[:count * tries]:
        if len(out) >= count:
            break
        i, j = idx[k]
        out.append((g.x0 + (j + rng.uniform(-0.5, 0.5)) * g.spacing, g.z0 + (i + rng.uniform(-0.5, 0.5)) * g.spacing))
    return out


def _steepness(ctx, h: np.ndarray, smooth_m: float = 0.0) -> np.ndarray:
    """Slope magnitude; `smooth_m` averages the land first, so the answer is the hillside's and
    not every hummock's (a factor that multiplies a landform must not be speckled)."""
    if smooth_m > 0.0:
        from scipy import ndimage
        h = ndimage.gaussian_filter(h, smooth_m / ctx.grid.spacing, mode="nearest")
    return np.hypot(*np.gradient(h, ctx.grid.spacing))


# --- by the water ------------------------------------------------------------------------------

## The raised beaches: five old shorelines, 3.5 to 30 m above the lake, each a level bench
## backed by the fossil cliff the water cut when it stood there -- the cliff a seventh of the
## rise to the next shoreline, so on a one-in-ten shore a bench forty to seventy metres deep
## ends in a bank of five to eight metres at about one in one. They only ever lower the land.
## The strandplain: ridges 105 m apart and up to nine metres high, parallel to the shore on its
## open stretches, each a long back slope and a steep face to the water, which is what the wind
## builds.
SHORELINES_M = (3.5, 8.5, 14.5, 21.5, 30.0)
SHORE_CLIFF = 0.14
RIDGE_SPACING_M = 105.0
RIDGE_HEIGHT_M = 9.0


def _levels(h: np.ndarray, levels, riser: float) -> np.ndarray:
    """Terraces at the given heights: between two levels the ground is a bench at the lower one
    and a riser (`riser` of the interval) up to the next. Below the first and above the last,
    unchanged. `levels` may be arrays (a level per texel)."""
    out = h.astype(np.float32, copy=True)
    for lo, hi in zip(levels[:-1], levels[1:]):
        inside = (h >= lo) & (h < hi)
        t = (h - lo) / (hi - lo)
        s = np.clip((t - (1.0 - riser)) / riser, 0.0, 1.0)
        s = s * s * (3.0 - 2.0 * s)
        out = np.where(inside, lo + (hi - lo) * s, out)
    return out


def raised_beaches(ctx, h: np.ndarray, r) -> np.ndarray:
    lk = ctx.lake
    band = smoothstep(90.0, 200.0, lk.sd) * (1.0 - smoothstep(1100.0, 1500.0, lk.sd))
    if not (lk.lake_id >= 0).any():
        return np.zeros_like(h)
    levels = [lk.level + v for v in SHORELINES_M]
    keep_off = smoothstep(40.0, 120.0, lk.island_sd) * (1.0 - np.clip(lk.causeway * 3.0, 0.0, 1.0))
    return ((_levels(h, levels, SHORE_CLIFF) - h) * band * keep_off).astype(np.float32)


def dune_ridges(ctx, h: np.ndarray, r) -> np.ndarray:
    lk = ctx.lake
    if not (lk.lake_id >= 0).any():
        return np.zeros_like(h)
    # on the shores that are neither a cliff shore nor a reed shelf
    open_shore = (1.0 - lk.cliffness) * (1.0 - lk.reediness)
    s = lk.sd + 22.0 * ctx.f(213, 2.0, 150, 600)
    # a sawtooth rounded at the crest: the face to the water is a third of the period, the back
    # slope the rest, so each ridge has a lee and the row reads as built by the wind
    ph = (s / RIDGE_SPACING_M) % 1.0
    tooth = np.where(ph < 0.3, ph / 0.3, (1.0 - ph) / 0.7)
    ridge = smoothstep(0.0, 1.0, tooth) ** 1.4
    stretch = smoothstep(-0.55, 0.25, ctx.f(214, 2.0, 300, 1200))
    fade = smoothstep(30.0, 70.0, lk.sd) * (1.0 - smoothstep(620.0, 860.0, lk.sd))
    keep_off = smoothstep(40.0, 120.0, lk.island_sd) * (1.0 - np.clip(lk.causeway * 3.0, 0.0, 1.0))
    return (RIDGE_HEIGHT_M * ridge * stretch * open_shore * fade * keep_off).astype(np.float32)


## Levees three and a half metres over the land beside the river -- twice the height of a man
## standing on the peat, so from anywhere on a marsh the skyline is a bank -- a little way off
## the channel on either side. And cut-off meanders, loops 70 to 170 m across with a rim of a
## metre and a quarter, cut to below the marsh's water table.
LEVEE_M = 3.5
LEVEE_OFF_M = 16.0
LEVEE_HALF_M = 9.0
OXBOWS_PER_KM2 = 2.2
OXBOW_RIM_M = 1.25


def levees(ctx, h: np.ndarray, r) -> np.ndarray:
    from .geography import line_field

    out = np.zeros_like(h, dtype=np.float32)
    for rv in getattr(ctx, "rivers", []) or []:
        w0, w1 = (float(v) for v in rv["width_m"])
        reach = 0.5 * max(w0, w1) + LEVEE_OFF_M + 3.0 * LEVEE_HALF_M
        lf = line_field(ctx.grid, rv["path"], reach)
        i0, i1, j0, j1 = lf.window
        half = 0.5 * (w0 + (w1 - w0) * lf.t ** 0.7)
        bank = LEVEE_M * np.exp(-((lf.d - half - LEVEE_OFF_M) / LEVEE_HALF_M) ** 2)
        # the silt dies out toward the mouth, where the river meets the sea's flats
        bank *= 1.0 - smoothstep(0.85, 1.0, lf.t)
        out[i0:i1, j0:j1] = np.maximum(out[i0:i1, j0:j1], bank)
    return out


def oxbows(ctx, h: np.ndarray, r) -> np.ndarray:
    rng = _rng(ctx, r, "oxbows")
    area_km2 = float(ctx.rf.weights[r.index].sum()) * ctx.grid.spacing ** 2 / 1e6
    count = int(round(OXBOWS_PER_KM2 * area_km2))
    bowl = np.zeros_like(h, dtype=np.float32)
    rim = np.zeros_like(h, dtype=np.float32)
    for cx, cz in _spots(ctx, r, rng, count):
        radius = rng.uniform(70.0, 170.0)
        width = rng.uniform(14.0, 24.0)
        a0 = rng.uniform(0.0, 2.0 * math.pi)
        extent = rng.uniform(math.radians(200.0), math.radians(290.0))

        def ends(dx, dz, a0=a0, extent=extent):
            # soft ends, so the loop tapers where the channel broke through it
            ang = (np.arctan2(dz, dx) - a0) % (2.0 * math.pi)
            return smoothstep(0.0, 0.35, ang) * (1.0 - smoothstep(extent - 0.35, extent, ang))

        def water(d, dx, dz, radius=radius, width=width):
            across = np.abs(d - radius)
            return ends(dx, dz) * np.clip(1.0 - (across / (0.5 * width)) ** 2, 0.0, 1.0) ** 0.5

        def bank(d, dx, dz, radius=radius, width=width):
            across = np.abs(d - radius)
            return ends(dx, dz) * OXBOW_RIM_M * np.exp(-((across - 0.5 * width - 6.0) / 4.5) ** 2)

        _stamp(bowl, ctx, cx, cz, radius + width + 16.0, water)
        _stamp(rim, ctx, cx, cz, radius + width + 16.0, bank)
    bowl = np.clip(bowl, 0.0, 1.0)
    # a crescent is cut to a floor a little over the water table, wherever the ground stands
    floor = float(r.base_height) + 0.35
    cut = bowl * np.clip(floor - h, -3.0, 0.0)
    return (rim * (1.0 - bowl) + cut).astype(np.float32)


# --- on the granite ----------------------------------------------------------------------------

STAIR_STEP_M = 18.0
STAIR_RISER = 0.22
## A tor is a pile of rock, not a hill: up to fourteen metres, which is what it takes to stand
## out of a wood whose canopy is fifteen.
TOR_M = 14.0
TOR_FIELD = 0.75
## A `terrace` step on ground of slope s has a riser of slope s / riser-fraction, as wide as
## riser-fraction * step / s. Past a slope of about a half the riser is a cliff a few metres wide,
## narrower than the heightmap can hold, so the riser widens instead: never steeper than
## `RISER_SLOPE_MAX` -- sharp treads on the gentle ground, crags on the steep, and on ground
## steeper than the crags themselves no stair.
RISER_SLOPE_MAX = 1.6


def _terrace_var(h: np.ndarray, step: float, riser: np.ndarray) -> np.ndarray:
    """`noise.terrace` with a riser fraction per texel."""
    q = h / step
    base = np.floor(q)
    frac = q - base
    t = np.clip((frac - (1.0 - riser)) / riser, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    return ((base + t) * step).astype(np.float32)


def granite_stair(ctx, h: np.ndarray, r) -> np.ndarray:
    # a terrace only ever lowers (each tread is the bottom of its step); raised by half a tread
    # the stair cuts and fills about equally, and no place is left standing on a plinth
    slope = _steepness(ctx, h, smooth_m=16.0)
    riser = np.clip(slope / RISER_SLOPE_MAX, STAIR_RISER, 1.0)
    off = STAIR_STEP_M * (1.0 - riser) * 0.5
    return (_terrace_var(h, STAIR_STEP_M, riser) + off - h).astype(np.float32)


def tors(ctx, h: np.ndarray, r) -> np.ndarray:
    # the lip of each bench is the top of the riser below it: where h is a whole number of steps
    q = h / STAIR_STEP_M
    frac = q - np.floor(q)
    near_whole = np.minimum(frac, 1.0 - frac)
    # a tor is as deep as it is long, so the lip it stands on is taken wide, and the pile capped
    lip = np.exp(-(near_whole / 0.11) ** 2)
    knobs = np.clip(ctx.f(148, 1.8, 25, 120) - TOR_FIELD, 0.0, 1.0) ** 1.2
    return (TOR_M * knobs * lip).astype(np.float32)


# --- in the limestone ---------------------------------------------------------------------------

## Limestone scars are the edges of the beds, and the beds lie level: a scar runs along the
## valley side at one height for kilometres, and the next one up runs at its own. So the scars
## are six levels, 65 m apart from 235 m, each a cliff band -- a pavement bench above it and a
## scree foot below -- running wherever the ground is sloping and the bed is exposed, which it
## is in runs of kilometres.
SCAR_LEVELS_M = (235.0, 300.0, 365.0, 430.0, 495.0, 560.0)
SCAR_HALF_M = 12.0
SCAR_FACE = (0.45, 0.75)
SCAR_SLOPE = (0.10, 0.22, 1.25, 1.7)
SHAKEHOLES_PER_KM2 = 45.0


def _scar(h: np.ndarray, level: float, half: float, face: tuple) -> np.ndarray:
    """One cliff band at `level`: the window [level - half, level + half] of the land's height
    becomes a foot at its bottom, a face between `face` fractions of it, and a bench at its top."""
    t = np.clip((h - (level - half)) / (2.0 * half), 0.0, 1.0)
    s = np.clip((t - face[0]) / (face[1] - face[0]), 0.0, 1.0)
    s = s * s * (3.0 - 2.0 * s)
    inside = (h > level - half) & (h < level + half)
    return np.where(inside, (level - half) + 2.0 * half * s - h, 0.0).astype(np.float32)


def limestone_scars(ctx, h: np.ndarray, r) -> np.ndarray:
    slope = _steepness(ctx, h, smooth_m=16.0)
    lo0, lo1, hi0, hi1 = SCAR_SLOPE
    on_slope = smoothstep(lo0, lo1, slope) * (1.0 - smoothstep(hi0, hi1, slope))
    exposed = smoothstep(-0.9, -0.3, ctx.f(154, 2.0, 1200, 4200))
    scars = np.zeros_like(h, dtype=np.float32)
    for k, level in enumerate(SCAR_LEVELS_M):
        bed = smoothstep(-0.9, -0.3, ctx.f(740 + k, 2.0, 900, 3600))
        scars += _scar(h, level, SCAR_HALF_M, SCAR_FACE) * bed
    return (scars * on_slope * exposed).astype(np.float32)


def shakeholes(ctx, h: np.ndarray, r) -> np.ndarray:
    slope = _steepness(ctx, h, smooth_m=16.0)
    moor = (1.0 - smoothstep(0.18, 0.30, slope))
    fields = smoothstep(0.0, 0.6, ctx.f(159, 2.0, 250, 900))
    rng = _rng(ctx, r, "shakeholes")
    area_km2 = float(ctx.rf.weights[r.index].sum()) * ctx.grid.spacing ** 2 / 1e6
    out = np.zeros_like(h, dtype=np.float32)
    g = ctx.grid
    for cx, cz in _spots(ctx, r, rng, int(SHAKEHOLES_PER_KM2 * area_km2 * 3)):
        j = int(round((cx - g.x0) / g.spacing))
        i = int(round((cz - g.z0) / g.spacing))
        if not (0 <= i < g.n and 0 <= j < g.n) or rng.random() > float(moor[i, j] * fields[i, j]):
            continue
        radius = rng.uniform(10.0, 26.0)
        depth = rng.uniform(3.5, 8.0) * radius / 16.0

        def bowl(d, dx, dz, radius=radius, depth=depth):
            return -depth * np.clip(1.0 - (d / radius) ** 2, 0.0, 1.0) ** 1.4

        _stamp(out, ctx, cx, cz, radius, bowl)
    return out


# --- under the ash -------------------------------------------------------------------------------

## The street grid: blocks 96 by 72 m, on the province's grain (23 degrees without one), streets
## 12 m across sunk 4 m, with four-metre banks; and each block between them a flat-topped mound of
## what the houses fell into, up to 5.5 m -- nine and a half metres from a street's floor to the
## block beside it, which from the floor of one is a skyline.
GRID_BEARING = 23.0
GRID_M = (96.0, 72.0)
STREET_M = 12.0
STREET_DEPTH_M = 4.0
BLOCK_M = 5.5


def buried_streets(ctx, h: np.ndarray, r) -> np.ndarray:
    th = math.radians(r.grain_deg if r.grain_deg is not None else GRID_BEARING)
    u = ctx.X * math.cos(th) + ctx.Z * math.sin(th)
    v = -ctx.X * math.sin(th) + ctx.Z * math.cos(th)
    streets = np.zeros_like(h)
    inside = np.ones_like(h)
    for coord, period, off in ((u, GRID_M[0], 31.0), (v, GRID_M[1], 17.0)):
        d = np.abs(((coord + off + 0.5 * period) % period) - 0.5 * period)
        streets = np.maximum(streets, 1.0 - smoothstep(0.5 * STREET_M, 0.5 * STREET_M + 4.0, d))
        inside = np.minimum(inside, smoothstep(0.5 * STREET_M + 4.0, 0.5 * STREET_M + 12.0, d))
    # not every block has the same depth of rubble in it, and the city did not cover all of it
    rubble = 0.55 + 0.45 * np.tanh(ctx.f(169, 1.8, 70, 260))
    city = smoothstep(-0.6, 0.1, ctx.f(168, 2.0, 900, 2600))
    return ((BLOCK_M * rubble * inside - STREET_DEPTH_M * streets) * city).astype(np.float32)


# --- on the downs --------------------------------------------------------------------------------

BARROWS_PER_KM2 = 0.9
LYNCHET_STEP_M = 4.5
LYNCHET_RISER = 0.28


def lynchets(ctx, h: np.ndarray, r) -> np.ndarray:
    # where a slope was ploughed along the contour for long enough, the soil crept down against
    # each strip and the hillside became a flight of banks; in flights, not everywhere
    slope = np.hypot(*np.gradient(h, ctx.grid.spacing))
    steep = smoothstep(0.10, 0.18, slope) * (1.0 - smoothstep(0.45, 0.60, slope))
    flights = smoothstep(0.1, 0.6, ctx.f(126, 2.0, 200, 900))
    return ((terrace(h, LYNCHET_STEP_M, LYNCHET_RISER) - h) * steep * flights).astype(np.float32)


def barrows(ctx, h: np.ndarray, r) -> np.ndarray:
    from scipy import ndimage

    g = ctx.grid
    # the crests: ground standing over what is within three hundred metres of it, and gentle
    around = ndimage.uniform_filter(h, size=max(int(300.0 / g.spacing), 3), mode="nearest")
    slope = np.hypot(*np.gradient(h, g.spacing))
    crest = (h - around > 6.0) & (slope < 0.12) & (ctx.rf.weights[r.index] > 0.85)
    idx = np.argwhere(crest)
    out = np.zeros_like(h, dtype=np.float32)
    if idx.size == 0:
        return out
    rng = _rng(ctx, r, "barrows")
    area_km2 = float(ctx.rf.weights[r.index].sum()) * g.spacing ** 2 / 1e6
    groups = max(int(round(BARROWS_PER_KM2 * area_km2)), 1)
    gz, gx = np.gradient(h, g.spacing)
    chosen: list = []
    for k in rng.permutation(idx.shape[0])[:4000]:
        if len(chosen) >= groups:
            break
        i, j = idx[k]
        x = g.x0 + j * g.spacing
        z = g.z0 + i * g.spacing
        if any(math.hypot(x - a, z - b) < 420.0 for a, b in chosen):
            continue
        chosen.append((x, z))
        # a line of them along the crest: across the fall of the ground
        ux, uz = -float(gz[i, j]), float(gx[i, j])
        nrm = math.hypot(ux, uz)
        if nrm < 1e-6:
            a = rng.uniform(0.0, math.pi)
            ux, uz = math.cos(a), math.sin(a)
        else:
            ux, uz = ux / nrm, uz / nrm
        count = int(rng.integers(3, 7))
        gap = rng.uniform(42.0, 66.0)
        for m in range(count):
            t = (m - 0.5 * (count - 1)) * gap
            bx = x + ux * t + rng.normal(0.0, 6.0)
            bz = z + uz * t + rng.normal(0.0, 6.0)
            radius = rng.uniform(18.0, 30.0)
            height = rng.uniform(4.5, 8.0)

            def mound(d, dx, dz, radius=radius, height=height):
                body = height * np.clip(1.0 - (d / radius) ** 2, 0.0, 1.0) ** 1.5
                ditch = -0.5 * np.exp(-((d - radius - 2.0) / 1.6) ** 2)
                return body + ditch

            _stamp(out, ctx, bx, bz, radius + 8.0, mound)
    return out


TERMS = {
    "raised_beaches": raised_beaches, "dune_ridges": dune_ridges,
    "levees": levees, "oxbows": oxbows,
    "granite_stair": granite_stair, "tors": tors,
    "limestone_scars": limestone_scars, "shakeholes": shakeholes,
    "buried_streets": buried_streets,
    "lynchets": lynchets, "barrows": barrows,
}


def protection(ctx, discs: list, lines: list) -> tuple:
    """(keep, no_raise): how much of the old ground to keep, and where nothing may rise.

    `discs` is [(x, z, radius)] for every place's pad; the ground is kept whole out to 1.3 pad
    radii and the landform comes back by 2.4. `lines` is [(x0, z0, x1, z1)] for every authored
    sightline; within 14 m of one, a landform may lower the ground but not raise it.
    """
    g = ctx.grid
    keep = np.zeros((g.n, g.n), dtype=np.float32)
    for x, z, radius in discs:
        def disc(d, dx, dz, radius=radius):
            return 1.0 - smoothstep(1.3 * radius, 2.4 * radius, d)

        tmp = np.zeros_like(keep)
        _stamp(tmp, ctx, x, z, 2.4 * radius + 4.0, disc)
        np.maximum(keep, tmp, out=keep)
    return keep, line_mask(g, lines, LINE_CORRIDOR_M)


## How far either side of an authored sightline nothing may be raised: landforms here, and
## road fill in `roads.plan_roads`.
LINE_CORRIDOR_M = 14.0


def line_mask(g, lines: list, width_m: float) -> np.ndarray:
    """bool [n, n]: within `width_m` of any of the segments [(x0, z0, x1, z1)] on grid `g`."""
    out = np.zeros((g.n, g.n), dtype=bool)
    for x0, z0, x1, z1 in lines:
        length = math.hypot(x1 - x0, z1 - z0)
        steps = max(int(length / (g.spacing * 0.5)), 2)
        t = np.linspace(0.0, 1.0, steps)
        j = np.clip(np.rint((x0 + (x1 - x0) * t - g.x0) / g.spacing).astype(np.int64), 0, g.n - 1)
        i = np.clip(np.rint((z0 + (z1 - z0) * t - g.z0) / g.spacing).astype(np.int64), 0, g.n - 1)
        out[i, j] = True
    if out.any():
        from scipy import ndimage
        out = ndimage.distance_transform_edt(~out) * g.spacing <= width_m
    return out


## How far past its carve a road's ground is held as the road was laid on it, and over how
## many metres more the landform comes back (`road_clear`).
ROAD_CLEAR_M = 4.0
ROAD_FADE_M = 30.0


def road_clear(road_d: np.ndarray, road_w: np.ndarray) -> np.ndarray:
    """float32 [n, n]: how much of the landform may stand here, 0 on a road and 1 clear of it.

    `road_d` and `road_w` are `roads.carve_roads`' distance to the nearest road's centre line
    and that road's width. The ground is held out to the road's half width, its shoulder
    (`roads.shoulder_m`) and ROAD_CLEAR_M, so everything the road was graded and carved
    against, and the land either side of it that the road tests read, is the land it was laid
    on; the landform returns by ROAD_FADE_M further.
    """
    from .roads import shoulder_m

    w = np.asarray(road_w, dtype=np.float32)
    inner = np.empty_like(w)
    for width in np.unique(w):              # a handful of road widths, and 0 where there is none
        inner[w == width] = 0.5 * float(width) + shoulder_m(float(width)) + ROAD_CLEAR_M
    return smoothstep(inner, inner + ROAD_FADE_M, np.asarray(road_d, dtype=np.float32)).astype(np.float32)


## how far from a river's centre line a landform may not dig below its water
RIVER_GUARD_M = 60.0


def river_guard(H: np.ndarray, delta: np.ndarray, river_d: np.ndarray, river_surf: np.ndarray,
                river_w: np.ndarray) -> np.ndarray:
    """`delta` with no pit dug below a river's water beside it.

    As beside a lake: within RIVER_GUARD_M of a river (and its half width), a landform lowers the
    land no further than half a metre over the water of the nearest river, and never raises it
    for that. A limestone scar cut across the Brindle Beck's head took its bed 9.7 m under the
    water, and the river's ribbon hung over the hole, 10 m up at its worst.
    """
    near = river_d <= river_w * 0.5 + RIVER_GUARD_M
    floor = np.minimum(H, river_surf + 0.5) - H
    return np.where(near & (delta < 0.0), np.maximum(delta, floor), delta).astype(np.float32)


def apply(ctx, h: np.ndarray, discs: list | None = None, lines: list | None = None) -> tuple:
    """The composed land with every province's landforms on it. Returns (heights, delta)."""
    delta = np.zeros_like(h, dtype=np.float32)
    for r in ctx.regions:
        names = [name for name in (r.landforms or []) if name in TERMS]
        if not names:
            continue
        w = ctx.rf.weights[r.index]
        if float(w.max()) < 1e-3:
            continue
        for name in names:
            delta += w * TERMS[name](ctx, h, r)
    if not delta.any():
        return h, delta
    # nothing at sea, and nothing under a lake: the seabed and the lake beds are the atlas's
    land = getattr(ctx, "land_soft", None)
    if land is not None:
        delta *= land
    delta *= smoothstep(-10.0, 30.0, ctx.lake.sd)
    # and beside a lake, no pit deeper than its water: a shakehole or a sunken street dug under the
    # level a few metres from the shore is a dry hole beside the water (7.7 m deep by the
    # Blackwater Tarn), not a pool
    lk = ctx.lake
    beside = (lk.sd > 0.0) & (lk.sd < 300.0)
    delta = np.where(beside, np.maximum(delta, np.minimum(h, lk.level + 0.5) - h), delta).astype(np.float32)
    keep, no_raise = protection(ctx, discs or [], lines or [])
    delta *= 1.0 - keep
    delta = np.where(no_raise, np.minimum(delta, 0.0), delta).astype(np.float32)
    return (h + delta).astype(np.float32), delta
