"""The beasts the country fights: wolves, hounds, a boar, the reptiles -- on WM_Quadruped_v1.

Pure numpy SDF, like horse_body.py and deer_body.py. A foe's skeleton is drawn joint by joint
(`QuadSkeleton(props, joints=...)`): a wolf stands on its toes, its paws on the ground, its hock
high behind; the rig's bone names stay the horse's (the "cannon" is the metacarpus, the "pastern"
the toes, the "hoof" the pad and the nails), so the gait generator and every clip work unchanged.

Each beast is built at the size its def's `scale` makes it in the world (the meta says which scale
that is): the game scales the model by the def's scale over that one.

    canid_scene(skel, style)    the dogs: a down wolf, a crag-wolf, a thornhound, a leech-hound
    regions(skel, P, style)     what a point of the body is, for the painter

A fur's silhouette is not a smooth hull: `Displaced` pushes the surface out by a clumped noise
stretched along the lie of the coat, so the ruff and the back read as hair at a distance.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict, field
from typing import Callable, Dict, List, Optional, Tuple

import numpy as np

from . import sdf, paint
from .quadruped import QuadSkeleton, QuadProportions
from . import horse_body as hb

X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])


def _u(v) -> np.ndarray:
    v = np.asarray(v, float)
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-12 else v


def _frame(along: np.ndarray, side: np.ndarray) -> np.ndarray:
    """Columns: `side` squared to `along`, the third axis, `along` (for a rotated ellipsoid)."""
    a = _u(along)
    w = side - a * float(side @ a)
    w = _u(w)
    return np.stack([w, np.cross(a, w), a], axis=1)


class Displaced(sdf.Scene):
    """A scene whose surface is pushed out by `disp(P)` metres (in by a negative value): fur
    clumps, bark plates, scutes. Only the grid points near the base surface are displaced, so it
    costs a thin shell's worth of noise, not the box's."""

    def __init__(self, base: sdf.Scene, disp: Callable[[np.ndarray], np.ndarray], reach: float):
        super().__init__()
        self.base = base
        self.prims = base.prims
        self.disp = disp
        self.reach = float(reach)

    def eval(self, P: np.ndarray) -> np.ndarray:
        d = self.base.eval(P)
        near = np.abs(d) < self.reach * 2.0 + 0.02
        if near.any():
            d = d.copy()
            d[near] = d[near] - self.disp(P[near])
        return d

    def grid(self, spacing: float, margin: float = 0.03, box=None, reach: float = 0.0):
        F, origin, sp = self.base.grid(spacing, margin + self.reach, box=box, reach=reach)
        near = np.abs(F) < self.reach * 2.0 + 2.0 * sp
        idx = np.nonzero(near)
        if len(idx[0]):
            P = origin + np.stack(idx, axis=1) * sp
            F[idx] = F[idx] - self.disp(P)
        return F, origin, sp


# --------------------------------------------------------------------------------------
# The dogs
# --------------------------------------------------------------------------------------

@dataclass
class CanidStyle:
    kind: str = "wolf"
    girth: float = 1.0        # the barrel's width
    depth: float = 1.0        # the chest's depth below the back
    legs: float = 1.0         # the limbs' thickness
    ruff: float = 0.6         # the mane over the neck and the shoulders
    fur: float = 0.008        # how far the coat's clumps stand off the hide, m
    muzzle: float = 1.0       # the muzzle's length
    muzzle_w: float = 1.0     # and its breadth
    ears: float = 1.0
    brush: float = 1.0        # the tail's fullness
    thorns: float = 0.0       # a thornhound's thorns along the spine, the shoulders and the jaw
    bark: float = 0.0         # bark plates over the back and the flanks
    sleek: float = 0.0        # a leech-hound's slick hide: no coat, ringed and wet
    age: float = 0.0          # an old dog: the hips and the shoulder blades standing up through the hide,
                              # the back let down between them, the belly slack, the muzzle gone grey
    torn_ear: float = 0.0     # the left ear's top bitten away (the share of it gone)
    scars: float = 0.0        # healed stab and rake scars along both flanks (how many, and how pale)
    coils: float = 0.0        # briar grown into the hide: thorned stems wound round the barrel, the neck and
                              # the haunches, and trailing off her (the Brake-Dam, who lies in the thorn)
    seed: int = 3

    def to_dict(self) -> dict:
        return asdict(self)


# A down wolf at 0.80 m at the withers: lean, long in the leg, deep and narrow in the chest, the
# head carried at the level of the back. Blender space, metres: faces -Y, left +X, ground z = 0.
WOLF_JOINTS = {
    "Hips": (0.0, 0.29, 0.715), "TailHead": (0.0, 0.47, 0.70),
    "Spine1": (0.0, 0.29, 0.715), "Spine2": (0.0, 0.02, 0.725), "Chest": (0.0, -0.22, 0.735),
    "Neck1": (0.0, -0.38, 0.70), "Neck2": (0.0, -0.50, 0.80), "Head": (0.0, -0.585, 0.885),
    "Muzzle": (0.0, -0.865, 0.805), "Jaw": (0.0, -0.646, 0.79), "Chin": (0.0, -0.813, 0.757),
    "Ear.L": (0.046, -0.6, 0.93), "EarTip.L": (0.07, -0.592, 1.005),
    "Tail1": (0.0, 0.47, 0.70), "Tail2": (0.0, 0.60, 0.635), "Tail3": (0.0, 0.69, 0.525),
    "TailTip": (0.0, 0.745, 0.385),
    "Scapula.L": (0.07, -0.17, 0.725), "Humerus.L": (0.095, -0.355, 0.555),
    "Forearm.L": (0.095, -0.245, 0.405), "FrontCannon.L": (0.085, -0.265, 0.115),
    "FrontPastern.L": (0.085, -0.295, 0.038), "FrontHoof.L": (0.085, -0.335, 0.016),
    "FrontToe.L": (0.085, -0.37, 0.0),
    "Thigh.L": (0.08, 0.355, 0.635), "Gaskin.L": (0.095, 0.235, 0.425),
    "HindCannon.L": (0.085, 0.415, 0.205), "HindPastern.L": (0.085, 0.365, 0.038),
    "HindHoof.L": (0.085, 0.325, 0.016), "HindToe.L": (0.085, 0.29, 0.0),
}
WOLF = QuadProportions(withers=0.80, body_length=0.62, leg_length=1.0, neck_length=0.6, head_size=0.55,
                       bulk=0.5, width=0.6, tail_length=0.6)

# The trunk, breast to rump: (y, top line, under line, half width) for the wolf above. Deepest
# just behind the elbow, tucked up hard at the loin, the croup level with the withers.
WOLF_TRUNK = ((-0.445, 0.615, 0.505, 0.045), (-0.385, 0.715, 0.425, 0.092), (-0.28, 0.785, 0.385, 0.112),
              (-0.14, 0.795, 0.375, 0.122), (0.0, 0.78, 0.41, 0.12), (0.12, 0.765, 0.50, 0.10),
              (0.24, 0.76, 0.545, 0.094), (0.355, 0.765, 0.55, 0.102), (0.455, 0.74, 0.565, 0.09),
              (0.515, 0.695, 0.585, 0.055))


def scaled_joints(base: Dict[str, Tuple[float, float, float]], k: float = 1.0, length: float = 1.0,
                  leg: float = 1.0, head: float = 1.0) -> Dict[str, Tuple[float, float, float]]:
    """A wolf's joints for another dog: `k` scales the whole, `length` the trunk fore and aft,
    `leg` the height of the legs under it (the trunk rides on them), `head` the head about the poll."""
    out = {}
    legs ={"Scapula", "Humerus", "Forearm", "FrontCannon", "FrontPastern", "FrontHoof", "FrontToe",
            "Thigh", "Gaskin", "HindCannon", "HindPastern", "HindHoof", "HindToe"}
    head_parts = {"Muzzle", "Jaw", "Chin", "Ear", "EarTip"}
    top = 0.40   # the elbow's height: below it the leg, above it the trunk
    poll = np.array(base["Head"], float)
    for n, (x, y, z) in base.items():
        b = n[:-2] if n[-2:] in (".L", ".R") else n
        if b in head_parts:
            continue
        if b in legs and z < top:
            zz = z * leg
        else:
            zz = top * leg + (z - top)
        out[n] = (x * k, y * length * k, zz * k)
    p2 = np.array(out["Head"], float)
    for n, (x, y, z) in base.items():
        b = n[:-2] if n[-2:] in (".L", ".R") else n
        if b in head_parts:
            d = (np.array([x, y, z]) - poll) * head
            out[n] = (p2[0] + d[0] * k, p2[1] + d[1] * k, p2[2] + d[2] * k)
    return out


def scaled_trunk(trunk, k: float = 1.0, length: float = 1.0, leg: float = 1.0, depth: float = 1.0,
                 girth: float = 1.0):
    top = 0.40
    out = []
    for y, t, b, w in trunk:
        tt = top * leg + (t - top)
        bb = top * leg + (b - top)
        # the depth below the top line
        bb = tt - (tt - bb) * depth
        out.append((y * length * k, tt * k, bb * k, w * girth * k))
    return tuple(out)


def _s(skel: QuadSkeleton) -> float:
    """The dog's size against the down wolf's 0.80 m."""
    return skel.props.withers / 0.80


def canid_scene(skel: QuadSkeleton, st: CanidStyle, trunk=WOLF_TRUNK) -> sdf.Scene:
    J = skel.J
    s = _s(skel)
    b = st.legs
    sc = sdf.Scene()
    sc.union(hb.section_loft(trunk))
    # the breast: the prosternum standing a little proud between the shoulders
    sc.union(sdf.ellipsoid(np.array([0.0, J["Humerus.L"][1] - 0.025 * s, J["Humerus.L"][2] - 0.035 * s]),
                           np.array([0.07 * st.girth, 0.07, 0.10]) * s), k=0.05 * s)
    _neck(sc, skel, st)
    _head(sc, skel, st)
    for side, sx in (("L", 1.0), ("R", -1.0)):
        _foreleg(sc, skel, st, side, sx)
        _hindleg(sc, skel, st, side, sx)
    _tail(sc, skel, st)
    if st.age > 0:
        _old_bones(sc, skel, st)
    if st.thorns > 0:
        _thorns(sc, skel, st)
    if st.coils > 0:
        _coils(sc, skel, st)
    # nothing below the ground
    sc.intersect(sdf.plane(np.array([0.0, 0.0, 0.0]), np.array([0.0, 0.0, -1.0])))
    return _coat(sc, skel, st)


def _old_bones(sc: sdf.Scene, skel: QuadSkeleton, st: CanidStyle) -> None:
    """An old dog's frame showing through: the points of the hips and the tops of the shoulder
    blades standing up out of the back line, the spine's knuckles over the loin, and the back let
    down between withers and croup."""
    J = skel.J
    s = _s(skel)
    a = st.age
    top = lambda y: np.interp(y, [J["Chest"][1], J["Spine1"][1], J["Hips"][1]],  # noqa: E731
                              [J["Chest"][2], J["Spine1"][2], J["Hips"][2]])
    # the sway: the middle of the back let down
    mid = 0.5 * (J["Chest"] + J["Spine1"])
    sc.subtract(sdf.ellipsoid(mid + np.array([0.0, 0.0, 0.085 + 0.012 * a]) * s, np.array([0.16, 0.20, 0.05]) * s),
                k=0.05 * s)
    for sx in (1.0, -1.0):
        hip = np.array([sx * 0.062 * s, J["Thigh.L"][1] - 0.075 * s, top(J["Thigh.L"][1] - 0.075 * s) + 0.035 * s])
        sc.union(sdf.ellipsoid(hip, np.array([0.03, 0.04, 0.026]) * s * (0.8 + 0.3 * a)), k=0.03 * s)
        blade = np.array([sx * 0.05 * s, J["Scapula.L"][1] + 0.01 * s, J["Scapula.L"][2] + 0.03 * s])
        sc.union(sdf.ellipsoid(blade, np.array([0.022, 0.05, 0.022]) * s * (0.8 + 0.3 * a)), k=0.025 * s)
    for i in range(6):
        y = J["Spine1"][1] + (J["Hips"][1] - J["Spine1"][1]) * (i / 5.0) * 0.9 - 0.06 * s
        sc.union(sdf.sphere(np.array([0.0, y, top(y) + 0.028 * s]), 0.014 * s * a), k=0.018 * s)


def scars(skel: QuadSkeleton, st: CanidStyle, P: np.ndarray) -> np.ndarray:
    """0..1: the healed scars along both flanks -- short stabs (a heron's bill) and long rakes --
    hairless and pale; deterministic from the seed."""
    if st.scars <= 0:
        return np.zeros(len(P))
    J = skel.J
    s = _s(skel)
    rng = np.random.default_rng(st.seed + 101)
    y0, y1 = J["Chest"][1] + 0.04 * s, J["Thigh.L"][1] - 0.02 * s
    z0, z1 = J["Forearm.L"][2] + 0.04 * s, J["Spine1"][2] - 0.02 * s
    out = np.zeros(len(P))
    n = int(round(7 * st.scars))
    for sx in (1.0, -1.0):
        side = sm(0.0, 0.03 * s, P[:, 0] * sx)
        for i in range(n):
            c = np.array([rng.uniform(y0, y1), rng.uniform(z0, z1)])
            ang = rng.uniform(-0.9, 0.9) + (math.pi * 0.5 if rng.random() < 0.3 else 0.0)
            ln = (rng.uniform(0.08, 0.16) if i % 3 == 0 else rng.uniform(0.02, 0.05)) * s
            w = (0.006 if ln > 0.06 * s else 0.008) * s
            d = np.array([math.cos(ang), math.sin(ang)])
            q = np.stack([P[:, 1], P[:, 2]], axis=1) - c
            t = np.clip(q @ d, -ln * 0.5, ln * 0.5)
            dist = np.linalg.norm(q - t[:, None] * d[None, :], axis=1)
            # thinning to the ends
            taper = 1.0 - (np.abs(t) / (ln * 0.5)) ** 2 * 0.6
            out = np.maximum(out, side * (1.0 - sm(w * taper * 0.6, w * taper, dist)))
    return np.clip(out, 0.0, 1.0)


def _neck(sc: sdf.Scene, skel: QuadSkeleton, st: CanidStyle) -> None:
    J = skel.J
    s = _s(skel)
    n1, n2, hd = J["Neck1"], J["Neck2"], J["Head"]
    # from the withers and the breast up to behind the ears: deep below, where the throat runs into
    # the chest, and thick on top under the ruff
    stations = [(n1 + np.array([0.0, 0.10, -0.02]) * s, 0.10 * s * st.girth, 0.15 * s),
                (n1 + np.array([0.0, -0.01, 0.01]) * s, 0.085 * s * st.girth, 0.12 * s),
                (n2 + np.array([0.0, 0.0, -0.01]) * s, 0.068 * s, 0.092 * s),
                (hd + np.array([0.0, 0.05, -0.065]) * s, 0.046 * s, 0.052 * s)]
    sc.union(sdf.sweep(stations, X, axis=None), k=0.05 * s)
    if st.ruff > 0:
        r = st.ruff
        # the ruff: a collar of long hair from behind the ears over the shoulders and down the throat
        stations = [(J["Chest"] + np.array([0.0, -0.02, 0.0]) * s, 0.10 * s * r + 0.04 * s, 0.06 * s * r + 0.03 * s),
                    (n1 + np.array([0.0, 0.02, 0.06]) * s, 0.10 * s, 0.07 * s + 0.03 * s * r),
                    (n2 + np.array([0.0, 0.03, 0.0]) * s, 0.07 * s + 0.022 * s * r, 0.08 * s + 0.018 * s * r)]
        sc.union(sdf.sweep(stations, X), k=0.04 * s)
        # and the throat's beard
        th = [(n1 + np.array([0.0, -0.06, -0.10]) * s, 0.07 * s, 0.05 * s),
              (n2 + np.array([0.0, -0.03, -0.09]) * s, 0.06 * s, 0.05 * s * r + 0.02 * s),
              (J["Jaw"] + np.array([0.0, 0.0, -0.06]) * s, 0.045 * s, 0.03 * s)]
        sc.union(sdf.sweep(th, X), k=0.04 * s)


def head_axes(skel: QuadSkeleton):
    """(poll, the head's line toward the nose, square to it toward the jaw, its length)."""
    J = skel.J
    poll, muz = J["Head"], J["Muzzle"]
    hd = muz - poll
    hl = float(np.linalg.norm(hd))
    hu = hd / hl
    dn = _u(np.cross(hu, X))
    if dn[2] > 0:
        dn = -dn
    return poll, hu, dn, hl


def H(skel: QuadSkeleton, along: float, down: float, side: float = 0.0) -> np.ndarray:
    """A point of the head, in the down wolf's metres scaled to this dog's head: `along` the line
    from the poll toward the nose, `down` square to it toward the throat, `side` to the left."""
    poll, hu, dn, hl = head_axes(skel)
    k = hl / 0.29
    m = getattr(skel, "muzzle", 1.0)
    if along > 0.12:
        along = 0.12 + (along - 0.12) * m
    return poll + (hu * along + dn * down + X * side) * k


def head_k(skel: QuadSkeleton) -> float:
    return head_axes(skel)[3] / 0.29


def mouth_line(skel: QuadSkeleton, st: CanidStyle):
    """The corner of the mouth and the tip of the lips: the cut between the jaws."""
    return H(skel, 0.118, 0.056), H(skel, 0.283, 0.034)


def _head(sc: sdf.Scene, skel: QuadSkeleton, st: CanidStyle) -> None:
    """A dog's head: a broad skull behind the eyes, the cheeks, a stop, and the muzzle running long
    and straight to a black nose; the lower jaw is its own piece under the mouth's line, so it can
    open; the fangs over it; pointed ears standing up and out, cupped forward."""
    poll, hu, dn, hl = head_axes(skel)
    k = head_k(skel)
    rot = _frame(hu, X)
    mw = st.muzzle_w

    def h(a, d, x=0.0):
        return H(skel, a, d, x)
    # the skull, broad behind the eyes, and the crest of the occiput
    sc.union(sdf.ellipsoid(h(0.06, 0.02), np.array([0.062, 0.062, 0.07]) * k, rot=rot), k=0.03 * k)
    # the cheeks: the jaw's muscle under and behind the eye
    for sx in (1.0, -1.0):
        sc.union(sdf.ellipsoid(h(0.095, 0.056, sx * 0.034), np.array([0.026, 0.034, 0.042]) * k, rot=rot), k=0.025 * k)
    # the brow over the eyes, and the stop falling from it to the muzzle
    sc.union(sdf.ellipsoid(h(0.135, 0.012), np.array([0.046, 0.026, 0.036]) * k, rot=rot), k=0.03 * k)
    # the muzzle: the upper jaw, boxy, its underside the mouth's line
    sc.union(sdf.elliptic_cone(h(0.125, 0.026), h(0.272, 0.012), 0.043 * k * mw, 0.036 * k, 0.027 * k * mw, 0.025 * k, X,
                               squash_v_neg=0.2), k=0.025 * k)
    # the nose
    sc.union(sdf.ellipsoid(h(0.284, 0.006), np.array([0.019 * mw, 0.017, 0.016]) * k, rot=rot), k=0.008 * k)
    # the lower jaw: from the hinge under the cheek to the chin
    sc.union(sdf.elliptic_cone(h(0.10, 0.072), h(0.262, 0.05), 0.033 * k * mw, 0.026 * k, 0.018 * k * mw, 0.015 * k, X),
             k=0.02 * k)
    # the mouth: a cut from the corner to the lips' tip, so the jaws part
    corner, tip = mouth_line(skel, st)
    along = tip - corner
    L = float(np.linalg.norm(along))
    cut = sdf.box(0.5 * (corner + tip) + _u(along) * 0.02 * k,
                  np.array([0.06 * k * mw, 0.0032 * k, L * 0.5 + 0.02 * k]), rot=_frame(along, X))
    sc.subtract(cut, k=0.002 * k)
    # the fangs: the upper canines over the lower lip, the lower inside them
    for sx in (1.0, -1.0):
        u0 = h(0.262, 0.03, sx * 0.016 * mw)
        sc.union(sdf.round_cone(u0, u0 + dn * 0.02 * k + hu * 0.002 * k, 0.0045 * k, 0.0012 * k), k=0.002 * k)
        l0 = h(0.255, 0.045, sx * 0.013 * mw)
        sc.union(sdf.round_cone(l0, l0 - dn * 0.016 * k, 0.0038 * k, 0.001 * k), k=0.002 * k)
    # the throat under the jaw's angle, into the neck
    sc.union(sdf.ellipsoid(h(0.06, 0.085), np.array([0.042, 0.05, 0.04]) * k, rot=rot), k=0.03 * k)
    # the eyes, set obliquely under the brow: a socket and the ball in it
    for sx in (1.0, -1.0):
        sc.subtract(sdf.sphere(h(0.122, 0.024, sx * 0.043), 0.012 * k), k=0.006 * k)
        sc.union(sdf.sphere(h(0.122, 0.024, sx * 0.033), 0.0115 * k), k=0.003 * k)
    # the ears: broad-based triangles, standing up and a little out, cupped on their fronts
    J = skel.J
    for side, sx in (("L", 1.0), ("R", -1.0)):
        e0, e1 = J[f"Ear.{side}"], J[f"EarTip.{side}"]
        e1 = e0 + (e1 - e0) * st.ears
        full = e1.copy()
        up = _u(e1 - e0)
        wide = _u(np.cross(up, -hu))
        base = e0 - up * 0.02 * k
        sc.union(sdf.elliptic_cone(base, e1, 0.046 * k * st.ears, 0.013 * k, 0.005 * k, 0.003 * k, wide), k=0.012 * k)
        front = _u(np.cross(wide, up))
        if float(front @ hu) < 0:
            front = -front
        sc.subtract(sdf.elliptic_cone(base + up * 0.03 * k + front * 0.009 * k, e1 - up * 0.014 * k + front * 0.004 * k,
                                      0.032 * k * st.ears, 0.006 * k, 0.003 * k, 0.002 * k, wide), k=0.003 * k)
        if side == "L" and st.torn_ear > 0:
            # bitten: the top of the ear gone in a ragged bite, a nick out of its back edge below
            L = float(np.linalg.norm(full - e0))
            bite = e0 + up * L * (1.0 - st.torn_ear * 0.55) + wide * 0.012 * k
            sc.subtract(sdf.sphere(bite + up * 0.03 * k, 0.036 * k), k=0.003 * k)
            sc.subtract(sdf.sphere(bite - wide * 0.03 * k - up * 0.006 * k, 0.014 * k), k=0.002 * k)
            nick = e0 + up * L * 0.42 - wide * 0.034 * k * st.ears
            sc.subtract(sdf.sphere(nick, 0.009 * k), k=0.002 * k)


def _foreleg(sc: sdf.Scene, skel: QuadSkeleton, st: CanidStyle, side: str, sx: float) -> None:
    J = skel.J
    s = _s(skel)
    b = st.legs
    sca, sho, elb, wri, kn, pad, toe = (J[f"Scapula.{side}"], J[f"Humerus.{side}"], J[f"Forearm.{side}"],
                                       J[f"FrontCannon.{side}"], J[f"FrontPastern.{side}"],
                                       J[f"FrontHoof.{side}"], J[f"FrontToe.{side}"])
    # the shoulder blade under the skin, and the upper arm's muscle to the elbow
    sc.union(sdf.elliptic_cone(sca + np.array([0.0, 0.0, -0.02]) * s, sho + np.array([sx * 0.0, 0.01, 0.0]) * s,
                               0.035 * s, 0.075 * s, 0.045 * s, 0.07 * s, X), k=0.05 * s)
    sc.union(sdf.elliptic_cone(sho, elb + np.array([0.0, 0.015, 0.01]) * s, 0.048 * s * b, 0.06 * s * b,
                               0.04 * s * b, 0.048 * s * b, X), k=0.04 * s)
    # the forearm, lean and straight, the wrist's pad behind
    sc.union(sdf.elliptic_cone(elb + np.array([0.0, 0.004, -0.01]) * s, wri, 0.044 * s * b, 0.054 * s * b,
                               0.026 * s * b, 0.029 * s * b, X), k=0.03 * s)
    sc.union(sdf.ellipsoid(wri + np.array([0.0, 0.006, 0.0]) * s, np.array([0.028, 0.03, 0.028]) * s * b), k=0.012 * s)
    # the metacarpus and the paw
    sc.union(sdf.round_cone(wri, kn + np.array([0.0, 0.0, 0.006]) * s, 0.025 * s * b, 0.025 * s * b), k=0.012 * s)
    _paw(sc, skel, kn, pad, toe, sx, 1.0 * b)


def _hindleg(sc: sdf.Scene, skel: QuadSkeleton, st: CanidStyle, side: str, sx: float) -> None:
    J = skel.J
    s = _s(skel)
    b = st.legs
    hip, sti, hoc, kn, pad, toe = (J[f"Thigh.{side}"], J[f"Gaskin.{side}"], J[f"HindCannon.{side}"],
                                   J[f"HindPastern.{side}"], J[f"HindHoof.{side}"], J[f"HindToe.{side}"])
    # the thigh: the big muscle from the croup to the stifle, broad seen from the side
    top = hip + np.array([0.0, 0.03, 0.05]) * s
    sc.union(sdf.elliptic_cone(top - X * sx * 0.012 * s, sti + np.array([-sx * 0.002, 0.035, 0.0]) * s, 0.05 * s * b,
                               0.12 * s * b, 0.042 * s * b, 0.068 * s * b, X), k=0.075 * s)
    # the second thigh, behind the shin, down to the hock
    sc.union(sdf.elliptic_cone(sti + np.array([0.0, 0.02, 0.0]) * s, hoc + np.array([0.0, -0.005, 0.02]) * s,
                               0.046 * s * b, 0.066 * s * b, 0.025 * s * b, 0.036 * s * b, X), k=0.035 * s)
    # the hock's point
    sc.union(sdf.round_cone(hoc, hoc + np.array([0.0, 0.03, 0.012]) * s, 0.022 * s * b, 0.016 * s * b), k=0.012 * s)
    # the metatarsus and the paw
    sc.union(sdf.round_cone(hoc, kn + np.array([0.0, 0.0, 0.006]) * s, 0.024 * s * b, 0.024 * s * b), k=0.012 * s)
    _paw(sc, skel, kn, pad, toe, sx, 0.94 * b)


def _paw(sc: sdf.Scene, skel: QuadSkeleton, kn, pad, toe, sx: float, b: float) -> None:
    """A dog's paw: an oval pad flat on the ground, four toes ahead of it, the nails' points."""
    s = _s(skel)
    c = 0.5 * (kn + toe)
    c = np.array([c[0], c[1], 0.022 * s])
    sc.union(sdf.ellipsoid(c, np.array([0.033, 0.042, 0.024]) * s * b), k=0.014 * s)
    fwd = _u(np.array([0.0, toe[1] - kn[1], 0.0]))
    for i, dx in enumerate((-1.5, -0.5, 0.5, 1.5)):
        p = np.array([kn[0] + dx * 0.0155 * s * b, toe[1] - fwd[1] * 0.012 * s * (1.0 if abs(dx) < 1 else 1.8), 0.017 * s])
        sc.union(sdf.ellipsoid(p, np.array([0.011, 0.015, 0.016]) * s * b), k=0.008 * s)
        # the nail
        sc.union(sdf.round_cone(p + fwd * 0.008 * s + Z * 0.002 * s, p + fwd * 0.022 * s - Z * 0.012 * s,
                                0.004 * s, 0.0015 * s), k=0.003 * s)


def _tail(sc: sdf.Scene, skel: QuadSkeleton, st: CanidStyle) -> None:
    J = skel.J
    s = _s(skel)
    pts = [J["Tail1"] - np.array([0.0, 0.03, 0.0]) * s, J["Tail2"], J["Tail3"], J["TailTip"]]
    r = st.brush
    radii = [0.035 * s, (0.035 + 0.025 * r) * s, (0.03 + 0.032 * r) * s, (0.018 + 0.01 * r) * s]
    sc.union(sdf.tube_path(pts, radii), k=0.035 * s)


def _thorns(sc: sdf.Scene, skel: QuadSkeleton, st: CanidStyle) -> None:
    """A thornhound's thorns: hooked spines along the back's ridge, over the shoulders, down the
    tail and along the jaw's line, each leaning back the way the coat lies."""
    J = skel.J
    s = _s(skel)
    rng = np.random.default_rng(st.seed + 101)
    k = st.thorns
    spine = [J["Head"] + np.array([0.0, 0.03, 0.055]) * s, J["Neck2"] + np.array([0.0, 0.0, 0.09]) * s,
             J["Neck1"] + np.array([0.0, 0.02, 0.12]) * s, J["Chest"] + np.array([0.0, 0.0, 0.065]) * s,
             J["Spine2"] + np.array([0.0, 0.0, 0.05]) * s, J["Spine1"] + np.array([0.0, 0.0, 0.05]) * s,
             J["Tail1"] + np.array([0.0, 0.0, 0.035]) * s, J["Tail2"] + np.array([0.0, 0.0, 0.05]) * s]
    pts = np.array(spine)
    # a clear rhythm: a row of big hooked thorns down the ridge, each with a smaller pair flanking
    # it a little behind, largest over the withers and the croup
    n_big = 11
    tt = np.linspace(0.15, len(pts) - 1.0, n_big)
    line = sdf._catmull_rom(pts, tt)
    nxt = sdf._catmull_rom(pts, np.minimum(tt + 0.2, len(pts) - 1.0))
    for i, p in enumerate(line):
        f = i / (n_big - 1)
        size = (0.075 + 0.035 * math.sin(math.pi * f) ** 0.6) * s * k * (0.9 + 0.2 * rng.random())
        back = _u(nxt[i] - p) if np.linalg.norm(nxt[i] - p) > 1e-6 else Y
        _hook(sc, p - Z * 0.012 * s, Z, back, size, 0.016 * s * k, s)
        for sx in (1.0, -1.0):
            q = p + back * 0.035 * s + X * sx * 0.045 * s - Z * 0.02 * s
            _hook(sc, q, _u(Z + X * sx * 0.8), back, size * 0.55, 0.011 * s * k, s)
    # the jaw's thorns: short and forward-raked under the chin and along the lower jaw
    corner, tip = mouth_line(skel, st)
    poll, hu, dn, hl = head_axes(skel)
    for f in (0.15, 0.35, 0.55, 0.75):
        for sx in (1.0, -1.0):
            base = corner + (tip - corner) * f + dn * 0.03 * s + X * sx * 0.022 * s
            tip2 = base + _u(dn * 0.8 + X * sx * 0.6 - hu * 0.2) * 0.028 * s * k
            sc.union(sdf.round_cone(base, tip2, 0.006 * s * k, 0.001 * s), k=0.004 * s)
    # the shoulders and the haunches: a few heavy thorns standing out of the bark
    for side, sx in (("L", 1.0), ("R", -1.0)):
        for anchor, d in ((J[f"Scapula.{side}"], np.array([sx * 0.06, 0.02, -0.02])),
                          (J[f"Thigh.{side}"], np.array([sx * 0.08, -0.01, 0.02])),
                          (J[f"Humerus.{side}"], np.array([sx * 0.05, 0.03, -0.04]))):
            base = anchor + d * s
            _hook(sc, base, _u(np.array([sx * 0.9, 0.0, 0.5])), Y, 0.075 * s * k, 0.016 * s * k, s)


def _coils(sc: sdf.Scene, skel: QuadSkeleton, st: CanidStyle) -> None:
    """The briar grown into her: thorned stems wound round the barrel from the withers to the croup,
    a turn round the neck and one round each haunch, lying on the hide (each laid where the body so
    far is, pushed out until it stands on it) with hooked thorns along them, and two loose ends of it
    trailing off her flanks to the ground."""
    J = skel.J
    s = _s(skel)
    k = st.coils
    rng = np.random.default_rng(st.seed + 211)
    body = sc.near(0.12 * s)

    def lay(p, off):
        p = np.asarray(p, float).copy()
        for _ in range(30):
            d = float(body.eval(p[None])[0])
            if d >= off - 1e-4:
                break
            e = 0.003 * s
            g = np.array([float(body.eval((p + v)[None])[0]) - float(body.eval((p - v)[None])[0])
                          for v in (X * e, Y * e, Z * e)])
            n = np.linalg.norm(g)
            if n < 1e-9:
                break
            p = p + g / n * min(off - d + 1e-4, 0.03 * s)
        return p

    def helix(a, b, radius, turns, phase, n=40):
        out = []
        ax = _u(b - a)
        u = _u(np.cross(ax, X)) if abs(ax @ X) < 0.9 else _u(np.cross(ax, Z))
        v = np.cross(ax, u)
        for i in range(n + 1):
            f = i / n
            t = phase + 2.0 * math.pi * turns * f
            c = a + (b - a) * f
            out.append(c + (u * math.cos(t) + v * math.sin(t)) * radius)
        return out

    stems = []
    # round the barrel, withers to croup, two stems crossing
    for ph in (0.0, 2.6):
        stems.append(helix(J["Chest"] - Y * 0.06 * s, J["Spine1"] + Y * 0.04 * s, 0.05 * s, 2.2 * k, ph))
    # round the neck, and round each haunch
    stems.append(helix(J["Neck1"], J["Neck2"], 0.03 * s, 1.3, 0.8, n=24))
    for side, sx in (("L", 1.0), ("R", -1.0)):
        stems.append(helix(J[f"Thigh.{side}"] + X * sx * 0.02 * s, J[f"Gaskin.{side}"], 0.03 * s, 1.1, 1.7 * sx, n=20))
    r = 0.016 * s * min(1.4, 0.8 + 0.4 * k)
    for stem in stems:
        laid = [lay(p, r * 1.1) for p in stem]
        sc.union(sdf.tube_path(laid, r, density=3), k=0.008 * s)
        for i in range(2, len(laid) - 1, 3):
            p = laid[i]
            out = _u(p - (J["Spine2"] if p[1] > J["Neck1"][1] else J["Neck2"]))
            along = _u(laid[i + 1] - laid[i - 1])
            _hook(sc, p, _u(out + Z * 0.3), along, (0.035 + 0.02 * rng.random()) * s * k, 0.007 * s * k, s)
    # two loose ends, off the flanks and down to the ground, where she was lying in it
    for sx, at in ((1.0, J["Spine2"]), (-1.0, J["Spine1"])):
        top = lay(at + X * sx * 0.12 * s - Z * 0.08 * s, r)
        pts = [top, top + np.array([sx * 0.10, 0.04, -0.18]) * s, top + np.array([sx * 0.2, 0.12, -0.42]) * s,
               np.array([top[0] + sx * 0.32 * s, top[1] + 0.22 * s, 0.03 * s])]
        sc.union(sdf.tube_path(pts, [r, r * 0.9, r * 0.8, r * 0.6], density=3), k=0.01 * s)
        for i in range(1, 3):
            _hook(sc, pts[i], _u(np.array([sx, 0.0, 0.4])), _u(pts[i + 1] - pts[i]), 0.04 * s * k, 0.007 * s * k, s)


def _hook(sc: sdf.Scene, base, out, back, size: float, r: float, s: float) -> None:
    """A thorn: thick at its root, rising along `out` and hooking back along `back` to its point."""
    out = _u(out)
    back = _u(back - out * float(np.dot(back, out)))
    pts = [base, base + out * size * 0.45 + back * size * 0.08, base + out * size * 0.8 + back * size * 0.3,
           base + out * size * 0.95 + back * size * 0.62]
    sc.union(sdf.tube_path(pts, [r, r * 0.6, r * 0.32, 0.0015 * s]), k=0.01 * s)


def _coat(sc: sdf.Scene, skel: QuadSkeleton, st: CanidStyle) -> sdf.Scene:
    """The coat's clumps and the bark's plates on the hull; a sleek hide stays as it is."""
    if st.fur <= 0 and st.bark <= 0:
        return sc
    s = _s(skel)
    n1 = paint.Noise(st.seed + 7, 64)
    n2 = paint.Noise(st.seed + 19, 64)
    amp = max(st.fur, st.bark * 0.012) * s

    def disp(P):
        R = regions(skel, P, st, fine=False)
        # the lie of the coat: clumps long along the body, short across it
        Q = P * np.array([1.0, 0.38, 0.8])
        clump = n1.fbm(Q, freq=34.0 / s, octaves=2)
        long_hair = np.clip(0.35 + 0.9 * R["ruff"] + 0.6 * R["back"] + 0.9 * R["tail"] + 0.5 * R["breeches"], 0, 1.6)
        short = 1.0 - np.clip(R["face"] + R["legs"] + R["paw"] + R["ear"], 0, 1)
        out = st.fur * s * (clump - 0.45) * 2.0 * long_hair * short
        if st.bark > 0:
            # plates: the cells of a stretched lattice, raised in their middles, split at their edges
            F = _cells(P * np.array([1.0, 0.6, 1.0]), 15.0 / s, st.seed)
            plate = 1.0 - paint.smoothstep(0.45, 0.72, F)
            barky = np.clip(R["back"] + R["flank"] + 0.6 * R["tail"] + 0.5 * R["legs_upper"], 0, 1) * (1.0 - R["face"])
            out = out * (1.0 - 0.7 * barky) + st.bark * 0.014 * s * (plate - 0.4) * barky
            out = out + 0.002 * s * (n2.at(P, 90.0 / s) - 0.5) * barky
        return out
    return Displaced(sc, disp, amp * 1.6 + 0.004 * s)


def _cells(P: np.ndarray, freq: float, seed: int) -> np.ndarray:
    """Worley F1 of a jittered lattice (as horse_forge.cells), for plates and scutes."""
    rng = np.random.default_rng(seed)
    Jt = rng.random((32, 32, 32, 3))
    Q = P * freq
    base = np.floor(Q).astype(np.int64)
    best = np.full(len(P), 9.0)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                c = base + np.array([dx, dy, dz])
                j = Jt[c[:, 0] % 32, c[:, 1] % 32, c[:, 2] % 32]
                d = np.linalg.norm(Q - (c + 0.15 + 0.7 * j), axis=1)
                np.minimum(best, d, out=best)
    return best


# --------------------------------------------------------------------------------------
# The painter's map
# --------------------------------------------------------------------------------------

def sm(e0, e1, x) -> np.ndarray:
    """smoothstep whose edges may be arrays (a line that follows the back)."""
    e0 = np.asarray(e0, float)
    e1 = np.asarray(e1, float)
    t = np.clip((np.asarray(x, float) - e0) / np.maximum(e1 - e0, 1e-9), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _seg(P: np.ndarray, a, b) -> Tuple[np.ndarray, np.ndarray]:
    """(distance to the segment a-b, the parameter along it 0..1)."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ab = b - a
    u = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(P - (a + u[:, None] * ab), axis=1), u


def eye_centres(skel: QuadSkeleton, st=None) -> List[np.ndarray]:
    J = skel.J
    s = _s(skel)
    poll, hu, dn, hl = head_axes(skel)
    return [H(skel, 0.122, 0.024, sx * 0.037) for sx in (1.0, -1.0)]


def regions(skel: QuadSkeleton, P: np.ndarray, st: CanidStyle, fine: bool = True) -> Dict[str, np.ndarray]:
    """Soft masks over points at rest: back (the saddle), flank, belly (and the pale underside),
    ruff, breeches (the hind legs' long hair), tail, tail_tip, face, muzzle, nose, lips, mouth
    (inside the cut), teeth, eye, ear, ear_in, legs, legs_upper, paw, nail, thorn (and bark)."""
    J = skel.J
    s = _s(skel)
    n = len(P)
    R: Dict[str, np.ndarray] = {}
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    line_y = [J["Head"][1] - 0.02 * s, J["Neck2"][1], J["Neck1"][1], J["Chest"][1], J["Spine1"][1], J["Tail1"][1] + 0.04 * s]
    line_z = [J["Head"][2] + 0.05 * s, J["Neck2"][2] + 0.075 * s, J["Neck1"][2] + 0.11 * s, J["Chest"][2] + 0.04 * s,
              J["Spine1"][2] + 0.04 * s, J["Tail1"][2] + 0.0 * s]
    spine_z = np.interp(y, line_y, line_z)
    elbow = J["Forearm.L"][2]
    trunk_y = sm(J["Neck1"][1] - 0.04 * s, J["Neck1"][1] + 0.02 * s, y) * (1.0 - sm(J["Tail1"][1], J["Tail1"][1] + 0.06 * s, y))
    along_y = sm(J["Head"][1] - 0.04 * s, J["Head"][1] + 0.04 * s, y) * (1.0 - sm(J["Tail1"][1], J["Tail1"][1] + 0.06 * s, y))
    R["back"] = sm(spine_z - 0.14 * s, spine_z - 0.025 * s, z) * along_y
    R["belly"] = (1.0 - sm(elbow - 0.02 * s, elbow + 0.12 * s, z)) * (1.0 - sm(0.07 * s, 0.11 * s, np.abs(x))) \
        * trunk_y * sm(0.0, 0.1, z - 0.3 * s)
    R["flank"] = trunk_y * sm(elbow, elbow + 0.1 * s, z) * (1.0 - R["back"])
    d_tail, u_tail = _seg(P, J["Tail1"], J["TailTip"])
    R["tail"] = (1.0 - sm(0.06 * s, 0.10 * s, d_tail)) * sm(J["Tail1"][1] - 0.02 * s, J["Tail1"][1] + 0.03 * s, y)
    R["tail_tip"] = R["tail"] * sm(0.72, 0.9, u_tail)
    poll, hu, dn, hl = head_axes(skel)
    rel = P - poll
    along = rel @ hu
    R["face"] = sm(-0.02 * s, 0.03 * s, along) * (1.0 - sm(0.10 * s, 0.14 * s, np.linalg.norm(rel - np.outer(along, hu), axis=1)))
    R["face"] = np.clip(R["face"] * (1.0 - sm(0.0, 0.02 * s, (y - poll[1]) - 0.03 * s)), 0, 1)
    R["back"] = R["back"] * (1.0 - 0.7 * R["face"])
    R["muzzle"] = R["face"] * sm(0.36 * hl, 0.48 * hl, along)
    R["nose"] = 1.0 - sm(0.017 * s, 0.026 * s, np.linalg.norm(P - (J["Muzzle"] - hu * 0.004 * s + dn * 0.004 * s), axis=1))
    corner, tip = mouth_line(skel, st)
    d_m, u_m = _seg(P, corner, tip)
    R["lips"] = (1.0 - sm(0.006 * s, 0.012 * s, d_m)) * R["face"]
    R["mouth"] = (1.0 - sm(0.002 * s, 0.006 * s, d_m)) * R["face"]
    # the teeth: along the lips' edge forward of the corner, and the fangs
    R["teeth"] = np.zeros(n)
    for sx in (1.0, -1.0):
        base = tip - _u(tip - corner) * 0.03 * s + X * sx * 0.016 * s * st.muzzle_w
        R["teeth"] = np.maximum(R["teeth"], 1.0 - sm(0.006 * s, 0.012 * s, np.linalg.norm(P - base, axis=1)))
    R["teeth"] = np.maximum(R["teeth"], R["mouth"] * sm(0.8, 0.9, u_m) * 0.8)
    eyes = eye_centres(skel, st)
    de = np.minimum(np.linalg.norm(P - eyes[0], axis=1), np.linalg.norm(P - eyes[1], axis=1))
    R["eye"] = 1.0 - sm(0.010 * s, 0.014 * s, de)
    R["eye_ring"] = (1.0 - sm(0.014 * s, 0.022 * s, de)) * (1.0 - R["eye"])
    R["ear"] = np.zeros(n)
    R["ear_in"] = np.zeros(n)
    for side, sx in (("L", 1.0), ("R", -1.0)):
        e0, e1 = J[f"Ear.{side}"], J[f"EarTip.{side}"]
        torn = st.torn_ear * 0.55 if side == "L" else 0.0
        d_e, u_e = _seg(P, e0 - (e1 - e0) * 0.1, e0 + (e1 - e0) * st.ears * (1.0 - torn))
        ear = (1.0 - sm(0.03 * s, 0.045 * s, d_e)) * sm(0.05, 0.2, u_e)
        R["ear"] = np.maximum(R["ear"], ear)
        front = -((P - e0) @ hu)
        R["ear_in"] = np.maximum(R["ear_in"], ear * sm(-0.004 * s, 0.006 * s, -front) * (1.0 - sm(0.75, 0.95, u_e)))
    # the legs, below the elbow and the stifle
    knee_z = J["FrontCannon.L"][2]
    R["legs"] = (1.0 - sm(elbow - 0.06 * s, elbow + 0.02 * s, z)) * (1.0 - trunk_y * sm(0.0, 0.05 * s, z - (elbow - 0.06 * s)))
    R["legs"] = np.clip(R["legs"] + (1.0 - sm(knee_z * 1.3, knee_z * 1.8, z)), 0, 1)
    R["legs_upper"] = sm(elbow - 0.05 * s, elbow + 0.04 * s, z) * (1.0 - sm(elbow + 0.1 * s, elbow + 0.22 * s, z)) \
        * sm(0.06 * s, 0.10 * s, np.abs(x))
    R["paw"] = 1.0 - sm(0.035 * s, 0.05 * s, z)
    R["nail"] = np.zeros(n)
    for f in ("Front", "Hind"):
        for side in ("L", "R"):
            toe = J[f"{f}Toe.{side}"]
            R["nail"] = np.maximum(R["nail"], (1.0 - sm(0.012 * s, 0.02 * s, np.abs(y - (toe[1] + (0.004 if f == "Hind" else 0.0) * s))))
                                   * (1.0 - sm(0.012 * s, 0.02 * s, z)) * (1.0 - sm(0.035 * s, 0.05 * s, np.abs(x - toe[0]))))
    R["nail"] *= sm(-0.01 * s, 0.002 * s, -(y - np.where(y < 0, J["FrontToe.L"][1], J["HindToe.L"][1])) + 0.012 * s)
    d_n1, _ = _seg(P, J["Chest"], J["Head"])
    R["ruff"] = (1.0 - sm(0.10 * s, 0.17 * s, d_n1)) * (1.0 - R["face"]) * sm(J["Chest"][1] + 0.08 * s, J["Chest"][1] - 0.04 * s, y) \
        * sm(0.0, 1.0, st.ruff + 0.4)
    R["breeches"] = np.zeros(n)
    for side in ("L", "R"):
        d_b, _ = _seg(P, J[f"Thigh.{side}"] + np.array([0.0, 0.06, 0.0]) * s, J[f"HindCannon.{side}"] + np.array([0.0, 0.04, 0.04]) * s)
        R["breeches"] = np.maximum(R["breeches"], 1.0 - sm(0.04 * s, 0.07 * s, d_b))
    R["throat"] = (1.0 - sm(0.06 * s, 0.11 * s, _seg(P, J["Chin"], J["Humerus.L"] * np.array([0.0, 1.0, 1.0]))[0])) \
        * sm(0.0, 0.03 * s, -((P - J["Neck2"]) @ np.array([0.0, -0.4, 1.0])))
    R["thorn"] = np.zeros(n)
    if st.thorns > 0 and fine:
        # what stands proud of the hull: found from the distance to a thornless hull
        R["thorn"] = _proud(skel, st, P)
    return R


_PROUD_CACHE: Dict[int, sdf.Scene] = {}


def _proud(skel: QuadSkeleton, st: CanidStyle, P: np.ndarray) -> np.ndarray:
    key = id(skel)
    if key not in _PROUD_CACHE:
        bare = CanidStyle(**{**st.to_dict(), "thorns": 0.0, "fur": 0.0, "bark": 0.0})
        _PROUD_CACHE[key] = canid_scene(skel, bare)
    s = _s(skel)
    d = _PROUD_CACHE[key].near(0.03 * s).eval(P)
    return paint.smoothstep(0.006 * s, 0.016 * s, d)
