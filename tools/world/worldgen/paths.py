"""Least-cost paths on a coarse lattice (rivers and roads share this machinery).

A coarse grid (16 m per cell by default) is turned into a sparse 8-neighbour digraph whose
edge cost is set by a caller-supplied function of the two endpoint heights and the cell
weights; scipy's Dijkstra then gives an exact least-cost route. This is both faster and far
more believable than hand-walking a gradient, and it is what makes rivers sit in valleys and
roads sit on gentle grades.
"""
from __future__ import annotations

import numpy as np
from scipy import ndimage
from scipy.sparse import coo_matrix, csgraph

NEIGHBOURS = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]


def build_graph(h: np.ndarray, cell_m: float, climb_penalty: float, descent_bonus: float,
                area_cost: np.ndarray, blocked: np.ndarray | None = None) -> csgraph.csr_matrix:
    """Directed graph: cost = length * (area_cost + climb_penalty*max(0, dh)/len - descent_bonus*...)."""
    n = h.shape[0]
    idx = np.arange(n * n, dtype=np.int64).reshape(n, n)
    rows, cols, data = [], [], []
    for dy, dx in NEIGHBOURS:
        ys = slice(max(0, -dy), n - max(0, dy))
        xs = slice(max(0, -dx), n - max(0, dx))
        ys2 = slice(max(0, dy), n - max(0, -dy))
        xs2 = slice(max(0, dx), n - max(0, -dx))
        a = idx[ys, xs].ravel()
        b = idx[ys2, xs2].ravel()
        length = float(np.hypot(dx, dy)) * cell_m
        dh = (h[ys2, xs2] - h[ys, xs]).ravel()
        grade = dh / length
        base = 0.5 * (area_cost[ys, xs] + area_cost[ys2, xs2]).ravel()
        c = length * (base + climb_penalty * np.maximum(grade, 0.0) - descent_bonus * np.minimum(grade, 0.0))
        c = np.maximum(c, 0.01 * length)
        if blocked is not None:
            bad = (blocked[ys, xs] | blocked[ys2, xs2]).ravel()
            c = np.where(bad, np.inf, c)
        ok = np.isfinite(c)
        rows.append(a[ok]); cols.append(b[ok]); data.append(c[ok].astype(np.float64))
    return coo_matrix((np.concatenate(data), (np.concatenate(rows), np.concatenate(cols))),
                      shape=(n * n, n * n)).tocsr()


def shortest_path(graph, n: int, start_ij: tuple, goal_mask: np.ndarray) -> list:
    """Least-cost route from one cell to the nearest cell of goal_mask. Returns [(i, j), ...]."""
    src = int(start_ij[0]) * n + int(start_ij[1])
    dist, pred = csgraph.dijkstra(graph, directed=True, indices=src, return_predecessors=True)
    goals = np.flatnonzero(goal_mask.ravel())
    if goals.size == 0:
        return []
    d = dist[goals]
    if not np.isfinite(d).any():
        return []
    end = int(goals[int(np.argmin(d))])
    path = []
    cur = end
    guard = 0
    while cur != -9999 and cur >= 0 and guard < n * n:
        path.append((cur // n, cur % n))
        if cur == src:
            break
        cur = int(pred[cur])
        guard += 1
    path.reverse()
    return path


def path_between(graph, n: int, start_ij: tuple, goal_ij: tuple) -> list:
    mask = np.zeros((n, n), dtype=bool)
    mask[int(goal_ij[0]), int(goal_ij[1])] = True
    return shortest_path(graph, n, start_ij, mask)


def smooth_polyline(points: list, passes: int = 4, keep_ends: bool = True) -> np.ndarray:
    """Chaikin-ish smoothing of an [(x, z), ...] list into a smooth float array."""
    p = np.asarray(points, dtype=np.float64)
    if p.shape[0] < 3:
        return p
    for _ in range(passes):
        q = p.copy()
        q[1:-1] = 0.25 * p[:-2] + 0.5 * p[1:-1] + 0.25 * p[2:]
        if not keep_ends:
            q[0] = 0.5 * (p[0] + p[1])
            q[-1] = 0.5 * (p[-1] + p[-2])
        p = q
    return p


def resample_polyline(points: np.ndarray, step_m: float) -> np.ndarray:
    """Even spacing along a polyline."""
    p = np.asarray(points, dtype=np.float64)
    if p.shape[0] < 2:
        return p
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    total = s[-1]
    if total < step_m:
        return p
    t = np.arange(0.0, total, step_m)
    t = np.append(t, total)
    out = np.stack([np.interp(t, s, p[:, 0]), np.interp(t, s, p[:, 1])], axis=1)
    return out


def rasterise_polyline(points: np.ndarray, grid, value: np.ndarray | None = None,
                       out_mask: np.ndarray | None = None, out_value: np.ndarray | None = None):
    """Stamp a polyline (world metres) into a texel mask, optionally carrying a per-point value."""
    n = grid.n
    if out_mask is None:
        out_mask = np.zeros((n, n), dtype=bool)
    dense = resample_polyline(points, grid.spacing * 0.5)
    j, i = grid.to_tex(dense[:, 0], dense[:, 1])
    j, i = grid.clamp_index(j, i)
    out_mask[i, j] = True
    if value is not None and out_value is not None:
        seg = np.linalg.norm(np.diff(points, axis=0), axis=1)
        s = np.concatenate([[0.0], np.cumsum(seg)])
        sd = np.linalg.norm(np.diff(dense, axis=0), axis=1)
        sdense = np.concatenate([[0.0], np.cumsum(sd)])
        v = np.interp(sdense, s, value)
        out_value[i, j] = v
    return out_mask, out_value


def field_from_mask(mask: np.ndarray, values: np.ndarray):
    """Distance (texels) to the nearest mask cell and that cell's value, for every texel."""
    dist, (ii, jj) = ndimage.distance_transform_edt(~mask, return_indices=True)
    return dist.astype(np.float32), values[ii, jj]
