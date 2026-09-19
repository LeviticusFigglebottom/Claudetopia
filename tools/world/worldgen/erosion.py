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


def valley_carve(h: np.ndarray, cell_m: float, strength: np.ndarray, max_depth: float = 30.0,
                 knee: float = 60.0, power: float = 0.42) -> tuple:
    """Deepen the drainage network. Returns (carved heights, 0..1 channel-ness)."""
    filled = fill_sinks(ndimage.gaussian_filter(h, 1.0))
    acc = flow_accumulation(filled, cell_m)
    # normalised channel strength: log so trunk valleys are only a few times deeper than heads
    a = np.log1p(acc / knee)
    a = a / max(float(np.percentile(a, 99.9)), 1e-6)
    chan = np.clip(a, 0.0, 1.0) ** power
    chan = ndimage.gaussian_filter(chan, 1.2)
    depth = max_depth * chan * strength
    carved = h - depth
    # the valley floor should be smoother than the ridges it cuts through
    smooth = ndimage.gaussian_filter(carved, 2.0)
    out = carved + (smooth - carved) * (0.55 * chan)
    return out.astype(np.float32), chan.astype(np.float32)
