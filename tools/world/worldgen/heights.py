"""Height synthesis.

Each region shape produces a full field at the composition resolution (Nc = min(N, 2048));
fields are blended with the region weights, then the Mere, the soft world edges and a
full-resolution detail band are applied. Rivers, roads and pads are carved later (hydro, roads).
All heights are metres above sea level; the Mere's surface is LAKE_LEVEL.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .grid import Grid, lerp, smoothstep
from .erosion import valley_carve
from .noise import NoiseBank, downsample, ridged, terrace, upsample, warp
from .regions import RegionDef, RegionField

LAKE_LEVEL = 8.0
SEA_LEVEL = 0.0
HUSH_FLOOR = -26.0
ISLAND_CENTER = (0.0, -150.0)
ISLAND_RADIUS = 240.0
CAUSEWAY_X = 0.0
CAUSEWAY_HALF_WIDTH = 6.0
CAUSEWAY_DECK = 9.8


@dataclass
class LakeGeometry:
    center: tuple
    radius: float
    sd: np.ndarray            # signed distance to the shore in metres (negative inside)
    island_sd: np.ndarray     # signed distance to the island shore (negative inside)
    northness: np.ndarray     # 0..1 how much this texel faces the northern (cliff) shore
    westness: np.ndarray      # 0..1 reed-fringe western shore
    causeway: np.ndarray      # 0..1 causeway deck mask (soft edge)


def lake_geometry(grid: Grid, bank: NoiseBank, center: tuple, radius: float) -> LakeGeometry:
    n = grid.n
    X, Z = grid.mesh()
    dx = X - center[0]
    dz = Z - center[1]
    d = np.sqrt(dx * dx + dz * dz)
    theta = np.arctan2(dz, dx)
    w1 = bank.field_at(211, n, beta=2.0, wl_min=500, wl_max=1800)
    shore_r = radius * (1.0 + 0.09 * np.sin(3.0 * theta + 0.7) + 0.05 * np.sin(7.0 * theta + 2.1)) + 75.0 * w1
    sd = (d - shore_r).astype(np.float32)
    # island (Tollmere) of black stone
    dix = X - ISLAND_CENTER[0]
    diz = Z - ISLAND_CENTER[1]
    di = np.sqrt(dix * dix + diz * diz)
    thi = np.arctan2(diz, dix)
    island_r = ISLAND_RADIUS * (1.0 + 0.12 * np.sin(2.0 * thi + 1.3) + 0.07 * np.sin(5.0 * thi))
    island_sd = (di - island_r).astype(np.float32)
    # which part of the shore: north -> low cliffs, west -> reed fringe
    northness = smoothstep(-0.25, -0.75, (dz / np.maximum(d, 1.0))).astype(np.float32)
    westness = smoothstep(-0.35, -0.85, (dx / np.maximum(d, 1.0))).astype(np.float32)
    # the Long Stride: straight causeway from the island south to the shore
    cw = 1.0 - smoothstep(CAUSEWAY_HALF_WIDTH, CAUSEWAY_HALF_WIDTH + 9.0, np.abs(X - CAUSEWAY_X))
    along = (Z > ISLAND_CENTER[1]) & (sd < 40.0)
    causeway = (cw * along).astype(np.float32)
    return LakeGeometry(center=center, radius=radius, sd=sd, island_sd=island_sd, northness=northness,
                        westness=westness, causeway=causeway)


@dataclass
class HeightContext:
    grid: Grid
    bank: NoiseBank
    regions: list
    rf: RegionField
    lake: LakeGeometry
    places: list
    X: np.ndarray = field(init=False)
    Z: np.ndarray = field(init=False)

    def __post_init__(self):
        self.X, self.Z = self.grid.mesh()

    def f(self, salt, beta=1.8, wl_min=None, wl_max=None, aniso=None):
        return self.bank.field_at(salt, self.grid.n, beta=beta, wl_min=wl_min, wl_max=wl_max, aniso=aniso)

    def warped(self, salt, wl_min, wl_max, amount_m, beta=1.8, aniso=None, wsalt=(203, 204)):
        base = self.f(salt, beta, wl_min, wl_max, aniso)
        a = amount_m / self.grid.spacing
        return warp(base, a * self.f(wsalt[0], 1.8, 150, 450), a * self.f(wsalt[1], 1.8, 150, 450))

    def blob(self, cx, cz, radius, depth):
        d2 = (self.X - cx) ** 2 + (self.Z - cz) ** 2
        return depth * np.exp(-d2 / (2.0 * (radius * 0.5) ** 2))

    def flat_pit(self, cx, cz, radius, depth, rim=15.0):
        d = np.sqrt((self.X - cx) ** 2 + (self.Z - cz) ** 2)
        return -depth * (1.0 - smoothstep(radius - rim, radius + rim, d))

    def place(self, short_id):
        for p in self.places:
            if p["id"].endswith("/" + short_id):
                return p
        return None

    def rng(self, salt):
        return np.random.default_rng(np.random.SeedSequence([self.bank.seed, salt]))


def sc(v, k: float = 2.0):
    """Soft clip a unit-variance field to about +-k (fractal fields have 5-sigma tails)."""
    return (k * np.tanh(v / k)).astype(np.float32)


def asym(v, up: float = 1.0, down: float = 0.35, k: float = 2.0):
    """Hills up, shallow valleys down: positive side scaled by `up`, negative by `down`."""
    v = sc(v, k)
    return np.where(v > 0, up * v, down * v).astype(np.float32)


# --- shapes ----------------------------------------------------------------------------------

def shape_downs(ctx: HeightContext, r: RegionDef) -> np.ndarray:
    """Chalk downs: long whale-backed hills (rounded tops), narrow dry valleys."""
    v = ctx.warped(111, None, 2200, 90.0, beta=2.1, aniso=(35.0, 3.0))
    dome = (0.5 + 0.5 * np.tanh(v / 1.1)) ** 0.8          # broad rounded whale-backs
    h = (r.base_height - 0.4 * r.relief) + 1.0 * r.relief * dome
    h += 0.10 * r.relief * sc(ctx.f(112, 2.0, None, 800), 1.5) + 0.05 * r.relief * sc(ctx.f(115, 2.0, 120, 420), 1.5)
    # the Cracked Toll: the bell's crater in the hill above Merrowby
    toll = ctx.place("cracked_toll")
    if toll:
        cx, cz = toll["position"]
        d = np.sqrt((ctx.X - cx) ** 2 + (ctx.Z - cz) ** 2)
        h += -9.0 * np.exp(-(d / 70.0) ** 2) + 3.5 * np.exp(-((d - 115.0) / 28.0) ** 2)
    return h.astype(np.float32)


def shape_lake_basin(ctx: HeightContext, r: RegionDef) -> np.ndarray:
    """Low land around the Mere; the lake itself is carved globally in apply_lake()."""
    mix = 0.45 * ctx.f(121, 2.0, None, 600) + 0.55 * ctx.f(122, 2.1, None, 1800)
    h = 13.0 + 5.0 * np.tanh(0.6 * mix)
    # rises toward the northern cliffs and the eastern headland of the Lamp
    h += 14.0 * smoothstep(-800.0, -1500.0, ctx.Z)
    lamp = ctx.place("the_lamp")
    if lamp:
        h += ctx.blob(lamp["position"][0], lamp["position"][1], 420.0, 12.0)
    return h.astype(np.float32)


def shape_delta(ctx: HeightContext, r: RegionDef) -> np.ndarray:
    """Marsh delta near sea level: braided channels, peat islands, tide-flats to the west."""
    mix = 0.5 * ctx.f(131, 2.0, None, 600) + 0.5 * ctx.f(132, 2.1, None, 1800)
    # the delta tilts gently down toward the sea in the west
    h = 1.3 + 1.8 * smoothstep(-3600.0, -2000.0, ctx.X) + 0.8 * np.tanh(0.8 * mix)
    c1 = ctx.warped(133, 240, 700, 120.0, beta=1.7, aniso=(0.0, 1.6))
    c2 = ctx.warped(134, 400, 1100, 160.0, beta=1.7, aniso=(0.0, 1.2))
    chan1 = np.exp(-(c1 / 0.22) ** 2)
    chan2 = np.exp(-(c2 / 0.16) ** 2)
    islands = 2.2 * np.clip(ctx.f(135, 1.9, None, 260) - 0.6, 0.0, 1.2) ** 1.2
    h = h + islands - 2.2 * chan1 - 1.8 * chan2
    # tide-flats: everything sinks toward the west
    h = lerp(h, 0.5 + 0.25 * ctx.f(136, 1.6, 50, 170), smoothstep(-3050.0, -3500.0, ctx.X))
    return h.astype(np.float32)


def shape_forest_rise(ctx: HeightContext, r: RegionDef) -> np.ndarray:
    """Old forest on rising granite: ravines with falls, tors, climbing to the Briar."""
    rise = 0.05 * np.clip(ctx.X - 900.0, 0.0, None)
    mix = 0.62 * ctx.f(141, 2.2, None, 2400) + 0.26 * ctx.f(142, 2.0, None, 800) + 0.12 * ctx.f(147, 2.0, 120, 460)
    h = 30.0 + rise + 0.8 * r.relief * asym(mix / 0.71, 0.6, 0.25)
    # ravines: a few long clefts running down toward the lake, with falls where the land steps
    rav = np.exp(-(ctx.warped(144, 500, 1500, 150.0, beta=1.8, aniso=(0.0, 2.0)) / 0.09) ** 2)
    rav *= smoothstep(1300.0, 2200.0, ctx.X) * smoothstep(0.1, 0.6, ctx.f(146, 2.2, None, 2400))
    h -= 26.0 * rav
    tors = 20.0 * np.clip(ctx.f(145, 1.8, 30, 190) - 1.6, 0.0, 1.0) ** 2
    h += tors
    return h.astype(np.float32)


def shape_mountains(ctx: HeightContext, r: RegionDef) -> np.ndarray:
    """Karst mountains: ridges, terraces, gorges, sinkholes, high moor; peaks toward the north."""
    e = smoothstep(-1100.0, -3900.0, ctx.Z)
    # broad massifs, a few sharp crest lines on top of them, small crags on the slopes
    bulk = 0.5 + 0.5 * np.tanh(ctx.f(151, 2.3, None, 3200) / 1.1)
    crest = ridged(ctx.f(157, 2.2, None, 1800, aniso=(15.0, 1.6)), 1.8)
    crags = ridged(ctx.f(152, 2.0, 60, 400), 1.1)
    l2 = sc(ctx.f(153, 2.1, None, 1800))
    relief = r.relief * (0.35 + 0.65 * e)
    h = 40.0 + 130.0 * e + relief * ((0.6 + 0.15 * e) * bulk + 0.28 * crest * (0.25 + 0.75 * bulk)
                                     + 0.035 * crags * (0.3 + 0.7 * crest) + 0.05 * l2)
    # high moor: away from the crests, the middle heights flatten into a rolling plateau
    moor = smoothstep(0.5, 0.2, crest) * smoothstep(0.2, 0.5, e) * (1.0 - smoothstep(0.8, 0.95, e))
    moor_h = 255.0 + 25.0 * l2 + 8.0 * sc(ctx.f(158, 2.0, None, 700))
    h = lerp(h, moor_h, 0.6 * moor)
    # karst terraces (limestone pavements) in the middle band
    pav = ctx.f(154, 2.0, None, 700)
    gentle = 1.0 - smoothstep(0.25, 0.6, np.hypot(*np.gradient(h, ctx.grid.spacing)))
    band = smoothstep(220.0, 300.0, h) * (1.0 - smoothstep(460.0, 540.0, h)) * smoothstep(0.35, 0.85, pav) * gentle
    h = lerp(h, terrace(h, 34.0, 0.4), 0.28 * band)
    # gorges: a few narrow slots cut through the mid heights
    g = np.exp(-(ctx.warped(155, 300, 1000, 120.0, beta=1.7, aniso=(80.0, 1.6)) / 0.14) ** 2)
    g *= smoothstep(200.0, 300.0, h) * (1.0 - smoothstep(500.0, 600.0, h))
    g *= smoothstep(0.5, 1.0, ctx.f(159, 2.2, None, 2400))
    h -= 42.0 * g
    # sinkholes
    rng = ctx.rng(156)
    cx, cz = r.center
    for _ in range(36):
        px = cx + rng.uniform(-1500, 1500)
        pz = cz + rng.uniform(-1300, 700)
        h += ctx.blob(px, pz, rng.uniform(40, 80), -rng.uniform(6, 11))
    return h.astype(np.float32)


def shape_ash_plateau(ctx: HeightContext, r: RegionDef) -> np.ndarray:
    """Ash plateau over the Builders' city: terraces, sunken plazas, the Choir ring."""
    mix = 0.7 * ctx.f(161, 2.2, None, 1900) + 0.3 * ctx.f(162, 2.0, None, 700)
    h = 88.0 + 24.0 * np.tanh(1.3 * mix) + 5.0 * sc(ctx.f(162, 2.0, None, 700)) \
        + 3.0 * sc(ctx.f(166, 2.0, 140, 520), 1.5) + 1.5 * sc(ctx.f(163, 1.8, 40, 220))
    # the Builders' city shows through as terraces near the Choir
    choir = ctx.place("sunken_choir")
    ccx, ccz = choir["position"] if choir else r.center
    dchoir = np.sqrt((ctx.X - ccx) ** 2 + (ctx.Z - ccz) ** 2)
    t = smoothstep(0.2, 0.6, ctx.warped(164, 300, 1100, 80.0, beta=1.9)) * (1.0 - smoothstep(900.0, 1600.0, dchoir))
    h = lerp(h, terrace(h, 9.0, 0.3), 0.85 * t)
    rng = ctx.rng(165)
    cx, cz = r.center
    for _ in range(16):
        px = cx + rng.uniform(-1400, 1400)
        pz = cz + rng.uniform(-1200, 900)
        h += ctx.flat_pit(px, pz, rng.uniform(40, 85), rng.uniform(4, 7))
    if choir:
        h += ctx.flat_pit(choir["position"][0], choir["position"][1], 135.0, 12.0, rim=22.0)
    return h.astype(np.float32)


SHAPES = {
    "downs": shape_downs,
    "lake_basin": shape_lake_basin,
    "delta": shape_delta,
    "forest_rise": shape_forest_rise,
    "mountains": shape_mountains,
    "ash_plateau": shape_ash_plateau,
}


# --- composition ----------------------------------------------------------------------------

def blend_regions(ctx: HeightContext) -> np.ndarray:
    n = ctx.grid.n
    h = np.zeros((n, n), dtype=np.float32)
    for r in ctx.regions:
        fn = SHAPES.get(r.shape, shape_downs)
        h += ctx.rf.weights[r.index] * fn(ctx, r)
    return h


def apply_lake(ctx: HeightContext, h: np.ndarray) -> np.ndarray:
    """Carve the Mere below LAKE_LEVEL, shape its shores, raise Tollmere and the Long Stride."""
    lk = ctx.lake
    sd = lk.sd
    inside = 1.0 - smoothstep(-40.0, 0.0, sd)  # 1 well inside, 0 on land
    depth_t = np.clip(-sd / (lk.radius * 0.75), 0.0, 1.0)
    bed = LAKE_LEVEL - 14.0 * smoothstep(0.0, 1.0, depth_t) ** 0.8 - 0.6 * ctx.f(171, 1.9, None, 260)
    # western reed shelf stays shallow
    shelf = (LAKE_LEVEL - 1.3) * np.ones_like(bed)
    bed = lerp(bed, np.maximum(bed, shelf), lk.westness * (1.0 - smoothstep(60.0, 220.0, -sd)))
    # shore profile on land: shingle rising 4 m over 60 m, then the region field (kept above
    # the lake for a few hundred metres so no dry hollows sit below lake level near the shore)
    shore = LAKE_LEVEL + 4.0 * smoothstep(0.0, 60.0, sd)
    land = lerp(shore, h, smoothstep(50.0, 320.0, sd))
    near = 1.0 - smoothstep(250.0, 700.0, sd)
    land = lerp(land, np.maximum(land, LAKE_LEVEL + 1.5), near)
    # northern cliff shore: a sharp 7-10 m step right at the water
    cliff = (7.0 + 3.0 * ctx.f(172, 1.9, None, 260)) * smoothstep(0.0, 10.0, sd)
    land = land + cliff * lk.northness * (1.0 - smoothstep(40.0, 260.0, sd))
    h2 = lerp(land, np.minimum(bed, land), inside)
    # the island of black stone
    isl = 1.0 - smoothstep(-30.0, 25.0, lk.island_sd)
    island_h = LAKE_LEVEL + 9.0 * smoothstep(0.0, 0.4, np.clip(-lk.island_sd / ISLAND_RADIUS, 0, 1)) ** 0.7
    island_h += 1.5 * ctx.f(173, 1.9, None, 260) * smoothstep(-20.0, -80.0, lk.island_sd)
    # Tollmere is a stack of fused stone, not a smooth dome: broken ledges step up to a
    # fractured crown, and the relief dies out before it reaches the waterline
    inner = smoothstep(-6.0, -55.0, lk.island_sd)
    ledges = terrace(np.clip(7.0 * ctx.f(174, 1.7, 40.0, 200.0), 0.0, None), 2.2, 0.45)
    fracture = 1.2 * np.abs(ctx.f(175, 1.5, 9.0, 48.0))
    island_h = island_h + (ledges + fracture) * inner
    h2 = np.maximum(h2, lerp(h2, island_h, isl))
    # the Long Stride causeway: a straight raised deck with sloped sides
    deck = CAUSEWAY_DECK + 0.3 * smoothstep(0.0, 400.0, ctx.Z)
    sides = deck - 1.4 * np.clip(np.abs(ctx.X - CAUSEWAY_X) - CAUSEWAY_HALF_WIDTH, 0.0, None)
    on_span = (ctx.Z > ISLAND_CENTER[1] + 50.0) & (sd < 20.0) & (lk.island_sd > -40.0)
    h2 = np.where(on_span, np.maximum(h2, sides), h2)
    return h2.astype(np.float32)


def apply_edges(ctx: HeightContext, h: np.ndarray) -> np.ndarray:
    """Soft edges (DESIGN 4.2): mountain wall N, cliffs S, sea W, rising forest E."""
    X, Z = ctx.X, ctx.Z
    wob = ctx.f(181, 2.2, None, 2000)
    ridge = ridged(ctx.f(182, 2.0, None, 700), 1.3)
    # east: the Thornmarch rampart (the forest keeps rising into the Briar wall)
    se = smoothstep(3350.0, 4096.0, X + 120.0 * wob)
    rampart = 190.0 + 130.0 * se + 50.0 * ridge
    h = lerp(h, np.maximum(h, rampart), se)
    # north: the wall of Skerrow, peaks 600-700 m, with the notch of Windgate Pass
    sn = smoothstep(-3150.0, -4000.0, Z + 140.0 * wob)
    wall = 300.0 + 280.0 * sn + 110.0 * ridge
    windgate = ctx.place("windgate")
    if windgate:
        gx = windgate["position"][0]
        notch = np.exp(-((X - gx) / 190.0) ** 2)
        wall = wall - 300.0 * notch * sn
    h = lerp(h, np.maximum(h, wall), sn)
    # south: cliffs down to the Hush
    ss = smoothstep(3660.0, 3800.0, Z + 90.0 * wob)
    h = lerp(h, HUSH_FLOOR + 6.0 * ridge, ss)
    # west: tide-flats then the Grey Sea (coast wobbles)
    sw = smoothstep(-3520.0 - 170.0 * sc(wob, 1.5), -3900.0, X)
    h = lerp(h, -6.5 + 1.2 * ridge, sw)
    return h.astype(np.float32)


def detail_amplitude(owner: np.ndarray, regions: list) -> np.ndarray:
    amp_by_shape = {"downs": 0.5, "lake_basin": 0.3, "delta": 0.1, "forest_rise": 1.0, "mountains": 1.5, "ash_plateau": 0.35}
    table = np.array([amp_by_shape.get(r.shape, 0.5) for r in regions], dtype=np.float32)
    return table[owner]


EROSION_STRENGTH = {"downs": 1.0, "lake_basin": 0.35, "delta": 0.25, "forest_rise": 1.05,
                    "mountains": 1.25, "ash_plateau": 0.45}
EROSION_DEPTH = {"downs": 24.0, "lake_basin": 8.0, "delta": 4.0, "forest_rise": 32.0,
                 "mountains": 52.0, "ash_plateau": 12.0}


def apply_drainage(ctx: HeightContext, h: np.ndarray, work_n: int = 1024) -> tuple:
    """Cut a dendritic valley network into the blended land (see worldgen/erosion.py)."""
    n = ctx.grid.n
    g = ctx.grid.with_n(min(n, work_n))
    hw = downsample(h, g.n)
    owner_w = ctx.rf.owner_at(g.n)
    strength = np.zeros((g.n, g.n), dtype=np.float32)
    depth_by = np.zeros((g.n, g.n), dtype=np.float32)
    for r in ctx.regions:
        m = owner_w == r.index
        strength[m] = EROSION_STRENGTH.get(r.shape, 0.8)
        depth_by[m] = EROSION_DEPTH.get(r.shape, 15.0)
    # no carving in standing water or on the shore shelf
    lake_sd_w = downsample(ctx.lake.sd, g.n)
    dry = smoothstep(-20.0, 220.0, lake_sd_w) * smoothstep(LAKE_LEVEL - 1.0, LAKE_LEVEL + 7.0, hw)
    strength = strength * dry
    carved, chan = valley_carve(hw, g.spacing, depth_by, strength)
    delta = carved - hw
    if g.n != n:
        delta = upsample(delta, n, order=3)
        chan = upsample(chan, n, order=1)
    return (h + delta).astype(np.float32), chan.astype(np.float32)


def compose_heights(grid: Grid, grid_c: Grid, bank: NoiseBank, regions: list, rf: RegionField, lake_c: LakeGeometry,
                    lake_f: LakeGeometry, places: list) -> np.ndarray:
    """Full pipeline up to (not including) pads, rivers and roads. Returns heights at grid.n."""
    ctx = HeightContext(grid=grid_c, bank=bank, regions=regions, rf=rf, lake=lake_c, places=places)
    h = blend_regions(ctx)
    h = apply_lake(ctx, h)
    h = apply_edges(ctx, h)
    h, _chan = apply_drainage(ctx, h)
    h = apply_lake(ctx, h)          # the Mere, its shores and the causeway win over the valleys
    bank.forget()
    H = upsample(h, grid.n, order=3)
    # full-resolution detail band, damped on water and steep-scaled in the mountains
    owner = rf.owner_at(grid.n)
    amp = detail_amplitude(owner, regions)
    d = bank.detail(190, grid.n, wl_min=max(3.0 * grid.spacing, 6.0), wl_max=64.0, beta=1.5)
    water = 1.0 - smoothstep(-6.0, 6.0, lake_f.sd)
    H += d * amp * (1.0 - 0.85 * water)
    return H.astype(np.float32)
