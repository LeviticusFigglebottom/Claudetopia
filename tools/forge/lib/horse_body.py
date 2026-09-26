"""The horse's body and its tack, as signed-distance scenes on WM_Quadruped_v1 (pure numpy).

Everything is placed from the skeleton's joints, so a different set of proportions gives a
different animal from the same code: the barrel hangs from the spine, the neck runs along the
neck bones, each leg is modelled joint to joint. The shapes are a cob's, a stocky draught-riding
horse of the Vale: a deep barrel, a round croup, a thick crested neck with a hogged mane, short
strong cannons and feathered fetlocks.

`horse_scene` is the coat: the body with its tail, the mane's ridge and the feather, one closed
surface. `tack_scenes` is what the Wardens put on it -- the saddle, its cloth, the girth and the
breastplate, the stirrups, the bridle and the reins -- each a thin shell made from the body's own
field, so it sits on the horse and follows it. `regions` names what a texel is (coat, points,
hoof, mane...), which the painter reads.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional, Tuple

import numpy as np

from . import sdf
from .quadruped import QuadSkeleton, DEFAULT_WITHERS

X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])


@dataclass
class HorseStyle:
    """How this animal is built, beyond its skeleton."""
    girth: float = 1.0          # the barrel's width and depth
    croup: float = 1.0          # the quarters' muscle
    crest: float = 1.0          # the neck's crest (a stallion's or a cob's is heavy)
    feather: float = 1.0        # the hair at the fetlocks (0 for a deer or a fine horse)
    mane: str = "hogged"        # hogged (clipped to a ridge) | none
    tail: float = 1.0           # the tail's hair: its length and fullness (0: a deer's scut)
    hoof: float = 1.0           # the hooves' size
    head: str = "horse"         # horse | none (a caller draws its own: deer_body)
    cloven: bool = False        # a split hoof (a deer's, a goat's)

    def to_dict(self) -> dict:
        return asdict(self)


def _s(skel: QuadSkeleton) -> float:
    return skel.props.withers / DEFAULT_WITHERS


def _mirror(p: np.ndarray) -> np.ndarray:
    return np.array([-p[0], p[1], p[2]])


def _outline(pts: np.ndarray, n: int = 72) -> np.ndarray:
    """A closed Catmull-Rom curve through the 2D points `pts`, resampled to `n` points."""
    P = np.asarray(pts, float)
    m = len(P)
    ext = np.concatenate([P[-1:], P, P[:2]], axis=0)
    tt = np.linspace(0.0, m, n, endpoint=False)
    i = np.floor(tt).astype(int)
    f = (tt - i)[:, None]
    p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
    f2, f3 = f * f, f * f * f
    return 0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f2 + (-p0 + 3 * p1 - 3 * p2 + p3) * f3)


def _poly_sdf(Q: np.ndarray, C: np.ndarray) -> np.ndarray:
    """Signed distance from 2D points Q (n,2) to the closed polygon C (m,2), negative inside."""
    d = np.full(len(Q), 1e9)
    inside = np.zeros(len(Q), bool)
    m = len(C)
    for i in range(m):
        a, b = C[i], C[(i + 1) % m]
        ab = b - a
        L2 = float(ab @ ab)
        if L2 < 1e-14:
            continue
        u = np.clip(((Q - a) @ ab) / L2, 0.0, 1.0)
        np.minimum(d, np.linalg.norm(Q - (a + u[:, None] * ab), axis=1), out=d)
        # crossing number along +y
        c1 = (a[1] > Q[:, 1]) != (b[1] > Q[:, 1])
        xint = a[0] + (Q[:, 1] - a[1]) * (ab[0] / (ab[1] if abs(ab[1]) > 1e-14 else 1e-14))
        inside ^= c1 & (Q[:, 0] < xint)
    return np.where(inside, -d, d)


def pillow(outline, sx: float, xc, thick, depth: float) -> sdf.Prim:
    """A muscle mass drawn as its side-view outline and given body: the outline (y, z) pairs,
    standing in the plane x = sx*xc(z) and swelling to a half thickness thick(z) a `depth` in
    from its edge, with a round rim. `xc` and `thick` are
    [(z, value)] tables. This is what gives a crisp shoulder, a quarter with an edge, a stifle
    you can see: the silhouette is drawn, not left to where blobs happen to meet."""
    C = _outline(np.asarray(outline, float))
    zc = np.array([z for z, _ in xc])
    vc = np.array([v for _, v in xc])
    zt = np.array([z for z, _ in thick])
    vt = np.array([v for _, v in thick])
    oc, ot = np.argsort(zc), np.argsort(zt)
    D = depth

    def fn(P):
        d2 = _poly_sdf(P[:, 1:3], C)
        u = np.clip(-d2 / D, 0.0, 1.0)
        h = np.interp(P[:, 2], zt[ot], vt[ot]) * np.sqrt(np.maximum(1.0 - (1.0 - u) ** 2, 0.0))
        x0 = sx * np.interp(P[:, 2], zc[oc], vc[oc])
        dx = np.abs(P[:, 0] - x0) - h
        # outside the outline: the distance to the rim; inside: how far through the side
        return np.where(d2 > 0, np.sqrt(d2 * d2 + np.maximum(dx, 0.0) ** 2), np.maximum(d2, dx))
    lo2, hi2 = C.min(axis=0), C.max(axis=0)
    xm = float(np.max(np.abs(vc)) + np.max(vt))
    xn = float(np.min(np.abs(vc)) - np.max(vt))
    lo = np.array([min(sx * xm, sx * xn), lo2[0], lo2[1]])
    hi = np.array([max(sx * xm, sx * xn), hi2[0], hi2[1]])
    return sdf.Prim(fn, lo, hi)


def horse_scene(skel: QuadSkeleton, st: Optional[HorseStyle] = None) -> sdf.Scene:
    st = st or HorseStyle()
    J = skel.J
    s = _s(skel)
    bulk = skel.props.bulk * st.girth
    sc = sdf.Scene()
    spine = {k: J[k] for k in ("Spine1", "Spine2", "Chest", "Neck1")}
    bl = skel.props.body_length

    def at(y: float, z_below_spine: float) -> np.ndarray:
        """A point on the mid-line at body-y `y` (default horse's metres), `z` below the spine."""
        yy = y * bl * s
        # the spine's height there, interpolated along its joints
        ys = [J["Hips"][1], J["Spine2"][1], J["Chest"][1], J["Neck1"][1]]
        zs = [J["Hips"][2], J["Spine2"][2], J["Chest"][2], J["Neck1"][2]]
        order = np.argsort(ys)
        z = float(np.interp(yy, np.array(ys)[order], np.array(zs)[order]))
        return np.array([0.0, yy, z - z_below_spine * s])

    # -- the barrel: breast to buttock, the ribs widest behind the girth, the flank tucked up
    # toward the stifle so the belly does not run straight into the hind legs -----------------
    barrel = [
        (at(-0.62, 0.42), 0.13, 0.16),
        (at(-0.50, 0.33), 0.21, 0.26),
        (at(-0.26, 0.30), 0.27, 0.33),
        (at(0.00, 0.29), 0.30, 0.335),
        (at(0.22, 0.26), 0.29, 0.30),
        (at(0.42, 0.18), 0.26, 0.235),
        (at(0.60, 0.15), 0.22, 0.18),
        (at(0.74, 0.14), 0.10, 0.10),
    ]
    barrel = [(c, ru * s * bulk, rv * s * (0.85 + 0.15 * bulk)) for c, ru, rv in barrel]
    sc.union(sdf.sweep(barrel, X, axis=Y, density=4, max_spheres=120), k=0.0)
    # the withers: a ridge over the shoulders, where the saddle's front sits behind
    sc.union(sdf.ellipsoid(at(-0.30, -0.02), np.array([0.075, 0.20, 0.07]) * s), k=0.06 * s)
    # the back's top line, so the barrel's round does not dip between withers and croup
    sc.union(sdf.capsule(at(-0.20, 0.03), at(0.40, 0.02), 0.06 * s), k=0.08 * s)

    def jp(name: str, dy: float, dz: float) -> Tuple[float, float]:
        return (float(J[name][1] + dy * s), float(J[name][2] + dz * s))

    def jz(name: str, dz: float) -> float:
        return float(J[name][2] + dz * s)

    # -- the quarters: drawn in side view -- the point of hip, the round of the croup, the
    # point of buttock, the hamstring's line down to the hock, the gaskin, the stifle forward
    # at the flank's fold -- and swelled out from the body ------------------------------------
    cq = st.croup
    hind = [jp("Hips", -0.10, -0.04), jp("Hips", 0.10, 0.05), jp("TailHead", -0.06, 0.0),
            jp("Thigh.L", 0.28, 0.02), jp("Thigh.L", 0.26, -0.16), jp("HindCannon.L", 0.12, 0.28),
            jp("HindCannon.L", 0.08, 0.12), jp("HindCannon.L", 0.055, 0.04), jp("HindCannon.L", -0.03, 0.04),
            jp("Gaskin.L", 0.15, -0.14), jp("Gaskin.L", 0.03, -0.05), jp("Gaskin.L", -0.045, 0.03),
            jp("Gaskin.L", -0.03, 0.16), jp("Thigh.L", -0.22, -0.02), jp("Hips", -0.12, -0.12)]
    wd = skel.props.width
    hind_x = [(jz("Hips", 0.05), 0.125 * s * wd), (jz("Thigh.L", 0.0), 0.16 * s * wd), (jz("Gaskin.L", 0.0), 0.175 * s * wd),
              (jz("HindCannon.L", 0.0), 0.16 * s * wd)]
    hind_t = [(jz("Hips", 0.05), 0.11 * s * cq * bulk), (jz("Thigh.L", 0.0), 0.15 * s * cq * bulk),
              (jz("Gaskin.L", 0.05), 0.13 * s * cq * bulk), (jz("Gaskin.L", -0.15), 0.09 * s * bulk), (jz("HindCannon.L", 0.0), 0.07 * s * bulk)]
    for sx in (1.0, -1.0):
        sc.union(pillow(hind, sx, hind_x, hind_t, 0.30 * s), k=0.09 * s)
        # the point of hip: the bone at the front corner of the quarters
        sc.union(sdf.ellipsoid(np.array([sx * 0.215 * s * wd, *jp("Hips", -0.07, -0.09)]), np.array([0.06, 0.075, 0.06]) * s * bulk),
                 k=0.05 * s)

    # -- the shoulders: the blade laid back from the withers to its point, the arm and the
    # triceps' mass behind it down to the elbow, all one drawn shape ---------------------------
    fore = [jp("Scapula.L", 0.08, 0.06), jp("Scapula.L", -0.06, 0.07), jp("Humerus.L", 0.03, 0.18),
            jp("Humerus.L", -0.07, 0.03), jp("Humerus.L", -0.085, -0.04), jp("Forearm.L", -0.18, 0.08),
            jp("Forearm.L", -0.11, -0.02), jp("Forearm.L", -0.09, -0.14), jp("Forearm.L", 0.04, -0.12),
            jp("Forearm.L", 0.07, 0.0), jp("Forearm.L", 0.105, 0.14), jp("Scapula.L", 0.10, -0.26),
            jp("Scapula.L", 0.11, -0.08)]
    fore_x = [(jz("Scapula.L", 0.06), 0.06 * s * wd), (jz("Humerus.L", 0.15), 0.13 * s * wd), (jz("Humerus.L", 0.0), 0.16 * s * wd),
              (jz("Forearm.L", 0.0), 0.16 * s * wd), (jz("Forearm.L", -0.15), 0.155 * s * wd)]
    fore_t = [(jz("Scapula.L", 0.06), 0.06 * s * bulk), (jz("Humerus.L", 0.2), 0.10 * s * bulk), (jz("Humerus.L", 0.0), 0.115 * s * bulk),
              (jz("Forearm.L", 0.0), 0.10 * s * bulk), (jz("Forearm.L", -0.15), 0.08 * s * bulk)]
    for sx in (1.0, -1.0):
        sc.union(pillow(fore, sx, fore_x, fore_t, 0.22 * s), k=0.06 * s)
        # the breast: a pectoral each side, a cleft between
        sc.union(sdf.ellipsoid(np.array([sx * 0.075 * s * wd, *jp("Humerus.L", -0.10, -0.09)]),
                               np.array([0.085, 0.09, 0.14]) * s * bulk), k=0.06 * s)

    # -- the neck: deep at its root, a crest along the top, narrow at the throat -----------
    n1, n2, poll = J["Neck1"], J["Neck2"], J["Head"]
    down = np.array([0.0, 0.0, -1.0])
    neck = [
        (n1 + np.array([0.0, 0.12, -0.14]) * s, 0.19 * s * bulk, 0.34 * s),
        (n1 + np.array([0.0, -0.02, -0.02]) * s, 0.16 * s * bulk, 0.27 * s),
        (n2 + np.array([0.0, 0.03, -0.04]) * s, 0.13 * s * (0.8 + 0.2 * bulk), 0.20 * s),
        (poll + np.array([0.0, 0.03, -0.09]) * s, 0.095 * s, 0.12 * s),
    ]
    sc.union(sdf.sweep(neck, X, density=4, max_spheres=90), k=0.08 * s)
    # the crest: a heavy ridge along the top of the neck
    crest_pts = [n1 + np.array([0.0, 0.14, 0.13]) * s, n1 + np.array([0.0, -0.02, 0.16]) * s,
                 n2 + np.array([0.0, 0.02, 0.10]) * s, poll + np.array([0.0, 0.04, 0.02]) * s]
    # (a cob's is heavy: it stands a hand's breadth above the neck's line and runs thick into
    # the withers)
    crest_pts = [n1 + np.array([0.0, 0.16, 0.10]) * s] + crest_pts
    sc.union(sdf.tube_path(crest_pts, [0.06 * s * st.crest, 0.075 * s * st.crest, 0.095 * s * st.crest,
                                       0.07 * s * st.crest, 0.04 * s]),
             k=0.07 * s)

    # -- the head ---------------------------------------------------------------------------
    muzzle = J["Muzzle"]
    hd = muzzle - poll
    hl = float(np.linalg.norm(hd))
    hu = hd / hl
    hs = skel.props.head_size * s
    if st.head == "horse":
        _horse_head(sc, skel, st)

    # -- the legs ---------------------------------------------------------------------------
    for side, sx in (("L", 1.0), ("R", -1.0)):
        _leg(sc, skel, side, sx, fore=True, st=st)
        _leg(sc, skel, side, sx, fore=False, st=st)

    # -- the tail: the dock, and the hair hanging from it -----------------------------------
    t1, t2, t3 = J["Tail1"], J["Tail2"], J["Tail3"]
    tip = J["TailTip"]
    if st.tail > 0.0:
        sc.union(sdf.round_cone(t1 + np.array([0.0, -0.03, 0.0]) * s, t2, 0.06 * s, 0.045 * s), k=0.05 * s)
        L = st.tail
        hang = [t2 + np.array([0.0, 0.02, 0.0]) * s,
                t3 + np.array([0.0, 0.03, 0.0]) * s,
                tip + np.array([0.0, 0.03, 0.02]) * s,
                tip + np.array([0.0, 0.02, -0.28 * L]) * s,
                tip + np.array([0.0, -0.01, -0.46 * L]) * s]
        sc.union(sdf.tube_path(hang, [0.05 * s, 0.07 * s, 0.072 * s, 0.055 * s, 0.025 * s], density=3), k=0.05 * s)
        # the hair parts into locks round the core, of different lengths, a little apart at the
        # ends: the silhouette is hair and not a club
        for i, (dx, dy, dz) in enumerate(((0.07, 0.02, 0.0), (-0.07, 0.03, -0.06), (0.03, 0.08, -0.13), (-0.045, -0.035, -0.20),
                                          (0.08, -0.02, -0.09), (-0.02, 0.09, -0.03), (0.0, -0.05, -0.15), (-0.08, 0.05, 0.03))):
            a = t3 + np.array([dx * 0.4, 0.02, -0.02 - 0.04 * i]) * s
            b = tip + np.array([dx * 0.9, dy, -0.28 * L + dz]) * s
            c = tip + np.array([dx * 1.1, dy * 0.7, -0.44 * L + dz * 0.8]) * s
            sc.union(sdf.tube_path([a, b, c], [0.034 * s, 0.04 * s, 0.012 * s], density=3), k=0.02 * s)

    # -- the hogged mane: a short clipped ridge along the crest, a tuft of forelock ----------
    if st.mane == "hogged":
        # the ridge sits on the crest's own top line, found on the body built without it
        ridge = list(mane_line(skel, st) + np.array([0.0, 0.0, 0.004]) * s)
        n = len(ridge)
        radii = [0.018 * s + 0.012 * s * math.sin(math.pi * min(1.0, 0.15 + i / (n - 1))) for i in range(n)]
        sc.union(sdf.tube_path(ridge, radii), k=0.02 * s)
        sc.union(sdf.tube_path([poll + np.array([0.0, -0.02, 0.07]) * hs, poll + hu * 0.18 * hl + np.array([0.0, -0.05, 0.05]) * hs],
                               [0.022 * hs, 0.01 * hs]), k=0.02 * s)
    # standing square on the ground: nothing below the soles
    sc.intersect(sdf.plane(np.array([0.0, 0.0, 0.0]), np.array([0.0, 0.0, -1.0])))
    return sc


_MANE_CACHE: Dict[tuple, np.ndarray] = {}


def mane_line(skel: QuadSkeleton, st: HorseStyle) -> np.ndarray:
    """The top line of the neck from the withers to the poll, as points on the coat: where the
    hogged mane stands and where the painter puts it. Found by dropping onto the body built
    without a mane, so it follows whatever crest the style gives."""
    key = (tuple(np.round(skel.J["Neck1"], 4)), tuple(np.round(skel.J["Head"], 4)), st.crest, st.girth, skel.props.bulk)
    if key in _MANE_CACHE:
        return _MANE_CACHE[key]
    from dataclasses import replace
    bare = horse_scene(skel, replace(st, mane="none", tail=0.0, feather=0.0))
    s = _s(skel)
    y0 = skel.J["Neck1"][1] + 0.16 * s
    y1 = skel.J["Head"][1] + 0.05 * s
    pts = []
    for y in np.linspace(y0, y1, 11):
        z = skel.J["Head"][2] + 0.4 * s
        for _ in range(200):
            d = bare.eval(np.array([[0.0, y, z]]))[0]
            if d < 0.0015 * s:
                break
            z -= max(d * 0.8, 0.001 * s)
        pts.append(np.array([0.0, y, z]))
    out = np.array(pts)
    _MANE_CACHE[key] = out
    return out


def _horse_head(sc: sdf.Scene, skel: QuadSkeleton, st: HorseStyle) -> None:
    """A horse's head on the poll: the cranium, the long face, the muzzle, the jowls, the ears."""
    J = skel.J
    s = _s(skel)
    poll, muzzle = J["Head"], J["Muzzle"]
    hd = muzzle - poll
    hl = float(np.linalg.norm(hd))
    hu = hd / hl
    hs = skel.props.head_size * s
    # the cranium and the forehead
    sc.union(sdf.ellipsoid(poll + hu * 0.10 * hl + np.array([0.0, 0.0, -0.02]) * hs,
                           np.array([0.095, 0.12, 0.11]) * hs), k=0.05 * s)
    # the face, tapering to the muzzle
    sc.union(sdf.elliptic_cone(poll + hu * 0.18 * hl, muzzle - hu * 0.10 * hl,
                               0.092 * hs, 0.10 * hs, 0.066 * hs, 0.078 * hs, X), k=0.05 * s)
    # the muzzle's bulb and the lips
    sc.union(sdf.ellipsoid(muzzle - hu * 0.05 * hl + np.array([0.0, 0.0, 0.0]), np.array([0.075, 0.082, 0.078]) * hs),
             k=0.04 * s)
    # the jowls (cheeks), round under the eyes
    jaw = J["Jaw"]
    for sx in (1.0, -1.0):
        c = jaw + np.array([sx * 0.058, -0.03, 0.0]) * hs
        sc.union(sdf.ellipsoid(c, np.array([0.06, 0.12, 0.11]) * hs), k=0.05 * s)
    # the jaw's line under the face
    sc.union(sdf.capsule(jaw + np.array([0.0, 0.0, -0.05]) * hs, J["Chin"] + np.array([0.0, 0.0, 0.02]) * hs, 0.045 * hs),
             k=0.05 * s)
    # the nostrils and the mouth's line
    for sx in (1.0, -1.0):
        sc.subtract(sdf.ellipsoid(muzzle + hu * 0.01 * hl + np.array([sx * 0.04, 0.0, 0.035]) * hs,
                                  np.array([0.018, 0.026, 0.02]) * hs), k=0.012 * s)
    sc.subtract(sdf.capsule(J["Chin"] + np.array([0.045, -0.04, 0.035]) * hs, J["Chin"] + np.array([-0.045, -0.04, 0.035]) * hs,
                            0.008 * hs), k=0.01 * s)
    # the eyes' brows
    for sx in (1.0, -1.0):
        e = eye_centre(skel, sx)
        sc.union(sdf.sphere(e + np.array([sx * -0.004, 0.0, 0.012]) * hs, 0.03 * hs), k=0.02 * s)
    # the ears: flattened cones, hollow in front
    for side, sx in (("L", 1.0), ("R", -1.0)):
        b = skel.bones[f"Ear.{side}"]
        base, tip = b.head, b.tail
        sc.union(sdf.elliptic_cone(base, tip, 0.035 * hs, 0.025 * hs, 0.008 * hs, 0.006 * hs, -Y), k=0.02 * s)
        cup_a = base + (tip - base) * 0.15 + np.array([0.0, -0.016, 0.0]) * hs
        cup_b = base + (tip - base) * 0.85 + np.array([0.0, -0.008, 0.0]) * hs
        sc.subtract(sdf.elliptic_cone(cup_a, cup_b, 0.022 * hs, 0.012 * hs, 0.004 * hs, 0.003 * hs, -Y), k=0.006 * s)


def eye_centre(skel: QuadSkeleton, sx: float) -> np.ndarray:
    poll, muzzle = skel.J["Head"], skel.J["Muzzle"]
    hs = skel.props.head_size * _s(skel)
    hd = muzzle - poll
    return poll + hd * 0.26 + np.array([sx * 0.088, 0.0, 0.035]) * hs


def hoof_cone(skel: QuadSkeleton, cor: np.ndarray, hf: float) -> sdf.Prim:
    """The hoof below the coronet `cor`: wider at the ground, flat soled, the wall sloping."""
    s = _s(skel)
    base = np.array([cor[0], cor[1] - 0.025 * s * hf, 0.0])
    return sdf.elliptic_cone(cor + np.array([0.0, 0.0, 0.01]) * s, base + np.array([0.0, 0.0, 0.004]) * s,
                             0.046 * s * hf, 0.05 * s * hf, 0.062 * s * hf, 0.072 * s * hf, X)


def _leg(sc: sdf.Scene, skel: QuadSkeleton, side: str, sx: float, fore: bool, st: HorseStyle) -> None:
    J = skel.J
    s = _s(skel)
    b = skel.props.bulk
    k = 0.03 * s
    if fore:
        elbow, knee, fet, cor, toe = (J[f"Forearm.{side}"], J[f"FrontCannon.{side}"], J[f"FrontPastern.{side}"],
                                      J[f"FrontHoof.{side}"], J[f"FrontToe.{side}"])
        # the forearm: the muscle thick at the elbow, the tendon line behind to the knee
        sc.union(sdf.elliptic_cone(elbow + np.array([0.0, -0.01, 0.04]) * s, knee + np.array([0.0, 0.0, 0.03]) * s,
                                   0.085 * s * b, 0.10 * s * b, 0.05 * s * b, 0.055 * s * b, X), k=0.06 * s)
        # the knee: a flat, bony block
        sc.union(sdf.ellipsoid(knee + np.array([0.0, -0.005, 0.0]) * s, np.array([0.05, 0.055, 0.06]) * s * b), k=k)
    else:
        stifle, hock, fet, cor, toe = (J[f"Gaskin.{side}"], J[f"HindCannon.{side}"], J[f"HindPastern.{side}"],
                                       J[f"HindHoof.{side}"], J[f"HindToe.{side}"])
        # the gaskin: muscle behind the tibia, lean down to the hock
        sc.union(sdf.elliptic_cone(stifle + np.array([0.0, 0.03, -0.02]) * s, hock + np.array([0.0, -0.01, 0.05]) * s,
                                   0.085 * s * b, 0.11 * s * b, 0.045 * s * b, 0.055 * s * b, X), k=0.05 * s)
        # the hock, and its point behind
        sc.union(sdf.ellipsoid(hock + np.array([0.0, 0.0, 0.0]) * s, np.array([0.05, 0.065, 0.07]) * s * b), k=k)
        sc.union(sdf.round_cone(hock + np.array([0.0, 0.02, 0.02]) * s, hock + np.array([0.0, 0.075, 0.06]) * s,
                                0.03 * s * b, 0.026 * s * b), k=0.025 * s)
        knee = hock
    # the cannon: flat side to side, deep with the tendons behind
    sc.union(sdf.elliptic_cone(knee + np.array([0.0, 0.005, -0.04]) * s, fet + np.array([0.0, 0.0, 0.03]) * s,
                               0.04 * s * b, 0.054 * s * b, 0.038 * s * b, 0.052 * s * b, X), k=0.03 * s)
    # the fetlock joint, round behind
    sc.union(sdf.ellipsoid(fet + np.array([0.0, 0.012, 0.0]) * s, np.array([0.045, 0.058, 0.05]) * s * b), k=k)
    # the pastern
    sc.union(sdf.round_cone(fet, cor, 0.036 * s * b, 0.042 * s * b), k=0.02 * s)
    # the hoof: wider at the ground, flat soled, the wall sloping
    sc.union(hoof_cone(skel, cor, st.hoof), k=0.012 * s)
    if st.cloven:
        # the cleft between the two claws, from the toe back most of the way to the heel
        sc.subtract(sdf.box(np.array([cor[0], toe[1] + 0.02 * s, 0.03 * s]), np.array([0.004, 0.035, 0.05]) * s), k=0.003 * s)
    # the feather: long hair from the fetlock down over the heel
    if st.feather > 0:
        f = st.feather
        # a skirt of hair from the back of the fetlock, flaring over the heel and the sides of
        # the hoof to the ground; the toe's wall stays clear in front
        top = fet + np.array([0.0, 0.035, 0.0]) * s
        hem = np.array([cor[0], cor[1] + 0.05 * s, 0.035 * s])
        sc.union(sdf.elliptic_cone(top, hem, 0.047 * s * f, 0.05 * s * f, 0.06 * s * f, 0.052 * s * f, X), k=0.02 * s)
        # the hair parts into a few locks at the hem behind and at the sides, so its edge is
        # ragged, not a bell
        for a in (-75.0, -35.0, 0.0, 35.0, 75.0):
            ang = math.radians(a)
            dirn = np.array([sx * math.sin(ang), math.cos(ang), 0.0])
            l_top = fet + dirn * 0.03 * s + np.array([0.0, 0.025, -0.04]) * s
            l_end = np.array([cor[0], cor[1] + 0.035 * s, 0.012 * s]) + dirn * 0.065 * s * f
            sc.union(sdf.round_cone(l_top, l_end, 0.024 * s * f, 0.011 * s * f), k=0.015 * s)


# --------------------------------------------------------------------------------------
# What a point on the body is: the painter's map
# --------------------------------------------------------------------------------------

def regions(skel: QuadSkeleton, P: np.ndarray, st: Optional[HorseStyle] = None) -> Dict[str, np.ndarray]:
    """Soft masks (0..1) over points P (n,3) at rest: `hoof`, `points` (the dark lower legs),
    `mane`, `tail`, `muzzle`, `eye`, `ear_in`, `dorsal` (the dun's stripe), `belly`, `feather`."""
    st = st or HorseStyle()
    J = skel.J
    s = _s(skel)
    z = P[:, 2]
    out: Dict[str, np.ndarray] = {}

    def sm(x):
        x = np.clip(x, 0.0, 1.0)
        return x * x * (3 - 2 * x)
    # the hooves: below the coronet band
    cor_z = J["FrontHoof.L"][2] + 0.005 * s
    # the hoof's wall: below the coronet and on the hoof itself, not the feather hanging over it
    on_hoof = np.full(len(P), 1e6)
    for side in ("L", "R"):
        for fore in ("Front", "Hind"):
            on_hoof = np.minimum(on_hoof, hoof_cone(skel, J[f"{fore}Hoof.{side}"], st.hoof).fn(P))
    out["hoof"] = sm((cor_z - z) / (0.012 * s)) * sm((0.008 * s - on_hoof) / (0.006 * s))
    # the points: the legs dark from above the knee and the hock down
    knee_z = J["FrontCannon.L"][2] + 0.10 * s
    out["points"] = sm((knee_z - z) / (0.12 * s))
    # the dusk above the points: the forearms and gaskins shade down into them
    out["dusk"] = sm((knee_z + 0.32 * s - z) / (0.34 * s))
    # the ground's reach: how far up the legs a road's mud and dust splash
    out["splash"] = sm((0.30 * s - z) / (0.24 * s))
    # the mane's ridge and the forelock: above the crest line
    n1, n2, poll = J["Neck1"], J["Neck2"], J["Head"]
    mane = np.zeros(len(P))
    if st.mane != "none":
        line = mane_line(skel, st)
        for a, b in zip(line[:-1], line[1:]):
            ab = b - a
            u = np.clip(((P - a) @ ab) / float(ab @ ab), 0, 1)
            d = np.linalg.norm(P - (a + u[:, None] * ab), axis=1)
            mane = np.maximum(mane, sm((0.055 * s - d) / (0.015 * s)))
    out["mane"] = mane * (1.0 if st.mane != "none" else 0.0)
    # the tail's hair: behind and below the dock
    t2 = J["Tail2"]
    out["tail"] = sm((P[:, 1] - (t2[1] - 0.01 * s)) / (0.03 * s)) * sm((t2[2] + 0.02 * s - z) / (0.05 * s))
    # the muzzle: the soft dark end of the face
    mz = J["Muzzle"]
    d = np.linalg.norm((P - (mz + (J["Head"] - mz) * 0.08)) / np.array([1.0, 1.1, 1.2]), axis=1)
    out["muzzle"] = sm((0.10 * s - d) / (0.03 * s))
    ey = np.zeros(len(P))
    for sx in (1.0, -1.0):
        ey = np.maximum(ey, sm((0.03 * s - np.linalg.norm(P - eye_centre(skel, sx), axis=1)) / (0.008 * s)))
    out["eye"] = ey
    ear = np.zeros(len(P))
    for side in ("L", "R"):
        b = skel.bones[f"Ear.{side}"]
        ab = b.tail - b.head
        u = np.clip(((P - b.head) @ ab) / float(ab @ ab), 0, 1)
        d = np.linalg.norm(P - (b.head + u[:, None] * ab), axis=1)
        ear = np.maximum(ear, sm((0.04 * s - d) / (0.01 * s)) * sm((P[:, 2] - b.head[2]) / (0.02 * s)))
    out["ear"] = ear
    # the dorsal stripe: a dun's dark line from the withers to the tail
    top = np.interp(P[:, 1], [J["Chest"][1], J["Hips"][1] + 0.3 * s], [J["Chest"][2], J["Hips"][2]])
    band = sm((0.03 * s - np.abs(P[:, 0])) / (0.02 * s)) * sm((z - top) / (0.03 * s))
    band *= sm((P[:, 1] - (J["Chest"][1] - 0.05 * s)) / (0.05 * s)) * sm(((J["Tail1"][1] + 0.02 * s) - P[:, 1]) / (0.03 * s))
    out["dorsal"] = band
    belly_z = J["Spine2"][2] - 0.55 * s
    out["belly"] = sm((belly_z - z) / (0.12 * s)) * sm((z - knee_z) / (0.1 * s))
    # the face: the head forward of the poll, which a dun carries darker than the body
    hd = J["Muzzle"] - J["Head"]
    u = ((P - J["Head"]) @ hd) / float(hd @ hd)
    off = np.linalg.norm(P - (J["Head"] + np.clip(u, 0, 1)[:, None] * hd), axis=1)
    out["face"] = sm((u + 0.05) / 0.2) * sm((0.20 * s - off) / (0.05 * s))
    fz_hi = J["FrontPastern.L"][2] + 0.05 * s
    out["feather"] = sm((fz_hi - z) / (0.03 * s)) * (1.0 - out["hoof"]) * (1.0 if st.feather > 0 else 0.0)
    return out


# --------------------------------------------------------------------------------------
# The tack: shells cut from the body's field
# --------------------------------------------------------------------------------------

class FieldPrim:
    """A primitive whose field is read from a sampled body field: a shell `inner`..`outer` metres
    off the body's surface, kept where `region(P) <= 0`."""


def shell_prim(field: sdf.SampledField, inner: float, outer: float, region, lo, hi) -> sdf.Prim:
    def fn(P):
        d = field.eval(P)
        sh = np.maximum(d - outer, inner - d)
        return np.maximum(sh, region(P))
    return sdf.Prim(fn, np.asarray(lo, float), np.asarray(hi, float))


def _box_region(c, half, round_r=0.0):
    c = np.asarray(c, float)
    half = np.asarray(half, float)

    def fn(P):
        q = np.abs(P - c) - half
        return np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0) - round_r
    return fn


def _slab(point, normal, half):
    point = np.asarray(point, float)
    n = np.asarray(normal, float)
    n = n / np.linalg.norm(n)

    def fn(P):
        return np.abs((P - point) @ n) - half
    return fn


def _and(*fns):
    def fn(P):
        d = fns[0](P)
        for f in fns[1:]:
            d = np.maximum(d, f(P))
        return d
    return fn


# The irons hang this far out from the midline (default horse's metres): where the rider's feet are
# (player-feel's seat clips, checked against the body SDF: at 0.33 the shins went 6 cm into the
# barrel, at 0.37 with the toes turned out 3 cm, the calf's radius allowed for).
IRON_X = 0.37
# and the leathers' drop from the bar to the iron's eye: the tread comes 0.64 m under the seat,
# where the balls of the rider's feet are (0.63), with a sole between
LEATHER = 0.46


def saddle_point(skel: QuadSkeleton) -> np.ndarray:
    return skel.bones["Socket.Saddle"].head.copy()


def tack_scenes(skel: QuadSkeleton, body: sdf.SampledField) -> Dict[str, sdf.Scene]:
    """The Wardens' tack for this horse, each piece a scene. Material regions for the painter are
    by name: `leather`, `cloth`, `iron`, `brass`."""
    J = skel.J
    s = _s(skel)
    seat = saddle_point(skel)
    out: Dict[str, sdf.Scene] = {}
    lo_all = np.array([-0.6, -1.4, 0.3]) * s
    hi_all = np.array([0.6, 1.2, 2.2]) * s

    # the saddle cloth: wool, square cut, hanging to mid-barrel; under the saddle
    cloth = sdf.Scene()
    c_c = seat + np.array([0.0, 0.06, -0.26]) * s
    cloth.union(shell_prim(body, 0.002 * s, 0.014 * s,
                           _box_region(c_c, np.array([0.60, 0.30, 0.30]) * s, 0.03 * s),
                           c_c - np.array([0.6, 0.34, 0.34]) * s, c_c + np.array([0.6, 0.34, 0.34]) * s))
    out["cloth"] = cloth

    # the saddle: skirts of leather down each side, the seat a sweep over the back that dips
    # between the pommel and the cantle
    sad = sdf.Scene()
    c_s = seat + np.array([0.0, 0.0, -0.16]) * s
    sad.union(shell_prim(body, 0.012 * s, 0.03 * s,
                         _box_region(c_s, np.array([0.40, 0.23, 0.19]) * s, 0.04 * s),
                         c_s - np.array([0.45, 0.28, 0.25]) * s, c_s + np.array([0.45, 0.28, 0.25]) * s))
    top = []
    for dy, dz, ru, rv in ((-0.24, 0.07, 0.07, 0.05), (-0.19, 0.08, 0.11, 0.07), (-0.10, 0.025, 0.16, 0.07),
                           (0.00, 0.0, 0.17, 0.07), (0.10, 0.025, 0.17, 0.07), (0.17, 0.08, 0.15, 0.08),
                           (0.21, 0.10, 0.12, 0.05)):
        c = seat + np.array([0.0, dy, dz]) * s
        rvv = rv * s
        top.append((c - np.array([0.0, 0.0, rvv]), ru * s, rvv))
    sad.union(sdf.sweep(top, X, axis=Y, density=4, max_spheres=80), k=0.03 * s)
    out["saddle"] = sad

    # the girth, round the barrel behind the elbows; the breastplate round the chest front
    girth = sdf.Scene()
    gy = J["Forearm.L"][1] + 0.12 * s
    girth.union(shell_prim(body, 0.004 * s, 0.014 * s,
                           _and(_slab(np.array([0.0, gy, 0.0]), np.array([0.0, 1.0, -0.12]), 0.035 * s),
                                lambda P: P[:, 2] - (seat[2] - 0.12 * s)),
                           np.array([-0.5, gy - 0.1, 0.5]) * np.array([s, 1, s]), np.array([0.5, gy + 0.1, 1.6 * s])))
    # the breastplate: a strap from the saddle's front on each side, round the breast above the
    # points of the shoulders
    shoulder_z = J["Humerus.L"][2] + 0.10 * s
    ring = []
    for t in np.linspace(-1.0, 1.0, 9):
        a = t * math.pi * 0.5
        # round the front of the chest, from one side to the other: each point found by walking
        # in from outside until it lies on the coat
        dirn = np.array([math.sin(a), -math.cos(a), 0.0])
        c0 = np.array([0.0, J["Humerus.L"][1] + 0.05 * s, shoulder_z - 0.05 * s * math.cos(a)])
        p = c0 + dirn * 0.8 * s
        for _ in range(80):
            d = body.eval(p[None, :])[0] - 0.011 * s
            if abs(d) < 0.001 * s:
                break
            # (the sampled field reads huge far from the body: step no more than 5 cm at a time)
            p = p - dirn * min(max(d, -0.02 * s), 0.05 * s) * 0.9
        ring.append(p)
    for sx in (1.0, -1.0):
        ring_side = [p for p in ring if p[0] * sx >= -1e-6]
        ring_side = sorted(ring_side, key=lambda p: -abs(p[0]))
        back = seat + np.array([sx * 0.26, -0.20, -0.12]) * s
        pts = [back] + ring_side
        for i, p in enumerate(pts):
            for _ in range(3):
                d = body.eval(p[None, :])[0]
                g = body.gradient(p[None, :])[0]
                p = p - g * (d - 0.011 * s)
            pts[i] = p
        girth.union(sdf.tube_path(pts, 0.011 * s, density=3))
    # the stirrup leathers, from the saddle's bars down the flaps
    for sx in (1.0, -1.0):
        top = np.array([sx * 0.29 * s, seat[1] - 0.06 * s, seat[2] - 0.08 * s])
        d_body = body.eval(top[None, :])[0]
        top[0] += sx * max(0.0, 0.035 * s - d_body)
        bot = np.array([sx * IRON_X * s, top[1], top[2] - LEATHER * s])
        girth.union(sdf.elliptic_cone(top, bot, 0.004 * s, 0.016 * s, 0.004 * s, 0.016 * s, X))
    out["straps"] = girth

    # the stirrups: leathers from the saddle's bars, irons hanging below the flaps
    irons = sdf.Scene()
    for sx in (1.0, -1.0):
        side_x = sx * 0.29 * s
        top = np.array([side_x, seat[1] - 0.06 * s, seat[2] - 0.08 * s])
        # the leather hangs just clear of the flap
        d_body = body.eval(top[None, :])[0]
        top[0] += sx * max(0.0, 0.035 * s - d_body)
        bot = np.array([sx * IRON_X * s, top[1], top[2] - LEATHER * s])
        ring = bot + np.array([0.0, 0.0, -0.055]) * s
        irons.union(sdf.torus(ring, 0.055 * s, 0.008 * s, axis=Y))
        # the tread
        irons.union(sdf.box(ring + np.array([0.0, 0.0, -0.05]) * s, np.array([0.045, 0.028, 0.006]) * s))
    out["irons"] = irons

    # the bridle: the headstall over the poll and down the cheeks, the browband, the noseband,
    # the throatlash; the bit's rings; the reins to the saddle's front
    br = sdf.Scene()
    poll, muzzle = J["Head"], J["Muzzle"]
    hd = muzzle - poll
    hu = hd / np.linalg.norm(hd)
    hs = skel.props.head_size * s
    lo_h = poll - np.array([0.2, 0.5, 0.7]) * hs
    hi_h = poll + np.array([0.2, 0.2, 0.2]) * hs
    lo_h = np.minimum(lo_h, muzzle - 0.2 * hs)
    hi_h = np.maximum(hi_h, muzzle + 0.2 * hs)
    side_normal = np.cross(hu, X)
    # noseband: a ring round the face, two thirds of the way down
    nb = poll + hd * 0.62
    br.union(shell_prim(body, 0.0, 0.009 * hs, _slab(nb, hu, 0.018 * hs), lo_h, hi_h))
    # browband across the forehead below the ears
    bb = poll + hd * 0.07 + np.array([0.0, 0.0, 0.02]) * hs
    br.union(shell_prim(body, 0.0, 0.009 * hs, _and(_slab(bb, hu + np.array([0.0, 0.0, 0.6]), 0.014 * hs),
                                                   lambda P, bb=bb: -(P - bb) @ side_normal - 0.0),
                        lo_h, hi_h))
    # the headstall: over the poll behind the ears, down each cheek to the bit
    bit = skel.bones["Socket.Bit"].head
    for sx in (1.0, -1.0):
        ring = np.array([sx * abs(bit[0]), bit[1], bit[2]])
        a = poll + np.array([sx * 0.07, 0.03, 0.05]) * hs
        b = poll + hd * 0.35 + np.array([sx * 0.095, 0.0, 0.0]) * hs
        c = ring + np.array([sx * 0.005, 0.015, 0.02]) * hs
        pts = [a, b, c]
        # hold each point just off the skin
        for i, p in enumerate(pts):
            d = body.eval(p[None, :])[0]
            g = body.gradient(p[None, :])[0]
            pts[i] = p - g * (d - 0.008 * hs)
        br.union(sdf.tube_path(pts, 0.009 * hs))
        br.union(sdf.torus(ring, 0.028 * hs, 0.0055 * hs, axis=X))
    # over the poll
    br.union(shell_prim(body, 0.0, 0.009 * hs, _slab(poll + np.array([0.0, 0.03, 0.0]) * hs, np.array([0.0, 1.0, -0.25]), 0.013 * hs),
                        poll - np.array([0.2, 0.12, 0.25]) * hs, poll + np.array([0.2, 0.12, 0.2]) * hs))
    # the reins: from each ring back along the neck to the pommel, sagging a little
    pom = seat + np.array([0.0, -0.22, 0.05]) * s
    for sx in (1.0, -1.0):
        ring = np.array([sx * (abs(bit[0]) + 0.004 * hs), bit[1] + 0.005, bit[2]])
        mid1 = J["Neck2"] + np.array([sx * 0.10, 0.0, -0.10]) * s
        mid2 = J["Neck1"] + np.array([sx * 0.14, 0.05, 0.02]) * s
        end = pom + np.array([sx * 0.05, 0.0, -0.01]) * s
        pts = [ring, mid1, mid2, end]
        for i in (1, 2):
            d = body.eval(pts[i][None, :])[0]
            g = body.gradient(pts[i][None, :])[0]
            pts[i] = pts[i] - g * (d - 0.02 * s)
        br.union(sdf.tube_path(pts, 0.0065 * s))
    out["bridle"] = br
    return out


def tack_region(name: str) -> str:
    return {"cloth": "cloth", "saddle": "leather", "straps": "leather", "irons": "iron", "bridle": "leather"}[name]
