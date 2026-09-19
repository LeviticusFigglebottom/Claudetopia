"""Scatter placement into 256 m cells.

For every scatter rule a jittered lattice of candidate points is generated across the whole
world at the rule's ideal spacing, then thinned by region membership, slope, moisture, height,
clustering noise and the road/pad/water exclusions. Survivors are bucketed into cells and
written as `cells/<cx>_<cz>.json` in the shape fixed by docs/CONTRACTS.md section 6.
"""
from __future__ import annotations

import json
import math

import numpy as np

from .grid import Grid, sample_bilinear, sample_nearest, smoothstep

HECTARE = 10000.0


def load_rules(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


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
                 slope: np.ndarray, bank, regions: list):
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


def scatter(world: ScatterWorld, rules: dict, regions: list, seed: int, cluster_noise_salt: int = 700) -> dict:
    """Returns {(cx, cz): {asset_path: [[x, y, z, yaw, scale, tint], ...]}}."""
    grid = world.grid
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
        density = float(cfg.get("density", 1.0)) * mult
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
        # clustering: a low-frequency field decides where this species actually grows
        cl = float(cfg.get("cluster", 0.35))
        if cl > 0.0:
            field = world.bank.field_at(cluster_noise_salt + n, min(grid.n, 1024), beta=1.8,
                                        wl_min=float(cfg.get("rows", 60.0)), wl_max=420.0)
            g2 = grid.with_n(field.shape[0])
            cf = 0.5 + 0.5 * np.tanh(sample_bilinear(field, g2, x, z))
            acc *= (1.0 - cl) + cl * 2.0 * cf
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
        asset = "res://assets/models/%s/%s.glb" % (cfg["asset"], cfg["asset"].split("/")[-1])
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
            lst = bucket.setdefault(asset, [])
            for t in sel:
                lst.append([round(float(x[t]), 2), round(float(y[t]), 2), round(float(z[t]), 2),
                            round(float(yaw[t]), 1), round(float(scale[t]), 3), _hex(tints[t])])
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
