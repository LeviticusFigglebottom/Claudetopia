"""A landform apiece: the shape each region has and no other region does.

The drop test (DESIGN 10.1) reads a region's landform with the colour taken out -- its
skyline, how rugged it is, where the detail sits down the frame -- and on the 42-shot sheet it
read 0.12 as recorded (shot with no points of interest standing) and 0.26 re-shot with them,
against 0.17 for chance and a bar of 0.55. The regions differed by the colour of the ground,
not by its shape. Five of the six shape functions were broad rolling fields at different
heights, and at the scale a person walking sees (fifty to three hundred metres off, a few metres
to a few tens of metres of relief) they all read as the same lumpy grass.

So each region gets one or two terms here that only it has, built from its own geometry at
that scale, applied once to the composed land after the drainage and the Mere have had their
say (`heights.compose_heights`). Only with the world build's `landforms` recipe: they are
measured (PROGRESS.md, "The shape of the land") but not yet looked at from the ground, and
measured as relief at that scale they barely move any region, so no default build makes them.

* Brightwater -- the Mere has fallen since the Toll came down, and a lake that falls leaves its
  old shorelines behind it: raised beaches, level benches a few metres apart stepping up from
  the water, and on the open south and east shores a strandplain of wind-built dune ridges
  parallel to it, each with a steep face to the water and a long back.
* Sedgemire -- the delta's channels are banked with silt, a couple of metres above the marsh,
  the only dry lines in the country; and the loops the channels have abandoned lie about as
  crescent pools with their own low rims.
* The Briarwold -- old granite does not ramp, it goes up in benches: the rise is stepped, and
  the tors stand on the lips of the steps rather than anywhere.
* Skerrow -- the karst's middle heights break into horizontal limestone scars, and the moor
  above them is pocked with shakeholes, the sinks the water went down.
* Cinderlea -- the ash lies over the Builders' city, and the city shows through it: straight
  sunken streets on one grid, running to the horizon, and between them the blocks mounded with
  what the houses fell into -- flat tops and straight sides, which no natural ground has.
* Hearthvale -- the escarpment is already its landform. What it adds at a walking scale is
  the face stepped with strip lynchets where it was ploughed along the contour, and on the
  crest the barrows, round mounds in lines behind the skyline, which is where the
  hedge-wights are and what the Vale's own Hollin Barrow is one of.

Every term is generated from the region's own shape with no reference to where anything
stands, and then two masks keep what has already been composed on the land. The ground under a
place and around it is left as it was: fifty-five places and points of interest were placed,
and their sightlines answered one at a time, against the land as it is, and a pad flattens to
the median of whatever is under it, so a terrace tread through a POI would move the height its
sightlines are aimed from. And nothing may rise along an authored sightline: nine of the 87
lines clear the ground by under half a metre. Lowering is free everywhere.
"""
from __future__ import annotations

import math

import numpy as np

from .grid import smoothstep
from .noise import terrace

LAKE_LEVEL = 8.0


def _edge_weight(ctx) -> np.ndarray:
    """How far into the world's soft edges a point lies (heights.apply_edges' own masks)."""
    from .heights import sc

    X, Z = ctx.X, ctx.Z
    wob = ctx.f(181, 2.2, None, 2000)
    se = smoothstep(3350.0, 4096.0, X + 120.0 * wob)
    sn = smoothstep(-3150.0, -4000.0, Z + 140.0 * wob)
    ss = smoothstep(3660.0, 3800.0, Z + 90.0 * wob)
    sw = smoothstep(-3520.0 - 170.0 * sc(wob, 1.5), -3900.0, X)
    return np.maximum(np.maximum(se, sn), np.maximum(ss, sw)).astype(np.float32)


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


# --- Brightwater -------------------------------------------------------------------------------

## The raised beaches: a bench every 3.2 m of height, its bank a tenth of the step, from 110 m
## back from the water out to about a kilometre. The strandplain: ridges 78 m apart and up to
## five and a half metres high, parallel to the shore, on the open stretches of it -- each one
## a gentle back slope and a steeper face to the water, which is what the wind builds.
BEACH_STEP_M = 3.2
RIDGE_SPACING_M = 78.0
RIDGE_HEIGHT_M = 5.5


def brightwater(ctx, h: np.ndarray, r) -> np.ndarray:
    lk = ctx.lake
    sd = lk.sd
    base = LAKE_LEVEL + 1.5
    band = smoothstep(110.0, 240.0, sd) * (1.0 - smoothstep(950.0, 1350.0, sd))
    above = np.maximum(h - base, 0.0)
    benches = terrace(above, BEACH_STEP_M, 0.10) + base
    beaches = np.where(h > base, benches - h, 0.0) * band
    # the strandplain, on the shores that are neither the northern cliffs nor the reed shelf
    open_shore = (1.0 - lk.northness) * (1.0 - lk.westness)
    s = sd + 18.0 * ctx.f(213, 2.0, 150, 600)
    # a sawtooth rounded at the crest: the face to the water is a third of the period, the back
    # slope the rest, so each ridge has a lee and the row reads as built by the wind
    ph = (s / RIDGE_SPACING_M) % 1.0
    tooth = np.where(ph < 0.33, ph / 0.33, (1.0 - ph) / 0.67)
    ridge = smoothstep(0.0, 1.0, tooth) ** 1.6
    stretch = smoothstep(-0.2, 0.6, ctx.f(214, 2.0, 300, 1200))
    fade = smoothstep(35.0, 70.0, sd) * (1.0 - smoothstep(420.0, 620.0, sd))
    dunes = RIDGE_HEIGHT_M * ridge * stretch * open_shore * fade
    # not on Tollmere's stone or the causeway's deck
    keep_off = smoothstep(40.0, 120.0, lk.island_sd) * (1.0 - np.clip(lk.causeway * 3.0, 0.0, 1.0))
    return ((beaches + dunes) * keep_off).astype(np.float32)


# --- Sedgemire ---------------------------------------------------------------------------------

LEVEE_M = 2.2
OXBOWS = 34


def sedgemire(ctx, h: np.ndarray, r) -> np.ndarray:
    # the same two channel fields shape_delta cuts (the bank caches them, so these are the ones)
    c1 = ctx.warped(133, 240, 700, 120.0, beta=1.7, aniso=(0.0, 1.6))
    c2 = ctx.warped(134, 400, 1100, 160.0, beta=1.7, aniso=(0.0, 1.2))
    lev = np.maximum(np.exp(-((np.abs(c1) - 0.33) / 0.08) ** 2),
                     0.5 * np.exp(-((np.abs(c2) - 0.26) / 0.07) ** 2))
    # the banks are silt the channels dropped, so they die out on the tide-flats and the sea
    wet = 1.0 - smoothstep(-3050.0, -3450.0, ctx.X)
    levees = (LEVEE_M * lev * wet).astype(np.float32)
    # cut-off meanders: crescents of open water with a low rim, cut to below the marsh table
    rng = ctx.rng(137)
    cx0, cz0 = r.center
    bowl = np.zeros_like(levees)
    rim = np.zeros_like(levees)
    for _ in range(OXBOWS):
        cx = cx0 + rng.uniform(-1500.0, 1300.0)
        cz = cz0 + rng.uniform(-1500.0, 1400.0)
        radius = rng.uniform(55.0, 130.0)
        width = rng.uniform(12.0, 20.0)
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
            return ends(dx, dz) * 0.7 * np.exp(-((across - 0.5 * width - 6.0) / 4.0) ** 2)

        _stamp(bowl, ctx, cx, cz, radius + width + 16.0, water)
        _stamp(rim, ctx, cx, cz, radius + width + 16.0, bank)
    bowl = np.clip(bowl, 0.0, 1.0)
    # a crescent is cut to a floor below the marsh table, wherever the marsh stands
    floor = 0.35
    cut = bowl * np.clip(floor - h, -3.0, 0.0)
    return ((levees + rim) * (1.0 - bowl) + cut).astype(np.float32)


# --- The Briarwold -----------------------------------------------------------------------------

STAIR_STEP_M = 18.0
STAIR_RISER = 0.28
## a tor is a pile of rock five to twelve metres high, not a hill
TOR_M = 8.0


## A `terrace` step on ground of slope s has a riser of slope s / riser-fraction, as wide as
## riser-fraction * step / s. Past a slope of about a half the riser is a cliff a few metres wide,
## narrower than the heightmap can hold: measured on the first build with the scars in, the
## risers on Kharrow Hold's steep flanks came out as twenty-metre slots aliased into a stair of
## texels, and every road off the hold had to dive into one. So both stepped landforms fade out
## where the ground is already that steep, which is where it needs no help to look like rock.
STEP_FADE = (0.38, 0.55)


def _steepness(ctx, h: np.ndarray) -> np.ndarray:
    return np.hypot(*np.gradient(h, ctx.grid.spacing))


def briarwold(ctx, h: np.ndarray, r) -> np.ndarray:
    stepped = terrace(h, STAIR_STEP_M, STAIR_RISER)
    stair = (stepped - h) * (1.0 - smoothstep(STEP_FADE[0], STEP_FADE[1], _steepness(ctx, h)))
    # the lip of each bench is the top of the riser below it: where h is a whole number of steps
    q = h / STAIR_STEP_M
    frac = q - np.floor(q)
    near_whole = np.minimum(frac, 1.0 - frac)
    lip = np.exp(-(near_whole / 0.07) ** 2)
    knobs = np.clip(ctx.f(148, 1.8, 25, 120) - 0.9, 0.0, 1.3) ** 1.5
    tors = TOR_M * knobs * lip
    return (stair + tors).astype(np.float32)


# --- Skerrow -----------------------------------------------------------------------------------

SCAR_STEP_M = 20.0
SCAR_RISER = 0.25
SHAKEHOLES = 900


def skerrow(ctx, h: np.ndarray, r) -> np.ndarray:
    # limestone scars: the middle heights stepped in horizontal cliff bands
    slope = _steepness(ctx, h)
    band = smoothstep(200.0, 260.0, h) * (1.0 - smoothstep(470.0, 540.0, h))
    where = smoothstep(-0.3, 0.5, ctx.f(154, 2.0, None, 700))
    fade = 1.0 - smoothstep(STEP_FADE[0], STEP_FADE[1], slope)
    scars = (terrace(h, SCAR_STEP_M, SCAR_RISER) - h) * band * where * fade * 0.85
    out = scars.astype(np.float32)
    # shakeholes: sinks on the moor, in fields, where the water went down
    moor = smoothstep(215.0, 245.0, h) * (1.0 - smoothstep(330.0, 380.0, h)) \
        * (1.0 - smoothstep(0.18, 0.30, slope))
    fields = smoothstep(0.0, 0.6, ctx.f(159, 2.0, 250, 900))
    rng = ctx.rng(158)
    cx0, cz0 = r.center
    g = ctx.grid
    placed = 0
    for _ in range(SHAKEHOLES * 6):
        if placed >= SHAKEHOLES:
            break
        cx = cx0 + rng.uniform(-2200.0, 2400.0)
        cz = cz0 + rng.uniform(-1300.0, 1400.0)
        radius = rng.uniform(9.0, 22.0)
        depth = rng.uniform(3.0, 7.0) * radius / 16.0
        keep = rng.random()
        j = int(round((cx - g.x0) / g.spacing))
        i = int(round((cz - g.z0) / g.spacing))
        if not (0 <= i < g.n and 0 <= j < g.n):
            continue
        if keep > float(moor[i, j] * fields[i, j]):
            continue

        def bowl(d, dx, dz, radius=radius, depth=depth):
            return -depth * np.clip(1.0 - (d / radius) ** 2, 0.0, 1.0) ** 1.4

        _stamp(out, ctx, cx, cz, radius, bowl)
        placed += 1
    return out


# --- Cinderlea ---------------------------------------------------------------------------------

## The street grid: blocks 96 by 72 m on a bearing of 23 degrees, streets 12 m across sunk
## 2.8 m, with five-metre banks; and each block between them a flat-topped mound of what the
## houses fell into, up to 3.5 m -- six metres from a street's floor to the block beside it.
GRID_BEARING = 23.0
GRID_M = (96.0, 72.0)
STREET_M = 12.0
STREET_DEPTH_M = 2.8
BLOCK_M = 3.5


def cinderlea(ctx, h: np.ndarray, r) -> np.ndarray:
    th = math.radians(GRID_BEARING)
    u = ctx.X * math.cos(th) + ctx.Z * math.sin(th)
    v = -ctx.X * math.sin(th) + ctx.Z * math.cos(th)
    streets = np.zeros_like(h)
    inside = np.ones_like(h)
    for coord, period, off in ((u, GRID_M[0], 31.0), (v, GRID_M[1], 17.0)):
        d = np.abs(((coord + off + 0.5 * period) % period) - 0.5 * period)
        streets = np.maximum(streets, 1.0 - smoothstep(0.5 * STREET_M, 0.5 * STREET_M + 5.0, d))
        # how far into its block a point is, 0 at the street's bank and 1 a dozen metres in
        inside = np.minimum(inside, smoothstep(0.5 * STREET_M + 5.0, 0.5 * STREET_M + 17.0, d))
    # not every block has the same depth of rubble in it: some houses stood taller
    rubble = 0.55 + 0.45 * np.tanh(ctx.f(169, 1.8, 70, 260))
    # the city did not cover all of the heath, and the Choir's own terraces are older still
    city = smoothstep(-0.25, 0.35, ctx.f(168, 2.0, 900, 2600))
    choir = ctx.place("sunken_choir")
    ccx, ccz = choir["position"] if choir else r.center
    dchoir = np.sqrt((ctx.X - ccx) ** 2 + (ctx.Z - ccz) ** 2)
    away = smoothstep(420.0, 700.0, dchoir)
    shape = BLOCK_M * rubble * inside - STREET_DEPTH_M * streets
    return (shape * city * away).astype(np.float32)


# --- Hearthvale --------------------------------------------------------------------------------

BARROW_GROUPS = 26
LYNCHET_STEP_M = 3.0


def hearthvale(ctx, h: np.ndarray, r) -> np.ndarray:
    from .heights import SCARP_BEARING

    th = math.radians(SCARP_BEARING)
    cx0, cz0 = r.center
    across = (ctx.X - cx0) * math.cos(th) + (ctx.Z - cz0) * math.sin(th)
    along = -(ctx.X - cx0) * math.sin(th) + (ctx.Z - cz0) * math.cos(th)
    wander = (230.0 * np.sin(along / 940.0) + 130.0 * np.sin(along / 395.0 + 1.7)
              + 210.0 * ctx.f(117, 2.0, 600, 2600))
    sd = across - wander
    # Strip lynchets: where the face was ploughed along the contour for long enough, the soil
    # crept down against each strip and the hillside became a flight of steps -- banks of a
    # couple of metres, one above another up the scarp, which is the other thing a chalk
    # face shows from the vale besides its own white scar. In flights, not everywhere.
    slope = np.hypot(*np.gradient(h, ctx.grid.spacing))
    steep = smoothstep(0.10, 0.18, slope) * (1.0 - smoothstep(0.45, 0.60, slope))
    face = smoothstep(-320.0, -220.0, sd) * (1.0 - smoothstep(20.0, 70.0, sd))
    flights = smoothstep(0.1, 0.6, ctx.f(126, 2.0, 200, 900))
    out = ((terrace(h, LYNCHET_STEP_M, 0.35) - h) * steep * face * flights).astype(np.float32)
    # the barrows: just behind the crest, on this region's own ground
    crest = (sd > 25.0) & (sd < 160.0) & (ctx.rf.weights[r.index] > 0.85)
    idx = np.argwhere(crest)
    if idx.size == 0:
        return out
    rng = ctx.rng(125)
    g = ctx.grid
    ux, uz = -math.sin(th), math.cos(th)           # the crest's own direction
    chosen: list = []
    for k in rng.permutation(idx.shape[0])[:4000]:
        if len(chosen) >= BARROW_GROUPS:
            break
        i, j = idx[k]
        x = g.x0 + j * g.spacing
        z = g.z0 + i * g.spacing
        if any(math.hypot(x - a, z - b) < 420.0 for a, b in chosen):
            continue
        chosen.append((x, z))
        count = int(rng.integers(3, 7))
        gap = rng.uniform(42.0, 66.0)
        for m in range(count):
            t = (m - 0.5 * (count - 1)) * gap
            bx = x + ux * t + rng.normal(0.0, 6.0)
            bz = z + uz * t + rng.normal(0.0, 6.0)
            radius = rng.uniform(14.0, 24.0)
            height = rng.uniform(3.0, 5.5)

            def mound(d, dx, dz, radius=radius, height=height):
                body = height * np.clip(1.0 - (d / radius) ** 2, 0.0, 1.0) ** 1.5
                ditch = -0.5 * np.exp(-((d - radius - 2.0) / 1.6) ** 2)
                return body + ditch

            _stamp(out, ctx, bx, bz, radius + 8.0, mound)
    return out


SIGNATURES = {
    "lake_basin": brightwater,
    "delta": sedgemire,
    "forest_rise": briarwold,
    "mountains": skerrow,
    "ash_plateau": cinderlea,
    "downs": hearthvale,
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


def apply(ctx, h: np.ndarray, discs: list | None = None, lines: list | None = None) -> tuple:
    """The composed land with every region's signature on it. Returns (heights, delta)."""
    delta = np.zeros_like(h, dtype=np.float32)
    for r in ctx.regions:
        fn = SIGNATURES.get(r.shape)
        if fn is None:
            continue
        w = ctx.rf.weights[r.index]
        if float(w.max()) < 1e-3:
            continue
        delta += w * fn(ctx, h, r)
    delta *= 1.0 - _edge_weight(ctx)
    # nothing below the Mere's surface is reshaped: the lake bed and the shelf are apply_lake's
    delta *= smoothstep(-10.0, 30.0, ctx.lake.sd)
    keep, no_raise = protection(ctx, discs or [], lines or [])
    delta *= 1.0 - keep
    delta = np.where(no_raise, np.minimum(delta, 0.0), delta).astype(np.float32)
    return (h + delta).astype(np.float32), delta
