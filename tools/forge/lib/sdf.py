"""Signed-distance modelling core for the character forge.

Organic bodies need *blended* unions (a shoulder flows into a torso), which a boolean
union of primitives cannot give.  So shapes are built as smooth-min SDF fields and
polygonised with naive surface nets (dual contouring's simple cousin): watertight quad
meshes, no voxel staircase, and the same field can be offset by a constant to make a
clothing shell that fits the body exactly.

Everything is numpy; no Blender, no scipy.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Callable, List, Optional, Sequence, Tuple

import numpy as np

Vec = np.ndarray


def _unit(v: np.ndarray) -> np.ndarray:
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-12 else v


# --------------------------------------------------------------------------------------
# primitives: each returns a callable P(n,3) -> d(n) plus an axis-aligned bound
# --------------------------------------------------------------------------------------

@dataclass
class Prim:
    fn: Callable[[np.ndarray], np.ndarray]
    lo: np.ndarray
    hi: np.ndarray
    op: str = "union"      # union | subtract | intersect
    k: float = 0.0         # blend radius


def sphere(c, r: float, k: float = 0.0, op: str = "union") -> Prim:
    c = np.asarray(c, float)

    def fn(P):
        return np.linalg.norm(P - c, axis=1) - r
    return Prim(fn, c - r, c + r, op, k)


def ellipsoid(c, r, k: float = 0.0, op: str = "union", rot: Optional[np.ndarray] = None) -> Prim:
    c = np.asarray(c, float)
    r = np.asarray(r, float)
    Rt = None if rot is None else np.asarray(rot, float).T

    def fn(P):
        q = P - c
        if Rt is not None:
            q = q @ Rt.T
        k0 = np.linalg.norm(q / r, axis=1)
        k1 = np.linalg.norm(q / (r * r), axis=1)
        return np.where(k0 < 1e-9, -r.min(), k0 * (k0 - 1.0) / np.maximum(k1, 1e-9))
    ext = r if rot is None else np.abs(np.asarray(rot, float)) @ r
    return Prim(fn, c - ext, c + ext, op, k)


def round_cone(a, b, ra: float, rb: float, k: float = 0.0, op: str = "union") -> Prim:
    """Capsule with different end radii (exact SDF).

    Degenerate case: when |ra - rb| >= |b - a| one end sphere contains the other and the
    closed-form below would take the square root of a negative number, so the shape is the
    containing sphere instead."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ba = b - a
    l2 = float(np.dot(ba, ba))
    rr = ra - rb
    a2 = l2 - rr * rr
    if a2 <= 1e-9:
        c, r = (a, ra) if ra >= rb else (b, rb)
        return sphere(c, r, k, op)
    il2 = 1.0 / max(l2, 1e-12)

    def fn(P):
        p = P - a
        y = p @ ba
        z = y - l2
        x2 = np.sum((p * l2 - np.outer(y, ba)) ** 2, axis=1)
        y2 = y * y * l2
        z2 = z * z * l2
        d = np.where(np.sign(z) * a2 * z2 > 0,
                     np.sqrt(np.maximum(x2 + z2, 0.0)) * il2 - rb,
                     np.where(np.sign(y) * a2 * y2 < 0,
                              np.sqrt(np.maximum(x2 + y2, 0.0)) * il2 - ra,
                              (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - ra))
        return d
    lo = np.minimum(a - ra, b - rb)
    hi = np.maximum(a + ra, b + rb)
    return Prim(fn, lo, hi, op, k)


def capsule(a, b, r: float, k: float = 0.0, op: str = "union") -> Prim:
    return round_cone(a, b, r, r, k, op)


def elliptic_cone(a, b, ru1: float, rv1: float, ru2: float, rv2: float, u: Vec, k: float = 0.0,
                  op: str = "union", squash_v_neg: float = 0.0) -> Prim:
    """Round cone with an elliptical cross-section: `u` is the in-plane axis whose radii are
    ru1/ru2 (at a/b), the perpendicular gets rv1/rv2.  Implemented by an anisotropic scale
    around the segment axis, which keeps the zero set exact.  `squash_v_neg` flattens the -v
    side (soles, shield faces)."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    w = _unit(b - a)
    uu = np.asarray(u, float)
    uu = _unit(uu - np.dot(uu, w) * w)
    if np.linalg.norm(uu) < 1e-6:
        uu = _unit(np.cross(w, np.array([0.0, 0.0, 1.0])))
    vv = np.cross(w, uu)
    su = 0.5 * (ru1 + ru2)
    sv = 0.5 * (rv1 + rv2)
    g = math.sqrt(max(su * sv, 1e-12))
    ku = su / g
    kv = sv / g
    M = np.stack([uu / ku, vv / kv, w], axis=0)       # world -> scaled local (rows)
    la = np.zeros(3)
    lb = np.array([0.0, 0.0, float(np.linalg.norm(b - a))])
    r1 = math.sqrt(max((ru1 / ku) * (rv1 / kv), 1e-12))
    r2 = math.sqrt(max((ru2 / ku) * (rv2 / kv), 1e-12))
    base = round_cone(la, lb, r1, r2)
    scale = min(ku, kv)

    def fn(P):
        q = (P - a) @ M.T
        if squash_v_neg > 0:
            neg = q[:, 1] < 0
            q = q.copy()
            q[neg, 1] /= max(1.0 - squash_v_neg, 0.05)
        return base.fn(q) * scale
    rmax = max(ru1, rv1, ru2, rv2)
    lo = np.minimum(a, b) - rmax
    hi = np.maximum(a, b) + rmax
    return Prim(fn, lo, hi, op, k)


def _catmull_rom(pts: np.ndarray, t: np.ndarray) -> np.ndarray:
    """Centripetal-ish Catmull-Rom through `pts` (n, d) sampled at parameter t in [0, n-1]."""
    n = len(pts)
    i = np.clip(np.floor(t).astype(int), 0, n - 2)
    f = (t - i)[:, None]
    p0 = pts[np.clip(i - 1, 0, n - 1)]
    p1 = pts[i]
    p2 = pts[np.clip(i + 1, 0, n - 1)]
    p3 = pts[np.clip(i + 2, 0, n - 1)]
    f2 = f * f
    f3 = f2 * f
    return 0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f2 + (-p0 + 3 * p1 - 3 * p2 + p3) * f3)


def sweep(stations: Sequence[Tuple[Vec, float, float]], u: Vec, k: float = 0.0, op: str = "union",
          squash_v_neg: float = 0.0, axis: Optional[Vec] = None, density: int = 5,
          max_spheres: int = 220, smooth_profile: bool = True) -> Prim:
    """A swept volume through (centre, ru, rv) stations: the envelope of a dense chain of
    spheres in one anisotropically scaled space.

    Spheres (rather than round cones) because a cone between two stations is undefined when
    the radius changes faster than the distance — which happens at every dome, like the top
    of a skull — and produces flat disc artefacts.  A chain dense enough that the spacing is
    a small fraction of the radius is smooth to well under a voxel, and never degenerates.
    The profile runs through the stations as a Catmull-Rom spline, so there are no creases
    at the stations either."""
    cs = np.array([np.asarray(c, float) for c, _, _ in stations])
    rus = np.array([float(ru) for _, ru, _ in stations])
    rvs = np.array([float(rv) for _, _, rv in stations])
    w = _unit(np.asarray(axis, float) if axis is not None else (cs[-1] - cs[0]))
    uu = np.asarray(u, float)
    uu = _unit(uu - np.dot(uu, w) * w)
    if np.linalg.norm(uu) < 1e-6:
        uu = _unit(np.cross(w, np.array([0.0, 0.0, 1.0]) if abs(w[2]) < 0.9 else np.array([1.0, 0.0, 0.0])))
    vv = np.cross(w, uu)
    su, sv = float(rus.mean()), float(rvs.mean())
    g = math.sqrt(max(su * sv, 1e-12))
    ku, kv = su / g, sv / g
    M = np.stack([uu / ku, vv / kv, w], axis=0)
    origin = cs[0]
    pts = (cs - origin) @ M.T
    radii = np.sqrt(np.maximum((rus / ku) * (rvs / kv), 1e-12))
    # resample
    seg_len = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    total = float(seg_len.sum())
    step = max(float(radii.min()) / max(density, 1), total / max_spheres, 1e-4)
    n = int(np.clip(math.ceil(total / step), len(pts), max_spheres))
    tt = np.linspace(0.0, len(pts) - 1.0, n)
    if smooth_profile and len(pts) > 2:
        C = _catmull_rom(pts, tt)
        R = _catmull_rom(radii[:, None], tt)[:, 0]
    else:
        C = np.stack([np.interp(tt, np.arange(len(pts)), pts[:, i]) for i in range(3)], axis=1)
        R = np.interp(tt, np.arange(len(pts)), radii)
    R = np.maximum(R, 1e-4)
    scale = min(ku, kv)

    def fn(P):
        q = (P - origin) @ M.T
        if squash_v_neg > 0:
            neg = q[:, 1] < 0
            q = q.copy()
            q[neg, 1] /= max(1.0 - squash_v_neg, 0.05)
        d = np.full(len(q), 1e6)
        for i in range(len(C)):
            np.minimum(d, np.linalg.norm(q - C[i], axis=1) - R[i], out=d)
        return d * scale
    rmax = float(max(rus.max(), rvs.max()))
    lo = cs.min(axis=0) - rmax
    hi = cs.max(axis=0) + rmax
    return Prim(fn, lo, hi, op, k)


def tube_path(points: Sequence[Vec], radii, k: float = 0.0, op: str = "union", density: int = 5,
              max_spheres: int = 260, closed: bool = False, smooth_profile: bool = True) -> Prim:
    """A round tube along an arbitrary 3D path (isotropic radii), as a dense sphere chain.

    Used for anything that curves through space: the jaw horseshoe, belts and straps, hair
    locks and braids, horns, halos.  `radii` is a scalar or one value per point."""
    P = np.array([np.asarray(p, float) for p in points])
    R = np.full(len(P), float(radii)) if np.isscalar(radii) else np.asarray(radii, float)
    if closed:
        P = np.concatenate([P, P[:1]], axis=0)
        R = np.concatenate([R, R[:1]], axis=0)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    total = float(seg.sum())
    step = max(float(R.min()) / max(density, 1), total / max_spheres, 1e-4)
    n = int(np.clip(math.ceil(total / step), len(P), max_spheres))
    tt = np.linspace(0.0, len(P) - 1.0, n)
    if smooth_profile and len(P) > 2:
        C = _catmull_rom(P, tt)
        RR = np.maximum(_catmull_rom(R[:, None], tt)[:, 0], 1e-4)
    else:
        C = np.stack([np.interp(tt, np.arange(len(P)), P[:, i]) for i in range(3)], axis=1)
        RR = np.interp(tt, np.arange(len(P)), R)

    def fn(Q):
        d = np.full(len(Q), 1e6)
        for i in range(len(C)):
            np.minimum(d, np.linalg.norm(Q - C[i], axis=1) - RR[i], out=d)
        return d
    rmax = float(R.max())
    return Prim(fn, P.min(axis=0) - rmax, P.max(axis=0) + rmax, op, k)


def loft(stations: Sequence[Tuple[Vec, float, float]], u: Vec, k: float = 0.0, op: str = "union",
         squash_v_neg: float = 0.0, internal_k: float = 0.0, axis: Optional[Vec] = None) -> Prim:
    """Swept solid through (centre, ru, rv) stations.  Alias of `sweep`; `internal_k` is
    accepted for call-site symmetry and ignored (a sphere sweep has no internal seams)."""
    return sweep(stations, u, k=k, op=op, squash_v_neg=squash_v_neg, axis=axis)


def group(prims: Sequence[Prim], k: float = 0.0, op: str = "union", internal_k: float = 0.0) -> Prim:
    """Combine primitives into one, so the group blends with the scene as a single shape."""
    prims = list(prims)

    def fn(P):
        d = prims[0].fn(P)
        for p in prims[1:]:
            if p.op == "subtract":
                d = smax(d, -p.fn(P), p.k or internal_k)
            elif p.op == "intersect":
                d = smax(d, p.fn(P), p.k or internal_k)
            else:
                d = smin(d, p.fn(P), p.k or internal_k)
        return d
    lo = np.min(np.stack([p.lo for p in prims if p.op == "union"]), axis=0)
    hi = np.max(np.stack([p.hi for p in prims if p.op == "union"]), axis=0)
    return Prim(fn, lo, hi, op, k)


def chain(points: Sequence[Vec], radii: Sequence[float], k: float = 0.0, op: str = "union") -> Prim:
    """A polyline of round cones combined with a plain min (one limb, no station rings)."""
    segs = [round_cone(points[i], points[i + 1], radii[i], radii[i + 1]) for i in range(len(points) - 1)]
    return group(segs, k, op, internal_k=0.0)


def plane(point, normal, k: float = 0.0, op: str = "intersect") -> Prim:
    """Half-space: inside is where (p - point)·normal <= 0."""
    point = np.asarray(point, float)
    n = _unit(np.asarray(normal, float))

    def fn(P):
        return (P - point) @ n
    big = np.array([1e3, 1e3, 1e3])
    return Prim(fn, -big, big, op, k)


def box(c, half, k: float = 0.0, op: str = "union", rot: Optional[np.ndarray] = None, round_r: float = 0.0) -> Prim:
    c = np.asarray(c, float)
    h = np.asarray(half, float) - round_r
    Rt = None if rot is None else np.asarray(rot, float).T

    def fn(P):
        q = P - c
        if Rt is not None:
            q = q @ Rt.T
        q = np.abs(q) - h
        outside = np.linalg.norm(np.maximum(q, 0.0), axis=1)
        inside = np.minimum(np.max(q, axis=1), 0.0)
        return outside + inside - round_r
    ext = (np.asarray(half, float)) if rot is None else np.abs(np.asarray(rot, float)) @ np.asarray(half, float)
    return Prim(fn, c - ext, c + ext, op, k)


def torus(c, R: float, r: float, axis: Vec = np.array([0.0, 0.0, 1.0]), k: float = 0.0, op: str = "union") -> Prim:
    c = np.asarray(c, float)
    w = _unit(np.asarray(axis, float))
    uu = _unit(np.cross(w, np.array([0.0, 0.0, 1.0]) if abs(w[2]) < 0.9 else np.array([1.0, 0.0, 0.0])))
    vv = np.cross(w, uu)
    M = np.stack([uu, vv, w], axis=0)

    def fn(P):
        q = (P - c) @ M.T
        rad = np.hypot(q[:, 0], q[:, 1]) - R
        return np.hypot(rad, q[:, 2]) - r
    ext = np.array([R + r, R + r, R + r])
    return Prim(fn, c - ext, c + ext, op, k)


# --------------------------------------------------------------------------------------
# scene: smooth combination on a grid
# --------------------------------------------------------------------------------------

def smin(d1: np.ndarray, d2: np.ndarray, k: float) -> np.ndarray:
    if k <= 1e-9:
        return np.minimum(d1, d2)
    h = np.clip(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0)
    return d2 * (1 - h) + d1 * h - k * h * (1 - h)


def smax(d1: np.ndarray, d2: np.ndarray, k: float) -> np.ndarray:
    if k <= 1e-9:
        return np.maximum(d1, d2)
    h = np.clip(0.5 - 0.5 * (d2 - d1) / k, 0.0, 1.0)
    return d2 * (1 - h) + d1 * h + k * h * (1 - h)


# Most grid points one primitive is evaluated at in one call (see Scene.grid).
GRID_CHUNK = 600_000


class Scene:
    """An ordered list of primitives combined with smooth min/max."""

    def __init__(self):
        self.prims: List[Prim] = []

    def add(self, p) -> "Scene":
        if isinstance(p, Prim):
            self.prims.append(p)
        else:
            for q in p:
                self.prims.append(q)
        return self

    def union(self, p, k: float = 0.0) -> "Scene":
        for q in ([p] if isinstance(p, Prim) else list(p)):
            q.op = "union"
            q.k = k or q.k
            self.prims.append(q)
        return self

    def subtract(self, p, k: float = 0.0) -> "Scene":
        for q in ([p] if isinstance(p, Prim) else list(p)):
            q.op = "subtract"
            q.k = k or q.k
            self.prims.append(q)
        return self

    def intersect(self, p, k: float = 0.0) -> "Scene":
        for q in ([p] if isinstance(p, Prim) else list(p)):
            q.op = "intersect"
            q.k = k or q.k
            self.prims.append(q)
        return self

    def bounds(self, margin: float = 0.02) -> Tuple[np.ndarray, np.ndarray]:
        lo = np.array([1e9, 1e9, 1e9])
        hi = -lo
        for p in self.prims:
            if p.op != "union":
                continue
            lo = np.minimum(lo, p.lo - p.k)
            hi = np.maximum(hi, p.hi + p.k)
        return lo - margin, hi + margin

    def near(self, margin: float = 0.08) -> "_NearScene":
        """This scene, read only near its surface (see `_NearScene`)."""
        return _NearScene(self, margin)

    def eval(self, P: np.ndarray) -> np.ndarray:
        """Evaluate the field at arbitrary points (n,3)."""
        d = np.full(len(P), 1e6)
        for p in self.prims:
            dp = p.fn(P)
            if p.op == "union":
                d = smin(d, dp, p.k)
            elif p.op == "subtract":
                d = smax(d, -dp, p.k)
            else:
                d = smax(d, dp, p.k)
        return d

    def grid(self, spacing: float, margin: float = 0.03,
             box: Optional[Tuple[np.ndarray, np.ndarray]] = None,
             reach: float = 0.0) -> Tuple[np.ndarray, np.ndarray, float]:
        """Sample the field on a regular grid.  Returns (field (nx,ny,nz), origin, spacing).
        Primitives are only evaluated inside their own (expanded) bounds, so cost scales with
        the shape, not the bounding box. `box` (lo, hi) samples that box only: part of a shape,
        finely (a face's detail, where the whole head at that spacing is too many points).

        So a point a few centimetres off the surface, past a primitive's bounds, reads the
        distance to whatever else is near, not to that primitive: under the arm, 3 cm off the
        torso, the body read 4.5 cm (the arm's), and the woman's narrower torso 13.6. `reach`
        evaluates each primitive that much further out, for a field that must be a distance out
        to it (a garment's fit, body.fit_positions)."""
        if box is not None:
            lo, hi = np.asarray(box[0], float), np.asarray(box[1], float)
        else:
            lo, hi = self.bounds(margin)
        n = np.maximum(np.ceil((hi - lo) / spacing).astype(int) + 1, 2)
        origin = lo
        axes = [origin[i] + np.arange(n[i]) * spacing for i in range(3)]
        F = np.full(tuple(n), 1e6)
        for p in self.prims:
            pad = p.k + 2 * spacing + reach
            if p.op in ("union", "subtract"):
                # A union only adds material inside its own bounds; a subtraction only
                # removes material inside its own bounds (outside, -d is very negative and
                # the smooth max returns the field unchanged).  Either way there is no need
                # to evaluate it over the whole grid — which is what made a cloak with nine
                # fold cuts take three minutes.
                i0 = np.maximum(np.floor((p.lo - pad - origin) / spacing).astype(int), 0)
                i1 = np.minimum(np.ceil((p.hi + pad - origin) / spacing).astype(int) + 1, n)
                if np.any(i1 <= i0):
                    continue
            else:
                i0 = np.zeros(3, int)
                i1 = n
            # In slabs of at most GRID_CHUNK points: a torso-sized shell at 3 mm is 8 million
            # points, and its region functions and a sampled field's eight gathered copies of
            # them were gigabytes at once -- the brigandine was killed for memory mid-build.
            # Every field here is pointwise, so the slabs give the same grid.
            plane = max(int(i1[1] - i0[1]) * int(i1[2] - i0[2]), 1)
            per = max(1, GRID_CHUNK // plane)
            for xa in range(int(i0[0]), int(i1[0]), per):
                xb = min(xa + per, int(i1[0]))
                sl = (slice(xa, xb), slice(int(i0[1]), int(i1[1])), slice(int(i0[2]), int(i1[2])))
                gx, gy, gz = np.meshgrid(axes[0][sl[0]], axes[1][sl[1]], axes[2][sl[2]], indexing="ij")
                P = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], axis=1)
                dp = p.fn(P).reshape(gx.shape)
                if p.op == "union":
                    F[sl] = smin(F[sl], dp, p.k)
                elif p.op == "subtract":
                    F[sl] = smax(F[sl], -dp, p.k)
                else:
                    F[sl] = smax(F[sl], dp, p.k)
        return F, origin, spacing


class _NearScene:
    """A scene's field where it matters to something probing near the surface: each union or
    subtraction is evaluated only at the points within `margin` (and its blend) of its bounds.
    Closer than `margin` to the surface the value is exact; further out it is at least `margin`,
    which is all an occlusion probe of a smaller radius asks of it.

    `Scene.eval` evaluates every primitive at every point. Painting the body, the occlusion
    probe put five points above each of a million texels through the whole body, and every one
    of them through each sphere of ten fingers: the rig's bake went from twenty minutes to
    over an hour when the hands got fingers."""

    def __init__(self, scene: "Scene", margin: float):
        self.scene = scene
        self.margin = margin

    def eval(self, P: np.ndarray) -> np.ndarray:
        d = np.full(len(P), 1e6)
        for p in self.scene.prims:
            if p.op in ("union", "subtract"):
                pad = self.margin + p.k
                idx = np.nonzero(np.all((P >= p.lo - pad) & (P <= p.hi + pad), axis=1))[0]
                if len(idx) == 0:
                    continue
                dp = p.fn(P[idx])
                d[idx] = smin(d[idx], dp, p.k) if p.op == "union" else smax(d[idx], -dp, p.k)
            else:
                d = smax(d, p.fn(P), p.k)
        return d


class SampledField:
    """A scene's distance field cached on a grid and read back by trilinear interpolation.

    Clothing is built by offsetting the body's field, and the body is forty-odd primitives
    with hundreds of spheres between them; evaluating that per garment voxel is hopeless.
    Sampling it once and interpolating is both fast and accurate enough — the interpolation
    error of a distance field is second order in the spacing, and garment shells sit
    millimetres off a surface that was itself meshed at this resolution."""

    def __init__(self, scene: "Scene", spacing: float = 0.005, margin: float = 0.06, reach: float = 0.0):
        self.F, self.origin, self.spacing = scene.grid(spacing, margin, reach=reach)
        self.shape = np.array(self.F.shape)
        self.far = float(np.max(self.F))

    @classmethod
    def from_grid(cls, F: np.ndarray, origin: np.ndarray, spacing: float) -> "SampledField":
        """Wrap a grid that has already been sampled (by the mesher, say) instead of sampling
        the scene a second time."""
        f = cls.__new__(cls)
        f.F, f.origin, f.spacing = F, np.asarray(origin, float), float(spacing)
        f.shape = np.array(F.shape)
        f.far = float(np.max(F))
        return f

    def eval(self, P: np.ndarray) -> np.ndarray:
        q = (np.asarray(P, float) - self.origin) / self.spacing
        i0 = np.floor(q).astype(np.int64)
        f = q - i0
        out_of = np.any((i0 < 0) | (i0 >= self.shape - 1), axis=1)
        i0 = np.clip(i0, 0, self.shape - 2)
        F = self.F
        c = {}
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    c[(dx, dy, dz)] = F[i0[:, 0] + dx, i0[:, 1] + dy, i0[:, 2] + dz]
        x00 = c[(0, 0, 0)] + (c[(1, 0, 0)] - c[(0, 0, 0)]) * f[:, 0]
        x10 = c[(0, 1, 0)] + (c[(1, 1, 0)] - c[(0, 1, 0)]) * f[:, 0]
        x01 = c[(0, 0, 1)] + (c[(1, 0, 1)] - c[(0, 0, 1)]) * f[:, 0]
        x11 = c[(0, 1, 1)] + (c[(1, 1, 1)] - c[(0, 1, 1)]) * f[:, 0]
        y0 = x00 + (x10 - x00) * f[:, 1]
        y1 = x01 + (x11 - x01) * f[:, 1]
        d = y0 + (y1 - y0) * f[:, 2]
        # outside the cached box, fall back to the distance to the box itself
        if out_of.any():
            lo = self.origin
            hi = self.origin + (self.shape - 1) * self.spacing
            p = np.asarray(P, float)[out_of]
            outside = np.linalg.norm(np.maximum(np.maximum(lo - p, p - hi), 0.0), axis=1)
            d[out_of] = np.maximum(d[out_of], outside)
        return d

    def gradient(self, P: np.ndarray, eps: Optional[float] = None) -> np.ndarray:
        e = eps if eps is not None else self.spacing
        g = np.empty_like(np.asarray(P, float))
        for a in range(3):
            o = np.zeros(3)
            o[a] = e
            g[:, a] = (self.eval(P + o) - self.eval(P - o)) / (2 * e)
        return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)

    def bounds(self, margin: float = 0.0) -> Tuple[np.ndarray, np.ndarray]:
        hi = self.origin + (self.shape - 1) * self.spacing
        return self.origin - margin, hi + margin


# --------------------------------------------------------------------------------------
# surface nets
# --------------------------------------------------------------------------------------

_CORNERS = np.array([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0), (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], dtype=float)
_EDGES = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]


def surface_nets(F: np.ndarray, origin: np.ndarray, spacing: float, iso: float = 0.0) -> Tuple[np.ndarray, np.ndarray]:
    """Polygonise a scalar field (negative = inside).  Returns (verts (n,3), quads (m,4))."""
    G = F - iso
    nx, ny, nz = G.shape
    c = np.empty((8, nx - 1, ny - 1, nz - 1))
    for i, (dx, dy, dz) in enumerate(_CORNERS.astype(int)):
        c[i] = G[dx:dx + nx - 1, dy:dy + ny - 1, dz:dz + nz - 1]
    inside = c <= 0
    active = inside.any(axis=0) & (~inside).any(axis=0)
    acc = np.zeros((3,) + active.shape)
    cnt = np.zeros(active.shape)
    for a, b in _EDGES:
        va, vb = c[a], c[b]
        cross = (va <= 0) != (vb <= 0)
        with np.errstate(divide="ignore", invalid="ignore"):
            t = np.where(cross, va / np.where(np.abs(va - vb) < 1e-12, 1e-12, va - vb), 0.0)
        pa, pb = _CORNERS[a], _CORNERS[b]
        for d in range(3):
            acc[d] += np.where(cross, pa[d] + (pb[d] - pa[d]) * t, 0.0)
        cnt += cross
    pos = acc / np.maximum(cnt, 1.0)
    idx = -np.ones(active.shape, dtype=np.int64)
    cells = np.argwhere(active)
    idx[active] = np.arange(len(cells))
    offs = np.stack([pos[d][active] for d in range(3)], axis=1)
    verts = (cells + offs) * spacing + origin

    quads: List[np.ndarray] = []
    sgn = G <= 0
    # For each grid edge with a sign change, the four cells around it form one quad.
    # a1, a2 are the cyclic successors of `axis` so that e[a1] x e[a2] = e[axis]; then the
    # cell offsets below wind counter-clockwise seen from +axis, i.e. the face normal is
    # +axis, which is correct when the low end of the edge is inside.
    for axis in range(3):
        a1, a2 = (axis + 1) % 3, (axis + 2) % 3
        sl0 = [slice(None)] * 3
        sl1 = [slice(None)] * 3
        sl0[axis] = slice(0, G.shape[axis] - 1)
        sl1[axis] = slice(1, G.shape[axis])
        for a in (a1, a2):
            sl0[a] = slice(1, G.shape[a] - 1)
            sl1[a] = slice(1, G.shape[a] - 1)
        s0 = sgn[tuple(sl0)]
        s1 = sgn[tuple(sl1)]
        cross = s0 != s1
        if not cross.any():
            continue
        pts = np.argwhere(cross)
        gi = np.zeros((len(pts), 3), dtype=np.int64)
        gi[:, axis] = pts[:, axis]
        gi[:, a1] = pts[:, a1] + 1
        gi[:, a2] = pts[:, a2] + 1
        quad = np.empty((len(pts), 4), dtype=np.int64)
        combos = [(-1, -1), (0, -1), (0, 0), (-1, 0)]
        ok = np.ones(len(pts), dtype=bool)
        for qi, (d1, d2) in enumerate(combos):
            ci = gi.copy()
            ci[:, a1] += d1
            ci[:, a2] += d2
            valid = np.ones(len(pts), dtype=bool)
            for d in range(3):
                valid &= (ci[:, d] >= 0) & (ci[:, d] < idx.shape[d])
            v = np.where(valid, idx[np.clip(ci[:, 0], 0, idx.shape[0] - 1),
                                    np.clip(ci[:, 1], 0, idx.shape[1] - 1),
                                    np.clip(ci[:, 2], 0, idx.shape[2] - 1)], -1)
            quad[:, qi] = v
            ok &= v >= 0
        quad = quad[ok]
        inside_low = s0[cross][ok]
        rev = quad[:, ::-1]
        sel = np.where(inside_low[:, None], quad, rev)
        quads.append(sel)
    Q = np.concatenate(quads, axis=0) if quads else np.zeros((0, 4), dtype=np.int64)
    return verts, Q


# --------------------------------------------------------------------------------------
# mesh post-processing
# --------------------------------------------------------------------------------------

def quad_edges(quads: np.ndarray) -> np.ndarray:
    e = np.concatenate([quads[:, [0, 1]], quads[:, [1, 2]], quads[:, [2, 3]], quads[:, [3, 0]]], axis=0)
    return e


def taubin_smooth(verts: np.ndarray, quads: np.ndarray, iters: int = 8, lam: float = 0.55, mu: float = -0.58,
                  weight: Optional[np.ndarray] = None) -> np.ndarray:
    """Volume-preserving smoothing (Laplacian shrink + inflate)."""
    n = len(verts)
    e = quad_edges(quads)
    V = verts.copy()
    cnt = np.zeros(n)
    np.add.at(cnt, e[:, 0], 1)
    np.add.at(cnt, e[:, 1], 1)
    cnt = np.maximum(cnt, 1)
    for i in range(iters):
        f = lam if i % 2 == 0 else mu
        acc = np.zeros_like(V)
        np.add.at(acc, e[:, 0], V[e[:, 1]])
        np.add.at(acc, e[:, 1], V[e[:, 0]])
        delta = acc / cnt[:, None] - V
        if weight is not None:
            delta = delta * weight[:, None]
        V = V + f * delta
    return V


def vertex_normals(verts: np.ndarray, quads: np.ndarray) -> np.ndarray:
    N = np.zeros_like(verts)
    for tri in ((0, 1, 2), (0, 2, 3)):
        a, b, c = quads[:, tri[0]], quads[:, tri[1]], quads[:, tri[2]]
        fn = np.cross(verts[b] - verts[a], verts[c] - verts[a])
        for i in (a, b, c):
            np.add.at(N, i, fn)
    ln = np.linalg.norm(N, axis=1, keepdims=True)
    return N / np.maximum(ln, 1e-12)


def project_to_field(verts: np.ndarray, scene: Scene, iters: int = 2, step: float = 0.7,
                     iso: float = 0.0, eps: float = 1e-3, max_step: float = 0.01) -> np.ndarray:
    """Push vertices back onto the iso-surface (recovers detail that smoothing rounded off).

    The move is clamped to `max_step`.  A field built from a region mask has flat plateaus
    where the gradient is nearly zero while the value is not; without a clamp, dividing by
    that gradient throws vertices thousands of metres away — which is exactly how a hairstyle
    ended up with a spike reaching 1.8 km into the sky."""
    V = verts.copy()
    for _ in range(iters):
        d = scene.eval(V) - iso
        g = np.empty_like(V)
        for a in range(3):
            o = np.zeros(3)
            o[a] = eps
            g[:, a] = (scene.eval(V + o) - scene.eval(V - o)) / (2 * eps)
        gl = np.linalg.norm(g, axis=1, keepdims=True)
        delta = -step * (d[:, None] * g / np.maximum(gl, 1e-4))
        n = np.linalg.norm(delta, axis=1, keepdims=True)
        delta = np.where(n > max_step, delta * (max_step / np.maximum(n, 1e-12)), delta)
        delta[~np.isfinite(delta)] = 0.0
        # a vertex sitting in a flat plateau has nothing to project onto: leave it alone
        delta[(gl < 1e-3).ravel()] = 0.0
        V = V + delta
    return V


def mesh_from_scene(scene: Scene, spacing: float, smooth_iters: int = 6, project: int = 1,
                    iso: float = 0.0, grid_out: Optional[list] = None) -> Tuple[np.ndarray, np.ndarray]:
    """Surface-nets mesh of a scene. Pass a list as `grid_out` to be handed the sampled grid
    (F, origin, spacing) as well, so a painter can read the same field without resampling it."""
    F, origin, sp = scene.grid(spacing)
    if grid_out is not None:
        grid_out[:] = [F, origin, sp]
    verts, quads = surface_nets(F, origin, sp, iso)
    if len(verts) == 0:
        return verts, quads
    if smooth_iters:
        verts = taubin_smooth(verts, quads, iters=smooth_iters)
    if project:
        verts = project_to_field(verts, scene, iters=project, iso=iso, max_step=1.2 * spacing)
        verts = taubin_smooth(verts, quads, iters=2)
    bad = ~np.isfinite(verts).all(axis=1)
    if bad.any():
        verts[bad] = 0.0
    return verts, quads


def region_mask_faces(quads: np.ndarray, vmask: np.ndarray, min_verts: int = 3) -> np.ndarray:
    """Quads with at least `min_verts` corners in the mask."""
    return quads[vmask[quads].sum(axis=1) >= min_verts]


def submesh(verts: np.ndarray, faces: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Compact a face selection into its own mesh; returns (verts, faces, source_indices)."""
    used = np.unique(faces)
    remap = -np.ones(len(verts), dtype=np.int64)
    remap[used] = np.arange(len(used))
    return verts[used], remap[faces], used


def shell(verts: np.ndarray, faces: np.ndarray, normals: np.ndarray, outer: np.ndarray,
          inner: float = 0.004) -> Tuple[np.ndarray, List[List[int]]]:
    """Give a face patch thickness: outer surface offset by `outer` per vertex, an inner
    surface offset inward, and a rim joining the boundary."""
    n = len(verts)
    outer_v = verts + normals * np.asarray(outer)[:, None]
    inner_v = verts - normals * inner
    faces_out = [[int(i) for i in f] for f in faces]
    faces_in = [[int(i) + n for i in f[::-1]] for f in faces]
    edge_count = {}
    for f in faces:
        m = len(f)
        for i in range(m):
            a, b = int(f[i]), int(f[(i + 1) % m])
            key = (min(a, b), max(a, b))
            edge_count[key] = edge_count.get(key, 0) + 1
    rim = []
    for f in faces:
        m = len(f)
        for i in range(m):
            a, b = int(f[i]), int(f[(i + 1) % m])
            if edge_count[(min(a, b), max(a, b))] == 1:
                rim.append([a, b, b + n, a + n])
    return np.concatenate([outer_v, inner_v], axis=0), faces_out + faces_in + rim
