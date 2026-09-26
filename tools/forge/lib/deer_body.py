"""The red deer on WM_Quadruped_v1: the hind and the stag share one body; the stag's antlers are an
attachment of their own (pure numpy SDF, like horse_body.py and sheep_body.py).

The trunk, the quarters and the shoulders are the horse's drawn shapes at a deer's proportions
(a slimmer barrel tucked up hard at the flank, lighter quarters, long fine legs with split hooves);
the head, the ears and the scut are a deer's own. A red deer stands 1.15 m at the shoulder and
1.9 m from nose to tail, and carries its neck high.

`antler_scene` is a stag's pair of antlers in the head's frame at the poll: each a beam sweeping
back and up from the pedicle, with a brow, a bez and a trez tine forward and a cup of three
points at the crown. It is built alone and hung on Socket.Head in the game.
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
Z = np.array([0.0, 0.0, 1.0])

# A Briarwold red deer: shoulder 1.15 m, nose to tail about 1.9 m, the neck carried high.
RED = QuadProportions(withers=1.15, body_length=1.2, leg_length=1.12, neck_length=1.12, head_size=1.0,
                      bulk=0.74, width=0.86, tail_length=0.30, cannon=1.22, neck_raise=16.0)


@dataclass
class DeerStyle:
    coat: str = "red"            # red (summer) | grey (the grey hart: desaturated, pale)
    ruff: float = 0.0            # a stag's rutting mane on the neck's underside (0 for a hind)
    seed: int = 11

    def to_dict(self) -> dict:
        return asdict(self)


def _s(skel: QuadSkeleton) -> float:
    return skel.props.withers / DEFAULT_WITHERS


def horse_style() -> hb.HorseStyle:
    """What the shared body generator is asked for: a deer's trunk and legs, no horse's head."""
    return hb.HorseStyle(girth=0.92, croup=0.82, crest=0.25, feather=0.0, mane="none", tail=0.0, hoof=0.62,
                         head="none", cloven=True)


def deer_scene(skel: QuadSkeleton, st: Optional[DeerStyle] = None) -> sdf.Scene:
    st = st or DeerStyle()
    sc = hb.horse_scene(skel, horse_style())
    # horse_scene ends with the ground's plane; the head and the scut go in before it
    ground = sc.prims.pop()
    J = skel.J
    s = _s(skel)
    _head(sc, skel)
    # the scut: short, flat, held down over the rump patch
    t1, t2, t3 = J["Tail1"], J["Tail2"], J["Tail3"]
    sc.union(sdf.elliptic_cone(t1 + np.array([0.0, -0.02, 0.0]) * s, t3 + np.array([0.0, 0.01, 0.0]) * s,
                               0.05 * s, 0.03 * s, 0.035 * s, 0.018 * s, X), k=0.03 * s)
    if st.ruff > 0:
        # the rutting ruff: long coarse hair under the throat and down the neck's front
        n1, n2, jaw = J["Neck1"], J["Neck2"], J["Jaw"]
        pts = [jaw + np.array([0.0, 0.03, -0.06]) * s, n2 + np.array([0.0, -0.06, -0.10]) * s,
               n1 + np.array([0.0, -0.10, -0.12]) * s]
        sc.union(sdf.tube_path(pts, [0.05 * s * st.ruff, 0.085 * s * st.ruff, 0.07 * s * st.ruff]), k=0.05 * s)
    sc.prims.append(ground)
    return sc


def _frame(along: np.ndarray, side: np.ndarray) -> np.ndarray:
    """Columns: `side` made square to `along`, the third axis, `along` -- for a rotated ellipsoid."""
    a = along / np.linalg.norm(along)
    w = side - a * float(side @ a)
    w /= np.linalg.norm(w)
    return np.stack([w, np.cross(a, w), a], axis=1)


def _head(sc: sdf.Scene, skel: QuadSkeleton) -> None:
    """A deer's head: a broad forehead between wide-set eyes, tapering long and fine to a small
    moist muzzle; a clean jaw; big oval ears held out and up, cupped forward."""
    J = skel.J
    s = _s(skel)
    poll, muzzle = J["Head"], J["Muzzle"]
    hd = muzzle - poll
    hl = float(np.linalg.norm(hd))
    hu = hd / hl
    hs = skel.props.head_size * s
    sc.union(sdf.ellipsoid(poll + hu * 0.12 * hl + np.array([0.0, 0.0, -0.01]) * hs, np.array([0.085, 0.11, 0.095]) * hs),
             k=0.04 * s)
    sc.union(sdf.elliptic_cone(poll + hu * 0.20 * hl, muzzle - hu * 0.10 * hl, 0.074 * hs, 0.085 * hs, 0.036 * hs, 0.05 * hs, X),
             k=0.04 * s)
    sc.union(sdf.ellipsoid(muzzle - hu * 0.05 * hl, np.array([0.042, 0.05, 0.048]) * hs), k=0.03 * s)
    jaw, chin = J["Jaw"], J["Chin"]
    for sx in (1.0, -1.0):
        sc.union(sdf.ellipsoid(jaw + np.array([sx * 0.045, -0.02, 0.0]) * hs, np.array([0.045, 0.09, 0.08]) * hs), k=0.04 * s)
        e = hb.eye_centre(skel, sx)
        sc.union(sdf.sphere(e + np.array([sx * -0.004, 0.0, 0.008]) * hs, 0.03 * hs), k=0.015 * s)
        sc.subtract(sdf.ellipsoid(muzzle + hu * 0.01 * hl + np.array([sx * 0.025, 0.0, 0.02]) * hs,
                                  np.array([0.011, 0.018, 0.013]) * hs), k=0.008 * s)
    sc.union(sdf.capsule(jaw + np.array([0.0, 0.0, -0.045]) * hs, chin + np.array([0.0, 0.0, 0.015]) * hs, 0.028 * hs),
             k=0.04 * s)
    for side, sx in (("L", 1.0), ("R", -1.0)):
        base, tip = ear_line(skel, sx)
        mid = (base + tip) * 0.5
        L = float(np.linalg.norm(tip - base))
        rot = _frame(tip - base, Y)      # thin front to back, broad across, long along
        sc.union(sdf.ellipsoid(mid, np.array([0.02 * hs, 0.07 * hs, L * 0.55]), rot=rot), k=0.015 * s)
        sc.subtract(sdf.ellipsoid(mid - Y * 0.016 * hs, np.array([0.01 * hs, 0.052 * hs, L * 0.45]), rot=rot), k=0.005 * s)


def ear_line(skel: QuadSkeleton, sx: float):
    """A deer's ear, base to tip: longer than a horse's and held out to the side and up."""
    side = "L" if sx > 0 else "R"
    b = skel.bones[f"Ear.{side}"]
    d = b.tail - b.head
    d = d / np.linalg.norm(d)
    out = d + np.array([sx * 0.9, 0.15, 0.0])
    out /= np.linalg.norm(out)
    hs = skel.props.head_size * _s(skel)
    return b.head, b.head + out * 0.26 * hs


def antler_scene(skel: QuadSkeleton, points: int = 12, seed: int = 4) -> sdf.Scene:
    """A royal stag's antlers (twelve points) in the skeleton's frame, standing on the poll."""
    J = skel.J
    s = _s(skel)
    rng = np.random.default_rng(seed)
    poll = J["Head"]
    hs = skel.props.head_size * s
    sc = sdf.Scene()
    for sx in (1.0, -1.0):
        ped = poll + np.array([sx * 0.055, -0.025, 0.05]) * hs
        # the beam: out, back and up, curving in at the top
        beam = [ped,
                ped + np.array([sx * 0.08, 0.04, 0.14]) * s,
                ped + np.array([sx * 0.22, 0.14, 0.34]) * s,
                ped + np.array([sx * 0.31, 0.25, 0.52]) * s,
                ped + np.array([sx * 0.27, 0.33, 0.68]) * s]
        radii = [0.026 * s, 0.022 * s, 0.018 * s, 0.015 * s, 0.012 * s]
        sc.union(sdf.tube_path(beam, radii, density=4))
        # the burr at the pedicle
        sc.union(sdf.torus(ped + np.array([0.0, 0.0, 0.012]) * s, 0.026 * s, 0.008 * s, axis=Z), k=0.006 * s)

        def tine(at: float, fwd: float, up: float, out: float, length: float, r: float):
            i = min(int(at * (len(beam) - 1)), len(beam) - 2)
            f = at * (len(beam) - 1) - i
            p = beam[i] * (1 - f) + beam[i + 1] * f
            d = np.array([sx * out, -fwd, up])
            d = d / np.linalg.norm(d)
            q = p + d * length * s
            bend = q + np.array([0.0, 0.0, 0.25]) * length * s + np.array([sx * 0.02, 0.0, 0.0]) * s
            sc.union(sdf.tube_path([p, (p + q) * 0.5 + np.array([0.0, 0.0, 0.02]) * s, bend],
                                   [r * s, r * 0.75 * s, r * 0.25 * s], density=4), k=0.008 * s)
        tine(0.08, 1.0, 0.30, 0.15, 0.27, 0.014)    # the brow tine, forward over the face
        tine(0.18, 1.0, 0.45, 0.25, 0.22, 0.012)    # the bez
        tine(0.47, 0.9, 0.70, 0.30, 0.20, 0.011)    # the trez
        # the crown: a cup of three points at the top
        for k in range(3):
            a = (k - 1) * 0.7 + rng.normal(0.0, 0.08)
            d = (math.sin(a) * 0.6, math.cos(a) * 0.5)
            tine(0.86 + 0.04 * k, d[1], 1.0, 0.3 + d[0], 0.15 + 0.02 * k, 0.010)
    return sc


def regions(skel: QuadSkeleton, P: np.ndarray, st: Optional[DeerStyle] = None) -> Dict[str, np.ndarray]:
    """Soft masks (0..1): `rump` (the pale caudal patch), `belly`, `back` (the darker saddle),
    `face`, `muzzle`, `eye`, `gland` (the dark preorbital gland), `ear`, `ear_in`, `hoof`, `legs`,
    `ruff`, `throat` (the pale chin and throat)."""
    st = st or DeerStyle()
    J = skel.J
    s = _s(skel)

    def sm(x):
        x = np.clip(x, 0.0, 1.0)
        return x * x * (3 - 2 * x)
    z = P[:, 2]
    out: Dict[str, np.ndarray] = {}
    th = J["TailHead"]
    # the rump patch: round the tail and down the backs of the thighs, pale
    d = np.linalg.norm((P - (th + np.array([0.0, 0.02, -0.14]) * s)) / np.array([1.3, 0.55, 1.0]), axis=1)
    out["rump"] = sm((0.19 * s - d) / (0.03 * s)) * sm((P[:, 1] - (th[1] - 0.10 * s)) / (0.04 * s))
    belly_z = J["Spine2"][2] - 0.45 * s
    out["belly"] = sm((belly_z - z) / (0.10 * s)) * sm((z - J["FrontCannon.L"][2]) / (0.1 * s))
    out["back"] = sm((z - (J["Spine2"][2] - 0.12 * s)) / (0.12 * s)) * sm((P[:, 1] - (J["Neck1"][1])) / (0.1 * s))
    poll, muzzle = J["Head"], J["Muzzle"]
    hd = muzzle - poll
    hl = float(np.linalg.norm(hd))
    u = ((P - poll) @ hd) / float(hd @ hd)
    off = np.linalg.norm(P - (poll + np.clip(u, 0, 1)[:, None] * hd), axis=1)
    out["face"] = sm((u + 0.05) / 0.15) * sm((0.32 * hl - off) / (0.05 * hl))
    out["muzzle"] = sm((u - 0.86) / 0.06) * out["face"]
    ey = np.zeros(len(P))
    gl = np.zeros(len(P))
    for sx in (1.0, -1.0):
        e = hb.eye_centre(skel, sx)
        ey = np.maximum(ey, sm((0.022 * s - np.linalg.norm(P - e, axis=1)) / (0.005 * s)))
        g = e + hd / hl * 0.06 + np.array([0.0, 0.0, -0.03]) * s
        gl = np.maximum(gl, sm((0.02 * s - np.linalg.norm(P - g, axis=1)) / (0.008 * s)))
    out["eye"] = ey
    out["gland"] = gl * (1.0 - ey)
    ear = np.zeros(len(P))
    ear_in = np.zeros(len(P))
    for sx in (1.0, -1.0):
        a, b = ear_line(skel, sx)
        ab = b - a
        v = np.clip(((P - a) @ ab) / float(ab @ ab), 0.0, 1.0)
        dd = np.linalg.norm(P - (a + v[:, None] * ab), axis=1)
        m = sm((0.06 * s - dd) / (0.015 * s)) * sm(v / 0.1)
        ear = np.maximum(ear, m)
        ear_in = np.maximum(ear_in, m * sm((a[1] - P[:, 1]) / (0.004 * s)))
    out["ear"] = ear
    out["ear_in"] = ear_in
    cor_z = J["FrontHoof.L"][2] + 0.004 * s
    out["hoof"] = sm((cor_z - z) / (0.008 * s))
    out["legs"] = sm((J["FrontCannon.L"][2] + 0.10 * s - z) / (0.2 * s))
    jaw = J["Jaw"]
    out["throat"] = sm((0.10 * s - np.linalg.norm(P - (jaw + np.array([0.0, 0.03, -0.07]) * s), axis=1)) / (0.04 * s))
    n2 = J["Neck2"]
    out["ruff"] = (sm((0.14 * s - np.linalg.norm(P - (n2 + np.array([0.0, -0.06, -0.10]) * s), axis=1)) / (0.05 * s))
                   * (1.0 if st.ruff > 0 else 0.0))
    return out
