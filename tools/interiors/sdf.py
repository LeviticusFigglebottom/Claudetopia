"""Signed-distance field primitives and fractal noise, vectorised over a voxel grid.

Convention: the field is negative inside open space (air the player walks through) and
positive inside solid rock. Marching cubes at level 0 therefore gives the cave wall.
"""
from __future__ import annotations

import numpy as np
from scipy import ndimage


def grid(bounds_min, bounds_max, voxel: float):
    """Return (X, Y, Z) coordinate arrays and the grid shape for a world-space box."""
    bounds_min = np.asarray(bounds_min, dtype=np.float32)
    bounds_max = np.asarray(bounds_max, dtype=np.float32)
    n = np.maximum(np.ceil((bounds_max - bounds_min) / voxel).astype(int) + 1, 2)
    axes = [np.linspace(bounds_min[i], bounds_min[i] + (n[i] - 1) * voxel, n[i], dtype=np.float32) for i in range(3)]
    X, Y, Z = np.meshgrid(*axes, indexing="ij")
    return X, Y, Z, tuple(n), bounds_min


def fbm(shape, rng: np.random.Generator, octaves: int = 4, base: int = 6, gain: float = 0.5, lacunarity: float = 2.0) -> np.ndarray:
    """Smooth fractal noise in [-1, 1] over `shape`, built by upsampling random grids."""
    out = np.zeros(shape, dtype=np.float32)
    amp = 1.0
    total = 0.0
    res = base
    for _ in range(octaves):
        low = rng.standard_normal((max(res, 2),) * 3).astype(np.float32)
        zoom = [s / low.shape[i] for i, s in enumerate(shape)]
        out += amp * ndimage.zoom(low, zoom, order=3, mode="nearest")[: shape[0], : shape[1], : shape[2]]
        total += amp
        amp *= gain
        res = int(res * lacunarity)
    out /= max(total, 1e-6)
    peak = float(np.abs(out).max())
    return out / peak if peak > 1e-6 else out


def sphere(X, Y, Z, centre, radius: float) -> np.ndarray:
    c = np.asarray(centre, dtype=np.float32)
    return np.sqrt((X - c[0]) ** 2 + (Y - c[1]) ** 2 + (Z - c[2]) ** 2) - radius


def ellipsoid(X, Y, Z, centre, radii) -> np.ndarray:
    """Approximate (gradient-corrected) ellipsoid distance; good enough for blending."""
    c = np.asarray(centre, dtype=np.float32)
    r = np.asarray(radii, dtype=np.float32)
    px, py, pz = (X - c[0]) / r[0], (Y - c[1]) / r[1], (Z - c[2]) / r[2]
    k0 = np.sqrt(px * px + py * py + pz * pz)
    qx, qy, qz = px / r[0], py / r[1], pz / r[2]
    k1 = np.sqrt(qx * qx + qy * qy + qz * qz)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def capsule(X, Y, Z, a, b, radius_a: float, radius_b: float | None = None) -> np.ndarray:
    """Round tunnel between two points, radius lerped along its length."""
    a = np.asarray(a, dtype=np.float32)
    b = np.asarray(b, dtype=np.float32)
    if radius_b is None:
        radius_b = radius_a
    ab = b - a
    denom = float(np.dot(ab, ab)) or 1e-6
    px, py, pz = X - a[0], Y - a[1], Z - a[2]
    t = np.clip((px * ab[0] + py * ab[1] + pz * ab[2]) / denom, 0.0, 1.0).astype(np.float32)
    dx = px - t * ab[0]
    dy = py - t * ab[1]
    dz = pz - t * ab[2]
    r = radius_a + (radius_b - radius_a) * t
    return np.sqrt(dx * dx + dy * dy + dz * dz) - r


def box_tunnel(X, Y, Z, a, b, half_w: float, half_h: float) -> np.ndarray:
    """Squared-off passage between two points: a mined adit or a masonry corridor.

    Cross-section is a rectangle in the plane perpendicular to the run, with a slight
    arch produced by rounding the top corners.
    """
    a = np.asarray(a, dtype=np.float32)
    b = np.asarray(b, dtype=np.float32)
    ab = b - a
    length = float(np.linalg.norm(ab)) or 1e-6
    d = ab / length
    up = np.array([0.0, 1.0, 0.0], dtype=np.float32)
    if abs(float(np.dot(d, up))) > 0.95:
        up = np.array([1.0, 0.0, 0.0], dtype=np.float32)
    side = np.cross(d, up)
    side /= max(float(np.linalg.norm(side)), 1e-6)
    up = np.cross(side, d)
    px, py, pz = X - a[0], Y - a[1], Z - a[2]
    t = px * d[0] + py * d[1] + pz * d[2]
    u = px * side[0] + py * side[1] + pz * side[2]
    v = px * up[0] + py * up[1] + pz * up[2]
    qt = np.abs(t - length * 0.5) - length * 0.5
    qu = np.abs(u) - half_w
    qv = np.abs(v) - half_h
    qt = np.maximum(qt, 0.0)
    qu_c = np.maximum(qu, 0.0)
    qv_c = np.maximum(qv, 0.0)
    outside = np.sqrt(qt * qt + qu_c * qu_c + qv_c * qv_c)
    inside = np.minimum(np.maximum(np.abs(t - length * 0.5) - length * 0.5, np.maximum(qu, qv)), 0.0)
    return outside + inside


def cone(X, Y, Z, tip, height: float, radius: float) -> np.ndarray:
    """Stalactite (negative height) or stalagmite (positive), tip at `tip`."""
    c = np.asarray(tip, dtype=np.float32)
    h = abs(height)
    sign = 1.0 if height > 0 else -1.0
    y = (Y - c[1]) * sign
    rad = np.sqrt((X - c[0]) ** 2 + (Z - c[2]) ** 2)
    taper = radius * np.clip(y / max(h, 1e-6), 0.0, 1.0)
    body = np.maximum(rad - taper, -y)
    return np.maximum(body, y - h)


def smooth_union(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    """Blend two fields so chambers and tunnels meet in a fillet, not a seam."""
    if k <= 1e-5:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1.0 - h) + a * h - k * h * (1.0 - h)


def smooth_subtract(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    """`a` with `b` taken out of it, blended over `k`: max(a, -b) with a fillet.

    The two terms of the blend were the wrong way round, (-b) where h is 0 and a where it is 1,
    which is max(a, -b) only inside the fillet: everywhere else it answered -b, so every column,
    rubble heap and stalactite turned all the rock round it into open space -- in Hollin Barrow
    88% of the field was air, and the bottom layer of the grid was open over three quarters of
    the plan."""
    h = np.clip(0.5 - 0.5 * (b + a) / k, 0.0, 1.0)
    return a * (1.0 - h) + (-b) * h + k * h * (1.0 - h)
