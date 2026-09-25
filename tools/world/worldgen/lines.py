"""The pieces of a line (a hedge, a drystone wall, a post-and-rail) set on the ground along their whole
length, and no stub of one left standing alone.

A line piece was set down at the ground under its middle. A drystone wall module is 2.4 m long;
laid across a 1 in 2 bank, its downhill end stood 0.6 m over the ground. The 4096 shots for playtest 6
("fences along roads that seem randomly placed, missing or clipping") had a Skerrow wall piece
standing out over a brow. A boundary broken by the slope and water checks also left runs of one or
two pieces in open ground. `seat` puts each piece's middle at the lower of the ground under its two
ends, less LINE_SINK_M, so both ends are in the ground. It then takes out every piece with fewer than
STUB_NEIGHBOURS of its own kind within STUB_REACH_M.
"""
from __future__ import annotations

import math
import os

import numpy as np

from .grid import Grid, sample_bilinear
from .rows import Rows

## a line's kinds, and each piece's half-length at scale one (its run lies along its own +X)
HALF_M = {"drystone_wall_end": 0.45, "drystone_wall": 1.2, "hedge_segment": 1.05, "fence_post_rail": 1.18}
LINE_SINK_M = 0.08
STUB_REACH_M = 5.5
STUB_NEIGHBOURS = 2


def _kind(asset: str) -> str | None:
    name = os.path.basename(asset)
    for k in HALF_M:                        # (the wall's end before the wall: it is its prefix)
        if "_" + k + "_" in name:
            return k
    return None


def seat(buckets: dict, grid: Grid, H: np.ndarray) -> dict:
    """In place: every line piece in `buckets` set down on the ground at both its ends, and the stubs
    taken out. Returns {"pieces", "stubs"}."""
    from scipy.spatial import cKDTree

    counts = {"pieces": 0, "stubs": 0}
    where: dict = {}
    for key, by_asset in buckets.items():
        for asset, rows in by_asset.items():
            kind = _kind(asset)
            if kind is None or isinstance(rows, Rows) or not rows:
                continue
            arr = np.array([(float(r[0]), float(r[2]), float(r[3]), float(r[4])) for r in rows], dtype=np.float64)
            a = np.radians(arr[:, 2])
            h = HALF_M[kind] * arr[:, 3]
            ex, ez = np.cos(a) * h, -np.sin(a) * h
            ends = np.minimum(sample_bilinear(H, grid, arr[:, 0] + ex, arr[:, 1] + ez),
                              sample_bilinear(H, grid, arr[:, 0] - ex, arr[:, 1] - ez))
            mid = sample_bilinear(H, grid, arr[:, 0], arr[:, 1])
            y = np.minimum(ends, mid) - LINE_SINK_M
            for r, v in zip(rows, y.tolist()):
                r[1] = round(v, 2)
            counts["pieces"] += len(rows)
            family = "drystone_wall" if kind.startswith("drystone_wall") else kind
            where.setdefault(family, []).append((key, asset, arr[:, :2]))
    for family, parts in where.items():
        pts = np.concatenate([p for _, _, p in parts])
        if pts.shape[0] == 0:
            continue
        tree = cKDTree(pts)
        near = np.array([len(n) - 1 for n in tree.query_ball_point(pts, STUB_REACH_M)])
        at = 0
        for key, asset, p in parts:
            keep = near[at:at + p.shape[0]] >= STUB_NEIGHBOURS
            at += p.shape[0]
            if keep.all():
                continue
            counts["stubs"] += int((~keep).sum())
            rows = buckets[key][asset]
            buckets[key][asset] = [r for r, k in zip(rows, keep) if k]
            if not buckets[key][asset]:
                del buckets[key][asset]
    return counts
