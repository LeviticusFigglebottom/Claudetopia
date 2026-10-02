#!/usr/bin/env python3
"""The small scale of a terrain texture: what the ground is made of at your feet.

    python3 tools/world/terrain_micro.py ash_soil            # apply to the shipped pair in place
    python3 tools/world/terrain_micro.py ash_soil --out /tmp/x --preview

The painted terrain textures carry their story in large soft bands and a mottle, and at close
range that reads as blotchy smears under a normal map -- plastic. This lays a micro layer over a
seamless albedo_height / normal_rough pair: a fine grain, scattered cinders and pale flecks,
small pebbles that stand up out of the ground (albedo, height and normal), and wind ripples.
Everything is periodic on the tile, so the texture stays seamless. The albedo's mean in linear
light is held where it was, so the ground's brightness (tests/unit/test_ground_albedo.gd) does
not move. gen_terrain_textures.py applies the same recipe to a slot whose spec names `micro`.
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
TEXTURES = os.path.join(HERE, "..", "..", "game", "assets", "textures", "terrain")

# per material: grain (value spread), cinders and flecks (count per tile), pebbles (count,
# radius px range, value), ripples (strength, wavelength px, angle deg), normal strength
RECIPES = {
    "ash_soil": {"grain": 0.10, "cinders": 5200, "cinder_value": 0.45, "flecks": 2600, "fleck_value": 1.55,
                 "pebbles": 1400, "pebble_r": (3.0, 9.0), "pebble_value": 1.4,
                 "ripples": 0.8, "flatten": 0.4, "ripple_wl": 38.0, "ripple_angle": 22.0, "normal": 2.2},
    "grey_grass": {"grain": 0.06, "cinders": 1800, "cinder_value": 0.55, "flecks": 600, "fleck_value": 1.35,
                   "pebbles": 250, "pebble_r": (2.5, 6.0), "pebble_value": 1.15,
                   "ripples": 0.0, "ripple_wl": 40.0, "ripple_angle": 0.0, "normal": 1.4},
    "limestone": {"grain": 0.07, "cinders": 900, "cinder_value": 0.7, "flecks": 1400, "fleck_value": 1.25,
                  "pebbles": 300, "pebble_r": (2.5, 7.0), "pebble_value": 1.12,
                  "ripples": 0.0, "ripple_wl": 40.0, "ripple_angle": 0.0, "normal": 1.6, "flatten": 0.25},
    "granite": {"grain": 0.08, "cinders": 1500, "cinder_value": 0.65, "flecks": 1800, "fleck_value": 1.3,
                "pebbles": 250, "pebble_r": (2.5, 6.0), "pebble_value": 1.12,
                "ripples": 0.0, "ripple_wl": 40.0, "ripple_angle": 0.0, "normal": 1.6, "flatten": 0.2},
    "fused_stone": {"grain": 0.05, "cinders": 800, "cinder_value": 0.6, "flecks": 1200, "fleck_value": 1.3,
                    "pebbles": 120, "pebble_r": (2.0, 5.0), "pebble_value": 1.2,
                    "ripples": 0.0, "ripple_wl": 40.0, "ripple_angle": 0.0, "normal": 1.2},
}


def periodic_noise(n: int, rng, wl_min: float, wl_max: float) -> np.ndarray:
    """Seamless band-limited noise on an n x n tile, unit variance."""
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    r = np.hypot(fx, fy) + 1e-9
    band = ((r >= 1.0 / wl_max) & (r <= 1.0 / wl_min)).astype(np.float64)
    spec = (rng.standard_normal((n, n)) + 1j * rng.standard_normal((n, n))) * band / np.sqrt(r)
    out = np.real(np.fft.ifft2(spec))
    return (out - out.mean()) / (out.std() + 1e-9)


def stamp(field: np.ndarray, x: float, y: float, r: float, value: float, soft: float = 0.6) -> None:
    """Add a soft round blob to `field` (wrapping at the edges); value at the centre."""
    n = field.shape[0]
    rr = int(np.ceil(r * 1.6)) + 1
    ys = np.arange(int(y) - rr, int(y) + rr + 1)
    xs = np.arange(int(x) - rr, int(x) + rr + 1)
    dy, dx = np.meshgrid(ys - y, xs - x, indexing="ij")
    d = np.hypot(dx, dy) / max(r, 0.5)
    w = np.clip(1.0 - d, 0.0, 1.0) ** soft
    np.add.at(field, (ys[:, None] % n, xs[None, :] % n), w * value)


def to_lin(s):
    return np.where(s <= 0.04045, s / 12.92, ((s + 0.055) / 1.055) ** 2.4)


def to_srgb(v):
    v = np.clip(v, 0.0, 1.0)
    return np.where(v <= 0.0031308, v * 12.92, 1.055 * v ** (1 / 2.4) - 0.055)


def apply(albedo_height: np.ndarray, normal_rough: np.ndarray, recipe: dict, seed: int = 7) -> tuple:
    """Arrays as uint8 RGBA (h, w, 4); returns the new pair.

    The recipe's sizes are pixels of the 1024 tile. A larger tile (the High set's 2048) scales them,
    so a grain, a pebble or a ripple is the same size on the ground at either resolution."""
    rng = np.random.default_rng(seed)
    n = albedo_height.shape[0]
    k = n / 1024.0
    rgb = to_lin(albedo_height[..., :3].astype(np.float64) / 255.0)
    mean_before = rgb.mean(axis=(0, 1))
    height = albedo_height[..., 3].astype(np.float64) / 255.0

    # the painted blotches, a metre across, are held back a little so the small scale carries
    # the near ground: `flatten` of the low-passed log-brightness is taken out (periodic blur)
    if recipe.get("flatten", 0.0) > 0:
        lum = np.log(rgb.mean(axis=2) + 1e-4)
        f = np.fft.fftfreq(n)
        fx, fy = np.meshgrid(f, f)
        low = np.real(np.fft.ifft2(np.fft.fft2(lum) * np.exp(-(fx ** 2 + fy ** 2) * (2 * np.pi * 40.0 * k) ** 2 / 2)))
        rgb = rgb * np.exp(-recipe["flatten"] * (low - low.mean()))[..., None]
    value = np.ones((n, n))
    bump = np.zeros((n, n))
    # grain: two octaves of fine noise, a few pixels across
    grain = 0.65 * periodic_noise(n, rng, 1.5 * k, 4.0 * k) + 0.35 * periodic_noise(n, rng, 4.0 * k, 10.0 * k)
    value *= 1.0 + recipe["grain"] * grain
    bump += 0.12 * grain
    # wind ripples: long, slightly wavering bands
    if recipe["ripples"] > 0:
        yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
        a = np.radians(recipe["ripple_angle"])
        # an integer number of waves across the tile keeps it seamless
        waves = max(1, round(n / (recipe["ripple_wl"] * k)))
        warp = 6.0 * k * periodic_noise(n, rng, 60.0 * k, 300.0 * k)
        phase = 2 * np.pi * waves * ((np.cos(a) * xx + np.sin(a) * yy) + warp) / n
        mask = np.clip(0.5 + 0.8 * periodic_noise(n, rng, 120.0 * k, 500.0 * k), 0.0, 1.0)
        rip = (np.sin(phase) ** 3) * mask * recipe["ripples"]
        value *= 1.0 + 0.10 * rip
        bump += 0.35 * rip
    # pebbles: they stand up, catch the light, and carry a little shade under them
    peb = np.zeros((n, n))
    lo, hi = recipe["pebble_r"]
    for _ in range(recipe["pebbles"]):
        r = rng.uniform(lo, hi)
        stamp(peb, rng.uniform(0, n), rng.uniform(0, n), r * k, 1.0, soft=0.45)
    peb = np.clip(peb, 0.0, 1.0)
    value = value * (1.0 + (recipe["pebble_value"] - 1.0) * peb)
    bump += 1.4 * peb
    # cinders and flecks: specks one to three pixels across
    specks = np.zeros((n, n))
    for _ in range(recipe["cinders"]):
        stamp(specks, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(0.8, 2.2) * k, -1.0, soft=1.0)
    flecks = np.zeros((n, n))
    for _ in range(recipe["flecks"]):
        stamp(flecks, rng.uniform(0, n), rng.uniform(0, n), rng.uniform(0.6, 1.6) * k, 1.0, soft=1.0)
    specks = np.clip(-specks, 0.0, 1.0)
    flecks = np.clip(flecks, 0.0, 1.0)
    value *= 1.0 - (1.0 - recipe["cinder_value"]) * specks
    value *= 1.0 + (recipe["fleck_value"] - 1.0) * flecks
    bump += 0.3 * flecks - 0.2 * specks

    rgb = rgb * value[..., None]
    rgb *= (mean_before / (rgb.mean(axis=(0, 1)) + 1e-9))[None, None, :]
    new_ah = albedo_height.copy()
    new_ah[..., :3] = np.clip(to_srgb(rgb) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    new_h = np.clip(height + 0.12 * (bump - bump.mean()) / (bump.std() + 1e-9) * 0.35, 0.0, 1.0)
    new_ah[..., 3] = np.clip(new_h * 255.0 + 0.5, 0, 255).astype(np.uint8)

    # normals: the micro height's slope added to the painted normal (OpenGL +Y), periodic
    gx = (np.roll(bump, -1, axis=1) - np.roll(bump, 1, axis=1)) * 0.5
    gy = (np.roll(bump, -1, axis=0) - np.roll(bump, 1, axis=0)) * 0.5
    nrm = normal_rough[..., :3].astype(np.float64) / 255.0 * 2.0 - 1.0
    s = recipe["normal"] * 0.25 * k
    nrm[..., 0] -= gx * s
    nrm[..., 1] += gy * s
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True) + 1e-9
    new_nr = normal_rough.copy()
    new_nr[..., :3] = np.clip((nrm * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    # roughness: pebbles a touch smoother, cinders glassy-black
    rough = normal_rough[..., 3].astype(np.float64) / 255.0 - 0.08 * peb - 0.25 * specks
    new_nr[..., 3] = np.clip(rough * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return new_ah, new_nr


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("slots", nargs="+")
    ap.add_argument("--dir", default=TEXTURES)
    ap.add_argument("--out", default="", help="write here instead of in place")
    ap.add_argument("--preview", action="store_true", help="also write <slot>_micro_preview.png")
    args = ap.parse_args()
    out = args.out or args.dir
    os.makedirs(out, exist_ok=True)
    for slot in args.slots:
        recipe = RECIPES[slot]
        a_path = os.path.join(args.dir, "%s_albedo_height.png" % slot)
        n_path = os.path.join(args.dir, "%s_normal_rough.png" % slot)
        ah = np.asarray(Image.open(a_path).convert("RGBA"))
        nr = np.asarray(Image.open(n_path).convert("RGBA"))
        new_ah, new_nr = apply(ah, nr, recipe, seed=sum(map(ord, slot)))
        Image.fromarray(new_ah, "RGBA").save(os.path.join(out, "%s_albedo_height.png" % slot), optimize=True)
        Image.fromarray(new_nr, "RGBA").save(os.path.join(out, "%s_normal_rough.png" % slot), optimize=True)
        if args.preview:
            Image.fromarray(new_ah[..., :3]).crop((0, 0, 512, 512)).save(os.path.join(out, "%s_micro_preview.png" % slot))
        print("%s: micro layer written to %s" % (slot, out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
