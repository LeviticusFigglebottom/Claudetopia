"""Nothing made or grown stands in the water.

Every placer checks the water mask where it puts a thing down: the scatter, the hedges, the
roadside, the standing stones. But the mask is the build's texels, and a river narrower than two
of them is only partly in it. On a 1024 build (8 m texels) fence posts, a milestone, two signposts,
a willow and a juniper stood inside a river's banks. A cart in a Briarwold river was the batch 3
shots' version of it. So after everything is placed, this sweeps the buckets once. A prop or a tree
is taken out if it stands within a river's channel (its drawn half-width, measured to the
centreline, not the texel), in an oxbow or a plunge pool, or on the water mask. Rock and plants are
left: stones in a beck and reeds in the shallows are where they belong.
"""
from __future__ import annotations

import numpy as np

from .grid import Grid, sample_nearest
from .rows import Rows

## the categories of asset that never stand in water (and a standing stone, which somebody set up
## on dry ground: one stood in a Skerrow beck), and how far clear of a channel's edge
DRY_CATEGORIES = ("/props/", "/trees/", "_standing_stone_")
CHANNEL_MARGIN_M = 0.8
## how finely a river's centreline is walked for the distance to it
WALK_M = 1.0


def _channel(rivers: list):
    """A KD tree over every river's (and oxbow's and pool's) centreline, walked every WALK_M, and
    the half-width at each point."""
    from scipy.spatial import cKDTree

    pts, half = [], []
    for r in rivers:
        p = np.asarray(r.points, dtype=np.float64)[:, :2]
        w = np.asarray(r.width, dtype=np.float64)
        if p.shape[0] < 2:
            continue
        seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
        cum = np.concatenate([[0.0], np.cumsum(seg)])
        s = np.arange(0.0, float(cum[-1]) + 1e-6, WALK_M)
        pts.append(np.stack([np.interp(s, cum, p[:, 0]), np.interp(s, cum, p[:, 1])], axis=1))
        half.append(0.5 * np.interp(s, cum, w))
    if not pts:
        return None, None
    return cKDTree(np.concatenate(pts)), np.concatenate(half)


def sweep(buckets: dict, grid: Grid, rivers: list, water_mask: np.ndarray) -> dict:
    """Take every prop and tree standing in water out of `buckets` (in place). `rivers` are the
    hydro.River list with their oxbows and pools (hydro.with_oxbows). Returns {asset: count}."""
    tree, half = _channel(rivers)
    dropped: dict = {}
    for key in list(buckets):
        by_asset = buckets[key]
        for asset in list(by_asset):
            if not any(c in asset for c in DRY_CATEGORIES):
                continue
            rows = by_asset[asset]
            if not len(rows):
                continue
            if isinstance(rows, Rows):
                xz = rows.xz()
            else:
                xz = np.array([(float(r[0]), float(r[2])) for r in rows], dtype=np.float64)
            wet = sample_nearest(water_mask, grid, xz[:, 0], xz[:, 1]) > 0
            if tree is not None:
                d, i = tree.query(xz)
                wet |= d < half[i] + CHANNEL_MARGIN_M
            if not wet.any():
                continue
            dropped[asset] = dropped.get(asset, 0) + int(wet.sum())
            if isinstance(rows, Rows):
                rows.keep(~wet)
                if not len(rows):
                    del by_asset[asset]
                continue
            keep = [r for r, w in zip(rows, wet) if not w]
            if keep:
                by_asset[asset] = keep
            else:
                del by_asset[asset]
    return dropped
