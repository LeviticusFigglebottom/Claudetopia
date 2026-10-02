"""What the bosses wear that nobody else does: hats, crowns, hoods and veils, a tabard, a founder's
apron, mantles of knotted cords and ropes of beads.

A boss is known across a hall before its face is: by the shape on its head and the shape of what
hangs off it. These are built as the rest of the wardrobe is (cloth.py): offsets of the body's and
the head's own fields where they lie on the body, and their own shapes where they stand off it --
a brim, a crown's tines, a cord hanging straight from a band. Headgear is rigid to the head
(`bone="Head"`); what hangs from the shoulders takes the body's weights.

Each names how it is dressed (`paint_as`: the palette colour it takes -- a felt hat is the cloth's,
not the metal its slot would give it) and whether it covers the crown (`covers_head`: the hair under
it is worn close).
"""
from __future__ import annotations

import math
from typing import List, Optional

import numpy as np

from . import body as bodylib
from . import sdf
from .rig import Skeleton
from .sdf import Prim, Scene
from . import cloth as C

UP = np.array([0.0, 0.0, 1.0])


# --- shapes a hat is made of -------------------------------------------------------------------

_HEADS: dict = {}


def _head(skel: Skeleton):
    """The head's field, sampled once per skeleton (it takes seconds, and a hat asks for it often)."""
    key = id(skel)
    if key not in _HEADS:
        _HEADS.clear()
        _HEADS[key] = (skel, C._head_field(skel))
    return _HEADS[key][1]


def _push_out(fld, p: np.ndarray, off: float, iters: int = 40) -> np.ndarray:
    """`p` moved out along the field's slope until it stands `off` off the surface (left where it is
    when it already does): where a cord or a bead lies on a body."""
    p = np.asarray(p, float).copy()
    h = 0.002
    for _ in range(iters):
        d = float(fld.eval(p[None])[0])
        if d >= off - 1e-4:
            break
        g = np.array([float(fld.eval((p + e)[None])[0]) - float(fld.eval((p - e)[None])[0])
                      for e in (np.array([h, 0, 0]), np.array([0, h, 0]), np.array([0, 0, h]))]) / (2 * h)
        n = np.linalg.norm(g)
        if n < 1e-6:
            break
        p = p + g / n * min(off - d + 1e-4, 0.03)
    return p


def _crown(skel: Skeleton, gap: float, rim_z: float, rise: float = 0.0, wide: float = 1.0) -> Prim:
    """A hat's crown: the head pushed out by `gap` (over the close hair a hat is worn on), and
    `rise` metres more above the skull's middle, from `rim_z` up. Solid: the head fills it."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    head = _head(skel)
    c = np.asarray(L["skull_c"], float)
    r = np.asarray(L["skull_r"], float)
    dome = sdf.ellipsoid(c + np.array([0.0, 0.0, rise * 0.5]),
                         (r + gap) * np.array([wide, wide, 1.0]) + np.array([0.0, 0.0, rise * 0.5]))

    def fn(P):
        d = np.minimum(head.eval(P) - gap, dome.fn(P))
        return np.maximum(d, rim_z - P[:, 2])
    lo = c - r * 1.6 - 0.05 * s
    hi = c + r * 1.6 + np.array([0.0, 0.0, rise]) + 0.05 * s
    lo[2] = rim_z - 0.01 * s
    return Prim(C._chunked(fn), lo, hi, "union", 0.0)


def _brim(cx: float, cy: float, z: float, r_in: float, r_out, thick: float, droop: float = 0.0,
          ry: float = 1.12) -> Prim:
    """A brim round (cx, cy) at height `z`: an annulus from `r_in` out to `r_out` (a number, or a
    function of the angle round from straight ahead), falling `droop` metres at its edge, and an
    ellipse `ry` times as deep as it is wide, as a head is."""
    r_max = float(r_out) if np.isscalar(r_out) else float(np.max(r_out(np.linspace(0.0, math.pi, 33))))

    def fn(P):
        x = P[:, 0] - cx
        y = (P[:, 1] - cy) / ry
        rr = np.hypot(x, y)
        a = np.arctan2(np.abs(x), -(P[:, 1] - cy))
        ro = r_out(a) if callable(r_out) else r_out
        f = np.clip((rr - r_in) / np.maximum(ro - r_in, 1e-4), 0.0, 1.0)
        zb = z - droop * f * f
        return np.maximum.reduce([np.abs(P[:, 2] - zb) - thick * 0.5, rr - ro, r_in * 0.6 - rr])
    m = r_max * ry + 0.02
    return Prim(C._chunked(fn), np.array([cx - m, cy - m, z - droop - thick - 0.02]),
                np.array([cx + m, cy + m, z + thick + 0.02]), "union", 0.0)


def _cone(cx: float, cy: float, z0: float, z1: float, r0: float, r1: float, ry: float = 1.0) -> Prim:
    """A solid frustum from radius `r0` at `z0` to `r1` at `z1` (a tall hat, a conical one)."""
    def fn(P):
        t = np.clip((P[:, 2] - z0) / max(z1 - z0, 1e-4), 0.0, 1.0)
        r = r0 + (r1 - r0) * t
        rr = np.hypot(P[:, 0] - cx, (P[:, 1] - cy) / ry)
        side = (rr - r) / math.sqrt(1.0 + ((r1 - r0) / max(z1 - z0, 1e-4)) ** 2)
        return np.maximum.reduce([side, z0 - P[:, 2], P[:, 2] - z1])
    m = max(r0, r1) * max(ry, 1.0) + 0.02
    return Prim(C._chunked(fn), np.array([cx - m, cy - m, z0 - 0.02]), np.array([cx + m, cy + m, z1 + 0.02]),
                "union", 0.0)


def _ring_on_head(skel: Skeleton, gap: float, z: float, n: int, out: float = 0.0) -> List[np.ndarray]:
    """`n` points round the head at height `z`, `gap` + `out` off it, from straight ahead round to
    the left and back."""
    L = bodylib.head_landmarks(skel)
    head = _head(skel)
    cy = float(L["skull_c"][1])
    return [C._surface_point(head, gap + out, 2.0 * math.pi * i / n, z, r_max=0.25, centre=(0.0, cy))
            for i in range(n)]


def _band(skel: Skeleton, gap: float, z0: float, z1: float, thick: float) -> Prim:
    """A band round the head between two heights, `gap` off it and `thick` deep."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    head = _head(skel)
    c = np.asarray(L["skull_c"], float)

    def fn(P):
        d = head.eval(P)
        shell = np.maximum(d - (gap + thick), gap - d)
        return np.maximum.reduce([shell, z0 - P[:, 2], P[:, 2] - z1])
    lo = c - np.array([0.16, 0.18, 0.0]) * s
    hi = c + np.array([0.16, 0.18, 0.0]) * s
    lo[2], hi[2] = z0 - 0.01, z1 + 0.01
    return Prim(C._chunked(fn), lo, hi, "union", 0.0)


def _garment(name: str, sc: Scene, *, material: str, paint_as: Optional[str], covers: bool = False,
             spacing: float = 0.0026, tris: int = 2200, smooth: int = 3, bone: Optional[str] = "Head") -> C.Garment:
    g = C.Garment(name, sc, spacing=spacing, smooth=smooth, target_tris=tris, material=material, bone=bone)
    g.paint_as = paint_as
    g.covers_head = covers
    return g


# --- headgear ------------------------------------------------------------------------------------

def kettle_hat(skel: Skeleton, body) -> C.Garment:
    """A Warden's kettle hat: a round iron cap sitting level on the brow, and a broad brim sloping
    down all round it, riveted to the cap's band. The militia's helm, which reads at a hundred
    paces as a man of the Wardens and nothing else."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    rim = float(L["brow_z"]) + 0.012 * s
    sc = Scene()
    sc.union(_crown(skel, 0.018 * s, rim, rise=0.03 * s))
    sc.union(_brim(0.0, cy, rim + 0.004 * s, 0.085 * s, 0.205 * s, 0.009 * s, droop=0.05 * s, ry=1.08),
             k=0.006 * s)
    # the band where the brim is riveted on, and a ridge over the cap from front to back
    for p in _ring_on_head(skel, 0.018 * s, rim + 0.012 * s, 18, out=0.004 * s):
        sc.union(sdf.sphere(p, 0.0042 * s), k=0.002 * s)
    ridge = [np.array([0.0, cy + float(L["skull_r"][1]) * math.cos(t) * 1.16,
                       float(L["skull_c"][2]) + (float(L["skull_r"][2]) * 1.16 + 0.03 * s) * math.sin(t)])
             for t in np.linspace(0.35, math.pi - 0.35, 13)]
    sc.union(sdf.tube_path(ridge, 0.005 * s, density=3), k=0.006 * s)
    return _garment("kettle_hat", sc, material="iron", paint_as=None, covers=True, tris=2400)


def miners_hat(skel: Skeleton, body) -> C.Garment:
    """An overman's hat of hardened felt: a high round crown, a brim turned down before and behind,
    and on its front a lump of clay with a tallow candle stood in it, for the light to count by."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    rim = float(L["brow_z"]) + 0.010 * s
    sc = Scene()
    sc.union(_crown(skel, 0.016 * s, rim, rise=0.05 * s, wide=1.03))
    sc.union(_brim(0.0, cy, rim + 0.006 * s, 0.085 * s, lambda a: (0.16 + 0.02 * np.cos(a) ** 2) * s,
                   0.007 * s, droop=0.03 * s), k=0.008 * s)
    sc.union(sdf.torus([0.0, cy, rim + 0.016 * s], float(L["skull_r"][0]) + 0.018 * s, 0.006 * s), k=0.004 * s)
    # the clay and the candle, at the front of the crown (another layer: tallow is not felt)
    front = C._surface_point(_head(skel), 0.020 * s, 0.0, rim + 0.045 * s, r_max=0.25, centre=(0.0, cy))
    wax = Scene()
    wax.union(sdf.ellipsoid(front + np.array([0.0, -0.010, 0.0]) * s, np.array([0.024, 0.018, 0.018]) * s))
    wick = front + np.array([0.0, -0.018 * s, 0.012 * s])
    wax.union(sdf.capsule(wick, wick + np.array([0.0, -0.004, 0.055]) * s, 0.0085 * s), k=0.004 * s)
    g = _garment("miners_hat", sc, material="leather", paint_as="secondary", covers=True, tris=2200)
    g.layers = [_garment("miners_hat_candle", wax, material="horn", paint_as="trim", spacing=0.0018, tris=500)]
    return g


def shift_cap(skel: Skeleton, body) -> C.Garment:
    """A shift-captain's cap of boiled leather, close to the skull and down over the ears, with a
    short stiff peak, a brass band round it and the captain's brass lamp-bracket on the brow."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    rim = float(L["brow_z"]) + 0.006 * s
    sc = Scene()
    sc.union(_crown(skel, 0.014 * s, rim, rise=0.018 * s))
    # the ear flaps: the crown carried down over the ears and the back of the head
    head = _head(skel)
    flaps = C.offset_shell(head, lambda P: C.sdf_smoothstep(0.0, 0.02 * s, P[:, 1] - cy + 0.03 * s)
                           * (1.0 - C.sdf_smoothstep(rim - 0.002, rim + 0.002, P[:, 2])),
                           0.006 * s, gap=0.012 * s,
                           bounds=(np.array([-0.13, cy - 0.06, float(L["nape_z"]) - 0.01]) * np.array([s, 1, 1]),
                                   np.array([0.13 * s, cy + 0.15 * s, rim + 0.01])))
    sc.union(flaps, k=0.006 * s)
    sc.union(_brim(0.0, cy, rim + 0.002 * s, 0.085 * s, lambda a: (0.085 + 0.065 * np.clip(np.cos(a), 0, 1) ** 3) * s,
                   0.006 * s, droop=0.012 * s), k=0.004 * s)
    brass = Scene()
    brass.union(_band(skel, 0.020 * s, rim + 0.002 * s, rim + 0.016 * s, 0.004 * s))
    front = C._surface_point(head, 0.026 * s, 0.0, rim + 0.03 * s, r_max=0.25, centre=(0.0, cy))
    brass.union(sdf.box(front, np.array([0.016, 0.006, 0.022]) * s, round_r=0.003 * s), k=0.003 * s)
    brass.union(sdf.capsule(front + np.array([0.0, -0.01, 0.0]) * s, front + np.array([0.0, -0.03, 0.02]) * s,
                            0.006 * s), k=0.003 * s)
    lamp = front + np.array([0.0, -0.034, 0.038]) * s
    brass.union(sdf.round_cone(lamp - np.array([0.0, 0.0, 0.016]) * s, lamp + np.array([0.0, 0.0, 0.012]) * s,
                               0.014 * s, 0.006 * s), k=0.003 * s)
    g = _garment("shift_cap", sc, material="leather", paint_as="leather", covers=True, tris=2400)
    g.layers = [_garment("shift_cap_brass", brass, material="iron", paint_as=None, spacing=0.0018, tris=900)]
    return g


def clerk_hat(skel: Skeleton, body) -> C.Garment:
    """A receiver's tall hat: a stiff black crown standing a hand and a half over the head,
    widening a little to its flat top, on a narrow brim, a band and a buckle round its foot."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    rim = float(L["brow_z"]) + 0.008 * s
    top = float(L["top"][2]) + 0.17 * s
    sc = Scene()
    sc.union(_crown(skel, 0.015 * s, rim))
    sc.union(_cone(0.0, cy, rim, top, 0.096 * s, 0.108 * s, ry=1.14), k=0.004 * s)
    sc.union(_brim(0.0, cy, rim + 0.003 * s, 0.09 * s, 0.135 * s, 0.006 * s, droop=0.006 * s), k=0.004 * s)
    band = Scene()
    band.union(_cone(0.0, cy, rim + 0.006 * s, rim + 0.03 * s, 0.1 * s, 0.101 * s, ry=1.14))
    band.subtract(_cone(0.0, cy, rim, rim + 0.04 * s, 0.094 * s, 0.096 * s, ry=1.14))
    band.union(sdf.box([0.0, cy - 0.118 * s, rim + 0.018 * s], np.array([0.016, 0.006, 0.016]) * s,
                       round_r=0.002 * s), k=0.002 * s)
    g = _garment("clerk_hat", sc, material="cloth", paint_as="secondary", covers=True, spacing=0.003, tris=1800)
    g.layers = [_garment("clerk_hat_band", band, material="iron", paint_as=None, spacing=0.002, tris=700)]
    return g


def magister_cap(skel: Skeleton, body) -> C.Garment:
    """A Sayer magister's cap: a broad soft bonnet of velvet worn on the back of the head, wider
    than the shoulders are deep, over a band, with the Circle's brass rings on its front."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    rim = float(L["brow_z"]) + 0.014 * s
    sc = Scene()
    sc.union(_band(skel, 0.012 * s, rim, rim + 0.03 * s, 0.01 * s))
    sc.union(_crown(skel, 0.016 * s, rim + 0.02 * s), k=0.008 * s)
    tilt = np.array([[1.0, 0.0, 0.0], [0.0, math.cos(0.22), -math.sin(0.22)], [0.0, math.sin(0.22), math.cos(0.22)]])
    sc.union(sdf.ellipsoid([0.0, cy + 0.022 * s, float(L["top"][2]) - 0.005 * s],
                           np.array([0.16, 0.17, 0.045]) * s, rot=tilt), k=0.02 * s)
    rings = Scene()
    front = C._surface_point(_head(skel), 0.024 * s, 0.0, rim + 0.016 * s, r_max=0.25, centre=(0.0, cy))
    for i, r in enumerate((0.022, 0.014, 0.007)):
        rings.union(sdf.torus(front + np.array([0.0, -0.004 * i, 0.0]) * s, r * s, 0.0024 * s,
                              axis=np.array([0.0, 1.0, 0.0])))
    g = _garment("magister_cap", sc, material="cloth", paint_as="secondary", covers=True, spacing=0.003, tris=2000)
    g.layers = [_garment("magister_cap_rings", rings, material="iron", paint_as=None, spacing=0.0015, tris=600)]
    return g


def crude_crown(skel: Skeleton, body) -> C.Garment:
    """A digger-king's crown, beaten out of somebody else's grave-goods: a rough band of bronze on
    the brow and nine tines of uneven height hammered up out of it, each with a knob, and the
    barrow's garnets set crooked in its front."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    z0 = float(L["brow_z"]) + 0.018 * s
    gap = 0.02 * s
    sc = Scene()
    sc.union(_band(skel, gap, z0, z0 + 0.036 * s, 0.006 * s))
    rng = np.random.default_rng(1019)
    n = 9
    pts = _ring_on_head(skel, gap, z0 + 0.03 * s, n, out=0.003 * s)
    for i, p in enumerate(pts):
        h = (0.07 + (0.035 if i % 2 == 0 else 0.0) + rng.uniform(-0.012, 0.012)) * s
        out = p - np.array([0.0, cy, p[2]])
        out[2] = 0.0
        out = out / max(np.linalg.norm(out), 1e-6)
        tip = p + out * 0.018 * s + UP * h + rng.uniform(-0.006, 0.006, 3) * s * np.array([1, 1, 0])
        sc.union(sdf.round_cone(p, tip, 0.010 * s, 0.0045 * s), k=0.006 * s)
        sc.union(sdf.sphere(tip, 0.0085 * s), k=0.003 * s)
    stones = Scene()
    for i, p in enumerate(_ring_on_head(skel, gap, z0 + 0.016 * s, 14, out=0.006 * s)):
        if i in (0, 2, 12, 5, 9):
            stones.union(sdf.ellipsoid(p, np.array([0.0075, 0.0075, 0.009]) * s))
    g = _garment("crude_crown", sc, material="iron", paint_as=None, covers=False, spacing=0.0022, tris=2400)
    g.layers = [_garment("crude_crown_stones", stones, material="horn", paint_as="trim", spacing=0.0015, tris=400)]
    return g


def antler_band(skel: Skeleton, body) -> C.Garment:
    """The band of blackened iron Ardo's antlers are fixed to, made for a smaller head than the one
    under it: across the brow and round, a strap over the crown from ear to ear, and a socket at
    each side of the crown where the beams are pinned (EnemyDress grows the antlers out of them)."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    z0 = float(L["brow_z"]) + 0.004 * s
    head = _head(skel)
    sc = Scene()
    sc.union(_band(skel, 0.012 * s, z0, z0 + 0.026 * s, 0.007 * s))
    strap = []
    for t in np.linspace(0.0, math.pi, 17):
        a = math.pi * 0.5
        d = np.array([math.cos(t), 0.0, math.sin(t)])
        o = np.array([0.0, cy - 0.01 * s, float(L["skull_c"][2])])
        lo_r, hi_r = 0.0, 0.25
        for _ in range(36):
            m = 0.5 * (lo_r + hi_r)
            if float(head.eval((o + d * m)[None])[0]) < 0.016 * s:
                lo_r = m
            else:
                hi_r = m
        q = o + d * hi_r
        if q[2] >= z0:
            strap.append(q)
    if len(strap) > 2:
        sc.union(sdf.tube_path(strap, 0.007 * s, density=3), k=0.008 * s)
    # the sockets, where the beams root (EnemyDress.grow_antlers: 7 cm each side of the crown)
    for sx in (1.0, -1.0):
        base = np.array([sx * 0.07 * s, cy - 0.01 * s, float(L["top"][2]) - 0.012 * s])
        q = C._surface_point(head, 0.016 * s, sx * math.pi * 0.5, float(base[2]), r_max=0.2, centre=(0.0, cy))
        sc.union(sdf.round_cone(q, base + np.array([sx * 0.008, 0.0, 0.03]) * s, 0.014 * s, 0.011 * s), k=0.008 * s)
    for p in _ring_on_head(skel, 0.012 * s, z0 + 0.013 * s, 12, out=0.006 * s):
        sc.union(sdf.sphere(p, 0.004 * s), k=0.002 * s)
    return _garment("antler_band", sc, material="iron", paint_as=None, covers=False, spacing=0.0022, tris=1600)


def cord_veil(skel: Skeleton, body) -> C.Garment:
    """The Name-Wife's veil: a band of plaited rush on the brow and, hung from it all round, the
    names she has not yet hung on her wall -- cords knotted in their families' weaves, a fringe of
    them falling over her face to below her chin, and longer behind to the nape."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    head = _head(skel)
    z0 = float(L["brow_z"]) + 0.02 * s
    sc = Scene()
    sc.union(_band(skel, 0.014 * s, z0 - 0.008 * s, z0 + 0.016 * s, 0.008 * s))
    sc.union(_crown(skel, 0.012 * s, z0), k=0.006 * s)
    rng = np.random.default_rng(7)
    n = 30
    chin = float(L["chin_z"])
    for i in range(n):
        a = 2.0 * math.pi * (i + 0.5) / n
        front = math.cos(a)
        end = chin - (0.07 if front > 0.3 else 0.03) * s - rng.uniform(0.0, 0.04) * s
        pts, rr = [], 0.0
        for z in np.linspace(z0, end, 9):
            p = C._surface_point(head, 0.022 * s, a, float(z), r_max=0.25, centre=(0.0, cy))
            r = math.hypot(p[0], p[1] - cy)
            rr = max(rr, r)
            pts.append(np.array([math.sin(a) * rr, cy - math.cos(a) * rr, float(z)]))
        sc.union(sdf.tube_path(pts, 0.0042 * s, density=3), k=0.002 * s)
        for k_ in range(2, 9, 2):
            if rng.random() < 0.75:
                sc.union(sdf.sphere(pts[k_], 0.0075 * s), k=0.002 * s)
    return _garment("cord_veil", sc, material="cloth", paint_as="trim", covers=True, spacing=0.0022, tris=3400,
                    smooth=2)


def wimple(skel: Skeleton, body) -> C.Garment:
    """A barrow-wife's wimple and veil: linen wound close round the head and the throat with the
    face left bare in an oval, and the veil falling from the crown behind to the shoulders."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    head = _head(skel)
    neck = np.asarray(skel.J["Neck"], float)
    gap, t = 0.012 * s, 0.008 * s
    throat = sdf.capsule(neck + np.array([0.0, 0.0, -0.02]) * s, np.array([0.0, 0.0, float(L["jaw_z"])]),
                         0.062 * s)
    face = sdf.ellipsoid([0.0, float(L["face_y"]) - 0.03 * s, float(L["nose_root_z"]) - 0.025 * s],
                         np.array([0.058, 0.08, 0.078]) * s)

    def fn(P):
        d = np.minimum(head.eval(P), throat.fn(P) - 0.01 * s) - (gap + t)
        d = np.maximum(d, -face.fn(P))
        return np.maximum(d, float(neck[2]) - 0.035 * s - P[:, 2])
    lo = np.array([-0.16, cy - 0.2, float(neck[2]) - 0.06]) * np.array([s, 1, 1])
    hi = np.array([0.16 * s, cy + 0.2 * s, float(L["top"][2]) + 0.05 * s])
    sc = Scene()
    sc.union(Prim(C._chunked(fn), lo, hi, "union", 0.0))
    # the veil behind: from the crown, falling and widening to below the nape
    top = np.array([0.0, cy + 0.03 * s, float(L["top"][2]) + 0.005 * s])
    bot = np.array([0.0, cy + 0.13 * s, float(neck[2]) - 0.07 * s])
    sc.union(sdf.loft([(top, 0.085 * s, 0.05 * s), ((top + bot) * 0.5 + np.array([0.0, 0.015, 0.0]) * s, 0.12 * s,
                                                                          0.045 * s), (bot, 0.15 * s, 0.03 * s)],
                      np.array([1.0, 0.0, 0.0]), axis=UP), k=0.02 * s)
    return _garment("wimple", sc, material="cloth", paint_as="secondary", covers=True, spacing=0.003, tris=2600)


def sou_wester(skel: Skeleton, body) -> C.Garment:
    """A lampman's sou'wester of oiled canvas: a round crown and a brim short before and long and
    drooping behind, over the collar, for the sea-mouth's weather to run off."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    rim = float(L["brow_z"]) + 0.006 * s
    sc = Scene()
    sc.union(_crown(skel, 0.016 * s, rim, rise=0.012 * s, wide=1.06))
    sc.union(_brim(0.0, cy, rim + 0.004 * s, 0.085 * s,
                   lambda a: (0.11 + 0.09 * (a / math.pi) ** 3) * s, 0.008 * s, droop=0.028 * s), k=0.01 * s)
    sc.union(sdf.torus([0.0, cy, rim + 0.012 * s], float(L["skull_r"][0]) + 0.02 * s, 0.005 * s), k=0.005 * s)
    return _garment("sou_wester", sc, material="leather", paint_as="primary", covers=True, tris=2200)


def reed_hat(skel: Skeleton, body) -> C.Garment:
    """A Reedfolk hat of plaited reed: a broad shallow cone, wider than the shoulders, on a band, for
    rain and for the long white light off the water."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    rim = float(L["brow_z"]) + 0.02 * s
    sc = Scene()
    top = float(L["top"][2]) + 0.12 * s
    sc.union(_cone(0.0, cy, rim + 0.01 * s, top, 0.3 * s, 0.012 * s))
    sc.subtract(_cone(0.0, cy, rim - 0.04 * s, top - 0.03 * s, 0.31 * s, 0.002 * s), k=0.004 * s)
    sc.union(sdf.torus([0.0, cy, rim + 0.011 * s], 0.296 * s, 0.006 * s), k=0.004 * s)
    # the band it sits on, and the crown of the head under the cone
    sc.union(_band(skel, 0.012 * s, rim - 0.004 * s, rim + 0.02 * s, 0.008 * s), k=0.006 * s)
    sc.union(_crown(skel, 0.012 * s, rim + 0.01 * s), k=0.01 * s)
    return _garment("reed_hat", sc, material="cloth", paint_as="trim", covers=True, spacing=0.003, tris=2000)


def choir_cowl(skel: Skeleton, body) -> C.Garment:
    """A chorister's cowl worn a hundred and seventy years: drawn up into a tall peak over the
    crown, as a bell is drawn, deep in front so the face is in its shadow, and falling round the jaw
    to the throat."""
    s = C._s(skel)
    L = bodylib.head_landmarks(skel)
    cy = float(L["skull_c"][1])
    head = _head(skel)
    gap, t = 0.024 * s, 0.008 * s
    top = float(L["top"][2])
    peak = sdf.round_cone(np.array([0.0, cy + 0.01 * s, float(L["skull_c"][2])]),
                          np.array([0.0, cy + 0.06 * s, top + 0.24 * s]), 0.1 * s, 0.012 * s)
    face = sdf.ellipsoid([0.0, float(L["face_y"]) - 0.06 * s, float(L["eye_z"]) - 0.035 * s],
                         np.array([0.066, 0.11, 0.1]) * s)
    jaw = float(L["chin_z"]) - 0.03 * s

    def fn(P):
        outer = np.minimum(head.eval(P) - (gap + t), peak.fn(P) - t)
        shell = np.maximum(outer, -(outer + t))
        shell = np.maximum(shell, -face.fn(P))
        return np.maximum(shell, jaw - P[:, 2])
    lo = np.array([-0.17 * s, cy - 0.22 * s, jaw - 0.02])
    hi = np.array([0.17 * s, cy + 0.2 * s, top + 0.28 * s])
    sc = Scene()
    sc.union(Prim(C._chunked(fn), lo, hi, "union", 0.0))
    # its hem, rolled
    return _garment("choir_cowl", sc, material="cloth", paint_as="primary", covers=True, spacing=0.003, tris=2600)


# --- worn on the body -----------------------------------------------------------------------------

def tabard(skel: Skeleton, body) -> C.Garment:
    """A tabard over the harness: a panel before and one behind from the shoulders to the knee, open
    at the sides and belted, standing off the padded coat under it, a roundel on the breast."""
    s = C._s(skel)
    h = skel.props.height
    half_w = 0.150 * s
    panels = lambda P: 1.0 - C.sdf_smoothstep(half_w - 0.012 * s, half_w + 0.004 * s, np.abs(P[:, 0]))  # noqa: E731
    g = C.skirt(skel, body, hem=0.30, flare=0.35, name="tabard", gap=0.040, folds=5)
    g.scene.intersect(sdf.box([0.0, 0.0, 0.5 * h], np.array([half_w, 0.4 * s, 0.5 * h])))
    reg = C.region_and(C.torso_region(skel, top=0.95, hem=0.52, sleeves=0.0, collar=0.01), panels)
    g.scene.union(C.offset_shell(body, reg, 0.006 * s, gap=0.036 * s,
                                 bounds=C.zbox(skel, 0.5 * h, 0.93 * h, xy=0.2)), k=0.01 * s)
    roundel = Scene()
    chest = np.asarray(skel.J["Chest"], float)
    fr = C._surface_point(body, 0.046 * s, 0.0, float(chest[2]) + 0.02 * s, r_max=0.4)
    roundel.union(sdf.torus(fr, 0.075 * s, 0.011 * s, axis=np.array([0.0, 1.0, 0.0])))
    roundel.union(sdf.ellipsoid(fr + np.array([0.0, 0.0, 0.005]) * s, np.array([0.028, 0.009, 0.045]) * s))
    g.layers = [_garment("tabard_roundel", roundel, material="cloth", paint_as="trim", spacing=0.0025, tris=600,
                         bone=None)]
    g.paint_as = "secondary"
    g.target_tris = 3600
    return g


def founders_apron(skel: Skeleton, body) -> C.Garment:
    """A bellfounder's apron of doubled hide from the breastbone to the shin, broad enough to stand
    in front of a pour, scorched and studded with the spatter of it, on a neck strap."""
    s = C._s(skel)
    h = skel.props.height
    g = C.skirt(skel, body, hem=0.17, flare=0.25, name="founders_apron", gap=0.016, folds=3)
    front = lambda P: (1.0 - C.sdf_smoothstep(-0.04 * s, 0.02 * s, P[:, 1])) * \
        (1.0 - C.sdf_smoothstep(0.17 * s, 0.2 * s, np.abs(P[:, 0])))  # noqa: E731
    g.scene.intersect(sdf.box([0.0, -0.3 * s, 0.5 * h], np.array([0.21 * s, 0.3 * s, 0.5 * h])))
    chest = float(skel.J["Chest"][2])
    reg = C.region_and(C.band_z(0.5 * h, chest + 0.05 * s, 0.02 * s), front)
    g.scene.union(C.offset_shell(body, reg, 0.012 * s, gap=0.02 * s,
                                 bounds=C.zbox(skel, 0.48 * h, chest + 0.1 * s, xy=0.24, ymin=-0.3, ymax=0.1)),
                  k=0.01 * s)
    neck = float(skel.J["Neck"][2])
    g.scene.union(sdf.tube_path([[0.07 * s, -0.08 * s, chest + 0.04 * s], [0.06 * s, 0.0, neck],
                                 [0.0, 0.08 * s, neck + 0.01 * s], [-0.06 * s, 0.0, neck],
                                 [-0.07 * s, -0.08 * s, chest + 0.04 * s]], 0.009 * s), k=0.01 * s)
    g.material = "leather"
    g.paint_as = "leather"
    g.target_tris = 2600
    return g


def cord_mantle(skel: Skeleton, body) -> C.Garment:
    """A mantle of names: a collar of plaited rush on the shoulders and, hanging from it before and
    behind, the cords of every name taken -- each knotted in its family's weave, lying on the body
    to the waist and below it."""
    s = C._s(skel)
    neck = np.asarray(skel.J["Neck"], float)
    sc = Scene()
    collar_z = float(neck[2]) - 0.035 * s
    ring = [_push_out(body, np.array([math.sin(a) * 0.075 * s, -math.cos(a) * 0.07 * s, collar_z]), 0.03 * s)
            for a in np.linspace(0.0, 2.0 * math.pi, 24, endpoint=False)]
    sc.union(sdf.tube_path(ring, 0.02 * s, density=3, closed=True))
    rng = np.random.default_rng(23)
    n = 46
    for i in range(n):
        a = 2.0 * math.pi * (i + rng.uniform(-0.2, 0.2)) / n
        if abs(math.sin(a)) > 0.72:
            continue                    # nothing hangs over the arms
        end = float(skel.J["Hips"][2]) - rng.uniform(0.0, 0.18) * s
        pts = []
        prev = _push_out(body, np.array([math.sin(a) * 0.08 * s, -math.cos(a) * 0.075 * s, collar_z]), 0.032 * s)
        for z in np.linspace(collar_z - 0.01 * s, end, 10):
            # hanging: straight down from the last point, and out only as far as the body pushes it
            prev = _push_out(body, np.array([prev[0], prev[1], float(z)]), 0.032 * s)
            pts.append(prev)
        sc.union(sdf.tube_path(pts, 0.0085 * s, density=3), k=0.003 * s)
        for k_ in range(2, 10, 2):
            if rng.random() < 0.7:
                sc.union(sdf.sphere(pts[k_], 0.015 * s), k=0.003 * s)
    g = C.Garment("cord_mantle", sc, spacing=0.0035, smooth=2, target_tris=3800, material="cloth")
    g.paint_as = "trim"
    g.covers_head = False
    return g


def bead_ropes(skel: Skeleton, body) -> C.Garment:
    """A barrow-wife's beads, longer than she is tall: chalk beads and pierced flint wound round
    and round her neck and hanging in loops down to her belly, the last of them knots in the string."""
    s = C._s(skel)
    neck = np.asarray(skel.J["Neck"], float)
    sc = Scene()
    for loop, (drop, off) in enumerate(((0.06, 0.028), (0.17, 0.032), (0.28, 0.036), (0.38, 0.04))):
        pts = []
        top = float(neck[2]) - 0.03 * s
        for i in range(40):
            a = 2.0 * math.pi * i / 40
            front = max(0.0, math.cos(a))
            z = top - drop * s * front ** 1.5 - 0.01 * s * (1.0 - front)
            # round the neck, and down the breast as far as each loop drops
            wide = 0.075 + 0.03 * front * min(1.0, drop / 0.15)
            pts.append(_push_out(body, np.array([math.sin(a) * wide * s, -math.cos(a) * 0.072 * s, z]), off * s))
        bead_r = 0.014 * s if loop < 3 else 0.009 * s
        for i, p in enumerate(pts):
            if loop == 3 and i % 2:
                continue
            sc.union(sdf.sphere(p, bead_r * (1.0 if i % 3 else 1.25)))
    g = C.Garment("bead_ropes", sc, spacing=0.003, smooth=2, target_tris=3200, material="horn")
    g.paint_as = "trim"
    g.covers_head = False
    return g


BUILDERS = {
    "kettle_hat": kettle_hat, "miners_hat": miners_hat, "shift_cap": shift_cap, "clerk_hat": clerk_hat,
    "magister_cap": magister_cap, "crude_crown": crude_crown, "antler_band": antler_band, "cord_veil": cord_veil,
    "wimple": wimple, "sou_wester": sou_wester, "reed_hat": reed_hat, "choir_cowl": choir_cowl,
    "tabard": tabard, "founders_apron": founders_apron, "cord_mantle": cord_mantle, "bead_ropes": bead_ropes,
}
