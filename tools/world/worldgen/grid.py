"""Coordinate conventions (docs/CONTRACTS.md section 1 and 6).

World origin is the centre; x east, z south; bounds +-size_m/2. Arrays are [row=z, col=x].
Texel (i, j) sits at world (x0 + j*spacing, z0 + i*spacing), matching a Terrain3D import at
global_position (x0, 0, z0). Cells are 256 m: cx = floor((x + size/2) / 256).
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class Grid:
    size_m: float
    n: int
    cell_size_m: float = 256.0

    @property
    def spacing(self) -> float:
        return self.size_m / self.n

    @property
    def x0(self) -> float:
        return -self.size_m / 2.0

    @property
    def z0(self) -> float:
        return -self.size_m / 2.0

    @property
    def cells(self) -> int:
        return int(round(self.size_m / self.cell_size_m))

    @property
    def texels_per_cell(self) -> int:
        return self.n // self.cells

    def with_n(self, n: int) -> "Grid":
        return Grid(self.size_m, n, self.cell_size_m)

    # --- conversions ---------------------------------------------------------------------
    def to_tex(self, x, z):
        """World metres -> fractional texel coordinates (j, i)."""
        return (np.asarray(x) - self.x0) / self.spacing, (np.asarray(z) - self.z0) / self.spacing

    def to_world(self, j, i):
        return self.x0 + np.asarray(j) * self.spacing, self.z0 + np.asarray(i) * self.spacing

    def clamp_index(self, j, i):
        j = np.clip(np.rint(j).astype(np.int64), 0, self.n - 1)
        i = np.clip(np.rint(i).astype(np.int64), 0, self.n - 1)
        return j, i

    def coords(self, dtype=np.float32):
        """World x and z coordinate vectors (1-D) for this grid."""
        x = (self.x0 + np.arange(self.n, dtype=np.float64) * self.spacing).astype(dtype)
        z = (self.z0 + np.arange(self.n, dtype=np.float64) * self.spacing).astype(dtype)
        return x, z

    def mesh(self, dtype=np.float32):
        """Broadcastable world coordinate arrays X[1, n], Z[n, 1]."""
        x, z = self.coords(dtype)
        return x[None, :], z[:, None]

    def cell_of(self, x, z):
        cx = np.floor((np.asarray(x) + self.size_m / 2.0) / self.cell_size_m).astype(np.int64)
        cz = np.floor((np.asarray(z) + self.size_m / 2.0) / self.cell_size_m).astype(np.int64)
        return cx, cz

    def written_cell(self, x: float, z: float) -> tuple:
        """The cell a thing at (x, z) is filed in: the one its coordinates stand in as a cell file
        writes them, to the centimetre, clamped to the world. Filed by the unrounded position, a
        tuft 4 mm short of a cell's edge was written on the edge and read as the next cell's."""
        cx, cz = self.cell_of(np.array([round(float(x), 2)]), np.array([round(float(z), 2)]))
        return (int(np.clip(cx[0], 0, self.cells - 1)), int(np.clip(cz[0], 0, self.cells - 1)))


def sample_bilinear(arr: np.ndarray, grid: Grid, x, z) -> np.ndarray:
    """Bilinear sample of a [z, x] array at world coordinates."""
    fj, fi = grid.to_tex(x, z)
    fj = np.clip(fj, 0, grid.n - 1.001)
    fi = np.clip(fi, 0, grid.n - 1.001)
    j0 = np.floor(fj).astype(np.int64)
    i0 = np.floor(fi).astype(np.int64)
    tj = (fj - j0).astype(np.float32)
    ti = (fi - i0).astype(np.float32)
    j1 = np.minimum(j0 + 1, grid.n - 1)
    i1 = np.minimum(i0 + 1, grid.n - 1)
    a = arr[i0, j0] * (1 - tj) + arr[i0, j1] * tj
    b = arr[i1, j0] * (1 - tj) + arr[i1, j1] * tj
    return a * (1 - ti) + b * ti


def sample_nearest(arr: np.ndarray, grid: Grid, x, z) -> np.ndarray:
    fj, fi = grid.to_tex(x, z)
    j, i = grid.clamp_index(fj, fi)
    return arr[i, j]


def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=np.float32) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t
