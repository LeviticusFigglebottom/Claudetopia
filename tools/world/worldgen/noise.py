"""Spectral noise bank.

Fractal fields are synthesised in the frequency domain: white noise -> FFT -> 1/f^beta amplitude
with a smooth band-pass in *metres* -> inverse FFT -> unit variance. This is deterministic from
the seed, tileable, and fast enough for 4096^2 (about 1.5 s per field). Large-scale bands are
generated on a fixed 1024^2 lattice and upsampled, so a --size 1024 build and a full build share
the same large-scale layout.
"""
from __future__ import annotations

from collections import OrderedDict

import numpy as np
from scipy import ndimage

from .grid import Grid, smoothstep


def _band_filter(n: int, spacing_m: float, beta: float, wl_min: float | None, wl_max: float | None,
                 aniso: tuple | None = None) -> np.ndarray:
    fy = np.fft.fftfreq(n)[:, None].astype(np.float32)
    fx = np.fft.rfftfreq(n)[None, :].astype(np.float32)
    f = np.sqrt(fx * fx + fy * fy)  # cycles per texel
    f[0, 0] = 1.0
    amp = f ** (-beta)
    if aniso is not None:
        # elongate structures along direction theta0 by damping frequencies parallel to it
        theta0, strength = np.radians(aniso[0]), float(aniso[1])
        c = (fx * np.cos(theta0) + fy * np.sin(theta0)) / f
        amp *= np.exp(-strength * c * c)
    f_m = f / spacing_m  # cycles per metre
    if wl_max is not None:  # suppress wavelengths longer than wl_max
        lo = 1.0 / wl_max
        amp *= smoothstep(lo * 0.6, lo * 1.4, f_m)
    if wl_min is not None:  # suppress wavelengths shorter than wl_min
        hi = 1.0 / wl_min
        amp *= 1.0 - smoothstep(hi * 0.7, hi * 1.3, f_m)
    amp[0, 0] = 0.0
    return amp.astype(np.float32)


## How much generated noise a bank keeps for reuse, in bytes. A field is deterministic from the
## seed and its salt, so one that has been let go is simply made again when it is next asked for.
## Kept without a limit, a 4096 build of the atlas held every field it had ever made: the 42 at
## full resolution that break up the provinces' borders (2.7 GB) and two per range at 2048, and
## the build was killed at 10.1 GB. The least recently used go first.
CACHE_BUDGET_BYTES = 512 * 1024 * 1024


class NoiseBank:
    """Seeded generator of unit-variance fractal fields on a grid."""

    def __init__(self, seed: int, grid: Grid, base_n: int = 1024, budget_bytes: int | None = None):
        self.seed = int(seed)
        self.grid = grid
        self.base_n = min(base_n, grid.n)
        self.budget = CACHE_BUDGET_BYTES if budget_bytes is None else int(budget_bytes)
        self._cache: OrderedDict = OrderedDict()
        self._bytes = 0

    def _cached(self, key):
        out = self._cache.get(key)
        if out is not None:
            self._cache.move_to_end(key)
        return out

    def _keep(self, key, value: np.ndarray) -> None:
        self._cache[key] = value
        self._bytes += value.nbytes
        while self._bytes > self.budget and self._cache:
            _k, old = self._cache.popitem(last=False)
            self._bytes -= old.nbytes

    def _rng(self, salt: int) -> np.random.Generator:
        return np.random.default_rng(np.random.SeedSequence([self.seed, int(salt) & 0xFFFFFFFF]))

    def field(self, salt: int, beta: float = 1.8, wl_min: float | None = None, wl_max: float | None = None,
              n: int | None = None, aniso: tuple | None = None) -> np.ndarray:
        """Unit-variance fractal field at resolution n (default: base lattice, upsampled to grid)."""
        key = (salt, beta, wl_min, wl_max, n, aniso)
        hit = self._cached(key)
        if hit is not None:
            return hit
        gen_n = self.base_n if n is None else n
        g = self.grid.with_n(gen_n)
        white = self._rng(salt).standard_normal((gen_n, gen_n), dtype=np.float32)
        spec = np.fft.rfft2(white)
        spec *= _band_filter(gen_n, g.spacing, beta, wl_min, wl_max, aniso)
        out = np.fft.irfft2(spec, s=(gen_n, gen_n)).astype(np.float32)
        std = float(out.std())
        if std > 1e-8:
            out /= std
        self._keep(key, out)
        return out

    def field_at(self, salt: int, n: int, beta: float = 1.8, wl_min: float | None = None,
                 wl_max: float | None = None, aniso: tuple | None = None) -> np.ndarray:
        """Field generated on the base lattice, upsampled (cubic) to n x n."""
        key = ("up", salt, beta, wl_min, wl_max, aniso, n)
        hit = self._cached(key)
        if hit is not None:
            return hit
        base = self.field(salt, beta, wl_min, wl_max, aniso=aniso)
        out = upsample(base, n)
        self._keep(key, out)
        return out

    def forget(self) -> None:
        """Drop cached fields (memory)."""
        self._cache.clear()
        self._bytes = 0

    def detail(self, salt: int, n: int, wl_min: float, wl_max: float, beta: float = 1.6) -> np.ndarray:
        """High-frequency field generated directly at resolution n."""
        return self.field(salt, beta, wl_min, wl_max, n=n)


def upsample(a: np.ndarray, n: int, order: int = 3) -> np.ndarray:
    if a.shape[0] == n:
        return a
    if a.shape[0] > n:
        step = a.shape[0] // n
        return a[::step, ::step].copy()
    z = n / a.shape[0]
    return ndimage.zoom(a, z, order=order, mode="nearest", grid_mode=True).astype(np.float32)


def downsample(a: np.ndarray, n: int) -> np.ndarray:
    """Block-mean downsample of a [m, m] array to [n, n]; upsamples instead if n is larger."""
    m = a.shape[0]
    if m == n:
        return a
    if n > m:
        return upsample(a, n, order=1)
    f = m // n
    if f * n != m:                      # not a clean factor: fall back to resampling
        return upsample(a, n, order=1)
    return a.reshape(n, f, n, f).mean(axis=(1, 3)).astype(a.dtype)


def warp(field: np.ndarray, dx: np.ndarray, dz: np.ndarray, order: int = 1) -> np.ndarray:
    """Sample `field` at (i + dz, j + dx) texel offsets (domain warp), wrapping at the borders."""
    n = field.shape[0]
    ii, jj = np.meshgrid(np.arange(n, dtype=np.float32), np.arange(n, dtype=np.float32), indexing="ij")
    return ndimage.map_coordinates(field, [ii + dz, jj + dx], order=order, mode="wrap").astype(np.float32)


def ridged(field: np.ndarray, sharpness: float = 1.0) -> np.ndarray:
    """1 - |f| ridges from a unit field, remapped to 0..1 with optional sharpening."""
    r = 1.0 - np.abs(field) / 2.5
    r = np.clip(r, 0.0, 1.0)
    if sharpness != 1.0:
        r = r ** sharpness
    return r.astype(np.float32)


def terrace(h: np.ndarray, step: float, riser: float = 0.35) -> np.ndarray:
    """Soft quantisation: flat treads with short smooth risers (fraction `riser` of a step)."""
    q = h / step
    base = np.floor(q)
    frac = q - base
    t = np.clip((frac - (1.0 - riser)) / riser, 0.0, 1.0)
    t = t * t * (3 - 2 * t)
    return ((base + t) * step).astype(np.float32)
