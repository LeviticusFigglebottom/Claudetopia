"""Texture control maps and the colour map.

Every terrain slot in docs/CONTRACTS.md section 5 gets a weight field built from region
membership, slope, height, moisture, road and water masks and noise. The two strongest slots
at each texel become base and overlay, and their relative strength becomes the blend value,
so material borders are soft and irregular rather than stencilled.

The colour map is the region's palette painted with low-frequency noise (plus wetness in the
alpha channel, which Terrain3D reads as a roughness modifier), so that even before props
exist a screenshot says which region it is.
"""
from __future__ import annotations

import numpy as np
from scipy import ndimage

from .grid import Grid, lerp, smoothstep
from .noise import NoiseBank

SLOTS = {
    "vale_grass": 0, "chalk": 1, "dirt_path": 2, "mud": 3, "peat": 4, "forest_floor": 5,
    "moss": 6, "granite": 7, "limestone": 8, "scree": 9, "snow": 10, "heather": 11,
    "ash_soil": 12, "grey_grass": 13, "fused_stone": 14, "shingle": 15, "cobbles": 16,
    "barley": 17, "orchard_grass": 18, "lake_bed": 19, "sand_flats": 20,
}
SLOT_NAMES = [name for name, _ in sorted(SLOTS.items(), key=lambda kv: kv[1])]
SNOW_LINE = 520.0


class SurfaceContext:
    """Everything the texture rules read, all at full resolution."""

    def __init__(self, grid: Grid, bank: NoiseBank, H: np.ndarray, regions: list, owner: np.ndarray,
                 water_mask: np.ndarray, water_level: np.ndarray, moisture: np.ndarray,
                 river_d: np.ndarray, road_d: np.ndarray, road_w: np.ndarray, pad_mask: np.ndarray,
                 lake, places: list):
        self.grid = grid
        self.bank = bank
        self.H = H
        self.regions = regions
        self.owner = owner
        self.water = water_mask.astype(bool)
        self.water_level = water_level
        self.moisture = moisture
        self.river_d = river_d
        self.road_d = road_d
        self.road_w = road_w
        self.pad = pad_mask
        self.lake = lake
        self.places = places
        n = grid.n
        gy, gx = np.gradient(H, grid.spacing)
        self.slope = np.hypot(gx, gy).astype(np.float32)          # rise over run
        self.X, self.Z = grid.mesh()
        self.idx = {r.shape: r.index for r in regions}
        self.n = n
        self._patch_cache: dict = {}
        # roads: on the carriageway, and a slightly wider verge
        self.on_road = road_d <= road_w * 0.5 + 0.6
        self.near_road = road_d <= road_w * 0.5 + 3.5
        # settlement footprints (cobbles, trodden ground)
        self.town = np.zeros((n, n), dtype=bool)
        for p in places:
            if p.get("kind") in ("city", "town", "village"):
                r = 70.0 if p["kind"] != "village" else 42.0
                d2 = (self.X - p["position"][0]) ** 2 + (self.Z - p["position"][1]) ** 2
                self.town |= d2 < r * r

    def region(self, shape: str) -> np.ndarray:
        i = self.idx.get(shape, -1)
        return (self.owner == i) if i >= 0 else np.zeros((self.n, self.n), dtype=bool)

    def patch(self, salt: int, wl_min: float = 40.0, wl_max: float = 220.0) -> np.ndarray:
        """0..1 patchy noise for breaking up material boundaries."""
        key = (salt, wl_min, wl_max)
        if key not in self._patch_cache:
            f = self.bank.detail(salt, self.n, wl_min=wl_min, wl_max=wl_max, beta=1.6)
            self._patch_cache[key] = (0.5 + 0.5 * np.tanh(f)).astype(np.float32)
        return self._patch_cache[key]

    def near_place(self, short_ids, radius: float) -> np.ndarray:
        out = np.zeros((self.n, self.n), dtype=bool)
        for p in self.places:
            if p["id"].split("/")[-1] in short_ids:
                d2 = (self.X - p["position"][0]) ** 2 + (self.Z - p["position"][1]) ** 2
                out |= d2 < radius * radius
        return out


def _weights(ctx: SurfaceContext):
    """Yield (slot_id, weight) for every terrain material, region by region."""
    s = ctx.slope
    H = ctx.H
    m = ctx.moisture
    flat = 1.0 - smoothstep(0.12, 0.45, s)
    steep = smoothstep(0.35, 0.85, s)
    verysteep = smoothstep(0.7, 1.3, s)
    dry = 1.0 - m

    downs = ctx.region("downs").astype(np.float32)
    basin = ctx.region("lake_basin").astype(np.float32)
    delta = ctx.region("delta").astype(np.float32)
    forest = ctx.region("forest_rise").astype(np.float32)
    karst = ctx.region("mountains").astype(np.float32)
    ash = ctx.region("ash_plateau").astype(np.float32)
    shore_band = np.exp(-((ctx.lake.sd) / 55.0) ** 2)
    river_band = np.exp(-(ctx.river_d / 14.0) ** 2)

    # --- Hearthvale: chalk downs, barley, orchards -------------------------------------
    yield SLOTS["vale_grass"], downs * (0.75 + 0.35 * flat) + basin * 0.5 * (1.0 - shore_band)
    yield SLOTS["chalk"], downs * (0.25 + 1.5 * steep + 0.7 * smoothstep(70.0, 105.0, H) * dry * ctx.patch(401)) \
        + basin * 1.3 * verysteep * smoothstep(-400.0, -1200.0, ctx.Z)
    yield SLOTS["barley"], downs * 1.25 * ctx.patch(402, 90, 380) ** 2 * flat * dry * (1.0 - smoothstep(75.0, 95.0, H))
    yield SLOTS["orchard_grass"], downs * 1.4 * ctx.near_place({"tamwick", "merrowby", "wardens_rest"}, 340.0) * flat \
        + basin * 0.8 * ctx.near_place({"gullhithe"}, 240.0) * flat

    # --- Brightwater: the Mere, its shingle shores, the black island -------------------
    under_water = ctx.water.astype(np.float32)
    yield SLOTS["lake_bed"], 2.2 * under_water * (1.0 - smoothstep(0.0, 1.0, np.abs(ctx.lake.sd) / 4000.0)) \
        * (ctx.lake.sd < 0).astype(np.float32) + 0.9 * under_water * (H > -1.0)
    yield SLOTS["shingle"], 1.9 * shore_band * (1.0 - steep) + 0.9 * river_band * (1.0 - ctx.water) * basin
    yield SLOTS["fused_stone"], 2.4 * (ctx.lake.island_sd < 20.0).astype(np.float32) \
        + ash * (0.55 * ctx.patch(403, 60, 260) ** 2 + 1.6 * ctx.near_place({"sunken_choir", "cantors_seat"}, 420.0))
    yield SLOTS["cobbles"], 2.6 * ctx.town * (1.0 - steep) + 1.8 * (ctx.on_road & ctx.town) \
        + 2.0 * (np.abs(ctx.X) < 12.0) * (ctx.lake.sd < 60.0) * (ctx.Z > -160.0) * (ctx.Z < 1400.0)

    # --- Sedgemire: peat, mud, tide-flats ----------------------------------------------
    yield SLOTS["peat"], delta * (1.1 + 0.8 * ctx.patch(404) * flat) * (1.0 - smoothstep(-3300.0, -3700.0, ctx.X))
    yield SLOTS["mud"], delta * (0.6 + 1.7 * m * (1.0 - flat * 0.3)) + 1.2 * river_band * (delta + basin * 0.4) \
        + 0.8 * m * downs * (1.0 - flat) * 0.3
    yield SLOTS["sand_flats"], delta * 2.4 * smoothstep(-3150.0, -3600.0, ctx.X) \
        + 1.6 * (H < 0.6) * (ctx.X < -3300.0)

    # --- The Briarwold: forest floor, moss, granite ------------------------------------
    yield SLOTS["forest_floor"], forest * (1.15 + 0.5 * flat * dry)
    yield SLOTS["moss"], forest * (0.55 + 1.3 * m * ctx.patch(405) + 0.9 * river_band) \
        + karst * 0.35 * m * flat * (1.0 - smoothstep(300.0, 420.0, H))
    yield SLOTS["granite"], forest * (1.7 * steep + 0.9 * verysteep) \
        + karst * 0.8 * verysteep * smoothstep(0.35, 0.7, ctx.patch(406))

    # --- Skerrow: limestone pavement, scree, heather, snow -----------------------------
    yield SLOTS["limestone"], karst * (0.95 + 0.9 * flat * smoothstep(180.0, 320.0, H)) \
        * (1.0 - smoothstep(SNOW_LINE - 60.0, SNOW_LINE + 40.0, H))
    yield SLOTS["scree"], karst * (1.9 * steep + 1.1 * smoothstep(0.55, 1.1, s) * smoothstep(250.0, 420.0, H))
    yield SLOTS["heather"], karst * 1.5 * flat * ctx.patch(407, 70, 300) * smoothstep(120.0, 220.0, H) \
        * (1.0 - smoothstep(430.0, 520.0, H)) + downs * 0.35 * ctx.patch(407, 70, 300) * smoothstep(80.0, 100.0, H)
    yield SLOTS["snow"], 2.6 * smoothstep(SNOW_LINE - 40.0, SNOW_LINE + 70.0, H) * (1.0 - 0.6 * verysteep)

    # --- Cinderlea: ash and grey grass --------------------------------------------------
    yield SLOTS["ash_soil"], ash * (1.2 + 0.7 * dry * (1.0 - flat))
    yield SLOTS["grey_grass"], ash * 1.5 * flat * ctx.patch(408, 80, 320) + ash * 0.4

    # --- roads everywhere ---------------------------------------------------------------
    yield SLOTS["dirt_path"], 3.0 * ctx.on_road * (1.0 - ctx.town) + 1.1 * ctx.near_road * (1.0 - ctx.town) \
        + 1.4 * ctx.pad * (1.0 - ctx.town) * (1.0 - steep) * ctx.patch(409, 30, 120)


def control_maps(ctx: SurfaceContext, blend_sharpness: float = 1.6):
    """base id, overlay id and blend (0-255) per texel, from the two strongest materials."""
    n = ctx.n
    best = np.zeros((n, n), dtype=np.float32)
    second = np.zeros((n, n), dtype=np.float32)
    base = np.zeros((n, n), dtype=np.uint8)
    overlay = np.zeros((n, n), dtype=np.uint8)
    jitter_scale = 0.12
    for slot, w in _weights(ctx):
        w = np.asarray(w, dtype=np.float32)
        w = w * (1.0 + jitter_scale * (ctx.patch(500 + slot, 18, 70) - 0.5))
        is_best = w > best
        is_second = (~is_best) & (w > second)
        # the old best slides down into second place; a mid-ranking slot takes second only
        overlay = np.where(is_best, base, np.where(is_second, np.uint8(slot), overlay)).astype(np.uint8)
        second = np.where(is_best, best, np.where(is_second, w, second))
        base = np.where(is_best, np.uint8(slot), base).astype(np.uint8)
        best = np.where(is_best, w, best)
    ratio = np.divide(second, np.maximum(best, 1e-4), dtype=np.float32)
    blend = np.clip(np.power(np.clip(ratio, 0.0, 1.0), blend_sharpness) * 255.0, 0, 255).astype(np.uint8)
    overlay = np.where(second <= 1e-4, base, overlay).astype(np.uint8)
    return base.astype(np.uint8), overlay, blend


def _hex_to_rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def colour_map(ctx: SurfaceContext, rf, strength: float = 0.34) -> np.ndarray:
    """RGBA8 tint map: region palettes broken up by low-frequency noise; alpha = wetness."""
    n = ctx.n
    acc = np.zeros((n, n, 3), dtype=np.float32)
    total = np.zeros((n, n), dtype=np.float32)
    for r in ctx.regions:
        pal = [_hex_to_rgb(c) for c in (r.palette or ["#ffffff"])]
        while len(pal) < 6:
            pal.append(pal[-1])
        w = rf.weight_at(r.index, n)
        a = 0.5 + 0.5 * np.tanh(ctx.bank.field_at(600 + r.index, n, beta=1.9, wl_min=240, wl_max=1100))
        b = 0.5 + 0.5 * np.tanh(ctx.bank.field_at(620 + r.index, n, beta=1.8, wl_min=90, wl_max=380))
        # three palette voices: the region's ground colour, its foil and its accent
        c0 = pal[1] if r.shape in ("downs", "forest_rise") else pal[0]
        c1 = pal[0] if r.shape in ("downs", "forest_rise") else pal[2]
        c2 = pal[3]
        mix = (c0[None, None, :] * (1.0 - a)[..., None] + c1[None, None, :] * a[..., None])
        mix = mix * (1.0 - 0.35 * b)[..., None] + c2[None, None, :] * (0.35 * b)[..., None]
        acc += mix * w[..., None]
        total += w
    acc /= np.maximum(total, 1e-6)[..., None]
    tint = lerp(np.ones_like(acc), acc, strength)
    # height and slope shading so the land reads even on flat light
    shade = 1.0 + 0.10 * np.tanh((ctx.H - 60.0) / 260.0) - 0.10 * smoothstep(0.35, 1.1, ctx.slope)
    tint *= shade[..., None]
    # snow and water lighten; ash darkens the accent
    tint = lerp(tint, np.ones_like(tint), smoothstep(SNOW_LINE - 20.0, SNOW_LINE + 80.0, ctx.H)[..., None] * 0.8)
    wet = np.clip(0.75 * ctx.moisture + 0.9 * ctx.water, 0.0, 1.0)
    alpha = np.clip(0.5 - 0.38 * wet, 0.0, 1.0)
    rgba = np.concatenate([np.clip(tint, 0.0, 1.0), alpha[..., None]], axis=-1)
    return (rgba * 255.0 + 0.5).astype(np.uint8)
