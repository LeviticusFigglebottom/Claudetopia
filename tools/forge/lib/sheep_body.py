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
        # the wool comes down over the tops of the legs: a cuff round each forearm and gaskin,
        # ending in a ragged edge a hand above the knee and the hock
        for top, bot in ((fa, J["FrontCannon.%s" % side]), (th, J["HindCannon.%s" % side])):
            end = bot + (top - bot) * 0.45
            sc.union(sdf.round_cone(top + np.array([0.0, 0.0, 0.03]), end, 0.05 * f, 0.034 * f), k=0.03)
    # locks: the surface matted into clumps, so the fleece reads as wool and not as a balloon or
    # a heap of bubbles: many small clumps of three sizes, each an ellipsoid lying along the
    # surface and hanging a little down it, sunk most of the way in; the smallest stand proudest,
    # which crimps the silhouette at the edges
    lo, hi = sc.bounds(0.0)
    core = sdf.Scene()
    for p in sc.prims:
        core.prims.append(p)
    pts = rng.uniform(lo, hi, size=(60000, 3))
    d = core.eval(pts)
    near = pts[np.abs(d) < 0.004]
    # thin them to an even scatter: no two clump centres closer than 2.2 cm
    keep = []
    for p in near:
        if all(np.linalg.norm(p - q) > 0.022 for q in keep[-400:]):
            keep.append(p)
        if len(keep) >= 900:
            break
    near = np.array(keep)
    if len(near):
        g = np.stack([core.eval(near + e) - core.eval(near - e) for e in np.eye(3) * 0.004], axis=1)
        g /= np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)
        for p, nrm in zip(near, g):
            size = rng.choice([0.6, 0.8, 1.0], p=[0.35, 0.4, 0.25])
            r = (0.020 + 0.008 * rng.random()) * f * size
            # along the surface, mostly downhill: a lock hangs
            down = np.array([0.0, 0.0, -1.0])
            down = down - nrm * float(down @ nrm)
            if np.linalg.norm(down) < 1e-3:
                down = np.cross(nrm, X)
            down /= np.linalg.norm(down)
            ang = rng.normal(0.0, 0.6)
            side = np.cross(nrm, down)
            along = down * math.cos(ang) + side * math.sin(ang)
            across = np.cross(nrm, along)
            rot = np.stack([along, across, nrm], axis=1)
            radii = np.array([r * (1.3 + 0.5 * rng.random()), r * (0.8 + 0.3 * rng.random()), r * 0.8])
            sunk = 0.45 + 0.2 * (size - 0.6)
            sc.union(sdf.ellipsoid(p - nrm * r * sunk, radii, rot=rot), k=0.008)
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
        sc.union(sdf.sphere(e, EYE_R * hl), k=0.006)
        # the lids: a ridge round the eye, the line that makes it read at a pen's distance
        out = e - (poll + hd * 0.32)
        out[1] = 0.0
        out /= max(np.linalg.norm(out), 1e-9)
        sc.union(sdf.torus(e - out * 0.012 * hl, EYE_R * hl * 1.05, 0.012 * hl, axis=out), k=0.006)
    # the poll's wool cap
    sc.union(sdf.ellipsoid(poll + np.array([0.0, 0.01, 0.015]), np.array([0.2, 0.2, 0.15]) * hl * f), k=0.02)
    # the ears: out sideways and a little down, flat leaves
    for side, sx in (("L", 1.0), ("R", -1.0)):
        base, tip = ear_line(skel, sx)
        sc.union(sdf.elliptic_cone(base, tip, 0.06 * hl, 0.12 * hl, 0.02 * hl, 0.05 * hl, np.array([0.0, 1.0, 0.0])), k=0.01)
    # the legs: slim, bony, out of the wool -- a sheep's, not a horse's at a sheep's size
    for side, sx in (("L", 1.0), ("R", -1.0)):
        _sheep_leg(sc, skel, side, sx, fore=True)
        _sheep_leg(sc, skel, side, sx, fore=False)
    # the tail: a short woolly dock
    sc.union(sdf.round_cone(tail, J["Tail3"], 0.045 * f, 0.03 * f), k=0.03)
    sc.intersect(sdf.plane(np.zeros(3), np.array([0.0, 0.0, -1.0])))
    return sc


def _sheep_leg(sc: sdf.Scene, skel: QuadSkeleton, side: str, sx: float, fore: bool) -> None:
    """A ewe's leg from inside the wool to the ground: a muscled top tapering to a knobbly knee
    (or the hock's point behind), a thin cannon, a small fetlock, a short pastern and a neat
    cloven hoof. Radii are in metres at the ewe's size; the joints are knobs a little wider than
    the bone either side, blended tight so they read as joints and not as breaks."""
    J = skel.J
    s = _s(skel)
    q = s / 0.4267                     # 1.0 at the ewe's withers
    if fore:
        top, knee, fet, cor, toe = (J[f"Forearm.{side}"], J[f"FrontCannon.{side}"], J[f"FrontPastern.{side}"],
                                    J[f"FrontHoof.{side}"], J[f"FrontToe.{side}"])
        # the forearm: muscle in front, thinning to the knee
        sc.union(sdf.elliptic_cone(top + np.array([0.0, -0.004, 0.03]) * q, knee + np.array([0.0, 0.0, 0.012]) * q,
                                   0.024 * q, 0.030 * q, 0.014 * q, 0.016 * q, X), k=0.012 * q)
        # the knee: a flat bony knob, a touch proud in front
        sc.union(sdf.ellipsoid(knee + np.array([0.0, -0.003, 0.0]) * q, np.array([0.017, 0.019, 0.022]) * q), k=0.006 * q)
    else:
        stifle, hock, fet, cor, toe = (J[f"Gaskin.{side}"], J[f"HindCannon.{side}"], J[f"HindPastern.{side}"],
                                       J[f"HindHoof.{side}"], J[f"HindToe.{side}"])
        # the gaskin: muscle behind the shin, lean to the hock
        sc.union(sdf.elliptic_cone(stifle + np.array([0.0, 0.01, 0.0]) * q, hock + np.array([0.0, 0.0, 0.01]) * q,
                                   0.026 * q, 0.034 * q, 0.013 * q, 0.017 * q, X), k=0.012 * q)
        # the hock and its point behind
        sc.union(sdf.ellipsoid(hock, np.array([0.016, 0.02, 0.022]) * q), k=0.006 * q)
        sc.union(sdf.round_cone(hock + np.array([0.0, 0.006, 0.006]) * q, hock + np.array([0.0, 0.026, 0.02]) * q,
                                0.009 * q, 0.008 * q), k=0.006 * q)
        knee = hock
    # the cannon: thin, flat side to side
    sc.union(sdf.elliptic_cone(knee + np.array([0.0, 0.0, -0.012]) * q, fet + np.array([0.0, 0.0, 0.008]) * q,
                               0.011 * q, 0.013 * q, 0.010 * q, 0.012 * q, X), k=0.006 * q)
    # the fetlock, a small knob, and the short pastern
    sc.union(sdf.ellipsoid(fet + np.array([0.0, 0.003, 0.0]) * q, np.array([0.013, 0.015, 0.014]) * q), k=0.005 * q)
    sc.union(sdf.round_cone(fet, cor, 0.010 * q, 0.011 * q), k=0.005 * q)
    # the hoof: two claws, narrow and pointed, with the cleft between
    base = np.array([cor[0], toe[1] * 0.35 + cor[1] * 0.65, 0.0])
    sc.union(sdf.elliptic_cone(cor + np.array([0.0, 0.0, 0.004]) * q, base + np.array([0.0, 0.0, 0.003]) * q,
                               0.013 * q, 0.015 * q, 0.017 * q, 0.024 * q, X), k=0.004 * q)
    sc.subtract(sdf.box(np.array([cor[0], toe[1] + 0.006 * q, 0.012 * q]), np.array([0.0018, 0.014, 0.02]) * q), k=0.002 * q)


def ear_line(skel: QuadSkeleton, sx: float):
    """The ear's base and tip: out sideways from the poll and a little down."""
    poll, muzzle = skel.J["Head"], skel.J["Muzzle"]
    hd = muzzle - poll
    hl = float(np.linalg.norm(hd))
    base = poll + hd * 0.14 + np.array([sx * 0.17, 0.0, 0.0]) * hl
    return base, base + np.array([sx * 0.46, 0.06, -0.12]) * hl


EYE_R = 0.068     # the eye's radius, in head lengths


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
    # the legs are bare below the wool's cuffs (a little under halfway from the knee to the elbow)
    cuff_z = J["FrontCannon.L"][2] + (J["Forearm.L"][2] - J["FrontCannon.L"][2]) * 0.45 - 0.03
    leg_bare = sm((cuff_z - z) / (0.012 * s))
    # the face: ahead of the poll's wool, on the head
    poll, muzzle = J["Head"], J["Muzzle"]
    hd = muzzle - poll
    u = ((P - poll) @ hd) / float(hd @ hd)
    # the face: near the head's own axis, from the eyes' line to past the muzzle's tip
    hl = float(np.linalg.norm(hd))
    uc = np.clip(u, 0.0, 1.1)
    d_axis = np.linalg.norm(P - (poll + uc[:, None] * hd), axis=1)
    face = sm((u - 0.12) / 0.10) * sm((0.34 * hl - d_axis) / (0.05 * hl))
    # the ears, along the same leaves sheep_scene draws
    ear = np.zeros(len(P))
    for sx in (1.0, -1.0):
        a, b = ear_line(skel, sx)
        ab = b - a
        v = np.clip(((P - a) @ ab) / float(ab @ ab), 0.0, 1.0)
        d = np.linalg.norm(P - (a + v[:, None] * ab), axis=1)
        ear = np.maximum(ear, sm((0.15 * hl - d) / (0.03 * hl)))
    out["skin"] = np.clip(np.maximum(np.maximum(leg_bare, face), ear), 0, 1) * (1.0 - out["hoof"])
    # the eye: a glossy dark ball with an amber iris round a long pupil, and the lid round it
    ey = np.zeros(len(P))
    iris = np.zeros(len(P))
    lid = np.zeros(len(P))
    for sx in (1.0, -1.0):
        e = sheep_eye(skel, sx)
        q = P - e
        dist = np.linalg.norm(q, axis=1)
        r = EYE_R * hl
        on = sm((r * 1.08 - dist) / (0.004 * s))
        # where on the ball: the iris is a ring round the outward pole, the pupil a bar across it
        outward = np.array([sx, 0.0, 0.0])
        cos_t = (q @ outward) / np.maximum(dist, 1e-9)
        ring = sm((cos_t - 0.55) / 0.08)
        pupil = sm((0.28 * r - np.abs(q[:, 2])) / (0.08 * r)) * sm((cos_t - 0.80) / 0.05)
        ey = np.maximum(ey, on)
        iris = np.maximum(iris, on * ring * (1.0 - pupil))
        lid = np.maximum(lid, sm((dist - r * 1.02) / (0.004 * s)) * sm((r * 1.45 - dist) / (0.006 * s)))
    out["eye"] = ey
    out["iris"] = iris
    out["lid"] = lid * (1.0 - ey)
    out["nose"] = sm((0.035 * s * skel.props.head_size - np.linalg.norm(P - (muzzle - hd * 0.02), axis=1)) / (0.01 * s))
    out["wool"] = np.clip(1.0 - out["skin"] - out["hoof"], 0, 1)
    return out
