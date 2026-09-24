#!/usr/bin/env python3
"""Generate the 21 Wickmere terrain textures (docs/CONTRACTS.md section 5).

Writes, for every slot, a seamless 1024x1024 pair into game/assets/textures/terrain/:

    <name>_albedo_height.png   RGB albedo, A height
    <name>_normal_rough.png    RGB normal (OpenGL +Y), A roughness

The look follows DESIGN.md section 7.0: painterly, not photographic. Every layer is built
from band-limited spectral noise (periodic, so the tiles are seamless by construction),
quantised into a few soft colour bands ("strokes") with a little edge wear, plus one
material-specific feature layer -- pebbles, cracks, blades, ripples, laid stones. Micro
detail is deliberately restrained; the height channel carries the story instead.

    tools/world/gen_terrain_textures.py            # all slots
    tools/world/gen_terrain_textures.py chalk moss # named slots only
    tools/world/gen_terrain_textures.py --size 512 --out /tmp/tex
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from worldgen.grid import Grid, lerp, smoothstep
from worldgen.noise import NoiseBank, ridged

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_OUT = os.path.join(REPO, "game", "assets", "textures", "terrain")
SEED = 20260919


def hexcol(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


class Painter:
    """Seamless painterly layers on one tile."""

    def __init__(self, name: str, size: int, tile_m: float, seed: int):
        self.name = name
        self.size = size
        self.tile_m = tile_m
        self.grid = Grid(tile_m, size)
        self.bank = NoiseBank(seed + (abs(hash(name)) % 100000), self.grid, base_n=size)
        self.rng = np.random.default_rng(np.random.SeedSequence([seed, abs(hash(name)) % 100000]))

    def f(self, salt: int, beta=1.8, wl_min=None, wl_max=None, aniso=None) -> np.ndarray:
        """Unit-variance periodic field; wavelengths are in metres on the tile."""
        return self.bank.field(salt, beta=beta, wl_min=wl_min, wl_max=wl_max, n=self.size, aniso=aniso)

    def warp(self, field: np.ndarray, salt: int, amount_m: float, wl: float = 0.5) -> np.ndarray:
        px = amount_m / self.grid.spacing
        dx = px * self.f(salt, 1.8, wl * 0.35, wl)
        dz = px * self.f(salt + 1, 1.8, wl * 0.35, wl)
        n = self.size
        ii, jj = np.meshgrid(np.arange(n, dtype=np.float32), np.arange(n, dtype=np.float32), indexing="ij")
        return ndimage.map_coordinates(field, [ii + dz, jj + dx], order=1, mode="wrap").astype(np.float32)

    # --- layers ---------------------------------------------------------------------------
    def bands(self, salt: int, steps: int, wl: float, softness: float = 0.35, aniso=None) -> np.ndarray:
        """Quantised 0..1 field: the painterly 'big strokes' that carry colour."""
        v = 0.5 + 0.5 * np.tanh(self.f(salt, 1.9, wl * 0.3, wl, aniso) * 0.8)
        v = self.warp(v, salt + 37, wl * 0.12, wl * 0.6)
        q = v * steps
        k = np.floor(q)
        frac = q - k
        e = smoothstep(0.5 - softness * 0.5, 0.5 + softness * 0.5, frac)
        return np.clip((k + e) / steps, 0.0, 1.0).astype(np.float32)

    def mottle(self, salt: int, wl: float, aniso=None) -> np.ndarray:
        return (0.5 + 0.5 * np.tanh(self.f(salt, 1.8, wl * 0.25, wl, aniso))).astype(np.float32)

    def strokes(self, salt: int, wl: float, angle: float, strength: float = 1.0) -> np.ndarray:
        """Directional brush texture, -1..1."""
        v = self.f(salt, 1.6, wl * 0.15, wl, aniso=(angle, 3.5))
        return (np.tanh(v * 1.2) * strength).astype(np.float32)

    def points(self, count: int, r_min_m: float, r_max_m: float, salt: int = 0, power: float = 2.0):
        """Toroidal bumps: returns (height 0..1, ownership id map, per-point radius px)."""
        n = self.size
        rng = np.random.default_rng(np.random.SeedSequence([self.bank.seed, 5000 + salt]))
        h = np.zeros((n, n), dtype=np.float32)
        ids = np.zeros((n, n), dtype=np.int32)
        best = np.zeros((n, n), dtype=np.float32)
        px_per_m = n / self.tile_m
        cx = rng.integers(0, n, count)
        cy = rng.integers(0, n, count)
        radii = rng.uniform(r_min_m, r_max_m, count) * px_per_m
        squash = rng.uniform(0.6, 1.0, count)
        rot = rng.uniform(0.0, np.pi, count)
        for k in range(count):
            r = max(2.0, float(radii[k]))
            w = int(r) + 2
            yy, xx = np.mgrid[-w:w + 1, -w:w + 1].astype(np.float32)
            ca, sa = np.cos(rot[k]), np.sin(rot[k])
            u = (xx * ca + yy * sa)
            v = (-xx * sa + yy * ca) / squash[k]
            d = np.sqrt(u * u + v * v) / r
            bump = np.clip(1.0 - d * d, 0.0, 1.0) ** (power * 0.5)
            ys = (np.arange(-w, w + 1) + cy[k]) % n
            xs = (np.arange(-w, w + 1) + cx[k]) % n
            sub = h[np.ix_(ys, xs)]
            np.maximum(sub, bump, out=sub)
            h[np.ix_(ys, xs)] = sub
            sb = best[np.ix_(ys, xs)]
            take = bump > sb
            si = ids[np.ix_(ys, xs)]
            si[take] = k + 1
            ids[np.ix_(ys, xs)] = si
            sb[take] = bump[take]
            best[np.ix_(ys, xs)] = sb
        return h, ids, radii

    def blades(self, count: int, length_m: float, width_m: float, salt: int, lean: float = 0.35) -> np.ndarray:
        """Short directional strokes: grass blades, reeds, heather twigs."""
        n = self.size
        rng = np.random.default_rng(np.random.SeedSequence([self.bank.seed, 7000 + salt]))
        h = np.zeros((n, n), dtype=np.float32)
        px = n / self.tile_m
        L = max(3.0, length_m * px)
        W = max(1.0, width_m * px)
        cx = rng.integers(0, n, count)
        cy = rng.integers(0, n, count)
        ang = rng.uniform(0, 2 * np.pi, count)
        w = int(L) + 2
        yy, xx = np.mgrid[-w:w + 1, -w:w + 1].astype(np.float32)
        for k in range(count):
            ca, sa = np.cos(ang[k]), np.sin(ang[k])
            u = xx * ca + yy * sa
            v = -xx * sa + yy * ca
            bend = lean * (u / L) ** 2 * L
            d = np.abs(v - bend) / W
            along = np.clip(1.0 - np.abs(u) / L, 0.0, 1.0)
            blade = np.clip(1.0 - d, 0.0, 1.0) ** 1.5 * along
            ys = (np.arange(-w, w + 1) + cy[k]) % n
            xs = (np.arange(-w, w + 1) + cx[k]) % n
            sub = h[np.ix_(ys, xs)]
            np.maximum(sub, blade, out=sub)
            h[np.ix_(ys, xs)] = sub
        return h

    def voronoi(self, cells: int, jitter: float, salt: int, warp_cells: float = 0.0, warp_wl: float = 0.6):
        """Toroidal Voronoi. Returns (f1, f2, id): nearest and second distance in cell units.

        Real ground breaks into plates, clints and packed stones; Voronoi cells read as those
        far better than ridged noise, which always ends up looking like worms.
        """
        n = self.size
        rng = np.random.default_rng(np.random.SeedSequence([self.bank.seed, 8100 + salt]))
        step = n / float(cells)
        jx = (rng.random((cells, cells)) - 0.5) * 2.0 * jitter
        jy = (rng.random((cells, cells)) - 0.5) * 2.0 * jitter
        y, x = np.mgrid[0:n, 0:n].astype(np.float32)
        if warp_cells > 0.0:
            # keep the warp well under one cell, or the cells smear into worms
            px = min(warp_cells, 0.2) * step
            x = x + px * self.f(salt + 91, 1.8, warp_wl * 0.3, warp_wl)
            y = y + px * self.f(salt + 92, 1.8, warp_wl * 0.3, warp_wl)
        gx = x / step
        gy = y / step
        ci = np.floor(gx).astype(np.int32)
        cj = np.floor(gy).astype(np.int32)
        f1 = np.full((n, n), 1e9, dtype=np.float32)
        f2 = np.full((n, n), 1e9, dtype=np.float32)
        ids = np.zeros((n, n), dtype=np.int32)
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                ai = (ci + ox) % cells
                aj = (cj + oy) % cells
                fx = (ci + ox) + 0.5 + jx[aj, ai]
                fy = (cj + oy) + 0.5 + jy[aj, ai]
                d = np.hypot(gx - fx, gy - fy)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                ids = np.where(closer, aj * cells + ai, ids)
                f1 = np.where(closer, d, f1)
        return f1.astype(np.float32), f2.astype(np.float32), ids

    def plates(self, cells: int, jitter: float, salt: int, seam: float = 0.09, warp_cells: float = 0.0,
               flat: float = 0.55):
        """Flat plates parted by seams: (plate height 0..1, seam mask 0..1, ids).

        `edge` is the distance to the nearest cell boundary (in cell units), so a plate is a
        plateau that falls away only in the last `seam` of its width -- clints and grykes,
        not blobs.
        """
        f1, f2, ids = self.voronoi(cells, jitter, salt, warp_cells=warp_cells)
        edge = (f2 - f1) * 0.5                          # distance to the shared boundary
        seam_mask = (1.0 - smoothstep(0.0, seam, edge)).astype(np.float32)
        body = np.clip(smoothstep(seam * 0.9, seam * 0.9 + flat * 0.5, edge), 0.0, 1.0)
        return body.astype(np.float32), seam_mask, ids

    def pebbles_field(self, cells: int, jitter: float, salt: int, radius: float = 0.5,
                      crease: float = 0.06, warp_cells: float = 0.0):
        """Packed rounded stones: a hemispherical dome per site, creased where stones touch."""
        f1, f2, ids = self.voronoi(cells, jitter, salt, warp_cells=warp_cells)
        dome = np.sqrt(np.clip(1.0 - (f1 / max(radius, 1e-3)) ** 2, 0.0, 1.0))
        edge = (f2 - f1) * 0.5
        dome = dome * np.clip(edge / max(crease, 1e-3), 0.0, 1.0) ** 0.6
        return dome.astype(np.float32), ids

    def cracks(self, salt: int, wl: float, sharp: float = 8.0) -> np.ndarray:
        """Thin dark seams (bedding planes, dried mud, fused stone joints)."""
        v = ridged(self.f(salt, 1.9, wl * 0.25, wl), 1.0)
        v = self.warp(v, salt + 11, wl * 0.05, wl * 0.5)
        return np.clip((v - (1.0 - 1.0 / sharp)) * sharp, 0.0, 1.0).astype(np.float32)


def colour_from_bands(pal: list, band: np.ndarray, mottle: np.ndarray) -> np.ndarray:
    """Blend a palette along a 0..1 band field, with a second field shifting the mix."""
    cols = np.stack([hexcol(c) for c in pal])          # [k, 3]
    k = cols.shape[0] - 1
    t = np.clip(band * 0.75 + mottle * 0.25, 0.0, 1.0) * k
    i0 = np.clip(np.floor(t).astype(np.int32), 0, k)
    i1 = np.clip(i0 + 1, 0, k)
    f = (t - i0)[..., None]
    return (cols[i0] * (1.0 - f) + cols[i1] * f).astype(np.float32)


def normal_from_height(h: np.ndarray, strength: float, size: int) -> np.ndarray:
    """OpenGL (+Y) tangent-space normal from a height field, wrapping at the edges."""
    hp = np.pad(h, 1, mode="wrap")
    dx = (hp[1:-1, 2:] - hp[1:-1, :-2]) * 0.5
    dy = (hp[2:, 1:-1] - hp[:-2, 1:-1]) * 0.5
    nx = -dx * strength * size / 256.0
    ny = dy * strength * size / 256.0        # +Y up (OpenGL): invert the image-space gradient
    nz = np.ones_like(nx)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l, ny / l, nz / l], axis=-1).astype(np.float32)


# --- material recipes -----------------------------------------------------------------------

def mat_grass(p: Painter, spec: dict) -> tuple:
    band = p.bands(11, spec.get("steps", 4), spec.get("band_wl", 1.6), 0.5)
    mott = p.mottle(13, spec.get("mottle_wl", 0.55))
    alb = colour_from_bands(spec["colors"], band, mott)
    blade = p.blades(spec.get("blades", 2600), spec.get("blade_len", 0.075), spec.get("blade_w", 0.010), 3)
    blade = np.maximum(blade, 0.55 * p.blades(spec.get("blades", 2600) // 2, spec.get("blade_len", 0.075) * 1.5,
                                              spec.get("blade_w", 0.010), 4))
    tip = hexcol(spec.get("tip", spec["colors"][-1]))
    alb = lerp(alb, tip[None, None, :], (blade * 0.55)[..., None])
    alb *= (1.0 + 0.07 * p.strokes(17, 0.8, spec.get("angle", 35.0)))[..., None]
    if spec.get("flowers"):
        fh, fid, _ = p.points(spec["flowers"][1], 0.006, 0.013, salt=9)
        fcol = hexcol(spec["flowers"][0])
        alb = lerp(alb, fcol[None, None, :], np.clip(fh * 1.6, 0, 1)[..., None])
    h = 0.42 + 0.30 * blade + 0.16 * band + 0.08 * mott
    rough = 0.82 + 0.10 * mott - 0.06 * blade
    return alb, h, rough, spec.get("normal_strength", 1.5)


def mat_soil(p: Painter, spec: dict) -> tuple:
    band = p.bands(21, spec.get("steps", 3), spec.get("band_wl", 1.3), 0.55)
    mott = p.mottle(23, 0.45)
    alb = colour_from_bands(spec["colors"], band, mott)
    grit, gid, _ = p.points(spec.get("grit", 900), 0.008, 0.022, salt=5, power=1.6)
    gcol = hexcol(spec.get("grit_colour", spec["colors"][0]))
    alb = lerp(alb, gcol[None, None, :], (grit * 0.45)[..., None])
    if spec.get("crack_cells"):
        _, crack_seam, _ = p.plates(spec["crack_cells"], 0.45, 27, seam=spec.get("crack_seam", 0.05),
                                    warp_cells=spec.get("crack_warp", 0.08))
        crack = crack_seam * spec.get("cracks", 0.0)
    else:
        crack = p.cracks(27, spec.get("crack_wl", 0.9), spec.get("crack_sharp", 10.0)) * spec.get("cracks", 0.0)
    alb *= (1.0 - 0.35 * crack)[..., None]
    alb *= (1.0 + 0.06 * p.strokes(29, 0.7, 12.0))[..., None]
    h = 0.45 + 0.22 * grit + 0.18 * band - 0.28 * crack + 0.08 * mott
    rough = spec.get("rough", 0.88) + 0.08 * mott - 0.05 * grit
    return alb, h, rough, spec.get("normal_strength", 1.8)


def mat_rock(p: Painter, spec: dict) -> tuple:
    """Bedrock as plates parted by fissures: clints and grykes, granite blocks, fused slabs."""
    body, seams, ids = p.plates(spec.get("cells", 6), spec.get("jitter", 0.42), 31,
                                seam=spec.get("seam", 0.06), warp_cells=spec.get("plate_warp", 0.1))
    _, fine_seams, _ = p.plates(spec.get("cells", 6) * 3, 0.45, 33, seam=spec.get("seam", 0.06) * 0.8,
                                warp_cells=spec.get("plate_warp", 0.1) * 0.6)
    seams = np.clip(seams + 0.5 * fine_seams * spec.get("fine_seams", 1.0), 0.0, 1.0)
    mott = p.mottle(35, 0.7, aniso=spec.get("aniso"))
    band = p.bands(37, spec.get("steps", 4), spec.get("band_wl", 2.2), 0.4, aniso=spec.get("aniso"))
    alb = colour_from_bands(spec["colors"], band, mott)
    # each plate keeps its own value, so the rock reads as blocks rather than clouds
    rng = np.random.default_rng(np.random.SeedSequence([p.bank.seed, 311]))
    tint = rng.uniform(0.86, 1.16, int(ids.max()) + 1).astype(np.float32)[ids]
    alb = alb * lerp(np.ones_like(tint), tint, 0.85 * body)[..., None]
    dark = hexcol(spec.get("seam_colour", spec["colors"][0]))
    alb = lerp(alb, dark[None, None, :], (seams ** 1.4 * 0.9)[..., None])
    # bedding: faint parallel grain across each plate, the way sedimentary rock splits
    bed = 0.5 + 0.5 * np.tanh(p.f(45, 1.7, 0.06, 0.45, aniso=(spec.get("bedding_angle", 20.0), 4.0)) * 1.4)
    alb *= (1.0 - spec.get("bedding", 0.10) * (bed - 0.5))[..., None]
    if spec.get("lichen"):
        lichen = np.clip(p.mottle(41, 0.3) - 0.58, 0.0, 1.0) * spec["lichen"] * 5.0
        lichen *= (0.35 + 0.65 * body)
        alb = lerp(alb, hexcol(spec.get("lichen_colour", "#8a9a64"))[None, None, :],
                   np.clip(lichen, 0, 0.8)[..., None])
    alb *= (1.0 + 0.045 * p.strokes(43, 1.1, spec.get("angle", 0.0)))[..., None]
    h = 0.40 + 0.34 * body + 0.14 * band * body - 0.34 * seams ** 1.3 + 0.05 * mott \
        + 0.05 * spec.get("bedding", 0.10) * 10.0 * (bed - 0.5) * body
    rough = spec.get("rough", 0.78) + 0.09 * mott + 0.10 * seams
    return alb, h, rough, spec.get("normal_strength", 2.4)


def mat_pebbles(p: Painter, spec: dict) -> tuple:
    """Packed stones (shingle, scree): Voronoi cells domed into pebbles, gaps in shadow."""
    dome, ids = p.pebbles_field(spec.get("cells", 22), 0.44, 51, radius=spec.get("radius", 0.52),
                                crease=spec.get("crease", 0.06), warp_cells=spec.get("warp", 0.08))
    small, _ = p.pebbles_field(spec.get("cells", 22) * 2, 0.46, 53, radius=spec.get("radius", 0.52) * 0.9,
                               crease=spec.get("crease", 0.06), warp_cells=spec.get("warp", 0.08))
    stones = np.clip(np.maximum(dome, small * spec.get("small_mix", 0.55)), 0.0, 1.0)
    base_band = p.bands(55, 3, 1.1, 0.6)
    alb = colour_from_bands(spec["colors"], base_band, p.mottle(57, 0.4))
    rng = np.random.default_rng(np.random.SeedSequence([p.bank.seed, 61]))
    tintmap = rng.uniform(0.74, 1.26, int(ids.max()) + 1).astype(np.float32)
    alb = alb * lerp(np.ones_like(stones), tintmap[ids], np.clip(dome * 1.6, 0, 1))[..., None]
    grain = 1.0 + 0.10 * p.strokes(59, 0.35, 0.0)
    alb *= grain[..., None]
    crease = 1.0 - np.clip(stones * 2.2, 0.0, 1.0)           # only the creases darken
    alb *= (1.0 - 0.38 * crease)[..., None]
    gap = crease
    wet = spec.get("wet", 0.0)
    if wet:
        alb = lerp(alb, alb * 0.70, (gap * wet)[..., None])
    h = 0.26 + 0.62 * stones + 0.08 * base_band
    rough = spec.get("rough", 0.72) + 0.14 * gap - 0.3 * wet * gap
    return alb, h, rough, spec.get("normal_strength", 2.8)


def mat_cobbles(p: Painter, spec: dict) -> tuple:
    """Laid stones: a jittered grid of rounded blocks with mortar gaps."""
    n = p.size
    cells = spec.get("cells", 11)
    step = n / cells
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    rng = np.random.default_rng(np.random.SeedSequence([p.bank.seed, 71]))
    jx = rng.uniform(-0.22, 0.22, (cells, cells)).astype(np.float32)
    jy = rng.uniform(-0.22, 0.22, (cells, cells)).astype(np.float32)
    row = (y / step).astype(np.int32) % cells
    offset = (row % 2) * 0.5                      # every other row offset half a stone
    gx = (x / step + offset)
    col = gx.astype(np.int32) % cells
    fx = gx - np.floor(gx) - 0.5 + jx[row, col]
    fy = (y / step) - np.floor(y / step) - 0.5 + jy[row, col]
    d = np.maximum(np.abs(fx), np.abs(fy)) * 2.0
    stone = np.clip(1.0 - smoothstep(0.66, 0.95, d), 0.0, 1.0)
    round_h = stone * (1.0 - 0.45 * d * d)
    tint = rng.uniform(0.8, 1.2, (cells, cells)).astype(np.float32)[row, col]
    alb = colour_from_bands(spec["colors"], p.bands(73, 3, 1.4, 0.6), p.mottle(75, 0.5))
    alb = alb * lerp(np.ones_like(tint), tint, stone)[..., None]
    mortar = hexcol(spec.get("mortar", "#6a6660"))
    alb = lerp(mortar[None, None, :], alb, stone[..., None])
    wear = p.mottle(77, 0.3)
    alb *= (0.9 + 0.2 * wear)[..., None]
    h = 0.30 + 0.55 * round_h + 0.06 * wear
    rough = 0.62 + 0.25 * (1.0 - stone) + 0.08 * wear
    return alb, h, rough, spec.get("normal_strength", 3.2)


def mat_snow(p: Painter, spec: dict) -> tuple:
    drift = p.bands(81, 4, 2.4, 0.8, aniso=(20.0, 2.0))
    fine = p.mottle(83, 0.35)
    alb = colour_from_bands(spec["colors"], drift, fine)
    sparkle = np.clip(p.mottle(85, 0.06) - 0.78, 0.0, 1.0) * 4.0
    alb = np.clip(alb + sparkle[..., None] * 0.10, 0.0, 1.0)
    h = 0.45 + 0.35 * drift + 0.10 * fine
    rough = 0.42 + 0.22 * fine - 0.12 * sparkle
    return alb, h, rough, spec.get("normal_strength", 1.1)


def mat_sand(p: Painter, spec: dict) -> tuple:
    ripple = 0.5 + 0.5 * np.sin(p.f(91, 1.9, 0.25, 1.4, aniso=(spec.get("angle", 80.0), 3.0)) * 4.2)
    ripple = p.warp(ripple, 93, 0.05, 0.6)
    band = p.bands(95, 3, 1.8, 0.7)
    alb = colour_from_bands(spec["colors"], band, ripple * 0.6 + 0.2)
    wet = spec.get("wet", 0.0)
    if wet:
        pools = np.clip(p.mottle(97, 0.9) - 0.55, 0, 1) * 3.0
        alb = lerp(alb, alb * 0.62, np.clip(pools * wet, 0, 1)[..., None])
    grit, _, _ = p.points(spec.get("shells", 120), 0.006, 0.016, salt=6, power=1.4)
    alb = lerp(alb, hexcol(spec.get("shell_colour", "#efe6d2"))[None, None, :], (grit * 0.5)[..., None])
    h = 0.44 + 0.22 * ripple + 0.14 * band + 0.14 * grit
    rough = 0.80 + 0.10 * band - 0.3 * wet
    return alb, h, rough, spec.get("normal_strength", 1.4)


RECIPES = {"grass": mat_grass, "soil": mat_soil, "rock": mat_rock, "pebbles": mat_pebbles,
           "cobbles": mat_cobbles, "snow": mat_snow, "sand": mat_sand}

# The 21 slots of docs/CONTRACTS.md section 5, in id order.
MATERIALS = {
    "vale_grass": {"recipe": "grass", "tile_m": 2.6, "colors": ["#43613a", "#5b7c46", "#6f8f52", "#88a05e"],
                   "tip": "#9fae66", "blades": 3000, "flowers": ("#ded8b0", 130), "angle": 35.0},
    "chalk": {"recipe": "soil", "tile_m": 3.0, "colors": ["#b6b09c", "#cbc5b1", "#dcd6c2", "#e9e3d2"],
              "grit": 1200, "grit_colour": "#fbf8ee", "cracks": 0.4, "crack_cells": 6, "crack_seam": 0.035, "crack_warp": 0.1,
              "rough": 0.84, "normal_strength": 1.6},
    "dirt_path": {"recipe": "soil", "tile_m": 2.8, "colors": ["#4e4436", "#5e5241", "#70634e", "#84755d"],
                  "grit": 1500, "grit_colour": "#93856c", "cracks": 0.25, "rough": 0.9},
    "mud": {"recipe": "soil", "tile_m": 2.4, "colors": ["#2b2c20", "#3c3e2d", "#50533d", "#63664c"],
            "grit": 500, "grit_colour": "#6e7157", "cracks": 0.75, "crack_cells": 8, "crack_seam": 0.045,
            "crack_warp": 0.12, "rough": 0.6, "normal_strength": 2.2},
    "peat": {"recipe": "soil", "tile_m": 2.6, "colors": ["#1b1f13", "#282d1a", "#374024", "#47522e"],
             "grit": 700, "grit_colour": "#5f6b3e", "cracks": 0.35, "rough": 0.8},
    # Leaf litter, moss, exposed root and bare earth -- ochres and greens with structure in
    # them. A single brown is what says "texture" instead of "place".
    "forest_floor": {"recipe": "soil", "tile_m": 2.8, "colors": ["#2a3021", "#3c4226", "#5a4f2b", "#6f6338"],
                     "grit": 2600, "grit_colour": "#7e8a49", "cracks": 0.12, "rough": 0.88,
                     "normal_strength": 2.4},
    "moss": {"recipe": "grass", "tile_m": 1.8, "colors": ["#1f3a1c", "#2f5526", "#437032", "#5c8a3c"],
             "tip": "#7fa24a", "blades": 5200, "blade_len": 0.035, "blade_w": 0.006, "angle": 70.0,
             "normal_strength": 1.9},
    # The northern rock is weathered grey-brown with strata in it and lichen on it, not the blue
    # slate it was painted as: under Skerrow's cold light the fells read as blue-grey plastic
    # cracked into Voronoi cells. The seams are fewer, narrower and nearer the rock's own colour;
    # the bedding is stronger and level, so a cliff (Terrain3D projects steep ground sideways)
    # shows its strata.
    "granite": {"recipe": "rock", "tile_m": 3.4, "colors": ["#4f4943", "#665e55", "#7f766b", "#988e81"],
                "seam_colour": "#3a342e", "lichen": 0.3, "lichen_colour": "#8c8a6c", "cells": 4,
                "jitter": 0.45, "seam": 0.018, "plate_warp": 0.14, "fine_seams": 0.35, "bedding": 0.16,
                "bedding_angle": 4.0, "rough": 0.74, "normal_strength": 2.8},
    "limestone": {"recipe": "rock", "tile_m": 3.6, "colors": ["#6f6961", "#857e73", "#9c9486", "#b3aa99"],
                  "seam_colour": "#4d463d", "aniso": (10.0, 2.2), "cells": 3, "jitter": 0.4,
                  "seam": 0.016, "plate_warp": 0.16, "fine_seams": 0.15, "bedding": 0.3, "bedding_angle": 2.0,
                  "lichen": 0.3, "lichen_colour": "#9c9878", "rough": 0.8, "normal_strength": 3.0},
    "scree": {"recipe": "pebbles", "tile_m": 2.4, "colors": ["#544e47", "#6a635a", "#827a6e"],
              "cells": 15, "radius": 0.55, "crease": 0.05, "small_mix": 0.5, "warp": 0.1, "rough": 0.82,
              "normal_strength": 3.0},
    "snow": {"recipe": "snow", "tile_m": 3.2, "colors": ["#b9c6da", "#d2dcea", "#e6ecf4", "#f6f8fb"]},
    "heather": {"recipe": "grass", "tile_m": 2.2, "colors": ["#3a3a2c", "#4d4a33", "#5d5640", "#6e6349"],
                "tip": "#8a6a86", "blades": 4200, "blade_len": 0.05, "blade_w": 0.008,
                "flowers": ("#6e4a8a", 900), "angle": 15.0, "normal_strength": 2.0},
    # The black soil of the ash heath (WORLD_BIBLE 6.6), painted at a value it can be seen at like
    # every other slot and brought down by import_terrain.gd's `value`. It was painted as charcoal
    # (#121110 to #383532, a mean of 0.017 in linear light) and then multiplied down to 0.008
    # like the rest, and the Stair Head, where a new game begins, stood on black ground. These are
    # the old colours lifted in linear light (2.7 x c^0.85): a mean of 0.085, drawn at 0.044 (value 0.52), a
    # step under the grey grass. tools/world/ground_albedo.py prints every slot as it is drawn.
    "ash_soil": {"recipe": "soil", "tile_m": 2.6, "colors": ["#353331", "#484443", "#5d5a57", "#746f6a"],
                 "grit": 900, "grit_colour": "#a39c95", "cracks": 0.3, "rough": 0.92,
                 "normal_strength": 1.6},
    "grey_grass": {"recipe": "grass", "tile_m": 2.4, "colors": ["#3a3a36", "#4d4d47", "#5f5e56", "#706f66"],
                   "tip": "#83827a", "blades": 2600, "blade_len": 0.07, "flowers": ("#b23a2e", 12),
                   "angle": 50.0},
    "fused_stone": {"recipe": "rock", "tile_m": 4.0, "colors": ["#26242a", "#35323a", "#46424c", "#56515c"],
                    "seam_colour": "#101015", "cells": 3, "jitter": 0.12, "seam": 0.02, "plate_warp": 0.0, "bedding": 0.04,
                    "fine_seams": 0.25, "aniso": (45.0, 2.6), "rough": 0.42, "normal_strength": 1.8},
    "shingle": {"recipe": "pebbles", "tile_m": 2.0, "colors": ["#857f73", "#a39b8c", "#bdb4a2"],
                "cells": 26, "radius": 0.52, "crease": 0.05, "small_mix": 0.45, "warp": 0.08, "wet": 0.3, "rough": 0.6,
                "normal_strength": 3.2},
    "cobbles": {"recipe": "cobbles", "tile_m": 2.6, "colors": ["#5e5a55", "#767068", "#8d867c"],
                "mortar": "#4a463f", "cells": 10},
    "barley": {"recipe": "grass", "tile_m": 2.4, "colors": ["#8a7a34", "#a8963f", "#c2ab4c", "#d8c05c"],
               "tip": "#efd97a", "blades": 3600, "blade_len": 0.11, "blade_w": 0.009, "angle": 80.0,
               "normal_strength": 1.7},
    "orchard_grass": {"recipe": "grass", "tile_m": 2.4, "colors": ["#3f6236", "#537c42", "#688f4e", "#7fa25c"],
                      "tip": "#9dba62", "blades": 3400, "flowers": ("#ded0a4", 220), "angle": 20.0},
    "lake_bed": {"recipe": "soil", "tile_m": 2.8, "colors": ["#24312e", "#33433d", "#43554c", "#55675b"],
                 "grit": 1100, "grit_colour": "#6b7a6a", "cracks": 0.1, "rough": 0.45,
                 "normal_strength": 1.5},
    "sand_flats": {"recipe": "sand", "tile_m": 3.0, "colors": ["#8e8365", "#a89a76", "#c0b28a", "#d6c8a0"],
                   "wet": 0.5, "shells": 180},
}


# Godot import settings for these PNGs. The alpha channel carries height/roughness *data*,
# so alpha-border fixing must be off (it would bleed colour where alpha is dark), and every
# texture must import identically or Terrain3D cannot build one texture array from them.
IMPORT_PARAMS = {
    "compress/mode": "0",                 # lossless RGBA8: works headless, no editor codecs
    "compress/normal_map": "0",
    "compress/channel_pack": "1",         # channels are independent data, not colour+alpha
    "mipmaps/generate": "true",
    "process/fix_alpha_border": "false",
    "process/premult_alpha": "false",
    "process/normal_map_invert_y": "false",
    "detect_3d/compress_to": "0",         # never silently re-import when used in 3D
}


def write_import_settings(png_path: str) -> None:
    """Create or update <png>.import so Godot imports every slot the same way."""
    path = png_path + ".import"
    lines: list = []
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
    else:
        lines = ["[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "",
                 "[deps]", "", 'source_file="res://%s"' % os.path.relpath(
                     png_path, os.path.join(REPO, "game")).replace(os.sep, "/"), "", "[params]", ""]
    seen = set()
    out: list = []
    in_params = False
    for line in lines:
        if line.startswith("["):
            in_params = line.strip() == "[params]"
        if in_params and "=" in line:
            key = line.split("=", 1)[0].strip()
            if key in IMPORT_PARAMS:
                out.append("%s=%s" % (key, IMPORT_PARAMS[key]))
                seen.add(key)
                continue
        out.append(line)
    for key, value in IMPORT_PARAMS.items():
        if key not in seen:
            out.append("%s=%s" % (key, value))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out).rstrip() + "\n")


def generate(name: str, size: int, out_dir: str, seed: int = SEED) -> tuple:
    spec = MATERIALS[name]
    p = Painter(name, size, float(spec.get("tile_m", 2.5)), seed)
    alb, h, rough, nstrength = RECIPES[spec["recipe"]](p, spec)
    h = np.clip(h, 0.0, 1.0)
    # gentle contrast on the height so blending has something to bite on
    h = np.clip((h - h.mean()) * 1.25 + 0.5, 0.0, 1.0)
    nrm = normal_from_height(h, nstrength, size)
    rough = np.clip(rough, 0.05, 1.0)
    alb = np.clip(alb, 0.0, 1.0)
    albedo_height = np.concatenate([alb, h[..., None]], axis=-1)
    normal_rough = np.concatenate([nrm * 0.5 + 0.5, rough[..., None]], axis=-1)
    os.makedirs(out_dir, exist_ok=True)
    a_path = os.path.join(out_dir, "%s_albedo_height.png" % name)
    n_path = os.path.join(out_dir, "%s_normal_rough.png" % name)
    ah8 = (albedo_height * 255.0 + 0.5).astype(np.uint8)
    nr8 = (normal_rough * 255.0 + 0.5).astype(np.uint8)
    # the small scale at your feet -- grain, cinders, pebbles, ripples (terrain_micro.py)
    import terrain_micro
    if name in terrain_micro.RECIPES:
        ah8, nr8 = terrain_micro.apply(ah8, nr8, terrain_micro.RECIPES[name], seed=sum(map(ord, name)))
    Image.fromarray(ah8, "RGBA").save(a_path, optimize=True)
    Image.fromarray(nr8, "RGBA").save(n_path, optimize=True)
    if os.path.abspath(out_dir).startswith(os.path.join(REPO, "game")):
        write_import_settings(a_path)
        write_import_settings(n_path)
    return a_path, n_path


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Generate Wickmere terrain textures")
    ap.add_argument("slots", nargs="*", help="slot names (default: all 21)")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--out", type=str, default=DEFAULT_OUT)
    ap.add_argument("--seed", type=int, default=SEED)
    args = ap.parse_args(argv)
    names = args.slots or list(MATERIALS.keys())
    unknown = [n for n in names if n not in MATERIALS]
    if unknown:
        print("unknown slots: %s" % ", ".join(unknown))
        return 2
    import time
    t0 = time.time()
    for i, name in enumerate(names):
        t = time.time()
        a, n = generate(name, args.size, args.out, args.seed)
        print("  [%2d/%2d] %-14s %5.1fs  %s" % (i + 1, len(names), name, time.time() - t,
                                                os.path.basename(a)), flush=True)
    print("[textures] %d slots in %.1fs -> %s" % (len(names), time.time() - t0, args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
