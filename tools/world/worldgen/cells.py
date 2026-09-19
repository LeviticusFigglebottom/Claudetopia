"""Scatter placement into 256 m cells.

For every scatter rule a jittered lattice of candidate points is generated across the whole
world at the rule's ideal spacing, then thinned by region membership, slope, moisture, height,
clustering noise and the road/pad/water exclusions. Survivors are bucketed into cells and
written as `cells/<cx>_<cz>.json` in the shape fixed by docs/CONTRACTS.md section 6.
"""
from __future__ import annotations

import json
import math
import os

import numpy as np

from .grid import Grid, sample_bilinear, sample_nearest, smoothstep

HECTARE = 10000.0
## Where the forge puts what it makes. A rule names a kind ("trees/oak"); the forge builds that
## kind once per region with two or three variants ("trees/hearthvale_oak_a"), because a
## region's oaks are its own colour and one oak repeated is a wallpaper.
MODELS_DIR = "game/assets/models"


def load_rules(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def asset_index(repo_root: str) -> dict:
    """category -> {name: path}, read off what the forge has actually built."""
    out: dict = {}
    base = os.path.join(repo_root, MODELS_DIR)
    if not os.path.isdir(base):
        return out
    for category in sorted(os.listdir(base)):
        cat_dir = os.path.join(base, category)
        if not os.path.isdir(cat_dir):
            continue
        names = {}
        for name in sorted(os.listdir(cat_dir)):
            if os.path.exists(os.path.join(cat_dir, name, name + ".glb")):
                names[name] = "res://assets/models/%s/%s/%s.glb" % (category, name, name)
        if names:
            out[category] = names
    return out


## Where a rule and the forge call the same thing by different names, or where the forge has
## nothing and the nearest honest neighbour will do. A missing plant is a bald hillside, so a
## sundew standing in for a marsh marigold is the better of the two wrongs — but only inside
## the same habit: nothing here substitutes a tree for a herb.
ASSET_ALIASES = {
    "flora/reed": "flora/reeds",
    "flora/briar": "flora/briar_vine",
    "flora/lichen": "flora/lichen_crust",
    "flora/red_poppy": "flora/red_poppy_single",
    "flora/waterlily": "flora/waterlily_pad",
    "flora/hawthorn": "trees/hawthorn",
    "flora/juniper": "trees/juniper",
    "props/char_stump": "trees/char_stump",
    "trees/dead_ash": "trees/dead_ash_tree",
    # No asset of their own; these are the nearest thing growing in the same ground.
    "flora/bladderwort": "flora/marsh_marigold",
    "flora/sundew": "flora/bracket_fungus",
    "flora/cottongrass": "flora/grey_grass",
    "flora/clover": "flora/grass_clump",
    "flora/market_herbs": "flora/cow_parsley",
}


def assets_for(index: dict, rule_asset: str, region_short: str) -> list:
    """Every file a rule may draw on in this region, best match first.

    A rule asks for `trees/oak`. This region's own oaks win; another region's oaks are better
    than no oak at all (a hawthorn is a hawthorn); an exact name is taken as written, which is
    how a one-off asset with no variants still works.
    """
    rule_asset = ASSET_ALIASES.get(rule_asset, rule_asset)
    category, _, kind = rule_asset.partition("/")
    names = index.get(category, {})
    if not names:
        return []
    if kind in names:
        return [names[kind]]
    mine = [p for n, p in names.items() if n.startswith(region_short + "_" + kind + "_")]
    if mine:
        return mine
    anyones = [p for n, p in names.items() if n.endswith("_" + kind) or ("_" + kind + "_") in n]
    return anyones


def _hex(c) -> str:
    return "#%02x%02x%02x" % (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255))


def _palette_rgb(region) -> np.ndarray:
    pal = region.palette or ["#ffffff"]
    out = []
    for h in pal:
        h = h.lstrip("#")
        out.append([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
    return np.array(out, dtype=np.float32)


class ScatterWorld:
    """The sampled fields a scatter pass reads."""

    def __init__(self, grid: Grid, H: np.ndarray, owner: np.ndarray, moisture: np.ndarray,
                 water: np.ndarray, road_d: np.ndarray, road_w: np.ndarray, pad_mask: np.ndarray,
                 slope: np.ndarray, bank, regions: list, water_d=None, field_d=None):
        self.grid = grid
        self.H = H
        self.owner = owner
        self.moisture = moisture
        self.water = water
        self.road_d = road_d
        self.road_w = road_w
        self.pad = pad_mask
        self.slope = slope
        self.bank = bank
        self.regions = regions
        # distance to any water at all (river, mere, sea) and to the nearest field boundary
        self.water_d = water_d if water_d is not None else np.full(H.shape, 1e6, dtype=np.float32)
        self.field_d = field_d if field_d is not None else np.full(H.shape, 1e6, dtype=np.float32)

    def sample(self, x, z) -> dict:
        g = self.grid
        return {
            "h": sample_bilinear(self.H, g, x, z),
            "owner": sample_nearest(self.owner, g, x, z),
            "moisture": sample_bilinear(self.moisture, g, x, z),
            "water": sample_nearest(self.water, g, x, z),
            "road_d": sample_nearest(self.road_d, g, x, z),
            "road_w": sample_nearest(self.road_w, g, x, z),
            "pad": sample_nearest(self.pad.astype(np.uint8), g, x, z),
            "slope": sample_bilinear(self.slope, g, x, z),
            "water_d": sample_bilinear(self.water_d, g, x, z),
            "field_d": sample_bilinear(self.field_d, g, x, z),
        }


def _candidates(rng: np.random.Generator, size_m: float, spacing: float) -> tuple:
    """Jittered lattice covering the world; spacing is the mean distance between candidates."""
    k = max(int(size_m / spacing), 1)
    step = size_m / k
    base = (np.arange(k, dtype=np.float32) + 0.5) * step - size_m / 2.0
    gx, gz = np.meshgrid(base, base, indexing="xy")
    jitter = step * 0.5
    x = (gx + rng.uniform(-jitter, jitter, gx.shape)).astype(np.float32).ravel()
    z = (gz + rng.uniform(-jitter, jitter, gz.shape)).astype(np.float32).ravel()
    return x, z


def scatter(world: ScatterWorld, rules: dict, regions: list, seed: int, cluster_noise_salt: int = 700,
            repo_root: str = ".") -> dict:
    """Returns {(cx, cz): {asset_path: [[x, y, z, yaw, scale, tint], ...]}}."""
    grid = world.grid
    index = asset_index(repo_root)
    unmatched: set = set()
    defaults = rules.get("defaults", {})
    region_mult = rules.get("region_density", {})
    out: dict = {}
    entries: list = []
    for r in regions:
        mult = float(region_mult.get(r.shape, 1.0))
        for key in r.flora:
            rule = rules["flora"].get(key)
            if rule is None:
                continue
            entries.append((r, key, rule, mult))
        for i, rule in enumerate(rules.get("rocks", {}).get(r.shape, [])):
            entries.append((r, "rock_%d" % i, rule, mult))
    for n, (region, key, rule, mult) in enumerate(entries):
        cfg = dict(defaults)
        cfg.update(rule)
        # a rule may say what it is worth in a particular region: a wood is not a downland
        # copse at a slightly higher density, it is a different order of thing
        per_region = cfg.get("region_density", {})
        density = float(cfg.get("density", 1.0)) * float(per_region.get(region.shape, mult))
        if density <= 0.0:
            continue
        spacing = math.sqrt(HECTARE / density)
        rng = np.random.default_rng(np.random.SeedSequence([seed, 900 + n]))
        x, z = _candidates(rng, grid.size_m - 4.0, spacing)
        s = world.sample(x, z)
        keep = s["owner"] == region.index
        if not keep.any():
            continue
        x, z = x[keep], z[keep]
        for k in list(s.keys()):
            s[k] = s[k][keep]
        want_water = bool(cfg.get("water", False))
        acc = np.ones(x.shape, dtype=np.float32)
        acc *= (s["water"] > 0) if want_water else (s["water"] == 0)
        acc *= 1.0 - smoothstep(float(cfg.get("slope_max", 0.55)) * 0.75, float(cfg.get("slope_max", 0.55)), s["slope"])
        if "slope_min" in cfg:
            acc *= smoothstep(float(cfg["slope_min"]) * 0.6, float(cfg["slope_min"]), s["slope"])
        mo = cfg.get("moisture", [0.0, 1.0])
        acc *= smoothstep(mo[0] - 0.12, mo[0] + 0.05, s["moisture"])
        acc *= 1.0 - smoothstep(mo[1] - 0.05, mo[1] + 0.12, s["moisture"])
        hr = cfg.get("height", [-40, 900])
        acc *= smoothstep(hr[0] - 12.0, hr[0] + 6.0, s["h"])
        acc *= 1.0 - smoothstep(hr[1] - 6.0, hr[1] + 12.0, s["h"])
        # keep off roads, pads and the immediate verge
        acc *= s["road_d"] > (s["road_w"] * 0.5 + 2.5)
        acc *= s["pad"] == 0
        # Attraction bands. A landscape's strongest line-work is what grows *along* things:
        # willows and alders following every watercourse, thorn along a field boundary, a row
        # of trees marking a lane. Exclusion alone can only ever produce an even sprinkle.
        for field_key, band_key in (("water_d", "near_water"), ("field_d", "near_hedge"),
                                    ("road_d", "near_lane")):
            band = cfg.get(band_key)
            if not band:
                continue
            lo, hi = float(band[0]), float(band[1])
            strength = float(band[2]) if len(band) > 2 else 1.0
            d = s[field_key]
            # 1 inside the band, falling away either side over a third of its width
            soft = max((hi - lo) * 0.35, 1.5)
            inside = smoothstep(lo - soft, lo + soft * 0.3, d) * (1.0 - smoothstep(hi - soft * 0.3, hi + soft, d))
            acc *= (1.0 - strength) + strength * inside
        # clustering: a low-frequency field decides where this species actually grows
        cl = float(cfg.get("cluster", 0.35))
        if cl > 0.0:
            field = world.bank.field_at(cluster_noise_salt + n, min(grid.n, 1024), beta=1.8,
                                        wl_min=float(cfg.get("rows", 60.0)), wl_max=420.0)
            g2 = grid.with_n(field.shape[0])
            cf = 0.5 + 0.5 * np.tanh(sample_bilinear(field, g2, x, z))
            # A gate, not a gentle multiplier. Trees come in copses and shelter belts with real
            # open ground between them; scaling every candidate by 0.45 to 1.45 only produces an
            # even sprinkle that is slightly lumpy. Below the threshold the species is simply
            # absent, above it the ground is thick with it.
            thresh = float(cfg.get("cluster_threshold", 0.46))
            gate = smoothstep(thresh, thresh + float(cfg.get("cluster_edge", 0.16)), cf)
            acc *= (1.0 - cl) + cl * gate * float(cfg.get("cluster_boost", 2.6))
        draw = rng.random(x.shape).astype(np.float32)
        take = draw < np.clip(acc, 0.0, 1.0)
        if not take.any():
            continue
        x, z = x[take], z[take]
        y = s["h"][take]
        scale_lo, scale_hi = cfg.get("scale", [0.85, 1.2])
        scale = rng.uniform(scale_lo, scale_hi, x.shape).astype(np.float32)
        yaw = rng.uniform(0.0, 360.0, x.shape).astype(np.float32) if cfg.get("yaw_random", True) else np.zeros_like(x)
        pal = _palette_rgb(region)
        base_col = pal[1] if pal.shape[0] > 1 else pal[0]
        jit = float(cfg.get("tint_jitter", 0.07))
        tints = np.clip(base_col[None, :] * (1.0 + rng.normal(0.0, jit, (x.size, 3))), 0.25, 1.0)
        # This region's own variants of the thing the rule names. Spreading the instances over
        # them is what stops a hillside being one tree printed four hundred times.
        variants = assets_for(index, str(cfg["asset"]), region.short)
        if not variants:
            unmatched.add(str(cfg["asset"]))
            continue
        pick = rng.integers(0, len(variants), x.shape)
        cx, cz = grid.cell_of(x, z)
        cx = np.clip(cx, 0, grid.cells - 1)
        cz = np.clip(cz, 0, grid.cells - 1)
        keys = cx.astype(np.int64) * grid.cells + cz.astype(np.int64)
        order = np.argsort(keys, kind="stable")
        keys_s = keys[order]
        bounds = np.searchsorted(keys_s, np.unique(keys_s))
        uniq = np.unique(keys_s)
        for bi, k in enumerate(uniq):
            lo = bounds[bi]
            hi = bounds[bi + 1] if bi + 1 < bounds.size else keys_s.size
            sel = order[lo:hi]
            ccx, ccz = int(k // grid.cells), int(k % grid.cells)
            bucket = out.setdefault((ccx, ccz), {})
            for t in sel:
                lst = bucket.setdefault(variants[int(pick[t])], [])
                lst.append([round(float(x[t]), 2), round(float(y[t]), 2), round(float(z[t]), 2),
                            round(float(yaw[t]), 1), round(float(scale[t]), 3), _hex(tints[t])])
    if unmatched:
        print("[world] no asset for: %s" % ", ".join(sorted(unmatched)), flush=True)
    return out


def cell_region_ids(world: ScatterWorld, regions: list) -> dict:
    """Dominant region id per cell."""
    grid = world.grid
    per = grid.texels_per_cell
    own = world.owner
    out = {}
    counts_shape = (grid.cells, per, grid.cells, per)
    view = own.reshape(grid.cells, per, grid.cells, per)
    for cz in range(grid.cells):
        for cx in range(grid.cells):
            block = view[cz, :, cx, :]
            vals, cnt = np.unique(block, return_counts=True)
            out[(cx, cz)] = regions[int(vals[int(np.argmax(cnt))])].id
    return out
