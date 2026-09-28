#!/usr/bin/env python3
"""Tiling detail maps for what the people wear, read by game/assets/shaders/garment.gdshader.

    python3 tools/forge/gen_character_detail.py

The garments are baked at 384 px over a whole garment: enough for the colour of a cloth and its
folds, nowhere near enough for a thread, a pore in leather or a hammer mark, and lit smooth they read
as painted plastic. These are small maps that tile many times over a garment's UVs, so the surface
has a grain at any distance:

    weave_normal.png     a plain weave, over-and-under, with fibre fuzz        (cloth)
    grain_normal.png     leather: a cellular crease pattern and pores           (leather)
    hammer_normal.png    metal: overlapping shallow dents                       (iron)
    mottle.png           R: large, soft mottling (dye and wear), G: fibres,     (all)
                         B: small scuffs and scratches, all tiling, 0.5 = none
    skin_detail_normal.png  pores and the fine criss-cross of skin creases      (skin.gdshader)

Everything is periodic by construction (integer frequencies, wrapped distances), so no seam shows."""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "game", "assets", "textures", "characters")
N = 256
rng = np.random.default_rng(20260924)
yy, xx = np.mgrid[0:N, 0:N] / N          # 0..1, periodic


def fbm(octaves, base=2, falloff=0.55, seed=0):
    """Tiling fractal noise from integer-frequency waves with random phases, normalised to 0..1."""
    r = np.random.default_rng(seed)
    h = np.zeros((N, N))
    amp = 1.0
    for o in range(octaves):
        f = base * 2 ** o
        for _ in range(16):
            kx, ky = r.integers(-f, f + 1, size=2)
            if kx == 0 and ky == 0:
                continue
            h += amp * np.cos(2 * np.pi * (kx * xx + ky * yy) + r.uniform(0, 2 * np.pi))
        amp *= falloff
    h -= h.min()
    return h / max(h.max(), 1e-9)


def worley(cells, seed=0):
    """Distance to the nearest of `cells` random points, wrapped (tiling), normalised 0..1; and the id."""
    r = np.random.default_rng(seed)
    pts = r.uniform(0, 1, size=(cells, 2))
    best = np.full((N, N), 9.0)
    second = np.full((N, N), 9.0)
    for px, py in pts:
        dx = np.abs(xx - px)
        dy = np.abs(yy - py)
        dx = np.minimum(dx, 1 - dx)
        dy = np.minimum(dy, 1 - dy)
        d = np.sqrt(dx * dx + dy * dy)
        second = np.where(d < best, best, np.minimum(second, d))
        best = np.minimum(best, d)
    return best, second


def to_normal(h, strength):
    gy, gx = np.gradient(h)
    # wrap the gradient at the edges so the map tiles
    gx[:, 0] = (h[:, 1] - h[:, -1]) * 0.5
    gx[:, -1] = (h[:, 0] - h[:, -2]) * 0.5
    gy[0, :] = (h[1, :] - h[-1, :]) * 0.5
    gy[-1, :] = (h[0, :] - h[-2, :]) * 0.5
    n = np.stack([-gx * strength, -gy * strength, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save(name, arr):
    os.makedirs(OUT, exist_ok=True)
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
    img.save(os.path.join(OUT, name))
    print("wrote", os.path.join(OUT, name))


def weave():
    threads = 16                                   # threads each way per tile
    u, v = xx * threads, yy * threads
    iu, iv = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = u - iu, v - iv
    over = ((iu + iv) % 2 == 0)                    # which thread is on top in this cell
    warp = np.sin(np.pi * fu) ** 0.7               # a warp thread's round section, across u
    weft = np.sin(np.pi * fv) ** 0.7
    # the thread on top bulges along its length through the cell; the one under dips
    along_w = 0.55 + 0.45 * np.sin(np.pi * fv)
    along_f = 0.55 + 0.45 * np.sin(np.pi * fu)
    h = np.where(over, warp * along_w, weft * along_f)
    fuzz = fbm(4, base=24, seed=3)
    h = h * 0.85 + fuzz * 0.15
    return h


def skin_detail():
    """Skin's micro-relief: small round pits (pores) of uneven size and depth, set in the fine
    criss-cross of creases skin has everywhere, two families of short lines at an angle, broken
    up. Shallow: under the engine's light it is a grain in the sheen, not a texture you see."""
    d1, d2 = worley(420, seed=21)
    pores = 1.0 - np.clip(d1 * 64.0, 0, 1) ** 1.5          # a pit at each point
    size = fbm(2, base=4, seed=22)
    pores = pores * (0.4 + 0.6 * size)
    cells = np.clip((d2 - d1) * 30.0, 0, 1)                  # the ridges between pore cells
    creases = np.zeros((N, N))
    for k, (ax, ay) in enumerate(((5, 3), (-4, 5), (7, -2))):
        wave = np.cos(2 * np.pi * (ax * 6 * xx + ay * 6 * yy) + fbm(2, base=3, seed=30 + k) * 6.0)
        line = np.clip((wave - 0.86) / 0.14, 0, 1)
        creases += line * np.clip(fbm(2, base=4, seed=40 + k) * 2.0 - 0.6, 0, 1)
    h = 0.55 * cells - 0.65 * pores - 0.18 * np.clip(creases, 0, 1) + 0.15 * fbm(3, base=16, seed=23)
    return h


def main() -> int:
    save("skin_detail_normal.png", to_normal(skin_detail(), 4.0))
    save("weave_normal.png", to_normal(weave(), 6.0))
    d1, d2 = worley(90, seed=5)
    crease = np.clip((d2 - d1) * 14.0, 0, 1)        # thin valleys where cells meet
    pores = fbm(3, base=40, seed=6)
    grain = crease * 0.8 + pores * 0.2
    save("grain_normal.png", to_normal(grain, 3.0))
    dents_d, _ = worley(40, seed=9)
    dents = 1.0 - np.clip(dents_d * 6.5, 0, 1) ** 2
    hammer = -dents + fbm(3, base=6, seed=10) * 0.3
    save("hammer_normal.png", to_normal(hammer, 7.0))
    big = fbm(4, base=2, seed=11)
    fibre = fbm(3, base=32, seed=12)
    sd, _ = worley(160, seed=13)
    scratch = fbm(2, base=50, seed=14)
    scuffs = np.clip(1.0 - sd * 18.0, 0, 1) * (scratch > 0.62)
    mottle = np.stack([0.5 + (big - 0.5) * 0.9, 0.5 + (fibre - 0.5) * 0.9, 0.5 + scuffs * 0.5], axis=-1)
    save("mottle.png", mottle)
    return 0


if __name__ == "__main__":
    sys.exit(main())
