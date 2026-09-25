"""The Vale's ewe on WM_Quadruped_v1: a fleece with a closed belly, legs that grow out of it, a
face and ears (pure numpy SDF, like horse_body.py).

The fleece is one rounded mass from the breast to the dock, lumped with locks, hanging to the
knees and hocks and closed underneath: the old prop's sphere on four sticks left a gap under the
belly the eye read as the sheep being opened. The legs are the horse's legs at a sheep's size,
starting inside the fleece. The head is a sheep's: a short, deep face, a Roman nose, ears held
out sideways, a poll of wool.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict
from typing import Dict, Optional

import numpy as np

from . import sdf
from .quadruped import QuadSkeleton, QuadProportions, DEFAULT_WITHERS
from . import horse_body as hb

X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])

# A Hearthvale ewe: the spine line at 0.66 m, the fleece's top about 0.80.
EWE = QuadProportions(withers=0.64, body_length=1.08, leg_length=0.86, neck_length=0.72, head_size=1.05,
                      bulk=1.05, width=1.30, tail_length=0.55, cannon=0.95)


@dataclass
class SheepStyle:
    fleece: float = 1.0        # how deep the wool stands off the body (a shorn ewe is ~0.3)
    face: str = "dark"         # dark | white
    seed: int = 3

    def to_dict(self) -> dict:
        return asdict(self)


def _s(skel: QuadSkeleton) -> float:
    return skel.props.withers / DEFAULT_WITHERS


def sheep_scene(skel: QuadSkeleton, st: Optional[SheepStyle] = None) -> sdf.Scene:
    st = st or SheepStyle()
    J = skel.J
    s = _s(skel)
    f = st.fleece
    sc = sdf.Scene()
    rng = np.random.default_rng(st.seed)
    chest, spine2, hips = J["Chest"], J["Spine2"], J["Hips"]
    tail = J["Tail1"]
    # the fleece: breast to britch, as deep as it is wide, its belly line at the elbows
    front = J["Neck1"] + np.array([0.0, 0.02, -0.08]) * s
    elbow_z = J["Forearm.L"][2]
    belly_z = elbow_z + 0.03 - 0.03 * f
    top_z = spine2[2] + 0.10 * f
    mid_z = 0.5 * (belly_z + top_z)
    half_h = 0.5 * (top_z - belly_z)
    stations = [
        (np.array([0.0, front[1] - 0.02 * s, mid_z + 0.10 * s]), 0.20 * s * f, 0.26 * s * f),
        (np.array([0.0, chest[1], mid_z + 0.02 * s]), 0.19 * f, half_h * 0.97),
        (np.array([0.0, spine2[1], mid_z]), 0.215 * f, half_h * 1.03),
        (np.array([0.0, 0.5 * (spine2[1] + hips[1]), mid_z]), 0.215 * f, half_h * 1.02),
        (np.array([0.0, hips[1] + 0.03, mid_z + 0.01]), 0.19 * f, half_h * 0.93),
        (np.array([0.0, tail[1] + 0.01, mid_z + 0.03]), 0.11 * f, half_h * 0.6),
    ]
    sc.union(sdf.sweep(stations, X, axis=Y, density=4, max_spheres=120), k=0.0)
    # the fleece hangs over the tops of the legs: breeches behind, and the forearms' wool
    for side, sx in (("L", 1.0), ("R", -1.0)):
        th = J["Gaskin.%s" % side]
        sc.union(sdf.ellipsoid(th + np.array([sx * 0.02, 0.06, 0.06]) * s, np.array([0.12, 0.16, 0.22]) * s * f), k=0.10 * s)
        fa = J["Forearm.%s" % side]
        sc.union(sdf.ellipsoid(fa + np.array([0.0, 0.0, 0.02]) * s, np.array([0.10, 0.12, 0.16]) * s * f), k=0.10 * s)
    # locks: the surface lumped, so the fleece reads as wool and not as a balloon: small blobs sunk
    # most of the way into it, standing a centimetre or two proud
    lo, hi = sc.bounds(0.0)
    core = sdf.Scene()
    for p in sc.prims:
        core.prims.append(p)
    pts = rng.uniform(lo, hi, size=(4000, 3))
    d = core.eval(pts)
    near = pts[np.abs(d) < 0.006][:260]
    if len(near):
        g = np.stack([core.eval(near + e) - core.eval(near - e) for e in np.eye(3) * 0.004], axis=1)
        g /= np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)
        for p, nrm in zip(near, g):
            r = (0.028 + 0.018 * rng.random()) * f
            sc.union(sdf.sphere(p - nrm * r * 0.55, r), k=0.02)
    # the neck: short and thick with wool, into the head
    n1, n2, poll = J["Neck1"], J["Neck2"], J["Head"]
    sc.union(sdf.sweep([(n1 + np.array([0.0, 0.03, 0.0]), 0.12 * f, 0.15 * f),
                        (n2, 0.09 * f, 0.11 * f),
                        (poll + np.array([0.0, 0.02, -0.04]), 0.055, 0.06)], X, density=4), k=0.06)
    # the head: a deep face with a Roman nose, the muzzle blunt; sized off its own length
    muzzle = J["Muzzle"]
    hd = muzzle - poll
    hl = float(np.linalg.norm(hd))
    sc.union(sdf.ellipsoid(poll + hd * 0.2, np.array([0.25, 0.28, 0.25]) * hl), k=0.03)
    sc.union(sdf.elliptic_cone(poll + hd * 0.3, muzzle - hd * 0.1, 0.19 * hl, 0.23 * hl, 0.12 * hl, 0.16 * hl, X), k=0.03)
    sc.union(sdf.ellipsoid(muzzle - hd * 0.08, np.array([0.13, 0.15, 0.13]) * hl), k=0.02)
    for sx in (1.0, -1.0):
        sc.subtract(sdf.ellipsoid(muzzle - hd * 0.02 + np.array([sx * 0.05, -0.03, 0.02]) * hl, np.array([0.025, 0.03, 0.025]) * hl), k=0.01)
        e = sheep_eye(skel, sx)
        sc.union(sdf.sphere(e, 0.05 * hl), k=0.012)
    # the poll's wool cap
    sc.union(sdf.ellipsoid(poll + np.array([0.0, 0.01, 0.015]), np.array([0.2, 0.2, 0.15]) * hl * f), k=0.02)
    # the ears: out sideways and a little down, flat leaves
    for side, sx in (("L", 1.0), ("R", -1.0)):
        base = poll + hd * 0.14 + np.array([sx * 0.17, 0.0, 0.0]) * hl
        tip = base + np.array([sx * 0.46, 0.06, -0.12]) * hl
        sc.union(sdf.elliptic_cone(base, tip, 0.06 * hl, 0.12 * hl, 0.02 * hl, 0.05 * hl, np.array([0.0, 1.0, 0.0])), k=0.01)
    # the legs, slim, out of the wool
    st_h = hb.HorseStyle(feather=0.0, hoof=0.9)
    for side, sx in (("L", 1.0), ("R", -1.0)):
        hb._leg(sc, skel, side, sx, fore=True, st=st_h)
        hb._leg(sc, skel, side, sx, fore=False, st=st_h)
    # the tail: a short woolly dock
    sc.union(sdf.round_cone(tail, J["Tail3"], 0.045 * f, 0.03 * f), k=0.03)
    sc.intersect(sdf.plane(np.zeros(3), np.array([0.0, 0.0, -1.0])))
    return sc


def sheep_eye(skel: QuadSkeleton, sx: float) -> np.ndarray:
    poll, muzzle = skel.J["Head"], skel.J["Muzzle"]
    hl = float(np.linalg.norm(muzzle - poll))
    return poll + (muzzle - poll) * 0.32 + np.array([sx * 0.19, 0.0, 0.07]) * hl


def regions(skel: QuadSkeleton, P: np.ndarray, st: Optional[SheepStyle] = None) -> Dict[str, np.ndarray]:
    """Soft masks: `wool` (the fleece, the poll and the dock), `skin` (face, ears, legs),
    `hoof`, `eye`, `nose`."""
    J = skel.J
    s = _s(skel)

    def sm(x):
        x = np.clip(x, 0.0, 1.0)
        return x * x * (3 - 2 * x)
    z = P[:, 2]
    out: Dict[str, np.ndarray] = {}
    cor_z = J["FrontHoof.L"][2] + 0.004 * s
    out["hoof"] = sm((cor_z - z) / (0.008 * s))
    # the legs are bare below the wool: below the elbows ahead, below the stifle's wool behind
    leg_bare = sm((J["Forearm.L"][2] - 0.10 * s - z) / (0.04 * s))
    # the face: ahead of the poll's wool, on the head
    poll, muzzle = J["Head"], J["Muzzle"]
    hd = muzzle - poll
    u = ((P - poll) @ hd) / float(hd @ hd)
    # the face: near the head's own axis, from the eyes' line to past the muzzle's tip
    hl = float(np.linalg.norm(hd))
    uc = np.clip(u, 0.0, 1.1)
    d_axis = np.linalg.norm(P - (poll + uc[:, None] * hd), axis=1)
    face = sm((u - 0.12) / 0.10) * sm((0.34 * hl - d_axis) / (0.05 * hl))
    ear = np.zeros(len(P))
    for sx in (1.0, -1.0):
        base = poll + hd * 0.12 + np.array([sx * 0.06, 0.0, 0.0]) * skel.props.head_size * s
        ear = np.maximum(ear, sm((0.06 * s * skel.props.head_size - np.linalg.norm(P - base - np.array([sx * 0.06, 0.0, 0.0]) * s * skel.props.head_size, axis=1)) / (0.02 * s)))
    out["skin"] = np.clip(np.maximum(np.maximum(leg_bare, face), ear), 0, 1) * (1.0 - out["hoof"])
    ey = np.zeros(len(P))
    for sx in (1.0, -1.0):
        ey = np.maximum(ey, sm((0.021 * s * skel.props.head_size - np.linalg.norm(P - sheep_eye(skel, sx), axis=1)) / (0.004 * s)))
    out["eye"] = ey
    out["nose"] = sm((0.035 * s * skel.props.head_size - np.linalg.norm(P - (muzzle - hd * 0.02), axis=1)) / (0.01 * s))
    out["wool"] = np.clip(1.0 - out["skin"] - out["hoof"], 0, 1)
    return out
