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


# A red hind's barrel, breast to buttock, in metres for a beast 1.15 m at the withers: (y, the top
# line, the under line, the half width). Deep at the girth behind the elbow, the belly round in the
# middle and tucked up hard at the flank; the back level, rising a little over the loin to the hips,
# the croup falling round to the tail.
BARREL = ((-0.585, 1.06, 0.90, 0.05), (-0.53, 1.13, 0.76, 0.10), (-0.42, 1.20, 0.665, 0.13),
          (-0.26, 1.215, 0.625, 0.148), (-0.08, 1.20, 0.635, 0.168), (0.08, 1.195, 0.665, 0.172),
          (0.22, 1.20, 0.74, 0.16), (0.36, 1.215, 0.85, 0.142), (0.52, 1.195, 0.89, 0.127),
          (0.645, 1.135, 0.915, 0.095), (0.73, 1.06, 0.95, 0.045))
# The neck, from its root in the breast to the throat under the poll: (joint, dy, dz, half width,
# half depth) in the skeleton's scale -- slender, deep only where it meets the chest.
NECK = (("Neck1", 0.11, -0.13, 0.125, 0.25), ("Neck1", 0.0, 0.0, 0.10, 0.17),
        ("Neck2", 0.02, -0.02, 0.083, 0.125), ("Head", 0.035, -0.075, 0.062, 0.085))


def horse_style(skel: Optional[QuadSkeleton] = None) -> hb.HorseStyle:
    """What the shared body generator is asked for: a deer's trunk, neck and legs, no horse's head."""
    k = (skel.props.withers / 1.15) if skel is not None else 1.0
    barrel = tuple((y * k, t * k, b * k, w * k) for y, t, b, w in BARREL)
    return hb.HorseStyle(girth=0.92, croup=0.6, crest=0.12, feather=0.0, mane="none", tail=0.0, hoof=0.62,
                         head="none", cloven=True, barrel=barrel, neck=NECK, ridges=0.0, points=0.35, soft=3.0, pillow=0.75)


def deer_scene(skel: QuadSkeleton, st: Optional[DeerStyle] = None) -> sdf.Scene:
    st = st or DeerStyle()
    sc = hb.horse_scene(skel, horse_style(skel))
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
    """A deer's head, a wedge in profile: deep behind, where the jaw's angle stands under the eye and
    the throat runs into the neck, tapering long and fine along a straight face to a small moist
    muzzle; broad across the forehead between wide-set eyes; big pointed ears held out and up,
    cupped forward."""
    J = skel.J
    s = _s(skel)
    poll, muzzle = J["Head"], J["Muzzle"]
    hd = muzzle - poll
    hl = float(np.linalg.norm(hd))
    hu = hd / hl
    dn = np.array([0.0, -hu[2], hu[1]])          # square to the face, toward the jaw
    hs = skel.props.head_size * s
    rot = _frame(hu, X)
    # the cranium, and the forehead broad between the eyes
    sc.union(sdf.ellipsoid(poll + hu * 0.14 * hl + dn * 0.035 * hs, np.array([0.074, 0.085, 0.10]) * hs, rot=rot),
             k=0.04 * s)
    # the face: straight on top, narrowing and thinning to the muzzle
    sc.union(sdf.elliptic_cone(poll + hu * 0.30 * hl + dn * 0.045 * hs, muzzle - hu * 0.11 * hl + dn * 0.012 * hs,
                               0.064 * hs, 0.068 * hs, 0.032 * hs, 0.036 * hs, X), k=0.05 * s)
    sc.union(sdf.ellipsoid(muzzle - hu * 0.07 * hl + dn * 0.012 * hs, np.array([0.036, 0.04, 0.062]) * hs, rot=rot),
             k=0.035 * s)
    # the cheeks over the jaw's angle, deep under the eyes, and the jaw's line forward to the chin
    angle = poll + hu * 0.24 * hl + dn * 0.135 * hs
    for sx in (1.0, -1.0):
        sc.union(sdf.ellipsoid(angle + X * sx * 0.036 * hs - hu * 0.01 * hl, np.array([0.036, 0.075, 0.105]) * hs,
                               rot=_frame(hu + 0.35 * dn, X)), k=0.05 * s)
        e = eye_centre(skel, sx)
        sc.union(sdf.ellipsoid(e + np.array([sx * -0.008, 0.0, 0.0]) * hs, np.array([0.02, 0.03, 0.022]) * hs,
                               rot=_frame(hu, X)), k=0.02 * s)
        sc.subtract(sdf.ellipsoid(muzzle - hu * 0.015 * hl + dn * 0.0 * hs + np.array([sx * 0.022, 0.0, 0.0]) * hs,
                                  np.array([0.009, 0.016, 0.012]) * hs), k=0.008 * s)
    sc.union(sdf.capsule(angle + dn * 0.04 * hs, J["Chin"] + dn * 0.005 * hs, 0.026 * hs), k=0.06 * s)
    for side, sx in (("L", 1.0), ("R", -1.0)):
        base, tip = ear_line(skel, sx)
        L = float(np.linalg.norm(tip - base))
        u = (tip - base) / L
        fr = _frame(u, Y)                    # thin front to back, broad across, long along
        # a pointed oval: the broad leaf, a narrower one carrying it on to the point, the root
        sc.union(sdf.ellipsoid(base + u * 0.45 * L, np.array([0.018 * hs, 0.062 * hs, L * 0.46]), rot=fr), k=0.012 * s)
        sc.union(sdf.ellipsoid(base + u * 0.72 * L, np.array([0.012 * hs, 0.034 * hs, L * 0.30]), rot=fr), k=0.02 * s)
        sc.union(sdf.capsule(base - u * 0.06 * L - X * sx * 0.01 * hs, base + u * 0.15 * L, 0.022 * hs), k=0.02 * s)
        # the hollow of the ear, open to the front
        sc.subtract(sdf.ellipsoid(base + u * 0.5 * L - Y * 0.014 * hs, np.array([0.011 * hs, 0.046 * hs, L * 0.38]), rot=fr),
                    k=0.005 * s)


def eye_centre(skel: QuadSkeleton, sx: float) -> np.ndarray:
    """A deer's eye: large, on the side of the head a third of the way down the face, level with
    the forehead's lower edge -- not up on the top line as a horse's is."""
    poll, muzzle = skel.J["Head"], skel.J["Muzzle"]
    hd = muzzle - poll
    hu = hd / float(np.linalg.norm(hd))
    dn = np.array([0.0, -hu[2], hu[1]])
    hs = skel.props.head_size * _s(skel)
    return poll + hd * 0.29 + dn * 0.05 * hs + np.array([sx * 0.07, 0.0, 0.0]) * hs


def ear_line(skel: QuadSkeleton, sx: float):
    """A deer's ear, base to tip: longer than a horse's and held out to the side and up."""
    side = "L" if sx > 0 else "R"
    b = skel.bones[f"Ear.{side}"]
    d = b.tail - b.head
    d = d / np.linalg.norm(d)
    out = d + np.array([sx * 0.65, 0.12, 0.0])
    out /= np.linalg.norm(out)
    hs = skel.props.head_size * _s(skel)
    base = b.head + np.array([sx * 0.012, 0.01, -0.045]) * hs
    return base, base + out * 0.26 * hs


def antler_scene(skel: QuadSkeleton, points: int = 12, seed: int = 4) -> sdf.Scene:
    """A royal stag's antlers (twelve points) in the skeleton's frame, standing on the poll."""
    J = skel.J
    s = _s(skel)
    rng = np.random.default_rng(seed)
    poll = J["Head"]
    hs = skel.props.head_size * s
    sc = sdf.Scene()
    hd = J["Muzzle"] - poll
    hu = hd / float(np.linalg.norm(hd))
    dn = np.array([0.0, -hu[2], hu[1]])
    for sx in (1.0, -1.0):
        # the pedicle: on the frontal bone's top, behind the eyes and in front of the ears
        ped = poll + hd * 0.13 - dn * 0.04 * hs + X * sx * 0.045 * hs
        # the beam: up, out and back from the burr in a long sweep, turning forward at the crown
        beam = [ped,
                ped + np.array([sx * 0.06, 0.05, 0.12]) * s,
                ped + np.array([sx * 0.18, 0.17, 0.34]) * s,
                ped + np.array([sx * 0.30, 0.28, 0.56]) * s,
                ped + np.array([sx * 0.37, 0.31, 0.74]) * s,
                ped + np.array([sx * 0.38, 0.25, 0.87]) * s]
        radii = [0.040 * s, 0.035 * s, 0.030 * s, 0.026 * s, 0.022 * s, 0.018 * s]
        sc.union(sdf.tube_path(beam, radii, density=4))
        # the burr at the pedicle: a rough collar
        sc.union(sdf.torus(ped + np.array([0.0, 0.0, 0.014]) * s, 0.034 * s, 0.011 * s, axis=Z), k=0.006 * s)
        sc.union(sdf.capsule(ped - np.array([0.0, 0.0, 0.03]) * s, ped + np.array([0.0, 0.0, 0.01]) * s, 0.03 * s),
                 k=0.01 * s)

        def tine(at: float, fwd: float, up: float, out: float, length: float, r: float, curl: float = 0.3):
            i = min(int(at * (len(beam) - 1)), len(beam) - 2)
            f = at * (len(beam) - 1) - i
            p = beam[i] * (1 - f) + beam[i + 1] * f
            d = np.array([sx * out, -fwd, up])
            d = d / np.linalg.norm(d)
            q = p + d * length * s
            # each tine curves up toward its point
            end = q + np.array([0.0, 0.0, curl]) * length * s
            sc.union(sdf.tube_path([p, (p + q) * 0.5 + np.array([0.0, 0.0, 0.03]) * length * s, end],
                                   [r * s, r * 0.72 * s, r * 0.3 * s], density=4), k=0.012 * s)
        tine(0.03, 1.0, 0.15, 0.10, 0.30, 0.024, 0.35)   # the brow tine, forward over the face
        tine(0.12, 1.0, 0.30, 0.20, 0.25, 0.021, 0.35)   # the bez, close over it
        tine(0.46, 1.0, 0.55, 0.15, 0.22, 0.019, 0.30)   # the trez, from the beam's middle
        # the crown: a cup of three points round the beam's end, forward, out and back
        top = len(beam) - 1
        for fwd, out, ln in ((0.9, 0.1, 0.23), (0.1, 0.9, 0.20), (-0.6, 0.35, 0.18)):
            p = beam[top - 1] * 0.25 + beam[top] * 0.75
            d = np.array([sx * out, -fwd, 1.1]) + rng.normal(0.0, 0.06, 3)
            d = d / np.linalg.norm(d)
            q = p + d * ln * s
            sc.union(sdf.tube_path([p, (p + q) * 0.5, q + np.array([0.0, 0.0, 0.03]) * s],
                                   [0.018 * s, 0.013 * s, 0.005 * s], density=4), k=0.014 * s)
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
    # the rump patch: round the tail and a hand down the backs of the thighs, pale, on the buttocks
    # only -- a red deer's is small and buff, not a roe's white target
    d = np.linalg.norm((P - (th + np.array([0.0, 0.02, -0.12]) * s)) / np.array([0.9, 0.55, 1.0]), axis=1)
    out["rump"] = sm((0.15 * s - d) / (0.025 * s)) * sm((P[:, 1] - (th[1] - 0.06 * s)) / (0.03 * s))
    # the belly: pale along the barrel's under line only, as the loft draws it, and up between the
    # legs; not the flank
    k = skel.props.withers / 1.15
    by = np.array([b[0] for b in BARREL]) * k
    bb = np.array([b[2] for b in BARREL]) * k
    under = np.interp(P[:, 1], by, bb)
    out["belly"] = sm((under + 0.11 * k - z) / (0.06 * k)) * sm((z - J["FrontCannon.L"][2]) / (0.1 * s))
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
        e = eye_centre(skel, sx)
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
