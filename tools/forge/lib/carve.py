"""Carved stone for the landmarks: signed-distance figures and ruins, weathered, as meshes.

The first Choir colossi were lathed: a bell of robe with its folds as a cosine on the radius,
tube arms and a cylinder plinth, and from the ash plain they read as ribbed water tanks on a
blue drum. A carved figure is masses that flow into each other (a shoulder into a chest, a
sleeve off an arm), cut folds that deepen toward the hem, a break where the head was, and
erosion that eats the surface at every scale. That is what signed distance gives
(lib/sdf.py, the character forge's own core): smooth unions, subtractions, and a field that
noise can wear. This module is numpy only, so a figure can be looked at without Blender.

Z is up, metres, the figure faces -Y (the forge's front), and z = 0 is the ground line: the
base runs on below it, so it is buried rather than set down.
"""
from __future__ import annotations

import math
from typing import Callable, Sequence

import numpy as np

from . import sdf


# --- noise ---------------------------------------------------------------------------------

def _hash(ix, iy, iz, seed):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / float(0xFFFFFF)


def vnoise(P: np.ndarray, freq: float, seed: int = 0) -> np.ndarray:
    """Value noise in [0, 1] at points (n, 3), one cell per 1/freq metres."""
    q = P * freq
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3.0 - 2.0 * f)
    out = np.zeros(len(P))
    for dx in (0, 1):
        wx = f[:, 0] if dx else 1.0 - f[:, 0]
        for dy in (0, 1):
            wy = f[:, 1] if dy else 1.0 - f[:, 1]
            for dz in (0, 1):
                wz = f[:, 2] if dz else 1.0 - f[:, 2]
                out += wx * wy * wz * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm(P: np.ndarray, freq: float, octaves: int = 3, seed: int = 0, gain: float = 0.5) -> np.ndarray:
    """Fractal value noise, centred on 0 (about -0.5..0.5)."""
    v = np.zeros(len(P))
    a, norm = 1.0, 0.0
    P = P @ _skew()
    for o in range(octaves):
        v += a * (vnoise(P, freq * (2.03 ** o), seed + 17 * o) - 0.5)
        norm += a
        a *= gain
    return v / norm


_SKEW = None


def _skew() -> np.ndarray:
    """A fixed rotation off every axis: value noise's lattice lines up with x, y and z, and its
    zero-crossings read as ruled lines and square pits unless the lattice is turned."""
    global _SKEW
    if _SKEW is None:
        a, b, c = 0.61, 0.97, 0.37
        rx = np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])
        ry = np.array([[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]])
        rz = np.array([[math.cos(c), -math.sin(c), 0], [math.sin(c), math.cos(c), 0], [0, 0, 1]])
        _SKEW = rz @ ry @ rx
    return _SKEW


def ridged(P: np.ndarray, freq: float, seed: int = 0) -> np.ndarray:
    """0 along thin crooked lines, rising to 1 away from them: cracks, where it is near 0. The
    lookup is turned off the lattice and warped, so the lines wander."""
    Q = P @ _skew()
    warp = np.stack([fbm(Q, freq * 0.7, 2, seed + i * 7) for i in range(3)], axis=1) / freq * 0.6
    Q = Q + warp
    n = vnoise(Q, freq, seed) * 0.7 + vnoise(Q, freq * 2.3, seed + 5) * 0.3
    return np.abs(n - 0.5) * 2.0


# --- primitives beyond lib/sdf ---------------------------------------------------------------

def custom(fn: Callable[[np.ndarray], np.ndarray], lo, hi, k: float = 0.0, op: str = "union") -> sdf.Prim:
    return sdf.Prim(fn, np.asarray(lo, float), np.asarray(hi, float), op, k)


def worn(prim: sdf.Prim, amp: float, freq: float, seed: int = 0, octaves: int = 3,
         cracks: float = 0.0, crack_freq: float = 0.0, crack_w: float = 0.06, calm=()) -> sdf.Prim:
    """A primitive eaten by weather: its surface pitted and swollen by fractal noise of `amp`
    metres, and, with `cracks`, cut `cracks` metres deep along crooked lines. `calm` is a list
    of (centre, radius) where the weather is gentler (a hand's fingers, which full weathering
    eats through and leaves as crumbs in the air)."""
    base = prim.fn
    calm = [(np.asarray(c, float), float(r)) for c, r in calm]

    def fn(P):
        d = base(P)
        near = np.abs(d) < (amp * 2.0 + cracks + 0.5)
        if near.any():
            Q = P[near]
            e = fbm(Q, freq, octaves, seed) * amp * 2.0
            if cracks > 0.0:
                r = ridged(Q, crack_freq or freq * 0.5, seed + 91)
                e -= cracks * np.clip(1.0 - r / crack_w, 0.0, 1.0)
            for c, rad in calm:
                e *= np.clip(np.linalg.norm(Q - c, axis=1) / rad, 0.2, 1.0)
            d = d.copy()
            d[near] -= e
        return d
    pad = amp + 0.5
    return sdf.Prim(fn, prim.lo - pad, prim.hi + pad, prim.op, prim.k)


def moved(prim: sdf.Prim, R: np.ndarray, T) -> sdf.Prim:
    """`prim` turned by R (3x3) and then carried by T: evaluated by taking points back."""
    R = np.asarray(R, float)
    T = np.asarray(T, float)
    base = prim.fn

    def fn(P):
        return base((P - T) @ R)
    corners = np.array([[x, y, z] for x in (prim.lo[0], prim.hi[0]) for y in (prim.lo[1], prim.hi[1])
                        for z in (prim.lo[2], prim.hi[2])])
    moved_c = corners @ R.T + T
    return sdf.Prim(fn, moved_c.min(axis=0), moved_c.max(axis=0), prim.op, prim.k)


def rot(axis: Sequence[float], deg: float) -> np.ndarray:
    a = np.asarray(axis, float)
    a = a / np.linalg.norm(a)
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    x, y, z = a
    return np.array([[c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
                     [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
                     [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])


def robe(stations: Sequence[tuple], folds: int, fold_amp: Sequence[tuple], seed: int = 0,
         k: float = 0.0) -> sdf.Prim:
    """A robe as one body: elliptical sections (z, rx, ry, cy) interpolated up the figure, with
    folds hanging from the waist -- rounded ridges and creased valleys, their count fixed round
    the body so they gather where it narrows and fan where the hem spreads, each wandering a
    little as it falls, and deeper the lower they hang (`fold_amp`: (z, metres))."""
    st = np.array(stations, float)
    zs, rxs, rys, cys = st[:, 0], st[:, 1], st[:, 2], st[:, 3]
    fa = np.array(fold_amp, float)
    rng = np.random.default_rng(seed)
    phase = rng.uniform(0, math.tau, 3)
    # a second, uneven set of folds so no two ridges are alike
    folds2 = folds + 3

    def fn(P):
        z = np.clip(P[:, 2], zs[0], zs[-1])
        rx = np.interp(z, zs, rxs)
        ry = np.interp(z, zs, rys)
        cy = np.interp(z, zs, cys)
        x = P[:, 0]
        y = P[:, 1] - cy
        u, v = x / rx, y / ry
        rn = np.sqrt(u * u + v * v) + 1e-9
        # distance to the ellipse, near enough (exact on the axes, a little short between)
        grad = np.sqrt((u / rx) ** 2 + (v / ry) ** 2) + 1e-9
        d = (rn * rn - 1.0) / (2.0 * rn * grad)
        th = np.arctan2(v, u)
        wob = 0.35 * np.sin(P[:, 2] * 0.11 + phase[2]) + 0.2 * np.sin(P[:, 2] * 0.27 + phase[0])
        g1 = 2.0 * np.abs(np.cos(0.5 * (folds * th + phase[0] + wob))) - 1.0
        g2 = 2.0 * np.abs(np.cos(0.5 * (folds2 * th + phase[1] - wob * 1.4))) - 1.0
        g = 0.7 * g1 + 0.3 * g2
        amp = np.interp(P[:, 2], fa[:, 0], fa[:, 1])
        d = d - amp * g
        # capped top and bottom
        d = np.maximum(d, np.maximum(zs[0] - P[:, 2], P[:, 2] - zs[-1]))
        return d
    rmax = float(max(rxs.max(), rys.max()) + fa[:, 1].max() + 0.5)
    lo = np.array([-rmax, float((cys - rys).min()) - 1.0, zs[0]])
    hi = np.array([rmax, float((cys + rys).max()) + 1.0, zs[-1]])
    return sdf.Prim(fn, lo, hi, "union", k)


def slab(c, half, R=None, round_r: float = 0.3, k: float = 0.0, op: str = "union") -> sdf.Prim:
    return sdf.box(c, half, k=k, op=op, rot=R, round_r=round_r)


def jagged_cut(centre, normal, radius: float, depth: float, seed: int, bumps: int = 7) -> list:
    """A break: everything above a tilted plane goes, and the edge of the break is torn, with
    bites taken out of the rim. Returned as primitives: one intersect and a few subtractions."""
    c = np.asarray(centre, float)
    n = np.asarray(normal, float)
    n = n / np.linalg.norm(n)
    rng = np.random.default_rng(seed)

    def fn(P):
        base = (P - c) @ n
        # the break surface is rough: a few metres of lumps and a step or two
        return base + fbm(P, 0.45, 3, seed) * depth * 1.6
    prims = [custom(fn, c - 400, c + 400, op="intersect")]
    u = np.cross(n, [0.0, 0.0, 1.0] if abs(n[2]) < 0.9 else [1.0, 0.0, 0.0])
    u /= np.linalg.norm(u)
    w = np.cross(n, u)
    for i in range(bumps):
        a = rng.uniform(0, math.tau)
        p = c + (u * math.cos(a) + w * math.sin(a)) * radius * rng.uniform(0.75, 1.05) + n * rng.uniform(-0.2, 0.6) * depth
        prims.append(sdf.sphere(p, depth * rng.uniform(0.6, 1.2), k=0.3, op="subtract"))
    return prims


def local_cut(centre, normal, half_w: float, depth: float, seed: int, reach: float = 6.0) -> sdf.Prim:
    """A break confined to one member (a neck, a forearm): a subtraction of everything above a
    tilted plane within `half_w` of `centre` across it, the break surface torn by noise."""
    c = np.asarray(centre, float)
    n = np.asarray(normal, float)
    n = n / np.linalg.norm(n)
    u = np.cross(n, [0.0, 0.0, 1.0] if abs(n[2]) < 0.9 else [1.0, 0.0, 0.0])
    u /= np.linalg.norm(u)
    w = np.cross(n, u)
    R = np.stack([u, w, n], axis=1)            # local -> world columns
    half = np.array([half_w, half_w, reach])

    def fn(P):
        q = (P - c) @ R
        q[:, 2] -= reach
        q = np.abs(q) - half
        d = np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0)
        return d + fbm(P, 0.55, 3, seed) * depth * 1.8
    ext = np.abs(R) @ (half + np.array([0.0, 0.0, reach]))
    return sdf.Prim(fn, c - ext - depth * 2, c + ext + depth * 2, "subtract", 0.25)


def rubble(rng: np.random.Generator, count: int, r_in: float, r_out: float, size: tuple,
           sink: float = 0.45, avoid: Callable[[float, float], bool] | None = None, seed: int = 0,
           z_at: Callable[[float, float], float] | None = None) -> list:
    """Broken blocks round a foot: rounded, tumbled, half sunk into the ground, bigger ones
    nearer (they fell first and furthest down)."""
    out = []
    tries = 0
    while len(out) < count and tries < count * 20:
        tries += 1
        a = rng.uniform(0, math.tau)
        r = r_in + (r_out - r_in) * rng.random() ** 0.8
        x, y = math.cos(a) * r, math.sin(a) * r
        if avoid is not None and avoid(x, y):
            continue
        s = rng.uniform(size[0], size[1]) * (1.25 - 0.5 * (r - r_in) / max(r_out - r_in, 1e-3))
        half = np.array([s * rng.uniform(0.7, 1.5), s * rng.uniform(0.6, 1.1), s * rng.uniform(0.35, 0.8)])
        R = rot([rng.normal(), rng.normal(), rng.normal()], rng.uniform(0, 60)) @ rot([0, 0, 1], rng.uniform(0, 360))
        z0 = z_at(x, y) if z_at else 0.0
        cz = z0 + half[2] * (1.0 - 2.0 * sink)
        b = slab((x, y, cz), half, R, round_r=min(half) * 0.35)
        out.append(worn(b, amp=s * 0.12, freq=0.9 / max(s, 0.3), seed=seed + len(out)))
    return out


# --- meshing --------------------------------------------------------------------------------

def mesh(scene: sdf.Scene, spacing: float, smooth_iters: int = 3) -> tuple:
    """(verts (n,3), triangles (m,3)) of a scene: surface nets, lightly smoothed, split into
    triangles along the shorter diagonal."""
    V, Q = sdf.mesh_from_scene(scene, spacing, smooth_iters=smooth_iters, project=1)
    if len(Q) == 0:
        return V, np.zeros((0, 3), int)
    d02 = np.linalg.norm(V[Q[:, 0]] - V[Q[:, 2]], axis=1)
    d13 = np.linalg.norm(V[Q[:, 1]] - V[Q[:, 3]], axis=1)
    a = np.where((d02 <= d13)[:, None], Q[:, [0, 1, 2]], Q[:, [0, 1, 3]])
    b = np.where((d02 <= d13)[:, None], Q[:, [0, 2, 3]], Q[:, [1, 2, 3]])
    return V, np.concatenate([a, b], axis=0)


def keep_largest(V: np.ndarray, T: np.ndarray, min_tris: int = 40) -> tuple:
    """Drop the specks surface nets leaves where noise pinched off a crumb of stone."""
    n = len(V)
    parent = np.arange(n)

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for a, b in ((0, 1), (1, 2)):
        for i, j in zip(T[:, a], T[:, b]):
            ri, rj = find(i), find(j)
            if ri != rj:
                parent[ri] = rj
    roots = np.array([find(i) for i in range(n)])
    tri_root = roots[T[:, 0]]
    ids, counts = np.unique(tri_root, return_counts=True)
    keep = set(ids[counts >= min_tris].tolist())
    mask = np.array([r in keep for r in tri_root])
    return V, T[mask]
