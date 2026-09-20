"""Enclosed fields: the parcels a farmed landscape is divided into, and their boundaries.

The chalk downs of Hearthvale and the farmed shoulder of the lake basin are not open ground.
They are a patchwork of parcels, each carrying one crop, separated by hawthorn hedges and
flint walls that follow the parcel edges and not the contours. Without them the downs read as
one green blanket with noise patches on it, which is exactly what a generator produces and
exactly what a farmed country does not look like.

This builds the patchwork once, and everything else reads it:

* ``labels``  which parcel each texel belongs to (-1 where the land is not enclosed)
* ``edge_d``  metres to the nearest parcel boundary (1e6 where the land is not enclosed)

The texture rules pick a crop per parcel from its label, so a barley field has an edge a
hedge can sit on; the scatter places the hedge itself along ``edge_d``; and the colour map
darkens the boundary a little, so the line-work reads from a hilltop before a single bush has
been drawn. One pattern, three consumers, no disagreement about where a field is.

Parcels come from a jittered lattice of seeds, domain-warped so the boundaries wander like
land divided by walking rather than by surveying, then labelled by nearest seed.
"""
from __future__ import annotations

import numpy as np
from scipy import ndimage

from .grid import Grid
from .noise import upsample


def field_map(grid: Grid, bank, owner: np.ndarray, regions: list, shapes=("downs", "lake_basin"),
              spacing_m: float = 150.0, warp_m: float = 26.0, salt: int = 820,
              work_n: int = 2048) -> tuple:
    """Returns (labels int32, edge_d float32) at the full grid resolution.

    Computed on a coarser lattice and upsampled: a parcel is 165 m across and its boundary is
    a hedge two metres wide, so the extra resolution would cost two more distance transforms
    and move the line by less than a texel.
    """
    n = min(grid.n, work_n)
    step = grid.size_m / n

    enclosed = np.zeros((grid.n, grid.n), dtype=bool)
    for r in regions:
        if r.shape in shapes:
            enclosed |= owner == r.index
    if not enclosed.any():
        return (np.full((grid.n, grid.n), -1, dtype=np.int32),
                np.full((grid.n, grid.n), 1e6, dtype=np.float32))

    # seeds on a jittered lattice, in lattice coordinates
    per = max(int(round(grid.size_m / spacing_m)), 2)
    rng = np.random.default_rng(np.random.SeedSequence([bank.seed, salt]))
    gy, gx = np.meshgrid((np.arange(per) + 0.5) / per, (np.arange(per) + 0.5) / per, indexing="ij")
    jitter = 0.38 / per
    sy = np.clip(gy + rng.uniform(-jitter, jitter, gy.shape), 0.0, 0.999) * n
    sx = np.clip(gx + rng.uniform(-jitter, jitter, gx.shape), 0.0, 0.999) * n

    seeded = np.ones((n, n), dtype=bool)
    seeded[sy.astype(np.int32).ravel(), sx.astype(np.int32).ravel()] = False
    # nearest seed for every texel, which is the parcel it belongs to
    _, (iy, ix) = ndimage.distance_transform_edt(seeded, return_indices=True)
    labels = (iy.astype(np.int64) * n + ix.astype(np.int64)).astype(np.int64)

    # Warp the whole pattern so boundaries wander. Warping the labels rather than the seeds
    # keeps every parcel simply connected while bending its edges.
    a = warp_m / step
    dx = a * bank.field_at(salt + 1, n, beta=1.8, wl_min=90.0, wl_max=460.0)
    dz = a * bank.field_at(salt + 2, n, beta=1.8, wl_min=90.0, wl_max=460.0)
    yy, xx = np.meshgrid(np.arange(n), np.arange(n), indexing="ij")
    wy = np.clip(yy + dz, 0, n - 1).astype(np.int32)
    wx = np.clip(xx + dx, 0, n - 1).astype(np.int32)
    labels = labels[wy, wx]

    # boundary texels: a neighbour belongs to another parcel
    edge = np.zeros((n, n), dtype=bool)
    edge[:, :-1] |= labels[:, :-1] != labels[:, 1:]
    edge[:-1, :] |= labels[:-1, :] != labels[1:, :]
    if not edge.any():
        edge[0, 0] = True
    edge_d = (ndimage.distance_transform_edt(~edge) * step).astype(np.float32)

    if n != grid.n:
        edge_d = upsample(edge_d, grid.n, order=1).astype(np.float32)
        labels = np.repeat(np.repeat(labels, grid.n // n, axis=0), grid.n // n, axis=1)
    labels = labels.astype(np.int32)

    labels = np.where(enclosed, labels, np.int32(-1))
    edge_d = np.where(enclosed, edge_d, np.float32(1e6))
    return labels, edge_d


def parcel_value(labels: np.ndarray, salt: int, buckets: int = 1024) -> np.ndarray:
    """A stable pseudo-random 0..1 per parcel, for deciding what each field carries.

    The same label always gives the same number, so a field is one crop all the way to its
    hedge rather than a noise field that happens to cross it.
    """
    h = (labels.astype(np.int64) * np.int64(2654435761) + np.int64(salt) * np.int64(40503))
    h ^= h >> np.int64(13)
    h = (h * np.int64(1274126177)) & np.int64(0x7FFFFFFF)
    return ((h % buckets).astype(np.float32) / float(buckets - 1))
