"""Drainage: sink filling, D8 flow accumulation and valley carving.

Fractal noise alone gives mazy, unbelievable land: ridges that go nowhere and hollows with no
outlet. Running a real (if cheap) drainage pass over the composed heights gives every region
a dendritic valley network that water would actually cut, which is what makes the chalk downs
read as downs and the karst read as karst -- and it is also what the river tracer then follows.

The pass runs on a coarse lattice (8 m or so); the carve is upsampled and the fine detail band
is added on top afterwards.
"""
from __future__ import annotations

import numpy as np
from scipy import ndimage

D8 = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]


def fill_sinks(h: np.ndarray, eps: float = 0.002, iterations: int = 70) -> np.ndarray:
    """Planchon-Darboux style sink filling (relaxation form, plenty for shallow noise pits)."""
    big = float(h.max()) + 1000.0
    w = np.full_like(h, big)
    w[0, :] = h[0, :]
    w[-1, :] = h[-1, :]
    w[:, 0] = h[:, 0]
    w[:, -1] = h[:, -1]
    for _ in range(iterations):
        m = ndimage.minimum_filter(w, size=3, mode="nearest") + eps
        nw = np.maximum(h, np.minimum(w, m))
        if np.allclose(nw, w, atol=1e-4):
            w = nw
            break
        w = nw
    return w.astype(np.float32)


def flow_accumulation(h: np.ndarray, cell_m: float) -> np.ndarray:
    """D8 accumulation in cells drained (1 = ridge top). Input should be sink-filled."""
    n = h.shape[0]
    best_drop = np.zeros((n, n), dtype=np.float32)
    recv = np.full((n, n), -1, dtype=np.int64)
    idx = np.arange(n * n, dtype=np.int64).reshape(n, n)
    for dy, dx in D8:
        ys = slice(max(0, -dy), n - max(0, dy))
        xs = slice(max(0, -dx), n - max(0, dx))
        ys2 = slice(max(0, dy), n - max(0, -dy))
        xs2 = slice(max(0, dx), n - max(0, -dx))
        drop = (h[ys, xs] - h[ys2, xs2]) / (float(np.hypot(dx, dy)) * cell_m)
        better = drop > best_drop[ys, xs]
        sub = recv[ys, xs]
        sub[better] = idx[ys2, xs2][better]
        recv[ys, xs] = sub
        subd = best_drop[ys, xs]
        subd[better] = drop[better]
        best_drop[ys, xs] = subd
    acc = np.ones(n * n, dtype=np.float32)
    order = np.argsort(h.ravel(), kind="stable")[::-1]
    recv_flat = recv.ravel()
    for cell in order:                      # high ground first: every cell is settled before its receiver
        r = recv_flat[cell]
        if r >= 0:
            acc[r] += acc[cell]
    return acc.reshape(n, n)


def channel_field(h: np.ndarray, cell_m: float, knee: float = 60.0, power: float = 0.42,
                  jitter: np.ndarray | None = None) -> np.ndarray:
    """0..1 "how much of a valley is this": log-scaled, normalised flow accumulation.

    Unitless on purpose -- the caller multiplies it by a per-region depth in metres, so the
    result has to mean the same thing at 2 m and at 32 m per texel.

    `jitter` (metres) is added to the land the water is routed over, not to the land that is
    cut. On a long even slope -- a dale side drawn as one plane, a range's flank -- D8 routing
    runs every cell straight down in parallel lines that merge on the grid's own diagonals, and
    the carve combed the whole hillside with rills a few cells apart. A few metres of
    low-frequency unevenness is what a real hillside has, and it gathers the water into gills.
    """
    route = h if jitter is None else h + jitter
    filled = fill_sinks(ndimage.gaussian_filter(route, 1.0))
    acc = flow_accumulation(filled, cell_m)
    a = np.log1p(acc / knee)
    a = a / max(float(np.percentile(a, 99.9)), 1e-6)
    chan = np.clip(a, 0.0, 1.0) ** power
    return ndimage.gaussian_filter(chan, 1.2).astype(np.float32)


def valley_carve(h: np.ndarray, cell_m: float, depth_m: np.ndarray, strength: np.ndarray,
                 knee: float = 60.0, power: float = 0.42, jitter: np.ndarray | None = None) -> tuple:
    """Deepen the drainage network by up to depth_m metres. Returns (heights, channel field)."""
    chan = channel_field(h, cell_m, knee, power, jitter)
    carved = h - depth_m * chan * strength
    # a valley floor is smoother than the ridges it cuts through (metres either way: this is
    # a blend between two height fields, never scaled by the depth again)
    smooth = ndimage.gaussian_filter(carved, 2.0)
    out = carved + (smooth - carved) * (0.55 * chan)
    return out.astype(np.float32), chan
