"""Height synthesis, from the atlas.

The land is composed at the composition resolution (Nc = min(N, 2048)) in the order
tools/world/atlas/SCHEMA.md gives: the provinces' ground and hills, the ranges, peaks and valleys
(`geography.land`); the coast and the lakes; a drainage network cut into the land by biome, then
the coast and the lakes once more so the authored water wins; the causeways; and each province's
landforms. It is upsampled and a full-resolution detail band added. Rivers, roads and pads are
carved later (hydro, roads). All heights are metres above the sea.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from scipy import ndimage

from . import geography as GEO
from .erosion import valley_carve
from .grid import Grid, smoothstep
from .noise import NoiseBank, downsample, upsample, warp
from .regions import RegionField

SEA_LEVEL = GEO.SEA_LEVEL


@dataclass
class HeightContext:
    grid: Grid
    bank: NoiseBank
    regions: list            # the provinces, as RegionDefs (geography.provinces_from_atlas)
    rf: RegionField
    lake: object             # geography.Waters at this grid
    places: list
    rivers: list = field(default_factory=list)       # the atlas's rivers (dicts), for the levees
    land_soft: np.ndarray | None = None              # 1 on land, 0 at sea, soft over the shore
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

    def place(self, short_id):
        for p in self.places:
            if p["id"].endswith("/" + short_id):
                return p
        return None

    def rng(self, salt):
        return np.random.default_rng(np.random.SeedSequence([self.bank.seed, salt]))


def upsample_held(a: np.ndarray, n: int) -> np.ndarray:
    """Cubic upsample, held inside the range of each coarse texel's neighbours.

    A cubic spline rings at a step. The Skerrow Wall stands 470 m straight out of the sea in the
    north-west, and upsampled from 2048 to 4096 the ground at its foot rang to 96 m under the
    seabed, in 210 pits along the cliff. Held to the least and the most of the coarse texels
    round it, a slope is still a smooth cubic and a cliff is a cliff, with nothing past either end.
    """
    up = upsample(a, n, order=3)
    if n == a.shape[0]:
        return up
    lo = upsample(ndimage.minimum_filter(a, size=3, mode="nearest"), n, order=1)
    hi = upsample(ndimage.maximum_filter(a, size=3, mode="nearest"), n, order=1)
    np.clip(up, lo, hi, out=up)
    return up


def detail_amplitude(owner: np.ndarray, regions: list) -> np.ndarray:
    amp_by_shape = {"downs": 0.5, "lake_basin": 0.3, "delta": 0.1, "forest_rise": 1.0, "mountains": 1.5, "ash_plateau": 0.35}
    table = np.array([amp_by_shape.get(r.shape, 0.5) for r in regions], dtype=np.float32)
    return table[owner]


## how uneven, in metres, the land the drainage is routed over is made (erosion.channel_field),
## and over what wavelengths: broad enough that the water gathers into gills a few hundred metres
## apart, never so broad that it bends a valley the atlas drew
ROUTE_JITTER_M = 5.0
ROUTE_JITTER_WL = (120.0, 700.0)
EROSION_STRENGTH = {"downs": 1.0, "lake_basin": 0.35, "delta": 0.25, "forest_rise": 1.05,
                    "mountains": 1.25, "ash_plateau": 0.45}
EROSION_DEPTH = {"downs": 24.0, "lake_basin": 8.0, "delta": 4.0, "forest_rise": 32.0,
                 "mountains": 52.0, "ash_plateau": 12.0}


def apply_drainage(ctx: HeightContext, h: np.ndarray, sea: np.ndarray | None = None,
                   work_n: int = 1024) -> tuple:
    """Cut a dendritic valley network into the land (see worldgen/erosion.py), by biome, never
    in the sea, a lake or a lake's shore shelf."""
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
    lake_sd_w = downsample(ctx.lake.sd, g.n)
    level_w = downsample(ctx.lake.level, g.n)
    dry = smoothstep(-20.0, 220.0, lake_sd_w) * smoothstep(level_w - 1.0, level_w + 7.0, hw)
    if sea is not None:
        dry = dry * (1.0 - downsample(sea.astype(np.float32), g.n))
    strength = strength * dry
    # the water is routed over land a little less even than the land itself (erosion.channel_field)
    jitter = downsample(ROUTE_JITTER_M * ctx.f(611, 2.0, *ROUTE_JITTER_WL), g.n)
    carved, chan = valley_carve(hw, g.spacing, depth_by, strength, jitter=jitter)
    delta = carved - hw
    if g.n != n:
        delta = upsample(delta, n, order=3)
        chan = upsample(chan, n, order=1)
    return (h + delta).astype(np.float32), chan.astype(np.float32)


def compose_heights(grid: Grid, grid_c: Grid, bank: NoiseBank, atlas: dict, provinces: list,
                    rf: RegionField, waters_c, waters_f, places: list, things: dict,
                    keep_discs: list | None = None, keep_lines: list | None = None,
                    apart: bool = False) -> tuple:
    """The land from the atlas, up to (not including) pads, rivers and roads.

    Returns (heights at grid.n, landform delta at grid.n or None, extras). The provinces'
    landforms (worldgen/landforms.py) are held off `keep_discs` (the pads) and never raised along
    `keep_lines` (the authored sightlines); with `apart` they are not added to the heights but
    returned beside them, for the world build to lay on after the roads (the upsample is linear,
    so the two added are the land the landforms alone would have given). `extras` has `sea` (bool,
    grid.n: outside the coast) and `rock` (0..1, grid.n: a range's own flanks).
    """
    from . import landforms as landforms_mod

    ctx = HeightContext(grid=grid_c, bank=bank, regions=provinces, rf=rf, lake=waters_c, places=places,
                        rivers=list(atlas.get("rivers", [])))
    h, rock = GEO.land(ctx, atlas)
    # the coast and the lakes first, so the drainage runs to the water that is there ...
    h, sea = GEO.apply_coast(ctx, h, atlas)
    h = GEO.apply_lakes(ctx, h, waters_c)
    h, _chan = apply_drainage(ctx, h, sea)
    # ... and again after it, so the authored water wins over the valleys
    h, sea = GEO.apply_coast(ctx, h, atlas)
    h = GEO.apply_lakes(ctx, h, waters_c)
    h = GEO.apply_causeways(ctx, h, waters_c, atlas, things)
    if sea.any():
        sd_land = GEO.signed_distance(grid_c, ~sea)
        ctx.land_soft = (1.0 - smoothstep(-80.0, -20.0, sd_land)).astype(np.float32)
    delta = None
    if any(r.landforms for r in provinces):
        h_with, delta = landforms_mod.apply(ctx, h, keep_discs, keep_lines)
        if not apart:
            h = h_with
        del h_with
    bank.forget()
    H = upsample_held(h, grid.n)
    # full-resolution detail band, damped on water and steep-scaled in the mountains
    owner = rf.owner_at(grid.n)
    amp = detail_amplitude(owner, provinces)
    d = bank.detail(190, grid.n, wl_min=max(3.0 * grid.spacing, 6.0), wl_max=64.0, beta=1.5)
    sea_f = sea if grid.n == grid_c.n else (upsample(sea.astype(np.float32), grid.n, order=1) > 0.5)
    water = np.maximum(1.0 - smoothstep(-6.0, 6.0, waters_f.sd), sea_f.astype(np.float32))
    # a shelf is flat rock (geography.apply_shelves), not ground for the detail band to roughen
    for shelf in atlas["coast"].get("shelves", []):
        water = np.maximum(water, GEO.polygon_mask(grid, shelf["polygon"]).astype(np.float32))
    H += d * amp * (1.0 - 0.95 * water)
    extras = {"sea": sea_f, "rock": upsample(rock, grid.n, order=1) if grid.n != grid_c.n else rock}
    delta_f = None
    if apart and delta is not None and delta.any():
        delta_f = upsample(delta, grid.n, order=3)
    return H.astype(np.float32), delta_f, extras
