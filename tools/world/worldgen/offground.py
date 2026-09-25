"""Nothing is left standing in the air or under the hill: the last pass over the scatter.

The w4096c scan of every row against the ground under its whole footprint found 72 of 5.7 million
far off it, all cliff ledges: sea-cliff beds laid a few metres out from a face that turns at a
cove's corner (Cinderlea's at 88 and 105 m over a beach at half a metre), and crag ledges set back
into a plateau from the edge they were meant for (a Skerrow course 33 m under the fell top). Each
placing pass seats its own pieces and is tested for it; this is the net under them all. A row whose
foot stands more than OFF_M over the highest ground anywhere under its footprint is floating, and
one whose top is more than OFF_M under the lowest ground under it is buried: both are taken out, and
the build log says how many of each kind so the pass that laid them can be found.
"""
from __future__ import annotations

import os

import numpy as np

from .cells import asset_bounds
from .grid import Grid, sample_bilinear
from .rows import Rows

OFF_M = 2.0
## the footprint is read at its middle and at this many points round its rim
RIM_POINTS = 8


def _kind(asset: str) -> str:
    name = os.path.splitext(os.path.basename(asset))[0]
    return name.split("_", 1)[1] if "_" in name else name


def off_ground(H: np.ndarray, grid: Grid, x, y, z, scale, half: float, height: float) -> tuple:
    """(floating, buried) bool arrays for pieces at (x, y, z) of `scale`, their footprint `half`
    across and `height` tall at scale one."""
    x, y, z, scale = (np.asarray(v, dtype=np.float64) for v in (x, y, z, scale))
    a = np.linspace(0.0, 2.0 * np.pi, RIM_POINTS, endpoint=False)
    r = (half * scale)[:, None]
    xs = np.concatenate([x[:, None], x[:, None] + r * np.cos(a)], axis=1)
    zs = np.concatenate([z[:, None], z[:, None] + r * np.sin(a)], axis=1)
    gy = sample_bilinear(H, grid, xs.ravel(), zs.ravel()).reshape(xs.shape)
    floating = y - gy.max(axis=1) > OFF_M
    buried = gy.min(axis=1) - (y + height * scale) > OFF_M
    return floating, buried


def sweep(buckets: dict, grid: Grid, H: np.ndarray, repo_root: str = ".", dump: list | None = None) -> dict:
    """In place: every row in `buckets` floating or buried by more than OFF_M taken out. Returns
    {kind: [floating, buried]}. `dump`, a list, gets [asset, row, "floating" | "buried"] for each
    row taken out (the build writes it where WICKMERE_OFFGROUND_DUMP says)."""
    out: dict = {}
    for key in list(buckets):
        by_asset = buckets[key]
        for asset in list(by_asset):
            rows = by_asset[asset]
            if not len(rows):
                continue
            half, height = asset_bounds(asset, repo_root)
            if isinstance(rows, Rows):
                x, y, z, s = (rows.column(k, n) for k, n in ((0, "x"), (1, "y"), (2, "z"), (4, "scale")))
            else:
                arr = np.array([(float(r[0]), float(r[1]), float(r[2]), float(r[4]) if len(r) > 4 else 1.0)
                                for r in rows], dtype=np.float64)
                x, y, z, s = arr[:, 0], arr[:, 1], arr[:, 2], arr[:, 3]
            floating, buried = off_ground(H, grid, x, y, z, s, half, height)
            bad = floating | buried
            if not bad.any():
                continue
            got = out.setdefault(_kind(asset), [0, 0])
            got[0] += int(floating.sum())
            got[1] += int(buried.sum())
            if dump is not None:
                listed = rows if not isinstance(rows, Rows) else list(rows)
                for r, f, b_ in zip(listed, floating, buried):
                    if f or b_:
                        dump.append([asset, list(r), "floating" if f else "buried"])
            if isinstance(rows, Rows):
                rows.keep(~bad)
                if not len(rows):
                    del by_asset[asset]
                continue
            keep = [r for r, b in zip(rows, bad) if not b]
            if keep:
                by_asset[asset] = keep
            else:
                del by_asset[asset]
    return out
